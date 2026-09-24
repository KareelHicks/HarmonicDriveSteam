extends Node

const GameModeConfig = preload("res://scripts/gameplay/GameModeConfig.gd")
const LaneCountResolver = preload("res://scripts/songs/LaneCountResolver.gd")
signal profile_changed

const SAVE_PATH := "user://profile.cfg"
const DEFAULT_NOTE_SPEED_TYPE := "classic"
const DEFAULT_NOTE_APPROACH_TIME_MS := 600.0
const DEFAULT_LANE_WIDTH_SCALE := 0.4
const DEFAULT_DISPLAY_RESOLUTION := "1920x1080"
const FPS_LIMIT_OPTIONS := [30, 60, 120, 144, 240, 0]
const DISPLAY_RESOLUTION_OPTIONS := ["1280x720", "1600x900", "1920x1080", "2560x1440", "3840x2160"]
const HIT_EFFECTS_MODES := ["off", "minimal", "normal", "enhanced"]
const JUDGEMENT_DISPLAY_MODES := ["classic", "modern"]
const IN_GAME_UI_MODES := ["classic", "modern"]
const NOTE_SPEED_TYPES := ["classic", "modern"]
const KEYBOARD_LAYOUT_MIN_LANES := 4
const KEYBOARD_LAYOUT_MAX_LANES := 8
const KEYBOARD_LAYOUT_LANE_COUNTS := [4, 5, 6, 7, 8]
const DEFAULT_KEY_BINDINGS_BY_LANE_COUNT := {
	"4": {
		"lane_0": KEY_A,
		"lane_1": KEY_S,
		"lane_2": KEY_J,
		"lane_3": KEY_K,
	},
	"5": {
		"lane_0": KEY_A,
		"lane_1": KEY_S,
		"lane_2": KEY_D,
		"lane_3": KEY_J,
		"lane_4": KEY_K,
	},
	"6": {
		"lane_0": KEY_A,
		"lane_1": KEY_S,
		"lane_2": KEY_D,
		"lane_3": KEY_J,
		"lane_4": KEY_K,
		"lane_5": KEY_L,
	},
	"7": {
		"lane_0": KEY_A,
		"lane_1": KEY_S,
		"lane_2": KEY_D,
		"lane_3": KEY_SPACE,
		"lane_4": KEY_J,
		"lane_5": KEY_K,
		"lane_6": KEY_L,
	},
	"8": {
		"lane_0": KEY_A,
		"lane_1": KEY_S,
		"lane_2": KEY_D,
		"lane_3": KEY_F,
		"lane_4": KEY_J,
		"lane_5": KEY_K,
		"lane_6": KEY_L,
		"lane_7": KEY_SEMICOLON,
	},
}
const DEFAULT_BINDINGS := {
	"lane_0": KEY_A,
	"lane_1": KEY_S,
	"lane_2": KEY_D,
	"lane_3": KEY_J,
	"lane_4": KEY_K,
}
const LEGACY_SHARED_KEY_BINDINGS := {
	"lane_0": KEY_A,
	"lane_1": KEY_S,
	"lane_2": KEY_D,
	"lane_3": KEY_F,
	"lane_4": KEY_J,
	"lane_5": KEY_K,
	"lane_6": KEY_L,
	"lane_7": KEY_SEMICOLON,
}
const LEGACY_EXTRA_LANE_BINDINGS := {
	"lane_5": KEY_L,
	"lane_6": KEY_SEMICOLON,
	"lane_7": KEY_APOSTROPHE,
}
const DEFAULT_CONTROLLER_BINDINGS := {
	"lane_0": {"kind": "button", "button_index": JOY_BUTTON_LEFT_SHOULDER},
	"lane_1": {"kind": "axis", "axis": JOY_AXIS_TRIGGER_LEFT, "direction": 1, "threshold": 0.5},
	"lane_2": {"kind": "button", "button_index": JOY_BUTTON_A},
	"lane_3": {"kind": "axis", "axis": JOY_AXIS_TRIGGER_RIGHT, "direction": 1, "threshold": 0.5},
	"lane_4": {"kind": "button", "button_index": JOY_BUTTON_RIGHT_SHOULDER},
	"ui_up": {"kind": "button", "button_index": JOY_BUTTON_DPAD_UP},
	"ui_down": {"kind": "button", "button_index": JOY_BUTTON_DPAD_DOWN},
	"ui_left": {"kind": "button", "button_index": JOY_BUTTON_DPAD_LEFT},
	"ui_right": {"kind": "button", "button_index": JOY_BUTTON_DPAD_RIGHT},
	"ui_accept": {"kind": "button", "button_index": JOY_BUTTON_A},
	"ui_cancel": {"kind": "button", "button_index": JOY_BUTTON_B},
}
const DEFAULT_GAMEPLAY_STATS := {
	"notes_hit": 0,
	"notes_missed": 0,
	"song_completions": 0,
	"song_failures": 0,
	"full_combos": 0,
	"all_perfects": 0,
}

