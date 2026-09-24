extends Control

const HDTheme = preload("res://scripts/ui/HDTheme.gd")
const HDListRowScene = preload("res://scenes/common/HDListRow.tscn")
const GameModeConfig = preload("res://scripts/gameplay/GameModeConfig.gd")
const MenuNavigator = preload("res://scripts/ui/MenuNavigator.gd")
const HDSongCarousel = preload("res://scripts/ui/HDSongCarousel.gd")
const SongJacketService = preload("res://scripts/ui/SongJacketService.gd")
const HDUIMotion = preload("res://scripts/ui/HDUIMotion.gd")
const DifficultyManager := preload("res://scripts/editor/DifficultyManager.gd")
const ChartMetadataResolver := preload("res://scripts/songs/ChartMetadataResolver.gd")

signal back_requested
signal start_requested(song_entry: Dictionary, difficulty: String, mode: String)
signal loadout_requested

var _all_songs: Array[Dictionary] = []
var _songs: Array[Dictionary] = []
var _selected_song: Dictionary = {}
var _pending_mode := GameModeConfig.DEFAULT_MODE
var _menu_navigator: MenuNavigator
var _song_rows_by_id: Dictionary = {}
var _launching_song := false
var _is_exiting := false
var _carousel: HDSongCarousel
var _last_analog_carousel_ms := 0
var _practice_selection_mode := false
const _MODAL_FOCUS_META_KEY := "hd_modal_prev_focus_mode"


func _ready() -> void:
	_practice_selection_mode = AppState.practice_active
	_menu_navigator = MenuNavigator.install(self, Callable(self, "_on_back_button_pressed"))
	_all_songs = ContentRegistry.get_progression_ordered_songs()
	_songs = _all_songs.duplicate(true)
	%Background.color = HDTheme.BG
	_apply_header()
	_build_rows()
	_select_initial_song()
	_refresh_status()
	_hide_selection_overlay()
	ProgressionManager.progression_changed.connect(_on_progression_changed)
	call_deferred("_restore_selected_row_state")


func _apply_header() -> void:
	var size := get_viewport_rect().size
	var metrics := HDTheme.list_metrics(size)
	HDTheme.apply_label(%BackLabel, "caption", HDTheme.SECONDARY, false)
	%BackLabel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	HDTheme.apply_back_button(%BackButton, %BackLabel)
	HDTheme.apply_label(%TitleLabel, "screen_title", HDTheme.CYAN, true)
	HDTheme.apply_label(%SubtitleLabel, "caption", HDTheme.TERTIARY, true)
	HDTheme.apply_label(%StatusLabel, "body", HDTheme.SECONDARY, true)
	%SearchField.custom_minimum_size = Vector2(0, 42)
	%TitleLabel.text = "PRACTICE MODE — SELECT A TRACK" if _practice_selection_mode else "SELECT A TRACK"
	%SearchField.placeholder_text = "Search songs"
	%SubtitleLabel.text = _subtitle_text()
	%Divider.color = HDTheme.CYAN * Color(1, 1, 1, 0.30)
	%BackButton.custom_minimum_size = Vector2(132, 48)
	HDUIMotion.attach_button(%BackButton)
	%LoadoutButton.custom_minimum_size = Vector2(168, 48)
	%LoadoutButton.add_theme_stylebox_override("normal", HDTheme.button_style(false))
	%LoadoutButton.add_theme_stylebox_override("hover", HDTheme.button_style(false))
	%LoadoutButton.add_theme_stylebox_override("pressed", HDTheme.button_style(false))
	%LoadoutButton.add_theme_font_size_override("font_size", HDTheme.text_size("button_secondary", size))
	HDUIMotion.attach_button(%LoadoutButton)
	%RowsVBox.add_theme_constant_override("separation", metrics["row_spacing"])
	%ListScroll.visible = false
	%DetailPanel.visible = false
	_ensure_carousel()
	%SelectionPanel.custom_minimum_size = Vector2(HDTheme.overlay_metrics(size)["panel_width"] * 0.82, HDTheme.overlay_metrics(size)["panel_height"] * 0.72)
	%SelectionButtons.add_theme_constant_override("separation", 14)
	HDTheme.apply_label(%SelectionTitleLabel, "screen_title", HDTheme.CYAN, true)
	HDTheme.apply_label(%SelectionSubtitleLabel, "body", HDTheme.SECONDARY, true)
	for button in [%SelectionCancelButton]:
		button.custom_minimum_size = Vector2(0, HDTheme.overlay_metrics(size)["button_height"])
		button.add_theme_stylebox_override("normal", HDTheme.button_style(false))
		button.add_theme_stylebox_override("hover", HDTheme.button_style(false))
		button.add_theme_stylebox_override("pressed", HDTheme.button_style(false))
		button.add_theme_font_size_override("font_size", HDTheme.text_size("button_secondary", size))
		HDUIMotion.attach_button(button)
	%SelectionPanel.add_theme_stylebox_override("panel", HDTheme.overlay_panel_style())
	%OverlayDim.color = Color(0, 0, 0, 0.74)


