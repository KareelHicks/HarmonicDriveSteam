extends RefCounted
class_name HDTheme

enum DeviceClass {
	COMPACT_PHONE,
	REGULAR_PHONE,
	LARGE_PHONE,
	TABLET,
	DESKTOP,
}

const BG := Color(0.03, 0.04, 0.12, 0.38)
const PANEL_FILL := Color(0.07, 0.10, 0.23, 0.70)
const CARD_FILL := Color(0.08, 0.11, 0.26, 0.52)
const CARD_STROKE := Color(0.70, 0.90, 1.00, 0.20)
const CYAN := Color(0.15, 0.82, 1.0, 1.0)
const PURPLE := Color(0.55, 0.35, 1.0, 1.0)
const SECONDARY := Color(1, 1, 1, 0.84)
const TERTIARY := Color(1, 1, 1, 0.68)
const SHADOW := Color(0, 0, 0, 0.24)
const MISS := Color(1.0, 0.3, 0.3, 1.0)
const PERFECT := Color(1.0, 1.0, 0.3, 1.0)
const GREAT := Color(0.3, 0.9, 1.0, 1.0)
const GOOD := Color(0.3, 1.0, 0.5, 1.0)
const DEFAULT_THEME_ID := "theme_default"
const DIALOG_THEME_META := "hd_dialog_theme_visibility_hooked"

const LANE_COLORS := [
	Color(0.10, 0.88, 1.00, 1.0),
	Color(0.90, 0.18, 1.00, 1.0),
	Color(1.00, 0.90, 0.10, 1.0),
	Color(0.10, 1.00, 0.55, 1.0),
	Color(1.00, 0.42, 0.12, 1.0),
]


static func _make_palette(background: Color, background_top: Color, background_bottom: Color, gutter: Color, ambient: Color, lane_colors: Array, rail: Color, side_fx: Array) -> Dictionary:
	return {
		"background": background,
		"background_top": background_top,
		"background_bottom": background_bottom,
		"gutter": gutter,
		"ambient": ambient,
		"grid": rail * Color(1, 1, 1, 0.14),
		"lane_colors": lane_colors,
		"rail": rail,
		"side_fx": side_fx,
	}


