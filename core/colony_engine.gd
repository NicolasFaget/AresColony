class_name ColonyEngine
extends RefCounted
## Simulation de la colonie : flux de ressources, jour et nuit, raccordements, recherche,
## colons, événements (tempêtes, ravitaillements), objectifs et pilote automatique hors-ligne.
## Ne connaît ni les nœuds ni le disque : l'horloge et le stockage sont fournis par l'appelant.

## Émis après toute action du joueur (pas à chaque pas de simulation).
signal changed
signal building_placed(index: int)
signal research_completed(research_id: String)
signal card_unlocked(card_id: String)
signal objective_completed(objective_id: String)
signal colonist_evacuated(colonist_name: String, cause: String)
signal colonist_arrived(colonist_name: String)
signal storm_warning
signal storm_started
signal storm_ended
signal resupply_arrived(report: Dictionary)
## Une ressource vitale vient d'être épuisée.
signal shortage(resource: String)

## Durée d'un sol en jeu, à vitesse ×1 (secondes réelles).
const SECONDS_PER_SOL := 60.0
const SPEEDS: Array[int] = [0, 1, 2, 4]
## Pas de simulation (sols).
const STEP := 0.02
## Les panneaux ne reçoivent plus que 20 % de la lumière pendant une tempête.
const STORM_SOLAR := 0.2
const STORM_WARNING_SOLS := 1.0
const RESUPPLY_INTERVAL := 8.0
const RESUPPLY_MATERIALS := 120.0
## Hors-ligne : le temps s'écoule plus lentement (un sol toutes les 20 minutes), 8 h au plus.
const OFFLINE_SECONDS_PER_SOL := 1200.0
const OFFLINE_CAP_SECONDS := 8.0 * 3600.0
## Démolition : une partie des matériaux est récupérée.
const DEMOLISH_REFUND := 0.5
const AUTONOMY_GOAL := 10.0
const AUTONOMY_CREW := 8

const START_RESOURCES := {
	ColonyContent.ENERGY: 30.0, ColonyContent.OXYGEN: 30.0, ColonyContent.WATER: 80.0,
	ColonyContent.FOOD: 50.0, ColonyContent.MATERIALS: 180.0, ColonyContent.DATA: 10.0,
}

## Explications données au joueur quand un colon est évacué.
const CAUSES := {
	ColonyContent.OXYGEN: "Manque d'oxygène. Construisez des électrolyseurs et donnez-leur assez d'énergie, jour et nuit.",
	ColonyContent.WATER: "Manque d'eau. Recherchez la glace souterraine et posez un extracteur dessus.",
	ColonyContent.FOOD: "Manque de nourriture. Les ravitaillements diminuent : il faut des serres.",
}

var state: ColonyState
var map: ColonyMap
var building_defs := {}
var research_defs := {}
var cards := {}
var objectives: Array[Defs.Objective] = []

var _connected: Array[bool] = []
var _efficiency: Array[float] = []
var _occupied := {}
var _rng := RandomNumberGenerator.new()
var _storm_warned := false
var _shortage_flags := {}
var _autopilot := false


func _init(p_state: ColonyState) -> void:
	state = p_state
	for def in ColonyContent.buildings():
		building_defs[def.id] = def
	for r in ColonyContent.research():
		research_defs[r.id] = r
	for card in ColonyContent.cards():
		cards[card.id] = card
	objectives = ColonyContent.objectives()
	map = ColonyMap.new(state.map_seed)
	_rng.seed = state.map_seed
	_rng.state = state.event_seed
	if state.buildings.is_empty():
		_new_game()
	_rebuild()


func _new_game() -> void:
	state.buildings = [{ "id": "lander", "x": map.lander_cell.x, "y": map.lander_cell.y }] as Array[Dictionary]
	state.resources = START_RESOURCES.duplicate()
	for member: Array in ColonyContent.CREW:
		state.colonists.append({ "name": member[0], "role": member[1], "health": 1.0 })
	state.cards_unlocked = ["atmosphere", "oxygen_need"] as Array[String]
	state.next_storm = 12.0 + _rng.randf_range(0.0, 4.0)
	state.event_seed = _rng.state


