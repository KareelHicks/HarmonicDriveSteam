extends Node2D

##
# EmotionalGlyphLayer
# ------------------
# Floating geometric "runes": triangles/diamonds/hex outlines with rotation.
# Provides shape variety beyond rectangles/circles.
##

const MAX_GLYPHS_DESKTOP := 28
const MAX_GLYPHS_MOBILE := 14

const MOTION_LINEAR := 0
const MOTION_ORBIT := 1
const MOTION_ZIGZAG := 2

var _rng := RandomNumberGenerator.new()
var _glyphs: Array[Dictionary] = []
var _active_count := 0
var _time := 0.0
var _bounds := Vector2(1, 1)


func _ready() -> void:
	name = "EmotionalGlyphLayer"
	_rng.randomize()
	_build_pool()
	if EmotionalMotionSystem != null:
		EmotionalMotionSystem.register_layer(self)
	set_process(true)


func _exit_tree() -> void:
	if EmotionalMotionSystem != null:
		EmotionalMotionSystem.unregister_layer(self)


func ems_on_enabled_changed(is_enabled: bool) -> void:
	visible = is_enabled
	set_process(is_enabled)
	if not is_enabled:
		queue_redraw()


func ems_on_palette_changed(_ems: Node) -> void:
	_build_pool()


func ems_update(_ems: Node, delta: float) -> void:
	if EmotionalMotionSystem == null or not EmotionalMotionSystem.enabled:
		return
	_time += delta
	_bounds = _get_bounds_size()

	var max_glyphs := MAX_GLYPHS_DESKTOP
	if AppState != null and AppState.is_mobile_platform():
		max_glyphs = MAX_GLYPHS_MOBILE
	if ProfileStore != null and ProfileStore.is_prioritize_fps_enabled():
		max_glyphs = int(roundi(float(max_glyphs) * 0.7))
	var layer_weight := EmotionalMotionSystem.get_loadout_layer_weight("glyph", 1.0)
	if layer_weight <= 0.01:
		_active_count = 0
		queue_redraw()
		return
	if layer_weight < 1.0:
		max_glyphs = int(roundi(float(max_glyphs) * layer_weight))

	var combo := float(EmotionalMotionSystem.combo_energy)
	var intensity := float(EmotionalMotionSystem.intensity)
	_active_count = clampi(int(roundi(float(max_glyphs) * clampf(0.20 + combo * 0.55 + intensity * 0.25, 0.0, 1.0))), 0, max_glyphs)

	_update_glyphs(delta)
	queue_redraw()


func _build_pool() -> void:
	_glyphs.clear()
	for i in MAX_GLYPHS_DESKTOP:
		_glyphs.append(_make_glyph(i))


func _make_glyph(seed: int) -> Dictionary:
	var motion := MOTION_LINEAR
	var r := _rng.randf()
	if r < 0.55:
		motion = MOTION_LINEAR
	elif r < 0.80:
		motion = MOTION_ZIGZAG
	else:
		motion = MOTION_ORBIT

	var shape := _rng.randi_range(0, 2) # 0 tri, 1 diamond, 2 hex
	var size := _rng.randf_range(10.0, 34.0)
	var vel := Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)).normalized() * _rng.randf_range(10.0, 26.0)
	var rot := _rng.randf_range(0.0, TAU)
	var rot_speed := _rng.randf_range(-0.55, 0.55)
	var orbit_center := Vector2(_rng.randf(), _rng.randf())
	var orbit_radius := _rng.randf_range(0.04, 0.16)
	var orbit_angle := _rng.randf_range(0.0, TAU)
	var orbit_ang_vel := _rng.randf_range(-0.35, 0.35)
	var zig_phase := _rng.randf_range(0.0, TAU)
	var zig_amp := _rng.randf_range(0.03, 0.10)
	var zig_freq := _rng.randf_range(0.7, 1.6)

	var color := Color(1, 1, 1, 1)
	if EmotionalMotionSystem != null:
		color = EmotionalMotionSystem.pick_color("glyph", seed)

	return {
		"seed": seed,
		"shape": shape,
		"size": size,
		"pos": Vector2(_rng.randf(), _rng.randf()),
		"vel": vel,
		"motion": motion,
		"rot": rot,
		"rot_speed": rot_speed,
		"orbit_center": orbit_center,
		"orbit_radius": orbit_radius,
		"orbit_angle": orbit_angle,
		"orbit_ang_vel": orbit_ang_vel,
		"zig_phase": zig_phase,
		"zig_amp": zig_amp,
		"zig_freq": zig_freq,
		"alpha": _rng.randf_range(0.25, 1.0),
		"color": color,
	}


