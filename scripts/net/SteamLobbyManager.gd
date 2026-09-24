extends Node
class_name SteamLobbyManager

const GameModeConfig = preload("res://scripts/gameplay/GameModeConfig.gd")
const SteamLobbyProtocolScript = preload("res://scripts/net/SteamLobbyProtocol.gd")

const MAX_MEMBERS := 2
const LIVE_SCORE_INTERVAL_MS := 125
const RELIABLE_CHANNEL := 0
const LIVE_SCORE_CHANNEL := 1
const P2P_SEND_UNRELIABLE_NO_DELAY := 1
const P2P_SEND_RELIABLE := 2

signal auth_state_changed(identity: Dictionary)
signal players_changed(players: Array)
signal lobby_updated(lobby: Dictionary)
signal matchmaking_updated(payload: Dictionary)
signal start_time_received(start_time: float)
signal session_state_changed(active: bool, is_host: bool)
signal selection_changed(selection: Dictionary)
signal launch_requested(payload: Dictionary)
signal round_state_updated(snapshot: Dictionary)
signal error_raised(message: String)

var identity: IdentityService
var players: Array = []
var current_match: Dictionary = {}
var current_result_summary: Dictionary = {}
var current_selection: Dictionary = {
	"song_id": "",
	"difficulty": "",
	"mode": GameModeConfig.DEFAULT_MODE,
}
var shared_start_time: float = -1.0
var session_phase: String = "idle"
var active_flow: String = "steam_lobby"

var current_lobby_id: String = ""
var leader_steam_id: String = ""
var current_round_id: String = ""
var current_round_chart_hash: String = ""

var _last_live_submit_ms: int = 0
var _local_ready := false
var _pending_final_results: Dictionary = {}
var _last_sent_snapshot: Dictionary = {}


func _ready() -> void:
	set_process(true)


func setup(identity_service: IdentityService) -> void:
	identity = identity_service
	if identity != null and not identity.auth_state_changed.is_connected(_on_auth_state_changed):
		identity.auth_state_changed.connect(_on_auth_state_changed)
	_connect_steam_signals()


func is_available() -> bool:
	return not AppState.is_mobile_platform() and Engine.has_singleton("Steam") and SteamClient.is_ready()


func is_authenticated() -> bool:
	return identity != null and identity.is_authenticated()


func is_lobby_active() -> bool:
	return not current_lobby_id.is_empty()


func is_session_active() -> bool:
	return not current_round_id.is_empty() and session_phase in ["starting", "active", "finished"]


func is_hosting() -> bool:
	return is_party_leader()


func is_party_leader() -> bool:
	return is_lobby_active() and _local_steam_id() == leader_steam_id


func get_players() -> Array:
	return players.duplicate(true)


func get_current_selection() -> Dictionary:
	return current_selection.duplicate(true)


func get_current_phase() -> String:
	return session_phase


func get_active_flow() -> String:
	return "steam_lobby" if is_lobby_active() else "idle"


func get_current_round_snapshot() -> Dictionary:
	return current_match.duplicate(true)


func get_current_result_summary() -> Dictionary:
	return current_result_summary.duplicate(true)


func get_lobby_snapshot() -> Dictionary:
	return {
		"lobbyID": current_lobby_id,
		"leaderSteamID": leader_steam_id,
		"status": session_phase,
		"players": players.duplicate(true),
		"selection": current_selection.duplicate(true),
	}


func get_local_player_entry() -> Dictionary:
	var local_id := _local_steam_id()
	for player_variant in players:
		if player_variant is Dictionary:
			var player: Dictionary = player_variant as Dictionary
			if str(player.get("user_id", "")) == local_id:
				return player.duplicate(true)
	return {}


func create_party() -> void:
	if not is_available():
		error_raised.emit("Steam lobby multiplayer is unavailable until Steamworks is initialized.")
		return
	if not is_authenticated():
		error_raised.emit("Connect your account before creating a Steam party.")
		return
	SteamClient.allow_p2p_packet_relay(true)
	session_phase = "creating"
	matchmaking_updated.emit({"status": "creating", "flow": "steam_lobby"})
	SteamClient.create_steam_lobby(MAX_MEMBERS)


func join_party(lobby_id: String) -> void:
	var normalized_lobby_id := lobby_id.strip_edges()
	if normalized_lobby_id.is_empty():
		error_raised.emit("Steam lobby invite did not include a lobby ID.")
		return
	if not is_available():
		error_raised.emit("Steam lobby invite received, but Steamworks is not initialized.")
		return
	SteamClient.allow_p2p_packet_relay(true)
	session_phase = "joining"
	matchmaking_updated.emit({"status": "joining", "flow": "steam_lobby", "lobbyID": normalized_lobby_id})
	SteamClient.join_steam_lobby(normalized_lobby_id)


