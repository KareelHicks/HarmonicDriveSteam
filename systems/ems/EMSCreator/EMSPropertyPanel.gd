extends VBoxContainer
class_name EMSPropertyPanel

signal layer_changed(index: int, layer: Dictionary)
signal reactivity_rule_requested(rule: Dictionary)
signal layer_layout_requested(index: int, layer: Dictionary)

const EMSValidator = preload("res://systems/ems/EMSValidator.gd")
const EMSLoadoutCatalog = preload("res://scripts/ems/EMSLoadoutCatalog.gd")
const HDTheme = preload("res://scripts/ui/HDTheme.gd")

const LAYER_TYPES := [
	"solid_color",
	"gradient",
	"crt_gradient",
	"grid",
	"starfield",
	"particles",
	"floating_shapes",
	"tunnel",
	"scanlines",
	"glitch_overlay",
	"beat_pulse",
	"combo_aura",
	"miss_glitch",
	"image",
	"video",
	"signature_neon_rain",
	"signature_digital_snow",
	"signature_plasma_storm",
	"signature_quantum_grid",
	"signature_aurora_drive",
	"signature_cyber_ocean",
	"signature_fractal_space",
	"signature_prism_circuit",
	"signature_void_pulse",
	"signature_solar_bloom",
	"signature_lunar_glass",
	"signature_pixel_nebula",
	"signature_thunder_matrix",
	"signature_chromatic_rift",
	"signature_skyline_mirage",
	"signature_crystal_reactor",
	"signature_gravity_well",
	"signature_hypernova_flow",
	"signature_singularity_bloom",
]

const LAYER_TYPE_LABELS := {
	"solid_color": "Solid Color",
	"gradient": "Smooth Gradient",
	"crt_gradient": "CRT Gradient",
	"grid": "Grid",
	"starfield": "Starfield",
	"particles": "Particles",
	"floating_shapes": "Floating Shapes",
	"tunnel": "Tunnel",
	"scanlines": "Scanlines",
	"glitch_overlay": "Glitch Overlay",
	"beat_pulse": "Beat Pulse",
	"combo_aura": "Combo Aura",
	"miss_glitch": "Miss Glitch",
	"image": "Image",
	"video": "Video",
	"signature_neon_rain": "Built-In: Neon Rain",
	"signature_digital_snow": "Built-In: Digital Snow",
	"signature_plasma_storm": "Built-In: Plasma Storm",
	"signature_quantum_grid": "Built-In: Quantum Grid",
	"signature_aurora_drive": "Built-In: Aurora Drive",
	"signature_cyber_ocean": "Built-In: Cyber Ocean",
	"signature_fractal_space": "Built-In: Fractal Space",
	"signature_prism_circuit": "Built-In: Prism Circuit",
	"signature_void_pulse": "Built-In: Void Pulse",
	"signature_solar_bloom": "Built-In: Solar Bloom",
	"signature_lunar_glass": "Built-In: Lunar Glass",
	"signature_pixel_nebula": "Built-In: Pixel Nebula",
	"signature_thunder_matrix": "Built-In: Thunder Matrix",
	"signature_chromatic_rift": "Built-In: Chromatic Rift",
	"signature_skyline_mirage": "Built-In: Skyline Mirage",
	"signature_crystal_reactor": "Built-In: Crystal Reactor",
	"signature_gravity_well": "Built-In: Gravity Well",
	"signature_hypernova_flow": "Built-In: Hypernova Flow",
	"signature_singularity_bloom": "Built-In: Singularity Bloom",
}

