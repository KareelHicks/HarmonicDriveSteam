extends SceneTree

const ChartLoader := preload("res://scripts/gameplay/ChartLoader.gd")
const LaneCountResolver := preload("res://scripts/songs/LaneCountResolver.gd")
const SynthesizedRemixGenerator := preload("res://scripts/gameplay/SynthesizedRemixGenerator.gd")

const CHART_PATH := "res://content/charts/synthesized/afterglow_drive_medium.json"


func _initialize() -> void:
	var base_chart := ChartLoader.load_chart(CHART_PATH)
	if base_chart.is_empty():
		_fail("Failed to load chart: %s" % CHART_PATH)
		return

	var song_entry := {
		"id": "afterglow_drive",
		"display_name": "Afterglow Drive",
		"bpm": float(base_chart.get("bpm", 142.41)),
	}
	var base_hash := _file_sha256(CHART_PATH)
	var result_a := SynthesizedRemixGenerator.generate(base_chart.duplicate(true), song_entry, "Medium", base_hash)
	var result_b := SynthesizedRemixGenerator.generate(base_chart.duplicate(true), song_entry, "Medium", base_hash)
	var professional_result := SynthesizedRemixGenerator.generate(base_chart.duplicate(true), song_entry, "Professional", base_hash)
	var tap_forward_results := {
		"Easy": SynthesizedRemixGenerator.generate(base_chart.duplicate(true), song_entry, "Easy", base_hash),
		"Medium": result_a,
		"Hard": SynthesizedRemixGenerator.generate(base_chart.duplicate(true), song_entry, "Hard", base_hash),
		"Expert": SynthesizedRemixGenerator.generate(base_chart.duplicate(true), song_entry, "Expert", base_hash),
	}
	var chart_a: Dictionary = result_a.get("chart", {}) as Dictionary
	var chart_b: Dictionary = result_b.get("chart", {}) as Dictionary
	var professional_chart: Dictionary = professional_result.get("chart", {}) as Dictionary
	var notes_a: Array = chart_a.get("notes", []) as Array
	var notes_b: Array = chart_b.get("notes", []) as Array
	var professional_notes: Array = professional_chart.get("notes", []) as Array
	var original_notes: Array = base_chart.get("notes", []) as Array

	if not _assert(not notes_a.is_empty(), "Remix notes are empty"):
		return
	if not _assert(int(result_a.get("generated_note_count", 0)) > 0, "No generated notes were created"):
		return
	if not _assert(str(result_a.get("runtime_chart_hash", "")) == str(result_b.get("runtime_chart_hash", "")), "Runtime chart hash is not deterministic"):
		return
	if not _assert(_notes_signature(notes_a) == _notes_signature(notes_b), "Generated notes are not deterministic"):
		return
	if not _assert(notes_a.size() > original_notes.size(), "Remix did not add notes"):
		return
	if not _assert(
		int(result_a.get("generated_note_count", 0)) <= int(ceil(float(original_notes.size()) * 0.26)),
		"Medium Remix generated too many notes for the tap-forward v5 tuning"
	):
		return
	if not _assert(_preserves_original_notes(original_notes, notes_a), "Remix does not preserve every original note"):
		return
	if not _assert(_has_generated_hold(notes_a), "Remix did not generate any holds"):
		return
	if not _assert(_has_generated_chord(notes_a), "Remix did not generate any chord groups"):
		return
	for tuning_difficulty_variant in tap_forward_results.keys():
		var tuning_difficulty := str(tuning_difficulty_variant)
		var tuning_result: Dictionary = tap_forward_results[tuning_difficulty] as Dictionary
		var tuning_chart: Dictionary = tuning_result.get("chart", {}) as Dictionary
		var tuning_notes: Array = tuning_chart.get("notes", []) as Array
		var tuning_generated_count := int(tuning_result.get("generated_note_count", 0))
		var generated_chord_group_count := _generated_chord_group_count(tuning_notes)
		var generated_chord_group_limit := int(ceil(float(tuning_generated_count) * 0.16))
		if not _assert(
			generated_chord_group_count <= generated_chord_group_limit,
			"%s Remix generated %d chord groups; tap-forward v5 allows at most %d" % [
				tuning_difficulty,
				generated_chord_group_count,
				generated_chord_group_limit,
			]
		):
			return
		if not _assert(not _adds_to_authored_chord(tuning_notes), "%s Remix added notes to an authored chord group" % tuning_difficulty):
			return
		if not _assert(_max_generated_notes_at_authored_time(tuning_notes) <= 1, "%s Remix stacked multiple generated notes onto an authored tap" % tuning_difficulty):
			return
	if not _assert(_ids_are_sequential(notes_a), "Remix note ids are not sequential"):
		return
	if not _assert(_notes_are_sorted(notes_a), "Remix notes are not sorted"):
		return
	if not _assert(_lanes_are_valid(notes_a, LaneCountResolver.resolve_chart_lane_count(chart_a, song_entry)), "Remix note lane out of range"):
		return
	if not _assert(_max_notes_per_time(notes_a) <= 3, "Remix generated a quadruple-or-larger note group"):
		return
	if not _assert(not _has_generated_hold_intersection(notes_a), "Generated hold intersects another note on the same lane"):
		return
	if not _assert(int(professional_result.get("generated_note_count", 0)) > 0, "Professional Remix did not generate notes"):
		return
	if not _assert(
		int(professional_result.get("generated_note_count", 0)) <= int(ceil(float(original_notes.size()) * 0.63)),
		"Professional Remix generated too many notes for the tap-forward v5 tuning"
	):
		return
	if not _assert(not _has_generated_chord(professional_notes), "Professional Remix generated a chord group"):
		return
	if not _assert(_generated_times_are_single_total_groups(professional_notes), "Professional Remix added to an existing note group"):
		return
	if not _assert(_generated_notes_are_taps_or_holds(professional_notes), "Professional Remix generated an unsupported note type"):
		return
	if not _assert(not _has_generated_hold_intersection(professional_notes), "Professional generated hold intersects another same-lane note"):
		return
	if not _assert(_hold_trimming_behaves_as_expected(), "Professional hold trimming did not shorten/remove colliding sustains"):
		return

	print("SynthesizedRemixGenerator smoke test passed: original=%d generated=%d generated_chord_groups=%d total=%d hash=%s" % [
		original_notes.size(),
		int(result_a.get("generated_note_count", 0)),
		_generated_chord_group_count(notes_a),
		notes_a.size(),
		str(result_a.get("runtime_chart_hash", "")),
	])
	quit(0)


