extends RefCounted
class_name EMSLayerTemplateStore

const EMSValidator = preload("res://systems/ems/EMSValidator.gd")

const DEFAULT_ROOT := "user://ems/layer_types"
const TEMPLATE_FILE := "custom_layer_types.json"

var _root := DEFAULT_ROOT


func _init(root_path: String = DEFAULT_ROOT) -> void:
	_root = root_path


func ensure_dirs() -> void:
	DirAccess.make_dir_recursive_absolute(_root)


func list_templates() -> Array[Dictionary]:
	ensure_dirs()
	var path := _template_path()
	if not FileAccess.file_exists(path):
		return []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is not Dictionary:
		return []
	var raw_templates: Variant = (parsed as Dictionary).get("templates", [])
	if raw_templates is not Array:
		return []
	var out: Array[Dictionary] = []
	var seen := {}
	var raw_templates_array := raw_templates as Array
	for raw in raw_templates_array:
		if raw is not Dictionary:
			continue
		var template := _sanitize_template(raw as Dictionary)
		var template_id := str(template.get("template_id", ""))
		if template_id.is_empty() or seen.has(template_id):
			continue
		seen[template_id] = true
		out.append(template)
	return out


func save_template(layer: Dictionary, display_name: String = "") -> Dictionary:
	ensure_dirs()
	var layer_copy := _sanitize_layer(layer)
	if layer_copy.is_empty():
		return {"ok": false, "message": "Layer template is invalid.", "template": {}}
	var template_name := display_name.strip_edges()
	if template_name.is_empty():
		template_name = str(layer_copy.get("name", "Custom Layer")).strip_edges()
	if template_name.is_empty():
		template_name = "Custom Layer"
	var template_id := EMSValidator.sanitize_pack_id("%s_%d" % [template_name, Time.get_ticks_msec()])
	var template := {
		"template_id": template_id,
		"name": template_name,
		"base_type": str(layer_copy.get("type", "solid_color")),
		"layer": layer_copy,
		"updated_at": int(Time.get_unix_time_from_system()),
	}
	var templates := list_templates()
	templates.append(template)
	var payload := {
		"schema_version": 1,
		"templates": templates,
	}
	var file := FileAccess.open(_template_path(), FileAccess.WRITE)
	if file == null:
		return {"ok": false, "message": "Could not write custom layer type templates.", "template": {}}
	file.store_string(JSON.stringify(payload, "\t"))
	return {"ok": true, "message": "Custom layer type saved.", "template": template}


func make_layer_instance(template: Dictionary, existing_ids: Array[String], override_name: String = "") -> Dictionary:
	var layer_value: Variant = template.get("layer", {})
	var layer := _sanitize_layer(layer_value if layer_value is Dictionary else {})
	if layer.is_empty():
		return {}
	var name := override_name.strip_edges()
	if name.is_empty():
		name = str(layer.get("name", template.get("name", "Custom Layer"))).strip_edges()
	if name.is_empty():
		name = "Custom Layer"
	layer["name"] = name
	layer["id"] = _unique_layer_id(name, existing_ids)
	layer["layout_mode"] = "pack"
	layer["layout_source"] = ""
	return layer


func _template_path() -> String:
	return _root.path_join(TEMPLATE_FILE)


func _sanitize_template(value: Dictionary) -> Dictionary:
	var raw_layer: Variant = value.get("layer", {})
	var layer := _sanitize_layer(raw_layer if raw_layer is Dictionary else {})
	if layer.is_empty():
		return {}
	var template_name := _clean_text(str(value.get("name", layer.get("name", "Custom Layer"))), "Custom Layer", 64)
	var template_id := EMSValidator.sanitize_pack_id(str(value.get("template_id", template_name)))
	if template_id.is_empty():
		template_id = EMSValidator.sanitize_pack_id(template_name)
	return {
		"template_id": template_id,
		"name": template_name,
		"base_type": str(layer.get("type", "solid_color")),
		"layer": layer,
		"updated_at": int(value.get("updated_at", 0)),
	}


func _sanitize_layer(layer: Dictionary) -> Dictionary:
	if layer.is_empty():
		return {}
	var clean := layer.duplicate(true)
	clean["layout_mode"] = "pack"
	clean["layout_source"] = ""
	var layer_id := EMSValidator.sanitize_pack_id(str(clean.get("id", clean.get("name", "custom_layer"))))
	if layer_id.is_empty():
		layer_id = "custom_layer"
	clean["id"] = layer_id
	var config := {
		"schema_version": EMSValidator.SCHEMA_VERSION,
		"pack_type": EMSValidator.PACK_TYPE_CONFIG,
		"pack_id": "layer_template_validation",
		"title": "Layer Template Validation",
		"author": "Creator",
		"description": "Layer template validation.",
		"layers": [clean],
		"events": [],
		"palette": {"colors": ["#55DFFFFF"], "morph": "smooth", "speed": 0.2},
		"performance": {"motion_intensity": 0.7, "particle_intensity": 0.5, "audio_reactive": true, "estimated_cost": 0.2},
	}
	var validated := EMSValidator.validate_config(config)
	if not (validated.get("_validation_errors", []) as Array).is_empty():
		return {}
	var layers: Array = validated.get("layers", []) as Array
	if layers.is_empty() or layers[0] is not Dictionary:
		return {}
	return (layers[0] as Dictionary).duplicate(true)


func _unique_layer_id(layer_name: String, existing_ids: Array[String]) -> String:
	var base := EMSValidator.sanitize_pack_id(layer_name)
	if base.is_empty():
		base = "custom_layer"
	var candidate := base
	var suffix := 2
	while existing_ids.has(candidate):
		candidate = "%s_%d" % [base, suffix]
		suffix += 1
	return candidate


func _clean_text(value: String, fallback: String, max_len: int) -> String:
	var text := value.strip_edges().replace("\n", " ").replace("\r", " ").replace("\t", " ")
	while text.contains("  "):
		text = text.replace("  ", " ")
	if text.is_empty():
		text = fallback
	if text.length() > max_len:
		text = text.substr(0, max_len)
	return text
