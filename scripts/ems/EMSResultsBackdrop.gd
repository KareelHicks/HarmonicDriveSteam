extends Control

##
# EMSResultsBackdrop
# ------------------
# Full-screen EMS-powered backdrop for ResultsMenu.
#
# Safety/readability:
# - Only active when THEME EFFECTS is enabled.
# - Uses a very low-alpha EMS ambience behind the results panel.
# - Respects the user's shader toggle (distortion layer is optional).
# - Respects EMS background color + brightness and gutter-image settings.
##

var _viewport_container: SubViewportContainer
var _viewport: SubViewport
var _viewport_root: Control
var _distortion_layer: ColorRect

var _bg_color_rect := ColorRect.new()
var _img_left := TextureRect.new()
var _img_right := TextureRect.new()

var _time := 0.0
var _last_profile_revision := -1
var _tex_cache: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(PRESET_FULL_RECT)

	# Base color layer (beneath everything).
	_bg_color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg_color_rect.set_anchors_preset(PRESET_FULL_RECT)
	add_child(_bg_color_rect)

	# Optional background image layers (beneath EMS viewport).
	for img in [_img_left, _img_right]:
		img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		img.set_anchors_preset(PRESET_FULL_RECT)
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		img.visible = false
		add_child(img)

	# EMS visuals (full screen) via SubViewport so we can optionally apply distortion.
	_viewport = SubViewport.new()
	_viewport.name = "EMSResultsViewport"
	_viewport.disable_3d = true
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.size = Vector2i(maxi(1, int(size.x)), maxi(1, int(size.y)))

	_viewport_container = SubViewportContainer.new()
	_viewport_container.name = "EMSResultsViewportContainer"
	_viewport_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport_container.set_anchors_preset(PRESET_FULL_RECT)
	_viewport_container.stretch = true
	add_child(_viewport_container)
	_viewport_container.add_child(_viewport)

	_viewport_root = Control.new()
	_viewport_root.name = "EMSResultsViewportRoot"
	_viewport_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport_root.set_anchors_preset(PRESET_FULL_RECT)
	_viewport.add_child(_viewport_root)

	_build_ems_stack()
	_refresh_shader_stack()

	set_process(true)
	resized.connect(_on_resized)
	call_deferred("_on_resized")


func _exit_tree() -> void:
	if EmotionalMotionSystem != null:
		if _distortion_layer != null and is_instance_valid(_distortion_layer):
			EmotionalMotionSystem.unregister_layer(_distortion_layer)


func _on_resized() -> void:
	if _viewport != null and (_viewport_container == null or not _viewport_container.stretch):
		_viewport.size = Vector2i(maxi(1, int(size.x)), maxi(1, int(size.y)))
	_sync_distortion_source()


func _process(delta: float) -> void:
	_time += delta
	_refresh_profile_if_needed()
	_update_background_color()


func set_results_context(result: Dictionary) -> void:
	# Drive EMS in a non-gameplay context (lightweight).
	if EmotionalMotionSystem == null:
		return

	var accuracy := float(result.get("accuracy", 0.0))
	var perfect := int(result.get("perfect", 0))
	var great := int(result.get("great", 0))
	var good := int(result.get("good", 0))
	var miss := int(result.get("miss", 0))

	var is_fc := miss == 0
	var is_pc := (miss == 0 and great == 0 and good == 0 and perfect > 0)

	EmotionalMotionSystem.set_song_bpm(float(result.get("bpm", 120.0)))

	# Map to an ambience energy target (0..1).
	var quality := clampf(accuracy / 100.0, 0.0, 1.0)
	if is_fc:
		quality = maxf(quality, 0.70)
	if is_pc:
		quality = maxf(quality, 0.85)
	EmotionalMotionSystem.set_combo_energy(quality)

	# Emotional state mapping.
	var state := "neutral"
	if is_pc or accuracy >= 95.0:
		state = "euphoric"
	elif accuracy >= 90.0:
		state = "neutral"
	elif accuracy >= 70.0:
		state = "melancholic"
	else:
		state = "chaos"
	EmotionalMotionSystem.set_emotional_state(state)

	# Celebration impulses (subtle).
	if EmotionalMotionSystem.has_method("notify_impulse"):
		EmotionalMotionSystem.notify_impulse(0.75 if is_pc else (0.55 if is_fc else 0.40), 0.25, "results_rank")
		EmotionalMotionSystem.notify_impulse(0.50, 0.62, "results_score")


func trigger_results_impulse(tag: String, strength: float, y_norm: float) -> void:
	if EmotionalMotionSystem == null:
		return
	if EmotionalMotionSystem.has_method("notify_impulse"):
		EmotionalMotionSystem.notify_impulse(clampf(strength, 0.0, 1.0), clampf(y_norm, 0.0, 1.0), tag)


func _build_ems_stack() -> void:
	# Keep only non-chart-dependent layers for the results backdrop.
	var fog_script := load("res://scripts/ems/EmotionalFogNoiseLayer.gd")
	if fog_script is Script:
		_add_background_animation_layer((fog_script as Script).new())

	var gradient_script := load("res://scripts/ems/EmotionalGradientLayer.gd")
	if gradient_script is Script:
		_add_background_animation_layer((gradient_script as Script).new())

	var ribbon_script := load("res://scripts/ems/EmotionalRibbonLayer.gd")
	if ribbon_script is Script:
		_add_background_animation_layer((ribbon_script as Script).new())

	var glyph_script := load("res://scripts/ems/EmotionalGlyphLayer.gd")
	if glyph_script is Script:
		_add_background_animation_layer((glyph_script as Script).new())


