extends SceneTree


func _initialize() -> void:
	await process_frame
	var failures: Array[String] = []
	var profile := root.get_node_or_null("ProfileStore")
	var content := root.get_node_or_null("ContentRegistry")
	var app_state := root.get_node_or_null("AppState")
	if profile == null:
		failures.append("ProfileStore autoload was not found.")
	if content == null:
		failures.append("ContentRegistry autoload was not found.")
	if app_state == null:
		failures.append("AppState autoload was not found.")
	if not failures.is_empty():
		_finish(failures, profile, "")
		return

	var original_ui_mode := str(profile.call("get_in_game_ui_mode"))
	var song := _first_playable_song(content)
	if song.is_empty():
		failures.append("No playable manifest song was found.")
		_finish(failures, profile, original_ui_mode)
		return
	var difficulty := _first_difficulty(content, song)
	if difficulty.is_empty():
		failures.append("Playable song had no supported difficulty.")
		_finish(failures, profile, original_ui_mode)
		return

	var settings_menu := await _spawn_settings_menu()
	if settings_menu == null:
		failures.append("Failed to instantiate SettingsMenu.")
	else:
		_assert_settings_dropdown(settings_menu, failures)
		settings_menu.queue_free()
		await process_frame

	profile.call("set_in_game_ui_mode", "classic")
	var classic_scene := await _spawn_game_scene(app_state, song, difficulty)
	if classic_scene == null:
		failures.append("Failed to instantiate GameScene for classic in-game UI.")
	else:
		_assert_classic_hud(classic_scene, failures)
		classic_scene.queue_free()
		await process_frame

	profile.call("set_in_game_ui_mode", "modern")
	var modern_scene := await _spawn_game_scene(app_state, song, difficulty)
	if modern_scene == null:
		failures.append("Failed to instantiate GameScene for modern in-game UI.")
	else:
		_assert_modern_hud(modern_scene, failures)
		modern_scene.queue_free()
		await process_frame

	_finish(failures, profile, original_ui_mode)


func _spawn_settings_menu() -> Node:
	var packed := load("res://scenes/menus/SettingsMenu.tscn") as PackedScene
	if packed == null:
		return null
	var menu := packed.instantiate()
	root.add_child(menu)
	await process_frame
	return menu


func _spawn_game_scene(app_state: Node, song: Dictionary, difficulty: String) -> Node:
	app_state.set("current_song", song.duplicate(true))
	app_state.set("current_difficulty", difficulty)
	app_state.set("current_mode", "stems_mapped")
	var packed := load("res://scenes/gameplay/GameScene.tscn") as PackedScene
	if packed == null:
		return null
	var scene := packed.instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	return scene


func _assert_settings_dropdown(menu: Node, failures: Array[String]) -> void:
	var dropdown := menu.find_child("InGameUIOptionButton", true, false) as OptionButton
	if dropdown == null:
		failures.append("In-game UI dropdown was not found in SettingsMenu.")
		return
	if dropdown.item_count != 2:
		failures.append("In-game UI dropdown should expose exactly 2 choices.")
		return
	if dropdown.get_item_text(0) != "Classic in-game UI":
		failures.append("First in-game UI dropdown item was not 'Classic in-game UI'.")
	if dropdown.get_item_text(1) != "Modern in-game UI":
		failures.append("Second in-game UI dropdown item was not 'Modern in-game UI'.")


func _assert_classic_hud(scene: Node, failures: Array[String]) -> void:
	var score_pill := scene.find_child("ScorePill", true, false) as Control
	var top_center := scene.find_child("TopCenterVBox", true, false) as Control
	var modern_stats := scene.find_child("ModernStatsPanel", true, false) as Control
	if score_pill == null or not score_pill.visible:
		failures.append("Classic in-game UI did not show the existing ScorePill.")
	if top_center == null or not top_center.visible:
		failures.append("Classic in-game UI did not show the existing top-center song/combo labels.")
	if modern_stats == null:
		failures.append("ModernStatsPanel was not created for mode switching.")
	elif modern_stats.visible:
		failures.append("ModernStatsPanel should be hidden in classic in-game UI mode.")


func _assert_modern_hud(scene: Node, failures: Array[String]) -> void:
	var score_pill := scene.find_child("ScorePill", true, false) as Control
	var top_center := scene.find_child("TopCenterVBox", true, false) as Control
	var modern_stats := scene.find_child("ModernStatsPanel", true, false) as Control
	var modern_song := scene.find_child("ModernSongPanel", true, false) as Control
	var modern_combo := scene.find_child("ModernComboValueLabel", true, false) as Label
	var modern_title := scene.find_child("ModernSongTitleLabel", true, false) as Label
	if score_pill == null or score_pill.visible:
		failures.append("Modern in-game UI should hide the existing ScorePill.")
	if top_center == null or top_center.visible:
		failures.append("Modern in-game UI should hide the existing top-center song/combo labels.")
	if modern_stats == null or not modern_stats.visible:
		failures.append("ModernStatsPanel should be visible in modern in-game UI mode.")
	if modern_song == null or not modern_song.visible:
		failures.append("ModernSongPanel should be visible in modern in-game UI mode.")
	if modern_combo == null or modern_combo.text != "0":
		failures.append("Modern combo label did not initialize to 0.")
	if modern_title == null or modern_title.text.strip_edges().is_empty():
		failures.append("Modern song title label did not populate from song metadata.")


func _first_playable_song(content: Node) -> Dictionary:
	var songs: Array = content.call("get_songs")
	for song_variant in songs:
		if song_variant is not Dictionary:
			continue
		var song: Dictionary = song_variant
		if not _first_difficulty(content, song).is_empty():
			return song.duplicate(true)
	return {}


func _first_difficulty(content: Node, song: Dictionary) -> String:
	var difficulties: Array = content.call("get_supported_difficulties", song, "stems_mapped")
	for difficulty_variant in difficulties:
		var difficulty := str(difficulty_variant)
		if not difficulty.is_empty():
			return difficulty
	return ""


func _finish(failures: Array[String], profile: Node, original_ui_mode: String) -> void:
	if profile != null and not original_ui_mode.is_empty():
		profile.call("set_in_game_ui_mode", original_ui_mode)
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("In-game UI mode smoke test passed.")
	quit(0)
