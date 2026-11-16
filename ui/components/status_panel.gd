class_name StatusPanel
extends PanelContainer
## Barre du haut, sur une seule ligne : météo et heure, les cinq ressources vitales (valeur et
## tendance), lecture/pause, vitesse, réglages. Toucher la météo déplie une seconde ligne : sol,
## autres ressources (données, méthane, azote), Système solaire. Toucher une ressource ouvre son
## explication détaillée. Boutons d'au moins 56 × 52 : un doigt les touche sans viser.

signal settings_requested
signal network_requested
signal resource_requested(resource: String)

const SPEED_STEPS: Array[int] = [1, 2, 4]
const VITAL := [ColonyContent.ENERGY, ColonyContent.OXYGEN, ColonyContent.WATER, ColonyContent.FOOD, ColonyContent.MATERIALS]
const EXTRA := [ColonyContent.DATA, ColonyContent.METHANE, ColonyContent.NITROGEN]

var _clock: Label
var _weather_icon: TextureRect
var _play: Button
var _network: Button
var _speed: Button
var _more: Button
var _more_hint: TextureRect
var _time: Label
var _more_row: Control
var _values := {}
var _trends := {}
var _chips := {}
var _last_speed := 1
var expanded := false


func _ready() -> void:
	theme_type_variation = "WindowPanel"

	_weather_icon = UiFx.image(UiFx.icon("sun"), 22, Palette.WARNING)
	_weather_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	_play = _icon_button("pause", func() -> void:
		var engine := GameManager.engine
		engine.set_speed(0 if engine.state.speed > 0 else _last_speed))
	_speed = _icon_button("", func() -> void:
		var engine := GameManager.engine
		var index := SPEED_STEPS.find(maxi(engine.state.speed, 1))
		engine.set_speed(SPEED_STEPS[(index + 1) % SPEED_STEPS.size()]))
	var settings := _icon_button("gear", func() -> void: settings_requested.emit())
	settings.add_theme_color_override("icon_normal_color", Palette.TEXT_MUTED)
	# Météo et heure (toujours visibles) ; le chevron signale la seconde ligne.
	_time = UiFx.label("", "CaptionLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_time.add_theme_font_size_override("font_size", 13)
	_time.add_theme_color_override("font_color", Palette.TEXT)
	_more_hint = UiFx.image(UiFx.icon("chevron_down"), 14, Palette.TEXT_MUTED)
	_more_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var weather_top := UiFx.hbox(1, [_weather_icon, _more_hint])
	weather_top.alignment = BoxContainer.ALIGNMENT_CENTER
	var weather := UiFx.vbox(0, [weather_top, _time])
	weather.alignment = BoxContainer.ALIGNMENT_CENTER
	weather.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_more = _icon_button("", toggle_expanded)
	_more.custom_minimum_size.x = 62
	_more.add_child(weather)
	for child in weather.find_children("*", "Control", true, false):
		(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	weather.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var main_row := UiFx.hbox(3, [_more])
	for r: String in VITAL:
		main_row.add_child(_resource_chip(r))
	for b in [_play, _speed, settings]:
		main_row.add_child(b)

	_clock = UiFx.label("", "SmallLabel")
	_clock.add_theme_color_override("font_color", Palette.TEXT_MUTED)
	_network = _icon_button("planet", func() -> void: network_requested.emit())
	_network.add_theme_color_override("icon_normal_color", Palette.MONEY)
	_clock.custom_minimum_size.x = 90
	_more_row = UiFx.hbox(6, [_clock])
	for r: String in EXTRA:
		var chip := _resource_chip(r)
		chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		chip.custom_minimum_size.x = 96
		_more_row.add_child(chip)
	var spacer := UiFx.spacer()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_more_row.add_child(spacer)
	_more_row.add_child(_network)
	_more_row.visible = false

	add_child(UiFx.vbox(4, [main_row, _more_row]))
	refresh()


func toggle_expanded() -> void:
	expanded = not expanded
	_more_row.visible = expanded
	refresh()


@warning_ignore("integer_division")
func refresh() -> void:
	var engine := GameManager.engine
	var campaign := GameManager.campaign
	_network.visible = campaign != null and (campaign.colonies.size() > 1 or campaign.interplanetary_unlocked())
	var minutes := int(engine.time_of_day() * (24.0 * 60.0 + 39.0))
	_clock.text = Tr.t("Sol %d") % engine.sol_number()
	_time.text = "%02d:%02d" % [minutes / 60, minutes % 60]
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
	var extra_low := false
	for r in ColonyContent.RESOURCES:
		_values[r].text = NumberFormatter.format(engine.state.amount(r))
		var flow: float = flows[r]
		var trend: Label = _trends[r]
		trend.text = "▲" if flow > 0.05 else ("▼" if flow < -0.05 else "")
		trend.add_theme_color_override("font_color", Palette.SUCCESS if flow > 0.0 else Palette.DANGER)
		# Réserve vitale qui s'épuise bientôt : la valeur passe en rouge.
		var low: bool = days.get(r, INF) < ColonyAdvisor.WARNING_SOLS
		_values[r].add_theme_color_override("font_color", Palette.DANGER if low else Palette.TEXT)
		extra_low = extra_low or (low and r in EXTRA and _chips[r].visible)
	# Ligne repliée : le chevron passe en rouge si une des ressources cachées va manquer.
	_more_hint.texture = UiFx.icon("chevron_up" if expanded else "chevron_down")
	_more_hint.modulate = Palette.DANGER if extra_low and not expanded else Palette.TEXT_MUTED


func _icon_button(icon_name: String, action: Callable) -> Button:
	var button := Button.new()
	button.theme_type_variation = "SegmentButton"
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(56, 52)
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
	value.add_theme_font_size_override("font_size", 17)
	var trend := UiFx.label("", "CaptionLabel")
	trend.add_theme_font_size_override("font_size", 10)
	_values[resource] = value
	_trends[resource] = trend
	var content := UiFx.hbox(2, [UiFx.image(UiFx.icon(resource), 18, Palette.resource_color(resource)), value, trend])
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var chip := Button.new()
	chip.theme_type_variation = "SegmentButton"
	chip.custom_minimum_size = Vector2(0, 52)
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chip.focus_mode = Control.FOCUS_NONE
	chip.add_child(content)
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	chip.pressed.connect(func() -> void:
		AudioManager.play("click")
		resource_requested.emit(resource))
	_chips[resource] = chip
	return chip
