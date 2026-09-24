extends RefCounted
class_name YouTubeAudioImporter

const EditorAudioImporter := preload("res://scripts/editor/importers/EditorAudioImporter.gd")
const ExternalToolResolver := preload("res://scripts/system/ExternalToolResolver.gd")

const DOWNLOAD_FOLDER_NAME := ".youtube_download"
const DOWNLOAD_STEM := "source"
const YTDLP_FORMAT := "bestaudio[ext=m4a]/bestaudio[ext=webm]/bestaudio"
const DOWNLOAD_EXTENSIONS: Array[String] = ["m4a", "webm", "mp4", "opus", "ogg"]


static func import_url_to_project(youtube_url: String, project_folder: String) -> Dictionary:
	var url := youtube_url.strip_edges()
	if not is_supported_url(url):
		return {"ok": false, "path": "", "source_path": "", "youtube_url": url, "error": "Enter a valid YouTube URL."}
	if project_folder.strip_edges().is_empty():
		return {"ok": false, "path": "", "source_path": "", "youtube_url": url, "error": "Missing project folder."}

	var ytdlp := find_ytdlp()
	if ytdlp.is_empty():
		return {
			"ok": false,
			"path": "",
			"source_path": "",
			"youtube_url": url,
			"error": "yt-dlp was not found. Add a bundled binary under tools/yt-dlp/<platform>/ or install yt-dlp on PATH.",
		}

	var download_folder := project_folder.path_join(DOWNLOAD_FOLDER_NAME)
	var download_folder_abs := ProjectSettings.globalize_path(download_folder)
	var dir_err := DirAccess.make_dir_recursive_absolute(download_folder_abs)
	if dir_err != OK:
		return {"ok": false, "path": "", "source_path": "", "youtube_url": url, "error": "Could not create download folder: %s" % download_folder}

	_remove_previous_downloads(download_folder)
	var output_template := download_folder_abs.path_join("%s.%%(ext)s" % DOWNLOAD_STEM)
	var output: Array = []
	var args: Array[String] = [
		"--no-playlist",
		"-f",
		YTDLP_FORMAT,
		"-o",
		output_template,
		url,
	]
	var code := OS.execute(ytdlp, args, output, true, false)
	if code != 0:
		return {
			"ok": false,
			"path": "",
			"source_path": "",
			"youtube_url": url,
			"error": "yt-dlp download failed (%d): %s" % [code, "\n".join(output)],
		}

	var source_path := _find_downloaded_source(download_folder)
	if source_path.is_empty():
		return {
			"ok": false,
			"path": "",
			"source_path": "",
			"youtube_url": url,
			"error": "yt-dlp completed but no supported .webm or .m4a audio file was found.",
		}

	var target_path := project_folder.path_join("song.ogg")
	var convert := EditorAudioImporter.convert_to_ogg(source_path, target_path)
	if not bool(convert.get("ok", false)):
		return {
			"ok": false,
			"path": "",
			"source_path": source_path,
			"youtube_url": url,
			"error": str(convert.get("error", "FFmpeg conversion failed.")),
		}
	return {"ok": true, "path": target_path, "source_path": source_path, "youtube_url": url, "error": ""}