static func theme_palette(theme_id: String = DEFAULT_THEME_ID) -> Dictionary:
	match theme_id:
		"theme_neon":
			return _make_palette(
				Color(0.03, 0.03, 0.11, 1.0),
				Color(0.10, 0.05, 0.22, 1.0),
				Color(0.01, 0.02, 0.07, 1.0),
				Color(0.05, 0.04, 0.12, 1.0),
				Color(0.22, 0.78, 1.0, 0.18),
				[
					Color(0.12, 0.95, 1.0, 1.0),
					Color(0.70, 0.25, 1.0, 1.0),
					Color(1.0, 0.20, 0.92, 1.0),
					Color(0.38, 1.0, 0.82, 1.0),
					Color(1.0, 0.60, 0.16, 1.0),
				],
				CYAN,
				[
					Color(0.12, 0.95, 1.0, 0.85),
					Color(0.70, 0.25, 1.0, 0.85),
					Color(1.0, 0.20, 0.92, 0.85),
				]
			)
		"theme_retro":
			return _make_palette(
				Color(0.02, 0.06, 0.03, 1.0),
				Color(0.07, 0.14, 0.07, 1.0),
				Color(0.01, 0.03, 0.02, 1.0),
				Color(0.03, 0.08, 0.04, 1.0),
				Color(0.32, 0.92, 0.45, 0.16),
				[
					Color(0.45, 0.95, 0.45, 1.0),
					Color(0.26, 0.78, 0.26, 1.0),
					Color(0.72, 1.0, 0.58, 1.0),
					Color(0.12, 0.58, 0.12, 1.0),
					Color(0.85, 1.0, 0.70, 1.0),
				],
				Color(0.58, 1.0, 0.64, 1.0),
				[
					Color(0.45, 0.95, 0.45, 0.80),
					Color(0.72, 1.0, 0.58, 0.76),
					Color(0.26, 0.78, 0.26, 0.72),
				]
			)
		"theme_sunset":
			return _make_palette(
				Color(0.10, 0.03, 0.10, 1.0),
				Color(0.24, 0.08, 0.16, 1.0),
				Color(0.06, 0.02, 0.08, 1.0),
				Color(0.12, 0.05, 0.11, 1.0),
				Color(1.0, 0.54, 0.32, 0.16),
				[
					Color(1.0, 0.58, 0.22, 1.0),
					Color(1.0, 0.40, 0.56, 1.0),
					Color(1.0, 0.78, 0.26, 1.0),
					Color(0.98, 0.52, 0.72, 1.0),
					Color(1.0, 0.30, 0.34, 1.0),
				],
				Color(1.0, 0.68, 0.42, 1.0),
				[
					Color(1.0, 0.58, 0.22, 0.84),
					Color(1.0, 0.40, 0.56, 0.80),
					Color(1.0, 0.78, 0.26, 0.76),
				]
			)
		"theme_mono":
			return _make_palette(
				Color(0.05, 0.05, 0.06, 1.0),
				Color(0.14, 0.14, 0.16, 1.0),
				Color(0.02, 0.02, 0.03, 1.0),
				Color(0.07, 0.07, 0.08, 1.0),
				Color(1.0, 1.0, 1.0, 0.10),
				[
					Color(0.92, 0.92, 0.92, 1.0),
					Color(0.78, 0.78, 0.78, 1.0),
					Color(0.64, 0.64, 0.64, 1.0),
					Color(0.50, 0.50, 0.50, 1.0),
					Color(0.36, 0.36, 0.36, 1.0),
				],
				Color(0.94, 0.94, 0.94, 1.0),
				[
					Color(1.0, 1.0, 1.0, 0.68),
					Color(0.72, 0.72, 0.72, 0.62),
					Color(0.44, 0.44, 0.44, 0.56),
				]
			)
		"theme_synthwave":
			return _make_palette(
				Color(0.04, 0.00, 0.09, 1.0),
				Color(0.14, 0.02, 0.20, 1.0),
				Color(0.01, 0.00, 0.05, 1.0),
				Color(0.08, 0.02, 0.12, 1.0),
				Color(0.85, 0.24, 1.0, 0.14),
				[
					Color(0.21, 0.93, 1.0, 1.0),
					Color(0.83, 0.22, 1.0, 1.0),
					Color(1.0, 0.86, 0.24, 1.0),
					Color(0.15, 1.0, 0.68, 1.0),
					Color(1.0, 0.50, 0.25, 1.0),
				],
				Color(0.15, 0.82, 1.0, 1.0),
				[
					Color(0.21, 0.93, 1.0, 0.86),
					Color(0.83, 0.22, 1.0, 0.82),
					Color(1.0, 0.50, 0.25, 0.78),
				]
			)
		"theme_aurora":
			return _make_palette(
				Color(0.02, 0.06, 0.10, 1.0),
				Color(0.06, 0.17, 0.20, 1.0),
				Color(0.01, 0.03, 0.07, 1.0),
				Color(0.03, 0.08, 0.11, 1.0),
				Color(0.40, 1.0, 0.86, 0.16),
				[
					Color(0.42, 0.97, 1.0, 1.0),
					Color(0.62, 0.60, 1.0, 1.0),
					Color(0.83, 1.0, 0.52, 1.0),
					Color(0.35, 1.0, 0.72, 1.0),
					Color(0.97, 0.74, 0.42, 1.0),
				],
				Color(0.56, 0.98, 1.0, 1.0),
				[
					Color(0.42, 0.97, 1.0, 0.78),
					Color(0.62, 0.60, 1.0, 0.72),
					Color(0.35, 1.0, 0.72, 0.76),
				]
			)
		"theme_ember":
			return _make_palette(
				Color(0.10, 0.03, 0.02, 1.0),
				Color(0.22, 0.08, 0.03, 1.0),
				Color(0.04, 0.01, 0.01, 1.0),
				Color(0.11, 0.04, 0.03, 1.0),
				Color(1.0, 0.46, 0.18, 0.16),
				[
					Color(1.0, 0.54, 0.22, 1.0),
					Color(1.0, 0.26, 0.18, 1.0),
					Color(1.0, 0.82, 0.30, 1.0),
					Color(0.98, 0.46, 0.16, 1.0),
					Color(1.0, 0.72, 0.36, 1.0),
				],
				Color(1.0, 0.62, 0.26, 1.0),
				[
					Color(1.0, 0.54, 0.22, 0.82),
					Color(1.0, 0.26, 0.18, 0.78),
					Color(1.0, 0.82, 0.30, 0.76),
				]
			)
		"theme_oceanic":
			return _make_palette(
				Color(0.01, 0.05, 0.10, 1.0),
				Color(0.04, 0.14, 0.22, 1.0),
				Color(0.00, 0.02, 0.06, 1.0),
				Color(0.02, 0.07, 0.12, 1.0),
				Color(0.16, 0.72, 1.0, 0.16),
				[
					Color(0.18, 0.86, 1.0, 1.0),
					Color(0.14, 0.56, 1.0, 1.0),
					Color(0.40, 0.96, 0.90, 1.0),
					Color(0.24, 1.0, 0.74, 1.0),
					Color(0.68, 0.92, 1.0, 1.0),
				],
				Color(0.40, 0.94, 1.0, 1.0),
				[
					Color(0.18, 0.86, 1.0, 0.82),
					Color(0.14, 0.56, 1.0, 0.72),
					Color(0.40, 0.96, 0.90, 0.76),
				]
			)
		"theme_void":
			return _make_palette(
				Color(0.02, 0.01, 0.07, 1.0),
				Color(0.10, 0.03, 0.14, 1.0),
				Color(0.01, 0.00, 0.03, 1.0),
				Color(0.05, 0.02, 0.09, 1.0),
				Color(0.86, 0.12, 0.42, 0.14),
				[
					Color(0.40, 0.78, 1.0, 1.0),
					Color(0.78, 0.28, 1.0, 1.0),
					Color(0.95, 0.16, 0.54, 1.0),
					Color(0.48, 1.0, 0.82, 1.0),
					Color(1.0, 0.54, 0.36, 1.0),
				],
				Color(0.74, 0.28, 1.0, 1.0),
				[
					Color(0.74, 0.28, 1.0, 0.82),
					Color(0.95, 0.16, 0.54, 0.78),
					Color(0.40, 0.78, 1.0, 0.72),
				]
			)
		"theme_prism":
			return _make_palette(
				Color(0.04, 0.05, 0.08, 1.0),
				Color(0.13, 0.16, 0.24, 1.0),
				Color(0.02, 0.03, 0.05, 1.0),
				Color(0.07, 0.08, 0.12, 1.0),
				Color(1.0, 1.0, 1.0, 0.12),
				[
					Color(0.42, 0.92, 1.0, 1.0),
					Color(0.92, 0.38, 1.0, 1.0),
					Color(1.0, 0.92, 0.36, 1.0),
					Color(0.36, 1.0, 0.78, 1.0),
					Color(1.0, 0.52, 0.30, 1.0),
				],
				Color(0.82, 0.92, 1.0, 1.0),
				[
					Color(0.42, 0.92, 1.0, 0.74),
					Color(0.92, 0.38, 1.0, 0.70),
					Color(1.0, 0.92, 0.36, 0.66),
				]
			)
		"theme_spiral":
			return _make_palette(
				Color(0.015, 0.014, 0.018, 1.0),
				Color(0.08, 0.08, 0.10, 1.0),
				Color(0.00, 0.00, 0.01, 1.0),
				Color(0.02, 0.02, 0.025, 1.0),
				Color(1.0, 1.0, 1.0, 0.13),
				[
					Color(0.95, 0.95, 0.95, 1.0),
					Color(0.14, 0.14, 0.14, 1.0),
					Color(0.82, 0.82, 0.82, 1.0),
					Color(0.04, 0.04, 0.04, 1.0),
					Color(0.68, 0.68, 0.68, 1.0),
				],
				Color(0.94, 0.94, 0.94, 1.0),
				[
					Color(1.0, 1.0, 1.0, 0.70),
					Color(0.34, 0.34, 0.34, 0.62),
					Color(0.82, 0.82, 0.82, 0.58),
				]
			)
		_:
			return _make_palette(
				BG,
				Color(0.08, 0.10, 0.18, 1.0),
				Color(0.02, 0.03, 0.09, 1.0),
				Color(0.04, 0.05, 0.12, 1.0),
				Color(0.16, 0.82, 1.0, 0.14),
				LANE_COLORS,
				CYAN,
				[
					Color(0.15, 0.82, 1.0, 0.72),
					Color(0.55, 0.35, 1.0, 0.66),
					Color(1.0, 0.42, 0.12, 0.60),
				]
				)


