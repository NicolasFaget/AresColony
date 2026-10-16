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
	_test_synergies()
	_test_cards()
	_test_upgrades()
	_test_hazards()
	_test_era2()
	_test_era3()
	_test_guides()
	_test_campaign()
	_test_ceres()
	_test_regions()
	_test_night_and_batteries()
	_test_colonists()
	_test_research()
	_test_events()
	_test_offline()
	_test_save()
	_test_advisor()
	_test_number_formatter()
	_simulate_campaign()
	_simulate_realtime()
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
	engine.state.next_dust_devil = 1e9
	engine.dust_rate = 0.0
	engine.breakdown_rate = 0.0
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


# ---------- Régions ----------

func _test_regions() -> void:
	var jezero := _engine()
	var state := ColonyState.new()
	state.region = "arcadia"
	var arcadia := ColonyEngine.new(state)
	_check(arcadia.map.ice_cells().size() > jezero.map.ice_cells().size() + 20, "Arcadia : beaucoup plus de glace")
	_check(_near(arcadia.effect("solar"), 0.8) and _near(jezero.effect("solar"), 1.0), "Arcadia : moins de soleil")
	_check(arcadia.state.cards_unlocked.has("arcadia"), "Arcadia : fiche de la région")
	_check(arcadia.next_site().id == "ice_impact" and jezero.next_site().id == "delta", "sites propres à chaque région")
	arcadia.state.research_done.append("ice")
	arcadia.state.resources[R.MATERIALS] = 400.0
	var spot := ColonyBot.connected_spot(arcadia, "habitat")
	arcadia.place("habitat", spot)
	var home := arcadia.state.buildings.size() - 1
	_check(_near(arcadia._input_rate(home, R.ENERGY), arcadia.def_of(home).inputs[R.ENERGY] * 1.25), "Arcadia : chauffage +25 %")
	var copy := ColonyState.from_dict(JSON.parse_string(JSON.stringify(arcadia.state.to_dict())))
	_check(copy.region == "arcadia" and ColonyEngine.new(copy).map.tiles == arcadia.map.tiles, "région sauvegardée")


# ---------- Campagne : plusieurs colonies ----------

