extends VBoxContainer
class_name EMSTimelinePanel

signal events_changed(events: Array[Dictionary])

const EMSValidator = preload("res://systems/ems/EMSValidator.gd")
const HDTheme = preload("res://scripts/ui/HDTheme.gd")

const EVENT_LABELS := {
	"song_started": "Song Started",
	"song_section_changed": "Song Section Changed",
	"chart_reactive": "Chart Reactive",
	"audio_reactive": "Audio Reactive",
	"beat": "Beat (BPM)",
	"bass_hit": "Bass Hit",
	"combo_changed": "Combo Changed",
	"combo_milestone": "Combo Milestone",
	"miss": "Miss",
	"near_miss": "Near Miss",
	"player_hit": "Player Hit",
	"player_miss": "Player Miss",
	"fever_started": "Fever Started",
	"fever_ended": "Fever Ended",
	"song_ended": "Song Ended",
}

var _events: Array[Dictionary] = []
var _target_ids: Array[String] = ["*"]
var _rule_dialog: ConfirmationDialog
var _editing_index := -1
var _last_prefill_event := ""
var _event_option: OptionButton
var _action_option: OptionButton
var _target_option: OptionButton
var _threshold_spin: SpinBox
var _cooldown_spin: SpinBox
var _opacity_spin: SpinBox
var _duration_spin: SpinBox
var _scale_spin: SpinBox
var _amount_spin: SpinBox
var _count_spin: SpinBox
var _color_picker: ColorPickerButton
var _palette_color_picker: ColorPickerButton
var _scroll: ScrollContainer
var _rows: VBoxContainer


func set_events(events: Array[Dictionary], target_ids: Array = ["*"]) -> void:
	_events = events.duplicate(true)
	_target_ids.clear()
	for target in target_ids:
		_target_ids.append(str(target))
	if not _target_ids.has("*"):
		_target_ids.insert(0, "*")
	_rebuild()


func get_events() -> Array[Dictionary]:
	return _events.duplicate(true)


func get_debug_state() -> Dictionary:
	return {
		"event_count": _events.size(),
		"target_count": _target_ids.size(),
		"has_dialog": _rule_dialog != null,
		"has_add_new_rule": _has_button_text(self, "ADD RULE"),
		"has_chart_reactive_event": _event_option_has_value("chart_reactive"),
		"has_audio_reactive_event": _event_option_has_value("audio_reactive"),
		"last_prefill_event": _last_prefill_event,
		"prefill_dialog_visible": _rule_dialog != null and _rule_dialog.visible,
		"scrollable": _scroll != null,
		"horizontal_scrollable": _scroll != null and _scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED,
	}


func add_rule_for_test(rule: Dictionary) -> void:
	_events.append(rule.duplicate(true))
	_emit_events_changed()


func open_prefilled_rule(rule: Dictionary) -> void:
	_last_prefill_event = str(rule.get("event", ""))
	_open_rule_dialog(-1, rule)


func _rebuild() -> void:
	add_theme_constant_override("separation", 3)
	for child in get_children():
		if child != _rule_dialog:
			child.queue_free()
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 4)
	var title := Label.new()
	title.text = "EVENT RULES"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var add := Button.new()
	add.text = "ADD RULE"
	add.custom_minimum_size = Vector2(84, 24)
	add.pressed.connect(func(): _open_rule_dialog(-1))
	header.add_child(add)
	add_child(header)
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size.y = 112
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	add_child(_scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 2)
	_scroll.add_child(_rows)
	if _events.is_empty():
		var empty := Label.new()
		empty.text = "No event rules configured."
		_rows.add_child(empty)
	for i in range(_events.size()):
		_rows.add_child(_build_rule_row(i, _events[i] as Dictionary))
	_ensure_rule_dialog()


