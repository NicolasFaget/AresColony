extends Control
## Écran principal : le cratère en 3D, le bandeau des ressources en haut, le panneau à onglets
## et les actualités en bas, le mode placement, les fenêtres d'information.
## Il affiche ce que ColonyEngine expose et ne calcule rien lui-même.

const MARGIN := 10
const WINDOW_SHARE := 0.5
const TAP_SLOP := 12.0
const SYNERGY_COLOR := Color("#ffc94a")
## Un message d'ambiance tous les ~1,5 sol de jeu.
const CHATTER_EVERY := 1.5

var _engine: ColonyEngine
var _world: ColonyWorld
## Vue du Système solaire, quand elle est ouverte.
var _solar: SolarView
var _status: StatusPanel
var _alert: AlertBanner
var _coach: CoachCard
var _window: GameWindow
var _news: NewsTicker
var _message_slot: Control
var _safe_area: MarginContainer
var _pages: Array[Page] = []
var _research_page: ResearchPage
var _modal_layer: Control
## Fenêtre d'évacuation ouverte (plusieurs évacuations d'un coup : une seule fenêtre).
var _evacuation_modal: Modal
var _current_page := 0

# Mode placement.
var _placement_bar: PanelContainer
var _placement_title: Label
var _placement_reason: Label
var _placement_synergy: Label
## Fiches débloquées en attente de leur écran de découverte (une à la fois).
var _discoveries: Array[String] = []
var _discovery: DiscoveryScreen
var _placement_confirm: Button
var _placing := ""

# Gestes sur le monde.
var _touches := {}
var _press_position := Vector2.ZERO
var _dragged := false
var _pinch_distance := 0.0
var _next_chatter := 2.0
## Mode photo : interface masquée, barre réduite en bas.
var _photo_bar: Control


func _ready() -> void:
	# Lancée directement (éditeur, outils) : on reprend la dernière partie.
	if GameManager.engine == null:
		var slot := GameManager.most_recent_slot()
		GameManager.start_game(slot if not slot.is_empty() else GameManager.SLOTS[0])
	_engine = GameManager.engine
	theme = AppTheme.build()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	add_child(IconStudio.new())
	_world = ColonyWorld.new()
	add_child(_world)
	# Mobile : la 3D est calculée en plus basse résolution puis agrandie (l'interface reste nette).
	_world.apply_quality(GameManager.quality_level())
	_world.cell_tapped.connect(_on_cell_tapped)
	_world.colonist_tapped.connect(_show_colonist)
	_world.ghost_moved.connect(func(_c: Vector2i) -> void: _refresh_placement())
	_build_layout()
	_connect_engine()
	AudioManager.set_world(_engine.planet_id())

	GameManager.state_changed.connect(_refresh)
	GameManager.offline_report.connect(_show_offline_report)
	GameManager.campaign.completed.connect(_show_finale)
	get_viewport().size_changed.connect(_layout_changed)
	_layout_changed()
	_refresh()
	_next_chatter = _engine.state.sol + CHATTER_EVERY

	await get_tree().process_frame
	_show_load_problem()
	var report := GameManager.take_startup_report()
	if not report.is_empty():
		_show_offline_report(report)
	elif _engine.state.sol < 0.35:
		_show_welcome()
	if GameManager.campaign.is_complete() and not GameManager.campaign.finale_shown:
		_show_finale()


func _build_layout() -> void:
	var world_input := Control.new()
	world_input.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	world_input.mouse_filter = Control.MOUSE_FILTER_STOP
	world_input.gui_input.connect(_on_world_input)
	add_child(world_input)

	_safe_area = MarginContainer.new()
	_safe_area.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_safe_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_safe_area)
	var root := UiFx.vbox(6)
	_safe_area.add_child(root)

	_status = StatusPanel.new()
	_status.settings_requested.connect(_show_settings)
	_status.network_requested.connect(_show_network)
	_status.resource_requested.connect(_show_resource)
	root.add_child(_status)
	# Une seule ligne de messages sous la barre : l'alerte, ou une nouvelle pendant quelques secondes.
	_message_slot = Control.new()
	_message_slot.custom_minimum_size.y = 44
	_message_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_message_slot)
	_alert = AlertBanner.new()
	_alert.action_requested.connect(func(tab: int, target: String) -> void:
		if not _alert.advice().is_empty():
			# Demandé par le joueur : le conseil passe tout de suite, même devant une alerte rouge.
			_news.post_now(_alert.advice())
		_go_to(tab, target))
	_message_slot.add_child(_alert)
	_alert.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_news = NewsTicker.new()
	_news.showing_changed.connect(func(on: bool) -> void:
		_alert.set_muted(on)
		_update_message_slot())
	_message_slot.add_child(_news)
	_news.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Colonie retrouvée en veille (voir Campaign.switch_to) : le joueur doit savoir que le temps est arrêté.
	if _engine.state.speed == 0 and not _engine.vital_low().is_empty():
		_news.post(Tr.t("Colonie en veille : le temps est en pause. Construisez ce qui manque, puis relancez-le."))
	var spacer := UiFx.spacer()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(spacer)
	_coach = CoachCard.new()
	_coach.show_requested.connect(_go_to)
	_coach.skip_requested.connect(func() -> void:
		if _engine.state.era == 1 and _engine.planet_id() == "mars":
			_engine.state.tutorial_done = true
		elif not _engine.state.guides_skipped.has(_engine.state.era):
			_engine.state.guides_skipped.append(_engine.state.era)
		_news.post(Tr.t("Guide masqué. Les alertes restent là pour vous prévenir."))
		_refresh())
	root.add_child(_coach)

	root.add_child(_build_placement_bar())

	_window = GameWindow.new()
	_window.tab_selected.connect(_show_page)
	_window.collapsed_changed.connect(func(_c: bool) -> void: _layout_changed.call_deferred())
	root.add_child(_window)

	var build := BuildPage.new()
	build.place_requested.connect(_start_placement)
	build.info_requested.connect(_show_build_info)
	build.synergies_requested.connect(_show_synergies)
	var colony := ColonyPage.new()
	colony.maintenance_requested.connect(_show_maintenance)
	colony.expeditions_requested.connect(_show_expeditions)
	_research_page = ResearchPage.new()
	var knowledge := KnowledgePage.new()
	knowledge.open_card.connect(_show_card)
	var stack := Control.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.clip_contents = true
	_window.body.add_child(stack)
	for page: Page in [build, colony, _research_page, knowledge]:
		_pages.append(page)
		stack.add_child(page)
		page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		page.visible = false
	_pages[0].visible = true


	var fx := Control.new()
	fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fx)
	UiFx.fx_layer = fx

	_modal_layer = Control.new()
	_modal_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_modal_layer)
	move_child(fx, -1)


func _build_placement_bar() -> Control:
	_placement_title = UiFx.label("", "HeadingLabel")
	_placement_reason = UiFx.paragraph("", "SmallLabel")
	_placement_synergy = UiFx.paragraph("", "SmallLabel")
	_placement_synergy.add_theme_color_override("font_color", SYNERGY_COLOR)
	var cancel := Button.new()
	cancel.text = Tr.t("Terminer")
	cancel.custom_minimum_size = Vector2(0, 68)
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.pressed.connect(func() -> void:
		AudioManager.play("click")
		_stop_placement())
	_placement_confirm = Button.new()
	_placement_confirm.theme_type_variation = "GoldButton"
	_placement_confirm.text = Tr.t("Construire ici")
	_placement_confirm.custom_minimum_size = Vector2(0, 68)
	_placement_confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_placement_confirm.focus_mode = Control.FOCUS_NONE
	_placement_confirm.pressed.connect(_confirm_placement)
	_placement_bar = UiFx.panel("WindowPanel", UiFx.vbox(8, [
		_placement_title, _placement_reason, _placement_synergy, UiFx.hbox(10, [cancel, _placement_confirm])]))
	_placement_bar.visible = false
	return _placement_bar


func _connect_engine() -> void:
	_engine.research_completed.connect(_on_research_completed)
	_engine.objective_completed.connect(_on_objective_completed)
	_engine.card_unlocked.connect(_queue_discovery)
	_engine.storm_warning.connect(func() -> void:
		AudioManager.play("alert")
		_news.post(Tr.t("Les satellites annoncent une tempête de poussière : remplissez les batteries !")))
	_engine.storm_started.connect(func() -> void:
		AudioManager.play("storm")
		_news.post(Tr.t("Tempête de poussière ! Les panneaux solaires ne reçoivent plus que 20 % de la lumière.")))
	_engine.storm_ended.connect(func() -> void: _news.post(Tr.t("La tempête est passée. Le ciel redevient caramel.")))
	_engine.resupply_arrived.connect(_on_resupply)
	_engine.colonist_evacuated.connect(_on_evacuation)
	_engine.colonist_arrived.connect(func(n: String) -> void:
		AudioManager.play("recruit", 0.0, 1.0, 1.5)
		_news.post(Tr.t("%s rejoint la colonie. Bienvenue !") % n))
	_engine.shortage.connect(func(r: String) -> void:
		AudioManager.play("alert")
		_news.post(Tr.t("Alerte : plus %s ! Les colons puisent dans leurs réserves de secours.") % Tr.t(ColonyContent.RESOURCE_PARTITIVE[r])))
	_engine.building_placed.connect(func(_i: int) -> void: _world.sync_with_game())
	_engine.breakdown.connect(func(i: int) -> void:
		AudioManager.play("breakdown")
		_news.post(Tr.t("Panne ! ") + Tr.t(ColonyContent.BREAKDOWN_LINES.get(_engine.state.buildings[i].id, Tr.t("Une machine s'est arrêtée.")))))
	_engine.era_started.connect(_on_era_started)
	var campaign := GameManager.campaign
	if campaign != null:
		campaign.shipment_arrived.connect(_on_shipment_arrived)
		campaign.colony_founded.connect(_on_colony_founded)
	_engine.flare_warning.connect(func() -> void:
		AudioManager.play("alert")
		_news.post(Tr.t("Les satellites détectent une éruption solaire : les particules arrivent dans quelques heures. Tout le monde aux abris !")))
	_engine.flare_started.connect(func() -> void:
		AudioManager.play("flare")
		_news.post(Tr.t("Éruption solaire en cours. Les compteurs Geiger crépitent.")))
	_engine.flare_ended.connect(func() -> void: _news.post(Tr.t("L'éruption solaire est passée. On peut ressortir.")))
	_engine.expedition_returned.connect(func(site: Dictionary) -> void:
		AudioManager.play("rover_back")
		_news.post(Tr.t("Le rover est rentré : %s. Butin : %s.") % [Tr.t(site.name), ColonyPage._reward_text(site.reward)]))
	_engine.meteor_impact.connect(func(i: int) -> void:
		AudioManager.play("meteor")
		_world.impact(i)
		if i >= 0:
			_news.post(Tr.t("Impact de météorite sur le module « %s » : réparez-le. Les éclats de métal récupérés font %d matériaux.")
					% [Tr.t(_engine.def_of(i).name), roundi(ColonyEngine.METEOR_SALVAGE)])
		else:
			_news.post(Tr.t("Une petite météorite est tombée près de la colonie. Les éclats de métal récupérés font %d matériaux.")
					% roundi(ColonyEngine.METEOR_SALVAGE)))
	_engine.aurora_started.connect(func() -> void:
		AudioManager.play("aurora")
		_news.post(Tr.t("Une aurore verte illumine la nuit martienne ! Les mesures des colons rapportent %d données.")
				% roundi(ColonyEngine.AURORA_DATA)))
	_engine.world_event.connect(func(planet: String, event_id: String, gains: Dictionary) -> void:
		AudioManager.play(ColonyContent.world_event(event_id).sound)
		_world.world_event(planet)
		var gained := ColonyPage._reward_text(gains) if not gains.is_empty() else Tr.t("rien, faute de place")
		_news.post(Tr.t(ColonyContent.world_event(event_id).news) % gained))
	_engine.dilemma_raised.connect(func(_id: String) -> void:
		AudioManager.play("dilemma")
		_show_dilemma())
	_engine.dilemma_resolved.connect(func(report: Dictionary) -> void:
		if report.auto:
			_news.post(Tr.t("Sans réponse à temps, la colonie a choisi la prudence : %s") % report.text)
		else:
			_news.post(Tr.t("%s : %s") % [Tr.t(ColonyContent.DILEMMAS[report.id].title), report.text]))
	_engine.challenge_started.connect(func(id: String) -> void:
		_news.post(Tr.t("Nouveau défi : %s. %s") % [Tr.t(ColonyContent.CHALLENGES[id].title), Tr.t(ColonyContent.CHALLENGES[id].text)]))
	_engine.challenge_completed.connect(func(id: String) -> void:
		var def: Dictionary = ColonyContent.CHALLENGES[id]
		AudioManager.play("challenge")
		UiFx.float_text(Tr.t("Défi réussi ! %s") % ColonyPage._reward_text(def.reward), Vector2(size.x / 2.0, size.y * 0.4), Palette.MONEY)
		_news.post(Tr.t("Défi réussi : %s. Récompense : %s.") % [Tr.t(def.title), ColonyPage._reward_text(def.reward)]))
	_engine.challenge_expired.connect(func(id: String) -> void:
		_news.post(Tr.t("Défi « %s » non tenu à temps. Un autre arrive.") % Tr.t(ColonyContent.CHALLENGES[id].title)))
	_engine.dust_devil.connect(func(count: int) -> void:
		_news.post((Tr.t("Un tourbillon de poussière a balayé %d panneaux. Merci le vent !") % count) if count > 1
				else Tr.t("Un tourbillon de poussière a balayé un panneau. Merci le vent !")))