func leave_party(send_notice: bool = true) -> void:
	if send_notice and is_lobby_active():
		_broadcast_packet({
			"type": SteamLobbyProtocolScript.TYPE_LEAVE_NOTICE,
			"display_name": _local_display_name(),
		}, true)
	if is_lobby_active():
		SteamClient.leave_steam_lobby(current_lobby_id)
	_close_local_state()


func invite_friend(steam_id: String) -> bool:
	if not is_lobby_active():
		error_raised.emit("Create a Steam party before inviting friends.")
		return false
	var sent := SteamClient.invite_user_to_lobby(steam_id, current_lobby_id)
	if not sent:
		error_raised.emit("Direct Steam lobby invite failed. Try the Steam invite overlay.")
	return sent


func open_invite_overlay() -> Dictionary:
	if not is_lobby_active():
		return {"requested": false, "message": "Create a Steam party before opening the invite overlay."}
	return SteamClient.open_lobby_invite_overlay(current_lobby_id)


func set_song_selection(song_id: String, difficulty: String, mode: String) -> void:
	if not is_party_leader():
		error_raised.emit("Only the Steam party leader can change the song, mode, or difficulty.")
		return
	var safe_mode := mode if GameModeConfig.is_valid(mode) else GameModeConfig.DEFAULT_MODE
	if not _selection_is_valid(song_id, difficulty, safe_mode):
		error_raised.emit("That song, mode, or difficulty is not available locally.")
		return
	current_selection = {
		"song_id": song_id,
		"difficulty": difficulty,
		"mode": safe_mode,
	}
	_reset_ready_states()
	_write_lobby_settings()
	_broadcast_packet({
		"type": SteamLobbyProtocolScript.TYPE_SETTINGS_UPDATE,
		"song_id": song_id,
		"difficulty": difficulty,
		"mode": safe_mode,
	}, true)
	selection_changed.emit(get_current_selection())
	_emit_lobby_update("settings")
	_update_presence("Steam Party")


func set_ready_state(is_ready: bool) -> void:
	if not is_lobby_active():
		error_raised.emit("No Steam party is active.")
		return
	_local_ready = is_ready
	SteamClient.set_lobby_member_data(current_lobby_id, "ready", "1" if is_ready else "0")
	_update_player_ready(_local_steam_id(), is_ready)
	_broadcast_packet({
		"type": SteamLobbyProtocolScript.TYPE_READY_UPDATE,
		"ready": is_ready,
	}, true)
	_emit_lobby_update("ready")


func can_start_round() -> bool:
	if not is_party_leader():
		return false
	if players.size() != MAX_MEMBERS:
		return false
	if str(current_selection.get("song_id", "")).is_empty():
		return false
	for player_variant in players:
		if player_variant is Dictionary and not bool((player_variant as Dictionary).get("ready", false)):
			return false
	return _selection_is_valid(
		str(current_selection.get("song_id", "")),
		str(current_selection.get("difficulty", "")),
		str(current_selection.get("mode", GameModeConfig.DEFAULT_MODE))
	)


func start_round() -> void:
	if not can_start_round():
		error_raised.emit("Steam party needs two ready players and a valid selection before starting.")
		return
	current_round_id = "steam_%s_%d" % [current_lobby_id, Time.get_ticks_msec()]
	var planned_start_at_ms := int(Time.get_unix_time_from_system() * 1000.0) + 3000
	var packet := {
		"type": SteamLobbyProtocolScript.TYPE_ROUND_START,
		"round_id": current_round_id,
		"song_id": str(current_selection.get("song_id", "")),
		"difficulty": str(current_selection.get("difficulty", "")),
		"mode": str(current_selection.get("mode", GameModeConfig.DEFAULT_MODE)),
		"planned_start_at_ms": planned_start_at_ms,
	}
	_broadcast_packet(packet, true)
	_begin_round(packet)


func send_live_score(score: int, accuracy: float, combo: int) -> void:
	if current_round_id.is_empty():
		return
	var now_ms := Time.get_ticks_msec()
	if now_ms - _last_live_submit_ms < LIVE_SCORE_INTERVAL_MS:
		return
	_last_live_submit_ms = now_ms
	_apply_live_score(_local_steam_id(), score, accuracy, combo)
	_broadcast_packet({
		"type": SteamLobbyProtocolScript.TYPE_LIVE_SCORE,
		"round_id": current_round_id,
		"score": score,
		"accuracy": accuracy,
		"combo": combo,
		"timestamp": now_ms,
	}, false)


