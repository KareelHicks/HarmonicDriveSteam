extends Control

const NoteSpeedRules = preload("res://scripts/gameplay/NoteSpeedRules.gd")

signal back_requested

const HDTheme := preload("res://scripts/ui/HDTheme.gd")
const ChartLoader := preload("res://scripts/gameplay/ChartLoader.gd")
const ChartValidator := preload("res://scripts/songs/ChartValidator.gd")
const AudioResolver := preload("res://scripts/songs/AudioResolver.gd")
const SongResolver := preload("res://scripts/songs/SongResolver.gd")
const LaneCountResolver := preload("res://scripts/songs/LaneCountResolver.gd")
const ChartMetadataResolver := preload("res://scripts/songs/ChartMetadataResolver.gd")

const GridSnapManager := preload("res://scripts/editor/GridSnapManager.gd")
const PlaybackController := preload("res://scripts/editor/PlaybackController.gd")
const WaveformRenderer := preload("res://scripts/editor/WaveformRenderer.gd")
const NotePlacementSystem := preload("res://scripts/editor/NotePlacementSystem.gd")
const SongDatabase := preload("res://scripts/songs/SongDatabase.gd")
const EditorLog := preload("res://scripts/editor/EditorLog.gd")
const BPMDetector := preload("res://scripts/editor/BPMDetector.gd")
const AutoChartGenerator := preload("res://scripts/editor/AutoChartGenerator.gd")
const ChartImportUtils := preload("res://scripts/editor/importers/ChartImportUtils.gd")
const ChartImportService := preload("res://scripts/editor/importers/ChartImportService.gd")
const MidiImportWizardControls := preload("res://scripts/editor/importers/MidiImportWizardControls.gd")
const EditorAudioImporter := preload("res://scripts/editor/importers/EditorAudioImporter.gd")
const ImportSourceScanner := preload("res://scripts/editor/importers/ImportSourceScanner.gd")
const DifficultyManager := preload("res://scripts/editor/DifficultyManager.gd")
const SongPackageManager := preload("res://scripts/editor/SongPackageManager.gd")
const EditorPlaytestManager := preload("res://scripts/editor/EditorPlaytestManager.gd")
const EditorLiveModeManager := preload("res://scripts/editor/EditorLiveModeManager.gd")
const EditorPreferenceStore := preload("res://scripts/editor/EditorPreferenceStore.gd")
const YouTubeAudioImporter := preload("res://scripts/editor/YouTubeAudioImporter.gd")
const HarmonicProjectPackage := preload("res://scripts/editor/HarmonicProjectPackage.gd")
const ChartWorkshopUploadDialog := preload("res://scripts/editor/ChartWorkshopUploadDialog.gd")
const ChartWorkshopManager := preload("res://scripts/editor/ChartWorkshopManager.gd")

const ANALYSIS_BUS_NAME := &"ChartEditorAnalysis"
const DEFAULT_PX_PER_SECOND := 140.0
const DEFAULT_VERTICAL_PX_PER_SECOND := 80.0
const PLAYBACK_TARGET_OFFSET_RATIO := 0.35
const MANUAL_REVEAL_CENTER_RATIO := 0.50
const SCROLL_UPDATE_THRESHOLD_PX := 0.5
const LAYOUT_OPTION_HORIZONTAL := 0
const LAYOUT_OPTION_VERTICAL := 1
const DIRECTION_OPTION_FALL_DOWN := 0
const DIRECTION_OPTION_RISE_UP := 1
const VERTICAL_VIEW_OPTION_GAMEPLAY_PREVIEW := 0
const VERTICAL_VIEW_OPTION_TIMELINE_ZOOM := 1
const TOOLBAR_COMPACT_HEIGHT := 820.0
const TOOLBAR_TIGHT_HEIGHT := 720.0
const EDITOR_CONTROL_MIN_HEIGHT := 30.0
const EDITOR_PLAY_BUTTON_MIN_WIDTH := 84.0
const IMPORT_AUDIO_AUTO := "__auto__"
const IMPORT_AUDIO_NONE := "__none__"
const AUDIO_LINK_IMPORT_CHART_NOW := "__import_chart_now__"
const WORKSHOP_MISSING_URL_DIALOG_SIZE := Vector2i(520, 220)
const WORKSHOP_MISSING_URL_WARNING := "YouTube URL configuration is missing.\n\nYou may still proceed to upload your chart to the Workshop, but the associated audio file will not be uploaded.\n\nDo you want to proceed?"
const CONTEXT_MOVE_SELECTION := 100
const CONTEXT_COPY_SELECTION := 101
const CONTEXT_DELETE_SELECTION := 102
const CONTEXT_CONVERT_TAP := 200
const CONTEXT_CHANGE_HOLD_DURATION := 201
const CONTEXT_CONVERT_HOLD := 202
const CONTEXT_MOVE_NOTE := 203
const CONTEXT_COPY_NOTE := 204
const CONTEXT_DELETE_NOTE := 205
const CONTEXT_SELECT_LANE := 300
const CONTEXT_SELECT_CHART := 301
const CONTEXT_SHIFT_LANE := 302
const CONTEXT_SHIFT_MULTIPLE_LANES := 303
const CONTEXT_COPY_LANE := 304
const CONTEXT_COPY_CHART := 305
const CONTEXT_DELETE_LANE := 306
const CONTEXT_DELETE_CHART := 307
const CONTEXT_SNAP_SELECTION := 308
const CONTEXT_SNAP_CHART := 309

@onready var _top_panel: PanelContainer = %TopPanel
@onready var _status_label: Label = %StatusLabel
@onready var _create_project_button: Button = %CreateProjectButton
@onready var _open_project_button: Button = %OpenProjectButton
@onready var _import_project_button: Button = %ImportProjectButton
@onready var _export_project_button: Button = %ExportProjectButton
@onready var _import_chart_button: Button = %ImportChartButton
@onready var _workshop_upload_button: Button = %WorkshopUploadButton
@onready var _reload_songs_button: Button = %ReloadSongsButton
@onready var _song_option: OptionButton = %SongOption
@onready var _difficulty_option: OptionButton = %DifficultyOption
@onready var _lane_count_option: OptionButton = %LaneCountOption
@onready var _clone_difficulty_button: Button = %CloneDifficultyButton
@onready var _chart_stats_button: Button = %ChartStatsButton
@onready var _help_button: Button = %HelpButton
@onready var _remove_selected_button: Button = %RemoveSelectedButton
@onready var _snap_option: OptionButton = %SnapOption
@onready var _back_button: Button = %BackButton
@onready var _play_button: Button = %PlayButton
@onready var _playtest_button: Button = %PlaytestButton
@onready var _live_editor_button: Button = %LiveEditorButton
@onready var _save_button: Button = %SaveButton
@onready var _save_as_button: Button = %SaveAsButton
@onready var _audio_option: OptionButton = %AudioOption
@onready var _browse_audio_button: Button = %BrowseAudioButton
@onready var _bpm_spin: SpinBox = %BPMSpin
@onready var _auto_bpm_button: Button = %AutoBPMButton
@onready var _auto_chart_button: Button = %AutoChartButton
@onready var _scroll: ScrollContainer = %TimelineScroll
@onready var _timeline: TimelineView = %TimelineView
@onready var _audio_player: AudioStreamPlayer = %AudioPlayer
@onready var _audio_file_dialog: FileDialog = %AudioFileDialog
@onready var _auto_chart_file_dialog: FileDialog = %AutoChartFileDialog
@onready var _project_name_dialog: ConfirmationDialog = %ProjectNameDialog
@onready var _project_name_edit: LineEdit = %ProjectNameEdit
@onready var _project_folder_dialog: FileDialog = %ProjectFolderDialog
@onready var _chart_import_file_dialog: FileDialog = %ChartImportFileDialog
@onready var _save_as_file_dialog: FileDialog = %SaveAsFileDialog
@onready var _import_wizard_dialog: ConfirmationDialog = %ImportWizardDialog
@onready var _import_wizard_scroll: ScrollContainer = %ImportWizardScroll
@onready var _import_file_option: OptionButton = %ImportFileOption
@onready var _import_source_option: OptionButton = %ImportSourceOption
@onready var _import_audio_option: OptionButton = %ImportAudioOption
@onready var _import_difficulty_option: OptionButton = %ImportDifficultyOption
@onready var _import_warning_label: Label = %ImportWarningLabel
@onready var _message_dialog: AcceptDialog = %EditorMessageDialog
@onready var _help_dialog: AcceptDialog = %HelpDialog
@onready var _help_prev_button: Button = %HelpPrevButton
@onready var _help_next_button: Button = %HelpNextButton
@onready var _help_page_label: Label = %HelpPageLabel
@onready var _help_text: Label = %HelpTextLabel
@onready var _loading_overlay: ColorRect = %LoadingOverlay
@onready var _loading_title_label: Label = %LoadingTitleLabel
@onready var _loading_status_label: Label = %LoadingStatusLabel
@onready var _playtest_overlay: PanelContainer = %PlaytestOverlay
@onready var _playtest_close_button: Button = %PlaytestCloseButton
@onready var _playtest_runtime_holder: Control = %PlaytestRuntimeHolder
@onready var _live_editor_overlay: PanelContainer = %LiveEditorOverlay
@onready var _live_editor_close_button: Button = %LiveEditorCloseButton
@onready var _live_editor_runtime_holder: Control = %LiveEditorRuntimeHolder
@onready var _live_editor_start_pause_button: Button = %LiveEditorStartPauseButton
@onready var _live_editor_timeline_slider: HSlider = %LiveEditorTimelineSlider
@onready var _live_editor_speed_spin: SpinBox = %LiveEditorSpeedSpin
@onready var _live_editor_adding_toggle: CheckButton = %LiveEditorAddingToggle
@onready var _live_editor_remove_toggle: CheckButton = %LiveEditorRemoveToggle
@onready var _live_editor_timestamp_label: Label = %LiveEditorTimestampLabel
@onready var _live_editor_status_label: Label = %LiveEditorStatusLabel
@onready var _clone_difficulty_dialog: ConfirmationDialog = %CloneDifficultyDialog
@onready var _clone_from_option: OptionButton = %CloneFromOption
@onready var _clone_to_option: OptionButton = %CloneToOption
@onready var _clone_method_option: OptionButton = %CloneMethodOption
@onready var _clone_overwrite_check: CheckBox = %CloneOverwriteCheck
@onready var _speed_slider: HSlider = %SpeedSlider
@onready var _speed_value_label: Label = %SpeedValueLabel
@onready var _hold_threshold_label: Label = %HoldThresholdLabel
@onready var _hold_threshold_spin: SpinBox = %HoldThresholdSpin
@onready var _timestamp_label: Label = %TimestampLabel
@onready var _layout_option: OptionButton = %LayoutOption
@onready var _vertical_direction_option: OptionButton = %VerticalDirectionOption
@onready var _vertical_editor_root: VBoxContainer = %VerticalEditorRoot
@onready var _vertical_scroll: ScrollContainer = %VerticalHighwayScroll
@onready var _vertical_highway = %VerticalHighwayView
@onready var _bottom_minimap = %BottomMinimapView
@onready var _density_strip = %DensityStripView
@onready var _title_edit: LineEdit = %TitleEdit
@onready var _artist_edit: LineEdit = %ArtistEdit
@onready var _charter_edit: LineEdit = %CharterEdit
@onready var _difficulty_value_label: Label = %DifficultyValueLabel
@onready var _lanes_value_label: Label = %LanesValueLabel
@onready var _bpm_value_label: Label = %BPMValueLabel
@onready var _nps_value_label: Label = %NPSValueLabel
@onready var _tap_tool_button: Button = %TapToolButton
@onready var _hold_tool_button: Button = %HoldToolButton
@onready var _select_tool_button: Button = %SelectToolButton
@onready var _erase_tool_button: Button = %EraseToolButton
@onready var _vertical_view_mode_option: OptionButton = %VerticalViewModeOption
@onready var _track_width_slider: HSlider = %TrackWidthSlider
@onready var _track_width_value_label: Label = %TrackWidthValueLabel
@onready var _highway_zoom_slider: HSlider = %HighwayZoomSlider
@onready var _highway_zoom_value_label: Label = %HighwayZoomValueLabel
@onready var _layout_choice_dialog: ConfirmationDialog = %LayoutChoiceDialog
@onready var _layout_choice_option: OptionButton = %LayoutChoiceOption

var _grid := GridSnapManager.new()
var _playback := PlaybackController.new()
var _waveform := WaveformRenderer.new()
var _notes := NotePlacementSystem.new()
var _song_db := SongDatabase.new()

var _song_folder := ""
var _difficulty := "expert"
var _chart_path := ""
var _manifest_path := ""

var _px_per_second := DEFAULT_PX_PER_SECOND
var _chart_load_error := ""
var _song_entries: Array[Dictionary] = []
var _selected_song_id := ""
var _is_switching_song := false
var _audio_reason := ""
var _selected_audio_path := ""
var _active_audio_path := ""
var _analysis_bus_idx := -1
var _analysis_capture: AudioEffectCapture
var _analysis_in_progress := false
var _project_active := false
var _pending_import_path := ""
var _pending_import_folder := ""
var _pending_import_file_candidates: Array[String] = []
var _pending_import_audio_candidates: Array[String] = []
var _pending_import_audio_path := ""
var _pending_import_result: Dictionary = {}
var _pending_import_preview_result: Dictionary = {}
var _pending_import_waveform := WaveformRenderer.new()
var _midi_import_controls: Dictionary = {}
var _audio_link_dialog: ConfirmationDialog
var _audio_link_audio_option: OptionButton
var _audio_link_chart_option: OptionButton
var _audio_link_chart_file_dialog: FileDialog
var _audio_source_dialog: ConfirmationDialog
var _youtube_url_dialog: ConfirmationDialog
var _youtube_url_edit: LineEdit
var _import_project_file_dialog: FileDialog
var _export_project_file_dialog: FileDialog
var _workshop_upload_dialog: ChartWorkshopUploadDialog
var _workshop_missing_url_dialog: ConfirmationDialog
var _workshop_manager := ChartWorkshopManager.new()
var _pending_audio_import_folder := ""
var _pending_audio_link_chart_path := ""
var _context_menu: PopupMenu
var _context_note_id := -1
var _context_selected_ids: Array[int] = []
var _context_time_sec := 0.0
var _context_lane := 0
var _note_duration_dialog: ConfirmationDialog
var _note_duration_edit: LineEdit
var _note_move_dialog: ConfirmationDialog
var _note_move_time_edit: LineEdit
var _note_move_lane_edit: LineEdit
var _multi_move_dialog: ConfirmationDialog
var _multi_move_delta_time_edit: LineEdit
var _multi_move_delta_lane_edit: LineEdit
var _shift_lane_dialog: ConfirmationDialog
var _shift_lane_info_label: Label
var _shift_lane_target_option: OptionButton
var _shift_multi_dialog: ConfirmationDialog
var _shift_multi_rows: Array[Control] = []
var _shift_multi_checks: Array[CheckBox] = []
var _shift_multi_target_options: Array[OptionButton] = []
var _delete_chart_dialog: ConfirmationDialog
var _delete_chart_confirm_edit: LineEdit
var _start_charting_dialog: ConfirmationDialog
var _last_audio_missing_project := ""
var _new_project_start_prompt_requested := false
var _editor_busy := false
var _last_auto_bpm_audio_path := ""
var _loaded_session_folder := ""
var _loaded_session_chart_path := ""
var _session_load_generation := 0
var _playtest := EditorPlaytestManager.new()
var _live_editor := EditorLiveModeManager.new()
var _editor_layout := EditorPreferenceStore.LAYOUT_VERTICAL
var _vertical_direction := EditorPreferenceStore.DIRECTION_FALL_DOWN
var _vertical_view_mode := EditorPreferenceStore.VIEW_MODE_GAMEPLAY_PREVIEW
var _vertical_px_per_second := DEFAULT_VERTICAL_PX_PER_SECOND
var _vertical_tool := "tap"
var _vertical_track_width_scale := EditorPreferenceStore.DEFAULT_TRACK_WIDTH_SCALE
var _vertical_scroll_offset := 0.0
var _last_status_update_msec := 0
var _live_editor_notes_dirty := false
var _lane_count := LaneCountResolver.DEFAULT_LANES
var _loaded_chart_missing_lane_count := false
var _lane_count_dialog: ConfirmationDialog
var _lane_count_mode_option: OptionButton
var _lane_count_manual_option: OptionButton
var _auto_chart_preview_dialog: ConfirmationDialog
var _auto_chart_preview_label: Label
var _pending_auto_chart_result: Dictionary = {}
var _pending_auto_chart_audio_path := ""

var _help_pages: Array[String] = []
var _help_page_idx := 0


func _ready() -> void:
	await _show_loading("Initializing chart editor", "Preparing editor systems...")
	SongResolver.ensure_user_song_dirs()
	EditorLog.info("boot", "ChartEditorScene ready")
	_ensure_analysis_bus()

	_apply_style()
	if not get_viewport().size_changed.is_connected(_apply_responsive_editor_layout):
		get_viewport().size_changed.connect(_apply_responsive_editor_layout)
	_apply_responsive_editor_layout()
	_setup_snap_options()
	_setup_song_picker()
	_setup_project_controls()
	_setup_metadata_controls()
	_playtest.attach(_playtest_overlay, _playtest_close_button, _playtest_runtime_holder)
	_live_editor.attach(
		_live_editor_overlay,
		_live_editor_close_button,
		_live_editor_runtime_holder,
		_live_editor_start_pause_button,
		_live_editor_timeline_slider,
		_live_editor_speed_spin,
		_live_editor_adding_toggle,
		_live_editor_remove_toggle,
		_live_editor_timestamp_label,
		_live_editor_status_label
	)
	_live_editor.live_lane_event.connect(_on_live_editor_lane_event)
	_live_editor.live_adding_changed.connect(_on_live_editor_adding_changed)
	_live_editor.remove_note_requested.connect(_on_live_editor_remove_note_requested)
	_live_editor.live_mode_stopped.connect(_on_live_editor_stopped)
	_setup_difficulty_tools()
	_setup_auto_chart_controls()
	_setup_help()
	_setup_context_menu()
	_setup_start_charting_dialog()
	_setup_layout_controls()
	_setup_lane_count_controls()
	_setup_lane_count_migration_dialog()
	_setup_midi_import_controls()
	_setup_audio_link_dialog()
	_setup_audio_source_dialog()
	_setup_project_package_dialogs()
	_setup_workshop_upload_dialogs()
	_apply_editor_dialog_styles()

	_back_button.pressed.connect(_on_back_pressed)

	_playback.attach_player(_audio_player)
	_setup_speed_controls()
	_notes.attach_grid(_grid)
	_notes.set_lane_count(_lane_count)
	_setup_hold_threshold_control()

	_timeline.attach(_grid, _waveform)
	_timeline.set_lane_count(_lane_count)
	_apply_default_zoom()
	_timeline.time_clicked.connect(_on_time_clicked)
	_timeline.scrub_requested.connect(_on_scrub_requested)
	_timeline.zoom_requested.connect(_on_zoom_requested)
	_timeline.set_hold_place_mode(_notes.hold_mode)
	_timeline.hold_drag_started.connect(func(t: float, lane: int) -> void:
		if _editor_busy or _analysis_in_progress:
			return
		_notes.begin_hold_drag(t, lane)
	)
	_timeline.hold_drag_ended.connect(func(t: float, lane: int) -> void:
		if _editor_busy or _analysis_in_progress:
			return
		_notes.end_hold_drag(t, lane)
	)
	_timeline.selection_changed.connect(func(ids: Array) -> void:
		var typed: Array[int] = []
		for v in ids:
			typed.append(int(v))
		_notes.set_selected_ids(typed)
		_update_status()
	)
	_timeline.move_selected_requested.connect(func(dt: float, dlane: int) -> void:
		if _editor_busy or _analysis_in_progress:
			return
		_notes.move_selected(dt, dlane)
	)
	_timeline.copy_requested.connect(func() -> void:
		EditorLog.info("clipboard", "timeline copy_requested selected=%d" % _notes.get_selected_ids().size())
		_notes.copy_selected()
	)
	_timeline.paste_requested.connect(func(t: float) -> void:
		if _editor_busy or _analysis_in_progress:
			return
		EditorLog.info("clipboard", "timeline paste_requested at=%.3f" % t)
		_notes.paste_at(_grid.snap_time(t))
	)
	_timeline.scroll_nudge_requested.connect(func(delta_px: float) -> void:
		if _editor_busy or _analysis_in_progress:
			return
		_set_scroll_offset(_scroll.scroll_horizontal + delta_px)
	)
	_timeline.context_menu_requested.connect(_on_timeline_context_menu)
	_vertical_highway.attach(_grid, _waveform)
	_vertical_highway.set_lane_count(_lane_count)
	_vertical_highway.set_zoom(_vertical_px_per_second)
	_vertical_highway.set_view_mode(_vertical_view_mode)
	_refresh_gameplay_preview_settings()
	_vertical_highway.set_vertical_direction(_vertical_direction)
	_vertical_highway.set_track_width_scale(_vertical_track_width_scale)
	_vertical_highway.set_active_tool(_vertical_tool)
	_vertical_highway.time_clicked.connect(_on_time_clicked)
	_vertical_highway.scrub_requested.connect(_on_scrub_requested)
	_vertical_highway.zoom_requested.connect(_on_zoom_requested)
	_vertical_highway.hold_drag_started.connect(func(t: float, lane: int) -> void:
		if _editor_busy or _analysis_in_progress:
			return
		_notes.begin_hold_drag(t, lane)
	)
	_vertical_highway.hold_drag_ended.connect(func(t: float, lane: int) -> void:
		if _editor_busy or _analysis_in_progress:
			return
		_notes.end_hold_drag(t, lane)
	)
	_vertical_highway.selection_changed.connect(func(ids: Array) -> void:
		var typed: Array[int] = []
		for v in ids:
			typed.append(int(v))
		_notes.set_selected_ids(typed)
		_update_status()
	)
	_vertical_highway.move_selected_requested.connect(func(dt: float, dlane: int) -> void:
		if _editor_busy or _analysis_in_progress:
			return
		_notes.move_selected(dt, dlane)
	)
	_vertical_highway.copy_requested.connect(func() -> void:
		_notes.copy_selected()
	)
	_vertical_highway.paste_requested.connect(func(t: float) -> void:
		if _editor_busy or _analysis_in_progress:
			return
		_notes.paste_at(_grid.snap_time(t))
	)
	_vertical_highway.scroll_nudge_requested.connect(func(delta_px: float) -> void:
		if _editor_busy or _analysis_in_progress:
			return
		_set_vertical_scroll_offset(_vertical_scroll_offset + delta_px)
	)
	_vertical_highway.context_menu_requested.connect(_on_timeline_context_menu)
	_vertical_highway.delete_requested.connect(_on_vertical_delete_requested)
	_bottom_minimap.orientation = "horizontal"
	_bottom_minimap.scrub_requested.connect(_on_scrub_requested)
	_density_strip.orientation = "vertical"
	_density_strip.set_vertical_direction(_vertical_direction)
	_density_strip.scrub_requested.connect(_on_scrub_requested)

	_scroll.get_h_scroll_bar().value_changed.connect(func(v: float) -> void:
		_timeline.set_scroll_x(v)
		_update_minimap_window()
	)
	_vertical_scroll.get_v_scroll_bar().value_changed.connect(func(_v: float) -> void:
		_vertical_scroll.scroll_vertical = 0
	)

	_playback.position_changed.connect(func(t: float) -> void:
		_update_timestamp(t)
		if _editor_layout == EditorPreferenceStore.LAYOUT_VERTICAL:
			_vertical_highway.set_cursor_time(t)
			_bottom_minimap.set_cursor_time(t)
			_density_strip.set_cursor_time(t)
		else:
			_timeline.set_cursor_time(t)
		_reveal_time(t, _playback.is_playing())
		_update_status_throttled()
	)
	_playtest_button.pressed.connect(func() -> void:
		if not _project_active or _editor_busy or _analysis_in_progress:
			return
		_playback.pause()
		EditorLog.info("playtest", "requested difficulty=%s cursor=%.3f chart=%s" % [_difficulty, _playback.get_position(), _chart_path])
		EditorLog.info("playtest", "editor_notes=%d" % _notes.get_notes().size())
		# Ensure playtest uses the chart the user is editing.
		if not save_chart():
			return
		var manifest := _read_manifest()
		if manifest.is_empty():
			_status_label.text = "Playtest blocked: manifest missing."
			return
		EditorLog.info("playtest", "manifest song_id=%s title=%s audio_path=%s" % [str(manifest.get("song_id", "")), str(manifest.get("title", "")), str(manifest.get("audio_path", ""))])
		var start_time := _playback.get_position()
		var result: Dictionary = _playtest.start_for_project(_song_folder, manifest, _difficulty, start_time)
		if not bool(result.get("ok", false)):
			_status_label.text = "Playtest failed: %s" % str(result.get("error", ""))
	)
	_live_editor_button.pressed.connect(func() -> void:
		if not _project_active or _editor_busy or _analysis_in_progress:
			return
		if not _playback.has_audio() or _active_audio_path.is_empty():
			_status_label.text = "Live Editor blocked: load project audio first."
			return
		_playback.pause()
		var start_time := _playback.get_position()
		if not save_chart():
			return
		var manifest := _read_manifest()
		if manifest.is_empty():
			_status_label.text = "Live Editor blocked: manifest missing."
			return
		_live_editor_notes_dirty = false
		var result: Dictionary = _live_editor.start_for_project(
			_song_folder,
			manifest,
			_difficulty,
			start_time,
			_notes.get_notes(),
			_lane_count,
			_active_audio_path
		)
		if not bool(result.get("ok", false)):
			_status_label.text = "Live Editor failed: %s" % str(result.get("error", ""))
	)
	_playback.play_state_changed.connect(func(is_playing: bool) -> void:
		_play_button.text = "Pause" if is_playing else "Play"
		_update_timestamp(_playback.get_position())
		if is_playing:
			_reveal_time(_playback.get_position(), true)
		#EditorLog.info("playback", "state=%s" % ("playing" if is_playing else "paused"))
	)
	_playback.audio_loaded.connect(func(has_audio: bool, length_sec: float) -> void:
		_update_timestamp(_playback.get_position())
		_timeline.set_audio_length(length_sec)
		_vertical_highway.set_audio_length(length_sec)
		_bottom_minimap.set_audio_length(length_sec)
		_density_strip.set_audio_length(length_sec)
		_update_song_info(_read_manifest(), _current_chart_metadata())
		EditorLog.info("audio", "loaded=%s length=%.3f" % [str(has_audio), length_sec])
	)

	_notes.notes_changed.connect(func() -> void:
		if _live_editor.is_active():
			_live_editor_notes_dirty = true
			if not _live_editor.is_live_adding_enabled():
				_live_editor.replace_notes(_notes.get_notes())
			return
		_refresh_editor_note_views()
		#EditorLog.info("notes", "count=%d" % _notes.get_notes().size())
	)
	_notes.note_added.connect(func(note: Dictionary) -> void:
		if _live_editor.is_active() and _live_editor.is_live_adding_enabled():
			_live_editor.add_note(note)
	)
	_notes.selection_changed.connect(func(ids: Array) -> void:
		if _live_editor.is_active():
			return
		var typed: Array[int] = []
		for v in ids:
			typed.append(int(v))
		_timeline.set_selected_ids(typed)
		_vertical_highway.set_selected_ids(typed)
		_update_status()
	)
	_notes.undo_redo_state_changed.connect(func(_can_undo: bool, _can_redo: bool) -> void:
		if not _live_editor.is_active():
			_update_status()
	)

	_remove_selected_button.pressed.connect(func() -> void:
		if _editor_busy or _analysis_in_progress:
			return
		var removed := _notes.delete_selected()
		if removed > 0:
			_status_label.text = "Removed %d note(s)." % removed
		_update_status()
	)

	_play_button.pressed.connect(func() -> void:
		#EditorLog.info("ui", "Play button pressed")
		if _editor_busy or _analysis_in_progress:
			return
		_playback.toggle_play()
	)
	_browse_audio_button.pressed.connect(func() -> void:
		#EditorLog.info("ui", "Browse audio pressed")
		_show_audio_source_dialog()
	)
	_audio_file_dialog.file_selected.connect(func(path: String) -> void:
		_on_audio_file_selected(path)
	)
	_audio_option.item_selected.connect(func(_idx: int) -> void:
		_on_audio_option_selected()
	)
	_bpm_spin.value_changed.connect(_on_bpm_spin_changed)
	_auto_bpm_button.pressed.connect(_on_auto_bpm_pressed)
	_auto_chart_button.pressed.connect(_on_auto_chart_pressed)
	_auto_chart_file_dialog.file_selected.connect(_on_auto_chart_file_selected)
	_save_button.pressed.connect(_on_save_pressed)
	_save_as_button.pressed.connect(_on_save_as_pressed)
	_save_as_file_dialog.file_selected.connect(_on_save_as_file_selected)
	_save_as_file_dialog.custom_action.connect(_on_save_as_custom_action)
	_save_as_file_dialog.add_button("Save JSON Only", false, "save_json_only")

	_read_cmdline()
	if not _song_folder.is_empty():
		await _open_project_folder(_song_folder)
	else:
		_clear_session()
		_set_project_active(false)
	_update_status()
	_hide_loading()


