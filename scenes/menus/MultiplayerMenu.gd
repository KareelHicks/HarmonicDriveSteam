extends Control

const HDTheme = preload("res://scripts/ui/HDTheme.gd")
const GameModeConfig = preload("res://scripts/gameplay/GameModeConfig.gd")
const MobileScrollButtonScript = preload("res://scripts/ui/MobileScrollButton.gd")
const MenuNavigator = preload("res://scripts/ui/MenuNavigator.gd")
const SongJacketService = preload("res://scripts/ui/SongJacketService.gd")

signal back_requested

const DIFFICULTIES: Array[String] = ["Easy", "Medium", "Hard", "Expert", "Professional"]

@onready var _panel: PanelContainer = %Panel
@onready var _back_button: Button = $BackButton
@onready var _status_label: Label = %StatusLabel
@onready var _status_scroll: ScrollContainer = %StatusScroll
@onready var _main_scroll: ScrollContainer = %Scroll
@onready var _identity_label: Label = %IdentityLabel
@onready var _players_label: Label = %PlayersLabel
@onready var _selection_label: Label = %SelectionLabel
@onready var _lobby_state_label: Label = %LobbyStateLabel
@onready var _share_code_label: Label = %ShareCodeLabel
@onready var _buttons: Array[Button] = [
	%AuthenticateButton,
	%ClassicMatchmakeButton,
	%SteamInviteButton,
	%CreateLobbyButton,
	%SelectTrackButton,
	%ReadyButton,
]
@onready var _join_row: HBoxContainer = %ConnectionInput.get_parent()
@onready var _session_row: HBoxContainer = %HostInput.get_parent()

var _songs: Array[Dictionary] = []
var _selected_song: Dictionary = {}
var _pending_mode: String = GameModeConfig.DEFAULT_MODE
var _pending_steam_invite_after_lobby := false
var _status_history: Array[String] = []
var _classic_selection_presented := false
var _pending_custom_queue_after_selection := false
var _menu_navigator: MenuNavigator


func _ready() -> void:
	_apply_mobile_scroll_buttons()
	_menu_navigator = MenuNavigator.install(self, Callable(self, "_on_back_button_pressed"))
	_songs = _accessible_songs()
	_back_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_back_button.move_to_front()
	%Background.color = HDTheme.BG
	%SubtitleLabel.text = "Connect your account, then queue for Classic or Custom multiplayer through the relay."
	%AuthenticateButton.text = "CONNECT ACCOUNT"
	%ClassicMatchmakeButton.text = "QUEUE CLASSIC MATCH (Desktop & Mobile)"
	%SteamInviteButton.text = "INVITE FRIEND (Steam Only)"
	%CreateLobbyButton.text = "QUEUE CUSTOM MATCH (Desktop & Mobile)"
	%SelectTrackButton.text = "SELECT TRACK / MODE / DIFFICULTY"
	%PollMatchmakeButton.visible = false
	_join_row.visible = false
	%JoinLobbyButton.visible = false
	%ShareCodeLabel.visible = false
	_session_row.visible = false
	%HostSessionButton.visible = false
	%JoinSessionButton.visible = false
	apply_layout()
	get_viewport().size_changed.connect(apply_layout)
	if AppState.identity_service != null:
		AppState.identity_service.auth_state_changed.connect(_on_auth_state_changed)
		AppState.identity_service.login_failed.connect(_append_status)
	if AppState.match_service != null:
		AppState.match_service.auth_state_changed.connect(_on_auth_state_changed)
		AppState.match_service.players_changed.connect(_on_players_changed)
		AppState.match_service.matchmaking_updated.connect(_on_matchmaking_updated)
		AppState.match_service.lobby_updated.connect(_on_lobby_updated)
		AppState.match_service.start_time_received.connect(_on_start_time_received)
		AppState.match_service.error_raised.connect(_append_status)
		AppState.match_service.session_state_changed.connect(_on_session_state_changed)
		AppState.match_service.selection_changed.connect(_on_selection_changed)
	if AppState.steam_lobby_service != null:
		AppState.steam_lobby_service.players_changed.connect(_on_players_changed)
		AppState.steam_lobby_service.matchmaking_updated.connect(_on_steam_lobby_matchmaking_updated)
		AppState.steam_lobby_service.lobby_updated.connect(_on_steam_lobby_updated)
		AppState.steam_lobby_service.start_time_received.connect(_on_start_time_received)
		AppState.steam_lobby_service.error_raised.connect(_append_status)
		AppState.steam_lobby_service.session_state_changed.connect(_on_session_state_changed)
		AppState.steam_lobby_service.selection_changed.connect(_on_selection_changed)
	_on_auth_state_changed(AppState.identity_service.get_current_identity())
	if _steam_lobby_active():
		_on_players_changed(AppState.steam_lobby_service.get_players())
		_on_selection_changed(AppState.steam_lobby_service.get_current_selection())
		if AppState.steam_lobby_service.has_method("prepare_next_round") and AppState.steam_lobby_service.get_current_phase() == "finished":
			AppState.steam_lobby_service.prepare_next_round()
	else:
		_on_players_changed(AppState.match_service.get_players())
		_on_selection_changed(AppState.match_service.get_current_selection())
	_hide_selection_overlay()
	_refresh_lobby_controls()
	call_deferred("_reset_main_scroll_to_top")
	call_deferred("_refresh_menu_navigation")


