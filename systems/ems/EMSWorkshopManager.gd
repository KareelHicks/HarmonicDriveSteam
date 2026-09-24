extends RefCounted
class_name EMSWorkshopManager

signal upload_status_changed(status: Dictionary)
signal playtime_status_changed(status: Dictionary)

const EMSValidator = preload("res://systems/ems/EMSValidator.gd")
const EMSPackLoader = preload("res://systems/ems/EMSPackLoader.gd")

const WORKSHOP_TAGS := [
	"EMS",
	"EMS Config",
	"EMS Creator",
	"Neon",
	"Dark",
	"Bright",
	"Minimal",
	"Audio Reactive",
	"Particle Heavy",
	"Low Motion",
	"High Motion",
]

const VISIBILITY_VALUES := {
	"public": 0,
	"friends": 1,
	"private": 2,
	"unlisted": 3,
}
const STEAM_PREVIEW_MAX_BYTES := 1024 * 1024
const STEAM_PREVIEW_FILE := "steam_preview.png"
const STEAM_PREVIEW_SIZE := 512
const STEAM_PREVIEW_FOREGROUND_PADDING := 0.18
const STEAM_PREVIEW_FOREGROUND_THRESHOLD := 0.14
const WORKSHOP_UPLOAD_LOG_FILE := "user://workshop_upload_log.txt"
const INVALID_HANDLE_RETRY_DELAY_SEC := 3.0
const INVALID_HANDLE_MAX_RETRIES := 1

var _status := "Steam Workshop unavailable."
var _playtime_status := "Steam Workshop playtime tracking idle."
var _pending_create_upload := {}
var _pending_update_item_id := ""
var _pending_update_visibility := ""
var _pending_update_handle := 0
var _pending_update_progress: Dictionary = {}
var _update_progress_poll_active := false
var _steam_signals_connected := false
var _playtime_signals_connected := false
var _active_playtime_item_id := ""
var _pending_retry_upload := false
var _upload_session_id := ""
var _last_progress_log_key := ""