func _layout_changed() -> void:
	var window_size := Vector2(DisplayServer.window_get_size())
	var safe := Rect2(DisplayServer.get_display_safe_area())
	var factor := size / window_size if window_size.x > 0 and window_size.y > 0 else Vector2.ONE
	var top := 0.0
	var bottom := 0.0
	if OS.has_feature("mobile") and safe.size.y > 0.0:
		top = safe.position.y * factor.y
		bottom = (window_size.y - safe.end.y) * factor.y
	_safe_area.add_theme_constant_override("margin_left", MARGIN)
	_safe_area.add_theme_constant_override("margin_right", MARGIN)
	_safe_area.add_theme_constant_override("margin_top", int(top) + MARGIN)
	_safe_area.add_theme_constant_override("margin_bottom", int(bottom) + MARGIN)
	_window.custom_minimum_size.y = 0.0 if _window.collapsed else size.y * WINDOW_SHARE
	await get_tree().process_frame
	var covered_top := _status.get_global_rect().end.y
	var bottom_top := _window.get_global_rect().position.y
	for panel: Control in [_placement_bar, _coach]:
		if panel.visible:
			bottom_top = minf(bottom_top, panel.get_global_rect().position.y)
	var covered_bottom := size.y - bottom_top
	_world.rig.covered_fraction = clampf((covered_bottom - covered_top) / size.y, -0.5, 0.9)


func _update_message_slot() -> void:
	_message_slot.visible = _alert.has_alert() or _news.visible


func _refresh() -> void:
	_status.refresh()
	_pages[_current_page].refresh()
	_world.sync_with_game()
	if not _placing.is_empty():
		_world.refresh_ghost()
		_refresh_placement()
	_window.set_badge(2, _research_page.has_available_research())
	_window.set_badge(3, _engine.unread_cards() > 0)
	_refresh_guidance()
	AudioManager.set_mood("storm" if _engine.is_storm() else ("night" if _engine.is_night() else "day"))
	AudioManager.set_wind(1.0 if _engine.is_storm() else 0.0)
	if _engine.state.sol >= _next_chatter and _engine.state.speed > 0:
		_next_chatter = _engine.state.sol + CHATTER_EVERY + randf()
		var line := _colonist_line()
		_news.post(line if not line.is_empty() and randf() < 0.6 else ColonyContent.CHATTER[randi() % ColonyContent.CHATTER.size()])


## Alertes et guide : affichés sans gêner le placement.
func _refresh_guidance() -> void:
	var alerts := ColonyAdvisor.alerts(_engine)
	var top: Dictionary = alerts[0] if not alerts.is_empty() else {}
	var was_visible := _alert.has_alert()
	var was_danger: bool = _alert.has_alert() and _alert._alert.get("level") == "danger"
	_alert.show_alert(top, maxi(0, alerts.size() - 1))
	_news.set_hold(not top.is_empty() and top.level == "danger")
	_update_message_slot()
	if not top.is_empty() and top.level == "danger" and not was_danger:
		AudioManager.play("alert")
	var step := ColonyAdvisor.tutorial_step(_engine) if _placing.is_empty() else -1
	var coach_was_visible := _coach.visible
	if _coach.show_step(step) and coach_was_visible and _placing.is_empty():
		AudioManager.play("milestone")
		if step >= 0:
			_news.post(Tr.t("Étape du guide réussie !"))
		elif _engine.state.era == 1 and _engine.planet_id() == "mars":
			_news.post(Tr.t("Guide terminé : votre colonie respire, boit et mange. Bravo !"))
		else:
			_news.post(Tr.t("Guide de l'ère terminé. Bravo, commandant !"))
	if _alert.has_alert() != was_visible or _coach.visible != coach_was_visible:
		_layout_changed.call_deferred()


## Emmène le joueur à la solution : ouvre l'onglet et met la ligne en évidence.
func _go_to(tab: int, target: String) -> void:
	if not _placing.is_empty():
		_stop_placement()
	if target == "maintenance":
		_show_maintenance()
		return
	if target == "expeditions":
		_show_expeditions()
		return
	if target == "network":
		_show_network()
		return
	if target == "dilemma":
		_show_dilemma()
		return
	_select_tab(tab)
	_pages[tab].highlight(target)


func _show_page(index: int) -> void:
	if index == _current_page:
		_pages[index].scroll.scroll_vertical = 0
		return
	_pages[_current_page].visible = false
	_current_page = index
	var page := _pages[index]
	page.visible = true
	page.on_shown()
	page.modulate.a = 0.0
	page.create_tween().tween_property(page, "modulate:a", 1.0, 0.15)


func _select_tab(index: int) -> void:
	_window.select(index)
	if _window.collapsed:
		_window.toggle_collapsed()
	_show_page(index)


# ---------- Placement ----------

func _start_placement(def_id: String) -> void:
	AudioManager.play("click")
	_placing = def_id
	if not _window.collapsed:
		_window.toggle_collapsed()
	_placement_bar.visible = true
	_world.start_placement(def_id)
	_refresh_placement()
	_layout_changed.call_deferred()


func _stop_placement() -> void:
	_placing = ""
	_world.stop_placement()
	_placement_bar.visible = false
	if _window.collapsed:
		_window.toggle_collapsed()
	_layout_changed.call_deferred()


func _refresh_placement() -> void:
	if _placing.is_empty():
		return
	var def: Defs.Building = _engine.building_defs[_placing]
	var cell := _world.ghost_cell()
	_placement_title.text = Tr.t("Placer : %s (%s matériaux)") % [Tr.t(def.name), NumberFormatter.format(def.cost)]
	var problem := _engine.placement_problem(_placing, cell)
	if not problem.is_empty():
		_placement_reason.text = problem
		_placement_reason.add_theme_color_override("font_color", Palette.DANGER)
	elif not _engine.would_connect(_placing, cell):
		_placement_reason.text = Tr.t("Possible, mais isolé : il ne fonctionnera pas sans être relié (posez des conduites).")
		_placement_reason.add_theme_color_override("font_color", Palette.WARNING)
	else:
		_placement_reason.text = Tr.t("Touchez le sol pour déplacer le module. Emplacement valide et raccordé.")
		_placement_reason.add_theme_color_override("font_color", Palette.SUCCESS)
	_placement_confirm.disabled = not problem.is_empty()
	var bonuses: Array[String] = []
	if problem.is_empty():
		for found: Dictionary in _engine.preview_synergies(_placing, cell):
			bonuses.append(Tr.t("✦ %s : %s (%s)") % [Tr.t(found.synergy.name), Tr.t(found.synergy.effect), Tr.t(found.target)])
	_placement_synergy.text = "\n".join(bonuses)
	_placement_synergy.visible = not bonuses.is_empty()


func _confirm_placement() -> void:
	if _engine.place(_placing, _world.ghost_cell()):
		AudioManager.play("build")
		# On reste en mode placement pour enchaîner (conduites, panneaux...), une case plus loin.
		var def: Defs.Building = _engine.building_defs[_placing]
		_world.move_ghost(_world.ghost_cell() + Vector2i(def.size.x, 0))
	else:
		AudioManager.play("fail")
		UiFx.shake(_placement_confirm)


# ---------- Gestes sur le monde ----------

func _on_world_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
		else:
			_touches.erase(event.index)
		_pinch_distance = _touch_spread()
	elif event is InputEventScreenDrag and _touches.size() >= 2:
		_touches[event.index] = event.position
		var spread := _touch_spread()
		if _pinch_distance > 0.0 and spread > 0.0:
			_world.rig.zoom(_pinch_distance / spread)
		_pinch_distance = spread
		_dragged = true
	elif event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_world.rig.zoom(0.9)
			MOUSE_BUTTON_WHEEL_DOWN:
				_world.rig.zoom(1.1)
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					_press_position = event.position
					_dragged = false
				elif not _dragged and _touches.size() <= 1 and _photo_bar == null:
					_world.tap(event.position)
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		if _touches.size() >= 2:
			return
		if not _dragged and event.position.distance_to(_press_position) < TAP_SLOP:
			return
		_dragged = true
		_world.rig.pan_pixels(event.relative)
	elif event is InputEventMagnifyGesture:
		_world.rig.zoom(1.0 / event.factor)


func _touch_spread() -> float:
	if _touches.size() < 2:
		return 0.0
	var points := _touches.values()
	return (points[0] as Vector2).distance_to(points[1])


func _on_cell_tapped(cell: Vector2i, index: int) -> void:
	if index >= 0:
		_show_building(index)
		return
	var planet := _engine.planet()
	match _engine.map.tile_at(cell):
		ColonyMap.Tile.ROCK:
			_news.post(Tr.t(planet.rock))
		ColonyMap.Tile.RIM:
			_news.post(Tr.t(_engine.region().rim))
		ColonyMap.Tile.ICE:
			# Sur Mars, la glace se cache sous la poussière tant qu'on ne l'a pas cherchée.
			_news.post(Tr.t(planet.ice) if _engine.state.research_done.has("ice") or _engine.planet_id() != "mars"
					else Tr.t(planet.ground))
		_:
			_news.post(Tr.t(planet.ground))


# ---------- Événements ----------

func _on_research_completed(research_id: String) -> void:
	var r: Defs.Research = _engine.research_defs[research_id]
	AudioManager.play("research_done")
	_news.post(Tr.t("Recherche terminée : %s") % Tr.t(r.name))
	if research_id == "ice":
		_news.post(Tr.t("Les relevés révèlent de la glace sous la poussière : regardez la carte !"))


func _on_objective_completed(objective_id: String) -> void:
	for o in _engine.objectives:
		if o.id == objective_id:
			AudioManager.play("objective")
			_news.post(Tr.t("Objectif atteint : %s ! Récompense : %s") % [Tr.t(o.title), ColonyPage._reward_text(o.reward)])
			if objective_id == "rooted":
				Modal.open(_modal_layer, {
					"icon": "check", "title": Tr.t("Colonie enracinée !"),
					"body": Tr.t("Vingt colons vivent à l'abri des radiations, nourris par une serre sur un sol vivant et ")
							+ Tr.t("alimentés jour et nuit. Votre colonie est durable : c'est exactement ce que préparent ")
							+ Tr.t("les agences spatiales pour les premières bases martiennes.\n\nProchaine étape : le reste du Système solaire."),
					"confirm_text": Tr.t("Continuer à jouer"),
				})
			if objective_id == "return":
				Modal.open(_modal_layer, {
					"icon": "rocket", "title": Tr.t("Retour assuré !"),
					"body": Tr.t("Les réservoirs du véhicule de retour sont pleins de méthane fabriqué sur Mars, comme dans le plan ")
							+ Tr.t("Mars Direct. Votre colonie est autonome, explore les environs, et peut rentrer quand elle le veut.\n\n")
							+ Tr.t("Bravo, commandant ! Prochaine étape : rendre la colonie durable."),
					"confirm_text": Tr.t("Continuer à jouer"),
				})


