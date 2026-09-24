extends SceneTree

const EMSValidator := preload("res://systems/ems/EMSValidator.gd")
const EMSLoadoutCatalog := preload("res://scripts/ems/EMSLoadoutCatalog.gd")
const EMSPropertyPanelScript := preload("res://systems/ems/EMSCreator/EMSPropertyPanel.gd")
const EMSLayerListScript := preload("res://systems/ems/EMSCreator/EMSLayerList.gd")
const EMSTimelinePanelScript := preload("res://systems/ems/EMSCreator/EMSTimelinePanel.gd")
const EMSPreviewViewportScript := preload("res://systems/ems/EMSCreator/EMSPreviewViewport.gd")
const EMSLayerTypeBuilderDialogScript := preload("res://systems/ems/EMSCreator/EMSLayerTypeBuilderDialog.gd")


func _initialize() -> void:
	await process_frame
	var failures: Array[String] = []
	var scene := load("res://systems/ems/EMSCreator/EMSCreatorScene.tscn") as PackedScene
	if scene == null:
		failures.append("EMS Creator scene failed to load.")
		_finish(failures)
		return
	var creator := scene.instantiate()
	if creator is Control:
		(creator as Control).size = Vector2(1024, 615)
	root.add_child(creator)
	await process_frame
	await process_frame
	var property_panel := _find_by_script(creator, EMSPropertyPanelScript)
	var layer_list := _find_by_script(creator, EMSLayerListScript)
	var timeline := _find_by_script(creator, EMSTimelinePanelScript)
	var preview := _find_by_script(creator, EMSPreviewViewportScript)
	var builder := _find_by_script(creator, EMSLayerTypeBuilderDialogScript)
	if property_panel == null:
		failures.append("EMS property panel missing.")
	if layer_list == null:
		failures.append("EMS layer list missing.")
	if timeline == null:
		failures.append("EMS timeline panel missing.")
	if preview == null:
		failures.append("EMS preview viewport missing.")
	if builder == null:
		failures.append("EMS layer type builder missing.")
	if failures.is_empty():
		_verify_creator_layout(creator, failures)
		_verify_property_panel(creator, property_panel, timeline, failures)
		_verify_layer_list(layer_list, failures)
		_verify_timeline(timeline, failures)
		_verify_preview(preview, failures)
		_verify_builder(builder, failures)
	creator.queue_free()
	_finish(failures)


