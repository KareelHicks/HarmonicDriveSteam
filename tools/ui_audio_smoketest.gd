extends SceneTree

const HDSongCarousel := preload("res://scripts/ui/HDSongCarousel.gd")
const HDUIMotion := preload("res://scripts/ui/HDUIMotion.gd")


func _initialize() -> void:
	await process_frame
	var failures: Array[String] = []
	var ui_audio := root.get_node_or_null("UIAudio")
	if ui_audio == null:
		failures.append("UIAudio autoload was not found.")
	else:
		if not bool(ui_audio.call("is_navigation_enabled")):
			failures.append("UIAudio navigation starts disabled.")
		ui_audio.set("_last_play_msec", -1000000)
		ui_audio.call("play_navigation", 1, 1.0)
		if int(ui_audio.get("_last_play_msec")) <= -100000:
			failures.append("UIAudio did not record a navigation sound playback.")
		var hover_button := Button.new()
		root.add_child(hover_button)
		HDUIMotion.attach_button(hover_button)
		ui_audio.set("_last_play_msec", -1000000)
		hover_button.mouse_entered.emit()
		if int(ui_audio.get("_last_play_msec")) <= -100000:
			failures.append("Button hover did not trigger UI navigation audio.")
		hover_button.queue_free()

	var main_scene := load("res://scenes/app/Main.tscn") as PackedScene
	if main_scene == null:
		failures.append("Failed to load Main scene.")
	else:
		var main := main_scene.instantiate()
		root.add_child(main)
		await process_frame
		await process_frame
		main.call("show_chart_editor")
		await process_frame
		if ui_audio != null and bool(ui_audio.call("is_navigation_enabled")):
			failures.append("UIAudio stayed enabled in Chart Editor.")
		main.call("show_song_select")
		await process_frame
		await process_frame
		if ui_audio != null and not bool(ui_audio.call("is_navigation_enabled")):
			failures.append("UIAudio did not re-enable in Song Select.")
		var carousel := main.find_child("SongCarousel", true, false) as HDSongCarousel
		if carousel == null:
			failures.append("Song Select did not expose a SongCarousel.")
		elif ui_audio != null and carousel.songs.size() > 1:
			ui_audio.set("_last_play_msec", -1000000)
			carousel.move(1)
			if int(ui_audio.get("_last_play_msec")) <= -100000:
				failures.append("Carousel movement did not trigger UI navigation audio.")
		main.queue_free()
		await process_frame

	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("UI audio smoke test passed.")
	quit(0)
