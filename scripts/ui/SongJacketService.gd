extends RefCounted
class_name SongJacketService

const JACKET_DIR := "res://assets/jackets"
const FALLBACK_SIZE := 256


static func jacket_path_for_song(song_entry_or_id: Variant) -> String:
	var song_id := _song_id(song_entry_or_id)
	if song_id.is_empty():
		return ""
	return "%s/%s.png" % [JACKET_DIR, _jacket_id(song_id)]


static func texture_for_song(song_entry_or_id: Variant) -> Texture2D:
	var path := jacket_path_for_song(song_entry_or_id)
	if not path.is_empty() and ResourceLoader.exists(path):
		var texture := load(path) as Texture2D
		if texture != null:
			return texture
	if not path.is_empty() and _file_exists_exact(path):
		var image := Image.load_from_file(path)
		if image != null:
			return ImageTexture.create_from_image(image)
	return ImageTexture.create_from_image(fallback_image(song_entry_or_id, FALLBACK_SIZE))


static func fallback_image(song_entry_or_id: Variant, size: int = FALLBACK_SIZE) -> Image:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var song_id := _song_id(song_entry_or_id)
	var title := _song_title(song_entry_or_id)
	var palette := section_palette(_section_name(song_entry_or_id), int(_section_id(song_entry_or_id)))
	var seed := hash("%s:%s" % [song_id, title])
	for y in size:
		var yf := float(y) / float(maxi(1, size - 1))
		for x in size:
			var xf := float(x) / float(maxi(1, size - 1))
			var base := (palette[0] as Color).lerp(palette[1] as Color, yf)
			var dist := Vector2(xf - 0.5, yf - 0.5).length()
			var glow := clampf(1.0 - dist * 1.75, 0.0, 1.0)
			var wave := sin((xf * 8.0 + yf * 5.0) + float(seed % 1000) * 0.017) * 0.5 + 0.5
			var color := base.lerp(palette[2] as Color, glow * 0.45 + wave * 0.10)
			image.set_pixel(x, y, Color(color.r, color.g, color.b, 1.0))
	_draw_ring(image, Vector2(size, size) * 0.5, float(size) * 0.28, float(size) * 0.028, palette[2] as Color)
	_draw_ring(image, Vector2(size, size) * 0.5, float(size) * 0.39, float(size) * 0.012, palette[3] as Color)
	return image


static func section_palette(section_name: String, section_id: int = 0) -> Array:
	var key := section_name.strip_edges().to_lower()
	match key:
		"arrival":
			return [Color(0.02, 0.07, 0.16), Color(0.08, 0.22, 0.38), Color(0.30, 0.92, 1.0), Color(0.80, 1.0, 1.0)]
		"warmup":
			return [Color(0.08, 0.04, 0.10), Color(0.30, 0.10, 0.18), Color(1.0, 0.55, 0.22), Color(1.0, 0.88, 0.45)]
		"pulse":
			return [Color(0.06, 0.02, 0.12), Color(0.16, 0.05, 0.30), Color(0.95, 0.20, 1.0), Color(0.24, 0.90, 1.0)]
		"flow":
			return [Color(0.01, 0.08, 0.12), Color(0.03, 0.20, 0.25), Color(0.15, 1.0, 0.72), Color(0.48, 0.92, 1.0)]
		"drift":
			return [Color(0.05, 0.06, 0.14), Color(0.13, 0.12, 0.28), Color(0.60, 0.64, 1.0), Color(0.95, 0.70, 1.0)]
		"groove":
			return [Color(0.07, 0.04, 0.02), Color(0.26, 0.12, 0.04), Color(1.0, 0.76, 0.20), Color(1.0, 0.34, 0.18)]
		"lift":
			return [Color(0.02, 0.08, 0.08), Color(0.07, 0.22, 0.19), Color(0.55, 1.0, 0.62), Color(0.20, 0.92, 1.0)]
		"motion":
			return [Color(0.01, 0.06, 0.12), Color(0.05, 0.14, 0.24), Color(0.15, 0.82, 1.0), Color(0.85, 1.0, 1.0)]
		"energy":
			return [Color(0.10, 0.03, 0.02), Color(0.28, 0.08, 0.04), Color(1.0, 0.32, 0.12), Color(1.0, 0.92, 0.18)]
		"surge":
			return [Color(0.05, 0.01, 0.13), Color(0.16, 0.04, 0.36), Color(0.55, 0.35, 1.0), Color(1.0, 0.25, 0.86)]
		"drive":
			return [Color(0.02, 0.02, 0.07), Color(0.08, 0.08, 0.18), Color(0.95, 0.95, 1.0), Color(0.22, 0.92, 1.0)]
		"rush":
			return [Color(0.12, 0.02, 0.03), Color(0.34, 0.04, 0.10), Color(1.0, 0.18, 0.32), Color(1.0, 0.78, 0.24)]
		"euphoria":
			return [Color(0.08, 0.01, 0.09), Color(0.26, 0.04, 0.24), Color(1.0, 0.26, 0.70), Color(0.98, 0.82, 1.0)]
		"voltage":
			return [Color(0.02, 0.03, 0.04), Color(0.13, 0.10, 0.03), Color(1.0, 0.82, 0.22), Color(1.0, 1.0, 0.92)]
		_:
			var palettes := [
				[Color(0.02, 0.07, 0.14), Color(0.06, 0.16, 0.28), Color(0.18, 0.84, 1.0), Color(0.92, 1.0, 1.0)],
				[Color(0.06, 0.02, 0.12), Color(0.14, 0.05, 0.28), Color(0.65, 0.34, 1.0), Color(1.0, 0.40, 0.82)],
				[Color(0.10, 0.04, 0.02), Color(0.24, 0.08, 0.04), Color(1.0, 0.52, 0.18), Color(1.0, 0.90, 0.35)],
			]
			return palettes[wrapi(maxi(0, section_id - 1), 0, palettes.size())]


