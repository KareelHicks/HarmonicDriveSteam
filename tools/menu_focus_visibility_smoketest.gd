extends SceneTree

const HDTheme := preload("res://scripts/ui/HDTheme.gd")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	if not Input.get_connected_joypads().is_empty():
		print("Menu focus visibility smoke test skipped because a controller is connected.")
		quit(0)
		return
	await _check_title_menu_focus()
	await _check_song_select_focus()
	await _check_local_songs_focus()
	if _failures.is_empty():
		print("Menu focus visibility smoke test passed.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _check_title_menu_focus() -> void:
	var menu := _instantiate_menu("res://scenes/menus/TitleMenu.tscn")
	if menu == null:
		return
	await process_frame
	await process_frame
	var play_button := _button(menu, "PlayButton")
	_expect(_button(menu, "QuickPlayButton") == null, "Title menu should not expose the removed Quick Play playlist.")
	_expect(play_button != null, "Title menu is missing PlayButton.")
	_expect(_navigator_uses_controller_focus(menu) == false, "Title menu navigator should not use controller focus without a controller.")
	_expect(_no_focus_owner_for(menu), "Title menu should not claim focus without a controller.")
	if play_button != null:
		_expect(play_button.focus_mode == Control.FOCUS_NONE, "PlayButton should not be focusable without a controller.")
		_expect(not _button_uses_cyan_fill(play_button), "PlayButton should not use the cyan highlighted fill.")
	_check_active_button_style()
	menu.queue_free()


func _check_song_select_focus() -> void:
	var menu := _instantiate_menu("res://scenes/menus/SongSelectMenu.tscn")
	if menu == null:
		return
	await process_frame
	await process_frame
	var loadout_button := _button(menu, "LoadoutButton")
	_expect(loadout_button != null, "Song Select is missing LoadoutButton.")
	_expect(_navigator_uses_controller_focus(menu) == false, "Song Select navigator should not use controller focus without a controller.")
	_expect(_no_focus_owner_for(menu), "Song Select should not claim focus without a controller.")
	if loadout_button != null:
		_expect(loadout_button.focus_mode == Control.FOCUS_NONE, "Song Select LoadoutButton should not be focusable without a controller.")
	menu.call("_show_selection_overlay", "SELECT MODE", "Smoke", ["Classic"], Callable())
	await process_frame
	await process_frame
	_expect(_no_focus_owner_for(menu), "Song Select selection overlay should not claim focus without a controller.")
	var selection_button := _first_overlay_button(menu)
	if selection_button != null:
		_expect(selection_button.focus_mode == Control.FOCUS_NONE, "Song Select overlay option should not be focusable without a controller.")
	menu.queue_free()


func _check_local_songs_focus() -> void:
	var menu := _instantiate_menu("res://scenes/menus/LocalSongsMenu.tscn")
	if menu == null:
		return
	await process_frame
	await process_frame
	var loadout_button := _button(menu, "LoadoutButton")
	_expect(loadout_button != null, "Local Songs is missing LoadoutButton.")
	_expect(_navigator_uses_controller_focus(menu) == false, "Local Songs navigator should not use controller focus without a controller.")
	_expect(_no_focus_owner_for(menu), "Local Songs should not claim focus without a controller.")
	if loadout_button != null:
		_expect(loadout_button.focus_mode == Control.FOCUS_NONE, "Local Songs LoadoutButton should not be focusable without a controller.")
	menu.call("_show_selection_overlay", "SELECT MODE", "Smoke", ["Classic"], Callable())
	await process_frame
	await process_frame
	_expect(_no_focus_owner_for(menu), "Local Songs selection overlay should not claim focus without a controller.")
	var selection_button := _first_overlay_button(menu)
	if selection_button != null:
		_expect(selection_button.focus_mode == Control.FOCUS_NONE, "Local Songs overlay option should not be focusable without a controller.")
	menu.call("_hide_selection_overlay")
	menu.call("_show_info_overlay", "Import Song", "Smoke")
	await process_frame
	var info_close_button := _button(menu, "InfoCloseButton")
	if info_close_button != null:
		_expect(not info_close_button.has_focus(), "Local Songs info overlay close button should not claim focus without a controller.")
	menu.queue_free()


func _instantiate_menu(path: String) -> Control:
	var packed := load(path) as PackedScene
	if packed == null:
		_failures.append("Could not load %s." % path)
		return null
	var menu := packed.instantiate() as Control
	if menu == null:
		_failures.append("%s did not instantiate as a Control." % path)
		return null
	root.add_child(menu)
	return menu


func _navigator_uses_controller_focus(menu: Control) -> bool:
	var navigator := menu.get_node_or_null("MenuNavigator")
	return bool(navigator != null and navigator.has_method("uses_controller_focus") and navigator.call("uses_controller_focus"))


func _no_focus_owner_for(menu: Control) -> bool:
	var focused := root.gui_get_focus_owner()
	if focused == null:
		return true
	var node := focused as Node
	while node != null:
		if node == menu:
			return false
		node = node.get_parent()
	return true


func _first_overlay_button(menu: Control) -> Button:
	var selection_buttons := menu.get_node_or_null("%SelectionButtons")
	if selection_buttons == null:
		return null
	for child in selection_buttons.get_children():
		if child is Button and child.name != "SelectionCancelButton":
			return child as Button
	return null


func _button(menu: Control, node_name: String) -> Button:
	return menu.find_child(node_name, true, false) as Button


func _button_uses_cyan_fill(button: Button) -> bool:
	var style := button.get_theme_stylebox("normal")
	if style is not StyleBoxFlat:
		return false
	var color := (style as StyleBoxFlat).bg_color
	return color.b > 0.45 and color.g > 0.45 and color.r < 0.35


func _check_active_button_style() -> void:
	var active := HDTheme.button_style(true)
	var regular := HDTheme.button_style(false)
	_expect(active.bg_color.b > regular.bg_color.b and active.bg_color.g > regular.bg_color.g, "Active button style should use the light-blue fill.")
	_expect(active.border_color.g > 0.70 and active.border_color.b > 0.85 and active.border_color.r < 0.20, "Active button style should use the light-blue border.")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
