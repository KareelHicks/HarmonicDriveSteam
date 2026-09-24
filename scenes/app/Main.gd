extends Control

const TitleMenuScene = preload("res://scenes/menus/TitleMenu.tscn")
const SongSelectScene = preload("res://scenes/menus/SongSelectMenu.tscn")
const VisualizerMenuScene = preload("res://scenes/menus/VisualizerMenu.tscn")
const InfoScene = preload("res://scenes/menus/InfoMenu.tscn")
const SettingsScene = preload("res://scenes/menus/SettingsMenu.tscn")
const CalibrationScene = preload("res://scenes/menus/CalibrationMenu.tscn")
const ProgressionScene = preload("res://scenes/menus/ProgressionMenu.tscn")
const ShopScene = preload("res://scenes/menus/ShopMenu.tscn")
const StatsScene = preload("res://scenes/menus/StatsMenu.tscn")
const TrackStoreScene = preload("res://scenes/menus/TrackStoreMenu.tscn")
const TrackChartPreviewScene = preload("res://scenes/menus/TrackChartPreviewMenu.tscn")
const LeaderboardsScene = preload("res://scenes/menus/LeaderboardsMenu.tscn")
const SongLeaderboardScene = preload("res://scenes/menus/SongLeaderboardMenu.tscn")
const ResultsScene = preload("res://scenes/menus/ResultsMenu.tscn")
const MultiplayerScene = preload("res://scenes/menus/MultiplayerMenu.tscn")
const GameScene = preload("res://scenes/gameplay/GameScene.tscn")
const ChartEditorScene = preload("res://scenes/editor/ChartEditorScene.tscn")
const EMSCreatorScene = preload("res://systems/ems/EMSCreator/EMSCreatorScene.tscn")
const LocalSongsScene = preload("res://scenes/menus/LocalSongsMenu.tscn")
const DisplaySettingsApplier = preload("res://scripts/ui/DisplaySettingsApplier.gd")
const HDTheme = preload("res://scripts/ui/HDTheme.gd")
const SongResolver = preload("res://scripts/songs/SongResolver.gd")
const WorkshopSubscriptionSync = preload("res://scripts/workshop/WorkshopSubscriptionSync.gd")

const WORKSHOP_SYNC_RETRY_ATTEMPTS := 20
const WORKSHOP_SYNC_RETRY_INTERVAL_SEC := 1.0
const WORKSHOP_SYNC_COMPLETE_HOLD_SEC := 0.8
const WORKSHOP_SYNC_WARNING_HOLD_SEC := 1.8

@onready var screen_root: Control = %ScreenRoot
@onready var _global_ems_backdrop: Control = $GlobalEMSBackdrop
@onready var _global_ems_left_wrap: Control = $GlobalEMSBackdrop/GlobalEMSLeftWrap
@onready var _global_ems_right_wrap: Control = $GlobalEMSBackdrop/GlobalEMSRightWrap

var _current_screen: Node
var _workshop_status_overlay: Control
var _workshop_status_panel: PanelContainer
var _workshop_status_title_label: Label
var _workshop_status_phase_label: Label
var _workshop_status_detail_label: Label
var _startup_workshop_sync_complete := false
var _workshop_sync_in_progress := false


func _ready() -> void:
	_apply_initial_window_mode()
	resized.connect(_layout_global_ems_split)
	_global_ems_backdrop.resized.connect(_layout_global_ems_split)
	if EmotionalMotionSystem != null and EmotionalMotionSystem.has_signal("loadout_changed"):
		EmotionalMotionSystem.loadout_changed.connect(_on_ems_loadout_changed)
	call_deferred("_layout_global_ems_split")
	AppState.show_title_requested.connect(show_title)
	AppState.show_song_select_requested.connect(show_song_select)
	AppState.show_visualizer_select_requested.connect(show_visualizer_select)
	AppState.show_practice_select_requested.connect(show_practice_select)
	AppState.show_info_requested.connect(show_info)
	AppState.show_settings_requested.connect(show_settings)
	AppState.show_calibration_requested.connect(show_calibration)
	AppState.show_progression_requested.connect(show_progression)
	AppState.show_shop_requested.connect(show_shop)
	AppState.show_stats_requested.connect(show_stats)
	AppState.show_track_store_requested.connect(show_track_store)
	AppState.show_multiplayer_requested.connect(show_multiplayer)
	AppState.show_leaderboards_requested.connect(show_leaderboards)
	AppState.show_chart_editor_requested.connect(show_chart_editor)
	AppState.show_local_songs_requested.connect(show_local_songs)
	AppState.show_community_charts_requested.connect(show_community_charts)
	AppState.start_game_requested.connect(show_game)
	AppState.show_results_requested.connect(show_results)
	var startup_route: String = AppState.consume_pending_startup_route()
	if startup_route == "multiplayer":
		show_multiplayer()
	else:
		show_title()
	if startup_route != "multiplayer":
		call_deferred("_run_startup_workshop_sync")


