class_name Modal
extends Control
## Fenêtre de dialogue à la manière des tycoons classiques : barre de titre, contenu, boutons.
##
## Options de open() :
##   icon (nom d'icône pixel), title, body, extra (Control ajouté sous le texte),
##   confirm_text, confirm_style ("Button", "GoldButton", "GreenButton", "PurpleButton"),
##   on_confirm (Callable), cancel_text ("" : pas d'annulation), cancel_style, dismissible (toucher le voile ferme).

signal closed
## Le bouton d'annulation a été touché.
signal cancelled

var _sheet: PanelContainer
var _dismissible := true
var _closing := false


static func open(host: Control, options: Dictionary) -> Modal:
	var modal := Modal.new()
	host.add_child(modal)
	modal._build(options)
	return modal


func _build(options: Dictionary) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_dismissible = options.get("dismissible", true)

	var dim := ColorRect.new()
	dim.color = Palette.DIM_OVERLAY
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(_on_dim_input)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_sheet = UiFx.panel("WindowPanel")
	_sheet.custom_minimum_size.x = minf(640.0, get_parent().size.x - 48.0)
	center.add_child(_sheet)

	var title := UiFx.label(options.get("title", ""), "TitleLabel")
	var title_row := UiFx.hbox(10)
	if options.has("icon"):
		var tint: Color = Palette.RESOURCE_COLORS.get(options.icon, Palette.ACCENT)
		title_row.add_child(UiFx.image(UiFx.icon(options.icon), 32, tint))
	title_row.add_child(title)

	var content := UiFx.vbox(14)
	if not str(options.get("body", "")).is_empty():
		content.add_child(UiFx.paragraph(options.body, "BodyLabel", HORIZONTAL_ALIGNMENT_CENTER))
	if options.has("extra"):
		content.add_child(options.extra)

	var buttons := UiFx.hbox(10)
	buttons.custom_minimum_size.y = 76
	var cancel_text: String = options.get("cancel_text", "")
	if not cancel_text.is_empty():
		buttons.add_child(_button(cancel_text, options.get("cancel_style", "Button"), cancelled.emit))
	buttons.add_child(_button(options.get("confirm_text", "OK"), options.get("confirm_style", "GreenButton"),
			options.get("on_confirm", Callable())))
	content.add_child(buttons)

	_sheet.add_child(UiFx.vbox(14, [UiFx.panel("TitleBar", title_row), content]))

	# Apparition : la fenêtre « s'ouvre » depuis le centre.
	modulate.a = 0.0
	_sheet.scale = Vector2(0.9, 0.9)
	_sheet.resized.connect(func() -> void: _sheet.pivot_offset = _sheet.size / 2.0)
	var tween := create_tween().set_parallel()
	tween.tween_property(self, "modulate:a", 1.0, 0.12)
	tween.tween_property(_sheet, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func close() -> void:
	if _closing:
		return
	_closing = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.12)
	tween.tween_callback(func() -> void:
		closed.emit()
		queue_free())


## Centre de la fenêtre, pour lancer une animation depuis la modale.
func sheet_center() -> Vector2:
	return _sheet.get_global_rect().get_center()


func _button(text: String, style: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.theme_type_variation = style
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(func() -> void:
		if _closing:
			return
		AudioManager.play("click")
		if action.is_valid():
			action.call()
		close())
	return button


func _on_dim_input(event: InputEvent) -> void:
	if _dismissible and event is InputEventMouseButton and event.pressed:
		close()
