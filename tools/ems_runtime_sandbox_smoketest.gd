extends SceneTree

const EMSRuntime := preload("res://systems/ems/EMSRuntime.gd")
const EMSSandboxNode := preload("res://systems/ems/EMSSandboxNode.gd")
const EMSValidator := preload("res://systems/ems/EMSValidator.gd")


func _initialize() -> void:
	await process_frame
	var failures: Array[String] = []
	var runtime := EMSRuntime.new()
	root.add_child(runtime)
	var config := _all_layer_config()
	runtime.load_config(config)
	for event_name in EMSValidator.ALLOWED_EVENTS:
		runtime.dispatch_event(event_name, {"strength": 1.0, "value": 50})
	for i in range(4):
		runtime.update_runtime({"intensity": 0.8, "combo": 0.7, "bpm": 150.0, "density": 0.4, "motion_scale": 1.0}, 0.016)
		await process_frame
	var state := runtime.get_debug_state()
	if int(state.get("layer_count", 0)) != EMSValidator.ALLOWED_LAYER_TYPES.size():
		failures.append("Runtime did not create all allowed EMS layer types.")
	if str(state.get("last_event", "")) != str(EMSValidator.ALLOWED_EVENTS[-1]):
		failures.append("Runtime did not process every declared EMS event.")
	if int(state.get("event_count", 0)) < EMSValidator.ALLOWED_ACTIONS.size():
		failures.append("Runtime config did not include every declared EMS action.")
	var layout: Dictionary = state.get("layout", {}) as Dictionary
	if str(layout.get("background_region", "")) != "full_background":
		failures.append("Runtime did not preserve the EMS layout background region.")
	var layout_transform: Dictionary = state.get("layout_transform", {}) as Dictionary
	if absf(float(layout_transform.get("rotation", 0.0)) - 17.0) > 0.5:
		failures.append("Runtime did not apply the EMS layout rotation.")
	var saw_chart_reaction := false
	var saw_hit_reaction := false
	var saw_miss_reaction := false
	var saw_smooth_gradient := false
	var saw_crt_gradient := false
	var saw_custom_layer_layout := false
	var saw_reused_layer_layout := false
	var expected_families := {
		"combo_aura": "combo_aura_halos",
		"beat_pulse": "beat_pulse_waves",
		"particles": "neon_particles",
		"starfield": "depth_starfield",
		"image": "image_media",
		"video": "video_media",
	}
	var expected_signature_families := {
		"signature_neon_rain": "neon_raindrops",
		"signature_plasma_storm": "plasma_cells",
		"signature_quantum_grid": "quantum_lattice",
		"signature_aurora_drive": "aurora_curtains",
		"signature_fractal_space": "fractal_portals",
		"signature_prism_circuit": "prism_circuitry",
		"signature_solar_bloom": "solar_corona",
	}
	var seen_families := {}
	for layer_state in (state.get("layers", []) as Array):
		var layer_debug := layer_state as Dictionary
		var layer_type := str(layer_debug.get("type", ""))
		if float(layer_debug.get("normal_motion", 0.0)) <= 0.0:
			failures.append("Layer %s did not advance baseline animation." % str(layer_debug.get("id", "")))
		if expected_families.has(layer_type):
			seen_families[layer_type] = true
			if str(layer_debug.get("renderer_family", "")) != str(expected_families[layer_type]):
				failures.append("Layer %s did not expose renderer family %s." % [layer_type, str(expected_families[layer_type])])
			if int(layer_debug.get("visual_activity", 0)) <= 0:
				failures.append("Layer %s did not expose a non-empty visual draw state." % layer_type)
			var profile: Dictionary = layer_debug.get("particle_size_profile", {}) as Dictionary
			if layer_type == "particles" and float(profile.get("max", 99.0)) > 2.0:
				failures.append("Particles layer still defaults to oversized circle particles.")
			if layer_type == "starfield" and float(profile.get("max", 99.0)) > 1.6:
				failures.append("Starfield layer still uses particle-sized circles instead of small stars.")
		if layer_type.begins_with("signature_"):
			if not bool(layer_debug.get("signature_embedded", false)):
				failures.append("Built-in signature layer %s did not embed the loadout signature renderer." % layer_type)
			if expected_signature_families.has(layer_type) and str(layer_debug.get("renderer_family", "")) != str(expected_signature_families[layer_type]):
				failures.append("Built-in signature layer %s did not expose the loadout render family %s." % [layer_type, str(expected_signature_families[layer_type])])
			if int(layer_debug.get("visual_activity", 0)) <= 0:
				failures.append("Built-in signature layer %s did not expose a non-empty visual draw state." % layer_type)
		if float(layer_debug.get("chart_reaction", 0.0)) > 0.0:
			saw_chart_reaction = true
		if float(layer_debug.get("hit_reaction", 0.0)) > 0.0:
			saw_hit_reaction = true
		if float(layer_debug.get("miss_reaction", 0.0)) > 0.0:
			saw_miss_reaction = true
		if layer_type == "gradient":
			saw_smooth_gradient = str(layer_debug.get("gradient_render_mode", "")) == "smooth_polygon" and int(layer_debug.get("gradient_band_count", 0)) == 0
		if layer_type == "crt_gradient":
			saw_crt_gradient = str(layer_debug.get("gradient_render_mode", "")) == "crt_scanlines" and int(layer_debug.get("gradient_band_count", 0)) >= 96
		if str(layer_debug.get("id", "")) == "layer_0":
			var effective_layout: Dictionary = layer_debug.get("effective_layout", {}) as Dictionary
			saw_custom_layer_layout = str(effective_layout.get("mode", "")) == "custom" and absf(float(effective_layout.get("rotation", 0.0)) - 31.0) < 0.5
		if str(layer_debug.get("id", "")) == "layer_1":
			var reused_layout: Dictionary = layer_debug.get("effective_layout", {}) as Dictionary
			saw_reused_layer_layout = str(reused_layout.get("mode", "")) == "reuse" and str(reused_layout.get("source", "")) == "layer_0" and absf(float(reused_layout.get("rotation", 0.0)) - 31.0) < 0.5
	if not saw_chart_reaction:
		failures.append("Audio Reactive layers did not respond to chart/song events.")
	if not saw_hit_reaction:
		failures.append("Player Reactive hit layers did not respond to successful hit events.")
	if not saw_miss_reaction:
		failures.append("Player Reactive miss layers did not respond to miss events.")
	if not saw_smooth_gradient:
		failures.append("Smooth gradient renderer still exposed CRT scanline bands.")
	if not saw_crt_gradient:
		failures.append("CRT gradient renderer did not expose the preserved scanline gradient.")
	if not saw_custom_layer_layout:
		failures.append("Runtime did not apply a custom per-layer EMS layout.")
	if not saw_reused_layer_layout:
		failures.append("Runtime did not reuse another layer's EMS layout.")
	for expected_type in expected_families.keys():
		if not seen_families.has(expected_type):
			failures.append("Runtime did not create upgraded renderer family for %s." % str(expected_type))
	var calm_starfield := EMSRuntime.new()
	root.add_child(calm_starfield)
	calm_starfield.load_config(_single_layer_config("calm_starfield", "starfield", 120))
	calm_starfield.update_runtime({"intensity": 0.8, "combo": 0.7, "bpm": 150.0, "density": 0.4, "motion_scale": 1.0}, 0.016)
	await process_frame
	var calm_state := calm_starfield.get_debug_state()
	var calm_warp := _layer_value(calm_state, "calm_starfield", "starfield_warp")
	if calm_warp > 0.001:
		failures.append("Starfield warp activated without a chart/player reaction.")
	calm_starfield.dispatch_event("beat", {"strength": 1.0})
	calm_starfield.update_runtime({"intensity": 0.8, "combo": 0.7, "bpm": 150.0, "density": 0.4, "motion_scale": 1.0}, 0.016)
	await process_frame
	var reactive_warp := _layer_value(calm_starfield.get_debug_state(), "calm_starfield", "starfield_warp")
	if reactive_warp <= 0.001:
		failures.append("Starfield warp did not activate after a chart reaction.")
	var workshop_metadata_runtime := EMSRuntime.new()
	root.add_child(workshop_metadata_runtime)
	var workshop_metadata_config := _single_layer_config("workshop_metadata_layer", "gradient", 0)
	workshop_metadata_config["_pack_folder"] = "user://ems/workshop/123456789"
	workshop_metadata_config["_workshop_item_id"] = "123456789"
	workshop_metadata_runtime.load_config(workshop_metadata_config)
	var workshop_metadata_state := workshop_metadata_runtime.get_debug_state()
	if int(workshop_metadata_state.get("layer_count", 0)) != 1:
		failures.append("Runtime rejected a valid Workshop EMS config that contained internal loader metadata.")
	var gated_runtime := EMSRuntime.new()
	root.add_child(gated_runtime)
	gated_runtime.load_config(_reactivity_gate_config())
	gated_runtime.dispatch_event("beat", {"strength": 1.0})
	gated_runtime.dispatch_event("player_hit", {"strength": 1.0})
	gated_runtime.dispatch_event("player_miss", {"strength": 1.0})
	gated_runtime.update_runtime({"intensity": 0.6, "combo": 0.5, "bpm": 128.0, "density": 0.3, "motion_scale": 1.0}, 0.016)
	await process_frame
	_verify_reactivity_gates(gated_runtime.get_debug_state(), failures)
	var right_filtered_runtime := EMSRuntime.new()
	root.add_child(right_filtered_runtime)
	right_filtered_runtime.set_gutter_filter("right")
	right_filtered_runtime.load_config(_gutter_target_config())
	right_filtered_runtime.update_runtime({"intensity": 0.5, "combo": 0.4, "bpm": 128.0, "density": 0.3, "motion_scale": 1.0}, 0.016)
	await process_frame
	_verify_gutter_filter(right_filtered_runtime.get_debug_state(), "right", failures)
	var left_filtered_runtime := EMSRuntime.new()
	root.add_child(left_filtered_runtime)
	left_filtered_runtime.set_gutter_filter("left")
	left_filtered_runtime.load_config(_gutter_target_config())
	left_filtered_runtime.update_runtime({"intensity": 0.5, "combo": 0.4, "bpm": 128.0, "density": 0.3, "motion_scale": 1.0}, 0.016)
	await process_frame
	_verify_gutter_filter(left_filtered_runtime.get_debug_state(), "left", failures)
	for child in runtime.get_children():
		if child.get_parent() != runtime:
			failures.append("Runtime generated a visual node outside the sandbox runtime.")
	var sandbox := EMSSandboxNode.new()
	root.add_child(sandbox)
	await process_frame
	var sandbox_state := sandbox.get_debug_state()
	if sandbox_state.get("active", false) and not sandbox_state.has("layer_count"):
		failures.append("Sandbox debug state was malformed.")
	runtime.queue_free()
	calm_starfield.queue_free()
	workshop_metadata_runtime.queue_free()
	gated_runtime.queue_free()
	right_filtered_runtime.queue_free()
	left_filtered_runtime.queue_free()
	sandbox.queue_free()
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("EMS runtime sandbox smoke test passed.")
	quit(0)


