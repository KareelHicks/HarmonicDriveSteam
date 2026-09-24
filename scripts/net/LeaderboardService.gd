extends Node
class_name LeaderboardService

const RelayAPIClient = preload("res://scripts/net/RelayAPIClient.gd")
const GameModeConfig = preload("res://scripts/gameplay/GameModeConfig.gd")

signal request_failed(route: String, message: String)
signal solo_score_submitted(entry: Dictionary)

var _api
var _identity_service
var _steam: Object
var _steam_leaderboard_handles: Dictionary = {}
var _steam_submission_queue: Array[Dictionary] = []
var _steam_find_queue: Array[Dictionary] = []
var _steam_find_request: Dictionary = {}
var _steam_upload_request: Dictionary = {}
var _steam_download_request: Dictionary = {}
var _steam_submission_in_flight := false
var _steam_download_request_id := 0

const STEAM_LEADERBOARD_SORT_DESCENDING := 2
const STEAM_LEADERBOARD_DISPLAY_NUMERIC := 1
const STEAM_LEADERBOARD_DATA_REQUEST_GLOBAL := 0
const STEAM_LEADERBOARD_DATA_REQUEST_GLOBAL_AROUND_USER := 1


func _ready() -> void:
	_api = RelayAPIClient.new()
	add_child(_api)
	_api.request_failed.connect(_on_request_failed)
	_try_connect_steam_signals()


func setup(identity_service) -> void:
	_identity_service = identity_service


func is_authenticated() -> bool:
	return _identity_service != null and _identity_service.is_authenticated()


func load_song_summaries(song_ids: Array[String], callback: Callable = Callable()) -> void:
	if not _ensure_identity(callback):
		return
	if song_ids.is_empty():
		if callback.is_valid():
			callback.call(true, [])
		return
	var query_items: Array[Dictionary] = []
	for song_id in song_ids:
		query_items.append({"name": "song_id", "value": ContentRegistry.get_relay_song_id(song_id)})
	var route := _route_with_query(
		"/leaderboards/song-summaries",
		query_items
	)
	_api.call_api("GET", route, {}, _identity_service.get_backend_token(), func(success, _data, payload, _meta):
		if not success:
			if callback.is_valid():
				callback.call(false, [])
			return
		var summaries: Array = []
		for summary_variant in (payload.get("summaries", []) as Array):
			if summary_variant is Dictionary:
				var summary: Dictionary = (summary_variant as Dictionary).duplicate(true)
				summary["songID"] = ContentRegistry.get_song_id(str(summary.get("songID", "")))
				summaries.append(summary)
		if callback.is_valid():
			callback.call(true, summaries)
	)


func load_top_scores(song_id: String, difficulty: String, mode: String, limit: int = 100, callback: Callable = Callable()) -> void:
	if not _ensure_identity(callback):
		return
	var route := _route_with_query(
		"/leaderboards/top",
		[
			{"name": "song_id", "value": ContentRegistry.get_relay_song_id(song_id)},
			{"name": "difficulty", "value": _backend_difficulty(difficulty)},
			{"name": "mode", "value": _backend_mode(mode)},
			{"name": "limit", "value": str(limit)},
		]
	)
	_api.call_api("GET", route, {}, _identity_service.get_backend_token(), func(success, _data, payload, _meta):
		if not success:
			if callback.is_valid():
				callback.call(false, [])
			return
		var entries: Array = []
		for entry_variant in (payload.get("entries", []) as Array):
			if entry_variant is Dictionary:
				entries.append(_normalize_relay_leaderboard_entry(entry_variant as Dictionary))
		if callback.is_valid():
			callback.call(true, entries)
	)


