extends Control
## Menu principal : une colonie de démonstration en 3D en fond, le titre, et les actions
## (continuer, nouvelle colonie, sauvegardes, réglages, à propos).

const SLOT_NAMES := { "save": "Colonie 1", "save2": "Colonie 2", "save3": "Colonie 3" }

var _world: ColonyWorld
var _modal_layer: Control
var _continue: Button
var _continue_info: Label


## Bouton Retour (Android) : ferme la fenêtre du dessus, sinon quitte l'application.
func on_back() -> void:
	for i in range(_modal_layer.get_child_count() - 1, -1, -1):
		var child := _modal_layer.get_child(i)
		if child is Modal:
			child.close()
			return
	get_tree().quit()


func _ready() -> void:
	theme = AppTheme.build()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if OS.has_feature("mobile"):
		get_viewport().scaling_3d_scale = 0.55
	# Au lancement : écran du studio, pendant que la colonie de démonstration se prépare derrière.
	var splash: Splash = null
	if not GameManager.splash_shown:
		GameManager.splash_shown = true
		splash = Splash.new()
		add_child(splash)
		await get_tree().process_frame
		await get_tree().process_frame
	_build_background()
	_build_layout()
	AudioManager.set_world("mars")
	AudioManager.set_mood("day")
	AudioManager.set_wind(0.0)
	_refresh()
	if splash != null:
		move_child(splash, -1)
		splash.done.connect(splash.queue_free)
		splash.ready_to_go = true


func _process(delta: float) -> void:
	# Lent travelling autour de la colonie.
	if _world != null:
		_world.rig.rotation_degrees.y += delta * 2.5


## Colonie de démonstration : quelques sols joués par le joueur simulé, figée au soleil couchant.
func _build_background() -> void:
	var started := Time.get_ticks_msec()
	var demo := ColonyEngine.new(ColonyState.new())
	demo.state.next_storm = 1e9
	ColonyBot.play(demo, 9.0)
	if OS.is_debug_build():
		print("Colonie de démonstration : %d ms" % (Time.get_ticks_msec() - started))
	demo.state.sol = floorf(demo.state.sol) + 0.66
	demo.state.speed = 1
	_world = ColonyWorld.new()
	_world.engine = demo
	add_child(_world)
	_world.rig.camera.size = 12.0
	_world.rig.covered_fraction = 0.25


