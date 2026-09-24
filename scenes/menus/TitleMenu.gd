extends Control

const HDTheme = preload("res://scripts/ui/HDTheme.gd")
const MobileScrollButtonScript = preload("res://scripts/ui/MobileScrollButton.gd")
const MenuNavigator = preload("res://scripts/ui/MenuNavigator.gd")

signal play_requested
signal visualizer_requested
signal practice_requested
signal multiplayer_requested
signal leaderboards_requested
signal ems_creator_requested
signal progression_requested
signal shop_requested
signal settings_requested
signal calibration_requested
signal stats_requested
signal harmonic_charter_requested
signal local_songs_requested
signal community_charts_requested

@onready var _buttons: VBoxContainer = %ButtonsVBox
@onready var _status_label: Label = %StatusLabel
@onready var _now_playing_label: Label = %NowPlayingLabel
@onready var _footer: Label = %FooterLabel
@onready var _multiplayer_button: Button = %MultiplayerButton
@onready var _ems_creator_button: Button = %EMSCreatorButton
@onready var _stats_button: Button = %StatsButton
@onready var _charter_button: Button = %CharterButton
@onready var _local_songs_button: Button = %LocalSongsButton
@onready var _community_charts_button: Button = %CommunityChartsButton
@onready var _root_vbox: VBoxContainer = $SafeMargin/MenuScroll/RootVBox
@onready var _center_spacer: Control = $SafeMargin/MenuScroll/RootVBox/CenterSpacer
@onready var _buttons_wrap: CenterContainer = $SafeMargin/MenuScroll/RootVBox/ButtonsWrap
@onready var _divider_wrap: CenterContainer = $SafeMargin/MenuScroll/RootVBox/DividerWrap
@onready var _menu_scroll: ScrollContainer = $SafeMargin/MenuScroll
@onready var _title_logo: TextureRect = %TitleLogo
@onready var _menu_mute_button: Button = %MenuMuteButton
@onready var _quit_button: Button = %QuitButton
var _menu_navigator: MenuNavigator


func _ready() -> void:
	_apply_mobile_scroll_buttons()
	_menu_navigator = MenuNavigator.install(self)
	apply_layout()
	get_viewport().size_changed.connect(apply_layout)
	ProgressionManager.progression_changed.connect(apply_layout)
	if AppState.has_signal("steam_availability_changed") and not AppState.steam_availability_changed.is_connected(_on_steam_availability_changed):
		AppState.steam_availability_changed.connect(_on_steam_availability_changed)
	if MenuAudio != null:
		if not MenuAudio.playback_started.is_connected(_on_menu_audio_playback_started):
			MenuAudio.playback_started.connect(_on_menu_audio_playback_started)
		if not MenuAudio.playback_stopped.is_connected(_on_menu_audio_playback_stopped):
			MenuAudio.playback_stopped.connect(_on_menu_audio_playback_stopped)
	_refresh_menu_mute_button()
	_refresh_now_playing_label()
	call_deferred("_stabilize_initial_layout")


