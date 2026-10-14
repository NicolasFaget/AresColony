class_name ColonyPage
extends Page
## Onglet « Colonie » : objectif en cours, objectifs atteints, équipage et santé.

var _objective_title: Label
var _objective_text: Label
var _objective_bar: ProgressBar
var _objectives_done: Label
var _crew_title: Label
var _crew: VBoxContainer
var _info: Label


func _ready() -> void:
	add_subtitle("Ère 1 · Survie : tenir sans dépendre de la Terre.")

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
	var objective := engine.current_objective()
	if objective == null:
		_objective_title.text = "Ère « Survie » accomplie !"
		_objective_text.text = "La colonie tient seule. Les prochaines ères arrivent bientôt."
		_objective_bar.value = 100.0
	else:
		_objective_title.text = objective.title
		_objective_text.text = objective.description + "\nRécompense : " + _reward_text(objective.reward)
		_objective_bar.value = engine.objective_progress(objective.id) * 100.0
	var done: Array[String] = []
	for o in engine.objectives:
		if engine.state.objectives_done.has(o.id):
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

	var next := engine.state.next_resupply - engine.state.sol
	var housing_left := engine.housing() - engine.state.colonists.size()
	_info.text = "Prochain ravitaillement de la Terre dans %s sol%s. %s\nÉvacués vers la Terre : %d." % [
		NumberFormatter.format(next), "s" if next >= 2.0 else "",
		"Places libres : des recrues arriveront." if housing_left > 0 else "Aucune place libre : construisez un habitat pour accueillir des recrues.",
		engine.state.evacuated]


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
