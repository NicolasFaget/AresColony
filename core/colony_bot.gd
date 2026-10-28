class_name ColonyBot
extends RefCounted
## Joueur simulé raisonnable, utilisé par les tests (rythme, équilibrage), les captures d'écran
## et la colonie de démonstration du menu principal :
## construit ce qui manque le plus, garde une réserve de matériaux, étend ses conduites vers la glace.

const R = preload("res://core/colony_content.gd")
const RESEARCH_ORDER := ["moxie", "ice", "batteries", "greenhouse", "electrolysis", "recycling", "cleaning", "perchlorate", "regolith", "sabatier", "rovers", "erv", "solid_state", "shielding", "fission", "soil", "closed_loop", "spaceport", "brines", "cryogenics", "buffer_gas", "predictive"]


## Lance la prochaine recherche disponible, dans l'ordre conseillé.
static func research(engine: ColonyEngine) -> void:
	for id in RESEARCH_ORDER:
		if engine.research_state(id) == "available":
			engine.start_research(id)
			return


## Joue jusqu'au sol `until` (recherche et construction tous les quarts de sol).
static func play(engine: ColonyEngine, until: float) -> void:
	while engine.state.sol < until:
		research(engine)
		maintain(engine)
		build(engine)
		engine.advance(0.25)


## Première case libre où le module serait posé et raccordé.
static func connected_spot(engine: ColonyEngine, def_id: String, near := Vector2i(-1, -1)) -> Vector2i:
	var target := engine.map.lander_cell if near.x < 0 else near
	var best := Vector2i(-1, -1)
	var best_distance := INF
	for y in ColonyMap.SIZE:
		for x in ColonyMap.SIZE:
			var cell := Vector2i(x, y)
			if engine.placement_problem(def_id, cell).is_empty() and engine.would_connect(def_id, cell):
				var d := Vector2(cell).distance_to(Vector2(target))
				if d < best_distance:
					best_distance = d
					best = cell
	return best


