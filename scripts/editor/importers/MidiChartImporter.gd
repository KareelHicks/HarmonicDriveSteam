extends RefCounted
class_name MidiChartImporter

const Utils := preload("res://scripts/editor/importers/ChartImportUtils.gd")
const LaneCountResolver := preload("res://scripts/songs/LaneCountResolver.gd")

const TRACK_INSTRUMENTS := {
	"PART GUITAR": "guitar",
	"PART GHL GUITAR": "ghl_guitar",
	"T1 GEMS": "guitar",
	"PART BASS": "bass",
	"PART GHL BASS": "ghl_guitar",
	"PART RHYTHM": "rhythm",
	"PART RHYTHM GUITAR": "rhythm",
	"PART GUITAR COOP": "rhythm",
	"PART SYNTH": "synth",
	"PART PIANO": "piano",
	"PART KEYS": "keyboard",
	"PART REAL_KEYS": "keyboard",
	"PART KEYBOARD": "keyboard",
	"PART PRO_KEYS": "keyboard",
	"PART DRUMS": "drums",
	"PART REAL_DRUMS_PS": "drums",
}

const DIFFICULTY_NOTE_BASE := {
	"easy": 60,
	"medium": 72,
	"hard": 84,
	"expert": 96,
}

const MIDI_MIN_IMPORT_LANES := 4
const MIDI_MAX_IMPORT_LANES := 8


static func default_options() -> Dictionary:
	return {
		"track_index": -1,
		"lane_count": 0,
		"lane_mapping": "pitch_low_high",
		"note_type": "taps",
		"hold_threshold": 0.18,
		"min_spacing": 0.08,
		"min_velocity": 1,
		"velocity_priority": true,
		"time_offset": 0.0,
		"max_notes": 0,
		"audio_compare": false,
		"audio_peak_filter_threshold": 0.35,
		"audio_peak_snap_window": 0.04,
		"audio_peak_boost": true,
		"audio_add_peaks": false,
		"audio_timing_offset": 0.0,
	}


static func options_with_defaults(options: Dictionary) -> Dictionary:
	var merged := default_options()
	for key in options.keys():
		merged[key] = options[key]
	return merged


static func inspect_file(path: String) -> Dictionary:
	var bytes := FileAccess.get_file_as_bytes(path)
	return inspect_bytes(bytes, path.get_file())


static func inspect_bytes(bytes: PackedByteArray, source_name: String = "notes.mid") -> Dictionary:
	var parsed := _parse_midi_bytes(bytes, source_name)
	if not bool(parsed.get("ok", false)):
		return parsed
	var converted := convert_midi_data(parsed.get("midi_data", {}) as Dictionary, default_options())
	if not bool(converted.get("ok", false)):
		return {
			"ok": false,
			"error": str(converted.get("error", "No MIDI note events found to import.")),
			"entries": [],
			"metadata": parsed.get("metadata", {}),
			"midi_data": parsed.get("midi_data", {}),
			"import_type": "midi",
			"midi_options": default_options(),
		}
	converted["midi_data"] = parsed.get("midi_data", {})
	converted["import_type"] = "midi"
	converted["midi_options"] = default_options()
	return converted


static func convert_inspect_result(inspect_result: Dictionary, options: Dictionary = {}, waveform: Variant = null) -> Dictionary:
	return convert_midi_data(inspect_result.get("midi_data", {}) as Dictionary, options, waveform)


