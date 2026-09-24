extends RefCounted
class_name GameModeConfig

const SYNTHESIZED := "synthesized"
const STEMS_RANDOM := "stems_random"
const STEMS_MAPPED := "stems_mapped"

const ORDER := [
	STEMS_MAPPED,
	STEMS_RANDOM,
	SYNTHESIZED,
]

const DEFAULT_MODE := STEMS_MAPPED
const REQUIRED_LEVELS := {
	STEMS_MAPPED: 1,
	STEMS_RANDOM: 4,
	SYNTHESIZED: 7,
}

const DEFINITIONS := {
	SYNTHESIZED: {
		"id": SYNTHESIZED,
		"display_name": "Remix Difficulty",
		"short_label": "Remix",
		"chart_suffix": " [Synth]",
		"chart_folder": "charts",
	},
	STEMS_RANDOM: {
		"id": STEMS_RANDOM,
		"display_name": "Lane Shuffle",
		"short_label": "Shuffle",
		"chart_suffix": " [Random]",
		"chart_folder": "stem_charts_randomized",
	},
	STEMS_MAPPED: {
		"id": STEMS_MAPPED,
		"display_name": "Classic",
		"short_label": "Classic",
		"chart_suffix": " [Mapped]",
		"chart_folder": "stem_charts_mapped",
	},
}


static func get_definition(mode_id: String) -> Dictionary:
	return (DEFINITIONS.get(mode_id, DEFINITIONS[DEFAULT_MODE]) as Dictionary).duplicate(true)


static func get_display_name(mode_id: String) -> String:
	return str(get_definition(mode_id).get("display_name", "Classic"))


static func get_short_label(mode_id: String) -> String:
	return str(get_definition(mode_id).get("short_label", "Classic"))


static func get_chart_source_mode(mode_id: String) -> String:
	return str(get_definition(mode_id).get("chart_source_mode", mode_id))


static func is_valid(mode_id: String) -> bool:
	return DEFINITIONS.has(mode_id)


static func get_required_level(mode_id: String) -> int:
	return int(REQUIRED_LEVELS.get(mode_id, 1))


static func is_unlocked_for_level(mode_id: String, level: int) -> bool:
	return level >= get_required_level(mode_id)
