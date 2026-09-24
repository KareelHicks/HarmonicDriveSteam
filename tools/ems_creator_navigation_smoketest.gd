extends SceneTree

func _initialize() -> void:
	await process_frame
	var failures: Array[String] = []
	var title_scene := load("res://scenes/menus/TitleMenu.tscn") as PackedScene
	if title_scene == null:
		failures.append("Title menu scene failed to load.")
		_finish(failures)
		return
	var title := title_scene.instantiate()
	root.add_child(title)
	await process_frame
	var creator_button := _find_button_with_text(title, "EMS Creator")
	if creator_button == null:
		failures.append("Title menu is missing the EMS Creator button.")
	if not title.has_signal("ems_creator_requested"):
		failures.append("Title menu is missing ems_creator_requested signal.")
	else:
		var state := {"requested": false}
		title.connect("ems_creator_requested", func() -> void: state["requested"] = true)
		if creator_button != null:
			creator_button.pressed.emit()
			await process_frame
			if not bool(state.get("requested", false)):
				failures.append("EMS Creator button did not emit ems_creator_requested.")
	title.queue_free()
	var shop_scene := load("res://scenes/menus/ShopMenu.tscn") as PackedScene
	if shop_scene != null:
		var shop := shop_scene.instantiate()
		root.add_child(shop)
		await process_frame
		if _find_button_with_text(shop, "EMS CREATOR") != null or _find_button_with_text(shop, "EMS Creator") != null:
			failures.append("Loadouts menu still shows an EMS Creator button after it moved to the main menu.")
		shop.queue_free()
	var creator_scene := load("res://systems/ems/EMSCreator/EMSCreatorScene.tscn") as PackedScene
	if creator_scene == null:
		failures.append("EMS Creator scene failed to load.")
		_finish(failures)
		return
	var creator := creator_scene.instantiate()
	root.add_child(creator)
	await process_frame
	var back_button := _find_button_with_text(creator, "BACK TO MAIN MENU")
	if back_button == null:
		failures.append("EMS Creator is missing the BACK TO MAIN MENU button.")
	if not creator.has_signal("back_requested"):
		failures.append("EMS Creator is missing back_requested signal.")
	else:
		var back_state := {"requested": false}
		creator.connect("back_requested", func() -> void: back_state["requested"] = true)
		if back_button != null:
			back_button.pressed.emit()
			await process_frame
			if not bool(back_state.get("requested", false)):
				failures.append("BACK TO MAIN MENU button did not emit back_requested.")
	creator.queue_free()
	_finish(failures)


func _finish(failures: Array[String]) -> void:
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("EMS Creator navigation smoke test passed.")
	quit(0)


func _find_button_with_text(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text == text:
		return node as Button
	for child in node.get_children():
		var found := _find_button_with_text(child, text)
		if found != null:
			return found
	return null
