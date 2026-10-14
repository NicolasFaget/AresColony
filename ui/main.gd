extends Control
## Écran principal : le cratère en 3D, le bandeau des ressources en haut, le panneau à onglets
## et les actualités en bas, le mode placement, les fenêtres d'information.
## Il affiche ce que ColonyEngine expose et ne calcule rien lui-même.

const MARGIN := 10
const WINDOW_SHARE := 0.42
const TAP_SLOP := 12.0
## Un message d'ambiance tous les ~1,5 sol de jeu.
const CHATTER_EVERY := 1.5

var _engine: ColonyEngine
var _world: ColonyWorld
var _status: StatusPanel
var _alert: AlertBanner
var _coach: CoachCard
var _window: GameWindow
var _news: NewsTicker
var _safe_area: MarginContainer
var _pages: Array[Page] = []
var _research_page: ResearchPage
var _modal_layer: Control
var _current_page := 0

# Mode placement.
var _placement_bar: PanelContainer
var _placement_title: Label
var _placement_reason: Label
var _placement_confirm: Button
var _placing := ""

# Gestes sur le monde.
var _touches := {}
var _press_position := Vector2.ZERO
var _dragged := false
var _pinch_distance := 0.0
var _next_chatter := 2.0


func _ready() -> void:
	_engine = GameManager.engine
	theme = AppTheme.build()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Mobile : la 3D est calculée en plus basse résolution puis agrandie (l'interface reste nette).
	if OS.has_feature("mobile"):
		get_viewport().scaling_3d_scale = 0.55
	add_child(IconStudio.new())
	_world = ColonyWorld.new()
	add_child(_world)
	_world.cell_tapped.connect(_on_cell_tapped)
	_world.ghost_moved.connect(func(_c: Vector2i) -> void: _refresh_placement())
	_build_layout()
	_connect_engine()

	GameManager.state_changed.connect(_refresh)
	GameManager.offline_report.connect(_show_offline_report)
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
	_status.resource_requested.connect(_show_resource)
	root.add_child(_status)
	_alert = AlertBanner.new()
	_alert.action_requested.connect(_go_to)
	root.add_child(_alert)
	var spacer := UiFx.spacer()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(spacer)
	_coach = CoachCard.new()
	_coach.show_requested.connect(_go_to)
	_coach.skip_requested.connect(func() -> void:
		_engine.state.tutorial_done = true
		_news.post("Guide masqué. Les alertes restent là pour vous prévenir.")
		_refresh())
	root.add_child(_coach)

	root.add_child(_build_placement_bar())

	_window = GameWindow.new()
	_window.tab_selected.connect(_show_page)
	_window.collapsed_changed.connect(func(_c: bool) -> void: _layout_changed.call_deferred())
	root.add_child(_window)

	var build := BuildPage.new()
	build.place_requested.connect(_start_placement)
	var colony := ColonyPage.new()
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

	_news = NewsTicker.new()
	root.add_child(_news)

	var fx := Control.new()
	fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fx)
	UiFx.fx_layer = fx

	_modal_layer = Control.new()
	_modal_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_modal_layer)


func _build_placement_bar() -> Control:
	_placement_title = UiFx.label("", "HeadingLabel")
	_placement_reason = UiFx.paragraph("", "SmallLabel")
	var cancel := Button.new()
	cancel.text = "Terminer"
	cancel.custom_minimum_size = Vector2(0, 68)
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.pressed.connect(func() -> void:
		AudioManager.play("click")
		_stop_placement())
	_placement_confirm = Button.new()
	_placement_confirm.theme_type_variation = "GoldButton"
	_placement_confirm.text = "Construire ici"
	_placement_confirm.custom_minimum_size = Vector2(0, 68)
	_placement_confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_placement_confirm.focus_mode = Control.FOCUS_NONE
	_placement_confirm.pressed.connect(_confirm_placement)
	_placement_bar = UiFx.panel("WindowPanel", UiFx.vbox(8, [
		_placement_title, _placement_reason, UiFx.hbox(10, [cancel, _placement_confirm])]))
	_placement_bar.visible = false
	return _placement_bar


