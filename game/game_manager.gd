extends Node
## Autoload « GameManager » : seul point de contact entre le cœur du jeu et Godot.
## Boucle de simulation, sauvegarde automatique, pilote automatique hors-ligne, vibrations.
## Les écrans lisent `engine` et appellent ses méthodes ; ils ne touchent ni au disque ni à l'horloge.

## Retour après une absence : rapport du pilote automatique (voir ColonyEngine.apply_offline).
signal offline_report(report: Dictionary)
## Changement d'état à afficher : immédiat après une action, au plus REFRESH_INTERVAL sinon.
signal state_changed

const AUTOSAVE_INTERVAL := 30.0
const REFRESH_INTERVAL := 0.1
## Une frame plus longue est une suspension (veille du PC, débogueur...) : elle passe par le
## pilote automatique, comme une absence, au lieu d'être simulée avec ses événements.
const LONG_FRAME_SECONDS := 5.0
## En dessous, le pilote automatique tourne sans afficher de rapport.
const REPORT_MIN_SECONDS := 60.0

var engine: ColonyEngine
var load_result: SaveService.LoadResult

var _save_service: SaveService
var _since_last_save := 0.0
var _since_last_refresh := 0.0
var _startup_report := {}
var _skip_next_delta := false


func _ready() -> void:
	get_tree().auto_accept_quit = false
	_save_service = SaveService.new(FileSaveStorage.new("user://", _save_slot()))
	var state := _save_service.load_state()
	load_result = _save_service.last_result
	engine = ColonyEngine.new(state)
	engine.changed.connect(_on_engine_changed)
	_startup_report = engine.apply_offline(SaveService.now_unix())
	save()


func _process(delta: float) -> void:
	if _skip_next_delta:
		_skip_next_delta = false
	elif delta > LONG_FRAME_SECONDS:
		_report(engine.apply_offline_seconds(delta))
	else:
		engine.tick(delta)

	_since_last_refresh += delta
	if _since_last_refresh >= REFRESH_INTERVAL:
		_since_last_refresh = 0.0
		state_changed.emit()

	_since_last_save += delta
	if _since_last_save >= AUTOSAVE_INTERVAL:
		save()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED:
			save()
		NOTIFICATION_APPLICATION_RESUMED:
			_skip_next_delta = true
			var report := engine.apply_offline(SaveService.now_unix())
			save()
			_report(report)
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_GO_BACK_REQUEST:
			save()
		NOTIFICATION_WM_CLOSE_REQUEST:
			save()
			get_tree().quit()


func save() -> void:
	_save_service.save_state(engine.state, SaveService.now_unix())
	_since_last_save = 0.0


## Rapport hors-ligne du démarrage, à afficher une seule fois. Vide s'il n'y a rien à montrer.
func take_startup_report() -> Dictionary:
	var report := _startup_report
	_startup_report = {}
	return report if is_notable(report) else {}


static func is_notable(report: Dictionary) -> bool:
	return report.get("elapsed", 0.0) >= REPORT_MIN_SECONDS and report.get("sols", 0.0) > 0.0


func notify_changed() -> void:
	_on_engine_changed()


func vibrate(duration_ms := 12) -> void:
	if engine.state.haptics_enabled and OS.has_feature("mobile"):
		Input.vibrate_handheld(duration_ms)


func _on_engine_changed() -> void:
	_since_last_refresh = 0.0
	state_changed.emit()


func _report(report: Dictionary) -> void:
	if is_notable(report):
		offline_report.emit(report)


## Emplacement de sauvegarde : « save » par défaut, `-- --save=nom` en ligne de commande.
static func _save_slot() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--save="):
			return arg.trim_prefix("--save=").validate_filename()
	return "save"
