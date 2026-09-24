extends Node2D
class_name EMSLoadoutSignatureLayer

const POOL_DESKTOP := 72
const POOL_MOBILE := 36
const IMPULSE_MAX := 18
const CYBER_OCEAN_BASE_TIDE_SPEED := 0.30
const CYBER_OCEAN_MAX_TIDE_BOOST := 1.35
const CYBER_OCEAN_CADENCE_HITS := 5.0
const VISUALIZER_RANDOMIZED_PLACEMENT_EFFECTS := [
	"fractal_space",
	"solar_bloom",
	"lunar_glass",
	"thunder_matrix",
	"chromatic_rift",
	"crystal_reactor",
	"gravity_well",
	"hypernova_flow",
	"singularity_bloom",
]

var _rng := RandomNumberGenerator.new()
var _effect := "classic"
var _palette_morph := "profile"
var _reaction_model := "classic"
var _units: Array[Dictionary] = []
var _impulses: Array[Dictionary] = []
var _time := 0.0
var _active_count := 0
var _bounds := Vector2(1, 1)
var _energy := 0.0
var _pulse := 0.0
var _cyber_ocean_flow := 0.0
var _ems_ref: Node
var _profile_ref: Node
var _app_state_ref: Node
var _override_ems_ref: Node
var _manual_bounds := Vector2.ZERO
var _visualizer_placement_salt := 0
var _visualizer_placement_host_enabled := false
var _placement_seed := 0
var _placement_offset := Vector2.ZERO
var _placement_phase := 0.0


func _ready() -> void:
	name = "EMSLoadoutSignatureLayer"
	_rng.randomize()
	_sync_effect(true)
	var ems := _ems()
	if ems != null:
		ems.call("register_layer", self)
	set_process(true)


func _exit_tree() -> void:
	var ems := _ems()
	if ems != null:
		ems.call("unregister_layer", self)


func set_embedded_context(ems_provider: Node, bounds_size: Vector2 = Vector2.ZERO) -> void:
	_override_ems_ref = ems_provider
	_ems_ref = ems_provider
	set_manual_bounds(bounds_size)
	_sync_effect(true)


func set_visualizer_placement_salt(salt: int, host_enabled: bool = true) -> void:
	_visualizer_placement_salt = salt
	_visualizer_placement_host_enabled = host_enabled


func set_manual_bounds(bounds_size: Vector2) -> void:
	_manual_bounds = Vector2(maxf(0.0, bounds_size.x), maxf(0.0, bounds_size.y))
	if _manual_bounds.x > 1.0 and _manual_bounds.y > 1.0:
		_bounds = _manual_bounds
	elif is_inside_tree():
		_bounds = _get_bounds_size()
	else:
		_bounds = Vector2(1.0, 1.0)
	queue_redraw()


func ems_on_enabled_changed(is_enabled: bool) -> void:
	visible = is_enabled
	set_process(is_enabled)
	if not is_enabled:
		_impulses.clear()
		queue_redraw()


func ems_on_loadout_changed(_ems: Node) -> void:
	_sync_effect(true)


func ems_on_palette_changed(_ems: Node) -> void:
	_rebuild_pool()


func ems_on_impulse(_ems: Node, impulse: Dictionary) -> void:
	var ems := _ems()
	if ems == null or not bool(ems.get("enabled")) or not bool(ems.call("has_signature_effect")):
		return
	var c: Color = impulse.get("color", ems.call("pick_color", "signature_impulse", int(impulse.get("lane", 0))))
	_impulses.append({
		"ttl": 1.15,
		"age": 0.0,
		"strength": clampf(float(impulse.get("strength", 0.5)), 0.0, 1.0),
		"y_norm": clampf(float(impulse.get("y_norm", 0.82)), 0.0, 1.0),
		"lane": int(impulse.get("lane", 0)),
		"judgement": str(impulse.get("judgement", "hit")),
		"color": c,
	})
	if _impulses.size() > IMPULSE_MAX:
		_impulses.remove_at(0)


func ems_update(_ems: Node, delta: float) -> void:
	var ems := _ems()
	if ems == null or not bool(ems.get("enabled")):
		return
	_sync_effect()
	if not bool(ems.call("has_signature_effect")):
		_active_count = 0
		return
	_time += delta
	_bounds = _get_bounds_size()
	var combo := clampf(float(ems.get("combo_energy")), 0.0, 1.0)
	var intensity := clampf(float(ems.get("intensity")), 0.0, 1.0)
	var density := clampf(float(ems.get("note_density")), 0.0, 1.0)
	_energy = clampf(0.18 + combo * 0.52 + intensity * 0.42 + _impulse_energy() * 0.34, 0.0, 1.0)
	var bpm := maxf(10.0, float(ems.get("bpm")))
	_pulse = sin(_time * TAU * clampf(bpm / 120.0, 0.6, 1.8)) * 0.5 + 0.5
	var limit := _pool_limit()
	_active_count = clampi(int(roundi(float(limit) * clampf(0.38 + _energy * 0.55 + density * 0.14, 0.0, 1.0))), 0, limit)
	_update_impulses(delta)
	_update_cyber_ocean_flow(delta, combo)
	_update_units(delta, bpm, density)
	queue_redraw()


func get_debug_state() -> Dictionary:
	var ems := _ems()
	return {
		"effect": _effect,
		"palette_morph": _palette_morph,
		"reaction_model": _reaction_model,
		"active_count": _active_count,
		"pool_size": _units.size(),
		"impulses": _impulses.size(),
		"render_family": _render_family(),
		"signature_active": ems != null and bool(ems.call("has_signature_effect")),
		"visualizer_randomized_placement": _visualizer_placement_randomization_enabled(),
		"placement_seed": _placement_seed,
		"placement_offset": _placement_offset,
		"cyber_ocean_flow": _cyber_ocean_flow,
		"cyber_ocean_tide_speed": _cyber_ocean_tide_speed(),
	}


func _sync_effect(force: bool = false) -> void:
	var next_effect := "classic"
	var next_morph := "profile"
	var next_reaction := "classic"
	var ems := _ems()
	if ems != null:
		next_effect = str(ems.call("get_signature_effect"))
		next_morph = str(ems.call("get_palette_morph"))
		next_reaction = str(ems.call("get_reaction_model"))
	if force or next_effect != _effect or next_morph != _palette_morph or next_reaction != _reaction_model:
		if force or next_effect != _effect:
			_cyber_ocean_flow = 0.0
		_effect = next_effect
		_palette_morph = next_morph
		_reaction_model = next_reaction
		_rebuild_pool()


func _rebuild_pool() -> void:
	_units.clear()
	var base_seed := int(abs(hash("%s:%s:%s" % [_effect, _palette_morph, _reaction_model])))
	var randomize_placement := _visualizer_placement_randomization_enabled()
	if randomize_placement:
		var ems := _ems()
		var run_seed := int(ems.call("get_run_palette_seed")) if ems != null and ems.has_method("get_run_palette_seed") else 0
		base_seed = int(abs(hash("%d:%d:%d" % [base_seed, run_seed, _visualizer_placement_salt])))
	_placement_seed = base_seed
	_rng.seed = _placement_seed
	if randomize_placement:
		_placement_offset = Vector2(_rng.randf_range(-0.12, 0.12), _rng.randf_range(-0.09, 0.09))
		_placement_phase = _rng.randf_range(-0.45, 0.45)
	else:
		_placement_offset = Vector2.ZERO
		_placement_phase = 0.0
	for i in POOL_DESKTOP:
		_units.append({
			"seed": i,
			"pos": Vector2(_rng.randf(), _rng.randf()),
			"vel": Vector2(_rng.randf_range(-0.18, 0.18), _rng.randf_range(-0.10, 0.28)),
			"phase": _rng.randf_range(0.0, TAU),
			"phase2": _rng.randf_range(0.0, TAU),
			"size": _rng.randf_range(0.018, 0.085),
			"kind": _rng.randi_range(0, 5),
			"radius": _rng.randf_range(0.10, 0.42),
			"speed": _rng.randf_range(0.45, 1.65),
		})
	queue_redraw()


func _visualizer_placement_randomization_enabled() -> bool:
	var app_state := _app_state()
	return (
		_visualizer_placement_host_enabled
		and app_state != null
		and bool(app_state.get("visualizer_active"))
		and VISUALIZER_RANDOMIZED_PLACEMENT_EFFECTS.has(_effect)
	)


func _placement_center(base: Vector2) -> Vector2:
	return Vector2(
		clampf(base.x + _placement_offset.x, 0.20, 0.80),
		clampf(base.y + _placement_offset.y, 0.20, 0.80)
	)


