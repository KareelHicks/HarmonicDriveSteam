extends Control
class_name EMSCreatorController

signal back_requested

const EMSPackLoader = preload("res://systems/ems/EMSPackLoader.gd")
const EMSValidator = preload("res://systems/ems/EMSValidator.gd")
const EMSWorkshopManager = preload("res://systems/ems/EMSWorkshopManager.gd")
const EMSLayerList = preload("res://systems/ems/EMSCreator/EMSLayerList.gd")
const EMSPropertyPanel = preload("res://systems/ems/EMSCreator/EMSPropertyPanel.gd")
const EMSPreviewViewport = preload("res://systems/ems/EMSCreator/EMSPreviewViewport.gd")
const EMSTimelinePanel = preload("res://systems/ems/EMSCreator/EMSTimelinePanel.gd")
const EMSExportDialog = preload("res://systems/ems/EMSCreator/EMSExportDialog.gd")
const EMSWorkshopUploadDialog = preload("res://systems/ems/EMSCreator/EMSWorkshopUploadDialog.gd")
const EMSLayerTypeBuilderDialog = preload("res://systems/ems/EMSCreator/EMSLayerTypeBuilderDialog.gd")
const EMSPackManagerDialog = preload("res://systems/ems/EMSCreator/EMSPackManagerDialog.gd")
const EMSLayerTemplateStore = preload("res://systems/ems/EMSCreator/EMSLayerTemplateStore.gd")
const HDTheme = preload("res://scripts/ui/HDTheme.gd")

const CREATOR_FONT_SIZE := 12
const CREATOR_SMALL_FONT_SIZE := 10
const CREATOR_TITLE_FONT_SIZE := 15
const CREATOR_CONTROL_HEIGHT := 22.0
const SIDE_PANEL_WIDTH := 214.0
const PROPERTY_PANEL_WIDTH := 220.0
const CENTER_PANEL_MIN_WIDTH := 320.0
const TIMELINE_PANEL_HEIGHT := 170.0
const SIDE_PANEL_MIN_WIDTH := 196.0
const PROPERTY_PANEL_MIN_WIDTH := 176.0
const RESIZE_HANDLE_WIDTH := 8.0

var _layers: Array[Dictionary] = []
var _events: Array[Dictionary] = []
var _layout := {
	"background_region": "gutters",
	"position": [0.5, 0.5],
	"size": [1.0, 1.0],
	"scale": 1.0,
	"rotation": 0.0,
}
var _selected_index := -1
var _layer_list: EMSLayerList
var _property_panel: EMSPropertyPanel
var _property_scroll: ScrollContainer
var _preview: EMSPreviewViewport
var _timeline: EMSTimelinePanel
var _vertical_split: VSplitContainer
var _main_row: HBoxContainer
var _layer_panel_container: PanelContainer
var _property_panel_container: PanelContainer
var _layer_resize_handle: Control
var _property_resize_handle: Control
var _status: Label
var _status_panel: PanelContainer
var _performance: Label
var _simulation_status: Label
var _export_dialog: EMSExportDialog
var _workshop_upload_dialog: EMSWorkshopUploadDialog
var _layer_builder_dialog: EMSLayerTypeBuilderDialog
var _pack_manager_dialog: EMSPackManagerDialog
var _workshop_manager := EMSWorkshopManager.new()
var _layer_template_store := EMSLayerTemplateStore.new()
var _custom_layer_templates: Array[Dictionary] = []
var _action_buttons: Array[Button] = []
var _preview_playing := true
var _layout_scope := "pack"
var _layout_scope_option: OptionButton
var _layout_region_option: OptionButton
var _layout_gutter_target_option: OptionButton
var _layout_mode_option: OptionButton
var _layout_reuse_source_option: OptionButton
var _layout_spinners: Dictionary = {}
var _updating_layout_controls := false
var _layer_stack_dialog: AcceptDialog
var _layer_stack_rows: VBoxContainer
var _layer_layout_dialog: ConfirmationDialog
var _layer_layout_mode_option: OptionButton
var _layer_layout_source_option: OptionButton
var _layer_layout_spinners: Dictionary = {}
var _layer_layout_edit_index := -1
var _layer_layout_draft := {}
var _updating_layer_layout_controls := false
var _loaded_pack_folder := ""
var _last_export_metadata := {
	"title": "Creator EMS",
	"pack_id": "creator_ems",
	"author": "Player",
	"description": "Created in the Harmonic Drive EMS Creator.",
	"tags": ["EMS", "Custom"],
	"include_creator_project": true,
	"install_local": true,
	"visibility": "public",
	"workshop_visibility": "public",
}
var _split_defaults_applied := false
var _layer_panel_width := SIDE_PANEL_WIDTH
var _property_panel_width := PROPERTY_PANEL_WIDTH
var _active_resize_handle := ""
var _resize_start_mouse_x := 0.0
var _resize_start_layer_width := SIDE_PANEL_WIDTH
var _resize_start_property_width := PROPERTY_PANEL_WIDTH


func _ready() -> void:
	_seed_default_project()
	_refresh_layer_templates()
	_build_ui()
	_refresh_all()


func _input(event: InputEvent) -> void:
	if _active_resize_handle.is_empty():
		return
	if event is InputEventMouseMotion:
		_apply_active_resize_drag(get_global_mouse_position().x)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_LEFT and not mouse_button.pressed:
			_active_resize_handle = ""
			get_viewport().set_input_as_handled()


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 4)
	add_child(root)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	root.add_child(header)
	var back_button := Button.new()
	back_button.text = "BACK TO MAIN MENU"
	back_button.custom_minimum_size = Vector2(142, 26)
	back_button.pressed.connect(func() -> void: back_requested.emit())
	header.add_child(back_button)
	var title := Label.new()
	title.text = "EMS CREATOR"
	title.add_theme_font_size_override("font_size", CREATOR_TITLE_FONT_SIZE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(title)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(142, 1)
	header.add_child(spacer)
	_vertical_split = VSplitContainer.new()
	_vertical_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_vertical_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vertical_split.dragging_enabled = true
	_vertical_split.add_theme_constant_override("separation", 8)
	root.add_child(_vertical_split)
	_main_row = HBoxContainer.new()
	_main_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_main_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_main_row.add_theme_constant_override("separation", 4)
	_vertical_split.add_child(_main_row)
	_layer_list = EMSLayerList.new()
	_layer_list.custom_minimum_size.x = SIDE_PANEL_WIDTH
	_layer_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_layer_list.add_layer_requested.connect(_add_layer)
	_layer_list.create_layer_type_requested.connect(_open_layer_type_builder)
	_layer_list.duplicate_layer_requested.connect(_duplicate_layer)
	_layer_list.delete_layer_requested.connect(_delete_layer)
	_layer_list.move_layer_requested.connect(_move_layer)
	_layer_list.layer_selected.connect(_select_layer)
	_layer_panel_container = _panel("Layer List", _layer_list)
	_layer_panel_container.size_flags_horizontal = Control.SIZE_FILL
	_layer_panel_container.custom_minimum_size.x = _layer_panel_width
	_main_row.add_child(_layer_panel_container)
	_layer_resize_handle = _resize_handle("layer")
	_main_row.add_child(_layer_resize_handle)
	var center := VBoxContainer.new()
	center.custom_minimum_size.x = CENTER_PANEL_MIN_WIDTH
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_theme_constant_override("separation", 4)
	_preview = EMSPreviewViewport.new()
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_child(_preview)
	center.add_child(_build_layout_controls())
	var sim_row := HFlowContainer.new()
	sim_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sim_row.add_theme_constant_override("h_separation", 4)
	sim_row.add_theme_constant_override("v_separation", 4)
	for spec in [
		{"text": "Preview", "event": ""},
		{"text": "Chart", "event": "chart_reactive"},
		{"text": "Audio", "event": "audio_reactive"},
		{"text": "Beat", "event": "beat"},
		{"text": "Combo", "event": "combo_milestone"},
		{"text": "Miss", "event": "miss"},
		{"text": "Section", "event": "song_section_changed"},
	]:
		var button := Button.new()
		button.text = str(spec.get("text", ""))
		button.custom_minimum_size = Vector2(76, CREATOR_CONTROL_HEIGHT)
		button.clip_text = true
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.pressed.connect(func(event := str(spec.get("event", ""))): _simulate(event))
		sim_row.add_child(button)
	center.add_child(sim_row)
	_simulation_status = Label.new()
	_simulation_status.text = "Preview playing."
	center.add_child(_simulation_status)
	_main_row.add_child(center)
	_property_resize_handle = _resize_handle("property")
	_main_row.add_child(_property_resize_handle)
	_property_panel = EMSPropertyPanel.new()
	_property_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_property_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_property_panel.layer_changed.connect(_on_layer_changed)
	_property_panel.reactivity_rule_requested.connect(_open_prefilled_event_rule)
	_property_panel.layer_layout_requested.connect(_open_layer_layout_dialog)
	_property_scroll = ScrollContainer.new()
	_property_scroll.custom_minimum_size.x = PROPERTY_PANEL_WIDTH
	_property_scroll.size_flags_horizontal = Control.SIZE_FILL
	_property_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_property_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_property_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_property_scroll.add_child(_property_panel)
	_property_panel_container = _panel("Properties", _property_scroll)
	_property_panel_container.size_flags_horizontal = Control.SIZE_FILL
	_property_panel_container.custom_minimum_size.x = _property_panel_width
	_main_row.add_child(_property_panel_container)
	_timeline = EMSTimelinePanel.new()
	_timeline.custom_minimum_size.y = 120
	_timeline.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_timeline.events_changed.connect(_on_events_changed)
	_vertical_split.add_child(_panel("Timeline", _timeline))
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 5)
	_action_buttons.clear()
	for spec in [
		{"text": "MANAGE PACKS", "method": "_show_pack_manager", "width": 122.0},
		{"text": "SAVE DRAFT", "method": "_save_draft", "width": 104.0},
		{"text": "EXPORT", "method": "_show_export", "width": 70.0},
		{"text": "UPLOAD TO WORKSHOP", "method": "_upload_to_workshop", "width": 166.0},
	]:
		var button := Button.new()
		button.text = str(spec.get("text", ""))
		button.custom_minimum_size = Vector2(float(spec.get("width", 80.0)), CREATOR_CONTROL_HEIGHT)
		button.clip_text = true
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.pressed.connect(Callable(self, str(spec.get("method", ""))))
		actions.add_child(button)
		_action_buttons.append(button)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.clip_text = false
	_status.custom_minimum_size = Vector2(0, 30)
	_status_panel = _build_status_panel()
	root.add_child(_status_panel)
	_performance = Label.new()
	_performance.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(_performance)
	root.add_child(actions)
	_export_dialog = EMSExportDialog.new()
	_export_dialog.export_requested.connect(_export_pack)
	add_child(_export_dialog)
	_workshop_upload_dialog = EMSWorkshopUploadDialog.new()
	_workshop_upload_dialog.upload_requested.connect(_upload_to_workshop_with_details)
	add_child(_workshop_upload_dialog)
	_workshop_manager.upload_status_changed.connect(_on_workshop_upload_status_changed)
	_layer_builder_dialog = EMSLayerTypeBuilderDialog.new()
	_layer_builder_dialog.layer_created.connect(_on_layer_type_created)
	_layer_builder_dialog.template_saved.connect(_on_layer_template_saved)
	add_child(_layer_builder_dialog)
	_pack_manager_dialog = EMSPackManagerDialog.new()
	_pack_manager_dialog.load_pack_requested.connect(_load_creator_pack)
	_pack_manager_dialog.delete_pack_requested.connect(_delete_creator_pack)
	add_child(_pack_manager_dialog)
	_build_layer_stack_dialog()
	_build_layer_layout_dialog()
	_apply_compact_style(self)
	call_deferred("_apply_default_split_offsets")