func complete_local_round(final_result: Dictionary) -> void:
	if current_round_id.is_empty():
		return
	var local_final := _final_player_payload(_local_steam_id(), _local_display_name(), final_result)
	_pending_final_results[_local_steam_id()] = local_final
	_apply_final_player(local_final)
	_broadcast_packet({
		"type": SteamLobbyProtocolScript.TYPE_FINAL_RESULT,
		"round_id": current_round_id,
		"final_result": local_final,
	}, true)
	if is_party_leader():
		_try_publish_result_snapshot()
	else:
		session_phase = "finished"
		session_state_changed.emit(false, false)
		_emit_lobby_update("finished")


func prepare_next_round() -> void:
	if not is_lobby_active():
		return
	current_round_id = ""
	current_round_chart_hash = ""
	_pending_final_results.clear()
	_last_sent_snapshot.clear()
	shared_start_time = -1.0
	session_phase = "lobby"
	_clear_player_round_scores()
	_reset_ready_states()
	current_match["status"] = "lobby"
	_emit_lobby_update("lobby")


func close_session() -> void:
	leave_party()


func get_opponent_snapshot(snapshot: Dictionary = {}) -> Dictionary:
	var effective_snapshot := _effective_results_snapshot(snapshot)
	var local_id := _local_steam_id()
	for player_variant in _as_array(effective_snapshot.get("players", [])):
		if player_variant is Dictionary:
			var player: Dictionary = player_variant as Dictionary
			if str(player.get("userID", "")) != local_id:
				return player.duplicate(true)
	return {}


func get_winner_display_name(snapshot: Dictionary = {}) -> String:
	var effective_snapshot := _effective_results_snapshot(snapshot)
	var outcome := get_results_outcome(effective_snapshot)
	var winner_id := str(outcome.get("winner_user_id", current_result_summary.get("winnerUserID", "")))
	if winner_id.is_empty():
		return ""
	for player_variant in _as_array(effective_snapshot.get("players", [])):
		if player_variant is Dictionary:
			var player: Dictionary = player_variant as Dictionary
			if str(player.get("userID", "")) == winner_id:
				return str(player.get("displayName", "Player"))
	return ""


func get_local_player_placement(snapshot: Dictionary = {}) -> int:
	var effective_snapshot := _effective_results_snapshot(snapshot)
	var local_id := _local_steam_id()
	for player_variant in _as_array(effective_snapshot.get("players", [])):
		if player_variant is Dictionary:
			var player: Dictionary = player_variant as Dictionary
			if str(player.get("userID", "")) == local_id:
				return _placement_from_player(player)
	return 0


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
	var final_score := float(final_score_variant)
	var live_score := float(player.get("liveScore", 0.0))
	if final_score > 0.0:
		return true
	return live_score <= 0.0 and _placement_from_player(player) > 0


func has_authoritative_results(snapshot: Dictionary = {}) -> bool:
	return not get_results_outcome(snapshot).is_empty()


func get_results_outcome(snapshot: Dictionary = {}) -> Dictionary:
	var effective_snapshot := _effective_results_snapshot(snapshot)
	var local_id := _local_steam_id()
	if local_id.is_empty():
		return {}
	var players_array := _as_array(effective_snapshot.get("players", []))
	if players_array.size() < 2:
		return {}
	var score_outcome := _score_based_results_outcome(local_id, players_array)
	if not score_outcome.is_empty():
		return score_outcome
	var winner_user_id := str(current_result_summary.get("winnerUserID", "")).strip_edges()
	if not winner_user_id.is_empty():
		return {
			"winner_user_id": winner_user_id,
			"placement": 1 if winner_user_id == local_id else 2,
			"outcome": "victory" if winner_user_id == local_id else "defeat",
		}
	return {}


func get_fallback_results_outcome(local_score: int, snapshot: Dictionary = {}) -> Dictionary:
	var opponent := get_opponent_snapshot(snapshot)
	var opponent_score := 0
	if not opponent.is_empty():
		var final_score_variant: Variant = opponent.get("finalScore", null)
		opponent_score = int(final_score_variant) if final_score_variant != null else get_live_display_score_for_player(opponent)
	if local_score == opponent_score:
		return {"winner_user_id": "", "placement": 0, "outcome": "draw"}
	return {
		"winner_user_id": _local_steam_id() if local_score > opponent_score else str(opponent.get("userID", "")),
		"placement": 1 if local_score > opponent_score else 2,
		"outcome": "victory" if local_score > opponent_score else "defeat",
	}