func _on_resupply(report: Dictionary) -> void:
	_world.land_capsule()
	AudioManager.play("landing")
	var text := ""
	if report.get("rescue", false):
		text = Tr.t("Envoi de secours : la Terre fournit %s matériaux, juste de quoi construire un four à régolithe.") % NumberFormatter.format(report.materials)
	elif report.materials > 0.0:
		text = Tr.t("Ravitaillement de la Terre : +%s matériaux") % NumberFormatter.format(report.materials)
		if report.food > 0.0:
			text += Tr.t(", +%s rations") % NumberFormatter.format(report.food)
		else:
			text += Tr.t(". Plus de nourriture : la Terre compte sur vos serres")
		if not report.colonists.is_empty():
			text += Tr.t(". À bord : %s") % ", ".join(report.colonists)
		text += "."
	else:
		text = Tr.t("Une capsule de volontaires se pose : %s. Pas de matériaux à bord.") % ", ".join(report.colonists)
	_news.post(text)
	if report.get("last", false):
		Modal.open(_modal_layer, {
			"icon": "materials", "title": Tr.t("Dernier envoi de matériaux"),
			"body": Tr.t("La Terre ne peut plus financer les envois de matériaux. Des volontaires viendront encore, mais ")
					+ Tr.t("il faut désormais fabriquer vos matériaux sur place : recherchez « Frittage du régolithe » ")
					+ Tr.t("et construisez des fours à régolithe."),
			"confirm_text": Tr.t("Compris"),
		})


## Bouton Retour (Android) : ferme la fenêtre du dessus, sinon revient au menu principal.
## Réglage des graphismes, changé depuis le panneau des réglages.
func apply_quality(level: int) -> void:
	_world.apply_quality(level)


func on_back() -> void:
	if _photo_bar != null:
		_close_photo_mode()
		return
	for i in range(_modal_layer.get_child_count() - 1, -1, -1):
		var child := _modal_layer.get_child(i)
		if child is Modal:
			child.close()
			return
	if is_instance_valid(_solar):
		_close_network()
		return
	GameManager.open_menu()


func _on_evacuation(colonist_name: String, cause: String) -> void:
	_world.launch_evacuation()
	AudioManager.play("evacuation")
	_news.post(Tr.t("%s a été évacué vers la Terre.") % colonist_name)
	if is_instance_valid(_evacuation_modal):
		return
	_evacuation_modal = Modal.open(_modal_layer, {
		"icon": "warning", "title": Tr.t("%s évacué") % colonist_name,
		"body": (Tr.t("Sa santé ne permettait plus de rester sur Mars. Une capsule l'a ramené vers la Terre.\n\n")
				if _engine.planet_id() == "mars" else Tr.t("Sa santé ne permettait plus de rester ici. Le vaisseau de secours l'a ramené vers Mars.\n\n"))
				+ Tr.t("Cause : ") + Tr.t(cause),
		"confirm_text": Tr.t("Compris"),
	})


# ---------- Fenêtres ----------

func _show_welcome() -> void:
	Modal.open(_modal_layer, {
		"icon": "rocket", "title": Tr.t("Bienvenue : ") + Tr.t(_engine.region().name),
		"body": Tr.t("Votre équipage de 4 colons vient de se poser. Les réserves d'oxygène tiennent environ 9 sols.\n\n")
				+ Tr.t("Suivez le guide en bas de l'écran : il vous montre quoi faire, étape par étape.\n")
				+ Tr.t("Touchez une ressource en haut pour savoir d'où elle vient."),
		"confirm_text": Tr.t("C'est parti"),
	})


func _show_building(index: int) -> void:
	var def := _engine.def_of(index)
	var status := _engine.building_status(index)
	var lines: Array[String] = []
	# Débit moyen réel (soleil, poussière, recherches, synergies, améliorations), comme le bandeau.
	# À l'arrêt (panne, débranché) : ce qu'il ferait en marche.
	var flows := _engine.building_flows(index)
	var running := not flows.is_empty()
	if not running:
		for r: String in def.outputs:
			flows[r] = def.outputs[r] * _engine.rate_factor(index, r, true)
		for r: String in def.inputs:
			flows[r] = flows.get(r, 0.0) - def.inputs[r] * _engine.rate_factor(index, r, false)
	for r: String in ColonyContent.RESOURCES:
		if flows.has(r) and absf(flows[r]) > 0.005:
			lines.append(Tr.t("%s%s %s %s/sol") % ["+" if flows[r] > 0.0 else "−", NumberFormatter.format(absf(flows[r])),
					Tr.t(ColonyContent.RESOURCE_UNITS[r]), Tr.t(ColonyContent.RESOURCE_NAMES[r]).to_lower()])
	if not running and not flows.is_empty():
		lines.append(Tr.t("(en marche ; à l'arrêt pour l'instant)"))
	elif def.solar:
		lines.append(Tr.t("(moyenne sur un sol, nuits comprises)"))
	for r: String in def.storage:
		lines.append(Tr.t("Stockage : +%s %s %s") % [NumberFormatter.format(_engine.storage_of(index, r)), Tr.t(ColonyContent.RESOURCE_UNITS[r]), Tr.t(ColonyContent.RESOURCE_NAMES[r]).to_lower()])
	if _engine.housing_of(index) > 0:
		lines.append(Tr.t("Loge %d colons") % _engine.housing_of(index))
	if def.solar:
		lines.append(Tr.t("Poussière : %d %% (−%d %% d'énergie)") % [roundi(_engine.dust_of(index) * 100.0),
				roundi(ColonyEngine.DUST_LOSS * _engine.dust_of(index) * 100.0)])
	var status_label := UiFx.paragraph(status.text, "HeadingLabel", HORIZONTAL_ALIGNMENT_CENTER)
	status_label.add_theme_color_override("font_color", Palette.SUCCESS if status.ok else Palette.WARNING)
	var extra := UiFx.vbox(8, [UiFx.panel("Thumb", UiFx.building_icon(def.id, Vector2(200, 160))), status_label,
			UiFx.paragraph("\n".join(lines), "BodyLabel", HORIZONTAL_ALIGNMENT_CENTER)])
	(extra.get_child(0) as Control).size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var holder: Array[Modal] = []
	if def.id == "spaceport":
		var network := Button.new()
		network.theme_type_variation = "GoldButton"
		network.text = Tr.t("Réseau de colonies…")
		network.custom_minimum_size = Vector2(0, 60)
		network.focus_mode = Control.FOCUS_NONE
		network.pressed.connect(func() -> void:
			holder[0].close()
			_show_network.call_deferred())
		extra.add_child(network)
	if def.id == "garage":
		var trips := Button.new()
		trips.theme_type_variation = "PurpleButton"
		trips.text = Tr.t("Expéditions…")
		trips.custom_minimum_size = Vector2(0, 60)
		trips.focus_mode = Control.FOCUS_NONE
		trips.pressed.connect(func() -> void:
			holder[0].close()
			_show_expeditions.call_deferred())
		extra.add_child(trips)
	if _engine.is_broken(index) or def.solar:
		var care := Button.new()
		care.theme_type_variation = "GoldButton" if _engine.is_broken(index) else "Button"
		care.text = Tr.t("Réparer…") if _engine.is_broken(index) else Tr.t("Entretien des panneaux…")
		care.custom_minimum_size = Vector2(0, 60)
		care.focus_mode = Control.FOCUS_NONE
		care.pressed.connect(func() -> void:
			holder[0].close()
			_show_maintenance.call_deferred())
		extra.add_child(care)
	extra.add_child(_synergy_block(index))
	extra.add_child(_upgrade_block(index, holder))
	if not def.card.is_empty() and _engine.state.cards_unlocked.has(def.card):
		var learn := Button.new()
		learn.text = Tr.t("En savoir plus : ") + Tr.t(_engine.cards[def.card].title)
		learn.focus_mode = Control.FOCUS_NONE
		learn.clip_text = true
		learn.pressed.connect(func() -> void: _show_card(def.card))
		extra.add_child(learn)
	# Démolir : en bas de la fiche, discret et loin de « Fermer » (avec confirmation).
	if not def.fixed:
		var demolish := Button.new()
		demolish.flat = true
		demolish.text = Tr.t("Démolir ce module (+%s matériaux)") % NumberFormatter.format(def.cost * ColonyEngine.DEMOLISH_REFUND)
		demolish.focus_mode = Control.FOCUS_NONE
		demolish.add_theme_color_override("font_color", Palette.DANGER)
		demolish.add_theme_font_size_override("font_size", 17)
		demolish.pressed.connect(func() -> void:
			AudioManager.play("click")
			holder[0].close()
			_confirm_demolish.call_deferred(index))
		var gap := UiFx.spacer()
		gap.custom_minimum_size.y = 12
		extra.add_child(gap)
		extra.add_child(demolish)
	var options := {
		"icon": "tab_build", "title": Tr.t(def.name), "body": def.description, "extra": extra, "confirm_text": Tr.t("Fermer"),
	}
	var scroll: ScrollContainer = null
	if _engine.max_level(index) > 1:
		# Fiche longue (améliorations) : elle défile, mais sans laisser de vide si elle est courte.
		scroll = ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		extra.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(extra)
		options.extra = scroll
	var modal := Modal.open(_modal_layer, options)
	holder.append(modal)
	if scroll != null:
		var cap := minf(860.0, size.y * 0.62)
		scroll.custom_minimum_size.y = minf(extra.get_combined_minimum_size().y, cap)
		extra.minimum_size_changed.connect(func() -> void:
			scroll.custom_minimum_size.y = minf(extra.get_combined_minimum_size().y, cap))


func _confirm_demolish(index: int) -> void:
	if index >= _engine.state.buildings.size():
		return
	var def := _engine.def_of(index)
	Modal.open(_modal_layer, {
		"icon": "warning", "title": Tr.t("Démolir : %s ?") % Tr.t(def.name),
		"body": Tr.t("Le module disparaît, ses améliorations aussi. Vous récupérez %s matériaux.")
				% NumberFormatter.format(def.cost * ColonyEngine.DEMOLISH_REFUND),
		"confirm_text": Tr.t("Démolir"),
		"on_confirm": func() -> void:
			if _engine.demolish(index):
				AudioManager.play("whoosh"),
		"cancel_text": Tr.t("Garder"),
	})


# ---------- Réseau de colonies ----------

func _on_shipment_arrived(shipment: Dictionary) -> void:
	var campaign := GameManager.campaign
	if shipment.kind == "colony":
		return
	if shipment.to == campaign.active:
		_world.land_capsule()
		AudioManager.play("landing")
	_news.post(Tr.t("Cargaison livrée : %s → %s.") % [campaign.colony_name(shipment.from), campaign.colony_name(shipment.to)])
	var lost: Dictionary = shipment.get("lost", {})
	if not lost.is_empty():
		_news.post(Tr.t("Faute de stockage, une partie de la cargaison est perdue : %s.") % ColonyPage._reward_text(lost))


func _on_colony_founded(index: int) -> void:
	var campaign := GameManager.campaign
	AudioManager.play("milestone")
	Modal.open(_modal_layer, {
		"icon": "planet", "title": Tr.t("Nouvelle colonie : %s") % campaign.colony_name(index),
		"body": Tr.t("L'équipage s'est posé et a déployé son atterrisseur. La colonie partage tout votre savoir, mais elle part de presque rien : envoyez-lui des cargaisons depuis l'astroport."),
		"confirm_text": Tr.t("Y aller"), "confirm_style": "GoldButton",
		"on_confirm": func() -> void: GameManager.switch_colony(index),
		"cancel_text": Tr.t("Plus tard"),
	})


