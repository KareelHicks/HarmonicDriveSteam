extends Node

const CLOUD_FILE_NAME := "profile.cfg"

var _steam: Object
var _steam_ready := false
var _initial_sync_complete := false
var _applying_remote_profile := false
var _queued_upload := false
var _last_uploaded_revision := -1
var _status_text := "Steam Cloud unavailable."


func _ready() -> void:
	if ProfileStore != null and not ProfileStore.profile_changed.is_connected(_on_profile_changed):
		ProfileStore.profile_changed.connect(_on_profile_changed)
	set_process(true)


func _process(_delta: float) -> void:
	if not _steam_ready:
		if not _resolve_steam():
			return
		_perform_initial_sync()
		return
	if _queued_upload and _initial_sync_complete and not _applying_remote_profile:
		_upload_local_profile()


func get_status_text() -> String:
	return _status_text


func force_upload_local_profile() -> bool:
	_queued_upload = true
	if not _resolve_steam():
		return false
	if _applying_remote_profile:
		return false
	_upload_local_profile()
	return _status_text == "Steam Cloud synced."


func _resolve_steam() -> bool:
	if _steam_ready and _steam != null:
		return true
	if not Engine.has_singleton("Steam"):
		_status_text = "Steam Cloud unavailable in this build."
		return false
	if SteamClient == null or not SteamClient.is_ready():
		_status_text = "Waiting for Steam client..."
		return false
	_steam = Engine.get_singleton("Steam")
	if _steam == null:
		_status_text = "Steam Cloud unavailable in this build."
		return false
	if not _is_cloud_available():
		_status_text = "Steam Cloud is disabled for this account or app."
		return false
	_steam_ready = true
	_status_text = "Steam Cloud ready."
	return true


func _is_cloud_available() -> bool:
	if _steam == null:
		return false
	var app_enabled := true
	var account_enabled := true
	if _steam.has_method("isCloudEnabledForApp"):
		app_enabled = bool(_steam.call("isCloudEnabledForApp"))
	if _steam.has_method("isCloudEnabledForAccount"):
		account_enabled = bool(_steam.call("isCloudEnabledForAccount"))
	return app_enabled and account_enabled


func _perform_initial_sync() -> void:
	if _initial_sync_complete:
		return
	var remote_exists := _remote_file_exists()
	var applied_remote := false
	if remote_exists:
		var remote_contents := _read_remote_profile()
		if not remote_contents.is_empty() and _should_apply_remote_profile(remote_contents):
			_apply_remote_profile(remote_contents)
			applied_remote = true
	var local_revision := ProfileStore.get_profile_revision()
	_last_uploaded_revision = local_revision
	if not remote_exists or not applied_remote:
		_upload_local_profile()
	_initial_sync_complete = true


func _on_profile_changed() -> void:
	if _applying_remote_profile:
		return
	if not _initial_sync_complete:
		return
	_queued_upload = true


func _upload_local_profile() -> void:
	if not _resolve_steam():
		return
	var save_path := ProfileStore.get_save_path()
	if not FileAccess.file_exists(save_path):
		return
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return
	var contents := file.get_as_text()
	file.close()
	var bytes := contents.to_utf8_buffer()
	if _steam.has_method("beginFileWriteBatch"):
		_steam.call("beginFileWriteBatch")
	var success := false
	if _steam.has_method("fileWrite"):
		success = bool(_steam.call("fileWrite", CLOUD_FILE_NAME, bytes, bytes.size()))
	if _steam.has_method("endFileWriteBatch"):
		_steam.call("endFileWriteBatch")
	if success:
		_last_uploaded_revision = ProfileStore.get_profile_revision()
		_initial_sync_complete = true
		_queued_upload = false
		_status_text = "Steam Cloud synced."
	else:
		_status_text = "Steam Cloud upload failed."


func _remote_file_exists() -> bool:
	if _steam == null or not _steam.has_method("fileExists"):
		return false
	return bool(_steam.call("fileExists", CLOUD_FILE_NAME))


func _read_remote_profile() -> String:
	if _steam == null or not _steam.has_method("fileRead"):
		return ""
	var file_size := _get_remote_file_size()
	if file_size <= 0:
		return ""
	var response: Variant = _steam.call("fileRead", CLOUD_FILE_NAME, file_size)
	if response is PackedByteArray:
		return (response as PackedByteArray).get_string_from_utf8()
	if response is String:
		return str(response)
	return ""


func _get_remote_file_size() -> int:
	if _steam == null:
		return -1
	if _steam.has_method("getFileSize"):
		return int(_steam.call("getFileSize", CLOUD_FILE_NAME))
	if _steam.has_method("fileGetSize"):
		return int(_steam.call("fileGetSize", CLOUD_FILE_NAME))
	if _steam.has_method("fileSize"):
		return int(_steam.call("fileSize", CLOUD_FILE_NAME))
	return -1


func _should_apply_remote_profile(remote_contents: String) -> bool:
	if remote_contents.is_empty():
		return false
	var remote_meta := _extract_profile_metadata(remote_contents)
	var local_meta := _extract_local_profile_metadata()
	var remote_saved := int(remote_meta.get("profile_last_saved_unix", 0))
	var local_saved := int(local_meta.get("profile_last_saved_unix", 0))
	if remote_saved != local_saved:
		return remote_saved > local_saved
	var remote_revision := int(remote_meta.get("profile_revision", 0))
	var local_revision := int(local_meta.get("profile_revision", 0))
	return remote_revision > local_revision


func _extract_local_profile_metadata() -> Dictionary:
	return {
		"profile_revision": ProfileStore.get_profile_revision(),
		"profile_last_saved_unix": ProfileStore.get_profile_last_saved_unix(),
	}


func _extract_profile_metadata(contents: String) -> Dictionary:
	var config := ConfigFile.new()
	var parse_result := config.parse(contents)
	if parse_result != OK:
		return {}
	return {
		"profile_revision": int(config.get_value("profile", "profile_revision", 0)),
		"profile_last_saved_unix": int(config.get_value("profile", "profile_last_saved_unix", 0)),
	}


func _apply_remote_profile(remote_contents: String) -> void:
	var save_path := ProfileStore.get_save_path()
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		_status_text = "Steam Cloud download could not be written locally."
		return
	file.store_string(remote_contents)
	file.close()
	_applying_remote_profile = true
	ProfileStore.reload_profile_from_disk()
	_applying_remote_profile = false
	_status_text = "Steam Cloud downloaded latest save."
