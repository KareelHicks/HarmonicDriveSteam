extends Control

const HDTheme = preload("res://scripts/ui/HDTheme.gd")
const GameModeConfig = preload("res://scripts/gameplay/GameModeConfig.gd")
const MenuNavigator = preload("res://scripts/ui/MenuNavigator.gd")
const SongJacketService = preload("res://scripts/ui/SongJacketService.gd")

const LEVEL_PARTICLE_COUNT := 22
const MULTIPLAYER_SYNC_TIMEOUT_SECONDS := 30.0
const XP_FILL_SEGMENT_SECONDS := 1.2
const XP_LEVEL_UP_SEGMENT_SECONDS := 0.9
const XP_TICK_INTERVAL_SECONDS := 0.05

const TAB_SUMMARY := "summary"
const TAB_DETAILS := "details"
const TAB_REWARDS := "rewards"
const TAB_MATCH := "match"

signal back_requested
signal replay_requested
signal leaderboard_requested(song_id: String, summary: Dictionary)

var _result: Dictionary = {}
var _xp_tween: Tween
var _particle_pool: Array[ColorRect] = []
var _active_particles: Array[Dictionary] = []
var _multiplayer_sync_deadline_ms: int = 0
var _multiplayer_sync_resolved := false
var _multiplayer_achievement_reported := false
var _xp_audio_player: AudioStreamPlayer
var _xp_tick_accumulator := 0.0
var _xp_animating := false
var _xp_display_ratio := 0.0
var _xp_display_value := 0
var _xp_display_needed := 1
var _menu_navigator: MenuNavigator
var _vibez_tween: Tween
var _stats_tween: Tween
var _results_backdrop: Control
var _shimmer_time := 0.0
var _card_styles: Array[StyleBoxFlat] = []
var _active_tab := TAB_SUMMARY
var _tab_buttons: Dictionary = {}
var _tab_panels: Dictionary = {}
var _leaderboard_summary: Dictionary = {}
var _rank_snapshot_request_id := 0

var _scrim: ColorRect
var _vignette: ColorRect
var _fx_layer: Control
var _ui_root: MarginContainer
var _root_vbox: VBoxContainer
var _top_panel: PanelContainer
var _source_badge: Label
var _song_title_label: Label
var _song_subtitle_label: Label
var _variant_label: Label
var _rank_status_label: Label
var _content_scroll: ScrollContainer
var _content_vbox: VBoxContainer
var _body_grid: GridContainer
var _hero_card: PanelContainer
var _jacket_hero: TextureRect
var _rank_label: Label
var _combo_badge_label: Label
var _score_label: Label
var _accuracy_label: Label
var _combo_label: Label
var _judgement_grid: GridContainer
var _perfect_card: PanelContainer
var _great_card: PanelContainer
var _good_card: PanelContainer
var _miss_card: PanelContainer
var _perfect_value: Label
var _great_value: Label
var _good_value: Label
var _miss_value: Label
var _hero_xp_delta_label: Label
var _hero_xp_level_label: Label
var _hero_xp_bar_label: Label
var _hero_xp_bar_frame: PanelContainer
var _hero_xp_bar_fill: ColorRect
var _hero_xp_bar_spark: ColorRect
var _tabs_card: PanelContainer
var _tabs_bar: HBoxContainer
var _tab_content: PanelContainer
var _summary_panel: VBoxContainer
var _summary_rank_label: Label
var _summary_best_label: Label
var _summary_source_label: Label
var _details_panel: VBoxContainer
var _details_judgement_label: Label
var _details_precision_label: Label
var _rewards_panel: VBoxContainer
var _xp_earned_label: Label
var _vibez_earned_label: Label
var _level_progress_label: Label
var _xp_bar_label: Label
var _xp_bar_frame: PanelContainer
var _xp_bar_fill: ColorRect
var _xp_bar_spark: ColorRect
var _unlock_label: Label
var _match_panel: VBoxContainer
var _match_card: HBoxContainer
var _match_you_label: Label
var _match_outcome_label: Label
var _match_opponent_label: Label
var _match_status_label: Label
var _action_bar: PanelContainer
var _replay_button: Button
var _leaderboard_button: Button
var _back_button: Button


func _ready() -> void:
	_scrim = %Scrim
	_vignette = %Vignette
	_fx_layer = %FXLayer
	_ui_root = %UIRoot
	_results_backdrop = %EMSResultsBackdrop
	_build_ui()
	_menu_navigator = MenuNavigator.install(self, Callable(self, "_on_back_button_pressed"))
	_apply_layout()
	get_viewport().size_changed.connect(_apply_layout)
	set_process_unhandled_input(true)
	%Background.color = Color(0.02, 0.03, 0.08, 1.0)
	_result = ProfileStore.get_last_result()
	_setup_xp_audio()
	_setup_ems_results_backdrop()
	_multiplayer_achievement_reported = false
	_populate_result()
	_ensure_particle_pool()
	call_deferred("_prepare_results_fx")
	_begin_multiplayer_sync_wait_if_needed()
	_begin_rank_snapshot()
	set_process(true)


func get_initial_menu_focus() -> Control:
	return _replay_button


func _build_ui() -> void:
	for child in _ui_root.get_children():
		child.queue_free()
	_tab_buttons.clear()
	_tab_panels.clear()

	_root_vbox = VBoxContainer.new()
	_root_vbox.name = "ResultsRoot"
	_root_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_root_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_ui_root.add_child(_root_vbox)

	_top_panel = PanelContainer.new()
	_top_panel.name = "TopIdentityPanel"
	_top_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_root_vbox.add_child(_top_panel)

	var top_margin := MarginContainer.new()
	top_margin.add_theme_constant_override("margin_left", 18)
	top_margin.add_theme_constant_override("margin_top", 14)
	top_margin.add_theme_constant_override("margin_right", 18)
	top_margin.add_theme_constant_override("margin_bottom", 14)
	_top_panel.add_child(top_margin)

	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 14)
	top_margin.add_child(top_row)

	_source_badge = Label.new()
	_source_badge.name = "SourceBadge"
	_source_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_source_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_source_badge.custom_minimum_size = Vector2(132, 44)
	top_row.add_child(_source_badge)

	var title_stack := VBoxContainer.new()
	title_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_stack.add_theme_constant_override("separation", 2)
	top_row.add_child(title_stack)

	_song_title_label = Label.new()
	_song_title_label.name = "SongTitleLabel"
	_song_title_label.clip_text = true
	_song_title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_stack.add_child(_song_title_label)

	_song_subtitle_label = Label.new()
	_song_subtitle_label.name = "SongSubtitleLabel"
	_song_subtitle_label.clip_text = true
	_song_subtitle_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_stack.add_child(_song_subtitle_label)

	_variant_label = Label.new()
	_variant_label.name = "VariantLabel"
	_variant_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_variant_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_variant_label.custom_minimum_size = Vector2(260, 0)
	top_row.add_child(_variant_label)

	_rank_status_label = Label.new()
	_rank_status_label.name = "RankStatusLabel"
	_rank_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_rank_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_rank_status_label.custom_minimum_size = Vector2(220, 0)
	top_row.add_child(_rank_status_label)

	_content_scroll = ScrollContainer.new()
	_content_scroll.name = "ContentScroll"
	_content_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_root_vbox.add_child(_content_scroll)

	_content_vbox = VBoxContainer.new()
	_content_vbox.name = "ContentVBox"
	_content_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_vbox.add_theme_constant_override("separation", 14)
	_content_scroll.add_child(_content_vbox)

	_body_grid = GridContainer.new()
	_body_grid.name = "BodyGrid"
	_body_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body_grid.add_theme_constant_override("h_separation", 14)
	_body_grid.add_theme_constant_override("v_separation", 14)
	_content_vbox.add_child(_body_grid)

	_build_hero_card()
	_build_tabs_card()
	_build_action_bar()


