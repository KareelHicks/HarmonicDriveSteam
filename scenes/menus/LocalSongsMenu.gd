extends Control

const HDTheme := preload("res://scripts/ui/HDTheme.gd")
const HDListRowScene := preload("res://scenes/common/HDListRow.tscn")
const GameModeConfig := preload("res://scripts/gameplay/GameModeConfig.gd")
const MenuNavigator := preload("res://scripts/ui/MenuNavigator.gd")

const SongDatabase := preload("res://scripts/songs/SongDatabase.gd")
const SongResolver := preload("res://scripts/songs/SongResolver.gd")
const LaneCountResolver := preload("res://scripts/songs/LaneCountResolver.gd")
const ChartMetadataResolver := preload("res://scripts/songs/ChartMetadataResolver.gd")

const ChartValidator := preload("res://scripts/songs/ChartValidator.gd")
const DifficultyManager := preload("res://scripts/editor/DifficultyManager.gd")
const ChartImportUtils := preload("res://scripts/editor/importers/ChartImportUtils.gd")
const ChartImportService := preload("res://scripts/editor/importers/ChartImportService.gd")
const MidiImportWizardControls := preload("res://scripts/editor/importers/MidiImportWizardControls.gd")
const EditorAudioImporter := preload("res://scripts/editor/importers/EditorAudioImporter.gd")
const ImportSourceScanner := preload("res://scripts/editor/importers/ImportSourceScanner.gd")
const WaveformRenderer := preload("res://scripts/editor/WaveformRenderer.gd")
const YouTubeAudioImporter := preload("res://scripts/editor/YouTubeAudioImporter.gd")
const HarmonicProjectPackage := preload("res://scripts/editor/HarmonicProjectPackage.gd")
const WorkshopChartAudioLink := preload("res://scripts/workshop/WorkshopChartAudioLink.gd")
const WorkshopSubscriptionSync := preload("res://scripts/workshop/WorkshopSubscriptionSync.gd")
const HDSongCarousel := preload("res://scripts/ui/HDSongCarousel.gd")
const SongJacketService := preload("res://scripts/ui/SongJacketService.gd")
const HDUIMotion := preload("res://scripts/ui/HDUIMotion.gd")

const IMPORT_AUDIO_AUTO := "__auto__"
const IMPORT_AUDIO_NONE := "__none__"
const LINK_AUDIO_FILTERS: Array[String] = [
	"*.ogg, *.wav, *.mp3, *.opus, *.m4a, *.webm, *.mp4, *.aac ; Audio files",
	"*.ogg ; Ogg Vorbis",
	"*.wav ; WAV audio",
	"*.mp3 ; MP3 audio",
	"*.opus ; Opus audio",
	"*.m4a, *.webm, *.mp4, *.aac ; Convertible audio",
]
const MAIN_GAME_AUDIO_DIR := "res://content/audio"
const MAIN_GAME_CHART_DIR := "res://content/charts/stems_mapped"
const MAIN_GAME_MANIFEST_PATH := "res://content/manifests/song_manifest.json"

signal back_requested
signal start_requested(song_entry: Dictionary, difficulty: String, mode: String)
signal loadout_requested

@onready var _rows_vbox: VBoxContainer = %RowsVBox
@onready var _status_label: Label = %StatusLabel
@onready var _subtitle_label: Label = %SubtitleLabel
@onready var _search_field: LineEdit = %SearchField
@onready var _import_folder_dialog: FileDialog = %ImportFolderDialog
@onready var _project_name_dialog: ConfirmationDialog = %ProjectNameDialog
@onready var _project_name_edit: LineEdit = %ProjectNameEdit
@onready var _import_wizard_dialog: ConfirmationDialog = %ImportWizardDialog
@onready var _import_wizard_scroll: ScrollContainer = %ImportWizardScroll
@onready var _import_file_option: OptionButton = %ImportFileOption
@onready var _import_source_option: OptionButton = %ImportSourceOption
@onready var _import_audio_option: OptionButton = %ImportAudioOption
@onready var _import_difficulty_option: OptionButton = %ImportDifficultyOption
@onready var _import_warning_label: Label = %ImportWarningLabel
@onready var _message_dialog: AcceptDialog = %EditorMessageDialog
@onready var _loading_overlay: ColorRect = %LoadingOverlay
@onready var _loading_title_label: Label = %LoadingTitleLabel
@onready var _loading_status_label: Label = %LoadingStatusLabel
@onready var _import_to_main_game_button: Button = %ImportToMainGameButton
@onready var _link_audio_button: Button = %LinkAudioButton
@onready var _remove_community_chart_button: Button = %RemoveCommunityChartButton
@onready var _link_audio_file_dialog: FileDialog = %LinkAudioFileDialog

var _menu_navigator: MenuNavigator

var _song_db := SongDatabase.new()
var _all_songs: Array[Dictionary] = []
var _songs: Array[Dictionary] = []
var _song_rows_by_id: Dictionary = {}
var _selected_song: Dictionary = {}
var _pending_mode := GameModeConfig.DEFAULT_MODE
var _is_exiting := false
var _carousel: HDSongCarousel
var _last_analog_carousel_ms := 0

var _pending_source_folder := ""
var _pending_project_folder := ""
var _pending_import_path := ""
var _pending_import_file_candidates: Array[String] = []
var _pending_import_audio_candidates: Array[String] = []
var _pending_import_audio_path := ""
var _pending_import_result: Dictionary = {}
var _pending_import_preview_result: Dictionary = {}
var _pending_import_waveform := WaveformRenderer.new()
var _midi_import_controls: Dictionary = {}
var _import_source_dialog: ConfirmationDialog
var _import_harmonic_file_dialog: FileDialog
var _remove_community_chart_dialog: ConfirmationDialog
var _source_root_filter := SongResolver.CUSTOM_ROOT
var _source_type_filter := "custom"
var _screen_title := "LOCAL SONGS"
var _empty_status_message := "No local projects found. Use Import Song to add one."
var _allow_import_controls := true


func configure_source(root_filter: String, source_type: String, title: String, empty_status_message: String, allow_import_controls: bool = false) -> void:
	_source_root_filter = root_filter.strip_edges()
	_source_type_filter = source_type.strip_edges()
	_screen_title = title.strip_edges()
	_empty_status_message = empty_status_message.strip_edges()
	_allow_import_controls = allow_import_controls
	if _screen_title.is_empty():
		_screen_title = "LOCAL SONGS"
	if _empty_status_message.is_empty():
		_empty_status_message = "No songs found."
	if is_inside_tree():
		_apply_source_mode()
		_reload_local_songs()
		_apply_song_filter()
		_build_rows()
		_select_initial_song()
		_refresh_status()


func _ready() -> void:
	SongResolver.ensure_user_song_dirs()
	_menu_navigator = MenuNavigator.install(self, Callable(self, "_on_back_button_pressed"))
	%Background.color = HDTheme.BG
	_apply_header()
	_reload_local_songs()
	_apply_song_filter()
	_build_rows()
	_select_initial_song()
	_refresh_status()
	_hide_selection_overlay()
	_setup_midi_import_controls()
	_setup_project_import_dialogs()
	_setup_community_chart_remove_dialog()
	_link_audio_file_dialog.filters = PackedStringArray(LINK_AUDIO_FILTERS)
	HDTheme.apply_dialog_tree(self)
	_import_file_option.item_selected.connect(_on_import_file_option_selected)
	_import_audio_option.item_selected.connect(_on_import_audio_option_selected)
	call_deferred("_restore_selected_row_state")


func _setup_midi_import_controls() -> void:
	_midi_import_controls = MidiImportWizardControls.create()
	var root := _midi_import_controls.get("root") as Control
	var parent := _import_warning_label.get_parent() as VBoxContainer
	if parent != null and root != null:
		parent.add_child(root)
	MidiImportWizardControls.connect_changed(_midi_import_controls, Callable(self, "_on_midi_import_options_changed"))


func _setup_project_import_dialogs() -> void:
	_import_source_dialog = ConfirmationDialog.new()
	_import_source_dialog.title = "Import Song"
	_import_source_dialog.ok_button_text = "Import Folder"
	_import_source_dialog.cancel_button_text = "Cancel"
	_import_source_dialog.add_button("Import .harmonic", false, "harmonic")
	add_child(_import_source_dialog)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	_import_source_dialog.add_child(margin)
	var label := Label.new()
	label.text = "Choose a folder-based chart import or a packaged .harmonic project."
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 480.0
	margin.add_child(label)
	_import_source_dialog.confirmed.connect(_on_import_source_folder_selected)
	_import_source_dialog.custom_action.connect(_on_import_source_custom_action)

	_import_harmonic_file_dialog = FileDialog.new()
	_import_harmonic_file_dialog.title = "Import Harmonic Project"
	_import_harmonic_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_import_harmonic_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_import_harmonic_file_dialog.filters = PackedStringArray(["*.harmonic ; Harmonic Drive project (*.harmonic)"])
	_import_harmonic_file_dialog.file_selected.connect(_on_harmonic_file_selected)
	add_child(_import_harmonic_file_dialog)


