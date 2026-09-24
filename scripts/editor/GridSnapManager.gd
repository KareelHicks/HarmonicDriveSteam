extends RefCounted
class_name GridSnapManager

signal snap_changed()
signal tempo_changed()

const SUPPORTED_DIVISIONS: Array[int] = [0, 1, 2, 4, 8, 16, 32]

var _bpm: float = 120.0
var _offset: float = 0.0
var _division: int = 4

var bpm: float:
	get: return _bpm
	set(value):
		_bpm = maxf(1.0, value)
		tempo_changed.emit()

var offset: float:
	get: return _offset
	set(value):
		_offset = value
		tempo_changed.emit()

var division: int:
	get: return _division
	set(value):
		_division = value if SUPPORTED_DIVISIONS.has(value) else 4
		snap_changed.emit()


func set_snap_string(label: String) -> void:
	var cleaned := label.strip_edges()
	if cleaned.to_lower() == "off":
		division = 0
		return
	if cleaned.begins_with("1/"):
		cleaned = cleaned.substr(2)
	var d := int(cleaned)
	division = d


func get_snap_string() -> String:
	return "Off" if division <= 0 else "1/%d" % division


func seconds_per_beat() -> float:
	return 60.0 / bpm


func seconds_per_step() -> float:
	if division <= 0:
		return 0.0
	return seconds_per_beat() / float(division)


func time_to_beat(time_sec: float) -> float:
	return (time_sec - offset) / seconds_per_beat()


func beat_to_time(beat: float) -> float:
	return offset + (beat * seconds_per_beat())


func snap_time(time_sec: float) -> float:
	var step := seconds_per_step()
	if step <= 0.0:
		return time_sec
	var snapped := roundf((time_sec - offset) / step) * step + offset
	return maxf(0.0, snapped)


func next_step_time(time_sec: float) -> float:
	var step := seconds_per_step()
	if step <= 0.0:
		return time_sec
	var n := floorf((time_sec - offset) / step) + 1.0
	return maxf(0.0, n * step + offset)


func prev_step_time(time_sec: float) -> float:
	var step := seconds_per_step()
	if step <= 0.0:
		return time_sec
	var n := ceilf((time_sec - offset) / step) - 1.0
	return maxf(0.0, n * step + offset)
