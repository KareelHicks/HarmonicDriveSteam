extends Node
class_name InertialScrollController

const DRAG_THRESHOLD := 14.0
const STOP_SPEED := 24.0
const FRICTION := 10.0
const MAX_SPEED := 4200.0
const MOUSE_POINTER_ID := -100

var scroll_container: ScrollContainer
var content_root: Control

var _pointer_active := false
var _pointer_id := -1
var _dragging := false
var _press_position := Vector2.ZERO
var _last_position := Vector2.ZERO
var _last_motion_usec := 0
var _velocity := 0.0


static func install(target: ScrollContainer, content: Control = null) -> InertialScrollController:
	for child in target.get_children():
		if child is InertialScrollController:
			var existing: InertialScrollController = child
			existing.scroll_container = target
			existing.content_root = content
			return existing
	var controller := InertialScrollController.new()
	controller.name = "InertialScrollController"
	controller.scroll_container = target
	controller.content_root = content
	target.add_child(controller)
	return controller


func _ready() -> void:
	set_process_input(true)
	set_process(true)


func _input(event: InputEvent) -> void:
	if scroll_container == null or not is_instance_valid(scroll_container):
		return
	if not scroll_container.is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event
		if touch.pressed:
			if _is_pointer_inside(touch.position):
				_begin_drag(touch.index, touch.position)
		elif _pointer_active and _pointer_id == touch.index:
			_end_drag()
		return
	if event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event
		if _pointer_active and _pointer_id == drag.index:
			_update_drag(drag.position)
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var mouse_button: InputEventMouseButton = event
		if mouse_button.pressed:
			if _is_pointer_inside(mouse_button.position):
				_begin_drag(MOUSE_POINTER_ID, mouse_button.position)
		elif _pointer_active and _pointer_id == MOUSE_POINTER_ID:
			_end_drag()
		return
	if event is InputEventMouseMotion and _pointer_active and _pointer_id == MOUSE_POINTER_ID:
		var mouse_motion: InputEventMouseMotion = event
		_update_drag(mouse_motion.position)


func _process(delta: float) -> void:
	if _dragging or absf(_velocity) < STOP_SPEED:
		if not _dragging:
			_velocity = 0.0
		return
	_scroll_by(_velocity * delta)
	_velocity = move_toward(_velocity, 0.0, absf(_velocity) * FRICTION * delta)


func _begin_drag(pointer_id: int, position: Vector2) -> void:
	_pointer_active = true
	_pointer_id = pointer_id
	_dragging = false
	_press_position = position
	_last_position = position
	_last_motion_usec = Time.get_ticks_usec()
	_velocity = 0.0
	_set_scroll_suppressed(false)


func _update_drag(position: Vector2) -> void:
	if not _pointer_active:
		return
	var total_delta: Vector2 = position - _press_position
	if not _dragging:
		if absf(total_delta.y) < DRAG_THRESHOLD:
			_last_position = position
			_last_motion_usec = Time.get_ticks_usec()
			return
		if absf(total_delta.y) < absf(total_delta.x):
			return
		_dragging = true
		_set_scroll_suppressed(true)
	var now_usec: int = Time.get_ticks_usec()
	var delta_pixels: float = _last_position.y - position.y
	var delta_usec: int = maxi(1, now_usec - _last_motion_usec)
	var delta_seconds: float = float(delta_usec) / 1000000.0
	_scroll_by(delta_pixels)
	_velocity = clampf(delta_pixels / delta_seconds, -MAX_SPEED, MAX_SPEED)
	_last_position = position
	_last_motion_usec = now_usec


func _end_drag() -> void:
	_pointer_active = false
	_pointer_id = -1
	_dragging = false
	_set_scroll_suppressed(false)


func _scroll_by(delta_pixels: float) -> void:
	if scroll_container == null or scroll_container.get_v_scroll_bar() == null:
		return
	var scrollbar: VScrollBar = scroll_container.get_v_scroll_bar()
	var next_value: float = clampf(
		scroll_container.scroll_vertical + delta_pixels,
		scrollbar.min_value,
		scrollbar.max_value
	)
	scroll_container.scroll_vertical = int(round(next_value))


func _is_pointer_inside(position: Vector2) -> bool:
	return scroll_container.get_global_rect().has_point(position)


func _set_scroll_suppressed(suppressed: bool) -> void:
	if content_root == null or not is_instance_valid(content_root):
		return
	_apply_scroll_suppression(content_root, suppressed)


func _apply_scroll_suppression(node: Node, suppressed: bool) -> void:
	if node.has_method("set_touch_scroll_suppressed"):
		node.call("set_touch_scroll_suppressed", suppressed)
	for child in node.get_children():
		_apply_scroll_suppression(child, suppressed)
