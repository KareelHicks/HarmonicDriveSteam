extends Node

const GameModeConfig = preload("res://scripts/gameplay/GameModeConfig.gd")

const DEFAULT_STEAM_APP_ID := 4709930
const CONNECT_PREFIX := "hdmp:v1"
const FRIEND_FLAG_IMMEDIATE := 4
const PERSONA_STATE_OFFLINE := 0
const LOBBY_TYPE_FRIENDS_ONLY := 1
const P2P_SEND_RELIABLE := 2
const STEAM_INIT_RETRY_INTERVAL_MSEC := 5000

signal steam_ready_changed(ready: bool, status: String)
signal steam_invite_join_requested(invite: Dictionary)
signal steam_lobby_join_requested(lobby_id: String, friend_id: String)
signal steam_lobby_created(success: bool, lobby_id: String)
signal steam_lobby_joined(lobby_id: String, response: int)
signal steam_lobby_chat_updated(lobby_id: String, changed_id: String, making_change_id: String, state: int)
signal steam_lobby_data_updated(lobby_id: String, member_id: String, success: bool)
signal steam_lobby_kicked(lobby_id: String, admin_id: String, kicked_due_to_disconnect: bool)
signal steam_p2p_session_requested(steam_id: String)
signal steam_p2p_session_failed(steam_id: String, error: int)

var _initialized: bool = false
var _status_text: String = "Steam client not initialized."
var _awaiting_auto_init: bool = false
var _auto_init_deadline_msec: int = 0
var _awaiting_identity_ready: bool = false
var _identity_deadline_msec: int = 0
var _next_init_retry_msec: int = 0
var _join_signal_connected: bool = false
var _lobby_signals_connected: bool = false
var _p2p_signals_connected: bool = false
var _launch_invite_emitted: bool = false
var _launch_lobby_emitted: bool = false


func _ready() -> void:
	if not _is_desktop_platform():
		return
	if Engine.has_singleton("SteamServer") and not Engine.has_singleton("Steam"):
		_status_text = "GodotSteam Server is installed, but the game needs the standard GodotSteam client GDExtension."
		return
	if not Engine.has_singleton("Steam"):
		_status_text = _missing_steam_singleton_message()
		return
	if _uses_auto_initialization():
		_begin_auto_init_wait()
		return
	_initialize_steam()


func _process(_delta: float) -> void:
	if _awaiting_auto_init:
		_poll_auto_init()
	if _awaiting_identity_ready:
		_poll_identity_ready()
	if not _initialized:
		_poll_init_retry()
		return
	var steam: Object = Engine.get_singleton("Steam")
	if steam != null and steam.has_method("run_callbacks"):
		steam.call("run_callbacks")


func is_ready() -> bool:
	return _initialized


func get_status_text() -> String:
	return _status_text


func get_app_id() -> int:
	if ProjectSettings.has_setting("harmonic_drive/steam/app_id"):
		return int(ProjectSettings.get_setting("harmonic_drive/steam/app_id"))
	return DEFAULT_STEAM_APP_ID


static func build_multiplayer_connect_string(difficulty: String, mode: String, sender_steam_id: String = "", nonce: String = "") -> String:
	var safe_mode: String = mode if GameModeConfig.is_valid(mode) else GameModeConfig.DEFAULT_MODE
	var safe_nonce := nonce.strip_edges()
	if safe_nonce.is_empty():
		safe_nonce = "%d_%d" % [Time.get_unix_time_from_system(), Time.get_ticks_msec()]
	var fields: Dictionary = {
		"flow": "classic",
		"difficulty": difficulty.strip_edges(),
		"mode": safe_mode,
		"sender": sender_steam_id.strip_edges(),
		"nonce": safe_nonce,
	}
	var parts: Array[String] = [CONNECT_PREFIX]
	for key_variant in ["flow", "difficulty", "mode", "sender", "nonce"]:
		var key := str(key_variant)
		parts.append("%s=%s" % [key, str(fields.get(key, "")).uri_encode()])
	return "|".join(parts)


static func parse_multiplayer_connect_string(value: String) -> Dictionary:
	var trimmed := value.strip_edges()
	if trimmed.is_empty():
		return {"ok": false, "message": "Steam invite is empty."}
	var parts := trimmed.split("|", false)
	if parts.is_empty() or str(parts[0]) != CONNECT_PREFIX:
		return {"ok": false, "message": "Steam invite is not for Harmonic Drive multiplayer."}
	var fields: Dictionary = {}
	for index in range(1, parts.size()):
		var segment := str(parts[index])
		var separator_index := segment.find("=")
		if separator_index <= 0:
			continue
		var key := segment.substr(0, separator_index)
		var encoded_value := segment.substr(separator_index + 1)
		fields[key] = encoded_value.uri_decode()
	var flow := str(fields.get("flow", ""))
	var difficulty := str(fields.get("difficulty", "")).strip_edges()
	var mode := str(fields.get("mode", "")).strip_edges()
	if flow != "classic":
		return {"ok": false, "message": "Steam invite uses an unsupported multiplayer flow."}
	if difficulty.is_empty():
		return {"ok": false, "message": "Steam invite is missing a difficulty."}
	if not GameModeConfig.is_valid(mode):
		return {"ok": false, "message": "Steam invite uses an unsupported game mode."}
	return {
		"ok": true,
		"flow": flow,
		"difficulty": difficulty,
		"mode": mode,
		"sender": str(fields.get("sender", "")).strip_edges(),
		"nonce": str(fields.get("nonce", "")).strip_edges(),
		"connect": trimmed,
	}


static func parse_launch_invite_text(value: String) -> Dictionary:
	var candidates: Array[String] = [value]
	var decoded_value: String = value.uri_decode()
	if decoded_value != value:
		candidates.append(decoded_value)
	for candidate_text in candidates:
		var candidate: String = _extract_launch_connect_candidate(candidate_text)
		if candidate.is_empty():
			continue
		var parsed: Dictionary = parse_multiplayer_connect_string(candidate)
		if bool(parsed.get("ok", false)):
			return parsed
	return {}


