extends Control

const HDTheme = preload("res://scripts/ui/HDTheme.gd")
const MobileScrollButtonScript = preload("res://scripts/ui/MobileScrollButton.gd")
const MenuNavigator = preload("res://scripts/ui/MenuNavigator.gd")
const InputBindingGlyph = preload("res://scripts/ui/InputBindingGlyph.gd")
const DisplaySettingsApplier = preload("res://scripts/ui/DisplaySettingsApplier.gd")

signal back_requested

const KEYBOARD_LAYOUT_LANE_COUNTS := [4, 5, 6, 7, 8]
const CONTROLLER_LANE_ACTIONS := ["lane_0", "lane_1", "lane_2", "lane_3", "lane_4", "lane_5", "lane_6", "lane_7"]
const CONTROLLER_MENU_ACTIONS := ["ui_up", "ui_down", "ui_left", "ui_right", "ui_accept", "ui_cancel"]
const CONTROLLER_CAPTURE_AXIS_THRESHOLD := 0.6
const SETTINGS_SECTION_GAMEPLAY := "gameplay"
const SETTINGS_SECTION_AUDIO := "audio"
const SETTINGS_SECTION_EFFECTS := "effects"
const SETTINGS_SECTION_GRAPHICS := "graphics"
const SETTINGS_SECTION_INPUT := "input"
const FPS_LIMIT_VALUES := [30, 60, 120, 144, 240, 0]
const RESOLUTION_VALUES := ["1280x720", "1600x900", "1920x1080", "2560x1440", "3840x2160"]

var _capture_action := ""
var _capture_controller_binding := false
var _menu_navigator: MenuNavigator
var _pending_gutter_image_target := "" # "both" | "left" | "right"
var _save_status_tween: Tween
var _settings_section := SETTINGS_SECTION_GAMEPLAY
var _settings_tab_buttons: Dictionary = {}
var _settings_section_controls: Dictionary = {}
var _keyboard_layout_lane_count := 5


func _ready() -> void:
	_apply_mobile_scroll_buttons()
	_menu_navigator = MenuNavigator.install(self, Callable(self, "_on_back_button_pressed"))
	_apply_layout()
	HDTheme.apply_dialog_tree(self)
	get_viewport().size_changed.connect(_apply_layout)
	%LatencySlider.value = ProfileStore.get_latency_offset_ms()
	%LatencyValueLabel.text = "%d ms" % int(ProfileStore.get_latency_offset_ms())
	_setup_note_speed_type_dropdown()
	%ScrollSpeedSlider.value = ProfileStore.get_note_approach_time_ms()
	%ScrollSpeedValueLabel.text = "%d ms" % int(ProfileStore.get_note_approach_time_ms())
	%LaneWidthSlider.value = ProfileStore.get_lane_width_scale()
	%LaneWidthValueLabel.text = "%d%%" % int(round(ProfileStore.get_lane_width_scale() * 100.0))
	%MissDuckingCheckBox.button_pressed = ProfileStore.is_miss_audio_ducking_enabled()
	%MenuMusicVolumeSlider.value = ProfileStore.get_menu_music_volume()
	_update_menu_music_volume_label(float(%MenuMusicVolumeSlider.value))
	if not %MenuMusicVolumeSlider.value_changed.is_connected(_on_menu_music_volume_changed):
		%MenuMusicVolumeSlider.value_changed.connect(_on_menu_music_volume_changed)
	%GameplayMusicVolumeSlider.value = ProfileStore.get_gameplay_music_volume()
	_update_gameplay_music_volume_label(float(%GameplayMusicVolumeSlider.value))
	if not %GameplayMusicVolumeSlider.value_changed.is_connected(_on_gameplay_music_volume_changed):
		%GameplayMusicVolumeSlider.value_changed.connect(_on_gameplay_music_volume_changed)
	%ThemeEffectsCheckBox.button_pressed = ProfileStore.are_theme_effects_enabled()
	%ChartBackgroundCheckBox.button_pressed = ProfileStore.is_chart_background_disabled()
	_setup_ems_color_controls()
	_setup_ems_background_controls()
	_setup_ems_gutter_image_controls()
	_setup_ems_hit_effect_dropdown()
	%ShadersCheckBox.button_pressed = ProfileStore.are_shaders_enabled()
	%PrioritizeFPSCheckBox.button_pressed = ProfileStore.is_prioritize_fps_enabled()
	%LaneBrightnessSlider.value = ProfileStore.get_lane_brightness()
	_update_lane_brightness_label(float(%LaneBrightnessSlider.value))
	%NoteOpacitySlider.value = ProfileStore.get_note_opacity()
	_update_note_opacity_label(float(%NoteOpacitySlider.value))
	%NotesAboveJudgementButtonsCheckBox.button_pressed = ProfileStore.are_notes_above_judgement_buttons()
	%JudgementPopupsCheckBox.button_pressed = ProfileStore.are_judgement_popups_enabled()
	%VisualEffectBloomCheckBox.button_pressed = ProfileStore.is_visual_effect_bloom_enabled()
	%VisualEffectDistortionCheckBox.button_pressed = ProfileStore.is_visual_effect_distortion_enabled()
	%VisualEffectParticlesCheckBox.button_pressed = ProfileStore.is_visual_effect_particles_enabled()
	%VisualEffectBackgroundAnimationsCheckBox.button_pressed = ProfileStore.is_visual_effect_background_animations_enabled()
	%ReduceDriveMeterCriticalFXCheckBox.button_pressed = ProfileStore.is_drive_meter_critical_fx_reduced()
	_setup_drive_meter_theme_dropdown()
	_setup_display_dropdowns()
	_setup_window_mode_dropdown()
	_setup_hit_effects_dropdown()
	_setup_judgement_display_dropdown()
	_setup_in_game_ui_dropdown()
	_connect_graphics_controls()
	_setup_keyboard_layout_dropdown()
	_rebuild_binding_rows()
	_setup_settings_submenus()
	set_process_unhandled_input(true)




