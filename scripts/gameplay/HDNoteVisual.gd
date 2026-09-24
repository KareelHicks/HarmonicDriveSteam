extends Control
class_name HDNoteVisual

const HDTheme = preload("res://scripts/ui/HDTheme.gd")

class ZigZagSustainBar:
	extends Control

	const ANIMATION_FPS := 12.0
	const MAX_RENDER_HEIGHT := 3200.0

	var fill_color := Color(1, 1, 1, 0.8)
	var border_color := Color(1, 1, 1, 0.9)
	var border_width := 2.0
	var zigzag_amplitude := 5.0
	var zigzag_wavelength := 16.0
	var zigzag_speed := 8.0
	var _phase := 0.0
	var _redraw_accum := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(false)

	func set_animating(enabled: bool) -> void:
		if is_processing() == enabled:
			return
		_redraw_accum = 0.0
		set_process(enabled)
		if enabled:
			queue_redraw()

	func _process(delta: float) -> void:
		_redraw_accum += delta
		var frame_time := 1.0 / ANIMATION_FPS
		if _redraw_accum < frame_time:
			return
		var step_delta := _redraw_accum
		_redraw_accum = 0.0
		_phase = fmod(_phase + step_delta * zigzag_speed, zigzag_wavelength * 2.0)
		queue_redraw()

	func _draw() -> void:
		if size.x <= 1.0 or size.y <= 1.0:
			return
		var w := size.x
		var h := size.y
		var amp := clampf(zigzag_amplitude, 0.0, w * 0.45)
		var wave := maxf(6.0, zigzag_wavelength)
		var draw_top := maxf(0.0, h - MAX_RENDER_HEIGHT)
		var first_step := maxi(0, int(floor((draw_top + _phase) / wave)) - 1)
		var last_step := int(ceil((h + wave + _phase) / wave))

		var left: PackedVector2Array = PackedVector2Array()
		var right: PackedVector2Array = PackedVector2Array()
		for i in range(first_step, last_step + 1):
			var y := float(i) * wave - _phase
			if y < draw_top - wave:
				continue
			if y > h + wave:
				break
			var t := float(i)
			var offset := amp if int(t) % 2 == 0 else -amp
			left.append(Vector2(amp + offset * 0.35, y))
			right.append(Vector2(w - (amp + offset * 0.35), y))

		# Build closed polygon (left edge top->bottom, right edge bottom->top).
		if left.is_empty() or right.is_empty():
			return
		# Clamp endpoints to the bar rect.
		for idx in range(left.size()):
			left[idx].y = clampf(left[idx].y, draw_top, h)
			right[idx].y = clampf(right[idx].y, draw_top, h)

		var poly: PackedVector2Array = PackedVector2Array()
		for p in left:
			poly.append(p)
		for j in range(right.size() - 1, -1, -1):
			poly.append(right[j])

		draw_colored_polygon(poly, fill_color)
		# Border: draw the two zigzag edges.
		draw_polyline(left, border_color, border_width, true)
		draw_polyline(right, border_color, border_width, true)


var lane := 0
var base_size := Vector2.ZERO
var sustain_duration := 0.0
var is_holding := false
var lane_palette: Array = []
var head_glow: PanelContainer
var head_body: PanelContainer
var head_core: PanelContainer
var shine: ColorRect
var hold_aura: PanelContainer
var sustain_glow: PanelContainer
var sustain_body: PanelContainer
var sustain_core: PanelContainer
var sustain_cap: PanelContainer
var sustain_zigzag: ZigZagSustainBar
var low_cost := false
var _hold_aura_tween: Tween
var _ems_max_material: ShaderMaterial
var _ems_max_shader_enabled := false
var _ems_max_bloom_enabled := false
var _ems_max_distortion_enabled := false
var _ems_max_time := 0.0


func setup(note_lane: int, note_size: Vector2, duration: float, palette: Array = HDTheme.LANE_COLORS, reduce_cost: bool = false) -> void:
	lane = note_lane
	base_size = note_size
	sustain_duration = duration
	lane_palette = palette.duplicate()
	low_cost = reduce_cost
	size = note_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_head()
	_build_sustain()


