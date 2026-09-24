extends Node

const GameModeConfig = preload("res://scripts/gameplay/GameModeConfig.gd")
const EMSLoadoutCatalog = preload("res://scripts/ems/EMSLoadoutCatalog.gd")
const ShopManager = preload("res://scripts/progression/ShopManager.gd")

signal progression_changed
signal section_unlocked(section_id: int, song_ids: Array[String])

const PROGRESSION_SCHEMA_VERSION := 1
const XP_REWARD_SCALE := 0.20
const CURRENCY_REWARD_SCALE := 0.10
const DEFAULT_DATA := {
	"schema_version": PROGRESSION_SCHEMA_VERSION,
	"level": 1,
	"xp": 0,
	"currency": 0,
	"unlocked_songs": [],
	"completed_songs": {},
	"unlocked_sections": 1,
	"owned_items": [],
	"equipped_items": {
		"theme": "theme_default",
		"effect": "effect_none",
		"ems_loadout": "ems_harmonic_core",
		"speed_modifier": "speed_1_0",
		"enabled_modifiers": [],
	},
}

const DIFFICULTY_MULTIPLIERS := {
	"Easy": 1.0,
	"Medium": 1.1,
	"Hard": 1.25,
	"Expert": 1.45,
	"Professional": 1.7,
}
const SECTION_DISPLAY_NAMES := [
	"",
	"Arrival",
	"Warmup",
	"Pulse",
	"Flow",
	"Drift",
	"Groove",
	"Lift",
	"Motion",
	"Energy",
	"Surge",
	"Drive",
	"Rush",
	"Euphoria",
	"Voltage",
	"Spectrum",
	"Horizon",
	"Resonance",
	"Orbit",
	"Hyperdrive",
	"Singularity",
]
const HIGHWAY_MODIFIERS := [
	"modifier_black_hole",
]

var _player_data: Dictionary = {}


func _ready() -> void:
	_load_or_reset()


func _load_or_reset() -> void:
	var stored: Dictionary = ProfileStore.get_progression_data()
	if int(stored.get("schema_version", 0)) != PROGRESSION_SCHEMA_VERSION:
		reset_progression()
		return
	_player_data = _normalize_player_data(stored)
	_persist()


func reset_progression() -> void:
	_player_data = _default_player_data()
	_player_data["unlocked_songs"] = _all_standard_song_ids()
	_persist()


func get_player_data() -> Dictionary:
	return _player_data.duplicate(true)


func get_equipped_loadout() -> Dictionary:
	var equipped: Dictionary = (_player_data.get("equipped_items", {}) as Dictionary).duplicate(true)
	var ems_loadout_id: String = str(equipped.get("ems_loadout", EMSLoadoutCatalog.get_default_loadout_id()))
	var ems_entry := _ems_registry_entry(ems_loadout_id)
	if ems_entry.is_empty():
		ems_loadout_id = EMSLoadoutCatalog.get_default_loadout_id()
		ems_entry = _ems_registry_entry(ems_loadout_id)
	equipped["ems_loadout"] = ems_loadout_id
	equipped["ems_loadout_display_name"] = str(ems_entry.get("display_name", EMSLoadoutCatalog.get_display_name(ems_loadout_id)))
	equipped["ems_loadout_config"] = (ems_entry.get("config", EMSLoadoutCatalog.get_config(ems_loadout_id)) as Dictionary).duplicate(true)
	var speed_id: String = str(equipped.get("speed_modifier", "speed_1_0"))
	var speed_item: Dictionary = ShopManager.get_item(speed_id)
	equipped["speed_value"] = float(speed_item.get("value", 1.0))
	equipped["ranked"] = _is_ranked_loadout(equipped)
	return equipped


func get_equipped_ems_loadout_id() -> String:
	return str(get_equipped_loadout().get("ems_loadout", EMSLoadoutCatalog.get_default_loadout_id()))


func is_song_unlocked(_song_id: String) -> bool:
	# Enter The Flow song access is independent of section progression. Premium
	# storefront access remains enforced separately by PremiumStore.
	return true