func _pool_limit() -> int:
	var limit := POOL_DESKTOP
	if _is_mobile_platform():
		limit = POOL_MOBILE
	if _prioritize_fps_enabled():
		limit = int(roundi(float(limit) * 0.56))
	return clampi(limit, 8, POOL_DESKTOP)


func _update_impulses(delta: float) -> void:
	for i in range(_impulses.size() - 1, -1, -1):
		var imp := _impulses[i]
		imp["age"] = float(imp.get("age", 0.0)) + delta
		if float(imp["age"]) >= float(imp.get("ttl", 1.0)):
			_impulses.remove_at(i)
		else:
			_impulses[i] = imp


func _update_cyber_ocean_flow(delta: float, combo: float) -> void:
	if _effect != "cyber_ocean":
		_cyber_ocean_flow = 0.0
		return
	var cadence := _cyber_ocean_hit_cadence()
	var target := clampf(combo * 0.78 + cadence * 0.55, 0.0, 1.0)
	var rise_rate := lerpf(0.85, 1.90, cadence)
	var response_rate := rise_rate if target >= _cyber_ocean_flow else 0.60
	var follow := 1.0 - exp(-maxf(0.0, delta) * response_rate)
	_cyber_ocean_flow = lerpf(_cyber_ocean_flow, target, follow)
	if absf(_cyber_ocean_flow - target) < 0.0005:
		_cyber_ocean_flow = target


func _cyber_ocean_hit_cadence() -> float:
	var recent_hit_weight := 0.0
	for imp in _impulses:
		if not _is_hit_impulse(imp):
			continue
		var ttl := maxf(0.001, float(imp.get("ttl", 1.0)))
		var t := clampf(float(imp.get("age", 0.0)) / ttl, 0.0, 1.0)
		recent_hit_weight += clampf(float(imp.get("strength", 0.0)), 0.0, 1.0) * (1.0 - t)
	return clampf(recent_hit_weight / CYBER_OCEAN_CADENCE_HITS, 0.0, 1.0)


func _cyber_ocean_tide_speed() -> float:
	return CYBER_OCEAN_BASE_TIDE_SPEED + _cyber_ocean_flow * CYBER_OCEAN_MAX_TIDE_BOOST


func _update_units(delta: float, bpm: float, density: float) -> void:
	if _bounds.x <= 1.0 or _bounds.y <= 1.0:
		return
	var bpm_scale := clampf(bpm / 140.0, 0.65, 1.9)
	var impulse := _impulse_energy()
	for i in _active_count:
		var u := _units[i]
		var pos: Vector2 = u["pos"]
		var vel: Vector2 = u["vel"]
		var speed := float(u.get("speed", 1.0)) * bpm_scale * (0.65 + _energy * 0.55)
		match _effect:
			"neon_rain":
				pos.y += delta * (0.20 + speed * 0.20 + impulse * 0.18)
				pos.x += sin(_time * 1.25 + float(u["phase"])) * delta * 0.010
			"digital_snow":
				pos.y += delta * (0.035 + speed * 0.035)
				pos.x += sin(_time * 0.9 + float(u["phase"])) * delta * (0.025 + impulse * 0.05)
			"plasma_storm":
				pos += Vector2(
					sin(_time * (0.65 + speed * 0.08) + float(u["phase"])) * 0.055,
					cos(_time * (0.52 + speed * 0.07) + float(u["phase2"])) * 0.040
				) * delta * (0.8 + density + impulse)
			"quantum_grid":
				var cell := 0.125 + float(u["kind"] % 3) * 0.018
				var snapped := Vector2(round(pos.x / cell) * cell, round(pos.y / cell) * cell)
				pos = pos.lerp(snapped, clampf(delta * (0.8 + speed * 0.4 + impulse * 1.5), 0.0, 1.0))
				pos += Vector2(sin(_time + float(u["phase2"])), cos(_time * 0.7 + float(u["phase"]))) * delta * 0.010
			"aurora_drive":
				pos.x += delta * (0.018 + speed * 0.018)
				pos.y += sin(_time * 0.34 + float(u["phase"])) * delta * (0.018 + _energy * 0.016)
			"fractal_space":
				var fractal_center := _placement_center(Vector2(0.5 + sin(float(u["phase"])) * 0.08, 0.50 + cos(float(u["phase2"])) * 0.06))
				var fractal_rel := pos - fractal_center
				fractal_rel = fractal_rel.rotated(delta * (0.18 + speed * 0.16 + impulse * 0.35))
				fractal_rel *= 1.0 + sin(_time * 0.8 + float(u["phase"])) * delta * 0.010
				pos = fractal_center + fractal_rel
			"prism_circuit":
				if int(u["kind"]) % 2 == 0:
					pos.x += delta * (0.040 + speed * 0.030 + impulse * 0.055)
				else:
					pos.y += delta * (0.034 + speed * 0.026 + impulse * 0.045)
				pos.x = floorf(pos.x / 0.035) * 0.035 + sin(float(u["phase"])) * 0.004
				pos.y = floorf(pos.y / 0.035) * 0.035 + cos(float(u["phase2"])) * 0.004
			"solar_bloom":
				var solar_center := _placement_center(Vector2(0.5, 0.54))
				var solar_rel := pos - solar_center
				solar_rel = solar_rel.rotated(delta * (0.10 + speed * 0.12 + impulse * 0.28))
				solar_rel *= 1.0 + delta * (0.008 + impulse * 0.018)
				pos = solar_center + solar_rel
			"gravity_well", "singularity_bloom":
				var center := _placement_center(Vector2(0.5, 0.52))
				var rel := pos - center
				var angle := delta * (0.20 + speed * 0.20 + impulse * 0.30)
				rel = rel.rotated(angle)
				if _effect == "gravity_well":
					rel *= 1.0 - delta * (0.020 + impulse * 0.045)
				else:
					rel *= 1.0 + sin(_time + float(u["phase"])) * delta * 0.015
				pos = center + rel
			"hypernova_flow":
				var dir := (pos - _placement_center(Vector2(0.5, 0.55))).normalized()
				pos += dir * delta * (0.22 + speed * 0.22 + impulse * 0.45)
			"skyline_mirage":
				pos.x += delta * (0.035 + speed * 0.035)
				pos.y += sin(_time * 0.5 + float(u["phase"])) * delta * 0.010
			_:
				pos += vel * delta * (0.12 + speed * 0.10 + density * 0.08)
				pos += Vector2(sin(_time + float(u["phase"])), cos(_time * 0.8 + float(u["phase2"]))) * delta * 0.012
		pos.x = wrapf(pos.x, -0.15, 1.15)
		pos.y = wrapf(pos.y, -0.15, 1.15)
		u["pos"] = pos
		_units[i] = u


func _draw() -> void:
	var ems := _ems()
	if ems == null or not bool(ems.get("enabled")) or not bool(ems.call("has_signature_effect")):
		return
	_bounds = _get_bounds_size()
	if _bounds.x <= 1.0 or _bounds.y <= 1.0:
		return
	_draw_morph_wash()
	match _effect:
		"neon_rain":
			_draw_neon_rain()
		"digital_snow":
			_draw_digital_snow()
		"plasma_storm":
			_draw_plasma_storm()
		"quantum_grid":
			_draw_quantum_grid()
		"aurora_drive":
			_draw_aurora_drive()
		"cyber_ocean":
			_draw_cyber_ocean()
		"fractal_space":
			_draw_fractal_space()
		"prism_circuit":
			_draw_prism_circuit()
		"void_pulse":
			_draw_void_pulse()
		"solar_bloom":
			_draw_solar_bloom()
		"lunar_glass":
			_draw_lunar_glass()
		"pixel_nebula":
			_draw_pixel_nebula()
		"thunder_matrix":
			_draw_thunder_matrix()
		"chromatic_rift":
			_draw_chromatic_rift()
		"skyline_mirage":
			_draw_skyline_mirage()
		"crystal_reactor":
			_draw_crystal_reactor()
		"gravity_well":
			_draw_gravity_well()
		"hypernova_flow":
			_draw_hypernova_flow()
		"singularity_bloom":
			_draw_singularity_bloom()
		_:
			_draw_prism_circuit()
	_draw_impulse_accents()


