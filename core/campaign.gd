class_name Campaign
extends RefCounted
## Une partie à plusieurs colonies : une horloge commune, le savoir partagé (recherches, fiches,
## quiz), les fusées en vol entre colonies. Seule la colonie affichée est simulée image par image ;
## les autres tournent en pilote automatique prudent (sans événements, veille si une réserve baisse).

## Une cargaison ou un équipage de fondation est arrivé à destination.
signal shipment_arrived(shipment: Dictionary)
## Une nouvelle colonie vient d'être fondée (index dans `colonies`).
signal colony_founded(index: int)

const FORMAT_VERSION := 2
## Les colonies en arrière-plan avancent par paquets (pas besoin de les calculer à chaque image).
const BACKGROUND_STEP := 0.05
## Saut entre deux sites d'une même planète, en sols.
const SURFACE_HOP_SOLS := 1.0
## Carburant d'un saut : méthane fixe, plus par unité de cargaison (un colon compte pour 10 unités).
const HOP_FUEL := 20.0
const FUEL_PER_UNIT := 0.1
const COLONIST_UNITS := 10.0
const PAYLOAD_UNITS := 300.0
## Fonder une colonie : ce que le vaisseau emporte depuis la colonie de départ.
const FOUNDING_CREW := 4
const FOUNDING_MATERIALS := 150.0
const FOUNDING_FUEL := 60.0
## Ressources qu'on peut expédier.
const CARGO := [ColonyContent.MATERIALS, ColonyContent.WATER, ColonyContent.FOOD, ColonyContent.OXYGEN,
		ColonyContent.METHANE, ColonyContent.DATA]

var colonies: Array[ColonyState] = []
var engines: Array[ColonyEngine] = []
var active := 0
## Horloge de la campagne, en sols.
var time := 0.0
## Fusées en vol : { id, kind ("cargo" | "colony"), from, to, cargo, colonists, region, depart, arrive }.
var shipments: Array[Dictionary] = []
var next_shipment_id := 1
var deliveries := 0

## Colonies en veille sécurisée (index -> ressource vitale trop basse).
var standby := {}
var _background := 0.0
var _knowledge_dirty := false


static func from_state(state: ColonyState) -> Campaign:
	var campaign := Campaign.new()
	campaign._add_colony(state)
	campaign.time = state.sol
	return campaign


## Campagne autour d'une colonie déjà simulée (outils, captures d'écran).
static func from_engine(colony: ColonyEngine) -> Campaign:
	var campaign := Campaign.new()
	campaign._add_colony(colony.state, colony)
	campaign.time = colony.state.sol
	return campaign


func engine() -> ColonyEngine:
	return engines[active]


func colony_name(index: int) -> String:
	return colonies[index].name if not colonies[index].name.is_empty() \
			else ColonyContent.REGIONS[colonies[index].region].name


# ---------- Temps ----------

## Avance la campagne de `sols` : la colonie affichée normalement, les autres en pilote automatique.
func advance(sols: float) -> void:
	if sols <= 0.0:
		return
	engine().advance(sols)
	time += sols
	_background += sols
	if _background >= BACKGROUND_STEP:
		for i in engines.size():
			if i != active:
				var low := engines[i].run_autopilot(_background)
				if low.is_empty():
					standby.erase(i)
				else:
					standby[i] = low
		_background = 0.0
	_update_info()
	_deliver()
	if _knowledge_dirty:
		sync_knowledge()


## Temps réel écoulé à la vitesse de la colonie affichée (comme ColonyEngine.tick).
func tick(real_seconds: float) -> void:
	var speed := engine().state.speed
	if real_seconds > 0.0 and speed > 0:
		advance(real_seconds * speed / ColonyEngine.SECONDS_PER_SOL)


## Après une absence : chaque colonie passe en pilote automatique ; les fusées continuent leur route.
func apply_offline(now_unix: int) -> Dictionary:
	var state := colonies[active]
	return apply_offline_seconds(float(now_unix - state.last_saved_unix) if state.last_saved_unix > 0 else 0.0)


func apply_offline_seconds(elapsed: float) -> Dictionary:
	var report := {}
	for i in engines.size():
		var colony_report := engines[i].apply_offline_seconds(elapsed)
		if i == active:
			report = colony_report
	time += report.get("sols", 0.0)
	_update_info()
	_deliver()
	return report


func switch_to(index: int) -> void:
	if index >= 0 and index < engines.size():
		active = index
		standby.erase(index)


# ---------- Savoir partagé ----------

