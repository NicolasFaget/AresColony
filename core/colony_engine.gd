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
signal breakdown(index: int)
signal era_started(era: int)
signal flare_warning
signal flare_started
signal flare_ended
signal expedition_returned(site: Dictionary)
signal dust_devil(cleaned: int)

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
## Données gagnées à la première lecture d'une fiche, et pour une bonne réponse à son quiz.
const CARD_READ_REWARD := 5.0
const QUIZ_REWARD := 10.0
## Coût d'une amélioration (niveau 2, puis 3) : part du coût du module en matériaux, et données.
const UPGRADE_MATERIALS: Array[float] = [0.8, 1.2]
const UPGRADE_DATA: Array[float] = [15.0, 30.0]
## Objectif « Colonie modèle » : note B avec au moins autant de modules (hors conduites).
const MODEL_MODULES := 12
const RATING_GRADES := [[85.0, "A"], [70.0, "B"], [55.0, "C"], [40.0, "D"], [0.0, "E"]]
const AUTONOMY_GOAL := 10.0
## Poussière sur les panneaux (0 à 1) : dépôt par sol, beaucoup plus en tempête ; perte maximale.
const DUST_RATE := 0.015
const DUST_STORM_RATE := 0.06
const DUST_LOSS := 0.7
## Sortie de nettoyage : oxygène des combinaisons par panneau nettoyé.
const CLEAN_OXYGEN := 0.3
## Pannes : probabilité par machine et par sol, à partir du sol indiqué ; réparation = part du prix.
const BREAKDOWN_RATE := 0.02
const BREAKDOWN_START := 6.0
const REPAIR_SHARE := 0.3
## Nombre de ravitaillements qui apportent des matériaux et de la nourriture.
const RESUPPLY_LIMIT := 6
## Expédition en rover : méthane consommé et durée en sols.
const EXPEDITION_METHANE := 20.0
const EXPEDITION_SOLS := 2.0
## Ère 2 : colons visés et méthane à réunir pour le retour.
const CITY_CREW := 14
const RETURN_METHANE := 200.0
## Éruptions solaires (ère 3) : préavis, durée, intervalle, santé perdue par sol sans abri.
const FLARE_WARNING_SOLS := 0.5
const FLARE_SOLS := 0.3
const FLARE_DAMAGE := 1.0
## Ère 3 : colons visés et note demandée.
const ROOTED_CREW := 20
const ROOTED_SCORE := 85.0
const AUTONOMY_CREW := 8

const START_RESOURCES := {
	ColonyContent.ENERGY: 30.0, ColonyContent.OXYGEN: 30.0, ColonyContent.WATER: 80.0,
	ColonyContent.FOOD: 50.0, ColonyContent.MATERIALS: 200.0, ColonyContent.DATA: 10.0,
}

## Explications données au joueur quand un colon est évacué.
const CAUSES := {
	ColonyContent.OXYGEN: "Manque d'oxygène. Construisez des électrolyseurs et donnez-leur assez d'énergie, jour et nuit.",
	ColonyContent.WATER: "Manque d'eau. Recherchez la glace souterraine et posez un extracteur dessus.",
	ColonyContent.FOOD: "Manque de nourriture. Les ravitaillements diminuent : il faut des serres.",
	"radiation": "Radiations d'une éruption solaire. Construisez des habitats enterrés pour abriter tout le monde.",
}

var state: ColonyState
var map: ColonyMap
var building_defs := {}
var research_defs := {}
var cards := {}
var objectives: Array[Defs.Objective] = []

var _connected: Array[bool] = []
## Synergies actives de chaque module (identifiants de ColonyContent.SYNERGIES).
var _synergies: Array = []
var _efficiency: Array[float] = []
## Réglables par les tests (0 = aucune poussière, aucune panne).
var dust_rate := DUST_RATE
var breakdown_rate := BREAKDOWN_RATE
## Rendement moyen récent de chaque module (lissé sur environ un demi-sol, pour la note).
var _efficiency_avg: Array[float] = []
var _occupied := {}
var _rng := RandomNumberGenerator.new()
var _storm_warned := false
var _flare_warned := false
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
	state.buildings = [{ "id": "lander", "x": map.lander_cell.x, "y": map.lander_cell.y, "level": 1 }] as Array[Dictionary]
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
			var amount: float = def_of(i).storage.get(resource, 0.0)
			for upgrade: Dictionary in _upgrades_of(i):
				amount *= upgrade.get("storage", {}).get(resource, 1.0)
			total += amount
	return total


