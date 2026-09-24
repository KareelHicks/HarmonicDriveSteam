extends SceneTree

const HarmonicProjectPackage := preload("res://scripts/editor/HarmonicProjectPackage.gd")
const SongResolver := preload("res://scripts/songs/SongResolver.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := false
	var stamp := str(Time.get_unix_time_from_system()) + "_" + str(Time.get_ticks_msec())
	var root_path := "user://local_songs_harmonic_import_smoke_%s" % stamp
	var project := root_path.path_join("source_project")
	_create_harmonic_fixture(project)
	var package_path := root_path.path_join("local_songs_visible.harmonic")
	var export_result := HarmonicProjectPackage.export_project_to_harmonic(project, package_path)
	failed = _expect(bool(export_result.get("ok", false)), "Could not export .harmonic fixture: %s" % str(export_result.get("error", ""))) or failed
	var imported_folder := ""
	if bool(export_result.get("ok", false)):
		var import_result := HarmonicProjectPackage.import_harmonic_to_custom_songs(package_path)
		failed = _expect(bool(import_result.get("ok", false)), "Could not import .harmonic fixture: %s" % str(import_result.get("error", ""))) or failed
		imported_folder = str(import_result.get("project_folder", ""))
	var packed := load("res://scenes/menus/LocalSongsMenu.tscn") as PackedScene
	failed = _expect(packed != null, "Could not load LocalSongsMenu.tscn.") or failed
	if packed == null:
		quit(1)
		return
	var menu := packed.instantiate()
	root.add_child(menu)
	await process_frame

	var source_dialog := menu.get("_import_source_dialog") as ConfirmationDialog
	var harmonic_dialog := menu.get("_import_harmonic_file_dialog") as FileDialog
	failed = _expect(source_dialog != null, "LocalSongsMenu did not create import source dialog.") or failed
	failed = _expect(harmonic_dialog != null, "LocalSongsMenu did not create .harmonic file dialog.") or failed
	if harmonic_dialog != null:
		failed = _expect(harmonic_dialog.filters.has("*.harmonic ; Harmonic Drive project (*.harmonic)"), ".harmonic import filter missing.") or failed

	if source_dialog != null and harmonic_dialog != null:
		menu.call("_on_import_source_custom_action", &"harmonic")
		await process_frame
		failed = _expect(harmonic_dialog.visible, "Import .harmonic action did not show the file dialog.") or failed
		var all_songs: Array = menu.get("_all_songs") as Array
		var found_import := false
		var loaded_ids: Array[String] = []
		for song_var in all_songs:
			if song_var is Dictionary:
				var song := song_var as Dictionary
				loaded_ids.append(str(song.get("song_id", "")))
				if str(song.get("song_id", "")) == "local_songs_visible_harmonic":
					found_import = true
		var song_db: Variant = menu.get("_song_db")
		var load_errors: Array = []
		var load_warnings: Array = []
		var raw_loaded_ids: Array[String] = []
		if song_db != null and song_db.has_method("get_load_errors"):
			load_errors = song_db.get_load_errors()
		if song_db != null and song_db.has_method("get_load_warnings"):
			load_warnings = song_db.get_load_warnings()
		if song_db != null and song_db.has_method("get_songs"):
			for raw_song_var in song_db.get_songs():
				if raw_song_var is Dictionary:
					raw_loaded_ids.append("%s:%s:%s" % [
						str((raw_song_var as Dictionary).get("song_id", "")),
						str((raw_song_var as Dictionary).get("source", "")),
						str((raw_song_var as Dictionary).get("root_path", "")),
					])
		failed = _expect(
			found_import,
			"Imported .harmonic project did not appear in Local Songs. imported=%s filter=%s root_filter=%s filtered=%s raw=%s errors=%s warnings=%s" % [
				imported_folder,
				str(menu.get("_source_type_filter")),
				str(menu.get("_source_root_filter")),
				JSON.stringify(loaded_ids),
				JSON.stringify(raw_loaded_ids),
				JSON.stringify(load_errors),
				JSON.stringify(load_warnings),
			]
		) or failed

	if not imported_folder.is_empty():
		_cleanup_target(imported_folder)
	_cleanup_target(root_path)
	if failed:
		quit(1)
	else:
		print("Local Songs .harmonic import smoke test passed.")
		quit(0)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return false
	push_error(message)
	return true


func _create_harmonic_fixture(project: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(project))
	_write_json(project.path_join("manifest.json"), {
		"song_id": "local_songs_visible_harmonic",
		"title": "Local Songs Visible Harmonic",
		"artist": "Automated Test",
		"charter": "Automated Test",
		"bpm": 128.0,
		"offset": 0.0,
		"youtube_url": "",
		"audio_path": "song.ogg",
		"difficulties": ["expert"],
	})
	_write_json(project.path_join("expert.json"), {
		"version": 1,
		"difficulty": "expert",
		"lane_count": 5,
		"bpm": 128.0,
		"notes": [{"time": 1.0, "lane": 0, "type": "tap"}],
	})
	_write_bytes(project.path_join("song.ogg"), PackedByteArray([79, 103, 103, 83, 1, 2, 3]))


func _write_json(path: String, payload: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Could not write JSON fixture: %s" % path)
		return
	file.store_string(JSON.stringify(payload, "\t", false))
	file.flush()


func _write_bytes(path: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Could not write byte fixture: %s" % path)
		return
	file.store_buffer(bytes)
	file.flush()


func _cleanup_target(path: String) -> void:
	if path.is_empty() or not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path)):
		return
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
				_cleanup_target(child)
			else:
				DirAccess.remove_absolute(ProjectSettings.globalize_path(child))
		dir.list_dir_end()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
