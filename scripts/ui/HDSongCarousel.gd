extends Control
class_name HDSongCarousel

const HDTheme = preload("res://scripts/ui/HDTheme.gd")
const HDUIMotion = preload("res://scripts/ui/HDUIMotion.gd")
const SongJacketService = preload("res://scripts/ui/SongJacketService.gd")

signal song_changed(song: Dictionary)
signal song_activated(song: Dictionary)

var songs: Array[Dictionary] = []
var selected_index := 0
var title_provider := Callable()
var artist_provider := Callable()
var bpm_provider := Callable()
var difficulty_provider := Callable()
var best_provider := Callable()
var badge_provider := Callable()

var _cards: Array[PanelContainer] = []
var _card_holder: Control
var _left_nav_button: Button
var _right_nav_button: Button
var _move_tween: Tween
var _is_animating := false
var _touch_start_x := 0.0
var _hover_scroll_direction := 0
var _hover_scroll_rate := 0.0
var _hover_elapsed := 0.0
var _hover_armed := false
const HOVER_NAV_INITIAL_DELAY := 0.34
const HOVER_NAV_MIN_RATE := 0.55
const HOVER_NAV_MAX_RATE := 4.25
const HOVER_NAV_LEFT_START := 0.38
const HOVER_NAV_RIGHT_START := 0.62
const CENTER_CARD_BASE := Vector2(330, 420)
const SIDE_CARD_BASE := Vector2(210, 305)
const CENTER_JACKET_BASE := Vector2(154, 154)
const SIDE_JACKET_BASE := Vector2(92, 92)


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(0, 360)
	_build_layout()
	refresh()
	set_process(true)
	mouse_exited.connect(_set_hover_scroll.bind(0, 0.0))


func configure(song_entries: Array[Dictionary], selected_song_id: String = "", providers: Dictionary = {}) -> void:
	songs = song_entries.duplicate(true)
	title_provider = providers.get("title", Callable()) as Callable
	artist_provider = providers.get("artist", Callable()) as Callable
	bpm_provider = providers.get("bpm", Callable()) as Callable
	difficulty_provider = providers.get("difficulty", Callable()) as Callable
	best_provider = providers.get("best", Callable()) as Callable
	badge_provider = providers.get("badge", Callable()) as Callable
	selected_index = 0
	if not selected_song_id.is_empty():
		for index in songs.size():
			if _song_id(songs[index]) == selected_song_id:
				selected_index = index
				break
	refresh()


func get_selected_song() -> Dictionary:
	if songs.is_empty():
		return {}
	return (songs[wrapi(selected_index, 0, songs.size())] as Dictionary).duplicate(true)


func select_song_id(song_id: String, emit_change: bool = false) -> void:
	if song_id.is_empty():
		return
	for index in songs.size():
		if _song_id(songs[index]) == song_id:
			selected_index = index
			refresh()
			_layout_cards()
			if emit_change:
				song_changed.emit(get_selected_song())
			return


func move(delta: int) -> void:
	if songs.is_empty() or delta == 0 or _is_animating:
		return
	var direction := 1 if delta > 0 else -1
	_play_navigation_sound(direction)
	_animate_move(direction)
	song_changed.emit(get_selected_song())


func refresh() -> void:
	if _cards.is_empty():
		return
	for i in _cards.size():
		_populate_card(_cards[i], i - 1)


func _build_layout() -> void:
	for child in get_children():
		child.queue_free()
	_cards.clear()
	_left_nav_button = null
	_right_nav_button = null
	var root := Control.new()
	root.name = "CarouselRoot"
	root.set_anchors_preset(PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_card_holder = Control.new()
	_card_holder.name = "CarouselCards"
	_card_holder.set_anchors_preset(PRESET_FULL_RECT)
	_card_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_card_holder)
	for offset in [-1, 0, 1]:
		var card := _build_card(offset == 0)
		_card_holder.add_child(card)
		_cards.append(card)
	_build_nav_button(root, -1)
	_build_nav_button(root, 1)
	_layout_cards()
	call_deferred("_layout_nav_buttons")