func _build_rows() -> void:
	for child in %RowsVBox.get_children():
		child.queue_free()
	_song_rows_by_id.clear()
	_ensure_carousel()
	_apply_song_carousel_metadata(_songs)
	_carousel.configure(
		_songs,
		str(_selected_song.get("id", ProfileStore.get_selected_song_id())),
		{
			"best": Callable(self, "_carousel_best_label"),
			"badge": Callable(self, "_carousel_badge_label"),
			"difficulty": Callable(self, "_carousel_difficulty_label"),
		}
	)
	call_deferred("_refresh_menu_navigation")
	return
	var last_section_id := -1
	for index in _songs.size():
		var song: Dictionary = _songs[index]
		var song_id: String = str(song.get("id", ""))
		var section_meta: Dictionary = ProgressionManager.get_section_for_song(song_id)
		var section_id: int = int(section_meta.get("section_id", 1))
		if section_id != last_section_id:
			last_section_id = section_id
			%RowsVBox.add_child(_build_section_header(section_id))
		var row = HDListRowScene.instantiate()
		%RowsVBox.add_child(row)
		var subtitle := str(song.get("artist", "Unknown Artist"))
		var best_score: Dictionary = ProfileStore.get_best_score_for_song(str(song.get("id", "")))
		if not best_score.is_empty():
			subtitle += "\nBEST %s" % best_score.get("score", 0)
		var is_premium_song: bool = PremiumStore.is_premium_song(song_id)
		var is_progression_unlocked: bool = ProgressionManager.is_song_unlocked(song_id)
		var badge := ""
		if PremiumStore.is_android_store_enabled() and is_premium_song and not PremiumStore.is_song_playable(song_id):
			badge = "PREMIUM"
		elif not is_progression_unlocked:
			badge = "LOCKED"
		row.configure(
			str(song.get("display_name", "Unknown")),
			subtitle,
			_bpm_label(song),
			HDTheme.LANE_COLORS[index % HDTheme.LANE_COLORS.size()],
			badge,
			SongJacketService.texture_for_song(song)
		)
		row.activated.connect(_select_song.bind(song))
		row.focus_entered.connect(_on_song_row_focused.bind(song))
		_song_rows_by_id[song_id] = row
	call_deferred("_refresh_menu_navigation")


func _ensure_carousel() -> void:
	if _carousel != null and is_instance_valid(_carousel):
		return
	_carousel = HDSongCarousel.new()
	_carousel.name = "SongCarousel"
	%BodyHBox.add_child(_carousel)
	%BodyHBox.move_child(_carousel, 0)
	_carousel.song_changed.connect(_on_carousel_song_changed)
	_carousel.song_activated.connect(_select_song)


func _select_initial_song() -> void:
	if _songs.is_empty():
		return
	var preferred_song_id: String = ProfileStore.get_selected_song_id()
	if not preferred_song_id.is_empty():
		for song in _songs:
			if str(song.get("id", "")) == preferred_song_id:
				_selected_song = song
				_sync_carousel_to_selected()
				return
	for song in _songs:
		if is_song_available(str(song.get("id", ""))):
			_selected_song = song
			_sync_carousel_to_selected()
			return
	_selected_song = _songs[0]
	_sync_carousel_to_selected()


func _reset_list_to_top() -> void:
	if _carousel != null and not _songs.is_empty():
		_carousel.selected_index = 0
		_carousel.refresh()


