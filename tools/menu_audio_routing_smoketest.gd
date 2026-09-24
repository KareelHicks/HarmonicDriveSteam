extends SceneTree

const EMSLoadoutCatalog := preload("res://scripts/ems/EMSLoadoutCatalog.gd")


func _initialize() -> void:
	await process_frame
	var initial_root_size := root.size
	root.size = Vector2i(721, initial_root_size.y if initial_root_size.y > 0 else 720)
	await process_frame
	var failures: Array[String] = []
	var menu_audio := root.get_node("MenuAudio")
	var content_registry := root.get_node("ContentRegistry")
	var profile_store := root.get_node("ProfileStore")
	var progression_manager := root.get_node("ProgressionManager")
	var original_progression: Dictionary = (profile_store.call("get_progression_data") as Dictionary).duplicate(true)
	var original_chart_background_disabled := bool(profile_store.call("is_chart_background_disabled"))
	var original_ems_background_mode := str(profile_store.call("get_ems_background_mode"))
	var default_ems_id := EMSLoadoutCatalog.get_default_loadout_id()
	var equip_result: Dictionary = progression_manager.call("equip_item", default_ems_id) as Dictionary
	if not bool(equip_result.get("ok", false)):
		var progression: Dictionary = original_progression.duplicate(true)
		var equipped: Dictionary = (progression.get("equipped_items", {}) as Dictionary).duplicate(true)
		equipped["ems_loadout"] = default_ems_id
		progression["equipped_items"] = equipped
		profile_store.call("set_progression_data", progression)
		if progression_manager.has_method("_load_or_reset"):
			progression_manager.call("_load_or_reset")
	profile_store.call("set_chart_background_disabled", false)
	profile_store.call("set_ems_background_mode", "psychedelic")
	var main_scene := load("res://scenes/app/Main.tscn") as PackedScene
	if main_scene == null:
		push_error("Failed to load Main scene.")
		quit(1)
		return
	var main := main_scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	if main.get_node_or_null("GlobalEMSBackdrop/GlobalEMSLeftWrap/GlobalEMSLeftGutter") == null:
		failures.append("Main scene is missing the left menu EMS gutter.")
	if main.get_node_or_null("GlobalEMSBackdrop/GlobalEMSRightWrap/GlobalEMSRightGutter") == null:
		failures.append("Main scene is missing the right menu EMS gutter.")
	_assert_global_menu_ems_center_blend(main, failures)
	if not _global_menu_ems_active(main):
		failures.append("Main menu EMS was not active on the title screen.")

	if menu_audio.call("get_mode") != "random" or not bool(menu_audio.call("is_playing")):
		failures.append("Title did not start random menu music.")
	var title_song_id := str(menu_audio.call("get_current_song_id"))
	var title_song := content_registry.call("get_song", title_song_id) as Dictionary
	if not title_song.is_empty() and str(menu_audio.call("_resolve_menu_chart_path", title_song)).is_empty():
		failures.append("Title menu music did not resolve a chart for EMS playback.")

	for route in ["show_settings", "show_shop", "show_stats", "show_progression", "show_multiplayer"]:
		main.call(route)
		await process_frame
		await process_frame
		if str(menu_audio.call("get_mode")) != "random":
			failures.append("%s changed MenuAudio mode to %s." % [route, str(menu_audio.call("get_mode"))])
		if str(menu_audio.call("get_current_song_id")) != title_song_id:
			failures.append("%s changed the current title song." % route)
		main.show_title()
		await process_frame
		await process_frame
		if str(menu_audio.call("get_current_song_id")) != title_song_id:
			failures.append("Returning from %s restarted or skipped the title song." % route)

	main.show_song_select()
	await process_frame
	await process_frame
	if str(menu_audio.call("get_mode")) != "preview":
		failures.append("Single Player did not switch to selected-song preview audio.")
	if not _global_menu_ems_active(main):
		failures.append("Single Player did not keep menu EMS active.")

	main.show_local_songs()
	await process_frame
	await process_frame
	var local_screen := main.get("_current_screen") as Node
	var local_songs: Array = local_screen.get("_songs") if local_screen != null else []
	if not local_songs.is_empty() and str(menu_audio.call("get_mode")) != "preview":
		failures.append("Local Songs did not switch to selected local-song preview audio.")
	if not local_songs.is_empty():
		var local_song := (local_songs[0] as Dictionary).duplicate(true)
		var chart_paths := local_screen.call("_chart_paths_for_song", local_song) as Dictionary
		local_song["modes"] = local_screen.call("_mode_payloads_for_chart_paths", chart_paths)
		if chart_paths.is_empty():
			failures.append("Local Songs selected song did not expose chart paths for EMS playback.")
		elif str(menu_audio.call("_resolve_menu_chart_path", local_song)).is_empty():
			failures.append("Local Songs selected song did not resolve a chart for EMS playback.")

	var app_state := root.get_node("AppState")
	var gameplay_song := _first_playable_song(content_registry)
	if gameplay_song.is_empty():
		failures.append("No playable song found for gameplay EMS route check.")
	else:
		app_state.call("start_song", gameplay_song, str(gameplay_song.get("_smoke_difficulty", "Professional")), str(gameplay_song.get("_smoke_mode", "stems_mapped")))
		await process_frame
		await process_frame
		if _global_menu_ems_active(main):
			failures.append("Gameplay route left the global menu EMS active.")
		var gameplay_screen := main.get("_current_screen") as Node
		if gameplay_screen == null or not gameplay_screen.has_method("_maximum_gameplay_shaders_active"):
			failures.append("Gameplay route did not expose the expected gameplay screen.")
		else:
			var playfield_ems_background := gameplay_screen.find_child("PlayfieldEMSBackground", true, false) as CanvasItem
			if playfield_ems_background != null and playfield_ems_background.visible:
				failures.append("Gameplay playfield EMS background is visible over the chart.")
			var background := gameplay_screen.find_child("Background", true, false) as ColorRect
			if background == null:
				failures.append("Gameplay background was not found.")
			elif not background.visible or background.color.a < 0.99:
				failures.append("Gameplay background is not opaque behind the chart.")
			_assert_gameplay_uses_psychedelic_ems_background(gameplay_screen, failures)
			_assert_invisible_canvas_item(gameplay_screen.find_child("DriveMeterGlow", true, false), "DriveMeterGlow", failures)
			_assert_invisible_canvas_item(gameplay_screen.find_child("ReceptorDeck", true, false), "ReceptorDeck", failures)
			_assert_receptor_glow_present(gameplay_screen.find_child("BaseGlow", true, false), "Receptor BaseGlow", failures)
			_assert_receptor_glow_present(gameplay_screen.find_child("PressGlow", true, false), "Receptor PressGlow", failures)
			gameplay_screen.set("_chart_background_disabled", true)
			gameplay_screen.call("_apply_theme")
			gameplay_screen.call("_layout_playfield")
			await process_frame
			_assert_disabled_chart_background_layout(gameplay_screen, failures)

	menu_audio.call("stop")
	main.queue_free()
	await process_frame
	profile_store.call("set_chart_background_disabled", original_chart_background_disabled)
	profile_store.call("set_ems_background_mode", original_ems_background_mode)
	profile_store.call("set_progression_data", original_progression)
	if progression_manager.has_method("_load_or_reset"):
		progression_manager.call("_load_or_reset")

	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("Menu audio routing smoke test passed.")
	quit(0)


