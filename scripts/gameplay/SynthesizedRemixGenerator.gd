extends RefCounted
class_name SynthesizedRemixGenerator

const LaneCountResolver := preload("res://scripts/songs/LaneCountResolver.gd")

const GENERATOR_VERSION := "synthesized_remix_v5"
const HOLD_GROUP_RATIO := 0.12
# Keep Remix tap-forward: chords are occasional accents, not the default generated texture.
const CHORD_GROUP_RATIO := 0.04
const ACCENT_GROUP_RATIO := 0.06
const TRIPLE_CHORD_RATIO := 0.15
const TIME_KEY_SCALE := 1000.0
const MIN_START_TIME := 0.50
const MAX_TOTAL_NOTES_PER_TIME := 3
const MIN_GENERATED_HOLD_LENGTH := 0.18
const HOLD_TRIM_PADDING := 0.035

const ADD_RATIOS := {
	"Easy": 0.12,
	"Medium": 0.25,
	"Hard": 0.36,
	"Expert": 0.50,
	"Professional": 0.62,
}

const MIN_SPACING := {
	"Easy": 0.20,
	"Medium": 0.16,
	"Hard": 0.13,
	"Expert": 0.11,
	"Professional": 0.095,
}


static func generate(base_chart: Dictionary, song_entry: Dictionary, difficulty: String, base_chart_hash: String) -> Dictionary:
	var chart: Dictionary = base_chart.duplicate(true)
	var lane_count := LaneCountResolver.resolve_chart_lane_count(chart, song_entry)
	var bpm := maxf(1.0, float(chart.get("bpm", song_entry.get("bpm", 120.0))))
	var original_notes := _normalized_notes(chart.get("notes", []), lane_count)
	var target_additions := int(roundf(float(original_notes.size()) * float(ADD_RATIOS.get(difficulty, ADD_RATIOS["Medium"]))))

	if original_notes.is_empty() or target_additions <= 0:
		_sort_and_assign_ids(original_notes)
		chart["notes"] = original_notes
		chart["lane_count"] = lane_count
		var empty_seed_source := _seed_source(song_entry, difficulty, lane_count, base_chart_hash)
		var empty_seed := _stable_seed(empty_seed_source)
		var empty_hash := _runtime_chart_hash(chart, song_entry, difficulty, base_chart_hash, empty_seed_source)
		return {
			"chart": chart,
			"runtime_chart_hash": empty_hash,
			"generated_note_count": 0,
			"generator_version": GENERATOR_VERSION,
			"seed": empty_seed,
		}

	var seed_source := _seed_source(song_entry, difficulty, lane_count, base_chart_hash)
	var seed := _stable_seed(seed_source)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed

	var source_groups := _build_source_groups(original_notes)
	var candidates := _build_candidates(original_notes, source_groups, bpm, target_additions)
	var remix_notes := original_notes.duplicate(true)
	var generated_notes: Array = []
	var occupied_lanes_by_time := _build_occupied_lanes_by_time(remix_notes)
	var note_counts_by_time := _build_note_counts_by_time(remix_notes)
	var hold_intervals_by_lane := _build_hold_intervals_by_lane(remix_notes, lane_count)
	var note_times_by_lane := _build_note_times_by_lane(remix_notes, lane_count)
	var existing_group_times := _group_times(source_groups)
	var generated_group_times: Array = []
	var difficulty_rank := _difficulty_rank(difficulty)
	var impossible_remix := _is_impossible_remix_difficulty(difficulty)
	var min_spacing := float(MIN_SPACING.get(difficulty, MIN_SPACING["Medium"]))
	var beat_sec := 60.0 / bpm
	var max_generated_notes_per_time := 1 if impossible_remix else MAX_TOTAL_NOTES_PER_TIME
	var max_chord_lanes := 1 if impossible_remix else mini(3 if difficulty_rank >= 2 else 2, lane_count)
	var accent_limit := maxi(1, int(roundf(float(target_additions) * ACCENT_GROUP_RATIO)))
	var accent_groups_used := 0
	var has_generated_hold := false
	var has_generated_chord := false

	for candidate_variant in candidates:
		if generated_notes.size() >= target_additions:
			break
		if candidate_variant is not Dictionary:
			continue
		var candidate: Dictionary = candidate_variant
		var time := _round_time(float(candidate.get("time", 0.0)))
		if time < MIN_START_TIME:
			continue
		var is_accent := bool(candidate.get("accent", false))
		if is_accent and accent_groups_used >= accent_limit:
			continue
		if not is_accent and _nearest_time_distance(time, existing_group_times) < min_spacing:
			continue
		if _nearest_time_distance(time, generated_group_times) < min_spacing:
			continue

		var time_key := _time_key(time)
		var existing_note_count_at_time := int(note_counts_by_time.get(time_key, 0))
		if is_accent and existing_note_count_at_time >= 2:
			continue
		var allowed_generated_at_time := maxi(0, max_generated_notes_per_time - existing_note_count_at_time)
		if existing_note_count_at_time > 0:
			allowed_generated_at_time = mini(allowed_generated_at_time, 1)
		if allowed_generated_at_time <= 0:
			continue

		var remaining := mini(target_additions - generated_notes.size(), allowed_generated_at_time)
		var force_chord := false if impossible_remix else existing_note_count_at_time == 0 and not has_generated_chord and remaining >= 2 and generated_notes.size() >= maxi(2, int(target_additions * 0.35))
		var chord_size := 1 if impossible_remix else _choose_chord_size(rng, remaining, mini(max_chord_lanes, allowed_generated_at_time), force_chord)
		var force_hold := not has_generated_hold and generated_notes.size() >= maxi(1, int(target_additions * 0.45))
		var hold_length := _choose_hold_length(rng, beat_sec, difficulty_rank, force_hold)
		var lanes := _choose_lanes(time, chord_size, lane_count, occupied_lanes_by_time, hold_intervals_by_lane, note_times_by_lane, hold_length, rng, impossible_remix)

		if lanes.is_empty() and hold_length > 0.0:
			hold_length = 0.0
			lanes = _choose_lanes(time, chord_size, lane_count, occupied_lanes_by_time, hold_intervals_by_lane, note_times_by_lane, hold_length, rng)
		if lanes.is_empty():
			continue

		var group_generated_count := 0
		for lane_variant in lanes:
			if generated_notes.size() >= target_additions:
				break
			var lane := int(lane_variant)
			var note := {
				"time": time,
				"lane": lane,
				"type": "tap",
				"_generated": true,
				"_generator": GENERATOR_VERSION,
			}
			var actual_hold_length := hold_length
			if impossible_remix and hold_length > 0.0:
				actual_hold_length = _trim_hold_length_for_lane(time, lane, hold_length, hold_intervals_by_lane, note_times_by_lane)
			if actual_hold_length >= MIN_GENERATED_HOLD_LENGTH:
				note["type"] = "hold"
				note["duration"] = actual_hold_length
				note["length"] = actual_hold_length
				has_generated_hold = true
				_add_hold_interval(hold_intervals_by_lane, lane, time, time + actual_hold_length)
			_add_occupied_lane(occupied_lanes_by_time, time, lane)
			note_counts_by_time[time_key] = int(note_counts_by_time.get(time_key, 0)) + 1
			_add_note_time(note_times_by_lane, lane, time)
			remix_notes.append(note)
			generated_notes.append(note)
			group_generated_count += 1

		if group_generated_count > 0:
			generated_group_times.append(time)
			if is_accent:
				accent_groups_used += 1
			if group_generated_count > 1:
				has_generated_chord = true

	_sort_and_assign_ids(remix_notes)
	chart["notes"] = remix_notes
	chart["lane_count"] = lane_count
	chart["remix"] = {
		"generator_version": GENERATOR_VERSION,
		"base_chart_hash": base_chart_hash,
		"seed": seed,
		"generated_note_count": generated_notes.size(),
	}

	return {
		"chart": chart,
		"runtime_chart_hash": _runtime_chart_hash(chart, song_entry, difficulty, base_chart_hash, seed_source),
		"generated_note_count": generated_notes.size(),
		"generator_version": GENERATOR_VERSION,
		"seed": seed,
	}


