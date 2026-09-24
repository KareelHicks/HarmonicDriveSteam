extends Node
class_name MultiplayerManager

const RelayConfig = preload("res://scripts/net/RelayConfig.gd")
const RelayAPIClient = preload("res://scripts/net/RelayAPIClient.gd")
const MatchRealtimeClient = preload("res://scripts/net/MatchRealtimeClient.gd")
const GameModeConfig = preload("res://scripts/gameplay/GameModeConfig.gd")
const SteamMultiplayerInvite = preload("res://scripts/net/SteamMultiplayerInvite.gd")
const FINALIZE_RETRY_LIMIT := 4
const FINALIZE_RETRY_DELAY_SECONDS := 1.5

signal auth_state_changed(identity: Dictionary)
signal players_changed(players: Array)
signal lobby_updated(lobby: Dictionary)
signal matchmaking_updated(payload: Dictionary)
signal start_time_received(start_time: float)
signal hit_event_received(event: Dictionary)
signal session_state_changed(active: bool, is_host: bool)
signal selection_changed(selection: Dictionary)
signal launch_requested(payload: Dictionary)
signal round_state_updated(snapshot: Dictionary)
signal error_raised(message: String)

var identity: IdentityService
var api: RelayAPIClient
var realtime: MatchRealtimeClient
var players: Array = []
var current_match: Dictionary = {}
var current_classic_match: Dictionary = {}
var current_result_summary: Dictionary = {}
var current_selection: Dictionary = {
	"song_id": "",
	"difficulty": "",
	"mode": GameModeConfig.DEFAULT_MODE,
}
var current_invite_context: Dictionary = {}
var pending_steam_invite: Dictionary = {}
var shared_start_time: float = -1.0
var session_phase: String = "idle"
var active_flow: String = "idle"

var _poll_timer: Timer
var _finalize_retry_timer: Timer
var _current_round_match_id: String = ""
var _current_round_chart_hash: String = ""
var _realtime_connected: bool = false
var _last_live_submit_ms: int = 0
var _pending_finalize_payload: Dictionary = {}
var _finalize_retry_count: int = 0
var _finalize_in_flight: bool = false


func _ready() -> void:
	api = RelayAPIClient.new()
	add_child(api)
	api.request_failed.connect(_on_request_failed)

	realtime = MatchRealtimeClient.new()
	add_child(realtime)
	realtime.envelope_received.connect(_on_realtime_envelope)
	realtime.connection_changed.connect(_on_realtime_connection_changed)
	realtime.error_raised.connect(error_raised.emit)

	_poll_timer = Timer.new()
	_poll_timer.wait_time = RelayConfig.polling_interval_seconds()
	_poll_timer.autostart = false
	_poll_timer.one_shot = false
	_poll_timer.timeout.connect(_poll_active_state)
	add_child(_poll_timer)

	_finalize_retry_timer = Timer.new()
	_finalize_retry_timer.wait_time = FINALIZE_RETRY_DELAY_SECONDS
	_finalize_retry_timer.autostart = false
	_finalize_retry_timer.one_shot = true
	_finalize_retry_timer.timeout.connect(_retry_finalize_submission)
	add_child(_finalize_retry_timer)


func setup(identity_service: IdentityService) -> void:
	identity = identity_service
	if not identity.auth_state_changed.is_connected(_on_auth_state_changed):
		identity.auth_state_changed.connect(_on_auth_state_changed)
	if not identity.login_failed.is_connected(error_raised.emit):
		identity.login_failed.connect(error_raised.emit)
	if not identity.request_failed.is_connected(_on_request_failed):
		identity.request_failed.connect(_on_request_failed)


func is_available() -> bool:
	return identity != null and identity.is_available()


func is_authenticated() -> bool:
	return identity != null and identity.is_authenticated()


func is_session_active() -> bool:
	return not _current_round_match_id.is_empty()


func is_hosting() -> bool:
	return active_flow == "classic"


func get_players() -> Array:
	return players.duplicate(true)


func get_current_selection() -> Dictionary:
	return current_selection.duplicate(true)


func get_current_phase() -> String:
	return session_phase


func get_active_flow() -> String:
	return active_flow


func get_current_invite_context() -> Dictionary:
	return current_invite_context.duplicate(true)


func set_pending_steam_invite(invite: Dictionary) -> void:
	pending_steam_invite = invite.duplicate(true)
	current_invite_context = invite.duplicate(true)
	current_selection["song_id"] = ""
	current_selection["difficulty"] = str(invite.get("difficulty", current_selection.get("difficulty", "")))
	var invite_mode := str(invite.get("mode", current_selection.get("mode", GameModeConfig.DEFAULT_MODE)))
	current_selection["mode"] = invite_mode if GameModeConfig.is_valid(invite_mode) else GameModeConfig.DEFAULT_MODE
	selection_changed.emit(get_current_selection())


func peek_pending_steam_invite() -> Dictionary:
	return pending_steam_invite.duplicate(true)


func consume_pending_steam_invite() -> Dictionary:
	var invite := pending_steam_invite.duplicate(true)
	pending_steam_invite.clear()
	return invite


func get_shareable_lobby_code() -> String:
	return ""


func get_current_round_snapshot() -> Dictionary:
	return current_match.duplicate(true)


func get_current_result_summary() -> Dictionary:
	return current_result_summary.duplicate(true)


