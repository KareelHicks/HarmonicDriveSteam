extends RefCounted
class_name EditorLiveModeManager

## Owns the Chart Editor's Live Editor overlay controls. ChartEditorScene should
## call process_update() from its _process() while the editor is alive.

const GameModeConfig := preload("res://scripts/gameplay/GameModeConfig.gd")
const DifficultyManager := preload("res://scripts/editor/DifficultyManager.gd")
const SongResolver := preload("res://scripts/songs/SongResolver.gd")
const AudioResolver := preload("res://scripts/songs/AudioResolver.gd")
const ChartPreviewRuntimeScript := preload("res://scripts/editor/ChartPreviewRuntime.gd")

signal live_mode_started
signal live_mode_stopped(position_sec: float)
signal live_lane_event(time_sec: float, lane: int, pressed: bool)
signal live_adding_changed(enabled: bool)
signal remove_note_requested(note_id: int)

const MIN_SPEED_SCALE := 0.25
const MAX_SPEED_SCALE := 1.50
const DEFAULT_SPEED_SCALE := 1.00
const TIMELINE_STEP_SEC := 0.001

var _overlay: Control
var _close_button: BaseButton
var _runtime_holder: Control
var _start_pause_button: BaseButton
var _timeline_slider: Slider
var _speed_spin: SpinBox
var _live_adding_toggle: BaseButton
var _remove_notes_toggle: BaseButton
var _timestamp_label: Label
var _status_label: Label

var _runtime: Control
var _song_entry: Dictionary = {}
var _difficulty_id := "expert"
var _mode_id := GameModeConfig.DEFAULT_MODE
var _authoritative_notes: Array[Dictionary] = []
var _lane_count := 5
var _song_duration_sec := 0.0
var _paused := true
var _live_adding := false
var _remove_notes_enabled := false
var _updating_controls := false
var _scrubbing := false
var _missing_runtime_methods: Dictionary = {}
var _active_live_lanes: Dictionary = {}


func attach(
		overlay: Control,
		close_button: BaseButton,
		runtime_holder: Control,
		start_pause_button: BaseButton,
		timeline_slider: Slider,
		speed_spin: SpinBox,
		live_adding_toggle: BaseButton,
		remove_notes_toggle: BaseButton,
		timestamp_label: Label,
		status_label: Label = null
	) -> void:
	_overlay = overlay
	_close_button = close_button
	_runtime_holder = runtime_holder
	_start_pause_button = start_pause_button
	_timeline_slider = timeline_slider
	_speed_spin = speed_spin
	_live_adding_toggle = live_adding_toggle
	_remove_notes_toggle = remove_notes_toggle
	_timestamp_label = timestamp_label
	_status_label = status_label

	if _overlay != null:
		_overlay.visible = false
		_overlay.focus_mode = Control.FOCUS_ALL
	if _close_button != null and not _close_button.pressed.is_connected(stop):
		_close_button.pressed.connect(stop)
	if _start_pause_button != null and not _start_pause_button.pressed.is_connected(_on_start_pause_pressed):
		_start_pause_button.pressed.connect(_on_start_pause_pressed)
	if _timeline_slider != null:
		_timeline_slider.min_value = 0.0
		_timeline_slider.max_value = 0.0
		_timeline_slider.step = TIMELINE_STEP_SEC
		_timeline_slider.allow_greater = false
		_timeline_slider.allow_lesser = false
		if not _timeline_slider.value_changed.is_connected(_on_timeline_value_changed):
			_timeline_slider.value_changed.connect(_on_timeline_value_changed)
		if not _timeline_slider.drag_started.is_connected(_on_timeline_drag_started):
			_timeline_slider.drag_started.connect(_on_timeline_drag_started)
		if not _timeline_slider.drag_ended.is_connected(_on_timeline_drag_ended):
			_timeline_slider.drag_ended.connect(_on_timeline_drag_ended)
		if not _timeline_slider.gui_input.is_connected(_on_timeline_gui_input):
			_timeline_slider.gui_input.connect(_on_timeline_gui_input)
	if _speed_spin != null:
		_speed_spin.min_value = MIN_SPEED_SCALE
		_speed_spin.max_value = MAX_SPEED_SCALE
		_speed_spin.step = 0.01
		_speed_spin.allow_greater = false
		_speed_spin.allow_lesser = false
		_speed_spin.suffix = "x"
		if not _speed_spin.value_changed.is_connected(_on_speed_changed):
			_speed_spin.value_changed.connect(_on_speed_changed)
		var speed_line_edit := _speed_spin.get_line_edit()
		if speed_line_edit != null:
			if not speed_line_edit.text_submitted.is_connected(_on_speed_text_submitted):
				speed_line_edit.text_submitted.connect(_on_speed_text_submitted)
			if not speed_line_edit.focus_exited.is_connected(_on_speed_focus_exited):
				speed_line_edit.focus_exited.connect(_on_speed_focus_exited)
	if _live_adding_toggle != null and not _live_adding_toggle.toggled.is_connected(_on_live_adding_toggled):
		_live_adding_toggle.toggled.connect(_on_live_adding_toggled)
	if _remove_notes_toggle != null and not _remove_notes_toggle.toggled.is_connected(_on_remove_notes_toggled):
		_remove_notes_toggle.toggled.connect(_on_remove_notes_toggled)
	_reset_controls()


