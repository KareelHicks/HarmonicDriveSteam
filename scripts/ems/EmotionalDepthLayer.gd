extends Node2D

##
# EmotionalDepthLayer
# ------------------
# Adds multiple atmospheric "depth planes" behind gameplay to reduce flat UI feel.
#
# Implementation notes:
# - Draw-only (no shaders/ParticleSystem): uses _draw() for mobile safety.
# - Three depth planes with different motion speeds and BPM response.
# - Shapes are restrained: soft rectangles, silhouettes, drifting fragments.
# - Emotional states affect palette + motion amounts.
#
# Readability rules:
# - Always low opacity.
# - Slow movement, no flashing, no neon spam.
# - Intended to sit behind gameplay lanes/notes (inside EmotionalMotionLayer).
##

const STATE_NEUTRAL := "neutral"
const STATE_EUPHORIC := "euphoric"
const STATE_MELANCHOLIC := "melancholic"
const STATE_CHAOS := "chaos"

const PLANE_FAR := 0
const PLANE_MID := 1
const PLANE_NEAR := 2

const MAX_SHAPES_DESKTOP := 26
const MAX_SHAPES_MOBILE := 14

var parallax_enabled := true

const MOTION_LINEAR := 0
const MOTION_ORBIT := 1
const MOTION_ZIGZAG := 2
const MOTION_LISSAJOUS := 3
const MOTION_DASH := 4

var _rng := RandomNumberGenerator.new()
var _shapes: Array[Dictionary] = []
var _active_count := 0

var _time := 0.0
var _beat_phase := 0.0
var _smoothed_alpha := 0.0
var _smoothed_pulse := 0.0
var _viewport_size := Vector2(1, 1)

# Smoothed palette transitions.
var _palette_state := STATE_NEUTRAL
var _palette_blend := 1.0
var _silhouette_color := Color(0.07, 0.16, 0.28, 1.0)
var _fragment_color := Color(0.14, 0.28, 0.44, 1.0)
var _structure_color := Color(0.09, 0.22, 0.36, 1.0)


func _ready() -> void:
	name = "EmotionalDepthLayer"
	position = Vector2.ZERO
	_rng.randomize()
	_build_shapes()
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
		_smoothed_alpha = 0.0
		queue_redraw()


func ems_on_palette_changed(_ems: Node) -> void:
	# Refresh generated shapes/colors for this run.
	_build_shapes()


func ems_update(_ems: Node, delta: float) -> void:
	if EmotionalMotionSystem == null or not EmotionalMotionSystem.enabled:
		return

	_time += delta
	_viewport_size = _get_bounds_size()

	# Pool sizing based on platform + settings.
	var max_shapes := MAX_SHAPES_DESKTOP
	if AppState != null and AppState.is_mobile_platform():
		max_shapes = MAX_SHAPES_MOBILE
	if ProfileStore != null and ProfileStore.is_prioritize_fps_enabled():
		max_shapes = int(roundi(float(max_shapes) * 0.65))

	var combo := float(EmotionalMotionSystem.combo_energy)
	var intensity := float(EmotionalMotionSystem.intensity)
	var density_ratio := clampf(0.22 + combo * 0.50 + intensity * 0.28, 0.0, 1.0)
	_active_count = clampi(int(roundi(float(max_shapes) * density_ratio)), 0, max_shapes)

	# BPM pulse, but restrained (used as a micro-modulator).
	var bpm := maxf(10.0, float(EmotionalMotionSystem.bpm))
	var beats_per_second := bpm / 60.0
	_beat_phase = fmod(_beat_phase + delta * beats_per_second * TAU, TAU)
	var raw_pulse := sin(_beat_phase) * 0.5 + 0.5
	_smoothed_pulse = lerpf(_smoothed_pulse, raw_pulse, clampf(delta * 1.8, 0.0, 1.0))

	# Alpha scaling: depth should be present but never noisy.
	var base_alpha := 0.006
	var combo_alpha := combo * 0.030
	var pulse_alpha := (_smoothed_pulse - 0.5) * 0.006
	var boost := 1.0
	if EmotionalMotionSystem != null:
		boost = EmotionalMotionSystem.get_visual_boost() * EmotionalMotionSystem.get_style_multiplier()
		boost *= EmotionalMotionSystem.get_loadout_layer_weight("depth", 1.0)
	var target_alpha := (base_alpha + combo_alpha + pulse_alpha) * boost
	_smoothed_alpha = lerpf(_smoothed_alpha, target_alpha, clampf(delta * 1.8, 0.0, 1.0))
	_smoothed_alpha = clampf(_smoothed_alpha, 0.0, 0.11)

	_update_palette(delta)
	_update_shapes(delta)
	queue_redraw()