const LAYER_TYPE_DESCRIPTIONS := {
	"solid_color": "Flat color wash for simple backplates and masks.",
	"gradient": "Smooth multi-color background with no scanline bands.",
	"crt_gradient": "CRT-style gradient with deliberate scanline bands.",
	"grid": "Moving EMS grid lines driven by spacing, thickness, and speed.",
	"starfield": "Depth-scaled stars, twinkle, streaks, and warp bursts.",
	"particles": "Small neon motes with glow cores, trails, and reactive bursts.",
	"floating_shapes": "Floating geometric shapes using the selected shape control.",
	"tunnel": "Nested depth rings for tunnel and portal effects.",
	"scanlines": "Animated scanline bands for CRT and display interference looks.",
	"glitch_overlay": "Horizontal glitch slices and disruption-like strips.",
	"beat_pulse": "Beat bars, compression rings, and impact flashes.",
	"combo_aura": "Layered aura halos, orbiting arcs, and combo glow wisps.",
	"miss_glitch": "Miss-reactive glitch bars and disruption strips.",
	"image": "Places a local image or animated image asset inside the selected EMS layout region.",
	"video": "Places a local video asset inside the selected EMS layout region. Video packs are local/testing only and are not Steam Workshop-safe.",
	"signature_neon_rain": "Creator-safe version of the Neon Rain built-in EMS effect.",
	"signature_digital_snow": "Creator-safe version of the Digital Snow built-in EMS effect.",
	"signature_plasma_storm": "Creator-safe version of the Plasma Storm built-in EMS effect.",
	"signature_quantum_grid": "Creator-safe version of the Quantum Grid built-in EMS effect.",
	"signature_aurora_drive": "Creator-safe version of the Aurora Drive built-in EMS effect.",
	"signature_cyber_ocean": "Creator-safe version of the Cyber Ocean built-in EMS effect.",
	"signature_fractal_space": "Creator-safe version of the Fractal Space built-in EMS effect.",
	"signature_prism_circuit": "Creator-safe version of the Prism Circuit built-in EMS effect.",
	"signature_void_pulse": "Creator-safe version of the Void Pulse built-in EMS effect.",
	"signature_solar_bloom": "Creator-safe version of the Solar Bloom built-in EMS effect.",
	"signature_lunar_glass": "Creator-safe version of the Lunar Glass built-in EMS effect.",
	"signature_pixel_nebula": "Creator-safe version of the Pixel Nebula built-in EMS effect.",
	"signature_thunder_matrix": "Creator-safe version of the Thunder Matrix built-in EMS effect.",
	"signature_chromatic_rift": "Creator-safe version of the Chromatic Rift built-in EMS effect.",
	"signature_skyline_mirage": "Creator-safe version of the Skyline Mirage built-in EMS effect.",
	"signature_crystal_reactor": "Creator-safe version of the Crystal Reactor built-in EMS effect.",
	"signature_gravity_well": "Creator-safe version of the Gravity Well built-in EMS effect.",
	"signature_hypernova_flow": "Creator-safe version of the Hypernova Flow built-in EMS effect.",
	"signature_singularity_bloom": "Creator-safe version of the Singularity Bloom built-in EMS effect.",
}

var _index := -1
var _layer: Dictionary = {}
var _name_edit: LineEdit
var _type_option: OptionButton
var _type_description_label: Label
var _numeric_labels: Dictionary = {}
var _numeric_sliders: Dictionary = {}
var _numeric_spinners: Dictionary = {}
var _reactive_toggle: CheckBox
var _player_reactive_option: OptionButton
var _media_box: VBoxContainer
var _media_source_label: Label
var _media_select_button: Button
var _media_clear_button: Button
var _media_fit_option: OptionButton
var _media_loop_toggle: CheckBox
var _media_warning_label: Label
var _media_file_dialog: FileDialog
var _primary_color_button: Button
var _primary_color_swatch: ColorRect
var _primary_color_label: Label
var _color_dialog: ConfirmationDialog
var _color_picker: ColorPicker
var _dialog_swatch: ColorRect
var _dialog_hex_label: Label
var _dialog_accept_button: Button
var _dialog_cancel_button: Button
var _pending_color := Color.WHITE
var _closing_color_dialog := false
var _last_color_dialog_visible := false
var _updating_controls := false
var _rebuild_count := 0


func edit_layer(index: int, layer: Dictionary) -> void:
	var selection_changed := index != _index
	_index = index
	_layer = layer.duplicate(true)
	if selection_changed or get_child_count() == 0:
		_rebuild()
	else:
		_sync_controls_from_layer()


