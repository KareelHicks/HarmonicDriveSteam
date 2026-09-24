extends Control

const HDTheme = preload("res://scripts/ui/HDTheme.gd")
const ChartLoader = preload("res://scripts/gameplay/ChartLoader.gd")
const LaneCountResolver = preload("res://scripts/songs/LaneCountResolver.gd")
const HDNoteVisual = preload("res://scripts/gameplay/HDNoteVisual.gd")
const GameModeConfig = preload("res://scripts/gameplay/GameModeConfig.gd")
const MenuNavigator = preload("res://scripts/ui/MenuNavigator.gd")

signal back_requested

const DIFFICULTY_ORDER := ["Easy", "Medium", "Hard", "Expert", "Professional"]

var _song_id := ""
var _song: Dictionary = {}
var _mode_id := GameModeConfig.DEFAULT_MODE
var _difficulty := "Medium"
var _menu_navigator: MenuNavigator


func _ready() -> void:
	_menu_navigator = MenuNavigator.install(self, Callable(self, "_on_back_button_pressed"))
	_apply_layout()
	get_viewport().size_changed.connect(_apply_layout)


func configure(song_id: String) -> void:
	_song_id = song_id
	_song = ContentRegistry.get_song(song_id)
	var modes: Array[String] = ContentRegistry.get_supported_modes(_song)
	_mode_id = modes[0] if not modes.is_empty() else GameModeConfig.DEFAULT_MODE
	var difficulties: Array[String] = ContentRegistry.get_supported_difficulties(_song, _mode_id)
	_difficulty = "Medium" if difficulties.has("Medium") else (difficulties[0] if not difficulties.is_empty() else "Medium")
	_rebuild_mode_picker()
	_rebuild_difficulty_picker()
	_rebuild_preview()


func _apply_layout() -> void:
	var size: Vector2 = get_viewport_rect().size
	var metrics: Dictionary = HDTheme.overlay_metrics(size)
	%Background.color = HDTheme.BG
	%Panel.add_theme_stylebox_override("panel", HDTheme.overlay_panel_style())
	%Panel.custom_minimum_size = Vector2(minf(size.x - 28.0, metrics["panel_width"] * 1.35), minf(size.y - 28.0, metrics["panel_height"] * 1.22))
	HDTheme.apply_label(%BackLabel, "caption", HDTheme.SECONDARY)
	%BackLabel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	HDTheme.apply_back_button($BackButton, %BackLabel)
	%BackButton.z_index = 20
	HDTheme.apply_label(%TitleLabel, "screen_title", HDTheme.CYAN, true)
	HDTheme.apply_label(%SubtitleLabel, "body", HDTheme.SECONDARY, true)
	HDTheme.apply_label(%ModeLabel, "caption", HDTheme.TERTIARY)
	HDTheme.apply_label(%DifficultyLabel, "caption", HDTheme.TERTIARY)
	%PreviewFrame.add_theme_stylebox_override("panel", HDTheme.card_style())
	%PreviewFrame.custom_minimum_size.y = minf(size.y * 0.58, 760.0)
	%ModeButtons.add_theme_constant_override("separation", 10)
	%DifficultyButtons.add_theme_constant_override("separation", 10)
	%PreviewContent.custom_minimum_size.x = maxf(360.0, %PreviewScroll.size.x - 18.0)
	_layout_preview_stage()


func _rebuild_mode_picker() -> void:
	for child in %ModeButtons.get_children():
		child.queue_free()
	for mode in ContentRegistry.get_supported_modes(_song):
		var button := Button.new()
		button.text = GameModeConfig.get_short_label(mode)
		_style_filter_button(button, mode == _mode_id)
		button.pressed.connect(func() -> void:
			_mode_id = mode
			var difficulties: Array[String] = ContentRegistry.get_supported_difficulties(_song, _mode_id)
			if not difficulties.has(_difficulty):
				_difficulty = difficulties[0] if not difficulties.is_empty() else "Medium"
			_rebuild_mode_picker()
			_rebuild_difficulty_picker()
			_rebuild_preview()
		)
		%ModeButtons.add_child(button)
	call_deferred("_refresh_menu_navigation")


func _rebuild_difficulty_picker() -> void:
	for child in %DifficultyButtons.get_children():
		child.queue_free()
	var supported: Array[String] = ContentRegistry.get_supported_difficulties(_song, _mode_id)
	for difficulty_name in DIFFICULTY_ORDER:
		if not supported.has(difficulty_name):
			continue
		var button := Button.new()
		button.text = difficulty_name.to_upper()
		_style_filter_button(button, difficulty_name == _difficulty)
		button.pressed.connect(func() -> void:
			_difficulty = difficulty_name
			_rebuild_difficulty_picker()
			_rebuild_preview()
		)
		%DifficultyButtons.add_child(button)
	call_deferred("_refresh_menu_navigation")