func _panel(_title: String, content: Control) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = content.size_flags_horizontal
	panel.size_flags_vertical = content.size_flags_vertical
	panel.add_theme_stylebox_override("panel", _panel_style())
	panel.add_child(content)
	return panel


func _build_status_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(0, 36)
	panel.add_theme_stylebox_override("panel", _status_panel_style())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	panel.add_child(row)
	row.add_child(_label_badge("STATUS", 64.0))
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_status)
	return panel


func _resize_handle(handle_id: String) -> PanelContainer:
	var handle := PanelContainer.new()
	handle.custom_minimum_size = Vector2(RESIZE_HANDLE_WIDTH, 1)
	handle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	handle.mouse_default_cursor_shape = Control.CURSOR_HSIZE
	handle.tooltip_text = "Drag to resize panel"
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.30, 0.78, 1.0, 0.30)
	style.border_color = Color(0.70, 0.92, 1.0, 0.52)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	handle.add_theme_stylebox_override("panel", style)
	handle.gui_input.connect(func(event: InputEvent): _on_resize_handle_input(event, handle_id))
	return handle


func _on_resize_handle_input(event: InputEvent, handle_id: String) -> void:
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index != MOUSE_BUTTON_LEFT:
			return
		if mouse_button.pressed:
			_active_resize_handle = handle_id
			_resize_start_mouse_x = get_global_mouse_position().x
			_resize_start_layer_width = _layer_panel_width
			_resize_start_property_width = _property_panel_width
			accept_event()
		elif _active_resize_handle == handle_id:
			_active_resize_handle = ""
			accept_event()
	elif event is InputEventMouseMotion and _active_resize_handle == handle_id:
		_apply_active_resize_drag(get_global_mouse_position().x)
		accept_event()


func _apply_active_resize_drag(mouse_x: float) -> void:
	var delta_x := mouse_x - _resize_start_mouse_x
	if _active_resize_handle == "layer":
		_set_layer_panel_width(_resize_start_layer_width + delta_x)
	elif _active_resize_handle == "property":
		_set_property_panel_width(_resize_start_property_width - delta_x)


func _set_layer_panel_width(value: float) -> void:
	var max_width := _max_layer_panel_width()
	_layer_panel_width = clampf(value, SIDE_PANEL_MIN_WIDTH, max_width)
	if is_instance_valid(_layer_panel_container):
		_layer_panel_container.custom_minimum_size.x = _layer_panel_width
	if is_instance_valid(_layer_list):
		_layer_list.custom_minimum_size.x = maxf(SIDE_PANEL_MIN_WIDTH, _layer_panel_width - 10.0)


func _set_property_panel_width(value: float) -> void:
	var max_width := _max_property_panel_width()
	_property_panel_width = clampf(value, PROPERTY_PANEL_MIN_WIDTH, max_width)
	if is_instance_valid(_property_panel_container):
		_property_panel_container.custom_minimum_size.x = _property_panel_width
	if is_instance_valid(_property_scroll):
		_property_scroll.custom_minimum_size.x = maxf(PROPERTY_PANEL_MIN_WIDTH, _property_panel_width - 10.0)


func _max_layer_panel_width() -> float:
	var available := _main_row.size.x if is_instance_valid(_main_row) and _main_row.size.x > 0.0 else size.x
	var reserved := _property_panel_width + CENTER_PANEL_MIN_WIDTH + RESIZE_HANDLE_WIDTH * 2.0 + 28.0
	return maxf(SIDE_PANEL_MIN_WIDTH, available - reserved)


func _max_property_panel_width() -> float:
	var available := _main_row.size.x if is_instance_valid(_main_row) and _main_row.size.x > 0.0 else size.x
	var reserved := _layer_panel_width + CENTER_PANEL_MIN_WIDTH + RESIZE_HANDLE_WIDTH * 2.0 + 28.0
	return maxf(PROPERTY_PANEL_MIN_WIDTH, available - reserved)


func _apply_default_split_offsets() -> void:
	if _split_defaults_applied:
		return
	if not is_instance_valid(_vertical_split) or not is_instance_valid(_main_row):
		call_deferred("_apply_default_split_offsets")
		return
	if _vertical_split.size.x <= 0.0 or _main_row.size.x <= 0.0:
		call_deferred("_apply_default_split_offsets")
		return
	_set_layer_panel_width(SIDE_PANEL_WIDTH)
	_set_property_panel_width(PROPERTY_PANEL_WIDTH)
	var split_height := _vertical_split.size.y
	_vertical_split.split_offset = int(maxf(260.0, split_height - TIMELINE_PANEL_HEIGHT))
	_split_defaults_applied = true


func _build_layout_controls() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 3)
	panel.add_child(root)
	var title_row := HFlowContainer.new()
	title_row.add_theme_constant_override("h_separation", 4)
	title_row.add_theme_constant_override("v_separation", 3)
	title_row.add_child(_label_badge("EMS LAYOUT", 94.0))
	_layout_scope_option = OptionButton.new()
	_layout_scope_option.custom_minimum_size = Vector2(138, CREATOR_CONTROL_HEIGHT)
	_layout_scope_option.add_item("EMS Layout")
	_layout_scope_option.set_item_metadata(0, "pack")
	_layout_scope_option.add_item("Selected Layer Layout")
	_layout_scope_option.set_item_metadata(1, "selected_layer")
	_layout_scope_option.item_selected.connect(_on_layout_scope_selected)
	title_row.add_child(_layout_scope_option)
	_layout_region_option = OptionButton.new()
	_layout_region_option.custom_minimum_size = Vector2(114, CREATOR_CONTROL_HEIGHT)
	_layout_region_option.add_item("Two Gutters")
	_layout_region_option.set_item_metadata(0, "gutters")
	_layout_region_option.add_item("Full Background")
	_layout_region_option.set_item_metadata(1, "full_background")
	_layout_region_option.item_selected.connect(_on_layout_region_selected)
	title_row.add_child(_layout_region_option)
	_layout_gutter_target_option = OptionButton.new()
	_layout_gutter_target_option.custom_minimum_size = Vector2(126, CREATOR_CONTROL_HEIGHT)
	_layout_gutter_target_option.add_item("Both Gutters")
	_layout_gutter_target_option.set_item_metadata(0, "both")
	_layout_gutter_target_option.add_item("Left Gutter Only")
	_layout_gutter_target_option.set_item_metadata(1, "left")
	_layout_gutter_target_option.add_item("Right Gutter Only")
	_layout_gutter_target_option.set_item_metadata(2, "right")
	_layout_gutter_target_option.item_selected.connect(_on_layout_gutter_target_selected)
	title_row.add_child(_layout_gutter_target_option)
	var stack_button := Button.new()
	stack_button.text = "STACK"
	stack_button.custom_minimum_size = Vector2(56, CREATOR_CONTROL_HEIGHT)
	stack_button.clip_text = true
	stack_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	stack_button.pressed.connect(_open_layer_stack_dialog)
	title_row.add_child(stack_button)
	root.add_child(title_row)
	var mode_row := HFlowContainer.new()
	mode_row.add_theme_constant_override("h_separation", 4)
	mode_row.add_theme_constant_override("v_separation", 3)
	mode_row.add_child(_label_badge("Mode", 52.0))
	_layout_mode_option = OptionButton.new()
	_layout_mode_option.custom_minimum_size = Vector2(132, CREATOR_CONTROL_HEIGHT)
	_layout_mode_option.add_item("Use EMS Layout")
	_layout_mode_option.set_item_metadata(0, "pack")
	_layout_mode_option.add_item("Custom Layout")
	_layout_mode_option.set_item_metadata(1, "custom")
	_layout_mode_option.add_item("Reuse Another Layer")
	_layout_mode_option.set_item_metadata(2, "reuse")
	_layout_mode_option.item_selected.connect(_on_panel_layer_layout_mode_selected)
	mode_row.add_child(_layout_mode_option)
	mode_row.add_child(_label_badge("Reuse", 52.0))
	_layout_reuse_source_option = OptionButton.new()
	_layout_reuse_source_option.custom_minimum_size = Vector2(146, CREATOR_CONTROL_HEIGHT)
	_layout_reuse_source_option.item_selected.connect(_on_panel_layer_reuse_source_selected)
	mode_row.add_child(_layout_reuse_source_option)
	root.add_child(mode_row)
	var grid := GridContainer.new()
	grid.columns = 12
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 2)
	_layout_spinners.clear()
	_add_layout_spin(grid, "position_x", "X", 0.0, 1.0, 0.01, 0.5, 24.0, 38.0)
	_add_layout_spin(grid, "position_y", "Y", 0.0, 1.0, 0.01, 0.5, 24.0, 38.0)
	_add_layout_spin(grid, "size_x", "W", 0.05, 2.0, 0.01, 1.0, 24.0, 38.0)
	_add_layout_spin(grid, "size_y", "H", 0.05, 2.0, 0.01, 1.0, 24.0, 38.0)
	_add_layout_spin(grid, "scale", "Scale", 0.10, 4.0, 0.01, 1.0, 34.0, 38.0)
	_add_layout_spin(grid, "rotation", "Rot", -360.0, 360.0, 1.0, 0.0, 30.0, 38.0)
	root.add_child(grid)
	return panel


func _add_layout_spin(parent: GridContainer, key: String, label_text: String, min_value: float, max_value: float, step: float, value: float, label_width: float = 44.0, spin_width: float = 58.0) -> void:
	parent.add_child(_label_badge(label_text, label_width))
	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = step
	spin.value = value
	spin.custom_minimum_size = Vector2(spin_width, CREATOR_CONTROL_HEIGHT)
	spin.value_changed.connect(func(next_value: float): _on_layout_number_changed(key, next_value))
	parent.add_child(spin)
	_layout_spinners[key] = spin


func _build_layer_stack_dialog() -> void:
	_layer_stack_dialog = AcceptDialog.new()
	_layer_stack_dialog.title = "Layer Stack Order"
	_layer_stack_dialog.ok_button_text = "Done"
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	var help := Label.new()
	help.text = "Layers at the top of this list draw in front of lower layers."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(help)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(520, 360)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_layer_stack_rows = VBoxContainer.new()
	_layer_stack_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_layer_stack_rows.add_theme_constant_override("separation", 4)
	scroll.add_child(_layer_stack_rows)
	root.add_child(scroll)
	_layer_stack_dialog.add_child(root)
	add_child(_layer_stack_dialog)
	HDTheme.apply_dialog(_layer_stack_dialog)


func _open_layer_stack_dialog() -> void:
	_refresh_layer_stack_rows()
	_layer_stack_dialog.popup_centered(Vector2i(620, 480))


func _refresh_layer_stack_rows() -> void:
	if not is_instance_valid(_layer_stack_rows):
		return
	for child in _layer_stack_rows.get_children():
		child.queue_free()
	for reverse_index in range(_layers.size() - 1, -1, -1):
		var layer := _layers[reverse_index] as Dictionary
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var position_label := Label.new()
		position_label.custom_minimum_size.x = 62
		if reverse_index == _layers.size() - 1:
			position_label.text = "TOP"
		elif reverse_index == 0:
			position_label.text = "BOTTOM"
		else:
			position_label.text = "#%d" % (reverse_index + 1)
		row.add_child(position_label)
		var name_label := Label.new()
		name_label.text = "%s  (%s)" % [str(layer.get("name", layer.get("id", "Layer"))), str(layer.get("id", ""))]
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.clip_text = true
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(name_label)
		var front_button := Button.new()
		front_button.text = "FRONT"
		front_button.custom_minimum_size = Vector2(74, 28)
		front_button.disabled = reverse_index >= _layers.size() - 1
		front_button.pressed.connect(func(index := reverse_index): _move_layer_from_stack(index, 1))
		row.add_child(front_button)
		var back_button := Button.new()
		back_button.text = "BACK"
		back_button.custom_minimum_size = Vector2(64, 28)
		back_button.disabled = reverse_index <= 0
		back_button.pressed.connect(func(index := reverse_index): _move_layer_from_stack(index, -1))
		row.add_child(back_button)
		_layer_stack_rows.add_child(row)


