extends RefCounted
class_name WorkshopSubscriptionSync

const EMSPackLoader := preload("res://systems/ems/EMSPackLoader.gd")
const EMSValidator := preload("res://systems/ems/EMSValidator.gd")
const HarmonicProjectPackage := preload("res://scripts/editor/HarmonicProjectPackage.gd")
const AudioResolver := preload("res://scripts/songs/AudioResolver.gd")
const SongResolver := preload("res://scripts/songs/SongResolver.gd")
const YouTubeAudioImporter := preload("res://scripts/editor/YouTubeAudioImporter.gd")
const WorkshopChartAudioLink := preload("res://scripts/workshop/WorkshopChartAudioLink.gd")

const CHART_AUDIO_EXTENSIONS := ["ogg", "wav", "mp3", "opus", "m4a", "webm", "aac", "mp4", "mov"]
const CHART_PACKAGE_EXTENSIONS := ["harmonic", "zip"]
const DEFAULT_DOWNLOAD_RETRY_ATTEMPTS := 20
const DEFAULT_DOWNLOAD_RETRY_INTERVAL_SEC := 1.0
const MAX_PAYLOAD_SEARCH_DEPTH := 2


static func _empty_refresh_result(ok: bool, message: String, steam_unavailable: bool = false, retryable: bool = true) -> Dictionary:
	return {
		"ok": ok,
		"message": message,
		"ems": [],
		"charts": [],
		"downloads_requested": [],
		"pending_downloads": [],
		"has_pending_downloads": false,
		"removed_charts": [],
		"remove_failures": [],
		"removed_ems": [],
		"ems_remove_failures": [],
		"skipped": [],
		"steam_unavailable": steam_unavailable,
		"retryable": retryable,
	}


static func refresh_all(request_downloads: bool = true, download_chart_audio: bool = true) -> Dictionary:
	EMSPackLoader.ensure_user_dirs()
	SongResolver.ensure_user_song_dirs()
	var steam := _steam_singleton()
	if steam == null:
		return _empty_refresh_result(false, "Steam singleton is unavailable.", true, false)
	var steam_client := _steam_client()
	if steam_client == null or not steam_client.has_method("is_ready") or not bool(steam_client.call("is_ready")):
		return _empty_refresh_result(false, "Steamworks is not initialized.", true, false)

	var subscription_result := _subscribed_item_ids_result(steam)
	if not bool(subscription_result.get("ok", false)):
		return _empty_refresh_result(false, str(subscription_result.get("message", "Steam Workshop subscription API is unavailable.")), true, false)
	var item_ids: Array[String] = []
	for item in (subscription_result.get("item_ids", []) as Array):
		item_ids.append(str(item))
	var stale_chart_cleanup := prune_unsubscribed_chart_items(item_ids)
	var stale_ems_cleanup := prune_unsubscribed_ems_items(item_ids)
	var ems_items: Array[Dictionary] = []
	var chart_items: Array[Dictionary] = []
	var downloads_requested: Array[Dictionary] = []
	var pending_downloads: Array[Dictionary] = []
	var skipped: Array[Dictionary] = []
	for item_id in item_ids:
		var folder := _installed_folder_for_item(steam, item_id)
		if folder.is_empty():
			if request_downloads:
				var download_result := _request_item_download(steam, item_id)
				downloads_requested.append(download_result)
				pending_downloads.append(_pending_download_entry(item_id, "Workshop item is not installed yet.", download_result))
			else:
				skipped.append({"item_id": item_id, "reason": "Workshop item is not installed yet."})
			continue
		var synced := sync_installed_item(item_id, folder, download_chart_audio)
		if str(synced.get("type", "")) == "ems" and bool(synced.get("ok", false)):
			ems_items.append(synced)
		elif str(synced.get("type", "")) == "chart" and bool(synced.get("ok", false)):
			chart_items.append(synced)
		else:
			if request_downloads and _should_retry_failed_sync(synced):
				var retry_download_result := _request_item_download(steam, item_id)
				downloads_requested.append(retry_download_result)
				pending_downloads.append(_pending_download_entry(item_id, str(synced.get("message", "Workshop item folder is incomplete.")), retry_download_result, folder))
				synced["pending_download"] = true
			else:
				synced["pending_download"] = false
			skipped.append(synced)
	return {
		"ok": true,
		"message": "Steam Workshop subscriptions refreshed.",
		"ems": ems_items,
		"charts": chart_items,
		"downloads_requested": downloads_requested,
		"pending_downloads": pending_downloads,
		"has_pending_downloads": not pending_downloads.is_empty(),
		"removed_charts": stale_chart_cleanup.get("removed", []),
		"remove_failures": stale_chart_cleanup.get("failed", []),
		"removed_ems": stale_ems_cleanup.get("removed", []),
		"ems_remove_failures": stale_ems_cleanup.get("failed", []),
		"skipped": skipped,
	}


