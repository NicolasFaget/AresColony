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
		elif arg.begins_with("--lang="):
			var manager_node: Node = root.get_node("GameManager")
			manager_node.locale = arg.trim_prefix("--lang=")
			manager_node._apply_locale()
	DirAccess.make_dir_recursive_absolute(_out)

	var manager: Node = root.get_node("GameManager")
	manager.splash_shown = "--splash" not in OS.get_cmdline_user_args()
	manager.take_startup_report()
	var engine: ColonyEngine = ColonyEngine.new(ColonyState.new())
	manager.engine = engine
	var main: Control

	match scenario:
		"menu":
			manager.stop_game()
			var menu: Control = load("res://ui/menu.tscn").instantiate()
			root.add_child(menu)
			await _frames(150)
			await _shot("17_menu")
			menu._show_slots()
			await _frames(30)
			await _shot("18_sauvegardes")
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
			await _frames(30)
			await _shot("11_nuit")
		"tempete":
			ColonyBot.play(engine, 22.4)
			engine.state.storm_until = engine.state.sol + 3.0
			main = await _open_main()
			_close_modals(main)
			await _frames(120)
			await _shot("12_tempete")
		"zoom":
			ColonyBot.play(engine, 22.3)
			engine.state.speed = 1
			main = await _open_main()
			_close_modals(main)
			var rig: Node3D = main._world.rig
			# Centre sur la première conduite (le réseau vers la glace).
			var target := Vector3(engine.map.lander_cell.x, 0, engine.map.lander_cell.y)
			for i in engine.state.buildings.size():
				if engine.state.buildings[i].id == "link":
					target = Vector3(engine.state.buildings[i].x + 0.5, 0, engine.state.buildings[i].y + 0.5)
					break
			rig.camera.size = 7.0
			rig.position = target
			await _frames(500)
			await _shot("13_zoom_reseau")
			# Plein jour, caméra sur un astronaute visible.
			engine.state.sol = floorf(engine.state.sol) + 1.42
			_close_modals(main)
			await _frames(400)
			_close_modals(main)
			for agent: Dictionary in main._world._agents:
				var a: Node3D = agent.node
				if a.visible:
					rig.position = a.position
					break
			rig.camera.size = 3.2
			await _frames(5)
			await _shot("14_zoom_astronautes")
		"alerte":
			engine.state.next_storm = 1e9
			engine.advance(7.4)
			main = await _open_main()
			_close_modals(main)
			await _frames(30)
			await _shot("15_alerte")
			await _tap(main._alert.get_child(0).get_child(2).get_global_rect().get_center())
			await _frames(40)
			await _shot("16_que_faire")
		"synergies":
			for r: Defs.Research in engine.research_defs.values():
				engine.state.research_done.append(r.id)
			engine.state.resources[ColonyContent.MATERIALS] = 600.0
			var lander := engine.map.lander_cell
			for x in range(lander.x - 1, lander.x + 9):
				for y in range(lander.y - 1, lander.y + 6):
					if engine.map.tile_at(Vector2i(x, y)) != ColonyMap.Tile.RIM:
						engine.map.set_tile(Vector2i(x, y), ColonyMap.Tile.PLAIN)
			engine.place("habitat", lander + Vector2i(2, 0))
			engine.place("habitat", lander + Vector2i(4, 0))
			engine.place("greenhouse", lander + Vector2i(6, 0))
			engine.place("moxie", lander + Vector2i(6, 2))
			engine.place("solar", lander + Vector2i(0, 2))
			engine.place("battery", lander + Vector2i(0, 3))
			print("synergies actives : ", engine.active_synergy_count())
			main = await _open_main()
			_close_modals(main)
			if not main._window.collapsed:
				main._window.toggle_collapsed()
			main._world.rig.zoom(0.7)
			main._world.rig.focus(main._world.cell_center(lander + Vector2i(3, 1)), 0.0)
			await _frames(30)
			await _shot("29_jonctions_dorees")
			main._start_placement("greenhouse")
			main._world.move_ghost(lander + Vector2i(2, 2))
			main._refresh_placement()
			await _shot("30_apercu_synergie")
			main._stop_placement()
			main._show_synergies()
			await _shot("31_liste_synergies")
			_close_modals(main)
			main._show_building(3)
			await _shot("32_fiche_synergie")
		"fiches":
			ColonyBot.play(engine, 9.0)
			engine.state.speed = 0
			main = await _open_main()
			_close_modals(main)
			main._queue_discovery("storm")
			engine.unlock_card("storm")
			await _frames(40)
			await _shot("40_decouverte")
			_close_modals(main)
			main._discovery = null
			main._discoveries.clear()
			main._select_tab(3)
			await _frames(30)
			await _shot("41_encyclopedie")
			main._show_card("moxie")
			await _frames(10)
			var scroll: ScrollContainer = main._modal_layer.get_child(-1).find_children("*", "ScrollContainer", true, false)[0]
			scroll.scroll_vertical = 420
			await _shot("42_fiche_quiz")
			engine.answer_quiz("moxie", 0)
			_close_modals(main)
			main._show_card("moxie")
			await _frames(10)
			scroll = main._modal_layer.get_child(-1).find_children("*", "ScrollContainer", true, false)[0]
			scroll.scroll_vertical = 420
			await _shot("43_quiz_repondu")
		"ameliorations":
			ColonyBot.play(engine, 30.0)
			engine.state.speed = 0
			engine.state.resources[ColonyContent.DATA] = 80.0
			main = await _open_main()
			_close_modals(main)
			main._select_tab(1)
			await _frames(30)
			await _shot("50_note")
			var target := -1
			for i in engine.state.buildings.size():
				if engine.state.buildings[i].id == "greenhouse":
					target = i
			engine.upgrade(target)
			main._show_building(target)
			await _shot("51_amelioration")
			_close_modals(main)
			if not main._window.collapsed:
				main._window.toggle_collapsed()
			main._world.rig.focus(main._world.footprint_center(engine.cell_of(target), Vector2i(2, 2)), 0.0)
			main._world.rig.zoom(0.7)
			await _frames(30)
			await _shot("52_niveaux")
		"entretien":
			ColonyBot.play(engine, 47.0)
			engine.state.speed = 0
			engine.dust_rate = 0.0
			for i in engine.state.buildings.size():
				if engine.def_of(i).solar:
					engine.state.buildings[i].dust = 0.55
			var kiln := -1
			for i in engine.state.buildings.size():
				if engine.state.buildings[i].id in ["moxie", "extractor"] and kiln < 0:
					engine.state.buildings[i].broken = true
					kiln = i
			engine.state.research_done.append("regolith")
			engine.state.resources[ColonyContent.MATERIALS] = 300.0
			var spot := ColonyBot.connected_spot(engine, "kiln")
			engine.place("kiln", spot)
			engine.state.sol = floorf(engine.state.sol) + 1.45
			engine.advance(0.05)
			main = await _open_main()
			_close_modals(main)
			if not main._window.collapsed:
				main._window.toggle_collapsed()
			main._world.rig.zoom(0.75)
			await _frames(30)
			await _shot("60_alerte_entretien")
			main._show_maintenance()
			await _shot("61_entretien")
			_close_modals(main)
			main._select_tab(1)
			if main._window.collapsed:
				main._window.toggle_collapsed()
			await _frames(30)
			await _shot("62_colonie")
			_close_modals(main)
			for i in engine.state.buildings.size():
				if engine.state.buildings[i].id == "kiln":
					if not main._window.collapsed:
						main._window.toggle_collapsed()
					main._world.rig.focus(main._world.footprint_center(engine.cell_of(i), Vector2i(2, 2)), 0.0)
					await _frames(30)
					await _shot("63_four")
					break
		"ere2":
			ColonyBot.play(engine, 104.0)
			engine.state.speed = 0
			engine.state.sol = floorf(engine.state.sol) + 1.45
			engine.advance(0.05)
			main = await _open_main()
			_close_modals(main)
			main._on_era_started(2)
			await _shot("70_ere2")
			_close_modals(main)
			main._select_tab(1)
			if main._window.collapsed:
				main._window.toggle_collapsed()
			await _frames(30)
			await _shot("71_colonie_ere2")
			main._show_expeditions()
			await _shot("72_expeditions")
			_close_modals(main)
			if not main._window.collapsed:
				main._window.toggle_collapsed()
			for id in ["erv", "sabatier", "garage"]:
				for i in engine.state.buildings.size():
					if engine.state.buildings[i].id == id:
						main._world.rig.focus(main._world.footprint_center(engine.cell_of(i), Vector2i(2, 2)), 0.0)
						await _frames(30)
						await _shot("73_" + id)
						break
		"rover":
			ColonyBot.play(engine, 40.0)
			engine.state.speed = 0
			engine.state.era = 2
			for id in ["sabatier", "rovers"]:
				if not engine.state.research_done.has(id):
					engine.state.research_done.append(id)
			engine.state.resources[ColonyContent.MATERIALS] = 300.0
			engine.place("garage", ColonyBot.connected_spot(engine, "garage"))
			engine.state.resources[ColonyContent.METHANE] = 0.0
			engine.state.sol = floorf(engine.state.sol) + 1.4
			engine.state.expedition = { "site": "delta", "until": engine.state.sol + ColonyEngine.EXPEDITION_SOLS - 0.12 }
			main = await _open_main()
			_close_modals(main)
			if not main._window.collapsed:
				main._window.toggle_collapsed()
			main._world.rig.focus(main._world._rover.position if main._world._rover != null else Vector3(12, 0, 12), 0.0)
			await _frames(5)
			main._world.rig.focus(main._world._rover.position, 0.0)
			main._world.rig.zoom(0.8)
			await _frames(40)
			await _shot("80_rover")
		"ere3":
			ColonyBot.play(engine, 146.0)
			engine.state.speed = 0
			engine.state.sol = floorf(engine.state.sol) + 1.45
			engine.state.next_flare = engine.state.sol + 0.3
			engine.advance(0.05)
			main = await _open_main()
			_close_modals(main)
			main._on_era_started(3)
			await _shot("90_ere3")
			_close_modals(main)
			if not main._window.collapsed:
				main._window.toggle_collapsed()
			for id in ["biodome", "reactor", "bunker"]:
				for i in engine.state.buildings.size():
					if engine.state.buildings[i].id == id:
						main._world.rig.focus(main._world.footprint_center(engine.cell_of(i), engine.def_of(i).size), 0.0)
						await _frames(30)
						await _shot("91_" + id)
						break
			main._select_tab(1)
			main._window.toggle_collapsed()
			await _frames(30)
			await _shot("92_colonie_ere3")
		"biodome":
			engine.state.research_done.append("soil")
			engine.state.resources[ColonyContent.MATERIALS] = 400.0
			var spot := ColonyBot.connected_spot(engine, "biodome")
			engine.place("biodome", spot)
			engine.state.sol = 1.45
			main = await _open_main()
			_close_modals(main)
			if not main._window.collapsed:
				main._window.toggle_collapsed()
			main._world.rig.focus(main._world.footprint_center(spot, Vector2i(3, 3)), 0.0)
			main._world.rig.zoom(0.7)
			await _frames(30)
			await _shot("93_biodome")
		"arcadia":
			manager.stop_game()
			var menu: Control = load("res://ui/menu.tscn").instantiate()
			root.add_child(menu)
			await _frames(120)
			menu._choose_region("save3")
			await _frames(20)
			await _shot("95_choix_site")
			menu.queue_free()
			await _frames(5)
			var st := ColonyState.new()
			st.region = "arcadia"
			engine = ColonyEngine.new(st)
			manager.engine = engine
			ColonyBot.play(engine, 25.0)
			engine.state.speed = 0
			engine.state.sol = floorf(engine.state.sol) + 1.45
			engine.state.research_done.append("ice")
			main = await _open_main()
			_close_modals(main)
			if not main._window.collapsed:
				main._window.toggle_collapsed()
			main._world.rig.zoom(1.25)
			await _frames(30)
			await _shot("96_arcadia")
		"splash":
			manager.stop_game()
			var menu: Control = load("res://ui/menu.tscn").instantiate()
			root.add_child(menu)
			for t in [0.5, 1.0, 1.8]:
				await create_timer(t if t == 0.5 else 0.6).timeout
				await _shot("00_splash_%s" % str(t).replace(".", "_"))
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
