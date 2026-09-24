extends Node2D
class_name EMSRuntime

const EMSValidator = preload("res://systems/ems/EMSValidator.gd")
const EMSLoadoutCatalog = preload("res://scripts/ems/EMSLoadoutCatalog.gd")
const EMSLoadoutSignatureLayerScript = preload("res://scripts/ems/EMSLoadoutSignatureLayer.gd")

var _config: Dictionary = {}
var _layers: Dictionary = {}
var _layer_roots: Dictionary = {}
var _layer_order: Array[String] = []
var _events: Array[Dictionary] = []
var _time := 0.0
var _bloom_impulse := 0.0
var _distortion_impulse := 0.0
var _camera_shake := 0.0
var _shake_offset := Vector2.ZERO
var _audio_reactive_enabled := true
var _last_event_msec: Dictionary = {}
var _debug_last_event := ""
var _preview_canvas_size := Vector2.ZERO
var _content_root: Node2D
var _layout_background_region := "gutters"
var _layout_position_norm := Vector2(0.5, 0.5)
var _layout_size_norm := Vector2(1.0, 1.0)
var _layout_scale := 1.0
var _layout_rotation_degrees := 0.0
var _gutter_filter := "both"


class EMSSignaturePreviewContext:
	extends Node

	var enabled := true
	var combo_energy := 0.0
	var intensity := 0.0
	var note_density := 0.0
	var bpm := 120.0
	var signature_effect := "classic"
	var palette_morph := "profile"
	var reaction_model := "classic"
	var palette_colors: Array[Color] = []

	func configure(effect: String, morph: String, reaction: String, colors: Array[Color]) -> void:
		signature_effect = effect
		palette_morph = morph
		reaction_model = reaction
		palette_colors = colors.duplicate()

	func update_values(combo: float, intensity_value: float, density: float, bpm_value: float) -> void:
		combo_energy = clampf(combo, 0.0, 1.0)
		intensity = clampf(intensity_value, 0.0, 1.0)
		note_density = clampf(density, 0.0, 1.0)
		bpm = clampf(bpm_value, 40.0, 260.0)

	func get_signature_effect() -> String:
		return signature_effect

	func has_signature_effect() -> bool:
		return not signature_effect.is_empty() and signature_effect != "classic"

	func get_palette_morph() -> String:
		return palette_morph

	func get_reaction_model() -> String:
		return reaction_model

	func get_palette_colors() -> Array[Color]:
		return palette_colors.duplicate()

	func pick_color(_namespace: String, index: int = 0) -> Color:
		if palette_colors.is_empty():
			return Color(1.0, 1.0, 1.0, 1.0)
		var color_index := index % palette_colors.size()
		if color_index < 0:
			color_index += palette_colors.size()
		return palette_colors[color_index]

	func register_layer(_layer: Node) -> void:
		pass

	func unregister_layer(_layer: Node) -> void:
		pass


