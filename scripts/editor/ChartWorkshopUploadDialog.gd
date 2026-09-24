extends ConfirmationDialog
class_name ChartWorkshopUploadDialog

signal upload_requested(details: Dictionary)

const HDTheme = preload("res://scripts/ui/HDTheme.gd")

var _title_edit: LineEdit
var _author_edit: LineEdit
var _description_edit: TextEdit
var _tags_edit: LineEdit
var _visibility_option: OptionButton
var _existing_item_id_edit: LineEdit
var _change_note_edit: TextEdit
var _preview_path_edit: LineEdit
var _preview_browse_button: Button
var _preview_file_dialog: FileDialog
var _generate_missing_difficulty_check: CheckBox
var _status_label: Label
var _status_details_edit: TextEdit
var _content_scroll: ScrollContainer
var _footer_bar: HBoxContainer
var _cancel_button: Button
var _copy_details_button: Button
var _upload_button: Button
var _status_history: Array[String] = []


func _ready() -> void:
	title = "Upload Chart To Workshop"
	ok_button_text = "UPLOAD"
	cancel_button_text = "CANCEL"
	min_size = Vector2i(660, 560)
	size = Vector2i(660, 620)
	get_ok_button().visible = false
	get_cancel_button().visible = false

	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(600, 520)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	_content_scroll = ScrollContainer.new()
	_content_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content_scroll.custom_minimum_size = Vector2(600, 430)
	_content_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_content_scroll)

	var form := VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_theme_constant_override("separation", 8)
	_content_scroll.add_child(form)

	_title_edit = _line_edit("Workshop Title", "My Harmonic Drive Chart", form)
	_author_edit = _line_edit("Creator Name", "Player", form)
	_add_label("Description", form)
	_description_edit = TextEdit.new()
	_description_edit.placeholder_text = "Describe the chart, song, and difficulty coverage."
	_description_edit.custom_minimum_size = Vector2(560, 82)
	form.add_child(_description_edit)
	_tags_edit = _line_edit("Workshop Tags", "Chart, Custom", form)

	_visibility_option = OptionButton.new()
	_visibility_option.add_item("Private")
	_visibility_option.set_item_metadata(0, "private")
	_visibility_option.add_item("Friends Only")
	_visibility_option.set_item_metadata(1, "friends")
	_visibility_option.add_item("Public")
	_visibility_option.set_item_metadata(2, "public")
	_visibility_option.add_item("Unlisted")
	_visibility_option.set_item_metadata(3, "unlisted")
	_visibility_option.select(2)
	form.add_child(_labeled_control("Visibility", _visibility_option))

	_existing_item_id_edit = _line_edit("Existing Workshop Item ID (optional)", "", form)
	_add_label("Change Note", form)
	_change_note_edit = TextEdit.new()
	_change_note_edit.placeholder_text = "What changed in this chart upload?"
	_change_note_edit.custom_minimum_size = Vector2(560, 68)
	form.add_child(_change_note_edit)
	_add_label("Preview Image Path (optional)", form)
	var preview_row := HBoxContainer.new()
	preview_row.add_theme_constant_override("separation", 6)
	form.add_child(preview_row)
	_preview_path_edit = LineEdit.new()
	_preview_path_edit.placeholder_text = "Leave blank to generate a simple preview.png."
	_preview_path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_row.add_child(_preview_path_edit)
	_preview_browse_button = Button.new()
	_preview_browse_button.text = "BROWSE"
	_preview_browse_button.custom_minimum_size = Vector2(94, 30)
	preview_row.add_child(_preview_browse_button)

	var generate_row := HBoxContainer.new()
	generate_row.add_theme_constant_override("separation", 6)
	generate_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_child(generate_row)
	_generate_missing_difficulty_check = CheckBox.new()
	_generate_missing_difficulty_check.tooltip_text = "Generate missing difficulty charts based off of currently selected difficulty"
	_generate_missing_difficulty_check.button_pressed = false
	generate_row.add_child(_generate_missing_difficulty_check)
	var generate_label := Label.new()
	generate_label.text = "Generate missing difficulty charts based off of currently selected difficulty"
	generate_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	generate_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	generate_label.mouse_filter = Control.MOUSE_FILTER_STOP
	generate_label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	generate_label.gui_input.connect(_on_generate_missing_label_gui_input)
	generate_row.add_child(generate_label)

	var note := Label.new()
	note.text = "Workshop chart uploads export a Workshop-ready folder without audio. YouTube URLs are saved in manifest.json so players can retrieve their own local audio copy."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form.add_child(note)

	_status_label = Label.new()
	_status_label.text = "Ready to upload."
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.custom_minimum_size = Vector2(600, 34)
	root.add_child(_status_label)
	_status_details_edit = TextEdit.new()
	_status_details_edit.custom_minimum_size = Vector2(600, 118)
	_status_details_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_details_edit.editable = false
	root.add_child(_status_details_edit)
	var separator := HSeparator.new()
	root.add_child(separator)
	_footer_bar = HBoxContainer.new()
	_footer_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_footer_bar.add_theme_constant_override("separation", 10)
	root.add_child(_footer_bar)
	_copy_details_button = Button.new()
	_copy_details_button.text = "COPY ERROR DETAILS"
	_copy_details_button.custom_minimum_size = Vector2(188, 34)
	_footer_bar.add_child(_copy_details_button)
	var footer_spacer := Control.new()
	footer_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_footer_bar.add_child(footer_spacer)
	_cancel_button = Button.new()
	_cancel_button.text = "CANCEL"
	_cancel_button.custom_minimum_size = Vector2(120, 34)
	_footer_bar.add_child(_cancel_button)
	_upload_button = Button.new()
	_upload_button.text = "UPLOAD"
	_upload_button.custom_minimum_size = Vector2(120, 34)
	_footer_bar.add_child(_upload_button)

	confirmed.connect(_on_confirmed)
	_cancel_button.pressed.connect(hide)
	_upload_button.pressed.connect(_on_confirmed)
	_copy_details_button.pressed.connect(_copy_status_details)
	_preview_browse_button.pressed.connect(_open_preview_file_dialog)

	_preview_file_dialog = FileDialog.new()
	_preview_file_dialog.title = "Select Workshop Preview Image"
	_preview_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_preview_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_preview_file_dialog.filters = PackedStringArray(["*.png ; PNG image", "*.jpg, *.jpeg ; JPEG image", "*.webp ; WebP image"])
	_preview_file_dialog.file_selected.connect(_on_preview_file_selected)
	add_child(_preview_file_dialog)
	HDTheme.apply_dialog(self)
	HDTheme.apply_dialog(_preview_file_dialog)


