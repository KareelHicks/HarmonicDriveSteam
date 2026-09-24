extends Control

const HDTheme = preload("res://scripts/ui/HDTheme.gd")
const EMSLoadoutCatalog = preload("res://scripts/ems/EMSLoadoutCatalog.gd")
const ShopManager = preload("res://scripts/progression/ShopManager.gd")
const InertialScrollController = preload("res://scripts/ui/InertialScrollController.gd")
const MobileScrollButtonScript = preload("res://scripts/ui/MobileScrollButton.gd")
const MenuNavigator = preload("res://scripts/ui/MenuNavigator.gd")

signal back_requested
signal open_progression_requested

const LOADOUT_SECTION_THEME := "theme"
const LOADOUT_SECTION_EFFECT := "effect"
const LOADOUT_SECTION_SPEED_MODIFIER := "speed_modifier"
const LOADOUT_SECTION_CHART_MODIFIER := "modifier"
const LOADOUT_SECTION_EMS_LOADOUT := "ems_loadout"
const EMS_LOADOUT_PREVIEW_SIZE := Vector2(320, 180)

var _menu_navigator: MenuNavigator
var _active_loadout_section := LOADOUT_SECTION_EMS_LOADOUT
var _loadout_tab_buttons: Dictionary = {}
@onready var _back_button: Button = $Center/Panel/Margin/VBox/BackButton
@onready var _items_scroll: ScrollContainer = %ItemsScroll
@onready var _items_vbox: VBoxContainer = %ItemsVBox


func _ready() -> void:
	_apply_mobile_scroll_buttons()
	_menu_navigator = MenuNavigator.install(self, Callable(self, "_on_back_button_pressed"))
	InertialScrollController.install(_items_scroll, _items_vbox)
	_setup_loadout_tabs()
	_apply_layout()
	_rebuild()
	get_viewport().size_changed.connect(_apply_layout)
	ProgressionManager.progression_changed.connect(_rebuild)
	var registry := get_node_or_null("/root/EMSRegistry")
	if registry != null and registry.has_signal("registry_changed") and not registry.is_connected("registry_changed", Callable(self, "_rebuild")):
		registry.connect("registry_changed", Callable(self, "_rebuild"))


func _apply_layout() -> void:
	var size: Vector2 = get_viewport_rect().size
	var metrics: Dictionary = HDTheme.overlay_metrics(size)
	%Background.color = HDTheme.BG
	%Panel.add_theme_stylebox_override("panel", HDTheme.overlay_panel_style())
	%Panel.custom_minimum_size = Vector2(minf(size.x - 40.0, metrics["panel_width"] * 1.35), minf(size.y - 40.0, metrics["panel_height"] * 1.18))
	HDTheme.apply_label(%BackLabel, "caption", HDTheme.SECONDARY)
	%BackLabel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	HDTheme.apply_back_button(_back_button, %BackLabel)
	_back_button.size_flags_horizontal = 0
	%TitleLabel.text = "LOADOUT"
	HDTheme.apply_label(%TitleLabel, "screen_title", HDTheme.CYAN, true)
	HDTheme.apply_label(%CurrencyLabel, "body", HDTheme.SECONDARY, true)
	HDTheme.apply_label(%StatusLabel, "supporting", HDTheme.TERTIARY, true)
	%LoadoutTabGrid.columns = 2 if float(%Panel.custom_minimum_size.x) < 780.0 else (3 if float(%Panel.custom_minimum_size.x) < 1120.0 else 5)
	for button in [%ProgressionButton, %BackActionButton]:
		button.custom_minimum_size.y = metrics["button_height"]
		button.add_theme_font_size_override("font_size", HDTheme.text_size("button_secondary", size))
		button.add_theme_stylebox_override("normal", HDTheme.button_style(button == %ProgressionButton))
		button.add_theme_stylebox_override("hover", HDTheme.button_style(button == %ProgressionButton))
		button.add_theme_stylebox_override("pressed", HDTheme.button_style(button == %ProgressionButton))
	%ItemsVBox.add_theme_constant_override("separation", 12)
	%ItemsScroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_refresh_loadout_tab_styles()


