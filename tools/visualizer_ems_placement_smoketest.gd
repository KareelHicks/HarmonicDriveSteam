extends SceneTree

const SignatureLayerScript = preload("res://scripts/ems/EMSLoadoutSignatureLayer.gd")


class FakeAppState extends Node:
	var visualizer_active := false

	func is_mobile_platform() -> bool:
		return false


class FakeEMS extends Node:
	var run_palette_seed := 0

	func get_run_palette_seed() -> int:
		return run_palette_seed


func _initialize() -> void:
	var failures: Array[String] = []
	var app_state := FakeAppState.new()
	var ems := FakeEMS.new()
	var layer := SignatureLayerScript.new() as Node2D
	layer.set("_app_state_ref", app_state)
	layer.set("_override_ems_ref", ems)
	layer.set("_effect", "gravity_well")
	layer.set("_palette_morph", "solid")
	layer.set("_reaction_model", "circular")
	layer.call("set_visualizer_placement_salt", 0, true)

	ems.run_palette_seed = 101
	layer.call("_rebuild_pool")
	if (layer.get("_placement_offset") as Vector2) != Vector2.ZERO:
		failures.append("Normal gameplay changed the deterministic EMS signature placement.")

	app_state.visualizer_active = true
	layer.call("_rebuild_pool")
	var first_offset := layer.get("_placement_offset") as Vector2
	var first_seed := int(layer.get("_placement_seed"))
	if first_offset == Vector2.ZERO:
		failures.append("Visualizer Mode did not vary a supported EMS signature placement.")

	layer.call("_rebuild_pool")
	if not (layer.get("_placement_offset") as Vector2).is_equal_approx(first_offset) or int(layer.get("_placement_seed")) != first_seed:
		failures.append("Visualizer EMS placement changed within the same song seed.")

	ems.run_palette_seed = 202
	layer.call("_rebuild_pool")
	if (layer.get("_placement_offset") as Vector2).is_equal_approx(first_offset):
		failures.append("Visualizer EMS placement did not change for a new song seed.")

	ems.run_palette_seed = 101
	layer.call("set_visualizer_placement_salt", 1)
	layer.call("_rebuild_pool")
	if int(layer.get("_placement_seed")) == first_seed:
		failures.append("Visualizer EMS left and right placements used the same seed.")

	layer.set("_effect", "neon_rain")
	layer.call("_rebuild_pool")
	if (layer.get("_placement_offset") as Vector2) != Vector2.ZERO:
		failures.append("Visualizer placement randomization affected a non-curated EMS signature.")

	layer.free()
	ems.free()
	app_state.free()

	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return

	print("VISUALIZER_EMS_PLACEMENT_SMOKETEST_OK")
	quit(0)