func _setup_auto_chart_controls() -> void:
	_auto_chart_preview_dialog = ConfirmationDialog.new()
	_auto_chart_preview_dialog.title = "Auto Chart Preview"
	_auto_chart_preview_dialog.ok_button_text = "Apply Chart"
	add_child(_auto_chart_preview_dialog)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	_auto_chart_preview_dialog.add_child(margin)

	_auto_chart_preview_label = Label.new()
	_auto_chart_preview_label.custom_minimum_size = Vector2(620, 0)
	_auto_chart_preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	margin.add_child(_auto_chart_preview_label)

	_auto_chart_preview_dialog.confirmed.connect(_on_auto_chart_preview_confirmed)


func _setup_help() -> void:
	_help_pages = _build_help_pages()
	_help_page_idx = 0
	_help_button.pressed.connect(func() -> void:
		_help_page_idx = 0
		_update_help_page()
		_help_dialog.popup_centered_ratio(0.85)
	)
	_help_prev_button.pressed.connect(func() -> void:
		if _help_page_idx <= 0:
			return
		_help_page_idx -= 1
		_update_help_page()
	)
	_help_next_button.pressed.connect(func() -> void:
		if _help_page_idx >= _help_pages.size() - 1:
			return
		_help_page_idx += 1
		_update_help_page()
	)
	_update_help_page()


func _setup_context_menu() -> void:
	_context_menu = PopupMenu.new()
	add_child(_context_menu)
	_context_menu.id_pressed.connect(_on_context_menu_id_pressed)

	_note_duration_dialog = ConfirmationDialog.new()
	_note_duration_dialog.title = "Hold Duration (seconds)"
	add_child(_note_duration_dialog)
	var dur_vbox := VBoxContainer.new()
	_note_duration_dialog.add_child(dur_vbox)
	var dur_label := Label.new()
	dur_label.text = "Enter hold duration in seconds (e.g. 1.250)"
	dur_vbox.add_child(dur_label)
	_note_duration_edit = LineEdit.new()
	_note_duration_edit.placeholder_text = "1.000"
	dur_vbox.add_child(_note_duration_edit)
	_note_duration_dialog.confirmed.connect(_on_duration_confirmed)

	_note_move_dialog = ConfirmationDialog.new()
	_note_move_dialog.title = "Move Note"
	add_child(_note_move_dialog)
	var move_vbox := VBoxContainer.new()
	_note_move_dialog.add_child(move_vbox)
	var move_label := Label.new()
	move_label.text = "Move to absolute time and lane"
	move_vbox.add_child(move_label)
	_note_move_time_edit = LineEdit.new()
	_note_move_time_edit.placeholder_text = "22.576"
	move_vbox.add_child(_note_move_time_edit)
	_note_move_lane_edit = LineEdit.new()
	_note_move_lane_edit.placeholder_text = "Lane (0-7)"
	move_vbox.add_child(_note_move_lane_edit)
	_note_move_dialog.confirmed.connect(_on_move_single_confirmed)

	_multi_move_dialog = ConfirmationDialog.new()
	_multi_move_dialog.title = "Move Selection"
	add_child(_multi_move_dialog)
	var mm_vbox := VBoxContainer.new()
	_multi_move_dialog.add_child(mm_vbox)
	var mm_label := Label.new()
	mm_label.text = "Move selection by delta time and lane"
	mm_vbox.add_child(mm_label)
	_multi_move_delta_time_edit = LineEdit.new()
	_multi_move_delta_time_edit.placeholder_text = "Delta seconds (e.g. 0.250 or -0.250)"
	mm_vbox.add_child(_multi_move_delta_time_edit)
	_multi_move_delta_lane_edit = LineEdit.new()
	_multi_move_delta_lane_edit.placeholder_text = "Delta lane (e.g. 1 or -1)"
	mm_vbox.add_child(_multi_move_delta_lane_edit)
	_multi_move_dialog.confirmed.connect(_on_move_multi_confirmed)

	_shift_lane_dialog = ConfirmationDialog.new()
	_shift_lane_dialog.title = "Shift Selected Lane to New Lane"
	_shift_lane_dialog.ok_button_text = "Shift"
	add_child(_shift_lane_dialog)
	var shift_lane_vbox := VBoxContainer.new()
	shift_lane_vbox.add_theme_constant_override("separation", 8)
	_shift_lane_dialog.add_child(shift_lane_vbox)
	_shift_lane_info_label = Label.new()
	_shift_lane_info_label.text = "Shift all notes from the selected lane to:"
	shift_lane_vbox.add_child(_shift_lane_info_label)
	_shift_lane_target_option = OptionButton.new()
	_shift_lane_target_option.custom_minimum_size = Vector2(260, 0)
	shift_lane_vbox.add_child(_shift_lane_target_option)
	_shift_lane_dialog.confirmed.connect(_on_shift_lane_confirmed)

	_shift_multi_dialog = ConfirmationDialog.new()
	_shift_multi_dialog.title = "Shift Multiple Lanes"
	_shift_multi_dialog.ok_button_text = "Shift"
	add_child(_shift_multi_dialog)
	var shift_multi_vbox := VBoxContainer.new()
	shift_multi_vbox.add_theme_constant_override("separation", 8)
	_shift_multi_dialog.add_child(shift_multi_vbox)
	var shift_multi_label := Label.new()
	shift_multi_label.text = "Choose which source lanes to shift and their destination lanes."
	shift_multi_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	shift_multi_label.custom_minimum_size.x = 420.0
	shift_multi_vbox.add_child(shift_multi_label)
	var shift_multi_grid := GridContainer.new()
	shift_multi_grid.columns = 3
	shift_multi_grid.add_theme_constant_override("h_separation", 12)
	shift_multi_grid.add_theme_constant_override("v_separation", 6)
	shift_multi_vbox.add_child(shift_multi_grid)
	for header in ["Source", "Shift", "Destination"]:
		var header_label := Label.new()
		header_label.text = header
		shift_multi_grid.add_child(header_label)
	for lane_idx in range(LaneCountResolver.MAX_LANES):
		var source_label := Label.new()
		source_label.text = "Lane %d" % (lane_idx + 1)
		shift_multi_grid.add_child(source_label)
		var enabled_check := CheckBox.new()
		shift_multi_grid.add_child(enabled_check)
		var target_option := OptionButton.new()
		target_option.custom_minimum_size = Vector2(180, 0)
		shift_multi_grid.add_child(target_option)
		_shift_multi_rows.append(source_label)
		_shift_multi_checks.append(enabled_check)
		_shift_multi_target_options.append(target_option)
	_shift_multi_dialog.confirmed.connect(_on_shift_multi_lanes_confirmed)

	_delete_chart_dialog = ConfirmationDialog.new()
	_delete_chart_dialog.title = "Delete All Notes In Chart"
	_delete_chart_dialog.ok_button_text = "Delete"
	add_child(_delete_chart_dialog)
	var delete_chart_vbox := VBoxContainer.new()
	delete_chart_vbox.add_theme_constant_override("separation", 8)
	_delete_chart_dialog.add_child(delete_chart_vbox)
	var delete_chart_label := Label.new()
	delete_chart_label.text = "This will delete every note in the current chart. Type delete to confirm."
	delete_chart_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	delete_chart_label.custom_minimum_size.x = 420.0
	delete_chart_vbox.add_child(delete_chart_label)
	_delete_chart_confirm_edit = LineEdit.new()
	_delete_chart_confirm_edit.placeholder_text = "delete"
	delete_chart_vbox.add_child(_delete_chart_confirm_edit)
	_delete_chart_dialog.confirmed.connect(_on_delete_chart_confirmed)


func _setup_start_charting_dialog() -> void:
	_start_charting_dialog = ConfirmationDialog.new()
	_start_charting_dialog.title = "Start Charting"
	_start_charting_dialog.ok_button_text = "Import Audio"
	_start_charting_dialog.cancel_button_text = "Not Now"
	_start_charting_dialog.add_button("Import Chart + Audio", false, "import_chart_audio")
	add_child(_start_charting_dialog)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	_start_charting_dialog.add_child(margin)

	var label := Label.new()
	label.text = (
		"This new project has no audio yet.\n\n" +
		"Import audio to begin charting from scratch, or use Import Chart + Audio if you already have a chart package or chart file with matching audio."
	)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 520.0
	margin.add_child(label)

	_start_charting_dialog.confirmed.connect(_on_start_charting_import_audio)
	_start_charting_dialog.custom_action.connect(_on_start_charting_custom_action)


func _setup_layout_controls() -> void:
	_editor_layout = EditorPreferenceStore.get_layout_mode()
	_vertical_direction = EditorPreferenceStore.get_vertical_direction()
	_vertical_view_mode = EditorPreferenceStore.get_vertical_view_mode()
	_vertical_track_width_scale = EditorPreferenceStore.get_track_width_scale()

	_layout_option.clear()
	_layout_option.add_item("Horizontal Timeline", LAYOUT_OPTION_HORIZONTAL)
	_layout_option.add_item("Vertical Highway", LAYOUT_OPTION_VERTICAL)
	_layout_option.select(1 if _editor_layout == EditorPreferenceStore.LAYOUT_VERTICAL else 0)
	_layout_option.item_selected.connect(func(idx: int) -> void:
		var id := _layout_option.get_item_id(idx)
		var mode := EditorPreferenceStore.LAYOUT_VERTICAL if id == LAYOUT_OPTION_VERTICAL else EditorPreferenceStore.LAYOUT_HORIZONTAL
		_set_editor_layout(mode, true)
	)

	_vertical_direction_option.clear()
	_vertical_direction_option.add_item("Notes Fall Down", DIRECTION_OPTION_FALL_DOWN)
	_vertical_direction_option.add_item("Notes Rise Up", DIRECTION_OPTION_RISE_UP)
	_vertical_direction_option.select(1 if _vertical_direction == EditorPreferenceStore.DIRECTION_RISE_UP else 0)
	_vertical_direction_option.item_selected.connect(func(idx: int) -> void:
		var id := _vertical_direction_option.get_item_id(idx)
		_set_vertical_direction(EditorPreferenceStore.DIRECTION_RISE_UP if id == DIRECTION_OPTION_RISE_UP else EditorPreferenceStore.DIRECTION_FALL_DOWN, true)
	)
	_vertical_view_mode_option.clear()
	_vertical_view_mode_option.add_item("Gameplay Preview", VERTICAL_VIEW_OPTION_GAMEPLAY_PREVIEW)
	_vertical_view_mode_option.add_item("Timeline Zoom", VERTICAL_VIEW_OPTION_TIMELINE_ZOOM)
	_vertical_view_mode_option.select(0 if _vertical_view_mode == EditorPreferenceStore.VIEW_MODE_GAMEPLAY_PREVIEW else 1)
	_vertical_view_mode_option.item_selected.connect(func(idx: int) -> void:
		var id := _vertical_view_mode_option.get_item_id(idx)
		_set_vertical_view_mode(EditorPreferenceStore.VIEW_MODE_GAMEPLAY_PREVIEW if id == VERTICAL_VIEW_OPTION_GAMEPLAY_PREVIEW else EditorPreferenceStore.VIEW_MODE_TIMELINE_ZOOM, true)
	)
	_track_width_slider.value = _vertical_track_width_scale
	_track_width_value_label.text = "%d%%" % int(roundf(_vertical_track_width_scale * 100.0))
	_track_width_slider.value_changed.connect(func(value: float) -> void:
		_set_vertical_track_width(value, true)
	)
	_highway_zoom_slider.value = _vertical_px_per_second
	_highway_zoom_value_label.text = "%dpx/s" % int(roundf(_vertical_px_per_second))
	_highway_zoom_slider.value_changed.connect(func(value: float) -> void:
		_set_vertical_zoom(value, true)
	)

	_layout_choice_option.clear()
	_layout_choice_option.add_item("Vertical Highway Mode", LAYOUT_OPTION_VERTICAL)
	_layout_choice_option.add_item("Horizontal Timeline Mode", LAYOUT_OPTION_HORIZONTAL)
	_layout_choice_option.select(0 if _editor_layout == EditorPreferenceStore.LAYOUT_VERTICAL else 1)
	_layout_choice_dialog.confirmed.connect(func() -> void:
		var id := _layout_choice_option.get_item_id(_layout_choice_option.selected)
		var mode := EditorPreferenceStore.LAYOUT_VERTICAL if id == LAYOUT_OPTION_VERTICAL else EditorPreferenceStore.LAYOUT_HORIZONTAL
		EditorPreferenceStore.mark_layout_prompt_shown()
		_set_editor_layout(mode, true)
	)

	for button in [_tap_tool_button, _hold_tool_button, _select_tool_button, _erase_tool_button]:
		(button as Button).toggle_mode = true
	_tap_tool_button.pressed.connect(func() -> void:
		_set_vertical_tool("tap")
	)
	_hold_tool_button.pressed.connect(func() -> void:
		_set_vertical_tool("hold")
	)
	_select_tool_button.pressed.connect(func() -> void:
		_set_vertical_tool("select")
	)
	_erase_tool_button.pressed.connect(func() -> void:
		_set_vertical_tool("erase")
	)

	_bottom_minimap.set_vertical_direction(_vertical_direction)
	_density_strip.set_vertical_direction(_vertical_direction)
	_set_vertical_track_width(_vertical_track_width_scale, false)
	_set_vertical_view_mode(_vertical_view_mode, false)
	_set_vertical_tool(_vertical_tool)
	_apply_editor_layout()


func _setup_lane_count_controls() -> void:
	_lane_count_option.clear()
	for count in range(LaneCountResolver.MIN_LANES, LaneCountResolver.MAX_LANES + 1):
		_lane_count_option.add_item("%d lanes" % count, count)
	_lane_count_option.item_selected.connect(func(idx: int) -> void:
		var count := _lane_count_option.get_item_id(idx)
		_set_lane_count(count, true)
	)
	_select_lane_count_option(_lane_count)


func _setup_lane_count_migration_dialog() -> void:
	_lane_count_dialog = ConfirmationDialog.new()
	_lane_count_dialog.title = "Choose Chart Lane Count"
	_lane_count_dialog.ok_button_text = "Apply"
	add_child(_lane_count_dialog)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	_lane_count_dialog.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)
	var label := Label.new()
	label.text = "This older chart does not specify lane_count. Choose a lane count, or infer it from the notes."
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 420.0
	vbox.add_child(label)
	_lane_count_mode_option = OptionButton.new()
	_lane_count_mode_option.add_item("Infer From Notes", 0)
	_lane_count_mode_option.add_item("Choose Manually", 1)
	vbox.add_child(_lane_count_mode_option)
	_lane_count_manual_option = OptionButton.new()
	for count in range(LaneCountResolver.MIN_LANES, LaneCountResolver.MAX_LANES + 1):
		_lane_count_manual_option.add_item("%d lanes" % count, count)
	_lane_count_manual_option.select(LaneCountResolver.DEFAULT_LANES - LaneCountResolver.MIN_LANES)
	vbox.add_child(_lane_count_manual_option)
	_lane_count_mode_option.item_selected.connect(func(idx: int) -> void:
		_lane_count_manual_option.visible = _lane_count_mode_option.get_item_id(idx) == 1
	)
	_lane_count_dialog.confirmed.connect(_on_lane_count_migration_confirmed)
	_lane_count_manual_option.visible = false


func _setup_midi_import_controls() -> void:
	_midi_import_controls = MidiImportWizardControls.create()
	var root := _midi_import_controls.get("root") as Control
	var parent := _import_warning_label.get_parent() as VBoxContainer
	if parent != null and root != null:
		parent.add_child(root)
	MidiImportWizardControls.connect_changed(_midi_import_controls, Callable(self, "_on_midi_import_options_changed"))


func _setup_audio_link_dialog() -> void:
	_audio_link_dialog = ConfirmationDialog.new()
	_audio_link_dialog.title = "Import Audio"
	_audio_link_dialog.ok_button_text = "Import"
	_audio_link_dialog.min_size = Vector2i(640, 360)
	add_child(_audio_link_dialog)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	_audio_link_dialog.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	var info := Label.new()
	info.text = "Choose the audio file to import. You can also import a chart now or link a chart from the same folder."
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size.x = 540.0
	vbox.add_child(info)

	var audio_label := Label.new()
	audio_label.text = "Audio file"
	vbox.add_child(audio_label)

	_audio_link_audio_option = OptionButton.new()
	_audio_link_audio_option.custom_minimum_size = Vector2(480, 0)
	vbox.add_child(_audio_link_audio_option)

	var chart_label := Label.new()
	chart_label.text = "Optional chart file"
	vbox.add_child(chart_label)

	_audio_link_chart_option = OptionButton.new()
	_audio_link_chart_option.custom_minimum_size = Vector2(540, 0)
	vbox.add_child(_audio_link_chart_option)

	_audio_link_chart_file_dialog = FileDialog.new()
	_audio_link_chart_file_dialog.title = "Import Chart"
	_audio_link_chart_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_audio_link_chart_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_audio_link_chart_file_dialog.filters = PackedStringArray([
		"*.osz, *.osk ; .osz/.osk beatmap package (*.osz, *.osk)",
		"*.osu ; .osu beatmap (*.osu)",
		"*.chart ; .chart chart file (*.chart)",
		"*.json ; Harmonic Drive chart (*.json)",
		"*.mid, *.midi ; MIDI chart (*.mid, *.midi)",
	])
	_audio_link_chart_file_dialog.use_native_dialog = true
	add_child(_audio_link_chart_file_dialog)
	_audio_link_chart_option.item_selected.connect(_on_audio_link_chart_option_selected)
	_audio_link_chart_file_dialog.file_selected.connect(_on_audio_link_chart_file_selected)
	_audio_link_dialog.confirmed.connect(_on_audio_link_dialog_confirmed)


func _setup_audio_source_dialog() -> void:
	_audio_source_dialog = ConfirmationDialog.new()
	_audio_source_dialog.title = "Import Audio"
	_audio_source_dialog.ok_button_text = "Local Audio File"
	_audio_source_dialog.cancel_button_text = "Cancel"
	_audio_source_dialog.add_button("YouTube URL", false, "youtube_url")
	add_child(_audio_source_dialog)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	_audio_source_dialog.add_child(margin)
	var label := Label.new()
	label.text = "Choose an audio source for this chart project."
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 440.0
	margin.add_child(label)
	_audio_source_dialog.confirmed.connect(_on_audio_source_local_selected)
	_audio_source_dialog.custom_action.connect(_on_audio_source_custom_action)

	_youtube_url_dialog = ConfirmationDialog.new()
	_youtube_url_dialog.title = "Import YouTube Audio"
	_youtube_url_dialog.ok_button_text = "Download"
	_youtube_url_dialog.cancel_button_text = "Cancel"
	add_child(_youtube_url_dialog)
	var yt_margin := MarginContainer.new()
	yt_margin.add_theme_constant_override("margin_left", 18)
	yt_margin.add_theme_constant_override("margin_top", 18)
	yt_margin.add_theme_constant_override("margin_right", 18)
	yt_margin.add_theme_constant_override("margin_bottom", 18)
	_youtube_url_dialog.add_child(yt_margin)
	var yt_vbox := VBoxContainer.new()
	yt_vbox.add_theme_constant_override("separation", 8)
	yt_margin.add_child(yt_vbox)
	var yt_label := Label.new()
	yt_label.text = "Paste a YouTube URL. Harmonic Drive will use yt-dlp to download .webm or .m4a audio, then FFmpeg to convert it to song.ogg for this local project."
	yt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	yt_label.custom_minimum_size.x = 560.0
	yt_vbox.add_child(yt_label)
	_youtube_url_edit = LineEdit.new()
	_youtube_url_edit.placeholder_text = "https://www.youtube.com/watch?v=..."
	_youtube_url_edit.custom_minimum_size = Vector2(560, 0)
	yt_vbox.add_child(_youtube_url_edit)
	_youtube_url_dialog.confirmed.connect(_on_youtube_url_confirmed)


func _setup_project_package_dialogs() -> void:
	_import_project_file_dialog = FileDialog.new()
	_import_project_file_dialog.title = "Import Harmonic Project"
	_import_project_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_import_project_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_import_project_file_dialog.filters = PackedStringArray(["*.harmonic ; Harmonic Drive project (*.harmonic)"])
	_import_project_file_dialog.file_selected.connect(_on_import_project_file_selected)
	add_child(_import_project_file_dialog)

	_export_project_file_dialog = FileDialog.new()
	_export_project_file_dialog.title = "Export Harmonic Project"
	_export_project_file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_export_project_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_export_project_file_dialog.filters = PackedStringArray(["*.harmonic ; Harmonic Drive project (*.harmonic)"])
	_export_project_file_dialog.file_selected.connect(_on_export_project_file_selected)
	add_child(_export_project_file_dialog)


func _setup_workshop_upload_dialogs() -> void:
	_workshop_upload_dialog = ChartWorkshopUploadDialog.new()
	_workshop_upload_dialog.upload_requested.connect(_on_workshop_upload_requested)
	add_child(_workshop_upload_dialog)
	_workshop_manager.upload_status_changed.connect(_on_workshop_upload_status_changed)

	_workshop_missing_url_dialog = ConfirmationDialog.new()
	_workshop_missing_url_dialog.title = "Upload Without YouTube URL"
	_workshop_missing_url_dialog.ok_button_text = "Proceed"
	_workshop_missing_url_dialog.cancel_button_text = "Cancel"
	_workshop_missing_url_dialog.min_size = Vector2i(500, 210)
	_workshop_missing_url_dialog.size = WORKSHOP_MISSING_URL_DIALOG_SIZE
	_workshop_missing_url_dialog.dialog_text = ""
	var missing_url_margin := MarginContainer.new()
	missing_url_margin.custom_minimum_size = Vector2(460, 124)
	missing_url_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	missing_url_margin.add_theme_constant_override("margin_left", 6)
	missing_url_margin.add_theme_constant_override("margin_right", 6)
	missing_url_margin.add_theme_constant_override("margin_top", 4)
	missing_url_margin.add_theme_constant_override("margin_bottom", 4)
	_workshop_missing_url_dialog.add_child(missing_url_margin)
	var missing_url_label := Label.new()
	missing_url_label.name = "WorkshopMissingUrlMessage"
	missing_url_label.text = WORKSHOP_MISSING_URL_WARNING
	missing_url_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	missing_url_label.custom_minimum_size = Vector2(448, 116)
	missing_url_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	missing_url_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	missing_url_margin.add_child(missing_url_label)
	_workshop_missing_url_dialog.confirmed.connect(_show_workshop_upload_dialog)
	add_child(_workshop_missing_url_dialog)


func _setup_metadata_controls() -> void:
	for edit in [_title_edit, _artist_edit, _charter_edit]:
		(edit as LineEdit).text_submitted.connect(func(_text: String) -> void:
			_commit_metadata_edits()
		)
		(edit as LineEdit).focus_exited.connect(_commit_metadata_edits)
	_set_metadata_controls_enabled(false)


func _set_metadata_controls_enabled(enabled: bool) -> void:
	for edit in [_title_edit, _artist_edit, _charter_edit]:
		if edit != null:
			(edit as LineEdit).editable = enabled


func _set_lane_count(count: int, mark_dirty: bool = false) -> void:
	_lane_count = LaneCountResolver.clamp_lane_count(count)
	AppState.sync_input_actions(_lane_count)
	_select_lane_count_option(_lane_count)
	_notes.set_lane_count(_lane_count)
	_timeline.set_lane_count(_lane_count)
	_vertical_highway.set_lane_count(_lane_count)
	_note_move_lane_edit.placeholder_text = "Lane (0-%d)" % (_lane_count - 1)
	if mark_dirty:
		_loaded_chart_missing_lane_count = false
	if _project_active:
		_update_song_info(_read_manifest(), _read_current_chart())
	_update_status()


func _select_lane_count_option(count: int) -> void:
	if _lane_count_option == null:
		return
	var clamped := LaneCountResolver.clamp_lane_count(count)
	for i in range(_lane_count_option.item_count):
		if _lane_count_option.get_item_id(i) == clamped:
			_lane_count_option.select(i)
			return


func _maybe_show_lane_count_migration_dialog() -> void:
	if not _loaded_chart_missing_lane_count:
		return
	if _lane_count_dialog == null or _lane_count_dialog.visible:
		return
	_lane_count_mode_option.select(0)
	_lane_count_manual_option.visible = false
	_lane_count_manual_option.select(_lane_count - LaneCountResolver.MIN_LANES)
	_lane_count_dialog.popup_centered()


func _on_lane_count_migration_confirmed() -> void:
	if _lane_count_mode_option.get_item_id(_lane_count_mode_option.selected) == 1:
		_set_lane_count(_lane_count_manual_option.get_item_id(_lane_count_manual_option.selected), true)
	else:
		_set_lane_count(LaneCountResolver.infer_from_notes(_notes.get_notes(), LaneCountResolver.DEFAULT_LANES), true)
	save_chart()


func _set_editor_layout(mode: String, persist: bool) -> void:
	_editor_layout = mode if mode == EditorPreferenceStore.LAYOUT_HORIZONTAL else EditorPreferenceStore.LAYOUT_VERTICAL
	if persist:
		EditorPreferenceStore.set_layout_mode(_editor_layout)
	_layout_option.select(1 if _editor_layout == EditorPreferenceStore.LAYOUT_VERTICAL else 0)
	_apply_editor_layout()
	_update_status()


