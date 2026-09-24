extends RefCounted
class_name EMSPackLoader

const EMSValidator = preload("res://systems/ems/EMSValidator.gd")

const LOCAL_ROOT := "user://ems/local"
const WORKSHOP_ROOT := "user://ems/workshop"
const EXPORT_ROOT := "user://ems/exports"

const AUTOMATED_TEST_PACK_IDS := {
	"creator_registration_probe": true,
	"registry_pack": true,
	"smoke_custom_pack": true,
	"delete_me_pack": true,
	"creator_export_config": true,
	"creator_export_project": true,
	"creator_export_media": true,
	"creator_export_high": true,
	"workshop_smoke": true,
	"workshop_upload_probe": true,
}


static func ensure_user_dirs() -> void:
	for path in [LOCAL_ROOT, WORKSHOP_ROOT, EXPORT_ROOT]:
		_ensure_user_dir(path)


static func scan_local() -> Array[Dictionary]:
	ensure_user_dirs()
	var entries := _visible_pack_entries(_scan_root(LOCAL_ROOT, "local"))
	var installed_ids := {}
	for entry in entries:
		installed_ids[str(entry.get("pack_id", ""))] = true
	for entry in _visible_pack_entries(_scan_root(EXPORT_ROOT, "local")):
		if installed_ids.has(str(entry.get("pack_id", ""))):
			continue
		entries.append(entry)
	return entries


static func scan_workshop() -> Array[Dictionary]:
	ensure_user_dirs()
	return _visible_pack_entries(_scan_root(WORKSHOP_ROOT, "workshop"))


static func scan_created_packs() -> Array[Dictionary]:
	ensure_user_dirs()
	var entries := _visible_pack_entries(_scan_root(LOCAL_ROOT, "local"))
	entries.append_array(_visible_pack_entries(_scan_root(EXPORT_ROOT, "export")))
	return entries


static func cleanup_automated_test_packs() -> Array[Dictionary]:
	ensure_user_dirs()
	var results: Array[Dictionary] = []
	for root in [LOCAL_ROOT, EXPORT_ROOT, WORKSHOP_ROOT]:
		for entry in _scan_root(root, "cleanup"):
			if not is_automated_test_pack_entry(entry):
				continue
			var result := _delete_pack_folder_recursive(str(entry.get("folder_path", "")))
			results.append(result)
	return results


static func cleanup_loadout_menu_noise() -> Array[Dictionary]:
	ensure_user_dirs()
	var results: Array[Dictionary] = cleanup_automated_test_packs()
	for root in [LOCAL_ROOT, EXPORT_ROOT, WORKSHOP_ROOT]:
		for entry in _scan_root(root, "cleanup"):
			if str(entry.get("validation_status", "valid")) != "invalid" and not _is_creator_listing_probe_entry(entry):
				continue
			var result := _delete_pack_folder_recursive(str(entry.get("folder_path", "")))
			results.append(result)
	return results


static func is_automated_test_pack_entry(entry: Dictionary) -> bool:
	var pack_id := EMSValidator.sanitize_pack_id(str(entry.get("pack_id", "")))
	var folder_id := EMSValidator.sanitize_pack_id(str(entry.get("folder_path", "")).get_file())
	if AUTOMATED_TEST_PACK_IDS.has(pack_id) or AUTOMATED_TEST_PACK_IDS.has(folder_id):
		return true
	for base_id in AUTOMATED_TEST_PACK_IDS.keys():
		if folder_id.begins_with("%s_" % str(base_id)):
			return true
	var title := str(entry.get("display_name", "")).strip_edges().to_lower()
	var author := str(entry.get("author", "")).strip_edges().to_lower()
	if author in ["test", "smoke tester", "automated test"] and title in ["creator export", "smoke custom pack", "registry pack", "delete me pack", "creator registration probe", "workshop smoke"]:
		return true
	return false


static func _is_creator_listing_probe_entry(entry: Dictionary) -> bool:
	var pack_id := EMSValidator.sanitize_pack_id(str(entry.get("pack_id", "")))
	var folder_id := EMSValidator.sanitize_pack_id(str(entry.get("folder_path", "")).get_file())
	if pack_id == "creator_listing_probe" or folder_id == "creator_listing_probe" or folder_id.begins_with("creator_listing_probe_"):
		return true
	var title := str(entry.get("display_name", "")).strip_edges().to_lower()
	var author := str(entry.get("author", "")).strip_edges().to_lower()
	return title == "creator listing probe" and author == "automated test"


