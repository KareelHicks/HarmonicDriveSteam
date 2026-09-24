extends Node

const EMSLoadoutCatalog = preload("res://scripts/ems/EMSLoadoutCatalog.gd")

##
# EmotionalMotionSystem
# --------------------
# Centralized atmosphere controller for Harmonic Drive.
#
# This is NOT a pile of disconnected effects scripts.
# The goal is to provide a single place that:
# - reacts to gameplay state (combo/performance, later: drive meter, fail state, etc.)
# - reacts to song intensity (bpm now; later: sections/peaks)
# - drives all non-gameplay ambient visuals BEHIND the gameplay layer
#
# Rendering & performance expectations:
# - All visual layers controlled by this system MUST render behind notes/receptors/HUD.
# - Effects must stay subtle at low intensity and never reduce readability.
# - Must be safe for mobile: avoid expensive shaders/particles by default.
#
# Global disable behavior:
# - This system is hard-gated by the player's "THEME EFFECTS" option.
# - When disabled, all registered layers stop processing/rendering.
##

signal enabled_changed(is_enabled: bool)
signal intensity_changed(value: float)
signal bpm_changed(value: float)
signal combo_energy_changed(value: float)
signal emotional_state_changed(state: String)
signal note_density_changed(value: float)
signal gutter_background_color_changed(color: Color)
signal loadout_changed(loadout_id: String)

## Public state (read by layers).
var enabled: bool = true:
	get:
		return _is_enabled

var intensity: float = 0.0:
	get:
		return _intensity

var bpm: float = 120.0:
	get:
		return _bpm

var combo_energy: float = 0.0:
	get:
		return _combo_energy

## Normalized note density proxy [0..1] (used to auto-reduce distortion).
var note_density: float = 0.0:
	get:
		return _note_density

## Public "mood" state driving atmosphere palettes/behavior.
## Valid values: "neutral", "euphoric", "melancholic", "chaos"
var emotional_state: String = "neutral":
	get:
		return _emotional_state

var _is_enabled := true
var _user_enabled := true
var _theme_effects_enabled := true

var _intensity := 0.0
var _bpm := 120.0
var _combo_energy := 0.0
var _combo_energy_target := 0.0
var _emotional_state := "neutral"
var _note_density := 0.0
var _note_density_target := 0.0

# Combo energy response tuning (Phase 4).
# These are intentionally conservative to avoid aggressive escalation.
@export var combo_energy_rise_rate := 1.4 # how quickly energy rises toward target (per second)
@export var combo_energy_decay_rate := 0.55 # how quickly energy decays toward target after misses/low combo (per second)
@export var combo_energy_curve_scale := 38.0 # higher = slower approach to 1.0 for high combos
@export var combo_energy_miss_target_floor := 0.12 # miss pulls target toward at least this (still smoothed)
@export var note_density_rise_rate := 2.0
@export var note_density_fall_rate := 1.2

var _combo_count := 0
var _last_combo_milestone := 0
var _recent_miss_timer := 0.0
var _beat_timer := 0.0

# Debug logging (throttled). Enabled by default in debug builds.
@export var debug_logging_enabled := false
@export var debug_log_interval_seconds := 1.0
var _debug_log_timer := 0.0
var _debug_last_log := ""

# Visual debug boost (lets you verify EMS visuals without permanently raising intensity).
# Keep at 1.0 for shipping; temporarily raise (e.g. 3.0-6.0) while testing.
@export var debug_visual_boost := 900.0

# EMS visual configuration (persisted in ProfileStore).
var color_mode := "random" # "random" | "custom"
var custom_primary := Color(0.20, 0.78, 0.95, 1.0)
var custom_secondary := Color(0.85, 0.40, 0.95, 1.0)
var custom_accent := Color(0.55, 0.92, 0.70, 1.0)
var trippy_level := "max" # "subtle" | "medium" | "max"

var _palette_rng := RandomNumberGenerator.new()
var _run_palette_colors: Array[Color] = []
var _run_palette_seed := 0
var _active_loadout_id := "ems_harmonic_core"
var _active_loadout_config: Dictionary = {}
var _loadout_palette_colors: Array[Color] = []
var _loadout_motion_profile := "harmonic_core"

# EMS background (gutter-only) configuration.
var background_mode := "solid" # "solid" | "random" | "psychedelic"
var background_solid_color := Color(0.04, 0.06, 0.12, 1.0)
var background_brightness := 0.40
var _gutter_bg_color := Color(0.04, 0.06, 0.12, 1.0)
var _gutter_bg_target := Color(0.04, 0.06, 0.12, 1.0)
var _gutter_bg_timer := 0.0
var _psychedelic_bg_phase := 0.0

# Judgement impulses (chart-synced hooks).
const _IMPULSE_MAX := 32
const _IMPULSE_TTL := 1.5
var _impulses: Array[Dictionary] = []