## Recherches, fiches et quiz sont communs : le savoir voyage par radio entre les colonies.
func sync_knowledge() -> void:
	_knowledge_dirty = false
	var research := {}
	var cards := {}
	var read := {}
	var quiz := {}
	for state in colonies:
		for id in state.research_done:
			research[id] = true
		for id in state.cards_unlocked:
			cards[id] = true
		for id in state.cards_read:
			read[id] = true
		quiz.merge(state.quiz_answers)
	for state in colonies:
		for id: String in research:
			if not state.research_done.has(id):
				state.research_done.append(id)
		if state.research_done.has(state.research_active):
			state.research_active = ""
			state.research_progress = 0.0
		for id: String in cards:
			if not state.cards_unlocked.has(id):
				state.cards_unlocked.append(id)
		for id: String in read:
			if not state.cards_read.has(id):
				state.cards_read.append(id)
		state.quiz_answers.merge(quiz)


# ---------- Fusées ----------

## Fondation possible dès qu'une colonie a terminé les trois ères de Mars (ère 4).
func interplanetary_unlocked() -> bool:
	for state in colonies:
		if state.era >= 4:
			return true
	return false


func transit_sols(from: int, to_region: String) -> float:
	return SURFACE_HOP_SOLS


func fuel_cost(cargo: Dictionary, colonists: int) -> float:
	var units := colonists * COLONIST_UNITS
	for r: String in cargo:
		units += cargo[r]
	return HOP_FUEL + FUEL_PER_UNIT * units


## Raison pour laquelle l'envoi est impossible ("" s'il est possible).
func shipment_problem(from: int, to: int, cargo: Dictionary, colonists: int) -> String:
	var origin := engines[from]
	if not origin.has_spaceport():
		return Tr.t("Il faut un astroport raccordé dans la colonie de départ.")
	if to == from or to < 0 or to >= colonies.size():
		return Tr.t("Choisissez une autre colonie.")
	var units := colonists * COLONIST_UNITS
	for r: String in cargo:
		units += cargo[r]
	if units <= 0.0:
		return Tr.t("La soute est vide.")
	if units > PAYLOAD_UNITS:
		return Tr.t("Trop lourd : %d unités au plus.") % int(PAYLOAD_UNITS)
	if colonists > 0 and colonists >= origin.state.colonists.size():
		return Tr.t("Il faut laisser au moins un colon sur place.")
	var fuel := fuel_cost(cargo, colonists)
	for r: String in cargo:
		var needed: float = cargo[r] + (fuel if r == ColonyContent.METHANE else 0.0)
		if origin.state.amount(r) < needed - 0.001:
			return Tr.t("Pas assez %s.") % Tr.t(ColonyContent.RESOURCE_PARTITIVE[r])
	if origin.state.amount(ColonyContent.METHANE) < fuel - 0.001:
		return Tr.t("Pas assez de méthane pour le vol (%s kg).") % NumberFormatter.format(fuel)
	return ""


func send_cargo(from: int, to: int, cargo: Dictionary, colonists: int) -> bool:
	if not shipment_problem(from, to, cargo, colonists).is_empty():
		return false
	var origin := engines[from]
	origin.withdraw(ColonyContent.METHANE, fuel_cost(cargo, colonists))
	for r: String in cargo:
		origin.withdraw(r, cargo[r])
	var crew := origin.release_colonists(colonists)
	_launch("cargo", from, to, cargo, crew, colonies[to].region)
	return true


func founding_problem(from: int) -> String:
	if not interplanetary_unlocked():
		return Tr.t("Terminez d'abord les trois ères de Mars.")
	var origin := engines[from]
	if not origin.has_spaceport():
		return Tr.t("Il faut un astroport raccordé dans la colonie de départ.")
	if origin.state.colonists.size() <= FOUNDING_CREW:
		return Tr.t("Il faut plus de %d colons pour en envoyer %d.") % [FOUNDING_CREW, FOUNDING_CREW]
	if origin.state.amount(ColonyContent.MATERIALS) < FOUNDING_MATERIALS:
		return Tr.t("Pas assez %s.") % Tr.t(ColonyContent.RESOURCE_PARTITIVE[ColonyContent.MATERIALS])
	if origin.state.amount(ColonyContent.METHANE) < FOUNDING_FUEL:
		return Tr.t("Pas assez de méthane pour le vol (%s kg).") % NumberFormatter.format(FOUNDING_FUEL)
	return ""


