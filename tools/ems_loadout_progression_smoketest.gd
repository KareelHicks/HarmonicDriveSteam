extends SceneTree

const EMSLoadoutCatalog := preload("res://scripts/ems/EMSLoadoutCatalog.gd")


func _initialize() -> void:
	await process_frame
	var profile_store := root.get_node("ProfileStore")
	var progression_manager := root.get_node("ProgressionManager")
	var original_progression := (profile_store.call("get_progression_data") as Dictionary).duplicate(true)
	var failures: Array[String] = []

	var legacy_progression := {
		"schema_version": 1,
		"level": 9,
		"xp": 42,
		"currency": 999,
		"unlocked_songs": [],
		"completed_songs": {},
		"unlocked_sections": 14,
		"owned_items": ["theme_default", "effect_none", "speed_1_0"],
		"equipped_items": {
			"theme": "theme_default",
			"effect": "effect_none",
			"speed_modifier": "speed_1_0",
			"enabled_modifiers": [],
		},
	}
	profile_store.call("set_progression_data", legacy_progression)
	progression_manager.call("_load_or_reset")
	await process_frame

	var player := progression_manager.call("get_player_data") as Dictionary
	var owned := _string_array(player.get("owned_items", []))
	for loadout in EMSLoadoutCatalog.get_core_loadouts():
		var loadout_id := str(loadout.get("id", ""))
		if not owned.has(loadout_id):
			failures.append("Migrated profile did not receive included EMS loadout %s." % loadout_id)
	if int(player.get("unlocked_sections", 0)) != 14:
		failures.append("Migration changed unlocked_sections from 14 to %d." % int(player.get("unlocked_sections", 0)))
	var equipped := progression_manager.call("get_equipped_loadout") as Dictionary
	if str(equipped.get("ems_loadout", "")) != EMSLoadoutCatalog.get_default_loadout_id():
		failures.append("Legacy profile did not default to Harmonic Core EMS loadout.")

	var equip_owned := progression_manager.call("equip_item", "ems_pixel_nebula") as Dictionary
	if not bool(equip_owned.get("ok", false)):
		failures.append("Included EMS loadout did not equip: %s" % str(equip_owned.get("message", "")))
	equipped = progression_manager.call("get_equipped_loadout") as Dictionary
	if str(equipped.get("ems_loadout", "")) != "ems_pixel_nebula":
		failures.append("Equipped EMS loadout did not persist after equip.")

	var equip_included := progression_manager.call("equip_item", "ems_singularity_bloom") as Dictionary
	if not bool(equip_included.get("ok", false)):
		failures.append("A built-in EMS loadout was still gated by section progress.")
	var purchase_route := progression_manager.call("purchase_item", "ems_thunder_matrix") as Dictionary
	if not bool(purchase_route.get("ok", false)):
		failures.append("Legacy purchase routing did not redirect an included EMS loadout to equip.")
	player = progression_manager.call("get_player_data") as Dictionary
	if int(player.get("currency", 0)) != 999:
		failures.append("Selecting an included EMS loadout charged VIBEZ.")
	owned = _string_array(player.get("owned_items", []))
	if not owned.has("ems_thunder_matrix"):
		failures.append("Included EMS loadout disappeared from normalized ownership.")
	if EMSLoadoutCatalog.ACQUISITION_SHOP_VARIANT != "shop_variant":
		failures.append("EMS catalog no longer exposes the future paid variant acquisition path.")

	profile_store.call("set_progression_data", original_progression)
	progression_manager.call("_load_or_reset")

	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("EMS loadout progression smoke test passed.")
	quit(0)


func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for item in value:
			result.append(str(item))
	return result