# Future: registered layered effects (Controls/CanvasItems) that implement EMS hooks.
var _registered_layers: Array[Node] = []


func _ready() -> void:
	if OS.is_debug_build():
		debug_logging_enabled = true
	_palette_rng.randomize()
	_sync_theme_effects_gate()
	if ProfileStore != null and not ProfileStore.profile_changed.is_connected(_on_profile_changed):
		ProfileStore.profile_changed.connect(_on_profile_changed)
	configure_from_profile()
	set_process(true)
	_debug_log("ready enabled=%s theme_effects=%s" % [str(_is_enabled), str(_theme_effects_enabled)])


func _process(delta: float) -> void:
	if debug_logging_enabled:
		_debug_log_timer += delta
		if _debug_log_timer >= maxf(0.1, debug_log_interval_seconds):
			_debug_log_timer = 0.0
			_debug_log_status()

	_recent_miss_timer = maxf(0.0, _recent_miss_timer - delta)

	# Age impulses.
	for i in range(_impulses.size() - 1, -1, -1):
		var imp := _impulses[i]
		imp["ttl"] = float(imp.get("ttl", 0.0)) - delta
		if float(imp["ttl"]) <= 0.0:
			_impulses.remove_at(i)
		else:
			_impulses[i] = imp

	# Smooth note density proxy.
	var density_rate := note_density_rise_rate if _note_density_target >= _note_density else note_density_fall_rate
	_note_density = lerpf(_note_density, _note_density_target, clampf(delta * density_rate, 0.0, 1.0))
	if absf(_note_density - _note_density_target) < 0.001:
		_note_density = _note_density_target

	# Keep combo energy smooth (avoid harsh flicker).
	var rate := combo_energy_rise_rate if _combo_energy_target >= _combo_energy else combo_energy_decay_rate
	_combo_energy = lerpf(_combo_energy, _combo_energy_target, clampf(delta * rate, 0.0, 1.0))
	if absf(_combo_energy - _combo_energy_target) < 0.001:
		_combo_energy = _combo_energy_target

	# Phase 1 intensity model:
	# - intentionally simple
	# - "combo_energy" is the dominant driver for now
	var target_intensity := clampf(_combo_energy, 0.0, 1.0)
	var next_intensity := lerpf(_intensity, target_intensity, clampf(delta * 2.5, 0.0, 1.0))
	if absf(next_intensity - _intensity) > 0.0005:
		_intensity = next_intensity
		intensity_changed.emit(_intensity)

	_update_gutter_background(delta)
	_update_read_only_events(delta)
	_update_layers(delta)


func set_song_bpm(value: float) -> void:
	var next := clampf(value, 10.0, 999.0)
	if is_equal_approx(next, _bpm):
		return
	_bpm = next
	bpm_changed.emit(_bpm)
	_debug_log("bpm=%s" % str(_bpm))

func set_note_density(value: float) -> void:
	var next := clampf(value, 0.0, 1.0)
	if is_equal_approx(next, _note_density_target):
		return
	_note_density_target = next
	note_density_changed.emit(_note_density_target)


func set_combo_energy(value: float) -> void:
	# Expected range: [0..1]. Callers can be sloppy; we clamp.
	var next := clampf(value, 0.0, 1.0)
	if is_equal_approx(next, _combo_energy_target):
		return
	_combo_energy_target = next
	combo_energy_changed.emit(_combo_energy_target)
	# (Status logging is throttled; no per-call prints here.)


func set_combo_count(combo_count: int) -> void:
	# Normalize combo streak -> energy target using a saturating curve.
	# This avoids abrupt jumps while still allowing "flow state" escalation.
	var previous_combo := _combo_count
	_combo_count = maxi(0, combo_count)
	var x := float(_combo_count)
	var scale := maxf(1.0, combo_energy_curve_scale)
	var streak_target := 1.0 - exp(-x / scale) # [0..1)

	# After a miss, keep target low and let decay be slow/smooth.
	if _combo_count == 0 and _recent_miss_timer > 0.0:
		streak_target = minf(streak_target, combo_energy_miss_target_floor)

	set_combo_energy(streak_target)
	if _combo_count != previous_combo:
		dispatch_ems_event("combo_changed", {"value": _combo_count, "previous": previous_combo, "strength": clampf(float(_combo_count) / 100.0, 0.0, 1.0)})
		var milestone := int(floor(float(_combo_count) / 50.0)) * 50
		if milestone > 0 and milestone != _last_combo_milestone:
			_last_combo_milestone = milestone
			dispatch_ems_event("combo_milestone", {"value": milestone, "strength": clampf(float(milestone) / 300.0, 0.0, 1.0)})
	if _combo_count == 0:
		_last_combo_milestone = 0


