extends Control

const ChartLoader = preload("res://scripts/gameplay/ChartLoader.gd")
const LaneCountResolver = preload("res://scripts/songs/LaneCountResolver.gd")
const JudgementRules = preload("res://scripts/gameplay/JudgementRules.gd")
const KeyboardInputProvider = preload("res://scripts/input/KeyboardInputProvider.gd")
const ControllerInputProvider = preload("res://scripts/input/ControllerInputProvider.gd")
const HDTheme = preload("res://scripts/ui/HDTheme.gd")
const HDNoteVisual = preload("res://scripts/gameplay/HDNoteVisual.gd")
const GameModeConfig = preload("res://scripts/gameplay/GameModeConfig.gd")
const InputBindingGlyph = preload("res://scripts/ui/InputBindingGlyph.gd")
const SynthesizedRemixGenerator = preload("res://scripts/gameplay/SynthesizedRemixGenerator.gd")
const StemsRandomLaneRandomizer = preload("res://scripts/gameplay/StemsRandomLaneRandomizer.gd")
const ScoreModifierRules = preload("res://scripts/gameplay/ScoreModifierRules.gd")
const NoteSpeedRules = preload("res://scripts/gameplay/NoteSpeedRules.gd")
const EMSGameplayShaderLayer = preload("res://scripts/ems/EMSGameplayShaderLayer.gd")
const EMSPressureWaveLayer = preload("res://scripts/ems/EMSPressureWaveLayer.gd")
const SpiralLaneLayer = preload("res://scripts/gameplay/SpiralLaneLayer.gd")
const BlackHoleLaneLayer = preload("res://scripts/gameplay/BlackHoleLaneLayer.gd")

signal song_finished(result: Dictionary)
signal visualizer_song_finished
signal game_exited
signal editor_live_lane_event(time_sec: float, lane: int, pressed: bool)
signal editor_note_remove_requested(note_id: int)

const SUSTAIN_RELEASE_FORGIVENESS := 0.10
const AUTO_MISS_WINDOW_MULTIPLIER := 1.2
const HOLD_TICK_INTERVAL := 0.10
const HIT_PARTICLE_POOL_SIZE := 96
const ACTUAL_HIT_PARTICLE_POOL_SIZE := 28
const TRAIL_GHOST_POOL_SIZE := 48
const SIDE_BAR_COUNT := 3
const CHORD_COMPLETION_GRACE := 0.045
const DRIVE_METER_LERP_SPEED := 10.0
const DRIVE_METER_MAX := 165.0
const DRIVE_METER_CRITICAL_THRESHOLD := 20.0
const DRIVE_METER_FLASH_DECAY := 4.8
const MODERN_LEFT_PANEL_PATH := "res://UI/left_panel.png"
const MODERN_RIGHT_PANEL_PATH := "res://UI/right_panel.png"
const MODERN_LEFT_PANEL_REGION := Rect2(295.0, 301.0, 909.0, 358.0)
const MODERN_RIGHT_PANEL_REGION := Rect2(344.0, 72.0, 1043.0, 832.0)
const DRIVE_METER_TUNING := {
	"Easy": {"miss_penalty": 0.5, "perfect_gain": 0.5, "great_gain": 0.35, "good_gain": 0.20},
	"Medium": {"miss_penalty": 1.0, "perfect_gain": 0.75, "great_gain": 0.5, "good_gain": 0.25},
	"Hard": {"miss_penalty": 2.0, "perfect_gain": 1.5, "great_gain": 0.75, "good_gain": 0.35},
	"Expert": {"miss_penalty": 3.0, "perfect_gain": 1.5, "great_gain": 0.75, "good_gain": 0.35},
	"Professional": {"miss_penalty": 4.0, "perfect_gain": 2.0, "great_gain": 0.75, "good_gain": 0.25},
}
const SPIRAL_BASE_SPEEDS := {
	"Easy": 0.05236,
	"Medium": 0.07854,
	"Hard": 0.11345,
	"Expert": 0.15708,
	"Professional": 0.20944,
}
const SPIRAL_DENSITY_SPEED_BOOST := 0.27925
const SPIRAL_SPEED_LERP := 2.6
const SPIRAL_DIRECTION_MIN_SECONDS := 4.0
const SPIRAL_DIRECTION_MAX_SECONDS := 9.0
const VISUALIZER_LANE_COUNT := 8

var _song: Dictionary = {}
var _difficulty := "Medium"
var _mode := GameModeConfig.DEFAULT_MODE
var _loadout: Dictionary = {}
var _theme_palette: Dictionary = {}
var _theme_effects_enabled := true
var _chart_background_disabled := false
var _prioritize_fps := false
var _lane_brightness := 1.0
var _note_opacity := 1.0
var _notes_above_judgement_buttons := false
var _hit_effects_mode := "normal"
var _judgement_popups_enabled := true
var _in_game_ui_mode := "classic"
var _song_duration := 0.0
var _chart: Dictionary = {}
var _runtime_chart_hash := ""
var _runtime_chart_seed := 0
var _lane_count := LaneCountResolver.DEFAULT_LANES
var _notes: Array[Dictionary] = []
var _next_note_index := 0
var _next_chart_reactive_index := 0
var _spawned_nodes := {}
var _judged_note_ids := {}
var _pending_chord_groups := {}
var _hold_state := {}
var _active_input_lanes := {}
var _pending_lane_presses := {}
var _lane_press_flush_queued := false
var _last_failed_time_key := -1
var _last_failed_time_key_deadline := 0.0
var _lane_overrides := {}
var _countdown_time := 3.0
var _started := false
var _finished := false
var _is_paused := false
var _is_failed := false
var _failure_stats_recorded := false
var _timing_feedback := ""
var _go_display_time := 0.0
var _editor_live_mode := false
var _editor_live_adding_enabled := false
var _editor_note_removal_enabled := false
var _editor_live_audio_ready := false
var _visualizer_mode := false
var _practice_mode := false
var _practice_scrubbing := false
var _visualizer_reactive_mode := "player"
var _visualizer_manual_energy := 0.0
var _editor_live_note_ids: Dictionary = {}
var _keyboard_input_provider
var _controller_input_provider

var _score := 0
var _combo := 0
var _max_combo := 0
var _judgements := {"Perfect": 0, "Great": 0, "Good": 0, "Miss": 0}
var _weighted_accuracy := 0.0
var _scored_note_count := 0
var _hold_tick_count := 0
var _hold_success_count := 0
var _hold_break_count := 0
var _score_multiplier := 1.0
var _active_gameplay_seconds := 0.0
var _preview_ids := {}
var _judgement_tween: Tween
var _lane_centers: Array = []
var _lane_flash_energy: Array = []
var _receptor_feedback_nodes: Array[Dictionary] = []
var _receptor_press_energy: Array[float] = []
var _left_side_energy: Array = []
var _right_side_energy: Array = []
var _ems_gutter_glow_energy := 0.0
var _particle_pool: Array[ColorRect] = []
var _active_particles: Array = []
var _actual_hit_particle_pool: Array[CPUParticles2D] = []
var _hit_particle_texture: Texture2D
var _trail_pool: Array[ColorRect] = []
var _active_trails: Array = []
var _screen_shake_timer := 0.0
var _screen_shake_strength := 0.0
var _background_decor: Control
var _lane_flash_layer: Control
var _max_gameplay_shader_layer: EMSGameplayShaderLayer
var _ems_pressure_wave_layer: EMSPressureWaveLayer
var _spiral_lane_layer: SpiralLaneLayer
var _black_hole_lane_layer: BlackHoleLaneLayer
var _left_gutter: ColorRect
var _right_gutter: ColorRect
var _left_gutter_image: TextureRect
var _right_gutter_image: TextureRect
var _playfield_ems_background: ColorRect
var _gutter_image_mode := "off"
var _gutter_image_tex_cache: Dictionary = {}
var _last_profile_revision := -1
var _top_glow: PanelContainer
var _bottom_glow: PanelContainer
var _lane_cover: ColorRect
var _grid_lines: Array[ColorRect] = []
var _lane_flash_nodes: Array[ColorRect] = []
var _lane_background_base_alphas: Array[float] = []
var _desktop_left_bars: Array[ColorRect] = []
var _desktop_right_bars: Array[ColorRect] = []
var _runway_sheen_phase := 0.0
var _opponent_snapshot: Dictionary = {}
var _drive_meter := DRIVE_METER_MAX
var _displayed_drive_meter := DRIVE_METER_MAX
var _max_drive_meter := DRIVE_METER_MAX
var _drive_fail_enabled := true
var _no_fail_modifier_active := false
var _drive_meter_enabled := false
var _drive_meter_flash_energy := 0.0
var _drive_meter_reduce_critical_fx := false
var _drive_meter_theme := "auto"
var _drive_meter_frame_style: StyleBoxFlat
var _drive_meter_fill_style: StyleBoxFlat
var _drive_meter_glow_style: StyleBoxFlat
var _spiral_angle := 0.0
var _spiral_speed := 0.0
var _spiral_direction := 1.0
var _spiral_direction_timer := 0.0
var _spiral_lanes_phase := 0.0
var _black_hole_phase := 0.0
var _modern_stats_panel: TextureRect
var _modern_song_panel: TextureRect
var _modern_score_label: Label
var _modern_score_divider: ColorRect
var _modern_multiplier_label: Label
var _modern_multiplier_caption_label: Label
var _modern_combo_vbox: VBoxContainer
var _modern_combo_value_label: Label
var _modern_combo_caption_label: Label
var _modern_song_title_label: Label
var _modern_song_artist_label: Label
var _modern_song_mode_label: Label
var _modern_song_stats_label: Label
var _modern_song_time_label: Label
var _modern_progress_track: ColorRect
var _modern_progress_fill: ColorRect

@onready var _note_layer: Control = %NoteLayer
@onready var _fx_layer: Control = %FXLayer
@onready var _touch_provider = %TouchInputProvider
@onready var _pause_overlay: PanelContainer = %PauseOverlay
@onready var _fail_overlay: PanelContainer = %FailOverlay
@onready var _emotional_motion_left_gutter: Control = %EmotionalMotionLeftGutter
@onready var _emotional_motion_right_gutter: Control = %EmotionalMotionRightGutter
@onready var _lane_backgrounds: HBoxContainer = %LaneBackgrounds
@onready var _runways: HBoxContainer = %Runways
@onready var _receptors: HBoxContainer = %Receptors
@onready var _runway_inset: MarginContainer = $RunwayInset
@onready var _receptor_deck: PanelContainer = %ReceptorDeck
@onready var _receptors_margin: MarginContainer = $ReceptorsMargin
@onready var _hit_rail: ColorRect = $HitRail
@onready var _hit_rail_glow: ColorRect = $HitRailGlow
@onready var _score_pill: PanelContainer = %ScorePill
@onready var _multiplier_pill: PanelContainer = %MultiplierPill
@onready var _opponent_vbox: VBoxContainer = %OpponentVBox
@onready var _pause_button: Button = %PauseButton
@onready var _top_center_vbox: VBoxContainer = $HUD/TopCenterVBox
@onready var _drive_meter_container: Control = %DriveMeterContainer
@onready var _drive_meter_fill_clip: Control = %DriveMeterFillClip
@onready var _drive_meter_frame: PanelContainer = %DriveMeterFrame
@onready var _drive_meter_fill: PanelContainer = %DriveMeterFill
@onready var _drive_meter_glow: PanelContainer = %DriveMeterGlow
@onready var _drive_meter_critical_tint: ColorRect = %DriveMeterCriticalTint
@onready var _practice_transport: PanelContainer = %PracticeTransport
@onready var _practice_play_pause_button: Button = %PracticePlayPauseButton
@onready var _practice_timeline: HSlider = %PracticeTimeline
@onready var _practice_timestamp: Label = %PracticeTimestamp
@onready var _practice_speed_spin: SpinBox = %PracticeSpeedSpin


func _ready() -> void:
	_song = AppState.current_song.duplicate(true)
	_visualizer_mode = AppState.visualizer_active
	_practice_mode = AppState.practice_active
	_visualizer_reactive_mode = AppState.normalize_visualizer_reactive_mode(AppState.visualizer_reactive_mode)
	_editor_live_mode = bool(_song.get("_editor_live_mode", false))
	_difficulty = AppState.current_difficulty
	_mode = AppState.current_mode
	_loadout = AppState.current_loadout.duplicate(true)
	_score_multiplier = _compute_score_multiplier()
	_setup_drive_meter_state()
	if _visualizer_mode or _practice_mode:
		_drive_meter_enabled = false
		_drive_fail_enabled = false
	if _editor_live_mode:
		_drive_meter_enabled = false
		_drive_fail_enabled = false
	_theme_palette = HDTheme.theme_palette(str(_loadout.get("theme", HDTheme.DEFAULT_THEME_ID)))
	_theme_effects_enabled = ProfileStore.are_theme_effects_enabled()
	_chart_background_disabled = ProfileStore.is_chart_background_disabled()
	if _visualizer_mode:
		# Visualizer Mode always uses the same full-EMS composition as Disable Chart Background.
		_chart_background_disabled = true
	_prioritize_fps = ProfileStore.is_prioritize_fps_enabled()
	_lane_brightness = ProfileStore.get_lane_brightness()
	_note_opacity = ProfileStore.get_note_opacity()
	_notes_above_judgement_buttons = ProfileStore.are_notes_above_judgement_buttons()
	_hit_effects_mode = ProfileStore.get_hit_effects_mode()
	_judgement_popups_enabled = ProfileStore.are_judgement_popups_enabled()
	_in_game_ui_mode = ProfileStore.get_in_game_ui_mode()
	if EmotionalMotionSystem != null:
		EmotionalMotionSystem.configure_from_profile()
		EmotionalMotionSystem.set_song_bpm(float(_song.get("bpm", 120.0)))
		if EmotionalMotionSystem.has_signal("loadout_changed") and not EmotionalMotionSystem.loadout_changed.is_connected(_on_ems_loadout_changed):
			EmotionalMotionSystem.loadout_changed.connect(_on_ems_loadout_changed)
		if OS.is_debug_build():
			print("[GameScene] THEME_EFFECTS=%s EMS.enabled=%s bpm=%s" % [
				str(_theme_effects_enabled),
				str(EmotionalMotionSystem.enabled),
				str(float(_song.get("bpm", 120.0))),
			])
	var is_editor_playtest: bool = bool(_song.get("_editor_playtest", false))
	if is_editor_playtest:
		print("[EditorPlaytest][GameScene] boot song_id=%s diff=%s mode=%s audio=%s" % [
			str(_song.get("id", "")),
			_difficulty,
			_mode,
			str(_song.get("audio_path", "")),
		])

	_editor_live_audio_ready = AudioSync.load_stream(
		str(_song.get("audio_path", "")),
		_editor_live_mode
	)
	if _editor_live_audio_ready:
		_song_duration = AudioSync.get_stream_length()
	var chart_path := ""
	var base_chart_hash := ""
	_runtime_chart_seed = 0
	if _visualizer_mode:
		_runtime_chart_hash = ""
		_lane_count = VISUALIZER_LANE_COUNT
		if _visualizer_is_chart_reactive():
			chart_path = ContentRegistry.get_chart_path(_song, _difficulty, _mode)
			base_chart_hash = ContentRegistry.get_chart_hash(_song, _difficulty, _mode)
			_runtime_chart_hash = base_chart_hash
			_chart = ChartLoader.load_chart(chart_path)
			_lane_count = LaneCountResolver.resolve_chart_lane_count(_chart, _song)
		else:
			# Player Reactive needs audio and the eight input bindings, but no chart data.
			_chart = {}
	else:
		chart_path = ContentRegistry.get_chart_path(_song, _difficulty, _mode)
		base_chart_hash = ContentRegistry.get_chart_hash(_song, _difficulty, _mode)
		_runtime_chart_hash = base_chart_hash
		_chart = ChartLoader.load_chart(chart_path)
		_lane_count = LaneCountResolver.resolve_chart_lane_count(_chart, _song)
		if _mode == GameModeConfig.SYNTHESIZED:
			var remix_result: Dictionary = SynthesizedRemixGenerator.generate(_chart, _song, _difficulty, base_chart_hash)
			var remix_chart: Dictionary = remix_result.get("chart", {}) as Dictionary
			if not remix_chart.is_empty():
				_chart = remix_chart
				_lane_count = LaneCountResolver.resolve_chart_lane_count(_chart, _song)
				_runtime_chart_hash = str(remix_result.get("runtime_chart_hash", base_chart_hash))
				_runtime_chart_seed = int(remix_result.get("seed", 0))
				if OS.is_debug_build():
					print("[GameScene] Remix generated notes=%d hash=%s" % [
						int(remix_result.get("generated_note_count", 0)),
						_runtime_chart_hash,
					])
		elif _mode == GameModeConfig.STEMS_RANDOM:
			var stems_random_result: Dictionary = StemsRandomLaneRandomizer.randomize_chart(_chart, _song, _difficulty, base_chart_hash)
			var stems_random_chart: Dictionary = stems_random_result.get("chart", {}) as Dictionary
			if not stems_random_chart.is_empty():
				_chart = stems_random_chart
				_lane_count = LaneCountResolver.resolve_chart_lane_count(_chart, _song)
				_runtime_chart_hash = str(stems_random_result.get("runtime_chart_hash", base_chart_hash))
				_runtime_chart_seed = int(stems_random_result.get("seed", 0))
				if OS.is_debug_build():
					print("[GameScene] Stems Random lane seed=%d hash=%s" % [
						_runtime_chart_seed,
						_runtime_chart_hash,
					])
	if _editor_live_mode:
		var editor_notes: Variant = _song.get("_editor_live_notes", [])
		if editor_notes is Array:
			_chart["notes"] = (editor_notes as Array).duplicate(true)
		var editor_lane_count := int(_song.get("_editor_live_lane_count", _lane_count))
		_lane_count = LaneCountResolver.clamp_lane_count(editor_lane_count)
		_chart["lane_count"] = _lane_count
	if EmotionalMotionSystem != null and _chart.has("bpm"):
		EmotionalMotionSystem.set_song_bpm(float(_chart.get("bpm", _song.get("bpm", 120.0))))
	if is_editor_playtest:
		print("[EditorPlaytest][GameScene] chart_path=%s" % chart_path)
		print("[EditorPlaytest][GameScene] loaded_notes=%d" % int((_chart.get("notes", []) as Array).size() if _chart.get("notes", []) is Array else 0))
	_notes.clear()
	for note_variant in (_chart.get("notes", []) as Array).duplicate(true):
		if note_variant is Dictionary:
			var note: Dictionary = (note_variant as Dictionary).duplicate(true)
			note["lane"] = clampi(int(note.get("lane", 0)), 0, _lane_count - 1)
			_notes.append(note)
	_next_chart_reactive_index = 0
	AppState.sync_input_actions(_lane_count)
	_seed_lane_overrides()
	_ensure_stage_layers()
	_ensure_fx_pools()
	_refresh_maximum_effects_config()
	_apply_theme()
	_configure_practice_transport()
	_build_lane_backgrounds()
	_build_receptors()
	_bind_input()
	_update_song_labels()
	_layout_playfield()
	call_deferred("_layout_playfield")
	var multiplayer_service := null if _editor_live_mode or _visualizer_mode or _practice_mode else _multiplayer_service()
	if multiplayer_service != null:
		if multiplayer_service.has_signal("round_state_updated") and not multiplayer_service.round_state_updated.is_connected(_on_round_state_updated):
			multiplayer_service.round_state_updated.connect(_on_round_state_updated)
		if multiplayer_service.has_method("get_current_round_snapshot"):
			_on_round_state_updated(multiplayer_service.call("get_current_round_snapshot"))
	_pause_overlay.visible = false
	if multiplayer_service != null and multiplayer_service.has_method("is_session_active") and bool(multiplayer_service.call("is_session_active")) and float(multiplayer_service.get("shared_start_time")) > 0.0:
		_countdown_time = maxf(0.0, float(multiplayer_service.get("shared_start_time")) - Time.get_unix_time_from_system())
	if _visualizer_mode:
		_configure_visualizer_presentation()
		call_deferred("_configure_visualizer_presentation")
		_begin_visualizer_song()
	elif _editor_live_mode:
		_started = true
		_is_paused = true
		_countdown_time = 0.0
		%CountdownLabel.text = ""
		%CountdownLabel.modulate.a = 0.0
		%JudgementLabel.text = ""
		_pause_button.visible = false
		_fail_overlay.visible = false
		_touch_provider.visible = false
		_touch_provider.set_process_input(false)
		var editor_start_time := maxf(0.0, float(_song.get("_editor_live_start_time", 0.0)))
		AudioSync.seek(editor_start_time)
		_rebuild_editor_live_notes(editor_start_time)
		_update_hud()
	elif _practice_mode:
		_begin_practice_session()
	else:
		_show_countdown_preview()
	_update_hud()
	AudioSync.playback_finished.connect(_on_audio_finished, CONNECT_ONE_SHOT)
	get_viewport().size_changed.connect(_on_viewport_resized)
	if not resized.is_connected(_on_viewport_resized):
		resized.connect(_on_viewport_resized)
	set_process(true)


func _exit_tree() -> void:
	if _practice_mode:
		AudioSync.reset_speed_scale()
	if EmotionalMotionSystem != null and _max_gameplay_shader_layer != null and is_instance_valid(_max_gameplay_shader_layer):
		EmotionalMotionSystem.unregister_layer(_max_gameplay_shader_layer)


func _configure_practice_transport() -> void:
	_practice_transport.visible = _practice_mode
	if not _practice_mode:
		return
	_practice_transport.add_theme_stylebox_override("panel", HDTheme.overlay_panel_style())
	_practice_play_pause_button.add_theme_stylebox_override("normal", HDTheme.button_style(true))
	_practice_play_pause_button.add_theme_stylebox_override("hover", HDTheme.button_style(true))
	_practice_play_pause_button.add_theme_stylebox_override("pressed", HDTheme.button_style(true))
	_practice_play_pause_button.add_theme_font_size_override("font_size", HDTheme.text_size("button_secondary", _display_size()))
	HDTheme.apply_label(_practice_timestamp, "caption", HDTheme.primary_text(), true)
	var speed_label := _practice_transport.get_node_or_null("Margin/HBox/SpeedLabel") as Label
	if speed_label != null:
		HDTheme.apply_label(speed_label, "caption", HDTheme.SECONDARY, true)
	_practice_timeline.min_value = 0.0
	_practice_timeline.max_value = maxf(0.001, _song_duration)
	_practice_timeline.step = 0.001
	_practice_speed_spin.min_value = AudioSync.MIN_SPEED_SCALE
	_practice_speed_spin.max_value = AudioSync.MAX_SPEED_SCALE
	_practice_speed_spin.step = 0.05
	_practice_speed_spin.value = AudioSync.DEFAULT_SPEED_SCALE
	if not _practice_play_pause_button.pressed.is_connected(_on_practice_play_pause_pressed):
		_practice_play_pause_button.pressed.connect(_on_practice_play_pause_pressed)
	if not _practice_timeline.value_changed.is_connected(_on_practice_timeline_value_changed):
		_practice_timeline.value_changed.connect(_on_practice_timeline_value_changed)
	if not _practice_timeline.drag_started.is_connected(_on_practice_timeline_drag_started):
		_practice_timeline.drag_started.connect(_on_practice_timeline_drag_started)
	if not _practice_timeline.drag_ended.is_connected(_on_practice_timeline_drag_ended):
		_practice_timeline.drag_ended.connect(_on_practice_timeline_drag_ended)
	if not _practice_speed_spin.value_changed.is_connected(_on_practice_speed_changed):
		_practice_speed_spin.value_changed.connect(_on_practice_speed_changed)


func _begin_practice_session() -> void:
	_started = true
	_finished = false
	_is_paused = true
	_countdown_time = 0.0
	%CountdownLabel.text = ""
	%CountdownLabel.modulate.a = 0.0
	%JudgementLabel.text = ""
	_fail_overlay.visible = false
	AudioSync.reset_speed_scale()
	_practice_speed_spin.set_value_no_signal(AudioSync.DEFAULT_SPEED_SCALE)
	AudioSync.seek(0.0)
	_reset_practice_score()
	_rebuild_editor_playtest_notes(0.0)
	_update_practice_transport()
	_update_hud()


