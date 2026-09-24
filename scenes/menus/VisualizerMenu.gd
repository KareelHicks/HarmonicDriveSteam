extends Control

const HDTheme = preload("res://scripts/ui/HDTheme.gd")
const HDSongCarousel = preload("res://scripts/ui/HDSongCarousel.gd")
const HDUIMotion = preload("res://scripts/ui/HDUIMotion.gd")
const MenuNavigator = preload("res://scripts/ui/MenuNavigator.gd")

signal back_requested
signal shuffle_requested(reactive_mode: String)
signal song_requested(song_entry: Dictionary, reactive_mode: String)

var _all_songs: Array[Dictionary] = []
var _songs: Array[Dictionary] = []
var _selected_song: Dictionary = {}
var _carousel: HDSongCarousel
var _menu_navigator: MenuNavigator
var _launching := false
var _pending_launch_kind := ""
var _pending_song: Dictionary = {}


func _ready() -> void:
	_menu_navigator = MenuNavigator.install(self, Callable(self, "_on_back_button_pressed"))
	_all_songs = AppState.get_visualizer_songs()
	_songs = _all_songs.duplicate(true)
	%Background.color = HDTheme.BG
	_build_carousel()
	_apply_style()
	_select_initial_song()
	_refresh_selected_copy()
	_preview_selected_song()
	get_viewport().size_changed.connect(_apply_style)


func _build_carousel() -> void:
	_carousel = HDSongCarousel.new()
	_carousel.name = "SongCarousel"
	%CarouselHolder.add_child(_carousel)
	_carousel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_carousel.song_changed.connect(_on_song_changed)
	_carousel.song_activated.connect(_launch_song)
	_carousel.configure(
		_songs,
		ProfileStore.get_visualizer_selected_song_id(),
		{
			"best": Callable(self, "_carousel_action_label"),
			"difficulty": Callable(self, "_carousel_instruction_label"),
			"badge": Callable(self, "_carousel_badge_label"),
		}
	)


