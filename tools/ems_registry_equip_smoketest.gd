extends SceneTree

const EMSLoadoutCatalog := preload("res://scripts/ems/EMSLoadoutCatalog.gd")
const EMSPackLoader := preload("res://systems/ems/EMSPackLoader.gd")
const EMSValidator := preload("res://systems/ems/EMSValidator.gd")


func _initialize() -> void:
	await process_frame
	EMSPackLoader.cleanup_automated_test_packs()
	var failures: Array[String] = []
	var profile_store := root.get_node("ProfileStore")
	var progression_manager := root.get_node("ProgressionManager")
	var original_progression: Dictionary = (profile_store.call("get_progression_data") as Dictionary).duplicate(true)
	var registry := root.get_node("EMSRegistry")
	var probe_folder := _create_local_pack("registry_visible_probe")
	var workshop_probe_folder := _create_workshop_pack("123456789012345678")
	var invalid_probe_folder := _create_invalid_local_pack("invalid_visible_probe")
	registry.call("reload")
	var built_in_entries: Array = registry.call("get_entries_by_source", "built_in") as Array
	var unlocked_entries: Array = registry.call("get_entries_by_source", "unlocked") as Array
	if built_in_entries.size() != EMSLoadoutCatalog.get_core_loadouts().size():
		failures.append("EMS registry should expose every included loadout as built-in equipment.")
	if not unlocked_entries.is_empty():
		failures.append("EMS registry still exposes a progression-gated unlocked source.")
	for loadout in EMSLoadoutCatalog.get_core_loadouts():
		var loadout_id := str(loadout.get("id", ""))
		var built_in_entry: Dictionary = registry.call("get_entry", loadout_id) as Dictionary
		if built_in_entry.is_empty():
			failures.append("Built-in EMS registry entry missing for %s." % loadout_id)
			continue
		var expected_preview := EMSLoadoutCatalog.get_preview_path(loadout_id)
		if str(built_in_entry.get("preview_path", "")) != expected_preview:
			failures.append("Built-in EMS %s did not expose preview path %s." % [loadout_id, expected_preview])
		if not FileAccess.file_exists(str(built_in_entry.get("preview_path", ""))):
			failures.append("Built-in EMS %s preview file is missing." % loadout_id)
	var entry_id := "community:local:registry_visible_probe"
	if not bool(registry.call("is_valid_ems", entry_id)):
		failures.append("Local EMS pack did not register as valid.")
	var workshop_entry_id := "community:workshop:registry_workshop_probe"
	var workshop_entry: Dictionary = registry.call("get_entry", workshop_entry_id) as Dictionary
	if workshop_entry.is_empty():
		failures.append("Workshop EMS pack did not register as valid.")
	elif str(workshop_entry.get("workshop_item_id", "")) != "123456789012345678":
		failures.append("Workshop EMS pack did not expose its published file id.")
	var workshop_config: Dictionary = registry.call("get_entry_config", workshop_entry_id) as Dictionary
	if str(workshop_config.get("workshop_item_id", "")) != "123456789012345678":
		failures.append("Workshop EMS runtime config did not expose its published file id.")
	var equip_result: Dictionary = progression_manager.call("equip_item", entry_id) as Dictionary
	if not bool(equip_result.get("ok", false)):
		failures.append("Community EMS did not equip: %s" % str(equip_result.get("message", "")))
	var equipped := progression_manager.call("get_equipped_loadout") as Dictionary
	if str(equipped.get("ems_loadout", "")) != entry_id:
		failures.append("Equipped community EMS id did not persist in progression.")
	if not bool((equipped.get("ems_loadout_config", {}) as Dictionary).get("community_runtime", false)):
		failures.append("Equipped community EMS did not expose community runtime config.")
	if str((equipped.get("ems_loadout_config", {}) as Dictionary).get("community_background_region", "")) != "full_background":
		failures.append("Equipped community EMS did not expose its full-background layout region.")
	for entry_variant in (registry.call("get_entries_by_source", "local") as Array):
		var entry := entry_variant as Dictionary
		if str(entry.get("validation_status", "valid")) == "invalid" or str(entry.get("pack_id", "")) == "invalid_visible_probe":
			failures.append("Invalid local EMS pack appeared in the Loadouts source list.")
	var progression: Dictionary = (profile_store.call("get_progression_data") as Dictionary).duplicate(true)
	var eq: Dictionary = progression.get("equipped_items", {}) as Dictionary
	eq["ems_loadout"] = "community:local:missing_pack"
	progression["equipped_items"] = eq
	profile_store.call("set_progression_data", progression)
	var active := registry.call("get_active_ems") as Dictionary
	if str(active.get("id", "")) != EMSLoadoutCatalog.get_default_loadout_id():
		failures.append("Missing community EMS did not fall back to Harmonic Core.")
	var included_result: Dictionary = progression_manager.call("equip_item", "ems_hypernova_flow") as Dictionary
	if not bool(included_result.get("ok", false)):
		failures.append("Included built-in EMS could not be equipped immediately.")
	profile_store.call("set_progression_data", original_progression)
	if progression_manager.has_method("_load_or_reset"):
		progression_manager.call("_load_or_reset")
	EMSPackLoader.delete_pack_folder(probe_folder)
	EMSPackLoader.delete_pack_folder(workshop_probe_folder)
	EMSPackLoader.delete_pack_folder(invalid_probe_folder)
	registry.call("reload")
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("EMS registry equip smoke test passed.")
	quit(0)


