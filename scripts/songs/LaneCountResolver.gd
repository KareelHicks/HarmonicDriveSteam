extends RefCounted
class_name LaneCountResolver

const MIN_LANES := 3
const MAX_LANES := 8
const DEFAULT_LANES := 5


static func clamp_lane_count(value: int) -> int:
	return clampi(value, MIN_LANES, MAX_LANES)


static func has_lane_count(payload: Dictionary) -> bool:
	return payload.has("lane_count") or payload.has("laneCount")


static func lane_count_from_payload(payload: Dictionary, fallback: int = DEFAULT_LANES) -> int:
	var raw: Variant = payload.get("lane_count", payload.get("laneCount", fallback))
	if typeof(raw) == TYPE_INT or typeof(raw) == TYPE_FLOAT:
		return clamp_lane_count(int(roundf(float(raw))))
	if typeof(raw) == TYPE_STRING:
		var text := String(raw).strip_edges()
		if text.is_valid_int():
			return clamp_lane_count(int(text))
	return clamp_lane_count(fallback)


static func infer_from_notes(notes: Array, fallback: int = DEFAULT_LANES) -> int:
	var max_lane := -1
	for note_var in notes:
		if note_var is not Dictionary:
			continue
		var note: Dictionary = note_var
		if not note.has("lane"):
			continue
		max_lane = maxi(max_lane, int(roundf(float(note.get("lane", 0)))))
	if max_lane < 0:
		return clamp_lane_count(fallback)
	return clamp_lane_count(max_lane + 1)


static func resolve_chart_lane_count(chart: Dictionary, manifest: Dictionary = {}) -> int:
	if has_lane_count(chart):
		return lane_count_from_payload(chart)
	if has_lane_count(manifest):
		return lane_count_from_payload(manifest)
	var notes_var: Variant = chart.get("notes", [])
	if notes_var is Array:
		return infer_from_notes(notes_var as Array, DEFAULT_LANES)
	return DEFAULT_LANES


static func normalize_chart_lane_count(chart: Dictionary, manifest: Dictionary = {}) -> Dictionary:
	chart["lane_count"] = resolve_chart_lane_count(chart, manifest)
	chart.erase("laneCount")
	return chart
