extends RefCounted
class_name NotePlacementSystem

signal notes_changed()
signal note_added(note: Dictionary)
signal selection_changed(selected_ids: Array[int])
signal undo_redo_state_changed(can_undo: bool, can_redo: bool)

const ChartValidator := preload("res://scripts/songs/ChartValidator.gd")
const EditorLog := preload("res://scripts/editor/EditorLog.gd")
const LaneCountResolver := preload("res://scripts/songs/LaneCountResolver.gd")
const DEFAULT_KEYBOARD_HOLD_THRESHOLD_MSEC := 120
const MIN_KEYBOARD_HOLD_THRESHOLD_MSEC := 1
const MAX_KEYBOARD_HOLD_THRESHOLD_MSEC := 5000

var _grid: GridSnapManager
var _notes: Array[Dictionary] = []
var _next_note_id := 0
var _selected_ids: Dictionary = {}
var _clipboard: Array[Dictionary] = []
var _undo_stack: Array[Dictionary] = []
var _redo_stack: Array[Dictionary] = []
const UNDO_LIMIT := 200
var _undo_suspended := 0
var _live_entry_batch_active := false

var hold_mode := false
var _keyboard_hold_threshold_msec := DEFAULT_KEYBOARD_HOLD_THRESHOLD_MSEC
# One pending entry per lane lets keyboard chords become simultaneous holds.
# Entries are started on key-down and resolved as taps or holds on key-up.
var _pending_holds: Dictionary = {}
var _lane_count := LaneCountResolver.DEFAULT_LANES


func attach_grid(grid: GridSnapManager) -> void:
	_grid = grid


func set_lane_count(count: int) -> void:
	_lane_count = LaneCountResolver.clamp_lane_count(count)
	_pending_holds.clear()
	var changed := false
	for i in range(_notes.size()):
		var note: Dictionary = _notes[i]
		var lane := int(note.get("lane", 0))
		var clamped := _clamp_lane(lane)
		if lane != clamped:
			if not changed:
				_record_undo()
			note["lane"] = clamped
			_notes[i] = note
			changed = true
	if changed:
		_sort_notes()
		_prune_selection()
		_redo_stack.clear()
		notes_changed.emit()
		_emit_undo_redo_state()


func get_lane_count() -> int:
	return _lane_count


func set_keyboard_hold_threshold_msec(value: int) -> void:
	_keyboard_hold_threshold_msec = clampi(
		value,
		MIN_KEYBOARD_HOLD_THRESHOLD_MSEC,
		MAX_KEYBOARD_HOLD_THRESHOLD_MSEC
	)


func get_keyboard_hold_threshold_msec() -> int:
	return _keyboard_hold_threshold_msec


func begin_live_entry_batch() -> void:
	if _live_entry_batch_active:
		return
	# While this mode is active, _record_undo() stores a tiny ID boundary for each
	# added note instead of deep-copying the chart. Per-note undo is preserved.
	_live_entry_batch_active = true


func end_live_entry_batch() -> void:
	if not _live_entry_batch_active:
		return
	_live_entry_batch_active = false


func set_notes(notes: Array[Dictionary]) -> void:
	_notes = notes.duplicate(true)
	_pending_holds.clear()
	_normalize_note_ids()
	_sort_notes()
	_prune_selection()
	_undo_stack.clear()
	_redo_stack.clear()
	notes_changed.emit()
	_emit_undo_redo_state()


func replace_notes(notes: Array[Dictionary]) -> void:
	_record_undo()
	_notes = notes.duplicate(true)
	_pending_holds.clear()
	_selected_ids.clear()
	_normalize_note_ids()
	_normalize_hold_fields()
	_sort_notes()
	_redo_stack.clear()
	notes_changed.emit()
	selection_changed.emit([])
	_emit_undo_redo_state()


func get_notes() -> Array[Dictionary]:
	return _notes.duplicate(true)


func get_note_count() -> int:
	return _notes.size()


func get_note(note_id: int) -> Dictionary:
	for n in _notes:
		if int(n.get("id", -1)) == note_id:
			return (n as Dictionary).duplicate(true)
	return {}


func get_note_ids_in_lane(lane: int) -> Array[int]:
	var clamped := _clamp_lane(lane)
	var ids: Array[int] = []
	for n in _notes:
		if int(n.get("lane", -1)) == clamped:
			ids.append(int(n.get("id", -1)))
	ids.sort()
	return ids