static func _draw_ring(image: Image, center: Vector2, radius: float, thickness: float, color: Color) -> void:
	var min_x := clampi(int(center.x - radius - thickness), 0, image.get_width() - 1)
	var max_x := clampi(int(center.x + radius + thickness), 0, image.get_width() - 1)
	var min_y := clampi(int(center.y - radius - thickness), 0, image.get_height() - 1)
	var max_y := clampi(int(center.y + radius + thickness), 0, image.get_height() - 1)
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var d := Vector2(float(x), float(y)).distance_to(center)
			var edge := absf(d - radius)
			if edge <= thickness:
				var alpha := clampf(1.0 - edge / maxf(1.0, thickness), 0.0, 1.0) * color.a
				image.set_pixel(x, y, image.get_pixel(x, y).lerp(color, alpha))


static func _file_exists_exact(path: String) -> bool:
	if path.is_empty():
		return false
	var dir_path := path.get_base_dir()
	var file_name := path.get_file()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return false
	dir.list_dir_begin()
	while true:
		var current := dir.get_next()
		if current.is_empty():
			break
		if not dir.current_is_dir() and current == file_name:
			dir.list_dir_end()
			return true
	dir.list_dir_end()
	return false


static func _song_id(song_entry_or_id: Variant) -> String:
	if song_entry_or_id is Dictionary:
		var song: Dictionary = song_entry_or_id
		return str(song.get("id", song.get("song_id", song.get("title", "")))).strip_edges()
	return str(song_entry_or_id).strip_edges()


static func _jacket_id(song_id: String) -> String:
	var normalized := song_id.strip_edges().to_lower()
	var output := ""
	var last_was_separator := false
	for index in normalized.length():
		var character := normalized[index]
		var is_valid := (character >= "a" and character <= "z") or (character >= "0" and character <= "9")
		if is_valid:
			output += character
			last_was_separator = false
		elif not last_was_separator:
			output += "_"
			last_was_separator = true
	return output.strip_edges().trim_prefix("_").trim_suffix("_")


static func _song_title(song_entry_or_id: Variant) -> String:
	if song_entry_or_id is Dictionary:
		var song: Dictionary = song_entry_or_id
		return str(song.get("display_name", song.get("title", _song_id(song)))).strip_edges()
	return _song_id(song_entry_or_id)


static func _section_name(song_entry_or_id: Variant) -> String:
	if song_entry_or_id is Dictionary:
		var song: Dictionary = song_entry_or_id
		return str(song.get("section_name", song.get("section", "")))
	return ""


static func _section_id(song_entry_or_id: Variant) -> int:
	if song_entry_or_id is Dictionary:
		var song: Dictionary = song_entry_or_id
		return int(song.get("section_id", 0))
	return 0