## Réseau de colonies, vu dans le Système solaire (voir SolarView). Les fenêtres s'ouvrent par-dessus.
func _show_network() -> void:
	if is_instance_valid(_solar):
		return
	AudioManager.play("whoosh")
	_solar = SolarView.new(GameManager.campaign)
	_solar.inset_top = _safe_area.get_theme_constant("margin_top")
	_solar.inset_bottom = _safe_area.get_theme_constant("margin_bottom")
	_solar.closed.connect(_close_network)
	_solar.colony_chosen.connect(func(index: int) -> void:
		AudioManager.play("whoosh")
		GameManager.switch_colony(index))
	_solar.cargo_requested.connect(_show_cargo)
	_solar.founding_requested.connect(_show_founding)
	_solar.list_requested.connect(_show_network_list)
	_solar.found_at.connect(func(region: String) -> void: _found_colony(GameManager.campaign.active, region))
	add_child(_solar)
	move_child(_solar, _modal_layer.get_index())
	# La colonie n'est plus ni dessinée ni animée tant que la vue est ouverte (une seule scène 3D
	# à la fois : sans cela, son ciel et ses animations coûtent autant que la vue elle-même).
	_world.visible = false
	_world.process_mode = Node.PROCESS_MODE_DISABLED
	get_viewport().disable_3d = true


func _close_network() -> void:
	if is_instance_valid(_solar):
		_solar.queue_free()
	_solar = null
	_world.visible = true
	_world.process_mode = Node.PROCESS_MODE_INHERIT
	get_viewport().disable_3d = false


## Réseau de colonies en liste : chaque colonie, les fusées en vol, et les actions de l'astroport.
func _show_network_list() -> void:
	var campaign := GameManager.campaign
	var holder: Array[Modal] = []
	var box := UiFx.vbox(10)
	for i in campaign.colonies.size():
		var state := campaign.colonies[i]
		var name := UiFx.label(campaign.colony_name(i), "HeadingLabel")
		var info := UiFx.label(Tr.t("%s · Sol %d · %d colons · ère %d") % [Tr.t(ColonyContent.PLANETS[campaign.planet_of(i)].name),
				int(state.sol) + 1, state.colonists.size(), state.era], "SmallLabel")
		var status := UiFx.paragraph("", "SmallLabel")
		var alerts := ColonyAdvisor.alerts(campaign.engines[i])
		if campaign.standby.has(i):
			status.text = Tr.t("En veille : la réserve %s est trop basse.") % Tr.t(ColonyContent.RESOURCE_PARTITIVE[campaign.standby[i]])
			status.add_theme_color_override("font_color", Palette.WARNING)
		elif not alerts.is_empty():
			status.text = alerts[0].title
			status.add_theme_color_override("font_color", Palette.DANGER if alerts[0].level == "danger" else Palette.WARNING)
		else:
			status.text = Tr.t("Tout va bien.")
			status.add_theme_color_override("font_color", Palette.SUCCESS)
		var text := UiFx.vbox(2, [name, info, status])
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var row := UiFx.hbox(8, [UiFx.image(UiFx.icon("planet"), 30, Palette.MONEY if i == campaign.active else Palette.TEXT_MUTED), text])
		if i == campaign.active:
			var here := UiFx.label(Tr.t("Ici"), "CaptionLabel")
			here.add_theme_color_override("font_color", Palette.ACCENT)
			row.add_child(here)
		else:
			var go := Button.new()
			go.text = Tr.t("Y aller")
			go.theme_type_variation = "GreenButton"
			go.custom_minimum_size = Vector2(110, 52)
			go.focus_mode = Control.FOCUS_NONE
			go.pressed.connect(func() -> void:
				AudioManager.play("whoosh")
				GameManager.switch_colony(i))
			row.add_child(go)
		box.add_child(UiFx.panel("Row", row))
	if not campaign.shipments.is_empty():
		box.add_child(UiFx.label(Tr.t("En vol"), "HeadingLabel"))
		for shipment: Dictionary in campaign.shipments:
			var target: String = campaign.colony_name(shipment.to) if shipment.to >= 0 \
					else Tr.t(ColonyContent.REGIONS[shipment.region].name)
			var what := Tr.t("Vaisseau de fondation") if shipment.kind == "colony" else Tr.t("Cargaison")
			var left := maxf(0.0, shipment.arrive - campaign.time)
			box.add_child(UiFx.paragraph(Tr.t("%s : %s → %s, arrivée dans %s sol%s.") % [what, campaign.colony_name(shipment.from),
					target, NumberFormatter.format(left), "s" if left >= 2.0 else ""], "SmallLabel"))
	var actions := UiFx.hbox(8)
	var cargo := Button.new()
	cargo.text = Tr.t("Expédier une cargaison")
	cargo.custom_minimum_size = Vector2(0, 60)
	cargo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cargo.focus_mode = Control.FOCUS_NONE
	cargo.disabled = campaign.colonies.size() < 2
	cargo.pressed.connect(func() -> void:
		holder[0].close()
		_show_cargo.call_deferred())
	var found := Button.new()
	found.theme_type_variation = "GoldButton"
	found.text = Tr.t("Fonder une colonie")
	found.custom_minimum_size = Vector2(0, 60)
	found.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	found.focus_mode = Control.FOCUS_NONE
	found.pressed.connect(func() -> void:
		holder[0].close()
		_show_founding.call_deferred())
	actions.add_child(cargo)
	actions.add_child(found)
	box.add_child(actions)
	if campaign.interplanetary_unlocked():
		# Longue liste : repliée, on la déplie au toucher.
		var lines := UiFx.vbox(4)
		for line in _window_lines(campaign):
			lines.add_child(UiFx.paragraph(line, "SmallLabel"))
		box.add_child(Foldable.new(UiFx.label(Tr.t("Fenêtres de tir"), "HeadingLabel"), lines))

	var scroll := _fitted_scroll(box)
	holder.append(Modal.open(_modal_layer, {
		"icon": "planet", "title": Tr.t("Réseau de colonies"), "extra": scroll, "confirm_text": Tr.t("Fermer"),
	}))


## Zone défilante dont la hauteur suit le contenu, sans dépasser 62 % de l'écran.
func _fitted_scroll(box: Control) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var cap := minf(820.0, size.y * 0.62)
	scroll.custom_minimum_size.y = cap
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	var fit := func() -> void:
		if is_instance_valid(scroll):
			scroll.custom_minimum_size.y = minf(cap, box.get_combined_minimum_size().y)
	box.resized.connect(fit)
	return scroll


## Fonder une colonie : le site d'atterrissage, et ce que le vaisseau emporte (selon la destination).
func _show_founding() -> void:
	var campaign := GameManager.campaign
	var origin := campaign.active
	var holder: Array[Modal] = []
	var box := UiFx.vbox(10)
	box.add_child(UiFx.paragraph(Tr.t("Le vaisseau emporte %d colons de cette colonie, des matériaux pour démarrer, et son carburant.") % Campaign.FOUNDING_CREW, "SmallLabel"))
	for id: String in ColonyContent.FOUNDING_REGIONS:
		var region: Dictionary = ColonyContent.REGIONS[id]
		var planet: Dictionary = ColonyContent.PLANETS[region.planet]
		var title := UiFx.label("%s · %s" % [Tr.t(planet.name), Tr.t(region.name)], "HeadingLabel")
		var cost := campaign.founding_cost(origin, id)
		var trip := UiFx.label(Tr.t("%s matériaux · %s kg de méthane · %s sol%s de voyage") % [
				NumberFormatter.format(cost[ColonyContent.MATERIALS]), NumberFormatter.format(cost[ColonyContent.METHANE]),
				NumberFormatter.format(campaign.transit_sols(origin, id)), "s" if campaign.transit_sols(origin, id) >= 2.0 else ""], "SmallLabel")
		trip.add_theme_color_override("font_color", Palette.ACCENT)
		var problem := campaign.founding_problem(origin, id)
		var go := Button.new()
		go.theme_type_variation = "GoldButton"
		go.text = Tr.t("Se poser ici")
		go.custom_minimum_size = Vector2(0, 56)
		go.focus_mode = Control.FOCUS_NONE
		go.disabled = not problem.is_empty()
		go.pressed.connect(func() -> void:
			if _found_colony(origin, id):
				holder[0].close())
		var rows: Array = [title, UiFx.paragraph(Tr.t(region.tagline), "SmallLabel"), trip, go]
		if not problem.is_empty():
			var reason := UiFx.paragraph(problem, "SmallLabel", HORIZONTAL_ALIGNMENT_CENTER)
			reason.add_theme_color_override("font_color", Palette.WARNING)
			rows.append(reason)
		box.add_child(UiFx.panel("Row", UiFx.vbox(6, rows)))
	var scroll := _fitted_scroll(box)
	holder.append(Modal.open(_modal_layer, {
		"icon": "planet", "title": Tr.t("Fonder une colonie"), "extra": scroll, "confirm_text": Tr.t("Fermer"),
	}))


## Lance un vaisseau de fondation (bruit, vibration, décollage, nouvelle). Vrai s'il est parti.
func _found_colony(origin: int, region: String) -> bool:
	if not GameManager.campaign.found_colony(origin, region):
		return false
	AudioManager.play("launch")
	_world.launch_from_spaceport()
	_news.post(Tr.t("Le vaisseau de fondation décolle vers %s !") % Tr.t(ColonyContent.REGIONS[region].name))
	return true


## Fenêtres de tir entre les mondes du réseau (et vers les mondes à coloniser).
func _window_lines(campaign: Campaign) -> Array[String]:
	var lines: Array[String] = []
	for key: String in ColonyContent.ROUTES:
		var worlds := key.split("-")
		var a := worlds[0]
		var b := worlds[1]
		var r: Dictionary = ColonyContent.ROUTES[key]
		var names := "%s ⇄ %s" % [Tr.t(ColonyContent.PLANETS[a].name), Tr.t(ColonyContent.PLANETS[b].name)]
		if campaign.window_open(a, b):
			lines.append(Tr.t("%s : fenêtre de tir ouverte, encore %s sols · trajet %s sols.") % [names,
					NumberFormatter.format(campaign.window_wait(a, b, true)), NumberFormatter.format(r.transit)])
		else:
			lines.append(Tr.t("%s : prochaine fenêtre de tir dans %s sols · trajet %s sols.") % [names,
					NumberFormatter.format(campaign.window_wait(a, b)), NumberFormatter.format(r.transit)])
	return lines


