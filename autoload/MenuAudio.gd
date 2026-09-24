extends Node

signal playback_started(song_id: String)
signal playback_stopped

const ChartLoader := preload("res://scripts/gameplay/ChartLoader.gd")
const GameModeConfig := preload("res://scripts/gameplay/GameModeConfig.gd")
const MENU_CHART_DIFFICULTIES := ["Professional", "Expert", "Hard", "Medium", "Easy"]
const MENU_EMS_LOOKAHEAD := 0.035

var _player := AudioStreamPlayer.new()
var _current_song_id := ""
var _current_stream_path := ""
var _mode := "stopped"
var _last_preview_song_id := ""
var _menu_context := "title" # "title" | "song_select" | other
var _title_muted := false
var _volume_linear := 1.0
var _ems_chart_notes: Array[Dictionary] = []
var _ems_chart_index := 0
var _ems_lane_count := 5
var _ems_recent_note_energy := 0.0
var _ems_last_song_time := 0.0


func _ready() -> void:
	add_child(_player)
	_player.bus = "Master"
	_player.finished.connect(_on_finished)
	if ProfileStore != null and not ProfileStore.profile_changed.is_connected(_on_profile_changed):
		ProfileStore.profile_changed.connect(_on_profile_changed)
	_apply_volume_from_profile()
	set_process(true)


func _process(delta: float) -> void:
	if EmotionalMotionSystem == null or not _player.playing or _mode == "stopped":
		return
	var previewing := _mode == "preview"
	var song_time := _current_playback_time()
	if song_time + 0.10 < _ems_last_song_time:
		_reset_ems_chart_cursor(song_time)
	_ems_last_song_time = song_time

	_fire_due_chart_notes(song_time + MENU_EMS_LOOKAHEAD, previewing)
	_ems_recent_note_energy = maxf(0.0, _ems_recent_note_energy - delta * 0.86)

	var base_energy := 0.54 if previewing else 0.36
	var base_density := 0.20 if previewing else 0.12
	if _ems_chart_notes.is_empty():
		base_energy *= 0.72
		base_density *= 0.72
	EmotionalMotionSystem.set_combo_energy(clampf(base_energy + _ems_recent_note_energy * 0.42, 0.0, 1.0))
	EmotionalMotionSystem.set_note_density(clampf(base_density + _ems_recent_note_energy * 0.62, 0.0, 1.0))


func play_random_song(exclude_song_id: String = "") -> bool:
	var songs: Array[Dictionary] = ContentRegistry.get_songs()
	var candidates: Array[Dictionary] = []
	var excluded_song_ids: Dictionary = {}
	if not exclude_song_id.is_empty():
		excluded_song_ids[exclude_song_id] = true
	if _mode == "preview" and not _current_song_id.is_empty():
		excluded_song_ids[_current_song_id] = true
	if not _last_preview_song_id.is_empty():
		excluded_song_ids[_last_preview_song_id] = true
	for song in songs:
		var audio_path: String = str(song.get("audio_path", ""))
		if audio_path.is_empty():
			continue
		if excluded_song_ids.has(str(song.get("id", ""))):
			continue
		candidates.append(song)
	if candidates.is_empty():
		candidates = songs.filter(func(song: Dictionary) -> bool:
			return not str(song.get("audio_path", "")).is_empty()
		)
	if candidates.is_empty():
		stop()
		return false
	var song: Dictionary = candidates[randi() % candidates.size()]
	var started := _play_song(song, "random")
	if started:
		_last_preview_song_id = ""
	return started


func play_random_song_if_needed(exclude_song_id: String = "") -> bool:
	if _mode == "random" and _player.playing and _player.stream != null:
		return true
	return play_random_song(exclude_song_id)


func play_song_preview(song_id: String) -> bool:
	if song_id.is_empty():
		stop()
		return false
	if _mode == "preview" and _current_song_id == song_id and _player.playing:
		return true
	var song: Dictionary = ContentRegistry.get_song(song_id)
	if song.is_empty():
		stop()
		return false
	_last_preview_song_id = song_id
	return _play_song(song, "preview")