func housing() -> int:
	var total := 0
	for i in state.buildings.size():
		if _connected[i]:
			total += def_of(i).housing
			for upgrade: Dictionary in _upgrades_of(i):
				total += upgrade.get("housing", 0)
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
			flows[r] -= _input_rate(i, r)
		for r: String in def.outputs:
			flows[r] += _output_rate(i, r, sun)
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
	if is_broken(index):
		return { "ok": false, "text": "En panne : réparez-le (%s matériaux)." % NumberFormatter.format(repair_cost(index)[ColonyContent.MATERIALS]) }
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


# ---------- Améliorations ----------

func level_of(index: int) -> int:
	return int(state.buildings[index].get("level", 1))


## Améliorations déjà faites sur un module.
func _upgrades_of(index: int) -> Array:
	var list: Array = ColonyContent.UPGRADES.get(state.buildings[index].id, [])
	return list.slice(0, level_of(index) - 1)


func max_level(index: int) -> int:
	return 1 + ColonyContent.UPGRADES.get(state.buildings[index].id, []).size()


## Prochaine amélioration d'un module ({} au niveau maximal).
func next_upgrade(index: int) -> Dictionary:
	var list: Array = ColonyContent.UPGRADES.get(state.buildings[index].id, [])
	var level := level_of(index)
	return list[level - 1] if level - 1 < list.size() else {}


func upgrade_cost(index: int) -> Dictionary:
	var step := level_of(index) - 1
	if next_upgrade(index).is_empty():
		return {}
	return { ColonyContent.MATERIALS: roundf(def_of(index).cost * UPGRADE_MATERIALS[step]),
			ColonyContent.DATA: UPGRADE_DATA[step] }


## Raison pour laquelle l'amélioration est impossible ("" si possible).
func upgrade_problem(index: int) -> String:
	if next_upgrade(index).is_empty():
		return "Niveau maximal atteint."
	if not _connected[index]:
		return "Raccordez d'abord ce module."
	var cost := upgrade_cost(index)
	for r: String in cost:
		if state.amount(r) < cost[r]:
			return "Pas assez %s." % ColonyContent.RESOURCE_PARTITIVE[r]
	return ""


func upgrade(index: int) -> bool:
	if not upgrade_problem(index).is_empty():
		return false
	var cost := upgrade_cost(index)
	for r: String in cost:
		_add(r, -cost[r])
	state.buildings[index].level = level_of(index) + 1
	_check_objectives()
	changed.emit()
	return true


# ---------- Note d'efficacité ----------

