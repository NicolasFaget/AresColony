class_name ColonyPage
extends Page
## Onglet « Colonie » : note, objectif en cours, entretien, équipage et santé.

var _objective_title: Label
var _objective_text: Label
var _objective_bar: ProgressBar
var _objectives_done: Label
var _crew_title: Label
var _crew: VBoxContainer
var _info: Label
var _grade: Label
var _score: Label
var _rating_bars: Array[ProgressBar] = []
var _rating_values: Array[Label] = []
var _rating_tip: Label
var _care: Button

signal maintenance_requested
signal expeditions_requested

var _era: Label
var _trips: Button


func _ready() -> void:
	_era = add_subtitle("")

	list.add_child(_rating_panel())

	_objective_title = UiFx.label("", "HeadingLabel")
	_objective_text = UiFx.paragraph("", "BodyLabel")
	_objective_bar = ProgressBar.new()
	_objective_bar.show_percentage = false
	_objective_bar.custom_minimum_size.y = 12
	_objective_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_objectives_done = UiFx.paragraph("", "SmallLabel")
	var objective := UiFx.panel("Row", UiFx.vbox(6, [
		UiFx.hbox(8, [UiFx.image(UiFx.icon("target"), 28, Palette.ACCENT), UiFx.label("Objectif", "CaptionLabel")]),
		_objective_title, _objective_text, _objective_bar, _objectives_done,
	]))
	objective.mouse_filter = Control.MOUSE_FILTER_PASS
	list.add_child(objective)

	_care = Button.new()
	_care.custom_minimum_size = Vector2(0, 60)
	_care.focus_mode = Control.FOCUS_NONE
	_care.pressed.connect(func() -> void:
		AudioManager.play("click")
		maintenance_requested.emit())
	list.add_child(_care)
	_trips = Button.new()
	_trips.theme_type_variation = "PurpleButton"
	_trips.custom_minimum_size = Vector2(0, 60)
	_trips.focus_mode = Control.FOCUS_NONE
	_trips.pressed.connect(func() -> void:
		AudioManager.play("click")
		expeditions_requested.emit())
	list.add_child(_trips)

	_crew_title = UiFx.label("", "HeadingLabel")
	_crew = UiFx.vbox(8)
	_info = UiFx.paragraph("", "SmallLabel")
	var crew := UiFx.panel("Row", UiFx.vbox(8, [_crew_title, _crew, _info]))
	crew.mouse_filter = Control.MOUSE_FILTER_PASS
	list.add_child(crew)
	add_bottom_padding()
	refresh()


func refresh() -> void:
	var engine := GameManager.engine
	_era.text = ColonyContent.ERAS[engine.state.era]
	_trips.visible = engine.state.era >= 2
	if engine.state.expedition.is_empty():
		_trips.text = "Expéditions en rover · %d site%s découvert%s" % [engine.state.sites_done.size(),
				"s" if engine.state.sites_done.size() > 1 else "", "s" if engine.state.sites_done.size() > 1 else ""]
	else:
		_trips.text = "Rover en route : %s" % engine.site_by_id(engine.state.expedition.site).name
	_refresh_rating()
	var objective := engine.current_objective()
	if objective == null:
		_objective_title.text = "Mission accomplie !"
		_objective_text.text = "La colonie est autonome et son retour est assuré. La suite arrive dans une prochaine version."
		_objective_bar.value = 100.0
	else:
		_objective_title.text = objective.title
		_objective_text.text = objective.description + "\nRécompense : " + _reward_text(objective.reward)
		_objective_bar.value = engine.objective_progress(objective.id) * 100.0
	var done: Array[String] = []
	for o in engine.objectives:
		if o.era == engine.state.era and engine.state.objectives_done.has(o.id):
			done.append("✓ " + o.title)
	_objectives_done.text = "  ".join(done)
	_objectives_done.visible = not done.is_empty()

	_crew_title.text = "Équipage : %d colons · %d places" % [engine.state.colonists.size(), engine.housing()]
	while _crew.get_child_count() < engine.state.colonists.size():
		_crew.add_child(_colonist_line())
	while _crew.get_child_count() > engine.state.colonists.size():
		var extra := _crew.get_child(_crew.get_child_count() - 1)
		_crew.remove_child(extra)
		extra.queue_free()
	for i in engine.state.colonists.size():
		var colonist: Dictionary = engine.state.colonists[i]
		var line := _crew.get_child(i)
		(line.get_child(1) as Label).text = "%s, %s" % [colonist.name, colonist.role]
		var bar: ProgressBar = line.get_child(2)
		bar.value = colonist.health * 100.0
		bar.theme_type_variation = "ProgressBar" if colonist.health > 0.5 else "MilestoneBar"

	var broken := engine.broken_count()
	_care.text = "Entretien · poussière %d %% · %s" % [roundi(engine.average_dust() * 100.0),
			"%d panne%s" % [broken, "s" if broken > 1 else ""] if broken > 0 else "aucune panne"]
	_care.theme_type_variation = "GoldButton" if broken > 0 or engine.average_dust() >= ColonyAdvisor.DUST_ALERT else "Button"
	var next := engine.state.next_resupply - engine.state.sol
	var housing_left := engine.housing() - engine.state.colonists.size()
	var left := engine.resupplies_left()
	_info.text = "%s %s\nÉvacués vers la Terre : %d." % [
		("Prochain ravitaillement de la Terre dans %s sol%s (%s)." % [NumberFormatter.format(next), "s" if next >= 2.0 else "",
				"le dernier avec des matériaux" if left == 1 else "encore %d avec des matériaux" % left]) if left > 0
				else "La Terre n'envoie plus de matériaux : fabriquez-les avec le four à régolithe.",
		"Places libres : des recrues arriveront." if housing_left > 0 else "Aucune place libre : construisez un habitat pour accueillir des recrues.",
		engine.state.evacuated]