func _build_card(center: bool) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "SelectedSongCard" if center else "SideSongCard"
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	card.custom_minimum_size = CENTER_CARD_BASE if center else SIDE_CARD_BASE
	card.modulate = Color.WHITE if center else Color(1, 1, 1, 0.52)
	card.add_theme_stylebox_override("panel", HDTheme.song_card_style(HDTheme.CYAN, center))
	if center:
		card.focus_mode = Control.FOCUS_ALL
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.gui_input.connect(_on_center_card_input)
	else:
		card.mouse_filter = Control.MOUSE_FILTER_PASS
	var margin := MarginContainer.new()
	margin.name = "CardMargin"
	margin.add_theme_constant_override("margin_left", 14 if center else 10)
	margin.add_theme_constant_override("margin_top", 14 if center else 10)
	margin.add_theme_constant_override("margin_right", 14 if center else 10)
	margin.add_theme_constant_override("margin_bottom", 14 if center else 10)
	card.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.name = "CardVBox"
	vbox.alignment = BoxContainer.ALIGNMENT_BEGIN
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 6 if center else 3)
	margin.add_child(vbox)
	var jacket_frame := CenterContainer.new()
	jacket_frame.name = "JacketFrame"
	jacket_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	jacket_frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	jacket_frame.custom_minimum_size = CENTER_JACKET_BASE if center else SIDE_JACKET_BASE
	vbox.add_child(jacket_frame)
	var jacket := TextureRect.new()
	jacket.name = "Jacket"
	jacket.custom_minimum_size = CENTER_JACKET_BASE if center else SIDE_JACKET_BASE
	jacket.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	jacket.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	jacket.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	jacket.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	jacket_frame.add_child(jacket)
	for label_name in ["Title", "Artist", "Meta", "Best", "Difficulty", "Badge"]:
		var label := Label.new()
		label.name = label_name
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.clip_text = false
		label.max_lines_visible = _label_max_lines(label_name, center)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.custom_minimum_size.y = _label_height(label_name, center)
		vbox.add_child(label)
	return card


func _populate_card(card: PanelContainer, offset: int) -> void:
	card.visible = not songs.is_empty()
	if songs.is_empty():
		return
	var center := offset == 0
	var index := wrapi(selected_index + offset, 0, songs.size())
	var song: Dictionary = songs[index]
	var accent: Color = HDTheme.LANE_COLORS[wrapi(index, 0, HDTheme.LANE_COLORS.size())]
	card.add_theme_stylebox_override("panel", HDTheme.song_card_style(accent, center))
	card.modulate = Color.WHITE if center else Color(1, 1, 1, 0.52)
	var vbox: VBoxContainer = card.get_node("CardMargin/CardVBox")
	_apply_card_density(card, center)
	var jacket_frame: CenterContainer = vbox.get_node("JacketFrame")
	var jacket: TextureRect = jacket_frame.get_node("Jacket")
	jacket.texture = SongJacketService.texture_for_song(song)
	var jacket_size := _jacket_size(center)
	jacket_frame.custom_minimum_size = jacket_size
	jacket.custom_minimum_size = jacket_size
	_set_label(vbox.get_node("Title"), _call_or_default(title_provider, song, _title(song)), "section_title" if center else "body", HDTheme.primary_text(), center)
	_set_label(vbox.get_node("Artist"), _call_or_default(artist_provider, song, _artist(song)), "body" if center else "supporting", HDTheme.SECONDARY, center)
	_set_label(vbox.get_node("Meta"), "%s  •  %s" % [_call_or_default(bpm_provider, song, _bpm_label(song)), _section_label(song)], "supporting", HDTheme.TERTIARY, center)
	_set_label(vbox.get_node("Best"), _call_or_default(best_provider, song, ""), "supporting", accent, center)
	_set_label(vbox.get_node("Difficulty"), _call_or_default(difficulty_provider, song, ""), "supporting", HDTheme.SECONDARY, center)
	_set_label(vbox.get_node("Badge"), _call_or_default(badge_provider, song, ""), "caption", HDTheme.PERFECT if center else HDTheme.TERTIARY, center)
	HDUIMotion.stop_breathing(card)
	card.scale = Vector2.ONE


