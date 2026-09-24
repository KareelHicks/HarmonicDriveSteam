extends RefCounted
class_name AudioResolver

const CACHE_ROOT := "user://audio_cache"
const MANUAL_AUDIO_BASENAMES: Array[String] = ["audio", "song", "music", "track"]
const AUDIO_EXTENSIONS: Array[String] = [".ogg", ".wav", ".mp3", ".opus"]

static func cache_path_for_song_id(song_id: String, ext_with_dot: String) -> String:
	var sanitized := _sanitize_id(song_id.strip_edges())
	var ext := ext_with_dot.to_lower()
	if sanitized.is_empty():
		return ""
	if not AUDIO_EXTENSIONS.has(ext):
		ext = ".ogg"
	return CACHE_ROOT.path_join(sanitized + ext)


static func resolve_audio(song_manifest: Dictionary, song_folder: String) -> Dictionary:
	# Resolution order:
	# 1) Manifest-selected audio_path
	# 2) Cached audio (legal-safe: stored locally after user action / prior resolution)
	# 3) Audio file packaged alongside the song folder (workshop/custom)
	# 4) Gracefully fail when unavailable
	var song_id: String = str(song_manifest.get("song_id", "")).strip_edges()
	var sanitized_id: String = _sanitize_id(song_id)

	var manifest_audio := _resolve_manifest_audio(song_manifest, song_folder)
	if manifest_audio.get("status", "") == "available":
		return manifest_audio

	var cached := _resolve_cached_audio(sanitized_id)
	if cached.get("status", "") == "available":
		return cached

	var folder_audio := _resolve_folder_audio(song_folder)
	if folder_audio.get("status", "") == "available":
		return folder_audio

	return {"status": "missing", "path": "", "reason": "Audio not available."}


static func _resolve_manifest_audio(song_manifest: Dictionary, song_folder: String) -> Dictionary:
	var raw := str(song_manifest.get("audio_path", "")).strip_edges()
	if raw.is_empty():
		return {"status": "missing", "path": "", "reason": "No manifest audio_path."}
	var candidates: Array[String] = []
	if raw.begins_with("user://") or raw.begins_with("res://") or raw.begins_with("/") or raw.find(":\\") == 1:
		candidates.append(raw)
	elif not song_folder.is_empty():
		candidates.append(song_folder.path_join(raw))
	for candidate in candidates:
		if FileAccess.file_exists(candidate):
			return {"status": "available", "path": candidate, "reason": "Found manifest audio_path."}
	return {"status": "missing", "path": "", "reason": "Manifest audio_path was not found."}


static func _resolve_cached_audio(sanitized_song_id: String) -> Dictionary:
	if sanitized_song_id.is_empty():
		return {"status": "missing", "path": "", "reason": "Missing song_id."}
	for ext in AUDIO_EXTENSIONS:
		var candidate := CACHE_ROOT.path_join(sanitized_song_id + ext)
		if FileAccess.file_exists(candidate):
			return {"status": "available", "path": candidate, "reason": "Found cached audio."}
	return {"status": "missing", "path": "", "reason": "No cached audio found."}


static func list_cached_audio(song_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var sanitized := _sanitize_id(song_id.strip_edges())
	if sanitized.is_empty():
		return out
	for ext in AUDIO_EXTENSIONS:
		var candidate := CACHE_ROOT.path_join(sanitized + ext)
		if FileAccess.file_exists(candidate):
			out.append({"path": candidate, "name": candidate.get_file()})
	return out


static func _resolve_manual_audio(song_folder: String) -> Dictionary:
	if song_folder.is_empty():
		return {"status": "missing", "path": "", "reason": "Missing song folder."}
	for base in MANUAL_AUDIO_BASENAMES:
		for ext in AUDIO_EXTENSIONS:
			var candidate := song_folder.path_join(base + ext)
			if FileAccess.file_exists(candidate):
				return {"status": "available", "path": candidate, "reason": "Found manually imported audio in song folder."}
	return {"status": "missing", "path": "", "reason": "No manually imported audio found in song folder."}


static func list_folder_audio(song_folder: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if song_folder.is_empty():
		return out
	var dir := DirAccess.open(song_folder)
	if dir == null:
		return out
	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name.is_empty():
			break
		if dir.current_is_dir():
			continue
		var lower := String(name).to_lower()
		if lower.begins_with(".") or lower.begins_with("waveform_preview_cache"):
			continue
		for ext in AUDIO_EXTENSIONS:
			if lower.ends_with(ext):
				out.append({"path": song_folder.path_join(name), "name": name})
				break
	dir.list_dir_end()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("name", "")) < str(b.get("name", ""))
	)
	return out


static func _resolve_folder_audio(song_folder: String) -> Dictionary:
	# Prefer conventional basenames, then fall back to first audio file found.
	if song_folder.is_empty():
		return {"status": "missing", "path": "", "reason": "Missing song folder."}
	var manual := _resolve_manual_audio(song_folder)
	if manual.get("status", "") == "available":
		return manual
	var candidates := list_folder_audio(song_folder)
	if candidates.is_empty():
		return {"status": "missing", "path": "", "reason": "No audio file found in song folder."}
	return {"status": "available", "path": str((candidates[0] as Dictionary).get("path", "")), "reason": "Found audio file in song folder."}


static func _sanitize_id(value: String) -> String:
	var out := ""
	for i in range(value.length()):
		var c: String = value.substr(i, 1)
		var is_ok := (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9") or c == "_" or c == "-" or c == "."
		out += c if is_ok else "_"
	out = out.strip_edges()
	if out.is_empty():
		return ""
	if out.length() > 80:
		out = out.substr(0, 80)
	return out
