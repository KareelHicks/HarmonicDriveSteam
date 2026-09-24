extends Node

const EMSLoadoutCatalog = preload("res://scripts/ems/EMSLoadoutCatalog.gd")
const EMSPackLoader = preload("res://systems/ems/EMSPackLoader.gd")
const EMSValidator = preload("res://systems/ems/EMSValidator.gd")
const EMSWorkshopManager = preload("res://systems/ems/EMSWorkshopManager.gd")

signal registry_changed
signal active_ems_changed(pack_id: String)

const SOURCE_BUILT_IN := "built_in"
const SOURCE_UNLOCKED := "unlocked"
const SOURCE_LOCAL := "local"
const SOURCE_WORKSHOP := "workshop"
const ACQUISITION_COMMUNITY := "community"
const PLAYTIME_SYNC_RETRY_INTERVAL_MSEC := 1000
const PLAYTIME_SYNC_MAX_RETRIES := 20

var _entries: Dictionary = {}
var _entries_by_source: Dictionary = {}
var _invalid_entries: Array[Dictionary] = []
var _workshop_manager := EMSWorkshopManager.new()
var _pending_playtime_sync := false
var _next_playtime_sync_msec := 0
var _playtime_sync_attempts := 0


func _ready() -> void:
	reload()


func _exit_tree() -> void:
	_workshop_manager.stop_playtime_tracking()


func _process(_delta: float) -> void:
	if not _pending_playtime_sync:
		return
	if Time.get_ticks_msec() < _next_playtime_sync_msec:
		return
	sync_active_workshop_playtime()


func reload() -> void:
	EMSPackLoader.ensure_user_dirs()
	_entries.clear()
	_entries_by_source.clear()
	_invalid_entries.clear()
	for source in [SOURCE_BUILT_IN, SOURCE_UNLOCKED, SOURCE_LOCAL, SOURCE_WORKSHOP]:
		_entries_by_source[source] = []
	_load_builtin_entries()
	_load_pack_entries(EMSPackLoader.scan_workshop())
	_load_pack_entries(EMSPackLoader.scan_local())
	registry_changed.emit()
	call_deferred("sync_active_workshop_playtime")


func get_all_entries(include_unavailable := false) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for source in [SOURCE_BUILT_IN, SOURCE_UNLOCKED, SOURCE_WORKSHOP, SOURCE_LOCAL]:
		out.append_array(get_entries_by_source(source, include_unavailable))
	out.append_array(_invalid_entries.duplicate(true))
	return out


func get_entries_by_source(source: String, include_unavailable := false) -> Array[Dictionary]:
	var values: Array = _entries_by_source.get(source, []) as Array
	var out: Array[Dictionary] = []
	for item in values:
		if item is Dictionary:
			var entry := item as Dictionary
			if include_unavailable or _entry_content_available(entry):
				out.append(entry.duplicate(true))
	return out


func get_shop_items() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in get_all_entries():
		if str(entry.get("validation_status", "valid")) == "invalid":
			continue
		var item := entry.duplicate(true)
		item.erase("config")
		item.erase("validation")
		out.append(item)
	return out


func get_entry(pack_id: String) -> Dictionary:
	if _entries.has(pack_id):
		return (_entries[pack_id] as Dictionary).duplicate(true)
	return {}


func is_valid_ems(pack_id: String) -> bool:
	var entry := get_entry(pack_id)
	if entry.is_empty():
		return false
	return str(entry.get("validation_status", "valid")) != "invalid"


func set_active_ems(pack_id: String) -> Dictionary:
	if not is_valid_ems(pack_id):
		var fallback := EMSLoadoutCatalog.get_default_loadout_id()
		_set_progression_ems(fallback)
		active_ems_changed.emit(fallback)
		sync_active_workshop_playtime()
		return {"ok": false, "message": "EMS pack is missing or invalid. Reverted to Harmonic Core.", "active_id": fallback}
	var result := _set_progression_ems(pack_id)
	if bool(result.get("ok", false)):
		active_ems_changed.emit(pack_id)
		sync_active_workshop_playtime()
	return result


func get_active_ems() -> Dictionary:
	var active_id := _active_ems_id_from_profile()
	if not is_valid_ems(active_id):
		active_id = EMSLoadoutCatalog.get_default_loadout_id()
	return get_entry(active_id)


func get_active_config() -> Dictionary:
	return get_entry_config(str(get_active_ems().get("id", EMSLoadoutCatalog.get_default_loadout_id())))


func get_entry_config(pack_id: String) -> Dictionary:
	var entry := get_entry(pack_id)
	if entry.is_empty():
		entry = get_entry(EMSLoadoutCatalog.get_default_loadout_id())
	return (entry.get("config", {}) as Dictionary).duplicate(true)