func apply_layout() -> void:
	var size: Vector2 = get_viewport_rect().size
	var metrics: Dictionary = HDTheme.overlay_metrics(size)
	HDTheme.apply_label(%BackLabel, "caption", HDTheme.SECONDARY)
	%BackLabel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	HDTheme.apply_back_button(_back_button, %BackLabel)
	$BackButton.offset_left = 40.0
	$BackButton.offset_top = 34.0
	$BackButton.offset_right = 192.0
	$BackButton.offset_bottom = 78.0
	HDTheme.apply_label(%TitleLabel, "screen_title", HDTheme.CYAN, true)
	HDTheme.apply_label(%SubtitleLabel, "body", HDTheme.SECONDARY, true)
	HDTheme.apply_label(_status_label, "supporting", HDTheme.SECONDARY, false)
	HDTheme.apply_label(_identity_label, "supporting", HDTheme.TERTIARY, false)
	HDTheme.apply_label(_players_label, "supporting", HDTheme.SECONDARY, false)
	HDTheme.apply_label(_share_code_label, "supporting", HDTheme.CYAN, false)
	HDTheme.apply_label(_selection_label, "supporting", HDTheme.SECONDARY, false)
	%SelectedJacket.custom_minimum_size = Vector2(168, 168)
	HDTheme.apply_label(_lobby_state_label, "supporting", HDTheme.TERTIARY, false)
	HDTheme.apply_label(%SelectionTitleLabel, "screen_title", HDTheme.CYAN, true)
	HDTheme.apply_label(%SelectionSubtitleLabel, "body", HDTheme.SECONDARY, true)
	_panel.custom_minimum_size = Vector2(metrics["panel_width"] * 1.02, metrics["panel_height"] * 0.88)
	_panel.add_theme_stylebox_override("panel", HDTheme.overlay_panel_style())
	%StatusPanel.add_theme_stylebox_override("panel", HDTheme.card_style())
	%SelectionPanel.custom_minimum_size = Vector2(metrics["panel_width"] * 0.9, metrics["panel_height"] * 0.64)
	%SelectionPanel.add_theme_stylebox_override("panel", HDTheme.overlay_panel_style())
	%OverlayDim.color = Color(0, 0, 0, 0.74)
	%SelectionScroll.custom_minimum_size = Vector2(0, metrics["panel_height"] * 0.38)
	%StatusPanel.custom_minimum_size = Vector2(0, maxf(150.0, metrics["panel_height"] * 0.24))
	for button in _buttons:
		var is_primary := button == %AuthenticateButton or button == %ClassicMatchmakeButton or button == %SteamInviteButton or button == %CreateLobbyButton
		button.custom_minimum_size.y = metrics["button_height"]
		button.add_theme_stylebox_override("normal", HDTheme.button_style(is_primary))
		button.add_theme_stylebox_override("hover", HDTheme.button_style(is_primary))
		button.add_theme_stylebox_override("pressed", HDTheme.button_style(is_primary))
		button.add_theme_font_size_override("font_size", HDTheme.text_size("button_secondary", size))
	%SelectionButtons.add_theme_constant_override("separation", 14)
	%SelectionCancelButton.custom_minimum_size.y = metrics["button_height"]
	%SelectionCancelButton.add_theme_stylebox_override("normal", HDTheme.button_style(false))
	%SelectionCancelButton.add_theme_stylebox_override("hover", HDTheme.button_style(false))
	%SelectionCancelButton.add_theme_stylebox_override("pressed", HDTheme.button_style(false))
	%SelectionCancelButton.add_theme_font_size_override("font_size", HDTheme.text_size("button_secondary", size))


