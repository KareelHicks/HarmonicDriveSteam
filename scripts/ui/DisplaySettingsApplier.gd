extends RefCounted

const RESOLUTION_FALLBACK := Vector2i(1920, 1080)


static func apply_from_profile() -> void:
	if ProfileStore == null:
		return
	apply_values(
		ProfileStore.get_fps_limit(),
		ProfileStore.get_vsync_mode(),
		ProfileStore.get_window_mode(),
		ProfileStore.get_display_resolution()
	)


static func apply_values(fps_limit: int, vsync_mode: String, window_mode: String, display_resolution: String) -> void:
	Engine.max_fps = maxi(0, fps_limit)
	_apply_vsync(vsync_mode)
	_apply_window(window_mode, _parse_resolution(display_resolution))


static func _apply_vsync(mode: String) -> void:
	match mode.to_lower():
		"off":
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		"adaptive":
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ADAPTIVE)
		_:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)


static func _apply_window(mode: String, resolution: Vector2i) -> void:
	if not _is_desktop():
		return
	match mode.to_lower():
		"windowed":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_size(resolution)
			_center_window(resolution)
		"borderless_fullscreen":
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		_:
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)


static func _center_window(resolution: Vector2i) -> void:
	var screen := DisplayServer.window_get_current_screen()
	var usable_rect := DisplayServer.screen_get_usable_rect(screen)
	var next_position := usable_rect.position + Vector2i(
		int((usable_rect.size.x - resolution.x) / 2),
		int((usable_rect.size.y - resolution.y) / 2)
	)
	DisplayServer.window_set_position(next_position)


static func _parse_resolution(value: String) -> Vector2i:
	var parts := value.to_lower().split("x")
	if parts.size() != 2:
		return RESOLUTION_FALLBACK
	var width := int(parts[0])
	var height := int(parts[1])
	if width <= 0 or height <= 0:
		return RESOLUTION_FALLBACK
	return Vector2i(width, height)


static func _is_desktop() -> bool:
	return OS.has_feature("windows") or OS.has_feature("macos") or OS.has_feature("linuxbsd")
