extends ConfirmationDialog
class_name EMSLayerTypeBuilderDialog

signal layer_created(layer: Dictionary)
signal template_saved(template: Dictionary, layer: Dictionary)

const EMSValidator = preload("res://systems/ems/EMSValidator.gd")
const EMSLoadoutCatalog = preload("res://scripts/ems/EMSLoadoutCatalog.gd")
const HDTheme = preload("res://scripts/ui/HDTheme.gd")

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
	"solid_color": "A flat color wash for simple backplates and masks.",
	"gradient": "A smooth multi-color background with no scanline bands.",
	"crt_gradient": "A CRT-style gradient with deliberate scanline bands.",
	"grid": "Moving EMS grid lines driven by spacing, thickness, and speed.",
	"starfield": "Depth-scaled stars, twinkle, streaks, and warp bursts.",
	"particles": "Small neon motes with glow cores, trails, and reactive bursts.",
	"floating_shapes": "Floating geometric shapes using the selected shape control.",
	"tunnel": "Nested depth rings for tunnel and portal effects.",
	"scanlines": "Animated scanline bands for CRT and display interference looks.",
	"glitch_overlay": "Horizontal glitch slices and displacement-like strips.",
	"beat_pulse": "Beat bars, compression rings, and impact flashes.",
	"combo_aura": "Layered aura halos, orbiting arcs, and combo glow wisps.",
	"miss_glitch": "Miss-reactive glitch bars and disruption strips.",
	"image": "Image layer. Pick the media file from the Properties panel after adding it.",
	"video": "Video layer. Pick the video from Properties. Video packs are local/testing only and not Steam Workshop-safe.",
	"signature_neon_rain": "Built-in Neon Rain style as a Creator-safe draw-only layer.",
	"signature_digital_snow": "Built-in Digital Snow style as a Creator-safe draw-only layer.",
	"signature_plasma_storm": "Built-in Plasma Storm style as a Creator-safe draw-only layer.",
	"signature_quantum_grid": "Built-in Quantum Grid style as a Creator-safe draw-only layer.",
	"signature_aurora_drive": "Built-in Aurora Drive style as a Creator-safe draw-only layer.",
	"signature_cyber_ocean": "Built-in Cyber Ocean style as a Creator-safe draw-only layer.",
	"signature_fractal_space": "Built-in Fractal Space style as a Creator-safe draw-only layer.",
	"signature_prism_circuit": "Built-in Prism Circuit style as a Creator-safe draw-only layer.",
	"signature_void_pulse": "Built-in Void Pulse style as a Creator-safe draw-only layer.",
	"signature_solar_bloom": "Built-in Solar Bloom style as a Creator-safe draw-only layer.",
	"signature_lunar_glass": "Built-in Lunar Glass style as a Creator-safe draw-only layer.",
	"signature_pixel_nebula": "Built-in Pixel Nebula style as a Creator-safe draw-only layer.",
	"signature_thunder_matrix": "Built-in Thunder Matrix style as a Creator-safe draw-only layer.",
	"signature_chromatic_rift": "Built-in Chromatic Rift style as a Creator-safe draw-only layer.",
	"signature_skyline_mirage": "Built-in Skyline Mirage style as a Creator-safe draw-only layer.",
	"signature_crystal_reactor": "Built-in Crystal Reactor style as a Creator-safe draw-only layer.",
	"signature_gravity_well": "Built-in Gravity Well style as a Creator-safe draw-only layer.",
	"signature_hypernova_flow": "Built-in Hypernova Flow style as a Creator-safe draw-only layer.",
	"signature_singularity_bloom": "Built-in Singularity Bloom style as a Creator-safe draw-only layer.",
}

const LAYER_TYPE_DEFAULTS := {
	"particles": {"particle_count": 72.0, "scale": 0.42, "thickness": 1.0, "speed": 0.42, "amplitude": 0.46, "frequency": 1.4, "estimated_cost": 0.28},
	"starfield": {"particle_count": 180.0, "scale": 0.55, "thickness": 1.0, "speed": 0.58, "direction": 90.0, "amplitude": 0.65, "frequency": 1.7, "estimated_cost": 0.36},
	"beat_pulse": {"particle_count": 0.0, "speed": 0.50, "frequency": 1.0, "amplitude": 0.48, "segments": 22.0, "thickness": 2.4, "scale": 1.0, "estimated_cost": 0.20},
	"combo_aura": {"particle_count": 0.0, "speed": 0.36, "frequency": 0.8, "amplitude": 0.50, "points": 12.0, "segments": 24.0, "scale": 1.15, "thickness": 2.0, "estimated_cost": 0.22},
	"image": {"particle_count": 0.0, "speed": 0.0, "scale": 1.0, "estimated_cost": 0.18},
	"video": {"particle_count": 0.0, "speed": 0.0, "scale": 1.0, "estimated_cost": 0.70},
}