func notify_miss() -> void:
	# Never drop abruptly; just bias the target down and allow slow decay.
	_recent_miss_timer = 1.2
	var floored := minf(_combo_energy_target, combo_energy_miss_target_floor)
	set_combo_energy(floored)
	dispatch_ems_event("miss", {"strength": 1.0, "value": 0})


func set_enabled(value: bool) -> void:
	_user_enabled = value
	_recompute_enabled()


func set_emotional_state(state: String) -> void:
	var normalized := state.to_lower().strip_edges()
	match normalized:
		"neutral", "euphoric", "melancholic", "chaos":
			pass
		_:
			normalized = "neutral"
	if normalized == _emotional_state:
		return
	_emotional_state = normalized
	emotional_state_changed.emit(_emotional_state)
	_debug_log("emotional_state=%s" % _emotional_state)


func configure_from_profile() -> void:
	if ProfileStore == null:
		return
	var prev_color_mode := color_mode
	var prev_primary := custom_primary
	var prev_secondary := custom_secondary
	var prev_accent := custom_accent
	var prev_trippy := trippy_level
	var prev_bg_mode := background_mode
	var prev_bg_solid := background_solid_color
	var prev_bg_brightness := background_brightness
	var prev_loadout := _active_loadout_id

	color_mode = ProfileStore.get_ems_color_mode()
	custom_primary = ProfileStore.get_ems_custom_primary()
	custom_secondary = ProfileStore.get_ems_custom_secondary()
	custom_accent = ProfileStore.get_ems_custom_accent()
	trippy_level = ProfileStore.get_ems_trippy_level()
	background_mode = ProfileStore.get_ems_background_mode()
	background_solid_color = ProfileStore.get_ems_background_solid_color()
	background_brightness = ProfileStore.get_ems_background_brightness()
	_apply_profile_equipped_loadout()

	# If palette-affecting config changed, rebuild palette immediately so layers update
	# without requiring a song restart.
	var palette_changed := (
		prev_color_mode != color_mode
		or prev_primary != custom_primary
		or prev_secondary != custom_secondary
		or prev_accent != custom_accent
		or prev_trippy != trippy_level
		or prev_loadout != _active_loadout_id
	)
	if palette_changed:
		_refresh_run_palette_from_config()

	# Ensure runtime background state starts from config when changed.
	if prev_bg_mode != background_mode or prev_bg_solid != background_solid_color or not is_equal_approx(prev_bg_brightness, background_brightness):
		if background_mode == "solid":
			_gutter_bg_color = background_solid_color
			_gutter_bg_target = background_solid_color
		elif background_mode == "psychedelic":
			_psychedelic_bg_phase = 0.0
			_gutter_bg_target = _pick_psychedelic_background_target(_psychedelic_bg_phase)
		else:
			# Force an immediate new target on random mode switch.
			_gutter_bg_timer = 0.0
			_gutter_bg_target = _pick_background_target()
	if prev_loadout != _active_loadout_id:
		_notify_loadout_changed()


func apply_loadout(loadout_id: String) -> void:
	var config := EMSLoadoutCatalog.get_config(loadout_id)
	if bool(config.get("profile_driven", true)) and ProfileStore != null:
		color_mode = ProfileStore.get_ems_color_mode()
		custom_primary = ProfileStore.get_ems_custom_primary()
		custom_secondary = ProfileStore.get_ems_custom_secondary()
		custom_accent = ProfileStore.get_ems_custom_accent()
		trippy_level = ProfileStore.get_ems_trippy_level()
		background_mode = ProfileStore.get_ems_background_mode()
		background_solid_color = ProfileStore.get_ems_background_solid_color()
		background_brightness = ProfileStore.get_ems_background_brightness()
	_apply_loadout_config(loadout_id)
	_refresh_run_palette_from_config()
	if background_mode == "solid":
		_gutter_bg_color = background_solid_color
		_gutter_bg_target = background_solid_color
	elif background_mode == "psychedelic":
		_psychedelic_bg_phase = 0.0
		_gutter_bg_target = _pick_psychedelic_background_target(_psychedelic_bg_phase)
	else:
		_gutter_bg_timer = 0.0
		_gutter_bg_target = _pick_background_target()
	_notify_loadout_changed()


func get_active_loadout_id() -> String:
	return _active_loadout_id


func get_active_loadout_display_name() -> String:
	var registry := _ems_registry()
	if registry != null and registry.has_method("get_display_name"):
		return str(registry.call("get_display_name", _active_loadout_id))
	return EMSLoadoutCatalog.get_display_name(_active_loadout_id)


func get_active_loadout_config() -> Dictionary:
	return _active_loadout_config.duplicate(true)


func get_motion_profile() -> String:
	return _loadout_motion_profile


func get_signature_effect() -> String:
	return str(_active_loadout_config.get("signature_effect", "classic"))


func has_signature_effect() -> bool:
	var effect := get_signature_effect()
	return not has_community_runtime() and not bool(_active_loadout_config.get("profile_driven", true)) and not effect.is_empty() and effect != "classic"


