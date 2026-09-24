extends RefCounted
class_name EditorAudioImporter

const Utils := preload("res://scripts/editor/importers/ChartImportUtils.gd")
const ExternalToolResolver := preload("res://scripts/system/ExternalToolResolver.gd")

const SUPPORTED_DIRECT_EXTENSIONS: Array[String] = ["wav", "ogg", "mp3"]
const SUPPORTED_CONVERT_EXTENSIONS: Array[String] = ["opus", "m4a", "webm", "mp4", "aac"]


static func import_audio(source_path: String, project_folder: String) -> Dictionary:
	var ext := source_path.get_extension().to_lower()
	if SUPPORTED_DIRECT_EXTENSIONS.has(ext):
		var target_name := "song.%s" % ext
		var copied := Utils.copy_file_to_project(source_path, project_folder, target_name)
		if not bool(copied.get("ok", false)):
			return copied
		return {"ok": true, "path": str(copied.get("path", "")), "error": ""}
	if SUPPORTED_CONVERT_EXTENSIONS.has(ext):
		return import_convertible_audio(source_path, project_folder)
	return {"ok": false, "path": "", "error": "Unsupported audio extension: .%s" % ext}


static func import_opus(source_path: String, project_folder: String) -> Dictionary:
	return import_convertible_audio(source_path, project_folder)


static func import_convertible_audio(source_path: String, project_folder: String) -> Dictionary:
	var ext := source_path.get_extension().to_lower()
	var copied := Utils.copy_file_to_project(source_path, project_folder, "source.%s" % ext)
	if not bool(copied.get("ok", false)):
		return copied
	var source_copy_path := str(copied.get("path", ""))
	var ogg_path := project_folder.path_join("song.ogg")
	var convert := convert_to_ogg(source_copy_path, ogg_path)
	if not bool(convert.get("ok", false)):
		return {"ok": false, "path": source_copy_path, "error": str(convert.get("error", ""))}
	return {"ok": true, "path": ogg_path, "error": ""}


static func convert_to_ogg(source_path: String, target_path: String) -> Dictionary:
	var ffmpeg := find_ffmpeg()
	if ffmpeg.is_empty():
		return {"ok": false, "error": "FFmpeg was not found. Add a bundled binary under tools/ffmpeg/<platform>/ or install ffmpeg on PATH."}
	var source_abs := ProjectSettings.globalize_path(source_path) if source_path.begins_with("user://") or source_path.begins_with("res://") else source_path
	var target_abs := ProjectSettings.globalize_path(target_path) if target_path.begins_with("user://") or target_path.begins_with("res://") else target_path
	var output: Array = []
	var args: Array[String] = ["-y", "-i", source_abs, "-vn", "-c:a", "libvorbis", "-q:a", "5", target_abs]
	var code := OS.execute(ffmpeg, args, output, true, false)
	if code != 0:
		output.clear()
		args = ["-y", "-i", source_abs, "-vn", "-c:a", "vorbis", "-strict", "-2", "-q:a", "5", target_abs]
		code = OS.execute(ffmpeg, args, output, true, false)
	if code != 0:
		return {"ok": false, "error": "FFmpeg conversion failed (%d): %s" % [code, "\n".join(output)]}
	if not FileAccess.file_exists(target_path) and not FileAccess.file_exists(target_abs):
		return {"ok": false, "error": "FFmpeg did not create %s" % target_path}
	return {"ok": true, "error": ""}


static func convert_to_wav(source_path: String, target_path: String) -> Dictionary:
	var ffmpeg := find_ffmpeg()
	if ffmpeg.is_empty():
		return {"ok": false, "error": "FFmpeg was not found. Add a bundled binary under tools/ffmpeg/<platform>/ or install ffmpeg on PATH."}
	var source_abs := ProjectSettings.globalize_path(source_path) if source_path.begins_with("user://") or source_path.begins_with("res://") else source_path
	var target_abs := ProjectSettings.globalize_path(target_path) if target_path.begins_with("user://") or target_path.begins_with("res://") else target_path
	var output: Array = []
	var args: Array[String] = ["-y", "-i", source_abs, "-vn", "-ac", "2", "-ar", "44100", "-c:a", "pcm_s16le", target_abs]
	var code := OS.execute(ffmpeg, args, output, true, false)
	if code != 0:
		return {"ok": false, "error": "FFmpeg WAV decode failed (%d): %s" % [code, "\n".join(output)]}
	if not FileAccess.file_exists(target_path) and not FileAccess.file_exists(target_abs):
		return {"ok": false, "error": "FFmpeg did not create %s" % target_path}
	return {"ok": true, "error": ""}


static func find_ffmpeg() -> String:
	var platform := OS.get_name().to_lower()
	var bundled_path := ""
	var system_candidates: Array[String] = []
	if platform.contains("windows"):
		bundled_path = "res://tools/ffmpeg/windows/ffmpeg.exe"
		system_candidates.append("ffmpeg.exe")
	elif platform.contains("mac"):
		bundled_path = "res://tools/ffmpeg/macos/ffmpeg"
		system_candidates.append("/opt/homebrew/bin/ffmpeg")
		system_candidates.append("/usr/local/bin/ffmpeg")
		system_candidates.append("ffmpeg")
	else:
		bundled_path = "res://tools/ffmpeg/linux/ffmpeg"
		system_candidates.append("/usr/bin/ffmpeg")
		system_candidates.append("/usr/local/bin/ffmpeg")
		system_candidates.append("ffmpeg")
	return ExternalToolResolver.resolve_tool(bundled_path, system_candidates, ["-version"])