func _update_palette(delta: float) -> void:
	var desired := STATE_NEUTRAL
	if EmotionalMotionSystem != null:
		desired = str(EmotionalMotionSystem.emotional_state).to_lower()
	if desired != _palette_state:
		_palette_state = desired
		_palette_blend = 0.0
	_palette_blend = clampf(_palette_blend + delta * 0.55, 0.0, 1.0)

	var target := _palette_for_state(_palette_state)
	if EmotionalMotionSystem != null:
		# Pull palette from EMS (random/custom) and let this layer only smooth it.
		target = {
			"silhouette": EmotionalMotionSystem.pick_color("depth_silhouette_%s" % _palette_state, 10),
			"fragment": EmotionalMotionSystem.pick_color("depth_fragment_%s" % _palette_state, 11),
			"structure": EmotionalMotionSystem.pick_color("depth_structure_%s" % _palette_state, 12),
		}
	var t := _palette_blend
	_silhouette_color = _silhouette_color.lerp(target["silhouette"], clampf(t * 0.22, 0.0, 1.0))
	_fragment_color = _fragment_color.lerp(target["fragment"], clampf(t * 0.22, 0.0, 1.0))
	_structure_color = _structure_color.lerp(target["structure"], clampf(t * 0.22, 0.0, 1.0))


func _build_shapes() -> void:
	_shapes.clear()
	for i in MAX_SHAPES_DESKTOP:
		_shapes.append(_make_shape(i))


func _make_shape(seed: int) -> Dictionary:
	# Choose plane & type.
	var plane := PLANE_FAR
	var r := _rng.randf()
	if r < 0.42:
		plane = PLANE_FAR
	elif r < 0.78:
		plane = PLANE_MID
	else:
		plane = PLANE_NEAR

	# Only keep small drifting fragments for now (no large panes/slabs).
	var type := 1

	var base_w := _rng.randf_range(10.0, 42.0)
	var base_h := _rng.randf_range(6.0, 22.0)

	var speed := _rng.randf_range(1.0, 6.0)
	match plane:
		PLANE_FAR:
			speed *= 0.65
		PLANE_MID:
			speed *= 1.0
		PLANE_NEAR:
			speed *= 1.35

	# Random direction from 8-way set (avoid typed-array inference issues).
	var dir8: Vector2 = Vector2.ZERO
	match _rng.randi_range(0, 7):
		0:
			dir8 = Vector2(-1, 0)
		1:
			dir8 = Vector2(1, 0)
		2:
			dir8 = Vector2(0, -1)
		3:
			dir8 = Vector2(0, 1)
		4:
			dir8 = Vector2(-1, -1)
		5:
			dir8 = Vector2(1, -1)
		6:
			dir8 = Vector2(-1, 1)
		_:
			dir8 = Vector2(1, 1)
	dir8 = dir8.normalized()
	var vel: Vector2 = dir8 * speed

	var motion_type := MOTION_LINEAR
	var motion_roll := _rng.randf()
	if motion_roll < 0.60:
		motion_type = MOTION_LINEAR
	elif motion_roll < 0.78:
		motion_type = MOTION_ZIGZAG
	elif motion_roll < 0.92:
		motion_type = MOTION_ORBIT
	elif motion_roll < 0.97:
		motion_type = MOTION_DASH
	else:
		motion_type = MOTION_LISSAJOUS

	var orbit_center := Vector2(_rng.randf(), _rng.randf())
	var orbit_radius := _rng.randf_range(0.04, 0.14)
	var orbit_angle := _rng.randf_range(0.0, TAU)
	var orbit_ang_vel := _rng.randf_range(-0.22, 0.22)
	var drift_vel := Vector2(_rng.randf_range(-0.05, 0.05), _rng.randf_range(-0.05, 0.05))
	var zig_amp := _rng.randf_range(0.02, 0.12)
	var zig_freq := _rng.randf_range(0.25, 1.05)
	var zig_phase := _rng.randf_range(0.0, TAU)
	var lissa_a := _rng.randf_range(0.6, 2.0)
	var lissa_b := _rng.randf_range(0.6, 2.0)
	var lissa_speed := _rng.randf_range(0.05, 0.16)
	var pulse_enabled := _rng.randf() < 0.5
	var pulse_phase := _rng.randf_range(0.0, TAU)
	var pulse_amount := _rng.randf_range(0.03, 0.10)
	var life := _rng.randf_range(3.5, 9.0)
	if motion_type == MOTION_DASH:
		# Fast crossers: short lived and clearly moving.
		life = _rng.randf_range(0.9, 2.2)
		speed *= _rng.randf_range(2.8, 4.2)

	return {
		"plane": plane,
		"type": type,
		"pos": Vector2(_rng.randf(), _rng.randf()),
		"orbit_center": orbit_center,
		"orbit_radius": orbit_radius,
		"orbit_angle": orbit_angle,
		"orbit_ang_vel": orbit_ang_vel,
		"drift_vel": drift_vel,
		"vel": vel,
		"motion_type": motion_type,
		"life": life,
		"age": 0.0,
		"pulse_enabled": pulse_enabled,
		"pulse_phase": pulse_phase,
		"pulse_amount": pulse_amount,
		"zig_amp": zig_amp,
		"zig_freq": zig_freq,
		"zig_phase": zig_phase,
		"lissa_a": lissa_a,
		"lissa_b": lissa_b,
		"lissa_speed": lissa_speed,
		"size": Vector2(base_w, base_h),
		"seed": seed,
		"alpha": _rng.randf_range(0.25, 1.0),
		"wobble": _rng.randf_range(0.03, 0.14),
	}