const TYPE_CONTROL_KEYS := {
	"solid_color": ["opacity", "intensity", "position_x", "position_y", "size_x", "size_y", "scale", "rotation", "estimated_cost"],
	"gradient": ["opacity", "intensity", "speed", "direction", "frequency", "amplitude", "scale", "rotation", "position_x", "position_y", "size_x", "size_y", "estimated_cost"],
	"crt_gradient": ["opacity", "intensity", "speed", "direction", "frequency", "amplitude", "spacing", "thickness", "scale", "rotation", "position_x", "position_y", "size_x", "size_y", "estimated_cost"],
	"grid": ["opacity", "intensity", "speed", "direction", "frequency", "amplitude", "spacing", "thickness", "scale", "rotation", "position_x", "position_y", "size_x", "size_y", "estimated_cost"],
	"starfield": ["opacity", "intensity", "particle_count", "speed", "direction", "frequency", "amplitude", "thickness", "scale", "rotation", "position_x", "position_y", "size_x", "size_y", "estimated_cost"],
	"particles": ["opacity", "intensity", "particle_count", "speed", "direction", "frequency", "amplitude", "thickness", "scale", "rotation", "position_x", "position_y", "size_x", "size_y", "estimated_cost"],
	"floating_shapes": ["opacity", "intensity", "particle_count", "speed", "direction", "frequency", "amplitude", "points", "thickness", "scale", "rotation", "position_x", "position_y", "size_x", "size_y", "estimated_cost"],
	"tunnel": ["opacity", "intensity", "speed", "direction", "frequency", "amplitude", "segments", "thickness", "scale", "rotation", "position_x", "position_y", "size_x", "size_y", "estimated_cost"],
	"scanlines": ["opacity", "intensity", "speed", "direction", "frequency", "spacing", "thickness", "distortion", "position_x", "position_y", "size_x", "size_y", "estimated_cost"],
	"glitch_overlay": ["opacity", "intensity", "speed", "direction", "frequency", "spacing", "thickness", "distortion", "shake", "position_x", "position_y", "size_x", "size_y", "estimated_cost"],
	"beat_pulse": ["opacity", "intensity", "speed", "frequency", "amplitude", "segments", "thickness", "scale", "rotation", "position_x", "position_y", "size_x", "size_y", "estimated_cost"],
	"combo_aura": ["opacity", "intensity", "speed", "frequency", "amplitude", "points", "segments", "thickness", "scale", "rotation", "position_x", "position_y", "size_x", "size_y", "estimated_cost"],
	"miss_glitch": ["opacity", "intensity", "speed", "direction", "frequency", "spacing", "thickness", "distortion", "shake", "position_x", "position_y", "size_x", "size_y", "estimated_cost"],
	"image": ["opacity", "intensity", "scale", "rotation", "position_x", "position_y", "size_x", "size_y", "estimated_cost"],
	"video": ["opacity", "intensity", "scale", "rotation", "position_x", "position_y", "size_x", "size_y", "estimated_cost"],
}

var _preset_row: Control
var _preset_option: OptionButton
var _type_option: OptionButton
var _description_label: Label
var _shape_option: OptionButton
var _blend_option: OptionButton
var _name_edit: LineEdit
var _color_picker: ColorPickerButton
var _palette_a: ColorPickerButton
var _palette_b: ColorPickerButton
var _reactive_toggle: CheckBox
var _player_reactive_option: OptionButton
var _low_motion_toggle: CheckBox
var _spins: Dictionary = {}
var _spin_rows: Dictionary = {}
var _custom_templates: Array[Dictionary] = []
var _applying_type_defaults := false
var _updating_preset := false
var _mode := "add_layer"