func _test_campaign() -> void:
	# Une ancienne sauvegarde (une seule colonie) devient une campagne.
	var old := _engine().state.to_dict()
	var migrated := Campaign.from_dict(old)
	_check(migrated.colonies.size() == 1 and migrated.active == 0, "ancienne sauvegarde convertie en campagne")

	var state := ColonyState.new()
	var campaign := Campaign.from_state(state)
	var mars := campaign.engine()
	mars.state.next_storm = 1e9
	mars.state.next_resupply = 1e9
	mars.state.next_dust_devil = 1e9
	mars.dust_rate = 0.0
	mars.breakdown_rate = 0.0
	for r: Defs.Research in mars.research_defs.values():
		mars.state.research_done.append(r.id)
	var lander := mars.map.lander_cell
	for x in range(lander.x + 2, lander.x + 9):
		for y in range(lander.y - 1, lander.y + 3):
			mars.map.set_tile(Vector2i(x, y), ColonyMap.Tile.PLAIN)
	mars.state.resources[R.MATERIALS] = 400.0
	_check(not campaign.founding_problem(0).is_empty(), "fondation : il faut finir les ères de Mars")
	mars.state.era = 4
	_check(campaign.founding_problem(0).begins_with("Il faut un astroport"), "fondation : il faut un astroport")
	_check(mars.place("spaceport", lander + Vector2i(2, 0)), "pose d'un astroport")
	_check("spaceport" in mars.state.objectives_done, "objectif « Porte des étoiles »")
	mars.state.resources[R.METHANE] = 100.0
	for k in 6:
		mars.state.colonists.append({ "name": "Recrue %d" % k, "role": "pilote", "health": 1.0 })
	var crew_before := mars.state.colonists.size()
	_check(campaign.found_colony(0, "arcadia"), "départ d'un vaisseau de fondation")
	_check(mars.state.colonists.size() == crew_before - Campaign.FOUNDING_CREW, "l'équipage quitte la colonie")
	_check(campaign.shipments.size() == 1 and campaign.colonies.size() == 1, "vaisseau en vol, colonie pas encore fondée")
	var founded := [0]
	campaign.colony_founded.connect(func(_i: int) -> void: founded[0] += 1)
	campaign.advance(Campaign.SURFACE_HOP_SOLS + 0.05)
	_check(founded[0] == 1 and campaign.colonies.size() == 2, "colonie fondée à l'arrivée")
	var outpost := campaign.engines[1]
	_check(outpost.state.colonists.size() == Campaign.FOUNDING_CREW and outpost.state.region == "arcadia", "équipage et région de la nouvelle colonie")
	_check(outpost.state.research_done.size() == mars.state.research_done.size(), "le savoir est partagé")
	_check(outpost.state.name == "Arcadia Planitia" and outpost.map.tiles != mars.map.tiles, "nom et carte propres")
	_check("outpost" in mars.state.objectives_done or mars.campaign_colonies == 2, "objectif « Deuxième foyer »")
	# Arrière-plan : la colonie non affichée avance aussi.
	var sol := outpost.state.sol
	campaign.advance(0.5)
	_check(outpost.state.sol > sol + 0.4, "la colonie en arrière-plan avance")
	# Cargaison.
	mars.state.resources[R.METHANE] = 100.0
	var stock := outpost.state.amount(R.MATERIALS)
	_check(campaign.shipment_problem(0, 1, { R.MATERIALS: 500.0 }, 0).begins_with("Trop lourd"), "cargaison trop lourde")
	_check(campaign.send_cargo(0, 1, { R.MATERIALS: 50.0 }, 0), "envoi d'une cargaison")
	campaign.advance(Campaign.SURFACE_HOP_SOLS + 0.1)
	_check(outpost.state.amount(R.MATERIALS) > stock + 40.0 and campaign.deliveries == 1, "cargaison livrée")
	# Bascule et sauvegarde.
	campaign.switch_to(1)
	_check(campaign.engine() == outpost, "bascule vers la nouvelle colonie")
	campaign.found_colony(0, "jezero") if campaign.founding_problem(0).is_empty() else null
	var copy := Campaign.from_dict(JSON.parse_string(JSON.stringify(campaign.to_dict())))
	_check(copy.colonies.size() == 2 and copy.active == 1 and copy.shipments.size() == campaign.shipments.size(), "campagne sauvegardée")
	_check(copy.colonies[1].name == "Arcadia Planitia", "nom de colonie sauvegardé")


# ---------- Cérès ----------