func _apply_initial_window_mode() -> void:
	DisplaySettingsApplier.apply_from_profile()


func _layout_global_ems_split() -> void:
	if _global_ems_backdrop == null or _global_ems_left_wrap == null or _global_ems_right_wrap == null:
		return
	var backdrop_size := _global_ems_backdrop.size
	if backdrop_size.x <= 0.0:
		backdrop_size = get_viewport_rect().size
	var full_background := _community_ems_uses_full_background()
	var active := bool(_global_ems_backdrop.get_meta("ems_context_active", true))
	_global_ems_left_wrap.set_meta("ems_layout_hidden", false)
	_global_ems_right_wrap.set_meta("ems_layout_hidden", full_background)
	if full_background:
		_global_ems_left_wrap.anchor_left = 0.0
		_global_ems_left_wrap.anchor_right = 1.0
		_global_ems_left_wrap.anchor_top = 0.0
		_global_ems_left_wrap.anchor_bottom = 1.0
		_global_ems_left_wrap.offset_left = 0.0
		_global_ems_left_wrap.offset_right = 0.0
		_global_ems_left_wrap.offset_top = 0.0
		_global_ems_left_wrap.offset_bottom = 0.0
		_global_ems_left_wrap.visible = active
		_global_ems_left_wrap.set_process(active)
		_global_ems_left_wrap.set_physics_process(active)
		_global_ems_right_wrap.visible = false
		_global_ems_right_wrap.set_process(false)
		_global_ems_right_wrap.set_physics_process(false)
		return
	var split_x := floorf(backdrop_size.x * 0.5)
	_global_ems_left_wrap.anchor_left = 0.0
	_global_ems_left_wrap.anchor_right = 0.0
	_global_ems_left_wrap.anchor_top = 0.0
	_global_ems_left_wrap.anchor_bottom = 1.0
	_global_ems_left_wrap.offset_left = 0.0
	_global_ems_left_wrap.offset_right = split_x
	_global_ems_left_wrap.offset_top = 0.0
	_global_ems_left_wrap.offset_bottom = 0.0
	_global_ems_right_wrap.anchor_left = 0.0
	_global_ems_right_wrap.anchor_right = 0.0
	_global_ems_right_wrap.anchor_top = 0.0
	_global_ems_right_wrap.anchor_bottom = 1.0
	_global_ems_right_wrap.offset_left = split_x
	_global_ems_right_wrap.offset_right = backdrop_size.x
	_global_ems_right_wrap.offset_top = 0.0
	_global_ems_right_wrap.offset_bottom = 0.0
	_global_ems_left_wrap.visible = active
	_global_ems_right_wrap.visible = active
	_global_ems_left_wrap.set_process(active)
	_global_ems_left_wrap.set_physics_process(active)
	_global_ems_right_wrap.set_process(active)
	_global_ems_right_wrap.set_physics_process(active)


func _community_ems_uses_full_background() -> bool:
	return EmotionalMotionSystem != null and EmotionalMotionSystem.has_method("community_uses_full_background") and bool(EmotionalMotionSystem.call("community_uses_full_background"))


func _on_ems_loadout_changed(_loadout_id: String) -> void:
	_layout_global_ems_split()
	_set_global_menu_ems_active(bool(_global_ems_backdrop.get_meta("ems_context_active", true)))


func _set_ui_navigation_audio_enabled(enabled: bool) -> void:
	var ui_audio := get_node_or_null("/root/UIAudio")
	if ui_audio != null and ui_audio.has_method("set_navigation_enabled"):
		ui_audio.call("set_navigation_enabled", enabled)


func _swap_screen(scene: PackedScene) -> Node:
	if is_instance_valid(_current_screen):
		_current_screen.queue_free()
	_current_screen = scene.instantiate()
	screen_root.add_child(_current_screen)
	return _current_screen


