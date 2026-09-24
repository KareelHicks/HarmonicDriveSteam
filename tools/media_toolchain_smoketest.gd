extends SceneTree

const EditorAudioImporter := preload("res://scripts/editor/importers/EditorAudioImporter.gd")
const YouTubeAudioImporter := preload("res://scripts/editor/YouTubeAudioImporter.gd")


func _init() -> void:
	var failed := false
	var status := YouTubeAudioImporter.tool_status()
	var ffmpeg := str(status.get("ffmpeg", ""))
	var ytdlp := str(status.get("yt_dlp", ""))
	failed = _expect(not ffmpeg.is_empty(), "FFmpeg was not resolved.") or failed
	failed = _expect(not ytdlp.is_empty(), "yt-dlp was not resolved.") or failed
	if not failed:
		failed = _expect(_probe_tool(ffmpeg, ["-version"]), "FFmpeg did not execute.") or failed
		failed = _expect(_probe_tool(ytdlp, ["--version"]), "yt-dlp did not execute.") or failed
	if not failed:
		failed = _exercise_ffmpeg_conversion(ffmpeg) or failed
	if failed:
		quit(1)
	else:
		print("Media toolchain smoke test passed.")
		quit(0)


func _exercise_ffmpeg_conversion(ffmpeg: String) -> bool:
	var root := "user://media_toolchain_smoketest"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root))
	var source := root.path_join("source.m4a")
	var target := root.path_join("song.ogg")
	var output: Array = []
	var create_code := OS.execute(
			ffmpeg,
			[
				"-y",
				"-f",
				"lavfi",
				"-i",
				"sine=frequency=440:duration=0.25",
				"-vn",
				"-c:a",
				"aac",
				ProjectSettings.globalize_path(source),
			],
			output,
			true,
			false
	)
	if create_code != 0:
		push_error("FFmpeg could not create source m4a (%d): %s" % [create_code, "\n".join(output)])
		return true
	var convert := EditorAudioImporter.convert_to_ogg(source, target)
	if not bool(convert.get("ok", false)):
		push_error("EditorAudioImporter conversion failed: %s" % str(convert.get("error", "")))
		return true
	var file := FileAccess.open(target, FileAccess.READ)
	if file == null or file.get_length() <= 0:
		push_error("Converted song.ogg was missing or empty.")
		return true
	return false


func _probe_tool(path: String, args: Array[String]) -> bool:
	var output: Array = []
	return OS.execute(path, args, output, true, false) == 0


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return false
	push_error(message)
	return true