func _select_song(song: Dictionary) -> void:
	_selected_song = song
	_sync_selected_song_preview()
	var song_id: String = str(song.get("id", ""))
	if PremiumStore.is_android_store_enabled() and PremiumStore.is_premium_song(song_id) and not PremiumStore.is_song_playable(song_id):
		%StatusLabel.text = PremiumStore.get_song_store_message(song_id)
		return
	_show_mode_selection()


func _refresh_details() -> void:
	_refresh_status()


func _refresh_status() -> void:
	%SubtitleLabel.text = _subtitle_text()
	if _practice_selection_mode:
		%StatusLabel.text = "Choose a song, mode, and difficulty. Practice runs are unranked and no-fail."
		return
	var progress: Dictionary = ProgressionManager.get_current_section_progress()
	if progress.is_empty():
		%StatusLabel.text = "ALL EMS LOADOUTS AVAILABLE  •  Every song is ready to play."
		return
	%StatusLabel.text = "%s  •  %d / %d CLEARS TO NEXT SECTION  •  All EMS Loadouts available." % [
		ProgressionManager.get_section_display_name(int(progress.get("section_id", 1))),
		int(progress.get("clears", 0)),
		int(progress.get("required", 2)),
	]
	%SubtitleLabel.text = "%d SONGS" % _songs.size()


func is_song_available(song_id: String) -> bool:
	if PremiumStore.is_android_store_enabled() and PremiumStore.is_premium_song(song_id):
		return PremiumStore.is_song_playable(song_id)
	return ProgressionManager.is_song_unlocked(song_id)


func _subtitle_text() -> String:
	return "%d SONGS" % _songs.size()


func _bpm_label(song: Dictionary) -> String:
	var bpm: float = float(song.get("bpm", 0.0))
	if bpm <= 0.0:
		return "-- BPM"
	if is_equal_approx(bpm, roundf(bpm)):
		return "%d BPM" % int(roundf(bpm))
	return "%.2f BPM" % bpm


func _build_section_header(section_id: int) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 76)
	panel.add_theme_stylebox_override("panel", HDTheme.card_style())
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	margin.add_child(vbox)
	var title := Label.new()
	var current_progress: Dictionary = ProgressionManager.get_current_section_progress()
	var is_current: bool = section_id == int(current_progress.get("section_id", -1))
	var unlocked: bool = section_id <= int(ProgressionManager.get_player_data().get("unlocked_sections", 1))
	title.text = "%s  •  %s" % [ProgressionManager.get_section_display_name(section_id), "REACHED" if unlocked else "UPCOMING"]
	HDTheme.apply_label(title, "section_title", HDTheme.CYAN if unlocked else HDTheme.TERTIARY)
	vbox.add_child(title)
	var subtitle := Label.new()
	if is_current:
		subtitle.text = "%d / %d CLEARS TO NEXT SECTION" % [int(current_progress.get("clears", 0)), int(current_progress.get("required", 2))]
	else:
		subtitle.text = "Every song and EMS Loadout is available; sections track completion progress."
	HDTheme.apply_label(subtitle, "supporting", HDTheme.SECONDARY)
	vbox.add_child(subtitle)
	return panel


func _hide_selection_overlay() -> void:
	%OverlayDim.visible = false
	%SelectionCenter.visible = false
	_set_modal_overlay_active(false)
	for child in %SelectionButtons.get_children():
		if child != %SelectionCancelButton:
			child.queue_free()
	if not _launching_song and not _is_exiting:
		call_deferred("_restore_selected_row_state")


