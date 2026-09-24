extends RefCounted
class_name NoteSpeedRules

const CLASSIC_BASE_APPROACH_SECONDS := 2.0
const MIN_SPEED_VALUE := 0.1
const MODERN_MIN_APPROACH_MS := 250.0
const MODERN_MAX_APPROACH_MS := 2000.0
const DIFFICULTY_SCROLL_MULTIPLIERS := {
	"Easy": 1.0,
	"Medium": 1.08,
	"Hard": 1.83,
	"Expert": 2.07,
	"Professional": 2.37,
}


static func resolved_approach_time(
		speed_type: String,
		approach_milliseconds: float,
		loadout_speed: float,
		difficulty: String
) -> float:
	if speed_type.strip_edges().to_lower() == "classic":
		var normalized_difficulty := difficulty.strip_edges().capitalize()
		var difficulty_speed: float = float(DIFFICULTY_SCROLL_MULTIPLIERS.get(normalized_difficulty, 1.0))
		return CLASSIC_BASE_APPROACH_SECONDS / maxf(MIN_SPEED_VALUE, loadout_speed * difficulty_speed)
	var modern_base_seconds := clampf(approach_milliseconds, MODERN_MIN_APPROACH_MS, MODERN_MAX_APPROACH_MS) / 1000.0
	return modern_base_seconds / maxf(MIN_SPEED_VALUE, loadout_speed)
