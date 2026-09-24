extends RefCounted
class_name SngImporter

const Utils := preload("res://scripts/editor/importers/ChartImportUtils.gd")
const ChartImporter := preload("res://scripts/editor/importers/ChartImporter.gd")
const MidiImporter := preload("res://scripts/editor/importers/MidiChartImporter.gd")
const OsuManiaImporter := preload("res://scripts/editor/importers/OsuManiaImporter.gd")


static func inspect_file(path: String, extract_folder: String = "") -> Dictionary:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < 64:
		return {"ok": false, "error": "SNG file is too small or unreadable.", "entries": [], "metadata": {}, "extracted": {}}
	if bytes.slice(0, 6).get_string_from_utf8() != "SNGPKG":
		return {"ok": false, "error": "Unsupported SNG file: missing SNGPKG header.", "entries": [], "metadata": {}, "extracted": {}}

	var mask := bytes.slice(10, 26)
	var offset := 26
	var metadata_len := Utils.read_u64_le(bytes, offset)
	offset += 8
	var metadata_end := offset + metadata_len
	var metadata_count := Utils.read_u64_le(bytes, offset)
	offset += 8
	var metadata := {}
	for _i in range(metadata_count):
		if offset + 4 > bytes.size():
			break
		var key_len := Utils.read_i32_le(bytes, offset)
		offset += 4
		var key := bytes.slice(offset, offset + key_len).get_string_from_utf8()
		offset += key_len
		var value_len := Utils.read_i32_le(bytes, offset)
		offset += 4
		var value := bytes.slice(offset, offset + value_len).get_string_from_utf8()
		offset += value_len
		metadata[key] = Utils.strip_rich_text(value)

	offset = metadata_end
	var file_index_len := Utils.read_u64_le(bytes, offset)
	offset += 8
	var file_index_end := offset + file_index_len
	var file_count := Utils.read_u64_le(bytes, offset)
	offset += 8
	var files: Array[Dictionary] = []
	for _i in range(file_count):
		if offset >= bytes.size():
			break
		var name_len := int(bytes[offset])
		offset += 1
		var filename := bytes.slice(offset, offset + name_len).get_string_from_utf8()
		offset += name_len
		var contents_len := Utils.read_u64_le(bytes, offset)
		offset += 8
		var contents_index := Utils.read_u64_le(bytes, offset)
		offset += 8
		files.append({"name": filename, "length": contents_len, "index": contents_index})

	var extracted := {}
	var notes_text := ""
	var notes_chart_name := ""
	var osu_text := ""
	var osu_name := ""
	var midi_bytes := PackedByteArray()
	var midi_name := ""
	var packaged_names: Array[String] = []
	for entry in files:
		var name := str(entry.get("name", ""))
		packaged_names.append(name)
		var length := int(entry.get("length", 0))
		var index := int(entry.get("index", 0))
		if index < 0 or length <= 0 or index + length > bytes.size():
			continue
		var decoded := _decode_payload(bytes.slice(index, index + length), mask)
		var file_name := name.get_file()
		var lower_name := file_name.to_lower()
		if lower_name.ends_with(".chart") and notes_text.is_empty():
			notes_text = decoded.get_string_from_utf8()
			notes_chart_name = file_name
		elif lower_name.ends_with(".osu") and osu_text.is_empty():
			osu_text = decoded.get_string_from_utf8()
			osu_name = file_name
		elif (lower_name.ends_with(".mid") or lower_name.ends_with(".midi")) and midi_bytes.is_empty():
			midi_bytes = decoded
			midi_name = file_name
		if not extract_folder.is_empty() and _should_extract_file(name):
			var target := extract_folder.path_join(file_name.to_lower())
			var f := FileAccess.open(target, FileAccess.WRITE)
			if f != null:
				f.store_buffer(decoded)
				f.flush()
				extracted[name] = target

	var chart_result := {}
	if notes_text.is_empty():
		if not osu_text.is_empty():
			chart_result = OsuManiaImporter.inspect_text(osu_text, osu_name if not osu_name.is_empty() else path.get_file())
		elif not midi_bytes.is_empty():
			chart_result = MidiImporter.inspect_bytes(midi_bytes, midi_name if not midi_name.is_empty() else path.get_file())
		else:
			return {
				"ok": false,
				"error": "SNG did not contain a supported chart file (.osu, .chart, .mid, or .midi). Packaged files: %s" % ", ".join(packaged_names),
				"entries": [],
				"metadata": metadata,
				"extracted": extracted,
			}
	else:
		chart_result = ChartImporter.inspect_text(notes_text, notes_chart_name if not notes_chart_name.is_empty() else path.get_file())
	if not bool(chart_result.get("ok", false)):
		chart_result["extracted"] = extracted
		return chart_result

	var chart_meta := chart_result.get("metadata", {}) as Dictionary
	var merged_meta := {
		"title": Utils.strip_rich_text(str(metadata.get("name", chart_meta.get("title", path.get_basename())))),
		"artist": Utils.strip_rich_text(str(metadata.get("artist", chart_meta.get("artist", "Unknown Artist")))),
		"charter": Utils.strip_rich_text(str(metadata.get("charter", chart_meta.get("charter", "Unknown Charter")))),
		"bpm": float(chart_meta.get("bpm", 120.0)),
	}
	return {
		"ok": true,
		"error": "",
		"entries": chart_result.get("entries", []) as Array,
		"metadata": merged_meta,
		"extracted": extracted,
	}


static func _decode_payload(masked: PackedByteArray, mask: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(masked.size())
	for i in range(masked.size()):
		out[i] = int(masked[i]) ^ (int(mask[i % 16]) ^ (i & 255))
	return out


static func _should_extract_file(filename: String) -> bool:
	var lower := filename.get_file().to_lower()
	return lower == "song.opus" or lower == "song.ogg" or lower == "song.mp3" or lower == "song.wav" or lower == "background.jpg" or lower == "background.jpeg" or lower == "background.png" or lower == "album.jpg" or lower == "album.jpeg" or lower == "album.png" or lower == "video.mp4" or lower.ends_with(".osu") or lower.ends_with(".chart") or lower.ends_with(".mid") or lower.ends_with(".midi")
