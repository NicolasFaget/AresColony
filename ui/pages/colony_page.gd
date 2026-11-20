class_name ColonyPage
extends Page
## Onglet « Colonie » : note, objectif en cours, entretien, équipage et santé.
## Chaque bloc montre l'essentiel ; le détail (jauges de la note, équipage) se déplie au toucher.

var _objective_title: Label
var _objective_text: Label
var _objective_bar: ProgressBar
var _objective_caption: Label
var _objective_reward: Label
var _crew_title: Label
var _crew: VBoxContainer
var _crew_summary: Label
var _info: Label
var _grade: Label
var _score: Label
var _rating_bars: Array[ProgressBar] = []
var _rating_values: Array[Label] = []
var _rating_tip: Label
var _care: Button
var _challenge: PanelContainer
var _challenge_title: Label
var _challenge_text: Label
var _challenge_bar: ProgressBar

signal maintenance_requested
signal expeditions_requested

var _era: Label
var _trips: Button


func _ready() -> void:
	_era = add_subtitle("")

	list.add_child(_rating_panel())

	_objective_title = UiFx.label("", "HeadingLabel")
	_objective_text = UiFx.paragraph("", "BodyLabel")
	_objective_reward = UiFx.label("", "SmallLabel")
	_objective_reward.add_theme_color_override("font_color", Palette.MONEY)
	_objective_bar = ProgressBar.new()
	_objective_bar.show_percentage = false
	_objective_bar.custom_minimum_size.y = 12
	_objective_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_objective_caption = UiFx.label("", "CaptionLabel")
	var objective := UiFx.panel("Row", UiFx.vbox(6, [
		UiFx.hbox(8, [UiFx.image(UiFx.icon("target"), 24, Palette.ACCENT), _objective_caption]),
		_objective_title, _objective_text, _objective_bar, _objective_reward,
	]))
	objective.mouse_filter = Control.MOUSE_FILTER_PASS
	list.add_child(objective)

	_challenge_title = UiFx.label("", "HeadingLabel")
	_challenge_text = UiFx.paragraph("", "SmallLabel")
	_challenge_bar = ProgressBar.new()
	_challenge_bar.show_percentage = false
	_challenge_bar.custom_minimum_size.y = 10
	_challenge_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_challenge_bar.theme_type_variation = "MilestoneBar"
	var caption := UiFx.label("Défi facultatif", "CaptionLabel")
	caption.add_theme_color_override("font_color", Palette.MONEY)
	_challenge = UiFx.panel("Row", UiFx.vbox(4, [
		UiFx.hbox(8, [UiFx.image(UiFx.icon("check"), 24, Palette.MONEY), caption]),
		_challenge_title, _challenge_text, _challenge_bar,
	]))
	_challenge.mouse_filter = Control.MOUSE_FILTER_PASS
	list.add_child(_challenge)

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
	_crew_summary = UiFx.label("", "SmallLabel")
	_crew = UiFx.vbox(8)
	_info = UiFx.paragraph("", "SmallLabel")
	list.add_child(Foldable.new(UiFx.vbox(2, [_crew_title, _crew_summary]), UiFx.vbox(8, [_crew, _info])))
	add_bottom_padding()
	refresh()


