extends Control

const HDTheme = preload("res://scripts/ui/HDTheme.gd")
const MobileScrollButtonScript = preload("res://scripts/ui/MobileScrollButton.gd")
const GameModeConfig = preload("res://scripts/gameplay/GameModeConfig.gd")
const MenuNavigator = preload("res://scripts/ui/MenuNavigator.gd")

signal back_requested
signal chart_requested(song_id: String)
signal start_requested(song_entry: Dictionary, difficulty: String, mode: String)

var _selected_song: Dictionary = {}
var _pending_mode := GameModeConfig.DEFAULT_MODE
var _menu_navigator: MenuNavigator
@onready var _back_button: Button = $BackButton


func _ready() -> void:
	_apply_mobile_scroll_buttons()
	_menu_navigator = MenuNavigator.install(self, Callable(self, "_on_back_button_pressed"))
	_back_button.move_to_front()
	_apply_layout()
	_rebuild()
	get_viewport().size_changed.connect(_apply_layout)
	PremiumStore.store_changed.connect(_rebuild)
	call_deferred("_refresh_menu_navigation")


func _exit_tree() -> void:
	PremiumStore.stop_audio_preview()


func _apply_layout() -> void:
	var size: Vector2 = get_viewport_rect().size
	var metrics: Dictionary = HDTheme.overlay_metrics(size)
	%Background.color = HDTheme.BG
	_back_button.z_index = 20
	_back_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_back_button.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	HDTheme.apply_label(%BackLabel, "caption", HDTheme.SECONDARY)
	%BackLabel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	HDTheme.apply_back_button(_back_button, %BackLabel)
	HDTheme.apply_label(%TitleLabel, "screen_title", HDTheme.CYAN, true)
	HDTheme.apply_label(%SubtitleLabel, "caption", HDTheme.TERTIARY, true)
	HDTheme.apply_label(%StatusLabel, "supporting", HDTheme.SECONDARY, true)
	HDTheme.apply_label(%FooterLabel, "caption", HDTheme.TERTIARY, true)
	%Divider.color = HDTheme.CYAN * Color(1, 1, 1, 0.30)
	%RowsVBox.add_theme_constant_override("separation", 14)
	%SelectionPanel.custom_minimum_size = Vector2(HDTheme.overlay_metrics(size)["panel_width"] * 0.82, HDTheme.overlay_metrics(size)["panel_height"] * 0.72)
	%SelectionButtons.add_theme_constant_override("separation", 14)
	HDTheme.apply_label(%SelectionTitleLabel, "screen_title", HDTheme.CYAN, true)
	HDTheme.apply_label(%SelectionSubtitleLabel, "body", HDTheme.SECONDARY, true)
	%RestoreButton.custom_minimum_size = Vector2(240, metrics["button_height"])
	%RestoreButton.add_theme_stylebox_override("normal", HDTheme.button_style(false))
	%RestoreButton.add_theme_stylebox_override("hover", HDTheme.button_style(false))
	%RestoreButton.add_theme_stylebox_override("pressed", HDTheme.button_style(false))
	%RestoreButton.add_theme_font_size_override("font_size", HDTheme.text_size("button_secondary", size))
	%SelectionCancelButton.custom_minimum_size = Vector2(0, HDTheme.overlay_metrics(size)["button_height"])
	%SelectionCancelButton.add_theme_stylebox_override("normal", HDTheme.button_style(false))
	%SelectionCancelButton.add_theme_stylebox_override("hover", HDTheme.button_style(false))
	%SelectionCancelButton.add_theme_stylebox_override("pressed", HDTheme.button_style(false))
	%SelectionCancelButton.add_theme_font_size_override("font_size", HDTheme.text_size("button_secondary", size))
	%SelectionPanel.add_theme_stylebox_override("panel", HDTheme.overlay_panel_style())
	%OverlayDim.color = Color(0, 0, 0, 0.74)


func _rebuild() -> void:
	%SubtitleLabel.text = "%d PREMIUM TRACKS" % PremiumStore.get_store_songs().size()
	%StatusLabel.text = PremiumStore.get_status_message()
	%FooterLabel.text = "Restore purchases for previously bought tracks."
	_hide_selection_overlay()
	for child in %RowsVBox.get_children():
		child.queue_free()
	for song in PremiumStore.get_store_songs():
		%RowsVBox.add_child(_build_row(song))
	call_deferred("_refresh_menu_navigation")


