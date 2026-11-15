class_name SolarView
extends Control
## Le réseau de colonies dans le Système solaire, en 3D : chaque colonie est une étiquette à toucher
## sur son monde ; les fusées en vol suivent leur trajet ; les routes depuis la colonie affichée sont
## vertes quand la fenêtre de tir est ouverte. Un doigt fait tourner la vue, deux doigts zooment.

signal closed
signal colony_chosen(index: int)
signal cargo_requested
signal founding_requested
signal list_requested
## Fonder une colonie dans cette région, depuis la colonie affichée.
signal found_at(region: String)

## Marges des bords de l'écran (encoche, barre de navigation), en pixels.
var inset_top := 12
var inset_bottom := 12
var _campaign: Campaign
var _system: SolarSystem
var _viewport: SubViewport
var _overlay: Control
## Étiquettes : une par colonie (bouton) et une par monde (nom, bouton discret).
var _colony_tags: Array[Button] = []
var _body_tags := {}
var _flight_tags: Array[Label] = []
## Colonies des lunes regroupées sous leur planète, en vue d'ensemble (planète -> bouton).
var _group_tags := {}
var _selected := -1
var _selected_body := ""
var _sheet_box: VBoxContainer
var _clock: Label
var _touches := {}
var _pinch := 0.0
var _press := Vector2.ZERO
var _dragged := false
## Fond opaque des étiquettes de colonies (lisibles devant une planète ou des anneaux clairs).
var _tag_style: StyleBoxFlat


func _init(campaign: Campaign) -> void:
	_campaign = campaign
	_tag_style = StyleBoxFlat.new()
	_tag_style.bg_color = Color(0.02, 0.07, 0.12, 0.94)
	_tag_style.border_color = Palette.BORDER
	_tag_style.set_border_width_all(2)
	_tag_style.set_corner_radius_all(16)
	_tag_style.set_content_margin_all(12)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var container := SubViewportContainer.new()
	container.stretch = true
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_DISABLED if OS.has_feature("mobile") else Viewport.MSAA_2X
	if OS.has_feature("mobile"):
		_viewport.scaling_3d_scale = 0.7
	container.add_child(_viewport)
	_system = SolarSystem.new()
	_viewport.add_child(_system)

	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)
	for id: String in SolarSystem.BODIES:
		var tag := Button.new()
		tag.text = Tr.t(SolarSystem.BODIES[id].name)
		tag.flat = true
		tag.focus_mode = Control.FOCUS_NONE
		tag.theme_type_variation = "CaptionLabel"
		tag.add_theme_color_override("font_color", Palette.TEXT_MUTED)
		tag.add_theme_color_override("font_outline_color", Palette.OUTLINE)
		tag.add_theme_constant_override("outline_size", 6)
		tag.add_theme_font_size_override("font_size", 22)
		tag.pressed.connect(_on_body_tapped.bind(id))
		_overlay.add_child(tag)
		_body_tags[id] = tag
	_add_colony_tags()

	_build_header()
	_build_sheet()
	_select(_campaign.active)
	_system.focus_on("")
	_update_scene(1.0)


## Une étiquette par colonie (une colonie peut être fondée pendant que la vue est ouverte).
func _add_colony_tags() -> void:
	for i in range(_colony_tags.size(), _campaign.colonies.size()):
		var tag := Button.new()
		tag.text = _campaign.colony_name(i)
		tag.focus_mode = Control.FOCUS_NONE
		tag.custom_minimum_size = Vector2(0, 52)
		tag.add_theme_font_size_override("font_size", 22)
		# Fond opaque : l'étiquette reste lisible devant une planète ou des anneaux clairs.
		var style := _tag_style
		for state in ["normal", "hover", "pressed"]:
			tag.add_theme_stylebox_override(state, style)
		tag.pressed.connect(_select.bind(i))
		_overlay.add_child(tag)
		_colony_tags.append(tag)


func _process(delta: float) -> void:
	if _colony_tags.size() != _campaign.colonies.size():
		_add_colony_tags()
	_update_scene(delta)


