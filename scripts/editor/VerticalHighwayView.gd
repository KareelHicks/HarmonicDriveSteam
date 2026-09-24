extends Control
class_name VerticalHighwayView

signal time_clicked(time_sec: float, lane: int, button_index: int, shift: bool)
signal scrub_requested(time_sec: float)
signal zoom_requested(multiplier: float, at_local_y: float)
signal selection_changed(selected_ids: Array)
signal move_selected_requested(delta_time_sec: float, delta_lane: int)
signal copy_requested()
signal paste_requested(at_time_sec: float)
signal hold_drag_started(time_sec: float, lane: int)
signal hold_drag_ended(time_sec: float, lane: int)
signal context_menu_requested(note_id: int, global_pos: Vector2, time_sec: float, lane: int, selected_ids: Array)
signal scroll_nudge_requested(delta_px: float)
signal delete_requested(time_sec: float, lane: int)

const HDTheme := preload("res://scripts/ui/HDTheme.gd")
const LaneCountResolver := preload("res://scripts/songs/LaneCountResolver.gd")

const TOP_PADDING := 120.0
const BOTTOM_PADDING := 160.0
const SIDE_PADDING := 52.0
const MIN_WIDTH := 520.0
const MIN_HEIGHT := 300.0
const AUTO_SCROLL_MARGIN_PX := 46.0
const AUTO_SCROLL_SPEED_PX_PER_SEC := 760.0
const WHEEL_SCROLL_PX := 90.0
const WAVEFORM_SAMPLE_STEP_PX := 4
const WAVEFORM_VISIBLE_LANES := 3.0
const VIEW_MODE_TIMELINE_ZOOM := "timeline_zoom"
const VIEW_MODE_GAMEPLAY_PREVIEW := "gameplay_preview"
const EDITOR_NOTE_HEIGHT_SCALE := 0.40
const EDITOR_NOTE_HEAD_HEIGHT := 16.0 * EDITOR_NOTE_HEIGHT_SCALE
const EDITOR_NOTE_CORNER_RADIUS := 5

var px_per_second := 80.0
var lane_count := 5
var vertical_direction := "fall_down"
var active_tool := "tap"
var track_width_scale := 0.72
var view_mode := VIEW_MODE_TIMELINE_ZOOM
var gameplay_approach_time := 0.6

var _grid: GridSnapManager
var _waveform: WaveformRenderer
var _notes: Array[Dictionary] = []
var _selected_ids: Dictionary = {}
var _cached_duration := 1.0
var _cursor_time := 0.0
var _audio_length := 0.0
var _scroll_y := 0.0

var _drag_scrub := false
var _drag_selecting := false
var _drag_hold := false
var _drag_moving := false
var _drag_start_pos := Vector2.ZERO
var _drag_last_pos := Vector2.ZERO
var _selection_rect := Rect2()
var _hold_drag_lane := 0
var _hold_drag_start_time := 0.0
var _hold_drag_current_time := 0.0
var _move_accum_time := 0.0
var _move_accum_lane := 0
var _auto_scroll_dir := 0


func attach(grid: GridSnapManager, waveform: WaveformRenderer) -> void:
	_grid = grid
	_waveform = waveform
	if _grid != null:
		_grid.snap_changed.connect(queue_redraw)
		_grid.tempo_changed.connect(queue_redraw)
	if _waveform != null:
		_waveform.waveform_ready.connect(queue_redraw)


func set_notes(notes: Array) -> void:
	_notes.clear()
	for n in notes:
		if n is Dictionary:
			_notes.append((n as Dictionary).duplicate(true))
	_notes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("time", 0.0)) < float(b.get("time", 0.0))
	)
	_recalculate_duration()
	_update_min_size()
	queue_redraw()


func set_lane_count(count: int) -> void:
	lane_count = LaneCountResolver.clamp_lane_count(count)
	queue_redraw()


func set_selected_ids(ids: Array) -> void:
	_selected_ids.clear()
	for id in ids:
		_selected_ids[int(id)] = true
	queue_redraw()


func get_selected_ids() -> Array[int]:
	var out: Array[int] = []
	for k in _selected_ids.keys():
		out.append(int(k))
	out.sort()
	return out