func _draw_morph_wash() -> void:
	var base := _color(0, 0.10 + _energy * 0.09, 0.0)
	var accent := _color(2, 0.07 + _pulse * 0.05, 0.4)
	match _palette_morph:
		"drip_shift":
			draw_rect(Rect2(Vector2.ZERO, _bounds), _color(0, 0.055 + _energy * 0.040, 0.0))
			for i in 8:
				var x := _bounds.x * (0.10 + float(i) * 0.115 + sin(_time * 0.16 + float(i)) * 0.012)
				var y := _bounds.y * (0.16 + fmod(float(i) * 0.137 + _time * 0.018, 0.70))
				var radius := minf(_bounds.x, _bounds.y) * (0.026 + float(i % 3) * 0.006)
				draw_circle(Vector2(x, y), radius, _color(i, 0.020 + _energy * 0.012, float(i) * 0.08))
		"heat_branch", "solar_corona":
			draw_rect(Rect2(Vector2.ZERO, _bounds), Color(0.070, 0.014, 0.010, 0.10 + _energy * 0.06))
			for i in 8:
				var p := _bounds * Vector2(0.24 + float(i % 4) * 0.17 + sin(_time * 0.18 + float(i)) * 0.025, 0.25 + float(i / 4) * 0.34 + cos(_time * 0.16 + float(i)) * 0.035)
				var r := minf(_bounds.x, _bounds.y) * (0.12 + float(i % 3) * 0.035 + _energy * 0.040)
				draw_circle(p, r, _color(i, 0.035 + _energy * 0.032, 0.2))
		"grid_phase":
			draw_rect(Rect2(Vector2.ZERO, _bounds), _color(0, 0.050 + _energy * 0.025, 0.0))
			for i in 8:
				var x := _bounds.x * (0.12 + float(i) * 0.11)
				var y := _bounds.y * (0.16 + fmod(_time * 0.025 + float(i) * 0.09, 0.64))
				var r := minf(_bounds.x, _bounds.y) * (0.045 + _pulse * 0.008)
				_draw_diamond(Vector2(x, y), r, _color(i, 0.020 + _energy * 0.014, 0.1), _color(i + 1, 0.045, 0.25), 1.0)
		"aurora_silk":
			draw_rect(Rect2(Vector2.ZERO, _bounds), _color(1, 0.040 + _energy * 0.020, 0.0))
			for band in 5:
				var points := PackedVector2Array()
				for i in 10:
					var x := float(i) / 9.0 * _bounds.x
					var top := _bounds.y * (0.10 + float(band) * 0.12) + sin(_time * 0.22 + float(i) * 0.55 + float(band)) * _bounds.y * 0.035
					points.append(Vector2(x, top))
				for i in range(9, -1, -1):
					var x2 := float(i) / 9.0 * _bounds.x
					var bottom := _bounds.y * (0.30 + float(band) * 0.12) + sin(_time * 0.20 + float(i) * 0.50 + float(band) + 1.6) * _bounds.y * 0.055
					points.append(Vector2(x2, bottom))
				draw_colored_polygon(points, _color(band, 0.025 + _energy * 0.018, float(band) * 0.11))
		"kaleidoscope":
			draw_rect(Rect2(Vector2.ZERO, _bounds), _color(0, 0.050 + _energy * 0.030, 0.0))
			var center := _bounds * Vector2(0.5, 0.5)
			for i in 10:
				var angle := _time * 0.10 + float(i) / 10.0 * TAU
				var r1 := minf(_bounds.x, _bounds.y) * (0.10 + _pulse * 0.015)
				var r2 := minf(_bounds.x, _bounds.y) * (0.36 + _energy * 0.040)
				var pts := PackedVector2Array([
					center + Vector2(cos(angle - 0.08), sin(angle - 0.08)) * r1,
					center + Vector2(cos(angle), sin(angle)) * r2,
					center + Vector2(cos(angle + 0.08), sin(angle + 0.08)) * r1,
				])
				draw_colored_polygon(pts, _color(i, 0.018 + _energy * 0.015, float(i) * 0.05))
		"prism_split":
			draw_rect(Rect2(Vector2.ZERO, _bounds), _color(0, 0.045 + _energy * 0.025, 0.0))
			for i in 10:
				var center := Vector2(
					_bounds.x * (0.08 + float(i % 5) * 0.20 + sin(_time * 0.15 + float(i)) * 0.012),
					_bounds.y * (0.18 + float(i / 5) * 0.44 + cos(_time * 0.14 + float(i)) * 0.020)
				)
				var size := minf(_bounds.x, _bounds.y) * (0.028 + float(i % 3) * 0.005)
				var angle := float(i) * 0.71 + _time * 0.08
				var pane := PackedVector2Array([
					center + Vector2(-size, -size * 0.55).rotated(angle),
					center + Vector2(size * 0.85, -size * 0.78).rotated(angle),
					center + Vector2(size, size * 0.58).rotated(angle),
					center + Vector2(-size * 0.72, size * 0.72).rotated(angle),
				])
				draw_colored_polygon(pane, _color(i, 0.018 + _energy * 0.012, float(i) * 0.07))
		"pixel_quantize", "nebula_quantize":
			var cell := maxf(20.0, minf(_bounds.x, _bounds.y) * 0.11)
			var columns := int(ceil(_bounds.x / cell))
			var rows := int(ceil(_bounds.y / cell))
			for x in columns:
				for y in rows:
					if (x + y + int(_time * 2.0)) % 3 == 0:
						draw_rect(Rect2(Vector2(x * cell, y * cell), Vector2(cell + 1.0, cell + 1.0)), _color(x + y, 0.018 + _energy * 0.025, float(x) * 0.05))
		"void_invert":
			draw_rect(Rect2(Vector2.ZERO, _bounds), Color(0.0, 0.0, 0.0, 0.18 + _energy * 0.11))
			draw_circle(_bounds * 0.5, minf(_bounds.x, _bounds.y) * (0.18 + _pulse * 0.05), _color(1, 0.035, 0.2))
		"caustic_wave", "horizon_heat":
			for i in 5:
				var y := _bounds.y * (0.18 + float(i) * 0.16 + sin(_time * 0.35 + float(i)) * 0.035)
				draw_line(Vector2(0, y), Vector2(_bounds.x, y + sin(_time + float(i)) * _bounds.y * 0.06), _color(i, 0.035 + _energy * 0.025, float(i) * 0.1), 18.0 + _energy * 12.0)
		_:
			draw_rect(Rect2(Vector2.ZERO, _bounds), base)
			draw_circle(_bounds * Vector2(0.5 + sin(_time * 0.18) * 0.12, 0.48), maxf(_bounds.x, _bounds.y) * 0.35, accent)


func _draw_neon_rain() -> void:
	if not _particles_enabled():
		return
	var hit_y := _bounds.y * 0.82
	for i in min(_active_count, 30):
		var u := _units[i]
		var p: Vector2 = u["pos"]
		var x := p.x * _bounds.x
		var y := p.y * _bounds.y
		var r := 2.6 + float(u["size"]) * 42.0
		var c := _color(i, 0.16 + _energy * 0.13, float(u["phase"]))
		draw_circle(Vector2(x, y - r * 0.35), r * 1.26, _color(i, 0.032 + _energy * 0.022, float(u["phase"])))
		draw_circle(Vector2(x, y), r * 0.64, c)
		draw_colored_polygon(PackedVector2Array([
			Vector2(x, y - r * 1.25),
			Vector2(x + r * 0.58, y - r * 0.12),
			Vector2(x, y + r * 0.78),
			Vector2(x - r * 0.58, y - r * 0.12),
		]), _color(i + 1, 0.14 + _energy * 0.07, 0.15))
		if abs(y - hit_y) < 28.0 + _energy * 18.0:
			var splash := clampf(1.0 - abs(y - hit_y) / 48.0, 0.0, 1.0)
			draw_arc(Vector2(x, hit_y + 4.0), 8.0 + splash * 22.0, PI * 1.06, PI * 1.94, 16, _color(i + 2, 0.08 * splash, 0.2), 1.4 + splash * 1.8)
			for d in 3:
				var dx := (float(d) - 1.0) * (7.0 + r)
				draw_circle(Vector2(x + dx, hit_y + 2.0 - splash * 5.0), 1.6 + splash * 2.0, _color(i + d, 0.12 * splash, 0.3))


func _draw_digital_snow() -> void:
	for y in range(0, int(_bounds.y), 28):
		draw_line(Vector2(0, y), Vector2(_bounds.x, y), _color(y, 0.025 + _energy * 0.020, 0.0), 1.0)
	if not _particles_enabled():
		return
	for i in _active_count:
		var u := _units[i]
		var p: Vector2 = u["pos"] * _bounds
		var s := floorf(4.0 + float(u["size"]) * 80.0)
		p = Vector2(floorf(p.x / s) * s, floorf(p.y / s) * s)
		draw_rect(Rect2(p, Vector2(s, s)), _color(i, 0.10 + _energy * 0.08, 0.0))


