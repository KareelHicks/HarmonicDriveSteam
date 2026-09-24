extends Control

##
# EmotionalGradientLayer
# ---------------------
# Lightweight animated gradient atmosphere layer.
#
# Goals:
# - Slow vertical gradients with subtle drift and depth (2 stacked passes).
# - BPM-reactive pulse modulation (soft, never flashing).
# - Opacity scaling from combo_energy (via EmotionalMotionSystem).
# - Emotional states (neutral/euphoric/melancholic/chaos) affect palette + motion.
#
# Constraints:
# - Must render behind gameplay lanes/notes.
# - Must keep readability: low alpha and slow motion.
# - Must be mobile-safe: no shaders/particles; minimal per-frame work.
##

const STATE_NEUTRAL := "neutral"
const STATE_EUPHORIC := "euphoric"
const STATE_MELANCHOLIC := "melancholic"
const STATE_CHAOS := "chaos"

const VALID_STATES := [STATE_NEUTRAL, STATE_EUPHORIC, STATE_MELANCHOLIC, STATE_CHAOS]

@onready var _pass_a := TextureRect.new()
@onready var _pass_b := TextureRect.new()

var _grad_a := Gradient.new()
var _grad_b := Gradient.new()
var _tex_a := GradientTexture2D.new()
var _tex_b := GradientTexture2D.new()

var _time := 0.0
var _beat_phase := 0.0
var _fusion_impulse := 0.0

var _current_state := STATE_NEUTRAL
var _state_blend := 1.0

# Smoothed outputs
var _smoothed_alpha := 0.0
var _smoothed_pulse := 0.0

# Smoothed color endpoints (top/bottom for each pass)
var _a_top := Color(0.10, 0.22, 0.45, 1.0)
var _a_bottom := Color(0.02, 0.05, 0.12, 1.0)
var _b_top := Color(0.06, 0.14, 0.26, 1.0)
var _b_bottom := Color(0.01, 0.03, 0.08, 1.0)


func _ready() -> void:
	name = "EmotionalGradientLayer"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	set_anchors_preset(PRESET_FULL_RECT)

	_setup_pass(_pass_a, _grad_a, _tex_a, 0.55)
	_setup_pass(_pass_b, _grad_b, _tex_b, 0.45)

	_apply_palette_targets(STATE_NEUTRAL, true)

	if EmotionalMotionSystem != null:
		EmotionalMotionSystem.register_layer(self)
		_current_state = str(EmotionalMotionSystem.emotional_state)

	set_process(true)


func _exit_tree() -> void:
	if EmotionalMotionSystem != null:
		EmotionalMotionSystem.unregister_layer(self)


func ems_on_enabled_changed(is_enabled: bool) -> void:
	visible = is_enabled
	set_process(is_enabled)
	if not is_enabled:
		_fusion_impulse = 0.0
		_pass_a.modulate.a = 0.0
		_pass_b.modulate.a = 0.0


func ems_on_impulse(_ems: Node, impulse: Dictionary) -> void:
	if not _is_psychedelic_background():
		return
	_fusion_impulse = clampf(maxf(_fusion_impulse, float(impulse.get("strength", 0.6))), 0.0, 1.0)