func _connect_engine() -> void:
	_engine.research_completed.connect(_on_research_completed)
	_engine.objective_completed.connect(_on_objective_completed)
	_engine.card_unlocked.connect(func(id: String) -> void:
		if id == "storm":
			_news.post("Nouvelle fiche dans l'encyclopédie : %s" % _engine.cards[id].title))
	_engine.storm_warning.connect(func() -> void:
		AudioManager.play("alert")
		_news.post("Les satellites annoncent une tempête de poussière : remplissez les batteries !"))
	_engine.storm_started.connect(func() -> void:
		AudioManager.play("alert")
		GameManager.vibrate(40)
		_news.post("Tempête de poussière ! Les panneaux solaires ne reçoivent plus que 20 % de la lumière."))
	_engine.storm_ended.connect(func() -> void: _news.post("La tempête est passée. Le ciel redevient caramel."))
	_engine.resupply_arrived.connect(_on_resupply)
	_engine.colonist_evacuated.connect(_on_evacuation)
	_engine.colonist_arrived.connect(func(n: String) -> void: _news.post("%s rejoint la colonie. Bienvenue !" % n))
	_engine.shortage.connect(func(r: String) -> void:
		AudioManager.play("alert")
		GameManager.vibrate(60)
		_news.post("Alerte : plus %s ! Les colons puisent dans leurs réserves de secours." % ColonyContent.RESOURCE_PARTITIVE[r]))
	_engine.building_placed.connect(func(_i: int) -> void: _world.sync_with_game())


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
	var covered_top := (_alert if _alert.visible else _status).get_global_rect().end.y
	var bottom_top := _window.get_global_rect().position.y
	for panel: Control in [_placement_bar, _coach]:
		if panel.visible:
			bottom_top = minf(bottom_top, panel.get_global_rect().position.y)
	var covered_bottom := size.y - bottom_top
	_world.rig.covered_fraction = clampf((covered_bottom - covered_top) / size.y, -0.5, 0.9)


func _refresh() -> void:
	_status.refresh()
	_pages[_current_page].refresh()
	_world.sync_with_game()
	if not _placing.is_empty():
		_world.refresh_ghost()
		_refresh_placement()
	_window.set_badge(2, _research_page.has_available_research())
	_refresh_guidance()
	AudioManager.set_mood("storm" if _engine.is_storm() else ("night" if _engine.is_night() else "day"))
	AudioManager.set_wind(1.0 if _engine.is_storm() else 0.0)
	if _engine.state.sol >= _next_chatter and _engine.state.speed > 0:
		_next_chatter = _engine.state.sol + CHATTER_EVERY + randf()
		_news.post(ColonyContent.CHATTER[randi() % ColonyContent.CHATTER.size()])


## Alertes et guide : affichés sans gêner le placement.
func _refresh_guidance() -> void:
	var alerts := ColonyAdvisor.alerts(_engine)
	var top: Dictionary = alerts[0] if not alerts.is_empty() else {}
	var was_visible := _alert.visible
	var was_danger: bool = _alert.visible and _alert._alert.get("level") == "danger"
	_alert.show_alert(top, maxi(0, alerts.size() - 1))
	if not top.is_empty() and top.level == "danger" and not was_danger:
		AudioManager.play("alert")
		GameManager.vibrate(40)
	var step := ColonyAdvisor.tutorial_step(_engine) if _placing.is_empty() else -1
	var coach_was_visible := _coach.visible
	if _coach.show_step(step) and coach_was_visible and _placing.is_empty():
		AudioManager.play("milestone")
		_news.post("Étape du guide réussie !" if step >= 0 else "Guide terminé : votre colonie respire, boit et mange. Bravo !")
	if _alert.visible != was_visible or _coach.visible != coach_was_visible:
		_layout_changed.call_deferred()


## Emmène le joueur à la solution : ouvre l'onglet et met la ligne en évidence.
func _go_to(tab: int, target: String) -> void:
	if not _placing.is_empty():
		_stop_placement()
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
	_placement_title.text = "Placer : %s (%s matériaux)" % [def.name, NumberFormatter.format(def.cost)]
	var problem := _engine.placement_problem(_placing, cell)
	if not problem.is_empty():
		_placement_reason.text = problem
		_placement_reason.add_theme_color_override("font_color", Palette.DANGER)
	elif not _engine.would_connect(_placing, cell):
		_placement_reason.text = "Possible, mais isolé : il ne fonctionnera pas sans être relié (posez des conduites)."
		_placement_reason.add_theme_color_override("font_color", Palette.WARNING)
	else:
		_placement_reason.text = "Touchez le sol pour déplacer le module. Emplacement valide et raccordé."
		_placement_reason.add_theme_color_override("font_color", Palette.SUCCESS)
	_placement_confirm.disabled = not problem.is_empty()


