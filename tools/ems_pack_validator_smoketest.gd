extends SceneTree

const EMSValidator := preload("res://systems/ems/EMSValidator.gd")

const ROOT := "user://ems_validator_smoke"


func _initialize() -> void:
	var failures: Array[String] = []
	_prepare_root()
	var valid_config := _write_pack("valid_config", EMSValidator.PACK_TYPE_CONFIG, _valid_config("valid_config"), {}, false)
	if not bool(valid_config.get("ok", false)):
		failures.append("Valid config pack failed validation: %s" % str(valid_config.get("errors", [])))
	var valid_layout: Dictionary = (valid_config.get("config", {}) as Dictionary).get("layout", {}) as Dictionary
	if str(valid_layout.get("background_region", "")) != "full_background":
		failures.append("Valid config layout did not preserve full_background.")
	var valid_layers: Array = (valid_config.get("config", {}) as Dictionary).get("layers", []) as Array
	if valid_layers.size() >= 2:
		var first_layer := valid_layers[0] as Dictionary
		var second_layer := valid_layers[1] as Dictionary
		if str(first_layer.get("layout_mode", "")) != "custom":
			failures.append("Valid config did not preserve a custom layer layout.")
		if str(first_layer.get("gutter_target", "")) != "right":
			failures.append("Valid config did not preserve the layer gutter target.")
		if str(second_layer.get("layout_mode", "")) != "reuse" or str(second_layer.get("layout_source", "")) != "particles":
			failures.append("Valid config did not preserve a reused layer layout source.")
	var valid_creator := _write_pack("valid_creator", EMSValidator.PACK_TYPE_CREATOR, _valid_config("valid_creator", EMSValidator.PACK_TYPE_CREATOR), {"schema_version": 1, "pack_type": EMSValidator.PACK_TYPE_CREATOR, "pack_id": "valid_creator", "layers": [], "events": []}, false)
	if not bool(valid_creator.get("ok", false)):
		failures.append("Valid creator pack failed validation: %s" % str(valid_creator.get("errors", [])))
	var media_pack := _write_media_pack("valid_media_pack", _media_config("valid_media_pack"), {"sample.png": "image", "loop.ogv": "video"})
	if not bool(media_pack.get("ok", false)):
		failures.append("Valid media pack failed validation: %s" % str(media_pack.get("errors", [])))
	if str(media_pack.get("warnings", [])).find("Video EMS layers") < 0:
		failures.append("Video media pack did not emit a Workshop warning.")
	var bad_media_path := _media_config("bad_media_path")
	((bad_media_path["layers"] as Array)[0] as Dictionary)["asset_path"] = "../sample.png"
	_write_media_pack("bad_media_path", bad_media_path, {"sample.png": "image"})
	_expect_reject("bad_media_path", "asset_path", failures)
	var source_path_pack := _media_config("source_path_pack")
	((source_path_pack["layers"] as Array)[0] as Dictionary)["source_path"] = "/tmp/sample.png"
	_write_media_pack("source_path_pack", source_path_pack, {"sample.png": "image"})
	_expect_reject("source_path_pack", "source_path", failures)

	_expect_reject("missing_files", "", failures)
	_write_raw_pack("bad_json", "{ nope", JSON.stringify(_valid_config("bad_json")), true)
	_expect_reject("bad_json", "JSON object", failures)
	var wrong_schema := _valid_config("wrong_schema")
	wrong_schema["schema_version"] = 2
	_write_pack("wrong_schema", EMSValidator.PACK_TYPE_CONFIG, wrong_schema, {}, false)
	_expect_reject("wrong_schema", "schema_version", failures)
	var unknown_layer := _valid_config("unknown_layer")
	(unknown_layer["layers"] as Array)[0]["type"] = "script_node"
	_write_pack("unknown_layer", EMSValidator.PACK_TYPE_CONFIG, unknown_layer, {}, false)
	_expect_reject("unknown_layer", "Unknown EMS layer type", failures)
	var unknown_property := _valid_config("unknown_property")
	(unknown_property["layers"] as Array)[0]["script"] = "nope"
	_write_pack("unknown_property", EMSValidator.PACK_TYPE_CONFIG, unknown_property, {}, false)
	_expect_reject("unknown_property", "Unknown property", failures)
	var bad_color := _valid_config("bad_color")
	(bad_color["layers"] as Array)[0]["color"] = "blue"
	_write_pack("bad_color", EMSValidator.PACK_TYPE_CONFIG, bad_color, {}, false)
	_expect_reject("bad_color", "Invalid color", failures)
	var bad_player_reactive := _valid_config("bad_player_reactive")
	(bad_player_reactive["layers"] as Array)[0]["player_reactive"] = "hit_and_miss"
	_write_pack("bad_player_reactive", EMSValidator.PACK_TYPE_CONFIG, bad_player_reactive, {}, false)
	_expect_reject("bad_player_reactive", "player_reactive", failures)
	var bad_layout := _valid_config("bad_layout")
	(bad_layout["layout"] as Dictionary)["background_region"] = "unsafe_canvas"
	_write_pack("bad_layout", EMSValidator.PACK_TYPE_CONFIG, bad_layout, {}, false)
	_expect_reject("bad_layout", "layout/background_region", failures)
	var bad_layer_layout_mode := _valid_config("bad_layer_layout_mode")
	((bad_layer_layout_mode["layers"] as Array)[0] as Dictionary)["layout_mode"] = "freeform_canvas"
	_write_pack("bad_layer_layout_mode", EMSValidator.PACK_TYPE_CONFIG, bad_layer_layout_mode, {}, false)
	_expect_reject("bad_layer_layout_mode", "invalid layout_mode", failures)
	var bad_layer_layout_source := _valid_config("bad_layer_layout_source")
	((bad_layer_layout_source["layers"] as Array)[1] as Dictionary)["layout_source"] = "missing_layer"
	_write_pack("bad_layer_layout_source", EMSValidator.PACK_TYPE_CONFIG, bad_layer_layout_source, {}, false)
	_expect_reject("bad_layer_layout_source", "invalid layout_source", failures)
	var bad_gutter_target := _valid_config("bad_gutter_target")
	((bad_gutter_target["layers"] as Array)[0] as Dictionary)["gutter_target"] = "middle"
	_write_pack("bad_gutter_target", EMSValidator.PACK_TYPE_CONFIG, bad_gutter_target, {}, false)
	_expect_reject("bad_gutter_target", "gutter_target", failures)
	for unsafe in [
		{"name": "external_url", "value": "https://example.com/evil"},
		{"name": "res_path", "value": "res://evil.png"},
		{"name": "user_path", "value": "user://evil.png"},
		{"name": "absolute_path", "value": "/tmp/evil.png"},
		{"name": "traversal", "value": "../evil.png"},
	]:
		var cfg := _valid_config(str(unsafe.get("name", "")))
		cfg["description"] = str(unsafe.get("value", ""))
		_write_pack(str(unsafe.get("name", "")), EMSValidator.PACK_TYPE_CONFIG, cfg, {}, false)
		_expect_reject(str(unsafe.get("name", "")), "path", failures)
	var forbidden := _write_pack("forbidden_script", EMSValidator.PACK_TYPE_CONFIG, _valid_config("forbidden_script"), {}, true)
	if bool(forbidden.get("ok", false)):
		failures.append("Pack containing .gd was not rejected.")
	var too_many_layers := _valid_config("too_many_layers")
	var layers: Array = too_many_layers["layers"] as Array
	for i in range(EMSValidator.MAX_LAYERS + 1):
		layers.append(_layer("extra_%d" % i, "grid", 0))
	_write_pack("too_many_layers", EMSValidator.PACK_TYPE_CONFIG, too_many_layers, {}, false)
	_expect_reject("too_many_layers", "at most", failures)
	var too_many_particles := _valid_config("too_many_particles")
	(too_many_particles["layers"] as Array)[0]["particle_count"] = EMSValidator.MAX_PARTICLES_PER_LAYER + 1
	_write_pack("too_many_particles", EMSValidator.PACK_TYPE_CONFIG, too_many_particles, {}, false)
	_expect_reject("too_many_particles", "max particles", failures)

	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("EMS pack validator smoke test passed.")
	quit(0)


