extends SceneTree
## Captures d'écran (vérification visuelle), avec une colonie construite par le joueur simulé.
## Lancement (avec fenêtre, pas en headless) :
##   godot --path . --resolution 720x1400 -s tests/capture.gd -- --save=capture --out=<dossier> --scenario=<nom>
## Scénarios : debut, milieu, nuit, tempete, interaction. La sauvegarde du joueur n'est pas touchée.

var _out := "user://captures"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scenario := "milieu"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--scenario="):
			scenario = arg.trim_prefix("--scenario=")
	DirAccess.make_dir_recursive_absolute(_out)

	var manager: Node = root.get_node("GameManager")
	manager.take_startup_report()
	var engine: ColonyEngine = ColonyEngine.new(ColonyState.new())
	manager.engine = engine
	var main: Control

	match scenario:
		"debut":
			main = await _open_main()
			await _shot("1_bienvenue")
			_close_modals(main)
			await _frames(20)
			await _shot("2_debut")
		"milieu":
			ColonyBot.play(engine, 22.3)
			engine.state.speed = 1
			main = await _open_main()
			_close_modals(main)
			for i in 4:
				main._select_tab(i)
				await _frames(30)
				await _shot("%d_onglet_%s" % [3 + i, ["construire", "colonie", "recherche", "savoir"][i]])
			main._show_card("moxie")
			await _shot("7_fiche")
			_close_modals(main)
			main._show_resource("oxygen")
			await _shot("8_ressource")
			_close_modals(main)
			main._show_building(1)
			await _shot("9_module")
			_close_modals(main)
			main._start_placement("habitat")
			await _frames(30)
			main._world.move_ghost(engine.map.lander_cell + Vector2i(-3, 3))
			await _shot("10_placement")
		"nuit":
			ColonyBot.play(engine, 21.9)
			main = await _open_main()
			_close_modals(main)
			main._window.toggle_collapsed()
			await _frames(30)
			await _shot("11_nuit")
		"tempete":
			ColonyBot.play(engine, 22.4)
			engine.state.storm_until = engine.state.sol + 3.0
			main = await _open_main()
			_close_modals(main)
			main._window.toggle_collapsed()
			await _frames(120)
			await _shot("12_tempete")
		"interaction":
			main = await _open_main()
			_close_modals(main)
			await _frames(10)
			var row = main._pages[0].list.get_child(0)
			await _tap(row._button.get_global_rect().get_center())
			print("toucher « Placer » ouvre le placement : ", main._world.is_placing())
			var before := engine.state.buildings.size()
			main._world.move_ghost(engine.map.lander_cell + Vector2i(2, 0))
			await _tap(main._placement_confirm.get_global_rect().get_center())
			print("« Construire ici » pose le module : ", engine.state.buildings.size() == before + 1)
			var rig_before: Vector3 = main._world.rig.position
			await _drag(Vector2(360, 420), Vector2(-150, 60))
			print("glisser déplace la caméra : ", main._world.rig.position != rig_before)
	quit()


func _open_main() -> Control:
	var main: Control = load("res://ui/main.tscn").instantiate()
	root.add_child(main)
	await _frames(90)
	return main


func _close_modals(main: Control) -> void:
	for modal in main._modal_layer.get_children():
		modal.queue_free()


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _shot(file_name: String) -> void:
	await _frames(25)
	root.get_texture().get_image().save_png(_out.path_join(file_name + ".png"))
	print("capture : ", file_name)


func _tap(at: Vector2) -> void:
	_mouse_button(at, true)
	await _frames(3)
	_mouse_button(at, false)
	await _frames(10)


func _drag(from: Vector2, offset: Vector2) -> void:
	_mouse_button(from, true)
	await _frames(2)
	for i in range(1, 13):
		var motion := InputEventMouseMotion.new()
		motion.position = root.get_final_transform() * (from + offset * i / 12.0)
		motion.relative = offset / 12.0
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(motion)
		await _frames(1)
	_mouse_button(from + offset, false)
	await _frames(10)


func _mouse_button(at: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = root.get_final_transform() * at
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	Input.parse_input_event(event)