func is_active() -> bool:
	return _runtime != null and is_instance_valid(_runtime) and _overlay != null and _overlay.visible


func is_paused() -> bool:
	return _paused


func is_live_adding_enabled() -> bool:
	return _live_adding


func is_note_removal_enabled() -> bool:
	return _remove_notes_enabled


func start_for_project(
		song_folder: String,
		manifest: Dictionary,
		difficulty_id: String,
		start_time_sec: float,
		notes: Array[Dictionary],
		lane_count: int,
		audio_path_override: String = ""
	) -> Dictionary:
	if is_active():
		_stop_runtime(false)
	if song_folder.strip_edges().is_empty():
		return {"ok": false, "error": "No project folder selected."}
	if _overlay == null or _runtime_holder == null:
		return {"ok": false, "error": "Live Editor controls are not attached."}
	if _start_pause_button == null or _timeline_slider == null or _speed_spin == null \
			or _live_adding_toggle == null or _remove_notes_toggle == null:
		return {"ok": false, "error": "Live Editor dock controls are incomplete."}

	var audio_path := _resolve_audio_path(song_folder, manifest, audio_path_override)
	if audio_path.is_empty():
		return {"ok": false, "error": "No supported audio file was found for this project."}
	var chart_paths := _resolve_chart_paths(song_folder, manifest)
	if chart_paths.is_empty():
		return {"ok": false, "error": "No chart files were found in this project."}

	_song_entry = {
		"id": str(manifest.get("song_id", song_folder.get_file())),
		"display_name": str(manifest.get("title", song_folder.get_file())),
		"artist": str(manifest.get("artist", "")),
		"audio_path": audio_path,
		"bpm": float(manifest.get("bpm", 120.0)),
		"_editor_playtest": true,
		"_editor_live_mode": true,
		"modes": {
			_mode_id: {
				"charts": chart_paths,
			}
		},
	}
	_difficulty_id = difficulty_id.strip_edges().to_lower()
	_authoritative_notes = notes.duplicate(true)
	_lane_count = maxi(1, lane_count)
	_active_live_lanes.clear()
	_song_duration_sec = maxf(0.0, float(manifest.get("duration", manifest.get("duration_sec", 0.0))))
	_missing_runtime_methods.clear()
	_overlay.visible = true
	_ensure_runtime()

	var clamped_start := maxf(0.0, start_time_sec)
	var difficulty_display := DifficultyManager.display_name(_difficulty_id)
	if _runtime.has_method("start_live"):
		_runtime.call("start_live", _song_entry, difficulty_display, _mode_id, clamped_start, _authoritative_notes, _lane_count)
	else:
		# Compatibility while the dedicated live runtime contract is being integrated.
		_runtime.call("start", _song_entry, difficulty_display, _mode_id, clamped_start)
		_warn_missing_runtime_method("start_live")
	if _runtime.has_method("is_running") and not bool(_runtime.call("is_running")):
		_stop_runtime(false)
		return {"ok": false, "error": "The gameplay scene or selected audio could not be started."}
	_refresh_duration_from_runtime()
	if _song_duration_sec > 0.0:
		clamped_start = minf(clamped_start, _song_duration_sec)

	_paused = true
	_live_adding = false
	_remove_notes_enabled = false
	_updating_controls = true
	_start_pause_button.text = "Start"
	_live_adding_toggle.set_pressed_no_signal(false)
	_remove_notes_toggle.set_pressed_no_signal(false)
	_remove_notes_toggle.disabled = false
	_timeline_slider.max_value = maxf(maxf(_song_duration_sec, clamped_start), TIMELINE_STEP_SEC)
	_timeline_slider.set_value_no_signal(clamped_start)
	_speed_spin.set_value_no_signal(clampf(float(_speed_spin.value), MIN_SPEED_SCALE, MAX_SPEED_SCALE))
	_updating_controls = false
	_apply_runtime_speed(float(_speed_spin.value))
	_set_runtime_paused(true)
	_set_runtime_live_adding(false)
	_set_runtime_note_removal(false)
	_seek_runtime(clamped_start)
	_update_timestamp(clamped_start)
	_set_status("Test Play ready. Scoring is enabled while Live Adding is off.")
	if _overlay.focus_mode != Control.FOCUS_NONE:
		_overlay.grab_focus()
	live_mode_started.emit()
	return {"ok": true, "error": ""}


