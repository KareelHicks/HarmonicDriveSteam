extends Control

const HDTheme = preload("res://scripts/ui/HDTheme.gd")
const GameModeConfig = preload("res://scripts/gameplay/GameModeConfig.gd")
const InertialScrollController = preload("res://scripts/ui/InertialScrollController.gd")
const MenuNavigator = preload("res://scripts/ui/MenuNavigator.gd")

signal back_requested

const DIFFICULTY_ORDER := ["Easy", "Medium", "Hard", "Expert", "Professional"]
const PLATFORM_BADGE_APPLE := "APPLE"
const PLATFORM_BADGE_ANDROID := "ANDROID"
const PLATFORM_BADGE_STEAM := "STEAM"
const PLATFORM_BADGE_GUEST := "GUEST"

@onready var _back_label: Label = %BackLabel
@onready var _title_label: Label = %TitleLabel
@onready var _artist_label: Label = %ArtistLabel
@onready var _status_label: Label = %StatusLabel
@onready var _difficulty_button: Button = %DifficultyButton
@onready var _mode_button: Button = %ModeButton
@onready var _source_button: Button = %SourceButton
@onready var _divider: ColorRect = %Divider
@onready var _list_scroll: ScrollContainer = %ListScroll
@onready var _rows_vbox: VBoxContainer = %RowsVBox

var _song_id := ""
var _song: Dictionary = {}
var _summary: Dictionary = {}
var _selected_difficulty := "Professional"
var _selected_mode := GameModeConfig.DEFAULT_MODE
var _selected_source := "railway"
var _entries: Array[Dictionary] = []
var _menu_navigator: MenuNavigator


func _ready() -> void:
	_menu_navigator = MenuNavigator.install(self, Callable(self, "_on_back_button_pressed"))
	InertialScrollController.install(_list_scroll, _rows_vbox)
	_apply_layout()
	get_viewport().size_changed.connect(_apply_layout)
	if AppState.identity_service != null:
		AppState.identity_service.auth_state_changed.connect(_on_auth_state_changed)
		AppState.identity_service.login_failed.connect(_on_identity_failed)
	if not _song_id.is_empty():
		_load_song()
	_refresh_labels()
	_build_rows()
	_attempt_load()


func configure(song_id: String, summary: Dictionary = {}) -> void:
	_song_id = song_id
	_summary = summary.duplicate(true)
	if is_inside_tree():
		_load_song()
		_refresh_labels()
		_attempt_load()


func _apply_layout() -> void:
	var size := get_viewport_rect().size
	%Background.color = HDTheme.BG
	HDTheme.apply_label(_back_label, "caption", HDTheme.SECONDARY, false)
	_back_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	HDTheme.apply_back_button($SafeMargin/VBox/BackButton, _back_label)
	HDTheme.apply_label(_title_label, "screen_title", HDTheme.CYAN, true)
	HDTheme.apply_label(_artist_label, "caption", HDTheme.TERTIARY, true)
	HDTheme.apply_label(_status_label, "body", HDTheme.SECONDARY, true)
	_divider.color = HDTheme.CYAN * Color(1, 1, 1, 0.30)
	for button in [_difficulty_button, _mode_button, _source_button]:
		button.custom_minimum_size.y = 58
		button.add_theme_stylebox_override("normal", HDTheme.button_style(false))
		button.add_theme_stylebox_override("hover", HDTheme.button_style(false))
		button.add_theme_stylebox_override("pressed", HDTheme.button_style(false))
		button.add_theme_font_size_override("font_size", HDTheme.text_size("button_secondary", size))
	_source_button.visible = _steam_source_available()
	_rows_vbox.add_theme_constant_override("separation", HDTheme.list_metrics(size)["row_spacing"])


func get_initial_menu_focus() -> Control:
	return _difficulty_button


