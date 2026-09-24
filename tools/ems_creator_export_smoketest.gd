extends SceneTree

const EMSPackLoader := preload("res://systems/ems/EMSPackLoader.gd")
const EMSValidator := preload("res://systems/ems/EMSValidator.gd")
const EMSCreatorControllerScript := preload("res://systems/ems/EMSCreator/EMSCreatorController.gd")
const EMSExportDialogScript := preload("res://systems/ems/EMSCreator/EMSExportDialog.gd")
const EMSWorkshopUploadDialogScript := preload("res://systems/ems/EMSCreator/EMSWorkshopUploadDialog.gd")
const EMSPackManagerDialogScript := preload("res://systems/ems/EMSCreator/EMSPackManagerDialog.gd")

var _created_paths: Array[String] = []


func _initialize() -> void:
	EMSPackLoader.cleanup_automated_test_packs()
	_cleanup_creator_listing_probe_packs()
	var failures: Array[String] = []
	var scene := load("res://systems/ems/EMSCreator/EMSCreatorScene.tscn")
	var instance: Node = null
	if not scene is PackedScene:
		failures.append("EMS Creator scene failed to load.")
	else:
		instance = (scene as PackedScene).instantiate()
		root.add_child(instance)
		await process_frame
		if instance.get_child_count() <= 0:
			failures.append("EMS Creator scene did not build its editor UI.")
		_verify_creator_export_ui(instance, failures)
	var config_pack := _config("creator_export_config", EMSValidator.PACK_TYPE_CONFIG, 60)
	var export_config := EMSPackLoader.export_pack("user://ems/exports", {}, config_pack, {}, "")
	_remember_result_paths(export_config)
	if not bool(export_config.get("ok", false)):
		failures.append("Config export failed: %s" % str(export_config.get("message", "")))
	var creator_pack := _config("creator_export_project", EMSValidator.PACK_TYPE_CREATOR, 120)
	var export_creator := EMSPackLoader.export_pack("user://ems/exports", {}, creator_pack, {"layers": creator_pack["layers"], "events": creator_pack["events"]}, "")
	_remember_result_paths(export_creator)
	if not bool(export_creator.get("ok", false)):
		failures.append("Creator export failed: %s" % str(export_creator.get("message", "")))
	var source_image_path := "user://ems_export_source_image.png"
	_write_preview_image(source_image_path)
	var media_config := _media_source_config("creator_export_media", source_image_path)
	var export_media := EMSPackLoader.export_pack("user://ems/exports", {}, media_config, {"layers": media_config["layers"], "events": []}, "")
	_remember_result_paths(export_media)
	if not bool(export_media.get("ok", false)):
		failures.append("Media export failed: %s" % str(export_media.get("message", "")))
	else:
		var exported_folder := str(export_media.get("path", ""))
		var validation: Dictionary = export_media.get("validation", {}) as Dictionary
		var exported_config: Dictionary = validation.get("config", {}) as Dictionary
		var media_layers: Array = exported_config.get("layers", []) as Array
		var exported_layer: Dictionary = media_layers[0] as Dictionary
		var asset_path := str(exported_layer.get("asset_path", ""))
		if asset_path.is_empty() or not asset_path.begins_with("media/"):
			failures.append("Media export did not rewrite source_path to media asset_path.")
		if not str(exported_layer.get("source_path", "")).is_empty():
			failures.append("Media export leaked source_path into saved config.")
		if not FileAccess.file_exists(exported_folder.path_join(asset_path)):
			failures.append("Media export did not copy the image into the pack media folder.")
	var high_config := _config("creator_export_high", EMSValidator.PACK_TYPE_CONFIG, 500)
	for i in range(20):
		(high_config["layers"] as Array).append({"id": "extra_%d" % i, "type": "particles", "name": "Extra", "opacity": 0.6, "color": "#55DFFFFF", "colors": ["#55DFFFFF"], "particle_count": 40})
	(high_config["performance"] as Dictionary)["motion_intensity"] = 1.0
	(high_config["performance"] as Dictionary)["estimated_cost"] = 1.0
	var validated := EMSValidator.validate_config(high_config)
	if str(validated.get("_performance_warning", "")) != "High":
		failures.append("High-cost creator config did not report High performance warning.")
	if instance != null:
		instance.queue_free()
	_cleanup_test_artifacts()
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("EMS creator export smoke test passed.")
	quit(0)