func _move_layer_from_stack(index: int, direction: int) -> void:
	_move_layer(index, direction)
	_refresh_layer_stack_rows()


func _build_layer_layout_dialog() -> void:
	_layer_layout_dialog = ConfirmationDialog.new()
	_layer_layout_dialog.title = "Layer EMS Layout"
	_layer_layout_dialog.ok_button_text = "Apply"
	_layer_layout_dialog.cancel_button_text = "Cancel"
	_layer_layout_dialog.confirmed.connect(_commit_layer_layout_dialog)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	_layer_layout_mode_option = OptionButton.new()
	_layer_layout_mode_option.add_item("Use EMS Layout")
	_layer_layout_mode_option.set_item_metadata(0, "pack")
	_layer_layout_mode_option.add_item("Custom Layout")
	_layer_layout_mode_option.set_item_metadata(1, "custom")
	_layer_layout_mode_option.add_item("Reuse Another Layer")
	_layer_layout_mode_option.set_item_metadata(2, "reuse")
	_layer_layout_mode_option.item_selected.connect(_on_layer_layout_mode_selected)
	root.add_child(_labeled_control("Layout Mode", _layer_layout_mode_option))
	_layer_layout_source_option = OptionButton.new()
	_layer_layout_source_option.item_selected.connect(_on_layer_layout_source_selected)
	root.add_child(_labeled_control("Reuse Layer", _layer_layout_source_option))
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 5)
	grid.add_theme_constant_override("v_separation", 3)
	_layer_layout_spinners.clear()
	_add_layer_layout_spin(grid, "position_x", "X", 0.0, 1.0, 0.01, 0.5)
	_add_layer_layout_spin(grid, "position_y", "Y", 0.0, 1.0, 0.01, 0.5)
	_add_layer_layout_spin(grid, "size_x", "W", 0.05, 2.0, 0.01, 1.0)
	_add_layer_layout_spin(grid, "size_y", "H", 0.05, 2.0, 0.01, 1.0)
	_add_layer_layout_spin(grid, "scale", "Scale", 0.10, 4.0, 0.01, 1.0)
	_add_layer_layout_spin(grid, "rotation", "Rot", -360.0, 360.0, 1.0, 0.0)
	root.add_child(grid)
	_layer_layout_dialog.add_child(root)
	add_child(_layer_layout_dialog)
	HDTheme.apply_dialog(_layer_layout_dialog)


func _add_layer_layout_spin(parent: GridContainer, key: String, label_text: String, min_value: float, max_value: float, step: float, value: float) -> void:
	parent.add_child(_label_badge(label_text, 44.0))
	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = step
	spin.value = value
	spin.custom_minimum_size = Vector2(58, CREATOR_CONTROL_HEIGHT)
	spin.value_changed.connect(func(next_value: float): _on_layer_layout_number_changed(key, next_value))
	parent.add_child(spin)
	_layer_layout_spinners[key] = spin


func _labeled_control(label_text: String, control: Control) -> VBoxContainer:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 3)
	var label := Label.new()
	label.text = label_text
	root.add_child(label)
	root.add_child(control)
	return root


func _open_layer_layout_dialog(index: int, layer: Dictionary) -> void:
	if index < 0 or index >= _layers.size():
		return
	_layer_layout_edit_index = index
	_layer_layout_draft = {
		"mode": _sanitize_layer_layout_mode(str(layer.get("layout_mode", "pack"))),
		"source": str(layer.get("layout_source", "")),
		"layout": _sanitize_layer_layout_for_creator(layer.get("layout", {})),
	}
	_sync_layer_layout_dialog_controls()
	_layer_layout_dialog.popup_centered(Vector2i(620, 380))


func _sync_layer_layout_dialog_controls() -> void:
	if not is_instance_valid(_layer_layout_mode_option) or not is_instance_valid(_layer_layout_source_option):
		return
	_updating_layer_layout_controls = true
	var mode := _sanitize_layer_layout_mode(str(_layer_layout_draft.get("mode", "pack")))
	_layer_layout_draft["mode"] = mode
	for item_index in range(_layer_layout_mode_option.item_count):
		if str(_layer_layout_mode_option.get_item_metadata(item_index)) == mode:
			_layer_layout_mode_option.select(item_index)
			break
	_layer_layout_source_option.clear()
	var source := str(_layer_layout_draft.get("source", ""))
	var selected_source_index := -1
	for layer_index in range(_layers.size()):
		if layer_index == _layer_layout_edit_index:
			continue
		var layer := _layers[layer_index] as Dictionary
		var layer_id := str(layer.get("id", ""))
		if layer_id.is_empty():
			continue
		var item_label := "%s (%s)" % [str(layer.get("name", layer_id)), layer_id]
		_layer_layout_source_option.add_item(item_label)
		var source_item_index := _layer_layout_source_option.item_count - 1
		_layer_layout_source_option.set_item_metadata(source_item_index, layer_id)
		if layer_id == source:
			selected_source_index = source_item_index
	if selected_source_index < 0 and _layer_layout_source_option.item_count > 0:
		selected_source_index = 0
		source = str(_layer_layout_source_option.get_item_metadata(0))
	if selected_source_index >= 0:
		_layer_layout_source_option.select(selected_source_index)
	_layer_layout_source_option.disabled = mode != "reuse" or _layer_layout_source_option.item_count <= 0
	if mode == "reuse":
		_layer_layout_draft["source"] = source
	else:
		_layer_layout_draft["source"] = ""
	var layout := _layer_layout_dialog_display_layout(mode, source)
	var position := _variant_vec2(layout.get("position", [0.5, 0.5]), Vector2(0.5, 0.5))
	var layout_size := _variant_vec2(layout.get("size", [1.0, 1.0]), Vector2(1.0, 1.0))
	_set_layer_layout_spin("position_x", position.x)
	_set_layer_layout_spin("position_y", position.y)
	_set_layer_layout_spin("size_x", layout_size.x)
	_set_layer_layout_spin("size_y", layout_size.y)
	_set_layer_layout_spin("scale", float(layout.get("scale", 1.0)))
	_set_layer_layout_spin("rotation", float(layout.get("rotation", 0.0)))
	var custom_enabled := mode == "custom"
	for key in _layer_layout_spinners.keys():
		var spin: SpinBox = _layer_layout_spinners[key]
		if is_instance_valid(spin):
			spin.editable = custom_enabled
			spin.modulate.a = 1.0 if custom_enabled else 0.55
	_updating_layer_layout_controls = false


func _set_layer_layout_spin(key: String, value: float) -> void:
	var spin: SpinBox = _layer_layout_spinners.get(key, null)
	if is_instance_valid(spin):
		spin.value = value


func _on_layer_layout_mode_selected(index: int) -> void:
	if _updating_layer_layout_controls:
		return
	var previous_mode := _sanitize_layer_layout_mode(str(_layer_layout_draft.get("mode", "pack")))
	var previous_source := str(_layer_layout_draft.get("source", ""))
	var mode := str(_layer_layout_mode_option.get_item_metadata(index)) if is_instance_valid(_layer_layout_mode_option) else "pack"
	var clean_mode := _sanitize_layer_layout_mode(mode)
	if clean_mode == "custom" and previous_mode != "custom":
		_layer_layout_draft["layout"] = _layer_layout_dialog_display_layout(previous_mode, previous_source)
	_layer_layout_draft["mode"] = clean_mode
	_sync_layer_layout_dialog_controls()


func _on_layer_layout_source_selected(index: int) -> void:
	if _updating_layer_layout_controls or not is_instance_valid(_layer_layout_source_option):
		return
	_layer_layout_draft["source"] = str(_layer_layout_source_option.get_item_metadata(index))
	_sync_layer_layout_dialog_controls()


func _on_layer_layout_number_changed(key: String, value: float) -> void:
	if _updating_layer_layout_controls:
		return
	var layout: Dictionary = _sanitize_layer_layout_for_creator(_layer_layout_draft.get("layout", {}))
	var position := _variant_vec2(layout.get("position", [0.5, 0.5]), Vector2(0.5, 0.5))
	var layout_size := _variant_vec2(layout.get("size", [1.0, 1.0]), Vector2(1.0, 1.0))
	match key:
		"position_x":
			position.x = clampf(value, 0.0, 1.0)
		"position_y":
			position.y = clampf(value, 0.0, 1.0)
		"size_x":
			layout_size.x = clampf(value, 0.05, 2.0)
		"size_y":
			layout_size.y = clampf(value, 0.05, 2.0)
		"scale":
			layout["scale"] = clampf(value, 0.10, 4.0)
		"rotation":
			layout["rotation"] = clampf(value, -360.0, 360.0)
	layout["position"] = [position.x, position.y]
	layout["size"] = [layout_size.x, layout_size.y]
	_layer_layout_draft["layout"] = layout


func _layer_layout_dialog_display_layout(mode: String, source: String) -> Dictionary:
	match _sanitize_layer_layout_mode(mode):
		"custom":
			return _sanitize_layer_layout_for_creator(_layer_layout_draft.get("layout", {}))
		"reuse":
			var source_index := _layer_index_for_id(source)
			if source_index >= 0:
				return _effective_layer_layout_for_index(source_index, {})
	return _layer_layout_from_pack_layout(_layout)


func _commit_layer_layout_dialog() -> void:
	if _layer_layout_edit_index < 0 or _layer_layout_edit_index >= _layers.size():
		return
	var layer := (_layers[_layer_layout_edit_index] as Dictionary).duplicate(true)
	var mode := _sanitize_layer_layout_mode(str(_layer_layout_draft.get("mode", "pack")))
	var source := str(_layer_layout_draft.get("source", ""))
	if mode == "reuse":
		if source.is_empty() or source == str(layer.get("id", "")) or not _has_layer_id(source):
			mode = "pack"
			source = ""
	elif mode != "custom":
		source = ""
	layer["layout_mode"] = mode
	layer["layout_source"] = source if mode == "reuse" else ""
	layer["layout"] = _sanitize_layer_layout_for_creator(_layer_layout_draft.get("layout", {}))
	_layers[_layer_layout_edit_index] = layer
	_repair_layer_layout_sources()
	_refresh_all()


func _sanitize_layer_layout_mode(mode: String) -> String:
	var clean := mode.strip_edges().to_lower()
	if clean in ["custom", "reuse"]:
		return clean
	return "pack"


func _sanitize_layer_layout_for_creator(value: Variant) -> Dictionary:
	var layout := {
		"position": [0.5, 0.5],
		"size": [1.0, 1.0],
		"scale": 1.0,
		"rotation": 0.0,
	}
	if value is Dictionary:
		var dict := value as Dictionary
		layout["position"] = _array_from_vec2(_variant_vec2(dict.get("position", layout["position"]), Vector2(0.5, 0.5)), Vector2(0, 0), Vector2(1, 1))
		layout["size"] = _array_from_vec2(_variant_vec2(dict.get("size", layout["size"]), Vector2(1.0, 1.0)), Vector2(0.05, 0.05), Vector2(2.0, 2.0))
		layout["scale"] = clampf(float(dict.get("scale", layout["scale"])), 0.10, 4.0)
		layout["rotation"] = clampf(float(dict.get("rotation", layout["rotation"])), -360.0, 360.0)
	return layout


func _sanitize_gutter_target(value: String) -> String:
	var clean := value.strip_edges().to_lower()
	match clean:
		"left", "right":
			return clean
		_:
			return "both"


func _selected_layer_gutter_target() -> String:
	if _selected_index < 0 or _selected_index >= _layers.size():
		return "both"
	return _sanitize_gutter_target(str((_layers[_selected_index] as Dictionary).get("gutter_target", "both")))


