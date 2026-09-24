extends RefCounted
class_name HarmonicProjectPackage

const SongResolver := preload("res://scripts/songs/SongResolver.gd")
const ChartValidator := preload("res://scripts/songs/ChartValidator.gd")
const ChartImportUtils := preload("res://scripts/editor/importers/ChartImportUtils.gd")
const YouTubeAudioImporter := preload("res://scripts/editor/YouTubeAudioImporter.gd")

const PACKAGE_EXTENSION := "harmonic"
const MANIFEST_FILE := "manifest.json"
const PREVIEW_FILE := "preview.png"
const AUDIO_EXTENSIONS: Array[String] = ["ogg", "wav", "mp3", "opus", "m4a", "webm", "aac", "mp4", "mov"]
const PACKAGE_EXTENSIONS: Array[String] = ["harmonic", "zip"]
const EXCLUDED_FILENAMES: Array[String] = [
	"waveform_preview_cache.wav",
	"midi_import_waveform_cache.wav",
]


static func export_project_to_harmonic(project_folder: String, output_path: String) -> Dictionary:
	var normalized_output := normalize_harmonic_path(output_path)
	if normalized_output.is_empty():
		return {"ok": false, "path": "", "error": "Choose a .harmonic package path."}
	var validation := validate_project_folder(project_folder)
	if not bool(validation.get("ok", false)):
		return validation
	var manifest := read_manifest(project_folder)
	var include_audio := not _has_valid_youtube_url(manifest)
	var export_audio_paths: Array[String] = []
	if include_audio:
		export_audio_paths = _audio_relative_paths_for_export(project_folder, manifest)
	if include_audio and export_audio_paths.is_empty():
		return {"ok": false, "path": "", "error": "Project has no valid YouTube URL and no local audio file to include."}
	var files := _collect_project_files(project_folder, include_audio, export_audio_paths)
	if files.is_empty():
		return {"ok": false, "path": "", "error": "Project has no files to export."}

	var output_abs := _globalize_if_needed(normalized_output)
	var dir_err := DirAccess.make_dir_recursive_absolute(output_abs.get_base_dir())
	if dir_err != OK:
		return {"ok": false, "path": "", "error": "Could not create export folder: %s" % output_abs.get_base_dir()}

	var writer := ZIPPacker.new()
	var open_err := writer.open(output_abs)
	if open_err != OK:
		return {"ok": false, "path": "", "error": "Could not create .harmonic package: %s" % normalized_output}
	for relative_path in files:
		var bytes := _bytes_for_export(project_folder, relative_path, true, include_audio, export_audio_paths)
		if bytes.is_empty():
			continue
		var start_err := writer.start_file(relative_path)
		if start_err != OK:
			writer.close()
			return {"ok": false, "path": "", "error": "Could not add %s to package." % relative_path}
		writer.write_file(bytes)
		writer.close_file()
	writer.close()
	return {"ok": true, "path": normalized_output, "error": "", "included_audio": include_audio and not export_audio_paths.is_empty(), "audio_files": export_audio_paths}


static func export_project_to_folder(project_folder: String, target_folder: String, preview_path: String = "") -> Dictionary:
	var validation := validate_project_folder(project_folder)
	if not bool(validation.get("ok", false)):
		return validation
	if target_folder.strip_edges().is_empty():
		return {"ok": false, "path": "", "error": "Missing target folder."}
	var target_abs := _globalize_if_needed(target_folder)
	var dir_err := DirAccess.make_dir_recursive_absolute(target_abs)
	if dir_err != OK:
		return {"ok": false, "path": "", "error": "Could not create export folder: %s" % target_folder}

	var files := _collect_project_files(project_folder, false)
	for relative_path in files:
		var bytes := _bytes_for_export(project_folder, relative_path, true, false, [])
		if bytes.is_empty():
			continue
		var target_path := target_folder.path_join(relative_path)
		var target_file_abs := _globalize_if_needed(target_path)
		DirAccess.make_dir_recursive_absolute(target_file_abs.get_base_dir())
		var file := FileAccess.open(target_file_abs, FileAccess.WRITE)
		if file == null:
			return {"ok": false, "path": "", "error": "Could not write %s." % target_path}
		file.store_buffer(bytes)
		file.flush()

	var preview_result := _ensure_preview_image(target_folder, preview_path)
	if not bool(preview_result.get("ok", false)):
		return preview_result
	return {"ok": true, "path": target_folder, "error": ""}


