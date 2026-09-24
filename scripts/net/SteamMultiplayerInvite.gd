extends RefCounted

const GameModeConfig = preload("res://scripts/gameplay/GameModeConfig.gd")


static func resolve_classic_bootstrap_mode(bootstrap: Dictionary, current_selection: Dictionary) -> String:
	var fallback_mode := str(current_selection.get("mode", GameModeConfig.DEFAULT_MODE))
	if not GameModeConfig.is_valid(fallback_mode):
		fallback_mode = GameModeConfig.DEFAULT_MODE
	var mode := str(bootstrap.get("mode", fallback_mode))
	if not GameModeConfig.is_valid(mode):
		mode = fallback_mode
	return mode