static func build(engine: ColonyEngine) -> void:
	var flows := engine.average_flows()
	var want := ""
	# Ressource vitale la plus urgente (réserve la plus courte), si son bilan est négatif.
	var urgent := ""
	var shortest := INF
	# Marge pour accueillir les prochaines recrues.
	var margin := { R.OXYGEN: 2.0, R.WATER: 6.0, R.FOOD: 2.5 }
	for r in [R.OXYGEN, R.WATER, R.FOOD]:
		if flows[r] < margin[r]:
			var days: float = engine.state.amount(r) / maxf(0.01, -flows[r])
			var producer: String = { R.OXYGEN: _oxygen_maker(engine), R.WATER: "extractor", R.FOOD: "greenhouse" }[r]
			if days < shortest and engine.is_unlocked(engine.building_defs[producer]):
				shortest = days
				urgent = r
	var outpost := _is_outpost(engine)
	# Avant-poste sans source de matériaux : le four d'abord, sauf urgence vitale imminente.
	if outpost and shortest > 3.0 and _count(engine, "kiln") == 0 and _count(engine, "brine") == 0 			and engine.is_unlocked(engine.building_defs["kiln"]):
		var spot := connected_spot(engine, "kiln")
		if spot.x >= 0:
			engine.place("kiln", spot)
		return
	if flows[R.ENERGY] < 4.0 and not engine.is_storm():
		want = _energy_maker(engine)
		if want.is_empty():
			return
	elif urgent == R.OXYGEN:
		if engine.planet().forbidden.has("moxie"):
			# Sans CO₂ : l'oxygène vient de l'eau, il faut donc d'abord de l'eau.
			want = "electrolyser" if flows[R.WATER] > 4.0 else "extractor"
		else:
			want = "electrolyser" if engine.is_unlocked(engine.building_defs["electrolyser"]) and flows[R.WATER] > 4.0 else "moxie"
	elif urgent == R.WATER:
		want = "extractor"
		for i in engine.state.buildings.size():
			if engine.state.buildings[i].id == "extractor" and engine.upgrade_problem(i).is_empty():
				engine.upgrade(i)
				return
	elif urgent == R.FOOD:
		want = "greenhouse"
	elif outpost and engine.planet_id() == "ceres" and engine.is_unlocked(engine.building_defs["brine"]) and _count(engine, "brine") < 2:
		want = "brine"
	elif outpost and engine.planet_id() == "titan" and engine.is_unlocked(engine.building_defs["methane_pump"]) and _count(engine, "methane_pump") < 2:
		want = "methane_pump"
	elif outpost and engine.is_unlocked(engine.building_defs["garage"]) and _count(engine, "garage") == 0 \
			and engine.state.amount(R.MATERIALS) >= 130.0:
		want = "garage"
	elif outpost and engine.is_unlocked(engine.building_defs["kiln"]) and _count(engine, "kiln") < 2:
		want = "kiln"
	# Avant-poste équipé : un astroport pour exporter, et de quoi stocker le méthane.
	elif outpost and _count(engine, "garage") > 0 and _count(engine, "tank") == 0 and engine.is_unlocked(engine.building_defs["tank"]):
		want = "tank"
	elif outpost and _count(engine, "garage") > 0 and not engine.has_spaceport() and engine.is_unlocked(engine.building_defs["spaceport"]) \
			and engine.state.amount(R.MATERIALS) >= 200.0:
		want = "spaceport"
	elif outpost and engine.planet_id() == "titan" and engine.has_spaceport() and _count(engine, "tank") < 2:
		want = "tank"
	elif outpost and engine.planet_id() == "titan" and engine.has_spaceport() and _count(engine, "n2_compressor") < 2 \
			and engine.is_unlocked(engine.building_defs["n2_compressor"]):
		want = "n2_compressor"
	elif outpost and engine.capacity(R.ENERGY) < 150.0 and engine.is_unlocked(engine.building_defs["battery"]):
		want = "battery"
	elif outpost:
		want = ""
	elif engine.is_unlocked(engine.building_defs["kiln"]) and engine.resupplies_left() <= 2 \
			and _count(engine, "kiln") < 1 + engine.state.colonists.size() / 4:
		want = "kiln"
	elif engine.is_unlocked(engine.building_defs["dome"]) and _count(engine, "dome") == 0:
		want = "dome"
	elif engine.state.era >= 3 and engine.is_unlocked(engine.building_defs["bunker"]) \
			and engine.state.colonists.size() >= engine.housing() - 1 and engine.recruits_left() > 0:
		want = "bunker"
	elif engine.state.colonists.size() >= engine.housing() - 1 and engine.recruits_left() > 0 			and flows[R.OXYGEN] >= margin[R.OXYGEN] and flows[R.FOOD] >= margin[R.FOOD]:
		want = "habitat"
	elif engine.is_unlocked(engine.building_defs["bunker"]) and engine.shelter_capacity() < engine.state.colonists.size():
		want = "bunker"
	elif engine.is_unlocked(engine.building_defs["reactor"]) and _count(engine, "reactor") == 0:
		want = "reactor"
	elif engine.is_unlocked(engine.building_defs["biodome"]) and _count(engine, "biodome") < 2:
		want = "biodome"
	elif engine.is_unlocked(engine.building_defs["garage"]) and _count(engine, "garage") == 0:
		want = "garage"
	elif engine.is_unlocked(engine.building_defs["sabatier"]) and _count(engine, "sabatier") < 3 \
			and flows[R.WATER] > 5.0:
		want = "sabatier"
	elif engine.is_unlocked(engine.building_defs["erv"]) and _count(engine, "erv") == 0:
		want = "erv"
	elif engine.is_unlocked(engine.building_defs["spaceport"]) and _count(engine, "spaceport") == 0:
		want = "spaceport"
	# Capitale (ère 4) : de grands dômes pour la seconde vague, et un compresseur d'appoint.
	elif engine.is_unlocked(engine.building_defs["dome"]) and engine.recruits_left() > 0 \
			and engine.state.colonists.size() >= engine.housing() - 1 and _count(engine, "dome") < 2 and _domes_ready(engine):
		want = "dome"
	elif engine.is_unlocked(engine.building_defs["dome"]) and _count(engine, "dome") > 0 and _count(engine, "n2_compressor") == 0:
		want = "n2_compressor"
	# Ère 4 : de quoi remplir les vols vers Cérès et Titan.
	elif engine.has_spaceport() and engine.capacity(R.METHANE) < 500.0 and engine.is_unlocked(engine.building_defs["tank"]):
		want = "tank"
	elif engine.capacity(R.ENERGY) < 150.0 and engine.is_unlocked(engine.building_defs["battery"]):
		want = "battery"
	if want.is_empty():
		# Un avant-poste garde ses matériaux pour l'essentiel avant d'améliorer.
		if not outpost or engine.state.amount(R.MATERIALS) >= 200.0:
			upgrade(engine)
		return
	if not engine.is_unlocked(engine.building_defs[want]):
		return
	# Confort (habitat, batteries) : seulement si une réserve reste pour les urgences vitales.
	if want in ["habitat", "battery", "garage", "erv", "sabatier", "bunker", "reactor", "biodome", "spaceport", "tank", "dome", "n2_compressor"] and engine.state.amount(R.MATERIALS) < engine.building_defs[want].cost + 50.0:
		return
	if want in ["extractor", "brine", "methane_pump"] and not (want == "extractor" and engine.planet().ice_everywhere):
		reach_ice(engine, want)
		return
	var spot := connected_spot(engine, want)
	if spot.x >= 0:
		engine.place(want, spot)