func play_song_entry_preview(song_entry: Dictionary) -> bool:
	var song_id := str(song_entry.get("id", song_entry.get("song_id", song_entry.get("title", "")))).strip_edges()
	var audio_path := str(song_entry.get("audio_path", "")).strip_edges()
	if audio_path.is_empty():
		stop()
		return false
	if _mode == "preview" and _current_song_id == song_id and _current_stream_path == audio_path and _player.playing:
		return true
	_last_preview_song_id = song_id
	return _play_song(song_entry, "preview")


func stop() -> void:
	_player.stop()
	_player.stream = null
	_current_song_id = ""
	_current_stream_path = ""
	_mode = "stopped"
	_clear_ems_chart()
	playback_stopped.emit()


func get_current_song_id() -> String:
	return _current_song_id


func get_mode() -> String:
	return _mode


func consume_last_preview_song_id() -> String:
	var song_id := _last_preview_song_id
	_last_preview_song_id = ""
	return song_id


func is_playing() -> bool:
	return _player.playing


func set_menu_context(context: String) -> void:
	_menu_context = context.to_lower()
	_apply_effective_volume()


func is_title_muted() -> bool:
	return _title_muted


func set_title_muted(muted: bool) -> void:
	_title_muted = muted
	_apply_effective_volume()


func toggle_title_mute() -> void:
	set_title_muted(not _title_muted)


func _play_song(song: Dictionary, mode: String) -> bool:
	var audio_path: String = str(song.get("audio_path", ""))
	if audio_path.is_empty():
		return false
	var stream := _load_stream(audio_path)
	if stream == null:
		push_error("Failed to load menu audio stream: %s" % audio_path)
		return false
	_player.stop()
	_player.stream = stream
	_current_song_id = str(song.get("id", ""))
	if _current_song_id.is_empty():
		_current_song_id = str(song.get("song_id", song.get("title", "")))
	_current_stream_path = audio_path
	_mode = mode
	_apply_effective_volume()
	_player.play()
	_drive_ems_for_song(song, mode)
	playback_started.emit(_current_song_id)
	return true


func _load_stream(audio_path: String) -> AudioStream:
	if audio_path.begins_with("res://"):
		return load(audio_path) as AudioStream
	if audio_path.begins_with("user://") or audio_path.is_absolute_path():
		var absolute_path := ProjectSettings.globalize_path(audio_path) if audio_path.begins_with("user://") else audio_path
		var lower := audio_path.to_lower()
		if lower.ends_with(".wav"):
			return AudioStreamWAV.load_from_file(absolute_path)
		if lower.ends_with(".ogg"):
			return AudioStreamOggVorbis.load_from_file(absolute_path)
		if lower.ends_with(".mp3"):
			return AudioStreamMP3.load_from_file(absolute_path)
	return load(audio_path) as AudioStream


func _drive_ems_for_song(song: Dictionary, mode: String) -> void:
	if EmotionalMotionSystem == null:
		return
	var bpm := float(song.get("bpm", 120.0))
	if bpm <= 0.0:
		bpm = 120.0
	_load_ems_chart(song)
	EmotionalMotionSystem.set_song_bpm(bpm)
	EmotionalMotionSystem.set_combo_energy(0.68 if mode == "preview" else 0.50)
	EmotionalMotionSystem.set_note_density(0.46 if mode == "preview" else 0.30)
	EmotionalMotionSystem.set_emotional_state("euphoric" if mode == "preview" else "neutral")


func _current_playback_time() -> float:
	if not _player.playing:
		return 0.0
	return maxf(0.0, _player.get_playback_position())


func _load_ems_chart(song: Dictionary) -> void:
	_clear_ems_chart()
	var chart_path := _resolve_menu_chart_path(song)
	if chart_path.is_empty():
		return
	var chart := ChartLoader.load_chart(chart_path)
	if chart.is_empty():
		return
	_ems_lane_count = int(chart.get("lane_count", chart.get("laneCount", _ems_lane_count)))
	var notes_variant: Variant = chart.get("notes", [])
	if notes_variant is not Array:
		return
	for note_variant in notes_variant as Array:
		if note_variant is not Dictionary:
			continue
		var note: Dictionary = note_variant
		if not note.has("time"):
			continue
		_ems_chart_notes.append(note.duplicate(true))
	if _ems_lane_count <= 0:
		_ems_lane_count = _infer_lane_count(_ems_chart_notes)
	_ems_lane_count = maxi(1, _ems_lane_count)