func _has_layer_id(layer_id: String) -> bool:
	for layer in _layers:
		if str((layer as Dictionary).get("id", "")) == layer_id:
			return true
	return false


func _repair_layer_layout_sources() -> void:
	var ids := {}
	for layer in _layers:
		var layer_id := str((layer as Dictionary).get("id", ""))
		if not layer_id.is_empty():
			ids[layer_id] = true
	for index in range(_layers.size()):
		var layer := (_layers[index] as Dictionary).duplicate(true)
		var layer_id := str(layer.get("id", ""))
		if str(layer.get("layout_mode", "pack")) == "reuse":
			var source := str(layer.get("layout_source", ""))
			if source.is_empty() or source == layer_id or not ids.has(source):
				layer["layout_mode"] = "pack"
				layer["layout_source"] = ""
				_layers[index] = layer


func _seed_default_project() -> void:
	_layout = _default_layout()
	_layers = [
		{
			"id": "aurora_gradient",
			"type": "gradient",
			"name": "Aurora Gradient",
			"opacity": 0.66,
			"color": "#55DFFFFF",
			"colors": ["#55DFFFFF", "#FF4DE1DD", "#FFE66DDD"],
			"speed": 0.28,
			"intensity": 0.9,
			"particle_count": 0,
			"reactive": true,
			"player_reactive": "off",
		},
		{
			"id": "beat_particles",
			"type": "particles",
			"name": "Beat Particles",
			"opacity": 0.78,
			"color": "#FFE66DCC",
			"colors": ["#55DFFFFF", "#FFE66DCC", "#FF4DE1CC"],
			"particle_count": 90,
			"speed": 0.35,
			"reactive": true,
			"player_reactive": "hit",
		},
	]
	_events = [
		{"event": "audio_reactive", "action": "pulse_opacity", "target": "*", "params": {"opacity": 0.95, "duration": 0.18}, "threshold": 0.0, "cooldown": 0.0},
		{"event": "miss", "action": "increase_distortion", "target": "*", "params": {"amount": 0.20}, "threshold": 0.0, "cooldown": 0.15},
	]
	_selected_index = 0


func _refresh_all() -> void:
	_layer_list.set_layers(_layers, _selected_index)
	_property_panel.edit_layer(_selected_index, _layers[_selected_index] if _selected_index >= 0 and _selected_index < _layers.size() else {})
	_timeline.set_events(_events, _layer_target_ids())
	_sync_layout_controls()
	_apply_compact_style(self)
	_refresh_preview_and_status()


func _refresh_preview_and_status() -> void:
	var config := _current_config(true)
	_preview.load_preview_config(config)
	_preview.set_preview_playing(_preview_playing)
	var validation := EMSValidator.validate_config(config)
	var errors: Array = validation.get("_validation_errors", []) as Array
	_performance.text = "PERFORMANCE: %s" % str(validation.get("_performance_warning", "Low"))
	_status.text = "Ready." if errors.is_empty() else "Validation: %s" % "; ".join(errors)


func _current_config(as_creator: bool, metadata: Dictionary = {}) -> Dictionary:
	var details := _merged_metadata(metadata)
	return {
		"schema_version": 1,
		"pack_type": EMSValidator.PACK_TYPE_CREATOR if as_creator else EMSValidator.PACK_TYPE_CONFIG,
		"pack_id": str(details.get("pack_id", "creator_ems")),
		"title": str(details.get("title", "Creator EMS")),
		"author": str(details.get("author", "Player")),
		"description": str(details.get("description", "Created in the Harmonic Drive EMS Creator.")),
		"layers": _layers.duplicate(true),
		"events": _events.duplicate(true),
		"layout": _layout.duplicate(true),
		"palette": {"colors": ["#55DFFFFF", "#FF4DE1FF", "#FFE66DFF"], "morph": "smooth", "speed": 0.25},
		"performance": {"motion_intensity": 0.72, "particle_intensity": 0.45, "audio_reactive": true, "estimated_cost": 0.35},
		"metadata": {"creator": "Harmonic Drive EMS Creator"},
	}


func _add_layer() -> void:
	_refresh_layer_templates()
	_layer_builder_dialog.open_add_layer(_custom_layer_templates)


func _duplicate_layer(index: int) -> void:
	if index < 0 or index >= _layers.size():
		return
	var copy := (_layers[index] as Dictionary).duplicate(true)
	copy["id"] = "%s_copy" % str(copy.get("id", "layer"))
	copy["name"] = "%s Copy" % str(copy.get("name", "Layer"))
	_layers.insert(index + 1, copy)
	_selected_index = index + 1
	_refresh_all()


func _delete_layer(index: int) -> void:
	if index < 0 or index >= _layers.size() or _layers.size() <= 1:
		return
	_layers.remove_at(index)
	_selected_index = clampi(index, 0, _layers.size() - 1)
	_repair_layer_layout_sources()
	_refresh_all()


func _move_layer(index: int, direction: int) -> void:
	var target := index + direction
	if index < 0 or index >= _layers.size() or target < 0 or target >= _layers.size():
		return
	var item := _layers[index]
	_layers.remove_at(index)
	_layers.insert(target, item)
	_selected_index = target
	_refresh_all()
	if is_instance_valid(_layer_stack_dialog) and _layer_stack_dialog.visible:
		_refresh_layer_stack_rows()


func _select_layer(index: int) -> void:
	_selected_index = index
	if _layout_scope == "selected_layer" and _selected_index >= 0 and _selected_index < _layers.size():
		_set_selected_layer_layout_mode("custom", "")
	_refresh_all()


func _on_layer_changed(index: int, layer: Dictionary) -> void:
	if index >= 0 and index < _layers.size():
		var previous := _layers[index] as Dictionary
		var needs_list_refresh := str(previous.get("name", "")) != str(layer.get("name", "")) or str(previous.get("type", "")) != str(layer.get("type", "")) or str(previous.get("id", "")) != str(layer.get("id", ""))
		_layers[index] = layer
		_repair_layer_layout_sources()
		if needs_list_refresh and is_instance_valid(_layer_list):
			_layer_list.set_layers(_layers, _selected_index)
			_sync_layout_controls()
	_refresh_preview_and_status()


func _on_events_changed(events: Array[Dictionary]) -> void:
	_events = events.duplicate(true)
	_apply_compact_style(self)
	_refresh_preview_and_status()


func _on_layout_region_selected(index: int) -> void:
	if _updating_layout_controls or _layout_scope == "selected_layer":
		return
	var region := str(_layout_region_option.get_item_metadata(index)) if is_instance_valid(_layout_region_option) else "gutters"
	_layout["background_region"] = "full_background" if region == "full_background" else "gutters"
	_sync_layout_controls()
	_refresh_preview_and_status()


func _on_layout_scope_selected(index: int) -> void:
	if _updating_layout_controls:
		return
	var scope := str(_layout_scope_option.get_item_metadata(index)) if is_instance_valid(_layout_scope_option) else "pack"
	_layout_scope = "selected_layer" if scope == "selected_layer" else "pack"
	if _selected_index >= 0 and _selected_index < _layers.size():
		if _layout_scope == "selected_layer":
			_set_selected_layer_layout_mode("custom", "")
		else:
			_set_selected_layer_layout_mode("pack", "")
	_sync_layout_controls()
	_refresh_preview_and_status()


func _on_layout_gutter_target_selected(index: int) -> void:
	if _updating_layout_controls:
		return
	if _layout_scope != "selected_layer" or _selected_index < 0 or _selected_index >= _layers.size():
		return
	var target := str(_layout_gutter_target_option.get_item_metadata(index)) if is_instance_valid(_layout_gutter_target_option) else "both"
	_set_selected_layer_gutter_target(target)


func _on_panel_layer_layout_mode_selected(index: int) -> void:
	if _updating_layout_controls or _layout_scope != "selected_layer":
		return
	var mode := str(_layout_mode_option.get_item_metadata(index)) if is_instance_valid(_layout_mode_option) else "pack"
	var source := _selected_panel_reuse_source()
	_set_selected_layer_layout_mode(mode, source)
	_sync_layout_controls()
	_refresh_preview_and_status()


func _on_panel_layer_reuse_source_selected(index: int) -> void:
	if _updating_layout_controls or _layout_scope != "selected_layer":
		return
	if _selected_index < 0 or _selected_index >= _layers.size() or not is_instance_valid(_layout_reuse_source_option):
		return
	var source := str(_layout_reuse_source_option.get_item_metadata(index))
	_set_selected_layer_layout_mode("reuse", source)
	_sync_layout_controls()
	_refresh_preview_and_status()


func _on_layout_number_changed(key: String, value: float) -> void:
	if _updating_layout_controls:
		return
	if _layout_scope == "selected_layer":
		_update_selected_layer_layout_number(key, value)
		return
	var position := _layout_vec2("position", Vector2(0.5, 0.5))
	var layout_size := _layout_vec2("size", Vector2(1.0, 1.0))
	match key:
		"position_x":
			position.x = clampf(value, 0.0, 1.0)
		"position_y":
			position.y = clampf(value, 0.0, 1.0)
		"size_x":
			layout_size.x = clampf(value, 0.05, 2.0)
		"size_y":
			layout_size.y = clampf(value, 0.05, 2.0)
		"scale":
			_layout["scale"] = clampf(value, 0.10, 4.0)
		"rotation":
			_layout["rotation"] = clampf(value, -360.0, 360.0)
	_layout["position"] = [position.x, position.y]
	_layout["size"] = [layout_size.x, layout_size.y]
	_refresh_preview_and_status()


func _sync_layout_controls() -> void:
	_layout = _sanitize_layout_for_creator(_layout)
	_updating_layout_controls = true
	if is_instance_valid(_layout_scope_option):
		_layout_scope_option.select(1 if _layout_scope == "selected_layer" else 0)
	if is_instance_valid(_layout_region_option):
		var region := str(_layout.get("background_region", "gutters"))
		_layout_region_option.select(1 if region == "full_background" else 0)
		_layout_region_option.disabled = _layout_scope == "selected_layer"
		_layout_region_option.modulate.a = 0.55 if _layout_scope == "selected_layer" else 1.0
	if is_instance_valid(_layout_gutter_target_option):
		var show_gutter_target := _layout_scope == "selected_layer" and str(_layout.get("background_region", "gutters")) == "gutters"
		_layout_gutter_target_option.visible = show_gutter_target
		_layout_gutter_target_option.disabled = not show_gutter_target or _selected_index < 0 or _selected_index >= _layers.size()
		_layout_gutter_target_option.modulate.a = 1.0 if not _layout_gutter_target_option.disabled else 0.55
		var selected_target := _selected_layer_gutter_target()
		for item_index in range(_layout_gutter_target_option.item_count):
			if str(_layout_gutter_target_option.get_item_metadata(item_index)) == selected_target:
				_layout_gutter_target_option.select(item_index)
				break
	_sync_panel_layer_layout_controls()
	var source_layout := _selected_layer_layout_for_controls() if _layout_scope == "selected_layer" else _layout
	var position := _variant_vec2(source_layout.get("position", [0.5, 0.5]), Vector2(0.5, 0.5))
	var layout_size := _variant_vec2(source_layout.get("size", [1.0, 1.0]), Vector2(1.0, 1.0))
	_set_layout_spin("position_x", position.x)
	_set_layout_spin("position_y", position.y)
	_set_layout_spin("size_x", layout_size.x)
	_set_layout_spin("size_y", layout_size.y)
	_set_layout_spin("scale", float(source_layout.get("scale", 1.0)))
	_set_layout_spin("rotation", float(source_layout.get("rotation", 0.0)))
	var selected_mode := _selected_layer_layout_mode()
	var spinners_enabled := _layout_scope != "selected_layer" or (_selected_index >= 0 and _selected_index < _layers.size() and selected_mode == "custom")
	_set_layout_spinners_enabled(spinners_enabled)
	_updating_layout_controls = false