static func _seed_source(song_entry: Dictionary, difficulty: String, lane_count: int, base_chart_hash: String) -> String:
	return "%s|%s|%s|%d|%s" % [
		GENERATOR_VERSION,
		str(song_entry.get("id", song_entry.get("display_name", ""))),
		difficulty,
		lane_count,
		base_chart_hash,
	]


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
		var duration := _duration_for_note(note)
		note["lane"] = clampi(int(roundf(float(note.get("lane", 0)))), 0, lane_count - 1)
		note["time"] = _round_time(float(note.get("time", 0.0)))
		if duration > 0.0:
			note["type"] = "hold"
			note["duration"] = duration
			note["length"] = duration
		elif not note.has("type"):
			note["type"] = "tap"
		notes.append(note)
	_sort_and_assign_ids(notes)
	return notes


static func _build_source_groups(notes: Array) -> Array:
	var groups_by_key := {}
	for note_variant in notes:
		if note_variant is not Dictionary:
			continue
		var note: Dictionary = note_variant
		var time := float(note.get("time", 0.0))
		var key := _time_key(time)
		var group: Dictionary = groups_by_key.get(key, {
			"time": time,
			"lanes": {},
			"note_count": 0,
			"hold_count": 0,
			"score": 0.0,
		})
		group["time"] = minf(float(group.get("time", time)), time)
		var lanes: Dictionary = group.get("lanes", {})
		lanes[int(note.get("lane", 0))] = true
		group["lanes"] = lanes
		group["note_count"] = int(group.get("note_count", 0)) + 1
		if _duration_for_note(note) > 0.0:
			group["hold_count"] = int(group.get("hold_count", 0)) + 1
		groups_by_key[key] = group

	var groups: Array = []
	for key in groups_by_key.keys():
		var group: Dictionary = groups_by_key[key]
		var score := 1.0 + float(group.get("note_count", 0)) * 0.40 + float(group.get("hold_count", 0)) * 0.25
		group["score"] = score
		groups.append(group)
	groups.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("time", 0.0)) < float(b.get("time", 0.0))
	)
	return groups


