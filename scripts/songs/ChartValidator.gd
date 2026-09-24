extends RefCounted
class_name ChartValidator

const LaneCountResolver := preload("res://scripts/songs/LaneCountResolver.gd")

const SUPPORTED_CHART_VERSIONS: Array[int] = [1]
const SUPPORTED_DIFFICULTIES: Array[String] = ["easy", "medium", "hard", "expert", "professional"]
const SUPPORTED_NOTE_TYPES: Array[String] = ["tap", "hold"]


static func is_valid(result: Dictionary) -> bool:
	return (result.get("errors", []) as Array).is_empty()


static func validate_manifest(manifest: Dictionary) -> Dictionary:
	var errors: Array[Dictionary] = []
	var warnings: Array[Dictionary] = []

	_require_string(manifest, "song_id", "/song_id", errors)
	_require_string(manifest, "title", "/title", errors)
	_require_string(manifest, "artist", "/artist", errors)
	_require_string(manifest, "charter", "/charter", errors)
	_require_number(manifest, "bpm", "/bpm", errors)
	_require_number(manifest, "offset", "/offset", errors)
	if manifest.has("youtube_url") and typeof(manifest.get("youtube_url", "")) != TYPE_STRING:
		errors.append(_issue("invalid_type", "Field youtube_url must be a string", "/youtube_url"))

	var difficulties_var: Variant = manifest.get("difficulties", null)
	if difficulties_var == null:
		errors.append(_issue("missing_field", "Missing required field: difficulties", "/difficulties"))
	elif difficulties_var is Array:
		var difficulties: Array = difficulties_var
		if difficulties.is_empty():
			warnings.append(_issue("empty_difficulties", "No difficulties declared in manifest", "/difficulties"))
		for i in range(difficulties.size()):
			var raw: Variant = difficulties[i]
			if typeof(raw) != TYPE_STRING:
				errors.append(_issue("invalid_difficulty", "Difficulty must be a string", "/difficulties/%d" % i))
				continue
			var diff: String = String(raw).strip_edges().to_lower()
			if diff.is_empty():
				errors.append(_issue("invalid_difficulty", "Difficulty must not be empty", "/difficulties/%d" % i))
				continue
			if not SUPPORTED_DIFFICULTIES.has(diff):
				warnings.append(_issue(
					"unknown_difficulty",
					"Unknown difficulty '%s' (supported: %s)" % [diff, ", ".join(SUPPORTED_DIFFICULTIES)],
					"/difficulties/%d" % i
				))
	else:
		errors.append(_issue("invalid_type", "Field difficulties must be an array", "/difficulties"))

	return {"errors": errors, "warnings": warnings}


static func validate_chart(chart: Dictionary, expected_difficulty: String = "") -> Dictionary:
	var errors: Array[Dictionary] = []
	var warnings: Array[Dictionary] = []

	var version_var: Variant = chart.get("version", null)
	if version_var == null:
		errors.append(_issue("missing_field", "Missing required field: version", "/version"))
	elif typeof(version_var) != TYPE_INT:
		errors.append(_issue("invalid_type", "Field version must be an integer", "/version"))
	else:
		var version: int = int(version_var)
		if not SUPPORTED_CHART_VERSIONS.has(version):
			var supported_versions: Array[String] = []
			for v in SUPPORTED_CHART_VERSIONS:
				supported_versions.append(str(v))
			errors.append(_issue(
				"unsupported_version",
				"Unsupported chart version %d (supported: %s)" % [version, ", ".join(supported_versions)],
				"/version"
			))

	var difficulty_var: Variant = chart.get("difficulty", null)
	if difficulty_var == null:
		errors.append(_issue("missing_field", "Missing required field: difficulty", "/difficulty"))
	elif typeof(difficulty_var) != TYPE_STRING:
		errors.append(_issue("invalid_type", "Field difficulty must be a string", "/difficulty"))
	else:
		var difficulty: String = String(difficulty_var).strip_edges().to_lower()
		if difficulty.is_empty():
			errors.append(_issue("invalid_difficulty", "Difficulty must not be empty", "/difficulty"))
		elif not SUPPORTED_DIFFICULTIES.has(difficulty):
			warnings.append(_issue(
				"unknown_difficulty",
				"Unknown difficulty '%s' (supported: %s)" % [difficulty, ", ".join(SUPPORTED_DIFFICULTIES)],
				"/difficulty"
			))
		if not expected_difficulty.is_empty() and difficulty != expected_difficulty.strip_edges().to_lower():
			warnings.append(_issue(
				"difficulty_mismatch",
				"Chart difficulty '%s' does not match expected '%s'" % [difficulty, expected_difficulty],
				"/difficulty"
			))

	var lane_count := LaneCountResolver.DEFAULT_LANES
	var lane_count_var: Variant = chart.get("lane_count", null)
	if lane_count_var == null:
		warnings.append(_issue("missing_lane_count", "Missing lane_count; using compatibility lane count", "/lane_count"))
	else:
		var lane_count_is_int := typeof(lane_count_var) == TYPE_INT
		if typeof(lane_count_var) == TYPE_FLOAT:
			var lcf := float(lane_count_var)
			lane_count_is_int = is_equal_approx(lcf, roundf(lcf))
		if not lane_count_is_int:
			errors.append(_issue("invalid_type", "Field lane_count must be an integer", "/lane_count"))
		else:
			lane_count = int(roundf(float(lane_count_var)))
			if lane_count < LaneCountResolver.MIN_LANES or lane_count > LaneCountResolver.MAX_LANES:
				errors.append(_issue(
					"invalid_lane_count",
					"lane_count must be between %d and %d" % [LaneCountResolver.MIN_LANES, LaneCountResolver.MAX_LANES],
					"/lane_count"
				))

	var notes_var: Variant = chart.get("notes", null)
	if notes_var == null:
		errors.append(_issue("missing_field", "Missing required field: notes", "/notes"))
	elif notes_var is Array:
		var notes: Array = notes_var
		for i in range(notes.size()):
			var note_var: Variant = notes[i]
			if typeof(note_var) != TYPE_DICTIONARY:
				errors.append(_issue("invalid_note", "Note must be an object", "/notes/%d" % i))
				continue
			_validate_note(note_var as Dictionary, i, lane_count, errors, warnings)
	else:
		errors.append(_issue("invalid_type", "Field notes must be an array", "/notes"))

	return {"errors": errors, "warnings": warnings}


