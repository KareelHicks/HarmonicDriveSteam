extends SceneTree

const EMSLoadoutCatalog := preload("res://scripts/ems/EMSLoadoutCatalog.gd")

const PREVIEW_SIZE := Vector2i(640, 360)
const FRAME_COUNT := 72

var _original_profile: Dictionary = {}
var _emotional_motion_layer_script: Script


func _initialize() -> void:
	await process_frame
	var failures: Array[String] = []
	_original_profile = _profile_snapshot()
	_force_preview_profile()
	var ems := root.get_node_or_null("EmotionalMotionSystem")
	if ems == null:
		failures.append("EmotionalMotionSystem autoload is missing.")
	_emotional_motion_layer_script = load("res://scripts/ems/EmotionalMotionLayer.gd") as Script
	if _emotional_motion_layer_script == null:
		failures.append("Could not load EmotionalMotionLayer.gd.")
	if failures.is_empty():
		for loadout in EMSLoadoutCatalog.get_core_loadouts():
			var loadout_id := str(loadout.get("id", ""))
			var output_path := EMSLoadoutCatalog.get_preview_path(loadout_id)
			var result := await _capture_loadout(ems, loadout_id, output_path)
			if not bool(result.get("ok", false)):
				failures.append(str(result.get("message", "Could not capture %s." % loadout_id)))

	_restore_profile()
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("Generated %d built-in EMS preview images." % EMSLoadoutCatalog.get_core_loadouts().size())
	quit(0)


func _capture_loadout(ems: Node, loadout_id: String, output_path: String) -> Dictionary:
	ems.call("apply_loadout", loadout_id)
	ems.call("reseed_run_palette", int(abs(hash(loadout_id))) % 999999999)
	ems.call("set_song_bpm", 142.0)
	ems.call("set_note_density", 0.58)
	ems.call("set_combo_energy", 0.82)
	ems.call("set_emotional_state", "euphoric")

	var viewport := SubViewport.new()
	viewport.name = "EMSPreviewViewport_%s" % loadout_id
	viewport.disable_3d = true
	viewport.transparent_bg = false
	viewport.size = PREVIEW_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)

	var root_control := Control.new()
	root_control.name = "EMSPreviewRoot"
	root_control.size = Vector2(PREVIEW_SIZE)
	root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(root_control)

	var background := ColorRect.new()
	background.name = "EMSPreviewBackground"
	background.color = ems.call("get_gutter_background_color") as Color
	background.size = Vector2(PREVIEW_SIZE)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_control.add_child(background)

	var layer := _emotional_motion_layer_script.new() as Control
	if layer == null:
		viewport.queue_free()
		await process_frame
		return {"ok": false, "message": "Could not instantiate EmotionalMotionLayer for %s." % loadout_id}
	layer.name = "EMSPreviewLayer"
	layer.size = Vector2(PREVIEW_SIZE)
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_control.add_child(layer)

	await process_frame
	await process_frame
	ems.call("apply_loadout", loadout_id)
	ems.call("reseed_run_palette", int(abs(hash(loadout_id))) % 999999999)
	for frame in range(FRAME_COUNT):
		if frame % 12 == 0:
			ems.call("notify_judgement", frame / 12 % 5, "Perfect", 1.0, float(frame) / 60.0, 0.82)
		elif frame % 18 == 0:
			ems.call("notify_impulse", 0.72, 0.36, "ems_preview_%s" % loadout_id, frame)
		background.color = ems.call("get_gutter_background_color") as Color
		await process_frame

	var texture := viewport.get_texture()
	if texture == null:
		viewport.queue_free()
		await process_frame
		return {"ok": false, "message": "Preview viewport did not produce a texture for %s." % loadout_id}
	var image := texture.get_image()
	if image == null or image.is_empty():
		viewport.queue_free()
		await process_frame
		return {"ok": false, "message": "Preview viewport produced an empty image for %s." % loadout_id}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_path.get_base_dir()))
	var err := image.save_png(ProjectSettings.globalize_path(output_path))
	viewport.queue_free()
	await process_frame
	if err != OK:
		return {"ok": false, "message": "Could not save EMS preview for %s to %s." % [loadout_id, output_path]}
	return {"ok": true, "path": output_path}


func _force_preview_profile() -> void:
	var profile := root.get_node_or_null("ProfileStore")
	if profile == null:
		return
	profile.call("set_theme_effects_enabled", true)
	profile.call("set_shaders_enabled", true)
	profile.call("set_visual_effect_bloom_enabled", true)
	profile.call("set_visual_effect_distortion_enabled", true)
	profile.call("set_visual_effect_particles_enabled", true)
	profile.call("set_visual_effect_background_animations_enabled", true)
	profile.call("set_ems_gutter_image_mode", "off")
	profile.call("set_ems_background_brightness", 0.58)


func _restore_profile() -> void:
	var profile := root.get_node_or_null("ProfileStore")
	if profile == null or _original_profile.is_empty():
		return
	profile.set("_profile", _original_profile.duplicate(true))
	if profile.has_method("save_profile"):
		profile.call("save_profile")
	if profile.has_signal("profile_changed"):
		profile.emit_signal("profile_changed")


func _profile_snapshot() -> Dictionary:
	var profile := root.get_node_or_null("ProfileStore")
	if profile == null:
		return {}
	var value: Variant = profile.get("_profile")
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}