func _update_scene(delta: float) -> void:
	_system.update(_campaign.time, delta)
	var routes := []
	var origin := _campaign.planet_of(_campaign.active)
	var linked := {}
	for i in _campaign.colonies.size():
		var world := _campaign.planet_of(i)
		if world != origin and not linked.has(world):
			linked[world] = true
			routes.append({ "from": origin, "to": world, "open": _campaign.window_open(origin, world) })
	var flights := []
	for shipment: Dictionary in _campaign.shipments:
		var to: String = _campaign.planet_of(shipment.to) if shipment.to >= 0 else Campaign.planet_of_region(shipment.region)
		var span: float = maxf(0.01, shipment.arrive - shipment.depart)
		flights.append({ "from": _campaign.planet_of(shipment.from), "to": to, "kind": shipment.kind,
				"progress": clampf((_campaign.time - shipment.depart) / span, 0.0, 1.0) })
	_system.draw_traffic(routes, flights)
	_clock.text = Tr.t("Sol %d de la campagne") % (int(_campaign.time) + 1)
	_place_tags(flights)


## Étiquettes : nom de chaque monde sous lui, colonies au-dessus, sans se chevaucher.
func _place_tags(flights: Array) -> void:
	var taken: Array[Rect2] = []
	var stacks := {}
	# Lunes trop près de leur planète à l'écran (vue d'ensemble) : leurs colonies sont regroupées
	# sous une seule étiquette, qui zoome sur la planète.
	var crowded := {}
	for id: String in SolarSystem.BODIES:
		var parent: String = SolarSystem.BODIES[id].get("parent", "")
		if parent.is_empty():
			continue
		var spot: Variant = _system.screen_position(_system.body_position(id))
		var center: Variant = _system.screen_position(_system.body_position(parent))
		if spot != null and center != null and (spot as Vector2).distance_to(center) < _system.screen_radius(parent) + 40.0:
			crowded[id] = parent
	var groups := {}
	for i in _colony_tags.size():
		var world := _campaign.planet_of(i)
		if crowded.has(world):
			groups[crowded[world]] = groups.get(crowded[world], 0) + 1
	# Une seule colonie autour d'une planète : son étiquette suffit.
	for world: String in crowded.keys():
		if groups.get(crowded[world], 0) < 2:
			crowded.erase(world)
	for parent: String in _group_tags:
		_group_tags[parent].visible = false
	for parent: String in groups:
		if groups[parent] < 2:
			continue
		var group := _group_tag(parent)
		var spot: Variant = _system.screen_position(_system.body_position(parent))
		if spot == null:
			continue
		group.visible = true
		group.text = Tr.t("%s · %d colonies") % [Tr.t(SolarSystem.BODIES[parent].name), groups[parent]]
		group.size = group.get_combined_minimum_size()
		var lift := maxf(_system.screen_radius(parent), 6.0) + 14.0
		var rect := _free_spot(Rect2((spot as Vector2) - Vector2(group.size.x * 0.5, lift + group.size.y), group.size), taken, -1.0)
		taken.append(rect)
		group.position = rect.position
	for i in _colony_tags.size():
		var tag := _colony_tags[i]
		var world := _campaign.planet_of(i)
		var spot: Variant = _system.screen_position(_system.body_position(world))
		tag.visible = spot != null and not crowded.has(world)
		if not tag.visible:
			continue
		tag.size = tag.get_combined_minimum_size()
		var level: int = stacks.get(world, 0)
		stacks[world] = level + 1
		var lift := maxf(_system.screen_radius(world), 6.0) + 14.0 + level * (tag.size.y + 6.0)
		var rect := Rect2((spot as Vector2) - Vector2(tag.size.x * 0.5, lift + tag.size.y), tag.size)
		rect = _free_spot(rect, taken, -1.0)
		taken.append(rect)
		tag.position = rect.position
		var selected := i == _selected
		var here := i == _campaign.active
		if selected != (tag.theme_type_variation == "GreenButton"):
			tag.theme_type_variation = "GreenButton" if selected else ""
			for state in ["normal", "hover", "pressed"]:
				if selected:
					tag.remove_theme_stylebox_override(state)
				else:
					tag.add_theme_stylebox_override(state, _tag_style)
		tag.icon = UiFx.icon("target") if here else null
		tag.expand_icon = false
		tag.add_theme_constant_override("icon_max_width", 22)
	for id: String in _body_tags:
		var tag: Button = _body_tags[id]
		var spot: Variant = _system.screen_position(_system.body_position(id))
		var parent: String = SolarSystem.BODIES[id].get("parent", "")
		# Une lune trop près de sa planète à l'écran : son nom attendra qu'on s'approche.
		var near_parent := false
		if spot != null and not parent.is_empty():
			var center: Variant = _system.screen_position(_system.body_position(parent))
			near_parent = center != null and (spot as Vector2).distance_to(center) < _system.screen_radius(parent) + 40.0
		tag.visible = spot != null and not near_parent
		if not tag.visible:
			continue
		tag.size = tag.get_combined_minimum_size()
		var drop := maxf(_system.screen_radius(id), 4.0) + 2.0
		var rect := Rect2((spot as Vector2) + Vector2(-tag.size.x * 0.5, drop), tag.size)
		var overlaps := false
		for other in taken:
			if other.intersects(rect):
				overlaps = true
		tag.visible = not overlaps
		if tag.visible:
			taken.append(rect)
			tag.position = rect.position
		tag.add_theme_color_override("font_color", Palette.TEXT if id == _selected_body else Palette.TEXT_MUTED)
	while _flight_tags.size() < flights.size():
		var label := UiFx.label("", "CaptionLabel")
		label.add_theme_font_size_override("font_size", 20)
		label.add_theme_color_override("font_outline_color", Palette.OUTLINE)
		label.add_theme_constant_override("outline_size", 6)
		_overlay.add_child(label)
		_flight_tags.append(label)
	for k in _flight_tags.size():
		var label := _flight_tags[k]
		label.visible = false
		if k >= flights.size():
			continue
		var flight: Dictionary = flights[k]
		var spot: Variant = _system.screen_position(_system.flight_position(flight))
		if spot == null:
			continue
		var shipment: Dictionary = _campaign.shipments[k]
		var left := maxf(0.0, shipment.arrive - _campaign.time)
		label.text = Tr.t("%s sol%s") % [NumberFormatter.format(ceilf(left)), "s" if left > 1.0 else ""]
		label.add_theme_color_override("font_color", Palette.MONEY if flight.kind == "colony" else Palette.ACCENT)
		label.size = label.get_combined_minimum_size()
		var rect := Rect2((spot as Vector2) + Vector2(10.0, -label.size.y * 0.5), label.size)
		var overlaps := false
		for other in taken:
			if other.intersects(rect):
				overlaps = true
		if not overlaps:
			label.visible = true
			label.position = rect.position
			taken.append(rect)