## Note de la colonie sur 100, sa lettre et le détail : fonctionnement, raccordement, synergies,
## améliorations. Chaque partie porte un conseil pour progresser.
func colony_rating() -> Dictionary:
	var modules := 0
	var consumers := 0
	var running := 0.0
	var isolated := 0
	var upgradable := 0
	var levels := 0
	for i in state.buildings.size():
		var def := def_of(i)
		if def.fixed or def.id == "link":
			continue
		modules += 1
		if not _connected[i]:
			isolated += 1
			continue
		if not def.inputs.is_empty():
			consumers += 1
			running += _efficiency_avg[i]
		if max_level(i) > 1:
			upgradable += 1
			levels += level_of(i) - 1
	var synergy_target := clampf(modules / 3.0, 2.0, 8.0)
	var parts: Array[Dictionary] = [
		{ "name": "Fonctionnement", "max": 40.0, "value": 40.0 * (running / consumers if consumers > 0 else 1.0),
			"tip": "Des modules tournent au ralenti faute d'énergie ou d'eau : ajoutez de la production ou des batteries." },
		{ "name": "Raccordement", "max": 10.0, "value": maxf(0.0, 10.0 - 5.0 * isolated),
			"tip": "Des modules sont isolés : reliez-les à l'atterrisseur par des conduites." },
		{ "name": "Synergies", "max": 25.0, "value": 25.0 * minf(1.0, active_synergy_count() / synergy_target),
			"tip": "Collez les bons modules entre eux : Construire › Synergies." },
		{ "name": "Améliorations", "max": 25.0, "value": 25.0 * (levels / (2.0 * upgradable) if upgradable > 0 else 0.0),
			"tip": "Touchez un module pour l'améliorer (matériaux et données)." },
	]
	var score := 0.0
	var weakest: Dictionary = parts[0]
	for part in parts:
		score += part.value
		if part.value / part.max < weakest.value / weakest.max:
			weakest = part
	var grade := "E"
	for step: Array in RATING_GRADES:
		if score >= step[0]:
			grade = step[1]
			break
	return { "score": score, "grade": grade, "parts": parts, "modules": modules,
			"tip": "" if weakest.value >= weakest.max - 0.01 else weakest.tip }


## Synergies actives d'un module (dictionnaires de ColonyContent.SYNERGIES).
func synergies_of(index: int) -> Array:
	return _synergies[index]


func active_synergy_count() -> int:
	var count := 0
	for i in state.buildings.size():
		if _connected[i]:
			count += _synergies[i].size()
	return count


## Synergies que gagnerait un module posé là, et celles qu'il offrirait à ses voisins.
## Retourne une liste de { "synergy", "target": nom du module bénéficiaire }.
func preview_synergies(def_id: String, cell: Vector2i) -> Array[Dictionary]:
	var def: Defs.Building = building_defs.get(def_id)
	var result: Array[Dictionary] = []
	if def == null:
		return result
	var neighbors := _neighbors_of(cell, def.size)
	var seen := {}
	for synergy: Dictionary in ColonyContent.SYNERGIES:
		if synergy.building == def_id and not seen.has(synergy.id):
			for j: int in neighbors:
				if state.buildings[j].id == synergy.neighbor:
					seen[synergy.id] = true
					result.append({ "synergy": synergy, "target": def.name })
					break
		if synergy.neighbor == def_id:
			for j: int in neighbors:
				if state.buildings[j].id == synergy.building and not _has_synergy(j, synergy.id):
					result.append({ "synergy": synergy, "target": def_of(j).name })
					break
	return result


func _has_synergy(index: int, synergy_id: String) -> bool:
	for synergy: Dictionary in _synergies[index]:
		if synergy.id == synergy_id:
			return true
	return false


## Modules qui touchent directement une emprise (4 voisins).
func _neighbors_of(cell: Vector2i, size: Vector2i) -> Array[int]:
	var result: Array[int] = []
	for c in _footprint(cell, size):
		for step in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var other: int = _occupied.get(c + step, -1)
			if other >= 0 and not result.has(other) and _occupied.get(c, -2) != other:
				result.append(other)
	return result


func research_state(research_id: String) -> String:
	if state.research_done.has(research_id):
		return "done"
	if state.research_active == research_id:
		return "active"
	var r: Defs.Research = research_defs[research_id]
	if r.era > state.era:
		return "locked"
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
	if def.id == "erv" and _count_of("erv") > 0:
		return "Un seul véhicule de retour suffit."
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
	state.buildings.append({ "id": def_id, "x": cell.x, "y": cell.y, "level": 1 })
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


## Première lecture d'une fiche : rapporte des données. Retourne la récompense (0 si déjà lue).
func read_card(card_id: String) -> float:
	if not state.cards_unlocked.has(card_id) or state.cards_read.has(card_id):
		return 0.0
	state.cards_read.append(card_id)
	_add(ColonyContent.DATA, CARD_READ_REWARD)
	changed.emit()
	return CARD_READ_REWARD