func _process(_delta: float) -> void:
	if not is_lobby_active() or not SteamClient.is_ready():
		return
	_poll_p2p_channel(RELIABLE_CHANNEL)
	_poll_p2p_channel(LIVE_SCORE_CHANNEL)


func _connect_steam_signals() -> void:
	if not SteamClient.steam_lobby_created.is_connected(_on_steam_lobby_created):
		SteamClient.steam_lobby_created.connect(_on_steam_lobby_created)
	if not SteamClient.steam_lobby_joined.is_connected(_on_steam_lobby_joined):
		SteamClient.steam_lobby_joined.connect(_on_steam_lobby_joined)
	if not SteamClient.steam_lobby_chat_updated.is_connected(_on_steam_lobby_chat_updated):
		SteamClient.steam_lobby_chat_updated.connect(_on_steam_lobby_chat_updated)
	if not SteamClient.steam_lobby_data_updated.is_connected(_on_steam_lobby_data_updated):
		SteamClient.steam_lobby_data_updated.connect(_on_steam_lobby_data_updated)
	if not SteamClient.steam_lobby_kicked.is_connected(_on_steam_lobby_kicked):
		SteamClient.steam_lobby_kicked.connect(_on_steam_lobby_kicked)
	if not SteamClient.steam_p2p_session_requested.is_connected(_on_p2p_session_requested):
		SteamClient.steam_p2p_session_requested.connect(_on_p2p_session_requested)


func _on_auth_state_changed(new_identity: Dictionary) -> void:
	auth_state_changed.emit(new_identity.duplicate(true))
	if is_lobby_active():
		_write_local_member_data()
		_sync_members_from_lobby()


func _on_steam_lobby_created(success: bool, lobby_id: String) -> void:
	if not success:
		session_phase = "idle"
		error_raised.emit("Steam lobby creation failed.")
		return
	current_lobby_id = lobby_id
	leader_steam_id = _local_steam_id()
	session_phase = "lobby"
	SteamClient.set_lobby_data(current_lobby_id, "hd_protocol", str(SteamLobbyProtocolScript.VERSION))
	SteamClient.set_lobby_data(current_lobby_id, "hd_leader", leader_steam_id)
	SteamClient.set_lobby_data(current_lobby_id, "hd_status", session_phase)
	SteamClient.set_lobby_data(current_lobby_id, "hd_max_members", str(MAX_MEMBERS))
	_write_lobby_settings()
	_write_local_member_data()
	_sync_members_from_lobby()
	_broadcast_packet({"type": SteamLobbyProtocolScript.TYPE_HELLO, "display_name": _local_display_name()}, true)
	_emit_lobby_update("created")
	_update_presence("Steam Party")


func _on_steam_lobby_joined(lobby_id: String, response: int) -> void:
	if response != 1 and response != 0:
		error_raised.emit("Unable to join Steam lobby. Response: %d" % response)
		return
	current_lobby_id = lobby_id
	leader_steam_id = SteamClient.get_lobby_owner(current_lobby_id)
	if leader_steam_id.is_empty():
		leader_steam_id = str(SteamClient.get_lobby_data(current_lobby_id, "hd_leader"))
	session_phase = str(SteamClient.get_lobby_data(current_lobby_id, "hd_status")).strip_edges()
	if session_phase.is_empty() or session_phase == "creating" or session_phase == "joining":
		session_phase = "lobby"
	_read_lobby_settings()
	_write_local_member_data()
	_sync_members_from_lobby()
	_broadcast_packet({"type": SteamLobbyProtocolScript.TYPE_HELLO, "display_name": _local_display_name()}, true)
	_emit_lobby_update("joined")
	_update_presence("Steam Party")


func _on_steam_lobby_chat_updated(lobby_id: String, _changed_id: String, _making_change_id: String, _state: int) -> void:
	if lobby_id != current_lobby_id:
		return
	_sync_members_from_lobby()
	if is_lobby_active() and players.size() < MAX_MEMBERS and not is_party_leader():
		error_raised.emit("Steam party leader left. The Steam party has ended.")
		leave_party(false)


func _on_steam_lobby_data_updated(lobby_id: String, _member_id: String, _success: bool) -> void:
	if lobby_id != current_lobby_id:
		return
	leader_steam_id = SteamClient.get_lobby_owner(current_lobby_id)
	_read_lobby_settings()
	_sync_members_from_lobby()
	_emit_lobby_update("data")


func _on_steam_lobby_kicked(lobby_id: String, _admin_id: String, _due_to_disconnect: bool) -> void:
	if lobby_id != current_lobby_id:
		return
	error_raised.emit("You were removed from the Steam party.")
	_close_local_state()