func has_community_runtime() -> bool:
	return bool(_active_loadout_config.get("community_runtime", false))


func get_community_background_region() -> String:
	if not has_community_runtime():
		return "gutters"
	var layout: Dictionary = _active_loadout_config.get("community_layout", {}) as Dictionary
	var region := str(_active_loadout_config.get("community_background_region", layout.get("background_region", "gutters"))).strip_edges().to_lower()
	if region == "full_background":
		return "full_background"
	return "gutters"


func community_uses_full_background() -> bool:
	return has_community_runtime() and get_community_background_region() == "full_background"


func get_palette_morph() -> String:
	return str(_active_loadout_config.get("palette_morph", "profile"))


func get_reaction_model() -> String:
	return str(_active_loadout_config.get("reaction_model", "classic"))


func get_classic_layer_mix() -> Dictionary:
	var mix: Dictionary = _active_loadout_config.get("classic_layer_mix", {}) as Dictionary
	return mix.duplicate(true)


func is_classic_layer_enabled(layer_name: String, default_value: bool = true) -> bool:
	if has_community_runtime():
		return false
	if not has_signature_effect():
		return default_value
	var mix: Dictionary = _active_loadout_config.get("classic_layer_mix", {}) as Dictionary
	return bool(mix.get(layer_name, false))


func is_loadout_profile_driven() -> bool:
	return bool(_active_loadout_config.get("profile_driven", true))


func get_effective_hit_effect() -> String:
	var configured := str(_active_loadout_config.get("hit_effect", "")).to_lower()
	if configured in ["circular", "pressure"]:
		return configured
	if ProfileStore != null and ProfileStore.has_method("get_ems_hit_effect"):
		return str(ProfileStore.get_ems_hit_effect()).to_lower()
	return "circular"


func get_loadout_layer_weight(layer_name: String, default_value: float = 1.0) -> float:
	var weights: Dictionary = _active_loadout_config.get("layer_weights", {}) as Dictionary
	var value := float(weights.get(layer_name, default_value))
	value = clampf(value, 0.0, 1.35)
	if AppState != null and AppState.is_mobile_platform():
		value = minf(value, 1.08)
	if ProfileStore != null and ProfileStore.is_prioritize_fps_enabled():
		value = minf(value, 0.92)
	return value


func _apply_profile_equipped_loadout() -> void:
	var loadout_id := EMSLoadoutCatalog.get_default_loadout_id()
	if ProgressionManager != null and ProgressionManager.has_method("get_equipped_ems_loadout_id"):
		loadout_id = str(ProgressionManager.get_equipped_ems_loadout_id())
	_apply_loadout_config(loadout_id)


func _apply_loadout_config(loadout_id: String) -> void:
	var registry := _ems_registry()
	var entry: Dictionary = {}
	if registry != null and registry.has_method("get_entry"):
		entry = registry.call("get_entry", loadout_id) as Dictionary
	if entry.is_empty() and not EMSLoadoutCatalog.is_valid_loadout(loadout_id):
		loadout_id = EMSLoadoutCatalog.get_default_loadout_id()
		if registry != null and registry.has_method("get_entry"):
			entry = registry.call("get_entry", loadout_id) as Dictionary
	_active_loadout_id = loadout_id
	_active_loadout_config = (entry.get("config", EMSLoadoutCatalog.get_config(loadout_id)) as Dictionary).duplicate(true)
	_loadout_motion_profile = str(_active_loadout_config.get("motion_profile", "harmonic_core"))
	_loadout_palette_colors = _color_array(_active_loadout_config.get("palette", []))
	if bool(_active_loadout_config.get("profile_driven", true)):
		_loadout_palette_colors.clear()
		return
	color_mode = "loadout"
	trippy_level = str(_active_loadout_config.get("trippy_level", trippy_level))
	background_mode = str(_active_loadout_config.get("background_mode", background_mode))
	var solid_variant: Variant = _active_loadout_config.get("background_solid_color", background_solid_color)
	if solid_variant is Color:
		background_solid_color = solid_variant
	background_brightness = clampf(float(_active_loadout_config.get("background_brightness", background_brightness)), 0.0, 1.0)


func _color_array(value: Variant) -> Array[Color]:
	var colors: Array[Color] = []
	if value is Array:
		for item in value:
			if item is Color:
				colors.append(item)
	return colors


func _notify_loadout_changed() -> void:
	loadout_changed.emit(_active_loadout_id)
	for layer in _registered_layers:
		if layer == null or not is_instance_valid(layer):
			continue
		if layer.has_method("ems_on_loadout_changed"):
			layer.call("ems_on_loadout_changed", self)