static func convert_midi_data(midi_data: Dictionary, options: Dictionary = {}, waveform: Variant = null) -> Dictionary:
	var resolved := options_with_defaults(options)
	var tracks: Array = midi_data.get("tracks", []) as Array
	var selected_track_index := int(resolved.get("track_index", -1))
	var note_events: Array = []
	var source_name := "All MIDI Tracks"
	var source_section := source_name
	var instrument := "midi"
	if selected_track_index >= 0 and selected_track_index < tracks.size():
		var selected_track: Dictionary = tracks[selected_track_index] as Dictionary
		note_events = (selected_track.get("notes", []) as Array).duplicate(true)
		source_name = str(selected_track.get("display_name", "MIDI Track"))
		source_section = str(selected_track.get("name", source_name))
		instrument = str(selected_track.get("instrument", "midi"))
		if instrument.is_empty():
			instrument = "midi"
	else:
		for track_var in tracks:
			var track: Dictionary = track_var as Dictionary
			note_events.append_array(track.get("notes", []) as Array)

	if note_events.is_empty():
		return {"ok": false, "error": "No MIDI note events found to import.", "entries": [], "metadata": midi_data.get("metadata", {})}

	var lane_mapping := str(resolved.get("lane_mapping", "pitch_low_high"))
	var lane_count := int(resolved.get("lane_count", 0))
	if lane_count <= 0:
		lane_count = _lane_count_for_instrument(instrument) if lane_mapping == "authored" and instrument != "midi" else _generic_lane_count(note_events)
	lane_count = clampi(lane_count, MIDI_MIN_IMPORT_LANES, MIDI_MAX_IMPORT_LANES)
	var note_map := _note_map_for_options(note_events, lane_count, lane_mapping, instrument)
	var tempo_events: Array[Dictionary] = []
	for tempo_var in (midi_data.get("tempo_events", []) as Array):
		if tempo_var is Dictionary:
			tempo_events.append(tempo_var as Dictionary)
	if tempo_events.is_empty():
		tempo_events.append({"tick": 0, "bpm": 120.0, "sec": 0.0})
	var notes := _convert_option_notes(note_events, tempo_events, int(midi_data.get("division", 480)), lane_count, note_map, resolved, waveform)
	if notes.is_empty():
		return {"ok": false, "error": "MIDI settings produced no importable notes.", "entries": [], "metadata": midi_data.get("metadata", {})}
	notes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("time", 0.0)) < float(b.get("time", 0.0))
	)
	var entry := {
		"instrument": instrument,
		"difficulty": "expert",
		"source_name": source_name,
		"source_section": source_section,
		"lane_count": lane_count,
		"notes": notes,
	}
	return {"ok": true, "error": "", "entries": [entry], "metadata": midi_data.get("metadata", {})}


static func _parse_midi_bytes(bytes: PackedByteArray, source_name: String) -> Dictionary:
	if bytes.size() < 14 or bytes.slice(0, 4).get_string_from_utf8() != "MThd":
		return {"ok": false, "error": "Unsupported MIDI file.", "entries": [], "metadata": {}}
	var header_len := Utils.read_u32_be(bytes, 4)
	var division := Utils.read_u16_be(bytes, 12)
	if division <= 0 or (division & 0x8000) != 0:
		return {"ok": false, "error": "Unsupported MIDI timing division.", "entries": [], "metadata": {}}

	var offset := 8 + header_len
	var tracks: Array[Dictionary] = []
	var tempo_events: Array[Dictionary] = [{"tick": 0, "bpm": 120.0}]
	while offset + 8 <= bytes.size():
		if bytes.slice(offset, offset + 4).get_string_from_utf8() != "MTrk":
			break
		var length := Utils.read_u32_be(bytes, offset + 4)
		var track_bytes := bytes.slice(offset + 8, offset + 8 + length)
		var parsed := _parse_track(track_bytes)
		tracks.append(parsed)
		for tempo in (parsed.get("tempos", []) as Array):
			tempo_events.append(tempo as Dictionary)
		offset += 8 + length

	tempo_events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("tick", 0)) < int(b.get("tick", 0))
	)
	tempo_events = _tempo_map_with_seconds(tempo_events, division)
	for i in range(tracks.size()):
		var track: Dictionary = tracks[i] as Dictionary
		var display_name := str(track.get("name", "")).strip_edges()
		if display_name.is_empty():
			display_name = "Track %d" % (i + 1)
		track["index"] = i
		track["display_name"] = display_name
		track["instrument"] = _instrument_for_track(display_name)
		track["note_count"] = (track.get("notes", []) as Array).size()
		tracks[i] = track

	var metadata := {
		"title": source_name.get_file().get_basename(),
		"artist": "Unknown Artist",
		"charter": "Unknown Charter",
		"bpm": float((tempo_events[0] as Dictionary).get("bpm", 120.0)),
	}
	return {
		"ok": true,
		"error": "",
		"entries": [],
		"metadata": metadata,
		"midi_data": {
			"source_name": source_name,
			"division": division,
			"tempo_events": tempo_events,
			"tracks": tracks,
			"metadata": metadata,
		},
		"import_type": "midi",
	}


