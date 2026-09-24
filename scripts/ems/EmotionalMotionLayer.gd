extends Control

##
# EmotionalMotionLayer
# -------------------
# Dedicated rendering root for EmotionalMotionSystem visuals.
#
# Rendering order expectation:
# - This node must sit BEHIND gameplay lanes/notes/receptors (GameScene tree order).
# - It should be confined to the playfield width so gutters/HUD remain readable.
#
# Performance expectation:
# - Phase 1 uses only lightweight CanvasItem nodes (no shaders/particles).
# - Keep updates minimal and avoid allocations in _process.
##

@onready var _pulse_rect: TextureRect = TextureRect.new()
var _gradient_layer: Control
var _particle_layer: Node2D
var _depth_layer: Node2D
var _fog_layer: Node2D
var _ribbon_layer: Node2D
var _glyph_layer: Node2D
var _ripple_layer: Node2D
var _ripple_layer_top: Node2D
var _signature_layer: Node2D
var _sandbox_node: Node2D
var _viewport_container: SubViewportContainer
var _viewport: SubViewport
var _viewport_root: Control
var _distortion_layer: ColorRect
var _gradient := Gradient.new()
var _gradient_tex := GradientTexture2D.new()
var _time := 0.0


func _ready() -> void:
	# Keep the scene node name (left/right gutter) for clarity/debugging.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true

	set_anchors_preset(PRESET_FULL_RECT)
	offset_left = 0
	offset_top = 0
	offset_right = 0
	offset_bottom = 0

	# Route all EMS visuals through a SubViewport so fullscreen distortion can be
	# applied to ambience ONLY (never to gameplay notes/HUD).
	_viewport = SubViewport.new()
	_viewport.name = "EMSViewport"
	_viewport.disable_3d = true
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.size = Vector2i(maxi(1, int(size.x)), maxi(1, int(size.y)))

	_viewport_container = SubViewportContainer.new()
	_viewport_container.name = "EMSViewportContainer"
	_viewport_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport_container.set_anchors_preset(PRESET_FULL_RECT)
	_viewport_container.stretch = true
	add_child(_viewport_container)
	_viewport_container.add_child(_viewport)

	_viewport_root = Control.new()
	_viewport_root.name = "EMSViewportRoot"
	_viewport_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport_root.set_anchors_preset(PRESET_FULL_RECT)
	_viewport.add_child(_viewport_root)

	# Show raw viewport by default (failsafe). Distortion layer, when available,
	# draws on top. This ensures ambience is still visible if the shader path fails.
	_viewport_container.visible = true

	# Optional shader stack (distortion/bloom) - controlled by user option.
	_refresh_shader_stack()
	if ProfileStore != null and not ProfileStore.profile_changed.is_connected(_on_profile_changed):
		ProfileStore.profile_changed.connect(_on_profile_changed)

	_pulse_rect.name = "BackgroundPulse"
	_pulse_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pulse_rect.set_anchors_preset(PRESET_FULL_RECT)
	_pulse_rect.offset_left = 0
	_pulse_rect.offset_top = 0
	_pulse_rect.offset_right = 0
	_pulse_rect.offset_bottom = 0
	_pulse_rect.stretch_mode = TextureRect.STRETCH_SCALE
	# Phase 2+ layers: animated atmospheric gradient(s).
	# Note: these layers register with EmotionalMotionSystem for centralized gating.
	var gradient_script := load("res://scripts/ems/EmotionalGradientLayer.gd")
	if gradient_script is Script:
		_gradient_layer = (gradient_script as Script).new()
		# Defer adding until we build full stack order.

	# Phase 5: depth planes (geometry silhouettes / structures).
	var depth_script := load("res://scripts/ems/EmotionalDepthLayer.gd")
	if depth_script is Script:
		_depth_layer = (depth_script as Script).new()
		# Defer adding until we build full stack order.

	# Phase 3: lightweight particle ambience (still subtle).
	var particle_script := load("res://scripts/ems/EmotionalParticleLayer.gd")
	if particle_script is Script:
		_particle_layer = (particle_script as Script).new()
		# Defer adding until we build full stack order.

	var fog_script := load("res://scripts/ems/EmotionalFogNoiseLayer.gd")
	if fog_script is Script:
		_fog_layer = (fog_script as Script).new()

	var ribbon_script := load("res://scripts/ems/EmotionalRibbonLayer.gd")
	if ribbon_script is Script:
		_ribbon_layer = (ribbon_script as Script).new()

	var glyph_script := load("res://scripts/ems/EmotionalGlyphLayer.gd")
	if glyph_script is Script:
		_glyph_layer = (glyph_script as Script).new()

	var signature_script := load("res://scripts/ems/EMSLoadoutSignatureLayer.gd")
	if signature_script is Script:
		_signature_layer = (signature_script as Script).new()
		if _signature_layer.has_method("set_visualizer_placement_salt"):
			var layer_name := str(name).to_lower()
			var signature_salt := 1 if layer_name.find("right") != -1 else 0
			var is_visualizer_host := layer_name == "emotionalmotionleftgutter" or layer_name == "emotionalmotionrightgutter"
			_signature_layer.call("set_visualizer_placement_salt", signature_salt, is_visualizer_host)

	var sandbox_script := load("res://systems/ems/EMSSandboxNode.gd")
	if sandbox_script is Script:
		_sandbox_node = (sandbox_script as Script).new()

	var is_playfield_layer := str(name).to_lower().find("playfield") != -1
	var ripple_script := load("res://scripts/ems/EmotionalRippleLayer.gd")
	if ripple_script is Script and not is_playfield_layer:
		_ripple_layer = (ripple_script as Script).new()
		# Configure gutter orientation + placement for the default (hitline) ripples.
		if _ripple_layer is Node:
			var side := "right" if str(name).to_lower().find("right") != -1 else "left"
			if _ripple_layer.has_method("set"):
				_ripple_layer.set("gutter_side", side)
				_ripple_layer.set("placement", "hitline")
		# Second set of ripples up top (same impulses, different placement).
		_ripple_layer_top = (ripple_script as Script).new()
		if _ripple_layer_top is Node:
			var side2 := "right" if str(name).to_lower().find("right") != -1 else "left"
			_ripple_layer_top.set("gutter_side", side2)
			_ripple_layer_top.set("placement", "top")

	# Build viewport stack (back -> front).
	for layer in [_fog_layer, _gradient_layer, _signature_layer, _sandbox_node, _depth_layer, _ribbon_layer, _particle_layer, _glyph_layer, _ripple_layer, _ripple_layer_top]:
		if layer != null:
			_viewport_root.add_child(layer)

	# Phase 1 prototype pulse (kept minimal; can be removed once richer layers exist).
	_viewport_root.add_child(_pulse_rect)

	# Subtle two-color gradient (slowly modulated).
	_gradient.colors = PackedColorArray([
		Color(0.10, 0.22, 0.45, 1.0),
		Color(0.02, 0.05, 0.12, 1.0),
	])
	_gradient.offsets = PackedFloat32Array([0.0, 1.0])

	_gradient_tex.gradient = _gradient
	_gradient_tex.width = 256
	_gradient_tex.height = 256
	_gradient_tex.fill = GradientTexture2D.FILL_LINEAR
	_gradient_tex.fill_from = Vector2(0.15, 0.0)
	_gradient_tex.fill_to = Vector2(0.85, 1.0)

	_pulse_rect.texture = _gradient_tex
	_pulse_rect.modulate = Color(1, 1, 1, 0.0)
	_refresh_visual_effect_layers()

	if EmotionalMotionSystem != null:
		EmotionalMotionSystem.register_layer(self)
		ems_on_enabled_changed(EmotionalMotionSystem.enabled)

	set_process(true)
	resized.connect(_on_resized)
	call_deferred("_on_resized")