func _ensure_workshop_status_overlay() -> void:
	if is_instance_valid(_workshop_status_overlay):
		return
	_workshop_status_overlay = Control.new()
	_workshop_status_overlay.name = "WorkshopStatusOverlay"
	_workshop_status_overlay.visible = false
	_workshop_status_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_workshop_status_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_workshop_status_overlay)

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0, 0, 0, 0.62)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_workshop_status_overlay.add_child(dim)

	var center := CenterContainer.new()
	center.name = "Center"
	center.mouse_filter = Control.MOUSE_FILTER_STOP
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_workshop_status_overlay.add_child(center)

	_workshop_status_panel = PanelContainer.new()
	_workshop_status_panel.name = "StatusPanel"
	_workshop_status_panel.add_theme_stylebox_override("panel", HDTheme.overlay_panel_style())
	center.add_child(_workshop_status_panel)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_top", 26)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_bottom", 28)
	_workshop_status_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	_workshop_status_title_label = Label.new()
	_workshop_status_title_label.name = "TitleLabel"
	_workshop_status_title_label.text = "COMMUNITY CHARTS"
	HDTheme.apply_label(_workshop_status_title_label, "screen_title", HDTheme.CYAN, true)
	vbox.add_child(_workshop_status_title_label)

	var accent := ColorRect.new()
	accent.name = "Accent"
	accent.color = HDTheme.CYAN * Color(1, 1, 1, 0.72)
	accent.custom_minimum_size = Vector2(0, 3)
	vbox.add_child(accent)

	_workshop_status_phase_label = Label.new()
	_workshop_status_phase_label.name = "PhaseLabel"
	_workshop_status_phase_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	HDTheme.apply_label(_workshop_status_phase_label, "section_title", HDTheme.SECONDARY, true)
	vbox.add_child(_workshop_status_phase_label)

	_workshop_status_detail_label = Label.new()
	_workshop_status_detail_label.name = "DetailLabel"
	_workshop_status_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	HDTheme.apply_label(_workshop_status_detail_label, "body", HDTheme.TERTIARY, true)
	vbox.add_child(_workshop_status_detail_label)
	_layout_workshop_status_overlay()


func _layout_workshop_status_overlay() -> void:
	if not is_instance_valid(_workshop_status_panel):
		return
	var size := get_viewport_rect().size
	var metrics := HDTheme.overlay_metrics(size)
	var width := minf(float(metrics.get("panel_width", 720.0)), 720.0)
	_workshop_status_panel.custom_minimum_size = Vector2(width, 0)
	if is_instance_valid(_workshop_status_title_label):
		HDTheme.apply_label(_workshop_status_title_label, "screen_title", HDTheme.CYAN, true)
	if is_instance_valid(_workshop_status_phase_label):
		HDTheme.apply_label(_workshop_status_phase_label, "section_title", HDTheme.SECONDARY, true)
	if is_instance_valid(_workshop_status_detail_label):
		HDTheme.apply_label(_workshop_status_detail_label, "body", HDTheme.TERTIARY, true)


func _show_workshop_status(phase: String, detail: String, heading: String = "COMMUNITY CHARTS") -> void:
	_ensure_workshop_status_overlay()
	_layout_workshop_status_overlay()
	_workshop_status_title_label.text = heading
	_update_workshop_status(phase, detail)
	_workshop_status_overlay.visible = true
	_workshop_status_overlay.move_to_front()


func _update_workshop_status(phase: String, detail: String) -> void:
	_ensure_workshop_status_overlay()
	_workshop_status_phase_label.text = phase
	_workshop_status_detail_label.text = detail


func _hide_workshop_status() -> void:
	if is_instance_valid(_workshop_status_overlay):
		_workshop_status_overlay.visible = false


func _on_community_chart_sync_status(status: Dictionary) -> void:
	var title := str(status.get("title", "Preparing Community Charts")).strip_edges()
	var detail := str(status.get("detail", "")).strip_edges()
	if title.is_empty():
		title = "Preparing Community Charts"
	_update_workshop_status(title, detail)