func _update_practice_transport() -> void:
	if not _practice_mode or not is_instance_valid(_practice_transport):
		return
	var current_time := clampf(AudioSync.get_song_time_raw(), 0.0, maxf(0.0, _song_duration))
	if not _practice_scrubbing:
		_practice_timeline.set_value_no_signal(current_time)
	_practice_timestamp.text = _formatted_song_time(current_time, _song_duration)
	_practice_play_pause_button.text = "PLAY" if _is_paused or not AudioSync.is_playing() else "PAUSE"


func _on_practice_play_pause_pressed() -> void:
	if not _practice_mode:
		return
	if not _is_paused and AudioSync.is_playing():
		AudioSync.pause_playback()
		_is_paused = true
		_active_input_lanes.clear()
	else:
		var current_time := AudioSync.get_song_time_raw()
		if _song_duration > 0.0 and current_time >= _song_duration - 0.001:
			AudioSync.seek(0.0)
			_reset_practice_score()
			_rebuild_editor_playtest_notes(0.0)
		_ensure_practice_audio_finished_connection()
		_is_paused = false
		AudioSync.resume_playback()
	_practice_play_pause_button.release_focus()
	_update_practice_transport()


func _on_practice_timeline_drag_started() -> void:
	_practice_scrubbing = true


func _on_practice_timeline_drag_ended(_value_changed: bool) -> void:
	_practice_scrubbing = false
	_seek_practice_timeline(float(_practice_timeline.value))


func _on_practice_timeline_value_changed(value: float) -> void:
	if not _practice_mode:
		return
	_seek_practice_timeline(value)


func _seek_practice_timeline(time_sec: float) -> void:
	var clamped := clampf(time_sec, 0.0, maxf(0.0, _song_duration))
	AudioSync.seek(clamped)
	_reset_practice_score()
	_rebuild_editor_playtest_notes(_current_chart_time())
	_practice_timestamp.text = _formatted_song_time(clamped, _song_duration)
	_update_hud()


func _on_practice_speed_changed(value: float) -> void:
	if not _practice_mode:
		return
	AudioSync.set_speed_scale(value)
	_practice_speed_spin.release_focus()


func _ensure_practice_audio_finished_connection() -> void:
	if not AudioSync.playback_finished.is_connected(_on_audio_finished):
		AudioSync.playback_finished.connect(_on_audio_finished, CONNECT_ONE_SHOT)


func _display_size() -> Vector2:
	# GameScene can fill either the main viewport or an editor-owned runtime holder.
	# Its own Control size is the authoritative stage size in both cases.
	if size.x > 1.0 and size.y > 1.0:
		return size
	return get_viewport_rect().size


func _configure_visualizer_presentation() -> void:
	if not _visualizer_is_chart_reactive():
		_chart.clear()
		_notes.clear()
	_spawned_nodes.clear()
	_next_note_index = 0
	_drive_meter_enabled = false
	_drive_fail_enabled = false
	for node in [
		%Background,
		_lane_backgrounds,
		_runway_inset,
		_note_layer,
		_fx_layer,
		_touch_provider,
		_receptor_deck,
		_hit_rail_glow,
		_hit_rail,
		_receptors_margin,
		$HUD,
		_pause_overlay,
		_fail_overlay,
		_background_decor,
		_lane_flash_layer,
		_spiral_lane_layer,
		_black_hole_lane_layer,
		_max_gameplay_shader_layer,
		_ems_pressure_wave_layer,
	]:
		if node == null or not is_instance_valid(node):
			continue
		if node is CanvasItem:
			(node as CanvasItem).visible = false
		node.set_process(false)
		node.set_physics_process(false)
		if node is Control:
			(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	_touch_provider.set_process_input(false)
	_update_visualizer_background(0.0)
	_refresh_maximum_effects_config()
	_layout_visualizer_ems()


func _layout_visualizer_ems() -> void:
	var viewport_size := _display_size()
	var center_x := floorf(viewport_size.x * 0.5)
	if _emotional_motion_left_gutter != null:
		_emotional_motion_left_gutter.anchor_left = 0.0
		_emotional_motion_left_gutter.anchor_right = 0.0
		_emotional_motion_left_gutter.anchor_top = 0.0
		_emotional_motion_left_gutter.anchor_bottom = 1.0
		_emotional_motion_left_gutter.offset_left = 0.0
		_emotional_motion_left_gutter.offset_top = 0.0
		_emotional_motion_left_gutter.offset_right = center_x
		_emotional_motion_left_gutter.offset_bottom = 0.0
		_emotional_motion_left_gutter.visible = true
		_emotional_motion_left_gutter.set_process(true)
		_emotional_motion_left_gutter.set_physics_process(true)
	if _emotional_motion_right_gutter != null:
		_emotional_motion_right_gutter.anchor_left = 0.0
		_emotional_motion_right_gutter.anchor_right = 0.0
		_emotional_motion_right_gutter.anchor_top = 0.0
		_emotional_motion_right_gutter.anchor_bottom = 1.0
		_emotional_motion_right_gutter.offset_left = center_x
		_emotional_motion_right_gutter.offset_top = 0.0
		_emotional_motion_right_gutter.offset_right = viewport_size.x
		_emotional_motion_right_gutter.offset_bottom = 0.0
		_emotional_motion_right_gutter.visible = true
		_emotional_motion_right_gutter.set_process(true)
		_emotional_motion_right_gutter.set_physics_process(true)


func _begin_visualizer_song() -> void:
	_started = true
	_countdown_time = 0.0
	_visualizer_manual_energy = 0.0
	var visualizer_bpm := float(_chart.get("bpm", _song.get("bpm", 120.0)))
	if EmotionalMotionSystem != null:
		EmotionalMotionSystem.reseed_run_palette()
		EmotionalMotionSystem.set_song_bpm(visualizer_bpm)
		if _visualizer_is_chart_reactive():
			EmotionalMotionSystem.set_combo_count(0)
		else:
			EmotionalMotionSystem.set_combo_energy(0.42)
		EmotionalMotionSystem.set_note_density(0.12)
		EmotionalMotionSystem.set_emotional_state("euphoric")
		EmotionalMotionSystem.dispatch_ems_event("song_started", {
			"song_id": str(_song.get("id", "")),
			"mode": "visualizer",
			"bpm": visualizer_bpm,
			"strength": 1.0,
		})
	if not AudioSync.load_stream(str(_song.get("audio_path", ""))):
		call_deferred("_on_audio_finished")
		return
	_song_duration = AudioSync.get_stream_length()
	AudioSync.play_from_start()


func _visualizer_is_chart_reactive() -> bool:
	return _visualizer_reactive_mode == AppState.VISUALIZER_REACTIVE_CHART


func _apply_theme() -> void:
	var size := _display_size()
	var mobile_hud: bool = AppState.is_mobile_platform()
	var background_color: Color = _theme_palette.get("background", Color(0.02, 0.03, 0.08, 1.0))
	background_color.a = 1.0
	var ambient_color: Color = _theme_palette.get("ambient", HDTheme.CYAN * Color(1, 1, 1, 0.12)) if _theme_effects_enabled else Color(1, 1, 1, 0.0)
	%Background.color = background_color
	%Background.visible = not _chart_background_disabled
	var gutter_color: Color = _theme_palette.get("gutter", background_color)
	# If EMS is enabled, the gutter background becomes EMS-controlled (still outside lanes only).
	if _theme_effects_enabled and EmotionalMotionSystem != null and EmotionalMotionSystem.enabled:
		gutter_color = EmotionalMotionSystem.get_gutter_background_color()
	_left_gutter.color = gutter_color
	_right_gutter.color = gutter_color
	_left_gutter.visible = true
	_right_gutter.visible = true
	if _playfield_ems_background != null:
		_playfield_ems_background.color = _transparent_ems_canvas_color()
	_lane_cover.color = background_color.lerp(Color.BLACK, 0.18) * Color(1, 1, 1, 0.94)
	_apply_glow_style(_top_glow, _theme_palette.get("background_top", background_color), ambient_color)
	_apply_glow_style(_bottom_glow, _theme_palette.get("background_bottom", background_color), ambient_color)
	var grid_color: Color = _theme_palette.get("grid", HDTheme.CYAN * Color(1, 1, 1, 0.10)) if _theme_effects_enabled else Color(1, 1, 1, 0.0)
	for line in _grid_lines:
		line.visible = _theme_effects_enabled and not _prioritize_fps and not _chart_background_disabled
		line.color = grid_color
	var side_colors: Array = _theme_palette.get("side_fx", [ambient_color, ambient_color, ambient_color])
	for index in _desktop_left_bars.size():
		var side_color: Color = side_colors[index % side_colors.size()]
		_desktop_left_bars[index].visible = _theme_effects_enabled and not _prioritize_fps and not _chart_background_disabled
		_desktop_right_bars[index].visible = _theme_effects_enabled and not _prioritize_fps and not _chart_background_disabled
		_desktop_left_bars[index].color = side_color * Color(1, 1, 1, 0.22)
		_desktop_right_bars[index].color = side_color * Color(1, 1, 1, 0.22)
	for lane in _lane_flash_nodes.size():
		_lane_flash_nodes[lane].color = _lane_color(lane) * Color(1, 1, 1, 0.18)
	var receptor_deck_style := StyleBoxFlat.new()
	receptor_deck_style.bg_color = Color(0, 0, 0, 0)
	_receptor_deck.add_theme_stylebox_override("panel", receptor_deck_style)
	_receptor_deck.visible = false
	_score_pill.add_theme_stylebox_override("panel", HDTheme.card_style())
	_multiplier_pill.add_theme_stylebox_override("panel", HDTheme.card_style())
	_pause_button.add_theme_stylebox_override("normal", HDTheme.card_style())
	_pause_button.add_theme_stylebox_override("hover", HDTheme.card_style())
	_pause_button.add_theme_stylebox_override("pressed", HDTheme.card_style())
	%PauseOverlay.add_theme_stylebox_override("panel", HDTheme.overlay_panel_style())
	%FailOverlay.add_theme_stylebox_override("panel", HDTheme.overlay_panel_style())
	var overlay_metrics := HDTheme.overlay_metrics(size)
	%PauseOverlay.custom_minimum_size = Vector2(overlay_metrics["panel_width"] * 0.62, overlay_metrics["panel_height"] * 0.46)
	for button in [%ResumeButton, %RestartButton, %ExitButton]:
		button.custom_minimum_size.y = overlay_metrics["button_height"]
		button.add_theme_stylebox_override("normal", HDTheme.button_style(button == %ResumeButton))
		button.add_theme_stylebox_override("hover", HDTheme.button_style(button == %ResumeButton))
		button.add_theme_stylebox_override("pressed", HDTheme.button_style(button == %ResumeButton))
		button.add_theme_font_size_override("font_size", HDTheme.text_size("button_secondary", size))
	%FailOverlay.custom_minimum_size = Vector2(overlay_metrics["panel_width"] * 0.68, overlay_metrics["panel_height"] * 0.52)
	HDTheme.apply_label(%PauseTitleLabel, "screen_title", HDTheme.CYAN, true)
	HDTheme.apply_label(%FailTitleLabel, "screen_title", HDTheme.MISS, true)
	HDTheme.apply_label(%FailSubtitleLabel, "body", HDTheme.SECONDARY, true)
	for button in [%RetryButton, %PracticeButton, %FailQuitButton]:
		button.custom_minimum_size.y = overlay_metrics["button_height"]
		button.add_theme_stylebox_override("normal", HDTheme.button_style(button == %RetryButton))
		button.add_theme_stylebox_override("hover", HDTheme.button_style(button == %RetryButton))
		button.add_theme_stylebox_override("pressed", HDTheme.button_style(button == %RetryButton))
		button.add_theme_font_size_override("font_size", HDTheme.text_size("button_secondary", size))
	HDTheme.apply_label(%ScoreLabel, "section_title", HDTheme.primary_text(), true)
	HDTheme.apply_label(%MultiplierLabel, "button_secondary", Color(1.0, 0.85, 0.2, 1.0), true)
	HDTheme.apply_label(%OpponentNameLabel, "caption", HDTheme.SECONDARY, false)
	HDTheme.apply_label(%OpponentScoreLabel, "body", HDTheme.primary_text(), false)
	HDTheme.apply_label(%OpponentComboLabel, "caption", HDTheme.TERTIARY, false)
	HDTheme.apply_label(%ComboLabel, "section_title", HDTheme.primary_text(), false)
	%ComboLabel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if mobile_hud else HORIZONTAL_ALIGNMENT_LEFT
	%ComboLabel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	HDTheme.apply_label(%TrackLabel, "body", HDTheme.SECONDARY, false)
	%TrackLabel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if mobile_hud else HORIZONTAL_ALIGNMENT_LEFT
	%TrackLabel.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	%TrackLabel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	%TrackLabel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	HDTheme.apply_label(%TimeLabel, "caption", HDTheme.TERTIARY, false)
	%TimeLabel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if mobile_hud else HORIZONTAL_ALIGNMENT_LEFT
	%TimeLabel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	HDTheme.apply_label(%JudgementLabel, "screen_title", HDTheme.primary_text(), true)
	HDTheme.apply_label(%CountdownLabel, "screen_title", HDTheme.primary_text(), true)
	_ensure_modern_hud()
	_style_modern_hud(size)
	_apply_hud_mode()
	_apply_drive_meter_theme()
	_score_pill.size = Vector2(140, 46)
	_multiplier_pill.size = Vector2(82, 34)
	_pause_button.custom_minimum_size = Vector2(64, 56)
	_pause_button.add_theme_font_size_override("font_size", HDTheme.text_size("button_secondary", size))
	_hit_rail_glow.visible = not _prioritize_fps
	_layout_playfield()


func _ensure_modern_hud() -> void:
	if _modern_stats_panel != null and is_instance_valid(_modern_stats_panel):
		return
	var hud := $HUD
	_modern_stats_panel = _make_modern_panel_texture("ModernStatsPanel", MODERN_LEFT_PANEL_PATH, MODERN_LEFT_PANEL_REGION)
	hud.add_child(_modern_stats_panel)

	_modern_score_label = _make_modern_hud_label("ModernScoreLabel", "0")
	_modern_stats_panel.add_child(_modern_score_label)
	_modern_score_divider = ColorRect.new()
	_modern_score_divider.name = "ModernScoreDivider"
	_modern_score_divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modern_stats_panel.add_child(_modern_score_divider)
	_modern_multiplier_label = _make_modern_hud_label("ModernMultiplierLabel", "x1")
	_modern_stats_panel.add_child(_modern_multiplier_label)
	_modern_multiplier_caption_label = _make_modern_hud_label("ModernMultiplierCaptionLabel", "MULTIPLIER")
	_modern_stats_panel.add_child(_modern_multiplier_caption_label)

	_modern_combo_vbox = VBoxContainer.new()
	_modern_combo_vbox.name = "ModernComboVBox"
	_modern_combo_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modern_combo_vbox.z_index = 4
	_modern_combo_vbox.add_theme_constant_override("separation", -2)
	hud.add_child(_modern_combo_vbox)
	_modern_combo_value_label = _make_modern_hud_label("ModernComboValueLabel", "0")
	_modern_combo_vbox.add_child(_modern_combo_value_label)
	_modern_combo_caption_label = _make_modern_hud_label("ModernComboCaptionLabel", "COMBO")
	_modern_combo_vbox.add_child(_modern_combo_caption_label)

	_modern_song_panel = _make_modern_panel_texture("ModernSongPanel", MODERN_RIGHT_PANEL_PATH, MODERN_RIGHT_PANEL_REGION)
	hud.add_child(_modern_song_panel)
	_modern_song_title_label = _make_modern_hud_label("ModernSongTitleLabel", "")
	_modern_song_panel.add_child(_modern_song_title_label)
	_modern_song_artist_label = _make_modern_hud_label("ModernSongArtistLabel", "")
	_modern_song_panel.add_child(_modern_song_artist_label)
	_modern_song_mode_label = _make_modern_hud_label("ModernSongModeLabel", "")
	_modern_song_panel.add_child(_modern_song_mode_label)
	_modern_song_stats_label = _make_modern_hud_label("ModernSongStatsLabel", "")
	_modern_song_panel.add_child(_modern_song_stats_label)
	_modern_song_time_label = _make_modern_hud_label("ModernSongTimeLabel", "0:00 / 0:00")
	_modern_song_panel.add_child(_modern_song_time_label)
	_modern_progress_track = ColorRect.new()
	_modern_progress_track.name = "ModernSongProgressTrack"
	_modern_progress_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modern_song_panel.add_child(_modern_progress_track)
	_modern_progress_fill = ColorRect.new()
	_modern_progress_fill.name = "ModernSongProgressFill"
	_modern_progress_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modern_song_panel.add_child(_modern_progress_fill)


func _make_modern_panel_texture(node_name: String, source_path: String, source_region: Rect2) -> TextureRect:
	var source_texture := load(source_path) as Texture2D
	if source_texture == null:
		var image := Image.load_from_file(source_path)
		if image != null and not image.is_empty():
			source_texture = ImageTexture.create_from_image(image)
		else:
			push_warning("Unable to load modern HUD panel texture: %s" % source_path)

	var atlas := AtlasTexture.new()
	atlas.atlas = source_texture
	atlas.region = source_region

	var panel := TextureRect.new()
	panel.name = node_name
	panel.texture = atlas
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.z_index = 4
	panel.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	panel.stretch_mode = TextureRect.STRETCH_SCALE
	return panel


func _make_modern_hud_label(node_name: String, initial_text: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = initial_text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	return label


func _style_modern_hud(viewport_size: Vector2) -> void:
	_ensure_modern_hud()
	var scale := clampf(viewport_size.x / 1672.0, 0.66, 1.05)
	if viewport_size.y < 760.0:
		scale = minf(scale, 0.86)
	var magenta := Color(0.96, 0.15, 1.0, 1.0)
	var cyan := Color(0.16, 0.88, 1.0, 1.0)
	var white := Color(1.0, 1.0, 1.0, 0.96)
	var pale := Color(1.0, 1.0, 1.0, 0.86)
	_modern_score_divider.color = magenta * Color(1.0, 1.0, 1.0, 0.76)
	_modern_progress_track.color = Color(0.10, 0.16, 0.35, 0.70)
	_modern_progress_fill.color = Color(0.12, 0.96, 0.96, 0.95)
	_style_modern_label(_modern_score_label, int(round(40.0 * scale)), white, HORIZONTAL_ALIGNMENT_LEFT, true)
	_style_modern_label(_modern_multiplier_label, int(round(25.0 * scale)), Color(1.0, 0.85, 0.16, 1.0), HORIZONTAL_ALIGNMENT_LEFT, true)
	_style_modern_label(_modern_multiplier_caption_label, int(round(13.0 * scale)), pale, HORIZONTAL_ALIGNMENT_LEFT, true)
	_style_modern_label(_modern_combo_value_label, int(round(38.0 * scale)), white, HORIZONTAL_ALIGNMENT_LEFT, true)
	_style_modern_label(_modern_combo_caption_label, int(round(19.0 * scale)), cyan, HORIZONTAL_ALIGNMENT_LEFT, true)
	_style_modern_label(_modern_song_title_label, int(round(17.0 * scale)), white, HORIZONTAL_ALIGNMENT_LEFT, true)
	_style_modern_label(_modern_song_artist_label, int(round(14.0 * scale)), pale, HORIZONTAL_ALIGNMENT_LEFT, false)
	_style_modern_label(_modern_song_mode_label, int(round(14.0 * scale)), pale, HORIZONTAL_ALIGNMENT_LEFT, false)
	_style_modern_label(_modern_song_stats_label, int(round(13.0 * scale)), pale, HORIZONTAL_ALIGNMENT_LEFT, false)
	_style_modern_label(_modern_song_time_label, int(round(14.0 * scale)), white, HORIZONTAL_ALIGNMENT_LEFT, false)


func _style_modern_label(label: Label, font_size: int, color: Color, alignment: int, glow: bool) -> void:
	if label == null:
		return
	label.horizontal_alignment = alignment
	label.add_theme_font_size_override("font_size", maxi(10, font_size))
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", color * Color(1.0, 1.0, 1.0, 0.38 if glow else 0.18))
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", 0)
	label.add_theme_constant_override("shadow_outline_size", 5 if glow else 2)


func _is_modern_in_game_ui() -> bool:
	return _in_game_ui_mode == "modern"


func _apply_hud_mode() -> void:
	_ensure_modern_hud()
	var modern := _is_modern_in_game_ui()
	_score_pill.visible = not modern
	_multiplier_pill.visible = not modern
	_top_center_vbox.visible = not modern
	if modern:
		_opponent_vbox.visible = false
	_modern_stats_panel.visible = modern
	_modern_song_panel.visible = modern
	_modern_combo_vbox.visible = modern


func _update_modern_song_labels(title: String, artist: String, chart_difficulty: String, stats_line: String) -> void:
	if _modern_song_title_label == null:
		return
	_modern_song_title_label.text = title
	_modern_song_artist_label.text = artist
	_modern_song_mode_label.text = "%s / %s" % [GameModeConfig.get_display_name(_mode), chart_difficulty]
	_modern_song_stats_label.text = stats_line
	_modern_song_time_label.text = _formatted_song_time(0.0, _song_duration)


func _update_modern_hud(current_time: float) -> void:
	if _modern_score_label == null:
		return
	_modern_score_label.text = "%d" % _score
	_modern_multiplier_label.text = "x%d" % JudgementRules.combo_multiplier(_combo)
	_modern_combo_value_label.text = "%d" % _combo
	_modern_song_time_label.text = _formatted_song_time(current_time, _song_duration)
	if _modern_progress_track != null and _modern_progress_fill != null:
		var ratio := 0.0
		if _song_duration > 0.0:
			ratio = clampf(current_time / _song_duration, 0.0, 1.0)
		_modern_progress_fill.position = _modern_progress_track.position
		_modern_progress_fill.size = Vector2(_modern_progress_track.size.x * ratio, _modern_progress_track.size.y)


func _layout_modern_hud(viewport_size: Vector2) -> void:
	if _modern_stats_panel == null:
		return
	var scale := clampf(viewport_size.x / 1672.0, 0.66, 1.05)
	if viewport_size.y < 760.0:
		scale = minf(scale, 0.86)
	var top := clampf(viewport_size.y * 0.058, 40.0, 64.0)
	var stats_width := clampf(viewport_size.x * 0.155, 228.0, 268.0)
	var stats_height := clampf(viewport_size.y * 0.175, 146.0, 188.0)
	var song_width := clampf(viewport_size.x * 0.158, 248.0, 292.0)
	var song_height := stats_height
	if viewport_size.x < 920.0:
		stats_width = clampf(viewport_size.x * 0.38, 204.0, 248.0)
		song_width = clampf(viewport_size.x * 0.42, 220.0, 268.0)
		stats_height = clampf(viewport_size.y * 0.16, 132.0, 164.0)
		song_height = stats_height
		top = 30.0
	_modern_stats_panel.position = Vector2(0.0, top)
	_modern_stats_panel.size = Vector2(stats_width, stats_height)
	_modern_song_panel.position = Vector2(viewport_size.x - song_width, top)
	_modern_song_panel.size = Vector2(song_width, song_height)

	var left_pad := 28.0 * scale
	_modern_score_label.position = Vector2(left_pad, 24.0 * scale)
	_modern_score_label.size = Vector2(stats_width - left_pad - 44.0 * scale, 42.0 * scale)
	_modern_score_divider.position = Vector2(left_pad, 78.0 * scale)
	_modern_score_divider.size = Vector2(stats_width - left_pad - 44.0 * scale, maxf(2.0, 2.0 * scale))
	_modern_multiplier_label.position = Vector2(left_pad, 96.0 * scale)
	_modern_multiplier_label.size = Vector2(stats_width - left_pad - 46.0 * scale, 30.0 * scale)
	_modern_multiplier_caption_label.position = Vector2(left_pad, 128.0 * scale)
	_modern_multiplier_caption_label.size = Vector2(stats_width - left_pad - 46.0 * scale, 21.0 * scale)

	var combo_top := clampf(viewport_size.y * 0.625, top + stats_height + 26.0, viewport_size.y - 146.0)
	_modern_combo_vbox.position = Vector2(34.0 * scale, combo_top)
	_modern_combo_vbox.size = Vector2(150.0 * scale, 88.0 * scale)
	_modern_combo_value_label.custom_minimum_size = Vector2(150.0 * scale, 46.0 * scale)
	_modern_combo_caption_label.custom_minimum_size = Vector2(150.0 * scale, 30.0 * scale)

	var song_pad := 32.0 * scale
	var line_h := 21.0 * scale
	var song_content_width := song_width - song_pad - 24.0 * scale
	_modern_song_title_label.position = Vector2(song_pad, 24.0 * scale)
	_modern_song_title_label.size = Vector2(song_content_width, line_h)
	_modern_song_artist_label.position = Vector2(song_pad, 52.0 * scale)
	_modern_song_artist_label.size = Vector2(song_content_width, line_h)
	_modern_song_mode_label.position = Vector2(song_pad, 78.0 * scale)
	_modern_song_mode_label.size = Vector2(song_content_width, line_h)
	_modern_song_stats_label.position = Vector2(song_pad, 104.0 * scale)
	_modern_song_stats_label.size = Vector2(song_content_width, line_h)
	_modern_song_time_label.position = Vector2(song_pad, 132.0 * scale)
	_modern_song_time_label.size = Vector2(song_content_width, line_h)
	_modern_progress_track.position = Vector2(song_pad, song_height - 32.0 * scale)
	_modern_progress_track.size = Vector2(song_content_width, maxf(3.0, 5.0 * scale))
	_update_modern_hud(0.0 if not _started else AudioSync.get_song_time_raw())

	if _is_modern_in_game_ui():
		_pause_button.offset_top = minf(_modern_song_panel.position.y + _modern_song_panel.size.y + 14.0, viewport_size.y - _pause_button.custom_minimum_size.y - 18.0)
		_pause_button.offset_bottom = _pause_button.offset_top + _pause_button.custom_minimum_size.y
	_apply_hud_mode()


func _bind_input() -> void:
	_keyboard_input_provider = KeyboardInputProvider.new()
	_keyboard_input_provider.setup_provider({"lane_count": _lane_count})
	_keyboard_input_provider.lane_pressed.connect(_on_lane_pressed)
	_keyboard_input_provider.lane_released.connect(_on_lane_released)
	add_child(_keyboard_input_provider)
	_controller_input_provider = ControllerInputProvider.new()
	_controller_input_provider.setup_provider({"lane_count": _lane_count})
	_controller_input_provider.lane_pressed.connect(_on_lane_pressed)
	_controller_input_provider.lane_released.connect(_on_lane_released)
	add_child(_controller_input_provider)
	if _editor_live_mode:
		_touch_provider.visible = false
		_touch_provider.set_process_input(false)
		return
	_touch_provider.setup_provider({"lane_count": _lane_count})
	_touch_provider.lane_pressed.connect(_on_lane_pressed)
	_touch_provider.lane_released.connect(_on_lane_released)


func _setup_drive_meter_state() -> void:
	_drive_meter_enabled = not AppState.is_multiplayer_round_active()
	_no_fail_modifier_active = _has_modifier("modifier_no_fail") or bool(_loadout.get("forced_no_fail", false))
	_drive_fail_enabled = _drive_meter_enabled and not _no_fail_modifier_active
	_drive_meter_reduce_critical_fx = ProfileStore.is_drive_meter_critical_fx_reduced()
	_drive_meter_theme = ProfileStore.get_drive_meter_theme()
	_drive_meter = _max_drive_meter
	_displayed_drive_meter = _max_drive_meter
	_drive_meter_flash_energy = 0.0


func _drive_meter_tuning() -> Dictionary:
	return DRIVE_METER_TUNING.get(_difficulty, DRIVE_METER_TUNING["Medium"]) as Dictionary


func _apply_drive_meter_judgement(judgement: String) -> void:
	if not _drive_meter_enabled:
		return
	var tuning: Dictionary = _drive_meter_tuning()
	match judgement:
		"Perfect":
			_apply_drive_meter_delta(float(tuning.get("perfect_gain", 0.0)))
		"Great":
			_apply_drive_meter_delta(float(tuning.get("great_gain", 0.0)))
		"Good":
			_apply_drive_meter_delta(float(tuning.get("good_gain", 0.0)))
		"Miss":
			_apply_drive_meter_delta(-float(tuning.get("miss_penalty", 0.0)))
			_drive_meter_flash_energy = 1.0


func _apply_drive_meter_delta(amount: float) -> void:
	if not _drive_meter_enabled:
		return
	_drive_meter = clampf(_drive_meter + amount, 0.0, _max_drive_meter)
	if _drive_fail_enabled and _drive_meter <= 0.0:
		_trigger_song_failure()


func _trigger_song_failure() -> void:
	if _is_failed or _finished or not _drive_meter_enabled:
		return
	_is_failed = true
	_drive_meter = 0.0
	_record_song_failure_stats()
	_pause_overlay.visible = false
	_is_paused = false
	_fail_overlay.visible = true
	%FailSubtitleLabel.text = "The Drive Meter is empty.\nRetry or switch to Practice Mode."
	%JudgementLabel.text = "FAILED"
	%JudgementLabel.modulate = HDTheme.MISS
	%JudgementLabel.modulate.a = 1.0
	AudioSync.fade_out_and_stop(2.0)


func _record_song_failure_stats() -> void:
	if _failure_stats_recorded:
		return
	_failure_stats_recorded = true
	if ProfileStore == null or bool(_song.get("_editor_playtest", false)):
		return
	var notes_hit := _notes_hit_count()
	var notes_missed := _notes_missed_count()
	ProfileStore.record_gameplay_result_stats({
		"song_failed": true,
		"song_id": str(_song.get("id", "")),
		"difficulty": _difficulty,
		"mode": _mode,
		"score": _score,
		"max_combo": _max_combo,
		"perfect": int(_judgements.get("Perfect", 0)),
		"great": int(_judgements.get("Great", 0)),
		"good": int(_judgements.get("Good", 0)),
		"miss": int(_judgements.get("Miss", 0)),
		"notes_hit": notes_hit,
		"notes_missed": notes_missed,
		"hold_successes": _hold_success_count,
		"hold_breaks": _hold_break_count,
		"play_time_seconds": _active_gameplay_seconds,
		"full_combo": false,
		"all_perfect": false,
		"drive_chain": false,
		"overdrive_sync": false,
	})


func _update_drive_meter_visual(delta: float, immediate: bool = false) -> void:
	_drive_meter_container.visible = _drive_meter_enabled
	_drive_meter_critical_tint.visible = _drive_meter_enabled
	_drive_meter_glow.visible = false
	if not _drive_meter_enabled:
		return
	_drive_meter_flash_energy = maxf(0.0, _drive_meter_flash_energy - delta * DRIVE_METER_FLASH_DECAY)
	if immediate:
		_displayed_drive_meter = _drive_meter
	else:
		_displayed_drive_meter = lerpf(_displayed_drive_meter, _drive_meter, clampf(delta * DRIVE_METER_LERP_SPEED, 0.0, 1.0))
	if absf(_displayed_drive_meter - _drive_meter) < 0.02:
		_displayed_drive_meter = _drive_meter
	var ratio: float = clampf(_displayed_drive_meter / maxf(1.0, _max_drive_meter), 0.0, 1.0)
	var fill_color: Color = _drive_meter_color_for_ratio(ratio)
	if _drive_meter_flash_energy > 0.0:
		fill_color = fill_color.lerp(HDTheme.MISS, clampf(_drive_meter_flash_energy * 0.72, 0.0, 0.72))
	if _drive_meter_fill_style != null:
		_drive_meter_fill_style.bg_color = fill_color
	var clip_size: Vector2 = _drive_meter_fill_clip.size
	var fill_width: float = clip_size.x * ratio
	_drive_meter_fill.position = Vector2.ZERO
	_drive_meter_fill.size = Vector2(fill_width, clip_size.y)
	var critical_ratio: float = clampf((DRIVE_METER_CRITICAL_THRESHOLD - _displayed_drive_meter) / DRIVE_METER_CRITICAL_THRESHOLD, 0.0, 1.0)
	var pulse_strength := 1.0
	if critical_ratio > 0.0 and not _drive_meter_reduce_critical_fx:
		pulse_strength = 1.0 + (sin(Time.get_ticks_msec() * 0.012) * 0.5 + 0.5) * 0.04 * critical_ratio
	_drive_meter_container.scale = Vector2.ONE * pulse_strength
	if _drive_meter_glow_style != null:
		_drive_meter_glow_style.bg_color = Color(0, 0, 0, 0)
	_drive_meter_critical_tint.color = HDTheme.MISS * Color(1.0, 1.0, 1.0, 0.035 if _drive_meter_reduce_critical_fx else 0.08)
	_drive_meter_critical_tint.modulate.a = critical_ratio * (0.22 if _drive_meter_reduce_critical_fx else 0.55)
	_drive_meter_critical_tint.visible = critical_ratio > 0.0


func _apply_drive_meter_theme() -> void:
	var palette: Dictionary = _drive_meter_palette()
	_drive_meter_frame_style = StyleBoxFlat.new()
	_drive_meter_frame_style.bg_color = Color(0, 0, 0, 0)
	_drive_meter_frame_style.border_color = palette.get("border", HDTheme.CYAN * Color(1.0, 1.0, 1.0, 0.55))
	_drive_meter_frame_style.border_width_left = 2
	_drive_meter_frame_style.border_width_top = 2
	_drive_meter_frame_style.border_width_right = 2
	_drive_meter_frame_style.border_width_bottom = 2
	_drive_meter_frame_style.corner_radius_top_left = 14
	_drive_meter_frame_style.corner_radius_top_right = 14
	_drive_meter_frame_style.corner_radius_bottom_left = 14
	_drive_meter_frame_style.corner_radius_bottom_right = 14
	_drive_meter_frame.add_theme_stylebox_override("panel", _drive_meter_frame_style)
	_drive_meter_fill_style = StyleBoxFlat.new()
	_drive_meter_fill_style.corner_radius_top_left = 10
	_drive_meter_fill_style.corner_radius_top_right = 10
	_drive_meter_fill_style.corner_radius_bottom_left = 10
	_drive_meter_fill_style.corner_radius_bottom_right = 10
	_drive_meter_fill.add_theme_stylebox_override("panel", _drive_meter_fill_style)
	_drive_meter_glow_style = StyleBoxFlat.new()
	_drive_meter_glow_style.bg_color = Color(0, 0, 0, 0)
	_drive_meter_glow_style.shadow_color = Color(0, 0, 0, 0)
	_drive_meter_glow_style.shadow_size = 0
	_drive_meter_glow_style.corner_radius_top_left = 18
	_drive_meter_glow_style.corner_radius_top_right = 18
	_drive_meter_glow_style.corner_radius_bottom_left = 18
	_drive_meter_glow_style.corner_radius_bottom_right = 18
	_drive_meter_glow.add_theme_stylebox_override("panel", _drive_meter_glow_style)
	_drive_meter_glow.visible = false
	_update_drive_meter_visual(0.0, true)


func _drive_meter_palette() -> Dictionary:
	match _drive_meter_theme:
		"classic":
			return {
				"full": Color(0.15, 0.82, 1.0, 1.0),
				"mid": Color(1.0, 0.86, 0.20, 1.0),
				"critical": Color(1.0, 0.28, 0.20, 1.0),
				"background": Color(0.03, 0.05, 0.12, 0.92),
				"border": HDTheme.CYAN * Color(1.0, 1.0, 1.0, 0.46),
			}
		"mono":
			return {
				"full": Color(0.92, 0.92, 0.98, 1.0),
				"mid": Color(0.78, 0.78, 0.82, 1.0),
				"critical": Color(1.0, 0.34, 0.26, 1.0),
				"background": Color(0.05, 0.05, 0.07, 0.94),
				"border": Color(1.0, 1.0, 1.0, 0.22),
			}
		_:
			return {
				"full": _theme_palette.get("rail", HDTheme.CYAN),
				"mid": Color(1.0, 0.86, 0.20, 1.0),
				"critical": Color(1.0, 0.28, 0.20, 1.0),
				"background": HDTheme.BG.lerp(Color.BLACK, 0.24),
				"border": _theme_palette.get("rail", HDTheme.CYAN) * Color(1.0, 1.0, 1.0, 0.40),
			}


func _drive_meter_color_for_ratio(ratio: float) -> Color:
	var palette: Dictionary = _drive_meter_palette()
	var full_color: Color = palette.get("full", HDTheme.CYAN)
	var mid_color: Color = palette.get("mid", Color(1.0, 0.86, 0.20, 1.0))
	var critical_color: Color = palette.get("critical", HDTheme.MISS)
	if ratio >= 0.5:
		return mid_color.lerp(full_color, (ratio - 0.5) / 0.5)
	if ratio >= 0.2:
		return critical_color.lerp(mid_color, (ratio - 0.2) / 0.3)
	return critical_color


func _ensure_stage_layers() -> void:
	if _background_decor == null:
		_background_decor = Control.new()
		_background_decor.name = "BackgroundDecor"
		_background_decor.anchor_right = 1.0
		_background_decor.anchor_bottom = 1.0
		_background_decor.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_background_decor)
		move_child(_background_decor, 1 if get_child_count() > 1 else 0)
		_left_gutter = ColorRect.new()
		_left_gutter.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_background_decor.add_child(_left_gutter)
		_right_gutter = ColorRect.new()
		_right_gutter.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_background_decor.add_child(_right_gutter)
		_left_gutter_image = TextureRect.new()
		_left_gutter_image.name = "LeftGutterImage"
		_left_gutter_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_left_gutter_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_background_decor.add_child(_left_gutter_image)
		_right_gutter_image = TextureRect.new()
		_right_gutter_image.name = "RightGutterImage"
		_right_gutter_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_right_gutter_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_background_decor.add_child(_right_gutter_image)
		_playfield_ems_background = ColorRect.new()
		_playfield_ems_background.name = "PlayfieldEMSBackground"
		_playfield_ems_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_playfield_ems_background.visible = false
		_background_decor.add_child(_playfield_ems_background)
		_top_glow = PanelContainer.new()
		_top_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_background_decor.add_child(_top_glow)
		_bottom_glow = PanelContainer.new()
		_bottom_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_background_decor.add_child(_bottom_glow)
		_lane_cover = ColorRect.new()
		_lane_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_lane_cover.visible = false
		_background_decor.add_child(_lane_cover)
		for _index in 8:
			var line := ColorRect.new()
			line.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_background_decor.add_child(line)
			_grid_lines.append(line)
		for _side_index in SIDE_BAR_COUNT:
			var left_bar := ColorRect.new()
			left_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_background_decor.add_child(left_bar)
			_desktop_left_bars.append(left_bar)
			var right_bar := ColorRect.new()
			right_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_background_decor.add_child(right_bar)
			_desktop_right_bars.append(right_bar)
			_left_side_energy.append(0.0)
			_right_side_energy.append(0.0)
	if _lane_flash_layer == null:
		_lane_flash_layer = Control.new()
		_lane_flash_layer.name = "LaneFlashLayer"
		_lane_flash_layer.anchor_right = 1.0
		_lane_flash_layer.anchor_bottom = 1.0
		_lane_flash_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_lane_flash_layer)
		var note_layer_index := get_children().find(_note_layer)
		move_child(_lane_flash_layer, maxi(0, note_layer_index))
		for _lane_index in _lane_count:
			var flash := ColorRect.new()
			flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
			flash.visible = false
			_lane_flash_layer.add_child(flash)
			_lane_flash_nodes.append(flash)
			_lane_flash_energy.append(0.0)
	if _max_gameplay_shader_layer == null:
		_max_gameplay_shader_layer = EMSGameplayShaderLayer.new()
		_max_gameplay_shader_layer.anchor_right = 1.0
		_max_gameplay_shader_layer.anchor_bottom = 1.0
		_max_gameplay_shader_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_max_gameplay_shader_layer)
		var fx_index := get_children().find(_fx_layer)
		if fx_index >= 0:
			move_child(_max_gameplay_shader_layer, fx_index + 1)
		if EmotionalMotionSystem != null:
			EmotionalMotionSystem.register_layer(_max_gameplay_shader_layer)
	if _ems_pressure_wave_layer == null:
		_ems_pressure_wave_layer = EMSPressureWaveLayer.new()
		_ems_pressure_wave_layer.anchor_right = 1.0
		_ems_pressure_wave_layer.anchor_bottom = 1.0
		_ems_pressure_wave_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_ems_pressure_wave_layer)
		var pressure_fx_index := get_children().find(_fx_layer)
		if pressure_fx_index >= 0:
			move_child(_ems_pressure_wave_layer, pressure_fx_index + 1)
	if _spiral_lane_layer == null:
		_spiral_lane_layer = SpiralLaneLayer.new()
		_spiral_lane_layer.name = "SpiralLaneLayer"
		_spiral_lane_layer.anchor_right = 1.0
		_spiral_lane_layer.anchor_bottom = 1.0
		_spiral_lane_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_spiral_lane_layer.visible = false
		add_child(_spiral_lane_layer)
		var spiral_note_index := get_children().find(_note_layer)
		if spiral_note_index >= 0:
			move_child(_spiral_lane_layer, spiral_note_index)
	if _black_hole_lane_layer == null:
		_black_hole_lane_layer = BlackHoleLaneLayer.new()
		_black_hole_lane_layer.name = "BlackHoleLaneLayer"
		_black_hole_lane_layer.anchor_right = 1.0
		_black_hole_lane_layer.anchor_bottom = 1.0
		_black_hole_lane_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_black_hole_lane_layer.visible = false
		add_child(_black_hole_lane_layer)
		var black_hole_note_index := get_children().find(_note_layer)
		if black_hole_note_index >= 0:
			move_child(_black_hole_lane_layer, black_hole_note_index)


