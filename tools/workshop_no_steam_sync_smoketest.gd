extends SceneTree

const WorkshopSubscriptionSync := preload("res://scripts/workshop/WorkshopSubscriptionSync.gd")

var _status_events: Array[Dictionary] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var steam_client := root.get_node_or_null("/root/SteamClient")
	if steam_client != null and steam_client.has_method("is_ready") and bool(steam_client.call("is_ready")):
		print("Workshop no-Steam sync smoke test skipped because Steam is initialized.")
		quit(0)
		return

	var failures: Array[String] = []
	var started_msec := Time.get_ticks_msec()
	var result: Dictionary = await WorkshopSubscriptionSync.refresh_all_until_stable_interactive(
		true,
		Callable(self, "_on_status"),
		true,
		20,
		0.25
	)
	var elapsed_msec := Time.get_ticks_msec() - started_msec
	_expect(not bool(result.get("ok", true)), "No-Steam Workshop sync should fail cleanly.", failures)
	_expect(not bool(result.get("retryable", true)), "No-Steam Workshop sync should be non-retryable.", failures)
	_expect(bool(result.get("steam_unavailable", false)), "No-Steam Workshop sync should report steam_unavailable.", failures)
	_expect(int(result.get("attempts", 0)) == 1, "No-Steam Workshop sync should stop after one attempt.", failures)
	_expect(elapsed_msec < 1000, "No-Steam Workshop sync took too long: %d ms." % elapsed_msec, failures)
	_expect(_has_status_phase("workshop_unavailable"), "No-Steam Workshop sync should emit an unavailable status.", failures)
	if failures.is_empty():
		print("Workshop no-Steam sync smoke test passed.")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _on_status(status: Dictionary) -> void:
	_status_events.append(status.duplicate(true))


func _has_status_phase(phase: String) -> bool:
	for status_variant in _status_events:
		if str((status_variant as Dictionary).get("phase", "")) == phase:
			return true
	return false


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
