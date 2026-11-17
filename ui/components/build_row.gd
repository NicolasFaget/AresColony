class_name BuildRow
extends PanelContainer
## Ligne d'un module à construire : vignette 3D, effet par sol, coût, bouton « Placer ».
## Toucher la ligne (ailleurs que sur le bouton) ouvre la fiche d'information du module.

signal place_requested(building_id: String)
signal info_requested(building_id: String)

const TAP_SLOP := 14.0

var def: Defs.Building

var _button: Button
var _cost: Label
var _lock: Label
var _press_at := Vector2.ZERO
var _pressing := false


func _init(p_def: Defs.Building) -> void:
	def = p_def


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	var thumb := UiFx.panel("Thumb", UiFx.building_icon(def.id, Vector2(84, 68)))
	thumb.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var title := UiFx.label(def.name, "HeadingLabel")
	# L'essentiel seulement : production et consommation, les colons logés ; le stockage
	# n'apparaît que pour les réservoirs (le détail complet est dans la fiche du module posé).
	var effects := UiFx.hbox(10)
	for r: String in def.outputs:
		effects.add_child(_effect(r, def.outputs[r], true))
	for r: String in def.inputs:
		effects.add_child(_effect(r, def.inputs[r], false))
	if def.housing > 0:
		effects.add_child(_effect_icon("person", Palette.TEXT, Tr.t("+%d colons") % def.housing))
	if effects.get_child_count() == 0:
		for r: String in def.storage:
			effects.add_child(_effect(r, def.storage[r], true, Tr.t("stock ")))
	_lock = UiFx.label("", "SmallLabel")
	_lock.add_theme_color_override("font_color", Palette.WARNING)
	var info := UiFx.vbox(4, [title, effects, _lock])
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_button = Button.new()
	_button.theme_type_variation = "GoldButton"
	_button.custom_minimum_size = Vector2(128, 64)
	_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_cost = UiFx.label(NumberFormatter.format(def.cost), "NumberLabel")
	var content := UiFx.vbox(0, [UiFx.label(Tr.t("Placer"), "CaptionLabel", HORIZONTAL_ALIGNMENT_CENTER),
			UiFx.hbox(4, [UiFx.image(UiFx.icon("materials"), 20, Palette.ON_MONEY), _cost])])
	(content.get_child(1) as BoxContainer).alignment = BoxContainer.ALIGNMENT_CENTER
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_button.add_child(content)
	UiFx.on_tap(_button, func() -> void: place_requested.emit(def.id))

	var row := UiFx.hbox(12, [thumb, info, _button])
	add_child(row)
	# Tout sauf le bouton laisse passer le toucher jusqu'à la ligne.
	for part: Control in [thumb, info]:
		part.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for child in part.find_children("*", "Control", true, false):
			(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gui_input.connect(_on_input)
	refresh()


## Toucher (sans glisser, pour laisser défiler la liste) ouvre la fiche du module.
func _on_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press_at = event.position
			_pressing = true
		elif _pressing:
			_pressing = false
			if event.position.distance_to(_press_at) < TAP_SLOP:
				AudioManager.play("click")
				UiFx.pop(self, 0.03)
				info_requested.emit(def.id)
	elif event is InputEventMouseMotion and _pressing and event.position.distance_to(_press_at) >= TAP_SLOP:
		_pressing = false


func refresh() -> void:
	var engine := GameManager.engine
	var unlocked := engine.is_unlocked(def)
	theme_type_variation = "Row" if unlocked else "RowLocked"
	_button.visible = unlocked
	_lock.visible = not unlocked
	if not unlocked:
		_lock.text = Tr.t("Recherche nécessaire : %s") % Tr.t(engine.research_defs[def.research].name)
		return
	var affordable := engine.state.amount(ColonyContent.MATERIALS) >= def.cost
	_button.disabled = not affordable
	_cost.add_theme_color_override("font_color", Palette.ON_MONEY if affordable else Palette.TEXT_DIM)


func _effect(resource: String, amount: float, positive: bool, prefix := "") -> Control:
	var sign := "+" if positive else "−"
	return _effect_icon(resource, Palette.resource_color(resource), "%s%s%s" % [prefix, sign, NumberFormatter.format(amount)])


func _effect_icon(icon_name: String, color: Color, text: String) -> Control:
	var label := UiFx.label(text, "CaptionLabel")
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", 16)
	return UiFx.hbox(3, [UiFx.image(UiFx.icon(icon_name), 18, color), label])