func get_editor_debug_state() -> Dictionary:
	return {
		"index": _index,
		"rebuild_count": _rebuild_count,
		"opacity": float(_layer.get("opacity", 0.0)),
		"intensity": float(_layer.get("intensity", 0.0)),
		"particle_count": int(_layer.get("particle_count", 0)),
		"name": str(_layer.get("name", "")),
		"color": str(_layer.get("color", "")),
		"audio_reactive": bool(_layer.get("reactive", true)),
		"player_reactive": str(_layer.get("player_reactive", "off")),
		"layout_mode": str(_layer.get("layout_mode", "pack")),
		"layout_source": str(_layer.get("layout_source", "")),
		"has_layer_type_description": is_instance_valid(_type_description_label) and not _type_description_label.text.is_empty(),
		"has_color_swatch": is_instance_valid(_primary_color_swatch),
		"has_color_dialog": is_instance_valid(_color_dialog),
		"has_visible_accept_button": is_instance_valid(_dialog_accept_button) and _dialog_accept_button.visible,
		"has_media_controls": is_instance_valid(_media_box),
		"media_controls_visible": is_instance_valid(_media_box) and _media_box.visible,
		"media_kind": str(_layer.get("media_kind", "")),
		"asset_path": str(_layer.get("asset_path", "")),
		"source_path": str(_layer.get("source_path", "")),
		"layer_type_options": _layer_type_options_for_test(),
	}


func set_numeric_value_for_test(key: String, value: float) -> void:
	_set_numeric_value(key, value, true)


func set_layer_name_for_test(value: String) -> void:
	if is_instance_valid(_name_edit):
		_name_edit.text = value
	_on_layer_name_changed(value)


func set_audio_reactive_for_test(value: bool) -> void:
	_on_audio_reactive_toggled(value)


func set_player_reactive_for_test(mode: String) -> void:
	_select_player_reactive_mode(mode)
	_on_player_reactive_selected(_player_reactive_option.selected if is_instance_valid(_player_reactive_option) else 0)


func preview_primary_color_for_test(color: Color) -> void:
	_closing_color_dialog = false
	_pending_color = color
	_sync_dialog_color_preview(color)


func accept_primary_color_for_test() -> void:
	_commit_primary_color()


func cancel_primary_color_for_test() -> void:
	_cancel_primary_color_dialog()


func outside_close_primary_color_for_test() -> void:
	_commit_primary_color()


func open_primary_color_dialog_for_test() -> void:
	_open_primary_color_dialog()


func hide_primary_color_dialog_for_test() -> void:
	if is_instance_valid(_color_dialog):
		_color_dialog.hide()


func simulate_stale_color_dialog_for_test() -> void:
	if is_instance_valid(_color_dialog):
		_color_dialog.free()


func _rebuild() -> void:
	add_theme_constant_override("separation", 3)
	_rebuild_count += 1
	for child in get_children():
		child.queue_free()
	_clear_control_refs()
	_numeric_labels.clear()
	_numeric_sliders.clear()
	_numeric_spinners.clear()
	var title := Label.new()
	title.text = "PROPERTIES"
	add_child(title)
	if _index < 0:
		var empty := Label.new()
		empty.text = "Select a layer."
		add_child(empty)
		return
	_name_edit = LineEdit.new()
	_name_edit.text = str(_layer.get("name", "Layer"))
	_name_edit.placeholder_text = "Layer name"
	_name_edit.text_changed.connect(_on_layer_name_changed)
	add_child(_labeled("Layer Name", _name_edit))
	_type_option = OptionButton.new()
	for type_name in _visible_layer_types():
		_type_option.add_item(_layer_type_label(type_name))
		_type_option.set_item_metadata(_type_option.get_item_count() - 1, type_name)
		if type_name == str(_layer.get("type", "")):
			_type_option.select(_type_option.get_item_count() - 1)
	_type_option.item_selected.connect(_on_type_changed)
	_type_option.tooltip_text = _layer_type_description(str(_layer.get("type", "")))
	add_child(_labeled("Layer Type", _type_option))
	_type_description_label = Label.new()
	_type_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_type_description_label.text = _layer_type_description(str(_layer.get("type", "")))
	add_child(_type_description_label)
	_add_numeric_editor("opacity", "Opacity", float(_layer.get("opacity", 0.75)), 0.0, 1.0, 0.01, false)
	_add_numeric_editor("intensity", "Intensity", float(_layer.get("intensity", 1.0)), 0.0, 2.0, 0.01, false)
	_add_numeric_editor("particle_count", "Particles", float(_layer.get("particle_count", 0)), 0.0, 500.0, 1.0, true)
	_reactive_toggle = CheckBox.new()
	_reactive_toggle.text = "Audio Reactive"
	_reactive_toggle.button_pressed = bool(_layer.get("reactive", true))
	_reactive_toggle.toggled.connect(_on_audio_reactive_toggled)
	add_child(_reactive_toggle)
	_player_reactive_option = OptionButton.new()
	_player_reactive_option.add_item("Off")
	_player_reactive_option.add_item("Successful Hits")
	_player_reactive_option.add_item("Misses")
	_player_reactive_option.item_selected.connect(_on_player_reactive_selected)
	add_child(_labeled("Player Reactive", _player_reactive_option))
	_build_media_editor()
	var layout_button := Button.new()
	layout_button.text = "EDIT LAYOUT"
	layout_button.custom_minimum_size.y = 24
	layout_button.clip_text = true
	layout_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	layout_button.pressed.connect(func():
		if _index >= 0:
			layer_layout_requested.emit(_index, _layer.duplicate(true))
	)
	add_child(layout_button)
	_build_color_editor()
	_sync_controls_from_layer()