static func _build_candidates(notes: Array, source_groups: Array, bpm: float, target_additions: int) -> Array:
	var beat_sec := 60.0 / maxf(1.0, bpm)
	var chart_end := _chart_end_time(notes)
	var raw_candidates: Array = []

	for group_variant in source_groups:
		if group_variant is not Dictionary:
			continue
		var group: Dictionary = group_variant
		raw_candidates.append({
			"time": _round_time(float(group.get("time", 0.0))),
			"score": 2.0 + float(group.get("score", 0.0)) + _local_intensity(float(group.get("time", 0.0)), source_groups, beat_sec * 1.5),
			"accent": true,
		})

	var step := maxf(0.07, beat_sec * 0.25)
	var t := 0.0
	while t <= chart_end:
		var score := _beat_strength(t, beat_sec)
		score += _local_intensity(t, source_groups, beat_sec * 1.75)
		score += _gap_score(t, notes, beat_sec)
		raw_candidates.append({
			"time": _round_time(t),
			"score": score,
			"accent": false,
		})
		t += step

	var dedup := {}
	for candidate_variant in raw_candidates:
		var candidate: Dictionary = candidate_variant
		var key := _time_key(float(candidate.get("time", 0.0)))
		if not dedup.has(key) or float(candidate.get("score", 0.0)) > float((dedup[key] as Dictionary).get("score", 0.0)):
			dedup[key] = candidate

	var candidates: Array = []
	for key in dedup.keys():
		candidates.append(dedup[key])
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var score_a := float(a.get("score", 0.0))
		var score_b := float(b.get("score", 0.0))
		if is_equal_approx(score_a, score_b):
			return float(a.get("time", 0.0)) < float(b.get("time", 0.0))
		return score_a > score_b
	)

	# Keep enough candidates for fallback passes without dragging around every low-signal grid point.
	return candidates.slice(0, mini(candidates.size(), maxi(target_additions * 8, 64)))