func _log_upload_event(context: String, data: Dictionary = {}) -> void:
	var entry := {
		"time": Time.get_datetime_string_from_system(),
		"session_id": _upload_session_id,
		"event": context,
		"data": _safe_log_payload(data),
	}
	var line := "[EMSWorkshop] %s" % JSON.stringify(entry)
	print(line)
	var log_path := ProjectSettings.globalize_path(WORKSHOP_UPLOAD_LOG_FILE)
	DirAccess.make_dir_recursive_absolute(log_path.get_base_dir())
	var file := FileAccess.open(log_path, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(log_path, FileAccess.WRITE)
	if file == null:
		push_warning("Could not write EMS Workshop upload log: %s" % log_path)
		return
	file.seek_end()
	file.store_line(line)


func _variant_type_name(value: Variant) -> String:
	match typeof(value):
		TYPE_NIL:
			return "nil"
		TYPE_BOOL:
			return "bool"
		TYPE_INT:
			return "int"
		TYPE_FLOAT:
			return "float"
		TYPE_STRING:
			return "string"
		TYPE_DICTIONARY:
			return "dictionary"
		TYPE_ARRAY:
			return "array"
		_:
			return str(typeof(value))


func _safe_log_payload(payload: Variant) -> Variant:
	if payload == null:
		return null
	if payload is Dictionary:
		var out: Dictionary = {}
		for key in (payload as Dictionary).keys():
			out[key] = _safe_log_payload((payload as Dictionary).get(key))
		return out
	if payload is Array:
		var out_array: Array = []
		for item in payload:
			out_array.append(_safe_log_payload(item))
		return out_array
	if payload is PackedStringArray:
		var strings: Array[String] = []
		for item in payload:
			strings.append(str(item))
		return strings
	if payload is PackedByteArray:
		return "<%d bytes>" % (payload as PackedByteArray).size()
	return payload


func _safe_arg_list(args: Array) -> Array:
	var safe: Array = []
	for arg in args:
		safe.append(_safe_log_payload(arg))
	return safe


func is_available() -> bool:
	var app_state := _app_state()
	if app_state != null and app_state.has_method("is_mobile_platform") and bool(app_state.call("is_mobile_platform")):
		_status = "Steam Workshop is unavailable on mobile."
		_log_upload_event("availability.mobile_blocked", _steam_diagnostics())
		return false
	var steam_client := _steam_client()
	if steam_client == null or not steam_client.has_method("is_ready") or not bool(steam_client.call("is_ready")):
		_status = "Steamworks is not initialized."
		_log_upload_event("availability.steam_client_not_ready", _steam_diagnostics())
		return false
	if not Engine.has_singleton("Steam"):
		_status = "Steam singleton is unavailable."
		_log_upload_event("availability.steam_singleton_missing", _steam_diagnostics())
		return false
	var steam: Object = Engine.get_singleton("Steam")
	var has_create := steam.has_method("createItem") or steam.has_method("create_item")
	var has_update := steam.has_method("startItemUpdate") or steam.has_method("start_item_update")
	if not has_create and not has_update:
		_status = "GodotSteam Workshop UGC APIs are unavailable in this build."
		_log_upload_event("availability.ugc_api_missing", _steam_diagnostics())
		return false
	_connect_steam_signals(steam)
	_status = "Steam Workshop ready."
	_log_upload_event("availability.ready", _steam_diagnostics())
	return true


func upload_pack(folder_path: String, upload_details: Variant = {}, existing_item_id: String = "") -> Dictionary:
	_upload_session_id = "%d_%d" % [Time.get_unix_time_from_system(), Time.get_ticks_msec()]
	_last_progress_log_key = ""
	var details := _normalize_upload_details(upload_details, existing_item_id)
	_log_upload_event("upload_pack.start", {
		"folder_path": folder_path,
		"normalized_item_id": str(details.get("existing_item_id", "")),
		"param_item_id": str(existing_item_id).strip_edges(),
		"details": _safe_log_payload(details),
		"steam": _steam_diagnostics(),
	})
	var validation := EMSValidator.validate_pack_folder(folder_path)
	if not bool(validation.get("ok", false)):
		_status = "EMS pack failed validation before upload."
		_log_upload_event("upload_pack.validation_failed", {
			"reason": _safe_log_payload(validation),
			"folder_path": folder_path
		})
		return _with_upload_log({"ok": false, "message": _status, "validation": validation, "item_id": str(details.get("existing_item_id", ""))})
	if _validation_has_video(validation):
		_status = "Video EMS packs cannot be uploaded to Steam Workshop. Export them for local testing instead."
		_log_upload_event("upload_pack.validation_video_blocked", {
			"folder_path": folder_path,
			"item_id": str(details.get("existing_item_id", "")),
			"validation": _safe_log_payload(validation)
		})
		return _with_upload_log({"ok": false, "message": _status, "validation": validation, "item_id": str(details.get("existing_item_id", ""))})
	var upload_metadata := _metadata_for_upload(validation, details)
	var manifest: Dictionary = validation.get("manifest", {}) as Dictionary
	var config: Dictionary = validation.get("config", {}) as Dictionary
	var metadata := {
		"hd_content_type": "ems",
		"hd_ems_type": "creator" if str(config.get("pack_type", "")) == EMSValidator.PACK_TYPE_CREATOR else "config",
		"schema_version": EMSValidator.SCHEMA_VERSION,
		"min_game_version": "1.0.0",
		"pack_id": str(config.get("pack_id", manifest.get("pack_id", ""))),
		"title": str(upload_metadata.get("title", "")),
	}
	var upload_payload := _build_upload_payload(folder_path, upload_metadata)
	_log_upload_event("upload_pack.payload_built", {
		"folder_path": folder_path,
		"item_id": str(details.get("existing_item_id", "")),
		"metadata_title": str(upload_metadata.get("title", "")),
		"metadata_description_len": str(upload_metadata.get("description", "")).length(),
		"metadata_change_note": str(upload_metadata.get("change_note", "")),
		"payload": _safe_log_payload(upload_payload),
		"manifest_title": str(manifest.get("title", "")),
		"config_title": str(config.get("title", "")),
		"manifest_song_count": int(manifest.get("song_count", 0)),
		"config_pack_type": str(config.get("pack_type", ""))
	})
	if not bool(upload_payload.get("ok", false)):
		_status = str(upload_payload.get("message", "EMS Workshop upload payload is invalid."))
		return _with_upload_log({"ok": false, "message": _status, "validation": validation, "item_id": str(details.get("existing_item_id", "")), "metadata": metadata, "upload_metadata": upload_metadata, "upload_payload": upload_payload})
	if bool(details.get("dry_run", false)):
		_status = "Steam Workshop upload dry run passed validation."
		return _with_upload_log({"ok": true, "dry_run": true, "message": _status, "validation": validation, "item_id": str(details.get("existing_item_id", "")), "metadata": metadata, "upload_metadata": upload_metadata, "upload_payload": upload_payload})
	if not _pending_create_upload.is_empty() or _pending_update_handle != 0 or _pending_retry_upload:
		_status = "A Steam Workshop upload is already in progress. Wait for Steam to finish the current item before starting another upload."
		_log_upload_event("upload_pack.already_in_progress", {"pending_create": not _pending_create_upload.is_empty(), "pending_handle": _pending_update_handle, "pending_retry": _pending_retry_upload})
		return _with_upload_log({"ok": false, "message": _status, "validation": validation, "item_id": str(details.get("existing_item_id", "")), "metadata": metadata, "upload_metadata": upload_metadata, "upload_payload": upload_payload})
	if not is_available():
		return _with_upload_log({"ok": false, "message": _status, "validation": validation, "item_id": str(details.get("existing_item_id", "")), "metadata": metadata, "upload_metadata": upload_metadata, "upload_payload": upload_payload})
	var steam: Object = Engine.get_singleton("Steam")
	var steam_client := _steam_client()
	var app_id := int(steam_client.call("get_app_id")) if steam_client != null and steam_client.has_method("get_app_id") else 0
	var item_id := str(details.get("existing_item_id", "")).strip_edges()
	_log_upload_event("upload_pack.steam_ready", _steam_diagnostics(app_id, item_id))
	if item_id.is_empty():
		var created := _call_first(steam, ["createItem", "create_item"], [app_id, 0])
		_log_upload_event("upload_pack.create_item_called", {
			"app_id": app_id,
			"api": "createItem/create_item",
			"call_result": _safe_log_payload(created)
		})
		if bool(created.get("called", false)):
			_pending_create_upload = {
				"folder_path": folder_path,
				"validation": validation,
				"details": details,
				"metadata": metadata,
				"upload_metadata": upload_metadata,
				"upload_payload": upload_payload,
			}
		_status = "Steam Workshop item creation requested. Upload will continue after Steam returns the item id."
		var response := _with_upload_log({"ok": bool(created.get("called", false)), "pending": bool(created.get("called", false)), "message": _status, "validation": validation, "item_id": "", "metadata": metadata, "upload_metadata": upload_metadata, "upload_payload": upload_payload})
		upload_status_changed.emit(response)
		return response
	return _submit_existing_item(folder_path, item_id, validation, details, metadata, upload_metadata, upload_payload)


func _submit_existing_item(folder_path: String, item_id: String, validation: Dictionary, details: Dictionary, metadata: Dictionary, upload_metadata: Dictionary, upload_payload: Dictionary = {}, retry_count: int = 0) -> Dictionary:
	if not is_available():
		return _emit_upload_status({"ok": false, "pending": false, "message": _status, "validation": validation, "item_id": item_id, "metadata": metadata, "upload_metadata": upload_metadata, "upload_payload": upload_payload, "retry_count": retry_count}, "submit_existing.not_available")
	var steam: Object = Engine.get_singleton("Steam")
	var steam_client := _steam_client()
	var app_id := int(steam_client.call("get_app_id")) if steam_client != null and steam_client.has_method("get_app_id") else 0
	var numeric_item_id := int(item_id)
	_log_upload_event("submit_existing.start", {
		"folder_path": folder_path,
		"item_id": item_id,
		"numeric_item_id": numeric_item_id,
		"app_id": app_id,
		"metadata_title": str(metadata.get("title", "")),
		"metadata_description": str(metadata.get("description", "")),
		"metadata_schema": str(metadata.get("schema_version", "")),
		"retry_count": retry_count,
		"visibility": str(upload_metadata.get("visibility", "private")),
		"payload_size_bytes": int(upload_payload.get("payload_size_bytes", 0)),
		"content_global_path": str(upload_payload.get("content_global_path", "")),
		"preview_global_path": str(upload_payload.get("preview_global_path", "")),
		"steam": _steam_diagnostics(app_id, item_id),
	})
	if numeric_item_id <= 0:
		_status = "Workshop item id is invalid."
		_log_upload_event("submit_existing.invalid_item_id", {
			"item_id": item_id,
			"numeric_item_id": numeric_item_id,
			"app_id": app_id
		})
		return _emit_upload_status({"ok": false, "message": _status, "validation": validation, "item_id": item_id, "metadata": metadata, "upload_metadata": upload_metadata, "upload_payload": upload_payload, "retry_count": retry_count}, "submit_existing.invalid_item_id")
	if upload_payload.is_empty():
		upload_payload = _build_upload_payload(folder_path, upload_metadata)
	if not bool(upload_payload.get("ok", false)):
		_status = str(upload_payload.get("message", "EMS Workshop upload payload is invalid."))
		return _emit_upload_status({"ok": false, "message": _status, "validation": validation, "item_id": item_id, "metadata": metadata, "upload_metadata": upload_metadata, "upload_payload": upload_payload, "retry_count": retry_count}, "submit_existing.payload_invalid")
	var update_handle := _call_first(steam, ["startItemUpdate", "start_item_update"], [app_id, numeric_item_id])
	_log_upload_event("submit_existing.start_item_update", {
		"called": bool(update_handle.get("called", false)),
		"raw_value": _safe_log_payload(update_handle.get("value", null)),
		"value_type": _variant_type_name(update_handle.get("value", null)),
		"numeric_item_id": numeric_item_id,
		"app_id": app_id,
		"retry_count": retry_count
	})
	if not bool(update_handle.get("called", false)):
		_status = "Steam Workshop update APIs are unavailable."
		return _emit_upload_status({"ok": false, "message": _status, "validation": validation, "item_id": item_id, "metadata": metadata, "upload_metadata": upload_metadata, "upload_payload": upload_payload, "api_result": update_handle, "retry_count": retry_count}, "submit_existing.update_api_unavailable")
	var handle: Variant = update_handle.get("value", 0)
	var handle_type := _variant_type_name(handle)
	if int(handle) <= 0:
		if retry_count < INVALID_HANDLE_MAX_RETRIES:
			_pending_retry_upload = true
			_status = "Steam Workshop did not return a valid update handle. Retrying once in %.0f seconds." % INVALID_HANDLE_RETRY_DELAY_SEC
			var retrying := _with_upload_log({"ok": true, "pending": true, "message": _status, "validation": validation, "item_id": item_id, "metadata": metadata, "upload_metadata": upload_metadata, "upload_payload": upload_payload, "api_result": update_handle, "retry_count": retry_count, "retry_scheduled": true})
			_log_upload_event("submit_existing.invalid_handle_retry_scheduled", _safe_log_payload(retrying))
			upload_status_changed.emit(retrying)
			_retry_submit_existing_item_after_delay(folder_path, item_id, validation, details, metadata, upload_metadata, upload_payload, retry_count + 1)
			return retrying
		_pending_retry_upload = false
		_status = "Steam Workshop did not return a valid update handle after retry."
		_log_upload_event("submit_existing.invalid_handle", {
			"item_id": item_id,
			"numeric_item_id": numeric_item_id,
			"handle": _safe_log_payload(handle),
			"handle_type": handle_type,
			"api_result": _safe_log_payload(update_handle),
			"retry_count": retry_count
		})
		return _emit_upload_status({"ok": false, "pending": false, "message": _status, "validation": validation, "item_id": item_id, "metadata": metadata, "upload_metadata": upload_metadata, "upload_payload": upload_payload, "api_result": update_handle, "retry_count": retry_count}, "submit_existing.invalid_handle_final")
	_pending_retry_upload = false
	_log_upload_event("submit_existing.handle_validated", {
		"item_id": item_id,
		"handle": int(handle),
		"handle_type": handle_type
	})
	_pending_update_item_id = item_id
	_pending_update_visibility = str(upload_metadata.get("visibility", "private"))
	_pending_update_handle = int(handle)
	_pending_update_progress.clear()
	_last_progress_log_key = ""
	var setup_failures: Array[String] = []
	var setup_results: Dictionary = {}
	setup_results["language"] = _call_optional_ugc_setter(steam, ["setItemUpdateLanguage", "set_item_update_language"], [handle, "english"])
	setup_results["title"] = _call_required_ugc_setter(steam, ["setItemTitle", "set_item_title"], [handle, str(upload_metadata.get("title", "Harmonic Drive EMS"))], "title", setup_failures)
	setup_results["description"] = _call_required_ugc_setter(steam, ["setItemDescription", "set_item_description"], [handle, str(upload_metadata.get("description", ""))], "description", setup_failures)
	setup_results["tags"] = _call_required_ugc_setter(steam, ["setItemTags", "set_item_tags"], [handle, _workshop_tags(upload_metadata.get("tags", [])), false], "tags", setup_failures)
	setup_results["visibility"] = _call_required_ugc_setter(steam, ["setItemVisibility", "set_item_visibility"], [handle, _visibility_value(str(upload_metadata.get("visibility", "private")))], "visibility", setup_failures)
	setup_results["preview"] = _call_required_ugc_setter(steam, ["setItemPreview", "set_item_preview"], [handle, str(upload_payload.get("preview_global_path", ""))], "preview image", setup_failures)
	setup_results["content"] = _call_required_ugc_setter(steam, ["setItemContent", "set_item_content"], [handle, str(upload_payload.get("content_global_path", ""))], "content folder", setup_failures)
	setup_results["metadata"] = _call_required_ugc_setter(steam, ["setItemMetadata", "set_item_metadata"], [handle, JSON.stringify(metadata)], "metadata", setup_failures)
	if not setup_failures.is_empty():
		_pending_retry_upload = false
		_pending_update_item_id = ""
		_pending_update_visibility = ""
		_pending_update_handle = 0
		_update_progress_poll_active = false
		_status = "Steam Workshop upload setup failed: %s." % "; ".join(setup_failures)
		var setup_failed := {"ok": false, "message": _status, "validation": validation, "item_id": item_id, "metadata": metadata, "upload_metadata": upload_metadata, "upload_payload": upload_payload, "setter_failures": setup_failures, "api_results": setup_results}
		_log_upload_event("submit_existing.setup_failed", {
			"item_id": item_id,
			"setup_failures": setup_failures,
			"setter_results": _safe_log_payload(setup_results)
		})
		return _emit_upload_status(setup_failed, "submit_existing.setup_failed")
	_log_upload_event("submit_existing.setup_complete", {
		"item_id": item_id,
		"setup_results": _safe_log_payload(setup_results)
	})
	var submitted := _call_first(steam, ["submitItemUpdate", "submit_item_update"], [handle, str(upload_metadata.get("change_note", "Updated Harmonic Drive EMS pack."))])
	_log_upload_event("submit_existing.submit_called", {
		"item_id": item_id,
		"called": bool(submitted.get("called", false)),
		"api_result": _safe_log_payload(submitted)
	})
	if not bool(submitted.get("called", false)):
		_pending_retry_upload = false
		_pending_update_item_id = ""
		_pending_update_visibility = ""
		_pending_update_handle = 0
		_update_progress_poll_active = false
	else:
		_begin_update_progress_poll(int(handle), item_id, _pending_update_visibility, upload_payload)
	_status = "Steam Workshop item update submitted. Waiting for Steam to finish processing item %s." % item_id if bool(submitted.get("called", false)) else "Steam Workshop submit API unavailable."
	var response := {"ok": bool(submitted.get("called", false)), "pending": bool(submitted.get("called", false)), "message": _status, "validation": validation, "item_id": item_id, "metadata": metadata, "upload_metadata": upload_metadata, "upload_payload": upload_payload, "api_results": setup_results, "submit_api_result": submitted, "retry_count": retry_count}
	return _emit_upload_status(response, "submit_existing.submitted" if bool(submitted.get("called", false)) else "submit_existing.submit_unavailable")


func refresh_subscriptions() -> Dictionary:
	EMSPackLoader.ensure_user_dirs()
	if not is_available():
		return {"ok": false, "message": _status, "items": []}
	var steam: Object = Engine.get_singleton("Steam")
	var item_ids: Array = []
	var count_result := _call_first(steam, ["getNumSubscribedItems", "get_num_subscribed_items"], [])
	if bool(count_result.get("called", false)):
		var count := int(count_result.get("value", 0))
		var items_result := _call_first(steam, ["getSubscribedItems", "get_subscribed_items"], [count])
		if bool(items_result.get("called", false)) and items_result.get("value") is Array:
			item_ids = items_result.get("value") as Array
	var loaded: Array[Dictionary] = []
	for item_id_variant in item_ids:
		var item_id := str(item_id_variant)
		var info_result := _call_first(steam, ["getItemInstallInfo", "get_item_install_info"], [int(item_id)])
		if not bool(info_result.get("called", false)) or info_result.get("value") is not Dictionary:
			continue
		var info: Dictionary = info_result.get("value", {}) as Dictionary
		var source_folder := str(info.get("folder", info.get("install_folder", "")))
		if source_folder.is_empty():
			continue
		var validation := EMSValidator.validate_pack_folder(source_folder)
		if not bool(validation.get("ok", false)):
			continue
		var exported := EMSPackLoader.copy_validated_pack_to_root(source_folder, EMSPackLoader.WORKSHOP_ROOT, item_id)
		if bool(exported.get("ok", false)):
			loaded.append({"item_id": item_id, "path": str(exported.get("path", ""))})
	_status = "Steam Workshop subscriptions refreshed."
	return {"ok": true, "message": _status, "items": loaded}


func get_status() -> String:
	return _status


func is_playtime_tracking_available() -> bool:
	var app_state := _app_state()
	if app_state != null and app_state.has_method("is_mobile_platform") and bool(app_state.call("is_mobile_platform")):
		_playtime_status = "Steam Workshop playtime tracking is unavailable on mobile."
		return false
	var steam_client := _steam_client()
	if steam_client == null or not steam_client.has_method("is_ready") or not bool(steam_client.call("is_ready")):
		_playtime_status = "Steamworks is not initialized."
		return false
	if not Engine.has_singleton("Steam"):
		_playtime_status = "Steam singleton is unavailable."
		return false
	var steam: Object = Engine.get_singleton("Steam")
	if not steam.has_method("startPlaytimeTracking") or not steam.has_method("stopPlaytimeTracking") or not steam.has_method("stopPlaytimeTrackingForAllItems"):
		_playtime_status = "GodotSteam Workshop playtime APIs are unavailable in this build."
		return false
	_connect_playtime_signals(steam)
	_playtime_status = "Steam Workshop playtime tracking ready."
	return true


func set_active_playtime_item(item_id: String) -> Dictionary:
	var normalized_id := item_id.strip_edges()
	if normalized_id == _active_playtime_item_id:
		return {"ok": true, "message": _playtime_status, "item_id": _active_playtime_item_id, "already_active": true}
	if not _active_playtime_item_id.is_empty():
		stop_playtime_tracking(_active_playtime_item_id)
	if normalized_id.is_empty():
		_active_playtime_item_id = ""
		_playtime_status = "Steam Workshop playtime tracking stopped."
		return {"ok": true, "message": _playtime_status, "item_id": ""}
	return start_playtime_tracking(normalized_id)


func start_playtime_tracking(item_id: String) -> Dictionary:
	var normalized_id := item_id.strip_edges()
	if not normalized_id.is_valid_int() or int(normalized_id) <= 0:
		_playtime_status = "Workshop playtime item id is invalid."
		return {"ok": false, "message": _playtime_status, "item_id": normalized_id}
	if not is_playtime_tracking_available():
		return {"ok": false, "message": _playtime_status, "item_id": normalized_id}
	var steam: Object = Engine.get_singleton("Steam")
	var ids := PackedInt64Array()
	ids.append(int(normalized_id))
	var result := _call_first(steam, ["startPlaytimeTracking"], [ids])
	var ok := bool(result.get("called", false))
	_active_playtime_item_id = normalized_id if ok else ""
	_playtime_status = "Started Steam Workshop playtime tracking for item %s." % normalized_id if ok else "Steam Workshop startPlaytimeTracking API unavailable."
	var response := {"ok": ok, "message": _playtime_status, "item_id": normalized_id, "api_call": result.get("value", null)}
	playtime_status_changed.emit(response)
	return response


func stop_playtime_tracking(item_id: String = "") -> Dictionary:
	var normalized_id := item_id.strip_edges()
	if normalized_id.is_empty():
		normalized_id = _active_playtime_item_id
	if normalized_id.is_empty():
		_playtime_status = "Steam Workshop playtime tracking idle."
		return {"ok": true, "message": _playtime_status, "item_id": ""}
	if not normalized_id.is_valid_int() or int(normalized_id) <= 0:
		_playtime_status = "Workshop playtime item id is invalid."
		return {"ok": false, "message": _playtime_status, "item_id": normalized_id}
	if not is_playtime_tracking_available():
		return {"ok": false, "message": _playtime_status, "item_id": normalized_id}
	var steam: Object = Engine.get_singleton("Steam")
	var ids := PackedInt64Array()
	ids.append(int(normalized_id))
	var result := _call_first(steam, ["stopPlaytimeTracking"], [ids])
	var ok := bool(result.get("called", false))
	if normalized_id == _active_playtime_item_id:
		_active_playtime_item_id = ""
	_playtime_status = "Stopped Steam Workshop playtime tracking for item %s." % normalized_id if ok else "Steam Workshop stopPlaytimeTracking API unavailable."
	var response := {"ok": ok, "message": _playtime_status, "item_id": normalized_id, "api_call": result.get("value", null)}
	playtime_status_changed.emit(response)
	return response


func stop_all_playtime_tracking() -> Dictionary:
	if not is_playtime_tracking_available():
		return {"ok": false, "message": _playtime_status, "item_id": _active_playtime_item_id}
	var steam: Object = Engine.get_singleton("Steam")
	var result := _call_first(steam, ["stopPlaytimeTrackingForAllItems"], [])
	var ok := bool(result.get("called", false))
	_active_playtime_item_id = ""
	_playtime_status = "Stopped Steam Workshop playtime tracking for all items." if ok else "Steam Workshop stopPlaytimeTrackingForAllItems API unavailable."
	var response := {"ok": ok, "message": _playtime_status, "item_id": "", "api_call": result.get("value", null)}
	playtime_status_changed.emit(response)
	return response


func get_playtime_status() -> Dictionary:
	return {
		"message": _playtime_status,
		"active_item_id": _active_playtime_item_id,
		"available": is_playtime_tracking_available(),
	}


func _on_workshop_item_created(result: Variant = null, published_file_id: Variant = null, needs_legal_agreement: Variant = null) -> void:
	_log_upload_event("signal.item_created", {
		"result_raw": _safe_log_payload(result),
		"published_file_id_raw": _safe_log_payload(published_file_id),
		"needs_legal_agreement_raw": _safe_log_payload(needs_legal_agreement),
		"pending_create": not _pending_create_upload.is_empty(),
	})
	if _pending_create_upload.is_empty():
		_log_upload_event("signal.item_created.ignored", {})
		return
	var item_id := _extract_item_id([result, published_file_id, needs_legal_agreement])
	var legal_required := _extract_needs_legal_agreement([result, published_file_id, needs_legal_agreement])
	if item_id.is_empty():
		_status = "Steam Workshop item creation did not return an item id."
		var failed := {"ok": false, "message": _status, "item_id": "", "pending": false}
		_pending_create_upload.clear()
		_emit_upload_status(failed, "signal.item_created.no_id")
		return
	var pending := _pending_create_upload.duplicate(true)
	_pending_create_upload.clear()
	var details: Dictionary = pending.get("details", {}) as Dictionary
	details["existing_item_id"] = item_id
	details["workshop_item_id"] = item_id
	_status = "Steam Workshop item %s created. Waiting briefly before uploading the EMS content package." % item_id
	_emit_upload_status({"ok": true, "pending": true, "message": _status, "item_id": item_id, "needs_legal_agreement": legal_required}, "signal.item_created.continuing")
	_submit_created_item_after_delay(item_id, legal_required, pending)


func _submit_created_item_after_delay(item_id: String, legal_required: bool, pending: Dictionary) -> void:
	_log_upload_event("submit_created_item_after_delay.start", {
		"item_id": item_id,
		"needs_legal_agreement": legal_required,
		"pending_keys": pending.keys()
	})
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		await tree.create_timer(0.75).timeout
	var details: Dictionary = pending.get("details", {}) as Dictionary
	details["existing_item_id"] = item_id
	details["workshop_item_id"] = item_id
	var response := _submit_existing_item(
		str(pending.get("folder_path", "")),
		item_id,
		pending.get("validation", {}) as Dictionary,
		details,
		pending.get("metadata", {}) as Dictionary,
		pending.get("upload_metadata", {}) as Dictionary,
		pending.get("upload_payload", {}) as Dictionary
	)
	_log_upload_event("submit_created_item_after_delay.completed", {
		"item_id": item_id,
		"legal_required": legal_required,
		"response": _safe_log_payload(response)
	})
	if legal_required:
		response["needs_legal_agreement"] = true
		response["message"] = "%s Accept the Steam Workshop legal agreement in Steam if prompted." % str(response.get("message", ""))
		_status = str(response.get("message", _status))
		_emit_upload_status(response, "submit_created_item_after_delay.legal_notice")


func _on_workshop_item_updated(result: Variant = null, needs_legal_agreement: Variant = null, published_file_id: Variant = null) -> void:
	_log_upload_event("signal.item_updated.raw", {
		"result_raw": _safe_log_payload(result),
		"needs_legal_agreement_raw": _safe_log_payload(needs_legal_agreement),
		"published_file_id_raw": _safe_log_payload(published_file_id),
		"pending_item_id": _pending_update_item_id,
		"pending_handle": _pending_update_handle
	})
	var result_code := _extract_result_code([result, needs_legal_agreement, published_file_id])
	var success := result == null or result_code == 1 or result_code == 0
	var item_id := _pending_update_item_id
	if item_id.is_empty():
		item_id = _extract_item_id([result, needs_legal_agreement, published_file_id])
	var visibility := _pending_update_visibility
	var needs_legal := _extract_needs_legal_agreement([result, needs_legal_agreement, published_file_id])
	_pending_update_item_id = ""
	_pending_update_visibility = ""
	_pending_update_handle = 0
	_update_progress_poll_active = false
	_pending_retry_upload = false
	_status = "Steam Workshop upload completed for item %s." % item_id if success and not item_id.is_empty() else "Steam Workshop upload completed." if success else "Steam Workshop upload finished with result code %d (%s)." % [result_code, _steam_result_name(result_code)]
	var response := {"ok": success, "pending": false, "message": _status, "item_id": item_id, "visibility": visibility, "needs_legal_agreement": needs_legal, "result_code": result_code, "result_name": _steam_result_name(result_code), "upload_progress": _pending_update_progress.duplicate(true), "api_result": {"result": result, "needs_legal_agreement": needs_legal_agreement, "published_file_id": published_file_id}}
	_emit_upload_status(response, "signal.item_updated.emit")


func _on_start_playtime_tracking(result: Variant = null) -> void:
	_playtime_status = "Steam Workshop playtime tracking started."
	playtime_status_changed.emit({"ok": true, "message": _playtime_status, "item_id": _active_playtime_item_id, "result": result})


func _on_stop_playtime_tracking(result: Variant = null) -> void:
	_playtime_status = "Steam Workshop playtime tracking stopped."
	playtime_status_changed.emit({"ok": true, "message": _playtime_status, "item_id": _active_playtime_item_id, "result": result})


func _call_required_ugc_setter(target: Object, method_names: Array[String], args: Array, label: String, failures: Array[String]) -> Dictionary:
	_log_upload_event("ugc_setter.required.call", {
		"label": label,
		"methods": method_names,
		"args": _safe_arg_list(args)
	})
	var result := _call_first(target, method_names, args)
	_log_upload_event("ugc_setter.required.result", {
		"label": label,
		"methods": method_names,
		"called": bool(result.get("called", false)),
		"result": _safe_log_payload(result.get("value", null)),
		"result_type": _variant_type_name(result.get("value", null))
	})
	if not bool(result.get("called", false)):
		failures.append("%s API unavailable" % label)
		return result
	if not _is_steam_api_call_ok(result.get("value", null)):
		failures.append("%s rejected by Steam API" % label)
	return result


func _is_steam_api_call_ok(value: Variant) -> bool:
	if value == null:
		return false
	if value is bool:
		return bool(value)
	if value is int:
		# GodotSteam methods commonly return non-zero success as int in some versions.
		return int(value) > 0
	if value is float:
		return float(value) > 0.0
	if value is String:
		return not str(value).strip_edges().is_empty()
	return true


func _call_optional_ugc_setter(target: Object, method_names: Array[String], args: Array) -> Dictionary:
	_log_upload_event("ugc_setter.optional.call", {
		"methods": method_names,
		"args": _safe_arg_list(args)
	})
	var result := _call_first(target, method_names, args)
	_log_upload_event("ugc_setter.optional.result", {
		"methods": method_names,
		"called": bool(result.get("called", false)),
		"result": _safe_log_payload(result.get("value", null)),
		"result_type": _variant_type_name(result.get("value", null))
	})
	return result


func _call_first(target: Object, method_names: Array[String], args: Array) -> Dictionary:
	if target == null:
		return {"called": false, "value": null}
	for method_name in method_names:
		if target.has_method(method_name):
			var result: Variant = target.callv(method_name, args)
			return {"called": true, "value": result}
	return {"called": false, "value": null}


func _emit_upload_status(response: Dictionary, event_name: String) -> Dictionary:
	var enriched := _with_upload_log(response)
	_log_upload_event(event_name, _safe_log_payload(enriched))
	upload_status_changed.emit(enriched)
	return enriched


func _with_upload_log(response: Dictionary) -> Dictionary:
	response["upload_log_path"] = WORKSHOP_UPLOAD_LOG_FILE
	response["upload_log_global_path"] = ProjectSettings.globalize_path(WORKSHOP_UPLOAD_LOG_FILE)
	if not _upload_session_id.is_empty():
		response["upload_session_id"] = _upload_session_id
	return response


func _steam_diagnostics(app_id: int = 0, item_id: String = "") -> Dictionary:
	var steam_client := _steam_client()
	var steam_ready := steam_client != null and steam_client.has_method("is_ready") and bool(steam_client.call("is_ready"))
	var steam_status := ""
	if steam_client != null and steam_client.has_method("get_status_text"):
		steam_status = str(steam_client.call("get_status_text"))
	var resolved_app_id := app_id
	if resolved_app_id <= 0 and steam_client != null and steam_client.has_method("get_app_id"):
		resolved_app_id = int(steam_client.call("get_app_id"))
	var steam_id := ""
	if steam_client != null and steam_client.has_method("get_steam_id"):
		steam_id = str(steam_client.call("get_steam_id")).strip_edges()
	if steam_id.is_empty() and Engine.has_singleton("Steam"):
		var steam: Object = Engine.get_singleton("Steam")
		if steam.has_method("getSteamID"):
			steam_id = str(steam.call("getSteamID")).strip_edges()
			if steam_id == "0":
				steam_id = ""
	return {
		"steam_client_present": steam_client != null,
		"steam_client_ready": steam_ready,
		"steam_status": steam_status,
		"steam_singleton_present": Engine.has_singleton("Steam"),
		"app_id": resolved_app_id,
		"steam_id": steam_id,
		"item_id": item_id,
	}


func _normalize_upload_details(upload_details: Variant, existing_item_id: String) -> Dictionary:
	var details: Dictionary = {}
	if upload_details is Dictionary:
		details = (upload_details as Dictionary).duplicate(true)
	elif upload_details != null and not str(upload_details).strip_edges().is_empty():
		details["existing_item_id"] = str(upload_details).strip_edges()
	if not existing_item_id.strip_edges().is_empty():
		details["existing_item_id"] = existing_item_id.strip_edges()
	if not details.has("workshop_item_id"):
		details["workshop_item_id"] = str(details.get("existing_item_id", ""))
	if not details.has("existing_item_id"):
		details["existing_item_id"] = str(details.get("workshop_item_id", ""))
	return details


func _metadata_for_upload(validation: Dictionary, details: Dictionary) -> Dictionary:
	var manifest: Dictionary = validation.get("manifest", {}) as Dictionary
	var config: Dictionary = validation.get("config", {}) as Dictionary
	var title := str(details.get("title", manifest.get("title", config.get("title", "Harmonic Drive EMS")))).strip_edges()
	if title.is_empty():
		title = "Harmonic Drive EMS"
	var description := str(details.get("description", manifest.get("description", config.get("description", "")))).strip_edges()
	var tags := _workshop_tags(details.get("tags", manifest.get("tags", WORKSHOP_TAGS)))
	var preview_path := str(validation.get("preview_path", "")).strip_edges()
	return {
		"title": title,
		"description": description,
		"tags": tags,
		"visibility": str(details.get("visibility", details.get("workshop_visibility", "private"))),
		"change_note": str(details.get("change_note", "Updated Harmonic Drive EMS pack.")),
		"preview_path": preview_path,
	}


func _build_upload_payload(folder_path: String, upload_metadata: Dictionary) -> Dictionary:
	var content_global_path := ProjectSettings.globalize_path(folder_path)
	var preview_path := str(upload_metadata.get("preview_path", "")).strip_edges()
	if preview_path.is_empty():
		preview_path = folder_path.path_join(EMSValidator.PREVIEW_FILE)
	var source_preview_global_path := _globalize_if_needed(preview_path)
	if not DirAccess.dir_exists_absolute(content_global_path):
		return {"ok": false, "message": "Steam Workshop content folder does not exist: %s" % content_global_path, "content_path": folder_path, "content_global_path": content_global_path, "preview_path": preview_path, "source_preview_global_path": source_preview_global_path, "preview_global_path": source_preview_global_path, "payload_size_bytes": 0}
	if not FileAccess.file_exists(source_preview_global_path):
		return {"ok": false, "message": "Steam Workshop preview image does not exist: %s" % source_preview_global_path, "content_path": folder_path, "content_global_path": content_global_path, "preview_path": preview_path, "source_preview_global_path": source_preview_global_path, "preview_global_path": source_preview_global_path, "payload_size_bytes": 0}
	var prepared_preview := _prepare_steam_preview_image(preview_path, source_preview_global_path, folder_path)
	if not bool(prepared_preview.get("ok", false)):
		return {"ok": false, "message": str(prepared_preview.get("message", "Could not prepare Steam Workshop preview image.")), "content_path": folder_path, "content_global_path": content_global_path, "preview_path": preview_path, "source_preview_global_path": source_preview_global_path, "preview_global_path": source_preview_global_path, "payload_size_bytes": 0}
	var steam_preview_path := str(prepared_preview.get("preview_path", preview_path))
	var preview_global_path := str(prepared_preview.get("preview_global_path", source_preview_global_path))
	var preview_size := _file_size_bytes(preview_global_path)
	if preview_size <= 0:
		return {"ok": false, "message": "Steam Workshop preview image is empty: %s" % preview_global_path, "content_path": folder_path, "content_global_path": content_global_path, "preview_path": steam_preview_path, "source_preview_path": preview_path, "source_preview_global_path": source_preview_global_path, "preview_global_path": preview_global_path, "payload_size_bytes": 0, "preview_size_bytes": preview_size}
	if preview_size > STEAM_PREVIEW_MAX_BYTES:
		return {"ok": false, "message": "Steam Workshop preview image is too large after export: %s. Use an image under 1 MB." % _bytes_text(preview_size), "content_path": folder_path, "content_global_path": content_global_path, "preview_path": steam_preview_path, "source_preview_path": preview_path, "source_preview_global_path": source_preview_global_path, "preview_global_path": preview_global_path, "payload_size_bytes": 0, "preview_size_bytes": preview_size}
	var payload_size := _folder_payload_size_bytes(content_global_path)
	if payload_size <= 0:
		return {"ok": false, "message": "Steam Workshop content folder is empty: %s" % content_global_path, "content_path": folder_path, "content_global_path": content_global_path, "preview_path": steam_preview_path, "source_preview_path": preview_path, "source_preview_global_path": source_preview_global_path, "preview_global_path": preview_global_path, "payload_size_bytes": payload_size, "preview_size_bytes": preview_size}
	return {"ok": true, "message": "Steam Workshop payload ready.", "content_path": folder_path, "content_global_path": content_global_path, "preview_path": steam_preview_path, "source_preview_path": preview_path, "source_preview_global_path": source_preview_global_path, "preview_global_path": preview_global_path, "payload_size_bytes": payload_size, "preview_size_bytes": preview_size, "steam_preview_size": STEAM_PREVIEW_SIZE}


func _prepare_steam_preview_image(source_preview_path: String, source_preview_global_path: String, folder_path: String) -> Dictionary:
	var source_image := Image.load_from_file(source_preview_global_path)
	if source_image == null or source_image.is_empty():
		return {"ok": false, "message": "Could not read Steam Workshop preview image: %s" % source_preview_global_path}
	if source_image.get_format() != Image.FORMAT_RGBA8:
		source_image.convert(Image.FORMAT_RGBA8)
	var crop_rect := _square_crop_rect_for_preview(source_image)
	var cropped := Image.create(crop_rect.size.x, crop_rect.size.y, false, Image.FORMAT_RGBA8)
	cropped.fill(_preview_background_color(source_image))
	cropped.blit_rect(source_image, crop_rect, Vector2i.ZERO)
	cropped.resize(STEAM_PREVIEW_SIZE, STEAM_PREVIEW_SIZE, Image.INTERPOLATE_LANCZOS)
	_make_preview_opaque(cropped, _preview_background_color(source_image))
	var steam_preview_path := folder_path.path_join(STEAM_PREVIEW_FILE)
	var steam_preview_global_path := _globalize_if_needed(steam_preview_path)
	DirAccess.make_dir_recursive_absolute(steam_preview_global_path.get_base_dir())
	var save_err := cropped.save_png(steam_preview_global_path)
	if save_err != OK:
		return {"ok": false, "message": "Could not write Steam Workshop preview image: %s" % steam_preview_global_path}
	return {
		"ok": true,
		"message": "Prepared Steam Workshop preview image.",
		"preview_path": steam_preview_path,
		"preview_global_path": steam_preview_global_path,
		"source_preview_path": source_preview_path,
		"source_preview_global_path": source_preview_global_path,
	}


func _square_crop_rect_for_preview(image: Image) -> Rect2i:
	var width := image.get_width()
	var height := image.get_height()
	var side := mini(width, height)
	var foreground_rect := _foreground_rect_for_preview(image)
	if foreground_rect.size.x > 0 and foreground_rect.size.y > 0:
		var full_area := float(maxi(1, width * height))
		var foreground_area := float(foreground_rect.size.x * foreground_rect.size.y)
		if foreground_area < full_area * 0.78:
			var padded_side := int(ceil(float(maxi(foreground_rect.size.x, foreground_rect.size.y)) * (1.0 + STEAM_PREVIEW_FOREGROUND_PADDING * 2.0)))
			side = clampi(padded_side, 1, side)
			var center := Vector2(
				float(foreground_rect.position.x) + float(foreground_rect.size.x) * 0.5,
				float(foreground_rect.position.y) + float(foreground_rect.size.y) * 0.5
			)
			var x := clampi(int(round(center.x - float(side) * 0.5)), 0, maxi(0, width - side))
			var y := clampi(int(round(center.y - float(side) * 0.5)), 0, maxi(0, height - side))
			return Rect2i(Vector2i(x, y), Vector2i(side, side))
	var origin := Vector2i((width - side) / 2, (height - side) / 2)
	return Rect2i(origin, Vector2i(side, side))


func _foreground_rect_for_preview(image: Image) -> Rect2i:
	var width := image.get_width()
	var height := image.get_height()
	var background := _preview_background_color(image)
	var step := maxi(1, int(ceil(float(maxi(width, height)) / 512.0)))
	var min_x := width
	var min_y := height
	var max_x := -1
	var max_y := -1
	for y in range(0, height, step):
		for x in range(0, width, step):
			var color := image.get_pixel(x, y)
			if color.a <= 0.01:
				continue
			if _preview_color_distance(color, background) <= STEAM_PREVIEW_FOREGROUND_THRESHOLD:
				continue
			min_x = mini(min_x, x)
			min_y = mini(min_y, y)
			max_x = maxi(max_x, x)
			max_y = maxi(max_y, y)
	if max_x < min_x or max_y < min_y:
		return Rect2i(Vector2i.ZERO, Vector2i.ZERO)
	return Rect2i(Vector2i(min_x, min_y), Vector2i(mini(width - min_x, max_x - min_x + step), mini(height - min_y, max_y - min_y + step)))


func _preview_background_color(image: Image) -> Color:
	var width := image.get_width()
	var height := image.get_height()
	if width <= 0 or height <= 0:
		return Color(0.02, 0.03, 0.08, 1.0)
	var samples := [
		image.get_pixel(0, 0),
		image.get_pixel(width - 1, 0),
		image.get_pixel(0, height - 1),
		image.get_pixel(width - 1, height - 1)
	]
	var total := Color(0, 0, 0, 0)
	for sample in samples:
		total.r += sample.r
		total.g += sample.g
		total.b += sample.b
		total.a += sample.a
	return Color(total.r / 4.0, total.g / 4.0, total.b / 4.0, maxf(total.a / 4.0, 1.0))


func _preview_color_distance(a: Color, b: Color) -> float:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) + absf(a.a - b.a) * 0.25