func _show_mode_selection() -> void:
	if _selected_song.is_empty():
		return
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
	if _selected_song.is_empty():
		return
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
	%OverlayDim.mouse_filter = Control.MOUSE_FILTER_STOP
	%SelectionCenter.mouse_filter = Control.MOUSE_FILTER_STOP
	_set_modal_overlay_active(true)
	%SelectionTitleLabel.text = title
	%SelectionSubtitleLabel.text = subtitle
	for child in %SelectionButtons.get_children():
		if child != %SelectionCancelButton:
			child.queue_free()
	for option in options:
		var button := Button.new()
		button.text = label_builder.call(option) if label_builder.is_valid() else str(option)
		button.focus_mode = Control.FOCUS_ALL
		button.custom_minimum_size = Vector2(0, HDTheme.overlay_metrics(get_viewport_rect().size)["button_height"])
		var enabled: bool = enabled_builder.call(option) if enabled_builder.is_valid() else true
		button.disabled = not enabled
		button.add_theme_stylebox_override("normal", HDTheme.button_style(enabled))
		button.add_theme_stylebox_override("hover", HDTheme.button_style(enabled))
		button.add_theme_stylebox_override("pressed", HDTheme.button_style(enabled))
		button.add_theme_font_size_override("font_size", HDTheme.text_size("button_secondary", get_viewport_rect().size))
		HDUIMotion.attach_button(button)
		if enabled:
			button.pressed.connect(func() -> void:
				callback.call(option)
			)
		%SelectionButtons.add_child(button)
		%SelectionButtons.move_child(button, %SelectionButtons.get_child_count() - 2)
	_refresh_menu_navigation()
	call_deferred("_focus_initial_selection_button")
	call_deferred("_refresh_menu_navigation")


func _set_modal_overlay_active(active: bool) -> void:
	# When the overlay is open, prevent default Godot focus navigation from moving
	# to background controls (which can happen even if MenuNavigator filters focusables).
	var controls := _collect_all_controls(self)
	if active:
		for control in controls:
			if _is_overlay_control(control):
				continue
			if not control.has_meta(_MODAL_FOCUS_META_KEY):
				control.set_meta(_MODAL_FOCUS_META_KEY, int(control.focus_mode))
			control.focus_mode = Control.FOCUS_NONE
		return
	for control in controls:
		if not control.has_meta(_MODAL_FOCUS_META_KEY):
			continue
		control.focus_mode = int(control.get_meta(_MODAL_FOCUS_META_KEY))
		control.remove_meta(_MODAL_FOCUS_META_KEY)


func _collect_all_controls(node: Node) -> Array[Control]:
	var result: Array[Control] = []
	for child in node.get_children():
		if child is Control:
			result.append(child as Control)
		result.append_array(_collect_all_controls(child))
	return result


func _on_back_button_pressed() -> void:
	_is_exiting = true
	_hide_selection_overlay()
	back_requested.emit()


func _on_loadout_button_pressed() -> void:
	_is_exiting = true
	_hide_selection_overlay()
	loadout_requested.emit()


func _on_start_button_pressed() -> void:
	pass


func _on_unlock_button_pressed() -> void:
	pass


func _on_difficulty_option_item_selected(_index: int) -> void:
	pass


func _on_selection_cancel_button_pressed() -> void:
	_launching_song = false
	_hide_selection_overlay()


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
	_launching_song = true
	_is_exiting = true
	_hide_selection_overlay()
	MenuAudio.stop()
	start_requested.emit(_song_entry_for_selected_difficulty(_selected_song, difficulty), difficulty, _pending_mode)


func _song_entry_for_selected_difficulty(song: Dictionary, difficulty: String) -> Dictionary:
	var metadata := ChartMetadataResolver.metadata_for_song_entry(song, DifficultyManager.id_from_display(difficulty))
	return ChartMetadataResolver.apply_metadata_to_song_entry(song, metadata)


func _on_progression_changed() -> void:
	_all_songs = ContentRegistry.get_progression_ordered_songs()
	_apply_song_filter()
	_build_rows()
	_select_initial_song()
	_refresh_status()
	call_deferred("_restore_selected_row_state")


func _refresh_menu_navigation() -> void:
	if _menu_navigator != null:
		_menu_navigator.refresh_focusables()


func get_initial_menu_focus() -> Control:
	if _is_selection_overlay_visible():
		var overlay_button := _first_enabled_selection_button()
		if overlay_button != null:
			return overlay_button
	var selected_song_id: String = str(_selected_song.get("id", ""))
	if not selected_song_id.is_empty() and _carousel != null:
		return _carousel
	for song in _songs:
		var song_id: String = str(song.get("id", ""))
		if _song_rows_by_id.has(song_id):
			return _song_rows_by_id[song_id]
	return %BackButton