static func import_harmonic_to_custom_songs(package_path: String, custom_root: String = SongResolver.CUSTOM_ROOT) -> Dictionary:
	if package_path.strip_edges().is_empty():
		return {"ok": false, "project_folder": "", "manifest": {}, "youtube_url": "", "error": "Choose a .harmonic package."}
	if not FileAccess.file_exists(package_path):
		return {"ok": false, "project_folder": "", "manifest": {}, "youtube_url": "", "error": "Package file not found: %s" % package_path}

	var reader := ZIPReader.new()
	var open_err := reader.open(_globalize_if_needed(package_path))
	if open_err != OK:
		return {"ok": false, "project_folder": "", "manifest": {}, "youtube_url": "", "error": "Could not open package: %s" % package_path}
	var files := reader.get_files()
	if not files.has(MANIFEST_FILE):
		reader.close()
		return {"ok": false, "project_folder": "", "manifest": {}, "youtube_url": "", "error": "Package is missing manifest.json."}
	var manifest_bytes := reader.read_file(MANIFEST_FILE)
	var manifest_text := manifest_bytes.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(manifest_text)
	if parsed is not Dictionary:
		reader.close()
		return {"ok": false, "project_folder": "", "manifest": {}, "youtube_url": "", "error": "Package manifest.json is invalid."}
	var package_manifest := parsed as Dictionary
	var package_has_valid_youtube := _has_valid_youtube_url(package_manifest)
	var manifest := _manifest_without_audio_path(package_manifest) if package_has_valid_youtube else _manifest_with_packaged_audio(package_manifest, files)
	var folder_name := _project_folder_name(manifest, package_path.get_file().get_basename())
	var project_folder := _unique_project_folder(custom_root, folder_name)
	var project_abs := _globalize_if_needed(project_folder)
	var dir_err := DirAccess.make_dir_recursive_absolute(project_abs)
	if dir_err != OK:
		reader.close()
		return {"ok": false, "project_folder": "", "manifest": {}, "youtube_url": "", "error": "Could not create project folder: %s" % project_folder}

	for path_variant in files:
		var relative_path := str(path_variant)
		if relative_path.ends_with("/") or not _is_safe_relative_path(relative_path):
			continue
		if package_has_valid_youtube and _is_audio_file(relative_path):
			continue
		var target_path := project_folder.path_join(relative_path)
		var target_abs := _globalize_if_needed(target_path)
		DirAccess.make_dir_recursive_absolute(target_abs.get_base_dir())
		var bytes := JSON.stringify(manifest, "\t", false).to_utf8_buffer() if relative_path == MANIFEST_FILE else reader.read_file(relative_path)
		var target := FileAccess.open(target_abs, FileAccess.WRITE)
		if target == null:
			reader.close()
			return {"ok": false, "project_folder": project_folder, "manifest": manifest, "youtube_url": str(manifest.get("youtube_url", "")), "error": "Could not write %s." % target_path}
		target.store_buffer(bytes)
		target.flush()
	reader.close()

	return {
		"ok": true,
		"project_folder": project_folder,
		"manifest": manifest,
		"youtube_url": str(manifest.get("youtube_url", "")).strip_edges(),
		"error": "",
	}


static func validate_project_folder(project_folder: String) -> Dictionary:
	if project_folder.strip_edges().is_empty():
		return {"ok": false, "error": "Missing project folder."}
	var manifest_path := project_folder.path_join(MANIFEST_FILE)
	if not FileAccess.file_exists(manifest_path):
		return {"ok": false, "error": "Project is missing manifest.json."}
	var manifest := read_manifest(project_folder)
	if manifest.is_empty():
		return {"ok": false, "error": "Project manifest.json could not be read."}
	var validation := ChartValidator.validate_manifest(manifest)
	if not ChartValidator.is_valid(validation):
		var errors: Array = validation.get("errors", []) as Array
		var first := errors[0] as Dictionary if not errors.is_empty() else {}
		return {"ok": false, "error": str(first.get("message", "Project manifest is invalid.")), "validation": validation}
	return {"ok": true, "error": "", "manifest": manifest, "validation": validation}


