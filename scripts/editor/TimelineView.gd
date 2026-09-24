extends Control
class_name TimelineView

signal time_clicked(time_sec: float, lane: int, button_index: int, shift: bool)
signal scrub_requested(time_sec: float)
signal zoom_requested(multiplier: float, at_local_x: float)
signal selection_changed(selected_ids: Array)
signal move_selected_requested(delta_time_sec: float, delta_lane: int)
signal copy_requested()
signal paste_requested(at_time_sec: float)
signal hold_drag_started(time_sec: float, lane: int)
signal hold_drag_ended(time_sec: float, lane: int)
signal context_menu_requested(note_id: int, global_pos: Vector2, time_sec: float, lane: int, selected_ids: Array)
signal scroll_nudge_requested(delta_px: float)

const HDTheme := preload("res://scripts/ui/HDTheme.gd")
const LaneCountResolver := preload("res://scripts/songs/LaneCountResolver.gd")

var px_per_second: float = 200.0
var lane_count := 5

var _grid: GridSnapManager
var _waveform: WaveformRenderer
var _notes: Array[Dictionary] = []

var _cursor_time := 0.0
var _scroll_x := 0.0
var _audio_length := 0.0

var _drag_scrub := false
var _selected_ids: Dictionary = {}
var _drag_selecting := false
var _drag_hold := false
var _hold_drag_lane := 0
var _hold_drag_start_time := 0.0
var _hold_drag_current_time := 0.0
var _hold_place_mode := false
var _drag_moving := false
var _drag_move_started := false
var _drag_start_pos := Vector2.ZERO
var _drag_last_pos := Vector2.ZERO
var _drag_additive := false
var _selection_rect := Rect2()
var _move_accum_time := 0.0
var _move_accum_lane := 0
var _move_start_lane := 0
var _auto_scroll_dir := 0

const AUTO_SCROLL_MARGIN_PX := 42.0
const AUTO_SCROLL_SPEED_PX_PER_SEC := 820.0
const DRAG_MOVE_THRESHOLD_PX := 6.0
const EDITOR_NOTE_HEIGHT_SCALE := 0.40
const EDITOR_NOTE_CORNER_RADIUS := 5


func _visible_width() -> float:
	var parent_control: Control = get_parent() as Control
	if parent_control == null:
		return size.x
	return maxf(1.0, parent_control.size.x)


func attach(grid: GridSnapManager, waveform: WaveformRenderer) -> void:
	_grid = grid
	_waveform = waveform
	if _grid != null:
		_grid.snap_changed.connect(queue_redraw)
		_grid.tempo_changed.connect(queue_redraw)
	if _waveform != null:
		_waveform.waveform_ready.connect(queue_redraw)


func set_hold_place_mode(enabled: bool) -> void:
	_hold_place_mode = enabled


func set_lane_count(count: int) -> void:
	lane_count = LaneCountResolver.clamp_lane_count(count)
	queue_redraw()


func set_notes(notes: Array[Dictionary]) -> void:
	_notes = notes.duplicate(true)
	_update_min_size()
	queue_redraw()


func set_selected_ids(ids: Array[int]) -> void:
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


func set_scroll_x(scroll_x: float) -> void:
	_scroll_x = maxf(0.0, scroll_x)
	queue_redraw()


func set_audio_length(length_sec: float) -> void:
	_audio_length = maxf(0.0, length_sec)
	_update_min_size()
	queue_redraw()


func set_zoom(pxps: float) -> void:
	px_per_second = clampf(pxps, 40.0, 1200.0)
	_update_min_size()
	queue_redraw()


func time_to_x(time_sec: float) -> float:
	return time_sec * px_per_second


func x_to_time(x: float) -> float:
	return maxf(0.0, x / px_per_second)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	_update_min_size()
	set_process(true)


func _process(delta: float) -> void:
	if not _drag_moving or not _drag_move_started:
		_auto_scroll_dir = 0
		return
	var local_x := get_local_mouse_position().x
	var w := _visible_width()
	var visible_left := _scroll_x
	var visible_right := _scroll_x + w
	if local_x < visible_left + AUTO_SCROLL_MARGIN_PX:
		_auto_scroll_dir = -1
	elif local_x > visible_right - AUTO_SCROLL_MARGIN_PX:
		_auto_scroll_dir = 1
	else:
		_auto_scroll_dir = 0
	if _auto_scroll_dir != 0:
		scroll_nudge_requested.emit(float(_auto_scroll_dir) * AUTO_SCROLL_SPEED_PX_PER_SEC * delta)