func _on_auth_state_changed(identity: Dictionary) -> void:
	var user_id: String = str(identity.get("userID", ""))
	var display_name: String = str(identity.get("displayName", ""))
	var platform: String = str(identity.get("platform", ""))
	if user_id.is_empty():
		_identity_label.text = "Identity: not authenticated"
		_refresh_lobby_controls()
		return
	_identity_label.text = "Identity: %s (%s)" % [display_name, platform]
	_refresh_lobby_controls()


func _on_players_changed(player_list: Array) -> void:
	if player_list.is_empty():
		_players_label.text = "Players: none"
		_refresh_lobby_controls()
		return
	var lines: Array[String] = []
	for player_variant in player_list:
		if player_variant is Dictionary:
			var entry: Dictionary = player_variant as Dictionary
			var ready_suffix: String = "  •  READY" if bool(entry.get("is_ready", false)) else "  •  NOT READY"
			lines.append("• %s%s" % [str(entry.get("display_name", "Player")), ready_suffix])
	_players_label.text = "Players:\n%s" % "\n".join(lines)
	_refresh_lobby_controls()


func _on_matchmaking_updated(payload: Dictionary) -> void:
	var flow: String = AppState.match_service.get_active_flow()
	if flow == "classic":
		var status: String = str(payload.get("status", "")).to_lower()
		var common_count: int = (_as_array(payload.get("commonSongIDs", []))).size()
		var message: String = _clean_status_text(payload.get("message", ""))
		if not message.is_empty():
			_append_status(message)
		elif status == "waiting":
			_append_status("Classic match queued. Waiting for another player...")
		elif status == "selecting":
			_append_status("Classic match found. Choose a shared track.")
		elif status == "active":
			_append_status("Classic match is starting.")
		if status == "selecting" and common_count > 0 and not _classic_selection_presented:
			_classic_selection_presented = true
			call_deferred("_show_shared_song_selection")
		elif status != "selecting":
			_classic_selection_presented = false
	else:
		var status: String = str(payload.get("status", "waiting")).to_upper()
		_append_status("Custom match status: %s" % status)
	_refresh_lobby_controls()


func _on_lobby_updated(lobby: Dictionary) -> void:
	if lobby.has("lobbyID"):
		_on_steam_lobby_updated(lobby)
		return
	var flow: String = AppState.match_service.get_active_flow()
	if flow == "classic":
		var common_count: int = (lobby.get("commonSongIDs", []) as Array).size()
		_share_code_label.text = "Shared tracks: %d" % common_count
		if str(lobby.get("status", "")).to_lower() == "selecting" and common_count > 0 and not _classic_selection_presented:
			_classic_selection_presented = true
			call_deferred("_show_shared_song_selection")
		elif str(lobby.get("status", "")).to_lower() != "selecting":
			_classic_selection_presented = false
	else:
		_share_code_label.text = ""
	_refresh_lobby_controls()


func _on_steam_lobby_updated(lobby: Dictionary) -> void:
	if not _steam_lobby_active():
		_refresh_lobby_controls()
		return
	var lobby_id := str(lobby.get("lobbyID", ""))
	_share_code_label.text = "Steam lobby: %s" % lobby_id if not lobby_id.is_empty() else ""
	var reason := str(lobby.get("reason", "")).strip_edges()
	if reason == "created":
		_append_status("Steam party created. Invite a friend or choose a song.")
		if _pending_steam_invite_after_lobby:
			_pending_steam_invite_after_lobby = false
			call_deferred("_show_steam_friend_selection")
	elif reason == "joined":
		_append_status("Joined Steam party.")
	_refresh_lobby_controls()