static func refresh_all_interactive(request_downloads: bool = true, status_callback: Callable = Callable(), download_chart_audio: bool = true) -> Dictionary:
	EMSPackLoader.ensure_user_dirs()
	SongResolver.ensure_user_song_dirs()
	await _emit_status_frame(status_callback, "fetch_subscriptions", "Fetching subscribed Workshop items", "Checking Steam for subscribed charts and EMS packs.")
	var steam := _steam_singleton()
	if steam == null:
		return _empty_refresh_result(false, "Steam singleton is unavailable.", true, false)
	var steam_client := _steam_client()
	if steam_client == null or not steam_client.has_method("is_ready") or not bool(steam_client.call("is_ready")):
		return _empty_refresh_result(false, "Steamworks is not initialized.", true, false)

	var subscription_result := _subscribed_item_ids_result(steam)
	if not bool(subscription_result.get("ok", false)):
		return _empty_refresh_result(false, str(subscription_result.get("message", "Steam Workshop subscription API is unavailable.")), true, false)
	var item_ids: Array[String] = []
	for item in (subscription_result.get("item_ids", []) as Array):
		item_ids.append(str(item))
	await _emit_status_frame(status_callback, "check_subscriptions", "Checking subscribed Workshop items", "Found %d subscribed Workshop item%s." % [item_ids.size(), "" if item_ids.size() == 1 else "s"])
	var stale_chart_cleanup := prune_unsubscribed_chart_items(item_ids)
	var stale_ems_cleanup := prune_unsubscribed_ems_items(item_ids)
	var ems_items: Array[Dictionary] = []
	var chart_items: Array[Dictionary] = []
	var downloads_requested: Array[Dictionary] = []
	var pending_downloads: Array[Dictionary] = []
	var skipped: Array[Dictionary] = []
	for item_id in item_ids:
		await _emit_status_frame(status_callback, "check_item", "Checking Workshop item", "Validating item %s." % item_id)
		var folder := _installed_folder_for_item(steam, item_id)
		if folder.is_empty():
			if request_downloads:
				await _emit_status_frame(status_callback, "request_download", "Requesting Workshop download", "Steam has not installed item %s yet. Requesting it now." % item_id)
				var download_result := _request_item_download(steam, item_id)
				downloads_requested.append(download_result)
				pending_downloads.append(_pending_download_entry(item_id, "Workshop item is not installed yet.", download_result))
			else:
				skipped.append({"item_id": item_id, "reason": "Workshop item is not installed yet."})
			continue
		var synced: Dictionary = await sync_installed_item_interactive(item_id, folder, download_chart_audio, status_callback)
		if str(synced.get("type", "")) == "ems" and bool(synced.get("ok", false)):
			ems_items.append(synced)
		elif str(synced.get("type", "")) == "chart" and bool(synced.get("ok", false)):
			chart_items.append(synced)
		else:
			if request_downloads and _should_retry_failed_sync(synced):
				await _emit_status_frame(status_callback, "repair_download", "Repairing Workshop download", "Item %s has an incomplete local folder. Requesting Steam to download it again." % item_id)
				var retry_download_result := _request_item_download(steam, item_id)
				downloads_requested.append(retry_download_result)
				pending_downloads.append(_pending_download_entry(item_id, str(synced.get("message", "Workshop item folder is incomplete.")), retry_download_result, folder))
				synced["pending_download"] = true
			else:
				await _emit_status_frame(status_callback, "item_not_recognized", "Workshop item needs attention", "Item %s is installed, but its files are not a recognizable chart or EMS pack." % item_id)
				synced["pending_download"] = false
			skipped.append(synced)
	return {
		"ok": true,
		"message": "Steam Workshop subscriptions refreshed.",
		"ems": ems_items,
		"charts": chart_items,
		"downloads_requested": downloads_requested,
		"pending_downloads": pending_downloads,
		"has_pending_downloads": not pending_downloads.is_empty(),
		"removed_charts": stale_chart_cleanup.get("removed", []),
		"remove_failures": stale_chart_cleanup.get("failed", []),
		"removed_ems": stale_ems_cleanup.get("removed", []),
		"ems_remove_failures": stale_ems_cleanup.get("failed", []),
		"skipped": skipped,
	}


static func refresh_all_until_stable_interactive(
	request_downloads: bool = true,
	status_callback: Callable = Callable(),
	download_chart_audio: bool = true,
	max_attempts: int = DEFAULT_DOWNLOAD_RETRY_ATTEMPTS,
	retry_interval_sec: float = DEFAULT_DOWNLOAD_RETRY_INTERVAL_SEC
) -> Dictionary:
	var attempts := maxi(1, max_attempts)
	var last_result: Dictionary = {}
	for attempt in range(1, attempts + 1):
		await _emit_status_frame(status_callback, "sync_attempt", "Checking Workshop subscriptions", "Workshop sync attempt %d of %d." % [attempt, attempts])
		last_result = await refresh_all_interactive(request_downloads, status_callback, download_chart_audio)
		last_result["attempts"] = attempt
		if bool(last_result.get("ok", false)) and not bool(last_result.get("has_pending_downloads", false)):
			last_result["stabilized"] = true
			return last_result
		if not bool(last_result.get("ok", false)) and not bool(last_result.get("retryable", true)):
			last_result["stabilized"] = false
			await _emit_status_frame(status_callback, "workshop_unavailable", "Steam Workshop unavailable", str(last_result.get("message", "Steam Workshop sync is unavailable.")))
			return last_result
		if attempt >= attempts:
			break
		var pending_downloads: Array = last_result.get("pending_downloads", []) as Array
		var detail := str(last_result.get("message", "Waiting for Steam Workshop."))
		if not pending_downloads.is_empty():
			detail = "Waiting for Steam to finish %d Workshop download%s. Re-checking shortly." % [pending_downloads.size(), "" if pending_downloads.size() == 1 else "s"]
		await _emit_status_frame(status_callback, "wait_pending_downloads", "Waiting for Workshop downloads", detail)
		await _sleep_seconds(retry_interval_sec)
	last_result["attempts"] = attempts
	last_result["stabilized"] = false
	if bool(last_result.get("has_pending_downloads", false)):
		var pending: Array = last_result.get("pending_downloads", []) as Array
		last_result["message"] = "Steam Workshop still has %d pending download%s." % [pending.size(), "" if pending.size() == 1 else "s"]
	return last_result