func _build_nav_button(parent: Control, direction: int) -> void:
	var button := Button.new()
	button.name = "LeftNavigateButton" if direction < 0 else "RightNavigateButton"
	button.text = "‹" if direction < 0 else "›"
	button.tooltip_text = "Previous song" if direction < 0 else "Next song"
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.custom_minimum_size = Vector2(58, 96)
	button.add_theme_font_size_override("font_size", 48)
	button.add_theme_color_override("font_color", Color(1, 1, 1, 0.90))
	button.add_theme_stylebox_override("normal", _nav_button_style(false))
	button.add_theme_stylebox_override("hover", _nav_button_style(true))
	button.add_theme_stylebox_override("pressed", _nav_button_style(true))
	button.pressed.connect(move.bind(direction))
	button.mouse_entered.connect(_set_hover_scroll.bind(0, 0.0))
	button.mouse_exited.connect(_set_hover_scroll.bind(0, 0.0))
	HDUIMotion.attach_button(button)
	parent.add_child(button)
	if direction < 0:
		_left_nav_button = button
	else:
		_right_nav_button = button


func _nav_button_style(active: bool) -> StyleBoxFlat:
	var style := HDTheme.glass_panel_style(HDTheme.CYAN, false)
	style.bg_color = Color(0.02, 0.05, 0.12, 0.44 if active else 0.26)
	style.border_color = HDTheme.CYAN * Color(1, 1, 1, 0.24 if active else 0.12)
	style.shadow_color = HDTheme.CYAN * Color(1, 1, 1, 0.08 if active else 0.04)
	style.shadow_size = 8 if active else 4
	return style


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		if not _is_animating:
			_layout_cards()
		_layout_nav_buttons()


func _layout_nav_buttons() -> void:
	if _left_nav_button == null or _right_nav_button == null:
		return
	var button_size := Vector2(58, clampf(size.y * 0.34, 96.0, 166.0))
	var y := (size.y - button_size.y) * 0.5
	_left_nav_button.position = Vector2(18, y)
	_left_nav_button.size = button_size
	_right_nav_button.position = Vector2(size.x - button_size.x - 18, y)
	_right_nav_button.size = button_size


func _layout_cards() -> void:
	if _cards.is_empty():
		return
	for index in _cards.size():
		var offset := index - 1
		var layout := _card_layout(offset)
		var card := _cards[index]
		card.custom_minimum_size = layout["size"]
		card.position = layout["position"]
		card.size = layout["size"]
		card.pivot_offset = card.size * 0.5