func _all_layer_config() -> Dictionary:
	var types: Array = EMSValidator.ALLOWED_LAYER_TYPES
	var layers: Array[Dictionary] = []
	for i in range(types.size()):
		var player_mode := "off"
		if i % 5 == 1:
			player_mode = "hit"
		elif i % 5 == 3:
			player_mode = "miss"
		layers.append({"id": "layer_%d" % i, "type": types[i], "name": types[i], "opacity": 0.65, "color": "#55DFFFFF", "colors": ["#55DFFFFF", "#FF4DE1FF", "#FFE66DFF"], "particle_count": 20 if types[i] in ["starfield", "particles", "floating_shapes"] else 0, "speed": 0.2, "reactive": true, "player_reactive": player_mode})
	if layers.size() >= 2:
		layers[0]["layout_mode"] = "custom"
		layers[0]["layout"] = {"position": [0.34, 0.46], "size": [0.58, 0.72], "scale": 1.45, "rotation": 31.0}
		layers[1]["layout_mode"] = "reuse"
		layers[1]["layout_source"] = "layer_0"
	return {
		"schema_version": 1,
		"pack_type": "ems_config",
		"pack_id": "runtime_all_layers",
		"title": "Runtime All Layers",
		"author": "Test",
		"description": "Runtime smoke pack.",
		"layers": layers,
		"events": [
			{"event": "song_started", "action": "set_opacity", "target": "*", "params": {"opacity": 0.75}},
			{"event": "song_section_changed", "action": "set_color", "target": "*", "params": {"color": "#FF4DE1FF"}},
			{"event": "beat", "action": "pulse_opacity", "target": "*", "params": {"opacity": 0.95, "duration": 0.1}},
			{"event": "bass_hit", "action": "pulse_scale", "target": "*", "params": {"scale": 1.18, "duration": 0.1}},
			{"event": "combo_changed", "action": "increase_bloom", "target": "*", "params": {"amount": 0.15}},
			{"event": "combo_milestone", "action": "burst_particles", "target": "*", "params": {"count": 12}},
			{"event": "miss", "action": "shake_camera", "target": "*", "params": {"amount": 0.12}},
			{"event": "near_miss", "action": "increase_distortion", "target": "*", "params": {"amount": 0.08}},
			{"event": "player_hit", "action": "disable_layer", "target": "*", "params": {}},
			{"event": "fever_started", "action": "enable_layer", "target": "*", "params": {}},
			{"event": "fever_ended", "action": "transition_palette", "target": "*", "params": {"colors": ["#55DFFFFF", "#FFE66DFF"]}},
			{"event": "song_ended", "action": "set_opacity", "target": "*", "params": {"opacity": 0.72}},
		],
		"layout": {"background_region": "full_background", "position": [0.42, 0.58], "size": [0.80, 1.20], "scale": 1.25, "rotation": 17.0},
		"palette": {"colors": ["#55DFFFFF", "#FF4DE1FF", "#FFE66DFF"], "morph": "smooth", "speed": 0.2},
		"performance": {"motion_intensity": 0.7, "particle_intensity": 0.4, "audio_reactive": true, "estimated_cost": 0.35},
	}