## Réponse au quiz d'une fiche (une seule tentative). Retourne vrai si la réponse est juste.
func answer_quiz(card_id: String, choice: int) -> bool:
	if state.quiz_answers.has(card_id):
		return state.quiz_answers[card_id]
	if not state.cards_unlocked.has(card_id):
		return false
	var correct: bool = choice == cards[card_id].answer
	state.quiz_answers[card_id] = correct
	if correct:
		_add(ColonyContent.DATA, QUIZ_REWARD)
	changed.emit()
	return correct


func unread_cards() -> int:
	var count := 0
	for id in state.cards_unlocked:
		if not state.cards_read.has(id):
			count += 1
	return count


func quiz_score() -> int:
	return state.quiz_answers.values().count(true)


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
		if not _connected[i] or is_broken(i):
			continue
		var def := def_of(i)
		if def.inputs.is_empty():
			for r: String in def.outputs:
				passive[r] = passive.get(r, 0.0) + _output_rate(i, r, sun) * ds
		else:
			for r: String in def.inputs:
				demand[r] = demand.get(r, 0.0) + _input_rate(i, r) * ds
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
		if _connected[i] and not is_broken(i):
			var def := def_of(i)
			e = 1.0
			for r: String in def.inputs:
				e = minf(e, satisfied[r])
			for r: String in def.inputs:
				delta[r] = delta.get(r, 0.0) - _input_rate(i, r) * e * ds
			for r: String in def.outputs:
				delta[r] = delta.get(r, 0.0) + _output_rate(i, r, sun) * e * ds
		_efficiency[i] = e
		_efficiency_avg[i] = lerpf(_efficiency_avg[i], e, minf(1.0, ds * 2.0))
	for r: String in needs:
		delta[r] = delta.get(r, 0.0) - needs[r] * count * ds * satisfied.get(r, 1.0)
	delta[ColonyContent.DATA] = delta.get(ColonyContent.DATA, 0.0) + ColonyContent.COLONIST_DATA * count * ds

	for r: String in delta:
		_add(r, delta[r])
	_settle_dust(ds)
	_update_health(satisfied, ds)
	_advance_research(ds)
	state.sol += ds
	if not _autopilot:
		_events()
	_update_autonomy(ds)
	_check_shortages(demand)
	_check_objectives()


## Multiplicateur dû aux synergies et aux améliorations sur une entrée ou une sortie d'un module.
func rate_factor(index: int, resource: String, output: bool) -> float:
	var factor := 1.0
	for mod: Dictionary in _synergies[index] + _upgrades_of(index):
		factor *= mod.get("outputs" if output else "inputs", {}).get(resource, 1.0)
	return factor


func _input_rate(index: int, resource: String) -> float:
	return def_of(index).inputs[resource] * rate_factor(index, resource, false)


func _output_rate(index: int, resource: String, sun: float) -> float:
	var def := def_of(index)
	var rate: float = def.outputs[resource] * rate_factor(index, resource, true)
	if def.solar and resource == ColonyContent.ENERGY:
		rate *= sun * (1.0 - DUST_LOSS * dust_of(index))
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
	var flare := is_flare()
	var shelter := shelter_capacity()
	for i in range(state.colonists.size() - 1, -1, -1):
		var colonist: Dictionary = state.colonists[i]
		var mine := loss
		var why := cause
		# Les premiers colons trouvent place dans les abris ; les autres prennent les radiations.
		if flare and i >= shelter:
			mine += FLARE_DAMAGE
			why = "radiation"
		if mine <= 0.0:
			colonist.health = minf(1.0, colonist.health + 0.3 * ds)
		elif not _autopilot:
			# Résistance un peu différente selon les colons : ils ne partent pas tous en même temps.
			colonist.health -= mine * ds * (1.0 + 0.12 * (i % 4))
			if colonist.health <= 0.0:
				state.colonists.remove_at(i)
				state.evacuated += 1
				colonist_evacuated.emit(colonist.name, CAUSES.get(why, ""))


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
		var supplies := state.resupply_count <= RESUPPLY_LIMIT
		var materials := RESUPPLY_MATERIALS if supplies else 0.0
		var food := maxf(0.0, 30.0 - 6.0 * state.resupply_count) if supplies else 0.0
		_add(ColonyContent.MATERIALS, materials)
		_add(ColonyContent.FOOD, food)
		var arrived: Array[String] = []
		while arrived.size() < 2 and state.colonists.size() < housing() \
				and state.recruits_sent < ColonyContent.RECRUITS.size():
			var member: Array = ColonyContent.RECRUITS[state.recruits_sent]
			state.recruits_sent += 1
			_arrive(member)
			arrived.append(member[0])
		if supplies or not arrived.is_empty():
			resupply_arrived.emit({ "materials": materials, "food": food, "colonists": arrived,
					"last": state.resupply_count == RESUPPLY_LIMIT })

	_dust_devils()
	_breakdowns()
	_finish_expedition()
	_flares()