static func parse_launch_invite_from_args(args: Array) -> Dictionary:
	for index in args.size():
		var arg_text: String = str(args[index])
		var parsed: Dictionary = parse_launch_invite_text(arg_text)
		if bool(parsed.get("ok", false)):
			return parsed
		if _is_launch_connect_flag(arg_text) and index + 1 < args.size():
			parsed = parse_launch_invite_text(str(args[index + 1]))
			if bool(parsed.get("ok", false)):
				return parsed
		var assignment_index: int = arg_text.find("=")
		if assignment_index > 0 and _is_launch_connect_flag(arg_text.substr(0, assignment_index)):
			parsed = parse_launch_invite_text(arg_text.substr(assignment_index + 1))
			if bool(parsed.get("ok", false)):
				return parsed
	return {}


static func parse_lobby_launch_text(value: String) -> Dictionary:
	var candidates: Array[String] = [value]
	var decoded_value: String = value.uri_decode()
	if decoded_value != value:
		candidates.append(decoded_value)
	for candidate_text in candidates:
		var lobby_id: String = _extract_launch_lobby_candidate(candidate_text)
		if _is_valid_lobby_id(lobby_id):
			return {"ok": true, "lobby_id": lobby_id}
	return {}


static func parse_lobby_launch_from_args(args: Array) -> Dictionary:
	for index in args.size():
		var arg_text: String = str(args[index])
		var parsed: Dictionary = parse_lobby_launch_text(arg_text)
		if bool(parsed.get("ok", false)):
			return parsed
		if _is_launch_lobby_flag(arg_text) and index + 1 < args.size():
			parsed = parse_lobby_launch_text(str(args[index + 1]))
			if bool(parsed.get("ok", false)):
				return parsed
		var assignment_index: int = arg_text.find("=")
		if assignment_index > 0 and _is_launch_lobby_flag(arg_text.substr(0, assignment_index)):
			parsed = parse_lobby_launch_text(arg_text.substr(assignment_index + 1))
			if bool(parsed.get("ok", false)):
				return parsed
	return {}


func get_steam_id() -> String:
	var steam: Object = _steam_singleton()
	if steam == null or not steam.has_method("getSteamID"):
		return ""
	var steam_id := str(steam.call("getSteamID")).strip_edges()
	return "" if steam_id == "0" else steam_id


func get_persona_name() -> String:
	var steam: Object = _steam_singleton()
	if steam == null or not steam.has_method("getPersonaName"):
		return ""
	return str(steam.call("getPersonaName")).strip_edges()


func get_friend_display_name(steam_id: String) -> String:
	var steam: Object = _steam_singleton()
	if steam == null or not steam.has_method("getFriendPersonaName"):
		return ""
	var numeric_id := int(steam_id)
	if numeric_id <= 0:
		return ""
	return str(steam.call("getFriendPersonaName", numeric_id)).strip_edges()


func get_launch_invite() -> Dictionary:
	var steam: Object = _steam_singleton()
	if steam != null and steam.has_method("getLaunchCommandLine"):
		var command_line: String = str(steam.call("getLaunchCommandLine"))
		var launch_invite: Dictionary = parse_launch_invite_text(command_line)
		if bool(launch_invite.get("ok", false)):
			launch_invite["source"] = "steam_launch_command_line"
			return launch_invite
	var args: Array[String] = []
	for arg_variant in OS.get_cmdline_args():
		args.append(str(arg_variant))
	var args_invite: Dictionary = parse_launch_invite_from_args(args)
	if bool(args_invite.get("ok", false)):
		args_invite["source"] = "os_command_line"
		return args_invite
	return {}


func get_launch_lobby_invite() -> Dictionary:
	var steam: Object = _steam_singleton()
	if steam != null and steam.has_method("getLaunchCommandLine"):
		var command_line: String = str(steam.call("getLaunchCommandLine"))
		var launch_lobby: Dictionary = parse_lobby_launch_text(command_line)
		if bool(launch_lobby.get("ok", false)):
			launch_lobby["source"] = "steam_launch_command_line"
			return launch_lobby
	var args: Array[String] = []
	for arg_variant in OS.get_cmdline_args():
		args.append(str(arg_variant))
	var args_lobby: Dictionary = parse_lobby_launch_from_args(args)
	if bool(args_lobby.get("ok", false)):
		args_lobby["source"] = "os_command_line"
		return args_lobby
	return {}


func set_rich_presence(payload: Dictionary) -> bool:
	var steam: Object = _steam_singleton()
	if steam == null or not steam.has_method("setRichPresence"):
		return false
	var applied := false
	for key_variant in payload.keys():
		var key := str(key_variant).strip_edges()
		if key.is_empty():
			continue
		var value := ""
		if payload[key_variant] != null:
			value = str(payload[key_variant])
		var result: Variant = steam.call("setRichPresence", key, value)
		applied = applied or not (result is bool) or bool(result)
	return applied


func clear_multiplayer_presence() -> void:
	var steam: Object = _steam_singleton()
	if steam != null and steam.has_method("clearRichPresence"):
		steam.call("clearRichPresence")
		return
	set_rich_presence({
		"connect": "",
		"status": "",
		"song": "",
		"difficulty": "",
		"mode": "",
		"mode_label": "",
		"multiplayer": "",
		"steam_player_group": "",
		"steam_player_group_size": "",
		"steam_display": "",
	})


func set_menu_presence(status: String = "In Menus") -> void:
	clear_multiplayer_presence()
	set_rich_presence({
		"status": status,
		"steam_display": status,
	})