func ems_update(_ems: Node, delta: float) -> void:
	if EmotionalMotionSystem == null or not EmotionalMotionSystem.enabled:
		return

	_time += delta
	var impulse_decay := 1.25 if _prioritize_fps() else 0.85
	_fusion_impulse = maxf(0.0, _fusion_impulse - delta * impulse_decay)

	# --- Emotional state transitions (smoothed) ---
	var desired_state := str(EmotionalMotionSystem.emotional_state).to_lower()
	if not VALID_STATES.has(desired_state):
		desired_state = STATE_NEUTRAL
	if desired_state != _current_state:
		_current_state = desired_state
		_state_blend = 0.0

	_state_blend = clampf(_state_blend + delta * 0.6, 0.0, 1.0) # slow palette transition
	_apply_palette_targets(_current_state, false)

	# --- BPM pulse (soft, never flashy) ---
	var bpm := maxf(10.0, float(EmotionalMotionSystem.bpm))
	var beats_per_second := bpm / 60.0
	_beat_phase = fmod(_beat_phase + delta * beats_per_second * TAU, TAU)
	var raw_pulse := sin(_beat_phase) * 0.5 + 0.5
	_smoothed_pulse = lerpf(_smoothed_pulse, raw_pulse, clampf(delta * 2.0, 0.0, 1.0))

	# --- Alpha driven by combo_energy (and EMS intensity) ---
	var combo := float(EmotionalMotionSystem.combo_energy)
	var intensity := float(EmotionalMotionSystem.intensity)
	var base_alpha := 0.008
	var combo_alpha := combo * 0.050
	var intensity_alpha := intensity * 0.020
	var pulse_alpha := (_smoothed_pulse - 0.5) * 0.010 # very subtle
	var boost := 1.0
	if EmotionalMotionSystem != null:
		boost = EmotionalMotionSystem.get_visual_boost() * EmotionalMotionSystem.get_style_multiplier()
		boost *= EmotionalMotionSystem.get_loadout_layer_weight("gradient", 1.0)
	var target_alpha := (base_alpha + combo_alpha + intensity_alpha + pulse_alpha) * boost
	var is_psychedelic := _is_psychedelic_background()
	if is_psychedelic:
		var brightness_scale := sqrt(clampf(float(EmotionalMotionSystem.background_brightness), 0.0, 1.0))
		var fps_alpha_scale := 0.72 if _prioritize_fps() else 1.0
		target_alpha *= 1.55 * brightness_scale * fps_alpha_scale

	_smoothed_alpha = lerpf(_smoothed_alpha, target_alpha, clampf(delta * 2.2, 0.0, 1.0))
	_smoothed_alpha = clampf(_smoothed_alpha, 0.0, 0.22 if is_psychedelic else 0.16)

	# --- Motion (hypnotic) ---
	var behavior := _behavior_for_state(_current_state)
	var drift_speed := float(behavior.get("drift_speed", 4.0))
	var wobble_speed := float(behavior.get("wobble_speed", 0.12))
	var wobble_amount := float(behavior.get("wobble_amount", 0.10))
	if is_psychedelic:
		var fps_motion_scale := 0.66 if _prioritize_fps() else 1.0
		var energy := clampf((combo * 0.55) + (intensity * 0.45), 0.0, 1.0)
		drift_speed = (5.0 + energy * 4.0) * fps_motion_scale
		wobble_speed = (0.18 + energy * 0.10) * fps_motion_scale
		wobble_amount = (0.13 + energy * 0.09) * fps_motion_scale

	# Small diagonal drift by nudging gradient direction.
	var wobble := sin(_time * wobble_speed) * wobble_amount
	_tex_a.fill_from = Vector2(0.20 + wobble, -0.05)
	_tex_a.fill_to = Vector2(0.80 - wobble, 1.05)
	_tex_b.fill_from = Vector2(0.10 - wobble * 0.8, -0.12)
	_tex_b.fill_to = Vector2(0.90 + wobble * 0.8, 1.12)

	# Gentle pass offset drift (wrap) to add depth without extra cost.
	_pass_a.position.y = -fmod(_time * drift_speed, maxf(1.0, size.y * 0.22))
	_pass_b.position.y = -fmod(_time * (drift_speed * 0.65), maxf(1.0, size.y * 0.18))

	# Apply final alpha (keep it behind gameplay/readable).
	if is_psychedelic:
		_pass_a.modulate.a = clampf(_smoothed_alpha * 0.84, 0.0, 0.18)
		_pass_b.modulate.a = clampf(_smoothed_alpha * 0.70, 0.0, 0.15)
	else:
		_pass_a.modulate.a = clampf(_smoothed_alpha * 0.70, 0.0, 0.14)
		_pass_b.modulate.a = clampf(_smoothed_alpha * 0.55, 0.0, 0.12)


func _setup_pass(pass_rect: TextureRect, grad: Gradient, tex: GradientTexture2D, base_scale: float) -> void:
	pass_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pass_rect.set_anchors_preset(PRESET_FULL_RECT)
	pass_rect.stretch_mode = TextureRect.STRETCH_SCALE
	pass_rect.position = Vector2.ZERO
	pass_rect.scale = Vector2(1.0, 1.0 + base_scale) # extra height for drift wrap
	add_child(pass_rect)

	grad.colors = PackedColorArray([Color.BLACK, Color.BLACK])
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	tex.gradient = grad
	tex.width = 256
	tex.height = 256
	tex.fill = GradientTexture2D.FILL_LINEAR
	tex.fill_from = Vector2(0.25, 0.0)
	tex.fill_to = Vector2(0.75, 1.0)
	pass_rect.texture = tex
	pass_rect.modulate = Color(1, 1, 1, 0.0)


func _behavior_for_state(state: String) -> Dictionary:
	match state:
		STATE_EUPHORIC:
			return {"drift_speed": 6.0, "wobble_speed": 0.16, "wobble_amount": 0.12}
		STATE_MELANCHOLIC:
			return {"drift_speed": 3.0, "wobble_speed": 0.10, "wobble_amount": 0.08}
		STATE_CHAOS:
			# Still slow/hypnotic; "chaos" is only slightly more alive, not frantic.
			return {"drift_speed": 7.5, "wobble_speed": 0.20, "wobble_amount": 0.16}
		_:
			return {"drift_speed": 4.5, "wobble_speed": 0.12, "wobble_amount": 0.10}