func _load_song() -> void:
	_song = ContentRegistry.get_song(_song_id)
	if _song.is_empty() and not _summary.is_empty():
		_song = {
			"id": _song_id,
			"display_name": str(_summary.get("song_title", _summary.get("display_name", _summary.get("songID", _song_id)))),
			"artist": str(_summary.get("artist", _summary.get("song_artist", "Community Chart"))),
		}
	if not _summary.is_empty():
		_selected_difficulty = _display_difficulty(str(_summary.get("difficulty", "professional")))
		_selected_mode = _display_mode(str(_summary.get("mode", "stems_mapped")))
	else:
		var available_difficulties: Array[String] = ContentRegistry.get_supported_difficulties(_song, GameModeConfig.DEFAULT_MODE)
		if available_difficulties.has("Professional"):
			_selected_difficulty = "Professional"
		elif not available_difficulties.is_empty():
			_selected_difficulty = available_difficulties.back()
		var available_modes: Array[String] = ContentRegistry.get_supported_modes(_song)
		_selected_mode = GameModeConfig.DEFAULT_MODE if available_modes.has(GameModeConfig.DEFAULT_MODE) else (available_modes[0] if not available_modes.is_empty() else GameModeConfig.DEFAULT_MODE)


func _refresh_labels() -> void:
	_title_label.text = str(_song.get("display_name", "LEADERBOARD"))
	_artist_label.text = str(_song.get("artist", "Unknown Artist")).to_upper()
	_difficulty_button.text = "DIFFICULTY • %s" % _selected_difficulty
	_mode_button.text = "MODE • %s" % GameModeConfig.get_short_label(_selected_mode).to_upper()
	_source_button.text = "SOURCE • %s" % ("STEAM" if _selected_source == "steam" else "ONLINE")


func _attempt_load() -> void:
	if _song.is_empty():
		_status_label.text = "Song metadata could not be loaded."
		return
	if _selected_source == "steam":
		_load_steam_entries()
		return
	if AppState.identity_service == null:
		_status_label.text = "Identity service is unavailable."
		return
	if not AppState.identity_service.is_authenticated():
		_status_label.text = "Connecting account to load leaderboard..."
		AppState.identity_service.ensure_relay_identity()
		return
	_load_entries()


func _load_entries() -> void:
	if _selected_source == "steam":
		_load_steam_entries()
		return
	if AppState.leaderboard_service == null:
		_status_label.text = "Leaderboard service is unavailable."
		return
	_status_label.text = "Loading leaderboard..."
	AppState.leaderboard_service.load_top_scores(_song_id, _selected_difficulty, _selected_mode, 100, func(success: bool, entries: Array) -> void:
		if not success:
			_status_label.text = "Unable to load this leaderboard right now."
			return
		_entries.clear()
		for entry_variant in entries:
			if entry_variant is Dictionary:
				_entries.append((entry_variant as Dictionary).duplicate(true))
		_status_label.text = "Global top scores for %s • %s." % [_selected_difficulty, GameModeConfig.get_short_label(_selected_mode)]
		_build_rows()
	)


func _load_steam_entries() -> void:
	if AppState.leaderboard_service == null:
		_status_label.text = "Leaderboard service is unavailable."
		return
	if not _steam_source_available():
		_status_label.text = "Steam leaderboard is unavailable on this device."
		return
	_status_label.text = "Loading Steam leaderboard..."
	AppState.leaderboard_service.load_top_steam_scores(
		_song_id,
		_selected_difficulty,
		_selected_mode,
		100,
		func(success: bool, entries: Array) -> void:
			if not success:
				_status_label.text = "Unable to load the Steam leaderboard right now."
				return
			_entries.clear()
			for entry_variant in entries:
				if entry_variant is Dictionary:
					_entries.append((entry_variant as Dictionary).duplicate(true))
			_status_label.text = "Steam top scores for %s • %s." % [_selected_difficulty, GameModeConfig.get_short_label(_selected_mode)]
			_build_rows()
	)


func _build_rows() -> void:
	for child in _rows_vbox.get_children():
		child.queue_free()
	_list_scroll.scroll_vertical = 0
	if _entries.is_empty():
		var empty := Label.new()
		empty.text = "NO SCORES YET FOR THIS VARIANT"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		HDTheme.apply_label(empty, "body", HDTheme.TERTIARY, true)
		_rows_vbox.add_child(empty)
		return
	for entry in _entries:
		_rows_vbox.add_child(_build_entry_row(entry, _is_local_entry(entry)))