func refresh() -> void:
	var engine := GameManager.engine
	_era.text = Tr.t(engine.era_title())
	_trips.visible = engine.state.era >= 2 or engine.planet_id() != "mars"
	if engine.state.expedition.is_empty():
		var found := engine.state.sites_done.size()
		_trips.text = (Tr.t("Expéditions en rover · %d sites découverts") % found) if found > 1 \
				else (Tr.t("Expéditions en rover · %d site découvert") % found)
	else:
		_trips.text = Tr.t("Rover en route : %s") % Tr.t(engine.site_by_id(engine.state.expedition.site).name)
	_refresh_rating()
	var objective := engine.current_objective()
	if objective == null:
		_objective_title.text = Tr.t("Mission accomplie !")
		var campaign := GameManager.campaign
		if campaign != null and campaign.is_complete():
			_objective_text.text = Tr.t("Les cinq mondes sont accomplis, de Mars à Encelade. Vos colonies continuent de tourner : à vous de les faire grandir.")
		else:
			_objective_text.text = Tr.t("Tous les objectifs de ce monde sont remplis. D'autres colonies ont encore du travail : passez de l'une à l'autre avec le bouton planète, en haut.")
		_objective_bar.value = 100.0
	else:
		_objective_title.text = Tr.t(objective.title)
		_objective_text.text = Tr.t(objective.description)
		_objective_bar.value = engine.objective_progress(objective.id) * 100.0
	_objective_reward.text = (Tr.t("Récompense : ") + _reward_text(objective.reward)) if objective != null else ""
	_objective_reward.visible = objective != null
	var total := 0
	var done := 0
	for o in engine.objectives:
		if o.era == engine.state.era:
			total += 1
			done += 1 if engine.state.objectives_done.has(o.id) else 0
	_objective_caption.text = Tr.t("Objectif · %d / %d de l'ère") % [done, total]

	var challenge := engine.current_challenge()
	_challenge.visible = not challenge.is_empty()
	if not challenge.is_empty():
		var left := maxf(0.0, float(engine.state.challenge.until) - engine.state.sol)
		_challenge_title.text = Tr.t(challenge.title)
		_challenge_text.text = Tr.t("%s Récompense : %s · encore %s sol%s.") % [Tr.t(challenge.text), _reward_text(challenge.reward),
				NumberFormatter.format(left), "s" if left >= 2.0 else ""]
		_challenge_bar.value = engine.challenge_progress() * 100.0

	_crew_title.text = Tr.t("Équipage : %d colons · %d places") % [engine.state.colonists.size(), engine.housing()]
	if engine.state.era >= 3:
		_crew_title.text += Tr.t(" · %d à l'abri") % mini(engine.shelter_capacity(), engine.state.colonists.size())
	while _crew.get_child_count() < engine.state.colonists.size():
		_crew.add_child(_colonist_line())
	while _crew.get_child_count() > engine.state.colonists.size():
		var extra := _crew.get_child(_crew.get_child_count() - 1)
		_crew.remove_child(extra)
		extra.queue_free()
	var health := 0.0
	var tired := 0
	for colonist: Dictionary in engine.state.colonists:
		health += colonist.health
		tired += 1 if colonist.health <= 0.5 else 0
	if engine.state.colonists.is_empty():
		_crew_summary.text = Tr.t("Personne à bord.")
	else:
		_crew_summary.text = Tr.t("Santé moyenne : %d %%") % roundi(health / engine.state.colonists.size() * 100.0)
		if tired > 0:
			_crew_summary.text += Tr.t(" · %d en mauvaise forme") % tired
	UiFx.font_color(_crew_summary, Palette.WARNING if tired > 0 else Palette.TEXT_MUTED)
	for i in engine.state.colonists.size():
		var colonist: Dictionary = engine.state.colonists[i]
		var line := _crew.get_child(i)
		(line.get_child(1) as Label).text = Tr.t("%s, %s") % [colonist.name, Tr.t(colonist.role)]
		var bar: ProgressBar = line.get_child(2)
		bar.value = colonist.health * 100.0
		bar.theme_type_variation = "ProgressBar" if colonist.health > 0.5 else "MilestoneBar"

	var broken := engine.broken_count()
	_care.text = Tr.t("Entretien · poussière %d %% · %s") % [roundi(engine.average_dust() * 100.0),
			Tr.t("%d panne%s") % [broken, "s" if broken > 1 else ""] if broken > 0 else Tr.t("aucune panne")]
	_care.theme_type_variation = "GoldButton" if broken > 0 or engine.average_dust() >= ColonyAdvisor.DUST_ALERT else "Button"
	var next := engine.state.next_resupply - engine.state.sol
	var housing_left := engine.housing() - engine.state.colonists.size()
	var left := engine.resupplies_left()
	var supply: String
	if left > 0:
		supply = Tr.t("Prochain ravitaillement de la Terre dans %s sol%s (%s).") % [NumberFormatter.format(next), "s" if next >= 2.0 else "",
				Tr.t("le dernier avec des matériaux") if left == 1 else Tr.t("encore %d avec des matériaux") % left]
	elif engine.planet_id() != "mars":
		supply = Tr.t("Aucun ravitaillement de la Terre si loin : fabriquez vos matériaux ou faites-les livrer par cargaison.")
	else:
		supply = Tr.t("La Terre n'envoie plus de matériaux : fabriquez-les avec le four à régolithe.")
	var crew: String
	if housing_left <= 0:
		crew = Tr.t("Aucune place libre : construisez un habitat pour accueillir des recrues.")
	elif engine.recruits_left() > 0:
		crew = Tr.t("Places libres : des recrues arriveront.")
	elif engine.campaign_colonies > 1:
		crew = Tr.t("Places libres : d'autres colons peuvent venir par cargaison.")
	else:
		crew = Tr.t("Places libres.")
	_info.text = Tr.t("%s %s\nÉvacués vers la Terre : %d.") % [supply, crew, engine.state.evacuated]


## Note d'efficacité : grande lettre, score, quatre jauges et le conseil le plus utile.
func _rating_panel() -> Control:
	_grade = UiFx.label("", "TitleLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_grade.add_theme_font_size_override("font_size", 48)
	_grade.custom_minimum_size.x = 72
	_score = UiFx.label("", "CaptionLabel", HORIZONTAL_ALIGNMENT_CENTER)
	var left := UiFx.vbox(0, [_grade, _score])
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	var bars := UiFx.vbox(4)
	for part in ["Fonctionnement", "Raccordement", Tr.t("Synergies"), Tr.t("Améliorations")]:
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
	_rating_tip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var summary := UiFx.vbox(2, [UiFx.label(Tr.t("Efficacité de la colonie"), "CaptionLabel"), _rating_tip])
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary.alignment = BoxContainer.ALIGNMENT_CENTER
	# Résumé : la note et le conseil ; les quatre jauges au toucher.
	return Foldable.new(UiFx.hbox(12, [left, summary]), bars)


func _refresh_rating() -> void:
	var rating := GameManager.engine.colony_rating()
	_grade.text = rating.grade
	UiFx.font_color(_grade, { "A": Palette.SUCCESS, "B": Palette.ACCENT, "C": Palette.MONEY,
			"D": Palette.WARNING, "E": Palette.DANGER }[rating.grade])
	_score.text = Tr.t("%d / 100") % roundi(rating.score)
	for i in rating.parts.size():
		var part: Dictionary = rating.parts[i]
		_rating_bars[i].max_value = part.max
		_rating_bars[i].value = part.value
		_rating_values[i].text = "%d/%d" % [roundi(part.value), roundi(part.max)]
	_rating_tip.text = (Tr.t("Conseil : ") + rating.tip) if not rating.tip.is_empty() else Tr.t("Colonie exemplaire, rien à redire !")


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
		parts.append(Tr.t("%s %s") % [NumberFormatter.format(reward[r]), Tr.t(ColonyContent.RESOURCE_NAMES[r]).to_lower()])
	return ", ".join(parts)