func _global_menu_ems_active(main: Node) -> bool:
	var backdrop := main.get_node_or_null("GlobalEMSBackdrop")
	if backdrop == null:
		return false
	return bool(backdrop.get_meta("ems_context_active", true)) and (backdrop as CanvasItem).visible


func _assert_global_menu_ems_center_blend(main: Node, failures: Array[String]) -> void:
	if main.get_node_or_null("GlobalEMSBackdrop/GlobalEMSCenterSeamFill") != null:
		failures.append("Main menu EMS still has a visible center seam fill.")
	var left_wrap := main.get_node_or_null("GlobalEMSBackdrop/GlobalEMSLeftWrap") as Control
	var right_wrap := main.get_node_or_null("GlobalEMSBackdrop/GlobalEMSRightWrap") as Control
	if left_wrap == null or right_wrap == null:
		return
	var viewport_width := main.get_viewport().get_visible_rect().size.x
	var midpoint := floorf(viewport_width * 0.5)
	if absf((left_wrap.position.x + left_wrap.size.x) - midpoint) > 0.5:
		failures.append("Left menu EMS gutter does not end at the center split.")
	if absf(right_wrap.position.x - midpoint) > 0.5:
		failures.append("Right menu EMS gutter does not start at the center split.")


func _first_playable_song(content_registry: Node) -> Dictionary:
	var songs: Array = content_registry.call("get_songs")
	for song_variant in songs:
		var song := song_variant as Dictionary
		for mode in ["stems_mapped", "stems_random", "synthesized"]:
			var difficulties: Array = content_registry.call("get_supported_difficulties", song, mode)
			if difficulties.is_empty():
				continue
			var candidate := song.duplicate(true)
			candidate["_smoke_mode"] = mode
			candidate["_smoke_difficulty"] = str(difficulties[0])
			return candidate
	return {}