func is_song_multiplayer_accessible(song_id: String) -> bool:
	if song_id.is_empty():
		return false
	if not PremiumStore.is_premium_song(song_id):
		return true
	return PremiumStore.is_song_playable(song_id)


func get_section_for_song(song_id: String) -> Dictionary:
	return ContentRegistry.get_progression_song_meta(song_id)


func get_section_display_name(section_id: int) -> String:
	if section_id <= 0:
		return _get_default_section_display_name(1)
	var sections: Array[Dictionary] = ContentRegistry.get_progression_sections()
	for section in sections:
		if int(section.get("id", 0)) != section_id:
			continue
		var name: String = str(section.get("name", "")).strip_edges()
		if not name.is_empty():
			return name
		break
	return _get_default_section_display_name(section_id)


func _get_default_section_display_name(section_id: int) -> String:
	if section_id > 0 and section_id < SECTION_DISPLAY_NAMES.size():
		return str(SECTION_DISPLAY_NAMES[section_id])
	return "Section %d" % maxi(1, section_id)


func get_current_section_progress() -> Dictionary:
	var current_index: int = maxi(1, int(_player_data.get("unlocked_sections", 1))) - 1
	var sections: Array[Dictionary] = ContentRegistry.get_progression_sections()
	if current_index < 0 or current_index >= sections.size():
		return {}
	var section: Dictionary = sections[current_index]
	var songs: Array[String] = _string_array(section.get("songs", []))
	var eligible_songs: Array[String] = []
	for song_id in songs:
		if _counts_toward_section(song_id):
			eligible_songs.append(song_id)
	var clears := 0
	var completed: Dictionary = _player_data.get("completed_songs", {}) as Dictionary
	for song_id in eligible_songs:
		if completed.has(song_id):
			clears += 1
	var required: int = mini(int(section.get("unlock_requirement", 2)), eligible_songs.size())
	return {
		"section_id": int(section.get("id", current_index + 1)),
		"clears": clears,
		"required": required,
		"song_ids": songs,
		"eligible_song_ids": eligible_songs,
	}


func calculate_xp(score: int, accuracy: float, difficulty_multiplier: float) -> int:
	var base_xp: float = float(score) / 1000.0
	var accuracy_bonus: float = accuracy
	var total_xp: float = (base_xp + accuracy_bonus) * difficulty_multiplier * XP_REWARD_SCALE
	return maxi(0, int(round(total_xp)))


func xp_required_for_next_level(level: int = int(_player_data.get("level", 1))) -> int:
	return int(100 + pow(float(level), 1.5) * 50.0)


func calculate_currency(result: Dictionary) -> int:
	var currency: float = 0.0
	currency += float(result.get("perfect", 0)) * 2.0
	currency += float(result.get("great", 0)) * 1.0
	currency += float(result.get("good", 0)) * 0.5
	currency -= float(result.get("miss", 0)) * 1.0
	currency += float(result.get("score", 0)) / 5000.0
	currency *= CURRENCY_REWARD_SCALE
	return maxi(0, int(currency))