func get_display_name(pack_id: String) -> String:
	var entry := get_entry(pack_id)
	if entry.is_empty():
		return EMSLoadoutCatalog.get_display_name(EMSLoadoutCatalog.get_default_loadout_id())
	return str(entry.get("display_name", "Harmonic Core"))


func is_community_ems(pack_id: String) -> bool:
	return str(get_entry(pack_id).get("acquisition", "")) == ACQUISITION_COMMUNITY


func sync_active_workshop_playtime() -> Dictionary:
	var entry := get_active_ems()
	if str(entry.get("source", "")) != SOURCE_WORKSHOP:
		_clear_pending_playtime_sync()
		return _workshop_manager.set_active_playtime_item("")
	var item_id := _workshop_item_id_from_entry(entry)
	if item_id.is_empty():
		_clear_pending_playtime_sync()
		return _workshop_manager.set_active_playtime_item("")
	var result := _workshop_manager.set_active_playtime_item(item_id)
	if bool(result.get("ok", false)):
		_clear_pending_playtime_sync()
	else:
		_schedule_playtime_sync_retry()
	return result


func get_workshop_playtime_status() -> Dictionary:
	return _workshop_manager.get_playtime_status()


func _load_builtin_entries() -> void:
	for loadout in EMSLoadoutCatalog.get_core_loadouts():
		var entry := loadout.duplicate(true)
		var loadout_id := str(entry.get("id", ""))
		entry["source"] = SOURCE_BUILT_IN
		entry["pack_id"] = loadout_id
		entry["pack_type"] = "built_in"
		entry["author"] = "Harmonic Drive"
		entry["preview_path"] = EMSLoadoutCatalog.get_preview_path(loadout_id)
		entry["validation_status"] = "built_in"
		entry["motion_intensity"] = 1.0
		entry["particle_intensity"] = 1.0
		entry["audio_reactive"] = true
		var config: Dictionary = entry.get("config", {}) as Dictionary
		config["community_runtime"] = false
		entry["config"] = config
		_register_entry(entry)


func _load_pack_entries(entries: Array[Dictionary]) -> void:
	for entry_variant in entries:
		var entry := entry_variant.duplicate(true)
		if str(entry.get("validation_status", "valid")) == "invalid":
			_invalid_entries.append(entry)
			continue
		var raw_config: Dictionary = entry.get("config", {}) as Dictionary
		entry["config"] = _community_runtime_config(entry, raw_config)
		_register_entry(entry)


func _register_entry(entry: Dictionary) -> void:
	var entry_id := str(entry.get("id", ""))
	if entry_id.is_empty():
		return
	if _entries.has(entry_id):
		entry = _unique_community_entry(entry)
		entry_id = str(entry.get("id", ""))
	_entries[entry_id] = entry
	var source := str(entry.get("source", SOURCE_LOCAL))
	if not _entries_by_source.has(source):
		_entries_by_source[source] = []
	(_entries_by_source[source] as Array).append(entry)


func _entry_content_available(entry: Dictionary) -> bool:
	var source := str(entry.get("source", ""))
	if source != SOURCE_BUILT_IN and source != SOURCE_UNLOCKED:
		return true
	return EMSLoadoutCatalog.is_loadout_content_available(entry)


func _unique_community_entry(entry: Dictionary) -> Dictionary:
	var source := str(entry.get("source", SOURCE_LOCAL))
	var base_pack_id := EMSValidator.sanitize_pack_id(str(entry.get("folder_path", "")).get_file())
	if base_pack_id.is_empty():
		base_pack_id = EMSValidator.sanitize_pack_id(str(entry.get("pack_id", "community_ems")))
	if base_pack_id.is_empty():
		base_pack_id = "community_ems"
	var candidate := "community:%s:%s" % [source, base_pack_id]
	var index := 2
	while _entries.has(candidate):
		candidate = "community:%s:%s_%d" % [source, base_pack_id, index]
		index += 1
	entry["id"] = candidate
	entry["pack_id"] = candidate.split(":")[-1]
	return entry


func _community_runtime_config(entry: Dictionary, raw_config: Dictionary) -> Dictionary:
	var palette: Dictionary = raw_config.get("palette", {}) as Dictionary
	var colors: Array = palette.get("colors", []) as Array
	var layout: Dictionary = raw_config.get("layout", {}) as Dictionary
	return {
		"profile_driven": false,
		"community_runtime": true,
		"community_pack_config": raw_config.duplicate(true),
		"community_layout": layout.duplicate(true),
		"community_background_region": str(layout.get("background_region", "gutters")),
		"motion_profile": "community",
		"signature_effect": "community_runtime",
		"classic_layer_mix": {
			"gradient": false,
			"depth": false,
			"particles": false,
			"fog": false,
			"ribbon": false,
			"glyph": false,
			"ripple": false,
			"pulse": false,
		},
		"palette_morph": str(palette.get("morph", "community")),
		"reaction_model": "community_events",
		"workshop_item_id": str(entry.get("workshop_item_id", "")),
		"palette": _palette_colors(colors),
		"background_mode": "solid",
		"background_solid_color": _background_color(colors),
		"background_brightness": 0.34,
		"trippy_level": "medium",
		"hit_effect": "circular",
		"style_multiplier": 1.0,
		"layer_weights": {
			"gradient": 0.0,
			"depth": 0.0,
			"particles": 0.0,
			"fog": 0.0,
			"ribbon": 0.0,
			"glyph": 0.0,
			"ripple": 0.0,
			"distortion": 0.65,
			"gameplay_shader": 0.45,
			"pressure_wave": 0.55,
		},
		"display_name": str(entry.get("display_name", "Community EMS")),
	}