func submit_solo_score(song_entry: Dictionary, result: Dictionary, callback: Callable = Callable()) -> void:
	if not _ensure_identity(callback):
		return
	var payload := {
		"songID": ContentRegistry.get_relay_song_id(str(song_entry.get("id", ""))),
		"difficulty": _backend_difficulty(str(result.get("difficulty", "Medium"))),
		"mode": _backend_mode(str(result.get("mode", GameModeConfig.DEFAULT_MODE))),
		"perfect": int(result.get("perfect", 0)),
		"great": int(result.get("great", 0)),
		"good": int(result.get("good", 0)),
		"miss": int(result.get("miss", 0)),
		"maxCombo": int(result.get("max_combo", 0)),
		"sustainTicks": int(result.get("sustain_ticks", 0)),
		"holdSuccesses": int(result.get("hold_successes", 0)),
		"holdBreaks": int(result.get("hold_breaks", 0)),
		"chartHash": str(result.get("chart_hash", "")),
		"reportedScore": int(result.get("score", 0)),
		"reportedAccuracy": clampf(float(result.get("accuracy", 0.0)) / 100.0, 0.0, 1.0),
		"scoringEvents": result.get("scoring_events", []),
	}
	_api.call_api("POST", "/scores", payload, _identity_service.get_backend_token(), func(success, _data, payload_data, _meta):
		if success:
			solo_score_submitted.emit(payload_data.duplicate(true))
		if callback.is_valid():
			callback.call(success, payload_data.duplicate(true))
	)


func submit_steam_score_if_eligible(song_entry: Dictionary, result: Dictionary, previous_best_score: int) -> void:
	if not _can_submit_to_steam():
		return
	var submitted_score := int(result.get("score", 0))
	var is_first_entry := previous_best_score <= 0
	if not is_first_entry and submitted_score <= previous_best_score:
		return
	var request := {
		"kind": "submit",
		"leaderboard_name": _steam_leaderboard_name(song_entry, result),
		"score": submitted_score,
		"details": _steam_score_details(result),
		"find_method": "find_or_create",
	}
	_steam_submission_queue.append(request)
	_process_next_steam_submission()


func load_top_steam_scores(song_id: String, difficulty: String, mode: String, limit: int = 100, callback: Callable = Callable()) -> void:
	if not _can_submit_to_steam():
		if callback.is_valid():
			callback.call(false, [])
		return
	var request := {
		"kind": "download",
		"leaderboard_name": "HD_%s_%s_%s" % [song_id, mode, difficulty],
		"limit": maxi(1, limit),
		"callback": callback,
		"find_method": "find",
	}
	var leaderboard_handle := int(_steam_leaderboard_handles.get(str(request.get("leaderboard_name", "")), 0))
	if leaderboard_handle > 0:
		_begin_steam_global_download(leaderboard_handle, request)
		return
	_enqueue_steam_find_request(request)


func _ensure_identity(callback: Callable = Callable()) -> bool:
	if _identity_service == null or not _identity_service.is_authenticated():
		if callback.is_valid():
			callback.call(false, [])
		return false
	return true


func _route_with_query(route: String, query_items: Array) -> String:
	if query_items.is_empty():
		return route
	var encoded_parts: Array[String] = []
	for item_variant in query_items:
		if not (item_variant is Dictionary):
			continue
		var item: Dictionary = item_variant as Dictionary
		var name: String = str(item.get("name", "")).uri_encode()
		var value: String = str(item.get("value", "")).uri_encode()
		if name.is_empty():
			continue
		encoded_parts.append("%s=%s" % [name, value])
	return "%s?%s" % [route, "&".join(encoded_parts)]


func _backend_difficulty(display_value: String) -> String:
	match display_value.to_lower():
		"easy":
			return "easy"
		"medium":
			return "medium"
		"hard":
			return "hard"
		"expert":
			return "expert"
		"professional":
			return "professional"
		_:
			return display_value.to_lower()


func _backend_mode(mode_id: String) -> String:
	match mode_id:
		GameModeConfig.SYNTHESIZED:
			return "synthesized"
		GameModeConfig.STEMS_RANDOM:
			return "stems_random"
		_:
			return "stems_mapped"


func _normalize_relay_leaderboard_entry(raw_entry: Dictionary) -> Dictionary:
	var entry: Dictionary = raw_entry.duplicate(true)
	entry["songID"] = ContentRegistry.get_song_id(str(entry.get("songID", "")))
	entry["platform"] = _normalize_leaderboard_platform(str(entry.get("platform", "apple")))
	return entry