func _apply_editor_layout() -> void:
	var vertical := _editor_layout == EditorPreferenceStore.LAYOUT_VERTICAL
	_scroll.visible = not vertical
	_vertical_editor_root.visible = vertical
	_vertical_direction_option.visible = vertical
	_apply_responsive_editor_layout()
	if vertical:
		_vertical_highway.set_cursor_time(_playback.get_position())
		_vertical_highway.set_notes(_notes.get_notes())
		_vertical_highway.set_selected_ids(_notes.get_selected_ids())
		_update_minimap_window()
		call_deferred("_reveal_time", _playback.get_position(), false)
	else:
		_timeline.set_cursor_time(_playback.get_position())
		call_deferred("_reveal_time", _playback.get_position(), false)


func _set_vertical_direction(direction: String, persist: bool) -> void:
	_vertical_direction = direction if direction == EditorPreferenceStore.DIRECTION_RISE_UP else EditorPreferenceStore.DIRECTION_FALL_DOWN
	if persist:
		EditorPreferenceStore.set_vertical_direction(_vertical_direction)
	_vertical_direction_option.select(1 if _vertical_direction == EditorPreferenceStore.DIRECTION_RISE_UP else 0)
	_vertical_highway.set_vertical_direction(_vertical_direction)
	_bottom_minimap.set_vertical_direction(_vertical_direction)
	_density_strip.set_vertical_direction(_vertical_direction)
	_reveal_time(_playback.get_position(), false)
	_update_minimap_window()
	_update_status()


func _set_vertical_view_mode(mode: String, persist: bool) -> void:
	_vertical_view_mode = mode if mode == EditorPreferenceStore.VIEW_MODE_GAMEPLAY_PREVIEW else EditorPreferenceStore.VIEW_MODE_TIMELINE_ZOOM
	if persist:
		EditorPreferenceStore.set_vertical_view_mode(_vertical_view_mode)
	_vertical_view_mode_option.select(0 if _vertical_view_mode == EditorPreferenceStore.VIEW_MODE_GAMEPLAY_PREVIEW else 1)
	_vertical_highway.set_view_mode(_vertical_view_mode)
	_refresh_gameplay_preview_settings()
	var timeline_mode := _vertical_view_mode == EditorPreferenceStore.VIEW_MODE_TIMELINE_ZOOM
	_highway_zoom_slider.editable = timeline_mode
	_highway_zoom_slider.modulate.a = 1.0 if timeline_mode else 0.45
	_highway_zoom_value_label.text = "%dpx/s" % int(roundf(_vertical_px_per_second)) if timeline_mode else "Density Timeline"
	_reveal_time(_playback.get_position(), false)
	_update_status()


func _refresh_gameplay_preview_settings() -> void:
	var speed_type := "classic"
	var base_ms := 600.0
	if ProfileStore != null:
		speed_type = ProfileStore.get_note_speed_type()
		base_ms = ProfileStore.get_note_approach_time_ms()
	var speed_value := 1.0
	if AppState != null and AppState.current_loadout is Dictionary:
		speed_value = float((AppState.current_loadout as Dictionary).get("speed_value", speed_value))
	if ProgressionManager != null:
		var loadout: Dictionary = ProgressionManager.get_equipped_loadout()
		speed_value = float(loadout.get("speed_value", speed_value))
	_vertical_highway.set_gameplay_approach_time(NoteSpeedRules.resolved_approach_time(
		speed_type,
		base_ms,
		speed_value,
		_difficulty
	))


func _set_vertical_track_width(value: float, persist: bool) -> void:
	_vertical_track_width_scale = clampf(value, 0.45, 1.0)
	if persist:
		EditorPreferenceStore.set_track_width_scale(_vertical_track_width_scale)
	_vertical_highway.set_track_width_scale(_vertical_track_width_scale)
	_track_width_slider.value = _vertical_track_width_scale
	_track_width_value_label.text = "%d%%" % int(roundf(_vertical_track_width_scale * 100.0))


func _set_vertical_zoom(value: float, preserve_cursor_screen_pos: bool) -> void:
	var cursor_time: float = _playback.get_position()
	var playhead_screen_y: float = float(_vertical_highway.time_to_y(cursor_time)) - _vertical_scroll_offset
	_vertical_px_per_second = clampf(value, 30.0, 2000.0)
	_vertical_highway.set_zoom(_vertical_px_per_second)
	if _highway_zoom_slider.value != _vertical_px_per_second:
		_highway_zoom_slider.value = _vertical_px_per_second
	if _vertical_view_mode == EditorPreferenceStore.VIEW_MODE_TIMELINE_ZOOM:
		_highway_zoom_value_label.text = "%dpx/s" % int(roundf(_vertical_px_per_second))
	if preserve_cursor_screen_pos:
		_set_vertical_scroll_offset(maxf(0.0, _vertical_highway.time_to_y(cursor_time) - playhead_screen_y))
	else:
		_reveal_time(cursor_time, false)
	_update_status()


func _set_vertical_tool(tool_id: String) -> void:
	_vertical_tool = tool_id
	_vertical_highway.set_active_tool(_vertical_tool)
	var buttons := {
		"tap": _tap_tool_button,
		"hold": _hold_tool_button,
		"select": _select_tool_button,
		"erase": _erase_tool_button,
	}
	for key in buttons.keys():
		var button: Button = buttons[key]
		button.button_pressed = key == _vertical_tool
		_apply_editor_button_style(button, key == _vertical_tool)
	_update_status()


func _maybe_show_layout_choice() -> void:
	if EditorPreferenceStore.has_shown_layout_prompt():
		return
	if _layout_choice_dialog.visible:
		return
	_layout_choice_option.select(0 if _editor_layout == EditorPreferenceStore.LAYOUT_VERTICAL else 1)
	_layout_choice_dialog.popup_centered()


func _on_vertical_delete_requested(time_sec: float, lane: int) -> void:
	if _editor_busy or _analysis_in_progress:
		return
	var tolerance := 0.05
	var step := _grid.seconds_per_step()
	if step > 0.0:
		tolerance = maxf(0.03, step * 0.5)
	if _notes.delete_nearest(_grid.snap_time(time_sec), lane, tolerance):
		_status_label.text = "Removed note."
	_update_status()


func _on_timeline_context_menu(note_id: int, global_pos: Vector2, time_sec: float, lane: int, selected_ids: Array) -> void:
	if _editor_busy or _analysis_in_progress:
		return
	_context_note_id = note_id
	_context_time_sec = time_sec
	_context_lane = lane
	_context_selected_ids = []
	for v in selected_ids:
		_context_selected_ids.append(int(v))

	_context_menu.clear()
	if _context_note_id < 0:
		_context_menu.add_item("Select All Notes In Lane", CONTEXT_SELECT_LANE)
		_context_menu.add_item("Select All Notes In Chart", CONTEXT_SELECT_CHART)
		_context_menu.add_separator()
		_context_menu.add_item("Snap Selection to Nearest Snappable Position", CONTEXT_SNAP_SELECTION)
		_context_menu.add_item("Snap All Notes to Nearest Snappable Position", CONTEXT_SNAP_CHART)
		_context_menu.add_separator()
		_context_menu.add_item("Shift Selected Lane to New Lane", CONTEXT_SHIFT_LANE)
		_context_menu.add_item("Shift Multiple Lanes", CONTEXT_SHIFT_MULTIPLE_LANES)
		_context_menu.add_separator()
		_context_menu.add_item("Copy All Notes In Selected Lane", CONTEXT_COPY_LANE)
		_context_menu.add_item("Copy All Notes in Chart", CONTEXT_COPY_CHART)
		_context_menu.add_separator()
		_context_menu.add_item("Delete All Notes In Selected Lane", CONTEXT_DELETE_LANE)
		_context_menu.add_item("Delete All Notes In Chart", CONTEXT_DELETE_CHART)
	elif _context_selected_ids.size() > 1:
		_context_menu.add_item("Move…", CONTEXT_MOVE_SELECTION)
		_context_menu.add_item("Copy", CONTEXT_COPY_SELECTION)
		_context_menu.add_item("Delete", CONTEXT_DELETE_SELECTION)
	else:
		var note := _notes.get_note(_context_note_id)
		var kind := str(note.get("type", "tap")).to_lower()
		if kind == "hold":
			_context_menu.add_item("Convert to Tap", CONTEXT_CONVERT_TAP)
			_context_menu.add_item("Change Hold Duration…", CONTEXT_CHANGE_HOLD_DURATION)
		else:
			_context_menu.add_item("Convert to Hold…", CONTEXT_CONVERT_HOLD)
		_context_menu.add_separator()
		_context_menu.add_item("Move…", CONTEXT_MOVE_NOTE)
		_context_menu.add_item("Copy", CONTEXT_COPY_NOTE)
		_context_menu.add_item("Delete", CONTEXT_DELETE_NOTE)
	_context_menu.position = global_pos - global_position
	_context_menu.popup()


func _on_context_menu_id_pressed(id: int) -> void:
	match id:
		CONTEXT_MOVE_SELECTION:
			_multi_move_delta_time_edit.text = "0.000"
			_multi_move_delta_lane_edit.text = "0"
			_multi_move_dialog.popup_centered()
		CONTEXT_COPY_SELECTION:
			_notes.copy_selected()
		CONTEXT_DELETE_SELECTION:
			_notes.delete_selected()
		CONTEXT_CONVERT_TAP:
			_notes.set_note_type(_context_note_id, "tap")
		CONTEXT_CHANGE_HOLD_DURATION:
			_note_duration_edit.text = str(float(_notes.get_note(_context_note_id).get("length", 1.0)))
			_note_duration_dialog.popup_centered()
		CONTEXT_CONVERT_HOLD:
			_note_duration_edit.text = "1.000"
			_note_duration_dialog.popup_centered()
		CONTEXT_MOVE_NOTE:
			var note := _notes.get_note(_context_note_id)
			_note_move_time_edit.text = "%.3f" % float(note.get("time", _context_time_sec))
			_note_move_lane_edit.text = str(int(note.get("lane", _context_lane)))
			_note_move_dialog.popup_centered()
		CONTEXT_COPY_NOTE:
			_notes.copy_selected()
		CONTEXT_DELETE_NOTE:
			_notes.delete_selected()
		CONTEXT_SELECT_LANE:
			var lane_ids := _notes.get_note_ids_in_lane(_context_lane)
			_notes.set_selected_ids(lane_ids)
			_status_label.text = "Selected %d note(s) in lane %d." % [lane_ids.size(), _context_lane + 1]
		CONTEXT_SELECT_CHART:
			var chart_ids := _notes.get_all_note_ids()
			_notes.set_selected_ids(chart_ids)
			_status_label.text = "Selected %d note(s) in chart." % chart_ids.size()
		CONTEXT_SNAP_SELECTION:
			_snap_selected_notes_to_grid()
		CONTEXT_SNAP_CHART:
			_snap_all_notes_to_grid()
		CONTEXT_SHIFT_LANE:
			_open_shift_lane_dialog()
		CONTEXT_SHIFT_MULTIPLE_LANES:
			_open_shift_multi_lanes_dialog()
		CONTEXT_COPY_LANE:
			var lane_copied := _notes.copy_lane(_context_lane)
			_status_label.text = "Copied %d note(s) from lane %d." % [lane_copied, _context_lane + 1]
		CONTEXT_COPY_CHART:
			var chart_copied := _notes.copy_all()
			_status_label.text = "Copied %d note(s) from chart." % chart_copied
		CONTEXT_DELETE_LANE:
			var lane_removed := _notes.delete_lane(_context_lane)
			_status_label.text = "Deleted %d note(s) from lane %d." % [lane_removed, _context_lane + 1]
		CONTEXT_DELETE_CHART:
			_open_delete_chart_dialog()


func _on_duration_confirmed() -> void:
	var duration := float(_note_duration_edit.text)
	if duration <= 0.0:
		duration = 0.001
	var note := _notes.get_note(_context_note_id)
	var kind := str(note.get("type", "tap")).to_lower()
	if kind == "hold":
		_notes.set_hold_length(_context_note_id, duration)
	else:
		_notes.set_note_type(_context_note_id, "hold", duration)


func _on_move_single_confirmed() -> void:
	var t := float(_note_move_time_edit.text)
	var l := int(_note_move_lane_edit.text)
	_notes.move_note_absolute(_context_note_id, t, l)


func _on_move_multi_confirmed() -> void:
	var dt := float(_multi_move_delta_time_edit.text)
	var dl := int(_multi_move_delta_lane_edit.text)
	_notes.move_selected(dt, dl)


func _open_shift_lane_dialog() -> void:
	_shift_lane_info_label.text = "Shift all notes from lane %d to:" % (_context_lane + 1)
	var default_target := _context_lane
	if _lane_count > 1:
		default_target = _context_lane + 1 if _context_lane < _lane_count - 1 else _context_lane - 1
	_populate_lane_option(_shift_lane_target_option, default_target)
	_shift_lane_dialog.popup_centered()


func _open_shift_multi_lanes_dialog() -> void:
	_populate_shift_multi_lanes_dialog()
	_shift_multi_dialog.popup_centered()


func _open_delete_chart_dialog() -> void:
	_delete_chart_confirm_edit.text = ""
	_delete_chart_dialog.popup_centered()
	_delete_chart_confirm_edit.call_deferred("grab_focus")


func _populate_lane_option(option: OptionButton, selected_lane: int) -> void:
	option.clear()
	var clamped := clampi(selected_lane, 0, maxi(0, _lane_count - 1))
	for lane_idx in range(_lane_count):
		option.add_item("Lane %d" % (lane_idx + 1), lane_idx)
	for i in range(option.item_count):
		if option.get_item_id(i) == clamped:
			option.select(i)
			return
	if option.item_count > 0:
		option.select(0)


func _populate_shift_multi_lanes_dialog() -> void:
	for lane_idx in range(_shift_multi_checks.size()):
		var visible := lane_idx < _lane_count
		(_shift_multi_rows[lane_idx] as Control).visible = visible
		_shift_multi_checks[lane_idx].visible = visible
		_shift_multi_target_options[lane_idx].visible = visible
		_shift_multi_checks[lane_idx].button_pressed = false
		_populate_lane_option(_shift_multi_target_options[lane_idx], lane_idx)


func _on_shift_lane_confirmed() -> void:
	var target_lane := int(_shift_lane_target_option.get_selected_id())
	var moved := _notes.shift_lane_to_lane(_context_lane, target_lane)
	_status_label.text = "Shifted %d note(s) from lane %d to lane %d." % [moved, _context_lane + 1, target_lane + 1]


func _on_shift_multi_lanes_confirmed() -> void:
	var mapping: Dictionary = {}
	for lane_idx in range(_lane_count):
		if not _shift_multi_checks[lane_idx].button_pressed:
			continue
		mapping[lane_idx] = int(_shift_multi_target_options[lane_idx].get_selected_id())
	var moved := _notes.shift_lanes(mapping)
	_status_label.text = "Shifted %d note(s) across selected lanes." % moved


func _on_delete_chart_confirmed() -> void:
	if _delete_chart_confirm_edit.text.strip_edges().to_lower() != "delete":
		_status_label.text = "Delete all cancelled: confirmation text did not match."
		return
	var removed := _notes.delete_all_notes()
	_status_label.text = "Deleted %d note(s) from chart." % removed


func _snap_selected_notes_to_grid() -> void:
	if _grid.division <= 0:
		_status_label.text = "Choose a snap step before snapping notes."
		return
	var selected_count := _notes.get_selected_ids().size()
	if selected_count <= 0:
		_status_label.text = "Snap selection: no notes selected."
		return
	var moved := _notes.snap_selected_to_grid()
	_update_status()
	_status_label.text = "Snapped %d of %d selected note(s) to %s." % [moved, selected_count, _grid.get_snap_string()]


func _snap_all_notes_to_grid() -> void:
	if _grid.division <= 0:
		_status_label.text = "Choose a snap step before snapping notes."
		return
	var total := _notes.get_note_count()
	if total <= 0:
		_status_label.text = "Snap chart: no notes in chart."
		return
	var moved := _notes.snap_all_to_grid()
	_update_status()
	_status_label.text = "Snapped %d of %d note(s) to %s." % [moved, total, _grid.get_snap_string()]


func _update_help_page() -> void:
	if _help_pages.is_empty():
		_help_page_label.text = "Page 0/0"
		_help_text.text = "No help content available."
		_help_prev_button.disabled = true
		_help_next_button.disabled = true
		return
	_help_page_idx = clampi(_help_page_idx, 0, _help_pages.size() - 1)
	_help_page_label.text = "Page %d/%d" % [_help_page_idx + 1, _help_pages.size()]
	_help_text.text = _help_pages[_help_page_idx]
	_help_prev_button.disabled = _help_page_idx == 0
	_help_next_button.disabled = _help_page_idx >= _help_pages.size() - 1


func _build_help_pages() -> Array[String]:
	var pages: Array[String] = []
	pages.append(
		"GETTING STARTED\n\n" +
		"PROJECTS\n" +
		"- Create New Project starts a custom song folder in user://custom_songs/.\n" +
		"- Open Project loads an existing project folder.\n" +
		"- Reload Songs refreshes projects after files are added or changed on disk.\n" +
		"- After opening a project or importing chart/audio, the editor resets to 0:00.\n\n" +
		"METADATA\n" +
		"- Edit Title, Artist, and Charter in the left info panel.\n" +
		"- Difficulty, lane count, BPM, and NPS are shown below the editable metadata.\n" +
		"- NPS is read-only and updates from the current chart's note density.\n" +
		"- Use the lane count dropdown to set the chart to 3-8 lanes.\n\n" +
		"SAVING AND PLAYTESTING\n" +
		"- Save or Ctrl+S / Cmd+S writes the current difficulty JSON into the project folder.\n" +
		"- Playtest runs gameplay inside the editor from the current project.\n" +
		"- Playtest saves the active difficulty first so gameplay uses the latest editor notes.\n" +
		"- Live Editor opens the actual gameplay view paused at the current cursor.\n" +
		"- Turn on Live Adding, press gameplay lane keys during playback, and release held keys to create holds.\n" +
		"- Turn Live Adding off to judge notes, build combo, and earn score at any selected playback speed.\n" +
		"- Seeking the Live Editor timeline starts a clean scoring pass for that section.\n" +
		"- The Live Editor speed field accepts exact values such as 0.60x; press Enter after typing.\n" +
		"- Pause playback before enabling Remove Notes, then click a visible note head to delete it."
	)
	pages.append(
		"IMPORTING CHARTS AND AUDIO\n\n" +
		"IMPORT CHART\n" +
		"- Supports .osz, .osk, .osu, .sng, .chart, .mid, and .midi.\n" +
		"- If the selected file's folder contains multiple supported chart files, choose which chart to import.\n" +
		"- If the folder contains supported audio files, choose which audio file to link.\n" +
		"- Source Chart selects the chart/difficulty inside the imported file or package.\n" +
		"- Target Harmonic Drive difficulty controls which local difficulty is overwritten.\n" +
		"- Importing overwrites only the selected target difficulty.\n\n" +
		"IMPORT AUDIO\n" +
		"- Supports .wav, .ogg, .mp3, and .opus. Opus is converted for project use.\n" +
		"- If the selected audio file's folder contains multiple supported audio files, choose which audio to import.\n" +
		"- If the folder contains supported chart files, choose an optional chart to link/import with the audio.\n\n" +
		"IMPORT WIZARD\n" +
		"- The Import Chart window scrolls when needed.\n" +
		"- Cancel and Import stay visible in the footer."
	)
	pages.append(
		"MIDI IMPORT\n\n" +
		"DEFAULT BEHAVIOR\n" +
		"- MIDI defaults to EDM taps: generic MIDI becomes tap notes instead of holds.\n" +
		"- Notes are mapped across the selected lane count, from 4 to 8 lanes when auto-lanes are used.\n\n" +
		"ADVANCED MIDI\n" +
		"- Track source: import all MIDI note tracks together or one specific MIDI track.\n" +
		"- Lane count: Auto, 4, 5, 6, 7, or 8 lanes.\n" +
		"- Lane mapping: pitch low-to-high, pitch high-to-low, pitch modulo, or channel-based.\n" +
		"- Note type: taps only, preserve MIDI durations as holds, or hold threshold mode.\n" +
		"- Hold threshold: minimum MIDI duration that becomes a hold in threshold mode.\n" +
		"- Minimum spacing: suppress notes that are too close together.\n" +
		"- Minimum velocity and Velocity priority control which MIDI notes survive filtering/thinning.\n" +
		"- Time offset shifts imported MIDI timing before it becomes chart notes.\n" +
		"- Max notes can cap dense MIDI files.\n\n" +
		"AUDIO COMPARISON\n" +
		"- Compare MIDI against audio appears when waveform data is available.\n" +
		"- Peak filter threshold removes MIDI notes that do not land near strong waveform peaks.\n" +
		"- Peak snap window moves MIDI notes to nearby audio peaks.\n" +
		"- Peak boost thinning prefers MIDI notes near louder peaks when thinning dense charts.\n" +
		"- Add missing audio peaks can add tap notes at strong peaks with no nearby MIDI note.\n" +
		"- Audio timing offset adjusts MIDI/audio alignment before comparison."
	)
	pages.append(
		"LAYOUTS AND NAVIGATION\n\n" +
		"LAYOUTS\n" +
		"- Switch between Vertical Highway and Horizontal Timeline in the toolbar.\n" +
		"- In Vertical Highway, choose Notes Fall Down or Notes Rise Up.\n" +
		"- Editor View Mode has two choices:\n" +
		"  - Gameplay Preview: spacing follows gameplay approach-time behavior.\n" +
		"  - Timeline Zoom: spacing uses the editor px/s zoom slider.\n" +
		"- Track Width adjusts the Vertical Highway lane area width.\n" +
		"- Spacing controls Timeline Zoom density up to 2000px/s. In Gameplay Preview it is automatic.\n\n" +
		"NAVIGATION\n" +
		"- Space: Play/Pause.\n" +
		"- Arrow Keys: step backward/forward by the current snap value.\n" +
		"- Mouse Wheel: zoom.\n" +
		"- Click the ruler, waveform, minimap, or Density Timeline to seek/scrub.\n" +
		"- The Density Timeline shows note density and can be used to jump around the song.\n" +
		"- Speed changes playback rate from 0.25x to 1.5x."
	)
	pages.append(
		"PLACING AND EDITING NOTES\n\n" +
		"VERTICAL HIGHWAY\n" +
		"- Tap tool: left-click an empty lane position to place a tap.\n" +
		"- Hold tool or Shift: click and drag to create a hold.\n" +
		"- Select tool: click notes or drag a selection box.\n" +
		"- Erase tool: click or drag over notes to remove them.\n" +
		"- While playback is stopped, placing notes in Vertical Highway does not move the judgement line or recenter the chart.\n\n" +
		"HORIZONTAL TIMELINE\n" +
		"- Left-click an empty lane position to place a tap.\n" +
		"- Shift or HOLD mode starts hold placement.\n" +
		"- Click notes to select them.\n" +
		"- Drag selected notes to move them; notes remain visible while dragging.\n" +
		"- The timeline only auto-scrolls while dragging a selection near the visible left/right edges.\n" +
		"- In Vertical Highway, drag above or below the chart to auto-scroll a marquee selection.\n\n" +
		"KEYBOARD LANE ENTRY\n" +
		"- TAP mode: quickly press a lane key for a tap, or hold it down and release for a hold.\n" +
		"- Hold multiple lane keys together to create simultaneous holds.\n" +
		"- Hold Threshold controls how many milliseconds a key must stay down to become a hold.\n" +
		"- Click the Hold Threshold number to enter an exact value, or use its arrows.\n" +
		"- HOLD mode also uses press-and-release hold placement.\n" +
		"- Quick press in HOLD mode places a tap.\n" +
		"- Ctrl+H / Cmd+H toggles HOLD/TAP mode.\n" +
		"- Shift temporarily uses hold placement."
	)
	pages.append(
		"SELECTION, COPY, AND BULK ACTIONS\n\n" +
		"SELECTION\n" +
		"- Click a note to select it.\n" +
		"- Shift-click adds or removes notes from the selection.\n" +
		"- Drag a selection box to select multiple notes.\n" +
		"- Press Delete/Backspace or Remove Selected to delete selected notes.\n\n" +
		"COPY/PASTE\n" +
		"- Copy selected notes: Ctrl+C / Cmd+C.\n" +
		"- Paste copied notes: Ctrl+V / Cmd+V.\n" +
		"- Paste places copied notes at the current cursor time.\n\n" +
		"EMPTY-LANE RIGHT-CLICK MENU\n" +
		"- Right-click inside a lane without hitting a note to open lane/chart actions.\n" +
		"- Select All Notes In Lane selects every note in that lane.\n" +
		"- Select All Notes In Chart selects every note in the chart.\n" +
		"- Shift Selected Lane to New Lane moves all notes from the clicked lane to a destination lane.\n" +
		"- Shift Multiple Lanes lets you choose several source lanes and their destination lanes.\n" +
		"- Copy All Notes In Selected Lane copies every note in the clicked lane.\n" +
		"- Copy All Notes in Chart copies the whole chart.\n" +
		"- Delete All Notes In Selected Lane deletes every note in the clicked lane.\n" +
		"- Delete All Notes In Chart asks you to type delete before clearing the chart."
	)
	pages.append(
		"RIGHT-CLICK NOTE ACTIONS AND UNDO\n\n" +
		"NOTE RIGHT-CLICK MENU\n" +
		"- Right-click a note to open note actions.\n" +
		"- Convert to Tap changes a hold into a tap.\n" +
		"- Convert to Hold opens duration entry for a tap.\n" +
		"- Change Hold Duration edits an existing hold length.\n" +
		"- Move opens absolute time/lane entry for a single note.\n" +
		"- When multiple notes are selected, right-click a selected note to Move, Copy, or Delete the selection.\n\n" +
		"UNDO/REDO\n" +
		"- Undo: Ctrl+Z / Cmd+Z.\n" +
		"- Redo: Ctrl+Y or Ctrl+Shift+Z / Cmd+Shift+Z.\n" +
		"- Large operations such as paste, lane shifts, and bulk deletes undo as single editor actions.\n\n" +
		"SNAP\n" +
		"- Snap is controlled by the Snap dropdown.\n" +
		"- Choose Off for exact timestamps."
	)
	pages.append(
			"TOOLS AND UTILITIES\n\n" +
			"- Audio source: choose Auto or a linked audio file for the project.\n" +
			"- Import Audio adds local audio or downloads from a YouTube URL for the current project.\n" +
			"- Export .harmonic shares the project without audio; Import .harmonic restores it and redownloads URL-backed audio.\n" +
			"- Upload Workshop exports an audio-free project for Steam Workshop.\n" +
			"- Auto BPM analyzes loaded audio and updates the BPM field.\n" +
		"- Clone Diff copies notes between difficulties.\n" +
		"- Smart Clone uses waveform analysis when available.\n" +
		"- Stats shows per-difficulty note counts and density.\n" +
		"- Use Menu to leave the chart editor safely."
	)
	return pages


func _on_back_pressed() -> void:
	# Stop editor playback + close overlays so we return cleanly to main menu.
	_playback.pause()
	if _audio_player != null:
		_audio_player.stop()
	_hide_loading()
	if _message_dialog != null:
		_message_dialog.hide()
	if _import_wizard_dialog != null:
		_import_wizard_dialog.hide()
	if _project_name_dialog != null:
		_project_name_dialog.hide()
	if _clone_difficulty_dialog != null:
		_clone_difficulty_dialog.hide()
	if _playtest_overlay != null and _playtest_overlay.visible:
		_playtest.stop()
	if _live_editor_overlay != null and _live_editor_overlay.visible:
		_live_editor.stop()
	back_requested.emit()