func _setup_community_chart_remove_dialog() -> void:
	_remove_community_chart_dialog = ConfirmationDialog.new()
	_remove_community_chart_dialog.title = "Remove Community Chart"
	_remove_community_chart_dialog.ok_button_text = "Remove"
	_remove_community_chart_dialog.cancel_button_text = "Cancel"
	_remove_community_chart_dialog.confirmed.connect(_on_remove_community_chart_confirmed)
	add_child(_remove_community_chart_dialog)


func _apply_header() -> void:
	var size: Vector2 = get_viewport_rect().size
	var metrics: Dictionary = HDTheme.list_metrics(size)
	var overlay_metrics: Dictionary = HDTheme.overlay_metrics(size)
	HDTheme.apply_label(%BackLabel, "caption", HDTheme.SECONDARY, false)
	%BackLabel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	HDTheme.apply_back_button(%BackButton, %BackLabel)
	HDTheme.apply_label(%TitleLabel, "screen_title", HDTheme.CYAN, true)
	HDTheme.apply_label(%SubtitleLabel, "caption", HDTheme.TERTIARY, true)
	HDTheme.apply_label(_status_label, "body", HDTheme.SECONDARY, true)
	_search_field.custom_minimum_size = Vector2(0, 42)
	%Divider.color = HDTheme.CYAN * Color(1, 1, 1, 0.30)
	%BackButton.custom_minimum_size = Vector2(132, 48)
	%LoadoutButton.custom_minimum_size = Vector2(168, 48)
	%ImportButton.custom_minimum_size = Vector2(190, 48)
	_import_to_main_game_button.custom_minimum_size = Vector2(258, 48)
	_import_to_main_game_button.visible = OS.has_feature("editor")
	_import_to_main_game_button.disabled = not OS.has_feature("editor")
	_link_audio_button.custom_minimum_size = Vector2(170, 48)
	_remove_community_chart_button.custom_minimum_size = Vector2(190, 48)
	%ImportInfoButton.custom_minimum_size = Vector2(48, 48)
	_rows_vbox.add_theme_constant_override("separation", metrics["row_spacing"])
	%ListScroll.visible = false
	_ensure_carousel()
	%SelectionPanel.custom_minimum_size = Vector2(float(overlay_metrics["panel_width"]) * 0.82, float(overlay_metrics["panel_height"]) * 0.72)
	%InfoPanel.custom_minimum_size = Vector2(float(overlay_metrics["panel_width"]) * 0.92, float(overlay_metrics["panel_height"]) * 0.78)
	%SelectionButtons.add_theme_constant_override("separation", 14)
	HDTheme.apply_label(%SelectionTitleLabel, "screen_title", HDTheme.CYAN, true)
	HDTheme.apply_label(%SelectionSubtitleLabel, "body", HDTheme.SECONDARY, true)
	HDTheme.apply_label(%InfoTitleLabel, "screen_title", HDTheme.CYAN, true)
	HDTheme.apply_label(%InfoTextLabel, "body", HDTheme.SECONDARY, true)
	%InfoScroll.custom_minimum_size.y = float(overlay_metrics["panel_height"]) * 0.48
	# Ensure the scroll content has a sensible width so the label doesn't wrap to 1 character/line.
	%InfoScroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	%InfoTextLabel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	%InfoTextLabel.custom_minimum_size.x = maxf(360.0, %InfoPanel.custom_minimum_size.x - 80.0)
	for button in [%SelectionCancelButton, %LoadoutButton, %ImportButton, _import_to_main_game_button, _link_audio_button, _remove_community_chart_button, %ImportInfoButton]:
		button.add_theme_stylebox_override("normal", HDTheme.button_style(false))
		button.add_theme_stylebox_override("hover", HDTheme.button_style(false))
		button.add_theme_stylebox_override("pressed", HDTheme.button_style(false))
		button.add_theme_font_size_override("font_size", HDTheme.text_size("button_secondary", size))
		HDUIMotion.attach_button(button)
	%ImportInfoButton.add_theme_font_size_override("font_size", HDTheme.text_size("screen_title", size))
	%InfoCloseButton.add_theme_stylebox_override("normal", HDTheme.button_style(false))
	%InfoCloseButton.add_theme_stylebox_override("hover", HDTheme.button_style(false))
	%InfoCloseButton.add_theme_stylebox_override("pressed", HDTheme.button_style(false))
	%InfoCloseButton.add_theme_font_size_override("font_size", HDTheme.text_size("button_secondary", size))
	%InfoCloseButton.custom_minimum_size = Vector2(180, float(overlay_metrics["button_height"]))
	%SelectionCancelButton.custom_minimum_size = Vector2(0, float(overlay_metrics["button_height"]))
	%SelectionPanel.add_theme_stylebox_override("panel", HDTheme.overlay_panel_style())
	%InfoPanel.add_theme_stylebox_override("panel", HDTheme.overlay_panel_style())
	%OverlayDim.color = Color(0, 0, 0, 0.74)
	%SelectionCenter.mouse_filter = Control.MOUSE_FILTER_STOP
	%InfoCenter.mouse_filter = Control.MOUSE_FILTER_STOP
	_loading_overlay.color = Color(0, 0, 0, 0.45)
	_apply_source_mode()


func _apply_source_mode() -> void:
	if not is_inside_tree():
		return
	%TitleLabel.text = _screen_title
	%SearchField.placeholder_text = "Search community charts" if _source_type_filter == "workshop" else "Search local songs"
	%ImportButton.visible = _allow_import_controls
	%ImportButton.disabled = not _allow_import_controls
	_import_to_main_game_button.visible = _allow_import_controls and OS.has_feature("editor")
	_import_to_main_game_button.disabled = not _import_to_main_game_button.visible
	_link_audio_button.visible = _source_type_filter == "workshop"
	_remove_community_chart_button.visible = _source_type_filter == "workshop"
	%ImportInfoButton.visible = _allow_import_controls
	%ImportInfoButton.disabled = not _allow_import_controls
	_refresh_community_chart_buttons()


func _reload_local_songs() -> void:
	_song_db.reload()
	_all_songs.clear()
	for entry_var in _song_db.get_songs():
		if entry_var is not Dictionary:
			continue
		var entry: Dictionary = entry_var as Dictionary
		if str(entry.get("source", "")) != _source_type_filter:
			continue
		var root_path := str(entry.get("root_path", ""))
		if not _source_root_filter.is_empty() and not root_path.begins_with(_source_root_filter):
			continue
		_all_songs.append(_song_with_resolved_metadata(entry.duplicate(true), "professional"))
	_all_songs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("title", "")) < str(b.get("title", ""))
	)


func _apply_song_filter() -> void:
	var query: String = _search_field.text.strip_edges().to_lower()
	if query.is_empty():
		_songs = _all_songs.duplicate(true)
		return
	_songs.clear()
	for song in _all_songs:
		var haystack := "%s %s %s %s" % [
			str(song.get("title", "")),
			str(song.get("artist", "")),
			str(song.get("charter", "")),
			str(song.get("song_id", "")),
		]
		if haystack.to_lower().contains(query):
			_songs.append(song)


