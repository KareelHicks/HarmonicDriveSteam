extends Node
class_name IdentityService

const RelayConfig = preload("res://scripts/net/RelayConfig.gd")
const RelayAPIClient = preload("res://scripts/net/RelayAPIClient.gd")

signal auth_state_changed(identity: Dictionary)
signal login_failed(message: String)
signal request_failed(route: String, message: String)

var state: String = "idle"
var status_text: String = "Not connected"

var _identity: Dictionary = {}
var _api: RelayAPIClient
var _android_sign_in_timer: Timer
var _android_sign_in_elapsed: float = 0.0
var _android_games_plugin: Object
var _desktop_sign_in_timer: Timer
var _desktop_sign_in_elapsed: float = 0.0


func _ready() -> void:
	if OS.get_environment("HARMONIC_DRIVE_OFFLINE_QA") == "1":
		state = "offline"
		status_text = "Offline"
		return
	_api = RelayAPIClient.new()
	add_child(_api)
	_api.request_failed.connect(_on_request_failed)
	_android_sign_in_timer = Timer.new()
	_android_sign_in_timer.wait_time = 0.35
	_android_sign_in_timer.one_shot = false
	_android_sign_in_timer.timeout.connect(_poll_android_sign_in)
	add_child(_android_sign_in_timer)
	_desktop_sign_in_timer = Timer.new()
	_desktop_sign_in_timer.wait_time = 0.35
	_desktop_sign_in_timer.one_shot = false
	_desktop_sign_in_timer.timeout.connect(_poll_desktop_sign_in)
	add_child(_desktop_sign_in_timer)
	_bind_android_games_plugin()


func is_available() -> bool:
	return OS.get_environment("HARMONIC_DRIVE_OFFLINE_QA") != "1" and not RelayConfig.base_url().is_empty()


func is_authenticated() -> bool:
	return not str(_identity.get("backendToken", "")).is_empty()


func get_current_identity() -> Dictionary:
	return _identity.duplicate(true)


func current_user() -> Dictionary:
	return {
		"id": str(_identity.get("userID", "")),
		"display_name": str(_identity.get("displayName", "")),
	}


func logout_if_supported() -> void:
	_identity.clear()
	state = "idle"
	status_text = "Not connected"
	auth_state_changed.emit(get_current_identity())


func authenticate_current_platform() -> void:
	if not is_available():
		_emit_login_failure("Online identity is disabled for this offline session." if OS.get_environment("HARMONIC_DRIVE_OFFLINE_QA") == "1" else "Relay is not configured.")
		return
	print("[identity] authenticate_current_platform platform_android=%s relay=%s" % [OS.has_feature("android"), RelayConfig.base_url()])
	if OS.has_feature("android"):
		if _is_local_relay_url():
			_emit_login_failure("Relay base URL is still localhost. Android needs a reachable relay URL.")
			return
		var android_identity: Dictionary = _detect_android_identity()
		if not android_identity.is_empty():
			print("[identity] using existing Android identity display=%s user=%s" % [str(android_identity.get("displayName", "")), str(android_identity.get("platformUserID", ""))])
			_submit_platform_auth(android_identity)
			return
		if not _has_android_games_singleton():
			_emit_login_failure("Google Play Games sign-in plugin is not available in this Android build.")
			return
		if _begin_android_sign_in():
			print("[identity] started Android Play Games sign-in")
			state = "authenticating"
			status_text = "Opening Google Play Games sign-in..."
			_start_android_sign_in_poll()
			return
		_emit_login_failure("Google Play Games sign-in could not be started.")
		return
	if OS.has_feature("windows") or OS.has_feature("macos") or OS.has_feature("linuxbsd"):
		if not Engine.has_singleton("Steam"):
			_submit_platform_auth(_detect_guest_identity())
			return
	var payload: Dictionary = _detect_platform_payload()
	if payload.is_empty():
		if OS.has_feature("windows") or OS.has_feature("macos") or OS.has_feature("linuxbsd"):
			_submit_platform_auth(_detect_guest_identity())
			return
		_emit_login_failure("No supported platform identity is available.")
		return
	print("[identity] using non-Android identity platform=%s user=%s" % [str(payload.get("platform", "")), str(payload.get("platformUserID", ""))])
	_submit_platform_auth(payload)


