extends SceneTree

const GameModeConfig = preload("res://scripts/gameplay/GameModeConfig.gd")
const HDSongCarousel = preload("res://scripts/ui/HDSongCarousel.gd")


func _initialize() -> void:
	await process_frame
	var failures: Array[String] = []
	var app_state := root.get_node_or_null("AppState")
	var ems := root.get_node_or_null("EmotionalMotionSystem")
	var profile_store := root.get_node_or_null("ProfileStore")
	if app_state == null or ems == null or profile_store == null:
		push_error("Visualizer smoke test requires AppState, EmotionalMotionSystem, and ProfileStore autoloads.")
		quit(1)
		return
	var original_visualizer_song_id := str(profile_store.call("get_visualizer_selected_song_id"))

	var main_scene := load("res://scenes/app/Main.tscn") as PackedScene
	var main := main_scene.instantiate() if main_scene != null else null
	if main == null:
		push_error("Visualizer smoke test could not instantiate Main.tscn.")
		quit(1)
		return
	root.add_child(main)
	await process_frame
	await process_frame
	var title_screen := main.get("_current_screen") as Node
	if title_screen == null or title_screen.find_child("VisualizerButton", true, false) == null:
		failures.append("Main Menu is missing the Visualizer Mode option.")

	app_state.call("request_visualizer_select")
	await process_frame
	await process_frame
	var visualizer_menu := main.get("_current_screen") as Node
	if visualizer_menu == null or not visualizer_menu.has_signal("shuffle_requested") or not visualizer_menu.has_signal("song_requested"):
		failures.append("Main did not route Visualizer Mode to its dedicated selection screen.")
	if visualizer_menu != null and visualizer_menu.find_child("SongCarousel", true, false) == null:
		failures.append("Visualizer selection screen did not create the song carousel.")
	var search_field: LineEdit = null
	if visualizer_menu != null:
		search_field = visualizer_menu.find_child("SearchField", true, false) as LineEdit
	if search_field == null:
		failures.append("Visualizer selection screen is missing its Search field.")
	if visualizer_menu != null:
		visualizer_menu.call("_on_shuffle_button_pressed")
		var shuffle_prompt := visualizer_menu.find_child("ReactiveModeOverlay", true, false) as CanvasItem
		if shuffle_prompt == null or not shuffle_prompt.visible:
			failures.append("Shuffle selection did not prompt for Player Reactive or Chart Reactive.")
		if bool(app_state.get("visualizer_active")):
			failures.append("Shuffle selection launched before a reactive mode was chosen.")
		visualizer_menu.call("_on_cancel_reactive_button_pressed")

	var songs: Array = app_state.call("get_visualizer_songs")
	if songs.is_empty():
		failures.append("Visualizer catalog did not expose any songs with audio.")
	else:
		var selected_song := (songs[0] as Dictionary).duplicate(true)
		var selected_song_id := str(selected_song.get("id", ""))
		if search_field != null:
			search_field.text = selected_song_id
			visualizer_menu.call("_on_search_field_text_changed", selected_song_id)
			var filtered_songs := visualizer_menu.get("_songs") as Array
			if filtered_songs.is_empty():
				failures.append("Visualizer Search did not find a song by its ID.")
			else:
				for filtered_song_variant in filtered_songs:
					var filtered_song := filtered_song_variant as Dictionary
					var searchable := "%s %s %s %s" % [filtered_song.get("display_name", ""), filtered_song.get("artist", ""), filtered_song.get("id", ""), filtered_song.get("title", "")]
					if not searchable.to_lower().contains(selected_song_id.to_lower()):
						failures.append("Visualizer Search retained a non-matching song.")
						break
			search_field.text = ""
			visualizer_menu.call("_on_search_field_text_changed", "")
			if (visualizer_menu.get("_songs") as Array).size() != songs.size():
				failures.append("Clearing Visualizer Search did not restore the full song catalog.")
		visualizer_menu.call("_launch_song", selected_song)
		var song_prompt := visualizer_menu.find_child("ReactiveModeOverlay", true, false) as CanvasItem
		if song_prompt == null or not song_prompt.visible:
			failures.append("Song selection did not prompt for Player Reactive or Chart Reactive.")
		if visualizer_menu.find_child("PlayerReactiveButton", true, false) == null or visualizer_menu.find_child("ChartReactiveButton", true, false) == null:
			failures.append("Reactive mode prompt is missing one of its required choices.")
		visualizer_menu.call("_on_player_reactive_button_pressed")
		await process_frame
		await process_frame
		await process_frame
		var game := main.get("_current_screen") as Node
		if game == null or not game.has_signal("visualizer_song_finished"):
			failures.append("Visualizer launch did not enter the gameplay runtime.")
		else:
			if not bool(game.get("_visualizer_mode")):
				failures.append("Gameplay runtime did not enable its Visualizer Mode state.")
			if str(game.get("_visualizer_reactive_mode")) != "player" or str(app_state.get("visualizer_reactive_mode")) != "player":
				failures.append("Player Reactive selection was not preserved into gameplay.")
			if int(game.get("_lane_count")) != 8:
				failures.append("Player Reactive did not bind exactly eight lanes.")
			if not (game.get("_chart") as Dictionary).is_empty() or not (game.get("_notes") as Array).is_empty():
				failures.append("Player Reactive loaded chart content instead of leaving the chart disabled.")
			for node_name in ["LaneBackgrounds", "RunwayInset", "NoteLayer", "FXLayer", "ReceptorsMargin", "HUD"]:
				var hidden_node := game.find_child(node_name, true, false) as CanvasItem
				if hidden_node == null or hidden_node.visible:
					failures.append("Visualizer Mode left %s visible." % node_name)
			var left_ems := game.find_child("EmotionalMotionLeftGutter", true, false) as Control
			var right_ems := game.find_child("EmotionalMotionRightGutter", true, false) as Control
			var viewport_width := float((game.call("_display_size") as Vector2).x)
			var center_x := floorf(viewport_width * 0.5)
			if left_ems == null or not left_ems.visible or left_ems.anchor_left != 0.0 or left_ems.anchor_right != 0.0:
				failures.append("Visualizer Mode did not keep the left EMS gutter active.")
			elif absf(left_ems.position.x) > 1.0 or absf(left_ems.size.x - center_x) > 1.0:
				failures.append("Visualizer Mode left EMS half did not fill through the hidden chart background.")
			if right_ems == null or not right_ems.visible or right_ems.anchor_left != 0.0 or right_ems.anchor_right != 0.0:
				failures.append("Visualizer Mode did not keep the right EMS gutter active.")
			elif absf(right_ems.position.x - center_x) > 1.0 or absf(right_ems.size.x - (viewport_width - center_x)) > 1.0:
				failures.append("Visualizer Mode right EMS half did not fill through the hidden chart background.")
			if left_ems != null and right_ems != null and absf(right_ems.position.x - (left_ems.position.x + left_ems.size.x)) > 1.0:
				failures.append("Visualizer Mode left a center strip between its two EMS halves.")
			game.call("_update_visualizer_background", 0.0)
			var chart_background := game.find_child("Background", true, false) as ColorRect
			if not bool(game.get("_chart_background_disabled")) or chart_background == null or not chart_background.visible:
				failures.append("Visualizer Mode did not keep its opaque EMS background backing visible.")
			elif not chart_background.color.is_equal_approx(ems.call("get_gutter_background_color") as Color):
				failures.append("Visualizer Mode background did not honor the resolved EMS background color.")
			var pressure_layer := game.get("_ems_pressure_wave_layer") as CanvasItem
			if pressure_layer == null or pressure_layer.visible or pressure_layer.is_processing():
				failures.append("Visualizer Mode left the player pressure-hit layer active.")
			var gameplay_shader_layer := game.get("_max_gameplay_shader_layer") as CanvasItem
			if gameplay_shader_layer == null or gameplay_shader_layer.visible or gameplay_shader_layer.is_processing():
				failures.append("Visualizer Mode left the player gameplay-shader layer active.")
			if bool((app_state.get("current_loadout") as Dictionary).get("ranked", true)):
				failures.append("Visualizer Mode was incorrectly marked as a ranked run.")

			var impulses_before: Array = (ems.call("get_impulses") as Array).duplicate(true)
			game.call("_on_lane_pressed", 7)
			var impulses_after: Array = ems.call("get_impulses") as Array
			if impulses_after.is_empty():
				failures.append("Visualizer lane input did not generate an EMS impulse.")
			else:
				var last_impulse := impulses_after.back() as Dictionary
				if int(last_impulse.get("lane", -1)) != 7 or str(last_impulse.get("judgement", "")) != "Perfect":
					failures.append("Visualizer lane input generated the wrong EMS impulse payload.")
			if impulses_after.size() < impulses_before.size():
				failures.append("Visualizer lane input unexpectedly removed EMS impulses.")
			if pressure_layer != null and not (pressure_layer.get("_waves") as Array).is_empty():
				failures.append("Player Reactive spawned pressure-hit visuals without notes.")
			if int(game.get("_score")) != 0 or int(game.get("_scored_note_count")) != 0:
				failures.append("Visualizer lane input entered the chart scoring path.")

			var queued_ids: Dictionary = {}
			var opening_queue := (app_state.get("_visualizer_queue") as Array).duplicate(true)
			for queued_song_variant in opening_queue:
				var queued_song := queued_song_variant as Dictionary
				var queued_id := str(queued_song.get("id", ""))
				if queued_id == selected_song_id:
					failures.append("Selected-song Visualizer queue repeated the opening song immediately.")
				if queued_ids.has(queued_id):
					failures.append("Visualizer shuffled pass contained a duplicate song.")
				queued_ids[queued_id] = true
			if opening_queue.size() != maxi(0, songs.size() - 1):
				failures.append("Selected-song Visualizer pass did not queue every remaining song exactly once.")
			app_state.call("_rebuild_visualizer_queue", selected_song_id, false)
			var full_cycle_queue := app_state.get("_visualizer_queue") as Array
			if full_cycle_queue.size() != songs.size():
				failures.append("A repeated Visualizer shuffle cycle did not include the full song catalog.")
			if full_cycle_queue.size() > 1 and str((full_cycle_queue[0] as Dictionary).get("id", "")) == selected_song_id:
				failures.append("A repeated Visualizer shuffle cycle can immediately repeat the previous song.")
			app_state.set("_visualizer_queue", opening_queue)

			game.call("_on_audio_finished")
			await process_frame
			await process_frame
			await process_frame
			var continued_game := main.get("_current_screen") as Node
			if not bool(app_state.get("visualizer_active")):
				failures.append("Visualizer session stopped instead of continuing after the song.")
			if songs.size() > 1 and str((app_state.get("current_song") as Dictionary).get("id", "")) == selected_song_id:
				failures.append("Visualizer session did not continue to a random next song.")
			if continued_game == null or not bool(continued_game.get("_visualizer_mode")):
				failures.append("Visualizer continuation left the EMS-only gameplay runtime.")

			var last_visualizer_song_id := str((app_state.get("current_song") as Dictionary).get("id", ""))
			if continued_game != null:
				var cancel := InputEventAction.new()
				cancel.action = "ui_cancel"
				cancel.pressed = true
				continued_game.call("_unhandled_input", cancel)
				cancel = null
				await process_frame
				await process_frame
				if bool(app_state.get("visualizer_active")):
					failures.append("Exiting Visualizer Mode did not clear the active session.")
				var returned_screen := main.get("_current_screen") as Node
				if returned_screen == null or not returned_screen.has_signal("shuffle_requested"):
					failures.append("Exiting Visualizer Mode did not return to its selection screen.")
				else:
					var returned_carousel := returned_screen.find_child("SongCarousel", true, false) as HDSongCarousel
					if returned_carousel == null or str(returned_carousel.get_selected_song().get("id", "")) != last_visualizer_song_id:
						failures.append("Visualizer selection did not resume on the last played song.")
					var content_registry := root.get_node_or_null("ContentRegistry")
					var chart_song: Dictionary = {}
					if content_registry != null:
						for song_variant in songs:
							var candidate := song_variant as Dictionary
							var candidate_path := str(content_registry.call("get_chart_path", candidate, "Professional", GameModeConfig.STEMS_MAPPED))
							if not candidate_path.is_empty() and FileAccess.file_exists(candidate_path):
								chart_song = candidate.duplicate(true)
								break
					if chart_song.is_empty():
						failures.append("Visualizer catalog did not expose a song with a Professional Classic chart for Chart Reactive coverage.")
					else:
						returned_screen.call("_launch_song", chart_song)
						var chart_prompt := returned_screen.find_child("ReactiveModeOverlay", true, false) as CanvasItem
						if chart_prompt == null or not chart_prompt.visible:
							failures.append("Chart Reactive song selection skipped the reactive mode prompt.")
						returned_screen.call("_on_chart_reactive_button_pressed")
						await process_frame
						await process_frame
						await process_frame
						var chart_game := main.get("_current_screen") as Node
						if chart_game == null or not bool(chart_game.get("_visualizer_mode")):
							failures.append("Chart Reactive did not enter the Visualizer gameplay runtime.")
						else:
							var chart_notes := chart_game.get("_notes") as Array
							if str(app_state.get("visualizer_reactive_mode")) != "chart" or str(chart_game.get("_visualizer_reactive_mode")) != "chart":
								failures.append("Chart Reactive selection was not preserved into gameplay.")
							if str(app_state.get("current_difficulty")) != "Professional" or str(app_state.get("current_mode")) != GameModeConfig.STEMS_MAPPED:
								failures.append("Chart Reactive did not select the Professional Classic chart.")
							if (chart_game.get("_chart") as Dictionary).is_empty() or chart_notes.is_empty():
								failures.append("Chart Reactive did not load chart timing data.")
							var chart_pressure := chart_game.get("_ems_pressure_wave_layer") as CanvasItem
							if chart_pressure == null:
								failures.append("Chart Reactive is missing its EMS pressure-hit layer.")
							elif chart_pressure.visible or chart_pressure.is_processing() or bool(chart_game.call("_maximum_pressure_waves_active")):
								failures.append("Chart Reactive left the player pressure-hit layer active.")
							var chart_gameplay_shader := chart_game.get("_max_gameplay_shader_layer") as CanvasItem
							if chart_gameplay_shader == null or chart_gameplay_shader.visible or chart_gameplay_shader.is_processing() or bool(chart_game.call("_maximum_gameplay_shaders_active")):
								failures.append("Chart Reactive left the player gameplay-shader layer active.")
							chart_game.call("_update_visualizer_background", 0.0)
							var chart_background_node := chart_game.find_child("Background", true, false) as ColorRect
							if chart_background_node == null or not chart_background_node.visible:
								failures.append("Chart Reactive did not keep its opaque EMS background backing visible.")
							elif not chart_background_node.color.is_equal_approx(ems.call("get_gutter_background_color") as Color):
								failures.append("Chart Reactive background did not honor the resolved EMS background color.")
							if not chart_notes.is_empty():
								chart_game.set("_next_chart_reactive_index", 0)
								chart_game.set("_combo", 0)
								chart_game.set("_max_combo", 0)
								chart_game.set("_judgements", {"Perfect": 0, "Great": 0, "Good": 0, "Miss": 0})
								chart_game.set("_scored_note_count", 0)
								chart_game.set("_weighted_accuracy", 0.0)
								ems.call("set_combo_count", 0)
								var first_note := chart_notes[0] as Dictionary
								var first_note_time := float(first_note.get("time", 0.0))
								var first_dispatch_count := 0
								for chart_note_variant in chart_notes:
									var chart_note := chart_note_variant as Dictionary
									if float(chart_note.get("time", 0.0)) > first_note_time:
										break
									first_dispatch_count += 1
								var impulses_before_chart_hit := (ems.call("get_impulses") as Array).size()
								chart_game.call("_dispatch_due_visualizer_chart_hits", first_note_time)
								var impulses_after_chart_hit := ems.call("get_impulses") as Array
								if impulses_after_chart_hit.size() <= impulses_before_chart_hit:
									failures.append("Chart Reactive did not generate a Perfect EMS impulse at the first note timing.")
								else:
									var chart_impulse := impulses_after_chart_hit.back() as Dictionary
									if str(chart_impulse.get("judgement", "")) != "Perfect":
										failures.append("Chart Reactive generated a non-Perfect EMS judgement.")
								if int(chart_game.get("_combo")) != first_dispatch_count or int(chart_game.get("_max_combo")) != first_dispatch_count:
									failures.append("Chart Reactive did not begin a virtual Perfect combo.")
								if int((chart_game.get("_judgements") as Dictionary).get("Perfect", 0)) != first_dispatch_count:
									failures.append("Chart Reactive did not record its virtual Perfect judgement.")
								if not is_equal_approx(float(chart_game.call("_current_accuracy")), 100.0):
									failures.append("Chart Reactive virtual accuracy was not 100 percent.")
								var impulses_before_manual_press := impulses_after_chart_hit.size()
								chart_game.call("_on_lane_pressed", 7)
								if (ems.call("get_impulses") as Array).size() != impulses_before_manual_press:
									failures.append("Chart Reactive still responded to manual lane input.")
								if chart_pressure != null and not (chart_pressure.get("_waves") as Array).is_empty():
									failures.append("Chart Reactive spawned player pressure-hit visuals.")
							if int(chart_game.get("_score")) != 0:
								failures.append("Chart Reactive submitted gameplay score while simulating its virtual FC.")
							if not chart_notes.is_empty():
								chart_game.call("_dispatch_due_visualizer_chart_hits", INF)
								var virtual_result := chart_game.call("_visualizer_fc_payload") as Dictionary
								if int(chart_game.get("_combo")) != chart_notes.size() or int(chart_game.get("_max_combo")) != chart_notes.size():
									failures.append("Chart Reactive did not carry its Perfect combo through the full chart.")
								if not bool(virtual_result.get("full_combo", false)) or not bool(virtual_result.get("all_perfect", false)):
									failures.append("Chart Reactive did not resolve as a virtual FC and All Perfect.")
								if int(virtual_result.get("perfect", 0)) != chart_notes.size() or not is_equal_approx(float(virtual_result.get("accuracy", 0.0)), 100.0):
									failures.append("Chart Reactive virtual FC result was not 100 percent Perfect.")
							chart_game.call("_on_audio_finished")
							await process_frame
							await process_frame
							await process_frame
							var continued_chart_game := main.get("_current_screen") as Node
							if str(app_state.get("visualizer_reactive_mode")) != "chart":
								failures.append("Chart Reactive was not preserved for the next shuffled song.")
							if continued_chart_game == null or str(continued_chart_game.get("_visualizer_reactive_mode")) != "chart":
								failures.append("Chart Reactive continuation did not remain chart-driven.")
							elif (continued_chart_game.get("_notes") as Array).is_empty():
								failures.append("Chart Reactive continuation did not load the next song's chart timings.")

	root.get_node("AudioSync").call("load_stream", "")
	root.get_node("MenuAudio").call("stop")
	main.queue_free()
	await process_frame
	await process_frame
	main_scene = null
	main = null
	profile_store.call("set_visualizer_selected_song_id", original_visualizer_song_id)

	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("VISUALIZER_MODE_SMOKETEST_OK")
	quit(0)