func _verify_property_panel(creator: Node, panel: Node, timeline: Node, failures: Array[String]) -> void:
	var before: Dictionary = panel.call("get_editor_debug_state") as Dictionary
	panel.call("set_numeric_value_for_test", "intensity", 1.37)
	var after: Dictionary = panel.call("get_editor_debug_state") as Dictionary
	if int(after.get("rebuild_count", 0)) != int(before.get("rebuild_count", 0)):
		failures.append("Slider value changes rebuilt the property panel.")
	if absf(float(after.get("intensity", 0.0)) - 1.37) > 0.001:
		failures.append("Intensity slider did not preserve a continuous value.")
	if not bool(after.get("has_layer_type_description", false)):
		failures.append("Property panel does not expose the selected layer type description.")
	_verify_creator_layer_type_visibility(after.get("layer_type_options", []) as Array, "Property panel", failures)
	panel.call("set_layer_name_for_test", "Renamed Aurora Layer")
	var renamed_panel_state: Dictionary = panel.call("get_editor_debug_state") as Dictionary
	if str(renamed_panel_state.get("name", "")) != "Renamed Aurora Layer":
		failures.append("Property panel did not rename the selected layer.")
	var renamed_creator_state: Dictionary = creator.call("get_creator_debug_state") as Dictionary
	var layer_names: Array = renamed_creator_state.get("layer_names", []) as Array
	if layer_names.is_empty() or not layer_names.has("Renamed Aurora Layer"):
		failures.append("Renaming a layer did not refresh the Layers panel state.")
	panel.call("set_player_reactive_for_test", "miss")
	var player_reactive_state: Dictionary = panel.call("get_editor_debug_state") as Dictionary
	if str(player_reactive_state.get("player_reactive", "")) != "miss":
		failures.append("Property panel did not preserve the exclusive Player Reactive mode.")
	var player_rule_state: Dictionary = timeline.call("get_debug_state") as Dictionary
	if str(player_rule_state.get("last_prefill_event", "")) != "player_miss":
		failures.append("Player Reactive selection did not open a prefilled miss event rule.")
	panel.call("set_audio_reactive_for_test", true)
	var audio_rule_state: Dictionary = timeline.call("get_debug_state") as Dictionary
	if str(audio_rule_state.get("last_prefill_event", "")) != "audio_reactive":
		failures.append("Audio Reactive toggle did not open a prefilled audio event rule.")
	if not bool(after.get("has_color_swatch", false)) or not bool(after.get("has_color_dialog", false)):
		failures.append("Primary color swatch or dialog missing.")
	if not bool(after.get("has_visible_accept_button", false)):
		failures.append("Primary color dialog is missing an always-visible accept button.")
	var original_color := str(after.get("color", ""))
	panel.call("preview_primary_color_for_test", Color(1.0, 0.0, 0.0, 1.0))
	panel.call("cancel_primary_color_for_test")
	var canceled: Dictionary = panel.call("get_editor_debug_state") as Dictionary
	if str(canceled.get("color", "")) != original_color:
		failures.append("Canceled color edit committed a layer color.")
	panel.call("preview_primary_color_for_test", Color(0.0, 1.0, 0.0, 1.0))
	panel.call("accept_primary_color_for_test")
	var accepted: Dictionary = panel.call("get_editor_debug_state") as Dictionary
	if str(accepted.get("color", "")).to_lower() != "#00ff00ff":
		failures.append("Accepted color edit did not commit the selected color.")
	panel.call("preview_primary_color_for_test", Color(0.0, 0.25, 1.0, 1.0))
	panel.call("outside_close_primary_color_for_test")
	var outside_closed: Dictionary = panel.call("get_editor_debug_state") as Dictionary
	if str(outside_closed.get("color", "")).to_lower() != "#0040ffff":
		failures.append("Outside-close color edit did not commit the selected color.")
	panel.call("simulate_stale_color_dialog_for_test")
	panel.call("open_primary_color_dialog_for_test")
	var reopened: Dictionary = panel.call("get_editor_debug_state") as Dictionary
	if not bool(reopened.get("has_color_dialog", false)) or not bool(reopened.get("has_visible_accept_button", false)):
		failures.append("Primary color dialog did not recover from a stale freed picker reference.")
	panel.call("hide_primary_color_dialog_for_test")


