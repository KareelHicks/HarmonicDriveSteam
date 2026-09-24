extends Control

const HDTheme = preload("res://scripts/ui/HDTheme.gd")
const MobileScrollButtonScript = preload("res://scripts/ui/MobileScrollButton.gd")
const MenuNavigator = preload("res://scripts/ui/MenuNavigator.gd")

signal back_requested

const REQUIRED_TAPS := 8
const BPM := 120.0
const CLICK_DURATION_FRAMES := 2205
const TARGET_TICK_COUNT := 8

enum CalibrationState {
	IDLE,
	RUNNING,
	COMPLETE,
}

@onready var _back_button: Button = $BackButton
@onready var _target_button: Button = %TargetButton
@onready var _start_button: Button = %StartButton
@onready var _reset_button: Button = %ResetButton
@onready var _progress_dots: HBoxContainer = %ProgressDots
@onready var _tick_layer: Control = %TickLayer

var _state: CalibrationState = CalibrationState.IDLE
var _start_time := 0.0
var _tap_offsets: Array[float] = []
var _player := AudioStreamPlayer.new()
var _generator := AudioStreamGenerator.new()
var _playback: AudioStreamGeneratorPlayback
var _last_click_beat := -1
var _menu_navigator: MenuNavigator
var _intro_acknowledged := false
var _dot_nodes: Array[Panel] = []
var _tick_nodes: Array[ColorRect] = []


func _ready() -> void:
	_apply_mobile_scroll_buttons()
	_menu_navigator = MenuNavigator.install(self, Callable(self, "_on_back_button_pressed"))
	_setup_audio()
	_build_progress_dots()
	_build_target_ticks()
	_apply_layout()
	get_viewport().size_changed.connect(_apply_layout)
	set_process(true)
	_set_idle_state()


func _setup_audio() -> void:
	%Background.color = HDTheme.BG
	add_child(_player)
	_generator.mix_rate = 44100
	_generator.buffer_length = 0.1
	_player.stream = _generator
	_player.play()
	_playback = _player.get_stream_playback()