func _draw_plasma_storm() -> void:
	var count: int = mini(_active_count, 26)
	for i in count:
		var u := _units[i]
		var p: Vector2 = u["pos"] * _bounds
		var r := minf(_bounds.x, _bounds.y) * (0.040 + float(u["size"]) * 0.80 + _energy * 0.018)
		var wobble := Vector2(sin(_time * 1.3 + float(u["phase"])), cos(_time * 1.1 + float(u["phase2"]))) * r * 0.16
		draw_circle(p, r * 1.35, _color(i, 0.030 + _energy * 0.030, 0.0))
		draw_circle(p + wobble, r * 0.86, _color(i + 1, 0.075 + _energy * 0.060, 0.18))
		draw_circle(p - wobble * 0.65, r * 0.42, _color(i + 2, 0.105 + _energy * 0.075, 0.34))
		draw_arc(p, r * (1.05 + _pulse * 0.24), _time * 0.55 + float(u["phase"]), _time * 0.55 + float(u["phase"]) + PI * 1.35, 28, _color(i + 3, 0.09 + _energy * 0.05, 0.50), 1.3 + _energy * 1.7)


func _draw_quantum_grid() -> void:
	var spacing := maxf(42.0, minf(_bounds.x, _bounds.y) * 0.105)
	for i in min(_active_count, 34):
		var u := _units[i]
		var p: Vector2 = u["pos"] * _bounds
		p = Vector2(round(p.x / spacing) * spacing, round(p.y / spacing) * spacing)
		var phase := sin(_time * 1.6 + float(u["phase"])) * 0.5 + 0.5
		var r := 5.0 + phase * 7.0 + _energy * 6.0
		if i % 3 == 0:
			_draw_diamond(p, r * (1.5 + _pulse * 0.4), _color(i, 0.018 + _energy * 0.012, 0.1), _color(i + 1, 0.095 + _energy * 0.050, 0.22), 1.3)
		else:
			draw_circle(p, r * 0.42, _color(i, 0.13 + _energy * 0.07, 0.1))
		if i % 4 == 0:
			var target := Vector2(_bounds.x * 0.5, _bounds.y * (0.40 + sin(_time * 0.20) * 0.04))
			var mid := p.lerp(target, 0.42 + _pulse * 0.20)
			draw_line(p, mid, _color(i + 2, 0.050 + _energy * 0.025, 0.2), 1.2)


func _draw_aurora_drive() -> void:
	for curtain in 6:
		var top_points: Array[Vector2] = []
		var bottom_points: Array[Vector2] = []
		for i in 12:
			var x := float(i) / 11.0 * _bounds.x
			var fold := sin(_time * (0.20 + float(curtain) * 0.018) + float(i) * 0.70 + float(curtain))
			var top := _bounds.y * (0.04 + float(curtain) * 0.115) + fold * _bounds.y * (0.035 + _energy * 0.018)
			var bottom := top + _bounds.y * (0.20 + _energy * 0.050) + cos(_time * 0.17 + float(i) * 0.50 + float(curtain)) * _bounds.y * 0.035
			top_points.append(Vector2(x, top))
			bottom_points.append(Vector2(x, bottom))
		var sheet := PackedVector2Array()
		for p in top_points:
			sheet.append(p)
		for i in range(bottom_points.size() - 1, -1, -1):
			sheet.append(bottom_points[i])
		draw_colored_polygon(sheet, _color(curtain, 0.040 + _energy * 0.030, float(curtain) * 0.09))
		draw_polyline(PackedVector2Array(top_points), _color(curtain + 1, 0.045 + _pulse * 0.025, 0.18), 1.6 + _energy * 1.4, true)


func _draw_cyber_ocean() -> void:
	var impulse := _impulse_energy_for_hits()
	var wave_energy := clampf(_energy * 0.68 + impulse * 0.42, 0.0, 1.0)
	var wave_activity := 0.20 + wave_energy * 0.80
	var tide_speed := _cyber_ocean_tide_speed()
	var tide_shift := _time * tide_speed
	draw_rect(Rect2(Vector2.ZERO, _bounds), Color(0.005, 0.025, 0.055, 0.060 + wave_activity * 0.035))
	for wave in 6:
		var points := PackedVector2Array()
		for i in 28:
			var x := float(i) / 27.0 * _bounds.x
			var wave_idx := float(wave) / 5.0
			var crest := sin(tide_shift * (0.42 + wave_idx) + float(i) * 0.58) * (0.018 + wave_activity * 0.028 + impulse * 0.042)
			var phase_basis := float(wave)
			if _units.size() > i:
				phase_basis = float(_units[i]["phase"])
			var harmonic := sin(tide_shift * (0.16 + wave_idx) + float(i) * 0.19 + phase_basis) * (0.006 + wave_activity * 0.014)
			var hit_ripple := 0.0
			for imp in _impulses:
				if not _is_hit_impulse(imp):
					continue
				var ttl := maxf(0.001, float(imp.get("ttl", 1.0)))
				var t := clampf(float(imp.get("age", 0.0)) / ttl, 0.0, 1.0)
				var lane := int(imp.get("lane", 0)) % 5
				var hit_x := _bounds.x * (0.15 + float(lane) * 0.17)
				var distance := absf(x - hit_x)
				var falloff := clampf(1.0 - distance / (_bounds.x * (0.17 + t * 0.20)), 0.0, 1.0)
				hit_ripple += sin(distance * 0.032 - t * TAU * 1.45 + float(wave) * 0.55) * falloff * float(imp.get("strength", 0.0)) * (1.0 - t) * 0.042
			var rise := fmod(tide_shift * 0.08 + float(wave) * 0.18 + float(i) * 0.03, 1.0)
			var y := _bounds.y * (0.25 + wave_idx * 0.11 + rise * 0.024) + (crest + harmonic + hit_ripple) * _bounds.y
			points.append(Vector2(x, y))
		draw_polyline(points, _color(wave, 0.075 + wave_activity * 0.060, 0.0), 1.8 + wave_activity * 3.5, true)
	if _particles_enabled():
		for i in min(_active_count, 8):
			var p: Vector2 = _units[i]["pos"] * _bounds
			var foam_y := _bounds.y * (0.30 + float(i % 5) * 0.105 + sin(_time * 0.18 + float(_units[i]["phase"])) * 0.018)
			var foam_x := wrapf(p.x + sin(_time * 0.20 + float(_units[i]["phase2"])) * 16.0, 0.0, _bounds.x)
			var foam_len := 18.0 + float(_units[i]["size"]) * 70.0 + impulse * 20.0
			draw_line(Vector2(foam_x - foam_len * 0.5, foam_y), Vector2(foam_x + foam_len * 0.5, foam_y + sin(_time * 0.16 + float(i)) * 5.0), _color(i, 0.045 + impulse * 0.06, 0.16), 1.0 + impulse * 1.2)
		for imp in _impulses:
			if not _is_hit_impulse(imp):
				continue
			var ttl := maxf(0.001, float(imp.get("ttl", 1.0)))
			var t := clampf(float(imp.get("age", 0.0)) / ttl, 0.0, 1.0)
			var lane := int(imp.get("lane", 0)) % 5
			var strength := clampf(float(imp.get("strength", 0.0)), 0.0, 1.0)
			var center := Vector2(_bounds.x * (0.15 + float(lane) * 0.17), clampf(float(imp.get("y_norm", 0.78)), 0.20, 0.82) * _bounds.y)
			var spray_color: Color = imp.get("color", _color(lane, 1.0, 0.0))
			spray_color.a = (1.0 - t) * (0.08 + strength * 0.16)
			for ray in 5:
				var angle := -PI * 0.92 + float(ray) * PI * 0.13
				var length := _bounds.y * (0.035 + strength * 0.050) * (1.0 + t)
				var end := center + Vector2(cos(angle), sin(angle)) * length
				draw_line(center.lerp(end, 0.22), end, spray_color, 1.1 + strength * 1.5)


func _draw_fractal_space() -> void:
	for i in min(_active_count, 12):
		var u := _units[i]
		var p: Vector2 = u["pos"] * _bounds
		var r := (18.0 + float(u["size"]) * 210.0) * (0.80 + _energy * 0.40)
		var sides: int = 5 + (i % 3)
		for ring in 4:
			var rr := r / float(ring + 1)
			var rot := _time * (0.18 + float(ring) * 0.045) + float(u["phase"]) + float(ring)
			_draw_regular_polygon(p, rr, sides + ring, rot, _color(i + ring, 0.018 + _energy * 0.012, float(ring) * 0.1))
			_draw_polygon_outline(p, rr, sides + ring, -rot * 0.7, _color(i + ring + 2, 0.070 + _energy * 0.030, 0.25), 1.1)
		for spoke in 6:
			var angle := float(spoke) / 6.0 * TAU + _time * 0.12 + float(u["phase"])
			var satellite := p + Vector2(cos(angle), sin(angle)) * r * 0.82
			draw_circle(satellite, maxf(1.8, r * 0.045), _color(i + spoke, 0.080 + _energy * 0.050, 0.12))