func _palette_for_state(state: String) -> Dictionary:
	# All palettes are intentionally restrained (no neon rainbow cycling).
	match state:
		STATE_EUPHORIC:
			return {
				"a_top": Color(0.14, 0.40, 0.58, 1.0),
				"a_bottom": Color(0.03, 0.08, 0.16, 1.0),
				"b_top": Color(0.10, 0.28, 0.44, 1.0),
				"b_bottom": Color(0.02, 0.05, 0.12, 1.0),
			}
		STATE_MELANCHOLIC:
			return {
				"a_top": Color(0.10, 0.18, 0.30, 1.0),
				"a_bottom": Color(0.02, 0.04, 0.09, 1.0),
				"b_top": Color(0.07, 0.12, 0.20, 1.0),
				"b_bottom": Color(0.01, 0.03, 0.07, 1.0),
			}
		STATE_CHAOS:
			return {
				"a_top": Color(0.18, 0.26, 0.56, 1.0),
				"a_bottom": Color(0.03, 0.06, 0.14, 1.0),
				"b_top": Color(0.14, 0.18, 0.40, 1.0),
				"b_bottom": Color(0.02, 0.04, 0.10, 1.0),
			}
		_:
			return {
				"a_top": Color(0.10, 0.22, 0.45, 1.0),
				"a_bottom": Color(0.02, 0.05, 0.12, 1.0),
				"b_top": Color(0.06, 0.14, 0.26, 1.0),
				"b_bottom": Color(0.01, 0.03, 0.08, 1.0),
			}


func _apply_palette_targets(state: String, immediate: bool) -> void:
	if _is_psychedelic_background():
		_apply_psychedelic_palette_targets()
		return

	var target_a_top: Color
	var target_a_bottom: Color
	var target_b_top: Color
	var target_b_bottom: Color
	if EmotionalMotionSystem != null:
		# Palette authority lives in EMS (random/custom + emotional hue shift).
		target_a_top = EmotionalMotionSystem.pick_color("grad_a_top_%s" % state, 0)
		target_a_bottom = EmotionalMotionSystem.pick_color("grad_a_bottom_%s" % state, 1)
		target_b_top = EmotionalMotionSystem.pick_color("grad_b_top_%s" % state, 2)
		target_b_bottom = EmotionalMotionSystem.pick_color("grad_b_bottom_%s" % state, 3)
	else:
		var pal := _palette_for_state(state)
		target_a_top = pal["a_top"]
		target_a_bottom = pal["a_bottom"]
		target_b_top = pal["b_top"]
		target_b_bottom = pal["b_bottom"]

	if immediate:
		_a_top = target_a_top
		_a_bottom = target_a_bottom
		_b_top = target_b_top
		_b_bottom = target_b_bottom
	else:
		# Smooth all palette changes.
		var t := clampf(_state_blend, 0.0, 1.0)
		_a_top = _a_top.lerp(target_a_top, t * 0.18)
		_a_bottom = _a_bottom.lerp(target_a_bottom, t * 0.18)
		_b_top = _b_top.lerp(target_b_top, t * 0.18)
		_b_bottom = _b_bottom.lerp(target_b_bottom, t * 0.18)

	# Subtle intra-state color drift (very slow brightness shift, restrained).
	var drift := sin(_time * 0.08) * 0.5 + 0.5
	var lighten := 0.035 * drift
	var darken := 0.025 * (1.0 - drift)
	var a_top_drifted := _a_top.lerp(_a_top.lightened(lighten), 0.25).lerp(_a_top.darkened(darken), 0.15)
	var a_bottom_drifted := _a_bottom.lerp(_a_bottom.lightened(lighten * 0.8), 0.22).lerp(_a_bottom.darkened(darken * 0.9), 0.14)
	var b_top_drifted := _b_top.lerp(_b_top.lightened(lighten * 0.7), 0.20).lerp(_b_top.darkened(darken * 0.9), 0.12)
	var b_bottom_drifted := _b_bottom.lerp(_b_bottom.lightened(lighten * 0.6), 0.18).lerp(_b_bottom.darkened(darken), 0.10)

	_grad_a.colors = PackedColorArray([a_top_drifted, a_bottom_drifted])
	_grad_a.offsets = PackedFloat32Array([0.0, 1.0])
	_grad_b.colors = PackedColorArray([b_top_drifted, b_bottom_drifted])
	_grad_b.offsets = PackedFloat32Array([0.0, 1.0])


