extends RefCounted
class_name AutoChartGenerator

const LaneCountResolver := preload("res://scripts/songs/LaneCountResolver.gd")
const ChartValidator := preload("res://scripts/songs/ChartValidator.gd")

const GENERATOR_VERSION := "auto_chart_pure_godot_v1"
const FEATURE_RATE := 200.0
const MIN_BPM := 60.0
const MAX_BPM := 200.0
const MIN_START_TIME := 0.45
const TIME_KEY_SCALE := 1000.0
const MAX_NOTES_PER_TIME := 3
const MIN_HOLD_LENGTH := 0.30
const HOLD_PADDING := 0.035

const DIFFICULTY_NPS := {
	"easy": 1.08,
	"medium": 1.60,
	"hard": 2.48,
	"expert": 3.58,
	"professional": 6.70,
}

const DIFFICULTY_STEP_DIVISION := {
	"easy": 2,
	"medium": 4,
	"hard": 4,
	"expert": 8,
	"professional": 8,
}

const DIFFICULTY_MIN_SPACING := {
	"easy": 0.26,
	"medium": 0.18,
	"hard": 0.125,
	"expert": 0.095,
	"professional": 0.056,
}

const DIFFICULTY_HOLD_RATIO := {
	"easy": 0.08,
	"medium": 0.08,
	"hard": 0.07,
	"expert": 0.06,
	"professional": 0.05,
}


static func generate_from_wav(
	wav: AudioStreamWAV,
	difficulty: String,
	lane_count: int,
	bpm_hint: float = 0.0,
	offset_hint: float = 0.0,
	seed_text: String = ""
) -> Dictionary:
	var decoded := _decode_wav_features(wav)
	if not bool(decoded.get("ok", false)):
		return decoded

	var normalized_difficulty := difficulty.strip_edges().to_lower()
	if not DIFFICULTY_NPS.has(normalized_difficulty):
		normalized_difficulty = "expert"
	var lanes := LaneCountResolver.clamp_lane_count(lane_count)
	var duration := float(decoded.get("duration", 0.0))
	if duration <= 1.0:
		return {"ok": false, "notes": [], "error": "Audio is too short for auto charting.", "warnings": []}

	var tempo := _detect_tempo(decoded, bpm_hint, offset_hint)
	var bpm := float(tempo.get("bpm", bpm_hint if bpm_hint > 0.0 else 128.0))
	var offset := float(tempo.get("offset", offset_hint))
	var confidence := float(tempo.get("confidence", 0.0))
	var beat_sec := 60.0 / maxf(1.0, bpm)
	var step_division := int(DIFFICULTY_STEP_DIVISION.get(normalized_difficulty, 4))
	var step_sec := beat_sec / float(maxi(1, step_division))
	var rng := RandomNumberGenerator.new()
	rng.seed = _stable_seed("%s|%s|%d|%.3f|%.3f|%.3f" % [
		GENERATOR_VERSION,
		seed_text,
		lanes,
		duration,
		bpm,
		offset,
	])

	var frames: Array[Dictionary] = decoded.get("frames", []) as Array[Dictionary]
	var avg_env := float(decoded.get("avg_env", 0.0))
	var intensity_scale := clampf(0.82 + avg_env * 0.80 + confidence * 0.16, 0.62, 1.22)
	var target_nps := float(DIFFICULTY_NPS.get(normalized_difficulty, 3.58)) * intensity_scale
	if normalized_difficulty == "professional":
		target_nps = clampf(target_nps, 4.20, 8.20)
	var target_notes := maxi(4, int(roundf(duration * target_nps)))

	var warnings: Array[String] = []
	if confidence < 0.12:
		warnings.append("Low BPM confidence; review timing before publishing.")
	var candidates := _build_note_candidates(decoded, bpm, offset, step_sec, normalized_difficulty)
	if candidates.is_empty():
		return {"ok": false, "notes": [], "error": "No usable rhythmic events were found.", "warnings": warnings}

	var notes: Array[Dictionary] = []
	var occupied_by_time: Dictionary = {}
	var note_times_by_lane := _empty_lane_arrays(lanes)
	var hold_intervals_by_lane := _empty_lane_arrays(lanes)

	var hold_target := maxi(1, int(roundf(float(target_notes) * float(DIFFICULTY_HOLD_RATIO.get(normalized_difficulty, 0.06)))))
	var hold_count := _place_holds(
		notes,
		decoded,
		bpm,
		offset,
		step_sec,
		normalized_difficulty,
		lanes,
		hold_target,
		occupied_by_time,
		note_times_by_lane,
		hold_intervals_by_lane,
		rng
	)

	var tap_target := maxi(1, target_notes - hold_count)
	_place_taps(
		notes,
		candidates,
		tap_target,
		normalized_difficulty,
		lanes,
		beat_sec,
		occupied_by_time,
		note_times_by_lane,
		hold_intervals_by_lane,
		rng
	)

	if notes.is_empty():
		return {"ok": false, "notes": [], "error": "Auto chart produced no notes.", "warnings": warnings}
	if hold_count <= 0:
		warnings.append("No sustained region was strong enough for hold notes.")

	_sort_and_assign_ids(notes)
	var tap_count := 0
	var final_hold_count := 0
	for note in notes:
		if str(note.get("type", "tap")).to_lower() == "hold":
			final_hold_count += 1
		else:
			tap_count += 1

	var nps := float(notes.size()) / maxf(1.0, duration)
	var validation := ChartValidator.validate_chart({
		"version": 1,
		"difficulty": normalized_difficulty,
		"lane_count": lanes,
		"notes": notes,
	}, normalized_difficulty)
	if not ChartValidator.is_valid(validation):
		return {
			"ok": false,
			"notes": notes,
			"error": "Generated chart failed validation: %s" % _first_validation_error(validation),
			"warnings": warnings,
		}

	return {
		"ok": true,
		"notes": notes,
		"bpm": snappedf(bpm, 0.001),
		"offset": snappedf(offset, 0.001),
		"confidence": confidence,
		"tap_count": tap_count,
		"hold_count": final_hold_count,
		"nps": nps,
		"duration": duration,
		"generator_version": GENERATOR_VERSION,
		"warnings": warnings,
	}


