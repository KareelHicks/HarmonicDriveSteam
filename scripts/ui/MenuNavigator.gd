extends Node
class_name MenuNavigator

const HDTheme = preload("res://scripts/ui/HDTheme.gd")

var target: Control
var back_action: Callable


static func install(host: Control, on_back: Callable = Callable()) -> MenuNavigator:
	for child in host.get_children():
		if child is MenuNavigator:
			var existing: MenuNavigator = child
			existing.target = host
			existing.back_action = on_back
			existing.call_deferred("refresh_focusables")
			return existing
	var navigator := MenuNavigator.new()
	navigator.name = "MenuNavigator"
	navigator.target = host
	navigator.back_action = on_back
	host.add_child(navigator)
	navigator.call_deferred("refresh_focusables")
	return navigator


func _ready() -> void:
	if target == null and get_parent() is Control:
		target = get_parent()
	set_process(false)
	set_process_input(_desktop_menu_navigation_enabled())
	set_process_unhandled_input(_desktop_menu_navigation_enabled())
	var connection_callable := Callable(self, "_on_joy_connection_changed")
	if not Input.joy_connection_changed.is_connected(connection_callable):
		Input.joy_connection_changed.connect(connection_callable)
	if not _desktop_menu_navigation_enabled():
		call_deferred("_disable_mobile_focus")
		return
	call_deferred("refresh_focusables")


func _input(event: InputEvent) -> void:
	# Capture navigation inputs early so built-in Control focus navigation
	# doesn't "escape" modal overlays before we can re-route focus.
	_handle_navigation_event(event, true)


func refresh_focusables() -> void:
	if target == null or not is_instance_valid(target):
		return
	if not _desktop_menu_navigation_enabled():
		_disable_mobile_focus()
		return
	if not uses_controller_focus():
		_disable_pointer_focus()
		return
	var focusables := _collect_focusables(target)
	for control in focusables:
		_prepare_focusable(control)
	_ensure_focus(focusables)


func _unhandled_input(event: InputEvent) -> void:
	# Fallback if input reaches us only after GUI controls handled it.
	_handle_navigation_event(event, false)

func _handle_navigation_event(event: InputEvent, is_early_input: bool) -> void:
	if target == null or not target.is_visible_in_tree():
		return
	if not _desktop_menu_navigation_enabled():
		return
	var is_pressed_event := false
	if event is InputEventKey:
		is_pressed_event = event.pressed and not event.echo
	elif event is InputEventJoypadButton:
		is_pressed_event = event.pressed
	elif event is InputEventJoypadMotion:
		is_pressed_event = absf(event.axis_value) >= 0.5
	elif event is InputEventAction:
		is_pressed_event = event.pressed
	if not is_pressed_event:
		return
	if _navigation_blocked():
		return
	if not uses_controller_focus():
		if _is_cancel_event(event):
			_call_back_action()
		return
	var focused_owner := target.get_viewport().gui_get_focus_owner()
	if focused_owner is LineEdit and (focused_owner as LineEdit).has_focus():
		# Early stage: let the LineEdit consume enter/arrows for text editing/submission.
		# Late stage: if the LineEdit didn't consume it, prevent focus navigation.
		if _is_cancel_event(event):
			if _call_back_action():
				return
			return
		if is_early_input:
			return
		if _is_accept_event(event):
			(focused_owner as LineEdit).release_focus()
			refresh_focusables()
			var focusables := _sorted_controls(_collect_focusables(target))
			if not focusables.is_empty():
				var preferred := _preferred_initial_focus(focusables)
				preferred.grab_focus()
				_scroll_control_into_view(preferred)
			get_viewport().set_input_as_handled()
			return
		if _is_direction_event(event):
			get_viewport().set_input_as_handled()
			return
		return
	if _is_cancel_event(event):
		if _call_back_action():
			return
		return
	refresh_focusables()
	if _is_accept_event(event):
		if _activate_focused():
			get_viewport().set_input_as_handled()
		return
	var direction := Vector2.ZERO
	# Joypad motion events don't always report as ui_up/ui_down actions reliably, so map common axes
	# directly to avoid input "fallthrough" that can move focus to background controls.
	if event is InputEventJoypadMotion:
		var motion: InputEventJoypadMotion = event
		if motion.axis == JOY_AXIS_LEFT_Y or motion.axis == JOY_AXIS_RIGHT_Y:
			if motion.axis_value <= -0.5:
				direction = Vector2.UP
			elif motion.axis_value >= 0.5:
				direction = Vector2.DOWN
		elif motion.axis == JOY_AXIS_LEFT_X or motion.axis == JOY_AXIS_RIGHT_X:
			if motion.axis_value <= -0.5:
				direction = Vector2.LEFT
			elif motion.axis_value >= 0.5:
				direction = Vector2.RIGHT
	if event.is_action_pressed("ui_up"):
		direction = Vector2.UP
	elif event.is_action_pressed("ui_down"):
		direction = Vector2.DOWN
	elif event.is_action_pressed("ui_left"):
		direction = Vector2.LEFT
	elif event.is_action_pressed("ui_right"):
		direction = Vector2.RIGHT
	if direction != Vector2.ZERO and _move_focus(direction):
		get_viewport().set_input_as_handled()