func get_all_note_ids() -> Array[int]:
	var ids: Array[int] = []
	for n in _notes:
		ids.append(int(n.get("id", -1)))
	ids.sort()
	return ids


func update_note(note_id: int, updates: Dictionary) -> bool:
	if updates.is_empty():
		return false
	var idx := -1
	for i in range(_notes.size()):
		if int((_notes[i] as Dictionary).get("id", -1)) == note_id:
			idx = i
			break
	if idx < 0:
		return false
	_record_undo()
	var note: Dictionary = (_notes[idx] as Dictionary).duplicate(true)
	for key_variant in updates.keys():
		var key: String = str(key_variant)
		note[key] = updates[key_variant]
	_notes[idx] = note
	_sort_notes()
	_prune_selection()
	_redo_stack.clear()
	notes_changed.emit()
	_emit_undo_redo_state()
	return true


func set_note_type(note_id: int, kind: String, hold_length_sec: float = 0.0) -> bool:
	kind = kind.strip_edges().to_lower()
	if kind != "tap" and kind != "hold":
		return false
	var note := get_note(note_id)
	if note.is_empty():
		return false
	if kind == "tap":
		var updates := {"type": "tap"}
		updates.erase("length")
		updates.erase("duration")
		# Explicitly remove hold fields.
		return update_note(note_id, {"type": "tap", "length": 0.0, "duration": 0.0})
	var length := maxf(0.001, hold_length_sec)
	return update_note(note_id, {"type": "hold", "length": length, "duration": length})


func set_hold_length(note_id: int, hold_length_sec: float) -> bool:
	var note := get_note(note_id)
	if note.is_empty():
		return false
	if str(note.get("type", "tap")).to_lower() != "hold":
		return false
	var length := maxf(0.001, hold_length_sec)
	return update_note(note_id, {"length": length, "duration": length})


func move_note_absolute(note_id: int, time_sec: float, lane: int) -> bool:
	var note := get_note(note_id)
	if note.is_empty():
		return false
	var t := _snap(maxf(0.0, time_sec))
	var l := _clamp_lane(lane)
	return update_note(note_id, {"time": t, "lane": l})

func clear() -> void:
	_record_undo()
	_notes.clear()
	_pending_holds.clear()
	_next_note_id = 0
	_selected_ids.clear()
	_clipboard.clear()
	_redo_stack.clear()
	notes_changed.emit()
	selection_changed.emit([])
	_emit_undo_redo_state()


func set_selected_ids(ids: Array[int]) -> void:
	_selected_ids.clear()
	for id in ids:
		_selected_ids[int(id)] = true
	_prune_selection()
	selection_changed.emit(get_selected_ids())


func get_selected_ids() -> Array[int]:
	var out: Array[int] = []
	for k in _selected_ids.keys():
		out.append(int(k))
	out.sort()
	return out


func clear_selection() -> void:
	if _selected_ids.is_empty():
		return
	_selected_ids.clear()
	selection_changed.emit([])


func delete_selected() -> int:
	if _selected_ids.is_empty():
		return 0
	_record_undo()
	var removed := 0
	for i in range(_notes.size() - 1, -1, -1):
		var n: Dictionary = _notes[i]
		var id := int(n.get("id", -1))
		if id >= 0 and _selected_ids.has(id):
			_notes.remove_at(i)
			removed += 1
	_selected_ids.clear()
	if removed > 0:
		_redo_stack.clear()
		notes_changed.emit()
	selection_changed.emit([])
	_emit_undo_redo_state()
	return removed


func delete_note(note_id: int) -> bool:
	if note_id < 0:
		return false
	var note_index := -1
	for i in range(_notes.size()):
		if int((_notes[i] as Dictionary).get("id", -1)) == note_id:
			note_index = i
			break
	if note_index < 0:
		return false
	_record_undo()
	_notes.remove_at(note_index)
	_prune_selection()
	_redo_stack.clear()
	notes_changed.emit()
	selection_changed.emit(get_selected_ids())
	_emit_undo_redo_state()
	return true


func copy_selected() -> int:
	return copy_note_ids(get_selected_ids())


