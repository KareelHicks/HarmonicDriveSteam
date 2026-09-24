extends Node

const GameModeConfig = preload("res://scripts/gameplay/GameModeConfig.gd")

const ACHIEVEMENTS := {
	"First_Song": {"stat": "songs_completed"},
	"Welcome_Harmonic": {},
	"Locked_In": {},
	"Flow_State": {},
	"Precision_Driver": {},
	"Perfect_Timing": {},
	"Machine_Precision": {},
	"Combo_Machine": {},
	"Rookie_Driver": {},
	"Steady_Hands": {},
	"Rhythm_Warrior": {},
	"Beyond_Human": {},
	"Harmonic_Master": {},
	"Playlist_Starter": {"stat": "songs_completed"},
	"Tour_Complete": {"stat": "songs_completed"},
	"Endless_Drive": {"stat": "time_played"},
	"First_Jam": {"stat": "multiplayer_matches_completed"},
	"Rivalry": {},
	"I_Did_It": {"stat": "multiplayer_matches_won"},
	"Winner": {"stat": "multiplayer_matches_won"},
	"Harmonic_Winner": {"stat": "multiplayer_matches_won"},
	"Speed_Demon": {},
	"Chaos_Theory": {},
	"Style_Points": {},
	"Night_Drive": {},
	"Harmonic_Legend": {},
}

const LEGEND_ID := "Harmonic_Legend"
const TOTAL_SONGS_TIME_ACHIEVEMENT_SECONDS := 18000
const TRACKED_STAT_DEFAULTS := {
	"songs_completed": 0,
	"time_played": 0,
	"multiplayer_matches_completed": 0,
	"multiplayer_matches_won": 0,
}

var _steam: Object
var _steam_ready := false
var _refreshed := false
var _stats_cache: Dictionary = {}
var _unlocked_achievement_ids: Dictionary = {}
var _user_stats_received_count := 0
var _user_stats_stored_count := 0
var _last_user_stats_received_result := 0
var _last_user_stats_stored_result := 0


func _ready() -> void:
	set_process(true)


func _process(_delta: float) -> void:
	if _steam_ready:
		if _steam != null and _steam.has_method("run_callbacks"):
			_steam.call("run_callbacks")
		return
	if _resolve_steam_singleton():
		refresh_from_steam()


func is_ready() -> bool:
	return _steam_ready


func refresh_from_steam() -> void:
	if not _resolve_steam_singleton():
		return
	_refreshed = true
	_steam_ready = true
	_unlocked_achievement_ids.clear()
	for achievement_id in ACHIEVEMENTS.keys():
		var achieved := _get_achievement_state_from_steam(achievement_id)
		if achieved:
			_unlocked_achievement_ids[achievement_id] = true
	_store_unlocked_achievement_ids()


