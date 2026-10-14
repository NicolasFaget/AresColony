class_name UiFx
extends RefCounted
## Petits utilitaires d'interface : création de contrôles, animations, retour tactile.

## Calque au-dessus de tout, où vivent les textes flottants. Défini par l'écran principal.
static var fx_layer: Control

## Au-delà de ce déplacement (pixels) entre l'appui et le relâchement, c'était un défilement.
const TAP_SLOP := 14.0

static var _icons := {}


## Icône vectorielle de art/icons (générée par tools/make_icons.py).
static func icon(icon_name: String) -> Texture2D:
	if not _icons.has(icon_name):
		_icons[icon_name] = load("res://art/icons/%s.svg" % icon_name)
	return _icons[icon_name]


## Vignette 3D d'un module, rendue par l'IconStudio.
static func building_icon(building_id: String, side: Vector2) -> TextureRect:
	var node := image(IconStudio.texture(building_id), side.y)
	node.custom_minimum_size = side
	return node


static func label(text: String, variation := "", align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var node := Label.new()
	node.text = text
	node.theme_type_variation = variation
	node.horizontal_alignment = align
	node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


## Texte sur plusieurs lignes, qui s'adapte à la largeur disponible.
static func paragraph(text: String, variation := "BodyLabel", align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var node := label(text, variation, align)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return node


static func image(texture: Texture2D, side: float, tint := Color.WHITE) -> TextureRect:
	var node := TextureRect.new()
	node.texture = texture
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	node.custom_minimum_size = Vector2(side, side)
	node.modulate = tint
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


static func hbox(separation := 12, children: Array = []) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child: Control in children:
		box.add_child(child)
	return box


static func vbox(separation := 8, children: Array = []) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child: Control in children:
		box.add_child(child)
	return box


static func panel(variation: String, child: Control = null) -> PanelContainer:
	var node := PanelContainer.new()
	node.theme_type_variation = variation
	if child != null:
		node.add_child(child)
	return node


static func spacer() -> Control:
	var node := Control.new()
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


## Branche une action sur un bouton placé dans une liste défilante :
## - les gestes de défilement qui commencent sur le bouton sont transmis à la liste ;
## - un appui suivi d'un défilement n'est pas un achat ;
## - le bouton s'enfonce légèrement, puis rebondit.
static func on_tap(button: BaseButton, action: Callable) -> void:
	button.mouse_filter = Control.MOUSE_FILTER_PASS
	button.focus_mode = Control.FOCUS_NONE
	var origin := [Vector2.ZERO]
	button.button_down.connect(func() -> void:
		origin[0] = button.global_position
		press_in(button))
	button.button_up.connect(func() -> void: press_out(button))
	button.pressed.connect(func() -> void:
		if button.global_position.distance_to(origin[0]) <= TAP_SLOP:
			action.call())


static func press_in(control: Control) -> void:
	_center_pivot(control)
	var tween := control.create_tween()
	tween.tween_property(control, "scale", Vector2.ONE * 0.94, 0.08).set_trans(Tween.TRANS_QUAD)


static func press_out(control: Control) -> void:
	var tween := control.create_tween()
	tween.tween_property(control, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


## Petit rebond pour attirer l'œil (achat réussi, palier atteint).
static func pop(control: Control, strength := 0.12) -> void:
	_center_pivot(control)
	var tween := control.create_tween()
	tween.tween_property(control, "scale", Vector2.ONE * (1.0 + strength), 0.09).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(control, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


## Secousse horizontale : action impossible.
static func shake(control: Control) -> void:
	var tween := control.create_tween()
	var base := control.position
	for offset in [12.0, -10.0, 7.0, -4.0, 0.0]:
		tween.tween_property(control, "position:x", base.x + offset, 0.04)


## Texte qui monte et s'efface, centré sur `global_center`.
static func float_text(text: String, global_center: Vector2, color := Palette.MONEY, size := 28) -> void:
	if fx_layer == null or not fx_layer.is_visible_in_tree():
		return
	var node := label(text, "NumberLabel", HORIZONTAL_ALIGNMENT_CENTER)
	node.add_theme_color_override("font_color", color)
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_outline_color", Palette.OUTLINE)
	node.add_theme_constant_override("outline_size", 8)
	fx_layer.add_child(node)
	node.reset_size()
	node.global_position = global_center - node.size / 2.0
	node.pivot_offset = node.size / 2.0
	node.scale = Vector2.ONE * 0.6

	var tween := node.create_tween().set_parallel()
	tween.tween_property(node, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(node, "position:y", node.position.y - 90.0, 1.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(node, "modulate:a", 0.0, 0.45).set_delay(0.55)
	tween.chain().tween_callback(node.queue_free)


## Icônes qui volent d'un point à un autre (gains encaissés).
static func coin_burst(from: Vector2, to: Vector2, count := 10, on_arrival := Callable()) -> void:
	if fx_layer == null:
		return
	for i in count:
		var coin := image(icon("materials"), 40, Palette.resource_color("materials"))
		fx_layer.add_child(coin)
		coin.size = Vector2(44, 44)
		var spread := Vector2(randf_range(-120, 120), randf_range(-80, 80))
		coin.global_position = from - coin.size / 2.0
		var tween := coin.create_tween()
		tween.tween_property(coin, "global_position", from + spread - coin.size / 2.0, 0.35) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(coin, "global_position", to - coin.size / 2.0, 0.5) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN).set_delay(i * 0.04)
		tween.tween_callback(coin.queue_free)
		if i == count - 1 and on_arrival.is_valid():
			tween.tween_callback(on_arrival)


static func _center_pivot(control: Control) -> void:
	control.pivot_offset = control.size / 2.0