func _draw_prism_circuit() -> void:
	for i in min(_active_count, 20):
		var p: Vector2 = _units[i]["pos"] * _bounds
		var s := 10.0 + float(_units[i]["size"]) * 72.0
		var skew := Vector2(s * 0.34, -s * 0.18)
		var pane := PackedVector2Array([
			p + Vector2(-s, -s * 0.42) + skew,
			p + Vector2(s * 0.85, -s * 0.64),
			p + Vector2(s, s * 0.46) - skew * 0.4,
			p + Vector2(-s * 0.78, s * 0.68),
		])
		draw_colored_polygon(pane, _color(i, 0.035 + _energy * 0.030, 0.0))
		draw_polyline(pane, _color(i + 1, 0.080 + _energy * 0.035, 0.18), 1.0 + _energy * 1.1, true)
		if i % 4 == 0:
			var elbow := Vector2(p.x + ((1.0 if i % 8 == 0 else -1.0) * s * 0.88), p.y)
			var end := Vector2(elbow.x, p.y + ((1.0 if i % 3 == 0 else -1.0) * s * 0.68))
			draw_line(p, elbow, _color(i + 2, 0.105, 0.26), 1.6)
			draw_line(elbow, end, _color(i + 3, 0.090, 0.36), 1.6)
			var t := fmod(_time * 0.70 + float(i) * 0.11, 1.0)
			var pulse := p.lerp(elbow, minf(t * 2.0, 1.0)) if t < 0.5 else elbow.lerp(end, (t - 0.5) * 2.0)
			draw_circle(pulse, 2.4 + _energy * 2.6, _color(i + 4, 0.18, 0.44))


func _draw_void_pulse() -> void:
	var center := _bounds * _placement_center(Vector2(0.5, 0.52))
	draw_circle(center, maxf(_bounds.x, _bounds.y) * (0.16 + _energy * 0.05), Color(0, 0, 0, 0.26))
	for i in 8:
		var r := minf(_bounds.x, _bounds.y) * (0.10 + float(i) * 0.055 + fmod(_time * 0.035 + float(i) * 0.04, 0.05))
		draw_arc(center, r, 0.0, TAU, 72, _color(i, 0.05 + _energy * 0.035, 0.0), 2.0 + _energy * 2.0)


func _draw_solar_bloom() -> void:
	var center := _bounds * _placement_center(Vector2(0.50, 0.54))
	draw_circle(center, minf(_bounds.x, _bounds.y) * (0.16 + _energy * 0.05), _color(2, 0.040 + _energy * 0.030, 0.2))
	for i in 18:
		var angle := float(i) / 32.0 * TAU + sin(_time * 0.35) * 0.08 + _placement_phase
		var inner := minf(_bounds.x, _bounds.y) * (0.10 + _pulse * 0.018)
		var outer := minf(_bounds.x, _bounds.y) * (0.20 + _energy * 0.13 + float(i % 4) * 0.012)
		var width := 0.070 + _energy * 0.020
		var pts := PackedVector2Array([
			center + Vector2(cos(angle - width), sin(angle - width)) * inner,
			center + Vector2(cos(angle), sin(angle)) * outer,
			center + Vector2(cos(angle + width), sin(angle + width)) * inner,
			center + Vector2(cos(angle + PI), sin(angle + PI)) * inner * 0.20,
		])
		draw_colored_polygon(pts, _color(i, 0.045 + _energy * 0.055, 0.1))
	for i in min(_active_count, 28):
		var p: Vector2 = _units[i]["pos"] * _bounds
		var dist := p.distance_to(center)
		if dist < minf(_bounds.x, _bounds.y) * 0.42:
			draw_circle(p, 1.8 + float(i % 3) * 1.2 + _energy * 2.2, _color(i + 5, 0.14 + _energy * 0.08, 0.22))
	draw_circle(center, minf(_bounds.x, _bounds.y) * (0.065 + _energy * 0.045), _color(1, 0.18 + _energy * 0.13, 0.0))
	draw_circle(center, minf(_bounds.x, _bounds.y) * (0.026 + _pulse * 0.012), Color(1.0, 0.96, 0.72, 0.28 + _energy * 0.22))


func _draw_lunar_glass() -> void:
	var impulse := _impulse_energy_for_hits()
	var glass_tone := clampf(_energy * 0.62 + impulse * 0.48, 0.0, 1.0)
	var moon_center := _bounds * _placement_center(Vector2(0.50, 0.50))
	var halo_radius := minf(_bounds.x, _bounds.y) * (0.38 + _energy * 0.10)
	draw_rect(Rect2(Vector2.ZERO, _bounds), Color(0.035, 0.047, 0.075, 0.14 + glass_tone * 0.06))
	draw_circle(moon_center, halo_radius * 1.10, Color(0.50, 0.63, 0.88, 0.028 + glass_tone * 0.030))
	draw_circle(moon_center, halo_radius * 0.72, Color(0.70, 0.82, 1.0, 0.060 + glass_tone * 0.045))
	draw_circle(moon_center + Vector2(halo_radius * 0.13, -halo_radius * 0.08), halo_radius * 0.50, Color(0.88, 0.94, 1.0, 0.030 + glass_tone * 0.034))
	for pane in 7:
		var y_top := _bounds.y * (0.04 + float(pane) * 0.135)
		var skew := sin(float(pane) * 1.17 + _time * 0.035) * _bounds.x * 0.045
		var sheet := PackedVector2Array([
			Vector2(skew - _bounds.x * 0.06, y_top),
			Vector2(_bounds.x * (0.38 + float(pane % 3) * 0.11) + skew, y_top + _bounds.y * 0.060),
			Vector2(_bounds.x * 1.06 + skew * 0.35, y_top + _bounds.y * (0.10 + float(pane % 2) * 0.030)),
			Vector2(_bounds.x * (0.64 - float(pane % 2) * 0.12) - skew, y_top + _bounds.y * 0.205),
			Vector2(-_bounds.x * 0.04 - skew * 0.20, y_top + _bounds.y * 0.145),
		])
		draw_colored_polygon(sheet, Color(0.54, 0.68, 0.96, 0.012 + glass_tone * 0.012))
		draw_polyline(sheet, Color(0.84, 0.93, 1.0, 0.045 + glass_tone * 0.038), 0.9 + glass_tone * 0.8, true)
	for i in min(_active_count, 18):
		var base: Vector2 = _units[i]["pos"] * _bounds
		var p := Vector2(
			base.x + sin(_time * 0.045 + float(_units[i]["phase"])) * (5.0 + impulse * 10.0),
			base.y + cos(_time * 0.040 + float(_units[i]["phase2"])) * (5.0 + impulse * 8.0)
		)
		var crack_radius := 18.0 + float(_units[i]["size"]) * 120.0 + impulse * 18.0
		var crack_color := Color(0.88, 0.96, 1.0, 0.045 + glass_tone * 0.075 + impulse * 0.07)
		for branch in 3 + (i % 3):
			var angle := float(_units[i]["phase"]) + float(branch) * TAU / float(3 + (i % 3)) + sin(_time * 0.06 + float(i)) * 0.08
			var kink := p + Vector2(cos(angle + 0.18), sin(angle + 0.18)) * crack_radius * 0.42
			var end := p + Vector2(cos(angle), sin(angle)) * crack_radius
			draw_line(p, kink, crack_color, 0.9 + impulse * 0.7)
			draw_line(kink, end, Color(crack_color.r, crack_color.g, crack_color.b, crack_color.a * 0.62), 0.7 + impulse * 0.5)
	for imp in _impulses:
		if not _is_hit_impulse(imp):
			continue
		var ttl := maxf(0.001, float(imp.get("ttl", 1.0)))
		var t := clampf(float(imp.get("age", 0.0)) / ttl, 0.0, 1.0)
		var lane := int(imp.get("lane", 0)) % 5
		var strength := clampf(float(imp.get("strength", 0.0)), 0.0, 1.0)
		var center := Vector2(_bounds.x * (0.15 + float(lane) * 0.17), clampf(float(imp.get("y_norm", 0.76)), 0.18, 0.84) * _bounds.y)
		var burst := minf(_bounds.x, _bounds.y) * (0.045 + strength * 0.060 + t * 0.080)
		var hit_color: Color = imp.get("color", _color(lane, 1.0, 0.0))
		hit_color = hit_color.lerp(Color(0.90, 0.96, 1.0, 1.0), 0.65)
		hit_color.a = (1.0 - t) * (0.18 + strength * 0.22)
		for shard in 11:
			var angle := float(shard) / 11.0 * TAU + float(lane) * 0.37
			var inner := center + Vector2(cos(angle), sin(angle)) * burst * 0.18
			var outer := center + Vector2(cos(angle + sin(float(shard)) * 0.16), sin(angle + sin(float(shard)) * 0.16)) * burst
			draw_line(inner, outer, hit_color, 1.0 + strength * 1.3)
			if shard % 3 == 0:
				var side := burst * (0.12 + float(shard % 2) * 0.04)
				var shard_pts := PackedVector2Array([
					outer,
					outer + Vector2(cos(angle + 0.58), sin(angle + 0.58)) * side,
					outer + Vector2(cos(angle - 0.44), sin(angle - 0.44)) * side * 0.72,
				])
				draw_colored_polygon(shard_pts, Color(hit_color.r, hit_color.g, hit_color.b, hit_color.a * 0.28))


