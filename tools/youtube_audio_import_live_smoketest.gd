extends SceneTree

const YouTubeAudioImporter := preload("res://scripts/editor/YouTubeAudioImporter.gd")
const HarmonicProjectPackage := preload("res://scripts/editor/HarmonicProjectPackage.gd")

const TEST_URL := "https://www.youtube.com/watch?v=jNQXAC9IVRw"


func _init() -> void:
	var project := "user://youtube_audio_import_live_smoketest"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(project))
	var manifest := {
		"song_id": "youtube_audio_import_live_smoketest",
		"title": "YouTube Audio Import Live Smoketest",
		"artist": "yt-dlp",
		"charter": "Harmonic Drive",
		"youtube_url": TEST_URL,
	}
	HarmonicProjectPackage.write_manifest(project, manifest)
	var result := YouTubeAudioImporter.import_url_to_project(TEST_URL, project)
	if not bool(result.get("ok", false)):
		push_error("YouTube import failed: %s" % str(result.get("error", "")))
		quit(1)
		return
	var audio_path := str(result.get("path", ""))
	HarmonicProjectPackage.set_manifest_audio_path(project, audio_path)
	HarmonicProjectPackage.set_manifest_youtube_url(project, TEST_URL)
	var audio := FileAccess.open(audio_path, FileAccess.READ)
	if audio == null or audio.get_length() <= 0:
		push_error("YouTube import did not create non-empty audio: %s" % audio_path)
		quit(1)
		return
	var saved_manifest := HarmonicProjectPackage.read_manifest(project)
	if str(saved_manifest.get("youtube_url", "")) != TEST_URL:
		push_error("Manifest did not preserve youtube_url.")
		quit(1)
		return
	if str(saved_manifest.get("audio_path", "")) != audio_path:
		push_error("Manifest did not preserve imported audio_path.")
		quit(1)
		return
	print("YouTube audio import live smoke test passed: %s" % audio_path)
	quit(0)
