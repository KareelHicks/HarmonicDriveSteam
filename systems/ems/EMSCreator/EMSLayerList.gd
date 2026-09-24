extends VBoxContainer
class_name EMSLayerList

signal add_layer_requested
signal create_layer_type_requested
signal duplicate_layer_requested(index: int)
signal delete_layer_requested(index: int)
signal move_layer_requested(index: int, direction: int)
signal layer_selected(index: int)

var _layers: Array[Dictionary] = []
var _selected_index := -1
var _scroll: ScrollContainer
var _rows: VBoxContainer

const ICON_MOVE_UP := "^"
const ICON_MOVE_DOWN := "v"
const ICON_DUPLICATE := "+"
const ICON_DELETE := "x"


func set_layers(layers: Array[Dictionary], selected_index: int = -1) -> void:
	_layers = layers.duplicate(true)
	_selected_index = selected_index
	_rebuild()


func get_debug_state() -> Dictionary:
	return {
		"layer_count": _layers.size(),
		"selected_index": _selected_index,
		"scrollable": _scroll != null,
		"row_count": _rows.get_child_count() if _rows != null else 0,
		"first_row_action_texts": _first_row_action_texts(),
		"first_row_action_tooltips": _first_row_action_tooltips(),
	}


func _rebuild() -> void:
	for child in get_children():
		child.queue_free()
	var header := Label.new()
	header.text = "LAYERS"
	add_child(header)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 3)
	var add_button := Button.new()
	add_button.text = "ADD LAYER"
	add_button.clip_text = true
	add_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_button.custom_minimum_size = Vector2(78, 22)
	add_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_button.pressed.connect(func(): add_layer_requested.emit())
	buttons.add_child(add_button)
	var create_button := Button.new()
	create_button.text = "CREATE TYPE"
	create_button.clip_text = true
	create_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	create_button.custom_minimum_size = Vector2(86, 22)
	create_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	create_button.pressed.connect(func(): create_layer_type_requested.emit())
	buttons.add_child(create_button)
	add_child(buttons)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 3)
	_scroll.add_child(_rows)
	for i in range(_layers.size()):
		_rows.add_child(_build_layer_row(i, _layers[i] as Dictionary))


func _build_layer_row(index: int, layer: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	var select := Button.new()
	select.text = "%s%s" % ["* " if index == _selected_index else "", str(layer.get("name", layer.get("id", "Layer")))]
	select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	select.custom_minimum_size = Vector2(80, 22)
	select.clip_text = true
	select.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	select.tooltip_text = "%s / %s" % [str(layer.get("id", "")), str(layer.get("type", ""))]
	select.pressed.connect(func(): layer_selected.emit(index))
	row.add_child(select)
	for spec in [
		{"text": ICON_MOVE_UP, "tooltip": "Move Up", "dir": -1},
		{"text": ICON_MOVE_DOWN, "tooltip": "Move Down", "dir": 1},
	]:
		var move := Button.new()
		move.text = str(spec.get("text", ""))
		move.tooltip_text = str(spec.get("tooltip", ""))
		move.custom_minimum_size = Vector2(24, 22)
		move.clip_text = true
		move.disabled = index + int(spec.get("dir", 0)) < 0 or index + int(spec.get("dir", 0)) >= _layers.size()
		move.pressed.connect(func(direction := int(spec.get("dir", 0))): move_layer_requested.emit(index, direction))
		row.add_child(move)
	var dup := Button.new()
	dup.text = ICON_DUPLICATE
	dup.tooltip_text = "Duplicate"
	dup.custom_minimum_size = Vector2(24, 22)
	dup.clip_text = true
	dup.pressed.connect(func(): duplicate_layer_requested.emit(index))
	row.add_child(dup)
	var del := Button.new()
	del.text = ICON_DELETE
	del.tooltip_text = "Delete"
	del.custom_minimum_size = Vector2(24, 22)
	del.clip_text = true
	del.disabled = _layers.size() <= 1
	del.pressed.connect(func(): delete_layer_requested.emit(index))
	row.add_child(del)
	return row


func _first_row_action_texts() -> Array[String]:
	var texts: Array[String] = []
	if _rows == null or _rows.get_child_count() <= 0:
		return texts
	var row := _rows.get_child(0)
	for index in range(1, row.get_child_count()):
		var child := row.get_child(index)
		if child is Button:
			texts.append((child as Button).text)
	return texts


func _first_row_action_tooltips() -> Array[String]:
	var tooltips: Array[String] = []
	if _rows == null or _rows.get_child_count() <= 0:
		return tooltips
	var row := _rows.get_child(0)
	for index in range(1, row.get_child_count()):
		var child := row.get_child(index)
		if child is Button:
			tooltips.append((child as Button).tooltip_text)
	return tooltips