class EMSVisualLayer:
	extends Node2D

	var layer_id := ""
	var layer_type := "solid_color"
	var display_name := ""
	var enabled_by_config := true
	var runtime_enabled := true
	var base_opacity := 1.0
	var opacity := 1.0
	var color := Color(0.35, 0.88, 1.0, 0.8)
	var colors: Array[Color] = []
	var position_norm := Vector2(0.5, 0.5)
	var size_norm := Vector2(1.0, 1.0)
	var speed := 0.2
	var direction := 0.0
	var intensity := 1.0
	var particle_count := 0
	var shape := "circle"
	var scale_value := 1.0
	var rotation_degrees_value := 0.0
	var frequency := 1.0
	var thickness := 2.0
	var spacing := 42.0
	var points := 6
	var segments := 12
	var amplitude := 0.25
	var distortion := 0.0
	var bloom := 0.0
	var shake := 0.0
	var reactive := true
	var player_reactive := "off"
	var low_motion := false
	var layout_mode := "pack"
	var layout_source := ""
	var gutter_target := "both"
	var layout_position_norm := Vector2(0.5, 0.5)
	var layout_size_norm := Vector2(1.0, 1.0)
	var layout_scale := 1.0
	var layout_rotation_degrees := 0.0
	var effective_layout_mode := "pack"
	var effective_layout_source := ""
	var effective_layout_position_norm := Vector2(0.5, 0.5)
	var effective_layout_size_norm := Vector2(1.0, 1.0)
	var effective_layout_scale := 1.0
	var effective_layout_rotation_degrees := 0.0
	var effective_layout_transform_position := Vector2.ZERO
	var media_kind := ""
	var asset_path := ""
	var source_path := ""
	var fit_mode := "cover"
	var loop_media := true
	var signature_effect := ""
	var pack_folder := ""
	var _canvas_size := Vector2.ZERO
	var _time := 0.0
	var _pulse_timer := 0.0
	var _pulse_duration := 0.25
	var _pulse_opacity := 0.0
	var _pulse_scale := 1.0
	var _burst_energy := 0.0
	var _chart_reaction_energy := 0.0
	var _hit_reaction_energy := 0.0
	var _miss_reaction_energy := 0.0
	var _combo_value := 0.0
	var _context_intensity := 0.0
	var _density_value := 0.0
	var _bpm_value := 120.0
	var _rng := RandomNumberGenerator.new()
	var _particles: Array[Dictionary] = []
	var _media_texture: Texture2D = null
	var _media_error := ""
	var _video_player: Control = null
	var _video_stream_loaded := false
	var _signature_layer: Node = null
	var _signature_context: EMSSignaturePreviewContext = null

	func configure(config: Dictionary, content_folder: String = "") -> void:
		layer_id = str(config.get("id", "layer"))
		layer_type = str(config.get("type", "solid_color"))
		display_name = str(config.get("name", layer_id))
		enabled_by_config = bool(config.get("enabled", true))
		runtime_enabled = enabled_by_config
		base_opacity = clampf(float(config.get("opacity", 1.0)), 0.0, 1.0)
		opacity = base_opacity
		color = _color_from_hex(str(config.get("color", "#55DFFFFF")))
		colors.clear()
		for color_text in (config.get("colors", []) as Array):
			colors.append(_color_from_hex(str(color_text)))
		if colors.is_empty():
			colors = [color, Color(1.0, 0.30, 0.88, 0.80), Color(1.0, 0.90, 0.34, 0.80)]
		position_norm = _vec2_from_array(config.get("position", [0.5, 0.5]), Vector2(0.5, 0.5))
		size_norm = _vec2_from_array(config.get("size", [1.0, 1.0]), Vector2(1.0, 1.0))
		speed = float(config.get("speed", 0.2))
		direction = deg_to_rad(float(config.get("direction", 0.0)))
		intensity = clampf(float(config.get("intensity", 1.0)), 0.0, 2.0)
		particle_count = int(config.get("particle_count", 0))
		shape = str(config.get("shape", "circle"))
		scale_value = float(config.get("scale", 1.0))
		rotation_degrees_value = float(config.get("rotation", 0.0))
		frequency = float(config.get("frequency", 1.0))
		thickness = float(config.get("thickness", 2.0))
		spacing = float(config.get("spacing", 42.0))
		points = int(config.get("points", 6))
		segments = int(config.get("segments", 12))
		amplitude = float(config.get("amplitude", 0.25))
		distortion = float(config.get("distortion", 0.0))
		bloom = float(config.get("bloom", 0.0))
		shake = float(config.get("shake", 0.0))
		reactive = bool(config.get("reactive", true))
		player_reactive = _sanitize_player_reactive_mode(str(config.get("player_reactive", "off")))
		low_motion = bool(config.get("low_motion", false))
		layout_mode = _sanitize_layout_mode(str(config.get("layout_mode", "pack")))
		layout_source = str(config.get("layout_source", ""))
		gutter_target = _sanitize_gutter_target(str(config.get("gutter_target", "both")))
		var layer_layout: Dictionary = config.get("layout", {}) as Dictionary
		layout_position_norm = _vec2_from_array(layer_layout.get("position", [0.5, 0.5]), Vector2(0.5, 0.5))
		layout_size_norm = _vec2_from_array(layer_layout.get("size", [1.0, 1.0]), Vector2(1.0, 1.0))
		layout_scale = clampf(float(layer_layout.get("scale", 1.0)), 0.10, 4.0)
		layout_rotation_degrees = clampf(float(layer_layout.get("rotation", 0.0)), -360.0, 360.0)
		media_kind = str(config.get("media_kind", ""))
		if media_kind.is_empty() and layer_type in ["image", "video"]:
			media_kind = layer_type
		asset_path = str(config.get("asset_path", ""))
		source_path = str(config.get("source_path", ""))
		fit_mode = str(config.get("fit_mode", "cover"))
		loop_media = bool(config.get("loop", true))
		signature_effect = str(config.get("signature_effect", ""))
		if signature_effect.is_empty() and layer_type.begins_with("signature_"):
			signature_effect = layer_type.trim_prefix("signature_")
		pack_folder = content_folder
		_rng.seed = int(config.get("seed", 0)) + abs(hash(layer_id))
		_build_particles()
		_load_media()
		_sync_signature_renderer(true)
		visible = runtime_enabled
		set_process(false)
		queue_redraw()

	func tick(delta: float, context: Dictionary) -> void:
		if not runtime_enabled:
			return
		var motion_scale := float(context.get("motion_scale", 1.0))
		var combo := float(context.get("combo", 0.0))
		var intensity_value := float(context.get("intensity", 0.0))
		_combo_value = clampf(combo, 0.0, 1.0)
		_context_intensity = clampf(intensity_value, 0.0, 1.0)
		_density_value = clampf(float(context.get("density", 0.0)), 0.0, 1.0)
		_bpm_value = clampf(float(context.get("bpm", 120.0)), 40.0, 260.0)
		_sync_signature_context()
		_time += delta * maxf(0.05, absf(speed)) * motion_scale
		if _pulse_timer > 0.0:
			_pulse_timer = maxf(0.0, _pulse_timer - delta)
			var pulse_t := _pulse_timer / maxf(0.001, _pulse_duration)
			opacity = clampf(maxf(base_opacity, _pulse_opacity * pulse_t), 0.0, 1.0)
			_pulse_scale = lerpf(1.0, _pulse_scale, pulse_t)
		else:
			opacity = lerpf(opacity, base_opacity, clampf(delta * 3.0, 0.0, 1.0))
			_pulse_scale = lerpf(_pulse_scale, 1.0, clampf(delta * 4.0, 0.0, 1.0))
		_burst_energy = maxf(0.0, _burst_energy - delta * 1.6)
		_chart_reaction_energy = maxf(0.0, _chart_reaction_energy - delta * 2.15)
		_hit_reaction_energy = maxf(0.0, _hit_reaction_energy - delta * 2.45)
		_miss_reaction_energy = maxf(0.0, _miss_reaction_energy - delta * 1.65)
		_update_particles(delta, context, motion_scale, combo, intensity_value)
		if _signature_layer != null and is_instance_valid(_signature_layer):
			_signature_layer.call("ems_update", _signature_context, delta * motion_scale)
		queue_redraw()

	func set_layer_opacity(value: float) -> void:
		base_opacity = clampf(value, 0.0, 1.0)
		opacity = base_opacity
		queue_redraw()

	func pulse_opacity(value: float, duration: float) -> void:
		_pulse_opacity = clampf(value, 0.0, 1.0)
		_pulse_duration = clampf(duration, 0.02, 8.0)
		_pulse_timer = _pulse_duration
		queue_redraw()

	func set_layer_color(value: Color) -> void:
		color = value
		if colors.is_empty():
			colors.append(value)
		else:
			colors[0] = value
		queue_redraw()

	func pulse_scale(value: float, duration: float) -> void:
		_pulse_scale = clampf(value, 0.1, 4.0)
		_pulse_duration = clampf(duration, 0.02, 8.0)
		_pulse_timer = _pulse_duration
		queue_redraw()

	func burst_particles(count: int) -> void:
		_burst_energy = clampf(_burst_energy + float(maxi(1, count)) / 80.0, 0.0, 1.0)
		for i in range(mini(count, _particles.size())):
			var particle := _particles[i]
			particle["life"] = 1.0
			particle["speed"] = float(particle.get("speed", 0.0)) + 0.35 + _rng.randf() * 0.65
			_particles[i] = particle
		queue_redraw()

	func apply_chart_reaction(strength: float) -> void:
		if not reactive:
			return
		_chart_reaction_energy = maxf(_chart_reaction_energy, clampf(strength, 0.0, 1.0))
		_emit_signature_impulse(clampf(strength, 0.0, 1.0), 2, "chart")
		queue_redraw()

	func apply_player_hit(strength: float) -> void:
		if player_reactive != "hit":
			return
		_hit_reaction_energy = maxf(_hit_reaction_energy, clampf(strength, 0.0, 1.0))
		_emit_signature_impulse(clampf(strength, 0.0, 1.0), int(roundi(_time * 7.0)) % 5, "perfect")
		queue_redraw()

	func apply_player_miss(strength: float) -> void:
		if player_reactive != "miss":
			return
		_miss_reaction_energy = maxf(_miss_reaction_energy, clampf(strength, 0.0, 1.0))
		_emit_signature_impulse(clampf(strength, 0.0, 1.0), int(roundi(_time * 5.0)) % 5, "miss")
		queue_redraw()

	func enable_layer(value: bool) -> void:
		runtime_enabled = enabled_by_config and value
		visible = runtime_enabled
		if _signature_layer != null and is_instance_valid(_signature_layer):
			_signature_layer.call("ems_on_enabled_changed", runtime_enabled)
		queue_redraw()

	func transition_palette(next_colors: Array[Color]) -> void:
		if not next_colors.is_empty():
			colors = next_colors.duplicate()
			color = colors[0]
			_sync_signature_renderer(true)
		queue_redraw()

	func get_debug_state() -> Dictionary:
		return {
			"id": layer_id,
			"type": layer_type,
			"enabled": runtime_enabled,
			"particles": _particles.size(),
			"opacity": opacity,
			"audio_reactive": reactive,
			"player_reactive": player_reactive,
			"chart_reaction": _chart_reaction_energy,
			"hit_reaction": _hit_reaction_energy,
			"miss_reaction": _miss_reaction_energy,
			"normal_motion": _time,
			"renderer_family": _renderer_family(),
			"visual_activity": _visual_activity(),
			"particle_size_profile": _particle_size_profile(),
			"starfield_warp": _starfield_warp_amount() if layer_type == "starfield" else 0.0,
			"canvas_size": _canvas_size,
			"layout_mode": layout_mode,
			"layout_source": layout_source,
			"gutter_target": gutter_target,
			"effective_layout": {
				"mode": effective_layout_mode,
				"source": effective_layout_source,
				"position": [effective_layout_position_norm.x, effective_layout_position_norm.y],
				"size": [effective_layout_size_norm.x, effective_layout_size_norm.y],
				"scale": effective_layout_scale,
				"rotation": effective_layout_rotation_degrees,
			},
			"layout_transform": {
				"position": effective_layout_transform_position,
				"scale": Vector2.ONE * effective_layout_scale,
				"rotation": effective_layout_rotation_degrees,
			},
			"gradient_render_mode": "smooth_polygon" if layer_type == "gradient" else ("crt_scanlines" if layer_type == "crt_gradient" else ""),
			"gradient_band_count": _gradient_band_count(Rect2(Vector2.ZERO, get_viewport_rect().size)) if layer_type == "crt_gradient" else 0,
			"media_kind": media_kind,
			"asset_path": asset_path,
			"fit_mode": fit_mode,
			"media_loaded": _media_texture != null or _video_stream_loaded,
			"media_error": _media_error,
			"signature_effect": signature_effect,
			"signature_renderer_family": _signature_renderer_family(),
			"signature_embedded": _signature_layer != null and is_instance_valid(_signature_layer),
		}

	func set_canvas_size(value: Vector2) -> void:
		_canvas_size = Vector2(maxf(0.0, value.x), maxf(0.0, value.y))
		if _signature_layer != null and is_instance_valid(_signature_layer):
			_signature_layer.call("set_manual_bounds", _canvas_size)
		queue_redraw()

	func set_effective_layout(layout: Dictionary, transform_position: Vector2) -> void:
		effective_layout_mode = str(layout.get("mode", "pack"))
		effective_layout_source = str(layout.get("source", ""))
		effective_layout_position_norm = _vec2_from_array(layout.get("position", [0.5, 0.5]), Vector2(0.5, 0.5))
		effective_layout_size_norm = _vec2_from_array(layout.get("size", [1.0, 1.0]), Vector2(1.0, 1.0))
		effective_layout_scale = clampf(float(layout.get("scale", 1.0)), 0.10, 4.0)
		effective_layout_rotation_degrees = clampf(float(layout.get("rotation", 0.0)), -360.0, 360.0)
		effective_layout_transform_position = transform_position

	func _draw() -> void:
		if not runtime_enabled:
			return
		var draw_size := _canvas_size if _canvas_size.x > 1.0 and _canvas_size.y > 1.0 else get_viewport_rect().size
		var rect := Rect2(Vector2.ZERO, draw_size)
		if rect.size.x <= 1.0 or rect.size.y <= 1.0:
			rect.size = Vector2(640, 360)
		match layer_type:
			"solid_color":
				_draw_solid(rect)
			"gradient":
				_draw_gradient(rect)
			"crt_gradient":
				_draw_crt_gradient(rect)
			"grid":
				_draw_grid(rect)
			"starfield":
				_draw_starfield(rect)
			"particles":
				_draw_neon_particles(rect)
			"floating_shapes":
				_draw_particles(rect, true)
			"tunnel":
				_draw_tunnel(rect)
			"scanlines":
				_draw_scanlines(rect)
			"glitch_overlay":
				_draw_glitch(rect)
			"beat_pulse":
				_draw_beat_pulse(rect)
			"combo_aura":
				_draw_combo_aura(rect)
			"miss_glitch":
				_draw_reactive_shape(rect)
			"image":
				_draw_image_layer(rect)
			"video":
				_draw_video_layer(rect)
			_:
				if layer_type.begins_with("signature_"):
					_sync_signature_renderer(false)
				else:
					_draw_solid(rect)

	func _draw_solid(rect: Rect2) -> void:
		var reaction := _reaction_energy()
		var c := color
		c.a *= opacity * (0.55 + reaction * 0.22)
		draw_rect(rect, c, true)

	func _draw_gradient(rect: Rect2) -> void:
		var reaction := _reaction_energy()
		var phase := _time * 0.070 * maxf(0.20, intensity) + reaction * 0.080
		var drift := sin(_time * 0.55 + reaction * 0.8) * 0.055 * intensity
		var top := _palette_color(phase + drift)
		var top_right := _palette_color(phase + 0.16 - drift * 0.45)
		var bottom := _palette_color(phase + 0.48 + drift * 0.35)
		var bottom_left := _palette_color(phase + 0.66 - drift)
		var alpha := opacity * (0.54 + reaction * 0.12)
		top.a *= alpha
		top_right.a *= alpha
		bottom.a *= alpha
		bottom_left.a *= alpha
		draw_polygon(
			PackedVector2Array([
				Vector2(0.0, 0.0),
				Vector2(rect.size.x, 0.0),
				rect.size,
				Vector2(0.0, rect.size.y),
			]),
			PackedColorArray([top, top_right, bottom, bottom_left])
		)

	func _draw_crt_gradient(rect: Rect2) -> void:
		var reaction := _reaction_energy()
		var bands: int = _gradient_band_count(rect)
		var strip_h: float = ceil(rect.size.y / float(bands)) + 2.0
		for i in range(bands):
			var t := float(i) / float(maxi(1, bands - 1))
			var wave := sin((_time * TAU) + t * TAU * frequency + reaction * 1.4) * 0.5 + 0.5
			var color_offset := sin(_time * 1.7 + t * TAU * (1.2 + frequency * 0.22)) * 0.070 * intensity
			var c := _palette_color(t + wave * 0.10 + color_offset + reaction * 0.055)
			c.a *= opacity * (0.40 + wave * 0.12 + reaction * 0.12)
			var y: float = floor(rect.size.y * float(i) / float(bands))
			draw_rect(Rect2(0.0, y, rect.size.x, strip_h), c, true)
		var wash := _palette_color(_time * 0.08 + reaction * 0.18)
		wash.a *= opacity * (0.035 + reaction * 0.030)
		draw_rect(rect, wash, true)

	func _gradient_band_count(rect: Rect2) -> int:
		var height: float = rect.size.y if rect.size.y > 1.0 else 720.0
		return clampi(int(ceil(height / 5.0)), 96, 180)

	func _draw_grid(rect: Rect2) -> void:
		var reaction := _reaction_energy()
		var step := maxf(8.0, spacing)
		var c := color
		c.a *= opacity * (0.35 + reaction * 0.22)
		var offset := fposmod(_time * step * (3.2 + reaction * 5.0), step)
		for x in range(int(-step), int(rect.size.x + step), int(step)):
			draw_line(Vector2(float(x) + offset, 0), Vector2(float(x) - rect.size.x * (0.08 + reaction * 0.05) + offset, rect.size.y), c, thickness * (1.0 + reaction * 0.8))
		for y in range(int(-step), int(rect.size.y + step), int(step)):
			draw_line(Vector2(0, float(y) + offset), Vector2(rect.size.x, float(y) + offset), c, maxf(1.0, thickness * (0.65 + reaction * 0.45)))

	func _draw_particles(rect: Rect2, shapes: bool) -> void:
		var reaction := _reaction_energy()
		for i in range(_particles.size()):
			var p := _particles[i]
			var pos := Vector2(float(p.get("x", 0.0)) * rect.size.x, float(p.get("y", 0.0)) * rect.size.y)
			var size := float(p.get("size", 2.0)) * (1.0 + _burst_energy * 1.8 + reaction * 1.15)
			var c := _palette_color(float(p.get("hue", 0.0)))
			c.a *= opacity * float(p.get("life", 1.0)) * (0.40 + _burst_energy * 0.35 + reaction * 0.24)
			if shapes:
				_draw_shape(pos, size, c, i)
			else:
				draw_circle(pos, size, c)

	func _draw_neon_particles(rect: Rect2) -> void:
		var reaction := _reaction_energy()
		var glow_scale := clampf(thickness * 0.32 + scale_value * 0.42, 0.55, 5.0)
		for i in range(_particles.size()):
			var p := _particles[i]
			var pos := Vector2(float(p.get("x", 0.0)) * rect.size.x, float(p.get("y", 0.0)) * rect.size.y)
			var life := float(p.get("life", 1.0))
			var pulse := 0.78 + 0.22 * sin(_time * TAU * maxf(0.12, frequency) + float(p.get("phase", 0.0)))
			var base_size := float(p.get("size", 1.0)) * clampf(scale_value, 0.25, 3.0)
			var core_size := clampf(base_size * (0.48 + reaction * 0.35 + _burst_energy * 0.55) * pulse, 0.45, 4.25)
			var glow_size := core_size * (2.4 + glow_scale + reaction * 1.2 + _burst_energy * 1.8)
			var c := _palette_color(float(p.get("hue", 0.0)) + _time * 0.025)
			var glow := c
			glow.a *= opacity * life * (0.10 + reaction * 0.10 + _burst_energy * 0.18)
			draw_circle(pos, glow_size, glow)
			c.a *= opacity * life * (0.68 + reaction * 0.18 + _burst_energy * 0.18)
			draw_circle(pos, core_size, c)

	func _draw_starfield(rect: Rect2) -> void:
		var reaction := _reaction_energy()
		var center := rect.size * position_norm
		var warp := _starfield_warp_amount()
		for i in range(_particles.size()):
			var p := _particles[i]
			var depth := clampf(float(p.get("depth", 1.0)), 0.08, 1.2)
			var local := Vector2(float(p.get("x", 0.5)) - 0.5, float(p.get("y", 0.5)) - 0.5)
			var pos := center + Vector2(local.x * rect.size.x, local.y * rect.size.y) / depth
			if pos.x < -24.0 or pos.y < -24.0 or pos.x > rect.size.x + 24.0 or pos.y > rect.size.y + 24.0:
				continue
			var twinkle := 0.62 + 0.38 * sin(_time * (2.4 + frequency) + float(p.get("phase", 0.0)))
			var c := _palette_color(float(p.get("hue", 0.0)) + depth * 0.28)
			var size := clampf(float(p.get("size", 1.0)) * scale_value * (1.0 / depth) * (0.35 + reaction * 0.15), 0.55, 3.2)
			c.a *= opacity * float(p.get("life", 1.0)) * (0.30 + twinkle * 0.34 + reaction * 0.14)
			if warp > 0.28:
				var away := (pos - center).normalized()
				var tail := away * (8.0 + warp * 36.0) * (1.05 - depth)
				var tail_color := c
				tail_color.a *= 0.58
				draw_line(pos - tail, pos, tail_color, maxf(1.0, size), true)
			draw_circle(pos, size, c)

	func _draw_tunnel(rect: Rect2) -> void:
		var reaction := _reaction_energy()
		var center := rect.size * position_norm
		var max_radius := maxf(rect.size.x, rect.size.y) * 0.65
		for i in range(maxi(2, segments)):
			var t := float(i) / float(maxi(1, segments - 1))
			var radius := max_radius * (1.0 - t) * scale_value * (1.0 + reaction * 0.12)
			var phase := fposmod(t + _time * (0.12 + reaction * 0.08), 1.0)
			var c := _palette_color(phase)
			c.a *= opacity * (0.10 + t * 0.34 + reaction * 0.10)
			draw_arc(center, radius, 0, TAU, maxi(12, points), c, thickness * (1.0 + t + reaction), true)

	func _draw_scanlines(rect: Rect2) -> void:
		var reaction := _reaction_energy()
		var c := color
		c.a *= opacity * (0.26 + reaction * 0.28)
		var step := maxf(3.0, spacing * 0.25)
		var offset := fposmod(_time * (90.0 + reaction * 130.0), step)
		for y in range(0, int(rect.size.y + step), int(step)):
			draw_line(Vector2(0, float(y) + offset), Vector2(rect.size.x, float(y) + offset), c, maxf(1.0, thickness * (1.0 + reaction)))

	func _draw_glitch(rect: Rect2) -> void:
		var reaction := _reaction_energy()
		var rows := maxi(3, segments)
		for i in range(rows):
			var t := float(i) / float(rows)
			var wave := sin(_time * (13.0 + reaction * 12.0) + float(i) * 2.17)
			if absf(wave) < 0.45 - reaction * 0.22:
				continue
			var c := _palette_color(t)
			c.a *= opacity * (0.22 + reaction * 0.22)
			var h := maxf(2.0, thickness * (1.0 + absf(wave)))
			var x := wave * rect.size.x * (0.04 + reaction * 0.04) * intensity
			draw_rect(Rect2(x, rect.size.y * t, rect.size.x * (0.35 + absf(wave) * 0.48), h), c, true)

	func _draw_beat_pulse(rect: Rect2) -> void:
		var reaction := _reaction_energy()
		var center := rect.size * position_norm
		var bpm_phase := _time * maxf(0.5, _bpm_value / 120.0) * maxf(0.25, frequency)
		var pulse := pow(sin(bpm_phase * TAU) * 0.5 + 0.5, 2.0)
		var bars := maxi(6, mini(32, segments))
		var usable_w := rect.size.x * clampf(size_norm.x, 0.25, 1.0)
		var start_x := center.x - usable_w * 0.5
		var bar_w := maxf(2.0, usable_w / float(bars) * 0.45)
		for i in range(bars):
			var t := float(i) / float(maxi(1, bars - 1))
			var wave := sin(bpm_phase * TAU + t * TAU * 1.35) * 0.5 + 0.5
			var h := rect.size.y * (0.04 + amplitude * 0.16) * (0.35 + wave * 0.65 + reaction * 0.65 + pulse * 0.25)
			var c := _palette_color(t + _time * 0.04 + reaction * 0.12)
			c.a *= opacity * (0.18 + wave * 0.18 + reaction * 0.24)
			draw_rect(Rect2(start_x + t * usable_w - bar_w * 0.5, center.y - h * 0.5, bar_w, h), c, true)
		for ring in range(3):
			var ring_t := float(ring) / 3.0
			var radius := minf(rect.size.x, rect.size.y) * (0.12 + ring_t * 0.17 + pulse * 0.040 + reaction * 0.070) * scale_value
			var c2 := _palette_color(ring_t + _time * 0.08)
			c2.a *= opacity * (0.16 + reaction * 0.22 + pulse * 0.15) * (1.0 - ring_t * 0.22)
			draw_arc(center, radius, 0, TAU, maxi(24, points * 4), c2, maxf(1.0, thickness * (1.0 + pulse + reaction)), true)

	func _draw_combo_aura(rect: Rect2) -> void:
		var reaction := _reaction_energy()
		var center := rect.size * position_norm
		var combo_power := clampf(maxf(_combo_value, reaction * 0.85), 0.0, 1.0)
		var base_radius := minf(rect.size.x, rect.size.y) * (0.12 + amplitude * 0.18) * scale_value
		for i in range(5):
			var t := float(i) / 5.0
			var radius := base_radius * (1.0 + t * 0.42 + combo_power * 0.55 + sin(_time * 1.4 + float(i)) * 0.035)
			var start := _time * (0.8 + t) + t * TAU
			var arc_len := PI * (0.42 + combo_power * 0.55 + t * 0.20)
			var c := _palette_color(t + _time * 0.055 + combo_power * 0.12)
			c.a *= opacity * (0.16 + combo_power * 0.25) * (1.0 - t * 0.11)
			draw_arc(center, radius, start, start + arc_len, maxi(16, points * 3), c, maxf(1.0, thickness * (1.1 + combo_power)), true)
			draw_arc(center, radius * 0.84, start + PI, start + PI + arc_len * 0.72, maxi(16, points * 2), c, maxf(1.0, thickness * 0.72), true)
		for i in range(maxi(4, mini(14, points))):
			var angle := _time * (0.7 + combo_power) + float(i) * TAU / float(maxi(4, points))
			var r := base_radius * (1.15 + 0.55 * sin(_time * 0.9 + float(i)))
			var pos := center + Vector2(cos(angle), sin(angle)) * r
			var wisp := _palette_color(float(i) / float(maxi(1, points)) + _time * 0.08)
			wisp.a *= opacity * (0.16 + combo_power * 0.20)
			draw_circle(pos, maxf(1.4, thickness * (0.55 + combo_power)), wisp)

	func _draw_reactive_shape(rect: Rect2) -> void:
		var reaction := _reaction_energy()
		var center := rect.size * position_norm
		var pulse := sin(_time * TAU * maxf(0.25, frequency)) * 0.5 + 0.5
		var radius := minf(rect.size.x, rect.size.y) * (0.08 + amplitude * 0.20) * scale_value * _pulse_scale
		radius *= 1.0 + _burst_energy * 2.0 + reaction * 1.25 + pulse * 0.25
		var c := _palette_color(_time * 0.12 + pulse * 0.1 + reaction * 0.12)
		c.a *= opacity * (0.16 + pulse * 0.22 + _burst_energy * 0.26 + reaction * 0.22)
		if layer_type == "miss_glitch":
			for i in range(4):
				draw_rect(Rect2(center.x - radius + float(i) * (12.0 + reaction * 16.0), center.y - radius * 0.3 + float(i) * 8.0, radius * 1.8, thickness * (2.0 + reaction * 2.0)), c, true)
		else:
			draw_arc(center, radius, 0, TAU, maxi(16, points * 3), c, thickness * (1.0 + _burst_energy + reaction), true)
			draw_circle(center, radius * 0.18, c)

	func _draw_image_layer(rect: Rect2) -> void:
		_hide_video_player()
		var modulate := Color(1.0, 1.0, 1.0, opacity)
		if _media_texture == null:
			_draw_media_placeholder(rect, "IMAGE", Color(0.25, 0.85, 1.0, 0.32))
			return
		var target := _media_target_rect(rect, _media_texture.get_size())
		if fit_mode == "tile":
			draw_texture_rect(_media_texture, rect, true, modulate)
		else:
			draw_texture_rect(_media_texture, target, false, modulate)
		var wash := color
		wash.a *= opacity * clampf(bloom * 0.08 + _reaction_energy() * 0.06, 0.0, 0.20)
		draw_rect(rect, wash, true)

	func _draw_video_layer(rect: Rect2) -> void:
		_sync_video_player(rect)
		if not _video_stream_loaded:
			_draw_media_placeholder(rect, "VIDEO", Color(1.0, 0.42, 0.22, 0.30))
			return
		var reaction := _reaction_energy()
		var edge := _palette_color(_time * 0.05 + reaction * 0.12)
		edge.a *= opacity * (0.12 + reaction * 0.12)
		draw_rect(rect, edge, false, maxf(1.0, thickness))

	func _draw_media_placeholder(rect: Rect2, label_text: String, tint: Color) -> void:
		var reaction := _reaction_energy()
		var bg := tint
		bg.a *= opacity * (0.25 + reaction * 0.15)
		draw_rect(rect, bg, true)
		var line := tint.lightened(0.55)
		line.a *= opacity * (0.24 + reaction * 0.18)
		var step := maxf(18.0, spacing * 0.7)
		var offset := fposmod(_time * 30.0, step)
		for x in range(int(-step), int(rect.size.x + step), int(step)):
			draw_line(Vector2(float(x) + offset, 0.0), Vector2(float(x) - rect.size.x * 0.12 + offset, rect.size.y), line, maxf(1.0, thickness * 0.7), true)
		var frame := tint.lightened(0.75)
		frame.a *= opacity * 0.58
		draw_rect(rect.grow(-8.0), frame, false, maxf(1.0, thickness * 1.2))
		var bar_h := maxf(8.0, rect.size.y * 0.035)
		for i in range(4):
			var t := float(i) / 4.0
			var c := _palette_color(t + _time * 0.05)
			c.a *= opacity * 0.30
			draw_rect(Rect2(rect.size.x * (0.18 + t * 0.16), rect.size.y * 0.5 - bar_h * 0.5, rect.size.x * 0.08, bar_h), c, true)

	func _sync_signature_renderer(force: bool) -> void:
		if not layer_type.begins_with("signature_") or signature_effect.is_empty():
			_clear_signature_renderer()
			return
		if _signature_context == null or not is_instance_valid(_signature_context):
			_signature_context = EMSSignaturePreviewContext.new()
			_signature_context.name = "BuiltInEMSPreviewContext"
			add_child(_signature_context)
		if _signature_layer == null or not is_instance_valid(_signature_layer):
			_signature_layer = EMSLoadoutSignatureLayerScript.new()
			_signature_layer.name = "BuiltInEMS_%s" % signature_effect
			_signature_layer.call("set_embedded_context", _signature_context, _canvas_size)
			add_child(_signature_layer)
			force = true
		_sync_signature_context()
		_signature_layer.visible = runtime_enabled
		_signature_layer.modulate = Color(1.0, 1.0, 1.0, opacity)
		_signature_layer.call("set_manual_bounds", _canvas_size)
		if force:
			_signature_layer.call("ems_on_loadout_changed", _signature_context)
			_signature_layer.call("ems_on_palette_changed", _signature_context)

	func _sync_signature_context() -> void:
		if _signature_context == null or not is_instance_valid(_signature_context):
			return
		var catalog_config := _signature_catalog_config()
		var palette := _signature_palette(catalog_config)
		_signature_context.enabled = runtime_enabled
		_signature_context.configure(
			signature_effect,
			str(catalog_config.get("palette_morph", "spectral_flow")),
			str(catalog_config.get("reaction_model", "combo_surge")),
			palette
		)
		_signature_context.update_values(
			maxf(_combo_value, _hit_reaction_energy),
			maxf(_context_intensity, _reaction_energy()),
			_density_value,
			_bpm_value
		)

	func _clear_signature_renderer() -> void:
		if _signature_layer != null and is_instance_valid(_signature_layer):
			remove_child(_signature_layer)
			_signature_layer.queue_free()
		if _signature_context != null and is_instance_valid(_signature_context):
			remove_child(_signature_context)
			_signature_context.queue_free()
		_signature_layer = null
		_signature_context = null

	func _signature_catalog_config() -> Dictionary:
		if signature_effect.is_empty():
			return {}
		var config := EMSLoadoutCatalog.get_config("ems_%s" % signature_effect)
		if config.is_empty() or bool(config.get("profile_driven", false)):
			return {
				"palette_morph": "spectral_flow",
				"reaction_model": "combo_surge",
				"palette": colors.duplicate(),
			}
		return config

	func _signature_palette(catalog_config: Dictionary) -> Array[Color]:
		var palette: Array[Color] = []
		for color_value in (catalog_config.get("palette", []) as Array):
			if color_value is Color:
				palette.append(color_value)
			else:
				palette.append(_color_from_hex(str(color_value)))
		if palette.is_empty():
			palette = colors.duplicate()
		if palette.is_empty():
			palette = [color, Color(1.0, 0.30, 0.88, 1.0), Color(1.0, 0.90, 0.34, 1.0)]
		return palette

	func _emit_signature_impulse(strength: float, lane: int, judgement: String) -> void:
		if _signature_layer == null or not is_instance_valid(_signature_layer):
			return
		if _signature_context == null or not is_instance_valid(_signature_context):
			return
		_sync_signature_context()
		_signature_layer.call("ems_on_impulse", _signature_context, {
			"strength": clampf(strength, 0.0, 1.0),
			"lane": lane,
			"judgement": judgement,
			"y_norm": 0.82,
			"color": _signature_context.pick_color("creator_signature_impulse", lane),
		})

	func _signature_renderer_family() -> String:
		if _signature_layer != null and is_instance_valid(_signature_layer):
			var state: Dictionary = _signature_layer.call("get_debug_state") as Dictionary
			return str(state.get("render_family", signature_effect))
		return signature_effect

	func _draw_signature_layer(rect: Rect2) -> void:
		var effect := signature_effect
		var reaction := _reaction_energy()
		match effect:
			"neon_rain":
				_draw_signature_rain(rect, reaction)
			"digital_snow", "pixel_nebula":
				_draw_signature_blocks(rect, reaction, effect == "pixel_nebula")
			"plasma_storm", "solar_bloom", "singularity_bloom":
				_draw_signature_blobs(rect, reaction, effect)
			"quantum_grid", "prism_circuit", "thunder_matrix":
				_draw_signature_lattice(rect, reaction, effect)
			"aurora_drive", "cyber_ocean", "skyline_mirage", "hypernova_flow":
				_draw_signature_curtains(rect, reaction, effect)
			"fractal_space", "lunar_glass", "chromatic_rift", "crystal_reactor", "gravity_well", "void_pulse":
				_draw_signature_portals(rect, reaction, effect)
			_:
				_draw_signature_curtains(rect, reaction, effect)

	func _draw_signature_rain(rect: Rect2, reaction: float) -> void:
		var count := maxi(16, mini(44, segments * 2))
		for i in range(count):
			var x := fposmod(float(i * 73) + sin(_time * 1.3 + float(i)) * 42.0, rect.size.x)
			var y := fposmod(float(i * 119) + _time * rect.size.y * (0.18 + speed * 0.08), rect.size.y)
			var drop_len := 8.0 + float(i % 4) * 3.0 + reaction * 12.0
			var c := _palette_color(float(i) / float(count) + _time * 0.035)
			c.a *= opacity * (0.38 + reaction * 0.20)
			draw_line(Vector2(x, y - drop_len), Vector2(x, y), c, maxf(1.0, thickness * 0.8), true)
			draw_circle(Vector2(x, y), maxf(2.0, thickness * 1.2 + reaction * 2.0), c)
		if reaction > 0.05:
			for i in range(8):
				var px := fposmod(float(i * 151) + _time * 40.0, rect.size.x)
				var py := rect.size.y * (0.66 + sin(float(i)) * 0.18)
				var splash := _palette_color(float(i) / 8.0)
				splash.a *= opacity * reaction * 0.45
				draw_arc(Vector2(px, py), 8.0 + reaction * 18.0, PI, TAU, 12, splash, maxf(1.0, thickness), true)

	func _draw_signature_blocks(rect: Rect2, reaction: float, nebula: bool) -> void:
		var count := maxi(18, mini(70, segments * 3))
		for i in range(count):
			var t := float(i) / float(count)
			var x := fposmod(t * rect.size.x * 3.1 + _time * 18.0 * speed, rect.size.x)
			var y := fposmod(float((i * 47) % 997) / 997.0 * rect.size.y + sin(_time + float(i)) * 8.0, rect.size.y)
			var size := (3.0 if not nebula else 5.0) + float(i % 5) + reaction * 5.0
			var c := _palette_color(t + (0.18 if nebula else 0.0))
			c.a *= opacity * (0.24 + reaction * 0.20)
			draw_rect(Rect2(x, y, size, size), c, true)

	func _draw_signature_blobs(rect: Rect2, reaction: float, effect: String) -> void:
		var center := rect.size * position_norm
		var count := maxi(7, mini(18, segments))
		for i in range(count):
			var t := float(i) / float(count)
			var angle := t * TAU + _time * (0.5 + speed * 0.1)
			var radius := minf(rect.size.x, rect.size.y) * (0.08 + 0.34 * t + reaction * 0.08)
			var pos := center + Vector2(cos(angle * 1.7), sin(angle * 1.1)) * radius
			var blob_radius := minf(rect.size.x, rect.size.y) * (0.045 + amplitude * 0.035 + reaction * 0.045) * (1.0 + sin(_time * 2.0 + float(i)) * 0.15)
			var c := _palette_color(t + _time * 0.045)
			if effect == "solar_bloom":
				c = Color(1.0, lerpf(0.44, 0.92, t), 0.12, c.a)
			c.a *= opacity * (0.14 + reaction * 0.18)
			draw_circle(pos, blob_radius * 2.1, Color(c.r, c.g, c.b, c.a * 0.18))
			draw_circle(pos, blob_radius, c)
		var core := _palette_color(_time * 0.06)
		core.a *= opacity * (0.16 + reaction * 0.25)
		draw_circle(center, minf(rect.size.x, rect.size.y) * (0.06 + reaction * 0.05), core)

	func _draw_signature_lattice(rect: Rect2, reaction: float, effect: String) -> void:
		var cols := maxi(5, mini(12, points))
		var rows := maxi(4, mini(10, segments / 2))
		for y in range(rows):
			for x in range(cols):
				var pos := Vector2((float(x) + 0.5) / float(cols) * rect.size.x, (float(y) + 0.5) / float(rows) * rect.size.y)
				pos += Vector2(sin(_time + float(y)) * 8.0, cos(_time * 0.8 + float(x)) * 6.0) * (0.4 + reaction)
				var c := _palette_color(float(x + y) / float(cols + rows) + _time * 0.03)
				c.a *= opacity * (0.16 + reaction * 0.18)
				var s := 5.0 + reaction * 8.0
				draw_line(pos + Vector2(0, -s), pos + Vector2(s, 0), c, maxf(1.0, thickness), true)
				draw_line(pos + Vector2(s, 0), pos + Vector2(0, s), c, maxf(1.0, thickness), true)
				draw_line(pos + Vector2(0, s), pos + Vector2(-s, 0), c, maxf(1.0, thickness), true)
				draw_line(pos + Vector2(-s, 0), pos + Vector2(0, -s), c, maxf(1.0, thickness), true)
				if effect == "prism_circuit" and x < cols - 1:
					draw_line(pos, Vector2(pos.x + rect.size.x / float(cols) * 0.45, pos.y), c, maxf(1.0, thickness * 0.65), true)

	func _draw_signature_curtains(rect: Rect2, reaction: float, effect: String) -> void:
		var curtains := maxi(4, mini(10, segments / 2))
		for i in range(curtains):
			var t := float(i) / float(maxi(1, curtains - 1))
			var x := rect.size.x * t
			var wave := sin(_time * (0.8 + speed * 0.2) + t * TAU * frequency)
			var c := _palette_color(t + _time * 0.025)
			c.a *= opacity * (0.12 + reaction * 0.12)
			var width := rect.size.x / float(curtains) * (0.9 + reaction * 0.25)
			var top := Vector2(x + wave * rect.size.x * 0.04, 0.0)
			var bottom := Vector2(x - wave * rect.size.x * 0.08, rect.size.y)
			var pts := PackedVector2Array([top, top + Vector2(width, 0), bottom + Vector2(width * 0.35, 0), bottom - Vector2(width * 0.65, 0)])
			draw_polygon(pts, PackedColorArray([c, c.darkened(0.15), c.darkened(0.35), c]))
		if effect == "skyline_mirage":
			var horizon := rect.size.y * 0.68
			for i in range(8):
				var h := rect.size.y * (0.06 + float(i % 4) * 0.035)
				var x := float(i) / 8.0 * rect.size.x
				var c2 := color
				c2.a *= opacity * 0.14
				draw_rect(Rect2(x, horizon - h, rect.size.x * 0.09, h), c2, true)

	func _draw_signature_portals(rect: Rect2, reaction: float, effect: String) -> void:
		var center := rect.size * position_norm
		var rings := maxi(4, mini(12, segments / 2))
		for i in range(rings):
			var t := float(i) / float(maxi(1, rings - 1))
			var radius := minf(rect.size.x, rect.size.y) * (0.07 + t * 0.34 + reaction * 0.08) * scale_value
			var sides := maxi(3, mini(12, points + i % 4))
			var c := _palette_color(t + _time * 0.055)
			c.a *= opacity * (0.18 + reaction * 0.18) * (1.0 - t * 0.24)
			var pts := PackedVector2Array()
			for p in range(sides):
				var angle := _time * (0.35 + t) + float(p) * TAU / float(sides)
				var wobble := 1.0 + sin(_time * 1.7 + float(p + i)) * 0.06
				pts.append(center + Vector2(cos(angle), sin(angle)) * radius * wobble)
			draw_polyline(pts, c, maxf(1.0, thickness * (1.0 + reaction)), true)
		if effect == "gravity_well" or effect == "void_pulse":
			var core := Color(0.02, 0.0, 0.06, opacity * (0.42 + reaction * 0.20))
			draw_circle(center, minf(rect.size.x, rect.size.y) * (0.11 + reaction * 0.05), core)

	func _draw_shape(pos: Vector2, size: float, c: Color, index: int) -> void:
		match shape:
			"square":
				draw_rect(Rect2(pos - Vector2(size, size), Vector2(size * 2.0, size * 2.0)), c, false, maxf(1.0, thickness))
			"diamond":
				var pts := PackedVector2Array([pos + Vector2(0, -size), pos + Vector2(size, 0), pos + Vector2(0, size), pos + Vector2(-size, 0)])
				draw_polygon(pts, PackedColorArray([c, c, c, c]))
			"line":
				draw_line(pos - Vector2(size, 0).rotated(direction + float(index)), pos + Vector2(size, 0).rotated(direction + float(index)), c, thickness)
			_:
				draw_circle(pos, size, c)

	func _palette_color(position: float) -> Color:
		if colors.is_empty():
			return color
		var wrapped := fposmod(position, 1.0)
		var scaled := wrapped * float(colors.size())
		var idx := int(floor(scaled)) % colors.size()
		var next := (idx + 1) % colors.size()
		return colors[idx].lerp(colors[next], scaled - floor(scaled))

	func _build_particles() -> void:
		_particles.clear()
		for i in range(maxi(0, particle_count)):
			var particle_size := _rng.randf_range(1.6, 5.5)
			if layer_type == "particles":
				particle_size = _rng.randf_range(0.45, 1.85)
			elif layer_type == "starfield":
				particle_size = _rng.randf_range(0.35, 1.45)
			_particles.append({
				"x": _rng.randf(),
				"y": _rng.randf(),
				"speed": _rng.randf_range(0.05, 0.45),
				"size": particle_size,
				"hue": _rng.randf(),
				"life": _rng.randf_range(0.35, 1.0),
				"drift": _rng.randf_range(-0.25, 0.25),
				"depth": _rng.randf_range(0.18, 1.0),
				"phase": _rng.randf() * TAU,
			})

	func _update_particles(delta: float, context: Dictionary, motion_scale: float, combo: float, intensity_value: float) -> void:
		if _particles.is_empty():
			return
		var reaction := _reaction_energy()
		var dir_vec := Vector2.RIGHT.rotated(direction)
		if layer_type == "starfield":
			_update_starfield_particles(delta, motion_scale, combo, intensity_value, reaction)
			return
		for i in range(_particles.size()):
			var p := _particles[i]
			var speed_scale := float(p.get("speed", 0.1)) * delta * motion_scale * (0.12 + absf(speed))
			speed_scale *= 1.0 + combo * 0.28 + intensity_value * 0.18 + _burst_energy * 1.8 + reaction * 1.1
			var drift_wave := sin(_time * (2.3 + frequency * 0.18) + float(i) * 0.41) * delta * (reaction + amplitude) * 0.04
			p["x"] = fposmod(float(p.get("x", 0.0)) + dir_vec.x * speed_scale + float(p.get("drift", 0.0)) * delta * 0.03 * (1.0 + amplitude) + drift_wave, 1.0)
			p["y"] = fposmod(float(p.get("y", 0.0)) + dir_vec.y * speed_scale + cos(_time + float(i) * 0.37) * delta * (reaction + amplitude * 0.5) * 0.035, 1.0)
			p["life"] = clampf(float(p.get("life", 1.0)) + sin(_time + float(i) * 0.71) * delta * 0.12, 0.20, 1.0)
			_particles[i] = p

	func _update_starfield_particles(delta: float, motion_scale: float, combo: float, intensity_value: float, reaction: float) -> void:
		var calm_motion := 0.006 + absf(speed) * 0.018
		var reactive_motion := reaction * 0.34 + _burst_energy * 0.48
		var speed_base := delta * motion_scale * (calm_motion + reactive_motion)
		speed_base *= 1.0 + combo * 0.08 + intensity_value * 0.06
		var dir_vec := Vector2.RIGHT.rotated(direction) * delta * 0.025 * amplitude
		for i in range(_particles.size()):
			var p := _particles[i]
			var depth := float(p.get("depth", 1.0)) - speed_base * (1.15 - float(p.get("depth", 1.0)) * 0.35)
			p["x"] = float(p.get("x", 0.5)) + dir_vec.x * float(p.get("speed", 0.1))
			p["y"] = float(p.get("y", 0.5)) + dir_vec.y * float(p.get("speed", 0.1))
			if depth <= 0.08:
				p["x"] = clampf(0.5 + _rng.randf_range(-0.48, 0.48), 0.02, 0.98)
				p["y"] = clampf(0.5 + _rng.randf_range(-0.48, 0.48), 0.02, 0.98)
				p["depth"] = _rng.randf_range(0.72, 1.0)
				p["hue"] = _rng.randf()
				p["life"] = _rng.randf_range(0.45, 1.0)
			else:
				p["depth"] = depth
			_particles[i] = p

	func _reaction_energy() -> float:
		return clampf(maxf(maxf(_chart_reaction_energy, _hit_reaction_energy), maxf(_miss_reaction_energy, _burst_energy)), 0.0, 1.0)

	func _starfield_warp_amount() -> float:
		return clampf(_reaction_energy() * 0.95 + _burst_energy * 1.15, 0.0, 2.0)

	func _load_media() -> void:
		_media_texture = null
		_video_stream_loaded = false
		_media_error = ""
		_hide_video_player()
		if media_kind not in ["image", "video"]:
			return
		var resolved := _resolved_media_path()
		if resolved.is_empty():
			_media_error = "missing_media_path"
			return
		if media_kind == "image":
			var image := Image.new()
			var err := image.load(resolved)
			if err != OK:
				_media_error = "unsupported_or_unreadable_image"
				return
			_media_texture = ImageTexture.create_from_image(image)
		elif media_kind == "video":
			var stream := ResourceLoader.load(resolved)
			if stream == null:
				_media_error = "unsupported_or_unreadable_video"
				return
			var player := _ensure_video_player()
			if player == null:
				_media_error = "video_player_unavailable"
				return
			player.set("stream", stream)
			player.set("loop", loop_media)
			player.set("expand", true)
			player.modulate = Color(1.0, 1.0, 1.0, opacity)
			player.visible = runtime_enabled
			if player.has_method("play"):
				player.call("play")
			_video_stream_loaded = true

	func _resolved_media_path() -> String:
		var source := source_path.strip_edges()
		if not source.is_empty():
			return source
		var asset := asset_path.strip_edges()
		if asset.is_empty():
			return ""
		if not pack_folder.strip_edges().is_empty():
			return pack_folder.path_join(asset)
		return asset

	func _ensure_video_player() -> Control:
		if _video_player != null and is_instance_valid(_video_player):
			return _video_player
		var player := VideoStreamPlayer.new()
		player.visible = false
		add_child(player)
		_video_player = player
		return _video_player

	func _hide_video_player() -> void:
		if _video_player != null and is_instance_valid(_video_player):
			_video_player.visible = false

	func _sync_video_player(rect: Rect2) -> void:
		if not _video_stream_loaded:
			_hide_video_player()
			return
		var player := _ensure_video_player()
		if player == null:
			return
		player.visible = runtime_enabled
		player.position = rect.position
		player.size = rect.size
		player.modulate = Color(1.0, 1.0, 1.0, opacity)

	func _media_target_rect(rect: Rect2, media_size: Vector2) -> Rect2:
		if media_size.x <= 1.0 or media_size.y <= 1.0 or fit_mode == "stretch":
			return rect
		var sx := rect.size.x / media_size.x
		var sy := rect.size.y / media_size.y
		var scale_factor := minf(sx, sy) if fit_mode == "contain" else maxf(sx, sy)
		var size_value := media_size * scale_factor
		return Rect2(rect.position + (rect.size - size_value) * 0.5, size_value)

	func _renderer_family() -> String:
		match layer_type:
			"combo_aura":
				return "combo_aura_halos"
			"beat_pulse":
				return "beat_pulse_waves"
			"particles":
				return "neon_particles"
			"starfield":
				return "depth_starfield"
			"gradient":
				return "smooth_gradient"
			"crt_gradient":
				return "crt_gradient"
			"image":
				return "image_media"
			"video":
				return "video_media"
			_:
				if layer_type.begins_with("signature_"):
					return _signature_renderer_family()
				return layer_type

	func _visual_activity() -> int:
		match layer_type:
			"particles", "starfield", "floating_shapes":
				return _particles.size()
			"image", "video":
				return 1
			"beat_pulse":
				return maxi(6, mini(32, segments)) + 3
			"combo_aura":
				return 10 + maxi(4, mini(14, points))
			_:
				if layer_type.begins_with("signature_"):
					if _signature_layer != null and is_instance_valid(_signature_layer):
						var state: Dictionary = _signature_layer.call("get_debug_state") as Dictionary
						return max(1, int(state.get("active_count", 0)) + int(state.get("impulses", 0)))
					return maxi(8, segments)
				return maxi(1, segments)

	func _particle_size_profile() -> Dictionary:
		if _particles.is_empty():
			return {"min": 0.0, "max": 0.0}
		var min_size := 999999.0
		var max_size := 0.0
		for particle_variant in _particles:
			var p := particle_variant as Dictionary
			var size_value := float(p.get("size", 0.0))
			min_size = minf(min_size, size_value)
			max_size = maxf(max_size, size_value)
		return {"min": min_size, "max": max_size}

	func _sanitize_player_reactive_mode(mode: String) -> String:
		var normalized := mode.strip_edges().to_lower()
		match normalized:
			"hit", "miss":
				return normalized
			_:
				return "off"

	func _sanitize_layout_mode(mode: String) -> String:
		var normalized := mode.strip_edges().to_lower()
		match normalized:
			"custom", "reuse":
				return normalized
			_:
				return "pack"

	func _sanitize_gutter_target(value: String) -> String:
		var normalized := value.strip_edges().to_lower()
		match normalized:
			"left", "right":
				return normalized
			_:
				return "both"

	func _color_from_hex(value: String) -> Color:
		var hex := value.strip_edges()
		if hex.begins_with("#"):
			hex = hex.substr(1)
		if hex.length() == 6:
			hex += "FF"
		if hex.length() != 8:
			return Color(0.33, 0.87, 1.0, 1.0)
		return Color(
			float(hex.substr(0, 2).hex_to_int()) / 255.0,
			float(hex.substr(2, 2).hex_to_int()) / 255.0,
			float(hex.substr(4, 2).hex_to_int()) / 255.0,
			float(hex.substr(6, 2).hex_to_int()) / 255.0
		)

	func _vec2_from_array(value: Variant, default_value: Vector2) -> Vector2:
		if value is Array and (value as Array).size() >= 2:
			return Vector2(float((value as Array)[0]), float((value as Array)[1]))
		return default_value


