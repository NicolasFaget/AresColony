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
	for text in [_storage.read(), _storage.read_backup()]:
		var data: Variant = _parse_json(text)
		if data is Dictionary:
			last_result = LoadResult.LOADED if text == _storage.read() else LoadResult.RESTORED_FROM_BACKUP
			return Campaign.from_dict(data)
		if text == _storage.read() and not text.strip_edges().is_empty():
			push_warning("Sauvegarde illisible, mise de côté.")
			_storage.quarantine()
	last_result = LoadResult.NEW_GAME
	return Campaign.from_state(ColonyState.new())


func save_campaign(campaign: Campaign, now_unix: int) -> void:
	for state in campaign.colonies:
		state.last_saved_unix = now_unix
	_storage.write(JSON.stringify(campaign.to_dict(), "", true, true))


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
	if json.parse(text) != OK or not json.data is Dictionary:
		return null
	return ColonyState.from_dict(json.data)