func _add_background_animation_layer(layer: Node) -> void:
	var enabled := true
	if ProfileStore != null:
		enabled = ProfileStore.is_visual_effect_background_animations_enabled()
	layer.set_meta("ems_visual_effect_enabled", enabled)
	if layer is CanvasItem:
		(layer as CanvasItem).visible = enabled
	_viewport_root.add_child(layer)


func _refresh_profile_if_needed() -> void:
	if ProfileStore == null:
		return
	var rev := ProfileStore.get_profile_revision()
	if rev == _last_profile_revision:
		return
	_last_profile_revision = rev
	_refresh_shader_stack()
	_refresh_background_animation_layers()
	_refresh_images_from_profile()


func _refresh_shader_stack() -> void:
	# Respect user shader toggle.
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
		_distortion_layer.set_meta("ems_visual_effect_enabled", _shader_visual_effect_enabled())
		_distortion_layer.visible = _shader_visual_effect_enabled()
		add_child(_distortion_layer)
		_sync_distortion_source()
		if EmotionalMotionSystem != null:
			EmotionalMotionSystem.register_layer(_distortion_layer)
		_viewport_container.visible = true


func _refresh_background_animation_layers() -> void:
	var enabled := true
	if ProfileStore != null:
		enabled = ProfileStore.is_visual_effect_background_animations_enabled()
	for child in _viewport_root.get_children():
		if child is Node:
			(child as Node).set_meta("ems_visual_effect_enabled", enabled)
			(child as Node).set_process(enabled)
		if child is CanvasItem:
			(child as CanvasItem).visible = enabled


func _shader_visual_effect_enabled() -> bool:
	if ProfileStore == null:
		return true
	return ProfileStore.is_visual_effect_distortion_enabled() or ProfileStore.is_visual_effect_bloom_enabled()


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


func _update_background_color() -> void:
	if EmotionalMotionSystem == null:
		_bg_color_rect.color = Color(0.02, 0.03, 0.08, 1.0)
		return
	_bg_color_rect.color = EmotionalMotionSystem.get_gutter_background_color()


func _refresh_images_from_profile() -> void:
	if ProfileStore == null:
		return
	var mode := ProfileStore.get_ems_gutter_image_mode()
	var alpha := clampf(ProfileStore.get_ems_gutter_image_alpha(), 0.0, 1.0)

	var left_path := ""
	var right_path := ""
	match mode:
		"both":
			var p := ProfileStore.get_ems_gutter_image_path_both()
			left_path = p
			right_path = p
		"separate":
			left_path = ProfileStore.get_ems_gutter_image_path_left()
			right_path = ProfileStore.get_ems_gutter_image_path_right()
		_:
			left_path = ""
			right_path = ""

	_img_left.texture = _load_any_texture(left_path)
	_img_right.texture = _load_any_texture(right_path)
	_img_left.modulate = Color(1, 1, 1, alpha)
	_img_right.modulate = Color(1, 1, 1, alpha)

	# Display rules:
	# - both: show only left image full screen.
	# - separate: show left and right images full screen, but clip to halves.
	if mode == "both":
		_img_left.visible = _img_left.texture != null and alpha > 0.001
		_img_right.visible = false
		_img_left.set_anchors_preset(PRESET_FULL_RECT)
	else:
		_img_left.visible = _img_left.texture != null and alpha > 0.001
		_img_right.visible = _img_right.texture != null and alpha > 0.001
		# Clip each to its half. We implement as full rect + clip_contents containers by setting regions.
		# Simpler: use scale + position via anchors and rely on keep_aspect_covered; results are acceptable.
		_img_left.anchor_left = 0.0
		_img_left.anchor_right = 0.5
		_img_left.anchor_top = 0.0
		_img_left.anchor_bottom = 1.0
		_img_left.offset_left = 0.0
		_img_left.offset_right = 0.0
		_img_left.offset_top = 0.0
		_img_left.offset_bottom = 0.0
		_img_right.anchor_left = 0.5
		_img_right.anchor_right = 1.0
		_img_right.anchor_top = 0.0
		_img_right.anchor_bottom = 1.0
		_img_right.offset_left = 0.0
		_img_right.offset_right = 0.0
		_img_right.offset_top = 0.0
		_img_right.offset_bottom = 0.0


func _load_any_texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if _tex_cache.has(path):
		var cached: Variant = _tex_cache.get(path)
		return cached as Texture2D if cached is Texture2D else null

	if path.begins_with("res://") or path.begins_with("user://"):
		var tex: Resource = load(path)
		if tex is Texture2D:
			_tex_cache[path] = tex
			return tex

	# Absolute path: load via Image.load_from_file.
	var img: Image = Image.load_from_file(path)
	if img == null or img.get_width() <= 0:
		_tex_cache[path] = null
		return null
	var itex := ImageTexture.create_from_image(img)
	_tex_cache[path] = itex
	return itex
