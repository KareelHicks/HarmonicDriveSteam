extends RefCounted
class_name ChartLoader

const ChartValidator := preload("res://scripts/songs/ChartValidator.gd")
const LaneCountResolver := preload("res://scripts/songs/LaneCountResolver.gd")


static func load_chart(chart_path: String) -> Dictionary:
	if chart_path.is_empty() or not FileAccess.file_exists(chart_path):
		return {}
	var file := FileAccess.open(chart_path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var chart: Dictionary = parsed
	chart = LaneCountResolver.normalize_chart_lane_count(chart)
	# Authored note timings are treated as canonical. Ignore legacy offset metadata.
	chart["audioOffset"] = 0.0
	chart["audio_offset"] = 0.0
	chart.erase("offsetConfidence")
	chart.erase("offsetMethod")
	var notes: Variant = chart.get("notes", [])
	if notes is Array:
		var note_array: Array = notes
		var synthesized_ids := false
		# Normalize notes for gameplay runtime (some editor/import paths omit these fields).
		for i in range(note_array.size()):
			if note_array[i] is not Dictionary:
				continue
			var note: Dictionary = note_array[i]
			# Lane coercion
			if note.has("lane"):
				var lane_v: Variant = note.get("lane", 0)
				if typeof(lane_v) == TYPE_FLOAT:
					var lf := float(lane_v)
					if is_equal_approx(lf, roundf(lf)):
						note["lane"] = int(roundf(lf))
			# duration/length compatibility
			if note.has("length") and not note.has("duration"):
				note["duration"] = note.get("length", 0.0)
			# type defaulting
			if not note.has("type"):
				var dur := 0.0
				if note.has("duration"):
					dur = float(note.get("duration", 0.0))
				elif note.has("length"):
					dur = float(note.get("length", 0.0))
				note["type"] = "hold" if dur > 0.0 else "tap"
			# id synthesis (assigned after sort for determinism)
			if not note.has("id"):
				synthesized_ids = true
			note_array[i] = note

		# Deterministic ordering.
		note_array.sort_custom(func(a: Variant, b: Variant) -> bool:
			var ad: Dictionary = a as Dictionary if a is Dictionary else {}
			var bd: Dictionary = b as Dictionary if b is Dictionary else {}
			var ta := float(ad.get("time", 0.0))
			var tb := float(bd.get("time", 0.0))
			if ta == tb:
				var la := int(ad.get("lane", 0))
				var lb := int(bd.get("lane", 0))
				if la == lb:
					return str(ad.get("type", "")).to_lower() < str(bd.get("type", "")).to_lower()
				return la < lb
			return ta < tb
		)

		if synthesized_ids:
			for i in range(note_array.size()):
				if note_array[i] is Dictionary:
					var note: Dictionary = note_array[i]
					if not note.has("id"):
						note["id"] = i
						note_array[i] = note
			push_warning("ChartLoader: synthesized missing note ids for %s" % chart_path)

		chart["notes"] = note_array
	return chart


static func load_json_dictionary(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {"ok": false, "value": {}, "error": "File not found: %s" % path}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "value": {}, "error": "Failed to open file: %s" % path}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "value": {}, "error": "Expected JSON object at %s" % path}
	return {"ok": true, "value": parsed as Dictionary, "error": ""}