# ---------- Lecture ----------

func def_of(index: int) -> Defs.Building:
	return building_defs[state.buildings[index].id]


func cell_of(index: int) -> Vector2i:
	return Vector2i(state.buildings[index].x, state.buildings[index].y)


func is_linked(index: int) -> bool:
	return _connected[index]


func efficiency(index: int) -> float:
	return _efficiency[index]


func building_at(cell: Vector2i) -> int:
	return _occupied.get(cell, -1)


func capacity(resource: String) -> float:
	if resource == ColonyContent.DATA:
		return INF
	var total := 0.0
	for i in state.buildings.size():
		if _connected[i]:
			total += def_of(i).storage.get(resource, 0.0)
	return total


func housing() -> int:
	var total := 0
	for i in state.buildings.size():
		if _connected[i]:
			total += def_of(i).housing
	return total


func is_storm() -> bool:
	return state.storm_until > 0.0 and state.sol < state.storm_until


## Numéro du sol (commence à 1) et heure locale (un sol dure 24 h 39 min).
func sol_number() -> int:
	return int(state.sol) + 1


func time_of_day() -> float:
	return fposmod(state.sol, 1.0)


func is_night() -> bool:
	var t := time_of_day()
	return t < 0.25 or t > 0.75


## Multiplicateur de la lumière reçue par les panneaux (moyenne de 1 sur un sol par beau temps).
func sunlight() -> float:
	var daylight := maxf(0.0, cos(TAU * (time_of_day() - 0.5))) * PI
	return daylight * _storm_factor() * effect("solar")


func effect(key: String) -> float:
	var value := 1.0
	for id in state.research_done:
		var r: Defs.Research = research_defs.get(id)
		if r != null:
			value *= r.effects.get(key, 1.0)
	return value


func colonist_needs() -> Dictionary:
	var needs := ColonyContent.COLONIST_NEEDS.duplicate()
	needs[ColonyContent.WATER] *= effect("colonist_water")
	return needs


func is_unlocked(def: Defs.Building) -> bool:
	return def.research.is_empty() or state.research_done.has(def.research)


func buildable_defs() -> Array[Defs.Building]:
	var list: Array[Defs.Building] = []
	for def: Defs.Building in building_defs.values():
		if not def.fixed:
			list.append(def)
	return list


## Bilan moyen par sol de chaque ressource, si tous les modules raccordés tournent à plein
## (ensoleillement moyen, tempête comprise). Sert à l'affichage et à l'objectif « Autonomie ».
func average_flows() -> Dictionary:
	var flows := {}
	for r in ColonyContent.RESOURCES:
		flows[r] = 0.0
	var sun := _storm_factor() * effect("solar")
	for i in state.buildings.size():
		if not _connected[i]:
			continue
		var def := def_of(i)
		for r: String in def.inputs:
			flows[r] -= def.inputs[r]
		for r: String in def.outputs:
			flows[r] += _output_rate(def, r, sun)
	var count := state.colonists.size()
	var needs := colonist_needs()
	for r: String in needs:
		flows[r] -= needs[r] * count
	flows[ColonyContent.DATA] += ColonyContent.COLONIST_DATA * count
	return flows


## État d'un module, pour l'affichage : { "ok": bool, "text": String }.
func building_status(index: int) -> Dictionary:
	var def := def_of(index)
	if not _connected[index]:
		return { "ok": false, "text": "Non raccordé : collez-le à un module relié à l'atterrisseur." }
	if not def.inputs.is_empty():
		var e := _efficiency[index]
		if e < 0.999:
			var missing: String = ColonyContent.RESOURCE_PARTITIVE[_scarcest_input(def)]
			if e <= 0.001:
				return { "ok": false, "text": "À l'arrêt : manque %s." % missing }
			return { "ok": false, "text": "Ralenti à %d %% : manque %s." % [roundi(e * 100.0), missing] }
	if def.solar:
		if is_storm():
			return { "ok": true, "text": "Tempête : la poussière masque le soleil." }
		if is_night():
			return { "ok": true, "text": "Nuit : aucune production solaire." }
	return { "ok": true, "text": "En service." }