var _profile := {
	"profile_revision": 0,
	"profile_last_saved_unix": 0,
	"latency_offset_ms": 0.0,
	"note_speed_type": DEFAULT_NOTE_SPEED_TYPE,
	"note_approach_time_ms": DEFAULT_NOTE_APPROACH_TIME_MS,
	"lane_width_scale": DEFAULT_LANE_WIDTH_SCALE,
	"miss_audio_ducking_enabled": true,
	"menu_music_volume": 1.0,
	"gameplay_music_volume": 1.0,
	"theme_effects_enabled": true,
	"chart_background_disabled": false,
	"ems_color_mode": "random", # "random" | "custom"
	"ems_custom_primary": Color(0.20, 0.78, 0.95, 1.0),
	"ems_custom_secondary": Color(0.85, 0.40, 0.95, 1.0),
	"ems_custom_accent": Color(0.55, 0.92, 0.70, 1.0),
	"ems_trippy_level": "max", # "subtle" | "medium" | "max"
	"ems_background_mode": "psychedelic", # "solid" | "random" | "psychedelic"
	"ems_background_solid_color": Color(0.04, 0.06, 0.12, 1.0),
	"ems_background_brightness": 0.40, # multiplier applied to EMS gutter background color
	"ems_gutter_image_mode": "off", # "off" | "both" | "separate"
	"ems_gutter_image_path_both": "",
	"ems_gutter_image_path_left": "",
	"ems_gutter_image_path_right": "",
	"ems_gutter_image_alpha": 0.22,
	"ems_hit_effect": "pressure",
	"shaders_enabled": true,
	"visual_effect_bloom_enabled": true,
	"visual_effect_distortion_enabled": true,
	"visual_effect_particles_enabled": true,
	"visual_effect_background_animations_enabled": true,
	"prioritize_fps_enabled": false,
	"fps_limit": 0,
	"vsync_mode": "on",
	"display_resolution": DEFAULT_DISPLAY_RESOLUTION,
	"lane_brightness": 1.0,
	"note_opacity": 1.0,
	"notes_above_judgement_buttons": false,
	"hit_effects_mode": "enhanced",
	"judgement_display_mode": "modern",
	"in_game_ui_mode": "modern",
	"judgement_popups_enabled": true,
	"reduce_drive_meter_critical_fx": false,
	"drive_meter_theme": "auto",
	"window_mode": "",
	"selected_song_id": "",
	"visualizer_selected_song_id": "",
	"selected_difficulty": "Medium",
	"selected_mode": GameModeConfig.DEFAULT_MODE,
	"guest_uuid": "",
	"purchased_premium_product_ids": [],
	"steam_unique_completed_song_ids": [],
	"steam_cumulative_playtime_seconds": 0.0,
	"steam_best_leaderboard_ranks": {},
	"steam_unlocked_achievement_ids": [],
	"steam_completed_multiplayer_match_ids": [],
	"steam_won_multiplayer_match_ids": [],
	"key_bindings": DEFAULT_BINDINGS.duplicate(true),
	"key_bindings_by_lane_count": DEFAULT_KEY_BINDINGS_BY_LANE_COUNT.duplicate(true),
	"controller_bindings": DEFAULT_CONTROLLER_BINDINGS.duplicate(true),
	"high_scores": {},
	"last_result": {},
	"gameplay_stats": DEFAULT_GAMEPLAY_STATS.duplicate(true),
	"progression": {},
}


func _ready() -> void:
	load_profile()


func load_profile() -> void:
	var config := ConfigFile.new()
	var result := config.load(SAVE_PATH)
	if result != OK:
		save_profile()
		return

	for key in _profile.keys():
		if config.has_section_key("profile", key):
			_profile[key] = config.get_value("profile", key)

	if not (_profile.get("key_bindings", {}) is Dictionary):
		_profile["key_bindings"] = DEFAULT_BINDINGS.duplicate(true)
	if not (_profile.get("key_bindings_by_lane_count", {}) is Dictionary):
		_profile["key_bindings_by_lane_count"] = {}
	if not (_profile.get("controller_bindings", {}) is Dictionary):
		_profile["controller_bindings"] = DEFAULT_CONTROLLER_BINDINGS.duplicate(true)

	_profile["key_bindings_by_lane_count"] = _normalize_key_bindings_by_lane_count(
		_profile.get("key_bindings_by_lane_count", {}),
		_profile.get("key_bindings", {})
	)
	_profile["key_bindings"] = get_key_bindings(LaneCountResolver.DEFAULT_LANES)
	for action in DEFAULT_CONTROLLER_BINDINGS.keys():
		if not _profile["controller_bindings"].has(action):
			_profile["controller_bindings"][action] = DEFAULT_CONTROLLER_BINDINGS[action]
	_profile["controller_bindings"] = _normalize_controller_bindings(_profile.get("controller_bindings", {}))
	_profile["gameplay_stats"] = _normalize_gameplay_stats(_profile.get("gameplay_stats", {}))

	if int(_profile.get("profile_revision", 0)) < 0:
		_profile["profile_revision"] = 0
	if int(_profile.get("profile_last_saved_unix", 0)) < 0:
		_profile["profile_last_saved_unix"] = 0

	if str(_profile.get("guest_uuid", "")).is_empty():
		_profile["guest_uuid"] = _generate_guest_uuid()
		save_profile()
		return

	emit_signal("profile_changed")


func save_profile() -> void:
	_profile["profile_revision"] = int(_profile.get("profile_revision", 0)) + 1
	_profile["profile_last_saved_unix"] = int(Time.get_unix_time_from_system())
	var config := ConfigFile.new()
	for key in _profile.keys():
		config.set_value("profile", key, _profile[key])
	config.save(SAVE_PATH)
	emit_signal("profile_changed")


func reload_profile_from_disk() -> void:
	load_profile()


func reset_settings_to_recommended_defaults() -> void:
	for key in _recommended_settings_defaults().keys():
		_profile[key] = _duplicate_profile_value(_recommended_settings_defaults()[key])
	_profile["key_bindings"] = DEFAULT_BINDINGS.duplicate(true)
	_profile["key_bindings_by_lane_count"] = DEFAULT_KEY_BINDINGS_BY_LANE_COUNT.duplicate(true)
	_profile["controller_bindings"] = DEFAULT_CONTROLLER_BINDINGS.duplicate(true)
	save_profile()