func _confirm_placement() -> void:
	if _engine.place(_placing, _world.ghost_cell()):
		AudioManager.play("build")
		GameManager.vibrate(25)
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
				elif not _dragged and _touches.size() <= 1:
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
	match _engine.map.tile_at(cell):
		ColonyMap.Tile.ROCK:
			_news.post("Des rochers basaltiques : impossible de construire ici.")
		ColonyMap.Tile.RIM:
			_news.post("Le rebord du cratère Jezero. Superbe vue, mais trop pentu pour bâtir.")
		ColonyMap.Tile.ICE:
			_news.post("De la glace d'eau, juste sous la poussière !" if _engine.state.research_done.has("ice")
					else "Régolithe martien : poussière fine et sels de perchlorate.")
		_:
			_news.post("Régolithe martien : poussière fine et sels de perchlorate.")


# ---------- Événements ----------

func _on_research_completed(research_id: String) -> void:
	var r: Defs.Research = _engine.research_defs[research_id]
	AudioManager.play("upgrade")
	_news.post("Recherche terminée : %s" % r.name)
	if research_id == "ice":
		_news.post("Les relevés révèlent de la glace sous la poussière : regardez la carte !")
	if not r.card.is_empty():
		_show_card(r.card, true)


func _on_objective_completed(objective_id: String) -> void:
	for o in _engine.objectives:
		if o.id == objective_id:
			AudioManager.play("milestone")
			GameManager.vibrate(30)
			_news.post("Objectif atteint : %s ! Récompense : %s" % [o.title, ColonyPage._reward_text(o.reward)])
			if objective_id == "autonomy":
				Modal.open(_modal_layer, {
					"icon": "check", "title": "Ère « Survie » accomplie !",
					"body": "Votre colonie tient seule : oxygène, eau et nourriture sont produits sur place.\n"
							+ "C'est exactement le défi que la NASA et l'ESA préparent pour les premières missions habitées.\n\n"
							+ "Les ères suivantes (Autonomie, Expansion, Terraformation) arrivent dans une prochaine version.",
					"confirm_text": "Continuer à jouer",
				})


func _on_resupply(report: Dictionary) -> void:
	_world.land_capsule()
	AudioManager.play("landing")
	var text := "Ravitaillement de la Terre : +%s matériaux" % NumberFormatter.format(report.materials)
	if report.food > 0.0:
		text += ", +%s rations" % NumberFormatter.format(report.food)
	else:
		text += ". Plus de nourriture : la Terre compte sur vos serres"
	if not report.colonists.is_empty():
		text += ". À bord : %s" % ", ".join(report.colonists)
	_news.post(text + ".")


func _on_evacuation(colonist_name: String, cause: String) -> void:
	_world.launch_evacuation()
	AudioManager.play("evacuation")
	GameManager.vibrate(80)
	_news.post("%s a été évacué vers la Terre." % colonist_name)
	Modal.open(_modal_layer, {
		"icon": "warning", "title": "%s évacué" % colonist_name,
		"body": "Sa santé ne permettait plus de rester sur Mars. Une capsule l'a ramené vers la Terre.\n\n"
				+ "Cause : " + cause,
		"confirm_text": "Compris",
	})


# ---------- Fenêtres ----------

func _show_welcome() -> void:
	Modal.open(_modal_layer, {
		"icon": "rocket", "title": "Bienvenue dans le cratère Jezero",
		"body": "Votre équipage de 4 colons vient de se poser. Les réserves d'oxygène tiennent environ 9 sols.\n\n"
				+ "Suivez le guide en bas de l'écran : il vous montre quoi faire, étape par étape.\n"
				+ "Touchez une ressource en haut pour savoir d'où elle vient.",
		"confirm_text": "C'est parti",
	})