static func _decode_wav_features(wav: AudioStreamWAV) -> Dictionary:
	if wav == null:
		return {"ok": false, "notes": [], "error": "No WAV audio was provided.", "warnings": []}
	var mix_rate := int(wav.get_mix_rate())
	if mix_rate <= 0:
		return {"ok": false, "notes": [], "error": "Invalid WAV mix rate.", "warnings": []}
	var pcm: PackedByteArray = wav.get_data() if wav.has_method("get_data") else (wav.get("data") as PackedByteArray)
	if pcm.is_empty():
		return {"ok": false, "notes": [], "error": "Empty WAV data.", "warnings": []}

	var fmt := int(wav.get_format())
	var bytes_per_sample := 2
	if fmt == AudioStreamWAV.FORMAT_8_BITS:
		bytes_per_sample = 1
	elif fmt == AudioStreamWAV.FORMAT_16_BITS:
		bytes_per_sample = 2
	else:
		return {"ok": false, "notes": [], "error": "Auto Chart supports 8-bit and 16-bit PCM WAV files.", "warnings": []}

	var channels := 2 if bool(wav.is_stereo()) else 1
	var frame_bytes := bytes_per_sample * channels
	var total_frames := int(pcm.size() / frame_bytes)
	if total_frames <= 0:
		return {"ok": false, "notes": [], "error": "WAV file has no PCM frames.", "warnings": []}

	var hop := int(maxf(1.0, float(mix_rate) / FEATURE_RATE))
	var feature_count := int(ceilf(float(total_frames) / float(hop)))
	var frames: Array[Dictionary] = []
	frames.resize(feature_count)

	var prev_sample := 0.0
	var max_env := 0.0001
	var max_rms := 0.0001
	var max_high := 0.0001
	for feature_idx in range(feature_count):
		var start_frame := feature_idx * hop
		var count := mini(hop, total_frames - start_frame)
		var sum_abs := 0.0
		var sum_sq := 0.0
		var sum_high := 0.0
		var zero_crossings := 0
		var last_sign := 0
		for local_idx in range(count):
			var pcm_offset := (start_frame + local_idx) * frame_bytes
			var sample := _read_frame_sample(pcm, pcm_offset, bytes_per_sample, channels)
			var abs_sample := absf(sample)
			sum_abs += abs_sample
			sum_sq += sample * sample
			sum_high += absf(sample - prev_sample)
			var sign := 1 if sample >= 0.0 else -1
			if last_sign != 0 and sign != last_sign:
				zero_crossings += 1
			last_sign = sign
			prev_sample = sample
		var denom := float(maxi(1, count))
		var env := sum_abs / denom
		var rms := sqrt(sum_sq / denom)
		var high := sum_high / denom
		var zcr := float(zero_crossings) / denom
		max_env = maxf(max_env, env)
		max_rms = maxf(max_rms, rms)
		max_high = maxf(max_high, high)
		frames[feature_idx] = {
			"time": float(start_frame) / float(mix_rate),
			"env": env,
			"rms": rms,
			"high": high,
			"zcr": zcr,
			"onset": 0.0,
			"smooth": 0.0,
			"phrase": 0.0,
		}

	var avg_env := 0.0
	for i in range(frames.size()):
		var frame: Dictionary = frames[i]
		frame["env"] = float(frame.get("env", 0.0)) / max_env
		frame["rms"] = float(frame.get("rms", 0.0)) / max_rms
		frame["high"] = float(frame.get("high", 0.0)) / max_high
		frames[i] = frame
		avg_env += float(frame.get("env", 0.0))
	avg_env /= float(maxi(1, frames.size()))

	_build_onset_features(frames)
	return {
		"ok": true,
		"frames": frames,
		"feature_rate": FEATURE_RATE,
		"duration": float(total_frames) / float(mix_rate),
		"avg_env": avg_env,
	}


