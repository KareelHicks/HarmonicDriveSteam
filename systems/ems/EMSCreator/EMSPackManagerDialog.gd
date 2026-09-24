extends AcceptDialog
class_name EMSPackManagerDialog

signal load_pack_requested(folder_path: String)
signal delete_pack_requested(folder_path: String)

const EMSPackLoader = preload("res://systems/ems/EMSPackLoader.gd")
const HDTheme = preload("res://scripts/ui/HDTheme.gd")

var _entries: Array[Dictionary] = []
var _list: ItemList
var _actions: HBoxContainer
var _load_button: Button
var _delete_button: Button
var _status: Label
var _delete_confirm: ConfirmationDialog
var _pending_delete_path := ""


func _ready() -> void:
	title = "Manage Custom EMS Packs"
	ok_button_text = "CLOSE"
	min_size = Vector2i(860, 600)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	add_child(root)
	var intro := Label.new()
	intro.text = "Load a custom EMS pack back into the Creator, or delete saved Local/Export packs."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(intro)
	_actions = HBoxContainer.new()
	_actions.add_theme_constant_override("separation", 8)
	var refresh_button := Button.new()
	refresh_button.text = "REFRESH"
	refresh_button.custom_minimum_size = Vector2(140, 44)
	refresh_button.pressed.connect(refresh_packs)
	_actions.add_child(refresh_button)
	_load_button = Button.new()
	_load_button.text = "LOAD SELECTED"
	_load_button.custom_minimum_size = Vector2(190, 44)
	_load_button.pressed.connect(_load_selected)
	_actions.add_child(_load_button)
	_delete_button = Button.new()
	_delete_button.text = "DELETE SELECTED"
	_delete_button.custom_minimum_size = Vector2(190, 44)
	_delete_button.pressed.connect(_confirm_delete_selected)
	_actions.add_child(_delete_button)
	root.add_child(_actions)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status)
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(780, 300)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(func(_index: int): _refresh_buttons())
	_list.item_activated.connect(func(_index: int): _load_selected())
	root.add_child(_list)
	_delete_confirm = ConfirmationDialog.new()
	_delete_confirm.title = "Delete EMS Pack"
	_delete_confirm.ok_button_text = "DELETE"
	_delete_confirm.cancel_button_text = "CANCEL"
	_delete_confirm.confirmed.connect(_delete_confirmed)
	add_child(_delete_confirm)
	HDTheme.apply_dialog(self)
	HDTheme.apply_dialog(_delete_confirm)
	refresh_packs()


func refresh_packs() -> void:
	_entries = EMSPackLoader.scan_created_packs()
	_list.clear()
	for entry in _entries:
		_list.add_item(_entry_label(entry))
	if _entries.is_empty():
		_status.text = "No custom EMS packs found in user://ems/local/ or user://ems/exports/."
	else:
		_status.text = "%d custom EMS pack%s found." % [_entries.size(), "" if _entries.size() == 1 else "s"]
	_refresh_buttons()


func get_debug_state() -> Dictionary:
	return {
		"count": _entries.size(),
		"actions_before_list": _actions != null and _actions.get_index() < _list.get_index(),
		"has_load": _load_button != null,
		"has_delete": _delete_button != null,
		"load_visible": _load_button != null and _load_button.visible,
		"delete_visible": _delete_button != null and _delete_button.visible,
		"status": _status.text if _status != null else "",
	}


func select_pack_for_test(pack_id: String, source: String = "") -> bool:
	for i in range(_entries.size()):
		var entry := _entries[i]
		if str(entry.get("pack_id", "")) == pack_id and (source.is_empty() or str(entry.get("source", "")) == source):
			_list.select(i)
			_refresh_buttons()
			return true
	return false


func select_folder_for_test(folder_path: String) -> bool:
	for i in range(_entries.size()):
		var entry := _entries[i]
		if str(entry.get("folder_path", "")) == folder_path:
			_list.select(i)
			_refresh_buttons()
			return true
	return false


func get_selected_folder_for_test() -> String:
	var entry := _selected_entry()
	return str(entry.get("folder_path", ""))


func _entry_label(entry: Dictionary) -> String:
	var status := str(entry.get("validation_status", "valid")).to_upper()
	var source := str(entry.get("source", "local")).to_upper()
	var title_text := str(entry.get("display_name", entry.get("pack_id", "EMS Pack")))
	var author := str(entry.get("author", "Unknown"))
	var pack_type := str(entry.get("pack_type", "")).replace("_", " ").to_upper()
	var folder := str(entry.get("folder_path", ""))
	return "%s  -  %s  [%s / %s / %s]  %s" % [title_text, author, source, pack_type, status, folder]


func _refresh_buttons() -> void:
	var selected := not _selected_entry().is_empty()
	if _load_button != null:
		_load_button.disabled = not selected
	if _delete_button != null:
		_delete_button.disabled = not selected


func _selected_entry() -> Dictionary:
	if _list == null:
		return {}
	var selected := _list.get_selected_items()
	if selected.is_empty():
		return {}
	var index := int(selected[0])
	if index < 0 or index >= _entries.size():
		return {}
	return (_entries[index] as Dictionary).duplicate(true)


func _load_selected() -> void:
	var entry := _selected_entry()
	var folder := str(entry.get("folder_path", ""))
	if folder.is_empty():
		return
	load_pack_requested.emit(folder)
	hide()


func _confirm_delete_selected() -> void:
	var entry := _selected_entry()
	_pending_delete_path = str(entry.get("folder_path", ""))
	if _pending_delete_path.is_empty():
		return
	_delete_confirm.dialog_text = "Delete this EMS pack?\n\n%s\n\nThis removes the pack folder from disk." % _pending_delete_path
	_delete_confirm.popup_centered(Vector2i(620, 220))


func _delete_confirmed() -> void:
	if _pending_delete_path.is_empty():
		return
	delete_pack_requested.emit(_pending_delete_path)
	_pending_delete_path = ""
