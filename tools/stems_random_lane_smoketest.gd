extends SceneTree

const ChartLoader := preload("res://scripts/gameplay/ChartLoader.gd")
const LaneCountResolver := preload("res://scripts/songs/LaneCountResolver.gd")
const StemsRandomLaneRandomizer := preload("res://scripts/gameplay/StemsRandomLaneRandomizer.gd")

const CHART_PATH := "res://content/charts/stems_random/afterglow_drive_medium.json"


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
	var result_a := StemsRandomLaneRandomizer.randomize_chart(base_chart.duplicate(true), song_entry, "Medium", base_hash, 12345)
	var result_b := StemsRandomLaneRandomizer.randomize_chart(base_chart.duplicate(true), song_entry, "Medium", base_hash, 12345)
	var result_c := StemsRandomLaneRandomizer.randomize_chart(base_chart.duplicate(true), song_entry, "Medium", base_hash, 54321)
	var notes_base: Array = (base_chart.get("notes", []) as Array)
	var notes_a: Array = ((result_a.get("chart", {}) as Dictionary).get("notes", []) as Array)
	var notes_b: Array = ((result_b.get("chart", {}) as Dictionary).get("notes", []) as Array)
	var notes_c: Array = ((result_c.get("chart", {}) as Dictionary).get("notes", []) as Array)
	var lane_count := LaneCountResolver.resolve_chart_lane_count(result_a.get("chart", {}) as Dictionary, song_entry)

	if not _assert(notes_a.size() == notes_base.size(), "Randomizer changed note count"):
		return
	if not _assert(str(result_a.get("runtime_chart_hash", "")) == str(result_b.get("runtime_chart_hash", "")), "Same seed did not produce same hash"):
		return
	if not _assert(_notes_signature(notes_a, true) == _notes_signature(notes_b, true), "Same seed did not produce same lanes"):
		return
	if not _assert(_notes_signature(notes_a, true) != _notes_signature(notes_c, true), "Different seed produced identical lanes"):
		return
	if not _assert(_timing_signature(notes_a) == _timing_signature(notes_base), "Randomizer changed note timing/type/duration"):
		return
	if not _assert(_notes_are_sorted(notes_a), "Randomized notes are not sorted"):
		return
	if not _assert(_ids_are_sequential(notes_a), "Randomized note ids are not sequential"):
		return
	if not _assert(_lanes_are_valid(notes_a, lane_count), "Randomized note lane out of range"):
		return
	if not _assert(_same_time_groups_have_unique_lanes(notes_a, lane_count), "Randomized chord group reused a lane despite enough lanes"):
		return
	if not _assert(not _has_note_start_inside_hold(notes_a), "Randomized note starts inside an active hold on the same lane"):
		return

	print("StemsRandomLaneRandomizer smoke test passed: notes=%d seed=%d hash=%s" % [
		notes_a.size(),
		int(result_a.get("seed", 0)),
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


func _notes_signature(notes: Array, include_lane: bool) -> String:
	var parts: Array[String] = []
	for note_variant in notes:
		if note_variant is not Dictionary:
			continue
		var note: Dictionary = note_variant
		if include_lane:
			parts.append("%.3f|%d|%s|%.3f" % [
				float(note.get("time", 0.0)),
				int(note.get("lane", 0)),
				str(note.get("type", "tap")),
				_duration_for_note(note),
			])
		else:
			parts.append("%.3f|%s|%.3f" % [
				float(note.get("time", 0.0)),
				str(note.get("type", "tap")),
				_duration_for_note(note),
			])
	return "\n".join(parts)


func _timing_signature(notes: Array) -> String:
	var parts: Array[String] = []
	for note_variant in notes:
		if note_variant is not Dictionary:
			continue
		var note: Dictionary = note_variant
		parts.append("%.3f|%s|%.3f" % [
			float(note.get("time", 0.0)),
			str(note.get("type", "tap")),
			_duration_for_note(note),
		])
	parts.sort()
	return "\n".join(parts)


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


func _ids_are_sequential(notes: Array) -> bool:
	for i in range(notes.size()):
		if notes[i] is not Dictionary:
			return false
		if int((notes[i] as Dictionary).get("id", -1)) != i:
			return false
	return true


func _lanes_are_valid(notes: Array, lane_count: int) -> bool:
	for note_variant in notes:
		if note_variant is not Dictionary:
			return false
		var lane := int((note_variant as Dictionary).get("lane", -1))
		if lane < 0 or lane >= lane_count:
			return false
	return true


func _same_time_groups_have_unique_lanes(notes: Array, lane_count: int) -> bool:
	var groups := {}
	for note_variant in notes:
		if note_variant is not Dictionary:
			continue
		var note: Dictionary = note_variant
		var key := int(round(float(note.get("time", 0.0)) * 1000.0))
		var lanes: Array = groups.get(key, [])
		lanes.append(int(note.get("lane", 0)))
		groups[key] = lanes
	for key in groups.keys():
		var lanes: Array = groups[key]
		if lanes.size() > lane_count:
			continue
		var seen := {}
		for lane_variant in lanes:
			var lane := int(lane_variant)
			if seen.has(lane):
				return false
			seen[lane] = true
	return true


func _has_note_start_inside_hold(notes: Array) -> bool:
	var hold_intervals_by_lane := {}
	for note_variant in notes:
		if note_variant is not Dictionary:
			continue
		var note: Dictionary = note_variant
		var duration := _duration_for_note(note)
		if duration <= 0.0:
			continue
		var lane := int(note.get("lane", 0))
		var intervals: Array = hold_intervals_by_lane.get(lane, [])
		intervals.append({
			"id": int(note.get("id", -1)),
			"start": float(note.get("time", 0.0)),
			"end": float(note.get("time", 0.0)) + duration,
		})
		hold_intervals_by_lane[lane] = intervals

	for note_variant in notes:
		if note_variant is not Dictionary:
			continue
		var note: Dictionary = note_variant
		var lane := int(note.get("lane", 0))
		var time := float(note.get("time", 0.0))
		var note_id := int(note.get("id", -1))
		var intervals: Array = hold_intervals_by_lane.get(lane, [])
		for interval_variant in intervals:
			var interval: Dictionary = interval_variant
			if int(interval.get("id", -2)) == note_id:
				continue
			if time > float(interval.get("start", 0.0)) + 0.001 and time < float(interval.get("end", 0.0)) - 0.001:
				return true
	return false


func _duration_for_note(note: Dictionary) -> float:
	if note.has("duration"):
		return roundf(maxf(0.0, float(note.get("duration", 0.0))) * 1000.0) / 1000.0
	if note.has("length"):
		return roundf(maxf(0.0, float(note.get("length", 0.0))) * 1000.0) / 1000.0
	return 0.0


func _file_sha256(path: String) -> String:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return ""
	var hash_context := HashingContext.new()
	if hash_context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	hash_context.update(bytes)
	return hash_context.finish().hex_encode()