static func lane_color(palette: Dictionary, lane: int) -> Color:
	var colors: Array = palette.get("lane_colors", LANE_COLORS) as Array
	if colors.is_empty():
		colors = LANE_COLORS
	return colors[wrapi(lane, 0, colors.size())] as Color


static func device_class_for(size: Vector2) -> int:
	var width := minf(size.x, size.y)
	if OS.has_feature("macos") or OS.has_feature("windows") or OS.has_feature("linuxbsd"):
		return DeviceClass.DESKTOP
	if width >= 900.0:
		return DeviceClass.TABLET
	if width <= 360.0:
		return DeviceClass.COMPACT_PHONE
	if width <= 430.0:
		return DeviceClass.REGULAR_PHONE
	return DeviceClass.LARGE_PHONE


static func text_size(role: String, size: Vector2) -> int:
	var cls := device_class_for(size)
	var base_size := 16
	match cls:
		DeviceClass.COMPACT_PHONE:
			match role:
				"hero_title": base_size = 38
				"screen_title": base_size = 29
				"section_title": base_size = 21
				"button_primary": base_size = 21
				"button_secondary": base_size = 19
				"body", "status": base_size = 19
				"supporting": base_size = 17
				"caption", "footer": base_size = 16
		DeviceClass.REGULAR_PHONE:
			match role:
				"hero_title": base_size = 42
				"screen_title": base_size = 32
				"section_title": base_size = 23
				"button_primary": base_size = 23
				"button_secondary": base_size = 21
				"body", "status": base_size = 20
				"supporting": base_size = 18
				"caption", "footer": base_size = 16
		DeviceClass.LARGE_PHONE:
			match role:
				"hero_title": base_size = 48
				"screen_title": base_size = 36
				"section_title": base_size = 25
				"button_primary": base_size = 25
				"button_secondary": base_size = 22
				"body", "status": base_size = 22
				"supporting": base_size = 19
				"caption", "footer": base_size = 17
		_:
			match role:
				"hero_title": base_size = 50
				"screen_title": base_size = 38
				"section_title": base_size = 28
				"button_primary": base_size = 24
				"button_secondary": base_size = 22
				"body", "status": base_size = 20
				"supporting": base_size = 18
				"caption", "footer": base_size = 16
	return base_size