static func _lane_count_for_instrument(instrument: String) -> int:
	if instrument == "drums":
		return 4
	if instrument == "ghl_guitar":
		return 6
	return 5


static func _instrument_for_track(track_name: String) -> String:
	var name := track_name.strip_edges().to_upper()
	var aliases: Array = TRACK_INSTRUMENTS.keys()
	aliases.sort_custom(func(a: Variant, b: Variant) -> bool:
		return str(a).length() > str(b).length()
	)
	for candidate_value in aliases:
		var candidate := str(candidate_value)
		if name == candidate or name.contains(candidate):
			return str(TRACK_INSTRUMENTS[candidate])
	return "midi"


static func _note_map_for_instrument(instrument: String, difficulty: String) -> Dictionary:
	if instrument != "drums":
		return {}
	var base := int(DIFFICULTY_NOTE_BASE.get(difficulty, 96))
	return {base + 1: 0, base + 2: 1, base + 3: 2, base + 4: 3}


static func _parse_track(bytes: PackedByteArray) -> Dictionary:
	var offset := 0
	var tick := 0
	var running_status := 0
	var name := ""
	var tempos: Array[Dictionary] = []
	var active := {}
	var notes: Array[Dictionary] = []
	while offset < bytes.size():
		var delta_result := _read_var_len(bytes, offset)
		tick += int(delta_result.get("value", 0))
		offset = int(delta_result.get("offset", offset))
		if offset >= bytes.size():
			break
		var status := int(bytes[offset])
		if status < 0x80:
			status = running_status
		else:
			offset += 1
			running_status = status
		if status == 0xFF:
			if offset >= bytes.size():
				break
			var meta_type := int(bytes[offset])
			offset += 1
			var len_result := _read_var_len(bytes, offset)
			var length := int(len_result.get("value", 0))
			offset = int(len_result.get("offset", offset))
			var payload := bytes.slice(offset, offset + length)
			offset += length
			if meta_type == 0x03:
				name = payload.get_string_from_utf8()
			elif meta_type == 0x51 and payload.size() == 3:
				var us_per_qn := (int(payload[0]) << 16) | (int(payload[1]) << 8) | int(payload[2])
				if us_per_qn > 0:
					tempos.append({"tick": tick, "bpm": 60000000.0 / float(us_per_qn)})
			elif meta_type == 0x2F:
				break
			continue
		if status == 0xF0 or status == 0xF7:
			var syx := _read_var_len(bytes, offset)
			offset = int(syx.get("offset", offset)) + int(syx.get("value", 0))
			continue
		var event_type := status & 0xF0
		if offset >= bytes.size():
			break
		var data1 := int(bytes[offset])
		offset += 1
		var data2 := 0
		if event_type != 0xC0 and event_type != 0xD0:
			if offset >= bytes.size():
				break
			data2 = int(bytes[offset])
			offset += 1
		if event_type == 0x90 and data2 > 0:
			active[_active_note_key(status, data1)] = {"tick": tick, "velocity": data2, "channel": status & 0x0F}
		elif event_type == 0x80 or (event_type == 0x90 and data2 == 0):
			var active_key := _active_note_key(status, data1)
			if active.has(active_key):
				var active_note: Dictionary = active[active_key] as Dictionary
				var start_tick := int(active_note.get("tick", tick))
				active.erase(active_key)
				notes.append({
					"note": data1,
					"start": start_tick,
					"end": tick,
					"velocity": int(active_note.get("velocity", 64)),
					"channel": int(active_note.get("channel", status & 0x0F)),
				})
	return {"name": name, "tempos": tempos, "notes": notes}


