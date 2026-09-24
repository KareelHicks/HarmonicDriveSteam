extends Node

signal playback_finished

const DEFAULT_SPEED_SCALE := 1.0
const MIN_SPEED_SCALE := 0.25
const MAX_SPEED_SCALE := 1.5

var _player := AudioStreamPlayer.new()
var _loaded_stream_path := ""
var _paused_position := 0.0
var _is_paused := false
var _speed_scale := DEFAULT_SPEED_SCALE
var _duck_tween: Tween
var _fade_tween: Tween
var _is_fading_out := false
const DEFAULT_VOLUME_DB := 0.0
const MISS_DUCK_VOLUME_DB := -7.5
const MISS_DUCK_IN_TIME := 0.035
const MISS_DUCK_OUT_TIME := 0.16
var _base_volume_linear := 1.0
var _base_volume_db := 0.0


func _ready() -> void:
	add_child(_player)
	_player.bus = "Master"
	_player.pitch_scale = _speed_scale
	if ProfileStore != null and not ProfileStore.profile_changed.is_connected(_on_profile_changed):
		ProfileStore.profile_changed.connect(_on_profile_changed)
	_apply_volume_from_profile()
	_player.finished.connect(_on_finished)


func _on_profile_changed() -> void:
	_apply_volume_from_profile()


func _apply_volume_from_profile() -> void:
	_base_volume_linear = ProfileStore.get_gameplay_music_volume() if ProfileStore != null else 1.0
	if _base_volume_linear <= 0.0001:
		_base_volume_db = -80.0
	else:
		_base_volume_db = lerpf(-40.0, 0.0, clampf(_base_volume_linear, 0.0, 1.0))
	_player.volume_db = _base_volume_db


func load_stream(stream_path: String, force_reload: bool = false) -> bool:
	if stream_path.is_empty():
		_clear_loaded_stream()
		return false
	if not force_reload and _loaded_stream_path == stream_path and _player.stream != null:
		return true

	var stream: AudioStream = null
	# Important: in exported builds `res://` points inside the packed .pck and must be loaded via `load()`,
	# not via `load_from_file()` (which expects a real filesystem path).
	if stream_path.begins_with("res://"):
		stream = ResourceLoader.load(
			stream_path,
			"",
			ResourceLoader.CACHE_MODE_REPLACE if force_reload else ResourceLoader.CACHE_MODE_REUSE
		) as AudioStream
	elif stream_path.begins_with("user://") or stream_path.is_absolute_path():
		var abs := ProjectSettings.globalize_path(stream_path) if stream_path.begins_with("user://") else stream_path
		var lower := stream_path.to_lower()
		if lower.ends_with(".wav"):
			stream = AudioStreamWAV.load_from_file(abs)
		elif lower.ends_with(".ogg"):
			stream = AudioStreamOggVorbis.load_from_file(abs)
		elif lower.ends_with(".mp3"):
			stream = AudioStreamMP3.load_from_file(abs)
	else:
		stream = load(stream_path) as AudioStream
	if stream == null:
		_clear_loaded_stream()
		push_error("Failed to load audio stream: %s" % stream_path)
		return false

	_player.stop()
	_player.stream_paused = false
	_player.stream = stream
	_loaded_stream_path = stream_path
	_clear_audio_tweens()
	_paused_position = 0.0
	_is_paused = false
	return true


func play_from_start() -> void:
	_clear_audio_tweens()
	_paused_position = 0.0
	_is_paused = false
	_player.stream_paused = false
	_player.play()


func stop_playback() -> void:
	_clear_audio_tweens()
	_player.stream_paused = false
	_player.stop()
	_paused_position = 0.0
	_is_paused = false


func pause_playback() -> void:
	if _is_paused:
		return
	_clear_audio_tweens()
	_paused_position = get_song_time_raw()
	if _player.playing:
		# Preserve the transport's buffered position. Stopping and later starting at
		# the audible timestamp applies output-latency compensation a second time.
		_player.stream_paused = true
	_is_paused = true


func resume_playback() -> void:
	if _player.stream == null:
		return
	_clear_audio_tweens()
	if _player.playing:
		_player.stream_paused = false
	else:
		_player.play(_paused_position)
	_is_paused = false


