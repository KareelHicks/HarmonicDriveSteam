extends Control
class_name ChartPreviewRuntime

const GameModeConfig := preload("res://scripts/gameplay/GameModeConfig.gd")

signal exited
signal live_lane_event(time_sec: float, lane: int, pressed: bool)
signal editor_note_remove_requested(note_id: int)

var _game_scene: Control
var _song_entry: Dictionary = {}
var _difficulty_display := "Expert"
var _mode_id := GameModeConfig.DEFAULT_MODE
var _start_time_sec := 0.0
var _hot_reload_pending := false
var _live_mode := false
var _app_state_snapshot: Dictionary = {}
var _has_app_state_snapshot := false


func _app_state() -> Node:
	return get_node_or_null("/root/AppState")


func _audio_sync() -> Node:
	return get_node_or_null("/root/AudioSync")


func is_running() -> bool:
	return _game_scene != null and is_instance_valid(_game_scene)


func _exit_tree() -> void:
	var audio_sync := _audio_sync()
	if audio_sync != null:
		audio_sync.stop_playback()
		if audio_sync.has_method("reset_speed_scale"):
			audio_sync.call("reset_speed_scale")
	_restore_app_state()


func start(song_entry: Dictionary, difficulty_display: String, mode_id: String, start_time_sec: float = 0.0) -> void:
	stop()
	_capture_app_state()
	_song_entry = song_entry.duplicate(true)
	_difficulty_display = difficulty_display
	_mode_id = mode_id
	_start_time_sec = maxf(0.0, start_time_sec)
	_hot_reload_pending = false
	_live_mode = false
	_reset_audio_session()

	# Use the real game boot path by setting AppState fields BEFORE adding GameScene
	# to the tree. GameScene reads AppState in _ready().
	var app_state := _app_state()
	if app_state != null:
		var tagged := _song_entry.duplicate(true)
		tagged["_editor_playtest"] = true
		tagged["_editor_playtest_started_at"] = Time.get_unix_time_from_system()
		tagged["_editor_playtest_start_time"] = _start_time_sec
		app_state.current_song = tagged
		app_state.current_difficulty = _difficulty_display
		app_state.current_mode = _mode_id
		app_state.current_loadout = (app_state.current_loadout as Dictionary).duplicate(true)
	print("[EditorPlaytest] AppState set song_id=%s difficulty=%s mode=%s audio=%s" % [
		str(_song_entry.get("id", "")),
		_difficulty_display,
		_mode_id,
		str(_song_entry.get("audio_path", "")),
	])

	if not _instantiate_game_scene():
		stop()
		return

	call_deferred("_log_resolved_chart")


func start_live(
		song_entry: Dictionary,
		difficulty_display: String,
		mode_id: String,
		start_time_sec: float,
		notes: Array[Dictionary],
		lane_count: int
	) -> void:
	stop()
	_capture_app_state()
	_song_entry = song_entry.duplicate(true)
	_difficulty_display = difficulty_display
	_mode_id = mode_id
	_start_time_sec = maxf(0.0, start_time_sec)
	_hot_reload_pending = false
	_live_mode = true
	_reset_audio_session()

	var app_state := _app_state()
	if app_state != null:
		var tagged := _song_entry.duplicate(true)
		tagged["_editor_playtest"] = true
		tagged["_editor_live_mode"] = true
		tagged["_editor_live_start_time"] = _start_time_sec
		tagged["_editor_live_notes"] = notes.duplicate(true)
		tagged["_editor_live_lane_count"] = lane_count
		app_state.current_song = tagged
		app_state.current_difficulty = _difficulty_display
		app_state.current_mode = _mode_id
		app_state.current_loadout = (app_state.current_loadout as Dictionary).duplicate(true)

	if not _instantiate_game_scene():
		stop()
		return
	if _game_scene.has_method("editor_live_audio_ready") \
			and not bool(_game_scene.call("editor_live_audio_ready")):
		stop()
		return
	if _game_scene.has_method("configure_editor_live"):
		_game_scene.call("configure_editor_live", notes, lane_count, _start_time_sec)
	if _game_scene.has_signal("editor_live_lane_event"):
		_game_scene.connect("editor_live_lane_event", _on_game_live_lane_event)
	if _game_scene.has_signal("editor_note_remove_requested"):
		_game_scene.connect("editor_note_remove_requested", _on_game_note_remove_requested)