func _apply_psychedelic_palette_targets() -> void:
	var stop_count := 4 if _prioritize_fps() else 6
	var offsets := PackedFloat32Array()
	var colors_a := PackedColorArray()
	var colors_b := PackedColorArray()
	var bpm := 120.0
	var combo := 0.0
	var intensity := 0.0
	var brightness := 0.40
	var palette: Array[Color] = []
	if EmotionalMotionSystem != null:
		bpm = maxf(10.0, float(EmotionalMotionSystem.bpm))
		combo = float(EmotionalMotionSystem.combo_energy)
		intensity = float(EmotionalMotionSystem.intensity)
		brightness = clampf(float(EmotionalMotionSystem.background_brightness), 0.0, 1.0)
		palette = EmotionalMotionSystem.get_palette_colors()

	var energy: float = clampf((combo * 0.52) + (intensity * 0.48), 0.0, 1.0)
	var speed_scale: float = 0.64 if _prioritize_fps() else 1.0
	var beats_per_second: float = bpm / 60.0
	var beat: float = sin(_time * beats_per_second * TAU) * 0.5 + 0.5
	var phase: float = fmod(_time * (0.018 + bpm * 0.00005 + energy * 0.014) * speed_scale, 1.0)
	var fusion: float = clampf((sin(_time * (0.20 + energy * 0.08) * speed_scale) * 0.5 + 0.5) * 0.45 + beat * 0.30 + _fusion_impulse * 0.45, 0.0, 1.0)
	var value_scale: float = sqrt(brightness)
	var stop_denom: float = maxf(1.0, float(stop_count - 1))

	for i in range(stop_count):
		var ratio: float = float(i) / stop_denom
		offsets.append(ratio)
		var palette_pos: float = (phase + ratio * (1.0 + fusion * 0.18)) * maxf(1.0, float(palette.size()))
		var idx := int(floor(palette_pos))
		var local_mix: float = palette_pos - floor(palette_pos)
		var wave_a: float = sin(_time * 0.17 * speed_scale + ratio * TAU * 1.45 + _fusion_impulse * TAU) * (0.018 + fusion * 0.035)
		var wave_b: float = cos(_time * 0.13 * speed_scale + ratio * TAU * 1.20 - _fusion_impulse * TAU) * (0.020 + fusion * 0.040)
		var a0 := _psychedelic_palette_color(palette, idx, wave_a, energy, fusion, value_scale)
		var a1 := _psychedelic_palette_color(palette, idx + 1, -wave_a, energy, fusion, value_scale)
		var b0 := _psychedelic_palette_color(palette, idx + 2, wave_b, energy, fusion, value_scale * 0.92)
		var b1 := _psychedelic_palette_color(palette, idx + 3, -wave_b, energy, fusion, value_scale * 0.88)
		var fused_a := a0.lerp(a1, local_mix).lerp(b0, 0.10 + fusion * 0.18)
		var fused_b := b0.lerp(b1, 1.0 - local_mix).lerp(a1, 0.08 + fusion * 0.14)
		colors_a.append(fused_a.lerp(Color(0.02, 0.025, 0.055, 1.0), 0.16))
		colors_b.append(fused_b.lerp(Color(0.01, 0.018, 0.045, 1.0), 0.24))

	_grad_a.colors = colors_a
	_grad_a.offsets = offsets
	_grad_b.colors = colors_b
	_grad_b.offsets = offsets


func _psychedelic_palette_color(palette: Array[Color], index: int, hue_shift: float, energy: float, fusion: float, value_scale: float) -> Color:
	var base := Color(0.15, 0.55, 0.95, 1.0)
	if not palette.is_empty():
		var idx := index % palette.size()
		if idx < 0:
			idx += palette.size()
		base = palette[idx]
	elif EmotionalMotionSystem != null:
		base = EmotionalMotionSystem.pick_color("psychedelic_bg", index)
	var hsv := _rgb_to_hsv(base)
	var hue := fmod(hsv.x + hue_shift, 1.0)
	if hue < 0.0:
		hue += 1.0
	var sat := clampf(maxf(hsv.y, 0.62) + energy * 0.10 + fusion * 0.08, 0.0, 1.0)
	var val := clampf((maxf(hsv.z, 0.55) + energy * 0.12 + fusion * 0.08) * value_scale, 0.0, 0.94)
	return Color.from_hsv(hue, sat, val, 1.0)


func _rgb_to_hsv(color: Color) -> Vector3:
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


func _is_psychedelic_background() -> bool:
	return EmotionalMotionSystem != null and str(EmotionalMotionSystem.background_mode) == "psychedelic"


func _prioritize_fps() -> bool:
	return ProfileStore != null and ProfileStore.is_prioritize_fps_enabled()
