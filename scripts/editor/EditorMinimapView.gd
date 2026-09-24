extends Control
class_name EditorMinimapView

signal scrub_requested(time_sec: float)

const HDTheme := preload("res://scripts/ui/HDTheme.gd")

var orientation := "horizontal"
var vertical_direction := "fall_down"

var _notes: Array[Dictionary] = []
var _audio_length := 0.0
var _cached_duration := 1.0
var _cursor_time := 0.0
var _view_start_time := 0.0
var _view_end_time := 0.0
var _density_bins: Array[int] = []
var _density_bins_count := 0
var _density_duration := 0.0
var _density_max_count := 1
var _density_dirty := true


func set_notes(notes: Array) -> void:
	_notes.clear()
	for n in notes:
		if n is Dictionary:
			_notes.append((n as Dictionary).duplicate(true))
	_recalculate_duration()
	_density_dirty = true
	queue_redraw()


func set_audio_length(length_sec: float) -> void:
	_audio_length = maxf(0.0, length_sec)
	_recalculate_duration()
	_density_dirty = true
	queue_redraw()


func set_cursor_time(time_sec: float) -> void:
	_cursor_time = maxf(0.0, time_sec)
	queue_redraw()


func set_view_window(start_time: float, end_time: float) -> void:
	_view_start_time = maxf(0.0, start_time)
	_view_end_time = maxf(_view_start_time, end_time)
	queue_redraw()


func set_vertical_direction(direction: String) -> void:
	vertical_direction = direction if direction == "rise_up" else "fall_down"
	queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			scrub_requested.emit(_position_to_time(mb.position))
			accept_event()
			return
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var mm: InputEventMouseMotion = event
		scrub_requested.emit(_position_to_time(mm.position))
		accept_event()
		return


func _draw() -> void:
	var palette := HDTheme.theme_palette("theme_neon")
	draw_rect(Rect2(Vector2.ZERO, size), (palette["gutter"] as Color) * Color(1, 1, 1, 0.75), true)
	draw_rect(Rect2(Vector2.ZERO, size), HDTheme.CARD_STROKE, false, 1.0)
	if orientation == "vertical":
		_draw_vertical(palette)
	else:
		_draw_horizontal(palette)


func _draw_horizontal(palette: Dictionary) -> void:
	var duration := _duration()
	var base_y := size.y - 18.0
	var density_rect := Rect2(Vector2(0.0, 8.0), Vector2(size.x, maxf(10.0, size.y - 32.0)))
	_draw_horizontal_density(density_rect, duration, palette)
	_draw_horizontal_time_labels(duration, base_y)
	var cursor_x := _time_to_x(_cursor_time, duration)
	draw_line(Vector2(cursor_x, 3.0), Vector2(cursor_x, size.y - 3.0), palette["rail"], 2.0)
	if _view_end_time > _view_start_time:
		var x0 := _time_to_x(_view_start_time, duration)
		var x1 := _time_to_x(_view_end_time, duration)
		draw_rect(Rect2(Vector2(x0, 2.0), Vector2(maxf(2.0, x1 - x0), size.y - 4.0)), HDTheme.CYAN * Color(1, 1, 1, 0.10), true)
		draw_rect(Rect2(Vector2(x0, 2.0), Vector2(maxf(2.0, x1 - x0), size.y - 4.0)), HDTheme.CYAN * Color(1, 1, 1, 0.60), false, 1.0)