func _draw_pixel_nebula() -> void:
	var cell := maxf(10.0, minf(_bounds.x, _bounds.y) * 0.055)
	for i in min(_active_count, 46):
		var p: Vector2 = _units[i]["pos"] * _bounds
		p = Vector2(floorf(p.x / cell) * cell, floorf(p.y / cell) * cell)
		var s := cell * (1.0 + float(i % 3))
		draw_rect(Rect2(p, Vector2(s, s)), _color(i, 0.045 + _energy * 0.065, 0.0))


func _draw_thunder_matrix() -> void:
	var impulse := _impulse_energy()
	var hit_impulse := _impulse_energy_for_hits()
	var drive := clampf(0.16 + _energy * 0.50 + impulse * 0.38 + hit_impulse * 0.55, 0.0, 1.0)
	var center := _bounds * _placement_center(Vector2(0.50, 0.52))
	draw_rect(Rect2(Vector2.ZERO, _bounds), Color(0.004, 0.007, 0.026, 0.115 + drive * 0.055))
	draw_circle(center, minf(_bounds.x, _bounds.y) * (0.24 + hit_impulse * 0.10), Color(0.08, 0.20, 0.22, 0.025 + drive * 0.035))
	for ring in 4:
		var ring_radius := minf(_bounds.x, _bounds.y) * (0.13 + float(ring) * 0.075 + hit_impulse * 0.035)
		var ring_center := center + Vector2(sin(_time * 0.10 + float(ring)), cos(_time * 0.08 + float(ring) * 1.7)) * ring_radius * 0.12
		var ring_color := _color(ring + 2, 0.024 + drive * 0.030 + hit_impulse * 0.070, 0.18)
		draw_arc(ring_center, ring_radius, _time * 0.12 + float(ring) * 0.6, _time * 0.12 + float(ring) * 0.6 + PI * 1.18, 28, ring_color, 0.9 + drive * 1.0)
	for i in min(_active_count, 22):
		var u := _units[i]
		var p: Vector2 = u["pos"] * _bounds
		var charge := sin(_time * (0.34 + float(u["speed"]) * 0.08) + float(u["phase"])) * 0.5 + 0.5
		var radius := minf(_bounds.x, _bounds.y) * (0.020 + float(u["size"]) * 0.42 + charge * 0.010 + hit_impulse * 0.020)
		var cell_color := _color(i + 4, 0.040 + drive * 0.065 + charge * 0.045 + hit_impulse * 0.095, 0.08)
		if i % 2 == 0:
			_draw_diamond(p, radius, Color(cell_color.r, cell_color.g, cell_color.b, cell_color.a * 0.14), cell_color, 1.0 + drive * 1.1)
		else:
			_draw_polygon_outline(p, radius, 6, float(u["phase"]) + _time * 0.05, cell_color, 0.9 + drive * 0.9)
		if charge > 0.42 or hit_impulse > 0.08:
			var branch_count: int = 2 + (i % 3)
			for branch in branch_count:
				var angle := float(branch) / float(branch_count) * TAU + float(u["phase2"]) * 0.22
				var length := radius * (1.55 + drive * 1.25 + hit_impulse * 1.75)
				var branch_color := Color(cell_color.r, cell_color.g, cell_color.b, cell_color.a * (0.42 + hit_impulse * 0.58))
				var end := _draw_thunder_branch(p, angle, length, 4, branch_color, 0.8 + drive * 0.9 + hit_impulse * 1.4, float(i) * 0.71 + float(branch))
				if branch == 0:
					draw_circle(end, 1.4 + drive * 1.9 + hit_impulse * 3.4, Color(cell_color.r, cell_color.g, cell_color.b, cell_color.a * 0.82))
	for imp in _impulses:
		var ttl := maxf(0.001, float(imp.get("ttl", 1.0)))
		var t := clampf(float(imp.get("age", 0.0)) / ttl, 0.0, 1.0)
		var strength := clampf(float(imp.get("strength", 0.0)), 0.0, 1.0)
		var lane := int(imp.get("lane", 0)) % 5
		var impact := Vector2(_bounds.x * (0.15 + float(lane) * 0.17), clampf(float(imp.get("y_norm", 0.78)), 0.12, 0.88) * _bounds.y)
		var hit_scale := 1.0 if _is_hit_impulse(imp) else 0.45
		var surge: Color = imp.get("color", _color(lane, 1.0, 0.0))
		surge = surge.lerp(Color(0.80, 1.0, 1.0, 1.0), 0.38)
		surge.a = (1.0 - t) * (0.16 + strength * 0.30) * hit_scale
		var burst_radius := minf(_bounds.x, _bounds.y) * (0.030 + strength * 0.050 + t * 0.060)
		_draw_diamond(impact, burst_radius * 0.55, Color(surge.r, surge.g, surge.b, surge.a * 0.12), surge, 1.2 + strength * 1.4)
		draw_arc(impact, burst_radius, 0.0, TAU, 28, Color(surge.r, surge.g, surge.b, surge.a * 0.55), 1.0 + strength * 1.6)
		for branch in 7:
			var angle := float(branch) / 7.0 * TAU + float(lane) * 0.31 + sin(float(branch) + t * TAU) * 0.12
			var length := minf(_bounds.x, _bounds.y) * (0.060 + strength * 0.110) * (1.0 - t * 0.25)
			var end := _draw_thunder_branch(impact, angle, length, 5, surge, 1.0 + strength * 2.0, float(lane) + float(branch) * 0.83)
			if branch % 2 == 0:
				draw_circle(end, 1.2 + strength * 2.2, Color(surge.r, surge.g, surge.b, surge.a * 0.70))


func _draw_thunder_branch(origin: Vector2, angle: float, length: float, steps: int, color: Color, width: float, seed: float) -> Vector2:
	if length <= 1.0 or color.a <= 0.0:
		return origin
	var step_count := maxi(2, steps)
	var tangent := Vector2(cos(angle), sin(angle))
	var normal := Vector2(-tangent.y, tangent.x)
	var points := PackedVector2Array()
	points.append(origin)
	for step in range(1, step_count + 1):
		var progress := float(step) / float(step_count)
		var kink := sin(seed + float(step) * 1.37 + _time * 0.42) * length * 0.13 * (1.0 - progress * 0.35)
		points.append(origin + tangent * length * progress + normal * kink)
	draw_polyline(points, color, width, true)
	return points[points.size() - 1]


func _draw_chromatic_rift() -> void:
	for i in 7:
		var x := _bounds.x * (0.18 + float(i) * 0.11 + _placement_offset.x * 0.45 + sin(_time * 0.22 + float(i) + _placement_phase) * 0.025)
		var width := 4.0 + _energy * 8.0
		draw_line(Vector2(x - width, 0), Vector2(x + sin(_time + float(i)) * 44.0, _bounds.y), _color(i, 0.12 + _energy * 0.08, 0.0), width)
		draw_line(Vector2(x + width, 0), Vector2(x - sin(_time + float(i)) * 36.0, _bounds.y), _color(i + 2, 0.10 + _energy * 0.07, 0.5), width)


func _draw_skyline_mirage() -> void:
	var horizon := _bounds.y * (0.58 + sin(_time * 0.18) * 0.025)
	for i in 9:
		var y := horizon + float(i) * 13.0
		draw_line(Vector2(0, y), Vector2(_bounds.x, y + sin(_time * 0.4 + float(i)) * 8.0), _color(i, 0.055 + _energy * 0.035, 0.0), 3.0)
	for i in 12:
		var w := _bounds.x * (0.025 + float((i % 4) + 1) * 0.012)
		var h := _bounds.y * (0.08 + float((i % 5) + 1) * 0.025)
		var x := wrapf(_time * (8.0 + float(i)) + float(i) * _bounds.x * 0.13, -w, _bounds.x)
		draw_rect(Rect2(Vector2(x, horizon - h), Vector2(w, h)), Color(0.0, 0.0, 0.0, 0.20 + _energy * 0.12))