func on_song_completed(song_entry: Dictionary, result: Dictionary, loadout: Dictionary, was_first_completion: bool, base_song_complete_count: int, unique_song_complete_count: int, total_base_song_count: int) -> void:
	if not _resolve_steam_singleton():
		return
	if was_first_completion:
		_mark_unique_song_completed(str(song_entry.get("id", "")))
	var resolved_unique_count := maxi(unique_song_complete_count, get_unique_song_completion_count())
	var resolved_base_count := maxi(base_song_complete_count, get_base_song_completion_count())
	var resolved_total_base_count := maxi(total_base_song_count, get_total_base_song_count())
	_set_stat("songs_completed", resolved_unique_count)
	_set_stat("time_played", int(round(ProfileStore.get_steam_cumulative_playtime_seconds())))
	var difficulty: String = str(result.get("difficulty", ""))
	var accuracy: float = float(result.get("accuracy", 0.0))
	var max_combo: int = int(result.get("max_combo", 0))
	var speed_modifier: String = str(loadout.get("speed_modifier", "speed_1_0"))
	var theme_id: String = str(loadout.get("theme", "theme_default"))
	var effect_id: String = str(loadout.get("effect", "effect_none"))
	_unlock("First_Song", resolved_unique_count >= 1)
	_unlock("Welcome_Harmonic", resolved_unique_count >= 5)
	_unlock("Locked_In", max_combo >= 50)
	_unlock("Flow_State", max_combo >= 100)
	_unlock("Combo_Machine", max_combo >= 500)
	_unlock("Precision_Driver", accuracy >= 95.0)
	_unlock("Perfect_Timing", accuracy >= 98.0)
	_unlock("Machine_Precision", is_equal_approx(accuracy, 100.0))
	_unlock("Rookie_Driver", difficulty == "Easy")
	_unlock("Steady_Hands", difficulty == "Medium")
	_unlock("Rhythm_Warrior", difficulty == "Hard")
	_unlock("Beyond_Human", difficulty == "Expert")
	_unlock("Harmonic_Master", difficulty == "Professional")
	_unlock("Playlist_Starter", resolved_unique_count >= 25)
	_unlock("Tour_Complete", resolved_total_base_count > 0 and resolved_base_count >= resolved_total_base_count)
	_unlock("Endless_Drive", ProfileStore.get_steam_cumulative_playtime_seconds() >= TOTAL_SONGS_TIME_ACHIEVEMENT_SECONDS)
	_unlock("Speed_Demon", speed_modifier == "speed_1_2")
	_unlock("Chaos_Theory", speed_modifier == "speed_1_5")
	_unlock("Style_Points", theme_id != "theme_default" and effect_id != "effect_none")
	_unlock("Night_Drive", difficulty == "Professional" and speed_modifier == "speed_1_5" and is_equal_approx(accuracy, 100.0))
	_unlock_legend_if_ready()
	_store_stats()


func on_multiplayer_match_completed(result_snapshot: Dictionary, _local_result: Dictionary, did_win: bool) -> void:
	if not _resolve_steam_singleton():
		return
	var match_id: String = str(result_snapshot.get("matchID", "")).strip_edges()
	if match_id.is_empty():
		return
	var completed_ids: Array[String] = ProfileStore.get_steam_completed_multiplayer_match_ids()
	if not completed_ids.has(match_id):
		completed_ids.append(match_id)
		ProfileStore.set_steam_completed_multiplayer_match_ids(completed_ids)
	var won_ids: Array[String] = ProfileStore.get_steam_won_multiplayer_match_ids()
	if did_win and not won_ids.has(match_id):
		won_ids.append(match_id)
		ProfileStore.set_steam_won_multiplayer_match_ids(won_ids)
	_set_stat("multiplayer_matches_completed", completed_ids.size())
	_set_stat("multiplayer_matches_won", won_ids.size())
	_unlock("First_Jam", completed_ids.size() >= 1)
	_unlock("I_Did_It", won_ids.size() >= 1)
	_unlock("Winner", won_ids.size() >= 5)
	_unlock("Harmonic_Winner", won_ids.size() >= 20)
	_unlock_legend_if_ready()
	_store_stats()


func on_leaderboard_submission(song_id: String, difficulty: String, mode: String, submitted_entry: Dictionary, previous_best_rank: int) -> void:
	if not _resolve_steam_singleton():
		return
	var entry_rank := _extract_rank(submitted_entry)
	var key := _leaderboard_rank_key(song_id, difficulty, mode)
	var best_ranks: Dictionary = ProfileStore.get_steam_best_leaderboard_ranks()
	if entry_rank > 0:
		var stored_rank: int = int(best_ranks.get(key, 0))
		if stored_rank <= 0 or entry_rank < stored_rank:
			best_ranks[key] = entry_rank
			ProfileStore.set_steam_best_leaderboard_ranks(best_ranks)
		if previous_best_rank > 0 and entry_rank < previous_best_rank:
			_unlock("Rivalry", true)
			_unlock_legend_if_ready()
			_store_stats()