static func _active_note_key(status: int, note: int) -> String:
	return "%d:%d" % [status & 0x0F, note]


static func _read_var_len(bytes: PackedByteArray, offset: int) -> Dictionary:
	var value := 0
	var pos := offset
	while pos < bytes.size():
		var b := int(bytes[pos])
		pos += 1
		value = (value << 7) | (b & 0x7F)
		if (b & 0x80) == 0:
			break
	return {"value": value, "offset": pos}


static func _tempo_map_with_seconds(events: Array[Dictionary], division: int) -> Array[Dictionary]:
	var dedup: Array[Dictionary] = []
	var seen := {}
	for event in events:
		var tick := int((event as Dictionary).get("tick", 0))
		if seen.has(tick):
			continue
		seen[tick] = true
		dedup.append(event as Dictionary)
	dedup.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("tick", 0)) < int(b.get("tick", 0))
	)
	if dedup.is_empty() or int((dedup[0] as Dictionary).get("tick", 0)) != 0:
		dedup.insert(0, {"tick": 0, "bpm": 120.0})
	var out: Array[Dictionary] = []
	var last_tick := 0
	var last_sec := 0.0
	var last_bpm := float((dedup[0] as Dictionary).get("bpm", 120.0))
	for i in range(dedup.size()):
		var event := dedup[i]
		var tick := int(event.get("tick", 0))
		if i > 0:
			last_sec += (float(tick - last_tick) / float(division)) * (60.0 / maxf(1.0, last_bpm))
		out.append({"tick": tick, "bpm": float(event.get("bpm", last_bpm)), "sec": last_sec})
		last_tick = tick
		last_bpm = float(event.get("bpm", last_bpm))
	return out


static func _tick_to_seconds(tick: int, tempos: Array[Dictionary], division: int) -> float:
	var active := tempos[0] as Dictionary
	for event in tempos:
		var tempo := event as Dictionary
		if int(tempo.get("tick", 0)) <= tick:
			active = tempo
		else:
			break
	var base_tick := int(active.get("tick", 0))
	var base_sec := float(active.get("sec", 0.0))
	var bpm := float(active.get("bpm", 120.0))
	return base_sec + (float(tick - base_tick) / float(division)) * (60.0 / maxf(1.0, bpm))


static func _generic_entry_from_notes(note_events: Array, tempos: Array[Dictionary], division: int, source_section: String) -> Dictionary:
	var lane_count := _generic_lane_count(note_events)
	var note_map := _generic_note_map(note_events, lane_count)
	var notes := _convert_generic_tap_notes(note_events, tempos, division, lane_count, note_map)
	if notes.is_empty():
		return {}
	notes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("time", 0.0)) < float(b.get("time", 0.0))
	)
	var section := source_section.strip_edges()
	if section.is_empty():
		section = "Unnamed MIDI Track"
	return {
		"instrument": "midi",
		"difficulty": "expert",
		"source_name": section,
		"source_section": section,
		"lane_count": lane_count,
		"notes": notes,
	}


static func _generic_lane_count(note_events: Array) -> int:
	var unique := {}
	for event in note_events:
		if event is not Dictionary:
			continue
		unique[int((event as Dictionary).get("note", -1))] = true
	return clampi(unique.size(), MIDI_MIN_IMPORT_LANES, MIDI_MAX_IMPORT_LANES)


