extends Node

const VISUALIZER_REACTIVE_PLAYER := "player"
const VISUALIZER_REACTIVE_CHART := "chart"

const GameModeConfig = preload("res://scripts/gameplay/GameModeConfig.gd")
const IdentityService = preload("res://scripts/net/IdentityService.gd")
const LeaderboardService = preload("res://scripts/net/LeaderboardService.gd")
const LaneCountResolver = preload("res://scripts/songs/LaneCountResolver.gd")
const MultiplayerManager = preload("res://scripts/net/MultiplayerManager.gd")
const SteamLobbyManager = preload("res://scripts/net/SteamLobbyManager.gd")

signal show_title_requested
signal show_song_select_requested
signal show_visualizer_select_requested
signal show_practice_select_requested
signal show_info_requested(payload: Dictionary)
signal show_settings_requested
signal show_calibration_requested
signal show_progression_requested
signal show_shop_requested
signal show_track_store_requested
signal show_multiplayer_requested
signal show_leaderboards_requested
signal show_stats_requested
signal show_chart_editor_requested
signal show_local_songs_requested
signal show_community_charts_requested
signal start_game_requested(song_entry: Dictionary, difficulty: String, mode: String)
signal show_results_requested(result: Dictionary)
signal steam_availability_changed(ready: bool)

var identity_service
var leaderboard_service
var match_service
var steam_lobby_service

var current_song: Dictionary = {}
var current_difficulty: String = "Medium"
var current_mode: String = GameModeConfig.DEFAULT_MODE
var current_loadout: Dictionary = {}
var current_run_forced_no_fail := false
var visualizer_active := false
var practice_active := false
var visualizer_reactive_mode := VISUALIZER_REACTIVE_PLAYER
var _visualizer_queue: Array[Dictionary] = []
var _visualizer_last_song_id := ""
var multiplayer_context: Dictionary = {}
var _pending_startup_route: String = ""


func _ready() -> void:
	identity_service = IdentityService.new()
	add_child(identity_service)
	leaderboard_service = LeaderboardService.new()
	add_child(leaderboard_service)
	leaderboard_service.setup(identity_service)
	match_service = MultiplayerManager.new()
	add_child(match_service)
	match_service.setup(identity_service)
	match_service.launch_requested.connect(_on_multiplayer_launch_requested)
	steam_lobby_service = SteamLobbyManager.new()
	add_child(steam_lobby_service)
	steam_lobby_service.setup(identity_service)
	steam_lobby_service.launch_requested.connect(_on_multiplayer_launch_requested)
	if SteamClient.has_signal("steam_ready_changed") and not SteamClient.steam_ready_changed.is_connected(_on_steam_ready_changed):
		SteamClient.steam_ready_changed.connect(_on_steam_ready_changed)
	if not SteamClient.steam_invite_join_requested.is_connected(_on_steam_invite_join_requested):
		SteamClient.steam_invite_join_requested.connect(_on_steam_invite_join_requested)
	if not SteamClient.steam_lobby_join_requested.is_connected(_on_steam_lobby_join_requested):
		SteamClient.steam_lobby_join_requested.connect(_on_steam_lobby_join_requested)
	sync_input_actions()
	call_deferred("_warm_identity_on_launch")


func sync_input_actions(lane_count: int = LaneCountResolver.DEFAULT_LANES) -> void:
	var active_lane_count := LaneCountResolver.clamp_lane_count(lane_count)
	var key_bindings: Dictionary = ProfileStore.get_key_bindings(active_lane_count)
	var controller_bindings: Dictionary = ProfileStore.get_controller_bindings()
	for lane in range(LaneCountResolver.MAX_LANES):
		var action := "lane_%d" % lane
		_reset_action_events(action)
		if lane < active_lane_count and key_bindings.has(action):
			InputMap.action_add_event(action, _key_event(int(key_bindings[action])))
		if lane < active_lane_count:
			_add_controller_binding_event(action, controller_bindings.get(action, {}))
	_sync_navigation_actions(controller_bindings)


