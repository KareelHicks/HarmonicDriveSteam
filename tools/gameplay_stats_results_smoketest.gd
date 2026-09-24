extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	var profile_store := root.get_node("ProfileStore")
	var app_state := root.get_node("AppState")
	var original_stats: Dictionary = (profile_store.call("get_gameplay_stats") as Dictionary).duplicate(true)
	var original_result: Dictionary = (profile_store.call("get_last_result") as Dictionary).duplicate(true)
	var original_song: Dictionary = (app_state.get("current_song") as Dictionary).duplicate(true)
	var original_difficulty: String = str(app_state.get("current_difficulty"))
	var original_mode: String = str(app_state.get("current_mode"))
	var original_leaderboard_service: Variant = app_state.get("leaderboard_service")
	app_state.set("leaderboard_service", null)

	profile_store.call("set_gameplay_stats", {
		"notes_hit": 100,
		"notes_missed": 20,
		"song_completions": 3,
		"song_failures": 1,
		"full_combos": 2,
		"all_perfects": 1,
	})
	var completion_stats: Dictionary = profile_store.call("record_gameplay_result_stats", {
		"notes_hit": 10,
		"notes_missed": 0,
		"perfect": 10,
		"great": 0,
		"good": 0,
		"miss": 0,
		"full_combo": true,
		"all_perfect": true,
		"song_failed": false,
	}) as Dictionary
	_expect_int(completion_stats, "notes_hit", 110, failures)
	_expect_int(completion_stats, "notes_missed", 20, failures)
	_expect_int(completion_stats, "song_completions", 4, failures)
	_expect_int(completion_stats, "song_failures", 1, failures)
	_expect_int(completion_stats, "full_combos", 3, failures)
	_expect_int(completion_stats, "all_perfects", 2, failures)

	var failure_stats: Dictionary = profile_store.call("record_gameplay_result_stats", {
		"perfect": 1,
		"great": 2,
		"good": 3,
		"miss": 4,
		"hold_successes": 5,
		"hold_breaks": 6,
		"song_failed": true,
	}) as Dictionary
	_expect_int(failure_stats, "notes_hit", 121, failures)
	_expect_int(failure_stats, "notes_missed", 30, failures)
	_expect_int(failure_stats, "song_completions", 4, failures)
	_expect_int(failure_stats, "song_failures", 2, failures)
	_expect_int(failure_stats, "full_combos", 3, failures)
	_expect_int(failure_stats, "all_perfects", 2, failures)

	await _check_stats_menu(failures)
	await _check_results_combo_badge(app_state, profile_store, failures)

	profile_store.call("set_gameplay_stats", original_stats)
	profile_store.call("set_last_result", original_result)
	app_state.set("current_song", original_song)
	app_state.set("current_difficulty", original_difficulty)
	app_state.set("current_mode", original_mode)
	app_state.set("leaderboard_service", original_leaderboard_service)

	if failures.is_empty():
		print("Gameplay stats/results smoke test passed.")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _check_stats_menu(failures: Array[String]) -> void:
	var packed := load("res://scenes/menus/StatsMenu.tscn") as PackedScene
	if packed == null:
		failures.append("Could not load StatsMenu.tscn.")
		return
	var menu := packed.instantiate()
	root.add_child(menu)
	await process_frame
	await process_frame
	var text := _collect_label_text(menu)
	for expected in [
		"NOTES HIT  •  121",
		"NOTES MISSED  •  30",
		"TOTAL SONG COMPLETIONS  •  4",
		"TOTAL SONG FAILURES  •  2",
		"DRIVE CHAIN (FULL COMBO)  •  3",
		"OVERDRIVE SYNC (ALL PERFECT)  •  2",
	]:
		if not text.contains(expected):
			failures.append("Stats menu missing line: %s" % expected)
	menu.queue_free()
	await process_frame


func _check_results_combo_badge(app_state: Node, profile_store: Node, failures: Array[String]) -> void:
	var packed := load("res://scenes/menus/ResultsMenu.tscn") as PackedScene
	if packed == null:
		failures.append("Could not load ResultsMenu.tscn.")
		return
	app_state.set("current_song", {
		"id": "combo_probe",
		"display_name": "Combo Probe",
		"artist": "Harmonic Drive",
		"source_type": "official",
	})
	app_state.set("current_difficulty", "Professional")
	app_state.set("current_mode", "stems_mapped")
	await _check_result_case(
		packed,
		profile_store,
		_result_payload({
			"perfect": 10,
			"great": 0,
			"good": 0,
			"miss": 0,
			"notes_hit": 10,
			"notes_missed": 0,
			"full_combo": true,
			"all_perfect": true,
		}),
		"Overdrive Sync (AP)",
		failures
	)
	await _check_result_case(
		packed,
		profile_store,
		_result_payload({
			"perfect": 8,
			"great": 2,
			"good": 0,
			"miss": 0,
			"notes_hit": 10,
			"notes_missed": 0,
			"full_combo": true,
			"all_perfect": false,
		}),
		"Drive Chain (FC)",
		failures
	)


func _check_result_case(packed: PackedScene, profile_store: Node, result: Dictionary, expected_text: String, failures: Array[String]) -> void:
	profile_store.call("set_last_result", result.duplicate(true))
	var menu := packed.instantiate()
	root.add_child(menu)
	await process_frame
	await process_frame
	var badge := menu.find_child("ComboBadgeLabel", true, false) as Label
	if badge == null or badge.text != expected_text:
		failures.append("Combo badge expected %s, got %s." % [expected_text, badge.text if badge != null else "<missing>"])
	var reveal := menu.find_child("AchievementRevealLabel", true, false) as Label
	if reveal != null:
		failures.append("Achievement reveal flash should not exist after AP/FC flash removal.")
	menu.queue_free()
	await process_frame


func _result_payload(overrides: Dictionary) -> Dictionary:
	var result := {
		"song_id": "combo_probe",
		"song_display_name": "Combo Probe",
		"song_artist": "Harmonic Drive",
		"chart_author": "Smoketest",
		"difficulty": "Professional",
		"mode": "stems_mapped",
		"score": 300000,
		"accuracy": 100.0,
		"accuracy_text": "100.00%",
		"perfect": 10,
		"great": 0,
		"good": 0,
		"miss": 0,
		"notes_hit": 10,
		"notes_missed": 0,
		"max_combo": 10,
		"source_type": "official",
		"source_label": "Official",
		"return_route": "song_select",
		"ranked": true,
	}
	for key in overrides.keys():
		result[key] = overrides[key]
	return result


func _expect_int(stats: Dictionary, key: String, expected: int, failures: Array[String]) -> void:
	var actual := int(stats.get(key, -1))
	if actual != expected:
		failures.append("%s expected %d, got %d." % [key, expected, actual])


func _collect_label_text(node: Node) -> String:
	var parts: Array[String] = []
	if node is Label:
		parts.append((node as Label).text)
	for child in node.get_children():
		parts.append(_collect_label_text(child))
	return "\n".join(parts)