func copy_note_ids(ids: Array[int]) -> int:
	_clipboard.clear()
	if ids.is_empty():
		EditorLog.warn("clipboard", "copy_note_ids: no note ids")
		return 0
	var id_lookup: Dictionary = {}
	for id in ids:
		id_lookup[int(id)] = true
	var selected_notes: Array[Dictionary] = []
	for n in _notes:
		var id := int(n.get("id", -1))
		if id >= 0 and id_lookup.has(id):
			selected_notes.append(n.duplicate(true))
	if selected_notes.is_empty():
		EditorLog.warn("clipboard", "copy_note_ids: ids had no matching notes")
		return 0
	selected_notes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("time", 0.0)) < float(b.get("time", 0.0))
	)
	var t0 := float(selected_notes[0].get("time", 0.0))
	for n in selected_notes:
		var dt := float(n.get("time", 0.0)) - t0
		_clipboard.append({
			"dt": dt,
			"lane": int(n.get("lane", 0)),
			"type": str(n.get("type", "tap")),
			"length": float(n.get("length", 0.0)),
		})
	EditorLog.info("clipboard", "copy_note_ids: copied=%d" % _clipboard.size())
	return _clipboard.size()


func copy_lane(lane: int) -> int:
	return copy_note_ids(get_note_ids_in_lane(lane))


func copy_all() -> int:
	return copy_note_ids(get_all_note_ids())


func delete_lane(lane: int) -> int:
	var clamped := _clamp_lane(lane)
	var removed := 0
	for n in _notes:
		if int(n.get("lane", -1)) == clamped:
			removed += 1
	if removed <= 0:
		return 0
	_record_undo()
	for i in range(_notes.size() - 1, -1, -1):
		var n: Dictionary = _notes[i]
		if int(n.get("lane", -1)) == clamped:
			_notes.remove_at(i)
	_prune_selection()
	_redo_stack.clear()
	notes_changed.emit()
	selection_changed.emit(get_selected_ids())
	_emit_undo_redo_state()
	return removed


func delete_all_notes() -> int:
	if _notes.is_empty():
		return 0
	_record_undo()
	var removed := _notes.size()
	_notes.clear()
	_pending_holds.clear()
	_next_note_id = 0
	_selected_ids.clear()
	_redo_stack.clear()
	notes_changed.emit()
	selection_changed.emit([])
	_emit_undo_redo_state()
	return removed


func shift_lane_to_lane(source_lane: int, target_lane: int) -> int:
	var mapping: Dictionary = {}
	mapping[_clamp_lane(source_lane)] = _clamp_lane(target_lane)
	return shift_lanes(mapping)


func shift_lanes(lane_mapping: Dictionary) -> int:
	if lane_mapping.is_empty():
		return 0
	var normalized: Dictionary = {}
	for raw_source in lane_mapping.keys():
		var source := _clamp_lane(int(raw_source))
		var target := _clamp_lane(int(lane_mapping[raw_source]))
		if source != target:
			normalized[source] = target
	if normalized.is_empty():
		return 0
	var moved := 0
	for n in _notes:
		var lane := int(n.get("lane", -1))
		if normalized.has(lane):
			moved += 1
	if moved <= 0:
		return 0
	_record_undo()
	for i in range(_notes.size()):
		var n: Dictionary = _notes[i]
		var lane := int(n.get("lane", -1))
		if normalized.has(lane):
			n["lane"] = int(normalized[lane])
			_notes[i] = n
	_redo_stack.clear()
	_sort_notes()
	notes_changed.emit()
	_emit_undo_redo_state()
	return moved


func paste_at(time_sec: float) -> int:
	if _clipboard.is_empty():
		EditorLog.warn("clipboard", "paste_at: clipboard empty")
		return 0
	EditorLog.info("clipboard", "paste_at: target=%.3f count=%d" % [time_sec, _clipboard.size()])
	_begin_undo_group()
	var pasted := 0
	for entry in _clipboard:
		var t := maxf(0.0, time_sec + float(entry.get("dt", 0.0)))
		var lane := _clamp_lane(int(entry.get("lane", 0)))
		var kind := str(entry.get("type", "tap")).to_lower()
		var length := maxf(0.0, float(entry.get("length", 0.0)))
		if kind == "hold" and length > 0.0:
			_place_hold_raw(t, lane, length)
		else:
			_place_tap_raw(t, lane)
		pasted += 1
	_end_undo_group()
	if pasted > 0:
		_sort_notes()
		notes_changed.emit()
		_emit_undo_redo_state()
	return pasted