func get_opponent_snapshot(snapshot: Dictionary = {}) -> Dictionary:
	var effective_snapshot: Dictionary = _effective_results_snapshot(snapshot)
	if effective_snapshot.is_empty() or identity == null:
		return {}
	var local_id: String = str(identity.get_current_identity().get("userID", ""))
	for player_variant in _as_array(effective_snapshot.get("players", [])):
		if not (player_variant is Dictionary):
			continue
		var player: Dictionary = player_variant as Dictionary
		if str(player.get("userID", "")) == local_id:
			continue
		return player.duplicate(true)
	return {}


func get_winner_display_name(snapshot: Dictionary = {}) -> String:
	var effective_snapshot: Dictionary = _effective_results_snapshot(snapshot)
	if effective_snapshot.is_empty():
		return ""
	var winner_user_id: String = str(current_result_summary.get("winnerUserID", "")).strip_edges()
	if not winner_user_id.is_empty():
		for player_variant in _as_array(effective_snapshot.get("players", [])):
			if player_variant is Dictionary:
				var player: Dictionary = player_variant as Dictionary
				if str(player.get("userID", "")) == winner_user_id:
					return str(player.get("displayName", "Player"))
	var best_placement: int = 2147483647
	var winner_name := ""
	var score_ranked_players: Array[Dictionary] = []
	for player_variant in _as_array(effective_snapshot.get("players", [])):
		if not (player_variant is Dictionary):
			continue
		var player: Dictionary = player_variant as Dictionary
		if has_trustworthy_final_score(player):
			score_ranked_players.append(player)
		var placement: int = _placement_from_player(player)
		if placement <= 0:
			continue
		if placement < best_placement:
			best_placement = placement
			winner_name = str(player.get("displayName", "Player"))
	if winner_name.is_empty() and score_ranked_players.size() >= 2:
		score_ranked_players.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return int(a.get("finalScore", 0)) > int(b.get("finalScore", 0))
		)
		if int(score_ranked_players[0].get("finalScore", 0)) != int(score_ranked_players[1].get("finalScore", 0)):
			winner_name = str(score_ranked_players[0].get("displayName", "Player"))
	return winner_name


func get_local_player_placement(snapshot: Dictionary = {}) -> int:
	var effective_snapshot: Dictionary = _effective_results_snapshot(snapshot)
	if effective_snapshot.is_empty() or identity == null:
		return 0
	var local_id: String = str(identity.get_current_identity().get("userID", ""))
	if local_id.is_empty():
		return 0
	var score_ranked_players: Array[Dictionary] = []
	for player_variant in _as_array(effective_snapshot.get("players", [])):
		if not (player_variant is Dictionary):
			continue
		var player: Dictionary = player_variant as Dictionary
		if has_trustworthy_final_score(player):
			score_ranked_players.append(player)
		if str(player.get("userID", "")) != local_id:
			continue
		var placement: int = _placement_from_player(player)
		if placement > 0:
			return placement
	if score_ranked_players.size() >= 2:
		score_ranked_players.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return int(a.get("finalScore", 0)) > int(b.get("finalScore", 0))
		)
		for index in score_ranked_players.size():
			if str(score_ranked_players[index].get("userID", "")) == local_id:
				if index > 0 and int(score_ranked_players[index].get("finalScore", 0)) == int(score_ranked_players[index - 1].get("finalScore", 0)):
					return 0
				return index + 1
	return 0


func get_local_player_entry() -> Dictionary:
	var local_id: String = str(identity.get_current_identity().get("userID", ""))
	for player_variant in players:
		if player_variant is Dictionary:
			var player: Dictionary = player_variant as Dictionary
			if str(player.get("user_id", "")) == local_id:
				return player.duplicate(true)
	return {}


func get_classic_common_songs() -> Array[String]:
	var values: Array[String] = []
	for song_id_variant in current_classic_match.get("commonSongIDs", []):
		var local_song_id: String = ContentRegistry.get_song_id(str(song_id_variant))
		if not local_song_id.is_empty():
			values.append(local_song_id)
	return values


func preview_classic_accessible_song_ids(mode: String, difficulty: String) -> Array[String]:
	return _accessible_song_ids(mode, difficulty)


func authenticate_current_platform() -> void:
	if identity == null:
		error_raised.emit("Identity service is not configured.")
		return
	identity.authenticate_current_platform()


func set_song_selection(song_id: String, difficulty: String, mode: String) -> void:
	current_selection = {
		"song_id": song_id,
		"difficulty": difficulty,
		"mode": mode if GameModeConfig.is_valid(mode) else GameModeConfig.DEFAULT_MODE,
	}
	selection_changed.emit(get_current_selection())


func start_custom_matchmaking() -> void:
	if not _ensure_authenticated("starting a custom match"):
		return
	var song_id: String = str(current_selection.get("song_id", ""))
	var difficulty: String = str(current_selection.get("difficulty", ""))
	var mode: String = str(current_selection.get("mode", GameModeConfig.DEFAULT_MODE))
	if song_id.is_empty() or difficulty.is_empty():
		error_raised.emit("Choose a song, mode, and difficulty first.")
		return
	current_invite_context.clear()
	active_flow = "custom"
	session_phase = "searching"
	var relay_song_id: String = ContentRegistry.get_relay_song_id(song_id)
	var payload: Dictionary = {
		"songID": relay_song_id,
		"difficulty": _backend_difficulty(difficulty),
		"mode": mode,
	}
	_set_steam_multiplayer_presence("Searching Custom Match", difficulty, mode)
	api.call_api("POST", "/matches/find", payload, identity.get_backend_token(), _on_custom_match_response)


