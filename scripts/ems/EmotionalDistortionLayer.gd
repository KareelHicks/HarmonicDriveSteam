extends ColorRect

##
# EmotionalDistortionLayer
# -----------------------
# Applies a subtle "reality instability" shader to the EMS visuals only.
#
# Critical readability constraint:
# - This shader MUST NOT affect gameplay notes/receptors/HUD.
# - It should only process the EMS SubViewport texture (background ambience).
#
# Effects (lightweight):
# - gentle screen warping
# - subtle chromatic aberration
# - soft blur pulses (very low radius, few taps)
# - bloom modulation (approx via soft highlight lift; not a full bloom)
#
# Intensity drivers:
# - BPM, combo_energy, emotional_state
# - automatic reduction during high note density
##

const STATE_NEUTRAL := "neutral"
const STATE_EUPHORIC := "euphoric"
const STATE_MELANCHOLIC := "melancholic"
const STATE_CHAOS := "chaos"
const PSYCHEDELIC_RIPPLE_SHADER_MULTIPLIER := 3.0

@export var max_strength := 0.45 # absolute cap for shader strength
@export var smoothing_rate := 2.0

var _material := ShaderMaterial.new()
var _shader := Shader.new()
var _time := 0.0
var _smoothed_strength := 0.0


func _ready() -> void:
	name = "EmotionalDistortionLayer"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	color = Color(1, 1, 1, 1)

	_shader.code = _shader_code()
	_material.shader = _shader
	material = _material

	_material.set_shader_parameter("strength", 0.0)
	_material.set_shader_parameter("time", 0.0)
	_material.set_shader_parameter("warp_amount", 0.0)
	_material.set_shader_parameter("chromatic_amount", 0.0)
	_material.set_shader_parameter("blur_amount", 0.0)
	_material.set_shader_parameter("bloom_amount", 0.0)

	set_process(true)

	# If the texture isn't wired yet, render nothing until it is.
	visible = true


func set_source_texture(texture: Texture2D) -> void:
	_material.set_shader_parameter("source_tex", texture)
	# Sometimes the viewport texture arrives a frame later; ensure redraw.
	queue_redraw()

	if EmotionalMotionSystem != null and EmotionalMotionSystem.debug_logging_enabled:
		print("[EMS][%s] source_tex=%s" % [name, "ok" if texture != null else "null"])


func ems_update(_ems: Node, delta: float) -> void:
	if EmotionalMotionSystem == null or not EmotionalMotionSystem.enabled:
		_smoothed_strength = lerpf(_smoothed_strength, 0.0, clampf(delta * smoothing_rate, 0.0, 1.0))
		_apply_params()
		return

	_time += delta

	var bpm := float(EmotionalMotionSystem.bpm)
	var combo := float(EmotionalMotionSystem.combo_energy)
	var intensity := float(EmotionalMotionSystem.intensity)
	var density := float(EmotionalMotionSystem.note_density)
	var state := str(EmotionalMotionSystem.emotional_state).to_lower()

	# Base strength is intentionally conservative.
	var bpm_factor := clampf(bpm / 170.0, 0.6, 1.35)
	var state_mult := _state_multiplier(state)
	var density_reduction := lerpf(1.0, 0.45, clampf(density, 0.0, 1.0))

	var target := (0.06 + combo * 0.22 + intensity * 0.12) * bpm_factor * state_mult * density_reduction
	target *= EmotionalMotionSystem.get_visual_boost() * EmotionalMotionSystem.get_style_multiplier()
	target *= EmotionalMotionSystem.get_loadout_layer_weight("distortion", 1.0)
	target = clampf(target, 0.0, max_strength)

	_smoothed_strength = lerpf(_smoothed_strength, target, clampf(delta * smoothing_rate, 0.0, 1.0))

	_apply_params()


func _state_multiplier(state: String) -> float:
	match state:
		STATE_EUPHORIC:
			return 1.05
		STATE_MELANCHOLIC:
			return 0.92
		STATE_CHAOS:
			return 1.15
		_:
			return 1.00


