extends "res://scripts/input/GameplayInputProvider.gd"
class_name KeyboardInputProvider


func _ready() -> void:
	set_process_unhandled_input(true)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.physical_keycode != 0:
		for lane in lane_count:
			var action := "lane_%d" % lane
			if event.is_action_pressed(action) and not event.echo:
				lane_pressed.emit(lane)
			elif event.is_action_released(action):
				lane_released.emit(lane)