func _rebuild() -> void:
	var player: Dictionary = ProgressionManager.get_player_data()
	var equipped: Dictionary = ProgressionManager.get_equipped_loadout()
	%CurrencyLabel.text = "VIBEZ %d  •  THEME %s  •  EFFECT %s  •  EMS %s" % [
		int(player.get("currency", 0)),
		str(equipped.get("theme", "theme_default")).trim_prefix("theme_").to_upper(),
		str(equipped.get("effect", "effect_none")).trim_prefix("effect_").to_upper(),
		str(equipped.get("ems_loadout_display_name", "Harmonic Core")).to_upper(),
	]
	%StatusLabel.text = "Buy new modifiers and tap owned items to equip or toggle them."
	for child in %ItemsVBox.get_children():
		child.queue_free()
	match _active_loadout_section:
		LOADOUT_SECTION_THEME:
			_build_shop_item_section(LOADOUT_SECTION_THEME, player)
		LOADOUT_SECTION_EFFECT:
			_build_shop_item_section(LOADOUT_SECTION_EFFECT, player)
		LOADOUT_SECTION_SPEED_MODIFIER:
			_build_shop_item_section(LOADOUT_SECTION_SPEED_MODIFIER, player)
		LOADOUT_SECTION_CHART_MODIFIER:
			_build_shop_item_section(LOADOUT_SECTION_CHART_MODIFIER, player)
		LOADOUT_SECTION_EMS_LOADOUT:
			_build_ems_sections(player)
		_:
			_build_ems_sections(player)
	call_deferred("_refresh_menu_navigation")


func _setup_loadout_tabs() -> void:
	_loadout_tab_buttons = {
		LOADOUT_SECTION_EMS_LOADOUT: %EMSLoadoutTabButton,
		LOADOUT_SECTION_THEME: %ThemeTabButton,
		LOADOUT_SECTION_EFFECT: %EffectTabButton,
		LOADOUT_SECTION_SPEED_MODIFIER: %SpeedModifierTabButton,
		LOADOUT_SECTION_CHART_MODIFIER: %ChartModifierTabButton,
	}
	for section in _loadout_tab_buttons.keys():
		var button := _loadout_tab_buttons[section] as Button
		var callback := Callable(self, "_set_loadout_section").bind(str(section))
		if button != null and not button.pressed.is_connected(callback):
			button.pressed.connect(callback)
	_refresh_loadout_tab_styles()


func _set_loadout_section(section: String) -> void:
	if not _loadout_tab_buttons.has(section):
		section = LOADOUT_SECTION_EMS_LOADOUT
	_active_loadout_section = section
	_refresh_loadout_tab_styles()
	_rebuild()
	if is_instance_valid(_items_scroll):
		_items_scroll.scroll_vertical = 0


func _refresh_loadout_tab_styles() -> void:
	if _loadout_tab_buttons.is_empty():
		return
	var size := get_viewport_rect().size
	for section in _loadout_tab_buttons.keys():
		var button := _loadout_tab_buttons[section] as Button
		if button == null:
			continue
		var active := str(section) == _active_loadout_section
		button.set_pressed_no_signal(active)
		button.custom_minimum_size = Vector2(160, 42)
		button.add_theme_font_size_override("font_size", HDTheme.text_size("button_secondary", size))
		button.add_theme_stylebox_override("normal", HDTheme.button_style(active))
		button.add_theme_stylebox_override("hover", HDTheme.button_style(active))
		button.add_theme_stylebox_override("pressed", HDTheme.button_style(true))
		button.add_theme_stylebox_override("focus", HDTheme.button_style(active))