static func _build_onset_features(frames: Array[Dictionary]) -> void:
	if frames.is_empty():
		return
	var max_onset := 0.0001
	var prev_env := float(frames[0].get("env", 0.0))
	var prev_rms := float(frames[0].get("rms", 0.0))
	var prev_high := float(frames[0].get("high", 0.0))
	for i in range(frames.size()):
		var frame: Dictionary = frames[i]
		var env := float(frame.get("env", 0.0))
		var rms := float(frame.get("rms", 0.0))
		var high := float(frame.get("high", 0.0))
		var onset := maxf(0.0, env - prev_env) * 0.58
		onset += maxf(0.0, rms - prev_rms) * 0.18
		onset += maxf(0.0, high - prev_high) * 0.34
		onset += high * 0.06
		frame["onset"] = onset
		max_onset = maxf(max_onset, onset)
		frames[i] = frame
		prev_env = env
		prev_rms = rms
		prev_high = high

	var smoothed_env := _smooth_values(frames, "env", 12)
	var phrase_env := _smooth_values(frames, "env", 80)
	for i in range(frames.size()):
		var frame: Dictionary = frames[i]
		frame["onset"] = float(frame.get("onset", 0.0)) / max_onset
		frame["smooth"] = smoothed_env[i]
		frame["phrase"] = phrase_env[i]
		frames[i] = frame