func apply_layout() -> void:
	var size: Vector2 = get_viewport_rect().size
	var available_width: float = _menu_scroll.size.x if _menu_scroll != null and _menu_scroll.size.x > 0.0 else size.x - 36.0
	var metrics: Dictionary = HDTheme.main_menu_metrics(size)
	var is_desktop: bool = HDTheme.device_class_for(size) == HDTheme.DeviceClass.DESKTOP
	var compact_desktop: bool = is_desktop and size.y < 980.0
	var desktop_spacing_scale: float = 0.82 if is_desktop else 1.0
	# With a single logo (no subtitle), keep top/bottom padding tight.
	var header_top: float = 0.0
	var title_gap: float = 0.0
	var divider_gap: float = 0.0
	var footer_gap: float = 10.0 if compact_desktop else float(metrics["footer_bottom"]) * (0.55 if is_desktop else 1.0)
	var button_gap: int = int(round(float(metrics["button_gap"]) * (0.85 if is_desktop else 1.0)))
	var button_width: float = float(metrics["button_width"])
	var button_height: float = float(metrics["button_height"]) * (0.80 if compact_desktop else (0.9 if is_desktop else 1.0))
	%Background.color = HDTheme.BG
	HDTheme.apply_label(_footer, "footer", HDTheme.TERTIARY, true)
	HDTheme.apply_label(_status_label, "body", HDTheme.SECONDARY, true)
	HDTheme.apply_label(_now_playing_label, "footer", HDTheme.CYAN, true)
	var content_width: float = maxf(available_width, button_width + 40.0)
	_root_vbox.custom_minimum_size.x = content_width
	_divider_wrap.custom_minimum_size.x = content_width
	_buttons_wrap.custom_minimum_size.x = content_width
	for label in [_status_label, _now_playing_label, _footer]:
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_refresh_now_playing_label()
	_title_logo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Make the logo larger and use more of the available header space.
	var max_logo_width := minf(content_width, button_width + 980.0)
	var max_logo_height: float = clampf(size.y * (0.34 if is_desktop else 0.40), 220.0, 520.0)
	var logo_height: float = float(metrics.get("header_logo_height", -1.0))
	if logo_height <= 0.0 and _title_logo.texture != null:
		var tex_size: Vector2 = _title_logo.texture.get_size()
		if tex_size.x > 0.0:
			logo_height = max_logo_width * (tex_size.y / tex_size.x)
	# Clamp to avoid an oversized logo rect that creates dead space above the buttons.
	if logo_height <= 0.0:
		logo_height = 300.0
	_title_logo.custom_minimum_size = Vector2(max_logo_width, clampf(logo_height, 200.0, max_logo_height))
	# Avoid vertical centering which creates large dead areas above/below the logo.
	_root_vbox.alignment = BoxContainer.ALIGNMENT_BEGIN
	%HeaderSpacer.custom_minimum_size.y = header_top
	%TitleGap.custom_minimum_size.y = title_gap
	%DividerGap.custom_minimum_size.y = divider_gap
	_center_spacer.custom_minimum_size.y = 0.0
	%FooterSpacer.custom_minimum_size.y = footer_gap
	%Divider.color = HDTheme.CYAN * Color(1, 1, 1, 0.35)
	_buttons.add_theme_constant_override("separation", button_gap)
	for child in _buttons.get_children():
		if child is Button:
			_style_menu_button(child, false, button_width, button_height, size)
	_multiplayer_button.visible = AppState.supports_desktop_tools()
	_multiplayer_button.disabled = not AppState.can_use_steam_services()
	_multiplayer_button.tooltip_text = "" if not _multiplayer_button.disabled else "Open Steam to enable Multiplayer"
	_ems_creator_button.visible = AppState.supports_desktop_tools()
	_ems_creator_button.disabled = not _ems_creator_button.visible
	_stats_button.visible = AppState.has_steam_desktop_support()
	_stats_button.disabled = not _stats_button.visible
	_charter_button.visible = AppState.supports_desktop_tools()
	_charter_button.disabled = not _charter_button.visible
	_local_songs_button.visible = AppState.supports_desktop_tools() and not OS.has_feature("android")
	_local_songs_button.disabled = not _local_songs_button.visible
	_community_charts_button.visible = AppState.has_steam_desktop_support() and not OS.has_feature("android")
	_community_charts_button.disabled = not _community_charts_button.visible
	var player: Dictionary = ProgressionManager.get_player_data()
	_status_label.text = "LEVEL %d  •  %d VIBEZ  •  %d SONGS READY" % [
		int(player.get("level", 1)),
		int(player.get("currency", 0)),
		ContentRegistry.get_progression_ordered_songs().size()
	]
	_footer.text = "© 2026 HARMONIC DRIVE"
	_style_footer_buttons(size)


func _style_footer_buttons(size: Vector2) -> void:
	if _menu_mute_button == null:
		return
	_menu_mute_button.custom_minimum_size = Vector2(60, 60)
	_menu_mute_button.add_theme_stylebox_override("normal", HDTheme.card_style())
	_menu_mute_button.add_theme_stylebox_override("hover", HDTheme.card_style())
	_menu_mute_button.add_theme_stylebox_override("pressed", HDTheme.card_style())
	_menu_mute_button.add_theme_font_size_override("font_size", HDTheme.text_size("screen_title", size))
	_menu_mute_button.add_theme_color_override("font_color", HDTheme.primary_text())
	_menu_mute_button.tooltip_text = "Toggle main menu audio"
	if _quit_button == null:
		return
	_quit_button.visible = not AppState.is_mobile_platform()
	_quit_button.disabled = not _quit_button.visible
	_quit_button.custom_minimum_size = Vector2(118, 60)
	_quit_button.add_theme_stylebox_override("normal", HDTheme.card_style())
	_quit_button.add_theme_stylebox_override("hover", HDTheme.card_style())
	_quit_button.add_theme_stylebox_override("pressed", HDTheme.card_style())
	_quit_button.add_theme_font_size_override("font_size", HDTheme.text_size("footer", size))
	_quit_button.add_theme_color_override("font_color", HDTheme.primary_text())
	_quit_button.tooltip_text = "Quit Harmonic Drive"


func _on_menu_mute_button_pressed() -> void:
	if MenuAudio != null and MenuAudio.has_method("toggle_title_mute"):
		MenuAudio.toggle_title_mute()
	_refresh_menu_mute_button()