func _build_layout() -> void:
	# Dégradé sombre en bas : les boutons restent lisibles sans grand cadre, la colonie reste visible.
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 1.0])
	gradient.colors = PackedColorArray([Color(0.03, 0.05, 0.09, 0.0), Color(0.03, 0.05, 0.09, 0.92)])
	var shade_texture := GradientTexture2D.new()
	shade_texture.gradient = gradient
	shade_texture.fill_from = Vector2(0, 0)
	shade_texture.fill_to = Vector2(0, 0.55)
	shade_texture.width = 4
	shade_texture.height = 64
	var shade := TextureRect.new()
	shade.texture = shade_texture
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	shade.offset_top = -560
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	margin.add_theme_constant_override("margin_top", 90)
	margin.add_theme_constant_override("margin_bottom", 40)
	add_child(margin)

	var title := UiFx.label(Tr.t("ARES COLONY"), "TitleLabel", HORIZONTAL_ALIGNMENT_CENTER)
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.0, 0.6))
	title.add_theme_constant_override("outline_size", 10)
	var subtitle := UiFx.label(Tr.t("Survivre sur Mars, une découverte à la fois"), "BodyLabel", HORIZONTAL_ALIGNMENT_CENTER)
	subtitle.add_theme_color_override("font_color", Palette.TEXT)
	subtitle.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.0, 0.6))
	subtitle.add_theme_constant_override("outline_size", 6)

	# « Continuer » : le titre, puis le résumé de la partie sur deux lignes, coupées par « … » si
	# besoin (le résumé ne fait jamais déborder le menu de l'écran).
	_continue = _menu_button("", "GreenButton", _on_continue)
	_continue.custom_minimum_size.y = 118
	var continue_title := UiFx.label(Tr.t("Continuer"), "HeadingLabel", HORIZONTAL_ALIGNMENT_CENTER)
	continue_title.add_theme_font_size_override("font_size", 24)
	continue_title.add_theme_color_override("font_color", Palette.ON_ACCENT)
	_continue_info = UiFx.label("", "CaptionLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_continue_info.add_theme_color_override("font_color", Palette.ON_ACCENT)
	_continue_info.clip_text = true
	_continue_info.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var continue_box := UiFx.vbox(2, [continue_title, _continue_info])
	continue_box.alignment = BoxContainer.ALIGNMENT_CENTER
	continue_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	continue_box.offset_left = 12
	continue_box.offset_right = -12
	continue_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in continue_box.get_children():
		child.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_continue.add_child(continue_box)

	# L'essentiel en grand (continuer, nouvelle colonie), le reste en petit sur une ligne, avec
	# une icône.
	var new_game := _menu_button(Tr.t("Nouvelle colonie"), "GoldButton", _on_new_game)
	var small: Array[Button] = [_small_button("save", Tr.t("Sauvegardes"), _show_slots),
			_small_button("gear", Tr.t("Réglages"), _show_settings), _small_button("info", Tr.t("À propos"), _show_about),
			_small_button("close", Tr.t("Quitter"), _quit)]
	var buttons := UiFx.vbox(12, [_continue, new_game, UiFx.hbox(10, small)])
	# Version de développement : parties de test, repliées derrière un petit bouton.
	if OS.is_debug_build():
		var tests_box := UiFx.vbox(8)
		tests_box.visible = false
		for row: Array in [[["ere1", Tr.t("Ère 1")], ["ere2", Tr.t("Ère 2")], ["ere3", Tr.t("Ère 3")], ["ere4", Tr.t("Ère 4")]],
				[["ceres", Tr.t("Cérès")], ["titan", Tr.t("Titan")], ["europa", Tr.t("Europe")], ["enceladus", Tr.t("Encelade")]]]:
			var tests := UiFx.hbox(8, [])
			for test: Array in row:
				var b := _menu_button(test[1], "Button", _on_test_game.bind(test[0]))
				b.custom_minimum_size.y = 54
				tests.add_child(b)
			tests_box.add_child(tests)
		var toggle := Button.new()
		toggle.flat = true
		toggle.text = Tr.t("Parties de test")
		toggle.focus_mode = Control.FOCUS_NONE
		toggle.add_theme_color_override("font_color", Palette.TEXT_DIM)
		toggle.pressed.connect(func() -> void: tests_box.visible = not tests_box.visible)
		buttons.add_child(toggle)
		buttons.add_child(tests_box)
	for row in buttons.find_children("*", "HBoxContainer", true, false):
		for b in row.get_children():
			if b is Button:
				b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Pas de grand cadre sombre : les boutons flottent sur la colonie, qui reste visible.
	var card := buttons

	var version := UiFx.label(Tr.t("v%s · Mars") % ProjectSettings.get_setting("application/config/version", "0.1"),
			"CaptionLabel", HORIZONTAL_ALIGNMENT_CENTER)
	var spacer := UiFx.spacer()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(UiFx.vbox(10, [title, subtitle, spacer, card, version]))

	_modal_layer = Control.new()
	_modal_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_modal_layer)


## Petit bouton du bas du menu : icône au-dessus, libellé dessous.
func _small_button(icon_name: String, text: String, action: Callable) -> Button:
	var button := _menu_button("", "Button", action)
	button.custom_minimum_size.y = 78
	var label := UiFx.label(text, "CaptionLabel", HORIZONTAL_ALIGNMENT_CENTER)
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Palette.TEXT)
	label.clip_text = true
	var icon := UiFx.image(UiFx.icon(icon_name), 26, Palette.ACCENT)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var content := UiFx.vbox(4, [icon, label])
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(content)
	return button


func _menu_button(text: String, style: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.theme_type_variation = style
	button.custom_minimum_size.y = 74
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 24)
	# Un texte trop long (traduction, petit écran) est coupé par « … » au lieu d'élargir le menu.
	button.clip_text = true
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.pressed.connect(func() -> void:
		AudioManager.play("click")
		action.call())
	return button


