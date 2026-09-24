extends RefCounted
class_name EMSLoadoutCatalog

const DEFAULT_LOADOUT_ID := "ems_harmonic_core"
const ITEM_TYPE := "ems_loadout"
const ACQUISITION_INCLUDED := "included"
const ACQUISITION_SHOP_VARIANT := "shop_variant"
const PREVIEW_DIR := "res://assets/ems/previews"
const PROGRESSION_MANIFEST_PATH := "res://content/manifests/progression_manifest.json"
const SONGS_PER_AVAILABLE_SECTION := 4

const REQUIRED_CONFIG_KEYS := [
	"profile_driven",
	"motion_profile",
	"signature_effect",
	"classic_layer_mix",
	"palette_morph",
	"reaction_model",
	"style_multiplier",
	"layer_weights",
]


static func get_all_loadouts() -> Array[Dictionary]:
	return get_core_loadouts()


static func get_core_loadouts() -> Array[Dictionary]:
	return [
		_section_reward("ems_harmonic_core", "Harmonic Core", "Current EMS defaults and existing Options-driven behavior.", 1, _core_config()),
		_section_reward("ems_neon_rain", "Neon Rain", "Vertical cyan and magenta rain over a glossy dark stage.", 2, _preset_config("neon_rain", [Color(0.10, 0.92, 1.0, 1.0), Color(1.0, 0.12, 0.88, 1.0), Color(0.36, 0.28, 1.0, 1.0), Color(0.02, 0.98, 0.82, 1.0)], "psychedelic", Color(0.02, 0.015, 0.08, 1.0), 0.34, "max", "pressure", 1.08, {"gradient": 1.05, "depth": 0.80, "particles": 1.25, "fog": 0.70, "ribbon": 0.92, "glyph": 0.45, "ripple": 0.95, "distortion": 0.86, "gameplay_shader": 1.05, "pressure_wave": 1.05})),
		_section_reward("ems_digital_snow", "Digital Snow", "Cool pixel snow with soft blue-white particles.", 3, _preset_config("digital_snow", [Color(0.68, 0.95, 1.0, 1.0), Color(0.26, 0.52, 1.0, 1.0), Color(0.90, 0.96, 1.0, 1.0), Color(0.30, 0.80, 0.96, 1.0)], "solid", Color(0.015, 0.035, 0.075, 1.0), 0.42, "medium", "circular", 0.95, {"gradient": 0.88, "depth": 0.72, "particles": 1.18, "fog": 1.10, "ribbon": 0.35, "glyph": 0.82, "ripple": 0.78, "distortion": 0.35, "gameplay_shader": 0.58, "pressure_wave": 0.70})),
		_section_reward("ems_plasma_storm", "Plasma Storm", "Hot plasma ribbons and pressure-hit energy.", 4, _preset_config("plasma_storm", [Color(1.0, 0.28, 0.12, 1.0), Color(1.0, 0.82, 0.08, 1.0), Color(0.90, 0.04, 1.0, 1.0), Color(0.18, 0.94, 1.0, 1.0)], "psychedelic", Color(0.09, 0.018, 0.015, 1.0), 0.38, "max", "pressure", 1.18, {"gradient": 1.08, "depth": 0.95, "particles": 1.08, "fog": 0.48, "ribbon": 1.28, "glyph": 0.50, "ripple": 1.10, "distortion": 1.10, "gameplay_shader": 1.22, "pressure_wave": 1.25})),
		_section_reward("ems_quantum_grid", "Quantum Grid", "Wireframe grid depth with precise cyan and violet pulses.", 5, _preset_config("quantum_grid", [Color(0.08, 0.95, 1.0, 1.0), Color(0.50, 0.18, 1.0, 1.0), Color(0.90, 0.96, 1.0, 1.0), Color(0.0, 0.45, 1.0, 1.0)], "solid", Color(0.018, 0.020, 0.070, 1.0), 0.36, "medium", "pressure", 1.00, {"gradient": 0.78, "depth": 1.26, "particles": 0.72, "fog": 0.34, "ribbon": 0.65, "glyph": 1.20, "ripple": 0.96, "distortion": 0.54, "gameplay_shader": 0.92, "pressure_wave": 0.92})),
		_section_reward("ems_aurora_drive", "Aurora Drive", "Smooth aurora gradients with elegant low-noise motion.", 6, _preset_config("aurora_drive", [Color(0.18, 1.0, 0.72, 1.0), Color(0.18, 0.62, 1.0, 1.0), Color(0.78, 0.35, 1.0, 1.0), Color(0.80, 1.0, 0.86, 1.0)], "psychedelic", Color(0.015, 0.055, 0.075, 1.0), 0.34, "medium", "circular", 0.92, {"gradient": 1.25, "depth": 0.75, "particles": 0.66, "fog": 1.05, "ribbon": 1.05, "glyph": 0.45, "ripple": 0.70, "distortion": 0.42, "gameplay_shader": 0.58, "pressure_wave": 0.65})),
		_section_reward("ems_cyber_ocean", "Cyber Ocean", "Deep teal waves, bubbles, and glassy blue depth.", 7, _preset_config("cyber_ocean", [Color(0.02, 0.88, 0.92, 1.0), Color(0.00, 0.32, 0.75, 1.0), Color(0.12, 1.0, 0.60, 1.0), Color(0.66, 0.90, 1.0, 1.0)], "solid", Color(0.00, 0.030, 0.070, 1.0), 0.44, "medium", "circular", 0.98, {"gradient": 1.00, "depth": 1.18, "particles": 0.95, "fog": 1.08, "ribbon": 0.92, "glyph": 0.48, "ripple": 1.12, "distortion": 0.58, "gameplay_shader": 0.70, "pressure_wave": 0.78})),
		_section_reward("ems_fractal_space", "Fractal Space", "Geometric glyphs, starfield particles, and a cosmic palette.", 8, _preset_config("fractal_space", [Color(0.62, 0.26, 1.0, 1.0), Color(0.08, 0.86, 1.0, 1.0), Color(1.0, 0.28, 0.80, 1.0), Color(0.92, 0.92, 1.0, 1.0)], "random", Color(0.025, 0.014, 0.060, 1.0), 0.40, "max", "circular", 1.10, {"gradient": 0.92, "depth": 1.00, "particles": 1.16, "fog": 0.65, "ribbon": 0.72, "glyph": 1.30, "ripple": 0.90, "distortion": 0.88, "gameplay_shader": 0.92, "pressure_wave": 0.88})),
		_section_reward("ems_prism_circuit", "Prism Circuit", "Refracted prism colors and circuit-like traces.", 9, _preset_config("prism_circuit", [Color(1.0, 0.10, 0.22, 1.0), Color(0.10, 0.90, 1.0, 1.0), Color(0.20, 1.0, 0.35, 1.0), Color(1.0, 0.86, 0.10, 1.0), Color(0.72, 0.18, 1.0, 1.0)], "psychedelic", Color(0.025, 0.025, 0.075, 1.0), 0.35, "max", "pressure", 1.06, {"gradient": 1.02, "depth": 1.10, "particles": 0.82, "fog": 0.38, "ribbon": 0.82, "glyph": 1.20, "ripple": 0.92, "distortion": 0.78, "gameplay_shader": 0.98, "pressure_wave": 0.96})),
		_section_reward("ems_void_pulse", "Void Pulse", "Black and purple void energy with restrained pulse rings.", 10, _preset_config("void_pulse", [Color(0.42, 0.12, 0.92, 1.0), Color(0.95, 0.10, 0.70, 1.0), Color(0.10, 0.70, 1.0, 1.0), Color(0.72, 0.72, 0.92, 1.0)], "solid", Color(0.006, 0.005, 0.020, 1.0), 0.48, "medium", "circular", 0.90, {"gradient": 0.82, "depth": 1.12, "particles": 0.62, "fog": 0.62, "ribbon": 0.54, "glyph": 0.75, "ripple": 1.22, "distortion": 0.70, "gameplay_shader": 0.72, "pressure_wave": 1.10})),
		_section_reward("ems_solar_bloom", "Solar Bloom", "Gold and orange bloom with warm particle sparks.", 11, _preset_config("solar_bloom", [Color(1.0, 0.72, 0.08, 1.0), Color(1.0, 0.26, 0.08, 1.0), Color(1.0, 0.95, 0.58, 1.0), Color(0.92, 0.10, 0.32, 1.0)], "psychedelic", Color(0.090, 0.040, 0.005, 1.0), 0.36, "max", "pressure", 1.12, {"gradient": 1.12, "depth": 0.82, "particles": 1.24, "fog": 0.54, "ribbon": 1.00, "glyph": 0.48, "ripple": 1.05, "distortion": 0.76, "gameplay_shader": 1.18, "pressure_wave": 1.08})),
		_section_reward("ems_lunar_glass", "Lunar Glass", "Silver-blue glass shards with subtle shimmer.", 12, _preset_config("lunar_glass", [Color(0.72, 0.90, 1.0, 1.0), Color(0.38, 0.58, 1.0, 1.0), Color(0.92, 0.96, 1.0, 1.0), Color(0.54, 1.0, 0.92, 1.0)], "solid", Color(0.020, 0.025, 0.055, 1.0), 0.42, "subtle", "circular", 0.82, {"gradient": 0.78, "depth": 1.10, "particles": 0.82, "fog": 0.74, "ribbon": 0.48, "glyph": 1.05, "ripple": 0.72, "distortion": 0.34, "gameplay_shader": 0.48, "pressure_wave": 0.62})),
		_section_reward("ems_pixel_nebula", "Pixel Nebula", "Retro pixel motes over nebula gradients.", 13, _preset_config("pixel_nebula", [Color(0.98, 0.16, 0.90, 1.0), Color(0.18, 0.80, 1.0, 1.0), Color(0.92, 0.42, 1.0, 1.0), Color(1.0, 0.84, 0.16, 1.0)], "random", Color(0.045, 0.014, 0.060, 1.0), 0.40, "max", "circular", 1.05, {"gradient": 1.05, "depth": 0.78, "particles": 1.30, "fog": 0.66, "ribbon": 0.42, "glyph": 1.08, "ripple": 0.82, "distortion": 0.76, "gameplay_shader": 0.78, "pressure_wave": 0.74})),
		_section_reward("ems_thunder_matrix", "Thunder Matrix", "Electric streaks, grid flashes, and sharp impact ripples.", 14, _preset_config("thunder_matrix", [Color(0.12, 0.92, 1.0, 1.0), Color(0.58, 0.22, 1.0, 1.0), Color(1.0, 1.0, 0.28, 1.0), Color(0.95, 0.95, 1.0, 1.0)], "psychedelic", Color(0.012, 0.014, 0.050, 1.0), 0.38, "max", "pressure", 1.16, {"gradient": 0.95, "depth": 1.18, "particles": 0.92, "fog": 0.34, "ribbon": 1.16, "glyph": 1.16, "ripple": 1.24, "distortion": 0.95, "gameplay_shader": 1.18, "pressure_wave": 1.22})),
		_section_reward("ems_chromatic_rift", "Chromatic Rift", "Split-color ribbons with capped distortion.", 15, _preset_config("chromatic_rift", [Color(1.0, 0.08, 0.20, 1.0), Color(0.05, 0.95, 1.0, 1.0), Color(0.18, 1.0, 0.28, 1.0), Color(0.70, 0.18, 1.0, 1.0)], "psychedelic", Color(0.030, 0.008, 0.050, 1.0), 0.36, "max", "pressure", 1.10, {"gradient": 1.00, "depth": 0.92, "particles": 0.76, "fog": 0.30, "ribbon": 1.30, "glyph": 0.74, "ripple": 0.98, "distortion": 1.18, "gameplay_shader": 1.04, "pressure_wave": 0.98})),
		_section_reward("ems_skyline_mirage", "Skyline Mirage", "Horizon light bars and slow parallax silhouettes.", 16, _preset_config("skyline_mirage", [Color(0.12, 0.70, 1.0, 1.0), Color(1.0, 0.28, 0.72, 1.0), Color(1.0, 0.72, 0.18, 1.0), Color(0.30, 0.18, 0.86, 1.0)], "solid", Color(0.015, 0.020, 0.050, 1.0), 0.45, "medium", "circular", 0.92, {"gradient": 1.05, "depth": 1.28, "particles": 0.55, "fog": 0.50, "ribbon": 0.74, "glyph": 0.46, "ripple": 0.64, "distortion": 0.38, "gameplay_shader": 0.56, "pressure_wave": 0.58})),
		_section_reward("ems_crystal_reactor", "Crystal Reactor", "Emerald and cyan crystal fragments with reactor glow.", 17, _preset_config("crystal_reactor", [Color(0.10, 1.0, 0.62, 1.0), Color(0.10, 0.84, 1.0, 1.0), Color(0.76, 1.0, 0.22, 1.0), Color(0.88, 0.98, 1.0, 1.0)], "psychedelic", Color(0.010, 0.055, 0.040, 1.0), 0.36, "max", "pressure", 1.08, {"gradient": 1.02, "depth": 1.10, "particles": 1.08, "fog": 0.60, "ribbon": 0.82, "glyph": 1.24, "ripple": 1.06, "distortion": 0.76, "gameplay_shader": 1.12, "pressure_wave": 1.08})),
		_section_reward("ems_gravity_well", "Gravity Well", "Orbital particles with inward depth motion.", 18, _preset_config("gravity_well", [Color(0.45, 0.20, 1.0, 1.0), Color(0.04, 0.78, 1.0, 1.0), Color(0.95, 0.22, 0.82, 1.0), Color(0.18, 0.10, 0.42, 1.0)], "solid", Color(0.006, 0.004, 0.018, 1.0), 0.50, "medium", "circular", 0.96, {"gradient": 0.72, "depth": 1.30, "particles": 1.10, "fog": 0.72, "ribbon": 0.58, "glyph": 0.86, "ripple": 1.16, "distortion": 0.92, "gameplay_shader": 0.76, "pressure_wave": 1.12})),
		_section_reward("ems_hypernova_flow", "Hypernova Flow", "High-energy star flow with mobile and FPS caps.", 19, _preset_config("hypernova_flow", [Color(0.08, 0.92, 1.0, 1.0), Color(1.0, 0.16, 0.52, 1.0), Color(1.0, 0.88, 0.12, 1.0), Color(0.42, 0.20, 1.0, 1.0), Color(0.20, 1.0, 0.55, 1.0)], "psychedelic", Color(0.030, 0.012, 0.050, 1.0), 0.34, "max", "pressure", 1.20, {"gradient": 1.16, "depth": 1.06, "particles": 1.28, "fog": 0.42, "ribbon": 1.18, "glyph": 0.88, "ripple": 1.10, "distortion": 1.00, "gameplay_shader": 1.24, "pressure_wave": 1.18})),
		_section_reward("ems_singularity_bloom", "Singularity Bloom", "Final cosmic bloom with pressure waves and controlled distortion.", 20, _preset_config("singularity_bloom", [Color(0.78, 0.22, 1.0, 1.0), Color(0.10, 0.92, 1.0, 1.0), Color(1.0, 0.96, 0.32, 1.0), Color(1.0, 0.20, 0.72, 1.0), Color(0.28, 1.0, 0.70, 1.0)], "psychedelic", Color(0.012, 0.006, 0.030, 1.0), 0.36, "max", "pressure", 1.22, {"gradient": 1.18, "depth": 1.18, "particles": 1.18, "fog": 0.48, "ribbon": 1.20, "glyph": 1.12, "ripple": 1.28, "distortion": 1.05, "gameplay_shader": 1.28, "pressure_wave": 1.30})),
	]