func _draw_crystal_reactor() -> void:
	var center := _bounds * _placement_center(Vector2(0.50, 0.52))
	draw_circle(center, minf(_bounds.x, _bounds.y) * (0.06 + _energy * 0.04), _color(0, 0.18 + _energy * 0.12, 0.0))
	for i in min(_active_count, 30):
		var angle := float(i) / 30.0 * TAU + _time * 0.22 + _placement_phase
		var r := minf(_bounds.x, _bounds.y) * (0.16 + float(i % 5) * 0.035)
		var p := center + Vector2(cos(angle), sin(angle)) * r
		_draw_polygon_outline(p, 10.0 + float(i % 4) * 4.0, 3, angle, _color(i, 0.09 + _energy * 0.07, 0.0), 1.8)
	draw_arc(center, minf(_bounds.x, _bounds.y) * (0.20 + _pulse * 0.05), 0.0, TAU, 64, _color(3, 0.12, 0.2), 3.0)


func _draw_gravity_well() -> void:
	var center := _bounds * _placement_center(Vector2(0.50, 0.53))
	for i in 9:
		draw_arc(center, minf(_bounds.x, _bounds.y) * (0.08 + float(i) * 0.045), _time * 0.15 + float(i), TAU * 0.72 + _time * 0.15 + float(i), 54, _color(i, 0.055 + _energy * 0.035, 0.0), 2.0)
	if _particles_enabled():
		for i in min(_active_count, 38):
			var p: Vector2 = _units[i]["pos"] * _bounds
			draw_circle(p, 2.0 + float(i % 4), _color(i, 0.13 + _energy * 0.08, 0.0))


func _draw_hypernova_flow() -> void:
	var center := _bounds * _placement_center(Vector2(0.5, 0.55))
	for i in min(_active_count, 54):
		var p: Vector2 = _units[i]["pos"] * _bounds
		var dir := (p - center).normalized()
		var tail := p - dir * (24.0 + _energy * 95.0)
		draw_line(tail, p, _color(i, 0.12 + _energy * 0.12, 0.2), 1.5 + _energy * 2.6)


func _draw_singularity_bloom() -> void:
	var center := _bounds * _placement_center(Vector2(0.5, 0.52))
	draw_circle(center, minf(_bounds.x, _bounds.y) * (0.07 + _energy * 0.05), _color(1, 0.20 + _energy * 0.12, 0.0))
	for i in 12:
		var r := minf(_bounds.x, _bounds.y) * (0.10 + float(i) * 0.035 + _pulse * 0.015)
		draw_arc(center, r, _time * (0.15 + float(i) * 0.01), TAU + _time * (0.15 + float(i) * 0.01), 72, _color(i, 0.055 + _energy * 0.045, 0.15), 2.0 + _energy * 2.0)
	for i in min(_active_count, 28):
		var p: Vector2 = _units[i]["pos"] * _bounds
		draw_line(p, center, _color(i, 0.035 + _energy * 0.030, 0.0), 1.0)


func _draw_impulse_accents() -> void:
	for imp in _impulses:
		var ttl := maxf(0.001, float(imp.get("ttl", 1.0)))
		var t := clampf(float(imp.get("age", 0.0)) / ttl, 0.0, 1.0)
		var strength := clampf(float(imp.get("strength", 0.0)), 0.0, 1.0)
		var y := float(imp.get("y_norm", 0.82)) * _bounds.y
		var c: Color = imp.get("color", _color(0, 1.0, 0.0))
		c.a = (1.0 - t) * (0.10 + strength * 0.18)
		match _reaction_model:
			"plasma_strike":
				var center := Vector2(_bounds.x * (0.18 + float(int(imp.get("lane", 0)) % 5) * 0.16), y)
				draw_circle(center, 22.0 + t * 92.0 * strength, c)
				draw_arc(center, 32.0 + t * 120.0 * strength, 0.0, TAU, 32, c, 2.0 + strength * 2.5)
			"node_collapse":
				var center := Vector2(_bounds.x * (0.18 + float(int(imp.get("lane", 0)) % 5) * 0.16), y)
				_draw_diamond(center, 22.0 + (1.0 - t) * 52.0 * strength, Color(c.r, c.g, c.b, c.a * 0.22), c, 2.2)
			"curtain_breathe":
				var width := _bounds.x * (0.10 + strength * 0.08)
				draw_colored_polygon(PackedVector2Array([
					Vector2(_bounds.x * 0.5 - width, 0.0),
					Vector2(_bounds.x * 0.5 + width, 0.0),
					Vector2(_bounds.x * 0.5 + width * (1.6 + t), _bounds.y),
					Vector2(_bounds.x * 0.5 - width * (1.6 + t), _bounds.y),
				]), Color(c.r, c.g, c.b, c.a * 0.55))
			"fractal_spin":
				var center := Vector2(_bounds.x * (0.18 + float(int(imp.get("lane", 0)) % 5) * 0.16), y)
				for ring in 4:
					_draw_polygon_outline(center, 14.0 + t * 96.0 * strength / float(ring + 1), 5 + ring, _time * 0.8 + float(ring), c, 1.4)
			"trace_pulse":
				var x := _bounds.x * (0.18 + float(int(imp.get("lane", 0)) % 5) * 0.16)
				var elbow := Vector2(x + _bounds.x * 0.10, y)
				var end := Vector2(elbow.x, y - _bounds.y * 0.16 * strength)
				draw_line(Vector2(x, y), elbow, c, 2.0 + strength * 2.0)
				draw_line(elbow, end, c, 2.0 + strength * 2.0)
				draw_circle(elbow.lerp(end, t), 5.0 + strength * 6.0, c)
			"flare_burst":
				var center := _bounds * Vector2(0.5, 0.54)
				draw_circle(center, minf(_bounds.x, _bounds.y) * (0.12 + t * 0.24 * strength), c)
				draw_arc(center, minf(_bounds.x, _bounds.y) * (0.18 + t * 0.22), 0.0, TAU, 64, c, 2.0 + strength * 3.0)
			"sonar_burst":
				draw_arc(Vector2(_bounds.x * 0.5, y), _bounds.x * (0.08 + t * 0.42), 0.0, TAU, 64, c, 3.0)
			"rain_splash":
				var x := _bounds.x * (0.18 + float(int(imp.get("lane", 0)) % 5) * 0.16)
				draw_arc(Vector2(x, y + 6.0), 16.0 + t * 52.0 * strength, PI * 1.02, PI * 1.98, 24, c, 2.0 + strength * 2.0)
				for d in 5:
					var angle := PI + (float(d) / 4.0) * PI
					draw_circle(Vector2(x + cos(angle) * (14.0 + t * 48.0), y + sin(angle) * (8.0 + t * 20.0)), 2.0 + strength * 3.0, c)
			"glass_chime":
				var lane := int(imp.get("lane", 0)) % 5
				var center := Vector2(_bounds.x * (0.14 + float(lane) * 0.18), y)
				var arc_radius := minf(_bounds.x, _bounds.y) * (0.03 + t * 0.04 + strength * 0.10)
				draw_arc(center, arc_radius, -PI * 0.55, PI * 0.55, 14, c, 1.6 + strength * 2.2)
				draw_arc(center + Vector2(_bounds.x * 0.02, _bounds.y * 0.01), arc_radius * 0.62, 0.2, PI * 0.95, 12, c, 1.0 + strength * 1.6)
			"bolt_chain":
				var lane := int(imp.get("lane", 0)) % 5
				var x_base := _bounds.x * (0.15 + float(lane) * 0.17)
				var origin := Vector2(x_base, clampf(y, _bounds.y * 0.18, _bounds.y * 0.82))
				var chain_seed := float(int(imp.get("lane", 0))) * 0.73 + float(_impulses.size()) * 0.19
				var chain := origin
				for segment in 5:
					var segment_t := float(segment + 1) / 5.0
					var reach := _bounds.y * (0.030 + strength * 0.045) * segment_t
					var side := sin(chain_seed + float(segment) * 1.35) * _bounds.x * (0.020 + strength * 0.026)
					var next := Vector2(x_base + side, origin.y - reach)
					var segment_color := Color(c.r, c.g, c.b, c.a * (1.0 - segment_t * 0.38))
					draw_line(chain, next, segment_color, 1.1 + strength * 2.2)
					chain = next
				draw_arc(origin, _bounds.x * (0.020 + t * 0.055 + strength * 0.020), 0.0, TAU, 24, Color(c.r, c.g, c.b, c.a * 0.65), 1.0 + strength * 1.8)
			"snow_scatter", "pixel_pop":
				draw_line(Vector2(0, y), Vector2(_bounds.x, y), c, 2.0 + strength * 6.0)
			"event_horizon", "gravity_ring", "inward_pull":
				draw_arc(_bounds * 0.5, minf(_bounds.x, _bounds.y) * (0.12 + t * 0.36), 0.0, TAU, 72, c, 3.0 + strength * 3.0)
			_:
				draw_circle(Vector2(_bounds.x * (0.18 + float(int(imp.get("lane", 0)) % 5) * 0.16), y), 24.0 + t * 120.0 * strength, c)