func load_config(validated_config: Dictionary) -> void:
	clear()
	var pack_folder := str(validated_config.get("_pack_folder", ""))
	var config_for_validation := validated_config.duplicate(true)
	for key in config_for_validation.keys():
		if str(key).begins_with("_"):
			config_for_validation.erase(key)
	var sanitized := EMSValidator.validate_config(config_for_validation)
	if not (sanitized.get("_validation_errors", []) as Array).is_empty():
		return
	sanitized.erase("_validation_errors")
	sanitized.erase("_layer_count")
	sanitized.erase("_total_particles")
	sanitized.erase("_performance_warning")
	_config = sanitized
	_events = (sanitized.get("events", []) as Array).duplicate(true)
	_apply_layout_config(sanitized.get("layout", {}) as Dictionary)
	var performance: Dictionary = sanitized.get("performance", {}) as Dictionary
	_audio_reactive_enabled = bool(performance.get("audio_reactive", true))
	_content_root = Node2D.new()
	_content_root.name = "EMSRuntimeLayoutRoot"
	add_child(_content_root)
	for layer_config in (sanitized.get("layers", []) as Array):
		if layer_config is not Dictionary:
			continue
		if not _layer_matches_gutter_filter(layer_config as Dictionary):
			continue
		var layer_root := Node2D.new()
		var layer := EMSVisualLayer.new()
		layer.configure(layer_config as Dictionary, pack_folder)
		layer_root.name = "LayerLayout_%s" % layer.layer_id
		_content_root.add_child(layer_root)
		layer_root.add_child(layer)
		_layers[layer.layer_id] = layer
		_layer_roots[layer.layer_id] = layer_root
		_layer_order.append(layer.layer_id)
	_sync_content_transform()
	set_process(true)


func clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_layers.clear()
	_layer_roots.clear()
	_layer_order.clear()
	_events.clear()
	_config.clear()
	_bloom_impulse = 0.0
	_distortion_impulse = 0.0
	_camera_shake = 0.0
	_shake_offset = Vector2.ZERO
	_audio_reactive_enabled = true
	_debug_last_event = ""
	_content_root = null
	_layout_background_region = "gutters"
	_layout_position_norm = Vector2(0.5, 0.5)
	_layout_size_norm = Vector2(1.0, 1.0)
	_layout_scale = 1.0
	_layout_rotation_degrees = 0.0


func set_gutter_filter(value: String) -> void:
	_gutter_filter = _sanitize_gutter_filter(value)


func dispatch_event(event_name: String, payload: Dictionary = {}) -> void:
	if event_name not in EMSValidator.ALLOWED_EVENTS:
		return
	_debug_last_event = event_name
	_apply_automatic_reactivity(event_name, payload)
	var now := Time.get_ticks_msec()
	for rule_variant in _events:
		if rule_variant is not Dictionary:
			continue
		var rule := rule_variant as Dictionary
		if str(rule.get("event", "")) != event_name:
			continue
		var threshold := float(rule.get("threshold", 0.0))
		if float(payload.get("strength", payload.get("value", 1.0))) < threshold:
			continue
		var rule_key := "%s:%s:%s" % [event_name, str(rule.get("action", "")), str(rule.get("target", ""))]
		var cooldown_msec := int(float(rule.get("cooldown", 0.0)) * 1000.0)
		if cooldown_msec > 0 and now - int(_last_event_msec.get(rule_key, -99999999)) < cooldown_msec:
			continue
		_last_event_msec[rule_key] = now
		_apply_action(str(rule.get("action", "")), str(rule.get("target", "")), rule.get("params", {}) as Dictionary)