static func sync_installed_item(item_id: String, source_folder: String, download_chart_audio: bool = true) -> Dictionary:
	var normalized_item_id := _safe_item_id(item_id)
	if normalized_item_id.is_empty():
		return {"ok": false, "type": "", "item_id": item_id, "source_folder": source_folder, "message": "Workshop item id is invalid.", "retryable_download": false}
	if not DirAccess.dir_exists_absolute(_globalize_if_needed(source_folder)):
		return {"ok": false, "type": "", "item_id": normalized_item_id, "source_folder": source_folder, "message": "Workshop item folder does not exist.", "source_has_files": false, "retryable_download": true}

	var payload := _resolve_item_payload(source_folder)
	var payload_folder := str(payload.get("folder", source_folder))
	if bool(payload.get("ok", false)) and str(payload.get("type", "")) == "ems":
		var ems_copied := EMSPackLoader.copy_validated_pack_to_root(payload_folder, EMSPackLoader.WORKSHOP_ROOT, normalized_item_id)
		return {
			"ok": bool(ems_copied.get("ok", false)),
			"type": "ems",
			"item_id": normalized_item_id,
			"source_folder": source_folder,
			"payload_folder": payload_folder,
			"path": str(ems_copied.get("path", "")),
			"message": str(ems_copied.get("message", "")),
			"validation": ems_copied.get("validation", {}),
			"retryable_download": false,
		}

	if bool(payload.get("ok", false)) and str(payload.get("type", "")) == "chart":
		var chart_result := _sync_chart_item(normalized_item_id, payload_folder, download_chart_audio)
		chart_result["steam_source_folder"] = source_folder
		chart_result["payload_folder"] = payload_folder
		chart_result["retryable_download"] = false
		return chart_result

	return _invalid_payload_result(normalized_item_id, source_folder, payload)


static func sync_installed_item_interactive(item_id: String, source_folder: String, download_chart_audio: bool = true, status_callback: Callable = Callable()) -> Dictionary:
	var normalized_item_id := _safe_item_id(item_id)
	if normalized_item_id.is_empty():
		return {"ok": false, "type": "", "item_id": item_id, "source_folder": source_folder, "message": "Workshop item id is invalid.", "retryable_download": false}
	if not DirAccess.dir_exists_absolute(_globalize_if_needed(source_folder)):
		return {"ok": false, "type": "", "item_id": normalized_item_id, "source_folder": source_folder, "message": "Workshop item folder does not exist.", "source_has_files": false, "retryable_download": true}

	await _emit_status_frame(status_callback, "validate_item", "Validating Workshop item", "Checking whether item %s is an EMS pack or chart." % normalized_item_id)
	var payload := _resolve_item_payload(source_folder)
	var payload_folder := str(payload.get("folder", source_folder))
	if bool(payload.get("ok", false)) and str(payload.get("type", "")) == "ems":
		await _emit_status_frame(status_callback, "install_ems", "Installing EMS pack", "Copying subscribed EMS pack %s." % normalized_item_id)
		var ems_copied := EMSPackLoader.copy_validated_pack_to_root(payload_folder, EMSPackLoader.WORKSHOP_ROOT, normalized_item_id)
		return {
			"ok": bool(ems_copied.get("ok", false)),
			"type": "ems",
			"item_id": normalized_item_id,
			"source_folder": source_folder,
			"payload_folder": payload_folder,
			"path": str(ems_copied.get("path", "")),
			"message": str(ems_copied.get("message", "")),
			"validation": ems_copied.get("validation", {}),
			"retryable_download": false,
		}

	if bool(payload.get("ok", false)) and str(payload.get("type", "")) == "chart":
		var chart_result: Dictionary = await _sync_chart_item_interactive(normalized_item_id, payload_folder, download_chart_audio, status_callback)
		chart_result["steam_source_folder"] = source_folder
		chart_result["payload_folder"] = payload_folder
		chart_result["retryable_download"] = false
		return chart_result

	return _invalid_payload_result(normalized_item_id, source_folder, payload)


static func prune_unsubscribed_chart_items(subscribed_item_ids: Array, managed_root: String = "") -> Dictionary:
	SongResolver.ensure_user_song_dirs()
	var root := managed_root.strip_edges()
	if root.is_empty():
		root = SongResolver.WORKSHOP_ROOT
	var subscribed_lookup := {}
	for raw_item_id in subscribed_item_ids:
		var normalized := _safe_item_id(str(raw_item_id))
		if not normalized.is_empty():
			subscribed_lookup[normalized] = true

	var removed: Array[Dictionary] = []
	var failed: Array[Dictionary] = []
	var skipped: Array[Dictionary] = []
	var dir := DirAccess.open(root)
	if dir == null:
		return {"ok": true, "removed": removed, "failed": failed, "skipped": skipped}

	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name.is_empty():
			break
		if name == "." or name == ".." or not dir.current_is_dir():
			continue
		var item_id := _safe_item_id(name)
		if item_id.is_empty():
			skipped.append({"item_id": name, "reason": "Not a managed Workshop item folder."})
			continue
		if subscribed_lookup.has(item_id):
			skipped.append({"item_id": item_id, "reason": "Still subscribed."})
			continue
		var removal := remove_chart_item(item_id, root)
		if bool(removal.get("ok", false)):
			removed.append(removal)
		else:
			failed.append(removal)
	dir.list_dir_end()
	return {"ok": failed.is_empty(), "removed": removed, "failed": failed, "skipped": skipped}


static func prune_unsubscribed_ems_items(subscribed_item_ids: Array, managed_root: String = "") -> Dictionary:
	EMSPackLoader.ensure_user_dirs()
	var root := managed_root.strip_edges()
	if root.is_empty():
		root = EMSPackLoader.WORKSHOP_ROOT
	var subscribed_lookup := {}
	for raw_item_id in subscribed_item_ids:
		var normalized := _safe_item_id(str(raw_item_id))
		if not normalized.is_empty():
			subscribed_lookup[normalized] = true

	var removed: Array[Dictionary] = []
	var failed: Array[Dictionary] = []
	var skipped: Array[Dictionary] = []
	var dir := DirAccess.open(root)
	if dir == null:
		return {"ok": true, "removed": removed, "failed": failed, "skipped": skipped}

	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name.is_empty():
			break
		if name == "." or name == ".." or not dir.current_is_dir():
			continue
		var item_id := _safe_item_id(name)
		if item_id.is_empty():
			skipped.append({"item_id": name, "reason": "Not a managed Workshop item folder."})
			continue
		if subscribed_lookup.has(item_id):
			skipped.append({"item_id": item_id, "reason": "Still subscribed."})
			continue
		var folder := root.path_join(item_id)
		var clear_result := _clear_managed_folder(folder, root)
		var result := {
			"ok": bool(clear_result.get("ok", false)),
			"type": "ems",
			"item_id": item_id,
			"path": folder,
			"removed": bool(clear_result.get("ok", false)),
			"message": str(clear_result.get("message", "")),
		}
		if bool(result.get("ok", false)):
			removed.append(result)
		else:
			failed.append(result)
	dir.list_dir_end()
	return {"ok": failed.is_empty(), "removed": removed, "failed": failed, "skipped": skipped}