func _build_shop_item_section(item_type: String, player: Dictionary) -> void:
	%ItemsVBox.add_child(_build_type_header(item_type))
	var items := ShopManager.get_items_by_type(item_type)
	if items.is_empty():
		%ItemsVBox.add_child(_build_empty_shop_row(item_type))
		return
	for item in items:
		%ItemsVBox.add_child(_build_item_card(item, player))


func _build_type_header(item_type: String) -> Label:
	var label := Label.new()
	match item_type:
		LOADOUT_SECTION_CHART_MODIFIER:
			label.text = "CHART MODIFIER"
		LOADOUT_SECTION_EMS_LOADOUT:
			label.text = "EMS LOADOUT"
		_:
			label.text = item_type.replace("_", " ").to_upper()
	HDTheme.apply_label(label, "section_title", HDTheme.CYAN)
	return label


func _build_empty_shop_row(item_type: String) -> Label:
	var label := Label.new()
	label.text = "No %s items found." % item_type.replace("_", " ")
	HDTheme.apply_label(label, "supporting", HDTheme.TERTIARY)
	return label


func _build_ems_sections(player: Dictionary) -> void:
	var registry := get_node_or_null("/root/EMSRegistry")
	if registry == null or not registry.has_method("get_entries_by_source"):
		%ItemsVBox.add_child(_build_type_header("ems_loadout"))
		for item in ShopManager.get_items_by_type("ems_loadout"):
			if EMSLoadoutCatalog.is_loadout_content_available(item):
				%ItemsVBox.add_child(_build_item_card(item, player))
		return
	var sections := [
		{"label": "Built-In EMS", "source": "built_in"},
		{"label": "Subscribed Workshop EMS", "source": "workshop"},
		{"label": "Local EMS", "source": "local"},
	]
	for section in sections:
		var entries: Array = _content_available_ems_entries(registry.call("get_entries_by_source", str(section.get("source", ""))) as Array)
		%ItemsVBox.add_child(_build_ems_header(str(section.get("label", "")), entries.size()))
		if entries.is_empty():
			%ItemsVBox.add_child(_build_empty_ems_row(str(section.get("source", ""))))
			continue
		for entry_variant in entries:
			if entry_variant is Dictionary:
				%ItemsVBox.add_child(_build_ems_card(entry_variant as Dictionary, player))


func _content_available_ems_entries(entries: Array) -> Array:
	var visible: Array = []
	for entry_variant in entries:
		if entry_variant is not Dictionary:
			continue
		var entry := entry_variant as Dictionary
		if EMSLoadoutCatalog.is_loadout_content_available(entry):
			visible.append(entry)
	return visible


func _build_ems_header(label_text: String, count: int) -> Label:
	var label := Label.new()
	label.text = "%s  (%d)" % [label_text.to_upper(), count]
	HDTheme.apply_label(label, "section_title", HDTheme.CYAN)
	return label


func _build_empty_ems_row(source: String) -> Label:
	var label := Label.new()
	match source:
		"workshop":
			label.text = "No subscribed Workshop EMS packs found."
		"local":
			label.text = "No local EMS packs found in user://ems/local/ or user://ems/exports/."
		_:
			label.text = "No EMS packs found."
	HDTheme.apply_label(label, "supporting", HDTheme.TERTIARY)
	return label


