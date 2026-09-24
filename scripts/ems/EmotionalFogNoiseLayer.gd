extends Node2D

##
# EmotionalFogNoiseLayer
# ---------------------
# Low-res procedural noise texture that scrolls slowly to create "fog/haze".
# No shader; texture is generated once and then drawn tiled.
##

const TEX_SIZE := 128

var _rng := RandomNumberGenerator.new()
var _tex: ImageTexture
var _offset := Vector2.ZERO
var _bounds := Vector2(1, 1)


func _ready() -> void:
	name = "EmotionalFogNoiseLayer"
	_rng.randomize()
	_tex = _make_noise_texture()
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
		_offset = Vector2.ZERO
		queue_redraw()


func ems_update(_ems: Node, delta: float) -> void:
	if EmotionalMotionSystem == null or not EmotionalMotionSystem.enabled:
		return
	_bounds = _get_bounds_size()
	var bpm := float(EmotionalMotionSystem.bpm)
	var speed := (6.0 + bpm * 0.02) * 0.6
	_offset.x = fmod(_offset.x + delta * speed, float(TEX_SIZE))
	_offset.y = fmod(_offset.y + delta * (speed * 0.65), float(TEX_SIZE))
	queue_redraw()


func _draw() -> void:
	if _tex == null:
		return
	_bounds = _get_bounds_size()
	var combo := 0.0
	var intensity := 0.0
	var style := 1.0
	var tint := Color(1, 1, 1, 1)
	if EmotionalMotionSystem != null:
		combo = float(EmotionalMotionSystem.combo_energy)
		intensity = float(EmotionalMotionSystem.intensity)
		style = EmotionalMotionSystem.get_style_multiplier()
		var layer_weight := EmotionalMotionSystem.get_loadout_layer_weight("fog", 1.0)
		if layer_weight <= 0.01:
			return
		style *= layer_weight
		# Keep fog colorful; too much white lerp reads as gray on bright gutters.
		tint = EmotionalMotionSystem.pick_color("fog", 0).lerp(Color.WHITE, 0.03)

	var alpha := (0.02 + combo * 0.05 + intensity * 0.03) * style
	alpha = clampf(alpha, 0.0, 0.12)
	tint.a = alpha

	var tile := Vector2(TEX_SIZE, TEX_SIZE)
	var start := -Vector2(_offset.x, _offset.y)
	var x := start.x
	while x < _bounds.x:
		var y := start.y
		while y < _bounds.y:
			draw_texture_rect(_tex, Rect2(Vector2(x, y), tile), false, tint)
			y += tile.y
		x += tile.x


func _make_noise_texture() -> ImageTexture:
	var img := Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	for y in TEX_SIZE:
		for x in TEX_SIZE:
			var v := _rng.randf()
			# Bias toward darker to keep it subtle; alpha will control final strength.
			var g := pow(v, 2.2)
			img.set_pixel(x, y, Color(g, g, g, 1.0))
	return ImageTexture.create_from_image(img)


func _get_bounds_size() -> Vector2:
	var parent := get_parent()
	if parent is Control:
		return (parent as Control).size
	return get_viewport_rect().size