func _valid_config(pack_id: String, pack_type: String = EMSValidator.PACK_TYPE_CONFIG) -> Dictionary:
	var layers: Array[Dictionary] = [
		_layer("particles", "particles", 24),
		_layer("grid", "grid", 0),
	]
	layers[0]["layout_mode"] = "custom"
	layers[0]["layout"] = {"position": [0.36, 0.44], "size": [0.72, 0.82], "scale": 1.25, "rotation": 19.0}
	layers[0]["gutter_target"] = "right"
	layers[1]["layout_mode"] = "reuse"
	layers[1]["layout_source"] = "particles"
	return {
		"schema_version": 1,
		"pack_type": pack_type,
		"pack_id": pack_id,
		"title": "Smoke EMS",
		"author": "Test",
		"description": "Safe JSON-only EMS pack.",
		"layers": layers,
		"events": [
			{"event": "beat", "action": "pulse_opacity", "target": "particles", "params": {"opacity": 0.9, "duration": 0.1}, "threshold": 0.0, "cooldown": 0.0},
		],
		"layout": {"background_region": "full_background", "position": [0.45, 0.55], "size": [0.80, 1.15], "scale": 1.30, "rotation": 12.0},
		"palette": {"colors": ["#55DFFFFF", "#FF4DE1FF"], "morph": "smooth", "speed": 0.2},
		"performance": {"motion_intensity": 0.5, "particle_intensity": 0.3, "audio_reactive": true, "estimated_cost": 0.2},
	}


func _layer(layer_id: String, layer_type: String, particles: int) -> Dictionary:
	return {
		"id": layer_id,
		"type": layer_type,
		"name": layer_id,
		"opacity": 0.75,
		"color": "#55DFFFFF",
		"colors": ["#55DFFFFF", "#FF4DE1FF"],
		"particle_count": particles,
		"speed": 0.25,
		"reactive": true,
		"player_reactive": "off",
	}


