extends RefCounted
class_name EMSValidator

const SCHEMA_VERSION := 1
const PACK_TYPE_CONFIG := "ems_config"
const PACK_TYPE_CREATOR := "ems_creator"
const MANIFEST_FILE := "manifest.json"
const CONFIG_FILE := "ems_config.json"
const PROJECT_FILE := "ems_project.json"
const PREVIEW_FILE := "preview.png"
const STEAM_PREVIEW_FILE := "steam_preview.png"
const MEDIA_DIR := "media"

const MAX_LAYERS := 48
const MAX_PARTICLES_PER_LAYER := 500
const MAX_TOTAL_PARTICLES := 1500
const MAX_PREVIEW_BYTES := 2 * 1024 * 1024
const MAX_CONFIG_BYTES := 512 * 1024
const MAX_PROJECT_BYTES := 2 * 1024 * 1024
const MAX_WORKSHOP_PACK_BYTES := 10 * 1024 * 1024
const MAX_PACK_BYTES := 256 * 1024 * 1024
const MAX_MEDIA_FILE_BYTES := 128 * 1024 * 1024
const MAX_CAMERA_SHAKE := 0.35
const MAX_DISTORTION := 0.5
const MAX_BLOOM := 1.0

const ALLOWED_LAYER_TYPES := [
	"solid_color",
	"gradient",
	"crt_gradient",
	"grid",
	"starfield",
	"particles",
	"floating_shapes",
	"tunnel",
	"scanlines",
	"glitch_overlay",
	"beat_pulse",
	"combo_aura",
	"miss_glitch",
	"image",
	"video",
	"signature_neon_rain",
	"signature_digital_snow",
	"signature_plasma_storm",
	"signature_quantum_grid",
	"signature_aurora_drive",
	"signature_cyber_ocean",
	"signature_fractal_space",
	"signature_prism_circuit",
	"signature_void_pulse",
	"signature_solar_bloom",
	"signature_lunar_glass",
	"signature_pixel_nebula",
	"signature_thunder_matrix",
	"signature_chromatic_rift",
	"signature_skyline_mirage",
	"signature_crystal_reactor",
	"signature_gravity_well",
	"signature_hypernova_flow",
	"signature_singularity_bloom",
]

const IMAGE_EXTENSIONS := [
	".png",
	".jpg",
	".jpeg",
	".webp",
	".bmp",
	".tga",
	".svg",
	".gif",
]

const VIDEO_EXTENSIONS := [
	".ogv",
	".ogg",
	".webm",
	".mp4",
	".m4v",
	".mov",
	".avi",
	".mkv",
]

const MEDIA_FIT_MODES := [
	"cover",
	"contain",
	"stretch",
	"tile",
]

const ALLOWED_EVENTS := [
	"song_started",
	"song_section_changed",
	"chart_reactive",
	"audio_reactive",
	"beat",
	"bass_hit",
	"combo_changed",
	"combo_milestone",
	"miss",
	"near_miss",
	"player_hit",
	"player_miss",
	"fever_started",
	"fever_ended",
	"song_ended",
]

const ALLOWED_PLAYER_REACTIVE_MODES := [
	"off",
	"hit",
	"miss",
]

const ALLOWED_BACKGROUND_REGIONS := [
	"gutters",
	"full_background",
]

const ALLOWED_GUTTER_TARGETS := [
	"both",
	"left",
	"right",
]

const ALLOWED_LAYER_LAYOUT_MODES := [
	"pack",
	"custom",
	"reuse",
]

const ALLOWED_ACTIONS := [
	"set_opacity",
	"pulse_opacity",
	"set_color",
	"pulse_scale",
	"burst_particles",
	"increase_bloom",
	"increase_distortion",
	"shake_camera",
	"enable_layer",
	"disable_layer",
	"transition_palette",
]

const FORBIDDEN_EXTENSIONS := [
	".gd",
	".gdc",
	".tscn",
	".scn",
	".tres",
	".res",
	".shader",
	".pck",
	".dll",
	".dylib",
	".so",
	".exe",
	".bat",
	".command",
	".ps1",
	".zip",
]

const TOP_LEVEL_KEYS := {
	"schema_version": true,
	"pack_type": true,
	"pack_id": true,
	"title": true,
	"author": true,
	"description": true,
	"layers": true,
	"events": true,
	"layout": true,
	"palette": true,
	"performance": true,
	"metadata": true,
}

const MANIFEST_KEYS := {
	"schema_version": true,
	"pack_type": true,
	"pack_id": true,
	"title": true,
	"author": true,
	"description": true,
	"min_game_version": true,
	"tags": true,
}

const PROJECT_KEYS := {
	"schema_version": true,
	"pack_type": true,
	"pack_id": true,
	"title": true,
	"author": true,
	"draft_name": true,
	"layers": true,
	"events": true,
	"layout": true,
	"timeline": true,
	"notes": true,
}

const LAYOUT_KEYS := {
	"background_region": true,
	"position": true,
	"size": true,
	"scale": true,
	"rotation": true,
}

const LAYER_LAYOUT_KEYS := {
	"position": true,
	"size": true,
	"scale": true,
	"rotation": true,
}

