extends SceneTree

const EMSWorkshopManager := preload("res://systems/ems/EMSWorkshopManager.gd")
const EMSPackLoader := preload("res://systems/ems/EMSPackLoader.gd")
const EMSValidator := preload("res://systems/ems/EMSValidator.gd")


func _initialize() -> void:
	EMSPackLoader.cleanup_automated_test_packs()
	var failures: Array[String] = []
	var folder := _create_pack("workshop_upload_probe")
	var manager := EMSWorkshopManager.new()
	var result := manager.upload_pack(folder, {
		"title": "Workshop Upload Probe",
		"description": "Temporary Workshop smoke pack.",
		"tags": ["EMS", "Smoke"],
		"visibility": "private",
		"change_note": "Workshop manager smoke upload.",
		"dry_run": true,
	})
	if result.is_empty() or str(result.get("message", "")).is_empty():
		failures.append("Workshop upload wrapper returned an empty status.")
	if (result.get("upload_metadata", {}) as Dictionary).is_empty():
		failures.append("Workshop upload wrapper did not return upload metadata.")
	if str(result.get("upload_log_path", "")) != "user://workshop_upload_log.txt":
		failures.append("EMS Workshop upload did not report the persistent upload log path.")
	var upload_payload := result.get("upload_payload", {}) as Dictionary
	if upload_payload.is_empty() or not bool(upload_payload.get("ok", false)):
		failures.append("Workshop upload wrapper did not validate payload content.")
	if int(upload_payload.get("payload_size_bytes", 0)) <= 0:
		failures.append("Workshop upload payload size should be nonzero.")
	if str(upload_payload.get("preview_global_path", "")).is_empty() or not FileAccess.file_exists(str(upload_payload.get("preview_global_path", ""))):
		failures.append("Workshop upload payload did not resolve a valid preview image.")
	if str(upload_payload.get("preview_global_path", "")).get_file() != "steam_preview.png":
		failures.append("EMS Workshop upload should use a Steam-specific square preview image.")
	if str(upload_payload.get("source_preview_global_path", "")).get_file() != EMSValidator.PREVIEW_FILE:
		failures.append("EMS Workshop upload did not keep the original pack preview as the preview source.")
	var steam_preview := Image.load_from_file(str(upload_payload.get("preview_global_path", "")))
	if steam_preview == null or steam_preview.is_empty():
		failures.append("EMS Workshop square preview could not be loaded.")
	elif steam_preview.get_width() != 512 or steam_preview.get_height() != 512:
		failures.append("EMS Workshop square preview should be 512x512, got %dx%d." % [steam_preview.get_width(), steam_preview.get_height()])
	if str(upload_payload.get("content_global_path", "")).is_empty() or not DirAccess.dir_exists_absolute(str(upload_payload.get("content_global_path", ""))):
		failures.append("Workshop upload payload did not resolve a valid content folder.")
	if not bool(result.get("dry_run", false)):
		failures.append("Workshop upload smoke test did not use dry-run mode.")
	var steam_tags: Variant = manager.call("_workshop_tags", ["EMS", "Smoke"])
	if not (steam_tags is Array):
		failures.append("Workshop tags were not kept as an Array for this GodotSteam build.")
	elif not (steam_tags as Array).has("EMS Creator"):
		failures.append("Workshop tags did not include required EMS Creator tag.")
	manager.call("_on_workshop_item_updated", 1, false, 123456789012345678)
	if not manager.get_status().contains("123456789012345678"):
		failures.append("Workshop item_updated callback did not accept GodotSteam's three-argument signal shape.")
	var invalid := manager.upload_pack("user://does_not_exist")
	if bool(invalid.get("ok", false)):
		failures.append("Workshop manager accepted an invalid folder.")
	var invalid_playtime := manager.start_playtime_tracking("not_a_workshop_id")
	if bool(invalid_playtime.get("ok", false)):
		failures.append("Workshop playtime tracking accepted an invalid item id.")
	if not str(invalid_playtime.get("message", "")).contains("invalid"):
		failures.append("Workshop playtime tracking did not explain invalid item ids.")
	var idle_stop := manager.stop_playtime_tracking("")
	if not bool(idle_stop.get("ok", false)):
		failures.append("Workshop playtime idle stop should be safe.")
	var refresh := manager.refresh_subscriptions()
	if refresh.is_empty() or not refresh.has("message"):
		failures.append("Workshop subscription refresh returned malformed status.")
	EMSPackLoader.delete_pack_folder(folder)
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("EMS Workshop manager smoke test passed.")
	quit(0)


func _create_pack(pack_id: String) -> String:
	EMSPackLoader.ensure_user_dirs()
	var folder := EMSPackLoader.EXPORT_ROOT.path_join(pack_id)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	_write_json(folder.path_join(EMSValidator.MANIFEST_FILE), {"schema_version": 1, "pack_type": EMSValidator.PACK_TYPE_CONFIG, "pack_id": pack_id, "title": "Workshop Upload Probe", "author": "Automated Test", "description": "Temporary Workshop smoke pack.", "min_game_version": "1.0.0", "tags": ["EMS", "Test"]})
	_write_json(folder.path_join(EMSValidator.CONFIG_FILE), {
		"schema_version": 1,
		"pack_type": EMSValidator.PACK_TYPE_CONFIG,
		"pack_id": pack_id,
		"title": "Workshop Upload Probe",
		"author": "Automated Test",
		"description": "Temporary Workshop smoke pack.",
		"layers": [{"id": "solid", "type": "solid_color", "name": "Solid", "opacity": 0.4, "color": "#55DFFFFF", "colors": ["#55DFFFFF"], "particle_count": 0}],
		"events": [],
		"palette": {"colors": ["#55DFFFFF"], "morph": "smooth", "speed": 0.2},
		"performance": {"motion_intensity": 0.2, "particle_intensity": 0.0, "audio_reactive": false, "estimated_cost": 0.1},
	})
	var image := Image.create(640, 360, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 1.0))
	for y in range(116, 244):
		for x in range(256, 384):
			var edge := absf(float(x - 320)) / 64.0 + absf(float(y - 180)) / 64.0
			image.set_pixel(x, y, Color(0.1 + edge * 0.1, 0.65, 1.0, 1.0))
	for y in range(150, 210):
		for x in range(272, 368):
			image.set_pixel(x, y, Color(0.95, 0.97, 1.0, 1.0))
	image.save_png(folder.path_join(EMSValidator.PREVIEW_FILE))
	return folder


func _write_json(path: String, payload: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(payload, "\t", false))
