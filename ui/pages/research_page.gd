class_name ResearchPage
extends Page
## Onglet « Recherche » : les recherches de l'ère, disponibles d'abord.

var _rows: Array[ResearchRow] = []
var _subtitle: Label


func _ready() -> void:
	_subtitle = add_subtitle()
	for r: Defs.Research in GameManager.engine.research_defs.values():
		var row := ResearchRow.new(r)
		_rows.append(row)
		list.add_child(row)
	add_bottom_padding()
	refresh()


func refresh() -> void:
	var engine := GameManager.engine
	var order := { "active": 0, "available": 1, "locked": 2, "done": 3, "excluded": 4 }
	var sorted := _rows.duplicate()
	sorted.sort_custom(func(a: ResearchRow, b: ResearchRow) -> bool:
		var sa: int = order[engine.research_state(a.research.id)]
		var sb: int = order[engine.research_state(b.research.id)]
		if sa != sb:
			return sa < sb
		if a.research.era != b.research.era:
			return a.research.era < b.research.era
		return _rows.find(a) < _rows.find(b))
	for i in sorted.size():
		list.move_child(sorted[i], i)
		sorted[i].refresh()
	_subtitle.text = Tr.t("%d / %d terminées · les colons et l'atterrisseur produisent des données.") % [
		engine.state.research_done.size(), engine.research_defs.size()]


func highlight(target: String) -> void:
	for row in _rows:
		if row.research.id == target:
			flash_row(row)


func has_available_research() -> bool:
	var engine := GameManager.engine
	if not engine.state.research_active.is_empty():
		return false
	for r: Defs.Research in engine.research_defs.values():
		if engine.research_state(r.id) == "available" and engine.state.amount(ColonyContent.DATA) >= r.cost:
			return true
	return false
