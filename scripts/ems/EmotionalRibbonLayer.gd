extends Node2D

##
# EmotionalRibbonLayer
# -------------------
# Slow drifting ribbon curves (polylines) to add trippy motion without particles.
##

const MAX_RIBBONS_DESKTOP := 4
const MAX_RIBBONS_MOBILE := 2

var _rng := RandomNumberGenerator.new()
var _ribbons: Array[Dictionary] = []
var _time := 0.0
var _bounds := Vector2(1, 1)

# Chart-synced impulse response (from EMS.notify_judgement -> ems_on_impulse)
# Kept intentionally lightweight: single smoothed "kick" + localized bump around y_norm.
var _impulse_kick := 0.0
var _impulse_kick_target := 0.0
var _impulse_y_norm := 0.86
var _impulse_y_target := 0.86
var _impulse_color: Color = Color.WHITE


func _ready() -> void:
	name = "EmotionalRibbonLayer"
	_rng.randomize()
	_build_ribbons()
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
		_impulse_kick = 0.0
		_impulse_kick_target = 0.0
		queue_redraw()

func ems_on_impulse(_ems: Node, impulse: Dictionary) -> void:
	if EmotionalMotionSystem == null or not EmotionalMotionSystem.enabled:
		return

	var strength := clampf(float(impulse.get("strength", 0.5)), 0.0, 1.0)
	# Combine fast impulses; do not allocate per-note data.
	_impulse_kick_target = clampf(maxf(_impulse_kick_target, strength), 0.0, 1.0)

	var y_norm := clampf(float(impulse.get("y_norm", _impulse_y_target)), 0.0, 1.0)
	_impulse_y_target = y_norm

	var c: Color = impulse.get("color", _impulse_color)
	_impulse_color = c


func ems_update(_ems: Node, delta: float) -> void:
	if EmotionalMotionSystem == null or not EmotionalMotionSystem.enabled:
		return
	_time += delta
	_bounds = _get_bounds_size()

	# Smooth kick + decay to keep the motion hypnotic (no flashing).
	var kick_in := 1.0 - exp(-delta * 14.0)
	var kick_out := 1.0 - exp(-delta * 3.0)
	_impulse_kick = lerpf(_impulse_kick, _impulse_kick_target, kick_in)
	_impulse_kick_target = lerpf(_impulse_kick_target, 0.0, kick_out)
	_impulse_y_norm = lerpf(_impulse_y_norm, _impulse_y_target, 1.0 - exp(-delta * 10.0))

	queue_redraw()


func _build_ribbons() -> void:
	_ribbons.clear()
	var count := MAX_RIBBONS_DESKTOP
	if AppState != null and AppState.is_mobile_platform():
		count = MAX_RIBBONS_MOBILE
	for i in count:
		_ribbons.append({
			"seed": i,
			"phase": _rng.randf_range(0.0, TAU),
			"freq": _rng.randf_range(0.8, 1.8),
			"amp": _rng.randf_range(0.06, 0.18),
			"speed": _rng.randf_range(0.05, 0.16),
			"width": _rng.randf_range(2.0, 5.0),
			"x_base": _rng.randf_range(0.15, 0.85),
		})


func _draw() -> void:
	if EmotionalMotionSystem == null or not EmotionalMotionSystem.enabled:
		return
	_bounds = _get_bounds_size()
	if _bounds.x <= 1.0 or _bounds.y <= 1.0:
		return

	var combo := float(EmotionalMotionSystem.combo_energy)
	var intensity := float(EmotionalMotionSystem.intensity)
	var style := EmotionalMotionSystem.get_style_multiplier()
	var layer_weight := EmotionalMotionSystem.get_loadout_layer_weight("ribbon", 1.0)
	if layer_weight <= 0.01:
		return
	style *= layer_weight
	var bpm := float(EmotionalMotionSystem.bpm)
	var bpm_scale := clampf(bpm / 160.0, 0.7, 1.4)

	var alpha := (0.018 + combo * 0.05 + intensity * 0.03) * style
	alpha = clampf(alpha, 0.0, 0.12)

	# Impulse reaction (chart-synced): brief amplitude + thickness boost, with a localized bump around the impulse y.
	# Keep the effect subtle at low style levels.
	var kick := clampf(_impulse_kick, 0.0, 1.0)
	var kick_amp_mul := 1.0 + kick * (0.85 * style)
	var kick_width_mul := 1.0 + kick * (0.55 * style)
	var kick_alpha_add := kick * (0.020 * style)
	var bump_sigma := lerpf(0.10, 0.05, clampf(style / 1.6, 0.0, 1.0)) # narrower at "max"

	for r in _ribbons:
		var seed := int(r["seed"])
		# Speed up vertical wave travel slightly (user request: +35%).
		var phase := float(r["phase"]) + _time * float(r["speed"]) * 1.35 * bpm_scale
		var freq := float(r["freq"])
		var amp := float(r["amp"]) * kick_amp_mul
		var width := float(r["width"]) * kick_width_mul
		var x_base := float(r["x_base"])

		# Keep ribbons colorful; heavy white/black lerps tend to wash out into gray.
		var c1 := EmotionalMotionSystem.pick_color("ribbon_a", seed).lerp(Color.WHITE, 0.03)
		var c2 := EmotionalMotionSystem.pick_color("ribbon_b", seed + 100).lerp(Color.BLACK, 0.03)
		# Briefly tint brighter toward the judgement color on hits.
		c1 = c1.lerp(_impulse_color, kick * 0.35)
		c2 = c2.lerp(_impulse_color, kick * 0.20)

		# Polyline down the gutter.
		var points: PackedVector2Array = []
		var segments := 18
		for i in segments + 1:
			var t := float(i) / float(segments)
			var y := t * _bounds.y

			# Localized bump around the hit y to feel chart-synced (still cheap: few ribbons * few segments).
			var dy := (t - _impulse_y_norm) / maxf(0.0001, bump_sigma)
			var bump := exp(-dy * dy) * kick * 0.85

			var wob := sin(phase + t * TAU * freq) * amp
			var wob2 := sin(phase * 0.8 + t * TAU * (freq * 0.6) + 1.7) * amp * 0.6
			var x := (x_base + wob + wob2) * _bounds.x
			# Bump pushes slightly inward/outward to look like a vertical "wave" response.
			var bump_dir := -1.0 if x_base < 0.5 else 1.0
			x += bump * bump_dir * _bounds.x * 0.05
			points.append(Vector2(x, y))

		# Draw as colored segments to fake a gradient.
		for i in range(points.size() - 1):
			var t := float(i) / float(points.size() - 2)
			var col := c1.lerp(c2, t)
			col.a = clampf(alpha + kick_alpha_add, 0.0, 0.14)
			draw_line(points[i], points[i + 1], col, width)


func _get_bounds_size() -> Vector2:
	var parent := get_parent()
	if parent is Control:
		return (parent as Control).size
	return get_viewport_rect().size
