extends SceneTree

const EMSGameplayShaderLayer := preload("res://scripts/ems/EMSGameplayShaderLayer.gd")
const HDNoteVisual := preload("res://scripts/gameplay/HDNoteVisual.gd")


func _initialize() -> void:
	var shader_layer := EMSGameplayShaderLayer.new()
	root.add_child(shader_layer)
	shader_layer.configure_effects(true, true, true)
	shader_layer.set_playfield_metrics(5, 0.86)
	shader_layer.ems_on_enabled_changed(true)
	if not _assert(shader_layer.visible, "Maximum gameplay shader layer did not become visible"):
		return
	shader_layer.queue_free()

	var note := HDNoteVisual.new()
	root.add_child(note)
	note.setup(0, Vector2(72.0, 28.0), 0.4)
	note.set_ems_maximum_shader(true, true, true)
	note.update_ems_maximum_shader(0.75, 1.25)
	if not _assert(note.material == null, "Root note material should remain unset; child parts own the shader material"):
		return
	note.queue_free()

	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.set_pixel(16, 16, Color.WHITE)
	var tex := ImageTexture.create_from_image(img)
	if not _assert(tex != null, "Hit particle texture generation failed"):
		return
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.18, 1.0])
	ramp.colors = PackedColorArray([Color.WHITE, Color(1.0, 1.0, 1.0, 0.86), Color(1.0, 1.0, 1.0, 0.0)])

	var burst := CPUParticles2D.new()
	burst.one_shot = true
	burst.amount = 20
	burst.lifetime = 0.34
	burst.explosiveness = 0.88
	burst.randomness = 0.28
	burst.lifetime_randomness = 0.22
	burst.texture = tex
	burst.color_ramp = ramp
	burst.direction = Vector2.UP
	burst.spread = 180.0
	burst.gravity = Vector2(0.0, 250.0)
	burst.initial_velocity_min = 92.0
	burst.initial_velocity_max = 225.0
	burst.angular_velocity_min = -120.0
	burst.angular_velocity_max = 120.0
	burst.scale_amount_min = 0.28
	burst.scale_amount_max = 0.92
	burst.local_coords = true
	burst.restart()
	burst.free()

	print("EMS maximum visuals smoke test passed")
	quit(0)


func _assert(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
		quit(1)
		return false
	return true