func _apply_automatic_reactivity(event_name: String, payload: Dictionary) -> void:
	var source := _event_reaction_source(event_name)
	if source.is_empty():
		return
	var strength := clampf(float(payload.get("strength", payload.get("value", 1.0))), 0.0, 1.0)
	for layer_id in _layer_order:
		var layer: EMSVisualLayer = _layers.get(layer_id, null)
		if layer == null or not is_instance_valid(layer):
			continue
		match source:
			"chart":
				if _audio_reactive_enabled:
					layer.apply_chart_reaction(strength)
			"player_hit":
				layer.apply_player_hit(strength)
			"player_miss":
				layer.apply_player_miss(strength)


func _event_reaction_source(event_name: String) -> String:
	match event_name:
		"song_started", "song_section_changed", "chart_reactive", "audio_reactive", "beat", "fever_started", "fever_ended", "song_ended":
			return "chart"
		"player_hit", "near_miss", "bass_hit", "combo_changed", "combo_milestone":
			return "player_hit"
		"player_miss", "miss":
			return "player_miss"
		_:
			return ""


func update_runtime(context: Dictionary, delta: float) -> void:
	_time += delta
	_bloom_impulse = maxf(0.0, _bloom_impulse - delta * 1.5)
	_distortion_impulse = maxf(0.0, _distortion_impulse - delta * 1.2)
	_camera_shake = maxf(0.0, _camera_shake - delta * 1.8)
	var safe_context := context.duplicate(true)
	var motion := float(safe_context.get("motion_scale", 1.0))
	var profile_store := get_node_or_null("/root/ProfileStore")
	if profile_store != null and profile_store.has_method("is_prioritize_fps_enabled") and bool(profile_store.call("is_prioritize_fps_enabled")):
		motion *= 0.72
	var app_state := get_node_or_null("/root/AppState")
	if app_state != null and app_state.has_method("is_mobile_platform") and bool(app_state.call("is_mobile_platform")):
		motion *= 0.66
	safe_context["motion_scale"] = clampf(motion, 0.0, 1.0)
	for layer_id in _layer_order:
		var layer: EMSVisualLayer = _layers.get(layer_id, null)
		if layer != null and is_instance_valid(layer):
			layer.tick(delta, safe_context)
	_shake_offset = Vector2(
		sin(_time * 33.0) * _camera_shake * 12.0,
		cos(_time * 29.0) * _camera_shake * 9.0
	)
	if is_instance_valid(_content_root):
		_content_root.position = _shake_offset