func _sync_panel_layer_layout_controls() -> void:
	var has_selected := _selected_index >= 0 and _selected_index < _layers.size()
	var panel_controls_enabled := _layout_scope == "selected_layer" and has_selected
	var selected_mode := _selected_layer_layout_mode() if has_selected else "pack"
	if is_instance_valid(_layout_mode_option):
		for item_index in range(_layout_mode_option.item_count):
			if str(_layout_mode_option.get_item_metadata(item_index)) == selected_mode:
				_layout_mode_option.select(item_index)
				break
		_layout_mode_option.disabled = not panel_controls_enabled
		_layout_mode_option.modulate.a = 1.0 if panel_controls_enabled else 0.55
	if is_instance_valid(_layout_reuse_source_option):
		_layout_reuse_source_option.clear()
		var source := _selected_layer_layout_source() if has_selected else ""
		var selected_source_index := -1
		for layer_index in range(_layers.size()):
			if layer_index == _selected_index:
				continue
			var layer := _layers[layer_index] as Dictionary
			var layer_id := str(layer.get("id", ""))
			if layer_id.is_empty():
				continue
			_layout_reuse_source_option.add_item("%s (%s)" % [str(layer.get("name", layer_id)), layer_id])
			var source_index := _layout_reuse_source_option.item_count - 1
			_layout_reuse_source_option.set_item_metadata(source_index, layer_id)
			if layer_id == source:
				selected_source_index = source_index
		if selected_source_index < 0 and _layout_reuse_source_option.item_count > 0:
			selected_source_index = 0
		if selected_source_index >= 0:
			_layout_reuse_source_option.select(selected_source_index)
		var reuse_enabled := panel_controls_enabled and selected_mode == "reuse" and _layout_reuse_source_option.item_count > 0
		_layout_reuse_source_option.disabled = not reuse_enabled
		_layout_reuse_source_option.modulate.a = 1.0 if reuse_enabled else 0.55


func _set_layout_spin(key: String, value: float) -> void:
	var spin: SpinBox = _layout_spinners.get(key, null)
	if is_instance_valid(spin):
		spin.value = value


func _set_layout_spinners_enabled(enabled: bool) -> void:
	for key in _layout_spinners.keys():
		var spin: SpinBox = _layout_spinners[key]
		if is_instance_valid(spin):
			spin.editable = enabled
			spin.modulate.a = 1.0 if enabled else 0.55


func _update_selected_layer_layout_number(key: String, value: float) -> void:
	if _selected_index < 0 or _selected_index >= _layers.size():
		return
	if _selected_layer_layout_mode() != "custom":
		_set_selected_layer_layout_mode("custom", "")
	var layout := _selected_layer_layout_for_controls()
	var position := _variant_vec2(layout.get("position", [0.5, 0.5]), Vector2(0.5, 0.5))
	var layout_size := _variant_vec2(layout.get("size", [1.0, 1.0]), Vector2(1.0, 1.0))
	match key:
		"position_x":
			position.x = clampf(value, 0.0, 1.0)
		"position_y":
			position.y = clampf(value, 0.0, 1.0)
		"size_x":
			layout_size.x = clampf(value, 0.05, 2.0)
		"size_y":
			layout_size.y = clampf(value, 0.05, 2.0)
		"scale":
			layout["scale"] = clampf(value, 0.10, 4.0)
		"rotation":
			layout["rotation"] = clampf(value, -360.0, 360.0)
	layout["position"] = [position.x, position.y]
	layout["size"] = [layout_size.x, layout_size.y]
	var layer := (_layers[_selected_index] as Dictionary).duplicate(true)
	layer["layout_mode"] = "custom"
	layer["layout_source"] = ""
	layer["layout"] = _sanitize_layer_layout_for_creator(layout)
	_layers[_selected_index] = layer
	_repair_layer_layout_sources()
	_sync_layout_controls()
	_refresh_preview_and_status()


func _set_selected_layer_layout_mode(mode: String, source: String = "") -> void:
	if _selected_index < 0 or _selected_index >= _layers.size():
		return
	var clean_mode := _sanitize_layer_layout_mode(mode)
	var layer := (_layers[_selected_index] as Dictionary).duplicate(true)
	var layout := _effective_layer_layout_for_index(_selected_index, {})
	match clean_mode:
		"custom":
			layer["layout_mode"] = "custom"
			layer["layout_source"] = ""
			layer["layout"] = _sanitize_layer_layout_for_creator(layout)
		"reuse":
			var reuse_source := source
			if reuse_source.is_empty() or reuse_source == str(layer.get("id", "")) or not _has_layer_id(reuse_source):
				reuse_source = _first_reusable_layer_id(_selected_index)
			if reuse_source.is_empty():
				layer["layout_mode"] = "custom"
				layer["layout_source"] = ""
				layer["layout"] = _sanitize_layer_layout_for_creator(layout)
			else:
				layer["layout_mode"] = "reuse"
				layer["layout_source"] = reuse_source
				layer["layout"] = _sanitize_layer_layout_for_creator(layer.get("layout", layout))
		_:
			layer["layout_mode"] = "pack"
			layer["layout_source"] = ""
			layer["layout"] = _sanitize_layer_layout_for_creator(layer.get("layout", layout))
	_layers[_selected_index] = layer
	_repair_layer_layout_sources()


func _first_reusable_layer_id(excluding_index: int) -> String:
	for layer_index in range(_layers.size()):
		if layer_index == excluding_index:
			continue
		var layer_id := str((_layers[layer_index] as Dictionary).get("id", ""))
		if not layer_id.is_empty():
			return layer_id
	return ""


func _selected_panel_reuse_source() -> String:
	if not is_instance_valid(_layout_reuse_source_option) or _layout_reuse_source_option.selected < 0:
		return ""
	return str(_layout_reuse_source_option.get_item_metadata(_layout_reuse_source_option.selected))


func _set_selected_layer_gutter_target(value: String) -> void:
	if _selected_index < 0 or _selected_index >= _layers.size():
		return
	var layer := (_layers[_selected_index] as Dictionary).duplicate(true)
	layer["gutter_target"] = _sanitize_gutter_target(value)
	_layers[_selected_index] = layer
	_sync_layout_controls()
	_refresh_preview_and_status()


func _default_layout() -> Dictionary:
	return {
		"background_region": "gutters",
		"position": [0.5, 0.5],
		"size": [1.0, 1.0],
		"scale": 1.0,
		"rotation": 0.0,
	}


func _sanitize_layout_for_creator(value: Variant) -> Dictionary:
	var layout := _default_layout()
	if value is Dictionary:
		var dict := value as Dictionary
		var region := str(dict.get("background_region", layout["background_region"])).strip_edges().to_lower()
		layout["background_region"] = "full_background" if region == "full_background" else "gutters"
		layout["position"] = _array_from_vec2(_variant_vec2(dict.get("position", layout["position"]), Vector2(0.5, 0.5)), Vector2(0, 0), Vector2(1, 1))
		layout["size"] = _array_from_vec2(_variant_vec2(dict.get("size", layout["size"]), Vector2(1.0, 1.0)), Vector2(0.05, 0.05), Vector2(2.0, 2.0))
		layout["scale"] = clampf(float(dict.get("scale", layout["scale"])), 0.10, 4.0)
		layout["rotation"] = clampf(float(dict.get("rotation", layout["rotation"])), -360.0, 360.0)
	return layout


func _layer_layout_from_pack_layout(value: Dictionary) -> Dictionary:
	var layout := _sanitize_layout_for_creator(value)
	return {
		"position": (layout.get("position", [0.5, 0.5]) as Array).duplicate(true),
		"size": (layout.get("size", [1.0, 1.0]) as Array).duplicate(true),
		"scale": float(layout.get("scale", 1.0)),
		"rotation": float(layout.get("rotation", 0.0)),
	}


func _selected_layer_layout_for_controls() -> Dictionary:
	if _selected_index < 0 or _selected_index >= _layers.size():
		return _layer_layout_from_pack_layout(_layout)
	return _effective_layer_layout_for_index(_selected_index, {})


func _selected_layer_layout_mode() -> String:
	if _selected_index < 0 or _selected_index >= _layers.size():
		return "pack"
	return _sanitize_layer_layout_mode(str((_layers[_selected_index] as Dictionary).get("layout_mode", "pack")))


func _selected_layer_layout_source() -> String:
	if _selected_index < 0 or _selected_index >= _layers.size():
		return ""
	return str((_layers[_selected_index] as Dictionary).get("layout_source", ""))


func _effective_layer_layout_for_index(index: int, resolving: Dictionary) -> Dictionary:
	if index < 0 or index >= _layers.size():
		return _layer_layout_from_pack_layout(_layout)
	var layer := _layers[index] as Dictionary
	var layer_id := str(layer.get("id", ""))
	if not layer_id.is_empty() and resolving.has(layer_id):
		return _layer_layout_from_pack_layout(_layout)
	var mode := _sanitize_layer_layout_mode(str(layer.get("layout_mode", "pack")))
	match mode:
		"custom":
			return _sanitize_layer_layout_for_creator(layer.get("layout", {}))
		"reuse":
			var source := str(layer.get("layout_source", ""))
			var source_index := _layer_index_for_id(source)
			if source_index >= 0 and source_index != index:
				if not layer_id.is_empty():
					resolving[layer_id] = true
				return _effective_layer_layout_for_index(source_index, resolving)
	return _layer_layout_from_pack_layout(_layout)


func _layer_index_for_id(layer_id: String) -> int:
	for index in range(_layers.size()):
		if str((_layers[index] as Dictionary).get("id", "")) == layer_id:
			return index
	return -1


func _layout_vec2(key: String, fallback: Vector2) -> Vector2:
	return _variant_vec2(_layout.get(key, [fallback.x, fallback.y]), fallback)


func _variant_vec2(value: Variant, fallback: Vector2) -> Vector2:
	if value is Array and (value as Array).size() >= 2:
		return Vector2(float((value as Array)[0]), float((value as Array)[1]))
	if value is Dictionary:
		var dict := value as Dictionary
		return Vector2(float(dict.get("x", fallback.x)), float(dict.get("y", fallback.y)))
	return fallback


func _array_from_vec2(value: Vector2, min_value: Vector2, max_value: Vector2) -> Array:
	return [
		clampf(value.x, min_value.x, max_value.x),
		clampf(value.y, min_value.y, max_value.y),
	]


func _open_prefilled_event_rule(rule: Dictionary) -> void:
	if _timeline == null:
		return
	_timeline.open_prefilled_rule(rule)


func _simulate(event_name: String) -> void:
	if event_name.is_empty():
		_preview_playing = not _preview_playing
		_preview.set_preview_playing(_preview_playing)
		_simulation_status.text = "Preview playing." if _preview_playing else "Preview paused."
	else:
		_preview.simulate_event(event_name, 1.0)
		_simulation_status.text = "Simulated %s." % event_name.replace("_", " ").capitalize()


func _open_layer_type_builder() -> void:
	_refresh_layer_templates()
	_layer_builder_dialog.open_create_type(_custom_layer_templates)


func _show_pack_manager() -> void:
	_pack_manager_dialog.refresh_packs()
	_pack_manager_dialog.popup_centered(Vector2i(900, 640))


func _on_layer_type_created(layer: Dictionary) -> void:
	_append_layer_from_builder(layer)


func _on_layer_template_saved(template: Dictionary, layer: Dictionary) -> void:
	var template_name := str(template.get("name", layer.get("name", "Custom Layer"))).strip_edges()
	var result := _layer_template_store.save_template(layer, template_name)
	_refresh_layer_templates()
	_append_layer_from_builder(layer)
	_status.text = _result_message(result, "Custom layer type saved.")