func _ready() -> void:
	title = "Add EMS Layer"
	ok_button_text = "Add Layer"
	cancel_button_text = "Cancel"
	confirmed.connect(_commit_layer)
	_build_ui()
	HDTheme.apply_dialog(self)


func get_debug_state() -> Dictionary:
	return {
		"has_type_option": _type_option != null,
		"has_motion_controls": _spins.has("speed") and _spins.has("frequency") and _spins.has("amplitude"),
		"has_performance_controls": _spins.has("particle_count") and _spins.has("estimated_cost"),
		"has_player_reactive": _player_reactive_option != null,
		"has_layer_type_description": _description_label != null and not _description_label.text.is_empty(),
		"has_starting_point_selector": _preset_option != null,
		"starting_point_visible": is_instance_valid(_preset_row) and _preset_row.visible,
		"visible_numeric_controls": _visible_numeric_controls(),
		"mode": _mode,
		"forbidden_code_fields": false,
		"base_layer_types": _option_metadata_values(_type_option),
		"starting_point_types": _preset_builtin_types(),
	}


func create_layer_for_test(layer_type: String) -> Dictionary:
	_ensure_ready_controls()
	_select_option_text(_type_option, layer_type)
	_apply_defaults_to_controls(layer_type)
	_sync_type_specific_controls(layer_type)
	return _build_layer()


func open_add_layer(templates: Array) -> void:
	_ensure_ready_controls()
	_mode = "add_layer"
	title = "Add EMS Layer"
	ok_button_text = "Add Layer"
	_set_custom_templates(templates)
	_rebuild_preset_options()
	if is_instance_valid(_preset_option):
		_preset_option.select(0)
	if is_instance_valid(_preset_row):
		_preset_row.visible = true
	_apply_layer_to_controls(_default_layer_for_type("floating_shapes", "New Floating Shapes"))
	popup_centered(Vector2i(760, 680))


func open_create_type(templates: Array) -> void:
	_ensure_ready_controls()
	_mode = "create_type"
	title = "Create Layer Type"
	ok_button_text = "Save Type"
	_set_custom_templates(templates)
	_rebuild_preset_options()
	if is_instance_valid(_preset_row):
		_preset_row.visible = false
	_apply_layer_to_controls(_default_layer_for_type("floating_shapes", "Custom Layer Type"))
	popup_centered(Vector2i(760, 680))


func load_layer_for_test(layer: Dictionary) -> void:
	_ensure_ready_controls()
	_apply_layer_to_controls(layer)


func _build_ui() -> void:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(720, 620)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	scroll.add_child(root)
	_name_edit = LineEdit.new()
	_name_edit.text = "Custom Layer"
	root.add_child(_labeled("Layer Name", _name_edit))
	_preset_option = OptionButton.new()
	_preset_option.item_selected.connect(_on_preset_selected)
	_preset_row = _labeled("Starting Point", _preset_option)
	root.add_child(_preset_row)
	_type_option = _option(_visible_layer_types())
	_type_option.tooltip_text = _layer_type_description(_selected_option_value(_type_option))
	_type_option.item_selected.connect(_on_type_selected)
	root.add_child(_labeled("Base Renderer", _type_option))
	_description_label = Label.new()
	_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description_label.text = _layer_type_description(_selected_option_value(_type_option))
	root.add_child(_description_label)
	_shape_option = _option(["circle", "square", "diamond", "line"])
	root.add_child(_labeled("Shape", _shape_option))
	_blend_option = _option(["normal", "add", "screen", "multiply"])
	root.add_child(_labeled("Blend Mode", _blend_option))
	_color_picker = ColorPickerButton.new()
	_color_picker.color = Color(0.33, 0.87, 1.0, 1.0)
	root.add_child(_labeled("Primary Color", _color_picker))
	var palette_row := HBoxContainer.new()
	palette_row.add_theme_constant_override("separation", 8)
	_palette_a = ColorPickerButton.new()
	_palette_a.color = Color(1.0, 0.30, 0.88, 1.0)
	_palette_b = ColorPickerButton.new()
	_palette_b.color = Color(1.0, 0.90, 0.34, 1.0)
	palette_row.add_child(_palette_a)
	palette_row.add_child(_palette_b)
	root.add_child(_labeled("Palette Colors", palette_row))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	for spec in _numeric_specs():
		var key := str(spec.get("key", ""))
		var label := Label.new()
		label.text = str(spec.get("label", key))
		grid.add_child(label)
		var spin := SpinBox.new()
		spin.min_value = float(spec.get("min", 0.0))
		spin.max_value = float(spec.get("max", 1.0))
		spin.step = float(spec.get("step", 0.01))
		spin.value = float(spec.get("value", 0.0))
		spin.custom_minimum_size.x = 150
		grid.add_child(spin)
		_spins[key] = spin
		_spin_rows[key] = [label, spin]
	root.add_child(grid)
	_reactive_toggle = CheckBox.new()
	_reactive_toggle.text = "Audio Reactive"
	_reactive_toggle.button_pressed = true
	root.add_child(_reactive_toggle)
	_player_reactive_option = _option(["Off", "Successful Hits", "Misses"])
	root.add_child(_labeled("Player Reactive", _player_reactive_option))
	_low_motion_toggle = CheckBox.new()
	_low_motion_toggle.text = "Low Motion Safe"
	_low_motion_toggle.button_pressed = false
	root.add_child(_low_motion_toggle)
	add_child(scroll)
	_rebuild_preset_options()
	_sync_type_specific_controls(_selected_option_value(_type_option))