func _run_startup_workshop_sync() -> void:
	if _startup_workshop_sync_complete or _workshop_sync_in_progress:
		return
	if not _can_run_steam_workshop_sync():
		_startup_workshop_sync_complete = true
		return
	_workshop_sync_in_progress = true
	_show_workshop_status("Checking Workshop subscriptions", "Reconciling subscribed and unsubscribed Workshop items from Steam.", "WORKSHOP SYNC")
	await get_tree().process_frame
	var sync_result: Dictionary = await WorkshopSubscriptionSync.refresh_all_until_stable_interactive(
		true,
		Callable(self, "_on_community_chart_sync_status"),
		true,
		WORKSHOP_SYNC_RETRY_ATTEMPTS,
		WORKSHOP_SYNC_RETRY_INTERVAL_SEC
	)
	_reload_ems_registry_after_workshop_sync(sync_result)
	if bool(sync_result.get("ok", false)):
		if bool(sync_result.get("stabilized", false)):
			_update_workshop_status("Workshop sync complete", _workshop_sync_summary(sync_result))
			await get_tree().create_timer(WORKSHOP_SYNC_COMPLETE_HOLD_SEC).timeout
		else:
			_update_workshop_status("Workshop downloads still pending", _workshop_sync_summary(sync_result))
			await get_tree().create_timer(WORKSHOP_SYNC_WARNING_HOLD_SEC).timeout
	else:
		_update_workshop_status("Workshop sync unavailable", str(sync_result.get("message", "Steam Workshop sync did not complete.")))
		await get_tree().create_timer(WORKSHOP_SYNC_WARNING_HOLD_SEC).timeout
	_hide_workshop_status()
	_workshop_sync_in_progress = false
	_startup_workshop_sync_complete = true


func _can_run_steam_workshop_sync() -> bool:
	return not OS.has_feature("android") and AppState.can_use_steam_services()


func _reload_ems_registry_after_workshop_sync(sync_result: Dictionary) -> void:
	var changed_ems := not (sync_result.get("ems", []) as Array).is_empty()
	changed_ems = changed_ems or not (sync_result.get("removed_ems", []) as Array).is_empty()
	if not changed_ems:
		return
	var registry := get_node_or_null("/root/EMSRegistry")
	if registry != null and registry.has_method("reload"):
		registry.call("reload")


func _workshop_sync_summary(sync_result: Dictionary) -> String:
	var parts: Array[String] = []
	var chart_count := (sync_result.get("charts", []) as Array).size()
	var ems_count := (sync_result.get("ems", []) as Array).size()
	var removed_chart_count := (sync_result.get("removed_charts", []) as Array).size()
	var removed_ems_count := (sync_result.get("removed_ems", []) as Array).size()
	var pending_count := (sync_result.get("pending_downloads", []) as Array).size()
	if chart_count > 0:
		parts.append("%d chart%s ready" % [chart_count, "" if chart_count == 1 else "s"])
	if ems_count > 0:
		parts.append("%d EMS pack%s ready" % [ems_count, "" if ems_count == 1 else "s"])
	if removed_chart_count > 0:
		parts.append("%d unsubscribed chart%s removed" % [removed_chart_count, "" if removed_chart_count == 1 else "s"])
	if removed_ems_count > 0:
		parts.append("%d unsubscribed EMS pack%s removed" % [removed_ems_count, "" if removed_ems_count == 1 else "s"])
	if pending_count > 0:
		parts.append("%d Steam download%s still pending" % [pending_count, "" if pending_count == 1 else "s"])
	if parts.is_empty():
		return str(sync_result.get("message", "No Workshop changes found."))
	return ". ".join(parts) + "."


func show_title() -> void:
	_set_ui_navigation_audio_enabled(true)
	_set_global_menu_ems_active(true)
	var screen = _swap_screen(TitleMenuScene)
	MenuAudio.set_menu_context("title")
	var exclude_song_id := MenuAudio.consume_last_preview_song_id()
	if exclude_song_id.is_empty():
		exclude_song_id = MenuAudio.get_current_song_id()
	MenuAudio.play_random_song_if_needed(exclude_song_id)
	screen.play_requested.connect(AppState.request_song_select)
	screen.visualizer_requested.connect(AppState.request_visualizer_select)
	screen.practice_requested.connect(AppState.request_practice_select)
	screen.progression_requested.connect(AppState.request_progression)
	screen.shop_requested.connect(AppState.request_shop)
	screen.stats_requested.connect(AppState.request_stats)
	screen.settings_requested.connect(AppState.request_settings)
	screen.calibration_requested.connect(AppState.request_calibration)
	screen.multiplayer_requested.connect(AppState.request_multiplayer)
	screen.leaderboards_requested.connect(AppState.request_leaderboards)
	screen.ems_creator_requested.connect(show_ems_creator)
	screen.harmonic_charter_requested.connect(AppState.request_chart_editor)
	screen.local_songs_requested.connect(AppState.request_local_songs)
	screen.community_charts_requested.connect(AppState.request_community_charts)


