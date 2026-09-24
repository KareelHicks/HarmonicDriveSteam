extends RefCounted
class_name EditorPlaytestManager

const GameModeConfig := preload("res://scripts/gameplay/GameModeConfig.gd")
const DifficultyManager := preload("res://scripts/editor/DifficultyManager.gd")
const SongResolver := preload("res://scripts/songs/SongResolver.gd")
const ChartPreviewRuntimeScript := preload("res://scripts/editor/ChartPreviewRuntime.gd")

signal playtest_started
signal playtest_stopped

var _overlay: PanelContainer
var _close_button: Button
var _runtime_holder: Control

var _runtime: Control
var _song_entry: Dictionary = {}
var _difficulty_id := "expert"
var _mode_id := GameModeConfig.DEFAULT_MODE


func attach(overlay: PanelContainer, close_button: Button, runtime_holder: Control) -> void:
	_overlay = overlay
	_close_button = close_button
	_runtime_holder = runtime_holder
	if _overlay != null:
		_overlay.visible = false
	if _close_button != null and not _close_button.pressed.is_connected(stop):
		_close_button.pressed.connect(stop)


func is_active() -> bool:
	return _runtime != null and is_instance_valid(_runtime) and _overlay.visible


func start_for_project(song_folder: String, manifest: Dictionary, difficulty_id: String, start_time_sec: float) -> Dictionary:
	if song_folder.is_empty():
		return {"ok": false, "error": "No project folder selected."}
	var audio_path := str(manifest.get("audio_path", ""))
	if audio_path.is_empty():
		# Try common project outputs first, then fall back to any supported audio file in folder.
		for candidate in ["song.ogg", "song.wav", "song.mp3", "song.opus"]:
			var p := song_folder.path_join(candidate)
			if FileAccess.file_exists(p):
				audio_path = p
				break
		if audio_path.is_empty():
			var dir := DirAccess.open(song_folder)
			if dir != null:
				var supported := ["wav", "ogg", "mp3", "opus"]
				var found: Array[String] = []
				dir.list_dir_begin()
				while true:
					var name := dir.get_next()
					if name.is_empty():
						break
					if dir.current_is_dir():
						continue
					var lower := String(name).to_lower()
					for ext in supported:
						if lower.ends_with("." + ext):
							found.append(song_folder.path_join(name))
							break
				dir.list_dir_end()
				found.sort()
				if not found.is_empty():
					audio_path = found[0]
	var chart_paths := {}
	for id in DifficultyManager.all_ids():
		var p := SongResolver.get_chart_path(song_folder, id)
		if FileAccess.file_exists(p):
			chart_paths[DifficultyManager.display_name(id)] = p
	var manifest_chart_files: Dictionary = manifest.get("chart_files", {}) as Dictionary
	for id_var in manifest_chart_files.keys():
		var id := str(id_var).strip_edges().to_lower()
		var p := SongResolver.get_chart_path(song_folder, id)
		if FileAccess.file_exists(p):
			chart_paths[DifficultyManager.display_name(id)] = p
	print("[EditorPlaytest] song_folder=%s difficulty=%s start=%.3f" % [song_folder, difficulty_id, start_time_sec])
	print("[EditorPlaytest] audio_path=%s" % audio_path)
	print("[EditorPlaytest] charts=%s" % JSON.stringify(chart_paths))
	if chart_paths.is_empty():
		return {"ok": false, "error": "No chart files found in project."}

	_song_entry = {
		"id": str(manifest.get("song_id", song_folder.get_file())),
		"display_name": str(manifest.get("title", song_folder.get_file())),
		"artist": str(manifest.get("artist", "")),
		"audio_path": audio_path,
		"modes": {
			_mode_id: {
				"charts": chart_paths,
			}
		}
	}
	_difficulty_id = difficulty_id.strip_edges().to_lower()
	_overlay.visible = true

	if _runtime == null or not is_instance_valid(_runtime):
		_runtime = ChartPreviewRuntimeScript.new()
		_runtime_holder.add_child(_runtime)
		_runtime.anchor_right = 1.0
		_runtime.anchor_bottom = 1.0
		_runtime.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_runtime.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_runtime.exited.connect(stop)

	var display := DifficultyManager.display_name(_difficulty_id)
	_runtime.start(_song_entry, display, _mode_id, start_time_sec)
	# Ensure gameplay input providers see lane key events immediately.
	# (ChartEditorScene uses `_input` shortcuts and can leave input marked handled from the click that launched playtest.)
	if _overlay != null:
		_overlay.focus_mode = Control.FOCUS_ALL
		_overlay.grab_focus()
		print("[EditorPlaytest] overlay focused for input capture")
	playtest_started.emit()
	return {"ok": true, "error": ""}


func stop() -> void:
	if _runtime != null and is_instance_valid(_runtime):
		_runtime.stop()
	_overlay.visible = false
	playtest_stopped.emit()


func request_hot_reload() -> void:
	if not is_active():
		return
	_runtime.request_hot_reload()