static func import_pack_folder(source_folder: String) -> Dictionary:
	ensure_user_dirs()
	var validation := EMSValidator.validate_pack_folder(source_folder)
	if not bool(validation.get("ok", false)):
		return {"ok": false, "message": "EMS pack failed validation.", "validation": validation, "path": ""}
	var config: Dictionary = validation.get("config", {}) as Dictionary
	var pack_id := EMSValidator.sanitize_pack_id(str(config.get("pack_id", source_folder.get_file())))
	var target := _unique_folder(LOCAL_ROOT.path_join(pack_id))
	var copied := _copy_pack_files(source_folder, target)
	if not bool(copied.get("ok", false)):
		return copied
	var final_validation := EMSValidator.validate_pack_folder(target)
	return {
		"ok": bool(final_validation.get("ok", false)),
		"message": "Imported EMS pack." if bool(final_validation.get("ok", false)) else "Imported EMS pack failed final validation.",
		"validation": final_validation,
		"path": target,
	}


static func copy_validated_pack_to_root(source_folder: String, target_root: String, preferred_id: String = "") -> Dictionary:
	ensure_user_dirs()
	var validation := EMSValidator.validate_pack_folder(source_folder)
	if not bool(validation.get("ok", false)):
		return {"ok": false, "message": "EMS pack failed validation.", "validation": validation, "path": ""}
	var config: Dictionary = validation.get("config", {}) as Dictionary
	var pack_id := EMSValidator.sanitize_pack_id(preferred_id if not preferred_id.strip_edges().is_empty() else str(config.get("pack_id", source_folder.get_file())))
	if pack_id.is_empty():
		pack_id = EMSValidator.sanitize_pack_id(source_folder.get_file())
	var target := target_root.path_join(pack_id)
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(target)):
		_remove_pack_files(target)
	var copied := _copy_pack_files(source_folder, target)
	if not bool(copied.get("ok", false)):
		return copied
	var final_validation := EMSValidator.validate_pack_folder(target)
	return {
		"ok": bool(final_validation.get("ok", false)),
		"message": "Copied EMS pack." if bool(final_validation.get("ok", false)) else "Copied EMS pack failed final validation.",
		"validation": final_validation,
		"path": target,
	}


static func delete_pack_folder(folder_path: String) -> Dictionary:
	ensure_user_dirs()
	var folder := folder_path.strip_edges()
	if not _is_manageable_pack_folder(folder):
		return {"ok": false, "message": "Can only delete EMS packs under managed EMS roots.", "path": folder}
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(folder)):
		return {"ok": false, "message": "EMS pack folder does not exist.", "path": folder}
	return _delete_pack_folder_recursive(folder)


