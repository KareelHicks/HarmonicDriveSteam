extends RefCounted
class_name MidiImportWizardControls

const MidiImporter := preload("res://scripts/editor/importers/MidiChartImporter.gd")


static func create() -> Dictionary:
	var root := VBoxContainer.new()
	root.visible = false
	root.add_theme_constant_override("separation", 8)

	var title := Label.new()
	title.text = "Advanced MIDI"
	root.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 6)
	root.add_child(grid)

	var controls := {"root": root}
	controls["track"] = _add_option(grid, "Track source")
	controls["lane_count"] = _add_option(grid, "Lane count")
	controls["lane_mapping"] = _add_option(grid, "Lane mapping")
	controls["note_type"] = _add_option(grid, "Note type")
	controls["hold_threshold"] = _add_spin(grid, "Hold threshold", 0.0, 2.0, 0.01, 0.18)
	controls["min_spacing"] = _add_spin(grid, "Minimum spacing", 0.0, 1.0, 0.01, 0.08)
	controls["min_velocity"] = _add_spin(grid, "Minimum velocity", 1.0, 127.0, 1.0, 1.0)
	controls["velocity_priority"] = _add_check(grid, "Velocity priority", true)
	controls["time_offset"] = _add_spin(grid, "Time offset", -10.0, 10.0, 0.001, 0.0)
	controls["max_notes"] = _add_spin(grid, "Max notes", 0.0, 20000.0, 10.0, 0.0)
	controls["audio_compare"] = _add_check(grid, "Compare MIDI against audio", false)
	controls["audio_peak_filter_threshold"] = _add_spin(grid, "Peak filter threshold", 0.0, 1.0, 0.01, 0.35)
	controls["audio_peak_snap_window"] = _add_spin(grid, "Peak snap window", 0.0, 0.25, 0.005, 0.04)
	controls["audio_peak_boost"] = _add_check(grid, "Peak boost thinning", true)
	controls["audio_add_peaks"] = _add_check(grid, "Add missing audio peaks", false)
	controls["audio_timing_offset"] = _add_spin(grid, "Audio timing offset", -2.0, 2.0, 0.001, 0.0)

	var status := Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.text = "Audio comparison requires loaded waveform data."
	root.add_child(status)
	controls["audio_status"] = status

	_populate_static_options(controls)
	return controls


static func connect_changed(controls: Dictionary, callback: Callable) -> void:
	for key in controls.keys():
		var control: Variant = controls[key]
		if control is OptionButton:
			(control as OptionButton).item_selected.connect(func(_idx: int) -> void:
				callback.call()
			)
		elif control is SpinBox:
			(control as SpinBox).value_changed.connect(func(_value: float) -> void:
				callback.call()
			)
		elif control is CheckBox:
			(control as CheckBox).toggled.connect(func(_pressed: bool) -> void:
				callback.call()
			)


static func populate_tracks(controls: Dictionary, inspect_result: Dictionary) -> void:
	var option := controls.get("track") as OptionButton
	if option == null:
		return
	option.clear()
	var tracks: Array = ((inspect_result.get("midi_data", {}) as Dictionary).get("tracks", []) as Array)
	var note_track_count := 0
	for track_var in tracks:
		if track_var is Dictionary and int((track_var as Dictionary).get("note_count", 0)) > 0:
			note_track_count += 1
	if note_track_count > 1:
		option.add_item("All MIDI Tracks")
		option.set_item_metadata(option.item_count - 1, -1)
	for i in range(tracks.size()):
		var track: Dictionary = tracks[i] as Dictionary
		var count := int(track.get("note_count", 0))
		if count <= 0:
			continue
		option.add_item("%s (%d notes)" % [str(track.get("display_name", "Track %d" % (i + 1))), count])
		option.set_item_metadata(option.item_count - 1, i)
	if option.item_count == 0:
		option.add_item("All MIDI Tracks")
		option.set_item_metadata(0, -1)
	option.select(0)


static func set_midi_visible(controls: Dictionary, visible: bool) -> void:
	var root := controls.get("root") as Control
	if root != null:
		root.visible = visible


static func set_audio_available(controls: Dictionary, available: bool, reason: String = "") -> void:
	var audio_keys := [
		"audio_compare",
		"audio_peak_filter_threshold",
		"audio_peak_snap_window",
		"audio_peak_boost",
		"audio_add_peaks",
		"audio_timing_offset",
	]
	for key in audio_keys:
		var control: Variant = controls.get(key)
		if control is BaseButton:
			(control as BaseButton).disabled = not available
		elif control is SpinBox:
			(control as SpinBox).editable = available
	var compare := controls.get("audio_compare") as CheckBox
	if compare != null and not available:
		compare.button_pressed = false
	var status := controls.get("audio_status") as Label
	if status != null:
		status.text = "Audio comparison available." if available else reason