func _append_layer_from_builder(layer: Dictionary) -> void:
	var next_layer := layer.duplicate(true)
	next_layer["id"] = _unique_layer_id(str(next_layer.get("name", next_layer.get("id", "Layer"))))
	if not next_layer.has("name") or str(next_layer.get("name", "")).strip_edges().is_empty():
		next_layer["name"] = "Layer %d" % (_layers.size() + 1)
	_layers.append(next_layer)
	_selected_index = _layers.size() - 1
	_refresh_all()


func _refresh_layer_templates() -> void:
	_custom_layer_templates = _layer_template_store.list_templates()


func _unique_layer_id(layer_name: String) -> String:
	var existing_ids := _existing_layer_ids()
	var base := EMSValidator.sanitize_pack_id(layer_name)
	if base.is_empty():
		base = "layer"
	var candidate := base
	var suffix := 2
	while existing_ids.has(candidate):
		candidate = "%s_%d" % [base, suffix]
		suffix += 1
	return candidate


func _existing_layer_ids() -> Array[String]:
	var ids: Array[String] = []
	for layer in _layers:
		var layer_id := str((layer as Dictionary).get("id", ""))
		if not layer_id.is_empty():
			ids.append(layer_id)
	return ids


func _layer_target_ids() -> Array[String]:
	var ids: Array[String] = ["*"]
	for layer in _layers:
		var layer_id := str(layer.get("id", ""))
		if not layer_id.is_empty() and not ids.has(layer_id):
			ids.append(layer_id)
	return ids


func _save_draft() -> void:
	var result := _save_draft_with_metadata(_draft_metadata())
	_status.text = _result_message(result, "Draft saved to Local EMS.")


func _show_export() -> void:
	_export_dialog.set_metadata(_last_export_metadata)
	_export_dialog.popup_centered()


func _export_pack(details: Dictionary) -> void:
	var result := _export_pack_with_details(details)
	_status.text = _result_message(result, "EMS pack exported.")
	if bool(result.get("ok", false)) and is_instance_valid(_export_dialog):
		_export_dialog.hide()


func _upload_to_workshop() -> void:
	if not is_instance_valid(_workshop_upload_dialog):
		return
	_workshop_upload_dialog.set_metadata(_last_export_metadata)
	_workshop_upload_dialog.popup_centered()


func _upload_to_workshop_with_details(details_in: Dictionary) -> void:
	var details := _merged_metadata(details_in)
	details["include_creator_project"] = bool(details.get("include_creator_project", true))
	details["install_local"] = false
	_last_export_metadata = details.duplicate(true)
	_status.text = "Preparing Steam Workshop upload..."
	if is_instance_valid(_workshop_upload_dialog):
		_workshop_upload_dialog.set_status_message(_status.text)
	var include_project := bool(details.get("include_creator_project", true))
	var preview_path := str(details.get("preview_path", "")).strip_edges()
	var export_result := EMSPackLoader.export_pack(
		EMSPackLoader.EXPORT_ROOT,
		_manifest_metadata(details, include_project),
		_current_config(include_project, details),
		_project_metadata(details) if include_project else {},
		preview_path
	)
	if not bool(export_result.get("ok", false)):
		_status.text = str(export_result.get("message", "Export failed."))
		if is_instance_valid(_workshop_upload_dialog):
			_workshop_upload_dialog.set_status_message(_status.text, export_result)
		return
	var upload_result := _workshop_manager.upload_pack(str(export_result.get("path", "")), details)
	_status.text = _workshop_upload_result_message(upload_result, export_result, details)
	if is_instance_valid(_workshop_upload_dialog):
		_workshop_upload_dialog.set_status_message(_status.text, upload_result)


func _on_workshop_upload_status_changed(status: Dictionary) -> void:
	if _status == null:
		return
	_status.text = _workshop_status_event_message(status)
	if is_instance_valid(_workshop_upload_dialog):
		_workshop_upload_dialog.set_status_message(_status.text, status)


func _load_creator_pack(folder_path: String) -> Dictionary:
	var validation := EMSValidator.validate_pack_folder(folder_path)
	if not bool(validation.get("ok", false)):
		_status.text = "Could not load EMS pack: %s" % "; ".join(validation.get("errors", []) as Array)
		return {"ok": false, "message": _status.text, "validation": validation}
	var config: Dictionary = validation.get("config", {}) as Dictionary
	var layers_value: Variant = config.get("layers", [])
	var events_value: Variant = config.get("events", [])
	if layers_value is not Array or (layers_value as Array).is_empty():
		_status.text = "Could not load EMS pack: no editable layers found."
		return {"ok": false, "message": _status.text, "validation": validation}
	_layers.clear()
	var layers_array := layers_value as Array
	for layer in layers_array:
		if layer is Dictionary:
			var editable_layer := (layer as Dictionary).duplicate(true)
			_restore_media_source_path(editable_layer, folder_path)
			_layers.append(editable_layer)
	_events.clear()
	if events_value is Array:
		var events_array := events_value as Array
		for event_rule in events_array:
			if event_rule is Dictionary:
				_events.append((event_rule as Dictionary).duplicate(true))
	_layout = _sanitize_layout_for_creator(config.get("layout", {}))
	_selected_index = 0
	_loaded_pack_folder = folder_path
	_last_export_metadata = _metadata_from_validation(validation, folder_path)
	_refresh_all()
	_status.text = "Loaded %s from %s." % [str(_last_export_metadata.get("title", "EMS Pack")), folder_path]
	return {"ok": true, "message": _status.text, "validation": validation}


func _restore_media_source_path(layer: Dictionary, folder_path: String) -> void:
	var media_kind := str(layer.get("media_kind", ""))
	if media_kind.is_empty() and str(layer.get("type", "")) in ["image", "video"]:
		media_kind = str(layer.get("type", ""))
	if media_kind not in ["image", "video"]:
		return
	var asset_path := str(layer.get("asset_path", "")).strip_edges()
	if asset_path.is_empty():
		return
	var candidate := folder_path.path_join(asset_path)
	if FileAccess.file_exists(candidate):
		layer["source_path"] = candidate


func _delete_creator_pack(folder_path: String) -> Dictionary:
	var result := EMSPackLoader.delete_pack_folder(folder_path)
	_reload_registry()
	var registry := get_node_or_null("/root/EMSRegistry")
	if registry != null and registry.has_method("is_valid_ems") and registry.has_method("set_active_ems"):
		var progression := get_node_or_null("/root/ProgressionManager")
		if progression != null and progression.has_method("get_equipped_loadout"):
			var equipped: Dictionary = progression.call("get_equipped_loadout") as Dictionary
			var active_id := str(equipped.get("ems_loadout", ""))
			if active_id.begins_with("community:") and not bool(registry.call("is_valid_ems", active_id)):
				registry.call("set_active_ems", active_id)
	if _loaded_pack_folder == folder_path:
		_loaded_pack_folder = ""
	if _pack_manager_dialog != null:
		_pack_manager_dialog.refresh_packs()
	_status.text = "%s %s" % [str(result.get("message", "")), str(result.get("path", ""))]
	return result


func save_draft_for_test(metadata: Dictionary = {}) -> Dictionary:
	return _save_draft_with_metadata(_merged_metadata(metadata))


func export_pack_for_test(details: Dictionary = {}) -> Dictionary:
	return _export_pack_with_details(_merged_metadata(details))


func load_pack_for_test(folder_path: String) -> Dictionary:
	return _load_creator_pack(folder_path)


func delete_pack_for_test(folder_path: String) -> Dictionary:
	return _delete_creator_pack(folder_path)


func set_layer_template_store_root_for_test(root_path: String) -> void:
	_layer_template_store = EMSLayerTemplateStore.new(root_path)
	_refresh_layer_templates()


func create_layer_template_for_test(layer_type: String, layer_name: String) -> Dictionary:
	var layer: Dictionary = _layer_builder_dialog.create_layer_for_test(layer_type) as Dictionary
	layer["name"] = layer_name
	layer["id"] = EMSValidator.sanitize_pack_id(layer_name)
	var result := _layer_template_store.save_template(layer, layer_name)
	_refresh_layer_templates()
	return result


func add_layer_from_template_for_test(template_id: String, layer_name: String = "") -> Dictionary:
	_refresh_layer_templates()
	for template in _custom_layer_templates:
		if str((template as Dictionary).get("template_id", "")) != template_id:
			continue
		var layer := _layer_template_store.make_layer_instance(template as Dictionary, _existing_layer_ids(), layer_name)
		if layer.is_empty():
			return {"ok": false, "message": "Template could not create a layer."}
		_layers.append(layer)
		_selected_index = _layers.size() - 1
		_refresh_all()
		return {"ok": true, "layer": layer}
	return {"ok": false, "message": "Template not found."}


func open_add_layer_dialog_for_test() -> Dictionary:
	_add_layer()
	return _layer_builder_dialog.get_debug_state()


func show_export_dialog_for_test() -> Dictionary:
	_show_export()
	return get_creator_debug_state()


func export_from_dialog_for_test(details: Dictionary = {}) -> Dictionary:
	_show_export()
	_export_dialog.set_export_details_for_test(_merged_metadata(details))
	_export_pack(_export_dialog.get_export_details())
	return get_creator_debug_state()


func show_workshop_upload_dialog_for_test() -> Dictionary:
	_upload_to_workshop()
	return get_creator_debug_state()


func upload_to_workshop_from_dialog_for_test(details: Dictionary = {}) -> Dictionary:
	_upload_to_workshop()
	_workshop_upload_dialog.set_upload_details_for_test(_merged_metadata(details))
	var upload_details: Dictionary = _workshop_upload_dialog.get_upload_details()
	_upload_to_workshop_with_details(upload_details)
	var state := get_creator_debug_state()
	state["workshop_upload_details"] = upload_details
	return state


func select_layer_for_test(index: int) -> void:
	_select_layer(index)


func set_layout_scope_for_test(scope: String) -> void:
	_layout_scope = "selected_layer" if scope == "selected_layer" else "pack"
	if _selected_index >= 0 and _selected_index < _layers.size():
		if _layout_scope == "selected_layer":
			_set_selected_layer_layout_mode("custom", "")
		else:
			_set_selected_layer_layout_mode("pack", "")
	_sync_layout_controls()


func set_layout_number_for_test(key: String, value: float) -> void:
	_on_layout_number_changed(key, value)


func set_panel_layer_layout_mode_for_test(mode: String) -> void:
	if _layout_scope != "selected_layer":
		_layout_scope = "selected_layer"
	_set_selected_layer_layout_mode(mode, _selected_panel_reuse_source())
	_sync_layout_controls()
	_refresh_preview_and_status()


func set_panel_layer_reuse_source_for_test(source: String) -> void:
	if _layout_scope != "selected_layer":
		_layout_scope = "selected_layer"
	_set_selected_layer_layout_mode("reuse", source)
	_sync_layout_controls()
	_refresh_preview_and_status()


func set_selected_layer_gutter_target_for_test(target: String) -> void:
	_set_selected_layer_gutter_target(target)


func set_panel_widths_for_test(layer_width: float, property_width: float) -> void:
	_set_layer_panel_width(layer_width)
	_set_property_panel_width(property_width)


func simulate_property_resize_drag_for_test(start_mouse_x: float, end_mouse_x: float) -> void:
	_active_resize_handle = "property"
	_resize_start_mouse_x = start_mouse_x
	_resize_start_property_width = _property_panel_width
	_apply_active_resize_drag(end_mouse_x)
	_active_resize_handle = ""


func set_layout_for_test(region: String, position: Vector2, layout_size: Vector2, scale_value: float, rotation_degrees: float) -> void:
	_layout = _sanitize_layout_for_creator({
		"background_region": region,
		"position": [position.x, position.y],
		"size": [layout_size.x, layout_size.y],
		"scale": scale_value,
		"rotation": rotation_degrees,
	})
	_sync_layout_controls()
	_refresh_preview_and_status()