## Cargaison : destination, quantités (et colons), carburant et arrivée.
func _show_cargo() -> void:
	var campaign := GameManager.campaign
	var origin := campaign.active
	var holder: Array[Modal] = []
	var amounts := {}
	var crew := [0]
	var destination := [-1]
	for i in campaign.colonies.size():
		if i != origin:
			destination[0] = i
			break
	var box := UiFx.vbox(8)
	box.add_child(UiFx.label(Tr.t("Destination"), "HeadingLabel"))
	var group := ButtonGroup.new()
	var refresh_ref: Array[Callable] = []
	# Deux par ligne : la fenêtre garde sa largeur, quel que soit le nombre de colonies.
	var targets := GridContainer.new()
	targets.columns = mini(2, campaign.colonies.size() - 1)
	targets.add_theme_constant_override("h_separation", 6)
	targets.add_theme_constant_override("v_separation", 6)
	for i in campaign.colonies.size():
		if i == origin:
			continue
		var target := Button.new()
		target.text = campaign.colony_name(i)
		target.clip_text = true
		target.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		target.toggle_mode = true
		target.button_group = group
		target.button_pressed = i == destination[0]
		target.theme_type_variation = "SegmentButton"
		target.custom_minimum_size = Vector2(0, 52)
		target.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		target.focus_mode = Control.FOCUS_NONE
		target.pressed.connect(func() -> void:
			destination[0] = i
			refresh_ref[0].call())
		targets.add_child(target)
	box.add_child(targets)
	box.add_child(UiFx.label(Tr.t("Soute"), "HeadingLabel"))
	var launch := Button.new()
	var summary := UiFx.paragraph("", "SmallLabel", HORIZONTAL_ALIGNMENT_CENTER)
	var refresh := func() -> void:
		if destination[0] < 0:
			return
		var problem := campaign.shipment_problem(origin, destination[0], amounts, crew[0])
		launch.disabled = not problem.is_empty()
		var region := campaign.colonies[destination[0]].region
		summary.text = problem if not problem.is_empty() else Tr.t("Carburant : %s kg de méthane · arrivée dans %s sol.") % [
				NumberFormatter.format(campaign.fuel_cost(origin, region, amounts, crew[0])),
				NumberFormatter.format(campaign.transit_sols(origin, region))]
		# Arrivée trop pleine : le vol reste permis, le joueur est prévenu.
		var warning := campaign.shipment_warning(destination[0], amounts) if problem.is_empty() else ""
		if not warning.is_empty():
			summary.text = warning
		summary.add_theme_color_override("font_color", Palette.WARNING if not (problem.is_empty() and warning.is_empty()) else Palette.ACCENT)
	refresh_ref.append(refresh)
	var rows: Array = Campaign.CARGO.duplicate()
	rows.append("colonists")
	for r: String in rows:
		var is_crew := r == "colonists"
		var value := UiFx.label("0", "NumberLabel", HORIZONTAL_ALIGNMENT_CENTER)
		value.custom_minimum_size.x = 80
		var name := UiFx.label(Tr.t("Colons") if is_crew else Tr.t(ColonyContent.RESOURCE_NAMES[r]), "BodyLabel")
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var step := 1 if is_crew else 10
		# `sign` : −1 ou +1 (un pas), 0 : le plus possible (réserves de la colonie, place dans la soute).
		var change := func(sign: int) -> void:
			var units: float = crew[0] * Campaign.COLONIST_UNITS
			for k: String in amounts:
				units += amounts[k]
			if is_crew:
				var people: int = campaign.engines[origin].state.colonists.size()
				var room: int = crew[0] + int((Campaign.PAYLOAD_UNITS - units) / Campaign.COLONIST_UNITS)
				crew[0] = mini(people, maxi(room, crew[0])) if sign == 0 else clampi(crew[0] + sign * step, 0, people)
				value.text = str(crew[0])
			else:
				var have := floorf(campaign.engines[origin].state.amount(r))
				var mine: float = amounts.get(r, 0.0)
				var top := minf(have, maxf(mine, Campaign.PAYLOAD_UNITS - units + mine))
				amounts[r] = top if sign == 0 else clampf(mine + sign * step, 0.0, have)
				if amounts[r] <= 0.0:
					amounts.erase(r)
				value.text = NumberFormatter.format(amounts.get(r, 0.0))
			AudioManager.play("click")
			refresh.call()
		var minus := Button.new()
		minus.text = "−"
		minus.custom_minimum_size = Vector2(56, 48)
		minus.focus_mode = Control.FOCUS_NONE
		minus.pressed.connect(func() -> void: change.call(-1))
		var plus := Button.new()
		plus.text = "+"
		plus.custom_minimum_size = Vector2(56, 48)
		plus.focus_mode = Control.FOCUS_NONE
		plus.pressed.connect(func() -> void: change.call(1))
		var most := Button.new()
		most.text = Tr.t("Max")
		most.custom_minimum_size = Vector2(72, 48)
		most.focus_mode = Control.FOCUS_NONE
		most.pressed.connect(func() -> void: change.call(0))
		var icon := UiFx.image(UiFx.icon("person" if is_crew else r), 24, Palette.TEXT if is_crew else Palette.resource_color(r))
		box.add_child(UiFx.hbox(8, [icon, name, minus, value, plus, most]))
	launch.theme_type_variation = "GoldButton"
	launch.text = Tr.t("Lancer la fusée")
	launch.custom_minimum_size = Vector2(0, 64)
	launch.focus_mode = Control.FOCUS_NONE
	launch.pressed.connect(func() -> void:
		if campaign.send_cargo(origin, destination[0], amounts, crew[0]):
			AudioManager.play("launch")
			_world.launch_from_spaceport()
			_news.post(Tr.t("Cargaison en route vers %s.") % campaign.colony_name(destination[0]))
			holder[0].close())
	box.add_child(summary)
	box.add_child(launch)
	refresh.call()
	holder.append(Modal.open(_modal_layer, {
		"icon": "planet", "title": Tr.t("Expédier une cargaison"), "extra": box, "confirm_text": Tr.t("Fermer"),
	}))


## Fin de la campagne : les cinq mondes sont accomplis. Bilan, montré une seule fois.
func _show_finale() -> void:
	var campaign := GameManager.campaign
	if campaign.finale_shown:
		return
	campaign.finale_shown = true
	GameManager.save()
	AudioManager.play("milestone")
	var totals := campaign.totals()
	Modal.open(_modal_layer, {
		"icon": "planet", "title": Tr.t("Campagne accomplie !"),
		"body": Tr.t("De Jezero aux geysers d'Encelade, vos colonies vivent sur cinq mondes et se ravitaillent entre elles. ")
				+ Tr.t("Chaque étape suivait les plans des agences spatiales et ce que les sondes nous ont appris.\n\n")
				+ Tr.t("• %s sols depuis l'atterrissage\n") % NumberFormatter.format(roundf(totals.sols))
				+ Tr.t("• %d colonies, %d colons\n") % [totals.colonies, totals.colonists]
				+ Tr.t("• %d cargaisons livrées\n") % totals.deliveries
				+ Tr.t("• %d fiches lues sur %d, %d bonnes réponses aux quiz\n\n") % [totals.cards, totals.cards_total, totals.quiz]
				+ Tr.t("Merci d'avoir joué, commandant ! Vos colonies continuent de tourner."),
		"confirm_text": Tr.t("Continuer à jouer"),
	})


## Début d'une nouvelle ère : ce qui change et ce qu'il faut viser.
func _on_era_started(era: int) -> void:
	AudioManager.play("era")
	if era == 4:
		Modal.open(_modal_layer, {
			"icon": "planet", "title": Tr.t("Ère 4 · Interplanétaire"),
			"body": Tr.t("Votre colonie est enracinée. Il est temps de s'étendre :\n\n")
					+ Tr.t("• Recherchez puis construisez un astroport.\n")
					+ Tr.t("• Fondez une deuxième colonie sur Mars (bouton planète, en haut).\n")
					+ Tr.t("• Reliez vos colonies par des cargaisons.\n\n")
					+ Tr.t("Ensuite : Cérès, Titan, Europe, puis Encelade."),
			"confirm_text": Tr.t("En route !"),
		})
		return
	if era == 3:
		Modal.open(_modal_layer, {
			"icon": "target", "title": Tr.t("Ère 3 · Racines"),
			"body": Tr.t("Le retour est assuré. Faut-il pour autant transformer Mars en seconde Terre ? Les chercheurs ont ")
					+ Tr.t("fait les comptes : pas avec les techniques actuelles (voir la fiche « Terraformer Mars ? »).\n\n")
					+ Tr.t("Cette ère, on rend plutôt la colonie durable :\n")
					+ Tr.t("• S'abriter des éruptions solaires sous le régolithe.\n")
					+ Tr.t("• Produire de l'énergie nucléaire, jour et nuit.\n")
					+ Tr.t("• Cultiver une serre géante sur un sol vivant.\n")
					+ Tr.t("• Accueillir 20 colons avec la note d'efficacité A."),
			"confirm_text": Tr.t("Au travail !"),
		})
		return
	if era != 2:
		return
	Modal.open(_modal_layer, {
		"icon": "rocket", "title": Tr.t("Ère 2 · Expansion"),
		"body": Tr.t("Votre colonie tient seule sur Mars, bravo ! Place à l'expansion :\n\n")
				+ Tr.t("• Fabriquer du méthane avec la réaction de Sabatier (onglet Recherche).\n")
				+ Tr.t("• Explorer les environs en rover pressurisé et découvrir de vrais sites.\n")
				+ Tr.t("• Accueillir de nouveaux volontaires.\n")
				+ Tr.t("• Construire le véhicule de retour et remplir ses réservoirs, comme dans le plan Mars Direct."),
		"confirm_text": Tr.t("En route !"),
	})


## Expéditions en rover : sites découverts, sites à découvrir, départ.
func _show_expeditions() -> void:
	var holder: Array[Modal] = []
	var box := UiFx.vbox(10)
	box.add_child(UiFx.paragraph(Tr.t("Le rover pressurisé roule au méthane. Chaque expédition dure %s sols et coûte %s kg de méthane ; ")
			% [NumberFormatter.format(ColonyEngine.EXPEDITION_SOLS), NumberFormatter.format(ColonyEngine.EXPEDITION_METHANE)]
			+ Tr.t("elle rapporte des données ou des matériaux, et une fiche de découverte."), "SmallLabel"))
	for site: Dictionary in _engine.region_sites():
		var found := _engine.state.sites_done.has(site.id)
		var title := UiFx.label(("✓ " + Tr.t(site.name)) if found else Tr.t("Site inconnu"), "BodyLabel")
		title.add_theme_color_override("font_color", Palette.SUCCESS if found else Palette.TEXT_DIM)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var row := UiFx.hbox(8, [UiFx.image(UiFx.icon("rover" if found else "target"), 24, Palette.FAME if found else Palette.TEXT_DIM), title])
		if found and not site.card.is_empty():
			var read := Button.new()
			read.text = Tr.t("Fiche")
			read.custom_minimum_size = Vector2(96, 48)
			read.focus_mode = Control.FOCUS_NONE
			read.pressed.connect(func() -> void:
				holder[0].close()
				_show_card.call_deferred(site.card))
			row.add_child(read)
		box.add_child(row)
	if not _engine.state.expedition.is_empty():
		var left: float = _engine.state.expedition.until - _engine.state.sol
		var away := UiFx.paragraph(Tr.t("Le rover est en route vers « %s ». Retour dans %s sol%s.") % [
				Tr.t(_engine.site_by_id(_engine.state.expedition.site).name), NumberFormatter.format(maxf(0.0, left)),
				"s" if left >= 2.0 else ""], "BodyLabel")
		away.add_theme_color_override("font_color", Palette.FAME)
		box.add_child(away)
	else:
		var next := _engine.next_site()
		var problem := _engine.expedition_problem()
		var go := Button.new()
		go.theme_type_variation = "PurpleButton"
		go.text = Tr.t("Partir : %s · %s kg de méthane") % [Tr.t("site inconnu") if next.id != "prospect" else Tr.t(next.name),
				NumberFormatter.format(ColonyEngine.EXPEDITION_METHANE)]
		go.custom_minimum_size = Vector2(0, 64)
		go.focus_mode = Control.FOCUS_NONE
		go.disabled = not problem.is_empty()
		go.pressed.connect(func() -> void:
			if _engine.start_expedition():
				AudioManager.play("rover")
				_news.post(Tr.t("Le rover quitte la colonie. Les colons font coucou par le hublot."))
				holder[0].close())
		box.add_child(go)
		if not problem.is_empty():
			var reason := UiFx.label(problem, "SmallLabel", HORIZONTAL_ALIGNMENT_CENTER)
			reason.add_theme_color_override("font_color", Palette.WARNING)
			box.add_child(reason)
	holder.append(Modal.open(_modal_layer, {
		"icon": "rover", "title": Tr.t("Expéditions"), "extra": box, "confirm_text": Tr.t("Fermer"),
	}))


