extends SceneTree

const ChartImportUtils := preload("res://scripts/editor/importers/ChartImportUtils.gd")
const ChartLoader := preload("res://scripts/gameplay/ChartLoader.gd")
const DifficultyManager := preload("res://scripts/editor/DifficultyManager.gd")
const SongPackageManager := preload("res://scripts/editor/SongPackageManager.gd")

var _failures: Array[String] = []
var _project_folder := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_project_folder = "/tmp/harmonic_drive_chart_editor_difficulty_%d" % Time.get_ticks_usec()
	var mkdir_error := DirAccess.make_dir_recursive_absolute(_project_folder)
	_expect(mkdir_error == OK, "Could not create the temporary Chart Editor project.")
	if mkdir_error != OK:
		_finish()
		return

	var manifest := {
		"song_id": "difficulty_switch_probe",
		"title": "Difficulty Switch Probe",
		"artist": "Regression Artist",
		"charter": "Regression Charter",
		"bpm": 137.0,
		"lane_count": 7,
		"offset": 0.0,
		"difficulties": ["expert"],
	}
	var manifest_result := ChartImportUtils.write_json(_project_folder.path_join("manifest.json"), manifest)
	_expect(bool(manifest_result.get("ok", false)), "Could not write the temporary project manifest.")
	var expert_path := SongPackageManager.ensure_chart_exists(_project_folder, "expert")
	_expect(FileAccess.file_exists(expert_path), "Could not create the starter Expert chart.")

	var packed := load("res://scenes/editor/ChartEditorScene.tscn") as PackedScene
	var scene := packed.instantiate() if packed != null else null
	_expect(scene != null, "Could not instantiate ChartEditorScene.tscn.")
	if scene == null:
		_finish()
		return
	root.add_child(scene)
	await process_frame
	await process_frame

	scene.set("_song_folder", _project_folder)
	scene.set("_manifest_path", _project_folder.path_join("manifest.json"))
	scene.set("_difficulty", "expert")
	scene.call("_load_project_options")
	var difficulty_option := scene.get_node_or_null("%DifficultyOption") as OptionButton
	_expect(difficulty_option != null, "Chart Editor is missing its difficulty selector.")
	if difficulty_option != null:
		_expect(difficulty_option.item_count == DifficultyManager.all_ids().size(), "Difficulty selector does not expose every supported difficulty.")
		for index in range(difficulty_option.item_count):
			_expect(not difficulty_option.is_item_disabled(index), "%s is disabled before its chart exists." % difficulty_option.get_item_text(index))

		var easy_index := _option_index(difficulty_option, "easy")
		_expect(easy_index >= 0, "Difficulty selector is missing Easy.")
		if easy_index >= 0:
			var easy_path := _project_folder.path_join("easy.json")
			_expect(not FileAccess.file_exists(easy_path), "Easy unexpectedly existed before it was selected.")
			difficulty_option.select(easy_index)
			difficulty_option.item_selected.emit(easy_index)
			for _frame in range(12):
				await process_frame
			_expect(str(scene.get("_difficulty")) == "easy", "Selecting Easy did not switch the active editor difficulty.")
			_expect(FileAccess.file_exists(easy_path), "Selecting a missing difficulty did not create its clean chart.")
			var loaded_easy := ChartLoader.load_hd_chart(easy_path, "easy")
			_expect(bool(loaded_easy.get("ok", false)), "The newly created Easy chart is invalid.")
			var easy_chart := loaded_easy.get("chart", {}) as Dictionary
			_expect((easy_chart.get("notes", []) as Array).is_empty(), "Direct difficulty switching copied notes instead of creating a clean chart.")
			_expect(str(easy_chart.get("difficulty", "")) == "easy", "New chart has the wrong difficulty ID.")
			_expect(str(easy_chart.get("title", "")) == "Difficulty Switch Probe", "New chart did not preserve the project title.")
			_expect(str(easy_chart.get("artist", "")) == "Regression Artist", "New chart did not preserve the project artist.")
			_expect(str(easy_chart.get("charter", "")) == "Regression Charter", "New chart did not preserve the project charter.")
			_expect(int(easy_chart.get("lane_count", 0)) == 7, "New chart did not preserve the project lane count.")
			_expect(is_equal_approx(float(easy_chart.get("bpm", 0.0)), 137.0), "New chart did not preserve the project BPM.")
			var updated_manifest := ChartLoader.load_json_dictionary(_project_folder.path_join("manifest.json"))
			var updated_payload := updated_manifest.get("value", {}) as Dictionary
			_expect((updated_payload.get("difficulties", []) as Array).has("easy"), "Selecting a new difficulty did not register it in the project manifest.")

	scene.queue_free()
	await process_frame
	_finish()


func _option_index(option: OptionButton, difficulty_id: String) -> int:
	for index in range(option.item_count):
		if option.get_item_text(index).strip_edges().to_lower() == difficulty_id:
			return index
	return -1


func _finish() -> void:
	_remove_tree(_project_folder)
	if _failures.is_empty():
		print("CHART_EDITOR_DIFFICULTY_SWITCHING_SMOKETEST_OK")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _remove_tree(path: String) -> void:
	if path.is_empty() or not path.begins_with("/tmp/harmonic_drive_chart_editor_difficulty_"):
		return
	var directory := DirAccess.open(path)
	if directory == null:
		return
	for file_name in directory.get_files():
		DirAccess.remove_absolute(path.path_join(file_name))
	for directory_name in directory.get_directories():
		_remove_tree(path.path_join(directory_name))
	DirAccess.remove_absolute(path)