func on_session_time(delta_seconds: float) -> void:
	if delta_seconds <= 0.0:
		return
	var updated_seconds: float = ProfileStore.get_steam_cumulative_playtime_seconds() + delta_seconds
	ProfileStore.set_steam_cumulative_playtime_seconds(updated_seconds)
	if not _resolve_steam_singleton():
		return
	_set_stat("time_played", int(round(updated_seconds)))
	_unlock("Endless_Drive", updated_seconds >= TOTAL_SONGS_TIME_ACHIEVEMENT_SECONDS)
	_unlock_legend_if_ready()
	_store_stats()


func get_unique_song_completion_count() -> int:
	return ProfileStore.get_steam_unique_completed_song_ids().size()


func get_base_song_completion_count() -> int:
	var completed: Dictionary = ProfileStore.get_progression_data().get("completed_songs", {}) as Dictionary
	var count := 0
	for song in ContentRegistry.get_songs():
		if not (song is Dictionary):
			continue
		var entry: Dictionary = song as Dictionary
		if bool(entry.get("is_premium", false)):
			continue
		if completed.has(str(entry.get("id", ""))):
			count += 1
	return count


func get_total_base_song_count() -> int:
	var count := 0
	for song in ContentRegistry.get_songs():
		if song is Dictionary:
			count += 1
	return count


func get_multiplayer_match_completion_count() -> int:
	return ProfileStore.get_steam_completed_multiplayer_match_ids().size()


func get_multiplayer_match_win_count() -> int:
	return ProfileStore.get_steam_won_multiplayer_match_ids().size()


func get_best_leaderboard_rank(song_id: String, difficulty: String, mode: String) -> int:
	var best_ranks: Dictionary = ProfileStore.get_steam_best_leaderboard_ranks()
	return int(best_ranks.get(_leaderboard_rank_key(song_id, difficulty, mode), 0))


func get_stats_snapshot() -> Dictionary:
	return {
		"steam_ready": _steam_ready,
		"steam_status": SteamClient.get_status_text() if SteamClient != null else "Steam unavailable.",
		"cloud_status": SteamCloudSync.get_status_text() if SteamCloudSync != null else "Steam Cloud unavailable.",
		"songs_completed": get_unique_song_completion_count(),
		"base_songs_completed": get_base_song_completion_count(),
		"total_base_songs": get_total_base_song_count(),
		"time_played_seconds": ProfileStore.get_steam_cumulative_playtime_seconds(),
		"multiplayer_matches_completed": get_multiplayer_match_completion_count(),
		"multiplayer_matches_won": get_multiplayer_match_win_count(),
		"unlocked_achievement_ids": ProfileStore.get_steam_unlocked_achievement_ids(),
	}


func reset_all_stats_and_achievements() -> Dictionary:
	if not _resolve_steam_singleton():
		return {"ok": false, "message": "Steam is not ready."}
	_request_current_stats()
	var stats_received := await _wait_for_user_stats_received()
	for stat_name_variant in TRACKED_STAT_DEFAULTS.keys():
		var stat_name := str(stat_name_variant)
		_set_stat(stat_name, int(TRACKED_STAT_DEFAULTS[stat_name_variant]))
	_store_stats()
	var stats_stored := await _wait_for_user_stats_stored()
	_request_current_stats()
	stats_received = await _wait_for_user_stats_received() and stats_received
	var stats_reset := _are_tracked_stats_reset()
	for achievement_id in ACHIEVEMENTS.keys():
		_clear_achievement(achievement_id)
	_store_stats()
	stats_stored = await _wait_for_user_stats_stored() and stats_stored
	_request_current_stats()
	stats_received = await _wait_for_user_stats_received() and stats_received
	var achievements_reset := _are_achievements_cleared()
	_stats_cache.clear()
	_unlocked_achievement_ids.clear()
	ProfileStore.clear_steam_tracking_data()
	if ProgressionManager != null and ProgressionManager.has_method("_load_or_reset"):
		ProgressionManager.call("_load_or_reset")
	var cloud_synced := true
	if SteamCloudSync != null and SteamCloudSync.has_method("force_upload_local_profile"):
		cloud_synced = bool(SteamCloudSync.call("force_upload_local_profile"))
	refresh_from_steam()
	var ok := stats_reset and achievements_reset and cloud_synced
	var message := "Steam stats and achievements reset." if ok else "Steam reset could not be fully verified."
	if not stats_received:
		message = "Steam did not confirm updated stats."
	elif not stats_stored:
		message = "Steam did not confirm stat storage."
	elif not cloud_synced:
		message = "Steam Cloud profile upload did not complete."
	return {
		"ok": ok,
		"stats_reset": stats_reset,
		"achievements_reset": achievements_reset,
		"cloud_synced": cloud_synced,
		"message": message,
	}