func _verify_creator_export_ui(instance: Node, failures: Array[String]) -> void:
	var controller := _find_by_script(instance, EMSCreatorControllerScript)
	var dialog := _find_by_script(instance, EMSExportDialogScript)
	var workshop_dialog := _find_by_script(instance, EMSWorkshopUploadDialogScript)
	var manager := _find_by_script(instance, EMSPackManagerDialogScript)
	if controller == null:
		failures.append("EMS Creator controller missing.")
		return
	if dialog == null:
		failures.append("EMS Export dialog missing.")
		return
	if workshop_dialog == null:
		failures.append("EMS Workshop upload dialog missing.")
		return
	if manager == null:
		failures.append("EMS Pack Manager dialog missing.")
		return
	var dialog_state: Dictionary = dialog.call("get_debug_state") as Dictionary
	for key in ["has_title", "has_pack_id", "has_author", "has_description", "has_tags"]:
		if not bool(dialog_state.get(key, false)):
			failures.append("EMS Export dialog missing metadata field %s." % key)
	for key in ["body_scrollable", "has_footer", "has_footer_cancel", "has_footer_export"]:
		if not bool(dialog_state.get(key, false)):
			failures.append("EMS Export dialog missing fixed footer/scroll state %s." % key)
	var workshop_state: Dictionary = workshop_dialog.call("get_debug_state") as Dictionary
	for key in ["has_title", "has_pack_id", "has_author", "has_description", "has_tags", "has_visibility", "has_existing_item_id", "has_change_note", "has_preview_path", "has_preview_browse"]:
		if not bool(workshop_state.get(key, false)):
			failures.append("EMS Workshop upload dialog missing metadata field %s." % key)
	for key in ["body_scrollable", "has_footer", "has_footer_cancel", "has_footer_upload", "has_status"]:
		if not bool(workshop_state.get(key, false)):
			failures.append("EMS Workshop upload dialog missing fixed footer/scroll state %s." % key)
	if str(workshop_state.get("visibility", "")) != "public":
		failures.append("EMS Workshop upload dialog should default to Public visibility for Steam checklist publishing.")
	if not str(workshop_state.get("status", "")).contains("Public visibility"):
		failures.append("EMS Workshop upload dialog status did not explain Public visibility publishing.")
	var details := {
		"title": "Creator Listing Probe",
		"pack_id": "Creator Listing Probe",
		"author": "Automated Test",
		"description": "A named custom EMS pack for Loadouts registration coverage.",
		"tags": ["EMS", "Test"],
		"include_creator_project": true,
		"install_local": true,
	}
	dialog.call("set_export_details_for_test", details)
	var normalized: Dictionary = dialog.call("get_export_details") as Dictionary
	if str(normalized.get("pack_id", "")) != "creator_listing_probe":
		failures.append("EMS Export dialog did not sanitize pack id from pack name.")
	controller.call("set_layout_for_test", "full_background", Vector2(0.60, 0.45), Vector2(0.82, 1.10), 1.28, -18.0)
	var open_state: Dictionary = controller.call("show_export_dialog_for_test") as Dictionary
	if not bool(open_state.get("export_dialog_visible", false)):
		failures.append("EMS Export dialog did not open before export.")
	var export_result: Dictionary = controller.call("export_pack_for_test", details) as Dictionary
	_remember_result_paths(export_result)
	if not bool(export_result.get("ok", false)):
		failures.append("Controller export failed: %s" % str(export_result.get("message", "")))
	if not str(export_result.get("path", "")).begins_with("user://ems/exports/"):
		failures.append("Controller export did not report the user://ems/exports path.")
	if not str(export_result.get("local_path", "")).begins_with("user://ems/local/"):
		failures.append("Controller export did not install a Local EMS test copy.")
	var dialog_export_state: Dictionary = controller.call("export_from_dialog_for_test", details) as Dictionary
	_remember_result_paths(dialog_export_state)
	if bool(dialog_export_state.get("export_dialog_visible", true)):
		failures.append("Successful EMS Export did not close the export dialog.")
	if not str(dialog_export_state.get("status", "")).contains("user://ems/exports/"):
		failures.append("Successful EMS Export did not leave a visible exported path status.")
	var workshop_open_state: Dictionary = controller.call("show_workshop_upload_dialog_for_test") as Dictionary
	if not bool(workshop_open_state.get("workshop_upload_dialog_visible", false)):
		failures.append("EMS Workshop upload dialog did not open before upload.")
	var workshop_dialog_state: Dictionary = workshop_open_state.get("workshop_upload_dialog_state", {}) as Dictionary
	if not bool(workshop_dialog_state.get("has_status_details", false)):
		failures.append("EMS Workshop upload dialog is missing the persistent status details panel.")
	if not bool(workshop_dialog_state.get("has_copy_details", false)):
		failures.append("EMS Workshop upload dialog is missing the copy error details button.")
	var workshop_upload_state: Dictionary = controller.call("upload_to_workshop_from_dialog_for_test", {
		"title": "Creator Listing Probe",
		"pack_id": "creator_listing_probe",
		"author": "Automated Test",
		"description": "Workshop upload dialog coverage.",
		"tags": ["EMS", "Test"],
		"visibility": "private",
		"change_note": "Smoke upload metadata.",
		"include_creator_project": true,
	}) as Dictionary
	var workshop_details: Dictionary = workshop_upload_state.get("workshop_upload_details", {}) as Dictionary
	if str(workshop_details.get("visibility", "")) != "private":
		failures.append("EMS Workshop upload dialog did not preserve visibility.")
	if str(workshop_details.get("change_note", "")).strip_edges().is_empty():
		failures.append("EMS Workshop upload dialog did not preserve change note.")
	if not str(workshop_upload_state.get("status", "")).contains("Steamworks") and not str(workshop_upload_state.get("status", "")).contains("Steam Workshop"):
		failures.append("EMS Workshop upload flow did not report a Steam Workshop status.")
	if not str(workshop_upload_state.get("status", "")).contains("public-item checklist"):
		failures.append("Private Workshop upload status did not explain the public-item checklist requirement.")
	workshop_dialog_state = workshop_upload_state.get("workshop_upload_dialog_state", {}) as Dictionary
	if not str(workshop_dialog_state.get("status_details", "")).contains("Steam Workshop"):
		failures.append("EMS Workshop upload dialog did not preserve status details.")
	var load_result: Dictionary = controller.call("load_pack_for_test", str(export_result.get("local_path", ""))) as Dictionary
	if not bool(load_result.get("ok", false)):
		failures.append("Controller could not load an exported Local EMS pack: %s" % str(load_result.get("message", "")))
	var controller_state: Dictionary = controller.call("get_creator_debug_state") as Dictionary
	if not bool(controller_state.get("has_status_panel", false)) or float(controller_state.get("status_min_height", 0.0)) < 30.0:
		failures.append("EMS Creator is missing the visible status panel.")
	if str((controller_state.get("metadata", {}) as Dictionary).get("pack_id", "")) != "creator_listing_probe":
		failures.append("Loaded EMS pack metadata did not become the active Creator project.")
	var layout: Dictionary = controller_state.get("layout", {}) as Dictionary
	if str(layout.get("background_region", "")) != "full_background" or absf(float(layout.get("rotation", 0.0)) + 18.0) > 0.001:
		failures.append("Loaded EMS pack did not restore its full-background layout transform.")
	if int(controller_state.get("layer_count", 0)) <= 0:
		failures.append("Loaded EMS pack did not populate Creator layers.")
	manager.call("refresh_packs")
	var manager_state: Dictionary = manager.call("get_debug_state") as Dictionary
	if int(manager_state.get("count", 0)) <= 0:
		failures.append("EMS Pack Manager did not list created packs.")
	if not bool(manager_state.get("actions_before_list", false)):
		failures.append("EMS Pack Manager actions are not above the pack list.")
	if not bool(manager_state.get("load_visible", false)) or not bool(manager_state.get("delete_visible", false)):
		failures.append("EMS Pack Manager load/delete buttons are not visible.")
	if not bool(manager.call("select_folder_for_test", str(export_result.get("local_path", "")))):
		failures.append("EMS Pack Manager could not select the exported local pack.")
	if str(manager.call("get_selected_folder_for_test")) != str(export_result.get("local_path", "")):
		failures.append("EMS Pack Manager selected folder did not match the local export path.")
	var registry := root.get_node_or_null("EMSRegistry")
	if registry != null:
		registry.call("reload")
		var entry := registry.call("get_entry", "community:local:creator_listing_probe") as Dictionary
		if entry.is_empty():
			failures.append("Exported local EMS pack did not register under Local EMS.")
		elif str(entry.get("display_name", "")) != "Creator Listing Probe" or str(entry.get("author", "")) != "Automated Test":
			failures.append("Exported local EMS pack metadata did not reach the registry.")
		else:
			var config: Dictionary = entry.get("config", {}) as Dictionary
			if str(config.get("community_background_region", "")) != "full_background":
				failures.append("Exported local EMS pack layout did not reach the registry runtime config.")
	var draft_result: Dictionary = controller.call("save_draft_for_test", {}) as Dictionary
	_remember_result_paths(draft_result)
	if not bool(draft_result.get("ok", false)):
		failures.append("Save Draft failed: %s" % str(draft_result.get("message", "")))
	if not str(draft_result.get("local_path", draft_result.get("path", ""))).begins_with("user://ems/local/"):
		failures.append("Save Draft did not report a Local EMS path.")
	var delete_details := {
		"title": "Delete Me Pack",
		"pack_id": "delete_me_pack",
		"author": "Smoke Tester",
		"description": "Temporary delete test pack.",
		"tags": ["EMS", "Delete"],
		"include_creator_project": true,
		"install_local": true,
	}
	var delete_export: Dictionary = controller.call("export_pack_for_test", delete_details) as Dictionary
	_remember_result_paths(delete_export)
	if not bool(delete_export.get("ok", false)):
		failures.append("Delete test export failed: %s" % str(delete_export.get("message", "")))
	for path_key in ["local_path", "path"]:
		var path := str(delete_export.get(path_key, ""))
		var delete_result: Dictionary = controller.call("delete_pack_for_test", path) as Dictionary
		if not bool(delete_result.get("ok", false)):
			failures.append("Delete test failed for %s: %s" % [path_key, str(delete_result.get("message", ""))])
		if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path)):
			failures.append("Deleted EMS pack folder still exists for %s." % path_key)
		else:
			_created_paths.erase(path)