func _verify_creator_layout(creator: Node, failures: Array[String]) -> void:
	if not creator.has_method("get_creator_debug_state"):
		failures.append("EMS Creator is missing layout debug state.")
		return
	creator.call("set_layer_template_store_root_for_test", "user://ems/test_layer_types_%d" % Time.get_ticks_msec())
	var state: Dictionary = creator.call("get_creator_debug_state") as Dictionary
	if not bool(state.get("has_layout_controls", false)):
		failures.append("EMS Creator is missing pack-level layout controls.")
	if not bool(state.get("has_layout_scope_selector", false)):
		failures.append("EMS Creator is missing the EMS Layout scope selector.")
	if not bool(state.get("has_layout_gutter_target_selector", false)):
		failures.append("EMS Creator is missing the selected-layer gutter target selector.")
	if not bool(state.get("has_layout_mode_selector", false)):
		failures.append("EMS Creator is missing the panel Layout Mode selector.")
	if not bool(state.get("has_layout_reuse_selector", false)):
		failures.append("EMS Creator is missing the panel Reuse Layer selector.")
	if int(state.get("layout_value_label_count", 0)) < 6:
		failures.append("EMS Layout panel is missing X/Y/W/H/Scale/Rot labels.")
	if not bool(state.get("has_resizable_panel_splits", false)):
		failures.append("EMS Creator is missing draggable split panes for resizing panels.")
	creator.call("set_layout_for_test", "full_background", Vector2(0.62, 0.42), Vector2(0.78, 1.18), 1.35, 23.0)
	state = creator.call("get_creator_debug_state") as Dictionary
	var layout: Dictionary = state.get("layout", {}) as Dictionary
	if str(layout.get("background_region", "")) != "full_background":
		failures.append("EMS Creator layout mode did not switch to Full Background.")
	if absf(float(layout.get("scale", 0.0)) - 1.35) > 0.001 or absf(float(layout.get("rotation", 0.0)) - 23.0) > 0.001:
		failures.append("EMS Creator layout scale/rotation controls did not update.")
	if not bool(state.get("property_panel_visible", false)):
		failures.append("EMS Creator properties panel is not visible at the editor test size.")
	if not bool(state.get("property_panel_fits", false)):
		failures.append("EMS Creator properties panel is clipped by the right edge.")
	if float(state.get("property_panel_width", 0.0)) < 188.0:
		failures.append("EMS Creator properties panel was compressed below a usable width.")
	if not bool(state.get("property_panel_scrollable", false)):
		failures.append("EMS Creator properties panel does not provide scrolling for compact widths.")
	if not bool(state.get("footer_action_buttons_readable", false)):
		failures.append("EMS Creator footer action buttons were compressed until their labels disappeared.")
	if float(state.get("layer_list_width", 0.0)) > 245.0:
		failures.append("EMS Creator layer list consumed too much horizontal space.")
	creator.call("set_panel_widths_for_test", 206.0, 280.0)
	state = creator.call("get_creator_debug_state") as Dictionary
	if float(state.get("configured_property_panel_width", 0.0)) < 270.0:
		failures.append("EMS Creator property resize handle did not expand the Properties panel.")
	if float(state.get("configured_layer_panel_width", 0.0)) < 200.0:
		failures.append("EMS Creator layer resize handle did not preserve a usable Layers panel width.")
	creator.call("set_panel_widths_for_test", 206.0, 220.0)
	creator.call("simulate_property_resize_drag_for_test", 500.0, 440.0)
	state = creator.call("get_creator_debug_state") as Dictionary
	if float(state.get("configured_property_panel_width", 0.0)) < 275.0:
		failures.append("Dragging the Properties handle left did not expand the Properties panel.")
	if not bool(state.get("timeline_visible", false)):
		failures.append("EMS Creator Event Rules section is not visible with enough height.")
	if not bool(state.get("timeline_fits", false)):
		failures.append("EMS Creator Event Rules panel is clipped by the right edge.")
	var preview_size: Vector2 = state.get("preview_size", Vector2.ZERO)
	if preview_size.x < 320.0 or preview_size.y < 200.0:
		failures.append("EMS Creator preview area was too small after compact layout.")
	if not bool(state.get("has_layer_stack_dialog", false)):
		failures.append("EMS Creator is missing the Layer Stack dialog.")
	if not bool(state.get("has_layer_layout_dialog", false)):
		failures.append("EMS Creator is missing the per-layer EMS Layout dialog.")
	var template_result: Dictionary = creator.call("create_layer_template_for_test", "combo_aura", "Smoke Aura Type") as Dictionary
	if not bool(template_result.get("ok", false)):
		failures.append("EMS Creator did not save a reusable custom layer type.")
	state = creator.call("get_creator_debug_state") as Dictionary
	if int(state.get("saved_layer_template_count", 0)) < 1 or not (state.get("saved_layer_template_names", []) as Array).has("Smoke Aura Type"):
		failures.append("Saved custom layer type did not appear in the Creator template list.")
	var add_dialog_state: Dictionary = creator.call("open_add_layer_dialog_for_test") as Dictionary
	if str(add_dialog_state.get("mode", "")) != "add_layer" or not bool(add_dialog_state.get("starting_point_visible", false)):
		failures.append("Add Layer does not open the advanced layer selection/configuration dialog.")
	creator.call("set_layer_layout_for_test", 0, "custom", "", Vector2(0.32, 0.44), Vector2(0.62, 0.74), 1.42, -18.0)
	creator.call("set_layer_layout_for_test", 1, "reuse", "aurora_gradient", Vector2(0.50, 0.50), Vector2(1.0, 1.0), 1.0, 0.0)
	creator.call("reorder_layers_for_test", ["beat_particles", "aurora_gradient"])
	state = creator.call("get_creator_debug_state") as Dictionary
	var layer_order: Array = state.get("layer_order", []) as Array
	if layer_order.size() < 2 or str(layer_order[-1]) != "aurora_gradient":
		failures.append("EMS Creator layer stack did not move Aurora Gradient to the front.")
	var saw_custom_layout := false
	var saw_reused_layout := false
	for layer_layout in (state.get("layer_layouts", []) as Array):
		if layer_layout is not Dictionary:
			continue
		var layout_state := layer_layout as Dictionary
		if str(layout_state.get("id", "")) == "aurora_gradient":
			var layer_layout_config: Dictionary = layout_state.get("layout", {}) as Dictionary
			saw_custom_layout = str(layout_state.get("layout_mode", "")) == "custom" and absf(float(layer_layout_config.get("rotation", 0.0)) + 18.0) < 0.01
		if str(layout_state.get("id", "")) == "beat_particles":
			saw_reused_layout = str(layout_state.get("layout_mode", "")) == "reuse" and str(layout_state.get("layout_source", "")) == "aurora_gradient"
	if not saw_custom_layout:
		failures.append("EMS Creator did not store a custom per-layer layout.")
	if not saw_reused_layout:
		failures.append("EMS Creator did not store a reused per-layer layout source.")
	creator.call("select_layer_for_test", 1)
	creator.call("set_layout_scope_for_test", "selected_layer")
	state = creator.call("get_creator_debug_state") as Dictionary
	if str(state.get("layout_scope", "")) != "selected_layer":
		failures.append("EMS Layout scope selector did not switch to Selected Layer Layout.")
	if str(state.get("selected_layer_layout_mode", "")) != "custom" or not bool(state.get("layout_mode_selector_enabled", false)):
		failures.append("Selected Layer Layout did not switch the selected layer into Custom Layout mode.")
	var selected_preview: Dictionary = state.get("selected_layer_layout_preview", {}) as Dictionary
	if absf(float(selected_preview.get("rotation", 0.0)) + 18.0) > 0.01:
		failures.append("Selected Layer Layout scope did not display the selected layer's custom layout.")
	creator.call("set_layout_number_for_test", "rotation", 37.0)
	state = creator.call("get_creator_debug_state") as Dictionary
	var pack_layout_after_layer_edit: Dictionary = state.get("layout", {}) as Dictionary
	if absf(float(pack_layout_after_layer_edit.get("rotation", 0.0)) - 23.0) > 0.01:
		failures.append("Selected Layer Layout edit unexpectedly changed the pack EMS Layout.")
	var layer_scope_updated := false
	for layer_layout in (state.get("layer_layouts", []) as Array):
		if layer_layout is Dictionary and str((layer_layout as Dictionary).get("id", "")) == "aurora_gradient":
			var updated_layout: Dictionary = (layer_layout as Dictionary).get("layout", {}) as Dictionary
			layer_scope_updated = str((layer_layout as Dictionary).get("layout_mode", "")) == "custom" and absf(float(updated_layout.get("rotation", 0.0)) - 37.0) < 0.01
	if not layer_scope_updated:
		failures.append("Selected Layer Layout edit did not update the selected layer layout.")
	creator.call("set_layer_layout_for_test", 0, "custom", "", Vector2(0.24, 0.58), Vector2(0.44, 0.66), 0.82, 11.0)
	creator.call("set_panel_layer_reuse_source_for_test", "beat_particles")
	state = creator.call("get_creator_debug_state") as Dictionary
	if str(state.get("selected_layer_layout_mode", "")) != "reuse" or str(state.get("selected_layer_layout_source", "")) != "beat_particles":
		failures.append("EMS Layout panel Reuse Layer selector did not switch the selected layer to reused layout mode.")
	if not bool(state.get("layout_reuse_selector_enabled", false)):
		failures.append("EMS Layout panel did not enable the Reuse Layer dropdown in reused layout mode.")
	creator.call("set_panel_layer_layout_mode_for_test", "custom")
	state = creator.call("get_creator_debug_state") as Dictionary
	if str(state.get("selected_layer_layout_mode", "")) != "custom":
		failures.append("EMS Layout panel Layout Mode selector did not switch back to Custom Layout.")
	creator.call("set_layout_scope_for_test", "pack")
	state = creator.call("get_creator_debug_state") as Dictionary
	if str(state.get("selected_layer_layout_mode", "")) != "pack":
		failures.append("Switching back to EMS Layout did not set the selected layer to Use EMS Layout.")
	creator.call("set_layout_for_test", "gutters", Vector2(0.5, 0.5), Vector2(1.0, 1.0), 1.0, 0.0)
	creator.call("select_layer_for_test", 1)
	creator.call("set_layout_scope_for_test", "selected_layer")
	state = creator.call("get_creator_debug_state") as Dictionary
	if not bool(state.get("layout_gutter_target_selector_visible", false)):
		failures.append("Selected Layer Layout did not show the gutter target selector in Two Gutters mode.")
	creator.call("set_selected_layer_gutter_target_for_test", "right")
	state = creator.call("get_creator_debug_state") as Dictionary
	if str(state.get("selected_layer_gutter_target", "")) != "right":
		failures.append("Selected Layer Layout gutter target did not update to Right Gutter Only.")
	var saw_right_target := false
	for layer_layout in (state.get("layer_layouts", []) as Array):
		if layer_layout is Dictionary and str((layer_layout as Dictionary).get("id", "")) == "aurora_gradient":
			saw_right_target = str((layer_layout as Dictionary).get("gutter_target", "")) == "right"
	if not saw_right_target:
		failures.append("Selected layer did not store its right-gutter target.")
	creator.call("set_layout_scope_for_test", "pack")
	creator.call("set_layout_for_test", "full_background", Vector2(0.62, 0.42), Vector2(0.78, 1.18), 1.35, 23.0)
	creator.call("set_layout_number_for_test", "scale", 1.12)
	state = creator.call("get_creator_debug_state") as Dictionary
	var pack_layout_after_pack_edit: Dictionary = state.get("layout", {}) as Dictionary
	if str(state.get("layout_scope", "")) != "pack" or absf(float(pack_layout_after_pack_edit.get("scale", 0.0)) - 1.12) > 0.01:
		failures.append("EMS Layout scope selector did not return to pack EMS Layout editing.")
	var template: Dictionary = template_result.get("template", {}) as Dictionary
	var add_template_result: Dictionary = creator.call("add_layer_from_template_for_test", str(template.get("template_id", "")), "Smoke Aura Instance") as Dictionary
	if not bool(add_template_result.get("ok", false)):
		failures.append("EMS Creator could not add a layer from a saved custom layer type.")
	state = creator.call("get_creator_debug_state") as Dictionary
	if not (state.get("layer_names", []) as Array).has("Smoke Aura Instance"):
		failures.append("Layer added from saved custom type did not preserve the requested layer name.")