static func export_pack(target_root: String, manifest: Dictionary, config: Dictionary, project: Dictionary = {}, preview_path: String = "", overwrite_existing: bool = false) -> Dictionary:
	ensure_user_dirs()
	var root := target_root.strip_edges()
	if root.is_empty():
		root = EXPORT_ROOT
	if not root.begins_with("user://"):
		return {"ok": false, "message": "EMS exports must target user://.", "path": "", "validation": {}}
	_ensure_user_dir(root)
	var sanitized_config := EMSValidator.validate_config(config)
	var errors: Array = sanitized_config.get("_validation_errors", []) as Array
	if not errors.is_empty():
		return {"ok": false, "message": "EMS config failed validation.", "path": "", "validation": {"ok": false, "errors": errors}}
	sanitized_config.erase("_validation_errors")
	sanitized_config.erase("_layer_count")
	sanitized_config.erase("_total_particles")
	sanitized_config.erase("_performance_warning")
	var pack_id := EMSValidator.sanitize_pack_id(str(sanitized_config.get("pack_id", "community_ems")))
	if pack_id.is_empty():
		pack_id = "community_ems"
	sanitized_config["pack_id"] = pack_id
	var folder := root.path_join(pack_id)
	if overwrite_existing and DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(folder)):
		_remove_pack_files(folder)
	elif not overwrite_existing:
		folder = _unique_folder(folder)
	var err := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	if err != OK:
		return {"ok": false, "message": "Could not create EMS export folder.", "path": folder, "validation": {}}
	var media_result := _copy_export_media(sanitized_config, folder)
	if not bool(media_result.get("ok", false)):
		return media_result

	var manifest_out := manifest.duplicate(true)
	manifest_out["schema_version"] = EMSValidator.SCHEMA_VERSION
	manifest_out["pack_type"] = str(sanitized_config.get("pack_type", EMSValidator.PACK_TYPE_CONFIG))
	manifest_out["pack_id"] = pack_id
	manifest_out["title"] = str(sanitized_config.get("title", manifest_out.get("title", "Community EMS")))
	manifest_out["author"] = str(sanitized_config.get("author", manifest_out.get("author", "Unknown Creator")))
	manifest_out["description"] = str(sanitized_config.get("description", manifest_out.get("description", "")))
	manifest_out["min_game_version"] = str(manifest_out.get("min_game_version", "1.0.0"))
	manifest_out["tags"] = manifest_out.get("tags", ["EMS"])
	if not _write_json(folder.path_join(EMSValidator.MANIFEST_FILE), manifest_out):
		return {"ok": false, "message": "Could not write manifest.json.", "path": folder, "validation": {}}
	if not _write_json(folder.path_join(EMSValidator.CONFIG_FILE), sanitized_config):
		return {"ok": false, "message": "Could not write ems_config.json.", "path": folder, "validation": {}}
	if str(sanitized_config.get("pack_type", "")) == EMSValidator.PACK_TYPE_CREATOR:
		var project_out := project.duplicate(true)
		project_out["schema_version"] = EMSValidator.SCHEMA_VERSION
		project_out["pack_type"] = EMSValidator.PACK_TYPE_CREATOR
		project_out["pack_id"] = pack_id
		project_out["title"] = str(sanitized_config.get("title", "Community EMS"))
		project_out["author"] = str(sanitized_config.get("author", "Unknown Creator"))
		project_out["layers"] = (sanitized_config.get("layers", []) as Array).duplicate(true)
		if not _write_json(folder.path_join(EMSValidator.PROJECT_FILE), project_out):
			return {"ok": false, "message": "Could not write ems_project.json.", "path": folder, "validation": {}}
	if not preview_path.is_empty() and FileAccess.file_exists(preview_path):
		var copied := _copy_or_normalize_preview(preview_path, folder.path_join(EMSValidator.PREVIEW_FILE))
		if not bool(copied.get("ok", false)):
			return copied
	else:
		var generated := _generate_preview(folder.path_join(EMSValidator.PREVIEW_FILE), sanitized_config)
		if not bool(generated.get("ok", false)):
			return generated
	var validation := EMSValidator.validate_pack_folder(folder)
	return {
		"ok": bool(validation.get("ok", false)),
		"message": "EMS pack exported." if bool(validation.get("ok", false)) else "Exported EMS pack failed validation.",
		"path": folder,
		"validation": validation,
	}


static func _scan_root(root: String, source: String) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var dir := DirAccess.open(root)
	if dir == null:
		return entries
	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name.is_empty():
			break
		if name == "." or name == ".." or not dir.current_is_dir():
			continue
		var folder := root.path_join(name)
		var validation := EMSValidator.validate_pack_folder(folder)
		if not bool(validation.get("ok", false)):
			entries.append(_invalid_entry(folder, source, validation))
			continue
		entries.append(_entry_from_validation(folder, source, validation))
	dir.list_dir_end()
	return entries


static func _visible_pack_entries(entries: Array[Dictionary]) -> Array[Dictionary]:
	var visible: Array[Dictionary] = []
	for entry in entries:
		if is_automated_test_pack_entry(entry):
			continue
		visible.append(entry)
	return visible