static func remove_chart_item(item_id: String, managed_root: String = "") -> Dictionary:
	var normalized_item_id := _safe_item_id(item_id)
	if normalized_item_id.is_empty():
		return {"ok": false, "type": "chart", "item_id": item_id, "path": "", "removed": false, "message": "Workshop item id is invalid."}
	var root := managed_root.strip_edges()
	if root.is_empty():
		root = SongResolver.WORKSHOP_ROOT
	var target_folder := root.path_join(normalized_item_id)
	var existed := DirAccess.dir_exists_absolute(_globalize_if_needed(target_folder))
	var clear_result := _clear_managed_folder(target_folder, root)
	return {
		"ok": bool(clear_result.get("ok", false)),
		"type": "chart",
		"item_id": normalized_item_id,
		"path": target_folder,
		"removed": existed and bool(clear_result.get("ok", false)),
		"message": str(clear_result.get("message", "")),
	}


static func _resolve_item_payload(source_folder: String) -> Dictionary:
	var candidates := _candidate_payload_folders(source_folder)
	var first_ems_validation: Dictionary = {}
	var first_chart_validation: Dictionary = {}
	for candidate in candidates:
		var ems_validation := EMSValidator.validate_pack_folder(candidate)
		if first_ems_validation.is_empty():
			first_ems_validation = ems_validation
		if bool(ems_validation.get("ok", false)):
			return {
				"ok": true,
				"type": "ems",
				"folder": candidate,
				"candidate_folders": candidates,
				"ems_validation": ems_validation,
				"chart_validation": {},
				"source_has_files": true,
			}

		var chart_validation := HarmonicProjectPackage.validate_project_folder(candidate)
		if first_chart_validation.is_empty():
			first_chart_validation = chart_validation
		if bool(chart_validation.get("ok", false)):
			return {
				"ok": true,
				"type": "chart",
				"folder": candidate,
				"candidate_folders": candidates,
				"ems_validation": ems_validation,
				"chart_validation": chart_validation,
				"source_has_files": true,
			}

	var source_has_files := _folder_has_any_file(source_folder)
	return {
		"ok": false,
		"type": "",
		"folder": source_folder,
		"candidate_folders": candidates,
		"ems_validation": first_ems_validation,
		"chart_validation": first_chart_validation,
		"source_has_files": source_has_files,
		"retryable_download": not source_has_files,
	}


static func _invalid_payload_result(item_id: String, source_folder: String, payload: Dictionary) -> Dictionary:
	var source_has_files := bool(payload.get("source_has_files", _folder_has_any_file(source_folder)))
	return {
		"ok": false,
		"type": "",
		"item_id": item_id,
		"source_folder": source_folder,
		"payload_folder": str(payload.get("folder", source_folder)),
		"message": "Workshop item is not a valid EMS pack or Harmonic chart pack.",
		"ems_validation": payload.get("ems_validation", {}),
		"chart_validation": payload.get("chart_validation", {}),
		"candidate_folders": payload.get("candidate_folders", []),
		"source_has_files": source_has_files,
		"retryable_download": not source_has_files,
	}


static func _candidate_payload_folders(source_folder: String) -> Array[String]:
	var out: Array[String] = []
	var seen := {}
	_append_payload_candidate(source_folder, out, seen)
	_collect_payload_candidate_folders(source_folder, 0, out, seen)
	return out


static func _collect_payload_candidate_folders(folder: String, depth: int, out: Array[String], seen: Dictionary) -> void:
	if depth >= MAX_PAYLOAD_SEARCH_DEPTH:
		return
	var dir := DirAccess.open(_globalize_if_needed(folder))
	if dir == null:
		return
	var child_dirs: Array[String] = []
	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name.is_empty():
			break
		if not dir.current_is_dir() or _is_ignored_payload_name(name) or String(name).begins_with("."):
			continue
		child_dirs.append(name)
	dir.list_dir_end()
	child_dirs.sort()
	for name in child_dirs:
		var child := folder.path_join(name)
		_append_payload_candidate(child, out, seen)
		_collect_payload_candidate_folders(child, depth + 1, out, seen)


static func _append_payload_candidate(folder: String, out: Array[String], seen: Dictionary) -> void:
	var candidate := folder.strip_edges().rstrip("/")
	if candidate.is_empty():
		return
	var absolute := _globalize_if_needed(candidate).rstrip("/")
	if seen.has(absolute) or not DirAccess.dir_exists_absolute(absolute):
		return
	seen[absolute] = true
	out.append(candidate)


static func _folder_has_any_file(folder: String, max_depth: int = MAX_PAYLOAD_SEARCH_DEPTH + 1) -> bool:
	var dir := DirAccess.open(_globalize_if_needed(folder))
	if dir == null:
		return false
	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name.is_empty():
			break
		if _is_ignored_payload_name(name):
			continue
		var is_dir := dir.current_is_dir()
		if not is_dir:
			dir.list_dir_end()
			return true
		if not String(name).begins_with(".") and max_depth > 0 and _folder_has_any_file(folder.path_join(name), max_depth - 1):
			dir.list_dir_end()
			return true
	dir.list_dir_end()
	return false


static func _is_ignored_payload_name(name: String) -> bool:
	var lower := name.to_lower()
	return name == "." or name == ".." or lower == ".ds_store" or lower == "thumbs.db" or lower == "__macosx"


static func _should_retry_failed_sync(sync_result: Dictionary) -> bool:
	return bool(sync_result.get("retryable_download", false))