static func import_url_to_project_interactive(youtube_url: String, project_folder: String, status_callback: Callable = Callable()) -> Dictionary:
	var url := youtube_url.strip_edges()
	if not is_supported_url(url):
		return {"ok": false, "path": "", "source_path": "", "youtube_url": url, "error": "Enter a valid YouTube URL."}
	if project_folder.strip_edges().is_empty():
		return {"ok": false, "path": "", "source_path": "", "youtube_url": url, "error": "Missing project folder."}

	var ytdlp := find_ytdlp()
	if ytdlp.is_empty():
		return {
			"ok": false,
			"path": "",
			"source_path": "",
			"youtube_url": url,
			"error": "yt-dlp was not found. Add a bundled binary under tools/yt-dlp/<platform>/ or install yt-dlp on PATH.",
		}

	var download_folder := project_folder.path_join(DOWNLOAD_FOLDER_NAME)
	var download_folder_abs := ProjectSettings.globalize_path(download_folder)
	var dir_err := DirAccess.make_dir_recursive_absolute(download_folder_abs)
	if dir_err != OK:
		return {"ok": false, "path": "", "source_path": "", "youtube_url": url, "error": "Could not create download folder: %s" % download_folder}

	_remove_previous_downloads(download_folder)
	var output_template := download_folder_abs.path_join("%s.%%(ext)s" % DOWNLOAD_STEM)
	var output: Array = []
	var args: Array[String] = [
		"--no-playlist",
		"-f",
		YTDLP_FORMAT,
		"-o",
		output_template,
		url,
	]
	await _emit_status_frame(status_callback, "download_youtube", "Downloading YouTube content", "Fetching the subscribed chart audio with yt-dlp.")
	var code := OS.execute(ytdlp, args, output, true, false)
	if code != 0:
		return {
			"ok": false,
			"path": "",
			"source_path": "",
			"youtube_url": url,
			"error": "yt-dlp download failed (%d): %s" % [code, "\n".join(output)],
		}

	var source_path := _find_downloaded_source(download_folder)
	if source_path.is_empty():
		return {
			"ok": false,
			"path": "",
			"source_path": "",
			"youtube_url": url,
			"error": "yt-dlp completed but no supported .webm or .m4a audio file was found.",
		}

	var target_path := project_folder.path_join("song.ogg")
	await _emit_status_frame(status_callback, "convert_youtube", "Converting YouTube audio", "Converting downloaded audio to song.ogg.")
	var convert := EditorAudioImporter.convert_to_ogg(source_path, target_path)
	if not bool(convert.get("ok", false)):
		return {
			"ok": false,
			"path": "",
			"source_path": source_path,
			"youtube_url": url,
			"error": str(convert.get("error", "FFmpeg conversion failed.")),
		}
	return {"ok": true, "path": target_path, "source_path": source_path, "youtube_url": url, "error": ""}


static func find_ytdlp() -> String:
	var platform := OS.get_name().to_lower()
	var bundled_path := ""
	var system_candidates: Array[String] = []
	if platform.contains("windows"):
		bundled_path = "res://tools/yt-dlp/windows/yt-dlp.exe"
		system_candidates.append("yt-dlp.exe")
	elif platform.contains("mac"):
		bundled_path = "res://tools/yt-dlp/macos/yt-dlp"
		system_candidates.append("/opt/homebrew/bin/yt-dlp")
		system_candidates.append("/usr/local/bin/yt-dlp")
		system_candidates.append("yt-dlp")
	else:
		bundled_path = "res://tools/yt-dlp/linux/yt-dlp"
		system_candidates.append("/usr/bin/yt-dlp")
		system_candidates.append("/usr/local/bin/yt-dlp")
		system_candidates.append("yt-dlp")
	return ExternalToolResolver.resolve_tool(bundled_path, system_candidates, ["--version"])


static func tool_status() -> Dictionary:
	return {
		"yt_dlp": find_ytdlp(),
		"ffmpeg": EditorAudioImporter.find_ffmpeg(),
	}


static func is_supported_url(value: String) -> bool:
	var lower := value.to_lower()
	if not (lower.begins_with("https://") or lower.begins_with("http://")):
		return false
	return lower.contains("youtube.com/") or lower.contains("youtu.be/")


static func _emit_status_frame(status_callback: Callable, phase: String, title: String, detail: String) -> void:
	if status_callback.is_valid():
		status_callback.call({"phase": phase, "title": title, "detail": detail})
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		await tree.process_frame


static func _remove_previous_downloads(download_folder: String) -> void:
	var dir := DirAccess.open(download_folder)
	if dir == null:
		return
	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name.is_empty():
			break
		if dir.current_is_dir():
			continue
		if String(name).begins_with(DOWNLOAD_STEM + "."):
			dir.remove(name)
	dir.list_dir_end()


static func _find_downloaded_source(download_folder: String) -> String:
	var dir := DirAccess.open(download_folder)
	if dir == null:
		return ""
	var found: Array[String] = []
	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name.is_empty():
			break
		if dir.current_is_dir():
			continue
		var lower := String(name).to_lower()
		if not lower.begins_with(DOWNLOAD_STEM + "."):
			continue
		var ext := lower.get_extension()
		if DOWNLOAD_EXTENSIONS.has(ext):
			var candidate := download_folder.path_join(name)
			var file := FileAccess.open(candidate, FileAccess.READ)
			if file != null and file.get_length() > 0:
				found.append(candidate)
	dir.list_dir_end()
	found.sort_custom(func(a: String, b: String) -> bool:
		var a_rank := DOWNLOAD_EXTENSIONS.find(a.get_extension().to_lower())
		var b_rank := DOWNLOAD_EXTENSIONS.find(b.get_extension().to_lower())
		if a_rank == b_rank:
			return a < b
		return a_rank < b_rank
	)
	return found[0] if not found.is_empty() else ""
