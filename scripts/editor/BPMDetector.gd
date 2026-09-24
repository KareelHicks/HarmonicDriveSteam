extends RefCounted
class_name BPMDetector

const MIN_BPM := 60.0
const MAX_BPM := 200.0


static func detect_bpm_from_stream(stream: AudioStream) -> Dictionary:
	if stream == null:
		return {"ok": false, "bpm": 0.0, "confidence": 0.0, "reason": "No audio loaded."}
	if stream is AudioStreamWAV:
		return detect_bpm_from_wav(stream as AudioStreamWAV)
	return {"ok": false, "bpm": 0.0, "confidence": 0.0, "reason": "Auto BPM currently supports WAV audio only."}


static func detect_bpm_from_wav(wav: AudioStreamWAV) -> Dictionary:
	var mix_rate := int(wav.get_mix_rate())
	if mix_rate <= 0:
		return {"ok": false, "bpm": 0.0, "confidence": 0.0, "reason": "Invalid WAV mix rate."}

	var pcm: PackedByteArray = wav.get_data() if wav.has_method("get_data") else (wav.get("data") as PackedByteArray)
	if pcm.is_empty():
		return {"ok": false, "bpm": 0.0, "confidence": 0.0, "reason": "Empty WAV data."}

	var stereo := bool(wav.is_stereo())
	var channels := 2 if stereo else 1
	var fmt := int(wav.get_format())
	var bytes_per_sample := 2
	if fmt == AudioStreamWAV.FORMAT_8_BITS:
		bytes_per_sample = 1
	elif fmt == AudioStreamWAV.FORMAT_16_BITS:
		bytes_per_sample = 2
	else:
		return {"ok": false, "bpm": 0.0, "confidence": 0.0, "reason": "Unsupported WAV format."}

	var envelope_rate := 200.0
	var env := envelope_from_pcm_abs(pcm, mix_rate, envelope_rate, bytes_per_sample, channels)
	return detect_bpm_from_envelope(env, envelope_rate)


static func detect_bpm_from_envelope(env: PackedFloat32Array, envelope_rate: float) -> Dictionary:
	if env.is_empty() or env.size() < 32:
		return {"ok": false, "bpm": 0.0, "confidence": 0.0, "reason": "Envelope too short for BPM detection."}

	# Onset strength: positive differences, lightly smoothed.
	var onset: PackedFloat32Array = PackedFloat32Array()
	onset.resize(env.size())
	var prev := env[0]
	for i in range(1, env.size()):
		var d := env[i] - prev
		onset[i] = maxf(0.0, d)
		prev = env[i]

	_smooth_in_place(onset, 5)

	var min_lag := int(floorf((60.0 * envelope_rate) / MAX_BPM))
	var max_lag := int(ceilf((60.0 * envelope_rate) / MIN_BPM))
	min_lag = max(1, min_lag)
	max_lag = max(min_lag + 1, max_lag)

	var best_lag := -1
	var best_score := -1.0
	var total_energy := 0.0
	for v in onset:
		total_energy += v * v
	if total_energy <= 0.0:
		return {"ok": false, "bpm": 0.0, "confidence": 0.0, "reason": "No rhythmic energy detected."}

	for lag in range(min_lag, min(max_lag, onset.size() - 1)):
		var s := 0.0
		var n := onset.size() - lag
		for i in range(n):
			s += onset[i] * onset[i + lag]
		if s > best_score:
			best_score = s
			best_lag = lag

	if best_lag <= 0:
		return {"ok": false, "bpm": 0.0, "confidence": 0.0, "reason": "Failed to estimate BPM."}

	var bpm := (60.0 * envelope_rate) / float(best_lag)
	bpm = _normalize_tempo(bpm)
	var confidence := clampf(best_score / total_energy, 0.0, 1.0)
	return {"ok": true, "bpm": bpm, "confidence": confidence, "reason": ""}


static func envelope_from_pcm_abs(pcm: PackedByteArray, mix_rate: int, envelope_rate: float, bytes_per_sample: int, channels: int) -> PackedFloat32Array:
	var hop := int(maxf(1.0, float(mix_rate) / envelope_rate))
	var frame_bytes := bytes_per_sample * channels
	var total_frames := pcm.size() / frame_bytes
	var env: PackedFloat32Array = PackedFloat32Array()
	if total_frames <= hop * 4:
		return env
	env.resize(int(total_frames / hop))

	var env_i := 0
	var frame_idx := 0
	while frame_idx < total_frames and env_i < env.size():
		var amp := _avg_abs_amp(pcm, frame_idx, hop, bytes_per_sample, channels, frame_bytes, total_frames)
		env[env_i] = amp
		env_i += 1
		frame_idx += hop
	return env


static func _normalize_tempo(bpm: float) -> float:
	# Handle half/double tempo ambiguity by folding into [MIN_BPM, MAX_BPM].
	var b := bpm
	while b < MIN_BPM:
		b *= 2.0
	while b > MAX_BPM:
		b *= 0.5
	return b


static func _smooth_in_place(arr: PackedFloat32Array, radius: int) -> void:
	if arr.size() < 3 or radius <= 0:
		return
	var copy := arr.duplicate()
	for i in range(arr.size()):
		var a := int(max(0, i - radius))
		var b := int(min(arr.size() - 1, i + radius))
		var sum := 0.0
		var count := 0
		for j in range(a, b + 1):
			sum += copy[j]
			count += 1
		arr[i] = sum / float(max(1, count))


static func _avg_abs_amp(pcm: PackedByteArray, start_frame: int, frame_count: int, bytes_per_sample: int, channels: int, frame_bytes: int, total_frames: int) -> float:
	var sum := 0.0
	var frames := mini(frame_count, total_frames - start_frame)
	if frames <= 0:
		return 0.0
	for i in range(frames):
		var base := (start_frame + i) * frame_bytes
		sum += _read_frame_amplitude(pcm, base, bytes_per_sample, channels)
	return sum / float(frames)


static func _read_frame_amplitude(pcm: PackedByteArray, base: int, bytes_per_sample: int, channels: int) -> float:
	if bytes_per_sample == 1:
		var sum := 0.0
		for c in range(channels):
			var v := int(pcm[base + c])
			if v > 127:
				v -= 256
			sum += absf(float(v) / 128.0)
		return sum / float(channels)

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