func _assert_invisible_canvas_item(node: Node, label: String, failures: Array[String]) -> void:
	var item := node as CanvasItem
	if item == null:
		failures.append("%s was not found." % label)
		return
	if item.visible:
		failures.append("%s is still visible." % label)


func _assert_receptor_glow_present(node: Node, label: String, failures: Array[String]) -> void:
	var panel := node as PanelContainer
	if panel == null:
		failures.append("%s was not found." % label)
		return
	var style := panel.get_theme_stylebox("panel") as StyleBoxFlat
	if style == null:
		failures.append("%s does not have a flat stylebox." % label)
		return
	if style.bg_color.a <= 0.001:
		failures.append("%s does not have a visible button fill glow." % label)
	if style.shadow_size <= 0 or style.shadow_color.a <= 0.001:
		failures.append("%s does not have a visible button shadow glow." % label)


func _assert_gameplay_uses_psychedelic_ems_background(gameplay_screen: Node, failures: Array[String]) -> void:
	var ems := root.get_node_or_null("EmotionalMotionSystem")
	if ems == null:
		failures.append("EmotionalMotionSystem autoload was not found during gameplay.")
		return
	if str(ems.get("background_mode")) != "psychedelic":
		failures.append("Gameplay EMS background mode was %s instead of psychedelic." % str(ems.get("background_mode")))
	var left_ems := gameplay_screen.find_child("EmotionalMotionLeftGutter", true, false)
	if left_ems == null:
		failures.append("Gameplay left EMS gutter was not found for psychedelic background check.")
		return
	var fog_layer: Variant = left_ems.get("_fog_layer")
	if fog_layer is CanvasItem and (fog_layer as CanvasItem).visible:
		failures.append("Gameplay psychedelic EMS background still has the grainy fog/noise layer visible.")
	if fog_layer is Node and bool((fog_layer as Node).get_meta("ems_visual_effect_enabled", true)):
		failures.append("Gameplay psychedelic EMS background still has the fog/noise layer enabled.")
	var gradient_layer: Variant = left_ems.get("_gradient_layer")
	if gradient_layer == null:
		failures.append("Gameplay left EMS gutter did not expose its gradient layer.")
		return
	var grad_a: Variant = gradient_layer.get("_grad_a") if gradient_layer.has_method("get") else null
	if not (grad_a is Gradient):
		failures.append("Gameplay EMS gradient layer did not expose a Gradient.")
		return
	if (grad_a as Gradient).colors.size() < 4:
		failures.append("Gameplay EMS gradient stayed on the smooth two-stop branch instead of psychedelic colors.")


func _assert_disabled_chart_background_layout(gameplay_screen: Node, failures: Array[String]) -> void:
	var background := gameplay_screen.find_child("Background", true, false) as CanvasItem
	if background == null:
		failures.append("Disabled chart background check could not find Background.")
	elif background.visible:
		failures.append("Disable chart background left the main chart Background visible.")
	var lane_backgrounds := gameplay_screen.find_child("LaneBackgrounds", true, false) as CanvasItem
	if lane_backgrounds != null and lane_backgrounds.visible:
		failures.append("Disable chart background left lane backgrounds visible.")
	var runway_inset := gameplay_screen.get_node_or_null("RunwayInset") as CanvasItem
	if runway_inset != null and runway_inset.visible:
		failures.append("Disable chart background left runway backgrounds visible.")
	var viewport_width := gameplay_screen.get_viewport().get_visible_rect().size.x
	var left_ems := gameplay_screen.find_child("EmotionalMotionLeftGutter", true, false) as Control
	var right_ems := gameplay_screen.find_child("EmotionalMotionRightGutter", true, false) as Control
	if left_ems == null or right_ems == null:
		failures.append("Disabled chart background check could not find EMS gutter controls.")
		return
	var midpoint := floorf(viewport_width * 0.5)
	if left_ems.size.x < midpoint - 0.5:
		failures.append("Left EMS gutter did not expand into the disabled chart area.")
	if right_ems.position.x > midpoint + 0.5:
		failures.append("Right EMS gutter did not expand into the disabled chart area.")
	if not right_ems.visible:
		failures.append("Disable chart background hid the split right EMS layer.")
	if absf((left_ems.position.x + left_ems.size.x) - midpoint) > 0.5:
		failures.append("Left EMS gutter does not end at the disabled-chart center split.")
	if absf(right_ems.position.x - midpoint) > 0.5:
		failures.append("Right EMS gutter does not start at the disabled-chart center split.")
	if gameplay_screen.find_child("EMSCenterSeamCover", true, false) != null:
		failures.append("Disable chart background still has a center seam cover.")