func _recommended_settings_defaults() -> Dictionary:
	return {
		"latency_offset_ms": 0.0,
		"note_speed_type": DEFAULT_NOTE_SPEED_TYPE,
		"note_approach_time_ms": DEFAULT_NOTE_APPROACH_TIME_MS,
		"lane_width_scale": DEFAULT_LANE_WIDTH_SCALE,
		"miss_audio_ducking_enabled": true,
		"menu_music_volume": 1.0,
		"gameplay_music_volume": 1.0,
		"theme_effects_enabled": true,
		"chart_background_disabled": false,
		"ems_color_mode": "random",
		"ems_custom_primary": Color(0.20, 0.78, 0.95, 1.0),
		"ems_custom_secondary": Color(0.85, 0.40, 0.95, 1.0),
		"ems_custom_accent": Color(0.55, 0.92, 0.70, 1.0),
		"ems_trippy_level": "max",
		"ems_background_mode": "psychedelic",
		"ems_background_solid_color": Color(0.04, 0.06, 0.12, 1.0),
		"ems_background_brightness": 0.40,
		"ems_gutter_image_mode": "off",
		"ems_gutter_image_path_both": "",
		"ems_gutter_image_path_left": "",
		"ems_gutter_image_path_right": "",
		"ems_gutter_image_alpha": 0.22,
		"ems_hit_effect": "pressure",
		"shaders_enabled": true,
		"visual_effect_bloom_enabled": true,
		"visual_effect_distortion_enabled": true,
		"visual_effect_particles_enabled": true,
		"visual_effect_background_animations_enabled": true,
		"prioritize_fps_enabled": false,
		"fps_limit": 0,
		"vsync_mode": "on",
		"display_resolution": DEFAULT_DISPLAY_RESOLUTION,
		"lane_brightness": 1.0,
		"note_opacity": 1.0,
		"notes_above_judgement_buttons": false,
		"hit_effects_mode": "enhanced",
		"judgement_display_mode": "modern",
		"in_game_ui_mode": "modern",
		"judgement_popups_enabled": true,
		"reduce_drive_meter_critical_fx": false,
		"drive_meter_theme": "auto",
		"window_mode": "",
	}


func _duplicate_profile_value(value: Variant) -> Variant:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	if value is Array:
		return (value as Array).duplicate(true)
	return value


func _normalize_gameplay_stats(value: Variant) -> Dictionary:
	var normalized := DEFAULT_GAMEPLAY_STATS.duplicate(true)
	if value is Dictionary:
		var source := value as Dictionary
		for key in normalized.keys():
			normalized[key] = maxi(0, int(source.get(key, normalized[key])))
	return normalized


func _notes_hit_from_result(result: Dictionary) -> int:
	return int(result.get("perfect", 0)) \
		+ int(result.get("great", 0)) \
		+ int(result.get("good", 0)) \
		+ int(result.get("hold_successes", 0))


func get_profile_revision() -> int:
	return int(_profile.get("profile_revision", 0))


func get_profile_last_saved_unix() -> int:
	return int(_profile.get("profile_last_saved_unix", 0))


func get_save_path() -> String:
	return SAVE_PATH


func get_latency_offset_ms() -> float:
	return float(_profile.get("latency_offset_ms", 0.0))


func set_latency_offset_ms(value: float) -> void:
	_profile["latency_offset_ms"] = clampf(value, -250.0, 250.0)
	save_profile()


func get_note_speed_type() -> String:
	var value := str(_profile.get("note_speed_type", DEFAULT_NOTE_SPEED_TYPE)).strip_edges().to_lower()
	return value if NOTE_SPEED_TYPES.has(value) else DEFAULT_NOTE_SPEED_TYPE


func set_note_speed_type(value: String) -> void:
	var normalized := value.strip_edges().to_lower()
	_profile["note_speed_type"] = normalized if NOTE_SPEED_TYPES.has(normalized) else DEFAULT_NOTE_SPEED_TYPE
	save_profile()


func get_note_approach_time_ms() -> float:
	return float(_profile.get("note_approach_time_ms", DEFAULT_NOTE_APPROACH_TIME_MS))


func set_note_approach_time_ms(value: float) -> void:
	_profile["note_approach_time_ms"] = clampf(value, 250.0, 2000.0)
	save_profile()


func get_lane_width_scale() -> float:
	return float(_profile.get("lane_width_scale", DEFAULT_LANE_WIDTH_SCALE))


func set_lane_width_scale(value: float) -> void:
	_profile["lane_width_scale"] = clampf(value, 0.25, 1.75)
	save_profile()


func is_miss_audio_ducking_enabled() -> bool:
	return bool(_profile.get("miss_audio_ducking_enabled", true))


func set_miss_audio_ducking_enabled(enabled: bool) -> void:
	_profile["miss_audio_ducking_enabled"] = enabled
	save_profile()


func get_menu_music_volume() -> float:
	return clampf(float(_profile.get("menu_music_volume", 1.0)), 0.0, 1.0)


func set_menu_music_volume(value: float) -> void:
	_profile["menu_music_volume"] = clampf(value, 0.0, 1.0)
	save_profile()


func get_gameplay_music_volume() -> float:
	return clampf(float(_profile.get("gameplay_music_volume", 1.0)), 0.0, 1.0)


func set_gameplay_music_volume(value: float) -> void:
	_profile["gameplay_music_volume"] = clampf(value, 0.0, 1.0)
	save_profile()


func are_theme_effects_enabled() -> bool:
	return bool(_profile.get("theme_effects_enabled", true))


func set_theme_effects_enabled(enabled: bool) -> void:
	_profile["theme_effects_enabled"] = enabled
	save_profile()


func is_chart_background_disabled() -> bool:
	return bool(_profile.get("chart_background_disabled", false))


func set_chart_background_disabled(disabled: bool) -> void:
	_profile["chart_background_disabled"] = disabled
	save_profile()


func are_shaders_enabled() -> bool:
	return bool(_profile.get("shaders_enabled", true))


func set_shaders_enabled(enabled: bool) -> void:
	_profile["shaders_enabled"] = enabled
	save_profile()


func is_visual_effect_bloom_enabled() -> bool:
	return bool(_profile.get("visual_effect_bloom_enabled", true))