## Entretien : poussière des panneaux (sortie de nettoyage) et machines en panne (réparations).
func _show_maintenance() -> void:
	var holder: Array[Modal] = []
	var reopen := func() -> void:
		if not holder.is_empty():
			holder[0].close()
		_show_maintenance.call_deferred()
	var box := UiFx.vbox(10)
	var dust := _engine.average_dust()
	box.add_child(UiFx.label(Tr.t("Panneaux solaires"), "HeadingLabel"))
	box.add_child(UiFx.paragraph(Tr.t("Poussière moyenne : %d %%, soit −%d %% d'énergie solaire.") % [roundi(dust * 100.0),
			roundi(ColonyEngine.DUST_LOSS * dust * 100.0)], "BodyLabel"))
	box.add_child(UiFx.paragraph(Tr.t("La poussière se dépose chaque sol, bien plus pendant les tempêtes. Les tourbillons de ")
			+ Tr.t("poussière en balaient parfois quelques-uns, comme pour les rovers Spirit et Opportunity."), "SmallLabel"))
	var problem := _engine.cleaning_problem()
	var clean := Button.new()
	clean.theme_type_variation = "GoldButton"
	clean.text = Tr.t("Sortie de nettoyage · %s kg d'oxygène") % NumberFormatter.format(_engine.cleaning_cost())
	clean.custom_minimum_size = Vector2(0, 64)
	clean.focus_mode = Control.FOCUS_NONE
	clean.disabled = not problem.is_empty()
	clean.pressed.connect(func() -> void:
		if _engine.clean_panels():
			AudioManager.play("clean")
			_news.post(Tr.t("Sortie réussie : les panneaux brillent à nouveau. Les colons, eux, sont couverts de poussière."))
			reopen.call())
	box.add_child(clean)
	if not problem.is_empty():
		var reason := UiFx.label(problem, "SmallLabel", HORIZONTAL_ALIGNMENT_CENTER)
		reason.add_theme_color_override("font_color", Palette.TEXT_MUTED)
		box.add_child(reason)

	box.add_child(UiFx.label("Machines", "HeadingLabel"))
	var any := false
	# Beaucoup de pannes : un seul bouton pour tout réparer (ce que les matériaux permettent).
	if _engine.broken_count() >= 2:
		var all := Button.new()
		all.theme_type_variation = "GoldButton"
		all.text = Tr.t("Tout réparer · %s matériaux") % NumberFormatter.format(_engine.repair_all_cost())
		all.custom_minimum_size = Vector2(0, 64)
		all.focus_mode = Control.FOCUS_NONE
		var affordable := false
		for i in _engine.state.buildings.size():
			affordable = affordable or (_engine.is_broken(i) and _engine.repair_problem(i).is_empty())
		all.disabled = not affordable
		all.pressed.connect(func() -> void:
			var fixed := _engine.repair_all()
			if fixed.is_empty():
				return
			AudioManager.play("build")
			var left := _engine.broken_count()
			_news.post(Tr.t("%d machines réparées.") % fixed.size() if left == 0
					else Tr.t("%d machines réparées ; il manque des matériaux pour les %d autres.") % [fixed.size(), left])
			reopen.call())
		box.add_child(all)
		if not affordable:
			var short := UiFx.label(Tr.t("Pas assez de matériaux."), "SmallLabel", HORIZONTAL_ALIGNMENT_CENTER)
			short.add_theme_color_override("font_color", Palette.TEXT_MUTED)
			box.add_child(short)
	for i in _engine.state.buildings.size():
		if not _engine.is_broken(i):
			continue
		any = true
		var name := UiFx.label(_engine.def_of(i).name, "BodyLabel")
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var fix := Button.new()
		fix.theme_type_variation = "GoldButton"
		fix.text = Tr.t("Réparer · %s") % NumberFormatter.format(_engine.repair_cost(i)[ColonyContent.MATERIALS])
		fix.custom_minimum_size = Vector2(170, 56)
		fix.focus_mode = Control.FOCUS_NONE
		fix.disabled = not _engine.repair_problem(i).is_empty()
		fix.pressed.connect(func() -> void:
			if _engine.repair(i):
				AudioManager.play("repair")
				var fixer := _repairer()
				if not fixer.is_empty():
					_news.post(Tr.t(ColonyContent.REPAIR_LINE) % [fixer, Tr.t(_engine.def_of(i).name)])
				reopen.call())
		box.add_child(UiFx.hbox(8, [UiFx.image(UiFx.icon("warning"), 24, Palette.WARNING), name, fix]))
	if not any:
		var fine := UiFx.paragraph(Tr.t("Aucune panne : tout tourne. Les machines lâchent de temps en temps ; une réparation coûte ")
				+ Tr.t("30 % de leur prix en matériaux."), "SmallLabel")
		fine.add_theme_color_override("font_color", Palette.SUCCESS)
		box.add_child(fine)
	holder.append(Modal.open(_modal_layer, {
		"icon": "gear", "title": Tr.t("Entretien"), "extra": box, "confirm_text": Tr.t("Fermer"),
	}))


## Niveau d'un module, améliorations faites et prochaine amélioration (avec son pourquoi).
func _upgrade_block(index: int, holder: Array[Modal]) -> Control:
	var box := UiFx.vbox(6)
	var top := _engine.max_level(index)
	if top <= 1:
		return box
	var level := _engine.level_of(index)
	var caption := UiFx.label(Tr.t("NIVEAU %d / %d   %s") % [level, top, "★".repeat(level) + "☆".repeat(top - level)], "CaptionLabel")
	caption.add_theme_color_override("font_color", Palette.MONEY)
	box.add_child(caption)
	var upgrades: Array = ColonyContent.UPGRADES[_engine.state.buildings[index].id]
	for i in level - 1:
		var done := UiFx.paragraph(Tr.t("✓ %s : %s") % [Tr.t(upgrades[i].name), Tr.t(upgrades[i].effect)], "SmallLabel")
		done.add_theme_color_override("font_color", Palette.SUCCESS)
		box.add_child(done)
	var next := _engine.next_upgrade(index)
	if next.is_empty():
		return box
	var title := UiFx.label(Tr.t("Amélioration : ") + Tr.t(next.name), "HeadingLabel")
	var effect := UiFx.label(next.effect, "BodyLabel")
	effect.add_theme_color_override("font_color", Palette.ACCENT)
	box.add_child(title)
	box.add_child(effect)
	box.add_child(UiFx.paragraph(next.why, "SmallLabel"))
	var cost := _engine.upgrade_cost(index)
	var problem := _engine.upgrade_problem(index)
	var button := Button.new()
	button.theme_type_variation = "GoldButton"
	button.text = Tr.t("Améliorer · %s matériaux · %s données") % [NumberFormatter.format(cost[ColonyContent.MATERIALS]),
			NumberFormatter.format(cost[ColonyContent.DATA])]
	button.custom_minimum_size = Vector2(0, 64)
	button.focus_mode = Control.FOCUS_NONE
	button.disabled = not problem.is_empty()
	button.pressed.connect(func() -> void:
		if not _engine.upgrade(index):
			AudioManager.play("fail")
			UiFx.shake(button)
			return
		AudioManager.play("upgrade")
		UiFx.float_text(Tr.t("Niveau %d !") % _engine.level_of(index), button.get_global_rect().get_center(), Palette.MONEY)
		if not holder.is_empty():
			holder[0].close()
		_show_building.call_deferred(index))
	box.add_child(button)
	if not problem.is_empty():
		var reason := UiFx.label(problem, "SmallLabel", HORIZONTAL_ALIGNMENT_CENTER)
		reason.add_theme_color_override("font_color", Palette.WARNING)
		box.add_child(reason)
	return box


## Synergies d'un module dans sa fiche : actives (dorées, avec le pourquoi) ou possibles.
## Fiche d'un module à construire (toucher sa ligne dans l'onglet Construire) : à quoi il sert,
## ce qu'il produit et consomme, ses synergies, puis « Placer ».
func _show_build_info(def_id: String) -> void:
	var def: Defs.Building = _engine.building_defs[def_id]
	var lines: Array[String] = []
	for r: String in def.outputs:
		lines.append(Tr.t("+%s %s %s/sol") % [NumberFormatter.format(def.outputs[r]), Tr.t(ColonyContent.RESOURCE_UNITS[r]), Tr.t(ColonyContent.RESOURCE_NAMES[r]).to_lower()])
	for r: String in def.inputs:
		lines.append(Tr.t("−%s %s %s/sol") % [NumberFormatter.format(def.inputs[r]), Tr.t(ColonyContent.RESOURCE_UNITS[r]), Tr.t(ColonyContent.RESOURCE_NAMES[r]).to_lower()])
	if def.solar:
		lines.append(Tr.t("(selon le soleil : rien la nuit, peu en tempête)"))
	for r: String in def.storage:
		lines.append(Tr.t("Stockage : +%s %s %s") % [NumberFormatter.format(def.storage[r]), Tr.t(ColonyContent.RESOURCE_UNITS[r]), Tr.t(ColonyContent.RESOURCE_NAMES[r]).to_lower()])
	if def.housing > 0:
		lines.append(Tr.t("Loge %d colons") % def.housing)
	lines.append(Tr.t("Taille : %d × %d cases · %s matériaux") % [def.size.x, def.size.y, NumberFormatter.format(def.cost)])
	var extra := UiFx.vbox(8, [UiFx.panel("Thumb", UiFx.building_icon(def.id, Vector2(200, 160))),
			UiFx.paragraph("\n".join(lines), "BodyLabel", HORIZONTAL_ALIGNMENT_CENTER)])
	(extra.get_child(0) as Control).size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	for synergy: Dictionary in ColonyContent.SYNERGIES:
		if synergy.building != def_id and synergy.neighbor != def_id:
			continue
		var other: String = synergy.neighbor if synergy.building == def_id else synergy.building
		var bonus := UiFx.paragraph(Tr.t("✦ Collé à : %s → %s") % [Tr.t(_engine.building_defs[other].name), Tr.t(synergy.effect)], "SmallLabel", HORIZONTAL_ALIGNMENT_CENTER)
		bonus.add_theme_color_override("font_color", SYNERGY_COLOR)
		extra.add_child(bonus)
	var holder: Array[Modal] = []
	if not def.card.is_empty() and _engine.state.cards_unlocked.has(def.card):
		var learn := Button.new()
		learn.text = Tr.t("En savoir plus : ") + Tr.t(_engine.cards[def.card].title)
		learn.focus_mode = Control.FOCUS_NONE
		learn.clip_text = true
		learn.pressed.connect(func() -> void:
			holder[0].close()
			_show_card.call_deferred(def.card))
		extra.add_child(learn)
	var options := { "icon": "tab_build", "title": Tr.t(def.name), "body": def.description, "extra": extra }
	var unlocked := _engine.is_unlocked(def)
	var affordable := _engine.state.amount(ColonyContent.MATERIALS) >= def.cost
	if unlocked and affordable:
		options.confirm_text = Tr.t("Placer")
		options.confirm_style = "GoldButton"
		options.on_confirm = func() -> void: _start_placement.call_deferred(def_id)
		options.cancel_text = Tr.t("Fermer")
	else:
		var why := UiFx.paragraph(Tr.t("Pas assez de matériaux.") if unlocked
				else Tr.t("Recherche nécessaire : %s") % Tr.t(_engine.research_defs[def.research].name), "SmallLabel", HORIZONTAL_ALIGNMENT_CENTER)
		why.add_theme_color_override("font_color", Palette.WARNING)
		extra.add_child(why)
		options.confirm_text = Tr.t("Fermer")
	holder.append(Modal.open(_modal_layer, options))


func _synergy_block(index: int) -> Control:
	var box := UiFx.vbox(6)
	var active := _engine.synergies_of(index)
	for synergy: Dictionary in active:
		var title := UiFx.label(Tr.t("✦ %s : %s") % [Tr.t(synergy.name), Tr.t(synergy.effect)], "BodyLabel")
		title.add_theme_color_override("font_color", SYNERGY_COLOR)
		box.add_child(title)
		box.add_child(UiFx.paragraph(synergy.why, "SmallLabel"))
	var possible: Array[String] = []
	var id: String = _engine.state.buildings[index].id
	for synergy: Dictionary in ColonyContent.SYNERGIES:
		if synergy.building == id and not active.has(synergy):
			possible.append(Tr.t("collé à : %s → %s") % [Tr.t(_engine.building_defs[synergy.neighbor].name), Tr.t(synergy.effect)])
	if not possible.is_empty():
		var hint := UiFx.paragraph(Tr.t("Synergie possible si ") + Tr.t(", ou ").join(possible) + ".", "SmallLabel")
		hint.add_theme_color_override("font_color", Palette.TEXT_MUTED)
		box.add_child(hint)
	return box