func _single_layer_config(layer_id: String, layer_type: String, particles: int) -> Dictionary:
	return {
		"schema_version": 1,
		"pack_type": "ems_config",
		"pack_id": "runtime_single_%s" % layer_type,
		"title": "Runtime Single %s" % layer_type,
		"author": "Test",
		"description": "Runtime single-layer smoke pack.",
		"layers": [{"id": layer_id, "type": layer_type, "name": layer_type, "opacity": 0.65, "color": "#55DFFFFF", "colors": ["#55DFFFFF", "#FF4DE1FF", "#FFE66DFF"], "particle_count": particles, "speed": 0.58, "reactive": true, "player_reactive": "off"}],
		"events": [],
		"layout": {"background_region": "full_background", "position": [0.5, 0.5], "size": [1.0, 1.0], "scale": 1.0, "rotation": 0.0},
		"palette": {"colors": ["#55DFFFFF", "#FF4DE1FF", "#FFE66DFF"], "morph": "smooth", "speed": 0.2},
		"performance": {"motion_intensity": 0.7, "particle_intensity": 0.4, "audio_reactive": true, "estimated_cost": 0.35},
	}


func _layer_value(state: Dictionary, layer_id: String, key: String) -> float:
	for layer_state in (state.get("layers", []) as Array):
		var debug := layer_state as Dictionary
		if str(debug.get("id", "")) == layer_id:
			return float(debug.get(key, 0.0))
	return 0.0