func _clear_control_refs() -> void:
	_name_edit = null
	_type_option = null
	_type_description_label = null
	_reactive_toggle = null
	_player_reactive_option = null
	_primary_color_button = null
	_primary_color_swatch = null
	_primary_color_label = null
	_media_box = null
	_media_source_label = null
	_media_select_button = null
	_media_clear_button = null
	_media_fit_option = null
	_media_loop_toggle = null
	_media_warning_label = null
	_media_file_dialog = null
	_clear_color_dialog_refs(false)
	_closing_color_dialog = false
	_last_color_dialog_visible = false


func _clear_color_dialog_refs(free_existing: bool) -> void:
	if free_existing and is_instance_valid(_color_dialog):
		_color_dialog.queue_free()
	_color_dialog = null
	_color_picker = null
	_dialog_swatch = null
	_dialog_hex_label = null
	_dialog_accept_button = null
	_dialog_cancel_button = null


func _sync_controls_from_layer() -> void:
	if _index < 0:
		return
	_updating_controls = true
	if is_instance_valid(_name_edit):
		_name_edit.text = str(_layer.get("name", "Layer"))
	if is_instance_valid(_type_option):
		for i in range(_type_option.get_item_count()):
			if str(_type_option.get_item_metadata(i)) == str(_layer.get("type", "")):
				_type_option.select(i)
				break
		_type_option.tooltip_text = _layer_type_description(str(_layer.get("type", "")))
	if is_instance_valid(_type_description_label):
		_type_description_label.text = _layer_type_description(str(_layer.get("type", "")))
	_sync_numeric_editor("opacity", float(_layer.get("opacity", 0.75)))
	_sync_numeric_editor("intensity", float(_layer.get("intensity", 1.0)))
	_sync_numeric_editor("particle_count", float(_layer.get("particle_count", 0)))
	if is_instance_valid(_reactive_toggle):
		_reactive_toggle.button_pressed = bool(_layer.get("reactive", true))
	_select_player_reactive_mode(str(_layer.get("player_reactive", "off")))
	_sync_media_controls()
	_update_color_swatch(_color_from_hex(str(_layer.get("color", "#55DFFFFF"))))
	_updating_controls = false


func _add_numeric_editor(key: String, label_text: String, value: float, min_value: float, max_value: float, step: float, integer_value: bool) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	var header := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(label)
	var value_label := Label.new()
	value_label.text = _format_numeric_value(value, integer_value)
	header.add_child(value_label)
	box.add_child(header)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.value = clampf(value, min_value, max_value)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(next_value: float): _set_numeric_value(key, next_value, true))
	row.add_child(slider)
	var spinner := SpinBox.new()
	spinner.min_value = min_value
	spinner.max_value = max_value
	spinner.step = step
	spinner.value = clampf(value, min_value, max_value)
	spinner.custom_minimum_size = Vector2(58, 24)
	spinner.value_changed.connect(func(next_value: float): _set_numeric_value(key, next_value, false))
	row.add_child(spinner)
	box.add_child(row)
	_numeric_labels[key] = {"label": value_label, "integer": integer_value}
	_numeric_sliders[key] = slider
	_numeric_spinners[key] = spinner
	add_child(box)