func _apply_layout() -> void:
	var size := get_viewport_rect().size
	var metrics := HDTheme.overlay_metrics(size)
	%Background.color = HDTheme.BG.lightened(0.05)
	var panel_style: StyleBoxFlat = HDTheme.overlay_panel_style()
	panel_style.bg_color = panel_style.bg_color.lightened(0.05)
	panel_style.border_color = panel_style.border_color.lightened(0.05)
	%Panel.add_theme_stylebox_override("panel", panel_style)
	%Panel.custom_minimum_size = Vector2(metrics["panel_width"], metrics["panel_height"])
	HDTheme.apply_label(%BackLabel, "caption", HDTheme.SECONDARY)
	%BackLabel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	HDTheme.apply_back_button($BackButton, %BackLabel)
	$BackButton.offset_left = 40.0
	$BackButton.offset_top = 34.0
	$BackButton.offset_right = 192.0
	$BackButton.offset_bottom = 78.0
	HDTheme.apply_label(%TitleLabel, "screen_title", HDTheme.CYAN, true)
	%SettingsSubMenuGrid.columns = 2 if float(metrics["panel_width"]) < 640.0 else 3
	HDTheme.apply_label(%LatencyCaption, "body", HDTheme.SECONDARY)
	HDTheme.apply_label(%LatencyValueLabel, "caption", HDTheme.TERTIARY)
	HDTheme.apply_label(%NoteSpeedTypeLabel, "body", HDTheme.SECONDARY)
	HDTheme.apply_label(%ScrollSpeedLabel, "body", HDTheme.SECONDARY)
	HDTheme.apply_label(%ScrollSpeedValueLabel, "caption", HDTheme.TERTIARY)
	HDTheme.apply_label(%LaneWidthLabel, "body", HDTheme.SECONDARY)
	HDTheme.apply_label(%LaneWidthValueLabel, "caption", HDTheme.TERTIARY)
	HDTheme.apply_label(%MissDuckingLabel, "body", HDTheme.SECONDARY)
	HDTheme.apply_label(%MenuMusicVolumeLabel, "body", HDTheme.SECONDARY)
	HDTheme.apply_label(%MenuMusicVolumeValueLabel, "caption", HDTheme.TERTIARY)
	HDTheme.apply_label(%GameplayMusicVolumeLabel, "body", HDTheme.SECONDARY)
	HDTheme.apply_label(%GameplayMusicVolumeValueLabel, "caption", HDTheme.TERTIARY)
	HDTheme.apply_label(%ThemeEffectsLabel, "body", HDTheme.SECONDARY)
	HDTheme.apply_label(%EMSColorsLabel, "body", HDTheme.SECONDARY)
	HDTheme.apply_label(%EMSBackgroundLabel, "body", HDTheme.SECONDARY)
	HDTheme.apply_label(%EMSBackgroundBrightnessLabel, "body", HDTheme.SECONDARY)
	HDTheme.apply_label(%EMSBackgroundBrightnessValueLabel, "caption", HDTheme.TERTIARY)
	HDTheme.apply_label(%EMSGutterImageLabel, "body", HDTheme.SECONDARY)
	HDTheme.apply_label(%EMSGutterImageAlphaLabel, "body", HDTheme.SECONDARY)
	HDTheme.apply_label(%EMSGutterImageAlphaValueLabel, "caption", HDTheme.TERTIARY)
	HDTheme.apply_label(%EMSTrippyLevelLabel, "body", HDTheme.SECONDARY)
	HDTheme.apply_label(%EMSHitEffectLabel, "body", HDTheme.SECONDARY)
	HDTheme.apply_label(%ShadersLabel, "body", HDTheme.SECONDARY)
	HDTheme.apply_label(%VisualEffectsLabel, "section_title")
	HDTheme.apply_label(%FPSLimitLabel, "body", HDTheme.SECONDARY)
	HDTheme.apply_label(%VSyncLabel, "body", HDTheme.SECONDARY)
	HDTheme.apply_label(%PrioritizeFPSLabel, "body", HDTheme.SECONDARY)
	HDTheme.apply_label(%ResolutionLabel, "body", HDTheme.SECONDARY)
	HDTheme.apply_label(%LaneBrightnessLabel, "body", HDTheme.SECONDARY)
	HDTheme.apply_label(%LaneBrightnessValueLabel, "caption", HDTheme.TERTIARY)
	HDTheme.apply_label(%NoteOpacityLabel, "body", HDTheme.SECONDARY)
	HDTheme.apply_label(%NoteOpacityValueLabel, "caption", HDTheme.TERTIARY)
	HDTheme.apply_label(%NotesLayeringLabel, "body", HDTheme.SECONDARY)
	HDTheme.apply_label(%HitEffectsLabel, "body", HDTheme.SECONDARY)
	HDTheme.apply_label(%JudgementDisplayLabel, "body", HDTheme.SECONDARY)
	HDTheme.apply_label(%InGameUILabel, "body", HDTheme.SECONDARY)
	HDTheme.apply_label(%JudgementPopupsLabel, "body", HDTheme.SECONDARY)
	HDTheme.apply_label(%DriveMeterThemeLabel, "body", HDTheme.SECONDARY)
	HDTheme.apply_label(%DriveMeterAccessibilityLabel, "body", HDTheme.SECONDARY)
	HDTheme.apply_label(%WindowModeLabel, "body", HDTheme.SECONDARY)
	HDTheme.apply_label(%BindingsTitleLabel, "section_title")
	HDTheme.apply_label(%KeyboardLayoutLabel, "body", HDTheme.SECONDARY)
	HDTheme.apply_label(%ControllerBindingsTitleLabel, "section_title")
	HDTheme.apply_label(%ControllerMenuBindingsTitleLabel, "section_title")
	HDTheme.apply_label(%CaptureLabel, "body", HDTheme.SECONDARY)
	_apply_black_field_backgrounds()
	_apply_black_slider_styles()
	for checkbox in [%MissDuckingCheckBox, %ThemeEffectsCheckBox, %ChartBackgroundCheckBox, %PrioritizeFPSCheckBox, %NotesAboveJudgementButtonsCheckBox, %JudgementPopupsCheckBox, %VisualEffectBloomCheckBox, %VisualEffectDistortionCheckBox, %VisualEffectParticlesCheckBox, %VisualEffectBackgroundAnimationsCheckBox, %ReduceDriveMeterCriticalFXCheckBox]:
		checkbox.add_theme_font_size_override("font_size", HDTheme.text_size("button_secondary", size))
	%ShadersCheckBox.add_theme_font_size_override("font_size", HDTheme.text_size("button_secondary", size))
	for button in [%EMSPrimaryColorPicker, %EMSSecondaryColorPicker, %EMSAccentColorPicker]:
		button.custom_minimum_size.y = 44
		button.add_theme_font_size_override("font_size", HDTheme.text_size("button_secondary", size))
	%EMSColorModeOptionButton.custom_minimum_size.y = 44
	%EMSColorModeOptionButton.add_theme_font_size_override("font_size", HDTheme.text_size("button_secondary", size))
	%EMSBackgroundModeOptionButton.custom_minimum_size.y = 44
	%EMSBackgroundModeOptionButton.add_theme_font_size_override("font_size", HDTheme.text_size("button_secondary", size))
	%EMSBackgroundColorPicker.custom_minimum_size.y = 44
	%EMSBackgroundColorPicker.add_theme_font_size_override("font_size", HDTheme.text_size("button_secondary", size))
	%EMSBackgroundBrightnessSlider.custom_minimum_size.y = 44
	%EMSTrippyLevelOptionButton.custom_minimum_size.y = 44
	%EMSTrippyLevelOptionButton.add_theme_font_size_override("font_size", HDTheme.text_size("button_secondary", size))
	%EMSHitEffectOptionButton.custom_minimum_size.y = 44
	%EMSHitEffectOptionButton.add_theme_font_size_override("font_size", HDTheme.text_size("button_secondary", size))
	%EMSGutterImageModeOptionButton.custom_minimum_size.y = 44
	%EMSGutterImageModeOptionButton.add_theme_font_size_override("font_size", HDTheme.text_size("button_secondary", size))
	for button in [%EMSGutterImageBothButton, %EMSGutterImageLeftButton, %EMSGutterImageRightButton]:
		button.custom_minimum_size.y = 44
		button.add_theme_font_size_override("font_size", HDTheme.text_size("button_secondary", size))
	%EMSGutterImageAlphaSlider.custom_minimum_size.y = 44
	%DriveMeterThemeOptionButton.custom_minimum_size.y = 44
	%DriveMeterThemeOptionButton.add_theme_font_size_override("font_size", HDTheme.text_size("button_secondary", size))
	for option_button in [%NoteSpeedTypeOptionButton, %FPSLimitOptionButton, %VSyncOptionButton, %HitEffectsOptionButton, %JudgementDisplayOptionButton, %InGameUIOptionButton, %ResolutionOptionButton]:
		option_button.custom_minimum_size.y = 44
		option_button.add_theme_font_size_override("font_size", HDTheme.text_size("button_secondary", size))
	%KeyboardLayoutOptionButton.custom_minimum_size.y = 44
	%KeyboardLayoutOptionButton.add_theme_font_size_override("font_size", HDTheme.text_size("button_secondary", size))
	%WindowModeOptionButton.custom_minimum_size.y = 44
	%WindowModeOptionButton.add_theme_font_size_override("font_size", HDTheme.text_size("button_secondary", size))
	%SaveButton.add_theme_stylebox_override("normal", HDTheme.button_style(true))
	%SaveButton.add_theme_stylebox_override("hover", HDTheme.button_style(true))
	%SaveButton.add_theme_stylebox_override("pressed", HDTheme.button_style(true))
	%ResetRecommendedDefaultsButton.add_theme_stylebox_override("normal", HDTheme.button_style(false))
	%ResetRecommendedDefaultsButton.add_theme_stylebox_override("hover", HDTheme.button_style(false))
	%ResetRecommendedDefaultsButton.add_theme_stylebox_override("pressed", HDTheme.button_style(false))
	%BackActionButton.add_theme_stylebox_override("normal", HDTheme.button_style(false))
	%BackActionButton.add_theme_stylebox_override("hover", HDTheme.button_style(false))
	%BackActionButton.add_theme_stylebox_override("pressed", HDTheme.button_style(false))
	var footer_button_width := clampf(metrics["panel_width"] * 0.28, 140.0, 230.0)
	for button in [%SaveButton, %ResetRecommendedDefaultsButton, %BackActionButton]:
		button.custom_minimum_size.y = metrics["button_height"]
		button.custom_minimum_size.x = footer_button_width
		button.add_theme_font_size_override("font_size", HDTheme.text_size("button_secondary", size))
	%LatencySlider.custom_minimum_size.y = 44
	%ScrollSpeedSlider.custom_minimum_size.y = 44
	%LaneWidthSlider.custom_minimum_size.y = 44
	%MenuMusicVolumeSlider.custom_minimum_size.y = 44
	%GameplayMusicVolumeSlider.custom_minimum_size.y = 44
	%LaneBrightnessSlider.custom_minimum_size.y = 44
	%NoteOpacitySlider.custom_minimum_size.y = 44
	var show_bindings: bool = not AppState.is_mobile_platform()
	var show_window_mode: bool = OS.has_feature("windows") or OS.has_feature("macos") or OS.has_feature("linuxbsd")
	%WindowModeLabel.visible = show_window_mode
	%WindowModeOptionButton.visible = show_window_mode
	%BindingsTitleLabel.visible = show_bindings
	%KeyboardLayoutLabel.visible = show_bindings
	%KeyboardLayoutOptionButton.visible = show_bindings
	%BindingsVBox.visible = show_bindings
	%ControllerBindingsTitleLabel.visible = show_bindings
	%ControllerBindingsVBox.visible = show_bindings
	%ControllerMenuBindingsTitleLabel.visible = show_bindings
	%ControllerMenuBindingsVBox.visible = show_bindings
	# CaptureLabel is used both for input-capture prompts and for short-lived save messages.
	if not show_bindings:
		%CaptureLabel.visible = false
	elif not _capture_action.is_empty():
		%CaptureLabel.visible = true
	else:
		%CaptureLabel.visible = not str(%CaptureLabel.text).is_empty()
	_refresh_settings_submenu_styles()
	_apply_settings_section_visibility()