static func _detect_tempo(decoded: Dictionary, bpm_hint: float, offset_hint: float) -> Dictionary:
	var frames: Array[Dictionary] = decoded.get("frames", []) as Array[Dictionary]
	if frames.size() < 32:
		return {"bpm": bpm_hint if bpm_hint > 0.0 else 128.0, "offset": offset_hint, "confidence": 0.0}

	var min_lag := int(floorf((60.0 * FEATURE_RATE) / MAX_BPM))
	var max_lag := int(ceilf((60.0 * FEATURE_RATE) / MIN_BPM))
	var total_energy := 0.0001
	for frame in frames:
		var onset := float(frame.get("onset", 0.0))
		total_energy += onset * onset

	var candidates: Array[Dictionary] = []
	for lag in range(maxi(1, min_lag), mini(max_lag, frames.size() - 1)):
		var score := 0.0
		var limit := frames.size() - lag
		for i in range(limit):
			score += float(frames[i].get("onset", 0.0)) * float(frames[i + lag].get("onset", 0.0))
		if score <= 0.0:
			continue
		var raw_bpm := (60.0 * FEATURE_RATE) / float(lag)
		for folded_bpm in _tempo_variants(raw_bpm):
			var adjusted := score * _edm_tempo_bias(float(folded_bpm), bpm_hint)
			candidates.append({"bpm": float(folded_bpm), "lag": int(roundf((60.0 * FEATURE_RATE) / float(folded_bpm))), "score": score, "adjusted": adjusted})

	if candidates.is_empty():
		return {"bpm": bpm_hint if bpm_hint > 0.0 else 128.0, "offset": offset_hint, "confidence": 0.0}

	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("adjusted", 0.0)) > float(b.get("adjusted", 0.0))
	)
	var best: Dictionary = candidates[0]
	var lag := clampi(int(best.get("lag", 1)), 1, frames.size() - 1)
	var phase := _detect_offset_phase(frames, lag)
	var offset := float(phase) / FEATURE_RATE
	var bpm := float(best.get("bpm", 128.0))
	var confidence := clampf(float(best.get("score", 0.0)) / total_energy, 0.0, 1.0)
	if bpm_hint > 0.0 and confidence < 0.08:
		bpm = bpm_hint
		offset = offset_hint
	return {"bpm": bpm, "offset": offset, "confidence": confidence}


static func _tempo_variants(raw_bpm: float) -> Array:
	var values := []
	var b := raw_bpm
	while b < MIN_BPM:
		b *= 2.0
	while b > MAX_BPM:
		b *= 0.5
	values.append(b)
	if b * 2.0 <= MAX_BPM:
		values.append(b * 2.0)
	if b * 0.5 >= MIN_BPM:
		values.append(b * 0.5)
	return values


static func _edm_tempo_bias(bpm: float, bpm_hint: float) -> float:
	var bias := 1.0
	if bpm >= 124.0 and bpm <= 148.0:
		bias += 0.16
	elif bpm >= 115.0 and bpm <= 158.0:
		bias += 0.07
	elif bpm < 95.0:
		bias -= 0.11
	if bpm_hint > 0.0:
		var hint_error := absf(bpm - bpm_hint)
		if hint_error <= 2.0:
			bias += 0.10
		elif hint_error <= 6.0:
			bias += 0.04
	return bias


static func _detect_offset_phase(frames: Array[Dictionary], lag: int) -> int:
	var best_phase := 0
	var best_score := -INF
	for phase in range(lag):
		var score := 0.0
		var i := phase
		while i < frames.size():
			score += float(frames[i].get("onset", 0.0)) * 1.00
			score += float(frames[i].get("smooth", 0.0)) * 0.10
			i += lag
		if score > best_score:
			best_score = score
			best_phase = phase
	return best_phase


static func _build_note_candidates(decoded: Dictionary, bpm: float, offset: float, step_sec: float, difficulty: String) -> Array[Dictionary]:
	var frames: Array[Dictionary] = decoded.get("frames", []) as Array[Dictionary]
	var duration := float(decoded.get("duration", 0.0))
	var beat_sec := 60.0 / maxf(1.0, bpm)
	var threshold := _onset_threshold(frames, difficulty)
	var raw_candidates: Array[Dictionary] = []

	for i in range(2, frames.size() - 2):
		var onset := float(frames[i].get("onset", 0.0))
		if onset < threshold:
			continue
		if onset < float(frames[i - 1].get("onset", 0.0)) or onset < float(frames[i + 1].get("onset", 0.0)):
			continue
		var time := float(frames[i].get("time", 0.0))
		raw_candidates.append({"time": time, "source": "onset", "base_score": onset * 2.3})

	var t := offset
	while t < duration:
		raw_candidates.append({"time": t, "source": "grid", "base_score": 0.30})
		t += step_sec

	var dedup: Dictionary = {}
	for raw in raw_candidates:
		var snapped := _snap_to_grid(float(raw.get("time", 0.0)), offset, step_sec)
		if snapped < MIN_START_TIME or snapped > duration - 0.20:
			continue
		var score := float(raw.get("base_score", 0.0))
		score += _feature_near_time(frames, snapped, "onset", 0.045) * 1.35
		score += _feature_near_time(frames, snapped, "high", 0.045) * 0.72
		score += _feature_near_time(frames, snapped, "zcr", 0.035) * 0.16
		score += _feature_at_time(frames, snapped, "smooth") * 0.52
		score += _feature_at_time(frames, snapped, "phrase") * 0.22
		score += _beat_accent_score(snapped, offset, beat_sec)
		var key := _time_key(snapped)
		if not dedup.has(key) or score > float((dedup[key] as Dictionary).get("score", 0.0)):
			dedup[key] = {"time": snapped, "score": score}

	var candidates: Array[Dictionary] = []
	for key in dedup.keys():
		candidates.append(dedup[key])
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var score_a := float(a.get("score", 0.0))
		var score_b := float(b.get("score", 0.0))
		if is_equal_approx(score_a, score_b):
			return float(a.get("time", 0.0)) < float(b.get("time", 0.0))
		return score_a > score_b
	)
	return candidates