## Répare les machines en panne et nettoie les panneaux trop poussiéreux.
static func maintain(engine: ColonyEngine) -> void:
	for i in engine.state.buildings.size():
		if engine.is_broken(i):
			engine.repair(i)
	if engine.average_dust() > 0.3:
		engine.clean_panels()
	if engine.state.amount(R.METHANE) >= 30.0 and engine.state.expeditions < 4:
		engine.start_expedition()


static func _count(engine: ColonyEngine, def_id: String) -> int:
	var count := 0
	for building in engine.state.buildings:
		if building.id == def_id:
			count += 1
	return count


## Ère 4 : joue toutes les colonies, fonde Cérès puis Titan, et fait circuler les cargaisons
## (matériaux de Cérès vers Mars, méthane de Mars vers Cérès, méthane de Titan vers le réseau).
static func network(campaign: Campaign) -> void:
	for colony in campaign.engines:
		research(colony)
		maintain(colony)
		build(colony)
	if not campaign.interplanetary_unlocked():
		return
	var planets := []
	for i in campaign.colonies.size():
		planets.append(campaign.planet_of(i))
	for shipment in campaign.shipments:
		if shipment.kind == "colony":
			planets.append(Campaign.planet_of_region(shipment.region))
	for region in ["ceres", "titan"]:
		if not planets.has(region):
			campaign.found_colony(0, region)
			break
	var mars := campaign.engines[0]
	for i in range(1, campaign.engines.size()):
		var colony := campaign.engines[i]
		match campaign.planet_of(i):
			"ceres":
				# Une seule fusée pour les matériaux et l'azote : le vol coûte du méthane, rare ici.
				var spare := colony.state.amount(R.MATERIALS) - 120.0
				var nitrogen := colony.state.amount(R.NITROGEN) - 5.0
				var send_nitrogen := nitrogen >= 30.0 and _needs_nitrogen(mars)
				var shipped := false
				if spare >= 40.0:
					for to in _by_free_space(campaign, R.MATERIALS, i):
						var cargo := { R.MATERIALS: minf(spare, 150.0) }
						if to == 0 and send_nitrogen:
							cargo[R.NITROGEN] = nitrogen
						if _ship_cargo(campaign, i, to, cargo):
							shipped = to == 0 and send_nitrogen
							break
				if send_nitrogen and not shipped:
					_ship(campaign, i, 0, R.NITROGEN, nitrogen)
				# Cérès n'a pas de méthane : Mars lui en envoie, une fois Titan fondée.
				if planets.has("titan") and colony.state.amount(R.METHANE) < 80.0 and colony.capacity(R.METHANE) >= 150.0 \
						and mars.state.amount(R.METHANE) >= 300.0:
					_ship(campaign, 0, i, R.METHANE, 150.0)
			"titan":
				var nitrogen := colony.state.amount(R.NITROGEN) - 20.0
				if nitrogen >= 60.0 and _needs_nitrogen(mars):
					_ship(campaign, i, 0, R.NITROGEN, nitrogen)
				var stock := colony.state.amount(R.METHANE) - 30.0
				if stock >= 150.0:
					for to in _by_free_space(campaign, R.METHANE, i):
						if _ship(campaign, i, to, R.METHANE, stock):
							break


## Autres colonies, de celle qui a le plus de place libre pour `resource` à celle qui en a le moins.
static func _by_free_space(campaign: Campaign, resource: String, from: int) -> Array:
	var list := []
	for k in campaign.engines.size():
		if k != from:
			list.append(k)
	var free := func(k: int) -> float:
		var colony := campaign.engines[k]
		return colony.capacity(resource) - colony.state.amount(resource) - colony.incoming.get(resource, 0.0)
	list.sort_custom(func(a: int, b: int) -> bool: return free.call(a) > free.call(b))
	return list


