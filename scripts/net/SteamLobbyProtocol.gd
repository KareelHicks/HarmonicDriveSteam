extends RefCounted
class_name SteamLobbyProtocol

const VERSION := 1
const TYPE_HELLO := "hello"
const TYPE_SETTINGS_UPDATE := "settings_update"
const TYPE_READY_UPDATE := "ready_update"
const TYPE_ROUND_START := "round_start"
const TYPE_LIVE_SCORE := "live_score"
const TYPE_FINAL_RESULT := "final_result"
const TYPE_RESULT_SNAPSHOT := "result_snapshot"
const TYPE_LEAVE_NOTICE := "leave_notice"

const LEADER_ONLY_TYPES := [
	TYPE_SETTINGS_UPDATE,
	TYPE_ROUND_START,
	TYPE_RESULT_SNAPSHOT,
]


static func encode(packet: Dictionary) -> PackedByteArray:
	var payload: Dictionary = packet.duplicate(true)
	payload["v"] = VERSION
	return JSON.stringify(payload).to_utf8_buffer()


static func decode(data: PackedByteArray) -> Dictionary:
	if data.is_empty():
		return {}
	var text := data.get_string_from_utf8()
	if text.strip_edges().is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return {}
	var packet: Dictionary = (parsed as Dictionary).duplicate(true)
	if int(packet.get("v", -1)) != VERSION:
		return {}
	if str(packet.get("type", "")).strip_edges().is_empty():
		return {}
	return packet


static func sender_allowed(packet_type: String, sender_id: String, leader_id: String) -> bool:
	if not LEADER_ONLY_TYPES.has(packet_type):
		return true
	return sender_id == leader_id and not leader_id.is_empty()


static func has_stale_round(packet: Dictionary, active_round_id: String) -> bool:
	var packet_round_id := str(packet.get("round_id", "")).strip_edges()
	if packet_round_id.is_empty():
		return false
	if active_round_id.strip_edges().is_empty():
		return false
	return packet_round_id != active_round_id


static func packet_requires_active_round(packet_type: String) -> bool:
	return packet_type in [
		TYPE_LIVE_SCORE,
		TYPE_FINAL_RESULT,
		TYPE_RESULT_SNAPSHOT,
	]


static func build_result_snapshot(round_id: String, match_id: String, players: Array) -> Dictionary:
	var ranked_players: Array[Dictionary] = []
	for player_variant in players:
		if player_variant is Dictionary:
			ranked_players.append((player_variant as Dictionary).duplicate(true))
	ranked_players.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("finalScore", 0)) > int(b.get("finalScore", 0))
	)
	var previous_score: Variant = null
	var current_placement := 0
	for index in ranked_players.size():
		var player: Dictionary = ranked_players[index]
		var score := int(player.get("finalScore", 0))
		if previous_score == null or score != int(previous_score):
			current_placement = index + 1
		player["finalPlacement"] = current_placement
		player["placement"] = current_placement
		previous_score = score
		ranked_players[index] = player
	var winner_user_id := ""
	if ranked_players.size() >= 2:
		var top_score := int(ranked_players[0].get("finalScore", 0))
		var second_score := int(ranked_players[1].get("finalScore", 0))
		if top_score != second_score:
			winner_user_id = str(ranked_players[0].get("userID", ""))
	return {
		"matchID": match_id,
		"roundID": round_id,
		"status": "finished",
		"winnerUserID": winner_user_id,
		"players": ranked_players,
	}