func _test_ceres() -> void:
	var state := ColonyState.new()
	var campaign := Campaign.from_state(state)
	var mars := campaign.engine()
	mars.state.next_storm = 1e9
	mars.state.next_resupply = 1e9
	mars.state.next_dust_devil = 1e9
	mars.dust_rate = 0.0
	mars.breakdown_rate = 0.0
	for r: Defs.Research in mars.research_defs.values():
		mars.state.research_done.append(r.id)
	mars.state.era = 4
	var lander := mars.map.lander_cell
	for x in range(lander.x + 2, lander.x + 9):
		for y in range(lander.y - 1, lander.y + 3):
			mars.map.set_tile(Vector2i(x, y), ColonyMap.Tile.PLAIN)
	mars.state.resources[R.MATERIALS] = 400.0
	mars.place("spaceport", lander + Vector2i(2, 0))
	for k in 8:
		mars.state.colonists.append({ "name": "Recrue %d" % k, "role": "pilote", "health": 1.0 })
	var route: Dictionary = Campaign.route("mars", "ceres")
	_check(not route.is_empty() and route.transit > 10.0, "route Mars-Cérès : un long voyage")
	# Fenêtre de tir : fermée, puis ouverte.
	campaign.time = route.phase + route.open + 1.0
	_check(not campaign.window_open("mars", "ceres") and campaign.window_wait("mars", "ceres") > 0.0, "fenêtre de tir fermée")
	mars.state.resources[R.METHANE] = 300.0
	_check(campaign.founding_problem(0, "ceres").begins_with("Fenêtre de tir fermée"), "fondation sur Cérès hors fenêtre refusée")
	_check(campaign.founding_problem(0, "arcadia").is_empty(), "fondation sur Mars possible à tout moment")
	campaign.time = route.phase + route.synodic
	_check(campaign.window_open("mars", "ceres"), "fenêtre de tir ouverte")
	var cost := campaign.founding_cost(0, "ceres")
	_check(cost[R.MATERIALS] > Campaign.FOUNDING_MATERIALS and cost[R.METHANE] > Campaign.FOUNDING_FUEL, "fonder sur Cérès coûte plus cher")
	mars.state.resources[R.MATERIALS] = 400.0
	mars.state.resources[R.METHANE] = 300.0
	_check(campaign.found_colony(0, "ceres"), "départ vers Cérès")
	campaign.advance(route.transit - 1.0)
	_check(campaign.colonies.size() == 1, "le vaisseau est encore en route")
	campaign.advance(1.5)
	_check(campaign.colonies.size() == 2 and campaign.planet_of(1) == "ceres", "colonie fondée sur Cérès")
	var ceres := campaign.engines[1]
	_check(ceres.planet().forbidden.has("moxie"), "pas d'électrolyseur de CO₂ sans air")
	_check(_near(ceres.effect("solar"), mars.effect("solar") * 0.3), "Cérès : trois fois moins de soleil")
	var reactor := false
	for building in ceres.state.buildings:
		reactor = reactor or building.id == "reactor"
	_check(reactor, "l'avant-poste arrive avec un petit réacteur")
	_check(ceres.current_objective().planet == "ceres", "objectifs propres à Cérès")
	_check(ceres.era_title().begins_with("Cérès"), "ère propre à Cérès")
	mars._check_objectives()
	_check("ceres" in mars.state.objectives_done, "objectif « Ceinture d'astéroïdes »")
	var sol := ceres.state.sol
	ceres.advance(30.0)
	_check(not ceres.is_storm() and ceres.dust_of(0) == 0.0, "pas de tempête ni de poussière sans air")
	# Décoller de Cérès coûte bien moins que de Mars.
	_check(campaign.fuel_cost(1, "jezero", {}, 0) < campaign.fuel_cost(0, "ceres", {}, 0) * 0.5, "décollage de Cérès bon marché")
	_check(sol < ceres.state.sol, "Cérès avance")


# ---------- Guides des ères ----------

func _test_guides() -> void:
	var engine := _rich_engine()
	engine.state.tutorial_done = true
	_check(ColonyAdvisor.tutorial_step(engine) == -1, "guide de l'ère 1 passé")
	engine.state.era = 2
	engine.state.research_done.erase("sabatier")
	var step := ColonyAdvisor.tutorial_step(engine)
	_check(step >= 0 and ColonyAdvisor.TUTORIAL[step].id == "research_sabatier", "guide de l'ère 2 : première étape")
	_check(ColonyAdvisor.era_steps(2).size() == 7 and ColonyAdvisor.era_steps(3).size() == 6, "étapes des guides des ères 2 et 3")
	engine.state.research_done.append("sabatier")
	_check(ColonyAdvisor.TUTORIAL[ColonyAdvisor.tutorial_step(engine)].id == "build_sabatier", "guide : étape suivante")
	engine.state.guides_skipped.append(2)
	_check(ColonyAdvisor.tutorial_step(engine) == -1, "guide de l'ère 2 passé")
	engine.state.era = 3
	_check(ColonyAdvisor.TUTORIAL[ColonyAdvisor.tutorial_step(engine)].era == 3, "guide de l'ère 3")
	var copy := ColonyState.from_dict(JSON.parse_string(JSON.stringify(engine.state.to_dict())))
	_check(copy.guides_skipped == [2], "guides passés sauvegardés")


# ---------- Ère 3 ----------