func _ensure_fx_pools() -> void:
	if _particle_pool.is_empty():
		for _index in HIT_PARTICLE_POOL_SIZE:
			var dot := ColorRect.new()
			dot.visible = false
			dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_fx_layer.add_child(dot)
			_particle_pool.append(dot)
	if _actual_hit_particle_pool.is_empty():
		_hit_particle_texture = _make_hit_particle_texture()
		var fade_ramp := _make_hit_particle_color_ramp()
		for _index in ACTUAL_HIT_PARTICLE_POOL_SIZE:
			var burst := CPUParticles2D.new()
			burst.name = "ActualHitParticles"
			burst.visible = false
			burst.emitting = false
			burst.one_shot = true
			burst.amount = 24
			burst.lifetime = 0.34
			burst.explosiveness = 0.88
			burst.randomness = 0.28
			burst.lifetime_randomness = 0.22
			burst.texture = _hit_particle_texture
			burst.color_ramp = fade_ramp
			burst.direction = Vector2.UP
			burst.spread = 180.0
			burst.gravity = Vector2(0.0, 250.0)
			burst.initial_velocity_min = 92.0
			burst.initial_velocity_max = 225.0
			burst.angular_velocity_min = -120.0
			burst.angular_velocity_max = 120.0
			burst.scale_amount_min = 0.28
			burst.scale_amount_max = 0.92
			burst.local_coords = true
			_fx_layer.add_child(burst)
			_actual_hit_particle_pool.append(burst)
	if _trail_pool.is_empty():
		for _index in TRAIL_GHOST_POOL_SIZE:
			var ghost := ColorRect.new()
			ghost.visible = false
			ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_note_layer.add_child(ghost)
			_trail_pool.append(ghost)


func _build_lane_backgrounds() -> void:
	for child in _lane_backgrounds.get_children():
		child.queue_free()
	for child in _runways.get_children():
		child.queue_free()
	_lane_background_base_alphas.clear()
	for lane in _lane_count:
		var shade := ColorRect.new()
		var lane_color: Color = _lane_color(lane)
		var base_alpha := (0.045 if lane % 2 == 0 else 0.018) * _lane_brightness
		_lane_background_base_alphas.append(base_alpha)
		shade.color = lane_color * Color(1, 1, 1, base_alpha)
		shade.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_lane_backgrounds.add_child(shade)
		var runway := PanelContainer.new()
		runway.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var style := StyleBoxFlat.new()
		style.bg_color = lane_color * Color(1, 1, 1, 0.028 * _lane_brightness)
		style.corner_radius_top_left = 14
		style.corner_radius_top_right = 14
		style.corner_radius_bottom_left = 14
		style.corner_radius_bottom_right = 14
		runway.add_theme_stylebox_override("panel", style)
		_runways.add_child(runway)