func _show_building(index: int) -> void:
	var def := _engine.def_of(index)
	var status := _engine.building_status(index)
	var lines: Array[String] = []
	for r: String in def.outputs:
		lines.append("+%s %s %s/sol" % [NumberFormatter.format(def.outputs[r]), ColonyContent.RESOURCE_UNITS[r], ColonyContent.RESOURCE_NAMES[r].to_lower()])
	for r: String in def.inputs:
		lines.append("−%s %s %s/sol" % [NumberFormatter.format(def.inputs[r]), ColonyContent.RESOURCE_UNITS[r], ColonyContent.RESOURCE_NAMES[r].to_lower()])
	for r: String in def.storage:
		lines.append("Stockage : +%s %s %s" % [NumberFormatter.format(def.storage[r]), ColonyContent.RESOURCE_UNITS[r], ColonyContent.RESOURCE_NAMES[r].to_lower()])
	if def.housing > 0:
		lines.append("Loge %d colons" % def.housing)
	var status_label := UiFx.paragraph(status.text, "HeadingLabel", HORIZONTAL_ALIGNMENT_CENTER)
	status_label.add_theme_color_override("font_color", Palette.SUCCESS if status.ok else Palette.WARNING)
	var extra := UiFx.vbox(8, [UiFx.panel("Thumb", UiFx.building_icon(def.id, Vector2(200, 160))), status_label,
			UiFx.paragraph("\n".join(lines), "BodyLabel", HORIZONTAL_ALIGNMENT_CENTER)])
	(extra.get_child(0) as Control).size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if not def.card.is_empty() and _engine.state.cards_unlocked.has(def.card):
		var learn := Button.new()
		learn.text = "En savoir plus : " + _engine.cards[def.card].title
		learn.focus_mode = Control.FOCUS_NONE
		learn.clip_text = true
		learn.pressed.connect(func() -> void: _show_card(def.card))
		extra.add_child(learn)
	var options := {
		"icon": "tab_build", "title": def.name, "body": def.description, "extra": extra, "confirm_text": "Fermer",
	}
	if not def.fixed:
		options.cancel_text = "Démolir (+%s)" % NumberFormatter.format(def.cost * ColonyEngine.DEMOLISH_REFUND)
		options.cancel_style = "Button"
	var modal := Modal.open(_modal_layer, options)
	if not def.fixed:
		modal.cancelled.connect(func() -> void:
			if _engine.demolish(index):
				AudioManager.play("whoosh"))


func _show_card(card_id: String, discovered := false) -> void:
	var card: Defs.Card = _engine.cards[card_id]
	var status := UiFx.label(card.status, "CaptionLabel", HORIZONTAL_ALIGNMENT_CENTER)
	status.add_theme_color_override("font_color", Palette.STATUS_COLORS.get(card.status, Palette.TEXT_MUTED))
	var in_game := UiFx.paragraph("Dans le jeu : " + card.in_game, "SmallLabel")
	in_game.add_theme_color_override("font_color", Palette.ACCENT)
	var extra := UiFx.vbox(10, [status, UiFx.paragraph(card.fact, "BodyLabel"), in_game,
			UiFx.label("Sources", "CaptionLabel")])
	for source: Array in card.sources:
		var link := LinkButton.new()
		link.text = source[0]
		link.uri = source[1]
		link.add_theme_color_override("font_color", Palette.FAME)
		link.add_theme_font_size_override("font_size", 18)
		extra.add_child(link)
	Modal.open(_modal_layer, {
		"icon": "tab_knowledge",
		"title": ("Découverte : " if discovered else "") + card.title,
		"extra": extra,
		"confirm_text": "Fermer",
	})


func _show_resource(resource: String) -> void:
	var flows := _engine.average_flows()
	var lines: Array[String] = []
	var unit: String = ColonyContent.RESOURCE_UNITS[resource]
	var by_type := {}
	for i in _engine.state.buildings.size():
		if not _engine.is_linked(i):
			continue
		var def := _engine.def_of(i)
		var amount: float = def.outputs.get(resource, 0.0) - def.inputs.get(resource, 0.0)
		if amount != 0.0:
			by_type[def.name] = by_type.get(def.name, 0.0) + amount
	for name: String in by_type:
		lines.append("%s : %s%s %s/sol" % [name, "+" if by_type[name] > 0.0 else "", NumberFormatter.format(by_type[name]), unit])
	var needs := _engine.colonist_needs()
	if needs.has(resource):
		lines.append("Colons (%d) : −%s %s/sol" % [_engine.state.colonists.size(),
				NumberFormatter.format(needs[resource] * _engine.state.colonists.size()), unit])
	if resource == ColonyContent.DATA:
		lines.append("Colons (%d) : +%s/sol" % [_engine.state.colonists.size(), NumberFormatter.format(ColonyContent.COLONIST_DATA * _engine.state.colonists.size())])
	var capacity := _engine.capacity(resource)
	var stock := "%s %s" % [NumberFormatter.format(_engine.state.amount(resource)), unit]
	if not is_inf(capacity):
		stock += " / %s" % NumberFormatter.format(capacity)
	var flow: float = flows[resource]
	Modal.open(_modal_layer, {
		"icon": resource,
		"title": ColonyContent.RESOURCE_NAMES[resource],
		"body": ColonyContent.RESOURCE_HELP[resource],
		"extra": UiFx.vbox(6, [
			UiFx.label("Réserve : " + stock, "HeadingLabel", HORIZONTAL_ALIGNMENT_CENTER),
			UiFx.label("Bilan moyen : %s%s %s/sol" % ["+" if flow >= 0.0 else "", NumberFormatter.format(flow), unit],
					"IncomeLabel" if flow >= 0.0 else "BodyLabel", HORIZONTAL_ALIGNMENT_CENTER),
			UiFx.paragraph("\n".join(lines) if not lines.is_empty() else "Aucun module ne produit ni ne consomme cette ressource.",
					"SmallLabel", HORIZONTAL_ALIGNMENT_CENTER),
		]),
		"confirm_text": "Fermer",
	})