func _test_era3() -> void:
	var engine := _rich_engine()
	engine.state.era = 2
	for objective in engine.objectives:
		if objective.era <= 2 and objective.id != "return":
			engine.state.objectives_done.append(objective.id)
	engine.state.resources[R.MATERIALS] = 400.0
	var lander := engine.map.lander_cell
	engine.place("erv", lander + Vector2i(2, 0))
	engine.state.resources[R.METHANE] = ColonyEngine.RETURN_METHANE
	engine._check_objectives()
	_check(engine.state.era == 3, "l'ère 3 commence après l'ère 2")
	_check(engine.state.cards_unlocked.has("terraforming"), "fiche sur la terraformation")
	_check(engine.state.next_flare < 1e8, "les éruptions solaires sont programmées")
	_check(engine.shelter_capacity() == 0, "aucun abri au départ")
	# Éruption sans abri : tout le monde perd de la santé.
	engine.state.next_flare = engine.state.sol + 0.01
	var flares := [0]
	engine.flare_started.connect(func() -> void: flares[0] += 1)
	engine.advance(0.2)
	_check(flares[0] == 1 and engine.is_flare(), "une éruption commence")
	var hurt := true
	for c in engine.state.colonists:
		hurt = hurt and c.health < 1.0
	_check(hurt, "sans abri, les colons prennent les radiations")
	# Avec un habitat enterré, quatre colons sont protégés.
	engine.state.resources[R.MATERIALS] = 400.0
	_check(engine.place("bunker", lander + Vector2i(4, 0)), "pose d'un habitat enterré")
	_check(engine.shelter_capacity() == 4, "l'habitat enterré abrite 4 colons")
	for c in engine.state.colonists:
		c.health = 1.0
	engine.advance(0.05)
	var safe := 0
	for c in engine.state.colonists:
		if c.health >= 1.0:
			safe += 1
	_check(safe >= mini(4, engine.state.colonists.size()), "les colons abrités sont protégés")
	_check(engine.place("reactor", lander + Vector2i(6, 0)), "pose d'un réacteur à fission")
	var reactor := engine.state.buildings.size() - 1
	_check(_near(engine._output_rate(reactor, R.ENERGY, 0.0), 60.0), "le réacteur produit même sans soleil")
	_check(not "rooted" in engine.state.objectives_done, "« Enracinés » attend les autres objectifs")
	var copy := ColonyState.from_dict(JSON.parse_string(JSON.stringify(engine.state.to_dict())))
	_check(copy.era == 3 and _near(copy.next_flare, engine.state.next_flare), "ère 3 sauvegardée")


# ---------- Ère 2 ----------

func _test_era2() -> void:
	var engine := _rich_engine()
	engine.state.research_done.erase("sabatier")
	engine.state.research_done.erase("rovers")
	engine.state.research_done.erase("erv")
	_check(engine.research_state("sabatier") == "locked", "recherche de l'ère 2 verrouillée en ère 1")
	_check(engine.current_objective().era == 1, "objectif de l'ère 1")
	var eras: Array[int] = []
	engine.era_started.connect(func(era: int) -> void: eras.append(era))
	for objective in engine.objectives:
		if objective.era == 1 and objective.id != "autonomy":
			engine.state.objectives_done.append(objective.id)
	engine.state.autonomy_streak = ColonyEngine.AUTONOMY_GOAL
	engine._check_objectives()
	_check(engine.state.era == 2 and eras == [2], "l'ère 2 commence quand l'ère 1 est accomplie")
	_check(engine.current_objective().id == "methane", "premier objectif de l'ère 2")
	_check(engine.research_state("sabatier") == "available", "recherche de l'ère 2 disponible")
	for id in ["sabatier", "rovers", "erv"]:
		engine.state.research_done.append(id)
	engine.state.resources[R.MATERIALS] = 400.0
	var lander := engine.map.lander_cell
	_check(engine.expedition_problem().begins_with("Construisez"), "expédition : il faut un garage")
	_check(engine.place("garage", lander + Vector2i(2, 0)), "pose du garage")
	_check(engine.place("sabatier", lander + Vector2i(4, 0)), "pose d'un réacteur Sabatier")
	_check("methane" in engine.state.objectives_done, "objectif « Carburant martien »")
	engine.state.resources[R.METHANE] = 40.0
	var data := engine.state.amount(R.DATA)
	_check(engine.start_expedition() and engine.state.expedition.site == "delta", "départ vers le delta de Jezero")
	_check(not engine.start_expedition(), "une expédition à la fois")
	engine.state.sol = engine.state.expedition.until
	engine._finish_expedition()
	_check(engine.state.expeditions == 1 and "delta" in engine.state.sites_done, "retour d'expédition")
	_check(engine.state.cards_unlocked.has("jezero") and engine.state.amount(R.DATA) >= data + 30.0, "fiche et données rapportées")
	_check(engine.next_site().id == "meteorite", "site suivant")
	engine.state.resources[R.MATERIALS] = 400.0
	_check(engine.place("erv", lander + Vector2i(2, 2)), "pose du véhicule de retour")
	_check(engine.placement_problem("erv", lander + Vector2i(6, 0)).begins_with("Un seul"), "un seul véhicule de retour")
	_check(engine.capacity(R.METHANE) >= ColonyEngine.RETURN_METHANE, "le véhicule stocke le méthane du retour")
	var copy := ColonyState.from_dict(JSON.parse_string(JSON.stringify(engine.state.to_dict())))
	_check(copy.era == 2 and copy.sites_done == engine.state.sites_done and copy.expeditions == 1, "ère et expéditions sauvegardées")