func _apply_layout() -> void:
	var size := get_viewport_rect().size
	var is_mobile := AppState.is_mobile_platform()
	var title_width: float = minf(size.x - 48.0, 680.0)
	var pulse_size: float = 180.0 if is_mobile else 168.0
	var card_width: float = minf(size.x - 40.0, 520.0)
	var intro_width: float = minf(size.x - 40.0, 520.0)
	var helper_width: float = minf(size.x - 48.0, 720.0)
	var bottom_width: float = minf(size.x - 48.0, 520.0)
	var progress_width: float = minf(size.x - 80.0, 320.0)
	var bottom_cluster_top: float = size.y * (0.74 if is_mobile else 0.76)
	var tap_count_top: float = bottom_cluster_top + 44.0
	var status_top: float = tap_count_top + 38.0
	var actions_top: float = status_top + 54.0

	%MidBand.color = Color(0.07, 0.07, 0.20, 0.70)
	%MidBand.offset_top = size.y * 0.52
	%MidBand.offset_bottom = size.y * 0.74

	HDTheme.apply_label(%BackLabel, "caption", HDTheme.SECONDARY)
	%BackLabel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	HDTheme.apply_back_button(_back_button, %BackLabel)
	_back_button.offset_left = 24.0
	_back_button.offset_top = 24.0
	_back_button.offset_right = 160.0
	_back_button.offset_bottom = 64.0

	%HeaderBox.offset_left = size.x * 0.5 - title_width * 0.5
	%HeaderBox.offset_top = 22.0 if is_mobile else 18.0
	%HeaderBox.offset_right = %HeaderBox.offset_left + title_width
	%HeaderBox.offset_bottom = %HeaderBox.offset_top + 120.0
	%HeaderBox.add_theme_constant_override("separation", 6)
	HDTheme.apply_label(%TitleLabel, "screen_title", HDTheme.CYAN, true)
	HDTheme.apply_label(%SubtitleLabel, "section_title", HDTheme.primary_text(), true)
	HDTheme.apply_label(%BeatCenterLabel, "section_title", HDTheme.primary_text(), true)

	%PulseWrap.offset_left = size.x * 0.5 - pulse_size * 0.5
	%PulseWrap.offset_top = size.y * 0.29
	%PulseWrap.offset_right = %PulseWrap.offset_left + pulse_size
	%PulseWrap.offset_bottom = %PulseWrap.offset_top + pulse_size
	%PulseStack.custom_minimum_size = Vector2(pulse_size, pulse_size)
	%TargetButton.size = Vector2(pulse_size, pulse_size)
	_layout_target_visuals(pulse_size)
	_layout_target_ticks(pulse_size)

	%InstructionCard.offset_left = size.x * 0.5 - intro_width * 0.5
	%InstructionCard.offset_top = size.y * 0.5 - 120.0
	%InstructionCard.offset_right = %InstructionCard.offset_left + card_width
	%InstructionCard.offset_bottom = %InstructionCard.offset_top + (250.0 if is_mobile else 238.0)
	%InstructionCard.add_theme_stylebox_override("panel", _instruction_card_style())
	%InstructionMargin.add_theme_constant_override("margin_left", 28)
	%InstructionMargin.add_theme_constant_override("margin_top", 24)
	%InstructionMargin.add_theme_constant_override("margin_right", 28)
	%InstructionMargin.add_theme_constant_override("margin_bottom", 24)
	%InstructionVBox.add_theme_constant_override("separation", 16)
	HDTheme.apply_label(%CardTitleLabel, "section_title", HDTheme.CYAN, true)
	HDTheme.apply_label(%CardBodyLabel, "body", HDTheme.SECONDARY, true)
	HDTheme.apply_label(%CardOffsetLabel, "supporting", HDTheme.TERTIARY, true)

	_style_button(_start_button, true, size)
	_style_button(_reset_button, false, size)
	_style_button(%OkayButton, true, size)
	_target_button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	_target_button.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	_target_button.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	_target_button.focus_mode = Control.FOCUS_NONE
	%CardButtons.add_theme_constant_override("separation", 12)

	%ProgressWrap.offset_left = size.x * 0.5 - progress_width * 0.5
	%ProgressWrap.offset_top = bottom_cluster_top
	%ProgressWrap.offset_right = %ProgressWrap.offset_left + progress_width
	%ProgressWrap.offset_bottom = %ProgressWrap.offset_top + 24.0
	_progress_dots.add_theme_constant_override("separation", 12)
	_update_progress_dot_styles()

	%TapCountLabel.offset_left = size.x * 0.5 - helper_width * 0.5
	%TapCountLabel.offset_top = tap_count_top
	%TapCountLabel.offset_right = %TapCountLabel.offset_left + helper_width
	%TapCountLabel.offset_bottom = %TapCountLabel.offset_top + 30.0
	HDTheme.apply_label(%TapCountLabel, "body", HDTheme.TERTIARY, true)

	%StatusLabel.offset_left = size.x * 0.5 - helper_width * 0.5
	%StatusLabel.offset_top = status_top
	%StatusLabel.offset_right = %StatusLabel.offset_left + helper_width
	%StatusLabel.offset_bottom = %StatusLabel.offset_top + 30.0
	HDTheme.apply_label(%StatusLabel, "body", HDTheme.SECONDARY, true)

	%BottomActions.offset_left = size.x * 0.5 - bottom_width * 0.5
	%BottomActions.offset_top = actions_top
	%BottomActions.offset_right = %BottomActions.offset_left + bottom_width
	%BottomActions.offset_bottom = %BottomActions.offset_top + 110.0
	%BottomActions.add_theme_constant_override("separation", 12)
	HDTheme.apply_label(%RunningHintLabel, "body", HDTheme.CYAN, true)
	_style_button(%BottomResetButton, false, size)
	%BottomResetButton.visible = _state == CalibrationState.RUNNING

	_update_progress_dot_styles()


func _instruction_card_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.09, 0.22, 0.94)
	style.border_color = Color(HDTheme.CYAN.r, HDTheme.CYAN.g, HDTheme.CYAN.b, 0.34)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 26
	style.corner_radius_top_right = 26
	style.corner_radius_bottom_left = 26
	style.corner_radius_bottom_right = 26
	style.shadow_color = Color(0, 0, 0, 0.2)
	style.shadow_size = 10
	return style


func _style_button(button: Button, primary: bool, size: Vector2) -> void:
	button.custom_minimum_size = Vector2(0, 54.0 if AppState.is_mobile_platform() else 50.0)
	button.add_theme_stylebox_override("normal", HDTheme.button_style(primary))
	button.add_theme_stylebox_override("hover", HDTheme.button_style(primary))
	button.add_theme_stylebox_override("pressed", HDTheme.button_style(primary))
	button.add_theme_font_size_override("font_size", HDTheme.text_size("button_secondary", size))