func get_debug_state() -> Dictionary:
	var layer_states: Array[Dictionary] = []
	for layer_id in _layer_order:
		var layer: EMSVisualLayer = _layers.get(layer_id, null)
		if layer != null and is_instance_valid(layer):
			layer_states.append(layer.get_debug_state())
	var pack_transform := _layout_transform_debug(_pack_layout_dict(), _effective_canvas_size())
	return {
		"active": not _config.is_empty(),
		"layer_count": _layers.size(),
		"event_count": _events.size(),
		"last_event": _debug_last_event,
		"bloom": _bloom_impulse,
		"distortion": _distortion_impulse,
		"camera_shake": _camera_shake,
		"preview_canvas_size": _preview_canvas_size,
		"layout": {
			"background_region": _layout_background_region,
			"position": [_layout_position_norm.x, _layout_position_norm.y],
			"size": [_layout_size_norm.x, _layout_size_norm.y],
			"scale": _layout_scale,
			"rotation": _layout_rotation_degrees,
		},
		"layout_transform": {
			"position": pack_transform.get("position", Vector2.ZERO),
			"scale": pack_transform.get("scale", Vector2.ONE),
			"rotation": pack_transform.get("rotation", 0.0),
		},
		"gutter_filter": _gutter_filter,
		"external_position": position,
		"shake_offset": _shake_offset,
		"layers": layer_states,
	}