func _on_p2p_session_requested(steam_id: String) -> void:
	if _is_member(steam_id):
		SteamClient.accept_p2p_session(steam_id)


func _poll_p2p_channel(channel: int) -> void:
	for packet in SteamClient.read_p2p_packets(channel, 16):
		if packet is Dictionary:
			_handle_p2p_packet(packet as Dictionary)


func _handle_p2p_packet(packet_payload: Dictionary) -> void:
	var sender_id := str(packet_payload.get("steam_id", "")).strip_edges()
	if not _is_member(sender_id):
		return
	var packet := SteamLobbyProtocolScript.decode(packet_payload.get("data", PackedByteArray()))
	if packet.is_empty():
		return
	var packet_type := str(packet.get("type", ""))
	if not SteamLobbyProtocolScript.sender_allowed(packet_type, sender_id, leader_steam_id):
		return
	if SteamLobbyProtocolScript.packet_requires_active_round(packet_type) and SteamLobbyProtocolScript.has_stale_round(packet, current_round_id):
		return
	match packet_type:
		SteamLobbyProtocolScript.TYPE_HELLO:
			_sync_members_from_lobby()
		SteamLobbyProtocolScript.TYPE_SETTINGS_UPDATE:
			_apply_settings_packet(packet)
		SteamLobbyProtocolScript.TYPE_READY_UPDATE:
			_update_player_ready(sender_id, bool(packet.get("ready", false)))
			_emit_lobby_update("ready")
		SteamLobbyProtocolScript.TYPE_ROUND_START:
			_begin_round(packet)
		SteamLobbyProtocolScript.TYPE_LIVE_SCORE:
			_apply_live_score(sender_id, int(packet.get("score", 0)), float(packet.get("accuracy", 0.0)), int(packet.get("combo", 0)))
		SteamLobbyProtocolScript.TYPE_FINAL_RESULT:
			_apply_remote_final_result(sender_id, packet)
		SteamLobbyProtocolScript.TYPE_RESULT_SNAPSHOT:
			_apply_result_snapshot(packet.get("snapshot", {}))
		SteamLobbyProtocolScript.TYPE_LEAVE_NOTICE:
			_sync_members_from_lobby()


func _broadcast_packet(packet: Dictionary, reliable: bool) -> void:
	if not is_lobby_active():
		return
	var data := SteamLobbyProtocolScript.encode(packet)
	var channel := RELIABLE_CHANNEL if reliable else LIVE_SCORE_CHANNEL
	var send_type := P2P_SEND_RELIABLE if reliable else P2P_SEND_UNRELIABLE_NO_DELAY
	var local_id := _local_steam_id()
	for member_id in SteamClient.get_lobby_members(current_lobby_id):
		if member_id == local_id:
			continue
		SteamClient.send_p2p_packet(member_id, data, send_type, channel)


func _begin_round(packet: Dictionary) -> void:
	var song_id := str(packet.get("song_id", "")).strip_edges()
	var difficulty := str(packet.get("difficulty", "")).strip_edges()
	var mode := str(packet.get("mode", GameModeConfig.DEFAULT_MODE)).strip_edges()
	if not _selection_is_valid(song_id, difficulty, mode):
		error_raised.emit("Steam round start was ignored because the selected song is not available locally.")
		return
	current_round_id = str(packet.get("round_id", current_round_id)).strip_edges()
	current_round_chart_hash = ""
	current_selection = {"song_id": song_id, "difficulty": difficulty, "mode": mode}
	_pending_final_results.clear()
	_last_sent_snapshot.clear()
	current_result_summary.clear()
	shared_start_time = float(int(packet.get("planned_start_at_ms", 0))) / 1000.0
	session_phase = "active"
	current_match = {
		"matchID": current_round_id,
		"roundID": current_round_id,
		"status": "active",
		"players": _players_for_snapshot(),
	}
	selection_changed.emit(get_current_selection())
	start_time_received.emit(shared_start_time)
	session_state_changed.emit(true, is_party_leader())
	round_state_updated.emit(current_match.duplicate(true))
	_emit_lobby_update("active")
	_update_presence("Playing Steam Multiplayer")
	launch_requested.emit({
		"song_id": song_id,
		"difficulty": difficulty,
		"mode": mode,
		"match_id": current_round_id,
		"round_id": current_round_id,
		"planned_start_at_ms": int(packet.get("planned_start_at_ms", 0)),
		"steam_lobby_id": current_lobby_id,
		"backend": "steam_lobby",
	})