func _numeric_specs() -> Array[Dictionary]:
	return [
		{"key": "opacity", "label": "Opacity", "min": 0.0, "max": 1.0, "step": 0.01, "value": 0.75},
		{"key": "intensity", "label": "Intensity", "min": 0.0, "max": 2.0, "step": 0.01, "value": 1.0},
		{"key": "particle_count", "label": "Particles", "min": 0.0, "max": 500.0, "step": 1.0, "value": 64.0},
		{"key": "speed", "label": "Speed", "min": -4.0, "max": 4.0, "step": 0.01, "value": 0.25},
		{"key": "direction", "label": "Direction", "min": -360.0, "max": 360.0, "step": 1.0, "value": 90.0},
		{"key": "rotation", "label": "Rotation", "min": -360.0, "max": 360.0, "step": 1.0, "value": 0.0},
		{"key": "frequency", "label": "Frequency", "min": 0.0, "max": 20.0, "step": 0.05, "value": 1.0},
		{"key": "amplitude", "label": "Amplitude", "min": 0.0, "max": 2.0, "step": 0.01, "value": 0.25},
		{"key": "distortion", "label": "Distortion", "min": 0.0, "max": 0.5, "step": 0.01, "value": 0.0},
		{"key": "bloom", "label": "Bloom", "min": 0.0, "max": 1.0, "step": 0.01, "value": 0.0},
		{"key": "shake", "label": "Shake", "min": 0.0, "max": 0.35, "step": 0.01, "value": 0.0},
		{"key": "segments", "label": "Segments", "min": 1.0, "max": 96.0, "step": 1.0, "value": 18.0},
		{"key": "points", "label": "Points", "min": 3.0, "max": 64.0, "step": 1.0, "value": 6.0},
		{"key": "spacing", "label": "Spacing", "min": 4.0, "max": 240.0, "step": 1.0, "value": 42.0},
		{"key": "thickness", "label": "Thickness", "min": 0.5, "max": 32.0, "step": 0.5, "value": 2.0},
		{"key": "scale", "label": "Scale", "min": 0.05, "max": 8.0, "step": 0.01, "value": 1.0},
		{"key": "position_x", "label": "Position X", "min": 0.0, "max": 1.0, "step": 0.01, "value": 0.5},
		{"key": "position_y", "label": "Position Y", "min": 0.0, "max": 1.0, "step": 0.01, "value": 0.5},
		{"key": "size_x", "label": "Size X", "min": 0.01, "max": 2.0, "step": 0.01, "value": 1.0},
		{"key": "size_y", "label": "Size Y", "min": 0.01, "max": 2.0, "step": 0.01, "value": 1.0},
		{"key": "combo_influence", "label": "Combo Influence", "min": 0.0, "max": 1.0, "step": 0.01, "value": 0.35},
		{"key": "beat_influence", "label": "Beat Influence", "min": 0.0, "max": 1.0, "step": 0.01, "value": 0.55},
		{"key": "miss_influence", "label": "Miss Influence", "min": 0.0, "max": 1.0, "step": 0.01, "value": 0.20},
		{"key": "estimated_cost", "label": "Estimated Cost", "min": 0.0, "max": 1.0, "step": 0.01, "value": 0.35},
	]