## Lance un vaisseau de fondation vers `region` : la colonie naît à son arrivée.
func found_colony(from: int, region: String) -> bool:
	if not founding_problem(from).is_empty() or not ColonyContent.REGIONS.has(region):
		return false
	var origin := engines[from]
	origin.withdraw(ColonyContent.MATERIALS, FOUNDING_MATERIALS)
	origin.withdraw(ColonyContent.METHANE, FOUNDING_FUEL)
	var crew := origin.release_colonists(FOUNDING_CREW)
	_launch("colony", from, -1, { ColonyContent.MATERIALS: FOUNDING_MATERIALS }, crew, region)
	return true


func _launch(kind: String, from: int, to: int, cargo: Dictionary, crew: Array, region: String) -> void:
	shipments.append({
		"id": next_shipment_id, "kind": kind, "from": from, "to": to, "cargo": cargo.duplicate(),
		"colonists": crew, "region": region, "depart": time, "arrive": time + transit_sols(from, region),
	})
	next_shipment_id += 1


func _deliver() -> void:
	var i := 0
	while i < shipments.size():
		var shipment := shipments[i]
		if time < shipment.arrive:
			i += 1
			continue
		shipments.remove_at(i)
		if shipment.kind == "colony":
			shipment.to = _found(shipment)
		else:
			engines[shipment.to].receive(shipment.cargo, shipment.colonists)
			deliveries += 1
		_update_info()
		shipment_arrived.emit(shipment)


## Crée la colonie apportée par un vaisseau de fondation.
func _found(shipment: Dictionary) -> int:
	var state := ColonyState.new()
	state.region = shipment.region
	state.map_seed = 1 + colonies.size() * 7919
	state.name = _new_name(shipment.region)
	# Même calendrier que la colonie de départ.
	state.sol = colonies[shipment.from].sol
	var index := _add_colony(state)
	var colony := engines[index]
	colony.setup_outpost(shipment.colonists, shipment.cargo)
	_knowledge_dirty = true
	sync_knowledge()
	colony_founded.emit(index)
	return index


func _new_name(region: String) -> String:
	var base: String = ColonyContent.REGIONS[region].name
	var count := 0
	for state in colonies:
		if state.region == region:
			count += 1
	return base if count == 0 else "%s %s" % [base, ["II", "III", "IV", "V", "VI", "VII"][mini(count - 1, 5)]]


func _add_colony(state: ColonyState, existing: ColonyEngine = null) -> int:
	if state.name.is_empty():
		state.name = ColonyContent.REGIONS[state.region].name
	colonies.append(state)
	var colony := existing if existing != null else ColonyEngine.new(state)
	colony.research_completed.connect(func(_id: String) -> void: _knowledge_dirty = true)
	colony.card_unlocked.connect(func(_id: String) -> void: _knowledge_dirty = true)
	engines.append(colony)
	_update_info()
	return engines.size() - 1


## Ce que les objectifs d'une colonie doivent savoir de la campagne.
func _update_info() -> void:
	for colony in engines:
		colony.campaign_colonies = colonies.size()
		colony.campaign_deliveries = deliveries


# ---------- Sauvegarde ----------

func to_dict() -> Dictionary:
	var list := []
	for state in colonies:
		list.append(state.to_dict())
	return {
		"version": FORMAT_VERSION, "colonies": list, "active": active, "time": time,
		"shipments": shipments.duplicate(true), "next_shipment_id": next_shipment_id, "deliveries": deliveries,
	}


## Relit une campagne ; une sauvegarde d'avant les campagnes (une seule colonie) est convertie.
static func from_dict(data: Dictionary) -> Campaign:
	if not data.get("colonies") is Array:
		return from_state(ColonyState.from_dict(data))
	var campaign := Campaign.new()
	for item: Variant in data.colonies:
		if item is Dictionary:
			campaign._add_colony(ColonyState.from_dict(item))
	if campaign.colonies.is_empty():
		campaign._add_colony(ColonyState.new())
	campaign.active = clampi(int(data.get("active", 0)), 0, campaign.colonies.size() - 1)
	campaign.time = float(data.get("time", campaign.colonies[0].sol))
	campaign.next_shipment_id = int(data.get("next_shipment_id", 1))
	campaign.deliveries = int(data.get("deliveries", 0))
	var list: Variant = data.get("shipments")
	if list is Array:
		for item: Variant in list:
			if item is Dictionary and item.get("arrive") != null:
				var shipment: Dictionary = item
				shipment.from = int(shipment.get("from", 0))
				shipment.to = int(shipment.get("to", -1))
				campaign.shipments.append(shipment)
	campaign._update_info()
	campaign.sync_knowledge()
	return campaign


## Résumé pour le menu : la colonie affichée, et le nombre de colonies.
func summary() -> Dictionary:
	var result := colonies[active].summary()
	result.colonies = colonies.size()
	result.last_saved_unix = colonies[active].last_saved_unix
	return result
