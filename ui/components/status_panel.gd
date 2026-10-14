class_name StatusPanel
extends PanelContainer
## Bandeau du haut : sol et heure, météo, vitesse du temps, réglages, puis les six ressources
## avec leur réserve et leur bilan par sol. Toucher une ressource l'explique.

signal settings_requested
signal resource_requested(resource: String)

var _clock: Label
var _weather_icon: TextureRect
var _weather: Label
var _speed_buttons := {}
var _values := {}
var _flows := {}
var _chips := {}


func _ready() -> void:
	theme_type_variation = "WindowPanel"

	_weather_icon = UiFx.image(UiFx.icon("sun"), 30, Palette.WARNING)
	_clock = UiFx.label("", "HeadingLabel")
	_weather = UiFx.label("", "SmallLabel")
	var clock_box := UiFx.vbox(0, [_clock, _weather])
	clock_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var speeds := UiFx.hbox(2)
	var group := ButtonGroup.new()
	for speed in ColonyEngine.SPEEDS:
		var button := Button.new()
		button.theme_type_variation = "SegmentButton"
		button.toggle_mode = true
		button.button_group = group
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(62, 52)
		button.icon = UiFx.icon("pause" if speed == 0 else ("play" if speed == 1 else "fast"))
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 22)
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if speed > 2:
			button.text = "×4"
			button.icon = null
		button.pressed.connect(func() -> void:
			AudioManager.play("click")
			GameManager.engine.set_speed(speed))
		speeds.add_child(button)
		_speed_buttons[speed] = button

	var settings := Button.new()
	settings.icon = UiFx.icon("gear")
	settings.expand_icon = true
	settings.custom_minimum_size = Vector2(52, 52)
	settings.add_theme_constant_override("icon_max_width", 26)
	settings.add_theme_color_override("icon_normal_color", Palette.TEXT_MUTED)
	settings.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	settings.focus_mode = Control.FOCUS_NONE
	settings.pressed.connect(func() -> void:
		AudioManager.play("click")
		settings_requested.emit())

	var resources := UiFx.hbox(6)
	for r in ColonyContent.RESOURCES:
		resources.add_child(_resource_chip(r))

	add_child(UiFx.vbox(10, [
		UiFx.hbox(10, [_weather_icon, clock_box, speeds, settings]),
		resources,
	]))
	refresh()


@warning_ignore("integer_division")
func refresh() -> void:
	var engine := GameManager.engine
	var minutes := int(engine.time_of_day() * (24.0 * 60.0 + 39.0))
	_clock.text = "Sol %d · %02d:%02d" % [engine.sol_number(), minutes / 60, minutes % 60]
	if engine.is_storm():
		_weather_icon.texture = UiFx.icon("storm")
		_weather.text = "Tempête de poussière"
		_weather_icon.modulate = Palette.WARNING
	elif engine.is_night():
		_weather_icon.texture = UiFx.icon("moon")
		_weather.text = "Nuit · panneaux solaires à l'arrêt"
		_weather_icon.modulate = Color("#b8c8ff")
	else:
		_weather_icon.texture = UiFx.icon("sun")
		_weather.text = "Jour · ciel dégagé"
		_weather_icon.modulate = Palette.WARNING
	_speed_buttons[engine.state.speed].set_pressed_no_signal(true)

	var flows := engine.average_flows()
	for r in ColonyContent.RESOURCES:
		var amount := engine.state.amount(r)
		_values[r].text = NumberFormatter.format(amount)
		var flow: float = flows[r]
		var label: Label = _flows[r]
		label.text = ("+" if flow >= 0.0 else "") + NumberFormatter.format(flow) + "/sol"
		label.add_theme_color_override("font_color", Palette.SUCCESS if flow >= 0.0 else Palette.DANGER)
		# Réserve vitale de moins d'un sol : la pastille clignote en rouge.
		var low: bool = r in ColonyContent.VITAL and flow < 0.0 and amount < -flow
		var chip: Control = _chips[r]
		chip.modulate = Color(1, 0.55, 0.55) if low and Time.get_ticks_msec() % 1000 < 500 else Color.WHITE


func _resource_chip(resource: String) -> Control:
	var value := UiFx.label("", "NumberLabel")
	value.add_theme_font_size_override("font_size", 19)
	var flow := UiFx.label("", "CaptionLabel")
	flow.add_theme_font_size_override("font_size", 13)
	_values[resource] = value
	_flows[resource] = flow
	var content := UiFx.hbox(5, [UiFx.image(UiFx.icon(resource), 22, Palette.resource_color(resource)),
			UiFx.vbox(-2, [value, flow])])
	var chip := Button.new()
	chip.theme_type_variation = "SegmentButton"
	chip.custom_minimum_size = Vector2(0, 54)
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chip.focus_mode = Control.FOCUS_NONE
	chip.add_child(content)
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 8
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	chip.pressed.connect(func() -> void:
		AudioManager.play("click")
		resource_requested.emit(resource))
	_chips[resource] = chip
	return chip