func cancel_custom_match() -> void:
	if current_match.is_empty():
		return
	var match_id: String = str(current_match.get("matchID", ""))
	if match_id.is_empty():
		return
	api.call_api("POST", "/matches/%s/cancel" % match_id.uri_encode(), {}, identity.get_backend_token(), _on_custom_match_response)


func start_classic_matchmaking(difficulty: String = "", mode: String = GameModeConfig.DEFAULT_MODE, invite_context: Dictionary = {}) -> void:
	if not _ensure_authenticated("starting a classic match"):
		return
	var selected_difficulty: String = difficulty if not difficulty.is_empty() else str(current_selection.get("difficulty", RelayConfig.classic_default_difficulty()))
	var selected_mode: String = mode if GameModeConfig.is_valid(mode) else str(current_selection.get("mode", GameModeConfig.DEFAULT_MODE))
	if not GameModeConfig.is_valid(selected_mode):
		selected_mode = GameModeConfig.DEFAULT_MODE
	var accessible_song_ids := _accessible_song_ids(selected_mode, selected_difficulty)
	if accessible_song_ids.is_empty():
		error_raised.emit("No shared %s songs are available for %s." % [GameModeConfig.get_short_label(selected_mode), selected_difficulty])
		return
	current_invite_context = invite_context.duplicate(true)
	current_selection["song_id"] = ""
	current_selection["difficulty"] = selected_difficulty
	current_selection["mode"] = selected_mode
	selection_changed.emit(get_current_selection())
	active_flow = "classic"
	session_phase = "searching"
	var payload: Dictionary = {
		"difficulty": _backend_difficulty(selected_difficulty),
		"accessibleSongIDs": accessible_song_ids,
		"mode": selected_mode,
	}
	var status := "Searching Steam Invite Queue" if not current_invite_context.is_empty() else "Searching Classic Match"
	_set_steam_multiplayer_presence(status, selected_difficulty, selected_mode, str(current_invite_context.get("connect", "")))
	api.call_api("POST", "/classic/find", payload, identity.get_backend_token(), _on_classic_match_response)


func select_classic_song(song_id: String) -> void:
	if current_classic_match.is_empty():
		error_raised.emit("No classic match is active.")
		return
	var classic_id: String = str(current_classic_match.get("classicMatchID", ""))
	if classic_id.is_empty():
		error_raised.emit("No classic match is active.")
		return
	current_selection["song_id"] = song_id
	selection_changed.emit(get_current_selection())
	var relay_song_id: String = ContentRegistry.get_relay_song_id(song_id)
	api.call_api(
		"POST",
		"/classic/%s/select-song" % classic_id.uri_encode(),
		{"songID": relay_song_id},
		identity.get_backend_token(),
		_on_classic_match_response
	)


func set_ready_state(is_ready: bool) -> void:
	if not _ensure_authenticated("setting ready state"):
		return
	if active_flow == "custom":
		if current_match.is_empty():
			error_raised.emit("No custom match is active.")
			return
		var match_id: String = str(current_match.get("matchID", ""))
		api.call_api(
			"POST",
			"/matches/%s/ready" % match_id.uri_encode(),
			{"ready": is_ready},
			identity.get_backend_token(),
			_on_custom_match_response
		)
		return
	if active_flow == "classic":
		if current_classic_match.is_empty():
			error_raised.emit("No classic match is active.")
			return
		var classic_id: String = str(current_classic_match.get("classicMatchID", ""))
		api.call_api(
			"POST",
			"/classic/%s/ready" % classic_id.uri_encode(),
			{"ready": is_ready},
			identity.get_backend_token(),
			_on_classic_match_response
		)
		return
	error_raised.emit("There is no active multiplayer flow.")


func can_launch_match() -> bool:
	if active_flow != "classic" or current_classic_match.is_empty():
		return false
	var rounds: Array = current_classic_match.get("rounds", []) as Array
	var current_index: int = int(current_classic_match.get("currentRoundIndex", 0))
	return rounds.size() > current_index + 1


func launch_match() -> void:
	if not can_launch_match():
		error_raised.emit("No additional classic rounds are ready to launch.")
		return
	var classic_id: String = str(current_classic_match.get("classicMatchID", ""))
	var next_index: int = int(current_classic_match.get("currentRoundIndex", 0)) + 1
	api.call_api(
		"POST",
		"/classic/%s/rounds/%d/start" % [classic_id.uri_encode(), next_index],
		{},
		identity.get_backend_token(),
		_on_classic_match_response
	)


func close_session() -> void:
	_stop_polling()
	if not _finalize_retry_timer.is_stopped():
		_finalize_retry_timer.stop()
	realtime.close_stream()
	_realtime_connected = false
	_current_round_match_id = ""
	_current_round_chart_hash = ""
	shared_start_time = -1.0
	_pending_finalize_payload.clear()
	_finalize_retry_count = 0
	_finalize_in_flight = false
	players.clear()
	current_match.clear()
	current_classic_match.clear()
	current_result_summary.clear()
	current_invite_context.clear()
	pending_steam_invite.clear()
	active_flow = "idle"
	session_phase = "idle"
	players_changed.emit(get_players())
	session_state_changed.emit(false, false)
	_clear_steam_multiplayer_presence()


