extends SceneTree

const GameModeConfig := preload("res://scripts/gameplay/GameModeConfig.gd")
const SteamMultiplayerInvite := preload("res://scripts/net/SteamMultiplayerInvite.gd")
const SteamClientScript := preload("res://autoload/SteamClient.gd")


func _initialize() -> void:
	var connect_string: String = SteamClientScript.build_multiplayer_connect_string(
		"Professional",
		GameModeConfig.STEMS_RANDOM,
		"76561198000000000",
		"nonce value"
	)
	var parsed: Dictionary = SteamClientScript.parse_multiplayer_connect_string(connect_string)
	if not _assert(bool(parsed.get("ok", false)), "Valid Steam multiplayer invite did not parse"):
		return
	if not _assert(str(parsed.get("flow", "")) == "classic", "Invite flow should be classic"):
		return
	if not _assert(str(parsed.get("difficulty", "")) == "Professional", "Invite difficulty did not round-trip"):
		return
	if not _assert(str(parsed.get("mode", "")) == GameModeConfig.STEMS_RANDOM, "Invite mode did not round-trip"):
		return
	if not _assert(str(parsed.get("sender", "")) == "76561198000000000", "Invite sender did not round-trip"):
		return
	if not _assert(str(parsed.get("nonce", "")) == "nonce value", "Invite nonce did not round-trip"):
		return
	if not _assert(not bool(SteamClientScript.parse_multiplayer_connect_string("not-hdmp").get("ok", false)), "Invalid prefix should be rejected"):
		return
	if not _assert(not bool(SteamClientScript.parse_multiplayer_connect_string("hdmp:v1|flow=classic|difficulty=Hard|mode=bad").get("ok", false)), "Invalid mode should be rejected"):
		return
	var parsed_from_text: Dictionary = SteamClientScript.parse_launch_invite_text("+connect \"%s\"" % connect_string)
	if not _assert(str(parsed_from_text.get("mode", "")) == GameModeConfig.STEMS_RANDOM, "Launch command text did not parse connect string"):
		return
	var parsed_from_args: Dictionary = SteamClientScript.parse_launch_invite_from_args(["+connect", connect_string])
	if not _assert(str(parsed_from_args.get("difficulty", "")) == "Professional", "Launch command args did not parse +connect payload"):
		return
	var parsed_from_assignment: Dictionary = SteamClientScript.parse_launch_invite_from_args(["--connect=%s" % connect_string.uri_encode()])
	if not _assert(str(parsed_from_assignment.get("sender", "")) == "76561198000000000", "Launch command assignment did not parse encoded payload"):
		return

	var fallback_mode: String = SteamMultiplayerInvite.resolve_classic_bootstrap_mode(
		{"matchID": "match_smoke"},
		{"mode": GameModeConfig.SYNTHESIZED}
	)
	if not _assert(fallback_mode == GameModeConfig.SYNTHESIZED, "Classic bootstrap did not fall back to current selected mode"):
		return
	var explicit_mode: String = SteamMultiplayerInvite.resolve_classic_bootstrap_mode(
		{"mode": GameModeConfig.STEMS_RANDOM},
		{"mode": GameModeConfig.SYNTHESIZED}
	)
	if not _assert(explicit_mode == GameModeConfig.STEMS_RANDOM, "Classic bootstrap did not respect explicit relay mode"):
		return
	var invalid_mode: String = SteamMultiplayerInvite.resolve_classic_bootstrap_mode(
		{"mode": "bad"},
		{"mode": GameModeConfig.SYNTHESIZED}
	)
	if not _assert(invalid_mode == GameModeConfig.SYNTHESIZED, "Classic bootstrap invalid mode did not fall back"):
		return

	print("Steam multiplayer invite smoke test passed")
	quit(0)


func _assert(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
		quit(1)
		return false
	return true
