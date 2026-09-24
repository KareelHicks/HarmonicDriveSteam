extends Node2D
class_name EMSSandboxNode

const EMSRuntime = preload("res://systems/ems/EMSRuntime.gd")

var _runtime: EMSRuntime
var _loaded_pack_id := ""


func _ready() -> void:
	name = "EMSSandboxNode"
	_runtime = EMSRuntime.new()
	_runtime.name = "EMSRuntime"
	add_child(_runtime)
	_runtime.set_gutter_filter(_infer_gutter_filter())
	set_process(false)
	var ems := _ems()
	if ems != null:
		ems.call("register_layer", self)
		ems_on_loadout_changed(ems)


func _exit_tree() -> void:
	var ems := _ems()
	if ems != null:
		ems.call("unregister_layer", self)


func ems_on_enabled_changed(is_enabled: bool) -> void:
	visible = is_enabled
	set_process(is_enabled)


func ems_on_loadout_changed(ems: Node) -> void:
	if ems == null or not ems.has_method("has_community_runtime") or not bool(ems.call("has_community_runtime")):
		_loaded_pack_id = ""
		if _runtime != null:
			_runtime.clear()
		set_meta("ems_visual_effect_enabled", false)
		visible = false
		return
	var active_id := str(ems.call("get_active_loadout_id"))
	if active_id == _loaded_pack_id:
		return
	var config: Dictionary = ems.call("get_active_loadout_config") as Dictionary
	var community_config: Dictionary = config.get("community_pack_config", {}) as Dictionary
	_runtime.set_gutter_filter(_infer_gutter_filter())
	_runtime.load_config(community_config)
	_loaded_pack_id = active_id
	set_meta("ems_visual_effect_enabled", true)
	visible = true


func ems_on_palette_changed(ems: Node) -> void:
	ems_on_loadout_changed(ems)


func ems_update(ems: Node, delta: float) -> void:
	if ems == null or _runtime == null or not bool(ems.call("has_community_runtime")):
		return
	_runtime.update_runtime({
		"intensity": float(ems.get("intensity")),
		"combo": float(ems.get("combo_energy")),
		"bpm": float(ems.get("bpm")),
		"density": float(ems.get("note_density")),
		"motion_scale": 1.0,
	}, delta)


func ems_on_impulse(_ems: Node, impulse: Dictionary) -> void:
	if _runtime == null:
		return
	var judgement := str(impulse.get("judgement", "")).to_lower()
	var strength := float(impulse.get("strength", 0.0))
	if judgement == "miss":
		_runtime.dispatch_event("player_miss", impulse)
		_runtime.dispatch_event("miss", impulse)
	else:
		_runtime.dispatch_event("player_hit", impulse)
		if judgement == "good":
			_runtime.dispatch_event("near_miss", impulse)
		if strength >= 0.85:
			_runtime.dispatch_event("bass_hit", impulse)


func ems_on_custom_event(event_name: String, payload: Dictionary) -> void:
	if _runtime != null:
		_runtime.dispatch_event(event_name, payload)


func get_debug_state() -> Dictionary:
	if _runtime == null:
		return {"active": false, "layer_count": 0}
	return _runtime.get_debug_state()


func _ems() -> Node:
	return get_node_or_null("/root/EmotionalMotionSystem")


func _infer_gutter_filter() -> String:
	var cursor: Node = self
	while cursor != null:
		var label := str(cursor.name).to_lower()
		if label.find("right") != -1:
			return "right"
		if label.find("left") != -1:
			return "left"
		cursor = cursor.get_parent()
	return "both"