func set_cursor_time(time_sec: float) -> void:
	_cursor_time = maxf(0.0, time_sec)
	queue_redraw()


func set_scroll_y(scroll_y: float) -> void:
	_scroll_y = maxf(0.0, scroll_y)
	queue_redraw()


func set_audio_length(length_sec: float) -> void:
	_audio_length = maxf(0.0, length_sec)
	_recalculate_duration()
	_update_min_size()
	queue_redraw()


func set_zoom(pxps: float) -> void:
	px_per_second = clampf(pxps, 30.0, 2000.0)
	_update_min_size()
	queue_redraw()


func set_view_mode(mode: String) -> void:
	var cleaned := mode.strip_edges().to_lower()
	view_mode = cleaned if cleaned == VIEW_MODE_GAMEPLAY_PREVIEW else VIEW_MODE_TIMELINE_ZOOM
	_update_min_size()
	queue_redraw()


func set_gameplay_approach_time(seconds: float) -> void:
	gameplay_approach_time = maxf(0.05, seconds)
	if view_mode == VIEW_MODE_GAMEPLAY_PREVIEW:
		_update_min_size()
		queue_redraw()


func is_gameplay_preview_mode() -> bool:
	return view_mode == VIEW_MODE_GAMEPLAY_PREVIEW


func gameplay_judgement_line_y() -> float:
	return _visible_height() * 0.86


func set_track_width_scale(value: float) -> void:
	track_width_scale = clampf(value, 0.45, 1.0)
	queue_redraw()


func set_vertical_direction(direction: String) -> void:
	vertical_direction = direction if direction == "rise_up" else "fall_down"
	queue_redraw()


func set_active_tool(tool_id: String) -> void:
	var cleaned := tool_id.strip_edges().to_lower()
	active_tool = cleaned if ["tap", "hold", "select", "erase"].has(cleaned) else "tap"


func time_to_y(time_sec: float) -> float:
	var duration := _duration()
	var track_h := maxf(1.0, duration * _effective_px_per_second())
	var ratio := clampf(time_sec / duration, 0.0, 1.0)
	if vertical_direction == "fall_down":
		ratio = 1.0 - ratio
	return TOP_PADDING + ratio * track_h


func y_to_time(y: float) -> float:
	var duration := _duration()
	var track_h := maxf(1.0, duration * _effective_px_per_second())
	var ratio := clampf((y - TOP_PADDING) / track_h, 0.0, 1.0)
	if vertical_direction == "fall_down":
		ratio = 1.0 - ratio
	return clampf(ratio * duration, 0.0, duration)


func visible_time_window() -> Vector2:
	var parent_control: Control = get_parent() as Control
	var visible_h := maxf(1.0, parent_control.size.y if parent_control != null else size.y)
	var t0 := y_to_time(_scroll_y)
	var t1 := y_to_time(_scroll_y + visible_h)
	return Vector2(minf(t0, t1), maxf(t0, t1))


func content_height() -> float:
	return TOP_PADDING + BOTTOM_PADDING + _duration() * _effective_px_per_second()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	_update_min_size()
	set_process(true)


func _process(delta: float) -> void:
	if not _drag_moving and not _drag_selecting:
		_auto_scroll_dir = 0
		return
	var local_y := get_local_mouse_position().y
	var h := _visible_height()
	if local_y < AUTO_SCROLL_MARGIN_PX:
		_auto_scroll_dir = -1
	elif local_y > h - AUTO_SCROLL_MARGIN_PX:
		_auto_scroll_dir = 1
	else:
		_auto_scroll_dir = 0
	if _auto_scroll_dir != 0:
		scroll_nudge_requested.emit(float(_auto_scroll_dir) * AUTO_SCROLL_SPEED_PX_PER_SEC * delta)
		if _drag_selecting:
			# The scroll signal updates _scroll_y synchronously. Rebuild the marquee
			# in content coordinates so it keeps expanding while the pointer remains
			# above or below the visible chart, even without new mouse-motion events.
			_update_selection_drag(get_local_mouse_position())