func seek(seconds: float) -> void:
	_paused_position = maxf(0.0, seconds)
	var stream_length := get_stream_length()
	if stream_length > 0.0:
		_paused_position = minf(_paused_position, stream_length)
	if _player.stream == null:
		return
	if _player.playing:
		_player.seek(_paused_position)
	else:
		# Establish a seekable paused transport so resuming does not restart the
		# clock through a stop/play cycle.
		_player.play(_paused_position)
		_player.stream_paused = true
		_is_paused = true


func set_speed_scale(value: float) -> void:
	_speed_scale = clampf(value, MIN_SPEED_SCALE, MAX_SPEED_SCALE)
	_player.pitch_scale = _speed_scale


func get_speed_scale() -> float:
	return _speed_scale


func reset_speed_scale() -> void:
	set_speed_scale(DEFAULT_SPEED_SCALE)


func is_playing() -> bool:
	return _player.playing and not _player.stream_paused and not _is_paused


func get_song_time_raw() -> float:
	if _is_paused or _player.stream_paused:
		return maxf(0.0, _paused_position)
	if _player.playing:
		var position := _player.get_playback_position()
		# Playback position is measured in source-audio seconds, while mix timing and
		# output latency are wall-clock seconds. Convert both wall-clock values into
		# the source timeline so slowed and accelerated editor sessions stay aligned.
		position += AudioServer.get_time_since_last_mix() * _speed_scale
		position -= AudioServer.get_output_latency() * _speed_scale
		position = maxf(0.0, position)
		var stream_length := get_stream_length()
		return minf(position, stream_length) if stream_length > 0.0 else position
	return maxf(0.0, _paused_position)


func get_adjusted_song_time() -> float:
	# The saved offset is wall-clock latency. Convert it into source-timeline
	# seconds so gameplay judgement stays aligned at editor playback speeds too.
	return get_song_time_raw() + (ProfileStore.get_latency_offset_ms() / 1000.0) * _speed_scale


func get_stream_length() -> float:
	if _player.stream == null:
		return 0.0
	return maxf(0.0, _player.stream.get_length())


func duck_for_miss() -> void:
	if not _player.playing or _is_fading_out:
		return
	if is_instance_valid(_duck_tween):
		_duck_tween.kill()
	_duck_tween = create_tween()
	_duck_tween.tween_property(_player, "volume_db", _base_volume_db + MISS_DUCK_VOLUME_DB, MISS_DUCK_IN_TIME)
	_duck_tween.tween_property(_player, "volume_db", _base_volume_db, MISS_DUCK_OUT_TIME)


func fade_out_and_stop(duration: float = 0.25) -> void:
	if not _player.playing:
		stop_playback()
		return
	if is_instance_valid(_duck_tween):
		_duck_tween.kill()
		_duck_tween = null
	_is_fading_out = true
	if is_instance_valid(_fade_tween):
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(_player, "volume_db", -24.0, maxf(0.01, duration))
	_fade_tween.tween_callback(Callable(self, "_finish_fade_out"))


func _reset_ducking() -> void:
	if is_instance_valid(_duck_tween):
		_duck_tween.kill()
	_duck_tween = null
	if not _is_fading_out:
		_player.volume_db = _base_volume_db


func _clear_audio_tweens() -> void:
	_is_fading_out = false
	if is_instance_valid(_duck_tween):
		_duck_tween.kill()
	_duck_tween = null
	if is_instance_valid(_fade_tween):
		_fade_tween.kill()
	_fade_tween = null
	_player.volume_db = _base_volume_db


func _finish_fade_out() -> void:
	stop_playback()


func _on_finished() -> void:
	_clear_audio_tweens()
	# Preserve the terminal cursor long enough for editor-style consumers to show
	# and scrub from the end. Normal gameplay listeners still call stop_playback()
	# during their finish flow, which intentionally resets the position to zero.
	_paused_position = get_stream_length()
	_is_paused = true
	playback_finished.emit()


func _clear_loaded_stream() -> void:
	_clear_audio_tweens()
	_player.stream_paused = false
	_player.stop()
	_player.stream = null
	_loaded_stream_path = ""
	_paused_position = 0.0
	_is_paused = false