func _build_receptors() -> void:
	for child in _receptors.get_children():
		child.queue_free()
	_receptor_feedback_nodes.clear()
	_receptor_press_energy.clear()
	var ems_hit_targets := _ems_hit_target_mode()
	var modern_size := _note_size()
	var btn_width: float = modern_size.x if ems_hit_targets else _lane_width() * 0.82
	var btn_height: float = modern_size.y if ems_hit_targets else _receptor_button_height()
	var button_drop := 0.0 if ems_hit_targets else btn_height * 0.05
	var vertical_pad := 0.0 if ems_hit_targets else 20.0
	for lane in _lane_count:
		var center := CenterContainer.new()
		center.custom_minimum_size = Vector2(_lane_width(), btn_height + vertical_pad + button_drop)
		center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var lane_color: Color = _lane_color(lane)
		var visual_root := Control.new()
		visual_root.name = "VisualRoot"
		visual_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		visual_root.custom_minimum_size = Vector2(_lane_width(), btn_height + vertical_pad + button_drop)
		visual_root.size = visual_root.custom_minimum_size
		center.add_child(visual_root)
		var glow := PanelContainer.new()
		glow.name = "BaseGlow"
		glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var glow_pad := 8.0 if ems_hit_targets else 10.0
		glow.custom_minimum_size = Vector2(btn_width + glow_pad, btn_height + glow_pad)
		glow.size = glow.custom_minimum_size
		glow.position = Vector2((visual_root.custom_minimum_size.x - glow.custom_minimum_size.x) * 0.5, (visual_root.custom_minimum_size.y - glow.custom_minimum_size.y) * 0.5)
		var glow_style := StyleBoxFlat.new()
		glow_style.bg_color = lane_color * Color(1, 1, 1, 0.08 if ems_hit_targets else 0.05)
		var glow_radius := int(round((btn_height + glow_pad) * 0.5)) if ems_hit_targets else 18
		glow_style.corner_radius_top_left = glow_radius
		glow_style.corner_radius_top_right = glow_radius
		glow_style.corner_radius_bottom_left = glow_radius
		glow_style.corner_radius_bottom_right = glow_radius
		glow_style.shadow_color = lane_color * Color(1, 1, 1, 0.28 if ems_hit_targets else 0.18)
		glow_style.shadow_size = 10 if ems_hit_targets else 5
		glow.add_theme_stylebox_override("panel", glow_style)
		visual_root.add_child(glow)
		var press_glow := PanelContainer.new()
		press_glow.name = "PressGlow"
		press_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var press_pad := 12.0 if ems_hit_targets else 14.0
		press_glow.custom_minimum_size = Vector2(btn_width + press_pad, btn_height + press_pad)
		press_glow.size = press_glow.custom_minimum_size
		press_glow.position = Vector2((visual_root.custom_minimum_size.x - press_glow.custom_minimum_size.x) * 0.5, (visual_root.custom_minimum_size.y - press_glow.custom_minimum_size.y) * 0.5)
		press_glow.modulate.a = 0.0
		var press_glow_style := StyleBoxFlat.new()
		press_glow_style.bg_color = lane_color * Color(1, 1, 1, 0.10)
		var press_radius := int(round((btn_height + press_pad) * 0.5)) if ems_hit_targets else 20
		press_glow_style.corner_radius_top_left = press_radius
		press_glow_style.corner_radius_top_right = press_radius
		press_glow_style.corner_radius_bottom_left = press_radius
		press_glow_style.corner_radius_bottom_right = press_radius
		press_glow_style.shadow_color = lane_color * Color(1, 1, 1, 0.55)
		press_glow_style.shadow_size = 12
		press_glow.add_theme_stylebox_override("panel", press_glow_style)
		visual_root.add_child(press_glow)
		var panel := PanelContainer.new()
		panel.name = "ReceptorPanel"
		panel.custom_minimum_size = Vector2(btn_width, btn_height)
		panel.size = panel.custom_minimum_size
		panel.position = Vector2((visual_root.custom_minimum_size.x - btn_width) * 0.5, (visual_root.custom_minimum_size.y - btn_height) * 0.5)
		var style := StyleBoxFlat.new()
		style.bg_color = lane_color.lerp(Color.BLACK, 0.62 if ems_hit_targets else 0.74) * Color(1, 1, 1, 0.92 if ems_hit_targets else 0.90)
		style.border_color = lane_color * Color(1, 1, 1, 0.86 if ems_hit_targets else 0.70)
		var border_width := 2 if ems_hit_targets else 2
		style.border_width_left = border_width
		style.border_width_top = border_width
		style.border_width_right = border_width
		style.border_width_bottom = border_width
		var panel_radius := int(round(btn_height * 0.5)) if ems_hit_targets else 15
		style.corner_radius_top_left = panel_radius
		style.corner_radius_top_right = panel_radius
		style.corner_radius_bottom_left = panel_radius
		style.corner_radius_bottom_right = panel_radius
		panel.add_theme_stylebox_override("panel", style)
		var inner := PanelContainer.new()
		inner.name = "InnerPanel"
		inner.anchor_right = 1.0
		inner.anchor_bottom = 1.0
		inner.offset_left = 10
		inner.offset_top = 9
		inner.offset_right = -10
		inner.offset_bottom = -10
		var inner_style := StyleBoxFlat.new()
		inner_style.bg_color = lane_color * Color(1, 1, 1, 0.06)
		inner_style.border_color = lane_color * Color(1, 1, 1, 0.10)
		inner_style.border_width_left = 1
		inner_style.border_width_top = 1
		inner_style.border_width_right = 1
		inner_style.border_width_bottom = 1
		inner_style.corner_radius_top_left = 11
		inner_style.corner_radius_top_right = 11
		inner_style.corner_radius_bottom_left = 11
		inner_style.corner_radius_bottom_right = 11
		inner.add_theme_stylebox_override("panel", inner_style)
		inner.visible = not ems_hit_targets
		panel.add_child(inner)
		var key_label_node: Label = null
		var top_strip := PanelContainer.new()
		top_strip.name = "TopStrip"
		top_strip.anchor_left = 0.5
		top_strip.anchor_top = 0.0
		top_strip.anchor_right = 0.5
		top_strip.anchor_bottom = 0.0
		top_strip.offset_left = -btn_width * 0.28
		top_strip.offset_top = 6
		top_strip.offset_right = btn_width * 0.28
		top_strip.offset_bottom = 11
		var top_strip_style := StyleBoxFlat.new()
		top_strip_style.bg_color = lane_color * Color(1, 1, 1, 0.14)
		top_strip_style.border_color = lane_color * Color(1, 1, 1, 0.26)
		top_strip_style.border_width_top = 1
		top_strip_style.border_width_bottom = 1
		top_strip_style.corner_radius_top_left = 6
		top_strip_style.corner_radius_top_right = 6
		top_strip_style.corner_radius_bottom_left = 6
		top_strip_style.corner_radius_bottom_right = 6
		top_strip.add_theme_stylebox_override("panel", top_strip_style)
		top_strip.visible = not ems_hit_targets
		panel.add_child(top_strip)
		var key_glyph_node: Control = null
		if _should_show_lane_key_labels():
			var binding_display := _lane_binding_display(lane)
			var key_label := Label.new()
			key_label.name = "KeyLabel"
			key_label.text = InputBindingGlyph.display_text(binding_display)
			key_label.anchor_right = 1.0
			key_label.anchor_bottom = 1.0
			key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			key_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			key_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			key_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
			HDTheme.apply_label(key_label, "section_title", lane_color.lerp(Color.WHITE, 0.08), true)
			key_label.add_theme_font_size_override("font_size", int(round(btn_height * 0.24)))
			key_label.add_theme_color_override("font_shadow_color", lane_color * Color(1, 1, 1, 0.32))
			key_label.add_theme_constant_override("shadow_offset_x", 0)
			key_label.add_theme_constant_override("shadow_offset_y", 0)
			panel.add_child(key_label)
			key_label_node = key_label
			if InputBindingGlyph.should_draw_glyph(binding_display):
				key_label.visible = false
				key_glyph_node = InputBindingGlyph.new()
				key_glyph_node.name = "KeyGlyph"
				key_glyph_node.set_display(binding_display)
				var glyph_w := minf(btn_width * 0.62, btn_height * 0.72)
				var glyph_h := btn_height * 0.34
				key_glyph_node.position = panel.position + Vector2((btn_width - glyph_w) * 0.5, (btn_height - glyph_h) * 0.5)
				key_glyph_node.custom_minimum_size = Vector2(glyph_w, glyph_h)
				key_glyph_node.size = Vector2(glyph_w, glyph_h)
		visual_root.add_child(panel)
		if key_glyph_node != null:
			visual_root.add_child(key_glyph_node)
		_receptor_feedback_nodes.append({
			"panel": panel,
			"press_glow": press_glow,
			"key_visual": key_glyph_node if key_glyph_node != null else key_label_node,
		})
		_receptor_press_energy.append(0.0)
		_receptors.add_child(center)


func _update_song_labels() -> void:
	var title := _metadata_text("title", str(_song.get("display_name", "Track")))
	var artist := _metadata_text("artist", str(_song.get("artist", "Unknown Artist")))
	var charter := _metadata_text("charter", str(_song.get("charter", "Unknown Charter")))
	var chart_difficulty := _metadata_text("difficulty", _difficulty).capitalize()
	var bpm := float(_chart.get("bpm", _song.get("bpm", 0.0)))
	var nps := float(_chart.get("nps", _calculate_chart_nps()))
	var stats_line := "%s lanes  %.1f BPM  %.2f NPS" % [_lane_count, bpm, nps]
	if AppState.is_mobile_platform():
		%TrackLabel.text = "%s\n%s\n%s" % [
			title,
			chart_difficulty,
			stats_line,
		]
	else:
		%TrackLabel.text = "%s\n%s\nCharter: %s\n%s / %s\n%s" % [
			title,
			artist,
			charter,
			GameModeConfig.get_display_name(_mode),
			chart_difficulty,
			stats_line,
		]
	%CountdownLabel.text = "3"
	%CountdownLabel.modulate.a = 1.0
	%ScoreLabel.text = "0"
	%ComboLabel.text = "0 COMBO"
	%MultiplierLabel.text = "×1"
	_update_modern_song_labels(title, artist, chart_difficulty, stats_line)
	_update_modern_hud(0.0)
	%OpponentNameLabel.text = ""
	%OpponentScoreLabel.text = ""
	%OpponentComboLabel.text = ""
	_opponent_vbox.visible = false


func _metadata_text(key: String, fallback: String) -> String:
	var value := str(_chart.get(key, fallback)).strip_edges()
	return fallback if value.is_empty() else value


func _calculate_chart_nps() -> float:
	var duration := maxf(0.0, _song_duration)
	for note in _notes:
		duration = maxf(duration, float(note.get("time", 0.0)) + float(note.get("length", note.get("duration", 0.0))))
	if duration <= 0.0:
		return 0.0
	return float(_notes.size()) / duration
	%TimeLabel.text = _formatted_song_time(0.0, _song_duration)
	%JudgementLabel.text = ""


func _show_countdown_preview() -> void:
	var preview_limit := _approach_time() * 1.1
	var preview_chart_time := _audio_start_chart_time()
	for note in _notes:
		var note_time := float(note.get("time", 0.0))
		var time_until_hit := note_time - preview_chart_time
		if time_until_hit >= -0.5 and time_until_hit <= preview_limit:
			var note_id := int(note.get("id", -1))
			_spawn_note(note, true)
			_preview_ids[note_id] = true
			_next_note_index += 1
		else:
			break
	_update_preview_positions()


func _process(delta: float) -> void:
	if _editor_live_mode:
		_process_editor_live(delta)
		return
	if _visualizer_mode:
		_process_visualizer(delta)
		return
	if _practice_mode:
		_update_practice_transport()
	if _finished or _is_paused:
		# Keep EMS calm during pauses/end states.
		if EmotionalMotionSystem != null:
			EmotionalMotionSystem.set_combo_count(0)
		return
	_update_receptor_feedback(delta)
	_update_drive_meter_visual(delta)
	var effect_song_time := _audio_start_chart_time()
	if _started:
		effect_song_time = _current_chart_time()
	_update_spiral_lanes_mode(delta)
	_update_black_hole_mode(delta)
	_update_emotional_motion_state()
	_update_emotional_note_density()
	_refresh_gutter_image_config_if_needed()
	_update_emotional_gutter_background(delta)
	_update_emotional_gutter_glow(delta)
	if _is_failed:
		_update_runtime_fx(delta, effect_song_time)
		_update_countdown_label(delta)
		return
	if not _started:
		_update_countdown(delta)
		_update_runtime_fx(delta, _audio_start_chart_time())
		return
	var song_time := effect_song_time
	_active_gameplay_seconds += delta
	_resolve_expired_chord_groups(song_time)
	_dispatch_due_chart_reactive_events(song_time)
	_spawn_upcoming_notes(song_time)
	_update_active_notes(song_time)
	_update_hold_state(song_time)
	_update_hud()
	_update_countdown_label(delta)
	_update_runtime_fx(delta, song_time)
	if _next_note_index >= _notes.size() and _spawned_nodes.is_empty() and (not AudioSync.is_playing() or _notes.is_empty()):
		_finish_song()


func _process_visualizer(delta: float) -> void:
	if _finished:
		return
	_visualizer_manual_energy = maxf(0.0, _visualizer_manual_energy - delta * 0.72)
	_update_visualizer_background(delta)
	if _visualizer_is_chart_reactive():
		_dispatch_due_visualizer_chart_hits(_current_chart_time())
	if EmotionalMotionSystem != null:
		# Chart Reactive owns a virtual Perfect streak, so its combo energy must stay
		# driven by set_combo_count(). Player Reactive continues to use manual energy.
		if not _visualizer_is_chart_reactive():
			EmotionalMotionSystem.set_combo_energy(0.42 + _visualizer_manual_energy * 0.52)
		EmotionalMotionSystem.set_note_density(0.12 + _visualizer_manual_energy * 0.34)


func _update_visualizer_background(delta: float) -> void:
	if not _visualizer_mode:
		return
	var target: Color = _theme_palette.get("background", Color(0.02, 0.03, 0.08, 1.0))
	if EmotionalMotionSystem != null and EmotionalMotionSystem.enabled:
		target = EmotionalMotionSystem.get_gutter_background_color()
	target.a = 1.0
	if delta <= 0.0:
		%Background.color = target
	else:
		var follow := 1.0 - exp(-delta * 2.2)
		%Background.color = %Background.color.lerp(target, follow)
		%Background.color.a = 1.0
	# The two EMS render halves use transparent sub-viewports. This opaque EMS-
	# resolved backing prevents the viewport clear color from showing through.
	%Background.visible = true


func _dispatch_due_visualizer_chart_hits(song_time: float) -> void:
	if not _visualizer_is_chart_reactive() or EmotionalMotionSystem == null:
		return
	while _next_chart_reactive_index < _notes.size():
		var note: Dictionary = _notes[_next_chart_reactive_index]
		var note_time := float(note.get("time", 0.0))
		if note_time > song_time:
			break
		var lane := _lane_for_note(note)
		var y_norm := _hit_line_y() / maxf(1.0, _display_size().y)
		_visualizer_manual_energy = 1.0
		_combo += 1
		_max_combo = maxi(_max_combo, _combo)
		_judgements["Perfect"] = int(_judgements.get("Perfect", 0)) + 1
		_scored_note_count += 1
		_weighted_accuracy += 1.0
		EmotionalMotionSystem.set_combo_count(_combo)
		EmotionalMotionSystem.notify_judgement(lane, "Perfect", 1.0, note_time, y_norm)
		var payload := {
			"note_id": int(note.get("id", _next_chart_reactive_index)),
			"lane": lane,
			"note_time": note_time,
			"duration": float(note.get("duration", note.get("length", 0.0))),
			"judgement": "Perfect",
			"strength": 1.0,
			"value": 1.0,
			"mode": "visualizer_chart_reactive",
		}
		EmotionalMotionSystem.dispatch_ems_event("chart_reactive", payload)
		EmotionalMotionSystem.dispatch_ems_event("audio_reactive", payload)
		_next_chart_reactive_index += 1


func _process_editor_live(delta: float) -> void:
	if _is_paused:
		if EmotionalMotionSystem != null:
			EmotionalMotionSystem.set_combo_count(0)
		return
	_update_receptor_feedback(delta)
	var song_time := _current_chart_time()
	_update_spiral_lanes_mode(delta)
	_update_black_hole_mode(delta)
	_update_emotional_motion_state()
	_update_emotional_note_density()
	_refresh_gutter_image_config_if_needed()
	_update_emotional_gutter_background(delta)
	_update_emotional_gutter_glow(delta)
	if not _editor_live_adding_enabled:
		_active_gameplay_seconds += delta
		_resolve_expired_chord_groups(song_time)
	_dispatch_due_chart_reactive_events(song_time)
	_spawn_upcoming_notes(song_time)
	_update_active_notes(song_time)
	if not _editor_live_adding_enabled:
		_update_hold_state(song_time)
	_update_hud()
	_update_runtime_fx(delta, song_time)


func _update_emotional_motion_state() -> void:
	if EmotionalMotionSystem == null:
		return

	# Phase 4: EMS owns combo -> combo_energy normalization/smoothing.
	if not _started or _is_failed:
		EmotionalMotionSystem.set_combo_count(0)
		return

	EmotionalMotionSystem.set_combo_count(_combo)


func _update_spiral_lanes_mode(delta: float) -> void:
	if _spiral_lane_layer == null:
		return
	var active := _is_spiral_theme()
	_spiral_lane_layer.visible = active
	if not active:
		return
	var density := clampf(float(_spawned_nodes.size()) / maxf(10.0, float(_lane_count) * 8.0), 0.0, 1.0)
	_spiral_lanes_phase = wrapf(_spiral_lanes_phase + delta * (0.22 + density * 0.46), -TAU, TAU)
	_spiral_lane_layer.set_phase(_spiral_lanes_phase)


func _update_black_hole_mode(delta: float) -> void:
	if _black_hole_lane_layer == null:
		return
	var active := _is_black_hole_mode()
	_black_hole_lane_layer.visible = active
	if not active:
		return
	var density := clampf(float(_spawned_nodes.size()) / maxf(10.0, float(_lane_count) * 8.0), 0.0, 1.0)
	_black_hole_phase = wrapf(_black_hole_phase + delta * (0.36 + density * 0.42), -TAU, TAU)
	_black_hole_lane_layer.set_phase(_black_hole_phase)


func _is_black_hole_mode() -> bool:
	return _has_modifier("modifier_black_hole")


func _ems_hit_target_mode() -> bool:
	if ProfileStore == null or not ProfileStore.has_method("get_judgement_display_mode"):
		return true
	return ProfileStore.get_judgement_display_mode() == "modern"


func _is_spiral_theme() -> bool:
	return str(_loadout.get("theme", "")) == "theme_spiral"


func _spiral_target_speed() -> float:
	var base_speed: float = float(SPIRAL_BASE_SPEEDS.get(_difficulty, SPIRAL_BASE_SPEEDS["Medium"]))
	var active_note_density := clampf(float(_spawned_nodes.size()) / maxf(10.0, float(_lane_count) * 8.0), 0.0, 1.0)
	var chart_nps := clampf(_calculate_chart_nps() / 8.0, 0.0, 1.0)
	var intensity := clampf(active_note_density * 0.72 + chart_nps * 0.28, 0.0, 1.0)
	return base_speed + SPIRAL_DENSITY_SPEED_BOOST * intensity


func _apply_spiral_playfield_transform(angle: float) -> void:
	_set_spiral_node_transform(_lane_backgrounds, angle)
	_set_spiral_node_transform(_runway_inset, angle)
	_set_spiral_node_transform(_lane_flash_layer, angle)
	_set_spiral_node_transform(_note_layer, angle)
	_set_spiral_node_transform(_receptors_margin, angle)
	_apply_spiral_lane_background_colors()


func _apply_spiral_lane_background_colors() -> void:
	return


func _spiral_ems_background_color() -> Color:
	if EmotionalMotionSystem != null and EmotionalMotionSystem.enabled and _theme_effects_enabled:
		return EmotionalMotionSystem.get_gutter_background_color()
	return _theme_palette.get("background", HDTheme.BG)


func _transparent_ems_canvas_color() -> Color:
	var color := _spiral_ems_background_color()
	color = color.darkened(0.55)
	color.a = 0.0
	return color


func _set_spiral_node_transform(node: Control, angle: float) -> void:
	if node == null or not is_instance_valid(node):
		return
	var viewport_center := _display_size() * 0.5
	node.pivot_offset = viewport_center - node.position
	node.rotation = angle


func _update_emotional_note_density() -> void:
	# Lightweight proxy: number of active spawned notes (and holds) on screen.
	# Used only to automatically reduce distortion during dense sections.
	if EmotionalMotionSystem == null:
		return
	if not _started or _is_failed:
		EmotionalMotionSystem.set_note_density(0.0)
		return
	var active := float(_spawned_nodes.size())
	# Tune for typical charts: 0..~80 active notes (including holds) maps to 0..1.
	var density := clampf(active / 80.0, 0.0, 1.0)
	EmotionalMotionSystem.set_note_density(density)


func _update_emotional_gutter_glow(delta: float) -> void:
	# Subtle "flow state" amplification for the LEFT/RIGHT gutters only.
	# This ensures EMS ambience never competes with note readability in the lanes.
	var target := 0.0
	if EmotionalMotionSystem != null and EmotionalMotionSystem.enabled and _theme_effects_enabled and not _prioritize_fps:
		target = clampf(float(EmotionalMotionSystem.combo_energy), 0.0, 1.0)
	_ems_gutter_glow_energy = lerpf(_ems_gutter_glow_energy, target, clampf(delta * 2.0, 0.0, 1.0))
	var glow_boost := 1.0 + _ems_gutter_glow_energy * 0.06
	if _left_gutter != null:
		_left_gutter.modulate = Color(glow_boost, glow_boost, glow_boost, 1.0)
	if _right_gutter != null:
		_right_gutter.modulate = Color(glow_boost, glow_boost, glow_boost, 1.0)
	# Optional: slight lane background emphasis without adding any new motion on top of notes.
	# This keeps readability high while still providing a "flow state" feeling in the lanes.
	for i in _lane_backgrounds.get_child_count():
		var shade := _lane_backgrounds.get_child(i)
		if shade is ColorRect:
			var lane := i
			var base_alpha := 0.020
			if lane >= 0 and lane < _lane_background_base_alphas.size():
				base_alpha = float(_lane_background_base_alphas[lane])
			var c := (shade as ColorRect).color
			c.a = clampf(base_alpha * (1.0 + _ems_gutter_glow_energy * 0.18), 0.0, 0.085)
			(shade as ColorRect).color = c


func _update_emotional_gutter_background(delta: float) -> void:
	# EMS background is a gutter-only color layer to help atmosphere read (never affects lanes).
	if _left_gutter == null or _right_gutter == null:
		return
	if EmotionalMotionSystem == null or not EmotionalMotionSystem.enabled or not _theme_effects_enabled:
		return

	# Smooth follow so rapid palette transitions remain premium.
	var target: Color = EmotionalMotionSystem.get_gutter_background_color()
	var t := 1.0 - exp(-delta * 2.2)
	_left_gutter.color = _left_gutter.color.lerp(target, t)
	_right_gutter.color = _right_gutter.color.lerp(target, t)
	if _playfield_ems_background != null and _chart_background_disabled:
		_playfield_ems_background.color = _playfield_ems_background.color.lerp(_transparent_ems_canvas_color(), t)


func _refresh_gutter_image_config_if_needed() -> void:
	if ProfileStore == null:
		return
	var rev := ProfileStore.get_profile_revision()
	if rev == _last_profile_revision:
		return
	_last_profile_revision = rev
	_apply_gutter_images_from_profile()
	_refresh_maximum_effects_config()


func _apply_gutter_images_from_profile() -> void:
	if _left_gutter_image == null or _right_gutter_image == null:
		return
	if ProfileStore == null:
		return
	var mode := ProfileStore.get_ems_gutter_image_mode()
	var alpha := clampf(ProfileStore.get_ems_gutter_image_alpha(), 0.0, 1.0)
	_gutter_image_mode = mode
	var left_path := ""
	var right_path := ""
	match mode:
		"both":
			var p := ProfileStore.get_ems_gutter_image_path_both()
			left_path = p
			right_path = ""
		"separate":
			left_path = ProfileStore.get_ems_gutter_image_path_left()
			right_path = ProfileStore.get_ems_gutter_image_path_right()
		_:
			left_path = ""
			right_path = ""

	_left_gutter_image.texture = _load_user_texture(left_path)
	_right_gutter_image.texture = _load_user_texture(right_path)
	if _left_gutter_image.texture == null and not left_path.is_empty():
		print("[GameScene] EMS gutter image failed to load (left) path=%s" % left_path)
	if _right_gutter_image.texture == null and not right_path.is_empty():
		print("[GameScene] EMS gutter image failed to load (right) path=%s" % right_path)
	_left_gutter_image.modulate = Color(1, 1, 1, alpha)
	_right_gutter_image.modulate = Color(1, 1, 1, alpha)
	_left_gutter_image.visible = _left_gutter_image.texture != null and alpha > 0.001
	_right_gutter_image.visible = mode == "separate" and _right_gutter_image.texture != null and alpha > 0.001
	_layout_playfield()


func _refresh_maximum_effects_config() -> void:
	if _max_gameplay_shader_layer == null:
		return
	if ProfileStore != null:
		_theme_effects_enabled = ProfileStore.are_theme_effects_enabled()
		_chart_background_disabled = ProfileStore.is_chart_background_disabled()
		_prioritize_fps = ProfileStore.is_prioritize_fps_enabled()
		_notes_above_judgement_buttons = ProfileStore.are_notes_above_judgement_buttons()
		_hit_effects_mode = ProfileStore.get_hit_effects_mode()
	if _visualizer_mode:
		_chart_background_disabled = true
	var shader_active := _maximum_gameplay_shaders_active()
	_max_gameplay_shader_layer.configure_effects(shader_active, _maximum_bloom_active(), _maximum_distortion_active())


func _is_ems_maximum_level() -> bool:
	return ProfileStore != null and ProfileStore.get_ems_trippy_level() == "max"


func _maximum_ems_effects_active() -> bool:
	return _theme_effects_enabled and _is_ems_maximum_level() and EmotionalMotionSystem != null and EmotionalMotionSystem.enabled


func _maximum_gameplay_shaders_active() -> bool:
	if _visualizer_mode:
		return false
	if _prioritize_fps:
		return false
	if not _maximum_ems_effects_active():
		return false
	if ProfileStore == null:
		return true
	return ProfileStore.are_shaders_enabled()


func _maximum_bloom_active() -> bool:
	return _maximum_gameplay_shaders_active() and (ProfileStore == null or ProfileStore.is_visual_effect_bloom_enabled())


func _maximum_distortion_active() -> bool:
	return _maximum_gameplay_shaders_active() and (ProfileStore == null or ProfileStore.is_visual_effect_distortion_enabled())


func _maximum_note_shader_intensity() -> float:
	if not _maximum_gameplay_shaders_active() or EmotionalMotionSystem == null:
		return 0.0
	var combo := clampf(float(EmotionalMotionSystem.combo_energy), 0.0, 1.0)
	var intensity := clampf(float(EmotionalMotionSystem.intensity), 0.0, 1.0)
	var density := clampf(float(EmotionalMotionSystem.note_density), 0.0, 1.0)
	var density_reduction := lerpf(1.0, 0.72, density)
	var layer_weight := EmotionalMotionSystem.get_loadout_layer_weight("gameplay_shader", 1.0)
	return clampf((0.24 + combo * 0.42 + intensity * 0.28) * density_reduction * layer_weight, 0.0, 1.0)