func _on_quit_button_pressed() -> void:
	get_tree().quit()


func _refresh_menu_mute_button() -> void:
	if _menu_mute_button == null:
		return
	var muted := false
	if MenuAudio != null and MenuAudio.has_method("is_title_muted"):
		muted = bool(MenuAudio.is_title_muted())
	_menu_mute_button.text = "🔇" if muted else "🔊"


func _on_menu_audio_playback_started(_song_id: String) -> void:
	_refresh_now_playing_label()


func _on_menu_audio_playback_stopped() -> void:
	_refresh_now_playing_label()


func _refresh_now_playing_label() -> void:
	if _now_playing_label == null:
		return
	var song_id := ""
	if MenuAudio != null and MenuAudio.has_method("get_current_song_id") and MenuAudio.has_method("is_playing") and bool(MenuAudio.is_playing()):
		song_id = str(MenuAudio.get_current_song_id()).strip_edges()
	var song_name := _resolve_song_display_name(song_id)
	_now_playing_label.visible = not song_name.is_empty()
	_now_playing_label.text = "NOW PLAYING: %s" % song_name


func _resolve_song_display_name(song_id: String) -> String:
	if song_id.is_empty() or ContentRegistry == null:
		return song_id
	var song_entry: Dictionary = ContentRegistry.get_song(song_id)
	if song_entry.is_empty():
		return song_id
	for key in ["display_name", "title", "name", "song_name"]:
		var candidate := str(song_entry.get(key, "")).strip_edges()
		if not candidate.is_empty():
			return candidate
	return song_id


func _stabilize_initial_layout() -> void:
	apply_layout()
	if _menu_scroll != null:
		_menu_scroll.scroll_vertical = 0
		_menu_scroll.scroll_horizontal = 0
	await get_tree().process_frame
	apply_layout()
	if _menu_scroll != null:
		_menu_scroll.scroll_vertical = 0
		_menu_scroll.scroll_horizontal = 0


func _style_menu_button(button: Button, primary: bool, width: float, height: float, size: Vector2) -> void:
	button.custom_minimum_size = Vector2(width, height)
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.add_theme_stylebox_override("normal", HDTheme.button_style(primary))
	button.add_theme_stylebox_override("hover", HDTheme.button_style(primary))
	button.add_theme_stylebox_override("pressed", HDTheme.button_style(primary))
	button.add_theme_font_size_override("font_size", HDTheme.text_size("button_primary" if primary else "button_secondary", size))
	button.add_theme_color_override("font_color", HDTheme.primary_text() if primary else HDTheme.SECONDARY)
	button.add_theme_constant_override("h_separation", 12)


func _build_label() -> String:
	var version_name: String = str(ProjectSettings.get_setting("application/config/version", "1.0")).strip_edges()
	if version_name.is_empty():
		version_name = "1.2"
	var build_number: String = "dev"
	if OS.has_feature("android") and Engine.has_singleton("GooglePlayGames"):
		var plugin: Object = Engine.get_singleton("GooglePlayGames")
		if plugin != null and plugin.has_method("getAppVersionCode"):
			var android_build: String = str(plugin.call("getAppVersionCode")).strip_edges()
			if not android_build.is_empty():
				build_number = android_build
	return "VERSION %s" % [version_name]


func _apply_mobile_scroll_buttons() -> void:
	if not AppState.is_mobile_platform():
		return
	for child in _buttons.get_children():
		if child is Button:
			child.set_script(MobileScrollButtonScript)


func _on_play_button_pressed() -> void:
	play_requested.emit()


func _on_visualizer_button_pressed() -> void:
	visualizer_requested.emit()


func _on_practice_button_pressed() -> void:
	practice_requested.emit()


func _on_multiplayer_button_pressed() -> void:
	if not AppState.can_use_steam_services():
		return
	multiplayer_requested.emit()


func _on_ems_creator_button_pressed() -> void:
	ems_creator_requested.emit()


func _on_leaderboards_button_pressed() -> void:
	leaderboards_requested.emit()


func _on_progression_button_pressed() -> void:
	progression_requested.emit()


func _on_shop_button_pressed() -> void:
	shop_requested.emit()


func _on_options_button_pressed() -> void:
	settings_requested.emit()


func _on_calibration_button_pressed() -> void:
	calibration_requested.emit()


func _on_stats_button_pressed() -> void:
	stats_requested.emit()


func _on_charter_button_pressed() -> void:
	harmonic_charter_requested.emit()


func _on_local_songs_button_pressed() -> void:
	local_songs_requested.emit()


func _on_community_charts_button_pressed() -> void:
	community_charts_requested.emit()


func _on_steam_availability_changed(_ready: bool) -> void:
	apply_layout()
