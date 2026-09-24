extends SceneTree

const GameModeConfig := preload("res://scripts/gameplay/GameModeConfig.gd")
const ContentRegistryScript := preload("res://autoload/ContentRegistry.gd")


func _initialize() -> void:
	var expected_order: Array[String] = [
		GameModeConfig.STEMS_MAPPED,
		GameModeConfig.STEMS_RANDOM,
		GameModeConfig.SYNTHESIZED,
	]
	if not _assert(GameModeConfig.ORDER == expected_order, "Game mode order is incorrect"):
		return
	if not _assert(GameModeConfig.DEFAULT_MODE == GameModeConfig.STEMS_MAPPED, "Default mode should be Classic"):
		return
	if not _assert(GameModeConfig.get_display_name(GameModeConfig.STEMS_MAPPED) == "Classic", "Stems Mapped display name should be Classic"):
		return
	if not _assert(GameModeConfig.get_short_label(GameModeConfig.STEMS_MAPPED) == "Classic", "Stems Mapped short label should be Classic"):
		return
	if not _assert(GameModeConfig.get_required_level(GameModeConfig.STEMS_MAPPED) == 1, "Classic unlock level should be 1"):
		return
	if not _assert(GameModeConfig.get_required_level(GameModeConfig.STEMS_RANDOM) == 4, "Stems Random unlock level should be 4"):
		return
	if not _assert(GameModeConfig.get_display_name(GameModeConfig.STEMS_RANDOM) == "Lane Shuffle", "Stems Random display name should be Lane Shuffle"):
		return
	if not _assert(GameModeConfig.get_short_label(GameModeConfig.STEMS_RANDOM) == "Shuffle", "Stems Random short label should be Shuffle"):
		return
	if not _assert(GameModeConfig.get_required_level(GameModeConfig.SYNTHESIZED) == 7, "Remix unlock level should be 7"):
		return

	var song_entry := {
		"modes": {
			GameModeConfig.SYNTHESIZED: {"charts": {"Medium": "res://example_synth.json"}},
			GameModeConfig.STEMS_RANDOM: {"charts": {"Medium": "res://example_random.json"}},
			GameModeConfig.STEMS_MAPPED: {"charts": {"Medium": "res://example_mapped.json"}},
		}
	}
	var registry := ContentRegistryScript.new()
	if not _assert(registry.get_supported_modes(song_entry) == expected_order, "ContentRegistry did not preserve central mode order"):
		registry.free()
		return
	registry.free()

	print("GameModeConfig smoke test passed: %s" % ", ".join(expected_order))
	quit(0)


func _assert(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
		quit(1)
		return false
	return true