func _update_shapes(delta: float) -> void:
	if _viewport_size.x <= 1.0 or _viewport_size.y <= 1.0:
		return

	var bpm := maxf(10.0, float(EmotionalMotionSystem.bpm))
	var pulse_speed := clampf(bpm / 140.0, 0.6, 1.6)
	var state := str(EmotionalMotionSystem.emotional_state).to_lower()
	var behavior := _behavior_for_state(state)

	for i in _active_count:
		var s := _shapes[i]
		var pos01: Vector2 = s["pos"]
		var vel: Vector2 = s["vel"]
		var plane: int = int(s["plane"])
		var wobble: float = float(s["wobble"])
		var motion_type: int = int(s.get("motion_type", MOTION_LINEAR))
		s["age"] = float(s.get("age", 0.0)) + delta
		if float(s.get("age", 0.0)) >= float(s.get("life", 999.0)):
			# Respawn to keep variety without allocations.
			_shapes[i] = _make_shape(int(s.get("seed", i)))
			continue

		var plane_scale := 1.0
		match plane:
			PLANE_FAR:
				plane_scale = 0.75
			PLANE_MID:
				plane_scale = 1.0
			PLANE_NEAR:
				plane_scale = 1.22

		var bpm_scale := 0.90 + pulse_speed * 0.10
		var state_scale := float(behavior.get("speed_scale", 1.0))
		# Increase baseline motion while keeping it cinematic.
		var speed_scale := (bpm_scale * plane_scale * state_scale) * 1.35

		match motion_type:
			MOTION_ORBIT:
				var center01: Vector2 = s["orbit_center"]
				var radius: float = float(s["orbit_radius"])
				var angle: float = float(s["orbit_angle"])
				var ang_vel: float = float(s["orbit_ang_vel"])
				angle = fmod(angle + delta * ang_vel * speed_scale, TAU)
				center01 += (s["drift_vel"] as Vector2) * delta * (0.18 + speed_scale * 0.10)
				center01.x = fmod(center01.x + 1.0, 1.0)
				center01.y = fmod(center01.y + 1.0, 1.0)
				pos01 = center01 + Vector2(cos(angle), sin(angle)) * radius
				s["orbit_center"] = center01
				s["orbit_angle"] = angle
			MOTION_ZIGZAG:
				var phase := float(s["zig_phase"])
				var amp := float(s["zig_amp"])
				var freq := float(s["zig_freq"])
				phase = fmod(phase + delta * freq * speed_scale, TAU)
				s["zig_phase"] = phase
				var forward := vel * delta * speed_scale
				var side := Vector2(-vel.y, vel.x).normalized() * sin(phase) * amp * delta * 60.0
				var motion := forward + side
				pos01.x += motion.x / _viewport_size.x
				pos01.y += motion.y / _viewport_size.y
			MOTION_LISSAJOUS:
				var a := float(s["lissa_a"])
				var b := float(s["lissa_b"])
				var sp := float(s["lissa_speed"])
				var t := _time * sp * speed_scale + float(s["seed"]) * 0.02
				var base := Vector2(sin(t * a), sin(t * b + 1.4)) * 0.08
				pos01 += base * delta * 10.0
				pos01 += (s["drift_vel"] as Vector2) * delta * 0.12
			MOTION_DASH:
				# Fast crossers: mostly horizontal with slight vertical drift.
				var motion := vel * delta * speed_scale * 1.4
				pos01.x += motion.x / _viewport_size.x
				pos01.y += motion.y / _viewport_size.y
			_:
				var motion := vel * delta * speed_scale
				# Slow sideways sway adds cinematic depth.
				var sway := sin((_time + float(s["seed"])) * wobble) * float(behavior.get("sway_amount", 0.010))
				motion.x += sway * _viewport_size.x
				pos01.x += motion.x / _viewport_size.x
				pos01.y += motion.y / _viewport_size.y

		# Wrap.
		if pos01.y < -0.20:
			pos01.y = 1.20
			pos01.x = fmod(pos01.x + _rng.randf_range(-0.18, 0.18) + 1.0, 1.0)
		if pos01.x < -0.20:
			pos01.x = 1.20
		if pos01.x > 1.20:
			pos01.x = -0.20

		s["pos"] = pos01
		_shapes[i] = s