func _style_filter_button(button: Button, active: bool) -> void:
	var size: Vector2 = get_viewport_rect().size
	button.custom_minimum_size = Vector2(0.0, 42.0)
	button.add_theme_stylebox_override("normal", HDTheme.button_style(active))
	button.add_theme_stylebox_override("hover", HDTheme.button_style(active))
	button.add_theme_stylebox_override("pressed", HDTheme.button_style(active))
	button.add_theme_font_size_override("font_size", HDTheme.text_size("caption", size))


func _rebuild_preview() -> void:
	if _song.is_empty():
		return
	%TitleLabel.text = str(_song.get("display_name", "TRACK CHART"))
	%SubtitleLabel.text = "%s  •  %s" % [str(_song.get("artist", "")), str(_song.get("bpm_text", "-- BPM"))]
	for child in %PreviewContent.get_children():
		child.queue_free()
	var chart_path: String = ContentRegistry.get_chart_path(_song, _difficulty, _mode_id)
	var chart: Dictionary = ChartLoader.load_chart(chart_path)
	var lane_count := LaneCountResolver.resolve_chart_lane_count(chart, _song)
	var notes: Array = chart.get("notes", []) as Array
	if notes.is_empty():
		return

	var stage_rect: Rect2 = _preview_stage_rect()
	var lane_gap: float = 18.0
	var lane_width: float = (stage_rect.size.x - lane_gap * float(lane_count - 1)) / float(lane_count)
	var note_width: float = lane_width * 0.82
	var note_height: float = 36.0
	var pixels_per_second: float = 150.0 if AppState.is_mobile_platform() else 128.0
	var max_time: float = 0.0
	for note_variant in notes:
		var note: Dictionary = note_variant as Dictionary
		var note_time: float = float(note.get("time", 0.0))
		var duration: float = float(note.get("duration", 0.0))
		max_time = maxf(max_time, note_time + duration)
	var content_height: float = maxf(stage_rect.position.y + 80.0 + max_time * pixels_per_second, %PreviewScroll.size.y + 40.0)
	%PreviewContent.custom_minimum_size = Vector2(stage_rect.position.x * 2.0 + stage_rect.size.x, content_height)
	_draw_preview_background(stage_rect, content_height, lane_gap, lane_width, lane_count)

	for note_variant in notes:
		var note: Dictionary = note_variant as Dictionary
		var lane: int = clampi(int(note.get("lane", 0)), 0, lane_count - 1)
		var note_time: float = float(note.get("time", 0.0))
		var duration: float = float(note.get("duration", 0.0))
		var visual := HDNoteVisual.new()
		visual.setup(lane, Vector2(note_width, note_height), duration)
		visual.position = Vector2(
			stage_rect.position.x + float(lane) * (lane_width + lane_gap) + (lane_width - note_width) * 0.5,
			stage_rect.position.y + note_time * pixels_per_second
		)
		if duration > 0.0:
			visual.update_sustain(maxf(duration * pixels_per_second, 12.0))
		%PreviewContent.add_child(visual)


func _draw_preview_background(stage_rect: Rect2, content_height: float, lane_gap: float, lane_width: float, lane_count: int) -> void:
	for lane in lane_count:
		var lane_color: Color = HDTheme.LANE_COLORS[lane % HDTheme.LANE_COLORS.size()]
		var panel := PanelContainer.new()
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.position = Vector2(stage_rect.position.x + float(lane) * (lane_width + lane_gap), 0.0)
		panel.size = Vector2(lane_width, content_height)
		var style := StyleBoxFlat.new()
		style.bg_color = Color(lane_color.r, lane_color.g, lane_color.b, 0.07)
		style.border_color = Color(lane_color.r, lane_color.g, lane_color.b, 0.12)
		style.border_width_left = 1
		style.border_width_right = 1
		style.corner_radius_top_left = 22
		style.corner_radius_top_right = 22
		style.corner_radius_bottom_left = 22
		style.corner_radius_bottom_right = 22
		panel.add_theme_stylebox_override("panel", style)
		%PreviewContent.add_child(panel)
	for index in range(0, int(content_height), 120):
		var grid := ColorRect.new()
		grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
		grid.color = Color(HDTheme.CYAN.r, HDTheme.CYAN.g, HDTheme.CYAN.b, 0.10)
		grid.position = Vector2(stage_rect.position.x, float(index))
		grid.size = Vector2(stage_rect.size.x, 1.0)
		%PreviewContent.add_child(grid)


func _preview_stage_rect() -> Rect2:
	var width: float = minf(%PreviewScroll.size.x - 36.0, 540.0)
	var left: float = (%PreviewScroll.size.x - width) * 0.5
	return Rect2(left, 16.0, width, maxf(240.0, %PreviewScroll.size.y - 32.0))


func _layout_preview_stage() -> void:
	if not is_instance_valid(%PreviewScroll):
		return
	if _song.is_empty():
		return
	call_deferred("_rebuild_preview")


func _on_back_button_pressed() -> void:
	back_requested.emit()


func _refresh_menu_navigation() -> void:
	if _menu_navigator != null:
		_menu_navigator.refresh_focusables()