func _mark_unique_song_completed(song_id: String) -> void:
	if song_id.is_empty():
		return
	var completed_ids: Array[String] = ProfileStore.get_steam_unique_completed_song_ids()
	if completed_ids.has(song_id):
		return
	completed_ids.append(song_id)
	ProfileStore.set_steam_unique_completed_song_ids(completed_ids)


func _unlock(achievement_id: String, condition: bool) -> void:
	if not condition or achievement_id.is_empty():
		return
	if _unlocked_achievement_ids.has(achievement_id):
		return
	if _steam == null:
		return
	for method_name in ["setAchievement", "set_achievement"]:
		if _steam.has_method(method_name):
			_steam.call(method_name, achievement_id)
			break
	_unlocked_achievement_ids[achievement_id] = true
	_store_unlocked_achievement_ids()


func _clear_achievement(achievement_id: String) -> bool:
	if achievement_id.is_empty() or _steam == null:
		return false
	for method_name in ["clearAchievement", "clear_achievement"]:
		if not _steam.has_method(method_name):
			continue
		var response: Variant = _steam.call(method_name, achievement_id)
		if not (response is bool) or bool(response):
			return true
	return false


func _request_current_stats() -> bool:
	if _steam == null:
		return false
	for method_name in ["requestCurrentStats", "request_current_stats"]:
		if not _steam.has_method(method_name):
			continue
		var response: Variant = _steam.call(method_name)
		if not (response is bool) or bool(response):
			return true
	return false


func _pump_steam_callbacks(iterations: int = 1) -> void:
	for _index in range(iterations):
		if _steam != null and _steam.has_method("run_callbacks"):
			_steam.call("run_callbacks")
		await get_tree().process_frame


func _wait_for_user_stats_received(timeout_frames: int = 180) -> bool:
	var initial_count := _user_stats_received_count
	for _index in range(timeout_frames):
		await _pump_steam_callbacks()
		if _user_stats_received_count > initial_count:
			return true
	return false


func _wait_for_user_stats_stored(timeout_frames: int = 180) -> bool:
	var initial_count := _user_stats_stored_count
	for _index in range(timeout_frames):
		await _pump_steam_callbacks()
		if _user_stats_stored_count > initial_count:
			return true
	return false


func _are_tracked_stats_reset() -> bool:
	for stat_name_variant in TRACKED_STAT_DEFAULTS.keys():
		var stat_name := str(stat_name_variant)
		if _get_stat_from_steam(stat_name) != int(TRACKED_STAT_DEFAULTS[stat_name_variant]):
			return false
	return true


func _are_achievements_cleared() -> bool:
	for achievement_id_variant in ACHIEVEMENTS.keys():
		var achievement_id := str(achievement_id_variant)
		if _get_achievement_state_from_steam(achievement_id):
			return false
	return true


func _unlock_legend_if_ready() -> void:
	if _unlocked_achievement_ids.has(LEGEND_ID):
		return
	for achievement_id in ACHIEVEMENTS.keys():
		if achievement_id == LEGEND_ID:
			continue
		if not _unlocked_achievement_ids.has(achievement_id):
			return
	_unlock(LEGEND_ID, true)


