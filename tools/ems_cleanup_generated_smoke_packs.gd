extends SceneTree

const EMSPackLoader := preload("res://systems/ems/EMSPackLoader.gd")


func _initialize() -> void:
	var results := EMSPackLoader.cleanup_loadout_menu_noise()
	var deleted := 0
	for result in results:
		if bool(result.get("ok", false)):
			deleted += 1
			print("Deleted generated or invalid EMS pack: %s" % str(result.get("path", "")))
		else:
			push_warning("Could not delete generated or invalid EMS pack: %s" % str(result.get("message", "")))
	print("Generated/invalid EMS pack cleanup complete. Deleted %d pack folder(s)." % deleted)
	quit(0)
