class_name CardRow
extends PanelContainer
## Vignette d'une fiche dans l'encyclopédie : illustration, titre, statut, pastilles « Nouveau » et
## quiz. Une fiche verrouillée montre une silhouette et la façon de la débloquer.

signal open_requested(card_id: String)

const TAP_SLOP := 14.0

var card: Defs.Card

var _picture: TextureRect
var _mystery: Label
var _title: Label
var _status: Label
var _new_badge: Label
var _quiz_badge: Label
var _press_at := Vector2.ZERO
var _pressing := false


func _init(p_card: Defs.Card) -> void:
	card = p_card


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gui_input.connect(_on_input)

	_picture = UiFx.building_icon(card.visual, Vector2(150, 118))
	_picture.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_mystery = UiFx.label("?", "TitleLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_mystery.add_theme_font_size_override("font_size", 56)
	_mystery.add_theme_color_override("font_color", Palette.TEXT_DIM)
	_mystery.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mystery.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	_new_badge = _badge("NOUVEAU · +%d" % int(ColonyEngine.CARD_READ_REWARD), Palette.MONEY)
	_quiz_badge = _badge("", Palette.ACCENT)
	var badges := UiFx.hbox(4, [_new_badge, _quiz_badge])
	badges.alignment = BoxContainer.ALIGNMENT_CENTER

	_title = UiFx.paragraph("", "HeadingLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_title.add_theme_font_size_override("font_size", 18)
	_status = UiFx.paragraph("", "CaptionLabel", HORIZONTAL_ALIGNMENT_CENTER)
	var box := UiFx.vbox(4, [_picture, _title, _status, UiFx.spacer(), badges])
	add_child(box)
	_picture.add_child(_mystery)
	_ignore_mouse(box)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	refresh()


func refresh() -> void:
	var state := GameManager.engine.state
	var unlocked := state.cards_unlocked.has(card.id)
	theme_type_variation = "Row" if unlocked else "RowLocked"
	_picture.self_modulate = Color.WHITE if unlocked else Color(0.0, 0.0, 0.0, 0.45)
	_mystery.visible = not unlocked
	_title.text = card.title if unlocked else "Fiche à découvrir"
	_status.text = card.status if unlocked else _unlock_hint()
	_status.add_theme_color_override("font_color", Palette.STATUS_COLORS.get(card.status, Palette.TEXT_DIM) if unlocked else Palette.TEXT_DIM)
	_new_badge.visible = unlocked and not state.cards_read.has(card.id)
	_quiz_badge.visible = unlocked and not card.quiz.is_empty()
	if state.quiz_answers.has(card.id):
		var good: bool = state.quiz_answers[card.id]
		_quiz_badge.text = "QUIZ ✓" if good else "QUIZ ✗"
		_quiz_badge.add_theme_color_override("font_color", Palette.SUCCESS if good else Palette.TEXT_DIM)
	else:
		_quiz_badge.text = "QUIZ · +%d" % int(ColonyEngine.QUIZ_REWARD)
		_quiz_badge.add_theme_color_override("font_color", Palette.ACCENT)


func _unlock_hint() -> String:
	var engine := GameManager.engine
	for r: Defs.Research in engine.research_defs.values():
		if r.card == card.id:
			return "Recherche : " + r.name
	if card.id == "storm":
		return "Survivez à une tempête de poussière"
	return "À découvrir en jouant"


func _badge(text: String, color: Color) -> Label:
	var badge := UiFx.label(text, "CaptionLabel", HORIZONTAL_ALIGNMENT_CENTER)
	badge.add_theme_color_override("font_color", color)
	badge.add_theme_font_size_override("font_size", 13)
	return badge


func _ignore_mouse(node: Node) -> void:
	for child in node.get_children():
		if child is Control:
			(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
			_ignore_mouse(child)


## Toucher (sans glisser, pour laisser défiler la liste) ouvre la fiche si elle est débloquée.
func _on_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press_at = event.position
			_pressing = true
		elif _pressing:
			_pressing = false
			if event.position.distance_to(_press_at) < TAP_SLOP and GameManager.engine.state.cards_unlocked.has(card.id):
				AudioManager.play("click")
				UiFx.pop(self, 0.04)
				open_requested.emit(card.id)
	elif event is InputEventMouseMotion and _pressing and event.position.distance_to(_press_at) >= TAP_SLOP:
		_pressing = false