func is_menu_focusable_control(control: Control) -> bool:
	if control == null:
		return false
	if _is_selection_overlay_visible():
		return _is_overlay_focusable_control(control)
	if control == %SearchField:
		return false
	return not _is_overlay_control(control)


func _on_search_field_text_changed(_new_text: String) -> void:
	var should_preserve_focus: bool = %SearchField.has_focus()
	_apply_song_filter()
	_build_rows()
	_select_initial_song()
	_refresh_status()
	call_deferred("_sync_selected_song_preview")
	if should_preserve_focus:
		call_deferred("_restore_search_focus")


func _on_search_field_text_submitted(_text: String) -> void:
	%SearchField.release_focus()
	call_deferred("_refresh_menu_navigation")


func _apply_song_filter() -> void:
	var query: String = %SearchField.text.strip_edges().to_lower()
	if query.is_empty():
		_songs = _all_songs.duplicate(true)
		return
	_songs.clear()
	for song in _all_songs:
		var haystack := "%s %s %s %s %s %s" % [
			str(song.get("display_name", "")),
			str(song.get("artist", "")),
			str(song.get("id", "")),
			str(song.get("title", "")),
			str(song.get("chart_author", song.get("charter", ""))),
			str(song.get("source_label", "")),
		]
		if haystack.to_lower().contains(query):
			_songs.append(song)


func _restore_search_focus() -> void:
	%SearchField.grab_focus()
	%SearchField.caret_column = %SearchField.text.length()


func _is_selection_overlay_visible() -> bool:
	return %SelectionCenter.visible


func _first_enabled_selection_button() -> Control:
	for child in %SelectionButtons.get_children():
		if child is BaseButton and not (child as BaseButton).disabled and child.visible:
			return child as Control
	return null


func _focus_initial_selection_button() -> void:
	if not _is_selection_overlay_visible():
		return
	if _menu_navigator != null and not _menu_navigator.uses_controller_focus():
		return
	var initial_focus := _first_enabled_selection_button()
	if initial_focus == null:
		return
	initial_focus.pivot_offset = initial_focus.size * 0.5
	initial_focus.grab_focus()


func _is_overlay_focusable_control(control: Control) -> bool:
	if control == %SelectionCancelButton:
		return true
	var node: Node = control
	while node != null:
		if node == %SelectionCenter:
			return true
		if node == self:
			return false
		node = node.get_parent()
	return false


func _is_overlay_control(control: Control) -> bool:
	var node: Node = control
	while node != null:
		if node == %SelectionCenter or node == %OverlayDim:
			return true
		if node == self:
			return false
		node = node.get_parent()
	return false


func _restore_selected_row_state() -> void:
	if _is_exiting or not is_inside_tree():
		return
	_refresh_menu_navigation()
	await get_tree().process_frame
	if _is_exiting or not is_inside_tree():
		return
	_restore_selected_row_focus()
	_sync_selected_song_preview()


func _restore_selected_row_focus() -> void:
	if _is_exiting or not is_inside_tree():
		return
	if _menu_navigator != null and not _menu_navigator.uses_controller_focus():
		_sync_carousel_to_selected()
		return
	var song_id: String = str(_selected_song.get("id", ""))
	if not song_id.is_empty() and _carousel != null:
		_carousel.grab_focus()
		_sync_carousel_to_selected()
		return
	_refresh_menu_navigation()


func _restore_selected_row_scroll(row: Control) -> void:
	if row == null or not is_instance_valid(row) or _is_exiting:
		return
	await get_tree().process_frame
	if row == null or not is_instance_valid(row) or _is_exiting:
		return
	%ListScroll.ensure_control_visible(row)
	await get_tree().process_frame
	if row == null or not is_instance_valid(row) or _is_exiting:
		return
	_scroll_row_into_view(row)


func _on_song_row_focused(song: Dictionary) -> void:
	if _launching_song or _is_exiting:
		return
	_selected_song = song
	_sync_selected_song_preview()


func _on_carousel_song_changed(song: Dictionary) -> void:
	if _launching_song or _is_exiting:
		return
	_selected_song = song
	_sync_selected_song_preview()