func _apply_style() -> void:
	var viewport_size := get_viewport_rect().size
	var metrics := HDTheme.overlay_metrics(viewport_size)
	var compact := viewport_size.x < 700.0
	HDTheme.apply_back_button(%BackButton, %BackLabel)
	%BackButton.custom_minimum_size = Vector2(138, 50)
	HDTheme.apply_label(%TitleLabel, "screen_title", HDTheme.CYAN, true)
	HDTheme.apply_label(%SubtitleLabel, "body", HDTheme.SECONDARY, true)
	HDTheme.apply_label(%SelectedHintLabel, "supporting", HDTheme.TERTIARY, true)
	%SearchField.custom_minimum_size = Vector2(0, 42)
	%SearchField.placeholder_text = "Search Visualizer songs"
	%SearchField.add_theme_stylebox_override("normal", HDTheme.dialog_field_style(false))
	%SearchField.add_theme_stylebox_override("focus", HDTheme.dialog_field_style(true))
	%SearchField.add_theme_color_override("font_color", HDTheme.primary_text())
	%SearchField.add_theme_color_override("font_placeholder_color", HDTheme.TERTIARY)
	%SearchField.add_theme_color_override("caret_color", HDTheme.CYAN)
	%SearchField.add_theme_color_override("selection_color", HDTheme.CYAN * Color(1, 1, 1, 0.28))
	%SearchField.add_theme_font_size_override("font_size", HDTheme.text_size("caption", viewport_size))
	HDTheme.apply_label(%ReactiveModeTitle, "section", HDTheme.CYAN, true)
	HDTheme.apply_label(%ReactiveModeDescription, "body", HDTheme.SECONDARY, true)
	%Divider.color = HDTheme.CYAN * Color(1, 1, 1, 0.30)
	%ReactiveModeOverlay.color = Color(0.0, 0.0, 0.0, 0.78)
	%ReactiveModePanel.add_theme_stylebox_override("panel", HDTheme.card_style())
	%ReactiveModePanel.custom_minimum_size.x = minf(500.0, maxf(240.0, viewport_size.x - 48.0))
	$SafeMargin/RootVBox/Header.custom_minimum_size.y = 156.0 if compact else 108.0
	%TitleLabel.offset_left = 0.0 if compact else 160.0
	%TitleLabel.offset_top = 56.0 if compact else 0.0
	%TitleLabel.offset_right = 0.0 if compact else -160.0
	%TitleLabel.offset_bottom = 98.0 if compact else 48.0
	%SubtitleLabel.offset_left = 8.0 if compact else 150.0
	%SubtitleLabel.offset_top = 100.0 if compact else 50.0
	%SubtitleLabel.offset_right = -8.0 if compact else -150.0
	%SubtitleLabel.offset_bottom = 154.0 if compact else 84.0
	var button_width := minf(360.0, maxf(120.0, (viewport_size.x - 80.0) * 0.5))
	for button in [%ShuffleButton, %StartSelectedButton]:
		button.custom_minimum_size = Vector2(button_width, float(metrics["button_height"]))
		button.add_theme_stylebox_override("normal", HDTheme.button_style(button == %ShuffleButton))
		button.add_theme_stylebox_override("hover", HDTheme.button_style(button == %ShuffleButton))
		button.add_theme_stylebox_override("pressed", HDTheme.button_style(button == %ShuffleButton))
		button.add_theme_stylebox_override("focus", HDTheme.button_style(button == %ShuffleButton))
		button.add_theme_font_size_override("font_size", HDTheme.text_size("button_secondary", viewport_size))
		HDUIMotion.attach_button(button)
	for button in [%PlayerReactiveButton, %ChartReactiveButton, %CancelReactiveButton]:
		button.custom_minimum_size = Vector2(minf(420.0, maxf(160.0, viewport_size.x - 96.0)), float(metrics["button_height"]))
		var primary: bool = button == %PlayerReactiveButton
		button.add_theme_stylebox_override("normal", HDTheme.button_style(primary))
		button.add_theme_stylebox_override("hover", HDTheme.button_style(primary))
		button.add_theme_stylebox_override("pressed", HDTheme.button_style(primary))
		button.add_theme_stylebox_override("focus", HDTheme.button_style(primary))
		button.add_theme_font_size_override("font_size", HDTheme.text_size("button_secondary", viewport_size))
		HDUIMotion.attach_button(button)
	%ShuffleButton.disabled = _all_songs.is_empty()
	%StartSelectedButton.disabled = _selected_song.is_empty()


func _select_initial_song() -> void:
	_selected_song = _carousel.get_selected_song()
	if _selected_song.is_empty() and not _songs.is_empty():
		_selected_song = _songs[0].duplicate(true)
		_carousel.select_song_id(str(_selected_song.get("id", "")), false)


func _on_song_changed(song: Dictionary) -> void:
	_selected_song = song.duplicate(true)
	ProfileStore.set_visualizer_selected_song_id(str(_selected_song.get("id", "")))
	_refresh_selected_copy()
	_preview_selected_song()


func _refresh_selected_copy() -> void:
	if _selected_song.is_empty():
		%SelectedHintLabel.text = "No songs match your search." if not %SearchField.text.strip_edges().is_empty() else "No playable songs with audio are available."
		%StartSelectedButton.disabled = true
		return
	%SelectedHintLabel.text = "START WITH %s, THEN CONTINUE IN RANDOM ORDER" % str(_selected_song.get("display_name", "SELECTED SONG")).to_upper()
	%StartSelectedButton.disabled = false


func _preview_selected_song() -> void:
	if _selected_song.is_empty():
		MenuAudio.stop()
		return
	MenuAudio.play_song_preview(str(_selected_song.get("id", "")))


func _on_shuffle_button_pressed() -> void:
	if _launching or _all_songs.is_empty():
		return
	_prompt_for_reactive_mode("shuffle")


func _on_start_selected_button_pressed() -> void:
	_launch_song(_selected_song)


func _launch_song(song: Dictionary) -> void:
	if _launching or song.is_empty():
		return
	ProfileStore.set_visualizer_selected_song_id(str(song.get("id", "")))
	_prompt_for_reactive_mode("song", song)