## Toutes les synergies : quels modules coller, quel effet, et pourquoi.
func _show_synergies() -> void:
	var list := UiFx.vbox(6)
	for synergy: Dictionary in ColonyContent.SYNERGIES:
		var pair := Tr.t("%s + %s") % [Tr.t(_engine.building_defs[synergy.building].name), Tr.t(_engine.building_defs[synergy.neighbor].name)]
		var title := UiFx.label("✦ " + Tr.t(synergy.name), "HeadingLabel")
		title.add_theme_color_override("font_color", SYNERGY_COLOR)
		var effect := UiFx.paragraph(Tr.t("%s → %s") % [pair, Tr.t(synergy.effect)], "SmallLabel")
		# L'explication scientifique se déplie au toucher.
		list.add_child(Foldable.new(UiFx.vbox(2, [title, effect]), UiFx.paragraph(synergy.why, "SmallLabel")))
	Modal.open(_modal_layer, {
		"icon": "tab_build", "title": Tr.t("Synergies"),
		"body": Tr.t("Collez ces modules l'un contre l'autre (sans conduite entre eux). Active : %d.") % _engine.active_synergy_count(),
		"extra": list, "confirm_text": Tr.t("Fermer"),
	})


## Écran de découverte plein écran, une fiche à la fois.
func _queue_discovery(card_id: String) -> void:
	if not _discoveries.has(card_id):
		_discoveries.append(card_id)
	_next_discovery.call_deferred()


func _next_discovery() -> void:
	if _discovery != null or _discoveries.is_empty():
		return
	var card: Defs.Card = _engine.cards[_discoveries.pop_front()]
	_discovery = DiscoveryScreen.open(_modal_layer, card)
	_discovery.read_requested.connect(_show_card)
	_discovery.closed.connect(func() -> void:
		_discovery = null
		_next_discovery.call_deferred())


func _show_card(card_id: String) -> void:
	var card: Defs.Card = _engine.cards[card_id]
	var status := UiFx.label(Tr.t(card.status).to_upper(), "CaptionLabel")
	status.add_theme_color_override("font_color", Palette.STATUS_COLORS.get(card.status, Palette.TEXT_MUTED))
	var figure := UiFx.label(card.figure, "NumberLabel")
	figure.add_theme_font_size_override("font_size", 40)
	figure.add_theme_color_override("font_color", Palette.MONEY)
	var figure_label := UiFx.paragraph(card.figure_label, "SmallLabel")
	var head_text := UiFx.vbox(2, [status, figure, figure_label])
	head_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_text.alignment = BoxContainer.ALIGNMENT_CENTER
	var head := UiFx.hbox(12, [UiFx.panel("Thumb", UiFx.building_icon(card.visual, Vector2(150, 120))), head_text])

	var in_game := UiFx.paragraph(Tr.t("Dans le jeu : ") + Tr.t(card.in_game), "SmallLabel")
	in_game.add_theme_color_override("font_color", Palette.ACCENT)
	var content := UiFx.vbox(12, [head, UiFx.paragraph(card.fact, "BodyLabel"), in_game])
	if not card.quiz.is_empty():
		content.add_child(_quiz_block(card))
	content.add_child(UiFx.label("Sources", "CaptionLabel"))
	for source: Array in card.sources:
		var link := LinkButton.new()
		link.text = source[0]
		link.uri = source[1]
		link.add_theme_color_override("font_color", Palette.FAME)
		link.add_theme_font_size_override("font_size", 18)
		content.add_child(link)
	Modal.open(_modal_layer, {
		"icon": "tab_knowledge", "title": card.title, "extra": content, "confirm_text": Tr.t("Fermer"),
	})
	var reward := _engine.read_card(card_id)
	if reward > 0.0:
		AudioManager.play("upgrade")
		UiFx.float_text(Tr.t("+%d données") % int(reward), Vector2(size.x / 2.0, size.y * 0.5), Palette.resource_color(ColonyContent.DATA))


## Quiz d'une fiche : trois choix, une seule tentative, des données pour la bonne réponse.
func _quiz_block(card: Defs.Card) -> Control:
	var caption := UiFx.label(Tr.t("QUIZ · +%d données") % int(ColonyEngine.QUIZ_REWARD), "CaptionLabel")
	caption.add_theme_color_override("font_color", Palette.ACCENT)
	var feedback := UiFx.paragraph("", "SmallLabel")
	var box := UiFx.vbox(8, [caption, UiFx.paragraph(card.quiz, "HeadingLabel")])
	var buttons: Array[Button] = []
	for i in card.choices.size():
		var choice := Button.new()
		choice.text = card.choices[i]
		choice.custom_minimum_size = Vector2(0, 56)
		choice.focus_mode = Control.FOCUS_NONE
		choice.clip_text = true
		buttons.append(choice)
		box.add_child(choice)
	box.add_child(feedback)
	var show_result := func(picked: int) -> void:
		for i in buttons.size():
			buttons[i].mouse_filter = Control.MOUSE_FILTER_IGNORE
			if i == card.answer:
				buttons[i].theme_type_variation = "GreenButton"
				buttons[i].text = "✓  " + Tr.t(card.choices[i])
			elif i == picked:
				buttons[i].text = "✗  " + Tr.t(card.choices[i])
				buttons[i].modulate = Color(1.0, 0.55, 0.5)
			else:
				buttons[i].modulate.a = 0.5
		var good: bool = _engine.state.quiz_answers.get(card.id, false)
		feedback.text = (Tr.t("Bonne réponse ! +%d données.") % int(ColonyEngine.QUIZ_REWARD) if good
				else Tr.t("Raté : la bonne réponse est « %s ».") % Tr.t(card.choices[card.answer]))
		feedback.add_theme_color_override("font_color", Palette.SUCCESS if good else Palette.WARNING)
	if _engine.state.quiz_answers.has(card.id):
		show_result.call(-1)
		if _engine.state.quiz_answers[card.id]:
			feedback.text = Tr.t("Quiz réussi ✓")
	else:
		for i in buttons.size():
			buttons[i].pressed.connect(func() -> void:
				var good := _engine.answer_quiz(card.id, i)
				AudioManager.play("quiz_right" if good else "quiz_wrong")
				show_result.call(i)
				if good:
					UiFx.float_text(Tr.t("+%d données") % int(ColonyEngine.QUIZ_REWARD), buttons[i].get_global_rect().get_center(),
							Palette.resource_color(ColonyContent.DATA))
				else:
					UiFx.shake(buttons[i]))
	return box


func _show_resource(resource: String) -> void:
	var flows := _engine.average_flows(true)
	var lines: Array[String] = []
	var unit: String = ColonyContent.RESOURCE_UNITS[resource]
	# Mêmes débits que le bandeau (ColonyEngine.building_flows), regroupés par type de module.
	var by_type := {}
	for i in _engine.state.buildings.size():
		var amount: float = _engine.building_flows(i, true).get(resource, 0.0)
		if absf(amount) > 0.005:
			var name := _engine.def_of(i).name
			by_type[name] = by_type.get(name, 0.0) + amount
	for name: String in by_type:
		lines.append(Tr.t("%s : %s%s %s/sol") % [Tr.t(name), "+" if by_type[name] > 0.0 else "−", NumberFormatter.format(absf(by_type[name])), unit])
	var needs := _engine.colonist_needs()
	if needs.has(resource):
		lines.append(Tr.t("Colons (%d) : −%s %s/sol") % [_engine.state.colonists.size(),
				NumberFormatter.format(needs[resource] * _engine.state.colonists.size()), unit])
	if resource == ColonyContent.DATA:
		lines.append(Tr.t("Colons (%d) : +%s/sol") % [_engine.state.colonists.size(), NumberFormatter.format(ColonyContent.COLONIST_DATA * _engine.state.colonists.size())])
	var capacity := _engine.capacity(resource)
	var stock := Tr.t("%s %s") % [NumberFormatter.format(_engine.state.amount(resource)), unit]
	if not is_inf(capacity):
		stock += Tr.t(" / %s") % NumberFormatter.format(capacity)
	var flow: float = flows[resource]
	Modal.open(_modal_layer, {
		"icon": resource,
		"title": ColonyContent.RESOURCE_NAMES[resource],
		"body": ColonyContent.RESOURCE_HELP[resource],
		"extra": UiFx.vbox(6, [
			UiFx.label(Tr.t("Réserve : ") + stock, "HeadingLabel", HORIZONTAL_ALIGNMENT_CENTER),
			UiFx.label(Tr.t("Bilan moyen : %s%s %s/sol") % ["+" if flow >= 0.0 else "", NumberFormatter.format(flow), unit],
					"IncomeLabel" if flow >= 0.0 else "BodyLabel", HORIZONTAL_ALIGNMENT_CENTER),
			UiFx.paragraph("\n".join(lines) if not lines.is_empty() else Tr.t("Aucun module ne produit ni ne consomme cette ressource."),
					"SmallLabel", HORIZONTAL_ALIGNMENT_CENTER),
		]),
		"confirm_text": Tr.t("Fermer"),
	})


func _show_offline_report(report: Dictionary) -> void:
	var box := UiFx.vbox(10)
	var lines: Array[String] = []
	for r in ColonyContent.RESOURCES:
		var delta: float = report.gains.get(r, 0.0)
		if absf(delta) >= 0.5:
			lines.append(Tr.t("%s : %s%s") % [Tr.t(ColonyContent.RESOURCE_NAMES[r]), "+" if delta > 0.0 else "", NumberFormatter.format(delta)])
	if not lines.is_empty():
		box.add_child(_report_section(Tr.t("Production"), "  ·  ".join(lines)))
	var done: Array[String] = []
	for id: String in report.get("research", []):
		done.append("✓ " + Tr.t(_engine.research_defs[id].name))
	for id: String in report.get("objectives", []):
		for o in _engine.objectives:
			if o.id == id:
				done.append("★ " + Tr.t(o.title))
	if not done.is_empty():
		box.add_child(_report_section(Tr.t("Terminé"), "\n".join(done), Palette.SUCCESS))
	var full: Array = report.get("full", [])
	if not full.is_empty():
		var names: Array[String] = []
		for r: String in full:
			names.append(Tr.t(ColonyContent.RESOURCE_NAMES[r]))
		box.add_child(_report_section(Tr.t("Réserves pleines"), Tr.t("%s : le surplus a été perdu. Plus de stockage, ou de quoi l'utiliser ?") % ", ".join(names), Palette.WARNING))
	box.add_child(_report_section(Tr.t("Et maintenant ?"), _next_step_hint(), Palette.ACCENT))
	var body := Tr.t("Absence : %s. La colonie a tourné en pilote automatique pendant %s sol%s, sans tempête ni danger.") % [
		NumberFormatter.duration(report.elapsed), NumberFormatter.format(report.sols), "s" if report.sols >= 2.0 else ""]
	if not report.standby.is_empty():
		body += Tr.t("\n\nVeille sécurisée déclenchée : la réserve %s allait s'épuiser. %s") % [
			Tr.t(ColonyContent.RESOURCE_PARTITIVE[report.standby]), Tr.t(ColonyEngine.CAUSES.get(report.standby, ""))]
		body += Tr.t("\n\nLe temps est en pause : construisez ce qui manque, puis relancez-le.")
	Modal.open(_modal_layer, {
		"icon": "clock", "title": Tr.t("Pendant votre absence"), "body": body, "extra": box,
		"confirm_text": "Reprendre",
	})


func _report_section(title: String, text: String, color := Palette.TEXT) -> Control:
	var caption := UiFx.label(title.to_upper(), "CaptionLabel")
	caption.add_theme_color_override("font_color", color)
	return UiFx.vbox(2, [caption, UiFx.paragraph(text, "SmallLabel")])


## Le conseil le plus utile au retour : l'alerte la plus urgente, sinon l'objectif ou un défi,
## sinon les modules qu'on peut s'offrir.
func _next_step_hint() -> String:
	var alerts := ColonyAdvisor.alerts(_engine)
	if not alerts.is_empty():
		return "%s. %s" % [alerts[0].title, alerts[0].advice]
	var challenge := _engine.current_challenge()
	if not challenge.is_empty():
		return Tr.t("Défi en cours : %s. %s") % [Tr.t(challenge.title), Tr.t(challenge.text)]
	var affordable: Array[String] = []
	for def in _engine.buildable_defs():
		if _engine.is_unlocked(def) and def.id != "link" and def.cost <= _engine.state.amount(ColonyContent.MATERIALS):
			affordable.append(Tr.t(def.name))
	if not affordable.is_empty():
		return Tr.t("Matériaux suffisants pour : %s.") % ", ".join(affordable.slice(0, 4))
	var objective := _engine.current_objective()
	return Tr.t("Objectif : %s.") % Tr.t(objective.title) if objective != null else Tr.t("Tout tourne. Bon retour, commandant !")


