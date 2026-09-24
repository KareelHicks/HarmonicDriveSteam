extends RefCounted
class_name ChartImportService

const Utils := preload("res://scripts/editor/importers/ChartImportUtils.gd")
const LaneCountResolver := preload("res://scripts/songs/LaneCountResolver.gd")
const ChartImporter := preload("res://scripts/editor/importers/ChartImporter.gd")
const MidiImporter := preload("res://scripts/editor/importers/MidiChartImporter.gd")
const HdJsonImporter := preload("res://scripts/editor/importers/HdJsonImporter.gd")
const OsuManiaImporter := preload("res://scripts/editor/importers/OsuManiaImporter.gd")
const OszImporter := preload("res://scripts/editor/importers/OszImporter.gd")
const SngImporter := preload("res://scripts/editor/importers/SngImporter.gd")
const AudioImporter := preload("res://scripts/editor/importers/EditorAudioImporter.gd")


static func inspect_import(path: String, project_folder: String) -> Dictionary:
	var ext := path.get_extension().to_lower()
	if ext == "osz" or ext == "osk":
		return OszImporter.inspect_file(path, "")
	if ext == "osu":
		return OsuManiaImporter.inspect_file(path)
	if ext == "chart":
		return ChartImporter.inspect_file(path)
	if ext == "mid" or ext == "midi":
		return MidiImporter.inspect_file(path)
	if ext == "json":
		return HdJsonImporter.inspect_file(path)
	if ext == "sng":
		return SngImporter.inspect_file(path, "")
	return {"ok": false, "error": "Unsupported chart import extension: .%s" % ext, "entries": [], "metadata": {}}


static func preview_import(import_path: String, inspect_result: Dictionary, import_options: Dictionary = {}, waveform: Variant = null) -> Dictionary:
	var ext := import_path.get_extension().to_lower()
	if ext == "mid" or ext == "midi":
		return MidiImporter.convert_inspect_result(inspect_result, import_options, waveform)
	return inspect_result


static func apply_import(project_folder: String, import_path: String, inspect_result: Dictionary, entry_index: int, target_difficulty: String, import_options: Dictionary = {}, waveform: Variant = null) -> Dictionary:
	var active_result := preview_import(import_path, inspect_result, import_options, waveform)
	if not bool(active_result.get("ok", false)):
		return active_result
	var entries: Array = active_result.get("entries", []) as Array
	if entry_index < 0 or entry_index >= entries.size():
		return {"ok": false, "error": "Invalid import selection."}
	var entry: Dictionary = entries[entry_index] as Dictionary
	var metadata: Dictionary = active_result.get("metadata", {}) as Dictionary
	var target_chart := project_folder.path_join("%s.json" % target_difficulty)
	var source_notes: Array[Dictionary] = []
	for note in (entry.get("notes", []) as Array):
		if note is Dictionary:
			source_notes.append(note as Dictionary)
	var lane_count := int(entry.get("lane_count", LaneCountResolver.infer_from_notes(source_notes, LaneCountResolver.DEFAULT_LANES)))
	var chart_metadata := metadata.duplicate(true)
	chart_metadata["nps"] = _calculate_nps(source_notes)
	var payload: Dictionary = Utils.chart_payload(target_difficulty, source_notes, lane_count, chart_metadata)
	var chart_write: Dictionary = Utils.write_json(target_chart, payload)
	if not bool(chart_write.get("ok", false)):
		return chart_write

	var source_copy: Dictionary = Utils.copy_file_to_project(import_path, project_folder)
	if not bool(source_copy.get("ok", false)):
		return source_copy

	var manifest_result: Dictionary = update_manifest(project_folder, metadata, target_difficulty)
	if not bool(manifest_result.get("ok", false)):
		return manifest_result

	return {"ok": true, "error": "", "chart_path": target_chart, "manifest_path": str(manifest_result.get("path", ""))}


static func _calculate_nps(notes: Array[Dictionary]) -> float:
	var duration := 0.0
	for note in notes:
		duration = maxf(duration, float(note.get("time", 0.0)) + float(note.get("length", note.get("duration", 0.0))))
	if duration <= 0.0:
		return 0.0
	return float(notes.size()) / duration


static func update_manifest(project_folder: String, metadata: Dictionary, difficulty: String) -> Dictionary:
	var manifest_path := project_folder.path_join("manifest.json")
	var manifest: Dictionary = {}
	if FileAccess.file_exists(manifest_path):
		var parsed: Variant = JSON.parse_string(FileAccess.open(manifest_path, FileAccess.READ).get_as_text())
		if parsed is Dictionary:
			manifest = parsed as Dictionary

	var title: String = Utils.strip_rich_text(str(metadata.get("title", manifest.get("title", project_folder.get_file()))))
	var song_id: String = Utils.sanitize_id(str(manifest.get("song_id", title)))
	manifest["song_id"] = song_id
	manifest["title"] = title
	manifest["artist"] = Utils.strip_rich_text(str(metadata.get("artist", manifest.get("artist", "Unknown Artist"))))
	manifest["charter"] = Utils.strip_rich_text(str(metadata.get("charter", manifest.get("charter", "Unknown Charter"))))
	manifest["bpm"] = float(metadata.get("bpm", manifest.get("bpm", 120.0)))
	manifest["offset"] = float(manifest.get("offset", 0.0))
	manifest["youtube_url"] = str(manifest.get("youtube_url", ""))
	var difficulties: Array = []
	if manifest.get("difficulties", []) is Array:
		difficulties = manifest.get("difficulties", []) as Array
	if not difficulties.has(difficulty):
		difficulties.append(difficulty)
	difficulties.sort_custom(func(a: Variant, b: Variant) -> bool:
		return Utils.DIFFICULTY_ORDER.find(str(a)) < Utils.DIFFICULTY_ORDER.find(str(b))
	)
	manifest["difficulties"] = difficulties
	var write_result: Dictionary = Utils.write_json(manifest_path, manifest)
	write_result["path"] = manifest_path
	return write_result


static func import_sng_audio_if_available(inspect_result: Dictionary, project_folder: String) -> Dictionary:
	return _import_extracted_audio_if_available(inspect_result, project_folder)


static func import_osz_audio_if_available(inspect_result: Dictionary, project_folder: String) -> Dictionary:
	return _import_extracted_audio_if_available(inspect_result, project_folder)


static func _import_extracted_audio_if_available(inspect_result: Dictionary, project_folder: String) -> Dictionary:
	var extracted: Dictionary = inspect_result.get("extracted", {}) as Dictionary
	for key in extracted.keys():
		var path := str(extracted[key])
		if path.get_extension().to_lower() == "opus":
			var target := project_folder.path_join("song.ogg")
			var converted := AudioImporter.convert_to_ogg(path, target)
			if not bool(converted.get("ok", false)):
				return {"ok": false, "path": "", "error": str(converted.get("error", ""))}
			return {"ok": true, "path": target, "error": ""}
		if ["wav", "ogg", "mp3"].has(path.get_extension().to_lower()):
			return AudioImporter.import_audio(path, project_folder)
	return {"ok": true, "path": "", "error": ""}


static func extract_sng_assets(path: String, project_folder: String) -> Dictionary:
	return SngImporter.inspect_file(path, project_folder)


static func extract_osz_assets(path: String, project_folder: String) -> Dictionary:
	return OszImporter.inspect_file(path, project_folder)