func set_metadata(metadata: Dictionary) -> void:
	if _title_edit == null:
		return
	_title_edit.text = str(metadata.get("title", "Harmonic Drive Chart"))
	_author_edit.text = str(metadata.get("author", "Player"))
	_description_edit.text = str(metadata.get("description", "Created in the Harmonic Drive Chart Editor."))
	_tags_edit.text = ", ".join(_string_array(metadata.get("tags", ["Chart", "Custom"])))
	_existing_item_id_edit.text = str(metadata.get("workshop_item_id", metadata.get("existing_item_id", "")))
	_change_note_edit.text = str(metadata.get("change_note", "Uploaded from the Harmonic Drive Chart Editor."))
	_preview_path_edit.text = str(metadata.get("preview_path", ""))
	_generate_missing_difficulty_check.button_pressed = bool(metadata.get("generate_missing_difficulties", false))
	_select_visibility(str(metadata.get("visibility", metadata.get("workshop_visibility", "public"))))
	_clear_status_details()
	set_status_message("Ready to upload.")


func get_upload_details() -> Dictionary:
	return {
		"title": _clean_text(_title_edit.text, "Harmonic Drive Chart"),
		"author": _clean_text(_author_edit.text, "Player"),
		"description": _clean_text(_description_edit.text, "Created in the Harmonic Drive Chart Editor."),
		"tags": _tags(),
		"visibility": _selected_visibility(),
		"workshop_visibility": _selected_visibility(),
		"existing_item_id": _existing_item_id_edit.text.strip_edges(),
		"workshop_item_id": _existing_item_id_edit.text.strip_edges(),
		"change_note": _clean_text(_change_note_edit.text, "Uploaded from the Harmonic Drive Chart Editor."),
		"preview_path": _preview_path_edit.text.strip_edges(),
		"generate_missing_difficulties": _generate_missing_difficulty_check.button_pressed,
	}


func set_status_message(message: String, details: Dictionary = {}) -> void:
	if _status_label != null:
		_status_label.text = message
	_append_status_details(message, details)