func _build_head() -> void:
	var color: Color = lane_palette[lane % lane_palette.size()]
	if not low_cost:
		hold_aura = _panel(color, Rect2(-10, -10, base_size.x + 20, base_size.y + 20), 0.18, 0.48, 18, color)
		hold_aura.modulate.a = 0.0
		add_child(hold_aura)
		head_glow = _panel(color, Rect2(-6, -6, base_size.x + 12, base_size.y + 12), 0.16, 0.50, 16, color)
		add_child(head_glow)
	head_body = _panel(color, Rect2(0, 0, base_size.x, base_size.y), 0.92, 0.72, 14, Color.WHITE)
	add_child(head_body)
	head_core = _panel(Color.WHITE, Rect2(base_size.x * 0.18, base_size.y * 0.18, base_size.x * 0.64, base_size.y * 0.64), 0.22, 0.18, 10, Color.WHITE)
	add_child(head_core)
	shine = ColorRect.new()
	shine.color = Color(1, 1, 1, 0.26)
	shine.position = Vector2(6, base_size.y * 0.10)
	shine.size = Vector2(base_size.x - 12, maxf(4.0, base_size.y * 0.18))
	shine.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shine)


func _build_sustain() -> void:
	if sustain_duration <= 0.0:
		return
	var color: Color = lane_palette[lane % lane_palette.size()]
	if not low_cost:
		sustain_glow = _panel(color, Rect2(base_size.x * 0.39, base_size.y * 0.5, base_size.x * 0.22, 12), 0.22, 0.50, 8, color)
		sustain_glow.visible = false
		add_child(sustain_glow)
	sustain_body = _panel(color, Rect2(base_size.x * 0.41, base_size.y * 0.5, base_size.x * 0.18, 12), 0.70, 0.98, 8, color)
	sustain_body.visible = false
	add_child(sustain_body)
	if not low_cost:
		sustain_core = _panel(Color.WHITE, Rect2(base_size.x * 0.46, base_size.y * 0.5, base_size.x * 0.08, 12), 0.18, 0.0, 6, Color.WHITE)
		sustain_core.visible = false
		add_child(sustain_core)
	sustain_cap = _panel(color, Rect2(base_size.x * 0.35, base_size.y * 0.5, base_size.x * 0.30, base_size.x * 0.30), 0.85, 0.30, 12, Color.WHITE)
	sustain_cap.visible = false
	add_child(sustain_cap)

	# A more animated/expressive sustain bar while holding.
	if not low_cost:
		sustain_zigzag = ZigZagSustainBar.new()
		sustain_zigzag.visible = false
		sustain_zigzag.fill_color = Color(color.r, color.g, color.b, 0.72)
		sustain_zigzag.border_color = Color(color.r, color.g, color.b, 0.98)
		sustain_zigzag.border_width = 2.0
		sustain_zigzag.zigzag_amplitude = maxf(3.0, base_size.x * 0.12)
		sustain_zigzag.zigzag_wavelength = maxf(10.0, base_size.y * 0.85)
		sustain_zigzag.zigzag_speed = 8.0
		add_child(sustain_zigzag)