func on_song_complete(result_payload: Dictionary) -> Dictionary:
	var result: Dictionary = result_payload.duplicate(true)
	var ranked: bool = bool(result.get("ranked", true))
	var skip_progression_rewards := bool(result.get("skip_progression_rewards", false))
	var reward_eligible: bool = not skip_progression_rewards and not bool(result.get("no_fail_active", false)) and not bool(result.get("practice_forced_no_fail", false))
	var level_before: int = int(_player_data.get("level", 1))
	var xp_before: int = int(_player_data.get("xp", 0))
	var currency_before: int = int(_player_data.get("currency", 0))
	var xp_needed_before: int = xp_required_for_next_level(level_before)
	var difficulty: String = str(result.get("difficulty", "Medium"))
	var xp_earned := 0
	var currency_earned := 0
	if reward_eligible:
		xp_earned = calculate_xp(
			int(result.get("score", 0)),
			float(result.get("accuracy", 0.0)),
			float(DIFFICULTY_MULTIPLIERS.get(difficulty, 1.0))
		)
		currency_earned = calculate_currency(result)
		add_xp(xp_earned)
		add_currency(currency_earned)
	var completion: Dictionary = {"section_unlocked": {}, "newly_unlocked_song_ids": [], "newly_unlocked_ems_loadout_ids": []}
	if not skip_progression_rewards and not bool(result.get("skip_progression_completion", false)):
		completion = complete_song(str(result.get("song_id", "")), int(result.get("score", 0)))
	var reward_payload := {
		"xp_earned": xp_earned,
		"xp_before": xp_before,
		"xp_after": int(_player_data.get("xp", 0)),
		"xp_needed_before": xp_needed_before,
		"xp_needed_after": xp_required_for_next_level(int(_player_data.get("level", 1))),
		"currency_earned": currency_earned,
		"currency_before": currency_before,
		"currency_after": int(_player_data.get("currency", 0)),
		"level_before": level_before,
		"level_after": int(_player_data.get("level", 1)),
		"section_unlocked": completion.get("section_unlocked", {}),
		"newly_unlocked_song_ids": completion.get("newly_unlocked_song_ids", []),
		"newly_unlocked_ems_loadout_ids": completion.get("newly_unlocked_ems_loadout_ids", []),
		"current_section_progress": get_current_section_progress(),
		"ranked": ranked,
	}
	return reward_payload


func add_xp(amount: int) -> void:
	var xp_total: int = int(_player_data.get("xp", 0)) + maxi(0, amount)
	var level: int = int(_player_data.get("level", 1))
	var needed: int = xp_required_for_next_level(level)
	while xp_total >= needed:
		xp_total -= needed
		level += 1
		needed = xp_required_for_next_level(level)
	_player_data["xp"] = xp_total
	_player_data["level"] = level


func add_currency(amount: int) -> void:
	_player_data["currency"] = maxi(0, int(_player_data.get("currency", 0)) + amount)


func complete_song(song_id: String, score: int) -> Dictionary:
	var completed: Dictionary = (_player_data.get("completed_songs", {}) as Dictionary).duplicate(true)
	var entry: Dictionary = (completed.get(song_id, {}) as Dictionary).duplicate(true)
	entry["best_score"] = maxi(int(entry.get("best_score", 0)), score)
	entry["clear_count"] = int(entry.get("clear_count", 0)) + 1
	completed[song_id] = entry
	_player_data["completed_songs"] = completed
	var unlock_payload: Dictionary = check_section_unlock()
	_persist()
	return unlock_payload


func check_section_unlock() -> Dictionary:
	var progress: Dictionary = get_current_section_progress()
	if progress.is_empty():
		return {"section_unlocked": {}, "newly_unlocked_song_ids": [], "newly_unlocked_ems_loadout_ids": []}
	if int(progress.get("clears", 0)) < int(progress.get("required", 2)):
		return {"section_unlocked": {}, "newly_unlocked_song_ids": [], "newly_unlocked_ems_loadout_ids": []}
	return unlock_next_section()


func unlock_next_section() -> Dictionary:
	var sections: Array[Dictionary] = ContentRegistry.get_progression_sections()
	var current_unlocked: int = int(_player_data.get("unlocked_sections", 1))
	if current_unlocked >= sections.size():
		return {"section_unlocked": {}, "newly_unlocked_song_ids": [], "newly_unlocked_ems_loadout_ids": []}
	var next_index: int = current_unlocked
	var section: Dictionary = sections[next_index]
	var section_id: int = int(section.get("id", next_index + 1))
	var new_songs: Array[String] = []
	_player_data["unlocked_sections"] = next_index + 1
	section_unlocked.emit(section_id, new_songs)
	return {"section_unlocked": section.duplicate(true), "newly_unlocked_song_ids": new_songs, "newly_unlocked_ems_loadout_ids": []}