func get_debug_state() -> Dictionary:
	return {
		"has_title": _title_edit != null,
		"has_author": _author_edit != null,
		"has_description": _description_edit != null,
		"has_tags": _tags_edit != null,
		"has_visibility": _visibility_option != null,
			"has_existing_item_id": _existing_item_id_edit != null,
			"has_change_note": _change_note_edit != null,
			"has_preview_path": _preview_path_edit != null,
			"has_preview_browse": _preview_browse_button != null and _preview_file_dialog != null,
			"has_generate_missing_difficulties": _generate_missing_difficulty_check != null,
			"generate_missing_difficulties": _generate_missing_difficulty_check.button_pressed if _generate_missing_difficulty_check != null else false,
			"body_scrollable": _content_scroll != null,
			"has_status_details": _status_details_edit != null,
			"status_details": _status_details_edit.text if _status_details_edit != null else "",
			"has_copy_details": _copy_details_button != null and _copy_details_button.visible,
			"has_footer": _footer_bar != null,
			"has_footer_cancel": _cancel_button != null and _cancel_button.visible,
			"has_footer_upload": _upload_button != null and _upload_button.visible,
			"has_status": _status_label != null,
			"status": _status_label.text if _status_label != null else "",
			"visibility": _selected_visibility(),
	}


func _line_edit(label_text: String, placeholder: String, root: VBoxContainer) -> LineEdit:
	_add_label(label_text, root)
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(edit)
	return edit


func _add_label(label_text: String, root: VBoxContainer) -> void:
	var label := Label.new()
	label.text = label_text
	root.add_child(label)


func _labeled_control(label_text: String, control: Control) -> VBoxContainer:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 3)
	_add_label(label_text, root)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(control)
	return root


func _on_confirmed() -> void:
	set_status_message("Preparing Steam Workshop upload...")
	upload_requested.emit(get_upload_details())


func _clear_status_details() -> void:
	_status_history.clear()
	if _status_details_edit != null:
		_status_details_edit.text = ""


func _append_status_details(message: String, details: Dictionary = {}) -> void:
	var line := "%s  %s" % [Time.get_datetime_string_from_system(), message]
	if not details.is_empty():
		var detail_copy := details.duplicate(true)
		detail_copy.erase("validation")
		line += "\n%s" % JSON.stringify(detail_copy, "\t", false)
	_status_history.append(line)
	while _status_history.size() > 80:
		_status_history.pop_front()
	if _status_details_edit != null:
		_status_details_edit.text = "\n\n".join(_status_history)
		_status_details_edit.scroll_vertical = _status_details_edit.get_line_count()


func _copy_status_details() -> void:
	var text := ""
	if _status_details_edit != null:
		text = _status_details_edit.text
	if text.strip_edges().is_empty():
		text = _status_label.text if _status_label != null else ""
	if not text.strip_edges().is_empty():
		DisplayServer.clipboard_set(text)
		set_status_message("Copied Workshop upload details to clipboard.")


func _on_generate_missing_label_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_generate_missing_difficulty_check.button_pressed = not _generate_missing_difficulty_check.button_pressed


func _open_preview_file_dialog() -> void:
	if _preview_file_dialog == null:
		return
	_preview_file_dialog.popup_centered(Vector2i(760, 520))


func _on_preview_file_selected(path: String) -> void:
	if _preview_path_edit != null:
		_preview_path_edit.text = path


func _selected_visibility() -> String:
	if _visibility_option == null or _visibility_option.selected < 0:
		return "public"
	return str(_visibility_option.get_item_metadata(_visibility_option.selected))


func _select_visibility(value: String) -> void:
	if _visibility_option == null:
		return
	var normalized := value.strip_edges().to_lower()
	for item_index in range(_visibility_option.item_count):
		if str(_visibility_option.get_item_metadata(item_index)) == normalized:
			_visibility_option.select(item_index)
			return
	_visibility_option.select(0)


func _tags() -> Array[String]:
	var out: Array[String] = []
	for part in _tags_edit.text.split(",", false):
		var tag := str(part).strip_edges()
		if not tag.is_empty() and not out.has(tag):
			out.append(tag)
	if out.is_empty():
		out = ["Chart", "Custom"]
	return out


func _string_array(value: Variant) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for item in value:
			var text := str(item).strip_edges()
			if not text.is_empty():
				out.append(text)
	elif not str(value).strip_edges().is_empty():
		out.append(str(value).strip_edges())
	return out


func _clean_text(value: String, fallback: String) -> String:
	var cleaned := value.strip_edges()
	return fallback if cleaned.is_empty() else cleaned