func update_sustain(height: float) -> void:
	if sustain_body == null:
		return
	var visible := height > 1.0
	if sustain_glow != null:
		sustain_glow.visible = visible
	sustain_body.visible = visible
	if sustain_core != null:
		sustain_core.visible = visible
	sustain_cap.visible = visible
	if sustain_zigzag != null:
		sustain_zigzag.visible = visible and is_holding and not low_cost
	if not visible:
		if sustain_zigzag != null:
			sustain_zigzag.set_animating(false)
		return
	var glow_width := base_size.x * (0.34 if is_holding and not low_cost else 0.22)
	var body_width := base_size.x * (0.28 if is_holding and not low_cost else 0.18)
	var use_zigzag := sustain_zigzag != null and is_holding and not low_cost
	if use_zigzag:
		# Hide the static body/core and swap in the animated zigzag bar.
		sustain_body.visible = false
		if sustain_core != null:
			sustain_core.visible = false
		sustain_zigzag.set_animating(true)
	else:
		if sustain_zigzag != null:
			sustain_zigzag.set_animating(false)
		sustain_body.visible = true
		if sustain_core != null:
			sustain_core.visible = true

	var wave_x := 0.0
	if sustain_glow != null:
		sustain_glow.position = Vector2(base_size.x * 0.33, -height + base_size.y * 0.5)
		sustain_glow.size = Vector2(glow_width, height)
	if use_zigzag:
		sustain_zigzag.position = Vector2(base_size.x * 0.33, -height + base_size.y * 0.5)
		sustain_zigzag.size = Vector2(glow_width, height)
	else:
		sustain_body.position = Vector2(base_size.x * (0.36 if is_holding and not low_cost else 0.41), -height + base_size.y * 0.5)
		sustain_body.size = Vector2(body_width, height)
	if sustain_core != null:
		sustain_core.position = Vector2(base_size.x * 0.46, -height + base_size.y * 0.5)
		sustain_core.size = Vector2(base_size.x * 0.08, height)
	sustain_cap.position = Vector2(base_size.x * 0.35, -height + base_size.y * 0.5 - base_size.x * 0.15)
	sustain_cap.size = Vector2(base_size.x * 0.30, base_size.x * 0.30)


func start_hold() -> void:
	if is_holding:
		return
	is_holding = true
	head_body.scale = Vector2(1.08, 1.08) if low_cost else Vector2(1.12, 1.12)
	head_core.modulate.a = 0.28 if low_cost else 0.34
	if head_glow != null:
		head_glow.modulate.a = 0.95
	if hold_aura != null:
		hold_aura.modulate.a = 0.85
		hold_aura.scale = Vector2(1.0, 1.0)
		if is_instance_valid(_hold_aura_tween):
			_hold_aura_tween.kill()
		if not low_cost:
			_hold_aura_tween = create_tween().set_loops()
			_hold_aura_tween.tween_property(hold_aura, "scale", Vector2(1.10, 1.10), 0.24).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if sustain_body != null:
		sustain_body.modulate.a = 0.90
		if sustain_core != null:
			sustain_core.modulate.a = 0.32
	if sustain_zigzag != null and not low_cost:
		sustain_zigzag.visible = true
		sustain_zigzag.set_animating(true)


func pop_and_fade() -> void:
	if sustain_zigzag != null:
		sustain_zigzag.set_animating(false)
	var tween := create_tween()
	tween.parallel().tween_property(self, "scale", Vector2(1.6, 1.6), 0.12)
	tween.parallel().tween_property(self, "modulate:a", 0.0, 0.12)
	tween.finished.connect(queue_free)


func miss_fade() -> void:
	if sustain_zigzag != null:
		sustain_zigzag.set_animating(false)
	if head_glow != null:
		head_glow.modulate = HDTheme.MISS
	head_body.modulate = Color(1.0, 0.6, 0.6, 0.95)
	head_core.modulate.a = 0.06
	shine.modulate.a = 0.0
	if sustain_glow != null:
		sustain_glow.modulate = HDTheme.MISS
	if sustain_body != null:
		sustain_body.modulate = Color(1.0, 0.5, 0.5, 0.8)
	if sustain_core != null:
		sustain_core.modulate.a = 0.04
	var tween := create_tween()
	tween.parallel().tween_property(self, "position", position + Vector2(0, 26), 0.18)
	tween.parallel().tween_property(self, "rotation", deg_to_rad(8.0 if lane % 2 == 0 else -8.0), 0.18)
	tween.parallel().tween_property(self, "scale", Vector2(0.86, 0.86), 0.18)
	tween.parallel().tween_property(self, "modulate:a", 0.0, 0.18)
	tween.finished.connect(queue_free)


func set_glow_multiplier(multiplier: float) -> void:
	if head_glow != null:
		head_glow.modulate.a = clampf(0.75 * multiplier, 0.0, 1.0)
	if sustain_glow != null:
		sustain_glow.modulate.a = clampf(0.65 * multiplier, 0.0, 1.0)