func _media_config(pack_id: String) -> Dictionary:
	return {
		"schema_version": 1,
		"pack_type": EMSValidator.PACK_TYPE_CONFIG,
		"pack_id": pack_id,
		"title": "Media EMS",
		"author": "Test",
		"description": "Media smoke pack.",
		"layers": [
			{"id": "image_layer", "type": "image", "name": "Image", "opacity": 0.80, "color": "#55DFFFFF", "colors": ["#55DFFFFF", "#FF4DE1FF"], "media_kind": "image", "asset_path": "media/sample.png", "fit_mode": "contain", "loop": true, "gutter_target": "left"},
			{"id": "video_layer", "type": "video", "name": "Video", "opacity": 0.80, "color": "#FFE66DFF", "colors": ["#FFE66DFF", "#FF4DE1FF"], "media_kind": "video", "asset_path": "media/loop.ogv", "fit_mode": "cover", "loop": true, "gutter_target": "right"},
			{"id": "signature_layer", "type": "signature_neon_rain", "name": "Neon Rain", "opacity": 0.70, "color": "#55DFFFFF", "colors": ["#55DFFFFF", "#FF4DE1FF"], "signature_effect": "neon_rain", "speed": 0.3},
		],
		"events": [],
		"layout": {"background_region": "gutters", "position": [0.5, 0.5], "size": [1.0, 1.0], "scale": 1.0, "rotation": 0.0},
		"palette": {"colors": ["#55DFFFFF", "#FF4DE1FF"], "morph": "smooth", "speed": 0.2},
		"performance": {"motion_intensity": 0.5, "particle_intensity": 0.3, "audio_reactive": true, "estimated_cost": 0.2},
	}


func _write_pack(name: String, pack_type: String, config: Dictionary, project: Dictionary, include_forbidden: bool) -> Dictionary:
	var folder := ROOT.path_join(name)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var manifest := {"schema_version": 1, "pack_type": pack_type, "pack_id": name, "title": name, "author": "Test", "description": "Smoke", "min_game_version": "1.0.0", "tags": ["EMS"]}
	_write_json(folder.path_join(EMSValidator.MANIFEST_FILE), manifest)
	_write_json(folder.path_join(EMSValidator.CONFIG_FILE), config)
	if pack_type == EMSValidator.PACK_TYPE_CREATOR:
		_write_json(folder.path_join(EMSValidator.PROJECT_FILE), project)
	_write_preview(folder.path_join(EMSValidator.PREVIEW_FILE))
	_write_preview(folder.path_join(EMSValidator.STEAM_PREVIEW_FILE))
	if include_forbidden:
		_write_text(folder.path_join("evil.gd"), "extends Node")
	return EMSValidator.validate_pack_folder(folder)


func _write_media_pack(name: String, config: Dictionary, media_files: Dictionary) -> Dictionary:
	var folder := ROOT.path_join(name)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder.path_join(EMSValidator.MEDIA_DIR)))
	var manifest := {"schema_version": 1, "pack_type": EMSValidator.PACK_TYPE_CONFIG, "pack_id": name, "title": name, "author": "Test", "description": "Smoke", "min_game_version": "1.0.0", "tags": ["EMS"]}
	_write_json(folder.path_join(EMSValidator.MANIFEST_FILE), manifest)
	_write_json(folder.path_join(EMSValidator.CONFIG_FILE), config)
	_write_preview(folder.path_join(EMSValidator.PREVIEW_FILE))
	for file_name in media_files.keys():
		var kind := str(media_files[file_name])
		var path := folder.path_join(EMSValidator.MEDIA_DIR).path_join(str(file_name))
		if kind == "image":
			_write_preview(path)
		else:
			_write_text(path, "video placeholder")
	return EMSValidator.validate_pack_folder(folder)


func _write_raw_pack(name: String, manifest_text: String, config_text: String, include_preview: bool) -> void:
	var folder := ROOT.path_join(name)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	_write_text(folder.path_join(EMSValidator.MANIFEST_FILE), manifest_text)
	_write_text(folder.path_join(EMSValidator.CONFIG_FILE), config_text)
	if include_preview:
		_write_preview(folder.path_join(EMSValidator.PREVIEW_FILE))


func _expect_reject(name: String, needle: String, failures: Array[String]) -> void:
	var validation := EMSValidator.validate_pack_folder(ROOT.path_join(name))
	if bool(validation.get("ok", false)):
		failures.append("%s was not rejected." % name)
		return
	if not needle.is_empty() and not str(validation.get("errors", [])).contains(needle):
		failures.append("%s rejected for the wrong reason: %s" % [name, str(validation.get("errors", []))])


func _prepare_root() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOT))


func _write_json(path: String, payload: Dictionary) -> void:
	_write_text(path, JSON.stringify(payload, "\t", false))


func _write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)


func _write_preview(path: String) -> void:
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.1, 0.7, 1.0, 1.0))
	image.save_png(path)