func _make_preview_opaque(image: Image, background: Color) -> void:
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color := image.get_pixel(x, y)
			if color.a >= 0.995:
				continue
			var alpha := clampf(color.a, 0.0, 1.0)
			image.set_pixel(x, y, Color(
				lerpf(background.r, color.r, alpha),
				lerpf(background.g, color.g, alpha),
				lerpf(background.b, color.b, alpha),
				1.0
			))


func _globalize_if_needed(path: String) -> String:
	if path.begins_with("user://") or path.begins_with("res://"):
		return ProjectSettings.globalize_path(path)
	return path


func _folder_payload_size_bytes(global_folder_path: String) -> int:
	var total := 0
	var dir := DirAccess.open(global_folder_path)
	if dir == null:
		return 0
	dir.list_dir_begin()
	while true:
		var entry_name := dir.get_next()
		if entry_name.is_empty():
			break
		if entry_name == "." or entry_name == "..":
			continue
		var child_path := global_folder_path.path_join(entry_name)
		if dir.current_is_dir():
			total += _folder_payload_size_bytes(child_path)
		else:
			var file := FileAccess.open(child_path, FileAccess.READ)
			if file != null:
				total += int(file.get_length())
	dir.list_dir_end()
	return total


func _file_size_bytes(global_file_path: String) -> int:
	var file := FileAccess.open(global_file_path, FileAccess.READ)
	if file == null:
		return 0
	return int(file.get_length())


