extends RefCounted
class_name SongPackageManager

const SongResolver := preload("res://scripts/songs/SongResolver.gd")
const ChartLoader := preload("res://scripts/gameplay/ChartLoader.gd")
const ChartValidator := preload("res://scripts/songs/ChartValidator.gd")
const LaneCountResolver := preload("res://scripts/songs/LaneCountResolver.gd")
const ChartImportUtils := preload("res://scripts/editor/importers/ChartImportUtils.gd")
const DifficultyManager := preload("res://scripts/editor/DifficultyManager.gd")
const WaveformRenderer := preload("res://scripts/editor/WaveformRenderer.gd")
const ChartMetadataResolver := preload("res://scripts/songs/ChartMetadataResolver.gd")


static func list_available_difficulties(song_folder: String) -> Array[String]:
	var available: Array[String] = []
	for id in DifficultyManager.all_ids():
		var chart_path := SongResolver.get_chart_path(song_folder, id)
		if FileAccess.file_exists(chart_path):
			available.append(id)
	return available


static func ensure_chart_exists(song_folder: String, difficulty_id: String) -> String:
	var id := difficulty_id.strip_edges().to_lower()
	if not DifficultyManager.is_valid_id(id):
		id = "expert"
	var chart_path := SongResolver.get_chart_path(song_folder, id)
	if FileAccess.file_exists(chart_path):
		return chart_path
	var metadata := ChartMetadataResolver.metadata_for_song_folder(song_folder, {}, id)
	var lane_count := LaneCountResolver.clamp_lane_count(int(metadata.get("lane_count", LaneCountResolver.DEFAULT_LANES)))
	var bpm := float(metadata.get("bpm", 120.0))
	if bpm <= 0.0:
		bpm = 120.0
	metadata["bpm"] = bpm
	metadata["nps"] = 0.0
	var payload := ChartImportUtils.chart_payload(id, [], lane_count, metadata)
	payload["timing_points"] = [{"time": 0.0, "bpm": bpm}]
	var json := JSON.stringify(payload, "\t", false)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(song_folder))
	var file := FileAccess.open(chart_path, FileAccess.WRITE)
	if file != null:
		file.store_string(json)
		file.flush()
	return chart_path


static func load_chart(song_folder: String, difficulty_id: String) -> Dictionary:
	var id := difficulty_id.strip_edges().to_lower()
	var path := SongResolver.get_chart_path(song_folder, id)
	var result: Dictionary = ChartLoader.load_hd_chart(path, id)
	if bool(result.get("ok", false)):
		return result.get("chart", {}) as Dictionary
	return {}


static func save_chart(song_folder: String, difficulty_id: String, payload: Dictionary) -> Dictionary:
	var id := difficulty_id.strip_edges().to_lower()
	payload["difficulty"] = id
	payload = LaneCountResolver.normalize_chart_lane_count(payload)
	var validation: Dictionary = ChartValidator.validate_chart(payload, id)
	if not ChartValidator.is_valid(validation):
		return {"ok": false, "path": "", "validation": validation}
	var path := SongResolver.get_chart_path(song_folder, id)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(song_folder))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "path": path, "validation": validation}
	file.store_string(JSON.stringify(payload, "\t", false))
	file.flush()
	return {"ok": true, "path": path, "validation": validation}