func _reactivity_gate_config() -> Dictionary:
	return {
		"schema_version": 1,
		"pack_type": "ems_config",
		"pack_id": "runtime_reactivity_gates",
		"title": "Runtime Reactivity Gates",
		"author": "Test",
		"description": "Runtime reactivity gate smoke pack.",
		"layers": [
			{"id": "audio_off", "type": "gradient", "name": "Audio Off", "opacity": 0.65, "color": "#55DFFFFF", "colors": ["#55DFFFFF", "#FF4DE1FF"], "speed": 0.2, "reactive": false, "player_reactive": "off"},
			{"id": "hit_only", "type": "particles", "name": "Hit Only", "opacity": 0.65, "color": "#55DFFFFF", "colors": ["#55DFFFFF", "#FF4DE1FF"], "particle_count": 8, "speed": 0.2, "reactive": false, "player_reactive": "hit"},
			{"id": "miss_only", "type": "floating_shapes", "name": "Miss Only", "opacity": 0.65, "color": "#55DFFFFF", "colors": ["#55DFFFFF", "#FF4DE1FF"], "particle_count": 8, "speed": 0.2, "reactive": false, "player_reactive": "miss"},
		],
		"events": [],
		"palette": {"colors": ["#55DFFFFF", "#FF4DE1FF"], "morph": "smooth", "speed": 0.2},
		"performance": {"motion_intensity": 0.7, "particle_intensity": 0.4, "audio_reactive": true, "estimated_cost": 0.2},
	}


