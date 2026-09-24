extends RefCounted
class_name ChartImporter

const Utils := preload("res://scripts/editor/importers/ChartImportUtils.gd")
const LaneCountResolver := preload("res://scripts/songs/LaneCountResolver.gd")

const INSTRUMENT_SECTIONS := {
	"guitar": ["Single"],
	"ghl_guitar": ["GHLGuitar"],
	"bass": ["Bass", "DoubleBass", "GHLBass"],
	"rhythm": ["Rhythm", "DoubleRhythm", "GHLRhythm"],
	"synth": ["Synth"],
	"piano": ["Piano"],
	"keyboard": ["Keyboard", "Keys", "ProKeys"],
	"drums": ["Drums", "ProDrums"],
}


static func inspect_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "Failed to open chart file: %s" % path, "entries": [], "metadata": {}}
	return inspect_text(file.get_as_text(), path)


static func inspect_text(text: String, source_name: String = "notes.chart") -> Dictionary:
	var sections := _parse_sections(text)
	if not sections.has("Song"):
		return {"ok": false, "error": "Missing [Song] section in %s" % source_name, "entries": [], "metadata": {}}

	var song := _parse_key_values(sections.get("Song", []) as Array)
	var resolution := int(str(song.get("Resolution", "192")))
	if resolution <= 0:
		resolution = 192
	var tempo_events := _parse_tempo_events(sections.get("SyncTrack", []) as Array, resolution)
	var metadata := {
		"title": Utils.strip_rich_text(str(song.get("Name", source_name.get_basename())).strip_edges()),
		"artist": Utils.strip_rich_text(str(song.get("Artist", "Unknown Artist")).strip_edges()),
		"charter": Utils.strip_rich_text(str(song.get("Charter", "Unknown Charter")).strip_edges()),
		"bpm": float((tempo_events[0] as Dictionary).get("bpm", 120.0)) if not tempo_events.is_empty() else 120.0,
		"resolution": resolution,
	}

	var entries: Array[Dictionary] = []
	for instrument in INSTRUMENT_SECTIONS.keys():
		var suffixes: Array = INSTRUMENT_SECTIONS[instrument] as Array
		for suffix_value in suffixes:
			var suffix := str(suffix_value)
			for diff in Utils.DIFFICULTY_ORDER:
				var section := _section_name(diff, suffix)
				if not sections.has(section):
					continue
				var lane_count := _lane_count_for_suffix(suffix)
				var notes := _convert_notes(sections.get(section, []) as Array, resolution, tempo_events, lane_count, _note_map_for_suffix(suffix))
				if notes.is_empty():
					continue
				entries.append({
					"instrument": instrument,
					"difficulty": diff,
					"source_name": "%s %s" % [diff.capitalize(), Utils.instrument_label(str(instrument))],
					"source_section": section,
					"lane_count": lane_count,
					"notes": notes,
				})

	if entries.is_empty():
		return {"ok": false, "error": "No supported lane-based instrument notes found in %s. Mic and vocals are intentionally ignored." % source_name, "entries": [], "metadata": metadata}
	return {"ok": true, "error": "", "entries": entries, "metadata": metadata}


static func _lane_count_for_suffix(suffix: String) -> int:
	if suffix.begins_with("GHL"):
		return 6
	if suffix.contains("Drums"):
		return 4
	return 5


static func _note_map_for_suffix(suffix: String) -> Dictionary:
	if suffix.contains("Drums"):
		return {1: 0, 2: 1, 3: 2, 4: 3}
	return {}


static func _section_name(difficulty: String, suffix: String) -> String:
	return difficulty.capitalize() + suffix


static func _parse_sections(text: String) -> Dictionary:
	var sections := {}
	var current := ""
	for raw_line in text.split("\n"):
		var line := raw_line.strip_edges()
		if line.is_empty():
			continue
		if line.begins_with("[") and line.ends_with("]"):
			current = line.substr(1, line.length() - 2)
			sections[current] = []
			continue
		if current.is_empty() or line == "{" or line == "}":
			continue
		(sections[current] as Array).append(line)
	return sections


static func _parse_key_values(lines: Array) -> Dictionary:
	var out := {}
	for raw in lines:
		var line := String(raw)
		var eq := line.find("=")
		if eq < 0:
			continue
		var key := line.substr(0, eq).strip_edges()
		var value := line.substr(eq + 1).strip_edges()
		if value.begins_with("\"") and value.ends_with("\"") and value.length() >= 2:
			value = value.substr(1, value.length() - 2)
		out[key] = value
	return out


