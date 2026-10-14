class_name ColonyAdvisor
extends RefCounted
## Conseiller de la colonie : prévisions des réserves vitales, alertes avec la marche à suivre,
## étapes du tutoriel guidé. Fonctions pures (lecture seule de l'engine), donc testables.

## Onglets de l'interface ciblés par les conseils.
const TAB_BUILD := 0
const TAB_COLONY := 1
const TAB_RESEARCH := 2

## En dessous de ce nombre de sols de réserve, l'alerte devient rouge ; au-dessus, orange.
const DANGER_SOLS := 1.0
const WARNING_SOLS := 2.5

## Tutoriel : identifiant, consigne, onglet et cible à montrer.
const TUTORIAL := [
	{ "id": "research_moxie", "tab": TAB_RESEARCH, "target": "moxie",
		"text": "Vos réserves d'oxygène ne tiendront que quelques sols. Lancez la recherche « Électrolyse du CO₂ »." },
	{ "id": "wait_moxie", "tab": TAB_RESEARCH, "target": "moxie",
		"text": "La recherche prend un demi-sol. Astuce : accélérez le temps avec ▶▶ en haut." },
	{ "id": "build_moxie", "tab": TAB_BUILD, "target": "moxie",
		"text": "Construisez un électrolyseur de CO₂ collé à l'atterrisseur : il fabrique l'oxygène avec l'air de Mars." },
	{ "id": "build_solar", "tab": TAB_BUILD, "target": "solar",
		"text": "L'électrolyseur consomme de l'énergie. Ajoutez des panneaux solaires, collés au réseau." },
	{ "id": "research_ice", "tab": TAB_RESEARCH, "target": "ice",
		"text": "L'eau va manquer. Recherchez « Glace souterraine » : elle révélera la glace du cratère." },
	{ "id": "build_extractor", "tab": TAB_BUILD, "target": "extractor",
		"text": "Tracez des conduites jusqu'à une plaque de glace (zones bleutées) et posez-y un extracteur." },
	{ "id": "build_greenhouse", "tab": TAB_RESEARCH, "target": "greenhouse",
		"text": "Les ravitaillements de nourriture diminuent. Recherchez puis construisez une serre." },
]


## Sols restants avant épuisement de chaque ressource vitale (INF si la réserve ne baisse pas).
static func forecast(engine: ColonyEngine) -> Dictionary:
	var flows := engine.average_flows()
	var result := {}
	for r in ColonyContent.VITAL:
		var flow: float = flows[r]
		result[r] = engine.state.amount(r) / -flow if flow < 0.0 else INF
	return result


## Alertes, de la plus urgente à la moins urgente :
## { "level": "danger" | "warning", "resource", "title", "advice", "tab", "target" }.
static func alerts(engine: ColonyEngine) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	if engine.state.colonists.is_empty():
		return list
	var days := forecast(engine)
	for r in ColonyContent.VITAL:
		var left: float = days[r]
		if left > WARNING_SOLS:
			continue
		var fix := _fix(engine, r)
		list.append({
			"level": "danger" if left <= DANGER_SOLS else "warning",
			"resource": r,
			"sols": left,
			"title": "%s : épuisé %s" % [ColonyContent.RESOURCE_NAMES[r],
					"maintenant" if left <= 0.01 else "dans %s sol%s" % [NumberFormatter.format(left), "s" if left >= 2.0 else ""]],
			"advice": fix.text, "tab": fix.tab, "target": fix.target,
		})
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.sols < b.sols)

	var isolated := 0
	for i in engine.state.buildings.size():
		if not engine.is_linked(i):
			isolated += 1
	if isolated > 0:
		list.append({ "level": "warning", "resource": "", "sols": INF,
			"title": "%d module%s isolé%s" % [isolated, "s" if isolated > 1 else "", "s" if isolated > 1 else ""],
			"advice": "Un module ne fonctionne que s'il est relié à l'atterrisseur. Posez des conduites.",
			"tab": TAB_BUILD, "target": "link" })
	return list


## Marche à suivre pour une ressource qui baisse, selon l'avancement de la colonie.
static func _fix(engine: ColonyEngine, resource: String) -> Dictionary:
	var energy_short: bool = engine.average_flows()[ColonyContent.ENERGY] < 0.0
	match resource:
		ColonyContent.OXYGEN:
			if not engine.state.research_done.has("moxie"):
				return _step("Lancez la recherche « Électrolyse du CO₂ ».", TAB_RESEARCH, "moxie")
			if energy_short:
				return _step("Vos électrolyseurs manquent d'énergie : ajoutez des panneaux solaires.", TAB_BUILD, "solar")
			return _step("Construisez un électrolyseur de CO₂ de plus.", TAB_BUILD, "moxie")
		ColonyContent.WATER:
			if not engine.state.research_done.has("ice"):
				return _step("Lancez la recherche « Glace souterraine ».", TAB_RESEARCH, "ice")
			if energy_short:
				return _step("Les extracteurs manquent d'énergie : ajoutez des panneaux solaires.", TAB_BUILD, "solar")
			return _step("Posez un extracteur sur une plaque de glace, relié par des conduites.", TAB_BUILD, "extractor")
		_:
			if not engine.state.research_done.has("greenhouse"):
				return _step("Recherchez la serre pressurisée (après la glace).", TAB_RESEARCH,
						"greenhouse" if engine.state.research_done.has("ice") else "ice")
			if not engine.state.research_done.has("perchlorate"):
				return _step("Construisez une serre, et recherchez le lavage des perchlorates (récoltes ×2).", TAB_BUILD, "greenhouse")
			return _step("Construisez une serre de plus.", TAB_BUILD, "greenhouse")


static func _step(text: String, tab: int, target: String) -> Dictionary:
	return { "text": text, "tab": tab, "target": target }


# ---------- Tutoriel ----------

## Index de la première étape non accomplie, ou -1 si le tutoriel est terminé ou passé.
static func tutorial_step(engine: ColonyEngine) -> int:
	if engine.state.tutorial_done:
		return -1
	for i in TUTORIAL.size():
		if not is_step_done(engine, TUTORIAL[i].id):
			return i
	return -1


static func is_step_done(engine: ColonyEngine, step_id: String) -> bool:
	var done := engine.state.research_done
	match step_id:
		"research_moxie":
			return done.has("moxie") or engine.state.research_active == "moxie"
		"wait_moxie":
			return done.has("moxie")
		"build_moxie":
			return _has_linked(engine, "moxie") or _has_linked(engine, "electrolyser")
		"build_solar":
			return _has_linked(engine, "solar")
		"research_ice":
			return done.has("ice") or engine.state.research_active == "ice"
		"build_extractor":
			return _has_linked(engine, "extractor")
		"build_greenhouse":
			return _has_linked(engine, "greenhouse")
	return true


static func _has_linked(engine: ColonyEngine, def_id: String) -> bool:
	for i in engine.state.buildings.size():
		if engine.state.buildings[i].id == def_id and engine.is_linked(i):
			return true
	return false