func _layout_target_visuals(pulse_size: float) -> void:
	var center := Vector2.ONE * (pulse_size * 0.5)
	var outer_size := pulse_size
	var glow_size := pulse_size * 0.76
	var pulse_core_size := pulse_size * 0.68
	var center_dot_size := maxf(10.0, pulse_size * 0.06)
	var label_height := pulse_size * 0.26
	var outer_style := StyleBoxFlat.new()
	outer_style.bg_color = Color(0.06, 0.08, 0.17, 0.72)
	outer_style.border_color = Color(1, 1, 1, 0.08)
	outer_style.border_width_left = 2
	outer_style.border_width_top = 2
	outer_style.border_width_right = 2
	outer_style.border_width_bottom = 2
	outer_style.corner_radius_top_left = int(pulse_size)
	outer_style.corner_radius_top_right = int(pulse_size)
	outer_style.corner_radius_bottom_right = int(pulse_size)
	outer_style.corner_radius_bottom_left = int(pulse_size)
	%OuterRing.add_theme_stylebox_override("panel", outer_style)

	var inner_style := StyleBoxFlat.new()
	inner_style.bg_color = Color(0.10, 0.19, 0.30, 0.78)
	inner_style.border_color = Color(HDTheme.CYAN.r, HDTheme.CYAN.g, HDTheme.CYAN.b, 0.46)
	inner_style.border_width_left = 2
	inner_style.border_width_top = 2
	inner_style.border_width_right = 2
	inner_style.border_width_bottom = 2
	inner_style.corner_radius_top_left = int(pulse_size)
	inner_style.corner_radius_top_right = int(pulse_size)
	inner_style.corner_radius_bottom_right = int(pulse_size)
	inner_style.corner_radius_bottom_left = int(pulse_size)
	%Pulse.add_theme_stylebox_override("panel", inner_style)

	var glow_style := StyleBoxFlat.new()
	glow_style.bg_color = Color(HDTheme.CYAN.r, HDTheme.CYAN.g, HDTheme.CYAN.b, 0.05)
	glow_style.border_color = Color(HDTheme.CYAN.r, HDTheme.CYAN.g, HDTheme.CYAN.b, 0.24)
	glow_style.border_width_left = 2
	glow_style.border_width_top = 2
	glow_style.border_width_right = 2
	glow_style.border_width_bottom = 2
	glow_style.corner_radius_top_left = int(pulse_size)
	glow_style.corner_radius_top_right = int(pulse_size)
	glow_style.corner_radius_bottom_right = int(pulse_size)
	glow_style.corner_radius_bottom_left = int(pulse_size)
	%PulseGlow.add_theme_stylebox_override("panel", glow_style)

	var core_style := StyleBoxFlat.new()
	core_style.bg_color = HDTheme.CYAN
	core_style.corner_radius_top_left = 100
	core_style.corner_radius_top_right = 100
	core_style.corner_radius_bottom_left = 100
	core_style.corner_radius_bottom_right = 100
	%CenterDot.add_theme_stylebox_override("panel", core_style)

	%OuterRing.position = center - Vector2.ONE * (outer_size * 0.5)
	%OuterRing.size = Vector2.ONE * outer_size
	%OuterRing.pivot_offset = %OuterRing.size * 0.5
	%PulseGlow.position = center - Vector2.ONE * (glow_size * 0.5)
	%PulseGlow.size = Vector2.ONE * glow_size
	%PulseGlow.pivot_offset = %PulseGlow.size * 0.5
	%Pulse.position = center - Vector2.ONE * (pulse_core_size * 0.5)
	%Pulse.size = Vector2.ONE * pulse_core_size
	%Pulse.pivot_offset = %Pulse.size * 0.5
	%CenterDot.position = center - Vector2.ONE * (center_dot_size * 0.5)
	%CenterDot.size = Vector2.ONE * center_dot_size
	%CenterDot.pivot_offset = %CenterDot.size * 0.5
	%BeatCenterLabel.position = Vector2(0.0, center.y - label_height * 0.5 + pulse_size * 0.01)
	%BeatCenterLabel.size = Vector2.ONE * pulse_size
	%BeatCenterLabel.size.y = label_height


func _build_progress_dots() -> void:
	if not _dot_nodes.is_empty():
		return
	for _index in range(REQUIRED_TAPS):
		var dot := Panel.new()
		dot.custom_minimum_size = Vector2(12, 12)
		_progress_dots.add_child(dot)
		_dot_nodes.append(dot)