static func _sync_chart_item(item_id: String, source_folder: String, download_chart_audio: bool) -> Dictionary:
	var target_folder := SongResolver.WORKSHOP_ROOT.path_join(_safe_item_id(item_id))
	var validation := HarmonicProjectPackage.validate_project_folder(source_folder)
	if not bool(validation.get("ok", false)):
		return {"ok": false, "type": "chart", "item_id": item_id, "source_folder": source_folder, "path": target_folder, "message": str(validation.get("error", "Workshop chart source is invalid.")), "validation": validation}
	if _cached_chart_matches_source(source_folder, target_folder):
		return _finalize_chart_item(item_id, source_folder, target_folder, download_chart_audio)
	if _same_global_path(source_folder, target_folder):
		return _finalize_chart_item(item_id, source_folder, target_folder, download_chart_audio)

	var staging_folder := SongResolver.WORKSHOP_ROOT.path_join(".sync_%s_%d" % [_safe_item_id(item_id), Time.get_ticks_msec()])
	var clear_staging := _clear_managed_folder(staging_folder, SongResolver.WORKSHOP_ROOT)
	if not bool(clear_staging.get("ok", false)):
		return {"ok": false, "type": "chart", "item_id": item_id, "source_folder": source_folder, "path": target_folder, "message": str(clear_staging.get("message", "Could not prepare Workshop staging folder."))}
	var copied := HarmonicProjectPackage.export_project_to_folder(source_folder, staging_folder)
	if not bool(copied.get("ok", false)):
		_clear_managed_folder(staging_folder, SongResolver.WORKSHOP_ROOT)
		return {"ok": false, "type": "chart", "item_id": item_id, "source_folder": source_folder, "path": target_folder, "message": str(copied.get("error", "Could not copy chart pack."))}
	_preserve_existing_chart_audio(target_folder, staging_folder)
	var finalized := _finalize_chart_item(item_id, source_folder, staging_folder, download_chart_audio)
	var replace_result := _replace_managed_folder(staging_folder, target_folder, SongResolver.WORKSHOP_ROOT)
	if not bool(replace_result.get("ok", false)):
		_clear_managed_folder(staging_folder, SongResolver.WORKSHOP_ROOT)
		return {"ok": false, "type": "chart", "item_id": item_id, "source_folder": source_folder, "path": target_folder, "message": str(replace_result.get("message", "Could not install Workshop chart pack."))}
	finalized["path"] = target_folder
	return finalized


static func _sync_chart_item_interactive(item_id: String, source_folder: String, download_chart_audio: bool, status_callback: Callable) -> Dictionary:
	var target_folder := SongResolver.WORKSHOP_ROOT.path_join(_safe_item_id(item_id))
	await _emit_status_frame(status_callback, "validate_chart", "Validating chart data", "Checking Workshop chart files for item %s." % item_id)
	var validation := HarmonicProjectPackage.validate_project_folder(source_folder)
	if not bool(validation.get("ok", false)):
		return {"ok": false, "type": "chart", "item_id": item_id, "source_folder": source_folder, "path": target_folder, "message": str(validation.get("error", "Workshop chart source is invalid.")), "validation": validation}
	await _emit_status_frame(status_callback, "check_cached_chart", "Checking cached chart", "Validating existing chart files and generated audio.")
	if _cached_chart_matches_source(source_folder, target_folder):
		return await _finalize_chart_item_interactive(item_id, source_folder, target_folder, download_chart_audio, status_callback)
	if _same_global_path(source_folder, target_folder):
		return await _finalize_chart_item_interactive(item_id, source_folder, target_folder, download_chart_audio, status_callback)

	await _emit_status_frame(status_callback, "install_chart", "Installing Workshop chart", "Copying chart data into the local Community Charts cache.")
	var staging_folder := SongResolver.WORKSHOP_ROOT.path_join(".sync_%s_%d" % [_safe_item_id(item_id), Time.get_ticks_msec()])
	var clear_staging := _clear_managed_folder(staging_folder, SongResolver.WORKSHOP_ROOT)
	if not bool(clear_staging.get("ok", false)):
		return {"ok": false, "type": "chart", "item_id": item_id, "source_folder": source_folder, "path": target_folder, "message": str(clear_staging.get("message", "Could not prepare Workshop staging folder."))}
	var copied := HarmonicProjectPackage.export_project_to_folder(source_folder, staging_folder)
	if not bool(copied.get("ok", false)):
		_clear_managed_folder(staging_folder, SongResolver.WORKSHOP_ROOT)
		return {"ok": false, "type": "chart", "item_id": item_id, "source_folder": source_folder, "path": target_folder, "message": str(copied.get("error", "Could not copy chart pack."))}
	if _preserve_existing_chart_audio(target_folder, staging_folder):
		await _emit_status_frame(status_callback, "preserve_audio", "Using existing audio", "Preserved the already converted song.ogg for this chart.")
	var finalized: Dictionary = await _finalize_chart_item_interactive(item_id, source_folder, staging_folder, download_chart_audio, status_callback)
	var replace_result := _replace_managed_folder(staging_folder, target_folder, SongResolver.WORKSHOP_ROOT)
	if not bool(replace_result.get("ok", false)):
		_clear_managed_folder(staging_folder, SongResolver.WORKSHOP_ROOT)
		return {"ok": false, "type": "chart", "item_id": item_id, "source_folder": source_folder, "path": target_folder, "message": str(replace_result.get("message", "Could not install Workshop chart pack."))}
	finalized["path"] = target_folder
	return finalized


