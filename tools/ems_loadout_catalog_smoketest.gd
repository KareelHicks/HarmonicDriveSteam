extends SceneTree

const EMSLoadoutCatalog := preload("res://scripts/ems/EMSLoadoutCatalog.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	var loadouts := EMSLoadoutCatalog.get_core_loadouts()
	if loadouts.size() != 20:
		failures.append("Expected exactly 20 core EMS loadouts, found %d." % loadouts.size())
	var seen_ids: Dictionary = {}
	var seen_catalog_orders: Dictionary = {}
	var seen_signatures: Dictionary = {}
	for loadout in loadouts:
		var loadout_id := str(loadout.get("id", ""))
		var catalog_order := int(loadout.get("catalog_order", 0))
		if loadout_id.is_empty():
			failures.append("Loadout has an empty id.")
		if seen_ids.has(loadout_id):
			failures.append("Duplicate loadout id: %s." % loadout_id)
		seen_ids[loadout_id] = true
		if catalog_order < 1 or catalog_order > 20:
			failures.append("%s has invalid catalog order %d." % [loadout_id, catalog_order])
		if int(loadout.get("progression_section_id", 0)) != catalog_order:
			failures.append("%s is not mapped to progression section %d." % [loadout_id, catalog_order])
		if seen_catalog_orders.has(catalog_order):
			failures.append("Duplicate catalog order: %d." % catalog_order)
		seen_catalog_orders[catalog_order] = true
		if str(loadout.get("type", "")) != EMSLoadoutCatalog.ITEM_TYPE:
			failures.append("%s has wrong item type." % loadout_id)
		if str(loadout.get("acquisition", "")) != EMSLoadoutCatalog.ACQUISITION_INCLUDED:
			failures.append("%s is not included equipment." % loadout_id)
		if not bool(loadout.get("default_owned", false)):
			failures.append("%s is not immediately owned." % loadout_id)
		if int(loadout.get("price", -1)) != 0:
			failures.append("%s should not cost VIBEZ." % loadout_id)
		var preview_path := str(loadout.get("preview_path", ""))
		if preview_path != EMSLoadoutCatalog.get_preview_path(loadout_id):
			failures.append("%s has wrong preview path: %s." % [loadout_id, preview_path])
		if not FileAccess.file_exists(preview_path):
			failures.append("%s preview image is missing at %s." % [loadout_id, preview_path])
		if not FileAccess.file_exists("%s.import" % preview_path):
			failures.append("%s preview import metadata is missing." % loadout_id)
		var preview_texture := load(preview_path) as Texture2D
		if preview_texture == null:
			failures.append("%s preview image did not load as a Texture2D." % loadout_id)
		elif preview_texture.get_width() != 640 or preview_texture.get_height() != 360:
			failures.append("%s preview should be 640x360, got %dx%d." % [loadout_id, preview_texture.get_width(), preview_texture.get_height()])
		var config: Dictionary = loadout.get("config", {}) as Dictionary
		for key in EMSLoadoutCatalog.REQUIRED_CONFIG_KEYS:
			if not config.has(key):
				failures.append("%s missing config key %s." % [loadout_id, key])
		var signature := str(config.get("signature_effect", ""))
		if loadout_id == EMSLoadoutCatalog.get_default_loadout_id():
			if signature != "classic":
				failures.append("Harmonic Core must use the classic signature effect.")
			if not bool(config.get("profile_driven", false)):
				failures.append("Harmonic Core must stay profile-driven.")
		else:
			if signature.is_empty() or signature == "classic":
				failures.append("%s is missing a unique non-classic signature effect." % loadout_id)
			if seen_signatures.has(signature):
				failures.append("Duplicate signature effect: %s." % signature)
			seen_signatures[signature] = true
			if bool(config.get("profile_driven", false)):
				failures.append("%s should not be profile-driven." % loadout_id)
			var mix: Dictionary = config.get("classic_layer_mix", {}) as Dictionary
			if bool(mix.get("ripple", false)) or bool(mix.get("ribbon", false)) or bool(mix.get("pulse", false)):
				failures.append("%s should not keep classic ripple/ribbon/pulse effects enabled." % loadout_id)
			if str(config.get("palette_morph", "")).is_empty() or str(config.get("reaction_model", "")).is_empty():
				failures.append("%s is missing palette morph or reaction model metadata." % loadout_id)
		var weights: Dictionary = config.get("layer_weights", {}) as Dictionary
		for weight_key in ["gradient", "depth", "particles", "fog", "ribbon", "glyph", "ripple", "distortion", "gameplay_shader", "pressure_wave"]:
			if not weights.has(weight_key):
				failures.append("%s missing layer weight %s." % [loadout_id, weight_key])
	if not EMSLoadoutCatalog.is_valid_loadout(EMSLoadoutCatalog.get_default_loadout_id()):
		failures.append("Default EMS loadout id is invalid.")
	if str(EMSLoadoutCatalog.get_default_loadout_id()) != "ems_harmonic_core":
		failures.append("Default EMS loadout should be ems_harmonic_core.")
	if seen_signatures.size() != 19:
		failures.append("Expected 19 unique non-core signature effects, found %d." % seen_signatures.size())
	var visible_loadouts := EMSLoadoutCatalog.get_content_available_core_loadouts()
	var visible_ids: Array[String] = []
	for loadout in visible_loadouts:
		visible_ids.append(str(loadout.get("id", "")))
	if visible_ids.size() != loadouts.size():
		failures.append("Every built-in EMS loadout should be visible; found %d of %d." % [visible_ids.size(), loadouts.size()])
	for loadout_id_variant in seen_ids.keys():
		var loadout_id := str(loadout_id_variant)
		if not visible_ids.has(loadout_id):
			failures.append("Included EMS loadout is hidden: %s." % loadout_id)
	if not EMSLoadoutCatalog.is_layer_type_content_available("signature_thunder_matrix"):
		failures.append("Included signature layers should remain available regardless of section progress.")
	if not EMSLoadoutCatalog.is_loadout_content_available(EMSLoadoutCatalog.get_loadout("ems_chromatic_rift"), 0):
		failures.append("Built-in EMS loadouts should be available independently of section content.")
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("EMS loadout catalog smoke test passed.")
	quit(0)
