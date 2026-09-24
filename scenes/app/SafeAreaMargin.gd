extends MarginContainer


func _ready() -> void:
	_apply_safe_area()
	get_viewport().size_changed.connect(_apply_safe_area)


func _apply_safe_area() -> void:
	var left := 0
	var top := 0
	var right := 0
	var bottom := 0

	if OS.has_feature("android") or OS.has_feature("ios"):
		var safe_area: Rect2i = DisplayServer.get_display_safe_area()
		var window_size_i: Vector2i = get_window().size
		var viewport_size: Vector2 = get_viewport_rect().size
		if safe_area.size.x > 0 and safe_area.size.y > 0 and window_size_i.x > 0 and window_size_i.y > 0:
			var scale_x: float = viewport_size.x / float(window_size_i.x)
			var scale_y: float = viewport_size.y / float(window_size_i.y)
			left = int(round(maxi(0, safe_area.position.x) * scale_x))
			top = int(round(maxi(0, safe_area.position.y) * scale_y))
			right = int(round(maxi(0, window_size_i.x - (safe_area.position.x + safe_area.size.x)) * scale_x))
			bottom = int(round(maxi(0, window_size_i.y - (safe_area.position.y + safe_area.size.y)) * scale_y))

	add_theme_constant_override("margin_left", left)
	add_theme_constant_override("margin_top", top)
	add_theme_constant_override("margin_right", right)
	add_theme_constant_override("margin_bottom", bottom)