func complete_local_round(final_result: Dictionary) -> void:
	if not _ensure_authenticated("submitting a final multiplayer result"):
		return
	if _current_round_match_id.is_empty():
		print("[multiplayer] skipped finalize because current round match ID is empty")
		return
	send_live_score(
		int(final_result.get("score", 0)),
		clampf(float(final_result.get("accuracy", 0.0)), 0.0, 100.0),
		int(final_result.get("max_combo", 0))
	)
	var final_chart_hash := str(final_result.get("chart_hash", ""))
	if final_chart_hash.is_empty():
		final_chart_hash = _current_round_chart_hash
	_pending_finalize_payload = {
		"songID": ContentRegistry.get_relay_song_id(str(final_result.get("song_id", ""))),
		"difficulty": _backend_difficulty(str(final_result.get("difficulty", "Medium"))),
		"mode": str(final_result.get("mode", GameModeConfig.DEFAULT_MODE)),
		"perfect": int(final_result.get("perfect", 0)),
		"great": int(final_result.get("great", 0)),
		"good": int(final_result.get("good", 0)),
		"miss": int(final_result.get("miss", 0)),
		"maxCombo": int(final_result.get("max_combo", 0)),
		"sustainTicks": int(final_result.get("sustain_ticks", 0)),
		"holdSuccesses": int(final_result.get("hold_successes", 0)),
		"holdBreaks": int(final_result.get("hold_breaks", 0)),
		"chartHash": final_chart_hash,
		"reportedScore": int(final_result.get("score", 0)),
		"reportedAccuracy": clampf(float(final_result.get("accuracy", 0.0)) / 100.0, 0.0, 1.0),
		"scoringEvents": [],
	}
	_finalize_retry_count = 0
	_submit_finalize_payload()


func _submit_finalize_payload() -> void:
	if _finalize_in_flight or _pending_finalize_payload.is_empty():
		return
	if not _ensure_authenticated("submitting a final multiplayer result"):
		return
	if _current_round_match_id.is_empty():
		return
	_finalize_in_flight = true
	print("[multiplayer] finalize submit match=%s attempt=%d payload=%s" % [
		_current_round_match_id,
		_finalize_retry_count + 1,
		JSON.stringify(_pending_finalize_payload),
	])
	api.call_api(
		"POST",
		"/matches/%s/finalize" % _current_round_match_id.uri_encode(),
		_pending_finalize_payload,
		identity.get_backend_token(),
		_on_finalize_completed
	)


func send_live_score(score: int, accuracy: float, combo: int) -> void:
	if _current_round_match_id.is_empty() or not _ensure_authenticated("submitting live multiplayer score"):
		return
	var now_ms: int = Time.get_ticks_msec()
	if now_ms - _last_live_submit_ms < 125:
		return
	_last_live_submit_ms = now_ms
	var payload: Dictionary = {
		"liveScore": score,
		"liveAccuracy": accuracy,
		"liveCombo": combo,
	}
	api.call_api(
		"POST",
		"/matches/%s/live-score" % _current_round_match_id.uri_encode(),
		payload,
		identity.get_backend_token(),
		Callable()
	)


func send_hit_event(_note_id: int, _hit_time: float) -> void:
	return


func _poll_active_state() -> void:
	if not _ensure_authenticated("refreshing multiplayer state"):
		return
	if not _current_round_match_id.is_empty():
		print("[multiplayer] polling round status for match=%s phase=%s" % [_current_round_match_id, session_phase])
		api.call_api("GET", "/matches/%s" % _current_round_match_id.uri_encode(), {}, identity.get_backend_token(), _on_round_status_response)
		return
	if active_flow == "custom":
		var match_id: String = str(current_match.get("matchID", ""))
		if not match_id.is_empty():
			api.call_api("GET", "/matches/%s" % match_id.uri_encode(), {}, identity.get_backend_token(), _on_custom_match_response)
	elif active_flow == "classic":
		var classic_id: String = str(current_classic_match.get("classicMatchID", ""))
		if not classic_id.is_empty():
			api.call_api("GET", "/classic/%s" % classic_id.uri_encode(), {}, identity.get_backend_token(), _on_classic_match_response)


func _start_polling() -> void:
	if _poll_timer.is_stopped():
		_poll_timer.start()


func _stop_polling() -> void:
	if not _poll_timer.is_stopped():
		_poll_timer.stop()


func _ensure_authenticated(action: String) -> bool:
	if identity == null or not identity.is_authenticated():
		error_raised.emit("Authenticate before %s." % action)
		return false
	return true


func _set_steam_multiplayer_presence(status: String, difficulty: String, mode: String, connect_string: String = "", group: String = "", group_size: int = 0) -> void:
	if not Engine.has_singleton("Steam") or not SteamClient.is_ready():
		return
	SteamClient.set_multiplayer_presence(status, difficulty, mode, connect_string, group, group_size)


func _clear_steam_multiplayer_presence() -> void:
	if not Engine.has_singleton("Steam") or not SteamClient.is_ready():
		return
	SteamClient.set_menu_presence("In Menus")


func _update_classic_steam_presence(snapshot: Dictionary) -> void:
	if active_flow != "classic":
		return
	var difficulty := str(current_selection.get("difficulty", ""))
	var mode := str(current_selection.get("mode", GameModeConfig.DEFAULT_MODE))
	var connect := str(current_invite_context.get("connect", ""))
	var status := "Classic Matchmaking"
	match str(snapshot.get("status", session_phase)).to_lower():
		"waiting", "searching":
			status = "Searching Classic Match"
		"selecting":
			status = "Selecting Shared Song"
		"active":
			status = "Playing Multiplayer"
		"finished":
			status = "Viewing Multiplayer Results"
	var group := str(snapshot.get("classicMatchID", ""))
	var group_size := (_as_array(snapshot.get("players", []))).size()
	_set_steam_multiplayer_presence(status, difficulty, mode, connect, group, group_size)


