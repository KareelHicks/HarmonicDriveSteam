extends Node2D

##
# EmotionalParticleLayer
# ---------------------
# Lightweight atmospheric particle field for EmotionalMotionSystem.
#
# Design:
# - No ParticleSystem, no shaders: we draw simple shapes in _draw().
# - Small, slow-moving "embers" + "neon fragments" + "haze" dots.
# - Alpha is intentionally low and scaled by combo_energy/intensity.
# - Density scales down on mobile for performance safety.
#
# Constraints:
# - Must never compete with gameplay readability (low opacity, soft motion).
# - Must remain subtle at low intensity (combo_energy near 0).
##

const KIND_EMBER := 0
const KIND_FRAGMENT := 1
const KIND_HAZE := 2

const MAX_PARTICLES_DESKTOP := 56
const MAX_PARTICLES_MOBILE := 26

const PARALLAX_STRENGTH := 10.0

var parallax_enabled := true

const MOTION_LINEAR := 0
const MOTION_ORBIT := 1
const MOTION_ZIGZAG := 2
const MOTION_LISSAJOUS := 3

var _rng := RandomNumberGenerator.new()
var _particles: Array[Dictionary] = []
var _active_count := 0

var _time := 0.0
var _beat_phase := 0.0
var _smoothed_alpha := 0.0
var _smoothed_pulse := 0.0

var _viewport_size := Vector2(1, 1)


func _ready() -> void:
	name = "EmotionalParticleLayer"
	position = Vector2.ZERO
	_rng.randomize()
	_rebuild_pool()
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
	# Refresh per-particle colors for this run.
	_rebuild_pool()


func ems_update(_ems: Node, delta: float) -> void:
	if EmotionalMotionSystem == null or not EmotionalMotionSystem.enabled:
		return

	_time += delta
	_viewport_size = _get_bounds_size()

	# --- Density scaling (mobile safety) ---
	var max_particles := MAX_PARTICLES_DESKTOP
	if AppState != null and AppState.is_mobile_platform():
		max_particles = MAX_PARTICLES_MOBILE
	# Extra safety when the player prioritizes FPS.
	if ProfileStore != null and ProfileStore.is_prioritize_fps_enabled():
		max_particles = int(roundi(float(max_particles) * 0.65))
	var layer_weight := EmotionalMotionSystem.get_loadout_layer_weight("particles", 1.0)
	if layer_weight <= 0.01:
		_active_count = 0
		_smoothed_alpha = 0.0
		queue_redraw()
		return
	if layer_weight < 1.0:
		max_particles = int(roundi(float(max_particles) * layer_weight))

	var combo := float(EmotionalMotionSystem.combo_energy)
	var intensity := float(EmotionalMotionSystem.intensity)
	var density_ratio := clampf(0.18 + combo * 0.62 + intensity * 0.20, 0.0, 1.0)
	var desired := int(roundi(float(max_particles) * density_ratio))
	_active_count = clampi(desired, 0, max_particles)

	# --- BPM pulse (soft) ---
	var bpm := maxf(10.0, float(EmotionalMotionSystem.bpm))
	var beats_per_second := bpm / 60.0
	_beat_phase = fmod(_beat_phase + delta * beats_per_second * TAU, TAU)
	var raw_pulse := sin(_beat_phase) * 0.5 + 0.5
	_smoothed_pulse = lerpf(_smoothed_pulse, raw_pulse, clampf(delta * 2.0, 0.0, 1.0))

	# --- Alpha scaling (never obstruct notes) ---
	var base_alpha := 0.0
	var combo_alpha := combo * 0.045
	var pulse_alpha := (_smoothed_pulse - 0.5) * 0.010
	var boost := 1.0
	if EmotionalMotionSystem != null:
		boost = EmotionalMotionSystem.get_visual_boost() * EmotionalMotionSystem.get_style_multiplier()
	var target_alpha := (base_alpha + combo_alpha + pulse_alpha) * boost * layer_weight
	_smoothed_alpha = lerpf(_smoothed_alpha, target_alpha, clampf(delta * 2.0, 0.0, 1.0))
	_smoothed_alpha = clampf(_smoothed_alpha, 0.0, 0.10)

	_update_particles(delta)
	queue_redraw()


func _rebuild_pool() -> void:
	_particles.clear()
	var capacity := MAX_PARTICLES_DESKTOP
	for i in capacity:
		_particles.append(_make_particle(i))