func show_chart_editor() -> void:
	_set_ui_navigation_audio_enabled(false)
	_set_global_menu_ems_active(false)
	MenuAudio.stop()
	var screen = _swap_screen(ChartEditorScene)
	screen.back_requested.connect(AppState.request_title)


func show_local_songs() -> void:
	_set_ui_navigation_audio_enabled(true)
	_set_global_menu_ems_active(true)
	MenuAudio.stop()
	MenuAudio.set_menu_context("song_select")
	var screen = _swap_screen(LocalSongsScene)
	screen.back_requested.connect(AppState.request_title)
	if screen.has_signal("loadout_requested"):
		screen.loadout_requested.connect(_show_shop_from_playlist.bind("local_songs"))
	screen.start_requested.connect(func(song_entry: Dictionary, difficulty: String, mode: String) -> void:
		AppState.start_song(song_entry, difficulty, mode)
	)


func show_community_charts() -> void:
	_set_ui_navigation_audio_enabled(true)
	_set_global_menu_ems_active(true)
	MenuAudio.stop()
	MenuAudio.set_menu_context("song_select")
	var empty_status := "No subscribed Workshop chart packs found."
	if _can_run_steam_workshop_sync():
		_show_workshop_status("Fetching subscribed Workshop items", "Checking Steam Workshop subscriptions.", "COMMUNITY CHARTS")
		await get_tree().process_frame
		var sync_result: Dictionary = await WorkshopSubscriptionSync.refresh_all_until_stable_interactive(
			true,
			Callable(self, "_on_community_chart_sync_status"),
			true,
			WORKSHOP_SYNC_RETRY_ATTEMPTS,
			WORKSHOP_SYNC_RETRY_INTERVAL_SEC
		)
		if bool(sync_result.get("ok", false)):
			_reload_ems_registry_after_workshop_sync(sync_result)
			_update_workshop_status("Opening Community Charts", _workshop_sync_summary(sync_result))
		else:
			_update_workshop_status("Opening cached Community Charts", str(sync_result.get("message", "Workshop sync did not complete.")))
	else:
		empty_status = "%s\n\nOpen Steam to sync subscribed Workshop chart packs." % AppState.get_steam_unavailable_message()
	await get_tree().process_frame
	var screen = _swap_screen(LocalSongsScene)
	if screen.has_method("configure_source"):
		screen.call("configure_source", SongResolver.WORKSHOP_ROOT, "workshop", "COMMUNITY CHARTS", empty_status)
	screen.back_requested.connect(AppState.request_title)
	if screen.has_signal("loadout_requested"):
		screen.loadout_requested.connect(_show_shop_from_playlist.bind("community_charts"))
	screen.start_requested.connect(func(song_entry: Dictionary, difficulty: String, mode: String) -> void:
		AppState.start_song(song_entry, difficulty, mode)
	)
	_hide_workshop_status()


func show_song_select() -> void:
	_set_ui_navigation_audio_enabled(true)
	_set_global_menu_ems_active(true)
	MenuAudio.stop()
	MenuAudio.set_menu_context("song_select")
	var screen = _swap_screen(SongSelectScene)
	screen.back_requested.connect(AppState.request_title)
	if screen.has_signal("loadout_requested"):
		screen.loadout_requested.connect(_show_shop_from_playlist.bind("song_select"))
	screen.start_requested.connect(func(song_entry: Dictionary, difficulty: String, mode: String) -> void:
		AppState.start_song(song_entry, difficulty, mode)
	)


func show_practice_select() -> void:
	_set_ui_navigation_audio_enabled(true)
	_set_global_menu_ems_active(true)
	MenuAudio.stop()
	MenuAudio.set_menu_context("song_select")
	var screen = _swap_screen(SongSelectScene)
	screen.back_requested.connect(AppState.request_title)
	if screen.has_signal("loadout_requested"):
		screen.loadout_requested.connect(_show_shop_from_playlist.bind("practice"))
	screen.start_requested.connect(func(song_entry: Dictionary, difficulty: String, mode: String) -> void:
		AppState.start_practice_song(song_entry, difficulty, mode)
	)


