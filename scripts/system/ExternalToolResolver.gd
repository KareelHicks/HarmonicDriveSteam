extends RefCounted
class_name ExternalToolResolver

const CACHE_ROOT := "user://external_tools"


static func resolve_tool(resource_path: String, system_candidates: Array[String], probe_args: Array[String]) -> String:
	var bundled := _resolve_bundled_tool(resource_path, probe_args)
	if not bundled.is_empty():
		return bundled
	for candidate in system_candidates:
		if _candidate_runs(candidate, probe_args):
			return candidate
	return ""


static func _resolve_bundled_tool(resource_path: String, probe_args: Array[String]) -> String:
	if resource_path.strip_edges().is_empty() or not FileAccess.file_exists(resource_path):
		return ""

	var real_path := ProjectSettings.globalize_path(resource_path)
	if FileAccess.file_exists(real_path):
		_make_executable(real_path)
		if _candidate_runs(real_path, probe_args):
			return real_path

	var extracted_path := _extract_resource_tool(resource_path)
	if extracted_path.is_empty():
		return ""
	_make_executable(extracted_path)
	return extracted_path if _candidate_runs(extracted_path, probe_args) else ""


static func _extract_resource_tool(resource_path: String) -> String:
	var source := FileAccess.open(resource_path, FileAccess.READ)
	if source == null:
		return ""
	var platform := _platform_folder()
	var target_dir := CACHE_ROOT.path_join(platform)
	var target_abs_dir := ProjectSettings.globalize_path(target_dir)
	if DirAccess.make_dir_recursive_absolute(target_abs_dir) != OK:
		return ""
	var target_path := target_dir.path_join(resource_path.get_file())
	var target_abs := ProjectSettings.globalize_path(target_path)
	var target := FileAccess.open(target_abs, FileAccess.WRITE)
	if target == null:
		return ""
	target.store_buffer(source.get_buffer(source.get_length()))
	target.flush()
	return target_abs


static func _candidate_runs(candidate: String, probe_args: Array[String]) -> bool:
	if candidate.strip_edges().is_empty():
		return false
	var args: Array[String] = []
	for arg in probe_args:
		args.append(str(arg))
	var output: Array = []
	var code := OS.execute(candidate, args, output, true, false)
	return code == 0


static func _make_executable(path: String) -> void:
	if OS.get_name().to_lower().contains("windows"):
		return
	for chmod_path in ["/bin/chmod", "/usr/bin/chmod", "chmod"]:
		var output: Array = []
		var code := OS.execute(chmod_path, ["755", path], output, true, false)
		if code == 0:
			return


static func _platform_folder() -> String:
	var platform := OS.get_name().to_lower()
	if platform.contains("windows"):
		return "windows"
	if platform.contains("mac"):
		return "macos"
	return "linux"