static func _beat_strength(time: float, beat_sec: float) -> float:
	var beat_pos := fmod(maxf(0.0, time), beat_sec)
	var dist_to_beat := minf(beat_pos, beat_sec - beat_pos)
	var dist_to_half := absf(beat_pos - beat_sec * 0.5)
	var dist_to_quarter := minf(absf(beat_pos - beat_sec * 0.25), absf(beat_pos - beat_sec * 0.75))
	if dist_to_beat <= 0.012:
		return 1.25
	if dist_to_half <= 0.012:
		return 0.95
	if dist_to_quarter <= 0.012:
		return 0.72
	return clampf(0.62 - dist_to_beat / maxf(0.001, beat_sec), 0.0, 0.62)


static func _local_intensity(time: float, source_groups: Array, window: float) -> float:
	var score := 0.0
	for group_variant in source_groups:
		if group_variant is not Dictionary:
			continue
		var group: Dictionary = group_variant
		var dt := absf(float(group.get("time", 0.0)) - time)
		if dt > window:
			continue
		var falloff := 1.0 - (dt / maxf(0.001, window))
		score += falloff * float(group.get("score", 0.0)) * 0.22
	return score


static func _gap_score(time: float, notes: Array, beat_sec: float) -> float:
	var nearest := _nearest_note_time_distance(time, notes)
	if nearest < 0.045:
		return -0.75
	return clampf(nearest / maxf(0.001, beat_sec * 1.5), 0.0, 1.0) * 0.65


static func _choose_chord_size(rng: RandomNumberGenerator, remaining: int, max_chord_lanes: int, force_chord: bool) -> int:
	var capped := mini(maxi(1, remaining), maxi(1, max_chord_lanes))
	if capped < 2:
		return 1
	if force_chord or rng.randf() < CHORD_GROUP_RATIO:
		if capped >= 3 and rng.randf() < TRIPLE_CHORD_RATIO:
			return 3
		return 2
	return 1


static func _choose_hold_length(rng: RandomNumberGenerator, beat_sec: float, difficulty_rank: int, force_hold: bool) -> float:
	if not force_hold and rng.randf() >= HOLD_GROUP_RATIO:
		return 0.0
	var beats := 1.0
	if difficulty_rank >= 3 and rng.randf() < 0.35:
		beats = 1.5
	elif rng.randf() < 0.30:
		beats = 0.5
	return _round_time(clampf(beat_sec * beats, 0.18, 1.60))


static func _choose_lanes(
	time: float,
	count: int,
	lane_count: int,
	occupied_lanes_by_time: Dictionary,
	hold_intervals_by_lane: Dictionary,
	note_times_by_lane: Dictionary,
	hold_length: float,
	rng: RandomNumberGenerator,
	allow_hold_trim: bool = false
) -> Array:
	var free_lanes: Array = []
	var end_time := time + hold_length
	var occupied: Dictionary = occupied_lanes_by_time.get(_time_key(time), {})
	for lane in range(lane_count):
		if occupied.has(lane):
			continue
		if _lane_has_hold_at(hold_intervals_by_lane, lane, time):
			continue
		if hold_length > 0.0 and not allow_hold_trim and _lane_hold_overlaps(hold_intervals_by_lane, lane, time, end_time):
			continue
		if hold_length > 0.0 and not allow_hold_trim and _lane_note_exists_during(note_times_by_lane, lane, time, end_time):
			continue
		free_lanes.append(lane)
	if free_lanes.is_empty():
		return []
	_shuffle_array(free_lanes, rng)
	return free_lanes.slice(0, mini(count, free_lanes.size()))


