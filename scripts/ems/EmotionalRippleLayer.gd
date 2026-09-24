extends Node2D

##
# EmotionalRippleLayer
# -------------------
# Chart-synced expanding ring ripples driven by EMS judgement impulses.
# Runs inside a gutter-sized EmotionalMotionLayer viewport (never over lanes).
##

const MAX_RIPPLES_DESKTOP := 20
const MAX_RIPPLES_MOBILE := 10
const RIPPLE_MIN_SATURATION := 0.74
const RIPPLE_MIN_VALUE := 0.70

@export var placement := "hitline" # "hitline" | "top"
@export var gutter_side := "left" # "left" | "right" (set by EmotionalMotionLayer)

var _ripples: Array[Dictionary] = []
var _time := 0.0
var _bounds := Vector2(1, 1)


func _ready() -> void:
	name = "EmotionalRippleLayer"
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
		_ripples.clear()
		queue_redraw()


func ems_on_impulse(_ems: Node, impulse: Dictionary) -> void:
	if EmotionalMotionSystem == null or not EmotionalMotionSystem.enabled:
		return
	_bounds = _get_bounds_size()
	var max_ripples := MAX_RIPPLES_DESKTOP
	if AppState != null and AppState.is_mobile_platform():
		max_ripples = MAX_RIPPLES_MOBILE
	if ProfileStore != null and ProfileStore.is_prioritize_fps_enabled():
		max_ripples = int(roundi(float(max_ripples) * 0.7))
	var layer_weight := EmotionalMotionSystem.get_loadout_layer_weight("ripple", 1.0)
	if layer_weight <= 0.01:
		return
	if layer_weight < 1.0:
		max_ripples = int(roundi(float(max_ripples) * layer_weight))

	var y_norm := clampf(float(impulse.get("y_norm", 0.86)), 0.0, 1.0)
	var y := y_norm * _bounds.y
	if placement == "top":
		# Compress into the top band; still reflects chart timing, but stays up top.
		y = lerpf(_bounds.y * 0.06, _bounds.y * 0.28, clampf(y_norm, 0.0, 1.0))

	# Place near the inner edge of the gutter to feel "under" the playfield.
	var inner_x := _bounds.x * 0.92 if gutter_side == "left" else _bounds.x * 0.08
	var x := lerpf(inner_x, _bounds.x * (0.35 if gutter_side == "left" else 0.65), 0.15)
	var strength := clampf(float(impulse.get("strength", 0.6)), 0.0, 1.0)

	var c := _resolve_ripple_color(impulse)

	_ripples.append({
		"pos": Vector2(x, y),
		"age": 0.0,
		"ttl": 1.15 + strength * 0.55,
		"start_r": 10.0 + strength * 18.0,
		"end_r": 120.0 + strength * 240.0,
		"color": c,
		"strength": strength,
	})
	if _ripples.size() > max_ripples:
		_ripples.remove_at(0)


func ems_update(_ems: Node, delta: float) -> void:
	if EmotionalMotionSystem == null or not EmotionalMotionSystem.enabled:
		return
	_time += delta
	_bounds = _get_bounds_size()
	for i in range(_ripples.size() - 1, -1, -1):
		var r := _ripples[i]
		r["age"] = float(r["age"]) + delta
		if float(r["age"]) >= float(r["ttl"]):
			_ripples.remove_at(i)
		else:
			_ripples[i] = r
	queue_redraw()