func _assert(condition: bool, message: String) -> bool:
	if not condition:
		_fail(message)
		return false
	return true


func _fail(message: String) -> void:
	push_error(message)
	quit(1)


func _preserves_original_notes(original_notes: Array, remix_notes: Array) -> bool:
	var remaining := {}
	for note_variant in remix_notes:
		if note_variant is not Dictionary:
			continue
		var key := _note_signature(note_variant as Dictionary)
		remaining[key] = int(remaining.get(key, 0)) + 1
	for note_variant in original_notes:
		if note_variant is not Dictionary:
			continue
		var key := _note_signature(note_variant as Dictionary)
		var count := int(remaining.get(key, 0))
		if count <= 0:
			return false
		remaining[key] = count - 1
	return true


func _has_generated_hold(notes: Array) -> bool:
	for note_variant in notes:
		if note_variant is not Dictionary:
			continue
		var note: Dictionary = note_variant
		if bool(note.get("_generated", false)) and _duration_for_note(note) > 0.0:
			return true
	return false


func _has_generated_chord(notes: Array) -> bool:
	var generated_by_time := {}
	for note_variant in notes:
		if note_variant is not Dictionary:
			continue
		var note: Dictionary = note_variant
		if not bool(note.get("_generated", false)):
			continue
		var key := _time_key(float(note.get("time", 0.0)))
		generated_by_time[key] = int(generated_by_time.get(key, 0)) + 1
	for key in generated_by_time.keys():
		if int(generated_by_time[key]) >= 2:
			return true
	return false


func _generated_chord_group_count(notes: Array) -> int:
	var groups := _note_group_counts(notes)
	var count := 0
	for group_variant in groups.values():
		var group: Dictionary = group_variant
		if int(group.get("generated", 0)) > 0 and int(group.get("total", 0)) > 1:
			count += 1
	return count


func _adds_to_authored_chord(notes: Array) -> bool:
	var groups := _note_group_counts(notes)
	for group_variant in groups.values():
		var group: Dictionary = group_variant
		if int(group.get("generated", 0)) > 0 and int(group.get("authored", 0)) >= 2:
			return true
	return false


func _max_generated_notes_at_authored_time(notes: Array) -> int:
	var groups := _note_group_counts(notes)
	var max_count := 0
	for group_variant in groups.values():
		var group: Dictionary = group_variant
		if int(group.get("authored", 0)) > 0:
			max_count = maxi(max_count, int(group.get("generated", 0)))
	return max_count