func _setup_settings_submenus() -> void:
	_settings_tab_buttons = {
		SETTINGS_SECTION_GAMEPLAY: %GameplayTabButton,
		SETTINGS_SECTION_AUDIO: %AudioTabButton,
		SETTINGS_SECTION_EFFECTS: %EffectsTabButton,
		SETTINGS_SECTION_GRAPHICS: %GraphicsTabButton,
		SETTINGS_SECTION_INPUT: %InputTabButton,
	}
	_settings_section_controls = {
		SETTINGS_SECTION_GAMEPLAY: [
			%LatencyRow,
			%LatencySlider,
			%NoteSpeedTypeLabel,
			%NoteSpeedTypeOptionButton,
			%ScrollSpeedRow,
			%ScrollSpeedSlider,
			%LaneWidthRow,
			%LaneWidthSlider,
			%MissDuckingLabel,
			%MissDuckingCheckBox,
			%DriveMeterThemeLabel,
			%DriveMeterThemeOptionButton,
			%DriveMeterAccessibilityLabel,
			%ReduceDriveMeterCriticalFXCheckBox,
		],
		SETTINGS_SECTION_AUDIO: [
			%MenuMusicVolumeRow,
			%MenuMusicVolumeSlider,
			%GameplayMusicVolumeRow,
			%GameplayMusicVolumeSlider,
		],
		SETTINGS_SECTION_EFFECTS: [
			%ThemeEffectsLabel,
			%ThemeEffectsCheckBox,
			%ChartBackgroundCheckBox,
			%EMSColorsLabel,
			%EMSColorModeOptionButton,
			%EMSColorPickersRow,
			%EMSBackgroundLabel,
			%EMSBackgroundModeOptionButton,
			%EMSBackgroundColorRow,
			%EMSBackgroundBrightnessRow,
			%EMSBackgroundBrightnessSlider,
			%EMSGutterImageLabel,
			%EMSGutterImageModeOptionButton,
			%EMSGutterImageBothRow,
			%EMSGutterImageSeparateRow,
			%EMSGutterImageAlphaRow,
			%EMSGutterImageAlphaSlider,
			%EMSTrippyLevelLabel,
			%EMSTrippyLevelOptionButton,
			%EMSHitEffectLabel,
			%EMSHitEffectOptionButton,
		],
		SETTINGS_SECTION_GRAPHICS: [
			%FPSLimitLabel,
			%FPSLimitOptionButton,
			%VSyncLabel,
			%VSyncOptionButton,
			%PrioritizeFPSLabel,
			%PrioritizeFPSCheckBox,
			%WindowModeLabel,
			%WindowModeOptionButton,
			%ResolutionLabel,
			%ResolutionOptionButton,
			%LaneBrightnessRow,
			%LaneBrightnessSlider,
			%NoteOpacityRow,
			%NoteOpacitySlider,
			%NotesLayeringLabel,
			%NotesAboveJudgementButtonsCheckBox,
			%HitEffectsLabel,
			%HitEffectsOptionButton,
			%JudgementDisplayLabel,
			%JudgementDisplayOptionButton,
			%InGameUILabel,
			%InGameUIOptionButton,
			%JudgementPopupsLabel,
			%JudgementPopupsCheckBox,
			%ShadersLabel,
			%ShadersCheckBox,
			%VisualEffectsLabel,
			%VisualEffectBloomCheckBox,
			%VisualEffectDistortionCheckBox,
			%VisualEffectParticlesCheckBox,
			%VisualEffectBackgroundAnimationsCheckBox,
		],
		SETTINGS_SECTION_INPUT: [
			%BindingsTitleLabel,
			%KeyboardLayoutLabel,
			%KeyboardLayoutOptionButton,
			%BindingsVBox,
			%ControllerBindingsTitleLabel,
			%ControllerBindingsVBox,
			%ControllerMenuBindingsTitleLabel,
			%ControllerMenuBindingsVBox,
		],
	}
	for section in _settings_tab_buttons.keys():
		var button := _settings_tab_buttons[section] as Button
		var callback := Callable(self, "_set_settings_section").bind(str(section))
		if button != null and not button.pressed.is_connected(callback):
			button.pressed.connect(callback)
	_set_settings_section(SETTINGS_SECTION_GAMEPLAY)


func _set_settings_section(section: String) -> void:
	if not _settings_tab_buttons.has(section):
		section = SETTINGS_SECTION_GAMEPLAY
	_settings_section = section
	_refresh_settings_submenu_styles()
	_apply_settings_section_visibility()
	if is_instance_valid(%ContentScroll):
		%ContentScroll.scroll_vertical = 0
	call_deferred("_refresh_menu_navigation")


func _refresh_settings_submenu_styles() -> void:
	if _settings_tab_buttons.is_empty():
		return
	var size := get_viewport_rect().size
	for section in _settings_tab_buttons.keys():
		var button := _settings_tab_buttons[section] as Button
		if button == null:
			continue
		var active := str(section) == _settings_section
		button.set_pressed_no_signal(active)
		button.custom_minimum_size = Vector2(148, 42)
		button.add_theme_font_size_override("font_size", HDTheme.text_size("button_secondary", size))
		button.add_theme_stylebox_override("normal", HDTheme.button_style(active))
		button.add_theme_stylebox_override("hover", HDTheme.button_style(active))
		button.add_theme_stylebox_override("pressed", HDTheme.button_style(true))
		button.add_theme_stylebox_override("focus", HDTheme.button_style(active))


func _apply_settings_section_visibility() -> void:
	if _settings_section_controls.is_empty():
		return
	for controls_variant in _settings_section_controls.values():
		for control_variant in controls_variant:
			var control := control_variant as Control
			if control != null:
				control.visible = false
	for control in (_settings_section_controls.get(_settings_section, []) as Array):
		if control != null:
			(control as Control).visible = true

	var show_window_mode: bool = OS.has_feature("windows") or OS.has_feature("macos") or OS.has_feature("linuxbsd")
	var graphics_active := _settings_section == SETTINGS_SECTION_GRAPHICS
	%WindowModeLabel.visible = graphics_active and show_window_mode
	%WindowModeOptionButton.visible = graphics_active and show_window_mode
	%ResolutionLabel.visible = graphics_active and show_window_mode
	%ResolutionOptionButton.visible = graphics_active and show_window_mode

	var modern_note_speed := _selected_note_speed_type() == "modern"
	%ScrollSpeedRow.visible = _settings_section == SETTINGS_SECTION_GAMEPLAY and modern_note_speed
	%ScrollSpeedSlider.visible = _settings_section == SETTINGS_SECTION_GAMEPLAY and modern_note_speed

	var show_bindings: bool = _settings_section == SETTINGS_SECTION_INPUT and not AppState.is_mobile_platform()
	%BindingsTitleLabel.visible = show_bindings
	%KeyboardLayoutLabel.visible = show_bindings
	%KeyboardLayoutOptionButton.visible = show_bindings
	%BindingsVBox.visible = show_bindings
	%ControllerBindingsTitleLabel.visible = show_bindings
	%ControllerBindingsVBox.visible = show_bindings
	%ControllerMenuBindingsTitleLabel.visible = show_bindings
	%ControllerMenuBindingsVBox.visible = show_bindings

	_update_ems_color_picker_visibility()
	_update_ems_background_picker_visibility()
	_update_gutter_image_visibility()
	_update_visual_effects_visibility()