func _build_item_card(item: Dictionary, player: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", HDTheme.card_style())
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	margin.add_child(row)
	var text_vbox := VBoxContainer.new()
	text_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_vbox.add_theme_constant_override("separation", 6)
	row.add_child(text_vbox)
	var title := Label.new()
	title.text = str(item.get("display_name", "Item"))
	HDTheme.apply_label(title, "section_title")
	text_vbox.add_child(title)
	var desc := Label.new()
	desc.text = "%s  •  %s" % [str(item.get("description", "")), _item_state_label(item, player)]
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	HDTheme.apply_label(desc, "body", HDTheme.SECONDARY)
	text_vbox.add_child(desc)
	var button: Button = MobileScrollButtonScript.new() if AppState.is_mobile_platform() else Button.new()
	button.custom_minimum_size = Vector2(180, 56)
	button.text = _item_action_label(item, player)
	button.add_theme_stylebox_override("normal", HDTheme.button_style(true))
	button.add_theme_stylebox_override("hover", HDTheme.button_style(true))
	button.add_theme_stylebox_override("pressed", HDTheme.button_style(true))
	button.add_theme_font_size_override("font_size", HDTheme.text_size("button_secondary", get_viewport_rect().size))
	button.disabled = not _item_available_for_player(item, player)
	button.pressed.connect(_on_item_pressed.bind(str(item.get("id", ""))))
	row.add_child(button)
	return panel


func _build_ems_card(item: Dictionary, player: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", HDTheme.card_style())
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	margin.add_child(row)
	var preview := TextureRect.new()
	preview.custom_minimum_size = EMS_LOADOUT_PREVIEW_SIZE
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	preview.clip_contents = true
	preview.texture = _ems_preview_texture(str(item.get("preview_path", "")))
	row.add_child(preview)
	var text_vbox := VBoxContainer.new()
	text_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_vbox.add_theme_constant_override("separation", 5)
	row.add_child(text_vbox)
	var title := Label.new()
	title.text = str(item.get("display_name", "EMS Pack"))
	HDTheme.apply_label(title, "section_title")
	text_vbox.add_child(title)
	var meta := Label.new()
	meta.text = "%s  •  %s  •  %s  •  Motion %.0f%%  •  Particles %.0f%%  •  Reactive %s  •  %s" % [
		str(item.get("author", "Unknown")),
		str(item.get("source", "built_in")).to_upper(),
		str(item.get("pack_type", "built_in")).replace("_", " ").to_upper(),
		float(item.get("motion_intensity", 1.0)) * 100.0,
		float(item.get("particle_intensity", 1.0)) * 100.0,
		"YES" if bool(item.get("audio_reactive", true)) else "NO",
		_item_state_label(item, player),
	]
	meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	HDTheme.apply_label(meta, "body", HDTheme.SECONDARY)
	text_vbox.add_child(meta)
	var desc := Label.new()
	desc.text = str(item.get("description", ""))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	HDTheme.apply_label(desc, "supporting", HDTheme.TERTIARY)
	text_vbox.add_child(desc)
	var button: Button = MobileScrollButtonScript.new() if AppState.is_mobile_platform() else Button.new()
	button.custom_minimum_size = Vector2(180, 56)
	button.text = _item_action_label(item, player)
	button.add_theme_stylebox_override("normal", HDTheme.button_style(true))
	button.add_theme_stylebox_override("hover", HDTheme.button_style(true))
	button.add_theme_stylebox_override("pressed", HDTheme.button_style(true))
	button.add_theme_font_size_override("font_size", HDTheme.text_size("button_secondary", get_viewport_rect().size))
	button.disabled = not _item_available_for_player(item, player)
	button.pressed.connect(_on_item_pressed.bind(str(item.get("id", ""))))
	row.add_child(button)
	return panel


func _item_state_label(item: Dictionary, player: Dictionary) -> String:
	if str(item.get("validation_status", "valid")) == "invalid":
		return "INVALID"
	if not _item_available_for_player(item, player):
		return "UNLOCKS AT LEVEL %d" % int(item.get("required_level", 1))
	var item_id: String = str(item.get("id", ""))
	if str(item.get("type", "")) == "ems_loadout":
		var equipped_ems: Dictionary = ProgressionManager.get_equipped_loadout()
		return "EQUIPPED" if str(equipped_ems.get("ems_loadout", "")) == item_id else "OWNED"
	var owned: bool = _string_array(player.get("owned_items", [])).has(item_id)
	if not owned:
		return "%d VIBEZ" % int(item.get("price", 0))
	var equipped: Dictionary = ProgressionManager.get_equipped_loadout()
	match str(item.get("type", "")):
		"theme":
			return "EQUIPPED" if str(equipped.get("theme", "")) == item_id else "OWNED"
		"effect":
			return "EQUIPPED" if str(equipped.get("effect", "")) == item_id else "OWNED"
		"ems_loadout":
			return "EQUIPPED" if str(equipped.get("ems_loadout", "")) == item_id else "OWNED"
		"speed_modifier":
			return "EQUIPPED" if str(equipped.get("speed_modifier", "")) == item_id else "OWNED"
		"modifier":
			return "ENABLED" if _string_array(equipped.get("enabled_modifiers", [])).has(item_id) else "OWNED"
	return "OWNED"


func _item_action_label(item: Dictionary, player: Dictionary) -> String:
	if str(item.get("validation_status", "valid")) == "invalid":
		return "INVALID"
	if not _item_available_for_player(item, player):
		return "LEVEL %d" % int(item.get("required_level", 1))
	var item_id := str(item.get("id", ""))
	if str(item.get("type", "")) == "ems_loadout":
		var equipped_ems: Dictionary = ProgressionManager.get_equipped_loadout()
		return "EQUIPPED" if str(equipped_ems.get("ems_loadout", "")) == item_id else "EQUIP"
	var owned: bool = _string_array(player.get("owned_items", [])).has(item_id)
	if owned and str(item.get("type", "")) == "modifier":
		var equipped: Dictionary = ProgressionManager.get_equipped_loadout()
		return "DISABLE" if _string_array(equipped.get("enabled_modifiers", [])).has(item_id) else "ENABLE"
	return "BUY" if not owned else "EQUIP"


func _item_available_for_player(item: Dictionary, player: Dictionary) -> bool:
	if str(item.get("validation_status", "valid")) == "invalid":
		return false
	if str(item.get("type", "")) == "ems_loadout" or str(item.get("acquisition", "")) == "community":
		return true
	return int(player.get("level", 1)) >= int(item.get("required_level", 1))


func _on_item_pressed(item_id: String) -> void:
	var player: Dictionary = ProgressionManager.get_player_data()
	var owned: bool = _string_array(player.get("owned_items", [])).has(item_id)
	var item := ShopManager.get_item(item_id)
	var outcome: Dictionary = ProgressionManager.equip_item(item_id) if str(item.get("type", "")) == "ems_loadout" or str(item.get("acquisition", "")) == "community" else (ProgressionManager.purchase_item(item_id) if not owned else ProgressionManager.equip_item(item_id))
	%StatusLabel.text = str(outcome.get("message", "Updated."))


func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for item in value:
			result.append(str(item))
	return result


func _ems_preview_texture(path: String) -> Texture2D:
	if not path.is_empty():
		if path.begins_with("res://"):
			var texture := load(path) as Texture2D
			if texture != null:
				return texture
		var source_path := ProjectSettings.globalize_path(path) if path.begins_with("user://") or path.begins_with("res://") else path
		var image := Image.load_from_file(source_path)
		if image != null and image.get_width() > 0:
			return ImageTexture.create_from_image(image)
	var image := Image.create(320, 180, false, Image.FORMAT_RGBA8)
	for y in range(image.get_height()):
		var t := float(y) / maxf(1.0, float(image.get_height() - 1))
		var c := HDTheme.BG.lerp(HDTheme.CYAN, 0.18 + t * 0.20)
		for x in range(image.get_width()):
			image.set_pixel(x, y, c)
	return ImageTexture.create_from_image(image)


func _on_back_button_pressed() -> void:
	back_requested.emit()


func _on_progression_button_pressed() -> void:
	open_progression_requested.emit()


func _apply_mobile_scroll_buttons() -> void:
	if not AppState.is_mobile_platform():
		return
	for button in [_back_button, %EMSLoadoutTabButton, %ThemeTabButton, %EffectTabButton, %SpeedModifierTabButton, %ChartModifierTabButton, %ProgressionButton, %BackActionButton]:
		button.set_script(MobileScrollButtonScript)


func _refresh_menu_navigation() -> void:
	if _menu_navigator != null:
		_menu_navigator.refresh_focusables()