func _build_rows() -> void:
	for child in _rows_vbox.get_children():
		child.queue_free()
	_song_rows_by_id.clear()
	_ensure_carousel()
	_apply_local_carousel_metadata(_songs)
	_carousel.configure(
		_songs,
		str(_selected_song.get("song_id", "")),
		{
			"title": Callable(self, "_local_title_label"),
			"best": Callable(self, "_local_best_label"),
			"badge": Callable(self, "_local_badge_label"),
			"difficulty": Callable(self, "_local_difficulty_label"),
		}
	)
	call_deferred("_refresh_menu_navigation")
	return
	for index in _songs.size():
		var song: Dictionary = _songs[index]
		var song_id: String = str(song.get("song_id", ""))
		var row := HDListRowScene.instantiate()
		_rows_vbox.add_child(row)
		var subtitle := str(song.get("artist", "Unknown Artist"))
		var badge := "PROJECT"
		row.configure(
			str(song.get("title", "Unknown")),
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
		_selected_song = {}
		_refresh_community_chart_buttons()
		return
	_selected_song = _songs[0]
	_sync_carousel_to_selected()
	_refresh_community_chart_buttons()


func _refresh_status() -> void:
	_subtitle_label.text = "%d SONGS" % _songs.size()
	if _songs.is_empty():
		_status_label.text = _empty_status_message
	else:
		_status_label.text = "Select a song to choose mode, difficulty, and play."
	_refresh_community_chart_buttons()


func _refresh_community_chart_buttons() -> void:
	var is_community := _source_type_filter == "workshop"
	var disabled := not is_community or _selected_song.is_empty()
	if _link_audio_button != null:
		_link_audio_button.visible = is_community
		_link_audio_button.disabled = disabled
	if _remove_community_chart_button != null:
		_remove_community_chart_button.visible = is_community
		_remove_community_chart_button.disabled = disabled


func _bpm_label(song: Dictionary) -> String:
	var bpm: float = float(song.get("bpm", 0.0))
	if bpm <= 0.0:
		return "-- BPM"
	if is_equal_approx(bpm, roundf(bpm)):
		return "%d BPM" % int(roundf(bpm))
	return "%.2f BPM" % bpm


func _song_with_resolved_metadata(song: Dictionary, difficulty_id: String = "") -> Dictionary:
	var metadata := ChartMetadataResolver.metadata_for_song_entry(song, difficulty_id)
	return ChartMetadataResolver.apply_metadata_to_song_entry(song, metadata)


func _select_song(song: Dictionary) -> void:
	_selected_song = song
	_show_mode_selection()


func _show_mode_selection() -> void:
	if _selected_song.is_empty():
		return
	var chart_paths := _chart_paths_for_song(_selected_song)
	if chart_paths.is_empty():
		_show_message("No Charts Found", "No difficulty charts were found in:\n%s" % str(_selected_song.get("root_path", "")))
		return
	var local_song_entry := {
		"modes": _mode_payloads_for_chart_paths(chart_paths),
	}
	var options: Array[String] = ContentRegistry.get_supported_modes(local_song_entry)
	if options.is_empty():
		_show_message("No Modes Found", "No playable chart modes were found for this local song.")
		return
	var player_level: int = ProgressionManager.get_level()
	var unlocked_modes: Array[String] = []
	for mode_id in options:
		if GameModeConfig.is_unlocked_for_level(mode_id, player_level):
			unlocked_modes.append(mode_id)
	if unlocked_modes.is_empty():
		_status_label.text = "Reach level %d to unlock more play modes." % mini(
			GameModeConfig.get_required_level(GameModeConfig.STEMS_RANDOM),
			GameModeConfig.get_required_level(GameModeConfig.SYNTHESIZED)
		)
		return
	var preferred_mode: String = ProfileStore.get_selected_mode()
	_pending_mode = preferred_mode if unlocked_modes.has(preferred_mode) else unlocked_modes[0]
	_show_selection_overlay(
		"SELECT MODE",
		"%s\n%s" % [str(_selected_song.get("title", "Unknown")), str(_selected_song.get("artist", ""))],
		options,
		Callable(self, "_on_mode_selected"),
		Callable(self, "_mode_option_label"),
		Callable(self, "_mode_option_enabled")
	)


func _show_difficulty_selection() -> void:
	if _selected_song.is_empty():
		return
	var chart_paths := _chart_paths_for_song(_selected_song)
	if chart_paths.is_empty():
		_show_message("No Charts Found", "No difficulty charts were found in:\n%s" % str(_selected_song.get("root_path", "")))
		return
	var local_song_entry := {
		"modes": _mode_payloads_for_chart_paths(chart_paths),
	}
	var options: Array[String] = []
	for display_name in ContentRegistry.get_supported_difficulties(local_song_entry, _pending_mode):
		var difficulty_id := DifficultyManager.id_from_display(display_name)
		options.append(difficulty_id)
	if options.is_empty():
		_show_message("No Charts Found", "No %s charts were found in:\n%s" % [GameModeConfig.get_short_label(_pending_mode), str(_selected_song.get("root_path", ""))])
		return
	_show_selection_overlay(
		"SELECT DIFFICULTY",
		"%s  •  %s" % [str(_selected_song.get("title", "Unknown")), GameModeConfig.get_short_label(_pending_mode)],
		options,
		Callable(self, "_on_difficulty_selected"),
		Callable(self, "_difficulty_label")
	)


func _mode_option_label(mode_id: String) -> String:
	if GameModeConfig.is_unlocked_for_level(mode_id, ProgressionManager.get_level()):
		return GameModeConfig.get_display_name(mode_id)
	return "%s  •  UNLOCKS AT LEVEL %d" % [GameModeConfig.get_display_name(mode_id), GameModeConfig.get_required_level(mode_id)]


func _mode_option_enabled(mode_id: String) -> bool:
	return GameModeConfig.is_unlocked_for_level(mode_id, ProgressionManager.get_level())


func _difficulty_label(difficulty_id: String) -> String:
	return DifficultyManager.display_name(str(difficulty_id))


func _on_mode_selected(mode_id: String) -> void:
	_pending_mode = mode_id
	ProfileStore.set_selected_mode(mode_id)
	_show_difficulty_selection()


func _on_difficulty_selected(difficulty_id: String) -> void:
	_hide_selection_overlay()
	var song_entry := _build_song_entry_for_game(_selected_song, difficulty_id)
	if song_entry.is_empty():
		return
	var display := DifficultyManager.display_name(difficulty_id)
	start_requested.emit(song_entry, display, _pending_mode)


func _build_song_entry_for_game(song: Dictionary, difficulty_id: String = "") -> Dictionary:
	var song_folder := str(song.get("root_path", ""))
	if song_folder.is_empty():
		_show_message("Missing Project Folder", "This project is missing a root_path.")
		return {}
	var audio_path := _audio_path_for_song(song)
	if audio_path.is_empty():
		var youtube_repair := _download_missing_youtube_audio_for_song(song, song_folder)
		if bool(youtube_repair.get("ok", false)):
			audio_path = str(youtube_repair.get("path", ""))
		elif bool(youtube_repair.get("attempted", false)):
			var repair_hint := "Use LINK AUDIO to attach a local file for this Community Chart." if str(song.get("source", _source_type_filter)) == "workshop" else "Import audio in the Chart Editor or re-import the song."
			_show_message(
				"YouTube Audio Download Failed",
				"No audio file was found in:\n%s\n\n%s\n\nyt-dlp: %s\nFFmpeg: %s\n\n%s" % [
					song_folder,
					str(youtube_repair.get("error", "YouTube audio download failed.")),
					str(youtube_repair.get("yt_dlp", "not found")),
					str(youtube_repair.get("ffmpeg", "not found")),
					repair_hint,
				]
			)
			return {}
		else:
			_show_message("Missing audio", "No audio file was found in:\n%s\n\nImport audio in the Chart Editor or re-import the song." % song_folder)
			return {}

	var chart_paths := _chart_paths_for_song(song)
	var source_type := str(song.get("source", _source_type_filter)).strip_edges()
	var source_label := "Community" if source_type == "workshop" else "Local"
	var resolved_song := _song_with_resolved_metadata(song.duplicate(true), difficulty_id)

	return {
		"id": str(song.get("song_id", song_folder.get_file())),
		"display_name": str(resolved_song.get("display_name", resolved_song.get("title", song_folder.get_file()))),
		"title": str(resolved_song.get("title", song_folder.get_file())),
		"artist": str(resolved_song.get("artist", "")),
		"charter": str(resolved_song.get("charter", "")),
		"chart_author": str(resolved_song.get("charter", "")),
		"source_type": source_type,
		"source": source_type,
		"source_label": source_label,
		"return_route": "community_charts" if source_type == "workshop" else "local_songs",
		"root_path": song_folder,
		"manifest_path": str(song.get("manifest_path", "")),
		"audio_path": audio_path,
		"assets": song.get("assets", {}),
		"metadata_source_difficulty": str(resolved_song.get("metadata_source_difficulty", "")),
		"modes": _mode_payloads_for_chart_paths(chart_paths),
	}


func _audio_path_for_song(song: Dictionary) -> String:
	var song_folder := str(song.get("root_path", ""))
	if song_folder.is_empty():
		return ""
	var audio_path := ""
	var manifest_path := str(song.get("manifest_path", song_folder.path_join("manifest.json")))
	if FileAccess.file_exists(manifest_path):
		var file := FileAccess.open(manifest_path, FileAccess.READ)
		if file != null:
			var parsed: Variant = JSON.parse_string(file.get_as_text())
			if parsed is Dictionary:
				audio_path = str((parsed as Dictionary).get("audio_path", "")).strip_edges()
	if not audio_path.is_empty() and not FileAccess.file_exists(audio_path):
		audio_path = song_folder.path_join(audio_path)
	if not audio_path.is_empty() and FileAccess.file_exists(audio_path):
		return audio_path
	for candidate in ["song.ogg", "song.wav", "song.mp3", "song.opus", "song.m4a", "song.webm", "song.aac"]:
		var p := song_folder.path_join(candidate)
		if FileAccess.file_exists(p):
			return p
	var dir := DirAccess.open(song_folder)
	if dir == null:
		return ""
	var supported := ["wav", "ogg", "mp3", "opus", "m4a", "webm", "aac"]
	var found: Array[String] = []
	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name.is_empty():
			break
		if dir.current_is_dir():
			continue
		var lower := String(name).to_lower()
		for ext in supported:
			if lower.ends_with("." + ext):
				found.append(song_folder.path_join(name))
				break
	dir.list_dir_end()
	found.sort()
	return found[0] if not found.is_empty() else ""


func _download_missing_youtube_audio_for_song(song: Dictionary, song_folder: String) -> Dictionary:
	var manifest := _manifest_for_song(song, song_folder)
	var youtube_url := str(manifest.get("youtube_url", "")).strip_edges()
	if not YouTubeAudioImporter.is_supported_url(youtube_url):
		return {"ok": false, "attempted": false, "path": "", "error": ""}
	_show_loading("Downloading YouTube audio", "Fetching audio for %s..." % str(song.get("title", song_folder.get_file())))
	var audio_result := YouTubeAudioImporter.import_url_to_project(youtube_url, song_folder)
	_hide_loading()
	if not bool(audio_result.get("ok", false)):
		var tool_status := YouTubeAudioImporter.tool_status()
		return {
			"ok": false,
			"attempted": true,
			"path": "",
			"error": str(audio_result.get("error", "YouTube audio download failed.")),
			"yt_dlp": str(tool_status.get("yt_dlp", "not found")),
			"ffmpeg": str(tool_status.get("ffmpeg", "not found")),
		}
	var audio_path := str(audio_result.get("path", "")).strip_edges()
	var manifest_result := HarmonicProjectPackage.set_manifest_audio_path(song_folder, audio_path.get_file())
	if bool(manifest_result.get("ok", false)):
		HarmonicProjectPackage.set_manifest_youtube_url(song_folder, youtube_url)
	return {
		"ok": bool(manifest_result.get("ok", false)),
		"attempted": true,
		"path": audio_path,
		"error": str(manifest_result.get("error", "")),
	}


func _manifest_for_song(song: Dictionary, song_folder: String) -> Dictionary:
	var manifest_path := str(song.get("manifest_path", song_folder.path_join("manifest.json")))
	if not FileAccess.file_exists(manifest_path):
		return {}
	var file := FileAccess.open(manifest_path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return (parsed as Dictionary) if parsed is Dictionary else {}


func _chart_paths_for_song(song: Dictionary) -> Dictionary:
	var song_folder := str(song.get("root_path", ""))
	if song_folder.is_empty():
		return {}
	var declared_chart_paths: Dictionary = song.get("chart_paths", {}) as Dictionary
	var chart_paths := {}
	for id in DifficultyManager.all_ids():
		var p := str(declared_chart_paths.get(id, "")).strip_edges()
		if p.is_empty():
			p = SongResolver.get_chart_path(song_folder, id)
		if FileAccess.file_exists(p):
			chart_paths[DifficultyManager.display_name(id)] = p
	return chart_paths


func _mode_payloads_for_chart_paths(chart_paths: Dictionary) -> Dictionary:
	var modes := {}
	for mode_id in GameModeConfig.ORDER:
		modes[mode_id] = {"charts": chart_paths.duplicate(true)}
	return modes


func _show_selection_overlay(title: String, subtitle: String, options: Array, callback: Callable, label_builder: Callable = Callable(), enabled_builder: Callable = Callable()) -> void:
	%SelectionCenter.visible = true
	%SelectionCenter.mouse_filter = Control.MOUSE_FILTER_STOP
	%SelectionTitleLabel.text = title
	%SelectionSubtitleLabel.text = subtitle
	_update_modal_dim()
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


func _hide_selection_overlay() -> void:
	%SelectionCenter.visible = false
	for child in %SelectionButtons.get_children():
		if child != %SelectionCancelButton:
			child.queue_free()
	_update_modal_dim()
	if not _is_exiting:
		call_deferred("_restore_selected_row_state")


func _show_message(title: String, message: String) -> void:
	_message_dialog.title = title
	_message_dialog.dialog_text = _dialog_safe_text(message)
	_message_dialog.popup_centered(Vector2i(760, 360))


func _dialog_safe_text(message: String, max_chars: int = 1800, wrap_at: int = 104) -> String:
	var text := message.strip_edges()
	if text.length() > max_chars:
		text = text.substr(0, max_chars) + "\n\n..."
	var wrapped: Array[String] = []
	for raw_line in text.split("\n"):
		var line := String(raw_line)
		while line.length() > wrap_at:
			var cut := line.rfind(" ", wrap_at)
			if cut < 32:
				cut = wrap_at
			wrapped.append(line.substr(0, cut).strip_edges())
			line = line.substr(cut).strip_edges()
		wrapped.append(line)
	return "\n".join(wrapped)


func _show_loading(title: String, detail: String) -> void:
	_loading_title_label.text = title
	_loading_status_label.text = detail
	_loading_overlay.visible = true
	_status_label.text = "%s: %s" % [title, detail]


func _update_loading(detail: String) -> void:
	_loading_status_label.text = detail
	_status_label.text = "%s: %s" % [_loading_title_label.text, detail]


func _hide_loading() -> void:
	_loading_overlay.visible = false


func _refresh_menu_navigation() -> void:
	if _menu_navigator != null:
		_menu_navigator.refresh_focusables()


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


func _is_selection_overlay_visible() -> bool:
	return %SelectionCenter.visible


func _is_info_overlay_visible() -> bool:
	return %InfoCenter.visible


func _is_modal_overlay_visible() -> bool:
	return _is_selection_overlay_visible() or _is_info_overlay_visible()


func _update_modal_dim() -> void:
	var dim_visible := _is_modal_overlay_visible()
	%OverlayDim.visible = dim_visible
	%OverlayDim.mouse_filter = Control.MOUSE_FILTER_STOP if dim_visible else Control.MOUSE_FILTER_IGNORE


func _is_overlay_focusable_control(control: Control) -> bool:
	if control == %SelectionCancelButton:
		return true
	if control == %InfoCloseButton:
		return true
	var node: Node = control
	while node != null:
		if node == %SelectionCenter or node == %InfoCenter:
			return true
		if node == self:
			return false
		node = node.get_parent()
	return false


func _is_overlay_control(control: Control) -> bool:
	var node: Node = control
	while node != null:
		if node == %SelectionCenter or node == %InfoCenter or node == %OverlayDim:
			return true
		if node == self:
			return false
		node = node.get_parent()
	return false


func get_initial_menu_focus() -> Control:
	if _is_info_overlay_visible():
		return %InfoCloseButton
	if _is_selection_overlay_visible():
		var overlay_button := _first_enabled_selection_button()
		if overlay_button != null:
			return overlay_button
	var song_id: String = str(_selected_song.get("song_id", ""))
	if not song_id.is_empty() and _carousel != null:
		return _carousel
	for song in _songs:
		var id: String = str(song.get("song_id", ""))
		if _song_rows_by_id.has(id):
			return _song_rows_by_id[id]
	return %BackButton


func is_menu_focusable_control(control: Control) -> bool:
	if control == null:
		return false
	if _is_modal_overlay_visible():
		# When the modal overlay is open, never allow focus to land on background controls,
		# even if something tries to programmatically grab focus.
		if not _is_overlay_focusable_control(control):
			control.focus_mode = Control.FOCUS_NONE
			if control.has_focus():
				control.release_focus()
			return false
		return _is_overlay_focusable_control(control)
	if control == _search_field:
		return false
	return not _is_overlay_control(control)


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
	var song_id: String = str(_selected_song.get("song_id", ""))
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


func _on_song_row_focused(song: Dictionary) -> void:
	if _is_exiting:
		return
	_selected_song = song
	_sync_selected_song_preview()


func _on_carousel_song_changed(song: Dictionary) -> void:
	if _is_exiting:
		return
	_selected_song = song
	_refresh_community_chart_buttons()
	_sync_selected_song_preview()


func _sync_carousel_to_selected() -> void:
	if _carousel == null or not is_instance_valid(_carousel):
		return
	var song_id := str(_selected_song.get("song_id", ""))
	if not song_id.is_empty():
		_carousel.select_song_id(song_id, false)


func _sync_selected_song_preview() -> void:
	if _is_exiting or not is_inside_tree():
		return
	if _selected_song.is_empty():
		MenuAudio.stop()
		return
	var preview_entry := _song_with_resolved_metadata(_selected_song.duplicate(true), "professional")
	var audio_path := _audio_path_for_song(preview_entry)
	if audio_path.is_empty():
		MenuAudio.stop()
		return
	var chart_paths := _chart_paths_for_song(preview_entry)
	preview_entry["audio_path"] = audio_path
	preview_entry["chart_paths"] = chart_paths
	preview_entry["modes"] = _mode_payloads_for_chart_paths(chart_paths)
	if not preview_entry.has("id"):
		preview_entry["id"] = str(preview_entry.get("song_id", preview_entry.get("title", "")))
	MenuAudio.play_song_entry_preview(preview_entry)


func _apply_local_carousel_metadata(song_entries: Array[Dictionary]) -> void:
	for index in song_entries.size():
		var song := _song_with_resolved_metadata(song_entries[index], "professional")
		song["section_name"] = "COMMUNITY" if _source_type_filter == "workshop" else "LOCAL"
		song["_difficulty_rating"] = clampi(_chart_paths_for_song(song).size(), 1, 5)
		song_entries[index] = song


func _local_title_label(song: Dictionary) -> String:
	return str(song.get("display_name", song.get("title", "Unknown")))


func _local_best_label(_song: Dictionary) -> String:
	return "WORKSHOP CHART" if _source_type_filter == "workshop" else "LOCAL PROJECT"


func _local_badge_label(_song: Dictionary) -> String:
	return "WORKSHOP" if _source_type_filter == "workshop" else "CUSTOM"


func _local_difficulty_label(song: Dictionary) -> String:
	return "DIFFICULTY %d / 5" % int(song.get("_difficulty_rating", 1))


func _unhandled_input(event: InputEvent) -> void:
	if _is_modal_overlay_visible() or _is_exiting or _carousel == null:
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


func _on_back_button_pressed() -> void:
	if _is_info_overlay_visible():
		_hide_info_overlay()
		return
	if _is_selection_overlay_visible():
		_hide_selection_overlay()
		return
	_is_exiting = true
	_hide_selection_overlay()
	back_requested.emit()


func _on_loadout_button_pressed() -> void:
	_is_exiting = true
	if _is_info_overlay_visible():
		_hide_info_overlay()
	_hide_selection_overlay()
	loadout_requested.emit()


func _on_selection_cancel_button_pressed() -> void:
	_hide_selection_overlay()


func _on_search_field_text_changed(_new_text: String) -> void:
	var preserve_focus := _search_field.has_focus()
	_apply_song_filter()
	_build_rows()
	_select_initial_song()
	_refresh_status()
	if preserve_focus:
		call_deferred("_restore_search_focus")


func _restore_search_focus() -> void:
	_search_field.grab_focus()
	_search_field.caret_column = _search_field.text.length()


func _on_search_field_text_submitted(_text: String) -> void:
	_search_field.release_focus()
	call_deferred("_refresh_menu_navigation")


func _on_import_button_pressed() -> void:
	if _import_source_dialog != null:
		_import_source_dialog.popup_centered(Vector2i(560, 220))
		return
	_on_import_source_folder_selected()


func _on_link_audio_button_pressed() -> void:
	if _source_type_filter != "workshop":
		return
	if _selected_song.is_empty():
		_show_message("No Community Chart Selected", "Select a Community Chart before linking audio.")
		return
	var project_folder := str(_selected_song.get("root_path", "")).strip_edges()
	if WorkshopChartAudioLink.item_id_from_project_folder(project_folder).is_empty():
		_show_message("Audio Link Failed", "This Community Chart does not have a valid Workshop item folder.")
		return
	_link_audio_file_dialog.title = "Select Audio For Community Chart"
	_link_audio_file_dialog.current_dir = ProjectSettings.globalize_path("user://")
	_link_audio_file_dialog.popup_centered_ratio(0.7)


func _on_remove_community_chart_button_pressed() -> void:
	if _source_type_filter != "workshop":
		return
	if _selected_song.is_empty():
		_show_message("No Community Chart Selected", "Select a Community Chart before removing it.")
		return
	var project_folder := str(_selected_song.get("root_path", "")).strip_edges()
	var item_id := WorkshopChartAudioLink.item_id_from_project_folder(project_folder)
	if item_id.is_empty():
		_show_message("Remove Failed", "This Community Chart does not have a valid Workshop item folder.")
		return
	if _remove_community_chart_dialog == null:
		_on_remove_community_chart_confirmed()
		return
	_remove_community_chart_dialog.dialog_text = _dialog_safe_text(
		"Remove \"%s\" from Community Charts on this device?\n\nThis deletes the cached chart files only. Linked audio is kept. If you are still subscribed in Steam, the chart may return the next time Workshop sync runs." %
		str(_selected_song.get("title", project_folder.get_file())),
		900,
		86
	)
	_remove_community_chart_dialog.popup_centered(Vector2i(680, 300))


func _on_remove_community_chart_confirmed() -> void:
	if _source_type_filter != "workshop" or _selected_song.is_empty():
		return
	var project_folder := str(_selected_song.get("root_path", "")).strip_edges()
	var item_id := WorkshopChartAudioLink.item_id_from_project_folder(project_folder)
	if item_id.is_empty():
		_show_message("Remove Failed", "This Community Chart does not have a valid Workshop item folder.")
		return
	var title := str(_selected_song.get("title", project_folder.get_file()))
	MenuAudio.stop()
	var result := WorkshopSubscriptionSync.remove_chart_item(item_id)
	if not bool(result.get("ok", false)):
		_show_message("Remove Failed", str(result.get("message", "Could not remove Community Chart.")))
		return
	_reload_local_songs()
	_apply_song_filter()
	_build_rows()
	_select_initial_song()
	_refresh_status()
	_sync_selected_song_preview()
	_show_message(
		"Community Chart Removed",
		"Removed %s from this device.\n\nIf you are still subscribed in Steam, it may return the next time Workshop sync runs." % title
	)


func _on_link_audio_file_selected(path: String) -> void:
	var source_path := path.strip_edges()
	if source_path.is_empty():
		return
	if _source_type_filter != "workshop" or _selected_song.is_empty():
		_show_message("Audio Link Failed", "Select a Community Chart before linking audio.")
		return
	var project_folder := str(_selected_song.get("root_path", "")).strip_edges()
	var item_id := WorkshopChartAudioLink.item_id_from_project_folder(project_folder)
	if item_id.is_empty():
		_show_message("Audio Link Failed", "This Community Chart does not have a valid Workshop item folder.")
		return
	_show_loading("Linking audio", "Preparing %s..." % source_path.get_file())
	var result := WorkshopChartAudioLink.link_audio_file(item_id, project_folder, source_path)
	_hide_loading()
	if not bool(result.get("ok", false)):
		_show_message("Audio Link Failed", str(result.get("error", "Could not link audio.")))
		return
	_reload_local_songs()
	_apply_song_filter()
	_build_rows()
	_select_song_by_folder(project_folder)
	_refresh_status()
	_sync_selected_song_preview()
	_show_message(
		"Audio Linked",
		"Community Chart: %s\nAudio: %s" % [
			str(_selected_song.get("title", project_folder.get_file())),
			str(result.get("audio_path", "")),
		]
	)


func _on_import_source_folder_selected() -> void:
	_import_folder_dialog.popup_centered_ratio(0.7)


func _on_import_source_custom_action(action: StringName) -> void:
	if action != &"harmonic":
		return
	if _import_source_dialog != null:
		_import_source_dialog.hide()
	if _import_harmonic_file_dialog != null:
		var root_abs := ProjectSettings.globalize_path(SongResolver.CUSTOM_ROOT)
		_import_harmonic_file_dialog.current_dir = root_abs
		_import_harmonic_file_dialog.popup_centered_ratio(0.7)


func _on_harmonic_file_selected(path: String) -> void:
	if path.strip_edges().is_empty():
		return
	_show_loading("Importing project", "Extracting .harmonic package...")
	var result := HarmonicProjectPackage.import_harmonic_to_custom_songs(path)
	if not bool(result.get("ok", false)):
		_hide_loading()
		_show_message("Project Import Failed", str(result.get("error", "Unknown import error.")))
		return
	var project_folder := str(result.get("project_folder", ""))
	var youtube_url := str(result.get("youtube_url", "")).strip_edges()
	var audio_status := "Audio: missing"
	if YouTubeAudioImporter.is_supported_url(youtube_url):
		_update_loading("Downloading YouTube audio...")
		var audio_result := YouTubeAudioImporter.import_url_to_project(youtube_url, project_folder)
		if bool(audio_result.get("ok", false)):
			HarmonicProjectPackage.set_manifest_audio_path(project_folder, str(audio_result.get("path", "")))
			HarmonicProjectPackage.set_manifest_youtube_url(project_folder, youtube_url)
			audio_status = "Audio: downloaded"
		else:
			audio_status = "Audio: YouTube download failed (%s)" % str(audio_result.get("error", "unknown error"))
	_hide_loading()
	_reload_local_songs()
	_apply_song_filter()
	_build_rows()
	_select_song_by_folder(project_folder)
	_refresh_status()
	_show_message(
		"Project Import Complete",
		"Project: %s\n%s" % [
			project_folder.get_file(),
			audio_status,
		]
	)


func _on_import_to_main_game_button_pressed() -> void:
	if not OS.has_feature("editor"):
		_show_message("Editor Only", "Import to Main Game is only available when running from the Godot editor.")
		return
	if _selected_song.is_empty():
		_show_message("No Song Selected", "Select a local song project before importing it to the main game.")
		return
	var selected_folder := str(_selected_song.get("root_path", ""))
	var result := _import_selected_song_to_main_game()
	if bool(result.get("ok", false)):
		_reload_local_songs()
		_apply_song_filter()
		_build_rows()
		_select_song_by_folder(selected_folder)
		_refresh_status()
		if ContentRegistry != null:
			ContentRegistry.reload_manifest()
		_show_message(
			"Main Game Import Complete",
			"Song: %s\nAudio: %s\nChart: %s\nManifest: %s" % [
				str(result.get("title", "")),
				str(result.get("audio_path", "")),
				str(result.get("chart_path", "")),
				MAIN_GAME_MANIFEST_PATH,
			]
		)
	else:
		_show_message("Main Game Import Failed", str(result.get("error", "Unknown error.")))


func _on_import_info_button_pressed() -> void:
	_show_info_overlay(
		"HOW TO IMPORT SONGS",
			"IMPORT SONG (Local Songs menu)\n" +
			"1) Click IMPORT SONG\n" +
			"2) Select a .harmonic package, or select a folder that contains either:\n" +
			"   - A .osz, .osk, or .sng package, OR\n" +
			"   - A .osu/.chart/.mid file + an audio file\n\n" +
			"Supported audio types:\n" +
			"- .wav, .ogg, .mp3, .opus, .m4a, .webm\n\n" +
		"HARMONIC CHARTER (in-game editor)\n" +
		"1) From the Title Menu, choose HARMONIC CHARTER\n" +
		"2) Create New Project (or open an existing project)\n" +
		"3) Use Import Chart (.osz, .osk, .osu, .sng, .chart, .mid/.midi)\n" +
			"4) Use Import Audio (.wav, .ogg, .mp3, .opus, .m4a, .webm) or YouTube URL\n" +
			"5) Use Export .harmonic to share a project without audio, then return to LOCAL SONGS to play the project\n\n" +
		"EDITOR ONLY: IMPORT TO MAIN GAME\n" +
		"Copies the selected local project's audio into res://content/audio as .ogg, copies only its Professional chart into res://content/charts/stems_mapped, and updates res://content/manifests/song_manifest.json."
	)


func _import_selected_song_to_main_game() -> Dictionary:
	var song := _selected_song.duplicate(true)
	var song_folder := str(song.get("root_path", ""))
	if song_folder.is_empty():
		return {"ok": false, "error": "The selected local song is missing its project folder."}
	var chart_paths := _chart_paths_for_song(song)
	var professional_chart := str(chart_paths.get("Professional", "")).strip_edges()
	if professional_chart.is_empty() or not FileAccess.file_exists(professional_chart):
		return {"ok": false, "error": "The selected local song does not have a Professional chart JSON."}
	var audio_source := _audio_path_for_song(song)
	if audio_source.is_empty() or not FileAccess.file_exists(audio_source):
		return {"ok": false, "error": "No audio file was found for this local song project."}

	var local_manifest := _read_dictionary_json(str(song.get("manifest_path", song_folder.path_join("manifest.json"))))
	var metadata := ChartMetadataResolver.metadata_for_song_entry(song, "professional")
	var title := str(metadata.get("title", song.get("title", local_manifest.get("title", song_folder.get_file())))).strip_edges()
	if title.is_empty():
		title = song_folder.get_file()
	var artist := str(metadata.get("artist", song.get("artist", local_manifest.get("artist", "")))).strip_edges()
	var song_id := _main_game_song_id(song, title)
	var audio_target := MAIN_GAME_AUDIO_DIR.path_join("%s.ogg" % song_id)
	var chart_target := MAIN_GAME_CHART_DIR.path_join("%s_professional.json" % song_id)

	var dir_result := _ensure_main_game_content_dirs()
	if not bool(dir_result.get("ok", false)):
		return dir_result
	var audio_result := _write_main_game_ogg(audio_source, audio_target)
	if not bool(audio_result.get("ok", false)):
		return audio_result
	var chart_result := _write_main_game_professional_chart(professional_chart, chart_target, song, local_manifest, title, artist, str(metadata.get("charter", "")))
	if not bool(chart_result.get("ok", false)):
		return chart_result
	var manifest_result := _upsert_main_game_song_manifest(song_id, title, artist, audio_target, chart_target, song, local_manifest)
	if not bool(manifest_result.get("ok", false)):
		return manifest_result
	return {
		"ok": true,
		"title": title,
		"audio_path": audio_target,
		"chart_path": chart_target,
	}


func _main_game_song_id(song: Dictionary, title: String) -> String:
	var raw := str(song.get("song_id", title)).strip_edges()
	if raw.is_empty():
		raw = title
	var song_id := ChartImportUtils.sanitize_id(raw).to_lower()
	return song_id if not song_id.is_empty() else "custom_song"


func _ensure_main_game_content_dirs() -> Dictionary:
	for path in [MAIN_GAME_AUDIO_DIR, MAIN_GAME_CHART_DIR, MAIN_GAME_MANIFEST_PATH.get_base_dir()]:
		var err := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))
		if err != OK:
			return {"ok": false, "error": "Could not create content directory:\n%s" % path}
	return {"ok": true}