func _update_custom_steam_presence(snapshot: Dictionary) -> void:
	if active_flow != "custom":
		return
	var difficulty := str(current_selection.get("difficulty", ""))
	var mode := str(current_selection.get("mode", GameModeConfig.DEFAULT_MODE))
	var status := "Custom Matchmaking"
	match str(snapshot.get("status", session_phase)).to_lower():
		"waiting", "searching":
			status = "Searching Custom Match"
		"ready":
			status = "Ready In Custom Match"
		"active":
			status = "Playing Multiplayer"
		"finished":
			status = "Viewing Multiplayer Results"
	var group := str(snapshot.get("matchID", ""))
	var group_size := (_as_array(snapshot.get("players", []))).size()
	_set_steam_multiplayer_presence(status, difficulty, mode, "", group, group_size)


func _accessible_song_ids(mode: String = GameModeConfig.DEFAULT_MODE, difficulty: String = "") -> Array[String]:
	var ids: Array[String] = []
	var selected_mode: String = mode if GameModeConfig.is_valid(mode) else GameModeConfig.DEFAULT_MODE
	for song_variant in ContentRegistry.get_songs():
		if song_variant is Dictionary:
			var song: Dictionary = song_variant as Dictionary
			var song_id: String = str(song.get("id", ""))
			if song_id.is_empty() or not ProgressionManager.is_song_multiplayer_accessible(song_id):
				continue
			if not ContentRegistry.get_supported_modes(song).has(selected_mode):
				continue
			if not difficulty.is_empty() and not ContentRegistry.get_supported_difficulties(song, selected_mode).has(difficulty):
				continue
			ids.append(ContentRegistry.get_relay_song_id(song_id))
	return ids


func _backend_difficulty(display_value: String) -> String:
	match display_value.to_lower():
		"easy":
			return "easy"
		"medium":
			return "medium"
		"hard":
			return "hard"
		"expert":
			return "expert"
		"professional":
			return "professional"
		_:
			return display_value.to_lower()


func _display_difficulty(backend_value: String) -> String:
	match backend_value.to_lower():
		"easy":
			return "Easy"
		"medium":
			return "Medium"
		"hard":
			return "Hard"
		"expert":
			return "Expert"
		"professional":
			return "Professional"
		_:
			return backend_value.capitalize()


func _on_auth_state_changed(new_identity: Dictionary) -> void:
	auth_state_changed.emit(new_identity.duplicate(true))


func _on_request_failed(_route: String, message: String) -> void:
	error_raised.emit(message)


func _on_custom_match_response(success: bool, data: Variant, payload: Dictionary, _meta: Dictionary) -> void:
	if not success or not (data is Dictionary):
		error_raised.emit(str(payload.get("message", "Custom multiplayer request failed.")))
		return
	var snapshot: Dictionary = (data as Dictionary).duplicate(true)
	current_match = snapshot
	session_phase = str(snapshot.get("status", session_phase))
	lobby_updated.emit(snapshot.duplicate(true))
	matchmaking_updated.emit(snapshot.duplicate(true))
	_sync_players_from_custom(snapshot)
	_maybe_launch_from_custom(snapshot)
	_update_custom_steam_presence(snapshot)
	_start_polling()


func _on_classic_match_response(success: bool, data: Variant, payload: Dictionary, _meta: Dictionary) -> void:
	if not success or not (data is Dictionary):
		error_raised.emit(str(payload.get("message", "Classic multiplayer request failed.")))
		return
	var snapshot: Dictionary = (data as Dictionary).duplicate(true)
	current_classic_match = snapshot
	session_phase = str(snapshot.get("status", session_phase))
	var difficulty: String = _display_difficulty(str(snapshot.get("difficulty", current_selection.get("difficulty", ""))))
	current_selection["difficulty"] = difficulty
	var mode: String = str(snapshot.get("mode", current_selection.get("mode", GameModeConfig.DEFAULT_MODE)))
	if not GameModeConfig.is_valid(mode):
		mode = str(current_selection.get("mode", GameModeConfig.DEFAULT_MODE))
	if not GameModeConfig.is_valid(mode):
		mode = GameModeConfig.DEFAULT_MODE
	current_selection["mode"] = mode
	selection_changed.emit(get_current_selection())
	lobby_updated.emit(snapshot.duplicate(true))
	matchmaking_updated.emit(snapshot.duplicate(true))
	_sync_players_from_classic(snapshot)
	_maybe_launch_from_classic(snapshot)
	_update_classic_steam_presence(snapshot)
	_start_polling()


func _sync_players_from_custom(snapshot: Dictionary) -> void:
	players.clear()
	for player_variant in _as_array(snapshot.get("players", [])):
		if player_variant is Dictionary:
			var player: Dictionary = player_variant as Dictionary
			players.append({
				"user_id": str(player.get("userID", "")),
				"display_name": str(player.get("displayName", "Player")),
				"is_ready": bool(player.get("ready", false)),
				"is_connected": bool(player.get("isConnected", true)),
				"live_score": int(player.get("liveScore", 0)),
				"live_combo": int(player.get("liveCombo", 0)),
				"final_score": player.get("finalScore", null),
				"final_placement": player.get("finalPlacement", null),
				"selected_song_id": ContentRegistry.get_song_id(str(snapshot.get("songID", current_selection.get("song_id", "")))),
			})
	players_changed.emit(get_players())