func _normalize_leaderboard_platform(raw_platform: String) -> String:
	match raw_platform.strip_edges().to_lower():
		"android":
			return "android"
		"steam":
			return "steam"
		"guest":
			return "guest"
		"apple", "ios", "gamecenter", "game_center":
			return "apple"
		_:
			return "apple"


func _on_request_failed(route: String, message: String) -> void:
	push_warning("Railway leaderboard submission failed for %s: %s" % [route, message])
	request_failed.emit(route, message)


func _can_submit_to_steam() -> bool:
	if AppState == null or not AppState.can_use_steam_services():
		return false
	return _resolve_steam_singleton()


func _resolve_steam_singleton() -> bool:
	if _steam != null:
		return true
	if not Engine.has_singleton("Steam"):
		return false
	_steam = Engine.get_singleton("Steam")
	if _steam == null:
		return false
	_try_connect_steam_signals()
	return true


func _try_connect_steam_signals() -> void:
	if _steam == null and Engine.has_singleton("Steam"):
		_steam = Engine.get_singleton("Steam")
	if _steam == null:
		return
	if _steam.has_signal("leaderboard_find_result") and not _steam.leaderboard_find_result.is_connected(_on_steam_leaderboard_find_result):
		_steam.leaderboard_find_result.connect(_on_steam_leaderboard_find_result)
	if _steam.has_signal("leaderboard_score_uploaded") and not _steam.leaderboard_score_uploaded.is_connected(_on_steam_leaderboard_score_uploaded):
		_steam.leaderboard_score_uploaded.connect(_on_steam_leaderboard_score_uploaded)
	if _steam.has_signal("leaderboard_scores_downloaded") and not _steam.leaderboard_scores_downloaded.is_connected(_on_steam_leaderboard_scores_downloaded):
		_steam.leaderboard_scores_downloaded.connect(_on_steam_leaderboard_scores_downloaded)


func _steam_leaderboard_name(song_entry: Dictionary, result: Dictionary) -> String:
	return "HD_%s_%s_%s" % [
		str(song_entry.get("id", "")).strip_edges(),
		str(result.get("mode", GameModeConfig.DEFAULT_MODE)).strip_edges(),
		str(result.get("difficulty", "Medium")).strip_edges(),
	]


func _steam_score_details(result: Dictionary) -> PackedInt32Array:
	var accuracy_scaled := int(round(clampf(float(result.get("accuracy", 0.0)), 0.0, 100.0) * 1000.0))
	var submitted_unix := int(Time.get_unix_time_from_system())
	return PackedInt32Array([
		accuracy_scaled,
		int(result.get("max_combo", 0)),
		int(result.get("perfect", 0)),
		int(result.get("miss", 0)),
		submitted_unix,
	])


func _process_next_steam_submission() -> void:
	if _steam_submission_in_flight or _steam_submission_queue.is_empty():
		return
	if not _can_submit_to_steam():
		var skipped_request: Dictionary = _steam_submission_queue.pop_front() as Dictionary
		_log_steam_failure(str(skipped_request.get("leaderboard_name", "")), "Steam submission unavailable on this client.")
		_process_next_steam_submission()
		return
	var request: Dictionary = _steam_submission_queue.pop_front() as Dictionary
	var leaderboard_name := str(request.get("leaderboard_name", "")).strip_edges()
	if leaderboard_name.is_empty():
		_log_steam_failure("", "Leaderboard name was empty.")
		return
	var leaderboard_handle := int(_steam_leaderboard_handles.get(leaderboard_name, 0))
	_steam_submission_in_flight = true
	if leaderboard_handle > 0:
		_submit_score_to_steam(leaderboard_handle, request)
		return
	_enqueue_steam_find_request(request)