func set_visual_effect_bloom_enabled(enabled: bool) -> void:
	_profile["visual_effect_bloom_enabled"] = enabled
	save_profile()


func is_visual_effect_distortion_enabled() -> bool:
	return bool(_profile.get("visual_effect_distortion_enabled", true))


func set_visual_effect_distortion_enabled(enabled: bool) -> void:
	_profile["visual_effect_distortion_enabled"] = enabled
	save_profile()


func is_visual_effect_particles_enabled() -> bool:
	return bool(_profile.get("visual_effect_particles_enabled", true))


func set_visual_effect_particles_enabled(enabled: bool) -> void:
	_profile["visual_effect_particles_enabled"] = enabled
	save_profile()


func is_visual_effect_background_animations_enabled() -> bool:
	return bool(_profile.get("visual_effect_background_animations_enabled", true))


func set_visual_effect_background_animations_enabled(enabled: bool) -> void:
	_profile["visual_effect_background_animations_enabled"] = enabled
	save_profile()


func get_ems_color_mode() -> String:
	var mode := str(_profile.get("ems_color_mode", "random")).to_lower()
	return "custom" if mode == "custom" else "random"


func set_ems_color_mode(mode: String) -> void:
	var normalized := mode.to_lower()
	_profile["ems_color_mode"] = "custom" if normalized == "custom" else "random"
	save_profile()


func get_ems_custom_primary() -> Color:
	var value: Variant = _profile.get("ems_custom_primary", Color(0.20, 0.78, 0.95, 1.0))
	return value if value is Color else Color(0.20, 0.78, 0.95, 1.0)


func set_ems_custom_primary(value: Color) -> void:
	_profile["ems_custom_primary"] = value
	save_profile()


func get_ems_custom_secondary() -> Color:
	var value: Variant = _profile.get("ems_custom_secondary", Color(0.85, 0.40, 0.95, 1.0))
	return value if value is Color else Color(0.85, 0.40, 0.95, 1.0)


func set_ems_custom_secondary(value: Color) -> void:
	_profile["ems_custom_secondary"] = value
	save_profile()


func get_ems_custom_accent() -> Color:
	var value: Variant = _profile.get("ems_custom_accent", Color(0.55, 0.92, 0.70, 1.0))
	return value if value is Color else Color(0.55, 0.92, 0.70, 1.0)


func set_ems_custom_accent(value: Color) -> void:
	_profile["ems_custom_accent"] = value
	save_profile()


func get_ems_trippy_level() -> String:
	var level := str(_profile.get("ems_trippy_level", "max")).to_lower()
	match level:
		"subtle", "medium", "max":
			return level
		_:
			return "max"


func set_ems_trippy_level(level: String) -> void:
	var normalized := level.to_lower()
	match normalized:
		"subtle", "medium", "max":
			_profile["ems_trippy_level"] = normalized
		_:
			_profile["ems_trippy_level"] = "max"
	save_profile()


func get_ems_background_mode() -> String:
	var mode := str(_profile.get("ems_background_mode", "psychedelic")).strip_edges().to_lower()
	match mode:
		"random", "psychedelic":
			return mode
		_:
			return "psychedelic"


func set_ems_background_mode(mode: String) -> void:
	var normalized := mode.strip_edges().to_lower()
	match normalized:
		"random", "psychedelic":
			_profile["ems_background_mode"] = normalized
		_:
			_profile["ems_background_mode"] = "psychedelic"
	save_profile()


func get_ems_background_solid_color() -> Color:
	var value: Variant = _profile.get("ems_background_solid_color", Color(0.04, 0.06, 0.12, 1.0))
	return value if value is Color else Color(0.04, 0.06, 0.12, 1.0)


func set_ems_background_solid_color(value: Color) -> void:
	_profile["ems_background_solid_color"] = value
	save_profile()


func get_ems_background_brightness() -> float:
	return clampf(float(_profile.get("ems_background_brightness", 0.40)), 0.0, 1.0)


func set_ems_background_brightness(value: float) -> void:
	_profile["ems_background_brightness"] = clampf(value, 0.0, 1.0)
	save_profile()


func get_ems_gutter_image_mode() -> String:
	var mode := str(_profile.get("ems_gutter_image_mode", "off")).to_lower()
	match mode:
		"both", "separate":
			return mode
		_:
			return "off"


func set_ems_gutter_image_mode(mode: String) -> void:
	var normalized := mode.to_lower()
	match normalized:
		"both", "separate":
			_profile["ems_gutter_image_mode"] = normalized
		_:
			_profile["ems_gutter_image_mode"] = "off"
	save_profile()


func get_ems_gutter_image_path_both() -> String:
	return str(_profile.get("ems_gutter_image_path_both", ""))


func set_ems_gutter_image_path_both(path: String) -> void:
	_profile["ems_gutter_image_path_both"] = path
	save_profile()


func get_ems_gutter_image_path_left() -> String:
	return str(_profile.get("ems_gutter_image_path_left", ""))


func set_ems_gutter_image_path_left(path: String) -> void:
	_profile["ems_gutter_image_path_left"] = path
	save_profile()


func get_ems_gutter_image_path_right() -> String:
	return str(_profile.get("ems_gutter_image_path_right", ""))


func set_ems_gutter_image_path_right(path: String) -> void:
	_profile["ems_gutter_image_path_right"] = path
	save_profile()


func get_ems_gutter_image_alpha() -> float:
	return clampf(float(_profile.get("ems_gutter_image_alpha", 0.22)), 0.0, 1.0)


func set_ems_gutter_image_alpha(value: float) -> void:
	_profile["ems_gutter_image_alpha"] = clampf(value, 0.0, 1.0)
	save_profile()


func is_prioritize_fps_enabled() -> bool:
	return bool(_profile.get("prioritize_fps_enabled", false))