func _on_search_field_text_changed(_new_text: String) -> void:
	var preserve_focus: bool = %SearchField.has_focus()
	var preferred_song_id: String = str(_selected_song.get("id", ProfileStore.get_visualizer_selected_song_id()))
	_apply_song_filter()
	_carousel.configure(
		_songs,
		preferred_song_id,
		{
			"best": Callable(self, "_carousel_action_label"),
			"difficulty": Callable(self, "_carousel_instruction_label"),
			"badge": Callable(self, "_carousel_badge_label"),
		}
	)
	_select_initial_song()
	if not _selected_song.is_empty():
		ProfileStore.set_visualizer_selected_song_id(str(_selected_song.get("id", "")))
	_refresh_selected_copy()
	_preview_selected_song()
	if preserve_focus:
		call_deferred("_restore_search_focus")
	if _menu_navigator != null:
		_menu_navigator.call_deferred("refresh_focusables")


func _apply_song_filter() -> void:
	var query: String = %SearchField.text.strip_edges().to_lower()
	if query.is_empty():
		_songs = _all_songs.duplicate(true)
		return
	_songs.clear()
	for song in _all_songs:
		var haystack: String = "%s %s %s %s" % [
			str(song.get("display_name", "")),
			str(song.get("artist", "")),
			str(song.get("id", "")),
			str(song.get("title", "")),
		]
		if haystack.to_lower().contains(query):
			_songs.append(song.duplicate(true))


func _restore_search_focus() -> void:
	%SearchField.grab_focus()
	%SearchField.caret_column = %SearchField.text.length()


func _on_search_field_text_submitted(_text: String) -> void:
	%SearchField.release_focus()
	if _carousel != null and not _songs.is_empty():
		_carousel.grab_focus()


func _prompt_for_reactive_mode(launch_kind: String, song: Dictionary = {}) -> void:
	_pending_launch_kind = launch_kind
	_pending_song = song.duplicate(true)
	%ReactiveModeOverlay.visible = true
	for button in [%PlayerReactiveButton, %ChartReactiveButton, %CancelReactiveButton]:
		button.focus_mode = Control.FOCUS_ALL
	%PlayerReactiveButton.grab_focus()


func _on_player_reactive_button_pressed() -> void:
	_launch_pending_selection(AppState.VISUALIZER_REACTIVE_PLAYER)


func _on_chart_reactive_button_pressed() -> void:
	_launch_pending_selection(AppState.VISUALIZER_REACTIVE_CHART)


func _launch_pending_selection(reactive_mode: String) -> void:
	if _launching or _pending_launch_kind.is_empty():
		return
	_launching = true
	%ReactiveModeOverlay.visible = false
	MenuAudio.stop()
	if _pending_launch_kind == "shuffle":
		shuffle_requested.emit(reactive_mode)
	else:
		song_requested.emit(_pending_song.duplicate(true), reactive_mode)


func _on_cancel_reactive_button_pressed() -> void:
	_pending_launch_kind = ""
	_pending_song.clear()
	%ReactiveModeOverlay.visible = false
	if _menu_navigator != null and _menu_navigator.uses_controller_focus():
		_menu_navigator.refresh_focusables()


func is_menu_focusable_control(control: Control) -> bool:
	var prompt_control := %ReactiveModeOverlay.is_ancestor_of(control)
	return prompt_control if %ReactiveModeOverlay.visible else not prompt_control


func _on_back_button_pressed() -> void:
	if _launching:
		return
	if %ReactiveModeOverlay.visible:
		_on_cancel_reactive_button_pressed()
		return
	_launching = true
	back_requested.emit()


func _unhandled_input(event: InputEvent) -> void:
	if _launching or _carousel == null or event is not InputEventKey:
		return
	if %ReactiveModeOverlay.visible:
		return
	if %SearchField.has_focus():
		return
	if event.is_action_pressed("ui_left"):
		_carousel.move(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		_carousel.move(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_launch_song(_carousel.get_selected_song())
		get_viewport().set_input_as_handled()


func _carousel_action_label(_song: Dictionary) -> String:
	return "VISUALIZER READY"


func _carousel_instruction_label(_song: Dictionary) -> String:
	return "PRESS ENTER OR START SELECTED SONG"


func _carousel_badge_label(_song: Dictionary) -> String:
	return "PLAYER OR CHART REACTIVE"
