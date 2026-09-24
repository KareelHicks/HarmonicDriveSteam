extends SceneTree

const AutoChartGenerator := preload("res://scripts/editor/AutoChartGenerator.gd")
const ChartValidator := preload("res://scripts/songs/ChartValidator.gd")

const SAMPLE_RATE := 44100
const DURATION_SEC := 32.0
const BPM := 138.0
const LANE_COUNT := 5


func _initialize() -> void:
	var wav := _build_synthetic_trance_wav()
	var result_a := AutoChartGenerator.generate_from_wav(wav, "professional", LANE_COUNT, 0.0, 0.0, "synthetic_trance")
	var result_b := AutoChartGenerator.generate_from_wav(wav, "professional", LANE_COUNT, 0.0, 0.0, "synthetic_trance")
	if not _assert(bool(result_a.get("ok", false)), "Auto chart failed: %s" % str(result_a.get("error", ""))):
		return
	if not _assert(bool(result_b.get("ok", false)), "Second auto chart failed"):
		return

	var notes_a: Array = result_a.get("notes", []) as Array
	var notes_b: Array = result_b.get("notes", []) as Array
	var detected_bpm := float(result_a.get("bpm", 0.0))
	var nps := float(result_a.get("nps", 0.0))
	var validation := ChartValidator.validate_chart({
		"version": 1,
		"difficulty": "professional",
		"lane_count": LANE_COUNT,
		"notes": notes_a,
	}, "professional")

	if not _assert(ChartValidator.is_valid(validation), "Generated chart failed validation: %s" % _first_validation_error(validation)):
		return
	if not _assert(notes_a.size() > 0, "Generated notes are empty"):
		return
	if not _assert(_note_signature(notes_a) == _note_signature(notes_b), "Auto chart output is not deterministic"):
		return
	if not _assert(absf(detected_bpm - BPM) <= 2.0, "Detected BPM %.3f is not close to %.3f" % [detected_bpm, BPM]):
		return
	if not _assert(int(result_a.get("tap_count", 0)) > 0, "No taps were generated"):
		return
	if not _assert(int(result_a.get("hold_count", 0)) > 0, "No holds were generated"):
		return
	if not _assert(_ids_are_sequential(notes_a), "Note ids are not sequential"):
		return
	if not _assert(_notes_are_sorted(notes_a), "Notes are not sorted"):
		return
	if not _assert(_lanes_are_valid(notes_a), "A note lane is out of range"):
		return
	if not _assert(_max_notes_per_time(notes_a) <= 3, "A chord group exceeds three notes"):
		return
	if not _assert(not _has_hold_collision(notes_a), "A note starts inside a same-lane hold"):
		return
	if not _assert(nps >= 4.2 and nps <= 8.4, "Professional NPS %.2f is outside expected range" % nps):
		return

	print("AutoChartGenerator smoke test passed: notes=%d taps=%d holds=%d bpm=%.3f nps=%.2f confidence=%.2f" % [
		notes_a.size(),
		int(result_a.get("tap_count", 0)),
		int(result_a.get("hold_count", 0)),
		detected_bpm,
		nps,
		float(result_a.get("confidence", 0.0)),
	])
	quit(0)


func _build_synthetic_trance_wav() -> AudioStreamWAV:
	var beat_sec := 60.0 / BPM
	var total_frames := int(DURATION_SEC * float(SAMPLE_RATE))
	var bytes := PackedByteArray()
	bytes.resize(total_frames * 2)
	for i in range(total_frames):
		var t := float(i) / float(SAMPLE_RATE)
		var beat_pos := fmod(t, beat_sec)
		var half_pos := absf(beat_pos - beat_sec * 0.5)
		var sample := 0.0

		# Sustained trance pad.
		var pad_gate := 0.55 + 0.20 * sin(TAU * 0.125 * t)
		sample += sin(TAU * 220.0 * t) * 0.12 * pad_gate
		sample += sin(TAU * 440.0 * t) * 0.06 * pad_gate

		# Four-on-the-floor kick transient.
		if beat_pos < 0.085:
			var decay := exp(-beat_pos * 42.0)
			sample += sin(TAU * (54.0 + 28.0 * decay) * t) * 0.78 * decay

		# Offbeat clap/high transient.
		if half_pos < 0.030:
			var d := exp(-half_pos * 80.0)
			sample += sin(TAU * 2200.0 * t) * 0.22 * d
			sample += sin(TAU * 3700.0 * t) * 0.15 * d

		# Vocal-chop-like gated high melody during phrases.
		var beat_index := int(floor(t / beat_sec))
		if beat_index >= 16 and beat_index <= 56:
			var sixteenth := fmod(t, beat_sec * 0.25)
			if sixteenth < 0.040:
				var chop_decay := exp(-sixteenth * 52.0)
				sample += sin(TAU * 660.0 * t) * 0.24 * chop_decay
				sample += sin(TAU * 1320.0 * t) * 0.10 * chop_decay

		sample = clampf(sample, -0.95, 0.95)
		var int_sample := int(roundf(sample * 32767.0))
		if int_sample < 0:
			int_sample += 65536
		var byte_idx := i * 2
		bytes[byte_idx] = int_sample & 0xff
		bytes[byte_idx + 1] = (int_sample >> 8) & 0xff

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = bytes
	return wav


