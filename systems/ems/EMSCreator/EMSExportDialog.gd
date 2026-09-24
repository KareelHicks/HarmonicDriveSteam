extends ConfirmationDialog
class_name EMSExportDialog

signal export_requested(details: Dictionary)

const EMSValidator = preload("res://systems/ems/EMSValidator.gd")
const HDTheme = preload("res://scripts/ui/HDTheme.gd")

var _title_edit: LineEdit
var _pack_id_edit: LineEdit
var _author_edit: LineEdit
var _description_edit: TextEdit
var _tags_edit: LineEdit
var _creator_toggle: CheckBox
var _install_toggle: CheckBox
var _content_scroll: ScrollContainer
var _footer_bar: HBoxContainer
var _cancel_button: Button
var _export_button: Button


func _ready() -> void:
	title = "Export EMS Pack"
	ok_button_text = "EXPORT"
	cancel_button_text = "CANCEL"
	min_size = Vector2i(620, 500)
	size = Vector2i(620, 560)
	get_ok_button().visible = false
	get_cancel_button().visible = false
	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(560, 460)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	_content_scroll = ScrollContainer.new()
	_content_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content_scroll.custom_minimum_size = Vector2(560, 380)
	_content_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_content_scroll)

	var form := VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_theme_constant_override("separation", 8)
	_content_scroll.add_child(form)

	_title_edit = _line_edit("Pack Name", "My EMS Pack", form)
	_pack_id_edit = _line_edit("Pack ID", "my_ems_pack", form)
	_author_edit = _line_edit("Creator Name", "Player", form)
	var desc_label := Label.new()
	desc_label.text = "Description"
	form.add_child(desc_label)
	_description_edit = TextEdit.new()
	_description_edit.placeholder_text = "Describe the visual identity, effects, and intended vibe."
	_description_edit.custom_minimum_size = Vector2(520, 82)
	form.add_child(_description_edit)
	_tags_edit = _line_edit("Tags", "EMS, Custom", form)
	_creator_toggle = CheckBox.new()
	_creator_toggle.text = "Include editable creator project"
	_creator_toggle.button_pressed = true
	form.add_child(_creator_toggle)
	_install_toggle = CheckBox.new()
	_install_toggle.text = "Install to Local EMS for testing"
	_install_toggle.button_pressed = true
	form.add_child(_install_toggle)
	var note := Label.new()
	note.text = "Exports write a Workshop-ready folder to user://ems/exports/. Installing also copies the validated pack into user://ems/local/ so it appears in Loadouts."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form.add_child(note)

	var separator := HSeparator.new()
	root.add_child(separator)
	_footer_bar = HBoxContainer.new()
	_footer_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_footer_bar.add_theme_constant_override("separation", 10)
	root.add_child(_footer_bar)
	var footer_spacer := Control.new()
	footer_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_footer_bar.add_child(footer_spacer)
	_cancel_button = Button.new()
	_cancel_button.text = "CANCEL"
	_cancel_button.custom_minimum_size = Vector2(120, 34)
	_footer_bar.add_child(_cancel_button)
	_export_button = Button.new()
	_export_button.text = "EXPORT"
	_export_button.custom_minimum_size = Vector2(120, 34)
	_footer_bar.add_child(_export_button)

	_title_edit.text_changed.connect(_on_title_changed)
	confirmed.connect(_on_confirmed)
	_cancel_button.pressed.connect(hide)
	_export_button.pressed.connect(_on_confirmed)
	HDTheme.apply_dialog(self)


func set_metadata(metadata: Dictionary) -> void:
	if _title_edit == null:
		return
	_title_edit.text = str(metadata.get("title", "Creator EMS"))
	_pack_id_edit.text = EMSValidator.sanitize_pack_id(str(metadata.get("pack_id", _title_edit.text)))
	_author_edit.text = str(metadata.get("author", "Player"))
	_description_edit.text = str(metadata.get("description", "Created in the Harmonic Drive EMS Creator."))
	_tags_edit.text = ", ".join(_string_array(metadata.get("tags", ["EMS", "Custom"])))
	_creator_toggle.button_pressed = bool(metadata.get("include_creator_project", true))
	_install_toggle.button_pressed = bool(metadata.get("install_local", true))


func get_export_details() -> Dictionary:
	var pack_title := _clean_text(_title_edit.text, "Creator EMS")
	var pack_id := EMSValidator.sanitize_pack_id(_pack_id_edit.text)
	if pack_id.is_empty():
		pack_id = EMSValidator.sanitize_pack_id(pack_title)
	if pack_id.is_empty():
		pack_id = "creator_ems"
	return {
		"title": pack_title,
		"pack_id": pack_id,
		"author": _clean_text(_author_edit.text, "Player"),
		"description": _clean_text(_description_edit.text, "Created in the Harmonic Drive EMS Creator."),
		"tags": _tags(),
		"include_creator_project": _creator_toggle.button_pressed,
		"install_local": _install_toggle.button_pressed,
	}


func set_export_details_for_test(details: Dictionary) -> void:
	set_metadata(details)
	if _creator_toggle != null:
		_creator_toggle.button_pressed = bool(details.get("include_creator_project", true))
	if _install_toggle != null:
		_install_toggle.button_pressed = bool(details.get("install_local", true))


func get_debug_state() -> Dictionary:
	return {
		"has_title": _title_edit != null,
		"has_pack_id": _pack_id_edit != null,
		"has_author": _author_edit != null,
		"has_description": _description_edit != null,
		"has_tags": _tags_edit != null,
		"include_creator_project": _creator_toggle != null and _creator_toggle.button_pressed,
		"install_local": _install_toggle != null and _install_toggle.button_pressed,
		"body_scrollable": _content_scroll != null,
		"has_footer": _footer_bar != null,
		"has_footer_cancel": _cancel_button != null and _cancel_button.visible,
		"has_footer_export": _export_button != null and _export_button.visible,
	}


func _line_edit(label_text: String, placeholder: String, root: VBoxContainer) -> LineEdit:
	var label := Label.new()
	label.text = label_text
	root.add_child(label)
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	root.add_child(edit)
	return edit


func _on_title_changed(value: String) -> void:
	if _pack_id_edit == null or not _pack_id_edit.text.strip_edges().is_empty():
		return
	_pack_id_edit.text = EMSValidator.sanitize_pack_id(value)


func _on_confirmed() -> void:
	export_requested.emit(get_export_details())


func _tags() -> Array[String]:
	var out: Array[String] = []
	for part in _tags_edit.text.split(",", false):
		var tag := str(part).strip_edges()
		if not tag.is_empty() and not out.has(tag):
			out.append(tag)
	if out.is_empty():
		out = ["EMS", "Custom"]
	return out


func _string_array(value: Variant) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for item in value:
			out.append(str(item))
	return out


func _clean_text(value: String, fallback: String) -> String:
	var text := value.strip_edges().replace("\n", " ").replace("\r", " ").replace("\t", " ")
	while text.contains("  "):
		text = text.replace("  ", " ")
	return fallback if text.is_empty() else text
