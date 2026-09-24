extends SceneTree

const EditorAudioImporter := preload("res://scripts/editor/importers/EditorAudioImporter.gd")
const WaveformRenderer := preload("res://scripts/editor/WaveformRenderer.gd")
const SongJacketService := preload("res://scripts/ui/SongJacketService.gd")

const SIZE := 256
const EXPORT_SIZE := 1024
const OUT_DIR := "res://assets/jackets"
const TEMP_DIR := "user://jacket_wav_cache"


func _initialize() -> void:
	await process_frame
	var failures: Array[String] = []
	var requested_song_id := _requested_song_id()
	var generated_count := 0
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEMP_DIR))
	var content_registry := root.get_node("ContentRegistry")
	var songs: Array = content_registry.call("get_songs")
	for song in songs:
		var song_id := str((song as Dictionary).get("id", "")).strip_edges()
		if not requested_song_id.is_empty() and song_id != requested_song_id:
			continue
		generated_count += 1
		var result := _generate_for_song(song)
		if not bool(result.get("ok", false)):
			failures.append("%s: %s" % [str(song.get("id", "unknown")), str(result.get("error", "unknown error"))])
	if not requested_song_id.is_empty() and generated_count == 0:
		failures.append("%s: song id was not found in the official catalog" % requested_song_id)
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("Generated %d song jacket%s in %s." % [generated_count, "" if generated_count == 1 else "s", OUT_DIR])
	quit(0)


func _requested_song_id() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--song-id="):
			return argument.trim_prefix("--song-id=").strip_edges()
	return ""


func _generate_for_song(song: Dictionary) -> Dictionary:
	var song_id := str(song.get("id", "")).strip_edges()
	if song_id.is_empty():
		return {"ok": false, "error": "missing song id"}
	var audio_path := str(song.get("audio_path", ""))
	if audio_path.is_empty():
		return {"ok": false, "error": "missing audio_path"}
	var wav_path := TEMP_DIR.path_join("%s.wav" % song_id)
	var converted := EditorAudioImporter.convert_to_wav(audio_path, wav_path)
	if not bool(converted.get("ok", false)):
		return converted
	var wav := AudioStreamWAV.load_from_file(wav_path)
	if wav == null:
		return {"ok": false, "error": "failed to load decoded WAV"}
	var waveform := WaveformRenderer.new()
	waveform.prepare_from_stream(wav)
	var progression := root.get_node("ProgressionManager")
	var section: Dictionary = progression.call("get_section_for_song", song_id)
	var section_id := int(section.get("section_id", 0))
	var section_name: String = progression.call("get_section_display_name", section_id)
	var analysis := _analyze_wav(wav, waveform)
	var image := _compose_jacket(song, section_id, section_name, analysis)
	image.resize(EXPORT_SIZE, EXPORT_SIZE, Image.INTERPOLATE_CUBIC)
	var path := OUT_DIR.path_join("%s.png" % song_id)
	var err := image.save_png(path)
	if err != OK:
		return {"ok": false, "error": "save_png failed: %s" % err}
	return {"ok": true}


func _analyze_wav(wav: AudioStreamWAV, waveform: WaveformRenderer) -> Dictionary:
	var pcm: PackedByteArray = wav.get_data() if wav.has_method("get_data") else (wav.get("data") as PackedByteArray)
	var mix_rate := int(wav.get_mix_rate())
	var channels := 2 if bool(wav.is_stereo()) else 1
	var frame_bytes := 2 * channels
	var total_frames := pcm.size() / frame_bytes
	var stride := maxi(1, total_frames / 12000)
	var bass := 0.0
	var melody := 0.0
	var energy := 0.0
	var previous := 0.0
	var count := 0
	for frame in range(0, total_frames, stride):
		var amp := _read_frame(pcm, frame * frame_bytes, channels)
		energy += absf(amp)
		bass += absf(lerpf(previous, amp, 0.18))
		melody += absf(amp - previous)
		previous = amp
		count += 1
	var safe_count := maxf(1.0, float(count))
	var peaks: Array[float] = []
	var duration := maxf(0.0, waveform.length_sec())
	var peak_count := 128
	for i in peak_count:
		var t := duration * float(i) / float(maxi(1, peak_count - 1))
		peaks.append(waveform.peak_at_time_interpolated(t))
	return {
		"duration": duration if duration > 0.0 else float(total_frames) / float(maxi(1, mix_rate)),
		"bass": clampf(bass / safe_count * 2.2, 0.0, 1.0),
		"melody": clampf(melody / safe_count * 18.0, 0.0, 1.0),
		"energy": clampf(energy / safe_count * 2.7, 0.0, 1.0),
		"peaks": peaks,
	}


func _compose_jacket(song: Dictionary, section_id: int, section_name: String, analysis: Dictionary) -> Image:
	var palette := SongJacketService.section_palette(section_name, section_id)
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	_draw_background(image, palette, str(song.get("id", "")))
	var center := Vector2(SIZE, SIZE) * 0.5
	var bass := float(analysis.get("bass", 0.4))
	var melody := float(analysis.get("melody", 0.4))
	var energy := float(analysis.get("energy", 0.4))
	_draw_particles(image, center, palette, energy, str(song.get("id", "")))
	_draw_spectrum_rings(image, center, palette, bass, melody)
	_draw_waveform(image, center, palette, analysis.get("peaks", []) as Array)
	_draw_title_bands(image, str(song.get("display_name", "Unknown")), section_name, float(song.get("bpm", 0.0)))
	return image