static func main_menu_metrics(size: Vector2) -> Dictionary:
	match device_class_for(size):
		DeviceClass.COMPACT_PHONE:
			return {"button_width": minf(size.x - 32.0, 420.0), "button_height": 72.0, "button_gap": 14.0, "header_title_top": 70.0, "title_line_gap": 46.0, "subtitle_gap": 32.0, "divider_gap": 28.0, "footer_bottom": 28.0}
		DeviceClass.REGULAR_PHONE:
			return {"button_width": minf(size.x - 36.0, 480.0), "button_height": 78.0, "button_gap": 16.0, "header_title_top": 78.0, "title_line_gap": 50.0, "subtitle_gap": 34.0, "divider_gap": 30.0, "footer_bottom": 32.0}
		DeviceClass.LARGE_PHONE:
			return {"button_width": minf(size.x - 40.0, 540.0), "button_height": 86.0, "button_gap": 18.0, "header_title_top": 88.0, "title_line_gap": 56.0, "subtitle_gap": 36.0, "divider_gap": 32.0, "footer_bottom": 34.0}
		_:
			return {"button_width": minf(size.x - 120.0, 620.0), "button_height": 76.0, "button_gap": 14.0, "header_title_top": 72.0, "title_line_gap": 40.0, "subtitle_gap": 26.0, "divider_gap": 22.0, "footer_bottom": 24.0}


static func list_metrics(size: Vector2) -> Dictionary:
	match device_class_for(size):
		DeviceClass.COMPACT_PHONE:
			return {"side_pad": 14.0, "top_padding": 164.0, "bottom_padding": 40.0, "row_height": 132.0, "row_spacing": 10.0, "list_bottom_inset": 28.0, "card_width_max": 720.0, "card_inner_padding": 18.0, "trailing_action_width": 132.0, "header_status_width": size.x - 28.0, "compact_phone": true}
		DeviceClass.REGULAR_PHONE:
			return {"side_pad": 16.0, "top_padding": 160.0, "bottom_padding": 44.0, "row_height": 136.0, "row_spacing": 12.0, "list_bottom_inset": 30.0, "card_width_max": 760.0, "card_inner_padding": 20.0, "trailing_action_width": 144.0, "header_status_width": minf(size.x - 32.0, 520.0), "compact_phone": false}
		DeviceClass.LARGE_PHONE:
			return {"side_pad": 18.0, "top_padding": 156.0, "bottom_padding": 46.0, "row_height": 140.0, "row_spacing": 12.0, "list_bottom_inset": 32.0, "card_width_max": 820.0, "card_inner_padding": 22.0, "trailing_action_width": 152.0, "header_status_width": minf(size.x - 36.0, 560.0), "compact_phone": false}
		_:
			return {"side_pad": 28.0, "top_padding": 128.0, "bottom_padding": 44.0, "row_height": 136.0, "row_spacing": 12.0, "list_bottom_inset": 32.0, "card_width_max": 980.0, "card_inner_padding": 22.0, "trailing_action_width": 200.0, "header_status_width": 620.0, "compact_phone": false}