func _sync_selected_song_preview() -> void:
	if _is_exiting or not is_inside_tree():
		return
	var song_id: String = str(_selected_song.get("id", ""))
	if song_id.is_empty():
		MenuAudio.stop()
		return
	MenuAudio.play_song_preview(song_id)


func _sync_carousel_to_selected() -> void:
	if _carousel == null or not is_instance_valid(_carousel):
		return
	var song_id := str(_selected_song.get("id", ""))
	if not song_id.is_empty():
		_carousel.select_song_id(song_id, false)


func _apply_song_carousel_metadata(song_entries: Array[Dictionary]) -> void:
	var note_counts: Array[int] = []
	for song in _all_songs:
		note_counts.append(int(song.get("professional_note_count", ProgressionManager.get_section_for_song(str(song.get("id", ""))).get("professional_note_count", 0))))
	note_counts.sort()
	for index in song_entries.size():
		var song := song_entries[index]
		var song_id := str(song.get("id", ""))
		var section_meta: Dictionary = ProgressionManager.get_section_for_song(song_id)
		var section_id := int(section_meta.get("section_id", 0))
		var note_count := int(song.get("professional_note_count", section_meta.get("professional_note_count", 0)))
		var rank := note_counts.find(note_count)
		var percentile := float(maxi(rank, 0)) / float(maxi(1, note_counts.size() - 1))
		song["section_id"] = section_id
		song["section_name"] = ProgressionManager.get_section_display_name(section_id)
		song["_difficulty_rating"] = clampi(1 + int(floor(percentile * 5.0)), 1, 5)
		song_entries[index] = song


func _carousel_best_label(song: Dictionary) -> String:
	var best_score: Dictionary = ProfileStore.get_best_score_for_song(str(song.get("id", "")))
	return "BEST %s" % best_score.get("score", 0) if not best_score.is_empty() else "BEST --"


func _carousel_badge_label(song: Dictionary) -> String:
	var song_id := str(song.get("id", ""))
	if PremiumStore.is_android_store_enabled() and PremiumStore.is_premium_song(song_id) and not PremiumStore.is_song_playable(song_id):
		return "PREMIUM"
	if not ProgressionManager.is_song_unlocked(song_id):
		return "LOCKED"
	return "READY"


func _carousel_difficulty_label(song: Dictionary) -> String:
	return "DIFFICULTY %d / 5" % int(song.get("_difficulty_rating", 1))


func _unhandled_input(event: InputEvent) -> void:
	if _is_selection_overlay_visible() or _launching_song or _is_exiting or _carousel == null:
		return
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if not key_event.pressed or key_event.echo:
			return
		if key_event.keycode == KEY_LEFT:
			_carousel.move(-1)
			get_viewport().set_input_as_handled()
		elif key_event.keycode == KEY_RIGHT:
			_carousel.move(1)
			get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton:
		var joy_button := event as InputEventJoypadButton
		if joy_button.pressed and joy_button.button_index == JOY_BUTTON_DPAD_LEFT:
			_carousel.move(-1)
			get_viewport().set_input_as_handled()
		elif joy_button.pressed and joy_button.button_index == JOY_BUTTON_DPAD_RIGHT:
			_carousel.move(1)
			get_viewport().set_input_as_handled()
	elif event is InputEventJoypadMotion:
		var joy_motion := event as InputEventJoypadMotion
		if joy_motion.axis != JOY_AXIS_LEFT_X or absf(joy_motion.axis_value) < 0.58:
			return
		var now := Time.get_ticks_msec()
		if now - _last_analog_carousel_ms < 220:
			return
		_last_analog_carousel_ms = now
		_carousel.move(1 if joy_motion.axis_value > 0.0 else -1)
		get_viewport().set_input_as_handled()


func _scroll_row_into_view(row: Control) -> void:
	if row == null or not is_instance_valid(row):
		return
	var viewport_height: float = %ListScroll.size.y
	var content_height: float = %RowsVBox.size.y
	var row_top: float = row.position.y
	var row_height: float = row.size.y
	var target_scroll: float = row_top - maxf(0.0, (viewport_height - row_height) * 0.5)
	var max_scroll: float = maxf(0.0, content_height - viewport_height)
	%ListScroll.scroll_vertical = int(clampf(target_scroll, 0.0, max_scroll))