static func _generic_note_map(note_events: Array, lane_count: int) -> Dictionary:
	var pitches: Array[int] = []
	var seen := {}
	for event in note_events:
		if event is not Dictionary:
			continue
		var pitch := int((event as Dictionary).get("note", -1))
		if pitch < 0 or seen.has(pitch):
			continue
		seen[pitch] = true
		pitches.append(pitch)
	pitches.sort()
	var note_map := {}
	if pitches.is_empty():
		return note_map
	if pitches.size() <= lane_count:
		if pitches.size() == 1:
			note_map[pitches[0]] = lane_count / 2
			return note_map
		for i in range(pitches.size()):
			var lane := int(roundf(float(i) * float(lane_count - 1) / float(pitches.size() - 1)))
			note_map[pitches[i]] = clampi(lane, 0, lane_count - 1)
		return note_map
	var min_pitch := pitches[0]
	var max_pitch := pitches[pitches.size() - 1]
	var pitch_span := maxi(1, max_pitch - min_pitch)
	for pitch in pitches:
		var normalized := float(pitch - min_pitch) / float(pitch_span)
		note_map[pitch] = clampi(int(roundf(normalized * float(lane_count - 1))), 0, lane_count - 1)
	return note_map


static func _note_map_for_options(note_events: Array, lane_count: int, lane_mapping: String, instrument: String) -> Dictionary:
	match lane_mapping:
		"pitch_high_low":
			return _generic_note_map_reversed(note_events, lane_count)
		"authored":
			var authored := _authored_note_map(note_events, lane_count, instrument)
			return authored if not authored.is_empty() else _generic_note_map(note_events, lane_count)
		_:
			return _generic_note_map(note_events, lane_count)


static func _generic_note_map_reversed(note_events: Array, lane_count: int) -> Dictionary:
	var note_map := _generic_note_map(note_events, lane_count)
	for pitch in note_map.keys():
		note_map[pitch] = lane_count - 1 - int(note_map[pitch])
	return note_map


static func _authored_note_map(note_events: Array, lane_count: int, instrument: String) -> Dictionary:
	var best_base := 96
	var best_score := -1
	for base_value in DIFFICULTY_NOTE_BASE.values():
		var base := int(base_value)
		var score := 0
		for event in note_events:
			if event is not Dictionary:
				continue
			var pitch := int((event as Dictionary).get("note", -1))
			var lane := pitch - base
			if instrument == "drums":
				lane = pitch - base - 1
			if lane >= 0 and lane < lane_count:
				score += 1
		if score > best_score:
			best_score = score
			best_base = base
	var note_map := {}
	if best_score <= 0:
		return note_map
	for lane in range(lane_count):
		note_map[best_base + lane] = lane
		if instrument == "drums":
			note_map[best_base + lane + 1] = lane
	return note_map


static func _lane_for_event(event: Dictionary, lane_count: int, lane_mapping: String, note_map: Dictionary) -> int:
	var pitch := int(event.get("note", -1))
	match lane_mapping:
		"pitch_modulo":
			return wrapi(pitch, 0, lane_count)
		"channel":
			return wrapi(int(event.get("channel", 0)), 0, lane_count)
		_:
			if not note_map.has(pitch):
				return -1
			return int(note_map[pitch])


static func _convert_generic_tap_notes(note_events: Array, tempos: Array[Dictionary], division: int, lane_count: int, note_map: Dictionary) -> Array[Dictionary]:
	var notes: Array[Dictionary] = []
	lane_count = LaneCountResolver.clamp_lane_count(lane_count)
	for event in note_events:
		if event is not Dictionary:
			continue
		var e := event as Dictionary
		var midi_note := int(e.get("note", -1))
		if not note_map.has(midi_note):
			continue
		var lane := int(note_map[midi_note])
		if lane < 0 or lane >= lane_count:
			continue
		var start_tick := int(e.get("start", 0))
		var start_sec := _tick_to_seconds(start_tick, tempos, division)
		notes.append({"time": start_sec, "lane": lane, "type": "tap"})
	return notes