static func _parse_tempo_events(lines: Array, resolution: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for raw in lines:
		var line := String(raw)
		var eq := line.find("=")
		if eq < 0:
			continue
		var tick_text := line.substr(0, eq).strip_edges()
		var rhs := line.substr(eq + 1).strip_edges().split(" ", false)
		if rhs.size() >= 2 and str(rhs[0]) == "B" and tick_text.is_valid_int():
			events.append({"tick": int(tick_text), "bpm": float(rhs[1]) / 1000.0})
	events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("tick", 0)) < int(b.get("tick", 0))
	)
	if events.is_empty() or int((events[0] as Dictionary).get("tick", 0)) != 0:
		events.insert(0, {"tick": 0, "bpm": 120.0})
	return _tempo_map_with_seconds(events, resolution)


static func _tempo_map_with_seconds(events: Array[Dictionary], resolution: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var last_tick := 0
	var last_sec := 0.0
	var last_bpm := float((events[0] as Dictionary).get("bpm", 120.0))
	for i in range(events.size()):
		var event := events[i]
		var tick := int(event.get("tick", 0))
		if i == 0:
			out.append({"tick": tick, "bpm": float(event.get("bpm", 120.0)), "sec": 0.0})
			last_tick = tick
			last_bpm = float(event.get("bpm", 120.0))
			continue
		last_sec += _ticks_to_seconds(tick - last_tick, last_bpm, resolution)
		out.append({"tick": tick, "bpm": float(event.get("bpm", last_bpm)), "sec": last_sec})
		last_tick = tick
		last_bpm = float(event.get("bpm", last_bpm))
	return out


static func _tick_to_seconds(tick: int, tempo_events: Array[Dictionary], resolution: int) -> float:
	var active := tempo_events[0] as Dictionary
	for event in tempo_events:
		if int((event as Dictionary).get("tick", 0)) <= tick:
			active = event as Dictionary
		else:
			break
	var base_tick := int(active.get("tick", 0))
	var base_sec := float(active.get("sec", 0.0))
	var bpm := float(active.get("bpm", 120.0))
	return base_sec + _ticks_to_seconds(tick - base_tick, bpm, resolution)


static func _ticks_to_seconds(ticks: int, bpm: float, resolution: int) -> float:
	return (float(ticks) / float(resolution)) * (60.0 / maxf(1.0, bpm))


static func _convert_notes(lines: Array, resolution: int, tempo_events: Array[Dictionary], lane_count: int, note_map: Dictionary = {}) -> Array[Dictionary]:
	var notes: Array[Dictionary] = []
	lane_count = LaneCountResolver.clamp_lane_count(lane_count)
	var chord_lanes_by_tick := {}
	for raw in lines:
		var line := String(raw)
		var eq := line.find("=")
		if eq < 0:
			continue
		var tick_text := line.substr(0, eq).strip_edges()
		if not tick_text.is_valid_int():
			continue
		var rhs := line.substr(eq + 1).strip_edges().split(" ", false)
		if rhs.size() < 3 or str(rhs[0]) != "N":
			continue
		var note_num := int(str(rhs[1]))
		var lane := note_num
		if not note_map.is_empty():
			if not note_map.has(note_num):
				continue
			lane = int(note_map[note_num])
		if lane < 0 or lane >= lane_count:
			continue
		var tick := int(tick_text)
		var length_ticks := int(str(rhs[2]))
		var lanes: Array = chord_lanes_by_tick.get(tick, []) as Array
		if lanes.has(lane):
			continue
		lanes.append(lane)
		chord_lanes_by_tick[tick] = lanes
		var time_sec := _tick_to_seconds(tick, tempo_events, resolution)
		var length_sec := _ticks_to_seconds(length_ticks, _bpm_at_tick(tick, tempo_events), resolution)
		if length_sec > 0.001:
			notes.append({"time": time_sec, "lane": lane, "type": "hold", "length": length_sec, "duration": length_sec})
		else:
			notes.append({"time": time_sec, "lane": lane, "type": "tap"})
	return notes


static func _bpm_at_tick(tick: int, tempo_events: Array[Dictionary]) -> float:
	var bpm := 120.0
	for event in tempo_events:
		var e := event as Dictionary
		if int(e.get("tick", 0)) <= tick:
			bpm = float(e.get("bpm", bpm))
		else:
			break
	return bpm