func _gutter_target_config() -> Dictionary:
	return {
		"schema_version": 1,
		"pack_type": "ems_config",
		"pack_id": "runtime_gutter_targets",
		"title": "Runtime Gutter Targets",
		"author": "Test",
		"description": "Runtime gutter target smoke pack.",
		"layers": [
			{"id": "both_layer", "type": "gradient", "name": "Both", "opacity": 0.65, "color": "#55DFFFFF", "colors": ["#55DFFFFF", "#FF4DE1FF"], "speed": 0.2, "reactive": true, "player_reactive": "off", "gutter_target": "both"},
			{"id": "left_layer", "type": "particles", "name": "Left", "opacity": 0.65, "color": "#55DFFFFF", "colors": ["#55DFFFFF", "#FF4DE1FF"], "particle_count": 8, "speed": 0.2, "reactive": true, "player_reactive": "off", "gutter_target": "left"},
			{"id": "right_layer", "type": "floating_shapes", "name": "Right", "opacity": 0.65, "color": "#55DFFFFF", "colors": ["#55DFFFFF", "#FF4DE1FF"], "particle_count": 8, "speed": 0.2, "reactive": true, "player_reactive": "off", "gutter_target": "right"},
		],
		"events": [],
		"layout": {"background_region": "gutters", "position": [0.5, 0.5], "size": [1.0, 1.0], "scale": 1.0, "rotation": 0.0},
		"palette": {"colors": ["#55DFFFFF", "#FF4DE1FF"], "morph": "smooth", "speed": 0.2},
		"performance": {"motion_intensity": 0.7, "particle_intensity": 0.4, "audio_reactive": true, "estimated_cost": 0.2},
	}


func _verify_gutter_filter(state: Dictionary, side: String, failures: Array[String]) -> void:
	if str(state.get("gutter_filter", "")) != side:
		failures.append("Runtime did not preserve %s gutter filter." % side)
	var ids := {}
	for layer_state in (state.get("layers", []) as Array):
		var debug := layer_state as Dictionary
		ids[str(debug.get("id", ""))] = str(debug.get("gutter_target", ""))
	if not ids.has("both_layer"):
		failures.append("%s gutter filter removed a both-gutters layer." % side.capitalize())
	if side == "right":
		if ids.has("left_layer") or not ids.has("right_layer"):
			failures.append("Right gutter filter did not isolate right-targeted layers.")
	else:
		if ids.has("right_layer") or not ids.has("left_layer"):
			failures.append("Left gutter filter did not isolate left-targeted layers.")


func _verify_reactivity_gates(state: Dictionary, failures: Array[String]) -> void:
	var by_id := {}
	for layer_state in (state.get("layers", []) as Array):
		var debug := layer_state as Dictionary
		by_id[str(debug.get("id", ""))] = debug
	var audio_off: Dictionary = by_id.get("audio_off", {}) as Dictionary
	if float(audio_off.get("chart_reaction", 0.0)) > 0.0:
		failures.append("Audio Reactive off layer still reacted to chart event.")
	var hit_only: Dictionary = by_id.get("hit_only", {}) as Dictionary
	if float(hit_only.get("hit_reaction", 0.0)) <= 0.0:
		failures.append("Hit-only Player Reactive layer did not react to player_hit.")
	if float(hit_only.get("miss_reaction", 0.0)) > 0.0:
		failures.append("Hit-only Player Reactive layer reacted to miss.")
	var miss_only: Dictionary = by_id.get("miss_only", {}) as Dictionary
	if float(miss_only.get("miss_reaction", 0.0)) <= 0.0:
		failures.append("Miss-only Player Reactive layer did not react to player_miss.")
	if float(miss_only.get("hit_reaction", 0.0)) > 0.0:
		failures.append("Miss-only Player Reactive layer reacted to hit.")
