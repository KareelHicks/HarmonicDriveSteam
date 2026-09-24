extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var preview_path := "user://shop_menu_oversized_ems_preview.png"
	_write_large_preview(preview_path)

	var packed := load("res://scenes/menus/ShopMenu.tscn") as PackedScene
	_expect(packed != null, "Could not load ShopMenu.tscn.")
	if packed == null:
		_finish(preview_path)
		return
	var menu := packed.instantiate()
	root.add_child(menu)
	await process_frame
	await process_frame
	var menu_text := _collect_label_text(menu)
	for included_name in ["Harmonic Core", "Thunder Matrix", "Chromatic Rift", "Skyline Mirage", "Crystal Reactor", "Gravity Well", "Hypernova Flow", "Singularity Bloom"]:
		_expect(_text_contains(menu_text, included_name), "Included EMS pack should render in Loadouts menu: %s." % included_name)
	_expect(not _text_contains(menu_text, "LOCKED"), "Built-in EMS Loadouts should not render a locked state.")
	_expect(not _text_contains(menu_text, "UNLOCKS IN"), "Built-in EMS Loadouts should not show section unlock requirements.")

	var scroll := menu.get_node_or_null("%ItemsScroll") as ScrollContainer
	_expect(scroll != null, "ShopMenu ItemsScroll is missing.")
	if scroll != null:
		_expect(scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "ShopMenu should disable horizontal scrolling for loadout rows.")

	var item := {
		"id": "workshop_layout_probe",
		"type": "ems_loadout",
		"display_name": "Workshop Layout Probe",
		"author": "Automated Test",
		"source": "workshop",
		"pack_type": "ems_config",
		"motion_intensity": 0.72,
		"particle_intensity": 0.45,
		"audio_reactive": true,
		"description": "Oversized preview should not stretch this EMS loadout row.",
		"acquisition": "community",
		"preview_path": preview_path,
	}
	var progression_manager := root.get_node_or_null("ProgressionManager")
	var player: Dictionary = progression_manager.call("get_player_data") as Dictionary if progression_manager != null else {}
	var card := menu.call("_build_ems_card", item, player) as PanelContainer
	_expect(card != null, "Could not build EMS loadout card.")
	if card != null:
		root.add_child(card)
		await process_frame
		var preview := _find_texture_rect(card)
		_expect(preview != null, "EMS loadout card preview TextureRect is missing.")
		if preview != null:
			_expect(preview.custom_minimum_size == Vector2(320, 180), "EMS loadout preview should use the fixed card preview size.")
			_expect(preview.expand_mode == TextureRect.EXPAND_IGNORE_SIZE, "EMS loadout preview should ignore source texture size.")
			_expect(preview.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_COVERED, "EMS loadout preview should crop oversized images into the fixed frame.")
			_expect(preview.clip_contents, "EMS loadout preview should clip oversized image content.")
			_expect(preview.texture != null and preview.texture.get_width() >= 1024, "Smoke fixture did not load an oversized preview texture.")
		var minimum := card.get_combined_minimum_size()
		_expect(minimum.y <= 360.0, "Oversized EMS preview should not make the loadout card taller than the fixed row frame. Minimum height: %.1f" % minimum.y)
		card.queue_free()

	menu.queue_free()
	_finish(preview_path)


func _find_texture_rect(node: Node) -> TextureRect:
	if node is TextureRect:
		return node as TextureRect
	for child in node.get_children():
		var found := _find_texture_rect(child)
		if found != null:
			return found
	return null


func _collect_label_text(node: Node) -> Array[String]:
	var values: Array[String] = []
	if node is Label:
		values.append((node as Label).text)
	for child in node.get_children():
		values.append_array(_collect_label_text(child))
	return values


func _text_contains(values: Array[String], needle: String) -> bool:
	for value in values:
		if value.contains(needle):
			return true
	return false


func _write_large_preview(path: String) -> void:
	var image := Image.create(1600, 1600, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.02, 0.02, 0.04, 1.0))
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if x % 120 < 64 or y % 120 < 64:
				image.set_pixel(x, y, Color(0.0, 0.55, 1.0, 1.0))
	var err := image.save_png(ProjectSettings.globalize_path(path))
	if err != OK:
		_failures.append("Could not write oversized EMS preview fixture.")


func _finish(preview_path: String) -> void:
	if FileAccess.file_exists(preview_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(preview_path))
	if _failures.is_empty():
		print("Shop menu EMS loadout layout smoke test passed.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
