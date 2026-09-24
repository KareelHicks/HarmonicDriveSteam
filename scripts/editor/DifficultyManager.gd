extends RefCounted
class_name DifficultyManager

const IDS: Array[String] = ["easy", "medium", "hard", "expert", "professional"]
const DISPLAY: Array[String] = ["Easy", "Medium", "Hard", "Expert", "Professional"]


static func all_ids() -> Array[String]:
	return IDS.duplicate()


static func all_display_names() -> Array[String]:
	return DISPLAY.duplicate()


static func is_valid_id(id: String) -> bool:
	return IDS.has(id.strip_edges().to_lower())


static func display_name(id: String) -> String:
	var normalized := id.strip_edges().to_lower()
	var idx := IDS.find(normalized)
	if idx < 0:
		return id
	return DISPLAY[idx]


static func id_from_display(display_name: String) -> String:
	var normalized := display_name.strip_edges()
	var idx := DISPLAY.find(normalized)
	if idx < 0:
		return normalized.to_lower()
	return IDS[idx]