func _draw() -> void:
	if _ripples.is_empty():
		return
	var combo := 0.0
	if EmotionalMotionSystem != null:
		combo = float(EmotionalMotionSystem.combo_energy)
	var alpha_base := (0.034 + combo * 0.075)
	if EmotionalMotionSystem != null:
		var layer_weight := EmotionalMotionSystem.get_loadout_layer_weight("ripple", 1.0)
		if layer_weight <= 0.01:
			return
		alpha_base *= EmotionalMotionSystem.get_style_multiplier() * layer_weight
	alpha_base = clampf(alpha_base, 0.0, 0.16)

	for r in _ripples:
		var age := float(r["age"])
		var ttl := maxf(0.001, float(r["ttl"]))
		var t := clampf(age / ttl, 0.0, 1.0)
		var ease := 1.0 - pow(1.0 - t, 2.0)
		var radius := lerpf(float(r["start_r"]), float(r["end_r"]), ease)
		var c: Color = r["color"]
		var strength := float(r["strength"])
		var base_a := alpha_base * (0.55 + strength * 0.75) * (1.0 - t)
		base_a = clampf(base_a, 0.0, 0.22)

		# --- Glow stack (premium, subtle) ---
		# Outer glow
		var glow: Color = c
		glow.a = base_a * 0.40
		draw_arc(r["pos"], radius * 1.08, 0.0, TAU, 52, glow, 6.0)
		# Mid glow
		glow.a = base_a * 0.55
		draw_arc(r["pos"], radius * 1.03, 0.0, TAU, 52, glow, 3.5)
		# Core ring
		c.a = base_a
		draw_arc(r["pos"], radius, 0.0, TAU, 52, c, 2.0)


func _resolve_ripple_color(impulse: Dictionary) -> Color:
	var lane := int(impulse.get("lane", 0))
	var judgement := str(impulse.get("judgement", "hit")).to_lower()
	var seed := lane + (37 if placement == "top" else 0)
	var c := Color(1, 1, 1, 1)
	var impulse_color: Variant = impulse.get("color", c)
	if impulse_color is Color:
		c = impulse_color

	if EmotionalMotionSystem != null:
		var tagged := EmotionalMotionSystem.pick_color("ripple_%s_%s" % [judgement, placement], seed)
		var palette := _palette_color_for_impulse(judgement, seed)
		c = c.lerp(tagged, 0.55).lerp(palette, 0.30)

	c.a = 1.0
	return _normalize_ripple_color(c)


func _palette_color_for_impulse(judgement: String, seed: int) -> Color:
	if EmotionalMotionSystem == null:
		return Color(1, 1, 1, 1)
	var colors := EmotionalMotionSystem.get_palette_colors()
	if colors.is_empty():
		return EmotionalMotionSystem.pick_color("ripple_palette_%s" % judgement, seed)
	var h := int(hash("ripple_palette_%s_%s" % [judgement, placement])) ^ seed
	var idx := int(abs(h)) % colors.size()
	var c: Color = colors[idx]
	c.a = 1.0
	return c


func _get_bounds_size() -> Vector2:
	var parent := get_parent()
	if parent is Control:
		return (parent as Control).size
	return get_viewport_rect().size


func _normalize_ripple_color(color: Color) -> Color:
	var hsv := _rgb_to_hsv(color)
	var s := clampf(maxf(hsv.y, RIPPLE_MIN_SATURATION), 0.0, 1.0)
	var v := clampf(maxf(hsv.z, RIPPLE_MIN_VALUE), 0.0, 1.0)
	return Color.from_hsv(hsv.x, s, v, color.a)


func _rgb_to_hsv(color: Color) -> Vector3:
	# Returns Vector3(h, s, v) with h in [0..1).
	var r := color.r
	var g := color.g
	var b := color.b
	var c_max := maxf(r, maxf(g, b))
	var c_min := minf(r, minf(g, b))
	var delta := c_max - c_min

	var h := 0.0
	if delta > 0.000001:
		if c_max == r:
			h = fmod(((g - b) / delta), 6.0)
		elif c_max == g:
			h = ((b - r) / delta) + 2.0
		else:
			h = ((r - g) / delta) + 4.0
		h /= 6.0
		if h < 0.0:
			h += 1.0

	var s := 0.0 if c_max <= 0.000001 else (delta / c_max)
	var v := c_max
	return Vector3(h, s, v)
