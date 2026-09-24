extends RefCounted
class_name ChartMetadataResolver

const ChartLoader := preload("res://scripts/gameplay/ChartLoader.gd")
const DifficultyManager := preload("res://scripts/editor/DifficultyManager.gd")
const LaneCountResolver := preload("res://scripts/songs/LaneCountResolver.gd")
const SongResolver := preload("res://scripts/songs/SongResolver.gd")

const UNKNOWN_ARTIST := "Unknown Artist"
const UNKNOWN_CHARTER := "Unknown Charter"
const UNTITLED_CHART := "Untitled Chart"
const METADATA_KEYS: Array[String] = ["title", "artist", "charter"]
const PREFERRED_FALLBACK_IDS: Array[String] = ["professional", "expert", "hard", "medium", "easy"]


static func metadata_for_song_entry(song: Dictionary, difficulty: String = "") -> Dictionary:
	var song_folder := str(song.get("root_path", "")).strip_edges()
	if not song_folder.is_empty():
		var manifest := read_manifest(song_folder, str(song.get("manifest_path", "")))
		return metadata_for_song_folder(song_folder, manifest, difficulty, song)
	return metadata_for_chart_paths(_chart_paths_from_song_entry(song), song, difficulty)


static func metadata_for_song_folder(song_folder: String, manifest: Dictionary = {}, difficulty: String = "", song: Dictionary = {}) -> Dictionary:
	var resolved_manifest := manifest.duplicate(true)
	if resolved_manifest.is_empty():
		resolved_manifest = read_manifest(song_folder)
	var chart_paths := _chart_paths_from_song_entry(song)
	var snapshots := _chart_snapshots(song_folder, resolved_manifest, chart_paths, difficulty)
	return _metadata_from_snapshots(snapshots, resolved_manifest, song, song_folder)


static func metadata_for_chart_paths(chart_paths: Dictionary, base_metadata: Dictionary = {}, difficulty: String = "") -> Dictionary:
	var snapshots: Array[Dictionary] = []
	for difficulty_id in difficulty_fallback_order(difficulty):
		var chart_path := _path_from_chart_paths(chart_paths, difficulty_id)
		if chart_path.is_empty() or not FileAccess.file_exists(chart_path):
			continue
		var loaded: Dictionary = ChartLoader.load_json_dictionary(chart_path)
		if bool(loaded.get("ok", false)):
			snapshots.append({
				"difficulty": difficulty_id,
				"path": chart_path,
				"chart": loaded.get("value", {}) as Dictionary,
			})
	return _metadata_from_snapshots(snapshots, base_metadata, base_metadata, "")


static func read_manifest(song_folder: String, manifest_path: String = "") -> Dictionary:
	var path := manifest_path.strip_edges()
	if path.is_empty():
		path = SongResolver.get_manifest_path(song_folder)
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var loaded: Dictionary = ChartLoader.load_json_dictionary(path)
	if bool(loaded.get("ok", false)):
		return loaded.get("value", {}) as Dictionary
	return {}


static func normalize_difficulty_id(difficulty: String) -> String:
	var cleaned := difficulty.strip_edges()
	if cleaned.is_empty():
		return ""
	var from_display := DifficultyManager.id_from_display(cleaned)
	if DifficultyManager.is_valid_id(from_display):
		return from_display
	var lower := cleaned.to_lower()
	return lower if DifficultyManager.is_valid_id(lower) else ""


static func difficulty_fallback_order(current_difficulty: String = "") -> Array[String]:
	var order: Array[String] = []
	var current := normalize_difficulty_id(current_difficulty)
	if not current.is_empty():
		order.append(current)
	for difficulty_id in PREFERRED_FALLBACK_IDS:
		if not order.has(difficulty_id):
			order.append(difficulty_id)
	for difficulty_id in DifficultyManager.all_ids():
		if not order.has(difficulty_id):
			order.append(difficulty_id)
	return order


static func has_metadata_value(key: String, value: Variant) -> bool:
	var cleaned := str(value).strip_edges()
	if cleaned.is_empty():
		return false
	var lower := cleaned.to_lower()
	if lower == "unknown" or lower == "n/a" or lower == "na" or lower == "-":
		return false
	match key:
		"artist":
			return lower != UNKNOWN_ARTIST.to_lower()
		"charter":
			return lower != UNKNOWN_CHARTER.to_lower()
		"title":
			return lower != UNTITLED_CHART.to_lower() and lower != "untitled"
	return true