func research_state(research_id: String) -> String:
	if state.research_done.has(research_id):
		return "done"
	if state.research_active == research_id:
		return "active"
	var r: Defs.Research = research_defs[research_id]
	for req: String in r.requires:
		if not state.research_done.has(req):
			return "locked"
	return "available"


# ---------- Construction ----------

## Raison pour laquelle le module ne peut pas être posé là, ou "" s'il peut l'être.
func placement_problem(def_id: String, cell: Vector2i) -> String:
	var def: Defs.Building = building_defs.get(def_id)
	if def == null or def.fixed:
		return "Module inconnu."
	if not is_unlocked(def):
		return "Recherche nécessaire : %s." % research_defs[def.research].name
	var ice := 0
	for c in _footprint(cell, def.size):
		if not map.in_bounds(c):
			return "Hors du cratère."
		if not map.is_buildable(c):
			return "Terrain impossible : rochers ou rebord du cratère."
		if _occupied.has(c):
			return "Emplacement déjà occupé."
		if map.tile_at(c) == ColonyMap.Tile.ICE:
			ice += 1
	if def.requires_tile == ColonyMap.Tile.ICE and ice < 2:
		return "À poser sur une plaque de glace (au moins 2 cases)."
	if state.amount(ColonyContent.MATERIALS) < def.cost:
		return "Matériaux insuffisants (%s nécessaires)." % NumberFormatter.format(def.cost)
	return ""


## Le module serait-il raccordé s'il était posé là ?
func would_connect(def_id: String, cell: Vector2i) -> bool:
	var def: Defs.Building = building_defs.get(def_id)
	if def == null:
		return false
	for c in _footprint(cell, def.size):
		for n in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var other: int = _occupied.get(c + n, -1)
			if other >= 0 and _connected[other]:
				return true
	return false


func place(def_id: String, cell: Vector2i) -> bool:
	if not placement_problem(def_id, cell).is_empty():
		return false
	var def: Defs.Building = building_defs[def_id]
	_add(ColonyContent.MATERIALS, -def.cost)
	state.buildings.append({ "id": def_id, "x": cell.x, "y": cell.y })
	_rebuild()
	building_placed.emit(state.buildings.size() - 1)
	_check_objectives()
	changed.emit()
	return true


func demolish(index: int) -> bool:
	if index <= 0 or index >= state.buildings.size() or def_of(index).fixed:
		return false
	_add(ColonyContent.MATERIALS, def_of(index).cost * DEMOLISH_REFUND)
	state.buildings.remove_at(index)
	_rebuild()
	_clamp_to_capacity()
	changed.emit()
	return true


# ---------- Recherche ----------

func start_research(research_id: String) -> bool:
	if research_state(research_id) != "available" or not state.research_active.is_empty():
		return false
	var r: Defs.Research = research_defs[research_id]
	if state.amount(ColonyContent.DATA) < r.cost:
		return false
	_add(ColonyContent.DATA, -r.cost)
	state.research_active = research_id
	state.research_progress = 0.0
	changed.emit()
	return true


func _advance_research(ds: float) -> void:
	if state.research_active.is_empty():
		return
	var r: Defs.Research = research_defs[state.research_active]
	state.research_progress += ds / r.duration
	if state.research_progress >= 1.0:
		state.research_done.append(r.id)
		state.research_active = ""
		state.research_progress = 0.0
		research_completed.emit(r.id)
		unlock_card(r.card)
		changed.emit()


func unlock_card(card_id: String) -> void:
	if not card_id.is_empty() and cards.has(card_id) and not state.cards_unlocked.has(card_id):
		state.cards_unlocked.append(card_id)
		card_unlocked.emit(card_id)