const LAYER_KEYS := {
	"id": true,
	"type": true,
	"name": true,
	"enabled": true,
	"opacity": true,
	"color": true,
	"colors": true,
	"position": true,
	"size": true,
	"speed": true,
	"direction": true,
	"intensity": true,
	"particle_count": true,
	"shape": true,
	"blend_mode": true,
	"scale": true,
	"rotation": true,
	"frequency": true,
	"thickness": true,
	"spacing": true,
	"seed": true,
	"reactive": true,
	"player_reactive": true,
	"points": true,
	"segments": true,
	"amplitude": true,
	"distortion": true,
	"bloom": true,
	"shake": true,
	"low_motion": true,
	"layout_mode": true,
	"layout_source": true,
	"layout": true,
	"gutter_target": true,
	"media_kind": true,
	"asset_path": true,
	"source_path": true,
	"fit_mode": true,
	"loop": true,
	"signature_effect": true,
}

const EVENT_RULE_KEYS := {
	"event": true,
	"action": true,
	"target": true,
	"params": true,
	"threshold": true,
	"cooldown": true,
}

const PALETTE_KEYS := {
	"colors": true,
	"morph": true,
	"speed": true,
}

const PERFORMANCE_KEYS := {
	"motion_intensity": true,
	"particle_intensity": true,
	"audio_reactive": true,
	"estimated_cost": true,
}


static func validate_pack_folder(folder_path: String) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var metrics := {
		"file_bytes": 0,
		"layer_count": 0,
		"total_particles": 0,
		"performance_warning": "Low",
		"media_files": 0,
		"video_files": 0,
	}
	var folder := folder_path.strip_edges()
	if folder.is_empty() or not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(folder)):
		return _result(false, ["Pack folder does not exist: %s" % folder], warnings, {}, {}, {}, "", metrics)

	_scan_pack_files(folder, errors, metrics)
	if int(metrics.get("file_bytes", 0)) > MAX_WORKSHOP_PACK_BYTES:
		warnings.append("Pack exceeds the 10 MB Steam Workshop-safe size; video-heavy packs should be tested locally instead of uploaded.")
	if int(metrics.get("file_bytes", 0)) > MAX_PACK_BYTES:
		errors.append("Pack exceeds the 256 MB local safety limit.")
	if int(metrics.get("video_files", 0)) > 0:
		warnings.append("Video EMS layers are local-only for testing; Steam Workshop uploads are not supported for video packs because of large file sizes and decoder limits.")

	var manifest_path := folder.path_join(MANIFEST_FILE)
	var config_path := folder.path_join(CONFIG_FILE)
	var preview_path := folder.path_join(PREVIEW_FILE)
	if not FileAccess.file_exists(manifest_path):
		errors.append("Missing manifest.json.")
	if not FileAccess.file_exists(config_path):
		errors.append("Missing ems_config.json.")
	if not FileAccess.file_exists(preview_path):
		errors.append("Missing preview.png.")
	elif _file_size(preview_path) > MAX_PREVIEW_BYTES:
		errors.append("preview.png exceeds the 2 MB size limit.")

	var manifest_load := _load_json_dict(manifest_path, 64 * 1024)
	var config_load := _load_json_dict(config_path, MAX_CONFIG_BYTES)
	var manifest: Dictionary = manifest_load.get("value", {}) as Dictionary
	var config: Dictionary = config_load.get("value", {}) as Dictionary
	if not bool(manifest_load.get("ok", false)):
		errors.append(str(manifest_load.get("error", "Failed to parse manifest.json.")))
	if not bool(config_load.get("ok", false)):
		errors.append(str(config_load.get("error", "Failed to parse ems_config.json.")))

	if not manifest.is_empty():
		_validate_manifest(manifest, errors)
	if not config.is_empty():
		config = validate_config(config)
		for err in (config.get("_validation_errors", []) as Array):
			errors.append(str(err))
		var source_path_layers := _layers_with_source_paths(config.get("layers", []))
		for layer_id in source_path_layers:
			errors.append("Pack config cannot contain source_path for layer %s; export media into media/ and use asset_path." % str(layer_id))
		if _config_has_video_layer(config):
			warnings.append("Video EMS layers are local-only for testing; Steam Workshop uploads are not supported for video packs because of large file sizes and decoder limits.")
		metrics["layer_count"] = int(config.get("_layer_count", 0))
		metrics["total_particles"] = int(config.get("_total_particles", 0))
		metrics["performance_warning"] = str(config.get("_performance_warning", "Low"))
		config.erase("_validation_errors")
		config.erase("_layer_count")
		config.erase("_total_particles")
		config.erase("_performance_warning")

	var manifest_type := str(manifest.get("pack_type", "")).strip_edges()
	var config_type := str(config.get("pack_type", "")).strip_edges()
	var pack_type := config_type if not config_type.is_empty() else manifest_type
	if not manifest_type.is_empty() and not config_type.is_empty() and manifest_type != config_type:
		errors.append("manifest.json and ems_config.json pack_type values do not match.")
	if pack_type == PACK_TYPE_CREATOR:
		var project_path := folder.path_join(PROJECT_FILE)
		if not FileAccess.file_exists(project_path):
			errors.append("Creator packs must include ems_project.json.")
		elif _file_size(project_path) > MAX_PROJECT_BYTES:
			errors.append("ems_project.json exceeds the 2 MB size limit.")
	elif FileAccess.file_exists(folder.path_join(PROJECT_FILE)) and pack_type == PACK_TYPE_CONFIG:
		errors.append("Config packs cannot include ems_project.json.")

	var project: Dictionary = {}
	if FileAccess.file_exists(folder.path_join(PROJECT_FILE)):
		var project_load := _load_json_dict(folder.path_join(PROJECT_FILE), MAX_PROJECT_BYTES)
		if not bool(project_load.get("ok", false)):
			errors.append(str(project_load.get("error", "Failed to parse ems_project.json.")))
		else:
			project = project_load.get("value", {}) as Dictionary
			_validate_project(project, errors)

	var id_source := str(config.get("pack_id", manifest.get("pack_id", folder.get_file()))).strip_edges()
	var sanitized_id := sanitize_pack_id(id_source)
	if sanitized_id.is_empty():
		errors.append("Pack id is empty after sanitization.")
	else:
		manifest["pack_id"] = sanitized_id
		config["pack_id"] = sanitized_id
		if not project.is_empty():
			project["pack_id"] = sanitized_id

	return _result(errors.is_empty(), errors, warnings, manifest, config, project, preview_path, metrics)


