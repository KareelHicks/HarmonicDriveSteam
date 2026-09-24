extends RefCounted
class_name PlaybackController

const EditorLog := preload("res://scripts/editor/EditorLog.gd")
const POSITION_LOG_INTERVAL_SEC := 0.5

signal play_state_changed(is_playing: bool)
signal position_changed(time_sec: float)
signal audio_loaded(has_audio: bool, length_sec: float)

var _player: AudioStreamPlayer
var _is_playing := false
var _length_sec := 0.0
var _position_sec := 0.0
var _last_position_log_sec := -1.0
var _speed_scale := 1.0
var _time_stretch_effect: AudioEffect

const PLAYBACK_BUS_NAME := &"ChartEditorPlayback"


func attach_player(player: AudioStreamPlayer) -> void:
	_player = player
	_position_sec = 0.0
	_last_position_log_sec = -1.0
	_ensure_playback_bus()
	_apply_speed_settings()
	_update_audio_loaded()


func set_stream(stream: AudioStream) -> void:
	if _player == null:
		return
	_player.stream = stream
	_position_sec = 0.0
	_last_position_log_sec = -1.0
	_is_playing = false
	_player.stream_paused = false
	_player.stop()
	_apply_speed_settings()
	_update_audio_loaded()


func has_audio() -> bool:
	return _player != null and _player.stream != null


func length_sec() -> float:
	return _length_sec


func is_playing() -> bool:
	return _is_playing


func toggle_play() -> void:
	if _player == null or _player.stream == null:
		return
	if _is_playing:
		pause()
	else:
		play()


func play() -> void:
	if _player == null or _player.stream == null:
		return
	if _player.playing:
		_player.stream_paused = false
	else:
		_player.play(_position_sec)
	_apply_speed_settings()
	_position_sec = _clamp_position(_position_sec)
	_last_position_log_sec = -1.0
	_is_playing = true
	play_state_changed.emit(true)


func pause() -> void:
	if _player == null:
		return
	_position_sec = _read_audible_position()
	if _player.playing:
		_player.stream_paused = true
	_is_playing = false
	play_state_changed.emit(false)


func seek(time_sec: float) -> void:
	if _player == null:
		return
	var clamped := _clamp_position(time_sec)
	_position_sec = clamped
	if _player.stream == null:
		EditorLog.info("playback", "seek target=%.3f emitted=%.3f" % [time_sec, clamped])
		position_changed.emit(clamped)
		return

	if _player.playing:
		_player.seek(clamped)
	else:
		# AudioStreamPlayer.seek() does nothing unless playing; start paused at desired position.
		_player.play(clamped)
		_player.stream_paused = true
	EditorLog.info("playback", "seek target=%.3f emitted=%.3f" % [time_sec, clamped])
	position_changed.emit(clamped)


func set_speed_scale(value: float) -> void:
	_speed_scale = clampf(value, 0.25, 1.5)
	_apply_speed_settings()


func speed_scale() -> float:
	return _speed_scale

func get_position() -> float:
	if _player == null:
		return 0.0
	if _player.stream == null:
		return _position_sec
	if _player.playing and not _player.stream_paused:
		_position_sec = _read_audible_position()
	return _position_sec


func process_update() -> void:
	if _player == null:
		return
	if _player.stream == null:
		return
	if _is_playing and _player.playing and not _player.stream_paused:
		var raw_pos := _clamp_position(_player.get_playback_position())
		var since_last_mix := AudioServer.get_time_since_last_mix()
		var mixed_pos := _mixed_timeline_position(raw_pos, since_last_mix)
		var latency := _playback_latency_compensation()
		var pos := _clamp_position(mixed_pos - latency)
		_position_sec = pos
		if _last_position_log_sec < 0.0 or pos - _last_position_log_sec >= POSITION_LOG_INTERVAL_SEC:
			EditorLog.info("playback", "tick raw=%.3f mixed=%.3f latency=%.3f speed=%.2f emitted=%.3f" % [raw_pos, mixed_pos, latency, _speed_scale, pos])
			_last_position_log_sec = pos
		position_changed.emit(pos)


func _update_audio_loaded() -> void:
	_length_sec = 0.0
	var has := false
	if _player != null and _player.stream != null:
		has = true
		_length_sec = maxf(0.0, _player.stream.get_length())
	audio_loaded.emit(has, _length_sec)


func _ensure_playback_bus() -> void:
	if _player == null:
		return
	if AudioServer.get_bus_index(PLAYBACK_BUS_NAME) < 0:
		AudioServer.add_bus(AudioServer.bus_count)
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, PLAYBACK_BUS_NAME)
		AudioServer.set_bus_send(idx, "Master")
	_player.bus = PLAYBACK_BUS_NAME
	var idx2 := AudioServer.get_bus_index(PLAYBACK_BUS_NAME)
	if idx2 < 0:
		return
	# Optional: preserve-pitch time-stretch if available.
	if ClassDB.class_exists("AudioEffectTimeStretch"):
		for i in range(AudioServer.get_bus_effect_count(idx2)):
			var eff := AudioServer.get_bus_effect(idx2, i)
			if eff != null and eff.get_class() == "AudioEffectTimeStretch":
				_time_stretch_effect = eff
				return
		var inst: Object = ClassDB.instantiate("AudioEffectTimeStretch")
		if inst != null and inst is AudioEffect:
			_time_stretch_effect = inst
			AudioServer.add_bus_effect(idx2, _time_stretch_effect, 0)
		else:
			_time_stretch_effect = null


func _apply_speed_settings() -> void:
	if _player == null:
		return
	# Tape style only: pitch changes with speed (simple and reliable).
	_player.pitch_scale = _speed_scale
	# If a time-stretch effect was added for other reasons, ensure it's disabled.
	if _time_stretch_effect != null and _time_stretch_effect.has_property("tempo"):
		_time_stretch_effect.set("tempo", 1.0)


func _read_audible_position() -> float:
	if _player == null or _player.stream == null:
		return _position_sec
	if _player.playing:
		var raw_pos := _clamp_position(_player.get_playback_position())
		var mixed_pos := _mixed_timeline_position(raw_pos, AudioServer.get_time_since_last_mix())
		return _clamp_position(mixed_pos - _playback_latency_compensation())
	return _position_sec


func _mixed_timeline_position(raw_position_sec: float, real_seconds_since_mix: float) -> float:
	# The waveform and judgement line use source-audio timeline seconds. At a
	# non-1.0 pitch scale, wall-clock time since the last mix advances through
	# that timeline by real_seconds * speed_scale.
	return _clamp_position(raw_position_sec + maxf(0.0, real_seconds_since_mix) * _speed_scale)


func _clamp_position(time_sec: float) -> float:
	var clamped := maxf(0.0, time_sec)
	if _length_sec > 0.0:
		clamped = minf(clamped, _length_sec)
	return clamped


func _playback_latency_compensation() -> float:
	# Output latency is reported in wall-clock seconds; convert it to the same
	# source-audio timeline used by get_playback_position() and the waveform.
	return maxf(0.0, AudioServer.get_output_latency()) * _speed_scale