func stop() -> void:
	_stop_runtime(true)


func _stop_runtime(emit_stopped: bool) -> void:
	var was_active := is_active()
	var was_live_adding := _live_adding
	var final_position := current_time_sec()
	_flush_live_lane_releases(final_position)
	if was_live_adding:
		live_adding_changed.emit(false)
	if _runtime != null and is_instance_valid(_runtime):
		if _runtime.has_method("stop"):
			_runtime.call("stop")
		_reset_audio_speed()
		if _runtime.get_parent() != null:
			_runtime.get_parent().remove_child(_runtime)
		_runtime.queue_free()
	_runtime = null
	if _overlay != null:
		_overlay.visible = false
	_reset_controls()
	if emit_stopped and was_active:
		live_mode_stopped.emit(final_position)


func current_time_sec() -> float:
	if _runtime != null and is_instance_valid(_runtime) and _runtime.has_method("current_time_sec"):
		return maxf(0.0, float(_runtime.call("current_time_sec")))
	return float(_timeline_slider.value) if _timeline_slider != null else 0.0


func song_duration_sec() -> float:
	return _song_duration_sec


func replace_notes(notes: Array[Dictionary]) -> void:
	_authoritative_notes = notes.duplicate(true)
	if not is_active():
		return
	if _runtime.has_method("replace_notes"):
		_runtime.call("replace_notes", _authoritative_notes)
	else:
		_warn_missing_runtime_method("replace_notes")


func add_note(note: Dictionary) -> void:
	if note.is_empty():
		return
	_insert_authoritative_note(note)
	if not is_active():
		return
	if _runtime.has_method("add_note"):
		_runtime.call("add_note", note)
	else:
		# Compatibility fallback is correct, but intentionally not the normal
		# per-key path because it rebuilds every gameplay note visual.
		_runtime.call("replace_notes", _authoritative_notes)
		_warn_missing_runtime_method("add_note")


func process_update() -> void:
	if not is_active():
		return
	_refresh_duration_from_runtime()
	if _runtime.has_method("is_live_paused"):
		var runtime_paused := bool(_runtime.call("is_live_paused"))
		if runtime_paused != _paused:
			_apply_paused_state(runtime_paused, false)
	var position := clampf(current_time_sec(), 0.0, _song_duration_sec if _song_duration_sec > 0.0 else INF)
	if not _scrubbing:
		_updating_controls = true
		_timeline_slider.set_value_no_signal(position)
		_updating_controls = false
	_update_timestamp(position)


func _ensure_runtime() -> void:
	if _runtime != null and is_instance_valid(_runtime):
		return
	_runtime = ChartPreviewRuntimeScript.new()
	_runtime_holder.add_child(_runtime)
	_runtime.set_anchors_preset(Control.PRESET_FULL_RECT)
	_runtime.offset_left = 0.0
	_runtime.offset_top = 0.0
	_runtime.offset_right = 0.0
	_runtime.offset_bottom = 0.0
	_runtime.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_runtime.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if _runtime.has_signal("exited"):
		_runtime.connect("exited", stop)
	if _runtime.has_signal("live_lane_event"):
		_runtime.connect("live_lane_event", _on_runtime_live_lane_event)
	else:
		push_warning("ChartPreviewRuntime is missing live_lane_event(time_sec, lane, pressed).")
	if _runtime.has_signal("editor_note_remove_requested"):
		_runtime.connect("editor_note_remove_requested", _on_runtime_note_remove_requested)
	else:
		push_warning("ChartPreviewRuntime is missing editor_note_remove_requested(note_id).")