func _draw_vertical(palette: Dictionary) -> void:
	var duration := _duration()
	var bins: int = maxi(8, int(size.y / 8.0))
	_ensure_density_cache(bins, duration)
	for i in range(bins):
		var t0 := (float(i) / float(bins)) * duration
		var t1 := (float(i + 1) / float(bins)) * duration
		var y0 := _time_to_y(t0, duration)
		var y1 := _time_to_y(t1, duration)
		var top := minf(y0, y1)
		var h := maxf(2.0, absf(y1 - y0))
		var w := (float(_density_bins[i]) / float(_density_max_count)) * maxf(2.0, size.x - 8.0)
		draw_rect(Rect2(Vector2(4.0, top), Vector2(w, h)), (palette["rail"] as Color) * Color(1, 1, 1, 0.36), true)
	var cursor_y := _time_to_y(_cursor_time, duration)
	draw_line(Vector2(0.0, cursor_y), Vector2(size.x, cursor_y), palette["rail"], 2.0)
	if _view_end_time > _view_start_time:
		var vy0 := _time_to_y(_view_start_time, duration)
		var vy1 := _time_to_y(_view_end_time, duration)
		var y := minf(vy0, vy1)
		var h2 := maxf(3.0, absf(vy1 - vy0))
		draw_rect(Rect2(Vector2(1.0, y), Vector2(size.x - 2.0, h2)), HDTheme.CYAN * Color(1, 1, 1, 0.14), true)
		draw_rect(Rect2(Vector2(1.0, y), Vector2(size.x - 2.0, h2)), HDTheme.CYAN * Color(1, 1, 1, 0.60), false, 1.0)


func _draw_horizontal_density(rect: Rect2, duration: float, palette: Dictionary) -> void:
	var bins: int = maxi(16, int(size.x / 10.0))
	_ensure_density_cache(bins, duration)
	var bin_w := rect.size.x / float(bins)
	for i in range(bins):
		var h := (float(_density_bins[i]) / float(_density_max_count)) * rect.size.y
		draw_rect(Rect2(Vector2(rect.position.x + float(i) * bin_w, rect.position.y + rect.size.y - h), Vector2(maxf(1.0, bin_w - 1.0), h)), (palette["rail"] as Color) * Color(1, 1, 1, 0.28), true)


func _draw_horizontal_time_labels(duration: float, y: float) -> void:
	var marks := 5
	var font := get_theme_default_font()
	for i in range(marks):
		var ratio := float(i) / float(marks - 1)
		var t := duration * ratio
		var x := minf(size.x - 1.0, size.x * ratio)
		draw_line(Vector2(x, y - 7.0), Vector2(x, y), HDTheme.TERTIARY, 1.0)
		var text := _format_clock(t)
		var text_w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		var label_x := clampf(x + 4.0, 4.0, maxf(4.0, size.x - text_w - 4.0))
		draw_string(font, Vector2(label_x, y + 10.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, HDTheme.TERTIARY)


func _duration() -> float:
	return _cached_duration


func _recalculate_duration() -> void:
	var last := _audio_length
	for n in _notes:
		last = maxf(last, float(n.get("time", 0.0)) + float(n.get("length", 0.0)) + 2.0)
	_cached_duration = maxf(1.0, last)


func _ensure_density_cache(bins: int, duration: float) -> void:
	if not _density_dirty and _density_bins_count == bins and is_equal_approx(_density_duration, duration):
		return
	_density_bins.clear()
	_density_bins.resize(bins)
	_density_bins_count = bins
	_density_duration = duration
	_density_max_count = 1
	for n in _notes:
		var t := clampf(float(n.get("time", 0.0)), 0.0, duration)
		var idx := clampi(int(floorf((t / duration) * float(bins))), 0, bins - 1)
		_density_bins[idx] += 1
		_density_max_count = maxi(_density_max_count, _density_bins[idx])
	_density_dirty = false


func _position_to_time(pos: Vector2) -> float:
	var duration := _duration()
	if orientation == "vertical":
		return _y_to_time(pos.y, duration)
	return clampf((pos.x / maxf(1.0, size.x)) * duration, 0.0, duration)


func _time_to_x(time_sec: float, duration: float) -> float:
	return clampf(time_sec / duration, 0.0, 1.0) * size.x


func _time_to_y(time_sec: float, duration: float) -> float:
	var ratio := clampf(time_sec / duration, 0.0, 1.0)
	if vertical_direction == "fall_down":
		ratio = 1.0 - ratio
	return ratio * size.y


func _y_to_time(y: float, duration: float) -> float:
	var ratio := clampf(y / maxf(1.0, size.y), 0.0, 1.0)
	if vertical_direction == "fall_down":
		ratio = 1.0 - ratio
	return clampf(ratio * duration, 0.0, duration)


func _format_clock(t: float) -> String:
	var sec := int(floorf(maxf(0.0, t)))
	return "%d:%02d" % [sec / 60, sec % 60]
