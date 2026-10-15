extends Control
## Menu principal : une colonie de démonstration en 3D en fond, le titre, et les actions
## (continuer, nouvelle colonie, sauvegardes, réglages, à propos).

const SLOT_NAMES := { "save": "Colonie 1", "save2": "Colonie 2", "save3": "Colonie 3" }

var _world: ColonyWorld
var _modal_layer: Control
var _continue: Button
var _continue_info: Label


func _ready() -> void:
	theme = AppTheme.build()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if OS.has_feature("mobile"):
		get_viewport().scaling_3d_scale = 0.55
	_build_background()
	_build_layout()
	AudioManager.set_mood("day")
	AudioManager.set_wind(0.0)
	_refresh()


func _process(delta: float) -> void:
	# Lent travelling autour de la colonie.
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

	_continue = _menu_button(Tr.t("Continuer"), "GreenButton", _on_continue)
	_continue_info = UiFx.label("", "CaptionLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_continue_info.add_theme_color_override("font_color", Palette.ON_ACCENT)
	_continue_info.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_continue_info.offset_top = -30
	_continue_info.offset_bottom = -8
	_continue.add_child(_continue_info)

	var buttons := UiFx.vbox(12, [
		_continue,
		_menu_button(Tr.t("Nouvelle colonie"), "GoldButton", _on_new_game),
		_menu_button(Tr.t("Sauvegardes"), "Button", _show_slots),
		UiFx.hbox(12, [_menu_button(Tr.t("Réglages"), "Button", _show_settings), _menu_button(Tr.t("À propos"), "Button", _show_about)]),
	])
	for row in buttons.get_children():
		if row is HBoxContainer:
			for b in row.get_children():
				b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var card := UiFx.panel("WindowPanel", buttons)

	var version := UiFx.label(Tr.t("v%s · Mars") % ProjectSettings.get_setting("application/config/version", "0.1"),
			"CaptionLabel", HORIZONTAL_ALIGNMENT_CENTER)
	var spacer := UiFx.spacer()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(UiFx.vbox(10, [title, subtitle, spacer, card, version]))

	_modal_layer = Control.new()
	_modal_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_modal_layer)


func _menu_button(text: String, style: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.theme_type_variation = style
	button.custom_minimum_size.y = 74
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 24)
	button.pressed.connect(func() -> void:
		AudioManager.play("click")
		action.call())
	return button


func _refresh() -> void:
	var slot := GameManager.most_recent_slot()
	_continue.visible = not slot.is_empty()
	if not slot.is_empty():
		_continue.custom_minimum_size.y = 96
		_continue.add_theme_constant_override("content_margin_bottom", 26)
		_continue_info.text = Tr.t("%s · %s") % [Tr.t(SLOT_NAMES[slot]), _summary_text(GameManager.slot_summary(slot))]


static func _summary_text(summary: Dictionary) -> String:
	if summary.is_empty():
		return Tr.t("Emplacement libre")
	var region: String = ColonyContent.REGIONS.get(summary.get("region", "jezero"), ColonyContent.REGIONS.jezero).name
	return Tr.t("%s · Sol %d · %d colon%s · %d/%d objectifs · %s") % [Tr.t(region), summary.sol, summary.colonists,
			"s" if summary.colonists > 1 else "", summary.objectives, ColonyContent.objectives().size(),
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


## Choix du site d'atterrissage d'une nouvelle colonie.
func _choose_region(slot: String) -> void:
	var list := UiFx.vbox(12)
	var modal: Modal
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
			modal.close()
			GameManager.open_game(slot, true, id))
		list.add_child(UiFx.panel("Row", UiFx.vbox(6, [title, tagline, traits, go])))
	modal = Modal.open(_modal_layer, {
		"icon": "rocket", "title": Tr.t("Choisir le site d'atterrissage"), "extra": list,
		"confirm_text": Tr.t("Retour"), "confirm_style": "Button",
	})


## Liste des emplacements. En mode « remplacer », chaque emplacement propose d'y recommencer.
func _show_slots(replacing := false) -> void:
	var list := UiFx.vbox(10)
	var modal: Modal
	for slot: String in GameManager.SLOTS:
		var summary := GameManager.slot_summary(slot)
		var name := UiFx.label(SLOT_NAMES[slot], "HeadingLabel")
		var info := UiFx.paragraph(_summary_text(summary), "SmallLabel")
		var actions := UiFx.hbox(8)
		if summary.is_empty():
			actions.add_child(_slot_button(Tr.t("Commencer"), "GoldButton", func() -> void:
				modal.close()
				_choose_region(slot)))
		else:
			if not replacing:
				actions.add_child(_slot_button(Tr.t("Charger"), "GreenButton", func() -> void:
					modal.close()
					GameManager.open_game(slot)))
			actions.add_child(_slot_button(Tr.t("Recommencer") if replacing else Tr.t("Supprimer"), "Button", func() -> void:
				_confirm_erase(slot, replacing, modal)))
		var row := UiFx.panel("Row", UiFx.vbox(6, [name, info, actions]))
		list.add_child(row)
	modal = Modal.open(_modal_layer, {
		"icon": "tab_knowledge",
		"title": Tr.t("Choisir un emplacement à remplacer") if replacing else Tr.t("Sauvegardes"),
		"body": Tr.t("Les 3 emplacements sont occupés. Recommencer efface la colonie choisie.") if replacing else "",
		"extra": list,
		"confirm_text": Tr.t("Fermer"),
	})


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


func _show_about() -> void:
	Modal.open(_modal_layer, {
		"icon": "rocket", "title": Tr.t("À propos"),
		"body": Tr.t("Ares Colony — un tycoon de colonie martienne où la science est la règle du jeu.\n\n")
				+ Tr.t("Conception : Nicolas Faget.\n")
				+ Tr.t("Faits scientifiques : NASA (JPL, Perseverance, Phoenix, Curiosity), université de Wageningen, ")
				+ Tr.t("université d'Arizona, Station spatiale internationale. Chaque fiche de l'encyclopédie cite ses sources.\n\n")
				+ Tr.t("Moteur : Godot Engine. Modèles, sons et musique générés par programme."),
		"confirm_text": Tr.t("Fermer"),
	})