func _on_start_pause_pressed() -> void:
	if not is_active():
		return
	_apply_paused_state(not _paused, true)
	if _overlay != null and _overlay.focus_mode != Control.FOCUS_NONE:
		_overlay.call_deferred("grab_focus")


func _apply_paused_state(paused: bool, notify_runtime: bool) -> void:
	if paused and not _paused:
		_flush_live_lane_releases(current_time_sec())
	_paused = paused
	_start_pause_button.text = "Start" if paused else "Pause"
	_remove_notes_toggle.disabled = not paused
	if not paused and _remove_notes_enabled:
		_remove_notes_enabled = false
		_updating_controls = true
		_remove_notes_toggle.set_pressed_no_signal(false)
		_updating_controls = false
		_set_runtime_note_removal(false)
	if notify_runtime:
		_set_runtime_paused(paused)
	if _live_adding:
		_set_status("Live Adding paused." if paused else "Live Adding active.")
	else:
		_set_status("Test Play paused." if paused else "Test Play active. Scoring enabled.")


func _on_timeline_value_changed(value: float) -> void:
	if _updating_controls or not is_active():
		return
	_flush_live_lane_releases(current_time_sec())
	_seek_runtime(value)
	_update_timestamp(value)


func _on_timeline_drag_started() -> void:
	_scrubbing = true


func _on_timeline_drag_ended(_value_changed: bool) -> void:
	_scrubbing = false
	if is_active():
		_seek_runtime(float(_timeline_slider.value))
	_restore_gameplay_focus_deferred()


func _on_timeline_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_restore_gameplay_focus_deferred()


func _on_speed_changed(value: float) -> void:
	if _updating_controls:
		return
	var clamped := clampf(value, MIN_SPEED_SCALE, MAX_SPEED_SCALE)
	_apply_runtime_speed(clamped)
	_set_status("Live Editor playback speed: %.2fx" % clamped)


func _on_speed_text_submitted(_text: String) -> void:
	_restore_gameplay_focus_deferred()


func _on_speed_focus_exited() -> void:
	_restore_gameplay_focus_deferred()


func _on_live_adding_toggled(enabled: bool) -> void:
	if _updating_controls:
		return
	if not enabled:
		_flush_live_lane_releases(current_time_sec())
	_live_adding = enabled
	if enabled and _remove_notes_enabled:
		_remove_notes_enabled = false
		_updating_controls = true
		_remove_notes_toggle.set_pressed_no_signal(false)
		_updating_controls = false
		_set_runtime_note_removal(false)
	_set_runtime_live_adding(enabled)
	live_adding_changed.emit(enabled)
	_set_status("Live Adding active. Scoring paused." if enabled else "Test Play active. Scoring enabled.")
	_restore_gameplay_focus_deferred()


func _on_remove_notes_toggled(enabled: bool) -> void:
	if _updating_controls:
		return
	if enabled and not _paused:
		_updating_controls = true
		_remove_notes_toggle.set_pressed_no_signal(false)
		_updating_controls = false
		_set_status("Pause playback before enabling Remove Notes.")
		_restore_gameplay_focus_deferred()
		return
	_remove_notes_enabled = enabled
	if enabled and _live_adding:
		_flush_live_lane_releases(current_time_sec())
		_live_adding = false
		_updating_controls = true
		_live_adding_toggle.set_pressed_no_signal(false)
		_updating_controls = false
		_set_runtime_live_adding(false)
		live_adding_changed.emit(false)
	_set_runtime_note_removal(enabled)
	_set_status("Click a note to remove it." if enabled else "Remove Notes off.")
	_restore_gameplay_focus_deferred()


func _on_runtime_live_lane_event(time_sec: float, lane: int, pressed: bool) -> void:
	if not is_active() or lane < 0 or lane >= _lane_count:
		return
	var event_time := maxf(0.0, time_sec)
	if pressed:
		if _paused or not _live_adding or _remove_notes_enabled or _active_live_lanes.has(lane):
			return
		_active_live_lanes[lane] = true
		live_lane_event.emit(event_time, lane, true)
		return
	if not _active_live_lanes.has(lane):
		return
	_active_live_lanes.erase(lane)
	live_lane_event.emit(event_time, lane, false)


