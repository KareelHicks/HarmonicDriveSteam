extends SceneTree

const EMSLoadoutCatalog := preload("res://scripts/ems/EMSLoadoutCatalog.gd")
const PremiumSongCatalog := preload("res://scripts/platform/PremiumSongCatalog.gd")


func _initialize() -> void:
	await process_frame
	var failures: Array[String] = []
	var profile := root.get_node_or_null("ProfileStore")
	var progression := root.get_node_or_null("ProgressionManager")
	var content := root.get_node_or_null("ContentRegistry")
	var app_state := root.get_node_or_null("AppState")
	if profile == null or progression == null or content == null or app_state == null:
		failures.append("Required autoloads were not available.")
		_finish(failures, profile, progression, {})
		return

	var original_progression := (profile.call("get_progression_data") as Dictionary).duplicate(true)
	progression.call("reset_progression")
	await process_frame

	_assert_quick_play_removed(app_state, failures)
	_assert_all_songs_available(content, progression, failures)
	await _assert_enter_the_flow_menu(content, failures)
	_assert_section_progress_does_not_gate_ems(content, progression, failures)
	_finish(failures, profile, progression, original_progression)


func _assert_quick_play_removed(app_state: Node, failures: Array[String]) -> void:
	if app_state.has_signal("show_quick_play_requested"):
		failures.append("AppState still exposes the removed Quick Play route.")
	var packed := load("res://scenes/menus/TitleMenu.tscn") as PackedScene
	if packed == null:
		failures.append("TitleMenu scene could not be loaded.")
		return
	var menu := packed.instantiate()
	if menu.find_child("QuickPlayButton", true, false) != null:
		failures.append("TitleMenu still contains a Quick Play button.")
	var play_button := menu.find_child("PlayButton", true, false) as Button
	if play_button == null or play_button.text != "Enter The Flow (Track Select)":
		failures.append("Enter The Flow should remain the regular singleplayer playlist.")
	menu.free()


func _assert_all_songs_available(content: Node, progression: Node, failures: Array[String]) -> void:
	var ordered_songs := content.call("get_progression_ordered_songs") as Array
	var manifest_songs := content.call("get_songs") as Array
	if ordered_songs.size() != manifest_songs.size():
		failures.append("Enter The Flow should include every manifest song, including songs not yet assigned to a section.")
	var player := progression.call("get_player_data") as Dictionary
	if int(player.get("unlocked_sections", 0)) != 1:
		failures.append("A fresh player should start with only the first EMS progression section active.")
	var compatibility_unlocked := _string_array(player.get("unlocked_songs", []))
	var owned := _string_array(player.get("owned_items", []))
	for loadout in EMSLoadoutCatalog.get_core_loadouts():
		var loadout_id := str(loadout.get("id", ""))
		if not owned.has(loadout_id):
			failures.append("Fresh profile is missing included EMS loadout: %s" % loadout_id)
	for song_variant in ordered_songs:
		if song_variant is not Dictionary:
			continue
		var song_id := str((song_variant as Dictionary).get("id", ""))
		if not bool(progression.call("is_song_unlocked", song_id)):
			failures.append("Song should be immediately playable: %s" % song_id)
		if not PremiumSongCatalog.is_premium_song(song_id) and not compatibility_unlocked.has(song_id):
			failures.append("Fresh profile compatibility list is missing standard song: %s" % song_id)


func _assert_enter_the_flow_menu(content: Node, failures: Array[String]) -> void:
	var packed := load("res://scenes/menus/SongSelectMenu.tscn") as PackedScene
	if packed == null:
		failures.append("SongSelectMenu scene could not be loaded.")
		return
	var menu := packed.instantiate()
	root.add_child(menu)
	await process_frame
	var title := menu.find_child("TitleLabel", true, false) as Label
	var status := menu.find_child("StatusLabel", true, false) as Label
	if title == null or title.text != "SELECT A TRACK":
		failures.append("Enter The Flow should open the regular track selector.")
	if status == null or not status.text.to_upper().contains("ALL EMS LOADOUTS AVAILABLE"):
		failures.append("Enter The Flow should state that every EMS Loadout is available.")
	for song_variant in content.call("get_progression_ordered_songs") as Array:
		if song_variant is not Dictionary:
			continue
		var song := song_variant as Dictionary
		if not bool(menu.call("is_song_available", str(song.get("id", "")))):
			failures.append("Enter The Flow menu rejected playable song: %s" % str(song.get("id", "")))
		if str(menu.call("_carousel_badge_label", song)) == "LOCKED":
			failures.append("Enter The Flow displayed a progression lock badge for %s." % str(song.get("id", "")))
	menu.queue_free()
	await process_frame


func _assert_section_progress_does_not_gate_ems(content: Node, progression: Node, failures: Array[String]) -> void:
	var sections := content.call("get_progression_sections") as Array
	if sections.size() < 2:
		failures.append("At least two progression sections are required for the section-progress test.")
		return
	var first_section := sections[0] as Dictionary
	var song_ids := _string_array(first_section.get("songs", []))
	var required := mini(int(first_section.get("unlock_requirement", 2)), song_ids.size())
	var unlock_payload: Dictionary = {}
	for index in range(required):
		unlock_payload = progression.call("complete_song", song_ids[index], 100000 + index) as Dictionary
	var player := progression.call("get_player_data") as Dictionary
	if int(player.get("unlocked_sections", 0)) != 2:
		failures.append("Clearing the first section should advance section progress.")
	if not (unlock_payload.get("newly_unlocked_song_ids", []) as Array).is_empty():
		failures.append("Section progression should not unlock songs because every song is already playable.")
	var new_ems := _string_array(unlock_payload.get("newly_unlocked_ems_loadout_ids", []))
	if not new_ems.is_empty():
		failures.append("Section completion should not report EMS unlocks because every loadout is already available.")
	var owned := _string_array(player.get("owned_items", []))
	for loadout in EMSLoadoutCatalog.get_core_loadouts():
		if not owned.has(str(loadout.get("id", ""))):
			failures.append("Section completion left an EMS Loadout gated: %s" % str(loadout.get("id", "")))


func _finish(failures: Array[String], profile: Node, progression: Node, original_progression: Dictionary) -> void:
	if profile != null and not original_progression.is_empty():
		profile.call("set_progression_data", original_progression)
		if progression != null:
			progression.call("_load_or_reset")
	if failures.is_empty():
		print("SONG_ACCESS_EMS_PROGRESSION_SMOKETEST_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for item in value:
			result.append(str(item))
	return result