func _sync_options_controls_from_profile() -> void:
	%LatencySlider.value = ProfileStore.get_latency_offset_ms()
	%LatencyValueLabel.text = "%d ms" % int(ProfileStore.get_latency_offset_ms())
	_select_note_speed_type(ProfileStore.get_note_speed_type())
	%ScrollSpeedSlider.value = ProfileStore.get_note_approach_time_ms()
	%ScrollSpeedValueLabel.text = "%d ms" % int(ProfileStore.get_note_approach_time_ms())
	%LaneWidthSlider.value = ProfileStore.get_lane_width_scale()
	%LaneWidthValueLabel.text = "%d%%" % int(round(ProfileStore.get_lane_width_scale() * 100.0))
	%MissDuckingCheckBox.button_pressed = ProfileStore.is_miss_audio_ducking_enabled()
	%MenuMusicVolumeSlider.value = ProfileStore.get_menu_music_volume()
	_update_menu_music_volume_label(float(%MenuMusicVolumeSlider.value))
	%GameplayMusicVolumeSlider.value = ProfileStore.get_gameplay_music_volume()
	_update_gameplay_music_volume_label(float(%GameplayMusicVolumeSlider.value))
	%ThemeEffectsCheckBox.button_pressed = ProfileStore.are_theme_effects_enabled()
	%ChartBackgroundCheckBox.button_pressed = ProfileStore.is_chart_background_disabled()
	%EMSColorModeOptionButton.select(1 if ProfileStore.get_ems_color_mode() == "custom" else 0)
	%EMSPrimaryColorPicker.color = ProfileStore.get_ems_custom_primary()
	%EMSSecondaryColorPicker.color = ProfileStore.get_ems_custom_secondary()
	%EMSAccentColorPicker.color = ProfileStore.get_ems_custom_accent()
	match ProfileStore.get_ems_trippy_level():
		"subtle":
			%EMSTrippyLevelOptionButton.select(0)
		"medium":
			%EMSTrippyLevelOptionButton.select(1)
		_:
			%EMSTrippyLevelOptionButton.select(2)
	match ProfileStore.get_ems_background_mode():
		"random":
			%EMSBackgroundModeOptionButton.select(1)
		"psychedelic":
			%EMSBackgroundModeOptionButton.select(2)
		_:
			%EMSBackgroundModeOptionButton.select(0)
	%EMSBackgroundColorPicker.color = ProfileStore.get_ems_background_solid_color()
	%EMSBackgroundBrightnessSlider.value = ProfileStore.get_ems_background_brightness()
	_update_ems_background_brightness_label(float(%EMSBackgroundBrightnessSlider.value))
	match ProfileStore.get_ems_gutter_image_mode():
		"both":
			%EMSGutterImageModeOptionButton.select(1)
		"separate":
			%EMSGutterImageModeOptionButton.select(2)
		_:
			%EMSGutterImageModeOptionButton.select(0)
	_set_gutter_button_path(%EMSGutterImageBothButton, ProfileStore.get_ems_gutter_image_path_both(), "Choose Image (Both Gutters)")
	_set_gutter_button_path(%EMSGutterImageLeftButton, ProfileStore.get_ems_gutter_image_path_left(), "Choose Left Image")
	_set_gutter_button_path(%EMSGutterImageRightButton, ProfileStore.get_ems_gutter_image_path_right(), "Choose Right Image")
	%EMSGutterImageAlphaSlider.value = ProfileStore.get_ems_gutter_image_alpha()
	_update_gutter_alpha_label(float(%EMSGutterImageAlphaSlider.value))
	_select_option_id(%EMSHitEffectOptionButton, 1 if ProfileStore.get_ems_hit_effect() == "pressure" else 0)
	%ShadersCheckBox.button_pressed = ProfileStore.are_shaders_enabled()
	%PrioritizeFPSCheckBox.button_pressed = ProfileStore.is_prioritize_fps_enabled()
	_select_option_id(%FPSLimitOptionButton, ProfileStore.get_fps_limit())
	match ProfileStore.get_vsync_mode():
		"off":
			%VSyncOptionButton.select(0)
		"adaptive":
			%VSyncOptionButton.select(2)
		_:
			%VSyncOptionButton.select(1)
	match ProfileStore.get_window_mode():
		"borderless_fullscreen":
			%WindowModeOptionButton.select(1)
		"windowed":
			%WindowModeOptionButton.select(2)
		_:
			%WindowModeOptionButton.select(0)
	_select_option_text(%ResolutionOptionButton, ProfileStore.get_display_resolution())
	%LaneBrightnessSlider.value = ProfileStore.get_lane_brightness()
	_update_lane_brightness_label(float(%LaneBrightnessSlider.value))
	%NoteOpacitySlider.value = ProfileStore.get_note_opacity()
	_update_note_opacity_label(float(%NoteOpacitySlider.value))
	%NotesAboveJudgementButtonsCheckBox.button_pressed = ProfileStore.are_notes_above_judgement_buttons()
	match ProfileStore.get_hit_effects_mode():
		"off":
			%HitEffectsOptionButton.select(0)
		"minimal":
			%HitEffectsOptionButton.select(1)
		"enhanced":
			%HitEffectsOptionButton.select(3)
		_:
			%HitEffectsOptionButton.select(2)
	_select_option_id(%JudgementDisplayOptionButton, 1 if ProfileStore.get_judgement_display_mode() == "classic" else 0)
	_select_option_id(%InGameUIOptionButton, 1 if ProfileStore.get_in_game_ui_mode() == "modern" else 0)
	%JudgementPopupsCheckBox.button_pressed = ProfileStore.are_judgement_popups_enabled()
	%ReduceDriveMeterCriticalFXCheckBox.button_pressed = ProfileStore.is_drive_meter_critical_fx_reduced()
	match ProfileStore.get_drive_meter_theme():
		"classic":
			%DriveMeterThemeOptionButton.select(1)
		"mono":
			%DriveMeterThemeOptionButton.select(2)
		_:
			%DriveMeterThemeOptionButton.select(0)
	_update_resolution_control_state()
	_apply_settings_section_visibility()
	_rebuild_binding_rows()
	call_deferred("_refresh_menu_navigation")


func _select_option_id(button: OptionButton, item_id: int) -> void:
	for index in range(button.get_item_count()):
		if button.get_item_id(index) == item_id:
			button.select(index)
			return


func _select_option_text(button: OptionButton, text: String) -> void:
	var normalized := text.strip_edges().to_lower()
	for index in range(button.get_item_count()):
		if button.get_item_text(index).strip_edges().to_lower() == normalized:
			button.select(index)
			return


func _apply_black_field_backgrounds() -> void:
	var base := StyleBoxFlat.new()
	base.bg_color = Color(0, 0, 0, 1.0)
	base.border_color = Color(1, 1, 1, 0.22)
	base.border_width_left = 2
	base.border_width_top = 2
	base.border_width_right = 2
	base.border_width_bottom = 2
	base.corner_radius_top_left = 12
	base.corner_radius_top_right = 12
	base.corner_radius_bottom_left = 12
	base.corner_radius_bottom_right = 12

	var hover: StyleBoxFlat = base.duplicate()
	hover.border_color = Color(1, 1, 1, 0.32)

	var pressed: StyleBoxFlat = base.duplicate()
	pressed.border_color = Color(0.15, 0.82, 1.0, 0.42)

	var focus: StyleBoxFlat = base.duplicate()
	focus.border_color = Color(0.15, 0.82, 1.0, 0.34)
	focus.shadow_color = Color(0, 0, 0, 0)
	focus.shadow_size = 0
	focus.shadow_offset = Vector2.ZERO

	var themed_buttons: Array[BaseButton] = [
		%MissDuckingCheckBox,
		%ThemeEffectsCheckBox,
		%ChartBackgroundCheckBox,
		%ShadersCheckBox,
		%PrioritizeFPSCheckBox,
		%NotesAboveJudgementButtonsCheckBox,
		%JudgementPopupsCheckBox,
		%VisualEffectBloomCheckBox,
		%VisualEffectDistortionCheckBox,
		%VisualEffectParticlesCheckBox,
		%VisualEffectBackgroundAnimationsCheckBox,
		%ReduceDriveMeterCriticalFXCheckBox,
		%EMSColorModeOptionButton,
		%EMSBackgroundModeOptionButton,
		%EMSTrippyLevelOptionButton,
		%EMSHitEffectOptionButton,
		%EMSGutterImageModeOptionButton,
		%EMSGutterImageBothButton,
		%EMSGutterImageLeftButton,
		%EMSGutterImageRightButton,
		%DriveMeterThemeOptionButton,
		%NoteSpeedTypeOptionButton,
		%FPSLimitOptionButton,
		%VSyncOptionButton,
		%HitEffectsOptionButton,
		%JudgementDisplayOptionButton,
		%InGameUIOptionButton,
		%ResolutionOptionButton,
		%WindowModeOptionButton,
	]

	for b: BaseButton in themed_buttons:
		if b == null:
			continue
		b.add_theme_stylebox_override("normal", base)
		b.add_theme_stylebox_override("hover", hover)
		b.add_theme_stylebox_override("pressed", pressed)
		b.add_theme_stylebox_override("focus", focus)


func _apply_black_slider_styles() -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0, 0, 0, 1.0)
	track.border_color = Color(1, 1, 1, 0.14)
	track.border_width_left = 2
	track.border_width_top = 2
	track.border_width_right = 2
	track.border_width_bottom = 2
	track.corner_radius_top_left = 10
	track.corner_radius_top_right = 10
	track.corner_radius_bottom_left = 10
	track.corner_radius_bottom_right = 10

	var grabber := StyleBoxFlat.new()
	grabber.bg_color = Color(1, 1, 1, 0.92)
	grabber.border_color = Color(0, 0, 0, 0.35)
	grabber.border_width_left = 2
	grabber.border_width_top = 2
	grabber.border_width_right = 2
	grabber.border_width_bottom = 2
	grabber.corner_radius_top_left = 10
	grabber.corner_radius_top_right = 10
	grabber.corner_radius_bottom_left = 10
	grabber.corner_radius_bottom_right = 10

	var grabber_highlight: StyleBoxFlat = grabber.duplicate()
	grabber_highlight.border_color = Color(0.15, 0.82, 1.0, 0.55)

	var sliders: Array[HSlider] = [
		%LatencySlider,
		%ScrollSpeedSlider,
		%LaneWidthSlider,
		%MenuMusicVolumeSlider,
		%GameplayMusicVolumeSlider,
		%EMSBackgroundBrightnessSlider,
		%EMSGutterImageAlphaSlider,
		%LaneBrightnessSlider,
		%NoteOpacitySlider,
	]

	for s: HSlider in sliders:
		if s == null:
			continue
		s.add_theme_stylebox_override("slider", track)
		s.add_theme_stylebox_override("grabber_area", track)
		s.add_theme_stylebox_override("grabber", grabber)
		s.add_theme_stylebox_override("grabber_highlight", grabber_highlight)


func _apply_mobile_scroll_buttons() -> void:
	if not AppState.is_mobile_platform():
		return
	for button in [%BackButton, %SaveButton, %BackActionButton, %MissDuckingCheckBox, %MenuMusicVolumeSlider, %GameplayMusicVolumeSlider, %ThemeEffectsCheckBox, %EMSColorModeOptionButton, %EMSPrimaryColorPicker, %EMSSecondaryColorPicker, %EMSAccentColorPicker, %EMSBackgroundModeOptionButton, %EMSBackgroundColorPicker, %EMSBackgroundBrightnessSlider, %EMSGutterImageModeOptionButton, %EMSGutterImageBothButton, %EMSGutterImageLeftButton, %EMSGutterImageRightButton, %EMSGutterImageAlphaSlider, %EMSTrippyLevelOptionButton, %EMSHitEffectOptionButton, %ShadersCheckBox, %VisualEffectBloomCheckBox, %VisualEffectDistortionCheckBox, %VisualEffectParticlesCheckBox, %VisualEffectBackgroundAnimationsCheckBox, %FPSLimitOptionButton, %VSyncOptionButton, %HitEffectsOptionButton, %JudgementDisplayOptionButton, %InGameUIOptionButton, %ResolutionOptionButton, %LaneBrightnessSlider, %NoteOpacitySlider, %PrioritizeFPSCheckBox, %NotesAboveJudgementButtonsCheckBox, %JudgementPopupsCheckBox, %ReduceDriveMeterCriticalFXCheckBox, %KeyboardLayoutOptionButton]:
		button.set_script(MobileScrollButtonScript)