static func get_shop_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	for loadout in get_all_loadouts():
		items.append(_shop_item_from_loadout(loadout))
	return items


static func get_content_available_section_count(sections_override: Array = []) -> int:
	var sections: Array = sections_override
	if sections.is_empty():
		sections = _content_registry_sections()
	var expected_section_id := 1
	var available_count := 0
	for section_variant in sections:
		if section_variant is not Dictionary:
			break
		var section := section_variant as Dictionary
		var section_id := int(section.get("id", expected_section_id))
		if section_id != expected_section_id:
			break
		var songs: Array = section.get("songs", []) as Array
		if songs.size() < SONGS_PER_AVAILABLE_SECTION:
			break
		available_count = section_id
		expected_section_id += 1
	return maxi(1, available_count)


static func is_loadout_content_available(loadout: Dictionary, available_section_count: int = -1) -> bool:
	# Built-in EMS Loadouts are included equipment. Section availability no longer
	# limits whether a player can browse or equip them.
	var _unused_section_count := available_section_count
	if loadout.is_empty():
		return false
	return true


static func is_loadout_id_content_available(loadout_id: String, available_section_count: int = -1) -> bool:
	var loadout := get_loadout(loadout_id)
	return is_loadout_content_available(loadout, available_section_count)


static func get_content_available_core_loadouts(available_section_count: int = -1) -> Array[Dictionary]:
	var _unused_section_count := available_section_count
	var out: Array[Dictionary] = []
	for loadout in get_core_loadouts():
		out.append(loadout.duplicate(true))
	return out