func _flush_live_lane_releases(time_sec: float) -> void:
	if _active_live_lanes.is_empty():
		return
	var lanes: Array[int] = []
	for lane_variant in _active_live_lanes.keys():
		lanes.append(int(lane_variant))
	lanes.sort()
	_active_live_lanes.clear()
	for lane in lanes:
		live_lane_event.emit(maxf(0.0, time_sec), lane, false)


func _insert_authoritative_note(note_value: Dictionary) -> void:
	var note := note_value.duplicate(true)
	var note_id := int(note.get("id", -1))
	for index in range(_authoritative_notes.size()):
		if int(_authoritative_notes[index].get("id", -2)) == note_id:
			_authoritative_notes[index] = note
			return
	var low := 0
	var high := _authoritative_notes.size()
	while low < high:
		var mid := (low + high) >> 1
		var existing: Dictionary = _authoritative_notes[mid]
		var existing_time := float(existing.get("time", 0.0))
		var note_time := float(note.get("time", 0.0))
		var existing_before := existing_time < note_time
		if is_equal_approx(existing_time, note_time):
			var existing_lane := int(existing.get("lane", 0))
			var note_lane := int(note.get("lane", 0))
			existing_before = existing_lane < note_lane \
				or (existing_lane == note_lane and int(existing.get("id", -1)) < note_id)
		if existing_before:
			low = mid + 1
		else:
			high = mid
	_authoritative_notes.insert(low, note)


func _on_runtime_note_remove_requested(note_id: int) -> void:
	if not is_active() or not _paused or not _remove_notes_enabled:
		return
	remove_note_requested.emit(note_id)


func _set_runtime_paused(paused: bool) -> void:
	if _runtime == null or not is_instance_valid(_runtime):
		return
	if _runtime.has_method("set_live_paused"):
		_runtime.call("set_live_paused", paused)
	elif paused and _runtime.has_method("pause"):
		_runtime.call("pause")
	elif not paused and _runtime.has_method("resume"):
		_runtime.call("resume")
	else:
		_warn_missing_runtime_method("set_live_paused")


func _seek_runtime(time_sec: float) -> void:
	if _runtime == null or not is_instance_valid(_runtime):
		return
	var clamped := clampf(time_sec, 0.0, _song_duration_sec if _song_duration_sec > 0.0 else INF)
	if _runtime.has_method("seek_live"):
		_runtime.call("seek_live", clamped)
	elif _runtime.has_method("restart_from"):
		_runtime.call("restart_from", clamped)
	else:
		_warn_missing_runtime_method("seek_live")


func _apply_runtime_speed(speed_scale: float) -> void:
	if _runtime != null and is_instance_valid(_runtime) and _runtime.has_method("set_playback_speed"):
		_runtime.call("set_playback_speed", speed_scale)
		return
	var audio_sync := _audio_sync()
	if audio_sync != null and audio_sync.has_method("set_speed_scale"):
		audio_sync.call("set_speed_scale", speed_scale)
	else:
		_warn_missing_runtime_method("set_playback_speed")


func _set_runtime_live_adding(enabled: bool) -> void:
	if _runtime != null and is_instance_valid(_runtime) and _runtime.has_method("set_live_adding"):
		_runtime.call("set_live_adding", enabled)
	elif enabled:
		_warn_missing_runtime_method("set_live_adding")


func _set_runtime_note_removal(enabled: bool) -> void:
	if _runtime != null and is_instance_valid(_runtime) and _runtime.has_method("set_note_removal_enabled"):
		_runtime.call("set_note_removal_enabled", enabled)
	elif enabled:
		_warn_missing_runtime_method("set_note_removal_enabled")


