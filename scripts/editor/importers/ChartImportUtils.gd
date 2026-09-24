extends RefCounted
class_name ChartImportUtils

const LaneCountResolver := preload("res://scripts/songs/LaneCountResolver.gd")

const DIFFICULTY_ORDER: Array[String] = ["easy", "medium", "hard", "expert", "professional"]
const INSTRUMENT_LABELS := {
	"guitar": "Guitar",
	"bass": "Bass Guitar",
	"rhythm": "Rhythm Guitar",
	"synth": "Synth",
	"piano": "Piano",
	"keyboard": "Keyboard",
	"drums": "Drums",
	"ghl_guitar": "GHL Guitar",
	"harmonic_drive_json": "Harmonic Drive JSON",
	"midi": "MIDI",
	"osu_mania": "osu!mania",
	"osu_lanes": "osu! lanes",
}


static func sanitize_id(value: String) -> String:
	var out := ""
	var trimmed := value.strip_edges()
	for i in range(trimmed.length()):
		var c := trimmed.substr(i, 1)
		var ok := (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9") or c == "_" or c == "-" or c == "."
		out += c if ok else "_"
	while out.contains("__"):
		out = out.replace("__", "_")
	out = out.strip_edges()
	return "song_project" if out.is_empty() else out.substr(0, mini(out.length(), 80))


static func strip_rich_text(value: String) -> String:
	var out := ""
	var in_tag := false
	for i in range(value.length()):
		var c := value.substr(i, 1)
		if c == "<":
			in_tag = true
			continue
		if c == ">":
			in_tag = false
			continue
		if not in_tag:
			out += c
	return out.strip_edges()


static func instrument_label(instrument: String) -> String:
	return str(INSTRUMENT_LABELS.get(instrument, instrument.capitalize()))


static func unique_path(folder: String, filename: String) -> String:
	var clean_name := filename.get_file()
	if clean_name.is_empty():
		clean_name = "imported_file"
	var stem := clean_name.get_basename()
	var ext := clean_name.get_extension()
	var candidate := folder.path_join(clean_name)
	var index := 2
	while FileAccess.file_exists(candidate):
		var suffix := "_%d" % index
		var next_name := stem + suffix
		if not ext.is_empty():
			next_name += "." + ext
		candidate = folder.path_join(next_name)
		index += 1
	return candidate


static func copy_file_to_project(source_path: String, project_folder: String, preferred_name: String = "") -> Dictionary:
	var source_abs := source_path
	if source_path.begins_with("user://") or source_path.begins_with("res://"):
		source_abs = ProjectSettings.globalize_path(source_path)
	if not FileAccess.file_exists(source_abs):
		return {"ok": false, "path": "", "error": "Source file not found: %s" % source_path}

	var name := preferred_name if not preferred_name.strip_edges().is_empty() else source_path.get_file()
	var target := unique_path(project_folder, name)
	var bytes := FileAccess.get_file_as_bytes(source_abs)
	if bytes.is_empty():
		return {"ok": false, "path": "", "error": "Failed to read source file: %s" % source_path}
	var file := FileAccess.open(target, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "path": "", "error": "Failed to write project file: %s" % target}
	file.store_buffer(bytes)
	file.flush()
	return {"ok": true, "path": target, "error": ""}


static func chart_payload(difficulty: String, notes: Array[Dictionary], lane_count: int = LaneCountResolver.DEFAULT_LANES, metadata: Dictionary = {}) -> Dictionary:
	var sorted_notes := notes.duplicate(true)
	sorted_notes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ta := float(a.get("time", 0.0))
		var tb := float(b.get("time", 0.0))
		if is_equal_approx(ta, tb):
			return int(a.get("lane", 0)) < int(b.get("lane", 0))
		return ta < tb
	)
	var payload := {
		"version": 1,
		"difficulty": difficulty,
		"lane_count": LaneCountResolver.clamp_lane_count(lane_count),
		"notes": sorted_notes,
	}
	for key in ["title", "artist", "charter"]:
		if metadata.has(key):
			var value := strip_rich_text(str(metadata.get(key, "")))
			if not value.is_empty():
				payload[key] = value
	if metadata.has("bpm"):
		var bpm := float(metadata.get("bpm", 0.0))
		if bpm > 0.0:
			payload["bpm"] = bpm
	if metadata.has("nps"):
		payload["nps"] = maxf(0.0, float(metadata.get("nps", 0.0)))
	return payload


static func write_json(path: String, payload: Dictionary) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "Failed to write %s" % path}
	file.store_string(JSON.stringify(payload, "\t", false))
	file.flush()
	return {"ok": true, "error": ""}


static func read_u16_be(bytes: PackedByteArray, offset: int) -> int:
	if offset + 1 >= bytes.size():
		return 0
	return (int(bytes[offset]) << 8) | int(bytes[offset + 1])


static func read_u32_be(bytes: PackedByteArray, offset: int) -> int:
	if offset + 3 >= bytes.size():
		return 0
	return (int(bytes[offset]) << 24) | (int(bytes[offset + 1]) << 16) | (int(bytes[offset + 2]) << 8) | int(bytes[offset + 3])


static func read_i32_le(bytes: PackedByteArray, offset: int) -> int:
	if offset + 3 >= bytes.size():
		return 0
	var value := int(bytes[offset]) | (int(bytes[offset + 1]) << 8) | (int(bytes[offset + 2]) << 16) | (int(bytes[offset + 3]) << 24)
	if value >= 2147483648:
		value -= 4294967296
	return value


static func read_u32_le(bytes: PackedByteArray, offset: int) -> int:
	if offset + 3 >= bytes.size():
		return 0
	return int(bytes[offset]) | (int(bytes[offset + 1]) << 8) | (int(bytes[offset + 2]) << 16) | (int(bytes[offset + 3]) << 24)


static func read_u64_le(bytes: PackedByteArray, offset: int) -> int:
	if offset + 7 >= bytes.size():
		return 0
	var lo := read_u32_le(bytes, offset)
	var hi := read_u32_le(bytes, offset + 4)
	return lo + (hi * 4294967296)
