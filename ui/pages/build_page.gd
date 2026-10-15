class_name BuildPage
extends Page
## Onglet « Construire » : les modules, débloqués d'abord.

signal place_requested(building_id: String)
signal synergies_requested

var _rows: Array[BuildRow] = []
var _hint: Label
var _synergies: Button


func _ready() -> void:
	_hint = add_subtitle("Posez les modules contre un module déjà relié à l'atterrisseur.")
	_synergies = Button.new()
	_synergies.theme_type_variation = "GoldButton"
	_synergies.custom_minimum_size = Vector2(0, 56)
	_synergies.focus_mode = Control.FOCUS_NONE
	_synergies.pressed.connect(func() -> void:
		AudioManager.play("click")
		synergies_requested.emit())
	list.add_child(_synergies)
	for def in GameManager.engine.buildable_defs():
		var row := BuildRow.new(def)
		row.place_requested.connect(place_requested.emit)
		_rows.append(row)
		list.add_child(row)
	add_bottom_padding()
	refresh()


func highlight(target: String) -> void:
	for row in _rows:
		if row.def.id == target:
			flash_row(row)


func refresh() -> void:
	var engine := GameManager.engine
	# Modules débloqués en premier, dans l'ordre du contenu.
	var index := 1
	for unlocked in [true, false]:
		for row in _rows:
			if engine.is_unlocked(row.def) == unlocked:
				list.move_child(row, index)
				index += 1
	for row in _rows:
		row.refresh()
	_synergies.text = "✦ Synergies entre voisins (%d actives)" % engine.active_synergy_count()