static func get_content_available_shop_items(available_section_count: int = -1) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	for loadout in get_content_available_core_loadouts(available_section_count):
		items.append(_shop_item_from_loadout(loadout))
	return items


static func signature_layer_type_to_loadout_id(layer_type: String) -> String:
	var type_name := layer_type.strip_edges()
	if not type_name.begins_with("signature_"):
		return ""
	return "ems_%s" % type_name.trim_prefix("signature_")


static func is_layer_type_content_available(layer_type: String, available_section_count: int = -1) -> bool:
	var loadout_id := signature_layer_type_to_loadout_id(layer_type)
	if loadout_id.is_empty():
		return true
	var loadout := get_loadout(loadout_id)
	if loadout.is_empty():
		return true
	return is_loadout_content_available(loadout, available_section_count)


static func _content_registry_sections() -> Array:
	var main_loop := Engine.get_main_loop()
	if main_loop is not SceneTree:
		return _progression_manifest_sections()
	var registry := (main_loop as SceneTree).root.get_node_or_null("ContentRegistry")
	if registry == null or not registry.has_method("get_progression_sections"):
		return _progression_manifest_sections()
	var sections := registry.call("get_progression_sections") as Array
	return sections if not sections.is_empty() else _progression_manifest_sections()


static func _progression_manifest_sections() -> Array:
	if not FileAccess.file_exists(PROGRESSION_MANIFEST_PATH):
		return []
	var file := FileAccess.open(PROGRESSION_MANIFEST_PATH, FileAccess.READ)
	if file == null:
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is not Dictionary:
		return []
	var out: Array = []
	for section_variant in (parsed as Dictionary).get("sections", []):
		if section_variant is Dictionary:
			out.append((section_variant as Dictionary).duplicate(true))
	return out