static func _entry_from_validation(folder: String, source: String, validation: Dictionary) -> Dictionary:
	var config: Dictionary = (validation.get("config", {}) as Dictionary).duplicate(true)
	var manifest: Dictionary = validation.get("manifest", {}) as Dictionary
	var metrics: Dictionary = validation.get("metrics", {}) as Dictionary
	var pack_id := EMSValidator.sanitize_pack_id(str(config.get("pack_id", manifest.get("pack_id", folder.get_file()))))
	var workshop_item_id := ""
	if source == "workshop":
		var folder_id := folder.get_file()
		if folder_id.is_valid_int() and int(folder_id) > 0:
			workshop_item_id = folder_id
		else:
			workshop_item_id = str(manifest.get("workshop_item_id", config.get("workshop_item_id", ""))).strip_edges()
		if not workshop_item_id.is_empty():
			config["_workshop_item_id"] = workshop_item_id
	config["_pack_folder"] = folder
	return {
		"id": "community:%s:%s" % [source, pack_id],
		"pack_id": pack_id,
		"workshop_item_id": workshop_item_id,
		"type": "ems_loadout",
		"acquisition": "community",
		"display_name": str(config.get("title", manifest.get("title", pack_id))),
		"description": str(config.get("description", manifest.get("description", "Community EMS pack."))),
		"author": str(config.get("author", manifest.get("author", "Unknown Creator"))),
		"source": source,
		"pack_type": str(config.get("pack_type", EMSValidator.PACK_TYPE_CONFIG)),
		"price": 0,
		"required_level": 1,
		"default_owned": true,
		"preview_path": str(validation.get("preview_path", "")),
		"validation_status": "valid",
		"validation": validation,
		"metrics": metrics,
		"motion_intensity": float((config.get("performance", {}) as Dictionary).get("motion_intensity", 0.0)),
		"particle_intensity": float((config.get("performance", {}) as Dictionary).get("particle_intensity", 0.0)),
		"audio_reactive": bool((config.get("performance", {}) as Dictionary).get("audio_reactive", true)),
		"config": config,
		"folder_path": folder,
	}


static func _invalid_entry(folder: String, source: String, validation: Dictionary) -> Dictionary:
	return {
		"id": "invalid:%s:%s" % [source, EMSValidator.sanitize_pack_id(folder.get_file())],
		"pack_id": EMSValidator.sanitize_pack_id(folder.get_file()),
		"type": "ems_loadout",
		"acquisition": "community_invalid",
		"display_name": folder.get_file(),
		"description": "Invalid EMS pack.",
		"author": "Unknown",
		"source": source,
		"pack_type": "",
		"price": 0,
		"required_level": 1,
		"default_owned": false,
		"preview_path": "",
		"validation_status": "invalid",
		"validation": validation,
		"metrics": validation.get("metrics", {}),
		"motion_intensity": 0.0,
		"particle_intensity": 0.0,
		"audio_reactive": false,
		"config": {},
		"folder_path": folder,
	}


static func _copy_pack_files(source_folder: String, target_folder: String) -> Dictionary:
	var err := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(target_folder))
	if err != OK:
		return {"ok": false, "message": "Could not create EMS target folder.", "path": target_folder, "validation": {}}
	for file_name in [EMSValidator.MANIFEST_FILE, EMSValidator.CONFIG_FILE, EMSValidator.PREVIEW_FILE, EMSValidator.PROJECT_FILE]:
		var source := source_folder.path_join(file_name)
		if FileAccess.file_exists(source):
			var copied := _copy_file(source, target_folder.path_join(file_name))
			if not bool(copied.get("ok", false)):
				return copied
	var media_copied := _copy_media_folder(source_folder, target_folder)
	if not bool(media_copied.get("ok", false)):
		return media_copied
	return {"ok": true, "message": "Copied EMS pack.", "path": target_folder, "validation": {}}


static func _remove_pack_files(folder: String) -> void:
	for file_name in [EMSValidator.MANIFEST_FILE, EMSValidator.CONFIG_FILE, EMSValidator.PREVIEW_FILE, EMSValidator.PROJECT_FILE]:
		var path := folder.path_join(file_name)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var media_folder := folder.path_join(EMSValidator.MEDIA_DIR)
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(media_folder)):
		var dir := DirAccess.open(media_folder)
		if dir != null:
			dir.list_dir_begin()
			while true:
				var name := dir.get_next()
				if name.is_empty():
					break
				if name == "." or name == ".." or dir.current_is_dir():
					continue
				DirAccess.remove_absolute(ProjectSettings.globalize_path(media_folder.path_join(name)))
			dir.list_dir_end()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(media_folder))