func _write_main_game_ogg(source_path: String, target_path: String) -> Dictionary:
	if source_path.get_extension().to_lower() == "ogg":
		return _copy_file_bytes(source_path, target_path)
	var conversion := EditorAudioImporter.convert_to_ogg(source_path, target_path)
	if not bool(conversion.get("ok", false)):
		return {"ok": false, "error": "Could not convert audio to .ogg:\n%s" % str(conversion.get("error", "Unknown audio conversion error."))}
	return {"ok": true}


func _copy_file_bytes(source_path: String, target_path: String) -> Dictionary:
	var source := FileAccess.open(source_path, FileAccess.READ)
	if source == null:
		return {"ok": false, "error": "Could not read source file:\n%s" % source_path}
	var target := FileAccess.open(target_path, FileAccess.WRITE)
	if target == null:
		return {"ok": false, "error": "Could not write target file:\n%s" % target_path}
	target.store_buffer(source.get_buffer(source.get_length()))
	return {"ok": true}


func _write_main_game_professional_chart(source_path: String, target_path: String, song: Dictionary, local_manifest: Dictionary, title: String, artist: String, charter: String = "") -> Dictionary:
	var chart: Dictionary = _read_dictionary_json(source_path)
	if chart.is_empty():
		return {"ok": false, "error": "Could not read Professional chart JSON:\n%s" % source_path}
	chart["title"] = title
	chart["artist"] = artist
	chart["charter"] = charter.strip_edges() if not charter.strip_edges().is_empty() else str(song.get("charter", local_manifest.get("charter", ""))).strip_edges()
	chart["difficulty"] = "Professional"
	chart["bpm"] = float(song.get("bpm", local_manifest.get("bpm", chart.get("bpm", 120.0))))
	chart["lane_count"] = int(chart.get("lane_count", song.get("lane_count", local_manifest.get("lane_count", 5))))
	return _write_json_value(target_path, chart)