func set_prioritize_fps_enabled(enabled: bool) -> void:
	_profile["prioritize_fps_enabled"] = enabled
	save_profile()


func get_fps_limit() -> int:
	var value := int(_profile.get("fps_limit", 0))
	return value if FPS_LIMIT_OPTIONS.has(value) else 0


func set_fps_limit(value: int) -> void:
	_profile["fps_limit"] = value if FPS_LIMIT_OPTIONS.has(value) else 0
	save_profile()


func get_vsync_mode() -> String:
	var mode := str(_profile.get("vsync_mode", "on")).to_lower()
	match mode:
		"off", "on", "adaptive":
			return mode
		_:
			return "on"


func set_vsync_mode(mode: String) -> void:
	var normalized := mode.to_lower()
	match normalized:
		"off", "on", "adaptive":
			_profile["vsync_mode"] = normalized
		_:
			_profile["vsync_mode"] = "on"
	save_profile()


func get_display_resolution() -> String:
	var resolution := str(_profile.get("display_resolution", DEFAULT_DISPLAY_RESOLUTION)).to_lower()
	return resolution if DISPLAY_RESOLUTION_OPTIONS.has(resolution) else DEFAULT_DISPLAY_RESOLUTION


func set_display_resolution(resolution: String) -> void:
	var normalized := resolution.to_lower()
	_profile["display_resolution"] = normalized if DISPLAY_RESOLUTION_OPTIONS.has(normalized) else DEFAULT_DISPLAY_RESOLUTION
	save_profile()


func get_lane_brightness() -> float:
	return clampf(float(_profile.get("lane_brightness", 1.0)), 0.0, 1.0)


func set_lane_brightness(value: float) -> void:
	_profile["lane_brightness"] = clampf(value, 0.0, 1.0)
	save_profile()


func get_note_opacity() -> float:
	return clampf(float(_profile.get("note_opacity", 1.0)), 0.5, 1.0)


func set_note_opacity(value: float) -> void:
	_profile["note_opacity"] = clampf(value, 0.5, 1.0)
	save_profile()


func are_notes_above_judgement_buttons() -> bool:
	return bool(_profile.get("notes_above_judgement_buttons", false))


func set_notes_above_judgement_buttons(enabled: bool) -> void:
	_profile["notes_above_judgement_buttons"] = enabled
	save_profile()


func get_ems_hit_effect() -> String:
	var mode := str(_profile.get("ems_hit_effect", "pressure")).to_lower()
	return mode if ["circular", "pressure"].has(mode) else "pressure"


func set_ems_hit_effect(mode: String) -> void:
	var normalized := mode.to_lower()
	_profile["ems_hit_effect"] = normalized if ["circular", "pressure"].has(normalized) else "pressure"
	save_profile()


func get_hit_effects_mode() -> String:
	var mode := str(_profile.get("hit_effects_mode", "enhanced")).to_lower()
	return mode if HIT_EFFECTS_MODES.has(mode) else "enhanced"


func set_hit_effects_mode(mode: String) -> void:
	var normalized := mode.to_lower()
	_profile["hit_effects_mode"] = normalized if HIT_EFFECTS_MODES.has(normalized) else "enhanced"
	save_profile()


func get_judgement_display_mode() -> String:
	var mode := str(_profile.get("judgement_display_mode", "modern")).to_lower()
	return mode if JUDGEMENT_DISPLAY_MODES.has(mode) else "modern"


func set_judgement_display_mode(mode: String) -> void:
	var normalized := mode.to_lower()
	_profile["judgement_display_mode"] = normalized if JUDGEMENT_DISPLAY_MODES.has(normalized) else "modern"
	save_profile()


func get_in_game_ui_mode() -> String:
	var mode := str(_profile.get("in_game_ui_mode", "modern")).to_lower()
	return mode if IN_GAME_UI_MODES.has(mode) else "modern"


func set_in_game_ui_mode(mode: String) -> void:
	var normalized := mode.to_lower()
	_profile["in_game_ui_mode"] = normalized if IN_GAME_UI_MODES.has(normalized) else "modern"
	save_profile()


func are_judgement_popups_enabled() -> bool:
	return bool(_profile.get("judgement_popups_enabled", true))


func set_judgement_popups_enabled(enabled: bool) -> void:
	_profile["judgement_popups_enabled"] = enabled
	save_profile()


func is_drive_meter_critical_fx_reduced() -> bool:
	return bool(_profile.get("reduce_drive_meter_critical_fx", false))


func set_drive_meter_critical_fx_reduced(enabled: bool) -> void:
	_profile["reduce_drive_meter_critical_fx"] = enabled
	save_profile()


func get_drive_meter_theme() -> String:
	var theme_id: String = str(_profile.get("drive_meter_theme", "auto")).to_lower()
	match theme_id:
		"auto", "classic", "mono":
			return theme_id
		_:
			return "auto"


func set_drive_meter_theme(theme_id: String) -> void:
	var normalized: String = theme_id.to_lower()
	match normalized:
		"auto", "classic", "mono":
			_profile["drive_meter_theme"] = normalized
		_:
			_profile["drive_meter_theme"] = "auto"
	save_profile()


func get_window_mode() -> String:
	var mode := str(_profile.get("window_mode", "")).to_lower()
	if mode == "fullscreen" or mode == "borderless_fullscreen" or mode == "windowed":
		return mode
	# Default desktop launch mode is fullscreen unless the user explicitly saved windowed.
	if OS.has_feature("windows") or OS.has_feature("macos") or OS.has_feature("linuxbsd"):
		return "fullscreen"
	return "windowed"


func set_window_mode(mode: String) -> void:
	var normalized := mode.to_lower()
	match normalized:
		"fullscreen", "borderless_fullscreen", "windowed":
			_profile["window_mode"] = normalized
		_:
			_profile["window_mode"] = "fullscreen"
	save_profile()