func _create_local_pack(pack_id: String) -> String:
	EMSPackLoader.ensure_user_dirs()
	var folder := EMSPackLoader.LOCAL_ROOT.path_join(pack_id)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	_write_json(folder.path_join(EMSValidator.MANIFEST_FILE), {"schema_version": 1, "pack_type": EMSValidator.PACK_TYPE_CONFIG, "pack_id": pack_id, "title": "Registry Probe Pack", "author": "Automated Test", "description": "Temporary local registry pack.", "min_game_version": "1.0.0", "tags": ["EMS", "Test"]})
	_write_json(folder.path_join(EMSValidator.CONFIG_FILE), {
		"schema_version": 1,
		"pack_type": EMSValidator.PACK_TYPE_CONFIG,
		"pack_id": pack_id,
		"title": "Registry Probe Pack",
		"author": "Automated Test",
		"description": "Temporary local registry pack.",
		"layers": [{"id": "grid", "type": "grid", "name": "Grid", "opacity": 0.7, "color": "#55DFFFFF", "colors": ["#55DFFFFF"], "particle_count": 0}],
		"events": [{"event": "beat", "action": "pulse_opacity", "target": "grid", "params": {"opacity": 0.9, "duration": 0.1}}],
		"layout": {"background_region": "full_background", "position": [0.5, 0.5], "size": [1.0, 1.0], "scale": 1.0, "rotation": 0.0},
		"palette": {"colors": ["#55DFFFFF", "#FF4DE1FF"], "morph": "smooth", "speed": 0.2},
		"performance": {"motion_intensity": 0.4, "particle_intensity": 0.0, "audio_reactive": true, "estimated_cost": 0.1},
	})
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.2, 0.9, 1.0, 1.0))
	image.save_png(folder.path_join(EMSValidator.PREVIEW_FILE))
	return folder


func _create_workshop_pack(workshop_item_id: String) -> String:
	EMSPackLoader.ensure_user_dirs()
	var folder := EMSPackLoader.WORKSHOP_ROOT.path_join(workshop_item_id)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	_write_json(folder.path_join(EMSValidator.MANIFEST_FILE), {"schema_version": 1, "pack_type": EMSValidator.PACK_TYPE_CONFIG, "pack_id": "registry_workshop_probe", "title": "Registry Workshop Probe", "author": "Automated Test", "description": "Temporary workshop registry pack.", "min_game_version": "1.0.0", "tags": ["EMS", "Test"]})
	_write_json(folder.path_join(EMSValidator.CONFIG_FILE), {
		"schema_version": 1,
		"pack_type": EMSValidator.PACK_TYPE_CONFIG,
		"pack_id": "registry_workshop_probe",
		"title": "Registry Workshop Probe",
		"author": "Automated Test",
		"description": "Temporary workshop registry pack.",
		"layers": [{"id": "solid", "type": "solid_color", "name": "Solid", "opacity": 0.35, "color": "#55DFFFFF", "colors": ["#55DFFFFF"], "particle_count": 0}],
		"events": [],
		"layout": {"background_region": "gutters", "position": [0.5, 0.5], "size": [1.0, 1.0], "scale": 1.0, "rotation": 0.0},
		"palette": {"colors": ["#55DFFFFF", "#FF4DE1FF"], "morph": "smooth", "speed": 0.2},
		"performance": {"motion_intensity": 0.3, "particle_intensity": 0.0, "audio_reactive": false, "estimated_cost": 0.1},
	})
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.2, 0.9, 1.0, 1.0))
	image.save_png(folder.path_join(EMSValidator.PREVIEW_FILE))
	return folder


func _create_invalid_local_pack(pack_id: String) -> String:
	EMSPackLoader.ensure_user_dirs()
	var folder := EMSPackLoader.LOCAL_ROOT.path_join(pack_id)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	_write_json(folder.path_join(EMSValidator.MANIFEST_FILE), {"schema_version": 1, "pack_type": EMSValidator.PACK_TYPE_CONFIG, "pack_id": pack_id, "title": "Invalid Probe Pack", "author": "Automated Test", "description": "Temporary invalid pack.", "min_game_version": "1.0.0", "tags": ["EMS", "Test"]})
	return folder


func _write_json(path: String, payload: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(payload, "\t", false))