func _upsert_main_game_song_manifest(song_id: String, title: String, artist: String, audio_path: String, chart_path: String, song: Dictionary, local_manifest: Dictionary) -> Dictionary:
	var manifest_value: Variant = _read_json_value(MAIN_GAME_MANIFEST_PATH)
	var manifest: Array = []
	if manifest_value is Array:
		manifest = (manifest_value as Array).duplicate(true)
	for i in range(manifest.size() - 1, -1, -1):
		var entry_var: Variant = manifest[i]
		if entry_var is Dictionary and str((entry_var as Dictionary).get("id", "")) == song_id:
			manifest.remove_at(i)
	var bpm: float = float(song.get("bpm", local_manifest.get("bpm", 120.0)))
	manifest.append({
		"id": song_id,
		"display_name": title,
		"artist": artist,
		"audio_path": audio_path,
		"chart_base_name": title,
		"difficulties": ["Professional"],
		"modes": {
			GameModeConfig.STEMS_MAPPED: {
				"id": GameModeConfig.STEMS_MAPPED,
				"display_name": "Classic",
				"short_label": "Classic",
				"charts": {
					"Professional": chart_path,
				},
			},
		},
		"preview_start": 0.0,
		"bpm": bpm,
		"is_premium": false,
	})
	manifest.sort_custom(func(a: Variant, b: Variant) -> bool:
		if a is Dictionary and b is Dictionary:
			return str((a as Dictionary).get("display_name", "")).to_lower() < str((b as Dictionary).get("display_name", "")).to_lower()
		return false
	)
	return _write_json_value(MAIN_GAME_MANIFEST_PATH, manifest)


