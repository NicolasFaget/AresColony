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
## Poussière moyenne à partir de laquelle on conseille un nettoyage.
const DUST_ALERT := 0.3

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
	# Ère 2 · Expansion.
	{ "id": "research_sabatier", "era": 2, "tab": TAB_RESEARCH, "target": "sabatier",
		"text": "Place à l'expansion ! Recherchez « Réaction de Sabatier » : du méthane avec l'eau et le CO₂ martien." },
	{ "id": "build_sabatier", "era": 2, "tab": TAB_BUILD, "target": "sabatier",
		"text": "Construisez un réacteur Sabatier. Collé à un électrolyseur d'eau, il consomme moins d'eau." },
	{ "id": "research_rovers", "era": 2, "tab": TAB_RESEARCH, "target": "rovers",
		"text": "Recherchez « Rovers pressurisés » pour partir explorer les environs." },
	{ "id": "build_garage", "era": 2, "tab": TAB_BUILD, "target": "garage",
		"text": "Construisez un garage à rovers, relié à la colonie." },
	{ "id": "first_expedition", "era": 2, "tab": TAB_COLONY, "target": "expeditions",
		"text": "Lancez une première expédition (20 kg de méthane) : elle rapporte une fiche et des ressources." },
	{ "id": "research_erv", "era": 2, "tab": TAB_RESEARCH, "target": "erv",
		"text": "Recherchez « Mars Direct » : la fusée du retour se remplira de votre méthane." },
	{ "id": "build_erv", "era": 2, "tab": TAB_BUILD, "target": "erv",
		"text": "Construisez le véhicule de retour, puis réunissez 200 kg de méthane." },
	# Ère 3 · Racines.
	{ "id": "research_shielding", "era": 3, "tab": TAB_RESEARCH, "target": "shielding",
		"text": "Des éruptions solaires vont frapper la colonie. Recherchez « Blindage en régolithe »." },
	{ "id": "build_bunker", "era": 3, "tab": TAB_BUILD, "target": "bunker",
		"text": "Construisez des habitats enterrés : chacun abrite 4 colons pendant une éruption." },
	{ "id": "research_fission", "era": 3, "tab": TAB_RESEARCH, "target": "fission",
		"text": "Recherchez « Réacteur à fission » : de l'énergie même la nuit et pendant les tempêtes." },
	{ "id": "build_reactor", "era": 3, "tab": TAB_BUILD, "target": "reactor",
		"text": "Construisez un réacteur à fission : collé au four à régolithe, il lui donne sa chaleur." },
	{ "id": "research_soil", "era": 3, "tab": TAB_RESEARCH, "target": "soil",
		"text": "Recherchez « Sol vivant » pour cultiver une grande serre sur un vrai sol." },
	{ "id": "build_biodome", "era": 3, "tab": TAB_BUILD, "target": "biodome",
		"text": "Construisez une serre géante : beaucoup de nourriture pour accueillir 20 colons." },
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
			"title": Tr.t("%s : épuisé %s") % [Tr.t(ColonyContent.RESOURCE_NAMES[r]),
					Tr.t("maintenant") if left <= 0.01 else Tr.t("dans %s sol%s") % [NumberFormatter.format(left), "s" if left >= 2.0 else ""]],
			"advice": fix.text, "tab": fix.tab, "target": fix.target,
		})
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.sols < b.sols)

	var isolated := 0
	for i in engine.state.buildings.size():
		if not engine.is_linked(i):
			isolated += 1
	if isolated > 0:
		list.append({ "level": "warning", "resource": "", "sols": INF,
			"title": (Tr.t("%d modules isolés") % isolated) if isolated > 1 else Tr.t("1 module isolé"),
			"advice": Tr.t("Un module ne fonctionne que s'il est relié à l'atterrisseur. Posez des conduites."),
			"tab": TAB_BUILD, "target": "link" })

	if engine.state.era >= 3 and (engine.is_flare() or engine.flare_soon()):
		var exposed := maxi(0, engine.state.colonists.size() - engine.shelter_capacity())
		if exposed > 0:
			var researched := engine.state.research_done.has("shielding")
			list.insert(0, { "level": "danger", "resource": "", "sols": 0.0,
				"title": (Tr.t("Éruption solaire ! %d colon%s sans abri") if engine.is_flare() else Tr.t("Éruption solaire imminente : %d colon%s sans abri")) % [
						exposed, "s" if exposed > 1 else ""],
				"advice": Tr.t("Construisez des habitats enterrés : 4 places à l'abri chacun.") if researched
						else Tr.t("Recherchez « Blindage en régolithe » pour construire des abris."),
				"tab": TAB_BUILD if researched else TAB_RESEARCH, "target": "bunker" if researched else "shielding" })
	var broken := engine.broken_count()
	if broken > 0:
		list.append({ "level": "warning", "resource": "", "sols": INF,
			"title": Tr.t("%d machine%s en panne") % [broken, "s" if broken > 1 else ""],
			"advice": Tr.t("Une machine en panne ne produit plus rien : réparez-la (matériaux)."),
			"tab": TAB_COLONY, "target": "maintenance" })
	var dust := engine.average_dust()
	if dust >= DUST_ALERT:
		list.append({ "level": "warning", "resource": ColonyContent.ENERGY, "sols": INF,
			"title": Tr.t("Panneaux poussiéreux : −%d %% d'énergie") % roundi(ColonyEngine.DUST_LOSS * dust * 100.0),
			"advice": Tr.t("Envoyez une sortie de nettoyage (elle coûte de l'oxygène), ou espérez un tourbillon de poussière."),
			"tab": TAB_COLONY, "target": "maintenance" })
	var outpost := engine.state.recruits_sent >= ColonyContent.RECRUITS.size() and engine.state.resupply_count >= ColonyEngine.RESUPPLY_LIMIT 			and engine.state.amount(ColonyContent.MATERIALS) >= 60.0
	if engine.resupplies_left() <= 1 and not _has_linked(engine, "kiln") and not _has_linked(engine, "brine") and not outpost:
		var researched := engine.state.research_done.has("regolith")
		list.append({ "level": "warning", "resource": ColonyContent.MATERIALS, "sols": INF,
			"title": Tr.t("Dernier envoi de matériaux au prochain ravitaillement") if engine.resupplies_left() == 1
					else Tr.t("La Terre n'envoie plus de matériaux"),
			"advice": Tr.t("Construisez un four à régolithe pour fabriquer vos matériaux.") if researched
					else Tr.t("Recherchez « Frittage du régolithe » pour fabriquer vos propres matériaux."),
			"tab": TAB_BUILD if researched else TAB_RESEARCH, "target": "kiln" if researched else "regolith" })
	return list