# ---------- Temps ----------

func set_speed(speed: int) -> void:
	if speed in SPEEDS:
		state.speed = speed
		changed.emit()


## Fait avancer la colonie de `real_seconds` à la vitesse choisie.
func tick(real_seconds: float) -> void:
	if real_seconds <= 0.0 or state.speed == 0:
		return
	advance(real_seconds * state.speed / SECONDS_PER_SOL)


## Avance de `sols` sols (par petits pas).
func advance(sols: float) -> void:
	var remaining := sols
	while remaining > 1e-9:
		var ds := minf(STEP, remaining)
		_step(ds)
		remaining -= ds


func _step(ds: float) -> void:
	var sun := sunlight()
	var n := state.buildings.size()
	var demand := {}
	var passive := {}
	for i in n:
		if not _connected[i]:
			continue
		var def := def_of(i)
		if def.inputs.is_empty():
			for r: String in def.outputs:
				passive[r] = passive.get(r, 0.0) + _output_rate(def, r, sun) * ds
		else:
			for r: String in def.inputs:
				demand[r] = demand.get(r, 0.0) + def.inputs[r] * ds
	var count := state.colonists.size()
	var needs := colonist_needs()
	for r: String in needs:
		demand[r] = demand.get(r, 0.0) + needs[r] * count * ds

	# Part de chaque demande que les réserves (plus la production passive) peuvent couvrir.
	var satisfied := {}
	for r: String in demand:
		var want: float = demand[r]
		satisfied[r] = 1.0 if want <= 0.0 else minf(1.0, (state.amount(r) + passive.get(r, 0.0)) / want)

	var delta := {}
	for i in n:
		var e := 0.0
		if _connected[i]:
			var def := def_of(i)
			e = 1.0
			for r: String in def.inputs:
				e = minf(e, satisfied[r])
			for r: String in def.inputs:
				delta[r] = delta.get(r, 0.0) - def.inputs[r] * e * ds
			for r: String in def.outputs:
				delta[r] = delta.get(r, 0.0) + _output_rate(def, r, sun) * e * ds
		_efficiency[i] = e
	for r: String in needs:
		delta[r] = delta.get(r, 0.0) - needs[r] * count * ds * satisfied.get(r, 1.0)
	delta[ColonyContent.DATA] = delta.get(ColonyContent.DATA, 0.0) + ColonyContent.COLONIST_DATA * count * ds

	for r: String in delta:
		_add(r, delta[r])
	_update_health(satisfied, ds)
	_advance_research(ds)
	state.sol += ds
	if not _autopilot:
		_events()
	_update_autonomy(ds)
	_check_shortages(demand)
	_check_objectives()


func _output_rate(def: Defs.Building, resource: String, sun: float) -> float:
	var rate: float = def.outputs[resource]
	if def.solar and resource == ColonyContent.ENERGY:
		rate *= sun
	if resource == ColonyContent.FOOD:
		rate *= effect("food")
	return rate


func _storm_factor() -> float:
	return STORM_SOLAR * effect("storm_solar") if is_storm() else 1.0


# ---------- Colons ----------

func _update_health(satisfied: Dictionary, ds: float) -> void:
	# Sans oxygène, les réserves de secours des combinaisons tiennent environ un sol.
	var loss: float = (1.0 - satisfied.get(ColonyContent.OXYGEN, 1.0)) * 1.2 \
			+ (1.0 - satisfied.get(ColonyContent.WATER, 1.0)) * 0.4 \
			+ (1.0 - satisfied.get(ColonyContent.FOOD, 1.0)) * 0.25
	var cause := ""
	if loss > 0.0:
		var worst := 1.0
		for r in ColonyContent.VITAL:
			if satisfied.get(r, 1.0) < worst:
				worst = satisfied.get(r, 1.0)
				cause = r
	for i in range(state.colonists.size() - 1, -1, -1):
		var colonist: Dictionary = state.colonists[i]
		if loss <= 0.0:
			colonist.health = minf(1.0, colonist.health + 0.3 * ds)
		elif not _autopilot:
			# Résistance un peu différente selon les colons : ils ne partent pas tous en même temps.
			colonist.health -= loss * ds * (1.0 + 0.12 * (i % 4))
			if colonist.health <= 0.0:
				state.colonists.remove_at(i)
				state.evacuated += 1
				colonist_evacuated.emit(colonist.name, CAUSES.get(cause, ""))