func _read_dictionary_json(path: String) -> Dictionary:
	var value: Variant = _read_json_value(path)
	return (value as Dictionary) if value is Dictionary else {}


func _read_json_value(path: String) -> Variant:
	if path.is_empty() or not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	return JSON.parse_string(file.get_as_text())


func _write_json_value(path: String, value: Variant) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "Could not write JSON file:\n%s" % path}
	file.store_string(JSON.stringify(value, "\t"))
	return {"ok": true}


func _show_info_overlay(title: String, message: String) -> void:
	%InfoTitleLabel.text = title
	%InfoTextLabel.text = message
	%InfoCenter.visible = true
	%InfoCenter.mouse_filter = Control.MOUSE_FILTER_STOP
	_update_modal_dim()
	_refresh_menu_navigation()
	if _menu_navigator != null and _menu_navigator.uses_controller_focus():
		%InfoCloseButton.grab_focus()


func _hide_info_overlay() -> void:
	%InfoCenter.visible = false
	_update_modal_dim()
	if not _is_exiting:
		call_deferred("_restore_selected_row_state")


func _on_info_close_button_pressed() -> void:
	_hide_info_overlay()


func _on_import_folder_selected(path: String) -> void:
	if path.is_empty():
		return
	_pending_source_folder = path
	_project_name_edit.text = ""
	_project_name_dialog.popup_centered()