func _commit_layer() -> void:
	var layer := _build_layer()
	if _mode == "create_type":
		template_saved.emit({"name": str(layer.get("name", "Custom Layer")), "layer": layer.duplicate(true)}, layer)
	else:
		layer_created.emit(layer)


func _build_layer() -> Dictionary:
	_ensure_ready_controls()
	var layer_type := _selected_option_value(_type_option)
	var layer_name := _name_edit.text.strip_edges()
	if layer_name.is_empty():
		layer_name = "Custom %s" % layer_type.capitalize()
	var layer := {
		"id": EMSValidator.sanitize_pack_id("%s_%d" % [layer_name, Time.get_ticks_msec()]),
		"type": layer_type,
		"name": layer_name,
		"enabled": true,
		"opacity": _spin_value("opacity"),
		"color": "#%s" % _color_picker.color.to_html(true),
		"colors": [
			"#%s" % _color_picker.color.to_html(true),
			"#%s" % _palette_a.color.to_html(true),
			"#%s" % _palette_b.color.to_html(true),
		],
		"position": [_spin_value("position_x"), _spin_value("position_y")],
		"size": [_spin_value("size_x"), _spin_value("size_y")],
		"speed": _spin_value("speed"),
		"direction": _spin_value("direction"),
		"intensity": _spin_value("intensity"),
		"particle_count": int(_spin_value("particle_count")),
		"shape": _selected_option_value(_shape_option),
		"blend_mode": _selected_option_value(_blend_option),
		"scale": _spin_value("scale"),
		"rotation": _spin_value("rotation"),
		"frequency": _spin_value("frequency"),
		"thickness": _spin_value("thickness"),
		"spacing": _spin_value("spacing"),
		"points": int(_spin_value("points")),
		"segments": int(_spin_value("segments")),
		"amplitude": _spin_value("amplitude"),
		"distortion": _spin_value("distortion"),
		"bloom": _spin_value("bloom"),
		"shake": _spin_value("shake"),
		"seed": Time.get_ticks_msec() % 999999999,
		"reactive": _reactive_toggle.button_pressed,
		"player_reactive": _selected_player_reactive_mode(),
		"low_motion": _low_motion_toggle.button_pressed,
	}
	if layer_type not in ["particles", "starfield", "floating_shapes"]:
		layer["particle_count"] = 0
	if layer_type in ["image", "video"]:
		layer["media_kind"] = layer_type
		layer["asset_path"] = ""
		layer["source_path"] = ""
		layer["fit_mode"] = "cover"
		layer["loop"] = true
	if layer_type.begins_with("signature_"):
		layer["signature_effect"] = layer_type.trim_prefix("signature_")
	return layer


func _default_layer_for_type(layer_type: String, layer_name: String = "") -> Dictionary:
	var name := layer_name.strip_edges()
	if name.is_empty():
		name = _layer_type_label(layer_type)
	var layer := {
		"id": EMSValidator.sanitize_pack_id(name),
		"type": layer_type,
		"name": name,
		"enabled": true,
		"opacity": 0.75,
		"color": "#55DFFFFF",
		"colors": ["#55DFFFFF", "#FF4DE1FF", "#FFE66DFF"],
		"position": [0.5, 0.5],
		"size": [1.0, 1.0],
		"speed": 0.25,
		"direction": 90.0,
		"intensity": 1.0,
		"particle_count": 64,
		"shape": "circle",
		"blend_mode": "screen",
		"scale": 1.0,
		"rotation": 0.0,
		"frequency": 1.0,
		"thickness": 2.0,
		"spacing": 42.0,
		"points": 6,
		"segments": 18,
		"amplitude": 0.25,
		"distortion": 0.0,
		"bloom": 0.0,
		"shake": 0.0,
		"seed": Time.get_ticks_msec() % 999999999,
		"reactive": true,
		"player_reactive": "off",
		"low_motion": false,
	}
	var defaults: Dictionary = LAYER_TYPE_DEFAULTS.get(layer_type, {}) as Dictionary
	for key_variant in defaults.keys():
		layer[str(key_variant)] = defaults[key_variant]
	if layer_type.begins_with("signature_"):
		layer["particle_count"] = 0
		layer["segments"] = 24
		layer["points"] = 10
		layer["speed"] = 0.42
		layer["frequency"] = 1.1
		layer["amplitude"] = 0.50
		layer["thickness"] = 2.2
		layer["signature_effect"] = layer_type.trim_prefix("signature_")
	if layer_type in ["image", "video"]:
		layer["media_kind"] = layer_type
		layer["asset_path"] = ""
		layer["source_path"] = ""
		layer["fit_mode"] = "cover"
		layer["loop"] = true
	if layer_type not in ["particles", "starfield", "floating_shapes"]:
		layer["particle_count"] = 0
	return layer