func _apply_maximum_note_shader_config(visual: HDNoteVisual, song_time: float) -> void:
	if visual == null or not is_instance_valid(visual):
		return
	var shader_active := _maximum_gameplay_shaders_active()
	visual.set_ems_maximum_shader(shader_active, _maximum_bloom_active(), _maximum_distortion_active())
	if shader_active:
		visual.update_ems_maximum_shader(_maximum_note_shader_intensity(), song_time)


func _hit_particles_profile_enabled() -> bool:
	return ProfileStore == null or ProfileStore.is_visual_effect_particles_enabled()


func _maximum_actual_hit_particles_active() -> bool:
	return _maximum_ems_effects_active() and _hit_particles_profile_enabled() and not _prioritize_fps


func _maximum_pressure_waves_active() -> bool:
	if _visualizer_mode:
		return false
	if not _maximum_ems_effects_active() or _prioritize_fps:
		return false
	if EmotionalMotionSystem != null:
		if EmotionalMotionSystem.get_loadout_layer_weight("pressure_wave", 1.0) <= 0.01:
			return false
		return EmotionalMotionSystem.get_effective_hit_effect() == "circular"
	if ProfileStore != null and ProfileStore.get_ems_hit_effect() != "circular":
		return false
	return true


func _spawn_ems_pressure_wave(lane: int, judgement: String, strength: float, origin: Vector2) -> void:
	if judgement == "Miss":
		return
	if _ems_pressure_wave_layer == null or not is_instance_valid(_ems_pressure_wave_layer):
		return
	if not _maximum_pressure_waves_active():
		return
	strength *= EmotionalMotionSystem.get_loadout_layer_weight("pressure_wave", 1.0) if EmotionalMotionSystem != null else 1.0
	var lane_color := _lane_color(lane)
	_ems_pressure_wave_layer.spawn_wave(lane, strength, origin - _ems_pressure_wave_layer.global_position, lane_color)


func _load_user_texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if _gutter_image_tex_cache.has(path):
		var cached: Variant = _gutter_image_tex_cache.get(path)
		return cached as Texture2D if cached is Texture2D else null

	# res:// resources can be loaded directly.
	if path.begins_with("res://"):
		var tex: Resource = load(path)
		if tex is Texture2D:
			_gutter_image_tex_cache[path] = tex
			return tex
		_gutter_image_tex_cache[path] = null
		return null

	# user:// paths can be loaded directly as resources in most cases.
	if path.begins_with("user://"):
		var user_tex: Resource = load(path)
		if user_tex is Texture2D:
			_gutter_image_tex_cache[path] = user_tex
			return user_tex

	# Absolute filesystem paths: load via Image.
	# Godot 4: Image.load_from_file(path) returns an Image; Image.load(path) returns Error.
	var img: Image = Image.load_from_file(path)
	if img == null or img.get_width() <= 0 or img.get_height() <= 0:
		_gutter_image_tex_cache[path] = null
		return null
	var itex := ImageTexture.create_from_image(img)
	_gutter_image_tex_cache[path] = itex
	return itex


func _update_countdown(delta: float) -> void:
	_countdown_time -= delta
	var countdown_int := maxi(1, ceili(_countdown_time))
	%CountdownLabel.text = str(countdown_int)
	if _countdown_time <= 0.0:
		_begin_song()


func _begin_song() -> void:
	_started = true
	if EmotionalMotionSystem != null:
		# Random palette per run (as configured).
		EmotionalMotionSystem.reseed_run_palette()
		EmotionalMotionSystem.dispatch_ems_event("song_started", {
			"song_id": str(_song.get("id", _song.get("song_id", ""))),
			"difficulty": _difficulty,
			"mode": _mode,
			"bpm": float(_chart.get("bpm", _song.get("bpm", 120.0))),
			"strength": 1.0,
		})
		var section_meta: Dictionary = ProgressionManager.get_section_for_song(str(_song.get("id", _song.get("song_id", "")))) if ProgressionManager != null else {}
		if not section_meta.is_empty():
			EmotionalMotionSystem.dispatch_ems_event("song_section_changed", {
				"section_id": int(section_meta.get("section_id", 0)),
				"section_name": str(section_meta.get("section_name", section_meta.get("name", ""))),
				"strength": 0.85,
			})
	%CountdownLabel.text = "GO!"
	%CountdownLabel.modulate.a = 1.0
	_go_display_time = 0.45
	for note_id in _preview_ids.keys():
		if _spawned_nodes.has(note_id):
			var visual: HDNoteVisual = (_spawned_nodes[note_id] as Dictionary)["node"]
			visual.modulate.a = _note_opacity
	_preview_ids.clear()
	if AudioSync.load_stream(str(_song.get("audio_path", ""))):
		AudioSync.play_from_start()
		if bool(_song.get("_editor_playtest", false)) and not _editor_live_mode:
			var editor_playtest_start := maxf(0.0, float(_song.get("_editor_playtest_start_time", 0.0)))
			if editor_playtest_start > 0.0:
				AudioSync.seek(editor_playtest_start)
				_rebuild_editor_playtest_notes(editor_playtest_start)
	else:
		%JudgementLabel.text = "Missing audio"
		%JudgementLabel.modulate = HDTheme.MISS


func _update_countdown_label(delta: float) -> void:
	if _go_display_time <= 0.0:
		return
	_go_display_time = maxf(0.0, _go_display_time - delta)
	if _go_display_time == 0.0:
		%CountdownLabel.text = ""
		%CountdownLabel.modulate.a = 0.0


func _spawn_upcoming_notes(song_time: float) -> void:
	while _next_note_index < _notes.size():
		var note: Dictionary = _notes[_next_note_index]
		if float(note.get("time", 0.0)) > song_time + _approach_time():
			break
		_spawn_note(note)
		_next_note_index += 1


func _spawn_note(note: Dictionary, preview: bool = false) -> void:
	var note_id := int(note.get("id", _spawned_nodes.size()))
	if _spawned_nodes.has(note_id):
		return
	var lane := _lane_for_note(note)
	var visual := HDNoteVisual.new()
	visual.setup(lane, _note_size(), float(note.get("duration", 0.0)), _theme_palette.get("lane_colors", HDTheme.LANE_COLORS), _prioritize_fps)
	if _editor_live_mode:
		visual.mouse_filter = Control.MOUSE_FILTER_STOP if _editor_note_removal_enabled else Control.MOUSE_FILTER_IGNORE
		visual.tooltip_text = "Click to remove this note while Remove Notes is enabled."
		visual.gui_input.connect(_on_editor_note_gui_input.bind(note_id))
	if _has_effect("effect_glow_boost") and not _prioritize_fps:
		visual.set_glow_multiplier(1.45)
	_apply_maximum_note_shader_config(visual, _audio_start_chart_time())
	visual.modulate.a = (0.55 if preview else 1.0) * _note_opacity
	_note_layer.add_child(visual)
	if preview:
		var note_time := float(note.get("time", 0.0))
		var preview_y := _y_position_for_time_until_hit(note_time - _audio_start_chart_time())
		_place_note_visual_on_lane(visual, lane, preview_y)
	_spawned_nodes[note_id] = {"node": visual, "note": note, "trail_time": 0.0}


func _update_preview_positions() -> void:
	for note_id in _preview_ids.keys():
		if not _spawned_nodes.has(note_id):
			continue
		var payload: Dictionary = _spawned_nodes[note_id]
		var note: Dictionary = payload["note"]
		var visual: HDNoteVisual = payload["node"]
		var lane := _lane_for_note(note)
		var note_time := float(note.get("time", 0.0))
		var preview_y := _y_position_for_time_until_hit(note_time - _audio_start_chart_time())
		_place_note_visual_on_lane(visual, lane, preview_y)


func _update_active_notes(song_time: float) -> void:
	var to_remove: Array[int] = []
	var editor_authoring := _editor_live_mode and _editor_live_adding_enabled
	var approach_time := _approach_time()
	var flashlight_enabled := _has_modifier("modifier_flashlight")
	var hidden_enabled := _has_modifier("modifier_hidden_notes")
	var ghost_holds_enabled := false
	var pulse_enabled := _has_effect("effect_pulse") and not _prioritize_fps
	var trail_enabled := _has_effect("effect_trail") and not _prioritize_fps
	var visibility_top := -_note_height() * 1.6
	var visibility_bottom := _display_size().y + _note_height() * 2.2
	for note_id in _spawned_nodes.keys():
		var payload: Dictionary = _spawned_nodes[note_id]
		var note: Dictionary = payload["note"]
		var visual: HDNoteVisual = payload["node"]
		var note_time := float(note.get("time", 0.0))
		var duration := float(note.get("duration", 0.0))
		var lane := _lane_for_note(note)
		var time_until_hit := note_time - song_time
		var head_y := _y_position_for_time_until_hit(time_until_hit)
		var note_end_time := note_time + duration
		var is_active_hold := editor_authoring and duration > 0.0 and song_time >= note_time and song_time <= note_end_time
		if not is_active_hold and duration > 0.0 and _hold_state.has(lane):
			var hold_payload: Dictionary = _hold_state[lane]
			var hold_note: Dictionary = hold_payload.get("note", {})
			if int(hold_note.get("id", -1)) == note_id:
				is_active_hold = true
		if is_active_hold:
			# While holding correctly, pin the head to the judgement line and let the sustain shrink.
			head_y = _hit_line_y()
			if editor_authoring:
				visual.start_hold()
		_place_note_visual_on_lane(visual, lane, head_y)
		if _prioritize_fps:
			visual.visible = head_y >= visibility_top and head_y <= visibility_bottom
		else:
			visual.visible = true
		var progress := 1.0 - (time_until_hit / approach_time)
		var note_alpha := 1.0
		if hidden_enabled:
			note_alpha = minf(note_alpha, clampf((progress - 0.55) / 0.30, 0.0, 1.0))
		if flashlight_enabled:
			var distance_ratio := absf(head_y - _hit_line_y()) / maxf(1.0, _hit_line_y() - _spawn_y())
			note_alpha = minf(note_alpha, clampf(1.15 - distance_ratio * 1.45, 0.12, 1.0))
		visual.modulate.a = note_alpha * _note_opacity
		if pulse_enabled:
			var pulse := 1.0 + sin(song_time * PI * 2.0) * 0.04
			visual.scale = Vector2.ONE * pulse
		else:
			visual.scale = Vector2.ONE
		_apply_maximum_note_shader_config(visual, song_time)
		var trail_progress := 1.0 - (time_until_hit / approach_time)
		if trail_enabled and song_time - float(payload.get("trail_time", 0.0)) > 0.05 and trail_progress > 0.2 and trail_progress < 1.05:
			_spawn_trail_afterimage(visual, lane)
			payload["trail_time"] = song_time
			_spawned_nodes[note_id] = payload
		if duration > 0.0:
			var sustain_seconds := duration
			if is_active_hold:
				var end_time := note_end_time
				if _hold_state.has(lane):
					var runtime_hold_payload: Dictionary = _hold_state[lane]
					end_time = float(runtime_hold_payload.get("end_time", note_end_time))
				sustain_seconds = maxf(0.0, end_time - song_time)
			var sustain_height := maxf(16.0, (sustain_seconds / approach_time) * (_hit_line_y() - _spawn_y()))
			sustain_height = minf(sustain_height, _display_size().y + _note_height() * 3.0)
			visual.update_sustain(sustain_height)
			if ghost_holds_enabled and not _prioritize_fps:
				visual.set_hold_visibility(clampf(progress, 0.18, 1.0) * 0.35)
			else:
				visual.set_hold_visibility(1.0)
		if editor_authoring:
			if song_time - note_end_time > approach_time * 0.55:
				to_remove.append(note_id)
			continue
		if _judged_note_ids.has(note_id):
			continue
		var miss_window := JudgementRules.max_window(_difficulty, _judgement_window_modifier_scale()) * AUTO_MISS_WINDOW_MULTIPLIER
		if song_time - note_time > miss_window:
			_register_judgement("Miss", lane, visual.global_position + visual.size * 0.5, note_id, 0.0, true)
			_judged_note_ids[note_id] = true
			to_remove.append(note_id)
	for note_id in to_remove:
		if editor_authoring:
			_discard_spawned_note(note_id)
		else:
			_remove_note(note_id, true)


func _dispatch_due_chart_reactive_events(song_time: float) -> void:
	if EmotionalMotionSystem == null:
		return
	while _next_chart_reactive_index < _notes.size():
		var note: Dictionary = _notes[_next_chart_reactive_index]
		var note_time := float(note.get("time", 0.0))
		if note_time > song_time:
			break
		var payload := {
			"note_id": int(note.get("id", _next_chart_reactive_index)),
			"lane": _lane_for_note(note),
			"note_time": note_time,
			"duration": float(note.get("duration", note.get("length", 0.0))),
			"strength": 1.0,
			"value": 1.0,
		}
		EmotionalMotionSystem.dispatch_ems_event("chart_reactive", payload)
		EmotionalMotionSystem.dispatch_ems_event("audio_reactive", payload)
		_next_chart_reactive_index += 1


func _update_hold_state(song_time: float) -> void:
	var released: Array[int] = []
	for lane in _hold_state.keys():
		var hold: Dictionary = _hold_state[lane]
		var last_tick_time: float = float(hold.get("last_tick_time", song_time))
		var elapsed: float = song_time - last_tick_time
		if elapsed >= HOLD_TICK_INTERVAL:
			var ticks: int = int(floor(elapsed / HOLD_TICK_INTERVAL))
			for _index in ticks:
				_register_hold_tick()
			hold["last_tick_time"] = last_tick_time + float(ticks) * HOLD_TICK_INTERVAL
			_hold_state[lane] = hold
		if song_time >= float(hold.get("end_time", 0.0)) - 0.02:
			released.append(lane)
	for lane in released:
		var hold: Dictionary = _hold_state[lane]
		var note_dict: Dictionary = hold.get("note", {})
		var note_id := int(note_dict.get("id", -1))
		if _spawned_nodes.has(note_id):
			var visual: HDNoteVisual = (_spawned_nodes[note_id] as Dictionary)["node"]
			_register_hold_success(_lane_for_note(note_dict), visual.global_position + visual.size * 0.5)
		_remove_note(note_id)
		_hold_state.erase(lane)


func _on_lane_pressed(lane: int) -> void:
	if not _started or _finished or _is_paused or _is_failed:
		return
	_active_input_lanes[lane] = true
	if _visualizer_mode:
		_trigger_visualizer_lane(lane)
		return
	_flash_receptor(lane)
	if _editor_live_mode and _editor_live_adding_enabled:
		editor_live_lane_event.emit(_current_chart_time(), lane, true)
		return
	_pending_lane_presses[lane] = true
	if not _lane_press_flush_queued:
		_lane_press_flush_queued = true
		call_deferred("_flush_pending_lane_presses")


func _trigger_visualizer_lane(lane: int) -> void:
	if EmotionalMotionSystem == null or _visualizer_is_chart_reactive():
		return
	var safe_lane := clampi(lane, 0, VISUALIZER_LANE_COUNT - 1)
	var y_norm := lerpf(0.18, 0.82, float(safe_lane) / float(VISUALIZER_LANE_COUNT - 1))
	var song_time := AudioSync.get_song_time_raw()
	_visualizer_manual_energy = 1.0
	EmotionalMotionSystem.notify_judgement(safe_lane, "Perfect", 1.0, song_time, y_norm)
	EmotionalMotionSystem.dispatch_ems_event("visualizer_lane", {
		"lane": safe_lane,
		"song_time": song_time,
		"y_norm": y_norm,
		"strength": 1.0,
		"value": 1.0,
	})


func _flush_pending_lane_presses() -> void:
	_lane_press_flush_queued = false
	if _pending_lane_presses.is_empty():
		return
	var lanes: Array[int] = []
	for lane_variant in _pending_lane_presses.keys():
		lanes.append(int(lane_variant))
	lanes.sort()
	_pending_lane_presses.clear()
	if not _started or _finished or _is_paused or _is_failed:
		return
	var song_time := _current_chart_time()
	var strict := _closest_hittable_group(song_time)
	if not strict.is_empty():
		var allowed_lanes := _currently_hittable_lanes(song_time)
		# Only presses from this input batch participate in anti-mash validation.
		# Lanes held from an earlier note must not block a fresh press in another lane.
		var invalid_lane := -1
		for lane in lanes:
			if not allowed_lanes.has(lane):
				invalid_lane = lane
				break
		if invalid_lane != -1:
			_fail_hittable_group(strict, song_time, invalid_lane)
			return
	for lane in lanes:
		_judge_lane_press(lane, song_time)


func _judge_lane_press(lane: int, song_time: float) -> void:
	var best_note: Dictionary = {}
	var best_visual: HDNoteVisual
	var best_note_id := -1
	var best_delta := 999.0
	var best_judgement := ""
	for note_id in _spawned_nodes.keys():
		if _judged_note_ids.has(note_id):
			continue
		var payload: Dictionary = _spawned_nodes[note_id]
		var note: Dictionary = payload["note"]
		if _lane_for_note(note) != lane:
			continue
		var delta := song_time - float(note.get("time", 0.0))
		var candidate_judgement := JudgementRules.judge_delta(delta, _difficulty, _judgement_window_modifier_scale())
		if candidate_judgement == "Miss":
			continue
		if absf(delta) < absf(best_delta):
			best_delta = delta
			best_note = note
			best_visual = payload["node"]
			best_note_id = int(note_id)
			best_judgement = candidate_judgement
	if best_note_id == -1:
		return
	var judgement := best_judgement
	_register_judgement(judgement, lane, best_visual.global_position + best_visual.size * 0.5, best_note_id, best_delta)
	_judged_note_ids[best_note_id] = true
	_track_chord_resolution(best_note, best_note_id, song_time)
	var duration := float(best_note.get("duration", 0.0))
	if duration > 0.0:
		best_visual.start_hold()
		_hold_state[lane] = {
			"note": best_note,
			"end_time": float(best_note.get("time", 0.0)) + duration,
			"last_tick_time": song_time,
		}
	else:
		_remove_note(best_note_id)


func _closest_hittable_group(song_time: float) -> Dictionary:
	# Find the closest unjudged note within the judgement window, then return the full time-key group.
	var max_window := JudgementRules.max_window(_difficulty, _judgement_window_modifier_scale())
	var best_note_id := -1
	var best_abs_delta := INF
	var best_time_key := -1
	var best_note_time := 0.0
	for note_id_variant in _spawned_nodes.keys():
		var note_id := int(note_id_variant)
		if _judged_note_ids.has(note_id):
			continue
		var payload: Dictionary = _spawned_nodes[note_id]
		var note: Dictionary = payload["note"]
		var delta := song_time - float(note.get("time", 0.0))
		var abs_delta := absf(delta)
		if abs_delta > max_window:
			continue
		if abs_delta < best_abs_delta:
			best_abs_delta = abs_delta
			best_note_id = note_id
			best_note_time = float(note.get("time", 0.0))
			best_time_key = _note_time_key(best_note_time)
	if best_note_id == -1:
		return {}
	# Chords may be authored with tiny floating differences; treat notes within a small epsilon as a group.
	var note_ids: Array[int] = []
	var chord_epsilon := 0.002
	for spawned_note_id in _spawned_nodes.keys():
		var note_id := int(spawned_note_id)
		if _judged_note_ids.has(note_id):
			continue
		var payload: Dictionary = _spawned_nodes[note_id]
		var note: Dictionary = payload["note"]
		if absf(float(note.get("time", 0.0)) - best_note_time) <= chord_epsilon:
			note_ids.append(note_id)
	# If we're mid-chord-resolution, prefer the group's expected lanes, since already-hit notes
	# may have been removed from _spawned_nodes by now.
	var expected_lanes: Dictionary = {}
	if _pending_chord_groups.has(best_time_key):
		var group: Dictionary = _pending_chord_groups[best_time_key]
		expected_lanes = (group.get("expected_lanes", {}) as Dictionary).duplicate(true)
	if expected_lanes.is_empty():
		for id in note_ids:
			if not _spawned_nodes.has(id):
				continue
			var payload: Dictionary = _spawned_nodes[id]
			var note: Dictionary = payload["note"]
			expected_lanes[_lane_for_note(note)] = true
	if note_ids.is_empty() and expected_lanes.is_empty():
		return {}
	return {"time_key": best_time_key, "note_ids": note_ids, "expected_lanes": expected_lanes}


func _currently_hittable_lanes(song_time: float) -> Dictionary:
	var lanes: Dictionary = {}
	for group_variant in _pending_chord_groups.values():
		var group: Dictionary = group_variant
		var expected: Dictionary = group.get("expected_lanes", {}) as Dictionary
		for lane_variant in expected.keys():
			lanes[int(lane_variant)] = true
	for note_id_variant in _spawned_nodes.keys():
		var note_id := int(note_id_variant)
		if _judged_note_ids.has(note_id):
			continue
		var payload: Dictionary = _spawned_nodes[note_id]
		var note: Dictionary = payload["note"]
		var delta := song_time - float(note.get("time", 0.0))
		if JudgementRules.judge_delta(delta, _difficulty, _judgement_window_modifier_scale()) == "Miss":
			continue
		lanes[_lane_for_note(note)] = true
	return lanes


func _fail_hittable_group(group: Dictionary, song_time: float, pressed_lane: int) -> void:
	# Debounce so chord-mash doesn't apply multiple misses for the same note time key.
	var time_key := int(group.get("time_key", -1))
	if time_key == _last_failed_time_key and song_time < _last_failed_time_key_deadline:
		return
	_last_failed_time_key = time_key
	_last_failed_time_key_deadline = song_time + CHORD_COMPLETION_GRACE

	var note_ids: Array[int] = group.get("note_ids", [])
	for note_id in note_ids:
		if _judged_note_ids.has(note_id):
			continue
		if not _spawned_nodes.has(note_id):
			continue
		var payload: Dictionary = _spawned_nodes[note_id]
		var note: Dictionary = payload["note"]
		var visual: HDNoteVisual = payload["node"]
		var lane := _lane_for_note(note)
		_register_judgement("Miss", lane, visual.global_position + visual.size * 0.5, note_id, 0.0, true)
		_judged_note_ids[note_id] = true
		_remove_note(note_id, true)

	# Clear any pending chord resolution for this time key.
	_pending_chord_groups.erase(time_key)


func _note_time_key(note_time: float) -> int:
	return int(round(note_time * 1000.0))


func _active_note_ids_for_time_key(time_key: int) -> Array[int]:
	var note_ids: Array[int] = []
	for spawned_note_id in _spawned_nodes.keys():
		var note_id := int(spawned_note_id)
		if _judged_note_ids.has(note_id):
			continue
		var payload: Dictionary = _spawned_nodes[note_id]
		var note: Dictionary = payload["note"]
		if _note_time_key(float(note.get("time", 0.0))) == time_key:
			note_ids.append(note_id)
	return note_ids


func _track_chord_resolution(note: Dictionary, note_id: int, song_time: float) -> void:
	var time_key := _note_time_key(float(note.get("time", 0.0)))
	# Determine chord membership using currently spawned notes even if one has already been judged.
	# This ensures double notes authored at the same timestamp can be hit by holding one key
	# and pressing the other without triggering the strict anti-mash "extra lane" rule.
	var sibling_note_ids: Array[int] = []
	for spawned_note_id in _spawned_nodes.keys():
		var id := int(spawned_note_id)
		if not _spawned_nodes.has(id):
			continue
		var payload: Dictionary = _spawned_nodes[id]
		var n: Dictionary = payload["note"]
		if _note_time_key(float(n.get("time", 0.0))) == time_key:
			sibling_note_ids.append(id)
	if sibling_note_ids.size() <= 1:
		_pending_chord_groups.erase(time_key)
		return
	var hit_note_ids: Dictionary = {}
	if _pending_chord_groups.has(time_key):
		hit_note_ids = (_pending_chord_groups[time_key] as Dictionary).get("hit_note_ids", {})
	hit_note_ids[note_id] = true
	var expected_lanes: Dictionary = {}
	for id in sibling_note_ids:
		if not _spawned_nodes.has(id):
			continue
		var payload: Dictionary = _spawned_nodes[id]
		var n: Dictionary = payload["note"]
		expected_lanes[_lane_for_note(n)] = true
	_pending_chord_groups[time_key] = {
		"deadline": song_time + CHORD_COMPLETION_GRACE,
		"note_ids": sibling_note_ids,
		"hit_note_ids": hit_note_ids,
		"expected_lanes": expected_lanes,
	}
	_resolve_chord_group_if_complete(time_key)


