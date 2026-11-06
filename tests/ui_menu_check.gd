## Vérification des parcours du menu et des fenêtres (suppression d'une sauvegarde, retour au menu,
## libération de la partie fermée). Sauvegardes dans user://ui_check (jamais celles du joueur),
## interface en français. Chaque contrôle raté fait échouer le script (code de sortie 1).
## Usage : godot --headless --path . -s tests/ui_menu_check.gd
extends SceneTree

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, label: String) -> void:
	print("%s %s" % ["OK    " if ok else "ÉCHEC ", label])
	if not ok:
		_failures += 1


func _press(node: Node, text: String) -> bool:
	for b in node.find_children("*", "Button", true, false):
		if (b as Button).text == text and b.is_visible_in_tree():
			(b as Button).pressed.emit()
			return true
	return false


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _run() -> void:
	var gm: Node = root.get_node("GameManager")
	gm.splash_shown = true
	# Les boutons sont cherchés par leur texte français, quelle que soit la langue de la machine.
	gm.locale = "fr"
	gm._apply_locale()
	# Dossier à part : les vraies sauvegardes du joueur ne sont jamais touchées.
	gm.save_dir = "user://ui_check"
	DirAccess.make_dir_recursive_absolute(gm.save_dir)
	for slot in gm.SLOTS:
		gm.delete_slot(slot)

	# Une partie créée puis fermée est bien écrite sur le disque, et relisible.
	gm.start_game("save", true)
	gm.stop_game()
	var reread := SaveService.new(FileSaveStorage.new(gm.save_dir, "save"))
	reread.load_campaign()
	_check(reread.last_result == SaveService.LoadResult.LOADED, "sauvegarde écrite et relue")

	# Suppression d'une sauvegarde depuis le menu.
	var menu: Control = load("res://ui/menu.tscn").instantiate()
	root.add_child(menu)
	await _frames(20)
	_check(menu._continue.visible, "départ : « Continuer » visible")
	menu._show_slots()
	await process_frame
	_check(_press(menu, "Supprimer"), "bouton Supprimer trouvé")
	await _frames(5)
	_check(_press(menu._modal_layer.get_child(-1), "Supprimer"), "confirmation de suppression")
	await _frames(30)
	_check(not menu._continue.visible, "après suppression : « Continuer » caché")
	_check(gm.most_recent_slot() == "", "après suppression : plus aucune partie récente")
	var leftovers := Array(DirAccess.get_files_at(gm.save_dir)).filter(func(f: String) -> bool: return f.begins_with("save"))
	_check(leftovers.is_empty(), "après suppression : fichiers effacés %s" % [leftovers])
	await _frames(60)
	var stuck := 0
	for m in menu._modal_layer.get_children():
		if not m._closing:
			stuck += 1
	_check(stuck <= 1, "fenêtres : pas d'empilement (%d ouverte(s))" % stuck)

	# Bouton « Menu principal » des réglages en jeu.
	menu.queue_free()
	gm.start_game("save", true)
	var campaign_ref: WeakRef = weakref(gm.campaign)
	var engine_ref: WeakRef = weakref(gm.engine)
	var main: Control = load("res://ui/main.tscn").instantiate()
	root.add_child(main)
	await _frames(30)
	for modal in main._modal_layer.get_children():
		modal.queue_free()
	await process_frame
	main._show_settings()
	await process_frame
	_check(_press(main._modal_layer.get_child(-1), "Menu principal"), "bouton Menu principal trouvé")
	await _frames(30)
	_check(current_scene != null and current_scene.scene_file_path == "res://ui/menu.tscn", "retour au menu principal")
	_check(gm.engine == null and gm.campaign == null, "partie fermée")

	# La partie fermée est libérée (pas de référence circulaire qui la garderait en mémoire).
	main.queue_free()
	await _frames(5)
	_check(campaign_ref.get_ref() == null and engine_ref.get_ref() == null, "partie fermée libérée de la mémoire")

	gm.delete_slot("save")
	print("Contrôle du menu : %d échec(s)" % _failures)
	quit(1 if _failures > 0 else 0)