## Mars a de la place pour de l'azote et en manque (moins de la moitié de ses réservoirs, livraisons comprises).
static func _needs_nitrogen(mars: ColonyEngine) -> bool:
	var room := mars.capacity(R.NITROGEN)
	return room > 0.0 and mars.state.amount(R.NITROGEN) + mars.incoming.get(R.NITROGEN, 0.0) < room * 0.5


## Les dômes déjà posés sont pressurisés (on n'en ajoute pas un vide de plus).
static func _domes_ready(engine: ColonyEngine) -> bool:
	for i in engine.state.buildings.size():
		if engine.state.buildings[i].id == "dome" and not engine.is_pressurized(i):
			return false
	return true


## Envoie jusqu'à `amount` de `resource` (moins si le méthane du vol ou la place manque).
static func _ship(campaign: Campaign, from: int, to: int, resource: String, amount: float) -> bool:
	return _ship_cargo(campaign, from, to, { resource: amount })


## Envoie la cargaison, réduite de 20 % en 20 % tant qu'elle ne passe pas (place, méthane du vol).
static func _ship_cargo(campaign: Campaign, from: int, to: int, cargo: Dictionary) -> bool:
	var scale := 1.0
	while scale > 0.1:
		var sized := {}
		var total := 0.0
		for r: String in cargo:
			sized[r] = cargo[r] * scale
			total += sized[r]
		if total < 20.0:
			return false
		if campaign.shipment_problem(from, to, sized, 0).is_empty():
			return campaign.send_cargo(from, to, sized, 0)
		scale *= 0.8
	return false


## Améliore le module le moins cher, en gardant une réserve de matériaux et de données pour la recherche.
static func upgrade(engine: ColonyEngine) -> void:
	var best := -1
	var best_cost := INF
	for i in engine.state.buildings.size():
		if not engine.upgrade_problem(i).is_empty():
			continue
		var cost: Dictionary = engine.upgrade_cost(i)
		if engine.state.amount(R.MATERIALS) < cost[R.MATERIALS] + 80.0 or engine.state.amount(R.DATA) < cost[R.DATA] + 20.0:
			continue
		if cost[R.MATERIALS] < best_cost:
			best_cost = cost[R.MATERIALS]
			best = i
	if best >= 0:
		engine.upgrade(best)


## Pose l'extracteur sur la glace si possible, sinon prolonge les conduites vers la glace.
## Monde sans CO₂ (Cérès, Titan) : l'oxygène vient de l'électrolyse de l'eau.
static func _oxygen_maker(engine: ColonyEngine) -> String:
	return "electrolyser" if engine.planet().forbidden.has("moxie") else "moxie"


## Énergie : des panneaux, ou un réacteur quand le soleil est trop faible ("" : attendre).
static func _energy_maker(engine: ColonyEngine) -> String:
	if engine.effect("solar") >= 0.5:
		return "solar"
	if engine.is_unlocked(engine.building_defs["reactor"]) \
			and engine.state.amount(R.MATERIALS) >= engine.building_defs["reactor"].cost:
		return "reactor"
	return "solar" if engine.effect("solar") >= 0.2 else ""


## Avant-poste d'un autre monde (fondé par le réseau, sans ravitaillement ni volontaires de la Terre).
static func _is_outpost(engine: ColonyEngine) -> bool:
	return engine.planet_id() != "mars" and engine.state.recruits_sent >= R.RECRUITS.size()


static func reach_ice(engine: ColonyEngine, def_id := "extractor") -> void:
	var ice := engine.map.ice_cells()
	var lander := Vector2(engine.map.lander_cell)
	ice.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return Vector2(a).distance_to(lander) < Vector2(b).distance_to(lander))
	for cell in ice:
		if engine.placement_problem(def_id, cell).is_empty() and engine.would_connect(def_id, cell):
			engine.place(def_id, cell)
			return
	# Conduites vers la plaque de glace libre la plus proche (et pas de réseau sans fin).
	if _count(engine, "link") >= 30:
		return
	for cell in ice:
		if engine.placement_problem(def_id, cell).is_empty():
			var spot := connected_spot(engine, "link", cell)
			if spot.x >= 0:
				engine.place("link", spot)
			return
