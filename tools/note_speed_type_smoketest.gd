extends SceneTree

const NoteSpeedRules = preload("res://scripts/gameplay/NoteSpeedRules.gd")


func _initialize() -> void:
	await process_frame
	var failures: Array[String] = []
	var profile := root.get_node_or_null("ProfileStore")
	if profile == null:
		failures.append("ProfileStore autoload was not found.")
		_finish(failures, null, "", 600.0)
		return

	var original_speed_type := str(profile.call("get_note_speed_type"))
	var original_approach_ms := float(profile.call("get_note_approach_time_ms"))
	_assert_profile_defaults(failures)
	_assert_xcode_formula_parity(failures)
	_assert_game_scene_uses_profile_mode(profile, failures)
	if load("res://scenes/editor/ChartEditorScene.gd") == null:
		failures.append("ChartEditorScene failed to compile with Note Speed Type preview support.")
	await _assert_settings_menu(profile, failures)
	_finish(failures, profile, original_speed_type, original_approach_ms)


func _assert_profile_defaults(failures: Array[String]) -> void:
	var profile_script := load("res://autoload/ProfileStore.gd") as Script
	var fresh_profile: Node = profile_script.new()
	if str(fresh_profile.call("get_note_speed_type")) != "classic":
		failures.append("A fresh profile should default Note Speed Type to Classic.")
	var recommended := fresh_profile.call("_recommended_settings_defaults") as Dictionary
	if str(recommended.get("note_speed_type", "")) != "classic":
		failures.append("Recommended settings should reset Note Speed Type to Classic.")
	fresh_profile.free()


func _assert_xcode_formula_parity(failures: Array[String]) -> void:
	var expected_classic := {
		"Easy": 2.0,
		"Medium": 2.0 / 1.08,
		"Hard": 2.0 / 1.83,
		"Expert": 2.0 / 2.07,
		"Professional": 2.0 / 2.37,
	}
	for difficulty in expected_classic.keys():
		var actual := NoteSpeedRules.resolved_approach_time("classic", 600.0, 1.0, difficulty)
		_expect_close(actual, float(expected_classic[difficulty]), "Classic %s duration" % difficulty, failures)
		var ignored_approach := NoteSpeedRules.resolved_approach_time("classic", 2000.0, 1.0, difficulty)
		_expect_close(ignored_approach, actual, "Classic %s ignores Note Approach Time" % difficulty, failures)

	for difficulty in expected_classic.keys():
		var modern := NoteSpeedRules.resolved_approach_time("modern", 600.0, 1.0, difficulty)
		_expect_close(modern, 0.6, "Modern %s preserves Godot approach time" % difficulty, failures)
	var modern_with_loadout := NoteSpeedRules.resolved_approach_time("modern", 900.0, 1.5, "Professional")
	_expect_close(modern_with_loadout, 0.6, "Modern loadout scaling", failures)


func _assert_game_scene_uses_profile_mode(profile: Node, failures: Array[String]) -> void:
	var game_script := load("res://scenes/gameplay/GameScene.gd") as Script
	if game_script == null:
		failures.append("GameScene script could not be loaded.")
		return
	var game: Node = game_script.new()
	game.set("_difficulty", "Professional")
	game.set("_loadout", {"speed_value": 1.0})
	profile.call("set_note_approach_time_ms", 600.0)
	profile.call("set_note_speed_type", "classic")
	_expect_close(float(game.call("_approach_time")), 2.0 / 2.37, "GameScene Classic runtime duration", failures)
	profile.call("set_note_speed_type", "modern")
	_expect_close(float(game.call("_approach_time")), 0.6, "GameScene Modern runtime duration", failures)
	game.free()


func _assert_settings_menu(profile: Node, failures: Array[String]) -> void:
	profile.call("set_note_speed_type", "classic")
	var packed := load("res://scenes/menus/SettingsMenu.tscn") as PackedScene
	if packed == null:
		failures.append("SettingsMenu scene could not be loaded.")
		return
	var menu := packed.instantiate()
	root.add_child(menu)
	await process_frame

	var dropdown := menu.find_child("NoteSpeedTypeOptionButton", true, false) as OptionButton
	var approach_row := menu.find_child("ScrollSpeedRow", true, false) as Control
	var approach_slider := menu.find_child("ScrollSpeedSlider", true, false) as Control
	if dropdown == null:
		failures.append("Note Speed Type dropdown was not found in Gameplay settings.")
	elif dropdown.item_count != 2:
		failures.append("Note Speed Type dropdown should expose exactly two choices.")
	else:
		if dropdown.get_item_text(0) != "Classic" or dropdown.get_item_text(1) != "Modern":
			failures.append("Note Speed Type choices should be Classic followed by Modern.")
		if dropdown.selected != 0:
			failures.append("Classic profile mode was not selected in the dropdown.")
	if approach_row == null or approach_slider == null:
		failures.append("Note Approach Time controls were not found.")
	elif approach_row.visible or approach_slider.visible:
		failures.append("Classic mode should hide Note Approach Time controls.")

	if dropdown != null:
		dropdown.select(1)
		dropdown.item_selected.emit(1)
		if approach_row != null and not approach_row.visible:
			failures.append("Modern mode should show the Note Approach Time row.")
		if approach_slider != null and not approach_slider.visible:
			failures.append("Modern mode should show the Note Approach Time slider.")
		menu.call("_on_save_button_pressed")
		if str(profile.call("get_note_speed_type")) != "modern":
			failures.append("Saving Settings did not persist Modern Note Speed Type.")
		dropdown.select(0)
		dropdown.item_selected.emit(0)
		menu.call("_on_save_button_pressed")
		if str(profile.call("get_note_speed_type")) != "classic":
			failures.append("Saving Settings did not persist Classic Note Speed Type.")
		if approach_row != null and approach_row.visible:
			failures.append("Switching back to Classic should hide Note Approach Time immediately.")

	menu.queue_free()
	await process_frame


func _expect_close(actual: float, expected: float, label: String, failures: Array[String]) -> void:
	if not is_equal_approx(actual, expected):
		failures.append("%s expected %.9f, got %.9f." % [label, expected, actual])


func _finish(
		failures: Array[String],
		profile: Node,
		original_speed_type: String,
		original_approach_ms: float
) -> void:
	if profile != null:
		profile.call("set_note_approach_time_ms", original_approach_ms)
		profile.call("set_note_speed_type", original_speed_type)
	if failures.is_empty():
		print("NOTE_SPEED_TYPE_SMOKETEST_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
