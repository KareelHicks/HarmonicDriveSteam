extends PanelContainer
class_name HDListRow

const HDTheme = preload("res://scripts/ui/HDTheme.gd")
const SongJacketService = preload("res://scripts/ui/SongJacketService.gd")
const HDUIMotion = preload("res://scripts/ui/HDUIMotion.gd")
const TAP_DRAG_THRESHOLD := 22.0

signal activated

@onready var _accent: ColorRect = %Accent
@onready var _title: Label = %Title
@onready var _subtitle: Label = %Subtitle
@onready var _cta: Label = %CTA
@onready var _badge: Label = %Badge
@onready var _jacket: TextureRect = %Jacket

var _pointer_active := false
var _press_position := Vector2.ZERO
var _touch_scroll_suppressed := false
var _accent_color := HDTheme.CYAN


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	focus_entered.connect(_on_focus_changed.bind(true))
	focus_exited.connect(_on_focus_changed.bind(false))
	mouse_entered.connect(_on_focus_changed.bind(true))
	mouse_exited.connect(_on_focus_changed.bind(false))
	HDUIMotion.attach_control(self)


func configure(title: String, subtitle: String, cta_text: String, accent_color: Color, badge_text: String = "", jacket_texture: Texture2D = null) -> void:
	var metrics: Dictionary = HDTheme.list_metrics(get_viewport_rect().size)
	custom_minimum_size = Vector2(0, metrics["row_height"])
	_accent_color = accent_color
	_apply_focus_style(false)
	_accent.color = accent_color
	_jacket.texture = jacket_texture if jacket_texture != null else SongJacketService.texture_for_song(title)
	_title.text = title
	_subtitle.text = subtitle
	_cta.text = cta_text
	_badge.visible = not badge_text.is_empty()
	_badge.text = badge_text
	HDTheme.apply_label(_title, "section_title")
	HDTheme.apply_label(_subtitle, "body", HDTheme.SECONDARY)
	HDTheme.apply_label(_cta, "button_secondary", HDTheme.CYAN, false)
	HDTheme.apply_label(_badge, "caption", HDTheme.TERTIARY, true)
	_cta.custom_minimum_size.x = metrics["trailing_action_width"]
	if AppState.is_mobile_platform():
		mouse_filter = Control.MOUSE_FILTER_PASS


func activate() -> void:
	activated.emit()


func set_touch_scroll_suppressed(suppressed: bool) -> void:
	_touch_scroll_suppressed = suppressed
	if suppressed:
		_pointer_active = false


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		activated.emit()
	if event is InputEventScreenTouch:
		if event.pressed:
			_begin_pointer(event.position)
		elif _should_activate(event.position):
			activated.emit()
		_end_pointer()
		return

	if event is InputEventScreenDrag:
		_update_drag(event.position)
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin_pointer(event.position)
		elif _should_activate(event.position):
			activated.emit()
		_end_pointer()
		return

	if event is InputEventMouseMotion:
		_update_drag(event.position)


func _begin_pointer(position: Vector2) -> void:
	_pointer_active = true
	_press_position = position
	_touch_scroll_suppressed = false


func _update_drag(position: Vector2) -> void:
	if not _pointer_active:
		return
	if position.distance_to(_press_position) >= TAP_DRAG_THRESHOLD:
		_touch_scroll_suppressed = true


func _should_activate(position: Vector2) -> bool:
	return _pointer_active \
		and not _touch_scroll_suppressed \
		and position.distance_to(_press_position) < TAP_DRAG_THRESHOLD


func _end_pointer() -> void:
	_pointer_active = false
	_touch_scroll_suppressed = false


func _on_focus_changed(focused: bool) -> void:
	_apply_focus_style(focused)


func _apply_focus_style(focused: bool) -> void:
	var style: StyleBoxFlat = HDTheme.song_card_style(_accent_color, focused)
	if focused:
		style.border_color = _accent_color
		style.border_width_left = maxi(style.border_width_left, 2)
		style.border_width_top = maxi(style.border_width_top, 2)
		style.border_width_right = maxi(style.border_width_right, 2)
		style.border_width_bottom = maxi(style.border_width_bottom, 2)
		style.bg_color = style.bg_color.lerp(_accent_color, 0.08)
	add_theme_stylebox_override("panel", style)
