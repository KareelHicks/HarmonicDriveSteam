extends RefCounted
class_name StemsRandomLaneRandomizer

const LaneCountResolver := preload("res://scripts/songs/LaneCountResolver.gd")

const GENERATOR_VERSION := "stems_random_lane_seed_v1"
const TIME_KEY_SCALE := 1000.0


static func randomize_chart(base_chart: Dictionary, song_entry: Dictionary, difficulty: String, base_chart_hash: String, seed: int = 0) -> Dictionary:
	var chart: Dictionary = base_chart.duplicate(true)
	var lane_count := LaneCountResolver.resolve_chart_lane_count(chart, song_entry)
	var seed_value := seed if seed > 0 else _new_seed(song_entry, difficulty, lane_count, base_chart_hash)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var notes := _normalized_notes(chart.get("notes", []), lane_count)
	var randomized_notes := _randomized_lanes(notes, lane_count, rng)
	_sort_and_assign_ids(randomized_notes)
	chart["notes"] = randomized_notes
	chart["lane_count"] = lane_count
	chart["stems_random_lane_seed"] = {
		"generator_version": GENERATOR_VERSION,
		"base_chart_hash": base_chart_hash,
		"seed": seed_value,
	}

	return {
		"chart": chart,
		"runtime_chart_hash": _runtime_chart_hash(chart, song_entry, difficulty, base_chart_hash, seed_value),
		"seed": seed_value,
		"generator_version": GENERATOR_VERSION,
	}


static func _new_seed(song_entry: Dictionary, difficulty: String, lane_count: int, base_chart_hash: String) -> int:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var source := "%s|%s|%s|%d|%s|%d|%d" % [
		GENERATOR_VERSION,
		str(song_entry.get("id", song_entry.get("display_name", ""))),
		difficulty,
		lane_count,
		base_chart_hash,
		Time.get_ticks_usec(),
		int(rng.randi()),
	]
	return _stable_seed(source)


static func _stable_seed(text: String) -> int:
	var value := 0
	for i in range(text.length()):
		value = int((value * 131 + text.unicode_at(i)) % 2147483647)
	return maxi(1, value)


static func _normalized_notes(raw_notes: Variant, lane_count: int) -> Array:
	var notes: Array = []
	if raw_notes is not Array:
		return notes
	for note_variant in raw_notes:
		if note_variant is not Dictionary:
			continue
		var note: Dictionary = (note_variant as Dictionary).duplicate(true)
		note["lane"] = clampi(int(roundf(float(note.get("lane", 0)))), 0, lane_count - 1)
		if _duration_for_note(note) > 0.0:
			note["type"] = "hold"
			note["duration"] = _duration_for_note(note)
			note["length"] = _duration_for_note(note)
		elif not note.has("type"):
			note["type"] = "tap"
		notes.append(note)
	_sort_and_assign_ids(notes)
	return notes


static func _randomized_lanes(notes: Array, lane_count: int, rng: RandomNumberGenerator) -> Array:
	var randomized := notes.duplicate(true)
	var grouped := _groups_by_time(randomized)
	var hold_end_by_lane: Array = []
	hold_end_by_lane.resize(lane_count)
	for lane in range(lane_count):
		hold_end_by_lane[lane] = 0.0

	for group in grouped:
		var group_time := float(group.get("time", 0.0))
		var group_notes: Array = group.get("notes", [])
		var unavailable := {}
		for lane in range(lane_count):
			if float(hold_end_by_lane[lane]) > group_time + 0.001:
				unavailable[lane] = true

		var preferred_lanes := _available_lanes(lane_count, unavailable)
		_shuffle_array(preferred_lanes, rng)
		var fallback_lanes := _all_lanes(lane_count)
		_shuffle_array(fallback_lanes, rng)
		var used_in_group := {}

		for note_variant in group_notes:
			if note_variant is not Dictionary:
				continue
			var note: Dictionary = note_variant
			var lane := _take_lane(preferred_lanes, used_in_group)
			if lane < 0:
				lane = _take_lane(fallback_lanes, used_in_group)
			if lane < 0:
				lane = rng.randi_range(0, lane_count - 1)
			note["lane"] = lane
			used_in_group[lane] = true
			var duration := _duration_for_note(note)
			if duration > 0.0:
				hold_end_by_lane[lane] = maxf(float(hold_end_by_lane[lane]), group_time + duration)

	return randomized