func _group_tag(parent: String) -> Button:
	if not _group_tags.has(parent):
		var tag := Button.new()
		tag.focus_mode = Control.FOCUS_NONE
		tag.custom_minimum_size = Vector2(0, 52)
		tag.add_theme_font_size_override("font_size", 22)
		for state in ["normal", "hover", "pressed"]:
			tag.add_theme_stylebox_override(state, _tag_style)
		tag.pressed.connect(_on_body_tapped.bind(parent))
		_overlay.add_child(tag)
		_group_tags[parent] = tag
	return _group_tags[parent]


## Décale un rectangle (vers le haut si `direction` vaut −1) jusqu'à une place libre.
func _free_spot(rect: Rect2, taken: Array[Rect2], direction: float) -> Rect2:
	for attempt in 12:
		var clash := false
		for other in taken:
			if other.grow(3.0).intersects(rect):
				clash = true
				rect.position.y = (other.position.y - rect.size.y - 4.0) if direction < 0.0 else other.end.y + 4.0
		if not clash:
			break
	return rect


# ---------- Panneaux ----------

func _build_header() -> void:
	var title := UiFx.label(Tr.t("Système solaire"), "HeadingLabel")
	_clock = UiFx.label("", "SmallLabel")
	var hint := UiFx.label(Tr.t("Tailles et distances pas à l'échelle"), "CaptionLabel")
	hint.add_theme_color_override("font_color", Palette.TEXT_DIM)
	var text := UiFx.vbox(0, [title, _clock, hint])
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var overview := Button.new()
	overview.icon = UiFx.icon("sun")
	overview.custom_minimum_size = Vector2(64, 64)
	overview.focus_mode = Control.FOCUS_NONE
	overview.pressed.connect(func() -> void:
		AudioManager.play("click")
		_selected_body = ""
		_system.focus_on(""))
	var close := Button.new()
	close.icon = UiFx.icon("close")
	close.custom_minimum_size = Vector2(64, 64)
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func() -> void:
		AudioManager.play("click")
		closed.emit())
	var header := UiFx.panel("WindowPanel", UiFx.hbox(8, [text, overview, close]))
	header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	header.offset_left = 12
	header.offset_right = -12
	header.offset_top = inset_top
	add_child(header)