func _sync_navigation_actions(controller_bindings: Dictionary) -> void:
	_configure_action(
		"ui_accept",
		[_key_event(KEY_ENTER), _key_event(KEY_KP_ENTER), _key_event(KEY_SPACE)],
		[_controller_event_for_binding(controller_bindings.get("ui_accept", {}))]
	)
	_configure_action(
		"ui_cancel",
		[_key_event(KEY_ESCAPE)],
		[_controller_event_for_binding(controller_bindings.get("ui_cancel", {}))]
	)
	_configure_action(
		"ui_up",
		[_key_event(KEY_UP)],
		[_controller_event_for_binding(controller_bindings.get("ui_up", {}))],
		[_joypad_motion_event(JOY_AXIS_LEFT_Y, -1.0)]
	)
	_configure_action(
		"ui_down",
		[_key_event(KEY_DOWN)],
		[_controller_event_for_binding(controller_bindings.get("ui_down", {}))],
		[_joypad_motion_event(JOY_AXIS_LEFT_Y, 1.0)]
	)
	_configure_action(
		"ui_left",
		[_key_event(KEY_LEFT)],
		[_controller_event_for_binding(controller_bindings.get("ui_left", {}))],
		[_joypad_motion_event(JOY_AXIS_LEFT_X, -1.0)]
	)
	_configure_action(
		"ui_right",
		[_key_event(KEY_RIGHT)],
		[_controller_event_for_binding(controller_bindings.get("ui_right", {}))],
		[_joypad_motion_event(JOY_AXIS_LEFT_X, 1.0)]
	)


func _configure_action(action: String, key_events: Array, joypad_button_events: Array = [], joypad_motion_events: Array = []) -> void:
	_reset_action_events(action)
	for event in key_events:
		if event != null:
			InputMap.action_add_event(action, event)
	for event in joypad_button_events:
		if event != null:
			InputMap.action_add_event(action, event)
	for event in joypad_motion_events:
		if event != null:
			InputMap.action_add_event(action, event)


