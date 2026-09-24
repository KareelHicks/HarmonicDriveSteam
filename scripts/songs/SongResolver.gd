extends RefCounted
class_name SongResolver

const OFFICIAL_ROOT := "res://songs/official"
const WORKSHOP_ROOT := "user://workshop"
const WORKSHOP_AUDIO_ROOT := "user://workshop_audio"
const CUSTOM_ROOT := "user://custom_songs"

const MANIFEST_FILENAME := "manifest.json"


static func ensure_user_song_dirs() -> void:
	_ensure_user_dir(WORKSHOP_ROOT)
	_ensure_user_dir(WORKSHOP_AUDIO_ROOT)
	_ensure_user_dir(CUSTOM_ROOT)
	_ensure_user_dir("user://audio_cache")


static func list_all_song_roots() -> Array[String]:
	return [OFFICIAL_ROOT, WORKSHOP_ROOT, CUSTOM_ROOT]


static func list_song_folders(root: String) -> Array[String]:
	var folders: Array[String] = []
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(root)) and root.begins_with("user://"):
		return folders
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(root)) and root.begins_with("res://"):
		# res:// directory existence is handled by DirAccess.open below.
		pass

	var dir := DirAccess.open(root)
	if dir == null:
		return folders
	dir.list_dir_begin()
	while true:
		var name: String = dir.get_next()
		if name.is_empty():
			break
		if name == "." or name == "..":
			continue
		if not dir.current_is_dir():
			continue
		var folder_path := root.path_join(name)
		var manifest_path := folder_path.path_join(MANIFEST_FILENAME)
		if FileAccess.file_exists(manifest_path):
			folders.append(folder_path)
	dir.list_dir_end()
	return folders


static func get_manifest_path(song_folder: String) -> String:
	return song_folder.path_join(MANIFEST_FILENAME)


static func get_chart_path(song_folder: String, difficulty: String) -> String:
	var id := difficulty.strip_edges().to_lower()
	var manifest_path := get_manifest_path(song_folder)
	if FileAccess.file_exists(manifest_path):
		var parsed: Variant = JSON.parse_string(FileAccess.open(manifest_path, FileAccess.READ).get_as_text())
		if parsed is Dictionary:
			var manifest := parsed as Dictionary
			var chart_files: Dictionary = manifest.get("chart_files", {}) as Dictionary
			var filename := str(chart_files.get(id, "")).strip_edges()
			if _is_safe_chart_filename(filename):
				return song_folder.path_join(filename.get_file())
	return song_folder.path_join("%s.json" % id)


static func _is_safe_chart_filename(filename: String) -> bool:
	if filename.is_empty():
		return false
	if filename.contains("/") or filename.contains("\\") or filename.contains(".."):
		return false
	return filename.get_extension().to_lower() == "json"


static func get_asset_path(song_folder: String, filename: String) -> String:
	return song_folder.path_join(filename)


static func _ensure_user_dir(user_path: String) -> void:
	if not user_path.begins_with("user://"):
		return
	var abs: String = ProjectSettings.globalize_path(user_path)
	if DirAccess.dir_exists_absolute(abs):
		return
	var err := DirAccess.make_dir_recursive_absolute(abs)
	if err != OK:
		push_warning("Failed to create directory %s (error %d)" % [user_path, err])