static func get_loadout(loadout_id: String) -> Dictionary:
	for loadout in get_all_loadouts():
		if str(loadout.get("id", "")) == loadout_id:
			return loadout.duplicate(true)
	return {}


static func get_default_loadout_id() -> String:
	return DEFAULT_LOADOUT_ID


static func is_valid_loadout(loadout_id: String) -> bool:
	return not get_loadout(loadout_id).is_empty()


static func get_display_name(loadout_id: String) -> String:
	var loadout := get_loadout(loadout_id)
	if loadout.is_empty():
		return get_loadout(DEFAULT_LOADOUT_ID).get("display_name", "Harmonic Core")
	return str(loadout.get("display_name", "Harmonic Core"))


static func get_preview_path(loadout_id: String) -> String:
	return "%s/%s.png" % [PREVIEW_DIR, loadout_id]


static func get_config(loadout_id: String) -> Dictionary:
	var loadout := get_loadout(loadout_id)
	if loadout.is_empty():
		loadout = get_loadout(DEFAULT_LOADOUT_ID)
	return (loadout.get("config", {}) as Dictionary).duplicate(true)


static func _section_reward(id: String, display_name: String, description: String, catalog_order: int, config: Dictionary) -> Dictionary:
	return {
		"id": id,
		"type": ITEM_TYPE,
		"display_name": display_name,
		"description": description,
		"catalog_order": catalog_order,
		"progression_section_id": catalog_order,
		"acquisition": ACQUISITION_INCLUDED,
		"price": 0,
		"required_level": 1,
		"default_owned": true,
		"preview_path": get_preview_path(id),
		"config": config,
	}