func _apply_layer_to_controls(layer: Dictionary) -> void:
	_ensure_ready_controls()
	_updating_preset = true
	var layer_type := str(layer.get("type", "floating_shapes"))
	if layer_type not in EMSValidator.ALLOWED_LAYER_TYPES:
		layer_type = "floating_shapes"
	_name_edit.text = str(layer.get("name", _layer_type_label(layer_type)))
	_select_option_text(_type_option, layer_type)
	if is_instance_valid(_description_label):
		_description_label.text = _layer_type_description(layer_type)
	if is_instance_valid(_type_option):
		_type_option.tooltip_text = _layer_type_description(layer_type)
	var primary := _color_from_hex(str(layer.get("color", "#55DFFFFF")), Color(0.33, 0.87, 1.0, 1.0))
	_color_picker.color = primary
	var colors: Array = layer.get("colors", []) as Array
	_palette_a.color = _color_from_hex(str(colors[1] if colors.size() > 1 else "#FF4DE1FF"), Color(1.0, 0.30, 0.88, 1.0))
	_palette_b.color = _color_from_hex(str(colors[2] if colors.size() > 2 else "#FFE66DFF"), Color(1.0, 0.90, 0.34, 1.0))
	var position := _variant_vec2(layer.get("position", [0.5, 0.5]), Vector2(0.5, 0.5))
	var layer_size := _variant_vec2(layer.get("size", [1.0, 1.0]), Vector2(1.0, 1.0))
	var numeric_values := {
		"opacity": float(layer.get("opacity", 0.75)),
		"intensity": float(layer.get("intensity", 1.0)),
		"particle_count": float(layer.get("particle_count", 0)),
		"speed": float(layer.get("speed", 0.25)),
		"direction": float(layer.get("direction", 90.0)),
		"rotation": float(layer.get("rotation", 0.0)),
		"frequency": float(layer.get("frequency", 1.0)),
		"amplitude": float(layer.get("amplitude", 0.25)),
		"distortion": float(layer.get("distortion", 0.0)),
		"bloom": float(layer.get("bloom", 0.0)),
		"shake": float(layer.get("shake", 0.0)),
		"segments": float(layer.get("segments", 18)),
		"points": float(layer.get("points", 6)),
		"spacing": float(layer.get("spacing", 42.0)),
		"thickness": float(layer.get("thickness", 2.0)),
		"scale": float(layer.get("scale", 1.0)),
		"position_x": position.x,
		"position_y": position.y,
		"size_x": layer_size.x,
		"size_y": layer_size.y,
		"combo_influence": float(layer.get("combo_influence", 0.35)),
		"beat_influence": float(layer.get("beat_influence", 0.55)),
		"miss_influence": float(layer.get("miss_influence", 0.20)),
		"estimated_cost": float(layer.get("estimated_cost", 0.35)),
	}
	for key_variant in numeric_values.keys():
		_set_spin_value(str(key_variant), float(numeric_values[key_variant]))
	_select_option_text(_shape_option, str(layer.get("shape", "circle")))
	_select_option_text(_blend_option, str(layer.get("blend_mode", "screen")))
	_reactive_toggle.button_pressed = bool(layer.get("reactive", true))
	_select_player_reactive_mode(str(layer.get("player_reactive", "off")))
	_low_motion_toggle.button_pressed = bool(layer.get("low_motion", false))
	_sync_type_specific_controls(layer_type)
	_updating_preset = false


func _spin_value(key: String) -> float:
	var spin: SpinBox = _spins.get(key, null)
	return float(spin.value) if spin != null else 0.0


