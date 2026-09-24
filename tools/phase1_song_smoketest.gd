extends SceneTree

const SongDatabase := preload("res://scripts/songs/SongDatabase.gd")


func _initialize() -> void:
	print("user:// resolves to: %s" % ProjectSettings.globalize_path("user://"))
	var db := SongDatabase.new()
	db.reload()

	var songs := db.get_songs()
	var errors := db.get_load_errors()
	var warnings := db.get_load_warnings()

	print("SongDatabase: %d songs loaded" % songs.size())
	if not warnings.is_empty():
		print("Warnings (%d):" % warnings.size())
		for w in warnings:
			print("- %s: %s (%s)" % [str(w.get("code", "")), str(w.get("message", "")), str(w.get("path", ""))])

	if not errors.is_empty():
		print("Errors (%d):" % errors.size())
		for e in errors:
			print("- %s: %s (%s)" % [str(e.get("code", "")), str(e.get("message", "")), str(e.get("path", ""))])
		quit(1)
	else:
		quit(0)
