class_name KnowledgePage
extends Page
## Onglet « Savoir » : l'encyclopédie illustrée des fiches de découverte, en galerie.

signal open_card(card_id: String)

var _rows: Array[CardRow] = []
var _subtitle: Label
var _grid: GridContainer


func _ready() -> void:
	_subtitle = add_subtitle()
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.mouse_filter = Control.MOUSE_FILTER_PASS
	list.add_child(_grid)
	for card: Defs.Card in GameManager.engine.cards.values():
		var row := CardRow.new(card)
		row.open_requested.connect(open_card.emit)
		_rows.append(row)
		_grid.add_child(row)
	add_bottom_padding()
	refresh()


func refresh() -> void:
	var engine := GameManager.engine
	# Fiches débloquées d'abord, non lues en tête.
	var index := 0
	for rank in [0, 1, 2]:
		for row in _rows:
			if _rank(row.card.id) == rank:
				_grid.move_child(row, index)
				index += 1
	for row in _rows:
		row.refresh()
	_subtitle.text = "%d / %d fiches découvertes · %d quiz réussis · faits réels et sourcés." % [
		engine.state.cards_unlocked.size(), engine.cards.size(), engine.quiz_score()]


func _rank(card_id: String) -> int:
	var state := GameManager.engine.state
	if not state.cards_unlocked.has(card_id):
		return 2
	return 1 if state.cards_read.has(card_id) else 0
