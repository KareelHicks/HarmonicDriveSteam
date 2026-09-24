extends Control
class_name ModernHUDPanel

const SIDE_LEFT := "left"
const SIDE_RIGHT := "right"

var panel_side := SIDE_LEFT
var fill_color := Color(0.02, 0.03, 0.11, 0.58)
var accent_color := Color(0.15, 0.82, 1.0, 0.92)
var secondary_accent_color := Color(0.90, 0.18, 1.0, 0.78)
var border_width := 1.5


func set_panel_side(value: String) -> void:
	panel_side = SIDE_RIGHT if value == SIDE_RIGHT else SIDE_LEFT
	queue_redraw()


func set_panel_colors(fill: Color, accent: Color, secondary: Color) -> void:
	fill_color = fill
	accent_color = accent
	secondary_accent_color = secondary
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	if size.x <= 2.0 or size.y <= 2.0:
		return
	var points := _panel_points()
	var closed := _closed_points(points)
	draw_colored_polygon(points, fill_color)
	draw_polyline(closed, accent_color * Color(1.0, 1.0, 1.0, 0.18), border_width + 3.0, true)
	draw_polyline(closed, accent_color, border_width, true)
	_draw_inner_lines()


func _panel_points() -> PackedVector2Array:
	var w := size.x
	var h := size.y
	if panel_side == SIDE_RIGHT:
		return PackedVector2Array([
			Vector2(w * 0.18, 0.0),
			Vector2(w, 0.0),
			Vector2(w, h),
			Vector2(w * 0.18, h),
			Vector2(0.0, h * 0.78),
			Vector2(0.0, h * 0.25),
		])
	return PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(w * 0.78, 0.0),
		Vector2(w * 0.91, h * 0.18),
		Vector2(w, h * 0.27),
		Vector2(w, h * 0.78),
		Vector2(w * 0.88, h * 0.92),
		Vector2(w * 0.82, h),
		Vector2(0.0, h),
	])


func _closed_points(points: PackedVector2Array) -> PackedVector2Array:
	var closed := PackedVector2Array()
	for point in points:
		closed.append(point)
	if points.size() > 0:
		closed.append(points[0])
	return closed


func _draw_inner_lines() -> void:
	var w := size.x
	var h := size.y
	var inset := 10.0
	var secondary := secondary_accent_color * Color(1.0, 1.0, 1.0, 0.70)
	var primary := accent_color * Color(1.0, 1.0, 1.0, 0.82)
	if panel_side == SIDE_RIGHT:
		draw_line(Vector2(w * 0.26, inset), Vector2(w - inset, inset), primary, 1.4, true)
		draw_line(Vector2(inset, h * 0.30), Vector2(inset, h * 0.72), primary, 1.2, true)
		draw_line(Vector2(inset, h * 0.75), Vector2(w * 0.15, h - inset), primary, 2.0, true)
		draw_line(Vector2(w * 0.44, h - inset), Vector2(w - inset, h - inset), secondary, 1.4, true)
		draw_line(Vector2(w * 0.18, h - inset * 2.1), Vector2(w * 0.18 + 24.0, h - inset * 0.55), primary, 2.0, true)
	else:
		draw_line(Vector2(inset, inset), Vector2(w * 0.76, inset), primary, 1.4, true)
		draw_line(Vector2(w - inset, h * 0.30), Vector2(w - inset, h * 0.73), secondary, 1.2, true)
		draw_line(Vector2(w - inset, h * 0.78), Vector2(w * 0.86, h - inset), secondary, 2.0, true)
		draw_line(Vector2(inset, h - inset), Vector2(w * 0.62, h - inset), primary, 1.4, true)
		draw_line(Vector2(w * 0.70, h - inset * 0.55), Vector2(w * 0.82, h - inset * 0.55), secondary, 2.0, true)