func set_gameplay_presence(song: Dictionary, difficulty: String, mode: String, is_multiplayer: bool) -> void:
	var song_name := str(song.get("display_name", song.get("title", song.get("id", "Unknown Song"))))
	var mode_label := GameModeConfig.get_short_label(mode)
	var status := "Playing Multiplayer" if is_multiplayer else "Playing"
	var display := "%s: %s [%s / %s]" % [status, song_name, difficulty, mode_label]
	set_rich_presence({
		"connect": "",
		"steam_player_group": "",
		"steam_player_group_size": "",
		"status": status,
		"song": song_name,
		"difficulty": difficulty,
		"mode": mode,
		"mode_label": mode_label,
		"multiplayer": "1" if is_multiplayer else "0",
		"steam_display": display,
	})


func set_multiplayer_presence(status: String, difficulty: String, mode: String, connect_string: String = "", group: String = "", group_size: int = 0) -> void:
	var payload: Dictionary = {
		"status": status,
		"song": "",
		"difficulty": difficulty,
		"mode": mode,
		"mode_label": GameModeConfig.get_short_label(mode),
		"connect": connect_string,
		"steam_player_group": group,
		"steam_player_group_size": str(group_size) if group_size > 0 else "",
		"multiplayer": "1",
		"steam_display": "%s [%s / %s]" % [status, difficulty, GameModeConfig.get_short_label(mode)],
	}
	set_rich_presence(payload)


func get_invitable_friends() -> Array[Dictionary]:
	var friends: Array[Dictionary] = []
	var steam: Object = _steam_singleton()
	if steam == null or not steam.has_method("getFriendCount") or not steam.has_method("getFriendByIndex"):
		return friends
	var count: int = int(steam.call("getFriendCount", FRIEND_FLAG_IMMEDIATE)) if _method_arg_count(steam, "getFriendCount") != 0 else int(steam.call("getFriendCount"))
	for index in count:
		var friend_id_variant: Variant = steam.call("getFriendByIndex", index, FRIEND_FLAG_IMMEDIATE) if _method_arg_count(steam, "getFriendByIndex") != 1 else steam.call("getFriendByIndex", index)
		var friend_id := str(friend_id_variant).strip_edges()
		if friend_id.is_empty() or friend_id == "0":
			continue
		var persona_state := PERSONA_STATE_OFFLINE
		if steam.has_method("getFriendPersonaState"):
			persona_state = int(steam.call("getFriendPersonaState", int(friend_id)))
		var display_name := friend_id
		if steam.has_method("getFriendPersonaName"):
			display_name = str(steam.call("getFriendPersonaName", int(friend_id))).strip_edges()
		if display_name.is_empty():
			display_name = friend_id
		var presence := _friend_presence_payload(steam, friend_id)
		friends.append({
			"steam_id": friend_id,
			"display_name": display_name,
			"persona_state": persona_state,
			"is_online": persona_state != PERSONA_STATE_OFFLINE,
			"status": str(presence.get("status", "")),
			"song": str(presence.get("song", "")),
			"difficulty": str(presence.get("difficulty", "")),
			"mode": str(presence.get("mode", "")),
			"mode_label": str(presence.get("mode_label", "")),
		})
	friends.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_online := bool(a.get("is_online", false))
		var b_online := bool(b.get("is_online", false))
		if a_online != b_online:
			return a_online
		return str(a.get("display_name", "")).to_lower() < str(b.get("display_name", "")).to_lower()
	)
	return friends


func send_game_invite(steam_id: String, connect_string: String) -> bool:
	var steam: Object = _steam_singleton()
	if steam == null or not steam.has_method("inviteUserToGame"):
		return false
	var numeric_id := int(steam_id)
	if numeric_id <= 0 or connect_string.strip_edges().is_empty():
		return false
	var result: Variant = steam.call("inviteUserToGame", numeric_id, connect_string)
	return bool(result) if result is bool else true


func is_overlay_enabled() -> bool:
	var steam: Object = _steam_singleton()
	if steam == null:
		return false
	if not steam.has_method("isOverlayEnabled"):
		return true
	return bool(steam.call("isOverlayEnabled"))


func open_invite_overlay_result(connect_string: String) -> Dictionary:
	var steam: Object = _steam_singleton()
	if steam == null:
		return {
			"requested": false,
			"overlay_enabled": false,
			"method": "",
			"message": "Steam overlay is unavailable because Steamworks is not initialized.",
		}
	if steam.has_method("isOverlayEnabled") and not bool(steam.call("isOverlayEnabled")):
		var disabled_message := "Steam overlay is disabled or unavailable in this runtime."
		if OS.has_feature("editor"):
			disabled_message += " Running from the Godot editor can prevent Steam from injecting the overlay; validate with an exported build launched through Steam."
		return {
			"requested": false,
			"overlay_enabled": false,
			"method": "isOverlayEnabled",
			"message": disabled_message,
		}
	if steam.has_method("activateGameOverlayInviteDialogConnectString") and not connect_string.strip_edges().is_empty():
		var result: Variant = steam.call("activateGameOverlayInviteDialogConnectString", connect_string)
		if not (result is bool) or bool(result):
			return {
				"requested": true,
				"overlay_enabled": true,
				"method": "activateGameOverlayInviteDialogConnectString",
				"message": "Steam invite overlay requested. If it does not appear, run an exported build through Steam and confirm the Steam Overlay is enabled for this app.",
			}
	if steam.has_method("activateGameOverlay"):
		var result: Variant = steam.call("activateGameOverlay", "Friends")
		if not (result is bool) or bool(result):
			return {
				"requested": true,
				"overlay_enabled": true,
				"method": "activateGameOverlay",
				"message": "Steam Friends overlay requested. If it does not appear, run an exported build through Steam and confirm the Steam Overlay is enabled for this app.",
			}
	return {
		"requested": false,
		"overlay_enabled": true,
		"method": "",
		"message": "Steam overlay APIs are unavailable for this runtime.",
	}


