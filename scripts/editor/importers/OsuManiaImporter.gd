extends RefCounted
class_name OsuManiaImporter

const Utils := preload("res://scripts/editor/importers/ChartImportUtils.gd")
const LaneCountResolver := preload("res://scripts/songs/LaneCountResolver.gd")

const MIN_OSU_MANIA_KEYS := 3
const MAX_OSU_MANIA_KEYS := 7


static func inspect_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "Failed to open osu! beatmap: %s" % path, "entries": [], "metadata": {}}
	return inspect_text(file.get_as_text(), path.get_file())


static func inspect_text(text: String, source_name: String = "beatmap.osu") -> Dictionary:
	var sections := _parse_sections(text)
	var general := _parse_key_values(sections.get("General", []) as Array)
	var metadata_section := _parse_key_values(sections.get("Metadata", []) as Array)
	var difficulty := _parse_key_values(sections.get("Difficulty", []) as Array)
	var mode := int(str(general.get("Mode", "0")))
	if mode != 3:
		return {
			"ok": false,
			"error": "%s is not a supported osu!mania beatmap. Only Mode 3 osu!mania imports are supported." % source_name,
			"entries": [],
			"metadata": {},
		}
	var lane_count := int(roundf(float(difficulty.get("CircleSize", LaneCountResolver.DEFAULT_LANES))))
	if lane_count < MIN_OSU_MANIA_KEYS or lane_count > MAX_OSU_MANIA_KEYS:
		return {
			"ok": false,
			"error": "%s uses %dK. Only osu!mania 3K, 4K, 5K, 6K, and 7K imports are supported." % [source_name, lane_count],
			"entries": [],
			"metadata": {},
		}
	var timing_points := _parse_timing_points(sections.get("TimingPoints", []) as Array)
	var notes := _parse_hit_objects(sections.get("HitObjects", []) as Array, lane_count)
	if notes.is_empty():
		return {"ok": false, "error": "No supported osu! hit objects found in %s." % source_name, "entries": [], "metadata": {}}
	var metadata := {
		"title": Utils.strip_rich_text(str(metadata_section.get("Title", source_name.get_basename()))),
		"artist": Utils.strip_rich_text(str(metadata_section.get("Artist", "Unknown Artist"))),
		"charter": Utils.strip_rich_text(str(metadata_section.get("Creator", "Unknown Charter"))),
		"bpm": _first_bpm(timing_points),
	}
	var version := str(metadata_section.get("Version", "expert")).strip_edges()
	var entry := {
		"instrument": "osu_mania",
		"difficulty": _difficulty_from_version(version),
		"source_name": "osu!mania %s" % version,
		"source_section": "HitObjects",
		"lane_count": lane_count,
		"notes": notes,
	}
	return {"ok": true, "error": "", "entries": [entry], "metadata": metadata}


static func _parse_sections(text: String) -> Dictionary:
	var sections := {}
	var current := ""
	for raw_line in text.split("\n"):
		var line := raw_line.strip_edges()
		if line.is_empty() or line.begins_with("//"):
			continue
		if line.begins_with("[") and line.ends_with("]"):
			current = line.substr(1, line.length() - 2)
			sections[current] = []
			continue
		if current.is_empty():
			continue
		(sections[current] as Array).append(line)
	return sections


static func _parse_key_values(lines: Array) -> Dictionary:
	var out := {}
	for raw in lines:
		var line := String(raw)
		var colon := line.find(":")
		if colon < 0:
			continue
		var key := line.substr(0, colon).strip_edges()
		var value := line.substr(colon + 1).strip_edges()
		out[key] = value
	return out


static func _parse_timing_points(lines: Array) -> Array[Dictionary]:
	var points: Array[Dictionary] = []
	for raw in lines:
		var parts := String(raw).split(",", true)
		if parts.size() < 2:
			continue
		var time_ms := float(parts[0])
		var beat_length := float(parts[1])
		if beat_length <= 0.0:
			continue
		points.append({"time": time_ms / 1000.0, "bpm": 60000.0 / beat_length})
	points.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("time", 0.0)) < float(b.get("time", 0.0))
	)
	return points


static func _first_bpm(points: Array[Dictionary]) -> float:
	if points.is_empty():
		return 120.0
	return float((points[0] as Dictionary).get("bpm", 120.0))


static func _parse_hit_objects(lines: Array, lane_count: int) -> Array[Dictionary]:
	var notes: Array[Dictionary] = []
	for raw in lines:
		var parts := String(raw).split(",", true)
		if parts.size() < 5:
			continue
		var x := float(parts[0])
		var start_ms := float(parts[2])
		var object_type := int(parts[3])
		var lane := _lane_for_hit_object(x, lane_count)
		var start_sec := start_ms / 1000.0
		if (object_type & 128) != 0 and parts.size() >= 6:
			var hold_parts := String(parts[5]).split(":", true)
			var end_ms := float(hold_parts[0])
			var length := maxf(0.0, (end_ms - start_ms) / 1000.0)
			if length > 0.001:
				notes.append({"time": start_sec, "lane": lane, "type": "hold", "length": length, "duration": length})
			else:
				notes.append({"time": start_sec, "lane": lane, "type": "tap"})
		elif (object_type & 2) != 0:
			notes.append({"time": start_sec, "lane": lane, "type": "tap"})
		elif (object_type & 8) != 0:
			notes.append({"time": start_sec, "lane": lane, "type": "tap"})
		elif (object_type & 1) != 0:
			notes.append({"time": start_sec, "lane": lane, "type": "tap"})
	notes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ta := float(a.get("time", 0.0))
		var tb := float(b.get("time", 0.0))
		if is_equal_approx(ta, tb):
			return int(a.get("lane", 0)) < int(b.get("lane", 0))
		return ta < tb
	)
	return notes


static func _lane_for_hit_object(x: float, lane_count: int) -> int:
	return clampi(int(floorf((x * float(lane_count)) / 512.0)), 0, lane_count - 1)


static func _difficulty_from_version(version: String) -> String:
	var text := version.strip_edges().to_lower()
	if text.contains("easy"):
		return "easy"
	if text.contains("normal") or text.contains("medium"):
		return "medium"
	if text.contains("hard"):
		return "hard"
	if text.contains("expert") or text.contains("insane"):
		return "expert"
	return "expert"
