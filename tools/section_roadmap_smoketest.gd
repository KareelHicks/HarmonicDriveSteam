extends SceneTree

const EMSLoadoutCatalog := preload("res://scripts/ems/EMSLoadoutCatalog.gd")
const FUTURE_SECTION_ROADMAP := {
	15: {"name": "Spectrum", "loadout_id": "ems_chromatic_rift", "loadout_name": "Chromatic Rift"},
	16: {"name": "Horizon", "loadout_id": "ems_skyline_mirage", "loadout_name": "Skyline Mirage"},
	17: {"name": "Resonance", "loadout_id": "ems_crystal_reactor", "loadout_name": "Crystal Reactor"},
	18: {"name": "Orbit", "loadout_id": "ems_gravity_well", "loadout_name": "Gravity Well"},
	19: {"name": "Hyperdrive", "loadout_id": "ems_hypernova_flow", "loadout_name": "Hypernova Flow"},
	20: {"name": "Singularity", "loadout_id": "ems_singularity_bloom", "loadout_name": "Singularity Bloom"},
}


func _initialize() -> void:
	await process_frame
	var failures: Array[String] = []
	var progression_manager := root.get_node_or_null("ProgressionManager")
	if progression_manager == null:
		failures.append("ProgressionManager autoload was not available.")
	else:
		for section_id_variant in FUTURE_SECTION_ROADMAP.keys():
			var section_id := int(section_id_variant)
			var expected := FUTURE_SECTION_ROADMAP[section_id] as Dictionary
			var section_name := str(progression_manager.call("get_section_display_name", section_id))
			if section_name != str(expected.get("name", "")):
				failures.append("Section %d should be named %s, found %s." % [section_id, expected.get("name", ""), section_name])
			var loadout_id := str(expected.get("loadout_id", ""))
			var loadout := EMSLoadoutCatalog.get_loadout(loadout_id)
			if loadout.is_empty():
				failures.append("Section %d EMS Loadout is missing: %s." % [section_id, loadout_id])
				continue
			if int(loadout.get("progression_section_id", 0)) != section_id:
				failures.append("%s is not mapped to Section %d." % [loadout_id, section_id])
			if str(loadout.get("display_name", "")) != str(expected.get("loadout_name", "")):
				failures.append("Section %d EMS Loadout should be named %s." % [section_id, expected.get("loadout_name", "")])
			if not bool(loadout.get("default_owned", false)):
				failures.append("Section %d EMS Loadout is not immediately available." % section_id)
			var preview_path := str(loadout.get("preview_path", ""))
			if not FileAccess.file_exists(preview_path):
				failures.append("Section %d EMS preview is missing: %s." % [section_id, preview_path])

	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("SECTION_ROADMAP_SMOKETEST_OK")
	quit(0)
