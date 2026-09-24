extends Control
class_name SpiralLaneLayer

var lane_count := 4
var lane_colors: Array = []
var phase := 0.0
var line_alpha := 0.22
var band_width := 12.0
var decorative := false
var playfield_left := 0.0
var playfield_width := 0.0
var hit_line_y := 0.0

const GAMEPLAY_SPIRAL_START_PROGRESS := 0.72
const GAMEPLAY_SPIRAL_FULL_PROGRESS := 0.90
const GAMEPLAY_SPIRAL_CENTER_Y := 0.26


func configure(count: int, colors: Array, is_decorative: bool = false) -> void:
	lane_count = maxi(1, count)
	lane_colors = colors.duplicate(true)
	decorative = is_decorative
	queue_redraw()


func set_playfield_metrics(left: float, width: float, hit_line: float) -> void:
	playfield_left = left
	playfield_width = width
	hit_line_y = hit_line
	queue_redraw()


func set_phase(value: float) -> void:
	phase = value
	queue_redraw()


func _draw() -> void:
	if size.x <= 1.0 or size.y <= 1.0:
		return
	if not decorative:
		_draw_spiral_lanes()
		return
	_draw_decorative_spiral()


func _draw_decorative_spiral() -> void:
	var center := size * 0.5
	var max_radius := size.length() * 0.62
	var turns := 5.75
	var steps := 360
	var spacing := TAU / float(lane_count)
	for lane in range(lane_count):
		var points := PackedVector2Array()
		var offset := phase + float(lane) * spacing
		for step in range(steps):
			var t := float(step) / float(steps - 1)
			var theta := t * TAU * turns + offset
			var radius := lerpf(8.0, max_radius, t)
			points.append(center + Vector2(cos(theta), sin(theta)) * radius)
		var color: Color = lane_colors[lane % lane_colors.size()] if not lane_colors.is_empty() else Color.WHITE
		draw_polyline(points, color * Color(1.0, 1.0, 1.0, line_alpha), band_width, true)
		draw_polyline(points, color.lerp(Color.WHITE, 0.35) * Color(1.0, 1.0, 1.0, line_alpha * 0.55), maxf(2.0, band_width * 0.22), true)


func _draw_spiral_lanes() -> void:
	var steps := 180
	for lane in range(lane_count):
		var points := PackedVector2Array()
		for step in range(steps):
			var progress := float(step) / float(steps - 1)
			points.append(spiral_lane_position(lane, progress, phase, size, playfield_left, playfield_width, hit_line_y, lane_count) - position)
		var color: Color = lane_colors[lane % lane_colors.size()] if not lane_colors.is_empty() else Color.WHITE
		draw_polyline(points, color * Color(1.0, 1.0, 1.0, line_alpha), maxf(6.0, band_width * 0.70), true)
		draw_polyline(points, color.lerp(Color.WHITE, 0.45) * Color(1.0, 1.0, 1.0, line_alpha * 0.55), maxf(1.5, band_width * 0.18), true)


static func spiral_lane_position(lane: int, progress: float, phase_value: float, viewport_size: Vector2, left: float, width: float, hit_line: float, count: int) -> Vector2:
	var safe_count := maxi(1, count)
	var lane_width := width / float(safe_count)
	var hit_point := Vector2(left + (float(lane) + 0.5) * lane_width, hit_line)
	var center := Vector2(left + width * 0.5, viewport_size.y * GAMEPLAY_SPIRAL_CENTER_Y)
	var start_vector := hit_point - center
	var start_radius := maxf(28.0, start_vector.length())
	var start_angle := start_vector.angle()
	var p := clampf(progress, 0.0, 1.0)
	var lane_phase := phase_value * 0.42 + float(lane) * 0.045
	var phase_influence := p * p * (3.0 - 2.0 * p)
	var theta := start_angle + lane_phase * phase_influence + p * TAU * 0.68
	var inner_radius := maxf(70.0, width * 0.24)
	var radius := lerpf(start_radius, inner_radius, p)
	var spiral_point := center + Vector2(cos(theta), sin(theta)) * radius
	var straight_x := hit_point.x
	var straight_y := lerpf(hit_line, -viewport_size.y * 0.05, p)
	var straight_point := Vector2(straight_x, straight_y)
	var blend_span := maxf(0.001, GAMEPLAY_SPIRAL_FULL_PROGRESS - GAMEPLAY_SPIRAL_START_PROGRESS)
	var blend := clampf((p - GAMEPLAY_SPIRAL_START_PROGRESS) / blend_span, 0.0, 1.0)
	blend = blend * blend * (3.0 - 2.0 * blend)
	return straight_point.lerp(spiral_point, blend)