func uses_controller_focus() -> bool:
	return _desktop_menu_navigation_enabled() and not Input.get_connected_joypads().is_empty()


func _navigation_blocked() -> bool:
	return target != null and target.has_method("is_menu_navigation_blocked") and bool(target.call("is_menu_navigation_blocked"))


func _desktop_menu_navigation_enabled() -> bool:
	return not AppState.is_mobile_platform()


func _collect_focusables(node: Node) -> Array[Control]:
	var result: Array[Control] = []
	for child in node.get_children():
		if child is Control:
			var control: Control = child
			if control.is_visible_in_tree() and _is_focusable(control) and _control_allowed_for_navigation(control):
				result.append(control)
		result.append_array(_collect_focusables(child))
	return result


func _disable_mobile_focus() -> void:
	if target == null or not is_instance_valid(target):
		return
	var controls := _collect_all_controls(target)
	for control in controls:
		control.focus_mode = Control.FOCUS_NONE
	var focused := target.get_viewport().gui_get_focus_owner()
	if focused is Control:
		(focused as Control).release_focus()


func _disable_pointer_focus() -> void:
	if target == null or not is_instance_valid(target):
		return
	var controls := _collect_all_controls(target)
	for control in controls:
		if _preserves_text_focus(control):
			continue
		control.focus_mode = Control.FOCUS_NONE
	var focused := target.get_viewport().gui_get_focus_owner()
	if focused is Control and not _preserves_text_focus(focused as Control):
		(focused as Control).release_focus()


func _preserves_text_focus(control: Control) -> bool:
	return control is LineEdit or control is TextEdit


func _collect_all_controls(node: Node) -> Array[Control]:
	var result: Array[Control] = []
	for child in node.get_children():
		if child is Control:
			result.append(child)
		result.append_array(_collect_all_controls(child))
	return result


func _is_focusable(control: Control) -> bool:
	if _is_back_button(control):
		return false
	if control is BaseButton:
		return not (control as BaseButton).disabled
	return control.has_method("activate")


func _is_back_button(control: Control) -> bool:
	var control_name: String = str(control.name)
	return control_name == "BackButton"


func _control_allowed_for_navigation(control: Control) -> bool:
	return target == null or not target.has_method("is_menu_focusable_control") or bool(target.call("is_menu_focusable_control", control))


func _prepare_focusable(control: Control) -> void:
	control.focus_mode = Control.FOCUS_ALL
	if control.has_meta("menu_navigator_prepared"):
		return
	control.set_meta("menu_navigator_prepared", true)
	if control is BaseButton:
		var button: BaseButton = control
		button.add_theme_stylebox_override("focus", HDTheme.button_style(true))


func _ensure_focus(focusables: Array[Control]) -> void:
	if focusables.is_empty():
		return
	var focused := target.get_viewport().gui_get_focus_owner()
	if focused in focusables:
		_scroll_control_into_view(focused)
		return
	var preferred := _preferred_initial_focus(focusables)
	preferred.grab_focus()
	_scroll_control_into_view(preferred)