func get_selected_song_id() -> String:
	return str(_profile.get("selected_song_id", ""))


func set_selected_song_id(song_id: String) -> void:
	_profile["selected_song_id"] = song_id
	save_profile()


func get_visualizer_selected_song_id() -> String:
	return str(_profile.get("visualizer_selected_song_id", ""))


func set_visualizer_selected_song_id(song_id: String) -> void:
	if get_visualizer_selected_song_id() == song_id:
		return
	_profile["visualizer_selected_song_id"] = song_id
	save_profile()


func get_selected_difficulty() -> String:
	return str(_profile.get("selected_difficulty", "Medium"))


func set_selected_difficulty(difficulty: String) -> void:
	_profile["selected_difficulty"] = difficulty
	save_profile()


func get_selected_mode() -> String:
	var mode_id := str(_profile.get("selected_mode", GameModeConfig.DEFAULT_MODE))
	return mode_id if GameModeConfig.is_valid(mode_id) else GameModeConfig.DEFAULT_MODE


func set_selected_mode(mode_id: String) -> void:
	_profile["selected_mode"] = mode_id if GameModeConfig.is_valid(mode_id) else GameModeConfig.DEFAULT_MODE
	save_profile()


func get_guest_uuid() -> String:
	var existing := str(_profile.get("guest_uuid", ""))
	if existing.is_empty():
		existing = _generate_guest_uuid()
		_profile["guest_uuid"] = existing
		save_profile()
	return existing


func get_purchased_premium_product_ids() -> Array[String]:
	var result: Array[String] = []
	var value: Variant = _profile.get("purchased_premium_product_ids", [])
	if value is Array:
		for item in value:
			result.append(str(item))
	return result


func set_purchased_premium_product_ids(product_ids: Array[String]) -> void:
	_profile["purchased_premium_product_ids"] = product_ids.duplicate()
	save_profile()


func get_gameplay_stats() -> Dictionary:
	return _normalize_gameplay_stats(_profile.get("gameplay_stats", {}))


func set_gameplay_stats(stats: Dictionary) -> void:
	_profile["gameplay_stats"] = _normalize_gameplay_stats(stats)
	save_profile()


func record_gameplay_result_stats(result: Dictionary) -> Dictionary:
	var stats := _normalize_gameplay_stats(_profile.get("gameplay_stats", {}))
	var notes_hit := maxi(0, int(result.get("notes_hit", _notes_hit_from_result(result))))
	var default_misses := int(result.get("miss", 0)) + int(result.get("hold_breaks", 0))
	var notes_missed := maxi(0, int(result.get("notes_missed", default_misses)))
	stats["notes_hit"] = int(stats.get("notes_hit", 0)) + notes_hit
	stats["notes_missed"] = int(stats.get("notes_missed", 0)) + notes_missed

	var song_failed := bool(result.get("song_failed", result.get("result_failed", result.get("failed", false))))
	if song_failed:
		stats["song_failures"] = int(stats.get("song_failures", 0)) + 1
	else:
		stats["song_completions"] = int(stats.get("song_completions", 0)) + 1
		var all_perfect := bool(result.get("all_perfect", result.get("overdrive_sync", false)))
		var full_combo := bool(result.get("full_combo", result.get("drive_chain", false))) or all_perfect
		if full_combo:
			stats["full_combos"] = int(stats.get("full_combos", 0)) + 1
		if all_perfect:
			stats["all_perfects"] = int(stats.get("all_perfects", 0)) + 1

	_profile["gameplay_stats"] = stats
	save_profile()
	return stats.duplicate(true)


func get_steam_unique_completed_song_ids() -> Array[String]:
	var result: Array[String] = []
	var value: Variant = _profile.get("steam_unique_completed_song_ids", [])
	if value is Array:
		for item in value:
			result.append(str(item))
	return result


func set_steam_unique_completed_song_ids(song_ids: Array[String]) -> void:
	_profile["steam_unique_completed_song_ids"] = song_ids.duplicate()
	save_profile()


func get_steam_cumulative_playtime_seconds() -> float:
	return float(_profile.get("steam_cumulative_playtime_seconds", 0.0))


func set_steam_cumulative_playtime_seconds(value: float) -> void:
	_profile["steam_cumulative_playtime_seconds"] = maxf(0.0, value)
	save_profile()


func get_steam_best_leaderboard_ranks() -> Dictionary:
	return (_profile.get("steam_best_leaderboard_ranks", {}) as Dictionary).duplicate(true)


func set_steam_best_leaderboard_ranks(ranks: Dictionary) -> void:
	_profile["steam_best_leaderboard_ranks"] = ranks.duplicate(true)
	save_profile()


func get_steam_unlocked_achievement_ids() -> Array[String]:
	var result: Array[String] = []
	var value: Variant = _profile.get("steam_unlocked_achievement_ids", [])
	if value is Array:
		for item in value:
			result.append(str(item))
	return result


func set_steam_unlocked_achievement_ids(achievement_ids: Array[String]) -> void:
	_profile["steam_unlocked_achievement_ids"] = achievement_ids.duplicate()
	save_profile()


func get_steam_completed_multiplayer_match_ids() -> Array[String]:
	var result: Array[String] = []
	var value: Variant = _profile.get("steam_completed_multiplayer_match_ids", [])
	if value is Array:
		for item in value:
			result.append(str(item))
	return result


func set_steam_completed_multiplayer_match_ids(match_ids: Array[String]) -> void:
	_profile["steam_completed_multiplayer_match_ids"] = match_ids.duplicate()
	save_profile()


func get_steam_won_multiplayer_match_ids() -> Array[String]:
	var result: Array[String] = []
	var value: Variant = _profile.get("steam_won_multiplayer_match_ids", [])
	if value is Array:
		for item in value:
			result.append(str(item))
	return result