func _resolve_chord_group_if_complete(time_key: int) -> void:
	if not _pending_chord_groups.has(time_key):
		return
	var group: Dictionary = _pending_chord_groups[time_key]
	var note_ids: Array[int] = group.get("note_ids", [])
	var unresolved := false
	for note_id in note_ids:
		if not _judged_note_ids.has(note_id):
			unresolved = true
			break
	if not unresolved:
		_pending_chord_groups.erase(time_key)


func _resolve_expired_chord_groups(song_time: float) -> void:
	var expired_keys: Array[int] = []
	for time_key_variant in _pending_chord_groups.keys():
		var time_key := int(time_key_variant)
		var group: Dictionary = _pending_chord_groups[time_key]
		if song_time < float(group.get("deadline", 0.0)):
			continue
		var note_ids: Array[int] = group.get("note_ids", [])
		for note_id in note_ids:
			if _judged_note_ids.has(note_id):
				continue
			if not _spawned_nodes.has(note_id):
				continue
			var payload: Dictionary = _spawned_nodes[note_id]
			var note: Dictionary = payload["note"]
			var visual: HDNoteVisual = payload["node"]
			var lane := _lane_for_note(note)
			_register_judgement("Miss", lane, visual.global_position + visual.size * 0.5, note_id, 0.0, true)
			_judged_note_ids[note_id] = true
			_remove_note(note_id, true)
		expired_keys.append(time_key)
	for time_key in expired_keys:
		_pending_chord_groups.erase(time_key)


func _on_lane_released(lane: int) -> void:
	_active_input_lanes.erase(lane)
	if _visualizer_mode:
		return
	if _editor_live_mode and _editor_live_adding_enabled:
		editor_live_lane_event.emit(_current_chart_time(), lane, false)
		return
	if _is_failed:
		return
	if not _hold_state.has(lane):
		return
	var hold: Dictionary = _hold_state[lane]
	var note_dict: Dictionary = hold.get("note", {})
	var song_time := _current_chart_time()
	if song_time + SUSTAIN_RELEASE_FORGIVENESS < float(hold.get("end_time", 0.0)):
		_hold_break_count += 1
		_apply_drive_meter_judgement("Miss")
		if ProfileStore.is_miss_audio_ducking_enabled():
			AudioSync.duck_for_miss()
		var note_id := int(note_dict.get("id", -1))
		_remove_note(note_id, true)
	else:
		var note_id := int(note_dict.get("id", -1))
		if _spawned_nodes.has(note_id):
			var visual: HDNoteVisual = (_spawned_nodes[note_id] as Dictionary)["node"]
			_register_hold_success(lane, visual.global_position + visual.size * 0.5)
		_remove_note(note_id)
	_hold_state.erase(lane)


func _register_judgement(judgement: String, lane: int, position: Vector2, note_id: int = -1, delta: float = 0.0, count_for_accuracy: bool = true) -> void:
	_judgements[judgement] = int(_judgements.get(judgement, 0)) + 1
	if judgement == "Miss":
		_combo = 0
		if EmotionalMotionSystem != null:
			EmotionalMotionSystem.notify_miss()
	else:
		_combo += 1
	_max_combo = maxi(_max_combo, _combo)
	if EmotionalMotionSystem != null:
		EmotionalMotionSystem.set_combo_count(_combo)
		var song_time_for_fx := _current_chart_time() if _started else _audio_start_chart_time()
		var strength := 0.65
		match judgement:
			"Perfect":
				strength = 1.0
			"Great":
				strength = 0.85
			"Good":
				strength = 0.70
			"Miss":
				strength = 0.45
			_:
				strength = 0.65
		EmotionalMotionSystem.notify_judgement(lane, judgement, strength, song_time_for_fx, _hit_line_y() / maxf(1.0, _display_size().y))
		_spawn_ems_pressure_wave(lane, judgement, strength, position)
	var add_points := float(JudgementRules.score_for(judgement, _combo)) * _score_multiplier
	_score += int(round(add_points))
	if count_for_accuracy:
		_scored_note_count += 1
	match judgement:
		"Perfect":
			_weighted_accuracy += 1.0
			%JudgementLabel.modulate = HDTheme.PERFECT
			_apply_drive_meter_judgement("Perfect")
		"Great":
			_weighted_accuracy += 0.8
			%JudgementLabel.modulate = HDTheme.GREAT
			_apply_drive_meter_judgement("Great")
		"Good":
			_weighted_accuracy += 0.5
			%JudgementLabel.modulate = HDTheme.GOOD
			_apply_drive_meter_judgement("Good")
		_:
			%JudgementLabel.modulate = HDTheme.MISS
			_apply_drive_meter_judgement("Miss")
			if ProfileStore.is_miss_audio_ducking_enabled():
				AudioSync.duck_for_miss()
	if _judgement_popups_enabled:
		%JudgementLabel.text = judgement.to_upper()
		if _has_modifier("modifier_accuracy_trainer") and judgement != "Miss":
			_timing_feedback = "EARLY" if delta < 0.0 else "LATE"
			%JudgementLabel.text = "%s\n%s" % [judgement.to_upper(), _timing_feedback]
		%JudgementLabel.scale = Vector2(1.3, 1.3)
		%JudgementLabel.modulate.a = 1.0
		if is_instance_valid(_judgement_tween):
			_judgement_tween.kill()
		_judgement_tween = create_tween()
		_judgement_tween.parallel().tween_property(%JudgementLabel, "scale", Vector2.ONE, 0.12)
		_judgement_tween.parallel().tween_property(%JudgementLabel, "modulate:a", 0.0, 0.5).set_delay(0.24)
	else:
		%JudgementLabel.text = ""
		%JudgementLabel.modulate.a = 0.0
	if judgement != "Miss":
		var multiplayer_service := null if _editor_live_mode else _multiplayer_service()
		if multiplayer_service != null and multiplayer_service.has_method("is_session_active") and bool(multiplayer_service.call("is_session_active")):
			multiplayer_service.call("send_live_score", _score, _current_accuracy(), _combo)
		if _should_spawn_hit_particles():
			_spawn_hit_particles(position, lane)
		_react_stage_fx(lane, judgement)
		if _hit_effects_allow_shake() and _has_effect("effect_shake") and not _prioritize_fps:
			_apply_hit_shake()


func _register_hold_tick() -> void:
	_hold_tick_count += 1
	var add_points := float(JudgementRules.hold_tick_score(_combo)) * _score_multiplier
	_score += int(round(add_points))


func _register_hold_success(lane: int, position: Vector2) -> void:
	_hold_success_count += 1
	_combo += 1
	_max_combo = maxi(_max_combo, _combo)
	var add_points := float(JudgementRules.hold_success_score(_combo)) * _score_multiplier
	_score += int(round(add_points))
	var multiplayer_service := null if _editor_live_mode else _multiplayer_service()
	if multiplayer_service != null and multiplayer_service.has_method("is_session_active") and bool(multiplayer_service.call("is_session_active")):
		multiplayer_service.call("send_live_score", _score, _current_accuracy(), _combo)
	if _should_spawn_hit_particles():
		_spawn_hit_particles(position, lane)
	_react_stage_fx(lane, "Perfect")
	if _hit_effects_allow_shake() and _has_effect("effect_shake") and not _prioritize_fps:
		_apply_hit_shake()


func _current_accuracy() -> float:
	var judged_count: int = maxi(1, _scored_note_count)
	return (_weighted_accuracy / float(judged_count)) * 100.0


func _hit_effects_strength() -> float:
	match _hit_effects_mode:
		"off":
			return 0.0
		"minimal":
			return 0.35
		"enhanced":
			return 1.35 if not _prioritize_fps else 1.0
		_:
			return 1.0


func _should_spawn_hit_particles() -> bool:
	if not _hit_particles_profile_enabled():
		return false
	return _hit_effects_mode == "normal" or _hit_effects_mode == "enhanced"


func _hit_effects_allow_side_bars() -> bool:
	return _hit_effects_mode == "normal" or _hit_effects_mode == "enhanced"


func _hit_effects_allow_shake() -> bool:
	return _hit_effects_mode == "normal" or _hit_effects_mode == "enhanced"


func _spawn_hit_particles(position: Vector2, lane: int) -> void:
	if not _should_spawn_hit_particles():
		return
	if _maximum_actual_hit_particles_active():
		_spawn_actual_hit_particles(position, lane)
		return
	var color: Color = _lane_color(lane)
	var local_origin: Vector2 = position - _fx_layer.global_position
	var particle_count := 18 if _has_effect("effect_aftershock") else 12
	var spread := 58.0 if _has_effect("effect_aftershock") else 42.0
	var life := 0.28 if not _has_effect("effect_aftershock") else 0.34
	if _hit_effects_mode == "enhanced" and not _prioritize_fps:
		particle_count = int(round(float(particle_count) * 1.45))
		spread *= 1.18
		life *= 1.12
	if _prioritize_fps:
		particle_count = 6 if _has_effect("effect_aftershock") else 4
		spread *= 0.58
		life *= 0.58
	for _index in particle_count:
		var dot := _take_particle()
		if dot == null:
			break
		var dot_size := randf_range(7.0, 13.0)
		if _prioritize_fps:
			dot_size = randf_range(4.0, 8.0)
		dot.color = color
		dot.size = Vector2(dot_size, dot_size)
		dot.scale = Vector2.ONE
		dot.position = local_origin + Vector2(randf_range(-18.0, 18.0), randf_range(-12.0, 12.0))
		dot.modulate.a = 0.95
		dot.visible = true
		_active_particles.append({
			"node": dot,
			"velocity": Vector2(randf_range(-spread, spread), randf_range(-spread * 1.05, spread * 0.20)),
			"life": life,
			"max_life": life,
			"shrink": randf_range(0.48, 0.78),
		})


func _spawn_actual_hit_particles(position: Vector2, lane: int) -> void:
	var burst := _take_actual_hit_particle()
	if burst == null:
		return
	var color: Color = _lane_color(lane).lerp(Color.WHITE, 0.10)
	var local_origin: Vector2 = position - _fx_layer.global_position
	var aftershock := _has_effect("effect_aftershock")
	var effect_strength := _hit_effects_strength()
	var amount := 28 if aftershock else 20
	var spread := 72.0 if aftershock else 58.0
	var life := 0.42 if aftershock else 0.34
	var velocity := 245.0 if aftershock else 190.0
	if _hit_effects_mode == "enhanced":
		amount = int(round(float(amount) * 1.32))
		spread *= 1.12
		life *= 1.08
		velocity *= 1.12
	if AppState.is_mobile_platform():
		amount = int(round(float(amount) * 0.74))
		spread *= 0.86
		velocity *= 0.88
	burst.amount = maxi(8, int(round(float(amount) * effect_strength)))
	burst.lifetime = life
	burst.spread = 180.0
	burst.initial_velocity_min = velocity * 0.44
	burst.initial_velocity_max = velocity
	burst.gravity = Vector2(0.0, spread * 3.2)
	burst.scale_amount_min = 0.22
	burst.scale_amount_max = 0.72 if not aftershock else 0.95
	burst.color = color
	burst.position = local_origin
	burst.rotation = randf_range(-0.18, 0.18)
	burst.visible = true
	burst.emitting = false
	burst.restart()
	burst.emitting = true


func _spawn_trail_afterimage(visual: HDNoteVisual, lane: int) -> void:
	if _prioritize_fps:
		return
	var ghost := _take_trail_ghost()
	if ghost == null:
		return
	ghost.color = _lane_color(lane) * Color(1, 1, 1, 0.18)
	ghost.size = visual.size
	ghost.position = visual.position
	ghost.scale = Vector2.ONE
	ghost.rotation = visual.rotation
	ghost.modulate.a = 1.0
	ghost.visible = true
	_active_trails.append({
		"node": ghost,
		"life": 0.18,
		"max_life": 0.18,
		"shrink": 0.82,
	})


func _apply_hit_shake() -> void:
	_screen_shake_timer = 0.10
	_screen_shake_strength = maxf(_screen_shake_strength, 8.0)


func _on_round_state_updated(snapshot: Dictionary) -> void:
	var multiplayer_service := _multiplayer_service()
	if multiplayer_service == null or not multiplayer_service.has_method("get_opponent_snapshot"):
		return
	_opponent_snapshot = multiplayer_service.call("get_opponent_snapshot", snapshot)
	_update_hud()


func _update_hud() -> void:
	%ScoreLabel.text = "%d" % _score
	%MultiplierLabel.text = "×%d" % JudgementRules.combo_multiplier(_combo)
	%ComboLabel.text = "%d COMBO" % _combo
	var current_time := 0.0 if not _started else AudioSync.get_song_time_raw()
	%TimeLabel.text = _formatted_song_time(current_time, _song_duration)
	_update_modern_hud(current_time)
	if not _opponent_snapshot.is_empty():
		%OpponentNameLabel.text = str(_opponent_snapshot.get("displayName", "MATCH")).to_upper()
		var multiplayer_service := _multiplayer_service()
		var displayed_score: int = multiplayer_service.call("get_live_display_score_for_player", _opponent_snapshot) if multiplayer_service != null and multiplayer_service.has_method("get_live_display_score_for_player") else int(_opponent_snapshot.get("liveScore", 0))
		%OpponentScoreLabel.text = "%d" % displayed_score
		var live_combo: int = int(_opponent_snapshot.get("liveCombo", 0))
		%OpponentComboLabel.text = "COMBO %d" % live_combo if live_combo > 1 else ""
		_opponent_vbox.visible = not _is_modern_in_game_ui()
	else:
		%OpponentNameLabel.text = ""
		%OpponentScoreLabel.text = ""
		%OpponentComboLabel.text = ""
		_opponent_vbox.visible = false


func _multiplayer_service() -> Node:
	if AppState != null and AppState.has_method("get_active_multiplayer_service"):
		return AppState.get_active_multiplayer_service()
	return AppState.match_service


func _remove_note(note_id: int, missed: bool = false) -> void:
	if not _spawned_nodes.has(note_id):
		return
	var payload: Dictionary = _spawned_nodes[note_id]
	var node: HDNoteVisual = payload["node"]
	if is_instance_valid(node):
		if missed:
			node.miss_fade()
		else:
			node.pop_and_fade()
	_spawned_nodes.erase(note_id)


func configure_editor_live(notes: Array[Dictionary], lane_count: int, start_time_sec: float) -> void:
	if not _editor_live_mode:
		return
	var next_lane_count := LaneCountResolver.clamp_lane_count(lane_count)
	if next_lane_count != _lane_count:
		_lane_count = next_lane_count
		_chart["lane_count"] = _lane_count
		AppState.sync_input_actions(_lane_count)
		if _keyboard_input_provider != null:
			_keyboard_input_provider.setup_provider({"lane_count": _lane_count})
		if _controller_input_provider != null:
			_controller_input_provider.setup_provider({"lane_count": _lane_count})
		_build_lane_backgrounds()
		_build_receptors()
		_layout_playfield()
	editor_replace_live_notes(notes)
	editor_seek_live(start_time_sec)
	editor_set_live_paused(true)


func editor_set_live_paused(paused: bool) -> void:
	if not _editor_live_mode:
		return
	if paused:
		if AudioSync.is_playing():
			AudioSync.pause_playback()
		_is_paused = true
		_active_input_lanes.clear()
		_update_hud()
		return
	var current_time := AudioSync.get_song_time_raw()
	var duration := AudioSync.get_stream_length()
	if duration > 0.0 and current_time >= duration - 0.001:
		AudioSync.seek(0.0)
		_reset_editor_live_score()
		_rebuild_editor_live_notes(_current_chart_time())
	_editor_note_removal_enabled = false
	_refresh_editor_note_mouse_filters()
	_ensure_editor_audio_finished_connection()
	_is_paused = false
	AudioSync.resume_playback()


func editor_is_live_paused() -> bool:
	return _is_paused


func editor_live_audio_ready() -> bool:
	return _editor_live_mode and _editor_live_audio_ready


func editor_seek_live(time_sec: float) -> void:
	if not _editor_live_mode:
		return
	var duration := AudioSync.get_stream_length()
	var clamped := maxf(0.0, time_sec)
	if duration > 0.0:
		clamped = minf(clamped, duration)
	AudioSync.seek(clamped)
	_reset_editor_live_score()
	_rebuild_editor_live_notes(_current_chart_time())
	_update_hud()


func editor_set_live_adding(enabled: bool) -> void:
	if not _editor_live_mode:
		return
	if _editor_live_adding_enabled == enabled:
		return
	_editor_live_adding_enabled = enabled
	_active_input_lanes.clear()
	_pending_lane_presses.clear()
	_lane_press_flush_queued = false
	# Every authoring/testing transition clears the previous performance. In
	# particular, switching back to Test Play starts a clean scoring pass for the
	# currently selected section and the latest authoritative notes.
	_reset_editor_live_score()
	_rebuild_editor_live_notes(_current_chart_time())
	_update_hud()


func editor_set_note_removal_enabled(enabled: bool) -> void:
	if not _editor_live_mode:
		return
	_editor_note_removal_enabled = enabled and _is_paused
	_refresh_editor_note_mouse_filters()


func editor_replace_live_notes(notes: Array[Dictionary]) -> void:
	if not _editor_live_mode:
		return
	_notes.clear()
	_editor_live_note_ids.clear()
	var fallback_id := 0
	for note_variant in notes.duplicate(true):
		if note_variant is not Dictionary:
			continue
		var note: Dictionary = (note_variant as Dictionary).duplicate(true)
		if not note.has("id"):
			note["id"] = fallback_id
		fallback_id = maxi(fallback_id + 1, int(note.get("id", fallback_id)) + 1)
		note["time"] = maxf(0.0, float(note.get("time", 0.0)))
		note["lane"] = clampi(int(note.get("lane", 0)), 0, _lane_count - 1)
		var duration := maxf(0.0, float(note.get("duration", note.get("length", 0.0))))
		if duration > 0.0:
			note["type"] = "hold"
			note["length"] = duration
			note["duration"] = duration
		else:
			note["type"] = "tap"
			note.erase("length")
			note.erase("duration")
		_notes.append(note)
		_editor_live_note_ids[int(note.get("id", -1))] = true
	_notes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_time := float(a.get("time", 0.0))
		var b_time := float(b.get("time", 0.0))
		if is_equal_approx(a_time, b_time):
			var a_lane := int(a.get("lane", 0))
			var b_lane := int(b.get("lane", 0))
			if a_lane == b_lane:
				return int(a.get("id", 0)) < int(b.get("id", 0))
			return a_lane < b_lane
		return a_time < b_time
	)
	_chart["notes"] = _notes.duplicate(true)
	_seed_lane_overrides()
	_reset_editor_live_score()
	_rebuild_editor_live_notes(_current_chart_time())
	_update_hud()


func editor_add_live_note(note_value: Dictionary) -> void:
	if not _editor_live_mode or note_value.is_empty():
		return
	var note: Dictionary = note_value.duplicate(true)
	var note_id := int(note.get("id", -1))
	if note_id < 0 or _editor_live_note_ids.has(note_id):
		return
	note["time"] = maxf(0.0, float(note.get("time", 0.0)))
	note["lane"] = clampi(int(note.get("lane", 0)), 0, _lane_count - 1)
	var duration := maxf(0.0, float(note.get("duration", note.get("length", 0.0))))
	if duration > 0.0:
		note["type"] = "hold"
		note["length"] = duration
		note["duration"] = duration
	else:
		note["type"] = "tap"
		note.erase("length")
		note.erase("duration")

	var insert_index := _live_note_insert_index(note)
	_notes.insert(insert_index, note)
	_editor_live_note_ids[note_id] = true
	if insert_index < _next_note_index:
		_next_note_index += 1
	if insert_index < _next_chart_reactive_index:
		_next_chart_reactive_index += 1
	var song_time := _current_chart_time()
	var note_end := float(note.get("time", 0.0)) + duration
	if insert_index < _next_note_index \
			and note_end >= song_time - _approach_time() * 0.55 \
			and float(note.get("time", 0.0)) <= song_time + _approach_time():
		_spawn_note(note)
	else:
		_spawn_upcoming_notes(song_time)
	_update_active_notes(song_time)
func _live_note_insert_index(note: Dictionary) -> int:
	var low := 0
	var high := _notes.size()
	while low < high:
		var mid := (low + high) >> 1
		var existing: Dictionary = _notes[mid]
		var existing_time := float(existing.get("time", 0.0))
		var note_time := float(note.get("time", 0.0))
		var existing_before := existing_time < note_time
		if is_equal_approx(existing_time, note_time):
			var existing_lane := int(existing.get("lane", 0))
			var note_lane := int(note.get("lane", 0))
			existing_before = existing_lane < note_lane \
				or (existing_lane == note_lane and int(existing.get("id", -1)) < int(note.get("id", -1)))
		if existing_before:
			low = mid + 1
		else:
			high = mid
	return low


func _rebuild_editor_live_notes(song_time: float) -> void:
	if not _editor_live_mode or _note_layer == null:
		return
	for payload_variant in _spawned_nodes.values():
		if payload_variant is Dictionary:
			var visual := (payload_variant as Dictionary).get("node", null) as Control
			if visual != null and is_instance_valid(visual):
				if visual.get_parent() != null:
					visual.get_parent().remove_child(visual)
				visual.queue_free()
	_spawned_nodes.clear()
	_judged_note_ids.clear()
	_pending_chord_groups.clear()
	_hold_state.clear()
	_preview_ids.clear()
	_pending_lane_presses.clear()
	_lane_press_flush_queued = false
	_reset_editor_live_transient_fx()
	_next_note_index = 0
	var earliest_visible_time := song_time
	if _editor_live_adding_enabled:
		earliest_visible_time = song_time - _approach_time() * 0.55
	while _next_note_index < _notes.size():
		var candidate: Dictionary = _notes[_next_note_index]
		var candidate_start := float(candidate.get("time", 0.0))
		var candidate_end := candidate_start + float(candidate.get("duration", candidate.get("length", 0.0)))
		var candidate_time := candidate_end if _editor_live_adding_enabled else candidate_start
		if candidate_time >= earliest_visible_time:
			break
		_next_note_index += 1
	_next_chart_reactive_index = 0
	while _next_chart_reactive_index < _notes.size() \
			and float(_notes[_next_chart_reactive_index].get("time", 0.0)) < song_time:
		_next_chart_reactive_index += 1
	_spawn_upcoming_notes(song_time)
	_update_active_notes(song_time)
	_refresh_editor_note_mouse_filters()


func _reset_editor_live_score() -> void:
	if not _editor_live_mode:
		return
	_reset_seekable_session_score()


func _reset_practice_score() -> void:
	if not _practice_mode:
		return
	_reset_seekable_session_score()


func _reset_seekable_session_score() -> void:
	_score = 0
	_combo = 0
	_max_combo = 0
	_judgements = {"Perfect": 0, "Great": 0, "Good": 0, "Miss": 0}
	_weighted_accuracy = 0.0
	_scored_note_count = 0
	_hold_tick_count = 0
	_hold_success_count = 0
	_hold_break_count = 0
	_active_gameplay_seconds = 0.0
	_timing_feedback = ""
	_last_failed_time_key = -1
	_last_failed_time_key_deadline = 0.0
	_drive_meter = _max_drive_meter
	_displayed_drive_meter = _max_drive_meter
	if EmotionalMotionSystem != null:
		EmotionalMotionSystem.set_combo_count(0)
	if is_instance_valid(_judgement_tween):
		_judgement_tween.kill()
	%JudgementLabel.text = ""
	%JudgementLabel.scale = Vector2.ONE
	%JudgementLabel.modulate.a = 0.0