func open_invite_overlay(connect_string: String) -> bool:
	return bool(open_invite_overlay_result(connect_string).get("requested", false))


func create_steam_lobby(max_members: int = 2) -> bool:
	var steam: Object = _steam_singleton()
	if steam == null or not steam.has_method("createLobby"):
		return false
	steam.call("createLobby", LOBBY_TYPE_FRIENDS_ONLY, max_members)
	return true


func join_steam_lobby(lobby_id: String) -> bool:
	var steam: Object = _steam_singleton()
	if steam == null or not steam.has_method("joinLobby"):
		return false
	var numeric_lobby_id := int(lobby_id)
	if numeric_lobby_id <= 0:
		return false
	steam.call("joinLobby", numeric_lobby_id)
	return true


func leave_steam_lobby(lobby_id: String) -> bool:
	var steam: Object = _steam_singleton()
	if steam == null or not steam.has_method("leaveLobby"):
		return false
	var numeric_lobby_id := int(lobby_id)
	if numeric_lobby_id <= 0:
		return false
	steam.call("leaveLobby", numeric_lobby_id)
	return true


func invite_user_to_lobby(steam_id: String, lobby_id: String) -> bool:
	var steam: Object = _steam_singleton()
	if steam == null or not steam.has_method("inviteUserToLobby"):
		return false
	var numeric_steam_id := int(steam_id)
	var numeric_lobby_id := int(lobby_id)
	if numeric_steam_id <= 0 or numeric_lobby_id <= 0:
		return false
	var result: Variant = steam.call("inviteUserToLobby", numeric_lobby_id, numeric_steam_id)
	if result is bool and bool(result):
		return true
	if result is bool and not bool(result):
		var reversed_result: Variant = steam.call("inviteUserToLobby", numeric_steam_id, numeric_lobby_id)
		return bool(reversed_result) if reversed_result is bool else true
	return true


func open_lobby_invite_overlay(lobby_id: String) -> Dictionary:
	var steam: Object = _steam_singleton()
	if steam == null:
		return {
			"requested": false,
			"overlay_enabled": false,
			"method": "",
			"message": "Steam overlay is unavailable because Steamworks is not initialized.",
		}
	var numeric_lobby_id := int(lobby_id)
	if numeric_lobby_id <= 0:
		return {
			"requested": false,
			"overlay_enabled": false,
			"method": "",
			"message": "Steam lobby ID is invalid.",
		}
	if steam.has_method("isOverlayEnabled") and not bool(steam.call("isOverlayEnabled")):
		var disabled_message := "Steam overlay is disabled or unavailable in this runtime."
		if OS.has_feature("editor"):
			disabled_message += " Running from the Godot editor can prevent Steam from injecting the overlay; validate with an exported build launched through Steam."
		return {
			"requested": false,
			"overlay_enabled": false,
			"method": "isOverlayEnabled",
			"message": disabled_message,
		}
	if steam.has_method("activateGameOverlayInviteDialog"):
		var result: Variant = steam.call("activateGameOverlayInviteDialog", numeric_lobby_id)
		if not (result is bool) or bool(result):
			return {
				"requested": true,
				"overlay_enabled": true,
				"method": "activateGameOverlayInviteDialog",
				"message": "Steam lobby invite overlay requested.",
			}
	if steam.has_method("activateGameOverlay"):
		var friends_result: Variant = steam.call("activateGameOverlay", "Friends")
		if not (friends_result is bool) or bool(friends_result):
			return {
				"requested": true,
				"overlay_enabled": true,
				"method": "activateGameOverlay",
				"message": "Steam Friends overlay requested.",
			}
	return {
		"requested": false,
		"overlay_enabled": true,
		"method": "",
		"message": "Steam lobby invite overlay APIs are unavailable for this runtime.",
	}


func set_lobby_data(lobby_id: String, key: String, value: String) -> bool:
	var steam: Object = _steam_singleton()
	if steam == null or not steam.has_method("setLobbyData"):
		return false
	var result: Variant = steam.call("setLobbyData", int(lobby_id), key, value)
	return bool(result) if result is bool else true


func get_lobby_data(lobby_id: String, key: String) -> String:
	var steam: Object = _steam_singleton()
	if steam == null or not steam.has_method("getLobbyData"):
		return ""
	return str(steam.call("getLobbyData", int(lobby_id), key))


func set_lobby_member_data(lobby_id: String, key: String, value: String) -> bool:
	var steam: Object = _steam_singleton()
	if steam == null or not steam.has_method("setLobbyMemberData"):
		return false
	var arg_count := _method_arg_count(steam, "setLobbyMemberData")
	var result: Variant = null
	if arg_count >= 3:
		result = steam.call("setLobbyMemberData", int(lobby_id), key, value)
	else:
		result = steam.call("setLobbyMemberData", key, value)
	return bool(result) if result is bool else true


func get_lobby_member_data(lobby_id: String, member_id: String, key: String) -> String:
	var steam: Object = _steam_singleton()
	if steam == null or not steam.has_method("getLobbyMemberData"):
		return ""
	return str(steam.call("getLobbyMemberData", int(lobby_id), int(member_id), key))


func get_lobby_owner(lobby_id: String) -> String:
	var steam: Object = _steam_singleton()
	if steam == null or not steam.has_method("getLobbyOwner"):
		return ""
	var owner := str(steam.call("getLobbyOwner", int(lobby_id))).strip_edges()
	return "" if owner == "0" else owner


func get_lobby_member_count(lobby_id: String) -> int:
	var steam: Object = _steam_singleton()
	if steam == null or not steam.has_method("getNumLobbyMembers"):
		return 0
	return int(steam.call("getNumLobbyMembers", int(lobby_id)))


