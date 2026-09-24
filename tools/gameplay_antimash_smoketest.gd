extends SceneTree

const HDNoteVisual = preload("res://scripts/gameplay/HDNoteVisual.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	var app_state := root.get_node("AppState")
	var content := root.get_node("ContentRegistry")
	var original_song: Dictionary = (app_state.get("current_song") as Dictionary).duplicate(true)
	var original_difficulty: String = str(app_state.get("current_difficulty"))
	var original_mode: String = str(app_state.get("current_mode"))
	var song := _first_playable_song(content)
	if song.is_empty():
		failures.append("No playable song was available for the anti-mash smoke test.")
	else:
		var difficulty := _first_difficulty(content, song)
		if difficulty.is_empty():
			failures.append("Playable song had no supported difficulty.")
		else:
			await _check_single_note_extra_lane_fails(app_state, song, difficulty, failures)
			await _check_authored_chord_still_hits(app_state, song, difficulty, failures)
			await _check_held_lane_does_not_block_new_press(app_state, song, difficulty, failures)
			await _check_receptor_glow_tracks_held_lane(app_state, song, difficulty, failures)

	app_state.set("current_song", original_song)
	app_state.set("current_difficulty", original_difficulty)
	app_state.set("current_mode", original_mode)

	if failures.is_empty():
		print("Gameplay anti-mash smoke test passed.")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _check_single_note_extra_lane_fails(app_state: Node, song: Dictionary, difficulty: String, failures: Array[String]) -> void:
	var scene := await _spawn_game_scene(app_state, song, difficulty)
	if scene == null:
		failures.append("Failed to instantiate GameScene for single-note anti-mash case.")
		return
	_prime_scene_for_manual_judgement(scene, [{ "id": 9001, "lane": 0 }])
	scene.call("_on_lane_pressed", 0)
	scene.call("_on_lane_pressed", 2)
	scene.call("_flush_pending_lane_presses")
	var judgements: Dictionary = scene.get("_judgements")
	if int(judgements.get("Miss", 0)) != 1:
		failures.append("Single note plus extra lane should register one miss, got %s." % str(judgements))
	if int(judgements.get("Perfect", 0)) + int(judgements.get("Great", 0)) + int(judgements.get("Good", 0)) != 0:
		failures.append("Single note plus extra lane should not register a hit, got %s." % str(judgements))
	scene.queue_free()
	await process_frame


func _check_authored_chord_still_hits(app_state: Node, song: Dictionary, difficulty: String, failures: Array[String]) -> void:
	var scene := await _spawn_game_scene(app_state, song, difficulty)
	if scene == null:
		failures.append("Failed to instantiate GameScene for chord anti-mash case.")
		return
	_prime_scene_for_manual_judgement(scene, [
		{ "id": 9101, "lane": 0 },
		{ "id": 9102, "lane": 2 },
	])
	scene.call("_on_lane_pressed", 0)
	scene.call("_on_lane_pressed", 2)
	scene.call("_flush_pending_lane_presses")
	var judgements: Dictionary = scene.get("_judgements")
	var hits := int(judgements.get("Perfect", 0)) + int(judgements.get("Great", 0)) + int(judgements.get("Good", 0))
	if hits != 2:
		failures.append("Two-lane chord should register two hits, got %s." % str(judgements))
	if int(judgements.get("Miss", 0)) != 0:
		failures.append("Two-lane chord should not register a miss, got %s." % str(judgements))
	scene.queue_free()
	await process_frame


func _check_held_lane_does_not_block_new_press(app_state: Node, song: Dictionary, difficulty: String, failures: Array[String]) -> void:
	var scene := await _spawn_game_scene(app_state, song, difficulty)
	if scene == null:
		failures.append("Failed to instantiate GameScene for held-lane input case.")
		return
	_prime_scene_for_manual_judgement(scene, [{ "id": 9201, "lane": 2 }])
	# Lane 0 was pressed before lane 2's note entered its judgement window.
	scene.set("_active_input_lanes", {0: true})
	scene.call("_on_lane_pressed", 2)
	scene.call("_flush_pending_lane_presses")
	var judgements: Dictionary = scene.get("_judgements")
	var hits := int(judgements.get("Perfect", 0)) + int(judgements.get("Great", 0)) + int(judgements.get("Good", 0))
	if hits != 1:
		failures.append("A fresh lane press was blocked by an already-held lane, got %s." % str(judgements))
	if int(judgements.get("Miss", 0)) != 0:
		failures.append("An already-held lane caused the fresh lane press to miss, got %s." % str(judgements))
	scene.queue_free()
	await process_frame


func _check_receptor_glow_tracks_held_lane(app_state: Node, song: Dictionary, difficulty: String, failures: Array[String]) -> void:
	var scene := await _spawn_game_scene(app_state, song, difficulty)
	if scene == null:
		failures.append("Failed to instantiate GameScene for held receptor glow case.")
		return
	_prime_scene_for_manual_judgement(scene, [])
	var energies: Array = scene.get("_receptor_press_energy")
	if energies.is_empty():
		failures.append("GameScene did not create receptor feedback energy state.")
	else:
		scene.call("_on_lane_pressed", 0)
		scene.call("_update_receptor_feedback", 1.0)
		energies = scene.get("_receptor_press_energy")
		if not is_equal_approx(float(energies[0]), 1.0):
			failures.append("Held lane receptor glow faded before release.")
		scene.call("_on_lane_released", 0)
		scene.call("_update_receptor_feedback", 0.05)
		energies = scene.get("_receptor_press_energy")
		if float(energies[0]) >= 1.0:
			failures.append("Released lane receptor glow did not begin fading.")
	scene.queue_free()
	await process_frame


func _spawn_game_scene(app_state: Node, song: Dictionary, difficulty: String) -> Node:
	app_state.set("current_song", song.duplicate(true))
	app_state.set("current_difficulty", difficulty)
	app_state.set("current_mode", "stems_mapped")
	var packed := load("res://scenes/gameplay/GameScene.tscn") as PackedScene
	if packed == null:
		return null
	var scene := packed.instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	return scene


func _prime_scene_for_manual_judgement(scene: Node, notes: Array[Dictionary]) -> void:
	scene.set("_started", true)
	scene.set("_finished", false)
	scene.set("_is_paused", false)
	scene.set("_is_failed", false)
	scene.set("_lane_count", 5)
	scene.set("_spawned_nodes", {})
	scene.set("_judged_note_ids", {})
	scene.set("_pending_chord_groups", {})
	scene.set("_hold_state", {})
	scene.set("_active_input_lanes", {})
	scene.set("_pending_lane_presses", {})
	scene.set("_lane_press_flush_queued", false)
	scene.set("_judgements", {"Perfect": 0, "Great": 0, "Good": 0, "Miss": 0})
	scene.set("_score", 0)
	scene.set("_combo", 0)
	scene.set("_max_combo", 0)
	scene.set("_weighted_accuracy", 0.0)
	scene.set("_scored_note_count", 0)
	var song_time := float(scene.call("_current_chart_time"))
	var spawned: Dictionary = {}
	for note_data in notes:
		var lane := int(note_data.get("lane", 0))
		var note_id := int(note_data.get("id", lane))
		var visual := HDNoteVisual.new()
		visual.setup(lane, Vector2(42, 22), 0.0)
		visual.global_position = Vector2(180.0 + float(lane) * 64.0, 320.0)
		scene.add_child(visual)
		spawned[note_id] = {
			"node": visual,
			"note": {
				"id": note_id,
				"lane": lane,
				"time": song_time,
				"duration": 0.0,
			},
			"trail_time": 0.0,
		}
	scene.set("_spawned_nodes", spawned)


func _first_playable_song(content: Node) -> Dictionary:
	for song in content.call("get_songs"):
		var song_dict: Dictionary = song
		if not song_dict.is_empty():
			return song_dict
	return {}


func _first_difficulty(content: Node, song: Dictionary) -> String:
	var difficulties: Array = content.call("get_supported_difficulties", song, "stems_mapped")
	for difficulty in difficulties:
		return str(difficulty)
	return ""
