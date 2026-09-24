extends Control

const KIND_TEXT := "text"
const KIND_KEY_SYMBOL := "key_symbol"
const KIND_KEY_SHORT := "key_short"
const KIND_CONTROLLER_BUTTON := "controller_button"
const KIND_CONTROLLER_AXIS := "controller_axis"
const KIND_EMPTY := "empty"

var display: Dictionary = {
	"kind": KIND_EMPTY,
	"text": "",
	"tooltip": "",
}


static func keyboard_display(physical_keycode: int) -> Dictionary:
	if physical_keycode == 0:
		return _display(KIND_EMPTY, "", "Unbound")
	var raw := OS.get_keycode_string(physical_keycode)
	var symbol := _keyboard_symbol(raw)
	if not symbol.is_empty():
		return _display(KIND_KEY_SYMBOL, symbol, raw)
	var normalized := raw.strip_edges().to_upper()
	if _is_single_letter_or_number(normalized):
		return _display(KIND_TEXT, normalized, raw)
	return _display(KIND_KEY_SHORT, _keyboard_short_name(raw), raw)


static func controller_display(binding_variant: Variant) -> Dictionary:
	if binding_variant is not Dictionary:
		return _display(KIND_EMPTY, "UNBOUND", "Unbound")
	var binding: Dictionary = binding_variant as Dictionary
	match str(binding.get("kind", "")).to_lower():
		"axis":
			var axis := int(binding.get("axis", 0))
			var direction := int(binding.get("direction", 1))
			return _display(KIND_CONTROLLER_AXIS, _controller_axis_short_name(axis, direction), _controller_axis_full_name(axis, direction))
		"button":
			var button_index := int(binding.get("button_index", 0))
			return _display(KIND_CONTROLLER_BUTTON, _controller_button_short_name(button_index), _controller_button_full_name(button_index))
		_:
			return _display(KIND_EMPTY, "UNBOUND", "Unbound")


static func display_text(binding_display: Dictionary) -> String:
	return str(binding_display.get("text", ""))


static func display_tooltip(binding_display: Dictionary) -> String:
	return str(binding_display.get("tooltip", binding_display.get("text", "")))


static func should_draw_glyph(binding_display: Dictionary) -> bool:
	var kind := str(binding_display.get("kind", KIND_TEXT))
	return kind == KIND_KEY_SYMBOL or kind == KIND_CONTROLLER_BUTTON or kind == KIND_CONTROLLER_AXIS


static func is_empty(binding_display: Dictionary) -> bool:
	return str(binding_display.get("kind", KIND_EMPTY)) == KIND_EMPTY


func set_display(binding_display: Dictionary) -> void:
	display = binding_display.duplicate(true)
	tooltip_text = display_tooltip(display)
	queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var kind := str(display.get("kind", KIND_EMPTY))
	var text := display_text(display)
	if text.is_empty():
		return
	match kind:
		KIND_CONTROLLER_BUTTON:
			_draw_controller_button(text)
		KIND_CONTROLLER_AXIS:
			_draw_controller_axis(text)
		_:
			_draw_keycap(text)


func _draw_keycap(text: String) -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var radius := minf(size.x, size.y) * 0.22
	draw_rect(rect.grow(-1.0), Color(0.02, 0.04, 0.08, 0.84), true)
	draw_rect(rect.grow(-1.0), Color(0.45, 0.85, 1.0, 0.72), false, 2.0)
	_draw_centered_text(text, rect, Color(0.94, 0.98, 1.0, 1.0), radius)


func _draw_controller_button(text: String) -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var is_shoulder := text in ["LB", "RB", "LT", "RT", "L3", "R3", "BCK", "OPT", "BTN"]
	if text.begins_with("D"):
		_draw_dpad_icon(text, rect)
		return
	if is_shoulder:
		_draw_pill_icon(text, rect, Color(0.04, 0.08, 0.12, 0.88), Color(0.45, 0.85, 1.0, 0.80))
		return
	var center := rect.get_center()
	var radius := minf(size.x, size.y) * 0.42
	draw_circle(center, radius, Color(0.04, 0.08, 0.12, 0.88))
	draw_arc(center, radius, 0.0, TAU, 48, Color(0.45, 0.85, 1.0, 0.82), 2.0)
	_draw_centered_text(text, rect, Color(0.94, 0.98, 1.0, 1.0), radius)


