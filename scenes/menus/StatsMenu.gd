extends Control

const HDTheme = preload("res://scripts/ui/HDTheme.gd")
const MenuNavigator = preload("res://scripts/ui/MenuNavigator.gd")

signal back_requested

var _menu_navigator: MenuNavigator
@onready var _back_button: Button = $Center/Panel/Margin/VBox/BackButton


func _ready() -> void:
	_menu_navigator = MenuNavigator.install(self, Callable(self, "_on_back_button_pressed"))
	_back_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_back_button.move_to_front()
	_apply_layout()
	_rebuild()
	get_viewport().size_changed.connect(_apply_layout)


func _apply_layout() -> void:
	var size: Vector2 = get_viewport_rect().size
	var metrics: Dictionary = HDTheme.overlay_metrics(size)
	%Background.color = HDTheme.BG
	%Panel.add_theme_stylebox_override("panel", HDTheme.overlay_panel_style())
	%Panel.custom_minimum_size = Vector2(minf(size.x - 40.0, metrics["panel_width"] * 1.35), minf(size.y - 40.0, metrics["panel_height"] * 1.2))
	HDTheme.apply_label(%BackLabel, "caption", HDTheme.SECONDARY)
	%BackLabel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	HDTheme.apply_back_button(_back_button, %BackLabel)
	HDTheme.apply_label(%TitleLabel, "screen_title", HDTheme.CYAN, true)
	HDTheme.apply_label(%SummaryLabel, "body", HDTheme.SECONDARY, true)
	HDTheme.apply_label(%ProgressLabel, "supporting", HDTheme.TERTIARY, true)
	%CardsVBox.add_theme_constant_override("separation", 14)
	for button in [%BackActionButton]:
		button.custom_minimum_size.y = metrics["button_height"]
		button.add_theme_font_size_override("font_size", HDTheme.text_size("button_secondary", size))
		button.add_theme_stylebox_override("normal", HDTheme.button_style(false))
		button.add_theme_stylebox_override("hover", HDTheme.button_style(false))
		button.add_theme_stylebox_override("pressed", HDTheme.button_style(false))


func _rebuild() -> void:
	for child in %CardsVBox.get_children():
		child.queue_free()
	var snapshot: Dictionary = SteamAchievements.get_stats_snapshot()
	var achievement_ids := _string_array(snapshot.get("unlocked_achievement_ids", []))
	var total_achievements := SteamAchievements.ACHIEVEMENTS.size()
	%SummaryLabel.text = "STEAMWORKS  •  %s" % str(snapshot.get("steam_status", "Unavailable"))
	%ProgressLabel.text = "ACHIEVEMENTS %d / %d  •  CLOUD  •  %s" % [
		achievement_ids.size(),
		total_achievements,
		str(snapshot.get("cloud_status", "Unavailable"))
	]
	%CardsVBox.add_child(_build_stat_card(
		"SONG PROGRESS",
		[
			"UNIQUE SONGS COMPLETED  •  %d / 25 (Playlist Starter)" % int(snapshot.get("songs_completed", 0)),
			"BASE SONGS CLEARED  •  %d / %d (Tour Complete)" % [
				int(snapshot.get("base_songs_completed", 0)),
				int(snapshot.get("total_base_songs", 0)),
			],
			"TOTAL PLAYTIME  •  %.2f / 5.00 HOURS (Endless Drive)" % [float(snapshot.get("time_played_seconds", 0.0)) / 3600.0],
		]
	))
	var gameplay_stats: Dictionary = ProfileStore.get_gameplay_stats()
	%CardsVBox.add_child(_build_stat_card(
		"GAMEPLAY TOTALS",
		[
			"NOTES HIT  •  %d" % int(gameplay_stats.get("notes_hit", 0)),
			"NOTES MISSED  •  %d" % int(gameplay_stats.get("notes_missed", 0)),
			"TOTAL SONG COMPLETIONS  •  %d" % int(gameplay_stats.get("song_completions", 0)),
			"TOTAL SONG FAILURES  •  %d" % int(gameplay_stats.get("song_failures", 0)),
			"DRIVE CHAIN (FULL COMBO)  •  %d" % int(gameplay_stats.get("full_combos", 0)),
			"OVERDRIVE SYNC (ALL PERFECT)  •  %d" % int(gameplay_stats.get("all_perfects", 0)),
		]
	))
	%CardsVBox.add_child(_build_stat_card(
		"MULTIPLAYER PROGRESS",
		[
			"MATCHES COMPLETED  •  %d" % int(snapshot.get("multiplayer_matches_completed", 0)),
			"MATCHES WON  •  %d / 20 (Harmonic Winner)" % int(snapshot.get("multiplayer_matches_won", 0)),
			"FIRST JAM  •  %s" % ("DONE" if int(snapshot.get("multiplayer_matches_completed", 0)) >= 1 else "PENDING"),
			"I DID IT  •  %s" % ("DONE" if int(snapshot.get("multiplayer_matches_won", 0)) >= 1 else "PENDING"),
		]
	))
	achievement_ids.sort()
	var unlocked_lines: Array[String] = []
	if achievement_ids.is_empty():
		unlocked_lines.append("NONE YET")
	else:
		for achievement_id in achievement_ids:
			unlocked_lines.append(achievement_id)
	%CardsVBox.add_child(_build_stat_card(
		"UNLOCKED ACHIEVEMENTS",
		unlocked_lines
	))
	call_deferred("_refresh_menu_navigation")


func _build_stat_card(title: String, lines: Array[String]) -> PanelContainer:
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
	header.text = title
	HDTheme.apply_label(header, "section_title", HDTheme.CYAN)
	vbox.add_child(header)
	for line in lines:
		var row := Label.new()
		row.text = line
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		HDTheme.apply_label(row, "body", HDTheme.SECONDARY)
		vbox.add_child(row)
	return panel


func _on_back_button_pressed() -> void:
	back_requested.emit()


func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for item in value:
			result.append(str(item))
	return result


func _refresh_menu_navigation() -> void:
	if _menu_navigator != null:
		_menu_navigator.refresh_focusables()
