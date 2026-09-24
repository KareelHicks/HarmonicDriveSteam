extends SceneTree

const WorkshopSubscriptionSync := preload("res://scripts/workshop/WorkshopSubscriptionSync.gd")
const WorkshopChartAudioLink := preload("res://scripts/workshop/WorkshopChartAudioLink.gd")
const HarmonicProjectPackage := preload("res://scripts/editor/HarmonicProjectPackage.gd")
const SongDatabase := preload("res://scripts/songs/SongDatabase.gd")
const SongResolver := preload("res://scripts/songs/SongResolver.gd")
const EMSPackLoader := preload("res://systems/ems/EMSPackLoader.gd")
const EMSValidator := preload("res://systems/ems/EMSValidator.gd")

var _failures: Array[String] = []


func _init() -> void:
	var stamp := str(Time.get_unix_time_from_system()) + "_" + str(Time.get_ticks_msec())
	var root := "user://workshop_subscription_sync_smoke_%s" % stamp
	var chart_source := root.path_join("chart_source")
	var ems_source := root.path_join("ems_source")
	var nested_chart_source := root.path_join("nested_chart_source")
	var nested_ems_source := root.path_join("nested_ems_source")
	var scratch_workshop_root := root.path_join("scratch_workshop_root")
	var chart_item_id := "987650001"
	var ems_item_id := "987650002"
	var nested_chart_item_id := "987650003"
	var nested_ems_item_id := "987650004"
	var invalid_nonempty_item_id := "987650005"
	var stale_chart_item_id := "987650009"
	var stale_ems_item_id := "987650010"
	_cleanup_target(SongResolver.WORKSHOP_ROOT.path_join(chart_item_id))
	_cleanup_target(SongResolver.WORKSHOP_AUDIO_ROOT.path_join(chart_item_id))
	_cleanup_target(EMSPackLoader.WORKSHOP_ROOT.path_join(ems_item_id))
	_cleanup_target(SongResolver.WORKSHOP_ROOT.path_join(nested_chart_item_id))
	_cleanup_target(SongResolver.WORKSHOP_AUDIO_ROOT.path_join(nested_chart_item_id))
	_cleanup_target(EMSPackLoader.WORKSHOP_ROOT.path_join(nested_ems_item_id))
	_create_chart_pack(chart_source)
	_create_ems_pack(ems_source)
	_create_chart_pack(nested_chart_source.path_join("payload").path_join("chart_pack"))
	_create_ems_pack(nested_ems_source.path_join("payload").path_join("ems_pack"))

	var chart_sync := WorkshopSubscriptionSync.sync_installed_item(chart_item_id, chart_source, false)
	_expect(bool(chart_sync.get("ok", false)), "Workshop chart sync failed: %s" % str(chart_sync.get("message", "")))
	_expect(str(chart_sync.get("type", "")) == "chart", "Workshop chart sync should return type=chart.")
	var chart_target := SongResolver.WORKSHOP_ROOT.path_join(chart_item_id)
	_expect(FileAccess.file_exists(chart_target.path_join("manifest.json")), "Workshop chart manifest was not copied.")
	_expect(FileAccess.file_exists(chart_target.path_join("expert.json")), "Workshop chart JSON was not copied.")
	var db := SongDatabase.new()
	db.reload()
	var synced_song := db.get_song("workshop_sync_chart")
	_expect(not synced_song.is_empty(), "Synced Workshop chart did not appear in SongDatabase.")
	_expect(str(synced_song.get("source", "")) == "workshop", "Synced Workshop chart source should be workshop.")
	var invalid_chart_source := root.path_join("invalid_chart_source")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(invalid_chart_source))
	var invalid_sync := WorkshopSubscriptionSync._sync_chart_item(chart_item_id, invalid_chart_source, false)
	_expect(not bool(invalid_sync.get("ok", false)), "Invalid Workshop chart source should fail sync.")
	_expect(FileAccess.file_exists(chart_target.path_join("manifest.json")), "Invalid Workshop chart source should not clear the existing cached chart.")
	var generated_audio_path := chart_target.path_join("song.ogg")
	_write_bytes(generated_audio_path, PackedByteArray([79, 103, 103, 83, 1, 2, 3, 4]))
	HarmonicProjectPackage.set_manifest_audio_path(chart_target, "song.ogg")
	var cached_audio_resync := WorkshopSubscriptionSync.sync_installed_item(chart_item_id, chart_source, true)
	_expect(bool(cached_audio_resync.get("ok", false)), "Workshop chart cached-audio resync failed: %s" % str(cached_audio_resync.get("message", "")))
	_expect(str(cached_audio_resync.get("audio_status", "")) == "cached", "Workshop chart cached-audio resync should not redownload YouTube audio.")
	_expect(FileAccess.file_exists(generated_audio_path), "Workshop chart cached-audio resync did not preserve existing song.ogg.")
	var audio_source := root.path_join("linked_audio.ogg")
	_write_bytes(audio_source, PackedByteArray([79, 103, 103, 83, 1, 2, 3]))
	var audio_link := WorkshopChartAudioLink.link_audio_file(chart_item_id, chart_target, audio_source)
	_expect(bool(audio_link.get("ok", false)), "Workshop chart audio link failed: %s" % str(audio_link.get("error", "")))
	var linked_audio_path := str(audio_link.get("audio_path", ""))
	_expect(FileAccess.file_exists(linked_audio_path), "Workshop chart linked audio file was not saved.")
	var resync := WorkshopSubscriptionSync.sync_installed_item(chart_item_id, chart_source, false)
	_expect(bool(resync.get("ok", false)), "Workshop chart resync after audio link failed: %s" % str(resync.get("message", "")))
	var resynced_manifest := _read_json(chart_target.path_join("manifest.json"))
	_expect(str(resynced_manifest.get("audio_path", "")) == linked_audio_path, "Workshop chart resync did not preserve linked audio_path.")
	var nested_chart_sync := WorkshopSubscriptionSync.sync_installed_item(nested_chart_item_id, nested_chart_source, false)
	_expect(bool(nested_chart_sync.get("ok", false)), "Nested Workshop chart sync failed: %s" % str(nested_chart_sync.get("message", "")))
	_expect(str(nested_chart_sync.get("type", "")) == "chart", "Nested Workshop chart sync should return type=chart.")
	var nested_chart_target := SongResolver.WORKSHOP_ROOT.path_join(nested_chart_item_id)
	_expect(FileAccess.file_exists(nested_chart_target.path_join("manifest.json")), "Nested Workshop chart manifest was not copied.")

	_create_chart_pack(scratch_workshop_root.path_join(chart_item_id))
	_create_chart_pack(scratch_workshop_root.path_join(stale_chart_item_id))
	var prune_result := WorkshopSubscriptionSync.prune_unsubscribed_chart_items([chart_item_id], scratch_workshop_root)
	_expect(bool(prune_result.get("ok", false)), "Workshop stale chart prune failed.")
	_expect(FileAccess.file_exists(scratch_workshop_root.path_join(chart_item_id).path_join("manifest.json")), "Workshop stale chart prune removed a still-subscribed chart.")
	_expect(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(scratch_workshop_root.path_join(stale_chart_item_id))), "Workshop stale chart prune did not remove unsubscribed chart folder.")
	var manual_remove := WorkshopSubscriptionSync.remove_chart_item(chart_item_id, scratch_workshop_root)
	_expect(bool(manual_remove.get("ok", false)), "Workshop manual chart remove failed: %s" % str(manual_remove.get("message", "")))
	_expect(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(scratch_workshop_root.path_join(chart_item_id))), "Workshop manual chart remove did not delete chart folder.")

	var scratch_ems_root := root.path_join("scratch_ems_workshop_root")
	_create_ems_pack(scratch_ems_root.path_join(ems_item_id))
	_create_ems_pack(scratch_ems_root.path_join(stale_ems_item_id))
	var ems_prune_result := WorkshopSubscriptionSync.prune_unsubscribed_ems_items([ems_item_id], scratch_ems_root)
	_expect(bool(ems_prune_result.get("ok", false)), "Workshop stale EMS prune failed.")
	_expect(FileAccess.file_exists(scratch_ems_root.path_join(ems_item_id).path_join(EMSValidator.MANIFEST_FILE)), "Workshop stale EMS prune removed a still-subscribed EMS pack.")
	_expect(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(scratch_ems_root.path_join(stale_ems_item_id))), "Workshop stale EMS prune did not remove unsubscribed EMS pack.")

	var ems_sync := WorkshopSubscriptionSync.sync_installed_item(ems_item_id, ems_source, false)
	_expect(bool(ems_sync.get("ok", false)), "Workshop EMS sync failed: %s" % str(ems_sync.get("message", "")))
	_expect(str(ems_sync.get("type", "")) == "ems", "Workshop EMS sync should return type=ems.")
	var ems_target := EMSPackLoader.WORKSHOP_ROOT.path_join(ems_item_id)
	_expect(FileAccess.file_exists(ems_target.path_join(EMSValidator.MANIFEST_FILE)), "Workshop EMS manifest was not copied.")
	_expect(FileAccess.file_exists(ems_target.path_join(EMSValidator.CONFIG_FILE)), "Workshop EMS config was not copied.")
	var nested_ems_sync := WorkshopSubscriptionSync.sync_installed_item(nested_ems_item_id, nested_ems_source, false)
	_expect(bool(nested_ems_sync.get("ok", false)), "Nested Workshop EMS sync failed: %s" % str(nested_ems_sync.get("message", "")))
	_expect(str(nested_ems_sync.get("type", "")) == "ems", "Nested Workshop EMS sync should return type=ems.")
	var nested_ems_target := EMSPackLoader.WORKSHOP_ROOT.path_join(nested_ems_item_id)
	_expect(FileAccess.file_exists(nested_ems_target.path_join(EMSValidator.MANIFEST_FILE)), "Nested Workshop EMS manifest was not copied.")
	var invalid_nonempty_source := root.path_join("invalid_nonempty_source")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(invalid_nonempty_source))
	_write_bytes(invalid_nonempty_source.path_join("placeholder.txt"), PackedByteArray([1, 2, 3]))
	var invalid_nonempty_sync := WorkshopSubscriptionSync.sync_installed_item(invalid_nonempty_item_id, invalid_nonempty_source, false)
	_expect(not bool(invalid_nonempty_sync.get("ok", false)), "Invalid non-empty Workshop folder should fail validation.")
	_expect(bool(invalid_nonempty_sync.get("source_has_files", false)), "Invalid non-empty Workshop folder should report source_has_files=true.")
	_expect(not bool(invalid_nonempty_sync.get("retryable_download", true)), "Invalid non-empty Workshop folder should not be marked retryable.")

	_cleanup_target(chart_target)
	_cleanup_target(SongResolver.WORKSHOP_AUDIO_ROOT.path_join(chart_item_id))
	_cleanup_target(ems_target)
	_cleanup_target(nested_chart_target)
	_cleanup_target(SongResolver.WORKSHOP_AUDIO_ROOT.path_join(nested_chart_item_id))
	_cleanup_target(nested_ems_target)
	_cleanup_target(scratch_workshop_root)
	_cleanup_target(scratch_ems_root)
	_cleanup_target(root)
	if _failures.is_empty():
		print("Workshop subscription sync smoke test passed.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _create_chart_pack(folder: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	_write_json(folder.path_join("manifest.json"), {
		"song_id": "workshop_sync_chart",
		"title": "Workshop Sync Chart",
		"artist": "Automated Test",
		"charter": "Automated Test",
		"bpm": 128.0,
		"offset": 0.0,
		"youtube_url": "https://www.youtube.com/watch?v=jNQXAC9IVRw",
		"difficulties": ["expert"],
	})
	_write_json(folder.path_join("expert.json"), {
		"version": 1,
		"difficulty": "expert",
		"lane_count": 5,
		"bpm": 128.0,
		"notes": [{"time": 1.0, "lane": 0, "type": "tap"}],
	})


