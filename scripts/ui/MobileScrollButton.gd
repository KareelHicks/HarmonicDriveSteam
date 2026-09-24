extends Button
class_name MobileScrollButton

const TAP_DRAG_THRESHOLD := 22.0

var _pointer_active := false
var _press_position := Vector2.ZERO
var _suppress_release := false


func _ready() -> void:
	if AppState.is_mobile_platform():
		mouse_filter = Control.MOUSE_FILTER_PASS
		action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE


func _gui_input(event: InputEvent) -> void:
	if not AppState.is_mobile_platform():
		return

	if event is InputEventScreenTouch:
		if event.pressed:
			_begin_pointer(event.position)
		else:
			_end_pointer()
		return

	if event is InputEventScreenDrag:
		_update_drag(event.position)
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin_pointer(event.position)
		else:
			_end_pointer()
		return

	if event is InputEventMouseMotion:
		_update_drag(event.position)


func _begin_pointer(position: Vector2) -> void:
	_pointer_active = true
	_press_position = position
	_suppress_release = false


func _update_drag(position: Vector2) -> void:
	if not _pointer_active:
		return
	if position.distance_to(_press_position) >= TAP_DRAG_THRESHOLD:
		_suppress_release = true
		set_pressed_no_signal(false)
		release_focus()


func _end_pointer() -> void:
	if _suppress_release:
		set_pressed_no_signal(false)
		release_focus()
	_pointer_active = false
	_suppress_release = false
