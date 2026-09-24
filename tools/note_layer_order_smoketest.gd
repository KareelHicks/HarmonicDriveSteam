extends SceneTree


func _initialize() -> void:
	await process_frame
	var failures: Array[String] = []
	var profile := root.get_node_or_null("ProfileStore")
	var content := root.get_node_or_null("ContentRegistry")
	var app_state := root.get_node_or_null("AppState")
	if profile == null:
		failures.append("ProfileStore autoload was not found.")
	if content == null:
		failures.append("ContentRegistry autoload was not found.")
	if app_state == null:
		failures.append("AppState autoload was not found.")
	if not failures.is_empty():
		_finish(failures, profile, false)
		return

	var original_notes_above := bool(profile.call("are_notes_above_judgement_buttons"))
	var song := _first_playable_song(content)
	if song.is_empty():
		failures.append("No playable manifest song was found.")
		_finish(failures, profile, original_notes_above)
		return
	var difficulty := _first_difficulty(content, song)
	if difficulty.is_empty():
		failures.append("Playable song had no supported difficulty.")
		_finish(failures, profile, original_notes_above)
		return

	profile.call("set_notes_above_judgement_buttons", false)
	var default_scene := await _spawn_game_scene(app_state, song, difficulty)
	if default_scene == null:
		failures.append("Failed to instantiate GameScene for default note layering.")
	else:
		if not _notes_are_behind_judgement(default_scene):
			failures.append("Default note layer was not behind judgement buttons.")
		default_scene.queue_free()
		await process_frame

	profile.call("set_notes_above_judgement_buttons", true)
	var above_scene := await _spawn_game_scene(app_state, song, difficulty)
	if above_scene == null:
		failures.append("Failed to instantiate GameScene for notes-above note layering.")
	else:
		if not _notes_are_above_judgement(above_scene):
			failures.append("Enabled note layer was not above judgement buttons.")
		above_scene.queue_free()
		await process_frame

	_finish(failures, profile, original_notes_above)


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


func _notes_are_behind_judgement(scene: Node) -> bool:
	var note_layer := scene.find_child("NoteLayer", true, false)
	var receptors_margin := scene.find_child("ReceptorsMargin", true, false)
	if note_layer == null or receptors_margin == null:
		return false
	return scene.get_children().find(note_layer) < scene.get_children().find(receptors_margin)


func _notes_are_above_judgement(scene: Node) -> bool:
	var note_layer := scene.find_child("NoteLayer", true, false)
	var fx_layer := scene.find_child("FXLayer", true, false)
	var receptors_margin := scene.find_child("ReceptorsMargin", true, false)
	if note_layer == null or fx_layer == null or receptors_margin == null:
		return false
	var children := scene.get_children()
	var note_index := children.find(note_layer)
	return note_index > children.find(receptors_margin) and children.find(fx_layer) > note_index


func _first_playable_song(content: Node) -> Dictionary:
	var songs: Array = content.call("get_songs")
	for song_variant in songs:
		if song_variant is not Dictionary:
			continue
		var song: Dictionary = song_variant
		if not _first_difficulty(content, song).is_empty():
			return song.duplicate(true)
	return {}


func _first_difficulty(content: Node, song: Dictionary) -> String:
	var difficulties: Array = content.call("get_supported_difficulties", song, "stems_mapped")
	for difficulty_variant in difficulties:
		var difficulty := str(difficulty_variant)
		if not difficulty.is_empty():
			return difficulty
	return ""


func _finish(failures: Array[String], profile: Node, original_notes_above: bool) -> void:
	if profile != null:
		profile.call("set_notes_above_judgement_buttons", original_notes_above)
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("Note layer order smoke test passed.")
	quit(0)