static func _groups_by_time(notes: Array) -> Array:
	var groups_by_key := {}
	for note_variant in notes:
		if note_variant is not Dictionary:
			continue
		var note: Dictionary = note_variant
		var time := float(note.get("time", 0.0))
		var key := _time_key(time)
		var group: Dictionary = groups_by_key.get(key, {"time": time, "notes": []})
		var group_notes: Array = group.get("notes", [])
		group_notes.append(note)
		group["time"] = minf(float(group.get("time", time)), time)
		group["notes"] = group_notes
		groups_by_key[key] = group

	var groups: Array = []
	for key in groups_by_key.keys():
		var group: Dictionary = groups_by_key[key]
		var group_notes: Array = group.get("notes", [])
		group_notes.sort_custom(func(a: Variant, b: Variant) -> bool:
			var da: Dictionary = a as Dictionary if a is Dictionary else {}
			var db: Dictionary = b as Dictionary if b is Dictionary else {}
			var ad := _duration_for_note(da)
			var bd := _duration_for_note(db)
			if not is_equal_approx(ad, bd):
				return ad > bd
			return int(da.get("id", 0)) < int(db.get("id", 0))
		)
		group["notes"] = group_notes
		groups.append(group)
	groups.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("time", 0.0)) < float(b.get("time", 0.0))
	)
	return groups


static func _available_lanes(lane_count: int, unavailable: Dictionary) -> Array:
	var lanes: Array = []
	for lane in range(lane_count):
		if not unavailable.has(lane):
			lanes.append(lane)
	return lanes


static func _all_lanes(lane_count: int) -> Array:
	var lanes: Array = []
	for lane in range(lane_count):
		lanes.append(lane)
	return lanes


static func _take_lane(lanes: Array, used_in_group: Dictionary) -> int:
	while not lanes.is_empty():
		var lane := int(lanes.pop_back())
		if not used_in_group.has(lane):
			return lane
	return -1


static func _shuffle_array(values: Array, rng: RandomNumberGenerator) -> void:
	for i in range(values.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = values[i]
		values[i] = values[j]
		values[j] = tmp


static func _sort_and_assign_ids(notes: Array) -> void:
	notes.sort_custom(func(a: Variant, b: Variant) -> bool:
		var da: Dictionary = a as Dictionary if a is Dictionary else {}
		var db: Dictionary = b as Dictionary if b is Dictionary else {}
		var ta := float(da.get("time", 0.0))
		var tb := float(db.get("time", 0.0))
		if is_equal_approx(ta, tb):
			var la := int(da.get("lane", 0))
			var lb := int(db.get("lane", 0))
			if la == lb:
				return int(da.get("id", 0)) < int(db.get("id", 0))
			return la < lb
		return ta < tb
	)
	for i in range(notes.size()):
		if notes[i] is Dictionary:
			var note: Dictionary = notes[i]
			note["id"] = i
			notes[i] = note


static func _runtime_chart_hash(chart: Dictionary, song_entry: Dictionary, difficulty: String, base_chart_hash: String, seed: int) -> String:
	var parts: Array[String] = [
		GENERATOR_VERSION,
		str(song_entry.get("id", "")),
		difficulty,
		base_chart_hash,
		str(seed),
		str(chart.get("lane_count", LaneCountResolver.DEFAULT_LANES)),
	]
	var notes: Array = chart.get("notes", []) as Array
	for note_variant in notes:
		if note_variant is not Dictionary:
			continue
		var note: Dictionary = note_variant
		parts.append("%d,%.3f,%d,%s,%.3f" % [
			int(note.get("id", -1)),
			float(note.get("time", 0.0)),
			int(note.get("lane", 0)),
			str(note.get("type", "tap")),
			_duration_for_note(note),
		])
	return _sha256_text("\n".join(parts))


static func _sha256_text(text: String) -> String:
	var hash_context := HashingContext.new()
	if hash_context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	hash_context.update(text.to_utf8_buffer())
	return hash_context.finish().hex_encode()


static func _duration_for_note(note: Dictionary) -> float:
	if note.has("duration"):
		return roundf(maxf(0.0, float(note.get("duration", 0.0))) * TIME_KEY_SCALE) / TIME_KEY_SCALE
	if note.has("length"):
		return roundf(maxf(0.0, float(note.get("length", 0.0))) * TIME_KEY_SCALE) / TIME_KEY_SCALE
	return 0.0


static func _time_key(time: float) -> int:
	return int(round(time * TIME_KEY_SCALE))