func get_lobby_members(lobby_id: String) -> Array[String]:
	var members: Array[String] = []
	var steam: Object = _steam_singleton()
	if steam == null or not steam.has_method("getNumLobbyMembers") or not steam.has_method("getLobbyMemberByIndex"):
		return members
	var numeric_lobby_id := int(lobby_id)
	var count := int(steam.call("getNumLobbyMembers", numeric_lobby_id))
	for index in count:
		var member_id := str(steam.call("getLobbyMemberByIndex", numeric_lobby_id, index)).strip_edges()
		if not member_id.is_empty() and member_id != "0":
			members.append(member_id)
	return members


func allow_p2p_packet_relay(enabled: bool) -> bool:
	var steam: Object = _steam_singleton()
	if steam == null or not steam.has_method("allowP2PPacketRelay"):
		return false
	var result: Variant = steam.call("allowP2PPacketRelay", enabled)
	return bool(result) if result is bool else true


func accept_p2p_session(steam_id: String) -> bool:
	var steam: Object = _steam_singleton()
	if steam == null or not steam.has_method("acceptP2PSessionWithUser"):
		return false
	var numeric_steam_id := int(steam_id)
	if numeric_steam_id <= 0:
		return false
	var result: Variant = steam.call("acceptP2PSessionWithUser", numeric_steam_id)
	return bool(result) if result is bool else true


func send_p2p_packet(steam_id: String, data: PackedByteArray, send_type: int = P2P_SEND_RELIABLE, channel: int = 0) -> bool:
	var steam: Object = _steam_singleton()
	if steam == null or not steam.has_method("sendP2PPacket"):
		return false
	var numeric_steam_id := int(steam_id)
	if numeric_steam_id <= 0 or data.is_empty():
		return false
	var result: Variant = steam.call("sendP2PPacket", numeric_steam_id, data, send_type, channel)
	if result is bool:
		return bool(result)
	return true


func read_p2p_packets(channel: int = 0, max_packets: int = 16) -> Array[Dictionary]:
	var packets: Array[Dictionary] = []
	var steam: Object = _steam_singleton()
	if steam == null or not steam.has_method("getAvailableP2PPacketSize") or not steam.has_method("readP2PPacket"):
		return packets
	for _index in max_packets:
		var size_variant: Variant = steam.call("getAvailableP2PPacketSize", channel)
		var packet_size := 0
		if size_variant is Dictionary:
			var size_dict: Dictionary = size_variant as Dictionary
			packet_size = int(size_dict.get("size", size_dict.get("packet_size", size_dict.get("packetSize", 0))))
		else:
			packet_size = int(size_variant)
		if packet_size <= 0:
			break
		var packet_variant: Variant = steam.call("readP2PPacket", packet_size, channel)
		if not (packet_variant is Dictionary):
			continue
		var packet: Dictionary = packet_variant as Dictionary
		var data_variant: Variant = packet.get("data", packet.get("body", PackedByteArray()))
		var data := PackedByteArray()
		if data_variant is PackedByteArray:
			data = data_variant
		elif data_variant is Array:
			data = PackedByteArray(data_variant as Array)
		var remote_id := str(packet.get("steamIDRemote", packet.get("steam_id_remote", packet.get("remote_steam_id", packet.get("steam_id", ""))))).strip_edges()
		if remote_id.is_empty() or remote_id == "0":
			remote_id = str(packet.get("remote_id", packet.get("steamID", packet.get("id", "")))).strip_edges()
		if data.is_empty() or remote_id.is_empty() or remote_id == "0":
			continue
		packets.append({
			"steam_id": remote_id,
			"data": data,
			"channel": channel,
		})
	return packets


func _initialize_steam() -> void:
	var steam: Object = Engine.get_singleton("Steam")
	if steam == null:
		_status_text = "Steamworks client singleton is unavailable."
		return
	if _singleton_ready_for_identity(steam):
		_mark_steam_ready(steam)
		return
	var init_result: Variant = null
	if steam.has_method("steamInitEx"):
		init_result = _call_steam_init(steam, "steamInitEx")
	elif steam.has_method("steamInit"):
		init_result = _call_steam_init(steam, "steamInit")
	elif steam.has_method("init"):
		init_result = _call_steam_init(steam, "init")
	if _singleton_ready_for_identity(steam):
		_mark_steam_ready(steam)
		return
	if _should_wait_for_identity(init_result):
		_begin_identity_ready_wait()
		return
	_status_text = _describe_init_failure(init_result)
	_schedule_init_retry()


func _begin_auto_init_wait() -> void:
	_status_text = "Waiting for Steamworks initialization..."
	_awaiting_auto_init = true
	_next_init_retry_msec = 0
	_auto_init_deadline_msec = Time.get_ticks_msec() + 5000
	_poll_auto_init()


func _begin_identity_ready_wait() -> void:
	_status_text = "Waiting for Steam user..."
	_awaiting_identity_ready = true
	_next_init_retry_msec = 0
	_identity_deadline_msec = Time.get_ticks_msec() + 5000
	_poll_identity_ready()


func _poll_auto_init() -> void:
	var steam: Object = Engine.get_singleton("Steam")
	if steam == null:
		_awaiting_auto_init = false
		_status_text = "Steamworks client singleton is unavailable."
		return
	if _singleton_ready_for_identity(steam):
		_mark_steam_ready(steam)
		return
	if Time.get_ticks_msec() < _auto_init_deadline_msec:
		return
	_awaiting_auto_init = false
	_status_text = _describe_auto_init_failure(steam)
	_schedule_init_retry()


func _poll_identity_ready() -> void:
	var steam: Object = Engine.get_singleton("Steam")
	if steam == null:
		_awaiting_identity_ready = false
		_status_text = "Steamworks client singleton is unavailable."
		return
	if _singleton_ready_for_identity(steam):
		_mark_steam_ready(steam)
		return
	if Time.get_ticks_msec() < _identity_deadline_msec:
		return
	_awaiting_identity_ready = false
	_status_text = _describe_auto_init_failure(steam)
	_schedule_init_retry()