## Note d'efficacité : grande lettre, score, quatre jauges et le conseil le plus utile.
func _rating_panel() -> Control:
	_grade = UiFx.label("", "TitleLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_grade.add_theme_font_size_override("font_size", 64)
	_grade.custom_minimum_size.x = 84
	_score = UiFx.label("", "CaptionLabel", HORIZONTAL_ALIGNMENT_CENTER)
	var left := UiFx.vbox(0, [_grade, _score])
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	var bars := UiFx.vbox(4)
	bars.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for part in ["Fonctionnement", "Raccordement", "Synergies", "Améliorations"]:
		var name := UiFx.label(part, "SmallLabel")
		name.custom_minimum_size.x = 150
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 10)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var value := UiFx.label("", "CaptionLabel", HORIZONTAL_ALIGNMENT_RIGHT)
		value.custom_minimum_size.x = 52
		_rating_bars.append(bar)
		_rating_values.append(value)
		bars.add_child(UiFx.hbox(8, [name, bar, value]))
	_rating_tip = UiFx.paragraph("", "SmallLabel")
	_rating_tip.add_theme_color_override("font_color", Palette.ACCENT)
	var panel := UiFx.panel("Row", UiFx.vbox(8, [
		UiFx.label("Efficacité de la colonie", "CaptionLabel"),
		UiFx.hbox(12, [left, bars]), _rating_tip,
	]))
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	return panel


func _refresh_rating() -> void:
	var rating := GameManager.engine.colony_rating()
	_grade.text = rating.grade
	_grade.add_theme_color_override("font_color", { "A": Palette.SUCCESS, "B": Palette.ACCENT, "C": Palette.MONEY,
			"D": Palette.WARNING, "E": Palette.DANGER }[rating.grade])
	_score.text = "%d / 100" % roundi(rating.score)
	for i in rating.parts.size():
		var part: Dictionary = rating.parts[i]
		_rating_bars[i].max_value = part.max
		_rating_bars[i].value = part.value
		_rating_values[i].text = "%d/%d" % [roundi(part.value), roundi(part.max)]
	_rating_tip.text = ("Conseil : " + rating.tip) if not rating.tip.is_empty() else "Colonie exemplaire, rien à redire !"


func _colonist_line() -> Control:
	var name := UiFx.label("", "BodyLabel")
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(160, 10)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return UiFx.hbox(10, [UiFx.image(UiFx.icon("person"), 24, Palette.TEXT_MUTED), name, bar])


static func _reward_text(reward: Dictionary) -> String:
	var parts: Array[String] = []
	for r: String in reward:
		parts.append("%s %s" % [NumberFormatter.format(reward[r]), ColonyContent.RESOURCE_NAMES[r].to_lower()])
	return ", ".join(parts)