func _sync_players_from_classic(snapshot: Dictionary) -> void:
	players.clear()
	for player_variant in _as_array(snapshot.get("players", [])):
		if player_variant is Dictionary:
			var player: Dictionary = player_variant as Dictionary
			players.append({
				"user_id": str(player.get("userID", "")),
				"display_name": str(player.get("displayName", "Player")),
				"is_ready": bool(player.get("ready", false)),
				"is_connected": bool(player.get("isConnected", true)),
				"live_score": int(player.get("liveScore", 0)),
				"live_combo": int(player.get("liveCombo", 0)),
				"final_score": player.get("finalScore", null),
				"final_placement": player.get("finalPlacement", null),
				"selected_song_id": ContentRegistry.get_song_id(str(player.get("selectedSongID", ""))),
			})
	players_changed.emit(get_players())


func _maybe_launch_from_custom(snapshot: Dictionary) -> void:
	var bootstrap: Dictionary = _as_dictionary(snapshot.get("bootstrap", {}))
	if bootstrap.is_empty():
		return
	_begin_round_from_bootstrap(bootstrap)


func _maybe_launch_from_classic(snapshot: Dictionary) -> void:
	var bootstrap: Dictionary = _as_dictionary(snapshot.get("currentBootstrap", {}))
	if bootstrap.is_empty():
		return
	_begin_round_from_bootstrap(bootstrap)


func _begin_round_from_bootstrap(bootstrap: Dictionary) -> void:
	var match_id: String = str(bootstrap.get("matchID", ""))
	var relay_song_id: String = str(bootstrap.get("songID", ""))
	var song_id: String = ContentRegistry.get_song_id(relay_song_id)
	var difficulty: String = _display_difficulty(str(bootstrap.get("difficulty", current_selection.get("difficulty", ""))))
	var mode: String = SteamMultiplayerInvite.resolve_classic_bootstrap_mode(bootstrap, current_selection)
	if match_id.is_empty() or difficulty.is_empty() or mode.is_empty() or match_id == _current_round_match_id:
		return
	if song_id.is_empty():
		song_id = relay_song_id
	current_selection["song_id"] = song_id
	current_selection["difficulty"] = difficulty
	current_selection["mode"] = mode
	selection_changed.emit(get_current_selection())
	_current_round_match_id = match_id
	_current_round_chart_hash = str(bootstrap.get("chartHash", ""))
	shared_start_time = float(bootstrap.get("plannedStartAtMs", 0.0)) / 1000.0
	start_time_received.emit(shared_start_time)
	session_state_changed.emit(true, false)
	_connect_realtime_if_possible(match_id)
	launch_requested.emit({
		"song_id": song_id,
		"difficulty": difficulty,
		"mode": mode,
		"match_id": match_id,
		"planned_start_at_ms": int(bootstrap.get("plannedStartAtMs", 0)),
	})


func _connect_realtime_if_possible(match_id: String) -> void:
	if identity == null:
		return
	var realtime_base_url: String = identity.get_realtime_base_url()
	var backend_token: String = identity.get_backend_token()
	if realtime_base_url.is_empty() or backend_token.is_empty():
		return
	realtime.connect_to_match(match_id, realtime_base_url, backend_token)


func _on_realtime_envelope(envelope: Dictionary) -> void:
	var envelope_type: String = str(envelope.get("type", ""))
	if envelope_type == "snapshot":
		var snapshot: Dictionary = _as_dictionary(envelope.get("snapshot", {}))
		if snapshot.is_empty():
			return
		current_match = snapshot
		round_state_updated.emit(current_match.duplicate(true))
		_sync_players_from_custom(snapshot)
		hit_event_received.emit(envelope.duplicate(true))
	elif envelope_type == "result":
		var result_payload: Dictionary = _as_dictionary(envelope.get("result", {}))
		if not result_payload.is_empty():
			print("[multiplayer] realtime result received match=%s payload=%s" % [_current_round_match_id, JSON.stringify(result_payload)])
			_apply_result_summary(result_payload)
		session_phase = "finished"
		session_state_changed.emit(false, false)


func _on_realtime_connection_changed(active: bool) -> void:
	_realtime_connected = active


func _on_finalize_completed(success: bool, _data: Variant, payload: Dictionary, _meta: Dictionary) -> void:
	_finalize_in_flight = false
	if not success:
		var response_code: String = str(_meta.get("response_code", ""))
		var route: String = str(_meta.get("route", ""))
		var raw_body: String = str(_meta.get("raw_body", ""))
		print("[multiplayer] finalize failed match=%s attempt=%d route=%s response=%s message=%s body=%s" % [
			_current_round_match_id,
			_finalize_retry_count + 1,
			route,
			response_code,
			str(payload.get("message", "Failed to submit final multiplayer score.")),
			raw_body,
		])
		if _finalize_retry_count < FINALIZE_RETRY_LIMIT - 1:
			_finalize_retry_count += 1
			if not _finalize_retry_timer.is_stopped():
				_finalize_retry_timer.stop()
			_finalize_retry_timer.start()
			return
		error_raised.emit(str(payload.get("message", "Failed to submit final multiplayer score.")))
		return
	print("[multiplayer] finalize succeeded match=%s response=%s" % [
		_current_round_match_id,
		JSON.stringify(_data),
	])
	if not _finalize_retry_timer.is_stopped():
		_finalize_retry_timer.stop()
	_finalize_retry_count = 0
	if _data is Dictionary:
		_apply_result_summary((_data as Dictionary).duplicate(true))
	session_phase = "finished"
	shared_start_time = -1.0
	session_state_changed.emit(false, false)
	_poll_active_state()


