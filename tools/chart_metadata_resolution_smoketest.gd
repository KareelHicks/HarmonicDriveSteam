extends SceneTree

const ChartMetadataResolver := preload("res://scripts/songs/ChartMetadataResolver.gd")
const SongPackageManager := preload("res://scripts/editor/SongPackageManager.gd")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var stamp := "%d_%d" % [int(Time.get_unix_time_from_system()), Time.get_ticks_msec()]
	var project := "user://chart_metadata_resolution_smoke_%s" % stamp
	_create_fixture(project)
	var manifest := _read_json(project.path_join("manifest.json"))
	var song := {
		"song_id": "chart_metadata_resolution_smoke",
		"title": str(manifest.get("title", "")),
		"artist": str(manifest.get("artist", "")),
		"charter": str(manifest.get("charter", "")),
		"root_path": project,
		"manifest_path": project.path_join("manifest.json"),
		"source": "custom",
		"chart_paths": {
			"easy": project.path_join("easy.json"),
			"expert": project.path_join("expert.json"),
			"professional": project.path_join("professional.json"),
		},
	}

	var expert_meta := ChartMetadataResolver.metadata_for_song_entry(song, "expert")
	_expect(str(expert_meta.get("title", "")) == "Expert Difficulty Title", "Current difficulty title should win when set.")
	_expect(str(expert_meta.get("artist", "")) == "Professional Artist", "Expert metadata should fall back to Professional artist.")
	_expect(str(expert_meta.get("charter", "")) == "Professional Charter", "Expert metadata should fall back to Professional charter.")

	var easy_meta := ChartMetadataResolver.metadata_for_song_entry(song, "easy")
	_expect(str(easy_meta.get("title", "")) == "Professional Difficulty Title", "Easy metadata should fall back to Professional title.")
	_expect(str(easy_meta.get("artist", "")) == "Professional Artist", "Easy metadata should fall back to Professional artist.")
	_expect(str(easy_meta.get("charter", "")) == "Professional Charter", "Easy metadata should fall back to Professional charter.")

	await _check_song_select_launch_payload(song)
	await _check_local_songs_launch_payload(song)
	_check_clone_metadata(project)
	_cleanup_target(project)
	if _failures.is_empty():
		print("Chart metadata resolution smoke test passed.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _check_local_songs_launch_payload(song: Dictionary) -> void:
	var packed := load("res://scenes/menus/LocalSongsMenu.tscn") as PackedScene
	if packed == null:
		_failures.append("Could not load LocalSongsMenu.tscn.")
		return
	var menu := packed.instantiate()
	root.add_child(menu)
	await process_frame
	if not menu.has_method("_build_song_entry_for_game"):
		_failures.append("LocalSongsMenu script did not load _build_song_entry_for_game.")
		menu.queue_free()
		return
	var launch_entry: Dictionary = menu.call("_build_song_entry_for_game", song, "expert") as Dictionary
	_expect(str(launch_entry.get("display_name", "")) == "Expert Difficulty Title", "Local Songs launch payload should use selected difficulty title.")
	_expect(str(launch_entry.get("artist", "")) == "Professional Artist", "Local Songs launch payload should fall back to Professional artist.")
	_expect(str(launch_entry.get("chart_author", "")) == "Professional Charter", "Local Songs launch payload should fall back to Professional charter.")
	menu.queue_free()


func _check_song_select_launch_payload(song: Dictionary) -> void:
	var packed := load("res://scenes/menus/SongSelectMenu.tscn") as PackedScene
	if packed == null:
		_failures.append("Could not load SongSelectMenu.tscn.")
		return
	var menu := packed.instantiate()
	root.add_child(menu)
	await process_frame
	if not menu.has_method("_song_entry_for_selected_difficulty"):
		_failures.append("SongSelectMenu script did not load _song_entry_for_selected_difficulty.")
		menu.queue_free()
		return
	var launch_entry: Dictionary = menu.call("_song_entry_for_selected_difficulty", song, "Expert") as Dictionary
	_expect(str(launch_entry.get("display_name", "")) == "Expert Difficulty Title", "Song Select launch payload should use selected difficulty title.")
	_expect(str(launch_entry.get("artist", "")) == "Professional Artist", "Song Select launch payload should fall back to Professional artist.")
	_expect(str(launch_entry.get("chart_author", "")) == "Professional Charter", "Song Select launch payload should fall back to Professional charter.")
	menu.queue_free()


func _check_clone_metadata(project: String) -> void:
	var clone_result := SongPackageManager.clone_difficulty(project, "easy", "hard", true)
	_expect(bool(clone_result.get("ok", false)), "Difficulty clone failed: %s" % str(clone_result.get("error", "")))
	var cloned := _read_json(project.path_join("hard.json"))
	_expect(str(cloned.get("title", "")) == "Professional Difficulty Title", "Cloned difficulty should inherit fallback title.")
	_expect(str(cloned.get("artist", "")) == "Professional Artist", "Cloned difficulty should inherit fallback artist.")
	_expect(str(cloned.get("charter", "")) == "Professional Charter", "Cloned difficulty should inherit fallback charter.")


func _create_fixture(project: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(project))
	_write_json(project.path_join("manifest.json"), {
		"song_id": "chart_metadata_resolution_smoke",
		"title": "Manifest Title",
		"artist": "Unknown Artist",
		"charter": "Unknown Charter",
		"bpm": 128.0,
		"offset": 0.0,
		"audio_path": "song.ogg",
		"difficulties": ["easy", "expert", "professional"],
	})
	_write_json(project.path_join("easy.json"), {
		"version": 1,
		"difficulty": "easy",
		"lane_count": 5,
		"bpm": 128.0,
		"notes": [{"time": 1.0, "lane": 0, "type": "tap"}],
	})
	_write_json(project.path_join("expert.json"), {
		"version": 1,
		"title": "Expert Difficulty Title",
		"artist": "",
		"charter": "",
		"difficulty": "expert",
		"lane_count": 5,
		"bpm": 128.0,
		"notes": [{"time": 1.0, "lane": 1, "type": "tap"}],
	})
	_write_json(project.path_join("professional.json"), {
		"version": 1,
		"title": "Professional Difficulty Title",
		"artist": "Professional Artist",
		"charter": "Professional Charter",
		"difficulty": "professional",
		"lane_count": 5,
		"bpm": 128.0,
		"notes": [{"time": 1.0, "lane": 2, "type": "tap"}],
	})
	_write_bytes(project.path_join("song.ogg"), PackedByteArray([79, 103, 103, 83, 1, 2, 3]))


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed as Dictionary if parsed is Dictionary else {}


func _write_json(path: String, payload: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_failures.append("Could not write JSON fixture: %s" % path)
		return
	file.store_string(JSON.stringify(payload, "\t", false))
	file.flush()


func _write_bytes(path: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_failures.append("Could not write byte fixture: %s" % path)
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