func _build_entry_row(entry: Dictionary, is_local: bool) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 92)
	var style: StyleBoxFlat = HDTheme.card_style()
	if is_local:
		style.border_color = HDTheme.CYAN
		style.border_width_left = maxi(style.border_width_left, 2)
		style.border_width_top = maxi(style.border_width_top, 2)
		style.border_width_right = maxi(style.border_width_right, 2)
		style.border_width_bottom = maxi(style.border_width_bottom, 2)
		style.bg_color = style.bg_color.lerp(HDTheme.CYAN, 0.07)
	panel.add_theme_stylebox_override("panel", style)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	margin.add_child(row)

	var rank := Label.new()
	rank.custom_minimum_size = Vector2(72, 0)
	rank.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rank.text = "#%d" % int(entry.get("rank", 0))
	HDTheme.apply_label(rank, "section_title", HDTheme.CYAN if is_local else HDTheme.primary_text(), false)
	row.add_child(rank)

	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_theme_constant_override("separation", 4)
	row.add_child(center)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	center.add_child(name_row)
	var name := Label.new()
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.clip_text = true
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name.text = str(entry.get("displayName", "Player"))
	HDTheme.apply_label(name, "section_title", HDTheme.primary_text(), false)
	name_row.add_child(name)
	if _selected_source != "steam":
		name_row.add_child(_build_platform_badge(str(entry.get("platform", ""))))
	if is_local:
		var you_badge := Label.new()
		you_badge.text = "YOU"
		you_badge.size_flags_horizontal = Control.SIZE_SHRINK_END
		HDTheme.apply_label(you_badge, "caption", HDTheme.CYAN, true)
		name_row.add_child(you_badge)

	var detail := Label.new()
	detail.text = _entry_detail_text(entry)
	HDTheme.apply_label(detail, "supporting", HDTheme.SECONDARY, false)
	center.add_child(detail)

	var score := Label.new()
	score.custom_minimum_size = Vector2(160, 0)
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	score.text = str(entry.get("score", 0))
	HDTheme.apply_label(score, "section_title", HDTheme.CYAN if is_local else HDTheme.primary_text(), false)
	row.add_child(score)
	return panel


func _compact_date(iso_text: String) -> String:
	if iso_text.length() >= 10:
		return iso_text.substr(0, 10)
	return iso_text


func _entry_detail_text(entry: Dictionary) -> String:
	var parts: Array[String] = [
		"%.1f%%" % (float(entry.get("accuracy", 0.0)) * 100.0),
		"COMBO %d" % int(entry.get("maxCombo", 0)),
	]
	var achieved_at := _compact_date(str(entry.get("achievedAt", "")))
	if not achieved_at.is_empty():
		parts.append(achieved_at)
	return " • ".join(parts)


func _is_local_entry(entry: Dictionary) -> bool:
	if _selected_source == "steam":
		var local_steam_id: String = _local_steam_id()
		return not local_steam_id.is_empty() and str(entry.get("userID", "")) == local_steam_id
	if AppState.identity_service == null:
		return false
	var local_user_id: String = str(AppState.identity_service.get_current_identity().get("userID", ""))
	return not local_user_id.is_empty() and str(entry.get("userID", "")) == local_user_id


func _local_steam_id() -> String:
	if not Engine.has_singleton("Steam"):
		return ""
	var steam: Object = Engine.get_singleton("Steam")
	for method_name_variant in ["getSteamID", "get_steam_id"]:
		var method_name: String = str(method_name_variant)
		if not steam.has_method(method_name):
			continue
		var steam_id: String = str(steam.call(method_name)).strip_edges()
		if steam_id != "0":
			return steam_id
	return ""


func _build_platform_badge(raw_platform: String) -> Control:
	var platform := _normalized_platform(raw_platform)
	var badge_panel := PanelContainer.new()
	badge_panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	badge_panel.add_theme_stylebox_override("panel", _platform_badge_style(platform))
	var badge := Label.new()
	badge.text = _platform_badge_text(platform)
	HDTheme.apply_label(badge, "caption", _platform_badge_text_color(platform), true)
	badge_panel.add_child(badge)
	return badge_panel


func _normalized_platform(raw_platform: String) -> String:
	match raw_platform.strip_edges().to_lower():
		"android":
			return "android"
		"steam":
			return "steam"
		"guest":
			return "guest"
		"apple", "ios", "gamecenter", "game_center", "":
			return "apple"
		_:
			return "apple"