func _on_round_status_response(success: bool, data: Variant, payload: Dictionary, _meta: Dictionary) -> void:
	if not success or not (data is Dictionary):
		print("[multiplayer] round status poll failed match=%s response=%s message=%s body=%s" % [
			_current_round_match_id,
			str(_meta.get("response_code", "")),
			str(payload.get("message", "Failed to refresh multiplayer round status.")),
			str(_meta.get("raw_body", "")),
		])
		error_raised.emit(str(payload.get("message", "Failed to refresh multiplayer round status.")))
		return
	var snapshot: Dictionary = (data as Dictionary).duplicate(true)
	print("[multiplayer] round status poll match=%s status=%s players=%s" % [
		str(snapshot.get("matchID", _current_round_match_id)),
		str(snapshot.get("status", "")),
		JSON.stringify(snapshot.get("players", [])),
	])
	current_match = _merge_match_snapshots(snapshot, current_match)
	session_phase = str(snapshot.get("status", session_phase))
	round_state_updated.emit(current_match.duplicate(true))
	_sync_players_from_custom(current_match)
	_update_custom_steam_presence(current_match)
	if session_phase == "finished":
		session_state_changed.emit(false, false)


func _retry_finalize_submission() -> void:
	if _pending_finalize_payload.is_empty():
		return
	print("[multiplayer] retrying finalize submission for match=%s attempt=%d" % [
		_current_round_match_id,
		_finalize_retry_count + 1,
	])
	_submit_finalize_payload()


func _apply_result_summary(summary: Dictionary) -> void:
	if summary.is_empty():
		return
	current_result_summary = summary.duplicate(true)
	if current_match.is_empty():
		current_match = {
			"matchID": str(summary.get("matchID", _current_round_match_id)),
			"status": "finished",
			"players": [],
		}
	current_match["status"] = "finished"
	var result_players: Array = _as_array(summary.get("players", []))
	if not result_players.is_empty():
		current_match = _merge_match_snapshots({
			"matchID": str(summary.get("matchID", _current_round_match_id)),
			"status": "finished",
			"players": result_players,
		}, current_match)
		_sync_players_from_custom(current_match)
	round_state_updated.emit(current_match.duplicate(true))


func _as_dictionary(value: Variant) -> Dictionary:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}


func _as_array(value: Variant) -> Array:
	if value is Array:
		return (value as Array).duplicate(true)
	return []


func _merge_match_snapshots(primary: Dictionary, fallback: Dictionary) -> Dictionary:
	if fallback.is_empty():
		return primary.duplicate(true)
	if primary.is_empty():
		return fallback.duplicate(true)
	var merged: Dictionary = fallback.duplicate(true)
	for key_variant in primary.keys():
		merged[str(key_variant)] = primary[key_variant]
	var fallback_players_by_id := {}
	for player_variant in _as_array(fallback.get("players", [])):
		if player_variant is Dictionary:
			var player: Dictionary = player_variant as Dictionary
			fallback_players_by_id[str(player.get("userID", ""))] = player.duplicate(true)
	var merged_players: Array = []
	for player_variant in _as_array(primary.get("players", [])):
		if player_variant is Dictionary:
			var primary_player: Dictionary = player_variant as Dictionary
			var user_id: String = str(primary_player.get("userID", ""))
			var fallback_player: Dictionary = fallback_players_by_id.get(user_id, {}) as Dictionary
			merged_players.append(_merge_player_snapshots(primary_player, fallback_player))
			fallback_players_by_id.erase(user_id)
	for remaining_player in fallback_players_by_id.values():
		if remaining_player is Dictionary:
			merged_players.append((remaining_player as Dictionary).duplicate(true))
	merged["players"] = merged_players
	return merged


func _merge_player_snapshots(primary: Dictionary, fallback: Dictionary) -> Dictionary:
	if fallback.is_empty():
		return primary.duplicate(true)
	var merged: Dictionary = fallback.duplicate(true)
	for key_variant in primary.keys():
		merged[str(key_variant)] = primary[key_variant]
	merged["displayName"] = str(primary.get("displayName", fallback.get("displayName", "Player")))
	merged["ready"] = bool(primary.get("ready", fallback.get("ready", false))) or bool(fallback.get("ready", false))
	merged["isConnected"] = bool(primary.get("isConnected", fallback.get("isConnected", true))) or bool(fallback.get("isConnected", true))
	merged["liveScore"] = maxi(int(primary.get("liveScore", 0)), int(fallback.get("liveScore", 0)))
	merged["liveAccuracy"] = maxf(float(primary.get("liveAccuracy", 0.0)), float(fallback.get("liveAccuracy", 0.0)))
	merged["liveCombo"] = maxi(int(primary.get("liveCombo", 0)), int(fallback.get("liveCombo", 0)))
	if not has_trustworthy_final_score(primary) and has_trustworthy_final_score(fallback):
		merged["finalScore"] = fallback.get("finalScore")
	if primary.get("finalAccuracy", null) == null and fallback.get("finalAccuracy", null) != null:
		merged["finalAccuracy"] = fallback.get("finalAccuracy")
	if primary.get("finalMaxCombo", null) == null and fallback.get("finalMaxCombo", null) != null:
		merged["finalMaxCombo"] = fallback.get("finalMaxCombo")
	if primary.get("finalPlacement", null) == null and fallback.get("finalPlacement", null) != null:
		merged["finalPlacement"] = fallback.get("finalPlacement")
	if primary.get("placement", null) == null and fallback.get("placement", null) != null:
		merged["placement"] = fallback.get("placement")
	return merged


func _placement_from_player(player: Dictionary) -> int:
	if player.get("finalPlacement", null) != null:
		return int(player.get("finalPlacement", 0))
	if player.get("placement", null) != null:
		return int(player.get("placement", 0))
	return 0


