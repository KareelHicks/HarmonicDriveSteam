extends RefCounted
class_name ShopManager

const EMSLoadoutCatalog = preload("res://scripts/ems/EMSLoadoutCatalog.gd")

const ITEMS: Array[Dictionary] = [
	{
		"id": "theme_default",
		"type": "theme",
		"display_name": "Default Theme",
		"description": "Original Harmonic Drive lane palette.",
		"price": 0,
		"default_owned": true,
		"required_level": 1,
	},
	{
		"id": "theme_neon",
		"type": "theme",
		"display_name": "Neon Theme",
		"description": "Bright cyan and purple lane colors.",
		"price": 160,
		"required_level": 2,
	},
	{
		"id": "theme_retro",
		"type": "theme",
		"display_name": "Retro Theme",
		"description": "Green-on-black arcade inspired palette.",
		"price": 180,
		"required_level": 3,
	},
	{
		"id": "theme_sunset",
		"type": "theme",
		"display_name": "Sunset Theme",
		"description": "Warm orange and pink lane palette.",
		"price": 220,
		"required_level": 4,
	},
	{
		"id": "theme_mono",
		"type": "theme",
		"display_name": "Mono Theme",
		"description": "Minimal monochrome contrast palette.",
		"price": 260,
		"required_level": 5,
	},
	{
		"id": "theme_synthwave",
		"type": "theme",
		"display_name": "Synthwave Theme",
		"description": "Ported synthwave palette inspired by the Apple build.",
		"price": 320,
		"required_level": 6,
	},
	{
		"id": "theme_aurora",
		"type": "theme",
		"display_name": "Aurora Theme",
		"description": "Icy teal and violet tones with a northern-lights glow.",
		"price": 360,
		"required_level": 7,
	},
	{
		"id": "theme_ember",
		"type": "theme",
		"display_name": "Ember Theme",
		"description": "Molten orange and red palette with a heated stage glow.",
		"price": 380,
		"required_level": 8,
	},
	{
		"id": "theme_oceanic",
		"type": "theme",
		"display_name": "Oceanic Theme",
		"description": "Deep-sea blues with glassy turquoise accents.",
		"price": 380,
		"required_level": 8,
	},
	{
		"id": "theme_void",
		"type": "theme",
		"display_name": "Void Theme",
		"description": "Dark cosmic hues with magenta and ultraviolet highlights.",
		"price": 420,
		"required_level": 9,
	},
	{
		"id": "theme_prism",
		"type": "theme",
		"display_name": "Prism Theme",
		"description": "Clean concert-light palette with bright refracted color.",
		"price": 440,
		"required_level": 10,
	},
	{
		"id": "theme_spiral",
		"type": "theme",
		"display_name": "Spiral Theme",
		"description": "Animated hypnotic spiral lane atmosphere.",
		"price": 480,
		"required_level": 10,
	},
	{
		"id": "effect_none",
		"type": "effect",
		"display_name": "No Effect",
		"description": "Default gameplay presentation.",
		"price": 0,
		"default_owned": true,
		"required_level": 1,
	},
	{
		"id": "effect_trail",
		"type": "effect",
		"display_name": "Trail Effect",
		"description": "Notes leave short-lived afterimages.",
		"price": 120,
		"required_level": 2,
	},
	{
		"id": "effect_pulse",
		"type": "effect",
		"display_name": "Pulse Effect",
		"description": "Notes pulse lightly with the beat.",
		"price": 150,
		"required_level": 3,
	},
	{
		"id": "effect_shake",
		"type": "effect",
		"display_name": "Screen Shake",
		"description": "Adds a small screen shake on successful hits.",
		"price": 180,
		"required_level": 4,
	},
	{
		"id": "effect_glow_boost",
		"type": "effect",
		"display_name": "Glow Boost",
		"description": "Increases note glow intensity.",
		"price": 220,
		"required_level": 5,
	},
	{
		"id": "effect_lane_bloom",
		"type": "effect",
		"display_name": "Lane Bloom",
		"description": "The struck lane blooms with a soft reactive flash.",
		"price": 240,
		"required_level": 5,
	},
	{
		"id": "effect_aftershock",
		"type": "effect",
		"display_name": "Aftershock",
		"description": "Adds a stronger burst and larger impact ring on clean hits.",
		"price": 280,
		"required_level": 7,
	},
	{
		"id": "effect_shimmer",
		"type": "effect",
		"display_name": "Runway Shimmer",
		"description": "Runways breathe with a subtle animated sheen.",
		"price": 260,
		"required_level": 6,
	},
	{
		"id": "effect_sidefire",
		"type": "effect",
		"display_name": "Sidefire",
		"description": "Desktop side panels flare brighter on successful hits.",
		"price": 300,
		"required_level": 8,
	},
	{
		"id": "speed_1_0",
		"type": "speed_modifier",
		"display_name": "1.0x Speed",
		"description": "Default note travel speed.",
		"value": 1.0,
		"price": 0,
		"default_owned": true,
		"required_level": 1,
	},
	{
		"id": "speed_1_2",
		"type": "speed_modifier",
		"display_name": "1.2x Speed",
		"description": "Faster travel speed for advanced play. Grants a 1.2x score multiplier.",
		"value": 1.2,
		"price": 140,
		"required_level": 3,
	},
	{
		"id": "speed_1_5",
		"type": "speed_modifier",
		"display_name": "1.5x Speed",
		"description": "Very fast travel speed challenge. Grants a 1.5x score multiplier.",
		"value": 1.5,
		"price": 220,
		"required_level": 6,
	},
	{
		"id": "speed_2_0",
		"type": "speed_modifier",
		"display_name": "2.0x Speed",
		"description": "Extreme travel speed challenge. Grants a 2.0x score multiplier.",
		"value": 2.0,
		"price": 360,
		"required_level": 9,
	},
	{
		"id": "modifier_accuracy_trainer",
		"type": "modifier",
		"display_name": "Accuracy Trainer",
		"description": "Shows early or late feedback on hits.",
		"price": 120,
		"required_level": 2,
	},
	{
		"id": "modifier_hidden_notes",
		"type": "modifier",
		"display_name": "Hidden Notes",
		"description": "Notes fade in only near the judgement line.",
		"price": 180,
		"required_level": 4,
	},
	{
		"id": "modifier_random_lane",
		"type": "modifier",
		"display_name": "Random Lane",
		"description": "Shuffles note lanes for a fresh pattern.",
		"price": 220,
		"required_level": 5,
	},
	{
		"id": "modifier_mirror",
		"type": "modifier",
		"display_name": "Mirror Mode",
		"description": "Flips lane assignments horizontally.",
		"price": 200,
		"required_level": 3,
	},
	{
		"id": "modifier_no_fail",
		"type": "modifier",
		"display_name": "No-Fail Mode",
		"description": "Practice mode that keeps the run going.",
		"price": 260,
		"required_level": 6,
	},
	{
		"id": "modifier_flashlight",
		"type": "modifier",
		"display_name": "Flashlight",
		"description": "Notes are brightest only near the judgement line.",
		"price": 240,
		"required_level": 6,
	},
	{
		"id": "modifier_lane_cover",
		"type": "modifier",
		"display_name": "Lane Cover",
		"description": "Covers the top of the highway for late-read practice.",
		"price": 260,
		"required_level": 7,
	},
	{
		"id": "modifier_precision",
		"type": "modifier",
		"display_name": "Precision Mode",
		"description": "Tightens judgement windows and grants a permanent 1.5x score multiplier.",
		"price": 320,
		"required_level": 9,
	},
	{
		"id": "modifier_black_hole",
		"type": "modifier",
		"display_name": "Black Hole",
		"description": "A subtle gravity well pulls notes inward without ruining readability.",
		"price": 340,
		"required_level": 7,
	},
]


static func get_all_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = ITEMS.duplicate(true)
	var registry := _ems_registry()
	if registry != null and registry.has_method("get_shop_items"):
		items.append_array(registry.call("get_shop_items") as Array)
	else:
		items.append_array(EMSLoadoutCatalog.get_content_available_shop_items())
	return items


static func get_default_owned_items() -> Array[String]:
	var owned: Array[String] = []
	for item in get_all_items():
		if bool(item.get("default_owned", false)):
			owned.append(str(item.get("id", "")))
	return owned


static func get_item(item_id: String) -> Dictionary:
	for item in get_all_items():
		if str(item.get("id", "")) == item_id:
			return item.duplicate(true)
	return {}


static func get_required_level(item_id: String) -> int:
	return int(get_item(item_id).get("required_level", 1))


static func is_unlocked_for_level(item_id: String, level: int) -> bool:
	return level >= get_required_level(item_id)


static func get_items_by_type(item_type: String) -> Array[Dictionary]:
	var filtered: Array[Dictionary] = []
	for item in get_all_items():
		if str(item.get("type", "")) == item_type:
			filtered.append(item.duplicate(true))
	return filtered


static func _ems_registry() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null("EMSRegistry")
