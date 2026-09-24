extends RefCounted
class_name OszImporter

const Utils := preload("res://scripts/editor/importers/ChartImportUtils.gd")
const OsuManiaImporter := preload("res://scripts/editor/importers/OsuManiaImporter.gd")

const SUPPORTED_EXTRACT_EXTS := ["osu", "ogg", "mp3", "wav", "opus", "jpg", "jpeg", "png", "webp", "mp4"]


static func inspect_file(path: String, extract_folder: String = "") -> Dictionary:
	var zip := ZIPReader.new()
	var err := zip.open(path)
	if err != OK:
		return {"ok": false, "error": "Failed to open osu! package archive: %s" % path, "entries": [], "metadata": {}, "extracted": {}}

	var entries: Array[Dictionary] = []
	var metadata: Dictionary = {}
	var extracted := {}
	var osu_names: Array[String] = []
	var import_errors: Array[String] = []

	for file_path in zip.get_files():
		var lower := String(file_path).to_lower()
		if lower.ends_with(".osu"):
			osu_names.append(String(file_path))
		if not extract_folder.is_empty() and _should_extract(file_path):
			var target := _extract_file(zip, String(file_path), extract_folder)
			if not target.is_empty():
				extracted[String(file_path)] = target

	osu_names.sort()
	for osu_name in osu_names:
		var bytes := zip.read_file(osu_name)
		if bytes.is_empty():
			import_errors.append("%s: empty or unreadable" % osu_name)
			continue
		var result := OsuManiaImporter.inspect_text(bytes.get_string_from_utf8(), osu_name.get_file())
		if not bool(result.get("ok", false)):
			import_errors.append("%s: %s" % [osu_name.get_file(), str(result.get("error", "unsupported"))])
			continue
		if metadata.is_empty():
			metadata = (result.get("metadata", {}) as Dictionary).duplicate(true)
		for entry_var in (result.get("entries", []) as Array):
			if entry_var is not Dictionary:
				continue
			var entry: Dictionary = (entry_var as Dictionary).duplicate(true)
			entry["source_file"] = osu_name
			entry["source_name"] = "%s — %s" % [osu_name.get_file().get_basename(), str(entry.get("source_name", "osu!mania"))]
			entries.append(entry)

	zip.close()

	if entries.is_empty():
		var detail := "No supported osu! beatmaps found in %s." % path.get_file()
		if not import_errors.is_empty():
			detail += "\n" + "\n".join(import_errors)
		return {"ok": false, "error": detail, "entries": [], "metadata": metadata, "extracted": extracted}
	return {"ok": true, "error": "", "entries": entries, "metadata": metadata, "extracted": extracted}


static func _should_extract(file_path: String) -> bool:
	var lower := file_path.get_file().to_lower()
	for ext in SUPPORTED_EXTRACT_EXTS:
		if lower.ends_with("." + ext):
			return true
	return false


static func _extract_file(zip: ZIPReader, file_path: String, extract_folder: String) -> String:
	var clean_name := file_path.get_file()
	if clean_name.is_empty() or clean_name.contains(".."):
		return ""
	var bytes := zip.read_file(file_path)
	if bytes.is_empty():
		return ""
	var target := Utils.unique_path(extract_folder, clean_name.to_lower())
	var file := FileAccess.open(target, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_buffer(bytes)
	file.flush()
	return target
