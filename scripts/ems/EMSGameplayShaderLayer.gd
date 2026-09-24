extends ColorRect
class_name EMSGameplayShaderLayer

##
# EMSGameplayShaderLayer
# ----------------------
# Maximum-mode shader pass for the active playfield.
#
# This layer is intentionally separate from EmotionalMotionLayer, which is
# gutter-only by design. GameScene bounds this ColorRect to the playfield and
# places it after notes/FX but before HUD-heavy UI.
##

@export var smoothing_rate := 3.4

var _material := ShaderMaterial.new()
var _shader := Shader.new()
var _time := 0.0
var _active := false
var _bloom_enabled := true
var _distortion_enabled := true
var _lane_count := 5
var _hit_line_y_norm := 0.86
var _smoothed_intensity := 0.0
var _shockwave_strength := 0.0
var _shockwave_origin := Vector2(0.5, 0.86)
var _shockwave_time := -100.0
var _last_impulse_key := ""


func _ready() -> void:
	name = "EMSGameplayShaderLayer"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	color = Color.WHITE
	_shader.code = _shader_code()
	_material.shader = _shader
	material = _material
	_apply_params(0.0, 0.0, 0.0)
	set_process(false)
	visible = false


func configure_effects(active: bool, bloom_enabled: bool, distortion_enabled: bool) -> void:
	_active = active
	_bloom_enabled = bloom_enabled
	_distortion_enabled = distortion_enabled
	var should_render := _active and (_bloom_enabled or _distortion_enabled)
	set_meta("ems_visual_effect_enabled", should_render)
	visible = should_render
	set_process(should_render)
	if not should_render:
		_smoothed_intensity = 0.0
		_shockwave_strength = 0.0
		_apply_params(0.0, 0.0, 0.0)


func set_playfield_metrics(lane_count: int, hit_line_y_norm: float) -> void:
	_lane_count = maxi(1, lane_count)
	_hit_line_y_norm = clampf(hit_line_y_norm, 0.0, 1.0)


func ems_on_enabled_changed(is_enabled: bool) -> void:
	var should_render := is_enabled and _active and (_bloom_enabled or _distortion_enabled)
	visible = should_render
	set_process(should_render)
	if not should_render:
		_smoothed_intensity = 0.0
		_shockwave_strength = 0.0
		_apply_params(0.0, 0.0, 0.0)


func ems_update(_ems: Node, delta: float) -> void:
	var ems := _ems()
	if not _active or ems == null or not bool(ems.get("enabled")):
		_smoothed_intensity = lerpf(_smoothed_intensity, 0.0, clampf(delta * smoothing_rate, 0.0, 1.0))
		_shockwave_strength = maxf(0.0, _shockwave_strength - delta * 3.6)
		_apply_params(_smoothed_intensity, 0.0, 0.0)
		return

	_time += delta
	_consume_latest_impulse(ems)

	var combo := clampf(float(ems.get("combo_energy")), 0.0, 1.0)
	var intensity := clampf(float(ems.get("intensity")), 0.0, 1.0)
	var density := clampf(float(ems.get("note_density")), 0.0, 1.0)
	var density_reduction := lerpf(1.0, 0.58, density)
	var style := 1.0
	if ems.has_method("get_style_multiplier"):
		style = clampf(float(ems.call("get_style_multiplier")), 0.7, 1.8)
	var layer_weight := 1.0
	if ems.has_method("get_loadout_layer_weight"):
		layer_weight = clampf(float(ems.call("get_loadout_layer_weight", "gameplay_shader", 1.0)), 0.0, 1.35)
	var target := (0.18 + combo * 0.42 + intensity * 0.34) * density_reduction * style
	target *= layer_weight
	target = clampf(target, 0.0, 1.0)
	_smoothed_intensity = lerpf(_smoothed_intensity, target, clampf(delta * smoothing_rate, 0.0, 1.0))
	_shockwave_strength = maxf(0.0, _shockwave_strength - delta * 2.9)

	var bloom := 0.0
	if _bloom_enabled:
		bloom = clampf(_smoothed_intensity * 0.55 + _shockwave_strength * 0.16, 0.0, 0.72)
	var distortion := 0.0
	if _distortion_enabled:
		distortion = clampf(_smoothed_intensity * 0.42 + _shockwave_strength * 0.20, 0.0, 0.62)
	_apply_params(_smoothed_intensity, bloom, distortion)