func _on_resized() -> void:
	# Keep viewport resolution in sync with the gutter rect for correct distortion sampling.
	if _viewport == null:
		return
	if _viewport_container != null and _viewport_container.stretch:
		_sync_distortion_source()
		return
	var next := Vector2i(maxi(1, int(size.x)), maxi(1, int(size.y)))
	_viewport.size = next
	_sync_distortion_source()
	if EmotionalMotionSystem != null and EmotionalMotionSystem.debug_logging_enabled:
		print("[EMS][%s] viewport_size=%s control_size=%s" % [name, str(next), str(size)])


func _sync_distortion_source() -> void:
	if _distortion_layer == null or not is_instance_valid(_distortion_layer):
		return
	if _viewport == null:
		return
	var tex := _viewport.get_texture()
	if tex == null:
		return
	if _distortion_layer.has_method("set_source_texture"):
		_distortion_layer.call("set_source_texture", tex)


func _exit_tree() -> void:
	if ProfileStore != null and ProfileStore.profile_changed.is_connected(_on_profile_changed):
		ProfileStore.profile_changed.disconnect(_on_profile_changed)
	if EmotionalMotionSystem != null:
		if _distortion_layer != null and is_instance_valid(_distortion_layer):
			EmotionalMotionSystem.unregister_layer(_distortion_layer)
		EmotionalMotionSystem.unregister_layer(self)


