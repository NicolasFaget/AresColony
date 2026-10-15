class_name ColonyBot
extends RefCounted
## Joueur simulé raisonnable, utilisé par les tests (rythme, équilibrage), les captures d'écran
## et la colonie de démonstration du menu principal :
## construit ce qui manque le plus, garde une réserve de matériaux, étend ses conduites vers la glace.

const R = preload("res://core/colony_content.gd")
const RESEARCH_ORDER := ["moxie", "ice", "batteries", "greenhouse", "electrolysis", "recycling", "cleaning", "perchlorate"]


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
			var producer: String = { R.OXYGEN: "moxie", R.WATER: "extractor", R.FOOD: "greenhouse" }[r]
			if days < shortest and engine.is_unlocked(engine.building_defs[producer]):
				shortest = days
				urgent = r
	if flows[R.ENERGY] < 4.0:
		want = "solar"
	elif urgent == R.OXYGEN:
		want = "electrolyser" if engine.is_unlocked(engine.building_defs["electrolyser"]) and flows[R.WATER] > 4.0 else "moxie"
	elif urgent == R.WATER:
		want = "extractor"
	elif urgent == R.FOOD:
		want = "greenhouse"
	elif engine.state.colonists.size() >= engine.housing() - 1 and engine.state.recruits_sent < R.RECRUITS.size() 			and flows[R.OXYGEN] >= margin[R.OXYGEN] and flows[R.FOOD] >= margin[R.FOOD]:
		want = "habitat"
	elif engine.capacity(R.ENERGY) < 150.0 and engine.is_unlocked(engine.building_defs["battery"]):
		want = "battery"
	if want.is_empty():
		upgrade(engine)
		return
	if not engine.is_unlocked(engine.building_defs[want]):
		return
	# Confort (habitat, batteries) : seulement si une réserve reste pour les urgences vitales.
	if want in ["habitat", "battery"] and engine.state.amount(R.MATERIALS) < engine.building_defs[want].cost + 50.0:
		return
	if want == "extractor":
		reach_ice(engine)
		return
	var spot := connected_spot(engine, want)
	if spot.x >= 0:
		engine.place(want, spot)


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
static func reach_ice(engine: ColonyEngine) -> void:
	var ice := engine.map.ice_cells()
	var lander := Vector2(engine.map.lander_cell)
	ice.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return Vector2(a).distance_to(lander) < Vector2(b).distance_to(lander))
	for cell in ice:
		if engine.placement_problem("extractor", cell).is_empty() and engine.would_connect("extractor", cell):
			engine.place("extractor", cell)
			return
	var spot := connected_spot(engine, "link", ice[0])
	if spot.x >= 0:
		engine.place("link", spot)