func _reset_action_events(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for event in InputMap.action_get_events(action):
		InputMap.action_erase_event(action, event)


func _key_event(physical_keycode: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = physical_keycode
	return event


func _joypad_button_event(button_index: int) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button_index
	return event


func _joypad_motion_event(axis: int, axis_value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = axis_value
	return event


func _add_controller_binding_event(action: String, binding_variant: Variant) -> void:
	var event: Variant = _controller_event_for_binding(binding_variant)
	if event != null:
		InputMap.action_add_event(action, event)


func _controller_event_for_binding(binding_variant: Variant) -> Variant:
	if binding_variant is not Dictionary:
		return null
	var binding: Dictionary = binding_variant as Dictionary
	var kind: String = str(binding.get("kind", "")).to_lower()
	if kind == "axis":
		var direction: float = -1.0 if float(binding.get("direction", 1.0)) < 0.0 else 1.0
		var threshold: float = clampf(absf(float(binding.get("threshold", 0.5))), 0.1, 1.0)
		return _joypad_motion_event(int(binding.get("axis", JOY_AXIS_LEFT_X)), direction * threshold)
	if kind == "button":
		return _joypad_button_event(int(binding.get("button_index", JOY_BUTTON_A)))
	return null


func request_title() -> void:
	_clear_visualizer_session()
	_clear_practice_session()
	_clear_temporary_run_flags()
	_set_steam_menu_presence("In Menus")
	show_title_requested.emit()


func request_song_select() -> void:
	_clear_visualizer_session()
	_clear_practice_session()
	_clear_temporary_run_flags()
	_set_steam_menu_presence("Choosing Song")
	show_song_select_requested.emit()


func request_visualizer_select() -> void:
	_clear_practice_session()
	_clear_visualizer_session()
	_clear_temporary_run_flags()
	_set_steam_menu_presence("Choosing Visualizer Music")
	show_visualizer_select_requested.emit()


func request_practice_select() -> void:
	_clear_visualizer_session()
	practice_active = true
	_clear_temporary_run_flags()
	_set_steam_menu_presence("Choosing Practice Song")
	show_practice_select_requested.emit()


func start_visualizer_shuffle(reactive_mode: String = VISUALIZER_REACTIVE_PLAYER) -> void:
	_clear_practice_session()
	visualizer_reactive_mode = normalize_visualizer_reactive_mode(reactive_mode)
	var songs := _get_visualizer_session_songs()
	if songs.is_empty():
		request_info("VISUALIZER MODE", "No playable songs are available for that reactive mode.")
		return
	visualizer_active = true
	_visualizer_last_song_id = ""
	_visualizer_queue = songs.duplicate(true)
	_visualizer_queue.shuffle()
	_start_next_visualizer_song()


func start_visualizer_song(song_entry: Dictionary, reactive_mode: String = VISUALIZER_REACTIVE_PLAYER) -> void:
	_clear_practice_session()
	if song_entry.is_empty() or not _is_visualizer_song_available(song_entry):
		request_info("VISUALIZER MODE", "That song is not currently available for Visualizer Mode.")
		return
	visualizer_reactive_mode = normalize_visualizer_reactive_mode(reactive_mode)
	if visualizer_reactive_mode == VISUALIZER_REACTIVE_CHART and _visualizer_chart_difficulty(song_entry).is_empty():
		request_info("VISUALIZER MODE", "That song does not have a chart available for Chart Reactive.")
		return
	visualizer_active = true
	_visualizer_last_song_id = ""
	_rebuild_visualizer_queue(str(song_entry.get("id", "")), true)
	_start_visualizer_song_entry(song_entry)


func advance_visualizer_song() -> void:
	if not visualizer_active:
		return
	_start_next_visualizer_song()


func get_visualizer_songs() -> Array[Dictionary]:
	var available: Array[Dictionary] = []
	for song in ContentRegistry.get_progression_ordered_songs():
		if _is_visualizer_song_available(song):
			available.append(song.duplicate(true))
	return available


func normalize_visualizer_reactive_mode(reactive_mode: String) -> String:
	if reactive_mode.strip_edges().to_lower() == VISUALIZER_REACTIVE_CHART:
		return VISUALIZER_REACTIVE_CHART
	return VISUALIZER_REACTIVE_PLAYER


func _get_visualizer_session_songs() -> Array[Dictionary]:
	var available := get_visualizer_songs()
	if visualizer_reactive_mode != VISUALIZER_REACTIVE_CHART:
		return available
	var charted: Array[Dictionary] = []
	for song in available:
		if not _visualizer_chart_difficulty(song).is_empty():
			charted.append(song)
	return charted


func _visualizer_chart_difficulty(song_entry: Dictionary) -> String:
	var supported := ContentRegistry.get_supported_difficulties(song_entry, GameModeConfig.STEMS_MAPPED)
	if supported.has("Professional"):
		return "Professional"
	return ""


func _is_visualizer_song_available(song_entry: Dictionary) -> bool:
	if str(song_entry.get("audio_path", "")).strip_edges().is_empty():
		return false
	var song_id := str(song_entry.get("id", ""))
	if PremiumStore != null and PremiumStore.is_android_store_enabled() and PremiumStore.is_premium_song(song_id):
		return PremiumStore.is_song_playable(song_id)
	return true


func _start_next_visualizer_song() -> void:
	if _visualizer_queue.is_empty():
		_rebuild_visualizer_queue(_visualizer_last_song_id)
	if _visualizer_queue.is_empty():
		request_visualizer_select()
		return
	var next_song: Dictionary = _visualizer_queue.pop_front()
	_start_visualizer_song_entry(next_song)


func _rebuild_visualizer_queue(avoid_first_song_id: String = "", omit_song: bool = false) -> void:
	_visualizer_queue.clear()
	for song in _get_visualizer_session_songs():
		if omit_song and not avoid_first_song_id.is_empty() and str(song.get("id", "")) == avoid_first_song_id:
			continue
		_visualizer_queue.append(song.duplicate(true))
	_visualizer_queue.shuffle()
	if _visualizer_queue.size() > 1 and not avoid_first_song_id.is_empty() and str(_visualizer_queue[0].get("id", "")) == avoid_first_song_id:
		var swap_index := randi_range(1, _visualizer_queue.size() - 1)
		var first_song := _visualizer_queue[0]
		_visualizer_queue[0] = _visualizer_queue[swap_index]
		_visualizer_queue[swap_index] = first_song


func _start_visualizer_song_entry(song_entry: Dictionary) -> void:
	current_song = song_entry.duplicate(true)
	current_difficulty = _visualizer_chart_difficulty(song_entry) if visualizer_reactive_mode == VISUALIZER_REACTIVE_CHART else "Medium"
	current_mode = GameModeConfig.STEMS_MAPPED
	current_loadout = ProgressionManager.get_equipped_loadout()
	current_run_forced_no_fail = true
	current_loadout["forced_no_fail"] = true
	current_loadout["practice_forced_no_fail"] = true
	current_loadout["ranked"] = false
	_visualizer_last_song_id = str(song_entry.get("id", ""))
	ProfileStore.set_visualizer_selected_song_id(_visualizer_last_song_id)
	MenuAudio.stop()
	_set_steam_menu_presence("Visualizer Mode — %s" % str(song_entry.get("display_name", song_entry.get("id", "Track"))))
	start_game_requested.emit(current_song, current_difficulty, current_mode)


func _clear_visualizer_session() -> void:
	visualizer_active = false
	visualizer_reactive_mode = VISUALIZER_REACTIVE_PLAYER
	_visualizer_queue.clear()
	_visualizer_last_song_id = ""


func _clear_practice_session() -> void:
	practice_active = false


func request_settings() -> void:
	_set_steam_menu_presence("In Settings")
	show_settings_requested.emit()


func request_multiplayer() -> void:
	_clear_temporary_run_flags()
	if not can_use_steam_services():
		request_info("MULTIPLAYER UNAVAILABLE", "%s\n\nOpen Steam, then return to Multiplayer." % get_steam_unavailable_message())
		return
	_set_steam_menu_presence("In Multiplayer Menu")
	show_multiplayer_requested.emit()


func request_leaderboards() -> void:
	show_leaderboards_requested.emit()


func request_stats() -> void:
	show_stats_requested.emit()


func request_chart_editor() -> void:
	_clear_temporary_run_flags()
	show_chart_editor_requested.emit()


func request_local_songs() -> void:
	_clear_temporary_run_flags()
	show_local_songs_requested.emit()


func request_community_charts() -> void:
	_clear_temporary_run_flags()
	_set_steam_menu_presence("Browsing Community Charts")
	show_community_charts_requested.emit()


func request_progression() -> void:
	show_progression_requested.emit()


func request_shop() -> void:
	show_shop_requested.emit()


func request_track_store() -> void:
	show_track_store_requested.emit()


func request_info(title: String, message: String) -> void:
	show_info_requested.emit({"title": title, "message": message})


func request_calibration() -> void:
	show_calibration_requested.emit()


func start_song(song_entry: Dictionary, difficulty: String, mode: String = GameModeConfig.DEFAULT_MODE, force_no_fail: bool = false) -> void:
	_clear_visualizer_session()
	_clear_practice_session()
	current_song = song_entry.duplicate(true)
	current_difficulty = difficulty
	current_mode = mode if GameModeConfig.is_valid(mode) else GameModeConfig.DEFAULT_MODE
	current_loadout = ProgressionManager.get_equipped_loadout()
	current_run_forced_no_fail = force_no_fail
	current_loadout["forced_no_fail"] = force_no_fail
	current_loadout["practice_forced_no_fail"] = force_no_fail
	current_loadout["ranked"] = bool(current_loadout.get("ranked", true)) and not force_no_fail
	ProfileStore.set_selected_song_id(str(song_entry.get("id", "")))
	ProfileStore.set_selected_difficulty(difficulty)
	ProfileStore.set_selected_mode(current_mode)
	_set_steam_gameplay_presence()
	start_game_requested.emit(current_song, current_difficulty, current_mode)


func start_practice_song(song_entry: Dictionary, difficulty: String, mode: String = GameModeConfig.DEFAULT_MODE) -> void:
	if song_entry.is_empty():
		return
	_clear_visualizer_session()
	practice_active = true
	current_song = song_entry.duplicate(true)
	current_difficulty = difficulty
	current_mode = mode if GameModeConfig.is_valid(mode) else GameModeConfig.DEFAULT_MODE
	current_loadout = ProgressionManager.get_equipped_loadout()
	current_run_forced_no_fail = true
	current_loadout["forced_no_fail"] = true
	current_loadout["practice_forced_no_fail"] = true
	current_loadout["practice_session"] = true
	current_loadout["skip_progression_rewards"] = true
	current_loadout["skip_progression_completion"] = true
	current_loadout["ranked"] = false
	ProfileStore.set_selected_song_id(str(song_entry.get("id", "")))
	ProfileStore.set_selected_difficulty(difficulty)
	ProfileStore.set_selected_mode(current_mode)
	_set_steam_menu_presence("Practice Mode — %s" % str(song_entry.get("display_name", song_entry.get("id", "Track"))))
	start_game_requested.emit(current_song, current_difficulty, current_mode)


func finish_song(result: Dictionary) -> void:
	if visualizer_active:
		advance_visualizer_song()
		return
	if practice_active:
		request_practice_select()
		return
	var final_result: Dictionary = result.duplicate(true)
	var multiplayer_service: Node = get_active_multiplayer_service()
	var multiplayer_active := multiplayer_service != null and multiplayer_service.has_method("is_session_active") and bool(multiplayer_service.call("is_session_active"))
	var steam_lobby_round: bool = multiplayer_service == steam_lobby_service and multiplayer_active
	var current_song_assets := {}
	if current_song.get("assets", {}) is Dictionary:
		current_song_assets = (current_song.get("assets", {}) as Dictionary).duplicate(true)
	final_result["song_id"] = str(current_song.get("id", ""))
	final_result["difficulty"] = current_difficulty
	final_result["mode"] = current_mode
	final_result["multiplayer"] = multiplayer_active
	final_result["source_type"] = _current_song_source_type()
	final_result["source_label"] = _current_song_source_label(str(final_result["source_type"]))
	final_result["return_route"] = _current_song_return_route(str(final_result["source_type"]), multiplayer_active)
	final_result["song_display_name"] = str(current_song.get("display_name", current_song.get("title", current_song.get("id", "Track"))))
	final_result["song_artist"] = str(current_song.get("artist", ""))
	final_result["chart_author"] = str(current_song.get("chart_author", current_song.get("charter", "")))
	final_result["song_root_path"] = str(current_song.get("root_path", ""))
	final_result["song_manifest_path"] = str(current_song.get("manifest_path", ""))
	final_result["song_preview_path"] = str(current_song_assets.get("preview_png", current_song.get("preview_path", "")))
	final_result["practice_forced_no_fail"] = bool(final_result.get("practice_forced_no_fail", current_run_forced_no_fail))
	var default_ranked := true if multiplayer_active else bool(current_loadout.get("ranked", true))
	final_result["ranked"] = bool(final_result.get("ranked", default_ranked))
	var was_first_completion := true
	var progression_snapshot: Dictionary = ProgressionManager.get_player_data()
	var completed_songs_before: Dictionary = progression_snapshot.get("completed_songs", {}) as Dictionary
	if completed_songs_before.has(str(current_song.get("id", ""))):
		was_first_completion = false
	var previous_local_best_score := 0
	if not current_song.is_empty():
		var previous_best_payload: Dictionary = ProfileStore.get_high_score(
			str(current_song.get("id", "")),
			current_difficulty,
			current_mode
		)
		previous_local_best_score = int(previous_best_payload.get("score", 0))
		ProfileStore.update_high_score(
			str(current_song.get("id", "")),
			current_difficulty,
			final_result,
			current_mode
		)
	final_result["previous_local_best_score"] = previous_local_best_score
	var progression_reward: Dictionary = ProgressionManager.on_song_complete(final_result)
	for key_variant in progression_reward.keys():
		final_result[str(key_variant)] = progression_reward[key_variant]
	var should_award_achievements: bool = bool(final_result.get("multiplayer", false)) or bool(final_result.get("ranked", false))
	if should_award_achievements:
		SteamAchievements.on_session_time(float(final_result.get("play_time_seconds", 0.0)))
		SteamAchievements.on_song_completed(
			current_song.duplicate(true),
			final_result.duplicate(true),
			current_loadout.duplicate(true),
			was_first_completion,
			SteamAchievements.get_base_song_completion_count(),
			SteamAchievements.get_unique_song_completion_count(),
			SteamAchievements.get_total_base_song_count()
		)
	if multiplayer_active and multiplayer_service != null:
		var round_snapshot: Dictionary = multiplayer_service.call("get_current_round_snapshot")
		if not round_snapshot.is_empty():
			final_result["winner_display_name"] = multiplayer_service.call("get_winner_display_name", round_snapshot)
			final_result["placement"] = multiplayer_service.call("get_local_player_placement", round_snapshot)
		multiplayer_service.call("complete_local_round", final_result)
		if steam_lobby_round:
			_submit_solo_score_if_possible(final_result)
	else:
		_submit_solo_score_if_possible(final_result)
	if not bool(current_song.get("_editor_playtest", false)):
		final_result["gameplay_stats"] = ProfileStore.record_gameplay_result_stats(final_result)
	ProfileStore.set_last_result(final_result)
	_clear_temporary_run_flags()
	_set_steam_results_presence(final_result)
	show_results_requested.emit(final_result)


func _current_song_source_type() -> String:
	var source := str(current_song.get("source_type", current_song.get("source", ""))).strip_edges().to_lower()
	if not source.is_empty():
		return source
	var root_path := str(current_song.get("root_path", "")).strip_edges().to_lower()
	if root_path.begins_with("user://workshop"):
		return "workshop"
	if root_path.begins_with("user://custom_songs"):
		return "custom"
	return "official"


func _current_song_source_label(source_type: String) -> String:
	match source_type:
		"workshop":
			return "Community"
		"custom":
			return "Local"
		_:
			return "Official"


func _current_song_return_route(source_type: String, multiplayer_active: bool) -> String:
	if multiplayer_active:
		return "multiplayer"
	var explicit_route := str(current_song.get("return_route", "")).strip_edges().to_lower()
	if not explicit_route.is_empty():
		return explicit_route
	match source_type:
		"workshop":
			return "community_charts"
		"custom":
			return "local_songs"
		_:
			return "song_select"


func is_mobile_platform() -> bool:
	return OS.has_feature("android") or OS.has_feature("ios")


func has_steam_desktop_support() -> bool:
	return not is_mobile_platform() and Engine.has_singleton("Steam")


func can_use_steam_services() -> bool:
	return has_steam_desktop_support() and SteamClient != null and SteamClient.is_ready()


func get_steam_unavailable_message() -> String:
	if is_mobile_platform():
		return "Steam services are not available on this platform."
	if not Engine.has_singleton("Steam"):
		return "Steamworks is not available in this build."
	if SteamClient != null and SteamClient.has_method("get_status_text"):
		var status := str(SteamClient.get_status_text()).strip_edges()
		if not status.is_empty():
			return status
	return "Steam is not running or has not finished initializing."


func supports_desktop_tools() -> bool:
	if is_mobile_platform():
		return false
	return OS.has_feature("windows") or OS.has_feature("macos") or OS.has_feature("linuxbsd")


func supports_touch_gameplay() -> bool:
	return is_mobile_platform() or OS.has_feature("windows") or OS.has_feature("macos") or OS.has_feature("linuxbsd")


func is_multiplayer_round_active() -> bool:
	var service: Node = get_active_multiplayer_service()
	if service != null and service.has_method("is_session_active") and bool(service.call("is_session_active")):
		return true
	return bool(multiplayer_context.get("active", false))


func get_active_multiplayer_service() -> Node:
	if steam_lobby_service != null:
		var steam_active := false
		if steam_lobby_service.has_method("is_session_active"):
			steam_active = steam_active or bool(steam_lobby_service.call("is_session_active"))
		if steam_lobby_service.has_method("is_lobby_active"):
			steam_active = steam_active or bool(steam_lobby_service.call("is_lobby_active")) and str(multiplayer_context.get("backend", "")) == "steam_lobby"
		if steam_active:
			return steam_lobby_service
	if match_service != null:
		return match_service
	return null


func is_steam_lobby_active() -> bool:
	return steam_lobby_service != null and steam_lobby_service.has_method("is_lobby_active") and bool(steam_lobby_service.call("is_lobby_active"))


func clear_multiplayer_context() -> void:
	multiplayer_context.clear()


func consume_pending_startup_route() -> String:
	var route: String = _pending_startup_route
	_pending_startup_route = ""
	return route


func clear_pending_startup_route(route: String = "") -> void:
	if route.is_empty() or _pending_startup_route == route:
		_pending_startup_route = ""


func _steam_presence_available() -> bool:
	return can_use_steam_services()


func _set_steam_menu_presence(status: String) -> void:
	if not _steam_presence_available():
		return
	SteamClient.set_menu_presence(status)


func _set_steam_gameplay_presence() -> void:
	if not _steam_presence_available():
		return
	SteamClient.set_gameplay_presence(current_song.duplicate(true), current_difficulty, current_mode, is_multiplayer_round_active())


func _set_steam_results_presence(result: Dictionary) -> void:
	if not _steam_presence_available():
		return
	if bool(result.get("multiplayer", false)):
		SteamClient.set_multiplayer_presence("Viewing Multiplayer Results", str(result.get("difficulty", current_difficulty)), str(result.get("mode", current_mode)))
		return
	SteamClient.set_menu_presence("Viewing Results")


func _clear_temporary_run_flags() -> void:
	current_run_forced_no_fail = false
	if current_loadout.is_empty():
		return
	current_loadout["forced_no_fail"] = false
	current_loadout["practice_forced_no_fail"] = false
	current_loadout["practice_session"] = false
	current_loadout["skip_progression_rewards"] = false
	current_loadout["skip_progression_completion"] = false
	current_loadout["ranked"] = bool(current_loadout.get("ranked", true))


func _on_multiplayer_launch_requested(payload: Dictionary) -> void:
	var song_id := str(payload.get("song_id", ""))
	var difficulty := str(payload.get("difficulty", ""))
	var mode := str(payload.get("mode", GameModeConfig.DEFAULT_MODE))
	var song_entry := ContentRegistry.get_song(song_id)
	if song_entry.is_empty():
		request_info("MULTIPLAYER", "Unable to launch multiplayer round because the selected song was not found.")
		return
	multiplayer_context = payload.duplicate(true)
	multiplayer_context["active"] = true
	start_song(song_entry, difficulty, mode)


func _on_steam_invite_join_requested(invite: Dictionary) -> void:
	print("[steam] Ignored legacy relay invite after native Steam lobby migration: %s" % JSON.stringify(invite))


func _on_steam_lobby_join_requested(lobby_id: String, _friend_id: String = "") -> void:
	if steam_lobby_service == null:
		return
	_pending_startup_route = "multiplayer"
	if identity_service != null and not identity_service.is_authenticated():
		identity_service.authenticate_current_platform()
	steam_lobby_service.join_party(lobby_id)
	request_multiplayer()


func _on_steam_ready_changed(ready: bool, _status: String = "") -> void:
	if ready and identity_service != null:
		identity_service.authenticate_current_platform()
	steam_availability_changed.emit(ready)


func _warm_identity_on_launch() -> void:
	if identity_service == null:
		return
	if identity_service.has_method("is_available") and not bool(identity_service.call("is_available")):
		return
	identity_service.ensure_relay_identity()


func _submit_solo_score_if_possible(final_result: Dictionary) -> void:
	if leaderboard_service == null or identity_service == null:
		return
	if not bool(final_result.get("ranked", true)):
		return
	if not identity_service.is_authenticated():
		return
	if current_song.is_empty():
		return
	var previous_best_rank: int = SteamAchievements.get_best_leaderboard_rank(
		str(current_song.get("id", "")),
		str(final_result.get("difficulty", current_difficulty)),
		str(final_result.get("mode", current_mode))
	)
	var previous_local_best_score := int(final_result.get("previous_local_best_score", 0))
	leaderboard_service.submit_solo_score(current_song.duplicate(true), final_result.duplicate(true), func(success: bool, payload: Dictionary) -> void:
		if not success:
			return
		leaderboard_service.submit_steam_score_if_eligible(
			current_song.duplicate(true),
			final_result.duplicate(true),
			previous_local_best_score
		)
		var rank: int = 0
		if payload.get("entry", null) is Dictionary:
			rank = int((payload.get("entry", {}) as Dictionary).get("rank", 0))
		if rank <= 0:
			rank = int(payload.get("rank", 0))
		if rank > 0:
			SteamAchievements.on_leaderboard_submission(
				str(current_song.get("id", "")),
				str(final_result.get("difficulty", current_difficulty)),
				str(final_result.get("mode", current_mode)),
				payload.duplicate(true),
				previous_best_rank
			)
			return
		leaderboard_service.load_top_scores(
			str(current_song.get("id", "")),
			str(final_result.get("difficulty", current_difficulty)),
			str(final_result.get("mode", current_mode)),
			100,
			func(load_success: bool, entries: Array) -> void:
				if not load_success:
					return
				var current_user_id: String = str(identity_service.get_current_identity().get("userID", ""))
				var entry_payload: Dictionary = {}
				for entry_variant in entries:
					if entry_variant is Dictionary and str((entry_variant as Dictionary).get("userID", "")) == current_user_id:
						entry_payload = (entry_variant as Dictionary).duplicate(true)
						break
				SteamAchievements.on_leaderboard_submission(
					str(current_song.get("id", "")),
					str(final_result.get("difficulty", current_difficulty)),
					str(final_result.get("mode", current_mode)),
					entry_payload,
					previous_best_rank
				)
		)
	)