static func read_options(controls: Dictionary) -> Dictionary:
	var options := MidiImporter.default_options()
	options["track_index"] = _selected_metadata_int(controls.get("track") as OptionButton, -1)
	options["lane_count"] = _selected_metadata_int(controls.get("lane_count") as OptionButton, 0)
	options["lane_mapping"] = _selected_metadata_string(controls.get("lane_mapping") as OptionButton, "pitch_low_high")
	options["note_type"] = _selected_metadata_string(controls.get("note_type") as OptionButton, "taps")
	options["hold_threshold"] = _spin_value(controls.get("hold_threshold") as SpinBox, 0.18)
	options["min_spacing"] = _spin_value(controls.get("min_spacing") as SpinBox, 0.08)
	options["min_velocity"] = int(roundf(_spin_value(controls.get("min_velocity") as SpinBox, 1.0)))
	options["velocity_priority"] = _check_value(controls.get("velocity_priority") as CheckBox, true)
	options["time_offset"] = _spin_value(controls.get("time_offset") as SpinBox, 0.0)
	options["max_notes"] = int(roundf(_spin_value(controls.get("max_notes") as SpinBox, 0.0)))
	var audio_compare := controls.get("audio_compare") as CheckBox
	options["audio_compare"] = audio_compare != null and not audio_compare.disabled and audio_compare.button_pressed
	options["audio_peak_filter_threshold"] = _spin_value(controls.get("audio_peak_filter_threshold") as SpinBox, 0.35)
	options["audio_peak_snap_window"] = _spin_value(controls.get("audio_peak_snap_window") as SpinBox, 0.04)
	options["audio_peak_boost"] = _check_value(controls.get("audio_peak_boost") as CheckBox, true)
	options["audio_add_peaks"] = _check_value(controls.get("audio_add_peaks") as CheckBox, false)
	options["audio_timing_offset"] = _spin_value(controls.get("audio_timing_offset") as SpinBox, 0.0)
	return options


static func _populate_static_options(controls: Dictionary) -> void:
	var lane_count := controls.get("lane_count") as OptionButton
	lane_count.add_item("Auto")
	lane_count.set_item_metadata(0, 0)
	for count in range(4, 9):
		lane_count.add_item("%d lanes" % count)
		lane_count.set_item_metadata(lane_count.item_count - 1, count)

	_populate_option(controls.get("lane_mapping") as OptionButton, [
		["Pitch low to high", "pitch_low_high"],
		["Pitch high to low", "pitch_high_low"],
		["Pitch modulo lanes", "pitch_modulo"],
		["MIDI channel", "channel"],
		["Authored lane notes", "authored"],
	])
	_populate_option(controls.get("note_type") as OptionButton, [
		["Taps only", "taps"],
		["Preserve durations", "preserve"],
		["Hold threshold", "threshold"],
	])


static func _populate_option(option: OptionButton, items: Array) -> void:
	option.clear()
	for item_var in items:
		var item: Array = item_var as Array
		option.add_item(str(item[0]))
		option.set_item_metadata(option.item_count - 1, str(item[1]))
	option.select(0)


static func _add_label(parent: GridContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	parent.add_child(label)


static func _add_option(parent: GridContainer, label: String) -> OptionButton:
	_add_label(parent, label)
	var option := OptionButton.new()
	option.custom_minimum_size = Vector2(220, 0)
	parent.add_child(option)
	return option


static func _add_spin(parent: GridContainer, label: String, min_value: float, max_value: float, step: float, value: float) -> SpinBox:
	_add_label(parent, label)
	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = step
	spin.value = value
	spin.allow_greater = true
	spin.allow_lesser = true
	spin.custom_minimum_size = Vector2(140, 0)
	parent.add_child(spin)
	return spin


static func _add_check(parent: GridContainer, label: String, pressed: bool) -> CheckBox:
	_add_label(parent, label)
	var check := CheckBox.new()
	check.button_pressed = pressed
	parent.add_child(check)
	return check


static func _selected_metadata_int(option: OptionButton, fallback: int) -> int:
	if option == null or option.selected < 0:
		return fallback
	return int(option.get_item_metadata(option.selected))


static func _selected_metadata_string(option: OptionButton, fallback: String) -> String:
	if option == null or option.selected < 0:
		return fallback
	return str(option.get_item_metadata(option.selected))


static func _spin_value(spin: SpinBox, fallback: float) -> float:
	return float(spin.value) if spin != null else fallback


static func _check_value(check: CheckBox, fallback: bool) -> bool:
	return bool(check.button_pressed) if check != null else fallback