func _rebuild_editor_playtest_notes(song_time: float) -> void:
	if _editor_live_mode or _note_layer == null:
		return
	for payload_variant in _spawned_nodes.values():
		if payload_variant is Dictionary:
			var visual := (payload_variant as Dictionary).get("node", null) as Control
			if visual != null and is_instance_valid(visual):
				if visual.get_parent() != null:
					visual.get_parent().remove_child(visual)
				visual.queue_free()
	_spawned_nodes.clear()
	_judged_note_ids.clear()
	_pending_chord_groups.clear()
	_hold_state.clear()
	_preview_ids.clear()
	_pending_lane_presses.clear()
	_lane_press_flush_queued = false
	_reset_editor_live_transient_fx()
	_next_note_index = 0
	while _next_note_index < _notes.size() and float(_notes[_next_note_index].get("time", 0.0)) < song_time:
		_next_note_index += 1
	_next_chart_reactive_index = _next_note_index
	_spawn_upcoming_notes(song_time)
	_update_active_notes(song_time)


func _discard_spawned_note(note_id: int) -> void:
	if not _spawned_nodes.has(note_id):
		return
	var payload: Dictionary = _spawned_nodes[note_id]
	var visual := payload.get("node", null) as Control
	if visual != null and is_instance_valid(visual):
		if visual.get_parent() != null:
			visual.get_parent().remove_child(visual)
		visual.queue_free()
	_spawned_nodes.erase(note_id)


func _reset_editor_live_transient_fx() -> void:
	for particle_variant in _active_particles:
		if particle_variant is Dictionary:
			var dot := (particle_variant as Dictionary).get("node", null) as ColorRect
			if dot != null and is_instance_valid(dot):
				_release_particle(dot)
	_active_particles.clear()
	for trail_variant in _active_trails:
		if trail_variant is Dictionary:
			var ghost := (trail_variant as Dictionary).get("node", null) as ColorRect
			if ghost != null and is_instance_valid(ghost):
				_release_trail_ghost(ghost)
	_active_trails.clear()
	for burst in _actual_hit_particle_pool:
		if burst != null and is_instance_valid(burst):
			burst.emitting = false
			burst.visible = false
	_screen_shake_timer = 0.0
	_screen_shake_strength = 0.0
	_lane_flash_layer.position = Vector2.ZERO
	_note_layer.position = Vector2.ZERO
	_fx_layer.position = Vector2.ZERO


func _refresh_editor_note_mouse_filters() -> void:
	if not _editor_live_mode:
		return
	var filter := Control.MOUSE_FILTER_STOP if _editor_note_removal_enabled and _is_paused else Control.MOUSE_FILTER_IGNORE
	for payload_variant in _spawned_nodes.values():
		if payload_variant is not Dictionary:
			continue
		var visual := (payload_variant as Dictionary).get("node", null) as Control
		if visual != null and is_instance_valid(visual):
			visual.mouse_filter = filter


func _on_editor_note_gui_input(event: InputEvent, note_id: int) -> void:
	if not _editor_live_mode or not _is_paused or not _editor_note_removal_enabled:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		editor_note_remove_requested.emit(note_id)
		accept_event()


func _input(event: InputEvent) -> void:
	# Gameplay rails and HUD elements sit above NoteLayer in the real scene. Resolve
	# paused editor clicks before GUI propagation so those presentation controls
	# cannot prevent a visible note head from being selected for removal.
	if not _editor_live_mode or not _is_paused or not _editor_note_removal_enabled:
		return
	if event is not InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index != MOUSE_BUTTON_LEFT or not mouse_event.pressed:
		return
	var hit_note_id := -1
	for note_id_variant in _spawned_nodes.keys():
		var payload: Dictionary = _spawned_nodes[note_id_variant]
		var visual := payload.get("node", null) as Control
		if visual == null or not is_instance_valid(visual) or not visual.visible:
			continue
		var local_position := visual.get_global_transform_with_canvas().affine_inverse() * mouse_event.position
		if Rect2(Vector2.ZERO, visual.size).has_point(local_position):
			hit_note_id = int(note_id_variant)
			break
	if hit_note_id >= 0:
		get_viewport().set_input_as_handled()
		editor_note_remove_requested.emit(hit_note_id)


func _ensure_editor_audio_finished_connection() -> void:
	if not AudioSync.playback_finished.is_connected(_on_audio_finished):
		AudioSync.playback_finished.connect(_on_audio_finished, CONNECT_ONE_SHOT)


func _flash_receptor(lane: int) -> void:
	if lane < 0 or lane >= _receptor_feedback_nodes.size():
		return
	_receptor_press_energy[lane] = 1.0
	_apply_receptor_feedback(lane, 1.0)


func _update_receptor_feedback(delta: float) -> void:
	for lane in _receptor_press_energy.size():
		var energy := 1.0 if bool(_active_input_lanes.get(lane, false)) else maxf(0.0, float(_receptor_press_energy[lane]) - delta * 8.5)
		_receptor_press_energy[lane] = energy
		_apply_receptor_feedback(lane, energy)


func _apply_receptor_feedback(lane: int, energy: float) -> void:
	if lane < 0 or lane >= _receptor_feedback_nodes.size():
		return
	var nodes := _receptor_feedback_nodes[lane]
	var panel := nodes.get("panel", null) as PanelContainer
	var press_glow := nodes.get("press_glow", null) as PanelContainer
	var key_visual := nodes.get("key_visual", null) as CanvasItem
	if panel != null:
		var scale_boost := 0.0 if _prioritize_fps else 0.022 * energy
		panel.scale = Vector2.ONE * (1.0 + scale_boost)
	if press_glow != null:
		press_glow.modulate.a = 0.82 * energy
		if not _prioritize_fps:
			press_glow.scale = Vector2.ONE * (1.0 + 0.055 * (1.0 - energy))
	if is_instance_valid(key_visual):
		key_visual.modulate = Color(1.0, 1.0, 1.0, lerpf(0.92, 1.0, energy))


func _hit_line_y() -> float:
	var viewport_size := _display_size()
	return viewport_size.y * 0.86


func _spawn_y() -> float:
	return -_note_height() * 0.5


func _note_size() -> Vector2:
	return Vector2(_lane_width() * 0.78, _note_height())


func _note_width() -> float:
	return _note_size().x


func _note_height() -> float:
	var viewport_size := _display_size()
	return maxf(22.0, viewport_size.y * 0.028)


func _receptor_button_height() -> float:
	var viewport_size := _display_size()
	return clampf(viewport_size.y * 0.102, 60.0, 108.0)


func _should_show_lane_key_labels() -> bool:
	return not AppState.is_mobile_platform()


func _lane_binding_display(lane: int) -> Dictionary:
	var bindings: Dictionary = ProfileStore.get_key_bindings(_lane_count)
	var action := "lane_%d" % lane
	var keycode := int(bindings.get(action, 0))
	return InputBindingGlyph.keyboard_display(keycode)


func _playfield_width() -> float:
	var viewport_size := _display_size()
	var lane_width_scale := 0.4
	if ProfileStore != null:
		lane_width_scale = ProfileStore.get_lane_width_scale()
	if AppState.is_mobile_platform():
		return clampf((viewport_size.x - 20.0) * lane_width_scale, 120.0, viewport_size.x - 20.0)
	var base := minf(viewport_size.x - 64.0, maxf(720.0, viewport_size.y * 0.56))
	return clampf(base * lane_width_scale, 120.0, viewport_size.x - 64.0)


func _playfield_left() -> float:
	var viewport_size := _display_size()
	return (viewport_size.x - _playfield_width()) * 0.5


func _playfield_right() -> float:
	return _playfield_left() + _playfield_width()


func _community_ems_uses_full_background() -> bool:
	return EmotionalMotionSystem != null and EmotionalMotionSystem.has_method("community_uses_full_background") and bool(EmotionalMotionSystem.call("community_uses_full_background"))


func _on_ems_loadout_changed(_loadout_id: String) -> void:
	_layout_hit_zone()


func _layout_hit_zone() -> void:
	var viewport_size := _display_size()
	var playfield_left := _playfield_left()
	var playfield_right := _playfield_right()
	var playfield_width := _playfield_width()
	var lane_width := _lane_width()
	var hit_line := _hit_line_y()
	var gutter_left_width := maxf(0.0, playfield_left)
	var gutter_right_width := maxf(0.0, viewport_size.x - playfield_right)
	var is_desktop := not AppState.is_mobile_platform()
	_lane_centers.clear()
	for lane in _lane_count:
		_lane_centers.append(_lane_x(lane))
	_lane_backgrounds.offset_left = playfield_left
	_lane_backgrounds.offset_right = playfield_right - viewport_size.x
	_lane_backgrounds.visible = not _chart_background_disabled and not _is_black_hole_mode()
	_runway_inset.visible = not _chart_background_disabled and not _is_black_hole_mode()
	if _playfield_ems_background != null:
		_playfield_ems_background.visible = false
		_playfield_ems_background.position = Vector2(playfield_left, 0.0)
		_playfield_ems_background.size = Vector2(playfield_width, viewport_size.y)
		_playfield_ems_background.color = _transparent_ems_canvas_color()
	if _spiral_lane_layer != null:
		_spiral_lane_layer.position = Vector2(playfield_left, 0.0)
		_spiral_lane_layer.size = Vector2(playfield_width, viewport_size.y)
		_spiral_lane_layer.visible = _is_spiral_theme()
		_spiral_lane_layer.configure(_lane_count, _theme_palette.get("lane_colors", HDTheme.LANE_COLORS), true)
		_spiral_lane_layer.set_playfield_metrics(playfield_left, playfield_width, hit_line)
	if _black_hole_lane_layer != null:
		_black_hole_lane_layer.position = Vector2(playfield_left, 0.0)
		_black_hole_lane_layer.size = Vector2(playfield_width, viewport_size.y)
		_black_hole_lane_layer.visible = _is_black_hole_mode()
		_black_hole_lane_layer.configure(_lane_count, _theme_palette.get("lane_colors", HDTheme.LANE_COLORS))
		_black_hole_lane_layer.set_playfield_metrics(playfield_left, playfield_width, hit_line)
	var ems_left_edge := playfield_left
	var ems_right_edge := playfield_right
	var disabled_chart_center_x := floorf(viewport_size.x * 0.5)
	if _chart_background_disabled:
		ems_left_edge = disabled_chart_center_x
		ems_right_edge = disabled_chart_center_x
	var community_full_background := _community_ems_uses_full_background()
	if _emotional_motion_left_gutter != null:
		_emotional_motion_left_gutter.anchor_left = 0.0
		_emotional_motion_left_gutter.anchor_right = 1.0 if community_full_background else 0.0
		_emotional_motion_left_gutter.anchor_top = 0.0
		_emotional_motion_left_gutter.anchor_bottom = 1.0
		_emotional_motion_left_gutter.offset_left = 0.0
		_emotional_motion_left_gutter.offset_right = 0.0 if community_full_background else ems_left_edge
		_emotional_motion_left_gutter.offset_top = 0.0
		_emotional_motion_left_gutter.offset_bottom = 0.0
		_emotional_motion_left_gutter.visible = true
		_emotional_motion_left_gutter.set_process(true)
		_emotional_motion_left_gutter.set_physics_process(true)
	if _emotional_motion_right_gutter != null:
		if community_full_background:
			_emotional_motion_right_gutter.visible = false
			_emotional_motion_right_gutter.set_process(false)
			_emotional_motion_right_gutter.set_physics_process(false)
		else:
			_emotional_motion_right_gutter.anchor_left = 0.0
			_emotional_motion_right_gutter.anchor_right = 0.0
			_emotional_motion_right_gutter.anchor_top = 0.0
			_emotional_motion_right_gutter.anchor_bottom = 1.0
			_emotional_motion_right_gutter.offset_left = ems_right_edge
			_emotional_motion_right_gutter.offset_right = viewport_size.x
			_emotional_motion_right_gutter.offset_top = 0.0
			_emotional_motion_right_gutter.offset_bottom = 0.0
			_emotional_motion_right_gutter.visible = true
			_emotional_motion_right_gutter.set_process(true)
			_emotional_motion_right_gutter.set_physics_process(true)
	if OS.is_debug_build():
		if _emotional_motion_left_gutter != null:
			print("[GameScene] EMS left gutter pos=%s size=%s" % [str(_emotional_motion_left_gutter.position), str(_emotional_motion_left_gutter.size)])
		if _emotional_motion_right_gutter != null:
			print("[GameScene] EMS right gutter pos=%s size=%s" % [str(_emotional_motion_right_gutter.position), str(_emotional_motion_right_gutter.size)])
	_runway_inset.offset_left = playfield_left + lane_width * 0.11
	_runway_inset.offset_right = (playfield_right - lane_width * 0.11) - viewport_size.x
	_runways.add_theme_constant_override("separation", lane_width * 0.22)
	_receptor_deck.visible = false
	_background_decor.position = Vector2.ZERO
	_background_decor.size = viewport_size
	var left_gutter_width := gutter_left_width
	var right_gutter_x := playfield_right
	if _chart_background_disabled:
		left_gutter_width = disabled_chart_center_x
		right_gutter_x = disabled_chart_center_x
	_left_gutter.position = Vector2.ZERO
	_left_gutter.size = Vector2(left_gutter_width, viewport_size.y)
	_right_gutter.position = Vector2(right_gutter_x, 0.0)
	_right_gutter.size = Vector2(viewport_size.x - right_gutter_x, viewport_size.y)
	if _left_gutter_image != null:
		if _gutter_image_mode == "both":
			_left_gutter_image.position = Vector2.ZERO
			_left_gutter_image.size = viewport_size
		else:
			_left_gutter_image.position = Vector2.ZERO
			_left_gutter_image.size = Vector2(gutter_left_width, viewport_size.y)
	if _right_gutter_image != null:
		_right_gutter_image.position = Vector2(playfield_right, 0.0)
		_right_gutter_image.size = Vector2(gutter_right_width, viewport_size.y)
	if _chart_background_disabled:
		if _left_gutter_image != null:
			_left_gutter_image.visible = false
		if _right_gutter_image != null:
			_right_gutter_image.visible = false
	_top_glow.position = Vector2(playfield_left + lane_width * 0.18, 18.0)
	_top_glow.size = Vector2(playfield_width - lane_width * 0.36, maxf(44.0, viewport_size.y * 0.055))
	_bottom_glow.position = Vector2(playfield_left + lane_width * 0.10, hit_line - maxf(18.0, viewport_size.y * 0.018))
	_bottom_glow.size = Vector2(playfield_width - lane_width * 0.20, maxf(54.0, viewport_size.y * 0.06))
	_lane_cover.visible = _has_modifier("modifier_lane_cover") and not _chart_background_disabled
	_lane_cover.position = Vector2(playfield_left, 0.0)
	_lane_cover.size = Vector2(playfield_width, maxf(78.0, viewport_size.y * 0.16))
	for index in _grid_lines.size():
		var line := _grid_lines[index]
		var ratio := float(index + 1) / float(_grid_lines.size() + 1)
		line.position = Vector2(playfield_left + lane_width * 0.08, lerpf(_spawn_y() + 48.0, hit_line - 72.0, ratio))
		line.size = Vector2(playfield_width - lane_width * 0.16, 1.0)
	for lane in _lane_flash_nodes.size():
		var flash := _lane_flash_nodes[lane]
		flash.position = Vector2(_lane_x(lane) - lane_width * 0.42, _spawn_y())
		flash.size = Vector2(lane_width * 0.84, hit_line - _spawn_y() + 12.0)
	if _max_gameplay_shader_layer != null:
		_max_gameplay_shader_layer.position = Vector2(playfield_left, 0.0)
		_max_gameplay_shader_layer.size = Vector2(playfield_width, viewport_size.y)
		_max_gameplay_shader_layer.set_playfield_metrics(_lane_count, hit_line / maxf(1.0, viewport_size.y))
	if _ems_pressure_wave_layer != null:
		_ems_pressure_wave_layer.position = Vector2(playfield_left, 0.0)
		_ems_pressure_wave_layer.size = Vector2(playfield_width, viewport_size.y)
		_ems_pressure_wave_layer.visible = _maximum_pressure_waves_active()
		_ems_pressure_wave_layer.configure(_lane_count, hit_line, _theme_palette.get("lane_colors", HDTheme.LANE_COLORS))
	for index in _desktop_left_bars.size():
		var left_bar := _desktop_left_bars[index]
		var right_bar := _desktop_right_bars[index]
		var bar_width := clampf(gutter_right_width * 0.15, 14.0, 30.0)
		var bar_height := viewport_size.y * (0.18 + float(index) * 0.08)
		var top := viewport_size.y * (0.17 + float(index) * 0.15)
		var left_x := maxf(10.0, gutter_left_width * 0.20 + float(index) * (bar_width + 10.0))
		var right_x := viewport_size.x - gutter_right_width * 0.22 - float(SIDE_BAR_COUNT - index) * (bar_width + 10.0)
		left_bar.visible = is_desktop
		right_bar.visible = is_desktop
		left_bar.position = Vector2(left_x, top)
		left_bar.size = Vector2(bar_width, bar_height)
		right_bar.position = Vector2(right_x, top)
		right_bar.size = Vector2(bar_width, bar_height)

	var rail_color: Color = _theme_palette.get("rail", HDTheme.CYAN)
	var glow_height := maxf(10.5, viewport_size.y * 0.0105)
	_hit_rail_glow.anchor_left = 0.0
	_hit_rail_glow.anchor_right = 0.0
	_hit_rail_glow.anchor_top = 0.0
	_hit_rail_glow.anchor_bottom = 0.0
	_hit_rail_glow.offset_left = playfield_left
	_hit_rail_glow.offset_right = playfield_right
	_hit_rail_glow.color = rail_color * Color(1, 1, 1, 0.18)
	_hit_rail_glow.offset_top = hit_line - glow_height * 0.5
	_hit_rail_glow.offset_bottom = hit_line + glow_height * 0.5
	_hit_rail_glow.visible = not _ems_hit_target_mode()

	var rail_height := maxf(4.2, viewport_size.y * 0.00441)
	_hit_rail.anchor_left = 0.0
	_hit_rail.anchor_right = 0.0
	_hit_rail.anchor_top = 0.0
	_hit_rail.anchor_bottom = 0.0
	_hit_rail.offset_left = playfield_left
	_hit_rail.offset_right = playfield_right
	_hit_rail.color = rail_color.lerp(Color(1.0, 1.0, 1.0, 1.0), 0.22)
	_hit_rail.offset_top = hit_line - rail_height * 0.5
	_hit_rail.offset_bottom = hit_line + rail_height * 0.5
	_hit_rail.visible = not _ems_hit_target_mode()

	var btn_height := _note_height() if _ems_hit_target_mode() else _receptor_button_height()
	var receptors_top := hit_line - btn_height * 0.5 if _ems_hit_target_mode() else hit_line + 10.0 + (_receptor_button_height() * 0.05)
	var receptors_bottom := receptors_top + btn_height
	_receptors_margin.anchor_left = 0.0
	_receptors_margin.anchor_right = 0.0
	_receptors_margin.anchor_top = 0.0
	_receptors_margin.anchor_bottom = 0.0
	_receptors_margin.offset_left = playfield_left
	_receptors_margin.offset_right = playfield_right
	_receptors_margin.offset_top = receptors_top
	_receptors_margin.offset_bottom = receptors_bottom
	_receptors_margin.add_theme_constant_override("margin_top", 0)
	_receptors_margin.add_theme_constant_override("margin_bottom", 0)
	_receptors.add_theme_constant_override("separation", 0)
	_layout_touch_input(playfield_left, lane_width, hit_line, receptors_bottom)

	var score_top := 18.0
	var left_gutter_hud_left := 18.0
	var left_gutter_hud_width := maxf(0.0, playfield_left - 36.0)
	var left_gutter_hud_score_width := clampf(left_gutter_hud_width, 118.0, 164.0)
	if playfield_left < 190.0:
		left_gutter_hud_left = playfield_left + 8.0
		left_gutter_hud_score_width = minf(playfield_width * 0.34, 150.0)
	_score_pill.size.x = left_gutter_hud_score_width
	_score_pill.offset_left = left_gutter_hud_left
	_score_pill.offset_top = score_top
	_score_pill.offset_right = _score_pill.offset_left + _score_pill.size.x
	_score_pill.offset_bottom = _score_pill.offset_top + _score_pill.size.y

	var score_multiplier_gap := 50.0
	_multiplier_pill.anchor_left = 0.0
	_multiplier_pill.anchor_right = 0.0
	_multiplier_pill.anchor_top = 0.0
	_multiplier_pill.anchor_bottom = 0.0
	_multiplier_pill.offset_left = _score_pill.offset_right + score_multiplier_gap
	_multiplier_pill.offset_right = _multiplier_pill.offset_left + _multiplier_pill.size.x
	_multiplier_pill.offset_top = score_top + (_score_pill.size.y - _multiplier_pill.size.y) * 0.5
	_multiplier_pill.offset_bottom = _multiplier_pill.offset_top + _multiplier_pill.size.y

	_pause_button.anchor_left = 0.0
	_pause_button.anchor_right = 0.0
	_pause_button.anchor_top = 0.0
	_pause_button.anchor_bottom = 0.0
	_pause_button.offset_left = viewport_size.x - 18.0 - _pause_button.custom_minimum_size.x
	_pause_button.offset_right = _pause_button.offset_left + _pause_button.custom_minimum_size.x
	_pause_button.offset_top = score_top + 40.0
	_pause_button.offset_bottom = _pause_button.offset_top + _pause_button.custom_minimum_size.y
	var drive_meter_width := minf(playfield_width * (0.74 if AppState.is_mobile_platform() else 0.44), viewport_size.x - 44.0)
	var drive_meter_min_width := minf(220.0, viewport_size.x - 44.0)
	drive_meter_width = clampf(drive_meter_width, drive_meter_min_width, viewport_size.x - 44.0)
	var drive_meter_height := 18.0
	var drive_meter_left := playfield_left + (playfield_width - drive_meter_width) * 0.5
	var drive_meter_top := 8.0
	_drive_meter_container.offset_left = drive_meter_left
	_drive_meter_container.offset_top = drive_meter_top
	_drive_meter_container.offset_right = drive_meter_left + drive_meter_width
	_drive_meter_container.offset_bottom = drive_meter_top + drive_meter_height
	_top_center_vbox.anchor_left = 0.0
	_top_center_vbox.anchor_right = 0.0
	_top_center_vbox.anchor_top = 0.0
	_top_center_vbox.anchor_bottom = 0.0
	var hud_info_left: float
	var hud_info_right: float
	var hud_info_width: float
	if AppState.is_mobile_platform():
		hud_info_width = minf(playfield_width * 0.72, viewport_size.x - 40.0)
		hud_info_left = playfield_left + (playfield_width - hud_info_width) * 0.5
		hud_info_right = hud_info_left + hud_info_width
		_top_center_vbox.offset_top = drive_meter_top + drive_meter_height + 8.0
		_top_center_vbox.offset_bottom = 132.0
	else:
		hud_info_left = playfield_right + 18.0
		hud_info_right = _pause_button.offset_left - 16.0
		hud_info_width = hud_info_right - hud_info_left
		if hud_info_width < 240.0:
			hud_info_width = clampf(gutter_right_width - 28.0, 180.0, 320.0)
			hud_info_right = viewport_size.x - 92.0
			hud_info_left = hud_info_right - hud_info_width
		hud_info_left = maxf(playfield_right + 12.0, hud_info_left)
		hud_info_right = minf(viewport_size.x - 22.0, hud_info_right)
		if hud_info_right - hud_info_left < 120.0:
			hud_info_width = minf(240.0, viewport_size.x * 0.28)
			hud_info_right = viewport_size.x - 18.0
			hud_info_left = hud_info_right - hud_info_width
		hud_info_width = maxf(160.0, hud_info_right - hud_info_left)
		_top_center_vbox.offset_top = 18.0
		_top_center_vbox.offset_bottom = 194.0
	_top_center_vbox.offset_left = hud_info_left
	_top_center_vbox.offset_right = hud_info_right
	_top_center_vbox.custom_minimum_size.x = hud_info_width
	_top_center_vbox.add_theme_constant_override("separation", 4)
	%ComboLabel.custom_minimum_size.x = hud_info_width
	%TrackLabel.custom_minimum_size.x = hud_info_width
	%TimeLabel.custom_minimum_size.x = hud_info_width
	%ComboLabel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	%TrackLabel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	%TimeLabel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_opponent_vbox.offset_left = 18.0
	_opponent_vbox.offset_top = 64.0
	_opponent_vbox.offset_right = 206.0
	_opponent_vbox.offset_bottom = 128.0
	_layout_modern_hud(viewport_size)


