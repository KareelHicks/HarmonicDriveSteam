extends PanelContainer
class_name EMSPreviewViewport

const EMSRuntime = preload("res://systems/ems/EMSRuntime.gd")

var _runtime: EMSRuntime
var _right_runtime: EMSRuntime
var _gameplay_overlay: PreviewGameplayOverlay
var _sim_time := 0.0
var _playing := true
var _last_config: Dictionary = {}


class PreviewGameplayOverlay:
	extends Node2D

	var panel_size := Vector2.ZERO
	var gutter_mode := false
	var gutter_width := 0.0
	var mask_color := Color(0.025, 0.028, 0.040, 0.82)

	func set_preview_layout(size_value: Vector2, gutters_enabled: bool, gutter_width_value: float) -> void:
		panel_size = Vector2(maxf(0.0, size_value.x), maxf(0.0, size_value.y))
		gutter_mode = gutters_enabled
		gutter_width = maxf(0.0, gutter_width_value)
		queue_redraw()

	func _draw() -> void:
		if panel_size.x <= 1.0 or panel_size.y <= 1.0:
			return
		var center_rect := Rect2(Vector2.ZERO, panel_size)
		if gutter_mode:
			center_rect = Rect2(gutter_width, 0.0, maxf(0.0, panel_size.x - gutter_width * 2.0), panel_size.y)
			draw_rect(center_rect, mask_color, true)
		_draw_chart_highway(center_rect)

	func _draw_chart_highway(center_rect: Rect2) -> void:
		if center_rect.size.x <= 24.0 or center_rect.size.y <= 80.0:
			return
		var road_top := center_rect.position.y + center_rect.size.y * 0.11
		var road_bottom := center_rect.position.y + center_rect.size.y * 0.96
		var road_center := center_rect.position.x + center_rect.size.x * 0.5
		var top_width := clampf(center_rect.size.x * 0.20, 56.0, 142.0)
		var bottom_width := clampf(center_rect.size.x * 0.58, 180.0, 390.0)
		var top_left := Vector2(road_center - top_width * 0.5, road_top)
		var top_right := Vector2(road_center + top_width * 0.5, road_top)
		var bottom_right := Vector2(road_center + bottom_width * 0.5, road_bottom)
		var bottom_left := Vector2(road_center - bottom_width * 0.5, road_bottom)
		var fill := Color(0.015, 0.018, 0.030, 0.72)
		var edge := Color(0.34, 0.88, 1.0, 0.38)
		var edge_hot := Color(1.0, 0.30, 0.88, 0.22)
		draw_polygon(PackedVector2Array([top_left, top_right, bottom_right, bottom_left]), PackedColorArray([fill, fill, fill, fill]))
		draw_line(top_left, bottom_left, edge, 2.0, true)
		draw_line(top_right, bottom_right, edge, 2.0, true)
		draw_line(top_left, top_right, edge_hot, 1.0, true)
		draw_line(bottom_left, bottom_right, edge, 2.0, true)
		var lanes := 5
		for lane in range(1, lanes):
			var t := float(lane) / float(lanes)
			var lane_top := top_left.lerp(top_right, t)
			var lane_bottom := bottom_left.lerp(bottom_right, t)
			var lane_color := Color(0.65, 0.82, 1.0, 0.12)
			draw_line(lane_top, lane_bottom, lane_color, 1.0, true)
		for row in range(7):
			var depth := float(row + 1) / 8.0
			var y := lerpf(road_top, road_bottom, depth)
			var w := lerpf(top_width, bottom_width, depth)
			var h := lerpf(6.0, 16.0, depth)
			var lane := row % lanes
			var lane_center := road_center - w * 0.5 + (float(lane) + 0.5) * (w / float(lanes))
			var note_colors: Array[Color] = [
				Color(0.28, 0.90, 1.0, 0.50),
				Color(1.0, 0.25, 0.95, 0.42),
				Color(1.0, 0.86, 0.22, 0.52),
				Color(0.25, 1.0, 0.58, 0.42),
				Color(1.0, 0.38, 0.20, 0.44),
			]
			var note_color: Color = note_colors[lane]
			_draw_capsule(Vector2(lane_center, y), Vector2(w / float(lanes) * 0.34, h), note_color)
		var pad_y := road_bottom - 24.0
		for lane in range(lanes):
			var lane_center := road_center - bottom_width * 0.5 + (float(lane) + 0.5) * (bottom_width / float(lanes))
			var pad_colors: Array[Color] = [
				Color(0.28, 0.90, 1.0, 0.28),
				Color(1.0, 0.25, 0.95, 0.24),
				Color(1.0, 0.86, 0.22, 0.30),
				Color(0.25, 1.0, 0.58, 0.24),
				Color(1.0, 0.38, 0.20, 0.26),
			]
			var pad_color: Color = pad_colors[lane]
			_draw_capsule(Vector2(lane_center, pad_y), Vector2(bottom_width / float(lanes) * 0.42, 20.0), pad_color)

	func _draw_capsule(center: Vector2, extents: Vector2, fill: Color) -> void:
		var half_h := maxf(2.0, extents.y * 0.5)
		var half_w := maxf(half_h, extents.x * 0.5)
		draw_rect(Rect2(center.x - half_w + half_h, center.y - half_h, maxf(0.0, half_w * 2.0 - half_h * 2.0), half_h * 2.0), fill, true)
		draw_circle(Vector2(center.x - half_w + half_h, center.y), half_h, fill)
		draw_circle(Vector2(center.x + half_w - half_h, center.y), half_h, fill)