func move_selected(delta_time_sec: float, delta_lane: int) -> int:
	if _selected_ids.is_empty():
		return 0
	if is_equal_approx(delta_time_sec, 0.0) and delta_lane == 0:
		return 0
	_record_undo()
	var moved := 0
	for i in range(_notes.size()):
		var n: Dictionary = _notes[i]
		var id := int(n.get("id", -1))
		if id < 0 or not _selected_ids.has(id):
			continue
		var t := float(n.get("time", 0.0)) + delta_time_sec
		t = _snap(maxf(0.0, t))
		var lane := _clamp_lane(int(n.get("lane", 0)) + delta_lane)
		n["time"] = t
		n["lane"] = lane
		_notes[i] = n
		moved += 1
	if moved > 0:
		_redo_stack.clear()
		_sort_notes()
		notes_changed.emit()
		_emit_undo_redo_state()
	return moved


func snap_selected_to_grid() -> int:
	if _grid == null or _grid.division <= 0 or _selected_ids.is_empty():
		return 0
	var changed := false
	for n in _notes:
		var id := int(n.get("id", -1))
		if id >= 0 and _selected_ids.has(id) and not is_equal_approx(float(n.get("time", 0.0)), _grid.snap_time(float(n.get("time", 0.0)))):
			changed = true
			break
	if not changed:
		return 0
	_record_undo()
	var snapped_count := 0
	for i in range(_notes.size()):
		var n: Dictionary = _notes[i]
		var id := int(n.get("id", -1))
		if id < 0 or not _selected_ids.has(id):
			continue
		var old_time := float(n.get("time", 0.0))
		var new_time := _grid.snap_time(old_time)
		if is_equal_approx(old_time, new_time):
			continue
		n["time"] = new_time
		_notes[i] = n
		snapped_count += 1
	if snapped_count > 0:
		_redo_stack.clear()
		_sort_notes()
		notes_changed.emit()
		_emit_undo_redo_state()
	return snapped_count


func snap_all_to_grid() -> int:
	if _grid == null or _grid.division <= 0 or _notes.is_empty():
		return 0
	var changed := false
	for n in _notes:
		if not is_equal_approx(float(n.get("time", 0.0)), _grid.snap_time(float(n.get("time", 0.0)))):
			changed = true
			break
	if not changed:
		return 0
	_record_undo()
	var snapped_count := 0
	for i in range(_notes.size()):
		var n: Dictionary = _notes[i]
		var old_time := float(n.get("time", 0.0))
		var new_time := _grid.snap_time(old_time)
		if is_equal_approx(old_time, new_time):
			continue
		n["time"] = new_time
		_notes[i] = n
		snapped_count += 1
	if snapped_count > 0:
		_redo_stack.clear()
		_sort_notes()
		notes_changed.emit()
		_emit_undo_redo_state()
	return snapped_count


func place_tap(time_sec: float, lane: int) -> void:
	_record_undo()
	var t := _snap(time_sec)
	var note := {"id": _next_note_id, "time": t, "lane": _clamp_lane(lane), "type": "tap"}
	_next_note_id += 1
	_insert_note_sorted(note)
	_redo_stack.clear()
	note_added.emit(note.duplicate(true))
	notes_changed.emit()
	_emit_undo_redo_state()


func place_hold(time_sec: float, lane: int, length_sec: float) -> void:
	_record_undo()
	var t := _snap(time_sec)
	var length := maxf(0.001, length_sec)
	var note := {"id": _next_note_id, "time": t, "lane": _clamp_lane(lane), "type": "hold", "length": length, "duration": length}
	_next_note_id += 1
	_insert_note_sorted(note)
	_redo_stack.clear()
	note_added.emit(note.duplicate(true))
	notes_changed.emit()
	_emit_undo_redo_state()


func handle_keyboard_lane(time_sec: float, lane: int, shift: bool) -> void:
	handle_keyboard_lane_event(time_sec, lane, shift, true)


func handle_keyboard_lane_event(time_sec: float, lane: int, shift: bool, pressed: bool) -> void:
	if _grid == null:
		return
	lane = _clamp_lane(lane)
	# Always wait for key-up so ordinary lane bindings can infer intent: a press
	# shorter than the hold threshold is a tap, while a sustained press is a hold.
	# Each lane tracks its own start, so chords work naturally.
	if pressed:
		_begin_hold(time_sec, lane)
	else:
		_commit_hold(time_sec, lane)


func delete_nearest(time_sec: float, lane: int, tolerance_sec: float) -> bool:
	lane = _clamp_lane(lane)
	var best_idx := -1
	var best_dt := INF
	for i in range(_notes.size()):
		var n: Dictionary = _notes[i]
		if int(n.get("lane", -1)) != lane:
			continue
		var dt := absf(float(n.get("time", 0.0)) - time_sec)
		if dt < best_dt:
			best_dt = dt
			best_idx = i
	if best_idx >= 0 and best_dt <= tolerance_sec:
		_record_undo()
		_notes.remove_at(best_idx)
		_prune_selection()
		_redo_stack.clear()
		notes_changed.emit()
		_emit_undo_redo_state()
		return true
	return false