func _retry_submit_existing_item_after_delay(folder_path: String, item_id: String, validation: Dictionary, details: Dictionary, metadata: Dictionary, upload_metadata: Dictionary, upload_payload: Dictionary, retry_count: int) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		await tree.create_timer(INVALID_HANDLE_RETRY_DELAY_SEC).timeout
	_pending_retry_upload = false
	_log_upload_event("submit_existing.invalid_handle_retry_begin", {
		"item_id": item_id,
		"retry_count": retry_count,
	})
	_submit_existing_item(folder_path, item_id, validation, details, metadata, upload_metadata, upload_payload, retry_count)


func _begin_update_progress_poll(handle: int, item_id: String, visibility: String, upload_payload: Dictionary) -> void:
	if handle <= 0:
		return
	_pending_update_handle = handle
	_update_progress_poll_active = true
	_log_upload_event("progress_poll.begin", {
		"handle": handle,
		"item_id": item_id,
		"visibility": visibility,
	})
	_poll_update_progress_loop(handle, item_id, visibility, upload_payload)


func _poll_update_progress_loop(handle: int, item_id: String, visibility: String, upload_payload: Dictionary) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var polls := 0
	while _update_progress_poll_active and _pending_update_handle == handle and polls < 240:
		await tree.create_timer(0.75).timeout
		if not _update_progress_poll_active or _pending_update_handle != handle:
			break
		if not Engine.has_singleton("Steam"):
			break
		var steam: Object = Engine.get_singleton("Steam")
		var progress_result := _call_first(steam, ["getItemUpdateProgress", "get_item_update_progress"], [handle])
		if bool(progress_result.get("called", false)):
			_pending_update_progress = _normalize_update_progress(progress_result.get("value", {}))
			var progress_key := JSON.stringify(_pending_update_progress)
			if progress_key != _last_progress_log_key:
				_last_progress_log_key = progress_key
				_log_upload_event("progress_poll.update", {
					"handle": handle,
					"item_id": item_id,
					"progress": _safe_log_payload(_pending_update_progress),
				})
			_status = _format_update_progress_status(item_id, _pending_update_progress)
			upload_status_changed.emit(_with_upload_log({
				"ok": true,
				"pending": true,
				"message": _status,
				"item_id": item_id,
				"visibility": visibility,
				"upload_progress": _pending_update_progress.duplicate(true),
				"upload_payload": upload_payload,
			}))
		polls += 1