func _sync_numeric_editor(key: String, value: float) -> void:
	var slider: HSlider = _numeric_sliders.get(key, null)
	var spinner: SpinBox = _numeric_spinners.get(key, null)
	var label_info: Dictionary = _numeric_labels.get(key, {}) as Dictionary
	var integer_value := bool(label_info.get("integer", false))
	if is_instance_valid(slider):
		slider.value = clampf(value, slider.min_value, slider.max_value)
	if is_instance_valid(spinner):
		spinner.value = clampf(value, spinner.min_value, spinner.max_value)
	var label: Label = label_info.get("label", null)
	if is_instance_valid(label):
		label.text = _format_numeric_value(value, integer_value)


func _set_numeric_value(key: String, value: float, from_slider: bool) -> void:
	if _updating_controls or _index < 0:
		return
	var label_info: Dictionary = _numeric_labels.get(key, {}) as Dictionary
	var integer_value := bool(label_info.get("integer", false))
	var slider: HSlider = _numeric_sliders.get(key, null)
	var spinner: SpinBox = _numeric_spinners.get(key, null)
	var min_value := slider.min_value if is_instance_valid(slider) else 0.0
	var max_value := slider.max_value if is_instance_valid(slider) else 1.0
	var next_value := clampf(value, min_value, max_value)
	var stored_value: Variant = int(round(next_value)) if integer_value else next_value
	_updating_controls = true
	if is_instance_valid(slider) and not from_slider:
		slider.value = next_value
	if is_instance_valid(spinner) and from_slider:
		spinner.value = next_value
	var label: Label = label_info.get("label", null)
	if is_instance_valid(label):
		label.text = _format_numeric_value(next_value, integer_value)
	_updating_controls = false
	_update_value(key, stored_value)


func _format_numeric_value(value: float, integer_value: bool) -> String:
	if integer_value:
		return str(int(round(value)))
	return "%.2f" % value


func _build_color_editor() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	var label := Label.new()
	label.text = "Primary Color"
	box.add_child(label)
	_primary_color_button = Button.new()
	_primary_color_button.text = "SELECT COLOR"
	_primary_color_button.custom_minimum_size.y = 24
	_primary_color_button.clip_text = true
	_primary_color_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_primary_color_button.pressed.connect(_open_primary_color_dialog)
	box.add_child(_primary_color_button)
	var preview_row := HBoxContainer.new()
	preview_row.add_theme_constant_override("separation", 6)
	_primary_color_swatch = ColorRect.new()
	_primary_color_swatch.custom_minimum_size = Vector2(34, 18)
	preview_row.add_child(_primary_color_swatch)
	_primary_color_label = Label.new()
	_primary_color_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_row.add_child(_primary_color_label)
	box.add_child(preview_row)
	add_child(box)
	_ensure_color_dialog()
	_update_color_swatch(_color_from_hex(str(_layer.get("color", "#55DFFFFF"))))