func _show_offline_report(report: Dictionary) -> void:
	var lines: Array[String] = []
	for r in ColonyContent.RESOURCES:
		var delta: float = report.gains.get(r, 0.0)
		if absf(delta) >= 0.5:
			lines.append("%s : %s%s" % [ColonyContent.RESOURCE_NAMES[r], "+" if delta > 0.0 else "", NumberFormatter.format(delta)])
	var body := "Absence : %s. La colonie a tourné en pilote automatique pendant %s sol%s, sans tempête ni danger." % [
		NumberFormatter.duration(report.elapsed), NumberFormatter.format(report.sols), "s" if report.sols >= 2.0 else ""]
	if not report.standby.is_empty():
		body += "\n\nVeille sécurisée déclenchée : la réserve %s allait s'épuiser. %s" % [
			ColonyContent.RESOURCE_PARTITIVE[report.standby], ColonyEngine.CAUSES.get(report.standby, "")]
	Modal.open(_modal_layer, {
		"icon": "clock", "title": "Rapport du pilote automatique", "body": body,
		"extra": UiFx.paragraph("\n".join(lines), "BodyLabel", HORIZONTAL_ALIGNMENT_CENTER),
		"confirm_text": "Reprendre",
	})


func _show_settings() -> void:
	var state := _engine.state
	var music := _setting_toggle("Musique", state.music_enabled, func(on: bool) -> void:
		state.music_enabled = on
		AudioManager.apply_settings())
	var sound := _setting_toggle("Sons et ambiance", state.sound_enabled, func(on: bool) -> void:
		state.sound_enabled = on
		AudioManager.apply_settings()
		AudioManager.play("click"))
	var haptics := _setting_toggle("Vibrations", state.haptics_enabled, func(on: bool) -> void:
		state.haptics_enabled = on
		GameManager.vibrate(20))
	Modal.open(_modal_layer, {
		"icon": "gear", "title": "Réglages",
		"extra": UiFx.vbox(10, [music, sound, haptics,
			UiFx.paragraph("Glissez pour parcourir le cratère, pincez (ou molette) pour zoomer.\n"
					+ "Touchez un module pour le détail, une ressource pour son explication.\n"
					+ "Hors-ligne : pilote automatique prudent, 8 h au plus, sans tempête.",
					"SmallLabel", HORIZONTAL_ALIGNMENT_CENTER),
			UiFx.label("Ares Colony · v%s" % ProjectSettings.get_setting("application/config/version", "0.1"),
					"CaptionLabel", HORIZONTAL_ALIGNMENT_CENTER)]),
		"confirm_text": "Fermer",
	})


func _setting_toggle(title: String, value: bool, on_change: Callable) -> Button:
	var button := Button.new()
	button.toggle_mode = true
	button.button_pressed = value
	button.custom_minimum_size.y = 60
	button.focus_mode = Control.FOCUS_NONE
	button.theme_type_variation = "GreenButton" if value else "Button"
	button.text = "%s : %s" % [title, "activé" if value else "désactivé"]
	button.toggled.connect(func(on: bool) -> void:
		button.theme_type_variation = "GreenButton" if on else "Button"
		button.text = "%s : %s" % [title, "activé" if on else "désactivé"]
		on_change.call(on))
	return button


func _show_load_problem() -> void:
	match GameManager.load_result:
		SaveService.LoadResult.RESTORED_FROM_BACKUP:
			_news.post("Sauvegarde restaurée depuis la copie de secours.")
		SaveService.LoadResult.CORRUPTED:
			Modal.open(_modal_layer, {
				"icon": "warning", "title": "Sauvegarde illisible",
				"body": "Une nouvelle colonie commence. L'ancien fichier a été conservé à part et ne sera pas effacé.",
				"confirm_text": "Compris",
			})