func _normalize_update_progress(value: Variant) -> Dictionary:
	if value is Dictionary:
		var progress := (value as Dictionary).duplicate(true)
		var status := int(progress.get("status", progress.get("update_status", progress.get("state", -1))))
		progress["status"] = status
		progress["status_name"] = _ugc_update_status_name(status)
		var processed := int(progress.get("processed", progress.get("bytes_processed", progress.get("processed_bytes", 0))))
		var total := int(progress.get("total", progress.get("bytes_total", progress.get("total_bytes", 0))))
		progress["processed_bytes"] = processed
		progress["total_bytes"] = total
		return progress
	return {"raw": value, "status": -1, "status_name": "Unknown", "processed_bytes": 0, "total_bytes": 0}


func _format_update_progress_status(item_id: String, progress: Dictionary) -> String:
	var status_name := str(progress.get("status_name", "Processing"))
	var processed := int(progress.get("processed_bytes", 0))
	var total := int(progress.get("total_bytes", 0))
	if total > 0:
		return "Steam Workshop upload for item %s: %s %s / %s. Keep the game open until Steam reports completed." % [item_id, status_name, _bytes_text(processed), _bytes_text(total)]
	return "Steam Workshop upload for item %s: %s. Keep the game open until Steam reports completed." % [item_id, status_name]