# ---------- Poussière et pannes ----------

func dust_of(index: int) -> float:
	return float(state.buildings[index].get("dust", 0.0))


## Panneaux (et atterrisseur) raccordés.
func _solar_indices() -> Array[int]:
	var list: Array[int] = []
	for i in state.buildings.size():
		if _connected[i] and def_of(i).solar:
			list.append(i)
	return list


func average_dust() -> float:
	var panels := _solar_indices()
	var total := 0.0
	for i in panels:
		total += dust_of(i)
	return total / panels.size() if not panels.is_empty() else 0.0


func _settle_dust(ds: float) -> void:
	var rate := (DUST_STORM_RATE if is_storm() else dust_rate) * effect("dust") * (1.0 if dust_rate > 0.0 else 0.0)
	if rate <= 0.0:
		return
	for i in _solar_indices():
		state.buildings[i].dust = minf(1.0, dust_of(i) + rate * ds)


## Panneaux assez sales pour mériter une sortie.
func _dirty_panels() -> Array[int]:
	var list: Array[int] = []
	for i in _solar_indices():
		if dust_of(i) > 0.02:
			list.append(i)
	return list


func cleaning_cost() -> float:
	return CLEAN_OXYGEN * _dirty_panels().size()


func cleaning_problem() -> String:
	if _dirty_panels().is_empty():
		return "Les panneaux sont propres."
	if is_storm():
		return "Sortie impossible pendant la tempête."
	if state.amount(ColonyContent.OXYGEN) < cleaning_cost() + 1.0:
		return "Pas assez d'oxygène pour les combinaisons."
	return ""


## Sortie extravéhiculaire : les colons brossent tous les panneaux.
func clean_panels() -> bool:
	if not cleaning_problem().is_empty():
		return false
	_add(ColonyContent.OXYGEN, -cleaning_cost())
	for i in _dirty_panels():
		state.buildings[i].dust = 0.0
	changed.emit()
	return true


## De temps en temps, un tourbillon de poussière balaie quelques panneaux (comme pour Spirit et Opportunity).
func _dust_devils() -> void:
	if is_storm() or state.sol < state.next_dust_devil:
		return
	state.next_dust_devil = state.sol + _rng.randf_range(5.0, 9.0)
	var dirty := _dirty_panels()
	var count := mini(dirty.size(), _rng.randi_range(2, 4))
	for k in count:
		var pick: int = dirty.pop_at(_rng.randi() % dirty.size())
		state.buildings[pick].dust = 0.0
	state.event_seed = _rng.state
	if count > 0:
		dust_devil.emit(count)


func is_broken(index: int) -> bool:
	return state.buildings[index].get("broken", false) == true


func broken_count() -> int:
	var count := 0
	for i in state.buildings.size():
		if is_broken(i):
			count += 1
	return count


func repair_cost(index: int) -> Dictionary:
	return { ColonyContent.MATERIALS: maxf(5.0, roundf(def_of(index).cost * REPAIR_SHARE)) }


func repair_problem(index: int) -> String:
	if not is_broken(index):
		return "Ce module fonctionne."
	if state.amount(ColonyContent.MATERIALS) < repair_cost(index)[ColonyContent.MATERIALS]:
		return "Pas assez de matériaux."
	return ""