func show_visualizer_select() -> void:
	_set_ui_navigation_audio_enabled(true)
	_set_global_menu_ems_active(true)
	MenuAudio.stop()
	MenuAudio.set_menu_context("song_select")
	var screen = _swap_screen(VisualizerMenuScene)
	screen.back_requested.connect(AppState.request_title)
	screen.shuffle_requested.connect(AppState.start_visualizer_shuffle)
	screen.song_requested.connect(AppState.start_visualizer_song)


func show_info(payload: Dictionary) -> void:
	_set_ui_navigation_audio_enabled(true)
	_set_global_menu_ems_active(true)
	_keep_main_menu_music()
	var screen = _swap_screen(InfoScene)
	screen.back_requested.connect(AppState.request_title)
	screen.configure(payload)


func show_settings() -> void:
	_set_ui_navigation_audio_enabled(true)
	_set_global_menu_ems_active(true)
	_keep_main_menu_music()
	var screen = _swap_screen(SettingsScene)
	screen.back_requested.connect(AppState.request_title)


func show_progression() -> void:
	_set_ui_navigation_audio_enabled(true)
	_set_global_menu_ems_active(true)
	_keep_main_menu_music()
	var screen = _swap_screen(ProgressionScene)
	screen.back_requested.connect(AppState.request_title)
	screen.open_shop_requested.connect(AppState.request_shop)


func _show_shop_from_playlist(return_route: String) -> void:
	show_shop(return_route)


func show_shop(return_route: String = "") -> void:
	_set_ui_navigation_audio_enabled(true)
	_set_global_menu_ems_active(true)
	_keep_main_menu_music()
	var screen = _swap_screen(ShopScene)
	screen.back_requested.connect(func() -> void:
		_return_from_shop(return_route)
	)
	screen.open_progression_requested.connect(AppState.request_progression)


func _return_from_shop(return_route: String) -> void:
	match return_route:
		"practice":
			show_practice_select()
		"song_select":
			show_song_select()
		"local_songs":
			show_local_songs()
		"community_charts":
			show_community_charts()
		_:
			AppState.request_title()


func show_ems_creator() -> void:
	_set_ui_navigation_audio_enabled(true)
	MenuAudio.set_menu_context("title")
	if not MenuAudio.play_random_song_if_needed():
		MenuAudio.stop()
	_set_global_menu_ems_active(false)
	var screen = _swap_screen(EMSCreatorScene)
	screen.back_requested.connect(AppState.request_title)


func show_stats() -> void:
	_set_ui_navigation_audio_enabled(true)
	_set_global_menu_ems_active(true)
	_keep_main_menu_music()
	var screen = _swap_screen(StatsScene)
	screen.back_requested.connect(AppState.request_title)


func show_track_store() -> void:
	_set_ui_navigation_audio_enabled(true)
	_set_global_menu_ems_active(false)
	MenuAudio.stop()
	var screen = _swap_screen(TrackStoreScene)
	screen.back_requested.connect(AppState.request_title)
	screen.chart_requested.connect(func(song_id: String) -> void:
		PremiumStore.stop_audio_preview()
		show_track_chart_preview(song_id)
	)
	screen.start_requested.connect(func(song_entry: Dictionary, difficulty: String, mode: String) -> void:
		PremiumStore.stop_audio_preview()
		AppState.start_song(song_entry, difficulty, mode)
	)


func show_track_chart_preview(song_id: String) -> void:
	_set_ui_navigation_audio_enabled(true)
	_set_global_menu_ems_active(false)
	MenuAudio.stop()
	var screen = _swap_screen(TrackChartPreviewScene)
	screen.back_requested.connect(show_track_store)
	screen.configure(song_id)


func show_leaderboards() -> void:
	_set_ui_navigation_audio_enabled(true)
	_set_global_menu_ems_active(true)
	_keep_main_menu_music()
	var screen = _swap_screen(LeaderboardsScene)
	screen.back_requested.connect(AppState.request_title)
	screen.song_requested.connect(func(song_id: String, summary: Dictionary) -> void:
		show_song_leaderboard(song_id, summary)
	)


func show_song_leaderboard(song_id: String, summary: Dictionary = {}) -> void:
	_set_ui_navigation_audio_enabled(true)
	_set_global_menu_ems_active(true)
	_keep_main_menu_music()
	var screen = _swap_screen(SongLeaderboardScene)
	screen.back_requested.connect(show_leaderboards)
	screen.configure(song_id, summary)