func _workshop_item_id_from_entry(entry: Dictionary) -> String:
	var item_id := str(entry.get("workshop_item_id", "")).strip_edges()
	if item_id.is_empty():
		var config: Dictionary = entry.get("config", {}) as Dictionary
		item_id = str(config.get("_workshop_item_id", config.get("workshop_item_id", ""))).strip_edges()
	if item_id.is_empty():
		var raw_config: Dictionary = (entry.get("config", {}) as Dictionary).get("community_pack_config", {}) as Dictionary
		item_id = str(raw_config.get("_workshop_item_id", raw_config.get("workshop_item_id", ""))).strip_edges()
	if item_id.is_empty():
		var folder_id := str(entry.get("folder_path", "")).get_file()
		if folder_id.is_valid_int():
			item_id = folder_id
	if not item_id.is_valid_int() or int(item_id) <= 0:
		return ""
	return item_id


func _schedule_playtime_sync_retry() -> void:
	if _playtime_sync_attempts >= PLAYTIME_SYNC_MAX_RETRIES:
		_pending_playtime_sync = false
		return
	_pending_playtime_sync = true
	_playtime_sync_attempts += 1
	_next_playtime_sync_msec = Time.get_ticks_msec() + PLAYTIME_SYNC_RETRY_INTERVAL_MSEC


func _clear_pending_playtime_sync() -> void:
	_pending_playtime_sync = false
	_playtime_sync_attempts = 0
	_next_playtime_sync_msec = 0


func _palette_colors(colors: Array) -> Array[Color]:
	var out: Array[Color] = []
	for color_text in colors:
		out.append(EMSRuntimeColor.from_hex(str(color_text)))
	if out.is_empty():
		out = [Color(0.33, 0.87, 1.0, 1.0), Color(1.0, 0.30, 0.88, 1.0), Color(1.0, 0.90, 0.34, 1.0)]
	return out


func _background_color(colors: Array) -> Color:
	if colors.is_empty():
		return Color(0.025, 0.035, 0.075, 1.0)
	var color := EMSRuntimeColor.from_hex(str(colors[0]))
	return color.lerp(Color.BLACK, 0.72)


func _active_ems_id_from_profile() -> String:
	if ProfileStore == null:
		return EMSLoadoutCatalog.get_default_loadout_id()
	var progression: Dictionary = ProfileStore.get_progression_data()
	var equipped: Dictionary = progression.get("equipped_items", {}) as Dictionary
	return str(equipped.get("ems_loadout", EMSLoadoutCatalog.get_default_loadout_id()))


func _set_progression_ems(pack_id: String) -> Dictionary:
	if ProgressionManager != null and ProgressionManager.has_method("equip_item"):
		var player: Dictionary = ProgressionManager.get_player_data()
		var owned: Array[String] = []
		for item in (player.get("owned_items", []) as Array):
			owned.append(str(item))
		if not owned.has(pack_id) and is_community_ems(pack_id):
			ProgressionManager.call("grant_visual_item", pack_id)
		return ProgressionManager.equip_item(pack_id)
	if ProfileStore == null:
		return {"ok": false, "message": "Profile is unavailable."}
	var progression: Dictionary = ProfileStore.get_progression_data()
	var equipped: Dictionary = progression.get("equipped_items", {}) as Dictionary
	equipped["ems_loadout"] = pack_id
	progression["equipped_items"] = equipped
	ProfileStore.set_progression_data(progression)
	return {"ok": true, "message": "Updated EMS loadout."}


class EMSRuntimeColor:
	static func from_hex(value: String) -> Color:
		var hex := value.strip_edges()
		if hex.begins_with("#"):
			hex = hex.substr(1)
		if hex.length() == 6:
			hex += "FF"
		if hex.length() != 8:
			return Color(0.33, 0.87, 1.0, 1.0)
		return Color(
			float(hex.substr(0, 2).hex_to_int()) / 255.0,
			float(hex.substr(2, 2).hex_to_int()) / 255.0,
			float(hex.substr(4, 2).hex_to_int()) / 255.0,
			float(hex.substr(6, 2).hex_to_int()) / 255.0
		)