func _refresh() -> void:
	var slot := GameManager.most_recent_slot()
	_continue.visible = not slot.is_empty()
	if not slot.is_empty():
		# Ligne 1 : emplacement et site ; ligne 2 : sol, colons, objectifs, date.
		var parts := _summary_text(GameManager.slot_summary(slot)).split(" · ", true, 1)
		_continue_info.text = Tr.t(SLOT_NAMES[slot]) + " · " + parts[0] + ("\n" + parts[1] if parts.size() > 1 else "")


static func _objective_count(region: String) -> int:
	var planet: String = ColonyContent.REGIONS.get(region, ColonyContent.REGIONS.jezero).get("planet", "mars")
	var count := 0
	for objective in ColonyContent.objectives():
		if objective.planet == planet:
			count += 1
	return count


static func _summary_text(summary: Dictionary) -> String:
	if summary.is_empty():
		return Tr.t("Emplacement libre")
	var region: String = ColonyContent.REGIONS.get(summary.get("region", "jezero"), ColonyContent.REGIONS.jezero).name
	return Tr.t("%s · Sol %d · %d colon%s · %d/%d objectifs · %s") % [Tr.t(region), summary.sol, summary.colonists,
			"s" if summary.colonists > 1 else "", summary.objectives, _objective_count(summary.get("region", "jezero")),
			_ago(summary.last_saved_unix)]


static func _ago(unix: int) -> String:
	var seconds := SaveService.now_unix() - unix
	return Tr.t("à l'instant") if seconds < 60 else Tr.t("il y a %s") % NumberFormatter.duration(seconds)


# ---------- Actions ----------

func _on_continue() -> void:
	var slot := GameManager.most_recent_slot()
	if not slot.is_empty():
		GameManager.open_game(slot)


func _on_new_game() -> void:
	var slot := GameManager.first_free_slot()
	if slot.is_empty():
		_show_slots(true)
		return
	_choose_region(slot)


## Versions de développement : partie de test (ères 1 à 4, Cérès, Titan) dans un emplacement libre.
func _on_test_game(test_name: String) -> void:
	var slot := GameManager.first_free_slot()
	if slot.is_empty():
		_show_slots()
		return
	if GameManager.install_test_save(slot, test_name):
		GameManager.open_game(slot)


## Choix du site d'atterrissage d'une nouvelle colonie.
func _choose_region(slot: String) -> void:
	var list := UiFx.vbox(12)
	# Partagée avec les boutons, créés avant la fenêtre (voir DESIGN.md, Pièges).
	var holder: Array[Modal] = []
	for id: String in ColonyContent.REGION_ORDER:
		var region: Dictionary = ColonyContent.REGIONS[id]
		var title := UiFx.label(region.name, "HeadingLabel")
		var tagline := UiFx.paragraph(region.tagline, "SmallLabel")
		var traits := UiFx.vbox(2)
		for line: String in region.traits:
			var point := UiFx.label("• " + Tr.t(line), "SmallLabel")
			point.add_theme_color_override("font_color", Palette.ACCENT)
			traits.add_child(point)
		var go := _slot_button(Tr.t("Se poser ici"), "GoldButton", func() -> void:
			holder[0].close()
			GameManager.open_game(slot, true, id))
		list.add_child(UiFx.panel("Row", UiFx.vbox(6, [title, tagline, traits, go])))
	holder.append(Modal.open(_modal_layer, {
		"icon": "rocket", "title": Tr.t("Choisir le site d'atterrissage"), "extra": list,
		"confirm_text": Tr.t("Retour"), "confirm_style": "Button",
	}))