func show_calibration() -> void:
	_set_ui_navigation_audio_enabled(true)
	_set_global_menu_ems_active(false)
	MenuAudio.stop()
	var screen = _swap_screen(CalibrationScene)
	screen.back_requested.connect(AppState.request_title)


func show_multiplayer() -> void:
	if not AppState.can_use_steam_services():
		AppState.clear_pending_startup_route("multiplayer")
		AppState.clear_multiplayer_context()
		show_info({
			"title": "MULTIPLAYER UNAVAILABLE",
			"message": "%s\n\nOpen Steam, then return to Multiplayer." % AppState.get_steam_unavailable_message(),
		})
		return
	_set_ui_navigation_audio_enabled(true)
	_set_global_menu_ems_active(true)
	_keep_main_menu_music()
	AppState.clear_pending_startup_route("multiplayer")
	AppState.clear_multiplayer_context()
	var screen = _swap_screen(MultiplayerScene)
	screen.back_requested.connect(AppState.request_title)


func show_game(_song_entry: Dictionary, _difficulty: String, _mode: String) -> void:
	_set_ui_navigation_audio_enabled(false)
	_set_global_menu_ems_active(false)
	MenuAudio.stop()
	var screen = _swap_screen(GameScene)
	screen.game_exited.connect(func() -> void:
		if AppState.visualizer_active:
			AppState.request_visualizer_select()
		elif AppState.practice_active:
			AppState.request_practice_select()
		elif AppState.is_multiplayer_round_active():
			AppState.request_multiplayer()
		else:
			AppState.request_song_select()
	)
	if AppState.visualizer_active:
		screen.visualizer_song_finished.connect(AppState.advance_visualizer_song)
	else:
		screen.song_finished.connect(AppState.finish_song)


func show_results(result: Dictionary) -> void:
	_set_ui_navigation_audio_enabled(true)
	_set_global_menu_ems_active(false)
	MenuAudio.stop()
	var screen = _swap_screen(ResultsScene)
	if bool(result.get("multiplayer", false)):
		screen.back_requested.connect(AppState.request_multiplayer)
		screen.replay_requested.connect(AppState.request_multiplayer)
	else:
		screen.back_requested.connect(func() -> void:
			_return_from_results(result)
		)
		screen.replay_requested.connect(func() -> void:
			if not AppState.current_song.is_empty():
				AppState.start_song(AppState.current_song, AppState.current_difficulty, AppState.current_mode)
		)
	if screen.has_signal("leaderboard_requested"):
		screen.leaderboard_requested.connect(func(song_id: String, summary: Dictionary) -> void:
			show_song_leaderboard(song_id, summary)
		)


func _return_from_results(result: Dictionary) -> void:
	match str(result.get("return_route", "")).strip_edges().to_lower():
		"community_charts":
			AppState.request_community_charts()
		"local_songs":
			AppState.request_local_songs()
		"multiplayer":
			AppState.request_multiplayer()
		_:
			match str(result.get("source_type", "")).strip_edges().to_lower():
				"workshop":
					AppState.request_community_charts()
				"custom":
					AppState.request_local_songs()
				_:
					AppState.request_song_select()


func _keep_main_menu_music() -> void:
	_set_global_menu_ems_active(true)
	MenuAudio.set_menu_context("title")
	if not MenuAudio.play_random_song_if_needed():
		MenuAudio.stop()


func _set_global_menu_ems_active(active: bool) -> void:
	if _global_ems_backdrop == null:
		return
	_apply_global_menu_ems_state(_global_ems_backdrop, active)


func _apply_global_menu_ems_state(node: Node, active: bool) -> void:
	node.set_meta("ems_context_active", active)
	var effective_active := active
	if node.has_meta("ems_layout_hidden") and bool(node.get_meta("ems_layout_hidden")):
		effective_active = false
	if node.has_meta("ems_visual_effect_enabled"):
		effective_active = effective_active and bool(node.get_meta("ems_visual_effect_enabled"))
	if node is CanvasItem:
		(node as CanvasItem).visible = effective_active
	if node is Node:
		node.set_process(effective_active)
		node.set_physics_process(effective_active)
	if node.has_method("ems_on_enabled_changed"):
		node.call("ems_on_enabled_changed", effective_active)
	for child in node.get_children():
		_apply_global_menu_ems_state(child, active)