func _refresh_duration_from_runtime() -> void:
	var runtime_duration := 0.0
	if _runtime != null and is_instance_valid(_runtime) and _runtime.has_method("song_duration_sec"):
		runtime_duration = maxf(0.0, float(_runtime.call("song_duration_sec")))
	else:
		var audio_sync := _audio_sync()
		if audio_sync != null and audio_sync.has_method("get_stream_length"):
			runtime_duration = maxf(0.0, float(audio_sync.call("get_stream_length")))
	if runtime_duration > 0.0:
		_song_duration_sec = runtime_duration
	if _timeline_slider != null:
		var duration_for_slider := maxf(maxf(_song_duration_sec, current_time_sec()), TIMELINE_STEP_SEC)
		if not is_equal_approx(_timeline_slider.max_value, duration_for_slider):
			_timeline_slider.max_value = duration_for_slider


func _resolve_audio_path(song_folder: String, manifest: Dictionary, audio_path_override: String = "") -> String:
	var requested := audio_path_override.strip_edges()
	if not requested.is_empty():
		return requested if FileAccess.file_exists(requested) else ""
	var result := AudioResolver.resolve_audio(manifest, song_folder)
	if str(result.get("status", "")) != "available":
		return ""
	return str(result.get("path", ""))


func _resolve_chart_paths(song_folder: String, manifest: Dictionary) -> Dictionary:
	var chart_paths := {}
	for difficulty in DifficultyManager.all_ids():
		var path := SongResolver.get_chart_path(song_folder, difficulty)
		if FileAccess.file_exists(path):
			chart_paths[DifficultyManager.display_name(difficulty)] = path
	var manifest_chart_files: Dictionary = manifest.get("chart_files", {}) as Dictionary
	for difficulty_variant in manifest_chart_files.keys():
		var difficulty := str(difficulty_variant).strip_edges().to_lower()
		var path := SongResolver.get_chart_path(song_folder, difficulty)
		if FileAccess.file_exists(path):
			chart_paths[DifficultyManager.display_name(difficulty)] = path
	return chart_paths


func _audio_sync() -> Node:
	if _runtime != null and is_instance_valid(_runtime):
		return _runtime.get_node_or_null("/root/AudioSync")
	if _overlay != null and is_instance_valid(_overlay):
		return _overlay.get_node_or_null("/root/AudioSync")
	return null


func _reset_audio_speed() -> void:
	var audio_sync := _audio_sync()
	if audio_sync != null and audio_sync.has_method("reset_speed_scale"):
		audio_sync.call("reset_speed_scale")


func _reset_controls() -> void:
	_paused = true
	_live_adding = false
	_remove_notes_enabled = false
	_song_duration_sec = 0.0
	_scrubbing = false
	_active_live_lanes.clear()
	_updating_controls = true
	if _start_pause_button != null:
		_start_pause_button.text = "Start"
	if _timeline_slider != null:
		_timeline_slider.max_value = 0.0
		_timeline_slider.set_value_no_signal(0.0)
	if _speed_spin != null:
		_speed_spin.set_value_no_signal(DEFAULT_SPEED_SCALE)
	if _live_adding_toggle != null:
		_live_adding_toggle.set_pressed_no_signal(false)
	if _remove_notes_toggle != null:
		_remove_notes_toggle.set_pressed_no_signal(false)
		_remove_notes_toggle.disabled = false
	_updating_controls = false
	_update_timestamp(0.0)


func _update_timestamp(position_sec: float) -> void:
	if _timestamp_label == null:
		return
	_timestamp_label.text = "%s / %s" % [_format_time(position_sec), _format_time(_song_duration_sec)]


func _format_time(seconds: float) -> String:
	var milliseconds := maxi(0, int(roundf(seconds * 1000.0)))
	var hours := milliseconds / 3600000
	var minutes := (milliseconds / 60000) % 60
	var whole_seconds := (milliseconds / 1000) % 60
	var millis := milliseconds % 1000
	if hours > 0:
		return "%02d:%02d:%02d.%03d" % [hours, minutes, whole_seconds, millis]
	return "%02d:%02d.%03d" % [minutes, whole_seconds, millis]


func _set_status(message: String) -> void:
	if _status_label != null:
		_status_label.text = message


func _warn_missing_runtime_method(method_name: String) -> void:
	if _missing_runtime_methods.has(method_name):
		return
	_missing_runtime_methods[method_name] = true
	push_warning("ChartPreviewRuntime is missing Live Editor method %s()." % method_name)


func _restore_gameplay_focus_deferred() -> void:
	if _overlay != null and _overlay.visible and _overlay.focus_mode != Control.FOCUS_NONE:
		_overlay.call_deferred("grab_focus")