func reseed_run_palette(seed: int = -1) -> void:
	# Random per run: if no seed provided, derive from time.
	_run_palette_seed = seed
	if _run_palette_seed < 0:
		_run_palette_seed = int(Time.get_ticks_msec()) ^ int(Time.get_unix_time_from_system())
	_palette_rng.seed = _run_palette_seed
	_run_palette_colors = _generate_palette()
	_debug_log("palette reseed=%d mode=%s level=%s" % [_run_palette_seed, color_mode, trippy_level])
	for layer in _registered_layers:
		if layer == null or not is_instance_valid(layer):
			continue
		if layer.has_method("ems_on_palette_changed"):
			layer.call("ems_on_palette_changed", self)


func get_run_palette_seed() -> int:
	return _run_palette_seed


func _refresh_run_palette_from_config() -> void:
	# Rebuild palette using the current run seed so "Random (New Each Run)" stays stable
	# until the next reseed, but custom colors apply immediately.
	if _run_palette_seed == 0:
		_run_palette_seed = int(Time.get_ticks_msec()) ^ int(Time.get_unix_time_from_system())
	_palette_rng.seed = _run_palette_seed
	_run_palette_colors = _generate_palette()
	_debug_log("palette refresh seed=%d mode=%s level=%s" % [_run_palette_seed, color_mode, trippy_level])
	for layer in _registered_layers:
		if layer == null or not is_instance_valid(layer):
			continue
		if layer.has_method("ems_on_palette_changed"):
			layer.call("ems_on_palette_changed", self)


func get_palette_colors() -> Array[Color]:
	if _run_palette_colors.is_empty():
		_run_palette_colors = _generate_palette()
	return _run_palette_colors


func pick_color(tag: String, index_seed: int) -> Color:
	# Deterministic color picking based on current run palette.
	var colors := get_palette_colors()
	if colors.is_empty():
		return Color(1, 1, 1, 1)
	var h := int(hash(tag) ^ index_seed ^ _run_palette_seed)
	var idx: int = int(abs(h)) % colors.size()
	var base: Color = colors[idx]

	# Gentle per-instance drift to avoid uniformity.
	var hsv: Vector3 = _rgb_to_hsv(base)
	var jitter := float(abs(h % 997)) / 997.0
	var hue := fmod(hsv.x + (jitter - 0.5) * 0.06 + _state_hue_shift(), 1.0)
	# Keep colors vivid; low-sat/low-val tends to read as gray in gutters.
	var sat := clampf(hsv.y * (1.05 + jitter * 0.18), 0.55, 1.0)
	var val := clampf(hsv.z * (0.98 + jitter * 0.16), 0.55, 1.0)
	return Color.from_hsv(hue, sat, val, base.a)


func get_style_multiplier() -> float:
	var base := 1.0
	match trippy_level:
		"subtle":
			base = 0.7
		"medium":
			base = 1.0
		_:
			base = 1.6
	# Safety caps.
	if AppState != null and AppState.is_mobile_platform():
		base *= 0.82
	if ProfileStore != null and ProfileStore.is_prioritize_fps_enabled():
		base *= 0.78
	if not bool(_active_loadout_config.get("profile_driven", true)):
		base *= clampf(float(_active_loadout_config.get("style_multiplier", 1.0)), 0.65, 1.35)
	return clampf(base, 0.45, 1.95)


func get_gutter_background_color() -> Color:
	# Intended for GameScene gutters only (outside lanes).
	return _dim_background(_gutter_bg_color)


func _dim_background(c: Color) -> Color:
	# Brightness multiplier for gutter-only background.
	# Recommended default is 0.40 (matches prior behavior).
	var d := c
	var mult := clampf(background_brightness, 0.0, 1.0)
	d.r *= mult
	d.g *= mult
	d.b *= mult
	d.a = 1.0
	return d


func notify_judgement(lane: int, judgement: String, strength: float, song_time: float, y_norm: float = 0.86) -> void:
	# Store a short-lived impulse so layers can react in sync with chart events.
	var imp := {
		"lane": lane,
		"judgement": judgement,
		"strength": clampf(strength, 0.0, 1.0),
		"song_time": song_time,
		"y_norm": clampf(y_norm, 0.0, 1.0),
		"color": pick_color("judgement_%s" % judgement, lane),
		"ttl": _IMPULSE_TTL,
	}
	_impulses.append(imp)
	if _impulses.size() > _IMPULSE_MAX:
		_impulses.remove_at(0)
	var judgement_key := judgement.to_lower()
	if judgement_key == "miss":
		dispatch_ems_event("miss", imp)
	elif judgement_key == "good":
		dispatch_ems_event("near_miss", imp)
	elif strength >= 0.85:
		dispatch_ems_event("bass_hit", imp)

	# Immediate dispatch hook (optional).
	for layer in _registered_layers:
		if layer == null or not is_instance_valid(layer):
			continue
		if not _layer_context_enabled(layer):
			continue
		if not _layer_visual_effect_enabled(layer):
			continue
		if layer.has_method("ems_on_impulse"):
			layer.call("ems_on_impulse", self, imp)