static func overlay_metrics(size: Vector2) -> Dictionary:
	match device_class_for(size):
		DeviceClass.COMPACT_PHONE:
			return {"panel_width": minf(size.x - 20.0, 440.0), "panel_height": minf(size.y - 40.0, 760.0), "compact_phone": true, "button_height": 64.0, "horizontal_inset": 18.0}
		DeviceClass.REGULAR_PHONE, DeviceClass.LARGE_PHONE:
			return {"panel_width": minf(size.x - 24.0, 560.0), "panel_height": minf(size.y - 44.0, 820.0), "compact_phone": false, "button_height": 70.0, "horizontal_inset": 22.0}
		_:
			return {"panel_width": minf(size.x - 120.0, 860.0), "panel_height": minf(size.y - 40.0, 860.0), "compact_phone": false, "button_height": 60.0, "horizontal_inset": 28.0}


static func safe_top(control: Control) -> float:
	return control.get_viewport().get_visible_rect().position.y


static func primary_text() -> Color:
	return Color(1.0, 1.0, 1.0, 0.98)


static func apply_label(label: Label, role: String, tone: Color = Color(1.0, 1.0, 1.0, 0.98), center: bool = false) -> void:
	var viewport_size := Vector2(720.0, 1280.0)
	if label.is_inside_tree():
		viewport_size = label.get_viewport_rect().size
	elif label.get_parent() is Control:
		var parent_control: Control = label.get_parent()
		if parent_control.size.x > 0.0 and parent_control.size.y > 0.0:
			viewport_size = parent_control.size
	label.add_theme_font_size_override("font_size", text_size(role, viewport_size))
	label.add_theme_color_override("font_color", tone)
	if center:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


static func apply_back_button(button: BaseButton, label: Label = null) -> void:
	if button == null:
		return
	button.flat = false
	if label != null:
		button.text = label.text
	button.add_theme_stylebox_override("normal", button_style(false))
	button.add_theme_stylebox_override("hover", button_style(false))
	button.add_theme_stylebox_override("pressed", button_style(false))
	button.add_theme_stylebox_override("focus", button_style(false))
	button.add_theme_color_override("font_color", SECONDARY)
	button.add_theme_color_override("font_hover_color", primary_text())
	button.add_theme_color_override("font_pressed_color", primary_text())
	if label != null:
		apply_label(label, "caption", primary_text(), false)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.visible = false


static func apply_dialog(dialog: Window, viewport_size: Vector2 = Vector2.ZERO) -> void:
	if dialog == null:
		return
	var size := _resolved_viewport_size(dialog, viewport_size)
	var theme := Theme.new()
	if dialog.theme != null:
		theme = dialog.theme.duplicate() as Theme
	_configure_dialog_theme(theme, size)
	dialog.theme = theme
	_style_dialog_subtree(dialog, size)
	_style_accept_dialog_buttons(dialog, size)
	if not dialog.has_meta(DIALOG_THEME_META) and dialog.has_signal("visibility_changed"):
		dialog.set_meta(DIALOG_THEME_META, true)
		dialog.visibility_changed.connect(func() -> void:
			if is_instance_valid(dialog) and dialog.visible:
				HDTheme._style_dialog_subtree(dialog, size)
				HDTheme._style_accept_dialog_buttons(dialog, size)
		)


static func apply_dialog_tree(root: Node, viewport_size: Vector2 = Vector2.ZERO) -> void:
	if root == null:
		return
	if root is Window:
		apply_dialog(root as Window, viewport_size)
	for child in root.get_children():
		apply_dialog_tree(child, viewport_size)


static func dialog_panel_style() -> StyleBoxFlat:
	var style := glass_panel_style(CYAN, true)
	style.bg_color = Color(0.045, 0.065, 0.16, 0.96)
	style.border_color = CYAN * Color(1, 1, 1, 0.30)
	style.shadow_color = Color(0, 0, 0, 0.42)
	style.shadow_size = 18
	style.shadow_offset = Vector2(0, 12)
	_set_style_padding(style, 10.0, 10.0, 8.0, 8.0)
	return style


static func dialog_popup_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_FILL.darkened(0.10)
	style.border_color = CYAN * Color(1, 1, 1, 0.28)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.shadow_color = Color(0, 0, 0, 0.42)
	style.shadow_size = 12
	style.shadow_offset = Vector2(0, 6)
	_set_style_padding(style, 8.0, 8.0, 6.0, 6.0)
	return style


static func dialog_field_style(focused: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.03, 0.08, 0.72 if not focused else 0.88)
	style.border_color = (CYAN if focused else CARD_STROKE) * Color(1, 1, 1, 0.42 if focused else 1.0)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	_set_style_padding(style, 10.0, 10.0, 7.0, 7.0)
	return style