func _mark_steam_ready(steam: Object) -> void:
	var was_initialized := _initialized
	_initialized = true
	_awaiting_auto_init = false
	_awaiting_identity_ready = false
	_next_init_retry_msec = 0
	_configure_overlay_notifications(steam)
	_connect_join_signal(steam)
	_connect_lobby_signals(steam)
	_status_text = "Steamworks initialized."
	if not was_initialized:
		steam_ready_changed.emit(true, _status_text)
	_emit_launch_lobby_if_present()
	_emit_launch_invite_if_present()


func _schedule_init_retry() -> void:
	if _initialized or not _is_desktop_platform() or not Engine.has_singleton("Steam"):
		return
	_next_init_retry_msec = Time.get_ticks_msec() + STEAM_INIT_RETRY_INTERVAL_MSEC


func _poll_init_retry() -> void:
	if _initialized or _awaiting_auto_init or _awaiting_identity_ready:
		return
	if not _is_desktop_platform() or not Engine.has_singleton("Steam"):
		return
	if _next_init_retry_msec <= 0:
		_schedule_init_retry()
		return
	if Time.get_ticks_msec() < _next_init_retry_msec:
		return
	_next_init_retry_msec = 0
	if _uses_auto_initialization():
		_begin_auto_init_wait()
	else:
		_initialize_steam()


func _call_steam_init(steam: Object, method_name: String) -> Variant:
	var arg_count := _method_arg_count(steam, method_name)
	var app_id := get_app_id()
	match arg_count:
		0:
			return steam.call(method_name)
		1:
			return steam.call(method_name, app_id)
		2:
			return steam.call(method_name, app_id, true)
		_:
			_status_text = "Unsupported Steam init signature for method %s." % method_name
			return null


func _method_arg_count(target: Object, method_name: String) -> int:
	for method_info in target.get_method_list():
		if str(method_info.get("name", "")) == method_name:
			return int((method_info.get("args", []) as Array).size())
	return -1


func _singleton_ready_for_identity(steam: Object) -> bool:
	if _steam_reports_not_running(steam):
		return false
	var steam_id := ""
	var persona_name := ""
	var logged_on := true
	if steam.has_method("getSteamID"):
		steam_id = str(steam.call("getSteamID")).strip_edges()
	if steam.has_method("loggedOn"):
		logged_on = bool(steam.call("loggedOn"))
	if steam.has_method("getPersonaName"):
		persona_name = str(steam.call("getPersonaName")).strip_edges()
	if steam_id == "0":
		steam_id = ""
	return logged_on and (not steam_id.is_empty() or not persona_name.is_empty())


func _describe_init_failure(init_result: Variant) -> String:
	if Engine.has_singleton("SteamServer") and not Engine.has_singleton("Steam"):
		return "GodotSteam Server is installed, but the game needs the standard GodotSteam client GDExtension."
	var steam: Object = Engine.get_singleton("Steam") if Engine.has_singleton("Steam") else null
	if _steam_reports_not_running(steam):
		return _steam_not_running_message()
	if init_result is Dictionary:
		var init_dict := init_result as Dictionary
		for key in ["verbal", "error", "message", "status"]:
			var text := str(init_dict.get(key, "")).strip_edges()
			if not text.is_empty():
				return "Steamworks initialization failed: %s" % text
	if steam != null and steam.has_method("loggedOn"):
		if not bool(steam.call("loggedOn")):
			return _logged_out_message()
	if init_result is bool:
		if bool(init_result):
			return "Steamworks initialized."
		return "Steamworks initialization failed. Launch the game through Steam or place steam_appid.txt next to the executable."
	var result_text := str(init_result).strip_edges()
	if not result_text.is_empty() and result_text != "<null>":
		return "Steamworks initialization failed: %s" % result_text
	return "Steamworks initialization failed. Launch the game through Steam or place steam_appid.txt next to the executable."


func _describe_auto_init_failure(steam: Object) -> String:
	if _steam_reports_not_running(steam):
		return _steam_not_running_message()
	if steam != null and steam.has_method("loggedOn") and not bool(steam.call("loggedOn")):
		return _logged_out_message()
	return "Steamworks initialization failed. Launch the game through Steam or keep steam_appid.txt next to the executable for local testing."


func _steam_reports_not_running(steam: Object) -> bool:
	if steam == null:
		return false
	for method_name in ["isSteamRunning", "is_steam_running"]:
		if steam.has_method(method_name):
			return not bool(steam.call(method_name))
	return false


func _steam_not_running_message() -> String:
	return "Steam is not running. Open Steam to enable Steam Workshop, Multiplayer, and Leaderboard submissions."


func _should_wait_for_identity(init_result: Variant) -> bool:
	if init_result is bool:
		return bool(init_result)
	if init_result is Dictionary:
		var init_dict: Dictionary = init_result as Dictionary
		for key_variant in ["status", "success", "ok"]:
			if not init_dict.has(key_variant):
				continue
			if bool(init_dict.get(key_variant, false)):
				return true
		var verbal: String = str(init_dict.get("verbal", "")).to_lower()
		if verbal.contains("ok") or verbal.contains("success"):
			return true
	return false


func _missing_steam_singleton_message() -> String:
	if not _is_desktop_platform():
		return "Steamworks is not available in this build."
	var exe_dir := OS.get_executable_path().get_base_dir()
	var steam_api_path := exe_dir.path_join("steam_api64.dll")
	var app_id_path := exe_dir.path_join("steam_appid.txt")
	var missing_files: Array[String] = []
	if OS.has_feature("windows") and not FileAccess.file_exists(steam_api_path):
		missing_files.append("steam_api64.dll")
	if not FileAccess.file_exists(app_id_path):
		missing_files.append("steam_appid.txt")
	if missing_files.is_empty():
		return "Steamworks is not available in this build. On Windows, launch the exported .exe from the full export folder so the GodotSteam DLLs remain beside it."
	return "Steamworks is not available in this build. Missing next to the executable: %s." % ", ".join(missing_files)


