extends Control

const HDTheme = preload("res://scripts/ui/HDTheme.gd")
const MenuNavigator = preload("res://scripts/ui/MenuNavigator.gd")

signal back_requested
var _menu_navigator: MenuNavigator


func _ready() -> void:
	_menu_navigator = MenuNavigator.install(self, Callable(self, "_on_back_button_pressed"))
	_apply_layout()
	get_viewport().size_changed.connect(_apply_layout)
	%Background.color = HDTheme.BG
	%Panel.add_theme_stylebox_override("panel", HDTheme.overlay_panel_style())


func _apply_layout() -> void:
	var size := get_viewport_rect().size
	var metrics := HDTheme.overlay_metrics(size)
	%Panel.custom_minimum_size = Vector2(metrics["panel_width"], metrics["panel_height"] * 0.58)
	HDTheme.apply_label(%BackLabel, "caption", HDTheme.SECONDARY)
	%BackLabel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	HDTheme.apply_back_button($BackButton, %BackLabel)
	$BackButton.offset_left = 40.0
	$BackButton.offset_top = 34.0
	$BackButton.offset_right = 192.0
	$BackButton.offset_bottom = 78.0
	HDTheme.apply_label(%TitleLabel, "screen_title", HDTheme.CYAN, true)
	HDTheme.apply_label(%MessageLabel, "body", HDTheme.SECONDARY, true)


func configure(payload: Dictionary) -> void:
	%TitleLabel.text = str(payload.get("title", "INFO"))
	%MessageLabel.text = str(payload.get("message", ""))


func _on_back_button_pressed() -> void:
	back_requested.emit()