func _move_focus(direction: Vector2) -> bool:
	var focusables := _sorted_controls(_collect_focusables(target))
	if focusables.is_empty():
		return false
	var current := target.get_viewport().gui_get_focus_owner()
	if not (current is Control) or not focusables.has(current):
		var preferred := _preferred_initial_focus(focusables)
		preferred.grab_focus()
		_scroll_control_into_view(preferred)
		_play_navigation_sound(direction)
		return true
	var current_control: Control = current
	var current_center := current_control.get_global_rect().get_center()
	var best: Control
	var best_score := INF
	for candidate in focusables:
		if candidate == current_control:
			continue
		var delta := candidate.get_global_rect().get_center() - current_center
		var primary := 0.0
		var secondary := 0.0
		if direction == Vector2.UP:
			primary = -delta.y
			secondary = absf(delta.x)
		elif direction == Vector2.DOWN:
			primary = delta.y
			secondary = absf(delta.x)
		elif direction == Vector2.LEFT:
			primary = -delta.x
			secondary = absf(delta.y)
		elif direction == Vector2.RIGHT:
			primary = delta.x
			secondary = absf(delta.y)
		if primary <= 2.0:
			continue
		var score := primary + secondary * 0.35
		if score < best_score:
			best_score = score
			best = candidate
	if best == null:
		var current_index := focusables.find(current_control)
		if current_index == -1:
			var fallback := _preferred_initial_focus(focusables)
			fallback.grab_focus()
			_scroll_control_into_view(fallback)
			_play_navigation_sound(direction)
			return true
		var step := -1 if direction == Vector2.UP or direction == Vector2.LEFT else 1
		var wrapped_index := posmod(current_index + step, focusables.size())
		best = focusables[wrapped_index]
	best.grab_focus()
	_scroll_control_into_view(best)
	_play_navigation_sound(direction)
	return true


func _activate_focused() -> bool:
	var focused := target.get_viewport().gui_get_focus_owner()
	if not (focused is Control):
		return false
	if focused is BaseButton:
		var button: BaseButton = focused
		if button.disabled:
			return false
		button.emit_signal("pressed")
		return true
	if focused.has_method("activate"):
		focused.call("activate")
		return true
	return false


func _sorted_controls(controls: Array[Control]) -> Array[Control]:
	var sorted: Array[Control] = controls.duplicate()
	sorted.sort_custom(func(a: Control, b: Control) -> bool:
		var rect_a := a.get_global_rect()
		var rect_b := b.get_global_rect()
		if absf(rect_a.position.y - rect_b.position.y) > 18.0:
			return rect_a.position.y < rect_b.position.y
		return rect_a.position.x < rect_b.position.x
	)
	return sorted


func _preferred_initial_focus(focusables: Array[Control]) -> Control:
	if target != null and target.has_method("get_initial_menu_focus"):
		var preferred: Variant = target.call("get_initial_menu_focus")
		if preferred is Control and focusables.has(preferred):
			return preferred
	return _sorted_controls(focusables)[0]


func _scroll_control_into_view(control: Control) -> void:
	var node: Node = control
	while node != null:
		node = node.get_parent()
		if node is ScrollContainer:
			(node as ScrollContainer).ensure_control_visible(control)
			return


func _play_navigation_sound(direction: Vector2) -> void:
	var ui_audio := _ui_audio()
	if ui_audio == null or not ui_audio.has_method("play_navigation"):
		return
	var horizontal := int(sign(direction.x))
	var vertical := int(sign(direction.y))
	ui_audio.call("play_navigation", horizontal if horizontal != 0 else vertical)


func _ui_audio() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null("UIAudio")


func _on_joy_connection_changed(_device: int, _connected: bool) -> void:
	if not _desktop_menu_navigation_enabled():
		return
	call_deferred("refresh_focusables")


func _call_back_action() -> bool:
	if not back_action.is_valid():
		return false
	back_action.call()
	get_viewport().set_input_as_handled()
	return true


func _is_cancel_event(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_cancel"):
		return true
	if event is InputEventKey:
		return (event as InputEventKey).keycode == KEY_ESCAPE
	return false


func _is_accept_event(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_accept"):
		return true
	if event is InputEventKey:
		var key_event := event as InputEventKey
		return key_event.keycode == KEY_ENTER or key_event.keycode == KEY_KP_ENTER
	return false


func _is_direction_event(event: InputEvent) -> bool:
	return event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down") or event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right")