func _update_min_size() -> void:
	var length := maxf(_audio_length, _guess_last_note_time() + 4.0)
	custom_minimum_size = Vector2(maxf(1200.0, length * px_per_second), 520.0)


func _guess_last_note_time() -> float:
	var last := 0.0
	for n in _notes:
		last = maxf(last, float(n.get("time", 0.0)) + float(n.get("length", 0.0)))
	return last


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			zoom_requested.emit(1.12, mb.position.x)
			accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			zoom_requested.emit(1.0 / 1.12, mb.position.x)
			accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			_drag_scrub = mb.pressed
			accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_drag_start_pos = mb.position
			_drag_last_pos = mb.position
			_drag_additive = mb.shift_pressed
			var time_sec := x_to_time(mb.position.x)
			# Ruler/waveform clicks: seek only (do not place notes).
			if _ruler_rect().has_point(mb.position) or _waveform_rect().has_point(mb.position):
				scrub_requested.emit(time_sec)
				accept_event()
				return
			# Chart area: either select a note or begin selection/placement.
			if _lanes_rect().has_point(mb.position):
				var hit := _hit_test_note(mb.position)
				if hit >= 0:
					# If clicking an already-selected note (without Shift), start moving the existing selection.
					if _selected_ids.has(hit) and not mb.shift_pressed and _selected_ids.size() > 0:
						_drag_moving = true
						_drag_move_started = false
						_auto_scroll_dir = 0
						_move_accum_time = 0.0
						_move_accum_lane = 0
						_move_start_lane = _lane_at_y(_drag_start_pos.y)
						# Seek without changing selection.
						scrub_requested.emit(time_sec)
					else:
						_toggle_select_id(hit, mb.shift_pressed)
						# Selecting a note should seek, not place.
						scrub_requested.emit(time_sec)
				else:
					# sustain placement: click/drag to set hold length.
					var wants_hold_drag := mb.shift_pressed or _hold_place_mode
					# Allow marquee selection while in hold mode by holding Cmd/Ctrl.
					var wants_selection := mb.ctrl_pressed or mb.meta_pressed
					if wants_hold_drag and not wants_selection:
						_drag_hold = true
						_hold_drag_lane = _lane_at_y(mb.position.y)
						_hold_drag_start_time = time_sec
						_hold_drag_current_time = time_sec
						hold_drag_started.emit(time_sec, _hold_drag_lane)
					else:
						# Start drag selection; if it becomes a click (no drag), we'll place on release.
						_drag_selecting = true
						_selection_rect = Rect2(_drag_start_pos, Vector2.ZERO)
						if not mb.shift_pressed:
							_selected_ids.clear()
							selection_changed.emit([])
				accept_event()
				return
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if _lanes_rect().has_point(mb.position):
				var time_sec := x_to_time(mb.position.x)
				var lane := _lane_at_y(mb.position.y)
				var hit := _hit_test_note(mb.position)
				if hit >= 0 and not _selected_ids.has(hit):
					_selected_ids.clear()
					_selected_ids[hit] = true
					selection_changed.emit(get_selected_ids())
					queue_redraw()
				var ids := get_selected_ids()
				context_menu_requested.emit(hit, get_global_mouse_position(), time_sec, lane, ids)
				accept_event()
				return
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			if _drag_hold:
				_drag_hold = false
				var t := x_to_time(mb.position.x)
				var lane := _hold_drag_lane
				_hold_drag_current_time = t
				hold_drag_ended.emit(t, lane)
				queue_redraw()
				accept_event()
				return
			if _drag_selecting:
				_drag_selecting = false
				var drag_dist := mb.position.distance_to(_drag_start_pos)
				if drag_dist < 6.0:
					# Click in chart area (empty): place a note.
					if _lanes_rect().has_point(mb.position):
						var t := x_to_time(mb.position.x)
						var lane := _lane_at_y(mb.position.y)
						time_clicked.emit(t, lane, MOUSE_BUTTON_LEFT, mb.shift_pressed)
				else:
					_apply_selection_rect(_selection_rect, _drag_additive)
				_selection_rect = Rect2()
				queue_redraw()
				accept_event()
				return
			if _drag_moving:
				_drag_moving = false
				_drag_move_started = false
				_auto_scroll_dir = 0
				if _move_accum_time != 0.0 or _move_accum_lane != 0:
					move_selected_requested.emit(_move_accum_time, _move_accum_lane)
				_move_accum_time = 0.0
				_move_accum_lane = 0
				accept_event()
				return
	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event
		if _drag_scrub:
			var t := x_to_time(mm.position.x)
			scrub_requested.emit(t)
			accept_event()
			return
		if _drag_hold:
			_hold_drag_current_time = x_to_time(mm.position.x)
			queue_redraw()
			accept_event()
			return
		if _drag_selecting:
			_drag_last_pos = mm.position
			_selection_rect = Rect2(_drag_start_pos, _drag_last_pos - _drag_start_pos).abs()
			queue_redraw()
			accept_event()
			return
		# Drag move selected notes if starting on a selected note.
		if not _drag_moving and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			# If the initial press was on a selected note, allow moving.
			var hit_id := _hit_test_note(_drag_start_pos)
			if hit_id >= 0 and _selected_ids.has(hit_id) and _lanes_rect().has_point(_drag_start_pos):
				_drag_moving = true
				_drag_move_started = false
				_auto_scroll_dir = 0
				_move_accum_time = 0.0
				_move_accum_lane = 0
				_move_start_lane = _lane_at_y(_drag_start_pos.y)
		if _drag_moving:
			if not _drag_move_started and mm.position.distance_to(_drag_start_pos) < DRAG_MOVE_THRESHOLD_PX:
				accept_event()
				return
			_drag_move_started = true
			var dt := (mm.position.x - _drag_last_pos.x) / px_per_second
			_move_accum_time += dt
			var lane_now := _lane_at_y(mm.position.y)
			var lane_prev := _lane_at_y(_drag_last_pos.y)
			_move_accum_lane += (lane_now - lane_prev)
			_drag_last_pos = mm.position
			accept_event()
			return

	if event is InputEventKey:
		var k: InputEventKey = event
		if k.pressed and not k.echo:
			if k.keycode == KEY_DELETE or k.keycode == KEY_BACKSPACE:
				# Deletion handled by editor; selection is already tracked.
				# Emit a selection_changed to prompt UI update if needed.
				accept_event()
				return
			if k.ctrl_pressed and k.keycode == KEY_C:
				copy_requested.emit()
				accept_event()
				return
			if k.ctrl_pressed and k.keycode == KEY_V:
				paste_requested.emit(_cursor_time)
				accept_event()
				return


