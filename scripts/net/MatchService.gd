extends RefCounted
class_name MatchService


func is_available() -> bool:
	return false


func start_matchmaking() -> Dictionary:
	return {"ok": false, "message": "Multiplayer is not implemented in the Godot v1 build."}