func _config(pack_id: String, pack_type: String, particles: int) -> Dictionary:
	return {
		"schema_version": 1,
		"pack_type": pack_type,
		"pack_id": pack_id,
		"title": "Creator Export",
		"author": "Test",
		"description": "Creator export smoke pack.",
		"layers": [{"id": "particles", "type": "particles", "name": "Particles", "opacity": 0.7, "color": "#55DFFFFF", "colors": ["#55DFFFFF", "#FF4DE1FF"], "particle_count": particles}],
		"events": [{"event": "beat", "action": "pulse_opacity", "target": "particles", "params": {"opacity": 0.95, "duration": 0.1}}],
		"layout": {"background_region": "gutters", "position": [0.5, 0.5], "size": [1.0, 1.0], "scale": 1.0, "rotation": 0.0},
		"palette": {"colors": ["#55DFFFFF", "#FF4DE1FF"], "morph": "smooth", "speed": 0.2},
		"performance": {"motion_intensity": 0.7, "particle_intensity": 0.5, "audio_reactive": true, "estimated_cost": 0.4},
	}


func _media_source_config(pack_id: String, source_image_path: String) -> Dictionary:
	return {
		"schema_version": 1,
		"pack_type": EMSValidator.PACK_TYPE_CREATOR,
		"pack_id": pack_id,
		"title": "Creator Media Export",
		"author": "Test",
		"description": "Creator media export smoke pack.",
		"layers": [{"id": "image_layer", "type": "image", "name": "Image", "opacity": 0.8, "color": "#55DFFFFF", "colors": ["#55DFFFFF", "#FF4DE1FF"], "media_kind": "image", "source_path": source_image_path, "asset_path": "", "fit_mode": "contain", "loop": true}],
		"events": [],
		"layout": {"background_region": "full_background", "position": [0.5, 0.5], "size": [1.0, 1.0], "scale": 1.0, "rotation": 0.0},
		"palette": {"colors": ["#55DFFFFF", "#FF4DE1FF"], "morph": "smooth", "speed": 0.2},
		"performance": {"motion_intensity": 0.7, "particle_intensity": 0.1, "audio_reactive": true, "estimated_cost": 0.25},
	}