func _apply_params() -> void:
	_material.set_shader_parameter("time", _time)
	_material.set_shader_parameter("strength", _smoothed_strength)

	# Split strength into component contributions (all subtle).
	var warp := clampf(_smoothed_strength * 0.55, 0.0, 0.22)
	var chroma := clampf(_smoothed_strength * 0.42, 0.0, 0.18)
	var blur := clampf(_smoothed_strength * 0.40, 0.0, 0.16)
	var bloom := clampf(_smoothed_strength * 0.35, 0.0, 0.14)
	if _is_psychedelic_background_mode():
		warp = clampf(warp * PSYCHEDELIC_RIPPLE_SHADER_MULTIPLIER, 0.0, 0.66)
		chroma = clampf(chroma * PSYCHEDELIC_RIPPLE_SHADER_MULTIPLIER, 0.0, 0.54)
		blur = clampf(blur * PSYCHEDELIC_RIPPLE_SHADER_MULTIPLIER, 0.0, 0.48)
		bloom = clampf(bloom * PSYCHEDELIC_RIPPLE_SHADER_MULTIPLIER, 0.0, 0.42)
	if ProfileStore != null:
		if not ProfileStore.is_visual_effect_distortion_enabled():
			warp = 0.0
			chroma = 0.0
			blur = 0.0
		if not ProfileStore.is_visual_effect_bloom_enabled():
			bloom = 0.0

	_material.set_shader_parameter("warp_amount", warp)
	_material.set_shader_parameter("chromatic_amount", chroma)
	_material.set_shader_parameter("blur_amount", blur)
	_material.set_shader_parameter("bloom_amount", bloom)


func _is_psychedelic_background_mode() -> bool:
	return EmotionalMotionSystem != null and str(EmotionalMotionSystem.background_mode) == "psychedelic"


func _shader_code() -> String:
	# CanvasItem shader (fast path on mobile renderer).
	return """
shader_type canvas_item;

uniform sampler2D source_tex : source_color;
uniform float time = 0.0;
uniform float strength = 0.0;
uniform float warp_amount = 0.0;
uniform float chromatic_amount = 0.0;
uniform float blur_amount = 0.0;
uniform float bloom_amount = 0.0;

// Tiny noise from UV + time (no textures).
float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 uv = UV;

	// Gentle warp (slow, cinematic).
	float n = hash(uv * 2.3 + time * 0.03);
	float wave_x = sin((uv.y * 6.0) + time * 0.45) * 0.5 + 0.5;
	float wave_y = sin((uv.x * 5.0) + time * 0.38) * 0.5 + 0.5;
	vec2 warp = vec2((wave_x - 0.5) + (n - 0.5) * 0.35, (wave_y - 0.5) * 0.7) * warp_amount * 0.010;
	vec2 wuv = uv + warp;

	// Chromatic aberration (subtle).
	vec2 ca = vec2(0.0015, 0.0010) * chromatic_amount;
	vec4 c_r = texture(source_tex, wuv + ca);
	vec4 c_g = texture(source_tex, wuv);
	vec4 c_b = texture(source_tex, wuv - ca);
	vec4 col = vec4(c_r.r, c_g.g, c_b.b, c_g.a);

	// Soft blur pulse (4 taps max).
	vec2 px = TEXTURE_PIXEL_SIZE;
	vec2 o = px * (1.0 + blur_amount * 3.0);
	vec4 blur_col =
		texture(source_tex, wuv + vec2(o.x, 0.0)) +
		texture(source_tex, wuv + vec2(-o.x, 0.0)) +
		texture(source_tex, wuv + vec2(0.0, o.y)) +
		texture(source_tex, wuv + vec2(0.0, -o.y));
	blur_col *= 0.25;
	col = mix(col, blur_col, blur_amount * 0.35);

	// Bloom modulation (approx): lift bright areas slightly.
	float luma = dot(col.rgb, vec3(0.299, 0.587, 0.114));
	float lift = smoothstep(0.55, 0.90, luma) * bloom_amount * 0.25;
	col.rgb += lift;

	// Overall strength (allows turning everything down together).
	col = mix(texture(source_tex, uv), col, strength);

	COLOR = col;
}
"""