func _draw_background(image: Image, palette: Array, seed_text: String) -> void:
	var seed := hash(seed_text)
	for y in SIZE:
		var yf := float(y) / float(SIZE - 1)
		for x in SIZE:
			var xf := float(x) / float(SIZE - 1)
			var dist := Vector2(xf - 0.5, yf - 0.5).length()
			var grad := (palette[0] as Color).lerp(palette[1] as Color, yf)
			var pulse := sin(xf * 11.0 + yf * 7.0 + float(seed % 1000) * 0.01) * 0.5 + 0.5
			var glow := clampf(1.0 - dist * 1.65, 0.0, 1.0)
			image.set_pixel(x, y, grad.lerp(palette[2] as Color, glow * 0.32 + pulse * 0.055))


func _draw_spectrum_rings(image: Image, center: Vector2, palette: Array, bass: float, melody: float) -> void:
	var scale := float(SIZE) / 1024.0
	var inner_radius := (155.0 + bass * 92.0) * scale
	var outer_radius := (305.0 + melody * 90.0) * scale
	for i in 96:
		var a0 := TAU * float(i) / 96.0
		var a1 := TAU * float(i + 1) / 96.0
		var wobble := sin(float(i) * 0.43 + bass * 8.0) * 26.0 * scale
		_draw_line(image, center + Vector2(cos(a0), sin(a0)) * (inner_radius - wobble), center + Vector2(cos(a1), sin(a1)) * (inner_radius + wobble), palette[2] as Color, 2)
	for i in 144:
		var angle := TAU * float(i) / 144.0
		var length := (24.0 + sin(float(i) * 0.31) * 14.0 + melody * 52.0) * scale
		var dir := Vector2(cos(angle), sin(angle))
		_draw_line(image, center + dir * outer_radius, center + dir * (outer_radius + length), palette[3] as Color, 1)


func _draw_waveform(image: Image, center: Vector2, palette: Array, peaks: Array) -> void:
	if peaks.is_empty():
		return
	var scale := float(SIZE) / 1024.0
	var width := 760.0 * scale
	var start_x := center.x - width * 0.5
	var y_mid := center.y + 250.0 * scale
	for i in peaks.size() - 1:
		var p0 := float(peaks[i])
		var p1 := float(peaks[i + 1])
		var x0 := start_x + width * float(i) / float(peaks.size() - 1)
		var x1 := start_x + width * float(i + 1) / float(peaks.size() - 1)
		_draw_line(image, Vector2(x0, y_mid - p0 * 90.0 * scale), Vector2(x1, y_mid - p1 * 90.0 * scale), palette[2] as Color, 1)
		_draw_line(image, Vector2(x0, y_mid + p0 * 90.0 * scale), Vector2(x1, y_mid + p1 * 90.0 * scale), palette[3] as Color, 1)


func _draw_particles(image: Image, center: Vector2, palette: Array, energy: float, seed_text: String) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_text)
	var count := 90 + int(energy * 260.0)
	var scale := float(SIZE) / 1024.0
	for i in count:
		var angle := rng.randf_range(0.0, TAU)
		var radius := rng.randf_range(80.0 * scale, 465.0 * scale)
		var pos := center + Vector2(cos(angle), sin(angle)) * radius
		var size := rng.randi_range(1, 3)
		_draw_disc(image, pos, size, (palette[2 + (i % 2)] as Color) * Color(1, 1, 1, rng.randf_range(0.30, 0.78)))


func _draw_title_bands(image: Image, title: String, section_name: String, bpm: float) -> void:
	var band := Color(0.0, 0.0, 0.0, 0.38)
	var band_top := int(float(SIZE) * 0.78)
	var band_bottom := int(float(SIZE) * 0.95)
	for y in range(band_top, band_bottom):
		for x in SIZE:
			image.set_pixel(x, y, image.get_pixel(x, y).lerp(band, band.a))
	var text_seed := hash("%s:%s:%s" % [title, section_name, bpm])
	for i in 24:
		var y: int = band_top + 9 + i * 2
		var w: int = 60 + abs((text_seed >> (i % 12)) % 130)
		var x: int = 24 + abs((text_seed >> (i % 8)) % 30)
		_draw_line(image, Vector2(x, y), Vector2(mini(SIZE - 24, x + w), y), Color(1, 1, 1, 0.42 if i < 9 else 0.22), 1)


func _draw_disc(image: Image, center: Vector2, radius: int, color: Color) -> void:
	var min_x := clampi(int(center.x) - radius, 0, SIZE - 1)
	var max_x := clampi(int(center.x) + radius, 0, SIZE - 1)
	var min_y := clampi(int(center.y) - radius, 0, SIZE - 1)
	var max_y := clampi(int(center.y) + radius, 0, SIZE - 1)
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var d := Vector2(x, y).distance_to(center)
			if d <= float(radius):
				image.set_pixel(x, y, image.get_pixel(x, y).lerp(color, color.a * (1.0 - d / float(radius + 1))))


func _draw_line(image: Image, from: Vector2, to: Vector2, color: Color, thickness: int = 1) -> void:
	var steps := maxi(1, int(from.distance_to(to)))
	for i in range(steps + 1):
		var p := from.lerp(to, float(i) / float(steps))
		_draw_disc(image, p, thickness, color)


func _read_frame(pcm: PackedByteArray, base: int, channels: int) -> float:
	var total := 0.0
	for c in channels:
		var o := base + c * 2
		if o + 1 >= pcm.size():
			break
		var v := (int(pcm[o + 1]) << 8) | int(pcm[o])
		if v >= 32768:
			v -= 65536
		total += float(v) / 32768.0
	return total / float(maxi(1, channels))