func _ugc_update_status_name(status: int) -> String:
	match status:
		0:
			return "Invalid"
		1:
			return "Preparing Config"
		2:
			return "Preparing Content"
		3:
			return "Uploading Content"
		4:
			return "Uploading Preview"
		5:
			return "Committing Changes"
		_:
			return "Processing"


func _bytes_text(value: int) -> String:
	if value >= 1024 * 1024:
		return "%.1f MB" % (float(value) / float(1024 * 1024))
	if value >= 1024:
		return "%.1f KB" % (float(value) / 1024.0)
	return "%d B" % value


func _workshop_tags(value: Variant) -> Array[String]:
	var tags: Array[String] = []
	if value is Array:
		for tag_variant in value:
			var tag := str(tag_variant).strip_edges()
			if not tag.is_empty() and not tags.has(tag):
				tags.append(tag)
	elif not str(value).strip_edges().is_empty():
		for part in str(value).split(",", false):
			var tag := part.strip_edges()
			if not tag.is_empty() and not tags.has(tag):
				tags.append(tag)
	for required_tag in ["EMS", "EMS Creator"]:
		if not tags.has(required_tag):
			tags.append(required_tag)
	return tags


func _packed_workshop_tags(value: Variant) -> PackedStringArray:
	var packed := PackedStringArray()
	for tag in _workshop_tags(value):
		packed.append(tag)
	return packed