static func _validate_note(note: Dictionary, index: int, lane_count: int, errors: Array[Dictionary], warnings: Array[Dictionary]) -> void:
	var prefix := "/notes/%d" % index

	var time_var: Variant = note.get("time", null)
	if time_var == null:
		errors.append(_issue("missing_field", "Missing required field: time", "%s/time" % prefix))
	elif typeof(time_var) != TYPE_FLOAT and typeof(time_var) != TYPE_INT:
		errors.append(_issue("invalid_type", "Field time must be a number", "%s/time" % prefix))
	else:
		var time_val: float = float(time_var)
		if time_val < 0.0:
			errors.append(_issue("invalid_time", "Note time must be >= 0", "%s/time" % prefix))

	var lane_var: Variant = note.get("lane", null)
	if lane_var == null:
		errors.append(_issue("missing_field", "Missing required field: lane", "%s/lane" % prefix))
	else:
		var lane_is_int := typeof(lane_var) == TYPE_INT
		if typeof(lane_var) == TYPE_FLOAT:
			var f := float(lane_var)
			lane_is_int = is_equal_approx(f, roundf(f))
		if not lane_is_int:
			errors.append(_issue("invalid_type", "Field lane must be an integer", "%s/lane" % prefix))
			return
		var lane_val: int = int(roundf(float(lane_var)))
		if lane_val < 0:
			errors.append(_issue("invalid_lane", "Lane must be >= 0", "%s/lane" % prefix))
		elif lane_val >= lane_count:
			errors.append(_issue("lane_out_of_range", "Lane %d exceeds chart lane range 0-%d" % [lane_val, lane_count - 1], "%s/lane" % prefix))

	var type_var: Variant = note.get("type", null)
	if type_var == null:
		errors.append(_issue("missing_field", "Missing required field: type", "%s/type" % prefix))
	elif typeof(type_var) != TYPE_STRING:
		errors.append(_issue("invalid_type", "Field type must be a string", "%s/type" % prefix))
	else:
		var note_type: String = String(type_var).strip_edges().to_lower()
		if not SUPPORTED_NOTE_TYPES.has(note_type):
			errors.append(_issue(
				"unsupported_note_type",
				"Unsupported note type '%s' (supported: %s)" % [note_type, ", ".join(SUPPORTED_NOTE_TYPES)],
				"%s/type" % prefix
			))
		elif note_type == "hold":
			var length_var: Variant = note.get("length", null)
			if length_var == null:
				errors.append(_issue("missing_field", "Hold notes require field: length", "%s/length" % prefix))
			elif typeof(length_var) != TYPE_FLOAT and typeof(length_var) != TYPE_INT:
				errors.append(_issue("invalid_type", "Field length must be a number", "%s/length" % prefix))
			else:
				var length_val: float = float(length_var)
				if length_val <= 0.0:
					errors.append(_issue("invalid_length", "Hold note length must be > 0", "%s/length" % prefix))


static func _require_string(payload: Dictionary, key: String, path: String, errors: Array[Dictionary]) -> void:
	var value: Variant = payload.get(key, null)
	if value == null:
		errors.append(_issue("missing_field", "Missing required field: %s" % key, path))
		return
	if typeof(value) != TYPE_STRING:
		errors.append(_issue("invalid_type", "Field %s must be a string" % key, path))
		return
	if String(value).strip_edges().is_empty():
		errors.append(_issue("invalid_value", "Field %s must not be empty" % key, path))


static func _require_number(payload: Dictionary, key: String, path: String, errors: Array[Dictionary]) -> void:
	var value: Variant = payload.get(key, null)
	if value == null:
		errors.append(_issue("missing_field", "Missing required field: %s" % key, path))
		return
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		errors.append(_issue("invalid_type", "Field %s must be a number" % key, path))


static func _issue(code: String, message: String, path: String) -> Dictionary:
	return {"code": code, "message": message, "path": path}