static func _convert_option_notes(note_events: Array, tempos: Array[Dictionary], division: int, lane_count: int, note_map: Dictionary, options: Dictionary, waveform: Variant = null) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	var lane_mapping := str(options.get("lane_mapping", "pitch_low_high"))
	var note_type := str(options.get("note_type", "taps"))
	var min_velocity := int(options.get("min_velocity", 1))
	var time_offset := float(options.get("time_offset", 0.0))
	var hold_threshold := float(options.get("hold_threshold", 0.18))
	var audio_enabled := bool(options.get("audio_compare", false)) and _waveform_ready(waveform)
	var audio_offset := float(options.get("audio_timing_offset", 0.0))
	var peak_filter := float(options.get("audio_peak_filter_threshold", 0.35))
	var snap_window := float(options.get("audio_peak_snap_window", 0.04))
	lane_count = clampi(lane_count, MIDI_MIN_IMPORT_LANES, MIDI_MAX_IMPORT_LANES)
	for event in note_events:
		if event is not Dictionary:
			continue
		var e := event as Dictionary
		var velocity := int(e.get("velocity", 64))
		if velocity < min_velocity:
			continue
		var lane := _lane_for_event(e, lane_count, lane_mapping, note_map)
		if lane < 0 or lane >= lane_count:
			continue
		var start_tick := int(e.get("start", 0))
		var end_tick := int(e.get("end", start_tick))
		var start_sec := _tick_to_seconds(start_tick, tempos, division) + time_offset
		var end_sec := _tick_to_seconds(end_tick, tempos, division) + time_offset
		if audio_enabled:
			var peak := _peak_near_time(waveform, start_sec + audio_offset, snap_window)
			if peak_filter > 0.0 and float(peak.get("peak", 0.0)) < peak_filter:
				continue
			if snap_window > 0.0 and bool(peak.get("ok", false)):
				start_sec = maxf(0.0, float(peak.get("time", start_sec + audio_offset)) - audio_offset)
		if start_sec < 0.0:
			continue
		var length_sec := maxf(0.0, end_sec - start_sec)
		var note := {
			"time": start_sec,
			"lane": lane,
			"type": "tap",
			"_velocity": velocity,
		}
		if note_type == "preserve" and length_sec > 0.001:
			note["type"] = "hold"
			note["length"] = length_sec
		elif note_type == "threshold" and length_sec >= hold_threshold:
			note["type"] = "hold"
			note["length"] = length_sec
		candidates.append(note)
	if audio_enabled and bool(options.get("audio_add_peaks", false)):
		_add_audio_peak_candidates(candidates, waveform, lane_count, options)
	return _postprocess_candidates(candidates, waveform, options)


static func _postprocess_candidates(candidates: Array[Dictionary], waveform: Variant, options: Dictionary) -> Array[Dictionary]:
	var min_spacing := maxf(0.0, float(options.get("min_spacing", 0.08)))
	var velocity_priority := bool(options.get("velocity_priority", true))
	var peak_boost := bool(options.get("audio_peak_boost", true)) and bool(options.get("audio_compare", false)) and _waveform_ready(waveform)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("time", 0.0)) < float(b.get("time", 0.0))
	)
	var spaced: Array[Dictionary] = []
	for candidate in candidates:
		if spaced.is_empty() or float(candidate.get("time", 0.0)) - float((spaced[spaced.size() - 1] as Dictionary).get("time", 0.0)) >= min_spacing:
			spaced.append(candidate)
		elif velocity_priority or peak_boost:
			var last: Dictionary = spaced[spaced.size() - 1] as Dictionary
			if _candidate_score(candidate, waveform, peak_boost) > _candidate_score(last, waveform, peak_boost):
				spaced[spaced.size() - 1] = candidate
	var max_notes := int(options.get("max_notes", 0))
	if max_notes > 0 and spaced.size() > max_notes:
		spaced.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return _candidate_score(a, waveform, peak_boost) > _candidate_score(b, waveform, peak_boost)
		)
		spaced = spaced.slice(0, max_notes)
		spaced.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a.get("time", 0.0)) < float(b.get("time", 0.0))
		)
	var notes: Array[Dictionary] = []
	for candidate in spaced:
		var note := candidate.duplicate(true)
		note.erase("_velocity")
		notes.append(note)
	return notes