func _note_group_counts(notes: Array) -> Dictionary:
	var groups := {}
	for note_variant in notes:
		if note_variant is not Dictionary:
			continue
		var note: Dictionary = note_variant
		var key := _time_key(float(note.get("time", 0.0)))
		var group: Dictionary = groups.get(key, {"total": 0, "generated": 0, "authored": 0})
		group["total"] = int(group.get("total", 0)) + 1
		if bool(note.get("_generated", false)):
			group["generated"] = int(group.get("generated", 0)) + 1
		else:
			group["authored"] = int(group.get("authored", 0)) + 1
		groups[key] = group
	return groups


func _generated_times_are_single_total_groups(notes: Array) -> bool:
	var total_by_time := {}
	var generated_times := {}
	for note_variant in notes:
		if note_variant is not Dictionary:
			continue
		var note: Dictionary = note_variant
		var key := _time_key(float(note.get("time", 0.0)))
		total_by_time[key] = int(total_by_time.get(key, 0)) + 1
		if bool(note.get("_generated", false)):
			generated_times[key] = true
	for key in generated_times.keys():
		if int(total_by_time.get(key, 0)) > 1:
			return false
	return true


func _generated_notes_are_taps_or_holds(notes: Array) -> bool:
	for note_variant in notes:
		if note_variant is not Dictionary:
			continue
		var note: Dictionary = note_variant
		if not bool(note.get("_generated", false)):
			continue
		var note_type := str(note.get("type", "tap"))
		if note_type != "tap" and note_type != "hold":
			return false
	return true


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


func _lanes_are_valid(notes: Array, lane_count: int) -> bool:
	for note_variant in notes:
		if note_variant is not Dictionary:
			return false
		var lane := int((note_variant as Dictionary).get("lane", -1))
		if lane < 0 or lane >= lane_count:
			return false
	return true


func _max_notes_per_time(notes: Array) -> int:
	var counts := {}
	var max_count := 0
	for note_variant in notes:
		if note_variant is not Dictionary:
			continue
		var key := _time_key(float((note_variant as Dictionary).get("time", 0.0)))
		var count := int(counts.get(key, 0)) + 1
		counts[key] = count
		max_count = maxi(max_count, count)
	return max_count


func _has_generated_hold_intersection(notes: Array) -> bool:
	for i in range(notes.size()):
		if notes[i] is not Dictionary:
			continue
		var a: Dictionary = notes[i]
		if not bool(a.get("_generated", false)) or _duration_for_note(a) <= 0.0:
			continue
		var a_lane := int(a.get("lane", 0))
		var a_start := float(a.get("time", 0.0))
		var a_end := a_start + _duration_for_note(a)
		for j in range(notes.size()):
			if i == j or notes[j] is not Dictionary:
				continue
			var b: Dictionary = notes[j]
			if int(b.get("lane", 0)) != a_lane:
				continue
			var b_start := float(b.get("time", 0.0))
			var b_duration := _duration_for_note(b)
			if b_duration > 0.0:
				var b_end := b_start + b_duration
				if a_start < b_end - 0.001 and a_end > b_start + 0.001:
					return true
			elif b_start > a_start + 0.001 and b_start < a_end - 0.001:
				return true
	return false


func _hold_trimming_behaves_as_expected() -> bool:
	var shortened := SynthesizedRemixGenerator._trim_hold_length_for_lane(
		1.000,
		0,
		1.000,
		{0: []},
		{0: [1.500]}
	)
	if not is_equal_approx(shortened, 0.465):
		return false

	var removed := SynthesizedRemixGenerator._trim_hold_length_for_lane(
		1.000,
		0,
		1.000,
		{0: []},
		{0: [1.100]}
	)
	return is_equal_approx(removed, 0.0)


func _notes_signature(notes: Array) -> String:
	var parts: Array[String] = []
	for note_variant in notes:
		if note_variant is Dictionary:
			parts.append(_note_signature(note_variant as Dictionary))
	return "\n".join(parts)


func _note_signature(note: Dictionary) -> String:
	return "%.3f|%d|%s|%.3f|%s" % [
		float(note.get("time", 0.0)),
		int(note.get("lane", 0)),
		str(note.get("type", "tap")),
		_duration_for_note(note),
		"g" if bool(note.get("_generated", false)) else "a",
	]


func _duration_for_note(note: Dictionary) -> float:
	if note.has("duration"):
		return roundf(maxf(0.0, float(note.get("duration", 0.0))) * 1000.0) / 1000.0
	if note.has("length"):
		return roundf(maxf(0.0, float(note.get("length", 0.0))) * 1000.0) / 1000.0
	return 0.0


func _time_key(time: float) -> int:
	return int(round(time * 1000.0))


func _file_sha256(path: String) -> String:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return ""
	var hash_context := HashingContext.new()
	if hash_context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	hash_context.update(bytes)
	return hash_context.finish().hex_encode()
