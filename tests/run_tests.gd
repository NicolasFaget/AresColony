extends SceneTree
## Tests du cœur du jeu, sans interface.
## Lancement : godot --headless --path . -s tests/run_tests.gd
## Code de sortie 0 si tout passe, 1 sinon.

const R = preload("res://core/colony_content.gd")

var _failures := 0
var _checks := 0


func _init() -> void:
	_test_content()
	_test_map()
	_test_new_game()
	_test_placement()
	_test_sunlight()
	_test_production()
	_test_night_and_batteries()
	_test_colonists()
	_test_research()
	_test_events()
	_test_offline()
	_test_save()
	_test_advisor()
	_test_number_formatter()
	_simulate_campaign()
	print("\n%d vérifications, %d échec(s)" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("ÉCHEC : ", label)


func _near(a: float, b: float, tolerance := 1e-6) -> bool:
	return absf(a - b) <= tolerance * maxf(1.0, maxf(absf(a), absf(b)))


func _engine() -> ColonyEngine:
	return ColonyEngine.new(ColonyState.new())


## Engine sans événements (tests qui sautent dans le temps) et dont la rangée à droite de
## l'atterrisseur est dégagée (les rochers sont placés au hasard).
func _calm_engine() -> ColonyEngine:
	var engine := _engine()
	engine.state.next_resupply = 1e9
	engine.state.next_storm = 1e9
	var lander := engine.map.lander_cell
	for x in range(lander.x + 2, lander.x + 9):
		for y in range(lander.y - 1, lander.y + 3):
			engine.map.set_tile(Vector2i(x, y), ColonyMap.Tile.PLAIN)
	return engine


## Engine avec toutes les recherches faites et beaucoup de matériaux (tests de construction).
func _rich_engine() -> ColonyEngine:
	var engine := _calm_engine()
	for r: Defs.Research in engine.research_defs.values():
		engine.state.research_done.append(r.id)
	engine.state.resources[R.MATERIALS] = 400.0
	return engine


# ---------- Contenu ----------

func _test_content() -> void:
	var engine := _engine()
	var ids := {}
	for def: Defs.Building in engine.building_defs.values():
		_check(not ids.has(def.id), "module unique : %s" % def.id)
		ids[def.id] = true
		_check(def.research.is_empty() or engine.research_defs.has(def.research), "recherche du module existe : %s" % def.id)
		_check(def.card.is_empty() or engine.cards.has(def.card), "fiche du module existe : %s" % def.id)
		for r: String in def.inputs.keys() + def.outputs.keys() + def.storage.keys():
			_check(r in R.RESOURCES, "ressource connue (%s, %s)" % [def.id, r])
	for r: Defs.Research in engine.research_defs.values():
		_check(r.card.is_empty() or engine.cards.has(r.card), "fiche de la recherche existe : %s" % r.id)
		for req: String in r.requires:
			_check(engine.research_defs.has(req), "prérequis existe : %s" % req)
	for card: Defs.Card in engine.cards.values():
		_check(not card.sources.is_empty(), "fiche sourcée : %s" % card.id)
		for source: Array in card.sources:
			_check(str(source[1]).begins_with("https://"), "source en lien https : %s" % card.id)


func _test_map() -> void:
	var a := ColonyMap.new(7)
	var b := ColonyMap.new(7)
	_check(a.tiles == b.tiles, "carte déterministe pour une même graine")
	_check(a.ice_cells().size() >= 12, "assez de glace sur la carte")
	_check(a.tile_at(Vector2i(0, 0)) == ColonyMap.Tile.RIM, "rebord du cratère dans les coins")
	_check(a.tile_at(Vector2i(-1, 5)) == ColonyMap.Tile.RIM, "hors carte = rebord")
	for y in range(a.lander_cell.y - 1, a.lander_cell.y + 3):
		for x in range(a.lander_cell.x - 1, a.lander_cell.x + 3):
			_check(a.tile_at(Vector2i(x, y)) == ColonyMap.Tile.PLAIN, "abords de l'atterrisseur dégagés")


func _test_new_game() -> void:
	var engine := _engine()
	_check(engine.state.buildings.size() == 1 and engine.state.buildings[0].id == "lander", "partie neuve : atterrisseur")
	_check(engine.state.colonists.size() == 4 and engine.housing() == 4, "partie neuve : 4 colons logés")
	_check(engine.is_linked(0), "l'atterrisseur est raccordé")
	_check(engine.state.cards_unlocked.has("atmosphere"), "fiches de départ")
	_check(engine.current_objective().id == "first_breath", "premier objectif")


# ---------- Construction ----------

func _test_placement() -> void:
	var engine := _calm_engine()
	var lander := engine.map.lander_cell
	_check(engine.placement_problem("moxie", lander + Vector2i(2, 0)).begins_with("Recherche"), "module verrouillé")
	_check(engine.placement_problem("solar", lander).contains("occupé"), "case occupée")
	_check(engine.placement_problem("solar", Vector2i(0, 0)) != "", "rebord du cratère refusé")
	_check(engine.placement_problem("solar", Vector2i(-3, 4)) == "Hors du cratère.", "hors carte refusé")

	var beside := lander + Vector2i(2, 0)
	_check(engine.would_connect("solar", beside), "à côté de l'atterrisseur : raccordé")
	_check(not engine.would_connect("solar", lander + Vector2i(4, 0)), "à distance : non raccordé")
	var materials := engine.state.amount(R.MATERIALS)
	_check(engine.place("solar", beside), "pose d'un panneau")
	_check(_near(engine.state.amount(R.MATERIALS), materials - 15.0), "le panneau coûte 15")
	_check(engine.is_linked(1), "panneau raccordé")

	_check(engine.place("solar", lander + Vector2i(5, 0)), "pose d'un panneau isolé")
	_check(not engine.is_linked(2), "panneau isolé non raccordé")
	_check(not engine.building_status(2).ok, "statut : non raccordé")
	_check(engine.place("link", lander + Vector2i(3, 0)) and engine.place("link", lander + Vector2i(4, 0)), "pose de conduites")
	_check(engine.is_linked(2), "les conduites raccordent le panneau isolé")

	_check(not engine.demolish(0), "l'atterrisseur ne se démolit pas")
	materials = engine.state.amount(R.MATERIALS)
	_check(engine.demolish(3), "démolition d'une conduite")
	_check(_near(engine.state.amount(R.MATERIALS), materials + 2.0), "démolition : la moitié du coût rendue")
	_check(not engine.is_linked(engine.state.buildings.size() - 1), "sans la conduite, le panneau est isolé")

	var rich := _rich_engine()
	var plain := ColonyBot.connected_spot(rich, "habitat")
	_check(rich.placement_problem("extractor", plain).contains("glace"), "extracteur hors de la glace refusé")
	rich.state.resources[R.MATERIALS] = 0.0
	_check(rich.placement_problem("solar", plain).begins_with("Matériaux"), "matériaux insuffisants")


# ---------- Production ----------

func _test_sunlight() -> void:
	var engine := _engine()
	engine.state.sol = 10.0
	_check(engine.sunlight() == 0.0 and engine.is_night(), "minuit : aucun soleil")
	engine.state.sol = 10.5
	_check(_near(engine.sunlight(), PI) and not engine.is_night(), "midi : plein soleil")
	var total := 0.0
	for i in 1000:
		engine.state.sol = 10.0 + i / 1000.0
		total += engine.sunlight()
	_check(absf(total / 1000.0 - 1.0) < 0.01, "ensoleillement moyen de 1 sur un sol")
	engine.state.sol = 10.5
	engine.state.storm_until = 12.0
	_check(_near(engine.sunlight(), PI * ColonyEngine.STORM_SOLAR), "tempête : 20 % de la lumière")


func _test_production() -> void:
	var engine := _rich_engine()
	engine.state.colonists.clear()
	engine.state.sol = 20.4
	var spot := ColonyBot.connected_spot(engine, "moxie")
	engine.place("moxie", spot)
	var o2 := engine.state.amount(R.OXYGEN)
	engine.advance(0.1)
	_check(engine.state.amount(R.OXYGEN) > o2, "électrolyseur de CO₂ alimenté : l'oxygène augmente")
	_check(_near(engine.efficiency(1), 1.0), "électrolyseur à plein régime")

	var isolated := _calm_engine()
	isolated.state.research_done.append("moxie")
	isolated.state.colonists.clear()
	isolated.place("moxie", isolated.map.lander_cell + Vector2i(5, 0))
	o2 = isolated.state.amount(R.OXYGEN)
	isolated.advance(0.5)
	_check(_near(isolated.state.amount(R.OXYGEN), o2), "électrolyseur non raccordé : rien")

	var flows := _engine().average_flows()
	_check(_near(flows[R.OXYGEN], -0.84 * 4), "bilan : 4 colons respirent 3,36 kg d'oxygène par sol")
	_check(_near(flows[R.ENERGY], 8.0), "bilan : l'atterrisseur produit 8 kWh par sol en moyenne")

	# Électrolyse de l'eau : vrai rapport de masse 8/9.
	var def: Defs.Building = engine.building_defs["electrolyser"]
	_check(absf(def.outputs[R.OXYGEN] / def.inputs[R.WATER] - 8.0 / 9.0) < 0.01, "électrolyseur d'eau : 8/9 de la masse en oxygène")


func _test_night_and_batteries() -> void:
	var engine := _rich_engine()
	engine.state.colonists.clear()
	engine.state.sol = 30.8
	engine.place("moxie", ColonyBot.connected_spot(engine, "moxie"))
	engine.state.resources[R.ENERGY] = 1.0
	engine.advance(0.3)
	_check(engine.efficiency(1) < 0.5, "la nuit, sans réserve d'énergie, l'électrolyseur ralentit")
	_check(not engine.building_status(1).ok, "statut : manque d'énergie")
	_check(engine.building_status(1).text.contains("d'énergie"), "statut en bon français")

	var capacity := engine.capacity(R.ENERGY)
	engine.place("battery", ColonyBot.connected_spot(engine, "battery"))
	_check(_near(engine.capacity(R.ENERGY), capacity + 60.0), "batterie : +60 kWh de stockage")


# ---------- Colons ----------

func _test_colonists() -> void:
	var engine := _calm_engine()
	var evacuated: Array[String] = []
	var causes: Array[String] = []
	engine.colonist_evacuated.connect(func(n: String, c: String) -> void:
		evacuated.append(n)
		causes.append(c))
	engine.state.resources[R.OXYGEN] = 0.0
	engine.advance(0.6)
	_check(evacuated.is_empty(), "les réserves de secours laissent le temps de réagir")
	engine.advance(0.15)
	_check(not evacuated.is_empty(), "sans oxygène, un colon finit par être évacué")
	_check(causes[0].contains("oxygène"), "la cause est expliquée")
	_check(evacuated.size() < 4, "les colons ne partent pas tous en même temps")
	_check(engine.state.evacuated == evacuated.size(), "évacuations comptées")

	var healthy := _calm_engine()
	healthy.state.colonists[0].health = 0.5
	healthy.advance(1.0)
	_check(healthy.state.colonists[0].health > 0.5, "bien approvisionné, un colon reprend des forces")


# ---------- Recherche ----------

func _test_research() -> void:
	var engine := _calm_engine()
	var completed: Array[String] = []
	engine.research_completed.connect(func(id: String) -> void: completed.append(id))
	_check(engine.research_state("greenhouse") == "locked", "serre verrouillée sans la glace")
	_check(engine.research_state("moxie") == "available", "électrolyse disponible")
	var data := engine.state.amount(R.DATA)
	_check(engine.start_research("moxie"), "lancement d'une recherche")
	_check(_near(engine.state.amount(R.DATA), data - 6.0), "la recherche coûte ses données")
	_check(not engine.start_research("ice"), "une seule recherche à la fois")
	engine.advance(0.6)
	_check(completed == (["moxie"] as Array[String]), "recherche terminée après sa durée")
	_check(engine.is_unlocked(engine.building_defs["moxie"]), "module débloqué")
	_check(engine.state.cards_unlocked.has("moxie"), "fiche débloquée")

	engine.state.resources[R.DATA] = 0.0
	_check(not engine.start_research("ice"), "pas assez de données")

	var bonus := _engine()
	bonus.state.research_done.append("recycling")
	_check(_near(bonus.colonist_needs()[R.WATER], 2.5 * 0.4), "recyclage : 60 % d'eau en moins")


# ---------- Événements ----------

func _test_events() -> void:
	var engine := _engine()
	var warned := [false]
	var started := [false]
	var resupplies: Array[Dictionary] = []
	engine.storm_warning.connect(func() -> void: warned[0] = true)
	engine.storm_started.connect(func() -> void: started[0] = true)
	engine.resupply_arrived.connect(func(r: Dictionary) -> void: resupplies.append(r))
	_check(engine.state.next_storm >= 12.0, "pas de tempête avant le sol 12")

	engine.state.resources[R.OXYGEN] = 60.0
	engine.state.sol = engine.state.next_storm - 1.5
	engine.advance(1.0)
	_check(warned[0] and not started[0], "tempête annoncée un sol à l'avance")
	engine.advance(1.0)
	_check(started[0] and engine.is_storm(), "la tempête éclate")
	_check(engine.state.cards_unlocked.has("storm"), "fiche de la tempête")
	_check(engine.state.next_storm > engine.state.storm_until, "prochaine tempête après celle-ci")

	var supply := _engine()
	supply.state.resupply_count = 0
	supply.place("habitat", ColonyBot.connected_spot(supply, "habitat"))
	var materials := supply.state.amount(R.MATERIALS)
	var arrivals: Array[Dictionary] = []
	supply.resupply_arrived.connect(func(r: Dictionary) -> void: arrivals.append(r))
	supply.state.sol = 7.99
	supply.advance(0.05)
	_check(arrivals.size() == 1, "ravitaillement au sol 8")
	_check(arrivals[0].colonists.size() == 2 and supply.state.colonists.size() == 6, "deux recrues logées dans l'habitat")
	_check(supply.state.amount(R.MATERIALS) > materials, "matériaux livrés")


func _test_offline() -> void:
	var engine := _engine()
	var evacuations := [0]
	engine.colonist_evacuated.connect(func(_n: String, _c: String) -> void: evacuations[0] += 1)
	var storm := engine.state.next_storm
	var report := engine.apply_offline_seconds(3.0 * 3600.0)
	_check(report.sols > 0.0, "hors-ligne : la colonie a continué")
	_check(report.standby == R.OXYGEN or report.standby == R.WATER, "hors-ligne : veille avant de manquer d'air ou d'eau")
	_check(evacuations[0] == 0, "hors-ligne : aucune évacuation")
	_check(engine.state.amount(R.OXYGEN) > 0.0, "veille déclenchée avant l'épuisement")
	_check(_near(engine.state.next_storm, storm + report.sols), "hors-ligne : la tempête est repoussée")

	var long := _rich_engine()
	long.state.colonists.clear()
	var capped := long.apply_offline_seconds(48.0 * 3600.0)
	_check(_near(capped.sols, ColonyEngine.OFFLINE_CAP_SECONDS / ColonyEngine.OFFLINE_SECONDS_PER_SOL, 1e-3),
			"hors-ligne plafonné à 8 h")
	_check(_engine().apply_offline_seconds(10.0).sols == 0.0, "absence très courte : rien à faire")


# ---------- Conseiller ----------

func _test_advisor() -> void:
	var engine := _calm_engine()
	var days := ColonyAdvisor.forecast(engine)
	_check(_near(days[R.OXYGEN], 30.0 / 3.36, 1e-3), "prévision : oxygène pour ~9 sols au départ")
	_check(ColonyAdvisor.alerts(engine).is_empty(), "pas d'alerte au départ")

	engine.state.resources[R.OXYGEN] = 3.0
	var alerts := ColonyAdvisor.alerts(engine)
	_check(alerts.size() == 1 and alerts[0].resource == R.OXYGEN and alerts[0].level == "danger", "alerte rouge : oxygène")
	_check(alerts[0].target == "moxie" and alerts[0].tab == ColonyAdvisor.TAB_RESEARCH, "conseil : lancer la recherche")
	engine.state.research_done.append("moxie")
	_check(ColonyAdvisor.alerts(engine)[0].target == "moxie" and ColonyAdvisor.alerts(engine)[0].tab == ColonyAdvisor.TAB_BUILD,
			"conseil suivant : construire l'électrolyseur")
	engine.state.resources[R.OXYGEN] = 7.0
	_check(ColonyAdvisor.alerts(engine)[0].level == "warning", "alerte orange quand il reste ~2 sols")

	var isolated := _calm_engine()
	isolated.place("solar", isolated.map.lander_cell + Vector2i(5, 0))
	_check(ColonyAdvisor.alerts(isolated).back().target == "link", "alerte : module isolé, poser des conduites")

	# Le tutoriel avance tout seul avec le joueur simulé, puis se termine.
	var tuto := _engine()
	_check(ColonyAdvisor.tutorial_step(tuto) == 0, "tutoriel : première étape")
	ColonyBot.play(tuto, 12.0)
	_check(ColonyAdvisor.tutorial_step(tuto) == -1, "tutoriel terminé en jouant normalement")
	var skipped := _engine()
	skipped.state.tutorial_done = true
	_check(ColonyAdvisor.tutorial_step(skipped) == -1, "tutoriel passé")


# ---------- Sauvegarde ----------

func _test_save() -> void:
	var storage := SaveStorage.new()
	var service := SaveService.new(storage)
	var engine := _rich_engine()
	engine.place("solar", ColonyBot.connected_spot(engine, "solar"))
	engine.state.speed = 4
	engine.state.music_enabled = false
	engine.advance(2.3)
	service.save_state(engine.state, 1_700_000_000)

	var loaded := service.load_state()
	_check(service.last_result == SaveService.LoadResult.LOADED, "sauvegarde relue")
	_check(_near(loaded.sol, engine.state.sol), "sauvegarde : temps")
	_check(loaded.buildings == engine.state.buildings, "sauvegarde : modules")
	_check(loaded.colonists.size() == 4 and loaded.colonists[0].name == "Ada", "sauvegarde : colons")
	_check(loaded.research_done == engine.state.research_done, "sauvegarde : recherches")
	_check(_near(loaded.amount(R.MATERIALS), engine.state.amount(R.MATERIALS)), "sauvegarde : ressources")
	_check(loaded.speed == 4 and not loaded.music_enabled, "sauvegarde : préférences")
	var reloaded := ColonyEngine.new(loaded)
	_check(reloaded.is_linked(reloaded.state.buildings.size() - 1), "sauvegarde : raccordements recalculés")

	var bad := ColonyState.from_dict({ "sol": "hier", "resources": { "oxygen": -5, "water": null },
			"buildings": [3, { "id": "lander", "x": "a" }], "colonists": [{ "health": 9 }],
			"settings": { "speed": 3, "music": "oui" } })
	_check(bad.sol == 0.3 and bad.amount(R.OXYGEN) == 0.0, "valeurs invalides : valeurs par défaut")
	_check(bad.buildings.size() == 1 and bad.colonists[0].health == 1.0, "listes invalides filtrées")
	_check(bad.speed == 1 and bad.music_enabled, "préférences invalides : défaut")

	storage.write("{cassé")
	_check(not service.load_state().buildings.is_empty() and service.last_result == SaveService.LoadResult.RESTORED_FROM_BACKUP,
			"sauvegarde corrompue : copie de secours restaurée")


func _test_number_formatter() -> void:
	_check(NumberFormatter.format(1234.0) == "1.23K", "format des nombres")
	_check(NumberFormatter.duration(3600.0 * 3) == "3 h", "format des durées")


# ---------- Campagne simulée ----------

## Joueur simulé raisonnable : recherche dans l'ordre, construit ce qui manque le plus,
## étend son réseau de conduites jusqu'à la glace. Mesure le rythme de l'ère « Survie ».
func _simulate_campaign() -> void:
	var engine := _engine()
	var done := {}
	var evacuations := [0]
	engine.objective_completed.connect(func(id: String) -> void: done[id] = engine.state.sol)
	engine.building_placed.connect(func(i: int) -> void:
		if OS.get_environment("TRACE") != "":
			print("    sol %.2f : %s (reste %.0f matériaux, O₂ %+.1f/sol)" % [engine.state.sol, engine.state.buildings[i].id,
					engine.state.amount(R.MATERIALS), engine.average_flows()[R.OXYGEN]]))
	engine.resupply_arrived.connect(func(r: Dictionary) -> void:
		if OS.get_environment("TRACE") != "":
			print("    sol %.2f : ravitaillement, recrues %s" % [engine.state.sol, r.colonists]))
	engine.colonist_evacuated.connect(func(n: String, c: String) -> void:
		evacuations[0] += 1
		var flows := engine.average_flows()
		print("  évacuation de %s au sol %.1f (O₂ %.1f, eau %.1f, nourriture %.1f, énergie %.1f/sol, matériaux %.0f, O₂ stock %.1f) : %s" % [
			n, engine.state.sol, flows[R.OXYGEN], flows[R.WATER], flows[R.FOOD], flows[R.ENERGY], engine.state.amount(R.MATERIALS), engine.state.amount(R.OXYGEN), c.left(20)]))
	while engine.state.sol < 80.0 and not done.has("autonomy"):
		ColonyBot.research(engine)
		ColonyBot.build(engine)
		engine.advance(0.25)

	print("\n--- Campagne « Survie » (joueur simulé) ---")
	for objective in engine.objectives:
		print("%-14s %s" % [objective.id, "sol %.1f" % done[objective.id] if done.has(objective.id) else "non atteint"])
	print("Évacuations : %d, colons : %d, modules : %d" % [evacuations[0], engine.state.colonists.size(), engine.state.buildings.size()])
	_check(done.get("first_breath", INF) <= 3.0, "premier oxygène avant le sol 3")
	_check(done.get("water", INF) <= 10.0, "eau avant le sol 10")
	_check(done.get("autonomy", INF) >= 20.0 and done.get("autonomy", INF) <= 60.0, "autonomie entre les sols 20 et 60")
	_check(evacuations[0] == 0, "un joueur raisonnable ne perd aucun colon")

	# Un joueur qui ne fait rien finit par mettre la colonie en danger, mais pas tout de suite.
	var idle := _engine()
	var first := [-1.0]
	idle.colonist_evacuated.connect(func(_n: String, _c: String) -> void:
		if first[0] < 0.0:
			first[0] = idle.state.sol)
	idle.advance(20.0)
	print("Sans rien faire : première évacuation au sol %.1f" % first[0])
	_check(first[0] >= 5.0 and first[0] <= 15.0, "sans rien faire : danger réel, mais pas avant le sol 5")