func notify_impulse(strength: float, y_norm: float, tag: String, index_seed: int = 0, color: Color = Color(0, 0, 0, 0)) -> void:
	# Generic impulse for non-gameplay contexts (e.g., Results UI).
	# Uses the same impulse packet shape so layers can react consistently.
	var c := color
	if c.a <= 0.0:
		c = pick_color(tag, index_seed)
	var imp := {
		"lane": index_seed,
		"judgement": "impulse",
		"strength": clampf(strength, 0.0, 1.0),
		"song_time": Time.get_unix_time_from_system(),
		"y_norm": clampf(y_norm, 0.0, 1.0),
		"color": c,
		"ttl": _IMPULSE_TTL,
	}
	_impulses.append(imp)
	if _impulses.size() > _IMPULSE_MAX:
		_impulses.remove_at(0)
	for layer in _registered_layers:
		if layer == null or not is_instance_valid(layer):
			continue
		if not _layer_context_enabled(layer):
			continue
		if not _layer_visual_effect_enabled(layer):
			continue
		if layer.has_method("ems_on_impulse"):
			layer.call("ems_on_impulse", self, imp)


func get_impulses() -> Array[Dictionary]:
	return _impulses


func dispatch_ems_event(event_name: String, payload: Dictionary = {}) -> void:
	for layer in _registered_layers:
		if layer == null or not is_instance_valid(layer):
			continue
		if not _layer_context_enabled(layer):
			continue
		if not _layer_visual_effect_enabled(layer):
			continue
		if layer.has_method("ems_on_custom_event"):
			layer.call("ems_on_custom_event", event_name, payload)


func _generate_palette() -> Array[Color]:
	if not _loadout_palette_colors.is_empty():
		return _loadout_palette_colors.duplicate()
	if color_mode == "custom":
		return [custom_primary, custom_secondary, custom_accent, custom_primary.lerp(custom_secondary, 0.5), custom_secondary.lerp(custom_accent, 0.5), custom_accent.lerp(custom_primary, 0.5)]

	# Random palette: choose a restrained but colorful base in HSV and derive harmonics.
	var base_h := _palette_rng.randf()
	var sat := _palette_rng.randf_range(0.55, 0.90)
	var val := _palette_rng.randf_range(0.70, 0.98)
	var c1 := Color.from_hsv(base_h, sat, val, 1.0)
	var c2 := Color.from_hsv(fmod(base_h + 0.33, 1.0), clampf(sat * 0.90, 0.45, 0.95), clampf(val * 0.95, 0.55, 1.0), 1.0)
	var c3 := Color.from_hsv(fmod(base_h + 0.66, 1.0), clampf(sat * 0.85, 0.40, 0.95), clampf(val * 0.90, 0.55, 1.0), 1.0)
	var c4 := c1.lerp(Color.WHITE, 0.12)
	var c5 := c2.lerp(Color.BLACK, 0.08)
	var c6 := c3.lerp(Color.WHITE, 0.10)
	return [c1, c2, c3, c4, c5, c6]


func _update_read_only_events(delta: float) -> void:
	if _bpm <= 0.0:
		return
	var beat_seconds := 60.0 / maxf(1.0, _bpm)
	_beat_timer += delta
	while _beat_timer >= beat_seconds:
		_beat_timer -= beat_seconds
		dispatch_ems_event("beat", {"strength": clampf(0.35 + _combo_energy * 0.45 + _intensity * 0.20, 0.0, 1.0), "bpm": _bpm})


func _update_gutter_background(delta: float) -> void:
	# Background color is a gutter-only visualization aid and aesthetic layer.
	# It MUST NOT affect lane readability.
	if background_mode == "solid":
		_gutter_bg_target = background_solid_color
	elif background_mode == "psychedelic":
		var bpm_scale := clampf(_bpm / 140.0, 0.70, 1.45)
		var energy := clampf((_combo_energy * 0.55) + (_intensity * 0.45), 0.0, 1.0)
		var fps_scale := 0.68 if ProfileStore != null and ProfileStore.is_prioritize_fps_enabled() else 1.0
		_psychedelic_bg_phase = fmod(_psychedelic_bg_phase + delta * (0.045 + energy * 0.035) * bpm_scale * fps_scale, 1.0)
		_gutter_bg_target = _pick_psychedelic_background_target(_psychedelic_bg_phase)
	else:
		_gutter_bg_timer -= delta
		if _gutter_bg_timer <= 0.0:
			# Change interval: slower by default, slightly faster when BPM is high.
			var random_bpm_scale := clampf(_bpm / 160.0, 0.75, 1.35)
			_gutter_bg_timer = _palette_rng.randf_range(2.6, 5.5) / random_bpm_scale
			_gutter_bg_target = _pick_background_target()

	# Smooth transition (no flashing).
	var t := 1.0 - exp(-delta * 1.15)
	var next := _gutter_bg_color.lerp(_gutter_bg_target, t)
	# Keep alpha at 1.0 for the ColorRect usage.
	next.a = 1.0
	if next != _gutter_bg_color:
		_gutter_bg_color = next
		gutter_background_color_changed.emit(_dim_background(_gutter_bg_color))