static func dialog_selection_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = CYAN * Color(1, 1, 1, 0.18)
	style.border_color = CYAN * Color(1, 1, 1, 0.34)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	return style


static func _configure_dialog_theme(theme: Theme, viewport_size: Vector2) -> void:
	var body_size := text_size("caption", viewport_size)
	var button_size := text_size("button_secondary", viewport_size)
	for type_name in ["Window", "AcceptDialog", "ConfirmationDialog", "FileDialog"]:
		theme.set_stylebox("panel", type_name, dialog_panel_style())
	theme.set_stylebox("embedded_border", "Window", dialog_panel_style())
	theme.set_stylebox("embedded_unfocused_border", "Window", dialog_panel_style())
	theme.set_color("title_color", "Window", CYAN)
	theme.set_font_size("title_font_size", "Window", text_size("button_secondary", viewport_size))
	theme.set_color("font_color", "Label", SECONDARY)
	theme.set_color("font_shadow_color", "Label", SHADOW)
	theme.set_font_size("font_size", "Label", body_size)
	theme.set_color("font_color", "Button", SECONDARY)
	theme.set_color("font_hover_color", "Button", primary_text())
	theme.set_color("font_pressed_color", "Button", primary_text())
	theme.set_color("font_disabled_color", "Button", TERTIARY.darkened(0.24))
	theme.set_font_size("font_size", "Button", button_size)
	theme.set_stylebox("normal", "Button", _dialog_button_style(false))
	theme.set_stylebox("hover", "Button", _dialog_button_style(true))
	theme.set_stylebox("pressed", "Button", _dialog_button_style(true))
	theme.set_stylebox("focus", "Button", _dialog_button_style(true))
	theme.set_stylebox("disabled", "Button", _dialog_button_disabled_style())
	for field_type in ["LineEdit", "TextEdit"]:
		theme.set_stylebox("normal", field_type, dialog_field_style(false))
		theme.set_stylebox("focus", field_type, dialog_field_style(true))
		theme.set_stylebox("read_only", field_type, dialog_field_style(false))
		theme.set_color("font_color", field_type, primary_text())
		theme.set_color("font_placeholder_color", field_type, TERTIARY)
		theme.set_color("caret_color", field_type, CYAN)
		theme.set_color("selection_color", field_type, CYAN * Color(1, 1, 1, 0.28))
		theme.set_font_size("font_size", field_type, body_size)
	for list_type in ["ItemList", "Tree"]:
		theme.set_stylebox("panel", list_type, dialog_field_style(false))
		theme.set_stylebox("focus", list_type, dialog_field_style(true))
		theme.set_stylebox("selected", list_type, dialog_selection_style())
		theme.set_stylebox("selected_focus", list_type, dialog_selection_style())
		theme.set_color("font_color", list_type, SECONDARY)
		theme.set_color("font_selected_color", list_type, primary_text())
		theme.set_font_size("font_size", list_type, body_size)
	theme.set_stylebox("panel", "PanelContainer", dialog_panel_style())
	theme.set_stylebox("panel", "PopupMenu", dialog_popup_panel_style())
	theme.set_stylebox("hover", "PopupMenu", dialog_selection_style())
	theme.set_color("font_color", "PopupMenu", SECONDARY)
	theme.set_color("font_hover_color", "PopupMenu", primary_text())
	theme.set_color("font_disabled_color", "PopupMenu", TERTIARY.darkened(0.2))
	theme.set_color("font_separator_color", "PopupMenu", CYAN * Color(1, 1, 1, 0.72))
	theme.set_font_size("font_size", "PopupMenu", body_size)
	theme.set_constant("buttons_min_width", "AcceptDialog", 96)
	theme.set_constant("buttons_min_height", "AcceptDialog", 36)
	theme.set_constant("h_separation", "AcceptDialog", 10)
	theme.set_constant("v_separation", "AcceptDialog", 10)
	theme.set_constant("item_start_padding", "PopupMenu", 12)
	theme.set_constant("item_end_padding", "PopupMenu", 12)