func set_steam_won_multiplayer_match_ids(match_ids: Array[String]) -> void:
	_profile["steam_won_multiplayer_match_ids"] = match_ids.duplicate()
	save_profile()


func clear_steam_tracking_data() -> void:
	_profile["steam_unique_completed_song_ids"] = []
	_profile["steam_cumulative_playtime_seconds"] = 0.0
	_profile["steam_best_leaderboard_ranks"] = {}
	_profile["steam_unlocked_achievement_ids"] = []
	_profile["steam_completed_multiplayer_match_ids"] = []
	_profile["steam_won_multiplayer_match_ids"] = []
	var progression := (_profile.get("progression", {}) as Dictionary).duplicate(true)
	if not progression.is_empty():
		progression["completed_songs"] = {}
		_profile["progression"] = progression
	save_profile()


func get_keyboard_layout_lane_counts() -> Array:
	return KEYBOARD_LAYOUT_LANE_COUNTS.duplicate()


func get_default_key_bindings(lane_count: int = LaneCountResolver.DEFAULT_LANES) -> Dictionary:
	return _default_key_bindings_for_lane_count(lane_count)


func get_key_bindings(lane_count: int = LaneCountResolver.DEFAULT_LANES) -> Dictionary:
	var layouts: Dictionary = _profile.get("key_bindings_by_lane_count", {}) as Dictionary
	var key := _keyboard_lane_count_key(lane_count)
	if not layouts.has(key):
		return _default_key_bindings_for_lane_count(lane_count)
	return _normalize_key_bindings_for_lane_count(layouts.get(key, {}), _keyboard_lane_count(lane_count))


func get_key_bindings_by_lane_count() -> Dictionary:
	return _normalize_key_bindings_by_lane_count(_profile.get("key_bindings_by_lane_count", {}), _profile.get("key_bindings", {}))


func set_key_binding(action: String, physical_keycode: int, lane_count: int = LaneCountResolver.DEFAULT_LANES) -> void:
	var clamped_lane_count := _keyboard_lane_count(lane_count)
	if not _action_belongs_to_lane_count(action, clamped_lane_count):
		return
	var layouts: Dictionary = get_key_bindings_by_lane_count()
	var key := str(clamped_lane_count)
	var bindings: Dictionary = _normalize_key_bindings_for_lane_count(layouts.get(key, {}), clamped_lane_count)
	bindings[action] = physical_keycode
	layouts[key] = bindings
	_profile["key_bindings_by_lane_count"] = layouts
	_profile["key_bindings"] = _normalize_key_bindings_for_lane_count(layouts.get(str(LaneCountResolver.DEFAULT_LANES), {}), LaneCountResolver.DEFAULT_LANES)
	save_profile()


func get_controller_bindings() -> Dictionary:
	return (_profile.get("controller_bindings", DEFAULT_CONTROLLER_BINDINGS) as Dictionary).duplicate(true)


func set_controller_binding(action: String, binding: Dictionary) -> void:
	var bindings: Dictionary = get_controller_bindings()
	bindings[action] = _normalize_single_controller_binding(binding, action)
	_profile["controller_bindings"] = bindings
	save_profile()


func _normalize_controller_bindings(raw_bindings: Variant) -> Dictionary:
	var normalized: Dictionary = DEFAULT_CONTROLLER_BINDINGS.duplicate(true)
	if raw_bindings is not Dictionary:
		return normalized
	var source: Dictionary = raw_bindings as Dictionary
	for action_variant in source.keys():
		var action: String = str(action_variant)
		normalized[action] = _normalize_single_controller_binding(source[action_variant], action)
	return normalized


func _normalize_key_bindings_by_lane_count(raw_layouts: Variant, legacy_bindings: Variant = {}) -> Dictionary:
	var normalized := {}
	var legacy_flat := _normalize_legacy_key_bindings(legacy_bindings)
	var preserve_legacy := legacy_bindings is Dictionary and not _key_bindings_match(legacy_flat, LEGACY_SHARED_KEY_BINDINGS)
	for lane_count in KEYBOARD_LAYOUT_LANE_COUNTS:
		var count := int(lane_count)
		var key := str(count)
		var raw_layout: Variant = null
		if raw_layouts is Dictionary:
			var layouts: Dictionary = raw_layouts as Dictionary
			if layouts.has(key):
				raw_layout = layouts[key]
			elif layouts.has(count):
				raw_layout = layouts[count]
		if raw_layout is Dictionary:
			normalized[key] = _normalize_key_bindings_for_lane_count(raw_layout, count)
		elif preserve_legacy:
			normalized[key] = _project_legacy_key_bindings_for_lane_count(legacy_flat, count)
		else:
			normalized[key] = _default_key_bindings_for_lane_count(count)
	return normalized


func _normalize_key_bindings_for_lane_count(raw_bindings: Variant, lane_count: int, fallback: Variant = null) -> Dictionary:
	var clamped_lane_count := _keyboard_lane_count(lane_count)
	var normalized: Dictionary = (fallback as Dictionary).duplicate(true) if fallback is Dictionary else _default_key_bindings_for_lane_count(clamped_lane_count)
	if raw_bindings is not Dictionary:
		return normalized
	var source: Dictionary = raw_bindings as Dictionary
	for lane in range(clamped_lane_count):
		var action := "lane_%d" % lane
		if source.has(action):
			normalized[action] = int(source[action])
	return normalized


func _normalize_legacy_key_bindings(raw_bindings: Variant) -> Dictionary:
	var normalized: Dictionary = LEGACY_SHARED_KEY_BINDINGS.duplicate(true)
	if raw_bindings is not Dictionary:
		return normalized
	var source: Dictionary = raw_bindings as Dictionary
	var legacy_five_lane_profile: bool = source.has("lane_3") \
		and source.has("lane_4") \
		and int(source.get("lane_3", 0)) == KEY_J \
		and int(source.get("lane_4", 0)) == KEY_K
	for action in LEGACY_SHARED_KEY_BINDINGS.keys():
		if source.has(action):
			normalized[action] = int(source[action])
		elif legacy_five_lane_profile and LEGACY_EXTRA_LANE_BINDINGS.has(action):
			normalized[action] = LEGACY_EXTRA_LANE_BINDINGS[action]
	return normalized


