class_name SaveService
extends RefCounted
## Sérialisation JSON de ColonyState vers un SaveStorage.

enum LoadResult {
	## Aucune sauvegarde : nouvelle partie.
	NEW_GAME,
	LOADED,
	## Sauvegarde principale illisible ou absente, copie de secours utilisée.
	RESTORED_FROM_BACKUP,
	## Rien de lisible : nouvelle partie, l'ancien fichier est mis de côté.
	CORRUPTED,
}

## Résultat du dernier load_state().
var last_result := LoadResult.NEW_GAME

var _storage: SaveStorage


func _init(storage: SaveStorage) -> void:
	_storage = storage


## Charge la sauvegarde, sinon sa copie de secours, sinon un état neuf.
## Une sauvegarde illisible n'est jamais écrasée : elle est mise de côté.
func load_state() -> ColonyState:
	var primary := _storage.read()
	var state := _parse(primary)
	if state != null:
		last_result = LoadResult.LOADED
		return state

	var primary_unreadable := not primary.strip_edges().is_empty()
	if primary_unreadable:
		push_warning("Sauvegarde illisible, mise de côté.")
		_storage.quarantine()

	state = _parse(_storage.read_backup())
	if state != null:
		last_result = LoadResult.RESTORED_FROM_BACKUP
		return state

	last_result = LoadResult.CORRUPTED if primary_unreadable else LoadResult.NEW_GAME
	return ColonyState.new()


## Charge une campagne (plusieurs colonies). Une ancienne sauvegarde à une colonie est convertie.
func load_campaign() -> Campaign:
	var primary := _storage.read()
	var data: Variant = _parse_json(primary)
	if is_campaign_data(data):
		last_result = LoadResult.LOADED
		return Campaign.from_dict(data)
	var primary_unreadable := not primary.strip_edges().is_empty()
	if primary_unreadable:
		push_warning("Sauvegarde illisible, mise de côté.")
		_storage.quarantine()
	data = _parse_json(_storage.read_backup())
	if is_campaign_data(data):
		last_result = LoadResult.RESTORED_FROM_BACKUP
		return Campaign.from_dict(data)
	last_result = LoadResult.CORRUPTED if primary_unreadable else LoadResult.NEW_GAME
	return Campaign.from_state(ColonyState.new())


func save_campaign(campaign: Campaign, now_unix: int) -> void:
	for state in campaign.colonies:
		state.last_saved_unix = now_unix
	_storage.write(JSON.stringify(campaign.to_dict(), "", true, true))


## Vrai si `data` a la forme d'une partie : une campagne (liste de colonies non vide) ou une
## ancienne sauvegarde à une colonie. Un JSON valide mais vide (`{}`) ou abîmé ne compte pas :
## le charger donnerait une partie neuve qui écraserait la vraie au prochain enregistrement.
static func is_campaign_data(data: Variant) -> bool:
	if not data is Dictionary:
		return false
	if not data.has("colonies"):
		return is_colony_data(data)
	if not data.colonies is Array or data.colonies.is_empty():
		return false
	for item: Variant in data.colonies:
		if not is_colony_data(item):
			return false
	return true


## Vrai si `data` a la forme d'une colonie sauvegardée (sol, ressources, modules, colons).
static func is_colony_data(data: Variant) -> bool:
	return data is Dictionary and (data.get("sol") is float or data.get("sol") is int) \
			and data.get("resources") is Dictionary and data.get("buildings") is Array and data.get("colonists") is Array


static func _parse_json(text: String) -> Variant:
	if text.strip_edges().is_empty():
		return null
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary:
		return null
	return json.data


func save_state(state: ColonyState, now_unix: int) -> void:
	state.last_saved_unix = now_unix
	# full_precision : sans lui, les grands montants perdraient des chiffres significatifs.
	_storage.write(JSON.stringify(state.to_dict(), "", true, true))


static func now_unix() -> int:
	return int(Time.get_unix_time_from_system())


## État lu depuis un texte JSON, ou null s'il est vide ou illisible.
static func _parse(text: String) -> ColonyState:
	if text.strip_edges().is_empty():
		return null
	var json := JSON.new()
	if json.parse(text) != OK or not is_colony_data(json.data):
		return null
	return ColonyState.from_dict(json.data)