func _build_sheet() -> void:
	_sheet_box = UiFx.vbox(8)
	var sheet := UiFx.panel("WindowPanel", _sheet_box)
	sheet.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	sheet.grow_vertical = Control.GROW_DIRECTION_BEGIN
	sheet.offset_left = 12
	sheet.offset_right = -12
	sheet.offset_bottom = -inset_bottom
	add_child(sheet)


## Fiche de la colonie choisie, et actions de l'astroport.
func _select(index: int) -> void:
	if index != _selected:
		AudioManager.play("click")
	_selected = index
	_selected_body = _campaign.planet_of(index)
	_system.focus_on(_selected_body)
	_fill_sheet()


func _on_body_tapped(id: String) -> void:
	AudioManager.play("click")
	for i in _campaign.colonies.size():
		if _campaign.planet_of(i) == id:
			_select(i)
			return
	_selected = -1
	_selected_body = id
	_system.focus_on(id)
	_fill_sheet()


func _fill_sheet() -> void:
	for child in _sheet_box.get_children():
		child.queue_free()
	if _selected >= 0:
		_colony_card(_selected)
	else:
		var name := UiFx.label(Tr.t(SolarSystem.BODIES[_selected_body].name), "HeadingLabel")
		var text := Tr.t("Aucune colonie ici pour l'instant.")
		if _selected_body == "earth":
			text = Tr.t("La Terre : d'où partent les volontaires et les ravitaillements.")
		elif _selected_body in ["jupiter", "saturn"]:
			text = Tr.t("Une planète géante, sans sol où se poser : les colonies vivent sur ses lunes.")
		var regions := _founding_regions(_selected_body)
		if not regions.is_empty():
			text = Tr.t("Aucune colonie ici pour l'instant : un vaisseau de fondation peut s'y poser.")
		_sheet_box.add_child(UiFx.vbox(2, [name, UiFx.paragraph(text, "SmallLabel")]))
		for region in regions:
			_founding_row(region)
	var cargo := _action(Tr.t("Cargaison"), "rocket", "")
	cargo.disabled = _campaign.colonies.size() < 2
	cargo.pressed.connect(func() -> void: cargo_requested.emit())
	var found := _action(Tr.t("Fonder"), "planet", "GoldButton")
	found.pressed.connect(func() -> void: founding_requested.emit())
	var list := _action(Tr.t("Liste"), "news", "")
	list.pressed.connect(func() -> void: list_requested.emit())
	_sheet_box.add_child(UiFx.hbox(8, [cargo, found, list]))


## Sites d'atterrissage d'un monde (fondation possible un jour depuis la colonie affichée).
func _founding_regions(world: String) -> Array[String]:
	var list: Array[String] = []
	for id: String in ColonyContent.FOUNDING_REGIONS:
		if Campaign.planet_of_region(id) == world:
			list.append(id)
	return list


## Un site où se poser : coût et durée du vol depuis la colonie affichée, ou ce qui manque.
func _founding_row(region: String) -> void:
	var origin := _campaign.active
	var cost := _campaign.founding_cost(origin, region)
	var transit := _campaign.transit_sols(origin, region)
	var title := UiFx.label(Tr.t(ColonyContent.REGIONS[region].name), "BodyLabel")
	var trip := UiFx.paragraph(Tr.t("%s matériaux · %s kg de méthane · %s sol%s de voyage") % [
			NumberFormatter.format(cost[ColonyContent.MATERIALS]), NumberFormatter.format(cost[ColonyContent.METHANE]),
			NumberFormatter.format(transit), "s" if transit >= 2.0 else ""], "SmallLabel")
	trip.add_theme_color_override("font_color", Palette.ACCENT)
	var text := UiFx.vbox(2, [title, trip])
	var problem := _campaign.founding_problem(origin, region)
	if not problem.is_empty():
		var reason := UiFx.paragraph(problem, "SmallLabel")
		reason.add_theme_color_override("font_color", Palette.WARNING)
		text.add_child(reason)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var go := Button.new()
	go.text = Tr.t("Se poser ici")
	go.theme_type_variation = "GoldButton"
	go.custom_minimum_size = Vector2(150, 60)
	go.focus_mode = Control.FOCUS_NONE
	go.disabled = not problem.is_empty()
	go.pressed.connect(func() -> void:
		found_at.emit(region)
		_fill_sheet.call_deferred())
	_sheet_box.add_child(UiFx.panel("Row", UiFx.hbox(8, [text, go])))