# ---------- Poussière, pannes, fin des ravitaillements ----------

func _test_hazards() -> void:
	var engine := _rich_engine()
	var lander := engine.map.lander_cell
	engine.place("solar", lander + Vector2i(2, 0))
	var panel := engine.state.buildings.size() - 1
	var clean := engine._output_rate(panel, R.ENERGY, 1.0)
	engine.dust_rate = ColonyEngine.DUST_RATE
	engine.advance(10.0)
	_check(engine.dust_of(panel) > 0.05, "la poussière se dépose")
	_check(engine._output_rate(panel, R.ENERGY, 1.0) < clean, "panneau poussiéreux : moins d'énergie")
	engine.state.resources[R.OXYGEN] = 40.0
	var o2 := engine.state.amount(R.OXYGEN)
	var cost := engine.cleaning_cost()
	_check(cost > 0.0 and engine.clean_panels(), "sortie de nettoyage")
	_check(engine.dust_of(panel) == 0.0 and _near(engine.state.amount(R.OXYGEN), o2 - cost), "nettoyage : propre, oxygène dépensé")
	_check(engine.cleaning_problem() == "Les panneaux sont propres.", "rien à nettoyer")

	engine.place("moxie", lander + Vector2i(3, 0))
	var machine := engine.state.buildings.size() - 1
	engine.state.buildings[machine].broken = true
	engine.advance(0.1)
	_check(engine.efficiency(machine) == 0.0 and not engine.building_status(machine).ok, "machine en panne : à l'arrêt")
	var materials := engine.state.amount(R.MATERIALS)
	_check(engine.repair(machine) and not engine.is_broken(machine), "réparation")
	_check(_near(engine.state.amount(R.MATERIALS), materials - 9.0), "réparation : 30 % du prix")
	# En temps réel, le jeu avance par tout petits pas (une image) : la fréquence doit rester la même.
	var rates: Array[float] = []
	for step in [0.02, 0.0005]:
		var sim := _rich_engine()
		sim.state.sol = ColonyEngine.BREAKDOWN_START
		sim.breakdown_rate = 0.5
		for k in 20:
			sim.state.buildings.append({ "id": "moxie", "x": 1 + k, "y": 1, "level": 1 })
		sim._rebuild()
		for k in 20:
			sim._connected[sim.state.buildings.size() - 1 - k] = true
		var elapsed := 0.0
		while elapsed < 1.0:
			sim.advance(step)
			elapsed += step
		rates.append(float(sim.broken_count()))
	# Attendu : 20 × (1 − e^−0,5) ≈ 8 machines en panne, quel que soit le pas.
	_check(rates[0] >= 3.0 and rates[0] <= 14.0 and rates[1] >= 3.0 and rates[1] <= 14.0,
			"pannes indépendantes de la taille des pas (%d et %d sur 20)" % [rates[0], rates[1]])
	engine.breakdown_rate = 50.0
	engine.state.sol = maxf(engine.state.sol, ColonyEngine.BREAKDOWN_START)
	engine.advance(0.5)
	_check(engine.is_broken(machine), "les machines tombent en panne")
	_check(not engine.is_broken(panel), "les panneaux ne tombent pas en panne")
	var copy := ColonyState.from_dict(JSON.parse_string(JSON.stringify(engine.state.to_dict())))
	_check(copy.buildings[machine].get("broken") == true and copy.buildings[panel].has("dust"), "panne et poussière sauvegardées")

	var earth := _calm_engine()
	earth.state.resupply_count = ColonyEngine.RESUPPLY_LIMIT
	earth.state.next_resupply = earth.state.sol + 0.1
	var reports: Array[Dictionary] = []
	earth.resupply_arrived.connect(func(r: Dictionary) -> void: reports.append(r))
	var stock := earth.state.amount(R.MATERIALS)
	earth.advance(0.2)
	_check(_near(earth.state.amount(R.MATERIALS), stock) and earth.resupplies_left() == 0, "après six ravitaillements : plus de matériaux")
	# Sans four et sans matériaux : envoi de secours pour en construire un.
	earth.state.resources[R.MATERIALS] = 5.0
	earth.state.next_resupply = earth.state.sol + 0.1
	earth.advance(0.2)
	_check(_near(earth.state.amount(R.MATERIALS), earth.building_defs["kiln"].cost) and reports.back().rescue,
			"envoi de secours : de quoi construire un four")

	var kiln := _rich_engine()
	_check(kiln.place("kiln", kiln.map.lander_cell + Vector2i(2, 0)), "pose d'un four à régolithe")
	kiln.state.resources[R.ENERGY] = 60.0
	var before := kiln.state.amount(R.MATERIALS)
	kiln.advance(0.2)
	_check(kiln.state.amount(R.MATERIALS) > before, "le four fabrique des matériaux")