func purchase_item(item_id: String) -> Dictionary:
	var item: Dictionary = ShopManager.get_item(item_id)
	if item.is_empty():
		return {"ok": false, "message": "Item not found."}
	if str(item.get("type", "")) == "ems_loadout":
		return equip_item(item_id)
	if str(item.get("acquisition", "")) == "community":
		return {"ok": false, "message": "Community EMS packs are free. Select Equip instead."}
	var level: int = int(_player_data.get("level", 1))
	var required_level: int = ShopManager.get_required_level(item_id)
	if level < required_level:
		return {"ok": false, "message": "Reach level %d to unlock this item." % required_level}
	var owned: Array[String] = _string_array(_player_data.get("owned_items", []))
	if owned.has(item_id):
		return {"ok": false, "message": "Item already owned."}
	var price: int = int(item.get("price", 0))
	var currency: int = int(_player_data.get("currency", 0))
	if currency < price:
		return {"ok": false, "message": "Not enough VIBEZ."}
	_player_data["currency"] = currency - price
	owned.append(item_id)
	_player_data["owned_items"] = owned
	_persist()
	return {"ok": true, "message": "Purchased %s." % str(item.get("display_name", "item"))}


func equip_item(item_id: String) -> Dictionary:
	var item: Dictionary = ShopManager.get_item(item_id)
	if item.is_empty():
		return {"ok": false, "message": "Item not found."}
	var owned: Array[String] = _string_array(_player_data.get("owned_items", []))
	if not owned.has(item_id) and (str(item.get("type", "")) == "ems_loadout" or str(item.get("acquisition", "")) == "community"):
		owned.append(item_id)
		_player_data["owned_items"] = owned
	if not owned.has(item_id):
		return {"ok": false, "message": "Item not owned."}
	var equipped: Dictionary = (_player_data.get("equipped_items", {}) as Dictionary).duplicate(true)
	match str(item.get("type", "")):
		"theme":
			equipped["theme"] = item_id
		"effect":
			equipped["effect"] = item_id
		"ems_loadout":
			equipped["ems_loadout"] = item_id
		"speed_modifier":
			equipped["speed_modifier"] = item_id
		"modifier":
			var enabled: Array[String] = _string_array(equipped.get("enabled_modifiers", []))
			if enabled.has(item_id):
				enabled.erase(item_id)
			else:
				if HIGHWAY_MODIFIERS.has(item_id):
					for highway_modifier in HIGHWAY_MODIFIERS:
						enabled.erase(highway_modifier)
				enabled.append(item_id)
			equipped["enabled_modifiers"] = enabled
		_:
			return {"ok": false, "message": "Unsupported item type."}
	_player_data["equipped_items"] = equipped
	_persist()
	if str(item.get("type", "")) == "ems_loadout":
		_sync_active_ems_workshop_playtime()
	return {"ok": true, "message": "Updated loadout.", "equipped": equipped}


func grant_visual_item(item_id: String) -> void:
	var item := ShopManager.get_item(item_id)
	if item.is_empty():
		return
	var owned: Array[String] = _string_array(_player_data.get("owned_items", []))
	if not owned.has(item_id):
		owned.append(item_id)
		_player_data["owned_items"] = owned
		_persist()


func get_currency() -> int:
	return int(_player_data.get("currency", 0))


func get_level() -> int:
	return int(_player_data.get("level", 1))


func get_ranked_mode_flag() -> bool:
	return bool(get_equipped_loadout().get("ranked", true))


func _default_player_data() -> Dictionary:
	var data: Dictionary = DEFAULT_DATA.duplicate(true)
	data["owned_items"] = ShopManager.get_default_owned_items()
	return data


func _persist() -> void:
	ProfileStore.set_progression_data(_player_data)
	progression_changed.emit()


func _normalize_player_data(data: Dictionary) -> Dictionary:
	var merged: Dictionary = _default_player_data()
	for key_variant in data.keys():
		var key: String = str(key_variant)
		merged[key] = data[key_variant]
	if not (merged.get("completed_songs", {}) is Dictionary):
		merged["completed_songs"] = {}
	merged["unlocked_sections"] = maxi(1, int(merged.get("unlocked_sections", 1)))
	merged["owned_items"] = _normalized_owned_items(merged, int(merged.get("unlocked_sections", 1)))
	merged["equipped_items"] = _normalized_equipped_items(merged)
	_validate_equipped_items(merged)
	merged["unlocked_songs"] = _all_standard_song_ids(_string_array(merged.get("unlocked_songs", [])))
	merged["schema_version"] = PROGRESSION_SCHEMA_VERSION
	return merged