static func _copy_export_media(config: Dictionary, folder: String) -> Dictionary:
	var layers: Array = config.get("layers", []) as Array
	var used_names := {}
	for index in range(layers.size()):
		if layers[index] is not Dictionary:
			continue
		var layer := (layers[index] as Dictionary).duplicate(true)
		var media_kind := str(layer.get("media_kind", ""))
		if media_kind.is_empty() and str(layer.get("type", "")) in ["image", "video"]:
			media_kind = str(layer.get("type", ""))
		if media_kind not in ["image", "video"]:
			layer.erase("source_path")
			layers[index] = layer
			continue
		var source_path := str(layer.get("source_path", "")).strip_edges()
		if not source_path.is_empty():
			if not FileAccess.file_exists(source_path):
				return {"ok": false, "message": "Media source file was not found: %s." % source_path, "path": folder, "validation": {}}
			var safe_name := EMSValidator.sanitize_media_file_name(source_path.get_file())
			safe_name = _unique_media_file_name(safe_name, used_names)
			used_names[safe_name] = true
			var target_rel := "%s/%s" % [EMSValidator.MEDIA_DIR, safe_name]
			var copied := _copy_file(source_path, folder.path_join(target_rel))
			if not bool(copied.get("ok", false)):
				return copied
			layer["asset_path"] = target_rel
		layer.erase("source_path")
		layers[index] = layer
	config["layers"] = layers
	return {"ok": true, "message": "Copied EMS media.", "path": folder, "validation": {}}


static func _copy_media_folder(source_folder: String, target_folder: String) -> Dictionary:
	var source_media := source_folder.path_join(EMSValidator.MEDIA_DIR)
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(source_media)):
		return {"ok": true, "message": "No media folder.", "path": target_folder, "validation": {}}
	var target_media := target_folder.path_join(EMSValidator.MEDIA_DIR)
	var err := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(target_media))
	if err != OK:
		return {"ok": false, "message": "Could not create EMS media folder.", "path": target_media, "validation": {}}
	var dir := DirAccess.open(source_media)
	if dir == null:
		return {"ok": false, "message": "Could not open EMS media folder.", "path": source_media, "validation": {}}
	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name.is_empty():
			break
		if name == "." or name == ".." or dir.current_is_dir():
			continue
		var copied := _copy_file(source_media.path_join(name), target_media.path_join(name))
		if not bool(copied.get("ok", false)):
			dir.list_dir_end()
			return copied
	dir.list_dir_end()
	return {"ok": true, "message": "Copied EMS media.", "path": target_media, "validation": {}}


static func _unique_media_file_name(file_name: String, used_names: Dictionary) -> String:
	var extension := file_name.get_extension()
	var stem := file_name.get_basename()
	var candidate := file_name
	var index := 2
	while used_names.has(candidate):
		candidate = "%s_%d.%s" % [stem, index, extension]
		index += 1
	return candidate


static func _is_manageable_pack_folder(folder: String) -> bool:
	if folder.contains("../") or folder.contains("..\\"):
		return false
	if folder == LOCAL_ROOT or folder == EXPORT_ROOT or folder == WORKSHOP_ROOT:
		return false
	return folder.begins_with("%s/" % LOCAL_ROOT) or folder.begins_with("%s/" % EXPORT_ROOT) or folder.begins_with("%s/" % WORKSHOP_ROOT)


static func _delete_pack_folder_recursive(folder: String) -> Dictionary:
	var normalized := folder.strip_edges()
	if not _is_manageable_pack_folder(normalized):
		return {"ok": false, "message": "Can only delete EMS pack folders under managed EMS roots.", "path": normalized}
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(normalized)):
		return {"ok": false, "message": "EMS pack folder does not exist.", "path": normalized}
	var err := _remove_tree(normalized)
	if err != OK:
		return {"ok": false, "message": "Could not delete EMS pack folder.", "path": normalized}
	return {"ok": true, "message": "Deleted EMS pack.", "path": normalized}


static func _remove_tree(path: String) -> Error:
	var global_path := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path):
		return DirAccess.remove_absolute(global_path)
	var dir := DirAccess.open(path)
	if dir == null:
		return ERR_CANT_OPEN
	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name.is_empty():
			break
		if name == "." or name == "..":
			continue
		var child := path.path_join(name)
		var err := OK
		if dir.current_is_dir():
			err = _remove_tree(child)
		else:
			err = DirAccess.remove_absolute(ProjectSettings.globalize_path(child))
		if err != OK:
			dir.list_dir_end()
			return err
	dir.list_dir_end()
	return DirAccess.remove_absolute(global_path)


