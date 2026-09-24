extends SceneTree

const SignatureLayerScript = preload("res://scripts/ems/EMSLoadoutSignatureLayer.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	var layer := SignatureLayerScript.new() as Node2D
	layer.set("_effect", "cyber_ocean")
	layer.set("_cyber_ocean_flow", 0.0)
	layer.set("_impulses", [_hit_impulse()])

	var base_speed := float(layer.call("_cyber_ocean_tide_speed"))
	layer.call("_update_cyber_ocean_flow", 1.0 / 60.0, 0.0)
	var first_hit_speed := float(layer.call("_cyber_ocean_tide_speed"))
	if first_hit_speed - base_speed > 0.05:
		failures.append("Cyber Ocean still jumps too quickly after one hit.")

	var single_hit_peak := first_hit_speed
	for _frame in 30:
		layer.call("_update_impulses", 1.0 / 60.0)
		layer.call("_update_cyber_ocean_flow", 1.0 / 60.0, 0.0)
		single_hit_peak = maxf(single_hit_peak, float(layer.call("_cyber_ocean_tide_speed")))

	layer.set("_cyber_ocean_flow", 0.0)
	layer.set("_impulses", [])
	var rapid_hit_peak := base_speed
	var hits := 0
	for frame in 90:
		if frame % 6 == 0:
			hits += 1
			var impulses := layer.get("_impulses") as Array
			impulses.append(_hit_impulse())
		layer.call("_update_impulses", 1.0 / 60.0)
		var combo := 1.0 - exp(-float(hits) / 38.0)
		layer.call("_update_cyber_ocean_flow", 1.0 / 60.0, combo)
		rapid_hit_peak = maxf(rapid_hit_peak, float(layer.call("_cyber_ocean_tide_speed")))

	if rapid_hit_peak <= single_hit_peak + 0.25:
		failures.append("Cyber Ocean did not build meaningful speed from sustained rapid hits.")
	if rapid_hit_peak > 1.6501:
		failures.append("Cyber Ocean exceeded its capped tide speed.")

	layer.free()
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("CYBER_OCEAN_SPEED_SMOKETEST_OK")
	quit(0)


func _hit_impulse() -> Dictionary:
	return {
		"ttl": 1.15,
		"age": 0.0,
		"strength": 1.0,
		"judgement": "Perfect",
	}