func _draw() -> void:
	if _active_count <= 0:
		return
	var bounds := _get_bounds_size()
	if bounds.x <= 1.0 or bounds.y <= 1.0:
		return

	var state := STATE_NEUTRAL
	if EmotionalMotionSystem != null:
		state = str(EmotionalMotionSystem.emotional_state).to_lower()
	var behavior := _behavior_for_state(state)
	var bpm := float(EmotionalMotionSystem.bpm) if EmotionalMotionSystem != null else 120.0
	var beat := sin(_time * (bpm / 60.0) * TAU) * 0.5 + 0.5
	var hit_boost := 0.0
	if EmotionalMotionSystem != null:
		var imps := EmotionalMotionSystem.get_impulses()
		for imp in imps:
			hit_boost = maxf(hit_boost, float(imp.get("strength", 0.0)))
	hit_boost = clampf(hit_boost, 0.0, 1.0)

	var parallax := Vector2.ZERO
	if parallax_enabled:
		parallax = _compute_parallax(bounds) * float(behavior.get("parallax_scale", 1.0))

	# Draw far -> mid -> near for clean depth.
	for plane in 3:
		for i in _active_count:
			var s := _shapes[i]
			if int(s["plane"]) != plane:
				continue
			var type: int = int(s["type"])
			var pos01: Vector2 = s["pos"]
			var base_size: Vector2 = s["size"]
			var a_scale: float = float(s["alpha"])
			var seed: float = float(s["seed"])

			var world := Vector2(pos01.x * bounds.x, pos01.y * bounds.y) + parallax * _plane_parallax_multiplier(plane)

			var color: Color = _silhouette_color
			var alpha := _smoothed_alpha * a_scale * _plane_alpha_multiplier(plane)
			# 50% pulse: cheap shared beat with per-shape phase.
			if bool(s.get("pulse_enabled", false)):
				var pphase := float(s.get("pulse_phase", 0.0))
				var pamt := float(s.get("pulse_amount", 0.06))
				var pulse := (sin(pphase + _time * (bpm / 60.0) * TAU) * 0.5 + 0.5)
				pulse = lerpf(pulse, 1.0, hit_boost * 0.35)
				base_size *= (1.0 + (pulse - 0.5) * 2.0 * pamt)

			# Tiny BPM breathing effect (micro brightness).
			var breathe := (_smoothed_pulse - 0.5) * 0.08
			var bright := clampf(1.0 + breathe, 0.95, 1.06)
			color = Color(color.r * bright, color.g * bright, color.b * bright, 1.0)

			match type:
				0:
					color = _silhouette_color
					alpha *= 0.95
					_draw_soft_rect(world, base_size, color, alpha, 0.18)
				1:
					color = _fragment_color
					alpha *= 0.65
					var wob := sin((_time + seed) * 0.9) * 0.20
					var size := Vector2(base_size.x * (1.0 + wob * 0.18), base_size.y)
					_draw_soft_rect(world, size, color, alpha, 0.22)
				2:
					color = _structure_color
					alpha *= 0.55
					_draw_structure(world, base_size, color, alpha)