static func load_hd_chart(chart_path: String, expected_difficulty: String = "") -> Dictionary:
	var loaded := load_json_dictionary(chart_path)
	if not loaded.get("ok", false):
		return {
			"ok": false,
			"chart": {},
			"errors": [{"code": "chart_parse_error", "message": str(loaded.get("error", "Failed to parse chart")), "path": chart_path}],
			"warnings": [],
		}

	var chart: Dictionary = loaded.get("value", {}) as Dictionary
	var normalized := _normalize_hd_chart(chart, expected_difficulty)
	chart = normalized.get("chart", chart) as Dictionary
	var pre_warnings: Array = normalized.get("warnings", []) as Array
	var validation := ChartValidator.validate_chart(chart, expected_difficulty)

	var notes_var: Variant = chart.get("notes", [])
	if notes_var is Array:
		var notes: Array = notes_var
		notes.sort_custom(func(a: Variant, b: Variant) -> bool:
			var ta := 0.0
			var tb := 0.0
			if a is Dictionary:
				ta = float((a as Dictionary).get("time", 0.0))
			if b is Dictionary:
				tb = float((b as Dictionary).get("time", 0.0))
			return ta < tb
		)

	return {
		"ok": ChartValidator.is_valid(validation),
		"chart": chart,
		"errors": validation.get("errors", []) as Array,
		"warnings": pre_warnings + (validation.get("warnings", []) as Array),
	}


static func _normalize_hd_chart(chart: Dictionary, expected_difficulty: String) -> Dictionary:
	var warnings: Array[Dictionary] = []

	# version: allow missing or numeric strings for editor-friendliness and backwards compat.
	if not chart.has("version"):
		chart["version"] = 1
		warnings.append({"code": "missing_version_defaulted", "message": "Chart missing version; defaulted to 1", "path": "/version"})
	else:
		var v: Variant = chart.get("version", 1)
		if typeof(v) == TYPE_FLOAT:
			var fv := float(v)
			if is_equal_approx(fv, roundf(fv)):
				chart["version"] = int(roundf(fv))
				warnings.append({"code": "version_coerced", "message": "Chart version coerced from float to int", "path": "/version"})
		elif typeof(v) == TYPE_STRING:
			var s := String(v).strip_edges()
			if s.is_valid_int():
				chart["version"] = int(s)
				warnings.append({"code": "version_coerced", "message": "Chart version coerced from string to int", "path": "/version"})

	# difficulty: allow missing by defaulting to expected (if provided).
	if not chart.has("difficulty") and not expected_difficulty.is_empty():
		chart["difficulty"] = expected_difficulty
		warnings.append({"code": "missing_difficulty_defaulted", "message": "Chart missing difficulty; defaulted from selection", "path": "/difficulty"})

	if not LaneCountResolver.has_lane_count(chart):
		warnings.append({"code": "missing_lane_count_defaulted", "message": "Chart missing lane_count; inferred/defaulted from notes", "path": "/lane_count"})
	chart = LaneCountResolver.normalize_chart_lane_count(chart)

	# notes normalization (optional): accept legacy duration/typed notes for editor loading.
	var notes_var: Variant = chart.get("notes", null)
	if notes_var is Array:
		var notes: Array = notes_var
		for i in range(notes.size()):
			if notes[i] is Dictionary:
				var note: Dictionary = notes[i]
				if note.has("lane"):
					var lane_v: Variant = note.get("lane", 0)
					if typeof(lane_v) == TYPE_FLOAT:
						var lf := float(lane_v)
						if is_equal_approx(lf, roundf(lf)):
							note["lane"] = int(roundf(lf))
							warnings.append({"code": "lane_coerced", "message": "Note lane coerced from float to int", "path": "/notes/%d/lane" % i})
				if not note.has("type"):
					if note.has("duration") or note.has("length"):
						note["type"] = "hold"
						warnings.append({"code": "note_type_defaulted", "message": "Note missing type; defaulted to hold", "path": "/notes/%d/type" % i})
					else:
						note["type"] = "tap"
						warnings.append({"code": "note_type_defaulted", "message": "Note missing type; defaulted to tap", "path": "/notes/%d/type" % i})
				if note.has("duration") and not note.has("length"):
					note["length"] = note.get("duration", 0.0)
					warnings.append({"code": "hold_duration_mapped", "message": "Hold note duration mapped to length", "path": "/notes/%d/length" % i})
				notes[i] = note
		chart["notes"] = notes

	return {"chart": chart, "warnings": warnings}
