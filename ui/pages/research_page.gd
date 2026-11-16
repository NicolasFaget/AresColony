class_name ResearchPage
extends Page
## Onglet « Recherche » : les recherches de l'ère, disponibles d'abord. Les ères suivantes et
## les recherches terminées sont repliées sous un titre (« Ère 2 · 6 recherches à débloquer »).

var _rows: Array[ResearchRow] = []
var _subtitle: Label
## Titres des groupes repliables (clé : "era2", "era3"…, "done") et groupes ouverts.
var _headers := {}
var _open := {}


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
	var groups := {}
	for row: ResearchRow in sorted:
		var key := _group_of(row)
		if not key.is_empty():
			groups[key] = groups.get(key, 0) + 1
	var index := 0
	var placed := {}
	for row: ResearchRow in sorted:
		var key := _group_of(row)
		if not key.is_empty() and not placed.has(key):
			placed[key] = true
			var header := _header(key)
			header.text = _header_text(key, groups[key])
			header.visible = true
			list.move_child(header, index)
			index += 1
		list.move_child(row, index)
		index += 1
		row.visible = key.is_empty() or _open.get(key, false)
		row.refresh()
	for key: String in _headers:
		if not groups.has(key):
			_headers[key].visible = false
	_subtitle.text = Tr.t("%d / %d terminées · les colons et l'atterrisseur produisent des données.") % [
		engine.state.research_done.size(), engine.research_defs.size()]


func highlight(target: String) -> void:
	for row in _rows:
		if row.research.id == target:
			var key := _group_of(row)
			if not key.is_empty() and not _open.get(key, false):
				_open[key] = true
				refresh()
			flash_row(row)


## Groupe repliable d'une ligne : une ère pas encore commencée, ou les recherches finies.
func _group_of(row: ResearchRow) -> String:
	var engine := GameManager.engine
	var state := engine.research_state(row.research.id)
	if state in ["done", "excluded"]:
		return "done"
	if state == "locked" and row.research.era > engine.research_era():
		return "era%d" % row.research.era
	return ""


func _header_text(key: String, count: int) -> String:
	_headers[key].icon = UiFx.icon("chevron_up" if _open.get(key, false) else "chevron_down")
	if key == "done":
		return Tr.t("Terminées ou écartées · %d") % count
	return Tr.t("Ère %s · %d recherche%s à débloquer") % [key.trim_prefix("era"), count, "s" if count > 1 else ""]


func _header(key: String) -> Button:
	if not _headers.has(key):
		var button := Button.new()
		button.flat = true
		button.focus_mode = Control.FOCUS_NONE
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size.y = 52
		button.add_theme_color_override("font_color", Palette.TEXT_MUTED)
		button.add_theme_font_size_override("font_size", 18)
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 20)
		button.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		button.add_theme_color_override("icon_normal_color", Palette.TEXT_MUTED)
		button.pressed.connect(func() -> void:
			AudioManager.play("click")
			_open[key] = not _open.get(key, false)
			refresh())
		list.add_child(button)
		_headers[key] = button
	return _headers[key]


func has_available_research() -> bool:
	var engine := GameManager.engine
	if not engine.state.research_active.is_empty():
		return false
	for r: Defs.Research in engine.research_defs.values():
		if engine.research_state(r.id) == "available" and engine.state.amount(ColonyContent.DATA) >= r.cost:
			return true
	return false
