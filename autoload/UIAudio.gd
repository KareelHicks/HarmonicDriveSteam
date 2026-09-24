extends Node

const SAMPLE_RATE := 22050
const DURATION_SECONDS := 0.045
const PLAYER_COUNT := 6
const MIN_REPEAT_SECONDS := 0.022
const BASE_VOLUME_DB := -32.0

var _navigation_enabled := true
var _stream: AudioStreamWAV
var _players: Array[AudioStreamPlayer] = []
var _next_player := 0
var _last_play_msec := -1000000


func _ready() -> void:
	_stream = _build_navigation_stream()
	for index in PLAYER_COUNT:
		var player := AudioStreamPlayer.new()
		player.name = "NavigationTick%d" % index
		player.bus = "Master"
		player.stream = _stream
		player.volume_db = BASE_VOLUME_DB
		add_child(player)
		_players.append(player)


func set_navigation_enabled(enabled: bool) -> void:
	_navigation_enabled = enabled


func is_navigation_enabled() -> bool:
	return _navigation_enabled


func play_navigation(direction: int = 0, intensity: float = 1.0) -> void:
	if not _navigation_enabled or _players.is_empty() or _stream == null:
		return
	var now := Time.get_ticks_msec()
	if now - _last_play_msec < int(MIN_REPEAT_SECONDS * 1000.0):
		return
	_last_play_msec = now
	var player := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	var direction_pitch := 1.0
	if direction < 0:
		direction_pitch = 0.965
	elif direction > 0:
		direction_pitch = 1.035
	player.stop()
	player.pitch_scale = direction_pitch * randf_range(0.985, 1.015)
	player.volume_db = BASE_VOLUME_DB + linear_to_db(clampf(intensity, 0.55, 1.25))
	player.play()


func _build_navigation_stream() -> AudioStreamWAV:
	var frame_count := int(roundf(float(SAMPLE_RATE) * DURATION_SECONDS))
	var data := PackedByteArray()
	data.resize(frame_count * 2)
	var seed := 0x5A17
	for frame in frame_count:
		var t := float(frame) / float(SAMPLE_RATE)
		var normalized := t / DURATION_SECONDS
		var attack := clampf(t / 0.002, 0.0, 1.0)
		var decay := pow(1.0 - normalized, 1.55)
		var envelope := attack * decay
		var chip_step := 0
		if normalized > 0.66:
			chip_step = 2
		elif normalized > 0.34:
			chip_step = 1
		var chip_freq := 880.0
		if chip_step == 1:
			chip_freq = 1174.66
		elif chip_step == 2:
			chip_freq = 1567.98
		var phase := fmod(chip_freq * t, 1.0)
		var square := 1.0 if phase < 0.5 else -1.0
		var triangle := 1.0 - absf(phase * 2.0 - 1.0) * 2.0
		var body := (square * 0.42 + triangle * 0.20) * envelope
		var click := (1.0 if frame % 2 == 0 else -1.0) * 0.16 * maxf(0.0, 1.0 - t / 0.006)
		seed = int((1103515245 * seed + 12345) & 0x7fffffff)
		var noise := ((float(seed % 2000) / 1000.0) - 1.0) * 0.055 * maxf(0.0, 1.0 - t / 0.008)
		var sample := clampf(body + click + noise, -1.0, 1.0)
		sample = roundf(sample * 10.0) / 10.0
		_write_pcm16(data, frame, sample)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = data
	return wav


func _write_pcm16(data: PackedByteArray, frame: int, sample: float) -> void:
	var value := int(roundf(clampf(sample, -1.0, 1.0) * 32767.0))
	if value < 0:
		value += 65536
	var offset := frame * 2
	data[offset] = value & 0xff
	data[offset + 1] = (value >> 8) & 0xff
