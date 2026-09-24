extends Control

const HDTheme = preload("res://scripts/ui/HDTheme.gd")
const HDListRowScene = preload("res://scenes/common/HDListRow.tscn")
const InertialScrollController = preload("res://scripts/ui/InertialScrollController.gd")
const MenuNavigator = preload("res://scripts/ui/MenuNavigator.gd")
const SongJacketService = preload("res://scripts/ui/SongJacketService.gd")

signal back_requested
signal song_requested(song_id: String, summary: Dictionary)

@onready var _back_label: Label = %BackLabel
@onready var _title_label: Label = %TitleLabel
@onready var _subtitle_label: Label = %SubtitleLabel
@onready var _status_label: Label = %StatusLabel
@onready var _divider: ColorRect = %Divider
@onready var _list_scroll: ScrollContainer = %ListScroll
@onready var _rows_vbox: VBoxContainer = %RowsVBox

var _songs: Array[Dictionary] = []
var _song_rows_by_id: Dictionary = {}
var _summaries_by_song_id: Dictionary = {}
var _menu_navigator: MenuNavigator


func _ready() -> void:
	_menu_navigator = MenuNavigator.install(self, Callable(self, "_on_back_button_pressed"))
	InertialScrollController.install(_list_scroll, _rows_vbox)
	_songs = ContentRegistry.get_songs()
	_apply_layout()
	get_viewport().size_changed.connect(_apply_layout)
	if AppState.identity_service != null:
		AppState.identity_service.auth_state_changed.connect(_on_auth_state_changed)
		AppState.identity_service.login_failed.connect(_on_identity_failed)
	_build_rows()
	_status_label.text = "Connecting account to load leaderboard summaries..."
	if AppState.identity_service != null:
		AppState.identity_service.ensure_relay_identity()
	_on_auth_state_changed(AppState.identity_service.get_current_identity() if AppState.identity_service != null else {})


func _apply_layout() -> void:
	var size := get_viewport_rect().size
	%Background.color = HDTheme.BG
	HDTheme.apply_label(_back_label, "caption", HDTheme.SECONDARY, false)
	_back_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	HDTheme.apply_back_button($SafeMargin/VBox/BackButton, _back_label)
	HDTheme.apply_label(_title_label, "screen_title", HDTheme.CYAN, true)
	HDTheme.apply_label(_subtitle_label, "caption", HDTheme.TERTIARY, true)
	HDTheme.apply_label(_status_label, "body", HDTheme.SECONDARY, true)
	_divider.color = HDTheme.CYAN * Color(1, 1, 1, 0.30)
	_rows_vbox.add_theme_constant_override("separation", HDTheme.list_metrics(size)["row_spacing"])


func get_initial_menu_focus() -> Control:
	for song in _songs:
		var song_id: String = str(song.get("id", ""))
		if _song_rows_by_id.has(song_id):
			return _song_rows_by_id[song_id] as Control
	return %BackButton


func _build_rows() -> void:
	for child in _rows_vbox.get_children():
		child.queue_free()
	_song_rows_by_id.clear()
	_list_scroll.scroll_vertical = 0
	for song in _songs:
		var row = HDListRowScene.instantiate()
		var song_id: String = str(song.get("id", ""))
		_rows_vbox.add_child(row)
		row.configure(
			str(song.get("display_name", "Unknown")),
			_song_subtitle(song_id, song),
			"VIEW",
			HDTheme.LANE_COLORS[_song_rows_by_id.size() % HDTheme.LANE_COLORS.size()],
			"",
			SongJacketService.texture_for_song(song)
		)
		row.activated.connect(_open_song.bind(song_id))
		_song_rows_by_id[song_id] = row
	call_deferred("_refresh_menu_navigation")


func _song_subtitle(song_id: String, song: Dictionary) -> String:
	var artist: String = str(song.get("artist", "Unknown Artist"))
	if not _summaries_by_song_id.has(song_id):
		return artist
	var summary: Dictionary = _summaries_by_song_id[song_id] as Dictionary
	return "%s\nBEST #%d • %d" % [
		artist,
		int(summary.get("rank", 0)),
		int(summary.get("score", 0)),
	]


func _on_auth_state_changed(identity: Dictionary) -> void:
	var user_id: String = str(identity.get("userID", ""))
	if user_id.is_empty():
		_status_label.text = "Sign in is required to view online leaderboards."
		return
	_load_summaries()


func _on_identity_failed(message: String) -> void:
	_status_label.text = message


func _load_summaries() -> void:
	if AppState.leaderboard_service == null:
		_status_label.text = "Leaderboard service is unavailable."
		return
	_status_label.text = "Loading leaderboard summaries..."
	var song_ids: Array[String] = []
	for song in _songs:
		song_ids.append(str(song.get("id", "")))
	AppState.leaderboard_service.load_song_summaries(song_ids, func(success: bool, summaries: Array) -> void:
		if not success:
			_status_label.text = "Unable to load leaderboard summaries right now."
			return
		_summaries_by_song_id.clear()
		for summary_variant in summaries:
			if summary_variant is Dictionary:
				var summary: Dictionary = (summary_variant as Dictionary).duplicate(true)
				_summaries_by_song_id[str(summary.get("songID", ""))] = summary
		_build_rows()
		_status_label.text = "Select a song to view the global leaderboard."
	)


func _open_song(song_id: String) -> void:
	var summary: Dictionary = (_summaries_by_song_id.get(song_id, {}) as Dictionary).duplicate(true)
	song_requested.emit(song_id, summary)


func _refresh_menu_navigation() -> void:
	if _menu_navigator != null:
		_menu_navigator.refresh_focusables()


func _on_back_button_pressed() -> void:
	back_requested.emit()