func _apply_settings_packet(packet: Dictionary) -> void:
	var song_id := str(packet.get("song_id", "")).strip_edges()
	var difficulty := str(packet.get("difficulty", "")).strip_edges()
	var mode := str(packet.get("mode", GameModeConfig.DEFAULT_MODE)).strip_edges()
	if not _selection_is_valid(song_id, difficulty, mode):
		error_raised.emit("Steam party selection is not available locally.")
		return
	current_selection = {"song_id": song_id, "difficulty": difficulty, "mode": mode}
	_reset_ready_states(false)
	selection_changed.emit(get_current_selection())
	_emit_lobby_update("settings")


func _apply_live_score(sender_id: String, score: int, accuracy: float, combo: int) -> void:
	for index in players.size():
		var player: Dictionary = players[index] as Dictionary
		if str(player.get("user_id", "")) != sender_id:
			continue
		player["live_score"] = score
		player["liveScore"] = score
		player["liveAccuracy"] = accuracy
		player["live_combo"] = combo
		player["liveCombo"] = combo
		players[index] = player
		break
	current_match["players"] = _players_for_snapshot()
	round_state_updated.emit(current_match.duplicate(true))
	players_changed.emit(get_players())


func _apply_remote_final_result(sender_id: String, packet: Dictionary) -> void:
	var final_result_variant: Variant = packet.get("final_result", {})
	if not (final_result_variant is Dictionary):
		return
	var final_result: Dictionary = (final_result_variant as Dictionary).duplicate(true)
	final_result["userID"] = sender_id
	_pending_final_results[sender_id] = final_result
	_apply_final_player(final_result)
	if is_party_leader():
		_try_publish_result_snapshot()


func _apply_final_player(final_player: Dictionary) -> void:
	var player_id := str(final_player.get("userID", final_player.get("user_id", "")))
	for index in players.size():
		var player: Dictionary = players[index] as Dictionary
		if str(player.get("user_id", "")) != player_id:
			continue
		for key_variant in final_player.keys():
			player[str(key_variant)] = final_player[key_variant]
		player["final_score"] = final_player.get("finalScore", player.get("final_score", null))
		players[index] = player
		break
	current_match["players"] = _players_for_snapshot()
	round_state_updated.emit(current_match.duplicate(true))
	players_changed.emit(get_players())


func _try_publish_result_snapshot() -> void:
	if _pending_final_results.size() < MAX_MEMBERS:
		return
	var snapshot := SteamLobbyProtocolScript.build_result_snapshot(current_round_id, current_round_id, _players_for_snapshot())
	current_result_summary = snapshot.duplicate(true)
	current_match = snapshot.duplicate(true)
	_last_sent_snapshot = snapshot.duplicate(true)
	session_phase = "finished"
	_broadcast_packet({
		"type": SteamLobbyProtocolScript.TYPE_RESULT_SNAPSHOT,
		"round_id": current_round_id,
		"snapshot": snapshot,
	}, true)
	round_state_updated.emit(current_match.duplicate(true))
	players_changed.emit(get_players())
	session_state_changed.emit(false, true)
	_emit_lobby_update("finished")
	_update_presence("Viewing Steam Results")


func _apply_result_snapshot(snapshot_variant: Variant) -> void:
	if not (snapshot_variant is Dictionary):
		return
	var snapshot: Dictionary = (snapshot_variant as Dictionary).duplicate(true)
	if str(snapshot.get("roundID", snapshot.get("round_id", ""))) != current_round_id:
		return
	current_result_summary = snapshot.duplicate(true)
	current_match = snapshot.duplicate(true)
	session_phase = "finished"
	_sync_players_from_snapshot(snapshot)
	round_state_updated.emit(current_match.duplicate(true))
	session_state_changed.emit(false, false)
	_emit_lobby_update("finished")
	_update_presence("Viewing Steam Results")


func _write_lobby_settings() -> void:
	if not is_lobby_active():
		return
	SteamClient.set_lobby_data(current_lobby_id, "hd_song_id", str(current_selection.get("song_id", "")))
	SteamClient.set_lobby_data(current_lobby_id, "hd_difficulty", str(current_selection.get("difficulty", "")))
	SteamClient.set_lobby_data(current_lobby_id, "hd_mode", str(current_selection.get("mode", GameModeConfig.DEFAULT_MODE)))
	SteamClient.set_lobby_data(current_lobby_id, "hd_status", session_phase)


func _read_lobby_settings() -> void:
	if not is_lobby_active():
		return
	var song_id := str(SteamClient.get_lobby_data(current_lobby_id, "hd_song_id")).strip_edges()
	var difficulty := str(SteamClient.get_lobby_data(current_lobby_id, "hd_difficulty")).strip_edges()
	var mode := str(SteamClient.get_lobby_data(current_lobby_id, "hd_mode")).strip_edges()
	if not GameModeConfig.is_valid(mode):
		mode = GameModeConfig.DEFAULT_MODE
	current_selection = {"song_id": song_id, "difficulty": difficulty, "mode": mode}
	selection_changed.emit(get_current_selection())