func _submit_score_to_steam(leaderboard_handle: int, request: Dictionary) -> void:
	if _steam == null or leaderboard_handle <= 0:
		_steam_submission_in_flight = false
		_log_steam_failure(str(request.get("leaderboard_name", "")), "Leaderboard handle was invalid.")
		_process_next_steam_submission()
		return
	_steam_upload_request = request.duplicate(true)
	_steam_upload_request["leaderboard_handle"] = leaderboard_handle
	for method_name in ["uploadLeaderboardScore", "upload_leaderboard_score"]:
		if not _steam.has_method(method_name):
			continue
		_steam.call(
			method_name,
			int(request.get("score", 0)),
			true,
			request.get("details", PackedInt32Array()),
			leaderboard_handle
		)
		return
	_steam_submission_in_flight = false
	_steam_upload_request.clear()
	_log_steam_failure(str(request.get("leaderboard_name", "")), "uploadLeaderboardScore is unavailable.")
	_process_next_steam_submission()


func _on_steam_leaderboard_find_result(new_handle: int, was_found: int) -> void:
	if _steam_find_request.is_empty():
		return
	var request := _steam_find_request.duplicate(true)
	_steam_find_request.clear()
	var leaderboard_name := str(request.get("leaderboard_name", ""))
	if was_found != 1 or new_handle <= 0:
		if str(request.get("kind", "")) == "download":
			_log_steam_failure(leaderboard_name, "Steam leaderboard could not be found.")
			var callback: Callable = request.get("callback") as Callable
			if callback.is_valid():
				callback.call(false, [])
		else:
			_steam_submission_in_flight = false
			_log_steam_failure(leaderboard_name, "findOrCreateLeaderboard failed.")
			_process_next_steam_submission()
		_process_next_steam_find_request()
		return
	_steam_leaderboard_handles[leaderboard_name] = new_handle
	if str(request.get("kind", "")) == "download":
		_begin_steam_global_download(new_handle, request)
	else:
		_submit_score_to_steam(new_handle, request)
	_process_next_steam_find_request()


func _on_steam_leaderboard_score_uploaded(success: int, this_handle: int, this_score: Dictionary) -> void:
	if _steam_upload_request.is_empty():
		return
	var request := _steam_upload_request.duplicate(true)
	_steam_upload_request.clear()
	_steam_submission_in_flight = false
	var leaderboard_name := str(request.get("leaderboard_name", ""))
	if success != 1:
		_log_steam_failure(leaderboard_name, "uploadLeaderboardScore failed for handle %d." % this_handle)
		_process_next_steam_submission()
		return
	if int(this_score.get("score_changed", 1)) == 0:
		print("Steam leaderboard kept previous best for %s." % leaderboard_name)
	else:
		print("Steam leaderboard submitted score for %s." % leaderboard_name)
	_process_next_steam_submission()


func _log_steam_failure(leaderboard_name: String, message: String) -> void:
	var prefix := "Steam leaderboard submission failed"
	if not leaderboard_name.is_empty():
		push_warning("%s for %s: %s" % [prefix, leaderboard_name, message])
	else:
		push_warning("%s: %s" % [prefix, message])


func _enqueue_steam_find_request(request: Dictionary) -> void:
	_steam_find_queue.append(request.duplicate(true))
	_process_next_steam_find_request()