func _lane_at_y(y: float) -> int:
	var lanes_rect := _lanes_rect()
	if not lanes_rect.has_point(Vector2(0.0, y)):
		return clampi(int(floorf(float(lane_count) * 0.5)), 0, lane_count - 1)
	var rel := (y - lanes_rect.position.y) / lanes_rect.size.y
	return clampi(int(floorf(rel * float(lane_count))), 0, lane_count - 1)


func _ruler_rect() -> Rect2:
	return Rect2(Vector2.ZERO, Vector2(size.x, 56.0))


func _waveform_rect() -> Rect2:
	return Rect2(Vector2(0.0, 56.0), Vector2(size.x, 110.0))


func _lanes_rect() -> Rect2:
	return Rect2(Vector2(0.0, 56.0 + 110.0), Vector2(size.x, size.y - (56.0 + 110.0)))


func _draw() -> void:
	var palette := HDTheme.theme_palette("theme_neon")
	draw_rect(Rect2(Vector2.ZERO, size), (palette["background"] as Color), true)

	# Hold placement preview.
	if _drag_hold:
		var lanes_rect := _lanes_rect()
		var lane_h := lanes_rect.size.y / float(lane_count)
		var y0 := lanes_rect.position.y + lane_h * float(_hold_drag_lane)
		var h := lane_h
		var x0 := time_to_x(_hold_drag_start_time)
		var x1 := time_to_x(_hold_drag_current_time)
		if x1 < x0:
			var tmp := x0
			x0 = x1
			x1 = tmp
		var preview_h := maxf(4.0, h * EDITOR_NOTE_HEIGHT_SCALE)
		var rect := Rect2(Vector2(x0, y0 + (h - preview_h) * 0.5), Vector2(maxf(6.0, x1 - x0), preview_h))
		_draw_rounded_box(rect, Color(0.2, 0.9, 0.9, 0.22), Color(0.2, 0.9, 0.9, 0.60), 2.0)

	_draw_ruler(palette)
	_draw_waveform(palette)
	_draw_grid_and_notes(palette)
	_draw_cursor(palette)
	_draw_selection_overlay(palette)