static func _style_dialog_subtree(node: Node, viewport_size: Vector2) -> void:
	if node == null:
		return
	if node is Window:
		var window := node as Window
		if window.theme == null:
			var theme := Theme.new()
			_configure_dialog_theme(theme, viewport_size)
			window.theme = theme
	elif node is PopupMenu:
		_style_popup_menu(node as PopupMenu, viewport_size)
	elif node is OptionButton:
		_style_button(node as BaseButton, viewport_size)
		_style_popup_menu((node as OptionButton).get_popup(), viewport_size)
	elif node is CheckBox:
		_style_checkbox(node as CheckBox, viewport_size)
	elif node is CheckButton:
		_style_checkbox(node as CheckButton, viewport_size)
	elif node is BaseButton:
		_style_button(node as BaseButton, viewport_size)
	elif node is LineEdit:
		_style_line_edit(node as LineEdit, viewport_size)
	elif node is TextEdit:
		_style_text_edit(node as TextEdit, viewport_size)
	elif node is Label:
		var label := node as Label
		label.add_theme_color_override("font_color", SECONDARY)
		label.add_theme_font_size_override("font_size", text_size("caption", viewport_size))
	elif node is PanelContainer:
		(node as PanelContainer).add_theme_stylebox_override("panel", dialog_panel_style())
	elif node is ScrollContainer:
		(node as ScrollContainer).add_theme_stylebox_override("panel", dialog_field_style(false))
	elif node is ItemList:
		_style_item_list(node as ItemList, viewport_size)
	elif node is Tree:
		_style_tree(node as Tree, viewport_size)
	for child in node.get_children():
		_style_dialog_subtree(child, viewport_size)


static func _style_accept_dialog_buttons(dialog: Window, viewport_size: Vector2) -> void:
	if dialog == null or not (dialog is AcceptDialog):
		return
	var accept_dialog := dialog as AcceptDialog
	_style_button(accept_dialog.get_ok_button(), viewport_size)
	if accept_dialog is ConfirmationDialog:
		_style_button((accept_dialog as ConfirmationDialog).get_cancel_button(), viewport_size)


static func _style_button(button: BaseButton, viewport_size: Vector2) -> void:
	if button == null:
		return
	button.flat = false
	button.add_theme_stylebox_override("normal", _dialog_button_style(false))
	button.add_theme_stylebox_override("hover", _dialog_button_style(true))
	button.add_theme_stylebox_override("pressed", _dialog_button_style(true))
	button.add_theme_stylebox_override("focus", _dialog_button_style(true))
	button.add_theme_stylebox_override("disabled", _dialog_button_disabled_style())
	button.add_theme_color_override("font_color", SECONDARY)
	button.add_theme_color_override("font_hover_color", primary_text())
	button.add_theme_color_override("font_pressed_color", primary_text())
	button.add_theme_color_override("font_disabled_color", TERTIARY.darkened(0.24))
	button.add_theme_font_size_override("font_size", text_size("button_secondary", viewport_size))


static func _style_checkbox(button: BaseButton, viewport_size: Vector2) -> void:
	if button == null:
		return
	button.add_theme_color_override("font_color", SECONDARY)
	button.add_theme_color_override("font_hover_color", primary_text())
	button.add_theme_color_override("font_pressed_color", primary_text())
	button.add_theme_font_size_override("font_size", text_size("caption", viewport_size))


static func _style_line_edit(edit: LineEdit, viewport_size: Vector2) -> void:
	if edit == null:
		return
	edit.add_theme_stylebox_override("normal", dialog_field_style(false))
	edit.add_theme_stylebox_override("focus", dialog_field_style(true))
	edit.add_theme_stylebox_override("read_only", dialog_field_style(false))
	edit.add_theme_color_override("font_color", primary_text())
	edit.add_theme_color_override("font_placeholder_color", TERTIARY)
	edit.add_theme_color_override("caret_color", CYAN)
	edit.add_theme_color_override("selection_color", CYAN * Color(1, 1, 1, 0.28))
	edit.add_theme_font_size_override("font_size", text_size("caption", viewport_size))


static func _style_text_edit(edit: TextEdit, viewport_size: Vector2) -> void:
	if edit == null:
		return
	edit.add_theme_stylebox_override("normal", dialog_field_style(false))
	edit.add_theme_stylebox_override("focus", dialog_field_style(true))
	edit.add_theme_stylebox_override("read_only", dialog_field_style(false))
	edit.add_theme_color_override("font_color", primary_text())
	edit.add_theme_color_override("font_placeholder_color", TERTIARY)
	edit.add_theme_color_override("caret_color", CYAN)
	edit.add_theme_color_override("selection_color", CYAN * Color(1, 1, 1, 0.28))
	edit.add_theme_font_size_override("font_size", text_size("caption", viewport_size))


static func _style_item_list(list: ItemList, viewport_size: Vector2) -> void:
	if list == null:
		return
	list.add_theme_stylebox_override("panel", dialog_field_style(false))
	list.add_theme_stylebox_override("focus", dialog_field_style(true))
	list.add_theme_stylebox_override("selected", dialog_selection_style())
	list.add_theme_stylebox_override("selected_focus", dialog_selection_style())
	list.add_theme_color_override("font_color", SECONDARY)
	list.add_theme_color_override("font_selected_color", primary_text())
	list.add_theme_font_size_override("font_size", text_size("caption", viewport_size))