func _arrive(member: Array) -> void:
	state.colonists.append({ "name": member[0], "role": member[1], "health": 1.0 })
	colonist_arrived.emit(member[0])


# ---------- Événements ----------

func _events() -> void:
	if not is_storm() and not _storm_warned and state.sol >= state.next_storm - STORM_WARNING_SOLS:
		_storm_warned = true
		storm_warning.emit()
	if state.storm_until < 0.0 and state.sol >= state.next_storm:
		state.storm_until = state.sol + _rng.randf_range(3.0, 6.0)
		state.next_storm = state.storm_until + _rng.randf_range(12.0, 20.0)
		state.event_seed = _rng.state
		storm_started.emit()
		unlock_card("storm")
	elif state.storm_until > 0.0 and state.sol >= state.storm_until:
		state.storm_until = -1.0
		_storm_warned = false
		storm_ended.emit()

	if state.sol >= state.next_resupply:
		state.next_resupply += RESUPPLY_INTERVAL
		state.resupply_count += 1
		var food := maxf(0.0, 30.0 - 6.0 * state.resupply_count)
		_add(ColonyContent.MATERIALS, RESUPPLY_MATERIALS)
		_add(ColonyContent.FOOD, food)
		var arrived: Array[String] = []
		while arrived.size() < 2 and state.colonists.size() < housing() \
				and state.recruits_sent < ColonyContent.RECRUITS.size():
			var member: Array = ColonyContent.RECRUITS[state.recruits_sent]
			state.recruits_sent += 1
			_arrive(member)
			arrived.append(member[0])
		resupply_arrived.emit({ "materials": RESUPPLY_MATERIALS, "food": food, "colonists": arrived })


func _check_shortages(demand: Dictionary) -> void:
	for r in ColonyContent.VITAL:
		if state.amount(r) <= 0.001 and demand.get(r, 0.0) > 0.0:
			if not _shortage_flags.get(r, false):
				_shortage_flags[r] = true
				shortage.emit(r)
		elif state.amount(r) > 5.0:
			_shortage_flags[r] = false


func _update_autonomy(ds: float) -> void:
	var flows := average_flows()
	var ok: bool = flows[ColonyContent.ENERGY] >= 0.0 and state.colonists.size() >= AUTONOMY_CREW
	for r in ColonyContent.VITAL:
		ok = ok and flows[r] >= 0.0 and state.amount(r) > 0.0
	state.autonomy_streak = state.autonomy_streak + ds if ok else 0.0


func _check_objectives() -> void:
	for objective in objectives:
		if state.objectives_done.has(objective.id) or not _objective_met(objective.id):
			continue
		state.objectives_done.append(objective.id)
		for r: String in objective.reward:
			_add(r, objective.reward[r])
		objective_completed.emit(objective.id)


func _objective_met(objective_id: String) -> bool:
	match objective_id:
		"first_breath":
			for i in state.buildings.size():
				if _connected[i] and def_of(i).outputs.has(ColonyContent.OXYGEN):
					return true
			return false
		"water":
			return _has_connected("extractor")
		"green":
			return _has_connected("greenhouse")
		"nights":
			return capacity(ColonyContent.ENERGY) >= 150.0
		"crew":
			return state.colonists.size() >= 8
		"autonomy":
			return state.autonomy_streak >= AUTONOMY_GOAL
	return false