func _visibility_value(value: String) -> int:
	var normalized := value.strip_edges().to_lower()
	if VISIBILITY_VALUES.has(normalized):
		return int(VISIBILITY_VALUES[normalized])
	return int(VISIBILITY_VALUES["private"])


func _steam_result_name(result_code: int) -> String:
	match result_code:
		0:
			return "No Result"
		1:
			return "OK"
		2:
			return "Fail"
		3:
			return "No Connection"
		5:
			return "Invalid Password"
		8:
			return "Invalid Parameter"
		9:
			return "File Not Found"
		10:
			return "Busy"
		15:
			return "Access Denied"
		16:
			return "Timeout"
		20:
			return "Service Unavailable"
		25:
			return "Limit Exceeded"
		33:
			return "Content Version"
		50:
			return "Item Deleted"
		_:
			return "Steam Result %d" % result_code


func _validation_has_video(validation: Dictionary) -> bool:
	var metrics: Dictionary = validation.get("metrics", {}) as Dictionary
	if int(metrics.get("video_files", 0)) > 0:
		return true
	var warnings: Array = validation.get("warnings", []) as Array
	for warning in warnings:
		if str(warning).to_lower().contains("video"):
			return true
	return false


func _connect_steam_signals(steam: Object) -> void:
	if _steam_signals_connected or steam == null:
		return
	for signal_name in ["item_created", "itemCreated", "create_item_result", "createItemResult"]:
		if steam.has_signal(signal_name):
			var callback := Callable(self, "_on_workshop_item_created")
			if not steam.is_connected(signal_name, callback):
				steam.connect(signal_name, callback)
			_steam_signals_connected = true
	for signal_name in ["item_updated", "itemUpdated", "item_update_result", "submit_item_update_result", "submitItemUpdateResult"]:
		if steam.has_signal(signal_name):
			var callback := Callable(self, "_on_workshop_item_updated")
			if not steam.is_connected(signal_name, callback):
				steam.connect(signal_name, callback)