func _consume_latest_impulse(ems: Node) -> void:
	if not _pressure_hit_effect_active():
		return
	if not ems.has_method("get_impulses"):
		return
	var impulses: Array = ems.call("get_impulses")
	if impulses.is_empty():
		return
	var latest: Dictionary = impulses[impulses.size() - 1]
	var key := "%s:%s:%s" % [
		str(latest.get("song_time", 0.0)),
		str(latest.get("lane", 0)),
		str(latest.get("judgement", "")),
	]
	if key == _last_impulse_key:
		return
	_last_impulse_key = key
	var lane := clampi(int(latest.get("lane", 0)), 0, _lane_count - 1)
	var strength := clampf(float(latest.get("strength", 0.0)), 0.0, 1.0)
	_shockwave_origin = Vector2((float(lane) + 0.5) / float(_lane_count), clampf(float(latest.get("y_norm", _hit_line_y_norm)), 0.0, 1.0))
	_shockwave_time = _time
	_shockwave_strength = maxf(_shockwave_strength, strength)


func _pressure_hit_effect_active() -> bool:
	var ems := _ems()
	if ems != null and ems.has_method("get_effective_hit_effect"):
		return str(ems.call("get_effective_hit_effect")).to_lower() == "pressure"
	var profile := get_node_or_null("/root/ProfileStore")
	return profile != null and profile.has_method("get_ems_hit_effect") and str(profile.call("get_ems_hit_effect")).to_lower() == "pressure"


func _ems() -> Node:
	return get_node_or_null("/root/EmotionalMotionSystem")


func _apply_params(intensity: float, bloom: float, distortion: float) -> void:
	_material.set_shader_parameter("time", _time)
	_material.set_shader_parameter("intensity", intensity)
	_material.set_shader_parameter("bloom_amount", bloom)
	_material.set_shader_parameter("distortion_amount", distortion)
	_material.set_shader_parameter("shockwave_strength", _shockwave_strength)
	_material.set_shader_parameter("shockwave_origin", _shockwave_origin)
	_material.set_shader_parameter("shockwave_time", _shockwave_time)


func _shader_code() -> String:
	return """
shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float time = 0.0;
uniform float intensity = 0.0;
uniform float bloom_amount = 0.0;
uniform float distortion_amount = 0.0;
uniform float shockwave_strength = 0.0;
uniform vec2 shockwave_origin = vec2(0.5, 0.86);
uniform float shockwave_time = -100.0;

void fragment() {
	vec2 local_uv = UV;
	vec2 screen_uv = SCREEN_UV;
	float wave_x = sin(local_uv.y * 11.0 + time * 2.1) * 0.5;
	float wave_y = cos(local_uv.x * 9.0 - time * 1.7) * 0.5;
	vec2 warp = vec2(wave_x, wave_y) * distortion_amount * 0.0045;

	float shock_age = max(0.0, time - shockwave_time);
	vec2 hit_vec = local_uv - shockwave_origin;
	float hit_dist = length(hit_vec);
	float ring_radius = shock_age * 0.72;
	float ring = 1.0 - smoothstep(0.0, 0.045, abs(hit_dist - ring_radius));
	ring *= smoothstep(0.58, 0.0, shock_age) * shockwave_strength;
	vec2 hit_dir = normalize(hit_vec + vec2(0.0001, 0.0001));
	warp += hit_dir * ring * distortion_amount * 0.026;

	vec2 warped_uv = screen_uv + warp;
	vec2 chroma = vec2(0.0022, 0.0014) * distortion_amount * (0.45 + ring);
	vec4 raw = texture(screen_texture, screen_uv);
	vec4 shifted = vec4(
		texture(screen_texture, warped_uv + chroma).r,
		texture(screen_texture, warped_uv).g,
		texture(screen_texture, warped_uv - chroma).b,
		texture(screen_texture, warped_uv).a
	);
	vec4 col = mix(raw, shifted, clamp(distortion_amount, 0.0, 1.0));

	vec2 px = SCREEN_PIXEL_SIZE * (2.0 + bloom_amount * 5.0);
	vec3 blur =
		texture(screen_texture, warped_uv + vec2(px.x, 0.0)).rgb +
		texture(screen_texture, warped_uv - vec2(px.x, 0.0)).rgb +
		texture(screen_texture, warped_uv + vec2(0.0, px.y)).rgb +
		texture(screen_texture, warped_uv - vec2(0.0, px.y)).rgb;
	blur *= 0.25;
	float luma = dot(blur, vec3(0.299, 0.587, 0.114));
	float bright_mask = smoothstep(0.42, 0.88, luma);
	col.rgb += blur * bright_mask * bloom_amount * 0.48;
	col.rgb += vec3(0.22, 0.62, 1.0) * ring * bloom_amount * 0.24;
	col.rgb = mix(raw.rgb, col.rgb, clamp(0.18 + intensity * 0.82, 0.0, 1.0));
	COLOR = vec4(col.rgb, 1.0);
}
"""
