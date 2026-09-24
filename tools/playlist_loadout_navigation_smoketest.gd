extends SceneTree

var _failures: Array[String] = []
var _song_select_loadout_requested := false
var _local_songs_loadout_requested := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	await _check_song_select_button()
	await _check_local_songs_button()
	await _check_main_return_routes()
	if _failures.is_empty():
		print("Playlist loadout navigation smoke test passed.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _check_song_select_button() -> void:
	var packed := load("res://scenes/menus/SongSelectMenu.tscn") as PackedScene
	if packed == null:
		_failures.append("Could not load SongSelectMenu.tscn.")
		return
	var menu := packed.instantiate()
	root.add_child(menu)
	await process_frame
	var button := menu.get_node_or_null("%LoadoutButton") as Button
	_expect(button != null, "Song Select is missing LoadoutButton.")
	if button != null:
		_expect(button.text == "LOADOUTS", "Song Select LoadoutButton text is incorrect.")
	if menu.has_signal("loadout_requested"):
		menu.loadout_requested.connect(func() -> void: _song_select_loadout_requested = true)
		menu.call("_on_loadout_button_pressed")
		_expect(_song_select_loadout_requested, "Song Select LoadoutButton did not emit loadout_requested.")
	else:
		_failures.append("Song Select is missing loadout_requested signal.")
	menu.queue_free()


func _check_local_songs_button() -> void:
	var packed := load("res://scenes/menus/LocalSongsMenu.tscn") as PackedScene
	if packed == null:
		_failures.append("Could not load LocalSongsMenu.tscn.")
		return
	var menu := packed.instantiate()
	root.add_child(menu)
	await process_frame
	var button := menu.get_node_or_null("%LoadoutButton") as Button
	_expect(button != null, "Local Songs is missing LoadoutButton.")
	if button != null:
		_expect(button.text == "LOADOUTS", "Local Songs LoadoutButton text is incorrect.")
	if menu.has_signal("loadout_requested"):
		menu.loadout_requested.connect(func() -> void: _local_songs_loadout_requested = true)
		menu.call("_on_loadout_button_pressed")
		_expect(_local_songs_loadout_requested, "Local Songs LoadoutButton did not emit loadout_requested.")
	else:
		_failures.append("Local Songs is missing loadout_requested signal.")
	menu.queue_free()


func _check_main_return_routes() -> void:
	var packed := load("res://scenes/app/Main.tscn") as PackedScene
	if packed == null:
		_failures.append("Could not load Main.tscn.")
		return
	var main := packed.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	await _expect_shop_return(main, "song_select", "SongSelectMenu", "SELECT A TRACK")
	await _expect_shop_return(main, "local_songs", "LocalSongsMenu", "LOCAL SONGS")
	await _expect_shop_return(main, "community_charts", "LocalSongsMenu", "COMMUNITY CHARTS")
	main.queue_free()


func _expect_shop_return(main: Node, route: String, expected_screen_name: String, expected_title: String) -> void:
	main.call("_show_shop_from_playlist", route)
	await process_frame
	var shop := main.get("_current_screen") as Node
	_expect(shop != null and shop.name == "ShopMenu", "Route %s did not open ShopMenu." % route)
	if shop != null and shop.has_method("_on_back_button_pressed"):
		shop.call("_on_back_button_pressed")
		await _wait_for_screen(main, expected_screen_name, expected_title)
	var screen := main.get("_current_screen") as Node
	_expect(screen != null and screen.name == expected_screen_name, "Shop back route %s did not return to %s." % [route, expected_screen_name])
	var title := screen.get_node_or_null("%TitleLabel") as Label if screen != null else null
	_expect(title != null and title.text == expected_title, "Shop back route %s returned with wrong title." % route)


func _wait_for_screen(main: Node, expected_screen_name: String, expected_title: String) -> void:
	for _i in range(180):
		await process_frame
		var screen := main.get("_current_screen") as Node
		if screen == null or screen.name != expected_screen_name:
			continue
		var title := screen.get_node_or_null("%TitleLabel") as Label
		if title != null and title.text == expected_title:
			return


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