func _layout_touch_input(playfield_left: float, lane_width: float, hit_line: float, receptors_bottom: float) -> void:
	# Touch/mouse lane hit testing should match the current playfield width (including on desktop,
	# where mouse clicks emulate touch input for testing).
	if not AppState.supports_touch_gameplay():
		return
	var viewport_size := _display_size()
	var touch_top: float = maxf(hit_line - maxf(72.0, _receptor_button_height() * 0.95), 0.0)
	var touch_height: float = maxf(viewport_size.y - touch_top, receptors_bottom - touch_top)
	_touch_provider.set_lane_layout({
		"left": playfield_left,
		"top": touch_top,
		"width": _playfield_width(),
		"height": touch_height,
		"separation": 0.0,
	})


func _formatted_song_time(current_seconds: float, total_seconds: float) -> String:
	var safe_total := maxf(0.0, total_seconds)
	var safe_current := clampf(current_seconds, 0.0, safe_total if safe_total > 0.0 else maxf(0.0, current_seconds))
	return "%s / %s" % [_format_time_value(safe_current), _format_time_value(safe_total)]


func _format_time_value(seconds: float) -> String:
	var total_seconds := maxi(0, int(floor(seconds + 0.0001)))
	var minutes := total_seconds / 60
	var remaining_seconds := total_seconds % 60
	return "%d:%02d" % [minutes, remaining_seconds]


func _layout_playfield() -> void:
	_apply_note_layer_order()
	_layout_hit_zone()
	_apply_spiral_playfield_transform(0.0)
	if _visualizer_mode:
		_configure_visualizer_presentation()


func _apply_note_layer_order() -> void:
	if _note_layer == null or _fx_layer == null:
		return
	_note_layer.z_index = 0
	_fx_layer.z_index = 0
	if _notes_above_judgement_buttons:
		var receptors_index := get_children().find(_receptors_margin)
		if receptors_index >= 0:
			move_child(_note_layer, receptors_index + 1)
			move_child(_fx_layer, get_children().find(_note_layer) + 1)
	else:
		var fx_index := get_children().find(_fx_layer)
		if fx_index >= 0:
			move_child(_note_layer, maxi(0, fx_index))


func _place_note_visual_on_lane(visual: Control, lane: int, y: float) -> void:
	if visual == null or not is_instance_valid(visual):
		return
	visual.pivot_offset = visual.size * 0.5
	if _is_black_hole_mode():
		var black_hole_center := _black_hole_lane_center_for_y(lane, y)
		visual.position = black_hole_center - visual.size * 0.5
		visual.rotation = _black_hole_lane_rotation_for_y(lane, y)
		visual.scale = Vector2.ONE
		return
	visual.rotation = 0.0
	visual.position = Vector2(_lane_x(lane) - visual.size.x * 0.5, y - _note_height() * 0.5)


func _spiral_lane_center_for_y(lane: int, y: float) -> Vector2:
	var hit_line := _hit_line_y()
	var travel_span := _spawn_y() - hit_line
	if absf(travel_span) < 1.0:
		travel_span = -1.0
	var progress := clampf((y - hit_line) / travel_span, 0.0, 1.0)
	return _spiral_lane_center_for_progress(lane, progress)


func _spiral_lane_rotation_for_y(lane: int, y: float) -> float:
	var hit_line := _hit_line_y()
	var travel_span := _spawn_y() - hit_line
	if absf(travel_span) < 1.0:
		travel_span = -1.0
	var progress := clampf((y - hit_line) / travel_span, 0.0, 1.0)
	var before := _spiral_lane_center_for_progress(lane, clampf(progress + 0.012, 0.0, 1.0))
	var after := _spiral_lane_center_for_progress(lane, clampf(progress - 0.012, 0.0, 1.0))
	var travel := after - before
	if travel.length_squared() <= 0.001:
		return 0.0
	return travel.angle() - PI * 0.5


func _spiral_lane_center_for_progress(lane: int, progress: float) -> Vector2:
	return SpiralLaneLayer.spiral_lane_position(
		lane,
		progress,
		_spiral_lanes_phase,
		_display_size(),
		_playfield_left(),
		_playfield_width(),
		_hit_line_y(),
		_lane_count
	)


func _black_hole_lane_center_for_y(lane: int, y: float) -> Vector2:
	var hit_line := _hit_line_y()
	var travel_span := _spawn_y() - hit_line
	if absf(travel_span) < 1.0:
		travel_span = -1.0
	var progress := clampf((y - hit_line) / travel_span, 0.0, 1.0)
	return _black_hole_lane_center_for_progress(lane, progress)


func _black_hole_lane_rotation_for_y(lane: int, y: float) -> float:
	var hit_line := _hit_line_y()
	var travel_span := _spawn_y() - hit_line
	if absf(travel_span) < 1.0:
		travel_span = -1.0
	var progress := clampf((y - hit_line) / travel_span, 0.0, 1.0)
	var before := _black_hole_lane_center_for_progress(lane, clampf(progress + 0.012, 0.0, 1.0))
	var after := _black_hole_lane_center_for_progress(lane, clampf(progress - 0.012, 0.0, 1.0))
	var travel := after - before
	if travel.length_squared() <= 0.001:
		return 0.0
	return travel.angle() - PI * 0.5


func _black_hole_lane_center_for_progress(lane: int, progress: float) -> Vector2:
	return BlackHoleLaneLayer.black_hole_lane_position(
		lane,
		progress,
		_black_hole_phase,
		_display_size(),
		_playfield_left(),
		_playfield_width(),
		_hit_line_y(),
		_lane_count
	)


func _lane_width() -> float:
	return _playfield_width() / float(_lane_count)


func _lane_x(lane: int) -> float:
	return _playfield_left() + (float(lane) + 0.5) * _lane_width()


func _on_pause_button_pressed() -> void:
	if _finished or _is_failed:
		return
	_is_paused = true
	_pause_overlay.visible = true
	AudioSync.pause_playback()


func _on_resume_button_pressed() -> void:
	_is_paused = false
	_pause_overlay.visible = false
	if _started:
		AudioSync.resume_playback()


func _on_restart_button_pressed() -> void:
	_restart_current_song(false)


func _on_exit_button_pressed() -> void:
	AudioSync.stop_playback()
	_finished = true
	game_exited.emit()


func _on_retry_button_pressed() -> void:
	_restart_current_song(false)


func _on_practice_button_pressed() -> void:
	_restart_current_song(true)


func _on_fail_quit_button_pressed() -> void:
	AudioSync.stop_playback()
	_finished = true
	game_exited.emit()


func _restart_current_song(force_no_fail: bool) -> void:
	_finished = true
	_is_paused = false
	_is_failed = false
	_failure_stats_recorded = false
	_active_input_lanes.clear()
	_pending_lane_presses.clear()
	_lane_press_flush_queued = false
	_pause_overlay.visible = false
	_fail_overlay.visible = false
	AudioSync.stop_playback()
	if _practice_mode or force_no_fail:
		AppState.start_practice_song(_song, _difficulty, _mode)
	else:
		AppState.start_song(_song, _difficulty, _mode, force_no_fail)


func _on_audio_finished() -> void:
	if _visualizer_mode:
		if _finished:
			return
		if _visualizer_is_chart_reactive():
			# Treat every remaining authored note as Perfect so Chart Reactive always
			# completes as a virtual 100% FC, even when a chart tail meets audio EOF.
			_dispatch_due_visualizer_chart_hits(INF)
		_finished = true
		if EmotionalMotionSystem != null:
			var visualizer_result := _visualizer_fc_payload()
			visualizer_result.merge({
				"song_id": str(_song.get("id", "")),
				"mode": "visualizer",
				"strength": 1.0,
			}, true)
			EmotionalMotionSystem.dispatch_ems_event("song_ended", visualizer_result)
		visualizer_song_finished.emit()
		return
	if _editor_live_mode:
		_is_paused = true
		_active_input_lanes.clear()
		_update_hud()
		return
	if _practice_mode:
		_is_paused = true
		_active_input_lanes.clear()
		_update_practice_transport()
		_update_hud()
		return
	_finish_song()


func _visualizer_fc_payload() -> Dictionary:
	var perfect_count := int(_judgements.get("Perfect", 0))
	var total_notes := _notes.size()
	var virtual_fc := _visualizer_is_chart_reactive() and total_notes > 0 and perfect_count == total_notes
	return {
		"score": 0,
		"max_combo": _max_combo,
		"perfect": perfect_count,
		"great": 0,
		"good": 0,
		"miss": 0,
		"notes_hit": perfect_count,
		"notes_missed": 0,
		"total_notes_judged": perfect_count,
		"full_combo": virtual_fc,
		"all_perfect": virtual_fc,
		"accuracy": 100.0 if virtual_fc else 0.0,
	}


func _notes_hit_count() -> int:
	return int(_judgements.get("Perfect", 0)) \
		+ int(_judgements.get("Great", 0)) \
		+ int(_judgements.get("Good", 0)) \
		+ _hold_success_count


func _notes_missed_count() -> int:
	return int(_judgements.get("Miss", 0)) + _hold_break_count


func _finish_song() -> void:
	if _visualizer_mode:
		_on_audio_finished()
		return
	if _practice_mode:
		_is_paused = true
		_active_input_lanes.clear()
		_update_practice_transport()
		return
	if _finished or _is_failed:
		return
	_finished = true
	if EmotionalMotionSystem != null:
		EmotionalMotionSystem.dispatch_ems_event("song_ended", {"strength": 1.0, "score": _score, "max_combo": _max_combo})
	AudioSync.stop_playback()
	var judged_count := maxf(1.0, float(_scored_note_count))
	var accuracy := (_weighted_accuracy / judged_count) * 100.0
	var notes_hit := _notes_hit_count()
	var notes_missed := _notes_missed_count()
	var full_combo := notes_missed == 0 and notes_hit > 0
	var all_perfect := full_combo \
		and int(_judgements.get("Great", 0)) == 0 \
		and int(_judgements.get("Good", 0)) == 0
	var result := {
		"score": _score,
		"max_combo": _max_combo,
		"perfect": _judgements["Perfect"],
		"great": _judgements["Great"],
		"good": _judgements["Good"],
		"miss": _judgements["Miss"],
		"notes_hit": notes_hit,
		"notes_missed": notes_missed,
		"total_notes_judged": notes_hit + notes_missed,
		"full_combo": full_combo,
		"all_perfect": all_perfect,
		"drive_chain": full_combo,
		"overdrive_sync": all_perfect,
		"song_failed": false,
		"accuracy": accuracy,
		"accuracy_text": "%.2f%%" % accuracy,
		"mode": _mode,
		"timing_feedback": _timing_feedback,
		"sustain_ticks": _hold_tick_count,
		"hold_successes": _hold_success_count,
		"hold_breaks": _hold_break_count,
		"play_time_seconds": _active_gameplay_seconds,
		"chart_hash": _runtime_chart_hash if not _runtime_chart_hash.is_empty() else ContentRegistry.get_chart_hash(_song, _difficulty, _mode),
		"chart_seed": _runtime_chart_seed,
		"scoring_events": [],
		"ranked": bool(_loadout.get("ranked", true)),
		"practice_forced_no_fail": bool(_loadout.get("practice_forced_no_fail", false)),
		"no_fail_active": _no_fail_modifier_active,
		"drive_meter_remaining": _drive_meter,
	}
	song_finished.emit(result)


func _on_viewport_resized() -> void:
	_apply_theme()
	_build_lane_backgrounds()
	_build_receptors()
	_layout_playfield()
	if _visualizer_mode:
		_configure_visualizer_presentation()
	call_deferred("_layout_playfield")
	if _visualizer_mode:
		call_deferred("_configure_visualizer_presentation")
	if _editor_live_mode and _is_paused:
		call_deferred("_rebuild_paused_editor_live_after_layout")


func _rebuild_paused_editor_live_after_layout() -> void:
	if _editor_live_mode and _is_paused:
		_rebuild_editor_live_notes(_current_chart_time())


func _unhandled_input(event: InputEvent) -> void:
	if _editor_live_mode:
		return
	if _visualizer_mode:
		if event.is_action_pressed("ui_cancel"):
			AudioSync.stop_playback()
			_finished = true
			game_exited.emit()
		return
	if _is_failed:
		return
	if event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_START:
		if _pause_overlay.visible:
			_on_resume_button_pressed()
		else:
			_on_pause_button_pressed()
		return
	if event.is_action_pressed("ui_cancel"):
		if _pause_overlay.visible:
			_on_resume_button_pressed()
		else:
			_on_pause_button_pressed()


func _approach_time() -> float:
	var speed_value: float = float(_loadout.get("speed_value", 1.0))
	var speed_type := "classic"
	var base_ms := 600.0
	if ProfileStore != null:
		speed_type = ProfileStore.get_note_speed_type()
		base_ms = ProfileStore.get_note_approach_time_ms()
	return NoteSpeedRules.resolved_approach_time(speed_type, base_ms, speed_value, _difficulty)


func _audio_start_chart_time() -> float:
	return 0.0


func _current_chart_time() -> float:
	if _editor_live_mode and _editor_live_adding_enabled:
		# Live charting authors source-audio timestamps. Player latency preferences
		# must not be baked into the chart itself.
		return AudioSync.get_song_time_raw()
	return AudioSync.get_adjusted_song_time()


func _y_position_for_time_until_hit(time_until_hit: float) -> float:
	var clamped: float = clampf(time_until_hit / _approach_time(), -0.5, 1.5)
	return _hit_line_y() + clamped * (_spawn_y() - _hit_line_y())


func _lane_color(lane: int) -> Color:
	var palette: Array = _theme_palette.get("lane_colors", HDTheme.LANE_COLORS)
	return palette[lane % palette.size()]


func _has_effect(effect_id: String) -> bool:
	return str(_loadout.get("effect", "effect_none")) == effect_id


func _has_modifier(modifier_id: String) -> bool:
	var enabled: Array = _loadout.get("enabled_modifiers", []) as Array
	if modifier_id == "modifier_no_fail" and bool(_loadout.get("forced_no_fail", false)):
		return true
	return enabled.has(modifier_id)


func _lane_for_note(note: Dictionary) -> int:
	if _editor_live_mode:
		return clampi(int(note.get("lane", 0)), 0, _lane_count - 1)
	var note_id: int = int(note.get("id", -1))
	var lane: int = int(_lane_overrides[note_id]) if _lane_overrides.has(note_id) else int(note.get("lane", 0))
	if _has_modifier("modifier_mirror"):
		lane = _lane_count - 1 - lane
	return clampi(lane, 0, _lane_count - 1)


func _seed_lane_overrides() -> void:
	_lane_overrides.clear()
	if _editor_live_mode:
		return
	if not _has_modifier("modifier_random_lane"):
		return
	var seed_source: int = hash(str(_song.get("id", "")) + "|" + _difficulty + "|" + _mode)
	for note in _notes:
		var note_id: int = int(note.get("id", -1))
		var base_lane: int = int(note.get("lane", 0))
		var offset: int = int(abs(seed_source + note_id * 31) % 3) - 1
		_lane_overrides[note_id] = clampi(base_lane + offset, 0, _lane_count - 1)


func _judgement_window_modifier_scale() -> float:
	return 0.84 if _has_modifier("modifier_precision") else 1.0


func _compute_score_multiplier() -> float:
	return ScoreModifierRules.score_multiplier_for_loadout(_loadout)


func _apply_glow_style(panel: PanelContainer, fill_color: Color, border_color: Color) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = fill_color * Color(1, 1, 1, 0.36)
	style.border_color = border_color * Color(1, 1, 1, 0.18)
	style.border_width_bottom = 1
	style.corner_radius_top_left = 18
	style.corner_radius_top_right = 18
	style.corner_radius_bottom_left = 18
	style.corner_radius_bottom_right = 18
	panel.add_theme_stylebox_override("panel", style)


func _take_particle() -> ColorRect:
	for dot in _particle_pool:
		if not dot.visible:
			return dot
	return null


func _take_actual_hit_particle() -> CPUParticles2D:
	for burst in _actual_hit_particle_pool:
		if burst != null and is_instance_valid(burst) and not burst.emitting:
			return burst
	return null


func _take_trail_ghost() -> ColorRect:
	for ghost in _trail_pool:
		if not ghost.visible:
			return ghost
	return null


func _release_particle(dot: ColorRect) -> void:
	dot.visible = false
	dot.scale = Vector2.ONE
	dot.modulate.a = 1.0


func _release_trail_ghost(ghost: ColorRect) -> void:
	ghost.visible = false
	ghost.scale = Vector2.ONE
	ghost.modulate.a = 1.0


func _make_hit_particle_texture() -> Texture2D:
	var tex_size := 32
	var img := Image.create(tex_size, tex_size, false, Image.FORMAT_RGBA8)
	var center := Vector2(float(tex_size - 1) * 0.5, float(tex_size - 1) * 0.5)
	var radius := float(tex_size) * 0.5
	for y in tex_size:
		for x in tex_size:
			var dist := Vector2(float(x), float(y)).distance_to(center) / radius
			var alpha := pow(clampf(1.0 - dist, 0.0, 1.0), 1.85)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(img)


func _make_hit_particle_color_ramp() -> Gradient:
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.18, 1.0])
	ramp.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 0.86),
		Color(1.0, 1.0, 1.0, 0.0),
	])
	return ramp


func _react_stage_fx(lane: int, judgement: String) -> void:
	var effect_strength := _hit_effects_strength()
	if effect_strength <= 0.0:
		return
	var intensity := 0.0
	match judgement:
		"Perfect":
			intensity = 1.0
		"Great":
			intensity = 0.74
		"Good":
			intensity = 0.48
		_:
			intensity = 0.0
	intensity *= effect_strength
	if intensity <= 0.0:
		return
	if _prioritize_fps:
		intensity *= 0.35
	if lane >= 0 and lane < _lane_flash_energy.size():
		var bloom_boost := 1.35 if _has_effect("effect_lane_bloom") and not _prioritize_fps else 1.0
		_lane_flash_energy[lane] = maxf(_lane_flash_energy[lane], intensity * bloom_boost)
	if _hit_effects_allow_side_bars() and not AppState.is_mobile_platform():
		var side_index := clampi(lane % SIDE_BAR_COUNT, 0, SIDE_BAR_COUNT - 1)
		var side_boost := 1.4 if _has_effect("effect_sidefire") and not _prioritize_fps else 0.85
		if _hit_effects_mode == "enhanced" and not _prioritize_fps:
			side_boost *= 1.18
		_left_side_energy[side_index] = maxf(_left_side_energy[side_index], intensity * side_boost)
		_right_side_energy[side_index] = maxf(_right_side_energy[side_index], intensity * side_boost)


func _update_runtime_fx(delta: float, song_time: float) -> void:
	_update_particle_pool(delta)
	_update_trail_pool(delta)
	_update_lane_fx(delta, song_time)
	_update_desktop_side_fx(delta, song_time)
	_update_screen_shake(delta)


func _update_particle_pool(delta: float) -> void:
	for index in range(_active_particles.size() - 1, -1, -1):
		var particle: Dictionary = _active_particles[index]
		var dot: ColorRect = particle["node"]
		var life: float = float(particle.get("life", 0.0)) - delta
		if life <= 0.0 or not is_instance_valid(dot):
			if is_instance_valid(dot):
				_release_particle(dot)
			_active_particles.remove_at(index)
			continue
		particle["life"] = life
		var velocity: Vector2 = particle.get("velocity", Vector2.ZERO)
		velocity.y += 220.0 * delta
		particle["velocity"] = velocity
		dot.position += velocity * delta
		var max_life := maxf(0.001, float(particle.get("max_life", life)))
		var life_ratio := life / max_life
		var shrink := float(particle.get("shrink", 0.65))
		var scale_value := lerpf(shrink, 1.0, life_ratio)
		dot.scale = Vector2.ONE * scale_value
		dot.modulate.a = life_ratio
		_active_particles[index] = particle


func _update_trail_pool(delta: float) -> void:
	for index in range(_active_trails.size() - 1, -1, -1):
		var trail: Dictionary = _active_trails[index]
		var ghost: ColorRect = trail["node"]
		var life: float = float(trail.get("life", 0.0)) - delta
		if life <= 0.0 or not is_instance_valid(ghost):
			if is_instance_valid(ghost):
				_release_trail_ghost(ghost)
			_active_trails.remove_at(index)
			continue
		trail["life"] = life
		var max_life := maxf(0.001, float(trail.get("max_life", life)))
		var life_ratio := life / max_life
		var shrink := float(trail.get("shrink", 0.82))
		ghost.scale = Vector2.ONE * lerpf(shrink, 1.0, life_ratio)
		ghost.modulate.a = life_ratio * 0.58
		_active_trails[index] = trail


func _update_lane_fx(delta: float, song_time: float) -> void:
	_runway_sheen_phase += delta * 1.6
	var shimmer_enabled := _has_effect("effect_shimmer") and not _prioritize_fps
	var decay_rate := 2.9 if not _prioritize_fps else 4.2
	for index in _lane_flash_nodes.size():
		_lane_flash_energy[index] = maxf(0.0, _lane_flash_energy[index] - delta * decay_rate)
		var flash: ColorRect = _lane_flash_nodes[index]
		if _chart_background_disabled:
			flash.visible = false
			continue
		var energy: float = float(_lane_flash_energy[index])
		flash.visible = energy > 0.01
		flash.modulate.a = energy * (0.26 if not _prioritize_fps else 0.12)
		if index < _runways.get_child_count():
			var runway: PanelContainer = _runways.get_child(index)
			var base_alpha: float = 0.92 + energy * 0.12
			if shimmer_enabled:
				base_alpha += sin(_runway_sheen_phase + float(index) * 0.7) * 0.05
			runway.modulate.a = clampf(base_alpha, 0.84, 1.0)
	if _theme_effects_enabled and not _prioritize_fps and not _chart_background_disabled:
		_top_glow.modulate.a = 0.92 + sin(song_time * 0.5) * 0.05
		_bottom_glow.modulate.a = 0.92 + sin(song_time * 0.5 + 1.2) * 0.05
	else:
		_top_glow.modulate.a = 0.0
		_bottom_glow.modulate.a = 0.0


func _update_desktop_side_fx(delta: float, song_time: float) -> void:
	if AppState.is_mobile_platform() or not _theme_effects_enabled or _prioritize_fps or _chart_background_disabled:
		for index in SIDE_BAR_COUNT:
			_left_side_energy[index] = 0.0
			_right_side_energy[index] = 0.0
			_desktop_left_bars[index].modulate.a = 0.0
			_desktop_right_bars[index].modulate.a = 0.0
		return
	for index in SIDE_BAR_COUNT:
		_left_side_energy[index] = maxf(0.0, _left_side_energy[index] - delta * 1.7)
		_right_side_energy[index] = maxf(0.0, _right_side_energy[index] - delta * 1.7)
		var left_bar := _desktop_left_bars[index]
		var right_bar := _desktop_right_bars[index]
		var ambient_pulse := 0.10 + sin(song_time * 1.4 + float(index) * 0.9) * 0.04
		left_bar.modulate.a = ambient_pulse + _left_side_energy[index] * 0.34
		right_bar.modulate.a = ambient_pulse + _right_side_energy[index] * 0.34
		left_bar.scale = Vector2(1.0, 1.0 + _left_side_energy[index] * 0.12)
		right_bar.scale = Vector2(1.0, 1.0 + _right_side_energy[index] * 0.12)


func _update_screen_shake(delta: float) -> void:
	var shake_offset := Vector2.ZERO
	if _screen_shake_timer > 0.0:
		_screen_shake_timer = maxf(0.0, _screen_shake_timer - delta)
		var decay := _screen_shake_timer / 0.10
		var strength := _screen_shake_strength * decay
		shake_offset = Vector2(randf_range(-strength, strength), randf_range(-strength, strength))
	else:
		_screen_shake_strength = 0.0
	_lane_flash_layer.position = shake_offset * 0.20
	_note_layer.position = shake_offset
	_fx_layer.position = shake_offset