func _process_next_steam_find_request() -> void:
	if not _steam_find_request.is_empty() or _steam_find_queue.is_empty():
		return
	var request: Dictionary = _steam_find_queue.pop_front() as Dictionary
	var leaderboard_name := str(request.get("leaderboard_name", "")).strip_edges()
	if leaderboard_name.is_empty():
		var callback: Callable = request.get("callback") as Callable
		if str(request.get("kind", "")) == "submit":
			_steam_submission_in_flight = false
			_process_next_steam_submission()
		elif callback.is_valid():
			callback.call(false, [])
		return
	var find_method := str(request.get("find_method", "find_or_create"))
	var can_find := _steam != null and (
		(find_method == "find" and (_steam.has_method("findLeaderboard") or _steam.has_method("find_leaderboard"))) or
		(find_method != "find" and (_steam.has_method("findOrCreateLeaderboard") or _steam.has_method("find_or_create_leaderboard")))
	)
	if not can_find:
		_log_steam_failure(leaderboard_name, "%s is unavailable." % ("findLeaderboard" if find_method == "find" else "findOrCreateLeaderboard"))
		var callback: Callable = request.get("callback") as Callable
		if str(request.get("kind", "")) == "submit":
			_steam_submission_in_flight = false
			_process_next_steam_submission()
		elif callback.is_valid():
			callback.call(false, [])
		_process_next_steam_find_request()
		return
	_steam_find_request = request
	if find_method == "find":
		if _steam.has_method("findLeaderboard"):
			_steam.call("findLeaderboard", leaderboard_name)
		else:
			_steam.call("find_leaderboard", leaderboard_name)
	else:
		var create_method := "findOrCreateLeaderboard" if _steam.has_method("findOrCreateLeaderboard") else "find_or_create_leaderboard"
		_steam.call(
			create_method,
			leaderboard_name,
			STEAM_LEADERBOARD_SORT_DESCENDING,
			STEAM_LEADERBOARD_DISPLAY_NUMERIC
		)


func _begin_steam_global_download(leaderboard_handle: int, request: Dictionary) -> void:
	var download_method := ""
	for method_name in ["downloadLeaderboardEntries", "download_leaderboard_entries"]:
		if _steam != null and _steam.has_method(method_name):
			download_method = method_name
			break
	if download_method.is_empty():
		var callback: Callable = request.get("callback") as Callable
		_log_steam_failure(str(request.get("leaderboard_name", "")), "downloadLeaderboardEntries is unavailable.")
		if callback.is_valid():
			callback.call(false, [])
		return
	_steam_download_request = request.duplicate(true)
	_steam_download_request_id += 1
	_steam_download_request["request_id"] = _steam_download_request_id
	_steam_download_request["handle"] = leaderboard_handle
	_steam_download_request["phase"] = "global"
	_steam_download_request["global_entries"] = []
	_arm_steam_download_timeout(_steam_download_request_id)
	_steam.call(
		download_method,
		1,
		int(request.get("limit", 100)),
		STEAM_LEADERBOARD_DATA_REQUEST_GLOBAL,
		leaderboard_handle
	)


func _on_steam_leaderboard_scores_downloaded(arg1: Variant, arg2: Variant, arg3: Variant) -> void:
	var this_handle := 0
	var these_results: Array = []
	for value in [arg1, arg2, arg3]:
		if value is Array:
			these_results = value
		elif value is int or value is float:
			this_handle = int(value)
	if _steam_download_request.is_empty():
		return
	if int(_steam_download_request.get("handle", 0)) != this_handle:
		return
	var callback: Callable = _steam_download_request.get("callback") as Callable
	var phase := str(_steam_download_request.get("phase", "global"))
	var mapped_entries := _map_steam_leaderboard_entries(these_results)
	if phase == "global":
		var local_steam_id := _local_steam_id()
		var has_local_entry := local_steam_id.is_empty()
		for entry in mapped_entries:
			if str(entry.get("userID", "")) == local_steam_id:
				has_local_entry = true
				break
		var around_user_method := ""
		for method_name in ["downloadLeaderboardEntries", "download_leaderboard_entries"]:
			if _steam != null and _steam.has_method(method_name):
				around_user_method = method_name
				break
		if has_local_entry or around_user_method.is_empty():
			_steam_download_request.clear()
			if callback.is_valid():
				callback.call(true, mapped_entries)
			return
		_steam_download_request["phase"] = "around_user"
		_steam_download_request["global_entries"] = mapped_entries
		_steam.call(
			around_user_method,
			-2,
			2,
			STEAM_LEADERBOARD_DATA_REQUEST_GLOBAL_AROUND_USER,
			this_handle
		)
		return
	var merged := _merge_steam_entries(
		_steam_download_request.get("global_entries", []) as Array,
		mapped_entries
	)
	_steam_download_request.clear()
	if callback.is_valid():
		callback.call(true, merged)