func _on_live_editor_lane_event(time_sec: float, lane: int, pressed: bool) -> void:
	if not _live_editor.is_active() or lane < 0 or lane >= _lane_count:
		return
	_notes.handle_keyboard_lane_event(maxf(0.0, time_sec), lane, false, pressed)


func _on_live_editor_adding_changed(enabled: bool) -> void:
	if enabled:
		_notes.begin_live_entry_batch()
	else:
		_notes.end_live_entry_batch()


func _on_live_editor_remove_note_requested(note_id: int) -> void:
	if not _live_editor.is_active() or not _live_editor.is_paused() \
			or not _live_editor.is_note_removal_enabled():
		return
	if _notes.delete_note(note_id):
		_live_editor_status_label.text = "Removed note %d. Undo remains available in the editor." % note_id


func _on_live_editor_stopped(position_sec: float) -> void:
	_notes.end_live_entry_batch()
	if _live_editor_notes_dirty:
		_refresh_editor_note_views()
		_live_editor_notes_dirty = false
	_playback.seek(position_sec)
	_update_timestamp(position_sec)
	_status_label.text = "Live Editor closed at %s." % _format_timestamp(position_sec)


func _refresh_editor_note_views() -> void:
	var notes_snapshot := _notes.get_notes()
	var selected_ids := _notes.get_selected_ids()
	_timeline.set_notes(notes_snapshot)
	_timeline.set_selected_ids(selected_ids)
	_vertical_highway.set_notes(notes_snapshot)
	_vertical_highway.set_selected_ids(selected_ids)
	_bottom_minimap.set_notes(notes_snapshot)
	_density_strip.set_notes(notes_snapshot)
	_update_song_info(_read_manifest(), _current_chart_metadata())
	_update_status()


func _process(delta: float) -> void:
	_playback.process_update()
	_live_editor.process_update()


func _input(event: InputEvent) -> void:
	# Global editor shortcuts. Using _input (not _unhandled_input) avoids cases where
	# focused Controls consume key events before they reach _unhandled_input.
	if (_playtest_overlay != null and _playtest_overlay.visible) \
			or (_live_editor_overlay != null and _live_editor_overlay.visible):
		return
	if not _project_active:
		return
	if _editor_busy or _analysis_in_progress:
		return
	# Avoid intercepting shortcuts while typing in text fields.
	var focused := get_viewport().gui_get_focus_owner()
	if focused is LineEdit:
		return
	# Lane placement uses the user's InputMap bindings (keyboard/controller/SteamDeck).
	# Key-down records the chart time; key-up resolves a quick press to a tap or a
	# sustained press to a hold. This intentionally does not depend on hard-coded keycodes.
	for lane in range(_lane_count):
		var action := "lane_%d" % lane
		if event.is_action_pressed(action):
			_notes.handle_keyboard_lane(_playback.get_position(), lane, event is InputEventKey and (event as InputEventKey).shift_pressed)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_released(action):
			_notes.handle_keyboard_lane_event(_playback.get_position(), lane, event is InputEventKey and (event as InputEventKey).shift_pressed, false)
			get_viewport().set_input_as_handled()
			return

	if event is not InputEventKey:
		return
	var k: InputEventKey = event as InputEventKey
	if not k.pressed or k.echo:
		return

	var mod_pressed := k.ctrl_pressed or k.meta_pressed
	if not mod_pressed:
		return

	# Copy/Paste (Cmd/Ctrl).
	if k.keycode == KEY_C:
		EditorLog.info("clipboard", "_input copy pressed selected=%d" % _notes.get_selected_ids().size())
		var copied := _notes.copy_selected()
		if copied > 0:
			_status_label.text = "Copied %d note(s)." % copied
			EditorLog.info("clipboard", "copied=%d" % copied)
		else:
			_status_label.text = "Copy: no notes selected."
			EditorLog.warn("clipboard", "copy no-op (nothing selected)")
		get_viewport().set_input_as_handled()
		return
	if k.keycode == KEY_V:
		var target_t := _grid.snap_time(_playback.get_position())
		EditorLog.info("clipboard", "_input paste pressed target=%.3f" % target_t)
		var pasted := _notes.paste_at(target_t)
		if pasted > 0:
			_status_label.text = "Pasted %d note(s)." % pasted
			EditorLog.info("clipboard", "pasted=%d" % pasted)
		else:
			_status_label.text = "Paste: clipboard empty."
			EditorLog.warn("clipboard", "paste no-op (clipboard empty)")
		get_viewport().set_input_as_handled()
		return


func _show_loading(title: String, detail: String) -> void:
	_set_editor_busy(true)
	_loading_title_label.text = title
	_loading_status_label.text = detail
	_loading_overlay.visible = true
	_status_label.text = "%s: %s" % [title, detail]
	await get_tree().process_frame


func _update_loading(detail: String) -> void:
	_loading_status_label.text = detail
	_status_label.text = "%s: %s" % [_loading_title_label.text, detail]
	await get_tree().process_frame


func _hide_loading() -> void:
	_loading_overlay.visible = false
	_set_editor_busy(false)


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


func _short_status(prefix: String, message: String, max_chars: int = 140) -> String:
	var text := message.replace("\n", " ").strip_edges()
	if text.length() > max_chars:
		text = text.substr(0, max_chars) + "..."
	return "%s: %s" % [prefix, text]


func _set_editor_busy(busy: bool) -> void:
	_editor_busy = busy
	if busy:
		_play_button.disabled = true
		_playtest_button.disabled = true
		_live_editor_button.disabled = true
		_save_button.disabled = true
		_save_as_button.disabled = true
		_import_chart_button.disabled = true
		_browse_audio_button.disabled = true
		_audio_option.disabled = true
		_auto_bpm_button.disabled = true
		_auto_chart_button.disabled = true
	else:
		_set_project_active(_project_active)


func _apply_default_zoom() -> void:
	_px_per_second = DEFAULT_PX_PER_SECOND
	_timeline.set_zoom(_px_per_second)
	_set_vertical_zoom(DEFAULT_VERTICAL_PX_PER_SECOND, false)
	_reveal_time(_playback.get_position(), false)


func _unhandled_input(event: InputEvent) -> void:
	if (_playtest_overlay != null and _playtest_overlay.visible) \
			or (_live_editor_overlay != null and _live_editor_overlay.visible):
		return
	if not _project_active:
		return
	if _editor_busy or _analysis_in_progress:
		return
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var k: InputEventKey = event as InputEventKey
		var mod_pressed := k.ctrl_pressed or k.meta_pressed
		if mod_pressed and k.keycode == KEY_Z:
			if k.shift_pressed:
				_notes.redo()
				_status_label.text = "Redid note changes"
			else:
				_notes.undo()
				_status_label.text = "Undo note changes"
			accept_event()
			return
		if mod_pressed and k.keycode == KEY_Y:
			_notes.redo()
			_status_label.text = "Redid note changes"
			accept_event()
			return
		if k.keycode == KEY_DELETE or k.keycode == KEY_BACKSPACE:
			var removed := _notes.delete_selected()
			if removed > 0:
				_status_label.text = "Removed %d note(s)." % removed
			accept_event()
			return
			if mod_pressed and k.keycode == KEY_C:
				EditorLog.info("clipboard", "shortcut copy pressed selected=%d" % _notes.get_selected_ids().size())
				var copied := _notes.copy_selected()
				if copied > 0:
					_status_label.text = "Copied %d note(s)." % copied
					EditorLog.info("clipboard", "copied=%d" % copied)
				else:
					_status_label.text = "Copy: no notes selected."
					EditorLog.warn("clipboard", "copy no-op (nothing selected)")
				accept_event()
				return
			if mod_pressed and k.keycode == KEY_V:
				var target_t := _grid.snap_time(_playback.get_position())
				EditorLog.info("clipboard", "shortcut paste pressed target=%.3f" % target_t)
				var pasted := _notes.paste_at(target_t)
				if pasted > 0:
					_status_label.text = "Pasted %d note(s)." % pasted
					EditorLog.info("clipboard", "pasted=%d" % pasted)
				else:
					_status_label.text = "Paste: clipboard empty."
					EditorLog.warn("clipboard", "paste no-op (clipboard empty)")
				accept_event()
				return
		if k.keycode == KEY_SPACE:
			#EditorLog.info("input", "Space play/pause")
			_playback.toggle_play()
			accept_event()
			return
		if k.keycode == KEY_S and k.ctrl_pressed:
			#EditorLog.info("input", "Ctrl+S save")
			await _save_chart_with_loading()
			accept_event()
			return
		if k.keycode == KEY_LEFT:
			#EditorLog.info("input", "Scrub left")
			var prev_time := _grid.prev_step_time(_playback.get_position())
			_playback.seek(prev_time)
			_reveal_time(prev_time, _playback.is_playing())
			accept_event()
			return
		if k.keycode == KEY_RIGHT:
			#EditorLog.info("input", "Scrub right")
			var next_time := _grid.next_step_time(_playback.get_position())
			_playback.seek(next_time)
			_reveal_time(next_time, _playback.is_playing())
			accept_event()
			return
		if k.keycode == KEY_H and (k.ctrl_pressed or k.meta_pressed):
			_notes.hold_mode = not _notes.hold_mode
			_timeline.set_hold_place_mode(_notes.hold_mode)
			#EditorLog.info("input", "HoldMode=%s" % str(_notes.hold_mode))
			_update_status()
			accept_event()
			return

		# Lane placement is handled via InputMap actions (lane_0..lane_7) in _input().


func _on_bpm_spin_changed(v: float) -> void:
	_grid.bpm = v
	#EditorLog.info("grid", "bpm override=%.3f" % _grid.bpm)
	_update_song_info(_read_manifest(), _current_chart_metadata())
	_update_status()


func _on_auto_bpm_pressed() -> void:
	await _show_loading("Analyzing audio", "Detecting BPM from loaded audio...")
	await _auto_detect_bpm(true, true)
	_hide_loading()


func _on_auto_chart_pressed() -> void:
	if not _project_active or _song_folder.is_empty():
		_status_label.text = "Open or create a project before auto charting."
		return
	var current_dir := ""
	if not _selected_audio_path.is_empty():
		current_dir = ProjectSettings.globalize_path(_selected_audio_path.get_base_dir()).simplify_path() if _selected_audio_path.begins_with("user://") or _selected_audio_path.begins_with("res://") else _selected_audio_path.get_base_dir().simplify_path()
	elif not _song_folder.is_empty():
		current_dir = ProjectSettings.globalize_path(_song_folder).simplify_path() if _song_folder.begins_with("user://") or _song_folder.begins_with("res://") else _song_folder.simplify_path()
	if not current_dir.is_empty():
		_auto_chart_file_dialog.current_dir = current_dir
	_auto_chart_file_dialog.popup_centered_ratio(0.7)


func _on_auto_chart_file_selected(path: String) -> void:
	if path.is_empty():
		return
	if path.get_extension().to_lower() != "wav":
		_show_message("Auto Chart Requires WAV", "Choose a .wav file for local Auto Chart analysis.")
		return
	if not _project_active or _song_folder.is_empty():
		_status_label.text = "Open or create a project before auto charting."
		return

	_pending_auto_chart_result = {}
	_pending_auto_chart_audio_path = ""
	await _show_loading("Auto Chart", "Importing WAV audio...")
	var import_result := _copy_audio_into_project(path)
	if not bool(import_result.get("ok", false)):
		_hide_loading()
		_show_message("Auto Chart Failed", "Audio import failed:\n%s" % str(import_result.get("error", "unknown error")))
		return

	_pending_auto_chart_audio_path = _selected_audio_path
	await _update_loading("Loading imported WAV...")
	var wav := _load_audio_stream(_selected_audio_path) as AudioStreamWAV
	if wav == null:
		_hide_loading()
		_show_message("Auto Chart Failed", "The selected audio was imported, but it could not be loaded as a WAV file.")
		return
	_playback.pause()
	_playback.set_stream(wav)
	_prepare_waveform_for_audio(_selected_audio_path, wav)
	_active_audio_path = _runtime_audio_path_for_loaded_audio(_selected_audio_path)
	_rebuild_audio_options(_read_manifest())
	_timeline.set_audio_length(_playback.length_sec())
	_vertical_highway.set_audio_length(_playback.length_sec())
	_bottom_minimap.set_audio_length(_playback.length_sec())
	_density_strip.set_audio_length(_playback.length_sec())

	await _update_loading("Analyzing waveform and generating notes...")
	var result := AutoChartGenerator.generate_from_wav(
		wav,
		_difficulty,
		_lane_count,
		_grid.bpm,
		_grid.offset,
		_auto_chart_seed_text(path)
	)
	_hide_loading()
	if not bool(result.get("ok", false)):
		_show_message("Auto Chart Failed", str(result.get("error", "Unknown auto chart error.")))
		return
	_pending_auto_chart_result = result
	_show_auto_chart_preview(result)


func _show_auto_chart_preview(result: Dictionary) -> void:
	if _auto_chart_preview_dialog == null or _auto_chart_preview_label == null:
		return
	var warnings: Array = result.get("warnings", []) as Array
	var warning_text := "None"
	if not warnings.is_empty():
		var warning_lines: Array[String] = []
		for warning in warnings:
			warning_lines.append(str(warning))
		warning_text = "\n".join(warning_lines)
	var existing_note_count := _notes.get_note_count()
	var replace_text := "This will replace %d existing note(s) in the active %s difficulty. Use Undo to restore them." % [
		existing_note_count,
		_difficulty,
	] if existing_note_count > 0 else "This will fill the active %s difficulty with generated notes." % _difficulty
	_auto_chart_preview_label.text = (
		"Audio: %s\n" % (_pending_auto_chart_audio_path.get_file() if not _pending_auto_chart_audio_path.is_empty() else "selected WAV") +
		"Difficulty: %s\n" % _difficulty +
		"BPM: %.3f\n" % float(result.get("bpm", _grid.bpm)) +
		"Offset: %.3fs\n" % float(result.get("offset", _grid.offset)) +
		"Confidence: %.2f\n" % float(result.get("confidence", 0.0)) +
		"Notes: %d total (%d taps, %d holds)\n" % [
			(result.get("notes", []) as Array).size(),
			int(result.get("tap_count", 0)),
			int(result.get("hold_count", 0)),
		] +
		"NPS: %.2f\n\n" % float(result.get("nps", 0.0)) +
		"%s\n\nWarnings:\n%s" % [replace_text, warning_text]
	)
	_auto_chart_preview_dialog.popup_centered(Vector2i(700, 430))


func _on_auto_chart_preview_confirmed() -> void:
	if _pending_auto_chart_result.is_empty():
		return
	var notes_var: Variant = _pending_auto_chart_result.get("notes", [])
	if notes_var is not Array:
		_show_message("Auto Chart Failed", "Generated notes were not in the expected format.")
		return
	var generated_notes: Array[Dictionary] = []
	for note_variant in notes_var:
		if note_variant is Dictionary:
			generated_notes.append((note_variant as Dictionary).duplicate(true))
	if generated_notes.is_empty():
		_show_message("Auto Chart Failed", "Generated chart had no notes to apply.")
		return

	var bpm := float(_pending_auto_chart_result.get("bpm", _grid.bpm))
	var offset := float(_pending_auto_chart_result.get("offset", _grid.offset))
	_grid.bpm = bpm
	_grid.offset = offset
	_bpm_spin.value = bpm
	_set_manifest_timing(bpm, offset)
	_notes.replace_notes(generated_notes)
	_reset_editor_view_to_start()
	_update_song_info(_read_manifest(), _current_chart_metadata())
	_status_label.text = "Auto Chart applied: %d notes. Save when ready." % generated_notes.size()
	_pending_auto_chart_result = {}
	_update_status()


func _auto_chart_seed_text(source_path: String) -> String:
	return "%s|%s|%s|%s|%d" % [
		_song_folder,
		_difficulty,
		source_path.get_file(),
		_pending_auto_chart_audio_path.get_file(),
		_lane_count,
	]


func _on_save_pressed() -> void:
	await _save_chart_with_loading()


func _on_save_as_pressed() -> void:
	if not _project_active or _song_folder.is_empty():
		return
	if not _chart_path.is_empty():
		_save_as_file_dialog.current_dir = ProjectSettings.globalize_path(_chart_path.get_base_dir()).simplify_path() if _chart_path.begins_with("user://") or _chart_path.begins_with("res://") else _chart_path.get_base_dir().simplify_path()
	else:
		_save_as_file_dialog.current_dir = ProjectSettings.globalize_path(_song_folder).simplify_path()
	_save_as_file_dialog.current_file = _chart_path.get_file() if not _chart_path.is_empty() else "%s.json" % _difficulty
	_save_as_file_dialog.root_subfolder = ""
	_save_as_file_dialog.popup_centered_ratio(0.7)


func _on_save_as_file_selected(path: String) -> void:
	var target := _normalize_chart_json_save_path(path)
	if target.is_empty():
		return
	await _save_chart_as(target)


func _on_save_as_custom_action(action: StringName) -> void:
	if action != &"save_json_only":
		return
	var target := _normalize_chart_json_save_path(_get_save_as_dialog_path())
	if target.is_empty():
		return
	_save_as_file_dialog.hide()
	await _save_chart_json_only(target)


func _save_chart_with_loading() -> void:
	_commit_metadata_edits()
	await _show_loading("Saving project", "Writing %s..." % _difficulty)
	save_chart()
	_hide_loading()


func _normalize_chart_json_save_path(path: String) -> String:
	if path.strip_edges().is_empty():
		return ""
	var selected := path.strip_edges()
	if selected.get_extension().is_empty():
		selected += ".json"
	if selected.get_extension().to_lower() != "json":
		_show_message("Save As Failed", "Chart filenames must end in .json.")
		return ""
	var filename := selected.get_file()
	if filename.is_empty() or filename.to_lower() == "manifest.json":
		_show_message("Save As Failed", "Choose a chart filename other than manifest.json.")
		return ""
	return selected


func _get_save_as_dialog_path() -> String:
	var selected := str(_save_as_file_dialog.current_path).strip_edges()
	if selected.is_empty() or selected == _save_as_file_dialog.current_dir:
		selected = _save_as_file_dialog.current_dir.path_join(_save_as_file_dialog.current_file)
	if selected.get_file().is_empty() and not _save_as_file_dialog.current_file.strip_edges().is_empty():
		selected = selected.path_join(_save_as_file_dialog.current_file.strip_edges())
	return selected


func _save_chart_as(target: String) -> void:
	_commit_metadata_edits()
	await _show_loading("Saving chart as", "Writing %s..." % target.get_file())
	var previous_path := _chart_path
	_chart_path = target
	var inside_project := _is_path_inside_current_project(target)
	var saved := save_chart(false)
	if saved:
		if inside_project:
			_ensure_manifest_has_difficulty(_difficulty)
			_set_manifest_chart_file(_difficulty, target.get_file())
			_load_project_options()
			_playtest.request_hot_reload()
			_status_label.text = "Saved %s as %s." % [_difficulty, target.get_file()]
		else:
			_chart_path = previous_path
			_status_label.text = "Saved JSON copy: %s" % target
	_hide_loading()


func _save_chart_json_only(target: String) -> void:
	_commit_metadata_edits()
	await _show_loading("Saving JSON only", "Writing %s..." % target.get_file())
	var previous_path := _chart_path
	_chart_path = target
	var saved := save_chart(false)
	_chart_path = previous_path
	if saved:
		_status_label.text = "Saved JSON only: %s" % target
	_hide_loading()


func _is_path_inside_current_project(path: String) -> bool:
	if _song_folder.is_empty() or path.strip_edges().is_empty():
		return false
	var project_abs := ProjectSettings.globalize_path(_song_folder).simplify_path()
	var path_abs := ProjectSettings.globalize_path(path).simplify_path() if path.begins_with("user://") or path.begins_with("res://") else path.simplify_path()
	return path_abs.begins_with(project_abs + "/")


func _on_time_clicked(time_sec: float, lane: int, button_index: int, shift: bool) -> void:
	var snapped := _grid.snap_time(time_sec)
	var preserve_vertical_preview_position := (
		_editor_layout == EditorPreferenceStore.LAYOUT_VERTICAL
		and not _playback.is_playing()
	)
	if not preserve_vertical_preview_position:
		_playback.seek(snapped)
		_reveal_time(snapped, _playback.is_playing())
	#EditorLog.info("mouse", "click button=%d lane=%d t=%.3f snapped=%.3f shift=%s" % [button_index, lane, time_sec, snapped, str(shift)])
	# Placement only (left click in chart area); deletion is via selection + Delete key/button.
	if shift or _notes.hold_mode:
		# Mouse hold placement is handled via click-drag in TimelineView when hold mode is enabled.
		# Fall back to a quick hold/tap placement when needed.
		_notes.handle_keyboard_lane_event(snapped, lane, true, true)
	else:
		_notes.place_tap(snapped, lane)


func _on_scrub_requested(time_sec: float) -> void:
	var snapped := _grid.snap_time(time_sec)
	#EditorLog.info("mouse", "scrub t=%.3f snapped=%.3f" % [time_sec, snapped])
	_playback.seek(snapped)
	_reveal_time(snapped, _playback.is_playing())


func _on_zoom_requested(multiplier: float, _at_local_x: float) -> void:
	if _editor_layout == EditorPreferenceStore.LAYOUT_VERTICAL:
		_set_vertical_zoom(_vertical_px_per_second * multiplier, true)
		var cursor_time: float = _playback.get_position()
		_reveal_time(cursor_time, _playback.is_playing())
		return
	var before := _px_per_second
	var cursor_time := _playback.get_position()
	var playhead_screen_x := cursor_time * before - _scroll.scroll_horizontal
	_px_per_second = clampf(_px_per_second * multiplier, 40.0, 1200.0)
	#EditorLog.info("mouse", "zoom multiplier=%.3f px_per_sec=%.1f" % [multiplier, _px_per_second])
	_timeline.set_zoom(_px_per_second)
	if _playback.is_playing():
		_reveal_time(cursor_time, true)
	else:
		_set_scroll_offset(maxf(0.0, cursor_time * _px_per_second - playhead_screen_x))
		_reveal_time(cursor_time, false)
	_update_status()


func _set_scroll_offset(offset: float) -> void:
	var clamped := maxf(0.0, offset)
	_scroll.scroll_horizontal = clamped
	_timeline.set_scroll_x(clamped)


func _reset_editor_view_to_start() -> void:
	_playback.seek(0.0)
	_timeline.set_cursor_time(0.0)
	_vertical_highway.set_cursor_time(0.0)
	_bottom_minimap.set_cursor_time(0.0)
	_density_strip.set_cursor_time(0.0)
	_set_scroll_offset(0.0)
	call_deferred("_reveal_time", 0.0, false)
	call_deferred("_update_minimap_window")


func _set_vertical_scroll_offset(offset: float) -> void:
	var view_h := maxf(1.0, _vertical_scroll.size.y)
	var content_h := maxf(_vertical_highway.content_height(), view_h)
	var clamped := clampf(offset, 0.0, maxf(content_h - view_h, 0.0))
	_vertical_scroll_offset = clamped
	if _vertical_scroll.scroll_vertical != 0:
		_vertical_scroll.scroll_vertical = 0
	_vertical_highway.set_scroll_y(clamped)
	_update_minimap_window()


func _reveal_time(time_sec: float, follow_playback: bool) -> void:
	if _editor_layout == EditorPreferenceStore.LAYOUT_VERTICAL:
		_reveal_vertical_time(time_sec, follow_playback)
		return
	_reveal_horizontal_time(time_sec, follow_playback)


func _reveal_horizontal_time(time_sec: float, follow_playback: bool) -> void:
	var view_w := maxf(1.0, _scroll.size.x)
	var clamped_time := maxf(0.0, time_sec)
	var time_x := clamped_time * _px_per_second
	var current_left := _scroll.scroll_horizontal
	var current_right := current_left + view_w
	var content_width := maxf(_timeline.custom_minimum_size.x, view_w)
	var max_offset := maxf(content_width - view_w, 0.0)

	var target_offset := NAN
	if follow_playback:
		target_offset = time_x - (view_w * PLAYBACK_TARGET_OFFSET_RATIO)
	elif time_x < current_left or time_x > current_right:
		target_offset = time_x - (view_w * MANUAL_REVEAL_CENTER_RATIO)

	if is_nan(target_offset):
		return

	var clamped_offset := clampf(target_offset, 0.0, max_offset)
	if absf(clamped_offset - current_left) <= SCROLL_UPDATE_THRESHOLD_PX:
		return

	_set_scroll_offset(clamped_offset)
	#if follow_playback:
		#EditorLog.info(
			#"scroll",
			#"left=%.1f right=%.1f x=%.1f target=%.1f follow=%s" % [
				#current_left,
				#current_right,
				#time_x,
				#clamped_offset,
				#str(follow_playback)
		#]
	#)


func _reveal_vertical_time(time_sec: float, follow_playback: bool) -> void:
	var view_h := maxf(1.0, _vertical_scroll.size.y)
	var clamped_time := maxf(0.0, time_sec)
	var time_y: float = float(_vertical_highway.time_to_y(clamped_time))
	var current_top := _vertical_scroll_offset
	var current_bottom := current_top + view_h
	var content_h := maxf(_vertical_highway.content_height(), view_h)
	var max_offset := maxf(content_h - view_h, 0.0)
	var gameplay_preview: bool = _vertical_highway.is_gameplay_preview_mode()

	var target_offset := NAN
	if gameplay_preview:
		target_offset = time_y - _vertical_highway.gameplay_judgement_line_y()
	elif follow_playback:
		target_offset = time_y - (view_h * 0.70)
	elif time_y < current_top or time_y > current_bottom:
		target_offset = time_y - (view_h * 0.58)

	if is_nan(target_offset):
		_update_minimap_window()
		return

	var clamped_offset := clampf(target_offset, 0.0, max_offset)
	if absf(clamped_offset - current_top) <= SCROLL_UPDATE_THRESHOLD_PX:
		_update_minimap_window()
		return

	_set_vertical_scroll_offset(clamped_offset)


func _update_minimap_window() -> void:
	var horizontal_start := _timeline.x_to_time(_scroll.scroll_horizontal)
	var horizontal_end := _timeline.x_to_time(_scroll.scroll_horizontal + maxf(1.0, _scroll.size.x))
	if _editor_layout == EditorPreferenceStore.LAYOUT_VERTICAL:
		var window: Vector2 = _vertical_highway.visible_time_window()
		_bottom_minimap.set_view_window(window.x, window.y)
		_density_strip.set_view_window(window.x, window.y)
	else:
		_bottom_minimap.set_view_window(horizontal_start, horizontal_end)
		_density_strip.set_view_window(horizontal_start, horizontal_end)


func _setup_snap_options() -> void:
	_snap_option.clear()
	for d in GridSnapManager.SUPPORTED_DIVISIONS:
		_snap_option.add_item("Off" if d <= 0 else "1/%d" % d)
	_snap_option.item_selected.connect(func(idx: int) -> void:
		var text := _snap_option.get_item_text(idx)
		_grid.set_snap_string(text)
		_update_status()
	)
	# Keep 1/4 as default, even with the added "Off" entry.
	var default_idx := maxi(0, GridSnapManager.SUPPORTED_DIVISIONS.find(4))
	_snap_option.select(default_idx)
	_grid.division = 4