func _update_min_size() -> void:
	custom_minimum_size = Vector2(MIN_WIDTH, MIN_HEIGHT)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			if mb.ctrl_pressed or mb.meta_pressed:
				zoom_requested.emit(1.08, mb.position.y)
			else:
				scroll_nudge_requested.emit(-WHEEL_SCROLL_PX)
			accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			if mb.ctrl_pressed or mb.meta_pressed:
				zoom_requested.emit(1.0 / 1.08, mb.position.y)
			else:
				scroll_nudge_requested.emit(WHEEL_SCROLL_PX)
			accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			_drag_scrub = mb.pressed
			accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_handle_left_press(mb)
			return
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			_handle_left_release(mb)
			return
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_handle_right_press(mb)
			return
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event as InputEventMouseMotion)
	elif event is InputEventKey:
		var k: InputEventKey = event
		if k.pressed and not k.echo:
			if (k.ctrl_pressed or k.meta_pressed) and k.keycode == KEY_C:
				copy_requested.emit()
				accept_event()
				return
			if (k.ctrl_pressed or k.meta_pressed) and k.keycode == KEY_V:
				paste_requested.emit(_cursor_time)
				accept_event()
				return


func _handle_left_press(mb: InputEventMouseButton) -> void:
	var content_pos := _content_pos(mb.position)
	_drag_start_pos = content_pos
	_drag_last_pos = content_pos
	var lanes_rect := _lanes_rect()
	if not lanes_rect.has_point(content_pos):
		scrub_requested.emit(y_to_time(content_pos.y))
		accept_event()
		return
	var time_sec := y_to_time(content_pos.y)
	var lane := _lane_at_x(content_pos.x)
	if active_tool == "erase":
		delete_requested.emit(time_sec, lane)
		scrub_requested.emit(time_sec)
		accept_event()
		return
	var hit := _hit_test_note(content_pos)
	if hit >= 0:
		if not _selected_ids.has(hit) or mb.shift_pressed:
			_toggle_select_id(hit, mb.shift_pressed)
		if _selected_ids.has(hit):
			_drag_moving = true
			_move_accum_time = 0.0
			_move_accum_lane = 0
		if not is_gameplay_preview_mode():
			scrub_requested.emit(time_sec)
		accept_event()
		return
	if active_tool == "hold" or mb.shift_pressed:
		_drag_hold = true
		_hold_drag_lane = lane
		_hold_drag_start_time = time_sec
		_hold_drag_current_time = time_sec
		hold_drag_started.emit(time_sec, lane)
	elif active_tool == "select" or mb.ctrl_pressed or mb.meta_pressed:
		_drag_selecting = true
		_selection_rect = Rect2(_drag_start_pos, Vector2.ZERO)
		if not mb.shift_pressed:
			_selected_ids.clear()
			selection_changed.emit([])
	else:
		_drag_selecting = true
		_selection_rect = Rect2(_drag_start_pos, Vector2.ZERO)
		if not mb.shift_pressed:
			_selected_ids.clear()
			selection_changed.emit([])
	accept_event()


func _handle_left_release(mb: InputEventMouseButton) -> void:
	var content_pos := _content_pos(mb.position)
	if _drag_hold:
		_drag_hold = false
		_hold_drag_current_time = y_to_time(content_pos.y)
		hold_drag_ended.emit(_hold_drag_current_time, _hold_drag_lane)
		queue_redraw()
		accept_event()
		return
	if _drag_selecting:
		_update_selection_drag(mb.position)
		_drag_selecting = false
		_auto_scroll_dir = 0
		var drag_dist := content_pos.distance_to(_drag_start_pos)
		if drag_dist < 6.0 and _lanes_rect().has_point(content_pos):
			if active_tool == "tap":
				time_clicked.emit(y_to_time(content_pos.y), _lane_at_x(content_pos.x), MOUSE_BUTTON_LEFT, mb.shift_pressed)
			elif active_tool == "select":
				selection_changed.emit(get_selected_ids())
		else:
			_apply_selection_rect(_selection_rect, mb.shift_pressed)
		_selection_rect = Rect2()
		queue_redraw()
		accept_event()
		return
	if _drag_moving:
		_drag_moving = false
		if not is_equal_approx(_move_accum_time, 0.0) or _move_accum_lane != 0:
			move_selected_requested.emit(_move_accum_time, _move_accum_lane)
		_move_accum_time = 0.0
		_move_accum_lane = 0
		queue_redraw()
		accept_event()
		return