func _write_preview_image(path: String) -> void:
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.25, 0.8, 1.0, 1.0))
	image.save_png(path)


func _find_by_script(node: Node, script: Script) -> Node:
	if node.get_script() == script:
		return node
	for child in node.get_children():
		var found := _find_by_script(child, script)
		if found != null:
			return found
	return null


func _remember_result_paths(result: Dictionary) -> void:
	for key in ["path", "local_path"]:
		var path := str(result.get(key, "")).strip_edges()
		if path.is_empty() or not path.begins_with("user://ems/"):
			continue
		if not _created_paths.has(path):
			_created_paths.append(path)


func _cleanup_test_artifacts() -> void:
	for path in _created_paths.duplicate():
		if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path)):
			EMSPackLoader.delete_pack_folder(path)
	_created_paths.clear()
	EMSPackLoader.cleanup_automated_test_packs()
	_cleanup_creator_listing_probe_packs()


func _cleanup_creator_listing_probe_packs() -> void:
	for entry in EMSPackLoader.scan_created_packs():
		if not _is_creator_listing_probe(entry):
			continue
		EMSPackLoader.delete_pack_folder(str(entry.get("folder_path", "")))


func _is_creator_listing_probe(entry: Dictionary) -> bool:
	var pack_id := EMSValidator.sanitize_pack_id(str(entry.get("pack_id", "")))
	var folder_id := EMSValidator.sanitize_pack_id(str(entry.get("folder_path", "")).get_file())
	if pack_id == "creator_listing_probe" or folder_id == "creator_listing_probe" or folder_id.begins_with("creator_listing_probe_"):
		return true
	var title := str(entry.get("display_name", "")).strip_edges().to_lower()
	var author := str(entry.get("author", "")).strip_edges().to_lower()
	return title == "creator listing probe" and author == "automated test"
