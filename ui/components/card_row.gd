class_name CardRow
extends PanelContainer
## Ligne d'une fiche de découverte dans l'encyclopédie (masquée tant qu'elle n'est pas débloquée).

signal open_requested(card_id: String)

var card: Defs.Card

var _title: Label
var _status: Label
var _open: Button


func _init(p_card: Defs.Card) -> void:
	card = p_card


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	_title = UiFx.label("", "HeadingLabel")
	_status = UiFx.label("", "CaptionLabel")
	var info := UiFx.vbox(2, [_title, _status])
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_open = Button.new()
	_open.text = "Lire"
	_open.custom_minimum_size = Vector2(110, 60)
	_open.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UiFx.on_tap(_open, func() -> void: open_requested.emit(card.id))
	add_child(UiFx.hbox(12, [UiFx.image(UiFx.icon("tab_knowledge"), 34, Palette.FAME), info, _open]))
	refresh()


func refresh() -> void:
	var unlocked := GameManager.engine.state.cards_unlocked.has(card.id)
	theme_type_variation = "Row" if unlocked else "RowLocked"
	_open.visible = unlocked
	_title.text = card.title if unlocked else "Fiche à découvrir"
	_status.text = card.status if unlocked else "Recherchez et explorez pour la débloquer."
	_status.add_theme_color_override("font_color", Palette.STATUS_COLORS.get(card.status, Palette.TEXT_DIM) if unlocked else Palette.TEXT_DIM)
