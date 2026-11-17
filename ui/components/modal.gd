class_name Modal
extends Control
## Fenêtre de dialogue : une feuille posée en bas de l'écran (à portée de pouce), presque toute la
## largeur, avec barre de titre et croix, contenu qui défile s'il est long, puis les boutons.
## Un simple « Fermer » est discret : la couleur vive est réservée aux vraies actions.
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

	# Marges : bords de l'écran, encoche et barre de gestes du téléphone.
	var window_size := Vector2(DisplayServer.window_get_size())
	var safe := Rect2(DisplayServer.get_display_safe_area())
	var host_size: Vector2 = get_parent().size
	var top := 0.0
	var bottom := 0.0
	if OS.has_feature("mobile") and safe.size.y > 0.0 and window_size.y > 0.0:
		top = safe.position.y * host_size.y / window_size.y
		bottom = (window_size.y - safe.end.y) * host_size.y / window_size.y
	var frame := MarginContainer.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_constant_override("margin_left", 14)
	frame.add_theme_constant_override("margin_right", 14)
	frame.add_theme_constant_override("margin_top", int(top) + 14)
	frame.add_theme_constant_override("margin_bottom", int(bottom) + 14)
	add_child(frame)
	var column := UiFx.vbox(0)
	column.alignment = BoxContainer.ALIGNMENT_END
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(column)

	_sheet = UiFx.panel("WindowPanel")
	_sheet.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_sheet.custom_minimum_size.x = minf(700.0, host_size.x - 28.0)
	column.add_child(_sheet)

	var title := UiFx.label(options.get("title", ""), "TitleLabel")
	var title_row := UiFx.hbox(10)
	if options.has("icon"):
		var tint: Color = Palette.RESOURCE_COLORS.get(options.icon, Palette.ACCENT)
		title_row.add_child(UiFx.image(UiFx.icon(options.icon), 32, tint))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_row.add_child(title)
	if _dismissible:
		var cross := Button.new()
		cross.theme_type_variation = "SegmentButton"
		cross.icon = UiFx.icon("close")
		cross.expand_icon = true
		cross.add_theme_constant_override("icon_max_width", 20)
		cross.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cross.add_theme_color_override("icon_normal_color", Palette.TEXT_MUTED)
		cross.custom_minimum_size = Vector2(52, 44)
		cross.focus_mode = Control.FOCUS_NONE
		cross.pressed.connect(func() -> void:
			AudioManager.play("click")
			close())
		title_row.add_child(cross)

	var content := UiFx.vbox(14)
	if not str(options.get("body", "")).is_empty():
		content.add_child(UiFx.paragraph(options.body, "BodyLabel", HORIZONTAL_ALIGNMENT_CENTER))
	if options.has("extra"):
		content.add_child(options.extra)

	var buttons := UiFx.hbox(10)
	var cancel_text: String = options.get("cancel_text", "")
	if not cancel_text.is_empty():
		buttons.add_child(_button(cancel_text, options.get("cancel_style", "Button"), cancelled.emit))
	# Fermer sans rien faire : bouton discret. Une vraie action : bouton coloré, plus haut.
	var plain_close: bool = not options.has("on_confirm") and cancel_text.is_empty() and not options.has("confirm_style") \
			and options.get("confirm_text", "OK") == Tr.t("Fermer")
	buttons.custom_minimum_size.y = 58 if plain_close else 72
	buttons.add_child(_button(options.get("confirm_text", "OK"), options.get("confirm_style", "Button" if plain_close else "GreenButton"),
			options.get("on_confirm", Callable())))

	# Le contenu défile s'il dépasse la place disponible ; sinon la fenêtre épouse son contenu.
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(content)
	var cap := host_size.y - top - bottom - 28.0 - 190.0
	var fit := func() -> void:
		scroll.custom_minimum_size.y = minf(content.get_combined_minimum_size().y, cap)
	content.minimum_size_changed.connect(fit)
	fit.call()

	_sheet.add_child(UiFx.vbox(12, [UiFx.panel("TitleBar", title_row), scroll, buttons]))

	# Apparition : la feuille monte depuis le bas.
	modulate.a = 0.0
	frame.position.y = 60.0
	var tween := create_tween().set_parallel()
	tween.tween_property(self, "modulate:a", 1.0, 0.12)
	tween.tween_property(frame, "position:y", 0.0, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


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
