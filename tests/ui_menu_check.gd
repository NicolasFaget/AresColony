## Vérification des parcours du menu et des fenêtres (suppression d'une sauvegarde, retour au menu).
## Sauvegardes dans user://ui_check (jamais celles du joueur), interface en français.
## Usage : godot --headless --path . -s tests/ui_menu_check.gd
extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _press(node: Node, text: String) -> bool:
	for b in node.find_children("*", "Button", true, false):
		if (b as Button).text == text and b.is_visible_in_tree():
			(b as Button).pressed.emit()
			return true
	return false

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
	gm.start_game("save", true)
	gm.stop_game()
	var menu: Control = load("res://ui/menu.tscn").instantiate()
	root.add_child(menu)
	for i in 20:
		await process_frame
	print("départ : continuer visible = ", menu._continue.visible)
	menu._show_slots()
	await process_frame
	var texts := []
	for b in menu.find_children("*", "Button", true, false):
		texts.append("%s%s" % [(b as Button).text, "" if b.is_visible_in_tree() else " (caché)"])
	print("boutons : ", texts, " · langue ", TranslationServer.get_locale())
	print("bouton Supprimer : ", _press(menu, "Supprimer"))
	for i in 5:
		await process_frame
	print("confirmation : ", _press(menu._modal_layer.get_child(-1), "Supprimer"))
	for i in 30:
		await process_frame
	print("après : continuer visible = ", menu._continue.visible, " ; plus récente = '", gm.most_recent_slot(), "' ; fichiers ", DirAccess.get_files_at(gm.save_dir))
	for i in 60:
		await process_frame
	for m in menu._modal_layer.get_children():
		var labels := []
		for l in m.find_children("*", "Label", true, false):
			labels.append((l as Label).text)
		print("fenêtre restante : ", labels.slice(0, 2), " en fermeture = ", m._closing)
	# Bouton « Menu principal » des réglages en jeu.
	menu.queue_free()
	gm.start_game("save", true)
	var main: Control = load("res://ui/main.tscn").instantiate()
	root.add_child(main)
	for i in 30:
		await process_frame
	for modal in main._modal_layer.get_children():
		modal.queue_free()
	await process_frame
	main._show_settings()
	await process_frame
	print("bouton Menu principal : ", _press(main._modal_layer.get_child(-1), "Menu principal"))
	for i in 30:
		await process_frame
	print("scène après : ", current_scene.scene_file_path if current_scene else "aucune", " ; partie fermée = ", gm.engine == null)
	gm.delete_slot("save")
	quit()