func ems_on_enabled_changed(is_enabled: bool) -> void:
	# Default behavior also applied by EmotionalMotionSystem, but keeping explicit
	# here clarifies intent for future layer authors.
	visible = is_enabled
	set_process(is_enabled)


func ems_update(_ems: Node, delta: float) -> void:
	# Intentionally minimal. This is a placeholder "pulse" prototype:
	# - slow gradient color modulation
	# - opacity driven by combo_energy (via EMS)
	if EmotionalMotionSystem == null or not EmotionalMotionSystem.enabled:
		_pulse_rect.modulate.a = 0.0
		return

	_time += delta

	var combo: float = EmotionalMotionSystem.combo_energy
	var intensity: float = EmotionalMotionSystem.intensity
	var boost := 1.0
	if EmotionalMotionSystem != null:
		boost = EmotionalMotionSystem.get_visual_boost() * EmotionalMotionSystem.get_style_multiplier()

	# Keep everything subtle by default.
	var target_alpha := ((0.006 + combo * 0.030) * (0.35 + intensity * 0.65)) * boost

	# Slow modulation (no hue shifts; just gentle brightness drift).
	var drift := sin(_time * 0.22) * 0.5 + 0.5
	var top := Color(0.10, 0.22, 0.45, 1.0).lerp(Color(0.12, 0.28, 0.52, 1.0), drift * 0.35)
	var bottom := Color(0.02, 0.05, 0.12, 1.0).lerp(Color(0.03, 0.06, 0.14, 1.0), drift * 0.25)
	_gradient.set_color(0, top)
	_gradient.set_color(1, bottom)

	_pulse_rect.modulate.a = clampf(target_alpha, 0.0, 0.14)


func _on_profile_changed() -> void:
	_refresh_shader_stack()
	_refresh_visual_effect_layers()


func ems_on_loadout_changed(_ems: Node) -> void:
	_refresh_visual_effect_layers()


func _refresh_shader_stack() -> void:
	# If shaders are disabled, remove shader layers entirely and render the raw viewport.
	var shaders_enabled := true
	if ProfileStore != null:
		shaders_enabled = ProfileStore.are_shaders_enabled()

	if not shaders_enabled:
		if _distortion_layer != null and is_instance_valid(_distortion_layer):
			if EmotionalMotionSystem != null:
				EmotionalMotionSystem.unregister_layer(_distortion_layer)
			_distortion_layer.queue_free()
		_distortion_layer = null
		_viewport_container.visible = true
		return

	# Ensure distortion layer exists when shaders are enabled.
	if _distortion_layer != null and is_instance_valid(_distortion_layer):
		_distortion_layer.set_meta("ems_visual_effect_enabled", _shader_visual_effect_enabled())
		_distortion_layer.visible = _shader_visual_effect_enabled()
		_sync_distortion_source()
		return

	var distortion_script := load("res://scripts/ems/EmotionalDistortionLayer.gd")
	if distortion_script is Script:
		_distortion_layer = (distortion_script as Script).new()
		_distortion_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_distortion_layer.set_anchors_preset(PRESET_FULL_RECT)
		_distortion_layer.offset_left = 0
		_distortion_layer.offset_top = 0
		_distortion_layer.offset_right = 0
		_distortion_layer.offset_bottom = 0
		_distortion_layer.set_meta("ems_visual_effect_enabled", _shader_visual_effect_enabled())
		_distortion_layer.visible = _shader_visual_effect_enabled()
		add_child(_distortion_layer)
		# Source is whatever the SubViewport rendered (may become valid after a frame).
		_sync_distortion_source()
		if EmotionalMotionSystem != null:
			EmotionalMotionSystem.register_layer(_distortion_layer)
		_viewport_container.visible = true