func _draw_controller_axis(text: String) -> void:
	if text == "LT" or text == "RT":
		_draw_pill_icon(text, Rect2(Vector2.ZERO, size), Color(0.04, 0.08, 0.12, 0.88), Color(0.45, 0.85, 1.0, 0.80))
		return
	var rect := Rect2(Vector2.ZERO, size)
	var center := rect.get_center()
	var radius := minf(size.x, size.y) * 0.36
	draw_circle(center, radius, Color(0.04, 0.08, 0.12, 0.78))
	draw_circle(center, radius * 0.45, Color(0.45, 0.85, 1.0, 0.32))
	draw_arc(center, radius, 0.0, TAU, 40, Color(0.45, 0.85, 1.0, 0.72), 2.0)
	_draw_centered_text(text, rect, Color(0.94, 0.98, 1.0, 1.0), radius)


func _draw_dpad_icon(text: String, rect: Rect2) -> void:
	var center := rect.get_center()
	var arm := minf(size.x, size.y) * 0.24
	var thickness := maxf(8.0, arm * 0.78)
	var horizontal := Rect2(Vector2(center.x - arm * 1.6, center.y - thickness * 0.5), Vector2(arm * 3.2, thickness))
	var vertical := Rect2(Vector2(center.x - thickness * 0.5, center.y - arm * 1.6), Vector2(thickness, arm * 3.2))
	draw_rect(horizontal, Color(0.04, 0.08, 0.12, 0.88), true)
	draw_rect(vertical, Color(0.04, 0.08, 0.12, 0.88), true)
	draw_rect(horizontal, Color(0.45, 0.85, 1.0, 0.54), false, 2.0)
	draw_rect(vertical, Color(0.45, 0.85, 1.0, 0.54), false, 2.0)
	_draw_centered_text(text, rect, Color(0.94, 0.98, 1.0, 1.0), arm)


func _draw_pill_icon(text: String, rect: Rect2, fill: Color, stroke: Color) -> void:
	var inner := rect.grow(-2.0)
	draw_rect(inner, fill, true)
	draw_rect(inner, stroke, false, 2.0)
	_draw_centered_text(text, rect, Color(0.94, 0.98, 1.0, 1.0), minf(size.x, size.y) * 0.35)


func _draw_centered_text(text: String, rect: Rect2, color: Color, target_size: float) -> void:
	var font := get_theme_default_font()
	var font_size := int(clampf(target_size, 12.0, 32.0))
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
	if text_size.x > rect.size.x - 8.0 and text_size.x > 0.0:
		font_size = maxi(10, int(floorf(float(font_size) * ((rect.size.x - 8.0) / text_size.x))))
		text_size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
	var pos := Vector2(rect.position.x + (rect.size.x - text_size.x) * 0.5, rect.position.y + (rect.size.y + text_size.y * 0.55) * 0.5)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)


static func _display(kind: String, text: String, tooltip: String) -> Dictionary:
	return {
		"kind": kind,
		"text": text,
		"tooltip": tooltip if not tooltip.is_empty() else text,
	}


static func _keyboard_symbol(raw: String) -> String:
	var key := raw.strip_edges().to_lower().replace(" ", "").replace("_", "").replace("-", "")
	match key:
		"semicolon":
			return ";"
		"apostrophe", "quote":
			return "'"
		"comma":
			return ","
		"period":
			return "."
		"slash":
			return "/"
		"backslash":
			return "\\"
		"bracketleft", "leftbracket":
			return "["
		"bracketright", "rightbracket":
			return "]"
		"minus":
			return "-"
		"equal", "equals":
			return "="
		"grave", "quoteleft", "backquote":
			return "`"
		_:
			return ""


static func _keyboard_short_name(raw: String) -> String:
	var key := raw.strip_edges().to_lower().replace(" ", "").replace("_", "").replace("-", "")
	match key:
		"escape":
			return "ESC"
		"space":
			return "SPC"
		"tab":
			return "TAB"
		"enter", "return":
			return "ENT"
		"kpenter":
			return "KPENT"
		"backspace":
			return "BKSP"
		"delete":
			return "DEL"
		"insert":
			return "INS"
		"home":
			return "HOME"
		"end":
			return "END"
		"pageup":
			return "PGUP"
		"pagedown":
			return "PGDN"
		"left":
			return "LEFT"
		"right":
			return "RGHT"
		"up":
			return "UP"
		"down":
			return "DOWN"
		"shift":
			return "SHFT"
		"control", "ctrl":
			return "CTRL"
		"alt":
			return "ALT"
		"meta", "super", "command":
			return "META"
	var upper := raw.strip_edges().to_upper().replace(" ", "")
	if upper.length() <= 5:
		return upper
	var compact := upper.substr(0, 1)
	for i in range(1, upper.length()):
		var c := upper.substr(i, 1)
		if c not in ["A", "E", "I", "O", "U"]:
			compact += c
		if compact.length() >= 5:
			break
	return compact.substr(0, 5)


