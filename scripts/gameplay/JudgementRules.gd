extends RefCounted
class_name JudgementRules

const BASE_WINDOWS := {
	"Perfect": 0.030,
	"Great": 0.045,
	"Good": 0.060,
}

const BASE_POINTS := {
	"Perfect": 100,
	"Great": 75,
	"Good": 50,
	"Miss": 0,
}

const HOLD_TICK_POINTS := 5
const HOLD_SUCCESS_POINTS := 50
const GLOBAL_HIT_WINDOW_SCALE := 1.05

const DIFFICULTY_SCALES := {
	"Easy": 1.6,
	"Medium": 1.35,
	"Hard": 1.15,
	"Expert": 1.0,
	"Professional": 0.85,
}

const WINDOW_TUNING := {
	"Easy": {"Perfect": 1.05, "Great": 1.06, "Good": 1.08},
	"Medium": {"Perfect": 1.05, "Great": 1.06, "Good": 1.08},
	"Hard": {"Perfect": 1.04, "Great": 1.05, "Good": 1.07},
	"Expert": {"Perfect": 1.03, "Great": 1.04, "Good": 1.06},
	"Professional": {"Perfect": 1.0, "Great": 1.0, "Good": 1.18},
}

const GOOD_EDGE_PROFILE := {
	"Easy": {"early": 1.18, "late": 1.08},
	"Medium": {"early": 1.18, "late": 1.08},
	"Hard": {"early": 1.16, "late": 1.07},
	"Expert": {"early": 1.14, "late": 1.06},
	"Professional": {"early": 1.12, "late": 1.10},
}

static func judge_delta(delta: float, difficulty: String = "Medium", window_scale: float = 1.0) -> String:
	var abs_delta := absf(delta)
	var perfect_window: float = window_for("Perfect", difficulty, window_scale)
	var great_window: float = window_for("Great", difficulty, window_scale)
	var good_window: float = good_window_for_delta(delta, difficulty, window_scale)
	if abs_delta <= perfect_window:
		return "Perfect"
	if abs_delta <= great_window:
		return "Great"
	if abs_delta <= good_window:
		return "Good"
	return "Miss"


static func max_window(difficulty: String = "Medium", window_scale: float = 1.0) -> float:
	return late_window_for("Good", difficulty, window_scale)


static func window_for(judgement: String, difficulty: String = "Medium", window_scale: float = 1.0) -> float:
	var scale: float = float(DIFFICULTY_SCALES.get(difficulty, DIFFICULTY_SCALES["Medium"]))
	var tuning_by_difficulty: Dictionary = WINDOW_TUNING.get(difficulty, WINDOW_TUNING["Medium"])
	var tuning: float = float(tuning_by_difficulty.get(judgement, 1.0))
	return float(BASE_WINDOWS.get(judgement, BASE_WINDOWS["Good"])) * scale * tuning * GLOBAL_HIT_WINDOW_SCALE * window_scale


static func early_window_for(judgement: String, difficulty: String = "Medium", window_scale: float = 1.0) -> float:
	var window := window_for(judgement, difficulty, window_scale)
	if judgement != "Good":
		return window
	var profile: Dictionary = GOOD_EDGE_PROFILE.get(difficulty, GOOD_EDGE_PROFILE["Medium"])
	return window * float(profile.get("early", 1.0))


static func late_window_for(judgement: String, difficulty: String = "Medium", window_scale: float = 1.0) -> float:
	var window := window_for(judgement, difficulty, window_scale)
	if judgement != "Good":
		return window
	var profile: Dictionary = GOOD_EDGE_PROFILE.get(difficulty, GOOD_EDGE_PROFILE["Medium"])
	return window * float(profile.get("late", 1.0))


static func good_window_for_delta(delta: float, difficulty: String = "Medium", window_scale: float = 1.0) -> float:
	if delta < 0.0:
		return early_window_for("Good", difficulty, window_scale)
	return late_window_for("Good", difficulty, window_scale)


static func combo_multiplier(combo: int) -> int:
	if combo < 10:
		return 1
	if combo < 25:
		return 2
	if combo < 50:
		return 4
	return 8


static func score_for(judgement: String, combo: int) -> int:
	var base_points: int = int(BASE_POINTS.get(judgement, 0))
	return base_points * combo_multiplier(combo)


static func hold_tick_score(combo: int) -> int:
	return HOLD_TICK_POINTS * combo_multiplier(combo)


static func hold_success_score(combo: int) -> int:
	return HOLD_SUCCESS_POINTS * combo_multiplier(combo)