static func _place_holds(
	notes: Array[Dictionary],
	decoded: Dictionary,
	bpm: float,
	offset: float,
	step_sec: float,
	difficulty: String,
	lane_count: int,
	target_count: int,
	occupied_by_time: Dictionary,
	note_times_by_lane: Dictionary,
	hold_intervals_by_lane: Dictionary,
	rng: RandomNumberGenerator
	) -> int:
	var frames: Array[Dictionary] = decoded.get("frames", []) as Array[Dictionary]
	var regions := _detect_sustained_regions(frames)
	if regions.is_empty():
		return 0
	var beat_sec := 60.0 / maxf(1.0, bpm)
	var rank := _difficulty_rank(difficulty)
	regions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("score", 0.0)) > float(b.get("score", 0.0))
	)
	var placed := 0
	for region in regions:
		if placed >= target_count:
			break
		var region_start := float(region.get("start", 0.0))
		var region_end := float(region.get("end", 0.0))
		var start_time := _snap_to_grid(region_start + beat_sec * 0.25, offset, step_sec)
		var max_len := region_end - start_time - HOLD_PADDING
		if max_len < MIN_HOLD_LENGTH:
			continue
		var preferred_beats := 1.0
		if rank >= 3:
			preferred_beats = 1.5
		elif rank <= 1:
			preferred_beats = 0.75
		var length := minf(max_len, beat_sec * preferred_beats)
		length = maxf(MIN_HOLD_LENGTH, _snap_duration(length, step_sec))
		if length > max_len + 0.001:
			length = max_len
		if length < MIN_HOLD_LENGTH:
			continue
		var lane := _choose_lane(start_time, lane_count, occupied_by_time, note_times_by_lane, hold_intervals_by_lane, length, rng)
		if lane < 0:
			continue
		var note := {
			"time": snappedf(start_time, 0.001),
			"lane": lane,
			"type": "hold",
			"length": snappedf(length, 0.001),
			"duration": snappedf(length, 0.001),
		}
		notes.append(note)
		_mark_note(note, occupied_by_time, note_times_by_lane, hold_intervals_by_lane)
		placed += 1
	return placed


static func _place_taps(
	notes: Array[Dictionary],
	candidates: Array[Dictionary],
	target_count: int,
	difficulty: String,
	lane_count: int,
	beat_sec: float,
	occupied_by_time: Dictionary,
	note_times_by_lane: Dictionary,
	hold_intervals_by_lane: Dictionary,
	rng: RandomNumberGenerator
) -> int:
	var min_spacing := float(DIFFICULTY_MIN_SPACING.get(difficulty, 0.095))
	var placed := 0
	var selected_times: Array[float] = []
	var rank := _difficulty_rank(difficulty)
	for candidate in candidates:
		if placed >= target_count:
			break
		var time := float(candidate.get("time", 0.0))
		if _nearest_time_distance(time, selected_times) < min_spacing:
			continue
		var score := float(candidate.get("score", 0.0))
		var key := _time_key(time)
		var existing_count := int((occupied_by_time.get(key, {}) as Dictionary).size())
		var max_group := mini(MAX_NOTES_PER_TIME, lane_count)
		var chord_size := _choose_chord_size(score, rank, existing_count, max_group, rng)
		var group_placed := 0
		for chord_idx in range(chord_size):
			if placed >= target_count:
				break
			var lane := _choose_lane(time, lane_count, occupied_by_time, note_times_by_lane, hold_intervals_by_lane, 0.0, rng, chord_idx)
			if lane < 0:
				continue
			var note := {
				"time": snappedf(time, 0.001),
				"lane": lane,
				"type": "tap",
			}
			notes.append(note)
			_mark_note(note, occupied_by_time, note_times_by_lane, hold_intervals_by_lane)
			placed += 1
			group_placed += 1
		if group_placed > 0:
			selected_times.append(time)
	return placed


