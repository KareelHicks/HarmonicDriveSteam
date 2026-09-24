extends Control

const HDTheme = preload("res://scripts/ui/HDTheme.gd")
const MobileScrollButtonScript = preload("res://scripts/ui/MobileScrollButton.gd")
const MenuNavigator = preload("res://scripts/ui/MenuNavigator.gd")
const SongJacketService = preload("res://scripts/ui/SongJacketService.gd")

signal back_requested
signal open_shop_requested
var _menu_navigator: MenuNavigator
@onready var _back_button: Button = $Center/Panel/Margin/VBox/BackButton


func _ready() -> void:
	_apply_mobile_scroll_buttons()
	_menu_navigator = MenuNavigator.install(self, Callable(self, "_on_back_button_pressed"))
	_back_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_back_button.move_to_front()
	_apply_layout()
	_rebuild()
	get_viewport().size_changed.connect(_apply_layout)
	ProgressionManager.progression_changed.connect(_rebuild)


func _apply_layout() -> void:
	var size: Vector2 = get_viewport_rect().size
	var metrics: Dictionary = HDTheme.overlay_metrics(size)
	%Background.color = HDTheme.BG
	%Panel.add_theme_stylebox_override("panel", HDTheme.overlay_panel_style())
	%Panel.custom_minimum_size = Vector2(minf(size.x - 40.0, metrics["panel_width"] * 1.35), minf(size.y - 40.0, metrics["panel_height"] * 1.18))
	HDTheme.apply_label(%BackLabel, "caption", HDTheme.SECONDARY)
	%BackLabel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	HDTheme.apply_back_button(_back_button, %BackLabel)
	_back_button.size_flags_horizontal = 0
	HDTheme.apply_label(%TitleLabel, "screen_title", HDTheme.CYAN, true)
	HDTheme.apply_label(%SummaryLabel, "body", HDTheme.SECONDARY, true)
	HDTheme.apply_label(%ProgressLabel, "supporting", HDTheme.TERTIARY, true)
	%SectionsVBox.add_theme_constant_override("separation", 14)
	for button in [%ShopButton, %BackActionButton]:
		button.custom_minimum_size.y = metrics["button_height"]
		button.add_theme_font_size_override("font_size", HDTheme.text_size("button_secondary", size))
		button.add_theme_stylebox_override("normal", HDTheme.button_style(button == %ShopButton))
		button.add_theme_stylebox_override("hover", HDTheme.button_style(button == %ShopButton))
		button.add_theme_stylebox_override("pressed", HDTheme.button_style(button == %ShopButton))


func _rebuild() -> void:
	var player: Dictionary = ProgressionManager.get_player_data()
	var progress: Dictionary = ProgressionManager.get_current_section_progress()
	%SummaryLabel.text = "LEVEL %d  •  XP %d / %d  •  VIBEZ %d" % [
		int(player.get("level", 1)),
		int(player.get("xp", 0)),
		ProgressionManager.xp_required_for_next_level(),
		int(player.get("currency", 0)),
	]
	if progress.is_empty():
		%ProgressLabel.text = "ALL EMS LOADOUTS AVAILABLE  •  Every song remains playable."
	else:
		%ProgressLabel.text = "CURRENT %s  •  %d / %d CLEARS TO NEXT SECTION  •  ALL EMS LOADOUTS AVAILABLE" % [
			ProgressionManager.get_section_display_name(int(progress.get("section_id", 1))),
			int(progress.get("clears", 0)),
			int(progress.get("required", 2)),
		]
	for child in %SectionsVBox.get_children():
		child.queue_free()
	for section in ContentRegistry.get_progression_sections():
		%SectionsVBox.add_child(_build_section_card(section))
	call_deferred("_refresh_menu_navigation")


func _build_section_card(section: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", HDTheme.card_style())
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)
	var header := Label.new()
	var section_id: int = int(section.get("id", 0))
	var unlocked: bool = section_id <= int(ProgressionManager.get_player_data().get("unlocked_sections", 1))
	header.text = "%s  •  %s" % [ProgressionManager.get_section_display_name(section_id), "REACHED" if unlocked else "UPCOMING"]
	HDTheme.apply_label(header, "section_title", HDTheme.CYAN if unlocked else HDTheme.TERTIARY)
	vbox.add_child(header)
	var meta := Label.new()
	meta.text = "PRO NOTE COUNT %d-%d  •  %d / %d SECTION CLEARS" % [
		int(section.get("min_note_count", 0)),
		int(section.get("max_note_count", 0)),
		min(int(ProgressionManager.get_current_section_progress().get("clears", 0)), int(section.get("unlock_requirement", 2))) if unlocked and section_id == int(ProgressionManager.get_current_section_progress().get("section_id", -1)) else int(section.get("unlock_requirement", 2)) if unlocked else 0,
		int(section.get("unlock_requirement", 2)),
	]
	HDTheme.apply_label(meta, "supporting", HDTheme.SECONDARY)
	vbox.add_child(meta)
	for song_id in _string_array(section.get("songs", [])):
		vbox.add_child(_build_song_row(song_id))
	return panel


func _build_song_row(song_id: String) -> PanelContainer:
	var song: Dictionary = ContentRegistry.get_song(song_id)
	var unlocked := ProgressionManager.is_song_unlocked(song_id)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", HDTheme.song_card_style(HDTheme.CYAN if unlocked else HDTheme.TERTIARY, false))
	panel.modulate = Color.WHITE if unlocked else Color(0.70, 0.70, 0.70, 0.55)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	margin.add_child(row)
	var jacket := TextureRect.new()
	jacket.custom_minimum_size = Vector2(52, 52)
	jacket.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	jacket.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	jacket.texture = SongJacketService.texture_for_song(song)
	row.add_child(jacket)
	var label := Label.new()
	var best: Dictionary = ProfileStore.get_best_score_for_song(song_id)
	label.text = "%s  •  %s" % [
		str(song.get("display_name", song_id)),
		"BEST %s" % best.get("score", 0) if not best.is_empty() else "LOCKED" if not unlocked else "BEST --",
	]
	HDTheme.apply_label(label, "body", HDTheme.primary_text() if unlocked else HDTheme.TERTIARY)
	row.add_child(label)
	return panel


func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for item in value:
			result.append(str(item))
	return result


func _on_back_button_pressed() -> void:
	back_requested.emit()


func _on_shop_button_pressed() -> void:
	open_shop_requested.emit()


func _apply_mobile_scroll_buttons() -> void:
	if not AppState.is_mobile_platform():
		return
	for button in [_back_button, %ShopButton, %BackActionButton]:
		button.set_script(MobileScrollButtonScript)


func _refresh_menu_navigation() -> void:
	if _menu_navigator != null:
		_menu_navigator.refresh_focusables()