func _ready() -> void:
	clip_contents = true
	custom_minimum_size = Vector2(420, 240)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_runtime = EMSRuntime.new()
	_runtime.name = "CreatorPreviewLeftRuntime"
	_runtime.set_gutter_filter("both")
	add_child(_runtime)
	_right_runtime = EMSRuntime.new()
	_right_runtime.name = "CreatorPreviewRightRuntime"
	_right_runtime.set_gutter_filter("right")
	add_child(_right_runtime)
	_gameplay_overlay = PreviewGameplayOverlay.new()
	_gameplay_overlay.name = "CreatorPreviewGameplayOverlay"
	add_child(_gameplay_overlay)
	_update_runtime_canvas()
	set_process(true)


func load_preview_config(config: Dictionary) -> void:
	_last_config = config.duplicate(true)
	if _runtime != null:
		_runtime.set_gutter_filter("left" if _is_gutter_mode() else "both")
		_runtime.load_config(config)
	if _right_runtime != null:
		if _is_gutter_mode():
			_right_runtime.set_gutter_filter("right")
			_right_runtime.load_config(config)
		else:
			_right_runtime.clear()
	_update_runtime_canvas()


func set_preview_playing(value: bool) -> void:
	_playing = value


func is_preview_playing() -> bool:
	return _playing


func simulate_event(event_name: String, strength: float = 1.0) -> void:
	if _runtime != null:
		_runtime.dispatch_event(event_name, {"strength": strength, "value": strength})
		_runtime.update_runtime({
			"intensity": 1.0,
			"combo": 1.0,
			"bpm": 140.0,
			"density": 0.7,
			"motion_scale": 1.0,
		}, 0.016)
	if _right_runtime != null and _right_runtime.visible:
		_right_runtime.dispatch_event(event_name, {"strength": strength, "value": strength})
		_right_runtime.update_runtime({
			"intensity": 1.0,
			"combo": 1.0,
			"bpm": 140.0,
			"density": 0.7,
			"motion_scale": 1.0,
		}, 0.016)


func get_preview_debug_state() -> Dictionary:
	if _runtime == null:
		return {}
	var state := _runtime.get_debug_state()
	state["preview_panel_size"] = size
	state["preview_region_mode"] = "gutters" if _is_gutter_mode() else "full_background"
	state["preview_right_runtime_active"] = _right_runtime != null and _right_runtime.visible
	state["preview_right_runtime_position"] = _right_runtime.position if _right_runtime != null else Vector2.ZERO
	state["preview_has_chart_highway"] = _gameplay_overlay != null and _gameplay_overlay.visible
	if _right_runtime != null and _right_runtime.visible:
		state["right_runtime"] = _right_runtime.get_debug_state()
	return state


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_runtime_canvas()


func _process(delta: float) -> void:
	if _runtime == null or not _playing:
		return
	_sim_time += delta
	_runtime.update_runtime({
		"intensity": sin(_sim_time * 1.7) * 0.5 + 0.5,
		"combo": sin(_sim_time * 0.9) * 0.5 + 0.5,
		"bpm": 140.0,
		"density": 0.45,
		"motion_scale": 1.0,
	}, delta)
	if _right_runtime != null and _right_runtime.visible:
		_right_runtime.update_runtime({
			"intensity": sin(_sim_time * 1.7) * 0.5 + 0.5,
			"combo": sin(_sim_time * 0.9) * 0.5 + 0.5,
			"bpm": 140.0,
			"density": 0.45,
			"motion_scale": 1.0,
		}, delta)


func _update_runtime_canvas() -> void:
	if _runtime == null:
		return
	var panel_size := Vector2(maxf(2.0, size.x), maxf(2.0, size.y))
	if _is_gutter_mode():
		var gutter_width := clampf(panel_size.x * 0.28, 80.0, panel_size.x * 0.46)
		var gutter_size := Vector2(gutter_width, panel_size.y)
		_runtime.visible = true
		_runtime.position = Vector2.ZERO
		_runtime.set_preview_canvas_size(gutter_size)
		if _right_runtime != null:
			_right_runtime.visible = true
			_right_runtime.position = Vector2(panel_size.x - gutter_width, 0.0)
			_right_runtime.set_preview_canvas_size(gutter_size)
		if _gameplay_overlay != null:
			_gameplay_overlay.visible = true
			_gameplay_overlay.position = Vector2.ZERO
			_gameplay_overlay.set_preview_layout(panel_size, true, gutter_width)
	else:
		_runtime.visible = true
		_runtime.position = Vector2.ZERO
		_runtime.set_preview_canvas_size(panel_size)
		if _right_runtime != null:
			_right_runtime.visible = false
			_right_runtime.position = Vector2.ZERO
			_right_runtime.set_preview_canvas_size(Vector2.ZERO)
		if _gameplay_overlay != null:
			_gameplay_overlay.visible = true
			_gameplay_overlay.position = Vector2.ZERO
			_gameplay_overlay.set_preview_layout(panel_size, false, 0.0)


func _is_gutter_mode() -> bool:
	var layout: Dictionary = _last_config.get("layout", {}) as Dictionary
	return str(layout.get("background_region", "gutters")) == "gutters"
