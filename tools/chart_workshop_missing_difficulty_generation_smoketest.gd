extends SceneTree

const ChartImportUtils := preload("res://scripts/editor/importers/ChartImportUtils.gd")
const DifficultyManager := preload("res://scripts/editor/DifficultyManager.gd")
const SongResolver := preload("res://scripts/songs/SongResolver.gd")
const WaveformRenderer := preload("res://scripts/editor/WaveformRenderer.gd")

const SAMPLE_RATE := 1000
const DURATION_SEC := 12.0

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/editor/ChartEditorScene.tscn") as PackedScene
	if packed == null:
		_fail("Could not load ChartEditorScene.tscn.")
		_finish()
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame

	var project := "user://tmp_chart_workshop_missing_diff_%d" % Time.get_ticks_msec()
	var err := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(project))
	_expect(err == OK, "Could not create temporary chart project.")
	ChartImportUtils.write_json(project.path_join("manifest.json"), {
		"song_id": "tmp_chart_workshop_missing_diff",
		"title": "Workshop Missing Difficulty Probe",
		"artist": "Automated Test",
		"charter": "Automated Test",
		"bpm": 120.0,
		"offset": 0.0,
		"youtube_url": "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
		"difficulties": ["expert"],
	})
	ChartImportUtils.write_json(project.path_join("expert.json"), ChartImportUtils.chart_payload(
		"expert",
		_source_notes(),
		5,
		{
			"title": "Workshop Missing Difficulty Probe",
			"artist": "Automated Test",
			"charter": "Automated Test",
			"bpm": 120.0,
		}
	))

	scene.set("_song_folder", project)
	scene.set("_manifest_path", project.path_join("manifest.json"))
	scene.set("_difficulty", "expert")
	var waveform := scene.get("_waveform") as WaveformRenderer
	_expect(waveform != null, "Chart editor scene did not expose waveform renderer.")
	if waveform != null:
		waveform.prepare_from_stream(_build_synthetic_wav())
		_expect(waveform.is_ready(), "Synthetic waveform should be ready for Smart Clone.")

	var summary: Dictionary = scene.call("_generate_missing_workshop_difficulties")
	_expect(bool(summary.get("requested", false)), "Workshop missing difficulty generation should mark request handled.")
	_expect(str(summary.get("source", "")) == "expert", "Workshop missing difficulty generation should use selected difficulty as source.")
	var generated: Array = summary.get("generated", []) as Array
	var failed: Array = summary.get("failed", []) as Array
	_expect(generated.size() == DifficultyManager.all_ids().size() - 1, "Workshop Smart Clone should generate every missing difficulty.")
	_expect(failed.is_empty(), "Workshop Smart Clone should not report failed difficulties.")

	for difficulty_id in DifficultyManager.all_ids():
		var chart_path := SongResolver.get_chart_path(project, difficulty_id)
		_expect(FileAccess.file_exists(chart_path), "Missing generated chart file: %s" % chart_path)

	var manifest := _read_json(project.path_join("manifest.json"))
	var difficulties: Array = manifest.get("difficulties", []) as Array
	for difficulty_id in DifficultyManager.all_ids():
		_expect(difficulties.has(difficulty_id), "Manifest missing generated difficulty: %s" % difficulty_id)

	var generation_message: String = scene.call("_workshop_generation_message", summary)
	_expect(generation_message.contains("Generated"), "Workshop generation summary should mention generated difficulties.")
	_expect(generation_message.contains("expert"), "Workshop generation summary should mention the source difficulty.")

	scene.queue_free()
	_finish()


func _source_notes() -> Array[Dictionary]:
	var notes: Array[Dictionary] = []
	for i in range(12):
		notes.append({
			"time": 0.5 + float(i) * 0.75,
			"lane": i % 5,
			"type": "tap",
		})
	return notes


func _build_synthetic_wav() -> AudioStreamWAV:
	var total_frames := int(DURATION_SEC * float(SAMPLE_RATE))
	var bytes := PackedByteArray()
	bytes.resize(total_frames * 2)
	for i in range(total_frames):
		var t := float(i) / float(SAMPLE_RATE)
		var beat_pos := fmod(t, 0.5)
		var sample := sin(TAU * 220.0 * t) * 0.12
		if beat_pos < 0.06:
			var decay := exp(-beat_pos * 46.0)
			sample += sin(TAU * 70.0 * t) * 0.82 * decay
		sample = clampf(sample, -0.95, 0.95)
		var int_sample := int(roundf(sample * 32767.0))
		if int_sample < 0:
			int_sample += 65536
		var byte_idx := i * 2
		bytes[byte_idx] = int_sample & 0xff
		bytes[byte_idx + 1] = (int_sample >> 8) & 0xff
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = bytes
	return wav


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed as Dictionary if parsed is Dictionary else {}


func _finish() -> void:
	if _failures.is_empty():
		print("Chart Workshop missing difficulty generation smoke test passed.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _fail(message: String) -> void:
	_failures.append(message)
