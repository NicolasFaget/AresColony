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
## Ère en cours (1 : Survie, 2 : Expansion).
var era: int = 1
## Expédition en cours : { "site": identifiant, "until": sol du retour } ou {}.
var expedition: Dictionary = {}
var sites_done: Array[String] = []
var expeditions: int = 0
## Éruptions solaires (ère 3) : prochaine, et fin de celle en cours.
var next_flare: float = 1e9
var flare_until: float = -1.0
## Fiches déjà lues (la première lecture rapporte des données).
var cards_read: Array[String] = []
## Quiz répondus : identifiant de fiche -> vrai si bonne réponse (une seule tentative).
var quiz_answers: Dictionary = {}

var map_seed: int = 1
## Région d'atterrissage (ColonyContent.REGIONS).
var region: String = "jezero"
## Matériaux expédiés vers d'autres colonies (objectif de Cérès).
var exported_materials: float = 0.0
## Nom de la colonie (plusieurs colonies peuvent partager une région : « Jezero II »).
var name: String = ""
## Graine des événements, avancée à chaque tirage (parties reproductibles).
var event_seed: int = 1
var next_storm: float = 12.0
var storm_until: float = -1.0
var next_resupply: float = 8.0
var resupply_count: int = 0
## Prochain tourbillon de poussière (il nettoie quelques panneaux).
var next_dust_devil: float = 7.0
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
## Ères dont le guide a été passé (le guide de l'ère 1 suit tutorial_done).
var guides_skipped: Array[int] = []


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
		"region": region,
		"name": name,
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
		"era": era,
		"expedition": expedition.duplicate(),
		"sites_done": sites_done.duplicate(),
		"expeditions": expeditions,
		"next_flare": next_flare,
		"flare_until": flare_until,
		"cards_read": cards_read.duplicate(),
		"quiz_answers": quiz_answers.duplicate(),
		"map_seed": map_seed,
		"exported_materials": exported_materials,
		"name": name,
		"region": region,
		"event_seed": event_seed,
		"next_storm": next_storm,
		"storm_until": storm_until,
		"next_resupply": next_resupply,
		"resupply_count": resupply_count,
		"next_dust_devil": next_dust_devil,
		"recruits_sent": recruits_sent,
		"evacuated": evacuated,
		"autonomy_streak": autonomy_streak,
		"last_saved_unix": last_saved_unix,
		"settings": {
			"speed": speed, "haptics": haptics_enabled, "music": music_enabled, "sound": sound_enabled,
			"tutorial_done": tutorial_done, "guides_skipped": guides_skipped.duplicate(),
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
				var building := { "id": item.id, "x": int(_num(item.get("x"), 0)), "y": int(_num(item.get("y"), 0)),
						"level": clampi(int(_num(item.get("level"), 1)), 1, 3) }
				if item.has("dust"):
					building.dust = clampf(_num(item.dust, 0.0), 0.0, 1.0)
				if item.get("broken") == true:
					building.broken = true
				state.buildings.append(building)
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
	state.era = clampi(int(_num(data.get("era"), 1)), 1, 4)
	state.name = str(data.get("name", "")) if data.get("name") is String else ""
	state.exported_materials = maxf(0.0, _num(data.get("exported_materials"), 0.0))
	var trip: Variant = data.get("expedition")
	if trip is Dictionary and trip.get("site") is String:
		state.expedition = { "site": trip.site, "until": _num(trip.get("until"), 0.0) }
	state.sites_done = _ids(data.get("sites_done"))
	state.expeditions = int(_num(data.get("expeditions"), 0))
	state.next_flare = _num(data.get("next_flare"), state.next_flare)
	state.flare_until = _num(data.get("flare_until"), -1.0)
	state.cards_read = _ids(data.get("cards_read"))
	var answers: Variant = data.get("quiz_answers")
	if answers is Dictionary:
		for key: Variant in answers:
			if answers[key] is bool:
				state.quiz_answers[str(key)] = answers[key]
	state.map_seed = int(_num(data.get("map_seed"), 1))
	var region: Variant = data.get("region")
	state.region = region if region is String and ColonyContent.REGIONS.has(region) else "jezero"
	state.event_seed = int(_num(data.get("event_seed"), 1))
	state.next_storm = _num(data.get("next_storm"), state.next_storm)
	state.storm_until = _num(data.get("storm_until"), -1.0)
	state.next_resupply = _num(data.get("next_resupply"), state.next_resupply)
	state.resupply_count = int(_num(data.get("resupply_count"), 0))
	state.next_dust_devil = _num(data.get("next_dust_devil"), state.next_dust_devil)
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
		var skipped: Variant = settings.get("guides_skipped")
		if skipped is Array:
			for era: Variant in skipped:
				if era is float or era is int:
					state.guides_skipped.append(int(era))
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
