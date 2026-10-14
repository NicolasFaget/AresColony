class_name BuildPage
extends Page
## Onglet « Construire » : les modules, débloqués d'abord.

signal place_requested(building_id: String)

var _rows: Array[BuildRow] = []
var _hint: Label


func _ready() -> void:
	_hint = add_subtitle("Posez les modules contre un module déjà relié à l'atterrisseur.")
	for def in GameManager.engine.buildable_defs():
		var row := BuildRow.new(def)
		row.place_requested.connect(place_requested.emit)
		_rows.append(row)
		list.add_child(row)
	add_bottom_padding()
	refresh()


func refresh() -> void:
	var engine := GameManager.engine
	# Modules débloqués en premier, dans l'ordre du contenu.
	var index := 0
	for unlocked in [true, false]:
		for row in _rows:
			if engine.is_unlocked(row.def) == unlocked:
				list.move_child(row, index)
				index += 1
	for row in _rows:
		row.refresh()