func delete_at_time(time_sec: float, lane: int) -> bool:
	return delete_nearest(time_sec, lane, 0.0005)


func validate_current_chart(difficulty: String) -> Dictionary:
	var chart := {
		"version": 1,
		"difficulty": difficulty,
		"lane_count": _lane_count,
		"notes": _notes.duplicate(true),
	}
	return ChartValidator.validate_chart(chart, difficulty)


func _begin_hold(time_sec: float, lane: int, force_hold: bool = false) -> void:
	if _pending_holds.has(lane):
		return
	_pending_holds[lane] = {
		"time": maxf(0.0, time_sec),
		"started_msec": Time.get_ticks_msec(),
		"force_hold": force_hold,
	}


func _commit_hold(time_sec: float, lane: int) -> void:
	if not _pending_holds.has(lane):
		return
	var pending: Dictionary = _pending_holds[lane] as Dictionary
	var raw_start: float = float(pending.get("time", time_sec))
	var raw_end: float = maxf(0.0, time_sec)
	var held_msec := maxi(0, Time.get_ticks_msec() - int(pending.get("started_msec", Time.get_ticks_msec())))
	var wants_hold := bool(pending.get("force_hold", false)) or held_msec >= _keyboard_hold_threshold_msec
	_pending_holds.erase(lane)
	var start := _snap(raw_start)
	var end := _snap(raw_end)
	if not wants_hold:
		place_tap(start, lane)
		return
	if end < start:
		var tmp := start
		start = end
		end = tmp
	if is_equal_approx(end, start):
		# A deliberate hold can begin and end inside one snap bucket, especially
		# at 0.5x. Give it one grid step instead of silently turning it into a tap.
		var step := _grid.seconds_per_step()
		end = start + step if step > 0.0 else maxf(start + 0.001, raw_end)
	var length := maxf(0.001, end - start)
	place_hold(start, lane, length)


func begin_hold_drag(time_sec: float, lane: int) -> void:
	if _grid == null:
		return
	_begin_hold(time_sec, _clamp_lane(lane), true)


func end_hold_drag(time_sec: float, lane: int) -> void:
	if _grid == null:
		return
	_commit_hold(time_sec, _clamp_lane(lane))


func _snap(time_sec: float) -> float:
	if _grid == null:
		return maxf(0.0, time_sec)
	return _grid.snap_time(time_sec)


func _sort_notes() -> void:
	_notes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ta := float(a.get("time", 0.0))
		var tb := float(b.get("time", 0.0))
		if ta == tb:
			return int(a.get("lane", 0)) < int(b.get("lane", 0))
		return ta < tb
	)


func _insert_note_sorted(note: Dictionary) -> void:
	var low := 0
	var high := _notes.size()
	while low < high:
		var mid := (low + high) >> 1
		var existing: Dictionary = _notes[mid]
		var existing_time := float(existing.get("time", 0.0))
		var note_time := float(note.get("time", 0.0))
		var existing_before := existing_time < note_time
		if is_equal_approx(existing_time, note_time):
			var existing_lane := int(existing.get("lane", 0))
			var note_lane := int(note.get("lane", 0))
			existing_before = existing_lane < note_lane \
				or (existing_lane == note_lane and int(existing.get("id", -1)) < int(note.get("id", -1)))
		if existing_before:
			low = mid + 1
		else:
			high = mid
	_notes.insert(low, note)


func _normalize_note_ids() -> void:
	var has_missing := false
	var max_id := -1
	for n in _notes:
		if not n.has("id"):
			has_missing = true
		else:
			max_id = maxi(max_id, int(n.get("id", -1)))
	_next_note_id = max_id + 1 if max_id >= 0 else 0
	if not has_missing:
		return
	# Deterministic assignment for legacy/imported notes missing ids.
	_sort_notes()
	for i in range(_notes.size()):
		var note: Dictionary = _notes[i]
		if not note.has("id"):
			note["id"] = _next_note_id
			_next_note_id += 1
		# Ensure holds have duration for gameplay compatibility.
		if note.has("length") and not note.has("duration"):
			note["duration"] = note.get("length", 0.0)
			_notes[i] = note


