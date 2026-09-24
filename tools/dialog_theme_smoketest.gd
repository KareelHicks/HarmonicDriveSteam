extends SceneTree

const HDTheme := preload("res://scripts/ui/HDTheme.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	await process_frame
	_check_direct_dialog_theme(failures)
	await _check_local_songs_dialog_theme(failures)
	await _check_settings_dialog_theme(failures)
	if failures.is_empty():
		print("Dialog theme smoke test passed.")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _check_direct_dialog_theme(failures: Array[String]) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Theme Smoke"
	dialog.dialog_text = "The dialog should use Harmonic Drive theme overrides."
	root.add_child(dialog)
	HDTheme.apply_dialog(dialog)
	_expect_dialog_styled(dialog, "direct AcceptDialog", failures)
	dialog.queue_free()


func _check_local_songs_dialog_theme(failures: Array[String]) -> void:
	var packed := load("res://scenes/menus/LocalSongsMenu.tscn") as PackedScene
	if packed == null:
		failures.append("Could not load LocalSongsMenu.tscn.")
		return
	var menu := packed.instantiate()
	root.add_child(menu)
	await process_frame
	var source_dialog := menu.get("_import_source_dialog") as ConfirmationDialog
	var harmonic_dialog := menu.get("_import_harmonic_file_dialog") as FileDialog
	_expect_dialog_styled(source_dialog, "Local Songs import source dialog", failures)
	_expect_dialog_styled(harmonic_dialog, "Local Songs .harmonic file dialog", failures)
	menu.queue_free()


func _check_settings_dialog_theme(failures: Array[String]) -> void:
	var packed := load("res://scenes/menus/SettingsMenu.tscn") as PackedScene
	if packed == null:
		failures.append("Could not load SettingsMenu.tscn.")
		return
	var menu := packed.instantiate()
	root.add_child(menu)
	await process_frame
	var reset_dialog := menu.get_node_or_null("%ResetRecommendedDefaultsDialog") as ConfirmationDialog
	var gutter_dialog := menu.get_node_or_null("%EMSGutterImageFileDialog") as FileDialog
	_expect_dialog_styled(reset_dialog, "Settings reset dialog", failures)
	_expect_dialog_styled(gutter_dialog, "Settings gutter file dialog", failures)
	menu.queue_free()


func _expect_dialog_styled(dialog: Window, label: String, failures: Array[String]) -> void:
	if dialog == null:
		failures.append("%s is missing." % label)
		return
	if dialog.theme == null:
		failures.append("%s does not have a dialog theme." % label)
		return
	if not dialog.theme.has_stylebox("embedded_border", "Window"):
		failures.append("%s is missing the Harmonic Drive window panel style." % label)
	if dialog is AcceptDialog:
		var ok_button := (dialog as AcceptDialog).get_ok_button()
		if ok_button == null:
			failures.append("%s is missing its OK button." % label)
		elif not ok_button.has_theme_stylebox_override("normal"):
			failures.append("%s OK button is missing the Harmonic Drive button style." % label)