func _effective_results_snapshot(snapshot: Dictionary) -> Dictionary:
	var effective_snapshot: Dictionary = snapshot if not snapshot.is_empty() else current_match
	if current_result_summary.is_empty():
		return effective_snapshot
	var result_players := _as_array(current_result_summary.get("players", []))
	if result_players.is_empty():
		return effective_snapshot
	return _merge_match_snapshots({
		"matchID": str(current_result_summary.get("matchID", effective_snapshot.get("matchID", _current_round_match_id))),
		"status": str(effective_snapshot.get("status", "finished")),
		"players": result_players,
	}, effective_snapshot)


func get_display_score_for_player(player: Dictionary) -> int:
	if has_trustworthy_final_score(player):
		return int(player.get("finalScore", 0))
	return int(player.get("liveScore", 0))


func get_live_display_score_for_player(player: Dictionary) -> int:
	return int(player.get("liveScore", 0))


func has_trustworthy_final_score(player: Dictionary) -> bool:
	var final_score_variant: Variant = player.get("finalScore", null)
	if final_score_variant == null:
		return false
	var final_score: float = float(final_score_variant)
	var live_score: float = float(player.get("liveScore", 0.0))
	if final_score > 0.0:
		return true
	return live_score <= 0.0 and _placement_from_player(player) > 0


func _score_based_results_outcome(local_user_id: String, players_array: Array) -> Dictionary:
	if players_array.size() < 2:
		return {}
	for player_variant in players_array:
		if not (player_variant is Dictionary):
			return {}
		var player: Dictionary = player_variant as Dictionary
		if not has_trustworthy_final_score(player):
			return {}
	var local_player: Dictionary = {}
	var opponent_player: Dictionary = {}
	for player_variant in players_array:
		var player: Dictionary = player_variant as Dictionary
		if str(player.get("userID", "")) == local_user_id:
			local_player = player
		else:
			opponent_player = player
	if local_player.is_empty() or opponent_player.is_empty():
		return {}
	var local_score := int(local_player.get("finalScore", 0))
	var opponent_score := int(opponent_player.get("finalScore", 0))
	if local_score == opponent_score:
		return {
			"winner_user_id": "",
			"placement": 0,
			"outcome": "draw",
		}
	return {
		"winner_user_id": str(local_player.get("userID", "")) if local_score > opponent_score else str(opponent_player.get("userID", "")),
		"placement": 1 if local_score > opponent_score else 2,
		"outcome": "victory" if local_score > opponent_score else "defeat",
	}


func has_authoritative_results(snapshot: Dictionary = {}) -> bool:
	return not get_results_outcome(snapshot).is_empty()


func get_results_outcome(snapshot: Dictionary = {}) -> Dictionary:
	var effective_snapshot: Dictionary = _effective_results_snapshot(snapshot)
	if effective_snapshot.is_empty() or identity == null:
		return {}
	var local_user_id: String = str(identity.get_current_identity().get("userID", ""))
	if local_user_id.is_empty():
		return {}
	var score_outcome: Dictionary = _score_based_results_outcome(local_user_id, _as_array(effective_snapshot.get("players", [])))
	if not score_outcome.is_empty():
		return score_outcome
	var winner_user_id: String = str(current_result_summary.get("winnerUserID", "")).strip_edges()
	if not winner_user_id.is_empty():
		return {
			"winner_user_id": winner_user_id,
			"placement": 1 if winner_user_id == local_user_id else 2,
			"outcome": "victory" if winner_user_id == local_user_id else "defeat",
		}
	var players_array := _as_array(effective_snapshot.get("players", []))
	if players_array.size() < 2:
		return {}
	for player_variant in players_array:
		if player_variant is Dictionary:
			var player: Dictionary = player_variant as Dictionary
			if _placement_from_player(player) <= 0:
				return {}
	var local_player: Dictionary = {}
	var opponent_player: Dictionary = {}
	for player_variant in players_array:
		if player_variant is Dictionary:
			var player: Dictionary = player_variant as Dictionary
			if str(player.get("userID", "")) == local_user_id:
				local_player = player
			else:
				opponent_player = player
	if local_player.is_empty() or opponent_player.is_empty():
		return {}
	var local_placement := _placement_from_player(local_player)
	var opponent_placement := _placement_from_player(opponent_player)
	if local_placement == opponent_placement:
		return {
			"winner_user_id": "",
			"placement": local_placement,
			"outcome": "draw",
		}
	return {
		"winner_user_id": str(local_player.get("userID", "")) if local_placement < opponent_placement else str(opponent_player.get("userID", "")),
		"placement": local_placement,
		"outcome": "victory" if local_placement < opponent_placement else "defeat",
	}


func get_fallback_results_outcome(local_score: int, snapshot: Dictionary = {}) -> Dictionary:
	var effective_snapshot: Dictionary = _effective_results_snapshot(snapshot)
	var opponent: Dictionary = get_opponent_snapshot(effective_snapshot)
	var opponent_score := 0
	if not opponent.is_empty():
		var final_score_variant: Variant = opponent.get("finalScore", null)
		opponent_score = int(final_score_variant) if final_score_variant != null else get_live_display_score_for_player(opponent)
	if local_score == opponent_score:
		return {
			"winner_user_id": "",
			"placement": 0,
			"outcome": "draw",
		}
	return {
		"winner_user_id": str(identity.get_current_identity().get("userID", "")) if local_score > opponent_score else str(opponent.get("userID", "")),
		"placement": 1 if local_score > opponent_score else 2,
		"outcome": "victory" if local_score > opponent_score else "lose",
	}