func ensure_relay_identity() -> void:
	if not is_authenticated():
		authenticate_current_platform()


func refreshIdentityFromRelay() -> void:
	authenticate_current_platform()


func get_backend_token() -> String:
	return str(_identity.get("backendToken", ""))


func get_realtime_base_url() -> String:
	return str(_identity.get("realtimeBaseURL", ""))


func _detect_platform_payload() -> Dictionary:
	if OS.has_feature("android"):
		var android_identity: Dictionary = _detect_android_identity()
		if not android_identity.is_empty():
			return android_identity
	if Engine.has_singleton("Steam") or OS.has_feature("windows") or OS.has_feature("macos") or OS.has_feature("linuxbsd"):
		var steam_identity: Dictionary = _detect_steam_identity()
		if not steam_identity.is_empty():
			return steam_identity
	if not (OS.has_feature("android") or OS.has_feature("windows") or OS.has_feature("macos") or OS.has_feature("linuxbsd")):
		return _detect_guest_identity()
	return {}


func _detect_android_identity() -> Dictionary:
	if _android_games_plugin != null:
		var direct_display_name: String = str(_android_games_plugin.call("getDisplayName")).strip_edges()
		var direct_player_id: String = str(_android_games_plugin.call("getPlayerID")).strip_edges()
		if not direct_display_name.is_empty() or not direct_player_id.is_empty():
			if direct_player_id.is_empty():
				direct_player_id = _normalize_fallback_id(direct_display_name)
			return {
				"platform": "android",
				"platformUserID": direct_player_id,
				"displayName": direct_display_name if not direct_display_name.is_empty() else "Android Player",
			}
	if Engine.has_singleton("GooglePlayGames"):
		var play_games: Object = Engine.get_singleton("GooglePlayGames")
		var direct_display_name: String = str(play_games.call("getDisplayName")).strip_edges()
		var direct_player_id: String = str(play_games.call("getPlayerID")).strip_edges()
		if not direct_display_name.is_empty() or not direct_player_id.is_empty():
			if direct_player_id.is_empty():
				direct_player_id = _normalize_fallback_id(direct_display_name)
			return {
				"platform": "android",
				"platformUserID": direct_player_id,
				"displayName": direct_display_name if not direct_display_name.is_empty() else "Android Player",
			}
	for singleton_name in ["GooglePlay", "GooglePlayGames", "PlayGames"]:
		if not Engine.has_singleton(singleton_name):
			continue
		var singleton: Object = Engine.get_singleton(singleton_name)
		var display_name: String = _call_first_string(singleton, ["getDisplayName", "getPlayerDisplayName", "get_player_display_name", "getPlayerName"])
		var player_id: String = _call_first_string(singleton, ["getPlayerID", "getPlayerId", "get_player_id", "getCurrentPlayerId"])
		if display_name.is_empty() and player_id.is_empty():
			continue
		if player_id.is_empty():
			player_id = _normalize_fallback_id(display_name)
		return {
			"platform": "android",
			"platformUserID": player_id,
			"displayName": display_name if not display_name.is_empty() else "Android Player",
		}
	return {}


func _has_android_games_singleton() -> bool:
	if _android_games_plugin != null:
		return true
	if Engine.has_singleton("GooglePlayGames"):
		return true
	for singleton_name in ["GooglePlay", "GooglePlayGames", "PlayGames"]:
		if Engine.has_singleton(singleton_name):
			return true
	return false


func _start_desktop_sign_in_poll() -> void:
	if _desktop_sign_in_timer == null:
		return
	_desktop_sign_in_elapsed = 0.0
	state = "authenticating"
	status_text = "Waiting for Steamworks..."
	if _desktop_sign_in_timer.is_stopped():
		_desktop_sign_in_timer.start()


