class_name GameWindow
extends PanelContainer
## Panneau principal en bas de l'écran (« bottom sheet ») : poignée, onglets, contenu.
## Toucher la poignée replie le panneau pour laisser voir le monde.

signal tab_selected(index: int)
signal collapsed_changed(collapsed: bool)

const TABS := [
	["tab_build", "Construire"],
	["tab_colony", "Colonie"],
	["tab_research", "Recherche"],
	["tab_knowledge", "Savoir"],
]

var current := 0
var collapsed := false
var body: PanelContainer

var _tabs: Array[Button] = []
var _icons: Array[TextureRect] = []
var _badges: Array[Control] = []
var _handle: Control


func _ready() -> void:
	theme_type_variation = "WindowPanel"

	# Poignée : une barre arrondie, comme les panneaux des applis mobiles.
	_handle = _Handle.new()
	_handle.gui_input.connect(_on_handle_input)

	var group := ButtonGroup.new()
	var tab_row := UiFx.hbox(6)
	for i in TABS.size():
		tab_row.add_child(_build_tab(i, group))

	body = UiFx.panel("Inset")
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL

	add_child(UiFx.vbox(8, [_handle, tab_row, body]))
	select(0)


func select(index: int) -> void:
	current = index
	_tabs[index].button_pressed = true
	for i in _icons.size():
		_icons[i].modulate = Palette.ACCENT if i == index else Palette.TEXT_MUTED


func set_badge(index: int, on: bool) -> void:
	if _badges[index].visible != on:
		_badges[index].visible = on
		if on:
			UiFx.pop(_badges[index], 0.6)


func toggle_collapsed() -> void:
	collapsed = not collapsed
	body.visible = not collapsed
	_handle.queue_redraw()
	collapsed_changed.emit(collapsed)


func _on_handle_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		GameManager.vibrate(8)
		AudioManager.play("whoosh", -6.0)
		toggle_collapsed()


func _build_tab(index: int, group: ButtonGroup) -> Button:
	var button := Button.new()
	button.theme_type_variation = "TabButton"
	button.toggle_mode = true
	button.button_group = group
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, 78)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var icon := UiFx.image(UiFx.icon(TABS[index][0]), 32, Palette.TEXT_MUTED)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var label := UiFx.label(TABS[index][1], "CaptionLabel", HORIZONTAL_ALIGNMENT_CENTER)
	var content := UiFx.vbox(4, [icon, label])
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	button.add_child(content)
	# Le libellé suit la couleur du bouton (cyan quand l'onglet est actif).
	button.toggled.connect(func(on: bool) -> void:
		label.add_theme_color_override("font_color", Palette.ACCENT if on else Palette.TEXT_DIM))

	var badge := _Dot.new()
	badge.visible = false
	button.add_child(badge)
	button.resized.connect(func() -> void: badge.position = Vector2(button.size.x / 2.0 + 12.0, 8.0))

	button.button_down.connect(UiFx.press_in.bind(icon))
	button.button_up.connect(UiFx.press_out.bind(icon))
	button.pressed.connect(func() -> void:
		GameManager.vibrate(8)
		AudioManager.play("tab")
		select(index)
		if collapsed:
			toggle_collapsed()
		tab_selected.emit(index))
	_tabs.append(button)
	_icons.append(icon)
	_badges.append(badge)
	return button


## Poignée du panneau, avec une flèche discrète quand il est replié.
class _Handle extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(0, 22)
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func _draw() -> void:
		var bar := Rect2(size.x / 2.0 - 32.0, size.y / 2.0 - 3.0, 64.0, 6.0)
		draw_rect(bar, Color(1, 1, 1, 0.28))
		draw_circle(bar.position + Vector2(0, 3), 3.0, Color(1, 1, 1, 0.28))
		draw_circle(bar.end - Vector2(0, 3), 3.0, Color(1, 1, 1, 0.28))


## Pastille de notification.
class _Dot extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(16, 16)
		size = custom_minimum_size
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_circle(size / 2.0, 8.0, Color(0.03, 0.09, 0.15), true, -1.0, true)
		draw_circle(size / 2.0, 6.0, Palette.DANGER, true, -1.0, true)
