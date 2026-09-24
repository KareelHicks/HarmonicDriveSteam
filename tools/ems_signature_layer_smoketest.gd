extends SceneTree

const EMSLoadoutCatalog := preload("res://scripts/ems/EMSLoadoutCatalog.gd")


func _initialize() -> void:
	await process_frame
	var ems := root.get_node("EmotionalMotionSystem")
	var failures: Array[String] = []
	var expected_families := {
		"ems_neon_rain": "neon_raindrops",
		"ems_plasma_storm": "plasma_cells",
		"ems_quantum_grid": "quantum_lattice",
		"ems_aurora_drive": "aurora_curtains",
		"ems_fractal_space": "fractal_portals",
		"ems_prism_circuit": "prism_circuitry",
		"ems_solar_bloom": "solar_corona",
	}
	var signature_script := load("res://scripts/ems/EMSLoadoutSignatureLayer.gd")
	if not signature_script is Script:
		push_error("Failed to load EMSLoadoutSignatureLayer.")
		quit(1)
		return

	var signature_layer: Node = (signature_script as Script).new()
	root.add_child(signature_layer)
	await process_frame
	for loadout in EMSLoadoutCatalog.get_core_loadouts():
		var loadout_id := str(loadout.get("id", ""))
		ems.call("apply_loadout", loadout_id)
		ems.call("reseed_run_palette", int(loadout.get("catalog_order", 1)) * 313)
		ems.call("set_song_bpm", 158.0)
		ems.call("set_combo_energy", 0.92)
		ems.call("set_note_density", 0.55)
		signature_layer.call("ems_on_loadout_changed", ems)
		signature_layer.call("ems_on_palette_changed", ems)
		signature_layer.call("ems_on_impulse", ems, {
			"lane": int(loadout.get("catalog_order", 1)) % 5,
			"strength": 0.82,
			"y_norm": 0.78,
			"color": ems.call("pick_color", "signature_test", int(loadout.get("catalog_order", 1))),
		})
		signature_layer.call("ems_update", ems, 0.016)
		var state := signature_layer.call("get_debug_state") as Dictionary
		if loadout_id == EMSLoadoutCatalog.get_default_loadout_id():
			if bool(state.get("signature_active", true)):
				failures.append("Harmonic Core unexpectedly activated the signature layer.")
			continue
		var config: Dictionary = loadout.get("config", {}) as Dictionary
		if str(state.get("effect", "")) != str(config.get("signature_effect", "")):
			failures.append("%s signature layer effect mismatch." % loadout_id)
		if int(state.get("active_count", 0)) <= 0:
			failures.append("%s signature layer did not activate any draw units." % loadout_id)
			if int(state.get("pool_size", 0)) < int(state.get("active_count", 0)):
				failures.append("%s signature layer active count exceeds pool size." % loadout_id)
			if str(state.get("palette_morph", "")).is_empty() or str(state.get("reaction_model", "")).is_empty():
				failures.append("%s signature layer missing morph/reaction debug state." % loadout_id)
			if expected_families.has(loadout_id) and str(state.get("render_family", "")) != str(expected_families[loadout_id]):
				failures.append("%s expected render family %s, got %s." % [loadout_id, str(expected_families[loadout_id]), str(state.get("render_family", ""))])
	signature_layer.queue_free()

	var motion_script := load("res://scripts/ems/EmotionalMotionLayer.gd")
	if not motion_script is Script:
		push_error("Failed to load EmotionalMotionLayer.")
		quit(1)
		return
	var motion_layer: Control = (motion_script as Script).new()
	motion_layer.name = "SignatureSmokeGutter"
	motion_layer.size = Vector2(640, 360)
	root.add_child(motion_layer)
	await process_frame
	await process_frame

	ems.call("apply_loadout", EMSLoadoutCatalog.get_default_loadout_id())
	await process_frame
	var core_state := motion_layer.call("get_ems_layer_debug_state") as Dictionary
	if bool(core_state.get("signature", false)):
		failures.append("Harmonic Core should not show the signature layer.")
	if not bool(core_state.get("ripple", false)) or not bool(core_state.get("ribbon", false)) or not bool(core_state.get("pulse", false)):
		failures.append("Harmonic Core should keep classic ripple/ribbon/pulse layers.")

	ems.call("apply_loadout", "ems_neon_rain")
	await process_frame
	var neon_state := motion_layer.call("get_ems_layer_debug_state") as Dictionary
	if not bool(neon_state.get("signature", false)):
		failures.append("Neon Rain should show the signature layer.")
	if bool(neon_state.get("ripple", false)) or bool(neon_state.get("ribbon", false)) or bool(neon_state.get("pulse", false)):
		failures.append("Neon Rain should disable classic ripple/ribbon/pulse layers.")
	motion_layer.queue_free()

	ems.call("apply_loadout", EMSLoadoutCatalog.get_default_loadout_id())
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("EMS signature layer smoke test passed.")
	quit(0)