func _connect_playtime_signals(steam: Object) -> void:
	if _playtime_signals_connected or steam == null:
		return
	if steam.has_signal("start_playtime_tracking"):
		var callback := Callable(self, "_on_start_playtime_tracking")
		if not steam.is_connected("start_playtime_tracking", callback):
			steam.connect("start_playtime_tracking", callback)
	if steam.has_signal("stop_playtime_tracking"):
		var callback := Callable(self, "_on_stop_playtime_tracking")
		if not steam.is_connected("stop_playtime_tracking", callback):
			steam.connect("stop_playtime_tracking", callback)
	_playtime_signals_connected = true


func _extract_item_id(values: Array) -> String:
	for value in values:
		if value is Dictionary:
			var payload := value as Dictionary
			for key in ["published_file_id", "publishedFileID", "published_file_id_or_error", "publishedfileid", "file_id", "item_id", "ugc_file_id"]:
				var text := str(payload.get(key, "")).strip_edges()
				if text.is_valid_int() and text.length() >= 8:
					return text
		var text := str(value).strip_edges()
		if text.is_empty() or text == "0":
			continue
		if text.is_valid_int() and text.length() >= 8:
			return text
	return ""


func _extract_result_code(values: Array) -> int:
	for value in values:
		if value is Dictionary:
			var payload := value as Dictionary
			for key in ["result", "result_code", "eresult", "status"]:
				var text := str(payload.get(key, "")).strip_edges()
				if text.is_valid_int():
					var numeric := int(text)
					if numeric >= 0 and numeric <= 100:
						return numeric
		var text := str(value).strip_edges()
		if text.is_valid_int():
			var numeric := int(text)
			if numeric >= 0 and numeric <= 100:
				return numeric
	return 0


func _extract_needs_legal_agreement(values: Array) -> bool:
	for value in values:
		if value is Dictionary:
			var payload := value as Dictionary
			for key in ["needs_legal_agreement", "needsLegalAgreement", "accept_legal_agreement", "legal_agreement_required"]:
				if payload.has(key):
					return bool(payload.get(key))
		elif value is bool and bool(value):
			return true
	return false


func _app_state() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null("AppState")


func _steam_client() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null("SteamClient")
