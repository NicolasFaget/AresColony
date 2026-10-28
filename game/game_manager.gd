extends Node
## Autoload « GameManager » : seul point de contact entre le cœur du jeu et Godot.
## Emplacements de sauvegarde, partie en cours (boucle de simulation, sauvegarde automatique,
## pilote automatique hors-ligne), réglages du joueur, vibrations.
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

## Emplacements de sauvegarde (le premier reprend l'ancien fichier unique « save »).
const SLOTS: Array[String] = ["save", "save2", "save3"]
const SETTINGS_PATH := "user://settings.json"
## Dossier des emplacements de sauvegarde (un test peut en choisir un autre).
var save_dir := "user://"
const MENU_SCENE := "res://ui/menu.tscn"
const GAME_SCENE := "res://ui/main.tscn"

## Partie en cours (toutes ses colonies), ou null au menu principal.
var campaign: Campaign
## Colonie affichée (celle de la campagne), ou null au menu principal.
var engine: ColonyEngine
var current_slot := ""
var load_result: SaveService.LoadResult
## Réglages communs à toutes les parties.
var settings := { "music": true, "sound": true, "haptics": true }
## Langue de l'interface : "fr" ou "en" (par défaut, celle du téléphone).
var locale := ""
var _english_loaded := false
## L'écran du studio ne s'affiche qu'au lancement de l'application.
var splash_shown := false

var _save_service: SaveService
var _since_last_save := 0.0
var _since_last_refresh := 0.0
var _startup_report := {}
var _skip_next_delta := false
var _fps_timer := 0.0


func _ready() -> void:
	get_tree().auto_accept_quit = false
	_load_settings()
	_apply_locale()
	# Outils (tests, captures) : `-- --save=nom` démarre directement une partie dans cet emplacement.
	var slot := _cmdline_slot()
	if not slot.is_empty():
		start_game(slot)


func _process(delta: float) -> void:
	_debug_fps(delta)
	if engine == null:
		return
	if _skip_next_delta:
		_skip_next_delta = false
	elif delta > LONG_FRAME_SECONDS:
		_report(campaign.apply_offline_seconds(delta))
	else:
		campaign.tick(delta)

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
			if engine != null:
				_skip_next_delta = true
				var report := campaign.apply_offline(SaveService.now_unix())
				save()
				_report(report)
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			save()
		NOTIFICATION_WM_GO_BACK_REQUEST:
			save()
			var scene := get_tree().current_scene
			if scene != null and scene.has_method("on_back"):
				scene.on_back()
			else:
				get_tree().quit()
		NOTIFICATION_WM_CLOSE_REQUEST:
			save()
			get_tree().quit()


# ---------- Parties ----------

## Charge (ou crée, si `new_game`) la partie de l'emplacement `slot`.
func start_game(slot: String, new_game := false, region := "jezero") -> void:
	current_slot = slot
	_save_service = SaveService.new(FileSaveStorage.new(save_dir, slot))
	if new_game:
		var state := ColonyState.new()
		state.region = region
		campaign = Campaign.from_state(state)
	else:
		campaign = _save_service.load_campaign()
	load_result = SaveService.LoadResult.NEW_GAME if new_game else _save_service.last_result
	_attach_engine()
	_startup_report = campaign.apply_offline(SaveService.now_unix())
	_since_last_save = 0.0
	save()


## Sauvegarde et ferme la partie en cours.
func stop_game() -> void:
	save()
	engine = null
	campaign = null
	_save_service = null
	current_slot = ""


## Affiche une autre colonie de la campagne (l'écran de jeu est reconstruit).
func switch_colony(index: int) -> void:
	if campaign == null or index == campaign.active:
		return
	save()
	campaign.switch_to(index)
	_attach_engine()
	load_result = SaveService.LoadResult.LOADED
	get_tree().change_scene_to_file(GAME_SCENE)


func _attach_engine() -> void:
	if engine != null and engine.changed.is_connected(_on_engine_changed):
		engine.changed.disconnect(_on_engine_changed)
	engine = campaign.engine()
	engine.changed.connect(_on_engine_changed)


func open_menu() -> void:
	stop_game()
	get_tree().change_scene_to_file(MENU_SCENE)


func open_game(slot: String, new_game := false, region := "jezero") -> void:
	start_game(slot, new_game, region)
	get_tree().change_scene_to_file(GAME_SCENE)


func save() -> void:
	if campaign != null and _save_service != null:
		_save_service.save_campaign(campaign, SaveService.now_unix())
	_since_last_save = 0.0