func _on_steam_lobby_matchmaking_updated(payload: Dictionary) -> void:
	var status := str(payload.get("status", payload.get("reason", ""))).strip_edges()
	if status in ["creating", "joining"]:
		_append_status("Steam party %s..." % status)
	_refresh_lobby_controls()


func _on_start_time_received(start_time: float) -> void:
	_append_status("Shared start time received: %.3f" % start_time)


func _on_session_state_changed(active: bool, _is_host: bool) -> void:
	if active:
		_append_status("Shared match start received.")
	else:
		_append_status("Round submission completed.")
	_refresh_lobby_controls()


func _on_selection_changed(selection: Dictionary) -> void:
	var song_id: String = str(selection.get("song_id", ""))
	if song_id.is_empty():
		_selection_label.text = "Selection: not set"
		%SelectedJacket.visible = false
	else:
		var song: Dictionary = ContentRegistry.get_song(song_id)
		%SelectedJacket.visible = true
		%SelectedJacket.texture = SongJacketService.texture_for_song(song)
		_selection_label.text = "Selection: %s  •  %s  •  %s" % [
			str(song.get("display_name", song_id)),
			str(selection.get("difficulty", "")),
			GameModeConfig.get_short_label(str(selection.get("mode", GameModeConfig.DEFAULT_MODE))),
		]
	_refresh_lobby_controls()


func _append_status(message: String) -> void:
	message = _clean_status_text(message)
	if message.is_empty():
		return
	var stamped_message: String = "[%s] %s" % [Time.get_time_string_from_system(), message]
	print("[multiplayer] %s" % stamped_message)
	_status_history.append(stamped_message)
	while _status_history.size() > 8:
		_status_history.remove_at(0)
	_status_label.text = "\n".join(_status_history)
	call_deferred("_scroll_status_to_bottom")


func _clean_status_text(value: Variant) -> String:
	if value == null:
		return ""
	var text := str(value).strip_edges()
	if text.is_empty() or text == "<null>":
		return ""
	return text


func _as_array(value: Variant) -> Array:
	if value is Array:
		return (value as Array).duplicate(true)
	return []


func _on_back_button_pressed() -> void:
	AppState.match_service.close_session()
	if AppState.steam_lobby_service != null and AppState.steam_lobby_service.is_lobby_active():
		AppState.steam_lobby_service.leave_party()
	back_requested.emit()


func _on_authenticate_button_pressed() -> void:
	if OS.has_feature("android"):
		_append_status("Connecting to Google Play Games...")
	elif Engine.has_singleton("Steam") or OS.has_feature("windows") or OS.has_feature("macos") or OS.has_feature("linuxbsd"):
		_append_status("Connecting account...")
	AppState.match_service.authenticate_current_platform()


func _on_classic_matchmake_button_pressed() -> void:
	if not AppState.match_service.is_authenticated():
		_append_status("Connect your account first.")
		return
	_show_selection_overlay(
		"SELECT DIFFICULTY",
		"Classic multiplayer uses mapped charts and shared track selection.",
		DIFFICULTIES,
		Callable(self, "_on_classic_difficulty_selected")
	)


func _on_steam_invite_button_pressed() -> void:
	if not AppState.match_service.is_authenticated():
		_append_status("Connect your account first.")
		return
	if not _steam_invite_available():
		_append_status("Steam invites are unavailable until Steamworks is initialized.")
		return
	if AppState.steam_lobby_service == null:
		_append_status("Steam lobby multiplayer is not configured.")
		return
	if not AppState.steam_lobby_service.is_lobby_active():
		_pending_steam_invite_after_lobby = true
		_append_status("Creating Steam party...")
		AppState.steam_lobby_service.create_party()
		_refresh_lobby_controls()
		return
	if not AppState.steam_lobby_service.is_party_leader():
		_append_status("Only the Steam party leader can invite friends.")
		return
	_show_steam_friend_selection()


func _on_create_lobby_button_pressed() -> void:
	if not AppState.match_service.is_authenticated():
		_append_status("Connect your account first.")
		return
	if str(AppState.match_service.get_current_selection().get("song_id", "")).is_empty():
		_pending_custom_queue_after_selection = true
		_show_song_selection()
		return
	_append_status("Searching custom matchmaking queue...")
	AppState.match_service.start_custom_matchmaking()