func _arm_steam_download_timeout(request_id: int) -> void:
	var timer := get_tree().create_timer(6.0)
	timer.timeout.connect(func() -> void:
		if _steam_download_request.is_empty():
			return
		if int(_steam_download_request.get("request_id", -1)) != request_id:
			return
		var request := _steam_download_request.duplicate(true)
		_steam_download_request.clear()
		_log_steam_failure(str(request.get("leaderboard_name", "")), "Steam leaderboard request timed out.")
		var callback: Callable = request.get("callback") as Callable
		if callback.is_valid():
			callback.call(false, [])
	)


func _map_steam_leaderboard_entries(entries: Array) -> Array[Dictionary]:
	var mapped: Array[Dictionary] = []
	for entry_variant in entries:
		if not (entry_variant is Dictionary):
			continue
		var entry: Dictionary = entry_variant as Dictionary
		var details: Variant = entry.get("details", PackedInt32Array())
		var detail_array: Array = []
		if details is PackedInt32Array:
			for value in details:
				detail_array.append(int(value))
		elif details is Array:
			for value in details:
				detail_array.append(int(value))
		var accuracy_scaled := int(detail_array[0]) if detail_array.size() > 0 else 0
		var combo := int(detail_array[1]) if detail_array.size() > 1 else 0
		var perfect_count := int(detail_array[2]) if detail_array.size() > 2 else 0
		var miss_count := int(detail_array[3]) if detail_array.size() > 3 else 0
		var submitted_unix := int(detail_array[4]) if detail_array.size() > 4 else 0
		var steam_id := str(entry.get("steam_id", ""))
		mapped.append({
			"rank": int(entry.get("global_rank", 0)),
			"userID": steam_id,
			"displayName": _steam_persona_name(steam_id),
			"score": int(entry.get("score", 0)),
			"accuracy": float(accuracy_scaled) / 100000.0,
			"maxCombo": combo,
			"perfect": perfect_count,
			"miss": miss_count,
			"achievedAt": _steam_entry_datetime(submitted_unix),
			"source": "steam",
		})
	return mapped


func _merge_steam_entries(global_entries: Array, around_user_entries: Array) -> Array[Dictionary]:
	var merged: Array[Dictionary] = []
	var seen_ids: Dictionary = {}
	for source_entries in [global_entries, around_user_entries]:
		for entry_variant in source_entries:
			if not (entry_variant is Dictionary):
				continue
			var entry: Dictionary = (entry_variant as Dictionary).duplicate(true)
			var key := str(entry.get("userID", ""))
			if key.is_empty():
				key = "rank:%d" % int(entry.get("rank", 0))
			if seen_ids.has(key):
				continue
			seen_ids[key] = true
			merged.append(entry)
	merged.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("rank", 0)) < int(b.get("rank", 0))
	)
	return merged


func _steam_persona_name(steam_id: String) -> String:
	if _steam == null:
		return "Steam Player"
	var local_id := _local_steam_id()
	if steam_id == local_id and _steam.has_method("getPersonaName"):
		return str(_steam.call("getPersonaName")).strip_edges()
	if _steam.has_method("getFriendPersonaName"):
		var persona_name := str(_steam.call("getFriendPersonaName", int(steam_id))).strip_edges()
		if not persona_name.is_empty() and persona_name != "[unknown]":
			return persona_name
	return "Steam Player"


func _local_steam_id() -> String:
	if _steam == null or not _steam.has_method("getSteamID"):
		return ""
	return str(_steam.call("getSteamID")).strip_edges()


func _steam_entry_datetime(unix_time: int) -> String:
	if unix_time <= 0:
		return ""
	var parts := Time.get_datetime_dict_from_unix_time(unix_time)
	return "%04d-%02d-%02d %02d:%02d" % [
		int(parts.get("year", 0)),
		int(parts.get("month", 0)),
		int(parts.get("day", 0)),
		int(parts.get("hour", 0)),
		int(parts.get("minute", 0)),
	]