func _build_rule_row(index: int, rule: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label := Label.new()
	label.text = _rule_summary(rule)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.tooltip_text = label.text
	row.add_child(label)
	var edit := Button.new()
	edit.text = "EDIT"
	edit.custom_minimum_size = Vector2(42, 23)
	edit.pressed.connect(func(): _open_rule_dialog(index))
	row.add_child(edit)
	var duplicate := Button.new()
	duplicate.text = "DUP"
	duplicate.custom_minimum_size = Vector2(42, 23)
	duplicate.pressed.connect(func(): _duplicate_rule(index))
	row.add_child(duplicate)
	var remove := Button.new()
	remove.text = "REMOVE"
	remove.custom_minimum_size = Vector2(58, 23)
	remove.pressed.connect(func(): _remove_rule(index))
	row.add_child(remove)
	return row


func _ensure_rule_dialog() -> void:
	if _rule_dialog != null:
		return
	_rule_dialog = ConfirmationDialog.new()
	_rule_dialog.title = "Event Rule"
	_rule_dialog.ok_button_text = "Accept"
	_rule_dialog.cancel_button_text = "Cancel"
	_rule_dialog.exclusive = false
	_rule_dialog.confirmed.connect(_commit_rule_dialog)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	_event_option = _event_option_control()
	_action_option = _option(EMSValidator.ALLOWED_ACTIONS)
	_action_option.item_selected.connect(func(_index: int): _sync_action_param_visibility())
	_target_option = _option(_target_ids)
	_threshold_spin = _spin(0.0, 1.0, 0.01)
	_cooldown_spin = _spin(0.0, 30.0, 0.05)
	_opacity_spin = _spin(0.0, 1.0, 0.01)
	_duration_spin = _spin(0.02, 8.0, 0.01)
	_scale_spin = _spin(0.1, 4.0, 0.01)
	_amount_spin = _spin(0.0, 1.0, 0.01)
	_count_spin = _spin(0.0, float(EMSValidator.MAX_PARTICLES_PER_LAYER), 1.0)
	_color_picker = ColorPickerButton.new()
	_palette_color_picker = ColorPickerButton.new()
	for pair in [
		["Event", _event_option],
		["Action", _action_option],
		["Target", _target_option],
		["Threshold", _threshold_spin],
		["Cooldown", _cooldown_spin],
		["Opacity", _opacity_spin],
		["Duration", _duration_spin],
		["Scale", _scale_spin],
		["Amount", _amount_spin],
		["Particle Count", _count_spin],
		["Color", _color_picker],
		["Palette Color", _palette_color_picker],
	]:
		var label := Label.new()
		label.text = str(pair[0])
		grid.add_child(label)
		grid.add_child(pair[1] as Control)
	root.add_child(grid)
	_rule_dialog.add_child(root)
	add_child(_rule_dialog)
	HDTheme.apply_dialog(_rule_dialog)


func _open_rule_dialog(index: int, preset_rule: Dictionary = {}) -> void:
	_ensure_rule_dialog()
	_editing_index = index
	_refresh_target_option()
	var rule := _default_rule()
	if index >= 0 and index < _events.size():
		rule = (_events[index] as Dictionary).duplicate(true)
	elif not preset_rule.is_empty():
		rule = preset_rule.duplicate(true)
	_select_option_text(_event_option, str(rule.get("event", "beat")))
	_select_option_text(_action_option, str(rule.get("action", "pulse_opacity")))
	_select_option_text(_target_option, str(rule.get("target", "*")))
	_threshold_spin.value = float(rule.get("threshold", 0.0))
	_cooldown_spin.value = float(rule.get("cooldown", 0.0))
	var params: Dictionary = rule.get("params", {}) as Dictionary
	_opacity_spin.value = float(params.get("opacity", 0.95))
	_duration_spin.value = float(params.get("duration", 0.18))
	_scale_spin.value = float(params.get("scale", 1.2))
	_amount_spin.value = float(params.get("amount", 0.2))
	_count_spin.value = float(params.get("count", 24))
	_color_picker.color = _color_from_hex(str(params.get("color", "#55DFFFFF")))
	var colors: Array = params.get("colors", ["#55DFFFFF"]) as Array
	_palette_color_picker.color = _color_from_hex(str(colors[0] if not colors.is_empty() else "#55DFFFFF"))
	_sync_action_param_visibility()
	_rule_dialog.popup_centered(Vector2i(560, 560))


func _commit_rule_dialog() -> void:
	var rule := {
		"event": _selected_option_value(_event_option),
		"action": _selected_option_value(_action_option),
		"target": _selected_option_value(_target_option),
		"params": _params_for_action(_selected_option_value(_action_option)),
		"threshold": float(_threshold_spin.value),
		"cooldown": float(_cooldown_spin.value),
	}
	if _editing_index >= 0 and _editing_index < _events.size():
		_events[_editing_index] = rule
	else:
		_events.append(rule)
	_emit_events_changed()


func _params_for_action(action: String) -> Dictionary:
	match action:
		"set_opacity", "pulse_opacity":
			return {"opacity": float(_opacity_spin.value), "duration": float(_duration_spin.value)}
		"set_color":
			return {"color": "#%s" % _color_picker.color.to_html(true)}
		"pulse_scale":
			return {"scale": float(_scale_spin.value), "duration": float(_duration_spin.value)}
		"burst_particles":
			return {"count": int(_count_spin.value)}
		"increase_bloom", "increase_distortion", "shake_camera":
			return {"amount": float(_amount_spin.value)}
		"transition_palette":
			return {"colors": ["#%s" % _palette_color_picker.color.to_html(true)]}
		_:
			return {}


func _sync_action_param_visibility() -> void:
	if _action_option == null:
		return
	var action := _selected_option_value(_action_option)
	var show_opacity := action in ["set_opacity", "pulse_opacity"]
	var show_duration := action in ["pulse_opacity", "pulse_scale"]
	var show_scale := action == "pulse_scale"
	var show_amount := action in ["increase_bloom", "increase_distortion", "shake_camera"]
	var show_count := action == "burst_particles"
	var show_color := action == "set_color"
	var show_palette := action == "transition_palette"
	_set_row_visible(_opacity_spin, show_opacity)
	_set_row_visible(_duration_spin, show_duration)
	_set_row_visible(_scale_spin, show_scale)
	_set_row_visible(_amount_spin, show_amount)
	_set_row_visible(_count_spin, show_count)
	_set_row_visible(_color_picker, show_color)
	_set_row_visible(_palette_color_picker, show_palette)


func _set_row_visible(control: Control, visible_value: bool) -> void:
	if control == null:
		return
	control.visible = visible_value
	var index := control.get_index()
	if index > 0:
		var label := control.get_parent().get_child(index - 1)
		if label is Control:
			(label as Control).visible = visible_value


func _duplicate_rule(index: int) -> void:
	if index >= 0 and index < _events.size():
		_events.insert(index + 1, (_events[index] as Dictionary).duplicate(true))
	_emit_events_changed()


func _remove_rule(index: int) -> void:
	if index >= 0 and index < _events.size():
		_events.remove_at(index)
	_emit_events_changed()


func _emit_events_changed() -> void:
	events_changed.emit(_events.duplicate(true))
	_rebuild()


func _refresh_target_option() -> void:
	if _target_option == null:
		return
	_target_option.clear()
	for target in _target_ids:
		_target_option.add_item(target)


func _default_rule() -> Dictionary:
	return {
		"event": "chart_reactive",
		"action": "pulse_opacity",
		"target": "*",
		"params": {"opacity": 0.95, "duration": 0.18},
		"threshold": 0.0,
		"cooldown": 0.0,
	}


func _rule_summary(rule: Dictionary) -> String:
	var target := str(rule.get("target", "*"))
	var threshold := float(rule.get("threshold", 0.0))
	var cooldown := float(rule.get("cooldown", 0.0))
	return "%s -> %s on %s  threshold %.2f  cooldown %.2fs" % [
		_event_display_name(str(rule.get("event", ""))),
		str(rule.get("action", "")),
		target,
		threshold,
		cooldown,
	]


func _option(values: Array) -> OptionButton:
	var option := OptionButton.new()
	for value in values:
		var index := option.get_item_count()
		option.add_item(str(value))
		option.set_item_metadata(index, str(value))
	return option


func _event_option_control() -> OptionButton:
	var option := OptionButton.new()
	for event_name in EMSValidator.ALLOWED_EVENTS:
		var index := option.get_item_count()
		option.add_item(_event_display_name(str(event_name)))
		option.set_item_metadata(index, str(event_name))
	return option


func _spin(min_value: float, max_value: float, step: float) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = step
	spin.custom_minimum_size = Vector2(118, 24)
	return spin


func _select_option_text(option: OptionButton, value: String) -> void:
	for i in range(option.get_item_count()):
		var meta: Variant = option.get_item_metadata(i)
		if str(meta) == value or option.get_item_text(i) == value:
			option.select(i)
			return
	if option.get_item_count() > 0:
		option.select(0)


func _selected_option_value(option: OptionButton) -> String:
	if option == null or option.selected < 0:
		return ""
	var meta: Variant = option.get_item_metadata(option.selected)
	if meta != null:
		return str(meta)
	return option.get_item_text(option.selected)


func _event_display_name(event_name: String) -> String:
	if EVENT_LABELS.has(event_name):
		return str(EVENT_LABELS[event_name])
	return event_name.replace("_", " ").capitalize()


func _event_option_has_value(event_name: String) -> bool:
	if _event_option == null:
		return false
	for i in range(_event_option.get_item_count()):
		if str(_event_option.get_item_metadata(i)) == event_name:
			return true
	return false


func _has_button_text(node: Node, text: String) -> bool:
	if node is Button and (node as Button).text == text:
		return true
	for child in node.get_children():
		if _has_button_text(child, text):
			return true
	return false


func _color_from_hex(value: String) -> Color:
	var hex := value.strip_edges()
	if hex.begins_with("#"):
		hex = hex.substr(1)
	if hex.length() == 6:
		hex += "FF"
	if hex.length() != 8:
		return Color(0.33, 0.87, 1.0, 1.0)
	return Color(
		float(hex.substr(0, 2).hex_to_int()) / 255.0,
		float(hex.substr(2, 2).hex_to_int()) / 255.0,
		float(hex.substr(4, 2).hex_to_int()) / 255.0,
		float(hex.substr(6, 2).hex_to_int()) / 255.0
	)