func _handle_right_press(mb: InputEventMouseButton) -> void:
	var content_pos := _content_pos(mb.position)
	if not _lanes_rect().has_point(content_pos):
		return
	var time_sec := y_to_time(content_pos.y)
	var lane := _lane_at_x(content_pos.x)
	var hit := _hit_test_note(content_pos)
	if hit >= 0 and not _selected_ids.has(hit):
		_selected_ids.clear()
		_selected_ids[hit] = true
		selection_changed.emit(get_selected_ids())
		queue_redraw()
	var ids := get_selected_ids()
	context_menu_requested.emit(hit, get_global_mouse_position(), time_sec, lane, ids)
	accept_event()


func _handle_mouse_motion(mm: InputEventMouseMotion) -> void:
	var content_pos := _content_pos(mm.position)
	if _drag_scrub:
		scrub_requested.emit(y_to_time(content_pos.y))
		accept_event()
		return
	if active_tool == "erase" and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and _lanes_rect().has_point(content_pos):
		delete_requested.emit(y_to_time(content_pos.y), _lane_at_x(content_pos.x))
		accept_event()
		return
	if _drag_hold:
		_hold_drag_current_time = y_to_time(content_pos.y)
		queue_redraw()
		accept_event()
		return
	if _drag_selecting:
		_update_selection_drag(mm.position)
		accept_event()
		return
	if _drag_moving:
		var dt := y_to_time(content_pos.y) - y_to_time(_drag_last_pos.y)
		_move_accum_time += dt
		var lane_now := _lane_at_x(content_pos.x)
		var lane_prev := _lane_at_x(_drag_last_pos.x)
		_move_accum_lane += lane_now - lane_prev
		_drag_last_pos = content_pos
		queue_redraw()
		accept_event()


func _update_selection_drag(local_pos: Vector2) -> void:
	_drag_last_pos = _content_pos(local_pos)
	_selection_rect = Rect2(_drag_start_pos, _drag_last_pos - _drag_start_pos).abs()
	queue_redraw()


func _draw() -> void:
	var palette := HDTheme.theme_palette("theme_neon")
	var visible_rect := Rect2(Vector2(0.0, _scroll_y), Vector2(size.x, _visible_height()))
	draw_set_transform(Vector2(0.0, -_scroll_y), 0.0, Vector2.ONE)
	draw_rect(visible_rect, (palette["background"] as Color), true)
	_draw_highway(palette, visible_rect)
	_draw_notes(palette)
	_draw_cursor(palette)
	_draw_drag_overlays()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_highway(palette: Dictionary, visible_rect: Rect2) -> void:
	var lanes_rect := _lanes_rect()
	var clipped := lanes_rect.intersection(visible_rect.grow(2.0))
	draw_rect(clipped, (palette["background_bottom"] as Color) * Color(1, 1, 1, 0.82), true)
	draw_rect(lanes_rect, HDTheme.CARD_STROKE, false, 1.0)
	_draw_waveform(palette, visible_rect, lanes_rect)
	for lane in range(lane_count + 1):
		var x := lanes_rect.position.x + lanes_rect.size.x * (float(lane) / float(lane_count))
		draw_line(Vector2(x, visible_rect.position.y), Vector2(x, visible_rect.position.y + visible_rect.size.y), (palette["grid"] as Color) * Color(1, 1, 1, 1.25), 1.0)
	for lane_label in range(lane_count):
		var lx := lanes_rect.position.x + lanes_rect.size.x * ((float(lane_label) + 0.5) / float(lane_count))
		draw_string(get_theme_default_font(), Vector2(lx - 18.0, visible_rect.position.y + 24.0), "L%d" % [lane_label + 1], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, HDTheme.TERTIARY)
	_draw_snap_lines(palette, visible_rect, lanes_rect)