func _build_row(song: Dictionary) -> Control:
	var size: Vector2 = get_viewport_rect().size
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", HDTheme.card_style())
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)

	var root: VBoxContainer = VBoxContainer.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	var title: Label = Label.new()
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.text = str(song.get("title", "Unknown Track"))
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	HDTheme.apply_label(title, "section_title")
	root.add_child(title)

	var artist: Label = Label.new()
	artist.mouse_filter = Control.MOUSE_FILTER_IGNORE
	artist.text = "by %s" % str(song.get("artist", "Unknown Artist"))
	artist.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	HDTheme.apply_label(artist, "caption", HDTheme.SECONDARY)
	root.add_child(artist)

	var actions: HBoxContainer = HBoxContainer.new()
	actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	actions.add_theme_constant_override("separation", 12)
	root.add_child(actions)

	var listen_button := _make_action_button("LISTEN", HDTheme.PURPLE, size)
	listen_button.pressed.connect(_on_listen_pressed.bind(str(song.get("song_id", ""))))
	actions.add_child(listen_button)

	var chart_button := _make_action_button("CHART", HDTheme.CYAN, size)
	chart_button.pressed.connect(_on_chart_pressed.bind(str(song.get("song_id", ""))))
	actions.add_child(chart_button)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	actions.add_child(spacer)

	var owned: bool = PremiumStore.is_purchased_product(str(song.get("product_id", "")))
	if owned:
		var owned_badge := Label.new()
		owned_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		owned_badge.text = "OWNED"
		HDTheme.apply_label(owned_badge, "button_secondary", Color(0.20, 0.95, 0.50, 1.0), true)
		actions.add_child(owned_badge)
		var play_button := _make_action_button("PLAY NOW", HDTheme.CYAN, size, 152.0)
		play_button.pressed.connect(_on_play_now_pressed.bind(str(song.get("song_id", ""))))
		actions.add_child(play_button)
	else:
		var price_label := Label.new()
		price_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		price_label.text = PremiumStore.get_display_price(str(song.get("product_id", "")))
		HDTheme.apply_label(price_label, "caption", HDTheme.primary_text())
		actions.add_child(price_label)

		var buy_button := _make_action_button("BUY", HDTheme.CYAN, size, 112.0)
		buy_button.pressed.connect(_on_buy_pressed.bind(str(song.get("product_id", ""))))
		actions.add_child(buy_button)

	return panel


func _make_action_button(title: String, accent: Color, size: Vector2, width: float = 108.0) -> Button:
	var button: Button = MobileScrollButtonScript.new() if AppState.is_mobile_platform() else Button.new()
	button.text = title
	button.custom_minimum_size = Vector2(width, 42)
	button.add_theme_stylebox_override("normal", HDTheme.button_style(false))
	button.add_theme_stylebox_override("hover", HDTheme.button_style(false))
	button.add_theme_stylebox_override("pressed", HDTheme.button_style(false))
	button.add_theme_font_size_override("font_size", HDTheme.text_size("caption", size))
	button.add_theme_color_override("font_color", accent)
	return button


func _on_back_button_pressed() -> void:
	PremiumStore.stop_audio_preview()
	back_requested.emit()


func _on_restore_button_pressed() -> void:
	var outcome: Dictionary = PremiumStore.restore_purchases()
	%StatusLabel.text = str(outcome.get("message", "Restoring purchases..."))


func _on_listen_pressed(song_id: String) -> void:
	var outcome: Dictionary = PremiumStore.start_audio_preview(song_id)
	%StatusLabel.text = str(outcome.get("message", ""))


func _on_chart_pressed(song_id: String) -> void:
	chart_requested.emit(song_id)


func _on_buy_pressed(product_id: String) -> void:
	var outcome: Dictionary = PremiumStore.purchase_product(product_id)
	%StatusLabel.text = str(outcome.get("message", ""))


func _on_play_now_pressed(song_id: String) -> void:
	_selected_song = ContentRegistry.get_song(song_id)
	if _selected_song.is_empty():
		%StatusLabel.text = "Unable to load that track."
		return
	_show_mode_selection()


func _hide_selection_overlay() -> void:
	%OverlayDim.visible = false
	%SelectionCenter.visible = false
	for child in %SelectionButtons.get_children():
		if child != %SelectionCancelButton:
			child.queue_free()
	call_deferred("_refresh_menu_navigation")