func _build_media_editor() -> void:
	_media_box = VBoxContainer.new()
	_media_box.add_theme_constant_override("separation", 3)
	var title := Label.new()
	title.text = "Media"
	_media_box.add_child(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	_media_select_button = Button.new()
	_media_select_button.text = "SELECT MEDIA"
	_media_select_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_media_select_button.clip_text = true
	_media_select_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_media_select_button.pressed.connect(_open_media_file_dialog)
	row.add_child(_media_select_button)
	_media_clear_button = Button.new()
	_media_clear_button.text = "CLEAR"
	_media_clear_button.custom_minimum_size.x = 54
	_media_clear_button.pressed.connect(_clear_media_path)
	row.add_child(_media_clear_button)
	_media_box.add_child(row)
	_media_source_label = Label.new()
	_media_source_label.clip_text = true
	_media_source_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_media_box.add_child(_media_source_label)
	_media_fit_option = OptionButton.new()
	for fit_mode in EMSValidator.MEDIA_FIT_MODES:
		_media_fit_option.add_item(fit_mode.capitalize())
		_media_fit_option.set_item_metadata(_media_fit_option.get_item_count() - 1, fit_mode)
	_media_fit_option.item_selected.connect(_on_media_fit_selected)
	_media_box.add_child(_labeled("Fit", _media_fit_option))
	_media_loop_toggle = CheckBox.new()
	_media_loop_toggle.text = "Loop media"
	_media_loop_toggle.toggled.connect(_on_media_loop_toggled)
	_media_box.add_child(_media_loop_toggle)
	_media_warning_label = Label.new()
	_media_warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_media_warning_label.text = "Video packs are local/testing only. Steam Workshop uploads are not supported for video packs because of large file sizes and decoder limits."
	_media_box.add_child(_media_warning_label)
	_media_file_dialog = FileDialog.new()
	_media_file_dialog.title = "Select EMS Media"
	_media_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_media_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_media_file_dialog.file_selected.connect(_on_media_file_selected)
	add_child(_media_box)
	add_child(_media_file_dialog)
	HDTheme.apply_dialog(_media_file_dialog)
	_sync_media_controls()


func _ensure_color_dialog() -> void:
	if is_instance_valid(_color_dialog) and is_instance_valid(_color_picker):
		return
	_clear_color_dialog_refs(true)
	_color_dialog = ConfirmationDialog.new()
	_color_dialog.title = "Primary Color"
	_color_dialog.ok_button_text = "Accept"
	_color_dialog.cancel_button_text = "Cancel"
	_color_dialog.exclusive = false
	_color_dialog.confirmed.connect(_commit_primary_color)
	_color_dialog.canceled.connect(_cancel_primary_color_dialog)
	_color_dialog.close_requested.connect(_commit_primary_color)
	_color_dialog.visibility_changed.connect(_on_color_dialog_visibility_changed)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 8)
	_dialog_accept_button = Button.new()
	_dialog_accept_button.text = "ACCEPT COLOR"
	_dialog_accept_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dialog_accept_button.pressed.connect(func():
		_commit_primary_color()
		if is_instance_valid(_color_dialog):
			_color_dialog.hide()
	)
	action_row.add_child(_dialog_accept_button)
	_dialog_cancel_button = Button.new()
	_dialog_cancel_button.text = "CANCEL"
	_dialog_cancel_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dialog_cancel_button.pressed.connect(func():
		_cancel_primary_color_dialog()
		if is_instance_valid(_color_dialog):
			_color_dialog.hide()
	)
	action_row.add_child(_dialog_cancel_button)
	root.add_child(action_row)
	_color_picker = ColorPicker.new()
	_color_picker.color_changed.connect(_on_dialog_color_changed)
	root.add_child(_color_picker)
	var preview_row := HBoxContainer.new()
	preview_row.add_theme_constant_override("separation", 6)
	_dialog_swatch = ColorRect.new()
	_dialog_swatch.custom_minimum_size = Vector2(52, 24)
	preview_row.add_child(_dialog_swatch)
	_dialog_hex_label = Label.new()
	_dialog_hex_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_row.add_child(_dialog_hex_label)
	root.add_child(preview_row)
	_color_dialog.add_child(root)
	add_child(_color_dialog)
	HDTheme.apply_dialog(_color_dialog)


func _open_primary_color_dialog() -> void:
	_ensure_color_dialog()
	_pending_color = _color_from_hex(str(_layer.get("color", "#55DFFFFF")))
	if not is_instance_valid(_color_picker) or not is_instance_valid(_color_dialog):
		return
	_color_picker.color = _pending_color
	_sync_dialog_color_preview(_pending_color)
	_closing_color_dialog = false
	_last_color_dialog_visible = true
	_color_dialog.popup_centered(Vector2i(560, 620))


func _on_dialog_color_changed(value: Color) -> void:
	_pending_color = value
	_sync_dialog_color_preview(value)


func _commit_primary_color() -> void:
	if _closing_color_dialog:
		return
	_closing_color_dialog = true
	var color_text := "#%s" % _pending_color.to_html(true)
	_update_color_swatch(_pending_color)
	_update_value("color", color_text)


func _cancel_primary_color_dialog() -> void:
	if _closing_color_dialog:
		return
	_closing_color_dialog = true
	_pending_color = _color_from_hex(str(_layer.get("color", "#55DFFFFF")))
	_sync_dialog_color_preview(_pending_color)