static func validate_config(config: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var sanitized := _sanitize_dictionary(config, TOP_LEVEL_KEYS, "/ems_config", errors)
	_require_int(sanitized, "schema_version", SCHEMA_VERSION, "/schema_version", errors)
	var pack_type := str(sanitized.get("pack_type", "")).strip_edges()
	if pack_type not in [PACK_TYPE_CONFIG, PACK_TYPE_CREATOR]:
		errors.append("pack_type must be ems_config or ems_creator.")
	sanitized["pack_type"] = pack_type
	sanitized["pack_id"] = sanitize_pack_id(str(sanitized.get("pack_id", "community_ems")))
	sanitized["title"] = _clean_text(str(sanitized.get("title", "Community EMS")), 80)
	sanitized["author"] = _clean_text(str(sanitized.get("author", "Unknown Creator")), 60)
	sanitized["description"] = _clean_text(str(sanitized.get("description", "")), 240)
	_validate_json_strings(sanitized, "/ems_config", errors)

	var layer_ids: Dictionary = {}
	var layers_out: Array[Dictionary] = []
	var total_particles := 0
	var layer_values: Variant = sanitized.get("layers", [])
	if not (layer_values is Array):
		errors.append("layers must be an array.")
	else:
		var layers: Array = layer_values
		if layers.size() > MAX_LAYERS:
			errors.append("EMS packs can contain at most %d layers." % MAX_LAYERS)
		for index in range(mini(layers.size(), MAX_LAYERS)):
			if layers[index] is not Dictionary:
				errors.append("Layer %d must be an object." % index)
				continue
			var layer := _sanitize_layer(layers[index] as Dictionary, index, errors)
			var layer_id := str(layer.get("id", ""))
			if layer_ids.has(layer_id):
				errors.append("Duplicate layer id: %s." % layer_id)
			layer_ids[layer_id] = true
			total_particles += int(layer.get("particle_count", 0))
			layers_out.append(layer)
		for index in range(layers_out.size()):
			var layer := layers_out[index]
			var layout_mode := str(layer.get("layout_mode", "pack"))
			var layout_source := str(layer.get("layout_source", ""))
			if layout_mode == "reuse":
				if layout_source.is_empty() or not layer_ids.has(layout_source) or layout_source == str(layer.get("id", "")):
					errors.append("Layer %s has invalid layout_source: %s." % [str(layer.get("id", "")), layout_source])
					layer["layout_mode"] = "pack"
					layer["layout_source"] = ""
			else:
				layer["layout_source"] = ""
			layers_out[index] = layer
	if total_particles > MAX_TOTAL_PARTICLES:
		errors.append("EMS packs can use at most %d particles total." % MAX_TOTAL_PARTICLES)
	sanitized["layers"] = layers_out

	var events_out: Array[Dictionary] = []
	var events_value: Variant = sanitized.get("events", [])
	if events_value is Array:
		for index in range(events_value.size()):
			if events_value[index] is not Dictionary:
				errors.append("Event rule %d must be an object." % index)
				continue
			events_out.append(_sanitize_event_rule(events_value[index] as Dictionary, layer_ids, index, errors))
	elif events_value != null:
		errors.append("events must be an array.")
	sanitized["events"] = events_out

	sanitized["layout"] = _sanitize_layout(sanitized.get("layout", {}), errors)
	sanitized["palette"] = _sanitize_palette(sanitized.get("palette", {}), errors)
	sanitized["performance"] = _sanitize_performance(sanitized.get("performance", {}), total_particles)
	sanitized["_validation_errors"] = errors
	sanitized["_layer_count"] = layers_out.size()
	sanitized["_total_particles"] = total_particles
	sanitized["_performance_warning"] = _performance_warning(layers_out.size(), total_particles, sanitized["performance"] as Dictionary)
	return sanitized


static func sanitize_pack_id(value: String) -> String:
	var text := value.strip_edges().to_lower()
	var out := ""
	for i in range(text.length()):
		var c := text.substr(i, 1)
		var ok := (c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "_" or c == "-"
		out += c if ok else "_"
	while out.contains("__"):
		out = out.replace("__", "_")
	out = out.strip_edges()
	if out.length() > 72:
		out = out.substr(0, 72)
	return out.strip_edges()


static func _validate_manifest(manifest: Dictionary, errors: Array[String]) -> void:
	_reject_unknown_keys(manifest, MANIFEST_KEYS, "/manifest", errors)
	_require_int(manifest, "schema_version", SCHEMA_VERSION, "/manifest/schema_version", errors)
	var pack_type := str(manifest.get("pack_type", "")).strip_edges()
	if pack_type not in [PACK_TYPE_CONFIG, PACK_TYPE_CREATOR]:
		errors.append("manifest pack_type must be ems_config or ems_creator.")
	_validate_json_strings(manifest, "/manifest", errors)


static func _validate_project(project: Dictionary, errors: Array[String]) -> void:
	_reject_unknown_keys(project, PROJECT_KEYS, "/ems_project", errors)
	_require_int(project, "schema_version", SCHEMA_VERSION, "/ems_project/schema_version", errors)
	var pack_type := str(project.get("pack_type", "")).strip_edges()
	if pack_type not in [PACK_TYPE_CONFIG, PACK_TYPE_CREATOR]:
		errors.append("ems_project pack_type must be ems_config or ems_creator.")
	_validate_json_strings(project, "/ems_project", errors)


static func _scan_pack_files(folder: String, errors: Array[String], metrics: Dictionary) -> void:
	var allowed := {
		MANIFEST_FILE: true,
		CONFIG_FILE: true,
		PROJECT_FILE: true,
		PREVIEW_FILE: true,
		STEAM_PREVIEW_FILE: true,
	}
	var dir := DirAccess.open(folder)
	if dir == null:
		errors.append("Could not open pack folder.")
		return
	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name.is_empty():
			break
		if name == "." or name == "..":
			continue
		if dir.current_is_dir():
			if name == MEDIA_DIR:
				_scan_media_folder(folder.path_join(name), errors, metrics)
			else:
				errors.append("Unsupported EMS pack folder: %s" % name)
			continue
		var lower := name.to_lower()
		if not allowed.has(name):
			errors.append("Unsupported EMS pack file: %s" % name)
		for ext in FORBIDDEN_EXTENSIONS:
			if lower.ends_with(ext):
				errors.append("Forbidden EMS pack file extension: %s" % name)
		metrics["file_bytes"] = int(metrics.get("file_bytes", 0)) + int(_file_size(folder.path_join(name)))
	dir.list_dir_end()


static func _scan_media_folder(media_folder: String, errors: Array[String], metrics: Dictionary) -> void:
	var dir := DirAccess.open(media_folder)
	if dir == null:
		errors.append("Could not open media folder.")
		return
	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name.is_empty():
			break
		if name == "." or name == "..":
			continue
		if dir.current_is_dir():
			errors.append("Nested folders are not allowed inside media/: %s" % name)
			continue
		var lower := name.to_lower()
		var media_path := media_folder.path_join(name)
		for ext in FORBIDDEN_EXTENSIONS:
			if lower.ends_with(ext):
				errors.append("Forbidden EMS media file extension: %s" % name)
		if not _is_allowed_media_extension(lower):
			errors.append("Unsupported EMS media file: %s" % name)
		var size := int(_file_size(media_path))
		if size > MAX_MEDIA_FILE_BYTES:
			errors.append("EMS media file exceeds the 128 MB local safety limit: %s" % name)
		if _has_extension(lower, VIDEO_EXTENSIONS):
			metrics["video_files"] = int(metrics.get("video_files", 0)) + 1
		metrics["media_files"] = int(metrics.get("media_files", 0)) + 1
		metrics["file_bytes"] = int(metrics.get("file_bytes", 0)) + size
	dir.list_dir_end()


static func _load_json_dict(path: String, max_bytes: int) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {"ok": false, "value": {}, "error": "File not found: %s" % path}
	if _file_size(path) > max_bytes:
		return {"ok": false, "value": {}, "error": "%s exceeds size limit." % path.get_file()}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "value": {}, "error": "Failed to open %s." % path.get_file()}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is not Dictionary:
		return {"ok": false, "value": {}, "error": "%s must contain a JSON object." % path.get_file()}
	return {"ok": true, "value": parsed as Dictionary, "error": ""}


static func _sanitize_layer(layer: Dictionary, index: int, errors: Array[String]) -> Dictionary:
	var sanitized := _sanitize_dictionary(layer, LAYER_KEYS, "/layers/%d" % index, errors)
	var layer_type := str(sanitized.get("type", "")).strip_edges()
	if layer_type not in ALLOWED_LAYER_TYPES:
		errors.append("Unknown EMS layer type at /layers/%d: %s" % [index, layer_type])
	sanitized["type"] = layer_type
	var layer_id := sanitize_pack_id(str(sanitized.get("id", "layer_%d" % index)))
	if layer_id.is_empty():
		layer_id = "layer_%d" % index
	sanitized["id"] = layer_id
	sanitized["name"] = _clean_text(str(sanitized.get("name", layer_id)), 64)
	sanitized["enabled"] = bool(sanitized.get("enabled", true))
	sanitized["opacity"] = _clamp_number(sanitized.get("opacity", 1.0), 0.0, 1.0)
	sanitized["speed"] = _clamp_number(sanitized.get("speed", 0.2), -4.0, 4.0)
	sanitized["direction"] = _clamp_number(sanitized.get("direction", 0.0), -360.0, 360.0)
	sanitized["intensity"] = _clamp_number(sanitized.get("intensity", 1.0), 0.0, 2.0)
	sanitized["scale"] = _clamp_number(sanitized.get("scale", 1.0), 0.05, 8.0)
	sanitized["rotation"] = _clamp_number(sanitized.get("rotation", 0.0), -360.0, 360.0)
	sanitized["frequency"] = _clamp_number(sanitized.get("frequency", 1.0), 0.0, 20.0)
	sanitized["thickness"] = _clamp_number(sanitized.get("thickness", 2.0), 0.5, 32.0)
	sanitized["spacing"] = _clamp_number(sanitized.get("spacing", 42.0), 4.0, 240.0)
	sanitized["points"] = int(_clamp_number(sanitized.get("points", 6), 3.0, 64.0))
	sanitized["segments"] = int(_clamp_number(sanitized.get("segments", 12), 1.0, 96.0))
	sanitized["amplitude"] = _clamp_number(sanitized.get("amplitude", 0.25), 0.0, 2.0)
	sanitized["distortion"] = _clamp_number(sanitized.get("distortion", 0.0), 0.0, MAX_DISTORTION)
	sanitized["bloom"] = _clamp_number(sanitized.get("bloom", 0.0), 0.0, MAX_BLOOM)
	sanitized["shake"] = _clamp_number(sanitized.get("shake", 0.0), 0.0, MAX_CAMERA_SHAKE)
	sanitized["seed"] = int(_clamp_number(sanitized.get("seed", index * 101), 0.0, 999999999.0))
	sanitized["reactive"] = bool(sanitized.get("reactive", true))
	var player_reactive := str(sanitized.get("player_reactive", "off")).strip_edges().to_lower()
	if player_reactive not in ALLOWED_PLAYER_REACTIVE_MODES:
		errors.append("Layer %s has invalid player_reactive mode: %s." % [layer_id, player_reactive])
		player_reactive = "off"
	sanitized["player_reactive"] = player_reactive
	var gutter_target := str(sanitized.get("gutter_target", "both")).strip_edges().to_lower()
	if gutter_target not in ALLOWED_GUTTER_TARGETS:
		errors.append("Layer %s has invalid gutter_target: %s." % [layer_id, gutter_target])
		gutter_target = "both"
	sanitized["gutter_target"] = gutter_target
	sanitized["low_motion"] = bool(sanitized.get("low_motion", false))
	var raw_particles := _numeric_or_default(sanitized.get("particle_count", _default_particles_for_type(layer_type)), float(_default_particles_for_type(layer_type)))
	if raw_particles > float(MAX_PARTICLES_PER_LAYER):
		errors.append("Layer %s exceeds max particles per layer." % layer_id)
	var particles := int(clampf(raw_particles, 0.0, float(MAX_PARTICLES_PER_LAYER)))
	sanitized["particle_count"] = particles if layer_type in ["particles", "starfield", "floating_shapes"] else 0
	var media_kind := str(sanitized.get("media_kind", "")).strip_edges().to_lower()
	if layer_type == "image":
		media_kind = "image"
	elif layer_type == "video":
		media_kind = "video"
	elif media_kind not in ["", "image", "video"]:
		errors.append("Layer %s has invalid media_kind: %s." % [layer_id, media_kind])
		media_kind = ""
	sanitized["media_kind"] = media_kind
	sanitized["asset_path"] = _sanitize_media_asset_path(str(sanitized.get("asset_path", "")), media_kind, layer_id, errors)
	sanitized["source_path"] = _sanitize_media_source_path(str(sanitized.get("source_path", "")), media_kind, layer_id, errors)
	var fit_mode := str(sanitized.get("fit_mode", "cover")).strip_edges().to_lower()
	if fit_mode not in MEDIA_FIT_MODES:
		errors.append("Layer %s has invalid fit_mode: %s." % [layer_id, fit_mode])
		fit_mode = "cover"
	sanitized["fit_mode"] = fit_mode
	sanitized["loop"] = bool(sanitized.get("loop", true))
	sanitized["signature_effect"] = _signature_effect_for_layer_type(layer_type, str(sanitized.get("signature_effect", "")))
	sanitized["color"] = _sanitize_color_value(sanitized.get("color", "#55DFFFCC"), "/layers/%d/color" % index, errors)
	sanitized["colors"] = _sanitize_color_array(sanitized.get("colors", []), "/layers/%d/colors" % index, errors)
	if (sanitized["colors"] as Array).is_empty():
		sanitized["colors"] = [sanitized["color"], "#FF4DE1CC", "#FFE66DCC"]
	sanitized["position"] = _sanitize_vec2(sanitized.get("position", [0.5, 0.5]), Vector2(0, 0), Vector2(1, 1))
	sanitized["size"] = _sanitize_vec2(sanitized.get("size", [1.0, 1.0]), Vector2(0.01, 0.01), Vector2(2.0, 2.0))
	var layout_mode := str(sanitized.get("layout_mode", "pack")).strip_edges().to_lower()
	if layout_mode not in ALLOWED_LAYER_LAYOUT_MODES:
		errors.append("Layer %s has invalid layout_mode: %s." % [layer_id, layout_mode])
		layout_mode = "pack"
	sanitized["layout_mode"] = layout_mode
	sanitized["layout_source"] = sanitize_pack_id(str(sanitized.get("layout_source", "")))
	sanitized["layout"] = _sanitize_layer_layout(sanitized.get("layout", {}), index, errors)
	return sanitized


static func _sanitize_media_asset_path(value: String, media_kind: String, layer_id: String, errors: Array[String]) -> String:
	var path := value.strip_edges().replace("\\", "/")
	if path.is_empty():
		return ""
	if media_kind not in ["image", "video"]:
		errors.append("Layer %s cannot use asset_path without image or video media_kind." % layer_id)
		return ""
	if path.begins_with("/") or path.begins_with("res://") or path.begins_with("user://") or path.contains("://") or path.contains("../") or path.contains(":"):
		errors.append("Layer %s has unsafe media asset_path. Use media/<file>." % layer_id)
		return ""
	if not path.begins_with("%s/" % MEDIA_DIR):
		errors.append("Layer %s media asset_path must live under media/." % layer_id)
		return ""
	var file_name := path.get_file()
	if file_name.is_empty() or file_name != sanitize_media_file_name(file_name):
		errors.append("Layer %s media asset_path has an unsafe file name." % layer_id)
		return ""
	if media_kind == "image" and not _has_extension(path.to_lower(), IMAGE_EXTENSIONS):
		errors.append("Layer %s image asset_path uses an unsupported extension." % layer_id)
		return ""
	if media_kind == "video" and not _has_extension(path.to_lower(), VIDEO_EXTENSIONS):
		errors.append("Layer %s video asset_path uses an unsupported extension." % layer_id)
		return ""
	return "%s/%s" % [MEDIA_DIR, file_name]


static func _sanitize_media_source_path(value: String, media_kind: String, layer_id: String, errors: Array[String]) -> String:
	var path := value.strip_edges()
	if path.is_empty():
		return ""
	if media_kind not in ["image", "video"]:
		errors.append("Layer %s cannot use source_path without image or video media_kind." % layer_id)
		return ""
	var normalized := path.replace("\\", "/")
	var lower := normalized.to_lower()
	if lower.begins_with("res://") or lower.begins_with("http://") or lower.begins_with("https://") or lower.contains("../") or lower.contains("..\\"):
		errors.append("Layer %s has unsafe media source_path." % layer_id)
		return ""
	if media_kind == "image" and not _has_extension(lower, IMAGE_EXTENSIONS):
		errors.append("Layer %s image source_path uses an unsupported extension." % layer_id)
		return ""
	if media_kind == "video" and not _has_extension(lower, VIDEO_EXTENSIONS):
		errors.append("Layer %s video source_path uses an unsupported extension." % layer_id)
		return ""
	return normalized


static func sanitize_media_file_name(value: String) -> String:
	var base := value.get_file().strip_edges()
	var extension := base.get_extension().to_lower()
	var stem := base.get_basename()
	var safe_stem := sanitize_pack_id(stem)
	if safe_stem.is_empty():
		safe_stem = "media"
	if extension.is_empty():
		return safe_stem
	return "%s.%s" % [safe_stem, extension]


static func _signature_effect_for_layer_type(layer_type: String, fallback: String) -> String:
	if layer_type.begins_with("signature_"):
		return layer_type.trim_prefix("signature_")
	return fallback.strip_edges().to_lower()


static func _sanitize_event_rule(rule: Dictionary, layer_ids: Dictionary, index: int, errors: Array[String]) -> Dictionary:
	var sanitized := _sanitize_dictionary(rule, EVENT_RULE_KEYS, "/events/%d" % index, errors)
	var event_name := str(sanitized.get("event", "")).strip_edges()
	var action := str(sanitized.get("action", "")).strip_edges()
	var target := str(sanitized.get("target", "")).strip_edges()
	if event_name not in ALLOWED_EVENTS:
		errors.append("Unknown EMS event at /events/%d: %s" % [index, event_name])
	if action not in ALLOWED_ACTIONS:
		errors.append("Unknown EMS action at /events/%d: %s" % [index, action])
	if target != "*" and not layer_ids.has(target):
		errors.append("EMS action target must be an EMS layer id: %s" % target)
	sanitized["event"] = event_name
	sanitized["action"] = action
	sanitized["target"] = target
	sanitized["threshold"] = _clamp_number(sanitized.get("threshold", 0.0), 0.0, 1.0)
	sanitized["cooldown"] = _clamp_number(sanitized.get("cooldown", 0.0), 0.0, 30.0)
	var params := {}
	if sanitized.get("params", {}) is Dictionary:
		params = sanitized.get("params", {}) as Dictionary
	params = _sanitize_action_params(params)
	sanitized["params"] = params
	return sanitized


static func _sanitize_action_params(params: Dictionary) -> Dictionary:
	var out := {}
	for key_variant in params.keys():
		var key := str(key_variant)
		var value: Variant = params[key_variant]
		match key:
			"opacity":
				out[key] = _clamp_number(value, 0.0, 1.0)
			"duration":
				out[key] = _clamp_number(value, 0.02, 8.0)
			"scale":
				out[key] = _clamp_number(value, 0.1, 4.0)
			"count":
				out[key] = int(_clamp_number(value, 0.0, float(MAX_PARTICLES_PER_LAYER)))
			"amount":
				out[key] = _clamp_number(value, 0.0, 1.0)
			"color":
				if value is String and _is_valid_hex_color(value):
					out[key] = value
			"colors":
				var color_errors: Array[String] = []
				out[key] = _sanitize_color_array(value, "/events/params/colors", color_errors)
	return out


static func _sanitize_layout(value: Variant, errors: Array[String]) -> Dictionary:
	var layout := {}
	if value is Dictionary:
		layout = _sanitize_dictionary(value as Dictionary, LAYOUT_KEYS, "/layout", errors)
	var region := str(layout.get("background_region", "gutters")).strip_edges().to_lower()
	if region not in ALLOWED_BACKGROUND_REGIONS:
		errors.append("layout/background_region must be gutters or full_background.")
		region = "gutters"
	layout["background_region"] = region
	layout["position"] = _sanitize_vec2(layout.get("position", [0.5, 0.5]), Vector2(0, 0), Vector2(1, 1))
	layout["size"] = _sanitize_vec2(layout.get("size", [1.0, 1.0]), Vector2(0.05, 0.05), Vector2(2.0, 2.0))
	layout["scale"] = _clamp_number(layout.get("scale", 1.0), 0.10, 4.0)
	layout["rotation"] = _clamp_number(layout.get("rotation", 0.0), -360.0, 360.0)
	return layout


static func _sanitize_layer_layout(value: Variant, index: int, errors: Array[String]) -> Dictionary:
	var layout := {}
	if value is Dictionary:
		layout = _sanitize_dictionary(value as Dictionary, LAYER_LAYOUT_KEYS, "/layers/%d/layout" % index, errors)
	layout["position"] = _sanitize_vec2(layout.get("position", [0.5, 0.5]), Vector2(0, 0), Vector2(1, 1))
	layout["size"] = _sanitize_vec2(layout.get("size", [1.0, 1.0]), Vector2(0.05, 0.05), Vector2(2.0, 2.0))
	layout["scale"] = _clamp_number(layout.get("scale", 1.0), 0.10, 4.0)
	layout["rotation"] = _clamp_number(layout.get("rotation", 0.0), -360.0, 360.0)
	return layout


static func _sanitize_palette(value: Variant, errors: Array[String]) -> Dictionary:
	var palette := {}
	if value is Dictionary:
		palette = _sanitize_dictionary(value as Dictionary, PALETTE_KEYS, "/palette", errors)
	var colors := _sanitize_color_array(palette.get("colors", []), "/palette/colors", errors)
	if colors.is_empty():
		colors = ["#55DFFFFF", "#FF4DE1FF", "#FFE66DFF"]
	palette["colors"] = colors
	palette["morph"] = _clean_text(str(palette.get("morph", "smooth")), 32)
	palette["speed"] = _clamp_number(palette.get("speed", 0.25), 0.0, 4.0)
	return palette


static func _sanitize_performance(value: Variant, total_particles: int) -> Dictionary:
	var perf := {}
	if value is Dictionary:
		var perf_errors: Array[String] = []
		perf = _sanitize_dictionary(value as Dictionary, PERFORMANCE_KEYS, "/performance", perf_errors)
	perf["motion_intensity"] = _clamp_number(perf.get("motion_intensity", 0.65), 0.0, 1.0)
	perf["particle_intensity"] = _clamp_number(perf.get("particle_intensity", clampf(float(total_particles) / float(MAX_TOTAL_PARTICLES), 0.0, 1.0)), 0.0, 1.0)
	perf["audio_reactive"] = bool(perf.get("audio_reactive", true))
	perf["estimated_cost"] = _clamp_number(perf.get("estimated_cost", 0.0), 0.0, 1.0)
	return perf


static func _performance_warning(layer_count: int, total_particles: int, perf: Dictionary) -> String:
	var score := 0.0
	score += float(layer_count) / float(MAX_LAYERS) * 0.42
	score += float(total_particles) / float(MAX_TOTAL_PARTICLES) * 0.38
	score += float(perf.get("motion_intensity", 0.0)) * 0.12
	score += float(perf.get("estimated_cost", 0.0)) * 0.08
	if score >= 0.68:
		return "High"
	if score >= 0.34:
		return "Medium"
	return "Low"


static func _sanitize_dictionary(value: Dictionary, allowed_keys: Dictionary, path: String, errors: Array[String]) -> Dictionary:
	_reject_unknown_keys(value, allowed_keys, path, errors)
	var out := {}
	for key_variant in value.keys():
		var key := str(key_variant)
		if allowed_keys.has(key):
			out[key] = value[key_variant]
	return out


static func _reject_unknown_keys(value: Dictionary, allowed_keys: Dictionary, path: String, errors: Array[String]) -> void:
	for key_variant in value.keys():
		var key := str(key_variant)
		if not allowed_keys.has(key):
			errors.append("Unknown property rejected at %s/%s." % [path, key])


static func _require_int(value: Dictionary, key: String, expected: int, path: String, errors: Array[String]) -> void:
	if int(value.get(key, -1)) != expected:
		errors.append("%s must be %d." % [path, expected])


static func _validate_json_strings(value: Variant, path: String, errors: Array[String]) -> void:
	match typeof(value):
		TYPE_DICTIONARY:
			var dict := value as Dictionary
			for key_variant in dict.keys():
				_validate_json_strings(dict[key_variant], "%s/%s" % [path, str(key_variant)], errors)
		TYPE_ARRAY:
			var arr := value as Array
			for i in range(arr.size()):
				_validate_json_strings(arr[i], "%s/%d" % [path, i], errors)
		TYPE_STRING:
			var text := str(value)
			if path.ends_with("/source_path") or path.ends_with("/asset_path"):
				return
			if _looks_like_forbidden_path(text):
				errors.append("External or unsafe path rejected at %s." % path)


static func _looks_like_forbidden_path(text: String) -> bool:
	var lower := text.strip_edges().to_lower()
	if lower.is_empty():
		return false
	return lower.begins_with("res://") or lower.begins_with("user://") or lower.begins_with("/") or lower.contains("://") or lower.contains("../") or lower.contains("..\\") or lower.find(":\\") == 1


static func _is_allowed_media_extension(path: String) -> bool:
	return _has_extension(path, IMAGE_EXTENSIONS) or _has_extension(path, VIDEO_EXTENSIONS)


static func _has_extension(path: String, extensions: Array) -> bool:
	var lower := path.to_lower()
	for ext in extensions:
		if lower.ends_with(str(ext)):
			return true
	return false


static func _config_has_video_layer(config: Dictionary) -> bool:
	var layers: Variant = config.get("layers", [])
	if layers is not Array:
		return false
	for layer_variant in layers:
		if layer_variant is not Dictionary:
			continue
		var layer := layer_variant as Dictionary
		if str(layer.get("type", "")) == "video" or str(layer.get("media_kind", "")) == "video":
			return true
	return false


static func _layers_with_source_paths(layers: Variant) -> Array[String]:
	var ids: Array[String] = []
	if layers is not Array:
		return ids
	for layer_variant in layers:
		if layer_variant is not Dictionary:
			continue
		var layer := layer_variant as Dictionary
		if not str(layer.get("source_path", "")).strip_edges().is_empty():
			ids.append(str(layer.get("id", "unknown")))
	return ids


static func _sanitize_color_value(value: Variant, path: String, errors: Array[String]) -> String:
	if value is String and _is_valid_hex_color(value):
		return str(value)
	errors.append("Invalid color at %s. Use #RRGGBB or #RRGGBBAA." % path)
	return "#55DFFFFF"


static func _sanitize_color_array(value: Variant, path: String, errors: Array[String]) -> Array[String]:
	var out: Array[String] = []
	if value is not Array:
		return out
	var arr := value as Array
	for i in range(mini(arr.size(), 16)):
		if arr[i] is String and _is_valid_hex_color(arr[i]):
			out.append(str(arr[i]))
		else:
			errors.append("Invalid color at %s/%d. Use #RRGGBB or #RRGGBBAA." % [path, i])
	return out


static func _is_valid_hex_color(value: String) -> bool:
	if not value.begins_with("#"):
		return false
	var hex := value.substr(1)
	if hex.length() not in [6, 8]:
		return false
	for i in range(hex.length()):
		var c := hex.substr(i, 1).to_lower()
		var ok := (c >= "0" and c <= "9") or (c >= "a" and c <= "f")
		if not ok:
			return false
	return true


static func _sanitize_vec2(value: Variant, min_value: Vector2, max_value: Vector2) -> Array:
	var x := 0.0
	var y := 0.0
	if value is Array and (value as Array).size() >= 2:
		x = _clamp_number((value as Array)[0], min_value.x, max_value.x)
		y = _clamp_number((value as Array)[1], min_value.y, max_value.y)
	elif value is Dictionary:
		var dict := value as Dictionary
		x = _clamp_number(dict.get("x", 0.0), min_value.x, max_value.x)
		y = _clamp_number(dict.get("y", 0.0), min_value.y, max_value.y)
	return [x, y]


static func _clamp_number(value: Variant, min_value: float, max_value: float) -> float:
	return clampf(_numeric_or_default(value, min_value), min_value, max_value)


static func _numeric_or_default(value: Variant, default_value: float) -> float:
	if typeof(value) in [TYPE_INT, TYPE_FLOAT]:
		return float(value)
	if value is String and str(value).is_valid_float():
		return float(value)
	return default_value


static func _default_particles_for_type(layer_type: String) -> int:
	match layer_type:
		"starfield":
			return 180
		"particles":
			return 120
		"floating_shapes":
			return 36
		_:
			return 0


static func _clean_text(value: String, max_length: int) -> String:
	var text := value.strip_edges().replace("\n", " ").replace("\r", " ").replace("\t", " ")
	while text.contains("  "):
		text = text.replace("  ", " ")
	if text.length() > max_length:
		text = text.substr(0, max_length)
	return text


static func _file_size(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	return int(file.get_length())


static func _result(ok: bool, errors: Array[String], warnings: Array[String], manifest: Dictionary, config: Dictionary, project: Dictionary, preview_path: String, metrics: Dictionary) -> Dictionary:
	return {
		"ok": ok,
		"errors": errors,
		"warnings": warnings,
		"manifest": manifest,
		"config": config,
		"project": project,
		"preview_path": preview_path,
		"metrics": metrics,
	}