func _set_stat(stat_name: String, value: int) -> void:
	if stat_name.is_empty() or not _resolve_steam_singleton():
		return
	_stats_cache[stat_name] = value
	for method_name in ["setStatInt", "set_stat_int", "setStat", "set_stat"]:
		if not _steam.has_method(method_name):
			continue
		match method_name:
			"setStat", "set_stat":
				_steam.call(method_name, stat_name, value)
			_:
				_steam.call(method_name, stat_name, value)
		return


func _get_stat_from_steam(stat_name: String) -> int:
	if stat_name.is_empty() or _steam == null:
		return 0
	for method_name in ["getStatInt", "get_stat_int", "getStat", "get_stat"]:
		if not _steam.has_method(method_name):
			continue
		var response: Variant = _steam.call(method_name, stat_name)
		if response is Dictionary:
			var response_dict: Dictionary = response as Dictionary
			for key in ["value", "stat", "result"]:
				if response_dict.has(key):
					return int(response_dict.get(key, 0))
		elif response is int or response is float:
			return int(response)
	return 0


func _store_stats() -> void:
	if _steam == null:
		return
	for method_name in ["storeStats", "store_stats"]:
		if _steam.has_method(method_name):
			_steam.call(method_name)
			return


func _resolve_steam_singleton() -> bool:
	if _steam != null:
		return true
	if not Engine.has_singleton("Steam"):
		return false
	var steam_client: Node = get_node_or_null("/root/SteamClient")
	if steam_client == null or not steam_client.has_method("is_ready") or not bool(steam_client.call("is_ready")):
		return false
	_steam = Engine.get_singleton("Steam")
	if _steam != null:
		_connect_steam_user_stats_signals()
	return _steam != null


func _connect_steam_user_stats_signals() -> void:
	if _steam == null:
		return
	if _steam.has_signal("user_stats_received") and not _steam.user_stats_received.is_connected(_on_user_stats_received):
		_steam.user_stats_received.connect(_on_user_stats_received)
	if _steam.has_signal("user_stats_stored") and not _steam.user_stats_stored.is_connected(_on_user_stats_stored):
		_steam.user_stats_stored.connect(_on_user_stats_stored)


func _on_user_stats_received(_game_id: int, result: int, _user: int) -> void:
	_user_stats_received_count += 1
	_last_user_stats_received_result = result


func _on_user_stats_stored(_game_id: int, result: int) -> void:
	_user_stats_stored_count += 1
	_last_user_stats_stored_result = result


func _get_achievement_state_from_steam(achievement_id: String) -> bool:
	if _steam == null:
		return false
	for method_name in ["getAchievement", "get_achievement"]:
		if not _steam.has_method(method_name):
			continue
		var response: Variant = _steam.call(method_name, achievement_id)
		if response is Dictionary:
			var response_dict: Dictionary = response as Dictionary
			for key in ["achieved", "unlocked", "value"]:
				if bool(response_dict.get(key, false)):
					return true
		elif response is bool:
			return bool(response)
	return false


func _extract_rank(payload: Dictionary) -> int:
	if payload.is_empty():
		return 0
	if payload.get("entry", null) is Dictionary:
		var entry: Dictionary = payload.get("entry", {}) as Dictionary
		if int(entry.get("rank", 0)) > 0:
			return int(entry.get("rank", 0))
	if int(payload.get("rank", 0)) > 0:
		return int(payload.get("rank", 0))
	return 0


func _leaderboard_rank_key(song_id: String, difficulty: String, mode: String) -> String:
	return "%s::%s::%s" % [song_id, mode, difficulty]


func _store_unlocked_achievement_ids() -> void:
	var achievement_ids: Array[String] = []
	for key_variant in _unlocked_achievement_ids.keys():
		achievement_ids.append(str(key_variant))
	achievement_ids.sort()
	ProfileStore.set_steam_unlocked_achievement_ids(achievement_ids)


func _seed_local_state_from_progression() -> void:
	for achievement_id in ProfileStore.get_steam_unlocked_achievement_ids():
		_unlocked_achievement_ids[achievement_id] = true
