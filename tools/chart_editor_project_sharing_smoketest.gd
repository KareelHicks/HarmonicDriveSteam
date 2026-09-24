extends SceneTree

const ChartWorkshopUploadDialog := preload("res://scripts/editor/ChartWorkshopUploadDialog.gd")

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

	var import_button := scene.get_node_or_null("%ImportProjectButton") as Button
	var export_button := scene.get_node_or_null("%ExportProjectButton") as Button
	var workshop_button := scene.get_node_or_null("%WorkshopUploadButton") as Button
	var audio_button := scene.get_node_or_null("%BrowseAudioButton") as Button
	_expect(import_button != null, "Missing ImportProjectButton.")
	_expect(export_button != null, "Missing ExportProjectButton.")
	_expect(workshop_button != null, "Missing WorkshopUploadButton.")
	_expect(audio_button != null and audio_button.text == "Import Audio", "Import Audio button missing or renamed unexpectedly.")
	var missing_url_dialog := scene.get("_workshop_missing_url_dialog") as ConfirmationDialog
	_expect(missing_url_dialog != null, "Missing Workshop missing-URL confirmation dialog.")
	if missing_url_dialog != null:
		_expect(missing_url_dialog.dialog_text.is_empty(), "Workshop missing-URL dialog should use wrapped custom body text.")
		_expect(missing_url_dialog.min_size.x <= 520 and missing_url_dialog.min_size.y <= 220, "Workshop missing-URL dialog should stay compact.")
		var missing_url_label := missing_url_dialog.find_child("WorkshopMissingUrlMessage", true, false) as Label
		_expect(missing_url_label != null, "Workshop missing-URL dialog missing wrapped warning label.")
		if missing_url_label != null:
			_expect(missing_url_label.autowrap_mode != TextServer.AUTOWRAP_OFF, "Workshop missing-URL warning should wrap text.")
			_expect(missing_url_label.text.contains("associated audio file will not be uploaded"), "Workshop missing-URL warning lost audio-file warning copy.")
		missing_url_dialog.popup_centered(Vector2i(520, 220))
		await process_frame
		_expect(missing_url_dialog.size.x <= 560 and missing_url_dialog.size.y <= 260, "Workshop missing-URL popup should open at compact size.")
		missing_url_dialog.hide()
	if import_button != null:
		_expect(not import_button.disabled, "Import .harmonic should be available before opening a project.")
	if export_button != null:
		_expect(export_button.disabled, "Export .harmonic should be disabled until a project is open.")
	if workshop_button != null:
		_expect(workshop_button.disabled, "Workshop upload should be disabled until a project is open.")
	var upload_dialog := scene.get("_workshop_upload_dialog") as ChartWorkshopUploadDialog
	_expect(upload_dialog != null, "Missing chart Workshop upload dialog.")
	if upload_dialog != null:
			var upload_state: Dictionary = upload_dialog.get_debug_state()
			_expect(bool(upload_state.get("has_generate_missing_difficulties", false)), "Workshop upload dialog missing generate-missing-difficulties option.")
			_expect(not bool(upload_state.get("generate_missing_difficulties", true)), "Generate-missing-difficulties option should default off.")
			_expect(bool(upload_state.get("has_status_details", false)), "Workshop upload dialog missing persistent status details panel.")
			_expect(bool(upload_state.get("has_copy_details", false)), "Workshop upload dialog missing copy error details button.")
			upload_dialog.set_metadata({"generate_missing_difficulties": true})
			upload_dialog.set_status_message("Synthetic upload error.", {"item_id": "123456789012345678", "upload_log_path": "user://workshop_upload_log.txt"})
			upload_state = upload_dialog.get_debug_state()
			_expect(str(upload_state.get("status_details", "")).contains("Synthetic upload error."), "Workshop upload dialog did not preserve status details.")
			var upload_details: Dictionary = upload_dialog.get_upload_details()
			_expect(bool(upload_details.get("generate_missing_difficulties", false)), "Workshop upload details should include generate-missing-difficulties selection.")

	scene.queue_free()
	_finish()


func _finish() -> void:
	if _failures.is_empty():
		print("Chart editor project sharing smoke test passed.")
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