func _write_local_member_data() -> void:
	if not is_lobby_active():
		return
	SteamClient.set_lobby_member_data(current_lobby_id, "display_name", _local_display_name())
	SteamClient.set_lobby_member_data(current_lobby_id, "ready", "1" if _local_ready else "0")


func _sync_members_from_lobby() -> void:
	if not is_lobby_active():
		return
	var current_members := SteamClient.get_lobby_members(current_lobby_id)
	var synced_players: Array = []
	for member_id in current_members:
		var display_name := str(SteamClient.get_lobby_member_data(current_lobby_id, member_id, "display_name")).strip_edges()
		if display_name.is_empty():
			display_name = SteamClient.get_friend_display_name(member_id)
		if display_name.is_empty():
			display_name = "Steam Player"
		var ready := str(SteamClient.get_lobby_member_data(current_lobby_id, member_id, "ready")) == "1"
		var existing := _player_by_id(member_id)
		synced_players.append(_merge_player_entry(existing, {
			"user_id": member_id,
			"userID": member_id,
			"display_name": display_name,
			"displayName": display_name,
			"ready": ready,
			"is_ready": ready,
			"isConnected": true,
			"is_connected": true,
			"selected_song_id": str(current_selection.get("song_id", "")),
		}))
	players = synced_players
	current_match["players"] = _players_for_snapshot()
	players_changed.emit(get_players())


func _sync_players_from_snapshot(snapshot: Dictionary) -> void:
	var snapshot_players := _as_array(snapshot.get("players", []))
	for snapshot_player_variant in snapshot_players:
		if snapshot_player_variant is Dictionary:
			var snapshot_player: Dictionary = snapshot_player_variant as Dictionary
			_apply_final_player(snapshot_player)


func _reset_ready_states(broadcast: bool = true) -> void:
	_local_ready = false
	if is_lobby_active():
		SteamClient.set_lobby_member_data(current_lobby_id, "ready", "0")
	for index in players.size():
		var player: Dictionary = players[index] as Dictionary
		player["ready"] = false
		player["is_ready"] = false
		players[index] = player
	if broadcast:
		_broadcast_packet({"type": SteamLobbyProtocolScript.TYPE_READY_UPDATE, "ready": false}, true)
	players_changed.emit(get_players())


func _clear_player_round_scores() -> void:
	for index in players.size():
		var player: Dictionary = players[index] as Dictionary
		for key in ["live_score", "liveScore", "liveAccuracy", "live_combo", "liveCombo", "final_score", "finalScore", "finalAccuracy", "finalMaxCombo", "finalPlacement", "placement"]:
			player.erase(key)
		players[index] = player


func _update_player_ready(steam_id: String, ready: bool) -> void:
	for index in players.size():
		var player: Dictionary = players[index] as Dictionary
		if str(player.get("user_id", "")) != steam_id:
			continue
		player["ready"] = ready
		player["is_ready"] = ready
		players[index] = player
		break
	players_changed.emit(get_players())


func _selection_is_valid(song_id: String, difficulty: String, mode: String) -> bool:
	if song_id.strip_edges().is_empty() or difficulty.strip_edges().is_empty():
		return false
	if not GameModeConfig.is_valid(mode):
		return false
	var song := ContentRegistry.get_song(song_id)
	if song.is_empty():
		return false
	if not ProgressionManager.is_song_multiplayer_accessible(song_id):
		return false
	if not ContentRegistry.get_supported_modes(song).has(mode):
		return false
	return ContentRegistry.get_supported_difficulties(song, mode).has(difficulty)


func _emit_lobby_update(reason: String) -> void:
	var snapshot := get_lobby_snapshot()
	snapshot["reason"] = reason
	lobby_updated.emit(snapshot.duplicate(true))
	matchmaking_updated.emit(snapshot.duplicate(true))


func _update_presence(status: String) -> void:
	if not SteamClient.is_ready():
		return
	SteamClient.set_multiplayer_presence(
		status,
		str(current_selection.get("difficulty", "")),
		str(current_selection.get("mode", GameModeConfig.DEFAULT_MODE)),
		"",
		current_lobby_id,
		players.size()
	)