## Menu du jeu (bouton à trois barres) : mode photo, réglages, aide, retour au menu principal.
func _show_settings() -> void:
	# Partagée avec les boutons, créés avant la fenêtre (voir DESIGN.md, Pièges).
	var holder: Array[Modal] = []
	var entry := func(icon_name: String, text: String, action: Callable) -> Button:
		var button := Button.new()
		button.text = text
		button.icon = UiFx.icon(icon_name)
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 26)
		button.add_theme_constant_override("h_separation", 14)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size.y = 64
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(func() -> void:
			AudioManager.play("click")
			holder[0].close()
			action.call_deferred())
		return button
	var box := UiFx.vbox(10, [
		entry.call("camera", Tr.t("Mode photo"), _show_photo_mode),
		entry.call("gear", Tr.t("Réglages"), _show_options),
		entry.call("tab_knowledge", Tr.t("Comment jouer"), _show_help),
		entry.call("close", Tr.t("Menu principal"), GameManager.open_menu),
		UiFx.label(Tr.t("La partie est sauvegardée automatiquement."), "CaptionLabel", HORIZONTAL_ALIGNMENT_CENTER),
	])
	holder.append(Modal.open(_modal_layer, {
		"icon": "menu", "title": Tr.t("Menu"), "extra": box, "confirm_text": Tr.t("Reprendre"),
	}))


func _show_options() -> void:
	Modal.open(_modal_layer, {
		"icon": "gear", "title": Tr.t("Réglages"), "extra": SettingsPanel.build(), "confirm_text": Tr.t("Fermer"),
	})


func _show_help() -> void:
	Modal.open(_modal_layer, {
		"icon": "tab_knowledge", "title": Tr.t("Comment jouer"),
		"body": Tr.t("Glissez pour parcourir le cratère, pincez (ou molette) pour zoomer.\n")
			+ Tr.t("Touchez un module pour le détail, une ressource pour son explication.\n")
			+ Tr.t("Hors-ligne : pilote automatique prudent, 8 h au plus, sans tempête."),
		"confirm_text": Tr.t("Fermer"),
	})


func _show_load_problem() -> void:
	match GameManager.load_result:
		SaveService.LoadResult.RESTORED_FROM_BACKUP:
			_news.post(Tr.t("Sauvegarde restaurée depuis la copie de secours."))
		SaveService.LoadResult.CORRUPTED:
			Modal.open(_modal_layer, {
				"icon": "warning", "title": Tr.t("Sauvegarde illisible"),
				"body": Tr.t("Une nouvelle colonie commence. L'ancien fichier a été conservé à part et ne sera pas effacé."),
				"confirm_text": Tr.t("Compris"),
			})


# ---------- Décisions et colons ----------

## Décision en attente : deux choix, chacun avec ce qu'il coûte et rapporte. « Plus tard » la garde
## dans le bandeau d'alerte jusqu'à l'échéance.
func _show_dilemma() -> void:
	var def := _engine.pending_dilemma()
	if def.is_empty():
		return
	for modal in _modal_layer.get_children():
		if modal.has_meta("dilemma") and not modal._closing:
			return
	var holder: Array[Modal] = []
	var box := UiFx.vbox(10)
	for i in def.choices.size():
		var option: Dictionary = def.choices[i]
		var button := Button.new()
		button.text = Tr.t(option.label)
		button.theme_type_variation = "GoldButton" if i == 0 else "Button"
		button.custom_minimum_size = Vector2(0, 60)
		button.focus_mode = Control.FOCUS_NONE
		var problem := _engine.dilemma_problem(i)
		button.disabled = not problem.is_empty()
		var outcome := UiFx.paragraph(Tr.t(option.outcome) if problem.is_empty() else problem, "SmallLabel", HORIZONTAL_ALIGNMENT_CENTER)
		outcome.add_theme_color_override("font_color", Palette.TEXT_MUTED if problem.is_empty() else Palette.WARNING)
		button.pressed.connect(func() -> void:
			var report := _engine.resolve_dilemma(i)
			if report.is_empty():
				return
			AudioManager.play("click")
			holder[0].close()
			Modal.open(_modal_layer, {
				"icon": "check", "title": Tr.t(def.title), "body": report.text, "confirm_text": Tr.t("Compris"),
			}))
		box.add_child(UiFx.vbox(4, [button, outcome]))
	var left := maxf(0.0, float(_engine.state.dilemma.until) - _engine.state.sol)
	var deadline := UiFx.label(Tr.t("Sans réponse dans %s sol%s : « %s ».") % [NumberFormatter.format(left), "s" if left >= 2.0 else "",
			Tr.t(def.choices[_engine.default_choice()].label)], "CaptionLabel", HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(deadline)
	var modal := Modal.open(_modal_layer, {
		"icon": "storm" if _engine.state.dilemma.id == "storm_shelter" else "warning",
		"title": Tr.t(def.title), "body": _engine.dilemma_text(), "extra": box,
		"confirm_text": Tr.t("Plus tard"), "confirm_style": "Button",
	})
	modal.set_meta("dilemma", true)
	holder.append(modal)


## Prénom du colon qui répare : de préférence un profil technique.
func _repairer() -> String:
	var colonists := _engine.state.colonists
	if colonists.is_empty():
		return ""
	for c in colonists:
		var role := str(c.role)
		if role.begins_with("ingén") or role.begins_with("mécan") or role.begins_with("électri") or role.begins_with("soud"):
			if randf() < 0.7:
				return c.name
	return colonists[randi() % colonists.size()].name


## Réplique d'un colon selon la situation, ou selon son métier ("" sans colon).
func _colonist_line() -> String:
	var colonists := _engine.state.colonists
	if colonists.is_empty():
		return ""
	var colonist: Dictionary = colonists[randi() % colonists.size()]
	var moods: Array[String] = []
	if _engine.is_storm():
		moods.append("storm")
	if _engine.is_aurora():
		moods.append("aurora")
	if _engine.broken_count() > 0:
		moods.append("broken")
	if _engine.state.colonists.size() >= _engine.housing() and _engine.housing() > 0:
		moods.append("crowded")
	if _engine.is_night() and _engine.planet_id() == "mars":
		moods.append("night")
	var lines: Array = []
	if not moods.is_empty() and randf() < 0.6:
		lines = ColonyContent.MOOD_LINES[moods[randi() % moods.size()]]
	else:
		lines = _role_lines(str(colonist.role))
		if lines.is_empty():
			lines = ColonyContent.MOOD_LINES.happy
	return Tr.t(lines[randi() % lines.size()]) % colonist.name


static func _role_lines(role: String) -> Array:
	for key: String in ColonyContent.ROLE_LINES:
		if role.begins_with(key):
			return ColonyContent.ROLE_LINES[key]
	return []


## Fiche d'un colon touché dans la vue 3D : prénom, métier, santé, une réplique.
func _show_colonist(index: int) -> void:
	if index < 0 or index >= _engine.state.colonists.size():
		return
	var colonist: Dictionary = _engine.state.colonists[index]
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size.y = 14
	bar.value = colonist.health * 100.0
	bar.theme_type_variation = "ProgressBar" if colonist.health > 0.5 else "MilestoneBar"
	var lines := _role_lines(str(colonist.role))
	var quote := Tr.t(lines[randi() % lines.size()]) % colonist.name if not lines.is_empty() else ""
	var health := UiFx.label(Tr.t("Santé : %d %%") % roundi(colonist.health * 100.0), "SmallLabel", HORIZONTAL_ALIGNMENT_CENTER)
	var extra := UiFx.vbox(8, [health, bar])
	if not quote.is_empty():
		extra.add_child(UiFx.paragraph(quote, "BodyLabel", HORIZONTAL_ALIGNMENT_CENTER))
	Modal.open(_modal_layer, {
		"icon": "person", "title": Tr.t("%s, %s") % [colonist.name, Tr.t(colonist.role)], "extra": extra,
		"confirm_text": Tr.t("Fermer"),
	})


# ---------- Mode photo ----------

## Mode photo : l'interface disparaît, on fait tourner la caméra autour de la colonie, et le ciel
## du monde apparaît (Jupiter, Saturne, la Terre, les étoiles). Le temps continue de passer.
func _show_photo_mode() -> void:
	if _photo_bar != null:
		return
	if not _placing.is_empty():
		_stop_placement()
	_world.set_photo_mode(true)
	_safe_area.visible = false
	get_viewport().scaling_3d_scale = _world.render_scale(true)
	var hint := UiFx.label(Tr.t("Glissez pour tourner, pincez pour zoomer."), "SmallLabel", HORIZONTAL_ALIGNMENT_CENTER)
	hint.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	hint.add_theme_constant_override("shadow_offset_y", 2)
	var close := Button.new()
	close.text = Tr.t("Fermer")
	close.custom_minimum_size = Vector2(180, 64)
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func() -> void:
		AudioManager.play("click")
		_close_photo_mode())
	var shoot := Button.new()
	shoot.text = Tr.t("Prendre la photo")
	shoot.icon = UiFx.icon("camera")
	shoot.expand_icon = false
	shoot.add_theme_constant_override("icon_max_width", 28)
	shoot.theme_type_variation = "GoldButton"
	shoot.custom_minimum_size = Vector2(280, 64)
	shoot.focus_mode = Control.FOCUS_NONE
	shoot.pressed.connect(_take_photo)
	var row := UiFx.hbox(12, [close, shoot])
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var bar := UiFx.vbox(8, [hint, row])
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -170
	bar.offset_bottom = -40
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)
	move_child(bar, _modal_layer.get_index())
	_photo_bar = bar


func _close_photo_mode() -> void:
	if _photo_bar == null:
		return
	_photo_bar.queue_free()
	_photo_bar = null
	_world.set_photo_mode(false)
	_safe_area.visible = true
	get_viewport().scaling_3d_scale = _world.render_scale()
	_layout_changed()


## Capture de l'écran sans l'interface, enregistrée dans les images de l'appareil (dossier
## « Ares Colony »), sinon dans les données du jeu.
func _take_photo() -> void:
	if _photo_bar == null:
		return
	_photo_bar.visible = false
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if _photo_bar == null:
		return
	_photo_bar.visible = true
	AudioManager.play("click")
	var path := save_photo(image)
	var flash := ColorRect.new()
	flash.color = Color(1, 1, 1, 0.8)
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flash)
	flash.create_tween().tween_property(flash, "color:a", 0.0, 0.35).finished.connect(flash.queue_free)
	var where := Tr.t("Photo enregistrée")
	if "/Download" in path:
		where = Tr.t("Photo enregistrée dans Téléchargements › Ares Colony")
	elif not path.begins_with("user://"):
		where = Tr.t("Photo enregistrée dans Images › Ares Colony")
	UiFx.float_text(where, Vector2(size.x / 2.0, size.y * 0.45), Palette.TEXT, 24)


## Enregistre une image ; retourne son chemin ("" en cas d'échec).
static func save_photo(image: Image) -> String:
	var name := "ares_colony_%s.jpg" % Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	# Encodée une seule fois. Android ne laisse un jeu écrire que dans Téléchargements ou Documents
	# (la galerie y voit les images) ; sinon, dans les données du jeu.
	var data := image.save_jpg_to_buffer(0.92)
	var folders: Array[String] = []
	for dir in [OS.SYSTEM_DIR_DOWNLOADS, OS.SYSTEM_DIR_PICTURES, OS.SYSTEM_DIR_DOCUMENTS]:
		var system := OS.get_system_dir(dir)
		if not system.is_empty():
			folders.append(system.path_join("Ares Colony"))
	folders.append("user://photos")
	for folder in folders:
		if not DirAccess.dir_exists_absolute(folder) and DirAccess.make_dir_recursive_absolute(folder) != OK:
			continue
		var path := folder.path_join(name)
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file != null:
			file.store_buffer(data)
			file.close()
			if FileAccess.get_open_error() == OK:
				return path
		if OS.is_debug_build():
			print("Photo : %s refusé (%d)" % [path, FileAccess.get_open_error()])
	return ""