func _setup_speed_controls() -> void:
	# Playback speed is always "Tape Style" (pitch changes with speed).
	_playback.set_speed_scale(float(_speed_slider.value))
	_speed_value_label.text = "%.2fx" % float(_speed_slider.value)
	_speed_slider.value_changed.connect(func(value: float) -> void:
		_playback.set_speed_scale(value)
		_speed_value_label.text = "%.2fx" % value
		_update_status()
	)


func _setup_hold_threshold_control() -> void:
	_hold_threshold_spin.min_value = float(NotePlacementSystem.MIN_KEYBOARD_HOLD_THRESHOLD_MSEC)
	_hold_threshold_spin.max_value = float(NotePlacementSystem.MAX_KEYBOARD_HOLD_THRESHOLD_MSEC)
	var saved_threshold := EditorPreferenceStore.get_keyboard_hold_threshold_msec()
	_hold_threshold_spin.set_value_no_signal(float(saved_threshold))
	_notes.set_keyboard_hold_threshold_msec(saved_threshold)
	_hold_threshold_spin.value_changed.connect(func(value: float) -> void:
		var threshold_msec := clampi(
			int(roundf(value)),
			NotePlacementSystem.MIN_KEYBOARD_HOLD_THRESHOLD_MSEC,
			NotePlacementSystem.MAX_KEYBOARD_HOLD_THRESHOLD_MSEC
		)
		_notes.set_keyboard_hold_threshold_msec(threshold_msec)
		EditorPreferenceStore.set_keyboard_hold_threshold_msec(threshold_msec)
		_update_status()
	)


func _apply_style() -> void:
	var palette := HDTheme.theme_palette("theme_neon")
	($Background as ColorRect).color = palette["background"]
	_top_panel.add_theme_stylebox_override("panel", HDTheme.overlay_panel_style())
	_help_dialog.add_theme_stylebox_override("panel", HDTheme.overlay_panel_style())
	(%HelpScroll as ScrollContainer).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_help_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_help_text.custom_minimum_size.x = 520.0
	for button in [
		_reload_songs_button,
		_create_project_button,
		_open_project_button,
		_import_project_button,
		_export_project_button,
		_import_chart_button,
		_workshop_upload_button,
		_back_button,
		_playtest_button,
		_live_editor_button,
		_live_editor_close_button,
		_save_button,
		_save_as_button,
		_browse_audio_button,
		_auto_bpm_button,
		_auto_chart_button,
		_clone_difficulty_button,
		_chart_stats_button,
		_help_button,
		_remove_selected_button,
		_help_prev_button,
		_help_next_button,
		_tap_tool_button,
		_hold_tool_button,
		_select_tool_button,
		_erase_tool_button,
	]:
		_apply_editor_button_style(button as Button, false)
	_apply_editor_button_style(_play_button, true)
	_apply_editor_button_style(_live_editor_start_pause_button, true)
	for option in [
		_audio_option,
		_snap_option,
		_layout_option,
		_vertical_direction_option,
		_vertical_view_mode_option,
		_song_option,
		_difficulty_option,
		_lane_count_option,
	]:
		_apply_editor_option_style(option as OptionButton)
	_apply_editor_spinbox_style(_bpm_spin)
	_apply_editor_spinbox_style(_hold_threshold_spin)
	_apply_editor_spinbox_style(_live_editor_speed_spin)
	HDTheme.apply_label(_status_label, "caption", HDTheme.TERTIARY, false)
	HDTheme.apply_label(_timestamp_label, "caption", HDTheme.SECONDARY, false)
	HDTheme.apply_label(_hold_threshold_label, "caption", HDTheme.TERTIARY, false)
	HDTheme.apply_label(_live_editor_timestamp_label, "caption", HDTheme.SECONDARY, false)
	HDTheme.apply_label(_live_editor_status_label, "caption", HDTheme.TERTIARY, false)
	for meta_label_name in ["TitleMetaLabel", "ArtistMetaLabel", "CharterMetaLabel", "DifficultyMetaLabel", "LanesMetaLabel", "BPMMetaLabel", "NPSMetaLabel"]:
		var meta_label := get_node_or_null("%" + meta_label_name) as Label
		if meta_label != null:
			HDTheme.apply_label(meta_label, "caption", HDTheme.TERTIARY, false)
	for value_label in [_difficulty_value_label, _lanes_value_label, _bpm_value_label, _nps_value_label]:
		HDTheme.apply_label(value_label, "caption", HDTheme.SECONDARY, false)
	for edit in [_title_edit, _artist_edit, _charter_edit]:
		_apply_editor_line_edit_style(edit as LineEdit)
	HDTheme.apply_label(_track_width_value_label, "caption", HDTheme.TERTIARY, false)
	HDTheme.apply_label(_help_page_label, "caption", HDTheme.TERTIARY, false)
	HDTheme.apply_label(_help_text, "body", HDTheme.SECONDARY, true)
	var help_ok := _help_dialog.get_ok_button()
	if help_ok != null:
		_apply_editor_button_style(help_ok, false)
		help_ok.add_theme_font_size_override("font_size", HDTheme.text_size("button_secondary", get_viewport_rect().size))
	_apply_compact_editor_fonts()


func _apply_editor_button_style(button: Button, primary: bool) -> void:
	if button == null:
		return
	button.add_theme_stylebox_override("normal", _editor_button_style(primary, false))
	button.add_theme_stylebox_override("hover", _editor_button_style(primary, true))
	button.add_theme_stylebox_override("pressed", _editor_button_style(true, false))
	button.add_theme_stylebox_override("focus", _editor_button_style(primary, true))
	button.add_theme_color_override("font_color", HDTheme.primary_text() if primary else HDTheme.SECONDARY)
	button.add_theme_constant_override("h_separation", 8)


func _apply_editor_option_style(option: OptionButton) -> void:
	if option == null:
		return
	option.fit_to_longest_item = false
	option.clip_text = true
	option.add_theme_stylebox_override("normal", _editor_option_style(false))
	option.add_theme_stylebox_override("hover", _editor_option_style(true))
	option.add_theme_stylebox_override("pressed", _editor_option_style(true))
	option.add_theme_stylebox_override("focus", _editor_option_style(true))
	option.add_theme_color_override("font_color", HDTheme.primary_text())
	option.add_theme_constant_override("h_separation", 8)
	_apply_editor_popup_style(option.get_popup())


func _apply_editor_line_edit_style(edit: LineEdit) -> void:
	if edit == null:
		return
	edit.add_theme_stylebox_override("normal", _editor_input_style(false))
	edit.add_theme_stylebox_override("focus", _editor_input_style(true))
	edit.add_theme_stylebox_override("read_only", _editor_input_style(false))
	edit.add_theme_color_override("font_color", HDTheme.primary_text())
	edit.add_theme_color_override("font_placeholder_color", HDTheme.TERTIARY)
	edit.add_theme_color_override("caret_color", HDTheme.CYAN)
	edit.custom_minimum_size.y = EDITOR_CONTROL_MIN_HEIGHT


func _apply_editor_spinbox_style(spin: SpinBox) -> void:
	if spin == null:
		return
	var edit := spin.get_line_edit()
	_apply_editor_line_edit_style(edit)


func _apply_editor_dialog_styles() -> void:
	_audio_file_dialog.use_native_dialog = false
	_auto_chart_file_dialog.use_native_dialog = false
	_project_folder_dialog.use_native_dialog = false
	_chart_import_file_dialog.use_native_dialog = false
	_save_as_file_dialog.use_native_dialog = false
	if _audio_link_chart_file_dialog != null:
		_audio_link_chart_file_dialog.use_native_dialog = false
	if _import_project_file_dialog != null:
		_import_project_file_dialog.use_native_dialog = false
	if _export_project_file_dialog != null:
		_export_project_file_dialog.use_native_dialog = false
	for window in [
		_project_name_dialog,
		_project_folder_dialog,
		_chart_import_file_dialog,
		_audio_file_dialog,
		_auto_chart_file_dialog,
		_save_as_file_dialog,
		_import_wizard_dialog,
		_message_dialog,
		_help_dialog,
		_clone_difficulty_dialog,
		_layout_choice_dialog,
		_context_menu,
		_note_duration_dialog,
		_note_move_dialog,
		_multi_move_dialog,
		_shift_lane_dialog,
		_shift_multi_dialog,
		_delete_chart_dialog,
		_start_charting_dialog,
		_lane_count_dialog,
		_audio_link_dialog,
		_audio_link_chart_file_dialog,
		_audio_source_dialog,
		_youtube_url_dialog,
		_import_project_file_dialog,
		_export_project_file_dialog,
		_workshop_upload_dialog,
		_workshop_missing_url_dialog,
		_auto_chart_preview_dialog,
	]:
		if window is Window:
			HDTheme.apply_dialog(window as Window)
		_apply_editor_window_style(window)
		_style_editor_subtree(window)


func _apply_editor_window_style(node: Node) -> void:
	if node == null:
		return
	if node is PopupMenu:
		_apply_editor_popup_style(node as PopupMenu)
		return
	if node.has_method("add_theme_stylebox_override"):
		node.add_theme_stylebox_override("panel", _editor_dialog_panel_style())
	if node.has_method("add_theme_color_override"):
		node.add_theme_color_override("font_color", HDTheme.primary_text())
		node.add_theme_color_override("title_color", HDTheme.primary_text())


func _style_editor_subtree(node: Node) -> void:
	if node == null:
		return
	if node is OptionButton:
		_apply_editor_option_style(node as OptionButton)
	elif node is Button:
		_apply_editor_button_style(node as Button, false)
	elif node is LineEdit:
		_apply_editor_line_edit_style(node as LineEdit)
	elif node is PopupMenu:
		_apply_editor_popup_style(node as PopupMenu)
	elif node is Label:
		(node as Label).add_theme_color_override("font_color", HDTheme.SECONDARY)
	elif node is PanelContainer:
		(node as PanelContainer).add_theme_stylebox_override("panel", _editor_dialog_panel_style())
	elif node is ScrollContainer:
		(node as ScrollContainer).add_theme_stylebox_override("panel", _editor_dialog_panel_style())
	for child in node.get_children():
		_style_editor_subtree(child)


func _apply_editor_popup_style(popup: PopupMenu) -> void:
	if popup == null:
		return
	popup.add_theme_stylebox_override("panel", _editor_popup_panel_style())
	popup.add_theme_stylebox_override("hover", _editor_popup_hover_style())
	popup.add_theme_color_override("font_color", HDTheme.primary_text())
	popup.add_theme_color_override("font_hover_color", HDTheme.primary_text())
	popup.add_theme_color_override("font_disabled_color", HDTheme.TERTIARY)
	popup.add_theme_color_override("font_accelerator_color", HDTheme.TERTIARY)
	popup.add_theme_color_override("font_separator_color", HDTheme.CYAN * Color(1, 1, 1, 0.7))
	popup.add_theme_constant_override("item_start_padding", 12)
	popup.add_theme_constant_override("item_end_padding", 12)
	popup.add_theme_constant_override("v_separation", 6)
	popup.transparent_bg = true


func _editor_button_style(primary: bool, hover: bool) -> StyleBoxFlat:
	var style := HDTheme.button_style(primary)
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	if hover and not primary:
		style.bg_color = HDTheme.CARD_FILL.lightened(0.06)
		style.border_color = HDTheme.CYAN * Color(1, 1, 1, 0.34)
	_set_style_padding(style, 7.0, 7.0, 3.0, 3.0)
	return style


func _editor_popup_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = HDTheme.PANEL_FILL.darkened(0.08)
	style.border_color = HDTheme.CYAN * Color(1, 1, 1, 0.28)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.shadow_color = Color(0, 0, 0, 0.42)
	style.shadow_size = 12
	style.shadow_offset = Vector2(0, 6)
	_set_style_padding(style, 6.0, 6.0, 6.0, 6.0)
	return style


func _editor_popup_hover_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = HDTheme.CYAN * Color(1, 1, 1, 0.18)
	style.border_color = HDTheme.CYAN * Color(1, 1, 1, 0.35)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	_set_style_padding(style, 2.0, 2.0, 2.0, 2.0)
	return style


func _editor_dialog_panel_style() -> StyleBoxFlat:
	var style := HDTheme.overlay_panel_style()
	style.bg_color = HDTheme.PANEL_FILL
	style.border_color = HDTheme.CYAN * Color(1, 1, 1, 0.24)
	_set_style_padding(style, 8.0, 8.0, 8.0, 8.0)
	return style


func _editor_option_style(hover: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = HDTheme.CARD_FILL.darkened(0.08)
	if hover:
		style.bg_color = HDTheme.CARD_FILL.lightened(0.03)
	style.border_color = HDTheme.CYAN * Color(1, 1, 1, 0.24 if not hover else 0.38)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 9
	style.corner_radius_top_right = 9
	style.corner_radius_bottom_left = 9
	style.corner_radius_bottom_right = 9
	_set_style_padding(style, 7.0, 7.0, 3.0, 3.0)
	return style


func _editor_input_style(focused: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = HDTheme.BG.lightened(0.03)
	style.border_color = HDTheme.CYAN * Color(1, 1, 1, 0.42 if focused else 0.16)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 7
	style.corner_radius_top_right = 7
	style.corner_radius_bottom_left = 7
	style.corner_radius_bottom_right = 7
	_set_style_padding(style, 7.0, 7.0, 3.0, 3.0)
	return style


func _set_style_padding(style: StyleBoxFlat, left: float, right: float, top: float, bottom: float) -> void:
	style.set_content_margin(SIDE_LEFT, left)
	style.set_content_margin(SIDE_RIGHT, right)
	style.set_content_margin(SIDE_TOP, top)
	style.set_content_margin(SIDE_BOTTOM, bottom)


func _apply_responsive_editor_layout() -> void:
	_apply_compact_editor_fonts()
	var scale := _toolbar_density_scale()
	var outer_margin := 3 if scale < 0.9 else 4
	var row_gap := 4 if scale < 0.9 else 5
	var h_gap := 4 if scale < 0.9 else 5
	var v_gap := 2 if scale < 0.9 else 3
	var safe_margin := get_node_or_null("SafeMargin") as MarginContainer
	if safe_margin != null:
		for key in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
			safe_margin.add_theme_constant_override(key, outer_margin)
	var root_vbox := get_node_or_null("SafeMargin/RootVBox") as VBoxContainer
	if root_vbox != null:
		root_vbox.add_theme_constant_override("separation", row_gap)
	var top_margin := get_node_or_null("SafeMargin/RootVBox/TopPanel/TopMargin") as MarginContainer
	if top_margin != null:
		top_margin.add_theme_constant_override("margin_left", 6)
		top_margin.add_theme_constant_override("margin_right", 6)
		top_margin.add_theme_constant_override("margin_top", row_gap)
		top_margin.add_theme_constant_override("margin_bottom", row_gap)
	var top_vbox := get_node_or_null("SafeMargin/RootVBox/TopPanel/TopMargin/TopVBox") as VBoxContainer
	if top_vbox != null:
		top_vbox.add_theme_constant_override("separation", row_gap)
	for row_path in [
		"SafeMargin/RootVBox/TopPanel/TopMargin/TopVBox/PlaybackRow",
		"SafeMargin/RootVBox/TopPanel/TopMargin/TopVBox/SongRow",
		"SafeMargin/RootVBox/TopPanel/TopMargin/TopVBox/PlaybackSpeedRow",
	]:
		var row := get_node_or_null(row_path) as HFlowContainer
		if row != null:
			row.add_theme_constant_override("h_separation", h_gap)
			row.add_theme_constant_override("v_separation", v_gap)
	var timeline_margin := get_node_or_null("SafeMargin/RootVBox/TimelinePanel/TimelineMargin") as MarginContainer
	if timeline_margin != null:
		var timeline_gap := 5 if scale < 0.9 else 6
		for key in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
			timeline_margin.add_theme_constant_override(key, timeline_gap)
	_apply_vertical_editor_density(scale)


func _apply_vertical_editor_density(scale: float) -> void:
	var vertical_panel_scale := minf(scale, 0.88)
	var viewport_height := get_viewport_rect().size.y
	var vertical_gap := 5 if vertical_panel_scale < 0.86 else 6
	var compact_margin := 7 if vertical_panel_scale < 0.86 else 8
	var main_row := get_node_or_null("SafeMargin/RootVBox/TimelinePanel/TimelineMargin/VerticalEditorRoot/VerticalMainRow") as HBoxContainer
	if main_row != null:
		main_row.add_theme_constant_override("separation", vertical_gap)
	var song_panel := get_node_or_null("SafeMargin/RootVBox/TimelinePanel/TimelineMargin/VerticalEditorRoot/VerticalMainRow/SongInfoPanel") as PanelContainer
	if song_panel != null:
		song_panel.custom_minimum_size.x = 176.0 * vertical_panel_scale
	var right_panel := get_node_or_null("SafeMargin/RootVBox/TimelinePanel/TimelineMargin/VerticalEditorRoot/VerticalMainRow/RightToolsPanel") as PanelContainer
	if right_panel != null:
		right_panel.custom_minimum_size.x = 124.0 * vertical_panel_scale
	for margin_path in [
		"SafeMargin/RootVBox/TimelinePanel/TimelineMargin/VerticalEditorRoot/VerticalMainRow/SongInfoPanel/SongInfoMargin",
		"SafeMargin/RootVBox/TimelinePanel/TimelineMargin/VerticalEditorRoot/VerticalMainRow/RightToolsPanel/RightToolsMargin",
	]:
		var margin := get_node_or_null(margin_path) as MarginContainer
		if margin != null:
			for key in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
				margin.add_theme_constant_override(key, compact_margin)
	var song_vbox := get_node_or_null("SafeMargin/RootVBox/TimelinePanel/TimelineMargin/VerticalEditorRoot/VerticalMainRow/SongInfoPanel/SongInfoMargin/SongInfoVBox") as VBoxContainer
	if song_vbox != null:
		song_vbox.add_theme_constant_override("separation", vertical_gap)
	var tools_vbox := get_node_or_null("SafeMargin/RootVBox/TimelinePanel/TimelineMargin/VerticalEditorRoot/VerticalMainRow/RightToolsPanel/RightToolsMargin/RightToolsVBox") as VBoxContainer
	if tools_vbox != null:
		tools_vbox.add_theme_constant_override("separation", vertical_gap)
	_vertical_view_mode_option.custom_minimum_size.x = 130.0 * vertical_panel_scale
	_track_width_slider.custom_minimum_size.x = 96.0 * vertical_panel_scale
	_highway_zoom_slider.custom_minimum_size.x = 96.0 * vertical_panel_scale
	# These views expand into spare room, but must be allowed to contract when the
	# editor is running inside Godot's shorter embedded game viewport.
	if viewport_height <= TOOLBAR_TIGHT_HEIGHT:
		_vertical_highway.custom_minimum_size.y = 180.0
		_density_strip.custom_minimum_size.y = 80.0
		_bottom_minimap.custom_minimum_size.y = 32.0
	elif viewport_height <= TOOLBAR_COMPACT_HEIGHT:
		_vertical_highway.custom_minimum_size.y = 220.0
		_density_strip.custom_minimum_size.y = 120.0
		_bottom_minimap.custom_minimum_size.y = 36.0
	elif viewport_height <= 940.0:
		_vertical_highway.custom_minimum_size.y = 260.0
		_density_strip.custom_minimum_size.y = 160.0
		_bottom_minimap.custom_minimum_size.y = 40.0
	else:
		_vertical_highway.custom_minimum_size.y = 300.0
		_density_strip.custom_minimum_size.y = 220.0
		_bottom_minimap.custom_minimum_size.y = 44.0


func _toolbar_density_scale() -> float:
	var viewport_size := get_viewport_rect().size
	var height := viewport_size.y
	var width := viewport_size.x
	var scale := 0.90
	if height <= TOOLBAR_TIGHT_HEIGHT:
		scale = 0.74
	elif height <= TOOLBAR_COMPACT_HEIGHT:
		scale = 0.80
	elif height <= 940.0:
		scale = 0.84
	if width <= 1600.0:
		scale = minf(scale, 0.76)
	elif width <= 1920.0:
		scale = minf(scale, 0.82)
	elif width <= 2200.0:
		scale = minf(scale, 0.86)
	return scale


func _apply_compact_editor_fonts() -> void:
	var scale := _toolbar_density_scale()
	var button_font_size: int = max(11, int(roundf(15.0 * scale)))
	var control_font_size: int = max(11, int(roundf(15.0 * scale)))
	var label_font_size: int = max(10, int(roundf(13.0 * scale)))
	for button in [
		_back_button,
		_play_button,
		_playtest_button,
		_live_editor_button,
		_live_editor_close_button,
		_live_editor_start_pause_button,
		_browse_audio_button,
		_auto_bpm_button,
		_auto_chart_button,
		_save_button,
		_save_as_button,
		_create_project_button,
		_open_project_button,
		_import_chart_button,
		_reload_songs_button,
		_clone_difficulty_button,
		_chart_stats_button,
		_help_button,
		_remove_selected_button,
		_tap_tool_button,
		_hold_tool_button,
		_select_tool_button,
		_erase_tool_button,
	]:
		(button as Button).add_theme_font_size_override("font_size", button_font_size)
	for toggle in [_live_editor_adding_toggle, _live_editor_remove_toggle]:
		(toggle as CheckButton).add_theme_font_size_override("font_size", control_font_size)
	for option in [
		_audio_option,
		_snap_option,
		_layout_option,
		_vertical_direction_option,
		_vertical_view_mode_option,
		_song_option,
		_difficulty_option,
		_lane_count_option,
	]:
		(option as OptionButton).add_theme_font_size_override("font_size", control_font_size)
	for label in [_speed_value_label, _hold_threshold_label, _timestamp_label, _status_label, _track_width_value_label, _highway_zoom_value_label, _difficulty_value_label, _lanes_value_label, _bpm_value_label, _nps_value_label, _live_editor_timestamp_label, _live_editor_status_label]:
		(label as Label).add_theme_font_size_override("font_size", label_font_size)
	for meta_label_name in ["TitleMetaLabel", "ArtistMetaLabel", "CharterMetaLabel", "DifficultyMetaLabel", "LanesMetaLabel", "BPMMetaLabel", "NPSMetaLabel"]:
		var meta_label := get_node_or_null("%" + meta_label_name) as Label
		if meta_label != null:
			meta_label.add_theme_font_size_override("font_size", max(10, label_font_size - 1))
	for vertical_label_name in ["ViewModeLabel", "TrackWidthLabel", "HighwayZoomLabel"]:
		var vertical_label := find_child(vertical_label_name, true, false) as Label
		if vertical_label != null:
			vertical_label.add_theme_font_size_override("font_size", label_font_size)
	for edit in [_title_edit, _artist_edit, _charter_edit]:
		(edit as LineEdit).add_theme_font_size_override("font_size", max(12, control_font_size - 1))
	var bpm_label := get_node_or_null("%BPMLabel") as Label
	if bpm_label != null:
		bpm_label.add_theme_font_size_override("font_size", label_font_size)
	_bpm_spin.add_theme_font_size_override("font_size", control_font_size)
	_hold_threshold_spin.add_theme_font_size_override("font_size", control_font_size)
	_live_editor_speed_spin.add_theme_font_size_override("font_size", control_font_size)
	_apply_toolbar_minimum_sizes(scale)


func _apply_toolbar_minimum_sizes(scale: float) -> void:
	var control_height := maxf(24.0, EDITOR_CONTROL_MIN_HEIGHT * scale)
	for button in [
		_back_button,
		_play_button,
		_playtest_button,
		_live_editor_button,
		_live_editor_close_button,
		_live_editor_start_pause_button,
		_browse_audio_button,
		_auto_bpm_button,
		_auto_chart_button,
		_save_button,
		_save_as_button,
		_create_project_button,
		_open_project_button,
		_import_chart_button,
		_reload_songs_button,
		_clone_difficulty_button,
		_chart_stats_button,
		_help_button,
		_remove_selected_button,
		_tap_tool_button,
		_hold_tool_button,
		_select_tool_button,
		_erase_tool_button,
	]:
		(button as Button).custom_minimum_size.y = control_height
	for toggle in [_live_editor_adding_toggle, _live_editor_remove_toggle]:
		(toggle as CheckButton).custom_minimum_size.y = control_height
	for option in [
		_audio_option,
		_snap_option,
		_layout_option,
		_vertical_direction_option,
		_vertical_view_mode_option,
		_song_option,
		_difficulty_option,
		_lane_count_option,
	]:
		(option as OptionButton).custom_minimum_size.y = control_height
	_back_button.custom_minimum_size.x = maxf(88.0, 80.0 * scale)
	_play_button.custom_minimum_size.x = maxf(74.0, EDITOR_PLAY_BUTTON_MIN_WIDTH * scale)
	_audio_option.custom_minimum_size.x = 126.0 * scale
	_auto_chart_button.custom_minimum_size.x = maxf(86.0, 86.0 * scale)
	_bpm_spin.custom_minimum_size = Vector2(76.0 * scale, control_height)
	_hold_threshold_spin.custom_minimum_size = Vector2(maxf(96.0, 104.0 * scale), control_height)
	_live_editor_speed_spin.custom_minimum_size = Vector2(maxf(96.0, 104.0 * scale), control_height)
	_snap_option.custom_minimum_size.x = 82.0 * scale
	_layout_option.custom_minimum_size.x = 138.0 * scale
	_vertical_direction_option.custom_minimum_size.x = 132.0 * scale
	_vertical_view_mode_option.custom_minimum_size.x = 130.0 * scale
	_song_option.custom_minimum_size.x = 170.0 * scale
	_difficulty_option.custom_minimum_size.x = 100.0 * scale
	_lane_count_option.custom_minimum_size.x = 90.0 * scale
	_speed_slider.custom_minimum_size.x = 104.0 * scale
	_speed_value_label.custom_minimum_size.x = 48.0 * scale
	_timestamp_label.custom_minimum_size.x = maxf(172.0, 190.0 * scale)
	_remove_selected_button.custom_minimum_size.x = maxf(168.0, 144.0 * scale)
	_status_label.custom_minimum_size.x = maxf(160.0, 220.0 * scale)


func _setup_difficulty_tools() -> void:
	_clone_difficulty_button.pressed.connect(func() -> void:
		if not _project_active:
			return
		_clone_from_option.clear()
		_clone_to_option.clear()
		_clone_method_option.clear()
		var ids := DifficultyManager.all_ids()
		for id in ids:
			_clone_from_option.add_item(id)
			_clone_to_option.add_item(id)
		# Use stable IDs to avoid any string-matching ambiguity.
		_clone_method_option.add_item("Complete Clone", 0)
		_clone_method_option.add_item("Smart Clone", 1)
		_clone_from_option.select(maxi(0, ids.find(_difficulty)))
		_clone_to_option.select(maxi(0, ids.find("professional" if _difficulty != "professional" else "expert")))
		_clone_method_option.select(0)
		_clone_overwrite_check.button_pressed = false
		_clone_difficulty_dialog.popup_centered()
	)
	_clone_difficulty_dialog.confirmed.connect(func() -> void:
		if not _project_active:
			return
		var from_id := _clone_from_option.get_item_text(_clone_from_option.selected).strip_edges().to_lower()
		var to_id := _clone_to_option.get_item_text(_clone_to_option.selected).strip_edges().to_lower()
		var method_id: int = _clone_method_option.get_selected_id()
		var method := "smart clone" if method_id == 1 else "complete clone"
		var overwrite := _clone_overwrite_check.button_pressed
		if method_id == 1 and not _waveform.is_ready():
			_show_message(
				"Smart Clone Unavailable",
				"Smart Clone currently requires a waveform preview. Please load WAV audio (or use Complete Clone)."
			)
			return
		await _show_loading("Cloning difficulty…", "Method: %s" % ("Smart Clone" if method_id == 1 else "Complete Clone"))
		var result: Dictionary = SongPackageManager.clone_difficulty(
			_song_folder,
			from_id,
			to_id,
			overwrite,
			method,
			_waveform
		)
		_hide_loading()
		if not bool(result.get("ok", false)):
			_show_message("Clone Failed", str(result.get("error", "Unknown error.")))
			return
		_load_project_options()
		var copied := int(result.get("copied", 0))
		var added := int(result.get("added", 0))
		var removed := int(result.get("removed", 0))
		var src_count := int(result.get("src_notes", copied + removed))
		var dst_count := int(result.get("dst_notes", copied + added))
		_status_label.text = "%s: %s -> %s" % [("Smart Clone" if method_id == 1 else "Complete Clone"), from_id, to_id]
		_show_message(
			"Clone Complete",
			"%s\n\nSource notes: %d\nDestination notes: %d\nCopied: %d\nAdded: %d\nRemoved: %d" % [
				_status_label.text,
				src_count,
				dst_count,
				copied,
				added,
				removed,
			]
		)
	)
	_chart_stats_button.pressed.connect(func() -> void:
		if not _project_active:
			return
		var lines: Array[String] = []
		for id in DifficultyManager.all_ids():
			var chart_path := SongResolver.get_chart_path(_song_folder, id)
			if not FileAccess.file_exists(chart_path):
				continue
			var chart: Dictionary = SongPackageManager.load_chart(_song_folder, id)
			var stats: Dictionary = SongPackageManager.compute_chart_stats(chart)
			lines.append("%s: notes=%d taps=%d holds=%d nps=%.2f dur=%.1fs" % [
				id,
				int(stats.get("note_count", 0)),
				int(stats.get("tap_count", 0)),
				int(stats.get("hold_count", 0)),
				float(stats.get("nps", 0.0)),
				float(stats.get("duration_sec", 0.0)),
			])
		if lines.is_empty():
			lines.append("No charts found in this project yet.")
		_show_message("Chart Statistics", "\n".join(lines))
	)


func _read_cmdline() -> void:
	for arg in OS.get_cmdline_args():
		if arg.begins_with("--editor_song_folder="):
			_song_folder = arg.split("=", true, 1)[1]
		elif arg.begins_with("--editor_difficulty="):
			_difficulty = arg.split("=", true, 1)[1].strip_edges().to_lower()
		elif arg.begins_with("--editor_chart_path="):
			_chart_path = arg.split("=", true, 1)[1]
		elif arg.begins_with("--editor_manifest_path="):
			_manifest_path = arg.split("=", true, 1)[1]


func _setup_song_picker() -> void:
	_reload_songs_button.pressed.connect(func() -> void:
		if _project_active:
			await _open_project_folder(_song_folder)
	)
	_song_option.item_selected.connect(func(_idx: int) -> void:
		await _apply_selected_song_from_ui()
	)
	_difficulty_option.item_selected.connect(func(_idx: int) -> void:
		if _is_switching_song:
			return
		_difficulty = _difficulty_option.get_item_text(_difficulty_option.selected).strip_edges().to_lower()
		if not _song_folder.is_empty():
			_chart_path = SongPackageManager.ensure_chart_exists(_song_folder, _difficulty)
			_ensure_manifest_has_difficulty(_difficulty)
		await _show_loading("Loading chart", "Switching to %s..." % _difficulty)
		await _load_session()
		_hide_loading()
		_update_status()
		_maybe_show_lane_count_migration_dialog()
	)


func _setup_project_controls() -> void:
	_create_project_button.pressed.connect(func() -> void:
		_project_name_edit.text = ""
		_project_name_dialog.popup_centered()
		_project_name_edit.grab_focus()
	)
	_open_project_button.pressed.connect(func() -> void:
		SongResolver.ensure_user_song_dirs()
		var root_abs := ProjectSettings.globalize_path(SongResolver.CUSTOM_ROOT)
		_project_folder_dialog.current_dir = root_abs
		_project_folder_dialog.root_subfolder = root_abs
		_project_folder_dialog.popup_centered_ratio(0.7)
	)
	_import_project_button.pressed.connect(_on_import_project_pressed)
	_export_project_button.pressed.connect(_on_export_project_pressed)
	_import_chart_button.pressed.connect(func() -> void:
		if not _project_active:
			return
		_chart_import_file_dialog.popup_centered_ratio(0.7)
	)
	_workshop_upload_button.pressed.connect(_on_workshop_upload_pressed)
	_project_name_dialog.confirmed.connect(_on_create_project_confirmed)
	_project_folder_dialog.dir_selected.connect(_on_project_folder_selected)
	_chart_import_file_dialog.file_selected.connect(_on_chart_import_file_selected)
	_import_wizard_dialog.confirmed.connect(_on_import_wizard_confirmed)
	_import_file_option.item_selected.connect(_on_import_file_option_selected)
	_import_audio_option.item_selected.connect(_on_import_audio_option_selected)
	_set_project_active(false)


func _set_project_active(active: bool) -> void:
	_project_active = active
	_create_project_button.disabled = false
	_open_project_button.disabled = false
	_import_project_button.disabled = false
	_export_project_button.disabled = not active
	_import_chart_button.disabled = not active
	_workshop_upload_button.disabled = not active
	_reload_songs_button.disabled = not active
	_song_option.disabled = not active
	_difficulty_option.disabled = not active
	_lane_count_option.disabled = not active
	_clone_difficulty_button.disabled = not active
	_chart_stats_button.disabled = not active
	_snap_option.disabled = not active
	_vertical_view_mode_option.disabled = not active
	_track_width_slider.editable = active
	_highway_zoom_slider.editable = active and _vertical_view_mode == EditorPreferenceStore.VIEW_MODE_TIMELINE_ZOOM
	_play_button.disabled = not active
	_playtest_button.disabled = not active
	_live_editor_button.disabled = not active
	_save_button.disabled = not active
	_save_as_button.disabled = not active
	_audio_option.disabled = not active
	_browse_audio_button.disabled = not active
	_auto_bpm_button.disabled = not active
	_auto_chart_button.disabled = not active
	_bpm_spin.editable = active
	_set_metadata_controls_enabled(active)
	_timeline.mouse_filter = Control.MOUSE_FILTER_PASS if active else Control.MOUSE_FILTER_IGNORE
	_vertical_highway.mouse_filter = Control.MOUSE_FILTER_PASS if active else Control.MOUSE_FILTER_IGNORE
	_bottom_minimap.mouse_filter = Control.MOUSE_FILTER_PASS if active else Control.MOUSE_FILTER_IGNORE
	_density_strip.mouse_filter = Control.MOUSE_FILTER_PASS if active else Control.MOUSE_FILTER_IGNORE
	if not active:
		_status_label.text = "Create or open a project to begin."


func _clear_session() -> void:
	_playback.pause()
	_playback.set_stream(null)
	_waveform.prepare_from_stream(null)
	_notes.clear()
	_song_folder = ""
	_manifest_path = ""
	_chart_path = ""
	_selected_song_id = ""
	_selected_audio_path = ""
	_active_audio_path = ""
	_chart_load_error = ""
	_audio_reason = ""
	_loaded_session_folder = ""
	_loaded_session_chart_path = ""
	_session_load_generation += 1
	_last_auto_bpm_audio_path = ""
	_pending_import_path = ""
	_pending_import_folder = ""
	_pending_import_file_candidates.clear()
	_pending_import_audio_candidates.clear()
	_pending_import_audio_path = ""
	_pending_import_result = {}
	_pending_import_preview_result = {}
	_pending_import_waveform.clear()
	_pending_audio_import_folder = ""
	_pending_audio_link_chart_path = ""
	_song_option.clear()
	_song_option.add_item("No project open")
	_difficulty_option.clear()
	_difficulty_option.add_item(_difficulty)
	_audio_option.clear()
	_audio_option.add_item("Audio: none")
	_timeline.set_audio_length(0.0)
	_timeline.set_notes([])
	_timeline.set_cursor_time(0.0)
	_vertical_highway.set_audio_length(0.0)
	_vertical_highway.set_notes([])
	_vertical_highway.set_cursor_time(0.0)
	_bottom_minimap.set_audio_length(0.0)
	_bottom_minimap.set_notes([])
	_bottom_minimap.set_cursor_time(0.0)
	_density_strip.set_audio_length(0.0)
	_density_strip.set_notes([])
	_density_strip.set_cursor_time(0.0)
	_set_lane_count(LaneCountResolver.DEFAULT_LANES)
	_loaded_chart_missing_lane_count = false
	_update_song_info({})


func _reset_loaded_resources_for_session(clear_audio_override: bool) -> void:
	_session_load_generation += 1
	if _playtest != null and _playtest.is_active():
		_playtest.stop()
	_playback.pause()
	_playback.set_stream(null)
	_waveform.prepare_from_stream(null)
	_notes.set_notes([])
	_chart_load_error = ""
	_audio_reason = ""
	_loaded_chart_missing_lane_count = false
	_last_auto_bpm_audio_path = ""
	_active_audio_path = ""
	if clear_audio_override:
		_selected_audio_path = ""
		_pending_import_path = ""
		_pending_import_folder = ""
		_pending_import_file_candidates.clear()
		_pending_import_audio_candidates.clear()
		_pending_import_audio_path = ""
		_pending_import_result = {}
		_pending_import_preview_result = {}
		_pending_import_waveform.clear()
		_pending_audio_import_folder = ""
		_pending_audio_link_chart_path = ""
	_timeline.set_audio_length(0.0)
	_timeline.set_notes([])
	_timeline.set_selected_ids([])
	_timeline.set_cursor_time(0.0)
	_vertical_highway.set_audio_length(0.0)
	_vertical_highway.set_notes([])
	_vertical_highway.set_selected_ids([])
	_vertical_highway.set_cursor_time(0.0)
	_bottom_minimap.set_audio_length(0.0)
	_bottom_minimap.set_notes([])
	_bottom_minimap.set_cursor_time(0.0)
	_density_strip.set_audio_length(0.0)
	_density_strip.set_notes([])
	_density_strip.set_cursor_time(0.0)
	_audio_option.clear()
	_audio_option.add_item("Audio: loading...")
	_update_status()


func _on_create_project_confirmed() -> void:
	await _show_loading("Creating project", "Preparing project folder...")
	var folder_name: String = ChartImportUtils.sanitize_id(_project_name_edit.text)
	if folder_name.is_empty():
		folder_name = "song_project"
	var project_folder: String = SongResolver.CUSTOM_ROOT.path_join(folder_name)
	var suffix: int = 2
	while DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(project_folder)):
		project_folder = SongResolver.CUSTOM_ROOT.path_join("%s_%d" % [folder_name, suffix])
		suffix += 1
	var err: int = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(project_folder))
	if err != OK:
		_status_label.text = "Create project failed: %s" % project_folder
		_hide_loading()
		_show_message("Create Project Failed", "The project folder could not be created:\n%s" % project_folder)
		return
	await _update_loading("Writing starter manifest and chart...")
	_write_starter_project(project_folder, folder_name)
	_new_project_start_prompt_requested = true
	await _open_project_folder(project_folder, false)


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
	ChartImportUtils.write_json(project_folder.path_join("expert.json"), ChartImportUtils.chart_payload(
		"expert",
		[],
		LaneCountResolver.DEFAULT_LANES,
		{
			"title": title,
			"artist": "Unknown Artist",
			"charter": "Unknown Charter",
			"bpm": 120.0,
			"nps": 0.0,
		}
	))