func _rebuild_binding_rows() -> void:
	for child in %BindingsVBox.get_children():
		child.queue_free()
	for child in %ControllerBindingsVBox.get_children():
		child.queue_free()
	for child in %ControllerMenuBindingsVBox.get_children():
		child.queue_free()
	if AppState.is_mobile_platform():
		return
	var size := get_viewport_rect().size
	var metrics := HDTheme.overlay_metrics(size)
	var key_bindings: Dictionary = ProfileStore.get_key_bindings(_keyboard_layout_lane_count)
	var controller_bindings: Dictionary = ProfileStore.get_controller_bindings()
	for lane in range(_keyboard_layout_lane_count):
		var action := "lane_%d" % lane
		%BindingsVBox.add_child(_make_binding_row(
			action,
			InputBindingGlyph.keyboard_display(int(key_bindings[action])),
			Callable(self, "_begin_key_capture").bind(action),
			size,
			metrics
		))
	for action in CONTROLLER_LANE_ACTIONS:
		%ControllerBindingsVBox.add_child(_make_binding_row(
			action,
			InputBindingGlyph.controller_display(controller_bindings.get(action, {})),
			Callable(self, "_begin_controller_capture").bind(action),
			size,
			metrics
		))
	for action in CONTROLLER_MENU_ACTIONS:
		%ControllerMenuBindingsVBox.add_child(_make_binding_row(
			action,
			InputBindingGlyph.controller_display(controller_bindings.get(action, {})),
			Callable(self, "_begin_controller_capture").bind(action),
			size,
			metrics
		))
	call_deferred("_refresh_menu_navigation")


func _setup_keyboard_layout_dropdown() -> void:
	_keyboard_layout_lane_count = 5
	%KeyboardLayoutOptionButton.clear()
	for lane_count in KEYBOARD_LAYOUT_LANE_COUNTS:
		var count := int(lane_count)
		%KeyboardLayoutOptionButton.add_item("%dK (%d Keys)" % [count, count], count)
	for index in range(%KeyboardLayoutOptionButton.item_count):
		if int(%KeyboardLayoutOptionButton.get_item_id(index)) == _keyboard_layout_lane_count:
			%KeyboardLayoutOptionButton.select(index)
			break
	if not %KeyboardLayoutOptionButton.item_selected.is_connected(_on_keyboard_layout_selected):
		%KeyboardLayoutOptionButton.item_selected.connect(_on_keyboard_layout_selected)


func _on_keyboard_layout_selected(index: int) -> void:
	_keyboard_layout_lane_count = int(%KeyboardLayoutOptionButton.get_item_id(index))
	AppState.sync_input_actions(_keyboard_layout_lane_count)
	_rebuild_binding_rows()


func _setup_window_mode_dropdown() -> void:
	%WindowModeOptionButton.clear()
	%WindowModeOptionButton.add_item("Fullscreen")
	%WindowModeOptionButton.add_item("Borderless Fullscreen")
	%WindowModeOptionButton.add_item("Windowed")
	var selected_mode: String = ProfileStore.get_window_mode()
	match selected_mode:
		"borderless_fullscreen":
			%WindowModeOptionButton.select(1)
		"windowed":
			%WindowModeOptionButton.select(2)
		_:
			%WindowModeOptionButton.select(0)


func _setup_note_speed_type_dropdown() -> void:
	%NoteSpeedTypeOptionButton.clear()
	%NoteSpeedTypeOptionButton.add_item("Classic", 0)
	%NoteSpeedTypeOptionButton.add_item("Modern", 1)
	_select_note_speed_type(ProfileStore.get_note_speed_type())
	if not %NoteSpeedTypeOptionButton.item_selected.is_connected(_on_note_speed_type_selected):
		%NoteSpeedTypeOptionButton.item_selected.connect(_on_note_speed_type_selected)


func _select_note_speed_type(speed_type: String) -> void:
	%NoteSpeedTypeOptionButton.select(1 if speed_type == "modern" else 0)


func _selected_note_speed_type() -> String:
	return "modern" if %NoteSpeedTypeOptionButton.selected == 1 else "classic"


func _on_note_speed_type_selected(_index: int) -> void:
	_apply_settings_section_visibility()


func _setup_display_dropdowns() -> void:
	%FPSLimitOptionButton.clear()
	for fps in FPS_LIMIT_VALUES:
		%FPSLimitOptionButton.add_item("Unlimited" if int(fps) == 0 else "%d FPS" % int(fps), int(fps))
	var selected_fps := ProfileStore.get_fps_limit()
	for index in %FPSLimitOptionButton.item_count:
		if int(%FPSLimitOptionButton.get_item_id(index)) == selected_fps:
			%FPSLimitOptionButton.select(index)
			break

	%VSyncOptionButton.clear()
	%VSyncOptionButton.add_item("Off", 0)
	%VSyncOptionButton.add_item("On", 1)
	%VSyncOptionButton.add_item("Adaptive", 2)
	match ProfileStore.get_vsync_mode():
		"off":
			%VSyncOptionButton.select(0)
		"adaptive":
			%VSyncOptionButton.select(2)
		_:
			%VSyncOptionButton.select(1)

	%ResolutionOptionButton.clear()
	for resolution in RESOLUTION_VALUES:
		%ResolutionOptionButton.add_item(resolution)
	var selected_resolution := ProfileStore.get_display_resolution()
	var resolution_index := RESOLUTION_VALUES.find(selected_resolution)
	%ResolutionOptionButton.select(maxi(0, resolution_index))
	_update_resolution_control_state()


func _setup_hit_effects_dropdown() -> void:
	%HitEffectsOptionButton.clear()
	%HitEffectsOptionButton.add_item("Off", 0)
	%HitEffectsOptionButton.add_item("Minimal", 1)
	%HitEffectsOptionButton.add_item("Normal", 2)
	%HitEffectsOptionButton.add_item("Enhanced", 3)
	match ProfileStore.get_hit_effects_mode():
		"off":
			%HitEffectsOptionButton.select(0)
		"minimal":
			%HitEffectsOptionButton.select(1)
		"enhanced":
			%HitEffectsOptionButton.select(3)
		_:
			%HitEffectsOptionButton.select(2)


func _setup_judgement_display_dropdown() -> void:
	%JudgementDisplayOptionButton.clear()
	%JudgementDisplayOptionButton.add_item("Modern", 0)
	%JudgementDisplayOptionButton.add_item("Classic", 1)
	match ProfileStore.get_judgement_display_mode():
		"classic":
			%JudgementDisplayOptionButton.select(1)
		_:
			%JudgementDisplayOptionButton.select(0)


func _setup_in_game_ui_dropdown() -> void:
	%InGameUIOptionButton.clear()
	%InGameUIOptionButton.add_item("Classic in-game UI", 0)
	%InGameUIOptionButton.add_item("Modern in-game UI", 1)
	match ProfileStore.get_in_game_ui_mode():
		"modern":
			%InGameUIOptionButton.select(1)
		_:
			%InGameUIOptionButton.select(0)


func _setup_ems_hit_effect_dropdown() -> void:
	%EMSHitEffectOptionButton.clear()
	%EMSHitEffectOptionButton.add_item("Circular", 0)
	%EMSHitEffectOptionButton.add_item("Pressure", 1)
	match ProfileStore.get_ems_hit_effect():
		"pressure":
			%EMSHitEffectOptionButton.select(1)
		_:
			%EMSHitEffectOptionButton.select(0)


func _connect_graphics_controls() -> void:
	if not %FPSLimitOptionButton.item_selected.is_connected(_on_display_option_changed):
		%FPSLimitOptionButton.item_selected.connect(_on_display_option_changed)
	if not %VSyncOptionButton.item_selected.is_connected(_on_display_option_changed):
		%VSyncOptionButton.item_selected.connect(_on_display_option_changed)
	if not %ResolutionOptionButton.item_selected.is_connected(_on_display_option_changed):
		%ResolutionOptionButton.item_selected.connect(_on_display_option_changed)
	if not %WindowModeOptionButton.item_selected.is_connected(_on_window_mode_option_button_item_selected):
		%WindowModeOptionButton.item_selected.connect(_on_window_mode_option_button_item_selected)
	if not %ShadersCheckBox.toggled.is_connected(_on_shaders_check_box_toggled):
		%ShadersCheckBox.toggled.connect(_on_shaders_check_box_toggled)


func _setup_drive_meter_theme_dropdown() -> void:
	%DriveMeterThemeOptionButton.clear()
	%DriveMeterThemeOptionButton.add_item("Auto")
	%DriveMeterThemeOptionButton.add_item("Classic")
	%DriveMeterThemeOptionButton.add_item("Mono")
	match ProfileStore.get_drive_meter_theme():
		"classic":
			%DriveMeterThemeOptionButton.select(1)
		"mono":
			%DriveMeterThemeOptionButton.select(2)
		_:
			%DriveMeterThemeOptionButton.select(0)