func _assert(condition: bool, message: String) -> bool:
	if not condition:
		_fail(message)
		return false
	return true


func _fail(message: String) -> void:
	push_error(message)
	quit(1)


func _note_signature(notes: Array) -> String:
	var parts: Array[String] = []
	for note_variant in notes:
		if note_variant is not Dictionary:
			continue
		var note: Dictionary = note_variant
		parts.append("%.3f|%d|%s|%.3f" % [
			float(note.get("time", 0.0)),
			int(note.get("lane", 0)),
			str(note.get("type", "tap")),
			_duration_for_note(note),
		])
	return "\n".join(parts)


func _ids_are_sequential(notes: Array) -> bool:
	for i in range(notes.size()):
		if notes[i] is not Dictionary:
			return false
		if int((notes[i] as Dictionary).get("id", -1)) != i:
			return false
	return true


func _notes_are_sorted(notes: Array) -> bool:
	var last_time := -INF
	var last_lane := -1
	for note_variant in notes:
		if note_variant is not Dictionary:
			return false
		var note: Dictionary = note_variant
		var time := float(note.get("time", 0.0))
		var lane := int(note.get("lane", 0))
		if time < last_time:
			return false
		if is_equal_approx(time, last_time) and lane < last_lane:
			return false
		last_time = time
		last_lane = lane
	return true


func _lanes_are_valid(notes: Array) -> bool:
	for note_variant in notes:
		if note_variant is not Dictionary:
			return false
		var lane := int((note_variant as Dictionary).get("lane", -1))
		if lane < 0 or lane >= LANE_COUNT:
			return false
	return true


func _max_notes_per_time(notes: Array) -> int:
	var counts := {}
	var max_count := 0
	for note_variant in notes:
		if note_variant is not Dictionary:
			continue
		var key := int(roundf(float((note_variant as Dictionary).get("time", 0.0)) * 1000.0))
		counts[key] = int(counts.get(key, 0)) + 1
		max_count = maxi(max_count, int(counts[key]))
	return max_count


func _has_hold_collision(notes: Array) -> bool:
	var intervals_by_lane := {}
	for note_variant in notes:
		if note_variant is not Dictionary:
			continue
		var note: Dictionary = note_variant
		var duration := _duration_for_note(note)
		if duration <= 0.0:
			continue
		var lane := int(note.get("lane", 0))
		var intervals: Array = intervals_by_lane.get(lane, [])
		intervals.append({
			"id": int(note.get("id", -1)),
			"start": float(note.get("time", 0.0)),
			"end": float(note.get("time", 0.0)) + duration,
		})
		intervals_by_lane[lane] = intervals
	for note_variant in notes:
		if note_variant is not Dictionary:
			continue
		var note: Dictionary = note_variant
		var lane := int(note.get("lane", 0))
		var time := float(note.get("time", 0.0))
		var note_id := int(note.get("id", -1))
		var intervals: Array = intervals_by_lane.get(lane, [])
		for interval_variant in intervals:
			var interval: Dictionary = interval_variant
			if int(interval.get("id", -2)) == note_id:
				continue
			if time > float(interval.get("start", 0.0)) + 0.001 and time < float(interval.get("end", 0.0)) - 0.001:
				return true
	return false


func _duration_for_note(note: Dictionary) -> float:
	if note.has("length"):
		return roundf(maxf(0.0, float(note.get("length", 0.0))) * 1000.0) / 1000.0
	if note.has("duration"):
		return roundf(maxf(0.0, float(note.get("duration", 0.0))) * 1000.0) / 1000.0
	return 0.0


func _first_validation_error(validation: Dictionary) -> String:
	var errors: Array = validation.get("errors", []) as Array
	if errors.is_empty():
		return "unknown validation error"
	var first: Dictionary = errors[0] as Dictionary
	return str(first.get("message", "invalid chart"))