func _verify_layer_list(layer_list: Node, failures: Array[String]) -> void:
	var many_layers: Array[Dictionary] = []
	for i in range(40):
		many_layers.append({"id": "layer_%d" % i, "type": "particles", "name": "Layer %d" % i})
	layer_list.call("set_layers", many_layers, 0)
	var state: Dictionary = layer_list.call("get_debug_state") as Dictionary
	if not bool(state.get("scrollable", false)):
		failures.append("Layer list is not wrapped in a scroll container.")
	if int(state.get("row_count", 0)) != 40:
		failures.append("Layer list did not render all test rows.")
	var action_texts: Array = state.get("first_row_action_texts", []) as Array
	var action_tooltips: Array = state.get("first_row_action_tooltips", []) as Array
	if action_texts.size() < 4 or str(action_texts[0]) == "UP" or str(action_texts[1]) == "DN" or str(action_texts[2]) == "DUP" or str(action_texts[3]) == "DEL":
		failures.append("Layer row action buttons still use full text instead of compact icons.")
	if action_texts.size() < 4 or str(action_texts[0]) != "^" or str(action_texts[1]) != "v" or str(action_texts[2]) != "+" or str(action_texts[3]) != "x":
		failures.append("Layer row action icons are not using portable ASCII symbols.")
	if action_tooltips.size() < 4 or str(action_tooltips[0]) != "Move Up" or str(action_tooltips[1]) != "Move Down" or str(action_tooltips[2]) != "Duplicate" or str(action_tooltips[3]) != "Delete":
		failures.append("Layer row icon buttons do not expose action names through tooltips.")