func _labeled(text: String, control: Control) -> VBoxContainer:
	var box := VBoxContainer.new()
	var label := Label.new()
	label.text = text
	box.add_child(label)
	box.add_child(control)
	return box


func _option(values: Array) -> OptionButton:
	var option := OptionButton.new()
	for value in values:
		var raw := str(value)
		option.add_item(_layer_type_label(raw))
		option.set_item_metadata(option.get_item_count() - 1, raw)
	return option


func _rebuild_preset_options() -> void:
	if not is_instance_valid(_preset_option):
		return
	_preset_option.clear()
	for layer_type in EMSValidator.ALLOWED_LAYER_TYPES:
		if not EMSLoadoutCatalog.is_layer_type_content_available(layer_type):
			continue
		_preset_option.add_item("New %s" % _layer_type_label(layer_type))
		_preset_option.set_item_metadata(_preset_option.get_item_count() - 1, {"kind": "builtin", "type": layer_type})
	for template in _custom_templates:
		if template is not Dictionary:
			continue
		var template_dict := template as Dictionary
		var template_id := str(template_dict.get("template_id", ""))
		var template_name := str(template_dict.get("name", "Custom Layer Type"))
		var base_type := str(template_dict.get("base_type", ""))
		if template_id.is_empty() or base_type.is_empty():
			continue
		_preset_option.add_item("Custom: %s" % template_name)
		_preset_option.set_item_metadata(_preset_option.get_item_count() - 1, {"kind": "template", "template_id": template_id})


func _set_custom_templates(templates: Array) -> void:
	_custom_templates.clear()
	for template in templates:
		if template is Dictionary:
			_custom_templates.append((template as Dictionary).duplicate(true))


func _select_option_text(option: OptionButton, value: String) -> void:
	for i in range(option.get_item_count()):
		if option.get_item_text(i) == value or str(option.get_item_metadata(i)) == value:
			option.select(i)
			return


func _selected_option_value(option: OptionButton) -> String:
	if option == null or option.selected < 0:
		return ""
	var metadata: Variant = option.get_item_metadata(option.selected)
	if metadata != null:
		return str(metadata)
	return option.get_item_text(option.selected)


func _layer_type_label(type_name: String) -> String:
	return str(LAYER_TYPE_LABELS.get(type_name, type_name))


func _layer_type_description(type_name: String) -> String:
	return str(LAYER_TYPE_DESCRIPTIONS.get(type_name, "Custom EMS layer renderer."))


func _visible_layer_types() -> Array[String]:
	var visible: Array[String] = []
	for layer_type in EMSValidator.ALLOWED_LAYER_TYPES:
		if EMSLoadoutCatalog.is_layer_type_content_available(layer_type):
			visible.append(layer_type)
	return visible


func _option_metadata_values(option: OptionButton) -> Array[String]:
	var values: Array[String] = []
	if not is_instance_valid(option):
		return values
	for i in range(option.get_item_count()):
		values.append(str(option.get_item_metadata(i)))
	return values


func _preset_builtin_types() -> Array[String]:
	var values: Array[String] = []
	if not is_instance_valid(_preset_option):
		return values
	for i in range(_preset_option.get_item_count()):
		var metadata: Variant = _preset_option.get_item_metadata(i)
		if metadata is Dictionary and str((metadata as Dictionary).get("kind", "")) == "builtin":
			values.append(str((metadata as Dictionary).get("type", "")))
	return values


func _on_type_selected(_index: int) -> void:
	if _updating_preset:
		return
	var layer_type := _selected_option_value(_type_option)
	if is_instance_valid(_description_label):
		_description_label.text = _layer_type_description(layer_type)
	if is_instance_valid(_type_option):
		_type_option.tooltip_text = _layer_type_description(layer_type)
	_apply_defaults_to_controls(layer_type)
	_sync_type_specific_controls(layer_type)


func _apply_defaults_to_controls(layer_type: String) -> void:
	if _applying_type_defaults:
		return
	_applying_type_defaults = true
	var defaults: Dictionary = LAYER_TYPE_DEFAULTS.get(layer_type, {}) as Dictionary
	if layer_type.begins_with("signature_"):
		defaults = {"particle_count": 0.0, "speed": 0.42, "frequency": 1.1, "amplitude": 0.50, "points": 10.0, "segments": 24.0, "thickness": 2.2, "scale": 1.0, "estimated_cost": 0.32}
	for key_variant in defaults.keys():
		_set_spin_value(str(key_variant), float(defaults[key_variant]))
	if layer_type not in ["particles", "starfield", "floating_shapes"]:
		_set_spin_value("particle_count", 0.0)
	_applying_type_defaults = false
	_sync_type_specific_controls(layer_type)