func _draw_polygon_outline(center: Vector2, radius: float, sides: int, rotation: float, color: Color, width: float) -> void:
	var pts := PackedVector2Array()
	for i in sides:
		var angle := rotation + float(i) / float(sides) * TAU
		pts.append(center + Vector2(cos(angle), sin(angle)) * radius)
	for i in sides:
		draw_line(pts[i], pts[(i + 1) % sides], color, width)


func _draw_regular_polygon(center: Vector2, radius: float, sides: int, rotation: float, color: Color) -> void:
	if sides < 3:
		return
	var pts := PackedVector2Array()
	for i in sides:
		var angle := rotation + float(i) / float(sides) * TAU
		pts.append(center + Vector2(cos(angle), sin(angle)) * radius)
	draw_colored_polygon(pts, color)


func _draw_diamond(center: Vector2, radius: float, fill_color: Color, outline_color: Color, width: float) -> void:
	var pts := PackedVector2Array([
		center + Vector2(0.0, -radius),
		center + Vector2(radius * 1.18, 0.0),
		center + Vector2(0.0, radius),
		center + Vector2(-radius * 1.18, 0.0),
	])
	if fill_color.a > 0.0:
		draw_colored_polygon(pts, fill_color)
	if outline_color.a > 0.0:
		draw_polyline(pts, outline_color, width, true)


func _color(index: int, alpha: float, phase_offset: float = 0.0) -> Color:
	var colors: Array = []
	var ems := _ems()
	if ems != null:
		colors = ems.call("get_palette_colors")
	if colors.is_empty():
		return Color(1, 1, 1, alpha)
	var idx := index % colors.size()
	if idx < 0:
		idx += colors.size()
	var c: Color = colors[idx]
	var hsv := _rgb_to_hsv(c)
	var phase := _time * 0.05 + phase_offset + float(index) * 0.011
	match _palette_morph:
		"drip_shift", "star_velocity", "electric_strobe":
			hsv.x = fmod(hsv.x + phase * (0.22 + _energy * 0.16), 1.0)
			hsv.z = clampf(hsv.z + _pulse * 0.18 + _energy * 0.12, 0.0, 1.0)
		"heat_branch", "solar_corona":
			hsv.x = fmod(hsv.x + sin(phase * TAU) * 0.025, 1.0)
			hsv.y = clampf(hsv.y * 1.32, 0.0, 1.0)
			hsv.z = clampf(hsv.z + _energy * 0.18 + _pulse * 0.08, 0.0, 1.0)
		"grid_phase":
			hsv.x = fmod(hsv.x + floorf(fmod(phase * 18.0, 4.0)) * 0.018, 1.0)
			hsv.y = clampf(hsv.y * 1.14, 0.0, 1.0)
			hsv.z = clampf(hsv.z + _pulse * 0.14, 0.0, 1.0)
		"pixel_quantize", "nebula_quantize":
			hsv.x = floorf(fmod(hsv.x + phase * 0.10, 1.0) * 10.0) / 10.0
			hsv.y = clampf(hsv.y * 1.20, 0.0, 1.0)
		"void_invert":
			hsv.x = fmod(hsv.x + 0.08 * sin(phase * TAU), 1.0)
			hsv.z = clampf(hsv.z * (0.55 + _energy * 0.28), 0.08, 0.72)
		"aurora_silk", "caustic_wave", "horizon_heat":
			hsv.x = fmod(hsv.x + sin(phase * TAU) * 0.045, 1.0)
			hsv.y = clampf(hsv.y * 0.92, 0.0, 1.0)
			hsv.z = clampf(hsv.z + _pulse * 0.08 + _energy * 0.05, 0.0, 1.0)
		"moon_shimmer":
			hsv.x = fmod(hsv.x + sin(phase * TAU) * 0.018, 1.0)
			hsv.y = clampf(hsv.y * 0.55, 0.15, 0.85)
			hsv.z = clampf(hsv.z + _pulse * 0.06 + _energy * 0.12, 0.25, 1.0)
		"kaleidoscope":
			hsv.x = fmod(hsv.x + float(index % 6) * 0.028 + sin(phase * TAU) * 0.035, 1.0)
			hsv.y = clampf(hsv.y * 1.22, 0.0, 1.0)
		"prism_split", "rift_split":
			hsv.x = fmod(hsv.x + float(index % 3) * 0.035 + phase * 0.12, 1.0)
			hsv.y = clampf(hsv.y * 1.28, 0.0, 1.0)
		_:
			hsv.x = fmod(hsv.x + phase * 0.08, 1.0)
			hsv.z = clampf(hsv.z + _energy * 0.08, 0.0, 1.0)
	c = Color.from_hsv(hsv.x, clampf(hsv.y, 0.45, 1.0), clampf(hsv.z, 0.35, 1.0), alpha)
	return c


func _impulse_energy() -> float:
	var strongest := 0.0
	for imp in _impulses:
		var ttl := maxf(0.001, float(imp.get("ttl", 1.0)))
		var t := clampf(float(imp.get("age", 0.0)) / ttl, 0.0, 1.0)
		strongest = maxf(strongest, float(imp.get("strength", 0.0)) * (1.0 - t))
	return strongest


func _is_hit_impulse(imp: Dictionary) -> bool:
	return str(imp.get("judgement", "hit")).to_lower() != "miss"


func _impulse_energy_for_hits() -> float:
	var strongest := 0.0
	for imp in _impulses:
		if not _is_hit_impulse(imp):
			continue
		var ttl := maxf(0.001, float(imp.get("ttl", 1.0)))
		var t := clampf(float(imp.get("age", 0.0)) / ttl, 0.0, 1.0)
		strongest = maxf(strongest, float(imp.get("strength", 0.0)) * (1.0 - t))
	return strongest


func _impulse_energy_for_misses() -> float:
	var strongest := 0.0
	for imp in _impulses:
		if _is_hit_impulse(imp):
			continue
		var ttl := maxf(0.001, float(imp.get("ttl", 1.0)))
		var t := clampf(float(imp.get("age", 0.0)) / ttl, 0.0, 1.0)
		strongest = maxf(strongest, float(imp.get("strength", 0.0)) * (1.0 - t))
	return strongest


func _render_family() -> String:
	match _effect:
		"neon_rain":
			return "neon_raindrops"
		"plasma_storm":
			return "plasma_cells"
		"quantum_grid":
			return "quantum_lattice"
		"aurora_drive":
			return "aurora_curtains"
		"fractal_space":
			return "fractal_portals"
		"prism_circuit":
			return "prism_circuitry"
		"solar_bloom":
			return "solar_corona"
		_:
			return _effect


func _particles_enabled() -> bool:
	var profile := _profile_store()
	return profile == null or bool(profile.call("is_visual_effect_particles_enabled"))


func _get_bounds_size() -> Vector2:
	if _manual_bounds.x > 1.0 and _manual_bounds.y > 1.0:
		return _manual_bounds
	var parent := get_parent()
	if parent is Control:
		return (parent as Control).size
	if not is_inside_tree():
		return Vector2(1.0, 1.0)
	return get_viewport_rect().size


func _ems() -> Node:
	if is_instance_valid(_override_ems_ref):
		return _override_ems_ref
	if is_instance_valid(_ems_ref):
		return _ems_ref
	var tree := get_tree()
	if tree == null or tree.root == null:
		return null
	_ems_ref = tree.root.get_node_or_null("EmotionalMotionSystem")
	return _ems_ref


func _profile_store() -> Node:
	if is_instance_valid(_profile_ref):
		return _profile_ref
	var tree := get_tree()
	if tree == null or tree.root == null:
		return null
	_profile_ref = tree.root.get_node_or_null("ProfileStore")
	return _profile_ref


func _app_state() -> Node:
	if is_instance_valid(_app_state_ref):
		return _app_state_ref
	var tree := get_tree()
	if tree == null or tree.root == null:
		return null
	_app_state_ref = tree.root.get_node_or_null("AppState")
	return _app_state_ref


func _is_mobile_platform() -> bool:
	var app_state := _app_state()
	return app_state != null and bool(app_state.call("is_mobile_platform"))


func _prioritize_fps_enabled() -> bool:
	var profile := _profile_store()
	return profile != null and bool(profile.call("is_prioritize_fps_enabled"))


func _rgb_to_hsv(color: Color) -> Vector3:
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
	return Vector3(h, s, c_max)