## Liste des emplacements. En mode « remplacer », chaque emplacement propose d'y recommencer.
func _show_slots(replacing := false) -> void:
	var list := UiFx.vbox(10)
	# Partagée avec les boutons, créés avant la fenêtre (voir DESIGN.md, Pièges).
	var holder: Array[Modal] = []
	for slot: String in GameManager.SLOTS:
		var summary := GameManager.slot_summary(slot)
		var name := UiFx.label(SLOT_NAMES[slot], "HeadingLabel")
		var info := UiFx.paragraph(_summary_text(summary), "SmallLabel")
		var actions := UiFx.hbox(8)
		if summary.is_empty():
			actions.add_child(_slot_button(Tr.t("Commencer"), "GoldButton", func() -> void:
				holder[0].close()
				_choose_region(slot)))
		else:
			if not replacing:
				actions.add_child(_slot_button(Tr.t("Charger"), "GreenButton", func() -> void:
					holder[0].close()
					GameManager.open_game(slot)))
			if replacing:
				actions.add_child(_slot_button(Tr.t("Recommencer"), "Button", func() -> void:
					_confirm_erase(slot, true, holder[0])))
			else:
				# Supprimer : une petite corbeille, à l'écart de « Charger » (avec confirmation).
				var erase := _slot_button("", "Button", func() -> void: _confirm_erase(slot, false, holder[0]))
				erase.tooltip_text = "Supprimer"
				erase.icon = UiFx.icon("trash")
				erase.expand_icon = true
				erase.add_theme_constant_override("icon_max_width", 24)
				erase.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
				erase.add_theme_color_override("icon_normal_color", Palette.TEXT_MUTED)
				erase.size_flags_horizontal = Control.SIZE_SHRINK_END
				erase.custom_minimum_size.x = 64
				actions.add_child(erase)
		var row := UiFx.panel("Row", UiFx.vbox(6, [name, info, actions]))
		list.add_child(row)
	holder.append(Modal.open(_modal_layer, {
		"icon": "tab_knowledge",
		"title": Tr.t("Choisir un emplacement à remplacer") if replacing else Tr.t("Sauvegardes"),
		"body": Tr.t("Les 3 emplacements sont occupés. Recommencer efface la colonie choisie.") if replacing else "",
		"extra": list,
		"confirm_text": Tr.t("Fermer"),
	}))


func _slot_button(text: String, style: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.theme_type_variation = style
	button.custom_minimum_size = Vector2(0, 56)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(func() -> void:
		AudioManager.play("click")
		action.call())
	return button


func _confirm_erase(slot: String, then_start: bool, list_modal: Modal) -> void:
	var summary := GameManager.slot_summary(slot)
	Modal.open(_modal_layer, {
		"icon": "warning",
		"title": (Tr.t("Recommencer « %s » ?") if then_start else Tr.t("Supprimer « %s » ?")) % Tr.t(SLOT_NAMES[slot]),
		"body": Tr.t("%s\nCette colonie sera effacée définitivement.") % _summary_text(summary),
		"confirm_text": Tr.t("Recommencer") if then_start else Tr.t("Supprimer"),
		"confirm_style": "GoldButton",
		"cancel_text": Tr.t("Annuler"),
		"on_confirm": func() -> void:
			GameManager.delete_slot(slot)
			list_modal.close()
			if then_start:
				_choose_region(slot)
			else:
				AudioManager.play("whoosh")
				_refresh()
				_show_slots.call_deferred(),
	})


func _show_settings() -> void:
	Modal.open(_modal_layer, { "icon": "gear", "title": Tr.t("Réglages"), "extra": SettingsPanel.build(), "confirm_text": Tr.t("Fermer") })


func _quit() -> void:
	GameManager.save()
	get_tree().quit()


func _show_about() -> void:
	Modal.open(_modal_layer, {
		"icon": "rocket", "title": Tr.t("À propos"),
		"body": Tr.t("Ares Colony — un tycoon de colonie martienne où la science est la règle du jeu.\n\n")
				+ Tr.t("Conception : Nicolas Faget.\n")
				+ Tr.t("Faits scientifiques : NASA (JPL, Perseverance, Phoenix, Curiosity), université de Wageningen, ")
				+ Tr.t("université d'Arizona, Station spatiale internationale. Chaque fiche de l'encyclopédie cite ses sources.\n\n")
				+ Tr.t("Moteur : Godot Engine. Modèles et sons générés par programme. Musiques : « Cradle of the Red Horizon », « The Red Horizon », « First Dome at Dawn », « Apex of Discovery ».")
				+ " " + Tr.t("Image de la Terre : NASA, Blue Marble."),
		"confirm_text": Tr.t("Fermer"),
	})
