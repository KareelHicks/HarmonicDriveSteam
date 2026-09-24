extends Node2D

##
# EmotionalPrismLayer
# ------------------
# Transparent floating structures (skewed quads) with soft highlight.
# Adds depth and color variety without "black rectangles".
##

const MAX_PANES_DESKTOP := 18
const MAX_PANES_MOBILE := 10

var _rng := RandomNumberGenerator.new()
var _panes: Array[Dictionary] = []
var _active_count := 0
var _time := 0.0
var _bounds := Vector2(1, 1)


func _ready() -> void:
	name = "EmotionalPrismLayer"
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

	var max_panes := MAX_PANES_DESKTOP
	if AppState != null and AppState.is_mobile_platform():
		max_panes = MAX_PANES_MOBILE
	if ProfileStore != null and ProfileStore.is_prioritize_fps_enabled():
		max_panes = int(roundi(float(max_panes) * 0.7))

	var combo := float(EmotionalMotionSystem.combo_energy)
	var intensity := float(EmotionalMotionSystem.intensity)
	_active_count = clampi(int(roundi(float(max_panes) * clampf(0.20 + combo * 0.55 + intensity * 0.25, 0.0, 1.0))), 0, max_panes)

	_update_panes(delta)
	queue_redraw()


func _build_pool() -> void:
	_panes.clear()
	for i in MAX_PANES_DESKTOP:
		_panes.append(_make_pane(i))


func _make_pane(seed: int) -> Dictionary:
	var size := Vector2(_rng.randf_range(80.0, 240.0), _rng.randf_range(50.0, 180.0))
	var skew := Vector2(_rng.randf_range(-0.35, 0.35), _rng.randf_range(-0.25, 0.25))
	var vel := Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)).normalized() * _rng.randf_range(8.0, 22.0)
	var rot := _rng.randf_range(0.0, TAU)
	var rot_speed := _rng.randf_range(-0.18, 0.18)
	var color := Color(1, 1, 1, 1)
	if EmotionalMotionSystem != null:
		color = EmotionalMotionSystem.pick_color("prism", seed)
	return {
		"seed": seed,
		"pos": Vector2(_rng.randf(), _rng.randf()),
		"vel": vel,
		"size": size,
		"skew": skew,
		"skew_phase": _rng.randf_range(0.0, TAU),
		"skew_speed": _rng.randf_range(0.05, 0.18),
		"rot": rot,
		"rot_speed": rot_speed,
		"life": _rng.randf_range(3.0, 8.0),
		"age": 0.0,
		"pulse_enabled": _rng.randf() < 0.5,
		"pulse_phase": _rng.randf_range(0.0, TAU),
		"pulse_amount": _rng.randf_range(0.03, 0.10),
		"alpha": _rng.randf_range(0.25, 1.0),
		"color": color,
	}


func _update_panes(delta: float) -> void:
	if _bounds.x <= 1.0 or _bounds.y <= 1.0:
		return
	var bpm := float(EmotionalMotionSystem.bpm)
	var bpm_scale := clampf(bpm / 160.0, 0.7, 1.4)
	for i in _active_count:
		var p := _panes[i]
		p["age"] = float(p.get("age", 0.0)) + delta
		if float(p.get("age", 0.0)) >= float(p.get("life", 999.0)):
			_panes[i] = _make_pane(int(p.get("seed", i)))
			continue
		var pos01: Vector2 = p["pos"]
		var vel: Vector2 = p["vel"]
		# Slightly faster baseline drift than before.
		pos01.x += (vel.x * delta * bpm_scale * 1.35) / _bounds.x
		pos01.y += (vel.y * delta * bpm_scale * 1.35) / _bounds.y
		if pos01.x < -0.25:
			pos01.x = 1.25
		if pos01.x > 1.25:
			pos01.x = -0.25
		if pos01.y < -0.25:
			pos01.y = 1.25
		if pos01.y > 1.25:
			pos01.y = -0.25
		p["pos"] = pos01
		p["rot"] = fmod(float(p["rot"]) + delta * float(p["rot_speed"]) * bpm_scale, TAU)
		p["skew_phase"] = fmod(float(p.get("skew_phase", 0.0)) + delta * float(p.get("skew_speed", 0.1)) * bpm_scale, TAU)
		_panes[i] = p


func _draw() -> void:
	if EmotionalMotionSystem == null or not EmotionalMotionSystem.enabled:
		return
	_bounds = _get_bounds_size()
	var combo := float(EmotionalMotionSystem.combo_energy)
	var intensity := float(EmotionalMotionSystem.intensity)
	var style := EmotionalMotionSystem.get_style_multiplier()
	var alpha_base := (0.010 + combo * 0.040 + intensity * 0.020) * style
	alpha_base = clampf(alpha_base, 0.0, 0.10)

	for i in _active_count:
		var p := _panes[i]
		var pos01: Vector2 = p["pos"]
		var center := Vector2(pos01.x * _bounds.x, pos01.y * _bounds.y)
		var size: Vector2 = p["size"]
		var skew: Vector2 = p["skew"]
		# Transform over time (skew wobble + optional pulse scale).
		var bpm := float(EmotionalMotionSystem.bpm)
		var beat := sin(_time * (bpm / 60.0) * TAU) * 0.5 + 0.5
		var hit_boost := 0.0
		var imps := EmotionalMotionSystem.get_impulses()
		for imp in imps:
			hit_boost = maxf(hit_boost, float(imp.get("strength", 0.0)))
		hit_boost = clampf(hit_boost, 0.0, 1.0)
		var sp := float(p.get("skew_phase", 0.0))
		skew += Vector2(sin(sp), cos(sp * 0.8)) * 0.08
		if bool(p.get("pulse_enabled", false)):
			var pphase := float(p.get("pulse_phase", 0.0))
			var pamt := float(p.get("pulse_amount", 0.06))
			var pulse := (sin(pphase + _time * (bpm / 60.0) * TAU) * 0.5 + 0.5)
			pulse = lerpf(pulse, 1.0, hit_boost * 0.35)
			size *= (1.0 + (pulse - 0.5) * 2.0 * pamt)
		var rot := float(p["rot"])

		var base: Color = p.get("color", Color(1, 1, 1, 1))
		base.a = alpha_base * float(p["alpha"])

		var pts := _quad_points(size, skew)
		var out := PackedVector2Array()
		for q in pts:
			out.append(center + q.rotated(rot))

		# Fill.
		draw_colored_polygon(out, base)

		# Soft inner highlight.
		var inner := PackedVector2Array()
		for q in pts:
			inner.append(center + (q * 0.78).rotated(rot))
		var hi := base.lightened(0.10)
		hi.a *= 0.45
		draw_colored_polygon(inner, hi)

		# Thin outline.
		var ol := base.lightened(0.18)
		ol.a *= 0.25
		for j in range(out.size()):
			draw_line(out[j], out[(j + 1) % out.size()], ol, 1.0)


func _quad_points(size: Vector2, skew: Vector2) -> PackedVector2Array:
	var w := size.x * 0.5
	var h := size.y * 0.5
	var sx := w * skew.x
	var sy := h * skew.y
	var pts := PackedVector2Array()
	pts.append(Vector2(-w + sx, -h))
	pts.append(Vector2(w, -h + sy))
	pts.append(Vector2(w - sx, h))
	pts.append(Vector2(-w, h - sy))
	return pts


func _get_bounds_size() -> Vector2:
	var parent := get_parent()
	if parent is Control:
		return (parent as Control).size
	return get_viewport_rect().size
