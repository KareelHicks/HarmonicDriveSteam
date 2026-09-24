extends SceneTree

const EMSLoadoutCatalog := preload("res://scripts/ems/EMSLoadoutCatalog.gd")


func _initialize() -> void:
	await process_frame
	var ems := root.get_node("EmotionalMotionSystem")
	var profile_store := root.get_node("ProfileStore")
	var original_prioritize_fps := bool(profile_store.call("is_prioritize_fps_enabled"))
	var failures: Array[String] = []
	profile_store.call("set_prioritize_fps_enabled", false)
	await process_frame

	var required_weights := ["gradient", "depth", "particles", "fog", "ribbon", "glyph", "ripple", "distortion", "gameplay_shader", "pressure_wave"]
	for loadout in EMSLoadoutCatalog.get_core_loadouts():
		var loadout_id := str(loadout.get("id", ""))
		ems.call("apply_loadout", loadout_id)
		ems.call("reseed_run_palette", int(loadout.get("catalog_order", 1)) * 101)
		ems.call("set_song_bpm", 146.0)
		ems.call("set_combo_energy", 0.84)
		ems.call("set_note_density", 0.42)
		ems.call("notify_impulse", 0.70, 0.78, "loadout_runtime_test", int(loadout.get("catalog_order", 1)))
		await process_frame
		if str(ems.call("get_active_loadout_id")) != loadout_id:
			failures.append("Active EMS loadout did not update to %s." % loadout_id)
		if str(ems.call("get_active_loadout_display_name")).is_empty():
			failures.append("%s has an empty active display name." % loadout_id)
		if str(ems.call("get_motion_profile")).is_empty():
			failures.append("%s has an empty motion profile." % loadout_id)
		var signature := str(ems.call("get_signature_effect"))
		if loadout_id == EMSLoadoutCatalog.get_default_loadout_id():
			if signature != "classic" or bool(ems.call("has_signature_effect")):
				failures.append("Harmonic Core should stay classic-only.")
		else:
			if signature.is_empty() or signature == "classic":
				failures.append("%s did not activate a unique signature effect." % loadout_id)
			if not bool(ems.call("has_signature_effect")):
				failures.append("%s did not report signature effect active." % loadout_id)
			if bool(ems.call("is_classic_layer_enabled", "ripple", true)) or bool(ems.call("is_classic_layer_enabled", "ribbon", true)):
				failures.append("%s kept classic ripple/ribbon layers enabled." % loadout_id)
		var palette: Array = ems.call("get_palette_colors")
		if palette.is_empty():
			failures.append("%s generated an empty EMS palette." % loadout_id)
		var hit_effect := str(ems.call("get_effective_hit_effect"))
		if hit_effect not in ["circular", "pressure"]:
			failures.append("%s produced invalid hit effect %s." % [loadout_id, hit_effect])
		for weight_key in required_weights:
			var weight := float(ems.call("get_loadout_layer_weight", weight_key, 1.0))
			if weight < 0.0 or weight > 1.35:
				failures.append("%s produced out-of-range %s weight %.3f." % [loadout_id, weight_key, weight])

	ems.call("apply_loadout", "ems_hypernova_flow")
	var normal_particle_weight := float(ems.call("get_loadout_layer_weight", "particles", 1.0))
	profile_store.call("set_prioritize_fps_enabled", true)
	await process_frame
	var capped_particle_weight := float(ems.call("get_loadout_layer_weight", "particles", 1.0))
	if capped_particle_weight > 0.92:
		failures.append("Prioritize FPS did not cap expensive EMS particle weight.")
	if capped_particle_weight >= normal_particle_weight:
		failures.append("Prioritize FPS did not reduce expensive EMS particle weight.")

	profile_store.call("set_prioritize_fps_enabled", original_prioritize_fps)
	ems.call("apply_loadout", EMSLoadoutCatalog.get_default_loadout_id())

	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("EMS loadout runtime smoke test passed.")
	quit(0)