func _draw_waveform(palette: Dictionary, visible_rect: Rect2, lanes_rect: Rect2) -> void:
	var center_x := lanes_rect.position.x + lanes_rect.size.x * 0.5
	var wave_col := (palette["rail"] as Color) * Color(1, 1, 1, 0.50)
	var screen_top := maxf(0.0, lanes_rect.position.y - _scroll_y)
	var screen_bottom := minf(_visible_height(), lanes_rect.position.y + lanes_rect.size.y - _scroll_y)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if _waveform == null or not _waveform.is_ready():
		draw_line(Vector2(center_x, screen_top), Vector2(center_x, screen_bottom), wave_col, 1.0)
		draw_set_transform(Vector2(0.0, -_scroll_y), 0.0, Vector2.ONE)
		return
	var start_y := int(floorf(screen_top))
	var end_y := int(ceilf(screen_bottom))
	var wave_half_width := lanes_rect.size.x * (minf(WAVEFORM_VISIBLE_LANES, float(lane_count)) / maxf(1.0, float(lane_count))) * 0.5
	for screen_y in range(start_y, end_y, WAVEFORM_SAMPLE_STEP_PX):
		var content_y := float(screen_y) + _scroll_y
		var t := y_to_time(content_y)
		var peak := _waveform.peak_at_time_interpolated(t)
		var w := peak * wave_half_width
		draw_line(Vector2(center_x - w, float(screen_y)), Vector2(center_x + w, float(screen_y)), wave_col, 1.0)
	draw_set_transform(Vector2(0.0, -_scroll_y), 0.0, Vector2.ONE)


func _draw_snap_lines(palette: Dictionary, visible_rect: Rect2, lanes_rect: Rect2) -> void:
	var window := visible_time_window()
	var minor_step := 0.25
	var major_step := 1.0
	var grid_offset := 0.0
	if _grid != null:
		major_step = _grid.seconds_per_beat()
		minor_step = _grid.seconds_per_step()
		grid_offset = _grid.offset
	if minor_step <= 0.0:
		return
	var t := floorf((window.x - grid_offset) / minor_step) * minor_step + grid_offset
	var end_t := window.y + minor_step
	var guard := 0
	while t <= end_t and guard < 20000:
		var y := time_to_y(t)
		if y >= visible_rect.position.y - 2.0 and y <= visible_rect.position.y + visible_rect.size.y + 2.0:
			var beat_pos := 0.0
			if major_step > 0.0:
				beat_pos = fposmod(t - grid_offset, major_step)
			var is_beat := beat_pos < 0.001 or absf(beat_pos - major_step) < 0.001
			var col := (palette["rail"] as Color) * Color(1, 1, 1, 0.45) if is_beat else (palette["grid"] as Color)
			draw_line(Vector2(lanes_rect.position.x, y), Vector2(lanes_rect.position.x + lanes_rect.size.x, y), col, 2.0 if is_beat else 1.0)
			if is_beat:
				draw_string(get_theme_default_font(), Vector2(8.0, y + 4.0), _format_time(t), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, HDTheme.TERTIARY)
		t += minor_step
		guard += 1