static func _shop_item_from_loadout(loadout: Dictionary) -> Dictionary:
	var item := loadout.duplicate(true)
	item.erase("config")
	return item


static func _core_config() -> Dictionary:
	return {
		"profile_driven": true,
		"motion_profile": "harmonic_core",
		"signature_effect": "classic",
		"classic_layer_mix": _core_classic_layer_mix(),
		"palette_morph": "profile",
		"reaction_model": "classic",
		"style_multiplier": 1.0,
		"layer_weights": _layer_weights({}),
	}


static func _preset_config(
	motion_profile: String,
	palette: Array,
	background_mode: String,
	background_solid_color: Color,
	background_brightness: float,
	trippy_level: String,
	hit_effect: String,
	style_multiplier: float,
	layer_weights: Dictionary
) -> Dictionary:
	var signature := _signature_details(motion_profile)
	return {
		"profile_driven": false,
		"motion_profile": motion_profile,
		"signature_effect": str(signature.get("signature_effect", motion_profile)),
		"classic_layer_mix": _classic_layer_mix(signature.get("classic_layer_mix", {}) as Dictionary),
		"palette_morph": str(signature.get("palette_morph", "spectral_flow")),
		"reaction_model": str(signature.get("reaction_model", "combo_surge")),
		"palette": palette,
		"background_mode": background_mode,
		"background_solid_color": background_solid_color,
		"background_brightness": background_brightness,
		"trippy_level": trippy_level,
		"hit_effect": hit_effect,
		"style_multiplier": style_multiplier,
		"layer_weights": _layer_weights(layer_weights),
	}