func _on_project_folder_selected(path: String) -> void:
	await _show_loading("Opening project", "Validating selected folder...")
	var project_folder: String = _custom_folder_from_selected_path(path)
	if project_folder.is_empty():
		_status_label.text = "Open failed: choose a folder inside user://custom_songs."
		_hide_loading()
		_show_message("Open Project Failed", "Choose an existing folder inside the Harmonic Drive custom songs directory.")
		return
	if not FileAccess.file_exists(project_folder.path_join("manifest.json")):
		await _update_loading("Creating missing starter project files...")
		_write_starter_project(project_folder, project_folder.get_file())
	await _open_project_folder(project_folder, false)


func _custom_folder_from_selected_path(path: String) -> String:
	var root_abs: String = ProjectSettings.globalize_path(SongResolver.CUSTOM_ROOT).simplify_path()
	var selected_abs: String = path.simplify_path()
	if selected_abs == root_abs:
		return ""
	if not selected_abs.begins_with(root_abs + "/"):
		return ""
	var relative: String = selected_abs.substr(root_abs.length() + 1)
	if relative.is_empty() or relative.contains(".."):
		return ""
	return SongResolver.CUSTOM_ROOT.path_join(relative)


func _open_project_folder(project_folder: String, show_loading: bool = true) -> void:
	if show_loading:
		await _show_loading("Opening project", "Preparing song directories...")
	SongResolver.ensure_user_song_dirs()
	_song_folder = project_folder
	_manifest_path = SongResolver.get_manifest_path(_song_folder)
	if not FileAccess.file_exists(_manifest_path):
		if show_loading:
			await _update_loading("Creating missing starter project files...")
		_write_starter_project(_song_folder, _song_folder.get_file())
	if show_loading:
		await _update_loading("Reading manifest and difficulties...")
	_load_project_options()
	_set_project_active(true)
	if show_loading:
		await _update_loading("Loading chart and audio...")
	await _load_session()
	_reset_editor_view_to_start()
	_update_status()
	_hide_loading()
	_maybe_show_layout_choice()
	_maybe_show_lane_count_migration_dialog()


func _load_project_options() -> void:
	_is_switching_song = true
	var manifest: Dictionary = _read_manifest()
	_selected_song_id = str(manifest.get("song_id", ChartImportUtils.sanitize_id(_song_folder.get_file())))
	_song_option.clear()
	_song_option.add_item("%s (project)" % _project_display_title(manifest))
	_song_option.set_item_metadata(0, _selected_song_id)
	_song_option.select(0)
	_difficulty_option.clear()
	for diff in DifficultyManager.all_ids():
		_difficulty_option.add_item(diff)
	var selected_idx := -1
	for i in range(_difficulty_option.item_count):
		if _difficulty_option.get_item_text(i).strip_edges().to_lower() == _difficulty:
			selected_idx = i
			break
	if selected_idx < 0:
		selected_idx = 0
		for i in range(_difficulty_option.item_count):
			if not _difficulty_option.is_item_disabled(i):
				selected_idx = i
				break
	_difficulty_option.select(selected_idx)
	_difficulty = _difficulty_option.get_item_text(selected_idx).strip_edges().to_lower()
	_chart_path = SongPackageManager.ensure_chart_exists(_song_folder, _difficulty)
	_ensure_manifest_has_difficulty(_difficulty)
	_is_switching_song = false


func _read_manifest() -> Dictionary:
	if _manifest_path.is_empty() or not FileAccess.file_exists(_manifest_path):
		return {}
	var loaded: Dictionary = ChartLoader.load_json_dictionary(_manifest_path)
	if bool(loaded.get("ok", false)):
		return loaded.get("value", {}) as Dictionary
	return {}


func _set_manifest_audio_path(audio_path: String) -> void:
	if _manifest_path.is_empty():
		return
	var manifest := _read_manifest()
	if manifest.is_empty():
		manifest = {}
	if audio_path.strip_edges().is_empty():
		manifest.erase("audio_path")
	else:
		manifest["audio_path"] = audio_path
	ChartImportUtils.write_json(_manifest_path, manifest)


func _set_manifest_youtube_url(youtube_url: String) -> void:
	if _manifest_path.is_empty():
		return
	var manifest := _read_manifest()
	if manifest.is_empty():
		return
	manifest["youtube_url"] = youtube_url.strip_edges()
	ChartImportUtils.write_json(_manifest_path, manifest)


func _current_youtube_url() -> String:
	return str(_read_manifest().get("youtube_url", "")).strip_edges()


func _set_manifest_timing(bpm: float, offset: float) -> void:
	if _manifest_path.is_empty():
		return
	var manifest := _read_manifest()
	if manifest.is_empty():
		return
	manifest["bpm"] = bpm
	manifest["offset"] = offset
	ChartImportUtils.write_json(_manifest_path, manifest)


func _update_song_info(manifest: Dictionary, chart: Dictionary = {}) -> void:
	if manifest.is_empty() and chart.is_empty():
		_set_metadata_controls_enabled(false)
		_set_line_edit_text_if_unfocused(_title_edit, "")
		_set_line_edit_text_if_unfocused(_artist_edit, "")
		_set_line_edit_text_if_unfocused(_charter_edit, "")
		_difficulty_value_label.text = "-"
		_lanes_value_label.text = "-"
		_bpm_value_label.text = "-"
		_nps_value_label.text = "-"
		return
	var metadata := _merged_chart_metadata(manifest, chart)
	var title := str(metadata.get("title", _song_folder.get_file()))
	var artist := str(metadata.get("artist", "Unknown Artist"))
	var charter := str(metadata.get("charter", "Unknown Charter"))
	_set_metadata_controls_enabled(_project_active)
	_set_line_edit_text_if_unfocused(_title_edit, title)
	_set_line_edit_text_if_unfocused(_artist_edit, artist)
	_set_line_edit_text_if_unfocused(_charter_edit, charter)
	_difficulty_value_label.text = str(metadata.get("difficulty", _difficulty)).capitalize()
	_lanes_value_label.text = str(int(metadata.get("lane_count", _lane_count)))
	_bpm_value_label.text = "%.1f" % float(metadata.get("bpm", _grid.bpm))
	_nps_value_label.text = "%.2f" % float(metadata.get("nps", _calculate_nps()))


func _merged_chart_metadata(manifest: Dictionary, chart: Dictionary = {}) -> Dictionary:
	var fallback := ChartMetadataResolver.metadata_for_song_folder(_song_folder, manifest, _difficulty)
	var title := str(fallback.get("title", _song_folder.get_file().replace("_", " "))).strip_edges()
	if ChartMetadataResolver.has_metadata_value("title", chart.get("title", "")):
		title = str(chart.get("title", title)).strip_edges()
	if title.is_empty():
		title = "Untitled Chart"
	var artist := str(fallback.get("artist", "Unknown Artist")).strip_edges()
	if ChartMetadataResolver.has_metadata_value("artist", chart.get("artist", "")):
		artist = str(chart.get("artist", artist)).strip_edges()
	var charter := str(fallback.get("charter", "Unknown Charter")).strip_edges()
	if ChartMetadataResolver.has_metadata_value("charter", chart.get("charter", "")):
		charter = str(chart.get("charter", charter)).strip_edges()
	var difficulty := str(chart.get("difficulty", fallback.get("difficulty", _difficulty))).strip_edges().to_lower()
	if difficulty.is_empty():
		difficulty = _difficulty
	var lane_count := LaneCountResolver.resolve_chart_lane_count(chart, manifest) if not chart.is_empty() or not manifest.is_empty() else _lane_count
	var bpm := float(chart.get("bpm", fallback.get("bpm", manifest.get("bpm", _grid.bpm))))
	if bpm <= 0.0:
		bpm = _grid.bpm
	var nps := float(chart.get("nps", fallback.get("nps", _calculate_nps())))
	return {
		"title": title,
		"artist": artist,
		"charter": charter,
		"difficulty": difficulty,
		"lane_count": LaneCountResolver.clamp_lane_count(lane_count),
		"bpm": bpm,
		"nps": maxf(0.0, nps),
	}


func _clean_metadata_text(value: String, fallback: String) -> String:
	var cleaned := value.strip_edges()
	return fallback if cleaned.is_empty() else cleaned


func _current_chart_metadata() -> Dictionary:
	var manifest := _read_manifest()
	var fallback := ChartMetadataResolver.metadata_for_song_folder(_song_folder, manifest, _difficulty)
	var title := _clean_metadata_text(_title_edit.text, str(fallback.get("title", _song_folder.get_file().replace("_", " "))))
	var artist := _clean_metadata_text(_artist_edit.text, str(fallback.get("artist", "Unknown Artist")))
	var charter := _clean_metadata_text(_charter_edit.text, str(fallback.get("charter", "Unknown Charter")))
	return {
		"title": title,
		"artist": artist,
		"charter": charter,
		"difficulty": _difficulty,
		"lane_count": _lane_count,
		"bpm": _grid.bpm,
		"nps": _calculate_nps(),
	}


func _read_current_chart() -> Dictionary:
	if _chart_path.is_empty() or not FileAccess.file_exists(_chart_path):
		return {}
	var loaded: Dictionary = ChartLoader.load_json_dictionary(_chart_path)
	if bool(loaded.get("ok", false)):
		return loaded.get("value", {}) as Dictionary
	return {}


func _project_display_title(manifest: Dictionary) -> String:
	for difficulty_id in DifficultyManager.all_ids():
		var candidate := SongResolver.get_chart_path(_song_folder, difficulty_id)
		if not FileAccess.file_exists(candidate):
			continue
		var loaded: Dictionary = ChartLoader.load_json_dictionary(candidate)
		if bool(loaded.get("ok", false)):
			var chart := loaded.get("value", {}) as Dictionary
			var title := str(chart.get("title", "")).strip_edges()
			if not title.is_empty():
				return title
	return str(manifest.get("title", _song_folder.get_file()))


func _set_line_edit_text_if_unfocused(edit: LineEdit, value: String) -> void:
	if edit == null:
		return
	if not edit.has_focus():
		edit.text = value


func _calculate_nps() -> float:
	var duration := maxf(0.0, _playback.length_sec())
	for note in _notes.get_notes():
		duration = maxf(duration, float(note.get("time", 0.0)) + float(note.get("length", 0.0)))
	if duration <= 0.0:
		return 0.0
	return float(_notes.get_note_count()) / duration


func _commit_metadata_edits() -> void:
	if not _project_active:
		return
	var metadata := _current_chart_metadata()
	if _song_option.item_count > 0:
		_song_option.set_item_text(_song_option.selected, "%s (project)" % str(metadata.get("title", "Untitled Chart")))
	_update_song_info(_read_manifest(), metadata)


func _reload_songs() -> void:
	#EditorLog.info("songs", "Reloading song database...")
	_song_db.reload()
	_song_entries = _song_db.get_songs()
	var load_errors: Array[Dictionary] = _song_db.get_load_errors()
	var load_warnings: Array[Dictionary] = _song_db.get_load_warnings()
	#EditorLog.info("songs", "found=%d errors=%d warnings=%d" % [_song_entries.size(), load_errors.size(), load_warnings.size()])
	_song_option.clear()
	_difficulty_option.clear()

	if _song_entries.is_empty():
		_song_option.add_item("No songs found (add manifest.json under user://custom_songs/<folder>/)")
		_song_option.disabled = true
		_difficulty_option.disabled = true
		if not load_errors.is_empty():
			var first_err: Dictionary = load_errors[0]
			_chart_load_error = "Song load error: %s" % str(first_err.get("message", ""))
		elif not load_warnings.is_empty():
			var first_warn: Dictionary = load_warnings[0]
			_chart_load_error = "Song load warning: %s" % str(first_warn.get("message", ""))
		return

	_song_option.disabled = false
	_difficulty_option.disabled = false

	var pick_id := _selected_song_id
	if pick_id.is_empty() and not _song_folder.is_empty():
		# Resolve from folder path if possible.
		for entry in _song_entries:
			if str(entry.get("root_path", "")) == _song_folder:
				pick_id = str(entry.get("song_id", ""))
				break

	var selected_index := 0
	for i in range(_song_entries.size()):
		var e: Dictionary = _song_entries[i]
		var title := str(e.get("title", ""))
		var sid := str(e.get("song_id", ""))
		var source := str(e.get("source", ""))
		var label := "%s (%s)" % [title, source]
		_song_option.add_item(label)
		_song_option.set_item_metadata(i, sid)
		if not pick_id.is_empty() and sid == pick_id:
			selected_index = i

	_song_option.select(selected_index)
	_apply_selected_song_from_ui()


func _apply_selected_song_from_ui() -> void:
	if _song_entries.is_empty():
		return
	await _show_loading("Loading project", "Applying selected song...")
	_is_switching_song = true
	var idx := _song_option.selected
	var song_id: String = str(_song_option.get_item_metadata(idx))
	_selected_song_id = song_id

	var entry: Dictionary = {}
	for e in _song_entries:
		if str(e.get("song_id", "")) == song_id:
			entry = e
			break
	if entry.is_empty():
		_is_switching_song = false
		_hide_loading()
		return

	_song_folder = str(entry.get("root_path", ""))
	_manifest_path = str(entry.get("manifest_path", ""))
	#EditorLog.info("songs", "selected song_id=%s folder=%s" % [_selected_song_id, _song_folder])

	var diffs: Array[String] = []
	for d in (entry.get("difficulties", []) as Array):
		if typeof(d) == TYPE_STRING:
			diffs.append(String(d))

	_difficulty_option.clear()
	if diffs.is_empty():
		diffs = ["expert"]
	for d2 in diffs:
		_difficulty_option.add_item(d2)

	var want := _difficulty.strip_edges().to_lower()
	var diff_idx := 0
	for j in range(diffs.size()):
		if diffs[j].to_lower() == want:
			diff_idx = j
			break
	_difficulty_option.select(diff_idx)
	_difficulty = _difficulty_option.get_item_text(diff_idx).strip_edges().to_lower()

	_chart_path = SongResolver.get_chart_path(_song_folder, _difficulty)
	_is_switching_song = false

	await _load_session()
	_hide_loading()
	_update_status()
	_maybe_show_lane_count_migration_dialog()


