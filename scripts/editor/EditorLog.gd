extends RefCounted
class_name EditorLog

static func info(tag: String, message: String) -> void:
	print("[ChartEditor][%s] %s" % [tag, message])


static func warn(tag: String, message: String) -> void:
	push_warning("[ChartEditor][%s] %s" % [tag, message])


static func err(tag: String, message: String) -> void:
	push_error("[ChartEditor][%s] %s" % [tag, message])