func _verify_timeline(timeline: Node, failures: Array[String]) -> void:
	var rules: Array[Dictionary] = []
	var actions: Array = EMSValidator.ALLOWED_ACTIONS
	for i in range(actions.size()):
		rules.append({
			"event": EMSValidator.ALLOWED_EVENTS[i % EMSValidator.ALLOWED_EVENTS.size()],
			"action": str(actions[i]),
			"target": "*",
			"params": _params_for_action(str(actions[i])),
			"threshold": 0.0,
			"cooldown": 0.0,
		})
	timeline.call("set_events", rules, ["*", "layer_0"])
	var state: Dictionary = timeline.call("get_debug_state") as Dictionary
	if not bool(state.get("has_add_new_rule", false)):
		failures.append("Timeline is missing ADD NEW RULE button.")
	if not bool(state.get("has_dialog", false)):
		failures.append("Timeline is missing configurable rule dialog.")
	if not bool(state.get("has_chart_reactive_event", false)) or not bool(state.get("has_audio_reactive_event", false)):
		failures.append("Timeline event list is missing Chart Reactive or Audio Reactive.")
	if not bool(state.get("horizontal_scrollable", false)):
		failures.append("Timeline rows do not provide horizontal scrolling for long event rules.")
	if int(state.get("event_count", 0)) != EMSValidator.ALLOWED_ACTIONS.size():
		failures.append("Timeline did not retain all action rule shapes.")