func _on_project_name_confirmed() -> void:
	var folder_name: String = ChartImportUtils.sanitize_id(_project_name_edit.text)
	if folder_name.is_empty():
		_show_message("Invalid Name", "Please enter a project name.")
		return
	_pending_project_folder = _make_unique_project_folder(folder_name)
	var err: int = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_pending_project_folder))
	if err != OK:
		_show_message("Create Project Failed", "Could not create:\n%s" % _pending_project_folder)
		return
	_write_starter_project(_pending_project_folder, folder_name)

	_pending_import_file_candidates = ImportSourceScanner.list_chart_files(_pending_source_folder)
	_pending_import_audio_candidates = ImportSourceScanner.list_audio_files(_pending_source_folder)
	var candidate := _pick_chart_candidate(_pending_source_folder)
	if candidate.is_empty():
		_show_message("Import Failed", "No supported chart file (.osz, .osk, .osu, .sng, .chart, .mid/.midi) found in:\n%s" % _pending_source_folder)
		return
	_begin_import_inspection(candidate)


func _begin_import_inspection(path: String) -> void:
	_pending_import_path = path
	_pending_import_file_candidates = ImportSourceScanner.ensure_contains(ImportSourceScanner.list_chart_files(_pending_source_folder), path)
	_pending_import_audio_candidates = ImportSourceScanner.list_audio_files(_pending_source_folder)
	if _is_package_import_path(path):
		_pending_import_audio_path = ""
	elif _pending_import_audio_path.is_empty() and not _pending_import_audio_candidates.is_empty():
		_pending_import_audio_path = _pending_import_audio_candidates[0]
	_pending_import_waveform.clear()
	_show_loading("Inspecting chart import", "Reading %s..." % path.get_file())
	_pending_import_result = ChartImportService.inspect_import(path, _pending_project_folder)
	if not bool(_pending_import_result.get("ok", false)):
		_hide_loading()
		_show_message("Chart Import Failed", str(_pending_import_result.get("error", "Unknown error.")))
		return
	if _is_pending_midi_import():
		_update_loading("Preparing MIDI audio comparison...")
		_prepare_pending_midi_waveform()
	_hide_loading()
	_populate_import_wizard()
	_popup_import_wizard()


func _populate_import_wizard() -> void:
	_pending_import_preview_result = {}
	_populate_import_file_options()
	_populate_import_audio_options()
	if _is_pending_midi_import():
		MidiImportWizardControls.set_midi_visible(_midi_import_controls, true)
		MidiImportWizardControls.populate_tracks(_midi_import_controls, _pending_import_result)
		MidiImportWizardControls.set_audio_available(_midi_import_controls, _pending_import_waveform.is_ready(), _midi_audio_unavailable_reason())
		_refresh_midi_import_preview()
	else:
		MidiImportWizardControls.set_midi_visible(_midi_import_controls, false)
		_populate_import_source_options(_pending_import_result)
	_populate_import_difficulty_options(_active_import_result())


func _populate_import_file_options() -> void:
	_import_file_option.clear()
	var files: Array[String] = _pending_import_file_candidates.duplicate()
	if files.is_empty() and not _pending_import_path.is_empty():
		files.append(_pending_import_path)
	for i in range(files.size()):
		var path := files[i]
		_import_file_option.add_item(path.get_file())
		_import_file_option.set_item_metadata(i, path)
		if path == _pending_import_path:
			_import_file_option.select(i)


func _populate_import_audio_options() -> void:
	_import_audio_option.clear()
	if _is_package_import_path(_pending_import_path):
		_import_audio_option.add_item("Packaged audio / auto")
		_import_audio_option.set_item_metadata(0, IMPORT_AUDIO_AUTO)
		_import_audio_option.add_item("No audio")
		_import_audio_option.set_item_metadata(1, IMPORT_AUDIO_NONE)
	else:
		_import_audio_option.add_item("No audio")
		_import_audio_option.set_item_metadata(0, IMPORT_AUDIO_NONE)

	for audio_path in _pending_import_audio_candidates:
		var idx := _import_audio_option.item_count
		_import_audio_option.add_item(audio_path.get_file())
		_import_audio_option.set_item_metadata(idx, audio_path)

	var selected_idx := 0
	if not _pending_import_audio_path.is_empty():
		for i in range(_import_audio_option.item_count):
			if str(_import_audio_option.get_item_metadata(i)) == _pending_import_audio_path:
				selected_idx = i
				break
	_import_audio_option.select(selected_idx)
	_pending_import_audio_path = _selected_import_audio_source_path()


func _populate_import_source_options(result: Dictionary) -> void:
	_import_source_option.clear()
	var entries: Array = result.get("entries", []) as Array
	for i in range(entries.size()):
		var entry: Dictionary = entries[i] as Dictionary
		var instrument: String = ChartImportUtils.instrument_label(str(entry.get("instrument", "")))
		var label: String = "%s — %s (%d notes)" % [
			instrument,
			str(entry.get("difficulty", "expert")).capitalize(),
			(entry.get("notes", []) as Array).size()
		]
		_import_source_option.add_item(label)
		_import_source_option.set_item_metadata(i, i)
	if _import_source_option.item_count > 0:
		_import_source_option.select(0)


func _populate_import_difficulty_options(result: Dictionary) -> void:
	_import_difficulty_option.clear()
	for diff in ChartValidator.SUPPORTED_DIFFICULTIES:
		_import_difficulty_option.add_item(diff)
	var default_diff := 0
	var entries: Array = result.get("entries", []) as Array
	if not entries.is_empty():
		var source_diff: String = str((entries[0] as Dictionary).get("difficulty", "expert"))
		default_diff = maxi(0, ChartValidator.SUPPORTED_DIFFICULTIES.find(source_diff))
	_import_difficulty_option.select(default_diff)
	_import_warning_label.text = "Importing overwrites only the selected target difficulty. Source: %s" % _pending_import_path.get_file()


func _active_import_result() -> Dictionary:
	return _pending_import_preview_result if not _pending_import_preview_result.is_empty() else _pending_import_result


func _is_pending_midi_import() -> bool:
	var ext := _pending_import_path.get_extension().to_lower()
	return ext == "mid" or ext == "midi" or str(_pending_import_result.get("import_type", "")) == "midi"


func _is_package_import_path(path: String) -> bool:
	var ext := path.get_extension().to_lower()
	return ext == "sng" or ext == "osz" or ext == "osk"


func _selected_import_audio_mode() -> String:
	if _import_audio_option == null or _import_audio_option.selected < 0:
		return IMPORT_AUDIO_NONE
	return str(_import_audio_option.get_item_metadata(_import_audio_option.selected))


func _selected_import_audio_source_path() -> String:
	var mode := _selected_import_audio_mode()
	if mode == IMPORT_AUDIO_AUTO or mode == IMPORT_AUDIO_NONE:
		return ""
	return mode


func _on_import_file_option_selected(index: int) -> void:
	if index < 0 or index >= _import_file_option.item_count:
		return
	var path := str(_import_file_option.get_item_metadata(index))
	if path.is_empty() or path == _pending_import_path:
		return
	_begin_import_inspection(path)