func _colony_card(i: int) -> void:
	var state := _campaign.colonies[i]
	var world := _campaign.planet_of(i)
	var name := UiFx.label(_campaign.colony_name(i), "HeadingLabel")
	name.clip_text = true
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var info := UiFx.label(Tr.t("%s · Sol %d · %d colons · ère %d") % [Tr.t(ColonyContent.PLANETS[world].name),
			int(state.sol) + 1, state.colonists.size(), state.era], "SmallLabel")
	var status := UiFx.paragraph("", "SmallLabel")
	var alerts := ColonyAdvisor.alerts(_campaign.engines[i])
	if _campaign.standby.has(i):
		status.text = Tr.t("En veille : la réserve %s est trop basse.") % Tr.t(ColonyContent.RESOURCE_PARTITIVE[_campaign.standby[i]])
		status.add_theme_color_override("font_color", Palette.WARNING)
	elif not alerts.is_empty():
		status.text = alerts[0].title
		status.add_theme_color_override("font_color", Palette.DANGER if alerts[0].level == "danger" else Palette.WARNING)
	else:
		status.text = Tr.t("Tout va bien.")
		status.add_theme_color_override("font_color", Palette.SUCCESS)
	var text := UiFx.vbox(2, [name, info, status])
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := UiFx.hbox(8, [text])
	if i == _campaign.active:
		var here := UiFx.label(Tr.t("Ici"), "CaptionLabel")
		here.add_theme_color_override("font_color", Palette.ACCENT)
		row.add_child(here)
	else:
		var go := Button.new()
		go.text = Tr.t("Y aller")
		go.theme_type_variation = "GreenButton"
		go.custom_minimum_size = Vector2(120, 60)
		go.focus_mode = Control.FOCUS_NONE
		go.pressed.connect(func() -> void: colony_chosen.emit(i))
		row.add_child(go)
	_sheet_box.add_child(row)
	var origin := _campaign.planet_of(_campaign.active)
	if i != _campaign.active and world != origin:
		var r := Campaign.route(origin, world)
		var trip := UiFx.paragraph("", "SmallLabel")
		if _campaign.window_open(origin, world):
			trip.text = Tr.t("Depuis ici : %s sols de vol · fenêtre de tir ouverte, encore %s sols.") % [
					NumberFormatter.format(r.transit), NumberFormatter.format(_campaign.window_wait(origin, world, true))]
			trip.add_theme_color_override("font_color", Palette.SUCCESS)
		else:
			trip.text = Tr.t("Depuis ici : %s sols de vol · prochaine fenêtre de tir dans %s sols.") % [
					NumberFormatter.format(r.transit), NumberFormatter.format(_campaign.window_wait(origin, world))]
			trip.add_theme_color_override("font_color", Palette.TEXT_MUTED)
		_sheet_box.add_child(trip)


func _action(text: String, icon_name: String, variation: String) -> Button:
	var button := Button.new()
	button.text = text
	button.icon = UiFx.icon(icon_name)
	button.add_theme_constant_override("icon_max_width", 26)
	button.theme_type_variation = variation
	button.custom_minimum_size = Vector2(0, 60)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE
	return button


# ---------- Gestes ----------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
		else:
			_touches.erase(event.index)
		_pinch = _spread()
	elif event is InputEventScreenDrag and _touches.size() >= 2:
		_touches[event.index] = event.position
		var spread := _spread()
		if _pinch > 0.0 and spread > 0.0:
			_system.zoom(_pinch / spread)
		_pinch = spread
		_dragged = true
	elif event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_system.zoom(0.9)
			MOUSE_BUTTON_WHEEL_DOWN:
				_system.zoom(1.1)
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					_press = event.position
					_dragged = false
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		if _touches.size() >= 2:
			return
		if not _dragged and event.position.distance_to(_press) < UiFx.TAP_SLOP:
			return
		_dragged = true
		_system.orbit(event.relative)
	elif event is InputEventMagnifyGesture:
		_system.zoom(1.0 / event.factor)


func _spread() -> float:
	if _touches.size() < 2:
		return 0.0
	var points: Array = _touches.values()
	return (points[0] as Vector2).distance_to(points[1])
