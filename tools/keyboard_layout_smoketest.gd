extends SceneTree

const EXPECTED_DEFAULTS := {
	4: [KEY_A, KEY_S, KEY_J, KEY_K],
	5: [KEY_A, KEY_S, KEY_D, KEY_J, KEY_K],
	6: [KEY_A, KEY_S, KEY_D, KEY_J, KEY_K, KEY_L],
	7: [KEY_A, KEY_S, KEY_D, KEY_SPACE, KEY_J, KEY_K, KEY_L],
	8: [KEY_A, KEY_S, KEY_D, KEY_F, KEY_J, KEY_K, KEY_L, KEY_SEMICOLON],
}

var _profile_store: Node
var _app_state: Node


func _initialize() -> void:
	_profile_store = root.get_node_or_null("ProfileStore")
	_app_state = root.get_node_or_null("AppState")
	if not _assert(_profile_store != null, "ProfileStore autoload is missing"):
		return
	if not _assert(_app_state != null, "AppState autoload is missing"):
		return

	for lane_count in EXPECTED_DEFAULTS.keys():
		if not _assert(_defaults_match(int(lane_count)), "%dK keyboard defaults are incorrect" % int(lane_count)):
			return
		if not _assert(_saved_layout_has_lane_count(int(lane_count)), "%dK saved keyboard layout is malformed" % int(lane_count)):
			return

	_app_state.call("sync_input_actions", 4)
	if not _assert(_lane_action_has_events(0), "4K lane_0 has no input events"):
		return
	if not _assert(_lane_action_has_events(3), "4K lane_3 has no input events"):
		return
	if not _assert(not _lane_action_has_events(4), "4K left lane_4 mapped"):
		return

	_app_state.call("sync_input_actions", 8)
	if not _assert(_lane_action_has_events(7), "8K lane_7 has no input events"):
		return

	print("Keyboard layout smoke test passed")
	quit(0)


func _defaults_match(lane_count: int) -> bool:
	var expected: Array = EXPECTED_DEFAULTS[lane_count]
	var defaults: Dictionary = _profile_store.call("get_default_key_bindings", lane_count)
	for lane in range(expected.size()):
		var action := "lane_%d" % lane
		if int(defaults.get(action, 0)) != int(expected[lane]):
			return false
	return defaults.size() == expected.size()


func _saved_layout_has_lane_count(lane_count: int) -> bool:
	var bindings: Dictionary = _profile_store.call("get_key_bindings", lane_count)
	if bindings.size() != lane_count:
		return false
	for lane in range(lane_count):
		if not bindings.has("lane_%d" % lane):
			return false
	return true


func _lane_action_has_events(lane: int) -> bool:
	var action := "lane_%d" % lane
	return InputMap.has_action(action) and not InputMap.action_get_events(action).is_empty()


func _assert(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
		quit(1)
		return false
	return true