func stop() -> void:
	if _game_scene != null and is_instance_valid(_game_scene):
		if _game_scene.get_parent() == self:
			remove_child(_game_scene)
		_game_scene.queue_free()
	_game_scene = null
	var audio_sync := _audio_sync()
	if audio_sync != null:
		audio_sync.stop_playback()
		if audio_sync.has_method("reset_speed_scale"):
			audio_sync.call("reset_speed_scale")
	_restore_app_state()
	_live_mode = false
	_hot_reload_pending = false


func request_hot_reload() -> void:
	if not is_running() or _live_mode:
		return
	_hot_reload_pending = true


func pause() -> void:
	if _live_mode:
		set_live_paused(true)
		return
	var audio_sync := _audio_sync()
	if audio_sync != null:
		audio_sync.pause_playback()


func resume() -> void:
	if _live_mode:
		set_live_paused(false)
		return
	var audio_sync := _audio_sync()
	if audio_sync != null:
		audio_sync.resume_playback()


func restart_from(time_sec: float) -> void:
	if _live_mode:
		seek_live(time_sec)
		return
	var audio_sync := _audio_sync()
	if audio_sync != null:
		audio_sync.seek(maxf(0.0, time_sec))


func current_time_sec() -> float:
	var audio_sync := _audio_sync()
	if audio_sync == null:
		return 0.0
	return audio_sync.get_song_time_raw()


func set_live_paused(paused: bool) -> void:
	if not _live_mode or not is_running():
		return
	if _game_scene.has_method("editor_set_live_paused"):
		_game_scene.call("editor_set_live_paused", paused)


func is_live_paused() -> bool:
	if not _live_mode or not is_running():
		return true
	if _game_scene.has_method("editor_is_live_paused"):
		return bool(_game_scene.call("editor_is_live_paused"))
	return not bool(_audio_sync().is_playing()) if _audio_sync() != null else true


func seek_live(time_sec: float) -> void:
	if not _live_mode or not is_running():
		return
	if _game_scene.has_method("editor_seek_live"):
		_game_scene.call("editor_seek_live", maxf(0.0, time_sec))


func set_playback_speed(speed_scale: float) -> void:
	var audio_sync := _audio_sync()
	if audio_sync != null and audio_sync.has_method("set_speed_scale"):
		audio_sync.call("set_speed_scale", speed_scale)


func set_live_adding(enabled: bool) -> void:
	if _live_mode and is_running() and _game_scene.has_method("editor_set_live_adding"):
		_game_scene.call("editor_set_live_adding", enabled)


func set_note_removal_enabled(enabled: bool) -> void:
	if _live_mode and is_running() and _game_scene.has_method("editor_set_note_removal_enabled"):
		_game_scene.call("editor_set_note_removal_enabled", enabled)


func replace_notes(notes: Array[Dictionary]) -> void:
	if _live_mode and is_running() and _game_scene.has_method("editor_replace_live_notes"):
		_game_scene.call("editor_replace_live_notes", notes)


func add_note(note: Dictionary) -> void:
	if _live_mode and is_running() and _game_scene.has_method("editor_add_live_note"):
		_game_scene.call("editor_add_live_note", note)


func song_duration_sec() -> float:
	var audio_sync := _audio_sync()
	return float(audio_sync.get_stream_length()) if audio_sync != null else 0.0