func _animate_move(direction: int) -> void:
	if _move_tween != null and is_instance_valid(_move_tween):
		_move_tween.kill()
	for card in _cards:
		HDUIMotion.stop_breathing(card)
	_is_animating = true
	selected_index = wrapi(selected_index + direction, 0, songs.size())
	refresh()
	for index in _cards.size():
		var offset := index - 1
		var start_offset := offset + direction
		var start_layout := _card_layout(start_offset)
		var end_layout := _card_layout(offset)
		var card := _cards[index]
		card.custom_minimum_size = end_layout["size"]
		card.position = start_layout["position"]
		card.size = start_layout["size"]
		card.pivot_offset = card.size * 0.5
		card.modulate.a = 0.0 if abs(start_offset) > 1 else (1.0 if start_offset == 0 else 0.52)
	_move_tween = create_tween()
	_move_tween.set_parallel(true)
	for index in _cards.size():
		var offset := index - 1
		var end_layout := _card_layout(offset)
		var card := _cards[index]
		_move_tween.tween_property(card, "position", end_layout["position"], 0.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_move_tween.tween_property(card, "size", end_layout["size"], 0.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_move_tween.tween_property(card, "modulate:a", 1.0 if offset == 0 else 0.52, 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_move_tween.finished.connect(func() -> void:
		_is_animating = false
		_layout_cards()
		refresh()
	)


func _card_layout(offset: int) -> Dictionary:
	var viewport_size := size
	if viewport_size.x <= 1.0 or viewport_size.y <= 1.0:
		viewport_size = Vector2(maxf(custom_minimum_size.x, 980.0), maxf(custom_minimum_size.y, 465.0))
	var center_size := _card_size(true)
	var side_size := _card_size(false)
	var gap := clampf(viewport_size.x * 0.028, 18.0, 44.0)
	var center_x := (viewport_size.x - center_size.x) * 0.5
	var center_y := (viewport_size.y - center_size.y) * 0.5
	var left_x := center_x - side_size.x - gap
	var right_x := center_x + center_size.x + gap
	var layout_size := center_size if offset == 0 else side_size
	var x := center_x
	if offset < 0:
		x = left_x - float(abs(offset) - 1) * (side_size.x + gap)
	elif offset > 0:
		x = right_x + float(offset - 1) * (side_size.x + gap)
	var y := (viewport_size.y - layout_size.y) * 0.5
	return {
		"position": Vector2(x, y if offset != 0 else center_y),
		"size": layout_size,
	}


func _card_size(center: bool) -> Vector2:
	return (CENTER_CARD_BASE if center else SIDE_CARD_BASE) * _card_scale()


func _card_scale() -> float:
	var viewport_size := size
	if viewport_size.x <= 1.0 or viewport_size.y <= 1.0:
		viewport_size = Vector2(980, 465)
	var height_scale := (viewport_size.y - 14.0) / CENTER_CARD_BASE.y
	var width_scale := viewport_size.x / 1120.0
	return clampf(minf(width_scale, height_scale), 0.60, 0.92)


func _jacket_size(center: bool) -> Vector2:
	var viewport_size := size
	if viewport_size.x <= 1.0 or viewport_size.y <= 1.0:
		viewport_size = Vector2(980, 465)
	var scale := _card_scale()
	return (CENTER_JACKET_BASE if center else SIDE_JACKET_BASE) * scale


func _apply_card_density(card: PanelContainer, center: bool) -> void:
	var scale := _card_scale()
	var margin := card.get_node("CardMargin") as MarginContainer
	var vbox := margin.get_node("CardVBox") as VBoxContainer
	var outer_margin := int(round((14.0 if center else 10.0) * scale))
	margin.add_theme_constant_override("margin_left", outer_margin)
	margin.add_theme_constant_override("margin_top", outer_margin)
	margin.add_theme_constant_override("margin_right", outer_margin)
	margin.add_theme_constant_override("margin_bottom", outer_margin)
	vbox.add_theme_constant_override("separation", max(2, int(round((6.0 if center else 3.0) * scale))))
	for label_name in ["Title", "Artist", "Meta", "Best", "Difficulty", "Badge"]:
		var label := vbox.get_node(label_name) as Label
		label.custom_minimum_size.y = _label_height(label_name, center) * scale


func _label_height(label_name: String, center: bool) -> float:
	if label_name == "Title":
		return 78.0 if center else 58.0
	if label_name == "Artist":
		return 38.0 if center else 32.0
	if label_name == "Meta":
		return 27.0 if center else 23.0
	return 23.0 if center else 19.0


func _label_max_lines(label_name: String, center: bool) -> int:
	if label_name == "Title":
		return 4 if center else 3
	if label_name == "Artist":
		return 2
	return 1


func _set_label(label: Label, text: String, role: String, tone: Color, center: bool) -> void:
	label.text = text
	label.visible = not text.strip_edges().is_empty()
	HDTheme.apply_label(label, role, tone, true)
	label.add_theme_font_size_override("font_size", _label_font_size(role, center))


func _label_font_size(role: String, center: bool) -> int:
	var scale := clampf(_card_scale(), 0.70, 1.0)
	var base_size := 14
	if center:
		match role:
			"section_title":
				base_size = 25
			"body":
				base_size = 20
			"supporting":
				base_size = 18
			_:
				base_size = 16
		return maxi(13, int(roundf(float(base_size) * scale)))
	match role:
		"body":
			base_size = 18
		"supporting":
			base_size = 16
		_:
			base_size = 14
	return maxi(12, int(roundf(float(base_size) * scale)))


func _call_or_default(provider: Callable, song: Dictionary, fallback: String) -> String:
	return str(provider.call(song)) if provider.is_valid() else fallback


func _on_center_card_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		song_activated.emit(get_selected_song())
		accept_event()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_WHEEL_UP:
			move(-1)
			accept_event()
		elif mouse.pressed and mouse.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			move(1)
			accept_event()
		elif mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			if mouse.position.x < size.x * 0.28:
				move(-1)
				accept_event()
			elif mouse.position.x > size.x * 0.72:
				move(1)
				accept_event()
	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_touch_start_x = touch.position.x
		else:
			var delta := touch.position.x - _touch_start_x
			if absf(delta) > 44.0:
				move(-1 if delta > 0.0 else 1)
				accept_event()
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		_update_hover_zone(motion.position)


func _process(delta: float) -> void:
	if _hover_scroll_direction == 0 or songs.size() <= 1:
		return
	if _is_animating:
		return
	_hover_elapsed += delta
	var repeat_delay := 1.0 / maxf(HOVER_NAV_MIN_RATE, _hover_scroll_rate)
	var initial_delay := clampf(HOVER_NAV_INITIAL_DELAY / maxf(1.0, _hover_scroll_rate * 0.62), 0.12, HOVER_NAV_INITIAL_DELAY)
	var delay := initial_delay if _hover_armed else repeat_delay
	if _hover_elapsed >= delay:
		_hover_elapsed = 0.0
		_hover_armed = false
		move(_hover_scroll_direction)


func _update_hover_zone(local_position: Vector2) -> void:
	if _point_over_nav_button(local_position):
		_set_hover_scroll(0, 0.0)
		return
	var left_start := size.x * HOVER_NAV_LEFT_START
	var right_start := size.x * HOVER_NAV_RIGHT_START
	if local_position.x < left_start:
		var strength := clampf((left_start - local_position.x) / maxf(1.0, left_start), 0.0, 1.0)
		_set_hover_scroll(-1, lerpf(HOVER_NAV_MIN_RATE, HOVER_NAV_MAX_RATE, strength))
	elif local_position.x > right_start:
		var strength := clampf((local_position.x - right_start) / maxf(1.0, size.x - right_start), 0.0, 1.0)
		_set_hover_scroll(1, lerpf(HOVER_NAV_MIN_RATE, HOVER_NAV_MAX_RATE, strength))
	else:
		_set_hover_scroll(0, 0.0)


func _point_over_nav_button(local_position: Vector2) -> bool:
	for button in [_left_nav_button, _right_nav_button]:
		if button != null and is_instance_valid(button):
			var rect := Rect2(button.position, button.size)
			if rect.has_point(local_position):
				return true
	return false


func _set_hover_scroll(direction: int, rate: float) -> void:
	if _hover_scroll_direction == direction and is_equal_approx(_hover_scroll_rate, rate):
		return
	_hover_scroll_direction = direction
	_hover_scroll_rate = rate
	_hover_elapsed = 0.0
	_hover_armed = direction != 0


func _play_navigation_sound(direction: int) -> void:
	var ui_audio := _ui_audio()
	if ui_audio == null or not ui_audio.has_method("play_navigation"):
		return
	ui_audio.call("play_navigation", direction, 1.08)


func _ui_audio() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null("UIAudio")


func _song_id(song: Dictionary) -> String:
	return str(song.get("id", song.get("song_id", "")))


func _title(song: Dictionary) -> String:
	return str(song.get("display_name", song.get("title", "Unknown")))


func _artist(song: Dictionary) -> String:
	return str(song.get("artist", "Unknown Artist"))


func _section_label(song: Dictionary) -> String:
	return str(song.get("section_name", "CUSTOM" if str(song.get("source", "")) == "custom" else "TRACK"))


func _bpm_label(song: Dictionary) -> String:
	var bpm := float(song.get("bpm", 0.0))
	if bpm <= 0.0:
		return "-- BPM"
	if is_equal_approx(bpm, roundf(bpm)):
		return "%d BPM" % int(roundf(bpm))
	return "%.2f BPM" % bpm