# ---------- Améliorations et note ----------

func _test_upgrades() -> void:
	var engine := _rich_engine()
	engine.state.resources[R.DATA] = 100.0
	var lander := engine.map.lander_cell
	for id: String in R.UPGRADES:
		_check(engine.building_defs.has(id) and R.UPGRADES[id].size() == 2, "améliorations d'un module connu : %s" % id)
	_check(engine.max_level(0) == 1 and engine.upgrade_problem(0) != "", "l'atterrisseur ne s'améliore pas")
	_check(engine.place("solar", lander + Vector2i(2, 0)), "pose d'un panneau")
	var panel := engine.state.buildings.size() - 1
	var cost := engine.upgrade_cost(panel)
	_check(_near(cost[R.MATERIALS], 12.0) and _near(cost[R.DATA], 15.0), "coût du niveau 2")
	var materials := engine.state.amount(R.MATERIALS)
	_check(engine.upgrade(panel) and engine.level_of(panel) == 2, "amélioration au niveau 2")
	_check(_near(engine.state.amount(R.MATERIALS), materials - 12.0) and _near(engine.state.amount(R.DATA), 85.0), "amélioration payée")
	_check(_near(engine._output_rate(panel, R.ENERGY, 1.0), 10.0 * 1.3), "triple jonction : +30 %")
	_check(engine.upgrade(panel) and engine.level_of(panel) == 3, "amélioration au niveau 3")
	_check(_near(engine._output_rate(panel, R.ENERGY, 1.0), 10.0 * 1.3 * 1.2), "suivi du soleil : +20 % de plus")
	_check(not engine.upgrade(panel) and engine.upgrade_problem(panel) == "Niveau maximal atteint.", "niveau maximal")
	var housing := engine.housing()
	_check(engine.place("habitat", lander + Vector2i(3, 0)), "pose d'un habitat")
	var home := engine.state.buildings.size() - 1
	engine.state.resources[R.DATA] = 100.0
	engine.upgrade(home)
	engine.upgrade(home)
	_check(engine.housing() == housing + 4 + 2, "extension gonflable : +2 places")
	engine.state.resources[R.DATA] = 0.0
	engine.place("battery", lander + Vector2i(5, 0))
	_check(engine.upgrade_problem(engine.state.buildings.size() - 1).begins_with("Pas assez"), "données insuffisantes")
	var rating := engine.colony_rating()
	_check(rating.score > 0.0 and rating.score <= 100.0 and rating.grade in ["A", "B", "C", "D", "E"], "note de la colonie")
	_check(rating.parts.size() == 4, "note détaillée")
	var copy := ColonyState.from_dict(JSON.parse_string(JSON.stringify(engine.state.to_dict())))
	_check(int(copy.buildings[panel].level) == 3, "niveau sauvegardé")