func _clear_ems_chart() -> void:
	_ems_chart_notes.clear()
	_ems_chart_index = 0
	_ems_recent_note_energy = 0.0
	_ems_last_song_time = 0.0
	_ems_lane_count = 5


func _resolve_menu_chart_path(song: Dictionary) -> String:
	var preferred_modes: Array[String] = [GameModeConfig.DEFAULT_MODE]
	for mode_id in GameModeConfig.ORDER:
		if not preferred_modes.has(mode_id):
			preferred_modes.append(mode_id)

	if song.has("modes") and ContentRegistry != null:
		for mode_id in preferred_modes:
			for difficulty in MENU_CHART_DIFFICULTIES:
				var chart_path := str(ContentRegistry.get_chart_path(song, difficulty, mode_id)).strip_edges()
				if _chart_path_exists(chart_path):
					return chart_path

	for key in ["chart_path", "professional_chart_path"]:
		var direct_path := str(song.get(key, "")).strip_edges()
		if _chart_path_exists(direct_path):
			return direct_path

	var chart_paths := song.get("chart_paths", {}) as Dictionary
	for difficulty in MENU_CHART_DIFFICULTIES:
		for key in [difficulty, difficulty.to_lower(), difficulty.to_snake_case()]:
			var chart_path := str(chart_paths.get(key, "")).strip_edges()
			if _chart_path_exists(chart_path):
				return chart_path
	return ""


func _chart_path_exists(chart_path: String) -> bool:
	return not chart_path.is_empty() and FileAccess.file_exists(chart_path)


func _fire_due_chart_notes(until_time: float, previewing: bool) -> void:
	if _ems_chart_notes.is_empty() or EmotionalMotionSystem == null or not EmotionalMotionSystem.has_method("notify_impulse"):
		return
	var fired_count := 0
	while _ems_chart_index < _ems_chart_notes.size():
		var note := _ems_chart_notes[_ems_chart_index]
		var note_time := float(note.get("time", 0.0))
		if note_time > until_time:
			break
		var lane := clampi(int(note.get("lane", 0)), 0, maxi(0, _ems_lane_count - 1))
		var duration := maxf(float(note.get("duration", note.get("length", 0.0))), 0.0)
		var strength := 0.58 if previewing else 0.42
		if duration > 0.05:
			strength += 0.10
		strength = clampf(strength + minf(0.14, float(fired_count) * 0.025), 0.0, 1.0)
		EmotionalMotionSystem.notify_impulse(strength, _lane_to_y_norm(lane), "menu_chart_note", lane)
		fired_count += 1
		_ems_chart_index += 1
	if fired_count > 0:
		_ems_recent_note_energy = minf(1.0, _ems_recent_note_energy + minf(0.34, float(fired_count) * 0.075))


func _reset_ems_chart_cursor(song_time: float) -> void:
	_ems_chart_index = 0
	while _ems_chart_index < _ems_chart_notes.size() and float(_ems_chart_notes[_ems_chart_index].get("time", 0.0)) < song_time:
		_ems_chart_index += 1


func _lane_to_y_norm(lane: int) -> float:
	if _ems_lane_count <= 1:
		return 0.50
	return lerpf(0.18, 0.86, float(lane) / float(_ems_lane_count - 1))


func _infer_lane_count(notes: Array[Dictionary]) -> int:
	var max_lane := 0
	for note in notes:
		max_lane = maxi(max_lane, int(note.get("lane", 0)))
	return max_lane + 1


func _on_finished() -> void:
	if _mode == "random":
		play_random_song(_current_song_id)
		return
	stop()


func _on_profile_changed() -> void:
	_apply_volume_from_profile()


func _apply_volume_from_profile() -> void:
	if ProfileStore == null:
		_volume_linear = 1.0
	else:
		_volume_linear = ProfileStore.get_menu_music_volume()
	_apply_effective_volume()


func _apply_effective_volume() -> void:
	var muted := (_menu_context == "title" and _title_muted)
	if muted or _volume_linear <= 0.0001:
		_player.volume_db = -80.0
		return
	# Map linear [0..1] to a useful dB range.
	_player.volume_db = lerpf(-40.0, 0.0, clampf(_volume_linear, 0.0, 1.0))