func _draw_notes(palette: Dictionary) -> void:
	var lanes_rect := _lanes_rect()
	var visible_rect := Rect2(Vector2(0.0, _scroll_y), Vector2(size.x, _visible_height()))
	var lane_w := lanes_rect.size.x / float(lane_count)
	var window := visible_time_window()
	var time_pad := 48.0 / maxf(1.0, _effective_px_per_second())
	var start_t := maxf(0.0, window.x - time_pad)
	var end_t := window.y + time_pad
	for n in _notes:
		var selected := _selected_ids.has(int(n.get("id", -1)))
		var lane := int(n.get("lane", 0))
		var t0 := float(n.get("time", 0.0))
		if _drag_moving and selected:
			lane = clampi(lane + _move_accum_lane, 0, lane_count - 1)
			t0 = maxf(0.0, t0 + _move_accum_time)
		if lane < 0 or lane >= lane_count:
			continue
		var length := float(n.get("length", 0.0))
		if not _drag_moving and t0 > end_t:
			break
		if t0 + length < start_t:
			continue
		var y0 := time_to_y(t0)
		var y1 := time_to_y(t0 + length)
		if maxf(y0, y1) < visible_rect.position.y - 40.0 or minf(y0, y1) > visible_rect.position.y + visible_rect.size.y + 40.0:
			continue
		var x0 := lanes_rect.position.x + float(lane) * lane_w
		var note_rect := Rect2(Vector2(x0 + lane_w * 0.16, y0 - EDITOR_NOTE_HEAD_HEIGHT * 0.5), Vector2(lane_w * 0.68, EDITOR_NOTE_HEAD_HEIGHT))
		var col := HDTheme.lane_color(palette, lane)
		if str(n.get("type", "tap")) == "hold":
			var top := minf(y0, y1)
			var body := Rect2(Vector2(x0 + lane_w * 0.35, top), Vector2(lane_w * 0.30, maxf(8.0, absf(y1 - y0))))
			_draw_rounded_box(body, col * Color(1, 1, 1, 0.22), col * Color(1, 1, 1, 0.55), 2.0)
			if selected:
				_draw_rounded_box(body.grow(3.0), Color.TRANSPARENT, HDTheme.CYAN * Color(1, 1, 1, 0.65), 2.0, false)
		_draw_rounded_box(note_rect, col * Color(1, 1, 1, 0.92), col, 2.0)
		if selected:
			_draw_rounded_box(note_rect.grow(4.0), Color.TRANSPARENT, HDTheme.CYAN, 2.0, false)


func _draw_cursor(palette: Dictionary) -> void:
	var lanes_rect := _lanes_rect()
	var y := time_to_y(_cursor_time)
	draw_line(Vector2(lanes_rect.position.x - 18.0, y), Vector2(lanes_rect.position.x + lanes_rect.size.x + 18.0, y), palette["rail"], 3.0)
	draw_string(get_theme_default_font(), Vector2(lanes_rect.position.x + lanes_rect.size.x + 24.0, y + 5.0), "JUDGEMENT", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, HDTheme.SECONDARY)


func _draw_drag_overlays() -> void:
	if _drag_hold:
		var lanes_rect := _lanes_rect()
		var lane_w := lanes_rect.size.x / float(lane_count)
		var x := lanes_rect.position.x + float(_hold_drag_lane) * lane_w + lane_w * 0.28
		var y0 := time_to_y(_hold_drag_start_time)
		var y1 := time_to_y(_hold_drag_current_time)
		var rect := Rect2(Vector2(x, minf(y0, y1)), Vector2(lane_w * 0.44, maxf(8.0, absf(y1 - y0))))
		_draw_rounded_box(rect, HDTheme.CYAN * Color(1, 1, 1, 0.18), HDTheme.CYAN * Color(1, 1, 1, 0.70), 2.0)
	if _drag_selecting and _selection_rect.size.length() > 2.0:
		var r := _selection_rect.abs()
		draw_rect(r, HDTheme.CYAN * Color(1, 1, 1, 0.10), true)
		draw_rect(r, HDTheme.CYAN * Color(1, 1, 1, 0.65), false, 2.0)


func _draw_rounded_box(rect: Rect2, fill: Color, border: Color = Color.TRANSPARENT, border_width: float = 0.0, draw_center: bool = true) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.draw_center = draw_center
	style.corner_radius_top_left = EDITOR_NOTE_CORNER_RADIUS
	style.corner_radius_top_right = EDITOR_NOTE_CORNER_RADIUS
	style.corner_radius_bottom_left = EDITOR_NOTE_CORNER_RADIUS
	style.corner_radius_bottom_right = EDITOR_NOTE_CORNER_RADIUS
	if border_width > 0.0:
		var width := maxi(1, int(roundf(border_width)))
		style.border_color = border
		style.border_width_left = width
		style.border_width_top = width
		style.border_width_right = width
		style.border_width_bottom = width
	draw_style_box(style, rect)


func _lane_at_x(x: float) -> int:
	var lanes_rect := _lanes_rect()
	if not lanes_rect.has_point(Vector2(x, lanes_rect.position.y + 1.0)):
		return clampi(int(floorf(float(lane_count) * 0.5)), 0, lane_count - 1)
	var rel := (x - lanes_rect.position.x) / lanes_rect.size.x
	return clampi(int(floorf(rel * float(lane_count))), 0, lane_count - 1)