static func _finalize_chart_item(item_id: String, source_folder: String, target_folder: String, download_chart_audio: bool) -> Dictionary:
	var manifest := HarmonicProjectPackage.read_manifest(target_folder)
	var youtube_url := str(manifest.get("youtube_url", "")).strip_edges()
	var audio_status := "not_requested"
	var link_result := WorkshopChartAudioLink.apply_saved_link(item_id, target_folder)
	if bool(link_result.get("applied", false)):
		manifest = HarmonicProjectPackage.read_manifest(target_folder)
		audio_status = "linked"
	elif not bool(link_result.get("ok", true)):
		audio_status = "linked_audio_missing: %s" % str(link_result.get("error", "unknown error"))
	var existing_audio := _valid_chart_audio_path(target_folder, manifest)
	if not existing_audio.is_empty():
		if str(manifest.get("audio_path", "")).strip_edges().is_empty():
			HarmonicProjectPackage.set_manifest_audio_path(target_folder, _audio_reference_for_manifest(target_folder, existing_audio))
		if audio_status == "not_requested":
			audio_status = "cached"
	elif download_chart_audio and YouTubeAudioImporter.is_supported_url(youtube_url):
		var audio_result := YouTubeAudioImporter.import_url_to_project(youtube_url, target_folder)
		if bool(audio_result.get("ok", false)):
			HarmonicProjectPackage.set_manifest_audio_path(target_folder, str(audio_result.get("path", "")).get_file())
			HarmonicProjectPackage.set_manifest_youtube_url(target_folder, youtube_url)
			audio_status = "downloaded"
		else:
			audio_status = "failed: %s" % str(audio_result.get("error", "unknown error"))
	return {
		"ok": true,
		"type": "chart",
		"item_id": item_id,
		"source_folder": source_folder,
		"path": target_folder,
		"message": "Synced Workshop chart pack.",
		"youtube_url": youtube_url,
		"audio_status": audio_status,
	}


static func _finalize_chart_item_interactive(item_id: String, source_folder: String, target_folder: String, download_chart_audio: bool, status_callback: Callable) -> Dictionary:
	var manifest := HarmonicProjectPackage.read_manifest(target_folder)
	var youtube_url := str(manifest.get("youtube_url", "")).strip_edges()
	var audio_status := "not_requested"
	await _emit_status_frame(status_callback, "check_audio", "Checking chart audio", "Validating existing audio before downloading anything.")
	var link_result := WorkshopChartAudioLink.apply_saved_link(item_id, target_folder)
	if bool(link_result.get("applied", false)):
		manifest = HarmonicProjectPackage.read_manifest(target_folder)
		audio_status = "linked"
	elif not bool(link_result.get("ok", true)):
		audio_status = "linked_audio_missing: %s" % str(link_result.get("error", "unknown error"))
	var existing_audio := _valid_chart_audio_path(target_folder, manifest)
	if not existing_audio.is_empty():
		if str(manifest.get("audio_path", "")).strip_edges().is_empty():
			HarmonicProjectPackage.set_manifest_audio_path(target_folder, _audio_reference_for_manifest(target_folder, existing_audio))
		if audio_status == "not_requested":
			audio_status = "cached"
		await _emit_status_frame(status_callback, "use_cached_audio", "Using cached chart audio", "Existing playable audio is already present.")
	elif download_chart_audio and YouTubeAudioImporter.is_supported_url(youtube_url):
		var audio_result: Dictionary = await YouTubeAudioImporter.import_url_to_project_interactive(youtube_url, target_folder, status_callback)
		if bool(audio_result.get("ok", false)):
			HarmonicProjectPackage.set_manifest_audio_path(target_folder, str(audio_result.get("path", "")).get_file())
			HarmonicProjectPackage.set_manifest_youtube_url(target_folder, youtube_url)
			audio_status = "downloaded"
		else:
			audio_status = "failed: %s" % str(audio_result.get("error", "unknown error"))
	return {
		"ok": true,
		"type": "chart",
		"item_id": item_id,
		"source_folder": source_folder,
		"path": target_folder,
		"message": "Synced Workshop chart pack.",
		"youtube_url": youtube_url,
		"audio_status": audio_status,
	}


static func _subscribed_item_ids(steam: Object) -> Array[String]:
	var result := _subscribed_item_ids_result(steam)
	var item_ids: Array[String] = []
	for item in (result.get("item_ids", []) as Array):
		item_ids.append(str(item))
	return item_ids


static func _subscribed_item_ids_result(steam: Object) -> Dictionary:
	var item_ids: Array[String] = []
	var count_result := _call_first(steam, ["getNumSubscribedItems", "get_num_subscribed_items"], [])
	if not bool(count_result.get("called", false)):
		return {"ok": false, "item_ids": item_ids, "message": "Steam Workshop subscription count API is unavailable."}
	var count := int(count_result.get("value", 0))
	if count <= 0:
		return {"ok": true, "item_ids": item_ids, "message": ""}
	var items_result := _call_first(steam, ["getSubscribedItems", "get_subscribed_items"], [count])
	if not bool(items_result.get("called", false)):
		return {"ok": false, "item_ids": item_ids, "message": "Steam Workshop subscribed-items API is unavailable."}
	var raw_items: Variant = items_result.get("value", [])
	if raw_items is PackedInt64Array:
		for item in raw_items:
			item_ids.append(str(item))
	elif raw_items is PackedInt32Array:
		for item in raw_items:
			item_ids.append(str(item))
	elif raw_items is Array:
		for item in raw_items:
			item_ids.append(str(item))
	return {"ok": true, "item_ids": item_ids, "message": ""}


static func _installed_folder_for_item(steam: Object, item_id: String) -> String:
	if not item_id.is_valid_int():
		return ""
	var info_result := _call_first(steam, ["getItemInstallInfo", "get_item_install_info"], [int(item_id)])
	if not bool(info_result.get("called", false)):
		return ""
	var value: Variant = info_result.get("value", null)
	if value is Dictionary:
		var info := value as Dictionary
		for key in ["folder", "install_folder", "folder_path", "path"]:
			var folder := str(info.get(key, "")).strip_edges()
			if not folder.is_empty():
				return folder
	if value is Array:
		for item in value as Array:
			var text := str(item).strip_edges()
			if text.contains("/") or text.contains("\\"):
				return text
	return ""


static func _request_item_download(steam: Object, item_id: String) -> Dictionary:
	if not item_id.is_valid_int():
		return {"ok": false, "item_id": item_id, "message": "Workshop item id is invalid."}
	var result := _call_first(steam, ["downloadItem", "download_item"], [int(item_id), true])
	return {
		"ok": bool(result.get("called", false)),
		"item_id": item_id,
		"message": "Steam Workshop item download requested." if bool(result.get("called", false)) else "Steam Workshop download API is unavailable.",
		"api_result": result.get("value", null),
	}


