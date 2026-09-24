extends Control
class_name EMSPressureWaveLayer

const MAX_WAVES := 24

var _waves: Array[Dictionary] = []
var _lane_count := 5
var _hit_line_y := 0.0
var _lane_colors: Array = []


func _ready() -> void:
	name = "EMSPressureWaveLayer"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)
	visible = false


func configure(lane_count: int, hit_line_y: float, lane_colors: Array) -> void:
	_lane_count = maxi(1, lane_count)
	_hit_line_y = hit_line_y
	_lane_colors = lane_colors.duplicate(true)
	queue_redraw()


func spawn_wave(lane: int, strength: float, origin: Vector2, color: Color = Color.WHITE) -> void:
	if not visible:
		return
	var safe_lane := clampi(lane, 0, _lane_count - 1)
	var c := color
	if c == Color.WHITE and safe_lane >= 0 and safe_lane < _lane_colors.size() and _lane_colors[safe_lane] is Color:
		c = _lane_colors[safe_lane]
	c.a = 1.0
	_waves.append({
		"age": 0.0,
		"ttl": 0.42 + clampf(strength, 0.0, 1.0) * 0.16,
		"origin": origin,
		"strength": clampf(strength, 0.0, 1.0),
		"color": c,
	})
	if _waves.size() > MAX_WAVES:
		_waves.remove_at(0)
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	for i in range(_waves.size() - 1, -1, -1):
		var wave := _waves[i]
		wave["age"] = float(wave.get("age", 0.0)) + delta
		if float(wave["age"]) >= float(wave.get("ttl", 0.48)):
			_waves.remove_at(i)
		else:
			_waves[i] = wave
	if _waves.is_empty():
		set_process(false)
	queue_redraw()


func _draw() -> void:
	if _waves.is_empty() or size.x <= 1.0 or size.y <= 1.0:
		return
	for wave in _waves:
		var age := float(wave.get("age", 0.0))
		var ttl := maxf(0.001, float(wave.get("ttl", 0.48)))
		var t := clampf(age / ttl, 0.0, 1.0)
		var ease := 1.0 - pow(1.0 - t, 2.4)
		var strength := clampf(float(wave.get("strength", 0.7)), 0.0, 1.0)
		var origin: Vector2 = wave.get("origin", Vector2(size.x * 0.5, _hit_line_y))
		var radius := lerpf(10.0 + strength * 8.0, 82.0 + strength * 46.0, ease)
		var alpha := (1.0 - t) * (0.30 + strength * 0.34)
		var c: Color = wave.get("color", Color.WHITE)

		var outer := c.lerp(Color(0.35, 0.95, 1.0, 1.0), 0.52)
		outer.a = alpha * 0.20
		draw_circle(origin, radius * 1.10, outer)

		var glow := c.lerp(Color(0.55, 1.0, 1.0, 1.0), 0.68)
		glow.a = alpha * 0.42
		draw_arc(origin, radius * 0.92, -PI * 0.98, PI * 0.12, 42, glow, 7.5 + strength * 3.5, true)
		draw_arc(origin, radius * 0.72, PI * 0.18, PI * 1.12, 42, glow, 5.5 + strength * 2.5, true)

		var core := c.lerp(Color.WHITE, 0.62)
		core.a = alpha
		draw_arc(origin, radius, 0.0, TAU, 64, core, 2.0 + strength * 1.8, true)

		var shimmer := Color(0.75, 1.0, 1.0, alpha * 0.34)
		var wobble_radius := radius * (0.48 + sin(t * TAU) * 0.035)
		draw_arc(origin + Vector2(sin(t * TAU) * 3.0, -cos(t * TAU) * 2.0), wobble_radius, -PI * 0.20, PI * 1.25, 36, shimmer, 1.4, true)