func _hit_test_note(local_pos: Vector2) -> int:
	if not _lanes_rect().has_point(local_pos):
		return -1
	var lane := _lane_at_x(local_pos.x)
	for n in _notes:
		if int(n.get("lane", -1)) != lane:
			continue
		var rect := _note_hit_rect(n)
		if rect.has_point(local_pos):
			return int(n.get("id", -1))
	return -1


func _note_hit_rect(note: Dictionary) -> Rect2:
	var lanes_rect := _lanes_rect()
	var lane_w := lanes_rect.size.x / float(lane_count)
	var lane := clampi(int(note.get("lane", 0)), 0, lane_count - 1)
	var x0 := lanes_rect.position.x + float(lane) * lane_w
	var y0 := time_to_y(float(note.get("time", 0.0)))
	var y1 := time_to_y(float(note.get("time", 0.0)) + float(note.get("length", 0.0)))
	var top := minf(y0, y1) - 10.0
	var bottom := maxf(y0, y1) + 10.0
	return Rect2(Vector2(x0 + lane_w * 0.12, top), Vector2(lane_w * 0.76, maxf(22.0, bottom - top)))


func _toggle_select_id(note_id: int, additive: bool) -> void:
	if not additive:
		_selected_ids.clear()
	if _selected_ids.has(note_id) and additive:
		_selected_ids.erase(note_id)
	else:
		_selected_ids[note_id] = true
	selection_changed.emit(get_selected_ids())
	queue_redraw()


func _apply_selection_rect(rect: Rect2, additive: bool) -> void:
	var clipped := rect.abs().intersection(_lanes_rect())
	if clipped.size.x <= 0.0 or clipped.size.y <= 0.0:
		return
	if not additive:
		_selected_ids.clear()
	for n in _notes:
		var id := int(n.get("id", -1))
		if id >= 0 and clipped.intersects(_note_hit_rect(n)):
			_selected_ids[id] = true
	selection_changed.emit(get_selected_ids())
	queue_redraw()


func _lanes_rect() -> Rect2:
	var available_w := maxf(320.0, size.x - (SIDE_PADDING * 2.0))
	var lane_w := clampf(available_w * track_width_scale, 280.0, available_w)
	var x := (size.x - lane_w) * 0.5
	var lane_h := maxf(_visible_height(), content_height() - TOP_PADDING)
	return Rect2(Vector2(x, TOP_PADDING * 0.5), Vector2(lane_w, lane_h))


func _content_pos(local_pos: Vector2) -> Vector2:
	return Vector2(local_pos.x, local_pos.y + _scroll_y)


func _visible_height() -> float:
	var parent_control: Control = get_parent() as Control
	return maxf(1.0, parent_control.size.y if parent_control != null else size.y)


func _effective_px_per_second() -> float:
	if view_mode != VIEW_MODE_GAMEPLAY_PREVIEW:
		return px_per_second
	var hit_line := gameplay_judgement_line_y()
	var spawn_y := -_gameplay_note_height() * 0.5
	return maxf(1.0, (hit_line - spawn_y) / maxf(0.05, gameplay_approach_time))


func _gameplay_note_height() -> float:
	return maxf(22.0, _visible_height() * 0.028)


func _duration() -> float:
	return _cached_duration


func _recalculate_duration() -> void:
	var last := _audio_length
	for n in _notes:
		last = maxf(last, float(n.get("time", 0.0)) + float(n.get("length", 0.0)) + 4.0)
	_cached_duration = maxf(1.0, last)


func _format_time(t: float) -> String:
	var sec := int(floorf(maxf(0.0, t)))
	var ms := int(roundf((t - float(sec)) * 1000.0))
	return "%d.%03d" % [sec, ms]


func _frange(start_v: float, end_v: float, step: float) -> Array[float]:
	var out: Array[float] = []
	if step <= 0.0:
		return out
	var v := start_v
	var guard := 0
	while v <= end_v and guard < 20000:
		out.append(v)
		v += step
		guard += 1
	return out