func _logged_out_message() -> String:
	var message := "Steamworks is present, but no logged-in Steam user was found. Launch the game through the Steam client while logged in."
	if OS.has_feature("macos") and not OS.has_feature("editor"):
		var app_id_path := OS.get_executable_path().get_base_dir().path_join("steam_appid.txt")
		if not FileAccess.file_exists(app_id_path):
			message += " For local macOS export testing outside Steam, copy steam_appid.txt into the app bundle beside the executable: HarmonicDrive.app/Contents/MacOS/steam_appid.txt."
		message += " If this is a signed/notarized macOS build, confirm the exported app is signed with the Disable Library Validation entitlement."
	return message


func _uses_auto_initialization() -> bool:
	if ProjectSettings.has_setting("steam/initialization/initialize_on_startup"):
		return bool(ProjectSettings.get_setting("steam/initialization/initialize_on_startup"))
	return false


func _configure_overlay_notifications(steam: Object) -> void:
	if steam == null:
		return
	for method_name in ["setOverlayNotificationPosition", "set_overlay_notification_position"]:
		if steam.has_method(method_name):
			steam.call(method_name, 1)
			break
	for method_name in ["setOverlayNotificationInset", "set_overlay_notification_inset"]:
		if steam.has_method(method_name):
			steam.call(method_name, 24, 24)
			break


func _steam_singleton() -> Object:
	if not _initialized or not Engine.has_singleton("Steam"):
		return null
	return Engine.get_singleton("Steam")


func _friend_presence_payload(steam: Object, friend_id: String) -> Dictionary:
	var payload: Dictionary = {}
	if steam == null:
		return payload
	var numeric_id := int(friend_id)
	if steam.has_method("requestFriendRichPresence"):
		steam.call("requestFriendRichPresence", numeric_id)
	if not steam.has_method("getFriendRichPresence"):
		return payload
	for key_variant in ["status", "song", "difficulty", "mode", "mode_label", "steam_display"]:
		var key := str(key_variant)
		var value := str(steam.call("getFriendRichPresence", numeric_id, key)).strip_edges()
		if not value.is_empty():
			payload[key] = value
	return payload


static func _extract_launch_connect_candidate(value: String) -> String:
	var text: String = _trim_launch_token(value)
	var start_index: int = text.find(CONNECT_PREFIX)
	if start_index < 0:
		return ""
	var candidate: String = text.substr(start_index)
	var end_index: int = candidate.length()
	for index in candidate.length():
		var ch: String = candidate.substr(index, 1)
		if [" ", "\t", "\n", "\r", "\"", "'"].has(ch):
			end_index = index
			break
	return _trim_launch_token(candidate.substr(0, end_index))


static func _extract_launch_lobby_candidate(value: String) -> String:
	var text: String = _trim_launch_token(value)
	var tokens: PackedStringArray = text.replace("=", " ").split(" ", false)
	for index in tokens.size():
		var token: String = _trim_launch_token(str(tokens[index]))
		if _is_valid_lobby_id(token):
			if index == 0:
				return token
			var previous := str(tokens[index - 1]).strip_edges().to_lower()
			if _is_launch_lobby_flag(previous) or previous.contains("connect_lobby"):
				return token
	for prefix in ["+connect_lobby", "-connect_lobby", "--connect_lobby", "connect_lobby"]:
		var prefix_index := text.to_lower().find(prefix)
		if prefix_index < 0:
			continue
		var candidate := text.substr(prefix_index + prefix.length()).strip_edges()
		var end_index := candidate.length()
		for char_index in candidate.length():
			var ch := candidate.substr(char_index, 1)
			if [" ", "\t", "\n", "\r", "\"", "'"].has(ch):
				end_index = char_index
				break
		candidate = _trim_launch_token(candidate.substr(0, end_index))
		if _is_valid_lobby_id(candidate):
			return candidate
	return ""


static func _is_launch_connect_flag(value: String) -> bool:
	var cleaned: String = value.strip_edges().to_lower()
	return cleaned in ["+connect", "-connect", "--connect", "connect", "+connect_lobby", "-connect_lobby", "--connect_lobby", "connect_lobby"]


static func _is_launch_lobby_flag(value: String) -> bool:
	var cleaned: String = value.strip_edges().to_lower()
	return cleaned in ["+connect_lobby", "-connect_lobby", "--connect_lobby", "connect_lobby"]


static func _is_valid_lobby_id(value: String) -> bool:
	var cleaned: String = _trim_launch_token(value)
	if cleaned.is_empty() or cleaned.length() < 8:
		return false
	for index in cleaned.length():
		var code := cleaned.unicode_at(index)
		if code < 48 or code > 57:
			return false
	return int(cleaned) > 0


static func _trim_launch_token(value: String) -> String:
	var cleaned: String = value.strip_edges()
	while cleaned.length() >= 2:
		var first_char: String = cleaned.substr(0, 1)
		var last_char: String = cleaned.substr(cleaned.length() - 1, 1)
		if (first_char == "\"" and last_char == "\"") or (first_char == "'" and last_char == "'"):
			cleaned = cleaned.substr(1, cleaned.length() - 2).strip_edges()
		else:
			break
	return cleaned


func _emit_launch_lobby_if_present() -> void:
	if _launch_lobby_emitted:
		return
	var invite: Dictionary = get_launch_lobby_invite()
	if not bool(invite.get("ok", false)):
		return
	_launch_lobby_emitted = true
	_status_text = "Steam lobby invite received."
	call_deferred("_emit_steam_lobby_join_requested", str(invite.get("lobby_id", "")), "")


func _emit_launch_invite_if_present() -> void:
	if _launch_invite_emitted:
		return
	var invite: Dictionary = get_launch_invite()
	if not bool(invite.get("ok", false)):
		return
	_launch_invite_emitted = true
	_status_text = "Steam multiplayer launch invite received."
	call_deferred("_emit_steam_invite_join_requested", invite)


