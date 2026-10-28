class_name StatusPanel
extends PanelContainer
## Barre du haut, compacte : heure et météo, lecture/pause, vitesse, réglages, puis les six
## ressources (valeur et tendance). Toucher une ressource ouvre son explication détaillée.

signal settings_requested
signal network_requested
signal resource_requested(resource: String)

const SPEED_STEPS: Array[int] = [1, 2, 4]

var _clock: Label
var _weather_icon: TextureRect
var _play: Button
var _network: Button
var _speed: Button
var _values := {}
var _trends := {}
var _chips := {}
var _last_speed := 1


func _ready() -> void:
	theme_type_variation = "WindowPanel"

	_weather_icon = UiFx.image(UiFx.icon("sun"), 26, Palette.WARNING)
	_clock = UiFx.label("", "HeadingLabel")
	_clock.add_theme_font_size_override("font_size", 21)
	_clock.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_play = _icon_button("pause", func() -> void:
		var engine := GameManager.engine
		engine.set_speed(0 if engine.state.speed > 0 else _last_speed))
	_speed = _icon_button("", func() -> void:
		var engine := GameManager.engine
		var index := SPEED_STEPS.find(maxi(engine.state.speed, 1))
		engine.set_speed(SPEED_STEPS[(index + 1) % SPEED_STEPS.size()]))
	_speed.custom_minimum_size.x = 64
	_network = _icon_button("planet", func() -> void: network_requested.emit())
	_network.add_theme_color_override("icon_normal_color", Palette.MONEY)
	var settings := _icon_button("gear", func() -> void: settings_requested.emit())
	settings.add_theme_color_override("icon_normal_color", Palette.TEXT_MUTED)

	var resources := UiFx.hbox(4)
	for r in ColonyContent.RESOURCES:
		resources.add_child(_resource_chip(r))

	add_child(UiFx.vbox(6, [UiFx.hbox(8, [_weather_icon, _clock, _network, _play, _speed, settings]), resources]))
	refresh()


@warning_ignore("integer_division")
func refresh() -> void:
	var engine := GameManager.engine
	var campaign := GameManager.campaign
	_network.visible = campaign != null and (campaign.colonies.size() > 1 or campaign.interplanetary_unlocked())
	var minutes := int(engine.time_of_day() * (24.0 * 60.0 + 39.0))
	_clock.text = Tr.t("Sol %d · %02d:%02d") % [engine.sol_number(), minutes / 60, minutes % 60]
	if engine.is_flare():
		_weather_icon.texture = UiFx.icon("warning")
		_weather_icon.modulate = Palette.DANGER
	elif engine.is_storm():
		_weather_icon.texture = UiFx.icon("storm")
		_weather_icon.modulate = Palette.WARNING
	elif engine.is_night():
		_weather_icon.texture = UiFx.icon("moon")
		_weather_icon.modulate = Color("#b8c8ff")
	else:
		_weather_icon.texture = UiFx.icon("sun")
		_weather_icon.modulate = Palette.WARNING
	if engine.state.speed > 0:
		_last_speed = engine.state.speed
	_play.icon = UiFx.icon("pause" if engine.state.speed > 0 else "play")
	_speed.text = Tr.t("×%d") % _last_speed

	var flows := engine.average_flows(true)
	var days := ColonyAdvisor.forecast(engine)
	_chips[ColonyContent.METHANE].visible = engine.state.era >= 2 or engine.planet_id() != "mars" \
			or engine.state.amount(ColonyContent.METHANE) > 0.0 or engine.capacity(ColonyContent.METHANE) > 0.0
	_chips[ColonyContent.NITROGEN].visible = engine.state.amount(ColonyContent.NITROGEN) > 0.0 \
			or engine.capacity(ColonyContent.NITROGEN) > 0.0
	for r in ColonyContent.RESOURCES:
		_values[r].text = NumberFormatter.format(engine.state.amount(r))
		var flow: float = flows[r]
		var trend: Label = _trends[r]
		trend.text = "▲" if flow > 0.05 else ("▼" if flow < -0.05 else "")
		trend.add_theme_color_override("font_color", Palette.SUCCESS if flow > 0.0 else Palette.DANGER)
		# Réserve vitale qui s'épuise bientôt : la valeur passe en rouge.
		var low: bool = days.get(r, INF) < ColonyAdvisor.WARNING_SOLS
		_values[r].add_theme_color_override("font_color", Palette.DANGER if low else Palette.TEXT)


func _icon_button(icon_name: String, action: Callable) -> Button:
	var button := Button.new()
	button.theme_type_variation = "SegmentButton"
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(50, 46)
	if not icon_name.is_empty():
		button.icon = UiFx.icon(icon_name)
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 22)
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.pressed.connect(func() -> void:
		AudioManager.play("click")
		action.call())
	return button


func _resource_chip(resource: String) -> Control:
	var value := UiFx.label("", "NumberLabel")
	value.add_theme_font_size_override("font_size", 18)
	var trend := UiFx.label("", "CaptionLabel")
	trend.add_theme_font_size_override("font_size", 11)
	_values[resource] = value
	_trends[resource] = trend
	var content := UiFx.hbox(3, [UiFx.image(UiFx.icon(resource), 20, Palette.resource_color(resource)), value, trend])
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	var chip := Button.new()
	chip.theme_type_variation = "SegmentButton"
	chip.custom_minimum_size = Vector2(0, 40)
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chip.focus_mode = Control.FOCUS_NONE
	chip.add_child(content)
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	chip.pressed.connect(func() -> void:
		AudioManager.play("click")
		resource_requested.emit(resource))
	_chips[resource] = chip
	return chip