func _show_mode_selection() -> void:
	var available_modes := ContentRegistry.get_supported_modes(_selected_song)
	if available_modes.is_empty():
		%StatusLabel.text = "No playable chart modes were found for %s." % str(_selected_song.get("display_name", "this track"))
		return
	var player_level: int = ProgressionManager.get_level()
	var unlocked_modes: Array[String] = []
	for mode_id in available_modes:
		if GameModeConfig.is_unlocked_for_level(mode_id, player_level):
			unlocked_modes.append(mode_id)
	if unlocked_modes.is_empty():
		%StatusLabel.text = "Reach level %d to unlock more play modes." % mini(
			GameModeConfig.get_required_level(GameModeConfig.SYNTHESIZED),
			GameModeConfig.get_required_level(GameModeConfig.STEMS_RANDOM)
		)
		return
	var preferred_mode: String = ProfileStore.get_selected_mode()
	_pending_mode = preferred_mode if unlocked_modes.has(preferred_mode) else unlocked_modes[0]
	_show_selection_overlay(
		"SELECT MODE",
		"%s\n%s" % [str(_selected_song.get("display_name", "Unknown")), str(_selected_song.get("artist", "Unknown Artist"))],
		available_modes,
		Callable(self, "_on_mode_selected"),
		Callable(self, "_mode_option_label"),
		Callable(self, "_mode_option_enabled")
	)


func _show_difficulty_selection() -> void:
	var difficulties: Array[String] = ContentRegistry.get_supported_difficulties(_selected_song, _pending_mode)
	if difficulties.is_empty():
		%StatusLabel.text = "No %s charts were found for %s." % [GameModeConfig.get_short_label(_pending_mode), str(_selected_song.get("display_name", "this track"))]
		_hide_selection_overlay()
		return
	_show_selection_overlay(
		"SELECT DIFFICULTY",
		"%s  •  %s" % [str(_selected_song.get("display_name", "Unknown")), GameModeConfig.get_short_label(_pending_mode)],
		difficulties,
		Callable(self, "_on_difficulty_selected")
	)


func _show_selection_overlay(title: String, subtitle: String, options: Array, callback: Callable, label_builder: Callable = Callable(), enabled_builder: Callable = Callable()) -> void:
	%OverlayDim.visible = true
	%SelectionCenter.visible = true
	%SelectionTitleLabel.text = title
	%SelectionSubtitleLabel.text = subtitle
	for child in %SelectionButtons.get_children():
		if child != %SelectionCancelButton:
			child.queue_free()
	for option in options:
		var button := Button.new()
		button.text = label_builder.call(option) if label_builder.is_valid() else str(option)
		button.custom_minimum_size = Vector2(0, HDTheme.overlay_metrics(get_viewport_rect().size)["button_height"])
		var enabled: bool = enabled_builder.call(option) if enabled_builder.is_valid() else true
		button.disabled = not enabled
		button.add_theme_stylebox_override("normal", HDTheme.button_style(enabled))
		button.add_theme_stylebox_override("hover", HDTheme.button_style(enabled))
		button.add_theme_stylebox_override("pressed", HDTheme.button_style(enabled))
		button.add_theme_font_size_override("font_size", HDTheme.text_size("button_secondary", get_viewport_rect().size))
		if enabled:
			button.pressed.connect(func() -> void:
				callback.call(option)
			)
		%SelectionButtons.add_child(button)
		%SelectionButtons.move_child(button, %SelectionButtons.get_child_count() - 2)
	call_deferred("_refresh_menu_navigation")


func _mode_option_label(mode_id: String) -> String:
	if GameModeConfig.is_unlocked_for_level(mode_id, ProgressionManager.get_level()):
		return GameModeConfig.get_display_name(mode_id)
	return "%s  •  UNLOCKS AT LEVEL %d" % [GameModeConfig.get_display_name(mode_id), GameModeConfig.get_required_level(mode_id)]


func _mode_option_enabled(mode_id: String) -> bool:
	return GameModeConfig.is_unlocked_for_level(mode_id, ProgressionManager.get_level())


func _on_mode_selected(mode_id: String) -> void:
	_pending_mode = mode_id
	ProfileStore.set_selected_mode(mode_id)
	_show_difficulty_selection()


func _on_difficulty_selected(difficulty: String) -> void:
	_hide_selection_overlay()
	start_requested.emit(_selected_song, difficulty, _pending_mode)


func _on_selection_cancel_button_pressed() -> void:
	_hide_selection_overlay()


func _apply_mobile_scroll_buttons() -> void:
	if not AppState.is_mobile_platform():
		return
	%RestoreButton.set_script(MobileScrollButtonScript)


func _refresh_menu_navigation() -> void:
	if _menu_navigator != null:
		_menu_navigator.refresh_focusables()
