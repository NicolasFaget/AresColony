class_name ResearchRow
extends PanelContainer
## Ligne d'une recherche : nom, effet, coût en données, état (verrouillée, disponible, en cours, faite).

var research: Defs.Research

var _status: Label
var _bar: ProgressBar
var _button: Button
var _cost: Label


func _init(p_research: Defs.Research) -> void:
	research = p_research


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	var title := UiFx.label(research.name, "HeadingLabel")
	_status = UiFx.label("", "SmallLabel")
	_bar = ProgressBar.new()
	_bar.theme_type_variation = "VioletBar"
	_bar.show_percentage = false
	_bar.custom_minimum_size.y = 10
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var info := UiFx.vbox(4, [title, UiFx.paragraph(research.summary, "BodyLabel"), _status, _bar])
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_button = Button.new()
	_button.theme_type_variation = "PurpleButton"
	_button.custom_minimum_size = Vector2(150, 76)
	_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_cost = UiFx.label(NumberFormatter.format(research.cost), "NumberLabel")
	_cost.add_theme_color_override("font_color", Color("#1c0f45"))
	var content := UiFx.vbox(0, [UiFx.label("Lancer", "CaptionLabel", HORIZONTAL_ALIGNMENT_CENTER),
			UiFx.hbox(4, [UiFx.image(UiFx.icon("data"), 20, Color("#1c0f45")), _cost])])
	(content.get_child(1) as BoxContainer).alignment = BoxContainer.ALIGNMENT_CENTER
	(content.get_child(0) as Label).add_theme_color_override("font_color", Color("#1c0f45"))
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_button.add_child(content)
	UiFx.on_tap(_button, _on_start)

	add_child(UiFx.hbox(12, [info, _button]))
	refresh()


func refresh() -> void:
	var engine := GameManager.engine
	var state := engine.research_state(research.id)
	theme_type_variation = "RowLocked" if state == "locked" else "Row"
	_bar.visible = state == "active"
	_button.visible = state == "available"
	match state:
		"done":
			_status.text = "✓ Terminée"
			_status.add_theme_color_override("font_color", Palette.SUCCESS)
		"active":
			_status.text = "En cours… (%d %%)" % roundi(engine.state.research_progress * 100.0)
			_status.add_theme_color_override("font_color", Palette.FAME)
			_bar.value = engine.state.research_progress * 100.0
		"locked":
			var names: Array[String] = []
			for req: String in research.requires:
				names.append(engine.research_defs[req].name)
			_status.text = "Nécessite : %s" % ", ".join(names)
			_status.add_theme_color_override("font_color", Palette.TEXT_DIM)
		_:
			_status.text = "Durée : %s sol" % NumberFormatter.format(research.duration)
			_status.add_theme_color_override("font_color", Palette.TEXT_MUTED)
			var can := engine.state.research_active.is_empty() and engine.state.amount(ColonyContent.DATA) >= research.cost
			_button.disabled = not can


func _on_start() -> void:
	if GameManager.engine.start_research(research.id):
		AudioManager.play("click")
		GameManager.vibrate(15)
	else:
		AudioManager.play("fail")
		UiFx.shake(_button)