func _load_session() -> void:
	if not _project_active and _song_folder.is_empty():
		return
	if not _song_folder.is_empty():
		_manifest_path = SongResolver.get_manifest_path(_song_folder)
		_chart_path = SongResolver.get_chart_path(_song_folder, _difficulty)
		#EditorLog.info("session", "song_folder=%s manifest=%s chart=%s" % [_song_folder, _manifest_path, _chart_path])
	if _chart_path.is_empty():
		_chart_path = "user://custom_songs/unsaved_%d_%s.json" % [Time.get_unix_time_from_system(), _difficulty]
		#EditorLog.warn("session", "no chart path; defaulting to %s" % _chart_path)

	var folder_changed := _loaded_session_folder != _song_folder
	_reset_loaded_resources_for_session(folder_changed)
	var load_generation := _session_load_generation

	var bpm := 120.0
	var has_bpm_from_manifest := false
	var has_bpm_from_chart := false
	var offset := 0.0
	var manifest: Dictionary = {}
	if FileAccess.file_exists(_manifest_path):
		var loaded: Dictionary = ChartLoader.load_json_dictionary(_manifest_path)
		if loaded.get("ok", false):
			manifest = loaded.get("value", {}) as Dictionary
			var mv: Dictionary = ChartValidator.validate_manifest(manifest)
			if ChartValidator.is_valid(mv):
				var manifest_bpm := float(manifest.get("bpm", 0.0))
				if manifest_bpm > 0.0:
					bpm = manifest_bpm
					has_bpm_from_manifest = true
				offset = float(manifest.get("offset", offset))
			else:
				EditorLog.warn("manifest", "invalid manifest at %s" % _manifest_path)
		else:
			EditorLog.err("manifest", "failed to parse %s: %s" % [_manifest_path, str(loaded.get("error", ""))])
	else:
		EditorLog.warn("manifest", "missing %s" % _manifest_path)

	var chart_notes: Array[Dictionary] = []
	var loaded_chart: Dictionary = {}
	_chart_load_error = ""
	_loaded_chart_missing_lane_count = false
	if FileAccess.file_exists(_chart_path):
		var result: Dictionary = ChartLoader.load_hd_chart(_chart_path, _difficulty)
		if result.get("ok", false):
			loaded_chart = result.get("chart", {}) as Dictionary
			for warning_var in (result.get("warnings", []) as Array):
				if warning_var is Dictionary and str((warning_var as Dictionary).get("code", "")) == "missing_lane_count_defaulted":
					_loaded_chart_missing_lane_count = true
					break
			for n in (loaded_chart.get("notes", []) as Array):
				if n is Dictionary:
					chart_notes.append(n as Dictionary)
			var chart_bpm := _extract_chart_bpm(loaded_chart)
			if chart_bpm > 0.0:
				bpm = chart_bpm
				has_bpm_from_chart = true
		else:
			var errs: Array = result.get("errors", []) as Array
			if not errs.is_empty():
				var first: Dictionary = errs[0] as Dictionary
				_chart_load_error = str(first.get("message", "Chart parse error"))
				EditorLog.err("chart", "load failed: %s (%s)" % [_chart_load_error, _chart_path])
			else:
				EditorLog.err("chart", "load failed with unknown error (%s)" % _chart_path)
	else:
		EditorLog.warn("chart", "missing %s (starting empty)" % _chart_path)

	_grid.bpm = bpm
	_grid.offset = offset
	#EditorLog.info("grid", "bpm=%.3f offset=%.3f snap=%s" % [_grid.bpm, _grid.offset, _grid.get_snap_string()])
	_bpm_spin.value = _grid.bpm
	var resolved_lane_count := LaneCountResolver.resolve_chart_lane_count(loaded_chart, manifest)
	if _loaded_chart_missing_lane_count and LaneCountResolver.has_lane_count(manifest):
		resolved_lane_count = LaneCountResolver.lane_count_from_payload(manifest)
	_set_lane_count(resolved_lane_count)
	_notes.set_notes(chart_notes)
	_update_song_info(manifest, loaded_chart)

	var audio_res: Dictionary
	if not _selected_audio_path.is_empty():
		if FileAccess.file_exists(_selected_audio_path):
			audio_res = {"status": "available", "path": _selected_audio_path, "reason": "Selected audio override."}
		else:
			_selected_audio_path = ""
			audio_res = AudioResolver.resolve_audio(manifest, _song_folder)
	else:
		audio_res = AudioResolver.resolve_audio(manifest, _song_folder)
	if audio_res.get("status", "") != "available":
		audio_res = _recover_audio_from_project_sng(manifest, str(audio_res.get("reason", "")))
	_audio_reason = str(audio_res.get("reason", ""))
	if audio_res.get("status", "") == "available":
		var audio_path: String = str(audio_res.get("path", ""))
		var stream := _load_audio_stream(audio_path)
		if stream != null:
			_playback.set_stream(stream)
			_prepare_waveform_for_audio(audio_path, stream)
			_active_audio_path = _runtime_audio_path_for_loaded_audio(audio_path)
			EditorLog.info("audio", "using %s" % audio_path)
		else:
			_active_audio_path = ""
			_playback.set_stream(null)
			_waveform.prepare_from_stream(null)
			_audio_reason = "Audio file was found but could not be loaded: %s" % audio_path
			EditorLog.warn("audio", _audio_reason)
			_notify_audio_missing(_audio_reason)
	else:
		_active_audio_path = ""
		_waveform.prepare_from_stream(null)
		EditorLog.warn("audio", "no audio available: %s" % _audio_reason)
		_notify_audio_missing(_audio_reason)

	_rebuild_audio_options(manifest)
	if _playback.has_audio():
		var should_auto_detect_bpm := not has_bpm_from_manifest and not has_bpm_from_chart
		if should_auto_detect_bpm:
			var audio_path_for_bpm := str(audio_res.get("path", ""))
			if audio_path_for_bpm != _last_auto_bpm_audio_path:
				_last_auto_bpm_audio_path = audio_path_for_bpm
				await _update_loading("Audio loaded. Analyzing BPM before enabling playback...")
				if load_generation != _session_load_generation:
					return
				await _auto_detect_bpm(false, false, load_generation)
				if load_generation != _session_load_generation:
					return
		else:
			await _update_loading("Audio loaded. Using BPM from chart/manifest.")
			if load_generation != _session_load_generation:
				return
			_last_auto_bpm_audio_path = ""
		await _update_loading("Audio ready.")
		if load_generation != _session_load_generation:
			return

	_timeline.set_audio_length(_playback.length_sec())
	_timeline.set_notes(_notes.get_notes())
	_timeline.set_cursor_time(_playback.get_position())
	_vertical_highway.set_audio_length(_playback.length_sec())
	_vertical_highway.set_notes(_notes.get_notes())
	_vertical_highway.set_cursor_time(_playback.get_position())
	_bottom_minimap.set_audio_length(_playback.length_sec())
	_bottom_minimap.set_notes(_notes.get_notes())
	_bottom_minimap.set_cursor_time(_playback.get_position())
	_density_strip.set_audio_length(_playback.length_sec())
	_density_strip.set_notes(_notes.get_notes())
	_density_strip.set_cursor_time(_playback.get_position())
	_loaded_session_folder = _song_folder
	_loaded_session_chart_path = _chart_path


func _extract_chart_bpm(chart: Dictionary) -> float:
	if chart.has("bpm"):
		var direct_bpm := float(chart.get("bpm", 0.0))
		if direct_bpm > 0.0:
			return direct_bpm
	var timing_points_var: Variant = chart.get("timing_points", null)
	if timing_points_var is Array:
		for tp_var in timing_points_var:
			if tp_var is Dictionary:
				var tp: Dictionary = tp_var
				var tp_bpm := float(tp.get("bpm", 0.0))
				if tp_bpm > 0.0:
					return tp_bpm
	return 0.0


func _notify_audio_missing(reason: String) -> void:
	if _song_folder.is_empty():
		return
	if _new_project_start_prompt_requested and _notes.get_note_count() == 0:
		_new_project_start_prompt_requested = false
		call_deferred("_show_start_charting_prompt")
		return
	var key := "%s:%s" % [_song_folder, reason]
	if key == _last_audio_missing_project:
		return
	_last_audio_missing_project = key
	var readable_reason := reason if not reason.strip_edges().is_empty() else "Audio not available."
	_show_message(
			"Audio Not Loaded",
			"Chart data loaded, but the editor could not load or import audio for this project.\n\nReason: %s\n\nYou can continue editing the chart without audio, or use Import Audio to provide a local file or YouTube URL." % readable_reason
	)


func _show_start_charting_prompt() -> void:
	if _start_charting_dialog == null or not _project_active:
		return
	_start_charting_dialog.popup_centered(Vector2i(620, 260))


func _on_start_charting_import_audio() -> void:
	if not _project_active:
		return
	call_deferred("_open_audio_import_dialog")


func _on_start_charting_custom_action(action: StringName) -> void:
	if action != &"import_chart_audio":
		return
	if _start_charting_dialog != null:
		_start_charting_dialog.hide()
	if not _project_active:
		return
	call_deferred("_open_chart_import_dialog")


func _open_audio_import_dialog() -> void:
	if not _project_active:
		return
	_show_audio_source_dialog()


func _open_chart_import_dialog() -> void:
	if not _project_active:
		return
	_chart_import_file_dialog.popup_centered_ratio(0.7)


func _show_audio_source_dialog() -> void:
	if not _project_active:
		return
	if _audio_source_dialog == null:
		_audio_file_dialog.popup_centered_ratio(0.7)
		return
	_audio_source_dialog.popup_centered(Vector2i(520, 210))


func _on_audio_source_local_selected() -> void:
	if not _project_active:
		return
	call_deferred("_open_local_audio_file_dialog")


func _open_local_audio_file_dialog() -> void:
	_audio_file_dialog.popup_centered_ratio(0.7)


func _on_audio_source_custom_action(action: StringName) -> void:
	if action != &"youtube_url":
		return
	if _audio_source_dialog != null:
		_audio_source_dialog.hide()
	_show_youtube_url_dialog()


func _show_youtube_url_dialog() -> void:
	if not _project_active:
		return
	var manifest := _read_manifest()
	if _youtube_url_edit != null:
		_youtube_url_edit.text = str(manifest.get("youtube_url", ""))
	_youtube_url_dialog.popup_centered(Vector2i(660, 260))
	if _youtube_url_edit != null:
		_youtube_url_edit.grab_focus()


func _on_youtube_url_confirmed() -> void:
	if not _project_active or _song_folder.is_empty():
		return
	var url := _youtube_url_edit.text.strip_edges() if _youtube_url_edit != null else ""
	if url.is_empty():
		_show_message("YouTube Import Failed", "Enter a YouTube URL before downloading audio.")
		return
	await _show_loading("Importing YouTube audio", "Downloading source audio with yt-dlp...")
	var result := YouTubeAudioImporter.import_url_to_project(url, _song_folder)
	if not bool(result.get("ok", false)):
		var tool_status := YouTubeAudioImporter.tool_status()
		_hide_loading()
		_show_message(
			"YouTube Import Failed",
			"%s\n\nyt-dlp: %s\nFFmpeg: %s" % [
				str(result.get("error", "Unknown YouTube import error.")),
				str(tool_status.get("yt_dlp", "not found")),
				str(tool_status.get("ffmpeg", "not found")),
			]
		)
		return
	_selected_audio_path = str(result.get("path", ""))
	_set_manifest_youtube_url(url)
	_set_manifest_audio_path(_selected_audio_path)
	await _update_loading("Reloading project audio...")
	await _load_session()
	_reset_editor_view_to_start()
	_hide_loading()
	_status_label.text = "Imported YouTube audio for this project."
	_update_status()


func _on_import_project_pressed() -> void:
	SongResolver.ensure_user_song_dirs()
	var root_abs := ProjectSettings.globalize_path(SongResolver.CUSTOM_ROOT)
	_import_project_file_dialog.current_dir = root_abs
	_import_project_file_dialog.popup_centered_ratio(0.7)


func _on_export_project_pressed() -> void:
	if not _project_active or _song_folder.is_empty():
		return
	if not save_chart():
		return
	var project_abs := ProjectSettings.globalize_path(_song_folder)
	_export_project_file_dialog.current_dir = project_abs
	_export_project_file_dialog.current_file = HarmonicProjectPackage.package_default_filename(_song_folder)
	_export_project_file_dialog.popup_centered_ratio(0.7)


func _on_export_project_file_selected(path: String) -> void:
	if path.strip_edges().is_empty() or _song_folder.is_empty():
		return
	if not save_chart():
		return
	await _show_loading("Exporting project", "Writing .harmonic package...")
	var result := HarmonicProjectPackage.export_project_to_harmonic(_song_folder, path)
	_hide_loading()
	if bool(result.get("ok", false)):
		_status_label.text = "Exported project: %s" % str(result.get("path", ""))
		var audio_summary := "Included local audio." if bool(result.get("included_audio", false)) else "Audio excluded because this project uses a valid YouTube URL."
		_show_message("Project Exported", "Project exported:\n%s\n\n%s" % [str(result.get("path", "")), audio_summary])
	else:
		_show_message("Project Export Failed", str(result.get("error", "Unknown export error.")))


func _on_import_project_file_selected(path: String) -> void:
	if path.strip_edges().is_empty():
		return
	await _show_loading("Importing project", "Extracting .harmonic package...")
	var result := HarmonicProjectPackage.import_harmonic_to_custom_songs(path)
	if not bool(result.get("ok", false)):
		_hide_loading()
		_show_message("Project Import Failed", str(result.get("error", "Unknown import error.")))
		return
	var project_folder := str(result.get("project_folder", ""))
	var youtube_url := str(result.get("youtube_url", "")).strip_edges()
	var audio_warning := ""
	if YouTubeAudioImporter.is_supported_url(youtube_url):
		await _update_loading("Downloading YouTube audio for imported project...")
		var audio_result := YouTubeAudioImporter.import_url_to_project(youtube_url, project_folder)
		if bool(audio_result.get("ok", false)):
			HarmonicProjectPackage.set_manifest_audio_path(project_folder, str(audio_result.get("path", "")))
			HarmonicProjectPackage.set_manifest_youtube_url(project_folder, youtube_url)
		else:
			audio_warning = str(audio_result.get("error", "YouTube audio download failed."))
	await _update_loading("Opening imported project...")
	await _open_project_folder(project_folder, false)
	_hide_loading()
	if audio_warning.is_empty():
		_show_message("Project Imported", "Imported project:\n%s" % project_folder)
	else:
		_show_message("Project Imported Without Audio", "Imported project:\n%s\n\nYouTube audio download failed:\n%s" % [project_folder, audio_warning])


func _on_workshop_upload_pressed() -> void:
	if not _project_active or _song_folder.is_empty():
		return
	if not save_chart():
		return
	if _current_youtube_url().is_empty():
		_workshop_missing_url_dialog.popup_centered(WORKSHOP_MISSING_URL_DIALOG_SIZE)
		return
	_show_workshop_upload_dialog()


func _show_workshop_upload_dialog() -> void:
	if _workshop_upload_dialog == null:
		return
	_workshop_upload_dialog.set_metadata(_workshop_metadata())
	_workshop_upload_dialog.popup_centered()


func _on_workshop_upload_requested(details_in: Dictionary) -> void:
	if not _project_active or _song_folder.is_empty():
		return
	var details := details_in.duplicate(true)
	if not save_chart():
		if _workshop_upload_dialog != null:
			_workshop_upload_dialog.set_status_message("Save failed. Fix chart validation errors before uploading.")
		return
	await _show_loading("Preparing Workshop upload", "Checking chart difficulties...")
	var generation_summary: Dictionary = {}
	if bool(details.get("generate_missing_difficulties", false)):
		await _update_loading("Generating missing difficulties with Smart Clone...")
		generation_summary = _generate_missing_workshop_difficulties()
		var generation_message := _workshop_generation_message(generation_summary)
		if _workshop_upload_dialog != null and not generation_message.is_empty():
			_workshop_upload_dialog.set_status_message(generation_message, generation_summary)
	else:
		_sync_manifest_available_difficulties()
	await _update_loading("Exporting audio-free chart project...")
	var export_folder := _workshop_export_folder()
	var export_result := HarmonicProjectPackage.export_project_to_folder(_song_folder, export_folder, str(details.get("preview_path", "")))
	if not bool(export_result.get("ok", false)):
		_hide_loading()
		if _workshop_upload_dialog != null:
			_workshop_upload_dialog.set_status_message(str(export_result.get("error", "Workshop export failed.")), export_result)
		return
	var upload_result := _workshop_manager.upload_project(str(export_result.get("path", "")), details)
	_hide_loading()
	var message := _workshop_upload_result_message(upload_result, export_result, details, generation_summary)
	_status_label.text = message
	if _workshop_upload_dialog != null:
		_workshop_upload_dialog.set_status_message(message, upload_result)


func _on_workshop_upload_status_changed(status: Dictionary) -> void:
	var message := _workshop_status_event_message(status)
	_status_label.text = message
	if _workshop_upload_dialog != null:
		_workshop_upload_dialog.set_status_message(message, status)


func _workshop_metadata() -> Dictionary:
	var manifest := _read_manifest()
	var metadata := _current_chart_metadata()
	var title := str(metadata.get("title", manifest.get("title", "Harmonic Drive Chart")))
	var author := str(metadata.get("charter", manifest.get("charter", "Player")))
	var tags: Array[String] = ["Chart", "Custom"]
	if not _current_youtube_url().is_empty():
		tags.append("YouTube")
	return {
		"title": title,
		"author": author,
		"description": "Created in the Harmonic Drive Chart Editor.",
		"tags": tags,
		"visibility": "public",
		"change_note": "Uploaded from the Harmonic Drive Chart Editor.",
		"workshop_item_id": str(manifest.get("workshop_item_id", "")),
	}


func _generate_missing_workshop_difficulties() -> Dictionary:
	var source_id := _difficulty.strip_edges().to_lower()
	var available_before := SongPackageManager.list_available_difficulties(_song_folder)
	var missing: Array[String] = []
	for difficulty_id in DifficultyManager.all_ids():
		if not available_before.has(difficulty_id):
			missing.append(difficulty_id)
	if missing.is_empty():
		_sync_manifest_available_difficulties()
		return {
			"requested": true,
			"source": source_id,
			"generated": [],
			"skipped": available_before,
			"failed": [],
			"warning": "",
		}
	if not DifficultyManager.is_valid_id(source_id):
		_sync_manifest_available_difficulties()
		return {
			"requested": true,
			"source": source_id,
			"generated": [],
			"skipped": available_before,
			"failed": missing,
			"warning": "Selected difficulty is not valid for Smart Clone generation.",
		}
	var source_path := SongResolver.get_chart_path(_song_folder, source_id)
	if not FileAccess.file_exists(source_path):
		_sync_manifest_available_difficulties()
		return {
			"requested": true,
			"source": source_id,
			"generated": [],
			"skipped": available_before,
			"failed": missing,
			"warning": "Selected source difficulty is missing: %s" % source_path,
		}
	if not _waveform.is_ready():
		_sync_manifest_available_difficulties()
		return {
			"requested": true,
			"source": source_id,
			"generated": [],
			"skipped": available_before,
			"failed": missing,
			"warning": "Smart Clone requires a waveform preview. Upload will continue with existing difficulties.",
		}

	var generated: Array[String] = []
	var failed: Array[String] = []
	for target_id in missing:
		if target_id == source_id:
			continue
		var result := SongPackageManager.clone_difficulty(
			_song_folder,
			source_id,
			target_id,
			false,
			"smart clone",
			_waveform
		)
		if bool(result.get("ok", false)):
			generated.append(target_id)
		else:
			failed.append("%s: %s" % [target_id, str(result.get("error", "Smart Clone failed."))])
	_sync_manifest_available_difficulties()
	return {
		"requested": true,
		"source": source_id,
		"generated": generated,
		"skipped": available_before,
		"failed": failed,
		"warning": "",
	}


func _sync_manifest_available_difficulties() -> void:
	if _manifest_path.is_empty():
		return
	var manifest := _read_manifest()
	if manifest.is_empty():
		return
	var available := SongPackageManager.list_available_difficulties(_song_folder)
	if available.is_empty():
		return
	manifest["difficulties"] = available
	ChartImportUtils.write_json(_manifest_path, manifest)


func _workshop_generation_message(summary: Dictionary) -> String:
	if summary.is_empty() or not bool(summary.get("requested", false)):
		return ""
	var source_id := str(summary.get("source", "")).strip_edges()
	var generated: Array = summary.get("generated", []) as Array
	var failed: Array = summary.get("failed", []) as Array
	var warning := str(summary.get("warning", "")).strip_edges()
	if not warning.is_empty():
		return "Missing difficulty generation skipped: %s" % warning
	if generated.is_empty() and failed.is_empty():
		return "No missing difficulty charts to generate."
	var parts: Array[String] = []
	if not generated.is_empty():
		parts.append("Generated %s from %s." % [", ".join(_string_array(generated)), source_id])
	if not failed.is_empty():
		parts.append("Could not generate %s." % ", ".join(_string_array(failed)))
	return " ".join(parts)


func _workshop_export_folder() -> String:
	var song_id := ChartImportUtils.sanitize_id(str(_read_manifest().get("song_id", _song_folder.get_file())))
	return "user://workshop_uploads".path_join("%s_%d_%d" % [song_id, Time.get_unix_time_from_system(), Time.get_ticks_msec()])


func _workshop_upload_result_message(upload_result: Dictionary, export_result: Dictionary, details: Dictionary, generation_summary: Dictionary = {}) -> String:
	var message := str(upload_result.get("message", _workshop_manager.get_status()))
	var item_id := str(upload_result.get("item_id", details.get("workshop_item_id", details.get("existing_item_id", "")))).strip_edges()
	var visibility := str((upload_result.get("upload_metadata", {}) as Dictionary).get("visibility", details.get("visibility", "public"))).strip_edges().to_lower()
	var parts: Array[String] = [message]
	var generation_message := _workshop_generation_message(generation_summary)
	if not generation_message.is_empty():
		parts.append(generation_message)
	if not item_id.is_empty():
		parts.append("Item ID: %s." % item_id)
	if not visibility.is_empty():
		parts.append("Visibility: %s." % visibility.capitalize())
	var payload := upload_result.get("upload_payload", {}) as Dictionary
	if not payload.is_empty():
		parts.append("Payload: %s from %s." % [_bytes_label(int(payload.get("payload_size_bytes", 0))), str(payload.get("content_global_path", ""))])
	parts.append("Audio was not included in the Workshop payload.")
	parts.append("Export: %s" % str(export_result.get("path", "")))
	return " ".join(parts)


func _workshop_status_event_message(status: Dictionary) -> String:
	var message := str(status.get("message", _workshop_manager.get_status()))
	var item_id := str(status.get("item_id", "")).strip_edges()
	var parts: Array[String] = [message]
	if not item_id.is_empty():
		parts.append("Item ID: %s." % item_id)
	var result_code := int(status.get("result_code", -1))
	if result_code >= 0 and status.has("result_code"):
		var result_name := str(status.get("result_name", ""))
		parts.append("Steam result: %d%s." % [result_code, " (%s)" % result_name if not result_name.is_empty() else ""])
	if bool(status.get("needs_legal_agreement", false)):
		parts.append("Accept the Steam Workshop legal agreement in Steam if prompted.")
	var log_path := str(status.get("upload_log_path", "")).strip_edges()
	if not log_path.is_empty():
		parts.append("Log: %s." % log_path)
	var progress := status.get("upload_progress", {}) as Dictionary
	if not progress.is_empty():
		var processed := int(progress.get("processed_bytes", 0))
		var total := int(progress.get("total_bytes", 0))
		if total > 0:
			parts.append("Progress: %s / %s." % [_bytes_label(processed), _bytes_label(total)])
	return " ".join(parts)


func _bytes_label(value: int) -> String:
	if value >= 1024 * 1024:
		return "%.1f MB" % (float(value) / float(1024 * 1024))
	if value >= 1024:
		return "%.1f KB" % (float(value) / 1024.0)
	return "%d B" % value


func _string_array(value: Variant) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for item in value:
			var text := str(item).strip_edges()
			if not text.is_empty():
				out.append(text)
	elif not str(value).strip_edges().is_empty():
		out.append(str(value).strip_edges())
	return out


func _recover_audio_from_project_sng(_manifest: Dictionary, previous_reason: String) -> Dictionary:
	if _song_folder.is_empty():
		return {"status": "missing", "path": "", "reason": previous_reason if not previous_reason.is_empty() else "Audio not available."}
	var dir := DirAccess.open(_song_folder)
	if dir == null:
		return {"status": "missing", "path": "", "reason": previous_reason if not previous_reason.is_empty() else "Audio not available."}
	var package_files: Array[String] = []
	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name.is_empty():
			break
		if dir.current_is_dir():
			continue
		var lower_name := String(name).to_lower()
		if lower_name.ends_with(".sng") or lower_name.ends_with(".osz") or lower_name.ends_with(".osk"):
			package_files.append(_song_folder.path_join(name))
	dir.list_dir_end()
	package_files.sort()
	var recovery_errors: Array[String] = []
	for package_path in package_files:
		var ext := package_path.get_extension().to_lower()
		EditorLog.info("audio", "attempting packaged audio recovery from %s" % package_path)
		var extracted_result: Dictionary = ChartImportService.extract_osz_assets(package_path, _song_folder) if ext == "osz" or ext == "osk" else ChartImportService.extract_sng_assets(package_path, _song_folder)
		if not bool(extracted_result.get("ok", false)):
			var extract_error := str(extracted_result.get("error", "unknown extraction error"))
			recovery_errors.append("%s: %s" % [package_path.get_file(), extract_error])
			EditorLog.warn("audio", "Packaged audio recovery extraction failed: %s" % extract_error)
			continue
		var audio_result: Dictionary = ChartImportService.import_osz_audio_if_available(extracted_result, _song_folder) if ext == "osz" or ext == "osk" else ChartImportService.import_sng_audio_if_available(extracted_result, _song_folder)
		if not bool(audio_result.get("ok", false)):
			var audio_error := str(audio_result.get("error", "unknown audio import error"))
			recovery_errors.append("%s: %s" % [package_path.get_file(), audio_error])
			EditorLog.warn("audio", "Packaged audio recovery conversion failed: %s" % audio_error)
			continue
		var path := str(audio_result.get("path", ""))
		if not path.is_empty() and FileAccess.file_exists(path):
			_selected_audio_path = path
			return {"status": "available", "path": path, "reason": "Recovered audio from project package."}
	if not recovery_errors.is_empty():
		return {"status": "missing", "path": "", "reason": "Packaged audio recovery failed: %s" % " | ".join(recovery_errors)}
	if not package_files.is_empty():
		return {"status": "missing", "path": "", "reason": "Packaged chart did not provide a supported audio file."}
	return {"status": "missing", "path": "", "reason": previous_reason if not previous_reason.is_empty() else "Audio not available."}


func _prepare_waveform_for_audio(audio_path: String, stream: AudioStream) -> void:
	if stream == null:
		_waveform.prepare_from_stream(null)
		return
	if stream is AudioStreamWAV:
		_waveform.prepare_from_stream(stream)
		return
	if _song_folder.is_empty():
		_waveform.prepare_from_stream(stream)
		return
	var cache_path: String = _song_folder.path_join("waveform_preview_cache.wav")
	var converted: Dictionary = EditorAudioImporter.convert_to_wav(audio_path, cache_path)
	if not bool(converted.get("ok", false)):
		_waveform.prepare_from_stream(stream)
		EditorLog.warn("waveform", str(converted.get("error", "Failed to decode waveform preview.")))
		return
	var wav: AudioStreamWAV = AudioStreamWAV.load_from_file(ProjectSettings.globalize_path(cache_path))
	if wav == null:
		_waveform.prepare_from_stream(stream)
		EditorLog.warn("waveform", "Failed to load decoded waveform WAV: %s" % cache_path)
		return
	_waveform.prepare_from_stream(wav)


func _load_audio_stream(path: String) -> AudioStream:
	if path.is_empty():
		return null
	if path.begins_with("res://"):
		var res: Resource = ResourceLoader.load(path)
		return res as AudioStream

	# user:// runtime load
	if path.ends_with(".wav"):
		return AudioStreamWAV.load_from_file(ProjectSettings.globalize_path(path))
	if path.ends_with(".ogg"):
		return AudioStreamOggVorbis.load_from_file(ProjectSettings.globalize_path(path))
	if path.ends_with(".mp3"):
		return AudioStreamMP3.load_from_file(ProjectSettings.globalize_path(path))
	if path.ends_with(".opus"):
		var converted: Dictionary = EditorAudioImporter.convert_to_ogg(path, _song_folder.path_join("song.ogg"))
		if bool(converted.get("ok", false)):
			return AudioStreamOggVorbis.load_from_file(ProjectSettings.globalize_path(_song_folder.path_join("song.ogg")))
		EditorLog.warn("audio", str(converted.get("error", "Failed to convert Opus audio.")))
	return null