func _normalize_hold_fields() -> void:
	for i in range(_notes.size()):
		var note: Dictionary = _notes[i]
		var length := 0.0
		if note.has("length"):
			length = maxf(0.0, float(note.get("length", 0.0)))
		elif note.has("duration"):
			length = maxf(0.0, float(note.get("duration", 0.0)))
		if length > 0.0:
			note["type"] = "hold"
			note["length"] = length
			note["duration"] = length
		elif not note.has("type"):
			note["type"] = "tap"
		_notes[i] = note


func _prune_selection() -> void:
	if _selected_ids.is_empty():
		return
	var existing: Dictionary = {}
	for n in _notes:
		existing[int(n.get("id", -1))] = true
	for k in _selected_ids.keys():
		if not existing.has(int(k)):
			_selected_ids.erase(k)


func can_undo() -> bool:
	return not _undo_stack.is_empty()


func can_redo() -> bool:
	return not _redo_stack.is_empty()


func undo() -> bool:
	if _undo_stack.is_empty():
		return false
	_redo_stack.append(_snapshot())
	var snap: Dictionary = _undo_stack.pop_back()
	_restore_snapshot(snap)
	notes_changed.emit()
	selection_changed.emit(get_selected_ids())
	_emit_undo_redo_state()
	return true


func redo() -> bool:
	if _redo_stack.is_empty():
		return false
	_undo_stack.append(_snapshot())
	var snap: Dictionary = _redo_stack.pop_back()
	_restore_snapshot(snap)
	notes_changed.emit()
	selection_changed.emit(get_selected_ids())
	_emit_undo_redo_state()
	return true


func _record_undo() -> void:
	if _undo_suspended > 0:
		return
	if _live_entry_batch_active:
		# New live notes always receive monotonically increasing IDs. Restoring this
		# boundary removes exactly this note without copying all existing notes now.
		_undo_stack.append({
			"kind": "live_add_step",
			"next_id": _next_note_id,
			"selected": get_selected_ids(),
		})
	else:
		_undo_stack.append(_snapshot())
	if _undo_stack.size() > UNDO_LIMIT:
		_undo_stack.pop_front()


func _begin_undo_group() -> void:
	# Record one undo snapshot for a multi-step operation (paste, etc).
	_record_undo()
	_undo_suspended += 1


func _end_undo_group() -> void:
	_undo_suspended = maxi(0, _undo_suspended - 1)
	# Grouped ops should invalidate redo like any other edit.
	_redo_stack.clear()


func _place_tap_raw(time_sec: float, lane: int) -> void:
	var t := _snap(time_sec)
	var note := {"id": _next_note_id, "time": t, "lane": _clamp_lane(lane), "type": "tap"}
	_next_note_id += 1
	_notes.append(note)


func _place_hold_raw(time_sec: float, lane: int, length_sec: float) -> void:
	var t := _snap(time_sec)
	var length := maxf(0.001, length_sec)
	var note := {"id": _next_note_id, "time": t, "lane": _clamp_lane(lane), "type": "hold", "length": length, "duration": length}
	_next_note_id += 1
	_notes.append(note)


func _snapshot() -> Dictionary:
	return {
		"notes": _notes.duplicate(true),
		"next_id": _next_note_id,
		"selected": get_selected_ids(),
	}


func _restore_snapshot(snap: Dictionary) -> void:
	if str(snap.get("kind", "")) == "live_add_step":
		var first_live_id := int(snap.get("next_id", _next_note_id))
		for index in range(_notes.size() - 1, -1, -1):
			if int(_notes[index].get("id", -1)) >= first_live_id:
				_notes.remove_at(index)
		_next_note_id = first_live_id
		_pending_holds.clear()
		_selected_ids.clear()
		for id in (snap.get("selected", []) as Array):
			_selected_ids[int(id)] = true
		_sort_notes()
		_prune_selection()
		return
	_notes = (snap.get("notes", []) as Array).duplicate(true)
	_next_note_id = int(snap.get("next_id", 0))
	# Key-down state is transient input, not chart history. Restoring it can revive
	# an already released chord lane and create an oversized hold on the next key-up.
	_pending_holds.clear()
	_selected_ids.clear()
	for id in (snap.get("selected", []) as Array):
		_selected_ids[int(id)] = true
	_sort_notes()
	_prune_selection()


func _emit_undo_redo_state() -> void:
	undo_redo_state_changed.emit(can_undo(), can_redo())


func _clamp_lane(lane: int) -> int:
	return clampi(lane, 0, _lane_count - 1)