static func _choose_chord_size(score: float, difficulty_rank: int, existing_count: int, max_group: int, rng: RandomNumberGenerator) -> int:
	var available := maxi(0, max_group - existing_count)
	if available <= 1 or difficulty_rank <= 1:
		return mini(1, available)
	var chance := 0.0
	if difficulty_rank == 2:
		chance = 0.12
	elif difficulty_rank == 3:
		chance = 0.20
	else:
		chance = 0.26
	if score > 2.8:
		chance += 0.08
	if rng.randf() >= chance:
		return 1
	if available >= 3 and difficulty_rank >= 3 and rng.randf() < 0.22:
		return 3
	return mini(2, available)


static func _choose_lane(
	time: float,
	lane_count: int,
	occupied_by_time: Dictionary,
	note_times_by_lane: Dictionary,
	hold_intervals_by_lane: Dictionary,
	hold_length: float,
	rng: RandomNumberGenerator,
	chord_index: int = 0
) -> int:
	var key := _time_key(time)
	var occupied: Dictionary = occupied_by_time.get(key, {})
	var preferred := int(absf(sin(time * 3.731 + float(chord_index) * 1.7)) * float(lane_count))
	preferred = clampi(preferred + (chord_index * 2), 0, lane_count - 1)
	var order: Array[int] = []
	for i in range(lane_count):
		order.append((preferred + i) % lane_count)
	if rng.randf() < 0.35:
		_shuffle(order, rng)
	for lane in order:
		if occupied.has(lane):
			continue
		if _lane_has_hold_at(hold_intervals_by_lane, lane, time):
			continue
		if hold_length > 0.0:
			if _lane_hold_overlaps(hold_intervals_by_lane, lane, time, time + hold_length):
				continue
			if _lane_note_exists_during(note_times_by_lane, lane, time, time + hold_length):
				continue
		if _recent_same_lane_note(note_times_by_lane, lane, time, 0.105):
			continue
		return lane
	for lane in order:
		if occupied.has(lane):
			continue
		if _lane_has_hold_at(hold_intervals_by_lane, lane, time):
			continue
		if hold_length > 0.0 and (_lane_hold_overlaps(hold_intervals_by_lane, lane, time, time + hold_length) or _lane_note_exists_during(note_times_by_lane, lane, time, time + hold_length)):
			continue
		return lane
	return -1


static func _detect_sustained_regions(frames: Array[Dictionary]) -> Array[Dictionary]:
	var smooth_values: Array[float] = []
	for frame in frames:
		smooth_values.append(float(frame.get("smooth", 0.0)))
	var threshold := maxf(0.08, _percentile(smooth_values, 0.52) * 0.82)
	var min_len_frames := int(roundf(0.42 * FEATURE_RATE))
	var gap_tolerance_frames := int(roundf(0.18 * FEATURE_RATE))
	var regions: Array[Dictionary] = []
	var start := -1
	var last_qualified := -1
	var accum := 0.0
	var accum_count := 0
	for i in range(frames.size()):
		var smooth := float(frames[i].get("smooth", 0.0))
		var qualifies := smooth >= threshold
		if qualifies:
			if start < 0:
				start = i
				accum = 0.0
				accum_count = 0
			last_qualified = i
			accum += smooth
			accum_count += 1
		elif start >= 0 and i - last_qualified > gap_tolerance_frames:
			if last_qualified - start + 1 >= min_len_frames:
				var start_time := float(frames[start].get("time", 0.0))
				var end_time := float(frames[last_qualified].get("time", 0.0))
				regions.append({"start": start_time, "end": end_time, "score": accum / float(maxi(1, accum_count))})
			start = -1
			last_qualified = -1
			accum = 0.0
			accum_count = 0
	if start >= 0 and last_qualified - start + 1 >= min_len_frames:
		regions.append({
			"start": float(frames[start].get("time", 0.0)),
			"end": float(frames[last_qualified].get("time", 0.0)),
			"score": accum / float(maxi(1, accum_count)),
		})
	return regions


