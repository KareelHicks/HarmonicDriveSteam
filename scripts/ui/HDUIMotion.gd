extends RefCounted
class_name HDUIMotion

const META_ATTACHED := "_hd_ui_motion_attached"
const META_HOVER := "_hd_ui_motion_hover"
const META_FOCUS := "_hd_ui_motion_focus"
const META_TWEEN := "_hd_ui_motion_tween"
const META_BREATH := "_hd_ui_motion_breath"


static func attach_button(button: BaseButton) -> void:
	if button == null or bool(button.get_meta(META_ATTACHED, false)):
		return
	button.set_meta(META_ATTACHED, true)
	button.mouse_entered.connect(_set_hover.bind(button, true))
	button.mouse_exited.connect(_set_hover.bind(button, false))
	button.focus_entered.connect(_set_focus.bind(button, true))
	button.focus_exited.connect(_set_focus.bind(button, false))
	button.button_down.connect(_press.bind(button))
	button.button_up.connect(_release.bind(button))
	button.resized.connect(_center_pivot.bind(button))
	button.call_deferred("set_pivot_offset", button.size * 0.5)


static func attach_control(control: Control) -> void:
	if control == null or bool(control.get_meta(META_ATTACHED, false)):
		return
	control.set_meta(META_ATTACHED, true)
	control.mouse_entered.connect(_set_hover.bind(control, true))
	control.mouse_exited.connect(_set_hover.bind(control, false))
	control.focus_entered.connect(_set_focus.bind(control, true))
	control.focus_exited.connect(_set_focus.bind(control, false))
	control.resized.connect(_center_pivot.bind(control))
	control.call_deferred("set_pivot_offset", control.size * 0.5)


static func start_breathing(control: Control) -> void:
	if control == null:
		return
	if control.has_meta(META_BREATH):
		var existing: Variant = control.get_meta(META_BREATH)
		if existing is Tween and is_instance_valid(existing):
			return
	_kill_tween(control, META_BREATH)
	control.pivot_offset = control.size * 0.5
	var tween := control.create_tween()
	tween.set_loops()
	tween.tween_property(control, "scale", Vector2.ONE * 1.025, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(control, "scale", Vector2.ONE, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	control.set_meta(META_BREATH, tween)


static func stop_breathing(control: Control) -> void:
	if control == null:
		return
	if not control.has_meta(META_BREATH):
		return
	_kill_tween(control, META_BREATH)
	_tween_scale(control, Vector2.ONE, 0.12)


static func _set_hover(control: Control, active: bool) -> void:
	control.set_meta(META_HOVER, active)
	if active:
		_play_navigation_sound(0)
	_apply_rest(control)


static func _set_focus(control: Control, active: bool) -> void:
	control.set_meta(META_FOCUS, active)
	_apply_rest(control)


static func _press(control: Control) -> void:
	_tween_scale(control, Vector2.ONE * 0.965, 0.06)
	control.modulate = Color(1.10, 1.10, 1.10, 1.0)


static func _release(control: Control) -> void:
	_apply_rest(control, true)


static func _center_pivot(control: Control) -> void:
	if control == null or not is_instance_valid(control):
		return
	control.pivot_offset = control.size * 0.5


static func _apply_rest(control: Control, bounce: bool = false) -> void:
	_center_pivot(control)
	var active := bool(control.get_meta(META_HOVER, false)) or bool(control.get_meta(META_FOCUS, false))
	control.modulate = Color(1.08, 1.08, 1.08, 1.0) if active else Color.WHITE
	_tween_scale(control, Vector2.ONE * (1.045 if active else 1.0), 0.18 if bounce else 0.11)


static func _tween_scale(control: Control, target: Vector2, seconds: float) -> void:
	_kill_tween(control, META_TWEEN)
	_center_pivot(control)
	var tween := control.create_tween()
	tween.tween_property(control, "scale", target, seconds).set_trans(Tween.TRANS_BACK if target.x > 1.0 else Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	control.set_meta(META_TWEEN, tween)


static func _kill_tween(control: Control, key: String) -> void:
	if control == null or not control.has_meta(key):
		return
	var tween: Variant = control.get_meta(key)
	if tween is Tween and is_instance_valid(tween):
		(tween as Tween).kill()
	control.remove_meta(key)


static func _play_navigation_sound(direction: int) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var ui_audio := tree.root.get_node_or_null("UIAudio")
	if ui_audio == null or not ui_audio.has_method("play_navigation"):
		return
	ui_audio.call("play_navigation", direction, 0.86)