func _begin_key_capture(action: String) -> void:
	_capture_action = action
	_capture_controller_binding = false
	%CaptureLabel.text = "Press a key for %dK %s" % [_keyboard_layout_lane_count, _binding_label(action)]
	%CaptureLabel.visible = true


func _begin_controller_capture(action: String) -> void:
	_capture_action = action
	_capture_controller_binding = true
	%CaptureLabel.text = "Press a controller button or move an axis for %s" % _binding_label(action)
	%CaptureLabel.visible = true


func _unhandled_input(event: InputEvent) -> void:
	if _capture_action.is_empty():
		return
	if _capture_controller_binding:
		if event is InputEventJoypadButton and event.pressed:
			ProfileStore.set_controller_binding(_capture_action, {
				"kind": "button",
				"button_index": event.button_index,
			})
			AppState.sync_input_actions()
			_finish_capture()
			get_viewport().set_input_as_handled()
			return
		if event is InputEventJoypadMotion and absf(event.axis_value) >= CONTROLLER_CAPTURE_AXIS_THRESHOLD:
			ProfileStore.set_controller_binding(_capture_action, {
				"kind": "axis",
				"axis": event.axis,
				"direction": -1 if event.axis_value < 0.0 else 1,
				"threshold": 0.5,
			})
			AppState.sync_input_actions()
			_finish_capture()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		ProfileStore.set_key_binding(_capture_action, event.physical_keycode, _keyboard_layout_lane_count)
		AppState.sync_input_actions(_keyboard_layout_lane_count)
		_finish_capture()
		get_viewport().set_input_as_handled()


func _on_latency_slider_value_changed(value: float) -> void:
	%LatencyValueLabel.text = "%d ms" % int(value)


func _on_scroll_speed_slider_value_changed(value: float) -> void:
	%ScrollSpeedValueLabel.text = "%d ms" % int(value)


func _on_lane_width_slider_value_changed(value: float) -> void:
	%LaneWidthValueLabel.text = "%d%%" % int(round(value * 100.0))


func _on_lane_brightness_slider_value_changed(value: float) -> void:
	_update_lane_brightness_label(value)


func _update_lane_brightness_label(value: float) -> void:
	%LaneBrightnessValueLabel.text = "%d%%" % int(round(clampf(value, 0.0, 1.0) * 100.0))


func _on_note_opacity_slider_value_changed(value: float) -> void:
	_update_note_opacity_label(value)


func _update_note_opacity_label(value: float) -> void:
	%NoteOpacityValueLabel.text = "%d%%" % int(round(clampf(value, 0.5, 1.0) * 100.0))


func _on_save_button_pressed() -> void:
	ProfileStore.set_latency_offset_ms(%LatencySlider.value)
	ProfileStore.set_note_speed_type(_selected_note_speed_type())
	ProfileStore.set_note_approach_time_ms(%ScrollSpeedSlider.value)
	ProfileStore.set_lane_width_scale(%LaneWidthSlider.value)
	ProfileStore.set_miss_audio_ducking_enabled(%MissDuckingCheckBox.button_pressed)
	ProfileStore.set_menu_music_volume(float(%MenuMusicVolumeSlider.value))
	ProfileStore.set_gameplay_music_volume(float(%GameplayMusicVolumeSlider.value))
	ProfileStore.set_theme_effects_enabled(%ThemeEffectsCheckBox.button_pressed)
	ProfileStore.set_chart_background_disabled(%ChartBackgroundCheckBox.button_pressed)
	ProfileStore.set_ems_color_mode(_ems_color_mode_value())
	ProfileStore.set_ems_custom_primary(%EMSPrimaryColorPicker.color)
	ProfileStore.set_ems_custom_secondary(%EMSSecondaryColorPicker.color)
	ProfileStore.set_ems_custom_accent(%EMSAccentColorPicker.color)
	ProfileStore.set_ems_background_mode(_ems_background_mode_value())
	ProfileStore.set_ems_background_solid_color(%EMSBackgroundColorPicker.color)
	ProfileStore.set_ems_background_brightness(float(%EMSBackgroundBrightnessSlider.value))
	ProfileStore.set_ems_gutter_image_mode(_ems_gutter_image_mode_value())
	ProfileStore.set_ems_gutter_image_path_both(_gutter_button_path(%EMSGutterImageBothButton))
	ProfileStore.set_ems_gutter_image_path_left(_gutter_button_path(%EMSGutterImageLeftButton))
	ProfileStore.set_ems_gutter_image_path_right(_gutter_button_path(%EMSGutterImageRightButton))
	ProfileStore.set_ems_gutter_image_alpha(float(%EMSGutterImageAlphaSlider.value))
	ProfileStore.set_ems_trippy_level(_ems_trippy_level_value())
	ProfileStore.set_ems_hit_effect(_ems_hit_effect_value())
	ProfileStore.set_shaders_enabled(%ShadersCheckBox.button_pressed)
	ProfileStore.set_visual_effect_bloom_enabled(%VisualEffectBloomCheckBox.button_pressed)
	ProfileStore.set_visual_effect_distortion_enabled(%VisualEffectDistortionCheckBox.button_pressed)
	ProfileStore.set_visual_effect_particles_enabled(%VisualEffectParticlesCheckBox.button_pressed)
	ProfileStore.set_visual_effect_background_animations_enabled(%VisualEffectBackgroundAnimationsCheckBox.button_pressed)
	ProfileStore.set_prioritize_fps_enabled(%PrioritizeFPSCheckBox.button_pressed)
	ProfileStore.set_fps_limit(_fps_limit_value())
	ProfileStore.set_vsync_mode(_vsync_mode_value())
	ProfileStore.set_window_mode(_window_mode_value())
	ProfileStore.set_display_resolution(_display_resolution_value())
	ProfileStore.set_lane_brightness(float(%LaneBrightnessSlider.value))
	ProfileStore.set_note_opacity(float(%NoteOpacitySlider.value))
	ProfileStore.set_notes_above_judgement_buttons(%NotesAboveJudgementButtonsCheckBox.button_pressed)
	ProfileStore.set_hit_effects_mode(_hit_effects_mode_value())
	ProfileStore.set_judgement_display_mode(_judgement_display_mode_value())
	ProfileStore.set_in_game_ui_mode(_in_game_ui_mode_value())
	ProfileStore.set_judgement_popups_enabled(%JudgementPopupsCheckBox.button_pressed)
	ProfileStore.set_drive_meter_critical_fx_reduced(%ReduceDriveMeterCriticalFXCheckBox.button_pressed)
	match %DriveMeterThemeOptionButton.selected:
		1:
			ProfileStore.set_drive_meter_theme("classic")
		2:
			ProfileStore.set_drive_meter_theme("mono")
		_:
			ProfileStore.set_drive_meter_theme("auto")
	%CaptureLabel.text = "Saved options."
	if not AppState.is_mobile_platform():
		%CaptureLabel.visible = true
		%CaptureLabel.modulate.a = 1.0
		_start_save_status_fade()


func _on_reset_recommended_defaults_button_pressed() -> void:
	%ResetRecommendedDefaultsDialog.popup_centered()


func _on_reset_recommended_defaults_confirmed() -> void:
	ProfileStore.reset_settings_to_recommended_defaults()
	_sync_options_controls_from_profile()
	_apply_display_controls_live()
	%CaptureLabel.text = "Recommended defaults restored."
	if not AppState.is_mobile_platform():
		%CaptureLabel.visible = true
		%CaptureLabel.modulate.a = 1.0
		_start_save_status_fade()


func _on_back_button_pressed() -> void:
	back_requested.emit()