func _poll_desktop_sign_in() -> void:
	_desktop_sign_in_elapsed += _desktop_sign_in_timer.wait_time
	var payload: Dictionary = _detect_platform_payload()
	if not payload.is_empty():
		_desktop_sign_in_timer.stop()
		print("[identity] using desktop identity platform=%s user=%s" % [str(payload.get("platform", "")), str(payload.get("platformUserID", ""))])
		_submit_platform_auth(payload)
		return
	if _desktop_sign_in_elapsed < 5.0:
		return
	_desktop_sign_in_timer.stop()
	_submit_platform_auth(_detect_guest_identity())


func _begin_android_sign_in() -> bool:
	if _android_games_plugin != null:
		_android_games_plugin.call("signIn")
		return true
	if Engine.has_singleton("GooglePlayGames"):
		var play_games: Object = Engine.get_singleton("GooglePlayGames")
		play_games.call("signIn")
		return true
	for singleton_name in ["GooglePlay", "GooglePlayGames", "PlayGames"]:
		if not Engine.has_singleton(singleton_name):
			continue
		var singleton: Object = Engine.get_singleton(singleton_name)
		for method_name in [
			"signIn",
			"sign_in",
			"login",
			"authenticate",
			"beginUserInitiatedSignIn",
			"startSignIn",
			"showLogin",
			"showSignIn",
		]:
			if singleton.has_method(method_name):
				singleton.call(method_name)
				return true
	return false


func _start_android_sign_in_poll() -> void:
	_android_sign_in_elapsed = 0.0
	if _android_sign_in_timer.is_stopped():
		print("[identity] starting Android sign-in poll")
		_android_sign_in_timer.start()


func _poll_android_sign_in() -> void:
	_android_sign_in_elapsed += _android_sign_in_timer.wait_time
	var android_identity: Dictionary = _detect_android_identity()
	if not android_identity.is_empty():
		print("[identity] Android sign-in poll found identity display=%s user=%s" % [str(android_identity.get("displayName", "")), str(android_identity.get("platformUserID", ""))])
		_android_sign_in_timer.stop()
		_submit_platform_auth(android_identity)
		return
	if _android_sign_in_elapsed >= 20.0:
		print("[identity] Android sign-in poll timed out")
		_android_sign_in_timer.stop()
		_emit_login_failure("Google Play Games sign-in did not complete. Make sure Play Games is installed and the user is signed in.")


func _submit_platform_auth(payload: Dictionary) -> void:
	state = "authenticating"
	status_text = "Connecting..."
	print("[identity] submitting relay auth platform=%s user=%s" % [str(payload.get("platform", "")), str(payload.get("platformUserID", ""))])
	_api.call_api("POST", "/auth/platform", payload, "", _on_auth_completed)


func _is_local_relay_url() -> bool:
	var base_url: String = RelayConfig.base_url().to_lower()
	return base_url.contains("127.0.0.1") or base_url.contains("localhost")


func _bind_android_games_plugin() -> void:
	if not OS.has_feature("android"):
		return
	if Engine.has_singleton("GooglePlayGames"):
		_android_games_plugin = Engine.get_singleton("GooglePlayGames")
		print("[identity] bound GooglePlayGames singleton")
		if _android_games_plugin != null and _android_games_plugin.has_signal("auth_state_changed"):
			if not _android_games_plugin.auth_state_changed.is_connected(_on_android_games_auth_state_changed):
				_android_games_plugin.auth_state_changed.connect(_on_android_games_auth_state_changed)
	else:
		print("[identity] GooglePlayGames singleton not available")


func _on_android_games_auth_state_changed(authenticated: bool, display_name: String, player_id: String, message: String) -> void:
	print("[identity] android auth signal authenticated=%s display=%s player_id=%s message=%s" % [authenticated, display_name, player_id, message])
	if authenticated:
		_android_sign_in_timer.stop()
		var effective_player_id: String = player_id if not player_id.is_empty() else _normalize_fallback_id(display_name)
		_submit_platform_auth({
			"platform": "android",
			"platformUserID": effective_player_id,
			"displayName": display_name if not display_name.is_empty() else "Android Player",
		})
		return
	if not message.is_empty():
		_android_sign_in_timer.stop()
		_emit_login_failure(message)