static func _trim_hold_length_for_lane(
	time: float,
	lane: int,
	requested_length: float,
	hold_intervals_by_lane: Dictionary,
	note_times_by_lane: Dictionary
) -> float:
	var requested_end := time + requested_length
	var collision_time := requested_end
	var times: Array = note_times_by_lane.get(lane, [])
	for note_time_variant in times:
		var note_time := float(note_time_variant)
		if note_time <= time + 0.001:
			continue
		if note_time < collision_time:
			collision_time = note_time

	var intervals: Array = hold_intervals_by_lane.get(lane, [])
	for interval_variant in intervals:
		var interval: Dictionary = interval_variant
		var interval_start := float(interval.get("start", 0.0))
		var interval_end := float(interval.get("end", 0.0))
		if time >= interval_start - 0.001 and time <= interval_end + 0.001:
			return 0.0
		if interval_start > time + 0.001 and interval_start < collision_time:
			collision_time = interval_start

	if collision_time >= requested_end - 0.001:
		return requested_length

	var trimmed_length := _round_time(collision_time - time - HOLD_TRIM_PADDING)
	if trimmed_length < MIN_GENERATED_HOLD_LENGTH:
		return 0.0
	return minf(requested_length, trimmed_length)


static func _shuffle_array(values: Array, rng: RandomNumberGenerator) -> void:
	for i in range(values.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = values[i]
		values[i] = values[j]
		values[j] = tmp


static func _build_occupied_lanes_by_time(notes: Array) -> Dictionary:
	var occupied := {}
	for note_variant in notes:
		if note_variant is not Dictionary:
			continue
		var note: Dictionary = note_variant
		_add_occupied_lane(occupied, float(note.get("time", 0.0)), int(note.get("lane", 0)))
	return occupied


static func _add_occupied_lane(occupied_lanes_by_time: Dictionary, time: float, lane: int) -> void:
	var key := _time_key(time)
	var lanes: Dictionary = occupied_lanes_by_time.get(key, {})
	lanes[lane] = true
	occupied_lanes_by_time[key] = lanes


static func _build_note_counts_by_time(notes: Array) -> Dictionary:
	var counts := {}
	for note_variant in notes:
		if note_variant is not Dictionary:
			continue
		var key := _time_key(float((note_variant as Dictionary).get("time", 0.0)))
		counts[key] = int(counts.get(key, 0)) + 1
	return counts


static func _build_note_times_by_lane(notes: Array, lane_count: int) -> Dictionary:
	var note_times := {}
	for lane in range(lane_count):
		note_times[lane] = []
	for note_variant in notes:
		if note_variant is not Dictionary:
			continue
		var note: Dictionary = note_variant
		_add_note_time(note_times, int(note.get("lane", 0)), float(note.get("time", 0.0)))
	return note_times


static func _add_note_time(note_times_by_lane: Dictionary, lane: int, time: float) -> void:
	var times: Array = note_times_by_lane.get(lane, [])
	times.append(_round_time(time))
	note_times_by_lane[lane] = times


static func _build_hold_intervals_by_lane(notes: Array, lane_count: int) -> Dictionary:
	var intervals := {}
	for lane in range(lane_count):
		intervals[lane] = []
	for note_variant in notes:
		if note_variant is not Dictionary:
			continue
		var note: Dictionary = note_variant
		var duration := _duration_for_note(note)
		if duration <= 0.0:
			continue
		var start := float(note.get("time", 0.0))
		_add_hold_interval(intervals, int(note.get("lane", 0)), start, start + duration)
	return intervals


static func _add_hold_interval(hold_intervals_by_lane: Dictionary, lane: int, start_time: float, end_time: float) -> void:
	var intervals: Array = hold_intervals_by_lane.get(lane, [])
	intervals.append({"start": start_time, "end": end_time})
	hold_intervals_by_lane[lane] = intervals


static func _lane_has_hold_at(hold_intervals_by_lane: Dictionary, lane: int, time: float) -> bool:
	var intervals: Array = hold_intervals_by_lane.get(lane, [])
	for interval_variant in intervals:
		var interval: Dictionary = interval_variant
		if time >= float(interval.get("start", 0.0)) - 0.001 and time <= float(interval.get("end", 0.0)) + 0.001:
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
	for note_time_variant in times:
		var note_time := float(note_time_variant)
		if note_time > start_time + 0.001 and note_time < end_time - 0.001:
			return true
	return false


static func _group_times(source_groups: Array) -> Array:
	var times: Array = []
	for group_variant in source_groups:
		if group_variant is Dictionary:
			times.append(float((group_variant as Dictionary).get("time", 0.0)))
	return times


static func _nearest_note_time_distance(time: float, notes: Array) -> float:
	var best := INF
	for note_variant in notes:
		if note_variant is Dictionary:
			best = minf(best, absf(float((note_variant as Dictionary).get("time", 0.0)) - time))
	return best


static func _nearest_time_distance(time: float, times: Array) -> float:
	if times.is_empty():
		return INF
	var best := INF
	for value_variant in times:
		best = minf(best, absf(float(value_variant) - time))
	return best


static func _chart_end_time(notes: Array) -> float:
	var end_time := 0.0
	for note_variant in notes:
		if note_variant is Dictionary:
			var note: Dictionary = note_variant
			end_time = maxf(end_time, float(note.get("time", 0.0)) + _duration_for_note(note))
	return end_time


static func _duration_for_note(note: Dictionary) -> float:
	if note.has("duration"):
		return _round_time(maxf(0.0, float(note.get("duration", 0.0))))
	if note.has("length"):
		return _round_time(maxf(0.0, float(note.get("length", 0.0))))
	return 0.0


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
				var ag := 1 if bool(da.get("_generated", false)) else 0
				var bg := 1 if bool(db.get("_generated", false)) else 0
				return ag < bg
			return la < lb
		return ta < tb
	)
	for i in range(notes.size()):
		if notes[i] is Dictionary:
			var note: Dictionary = notes[i]
			note["id"] = i
			notes[i] = note


