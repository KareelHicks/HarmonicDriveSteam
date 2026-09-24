extends SceneTree

const SteamLobbyProtocol := preload("res://scripts/net/SteamLobbyProtocol.gd")
const SteamClientScript := preload("res://autoload/SteamClient.gd")


func _initialize() -> void:
	var packet := {
		"type": SteamLobbyProtocol.TYPE_LIVE_SCORE,
		"round_id": "round_a",
		"score": 123456,
		"accuracy": 98.5,
		"combo": 321,
	}
	var decoded: Dictionary = SteamLobbyProtocol.decode(SteamLobbyProtocol.encode(packet))
	if not _assert(str(decoded.get("type", "")) == SteamLobbyProtocol.TYPE_LIVE_SCORE, "Protocol packet type did not round-trip"):
		return
	if not _assert(int(decoded.get("score", 0)) == 123456, "Protocol packet score did not round-trip"):
		return
	if not _assert(SteamLobbyProtocol.has_stale_round(decoded, "round_b"), "Stale round_id was not rejected"):
		return
	if not _assert(not SteamLobbyProtocol.has_stale_round(decoded, "round_a"), "Matching round_id was treated as stale"):
		return
	if not _assert(not SteamLobbyProtocol.sender_allowed(SteamLobbyProtocol.TYPE_ROUND_START, "follower", "leader"), "Follower was allowed to send round_start"):
		return
	if not _assert(SteamLobbyProtocol.sender_allowed(SteamLobbyProtocol.TYPE_ROUND_START, "leader", "leader"), "Leader was blocked from round_start"):
		return
	if not _assert(SteamLobbyProtocol.sender_allowed(SteamLobbyProtocol.TYPE_LIVE_SCORE, "follower", "leader"), "Follower live_score was blocked"):
		return

	var snapshot: Dictionary = SteamLobbyProtocol.build_result_snapshot("round_a", "match_a", [
		{"userID": "leader", "displayName": "Leader", "finalScore": 2000},
		{"userID": "follower", "displayName": "Follower", "finalScore": 1000},
	])
	if not _assert(str(snapshot.get("winnerUserID", "")) == "leader", "Result snapshot winner was incorrect"):
		return
	var players: Array = snapshot.get("players", []) as Array
	if not _assert(players.size() == 2, "Result snapshot player count was incorrect"):
		return
	if not _assert(int((players[0] as Dictionary).get("finalPlacement", 0)) == 1, "Winner placement was incorrect"):
		return
	if not _assert(int((players[1] as Dictionary).get("finalPlacement", 0)) == 2, "Follower placement was incorrect"):
		return

	var lobby_from_text: Dictionary = SteamClientScript.parse_lobby_launch_text("+connect_lobby 109775242615221234")
	if not _assert(str(lobby_from_text.get("lobby_id", "")) == "109775242615221234", "Lobby launch text did not parse"):
		return
	var lobby_from_args: Dictionary = SteamClientScript.parse_lobby_launch_from_args(["--connect_lobby=109775242615221235"])
	if not _assert(str(lobby_from_args.get("lobby_id", "")) == "109775242615221235", "Lobby launch args did not parse"):
		return
	if not _assert(SteamClientScript.parse_lobby_launch_text("+connect_lobby not-a-lobby").is_empty(), "Invalid lobby launch parsed unexpectedly"):
		return
	var client := SteamClientScript.new()
	var routed_lobby: Array[String] = []
	client.steam_lobby_join_requested.connect(func(lobby_id: String, friend_id: String) -> void:
		routed_lobby.clear()
		routed_lobby.append(lobby_id)
		routed_lobby.append(friend_id)
	)
	client._on_join_requested(109775242615221236, 76561198000000000)
	if not _assert(routed_lobby.size() == 2 and routed_lobby[0] == "109775242615221236", "Numeric join_requested did not route to Steam lobby"):
		return
	if not _assert(routed_lobby[1] == "76561198000000000", "Numeric join_requested did not preserve friend id"):
		return
	routed_lobby.clear()
	client._on_join_requested(76561198000000000, "+connect_lobby 109775242615221237")
	if not _assert(routed_lobby.size() == 2 and routed_lobby[0] == "109775242615221237", "String join_requested payload did not route to Steam lobby"):
		return

	print("Steam lobby protocol smoke test passed")
	quit(0)


func _assert(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
		quit(1)
		return false
	return true