## Marche à suivre pour une ressource qui baisse, selon l'avancement de la colonie.
static func _fix(engine: ColonyEngine, resource: String) -> Dictionary:
	var energy_short: bool = engine.average_flows()[ColonyContent.ENERGY] < 0.0
	match resource:
		ColonyContent.OXYGEN:
			if not engine.state.research_done.has("moxie"):
				return _step(Tr.t("Lancez la recherche « Électrolyse du CO₂ »."), TAB_RESEARCH, "moxie")
			if energy_short:
				return _step(Tr.t("Vos électrolyseurs manquent d'énergie : ajoutez des panneaux solaires."), TAB_BUILD, "solar")
			return _step(Tr.t("Construisez un électrolyseur de CO₂ de plus."), TAB_BUILD, "moxie")
		ColonyContent.WATER:
			if not engine.state.research_done.has("ice"):
				return _step(Tr.t("Lancez la recherche « Glace souterraine »."), TAB_RESEARCH, "ice")
			if energy_short:
				return _step(Tr.t("Les extracteurs manquent d'énergie : ajoutez des panneaux solaires."), TAB_BUILD, "solar")
			return _step(Tr.t("Posez un extracteur sur une plaque de glace, relié par des conduites."), TAB_BUILD, "extractor")
		_:
			if not engine.state.research_done.has("greenhouse"):
				return _step(Tr.t("Recherchez la serre pressurisée (après la glace)."), TAB_RESEARCH,
						"greenhouse" if engine.state.research_done.has("ice") else "ice")
			if not engine.state.research_done.has("perchlorate"):
				return _step(Tr.t("Construisez une serre, et recherchez le lavage des perchlorates (récoltes ×2)."), TAB_BUILD, "greenhouse")
			return _step(Tr.t("Construisez une serre de plus."), TAB_BUILD, "greenhouse")


static func _step(text: String, tab: int, target: String) -> Dictionary:
	return { "text": text, "tab": tab, "target": target }


# ---------- Tutoriel ----------

## Index de la première étape non accomplie, ou -1 si le tutoriel est terminé ou passé.
## Index (dans TUTORIAL) de la première étape non accomplie du guide de l'ère en cours,
## ou -1 si ce guide est terminé ou passé.
static func tutorial_step(engine: ColonyEngine) -> int:
	var era := engine.state.era
	if (era == 1 and engine.state.tutorial_done) or engine.state.guides_skipped.has(era):
		return -1
	for i in TUTORIAL.size():
		if TUTORIAL[i].get("era", 1) == era and not is_step_done(engine, TUTORIAL[i].id):
			return i
	return -1


## Étapes du guide d'une ère (index dans TUTORIAL).
static func era_steps(era: int) -> Array[int]:
	var list: Array[int] = []
	for i in TUTORIAL.size():
		if TUTORIAL[i].get("era", 1) == era:
			list.append(i)
	return list


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
		"first_expedition":
			return engine.state.expeditions > 0 or not engine.state.expedition.is_empty()
		"build_bunker":
			return engine.shelter_capacity() >= mini(engine.state.colonists.size(), 8)
	# Les autres étapes : « research_x » (lancée ou faite) et « build_x » (module raccordé).
	if step_id.begins_with("research_"):
		var research := step_id.trim_prefix("research_")
		return done.has(research) or engine.state.research_active == research
	if step_id.begins_with("build_"):
		return _has_linked(engine, step_id.trim_prefix("build_"))
	return true


static func _has_linked(engine: ColonyEngine, def_id: String) -> bool:
	for i in engine.state.buildings.size():
		if engine.state.buildings[i].id == def_id and engine.is_linked(i):
			return true
	return false