func _set_spin_value(key: String, value: float) -> void:
	var spin: SpinBox = _spins.get(key, null)
	if spin == null:
		return
	spin.value = clampf(value, spin.min_value, spin.max_value)


func _selected_player_reactive_mode() -> String:
	if _player_reactive_option == null:
		return "off"
	match _player_reactive_option.selected:
		1:
			return "hit"
		2:
			return "miss"
		_:
			return "off"


func _select_player_reactive_mode(mode: String) -> void:
	if not is_instance_valid(_player_reactive_option):
		return
	match mode.strip_edges().to_lower():
		"hit":
			_player_reactive_option.select(1)
		"miss":
			_player_reactive_option.select(2)
		_:
			_player_reactive_option.select(0)


func _on_preset_selected(index: int) -> void:
	if _updating_preset or not is_instance_valid(_preset_option):
		return
	var metadata: Variant = _preset_option.get_item_metadata(index)
	if metadata is not Dictionary:
		return
	var data := metadata as Dictionary
	if str(data.get("kind", "")) == "template":
		var template := _template_by_id(str(data.get("template_id", "")))
		var layer_value: Variant = template.get("layer", {})
		if layer_value is Dictionary:
			_apply_layer_to_controls((layer_value as Dictionary).duplicate(true))
		return
	var layer_type := str(data.get("type", "floating_shapes"))
	_apply_layer_to_controls(_default_layer_for_type(layer_type, "New %s" % _layer_type_label(layer_type)))


func _template_by_id(template_id: String) -> Dictionary:
	for template in _custom_templates:
		if template is Dictionary and str((template as Dictionary).get("template_id", "")) == template_id:
			return (template as Dictionary).duplicate(true)
	return {}


func _sync_type_specific_controls(layer_type: String) -> void:
	var visible_keys: Array = TYPE_CONTROL_KEYS.get(layer_type, ["opacity", "intensity", "position_x", "position_y", "size_x", "size_y", "scale", "rotation", "estimated_cost"]) as Array
	if layer_type.begins_with("signature_"):
		visible_keys = ["opacity", "intensity", "speed", "frequency", "amplitude", "points", "segments", "thickness", "scale", "rotation", "position_x", "position_y", "size_x", "size_y", "estimated_cost"]
	for key_variant in _spin_rows.keys():
		var key := str(key_variant)
		var visible := visible_keys.has(key)
		var row: Array = _spin_rows[key] as Array
		for control in row:
			if control is Control:
				(control as Control).visible = visible
	if is_instance_valid(_shape_option):
		_shape_option.get_parent().visible = layer_type == "floating_shapes"


func _visible_numeric_controls() -> Array[String]:
	var keys: Array[String] = []
	for key_variant in _spin_rows.keys():
		var row: Array = _spin_rows[key_variant] as Array
		if row.size() > 0 and row[0] is Control and (row[0] as Control).visible:
			keys.append(str(key_variant))
	return keys


func _variant_vec2(value: Variant, fallback: Vector2) -> Vector2:
	if value is Array and (value as Array).size() >= 2:
		return Vector2(float((value as Array)[0]), float((value as Array)[1]))
	if value is Dictionary:
		var dict := value as Dictionary
		return Vector2(float(dict.get("x", fallback.x)), float(dict.get("y", fallback.y)))
	return fallback


func _color_from_hex(value: String, fallback: Color) -> Color:
	var hex := value.strip_edges()
	if hex.begins_with("#"):
		hex = hex.substr(1)
	if hex.length() == 6:
		hex += "FF"
	if hex.length() != 8:
		return fallback
	return Color(
		float(hex.substr(0, 2).hex_to_int()) / 255.0,
		float(hex.substr(2, 2).hex_to_int()) / 255.0,
		float(hex.substr(4, 2).hex_to_int()) / 255.0,
		float(hex.substr(6, 2).hex_to_int()) / 255.0
	)


func _ensure_ready_controls() -> void:
	if _type_option == null:
		_build_ui()
