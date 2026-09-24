extends SceneTree

const HarmonicProjectPackage := preload("res://scripts/editor/HarmonicProjectPackage.gd")
const ChartWorkshopManager := preload("res://scripts/editor/ChartWorkshopManager.gd")
const YouTubeAudioImporter := preload("res://scripts/editor/YouTubeAudioImporter.gd")

var _failures: Array[String] = []


func _init() -> void:
	var stamp := str(Time.get_unix_time_from_system()) + "_" + str(Time.get_ticks_msec())
	var root := "user://harmonic_project_package_smoke_%s" % stamp
	var project := root.path_join("source_project")
	var imports_root := root.path_join("imports")
	var workshop_folder := root.path_join("workshop_export")
	var local_audio_project := root.path_join("local_audio_project")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(project))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(imports_root))
	_write_json(project.path_join("manifest.json"), {
		"song_id": "package_smoke",
		"title": "Package Smoke",
		"artist": "Test Artist",
		"charter": "Test Charter",
		"bpm": 128.0,
		"offset": 0.0,
		"youtube_url": "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
		"audio_path": project.path_join("song.ogg"),
		"difficulties": ["expert"],
	})
	_write_json(project.path_join("expert.json"), {
		"version": 1,
		"difficulty": "expert",
		"lane_count": 5,
		"bpm": 128.0,
		"notes": [{"time": 1.0, "lane": 0, "type": "tap"}],
	})
	_write_bytes(project.path_join("song.ogg"), PackedByteArray([79, 103, 103, 83]))
	_write_bytes(project.path_join("source.webm"), PackedByteArray([26, 69, 223, 163]))
	_write_bytes(project.path_join("waveform_preview_cache.wav"), PackedByteArray([82, 73, 70, 70]))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(local_audio_project))
	_write_json(local_audio_project.path_join("manifest.json"), {
		"song_id": "local_audio_package_smoke",
		"title": "Local Audio Package Smoke",
		"artist": "Test Artist",
		"charter": "Test Charter",
		"bpm": 128.0,
		"offset": 0.0,
		"youtube_url": "not a youtube url",
		"audio_path": "song.ogg",
		"difficulties": ["expert"],
	})
	_write_json(local_audio_project.path_join("expert.json"), {
		"version": 1,
		"difficulty": "expert",
		"lane_count": 5,
		"bpm": 128.0,
		"notes": [{"time": 1.0, "lane": 0, "type": "tap"}],
	})
	_write_bytes(local_audio_project.path_join("song.ogg"), PackedByteArray([79, 103, 103, 83, 1, 2, 3]))

	var package_path := root.path_join("package_smoke.harmonic")
	var export_result := HarmonicProjectPackage.export_project_to_harmonic(project, package_path)
	_expect(bool(export_result.get("ok", false)), "Export to .harmonic failed: %s" % str(export_result.get("error", "")))
	_check_zip(package_path)

	var import_result := HarmonicProjectPackage.import_harmonic_to_custom_songs(package_path, imports_root)
	_expect(bool(import_result.get("ok", false)), "Import .harmonic failed: %s" % str(import_result.get("error", "")))
	if bool(import_result.get("ok", false)):
		var imported_folder := str(import_result.get("project_folder", ""))
		var imported_manifest := HarmonicProjectPackage.read_manifest(imported_folder)
		_expect(str(imported_manifest.get("youtube_url", "")).contains("youtube.com"), "Imported manifest lost youtube_url.")
		_expect(not imported_manifest.has("audio_path"), "Imported manifest should not retain audio_path before download.")
		_expect(not FileAccess.file_exists(imported_folder.path_join("song.ogg")), "Imported .harmonic should not copy audio files.")

	var local_audio_package_path := root.path_join("local_audio_package_smoke.harmonic")
	var local_audio_export := HarmonicProjectPackage.export_project_to_harmonic(local_audio_project, local_audio_package_path)
	_expect(bool(local_audio_export.get("ok", false)), "Local-audio .harmonic export failed: %s" % str(local_audio_export.get("error", "")))
	_expect(bool(local_audio_export.get("included_audio", false)), "Local-audio .harmonic export did not report included audio.")
	_check_zip_with_local_audio(local_audio_package_path)
	var local_audio_import := HarmonicProjectPackage.import_harmonic_to_custom_songs(local_audio_package_path, imports_root)
	_expect(bool(local_audio_import.get("ok", false)), "Local-audio .harmonic import failed: %s" % str(local_audio_import.get("error", "")))
	if bool(local_audio_import.get("ok", false)):
		var local_import_folder := str(local_audio_import.get("project_folder", ""))
		var local_import_manifest := HarmonicProjectPackage.read_manifest(local_import_folder)
		_expect(str(local_import_manifest.get("audio_path", "")) == "song.ogg", "Packaged local audio should keep relative audio_path.")
		_expect(FileAccess.file_exists(local_import_folder.path_join("song.ogg")), "Packaged local audio was not imported.")

	var folder_result := HarmonicProjectPackage.export_project_to_folder(project, workshop_folder)
	_expect(bool(folder_result.get("ok", false)), "Workshop folder export failed: %s" % str(folder_result.get("error", "")))
	_expect(FileAccess.file_exists(workshop_folder.path_join("preview.png")), "Workshop export did not create preview.png.")
	var workshop_manifest := HarmonicProjectPackage.read_manifest(workshop_folder)
	_expect(not workshop_manifest.has("audio_path"), "Workshop manifest should not contain audio_path.")
	_expect(not FileAccess.file_exists(workshop_folder.path_join("song.ogg")), "Workshop export should not copy song.ogg.")

	var manager := ChartWorkshopManager.new()
	var dry_run := manager.upload_project(workshop_folder, {
		"title": "Package Smoke",
		"description": "Dry-run smoke upload.",
		"tags": ["Chart", "Smoke"],
		"visibility": "public",
		"change_note": "Smoke test.",
		"dry_run": true,
	})
	_expect(bool(dry_run.get("ok", false)) and bool(dry_run.get("dry_run", false)), "Chart Workshop dry-run failed: %s" % str(dry_run.get("message", "")))
	_expect(bool((dry_run.get("upload_payload", {}) as Dictionary).get("ok", false)), "Chart Workshop dry-run did not validate upload payload.")
	_expect(int((dry_run.get("upload_payload", {}) as Dictionary).get("payload_size_bytes", 0)) > 0, "Chart Workshop dry-run payload size should be nonzero.")
	_expect(str((dry_run.get("metadata", {}) as Dictionary).get("hd_content_type", "")) == "chart", "Chart Workshop metadata should mark hd_content_type=chart.")
	var upload_metadata := dry_run.get("upload_metadata", {}) as Dictionary
	_expect(str(upload_metadata.get("title", "")) == "Package Smoke", "Chart Workshop upload metadata lost the requested title.")
	_expect(str(upload_metadata.get("description", "")) == "Dry-run smoke upload.", "Chart Workshop upload metadata lost the requested description.")
	var created_item_id := str(manager.call("_extract_item_id", [1, 123456789012345678, false]))
	_expect(created_item_id == "123456789012345678", "Chart Workshop create-item callback did not accept GodotSteam's three-argument signal shape.")
	_expect(bool(manager.call("_extract_needs_legal_agreement", [1, 123456789012345678, true])), "Chart Workshop create-item callback did not detect legal-agreement flag.")

	var invalid_youtube := YouTubeAudioImporter.import_url_to_project("not a youtube url", project)
	_expect(not bool(invalid_youtube.get("ok", false)), "Invalid YouTube URLs should be rejected before tool execution.")

	if _failures.is_empty():
		print("Harmonic project package smoke test passed.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _check_zip(package_path: String) -> void:
	var reader := ZIPReader.new()
	var err := reader.open(ProjectSettings.globalize_path(package_path))
	_expect(err == OK, "Could not open exported .harmonic package.")
	if err != OK:
		return
	var files := reader.get_files()
	_expect(files.has("manifest.json"), ".harmonic package missing manifest.json.")
	_expect(files.has("expert.json"), ".harmonic package missing expert.json.")
	_expect(not files.has("song.ogg"), ".harmonic package should not include song.ogg.")
	_expect(not files.has("source.webm"), ".harmonic package should not include downloaded source audio.")
	_expect(not files.has("waveform_preview_cache.wav"), ".harmonic package should not include waveform cache.")
	var manifest_text := reader.read_file("manifest.json").get_string_from_utf8()
	var manifest: Variant = JSON.parse_string(manifest_text)
	if manifest is Dictionary:
		_expect(str((manifest as Dictionary).get("youtube_url", "")).contains("youtube.com"), ".harmonic manifest lost youtube_url.")
		_expect(not (manifest as Dictionary).has("audio_path"), ".harmonic manifest should not include audio_path.")
	else:
		_expect(false, ".harmonic manifest is not valid JSON.")
	reader.close()


func _check_zip_with_local_audio(package_path: String) -> void:
	var reader := ZIPReader.new()
	var err := reader.open(ProjectSettings.globalize_path(package_path))
	_expect(err == OK, "Could not open local-audio .harmonic package.")
	if err != OK:
		return
	var files := reader.get_files()
	_expect(files.has("manifest.json"), "Local-audio .harmonic package missing manifest.json.")
	_expect(files.has("expert.json"), "Local-audio .harmonic package missing expert.json.")
	_expect(files.has("song.ogg"), "Local-audio .harmonic package should include song.ogg.")
	var manifest_text := reader.read_file("manifest.json").get_string_from_utf8()
	var manifest: Variant = JSON.parse_string(manifest_text)
	if manifest is Dictionary:
		_expect(str((manifest as Dictionary).get("audio_path", "")) == "song.ogg", "Local-audio .harmonic manifest should keep relative audio_path.")
	else:
		_expect(false, "Local-audio .harmonic manifest is not valid JSON.")
	reader.close()


func _write_json(path: String, value: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_failures.append("Could not write JSON fixture: %s" % path)
		return
	file.store_string(JSON.stringify(value, "\t", false))
	file.flush()


func _write_bytes(path: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_failures.append("Could not write byte fixture: %s" % path)
		return
	file.store_buffer(bytes)
	file.flush()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