func repair(index: int) -> bool:
	if not repair_problem(index).is_empty():
		return false
	_add(ColonyContent.MATERIALS, -repair_cost(index)[ColonyContent.MATERIALS])
	state.buildings[index].erase("broken")
	changed.emit()
	return true


func _breakdowns() -> void:
	if breakdown_rate <= 0.0 or state.sol < BREAKDOWN_START:
		return
	var drew := false
	for i in state.buildings.size():
		if not _connected[i] or is_broken(i) or not state.buildings[i].id in ColonyContent.BREAKABLE:
			continue
		drew = true
		if _rng.randf() < breakdown_rate * STEP:
			state.buildings[i].broken = true
			breakdown.emit(i)
	if drew:
		state.event_seed = _rng.state


# ---------- Expéditions (ère 2) ----------

func _count_of(def_id: String) -> int:
	var count := 0
	for building in state.buildings:
		if building.id == def_id:
			count += 1
	return count


## Prochain site à découvrir (ou une prospection une fois tous les sites visités).
func next_site() -> Dictionary:
	for site: Dictionary in ColonyContent.SITES:
		if not state.sites_done.has(site.id):
			return site
	return ColonyContent.PROSPECTION


func site_by_id(site_id: String) -> Dictionary:
	for site: Dictionary in ColonyContent.SITES:
		if site.id == site_id:
			return site
	return ColonyContent.PROSPECTION


func expedition_problem() -> String:
	if not _has_connected("garage"):
		return "Construisez un garage à rovers, relié à la colonie."
	if not state.expedition.is_empty():
		return "Le rover est déjà en expédition."
	if is_storm():
		return "Pas d'expédition pendant une tempête."
	if state.amount(ColonyContent.METHANE) < EXPEDITION_METHANE:
		return "Pas assez de méthane (%s kg)." % NumberFormatter.format(EXPEDITION_METHANE)
	return ""


func start_expedition() -> bool:
	if not expedition_problem().is_empty():
		return false
	_add(ColonyContent.METHANE, -EXPEDITION_METHANE)
	state.expedition = { "site": next_site().id, "until": state.sol + EXPEDITION_SOLS }
	changed.emit()
	return true


func _finish_expedition() -> void:
	if state.expedition.is_empty() or state.sol < state.expedition.until:
		return
	var site := site_by_id(state.expedition.site)
	state.expedition = {}
	state.expeditions += 1
	if site.id != ColonyContent.PROSPECTION.id and not state.sites_done.has(site.id):
		state.sites_done.append(site.id)
	for r: String in site.reward:
		_add(r, site.reward[r])
	expedition_returned.emit(site)
	unlock_card(site.card)
	_check_objectives()


# ---------- Éruptions solaires (ère 3) ----------

func is_flare() -> bool:
	return state.flare_until > 0.0 and state.sol < state.flare_until


func flare_soon() -> bool:
	return not is_flare() and state.next_flare - state.sol <= FLARE_WARNING_SOLS


## Colons qui tiennent dans les abris (habitats enterrés raccordés).
func shelter_capacity() -> int:
	var total := 0
	for i in state.buildings.size():
		if _connected[i]:
			total += def_of(i).shelter
	return total


func _flares() -> void:
	if state.era < 3:
		return
	if not _flare_warned and flare_soon():
		_flare_warned = true
		flare_warning.emit()
	if state.flare_until < 0.0 and state.sol >= state.next_flare:
		state.flare_until = state.sol + FLARE_SOLS
		state.next_flare = state.flare_until + _rng.randf_range(10.0, 16.0)
		state.event_seed = _rng.state
		flare_started.emit()
	elif state.flare_until > 0.0 and state.sol >= state.flare_until:
		state.flare_until = -1.0
		_flare_warned = false
		flare_ended.emit()