static func _is_single_letter_or_number(text: String) -> bool:
	if text.length() != 1:
		return false
	var code := text.unicode_at(0)
	return (code >= 65 and code <= 90) or (code >= 48 and code <= 57)


static func _controller_button_short_name(button_index: int) -> String:
	match button_index:
		JOY_BUTTON_A:
			return "A"
		JOY_BUTTON_B:
			return "B"
		JOY_BUTTON_X:
			return "X"
		JOY_BUTTON_Y:
			return "Y"
		JOY_BUTTON_LEFT_SHOULDER:
			return "LB"
		JOY_BUTTON_RIGHT_SHOULDER:
			return "RB"
		JOY_BUTTON_START:
			return "OPT"
		JOY_BUTTON_DPAD_UP:
			return "DU"
		JOY_BUTTON_DPAD_DOWN:
			return "DD"
		JOY_BUTTON_DPAD_LEFT:
			return "DL"
		JOY_BUTTON_DPAD_RIGHT:
			return "DR"
		JOY_BUTTON_LEFT_STICK:
			return "L3"
		JOY_BUTTON_RIGHT_STICK:
			return "R3"
		_:
			return "B%d" % button_index


static func _controller_button_full_name(button_index: int) -> String:
	match button_index:
		JOY_BUTTON_A:
			return "A / Cross"
		JOY_BUTTON_B:
			return "B / Circle"
		JOY_BUTTON_X:
			return "X / Square"
		JOY_BUTTON_Y:
			return "Y / Triangle"
		JOY_BUTTON_LEFT_SHOULDER:
			return "L1 / LB"
		JOY_BUTTON_RIGHT_SHOULDER:
			return "R1 / RB"
		JOY_BUTTON_START:
			return "Start / Options"
		JOY_BUTTON_DPAD_UP:
			return "D-Pad Up"
		JOY_BUTTON_DPAD_DOWN:
			return "D-Pad Down"
		JOY_BUTTON_DPAD_LEFT:
			return "D-Pad Left"
		JOY_BUTTON_DPAD_RIGHT:
			return "D-Pad Right"
		JOY_BUTTON_LEFT_STICK:
			return "L3"
		JOY_BUTTON_RIGHT_STICK:
			return "R3"
		_:
			return "Button %d" % button_index


static func _controller_axis_short_name(axis: int, direction: int) -> String:
	var suffix := "-" if direction < 0 else "+"
	match axis:
		JOY_AXIS_LEFT_X:
			return "LX%s" % suffix
		JOY_AXIS_LEFT_Y:
			return "LY%s" % suffix
		JOY_AXIS_RIGHT_X:
			return "RX%s" % suffix
		JOY_AXIS_RIGHT_Y:
			return "RY%s" % suffix
		JOY_AXIS_TRIGGER_LEFT:
			return "LT"
		JOY_AXIS_TRIGGER_RIGHT:
			return "RT"
		_:
			return "A%d%s" % [axis, suffix]


static func _controller_axis_full_name(axis: int, direction: int) -> String:
	var suffix := "-" if direction < 0 else "+"
	match axis:
		JOY_AXIS_LEFT_X:
			return "Left Stick X%s" % suffix
		JOY_AXIS_LEFT_Y:
			return "Left Stick Y%s" % suffix
		JOY_AXIS_RIGHT_X:
			return "Right Stick X%s" % suffix
		JOY_AXIS_RIGHT_Y:
			return "Right Stick Y%s" % suffix
		JOY_AXIS_TRIGGER_LEFT:
			return "L2 / LT%s" % suffix
		JOY_AXIS_TRIGGER_RIGHT:
			return "R2 / RT%s" % suffix
		_:
			return "Axis %d%s" % [axis, suffix]
