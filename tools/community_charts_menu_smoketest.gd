extends SceneTree

var _community_signal_emitted := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	var packed := load("res://scenes/menus/TitleMenu.tscn") as PackedScene
	if packed == null:
		failures.append("Could not load TitleMenu.tscn.")
	else:
		var menu := packed.instantiate()
		root.add_child(menu)
		await process_frame
		var button := menu.get_node_or_null("%CommunityChartsButton") as Button
		if button == null:
			failures.append("CommunityChartsButton is missing.")
		elif button.text != "Community Charts":
			failures.append("CommunityChartsButton text is incorrect.")
		_community_signal_emitted = false
		if menu.has_signal("community_charts_requested"):
			menu.community_charts_requested.connect(_on_community_charts_requested)
			var has_scene_connection := false
			var connections := button.get_signal_connection_list("pressed") if button != null else []
			for connection in connections:
				var callable: Callable = (connection as Dictionary).get("callable", Callable())
				if callable.get_method() == "_on_community_charts_button_pressed":
					has_scene_connection = true
					break
			if not has_scene_connection:
				failures.append("CommunityChartsButton is not connected to _on_community_charts_button_pressed.")
			if button != null:
				menu.call("_on_community_charts_button_pressed")
				await process_frame
			if not _community_signal_emitted:
				failures.append("Community Charts handler did not emit community_charts_requested.")
		else:
			failures.append("TitleMenu is missing community_charts_requested signal.")

	if failures.is_empty():
		print("Community Charts menu smoke test passed.")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _on_community_charts_requested() -> void:
	_community_signal_emitted = true