func _verify_preview(preview: Node, failures: Array[String]) -> void:
	var initial_state: Dictionary = preview.call("get_preview_debug_state") as Dictionary
	var preview_panel_size: Vector2 = initial_state.get("preview_panel_size", Vector2.ZERO)
	var runtime_canvas_size: Vector2 = initial_state.get("preview_canvas_size", Vector2.ZERO)
	if preview_panel_size.x < 1.0 or preview_panel_size.y < 1.0 or runtime_canvas_size.distance_to(preview_panel_size) > 1.0:
		failures.append("EMS Preview runtime is not constrained to the center preview panel size.")
	var runtime_layout: Dictionary = initial_state.get("layout", {}) as Dictionary
	if str(runtime_layout.get("background_region", "")) != "full_background":
		failures.append("EMS Preview runtime did not apply the selected Full Background layout.")
	if not bool(initial_state.get("preview_has_chart_highway", false)):
		failures.append("EMS Preview did not draw the gameplay chart highway overlay.")
	var layout_transform: Dictionary = initial_state.get("layout_transform", {}) as Dictionary
	if absf(float(layout_transform.get("rotation", 0.0)) - 23.0) > 0.5:
		failures.append("EMS Preview runtime did not apply layout rotation.")
	for layer_state in (initial_state.get("layers", []) as Array):
		if layer_state is Dictionary and str((layer_state as Dictionary).get("type", "")) == "gradient":
			if str((layer_state as Dictionary).get("gradient_render_mode", "")) != "smooth_polygon":
				failures.append("Gradient preview is not using the smooth gradient renderer.")
			if int((layer_state as Dictionary).get("gradient_band_count", 0)) != 0:
				failures.append("Gradient preview still exposes CRT scanline bands.")
	preview.call("simulate_event", "combo_milestone", 1.0)
	var state: Dictionary = preview.call("get_preview_debug_state") as Dictionary
	if str(state.get("last_event", "")) != "combo_milestone":
		failures.append("Preview simulation did not dispatch the event.")
	preview.call("set_preview_playing", false)
	if bool(preview.call("is_preview_playing")):
		failures.append("Preview play/pause state did not update.")
	preview.call("load_preview_config", _preview_config("gutters"))
	state = preview.call("get_preview_debug_state") as Dictionary
	if str(state.get("preview_region_mode", "")) != "gutters":
		failures.append("EMS Preview did not switch to Two Gutters mode.")
	if not bool(state.get("preview_right_runtime_active", false)):
		failures.append("EMS Preview did not create a right gutter runtime.")
	var gutter_canvas: Vector2 = state.get("preview_canvas_size", Vector2.ZERO)
	if gutter_canvas.x >= preview_panel_size.x * 0.6:
		failures.append("EMS Preview Two Gutters mode still used a full-width runtime.")
	var right_runtime: Dictionary = state.get("right_runtime", {}) as Dictionary
	var right_canvas: Vector2 = right_runtime.get("preview_canvas_size", Vector2.ZERO)
	if right_canvas.distance_to(gutter_canvas) > 1.0:
		failures.append("EMS Preview left and right gutter runtimes do not match sizes.")
	if int(right_runtime.get("layer_count", 0)) <= 0:
		failures.append("EMS Preview right gutter runtime did not render a both-gutters layer.")
	preview.call("load_preview_config", _preview_config("gutters", "right"))
	preview.call("simulate_event", "miss", 1.0)
	state = preview.call("get_preview_debug_state") as Dictionary
	right_runtime = state.get("right_runtime", {}) as Dictionary
	if int(state.get("layer_count", -1)) != 0 or int(right_runtime.get("layer_count", 0)) <= 0:
		failures.append("EMS Preview did not isolate a Right Gutter Only layer to the right runtime.")
	var right_runtime_position: Vector2 = state.get("preview_right_runtime_position", Vector2.ZERO)
	if right_runtime_position.x <= preview_panel_size.x * 0.5:
		failures.append("EMS Preview right gutter runtime was reset back to the left side after update.")