func _platform_badge_text(platform: String) -> String:
	match platform:
		"android":
			return PLATFORM_BADGE_ANDROID
		"steam":
			return PLATFORM_BADGE_STEAM
		"guest":
			return PLATFORM_BADGE_GUEST
		_:
			return PLATFORM_BADGE_APPLE


func _platform_badge_text_color(platform: String) -> Color:
	match platform:
		"android":
			return Color(0.66, 0.96, 0.60, 1.0)
		"steam":
			return Color(0.56, 0.82, 1.0, 1.0)
		"guest":
			return Color(1.0, 1.0, 1.0, 0.56)
		_:
			return Color(1.0, 1.0, 1.0, 0.78)


func _platform_badge_style(platform: String) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.corner_radius_top_left = 9
	style.corner_radius_top_right = 9
	style.corner_radius_bottom_left = 9
	style.corner_radius_bottom_right = 9
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	match platform:
		"android":
			style.bg_color = Color(0.28, 0.56, 0.24, 0.20)
			style.border_color = Color(0.45, 0.80, 0.40, 0.42)
		"steam":
			style.bg_color = Color(0.16, 0.32, 0.58, 0.20)
			style.border_color = Color(0.34, 0.58, 0.88, 0.46)
		"guest":
			style.bg_color = Color(1.0, 1.0, 1.0, 0.06)
			style.border_color = Color(1.0, 1.0, 1.0, 0.12)
		_:
			style.bg_color = Color(1.0, 1.0, 1.0, 0.08)
			style.border_color = Color(1.0, 1.0, 1.0, 0.18)
	style.content_margin_left = 8
	style.content_margin_top = 3
	style.content_margin_right = 8
	style.content_margin_bottom = 3
	return style


func _cycle_difficulty() -> void:
	if _song.is_empty():
		return
	var available: Array[String] = ContentRegistry.get_supported_difficulties(_song, _selected_mode)
	if available.is_empty():
		return
	var current_index: int = available.find(_selected_difficulty)
	if current_index == -1:
		current_index = 0
	_selected_difficulty = available[(current_index + 1) % available.size()]
	_refresh_labels()
	_load_entries()


func _cycle_mode() -> void:
	if _song.is_empty():
		return
	var available: Array[String] = ContentRegistry.get_supported_modes(_song)
	if available.is_empty():
		return
	var current_index: int = available.find(_selected_mode)
	if current_index == -1:
		current_index = 0
	_selected_mode = available[(current_index + 1) % available.size()]
	var supported_difficulties: Array[String] = ContentRegistry.get_supported_difficulties(_song, _selected_mode)
	if not supported_difficulties.has(_selected_difficulty) and not supported_difficulties.is_empty():
		_selected_difficulty = supported_difficulties.back()
	_refresh_labels()
	_load_entries()


func _cycle_source() -> void:
	if not _steam_source_available():
		_selected_source = "railway"
	else:
		_selected_source = "steam" if _selected_source == "railway" else "railway"
	_refresh_labels()
	_load_entries()


func _steam_source_available() -> bool:
	return AppState.has_steam_desktop_support() and SteamClient != null and SteamClient.is_ready()


func _display_difficulty(backend_value: String) -> String:
	match backend_value.to_lower():
		"easy":
			return "Easy"
		"medium":
			return "Medium"
		"hard":
			return "Hard"
		"expert":
			return "Expert"
		"professional":
			return "Professional"
		_:
			return backend_value.capitalize()


func _display_mode(backend_value: String) -> String:
	match backend_value:
		"synthesized":
			return GameModeConfig.SYNTHESIZED
		"stems_random":
			return GameModeConfig.STEMS_RANDOM
		_:
			return GameModeConfig.STEMS_MAPPED


func _on_auth_state_changed(identity: Dictionary) -> void:
	if str(identity.get("userID", "")).is_empty():
		return
	_load_entries()


func _on_identity_failed(message: String) -> void:
	_status_label.text = message


func _on_back_button_pressed() -> void:
	back_requested.emit()


func _on_difficulty_button_pressed() -> void:
	_cycle_difficulty()


func _on_mode_button_pressed() -> void:
	_cycle_mode()


func _on_source_button_pressed() -> void:
	_cycle_source()
