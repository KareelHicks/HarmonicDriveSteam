extends RefCounted
class_name WaveformRenderer

signal waveform_ready()

const WAVEFORM_BUCKET_SEC := 0.001

var _ready := false
var _unsupported_reason := ""
var _bucket_sec := WAVEFORM_BUCKET_SEC
var _peaks: PackedFloat32Array = PackedFloat32Array()
var _length_sec := 0.0


func is_ready() -> bool:
	return _ready


func unsupported_reason() -> String:
	return _unsupported_reason


func length_sec() -> float:
	return _length_sec


func clear() -> void:
	_ready = false
	_unsupported_reason = ""
	_peaks = PackedFloat32Array()
	_length_sec = 0.0


func prepare_from_stream(stream: AudioStream) -> void:
	clear()
	if stream == null:
		_unsupported_reason = "No audio loaded."
		waveform_ready.emit()
		return
	_length_sec = maxf(0.0, stream.get_length())
	if stream is AudioStreamWAV:
		_build_from_wav(stream as AudioStreamWAV)
		return
	_unsupported_reason = "Waveform preview currently supports WAV audio only."
	waveform_ready.emit()


func peak_at_time(time_sec: float) -> float:
	if not _ready or _peaks.is_empty():
		return 0.0
	var idx := int(floorf(clampf(time_sec, 0.0, _length_sec) / _bucket_sec))
	idx = clampi(idx, 0, _peaks.size() - 1)
	return _peaks[idx]


func peak_at_time_interpolated(time_sec: float) -> float:
	if not _ready or _peaks.is_empty():
		return 0.0
	var sample_pos := clampf(time_sec, 0.0, _length_sec) / _bucket_sec
	var idx0 := clampi(int(floorf(sample_pos)), 0, _peaks.size() - 1)
	var idx1 := clampi(idx0 + 1, 0, _peaks.size() - 1)
	return lerpf(_peaks[idx0], _peaks[idx1], sample_pos - floorf(sample_pos))


func _build_from_wav(wav: AudioStreamWAV) -> void:
	var mix_rate := int(wav.get_mix_rate())
	if mix_rate <= 0:
		_unsupported_reason = "Invalid WAV mix rate."
		waveform_ready.emit()
		return

	var pcm: PackedByteArray = wav.get_data() if wav.has_method("get_data") else (wav.get("data") as PackedByteArray)
	if pcm.is_empty():
		_unsupported_reason = "Empty WAV data."
		waveform_ready.emit()
		return

	var stereo := bool(wav.is_stereo())
	var channels := 2 if stereo else 1

	var fmt := int(wav.get_format())
	var bytes_per_sample := 2
	if fmt == AudioStreamWAV.FORMAT_8_BITS:
		bytes_per_sample = 1
	elif fmt == AudioStreamWAV.FORMAT_16_BITS:
		bytes_per_sample = 2
	else:
		_unsupported_reason = "Unsupported WAV format."
		waveform_ready.emit()
		return

	# Keep transient placement precise enough for close chart-editor zoom. The
	# PCM scan cost is unchanged; only the compact peak envelope is denser.
	_bucket_sec = WAVEFORM_BUCKET_SEC
	var samples_per_bucket := int(maxf(1.0, float(mix_rate) * _bucket_sec))
	var frame_bytes := bytes_per_sample * channels
	var total_frames := pcm.size() / frame_bytes
	_length_sec = float(total_frames) / float(mix_rate)

	var bucket_count := int(ceilf(_length_sec / _bucket_sec))
	_peaks.resize(bucket_count)

	var frame_idx := 0
	for b in range(bucket_count):
		var max_amp := 0.0
		var frames_in_bucket: int = mini(samples_per_bucket, total_frames - frame_idx)
		if frames_in_bucket <= 0:
			_peaks[b] = 0.0
			continue
		for i in range(frames_in_bucket):
			var base := (frame_idx + i) * frame_bytes
			var amp := _read_frame_amplitude(pcm, base, bytes_per_sample, channels)
			if amp > max_amp:
				max_amp = amp
		_peaks[b] = clampf(max_amp, 0.0, 1.0)
		frame_idx += frames_in_bucket

	_ready = true
	waveform_ready.emit()


func _read_frame_amplitude(pcm: PackedByteArray, base: int, bytes_per_sample: int, channels: int) -> float:
	if bytes_per_sample == 1:
		var sum := 0.0
		for c in range(channels):
			var v := int(pcm[base + c])
			# Signed 8-bit PCM
			if v > 127:
				v -= 256
			sum += absf(float(v) / 128.0)
		return sum / float(channels)

	# 16-bit little endian signed PCM
	var sum16 := 0.0
	for c in range(channels):
		var o := base + (c * 2)
		var lo := int(pcm[o])
		var hi := int(pcm[o + 1])
		var v16 := (hi << 8) | lo
		if v16 >= 32768:
			v16 -= 65536
		sum16 += absf(float(v16) / 32768.0)
	return sum16 / float(channels)
