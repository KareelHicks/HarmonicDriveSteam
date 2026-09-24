extends RefCounted
class_name ImportSourceScanner

const CHART_EXTENSIONS: Array[String] = ["osz", "osk", "sng", "json", "chart", "osu", "mid", "midi"]
const AUDIO_EXTENSIONS: Array[String] = ["ogg", "wav", "mp3", "opus", "m4a", "webm"]


static func list_chart_files(folder_abs: String) -> Array[String]:
	return _list_files_by_extension_priority(folder_abs, CHART_EXTENSIONS)


static func list_audio_files(folder_abs: String) -> Array[String]:
	return _list_files_by_extension_priority(folder_abs, AUDIO_EXTENSIONS)


static func first_chart_file(folder_abs: String) -> String:
	var files := list_chart_files(folder_abs)
	return files[0] if not files.is_empty() else ""


static func first_audio_file(folder_abs: String) -> String:
	var files := list_audio_files(folder_abs)
	return files[0] if not files.is_empty() else ""


static func ensure_contains(files: Array[String], path: String) -> Array[String]:
	var out := files.duplicate()
	if not path.is_empty() and not out.has(path):
		out.insert(0, path)
	return out


static func _list_files_by_extension_priority(folder_abs: String, extensions: Array[String]) -> Array[String]:
	var by_ext := {}
	for ext in extensions:
		by_ext[ext] = []
	var dir := DirAccess.open(folder_abs)
	if dir == null:
		return []
	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name.is_empty():
			break
		if dir.current_is_dir():
			continue
		var lower := String(name).to_lower()
		if lower.begins_with(".") or lower.begins_with("waveform_preview_cache") or lower.begins_with("midi_import_waveform_cache"):
			continue
		var ext := lower.get_extension()
		if by_ext.has(ext):
			(by_ext[ext] as Array).append(folder_abs.path_join(name))
	dir.list_dir_end()

	var out: Array[String] = []
	for ext in extensions:
		var matches: Array = by_ext[ext] as Array
		matches.sort()
		for path in matches:
			out.append(str(path))
	return out