func _on_color_dialog_visibility_changed() -> void:
	if not is_instance_valid(_color_dialog):
		return
	var visible := _color_dialog.visible
	if _last_color_dialog_visible and not visible and not _closing_color_dialog:
		_commit_primary_color()
	if visible:
		_closing_color_dialog = false
	_last_color_dialog_visible = visible


func _sync_dialog_color_preview(value: Color) -> void:
	if is_instance_valid(_dialog_swatch):
		_dialog_swatch.color = value
	if is_instance_valid(_dialog_hex_label):
		_dialog_hex_label.text = "#%s" % value.to_html(true).to_upper()


func _update_color_swatch(value: Color) -> void:
	if is_instance_valid(_primary_color_swatch):
		_primary_color_swatch.color = value
	if is_instance_valid(_primary_color_label):
		_primary_color_label.text = "#%s" % value.to_html(true).to_upper()


func _on_type_changed(index: int) -> void:
	if _updating_controls:
		return
	var value := str(_type_option.get_item_metadata(index)) if is_instance_valid(_type_option) else ""
	if value.is_empty() and index >= 0 and index < LAYER_TYPES.size():
		value = LAYER_TYPES[index]
	if is_instance_valid(_type_option):
		_type_option.tooltip_text = _layer_type_description(value)
	if is_instance_valid(_type_description_label):
		_type_description_label.text = _layer_type_description(value)
	if value in ["image", "video"]:
		_layer["media_kind"] = value
		if not _layer.has("fit_mode"):
			_layer["fit_mode"] = "cover"
		if not _layer.has("loop"):
			_layer["loop"] = true
	else:
		_layer["media_kind"] = ""
	_update_value("type", value)
	_sync_media_controls()


func _sync_media_controls() -> void:
	var layer_type := str(_layer.get("type", ""))
	var visible := layer_type in ["image", "video"]
	if is_instance_valid(_media_box):
		_media_box.visible = visible
	if not visible:
		return
	if is_instance_valid(_media_select_button):
		_media_select_button.text = "SELECT IMAGE" if layer_type == "image" else "SELECT VIDEO"
	if is_instance_valid(_media_warning_label):
		_media_warning_label.visible = layer_type == "video"
	var source_text := str(_layer.get("source_path", "")).strip_edges()
	var asset_text := str(_layer.get("asset_path", "")).strip_edges()
	var display := source_text if not source_text.is_empty() else asset_text
	if display.is_empty():
		display = "No media selected."
	if is_instance_valid(_media_source_label):
		_media_source_label.text = display
		_media_source_label.tooltip_text = display
	if is_instance_valid(_media_fit_option):
		_select_option_metadata(_media_fit_option, str(_layer.get("fit_mode", "cover")))
	if is_instance_valid(_media_loop_toggle):
		_media_loop_toggle.button_pressed = bool(_layer.get("loop", true))


func _open_media_file_dialog() -> void:
	if not is_instance_valid(_media_file_dialog):
		return
	var layer_type := str(_layer.get("type", ""))
	if layer_type == "image":
		_media_file_dialog.filters = PackedStringArray([
			"*.png, *.jpg, *.jpeg, *.webp, *.bmp, *.tga, *.svg, *.gif ; Image Files",
			"*.gif ; Animated GIF Files",
			"*.* ; All Files",
		])
	elif layer_type == "video":
		_media_file_dialog.filters = PackedStringArray([
			"*.ogv, *.ogg, *.webm, *.mp4, *.m4v, *.mov, *.avi, *.mkv ; Video Files",
			"*.* ; All Files",
		])
	else:
		return
	_media_file_dialog.popup_centered(Vector2i(820, 560))


func _on_media_file_selected(path: String) -> void:
	var layer_type := str(_layer.get("type", ""))
	if layer_type not in ["image", "video"]:
		return
	_layer["media_kind"] = layer_type
	_layer["source_path"] = path
	_layer["asset_path"] = ""
	if not _layer.has("fit_mode"):
		_layer["fit_mode"] = "cover"
	if not _layer.has("loop"):
		_layer["loop"] = true
	_sync_media_controls()
	layer_changed.emit(_index, _layer.duplicate(true))