func set_ems_maximum_shader(enabled: bool, bloom_enabled: bool, distortion_enabled: bool) -> void:
	var effective_enabled := enabled and not low_cost and (bloom_enabled or distortion_enabled)
	if _ems_max_shader_enabled == effective_enabled \
		and _ems_max_bloom_enabled == bloom_enabled \
		and _ems_max_distortion_enabled == distortion_enabled:
		return
	_ems_max_shader_enabled = effective_enabled
	_ems_max_bloom_enabled = bloom_enabled
	_ems_max_distortion_enabled = distortion_enabled
	if _ems_max_material == null and effective_enabled:
		_ems_max_material = _make_ems_maximum_material()
		_ems_max_material.set_shader_parameter("lane_seed", float(lane) * 1.37)
	_apply_ems_material_to_parts(_ems_max_material if effective_enabled else null)
	if _ems_max_material != null:
		_ems_max_material.set_shader_parameter("bloom_amount", 1.0 if bloom_enabled else 0.0)
		_ems_max_material.set_shader_parameter("distortion_amount", 1.0 if distortion_enabled else 0.0)
		if not effective_enabled:
			_ems_max_material.set_shader_parameter("intensity", 0.0)


func update_ems_maximum_shader(intensity: float, song_time: float) -> void:
	if not _ems_max_shader_enabled or _ems_max_material == null:
		return
	_ems_max_time = song_time
	_ems_max_material.set_shader_parameter("time", _ems_max_time)
	_ems_max_material.set_shader_parameter("intensity", clampf(intensity, 0.0, 1.0))


func set_hold_visibility(alpha: float) -> void:
	if sustain_body == null:
		return
	var clamped_alpha := clampf(alpha, 0.0, 1.0)
	if sustain_glow != null:
		sustain_glow.modulate.a = 0.28 * clamped_alpha
	sustain_body.modulate.a = 0.78 * clamped_alpha
	if sustain_core != null:
		sustain_core.modulate.a = 0.24 * clamped_alpha
	sustain_cap.modulate.a = 0.88 * clamped_alpha


func _panel(color: Color, rect: Rect2, fill_alpha: float, border_alpha: float, radius: int, border_color: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color.r, color.g, color.b, fill_alpha)
	style.border_color = Color(border_color.r, border_color.g, border_color.b, border_alpha)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _apply_ems_material_to_parts(next_material: Material) -> void:
	for part in [
		hold_aura,
		head_glow,
		head_body,
		head_core,
		shine,
		sustain_glow,
		sustain_body,
		sustain_core,
		sustain_cap,
		sustain_zigzag,
	]:
		if part is CanvasItem:
			(part as CanvasItem).material = next_material


func _make_ems_maximum_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;

uniform float time = 0.0;
uniform float intensity = 0.0;
uniform float bloom_amount = 1.0;
uniform float distortion_amount = 1.0;
uniform float lane_seed = 0.0;

void vertex() {
	float wave = sin(VERTEX.y * 0.09 + time * 5.0 + lane_seed) * distortion_amount * intensity * 1.8;
	VERTEX.x += wave;
}

void fragment() {
	vec4 col = COLOR;
	float sheen = sin((UV.x * 7.0) + (UV.y * 5.0) + time * 4.3 + lane_seed) * 0.5 + 0.5;
	float pulse = sin(time * 6.2 + lane_seed) * 0.5 + 0.5;
	float glow = (0.18 + sheen * 0.24 + pulse * 0.14) * intensity * bloom_amount;
	col.rgb += col.rgb * glow;
	col.rgb += vec3(0.18, 0.72, 1.0) * glow * 0.18;
	col.a *= 1.0 + intensity * bloom_amount * 0.08;
	COLOR = col;
}
"""
	mat.shader = shader
	mat.set_shader_parameter("time", 0.0)
	mat.set_shader_parameter("intensity", 0.0)
	mat.set_shader_parameter("bloom_amount", 1.0)
	mat.set_shader_parameter("distortion_amount", 1.0)
	mat.set_shader_parameter("lane_seed", float(lane) * 1.37)
	return mat
