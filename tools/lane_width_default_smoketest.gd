extends SceneTree

const EXPECTED_LANE_WIDTH_SCALE := 0.4


func _initialize() -> void:
	await process_frame
	var failures: Array[String] = []
	var profile := root.get_node_or_null("ProfileStore")
	if profile == null:
		failures.append("ProfileStore autoload was not found.")
	else:
		_expect_close(
			float(profile.call("get_lane_width_scale")),
			EXPECTED_LANE_WIDTH_SCALE,
			"Brand-new saved profile Lane Width",
			failures
		)

	_assert_fresh_profile_defaults(failures)
	await _assert_settings_menu_defaults(failures)

	if failures.is_empty():
		print("LANE_WIDTH_DEFAULT_SMOKETEST_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _assert_fresh_profile_defaults(failures: Array[String]) -> void:
	var profile_script := load("res://autoload/ProfileStore.gd") as Script
	var fresh_profile: Node = profile_script.new()
	_expect_close(
		float(fresh_profile.call("get_lane_width_scale")),
		EXPECTED_LANE_WIDTH_SCALE,
		"In-memory fresh profile Lane Width",
		failures
	)
	var recommended := fresh_profile.call("_recommended_settings_defaults") as Dictionary
	_expect_close(
		float(recommended.get("lane_width_scale", -1.0)),
		EXPECTED_LANE_WIDTH_SCALE,
		"Recommended reset Lane Width",
		failures
	)
	fresh_profile.free()


func _assert_settings_menu_defaults(failures: Array[String]) -> void:
	var packed := load("res://scenes/menus/SettingsMenu.tscn") as PackedScene
	if packed == null:
		failures.append("SettingsMenu scene could not be loaded.")
		return
	var menu := packed.instantiate()
	var slider := menu.find_child("LaneWidthSlider", true, false) as HSlider
	var value_label := menu.find_child("LaneWidthValueLabel", true, false) as Label
	if slider == null or value_label == null:
		failures.append("Lane Width controls were not found in SettingsMenu.")
		menu.free()
		return
	_expect_close(slider.value, EXPECTED_LANE_WIDTH_SCALE, "Settings scene Lane Width", failures)
	if value_label.text != "40%":
		failures.append("Settings scene Lane Width label should initialize to 40%.")

	root.add_child(menu)
	await process_frame
	_expect_close(slider.value, EXPECTED_LANE_WIDTH_SCALE, "Ready Settings menu Lane Width", failures)
	if value_label.text != "40%":
		failures.append("Ready Settings menu Lane Width label should show 40%.")
	menu.queue_free()
	await process_frame


func _expect_close(actual: float, expected: float, label: String, failures: Array[String]) -> void:
	if not is_equal_approx(actual, expected):
		failures.append("%s expected %.2f, got %.2f." % [label, expected, actual])