func _clear_media_path() -> void:
	_layer["source_path"] = ""
	_layer["asset_path"] = ""
	_sync_media_controls()
	layer_changed.emit(_index, _layer.duplicate(true))


func _on_media_fit_selected(index: int) -> void:
	if _updating_controls or not is_instance_valid(_media_fit_option):
		return
	var value := str(_media_fit_option.get_item_metadata(index))
	_update_value("fit_mode", value)


func _on_media_loop_toggled(value: bool) -> void:
	if _updating_controls:
		return
	_update_value("loop", value)


func _on_layer_name_changed(value: String) -> void:
	if _updating_controls:
		return
	var clean := value.strip_edges()
	if clean.is_empty():
		clean = "Layer"
	_update_value("name", clean)


func _on_audio_reactive_toggled(value: bool) -> void:
	if _updating_controls:
		return
	_update_value("reactive", value)
	if value:
		_emit_reactivity_rule_request(_prefilled_reactivity_rule("audio_reactive"))


func _on_player_reactive_selected(_index: int) -> void:
	if _updating_controls:
		return
	var mode := _selected_player_reactive_mode()
	_update_value("player_reactive", mode)
	match mode:
		"hit":
			_emit_reactivity_rule_request(_prefilled_reactivity_rule("player_hit"))
		"miss":
			_emit_reactivity_rule_request(_prefilled_reactivity_rule("player_miss"))


func _select_player_reactive_mode(mode: String) -> void:
	if not is_instance_valid(_player_reactive_option):
		return
	var normalized := mode.strip_edges().to_lower()
	var index := 0
	match normalized:
		"hit":
			index = 1
		"miss":
			index = 2
		_:
			index = 0
	_player_reactive_option.select(index)


func _select_option_metadata(option: OptionButton, value: String) -> void:
	if not is_instance_valid(option):
		return
	for i in range(option.get_item_count()):
		if str(option.get_item_metadata(i)) == value:
			option.select(i)
			return


func _selected_player_reactive_mode() -> String:
	if not is_instance_valid(_player_reactive_option):
		return "off"
	match _player_reactive_option.selected:
		1:
			return "hit"
		2:
			return "miss"
		_:
			return "off"


func _update_value(key: String, value: Variant) -> void:
	if _index < 0:
		return
	_layer[key] = value
	layer_changed.emit(_index, _layer.duplicate(true))


func _emit_reactivity_rule_request(rule: Dictionary) -> void:
	if _index < 0 or rule.is_empty():
		return
	reactivity_rule_requested.emit(rule)


func _prefilled_reactivity_rule(event_name: String) -> Dictionary:
	var target := str(_layer.get("id", "*")).strip_edges()
	if target.is_empty():
		target = "*"
	var action := "pulse_opacity"
	var params := {"opacity": 0.95, "duration": 0.18}
	if event_name == "player_hit":
		action = "pulse_scale"
		params = {"scale": 1.22, "duration": 0.16}
	elif event_name == "player_miss":
		action = "pulse_opacity"
		params = {"opacity": 0.35, "duration": 0.22}
	return {
		"event": event_name,
		"action": action,
		"target": target,
		"params": params,
		"threshold": 0.0,
		"cooldown": 0.0,
	}


func _labeled(text: String, control: Control) -> VBoxContainer:
	var box := VBoxContainer.new()
	var label := Label.new()
	label.text = text
	box.add_child(label)
	box.add_child(control)
	return box


func _layer_type_label(type_name: String) -> String:
	return str(LAYER_TYPE_LABELS.get(type_name, type_name.capitalize()))


func _layer_type_description(type_name: String) -> String:
	return str(LAYER_TYPE_DESCRIPTIONS.get(type_name, "Custom EMS layer renderer."))


func _visible_layer_types() -> Array[String]:
	var visible: Array[String] = []
	for type_name in LAYER_TYPES:
		if EMSLoadoutCatalog.is_layer_type_content_available(type_name):
			visible.append(type_name)
	return visible


func _layer_type_options_for_test() -> Array[String]:
	var options: Array[String] = []
	if not is_instance_valid(_type_option):
		return options
	for i in range(_type_option.get_item_count()):
		options.append(str(_type_option.get_item_metadata(i)))
	return options


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