static func _copy_file(source_path: String, target_path: String) -> Dictionary:
	var bytes := FileAccess.get_file_as_bytes(source_path)
	if bytes.is_empty() and _file_size(source_path) > 0:
		return {"ok": false, "message": "Could not read %s." % source_path.get_file(), "path": target_path, "validation": {}}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(target_path.get_base_dir()))
	var file := FileAccess.open(target_path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "message": "Could not write %s." % target_path.get_file(), "path": target_path, "validation": {}}
	file.store_buffer(bytes)
	return {"ok": true, "message": "Copied file.", "path": target_path, "validation": {}}


static func _copy_or_normalize_preview(source_path: String, target_path: String) -> Dictionary:
	var image := Image.load_from_file(source_path)
	if image != null and not image.is_empty():
		if image.get_format() != Image.FORMAT_RGBA8:
			image.convert(Image.FORMAT_RGBA8)
		var canvas := Image.create(640, 360, false, Image.FORMAT_RGBA8)
		canvas.fill(Color(0.02, 0.03, 0.08, 1.0))
		var scale := minf(640.0 / float(maxi(1, image.get_width())), 360.0 / float(maxi(1, image.get_height())))
		var target_size := Vector2i(
			maxi(1, int(round(float(image.get_width()) * scale))),
			maxi(1, int(round(float(image.get_height()) * scale)))
		)
		image.resize(target_size.x, target_size.y, Image.INTERPOLATE_LANCZOS)
		var offset := Vector2i((640 - target_size.x) / 2, (360 - target_size.y) / 2)
		canvas.blit_rect(image, Rect2i(Vector2i.ZERO, target_size), offset)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(target_path.get_base_dir()))
		var err := canvas.save_png(target_path)
		if err == OK:
			return {"ok": true, "message": "Normalized preview image.", "path": target_path, "validation": {}}
	return _copy_file(source_path, target_path)


static func _write_json(path: String, payload: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(payload, "\t", false))
	return true


static func _generate_preview(path: String, config: Dictionary) -> Dictionary:
	var image := Image.create(320, 180, false, Image.FORMAT_RGBA8)
	var colors: Array = ((config.get("palette", {}) as Dictionary).get("colors", []) as Array)
	var c1 := _color_from_hex(str(colors[0] if colors.size() > 0 else "#55DFFF"))
	var c2 := _color_from_hex(str(colors[1] if colors.size() > 1 else "#FF4DE1"))
	for y in range(image.get_height()):
		var t := float(y) / maxf(1.0, float(image.get_height() - 1))
		var row := c1.lerp(c2, t)
		for x in range(image.get_width()):
			var glow := sin((float(x) / 22.0) + t * 7.0) * 0.5 + 0.5
			image.set_pixel(x, y, row.lerp(Color(0.02, 0.03, 0.08, 1.0), 0.35 - glow * 0.12))
	var err := image.save_png(path)
	if err != OK:
		return {"ok": false, "message": "Could not generate preview.png.", "path": path, "validation": {}}
	return {"ok": true, "message": "Generated preview.", "path": path, "validation": {}}


static func _color_from_hex(value: String) -> Color:
	var hex := value.strip_edges()
	if hex.begins_with("#"):
		hex = hex.substr(1)
	if hex.length() == 6:
		hex += "FF"
	if hex.length() != 8:
		return Color(0.33, 0.87, 1.0, 1.0)
	return Color(
		float(hex.substr(0, 2).hex_to_int()) / 255.0,
		float(hex.substr(2, 2).hex_to_int()) / 255.0,
		float(hex.substr(4, 2).hex_to_int()) / 255.0,
		float(hex.substr(6, 2).hex_to_int()) / 255.0
	)


static func _unique_folder(base: String) -> String:
	var candidate := base
	var index := 2
	while DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(candidate)):
		candidate = "%s_%d" % [base, index]
		index += 1
	return candidate


static func _ensure_user_dir(user_path: String) -> void:
	if not user_path.begins_with("user://"):
		return
	var abs := ProjectSettings.globalize_path(user_path)
	if DirAccess.dir_exists_absolute(abs):
		return
	var err := DirAccess.make_dir_recursive_absolute(abs)
	if err != OK:
		push_warning("Failed to create EMS directory %s (error %d)" % [user_path, err])


static func _file_size(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	return int(file.get_length())