func _on_poll_matchmake_button_pressed() -> void:
	_refresh_lobby_controls()


func _on_join_lobby_button_pressed() -> void:
	return


func _on_host_session_button_pressed() -> void:
	return


func _on_join_session_button_pressed() -> void:
	return


func _on_select_track_button_pressed() -> void:
	if _steam_lobby_active():
		if AppState.steam_lobby_service.is_party_leader():
			_show_song_selection()
		else:
			_append_status("The Steam party leader selects the song, mode, and difficulty.")
		return
	if AppState.match_service.get_active_flow() == "classic" and not AppState.match_service.get_classic_common_songs().is_empty():
		_show_shared_song_selection()
		return
	_show_song_selection()


func _on_ready_button_pressed() -> void:
	if _steam_lobby_active():
		var local_entry: Dictionary = AppState.steam_lobby_service.get_local_player_entry()
		var local_ready: bool = bool(local_entry.get("is_ready", local_entry.get("ready", false)))
		if AppState.steam_lobby_service.is_party_leader() and AppState.steam_lobby_service.can_start_round():
			AppState.steam_lobby_service.start_round()
			return
		AppState.steam_lobby_service.set_ready_state(not local_ready)
		return
	var local_entry: Dictionary = AppState.match_service.get_local_player_entry()
	var current_ready: bool = bool(local_entry.get("is_ready", false))
	AppState.match_service.set_ready_state(not current_ready)


func _refresh_lobby_controls() -> void:
	var is_authenticated: bool = AppState.match_service.is_authenticated()
	if _steam_lobby_active():
		_refresh_steam_lobby_controls(is_authenticated)
		return
	var flow: String = AppState.match_service.get_active_flow()
	var phase: String = AppState.match_service.get_current_phase()
	var local_entry: Dictionary = AppState.match_service.get_local_player_entry()
	var local_ready: bool = bool(local_entry.get("is_ready", false))
	var classic_busy: bool = flow == "classic" and phase in ["searching", "waiting", "selecting", "active"]
	var custom_busy: bool = flow == "custom" and phase in ["searching", "waiting", "ready", "active", "finished"]
	var steam_invite_ready := _steam_invite_available()
	%AuthenticateButton.text = "ACCOUNT CONNECTED" if is_authenticated else "CONNECT ACCOUNT"
	%AuthenticateButton.disabled = is_authenticated
	%SelectTrackButton.disabled = not is_authenticated or classic_busy
	%ReadyButton.disabled = not is_authenticated or (flow == "idle")
	%ReadyButton.text = "UNREADY" if local_ready else "READY UP"
	%SteamInviteButton.visible = steam_invite_ready and is_authenticated
	%SteamInviteButton.disabled = not steam_invite_ready or not is_authenticated or custom_busy or classic_busy
	_lobby_state_label.text = "Flow: %s  •  Phase: %s  •  Shared tracks: %d" % [
		flow if not flow.is_empty() else "idle",
		phase,
		AppState.match_service.get_classic_common_songs().size(),
	]
	%ClassicMatchmakeButton.text = "SEARCHING CLASSIC MATCH..." if classic_busy else "QUEUE CLASSIC MATCH"
	%CreateLobbyButton.text = "SEARCHING CUSTOM MATCH..." if custom_busy else "QUEUE CUSTOM MATCH"
	%ClassicMatchmakeButton.disabled = not is_authenticated or custom_busy or classic_busy
	%CreateLobbyButton.disabled = not is_authenticated or classic_busy or custom_busy