static func clone_difficulty(
	song_folder: String,
	from_id: String,
	to_id: String,
	overwrite: bool,
	method: String = "complete clone",
	waveform: WaveformRenderer = null
) -> Dictionary:
	var src := from_id.strip_edges().to_lower()
	var dst := to_id.strip_edges().to_lower()
	if not DifficultyManager.is_valid_id(src) or not DifficultyManager.is_valid_id(dst):
		return {"ok": false, "error": "Invalid difficulty selection."}
	if src == dst:
		return {"ok": false, "error": "Source and destination difficulties are the same."}
	var src_path := SongResolver.get_chart_path(song_folder, src)
	if not FileAccess.file_exists(src_path):
		return {"ok": false, "error": "Source chart missing: %s" % src_path}
	var dst_path := SongResolver.get_chart_path(song_folder, dst)
	if FileAccess.file_exists(dst_path) and not overwrite:
		return {"ok": false, "error": "Destination chart already exists."}
	var src_loaded: Dictionary = ChartLoader.load_hd_chart(src_path, src)
	if not bool(src_loaded.get("ok", false)):
		return {"ok": false, "error": "Failed to load source chart."}
	var chart: Dictionary = (src_loaded.get("chart", {}) as Dictionary).duplicate(true)
	chart["difficulty"] = dst
	var metadata := ChartMetadataResolver.metadata_for_song_folder(song_folder, {}, src)
	chart = ChartMetadataResolver.apply_metadata_to_chart(chart, metadata, true)
	chart["difficulty"] = dst
	var src_notes_count := 0
	var src_notes_var: Variant = chart.get("notes", [])
	if src_notes_var is Array:
		src_notes_count = (src_notes_var as Array).size()

	var cleaned_method := method.strip_edges().to_lower()
	if cleaned_method == "smart clone":
		if waveform == null or not waveform.is_ready():
			return {"ok": false, "error": "Smart Clone requires a loaded waveform (WAV currently)."}
		var smart: Dictionary = _smart_clone_chart(chart, src, dst, waveform)
		chart = smart.get("chart", chart) as Dictionary
		chart = ChartMetadataResolver.apply_metadata_to_chart(chart, metadata, true)
		chart["difficulty"] = dst
		var save2 := save_chart(song_folder, dst, chart)
		if not bool(save2.get("ok", false)):
			return {"ok": false, "error": "Failed to save cloned chart."}
		return {
			"ok": true,
			"path": str(save2.get("path", "")),
			"src_notes": src_notes_count,
			"dst_notes": int(smart.get("dst_notes", 0)),
			"copied": int(smart.get("copied", 0)),
			"added": int(smart.get("added", 0)),
			"removed": int(smart.get("removed", 0)),
		}
	var save := save_chart(song_folder, dst, chart)
	if not bool(save.get("ok", false)):
		return {"ok": false, "error": "Failed to save cloned chart."}
	return {
		"ok": true,
		"path": str(save.get("path", "")),
		"src_notes": src_notes_count,
		"dst_notes": src_notes_count,
		"copied": src_notes_count,
		"added": 0,
		"removed": 0,
	}


static func _difficulty_rank(id: String) -> int:
	var cleaned := id.strip_edges().to_lower()
	var ids := DifficultyManager.all_ids()
	return maxi(0, ids.find(cleaned))


static func _smart_clone_chart(src_chart: Dictionary, src_id: String, dst_id: String, waveform: WaveformRenderer) -> Dictionary:
	var chart: Dictionary = src_chart.duplicate(true)
	chart["difficulty"] = dst_id
	var notes_var: Variant = chart.get("notes", [])
	if notes_var is not Array:
		return {"chart": chart, "dst_notes": 0, "copied": 0, "added": 0, "removed": 0}
	var notes: Array = notes_var as Array
	var src_rank := _difficulty_rank(src_id)
	var dst_rank := _difficulty_rank(dst_id)
	var src_count := notes.size()

	# Sort by time then lane.
	notes.sort_custom(func(a: Variant, b: Variant) -> bool:
		if a is not Dictionary or b is not Dictionary:
			return false
		var da := a as Dictionary
		var db := b as Dictionary
		var ta := float(da.get("time", 0.0))
		var tb := float(db.get("time", 0.0))
		if ta == tb:
			return int(da.get("lane", 0)) < int(db.get("lane", 0))
		return ta < tb
	)

	if dst_rank < src_rank:
		# Downscale: keep fewer notes biased toward waveform peaks.
		var steps_down := src_rank - dst_rank
		var ratio := pow(0.65, float(steps_down))
		var target := maxi(1, int(roundf(float(notes.size()) * ratio)))
		var kept: Array = _select_notes_by_peak(notes, target, waveform)
		_assign_sequential_ids(kept)
		chart["notes"] = kept
		return {
			"chart": chart,
			"dst_notes": kept.size(),
			"copied": kept.size(),
			"added": 0,
			"removed": maxi(0, src_count - kept.size()),
		}

	if dst_rank > src_rank:
		# Upscale: add notes at prominent peaks where there's no nearby note.
		var steps_up := dst_rank - src_rank
		var ratio_up := pow(1.35, float(steps_up))
		var target_up := int(roundf(float(notes.size()) * ratio_up))
		var augmented: Array = _add_notes_by_peak(notes, target_up, waveform)
		_assign_sequential_ids(augmented)
		chart["notes"] = augmented
		return {
			"chart": chart,
			"dst_notes": augmented.size(),
			"copied": src_count,
			"added": maxi(0, augmented.size() - src_count),
			"removed": 0,
		}

	_assign_sequential_ids(notes)
	chart["notes"] = notes
	return {
		"chart": chart,
		"dst_notes": notes.size(),
		"copied": notes.size(),
		"added": 0,
		"removed": 0,
	}