func _update_progress_dot_styles() -> void:
	var active_count := _tap_offsets.size()
	for index in range(_dot_nodes.size()):
		var dot := _dot_nodes[index]
		var style := StyleBoxFlat.new()
		var active := index < active_count
		style.bg_color = HDTheme.CYAN if active else Color(1, 1, 1, 0.10)
		style.border_color = Color(HDTheme.CYAN.r, HDTheme.CYAN.g, HDTheme.CYAN.b, 0.36) if active else Color(1, 1, 1, 0.18)
		style.border_width_left = 1
		style.border_width_top = 1
		style.border_width_right = 1
		style.border_width_bottom = 1
		style.corner_radius_top_left = 12
		style.corner_radius_top_right = 12
		style.corner_radius_bottom_left = 12
		style.corner_radius_bottom_right = 12
		dot.add_theme_stylebox_override("panel", style)


func _build_target_ticks() -> void:
	if not _tick_nodes.is_empty():
		return
	for _index in range(TARGET_TICK_COUNT):
		var tick := ColorRect.new()
		tick.color = Color(1, 1, 1, 0.16)
		tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_tick_layer.add_child(tick)
		_tick_nodes.append(tick)


func _layout_target_ticks(pulse_size: float) -> void:
	var radius := pulse_size * 0.48
	var tick_length := pulse_size * 0.06
	var tick_thickness := 2.0
	var center := Vector2.ONE * (pulse_size * 0.5)
	for index in range(_tick_nodes.size()):
		var tick := _tick_nodes[index]
		var angle := TAU * float(index) / float(_tick_nodes.size())
		tick.size = Vector2(tick_thickness, tick_length)
		tick.pivot_offset = Vector2(tick_thickness * 0.5, tick_length)
		tick.position = center + Vector2(cos(angle), sin(angle)) * radius - Vector2(tick_thickness * 0.5, tick_length)
		tick.rotation = angle + PI * 0.5


func _process(_delta: float) -> void:
	if _state != CalibrationState.RUNNING:
		return
	var beat_interval := 60.0 / BPM
	var elapsed := Time.get_ticks_msec() / 1000.0 - _start_time
	var beat_phase: float = fmod(elapsed, beat_interval) / beat_interval
	var normalized := 1.0 - beat_phase
	var pulse_scale := lerpf(0.94, 1.05, normalized)
	var glow_scale := lerpf(0.94, 1.12, normalized)
	var alpha := lerpf(0.34, 1.0, normalized)
	%Pulse.scale = Vector2.ONE * pulse_scale
	%PulseGlow.scale = Vector2.ONE * glow_scale
	%Pulse.modulate = Color(HDTheme.CYAN.r, HDTheme.CYAN.g, HDTheme.CYAN.b, alpha)
	%PulseGlow.modulate = Color(HDTheme.CYAN.r, HDTheme.CYAN.g, HDTheme.CYAN.b, alpha * 0.42)
	var beat_index := int(floor(elapsed / beat_interval))
	if beat_index != _last_click_beat and _playback != null:
		_last_click_beat = beat_index
		_write_click()


func _write_click() -> void:
	if _playback.get_frames_available() < 3000:
		return
	for frame_index in range(CLICK_DURATION_FRAMES):
		var envelope := exp(-float(frame_index) / 220.0)
		var sample := sin(float(frame_index) * 0.25) * envelope * 0.45
		_playback.push_frame(Vector2(sample, sample))


func _set_idle_state() -> void:
	_state = CalibrationState.IDLE
	_tap_offsets.clear()
	_last_click_beat = -1
	_target_button.disabled = true
	_target_button.visible = AppState.is_mobile_platform()
	%InstructionCard.visible = true
	%OkayButton.visible = not _intro_acknowledged
	_start_button.visible = _intro_acknowledged
	_reset_button.visible = _intro_acknowledged
	%CardTitleLabel.text = "AUDIO CALIBRATION"
	%CardBodyLabel.text = _idle_body_text()
	%CardOffsetLabel.text = "CURRENT OFFSET  %d ms" % int(round(ProfileStore.get_latency_offset_ms()))
	%StatusLabel.text = "Use the metronome to line up your taps."
	%TapCountLabel.text = "0 / %d TAPS" % REQUIRED_TAPS
	%RunningHintLabel.visible = false
	%BottomResetButton.visible = false
	%BeatCenterLabel.text = "START"
	%Pulse.scale = Vector2.ONE
	%PulseGlow.scale = Vector2.ONE
	%Pulse.modulate = Color(HDTheme.CYAN.r, HDTheme.CYAN.g, HDTheme.CYAN.b, 0.32)
	%PulseGlow.modulate = Color(HDTheme.CYAN.r, HDTheme.CYAN.g, HDTheme.CYAN.b, 0.14)
	_update_progress_dot_styles()