func _pick_psychedelic_background_target(phase: float) -> Color:
	var wrapped := fmod(phase, 1.0)
	if wrapped < 0.0:
		wrapped += 1.0
	var energy := clampf((_combo_energy * 0.50) + (_intensity * 0.50), 0.0, 1.0)
	var impulse_energy := _recent_impulse_energy()
	var colors := get_palette_colors()
	if colors.is_empty():
		return Color(0.04, 0.06, 0.12, 1.0)
	var palette_pos: float = wrapped * float(colors.size())
	var base_index := int(floor(palette_pos))
	var palette_mix: float = palette_pos - floor(palette_pos)
	var beat_fusion := sin((wrapped * TAU * 2.0) + (_bpm * 0.003)) * 0.5 + 0.5
	var fusion := clampf((beat_fusion * 0.55) + (energy * 0.25) + (impulse_energy * 0.35), 0.0, 1.0)
	var c_a := _psychedelic_palette_color(base_index, wrapped, energy, impulse_energy)
	var c_b := _psychedelic_palette_color(base_index + 1, wrapped + 0.19, energy, impulse_energy)
	var c_c := _psychedelic_palette_color(base_index + 2, wrapped + 0.37, energy, impulse_energy)
	var c := c_a.lerp(c_b, palette_mix).lerp(c_c, 0.16 + fusion * 0.22)
	c = c.lerp(Color(0.035, 0.045, 0.09, 1.0), 0.24)
	c.a = 1.0
	return c


func _psychedelic_palette_color(index: int, phase: float, energy: float, impulse_energy: float) -> Color:
	var colors := get_palette_colors()
	if colors.is_empty():
		return Color(0.04, 0.06, 0.12, 1.0)
	var idx := index % colors.size()
	if idx < 0:
		idx += colors.size()
	var base: Color = colors[idx]
	var hsv := _rgb_to_hsv(base)
	var hue_wobble := sin((phase + float(idx) * 0.173) * TAU) * (0.018 + energy * 0.018 + impulse_energy * 0.014)
	var hue := fmod(hsv.x + hue_wobble + _state_hue_shift(), 1.0)
	if hue < 0.0:
		hue += 1.0
	var sat := clampf(maxf(hsv.y, 0.62) + energy * 0.10 + impulse_energy * 0.08, 0.0, 1.0)
	var val := clampf(maxf(hsv.z, 0.58) + energy * 0.12 + impulse_energy * 0.10, 0.0, 0.96)
	return Color.from_hsv(hue, sat, val, 1.0)


func _recent_impulse_energy() -> float:
	var strongest := 0.0
	for imp in _impulses:
		var ttl_ratio := clampf(float(imp.get("ttl", 0.0)) / _IMPULSE_TTL, 0.0, 1.0)
		var strength := clampf(float(imp.get("strength", 0.0)), 0.0, 1.0)
		strongest = maxf(strongest, strength * ttl_ratio)
	return strongest


func _pick_background_target() -> Color:
	# Derive from the run palette, but keep it darker so the colored lines/shapes read.
	var colors := get_palette_colors()
	if colors.is_empty():
		return Color(0.04, 0.06, 0.12, 1.0)
	var idx := int(abs(int(_palette_rng.randi()))) % colors.size()
	var c: Color = colors[idx]
	# Darken and slightly desaturate for comfort.
	c = c.lerp(Color.BLACK, 0.65)
	c = c.lerp(Color(0.08, 0.10, 0.16, 1.0), 0.25)
	c.a = 1.0
	return c


func _state_hue_shift() -> float:
	match _emotional_state:
		"euphoric":
			return 0.01
		"melancholic":
			return -0.01
		"chaos":
			return 0.02
		_:
			return 0.0


func _rgb_to_hsv(color: Color) -> Vector3:
	# Godot 4 does not expose Color.to_hsv(); keep this local and lightweight.
	# Returns Vector3(h, s, v) with h in [0..1).
	var r := color.r
	var g := color.g
	var b := color.b
	var c_max := maxf(r, maxf(g, b))
	var c_min := minf(r, minf(g, b))
	var delta := c_max - c_min

	var h := 0.0
	if delta > 0.000001:
		if c_max == r:
			h = fmod(((g - b) / delta), 6.0)
		elif c_max == g:
			h = ((b - r) / delta) + 2.0
		else:
			h = ((r - g) / delta) + 4.0
		h /= 6.0
		if h < 0.0:
			h += 1.0

	var s := 0.0 if c_max <= 0.000001 else (delta / c_max)
	var v := c_max
	return Vector3(h, s, v)