func _make_particle(seed: int) -> Dictionary:
	var kind := KIND_EMBER
	var roll := _rng.randf()
	if roll < 0.58:
		kind = KIND_EMBER
	elif roll < 0.88:
		kind = KIND_FRAGMENT
	else:
		kind = KIND_HAZE

	var size := 1.5 + _rng.randf() * 2.6
	if kind == KIND_FRAGMENT:
		size = 1.2 + _rng.randf() * 2.2
	if kind == KIND_HAZE:
		size = 6.0 + _rng.randf() * 14.0

	var speed := 4.0 + _rng.randf() * 10.0
	if kind == KIND_FRAGMENT:
		speed = 6.0 + _rng.randf() * 16.0
	if kind == KIND_HAZE:
		speed = 2.0 + _rng.randf() * 5.0

	var motion_type := MOTION_LINEAR
	var motion_roll := _rng.randf()
	if motion_roll < 0.55:
		motion_type = MOTION_LINEAR
	elif motion_roll < 0.72:
		motion_type = MOTION_ZIGZAG
	elif motion_roll < 0.88:
		motion_type = MOTION_ORBIT
	else:
		motion_type = MOTION_LISSAJOUS

	# Base direction can be any of 8 directions (avoid predictable left/right).
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

	# Motion params.
	var orbit_center := Vector2(_rng.randf(), _rng.randf())
	var orbit_radius := _rng.randf_range(0.04, 0.16)
	var orbit_angle := _rng.randf_range(0.0, TAU)
	var orbit_ang_vel := _rng.randf_range(-0.35, 0.35)
	var drift_vel := Vector2(_rng.randf_range(-0.08, 0.08), _rng.randf_range(-0.08, 0.08))

	var zig_amp := _rng.randf_range(0.02, 0.10)
	var zig_freq := _rng.randf_range(0.6, 1.6)
	var zig_phase := _rng.randf_range(0.0, TAU)

	var lissa_a := _rng.randf_range(0.6, 2.2)
	var lissa_b := _rng.randf_range(0.6, 2.2)
	var lissa_speed := _rng.randf_range(0.08, 0.22)

	# Color per particle (palette authority in EMS).
	var base_color := Color(1, 1, 1, 1)
	if EmotionalMotionSystem != null:
		var tag := "particle_ember" if kind == KIND_EMBER else ("particle_fragment" if kind == KIND_FRAGMENT else "particle_haze")
		base_color = EmotionalMotionSystem.pick_color(tag, seed)

	return {
		"kind": kind,
		"pos": Vector2(_rng.randf(), _rng.randf()),
		"orbit_center": orbit_center,
		"orbit_radius": orbit_radius,
		"orbit_angle": orbit_angle,
		"orbit_ang_vel": orbit_ang_vel,
		"drift_vel": drift_vel,
		"vel": vel,
		"motion_type": motion_type,
		"zig_amp": zig_amp,
		"zig_freq": zig_freq,
		"zig_phase": zig_phase,
		"lissa_a": lissa_a,
		"lissa_b": lissa_b,
		"lissa_speed": lissa_speed,
		"color": base_color,
		"size": size,
		"seed": seed,
		"wobble": _rng.randf_range(0.05, 0.22),
		"alpha": _rng.randf_range(0.35, 1.0),
	}


func _update_particles(delta: float) -> void:
	if _viewport_size.x <= 1.0 or _viewport_size.y <= 1.0:
		return

	var bpm := maxf(10.0, float(EmotionalMotionSystem.bpm))
	var pulse_speed := clampf(bpm / 140.0, 0.6, 1.6)

	for i in _active_count:
		var p := _particles[i]
		var pos01: Vector2 = p["pos"]
		var vel: Vector2 = p["vel"]
		var wobble: float = p["wobble"]
		var kind: int = int(p["kind"])
		var motion_type: int = int(p.get("motion_type", MOTION_LINEAR))

		# Subtle BPM influence: slightly faster drift on higher bpm (still slow).
		var speed_scale := 0.85 + pulse_speed * 0.15
		if kind == KIND_HAZE:
			speed_scale = 0.70 + pulse_speed * 0.10
		var motion := Vector2.ZERO

		match motion_type:
			MOTION_ORBIT:
				var center01: Vector2 = p["orbit_center"]
				var radius: float = float(p["orbit_radius"])
				var angle: float = float(p["orbit_angle"])
				var ang_vel: float = float(p["orbit_ang_vel"])
				angle = fmod(angle + delta * ang_vel * speed_scale, TAU)
				center01 += (p["drift_vel"] as Vector2) * delta * (0.25 + speed_scale * 0.15)
				center01.x = fmod(center01.x + 1.0, 1.0)
				center01.y = fmod(center01.y + 1.0, 1.0)
				pos01 = center01 + Vector2(cos(angle), sin(angle)) * radius
				p["orbit_center"] = center01
				p["orbit_angle"] = angle
			MOTION_ZIGZAG:
				var phase := float(p["zig_phase"])
				var amp := float(p["zig_amp"])
				var freq := float(p["zig_freq"])
				phase = fmod(phase + delta * freq * speed_scale, TAU)
				p["zig_phase"] = phase
				var forward := vel * delta * speed_scale
				var side := Vector2(-vel.y, vel.x).normalized() * sin(phase) * amp * delta * 60.0
				motion = forward + side
				pos01.x += motion.x / _viewport_size.x
				pos01.y += motion.y / _viewport_size.y
			MOTION_LISSAJOUS:
				var a := float(p["lissa_a"])
				var b := float(p["lissa_b"])
				var sp := float(p["lissa_speed"])
				var t := _time * sp * speed_scale + float(p["seed"]) * 0.03
				var base := Vector2(sin(t * a), sin(t * b + 1.1)) * 0.10
				pos01 += base * delta * 10.0
				pos01 += (p["drift_vel"] as Vector2) * delta * 0.15
			_:
				motion = vel * delta * speed_scale

				# Hypnotic wobble (tiny sideways sway).
				var sway := sin((_time + float(p["seed"])) * wobble) * 0.010
				motion.x += sway * _viewport_size.x

				# Move in normalized space for cheap wrap.
				pos01.x += motion.x / _viewport_size.x
				pos01.y += motion.y / _viewport_size.y

		# Wrap (keep density stable without respawn spam).
		if pos01.y < -0.10:
			pos01.y = 1.10
			pos01.x = fmod(pos01.x + _rng.randf_range(-0.15, 0.15) + 1.0, 1.0)
		if pos01.y > 1.15:
			pos01.y = -0.10
		if pos01.x < -0.10:
			pos01.x = 1.10
		if pos01.x > 1.10:
			pos01.x = -0.10

		p["pos"] = pos01
		_particles[i] = p