static func apply_metadata_to_song_entry(song: Dictionary, metadata: Dictionary) -> Dictionary:
	var entry := song.duplicate(true)
	var title := str(metadata.get("title", "")).strip_edges()
	if not title.is_empty():
		entry["title"] = title
		entry["display_name"] = title
	var artist := str(metadata.get("artist", "")).strip_edges()
	if not artist.is_empty():
		entry["artist"] = artist
	var charter := str(metadata.get("charter", "")).strip_edges()
	if not charter.is_empty():
		entry["charter"] = charter
		entry["chart_author"] = charter
	if metadata.has("bpm"):
		entry["bpm"] = float(metadata.get("bpm", 0.0))
	if metadata.has("lane_count"):
		entry["lane_count"] = int(metadata.get("lane_count", LaneCountResolver.DEFAULT_LANES))
	if metadata.has("nps"):
		entry["nps"] = float(metadata.get("nps", 0.0))
	if metadata.has("metadata_source_difficulty"):
		entry["metadata_source_difficulty"] = str(metadata.get("metadata_source_difficulty", ""))
	return entry


static func apply_metadata_to_chart(chart: Dictionary, metadata: Dictionary, overwrite: bool = true) -> Dictionary:
	var payload := chart.duplicate(true)
	for key in METADATA_KEYS:
		if not overwrite and has_metadata_value(key, payload.get(key, "")):
			continue
		var value := str(metadata.get(key, "")).strip_edges()
		if key == "title":
			if not value.is_empty():
				payload[key] = value
		elif has_metadata_value(key, value):
			payload[key] = value
	payload["difficulty"] = str(payload.get("difficulty", metadata.get("difficulty", ""))).strip_edges().to_lower()
	return payload


static func _chart_snapshots(song_folder: String, manifest: Dictionary, chart_paths: Dictionary, difficulty: String) -> Array[Dictionary]:
	var snapshots: Array[Dictionary] = []
	for difficulty_id in difficulty_fallback_order(difficulty):
		var chart_path := _chart_path_for_difficulty(song_folder, manifest, chart_paths, difficulty_id)
		if chart_path.is_empty() or not FileAccess.file_exists(chart_path):
			continue
		var loaded: Dictionary = ChartLoader.load_json_dictionary(chart_path)
		if bool(loaded.get("ok", false)):
			snapshots.append({
				"difficulty": difficulty_id,
				"path": chart_path,
				"chart": loaded.get("value", {}) as Dictionary,
			})
	return snapshots


static func _metadata_from_snapshots(snapshots: Array[Dictionary], manifest: Dictionary, song: Dictionary, song_folder: String) -> Dictionary:
	var fallback_title := _fallback_title(manifest, song, song_folder)
	var result := {
		"title": _first_chart_value("title", snapshots, _first_base_value("title", song, manifest, fallback_title)),
		"artist": _first_chart_value("artist", snapshots, _first_base_value("artist", song, manifest, UNKNOWN_ARTIST)),
		"charter": _first_chart_value("charter", snapshots, _first_base_value("charter", song, manifest, UNKNOWN_CHARTER)),
		"difficulty": _first_snapshot_difficulty(snapshots, str(song.get("difficulty", manifest.get("difficulty", "")))),
		"lane_count": LaneCountResolver.DEFAULT_LANES,
		"bpm": 0.0,
		"nps": 0.0,
		"metadata_source_difficulty": _first_metadata_source_difficulty(snapshots),
	}
	result["lane_count"] = _resolved_lane_count(snapshots, manifest, song)
	result["bpm"] = _resolved_number("bpm", snapshots, manifest, song, 0.0)
	result["nps"] = _resolved_number("nps", snapshots, manifest, song, 0.0)
	return result


static func _first_chart_value(key: String, snapshots: Array[Dictionary], fallback: String) -> String:
	for snapshot in snapshots:
		var chart: Dictionary = snapshot.get("chart", {}) as Dictionary
		var value: Variant = chart.get(key, "")
		if has_metadata_value(key, value):
			return str(value).strip_edges()
	return fallback


static func _first_base_value(key: String, song: Dictionary, manifest: Dictionary, fallback: String) -> String:
	var candidates: Array[Variant] = []
	if key == "title":
		candidates.append(song.get("display_name", ""))
	candidates.append(song.get(key, ""))
	if key == "charter":
		candidates.append(song.get("chart_author", ""))
	if key == "title":
		candidates.append(manifest.get("display_name", ""))
	candidates.append(manifest.get(key, ""))
	for value in candidates:
		if has_metadata_value(key, value):
			return str(value).strip_edges()
	return fallback


