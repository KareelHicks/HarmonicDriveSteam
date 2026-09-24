extends SceneTree

const SongResolver := preload("res://scripts/songs/SongResolver.gd")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var stamp := str(Time.get_unix_time_from_system()) + "_" + str(Time.get_ticks_msec())
	var item_id := "987650103"
	var chart_folder := SongResolver.WORKSHOP_ROOT.path_join(item_id)
	var scratch_root := "user://community_charts_audio_link_smoke_%s" % stamp
	var source_audio := scratch_root.path_join("linked_audio.ogg")
	_cleanup_target(chart_folder)
	_cleanup_target(SongResolver.WORKSHOP_AUDIO_ROOT.path_join(item_id))
	_cleanup_target(scratch_root)
	SongResolver.ensure_user_song_dirs()

	var packed := load("res://scenes/menus/LocalSongsMenu.tscn") as PackedScene
	_expect(packed != null, "Could not load LocalSongsMenu.tscn.")
	if packed == null:
		_finish(chart_folder, item_id, scratch_root)
		return
	var menu := packed.instantiate()
	root.add_child(menu)
	await process_frame
	await process_frame
	_create_chart_pack(chart_folder)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(scratch_root))
	_write_bytes(source_audio, PackedByteArray([79, 103, 103, 83, 1, 2, 3]))
	await process_frame

	var link_button := menu.get_node_or_null("%LinkAudioButton") as Button
	var remove_button := menu.get_node_or_null("%RemoveCommunityChartButton") as Button
	var link_dialog := menu.get_node_or_null("%LinkAudioFileDialog") as FileDialog
	_expect(link_button != null, "Community Charts link audio button is missing.")
	_expect(remove_button != null, "Community Charts remove button is missing.")
	_expect(link_dialog != null, "Community Charts link audio file dialog is missing.")
	if link_button != null:
		_expect(not link_button.visible, "LinkAudioButton should be hidden in the default Local Songs source.")
	if remove_button != null:
		_expect(not remove_button.visible, "RemoveCommunityChartButton should be hidden in the default Local Songs source.")

	menu.call("configure_source", SongResolver.WORKSHOP_ROOT, "workshop", "COMMUNITY CHARTS", "No subscribed Workshop chart packs found.")
	await process_frame
	if link_button != null:
		_expect(link_button.visible, "LinkAudioButton should be visible in Community Charts.")
		_expect(not link_button.disabled, "LinkAudioButton should be enabled when a Community Chart is selected.")
	if remove_button != null:
		_expect(remove_button.visible, "RemoveCommunityChartButton should be visible in Community Charts.")
		_expect(not remove_button.disabled, "RemoveCommunityChartButton should be enabled when a Community Chart is selected.")
	if link_dialog != null:
		_expect(link_dialog.filters.has("*.ogg, *.wav, *.mp3, *.opus, *.m4a, *.webm, *.mp4, *.aac ; Audio files"), "Link audio dialog is missing audio filters.")

	menu.set("_is_exiting", true)
	menu.call("_on_link_audio_file_selected", source_audio)
	await process_frame
	var manifest := _read_json(chart_folder.path_join("manifest.json"))
	var audio_path := str(manifest.get("audio_path", ""))
	_expect(not audio_path.is_empty(), "Community Chart link audio did not write manifest audio_path.")
	_expect(audio_path.begins_with(SongResolver.WORKSHOP_AUDIO_ROOT.path_join(item_id)), "Community Chart linked audio should be stored in the persistent workshop audio folder.")
	_expect(FileAccess.file_exists(audio_path), "Community Chart linked audio file was not created.")
	menu.call("_on_remove_community_chart_confirmed")
	await process_frame
	_expect(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(chart_folder)), "Remove Community Chart did not delete cached chart folder.")
	_expect(FileAccess.file_exists(audio_path), "Remove Community Chart should preserve linked audio cache.")

	menu.queue_free()
	_finish(chart_folder, item_id, scratch_root)


func _finish(chart_folder: String, item_id: String, scratch_root: String) -> void:
	_cleanup_target(chart_folder)
	_cleanup_target(SongResolver.WORKSHOP_AUDIO_ROOT.path_join(item_id))
	_cleanup_target(scratch_root)
	if _failures.is_empty():
		print("Community Charts audio link smoke test passed.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _create_chart_pack(folder: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	_write_json(folder.path_join("manifest.json"), {
		"song_id": "community_audio_link_chart",
		"title": "Community Audio Link Chart",
		"artist": "Automated Test",
		"charter": "Automated Test",
		"bpm": 128.0,
		"offset": 0.0,
		"youtube_url": "",
		"difficulties": ["expert"],
	})
	_write_json(folder.path_join("expert.json"), {
		"version": 1,
		"difficulty": "expert",
		"lane_count": 5,
		"bpm": 128.0,
		"notes": [{"time": 1.0, "lane": 0, "type": "tap"}],
	})


func _write_json(path: String, payload: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_failures.append("Could not write JSON fixture: %s" % path)
		return
	file.store_string(JSON.stringify(payload, "\t", false))
	file.flush()
	file.close()


func _write_bytes(path: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_failures.append("Could not write byte fixture: %s" % path)
		return
	file.store_buffer(bytes)
	file.flush()
	file.close()


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return (parsed as Dictionary) if parsed is Dictionary else {}


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


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