func set_preview_canvas_size(value: Vector2) -> void:
	_preview_canvas_size = Vector2(maxf(0.0, value.x), maxf(0.0, value.y))
	_sync_content_transform()


func get_layout_background_region() -> String:
	return _layout_background_region


func _layer_matches_gutter_filter(layer_config: Dictionary) -> bool:
	var target := _sanitize_gutter_filter(str(layer_config.get("gutter_target", "both")))
	match _gutter_filter:
		"left":
			return target == "both" or target == "left"
		"right":
			return target == "both" or target == "right"
		_:
			return true


func _apply_layout_config(layout: Dictionary) -> void:
	_layout_background_region = str(layout.get("background_region", "gutters")).strip_edges().to_lower()
	if _layout_background_region not in EMSValidator.ALLOWED_BACKGROUND_REGIONS:
		_layout_background_region = "gutters"
	_layout_position_norm = _vec2_from_array(layout.get("position", [0.5, 0.5]), Vector2(0.5, 0.5))
	_layout_position_norm.x = clampf(_layout_position_norm.x, 0.0, 1.0)
	_layout_position_norm.y = clampf(_layout_position_norm.y, 0.0, 1.0)
	_layout_size_norm = _vec2_from_array(layout.get("size", [1.0, 1.0]), Vector2(1.0, 1.0))
	_layout_size_norm.x = clampf(_layout_size_norm.x, 0.05, 2.0)
	_layout_size_norm.y = clampf(_layout_size_norm.y, 0.05, 2.0)
	_layout_scale = clampf(float(layout.get("scale", 1.0)), 0.10, 4.0)
	_layout_rotation_degrees = clampf(float(layout.get("rotation", 0.0)), -360.0, 360.0)
	_sync_content_transform()


