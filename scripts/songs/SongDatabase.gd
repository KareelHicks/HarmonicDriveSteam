extends RefCounted
class_name SongDatabase

const SongResolver := preload("res://scripts/songs/SongResolver.gd")
const ChartValidator := preload("res://scripts/songs/ChartValidator.gd")
const ChartLoader := preload("res://scripts/gameplay/ChartLoader.gd")
const ChartMetadataResolver := preload("res://scripts/songs/ChartMetadataResolver.gd")

var _songs: Array[Dictionary] = []
var _songs_by_id := {}
var _load_errors: Array[Dictionary] = []
var _load_warnings: Array[Dictionary] = []


func reload() -> void:
	SongResolver.ensure_user_song_dirs()
	_songs.clear()
	_songs_by_id.clear()
	_load_errors.clear()
	_load_warnings.clear()

	for root in SongResolver.list_all_song_roots():
		for folder in SongResolver.list_song_folders(root):
			_load_song_folder(folder, root)

	_songs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("title", "")) < str(b.get("title", ""))
	)


func get_songs() -> Array[Dictionary]:
	return _songs.duplicate(true)


func get_song(song_id: String) -> Dictionary:
	return (_songs_by_id.get(song_id, {}) as Dictionary).duplicate(true)


func get_load_errors() -> Array[Dictionary]:
	return _load_errors.duplicate(true)


func get_load_warnings() -> Array[Dictionary]:
	return _load_warnings.duplicate(true)


func _load_song_folder(song_folder: String, root: String) -> void:
	var manifest_path: String = SongResolver.get_manifest_path(song_folder)
	var manifest_load := ChartLoader.load_json_dictionary(manifest_path)
	if not manifest_load.get("ok", false):
		_load_errors.append({
			"code": "manifest_parse_error",
			"message": str(manifest_load.get("error", "Failed to parse manifest")),
			"path": manifest_path,
		})
		return

	var manifest: Dictionary = manifest_load.get("value", {}) as Dictionary
	var validation := ChartValidator.validate_manifest(manifest)
	for err in (validation.get("errors", []) as Array):
		_load_errors.append(_decorate_issue(err as Dictionary, manifest_path))
	for warn in (validation.get("warnings", []) as Array):
		_load_warnings.append(_decorate_issue(warn as Dictionary, manifest_path))

	if not ChartValidator.is_valid(validation):
		return

	var song_id: String = str(manifest.get("song_id", "")).strip_edges()
	if song_id.is_empty():
		return

	var source: String = "official" if root == SongResolver.OFFICIAL_ROOT else ("workshop" if root == SongResolver.WORKSHOP_ROOT else "custom")

	var declared_diffs: Array[String] = []
	for diff_var in (manifest.get("difficulties", []) as Array):
		if typeof(diff_var) == TYPE_STRING:
			var diff: String = String(diff_var).strip_edges().to_lower()
			if not diff.is_empty() and not declared_diffs.has(diff):
				declared_diffs.append(diff)

	var chart_paths := {}
	for diff in declared_diffs:
		var chart_path: String = SongResolver.get_chart_path(song_folder, diff)
		chart_paths[diff] = chart_path
		if not FileAccess.file_exists(chart_path):
			_load_warnings.append({
				"code": "missing_chart_file",
				"message": "Declared difficulty '%s' is missing chart file %s" % [diff, chart_path],
				"path": chart_path,
			})

	var metadata := ChartMetadataResolver.metadata_for_song_folder(song_folder, manifest, "professional", {"chart_paths": chart_paths})
	var entry := {
		"song_id": song_id,
		"title": str(metadata.get("title", manifest.get("title", ""))),
		"artist": str(metadata.get("artist", manifest.get("artist", ""))),
		"charter": str(metadata.get("charter", manifest.get("charter", ""))),
		"bpm": float(metadata.get("bpm", manifest.get("bpm", 0.0))),
		"offset": float(manifest.get("offset", 0.0)),
		"youtube_url": str(manifest.get("youtube_url", "")),
		"difficulties": declared_diffs.duplicate(),
		"source": source,
		"root_path": song_folder,
		"manifest_path": manifest_path,
		"chart_paths": chart_paths,
		"metadata_source_difficulty": str(metadata.get("metadata_source_difficulty", "")),
		"assets": {
			"preview_png": SongResolver.get_asset_path(song_folder, "preview.png"),
			"background_jpg": SongResolver.get_asset_path(song_folder, "background.jpg"),
			"video_mp4": SongResolver.get_asset_path(song_folder, "video.mp4"),
		},
	}

	if _songs_by_id.has(song_id):
		_load_warnings.append({
			"code": "duplicate_song_id",
			"message": "Duplicate song_id '%s' found in %s (keeping first occurrence)" % [song_id, manifest_path],
			"path": manifest_path,
		})
		return

	_songs_by_id[song_id] = entry
	_songs.append(entry)


func _decorate_issue(issue: Dictionary, file_path: String) -> Dictionary:
	var out := issue.duplicate(true)
	out["path"] = "%s%s" % [file_path, str(issue.get("path", ""))]
	return out
