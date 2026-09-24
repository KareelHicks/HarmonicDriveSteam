extends "res://scripts/input/GameplayInputProvider.gd"
class_name TouchInputProvider

var _panels: Array[ColorRect] = []
var _active_touches := {}
var _lane_layout: Dictionary = {}
var _lane_rects: Array[Rect2] = []
var _layout_left := 0.0
var _layout_top := 0.0
var _layout_width := 0.0
var _layout_height := 0.0
var _layout_separation := 0.0
var _layout_lane_width := 0.0


func setup_provider(config: Dictionary = {}) -> void:
	super.setup_provider(config)
	_lane_layout = config.get("lane_layout", {})
	set_process_input(true)
	_rebuild()


func _ready() -> void:
	_rebuild()


func set_lane_layout(layout: Dictionary) -> void:
	_lane_layout = layout.duplicate(true)
	_rebuild()


func _rebuild() -> void:
	for child in get_children():
		child.queue_free()
	_panels.clear()
	_lane_rects.clear()
	if lane_count <= 0:
		return

	var left: float = float(_lane_layout.get("left", 0.0))
	var top: float = float(_lane_layout.get("top", 0.0))
	var width: float = float(_lane_layout.get("width", size.x))
	var height: float = float(_lane_layout.get("height", size.y))
	var separation: float = float(_lane_layout.get("separation", 8.0))
	var lane_width: float = (width - separation * float(maxi(0, lane_count - 1))) / float(lane_count)
	var use_custom_layout: bool = width > 0.0 and height > 0.0
	_layout_left = left
	_layout_top = top
	_layout_width = width
	_layout_height = height
	_layout_separation = separation
	_layout_lane_width = lane_width

	for lane in range(lane_count):
		var panel := ColorRect.new()
		panel.name = "LaneTouch%d" % lane
		panel.color = Color(0.2 + (0.1 * lane), 0.6, 1.0, 0.09 if AppState.is_mobile_platform() else 0.0)
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		if use_custom_layout:
			panel.position = Vector2(left + float(lane) * (lane_width + separation), top)
			panel.size = Vector2(lane_width, height)
			_lane_rects.append(Rect2(panel.position, panel.size))
		else:
			panel.anchor_left = float(lane) / float(lane_count)
			panel.anchor_right = float(lane + 1) / float(lane_count)
			panel.anchor_top = 0.0
			panel.anchor_bottom = 1.0
			panel.offset_left = 4.0
			panel.offset_right = -4.0
			panel.offset_top = 4.0
			panel.offset_bottom = -4.0
			var rect_left: float = panel.anchor_left * size.x + panel.offset_left
			var rect_top: float = panel.anchor_top * size.y + panel.offset_top
			var rect_right: float = panel.anchor_right * size.x + panel.offset_right
			var rect_bottom: float = panel.anchor_bottom * size.y + panel.offset_bottom
			_lane_rects.append(Rect2(Vector2(rect_left, rect_top), Vector2(rect_right - rect_left, rect_bottom - rect_top)))
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(panel)
		_panels.append(panel)

	visible = AppState.supports_touch_gameplay()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		var local_position := _local_input_position(event.position)
		var lane: int = _lane_for_position(local_position)
		if event.pressed:
			if lane == -1:
				return
			_active_touches[event.index] = lane
			lane_pressed.emit(lane)
		else:
			if not _active_touches.has(event.index):
				return
			var release_lane := int(_active_touches.get(event.index, lane))
			_active_touches.erase(event.index)
			lane_released.emit(release_lane)
	elif event is InputEventScreenDrag:
		_handle_touch_drag(event.index, _local_input_position(event.position))
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var mouse_lane: int = _lane_for_position(_local_input_position(event.position))
		if event.pressed:
			if mouse_lane == -1:
				return
			_active_touches[-1] = mouse_lane
			lane_pressed.emit(mouse_lane)
		else:
			if not _active_touches.has(-1):
				return
			var release_lane := int(_active_touches.get(-1, mouse_lane))
			_active_touches.erase(-1)
			lane_released.emit(release_lane)
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_handle_touch_drag(-1, _local_input_position(event.position))


func _local_input_position(viewport_position: Vector2) -> Vector2:
	# InputEvent positions are viewport-global, but this provider can live inside
	# an editor runtime holder below a control dock. Convert before lane hit tests.
	return get_global_transform_with_canvas().affine_inverse() * viewport_position


func _handle_touch_drag(pointer_id: int, position: Vector2) -> void:
	if not _active_touches.has(pointer_id):
		return
	var previous_lane := int(_active_touches[pointer_id])
	var lane := _lane_for_position(position)
	if lane == previous_lane:
		return
	lane_released.emit(previous_lane)
	if lane == -1:
		_active_touches.erase(pointer_id)
		return
	_active_touches[pointer_id] = lane
	lane_pressed.emit(lane)


func _lane_for_position(position: Vector2) -> int:
	if _layout_width > 0.0 and _layout_height > 0.0 and lane_count > 0:
		# Keep hit-testing aligned to the visible playfield; small slop for fat-finger input only.
		var horizontal_slop: float = maxf(8.0, _layout_lane_width * 0.06)
		var vertical_slop: float = maxf(20.0, _layout_height * 0.06)
		var left_bound: float = _layout_left - horizontal_slop
		var right_bound: float = _layout_left + _layout_width + horizontal_slop
		var top_bound: float = _layout_top - vertical_slop
		var bottom_bound: float = _layout_top + _layout_height + vertical_slop
		if position.x >= left_bound and position.x <= right_bound and position.y >= top_bound and position.y <= bottom_bound:
			var clamped_x: float = clampf(position.x, _layout_left, _layout_left + _layout_width - 0.001)
			var relative_x: float = clamped_x - _layout_left
			var lane_span: float = _layout_lane_width + _layout_separation
			if lane_span > 0.0:
				return clampi(int(floor(relative_x / lane_span)), 0, lane_count - 1)
	for lane in _lane_rects.size():
		if _lane_rects[lane].has_point(position):
			return lane
	return -1