func _draw_ruler(palette: Dictionary) -> void:
	var view_w := _visible_width()
	var rect := Rect2(Vector2(_scroll_x, 0.0), Vector2(view_w, 56.0))
	draw_rect(rect, (palette["gutter"] as Color) * Color(1, 1, 1, 0.75), true)
	var grid_col: Color = palette["grid"]
	var rail: Color = palette["rail"]

	var start_t := x_to_time(_scroll_x)
	var end_t := x_to_time(_scroll_x + view_w)
	var major_step := 1.0
	var minor_step := 0.25
	if _grid != null:
		major_step = _grid.seconds_per_beat()
		minor_step = _grid.seconds_per_step()

	var first_major := floorf(start_t / major_step) * major_step
	for t in _frange(first_major, end_t + major_step, major_step):
		var x := time_to_x(t)
		draw_line(Vector2(x, rect.position.y + 10.0), Vector2(x, rect.position.y + rect.size.y), rail * Color(1, 1, 1, 0.55), 2.0)
		var label := _format_time(t)
		draw_string(get_theme_default_font(), Vector2(x + 6.0, rect.position.y + 34.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, HDTheme.primary_text())

	var first_minor := floorf(start_t / minor_step) * minor_step
	for t2 in _frange(first_minor, end_t + minor_step, minor_step):
		var x2 := time_to_x(t2)
		draw_line(Vector2(x2, rect.position.y + 40.0), Vector2(x2, rect.position.y + rect.size.y), grid_col, 1.0)


func _draw_waveform(palette: Dictionary) -> void:
	var view_w := _visible_width()
	var rect := Rect2(Vector2(_scroll_x, 56.0), Vector2(view_w, 110.0))
	draw_rect(rect, (palette["background_top"] as Color) * Color(1, 1, 1, 0.55), true)
	var center_y := rect.position.y + rect.size.y * 0.5
	var wave_col: Color = (palette["rail"] as Color) * Color(1, 1, 1, 0.22)

	if _waveform == null or not _waveform.is_ready():
		draw_line(Vector2(rect.position.x, center_y), Vector2(rect.position.x + rect.size.x, center_y), wave_col, 1.0)
		if _waveform != null and not _waveform.unsupported_reason().is_empty():
			draw_string(get_theme_default_font(), Vector2(rect.position.x + 14.0, rect.position.y + 28.0), _waveform.unsupported_reason(), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, HDTheme.TERTIARY)
		return

	var start_px := int(floorf(_scroll_x))
	var end_px := int(ceilf(_scroll_x + view_w))
	for px in range(start_px, end_px):
		var t := x_to_time(float(px))
		var peak := _waveform.peak_at_time_interpolated(t)
		var h := peak * (rect.size.y * 0.46)
		draw_line(Vector2(float(px), center_y - h), Vector2(float(px), center_y + h), wave_col, 1.0)


func _draw_grid_and_notes(palette: Dictionary) -> void:
	var view_w := _visible_width()
	var rect := Rect2(Vector2(_scroll_x, 56.0 + 110.0), Vector2(view_w, size.y - (56.0 + 110.0)))
	draw_rect(rect, (palette["background_bottom"] as Color) * Color(1, 1, 1, 0.65), true)
	var grid_col: Color = palette["grid"]

	# Lane separators
	for l in range(1, lane_count):
		var y := rect.position.y + (float(l) / float(lane_count)) * rect.size.y
		draw_line(Vector2(0.0, y), Vector2(size.x, y), grid_col, 1.0)

	# Vertical grid lines
	var start_t := x_to_time(_scroll_x)
	var end_t := x_to_time(_scroll_x + view_w)
	var minor_step := 0.25
	if _grid != null:
		minor_step = _grid.seconds_per_step()
	var first_minor := floorf(start_t / minor_step) * minor_step
	for t in _frange(first_minor, end_t + minor_step, minor_step):
		var x := time_to_x(t)
		draw_line(Vector2(x, rect.position.y), Vector2(x, rect.position.y + rect.size.y), grid_col, 1.0)

	# Notes
	for n in _notes:
		var lane := int(n.get("lane", 0))
		if lane < 0 or lane >= lane_count:
			continue
		var t0 := float(n.get("time", 0.0))
		var t1 := t0 + float(n.get("length", 0.0))
		if t0 > end_t + 1.0 or t1 < start_t - 1.0:
			continue
		var x0 := time_to_x(t0)
		var x1 := time_to_x(t1)
		var lane_y0 := rect.position.y + (float(lane) / float(lane_count)) * rect.size.y
		var lane_y1 := rect.position.y + (float(lane + 1) / float(lane_count)) * rect.size.y
		var lane_h := lane_y1 - lane_y0
		var note_h := maxf(4.0, (lane_h - 12.0) * EDITOR_NOTE_HEIGHT_SCALE)
		var note_y := lane_y0 + (lane_h - note_h) * 0.5
		var note_rect := Rect2(Vector2(x0 - 7.0, note_y), Vector2(14.0, note_h))
		var col := HDTheme.lane_color(palette, lane)
		var is_selected := _selected_ids.has(int(n.get("id", -1)))

		if str(n.get("type", "tap")) == "hold":
			var body_h := maxf(4.0, (lane_h - 20.0) * EDITOR_NOTE_HEIGHT_SCALE)
			var body_rect := Rect2(Vector2(x0, lane_y0 + (lane_h - body_h) * 0.5), Vector2(maxf(6.0, x1 - x0), body_h))
			_draw_rounded_box(body_rect, col * Color(1, 1, 1, 0.20), col * Color(1, 1, 1, 0.42), 2.0)
			if is_selected:
				_draw_rounded_box(body_rect.grow(2.0), Color.TRANSPARENT, HDTheme.CYAN * Color(1, 1, 1, 0.55), 2.0, false)
		_draw_rounded_box(note_rect, col * Color(1, 1, 1, 0.88), col * Color(1, 1, 1, 1.0), 2.0)
		if is_selected:
			_draw_rounded_box(note_rect.grow(3.0), Color.TRANSPARENT, HDTheme.CYAN, 2.0, false)


func _draw_cursor(palette: Dictionary) -> void:
	var x := time_to_x(_cursor_time)
	var rail: Color = palette["rail"]
	draw_line(Vector2(x, 0.0), Vector2(x, size.y), rail * Color(1, 1, 1, 0.92), 2.0)


func _format_time(t: float) -> String:
	var sec := int(floorf(t))
	var ms := int(roundf((t - float(sec)) * 1000.0))
	return "%d.%03d" % [sec, ms]


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


func _hit_test_note(local_pos: Vector2) -> int:
	if not _lanes_rect().has_point(local_pos):
		return -1
	var lane := _lane_at_y(local_pos.y)
	var start_t := x_to_time(_scroll_x)
	var end_t := x_to_time(_scroll_x + _visible_width())
	for n in _notes:
		if int(n.get("lane", -1)) != lane:
			continue
		var t0 := float(n.get("time", 0.0))
		var t1 := t0 + float(n.get("length", 0.0))
		if t0 > end_t + 1.0 or t1 < start_t - 1.0:
			continue
		var x0 := time_to_x(t0)
		var x1 := time_to_x(t1)
		var lanes_rect := _lanes_rect()
		var lane_y0 := lanes_rect.position.y + (float(lane) / float(lane_count)) * lanes_rect.size.y
		var lane_y1 := lanes_rect.position.y + (float(lane + 1) / float(lane_count)) * lanes_rect.size.y
		var head_rect := Rect2(Vector2(x0 - 8.0, lane_y0 + 4.0), Vector2(16.0, (lane_y1 - lane_y0) - 8.0))
		if head_rect.has_point(local_pos):
			return int(n.get("id", -1))
		if str(n.get("type", "tap")) == "hold":
			var body_rect := Rect2(Vector2(x0, lane_y0 + 10.0), Vector2(maxf(6.0, x1 - x0), (lane_y1 - lane_y0) - 20.0))
			if body_rect.has_point(local_pos):
				return int(n.get("id", -1))
	return -1


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
	if rect.size.length() < 2.0:
		return
	var lanes_rect := _lanes_rect()
	var clipped := rect.intersection(lanes_rect)
	if clipped.size.x <= 0.0 or clipped.size.y <= 0.0:
		return
	if not additive:
		_selected_ids.clear()
	for n in _notes:
		var lane := int(n.get("lane", -1))
		if lane < 0 or lane >= lane_count:
			continue
		var t0 := float(n.get("time", 0.0))
		var t1 := t0 + float(n.get("length", 0.0))
		var x0 := time_to_x(t0)
		var x1 := time_to_x(t1)
		var lane_y0 := lanes_rect.position.y + (float(lane) / float(lane_count)) * lanes_rect.size.y
		var lane_y1 := lanes_rect.position.y + (float(lane + 1) / float(lane_count)) * lanes_rect.size.y
		var note_rect := Rect2(Vector2(x0 - 8.0, lane_y0 + 4.0), Vector2(maxf(16.0, (x1 - x0) + 8.0), (lane_y1 - lane_y0) - 8.0))
		if clipped.intersects(note_rect):
			var id := int(n.get("id", -1))
			if id >= 0:
				_selected_ids[id] = true
	selection_changed.emit(get_selected_ids())
	queue_redraw()


func _draw_selection_overlay(palette: Dictionary) -> void:
	if _drag_selecting and _selection_rect.size.length() > 2.0:
		var r := _selection_rect.abs()
		draw_rect(r, HDTheme.CYAN * Color(1, 1, 1, 0.10), true)
		draw_rect(r, HDTheme.CYAN * Color(1, 1, 1, 0.65), false, 2.0)


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