func _draw() -> void:
	if _active_count <= 0:
		return

	var bounds := _get_bounds_size()
	if bounds.x <= 1.0 or bounds.y <= 1.0:
		return

	var parallax := Vector2.ZERO
	if parallax_enabled:
		parallax = _compute_parallax(bounds)

	# Draw haze first (soft), then embers/fragments.
	for draw_pass in 2:
		for i in _active_count:
			var p := _particles[i]
			var kind: int = int(p["kind"])
			if draw_pass == 0 and kind != KIND_HAZE:
				continue
			if draw_pass == 1 and kind == KIND_HAZE:
				continue

			var pos01: Vector2 = p["pos"]
			var size: float = float(p["size"])
			var a_scale: float = float(p["alpha"])

			var world := Vector2(pos01.x * bounds.x, pos01.y * bounds.y) + parallax

			var color: Color = p.get("color", Color(1, 1, 1, 1))
			var alpha := _smoothed_alpha * a_scale
			match kind:
				KIND_FRAGMENT:
					alpha *= 0.85
				KIND_HAZE:
					alpha *= 0.55

			alpha = clampf(alpha, 0.0, 0.055)
			color.a = alpha

			if kind == KIND_FRAGMENT:
				# Small rect shards (soft edges via low alpha).
				var w := size * (1.8 + sin((_time + float(p["seed"])) * 0.9) * 0.25)
				var h := size * 0.75
				draw_rect(Rect2(world - Vector2(w, h) * 0.5, Vector2(w, h)), color, true)
			else:
				draw_circle(world, size, color)


func _get_bounds_size() -> Vector2:
	# Prefer parent Control size (EmotionalMotionLayer clips to playfield).
	var parent := get_parent()
	if parent is Control:
		return (parent as Control).size
	# Fallback to viewport size.
	return get_viewport_rect().size


func _compute_parallax(bounds: Vector2) -> Vector2:
	# Normalize parallax in viewport space (mouse) then apply as a tiny local offset.
	var vp := get_viewport_rect().size
	var center_vp := vp * 0.5
	var m := center_vp
	if get_viewport() != null:
		m = get_viewport().get_mouse_position()
	var denom := Vector2(maxf(1.0, center_vp.x), maxf(1.0, center_vp.y))
	var norm := Vector2((m.x - center_vp.x) / denom.x, (m.y - center_vp.y) / denom.y)

	# Add gentle time-based drift so mobile (no mouse) still has depth.
	var drift := Vector2(sin(_time * 0.09), cos(_time * 0.08)) * 0.35
	norm = norm * 0.35 + drift
	return norm * PARALLAX_STRENGTH


const STATE_NEUTRAL := "neutral"
const STATE_EUPHORIC := "euphoric"
const STATE_MELANCHOLIC := "melancholic"
const STATE_CHAOS := "chaos"


func _palette_for_state(state: String) -> Dictionary:
	match state:
		STATE_EUPHORIC:
			return {
				"ember": Color(0.20, 0.78, 0.95, 1.0),
				"fragment": Color(0.55, 0.92, 0.70, 1.0),
				"haze": Color(0.10, 0.26, 0.52, 1.0),
			}
		STATE_MELANCHOLIC:
			return {
				"ember": Color(0.55, 0.72, 0.92, 1.0),
				"fragment": Color(0.62, 0.64, 0.88, 1.0),
				"haze": Color(0.06, 0.10, 0.20, 1.0),
			}
		STATE_CHAOS:
			# Still restrained: "chaos" adds slightly brighter accents, not spam.
			return {
				"ember": Color(0.95, 0.55, 0.90, 1.0),
				"fragment": Color(0.40, 0.75, 0.98, 1.0),
				"haze": Color(0.09, 0.14, 0.34, 1.0),
			}
		_:
			return {
				"ember": Color(0.20, 0.78, 0.95, 1.0),
				"fragment": Color(0.60, 0.82, 0.98, 1.0),
				"haze": Color(0.08, 0.16, 0.32, 1.0),
			}