static func _fallback_title(manifest: Dictionary, song: Dictionary, song_folder: String) -> String:
	for key in ["display_name", "title"]:
		var song_value: Variant = song.get(key, "")
		if has_metadata_value("title", song_value):
			return str(song_value).strip_edges()
		var manifest_value: Variant = manifest.get(key, "")
		if has_metadata_value("title", manifest_value):
			return str(manifest_value).strip_edges()
	var from_folder := song_folder.get_file().replace("_", " ").strip_edges() if not song_folder.is_empty() else ""
	return from_folder if not from_folder.is_empty() else UNTITLED_CHART


static func _first_snapshot_difficulty(snapshots: Array[Dictionary], fallback: String) -> String:
	if not snapshots.is_empty():
		return str(snapshots[0].get("difficulty", fallback)).strip_edges().to_lower()
	var normalized := normalize_difficulty_id(fallback)
	return normalized


static func _first_metadata_source_difficulty(snapshots: Array[Dictionary]) -> String:
	for key in METADATA_KEYS:
		for snapshot in snapshots:
			var chart: Dictionary = snapshot.get("chart", {}) as Dictionary
			if has_metadata_value(key, chart.get(key, "")):
				return str(snapshot.get("difficulty", "")).strip_edges().to_lower()
	return ""


static func _resolved_lane_count(snapshots: Array[Dictionary], manifest: Dictionary, song: Dictionary) -> int:
	for snapshot in snapshots:
		var chart: Dictionary = snapshot.get("chart", {}) as Dictionary
		if not chart.is_empty():
			return LaneCountResolver.resolve_chart_lane_count(chart, manifest)
	var song_count := int(song.get("lane_count", 0))
	if song_count > 0:
		return LaneCountResolver.clamp_lane_count(song_count)
	var manifest_count := int(manifest.get("lane_count", 0))
	if manifest_count > 0:
		return LaneCountResolver.clamp_lane_count(manifest_count)
	return LaneCountResolver.DEFAULT_LANES


static func _resolved_number(key: String, snapshots: Array[Dictionary], manifest: Dictionary, song: Dictionary, fallback: float) -> float:
	for snapshot in snapshots:
		var chart: Dictionary = snapshot.get("chart", {}) as Dictionary
		if chart.has(key):
			var value := float(chart.get(key, fallback))
			if value > 0.0:
				return value
	var song_value := float(song.get(key, fallback))
	if song_value > 0.0:
		return song_value
	var manifest_value := float(manifest.get(key, fallback))
	if manifest_value > 0.0:
		return manifest_value
	return fallback


static func _chart_path_for_difficulty(song_folder: String, manifest: Dictionary, chart_paths: Dictionary, difficulty_id: String) -> String:
	var direct := _path_from_chart_paths(chart_paths, difficulty_id)
	if not direct.is_empty():
		return direct
	var chart_files: Dictionary = manifest.get("chart_files", {}) as Dictionary
	var filename := str(chart_files.get(difficulty_id, "")).strip_edges()
	if not filename.is_empty() and not filename.contains("/") and not filename.contains("\\") and not filename.contains(".."):
		return song_folder.path_join(filename.get_file())
	if song_folder.is_empty():
		return ""
	return SongResolver.get_chart_path(song_folder, difficulty_id)


static func _path_from_chart_paths(chart_paths: Dictionary, difficulty_id: String) -> String:
	if chart_paths.has(difficulty_id):
		return str(chart_paths.get(difficulty_id, "")).strip_edges()
	var display := DifficultyManager.display_name(difficulty_id)
	if chart_paths.has(display):
		return str(chart_paths.get(display, "")).strip_edges()
	for key in chart_paths.keys():
		if normalize_difficulty_id(str(key)) == difficulty_id:
			return str(chart_paths.get(key, "")).strip_edges()
	return ""


static func _chart_paths_from_song_entry(song: Dictionary) -> Dictionary:
	var paths := {}
	var declared: Dictionary = song.get("chart_paths", {}) as Dictionary
	for key in declared.keys():
		var difficulty_id := normalize_difficulty_id(str(key))
		if difficulty_id.is_empty():
			continue
		paths[difficulty_id] = str(declared.get(key, "")).strip_edges()
	var modes: Dictionary = song.get("modes", {}) as Dictionary
	for mode_payload_variant in modes.values():
		if mode_payload_variant is not Dictionary:
			continue
		var mode_payload := mode_payload_variant as Dictionary
		var charts: Dictionary = mode_payload.get("charts", {}) as Dictionary
		for key in charts.keys():
			var difficulty_id := normalize_difficulty_id(str(key))
			if difficulty_id.is_empty() or paths.has(difficulty_id):
				continue
			paths[difficulty_id] = str(charts.get(key, "")).strip_edges()
	return paths
