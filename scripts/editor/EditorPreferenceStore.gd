extends RefCounted
class_name EditorPreferenceStore

const SAVE_PATH := "user://chart_editor.cfg"
const SECTION := "editor"
const LAYOUT_HORIZONTAL := "horizontal"
const LAYOUT_VERTICAL := "vertical"
const DIRECTION_FALL_DOWN := "fall_down"
const DIRECTION_RISE_UP := "rise_up"
const VIEW_MODE_TIMELINE_ZOOM := "timeline_zoom"
const VIEW_MODE_GAMEPLAY_PREVIEW := "gameplay_preview"
const DEFAULT_TRACK_WIDTH_SCALE := 0.72
const DEFAULT_KEYBOARD_HOLD_THRESHOLD_MSEC := 120
const MIN_KEYBOARD_HOLD_THRESHOLD_MSEC := 1
const MAX_KEYBOARD_HOLD_THRESHOLD_MSEC := 5000


static func get_layout_mode() -> String:
	var config := _load_config()
	var value := str(config.get_value(SECTION, "layout_mode", LAYOUT_VERTICAL)).strip_edges().to_lower()
	return value if _is_valid_layout(value) else LAYOUT_VERTICAL


static func set_layout_mode(value: String) -> void:
	var config := _load_config()
	var mode := value.strip_edges().to_lower()
	if not _is_valid_layout(mode):
		mode = LAYOUT_VERTICAL
	config.set_value(SECTION, "layout_mode", mode)
	config.save(SAVE_PATH)


static func get_vertical_direction() -> String:
	var config := _load_config()
	var value := str(config.get_value(SECTION, "vertical_direction", DIRECTION_FALL_DOWN)).strip_edges().to_lower()
	return value if _is_valid_direction(value) else DIRECTION_FALL_DOWN


static func set_vertical_direction(value: String) -> void:
	var config := _load_config()
	var direction := value.strip_edges().to_lower()
	if not _is_valid_direction(direction):
		direction = DIRECTION_FALL_DOWN
	config.set_value(SECTION, "vertical_direction", direction)
	config.save(SAVE_PATH)


static func get_vertical_view_mode() -> String:
	var config := _load_config()
	var value := str(config.get_value(SECTION, "vertical_view_mode", VIEW_MODE_GAMEPLAY_PREVIEW)).strip_edges().to_lower()
	return value if _is_valid_view_mode(value) else VIEW_MODE_GAMEPLAY_PREVIEW


static func set_vertical_view_mode(value: String) -> void:
	var config := _load_config()
	var mode := value.strip_edges().to_lower()
	if not _is_valid_view_mode(mode):
		mode = VIEW_MODE_GAMEPLAY_PREVIEW
	config.set_value(SECTION, "vertical_view_mode", mode)
	config.save(SAVE_PATH)


static func has_shown_layout_prompt() -> bool:
	var config := _load_config()
	return bool(config.get_value(SECTION, "layout_prompt_shown", false))


static func mark_layout_prompt_shown() -> void:
	var config := _load_config()
	config.set_value(SECTION, "layout_prompt_shown", true)
	config.save(SAVE_PATH)


static func get_track_width_scale() -> float:
	var config := _load_config()
	var value := float(config.get_value(SECTION, "track_width_scale", DEFAULT_TRACK_WIDTH_SCALE))
	return clampf(value, 0.45, 1.0)


static func set_track_width_scale(value: float) -> void:
	var config := _load_config()
	config.set_value(SECTION, "track_width_scale", clampf(value, 0.45, 1.0))
	config.save(SAVE_PATH)


static func get_keyboard_hold_threshold_msec() -> int:
	var config := _load_config()
	var value := int(config.get_value(
		SECTION,
		"keyboard_hold_threshold_msec",
		DEFAULT_KEYBOARD_HOLD_THRESHOLD_MSEC
	))
	return clampi(value, MIN_KEYBOARD_HOLD_THRESHOLD_MSEC, MAX_KEYBOARD_HOLD_THRESHOLD_MSEC)


static func set_keyboard_hold_threshold_msec(value: int) -> void:
	var config := _load_config()
	config.set_value(
		SECTION,
		"keyboard_hold_threshold_msec",
		clampi(value, MIN_KEYBOARD_HOLD_THRESHOLD_MSEC, MAX_KEYBOARD_HOLD_THRESHOLD_MSEC)
	)
	config.save(SAVE_PATH)


static func _load_config() -> ConfigFile:
	var config := ConfigFile.new()
	config.load(SAVE_PATH)
	return config


static func _is_valid_layout(value: String) -> bool:
	return value == LAYOUT_HORIZONTAL or value == LAYOUT_VERTICAL


static func _is_valid_direction(value: String) -> bool:
	return value == DIRECTION_FALL_DOWN or value == DIRECTION_RISE_UP


static func _is_valid_view_mode(value: String) -> bool:
	return value == VIEW_MODE_TIMELINE_ZOOM or value == VIEW_MODE_GAMEPLAY_PREVIEW