func _refresh_steam_lobby_controls(is_authenticated: bool) -> void:
	var service = AppState.steam_lobby_service
	var phase: String = service.get_current_phase()
	var local_entry: Dictionary = service.get_local_player_entry()
	var local_ready: bool = bool(local_entry.get("is_ready", local_entry.get("ready", false)))
	var is_leader: bool = service.is_party_leader()
	var selection: Dictionary = service.get_current_selection()
	var selected_song_id := str(selection.get("song_id", ""))
	%AuthenticateButton.text = "ACCOUNT CONNECTED" if is_authenticated else "CONNECT ACCOUNT"
	%AuthenticateButton.disabled = is_authenticated
	%ClassicMatchmakeButton.text = "QUEUE CLASSIC MATCH (Desktop & Mobile)"
	%CreateLobbyButton.text = "QUEUE CUSTOM MATCH (Desktop & Mobile)"
	%ClassicMatchmakeButton.disabled = true
	%CreateLobbyButton.disabled = true
	%SteamInviteButton.visible = true
	%SteamInviteButton.disabled = not is_authenticated or not is_leader
	%SteamInviteButton.text = "INVITE STEAM FRIEND" if is_leader else "WAITING FOR PARTY LEADER"
	%SelectTrackButton.disabled = not is_authenticated or not is_leader or phase == "active"
	%SelectTrackButton.text = "CHANGE SONG / MODE / DIFFICULTY" if not selected_song_id.is_empty() else "SELECT SONG / MODE / DIFFICULTY"
	%ReadyButton.disabled = not is_authenticated or selected_song_id.is_empty() or phase == "active"
	if is_leader and service.can_start_round():
		%ReadyButton.text = "START STEAM SONG"
	else:
		%ReadyButton.text = "UNREADY" if local_ready else "READY UP"
	_lobby_state_label.text = "Flow: steam lobby  •  Phase: %s  •  Leader: %s" % [
		phase,
		"YOU" if is_leader else _steam_leader_display_name(),
	]
	if selected_song_id.is_empty():
		_selection_label.text = "Selection: party leader has not selected a song"
		%SelectedJacket.visible = false
	else:
		var song: Dictionary = ContentRegistry.get_song(selected_song_id)
		%SelectedJacket.visible = true
		%SelectedJacket.texture = SongJacketService.texture_for_song(song)
		_selection_label.text = "Selection: %s  •  %s  •  %s" % [
			str(song.get("display_name", selected_song_id)),
			str(selection.get("difficulty", "")),
			GameModeConfig.get_short_label(str(selection.get("mode", GameModeConfig.DEFAULT_MODE))),
		]


func _show_song_selection() -> void:
	if _songs.is_empty():
		_append_status("No songs are available in the content manifest.")
		return
	_show_selection_overlay(
		"SELECT TRACK",
		"Choose the Steam party song" if _steam_lobby_active() else "Choose the custom multiplayer song",
		_songs,
		Callable(self, "_on_song_selected"),
		func(song: Dictionary) -> String:
			return str(song.get("display_name", "Unknown"))
	)


func _show_shared_song_selection() -> void:
	var song_options: Array[Dictionary] = []
	for song_id in AppState.match_service.get_classic_common_songs():
		var song: Dictionary = ContentRegistry.get_song(song_id)
		if not song.is_empty():
			song_options.append(song)
	if song_options.is_empty():
		_append_status("No shared tracks are available yet.")
		return
	var selection: Dictionary = AppState.match_service.get_current_selection()
	_show_selection_overlay(
		"SELECT SHARED TRACK",
		"Both players choose from %s / %s shared tracks." % [
			GameModeConfig.get_short_label(str(selection.get("mode", GameModeConfig.DEFAULT_MODE))),
			str(selection.get("difficulty", "")),
		],
		song_options,
		Callable(self, "_on_shared_song_selected"),
		func(song: Dictionary) -> String:
			return str(song.get("display_name", "Unknown"))
	)


func _show_steam_friend_selection() -> void:
	if not _steam_lobby_active():
		_append_status("Create a Steam party before inviting friends.")
		return
	var options: Array[Dictionary] = []
	for friend in SteamClient.get_invitable_friends():
		options.append(friend.duplicate(true))
	options.append({
		"fallback": true,
		"display_name": "Open Steam Invite Overlay",
	})
	_show_selection_overlay(
		"SELECT STEAM FRIEND",
		"Invite a friend to this Steam party.",
		options,
		Callable(self, "_on_steam_invite_friend_selected"),
		func(option: Dictionary) -> String:
			return _steam_friend_label(option)
	)


func _show_mode_selection() -> void:
	if _selected_song.is_empty():
		return
	var available_modes: Array[String] = ContentRegistry.get_supported_modes(_selected_song)
	if available_modes.is_empty():
		_append_status("No chart modes were found for %s." % str(_selected_song.get("display_name", "this track")))
		return
	_pending_mode = available_modes[0]
	_show_selection_overlay(
		"SELECT MODE",
		str(_selected_song.get("display_name", "Unknown")),
		available_modes,
		Callable(self, "_on_mode_selected"),
		func(mode_id: String) -> String:
			return GameModeConfig.get_display_name(mode_id)
	)


