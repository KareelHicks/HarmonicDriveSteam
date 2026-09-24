extends Node

const GameModeConfig = preload("res://scripts/gameplay/GameModeConfig.gd")
const SongJacketService = preload("res://scripts/ui/SongJacketService.gd")
const MANIFEST_PATH := "res://content/manifests/song_manifest.json"
const PROGRESSION_PATH := "res://content/manifests/progression_manifest.json"
const DIFFICULTY_ORDER := ["Easy", "Medium", "Hard", "Expert", "Professional"]

var _songs: Array[Dictionary] = []
var _songs_by_id := {}
var _songs_by_display_name := {}
var _songs_by_chart_base_name := {}
var _progression_sections: Array[Dictionary] = []
var _progression_song_meta := {}
var _chart_hash_cache := {}


func _ready() -> void:
	reload_manifest()


func reload_manifest() -> void:
	_songs.clear()
	_songs_by_id.clear()
	_songs_by_display_name.clear()
	_songs_by_chart_base_name.clear()
	_progression_sections.clear()
	_progression_song_meta.clear()
	_chart_hash_cache.clear()

	if not FileAccess.file_exists(MANIFEST_PATH):
		push_warning("Song manifest not found at %s" % MANIFEST_PATH)
		return

	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_ARRAY:
		push_error("Song manifest is invalid")
		return

	for entry_variant in parsed:
		var entry: Dictionary = entry_variant
		if entry.is_empty():
			continue
		_songs.append(entry)
		var song_id: String = str(entry.get("id", ""))
		var display_name: String = str(entry.get("display_name", ""))
		var chart_base_name: String = str(entry.get("chart_base_name", ""))
		_songs_by_id[song_id] = entry
		if not display_name.is_empty():
			_songs_by_display_name[display_name] = entry
		if not chart_base_name.is_empty():
			_songs_by_chart_base_name[chart_base_name] = entry

	_songs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("display_name", "")) < str(b.get("display_name", ""))
	)
	_load_progression_manifest()


func _load_progression_manifest() -> void:
	if not FileAccess.file_exists(PROGRESSION_PATH):
		return
	var file := FileAccess.open(PROGRESSION_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var payload: Dictionary = parsed
	for section_variant in payload.get("sections", []):
		if section_variant is Dictionary:
			_progression_sections.append((section_variant as Dictionary).duplicate(true))
	var song_meta: Dictionary = payload.get("songs", {}) as Dictionary
	for key_variant in song_meta.keys():
		_progression_song_meta[str(key_variant)] = (song_meta[key_variant] as Dictionary).duplicate(true)


func get_songs() -> Array[Dictionary]:
	return _songs.duplicate(true)


func get_song(song_id: String) -> Dictionary:
	var entry: Dictionary = _resolve_song_entry(song_id)
	return entry.duplicate(true)


func get_jacket_path(song_entry_or_id: Variant) -> String:
	return SongJacketService.jacket_path_for_song(song_entry_or_id)


func get_song_id(song_ref: String) -> String:
	var entry: Dictionary = _resolve_song_entry(song_ref)
	return str(entry.get("id", ""))


func get_relay_song_id(song_ref: String) -> String:
	var entry: Dictionary = _resolve_song_entry(song_ref)
	if entry.is_empty():
		return song_ref
	var chart_base_name: String = str(entry.get("chart_base_name", ""))
	if not chart_base_name.is_empty():
		return chart_base_name
	var display_name: String = str(entry.get("display_name", ""))
	if not display_name.is_empty():
		return display_name
	return str(entry.get("id", song_ref))


func get_first_song() -> Dictionary:
	if _songs.is_empty():
		return {}
	return (_songs[0] as Dictionary).duplicate(true)


func _resolve_song_entry(song_ref: String) -> Dictionary:
	if _songs_by_id.has(song_ref):
		return _songs_by_id[song_ref] as Dictionary
	if _songs_by_chart_base_name.has(song_ref):
		return _songs_by_chart_base_name[song_ref] as Dictionary
	if _songs_by_display_name.has(song_ref):
		return _songs_by_display_name[song_ref] as Dictionary
	return {}


func get_supported_modes(song_entry: Dictionary) -> Array[String]:
	var available: Array[String] = []
	var modes := song_entry.get("modes", {}) as Dictionary
	for mode_id in GameModeConfig.ORDER:
		var source_mode: String = GameModeConfig.get_chart_source_mode(mode_id)
		if modes.has(mode_id) or (source_mode != mode_id and modes.has(source_mode)):
			available.append(mode_id)
	return available


func get_supported_difficulties(song_entry: Dictionary, mode: String = GameModeConfig.DEFAULT_MODE) -> Array[String]:
	var available: Array[String] = []
	var source_mode: String = GameModeConfig.get_chart_source_mode(mode)
	var mode_payload := (song_entry.get("modes", {}) as Dictionary).get(source_mode, {}) as Dictionary
	var charts := mode_payload.get("charts", {}) as Dictionary
	for difficulty in DIFFICULTY_ORDER:
		if charts.has(difficulty):
			available.append(difficulty)
	return available


func get_chart_path(song_entry: Dictionary, difficulty: String, mode: String = GameModeConfig.DEFAULT_MODE) -> String:
	var source_mode: String = GameModeConfig.get_chart_source_mode(mode)
	var mode_payload := (song_entry.get("modes", {}) as Dictionary).get(source_mode, {}) as Dictionary
	return str((mode_payload.get("charts", {}) as Dictionary).get(difficulty, ""))


func get_chart_hash(song_entry: Dictionary, difficulty: String, mode: String = GameModeConfig.DEFAULT_MODE) -> String:
	var chart_path: String = get_chart_path(song_entry, difficulty, mode)
	if chart_path.is_empty():
		return ""
	if _chart_hash_cache.has(chart_path):
		return str(_chart_hash_cache.get(chart_path, ""))
	if not FileAccess.file_exists(chart_path):
		return ""
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(chart_path)
	if bytes.is_empty():
		return ""
	var hash_context := HashingContext.new()
	var hash_error: int = hash_context.start(HashingContext.HASH_SHA256)
	if hash_error != OK:
		return ""
	hash_context.update(bytes)
	var chart_hash: String = hash_context.finish().hex_encode()
	_chart_hash_cache[chart_path] = chart_hash
	return chart_hash


func get_progression_sections() -> Array[Dictionary]:
	return _progression_sections.duplicate(true)


func get_progression_song_meta(song_id: String) -> Dictionary:
	return (_progression_song_meta.get(song_id, {}) as Dictionary).duplicate(true)


func get_progression_ordered_songs() -> Array[Dictionary]:
	if _progression_sections.is_empty():
		return get_songs()
	var ordered: Array[Dictionary] = []
	var included_song_ids := {}
	for section in _progression_sections:
		for song_id_variant in (section.get("songs", []) as Array):
			var song_id: String = str(song_id_variant)
			if _songs_by_id.has(song_id):
				ordered.append((_songs_by_id[song_id] as Dictionary).duplicate(true))
				included_song_ids[song_id] = true
	for song in _songs:
		var song_id := str(song.get("id", ""))
		if not included_song_ids.has(song_id):
			ordered.append(song.duplicate(true))
	return ordered
