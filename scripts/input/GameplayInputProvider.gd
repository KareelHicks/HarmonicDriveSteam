extends Control
class_name GameplayInputProvider

signal lane_pressed(lane: int)
signal lane_released(lane: int)

var lane_count := 5


func setup_provider(config: Dictionary = {}) -> void:
	lane_count = int(config.get("lane_count", lane_count))