static func _pending_download_entry(item_id: String, reason: String, download_result: Dictionary = {}, source_folder: String = "") -> Dictionary:
	return {
		"item_id": item_id,
		"source_folder": source_folder,
		"reason": reason,
		"download_requested": bool(download_result.get("ok", false)),
		"download_result": download_result,
	}


static func _cached_chart_matches_source(source_folder: String, target_folder: String) -> bool:
	if not DirAccess.dir_exists_absolute(_globalize_if_needed(target_folder)):
		return false
	if not bool(HarmonicProjectPackage.validate_project_folder(target_folder).get("ok", false)):
		return false
	var source_files := _chart_payload_files(source_folder)
	var target_files := _chart_payload_files(target_folder)
	var source_has_preview := source_files.has(HarmonicProjectPackage.PREVIEW_FILE)
	if not source_has_preview:
		target_files.erase(HarmonicProjectPackage.PREVIEW_FILE)
	if source_files != target_files:
		return false
	for relative_path in source_files:
		var source_path := source_folder.path_join(relative_path)
		var target_path := target_folder.path_join(relative_path)
		if relative_path == HarmonicProjectPackage.MANIFEST_FILE:
			if _manifest_compare_text(source_folder) != _manifest_compare_text(target_folder):
				return false
			continue
		var source_bytes := _read_file_bytes(source_path)
		var target_bytes := _read_file_bytes(target_path)
		if source_bytes.size() != target_bytes.size():
			return false
		for i in range(source_bytes.size()):
			if source_bytes[i] != target_bytes[i]:
				return false
	return true


static func _preserve_existing_chart_audio(existing_folder: String, target_folder: String) -> bool:
	if not DirAccess.dir_exists_absolute(_globalize_if_needed(existing_folder)):
		return false
	var existing_manifest := HarmonicProjectPackage.read_manifest(existing_folder)
	var existing_audio := _valid_chart_audio_path(existing_folder, existing_manifest)
	if existing_audio.is_empty():
		return false
	var relative_audio := _relative_path_inside(existing_folder, existing_audio)
	if relative_audio.is_empty():
		return false
	var target_audio := target_folder.path_join(relative_audio)
	if _write_file_bytes(target_audio, _read_file_bytes(existing_audio)):
		return true
	return false


static func _valid_chart_audio_path(chart_folder: String, manifest: Dictionary) -> String:
	var resolved := AudioResolver.resolve_audio(manifest, chart_folder)
	var resolved_path := str(resolved.get("path", "")).strip_edges()
	if str(resolved.get("status", "")) == "available" and _file_has_bytes(resolved_path):
		return resolved_path
	for basename in ["song", "audio", "music", "track"]:
		for ext in CHART_AUDIO_EXTENSIONS:
			var candidate := chart_folder.path_join("%s.%s" % [basename, ext])
			if _file_has_bytes(candidate):
				return candidate
	var dir := DirAccess.open(chart_folder)
	if dir == null:
		return ""
	var found: Array[String] = []
	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name.is_empty():
			break
		if dir.current_is_dir():
			continue
		var lower := String(name).to_lower()
		if lower.begins_with("."):
			continue
		if CHART_AUDIO_EXTENSIONS.has(lower.get_extension()) and _file_has_bytes(chart_folder.path_join(name)):
			found.append(chart_folder.path_join(name))
	dir.list_dir_end()
	found.sort()
	return found[0] if not found.is_empty() else ""


static func _audio_reference_for_manifest(chart_folder: String, audio_path: String) -> String:
	var relative := _relative_path_inside(chart_folder, audio_path)
	if not relative.is_empty():
		return relative
	return audio_path


static func _chart_payload_files(root: String) -> Array[String]:
	var root_abs := _globalize_if_needed(root)
	var out: Array[String] = []
	_collect_chart_payload_files_recursive(root_abs, "", out)
	out.sort()
	return out


static func _collect_chart_payload_files_recursive(root_abs: String, relative_dir: String, out: Array[String]) -> void:
	var current_abs := root_abs.path_join(relative_dir) if not relative_dir.is_empty() else root_abs
	var dir := DirAccess.open(current_abs)
	if dir == null:
		return
	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name.is_empty():
			break
		if name == "." or name == ".." or String(name).begins_with("."):
			continue
		var relative_path := relative_dir.path_join(name) if not relative_dir.is_empty() else name
		if dir.current_is_dir():
			_collect_chart_payload_files_recursive(root_abs, relative_path, out)
			continue
		if _is_chart_payload_file(relative_path):
			out.append(relative_path)
	dir.list_dir_end()


static func _is_chart_payload_file(relative_path: String) -> bool:
	var lower := relative_path.to_lower()
	if lower.is_empty() or lower.begins_with("."):
		return false
	for segment in lower.split("/"):
		if String(segment).begins_with("."):
			return false
	var filename := lower.get_file()
	if filename == "waveform_preview_cache.wav" or filename == "midi_import_waveform_cache.wav":
		return false
	if CHART_PACKAGE_EXTENSIONS.has(lower.get_extension()):
		return false
	if CHART_AUDIO_EXTENSIONS.has(lower.get_extension()):
		return false
	return true


static func _manifest_compare_text(project_folder: String) -> String:
	var manifest := HarmonicProjectPackage.read_manifest(project_folder)
	var normalized := manifest.duplicate(true)
	normalized.erase("audio_path")
	if not normalized.has("youtube_url"):
		normalized["youtube_url"] = ""
	return JSON.stringify(normalized, "", true)


static func _read_file_bytes(path: String) -> PackedByteArray:
	var file := FileAccess.open(_globalize_if_needed(path), FileAccess.READ)
	if file == null:
		return PackedByteArray()
	var bytes := file.get_buffer(file.get_length())
	file.close()
	return bytes