func _verify_builder(builder: Node, failures: Array[String]) -> void:
	var state: Dictionary = builder.call("get_debug_state") as Dictionary
	if not bool(state.get("has_type_option", false)) or not bool(state.get("has_motion_controls", false)) or not bool(state.get("has_performance_controls", false)) or not bool(state.get("has_player_reactive", false)):
		failures.append("Layer Type Builder is missing required no-code controls.")
	if not bool(state.get("has_layer_type_description", false)):
		failures.append("Layer Type Builder does not expose layer type descriptions.")
	_verify_creator_layer_type_visibility(state.get("base_layer_types", []) as Array, "Layer Type Builder base renderer", failures)
	_verify_creator_layer_type_visibility(state.get("starting_point_types", []) as Array, "Layer Type Builder starting point", failures)
	builder.call("open_add_layer", [])
	state = builder.call("get_debug_state") as Dictionary
	if str(state.get("mode", "")) != "add_layer" or not bool(state.get("starting_point_visible", false)):
		failures.append("Layer Type Builder did not expose Add Layer starting-point selection.")
	_verify_creator_layer_type_visibility(state.get("starting_point_types", []) as Array, "Layer Type Builder add-layer starting point", failures)
	builder.call("open_create_type", [])
	state = builder.call("get_debug_state") as Dictionary
	if str(state.get("mode", "")) != "create_type" or bool(state.get("starting_point_visible", true)):
		failures.append("Create Type mode did not switch the builder into reusable template mode.")
	_verify_creator_layer_type_visibility(state.get("base_layer_types", []) as Array, "Layer Type Builder create-type base renderer", failures)
	var particle_defaults: Dictionary = {}
	var starfield_defaults: Dictionary = {}
	for layer_type in _creator_visible_layer_types():
		var layer: Dictionary = builder.call("create_layer_for_test", layer_type) as Dictionary
		var builder_state: Dictionary = builder.call("get_debug_state") as Dictionary
		var visible_controls: Array = builder_state.get("visible_numeric_controls", []) as Array
		if layer_type == "particles" and (not visible_controls.has("particle_count") or visible_controls.has("shake")):
			failures.append("Builder did not switch to Particles specific controls.")
		if layer_type == "particles":
			particle_defaults = layer.duplicate(true)
			if int(layer.get("particle_count", 0)) > 90 or float(layer.get("scale", 1.0)) >= 0.70:
				failures.append("Builder particles defaults are still too large/generic.")
		if layer_type == "starfield":
			starfield_defaults = layer.duplicate(true)
			if int(layer.get("particle_count", 0)) < 120 or float(layer.get("speed", 0.0)) <= float(particle_defaults.get("speed", 0.0)):
				failures.append("Builder starfield defaults do not create a distinct depth starfield.")
		if layer_type in ["beat_pulse", "combo_aura"]:
			if int(layer.get("particle_count", 0)) != 0:
				failures.append("Builder %s defaults should not rely on particle pools." % layer_type)
		if str(layer.get("player_reactive", "")) not in EMSValidator.ALLOWED_PLAYER_REACTIVE_MODES:
			failures.append("Builder emitted invalid Player Reactive mode for %s." % layer_type)
		for forbidden in ["script", "code", "shader", "scene", "resource", "path"]:
			if layer.has(forbidden):
				failures.append("Builder emitted forbidden field %s for %s." % [forbidden, layer_type])
		var config := {
			"schema_version": 1,
			"pack_type": EMSValidator.PACK_TYPE_CONFIG,
			"pack_id": "builder_%s" % layer_type,
			"title": "Builder %s" % layer_type,
			"author": "Test",
			"description": "Builder smoke.",
			"layers": [layer],
			"events": [],
			"palette": {"colors": ["#55DFFFFF"], "morph": "smooth", "speed": 0.2},
			"performance": {"motion_intensity": 0.7, "particle_intensity": 0.5, "audio_reactive": true, "estimated_cost": 0.4},
		}
		var validated := EMSValidator.validate_config(config)
		if not (validated.get("_validation_errors", []) as Array).is_empty():
			failures.append("Builder generated invalid layer for %s: %s" % [layer_type, "; ".join(validated.get("_validation_errors", []) as Array)])
	if not particle_defaults.is_empty() and not starfield_defaults.is_empty():
		if int(particle_defaults.get("particle_count", 0)) == int(starfield_defaults.get("particle_count", 0)):
			failures.append("Builder particles and starfield defaults still use the same particle density.")
	for hidden_type in _future_signature_types():
		if not EMSValidator.ALLOWED_LAYER_TYPES.has(hidden_type):
			failures.append("Hidden future signature should remain validator-allowed for compatibility: %s." % hidden_type)