func _project_legacy_key_bindings_for_lane_count(legacy_flat: Dictionary, lane_count: int) -> Dictionary:
	var clamped_lane_count := _keyboard_lane_count(lane_count)
	var projected := _default_key_bindings_for_lane_count(clamped_lane_count)
	for lane in range(clamped_lane_count):
		var action := "lane_%d" % lane
		if legacy_flat.has(action):
			projected[action] = int(legacy_flat[action])
	return projected


func _default_key_bindings_for_lane_count(lane_count: int) -> Dictionary:
	var key := _keyboard_lane_count_key(lane_count)
	var bindings: Dictionary = DEFAULT_KEY_BINDINGS_BY_LANE_COUNT.get(key, DEFAULT_KEY_BINDINGS_BY_LANE_COUNT[str(LaneCountResolver.DEFAULT_LANES)])
	return bindings.duplicate(true)


func _keyboard_lane_count(lane_count: int) -> int:
	return clampi(lane_count, KEYBOARD_LAYOUT_MIN_LANES, KEYBOARD_LAYOUT_MAX_LANES)


func _keyboard_lane_count_key(lane_count: int) -> String:
	return str(_keyboard_lane_count(lane_count))


func _action_belongs_to_lane_count(action: String, lane_count: int) -> bool:
	if not action.begins_with("lane_"):
		return false
	var lane_text := action.trim_prefix("lane_")
	if not lane_text.is_valid_int():
		return false
	var lane := int(lane_text)
	return lane >= 0 and lane < _keyboard_lane_count(lane_count)


func _key_bindings_match(left: Dictionary, right: Dictionary) -> bool:
	for action in right.keys():
		if int(left.get(action, -1)) != int(right.get(action, -2)):
			return false
	return true


func _normalize_single_controller_binding(raw_binding: Variant, action: String = "") -> Dictionary:
	if raw_binding is Dictionary:
		var binding: Dictionary = raw_binding as Dictionary
		var kind: String = str(binding.get("kind", "")).to_lower()
		if kind == "axis":
			return {
				"kind": "axis",
				"axis": int(binding.get("axis", JOY_AXIS_LEFT_X)),
				"direction": -1 if float(binding.get("direction", 1.0)) < 0.0 else 1,
				"threshold": clampf(absf(float(binding.get("threshold", 0.5))), 0.1, 1.0),
			}
		if kind == "button":
			return {
				"kind": "button",
				"button_index": int(binding.get("button_index", JOY_BUTTON_A)),
			}
	if raw_binding is int:
		return {
			"kind": "button",
			"button_index": int(raw_binding),
		}
	if DEFAULT_CONTROLLER_BINDINGS.has(action):
		return (DEFAULT_CONTROLLER_BINDINGS[action] as Dictionary).duplicate(true)
	return {
		"kind": "button",
		"button_index": JOY_BUTTON_A,
	}


func get_progression_data() -> Dictionary:
	return (_profile.get("progression", {}) as Dictionary).duplicate(true)


func set_progression_data(data: Dictionary) -> void:
	_profile["progression"] = data.duplicate(true)
	save_profile()


func get_high_score(song_id: String, difficulty: String, mode: String = GameModeConfig.DEFAULT_MODE) -> Dictionary:
	var high_scores := _profile.get("high_scores", {}) as Dictionary
	var key := "%s::%s::%s" % [song_id, mode, difficulty]
	if not high_scores.has(key):
		if mode == GameModeConfig.DEFAULT_MODE:
			var legacy_key := "%s::%s" % [song_id, difficulty]
			if high_scores.has(legacy_key):
				return (high_scores[legacy_key] as Dictionary).duplicate(true)
		return {}
	return (high_scores[key] as Dictionary).duplicate(true)


func get_best_score_for_song(song_id: String) -> Dictionary:
	var high_scores := _profile.get("high_scores", {}) as Dictionary
	var best_payload: Dictionary = {}
	for key_variant in high_scores.keys():
		var key := str(key_variant)
		if not key.begins_with("%s::" % song_id):
			continue
		var payload := (high_scores.get(key_variant, {}) as Dictionary).duplicate(true)
		if payload.is_empty():
			continue
		if best_payload.is_empty() or int(payload.get("score", 0)) > int(best_payload.get("score", 0)):
			var parts := key.split("::")
			if parts.size() == 3:
				payload["mode"] = parts[1]
				payload["difficulty"] = parts[2]
			elif parts.size() == 2:
				payload["mode"] = GameModeConfig.DEFAULT_MODE
				payload["difficulty"] = parts[1]
			best_payload = payload
	return best_payload


func update_high_score(song_id: String, difficulty: String, payload: Dictionary, mode: String = GameModeConfig.DEFAULT_MODE) -> void:
	var high_scores := (_profile.get("high_scores", {}) as Dictionary).duplicate(true)
	var key := "%s::%s::%s" % [song_id, mode, difficulty]
	var existing := high_scores.get(key, {}) as Dictionary
	if existing.is_empty() or int(payload.get("score", 0)) >= int(existing.get("score", 0)):
		high_scores[key] = payload.duplicate(true)
		_profile["high_scores"] = high_scores
		save_profile()


func get_last_result() -> Dictionary:
	return (_profile.get("last_result", {}) as Dictionary).duplicate(true)


func set_last_result(result: Dictionary) -> void:
	_profile["last_result"] = result.duplicate(true)
	save_profile()


func _generate_guest_uuid() -> String:
	return "%08x%08x" % [int(Time.get_unix_time_from_system()), randi()]
