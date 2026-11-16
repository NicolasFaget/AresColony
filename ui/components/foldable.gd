class_name Foldable
extends PanelContainer
## Bloc repliable : un résumé toujours visible, le détail au toucher (chevron).
## Un glissement fait défiler la liste au lieu de déplier le bloc.

signal toggled(open: bool)

const TAP_SLOP := 14.0

var header: Control
var details: Control
var opened := false

var _arrow: TextureRect
var _press_at := Vector2.ZERO
var _pressing := false


func _init(p_header: Control, p_details: Control, style := "Row") -> void:
	header = p_header
	details = p_details
	theme_type_variation = style
	mouse_filter = Control.MOUSE_FILTER_PASS
	_arrow = UiFx.image(UiFx.icon("chevron_down"), 22, Palette.TEXT_MUTED)
	_arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.visible = false
	add_child(UiFx.vbox(8, [UiFx.hbox(8, [header, _arrow]), details]))
	gui_input.connect(_on_input)


func set_open(on: bool) -> void:
	opened = on
	details.visible = on
	_arrow.texture = UiFx.icon("chevron_up" if on else "chevron_down")
	toggled.emit(on)


func _on_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press_at = event.position
			_pressing = true
		elif _pressing:
			_pressing = false
			if event.position.distance_to(_press_at) < TAP_SLOP:
				AudioManager.play("click")
				set_open(not opened)
	elif event is InputEventMouseMotion and _pressing and event.position.distance_to(_press_at) >= TAP_SLOP:
		_pressing = false
