extends SceneTree

const ShopManager := preload("res://scripts/progression/ShopManager.gd")
const ScoreModifierRules := preload("res://scripts/gameplay/ScoreModifierRules.gd")


func _initialize() -> void:
	await process_frame
	var failures: Array[String] = []
	_check_catalog(failures)
	_check_score_multiplier(failures)
	_check_progression_resolution(failures)

	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("Speed modifier catalog smoke test passed.")
	quit(0)


func _check_catalog(failures: Array[String]) -> void:
	if not ShopManager.get_item("speed_0_8").is_empty():
		failures.append("Removed speed_0_8 is still present in the shop catalog.")
	var speed_2_0 := ShopManager.get_item("speed_2_0")
	if speed_2_0.is_empty():
		failures.append("speed_2_0 is missing from the shop catalog.")
		return
	if str(speed_2_0.get("type", "")) != "speed_modifier":
		failures.append("speed_2_0 is not typed as a speed_modifier.")
	if not is_equal_approx(float(speed_2_0.get("value", 0.0)), 2.0):
		failures.append("speed_2_0 does not use a 2.0 travel speed value.")
	if not str(speed_2_0.get("description", "")).contains("2.0x score multiplier"):
		failures.append("speed_2_0 description does not advertise its 2.0x score multiplier.")


func _check_score_multiplier(failures: Array[String]) -> void:
	_expect_score_multiplier(failures, 1.0, [], 1.0)
	_expect_score_multiplier(failures, 1.2, [], 1.2)
	_expect_score_multiplier(failures, 1.5, [], 1.5)
	_expect_score_multiplier(failures, 2.0, [], 2.0)
	_expect_score_multiplier(failures, 2.0, ["modifier_precision"], 3.0)


func _expect_score_multiplier(failures: Array[String], speed_value: float, enabled_modifiers: Array[String], expected: float) -> void:
	var actual := ScoreModifierRules.score_multiplier_for_loadout({
		"speed_value": speed_value,
		"enabled_modifiers": enabled_modifiers,
	})
	if not is_equal_approx(actual, expected):
		failures.append(
			"Expected score multiplier %.2f for speed %.1f with modifiers %s, got %.2f." %
			[expected, speed_value, str(enabled_modifiers), actual]
		)


func _check_progression_resolution(failures: Array[String]) -> void:
	var profile_store := root.get_node_or_null("ProfileStore")
	var progression_manager := root.get_node_or_null("ProgressionManager")
	if profile_store == null or progression_manager == null:
		failures.append("Progression autoloads were not available for speed modifier resolution.")
		return
	var original_progression := (profile_store.call("get_progression_data") as Dictionary).duplicate(true)

	profile_store.call("set_progression_data", _profile_with_speed("speed_2_0", ["speed_2_0"]))
	progression_manager.call("_load_or_reset")
	var equipped := progression_manager.call("get_equipped_loadout") as Dictionary
	if str(equipped.get("speed_modifier", "")) != "speed_2_0":
		failures.append("Equipped speed_2_0 did not persist through progression normalization.")
	if not is_equal_approx(float(equipped.get("speed_value", 0.0)), 2.0):
		failures.append("Progression did not resolve speed_2_0 to speed_value 2.0.")
	if not bool(equipped.get("ranked", false)):
		failures.append("speed_2_0 should remain ranked when no gameplay modifiers are enabled.")

	profile_store.call("set_progression_data", _profile_with_speed("speed_0_8", ["speed_0_8"]))
	progression_manager.call("_load_or_reset")
	equipped = progression_manager.call("get_equipped_loadout") as Dictionary
	if str(equipped.get("speed_modifier", "")) != "speed_1_0":
		failures.append("Legacy speed_0_8 equipped state did not normalize back to speed_1_0.")
	if not is_equal_approx(float(equipped.get("speed_value", 0.0)), 1.0):
		failures.append("Legacy speed_0_8 did not resolve to default speed_value 1.0.")

	profile_store.call("set_progression_data", original_progression)
	progression_manager.call("_load_or_reset")


func _profile_with_speed(speed_id: String, extra_owned: Array[String]) -> Dictionary:
	var owned: Array[String] = ["theme_default", "effect_none", "speed_1_0"]
	for item_id in extra_owned:
		if not owned.has(item_id):
			owned.append(item_id)
	return {
		"schema_version": 1,
		"level": 9,
		"xp": 0,
		"currency": 0,
		"unlocked_songs": [],
		"completed_songs": {},
		"unlocked_sections": 1,
		"owned_items": owned,
		"equipped_items": {
			"theme": "theme_default",
			"effect": "effect_none",
			"ems_loadout": "ems_harmonic_core",
			"speed_modifier": speed_id,
			"enabled_modifiers": [],
		},
	}