func _sync_content_transform() -> void:
	var canvas := _effective_canvas_size()
	if is_instance_valid(_content_root):
		_content_root.position = _shake_offset
		_content_root.scale = Vector2.ONE
		_content_root.rotation = 0.0
	for index in range(_layer_order.size()):
		var layer_id := _layer_order[index]
		var layer: EMSVisualLayer = _layers.get(layer_id, null)
		var layer_root: Node2D = _layer_roots.get(layer_id, null)
		if layer != null and is_instance_valid(layer):
			var layout := _effective_layer_layout(layer_id, {})
			var position_norm := _vec2_from_array(layout.get("position", [0.5, 0.5]), Vector2(0.5, 0.5))
			var size_norm := _vec2_from_array(layout.get("size", [1.0, 1.0]), Vector2(1.0, 1.0))
			var effect_size := Vector2(
				maxf(2.0, canvas.x * size_norm.x),
				maxf(2.0, canvas.y * size_norm.y)
			)
			var transform_position := Vector2(canvas.x * position_norm.x, canvas.y * position_norm.y)
			if layer_root != null and is_instance_valid(layer_root):
				layer_root.position = transform_position
				layer_root.scale = Vector2.ONE * clampf(float(layout.get("scale", 1.0)), 0.10, 4.0)
				layer_root.rotation = deg_to_rad(clampf(float(layout.get("rotation", 0.0)), -360.0, 360.0))
				layer_root.z_index = index
			layer.position = -effect_size * 0.5
			layer.set_canvas_size(effect_size)
			layer.set_effective_layout(layout, transform_position)


func _pack_layout_dict() -> Dictionary:
	return {
		"mode": "pack",
		"source": "",
		"position": [_layout_position_norm.x, _layout_position_norm.y],
		"size": [_layout_size_norm.x, _layout_size_norm.y],
		"scale": _layout_scale,
		"rotation": _layout_rotation_degrees,
	}


func _effective_layer_layout(layer_id: String, resolving: Dictionary) -> Dictionary:
	var layer: EMSVisualLayer = _layers.get(layer_id, null)
	if layer == null or not is_instance_valid(layer):
		return _pack_layout_dict()
	if resolving.has(layer_id):
		return _pack_layout_dict()
	match layer.layout_mode:
		"custom":
			return {
				"mode": "custom",
				"source": "",
				"position": [layer.layout_position_norm.x, layer.layout_position_norm.y],
				"size": [layer.layout_size_norm.x, layer.layout_size_norm.y],
				"scale": layer.layout_scale,
				"rotation": layer.layout_rotation_degrees,
			}
		"reuse":
			if not layer.layout_source.is_empty() and _layers.has(layer.layout_source):
				resolving[layer_id] = true
				var reused := _effective_layer_layout(layer.layout_source, resolving)
				reused = reused.duplicate(true)
				reused["mode"] = "reuse"
				reused["source"] = layer.layout_source
				return reused
	return _pack_layout_dict()


func _layout_transform_debug(layout: Dictionary, canvas: Vector2) -> Dictionary:
	var position_norm := _vec2_from_array(layout.get("position", [0.5, 0.5]), Vector2(0.5, 0.5))
	var scale_value := clampf(float(layout.get("scale", 1.0)), 0.10, 4.0)
	var rotation_degrees := clampf(float(layout.get("rotation", 0.0)), -360.0, 360.0)
	return {
		"position": Vector2(canvas.x * position_norm.x, canvas.y * position_norm.y),
		"scale": Vector2.ONE * scale_value,
		"rotation": rotation_degrees,
	}


func _effective_canvas_size() -> Vector2:
	if _preview_canvas_size.x > 1.0 and _preview_canvas_size.y > 1.0:
		return _preview_canvas_size
	var viewport_size := get_viewport_rect().size
	if viewport_size.x > 1.0 and viewport_size.y > 1.0:
		return viewport_size
	return Vector2(640, 360)


func _apply_action(action: String, target: String, params: Dictionary) -> void:
	match action:
		"increase_bloom":
			_bloom_impulse = clampf(_bloom_impulse + float(params.get("amount", 0.25)), 0.0, EMSValidator.MAX_BLOOM)
			return
		"increase_distortion":
			_distortion_impulse = clampf(_distortion_impulse + float(params.get("amount", 0.20)), 0.0, EMSValidator.MAX_DISTORTION)
			return
		"shake_camera":
			_camera_shake = clampf(_camera_shake + float(params.get("amount", 0.12)), 0.0, EMSValidator.MAX_CAMERA_SHAKE)
			return
	var targets: Array[EMSVisualLayer] = []
	if target == "*":
		for layer_id in _layer_order:
			var layer: EMSVisualLayer = _layers.get(layer_id, null)
			if layer != null and is_instance_valid(layer):
				targets.append(layer)
	else:
		var layer: EMSVisualLayer = _layers.get(target, null)
		if layer != null and is_instance_valid(layer):
			targets.append(layer)
	for layer in targets:
		match action:
			"set_opacity":
				layer.set_layer_opacity(float(params.get("opacity", params.get("amount", 1.0))))
			"pulse_opacity":
				layer.pulse_opacity(float(params.get("opacity", 1.0)), float(params.get("duration", 0.22)))
			"set_color":
				layer.set_layer_color(_color_from_hex(str(params.get("color", "#55DFFFFF"))))
			"pulse_scale":
				layer.pulse_scale(float(params.get("scale", 1.25)), float(params.get("duration", 0.24)))
			"burst_particles":
				layer.burst_particles(int(params.get("count", 32)))
			"enable_layer":
				layer.enable_layer(true)
			"disable_layer":
				layer.enable_layer(false)
			"transition_palette":
				var next_colors: Array[Color] = []
				for color_text in (params.get("colors", []) as Array):
					next_colors.append(_color_from_hex(str(color_text)))
				layer.transition_palette(next_colors)


static func _color_from_hex(value: String) -> Color:
	var hex := value.strip_edges()
	if hex.begins_with("#"):
		hex = hex.substr(1)
	if hex.length() == 6:
		hex += "FF"
	if hex.length() != 8:
		return Color(0.33, 0.87, 1.0, 1.0)
	return Color(
		float(hex.substr(0, 2).hex_to_int()) / 255.0,
		float(hex.substr(2, 2).hex_to_int()) / 255.0,
		float(hex.substr(4, 2).hex_to_int()) / 255.0,
		float(hex.substr(6, 2).hex_to_int()) / 255.0
	)


static func _vec2_from_array(value: Variant, default_value: Vector2) -> Vector2:
	if value is Array and (value as Array).size() >= 2:
		return Vector2(float((value as Array)[0]), float((value as Array)[1]))
	return default_value


static func _sanitize_gutter_filter(value: String) -> String:
	var normalized := value.strip_edges().to_lower()
	match normalized:
		"left", "right":
			return normalized
		_:
			return "both"