func _build_hero_card() -> void:
	_hero_card = PanelContainer.new()
	_hero_card.name = "HeroSummaryCard"
	_hero_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hero_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body_grid.add_child(_hero_card)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 18)
	_hero_card.add_child(margin)

	var hero_vbox := VBoxContainer.new()
	hero_vbox.add_theme_constant_override("separation", 14)
	hero_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(hero_vbox)

	var hero_top := HBoxContainer.new()
	hero_top.add_theme_constant_override("separation", 18)
	hero_top.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hero_vbox.add_child(hero_top)

	_jacket_hero = TextureRect.new()
	_jacket_hero.name = "JacketHero"
	_jacket_hero.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_jacket_hero.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_jacket_hero.custom_minimum_size = Vector2(230, 230)
	hero_top.add_child(_jacket_hero)

	var score_stack := VBoxContainer.new()
	score_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	score_stack.add_theme_constant_override("separation", 8)
	hero_top.add_child(score_stack)

	_rank_label = Label.new()
	_rank_label.name = "RankLabel"
	_rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	score_stack.add_child(_rank_label)

	_combo_badge_label = Label.new()
	_combo_badge_label.name = "ComboBadgeLabel"
	_combo_badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	score_stack.add_child(_combo_badge_label)

	_score_label = Label.new()
	_score_label.name = "ScoreLabel"
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	score_stack.add_child(_score_label)

	_accuracy_label = Label.new()
	_accuracy_label.name = "AccuracyLabel"
	_accuracy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	score_stack.add_child(_accuracy_label)

	_combo_label = Label.new()
	_combo_label.name = "ComboLabel"
	_combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	score_stack.add_child(_combo_label)

	_judgement_grid = GridContainer.new()
	_judgement_grid.name = "JudgementGrid"
	_judgement_grid.columns = 4
	_judgement_grid.add_theme_constant_override("h_separation", 10)
	_judgement_grid.add_theme_constant_override("v_separation", 10)
	_judgement_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hero_vbox.add_child(_judgement_grid)

	var perfect := _make_judgement_card("PERFECT")
	_perfect_card = perfect["card"]
	_perfect_value = perfect["value"]
	var great := _make_judgement_card("GREAT")
	_great_card = great["card"]
	_great_value = great["value"]
	var good := _make_judgement_card("GOOD")
	_good_card = good["card"]
	_good_value = good["value"]
	var miss := _make_judgement_card("MISS")
	_miss_card = miss["card"]
	_miss_value = miss["value"]

	var hero_xp_stack := VBoxContainer.new()
	hero_xp_stack.name = "HeroXPStack"
	hero_xp_stack.add_theme_constant_override("separation", 7)
	hero_xp_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hero_vbox.add_child(hero_xp_stack)

	var hero_xp_row := HBoxContainer.new()
	hero_xp_row.name = "HeroXPRewardsRow"
	hero_xp_row.add_theme_constant_override("separation", 10)
	hero_xp_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hero_xp_stack.add_child(hero_xp_row)
	_hero_xp_delta_label = _make_reward_label(hero_xp_row)
	_hero_xp_level_label = _make_reward_label(hero_xp_row)
	_hero_xp_bar_label = _make_info_label(hero_xp_stack, "DRIVE XP")
	var hero_meter := _make_xp_bar(hero_xp_stack, "HeroXPBar")
	_hero_xp_bar_frame = hero_meter["frame"]
	_hero_xp_bar_fill = hero_meter["fill"]
	_hero_xp_bar_spark = hero_meter["spark"]


func _make_judgement_card(title_text: String) -> Dictionary:
	var panel := PanelContainer.new()
	panel.name = "%sCard" % title_text.capitalize().replace(" ", "")
	panel.custom_minimum_size = Vector2(0, 74)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_judgement_grid.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 2)
	margin.add_child(stack)

	var title := Label.new()
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(title)

	var value := Label.new()
	value.text = "0"
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(value)
	return {"card": panel, "title": title, "value": value}


func _build_tabs_card() -> void:
	_tabs_card = PanelContainer.new()
	_tabs_card.name = "TabbedDetailsCard"
	_tabs_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body_grid.add_child(_tabs_card)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 16)
	_tabs_card.add_child(margin)

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 14)
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(stack)

	_tabs_bar = HBoxContainer.new()
	_tabs_bar.name = "TabButtons"
	_tabs_bar.add_theme_constant_override("separation", 8)
	_tabs_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_child(_tabs_bar)

	_add_tab_button(TAB_SUMMARY, "Summary")
	_add_tab_button(TAB_DETAILS, "Details")
	_add_tab_button(TAB_REWARDS, "Rewards")
	_add_tab_button(TAB_MATCH, "Match / Rankings")

	_tab_content = PanelContainer.new()
	_tab_content.name = "TabContent"
	_tab_content.custom_minimum_size = Vector2(0, 300)
	_tab_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(_tab_content)

	var content_margin := MarginContainer.new()
	content_margin.add_theme_constant_override("margin_left", 16)
	content_margin.add_theme_constant_override("margin_top", 14)
	content_margin.add_theme_constant_override("margin_right", 16)
	content_margin.add_theme_constant_override("margin_bottom", 14)
	_tab_content.add_child(content_margin)

	var content_root := Control.new()
	content_root.name = "TabContentRoot"
	content_root.custom_minimum_size = Vector2(0, 280)
	content_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_margin.add_child(content_root)

	_summary_panel = _make_tab_panel("SummaryPanel", content_root)
	_summary_rank_label = _make_info_label(_summary_panel, "Loading rank")
	_summary_best_label = _make_info_label(_summary_panel, "")
	_summary_source_label = _make_info_label(_summary_panel, "")

	_details_panel = _make_tab_panel("DetailsPanel", content_root)
	_details_judgement_label = _make_info_label(_details_panel, "")
	_details_precision_label = _make_info_label(_details_panel, "")

	_rewards_panel = _make_tab_panel("RewardsPanel", content_root)
	var rewards_row := HBoxContainer.new()
	rewards_row.add_theme_constant_override("separation", 10)
	rewards_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rewards_panel.add_child(rewards_row)
	_xp_earned_label = _make_reward_label(rewards_row)
	_vibez_earned_label = _make_reward_label(rewards_row)
	_level_progress_label = _make_reward_label(rewards_row)
	_xp_bar_label = _make_info_label(_rewards_panel, "XP")
	var rewards_meter := _make_xp_bar(_rewards_panel, "XPBar")
	_xp_bar_frame = rewards_meter["frame"]
	_xp_bar_fill = rewards_meter["fill"]
	_xp_bar_spark = rewards_meter["spark"]
	_unlock_label = _make_info_label(_rewards_panel, "")

	_match_panel = _make_tab_panel("MatchPanel", content_root)
	_match_card = HBoxContainer.new()
	_match_card.name = "MatchCard"
	_match_card.add_theme_constant_override("separation", 10)
	_match_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_match_panel.add_child(_match_card)
	_match_you_label = _make_match_label(_match_card, HORIZONTAL_ALIGNMENT_LEFT)
	_match_outcome_label = _make_match_label(_match_card, HORIZONTAL_ALIGNMENT_CENTER)
	_match_opponent_label = _make_match_label(_match_card, HORIZONTAL_ALIGNMENT_RIGHT)
	_match_status_label = _make_info_label(_match_panel, "")

	_tab_panels = {
		TAB_SUMMARY: _summary_panel,
		TAB_DETAILS: _details_panel,
		TAB_REWARDS: _rewards_panel,
		TAB_MATCH: _match_panel,
	}
	_set_tab(TAB_SUMMARY)