## Progression d'un objectif, de 0 à 1 (pour l'affichage).
func objective_progress(objective_id: String) -> float:
	if state.objectives_done.has(objective_id):
		return 1.0
	match objective_id:
		"nights":
			return clampf(capacity(ColonyContent.ENERGY) / 150.0, 0.0, 1.0)
		"crew":
			return clampf(state.colonists.size() / 8.0, 0.0, 1.0)
		"autonomy":
			return clampf(state.autonomy_streak / AUTONOMY_GOAL, 0.0, 1.0)
	return 0.0


func current_objective() -> Defs.Objective:
	for objective in objectives:
		if not state.objectives_done.has(objective.id):
			return objective
	return null


# ---------- Hors-ligne ----------

## Pilote automatique sécurisé : la colonie continue avec ses flux, sans événement ni danger,
## et se met en veille dès qu'une ressource vitale va manquer.
## Retourne { "elapsed", "sols", "standby": ressource en cause ou "", "gains": { ressource: delta } }.
func apply_offline(now_unix: int) -> Dictionary:
	var elapsed := float(now_unix - state.last_saved_unix) if state.last_saved_unix > 0 else 0.0
	return apply_offline_seconds(elapsed)


func apply_offline_seconds(elapsed: float) -> Dictionary:
	var report := { "elapsed": maxf(0.0, elapsed), "sols": 0.0, "standby": "", "gains": {} }
	var sols := clampf(elapsed, 0.0, OFFLINE_CAP_SECONDS) / OFFLINE_SECONDS_PER_SOL
	if sols < 0.01:
		return report
	var before := state.resources.duplicate()
	var start := state.sol
	_autopilot = true
	var simulated := 0.0
	while simulated < sols:
		var ds := minf(STEP, sols - simulated)
		_step(ds)
		simulated += ds
		var needs := colonist_needs()
		for r in ColonyContent.VITAL:
			if state.amount(r) <= needs[r] * state.colonists.size() * 0.25:
				report.standby = r
		if not report.standby.is_empty():
			break
	_autopilot = false
	# Aucun événement pendant l'absence : on décale les échéances.
	var shift := state.sol - start
	state.next_storm += shift
	state.next_resupply += shift
	if state.storm_until > 0.0:
		state.storm_until += shift
	report.sols = shift
	for r in ColonyContent.RESOURCES:
		report.gains[r] = state.amount(r) - before.get(r, 0.0)
	changed.emit()
	return report


# ---------- Interne ----------

func _add(resource: String, value: float) -> void:
	state.resources[resource] = clampf(state.amount(resource) + value, 0.0, capacity(resource))


func _clamp_to_capacity() -> void:
	for r in ColonyContent.RESOURCES:
		state.resources[r] = minf(state.amount(r), capacity(r))


func _has_connected(def_id: String) -> bool:
	for i in state.buildings.size():
		if _connected[i] and state.buildings[i].id == def_id:
			return true
	return false


func _scarcest_input(def: Defs.Building) -> String:
	var worst := ""
	var lowest := INF
	for r: String in def.inputs:
		var ratio := state.amount(r) / maxf(def.inputs[r], 0.001)
		if ratio < lowest:
			lowest = ratio
			worst = r
	return worst


static func _footprint(cell: Vector2i, size: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in size.y:
		for x in size.x:
			cells.append(cell + Vector2i(x, y))
	return cells


## Recalcule l'occupation des cases et les raccordements (parcours depuis l'atterrisseur).
func _rebuild() -> void:
	_occupied.clear()
	var n := state.buildings.size()
	for i in n:
		for c in _footprint(cell_of(i), def_of(i).size):
			_occupied[c] = i
	_connected.resize(n)
	_connected.fill(false)
	_efficiency.resize(n)
	if n == 0:
		return
	var queue: Array[int] = [0]
	_connected[0] = true
	while not queue.is_empty():
		var i: int = queue.pop_front()
		for c in _footprint(cell_of(i), def_of(i).size):
			for step in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var other: int = _occupied.get(c + step, -1)
				if other >= 0 and not _connected[other]:
					_connected[other] = true
					queue.append(other)