static func _signature_details(motion_profile: String) -> Dictionary:
	match motion_profile:
		"neon_rain":
			return {"palette_morph": "drip_shift", "reaction_model": "rain_splash"}
		"digital_snow":
			return {"palette_morph": "pixel_quantize", "reaction_model": "snow_scatter"}
		"plasma_storm":
			return {"palette_morph": "heat_branch", "reaction_model": "plasma_strike"}
		"quantum_grid":
			return {"palette_morph": "grid_phase", "reaction_model": "node_collapse"}
		"aurora_drive":
			return {"palette_morph": "aurora_silk", "reaction_model": "curtain_breathe"}
		"cyber_ocean":
			return {"palette_morph": "caustic_wave", "reaction_model": "sonar_burst"}
		"fractal_space":
			return {"palette_morph": "kaleidoscope", "reaction_model": "fractal_spin"}
		"prism_circuit":
			return {"palette_morph": "prism_split", "reaction_model": "trace_pulse"}
		"void_pulse":
			return {"palette_morph": "void_invert", "reaction_model": "gravity_ring"}
		"solar_bloom":
			return {"palette_morph": "solar_corona", "reaction_model": "flare_burst"}
		"lunar_glass":
			return {"palette_morph": "moon_shimmer", "reaction_model": "glass_chime"}
		"pixel_nebula":
			return {"palette_morph": "nebula_quantize", "reaction_model": "pixel_pop"}
		"thunder_matrix":
			return {"palette_morph": "electric_strobe", "reaction_model": "bolt_chain"}
		"chromatic_rift":
			return {"palette_morph": "rift_split", "reaction_model": "tear_pull"}
		"skyline_mirage":
			return {"palette_morph": "horizon_heat", "reaction_model": "mirage_shift"}
		"crystal_reactor":
			return {"palette_morph": "reactor_charge", "reaction_model": "crystal_charge"}
		"gravity_well":
			return {"palette_morph": "orbital_lens", "reaction_model": "inward_pull"}
		"hypernova_flow":
			return {"palette_morph": "star_velocity", "reaction_model": "hyper_stream"}
		"singularity_bloom":
			return {"palette_morph": "singularity_bloom", "reaction_model": "event_horizon"}
		_:
			return {"palette_morph": "spectral_flow", "reaction_model": "combo_surge"}


static func _core_classic_layer_mix() -> Dictionary:
	return _classic_layer_mix({
		"gradient": true,
		"depth": true,
		"particles": true,
		"fog": true,
		"ribbon": true,
		"glyph": true,
		"ripple": true,
		"pulse": true,
	})


static func _classic_layer_mix(overrides: Dictionary) -> Dictionary:
	var mix := {
		"gradient": false,
		"depth": false,
		"particles": false,
		"fog": false,
		"ribbon": false,
		"glyph": false,
		"ripple": false,
		"pulse": false,
	}
	for key_variant in overrides.keys():
		var key := str(key_variant)
		if mix.has(key):
			mix[key] = bool(overrides[key_variant])
	return mix


static func _layer_weights(overrides: Dictionary) -> Dictionary:
	var weights := {
		"gradient": 1.0,
		"depth": 1.0,
		"particles": 1.0,
		"fog": 1.0,
		"ribbon": 1.0,
		"glyph": 1.0,
		"ripple": 1.0,
		"distortion": 1.0,
		"gameplay_shader": 1.0,
		"pressure_wave": 1.0,
	}
	for key_variant in overrides.keys():
		var key := str(key_variant)
		if weights.has(key):
			weights[key] = clampf(float(overrides[key_variant]), 0.0, 1.35)
	return weights