func _create_ems_pack(folder: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	_write_json(folder.path_join(EMSValidator.MANIFEST_FILE), {
		"schema_version": 1,
		"pack_type": EMSValidator.PACK_TYPE_CONFIG,
		"pack_id": "workshop_sync_ems",
		"title": "Workshop Sync EMS",
		"author": "Automated Test",
		"description": "Temporary Workshop sync smoke pack.",
		"min_game_version": "1.0.0",
		"tags": ["EMS", "Test"],
	})
	_write_json(folder.path_join(EMSValidator.CONFIG_FILE), {
		"schema_version": 1,
		"pack_type": EMSValidator.PACK_TYPE_CONFIG,
		"pack_id": "workshop_sync_ems",
		"title": "Workshop Sync EMS",
		"author": "Automated Test",
		"description": "Temporary Workshop sync smoke pack.",
		"layers": [{"id": "solid", "type": "solid_color", "name": "Solid", "opacity": 0.4, "color": "#55DFFFFF", "colors": ["#55DFFFFF"], "particle_count": 0}],
		"events": [],
		"palette": {"colors": ["#55DFFFFF"], "morph": "smooth", "speed": 0.2},
		"performance": {"motion_intensity": 0.2, "particle_intensity": 0.0, "audio_reactive": false, "estimated_cost": 0.1},
	})
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.2, 0.9, 1.0, 1.0))
	image.save_png(folder.path_join(EMSValidator.PREVIEW_FILE))
	image.save_png(folder.path_join(EMSValidator.STEAM_PREVIEW_FILE))


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