func _draw_soft_rect(center: Vector2, size: Vector2, color: Color, alpha: float, edge_softness: float) -> void:
	alpha = clampf(alpha, 0.0, 0.060)
	var c := color
	c.a = alpha
	draw_rect(Rect2(center - size * 0.5, size), c, true)
	# A second slightly larger rect at lower alpha fakes softness.
	var outer := size * (1.0 + edge_softness)
	c.a = alpha * 0.42
	draw_rect(Rect2(center - outer * 0.5, outer), c, true)
	# A faint inner gradient feel (smaller rect, slightly higher alpha).
	var inner := size * 0.78
	c.a = alpha * 0.55
	draw_rect(Rect2(center - inner * 0.5, inner), c, true)


func _draw_structure(center: Vector2, size: Vector2, color: Color, alpha: float) -> void:
	alpha = clampf(alpha, 0.0, 0.060)
	var c := color
	c.a = alpha * 0.70
	draw_rect(Rect2(center - size * 0.5, size), c, true)
	# Inner cut (simulated by drawing a smaller darker rect).
	var inner := size * 0.78
	var inner_color := color.darkened(0.25)
	inner_color.a = alpha * 0.35
	draw_rect(Rect2(center - inner * 0.5, inner), inner_color, true)
	# Thin "frame" highlight.
	var frame := size * 0.92
	var frame_color := color.lightened(0.10)
	frame_color.a = alpha * 0.18
	draw_rect(Rect2(center - frame * 0.5, frame), frame_color, false, 1.0)


func _plane_alpha_multiplier(plane: int) -> float:
	match plane:
		PLANE_FAR:
			return 0.62
		PLANE_MID:
			return 0.80
		_:
			return 0.95


func _plane_parallax_multiplier(plane: int) -> float:
	match plane:
		PLANE_FAR:
			return 0.45
		PLANE_MID:
			return 0.70
		_:
			return 1.00


func _get_bounds_size() -> Vector2:
	var parent := get_parent()
	if parent is Control:
		return (parent as Control).size
	return get_viewport_rect().size


func _compute_parallax(_bounds: Vector2) -> Vector2:
	var vp := get_viewport_rect().size
	var center_vp := vp * 0.5
	var m := center_vp
	if get_viewport() != null:
		m = get_viewport().get_mouse_position()
	var denom := Vector2(maxf(1.0, center_vp.x), maxf(1.0, center_vp.y))
	var norm := Vector2((m.x - center_vp.x) / denom.x, (m.y - center_vp.y) / denom.y)
	var drift := Vector2(sin(_time * 0.07), cos(_time * 0.06)) * 0.30
	norm = norm * 0.30 + drift
	return norm * 12.0


func _behavior_for_state(state: String) -> Dictionary:
	match state:
		STATE_EUPHORIC:
			return {"speed_scale": 1.10, "sway_amount": 0.012, "parallax_scale": 1.05}
		STATE_MELANCHOLIC:
			return {"speed_scale": 0.92, "sway_amount": 0.008, "parallax_scale": 0.95}
		STATE_CHAOS:
			# Still cinematic/slow: "chaos" is only slightly more alive.
			return {"speed_scale": 1.18, "sway_amount": 0.014, "parallax_scale": 1.10}
		_:
			return {"speed_scale": 1.00, "sway_amount": 0.010, "parallax_scale": 1.00}


func _palette_for_state(state: String) -> Dictionary:
	# Palettes are intentionally low-saturation, but must not read as "black boxes".
	# Keep them closer to the game's ambient blues with gentle tint shifts per state.
	match state:
		STATE_EUPHORIC:
			return {
				"silhouette": Color(0.10, 0.26, 0.44, 1.0),
				"fragment": Color(0.18, 0.48, 0.70, 1.0),
				"structure": Color(0.12, 0.34, 0.56, 1.0),
			}
		STATE_MELANCHOLIC:
			return {
				"silhouette": Color(0.08, 0.14, 0.26, 1.0),
				"fragment": Color(0.12, 0.24, 0.40, 1.0),
				"structure": Color(0.09, 0.18, 0.32, 1.0),
			}
		STATE_CHAOS:
			# Slightly more contrast, still restrained.
			return {
				"silhouette": Color(0.10, 0.18, 0.34, 1.0),
				"fragment": Color(0.22, 0.34, 0.72, 1.0),
				"structure": Color(0.12, 0.22, 0.46, 1.0),
			}
		_:
			return {
				"silhouette": Color(0.09, 0.20, 0.36, 1.0),
				"fragment": Color(0.14, 0.32, 0.52, 1.0),
				"structure": Color(0.10, 0.26, 0.44, 1.0),
			}