static func _mark_note(note: Dictionary, occupied_by_time: Dictionary, note_times_by_lane: Dictionary, hold_intervals_by_lane: Dictionary) -> void:
	var time := float(note.get("time", 0.0))
	var lane := int(note.get("lane", 0))
	var key := _time_key(time)
	var occupied: Dictionary = occupied_by_time.get(key, {})
	occupied[lane] = true
	occupied_by_time[key] = occupied
	var times: Array = note_times_by_lane.get(lane, [])
	times.append(time)
	note_times_by_lane[lane] = times
	var length := _duration_for_note(note)
	if length > 0.0:
		var intervals: Array = hold_intervals_by_lane.get(lane, [])
		intervals.append({"start": time, "end": time + length})
		hold_intervals_by_lane[lane] = intervals


static func _empty_lane_arrays(lane_count: int) -> Dictionary:
	var result: Dictionary = {}
	for lane in range(lane_count):
		result[lane] = []
	return result


static func _read_frame_sample(pcm: PackedByteArray, base: int, bytes_per_sample: int, channels: int) -> float:
	var sum := 0.0
	if bytes_per_sample == 1:
		for c in range(channels):
			var v := int(pcm[base + c])
			if v > 127:
				v -= 256
			sum += float(v) / 128.0
		return sum / float(channels)
	for c in range(channels):
		var o := base + (c * 2)
		var lo := int(pcm[o])
		var hi := int(pcm[o + 1])
		var v16 := (hi << 8) | lo
		if v16 >= 32768:
			v16 -= 65536
		sum += float(v16) / 32768.0
	return sum / float(channels)


static func _smooth_values(frames: Array[Dictionary], key: String, radius: int) -> Array[float]:
	var result: Array[float] = []
	result.resize(frames.size())
	for i in range(frames.size()):
		var a := maxi(0, i - radius)
		var b := mini(frames.size() - 1, i + radius)
		var sum := 0.0
		var count := 0
		for j in range(a, b + 1):
			sum += float(frames[j].get(key, 0.0))
			count += 1
		result[i] = sum / float(maxi(1, count))
	return result


static func _onset_threshold(frames: Array[Dictionary], difficulty: String) -> float:
	var values: Array[float] = []
	for frame in frames:
		values.append(float(frame.get("onset", 0.0)))
	var base := _percentile(values, 0.76)
	if difficulty == "professional":
		return maxf(0.10, base * 0.64)
	if difficulty == "expert":
		return maxf(0.12, base * 0.75)
	if difficulty == "hard":
		return maxf(0.15, base * 0.88)
	return maxf(0.18, base)


static func _percentile(values: Array[float], percentile: float) -> float:
	if values.is_empty():
		return 0.0
	var copy := values.duplicate()
	copy.sort()
	var idx := clampi(int(roundf(float(copy.size() - 1) * percentile)), 0, copy.size() - 1)
	return float(copy[idx])


static func _feature_at_time(frames: Array[Dictionary], time: float, key: String) -> float:
	if frames.is_empty():
		return 0.0
	var idx := clampi(int(roundf(time * FEATURE_RATE)), 0, frames.size() - 1)
	return float(frames[idx].get(key, 0.0))


static func _feature_near_time(frames: Array[Dictionary], time: float, key: String, window: float) -> float:
	if frames.is_empty():
		return 0.0
	var center := int(roundf(time * FEATURE_RATE))
	var radius := maxi(1, int(roundf(window * FEATURE_RATE)))
	var best := 0.0
	for i in range(maxi(0, center - radius), mini(frames.size() - 1, center + radius) + 1):
		best = maxf(best, float(frames[i].get(key, 0.0)))
	return best