func _runtime_audio_path_for_loaded_audio(path: String) -> String:
	if path.get_extension().to_lower() == "opus":
		var converted_path := _song_folder.path_join("song.ogg")
		if FileAccess.file_exists(converted_path):
			return converted_path
	return path


func save_chart(update_project_state: bool = true) -> bool:
	var payload := ChartImportUtils.chart_payload(_difficulty, _notes.get_notes(), _lane_count, _current_chart_metadata())
	var validation: Dictionary = ChartValidator.validate_chart(payload, _difficulty)
	if not ChartValidator.is_valid(validation):
		var errs: Array = validation.get("errors", []) as Array
		var first: Dictionary = errs[0] as Dictionary if not errs.is_empty() else {}
		_status_label.text = "Save blocked: %s" % str(first.get("message", "invalid chart"))
		return false

	var json := JSON.stringify(payload, "\t", false)
	if _chart_path.begins_with("res://"):
		_status_label.text = "Save blocked: cannot write to res:// in exports. Use user://."
		return false
	SongResolver.ensure_user_song_dirs()
	var target_path := _chart_path
	var abs := _chart_path
	if _chart_path.begins_with("user://"):
		abs = ProjectSettings.globalize_path(_chart_path)
	else:
		target_path = abs
	DirAccess.make_dir_recursive_absolute(abs.get_base_dir())
	var f := FileAccess.open(target_path, FileAccess.WRITE)
	if f == null:
		_status_label.text = "Save failed: %s" % _chart_path
		return false
	f.store_string(json)
	f.flush()
	if update_project_state:
		_ensure_manifest_has_difficulty(_difficulty)
		_playtest.request_hot_reload()
	_status_label.text = "Saved: %s" % _chart_path
	return true


func _ensure_manifest_has_difficulty(difficulty: String) -> void:
	var manifest: Dictionary = _read_manifest()
	if manifest.is_empty():
		return
	var diffs: Array = []
	if manifest.get("difficulties", []) is Array:
		diffs = manifest.get("difficulties", []) as Array
	if not diffs.has(difficulty):
		diffs.append(difficulty)
	manifest["difficulties"] = diffs
	ChartImportUtils.write_json(_manifest_path, manifest)


func _set_manifest_chart_file(difficulty: String, filename: String) -> void:
	var manifest: Dictionary = _read_manifest()
	if manifest.is_empty():
		return
	var id := difficulty.strip_edges().to_lower()
	var chart_files: Dictionary = manifest.get("chart_files", {}) as Dictionary
	if filename == "%s.json" % id:
		chart_files.erase(id)
	else:
		chart_files[id] = filename.get_file()
	if chart_files.is_empty():
		manifest.erase("chart_files")
	else:
		manifest["chart_files"] = chart_files
	ChartImportUtils.write_json(_manifest_path, manifest)


func _update_status() -> void:
	var pos: float = _playback.get_position()
	var snap: String = _grid.get_snap_string()
	var zoom: int = int(roundf(_vertical_px_per_second if _editor_layout == EditorPreferenceStore.LAYOUT_VERTICAL else _px_per_second))
	var zoom_text := "gameplay" if _vertical_view_mode == EditorPreferenceStore.VIEW_MODE_GAMEPLAY_PREVIEW else "%dpx/s" % zoom
	var mode: String = "HOLD" if _notes.hold_mode else "TAP"
	var layout := "Vertical" if _editor_layout == EditorPreferenceStore.LAYOUT_VERTICAL else "Horizontal"
	var direction := "fall" if _vertical_direction == EditorPreferenceStore.DIRECTION_FALL_DOWN else "rise"
	var view_mode := "gameplay preview" if _vertical_view_mode == EditorPreferenceStore.VIEW_MODE_GAMEPLAY_PREVIEW else "timeline zoom"
	var tool := _vertical_tool.capitalize() if _editor_layout == EditorPreferenceStore.LAYOUT_VERTICAL else "Timeline"
	var audio: String = "audio" if _playback.has_audio() else "no-audio"
	if audio == "no-audio" and not _audio_reason.is_empty():
		audio = "no-audio (%s)" % _audio_reason
	var undo_str := "undo:%d redo:%d" % [1 if _notes.can_undo() else 0, 1 if _notes.can_redo() else 0]
	var mode_hint := "Ctrl/Cmd+H=toggle HOLD  Shift=HOLD (temporary)"
	var threshold_hint := "threshold:%dms" % _notes.get_keyboard_hold_threshold_msec()
	var width_text := " width=%d%%" % int(roundf(_vertical_track_width_scale * 100.0)) if _editor_layout == EditorPreferenceStore.LAYOUT_VERTICAL else ""
	var base: String = "layout=%s%s%s  lanes=%d  tool=%s  t=%.3f  snap=%s  view=%s  zoom=%s  mode=%s  %s  (%s)  %s  %s  notes=%d" % [
		layout,
		" (%s)" % direction if _editor_layout == EditorPreferenceStore.LAYOUT_VERTICAL else "",
		width_text,
		_lane_count,
		tool,
		pos,
		snap,
		view_mode,
		zoom_text,
		mode,
		threshold_hint,
		mode_hint,
		audio,
		undo_str,
		_notes.get_note_count(),
	]
	if not _chart_load_error.is_empty():
		base = "Chart load error: %s  |  %s" % [_chart_load_error, base]
	_status_label.text = base


func _update_timestamp(time_sec: float) -> void:
	var current := _format_timestamp(time_sec)
	var duration := _playback.length_sec()
	var total := _format_timestamp(duration) if duration > 0.0 else "--:--.---"
	_timestamp_label.text = "Time %s / %s" % [current, total]


func _format_timestamp(time_sec: float) -> String:
	var total_msec := maxi(0, int(roundf(time_sec * 1000.0)))
	var milliseconds := total_msec % 1000
	var total_seconds := int(total_msec / 1000)
	var seconds := total_seconds % 60
	var total_minutes := int(total_seconds / 60)
	var minutes := total_minutes % 60
	var hours := int(total_minutes / 60)
	if hours > 0:
		return "%02d:%02d:%02d.%03d" % [hours, minutes, seconds, milliseconds]
	return "%02d:%02d.%03d" % [total_minutes, seconds, milliseconds]


func _update_status_throttled() -> void:
	var now := Time.get_ticks_msec()
	if now - _last_status_update_msec < 125:
		return
	_last_status_update_msec = now
	_update_status()


func _rebuild_audio_options(manifest: Dictionary) -> void:
	_audio_option.clear()
	_audio_option.add_item("Audio: Auto")
	_audio_option.set_item_metadata(0, "")

	var song_id: String = str(manifest.get("song_id", ""))
	var entries: Array[Dictionary] = []
	for e in AudioResolver.list_folder_audio(_song_folder):
		entries.append(e as Dictionary)
	for c in AudioResolver.list_cached_audio(song_id):
		entries.append(c as Dictionary)

	var idx := 1
	for entry in entries:
		var p: String = str(entry.get("path", ""))
		if p.is_empty():
			continue
		var label: String = "Audio: %s" % p.get_file()
		_audio_option.add_item(label)
		_audio_option.set_item_metadata(idx, p)
		idx += 1

	var select_idx := 0
	if not _selected_audio_path.is_empty():
		for i in range(_audio_option.item_count):
			if str(_audio_option.get_item_metadata(i)) == _selected_audio_path:
				select_idx = i
				break
	_audio_option.select(select_idx)


func _on_audio_option_selected() -> void:
	var p: String = str(_audio_option.get_item_metadata(_audio_option.selected))
	_selected_audio_path = p
	#EditorLog.info("audio", "selected audio option: %s" % (_selected_audio_path if not _selected_audio_path.is_empty() else "auto"))
	await _show_loading("Loading audio", "Applying audio selection...")
	await _load_session()
	_hide_loading()
	_update_status()


func _on_audio_file_selected(path: String) -> void:
	if path.is_empty():
		return
	if not _project_active or _song_folder.is_empty():
		_status_label.text = "Open or create a project before importing audio."
		return
	_show_audio_link_dialog(path)


func _show_audio_link_dialog(path: String) -> void:
	_pending_audio_import_folder = path.get_base_dir()
	_pending_audio_link_chart_path = ""
	var audio_files := ImportSourceScanner.ensure_contains(ImportSourceScanner.list_audio_files(_pending_audio_import_folder), path)
	_audio_link_audio_option.clear()
	for i in range(audio_files.size()):
		var audio_path := audio_files[i]
		_audio_link_audio_option.add_item(audio_path.get_file())
		_audio_link_audio_option.set_item_metadata(i, audio_path)
		if audio_path == path:
			_audio_link_audio_option.select(i)

	_audio_link_chart_option.clear()
	_audio_link_chart_option.add_item("Do not import a chart now")
	_audio_link_chart_option.set_item_metadata(0, "")
	_audio_link_chart_option.add_item("Import a chart now")
	_audio_link_chart_option.set_item_metadata(1, AUDIO_LINK_IMPORT_CHART_NOW)
	var chart_files := ImportSourceScanner.list_chart_files(_pending_audio_import_folder)
	for chart_path in chart_files:
		var idx := _audio_link_chart_option.item_count
		_audio_link_chart_option.add_item(chart_path.get_file())
		_audio_link_chart_option.set_item_metadata(idx, chart_path)
	_audio_link_chart_option.select(0)

	_audio_link_dialog.popup_centered(Vector2i(660, 390))


func _on_audio_link_chart_option_selected(index: int) -> void:
	if index < 0 or index >= _audio_link_chart_option.item_count:
		return
	var selected := str(_audio_link_chart_option.get_item_metadata(index))
	if selected != AUDIO_LINK_IMPORT_CHART_NOW:
		_pending_audio_link_chart_path = ""
		return
	_audio_link_chart_file_dialog.current_dir = _pending_audio_import_folder
	_audio_link_chart_file_dialog.popup_centered_ratio(0.7)


func _on_audio_link_chart_file_selected(path: String) -> void:
	if path.is_empty():
		return
	_pending_audio_link_chart_path = path
	for i in range(_audio_link_chart_option.item_count):
		if str(_audio_link_chart_option.get_item_metadata(i)) == path:
			_audio_link_chart_option.select(i)
			return
	var idx := _audio_link_chart_option.item_count
	_audio_link_chart_option.add_item("Selected: %s" % path.get_file())
	_audio_link_chart_option.set_item_metadata(idx, path)
	_audio_link_chart_option.select(idx)


func _on_audio_link_dialog_confirmed() -> void:
	if _audio_link_audio_option == null or _audio_link_audio_option.selected < 0:
		return
	var audio_path := str(_audio_link_audio_option.get_item_metadata(_audio_link_audio_option.selected))
	if audio_path.is_empty():
		return
	await _show_loading("Importing audio", "Copying and preparing %s..." % audio_path.get_file())
	var result := _copy_audio_into_project(audio_path)
	if not bool(result.get("ok", false)):
		_status_label.text = "Audio import failed: %s" % str(result.get("error", "unknown error"))
		EditorLog.err("audio", _status_label.text)
		_hide_loading()
		_show_message("Audio Import Failed", "%s\n\nThe chart remains loaded. Use Import Audio again to provide a local file or YouTube URL." % _status_label.text)
		return
	EditorLog.info("audio", "imported audio to %s" % _selected_audio_path)
	await _update_loading("Reloading project audio...")
	await _load_session()
	_reset_editor_view_to_start()
	_hide_loading()
	_update_status()

	if _audio_link_chart_option != null and _audio_link_chart_option.selected >= 0:
		var chart_path := str(_audio_link_chart_option.get_item_metadata(_audio_link_chart_option.selected))
		if chart_path == AUDIO_LINK_IMPORT_CHART_NOW:
			chart_path = _pending_audio_link_chart_path
		if not chart_path.is_empty():
			await _begin_chart_import(chart_path)


func _copy_audio_into_project(audio_path: String) -> Dictionary:
	var result: Dictionary = EditorAudioImporter.import_audio(audio_path, _song_folder)
	if bool(result.get("ok", false)):
		_selected_audio_path = str(result.get("path", ""))
		_set_manifest_audio_path(_selected_audio_path)
		_set_manifest_youtube_url("")
	return result


func _on_chart_import_file_selected(path: String) -> void:
	if path.is_empty():
		return
	if not _project_active or _song_folder.is_empty():
		_status_label.text = "Open or create a project before importing charts."
		return
	await _begin_chart_import(path)


func _begin_chart_import(path: String) -> void:
	_pending_import_path = path
	_pending_import_folder = path.get_base_dir()
	_pending_import_file_candidates = ImportSourceScanner.ensure_contains(ImportSourceScanner.list_chart_files(_pending_import_folder), path)
	_pending_import_audio_candidates = ImportSourceScanner.list_audio_files(_pending_import_folder)
	_pending_import_audio_path = ""
	if not _is_package_import_path(path) and not _playback.has_audio() and not _pending_import_audio_candidates.is_empty():
		_pending_import_audio_path = _pending_import_audio_candidates[0]
	_pending_import_waveform.clear()
	await _show_loading("Inspecting chart import", "Reading %s..." % path.get_file())
	_pending_import_result = ChartImportService.inspect_import(path, _song_folder)
	if not bool(_pending_import_result.get("ok", false)):
		var import_error := str(_pending_import_result.get("error", "unknown error"))
		_status_label.text = _short_status("Chart import failed", import_error)
		EditorLog.err("import", _status_label.text)
		_hide_loading()
		_show_message("Chart Import Failed", "Chart import failed:\n%s" % import_error)
		return
	if _is_pending_midi_import() and not _pending_import_audio_path.is_empty():
		await _update_loading("Preparing MIDI audio comparison...")
		_prepare_pending_import_waveform()
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
		MidiImportWizardControls.set_audio_available(_midi_import_controls, _active_midi_waveform() != null, _midi_audio_unavailable_reason())
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
	var is_package := _is_package_import_path(_pending_import_path)
	if is_package:
		_import_audio_option.add_item("Packaged audio / auto")
		_import_audio_option.set_item_metadata(0, IMPORT_AUDIO_AUTO)
		_import_audio_option.add_item("Keep current project audio")
		_import_audio_option.set_item_metadata(1, IMPORT_AUDIO_NONE)
	else:
		_import_audio_option.add_item("Keep current project audio")
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
		var entry_notes: Array = entry.get("notes", []) as Array
		var entry_lane_count := int(entry.get("lane_count", LaneCountResolver.infer_from_notes(entry_notes, LaneCountResolver.DEFAULT_LANES)))
		var label: String = "%s — %s (%d notes)" % [
			instrument,
			"%s, %d lanes" % [str(entry.get("difficulty", "expert")).capitalize(), entry_lane_count],
			entry_notes.size()
		]
		_import_source_option.add_item(label)
		_import_source_option.set_item_metadata(i, i)
	if _import_source_option.item_count > 0:
		_import_source_option.select(0)


func _populate_import_difficulty_options(result: Dictionary) -> void:
	_import_difficulty_option.clear()
	for diff in ChartValidator.SUPPORTED_DIFFICULTIES:
		_import_difficulty_option.add_item(diff)
	var default_diff: int = 0
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


func _active_midi_waveform() -> Variant:
	if not _pending_import_audio_path.is_empty():
		return _pending_import_waveform if _pending_import_waveform.is_ready() else null
	return _waveform if _waveform.is_ready() else null


func _on_import_file_option_selected(index: int) -> void:
	if index < 0 or index >= _import_file_option.item_count:
		return
	var path := str(_import_file_option.get_item_metadata(index))
	if path.is_empty() or path == _pending_import_path:
		return
	await _begin_chart_import(path)


func _on_import_audio_option_selected(_index: int) -> void:
	_pending_import_audio_path = _selected_import_audio_source_path()
	_pending_import_waveform.clear()
	if not _pending_import_audio_path.is_empty():
		_prepare_pending_import_waveform()
	if _is_pending_midi_import():
		MidiImportWizardControls.set_audio_available(_midi_import_controls, _active_midi_waveform() != null, _midi_audio_unavailable_reason())
		_refresh_midi_import_preview()


func _prepare_pending_import_waveform() -> void:
	_pending_import_waveform.clear()
	if _pending_import_audio_path.is_empty():
		return
	var wav_path := _pending_import_audio_path
	if _pending_import_audio_path.get_extension().to_lower() != "wav":
		var cache_path := _song_folder.path_join("midi_import_waveform_cache.wav")
		var converted := EditorAudioImporter.convert_to_wav(_pending_import_audio_path, cache_path)
		if not bool(converted.get("ok", false)):
			EditorLog.warn("waveform", str(converted.get("error", "Failed to decode MIDI comparison waveform.")))
			return
		wav_path = str(converted.get("path", ""))
	var wav: AudioStreamWAV = AudioStreamWAV.load_from_file(ProjectSettings.globalize_path(wav_path))
	if wav != null:
		_pending_import_waveform.prepare_from_stream(wav)


func _midi_audio_unavailable_reason() -> String:
	var active_waveform: Variant = _active_midi_waveform()
	if active_waveform == null:
		if _pending_import_audio_path.is_empty() and not _waveform.is_ready():
			return "Audio comparison disabled: select linked audio or load project audio first."
		var reason := _pending_import_waveform.unsupported_reason() if not _pending_import_audio_path.is_empty() else _waveform.unsupported_reason()
		return "Audio comparison disabled: %s" % (reason if not reason.is_empty() else "waveform is not ready.")
	return ""


func _on_midi_import_options_changed() -> void:
	if _is_pending_midi_import():
		_refresh_midi_import_preview()


func _refresh_midi_import_preview() -> void:
	if not _is_pending_midi_import():
		return
	var options := MidiImportWizardControls.read_options(_midi_import_controls)
	var waveform: Variant = _active_midi_waveform()
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
	var width := int(clampf(viewport_size.x * 0.46, 620.0, 860.0))
	var height := int(clampf(viewport_size.y * 0.72, 420.0, 720.0))
	_import_wizard_scroll.custom_minimum_size = Vector2(width - 70, maxf(220.0, float(height) - 150.0))
	_import_wizard_scroll.scroll_vertical = 0
	_import_wizard_dialog.popup_centered(Vector2i(width, height))


func _on_import_wizard_confirmed() -> void:
	if _pending_import_path.is_empty() or _pending_import_result.is_empty():
		return
	var entry_index: int = int(_import_source_option.get_item_metadata(_import_source_option.selected))
	var target_difficulty: String = _import_difficulty_option.get_item_text(_import_difficulty_option.selected).strip_edges().to_lower()
	var selected_audio_mode := _selected_import_audio_mode()
	var selected_audio_source_path := _selected_import_audio_source_path()
	await _show_loading("Importing chart", "Writing %s chart data..." % target_difficulty)
	var midi_options := MidiImportWizardControls.read_options(_midi_import_controls) if _is_pending_midi_import() else {}
	var midi_waveform: Variant = _active_midi_waveform() if _is_pending_midi_import() else null
	var result: Dictionary = ChartImportService.apply_import(_song_folder, _pending_import_path, _pending_import_result, entry_index, target_difficulty, midi_options, midi_waveform)
	if not bool(result.get("ok", false)):
		var import_error := str(result.get("error", "unknown error"))
		_status_label.text = _short_status("Chart import failed", import_error)
		EditorLog.err("import", _status_label.text)
		_hide_loading()
		_show_message("Chart Import Failed", "Chart import failed:\n%s" % import_error)
		return

	var audio_import_warning := ""
	var import_ext := _pending_import_path.get_extension().to_lower()
	if not selected_audio_source_path.is_empty():
		await _update_loading("Importing linked audio...")
		var linked_audio_result := _copy_audio_into_project(selected_audio_source_path)
		if not bool(linked_audio_result.get("ok", false)):
			audio_import_warning = "Linked audio import failed: %s" % str(linked_audio_result.get("error", "unknown error"))
			EditorLog.warn("audio", audio_import_warning)
	elif selected_audio_mode == IMPORT_AUDIO_AUTO and (import_ext == "sng" or import_ext == "osz" or import_ext == "osk"):
		await _update_loading("Extracting packaged chart assets...")
		var extracted_result: Dictionary = {}
		if import_ext == "osz" or import_ext == "osk":
			extracted_result = ChartImportService.extract_osz_assets(_pending_import_path, _song_folder)
		else:
			extracted_result = ChartImportService.extract_sng_assets(_pending_import_path, _song_folder)
		await _update_loading("Preparing packaged audio...")
		var audio_result: Dictionary = {}
		if import_ext == "osz" or import_ext == "osk":
			audio_result = ChartImportService.import_osz_audio_if_available(extracted_result, _song_folder)
		else:
			audio_result = ChartImportService.import_sng_audio_if_available(extracted_result, _song_folder)
		if bool(audio_result.get("ok", false)) and not str(audio_result.get("path", "")).is_empty():
			_selected_audio_path = str(audio_result.get("path", ""))
			_set_manifest_audio_path(_selected_audio_path)
			_set_manifest_youtube_url("")
		elif not bool(audio_result.get("ok", false)):
			audio_import_warning = "Packaged audio import failed: %s" % str(audio_result.get("error", "unknown error"))
			EditorLog.warn("audio", audio_import_warning)
		elif bool(extracted_result.get("ok", false)):
			audio_import_warning = "The packaged chart imported, but no supported audio file was found in the package."
			EditorLog.warn("audio", audio_import_warning)

	_difficulty = target_difficulty
	await _update_loading("Reloading imported chart...")
	_load_project_options()
	await _load_session()
	_reset_editor_view_to_start()
	_hide_loading()
	_status_label.text = "Imported %s to %s." % [_pending_import_path.get_file(), target_difficulty]
	if not audio_import_warning.is_empty():
		_show_message(
				"Chart Imported Without Audio",
				"%s\n\nThe chart was imported successfully and remains editable. Use Import Audio to provide a local file or YouTube URL." % audio_import_warning
		)
	_update_status()


func _auto_detect_bpm(log_failure: bool = true, force: bool = false, expected_generation: int = -1) -> void:
	if expected_generation < 0:
		expected_generation = _session_load_generation
	if _analysis_in_progress:
		if log_failure:
			EditorLog.warn("bpm", "Auto BPM already running.")
		return
	var stream := _audio_player.stream
	if stream == null:
		if log_failure:
			EditorLog.warn("bpm", "No audio loaded.")
		return

	# Fast/offline path for WAV.
	var wav_result: Dictionary = BPMDetector.detect_bpm_from_stream(stream)
	if bool(wav_result.get("ok", false)):
		_apply_bpm_result(wav_result, expected_generation)
		return

	# Realtime capture path for compressed formats (OGG/MP3).
	_analysis_in_progress = true
	EditorLog.info("bpm", "Auto BPM (realtime) started...")
	await _auto_detect_bpm_realtime(stream, force, expected_generation)


func _apply_bpm_result(result: Dictionary, expected_generation: int = -1) -> void:
	if expected_generation >= 0 and expected_generation != _session_load_generation:
		return
	var bpm := float(result.get("bpm", _grid.bpm))
	var conf := float(result.get("confidence", 0.0))
	_grid.bpm = bpm
	_bpm_spin.value = bpm
	EditorLog.info("bpm", "auto bpm=%.3f confidence=%.2f" % [bpm, conf])
	_update_status()


func _ensure_analysis_bus() -> void:
	_analysis_bus_idx = AudioServer.get_bus_index(ANALYSIS_BUS_NAME)
	if _analysis_bus_idx < 0:
		AudioServer.add_bus(-1)
		_analysis_bus_idx = AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(_analysis_bus_idx, ANALYSIS_BUS_NAME)
		AudioServer.set_bus_send(_analysis_bus_idx, &"Master")
		EditorLog.info("audio", "Created analysis bus '%s'" % String(ANALYSIS_BUS_NAME))

	# Ensure capture effect exists.
	var capture: AudioEffectCapture = null
	var effect_count: int = AudioServer.get_bus_effect_count(_analysis_bus_idx)
	for i in range(effect_count):
		var eff: AudioEffect = AudioServer.get_bus_effect(_analysis_bus_idx, i)
		if eff is AudioEffectCapture:
			capture = eff as AudioEffectCapture
			break
	if capture == null:
		capture = AudioEffectCapture.new()
		capture.buffer_length = 2.0
		AudioServer.add_bus_effect(_analysis_bus_idx, capture, 0)
		EditorLog.info("audio", "Added capture effect to analysis bus")
	_analysis_capture = capture


func _auto_detect_bpm_realtime(stream: AudioStream, _force: bool = false, expected_generation: int = -1) -> void:
	# Capture ~16 seconds of decoded audio from the analysis bus.
	if _analysis_bus_idx < 0 or _analysis_capture == null:
		EditorLog.warn("bpm", "Analysis bus not available.")
		_analysis_in_progress = false
		return
	if stream == null:
		EditorLog.warn("bpm", "No stream available for BPM analysis.")
		_analysis_in_progress = false
		return

	# Mute analysis bus while capturing, to avoid blasting the user.
	var prev_db := AudioServer.get_bus_volume_db(_analysis_bus_idx)
	AudioServer.set_bus_volume_db(_analysis_bus_idx, -80.0)

	_analysis_capture.clear_buffer()
	var analysis_player := AudioStreamPlayer.new()
	analysis_player.stream = stream
	analysis_player.bus = ANALYSIS_BUS_NAME
	add_child(analysis_player)
	analysis_player.play(0.0)

	var mix_rate := float(AudioServer.get_mix_rate())
	var envelope_rate := 200.0
	var hop := int(maxf(1.0, mix_rate / envelope_rate))

	var target_seconds := 16.0
	var target_env_len := int(target_seconds * envelope_rate)
	var env: PackedFloat32Array = PackedFloat32Array()
	env.resize(0)

	var frame_accum := 0
	var amp_accum := 0.0
	var last_progress := -1

	while env.size() < target_env_len:
		await get_tree().create_timer(0.05).timeout
		if expected_generation >= 0 and expected_generation != _session_load_generation:
			analysis_player.stop()
			analysis_player.queue_free()
			AudioServer.set_bus_volume_db(_analysis_bus_idx, prev_db)
			_analysis_in_progress = false
			return
		var progress := int(floorf((float(env.size()) / float(target_env_len)) * 100.0))
		if progress >= last_progress + 10:
			last_progress = progress
			if _loading_overlay.visible:
				await _update_loading("Analyzing audio BPM... %d%%" % progress)
		var available := _analysis_capture.get_frames_available()
		if available <= 0:
			continue
		var frames := mini(available, int(mix_rate * 0.25))
		var buf: PackedVector2Array = _analysis_capture.get_buffer(frames)
		if buf.is_empty():
			continue
		for v in buf:
			var mono := (absf(v.x) + absf(v.y)) * 0.5
			amp_accum += mono
			frame_accum += 1
			if frame_accum >= hop:
				env.append(amp_accum / float(frame_accum))
				amp_accum = 0.0
				frame_accum = 0
				if env.size() >= target_env_len:
					break

	analysis_player.stop()
	analysis_player.queue_free()
	AudioServer.set_bus_volume_db(_analysis_bus_idx, prev_db)

	var result: Dictionary = BPMDetector.detect_bpm_from_envelope(env, envelope_rate)
	if not bool(result.get("ok", false)):
		EditorLog.warn("bpm", str(result.get("reason", "Auto BPM failed.")))
		_analysis_in_progress = false
		return
	_apply_bpm_result(result, expected_generation)
	_analysis_in_progress = false
