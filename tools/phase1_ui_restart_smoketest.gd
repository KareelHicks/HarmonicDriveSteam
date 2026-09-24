extends SceneTree

const HDSongCarousel := preload("res://scripts/ui/HDSongCarousel.gd")
const SongJacketService := preload("res://scripts/ui/SongJacketService.gd")


func _initialize() -> void:
	await process_frame
	var failures: Array[String] = []
	_check_jackets(failures)
	await _check_scene_carousel("res://scenes/menus/SongSelectMenu.tscn", failures)
	await _check_scene_carousel("res://scenes/menus/LocalSongsMenu.tscn", failures)
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("Phase 1 UI restart smoke test passed.")
	quit(0)


func _check_jackets(failures: Array[String]) -> void:
	var content_registry := root.get_node("ContentRegistry")
	var songs: Array = content_registry.call("get_songs")
	for song_variant in songs:
		var song: Dictionary = song_variant as Dictionary
		var path := SongJacketService.jacket_path_for_song(song)
		if not FileAccess.file_exists(path):
			failures.append("Missing jacket %s" % path)
			continue
		var imported_texture := load(path) as Texture2D
		if imported_texture == null:
			failures.append("Invalid jacket texture %s" % path)
			continue
		if imported_texture.get_width() != 1024 or imported_texture.get_height() != 1024:
			failures.append("%s dimensions were %dx%d, expected 1024x1024." % [path, imported_texture.get_width(), imported_texture.get_height()])
		var texture := SongJacketService.texture_for_song(song)
		if texture == null:
			failures.append("Jacket texture did not resolve for %s" % str(song.get("id", "")))


func _check_scene_carousel(scene_path: String, failures: Array[String]) -> void:
	var packed := load(scene_path) as PackedScene
	if packed == null:
		failures.append("Failed to load %s" % scene_path)
		return
	var instance := packed.instantiate()
	if instance == null:
		failures.append("Failed to instantiate %s" % scene_path)
		return
	root.add_child(instance)
	await process_frame
	await process_frame
	var carousel := instance.find_child("SongCarousel", true, false) as HDSongCarousel
	var back_button := instance.find_child("BackButton", true, false) as Button
	if back_button == null:
		failures.append("%s missing BackButton." % scene_path)
	elif not back_button.visible or back_button.text.strip_edges().is_empty() or back_button.flat:
		failures.append("%s BackButton is not visibly styled." % scene_path)
	if carousel == null:
		failures.append("%s missing SongCarousel." % scene_path)
	else:
		var left_button := carousel.find_child("LeftNavigateButton", true, false) as Button
		var right_button := carousel.find_child("RightNavigateButton", true, false) as Button
		if left_button == null:
			failures.append("%s missing left carousel navigation button." % scene_path)
		if right_button == null:
			failures.append("%s missing right carousel navigation button." % scene_path)
		if scene_path.ends_with("SongSelectMenu.tscn") and carousel.songs.is_empty():
			failures.append("SongSelect carousel has no songs.")
		var selected_card := carousel.find_child("SelectedSongCard", true, false) as PanelContainer
		if selected_card == null:
			failures.append("%s missing selected carousel card." % scene_path)
		else:
			var selected_bounds := Rect2(selected_card.position, selected_card.size)
			var carousel_bounds := Rect2(Vector2.ZERO, carousel.size)
			if carousel.size.y > 1.0 and (selected_bounds.position.y < -1.0 or selected_bounds.end.y > carousel_bounds.end.y + 1.0):
				failures.append("%s selected carousel card is clipped vertically. card_y=%.1f card_h=%.1f carousel_h=%.1f" % [scene_path, selected_card.position.y, selected_card.size.y, carousel.size.y])
			if selected_card.has_meta("_hd_ui_motion_breath"):
				failures.append("%s selected carousel card is still running a breathing animation." % scene_path)
			for label_name in ["Title", "Artist", "Meta", "Best", "Difficulty", "Badge"]:
				var label := selected_card.find_child(label_name, true, false) as Label
				if label == null:
					failures.append("%s selected card missing %s label." % [scene_path, label_name])
					continue
				if not label.visible or label.text.strip_edges().is_empty() or label.custom_minimum_size.y <= 0.0:
					failures.append("%s selected card does not visibly expose %s." % [scene_path, label_name])
				if label_name == "Title" and label.max_lines_visible < 3:
					failures.append("%s selected card Title cannot wrap to three lines." % scene_path)
				if label_name == "Artist" and label.max_lines_visible < 2:
					failures.append("%s selected card Artist cannot wrap to two lines." % scene_path)
		if carousel.size.x > 1.0 and carousel.size.y > 1.0 and left_button != null:
			var hover_y := carousel.size.y * 0.5
			carousel.call("_update_hover_zone", Vector2(carousel.size.x * 0.34, hover_y))
			var near_rate := float(carousel.get("_hover_scroll_rate"))
			carousel.call("_update_hover_zone", Vector2(carousel.size.x * 0.12, hover_y))
			var far_rate := float(carousel.get("_hover_scroll_rate"))
			if far_rate <= near_rate:
				failures.append("%s carousel hover scroll does not speed up toward the edge." % scene_path)
			if far_rate < 3.0:
				failures.append("%s carousel hover scroll is too slow near the navigation edge." % scene_path)
			left_button.emit_signal("mouse_entered")
			if int(carousel.get("_hover_scroll_direction")) != 0:
				failures.append("%s carousel hover auto-scroll did not stop over the left nav button." % scene_path)
		if carousel.songs.size() > 1:
			var before := str(carousel.get_selected_song().get("id", carousel.get_selected_song().get("song_id", "")))
			carousel.move(1)
			var after := str(carousel.get_selected_song().get("id", carousel.get_selected_song().get("song_id", "")))
			if before == after:
				failures.append("%s carousel did not change selection." % scene_path)
		await _check_selection_overlay_initial_focus(instance, scene_path, failures)
	instance.queue_free()
	await process_frame


func _check_selection_overlay_initial_focus(instance: Node, scene_path: String, failures: Array[String]) -> void:
	if not instance.has_method("_show_selection_overlay"):
		return
	instance.call(
		"_show_selection_overlay",
		"SELECT MODE",
		"Smoke Test",
		["Classic", "Lane Shuffle"],
		Callable(self, "_noop_selection_option")
	)
	await process_frame
	await process_frame
	await process_frame
	var selection_buttons := instance.find_child("SelectionButtons", true, false)
	if selection_buttons == null:
		failures.append("%s missing SelectionButtons." % scene_path)
		return
	var first_option: Button = null
	for child in selection_buttons.get_children():
		if child is Button and child.name != "SelectionCancelButton":
			first_option = child as Button
			break
	if first_option == null:
		failures.append("%s selection overlay did not create an option button." % scene_path)
		return
	var expected_pivot := first_option.size * 0.5
	if first_option.pivot_offset.distance_to(expected_pivot) > 1.0:
		failures.append("%s first selection option pivot is not centered before hover." % scene_path)
	if not first_option.has_focus():
		failures.append("%s first selection option did not receive deferred focus." % scene_path)


func _noop_selection_option(_option: Variant) -> void:
	pass