func _set_running_state() -> void:
	_state = CalibrationState.RUNNING
	_tap_offsets.clear()
	_last_click_beat = -1
	_start_time = Time.get_ticks_msec() / 1000.0
	_target_button.disabled = not AppState.is_mobile_platform()
	_target_button.visible = AppState.is_mobile_platform()
	%InstructionCard.visible = false
	%RunningHintLabel.visible = true
	%RunningHintLabel.text = "Tap the center target on every click." if AppState.is_mobile_platform() else "Press any key on every click."
	%BottomResetButton.visible = true
	%StatusLabel.text = "Latest tap: --"
	%TapCountLabel.text = "0 / %d TAPS" % REQUIRED_TAPS
	%BeatCenterLabel.text = "TAP"
	_update_progress_dot_styles()


func _set_complete_state(average_ms: float) -> void:
	_state = CalibrationState.COMPLETE
	_target_button.disabled = true
	_target_button.visible = false
	%InstructionCard.visible = true
	%OkayButton.visible = false
	_start_button.visible = true
	_reset_button.visible = true
	%CardTitleLabel.text = "CALIBRATION SAVED"
	%CardBodyLabel.text = "A beat played at 120 BPM.\nYour average timing offset has been saved.\nRun calibration again any time if the game feels early or late."
	%CardOffsetLabel.text = "SAVED OFFSET  %d ms" % int(round(average_ms))
	%StatusLabel.text = "Saved average offset: %d ms" % int(round(average_ms))
	%TapCountLabel.text = "%d / %d TAPS" % [_tap_offsets.size(), REQUIRED_TAPS]
	%RunningHintLabel.visible = false
	%BottomResetButton.visible = false
	%BeatCenterLabel.text = "DONE"
	%Pulse.scale = Vector2.ONE
	%PulseGlow.scale = Vector2.ONE
	%Pulse.modulate = Color(HDTheme.CYAN.r, HDTheme.CYAN.g, HDTheme.CYAN.b, 0.82)
	%PulseGlow.modulate = Color(HDTheme.CYAN.r, HDTheme.CYAN.g, HDTheme.CYAN.b, 0.28)
	_update_progress_dot_styles()


func _idle_body_text() -> String:
	if AppState.is_mobile_platform():
		return "A beat will play at 120 BPM.\nTap the center circle each time you hear the click.\nAfter 8 taps your offset is saved."
	return "A beat will play at 120 BPM.\nPress any key each time you hear the click.\nAfter 8 taps your offset is saved."


func _on_start_button_pressed() -> void:
	_set_running_state()


func _on_okay_button_pressed() -> void:
	_intro_acknowledged = true
	_set_idle_state()


func _register_calibration_tap() -> void:
	if _state != CalibrationState.RUNNING:
		return
	var now := Time.get_ticks_msec() / 1000.0
	var beat_interval := 60.0 / BPM
	var elapsed := now - _start_time
	var nearest_beat: float = round(elapsed / beat_interval) * beat_interval
	var offset_ms: float = (elapsed - nearest_beat) * 1000.0
	_tap_offsets.append(offset_ms)
	%TapCountLabel.text = "%d / %d TAPS" % [_tap_offsets.size(), REQUIRED_TAPS]
	%StatusLabel.text = "Latest tap: %s%d ms" % ["+" if offset_ms >= 0.0 else "", int(round(offset_ms))]
	_update_progress_dot_styles()
	if _tap_offsets.size() >= REQUIRED_TAPS:
		var average := 0.0
		for offset in _tap_offsets:
			average += offset
		average /= float(_tap_offsets.size())
		ProfileStore.set_latency_offset_ms(average)
		_set_complete_state(average)


func _on_target_button_pressed() -> void:
	if AppState.is_mobile_platform():
		_register_calibration_tap()


func _on_reset_button_pressed() -> void:
	ProfileStore.set_latency_offset_ms(0.0)
	_set_idle_state()
	%StatusLabel.text = "Offset reset to 0 ms."


func _on_bottom_reset_button_pressed() -> void:
	_on_reset_button_pressed()


func _on_back_button_pressed() -> void:
	back_requested.emit()


func _unhandled_input(event: InputEvent) -> void:
	if _state != CalibrationState.RUNNING:
		return
	if AppState.is_mobile_platform():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		_register_calibration_tap()
		get_viewport().set_input_as_handled()


func _apply_mobile_scroll_buttons() -> void:
	if not AppState.is_mobile_platform():
		return
	for button in [_start_button, _reset_button, %BottomResetButton]:
		button.set_script(MobileScrollButtonScript)


func is_menu_navigation_blocked() -> bool:
	return _state == CalibrationState.RUNNING