static func _write_file_bytes(path: String, bytes: PackedByteArray) -> bool:
	if bytes.is_empty():
		return false
	var target_abs := _globalize_if_needed(path)
	var dir_err := DirAccess.make_dir_recursive_absolute(target_abs.get_base_dir())
	if dir_err != OK:
		return false
	var file := FileAccess.open(target_abs, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(bytes)
	file.flush()
	file.close()
	return true


static func _file_has_bytes(path: String) -> bool:
	if path.strip_edges().is_empty():
		return false
	var file := FileAccess.open(_globalize_if_needed(path), FileAccess.READ)
	if file == null:
		return false
	var has_bytes := file.get_length() > 0
	file.close()
	return has_bytes


static func _relative_path_inside(root: String, path: String) -> String:
	var root_clean := root.strip_edges().rstrip("/")
	var path_clean := path.strip_edges()
	if root_clean.is_empty() or path_clean.is_empty():
		return ""
	var root_prefix := root_clean + "/"
	if path_clean.begins_with(root_prefix):
		return path_clean.substr(root_prefix.length())
	var root_abs_prefix := _globalize_if_needed(root_clean).rstrip("/") + "/"
	var path_abs := _globalize_if_needed(path_clean)
	if path_abs.begins_with(root_abs_prefix):
		return path_abs.substr(root_abs_prefix.length())
	return ""


static func _emit_status_frame(status_callback: Callable, phase: String, title: String, detail: String) -> void:
	if status_callback.is_valid():
		status_callback.call({"phase": phase, "title": title, "detail": detail})
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		await tree.process_frame


static func _sleep_seconds(seconds: float) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	await tree.create_timer(maxf(0.05, seconds)).timeout


static func _replace_managed_folder(staging_folder: String, target_folder: String, managed_root: String) -> Dictionary:
	var staging := staging_folder.strip_edges()
	var target := target_folder.strip_edges()
	var root := managed_root.rstrip("/")
	if staging.is_empty() or target.is_empty() or not staging.begins_with(root + "/") or not target.begins_with(root + "/"):
		return {"ok": false, "message": "Refusing to replace unmanaged Workshop folder."}
	if not DirAccess.dir_exists_absolute(_globalize_if_needed(staging)):
		return {"ok": false, "message": "Workshop staging folder is missing: %s" % staging}
	if _same_global_path(staging, target):
		return {"ok": true, "message": "Workshop chart folder is already in place."}

	var backup := root.path_join(".backup_%s_%d" % [target.get_file(), Time.get_ticks_msec()])
	var target_exists := DirAccess.dir_exists_absolute(_globalize_if_needed(target))
	if target_exists:
		var clear_backup := _clear_managed_folder(backup, root)
		if not bool(clear_backup.get("ok", false)):
			return clear_backup
		var backup_err := DirAccess.rename_absolute(_globalize_if_needed(target), _globalize_if_needed(backup))
		if backup_err != OK:
			return {"ok": false, "message": "Could not back up existing Workshop chart folder: %s" % target}

	var install_err := DirAccess.rename_absolute(_globalize_if_needed(staging), _globalize_if_needed(target))
	if install_err != OK:
		if target_exists and DirAccess.dir_exists_absolute(_globalize_if_needed(backup)):
			DirAccess.rename_absolute(_globalize_if_needed(backup), _globalize_if_needed(target))
		return {"ok": false, "message": "Could not install Workshop chart folder: %s" % target}
	if target_exists:
		_clear_managed_folder(backup, root)
	return {"ok": true, "message": "Installed Workshop chart folder."}


static func _clear_managed_folder(folder_path: String, managed_root: String) -> Dictionary:
	var folder := folder_path.strip_edges()
	var root := managed_root.rstrip("/")
	if folder.is_empty() or not folder.begins_with(root + "/"):
		return {"ok": false, "message": "Refusing to clear unmanaged Workshop folder: %s" % folder}
	if not DirAccess.dir_exists_absolute(_globalize_if_needed(folder)):
		return {"ok": true, "message": "Target folder is empty."}
	return _delete_recursive(folder)


static func _delete_recursive(path: String) -> Dictionary:
	var dir := DirAccess.open(path)
	if dir != null:
		dir.list_dir_begin()
		while true:
			var name := dir.get_next()
			if name.is_empty():
				break
			if name == "." or name == "..":
				continue
			var child := path.path_join(name)
			if dir.current_is_dir():
				var child_result := _delete_recursive(child)
				if not bool(child_result.get("ok", false)):
					dir.list_dir_end()
					return child_result
			else:
				var file_err := DirAccess.remove_absolute(_globalize_if_needed(child))
				if file_err != OK:
					dir.list_dir_end()
					return {"ok": false, "message": "Could not delete %s." % child}
		dir.list_dir_end()
	var err := DirAccess.remove_absolute(_globalize_if_needed(path))
	if err != OK:
		return {"ok": false, "message": "Could not delete %s." % path}
	return {"ok": true, "message": "Deleted %s." % path}


static func _safe_item_id(item_id: String) -> String:
	var out := item_id.strip_edges()
	if out.is_valid_int() and int(out) > 0:
		return out
	return ""


static func _same_global_path(a: String, b: String) -> bool:
	var left := _globalize_if_needed(a).rstrip("/")
	var right := _globalize_if_needed(b).rstrip("/")
	return not left.is_empty() and left == right


static func _call_first(target: Object, method_names: Array[String], args: Array) -> Dictionary:
	if target == null:
		return {"called": false, "value": null}
	for method_name in method_names:
		if target.has_method(method_name):
			var result: Variant = target.callv(method_name, args)
			return {"called": true, "value": result}
	return {"called": false, "value": null}


static func _steam_singleton() -> Object:
	if Engine.has_singleton("Steam"):
		return Engine.get_singleton("Steam")
	return null


static func _steam_client() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null("/root/SteamClient")


static func _globalize_if_needed(path: String) -> String:
	if path.begins_with("user://") or path.begins_with("res://"):
		return ProjectSettings.globalize_path(path)
	return path