static func _select_notes_by_peak(notes: Array, target_count: int, waveform: WaveformRenderer) -> Array:
	# Score each note by waveform peak and keep the best while enforcing spacing.
	var scored: Array[Dictionary] = []
	for n_var in notes:
		if n_var is not Dictionary:
			continue
		var n: Dictionary = n_var as Dictionary
		var t := float(n.get("time", 0.0))
		var score := waveform.peak_at_time(t)
		scored.append({"note": n, "score": score})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("score", 0.0)) > float(b.get("score", 0.0))
	)

	var kept: Array = []
	var min_spacing := 0.20
	for entry in scored:
		var n: Dictionary = entry.get("note", {}) as Dictionary
		var t := float(n.get("time", 0.0))
		var ok := true
		for k_var in kept:
			var k: Dictionary = k_var as Dictionary
			if absf(float(k.get("time", 0.0)) - t) < min_spacing:
				ok = false
				break
		if not ok:
			continue
		kept.append(n)
		if kept.size() >= target_count:
			break

	# If spacing prevented enough notes, fill by time order.
	if kept.size() < target_count:
		var remaining := target_count - kept.size()
		for n_var in notes:
			if remaining <= 0:
				break
			if n_var is not Dictionary:
				continue
			var n: Dictionary = n_var as Dictionary
			if kept.has(n):
				continue
			kept.append(n)
			remaining -= 1

	kept.sort_custom(func(a: Variant, b: Variant) -> bool:
		var da := a as Dictionary
		var db := b as Dictionary
		return float(da.get("time", 0.0)) < float(db.get("time", 0.0))
	)
	return kept


static func _add_notes_by_peak(notes: Array, target_count: int, waveform: WaveformRenderer) -> Array:
	var augmented: Array = notes.duplicate(true)
	if augmented.size() >= target_count:
		return augmented

	# Build peak candidates by scanning over time.
	var length := waveform.length_sec()
	var step := 0.01
	var candidates: Array[Dictionary] = []
	var t := 0.0
	while t <= length:
		var p := waveform.peak_at_time(t)
		# Threshold tuned to pick energetic moments.
		if p >= 0.35:
			candidates.append({"time": t, "score": p})
		t += step
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("score", 0.0)) > float(b.get("score", 0.0))
	)

	var existing_times: Array[float] = []
	for n_var in augmented:
		if n_var is not Dictionary:
			continue
		existing_times.append(float((n_var as Dictionary).get("time", 0.0)))

	var min_spacing := 0.08
	var lane_cycle := 0
	var lane_count := LaneCountResolver.infer_from_notes(notes, LaneCountResolver.DEFAULT_LANES)
	for c in candidates:
		if augmented.size() >= target_count:
			break
		var ct := float(c.get("time", 0.0))
		var too_close := false
		for et in existing_times:
			if absf(et - ct) < min_spacing:
				too_close = true
				break
		if too_close:
			continue
		var new_note := {
			"time": ct,
			"lane": lane_cycle % lane_count,
			"type": "tap",
		}
		augmented.append(new_note)
		existing_times.append(ct)
		lane_cycle += 1

	augmented.sort_custom(func(a: Variant, b: Variant) -> bool:
		var da := a as Dictionary
		var db := b as Dictionary
		return float(da.get("time", 0.0)) < float(db.get("time", 0.0))
	)
	return augmented


static func _assign_sequential_ids(notes: Array) -> void:
	for i in range(notes.size()):
		if notes[i] is Dictionary:
			(notes[i] as Dictionary)["id"] = i


static func compute_chart_stats(chart: Dictionary) -> Dictionary:
	var notes_var: Variant = chart.get("notes", [])
	if notes_var is not Array:
		return {"note_count": 0, "hold_count": 0, "tap_count": 0, "duration_sec": 0.0, "nps": 0.0}
	var notes: Array = notes_var as Array
	var taps := 0
	var holds := 0
	var first_t := INF
	var last_t := 0.0
	for n_var in notes:
		if n_var is not Dictionary:
			continue
		var n: Dictionary = n_var as Dictionary
		var t := float(n.get("time", 0.0))
		var kind := str(n.get("type", "tap")).to_lower()
		if kind == "hold" and float(n.get("length", 0.0)) > 0.0:
			holds += 1
		else:
			taps += 1
		first_t = minf(first_t, t)
		last_t = maxf(last_t, t + maxf(0.0, float(n.get("length", 0.0))))
	var duration := 0.0
	if first_t != INF:
		duration = maxf(0.0, last_t - first_t)
	var count := taps + holds
	var nps := 0.0
	if duration > 0.001:
		nps = float(count) / duration
	return {"note_count": count, "hold_count": holds, "tap_count": taps, "duration_sec": duration, "nps": nps}