static func _candidate_score(candidate: Dictionary, waveform: Variant, peak_boost: bool) -> float:
	var score := float(candidate.get("_velocity", 64)) / 127.0
	if peak_boost and _waveform_ready(waveform):
		score += float(waveform.peak_at_time(float(candidate.get("time", 0.0))))
	return score


static func _add_audio_peak_candidates(candidates: Array[Dictionary], waveform: Variant, lane_count: int, options: Dictionary) -> void:
	if not _waveform_ready(waveform):
		return
	var threshold := maxf(0.45, float(options.get("audio_peak_filter_threshold", 0.35)))
	var min_spacing := maxf(0.08, float(options.get("min_spacing", 0.08)))
	var audio_offset := float(options.get("audio_timing_offset", 0.0))
	var t := 0.0
	var lane_cycle := 0
	var length := float(waveform.length_sec())
	while t <= length:
		var peak := float(waveform.peak_at_time(t))
		if peak >= threshold and not _has_candidate_near(candidates, t - audio_offset, min_spacing):
			candidates.append({
				"time": maxf(0.0, t - audio_offset),
				"lane": lane_cycle % lane_count,
				"type": "tap",
				"_velocity": int(roundf(peak * 127.0)),
			})
			lane_cycle += 1
			t += min_spacing
		else:
			t += 0.02


static func _has_candidate_near(candidates: Array[Dictionary], time_sec: float, min_spacing: float) -> bool:
	for candidate in candidates:
		if absf(float(candidate.get("time", 0.0)) - time_sec) < min_spacing:
			return true
	return false


static func _peak_near_time(waveform: Variant, time_sec: float, window: float) -> Dictionary:
	if not _waveform_ready(waveform):
		return {"ok": false, "peak": 0.0, "time": time_sec}
	var best_peak := -1.0
	var best_time := time_sec
	var start_t := maxf(0.0, time_sec - maxf(0.0, window))
	var end_t := minf(float(waveform.length_sec()), time_sec + maxf(0.0, window))
	var t := start_t
	while t <= end_t:
		var peak := float(waveform.peak_at_time(t))
		if peak > best_peak:
			best_peak = peak
			best_time = t
		t += 0.01
	return {"ok": best_peak >= 0.0, "peak": maxf(0.0, best_peak), "time": best_time}


static func _waveform_ready(waveform: Variant) -> bool:
	return waveform != null and waveform.has_method("is_ready") and bool(waveform.is_ready())


static func _convert_notes(note_events: Array, difficulty: String, tempos: Array[Dictionary], division: int, lane_count: int, note_map: Dictionary = {}) -> Array[Dictionary]:
	var notes: Array[Dictionary] = []
	var base := int(DIFFICULTY_NOTE_BASE.get(difficulty, 96))
	lane_count = LaneCountResolver.clamp_lane_count(lane_count)
	for event in note_events:
		var e := event as Dictionary
		var midi_note := int(e.get("note", -1))
		var lane := midi_note - base
		if not note_map.is_empty():
			if not note_map.has(midi_note):
				continue
			lane = int(note_map[midi_note])
		if lane < 0 or lane >= lane_count:
			continue
		var start_tick := int(e.get("start", 0))
		var end_tick := int(e.get("end", start_tick))
		var start_sec := _tick_to_seconds(start_tick, tempos, division)
		var end_sec := _tick_to_seconds(end_tick, tempos, division)
		var length_sec := maxf(0.0, end_sec - start_sec)
		if length_sec > 0.001:
			notes.append({"time": start_sec, "lane": lane, "type": "hold", "length": length_sec})
		else:
			notes.append({"time": start_sec, "lane": lane, "type": "tap"})
	return notes
