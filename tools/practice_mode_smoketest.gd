extends SceneTree


func _initialize() -> void:
	await process_frame
	var failures: Array[String] = []
	var app_state := root.get_node_or_null("AppState")
	var content_registry := root.get_node_or_null("ContentRegistry")
	var audio_sync := root.get_node_or_null("AudioSync")
	if app_state == null or content_registry == null or audio_sync == null:
		push_error("Practice smoke test requires AppState, ContentRegistry, and AudioSync autoloads.")
		quit(1)
		return

	var main_scene := load("res://scenes/app/Main.tscn") as PackedScene
	var main := main_scene.instantiate() if main_scene != null else null
	if main == null:
		push_error("Practice smoke test could not instantiate Main.tscn.")
		quit(1)
		return
	root.add_child(main)
	await process_frame
	await process_frame

	var title_screen := main.get("_current_screen") as Node
	var visualizer_button := title_screen.find_child("VisualizerButton", true, false) if title_screen != null else null
	var practice_button := title_screen.find_child("PracticeModeButton", true, false) if title_screen != null else null
	if practice_button == null:
		failures.append("Main Menu is missing the Practice Mode option.")
	elif visualizer_button == null or practice_button.get_index() != visualizer_button.get_index() + 1:
		failures.append("Practice Mode is not directly beneath Visualizer Mode.")

	app_state.call("request_practice_select")
	await process_frame
	await process_frame
	var practice_menu := main.get("_current_screen") as Node
	var title_label := practice_menu.find_child("TitleLabel", true, false) as Label if practice_menu != null else null
	if practice_menu == null or not practice_menu.has_signal("start_requested"):
		failures.append("Main did not route Practice Mode to song selection.")
	elif title_label == null or not title_label.text.contains("PRACTICE MODE"):
		failures.append("Practice song selection did not identify the active mode.")

	var selected_song: Dictionary = {}
	var selected_mode := "classic"
	var selected_difficulty := ""
	for song_variant in content_registry.call("get_progression_ordered_songs"):
		var candidate := song_variant as Dictionary
		if str(candidate.get("audio_path", "")).is_empty():
			continue
		for mode_variant in content_registry.call("get_supported_modes", candidate):
			var mode := str(mode_variant)
			var difficulties: Array = content_registry.call("get_supported_difficulties", candidate, mode)
			if difficulties.is_empty():
				continue
			var difficulty := str(difficulties[0])
			if str(content_registry.call("get_chart_path", candidate, difficulty, mode)).is_empty():
				continue
			selected_song = candidate.duplicate(true)
			selected_mode = mode
			selected_difficulty = difficulty
			break
		if not selected_song.is_empty():
			break

	if selected_song.is_empty():
		failures.append("No playable song was available for Practice Mode coverage.")
	else:
		practice_menu.emit_signal("start_requested", selected_song, selected_difficulty, selected_mode)
		await process_frame
		await process_frame
		await process_frame
		var game := main.get("_current_screen") as Node
		if game == null or not bool(game.get("_practice_mode")):
			failures.append("Practice selection did not enter the gameplay runtime in Practice Mode.")
		else:
			var transport := game.find_child("PracticeTransport", true, false) as Control
			var timeline := game.find_child("PracticeTimeline", true, false) as HSlider
			var speed_spin := game.find_child("PracticeSpeedSpin", true, false) as SpinBox
			if transport == null or not transport.visible:
				failures.append("Practice gameplay did not show its bottom transport dock.")
			if timeline == null or timeline.max_value <= 0.0:
				failures.append("Practice timeline was not configured for the selected song.")
			if speed_spin == null or not is_equal_approx(float(speed_spin.min_value), 0.25) or not is_equal_approx(float(speed_spin.max_value), 1.5):
				failures.append("Practice playback speed did not expose the Live Editor range.")
			if not bool(game.get("_is_paused")) or audio_sync.call("is_playing"):
				failures.append("Practice gameplay did not open paused for timeline setup.")
			if bool(game.get("_drive_fail_enabled")):
				failures.append("Practice Mode left the gameplay fail state enabled.")
			var loadout := app_state.get("current_loadout") as Dictionary
			if bool(loadout.get("ranked", true)) or not bool(loadout.get("practice_session", false)):
				failures.append("Practice Mode was not marked as an unranked practice session.")

			game.call("_on_practice_speed_changed", 0.75)
			if not is_equal_approx(float(audio_sync.call("get_speed_scale")), 0.75):
				failures.append("Practice speed control did not update audio playback speed.")
			var duration := float(audio_sync.call("get_stream_length"))
			var seek_target := minf(1.0, duration * 0.5)
			game.set("_score", 1234)
			game.call("_on_practice_timeline_value_changed", seek_target)
			if absf(float(audio_sync.call("get_song_time_raw")) - seek_target) > 0.02:
				failures.append("Practice timeline did not seek the source-audio timeline.")
			if int(game.get("_score")) != 0:
				failures.append("Practice seek did not reset stale scoring state.")

			game.call("_on_practice_play_pause_pressed")
			if bool(game.get("_is_paused")) or not bool(audio_sync.call("is_playing")):
				failures.append("Practice transport could not resume playback.")
			game.call("_on_practice_play_pause_pressed")
			if not bool(game.get("_is_paused")):
				failures.append("Practice transport could not pause playback.")

			game.call("_on_audio_finished")
			await process_frame
			if main.get("_current_screen") != game or not bool(game.get("_is_paused")):
				failures.append("Practice completion left gameplay instead of pausing for replay or seeking.")

			game.call("_on_exit_button_pressed")
			await process_frame
			await process_frame
			var returned_menu := main.get("_current_screen") as Node
			if returned_menu == null or not returned_menu.has_signal("start_requested") or not bool(app_state.get("practice_active")):
				failures.append("Exiting Practice gameplay did not return to Practice song selection.")

	app_state.call("request_title")
	await process_frame
	if bool(app_state.get("practice_active")):
		failures.append("Returning to the Main Menu did not clear the Practice session.")
	audio_sync.call("reset_speed_scale")
	audio_sync.call("load_stream", "")
	root.get_node("MenuAudio").call("stop")
	main.queue_free()
	await process_frame

	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("PRACTICE_MODE_SMOKETEST_OK")
	quit(0)