func _show_difficulty_selection() -> void:
	if _selected_song.is_empty():
		return
	var difficulties: Array[String] = ContentRegistry.get_supported_difficulties(_selected_song, _pending_mode)
	if difficulties.is_empty():
		_append_status("No %s difficulties were found for %s." % [GameModeConfig.get_short_label(_pending_mode), str(_selected_song.get("display_name", "this track"))])
		return
	_show_selection_overlay(
		"SELECT DIFFICULTY",
		"%s  •  %s" % [str(_selected_song.get("display_name", "Unknown")), GameModeConfig.get_short_label(_pending_mode)],
		difficulties,
		Callable(self, "_on_difficulty_selected")
	)


func _show_selection_overlay(title: String, subtitle: String, options: Array, callback: Callable, label_builder: Callable = Callable()) -> void:
	%OverlayDim.visible = true
	%SelectionCenter.visible = true
	%SelectionTitleLabel.text = title
	%SelectionSubtitleLabel.text = subtitle
	%SelectionScroll.scroll_vertical = 0
	for child in %SelectionButtons.get_children():
		if child != %SelectionCancelButton:
			child.queue_free()
	for option in options:
		var button: Button = MobileScrollButtonScript.new() if AppState.is_mobile_platform() else Button.new()
		button.text = label_builder.call(option) if label_builder.is_valid() else str(option)
		button.custom_minimum_size = Vector2(0, HDTheme.overlay_metrics(get_viewport_rect().size)["button_height"])
		button.add_theme_stylebox_override("normal", HDTheme.button_style(true))
		button.add_theme_stylebox_override("hover", HDTheme.button_style(true))
		button.add_theme_stylebox_override("pressed", HDTheme.button_style(true))
		button.add_theme_font_size_override("font_size", HDTheme.text_size("button_secondary", get_viewport_rect().size))
		if option is Dictionary and not str((option as Dictionary).get("id", "")).is_empty():
			button.icon = SongJacketService.texture_for_song(option)
			button.expand_icon = true
			button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(func() -> void:
			callback.call(option)
		)
		%SelectionButtons.add_child(button)
	call_deferred("_refresh_menu_navigation")


func _hide_selection_overlay() -> void:
	%OverlayDim.visible = false
	%SelectionCenter.visible = false
	for child in %SelectionButtons.get_children():
		if child != %SelectionCancelButton:
			child.queue_free()
	call_deferred("_refresh_menu_navigation")


func _on_song_selected(song: Dictionary) -> void:
	_selected_song = song.duplicate(true)
	_show_mode_selection()


func _on_shared_song_selected(song: Dictionary) -> void:
	_selected_song = song.duplicate(true)
	AppState.match_service.select_classic_song(str(song.get("id", "")))
	_hide_selection_overlay()


func _on_mode_selected(mode_id: String) -> void:
	_pending_mode = mode_id
	_show_difficulty_selection()


func _on_difficulty_selected(difficulty: String) -> void:
	if _selected_song.is_empty():
		return
	if _steam_lobby_active():
		AppState.steam_lobby_service.set_song_selection(str(_selected_song.get("id", "")), difficulty, _pending_mode)
		_hide_selection_overlay()
		_append_status("Steam party selection updated.")
		return
	AppState.match_service.set_song_selection(str(_selected_song.get("id", "")), difficulty, _pending_mode)
	_hide_selection_overlay()
	var should_queue_custom := _pending_custom_queue_after_selection
	_pending_custom_queue_after_selection = false
	if should_queue_custom:
		_append_status("Selection saved. Searching custom matchmaking queue...")
		AppState.match_service.start_custom_matchmaking()
	else:
		_append_status("Selection saved. Queue a custom match when ready.")


