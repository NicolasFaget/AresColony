class_name ColonyState
extends RefCounted
## État sauvegardable de la colonie. Uniquement des données, aucune logique de jeu.

const FORMAT_VERSION := 1

## Temps écoulé en sols (la partie entière est le numéro du sol).
var sol: float = 0.3
var resources: Dictionary = {}
## Modules posés : [{ "id": String, "x": int, "y": int }, ...]. L'atterrisseur est le premier.
var buildings: Array[Dictionary] = []
## Colons : [{ "name": String, "role": String, "health": float }, ...]
var colonists: Array[Dictionary] = []
var research_done: Array[String] = []
var research_active: String = ""
## Avancement de la recherche en cours, de 0 à 1.
var research_progress: float = 0.0
var objectives_done: Array[String] = []
var cards_unlocked: Array[String] = []
## Fiches déjà lues (la première lecture rapporte des données).
var cards_read: Array[String] = []
## Quiz répondus : identifiant de fiche -> vrai si bonne réponse (une seule tentative).
var quiz_answers: Dictionary = {}

var map_seed: int = 1
## Graine des événements, avancée à chaque tirage (parties reproductibles).
var event_seed: int = 1
var next_storm: float = 12.0
var storm_until: float = -1.0
var next_resupply: float = 8.0
var resupply_count: int = 0
var recruits_sent: int = 0
var evacuated: int = 0
## Sols consécutifs sans déficit vital (objectif « Autonomie »).
var autonomy_streak: float = 0.0
var last_saved_unix: int = 0

# Préférences du joueur.
var speed: int = 1
var haptics_enabled: bool = true
var music_enabled: bool = true
var sound_enabled: bool = true
## Tutoriel terminé ou passé.
var tutorial_done: bool = false


func amount(resource: String) -> float:
	return resources.get(resource, 0.0)


## Résumé affiché dans la liste des sauvegardes.
func summary() -> Dictionary:
	return {
		"sol": int(sol) + 1,
		"colonists": colonists.size(),
		"objectives": objectives_done.size(),
		"modules": maxi(0, buildings.size() - 1),
		"last_saved_unix": last_saved_unix,
	}


func to_dict() -> Dictionary:
	return {
		"version": FORMAT_VERSION,
		"sol": sol,
		"resources": resources.duplicate(),
		"buildings": buildings.duplicate(true),
		"colonists": colonists.duplicate(true),
		"research_done": research_done.duplicate(),
		"research_active": research_active,
		"research_progress": research_progress,
		"objectives_done": objectives_done.duplicate(),
		"cards_unlocked": cards_unlocked.duplicate(),
		"cards_read": cards_read.duplicate(),
		"quiz_answers": quiz_answers.duplicate(),
		"map_seed": map_seed,
		"event_seed": event_seed,
		"next_storm": next_storm,
		"storm_until": storm_until,
		"next_resupply": next_resupply,
		"resupply_count": resupply_count,
		"recruits_sent": recruits_sent,
		"evacuated": evacuated,
		"autonomy_streak": autonomy_streak,
		"last_saved_unix": last_saved_unix,
		"settings": {
			"speed": speed, "haptics": haptics_enabled, "music": music_enabled, "sound": sound_enabled,
			"tutorial_done": tutorial_done,
		},
	}


## Reconstruit un état depuis un dictionnaire JSON. Toute valeur invalide prend sa valeur par défaut.
static func from_dict(data: Dictionary) -> ColonyState:
	var state := ColonyState.new()
	state.sol = _num(data.get("sol"), state.sol)
	var res: Variant = data.get("resources")
	if res is Dictionary:
		for key: Variant in res:
			state.resources[str(key)] = maxf(0.0, _num(res[key], 0.0))
	var list: Variant = data.get("buildings")
	if list is Array:
		for item: Variant in list:
			if item is Dictionary and item.get("id") is String:
				state.buildings.append({ "id": item.id, "x": int(_num(item.get("x"), 0)), "y": int(_num(item.get("y"), 0)),
						"level": clampi(int(_num(item.get("level"), 1)), 1, 3) })
	list = data.get("colonists")
	if list is Array:
		for item: Variant in list:
			if item is Dictionary:
				state.colonists.append({ "name": str(item.get("name", "?")), "role": str(item.get("role", "")),
						"health": clampf(_num(item.get("health"), 1.0), 0.0, 1.0) })
	state.research_done = _ids(data.get("research_done"))
	state.research_active = str(data.get("research_active", "")) if data.get("research_active") is String else ""
	state.research_progress = clampf(_num(data.get("research_progress"), 0.0), 0.0, 1.0)
	state.objectives_done = _ids(data.get("objectives_done"))
	state.cards_unlocked = _ids(data.get("cards_unlocked"))
	state.cards_read = _ids(data.get("cards_read"))
	var answers: Variant = data.get("quiz_answers")
	if answers is Dictionary:
		for key: Variant in answers:
			if answers[key] is bool:
				state.quiz_answers[str(key)] = answers[key]
	state.map_seed = int(_num(data.get("map_seed"), 1))
	state.event_seed = int(_num(data.get("event_seed"), 1))
	state.next_storm = _num(data.get("next_storm"), state.next_storm)
	state.storm_until = _num(data.get("storm_until"), -1.0)
	state.next_resupply = _num(data.get("next_resupply"), state.next_resupply)
	state.resupply_count = int(_num(data.get("resupply_count"), 0))
	state.recruits_sent = int(_num(data.get("recruits_sent"), 0))
	state.evacuated = int(_num(data.get("evacuated"), 0))
	state.autonomy_streak = maxf(0.0, _num(data.get("autonomy_streak"), 0.0))
	state.last_saved_unix = int(_num(data.get("last_saved_unix"), 0))
	var settings: Variant = data.get("settings")
	if settings is Dictionary:
		var speed: int = int(_num(settings.get("speed"), 1))
		state.speed = speed if speed in ColonyEngine.SPEEDS else 1
		state.haptics_enabled = settings.get("haptics") if settings.get("haptics") is bool else true
		state.music_enabled = settings.get("music") if settings.get("music") is bool else true
		state.sound_enabled = settings.get("sound") if settings.get("sound") is bool else true
		state.tutorial_done = settings.get("tutorial_done") if settings.get("tutorial_done") is bool else false
	return state


static func _num(value: Variant, default: float) -> float:
	if value is float or value is int:
		var n := float(value)
		if not is_nan(n) and not is_inf(n):
			return n
	return default


static func _ids(value: Variant) -> Array[String]:
	var ids: Array[String] = []
	if value is Array:
		for item: Variant in value:
			if item is String and not ids.has(item):
				ids.append(item)
	return ids
