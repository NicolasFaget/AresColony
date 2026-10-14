class_name KnowledgePage
extends Page
## Onglet « Savoir » : l'encyclopédie des fiches de découverte.

signal open_card(card_id: String)

var _rows: Array[CardRow] = []
var _subtitle: Label


func _ready() -> void:
	_subtitle = add_subtitle()
	for card: Defs.Card in GameManager.engine.cards.values():
		var row := CardRow.new(card)
		row.open_requested.connect(open_card.emit)
		_rows.append(row)
		list.add_child(row)
	add_bottom_padding()
	refresh()


func refresh() -> void:
	var engine := GameManager.engine
	for row in _rows:
		row.refresh()
	_subtitle.text = "%d / %d fiches découvertes · faits réels et sourcés." % [
		engine.state.cards_unlocked.size(), engine.cards.size()]