static func _runtime_chart_hash(chart: Dictionary, song_entry: Dictionary, difficulty: String, base_chart_hash: String, seed_source: String) -> String:
	var parts: Array[String] = [
		GENERATOR_VERSION,
		str(song_entry.get("id", "")),
		difficulty,
		base_chart_hash,
		seed_source,
		str(chart.get("lane_count", LaneCountResolver.DEFAULT_LANES)),
	]
	var notes: Array = chart.get("notes", []) as Array
	for note_variant in notes:
		if note_variant is not Dictionary:
			continue
		var note: Dictionary = note_variant
		parts.append("%d,%.3f,%d,%s,%.3f,%s" % [
			int(note.get("id", -1)),
			float(note.get("time", 0.0)),
			int(note.get("lane", 0)),
			str(note.get("type", "tap")),
			_duration_for_note(note),
			"g" if bool(note.get("_generated", false)) else "a",
		])
	return _sha256_text("\n".join(parts))


static func _sha256_text(text: String) -> String:
	var hash_context := HashingContext.new()
	if hash_context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	hash_context.update(text.to_utf8_buffer())
	return hash_context.finish().hex_encode()


static func _difficulty_rank(difficulty: String) -> int:
	match difficulty:
		"Easy":
			return 0
		"Medium":
			return 1
		"Hard":
			return 2
		"Expert":
			return 3
		"Professional":
			return 4
		_:
			return 1


static func _is_impossible_remix_difficulty(difficulty: String) -> bool:
	var normalized := difficulty.strip_edges().to_lower()
	return normalized == "professional" or normalized == "impossible"


static func _time_key(time: float) -> int:
	return int(round(time * TIME_KEY_SCALE))


static func _round_time(value: float) -> float:
	return roundf(value * TIME_KEY_SCALE) / TIME_KEY_SCALE