func _add_tab_button(tab_id: String, text: String) -> void:
	var button := Button.new()
	button.name = "%sTabButton" % tab_id.capitalize().replace(" ", "")
	button.text = text
	button.toggle_mode = true
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(Callable(self, "_set_tab").bind(tab_id))
	_tabs_bar.add_child(button)
	_tab_buttons[tab_id] = button


func _make_tab_panel(panel_name: String, parent: Control) -> VBoxContainer:
	var panel := VBoxContainer.new()
	panel.name = panel_name
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_constant_override("separation", 10)
	parent.add_child(panel)
	return panel


func _make_info_label(parent: Control, text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label


func _make_reward_label(parent: Control) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label


func _make_xp_bar(parent: Control, base_name: String) -> Dictionary:
	var frame := PanelContainer.new()
	frame.name = "%sFrame" % base_name
	frame.custom_minimum_size = Vector2(0, 24)
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(frame)

	var clip := Control.new()
	clip.name = "%sFillClip" % base_name
	clip.clip_contents = true
	clip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clip.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_child(clip)

	var fill := ColorRect.new()
	fill.name = "%sFill" % base_name
	fill.anchor_left = 0.0
	fill.anchor_top = 0.0
	fill.anchor_right = 0.0
	fill.anchor_bottom = 1.0
	fill.offset_left = 0.0
	fill.offset_top = 0.0
	fill.offset_right = 0.0
	fill.offset_bottom = 0.0
	clip.add_child(fill)

	var spark := ColorRect.new()
	spark.name = "%sLeadSpark" % base_name
	spark.anchor_left = 0.0
	spark.anchor_top = 0.0
	spark.anchor_right = 0.0
	spark.anchor_bottom = 1.0
	spark.offset_left = 0.0
	spark.offset_top = 0.0
	spark.offset_right = 4.0
	spark.offset_bottom = 0.0
	spark.visible = false
	clip.add_child(spark)

	return {"frame": frame, "fill": fill, "spark": spark}


func _make_match_label(parent: Control, alignment: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.horizontal_alignment = alignment
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label


func _build_action_bar() -> void:
	_action_bar = PanelContainer.new()
	_action_bar.name = "ActionBar"
	_action_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_root_vbox.add_child(_action_bar)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 12)
	_action_bar.add_child(margin)

	var row := HBoxContainer.new()
	row.name = "ActionButtons"
	row.add_theme_constant_override("separation", 12)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(row)

	_replay_button = Button.new()
	_replay_button.name = "ReplayButton"
	_replay_button.text = "REPLAY"
	_replay_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_replay_button.pressed.connect(_on_replay_button_pressed)
	row.add_child(_replay_button)

	_leaderboard_button = Button.new()
	_leaderboard_button.name = "LeaderboardButton"
	_leaderboard_button.text = "VIEW LEADERBOARD"
	_leaderboard_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_leaderboard_button.pressed.connect(_on_leaderboard_button_pressed)
	row.add_child(_leaderboard_button)

	_back_button = Button.new()
	_back_button.name = "BackActionButton"
	_back_button.text = "SONG SELECT"
	_back_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_back_button.pressed.connect(_on_back_button_pressed)
	row.add_child(_back_button)


func _set_tab(tab_id: String) -> void:
	if not _tab_panels.has(tab_id):
		tab_id = TAB_SUMMARY
	_active_tab = tab_id
	for key in _tab_panels.keys():
		var panel := _tab_panels[key] as Control
		panel.visible = str(key) == tab_id
	for key in _tab_buttons.keys():
		var button := _tab_buttons[key] as Button
		var active := str(key) == tab_id
		button.set_pressed_no_signal(active)
		button.add_theme_stylebox_override("normal", HDTheme.button_style(active))
		button.add_theme_stylebox_override("hover", HDTheme.button_style(active))
		button.add_theme_stylebox_override("pressed", HDTheme.button_style(true))
		button.add_theme_stylebox_override("focus", HDTheme.button_style(active))
	call_deferred("_refresh_xp_bar_visuals")
	call_deferred("_refresh_menu_navigation")


func _refresh_menu_navigation() -> void:
	if _menu_navigator != null:
		_menu_navigator.refresh_focusables()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event: InputEventKey = event
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_SPACE:
			accept_event()
			return


func _apply_layout() -> void:
	var size := get_viewport_rect().size
	var compact := size.x < 960.0
	_ui_root.add_theme_constant_override("margin_left", 18 if compact else 40)
	_ui_root.add_theme_constant_override("margin_top", 18 if compact else 32)
	_ui_root.add_theme_constant_override("margin_right", 18 if compact else 40)
	_ui_root.add_theme_constant_override("margin_bottom", 18 if compact else 28)
	_root_vbox.add_theme_constant_override("separation", 12 if compact else 16)
	_body_grid.columns = 1 if compact else 2
	_judgement_grid.columns = 2 if compact else 4
	_tab_content.custom_minimum_size.y = 260 if compact else 300
	_scrim.color = Color(0.0, 0.0, 0.0, 0.42 if compact else 0.34)
	_vignette.color = Color(0.01, 0.01, 0.04, 0.30)

	_style_panel(_top_panel, 0.54)
	_style_panel(_hero_card, 0.56)
	_style_panel(_tabs_card, 0.56)
	_style_panel(_tab_content, 0.36, false)
	_style_panel(_action_bar, 0.58)
	_apply_badge_style(_source_badge)
	_apply_stat_card_styles()
	_apply_xp_bar_style()

	HDTheme.apply_label(_source_badge, "caption", HDTheme.CYAN, true)
	HDTheme.apply_label(_song_title_label, "section_title", HDTheme.primary_text(), false)
	HDTheme.apply_label(_song_subtitle_label, "caption", HDTheme.SECONDARY, false)
	HDTheme.apply_label(_variant_label, "caption", HDTheme.SECONDARY, false)
	HDTheme.apply_label(_rank_status_label, "caption", HDTheme.CYAN, false)
	HDTheme.apply_label(_rank_label, "hero_title", _rank_color(), false)
	HDTheme.apply_label(_combo_badge_label, "body", HDTheme.CYAN, false)
	HDTheme.apply_label(_score_label, "screen_title", HDTheme.primary_text(), false)
	HDTheme.apply_label(_accuracy_label, "body", HDTheme.SECONDARY, false)
	HDTheme.apply_label(_combo_label, "supporting", HDTheme.TERTIARY, false)
	for label in [_summary_rank_label, _summary_best_label, _summary_source_label, _details_judgement_label, _details_precision_label, _hero_xp_bar_label, _xp_bar_label, _unlock_label, _match_status_label]:
		HDTheme.apply_label(label, "body", HDTheme.SECONDARY, false)
	for label in [_hero_xp_delta_label, _hero_xp_level_label, _xp_earned_label, _vibez_earned_label, _level_progress_label, _match_you_label, _match_outcome_label, _match_opponent_label]:
		HDTheme.apply_label(label, "body", HDTheme.CYAN, true)
	for button in [_replay_button, _leaderboard_button, _back_button]:
		button.custom_minimum_size = Vector2(0, 58 if compact else 64)
		button.add_theme_font_size_override("font_size", HDTheme.text_size("button_secondary", size))
		button.add_theme_stylebox_override("normal", HDTheme.button_style(button == _replay_button))
		button.add_theme_stylebox_override("hover", HDTheme.button_style(button == _replay_button))
		button.add_theme_stylebox_override("pressed", HDTheme.button_style(true))
	for key in _tab_buttons.keys():
		var tab_button := _tab_buttons[key] as Button
		tab_button.custom_minimum_size = Vector2(0, 44)
		tab_button.add_theme_font_size_override("font_size", HDTheme.text_size("caption", size))
	_set_tab(_active_tab)
	_jacket_hero.custom_minimum_size = Vector2(170, 170) if compact else Vector2(230, 230)
	_content_scroll.scroll_vertical = 0


func _style_panel(panel: PanelContainer, alpha: float, major: bool = true) -> void:
	if panel == null:
		return
	var style := HDTheme.overlay_panel_style() if major else HDTheme.card_style()
	style.bg_color.a = alpha
	style.border_color.a = minf(style.border_color.a, 0.42)
	panel.add_theme_stylebox_override("panel", style)


func _apply_badge_style(label: Label) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = HDTheme.CYAN * Color(1, 1, 1, 0.13)
	style.border_color = HDTheme.CYAN * Color(1, 1, 1, 0.38)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	label.add_theme_stylebox_override("normal", style)


func _apply_xp_bar_style() -> void:
	var xp_frame_style := StyleBoxFlat.new()
	xp_frame_style.bg_color = HDTheme.CARD_FILL.lerp(Color.BLACK, 0.22)
	xp_frame_style.border_color = HDTheme.CYAN * Color(1, 1, 1, 0.28)
	xp_frame_style.border_width_left = 1
	xp_frame_style.border_width_top = 1
	xp_frame_style.border_width_right = 1
	xp_frame_style.border_width_bottom = 1
	xp_frame_style.corner_radius_top_left = 12
	xp_frame_style.corner_radius_top_right = 12
	xp_frame_style.corner_radius_bottom_left = 12
	xp_frame_style.corner_radius_bottom_right = 12
	_style_xp_meter(_hero_xp_bar_frame, _hero_xp_bar_fill, _hero_xp_bar_spark, xp_frame_style)
	_style_xp_meter(_xp_bar_frame, _xp_bar_fill, _xp_bar_spark, xp_frame_style)
	call_deferred("_refresh_xp_bar_visuals")


func _style_xp_meter(frame: PanelContainer, fill: ColorRect, spark: ColorRect, frame_style: StyleBoxFlat) -> void:
	if frame == null or fill == null or spark == null:
		return
	frame.add_theme_stylebox_override("panel", frame_style.duplicate())
	fill.color = _xp_fill_color()
	spark.color = Color.WHITE.lerp(_xp_fill_color(), 0.25)


func _populate_result() -> void:
	var song := _song_entry()
	_jacket_hero.texture = SongJacketService.texture_for_song(song)
	_song_title_label.text = _song_display_name()
	_song_subtitle_label.text = _song_subtitle()
	_source_badge.text = _source_label().to_upper()
	var mode_id := str(_result.get("mode", AppState.current_mode))
	_variant_label.text = "%s / %s / %s" % [
		str(_result.get("difficulty", AppState.current_difficulty)).to_upper(),
		GameModeConfig.get_short_label(mode_id).to_upper(),
		"RANKED" if bool(_result.get("ranked", true)) else "UNRANKED",
	]
	_score_label.text = "%d" % int(_result.get("score", 0))
	_accuracy_label.text = "ACCURACY %s" % str(_result.get("accuracy_text", _accuracy_text()))
	_apply_rank_and_badges()
	_apply_combo_highlight()
	_apply_stat_cards()
	_apply_rewards_labels()
	_apply_unlock_label()
	_apply_details_labels()
	_apply_route_actions()
	var multiplayer_service := _multiplayer_service()
	_refresh_multiplayer_outcome(multiplayer_service.call("get_current_round_snapshot") if multiplayer_service != null and multiplayer_service.has_method("get_current_round_snapshot") else {})


func _song_entry() -> Dictionary:
	var song := AppState.current_song.duplicate(true)
	if song.is_empty():
		song["id"] = str(_result.get("song_id", ""))
		song["display_name"] = str(_result.get("song_display_name", "Track"))
		song["artist"] = str(_result.get("song_artist", ""))
		song["charter"] = str(_result.get("chart_author", ""))
	return song


func _song_display_name() -> String:
	var from_result := str(_result.get("song_display_name", "")).strip_edges()
	if not from_result.is_empty():
		return from_result
	var song := _song_entry()
	return str(song.get("display_name", song.get("title", "Track")))


func _song_subtitle() -> String:
	var song := _song_entry()
	var parts: Array[String] = []
	var artist := str(_result.get("song_artist", song.get("artist", ""))).strip_edges()
	var charter := str(_result.get("chart_author", song.get("charter", ""))).strip_edges()
	if not artist.is_empty():
		parts.append(artist)
	if not charter.is_empty():
		parts.append("Chart by %s" % charter)
	if parts.is_empty():
		parts.append("Harmonic Drive")
	return "  |  ".join(parts)


func _source_type() -> String:
	var source := str(_result.get("source_type", "")).strip_edges().to_lower()
	if not source.is_empty():
		return source
	var song := _song_entry()
	source = str(song.get("source_type", song.get("source", ""))).strip_edges().to_lower()
	if not source.is_empty():
		return source
	var root_path := str(song.get("root_path", "")).strip_edges().to_lower()
	if root_path.begins_with("user://workshop"):
		return "workshop"
	if root_path.begins_with("user://custom_songs"):
		return "custom"
	return "official"


func _source_label() -> String:
	var label := str(_result.get("source_label", "")).strip_edges()
	if not label.is_empty():
		return label
	match _source_type():
		"workshop":
			return "Community"
		"custom":
			return "Local"
		_:
			return "Official"


func _route_label() -> String:
	if bool(_result.get("multiplayer", false)):
		return "MULTIPLAYER"
	match str(_result.get("return_route", "")).strip_edges().to_lower():
		"community_charts":
			return "COMMUNITY CHARTS"
		"local_songs":
			return "LOCAL SONGS"
		"song_select":
			return "SONG SELECT"
	match _source_type():
		"workshop":
			return "COMMUNITY CHARTS"
		"custom":
			return "LOCAL SONGS"
		_:
			return "SONG SELECT"


func _apply_route_actions() -> void:
	_back_button.text = _route_label()
	var ranked := bool(_result.get("ranked", true))
	var multiplayer := bool(_result.get("multiplayer", false))
	_leaderboard_button.visible = ranked and not multiplayer and not _song_id().is_empty()
	_leaderboard_button.disabled = not _leaderboard_button.visible


func _song_id() -> String:
	var id := str(_result.get("song_id", "")).strip_edges()
	if not id.is_empty():
		return id
	return str(_song_entry().get("id", "")).strip_edges()


func _accuracy_text() -> String:
	return "%.2f%%" % _accuracy_value()


func _accuracy_value() -> float:
	if _result.has("accuracy"):
		return float(_result.get("accuracy", 0.0))
	var text := str(_result.get("accuracy_text", "0.00%")).replace("%", "")
	return float(text) if text.is_valid_float() else 0.0


func _rank_for_accuracy(accuracy: float) -> String:
	if accuracy >= 95.0:
		return "S"
	if accuracy >= 90.0:
		return "A"
	if accuracy >= 80.0:
		return "B"
	if accuracy >= 70.0:
		return "C"
	return "D"


func _rank_color() -> Color:
	var col := HDTheme.CYAN
	if ProfileStore != null and ProfileStore.are_theme_effects_enabled() and EmotionalMotionSystem != null:
		col = EmotionalMotionSystem.pick_color("rank", int(round(_accuracy_value() * 10.0)))
	return col.lerp(Color.WHITE, 0.15)


func _apply_rank_and_badges() -> void:
	var accuracy := _accuracy_value()
	var rank := _rank_for_accuracy(accuracy)
	_rank_label.text = rank
	_rank_label.add_theme_color_override("font_color", _rank_color())
	var combo_achievement_text := _combo_achievement_text()
	if not combo_achievement_text.is_empty():
		_combo_badge_label.text = combo_achievement_text
	else:
		_combo_badge_label.text = "CLEAR"
	if is_instance_valid(_stats_tween):
		_stats_tween.kill()
	_stats_tween = create_tween()
	_rank_label.scale = Vector2.ONE * 0.85
	_rank_label.modulate.a = 0.0
	_stats_tween.tween_property(_rank_label, "modulate:a", 1.0, 0.18)
	_stats_tween.tween_property(_rank_label, "scale", Vector2.ONE * 1.05, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_stats_tween.tween_property(_rank_label, "scale", Vector2.ONE, 0.20).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_stats_tween.tween_callback(
		func() -> void:
			if _results_backdrop != null and _results_backdrop.visible and _results_backdrop.has_method("trigger_results_impulse"):
				_results_backdrop.call("trigger_results_impulse", "results_rank_reveal", 0.65, 0.22)
	)


func _combo_achievement_text() -> String:
	if _is_all_perfect_result():
		return "Overdrive Sync (AP)"
	if _is_full_combo_result():
		return "Drive Chain (FC)"
	return ""


func _is_full_combo_result() -> bool:
	if bool(_result.get("full_combo", _result.get("drive_chain", false))):
		return true
	var notes_hit := int(_result.get("notes_hit", int(_result.get("perfect", 0)) + int(_result.get("great", 0)) + int(_result.get("good", 0)) + int(_result.get("hold_successes", 0))))
	var notes_missed := int(_result.get("notes_missed", int(_result.get("miss", 0)) + int(_result.get("hold_breaks", 0))))
	return notes_hit > 0 and notes_missed == 0


func _is_all_perfect_result() -> bool:
	if bool(_result.get("all_perfect", _result.get("overdrive_sync", false))):
		return true
	if not _is_full_combo_result():
		return false
	return int(_result.get("great", 0)) == 0 and int(_result.get("good", 0)) == 0


func _apply_combo_highlight() -> void:
	var max_combo := int(_result.get("max_combo", 0))
	_combo_label.text = "FLOW STATE x%d" % max_combo if max_combo > 0 else "FLOW STATE -"
	var tw := create_tween()
	_combo_label.scale = Vector2.ONE
	tw.tween_property(_combo_label, "scale", Vector2.ONE * 1.03, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(_combo_label, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void:
		if _results_backdrop != null and _results_backdrop.visible and _results_backdrop.has_method("trigger_results_impulse"):
			_results_backdrop.call("trigger_results_impulse", "results_combo", 0.45, 0.52)
	)


func _apply_stat_cards() -> void:
	_perfect_value.text = str(int(_result.get("perfect", 0)))
	_great_value.text = str(int(_result.get("great", 0)))
	_good_value.text = str(int(_result.get("good", 0)))
	_miss_value.text = str(int(_result.get("miss", 0)))


func _apply_stat_card_styles() -> void:
	_card_styles.clear()
	var cards := [_perfect_card, _great_card, _good_card, _miss_card]
	for card in cards:
		if card == null:
			continue
		var frame_style := StyleBoxFlat.new()
		frame_style.bg_color = HDTheme.CARD_FILL.lerp(Color.BLACK, 0.18)
		frame_style.border_color = HDTheme.CYAN * Color(1, 1, 1, 0.28)
		frame_style.border_width_left = 1
		frame_style.border_width_top = 1
		frame_style.border_width_right = 1
		frame_style.border_width_bottom = 1
		frame_style.corner_radius_top_left = 10
		frame_style.corner_radius_top_right = 10
		frame_style.corner_radius_bottom_left = 10
		frame_style.corner_radius_bottom_right = 10
		_card_styles.append(frame_style)
		(card as PanelContainer).add_theme_stylebox_override("panel", frame_style)
	for panel in cards:
		if panel == null:
			continue
		var stack := (panel as PanelContainer).get_child(0).get_child(0) as VBoxContainer
		if stack == null:
			continue
		if stack.get_child_count() >= 2:
			HDTheme.apply_label(stack.get_child(0) as Label, "caption", HDTheme.TERTIARY, true)
			HDTheme.apply_label(stack.get_child(1) as Label, "supporting", HDTheme.primary_text(), true)


func _update_stat_card_shimmer() -> void:
	if _card_styles.is_empty():
		return
	if ProfileStore == null or not ProfileStore.are_theme_effects_enabled():
		return
	var base := 0.22
	var pulse := sin(_shimmer_time * 0.65) * 0.5 + 0.5
	var a := clampf(base + pulse * 0.10, 0.12, 0.40)
	for style in _card_styles:
		if style == null:
			continue
		var c := style.border_color
		c.a = a
		style.border_color = c


func _apply_rewards_labels() -> void:
	var xp_earned := int(_result.get("xp_earned", 0))
	var level_text := "LEVEL %d -> %d" % [
		int(_result.get("level_before", ProgressionManager.get_level())),
		int(_result.get("level_after", ProgressionManager.get_level())),
	]
	_xp_earned_label.text = "XP +%d" % xp_earned
	_vibez_earned_label.text = "VIBEZ +%d" % int(_result.get("currency_earned", 0))
	_level_progress_label.text = level_text
	_hero_xp_delta_label.text = "XP +%d" % xp_earned
	_hero_xp_level_label.text = level_text


func _apply_unlock_label() -> void:
	var unlock_text := ""
	var section_unlocked: Dictionary = _result.get("section_unlocked", {}) as Dictionary
	if not section_unlocked.is_empty():
		unlock_text = "%s SECTION REACHED" % ProgressionManager.get_section_display_name(int(section_unlocked.get("id", 0)))
	_unlock_label.text = unlock_text if not unlock_text.is_empty() else "No new progression milestones this run."
	_unlock_label.visible = true


func _apply_details_labels() -> void:
	_details_judgement_label.text = "Perfect %d   Great %d   Good %d   Miss %d" % [
		int(_result.get("perfect", 0)),
		int(_result.get("great", 0)),
		int(_result.get("good", 0)),
		int(_result.get("miss", 0)),
	]
	var parts: Array[String] = [
		"Max combo %d" % int(_result.get("max_combo", 0)),
		"Notes hit %d / missed %d" % [
			int(_result.get("notes_hit", int(_result.get("perfect", 0)) + int(_result.get("great", 0)) + int(_result.get("good", 0)) + int(_result.get("hold_successes", 0)))),
			int(_result.get("notes_missed", int(_result.get("miss", 0)) + int(_result.get("hold_breaks", 0)))),
		],
		"Score %d" % int(_result.get("score", 0)),
		"Accuracy %s" % str(_result.get("accuracy_text", _accuracy_text())),
	]
	if int(_result.get("hold_successes", 0)) > 0 or int(_result.get("hold_breaks", 0)) > 0:
		parts.append("Holds %d / breaks %d" % [int(_result.get("hold_successes", 0)), int(_result.get("hold_breaks", 0))])
	if int(_result.get("sustain_ticks", 0)) > 0:
		parts.append("Sustain ticks %d" % int(_result.get("sustain_ticks", 0)))
	_details_precision_label.text = "\n".join(parts)
	_summary_best_label.text = _best_delta_text()
	_summary_source_label.text = "%s chart | %s" % [_source_label(), _song_subtitle()]


func _best_delta_text() -> String:
	var previous := int(_result.get("previous_local_best_score", 0))
	var score := int(_result.get("score", 0))
	if previous <= 0:
		return "First recorded score for this chart."
	if score > previous:
		return "New best +%d over previous %d." % [score - previous, previous]
	if score == previous:
		return "Matched previous best %d." % previous
	return "Previous best %d remains ahead by %d." % [previous, previous - score]


func _xp_fill_color() -> Color:
	if ProfileStore != null and ProfileStore.are_theme_effects_enabled() and EmotionalMotionSystem != null:
		return EmotionalMotionSystem.pick_color("xp_fill", 1).lerp(Color.WHITE, 0.10)
	return HDTheme.CYAN.lerp(Color.WHITE, 0.12)


func _setup_ems_results_backdrop() -> void:
	var theme_on := ProfileStore != null and ProfileStore.are_theme_effects_enabled()
	if _results_backdrop == null:
		return
	_results_backdrop.visible = theme_on
	_results_backdrop.set_process(theme_on)
	if theme_on and _results_backdrop.has_method("set_results_context"):
		if EmotionalMotionSystem != null:
			EmotionalMotionSystem.configure_from_profile()
			EmotionalMotionSystem.reseed_run_palette()
		_results_backdrop.call("set_results_context", _result)


func _on_back_button_pressed() -> void:
	if _is_waiting_for_multiplayer_sync():
		return
	back_requested.emit()


func _on_replay_button_pressed() -> void:
	if _is_waiting_for_multiplayer_sync():
		return
	replay_requested.emit()


func _on_leaderboard_button_pressed() -> void:
	if _song_id().is_empty() or _leaderboard_button.disabled:
		return
	var summary := _leaderboard_summary.duplicate(true)
	summary["songID"] = _song_id()
	summary["song_title"] = _song_display_name()
	summary["artist"] = str(_result.get("song_artist", _song_entry().get("artist", "")))
	summary["difficulty"] = str(_result.get("difficulty", AppState.current_difficulty))
	summary["mode"] = str(_result.get("mode", AppState.current_mode))
	leaderboard_requested.emit(_song_id(), summary)


func _process(delta: float) -> void:
	_shimmer_time += delta
	_update_particles(delta)
	_update_multiplayer_sync_state()
	_update_xp_audio(delta)
	_update_stat_card_shimmer()


func _xp_ratio_before() -> float:
	var needed: float = maxf(1.0, float(_result.get("xp_needed_before", 1)))
	return clampf(float(_result.get("xp_before", 0)) / needed, 0.0, 1.0)


func _xp_ratio_after() -> float:
	var needed: float = maxf(1.0, float(_result.get("xp_needed_after", 1)))
	return clampf(float(_result.get("xp_after", 0)) / needed, 0.0, 1.0)


func _prepare_results_fx() -> void:
	await get_tree().process_frame
	_update_xp_bar_state(
		_xp_ratio_before(),
		int(_result.get("xp_before", 0)),
		int(_result.get("xp_needed_before", 1))
	)
	call_deferred("_animate_results_fx")
	_content_scroll.scroll_vertical = 0


func _update_xp_bar_state(ratio: float, xp_value: int, xp_needed: int) -> void:
	_xp_display_ratio = clampf(ratio, 0.0, 1.0)
	_xp_display_value = maxi(0, xp_value)
	_xp_display_needed = maxi(1, xp_needed)
	var xp_text := "DRIVE XP %d / %d" % [_xp_display_value, _xp_display_needed]
	_xp_bar_label.text = xp_text
	_hero_xp_bar_label.text = xp_text
	_refresh_xp_bar_visuals()


func _refresh_xp_bar_visuals() -> void:
	_apply_xp_fill_to_meter(_hero_xp_bar_frame, _hero_xp_bar_fill, _hero_xp_bar_spark, _xp_display_ratio)
	_apply_xp_fill_to_meter(_xp_bar_frame, _xp_bar_fill, _xp_bar_spark, _xp_display_ratio)


func _apply_xp_fill_to_meter(frame: PanelContainer, fill: ColorRect, spark: ColorRect, ratio: float) -> void:
	if frame == null or fill == null or spark == null:
		return
	var clip := fill.get_parent() as Control
	if clip == null:
		return
	var width := maxf(0.0, clip.size.x)
	if width <= 0.0:
		return
	var fill_width := clampf(ratio, 0.0, 1.0) * width
	fill.offset_left = 0.0
	fill.offset_top = 0.0
	fill.offset_right = fill_width
	fill.offset_bottom = 0.0
	spark.visible = _xp_animating and fill_width > 2.0
	spark.offset_left = clampf(fill_width - 4.0, 0.0, maxf(0.0, width - 4.0))
	spark.offset_right = spark.offset_left + 4.0


func _animate_results_fx() -> void:
	if is_instance_valid(_xp_tween):
		_xp_tween.kill()
	_xp_tween = create_tween()
	var ratio_before: float = _xp_ratio_before()
	var ratio_after: float = _xp_ratio_after()
	var level_before: int = int(_result.get("level_before", 1))
	var level_after: int = int(_result.get("level_after", level_before))
	var xp_before: int = int(_result.get("xp_before", 0))
	var xp_after: int = int(_result.get("xp_after", 0))
	var xp_needed_before: int = int(_result.get("xp_needed_before", 1))
	var xp_needed_after: int = int(_result.get("xp_needed_after", 1))
	var xp_earned: int = int(_result.get("xp_earned", 0))
	var play_xp_ticks: bool = xp_earned > 0
	_set_xp_animating(play_xp_ticks)
	if int(_result.get("currency_earned", 0)) > 0:
		_begin_vibez_animation()
	_xp_tween.tween_method(func(value: float) -> void:
		var current_xp: int = int(round(lerpf(float(xp_before), float(xp_needed_before), value)))
		_update_xp_bar_state(value, current_xp, xp_needed_before)
	, ratio_before, (1.0 if level_after > level_before else ratio_after), XP_FILL_SEGMENT_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if level_after > level_before:
		_xp_tween.tween_callback(func() -> void:
			_pulse_xp_meters()
			_spawn_level_up_particles()
			if _results_backdrop != null and _results_backdrop.visible and _results_backdrop.has_method("trigger_results_impulse"):
				_results_backdrop.call("trigger_results_impulse", "results_level_up", 0.75, 0.68)
		)
		_xp_tween.tween_method(func(value: float) -> void:
			var current_xp: int = int(round(lerpf(0.0, float(xp_after), value)))
			_update_xp_bar_state(value, current_xp, xp_needed_after)
		, 0.0, ratio_after, XP_LEVEL_UP_SEGMENT_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		_xp_tween.tween_callback(func() -> void:
			_update_xp_bar_state(ratio_after, xp_after, xp_needed_after)
		)
	_xp_tween.tween_callback(func() -> void:
		_set_xp_animating(false)
		_refresh_xp_bar_visuals()
	)


func _pulse_xp_meters() -> void:
	for meter in [_hero_xp_bar_frame, _xp_bar_frame]:
		var frame := meter as PanelContainer
		if frame == null:
			continue
		var tw := create_tween()
		frame.modulate = Color.WHITE
		tw.tween_property(frame, "modulate", Color(1.25, 1.45, 1.55, 1.0), 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(frame, "modulate", Color.WHITE, 0.28).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _begin_vibez_animation() -> void:
	if is_instance_valid(_vibez_tween):
		_vibez_tween.kill()
	_vibez_tween = create_tween()
	var earned := int(_result.get("currency_earned", 0))
	_vibez_tween.tween_method(func(v: float) -> void:
		_vibez_earned_label.text = "VIBEZ +%d" % int(round(v))
	, 0.0, float(earned), 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _ensure_particle_pool() -> void:
	if not _particle_pool.is_empty():
		return
	for _index in LEVEL_PARTICLE_COUNT:
		var dot := ColorRect.new()
		dot.visible = false
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fx_layer.add_child(dot)
		_particle_pool.append(dot)


func _take_particle() -> ColorRect:
	for dot in _particle_pool:
		if not dot.visible:
			return dot
	return null


func _spawn_level_up_particles() -> void:
	var particle_frame := _hero_xp_bar_frame if _hero_xp_bar_frame != null and _hero_xp_bar_frame.size.x > 0.0 else _xp_bar_frame
	var origin: Vector2 = particle_frame.global_position + Vector2(particle_frame.size.x * 0.5, particle_frame.size.y * 0.5)
	for _index in LEVEL_PARTICLE_COUNT:
		var dot := _take_particle()
		if dot == null:
			break
		var dot_size := randf_range(6.0, 12.0)
		dot.size = Vector2(dot_size, dot_size)
		dot.color = Color(HDTheme.CYAN.r, HDTheme.CYAN.g, 1.0, 1.0)
		dot.position = origin + Vector2(randf_range(-24.0, 24.0), randf_range(-10.0, 10.0))
		dot.modulate.a = 0.95
		dot.visible = true
		_active_particles.append({
			"node": dot,
			"velocity": Vector2(randf_range(-120.0, 120.0), randf_range(-160.0, -45.0)),
			"life": 0.65,
			"max_life": 0.65,
		})


func _update_particles(delta: float) -> void:
	for index in range(_active_particles.size() - 1, -1, -1):
		var particle: Dictionary = _active_particles[index]
		var dot: ColorRect = particle["node"]
		var life: float = float(particle.get("life", 0.0)) - delta
		if life <= 0.0 or not is_instance_valid(dot):
			if is_instance_valid(dot):
				dot.visible = false
				dot.scale = Vector2.ONE
				dot.modulate.a = 1.0
			_active_particles.remove_at(index)
			continue
		particle["life"] = life
		var velocity: Vector2 = particle.get("velocity", Vector2.ZERO)
		velocity.y += 220.0 * delta
		particle["velocity"] = velocity
		dot.position += velocity * delta
		var max_life: float = maxf(0.001, float(particle.get("max_life", life)))
		dot.modulate.a = life / max_life
		_active_particles[index] = particle


func _setup_xp_audio() -> void:
	if int(_result.get("xp_earned", 0)) <= 0:
		_xp_audio_player = null
		return
	_xp_audio_player = AudioStreamPlayer.new()
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = 44100.0
	generator.buffer_length = 0.15
	_xp_audio_player.stream = generator
	_xp_audio_player.volume_db = -12.0
	add_child(_xp_audio_player)
	_xp_audio_player.play()


func _set_xp_animating(active: bool) -> void:
	_xp_animating = active
	if active:
		_xp_tick_accumulator = 0.0


func _update_xp_audio(delta: float) -> void:
	if not _xp_animating:
		return
	_xp_tick_accumulator -= delta
	if _xp_tick_accumulator > 0.0:
		return
	_xp_tick_accumulator = XP_TICK_INTERVAL_SECONDS
	_play_xp_tick()


func _play_xp_tick() -> void:
	if _xp_audio_player == null:
		return
	var playback := _xp_audio_player.get_stream_playback()
	if not (playback is AudioStreamGeneratorPlayback):
		return
	var generator: AudioStreamGenerator = _xp_audio_player.stream as AudioStreamGenerator
	if generator == null:
		return
	var tick_length_seconds := 0.028
	var frame_count: int = mini(int(generator.mix_rate * tick_length_seconds), (playback as AudioStreamGeneratorPlayback).get_frames_available())
	if frame_count <= 0:
		return
	var phase := 0.0
	var phase_delta := TAU * 880.0 / generator.mix_rate
	for frame_index in frame_count:
		var envelope: float = 1.0 - (float(frame_index) / float(frame_count))
		var sample: float = sin(phase) * 0.08 * envelope
		(playback as AudioStreamGeneratorPlayback).push_frame(Vector2(sample, sample))
		phase += phase_delta


func _begin_multiplayer_sync_wait_if_needed() -> void:
	if not bool(_result.get("multiplayer", false)):
		return
	_multiplayer_sync_deadline_ms = Time.get_ticks_msec() + int(MULTIPLAYER_SYNC_TIMEOUT_SECONDS * 1000.0)
	_multiplayer_sync_resolved = false
	_replay_button.disabled = true
	_back_button.disabled = true
	_update_multiplayer_sync_label()
	var multiplayer_service := _multiplayer_service()
	if multiplayer_service != null and multiplayer_service.has_signal("round_state_updated") and not multiplayer_service.round_state_updated.is_connected(_on_round_state_updated):
		multiplayer_service.round_state_updated.connect(_on_round_state_updated)
	_on_round_state_updated(multiplayer_service.call("get_current_round_snapshot") if multiplayer_service != null and multiplayer_service.has_method("get_current_round_snapshot") else {})


func _on_round_state_updated(snapshot: Dictionary) -> void:
	_refresh_multiplayer_outcome(snapshot)
	if _multiplayer_sync_resolved or not bool(_result.get("multiplayer", false)):
		return
	if _is_round_snapshot_synced(snapshot):
		_multiplayer_sync_resolved = true
		_replay_button.disabled = false
		_back_button.disabled = false
		_report_multiplayer_achievement_outcome(snapshot, false)
		_match_status_label.text = "Match results synced."


func _is_round_snapshot_synced(snapshot: Dictionary) -> bool:
	var multiplayer_service := _multiplayer_service()
	if multiplayer_service == null or not multiplayer_service.has_method("has_authoritative_results"):
		return false
	return bool(multiplayer_service.call("has_authoritative_results", snapshot))


func _update_multiplayer_sync_state() -> void:
	if not _is_waiting_for_multiplayer_sync():
		return
	var remaining_ms: int = max(0, _multiplayer_sync_deadline_ms - Time.get_ticks_msec())
	if remaining_ms <= 0:
		_multiplayer_sync_resolved = true
		_replay_button.disabled = false
		_back_button.disabled = false
		_apply_multiplayer_fallback_outcome()
		_match_status_label.text = "Timed out waiting for match results."
		_rank_status_label.text = "Match fallback"
		return
	_update_multiplayer_sync_label()


func _update_multiplayer_sync_label() -> void:
	var remaining_seconds: int = maxi(0, int(ceil(float(max(0, _multiplayer_sync_deadline_ms - Time.get_ticks_msec())) / 1000.0)))
	_match_status_label.text = "Waiting for match results to sync: %ds" % remaining_seconds
	_rank_status_label.text = "Syncing match"


func _is_waiting_for_multiplayer_sync() -> bool:
	return bool(_result.get("multiplayer", false)) and not _multiplayer_sync_resolved


func _refresh_multiplayer_outcome(snapshot: Dictionary) -> void:
	if not bool(_result.get("multiplayer", false)):
		_match_card.visible = false
		if _match_status_label.text.is_empty():
			_match_status_label.text = _summary_rank_label.text
		return
	var winner_name: String = str(_result.get("winner_display_name", "")).strip_edges()
	var placement: int = int(_result.get("placement", 0))
	var opponent_name := ""
	var opponent_score := -1
	var local_score := int(_result.get("score", 0))
	var multiplayer_service := _multiplayer_service()
	if multiplayer_service != null:
		var outcome: Dictionary = multiplayer_service.call("get_results_outcome", snapshot) if multiplayer_service.has_method("get_results_outcome") else {}
		if not outcome.is_empty():
			var outcome_winner_user_id: String = str(outcome.get("winner_user_id", "")).strip_edges()
			winner_name = multiplayer_service.call("get_winner_display_name", snapshot) if not outcome_winner_user_id.is_empty() and multiplayer_service.has_method("get_winner_display_name") else ""
			placement = int(outcome.get("placement", 0))
		else:
			if winner_name.is_empty() and multiplayer_service.has_method("get_winner_display_name"):
				winner_name = multiplayer_service.call("get_winner_display_name", snapshot)
			if placement <= 0 and multiplayer_service.has_method("get_local_player_placement"):
				placement = int(multiplayer_service.call("get_local_player_placement", snapshot))
		var opponent: Dictionary = multiplayer_service.call("get_opponent_snapshot", snapshot) if multiplayer_service.has_method("get_opponent_snapshot") else {}
		if not opponent.is_empty():
			opponent_name = str(opponent.get("displayName", "Player"))
			opponent_score = int(multiplayer_service.call("get_display_score_for_player", opponent)) if multiplayer_service.has_method("get_display_score_for_player") else int(opponent.get("liveScore", 0))
	if local_score > 0 and opponent_score >= 0 and local_score != opponent_score:
		if local_score > opponent_score:
			winner_name = "YOU"
			placement = 1
		else:
			winner_name = opponent_name
			placement = 2
	if not winner_name.is_empty():
		_result["winner_display_name"] = winner_name
	if placement > 0:
		_result["placement"] = placement
	var outcome_text := "DRAW"
	if placement == 1:
		outcome_text = "WIN"
	elif placement == 2:
		outcome_text = "LOSE"
	_match_card.visible = true
	_match_you_label.text = "YOU  %d" % local_score
	_match_outcome_label.text = "%s  #%d" % [outcome_text, placement] if placement > 0 else outcome_text
	_match_opponent_label.text = "OPP  %d" % opponent_score if opponent_score >= 0 else "OPP  WAITING"
	_match_status_label.text = "Winner: %s" % winner_name if not winner_name.is_empty() else "Match result pending."
	_summary_rank_label.text = _match_status_label.text
	_rank_status_label.text = "Match #%d" % placement if placement > 0 else "Match pending"
	if _results_backdrop != null and _results_backdrop.visible and _results_backdrop.has_method("trigger_results_impulse"):
		_results_backdrop.call("trigger_results_impulse", "results_match", 0.55 if placement == 1 else 0.35, 0.18)


func _apply_multiplayer_fallback_outcome() -> void:
	var multiplayer_service := _multiplayer_service()
	if multiplayer_service == null:
		return
	var snapshot: Dictionary = multiplayer_service.call("get_current_round_snapshot") if multiplayer_service.has_method("get_current_round_snapshot") else {}
	var fallback: Dictionary = multiplayer_service.call("get_fallback_results_outcome", int(_result.get("score", 0)), snapshot) if multiplayer_service.has_method("get_fallback_results_outcome") else {}
	if fallback.is_empty():
		return
	var winner_user_id: String = str(fallback.get("winner_user_id", "")).strip_edges()
	if winner_user_id.is_empty():
		_match_status_label.text = "Draw"
		return
	var winner_name := ""
	for player_variant in snapshot.get("players", []) as Array:
		if player_variant is Dictionary:
			var player: Dictionary = player_variant as Dictionary
			if str(player.get("userID", "")) == winner_user_id:
				winner_name = str(player.get("displayName", "Player"))
				break
	var placement: int = int(fallback.get("placement", 0))
	_match_status_label.text = "Winner %s | You placed #%d" % [winner_name, placement]
	_report_multiplayer_achievement_outcome(snapshot, true)


func _report_multiplayer_achievement_outcome(snapshot: Dictionary, allow_fallback: bool) -> void:
	if _multiplayer_achievement_reported:
		return
	if not bool(_result.get("multiplayer", false)):
		return
	if SteamAchievements == null:
		return
	var outcome: Dictionary = {}
	var multiplayer_service := _multiplayer_service()
	if multiplayer_service != null:
		outcome = multiplayer_service.call("get_results_outcome", snapshot) if multiplayer_service.has_method("get_results_outcome") else {}
		if outcome.is_empty() and allow_fallback and multiplayer_service.has_method("get_fallback_results_outcome"):
			outcome = multiplayer_service.call("get_fallback_results_outcome", int(_result.get("score", 0)), snapshot)
	if outcome.is_empty():
		return
	var did_win := false
	var placement := int(outcome.get("placement", 0))
	var outcome_name := str(outcome.get("outcome", "")).to_lower()
	if placement > 0:
		did_win = placement == 1
	elif outcome_name == "victory" or outcome_name == "win":
		did_win = true
	SteamAchievements.on_multiplayer_match_completed(snapshot, _result, did_win)
	_multiplayer_achievement_reported = true


func _begin_rank_snapshot() -> void:
	_rank_snapshot_request_id += 1
	var request_id := _rank_snapshot_request_id
	_leaderboard_summary.clear()
	if bool(_result.get("multiplayer", false)):
		_summary_rank_label.text = "Match ranking uses live opponent results."
		_rank_status_label.text = "Match results"
		return
	if not bool(_result.get("ranked", true)):
		_set_rank_snapshot_text("Unranked run")
		_leaderboard_button.disabled = true
		return
	if AppState == null or AppState.leaderboard_service == null or AppState.identity_service == null:
		_set_rank_snapshot_text("Rank unavailable")
		_leaderboard_button.disabled = true
		return
	if not AppState.identity_service.is_authenticated():
		_set_rank_snapshot_text("Rank unavailable")
		return
	var current_identity: Dictionary = AppState.identity_service.get_current_identity()
	var current_user_id := str(current_identity.get("userID", "")).strip_edges()
	if current_user_id.is_empty():
		_set_rank_snapshot_text("Rank unavailable")
		return
	_set_rank_snapshot_text("Loading rank")
	AppState.leaderboard_service.load_top_scores(
		_song_id(),
		str(_result.get("difficulty", AppState.current_difficulty)),
		str(_result.get("mode", AppState.current_mode)),
		100,
		func(success: bool, entries: Array) -> void:
			if request_id != _rank_snapshot_request_id or not is_inside_tree():
				return
			if not success:
				_set_rank_snapshot_text("Rank unavailable")
				return
			var found: Dictionary = {}
			for entry_variant in entries:
				if not (entry_variant is Dictionary):
					continue
				var entry: Dictionary = entry_variant as Dictionary
				if str(entry.get("userID", "")) == current_user_id:
					found = entry.duplicate(true)
					break
			if found.is_empty():
				_set_rank_snapshot_text("Outside top 100")
				_leaderboard_summary = {"rank": 0, "score": int(_result.get("score", 0))}
				return
			_leaderboard_summary = found.duplicate(true)
			var rank := int(found.get("rank", 0))
			var score := int(found.get("score", _result.get("score", 0)))
			_set_rank_snapshot_text("#%d online | %d" % [rank, score])
	)


func _set_rank_snapshot_text(text: String) -> void:
	_summary_rank_label.text = text
	_match_status_label.text = text if not bool(_result.get("multiplayer", false)) else _match_status_label.text
	_rank_status_label.text = text


func _multiplayer_service() -> Node:
	if AppState != null and AppState.has_method("get_active_multiplayer_service"):
		return AppState.get_active_multiplayer_service()
	return AppState.match_service