func _close_local_state() -> void:
	players.clear()
	current_match.clear()
	current_result_summary.clear()
	current_selection = {"song_id": "", "difficulty": "", "mode": GameModeConfig.DEFAULT_MODE}
	shared_start_time = -1.0
	session_phase = "idle"
	current_lobby_id = ""
	leader_steam_id = ""
	current_round_id = ""
	current_round_chart_hash = ""
	_local_ready = false
	_pending_final_results.clear()
	_last_sent_snapshot.clear()
	players_changed.emit(get_players())
	selection_changed.emit(get_current_selection())
	session_state_changed.emit(false, false)
	_emit_lobby_update("closed")
	if SteamClient.is_ready():
		SteamClient.set_menu_presence("In Multiplayer Menu")


func _final_player_payload(player_id: String, display_name: String, final_result: Dictionary) -> Dictionary:
	return {
		"userID": player_id,
		"user_id": player_id,
		"displayName": display_name,
		"display_name": display_name,
		"ready": true,
		"is_ready": true,
		"isConnected": true,
		"finalScore": int(final_result.get("score", 0)),
		"finalAccuracy": float(final_result.get("accuracy", 0.0)),
		"finalMaxCombo": int(final_result.get("max_combo", 0)),
		"finalPerfect": int(final_result.get("perfect", 0)),
		"finalGreat": int(final_result.get("great", 0)),
		"finalGood": int(final_result.get("good", 0)),
		"finalMiss": int(final_result.get("miss", 0)),
		"chartHash": str(final_result.get("chart_hash", current_round_chart_hash)),
		"liveScore": int(final_result.get("score", 0)),
		"liveAccuracy": float(final_result.get("accuracy", 0.0)),
		"liveCombo": int(final_result.get("max_combo", 0)),
	}


func _players_for_snapshot() -> Array:
	var snapshot_players: Array = []
	for player_variant in players:
		if player_variant is Dictionary:
			var player: Dictionary = (player_variant as Dictionary).duplicate(true)
			player["userID"] = str(player.get("userID", player.get("user_id", "")))
			player["displayName"] = str(player.get("displayName", player.get("display_name", "Player")))
			player["ready"] = bool(player.get("ready", player.get("is_ready", false)))
			player["isConnected"] = bool(player.get("isConnected", player.get("is_connected", true)))
			player["liveScore"] = int(player.get("liveScore", player.get("live_score", 0)))
			player["liveCombo"] = int(player.get("liveCombo", player.get("live_combo", 0)))
			snapshot_players.append(player)
	return snapshot_players


func _merge_player_entry(existing: Dictionary, incoming: Dictionary) -> Dictionary:
	var merged := existing.duplicate(true)
	for key_variant in incoming.keys():
		merged[str(key_variant)] = incoming[key_variant]
	return merged


func _player_by_id(player_id: String) -> Dictionary:
	for player_variant in players:
		if player_variant is Dictionary:
			var player: Dictionary = player_variant as Dictionary
			if str(player.get("user_id", "")) == player_id:
				return player.duplicate(true)
	return {}


func _is_member(steam_id: String) -> bool:
	if steam_id.strip_edges().is_empty():
		return false
	for member_id in SteamClient.get_lobby_members(current_lobby_id):
		if member_id == steam_id:
			return true
	return false


func _local_steam_id() -> String:
	return SteamClient.get_steam_id()


func _local_display_name() -> String:
	var display_name := ""
	if identity != null:
		display_name = str(identity.get_current_identity().get("displayName", "")).strip_edges()
	if display_name.is_empty():
		display_name = SteamClient.get_persona_name()
	if display_name.is_empty():
		display_name = "Steam Player"
	return display_name


func _effective_results_snapshot(snapshot: Dictionary) -> Dictionary:
	if not snapshot.is_empty():
		return snapshot
	if not current_result_summary.is_empty():
		return current_result_summary
	return current_match


func _placement_from_player(player: Dictionary) -> int:
	if player.get("finalPlacement", null) != null:
		return int(player.get("finalPlacement", 0))
	if player.get("placement", null) != null:
		return int(player.get("placement", 0))
	return 0


func _score_based_results_outcome(local_user_id: String, players_array: Array) -> Dictionary:
	if players_array.size() < 2:
		return {}
	for player_variant in players_array:
		if not (player_variant is Dictionary):
			return {}
		if not has_trustworthy_final_score(player_variant as Dictionary):
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
		return {"winner_user_id": "", "placement": 0, "outcome": "draw"}
	return {
		"winner_user_id": str(local_player.get("userID", "")) if local_score > opponent_score else str(opponent_player.get("userID", "")),
		"placement": 1 if local_score > opponent_score else 2,
		"outcome": "victory" if local_score > opponent_score else "defeat",
	}


func _as_array(value: Variant) -> Array:
	if value is Array:
		return (value as Array).duplicate(true)
	return []
