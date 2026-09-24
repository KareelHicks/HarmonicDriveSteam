extends Control
class_name BlackHoleLaneLayer

var lane_count := 4
var lane_colors: Array = []
var phase := 0.0
var playfield_left := 0.0
var playfield_width := 0.0
var hit_line_y := 0.0
var line_alpha := 0.22
var band_width := 8.0


func configure(count: int, colors: Array) -> void:
	lane_count = maxi(1, count)
	lane_colors = colors.duplicate(true)
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
	var steps := 120
	for lane in range(lane_count):
		var points := PackedVector2Array()
		for step in range(steps):
			var progress := float(step) / float(steps - 1)
			points.append(black_hole_lane_position(lane, progress, phase, size, playfield_left, playfield_width, hit_line_y, lane_count) - position)
		var color: Color = lane_colors[lane % lane_colors.size()] if not lane_colors.is_empty() else Color.WHITE
		draw_polyline(points, color * Color(1.0, 1.0, 1.0, line_alpha), maxf(5.0, band_width * 0.72), true)
		draw_polyline(points, color.lerp(Color.WHITE, 0.42) * Color(1.0, 1.0, 1.0, line_alpha * 0.56), maxf(1.5, band_width * 0.22), true)
	_draw_gravity_well()


func _draw_gravity_well() -> void:
	var center := Vector2(playfield_left + playfield_width * 0.5, hit_line_y * 0.48)
	var radius := maxf(28.0, playfield_width * 0.055)
	draw_circle(center - position, radius * 2.2, Color(0.0, 0.0, 0.0, 0.18))
	draw_arc(center - position, radius * 2.8, phase, phase + TAU * 0.78, 48, Color(1.0, 1.0, 1.0, 0.13), 2.0, true)
	draw_arc(center - position, radius * 1.7, -phase * 1.25, -phase * 1.25 + TAU * 0.68, 48, Color(0.15, 0.82, 1.0, 0.12), 2.0, true)


static func black_hole_lane_position(lane: int, progress: float, phase_value: float, viewport_size: Vector2, left: float, width: float, hit_line: float, count: int) -> Vector2:
	var safe_count := maxi(1, count)
	var lane_width := width / float(safe_count)
	var base_x := left + (float(lane) + 0.5) * lane_width
	var p := clampf(progress, 0.0, 1.0)
	var y := lerpf(hit_line, -viewport_size.y * 0.07, p)
	var well := Vector2(left + width * 0.5, hit_line * 0.48)
	var straight := Vector2(base_x, y)
	var distance_ratio := clampf(absf(base_x - well.x) / maxf(1.0, width * 0.5), 0.0, 1.0)
	var pull_window := sin(p * PI)
	var pull_strength := 0.12 + distance_ratio * 0.10
	var pulse := 1.0 + sin(phase_value + p * TAU * 1.4) * 0.08
	var pulled := straight.lerp(well, pull_strength * pull_window * pulse)
	return Vector2(pulled.x, straight.y)