## Résumé d'un emplacement (voir ColonyState.summary), ou {} s'il est vide.
func slot_summary(slot: String) -> Dictionary:
	var storage := FileSaveStorage.new(save_dir, slot)
	if storage.read().strip_edges().is_empty() and storage.read_backup().strip_edges().is_empty():
		return {}
	return SaveService.new(storage).load_campaign().summary()


## Emplacement joué le plus récemment, ou "" s'il n'y a aucune sauvegarde.
func most_recent_slot() -> String:
	var best := ""
	var latest := -1
	for slot in SLOTS:
		var summary := slot_summary(slot)
		if not summary.is_empty() and summary.last_saved_unix > latest:
			latest = summary.last_saved_unix
			best = slot
	return best


func first_free_slot() -> String:
	for slot in SLOTS:
		if slot_summary(slot).is_empty():
			return slot
	return ""


## Parties de test des versions de développement (voir tools/make_test_save.gd).
const TEST_SAVES_DIR := "res://game/test_saves/"


## Copie la partie de test `test_name` (« ere4 », « ceres », « titan ») dans l'emplacement `slot`, datée de
## maintenant (pas d'absence à rattraper).
func install_test_save(slot: String, test_name: String) -> bool:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(TEST_SAVES_DIR + test_name + ".json"))
	if not data is Dictionary:
		return false
	SaveService.new(FileSaveStorage.new(save_dir, slot)).save_campaign(Campaign.from_dict(data), SaveService.now_unix())
	return true


func delete_slot(slot: String) -> void:
	var storage := FileSaveStorage.new(save_dir, slot)
	for path in [storage.save_path, storage.backup_path, storage.temp_path]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


## Rapport hors-ligne du démarrage, à afficher une seule fois. Vide s'il n'y a rien à montrer.
func take_startup_report() -> Dictionary:
	var report := _startup_report
	_startup_report = {}
	return report if is_notable(report) else {}


static func is_notable(report: Dictionary) -> bool:
	return report.get("elapsed", 0.0) >= REPORT_MIN_SECONDS and report.get("sols", 0.0) > 0.0


func notify_changed() -> void:
	_on_engine_changed()


# ---------- Réglages ----------

func set_setting(key: String, value: bool) -> void:
	settings[key] = value
	_save_settings()


func _save_settings() -> void:
	var data := settings.duplicate()
	data.locale = locale
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data))


## Change la langue, sauvegarde et recharge l'écran en cours pour l'afficher.
func change_locale(code: String) -> void:
	locale = code
	_save_settings()
	_apply_locale()
	save()
	load_result = SaveService.LoadResult.LOADED
	get_tree().reload_current_scene()


func _apply_locale() -> void:
	if locale.is_empty():
		locale = "fr" if OS.get_locale_language() == "fr" else "en"
	if locale == "en" and not _english_loaded:
		_english_loaded = true
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://i18n/en.json"))
		if data is Dictionary:
			var translation := Translation.new()
			translation.locale = "en"
			for key: String in data:
				translation.add_message(key, data[key])
			TranslationServer.add_translation(translation)
	TranslationServer.set_locale(locale)


func vibrate(duration_ms := 12) -> void:
	if settings.haptics and OS.has_feature("mobile"):
		Input.vibrate_handheld(duration_ms)


func _load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_PATH))
	if data is Dictionary:
		for key: String in settings:
			if data.get(key) is bool:
				settings[key] = data[key]
		if data.get("locale") in ["fr", "en"]:
			locale = data.locale


# ---------- Interne ----------

func _on_engine_changed() -> void:
	_since_last_refresh = 0.0
	state_changed.emit()


func _report(report: Dictionary) -> void:
	if is_notable(report):
		offline_report.emit(report)


## Version de développement : images par seconde dans le journal (mesure sur téléphone).
func _debug_fps(delta: float) -> void:
	if not OS.is_debug_build():
		return
	_fps_timer += delta
	if _fps_timer >= 5.0:
		_fps_timer = 0.0
		var rid := get_viewport().get_viewport_rid()
		RenderingServer.viewport_set_measure_render_time(rid, true)
		print("FPS %d · GPU %.1f ms · objets %d · primitives %d" % [
			Engine.get_frames_per_second(), RenderingServer.viewport_get_measured_render_time_gpu(rid),
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])


static func _cmdline_slot() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--save="):
			return arg.trim_prefix("--save=").validate_filename()
	return ""