func _params_for_action(action: String) -> Dictionary:
	match action:
		"set_opacity", "pulse_opacity":
			return {"opacity": 0.9, "duration": 0.12}
		"set_color":
			return {"color": "#55DFFFFF"}
		"pulse_scale":
			return {"scale": 1.2, "duration": 0.12}
		"burst_particles":
			return {"count": 12}
		"increase_bloom", "increase_distortion", "shake_camera":
			return {"amount": 0.1}
		"transition_palette":
			return {"colors": ["#55DFFFFF", "#FF4DE1FF"]}
		_:
			return {}


func _preview_config(region: String, gutter_target: String = "both") -> Dictionary:
	return {
		"schema_version": 1,
		"pack_type": EMSValidator.PACK_TYPE_CONFIG,
		"pack_id": "preview_%s" % region,
		"title": "Preview %s" % region,
		"author": "Test",
		"description": "Preview smoke.",
		"layers": [
			{"id": "preview_gradient", "type": "gradient", "name": "Preview Gradient", "opacity": 0.75, "color": "#55DFFFFF", "colors": ["#55DFFFFF", "#FF4DE1FF"], "speed": 0.2, "reactive": true, "player_reactive": "off", "gutter_target": gutter_target},
		],
		"events": [],
		"layout": {"background_region": region, "position": [0.5, 0.5], "size": [1.0, 1.0], "scale": 1.0, "rotation": 0.0},
		"palette": {"colors": ["#55DFFFFF", "#FF4DE1FF"], "morph": "smooth", "speed": 0.2},
		"performance": {"motion_intensity": 0.7, "particle_intensity": 0.3, "audio_reactive": true, "estimated_cost": 0.2},
	}


func _find_by_script(node: Node, script: Script) -> Node:
	if node.get_script() == script:
		return node
	for child in node.get_children():
		var found := _find_by_script(child, script)
		if found != null:
			return found
	return null


func _creator_visible_layer_types() -> Array[String]:
	var values: Array[String] = []
	for layer_type in EMSValidator.ALLOWED_LAYER_TYPES:
		if EMSLoadoutCatalog.is_layer_type_content_available(layer_type):
			values.append(layer_type)
	return values


func _future_signature_types() -> Array[String]:
	return [
		"signature_thunder_matrix",
		"signature_chromatic_rift",
		"signature_skyline_mirage",
		"signature_crystal_reactor",
		"signature_gravity_well",
		"signature_hypernova_flow",
		"signature_singularity_bloom",
	]


func _verify_creator_layer_type_visibility(options: Array, label: String, failures: Array[String]) -> void:
	var option_values: Array[String] = []
	for option in options:
		option_values.append(str(option))
	for hidden_type in _future_signature_types():
		if option_values.has(hidden_type):
			failures.append("%s should hide unavailable future signature type %s." % [label, hidden_type])
	for visible_type in ["signature_pixel_nebula", "particles", "gradient"]:
		if not option_values.has(visible_type):
			failures.append("%s should include visible layer type %s." % [label, visible_type])


func _finish(failures: Array[String]) -> void:
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("EMS Creator usability smoke test passed.")
	quit(0)