func _start_save_status_fade() -> void:
	if not is_instance_valid(%CaptureLabel):
		return
	if is_instance_valid(_save_status_tween):
		_save_status_tween.kill()
	_save_status_tween = create_tween()
	_save_status_tween.tween_interval(2.2)
	_save_status_tween.tween_property(%CaptureLabel, "modulate:a", 0.0, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_save_status_tween.tween_callback(func() -> void:
		%CaptureLabel.visible = false
		%CaptureLabel.text = ""
		%CaptureLabel.modulate.a = 1.0
	)


func _on_miss_ducking_check_box_toggled(_toggled_on: bool) -> void:
	pass


func _on_theme_effects_check_box_toggled(_toggled_on: bool) -> void:
	pass


func _on_menu_music_volume_changed(value: float) -> void:
	_update_menu_music_volume_label(value)


func _update_menu_music_volume_label(value: float) -> void:
	%MenuMusicVolumeValueLabel.text = "%d%%" % int(round(clampf(value, 0.0, 1.0) * 100.0))


func _on_gameplay_music_volume_changed(value: float) -> void:
	_update_gameplay_music_volume_label(value)


func _update_gameplay_music_volume_label(value: float) -> void:
	%GameplayMusicVolumeValueLabel.text = "%d%%" % int(round(clampf(value, 0.0, 1.0) * 100.0))


func _setup_ems_color_controls() -> void:
	%EMSColorModeOptionButton.clear()
	%EMSColorModeOptionButton.add_item("Random (New Each Run)", 0)
	%EMSColorModeOptionButton.add_item("Custom", 1)
	var mode := ProfileStore.get_ems_color_mode()
	%EMSColorModeOptionButton.selected = 1 if mode == "custom" else 0

	%EMSPrimaryColorPicker.color = ProfileStore.get_ems_custom_primary()
	%EMSSecondaryColorPicker.color = ProfileStore.get_ems_custom_secondary()
	%EMSAccentColorPicker.color = ProfileStore.get_ems_custom_accent()

	%EMSTrippyLevelOptionButton.clear()
	%EMSTrippyLevelOptionButton.add_item("Subtle", 0)
	%EMSTrippyLevelOptionButton.add_item("Medium", 1)
	%EMSTrippyLevelOptionButton.add_item("Maximum", 2)
	var level := ProfileStore.get_ems_trippy_level()
	match level:
		"subtle":
			%EMSTrippyLevelOptionButton.selected = 0
		"medium":
			%EMSTrippyLevelOptionButton.selected = 1
		_:
			%EMSTrippyLevelOptionButton.selected = 2

	_update_ems_color_picker_visibility()
	%EMSColorModeOptionButton.item_selected.connect(_on_ems_color_mode_selected)


func _on_ems_color_mode_selected(_index: int) -> void:
	_update_ems_color_picker_visibility()


func _update_ems_color_picker_visibility() -> void:
	var is_custom: bool = (%EMSColorModeOptionButton.selected == 1)
	%EMSColorPickersRow.visible = _settings_section == SETTINGS_SECTION_EFFECTS and is_custom


func _setup_ems_background_controls() -> void:
	%EMSBackgroundModeOptionButton.clear()
	%EMSBackgroundModeOptionButton.add_item("Solid (Choose Color)", 0)
	%EMSBackgroundModeOptionButton.add_item("Random (Smooth Shift)", 1)
	%EMSBackgroundModeOptionButton.add_item("Random (Maximum Visuals)", 2)
	var mode := ProfileStore.get_ems_background_mode()
	match mode:
		"random":
			%EMSBackgroundModeOptionButton.selected = 1
		"psychedelic":
			%EMSBackgroundModeOptionButton.selected = 2
		_:
			%EMSBackgroundModeOptionButton.selected = 0
	%EMSBackgroundColorPicker.color = ProfileStore.get_ems_background_solid_color()
	%EMSBackgroundBrightnessSlider.value = ProfileStore.get_ems_background_brightness()
	_update_ems_background_brightness_label(float(%EMSBackgroundBrightnessSlider.value))
	if not %EMSBackgroundBrightnessSlider.value_changed.is_connected(_on_ems_background_brightness_changed):
		%EMSBackgroundBrightnessSlider.value_changed.connect(_on_ems_background_brightness_changed)
	_update_ems_background_picker_visibility()
	%EMSBackgroundModeOptionButton.item_selected.connect(_on_ems_background_mode_selected)


func _on_ems_background_mode_selected(_index: int) -> void:
	_update_ems_background_picker_visibility()


func _update_ems_background_picker_visibility() -> void:
	var is_solid: bool = (%EMSBackgroundModeOptionButton.selected == 0)
	%EMSBackgroundColorRow.visible = _settings_section == SETTINGS_SECTION_EFFECTS and is_solid


func _ems_background_mode_value() -> String:
	match %EMSBackgroundModeOptionButton.selected:
		1:
			return "random"
		2:
			return "psychedelic"
		_:
			return "solid"


func _on_ems_background_brightness_changed(value: float) -> void:
	_update_ems_background_brightness_label(value)


func _update_ems_background_brightness_label(value: float) -> void:
	var recommended := 0.40
	var pct := int(round(value * 100.0))
	var rec_pct := int(round(recommended * 100.0))
	var suffix := " (Recommended: %d%%)" % rec_pct if absf(value - recommended) < 0.0001 else " (Recommended: %d%%)" % rec_pct
	%EMSBackgroundBrightnessValueLabel.text = "%d%%%s" % [pct, suffix]


func _setup_ems_gutter_image_controls() -> void:
	%EMSGutterImageModeOptionButton.clear()
	%EMSGutterImageModeOptionButton.add_item("Off", 0)
	%EMSGutterImageModeOptionButton.add_item("One Image (Both Gutters)", 1)
	%EMSGutterImageModeOptionButton.add_item("Separate Images (Left/Right)", 2)
	var mode := ProfileStore.get_ems_gutter_image_mode()
	match mode:
		"both":
			%EMSGutterImageModeOptionButton.selected = 1
		"separate":
			%EMSGutterImageModeOptionButton.selected = 2
		_:
			%EMSGutterImageModeOptionButton.selected = 0

	_set_gutter_button_path(%EMSGutterImageBothButton, ProfileStore.get_ems_gutter_image_path_both(), "Choose Image (Both Gutters)")
	_set_gutter_button_path(%EMSGutterImageLeftButton, ProfileStore.get_ems_gutter_image_path_left(), "Choose Left Image")
	_set_gutter_button_path(%EMSGutterImageRightButton, ProfileStore.get_ems_gutter_image_path_right(), "Choose Right Image")

	%EMSGutterImageAlphaSlider.value = ProfileStore.get_ems_gutter_image_alpha()
	_update_gutter_alpha_label(float(%EMSGutterImageAlphaSlider.value))
	if not %EMSGutterImageAlphaSlider.value_changed.is_connected(_on_gutter_alpha_changed):
		%EMSGutterImageAlphaSlider.value_changed.connect(_on_gutter_alpha_changed)

	_update_gutter_image_visibility()
	if not %EMSGutterImageModeOptionButton.item_selected.is_connected(_on_gutter_image_mode_selected):
		%EMSGutterImageModeOptionButton.item_selected.connect(_on_gutter_image_mode_selected)

	if not %EMSGutterImageBothButton.pressed.is_connected(_on_choose_gutter_both_pressed):
		%EMSGutterImageBothButton.pressed.connect(_on_choose_gutter_both_pressed)
	if not %EMSGutterImageLeftButton.pressed.is_connected(_on_choose_gutter_left_pressed):
		%EMSGutterImageLeftButton.pressed.connect(_on_choose_gutter_left_pressed)
	if not %EMSGutterImageRightButton.pressed.is_connected(_on_choose_gutter_right_pressed):
		%EMSGutterImageRightButton.pressed.connect(_on_choose_gutter_right_pressed)

	if not %EMSGutterImageFileDialog.file_selected.is_connected(_on_gutter_image_file_selected):
		%EMSGutterImageFileDialog.file_selected.connect(_on_gutter_image_file_selected)
	# Some platforms/dialogs emit files_selected even in single-select mode.
	if %EMSGutterImageFileDialog.has_signal("files_selected"):
		if not %EMSGutterImageFileDialog.files_selected.is_connected(_on_gutter_images_selected):
			%EMSGutterImageFileDialog.files_selected.connect(_on_gutter_images_selected)


func _on_gutter_image_mode_selected(_index: int) -> void:
	_update_gutter_image_visibility()


func _update_gutter_image_visibility() -> void:
	var sel := int(%EMSGutterImageModeOptionButton.selected)
	var effects_active := _settings_section == SETTINGS_SECTION_EFFECTS
	%EMSGutterImageBothRow.visible = effects_active and (sel == 1)
	%EMSGutterImageSeparateRow.visible = effects_active and (sel == 2)
	%EMSGutterImageAlphaRow.visible = effects_active and (sel != 0)
	%EMSGutterImageAlphaSlider.visible = effects_active and (sel != 0)


func _ems_gutter_image_mode_value() -> String:
	match int(%EMSGutterImageModeOptionButton.selected):
		1:
			return "both"
		2:
			return "separate"
		_:
			return "off"


func _on_choose_gutter_both_pressed() -> void:
	_pending_gutter_image_target = "both"
	%EMSGutterImageFileDialog.popup_centered_ratio(0.72)


func _on_choose_gutter_left_pressed() -> void:
	_pending_gutter_image_target = "left"
	%EMSGutterImageFileDialog.popup_centered_ratio(0.72)


func _on_choose_gutter_right_pressed() -> void:
	_pending_gutter_image_target = "right"
	%EMSGutterImageFileDialog.popup_centered_ratio(0.72)


func _on_gutter_image_file_selected(path: String) -> void:
	match _pending_gutter_image_target:
		"both":
			_set_gutter_button_path(%EMSGutterImageBothButton, path, "Choose Image (Both Gutters)")
		"left":
			_set_gutter_button_path(%EMSGutterImageLeftButton, path, "Choose Left Image")
		"right":
			_set_gutter_button_path(%EMSGutterImageRightButton, path, "Choose Right Image")
		_:
			pass
	_pending_gutter_image_target = ""


func _on_gutter_images_selected(paths: PackedStringArray) -> void:
	if paths.is_empty():
		return
	_on_gutter_image_file_selected(str(paths[0]))


func _set_gutter_button_path(button: Button, path: String, fallback_text: String) -> void:
	button.set_meta("gutter_path", path)
	if path.is_empty():
		button.text = fallback_text
		return
	button.text = _short_path_label(path)


func _gutter_button_path(button: Button) -> String:
	if button.has_meta("gutter_path"):
		return str(button.get_meta("gutter_path"))
	return ""


func _short_path_label(path: String) -> String:
	# Show just the filename (and a little prefix) to keep the UI tidy.
	var parts := path.replace("\\", "/").split("/")
	var file := parts[parts.size() - 1] if parts.size() > 0 else path
	return "Selected: %s" % file


func _on_gutter_alpha_changed(value: float) -> void:
	_update_gutter_alpha_label(value)


func _update_gutter_alpha_label(value: float) -> void:
	%EMSGutterImageAlphaValueLabel.text = "%d%%" % int(round(value * 100.0))


func _ems_color_mode_value() -> String:
	return "custom" if %EMSColorModeOptionButton.selected == 1 else "random"


func _ems_trippy_level_value() -> String:
	match %EMSTrippyLevelOptionButton.selected:
		0:
			return "subtle"
		1:
			return "medium"
		_:
			return "max"


func _fps_limit_value() -> int:
	return int(%FPSLimitOptionButton.get_item_id(%FPSLimitOptionButton.selected))


func _vsync_mode_value() -> String:
	match %VSyncOptionButton.selected:
		0:
			return "off"
		2:
			return "adaptive"
		_:
			return "on"


func _window_mode_value() -> String:
	match %WindowModeOptionButton.selected:
		1:
			return "borderless_fullscreen"
		2:
			return "windowed"
		_:
			return "fullscreen"


func _display_resolution_value() -> String:
	return str(%ResolutionOptionButton.get_item_text(%ResolutionOptionButton.selected))


func _hit_effects_mode_value() -> String:
	match %HitEffectsOptionButton.selected:
		0:
			return "off"
		1:
			return "minimal"
		3:
			return "enhanced"
		_:
			return "normal"


func _judgement_display_mode_value() -> String:
	match %JudgementDisplayOptionButton.get_selected_id():
		1:
			return "classic"
		_:
			return "modern"


func _in_game_ui_mode_value() -> String:
	match %InGameUIOptionButton.get_selected_id():
		1:
			return "modern"
		_:
			return "classic"


func _ems_hit_effect_value() -> String:
	match %EMSHitEffectOptionButton.get_selected_id():
		1:
			return "pressure"
		_:
			return "circular"


func _apply_display_controls_live() -> void:
	DisplaySettingsApplier.apply_values(
		_fps_limit_value(),
		_vsync_mode_value(),
		_window_mode_value(),
		_display_resolution_value()
	)


func _update_visual_effects_visibility() -> void:
	var visible: bool = _settings_section == SETTINGS_SECTION_GRAPHICS and %ShadersCheckBox.button_pressed
	%VisualEffectsLabel.visible = visible
	%VisualEffectBloomCheckBox.visible = visible
	%VisualEffectDistortionCheckBox.visible = visible
	%VisualEffectParticlesCheckBox.visible = visible
	%VisualEffectBackgroundAnimationsCheckBox.visible = visible


func _update_resolution_control_state() -> void:
	var windowed := _window_mode_value() == "windowed"
	%ResolutionOptionButton.disabled = not windowed
	%ResolutionOptionButton.modulate.a = 1.0 if windowed else 0.55
	%ResolutionLabel.modulate.a = 1.0 if windowed else 0.55
	%ResolutionOptionButton.tooltip_text = "" if windowed else "Fullscreen uses the monitor's native resolution."
	%ResolutionLabel.tooltip_text = %ResolutionOptionButton.tooltip_text


func _on_display_option_changed(_index: int) -> void:
	_update_resolution_control_state()
	_apply_display_controls_live()


func _on_shaders_check_box_toggled(_toggled_on: bool) -> void:
	_update_visual_effects_visibility()


func _on_prioritize_fps_check_box_toggled(_toggled_on: bool) -> void:
	pass


func _on_window_mode_option_button_item_selected(index: int) -> void:
	_on_display_option_changed(index)


func _on_reset_steam_stats_button_pressed() -> void:
	%CaptureLabel.text = "Resetting Steam stats first, then achievements..."
	if not AppState.is_mobile_platform():
		%CaptureLabel.visible = true
	var result: Dictionary = {"ok": false, "message": "Steam reset unavailable."}
	if SteamAchievements != null:
		result = await SteamAchievements.reset_all_stats_and_achievements()
	var ok := bool(result.get("ok", false))
	var stats_reset := bool(result.get("stats_reset", false))
	var achievements_reset := bool(result.get("achievements_reset", false))
	var cloud_synced := bool(result.get("cloud_synced", false))
	if ok:
		%CaptureLabel.text = str(result.get("message", "Steam stats and achievements reset."))
	else:
		%CaptureLabel.text = "Reset check failed  •  stats: %s  •  achievements: %s  •  cloud: %s" % [
			"OK" if stats_reset else "NOT CLEARED",
			"OK" if achievements_reset else "NOT CLEARED",
			"OK" if cloud_synced else "NOT SYNCED",
		]
	if not AppState.is_mobile_platform():
		%CaptureLabel.visible = true


func is_menu_navigation_blocked() -> bool:
	return not _capture_action.is_empty()


func _refresh_menu_navigation() -> void:
	if _menu_navigator != null:
		_menu_navigator.refresh_focusables()


func _finish_capture() -> void:
	_capture_action = ""
	_capture_controller_binding = false
	%CaptureLabel.text = ""
	%CaptureLabel.visible = false
	_rebuild_binding_rows()


func _make_binding_row(action: String, binding_display: Dictionary, pressed_action: Callable, size: Vector2, metrics: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var action_label := Label.new()
	action_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_label.text = _binding_label(action)
	HDTheme.apply_label(action_label, "body", HDTheme.SECONDARY)
	row.add_child(action_label)
	var bind_button := Button.new()
	bind_button.text = "" if InputBindingGlyph.should_draw_glyph(binding_display) else InputBindingGlyph.display_text(binding_display)
	bind_button.tooltip_text = InputBindingGlyph.display_tooltip(binding_display)
	bind_button.add_theme_stylebox_override("normal", HDTheme.button_style(false))
	bind_button.add_theme_stylebox_override("hover", HDTheme.button_style(false))
	bind_button.add_theme_stylebox_override("pressed", HDTheme.button_style(false))
	bind_button.custom_minimum_size = Vector2(180, metrics["button_height"])
	bind_button.add_theme_font_size_override("font_size", HDTheme.text_size("button_secondary", size))
	bind_button.pressed.connect(pressed_action)
	if InputBindingGlyph.should_draw_glyph(binding_display):
		var glyph: Control = InputBindingGlyph.new()
		glyph.set_display(binding_display)
		glyph.anchor_left = 0.5
		glyph.anchor_top = 0.5
		glyph.anchor_right = 0.5
		glyph.anchor_bottom = 0.5
		glyph.offset_left = -36.0
		glyph.offset_top = -18.0
		glyph.offset_right = 36.0
		glyph.offset_bottom = 18.0
		bind_button.add_child(glyph)
	row.add_child(bind_button)
	return row


func _binding_label(action: String) -> String:
	if action.begins_with("lane_"):
		var lane_text := action.trim_prefix("lane_")
		if lane_text.is_valid_int():
			return "Lane %d" % (int(lane_text) + 1)
	match action:
		"ui_up":
			return "Menu Up"
		"ui_down":
			return "Menu Down"
		"ui_left":
			return "Menu Left"
		"ui_right":
			return "Menu Right"
		"ui_accept":
			return "Menu Accept"
		"ui_cancel":
			return "Menu Cancel"
		_:
			var action_name := action.replace("_", " ")
			return action_name.substr(0, 1).to_upper() + action_name.substr(1)


func _controller_binding_text(binding_variant: Variant) -> String:
	if binding_variant is not Dictionary:
		return "UNBOUND"
	var binding: Dictionary = binding_variant as Dictionary
	match str(binding.get("kind", "")).to_lower():
		"axis":
			return _controller_axis_name(int(binding.get("axis", 0)), int(binding.get("direction", 1)))
		"button":
			return _controller_button_name(int(binding.get("button_index", 0)))
		_:
			return "UNBOUND"


func _controller_button_name(button_index: int) -> String:
	match button_index:
		JOY_BUTTON_A:
			return "A / CROSS"
		JOY_BUTTON_B:
			return "B / CIRCLE"
		JOY_BUTTON_X:
			return "X / SQUARE"
		JOY_BUTTON_Y:
			return "Y / TRIANGLE"
		JOY_BUTTON_LEFT_SHOULDER:
			return "L1 / LB"
		JOY_BUTTON_RIGHT_SHOULDER:
			return "R1 / RB"
		JOY_BUTTON_START:
			return "START / OPTIONS"
		JOY_BUTTON_DPAD_UP:
			return "DPAD UP"
		JOY_BUTTON_DPAD_DOWN:
			return "DPAD DOWN"
		JOY_BUTTON_DPAD_LEFT:
			return "DPAD LEFT"
		JOY_BUTTON_DPAD_RIGHT:
			return "DPAD RIGHT"
		JOY_BUTTON_LEFT_STICK:
			return "L3"
		JOY_BUTTON_RIGHT_STICK:
			return "R3"
		_:
			return "BUTTON %d" % button_index


func _controller_axis_name(axis: int, direction: int) -> String:
	var suffix := "-" if direction < 0 else "+"
	match axis:
		JOY_AXIS_LEFT_X:
			return "LEFT STICK X%s" % suffix
		JOY_AXIS_LEFT_Y:
			return "LEFT STICK Y%s" % suffix
		JOY_AXIS_RIGHT_X:
			return "RIGHT STICK X%s" % suffix
		JOY_AXIS_RIGHT_Y:
			return "RIGHT STICK Y%s" % suffix
		JOY_AXIS_TRIGGER_LEFT:
			return "L2 / LT%s" % suffix
		JOY_AXIS_TRIGGER_RIGHT:
			return "R2 / RT%s" % suffix
		_:
			return "AXIS %d%s" % [axis, suffix]