# ---------- Fiches ----------

func _test_cards() -> void:
	var engine := _calm_engine()
	for card: Defs.Card in engine.cards.values():
		_check(not card.figure.is_empty() and engine.building_defs.has(card.visual), "fiche illustrée : %s" % card.id)
		_check(card.choices.size() == 3 and card.answer >= 0 and card.answer < 3, "quiz valide : %s" % card.id)
	var data := engine.state.amount(R.DATA)
	_check(engine.unread_cards() == 2, "deux fiches de départ à lire")
	_check(_near(engine.read_card("atmosphere"), ColonyEngine.CARD_READ_REWARD), "première lecture récompensée")
	_check(engine.read_card("atmosphere") == 0.0, "relecture sans récompense")
	_check(engine.read_card("moxie") == 0.0, "fiche verrouillée : pas de récompense")
	_check(_near(engine.state.amount(R.DATA), data + ColonyEngine.CARD_READ_REWARD), "données de lecture créditées")
	var card: Defs.Card = engine.cards["atmosphere"]
	_check(engine.answer_quiz("atmosphere", card.answer), "bonne réponse au quiz")
	_check(engine.answer_quiz("atmosphere", (card.answer + 1) % 3), "une seule tentative : la première compte")
	_check(not engine.answer_quiz("oxygen_need", (engine.cards["oxygen_need"].answer + 1) % 3), "mauvaise réponse")
	_check(engine.quiz_score() == 1, "score du quiz")
	_check(_near(engine.state.amount(R.DATA), data + ColonyEngine.CARD_READ_REWARD + ColonyEngine.QUIZ_REWARD), "données du quiz créditées")
	var copy := ColonyState.from_dict(JSON.parse_string(JSON.stringify(engine.state.to_dict())))
	_check(copy.cards_read == engine.state.cards_read and copy.quiz_answers == engine.state.quiz_answers, "lectures et quiz sauvegardés")


# ---------- Synergies ----------