static func _beat_accent_score(time: float, offset: float, beat_sec: float) -> float:
	var beat_pos := fmod(maxf(0.0, time - offset), beat_sec)
	var dist_to_beat := minf(beat_pos, beat_sec - beat_pos)
	var dist_to_half := absf(beat_pos - beat_sec * 0.5)
	if dist_to_beat <= 0.012:
		var beat_index := int(roundf((time - offset) / beat_sec))
		return 0.95 if beat_index % 4 == 0 else 0.72
	if dist_to_half <= 0.014:
		return 0.44
	return 0.0


static func _snap_to_grid(time: float, offset: float, step_sec: float) -> float:
	if step_sec <= 0.0:
		return maxf(0.0, time)
	return maxf(0.0, roundf((time - offset) / step_sec) * step_sec + offset)


static func _snap_duration(duration: float, step_sec: float) -> float:
	if step_sec <= 0.0:
		return duration
	return maxf(MIN_HOLD_LENGTH, roundf(duration / step_sec) * step_sec)


static func _time_key(time: float) -> int:
	return int(roundf(time * TIME_KEY_SCALE))


static func _duration_for_note(note: Dictionary) -> float:
	if note.has("length"):
		return maxf(0.0, float(note.get("length", 0.0)))
	if note.has("duration"):
		return maxf(0.0, float(note.get("duration", 0.0)))
	return 0.0


static func _nearest_time_distance(time: float, times: Array[float]) -> float:
	if times.is_empty():
		return INF
	var best := INF
	for value in times:
		best = minf(best, absf(time - value))
	return best


static func _lane_has_hold_at(hold_intervals_by_lane: Dictionary, lane: int, time: float) -> bool:
	var intervals: Array = hold_intervals_by_lane.get(lane, [])
	for interval_variant in intervals:
		var interval: Dictionary = interval_variant
		if time > float(interval.get("start", 0.0)) + 0.001 and time < float(interval.get("end", 0.0)) - 0.001:
			return true
	return false


static func _lane_hold_overlaps(hold_intervals_by_lane: Dictionary, lane: int, start_time: float, end_time: float) -> bool:
	var intervals: Array = hold_intervals_by_lane.get(lane, [])
	for interval_variant in intervals:
		var interval: Dictionary = interval_variant
		if start_time < float(interval.get("end", 0.0)) - 0.001 and end_time > float(interval.get("start", 0.0)) + 0.001:
			return true
	return false


static func _lane_note_exists_during(note_times_by_lane: Dictionary, lane: int, start_time: float, end_time: float) -> bool:
	var times: Array = note_times_by_lane.get(lane, [])
	for time_variant in times:
		var time := float(time_variant)
		if time > start_time + 0.001 and time < end_time - 0.001:
			return true
	return false


static func _recent_same_lane_note(note_times_by_lane: Dictionary, lane: int, time: float, window: float) -> bool:
	var times: Array = note_times_by_lane.get(lane, [])
	for time_variant in times:
		if absf(float(time_variant) - time) < window:
			return true
	return false


static func _sort_and_assign_ids(notes: Array[Dictionary]) -> void:
	notes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ta := float(a.get("time", 0.0))
		var tb := float(b.get("time", 0.0))
		if is_equal_approx(ta, tb):
			return int(a.get("lane", 0)) < int(b.get("lane", 0))
		return ta < tb
	)
	for i in range(notes.size()):
		notes[i]["id"] = i


static func _difficulty_rank(difficulty: String) -> int:
	match difficulty:
		"easy":
			return 0
		"medium":
			return 1
		"hard":
			return 2
		"expert":
			return 3
		"professional":
			return 4
	return 3


static func _shuffle(values: Array[int], rng: RandomNumberGenerator) -> void:
	for i in range(values.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := values[i]
		values[i] = values[j]
		values[j] = tmp


static func _stable_seed(text: String) -> int:
	var value := 0
	for i in range(text.length()):
		value = int((value * 131 + text.unicode_at(i)) % 2147483647)
	return maxi(1, value)


static func _first_validation_error(validation: Dictionary) -> String:
	var errors: Array = validation.get("errors", []) as Array
	if errors.is_empty():
		return "unknown validation error"
	var first: Dictionary = errors[0] as Dictionary
	return str(first.get("message", "invalid chart"))
