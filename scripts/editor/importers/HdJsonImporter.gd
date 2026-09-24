extends RefCounted
class_name HdJsonImporter

const Utils := preload("res://scripts/editor/importers/ChartImportUtils.gd")
const LaneCountResolver := preload("res://scripts/songs/LaneCountResolver.gd")
const ChartValidator := preload("res://scripts/songs/ChartValidator.gd")


static func inspect_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "Failed to open JSON chart file: %s" % path, "entries": [], "metadata": {}}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is not Dictionary:
		return {"ok": false, "error": "JSON chart must contain an object at the root: %s" % path, "entries": [], "metadata": {}}
	return inspect_payload(parsed as Dictionary, path)


static func inspect_payload(payload: Dictionary, source_name: String = "chart.json") -> Dictionary:
	var notes_var: Variant = payload.get("notes", null)
	if notes_var is not Array:
		return {"ok": false, "error": "Harmonic Drive JSON charts must contain a notes array.", "entries": [], "metadata": {}}

	var notes := _normalize_notes(notes_var as Array)
	var lane_count := _resolve_lane_count(payload, notes)
	var difficulty := _resolve_difficulty(payload, source_name)
	var metadata := {
		"title": Utils.strip_rich_text(str(payload.get("title", _title_from_source(source_name)))),
		"artist": Utils.strip_rich_text(str(payload.get("artist", "Unknown Artist"))),
		"charter": Utils.strip_rich_text(str(payload.get("charter", "Unknown Charter"))),
		"bpm": float(payload.get("bpm", 120.0)),
		"nps": float(payload.get("nps", 0.0)),
	}
	var validation_payload: Dictionary = Utils.chart_payload(difficulty, notes, lane_count)
	var validation := ChartValidator.validate_chart(validation_payload, difficulty)
	if not ChartValidator.is_valid(validation):
		var errors: Array = validation.get("errors", []) as Array
		var first: Dictionary = errors[0] as Dictionary if not errors.is_empty() else {}
		return {
			"ok": false,
			"error": "Invalid Harmonic Drive JSON chart: %s" % str(first.get("message", "unknown validation error")),
			"entries": [],
			"metadata": metadata,
		}

	return {
		"ok": true,
		"error": "",
		"entries": [{
			"instrument": "harmonic_drive_json",
			"difficulty": difficulty,
			"source_name": "%s Harmonic Drive JSON" % difficulty.capitalize(),
			"source_section": "notes",
			"lane_count": lane_count,
			"notes": notes,
		}],
		"metadata": metadata,
	}


static func _normalize_notes(source_notes: Array) -> Array[Dictionary]:
	var notes: Array[Dictionary] = []
	for i in range(source_notes.size()):
		var source_var: Variant = source_notes[i]
		if source_var is not Dictionary:
			continue
		var source: Dictionary = source_var as Dictionary
		var note := {
			"time": maxf(0.0, float(source.get("time", 0.0))),
			"lane": int(roundf(float(source.get("lane", 0)))),
		}
		var length := 0.0
		if source.has("length"):
			length = float(source.get("length", 0.0))
		elif source.has("duration"):
			length = float(source.get("duration", 0.0))
		var note_type := str(source.get("type", "")).strip_edges().to_lower()
		if note_type.is_empty():
			note_type = "hold" if length > 0.0 else "tap"
		if note_type == "hold":
			note["type"] = "hold"
			note["length"] = maxf(0.001, length)
			note["duration"] = note["length"]
		else:
			note["type"] = "tap"
		notes.append(note)
	return notes


static func _resolve_lane_count(payload: Dictionary, notes: Array[Dictionary]) -> int:
	if LaneCountResolver.has_lane_count(payload):
		return LaneCountResolver.lane_count_from_payload(payload)
	return LaneCountResolver.infer_from_notes(notes, LaneCountResolver.DEFAULT_LANES)


static func _resolve_difficulty(payload: Dictionary, source_name: String) -> String:
	var raw := str(payload.get("difficulty", "")).strip_edges().to_lower()
	if ChartValidator.SUPPORTED_DIFFICULTIES.has(raw):
		return raw
	var stem := source_name.get_file().get_basename().to_lower()
	for difficulty in ChartValidator.SUPPORTED_DIFFICULTIES:
		if stem == difficulty or stem.ends_with("_%s" % difficulty) or stem.ends_with("-%s" % difficulty) or stem.ends_with(" %s" % difficulty):
			return difficulty
	return "expert"


static func _title_from_source(source_name: String) -> String:
	var stem := source_name.get_file().get_basename()
	for difficulty in ChartValidator.SUPPORTED_DIFFICULTIES:
		for suffix in ["_%s" % difficulty, "-%s" % difficulty, " %s" % difficulty]:
			if stem.to_lower().ends_with(suffix):
				stem = stem.substr(0, stem.length() - suffix.length())
				break
	return Utils.strip_rich_text(stem.replace("_", " ").strip_edges()).capitalize()