func _normalized_owned_items(data: Dictionary, unlocked_sections: int = 1) -> Array[String]:
	var _unused_unlocked_sections := unlocked_sections
	var owned: Array[String] = ShopManager.get_default_owned_items()
	for item_id in _string_array(data.get("owned_items", [])):
		if not owned.has(item_id):
			owned.append(item_id)
	_grant_all_ems_loadouts(owned)
	return owned


func _normalized_equipped_items(data: Dictionary) -> Dictionary:
	var equipped: Dictionary = (DEFAULT_DATA["equipped_items"] as Dictionary).duplicate(true)
	var incoming: Dictionary = data.get("equipped_items", {}) as Dictionary
	for key_variant in incoming.keys():
		var key: String = str(key_variant)
		equipped[key] = incoming[key_variant]
	equipped["enabled_modifiers"] = _string_array(equipped.get("enabled_modifiers", []))
	return equipped


func _validate_equipped_items(data: Dictionary) -> void:
	var owned: Array[String] = _string_array(data.get("owned_items", []))
	var equipped: Dictionary = data.get("equipped_items", {}) as Dictionary
	var default_equipped: Dictionary = DEFAULT_DATA["equipped_items"] as Dictionary
	for slot in ["theme", "effect", "speed_modifier", "ems_loadout"]:
		var item_id := str(equipped.get(slot, default_equipped.get(slot, "")))
		if not owned.has(item_id) or ShopManager.get_item(item_id).is_empty():
			equipped[slot] = default_equipped.get(slot, "")
	var enabled: Array[String] = []
	for modifier_id in _string_array(equipped.get("enabled_modifiers", [])):
		var modifier_item: Dictionary = ShopManager.get_item(modifier_id)
		if owned.has(modifier_id) and str(modifier_item.get("type", "")) == "modifier":
			enabled.append(modifier_id)
	equipped["enabled_modifiers"] = enabled
	data["equipped_items"] = equipped



func _grant_all_ems_loadouts(owned: Array[String]) -> void:
	for loadout in EMSLoadoutCatalog.get_content_available_core_loadouts():
		var loadout_id := str(loadout.get("id", ""))
		if loadout_id.is_empty():
			continue
		if not owned.has(loadout_id):
			owned.append(loadout_id)


func _is_ranked_loadout(equipped: Dictionary) -> bool:
	return _string_array(equipped.get("enabled_modifiers", [])).is_empty()


func _all_standard_song_ids(existing_song_ids: Array[String] = []) -> Array[String]:
	var unlocked: Array[String] = existing_song_ids.duplicate()
	for song in ContentRegistry.get_progression_ordered_songs():
		var song_id := str(song.get("id", ""))
		if song_id.is_empty() or PremiumStore.is_premium_song(song_id) or unlocked.has(song_id):
			continue
		unlocked.append(song_id)
	return unlocked


func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for item in value:
			result.append(str(item))
	return result


func _ems_registry_entry(loadout_id: String) -> Dictionary:
	var registry := get_node_or_null("/root/EMSRegistry")
	if registry != null and registry.has_method("get_entry"):
		var entry: Dictionary = registry.call("get_entry", loadout_id) as Dictionary
		if not entry.is_empty() and str(entry.get("validation_status", "valid")) != "invalid":
			return entry
	if EMSLoadoutCatalog.is_valid_loadout(loadout_id):
		return {
			"id": loadout_id,
			"display_name": EMSLoadoutCatalog.get_display_name(loadout_id),
			"config": EMSLoadoutCatalog.get_config(loadout_id),
		}
	return {}


func _sync_active_ems_workshop_playtime() -> void:
	var registry := get_node_or_null("/root/EMSRegistry")
	if registry != null and registry.has_method("sync_active_workshop_playtime"):
		registry.call("sync_active_workshop_playtime")


func _counts_toward_section(song_id: String) -> bool:
	if not PremiumStore.is_android_store_enabled():
		return true
	if not PremiumStore.is_premium_song(song_id):
		return true
	return PremiumStore.is_song_playable(song_id)