static func _style_tree(tree: Tree, viewport_size: Vector2) -> void:
	if tree == null:
		return
	tree.add_theme_stylebox_override("panel", dialog_field_style(false))
	tree.add_theme_stylebox_override("focus", dialog_field_style(true))
	tree.add_theme_stylebox_override("selected", dialog_selection_style())
	tree.add_theme_stylebox_override("selected_focus", dialog_selection_style())
	tree.add_theme_color_override("font_color", SECONDARY)
	tree.add_theme_color_override("font_selected_color", primary_text())
	tree.add_theme_font_size_override("font_size", text_size("caption", viewport_size))


static func _style_popup_menu(popup: PopupMenu, viewport_size: Vector2) -> void:
	if popup == null:
		return
	popup.add_theme_stylebox_override("panel", dialog_popup_panel_style())
	popup.add_theme_stylebox_override("hover", dialog_selection_style())
	popup.add_theme_color_override("font_color", SECONDARY)
	popup.add_theme_color_override("font_hover_color", primary_text())
	popup.add_theme_color_override("font_disabled_color", TERTIARY.darkened(0.2))
	popup.add_theme_color_override("font_separator_color", CYAN * Color(1, 1, 1, 0.72))
	popup.add_theme_font_size_override("font_size", text_size("caption", viewport_size))
	popup.add_theme_constant_override("item_start_padding", 12)
	popup.add_theme_constant_override("item_end_padding", 12)
	popup.transparent_bg = true


static func _dialog_button_style(hover: bool) -> StyleBoxFlat:
	var style := button_style(false)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	if hover:
		style.bg_color = CARD_FILL.lightened(0.05)
		style.border_color = CYAN * Color(1, 1, 1, 0.38)
	_set_style_padding(style, 12.0, 12.0, 6.0, 6.0)
	return style


static func _dialog_button_disabled_style() -> StyleBoxFlat:
	var style := _dialog_button_style(false)
	style.bg_color = CARD_FILL.darkened(0.10)
	style.border_color = CARD_STROKE.darkened(0.22)
	style.shadow_size = 0
	return style


static func _resolved_viewport_size(node: Node, fallback: Vector2) -> Vector2:
	if fallback != Vector2.ZERO:
		return fallback
	if node != null and node.is_inside_tree():
		var viewport := node.get_viewport()
		if viewport != null:
			return viewport.get_visible_rect().size
	return Vector2(1280.0, 720.0)


static func _set_style_padding(style: StyleBoxFlat, left: float, right: float, top: float, bottom: float) -> void:
	style.set_content_margin(SIDE_LEFT, left)
	style.set_content_margin(SIDE_RIGHT, right)
	style.set_content_margin(SIDE_TOP, top)
	style.set_content_margin(SIDE_BOTTOM, bottom)


static func button_style(primary: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.corner_radius_top_left = 22
	style.corner_radius_top_right = 22
	style.corner_radius_bottom_left = 22
	style.corner_radius_bottom_right = 22
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	if primary:
		style.bg_color = CYAN * Color(1, 1, 1, 0.17)
		style.border_color = CYAN * Color(1, 1, 1, 0.32)
	else:
		style.bg_color = CARD_FILL
		style.border_color = CARD_STROKE
	style.shadow_color = (CYAN if primary else Color.BLACK) * Color(1, 1, 1, 0.11)
	style.shadow_size = 6 if primary else 4
	style.shadow_offset = Vector2(0, 5)
	return style


static func card_style() -> StyleBoxFlat:
	return glass_panel_style(CYAN, false)


static func overlay_panel_style() -> StyleBoxFlat:
	return glass_panel_style(CYAN, true)


static func glass_panel_style(accent: Color = CYAN, major: bool = true) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_FILL if major else CARD_FILL
	style.border_color = accent * Color(1, 1, 1, 0.16 if major else 0.12)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	var radius := 28 if major else 24
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.shadow_color = accent * Color(1, 1, 1, 0.09)
	style.shadow_size = 11 if major else 7
	style.shadow_offset = Vector2(0, 8 if major else 5)
	return style


static func song_card_style(accent: Color = CYAN, selected: bool = false) -> StyleBoxFlat:
	var style := glass_panel_style(accent, false)
	if selected:
		style.bg_color = style.bg_color.lerp(accent, 0.11)
		style.border_color = accent * Color(1, 1, 1, 0.36)
		style.shadow_color = accent * Color(1, 1, 1, 0.17)
		style.shadow_size = 11
	return style