func _process(_delta: float) -> void:
	if _hot_reload_pending and is_running() and not _live_mode:
		_hot_reload_pending = false
		var t := current_time_sec()
		start(_song_entry, _difficulty_display, _mode_id, t)


func _instantiate_game_scene() -> bool:
	var packed := load("res://scenes/gameplay/GameScene.tscn") as PackedScene
	if packed == null:
		push_error("Missing gameplay scene: res://scenes/gameplay/GameScene.tscn")
		return false
	_game_scene = packed.instantiate() as Control
	if _game_scene == null:
		push_error("Unable to instantiate gameplay scene.")
		return false
	add_child(_game_scene)
	_game_scene.set_anchors_preset(Control.PRESET_FULL_RECT)
	_game_scene.offset_left = 0.0
	_game_scene.offset_top = 0.0
	_game_scene.offset_right = 0.0
	_game_scene.offset_bottom = 0.0
	_game_scene.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_game_scene.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if _game_scene.has_signal("game_exited"):
		_game_scene.connect("game_exited", func() -> void:
			exited.emit()
		)
	return true


func _capture_app_state() -> void:
	var app_state := _app_state()
	if app_state == null:
		_app_state_snapshot.clear()
		_has_app_state_snapshot = false
		return
	_app_state_snapshot = {
		"current_song": (app_state.current_song as Dictionary).duplicate(true),
		"current_difficulty": str(app_state.current_difficulty),
		"current_mode": str(app_state.current_mode),
		"current_loadout": (app_state.current_loadout as Dictionary).duplicate(true),
	}
	_has_app_state_snapshot = true


func _restore_app_state() -> void:
	if not _has_app_state_snapshot:
		return
	var app_state := _app_state()
	if app_state != null:
		app_state.current_song = (_app_state_snapshot.get("current_song", {}) as Dictionary).duplicate(true)
		app_state.current_difficulty = str(_app_state_snapshot.get("current_difficulty", "Medium"))
		app_state.current_mode = str(_app_state_snapshot.get("current_mode", GameModeConfig.DEFAULT_MODE))
		app_state.current_loadout = (_app_state_snapshot.get("current_loadout", {}) as Dictionary).duplicate(true)
	_app_state_snapshot.clear()
	_has_app_state_snapshot = false


func _reset_audio_session() -> void:
	var audio_sync := _audio_sync()
	if audio_sync == null:
		return
	audio_sync.stop_playback()
	if audio_sync.has_method("reset_speed_scale"):
		audio_sync.call("reset_speed_scale")


func _on_game_live_lane_event(time_sec: float, lane: int, pressed: bool) -> void:
	if _live_mode:
		live_lane_event.emit(time_sec, lane, pressed)


func _on_game_note_remove_requested(note_id: int) -> void:
	if _live_mode:
		editor_note_remove_requested.emit(note_id)


func _log_resolved_chart() -> void:
	var content := get_node_or_null("/root/ContentRegistry")
	if content == null:
		print("[EditorPlaytest] ContentRegistry missing; cannot resolve chart path.")
		return
	var app_state := _app_state()
	if app_state == null:
		print("[EditorPlaytest] AppState missing; cannot resolve chart path.")
		return
	var song_entry: Dictionary = (app_state.current_song as Dictionary).duplicate(true)
	var diff: String = str(app_state.current_difficulty)
	var mode: String = str(app_state.current_mode)
	var chart_path: String = str(content.get_chart_path(song_entry, diff, mode))
	print("[EditorPlaytest] resolved chart_path=%s" % chart_path)
	if FileAccess.file_exists(chart_path):
		var loaded := FileAccess.get_file_as_string(chart_path)
		var parsed: Variant = JSON.parse_string(loaded)
		if parsed is Dictionary:
			var notes: Variant = (parsed as Dictionary).get("notes", [])
			var count := (notes as Array).size() if notes is Array else 0
			print("[EditorPlaytest] chart notes=%d" % count)
	else:
		print("[EditorPlaytest] chart file missing on disk.")
