extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	var profile_store := root.get_node("ProfileStore")
	var app_state := root.get_node("AppState")
	var original_result: Dictionary = (profile_store.call("get_last_result") as Dictionary).duplicate(true)
	var original_song: Dictionary = (app_state.get("current_song") as Dictionary).duplicate(true)
	var original_difficulty: String = str(app_state.get("current_difficulty"))
	var original_mode: String = str(app_state.get("current_mode"))
	var original_leaderboard_service: Variant = app_state.get("leaderboard_service")
	app_state.set("leaderboard_service", null)

	var packed := load("res://scenes/menus/ResultsMenu.tscn") as PackedScene
	if packed == null:
		failures.append("Could not load ResultsMenu.tscn.")
	else:
		await _check_case(
			packed,
			{
				"id": "official_probe",
				"display_name": "Official Probe",
				"artist": "Harmonic Drive",
				"source_type": "official",
			},
			_base_result({"source_type": "official", "source_label": "Official", "return_route": "song_select", "ranked": true}),
			"OFFICIAL",
			"SONG SELECT",
			true,
			failures
		)
		await _check_case(
			packed,
			{
				"id": "local_probe",
				"display_name": "Local Probe",
				"artist": "Local Artist",
				"charter": "Local Charter",
				"source_type": "custom",
				"root_path": "user://custom_songs/local_probe",
			},
			_base_result({"source_type": "custom", "source_label": "Local", "return_route": "local_songs", "ranked": false}),
			"LOCAL",
			"LOCAL SONGS",
			false,
			failures
		)
		await _check_case(
			packed,
			{
				"id": "workshop_probe",
				"display_name": "Workshop Probe",
				"artist": "Community Artist",
				"charter": "Workshop Charter",
				"source_type": "workshop",
				"root_path": "user://workshop/workshop_probe",
			},
			_base_result({"source_type": "workshop", "source_label": "Community", "return_route": "community_charts", "ranked": true}),
			"COMMUNITY",
			"COMMUNITY CHARTS",
			true,
			failures
		)
		await _check_case(
			packed,
			{
				"id": "match_probe",
				"display_name": "Match Probe",
				"artist": "Versus Artist",
				"source_type": "official",
			},
			_base_result({"source_type": "official", "source_label": "Official", "return_route": "multiplayer", "ranked": true, "multiplayer": true, "placement": 1, "winner_display_name": "YOU"}),
			"OFFICIAL",
			"MULTIPLAYER",
			false,
			failures
		)

	profile_store.call("set_last_result", original_result)
	app_state.set("current_song", original_song)
	app_state.set("current_difficulty", original_difficulty)
	app_state.set("current_mode", original_mode)
	app_state.set("leaderboard_service", original_leaderboard_service)

	if failures.is_empty():
		print("Modern results menu smoke test passed.")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _base_result(overrides: Dictionary) -> Dictionary:
	var result := {
		"song_id": "probe",
		"song_display_name": "Probe Song",
		"song_artist": "Probe Artist",
		"chart_author": "Probe Charter",
		"difficulty": "Professional",
		"mode": "stems_mapped",
		"score": 285875,
		"accuracy": 85.81,
		"accuracy_text": "85.81%",
		"perfect": 556,
		"great": 83,
		"good": 111,
		"miss": 40,
		"max_combo": 133,
		"xp_earned": 126,
		"currency_earned": 126,
		"level_before": 15,
		"level_after": 15,
		"xp_before": 710,
		"xp_after": 836,
		"xp_needed_before": 3004,
		"xp_needed_after": 3004,
		"previous_local_best_score": 240000,
	}
	for key in overrides.keys():
		result[key] = overrides[key]
	return result


func _check_case(packed: PackedScene, song: Dictionary, result: Dictionary, expected_source: String, expected_back: String, expect_leaderboard_visible: bool, failures: Array[String]) -> void:
	var profile_store := root.get_node("ProfileStore")
	var app_state := root.get_node("AppState")
	app_state.set("current_song", song.duplicate(true))
	app_state.set("current_difficulty", str(result.get("difficulty", "Professional")))
	app_state.set("current_mode", str(result.get("mode", "stems_mapped")))
	profile_store.call("set_last_result", result.duplicate(true))
	var menu := packed.instantiate()
	root.add_child(menu)
	await process_frame
	await process_frame

	var source := menu.find_child("SourceBadge", true, false) as Label
	var back := menu.find_child("BackActionButton", true, false) as Button
	var leaderboard := menu.find_child("LeaderboardButton", true, false) as Button
	if source == null or source.text != expected_source:
		failures.append("%s source badge expected %s, got %s." % [str(result.get("source_type", "")), expected_source, source.text if source != null else "<missing>"])
	if back == null or back.text != expected_back:
		failures.append("%s back route expected %s, got %s." % [str(result.get("source_type", "")), expected_back, back.text if back != null else "<missing>"])
	if leaderboard == null:
		failures.append("LeaderboardButton is missing.")
	elif leaderboard.visible != expect_leaderboard_visible:
		failures.append("%s leaderboard visibility expected %s, got %s." % [str(result.get("source_type", "")), str(expect_leaderboard_visible), str(leaderboard.visible)])
	var hero_xp_frame := menu.find_child("HeroXPBarFrame", true, false) as PanelContainer
	var rewards_xp_frame := menu.find_child("XPBarFrame", true, false) as PanelContainer
	if hero_xp_frame == null:
		failures.append("Hero XP bar is missing from the left results panel.")
	if rewards_xp_frame == null:
		failures.append("Rewards XP bar is missing.")
	var xp_tween: Variant = menu.get("_xp_tween")
	if xp_tween is Tween and is_instance_valid(xp_tween):
		(xp_tween as Tween).kill()
	menu.set("_xp_animating", false)
	menu.call("_update_xp_bar_state", 0.25, 751, 3004)
	await process_frame
	var hero_fill := menu.find_child("HeroXPBarFill", true, false) as ColorRect
	if hero_fill == null:
		failures.append("Hero XP fill is missing.")
	else:
		var clip := hero_fill.get_parent() as Control
		if clip != null and clip.size.x > 0.0:
			var expected_width := clip.size.x * 0.25
			if absf(hero_fill.offset_right - expected_width) > 2.0:
				failures.append("Hero XP fill width expected %.1f, got %.1f." % [expected_width, hero_fill.offset_right])
			if hero_fill.offset_right >= clip.size.x - 1.0:
				failures.append("Hero XP fill rendered full width for a partial XP ratio.")

	for tab_id in ["summary", "details", "rewards", "match"]:
		menu.call("_set_tab", tab_id)
		await process_frame
		var panel_name := "%sPanel" % tab_id.capitalize()
		var panel := menu.find_child(panel_name, true, false) as Control
		if panel == null or not panel.visible:
			failures.append("%s tab did not show %s." % [str(result.get("source_type", "")), panel_name])

	var ems_backdrop := menu.get_node_or_null("%EMSResultsBackdrop") as Control
	if ems_backdrop == null:
		failures.append("EMSResultsBackdrop is missing.")
	var scrim := menu.get_node_or_null("%Scrim") as ColorRect
	if scrim == null or scrim.color.a <= 0.0:
		failures.append("Results scrim is missing or transparent.")
	menu.queue_free()
	await process_frame