func resupplies_left() -> int:
	return maxi(0, RESUPPLY_LIMIT - state.resupply_count)


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
		if objective.era > state.era or state.objectives_done.has(objective.id) or not _objective_met(objective.id):
			continue
		state.objectives_done.append(objective.id)
		for r: String in objective.reward:
			_add(r, objective.reward[r])
		objective_completed.emit(objective.id)
	# Toute l'ère accomplie : la suivante commence.
	if state.era < ColonyContent.ERAS.size():
		for objective in objectives:
			if objective.era == state.era and not state.objectives_done.has(objective.id):
				return
		state.era += 1
		if state.era == 3:
			state.next_flare = state.sol + 6.0
		era_started.emit(state.era)
		if state.era == 3:
			unlock_card("terraforming")


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
		"synergies":
			return active_synergy_count() >= 4
		"model":
			var rating := colony_rating()
			return rating.score >= 70.0 and rating.modules >= MODEL_MODULES
		"crew":
			return state.colonists.size() >= 8
		"autonomy":
			return state.autonomy_streak >= AUTONOMY_GOAL
		"methane":
			return _has_connected("sabatier")
		"explorer":
			return state.expeditions >= 3
		"city":
			return state.colonists.size() >= CITY_CREW
		"return":
			return _has_connected("erv") and state.amount(ColonyContent.METHANE) >= RETURN_METHANE
		"shelter":
			return shelter_capacity() >= maxi(4, state.colonists.size())
		"nuclear":
			return _has_connected("reactor")
		"garden":
			return _has_connected("biodome")
		"rooted":
			for other in ["shelter", "nuclear", "garden"]:
				if not state.objectives_done.has(other):
					return false
			return state.colonists.size() >= ROOTED_CREW and shelter_capacity() >= state.colonists.size() \
					and colony_rating().score >= ROOTED_SCORE
	return false


## Progression d'un objectif, de 0 à 1 (pour l'affichage).
func objective_progress(objective_id: String) -> float:
	if state.objectives_done.has(objective_id):
		return 1.0
	match objective_id:
		"nights":
			return clampf(capacity(ColonyContent.ENERGY) / 150.0, 0.0, 1.0)
		"synergies":
			return clampf(active_synergy_count() / 4.0, 0.0, 1.0)
		"model":
			var rating := colony_rating()
			return clampf(minf(rating.score / 70.0, float(rating.modules) / MODEL_MODULES), 0.0, 1.0)
		"crew":
			return clampf(state.colonists.size() / 8.0, 0.0, 1.0)
		"autonomy":
			return clampf(state.autonomy_streak / AUTONOMY_GOAL, 0.0, 1.0)
		"explorer":
			return clampf(state.expeditions / 3.0, 0.0, 1.0)
		"city":
			return clampf(float(state.colonists.size()) / CITY_CREW, 0.0, 1.0)
		"return":
			return clampf(state.amount(ColonyContent.METHANE) / RETURN_METHANE, 0.0, 1.0) if _has_connected("erv") else 0.0
		"shelter":
			return clampf(float(shelter_capacity()) / maxi(4, state.colonists.size()), 0.0, 1.0)
		"rooted":
			return clampf(minf(minf(float(state.colonists.size()) / ROOTED_CREW, colony_rating().score / ROOTED_SCORE),
					float(shelter_capacity()) / maxi(1, state.colonists.size())), 0.0, 1.0)
	return 0.0


func current_objective() -> Defs.Objective:
	for objective in objectives:
		if objective.era == state.era and not state.objectives_done.has(objective.id):
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
	var old := _efficiency_avg.size()
	_efficiency_avg.resize(n)
	for i in range(old, n):
		_efficiency_avg[i] = 1.0
	# Synergies : chaque module, une fois par type de synergie, si un voisin direct convient.
	_synergies.resize(n)
	for i in n:
		var active: Array = []
		var neighbors := _neighbors_of(cell_of(i), def_of(i).size)
		for synergy: Dictionary in ColonyContent.SYNERGIES:
			if synergy.building != state.buildings[i].id:
				continue
			for j: int in neighbors:
				if state.buildings[j].id == synergy.neighbor:
					active.append(synergy)
					break
		_synergies[i] = active
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