func set_layer_layout_for_test(index: int, mode: String, source: String, position: Vector2, layout_size: Vector2, scale_value: float, rotation_degrees: float) -> void:
	if index < 0 or index >= _layers.size():
		return
	var layer := (_layers[index] as Dictionary).duplicate(true)
	layer["layout_mode"] = _sanitize_layer_layout_mode(mode)
	layer["layout_source"] = source
	layer["layout"] = _sanitize_layer_layout_for_creator({
		"position": [position.x, position.y],
		"size": [layout_size.x, layout_size.y],
		"scale": scale_value,
		"rotation": rotation_degrees,
	})
	_layers[index] = layer
	_repair_layer_layout_sources()
	_refresh_all()


func reorder_layers_for_test(layer_ids: Array) -> void:
	var by_id := {}
	for layer in _layers:
		var layer_id := str((layer as Dictionary).get("id", ""))
		if not layer_id.is_empty():
			by_id[layer_id] = (layer as Dictionary).duplicate(true)
	var next_layers: Array[Dictionary] = []
	var used := {}
	for layer_id in layer_ids:
		if by_id.has(layer_id) and not used.has(layer_id):
			next_layers.append(by_id[layer_id])
			used[layer_id] = true
	for layer in _layers:
		var existing_id := str((layer as Dictionary).get("id", ""))
		if not used.has(existing_id):
			next_layers.append((layer as Dictionary).duplicate(true))
	_layers = next_layers
	_selected_index = clampi(_selected_index, 0, _layers.size() - 1)
	_repair_layer_layout_sources()
	_refresh_all()


func get_creator_debug_state() -> Dictionary:
	var creator_rect := get_global_rect()
	var property_rect := Rect2()
	if is_instance_valid(_property_panel_container):
		property_rect = _property_panel_container.get_global_rect()
	elif is_instance_valid(_property_scroll):
		property_rect = _property_scroll.get_global_rect()
	elif is_instance_valid(_property_panel):
		property_rect = _property_panel.get_global_rect()
	var layer_rect := Rect2()
	if is_instance_valid(_layer_list):
		layer_rect = _layer_list.get_global_rect()
	var timeline_rect := Rect2()
	if is_instance_valid(_timeline):
		timeline_rect = _timeline.get_global_rect()
	var layer_order: Array[String] = []
	var layer_layouts: Array[Dictionary] = []
	var layer_names: Array[String] = []
	var template_names: Array[String] = []
	var action_button_texts: Array[String] = []
	var action_button_widths: Array[float] = []
	var action_buttons_readable := _action_buttons.size() > 0
	for button in _action_buttons:
		if not is_instance_valid(button):
			action_buttons_readable = false
			continue
		action_button_texts.append(button.text)
		var width := button.get_global_rect().size.x
		action_button_widths.append(width)
		if button.text.strip_edges().is_empty() or width < maxf(44.0, button.custom_minimum_size.x * 0.85):
			action_buttons_readable = false
	for layer in _layers:
		var layer_dict := layer as Dictionary
		layer_order.append(str(layer_dict.get("id", "")))
		layer_names.append(str(layer_dict.get("name", "")))
		layer_layouts.append({
			"id": str(layer_dict.get("id", "")),
			"layout_mode": str(layer_dict.get("layout_mode", "pack")),
			"layout_source": str(layer_dict.get("layout_source", "")),
			"layout": (layer_dict.get("layout", {}) as Dictionary).duplicate(true),
			"gutter_target": _sanitize_gutter_target(str(layer_dict.get("gutter_target", "both"))),
		})
	for template in _custom_layer_templates:
		template_names.append(str((template as Dictionary).get("name", "")))
	return {
		"metadata": _last_export_metadata.duplicate(true),
		"status": _status.text if _status != null else "",
		"export_dialog_visible": is_instance_valid(_export_dialog) and _export_dialog.visible,
		"workshop_upload_dialog_visible": is_instance_valid(_workshop_upload_dialog) and _workshop_upload_dialog.visible,
		"workshop_upload_dialog_state": _workshop_upload_dialog.get_debug_state() if is_instance_valid(_workshop_upload_dialog) else {},
		"layer_count": _layers.size(),
		"layer_names": layer_names,
		"event_count": _events.size(),
		"saved_layer_template_count": _custom_layer_templates.size(),
		"saved_layer_template_names": template_names,
		"loaded_pack_folder": _loaded_pack_folder,
		"has_pack_manager": _pack_manager_dialog != null,
		"has_workshop_upload_dialog": _workshop_upload_dialog != null,
		"has_layer_stack_dialog": _layer_stack_dialog != null,
		"has_layer_layout_dialog": _layer_layout_dialog != null,
		"layer_order": layer_order,
		"layer_layouts": layer_layouts,
		"layout": _layout.duplicate(true),
		"layout_scope": _layout_scope,
		"selected_layer_layout_preview": _selected_layer_layout_for_controls(),
		"selected_layer_layout_mode": _selected_layer_layout_mode(),
		"selected_layer_layout_source": _selected_layer_layout_source(),
		"selected_layer_gutter_target": _selected_layer_gutter_target(),
		"has_layout_scope_selector": _layout_scope_option != null,
		"has_layout_mode_selector": _layout_mode_option != null,
		"has_layout_reuse_selector": _layout_reuse_source_option != null,
		"has_layout_gutter_target_selector": _layout_gutter_target_option != null,
		"has_resizable_panel_splits": is_instance_valid(_vertical_split) and _vertical_split.dragging_enabled and is_instance_valid(_layer_resize_handle) and is_instance_valid(_property_resize_handle),
		"layout_mode_selector_enabled": is_instance_valid(_layout_mode_option) and not _layout_mode_option.disabled,
		"layout_reuse_selector_enabled": is_instance_valid(_layout_reuse_source_option) and not _layout_reuse_source_option.disabled,
		"layout_gutter_target_selector_visible": is_instance_valid(_layout_gutter_target_option) and _layout_gutter_target_option.visible,
		"has_layout_controls": _layout_scope_option != null and _layout_region_option != null and _layout_gutter_target_option != null and _layout_mode_option != null and _layout_reuse_source_option != null and _layout_spinners.has("position_x") and _layout_spinners.has("rotation"),
		"layout_value_label_count": _layout_value_label_count(),
		"property_panel_visible": is_instance_valid(_property_panel) and _property_panel.visible and property_rect.size.x >= 188.0,
		"property_panel_fits": is_instance_valid(_property_panel) and property_rect.end.x <= creator_rect.end.x + 1.0,
		"property_panel_scrollable": is_instance_valid(_property_scroll) and _property_scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED and _property_scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED,
		"property_panel_width": property_rect.size.x,
		"layer_list_width": layer_rect.size.x,
		"configured_layer_panel_width": _layer_panel_width,
		"configured_property_panel_width": _property_panel_width,
		"footer_action_button_texts": action_button_texts,
		"footer_action_button_widths": action_button_widths,
		"footer_action_buttons_readable": action_buttons_readable,
		"has_status_panel": _status_panel != null and _status_panel.visible,
		"status_min_height": _status_panel.custom_minimum_size.y if _status_panel != null else 0.0,
		"timeline_visible": is_instance_valid(_timeline) and _timeline.visible and timeline_rect.size.y >= 130.0,
		"timeline_fits": is_instance_valid(_timeline) and timeline_rect.end.x <= creator_rect.end.x + 1.0,
		"timeline_height": timeline_rect.size.y,
		"preview_size": _preview.size if is_instance_valid(_preview) else Vector2.ZERO,
	}


func _layout_value_label_count() -> int:
	var count := 0
	for key in ["position_x", "position_y", "size_x", "size_y", "scale", "rotation"]:
		if _layout_spinners.has(key):
			count += 1
	return count


func _apply_compact_style(node: Node) -> void:
	if node is Window:
		return
	if node is Label:
		var label := node as Label
		if label == _status:
			label.add_theme_font_size_override("font_size", CREATOR_SMALL_FONT_SIZE)
			label.clip_text = false
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		else:
			label.add_theme_font_size_override("font_size", CREATOR_TITLE_FONT_SIZE if label.text in ["EMS CREATOR"] else CREATOR_FONT_SIZE)
			label.clip_text = true
			label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	elif node is Button:
		var button := node as Button
		button.add_theme_font_size_override("font_size", CREATOR_FONT_SIZE)
		_apply_button_style(button)
		if button.custom_minimum_size.y <= 0.0 or button.custom_minimum_size.y > CREATOR_CONTROL_HEIGHT:
			button.custom_minimum_size.y = CREATOR_CONTROL_HEIGHT
	elif node is OptionButton:
		var option := node as OptionButton
		option.add_theme_font_size_override("font_size", CREATOR_FONT_SIZE)
		_apply_button_style(option)
		if option.custom_minimum_size.y <= 0.0 or option.custom_minimum_size.y > CREATOR_CONTROL_HEIGHT:
			option.custom_minimum_size.y = CREATOR_CONTROL_HEIGHT
	elif node is CheckBox:
		var check := node as CheckBox
		check.add_theme_font_size_override("font_size", CREATOR_FONT_SIZE)
	elif node is SpinBox:
		var spin := node as SpinBox
		spin.add_theme_font_size_override("font_size", CREATOR_SMALL_FONT_SIZE)
		_apply_text_field_style(spin)
		if spin.custom_minimum_size.y <= 0.0 or spin.custom_minimum_size.y > CREATOR_CONTROL_HEIGHT:
			spin.custom_minimum_size.y = CREATOR_CONTROL_HEIGHT
	elif node is LineEdit:
		var line_edit := node as LineEdit
		line_edit.add_theme_font_size_override("font_size", CREATOR_FONT_SIZE)
		_apply_text_field_style(line_edit)
	elif node is HSlider:
		_apply_slider_style(node as HSlider)
	for child in node.get_children():
		_apply_compact_style(child)


func _apply_button_style(control: Control) -> void:
	control.add_theme_stylebox_override("normal", _control_style(Color(0.105, 0.118, 0.152, 0.96), Color(0.35, 0.82, 1.0, 0.25)))
	control.add_theme_stylebox_override("hover", _control_style(Color(0.145, 0.168, 0.215, 0.98), Color(0.42, 0.90, 1.0, 0.48)))
	control.add_theme_stylebox_override("pressed", _control_style(Color(0.070, 0.078, 0.110, 0.98), Color(0.95, 0.36, 1.0, 0.48)))
	control.add_theme_stylebox_override("disabled", _control_style(Color(0.060, 0.066, 0.084, 0.70), Color(0.35, 0.82, 1.0, 0.10)))
	control.add_theme_color_override("font_color", Color(0.92, 0.94, 1.0, 1.0))
	control.add_theme_color_override("font_disabled_color", Color(0.72, 0.74, 0.80, 0.58))


func _apply_text_field_style(control: Control) -> void:
	control.add_theme_stylebox_override("normal", _control_style(Color(0.090, 0.095, 0.122, 0.98), Color(0.35, 0.82, 1.0, 0.20)))
	control.add_theme_stylebox_override("focus", _control_style(Color(0.110, 0.120, 0.155, 0.98), Color(0.45, 0.90, 1.0, 0.50)))
	control.add_theme_stylebox_override("read_only", _control_style(Color(0.060, 0.066, 0.084, 0.85), Color(0.35, 0.82, 1.0, 0.10)))
	control.add_theme_color_override("font_color", Color(0.94, 0.96, 1.0, 1.0))
	control.add_theme_color_override("font_readonly_color", Color(0.74, 0.77, 0.86, 0.72))


func _apply_slider_style(slider: HSlider) -> void:
	slider.custom_minimum_size.y = 16
	slider.add_theme_stylebox_override("slider", _slider_track_style(Color(0.120, 0.128, 0.160, 0.98), Color(0.35, 0.82, 1.0, 0.16)))
	slider.add_theme_stylebox_override("grabber_area", _slider_track_style(Color(0.34, 0.82, 1.0, 0.58), Color(0.34, 0.82, 1.0, 0.0)))
	slider.add_theme_stylebox_override("grabber_area_highlight", _slider_track_style(Color(0.60, 0.90, 1.0, 0.80), Color(0.34, 0.82, 1.0, 0.0)))