static func read_manifest(project_folder: String) -> Dictionary:
	var manifest_path := project_folder.path_join(MANIFEST_FILE)
	if not FileAccess.file_exists(manifest_path):
		return {}
	var file := FileAccess.open(manifest_path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed as Dictionary if parsed is Dictionary else {}


static func write_manifest(project_folder: String, manifest: Dictionary) -> Dictionary:
	var manifest_path := project_folder.path_join(MANIFEST_FILE)
	var file := FileAccess.open(manifest_path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "Could not write manifest.json."}
	file.store_string(JSON.stringify(manifest, "\t", false))
	file.flush()
	return {"ok": true, "error": ""}


static func set_manifest_audio_path(project_folder: String, audio_path: String) -> Dictionary:
	var manifest := read_manifest(project_folder)
	if manifest.is_empty():
		return {"ok": false, "error": "Could not read manifest.json."}
	if audio_path.strip_edges().is_empty():
		manifest.erase("audio_path")
	else:
		manifest["audio_path"] = audio_path
	return write_manifest(project_folder, manifest)


static func set_manifest_youtube_url(project_folder: String, youtube_url: String) -> Dictionary:
	var manifest := read_manifest(project_folder)
	if manifest.is_empty():
		return {"ok": false, "error": "Could not read manifest.json."}
	manifest["youtube_url"] = youtube_url.strip_edges()
	return write_manifest(project_folder, manifest)


static func normalize_harmonic_path(path: String) -> String:
	var cleaned := path.strip_edges()
	if cleaned.is_empty():
		return ""
	if cleaned.get_extension().is_empty():
		cleaned += "." + PACKAGE_EXTENSION
	elif cleaned.get_extension().to_lower() != PACKAGE_EXTENSION:
		cleaned = cleaned.get_basename() + "." + PACKAGE_EXTENSION
	return cleaned


static func package_default_filename(project_folder: String) -> String:
	var manifest := read_manifest(project_folder)
	var id := str(manifest.get("song_id", project_folder.get_file())).strip_edges()
	if id.is_empty():
		id = project_folder.get_file()
	return "%s.%s" % [ChartImportUtils.sanitize_id(id), PACKAGE_EXTENSION]


static func _collect_project_files(project_folder: String, include_audio: bool, allowed_audio_paths: Array[String] = []) -> Array[String]:
	var root_abs := _globalize_if_needed(project_folder)
	var out: Array[String] = []
	_collect_project_files_recursive(root_abs, "", include_audio, allowed_audio_paths, out)
	out.sort()
	return out


static func _collect_project_files_recursive(root_abs: String, relative_dir: String, include_audio: bool, allowed_audio_paths: Array[String], out: Array[String]) -> void:
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
			_collect_project_files_recursive(root_abs, relative_path, include_audio, allowed_audio_paths, out)
			continue
		if _should_skip_file(relative_path, include_audio, allowed_audio_paths):
			continue
		out.append(relative_path)
	dir.list_dir_end()


static func _bytes_for_export(project_folder: String, relative_path: String, strip_audio_path: bool, include_audio: bool = false, audio_relative_paths: Array[String] = []) -> PackedByteArray:
	if relative_path == MANIFEST_FILE and strip_audio_path:
		var source_manifest := read_manifest(project_folder)
		var manifest := _manifest_with_packaged_audio(source_manifest, audio_relative_paths) if include_audio else _manifest_without_audio_path(source_manifest)
		return JSON.stringify(manifest, "\t", false).to_utf8_buffer()
	return FileAccess.get_file_as_bytes(_globalize_if_needed(project_folder.path_join(relative_path)))


static func _manifest_without_audio_path(manifest: Dictionary) -> Dictionary:
	var out := manifest.duplicate(true)
	out.erase("audio_path")
	if not out.has("youtube_url"):
		out["youtube_url"] = ""
	return out


static func _manifest_with_packaged_audio(manifest: Dictionary, audio_relative_paths: Array[String]) -> Dictionary:
	var out := manifest.duplicate(true)
	if not out.has("youtube_url"):
		out["youtube_url"] = ""
	var audio_path := _first_existing_audio_relative_path(audio_relative_paths)
	if audio_path.is_empty():
		out.erase("audio_path")
	else:
		out["audio_path"] = audio_path
	return out


static func _should_skip_file(relative_path: String, include_audio: bool, allowed_audio_paths: Array[String]) -> bool:
	var filename := relative_path.get_file()
	if EXCLUDED_FILENAMES.has(filename):
		return true
	if PACKAGE_EXTENSIONS.has(relative_path.get_extension().to_lower()):
		return true
	if not _is_audio_file(relative_path):
		return false
	if not include_audio:
		return true
	return not allowed_audio_paths.has(relative_path)


static func _is_audio_file(relative_path: String) -> bool:
	return AUDIO_EXTENSIONS.has(relative_path.get_extension().to_lower())


static func _has_valid_youtube_url(manifest: Dictionary) -> bool:
	return YouTubeAudioImporter.is_supported_url(str(manifest.get("youtube_url", "")).strip_edges())


static func _audio_relative_paths_for_export(project_folder: String, manifest: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var audio_path := str(manifest.get("audio_path", "")).strip_edges()
	var relative := _relative_audio_path(project_folder, audio_path)
	if not relative.is_empty():
		out.append(relative)
	for candidate in ["song.ogg", "song.wav", "song.mp3", "song.opus", "song.m4a", "song.webm", "song.aac"]:
		var p := project_folder.path_join(candidate)
		if FileAccess.file_exists(p) and not out.has(candidate):
			out.append(candidate)
	return out


static func _relative_audio_path(project_folder: String, audio_path: String) -> String:
	if audio_path.is_empty():
		return ""
	var candidate := audio_path
	if not FileAccess.file_exists(candidate):
		candidate = project_folder.path_join(audio_path)
	if not FileAccess.file_exists(candidate):
		return ""
	var relative := candidate
	var project_prefix := project_folder.rstrip("/") + "/"
	var project_abs_prefix := _globalize_if_needed(project_folder).rstrip("/") + "/"
	var candidate_abs := _globalize_if_needed(candidate)
	if relative.begins_with(project_prefix):
		relative = relative.substr(project_prefix.length())
	elif candidate_abs.begins_with(project_abs_prefix):
		relative = candidate_abs.substr(project_abs_prefix.length())
	elif not candidate.is_absolute_path() and not candidate.begins_with("user://") and not candidate.begins_with("res://"):
		relative = candidate
	else:
		return ""
	if not _is_safe_relative_path(relative) or not _is_audio_file(relative):
		return ""
	return relative


static func _first_existing_audio_relative_path(audio_relative_paths: Array) -> String:
	for item in audio_relative_paths:
		var relative := str(item).strip_edges()
		if not relative.is_empty() and _is_safe_relative_path(relative) and _is_audio_file(relative):
			return relative
	return ""


static func _is_safe_relative_path(relative_path: String) -> bool:
	if relative_path.is_empty() or relative_path.begins_with("/") or relative_path.begins_with("\\"):
		return false
	if relative_path.contains("..") or relative_path.contains(":"):
		return false
	return true


static func _project_folder_name(manifest: Dictionary, fallback: String) -> String:
	var raw := str(manifest.get("song_id", "")).strip_edges()
	if raw.is_empty():
		raw = str(manifest.get("title", "")).strip_edges()
	if raw.is_empty():
		raw = fallback
	return ChartImportUtils.sanitize_id(raw)


static func _unique_project_folder(root: String, folder_name: String) -> String:
	var base := root.path_join(ChartImportUtils.sanitize_id(folder_name))
	var out := base
	var suffix := 2
	while DirAccess.dir_exists_absolute(_globalize_if_needed(out)):
		out = root.path_join("%s_%d" % [folder_name, suffix])
		suffix += 1
	return out


static func _ensure_preview_image(target_folder: String, preview_path: String) -> Dictionary:
	var target_preview := target_folder.path_join(PREVIEW_FILE)
	if not preview_path.strip_edges().is_empty():
		var copied := _copy_file(preview_path, target_preview)
		if not bool(copied.get("ok", false)):
			return copied
		return {"ok": true, "error": ""}
	if FileAccess.file_exists(target_preview):
		return {"ok": true, "error": ""}
	var image := Image.create(512, 512, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.03, 0.04, 0.10, 1.0))
	for lane in range(6):
		var x0 := 54 + lane * 68
		for x in range(x0, x0 + 28):
			for y in range(72, 440):
				var pulse := 0.28 + float((x + y + lane * 17) % 70) / 220.0
				image.set_pixel(x, y, Color(0.0, 0.85, 1.0, pulse))
	for y2 in range(390, 405):
		for x2 in range(44, 468):
			image.set_pixel(x2, y2, Color(1.0, 0.18, 0.45, 0.92))
	var save_err := image.save_png(_globalize_if_needed(target_preview))
	if save_err != OK:
		return {"ok": false, "error": "Could not write Workshop preview image."}
	return {"ok": true, "error": ""}


static func _copy_file(source_path: String, target_path: String) -> Dictionary:
	var source_abs := _globalize_if_needed(source_path)
	if not FileAccess.file_exists(source_abs):
		return {"ok": false, "error": "Preview image not found: %s" % source_path}
	var target_abs := _globalize_if_needed(target_path)
	DirAccess.make_dir_recursive_absolute(target_abs.get_base_dir())
	var bytes := FileAccess.get_file_as_bytes(source_abs)
	if bytes.is_empty():
		return {"ok": false, "error": "Could not read preview image: %s" % source_path}
	var target := FileAccess.open(target_abs, FileAccess.WRITE)
	if target == null:
		return {"ok": false, "error": "Could not write preview image: %s" % target_path}
	target.store_buffer(bytes)
	target.flush()
	return {"ok": true, "error": ""}


static func _globalize_if_needed(path: String) -> String:
	if path.begins_with("user://") or path.begins_with("res://"):
		return ProjectSettings.globalize_path(path)
	return path