func _update_glyphs(delta: float) -> void:
	if _bounds.x <= 1.0 or _bounds.y <= 1.0:
		return
	var bpm := float(EmotionalMotionSystem.bpm)
	var bpm_scale := clampf(bpm / 160.0, 0.7, 1.4)
	for i in _active_count:
		var g := _glyphs[i]
		var pos01: Vector2 = g["pos"]
		var vel: Vector2 = g["vel"]
		var motion: int = int(g["motion"])

		match motion:
			MOTION_ORBIT:
				var center01: Vector2 = g["orbit_center"]
				var radius: float = float(g["orbit_radius"])
				var angle: float = float(g["orbit_angle"])
				angle = fmod(angle + delta * float(g["orbit_ang_vel"]) * bpm_scale, TAU)
				pos01 = center01 + Vector2(cos(angle), sin(angle)) * radius
				g["orbit_angle"] = angle
			MOTION_ZIGZAG:
				var phase := float(g["zig_phase"])
				phase = fmod(phase + delta * float(g["zig_freq"]) * bpm_scale, TAU)
				g["zig_phase"] = phase
				var forward := vel * delta * bpm_scale
				var side := Vector2(-vel.y, vel.x).normalized() * sin(phase) * float(g["zig_amp"]) * delta * 60.0
				var motion_vec := forward + side
				pos01.x += motion_vec.x / _bounds.x
				pos01.y += motion_vec.y / _bounds.y
			_:
				pos01.x += (vel.x * delta * bpm_scale) / _bounds.x
				pos01.y += (vel.y * delta * bpm_scale) / _bounds.y

		if pos01.x < -0.15:
			pos01.x = 1.15
		if pos01.x > 1.15:
			pos01.x = -0.15
		if pos01.y < -0.15:
			pos01.y = 1.15
		if pos01.y > 1.15:
			pos01.y = -0.15

		g["pos"] = pos01
		g["rot"] = fmod(float(g["rot"]) + delta * float(g["rot_speed"]) * bpm_scale, TAU)
		_glyphs[i] = g


func _draw() -> void:
	if EmotionalMotionSystem == null or not EmotionalMotionSystem.enabled:
		return
	_bounds = _get_bounds_size()
	var combo := float(EmotionalMotionSystem.combo_energy)
	var intensity := float(EmotionalMotionSystem.intensity)
	var style := EmotionalMotionSystem.get_style_multiplier()
	var layer_weight := EmotionalMotionSystem.get_loadout_layer_weight("glyph", 1.0)
	if layer_weight <= 0.01:
		return
	style *= layer_weight
	var alpha_base := (0.010 + combo * 0.045 + intensity * 0.020) * style
	alpha_base = clampf(alpha_base, 0.0, 0.12)

	for i in _active_count:
		var g := _glyphs[i]
		var pos01: Vector2 = g["pos"]
		var pos := Vector2(pos01.x * _bounds.x, pos01.y * _bounds.y)
		var size := float(g["size"])
		var rot := float(g["rot"])
		var shape := int(g["shape"])
		var c: Color = g.get("color", Color(1, 1, 1, 1))
		c.a = alpha_base * float(g["alpha"])

		var pts := _shape_points(shape, size)
		var out := PackedVector2Array()
		for p in pts:
			out.append(pos + p.rotated(rot))

		# Outline-only for a "glyph" feel.
		for j in range(out.size()):
			var a := out[j]
			var b := out[(j + 1) % out.size()]
			draw_line(a, b, c, 2.0)


func _shape_points(shape: int, size: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	match shape:
		0: # triangle
			pts.append(Vector2(0, -size))
			pts.append(Vector2(size * 0.85, size * 0.55))
			pts.append(Vector2(-size * 0.85, size * 0.55))
		1: # diamond
			pts.append(Vector2(0, -size))
			pts.append(Vector2(size, 0))
			pts.append(Vector2(0, size))
			pts.append(Vector2(-size, 0))
		_: # hex
			for i in 6:
				var a := float(i) / 6.0 * TAU
				pts.append(Vector2(cos(a), sin(a)) * size)
	return pts


func _get_bounds_size() -> Vector2:
	var parent := get_parent()
	if parent is Control:
		return (parent as Control).size
	return get_viewport_rect().size