func _test_synergies() -> void:
	var engine := _rich_engine()
	var lander := engine.map.lander_cell
	for synergy: Dictionary in R.SYNERGIES:
		_check(engine.building_defs.has(synergy.building) and engine.building_defs.has(synergy.neighbor),
				"synergie entre modules connus : %s" % synergy.id)
	_check(engine.place("habitat", lander + Vector2i(2, 0)), "pose d'un habitat")
	var first := engine.state.buildings.size() - 1
	_check(engine.synergies_of(first).is_empty(), "habitat seul : pas de synergie")
	var preview := engine.preview_synergies("habitat", lander + Vector2i(4, 0))
	_check(preview.size() == 2, "aperçu : murs mitoyens pour les deux habitats")
	_check(engine.place("habitat", lander + Vector2i(4, 0)), "pose d'un second habitat collé")
	var second := engine.state.buildings.size() - 1
	_check(engine.synergies_of(first).size() == 1 and engine.synergies_of(second).size() == 1, "murs mitoyens actifs")
	var base: float = engine.def_of(first).inputs[R.ENERGY]
	_check(_near(engine._input_rate(first, R.ENERGY), base * 0.75), "murs mitoyens : −25 % d'énergie")
	_check(engine.active_synergy_count() == 2, "deux synergies actives")
	var green := engine.preview_synergies("greenhouse", lander + Vector2i(6, 0))
	_check(green.size() == 1 and green[0].synergy.id == "greenhouse_habitat", "aperçu : serre collée à l'habitat")
	_check(engine.place("greenhouse", lander + Vector2i(6, 0)), "pose de la serre")
	var house := engine.state.buildings.size() - 1
	var food: float = engine.def_of(house).outputs[R.FOOD]
	_check(_near(engine._output_rate(house, R.FOOD, 1.0), food * 1.25 * engine.effect("food")), "serre + habitat : +25 % de nourriture")
	_check(engine.demolish(second), "démolition du second habitat")
	_check(engine.synergies_of(first).is_empty(), "sans voisin, la synergie disparaît")


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
	_check(_near(flows[R.ENERGY], 10.0 - 0.5 * 4), "bilan : l'atterrisseur produit 10 kWh, les 4 colons en utilisent 2")

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

	var summary := loaded.summary()
	_check(summary.sol == int(loaded.sol) + 1 and summary.colonists == 4 and summary.modules == loaded.buildings.size() - 1,
			"résumé de sauvegarde")
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
	# Les objectifs de l'ère 4 demandent plusieurs colonies : testés à part (_test_campaign).
	var mars_objectives := 0
	for objective in engine.objectives:
		if objective.era <= 3:
			mars_objectives += 1
	while engine.state.sol < 260.0 and done.size() < mars_objectives:
		ColonyBot.research(engine)
		ColonyBot.maintain(engine)
		ColonyBot.build(engine)
		engine.advance(0.25)

	print("\n--- Campagne « Survie » (joueur simulé) ---")
	for objective in engine.objectives:
		print("%-14s %s" % [objective.id, "sol %.1f" % done[objective.id] if done.has(objective.id) else "non atteint"])
	print("Évacuations : %d, colons : %d, modules : %d" % [evacuations[0], engine.state.colonists.size(), engine.state.buildings.size()])
	_check(done.get("first_breath", INF) <= 3.0, "premier oxygène avant le sol 3")
	_check(done.get("water", INF) <= 10.0, "eau avant le sol 10")
	_check(done.get("autonomy", INF) >= 20.0 and done.get("autonomy", INF) <= 70.0, "autonomie entre les sols 20 et 70")
	var era1 := 0.0
	for objective in engine.objectives:
		if objective.era == 1:
			era1 = maxf(era1, done.get(objective.id, INF))
	_check(era1 <= 80.0, "ère 1 accomplie avant le sol 80")
	var era2 := 0.0
	for objective in engine.objectives:
		if objective.era == 2:
			era2 = maxf(era2, done.get(objective.id, INF))
	_check(era2 <= 160.0, "ère 2 accomplie avant le sol 160")
	_check(done.size() >= mars_objectives and done.values().max() <= 250.0, "ère 3 accomplie avant le sol 250")
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


## Ère 1 jouée comme sur le téléphone : vitesse ×4, un tout petit pas par image (60 images/s).
## Les événements aléatoires doivent garder la même fréquence qu'en gros pas (bug des pannes, sol 83).
func _simulate_realtime() -> void:
	var engine := _engine()
	var frame := 4.0 / (60.0 * ColonyEngine.SECONDS_PER_SOL)
	var breakdowns := [0]
	var evacuations := [0]
	engine.breakdown.connect(func(_i: int) -> void: breakdowns[0] += 1)
	engine.colonist_evacuated.connect(func(_n: String, _c: String) -> void: evacuations[0] += 1)
	var machine_sols := 0.0
	var started := Time.get_ticks_msec()
	while engine.state.sol < 80.0 and not engine.state.objectives_done.has("autonomy"):
		ColonyBot.research(engine)
		ColonyBot.maintain(engine)
		ColonyBot.build(engine)
		var machines := 0
		for building in engine.state.buildings:
			if building.id in R.BREAKABLE:
				machines += 1
		var until := engine.state.sol + 0.25
		while engine.state.sol < until:
			engine.advance(frame)
		if engine.state.sol > ColonyEngine.BREAKDOWN_START:
			machine_sols += machines * 0.25
	var expected := machine_sols * ColonyEngine.BREAKDOWN_RATE
	print("\n--- Ère 1 en temps réel (×4, une image = %.5f sol) : %.1f s ---" % [frame, (Time.get_ticks_msec() - started) / 1000.0])
	print("Autonomie au sol %.1f · pannes %d (attendu ≈ %.1f) · évacuations %d" % [
		engine.state.sol, breakdowns[0], expected, evacuations[0]])
	_check(engine.state.objectives_done.has("autonomy") and engine.state.sol <= 75.0, "temps réel : autonomie atteinte")
	_check(evacuations[0] == 0, "temps réel : aucune évacuation")
	_check(breakdowns[0] <= expected * 2.5 + 3.0, "temps réel : pannes à la fréquence prévue")