func _control_style(bg: Color, border: Color, radius: int = 4) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1)
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	return style


func _slider_track_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := _control_style(bg, border, 6)
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	return style


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.038, 0.050, 0.76)
	style.border_color = Color(0.35, 0.82, 1.0, 0.18)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 5
	style.content_margin_right = 5
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	return style


func _status_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.030, 0.040, 0.95)
	style.border_color = Color(0.35, 0.82, 1.0, 0.35)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 5
	style.content_margin_right = 5
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style


func _label_badge(text: String, min_width: float = 0.0) -> PanelContainer:
	var badge := PanelContainer.new()
	badge.add_theme_stylebox_override("panel", _label_style())
	badge.custom_minimum_size = Vector2(min_width, CREATOR_CONTROL_HEIGHT)
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = false
	label.add_theme_font_size_override("font_size", CREATOR_SMALL_FONT_SIZE)
	badge.add_child(label)
	return badge


func _label_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.90)
	style.border_color = Color(0.0, 0.0, 0.0, 0.0)
	style.set_border_width_all(0)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	return style


func _save_draft_with_metadata(metadata: Dictionary) -> Dictionary:
	var details := _merged_metadata(metadata)
	if str(details.get("pack_id", "")) in ["creator_ems", "creator_pack"]:
		var stamp := str(int(Time.get_unix_time_from_system()))
		details["pack_id"] = "creator_draft_%s" % stamp
		details["title"] = "%s Draft %s" % [str(details.get("title", "Creator EMS")), stamp]
	details["include_creator_project"] = true
	details["install_local"] = true
	_last_export_metadata = details.duplicate(true)
	var result := EMSPackLoader.export_pack(EMSPackLoader.LOCAL_ROOT, _manifest_metadata(details, true), _current_config(true, details), _project_metadata(details), "", true)
	result["local_path"] = str(result.get("path", ""))
	_reload_registry()
	return result


func _draft_metadata() -> Dictionary:
	return _merged_metadata(_last_export_metadata)


func _export_pack_with_details(details_in: Dictionary) -> Dictionary:
	var details := _merged_metadata(details_in)
	_last_export_metadata = details.duplicate(true)
	var include_project := bool(details.get("include_creator_project", true))
	var config := _current_config(include_project, details)
	var project := _project_metadata(details) if include_project else {}
	var result := EMSPackLoader.export_pack(EMSPackLoader.EXPORT_ROOT, _manifest_metadata(details, include_project), config, project, "")
	if bool(result.get("ok", false)) and bool(details.get("install_local", true)):
		var install_result := EMSPackLoader.copy_validated_pack_to_root(str(result.get("path", "")), EMSPackLoader.LOCAL_ROOT, str(details.get("pack_id", "")))
		result["install_result"] = install_result
		result["local_path"] = str(install_result.get("path", ""))
		if not bool(install_result.get("ok", false)):
			result["ok"] = false
			result["message"] = "EMS pack exported but Local EMS install failed: %s" % str(install_result.get("message", ""))
	if bool(result.get("ok", false)):
		_reload_registry()
	return result


func _merged_metadata(metadata: Dictionary) -> Dictionary:
	var details := _last_export_metadata.duplicate(true)
	for key_variant in metadata.keys():
		details[str(key_variant)] = metadata[key_variant]
	var title_text := _clean_text(str(details.get("title", "Creator EMS")), "Creator EMS")
	var pack_id := EMSValidator.sanitize_pack_id(str(details.get("pack_id", "")))
	if pack_id.is_empty():
		pack_id = EMSValidator.sanitize_pack_id(title_text)
	if pack_id.is_empty():
		pack_id = "creator_ems"
	details["title"] = title_text
	details["pack_id"] = pack_id
	details["author"] = _clean_text(str(details.get("author", "Player")), "Player")
	details["description"] = _clean_text(str(details.get("description", "Created in the Harmonic Drive EMS Creator.")), "Created in the Harmonic Drive EMS Creator.")
	details["tags"] = _tags_array(details.get("tags", ["EMS", "Custom"]))
	details["include_creator_project"] = bool(details.get("include_creator_project", true))
	details["install_local"] = bool(details.get("install_local", true))
	details["visibility"] = str(details.get("visibility", details.get("workshop_visibility", "public"))).strip_edges().to_lower()
	if details["visibility"].is_empty():
		details["visibility"] = "public"
	details["workshop_visibility"] = details["visibility"]
	return details


func _manifest_metadata(details: Dictionary, include_project: bool) -> Dictionary:
	return {
		"schema_version": EMSValidator.SCHEMA_VERSION,
		"pack_type": EMSValidator.PACK_TYPE_CREATOR if include_project else EMSValidator.PACK_TYPE_CONFIG,
		"pack_id": str(details.get("pack_id", "creator_ems")),
		"title": str(details.get("title", "Creator EMS")),
		"author": str(details.get("author", "Player")),
		"description": str(details.get("description", "Created in the Harmonic Drive EMS Creator.")),
		"min_game_version": "1.0.0",
		"tags": _tags_array(details.get("tags", ["EMS", "Custom"])),
	}


func _project_metadata(details: Dictionary) -> Dictionary:
	return {
		"schema_version": EMSValidator.SCHEMA_VERSION,
		"pack_type": EMSValidator.PACK_TYPE_CREATOR,
		"pack_id": str(details.get("pack_id", "creator_ems")),
		"title": str(details.get("title", "Creator EMS")),
		"author": str(details.get("author", "Player")),
		"draft_name": str(details.get("title", "Creator EMS")),
		"layers": _layers.duplicate(true),
		"events": _events.duplicate(true),
		"layout": _layout.duplicate(true),
	}


func _metadata_from_validation(validation: Dictionary, folder_path: String) -> Dictionary:
	var config: Dictionary = validation.get("config", {}) as Dictionary
	var manifest: Dictionary = validation.get("manifest", {}) as Dictionary
	var pack_type := str(config.get("pack_type", manifest.get("pack_type", EMSValidator.PACK_TYPE_CREATOR)))
	var source := "local" if folder_path.begins_with("%s/" % EMSPackLoader.LOCAL_ROOT) else "export"
	return _merged_metadata({
		"title": str(config.get("title", manifest.get("title", folder_path.get_file()))),
		"pack_id": str(config.get("pack_id", manifest.get("pack_id", folder_path.get_file()))),
		"author": str(config.get("author", manifest.get("author", "Player"))),
		"description": str(config.get("description", manifest.get("description", "Created in the Harmonic Drive EMS Creator."))),
		"tags": manifest.get("tags", ["EMS", "Custom"]),
		"include_creator_project": pack_type == EMSValidator.PACK_TYPE_CREATOR,
		"install_local": source == "local",
		"visibility": str(config.get("visibility", manifest.get("visibility", "public"))),
		"workshop_visibility": str(config.get("workshop_visibility", manifest.get("workshop_visibility", "public"))),
	})


func _tags_array(value: Variant) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for item in value:
			var tag := _clean_text(str(item), "")
			if not tag.is_empty() and not out.has(tag):
				out.append(tag)
	else:
		for item in str(value).split(",", false):
			var tag := _clean_text(str(item), "")
			if not tag.is_empty() and not out.has(tag):
				out.append(tag)
	if out.is_empty():
		out = ["EMS", "Custom"]
	return out


func _clean_text(value: String, fallback: String) -> String:
	var text := value.strip_edges().replace("\n", " ").replace("\r", " ").replace("\t", " ")
	while text.contains("  "):
		text = text.replace("  ", " ")
	return fallback if text.is_empty() else text


func _reload_registry() -> void:
	var registry := get_node_or_null("/root/EMSRegistry")
	if registry != null and registry.has_method("reload"):
		registry.call("reload")


func _result_message(result: Dictionary, fallback: String) -> String:
	var message := str(result.get("message", fallback))
	var export_path := str(result.get("path", ""))
	var local_path := str(result.get("local_path", ""))
	if not export_path.is_empty() and not local_path.is_empty() and export_path != local_path:
		return "%s Exported to %s. Installed for testing at %s." % [message, export_path, local_path]
	if not local_path.is_empty():
		return "%s Saved to %s. Open Loadouts > Local EMS to equip it." % [message, local_path]
	if not export_path.is_empty():
		return "%s Saved to %s." % [message, export_path]
	return message


func _workshop_upload_result_message(upload_result: Dictionary, export_result: Dictionary, details: Dictionary) -> String:
	var message := str(upload_result.get("message", _workshop_manager.get_status()))
	var item_id := str(upload_result.get("item_id", details.get("workshop_item_id", details.get("existing_item_id", "")))).strip_edges()
	var visibility := str((upload_result.get("upload_metadata", {}) as Dictionary).get("visibility", details.get("visibility", "public"))).strip_edges().to_lower()
	var parts: Array[String] = [message]
	if not item_id.is_empty():
		parts.append("Item ID: %s." % item_id)
	parts.append("Visibility: %s." % visibility.capitalize())
	if visibility == "public":
		parts.append("Public visibility requested; Steam should clear the Workshop checklist after the item finishes processing and any legal agreement is accepted.")
	else:
		parts.append("Steam's public-item checklist will not clear until this item is set to Public.")
	var payload := upload_result.get("upload_payload", {}) as Dictionary
	if not payload.is_empty():
		parts.append("Payload: %s from %s." % [_bytes_label(int(payload.get("payload_size_bytes", 0))), str(payload.get("content_global_path", ""))])
	var log_path := str(upload_result.get("upload_log_path", "")).strip_edges()
	if not log_path.is_empty():
		parts.append("Log: %s." % log_path)
	parts.append("Keep Harmonic Drive open until Steam reports the upload completed.")
	parts.append("Export: %s" % str(export_result.get("path", "")))
	return " ".join(parts)


func _workshop_status_event_message(status: Dictionary) -> String:
	var message := str(status.get("message", _workshop_manager.get_status()))
	var item_id := str(status.get("item_id", "")).strip_edges()
	var visibility := str(status.get("visibility", "")).strip_edges().to_lower()
	var parts: Array[String] = [message]
	if not item_id.is_empty():
		parts.append("Item ID: %s." % item_id)
	if not visibility.is_empty():
		parts.append("Visibility: %s." % visibility.capitalize())
	var result_code := int(status.get("result_code", -1))
	if result_code >= 0 and status.has("result_code"):
		var result_name := str(status.get("result_name", ""))
		parts.append("Steam result: %d%s." % [result_code, " (%s)" % result_name if not result_name.is_empty() else ""])
	if bool(status.get("needs_legal_agreement", false)):
		parts.append("Accept the Steam Workshop legal agreement in Steam if prompted.")
	var progress := status.get("upload_progress", {}) as Dictionary
	if not progress.is_empty():
		var processed := int(progress.get("processed_bytes", 0))
		var total := int(progress.get("total_bytes", 0))
		if total > 0:
			parts.append("Progress: %s / %s." % [_bytes_label(processed), _bytes_label(total)])
	var payload := status.get("upload_payload", {}) as Dictionary
	if not payload.is_empty() and not bool(status.get("pending", false)):
		parts.append("Payload: %s." % _bytes_label(int(payload.get("payload_size_bytes", 0))))
	var log_path := str(status.get("upload_log_path", "")).strip_edges()
	if not log_path.is_empty():
		parts.append("Log: %s." % log_path)
	return " ".join(parts)


func _bytes_label(value: int) -> String:
	if value >= 1024 * 1024:
		return "%.1f MB" % (float(value) / float(1024 * 1024))
	if value >= 1024:
		return "%.1f KB" % (float(value) / 1024.0)
	return "%d B" % value