func _on_steam_invite_friend_selected(option: Dictionary) -> void:
	if bool(option.get("fallback", false)):
		var overlay_result: Dictionary = AppState.steam_lobby_service.open_invite_overlay() if _steam_lobby_active() else {"message": "No Steam party is active."}
		_append_status(str(overlay_result.get("message", "")))
		_hide_selection_overlay()
		return
	var friend_id := str(option.get("steam_id", "")).strip_edges()
	var friend_name := str(option.get("display_name", "Steam friend"))
	var sent: bool = AppState.steam_lobby_service.invite_friend(friend_id) if _steam_lobby_active() else false
	if sent:
		_append_status("Steam lobby invite sent to %s." % friend_name)
		_hide_selection_overlay()
		return
	_append_status("Direct Steam lobby invite failed. Opening the Steam invite overlay instead.")
	var overlay_result: Dictionary = AppState.steam_lobby_service.open_invite_overlay() if _steam_lobby_active() else {"message": "No Steam party is active."}
	_append_status(str(overlay_result.get("message", "")))
	_hide_selection_overlay()


func _on_classic_difficulty_selected(difficulty: String) -> void:
	AppState.match_service.start_classic_matchmaking(difficulty)
	_hide_selection_overlay()


func _steam_friend_label(friend: Dictionary) -> String:
	if bool(friend.get("fallback", false)):
		return "OPEN STEAM INVITE OVERLAY"
	var label_parts: Array[String] = [str(friend.get("display_name", "Steam Friend"))]
	var song := str(friend.get("song", "")).strip_edges()
	var difficulty := str(friend.get("difficulty", "")).strip_edges()
	var mode_label := str(friend.get("mode_label", "")).strip_edges()
	var status := str(friend.get("status", "")).strip_edges()
	if not song.is_empty():
		label_parts.append(song)
		if not difficulty.is_empty() or not mode_label.is_empty():
			label_parts.append("%s / %s" % [difficulty, mode_label])
	elif not status.is_empty():
		label_parts.append(status)
	else:
		label_parts.append("Online" if bool(friend.get("is_online", false)) else "Offline")
	return "  •  ".join(label_parts)


func _steam_invite_available() -> bool:
	return not AppState.is_mobile_platform() and Engine.has_singleton("Steam") and SteamClient.is_ready()


func _on_selection_cancel_button_pressed() -> void:
	_pending_custom_queue_after_selection = false
	_pending_steam_invite_after_lobby = false
	_hide_selection_overlay()


func _accessible_songs() -> Array[Dictionary]:
	var songs: Array[Dictionary] = []
	for song_variant in ContentRegistry.get_progression_ordered_songs():
		if song_variant is Dictionary:
			var song: Dictionary = song_variant as Dictionary
			var song_id: String = str(song.get("id", ""))
			if ProgressionManager.is_song_multiplayer_accessible(song_id):
				songs.append(song.duplicate(true))
	return songs


func _apply_mobile_scroll_buttons() -> void:
	if not AppState.is_mobile_platform():
		return
	for button in [%BackButton, %AuthenticateButton, %ClassicMatchmakeButton, %SteamInviteButton, %CreateLobbyButton, %SelectTrackButton, %ReadyButton, %SelectionCancelButton]:
		button.set_script(MobileScrollButtonScript)


func _refresh_menu_navigation() -> void:
	if _menu_navigator != null:
		_menu_navigator.refresh_focusables()


func _scroll_status_to_bottom() -> void:
	if _status_scroll == null:
		return
	_status_scroll.scroll_vertical = int(maxf(0.0, _status_label.size.y - _status_scroll.size.y))


func _reset_main_scroll_to_top() -> void:
	if _main_scroll == null:
		return
	_main_scroll.scroll_vertical = 0
	await get_tree().process_frame
	if _main_scroll != null:
		_main_scroll.scroll_vertical = 0


func _steam_lobby_active() -> bool:
	return AppState.steam_lobby_service != null and AppState.steam_lobby_service.is_lobby_active()


func _steam_leader_display_name() -> String:
	if not _steam_lobby_active():
		return "Player"
	var leader_id := str(AppState.steam_lobby_service.leader_steam_id)
	for player_variant in AppState.steam_lobby_service.get_players():
		if player_variant is Dictionary:
			var player: Dictionary = player_variant as Dictionary
			if str(player.get("user_id", "")) == leader_id:
				return str(player.get("display_name", "Player"))
	return "Player"
