extends RefCounted
class_name ScoreModifierRules


static func score_multiplier_for_loadout(loadout: Dictionary) -> float:
	var mult := 1.0
	var enabled: Array = loadout.get("enabled_modifiers", []) as Array
	# Precision mode: permanent leaderboard-intended multiplier.
	if enabled.has("modifier_precision"):
		mult *= 1.5
	# Speed bonuses apply to faster-than-default travel speeds.
	var speed_value: float = float(loadout.get("speed_value", 1.0))
	if speed_value > 1.0 and not is_equal_approx(speed_value, 1.0):
		mult *= speed_value
	return mult