func register_layer(layer: Node) -> void:
	# Layers are optional. This supports future EMS-driven architecture where
	# layered visuals register and are updated centrally for consistent gating.
	if layer == null:
		return
	if _registered_layers.has(layer):
		return
	_registered_layers.append(layer)
	_apply_enabled_to_layer(layer)
	_debug_log("register_layer name=%s count=%d" % [str(layer.name), _registered_layers.size()])


func unregister_layer(layer: Node) -> void:
	_registered_layers.erase(layer)
	if layer != null and is_instance_valid(layer):
		_debug_log("unregister_layer name=%s count=%d" % [str(layer.name), _registered_layers.size()])


func _update_layers(delta: float) -> void:
	if _registered_layers.is_empty():
		return

	# Don't hold onto freed nodes.
	for i in range(_registered_layers.size() - 1, -1, -1):
		var layer := _registered_layers[i]
		if layer == null or not is_instance_valid(layer):
			_registered_layers.remove_at(i)
			continue
		if not _layer_context_enabled(layer):
			continue
		if not _layer_visual_effect_enabled(layer):
			continue

		# Central update hook (optional).
		if layer.has_method("ems_update"):
			layer.call("ems_update", self, delta)


func _on_profile_changed() -> void:
	configure_from_profile()
	_sync_theme_effects_gate()


func _ems_registry() -> Node:
	return get_node_or_null("/root/EMSRegistry")


func _sync_theme_effects_gate() -> void:
	_theme_effects_enabled = true
	if ProfileStore != null:
		_theme_effects_enabled = ProfileStore.are_theme_effects_enabled()
	_recompute_enabled()


func _recompute_enabled() -> void:
	var next_enabled := _user_enabled and _theme_effects_enabled
	if next_enabled == _is_enabled:
		return
	_is_enabled = next_enabled
	enabled_changed.emit(_is_enabled)
	_debug_log("enabled=%s user=%s theme_effects=%s" % [str(_is_enabled), str(_user_enabled), str(_theme_effects_enabled)])

	# Hard gate all layers: stop processing and hide.
	for layer in _registered_layers:
		if layer == null or not is_instance_valid(layer):
			continue
		_apply_enabled_to_layer(layer)


func _apply_enabled_to_layer(layer: Node) -> void:
	var effective_enabled := _is_enabled and _layer_visual_effect_enabled(layer) and _layer_context_enabled(layer)
	# Contract: a layer may implement `ems_on_enabled_changed(is_enabled)` for custom handling.
	if layer.has_method("ems_on_enabled_changed"):
		layer.call("ems_on_enabled_changed", effective_enabled)

	# Generic safe defaults: do not render or tick when disabled.
	if layer is CanvasItem:
		(layer as CanvasItem).visible = effective_enabled
	if layer is Node:
		(layer as Node).set_process(effective_enabled)
		(layer as Node).set_physics_process(effective_enabled)


func _layer_visual_effect_enabled(layer: Node) -> bool:
	if layer.has_meta("ems_visual_effect_enabled"):
		return bool(layer.get_meta("ems_visual_effect_enabled"))
	return true


func _layer_context_enabled(layer: Node) -> bool:
	if layer.has_meta("ems_context_active"):
		return bool(layer.get_meta("ems_context_active"))
	return true


func _debug_log_status() -> void:
	# One-line snapshot, throttled, to confirm EMS is actively changing during gameplay.
	# (Avoids log spam while still proving it's alive.)
	var msg := "status enabled=%s bpm=%.2f combo=%d dens=%.2f target=%.3f energy=%.3f intensity=%.3f state=%s layers=%d" % [
		str(_is_enabled),
		_bpm,
		_combo_count,
		_note_density,
		_combo_energy_target,
		_combo_energy,
		_intensity,
		_emotional_state,
		_registered_layers.size(),
	]
	if msg != _debug_last_log:
		_debug_last_log = msg
		_debug_log(msg)


func _debug_log(message: String) -> void:
	if not debug_logging_enabled:
		return
	print("[EMS] %s" % message)


func get_visual_boost() -> float:
	# Allow boosting only when EMS is enabled; clamp to avoid accidental extremes.
	return clampf(debug_visual_boost, 0.5, 12.5)


# --- Future hooks (Phase 4+) -------------------------------------------------
# These are placeholders for future EMS-driven systems.
# Keep them lightweight and centrally gated by EMS.enabled.

func get_distortion_strength() -> float:
	# Future: subtle screen-space distortion. Must remain behind notes/readability-first.
	return 0.0


func get_camera_motion() -> Vector2:
	# Future: gentle camera sway/float. Keep small to avoid motion sickness on mobile.
	return Vector2.ZERO


func get_hallucination_amount() -> float:
	# Future: dreamlike overlays. Must remain subtle and globally disable-able.
	return 0.0