func _emit_steam_invite_join_requested(invite: Dictionary) -> void:
	steam_invite_join_requested.emit(invite)


func _emit_steam_lobby_join_requested(lobby_id: String, friend_id: String = "") -> void:
	steam_lobby_join_requested.emit(lobby_id, friend_id)


func _connect_join_signal(steam: Object) -> void:
	if _join_signal_connected or steam == null:
		return
	if not steam.has_signal("join_requested"):
		return
	var callback := Callable(self, "_on_join_requested")
	if not steam.is_connected("join_requested", callback):
		steam.connect("join_requested", callback)
	_join_signal_connected = true


func _connect_lobby_signals(steam: Object) -> void:
	if steam == null:
		return
	if not _lobby_signals_connected:
		_connect_signal_if_present(steam, "lobby_created", Callable(self, "_on_lobby_created"))
		_connect_signal_if_present(steam, "lobby_joined", Callable(self, "_on_lobby_joined"))
		_connect_signal_if_present(steam, "game_lobby_join_requested", Callable(self, "_on_game_lobby_join_requested"))
		_connect_signal_if_present(steam, "lobby_chat_update", Callable(self, "_on_lobby_chat_update"))
		_connect_signal_if_present(steam, "lobby_data_update", Callable(self, "_on_lobby_data_update"))
		_connect_signal_if_present(steam, "lobby_kicked", Callable(self, "_on_lobby_kicked"))
		_lobby_signals_connected = true
	if not _p2p_signals_connected:
		_connect_signal_if_present(steam, "p2p_session_request", Callable(self, "_on_p2p_session_request"))
		_connect_signal_if_present(steam, "p2p_session_connect_fail", Callable(self, "_on_p2p_session_connect_fail"))
		_p2p_signals_connected = true


func _connect_signal_if_present(target: Object, signal_name: String, callback: Callable) -> void:
	if not target.has_signal(signal_name):
		return
	if not target.is_connected(signal_name, callback):
		target.connect(signal_name, callback)


func _on_join_requested(first: Variant = "", second: Variant = null) -> void:
	var first_text := _id_text(first)
	var second_text := _id_text(second)
	if second is String and _route_join_payload_text(second_text, first_text):
		return
	if not (second is String) and _is_valid_lobby_id(first_text):
		_status_text = "Steam lobby invite received."
		steam_lobby_join_requested.emit(first_text, second_text)
		return
	if _route_join_payload_text(first_text, second_text):
		return
	if _route_join_payload_text(second_text, first_text):
		return
	_status_text = "Ignored Steam join request with unsupported payload."


func _route_join_payload_text(value: String, friend_id: String = "") -> bool:
	var text := value.strip_edges()
	if text.is_empty():
		return false
	var lobby_invite := parse_lobby_launch_text(text)
	if bool(lobby_invite.get("ok", false)):
		_status_text = "Steam lobby invite received."
		steam_lobby_join_requested.emit(str(lobby_invite.get("lobby_id", "")), friend_id)
		return true
	var invite := parse_launch_invite_text(text)
	if bool(invite.get("ok", false)):
		_status_text = "Steam multiplayer invite received."
		steam_invite_join_requested.emit(invite)
		return true
	return false


func _on_game_lobby_join_requested(lobby_id: Variant = "", friend_id: Variant = "") -> void:
	var lobby_text := _id_text(lobby_id)
	if not _is_valid_lobby_id(lobby_text):
		_status_text = "Ignored Steam lobby invite with invalid lobby ID."
		return
	_status_text = "Steam lobby invite received."
	steam_lobby_join_requested.emit(lobby_text, _id_text(friend_id))


func _on_lobby_created(connect: Variant = 0, lobby_id: Variant = "") -> void:
	var success := int(connect) == 1 or bool(connect)
	steam_lobby_created.emit(success, _id_text(lobby_id))


func _on_lobby_joined(lobby_id: Variant = "", _permissions: Variant = null, _locked: Variant = null, response: Variant = 1) -> void:
	steam_lobby_joined.emit(_id_text(lobby_id), int(response))


func _on_lobby_chat_update(lobby_id: Variant = "", changed_id: Variant = "", making_change_id: Variant = "", state: Variant = 0) -> void:
	steam_lobby_chat_updated.emit(_id_text(lobby_id), _id_text(changed_id), _id_text(making_change_id), int(state))


func _on_lobby_data_update(success: Variant = true, lobby_id: Variant = "", member_id: Variant = "") -> void:
	var lobby_text := _id_text(lobby_id)
	var member_text := _id_text(member_id)
	if not _is_valid_lobby_id(lobby_text) and _is_valid_lobby_id(_id_text(success)):
		lobby_text = _id_text(success)
		member_text = _id_text(lobby_id)
		success = true
	steam_lobby_data_updated.emit(lobby_text, member_text, bool(success))


func _on_lobby_kicked(lobby_id: Variant = "", admin_id: Variant = "", due_to_disconnect: Variant = false) -> void:
	steam_lobby_kicked.emit(_id_text(lobby_id), _id_text(admin_id), bool(due_to_disconnect))


func _on_p2p_session_request(steam_id: Variant = "") -> void:
	steam_p2p_session_requested.emit(_id_text(steam_id))


func _on_p2p_session_connect_fail(steam_id: Variant = "", error: Variant = 0) -> void:
	steam_p2p_session_failed.emit(_id_text(steam_id), int(error))


static func _id_text(value: Variant) -> String:
	if value == null:
		return ""
	if value is int:
		return "%d" % int(value)
	if value is float:
		return "%.0f" % float(value)
	return str(value).strip_edges()


func _is_desktop_platform() -> bool:
	return OS.has_feature("windows") or OS.has_feature("macos") or OS.has_feature("linuxbsd")
