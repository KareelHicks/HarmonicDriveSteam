extends RefCounted
class_name WorkshopChartAudioLink

const EditorAudioImporter := preload("res://scripts/editor/importers/EditorAudioImporter.gd")
const HarmonicProjectPackage := preload("res://scripts/editor/HarmonicProjectPackage.gd")
const SongResolver := preload("res://scripts/songs/SongResolver.gd")

const LINK_FILENAME := "audio_link.json"


static func link_audio_file(item_id: String, project_folder: String, source_audio_path: String) -> Dictionary:
	var normalized_item_id := _safe_item_id(item_id)
	if normalized_item_id.is_empty():
		return {"ok": false, "error": "Workshop item id is missing."}
	if project_folder.strip_edges().is_empty() or not DirAccess.dir_exists_absolute(_globalize_if_needed(project_folder)):
		return {"ok": false, "error": "Community chart folder is missing."}
	var source_path := source_audio_path.strip_edges()
	if source_path.is_empty() or not FileAccess.file_exists(_globalize_if_needed(source_path)):
		return {"ok": false, "error": "Audio file not found: %s" % source_audio_path}

	SongResolver.ensure_user_song_dirs()
	var cache_folder := link_folder(normalized_item_id)
	var dir_err := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(cache_folder))
	if dir_err != OK:
		return {"ok": false, "error": "Could not create linked audio folder: %s" % cache_folder}

	var import_result := EditorAudioImporter.import_audio(source_path, cache_folder)
	if not bool(import_result.get("ok", false)):
		return {"ok": false, "error": str(import_result.get("error", "Audio import failed."))}
	var audio_path := str(import_result.get("path", "")).strip_edges()
	if audio_path.is_empty() or not FileAccess.file_exists(_globalize_if_needed(audio_path)):
		return {"ok": false, "error": "Linked audio import did not create a playable audio file."}

	var manifest_result := HarmonicProjectPackage.set_manifest_audio_path(project_folder, audio_path)
	if not bool(manifest_result.get("ok", false)):
		return {"ok": false, "error": str(manifest_result.get("error", "Could not update Community Chart manifest."))}

	var link_record := {
		"item_id": normalized_item_id,
		"project_folder": project_folder,
		"audio_path": audio_path,
		"source_file": source_path.get_file(),
		"linked_at": Time.get_datetime_string_from_system(true),
	}
	var write_result := _write_json(link_file(normalized_item_id), link_record)
	if not bool(write_result.get("ok", false)):
		return write_result
	return {
		"ok": true,
		"item_id": normalized_item_id,
		"project_folder": project_folder,
		"audio_path": audio_path,
		"source_file": source_path.get_file(),
	}


static func apply_saved_link(item_id: String, project_folder: String) -> Dictionary:
	var normalized_item_id := _safe_item_id(item_id)
	if normalized_item_id.is_empty():
		return {"ok": false, "applied": false, "error": "Workshop item id is missing."}
	var record := read_link(normalized_item_id)
	if record.is_empty():
		return {"ok": true, "applied": false, "error": ""}
	var audio_path := str(record.get("audio_path", "")).strip_edges()
	if audio_path.is_empty() or not FileAccess.file_exists(_globalize_if_needed(audio_path)):
		return {"ok": false, "applied": false, "error": "Linked audio file is missing."}
	var manifest_result := HarmonicProjectPackage.set_manifest_audio_path(project_folder, audio_path)
	if not bool(manifest_result.get("ok", false)):
		return {"ok": false, "applied": false, "error": str(manifest_result.get("error", "Could not update Community Chart manifest."))}
	return {"ok": true, "applied": true, "audio_path": audio_path, "error": ""}


static func read_link(item_id: String) -> Dictionary:
	var normalized_item_id := _safe_item_id(item_id)
	if normalized_item_id.is_empty():
		return {}
	var path := link_file(normalized_item_id)
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return (parsed as Dictionary) if parsed is Dictionary else {}


static func link_folder(item_id: String) -> String:
	return SongResolver.WORKSHOP_AUDIO_ROOT.path_join(_safe_item_id(item_id))


static func link_file(item_id: String) -> String:
	return link_folder(item_id).path_join(LINK_FILENAME)


static func item_id_from_project_folder(project_folder: String) -> String:
	var root := SongResolver.WORKSHOP_ROOT.rstrip("/")
	var folder := project_folder.strip_edges().rstrip("/")
	if folder.is_empty() or not folder.begins_with(root + "/"):
		return ""
	return _safe_item_id(folder.get_file())


static func _safe_item_id(item_id: String) -> String:
	var out := item_id.strip_edges()
	if out.is_valid_int() and int(out) > 0:
		return out
	return ""


static func _write_json(path: String, value: Dictionary) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "Could not write linked audio metadata: %s" % path}
	file.store_string(JSON.stringify(value, "\t", false))
	file.flush()
	return {"ok": true, "error": ""}


static func _globalize_if_needed(path: String) -> String:
	if path.begins_with("user://") or path.begins_with("res://"):
		return ProjectSettings.globalize_path(path)
	return path