func _on_import_audio_option_selected(_index: int) -> void:
	_pending_import_audio_path = _selected_import_audio_source_path()
	_pending_import_waveform.clear()
	if _is_pending_midi_import():
		_prepare_pending_midi_waveform()
		MidiImportWizardControls.set_audio_available(_midi_import_controls, _pending_import_waveform.is_ready(), _midi_audio_unavailable_reason())
		_refresh_midi_import_preview()


func _midi_audio_unavailable_reason() -> String:
	if _pending_import_audio_path.is_empty():
		return "Audio comparison disabled: no linked audio file selected."
	if not _pending_import_waveform.is_ready():
		var reason := _pending_import_waveform.unsupported_reason()
		return "Audio comparison disabled: %s" % (reason if not reason.is_empty() else "waveform is not ready.")
	return ""


func _on_midi_import_options_changed() -> void:
	if _is_pending_midi_import():
		_refresh_midi_import_preview()


func _refresh_midi_import_preview() -> void:
	if not _is_pending_midi_import():
		return
	var options := MidiImportWizardControls.read_options(_midi_import_controls)
	var waveform: Variant = _pending_import_waveform if _pending_import_waveform.is_ready() else null
	var preview := ChartImportService.preview_import(_pending_import_path, _pending_import_result, options, waveform)
	if bool(preview.get("ok", false)):
		_pending_import_preview_result = preview
		_populate_import_source_options(_pending_import_preview_result)
		var entries: Array = _pending_import_preview_result.get("entries", []) as Array
		var entry: Dictionary = {}
		if not entries.is_empty():
			entry = entries[0] as Dictionary
		_import_warning_label.text = "MIDI preview: %d notes, %d lanes. Importing overwrites only the selected target difficulty." % [
			(entry.get("notes", []) as Array).size(),
			int(entry.get("lane_count", LaneCountResolver.DEFAULT_LANES)),
		]
	else:
		_pending_import_preview_result = {}
		_import_source_option.clear()
		_import_warning_label.text = "MIDI settings produced no notes: %s" % str(preview.get("error", "unknown error"))


func _popup_import_wizard() -> void:
	var viewport_size := get_viewport_rect().size
	var width := int(clampf(viewport_size.x * 0.48, 600.0, 820.0))
	var height := int(clampf(viewport_size.y * 0.72, 400.0, 700.0))
	_import_wizard_scroll.custom_minimum_size = Vector2(width - 70, maxf(220.0, float(height) - 150.0))
	_import_wizard_scroll.scroll_vertical = 0
	_import_wizard_dialog.popup_centered(Vector2i(width, height))


func _prepare_pending_midi_waveform() -> void:
	_pending_import_waveform.clear()
	var audio_path := _pending_import_audio_path
	if audio_path.is_empty():
		return
	var wav_path := audio_path
	if audio_path.get_extension().to_lower() != "wav":
		var converted := EditorAudioImporter.convert_to_wav(audio_path, _pending_project_folder.path_join("midi_import_waveform_cache.wav"))
		if not bool(converted.get("ok", false)):
			return
		wav_path = str(converted.get("path", ""))
	var wav: AudioStreamWAV = AudioStreamWAV.load_from_file(ProjectSettings.globalize_path(wav_path))
	if wav != null:
		_pending_import_waveform.prepare_from_stream(wav)


func _on_import_wizard_confirmed() -> void:
	if _pending_import_path.is_empty() or _pending_import_result.is_empty() or _pending_project_folder.is_empty():
		return
	var entry_index: int = int(_import_source_option.get_item_metadata(_import_source_option.selected))
	var target_difficulty: String = _import_difficulty_option.get_item_text(_import_difficulty_option.selected).strip_edges().to_lower()
	var selected_audio_mode := _selected_import_audio_mode()
	var selected_audio_source_path := _selected_import_audio_source_path()
	_show_loading("Importing chart", "Writing %s chart data..." % target_difficulty)
	var midi_options := MidiImportWizardControls.read_options(_midi_import_controls) if _is_pending_midi_import() else {}
	var midi_waveform: Variant = _pending_import_waveform if _is_pending_midi_import() and _pending_import_waveform.is_ready() else null
	var result: Dictionary = ChartImportService.apply_import(_pending_project_folder, _pending_import_path, _pending_import_result, entry_index, target_difficulty, midi_options, midi_waveform)
	if not bool(result.get("ok", false)):
		_hide_loading()
		_show_message("Chart Import Failed", str(result.get("error", "Unknown error.")))
		return

	var audio_status := "Audio: missing"
	var import_ext := _pending_import_path.get_extension().to_lower()
	if not selected_audio_source_path.is_empty():
		_update_loading("Importing linked audio...")
		var linked_audio_result: Dictionary = EditorAudioImporter.import_audio(selected_audio_source_path, _pending_project_folder)
		if bool(linked_audio_result.get("ok", false)):
			audio_status = "Audio: imported"
			_set_manifest_audio_path(_pending_project_folder, str(linked_audio_result.get("path", "")))
		else:
			audio_status = "Audio: import failed"
	elif selected_audio_mode == IMPORT_AUDIO_AUTO and (import_ext == "sng" or import_ext == "osz" or import_ext == "osk"):
		_update_loading("Extracting packaged chart assets...")
		var extracted_result: Dictionary = ChartImportService.extract_osz_assets(_pending_import_path, _pending_project_folder) if import_ext == "osz" or import_ext == "osk" else ChartImportService.extract_sng_assets(_pending_import_path, _pending_project_folder)
		_update_loading("Preparing packaged audio...")
		var audio_result: Dictionary = ChartImportService.import_osz_audio_if_available(extracted_result, _pending_project_folder) if import_ext == "osz" or import_ext == "osk" else ChartImportService.import_sng_audio_if_available(extracted_result, _pending_project_folder)
		if bool(audio_result.get("ok", false)) and not str(audio_result.get("path", "")).is_empty():
			audio_status = "Audio: imported"
			_set_manifest_audio_path(_pending_project_folder, str(audio_result.get("path", "")))
		elif not bool(audio_result.get("ok", false)):
			audio_status = "Audio: import failed"

	_hide_loading()
	_reload_local_songs()
	_apply_song_filter()
	_build_rows()
	_select_song_by_folder(_pending_project_folder)
	_refresh_status()
	_show_message(
		"Import Complete",
		"Project: %s\nChart: %s (%s)\n%s" % [
			_pending_project_folder.get_file(),
			_pending_import_path.get_file(),
			target_difficulty,
			audio_status,
		]
	)


func _select_song_by_folder(project_folder: String) -> void:
	for song in _songs:
		if str(song.get("root_path", "")) == project_folder:
			_selected_song = song
			break


func _make_unique_project_folder(folder_name: String) -> String:
	var base := SongResolver.CUSTOM_ROOT.path_join(folder_name)
	var suffix := 2
	var out := base
	while DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(out)):
		out = SongResolver.CUSTOM_ROOT.path_join("%s_%d" % [folder_name, suffix])
		suffix += 1
	return out


func _write_starter_project(project_folder: String, folder_name: String) -> void:
	var title: String = folder_name.replace("_", " ").strip_edges()
	if title.is_empty():
		title = folder_name
	var manifest: Dictionary = {
		"song_id": ChartImportUtils.sanitize_id(folder_name),
		"title": title,
		"artist": "Unknown Artist",
		"charter": "Unknown Charter",
		"bpm": 120.0,
		"offset": 0.0,
		"youtube_url": "",
		"difficulties": ["expert"],
	}
	ChartImportUtils.write_json(project_folder.path_join("manifest.json"), manifest)
	ChartImportUtils.write_json(project_folder.path_join("expert.json"), ChartImportUtils.chart_payload("expert", []))


func _set_manifest_audio_path(project_folder: String, audio_path: String) -> void:
	var manifest_path := project_folder.path_join("manifest.json")
	var manifest: Dictionary = {}
	if FileAccess.file_exists(manifest_path):
		var parsed: Variant = JSON.parse_string(FileAccess.open(manifest_path, FileAccess.READ).get_as_text())
		if parsed is Dictionary:
			manifest = parsed as Dictionary
	if audio_path.strip_edges().is_empty():
		manifest.erase("audio_path")
	else:
		manifest["audio_path"] = audio_path
	ChartImportUtils.write_json(manifest_path, manifest)


func _pick_chart_candidate(folder_abs: String) -> String:
	return ImportSourceScanner.first_chart_file(folder_abs)


func _pick_audio_candidate(folder_abs: String) -> String:
	return ImportSourceScanner.first_audio_file(folder_abs)


func _list_files_with_ext(folder_abs: String, exts: Array[String]) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(folder_abs)
	if dir == null:
		return out
	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name.is_empty():
			break
		if dir.current_is_dir():
			continue
		var lower := String(name).to_lower()
		for ext in exts:
			if lower.ends_with("." + ext):
				out.append(folder_abs.path_join(name))
				break
	dir.list_dir_end()
	out.sort()
	return out
