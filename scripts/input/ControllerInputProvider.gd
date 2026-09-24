extends "res://scripts/input/GameplayInputProvider.gd"
class_name ControllerInputProvider

const RELEASE_HYSTERESIS := 0.18

var _pressed_lanes: Dictionary = {}


func _ready() -> void:
	set_process_unhandled_input(true)


func setup_provider(config: Dictionary = {}) -> void:
	super.setup_provider(config)
	_pressed_lanes.clear()
	for lane in range(lane_count):
		_pressed_lanes[lane] = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventJoypadButton:
		_handle_button_event(event as InputEventJoypadButton)
	elif event is InputEventJoypadMotion:
		_handle_motion_event(event as InputEventJoypadMotion)



func _handle_button_event(event: InputEventJoypadButton) -> void:
	for lane in range(lane_count):
		var action := "lane_%d" % lane
		if event.is_action_pressed(action):
			_set_lane_pressed(lane, true)
		elif event.is_action_released(action):
			_set_lane_pressed(lane, false)


func _handle_motion_event(event: InputEventJoypadMotion) -> void:
	for lane in range(lane_count):
		var action := "lane_%d" % lane
		var current_pressed := bool(_pressed_lanes.get(lane, false))
		var target_pressed := current_pressed
		for mapped_event in InputMap.action_get_events(action):
			if mapped_event is not InputEventJoypadMotion:
				continue
			var mapped_motion: InputEventJoypadMotion = mapped_event as InputEventJoypadMotion
			if mapped_motion.axis != event.axis:
				continue
			var target_value: float = mapped_motion.axis_value
			var press_threshold: float = absf(target_value)
			if target_value < 0.0:
				if current_pressed:
					target_pressed = event.axis_value <= -(press_threshold - RELEASE_HYSTERESIS)
				else:
					target_pressed = event.axis_value <= -press_threshold
			else:
				if current_pressed:
					target_pressed = event.axis_value >= press_threshold - RELEASE_HYSTERESIS
				else:
					target_pressed = event.axis_value >= press_threshold
			break
		if target_pressed != current_pressed:
			_set_lane_pressed(lane, target_pressed)


func _set_lane_pressed(lane: int, pressed: bool) -> void:
	var current_pressed := bool(_pressed_lanes.get(lane, false))
	if current_pressed == pressed:
		return
	_pressed_lanes[lane] = pressed
	if pressed:
		lane_pressed.emit(lane)
	else:
		lane_released.emit(lane)