func _detect_steam_identity() -> Dictionary:
	var steam_client: Node = get_node_or_null("/root/SteamClient")
	if steam_client != null and steam_client.has_method("is_ready") and not bool(steam_client.call("is_ready")):
		return {}
	if Engine.has_singleton("Steam"):
		var steam: Object = Engine.get_singleton("Steam")
		var display_name: String = _call_first_string(steam, ["getPersonaName", "get_persona_name"])
		var steam_id: String = _call_first_string(steam, ["getSteamID", "get_steam_id"])
		if steam_id == "0":
			steam_id = ""
		if display_name.is_empty() and steam_id.is_empty():
			return {}
		if steam_id.is_empty():
			steam_id = _normalize_fallback_id(display_name)
		return {
			"platform": "steam",
			"platformUserID": steam_id,
			"displayName": display_name if not display_name.is_empty() else "Steam Player",
		}
	return {}


func _detect_guest_identity() -> Dictionary:
	var guest_uuid: String = ProfileStore.get_guest_uuid()
	return {
		"platform": "guest",
		"platformUserID": "guest_%s" % guest_uuid,
		"displayName": "Guest %s" % guest_uuid.substr(0, 8).to_upper(),
	}


func _call_first_string(target: Object, method_names: Array) -> String:
	for method_name_variant in method_names:
		var method_name: String = str(method_name_variant)
		if not target.has_method(method_name):
			continue
		var raw_value: Variant = target.call(method_name)
		var text: String = str(raw_value).strip_edges()
		if not text.is_empty() and text != "<null>":
			return text
	return ""


func _normalize_fallback_id(source: String) -> String:
	var lowered: String = source.strip_edges().to_lower()
	if lowered.is_empty():
		return ProfileStore.get_guest_uuid()
	var result := ""
	for index in lowered.length():
		var character: String = lowered.substr(index, 1)
		var ascii: int = character.unicode_at(0)
		var is_letter: bool = ascii >= 97 and ascii <= 122
		var is_digit: bool = ascii >= 48 and ascii <= 57
		if is_letter or is_digit:
			result += character
		else:
			result += "_"
	return result.strip_edges()


func _steam_not_available_message() -> String:
	var steam_client: Node = get_node_or_null("/root/SteamClient")
	if steam_client != null and steam_client.has_method("get_status_text"):
		var status: String = str(steam_client.call("get_status_text")).strip_edges()
		if not status.is_empty():
			return status
	if Engine.has_singleton("SteamServer") and not Engine.has_singleton("Steam"):
		return "GodotSteam Server is installed, but the game needs the standard GodotSteam client GDExtension."
	return "Steamworks is not available in this build. On Windows, run the exported .exe from the full export folder and keep the GodotSteam DLLs plus steam_appid.txt next to it."


func _on_auth_completed(success: bool, data: Variant, _payload: Dictionary, _meta: Dictionary) -> void:
	if not success or not (data is Dictionary):
		print("[identity] relay auth failed success=%s" % success)
		_emit_login_failure("Relay authentication failed.")
		return
	var identity_payload: Dictionary = ((data as Dictionary).get("identity", {}) as Dictionary).duplicate(true)
	if identity_payload.is_empty():
		print("[identity] relay auth returned empty identity payload")
		_emit_login_failure("Relay authentication returned an invalid identity payload.")
		return
	_identity = identity_payload
	state = "authenticated"
	status_text = str(_identity.get("displayName", "Authenticated"))
	print("[identity] relay auth completed userID=%s displayName=%s" % [str(_identity.get("userID", "")), str(_identity.get("displayName", ""))])
	auth_state_changed.emit(get_current_identity())


func _emit_login_failure(message: String) -> void:
	state = "failed"
	status_text = message
	print("[identity] login failure: %s" % message)
	login_failed.emit(message)
	auth_state_changed.emit(get_current_identity())


func _on_request_failed(route: String, message: String) -> void:
	request_failed.emit(route, message)
