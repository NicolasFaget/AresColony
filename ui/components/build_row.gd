class_name BuildRow
extends PanelContainer
## Ligne d'un module à construire : vignette 3D, effet par sol, coût, bouton « Placer ».

signal place_requested(building_id: String)

var def: Defs.Building

var _button: Button
var _cost: Label
var _lock: Label


func _init(p_def: Defs.Building) -> void:
	def = p_def


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	var thumb := UiFx.panel("Thumb", UiFx.building_icon(def.id, Vector2(84, 68)))
	thumb.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var title := UiFx.label(def.name, "HeadingLabel")
	var size_label := UiFx.label(Tr.t("%d×%d") % [def.size.x, def.size.y], "CaptionLabel")
	var effects := UiFx.hbox(10)
	for r: String in def.outputs:
		effects.add_child(_effect(r, def.outputs[r], true))
	for r: String in def.inputs:
		effects.add_child(_effect(r, def.inputs[r], false))
	for r: String in def.storage:
		effects.add_child(_effect(r, def.storage[r], true, Tr.t("stock ")))
	if def.housing > 0:
		effects.add_child(_effect_icon("person", Palette.TEXT, Tr.t("+%d colons") % def.housing))
	_lock = UiFx.label("", "SmallLabel")
	_lock.add_theme_color_override("font_color", Palette.WARNING)
	var info := UiFx.vbox(4, [UiFx.hbox(8, [title, size_label]), effects, _lock])
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

	add_child(UiFx.hbox(12, [thumb, info, _button]))
	refresh()


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