func _refresh_visual_effect_layers() -> void:
	var particles_enabled := true
	var background_enabled := true
	if ProfileStore != null:
		particles_enabled = ProfileStore.is_visual_effect_particles_enabled()
		background_enabled = ProfileStore.is_visual_effect_background_animations_enabled()
	var signature_enabled := background_enabled and _signature_effect_active()
	var community_enabled := background_enabled and _community_runtime_active()
	_apply_visual_layer_toggle(_signature_layer, signature_enabled)
	_apply_visual_layer_toggle(_sandbox_node, community_enabled)
	_apply_visual_layer_toggle(_particle_layer, particles_enabled and _classic_layer_enabled("particles", true))
	_apply_visual_layer_toggle(_fog_layer, background_enabled and _classic_layer_enabled("fog", true) and not _uses_glossy_background())
	_apply_visual_layer_toggle(_gradient_layer, background_enabled and _classic_layer_enabled("gradient", true))
	_apply_visual_layer_toggle(_depth_layer, background_enabled and _classic_layer_enabled("depth", true))
	_apply_visual_layer_toggle(_ribbon_layer, background_enabled and _classic_layer_enabled("ribbon", true))
	_apply_visual_layer_toggle(_glyph_layer, background_enabled and _classic_layer_enabled("glyph", true))
	_apply_visual_layer_toggle(_ripple_layer, background_enabled and _classic_layer_enabled("ripple", true))
	_apply_visual_layer_toggle(_ripple_layer_top, background_enabled and _classic_layer_enabled("ripple", true))
	_pulse_rect.set_meta("ems_visual_effect_enabled", background_enabled)
	_pulse_rect.visible = background_enabled and _classic_layer_enabled("pulse", true)


func _uses_glossy_background() -> bool:
	if EmotionalMotionSystem != null:
		return str(EmotionalMotionSystem.background_mode) == "psychedelic"
	return ProfileStore != null and ProfileStore.get_ems_background_mode() == "psychedelic"


func _signature_effect_active() -> bool:
	return EmotionalMotionSystem != null and EmotionalMotionSystem.has_signature_effect()


func _community_runtime_active() -> bool:
	return EmotionalMotionSystem != null and EmotionalMotionSystem.has_method("has_community_runtime") and EmotionalMotionSystem.has_community_runtime()


func _classic_layer_enabled(layer_name: String, default_value: bool) -> bool:
	if EmotionalMotionSystem == null or not EmotionalMotionSystem.has_method("is_classic_layer_enabled"):
		return default_value
	return bool(EmotionalMotionSystem.call("is_classic_layer_enabled", layer_name, default_value))


func get_ems_layer_debug_state() -> Dictionary:
	return {
		"signature": _layer_enabled(_signature_layer),
		"community_sandbox": _layer_enabled(_sandbox_node),
		"gradient": _layer_enabled(_gradient_layer),
		"depth": _layer_enabled(_depth_layer),
		"particles": _layer_enabled(_particle_layer),
		"fog": _layer_enabled(_fog_layer),
		"ribbon": _layer_enabled(_ribbon_layer),
		"glyph": _layer_enabled(_glyph_layer),
		"ripple": _layer_enabled(_ripple_layer) or _layer_enabled(_ripple_layer_top),
		"pulse": _pulse_rect.visible,
	}


func _layer_enabled(layer: Node) -> bool:
	if layer == null or not is_instance_valid(layer):
		return false
	if layer.has_meta("ems_visual_effect_enabled") and not bool(layer.get_meta("ems_visual_effect_enabled")):
		return false
	if layer is CanvasItem:
		return (layer as CanvasItem).visible
	return true


func _apply_visual_layer_toggle(layer: Node, enabled: bool) -> void:
	if layer == null or not is_instance_valid(layer):
		return
	layer.set_meta("ems_visual_effect_enabled", enabled)
	if layer is CanvasItem:
		(layer as CanvasItem).visible = enabled
	layer.set_process(enabled)
	layer.set_physics_process(enabled)


func _shader_visual_effect_enabled() -> bool:
	if ProfileStore == null:
		return true
	return ProfileStore.is_visual_effect_distortion_enabled() or ProfileStore.is_visual_effect_bloom_enabled()
