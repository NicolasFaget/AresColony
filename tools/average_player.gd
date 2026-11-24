extends SceneTree
## Étude d'équilibrage : des joueurs fictifs jouent la campagne comme sur un téléphone, par séances
## de quelques minutes, avec des absences entre deux (pilote automatique hors ligne).
## Trois profils : « expert » (le joueur simulé, sans erreur), « moyen » et « occasionnel ».
## Usage : godot --headless --path . -s tools/average_player.gd [-- --players=6 --days=45 --profile=moyen]
## Le rapport s'affiche et s'écrit dans build/average_player.txt (average_player_<profil>.txt avec --profile).

const R = preload("res://core/colony_content.gd")

## Un coup d'œil du joueur : au plus une action de chaque sorte, toutes les LOOK_SECONDS secondes.
const LOOK_SECONDS := 8.0
const MILESTONES := ["first_breath", "water", "autonomy", "ère 2", "ère 3", "ère 4", "ceres", "titan", "capital", "europa", "enceladus", "fin"]

## sessions : heures des séances dans la journée ; minutes : durée moyenne d'une séance ;
## skill : chance de faire le bon choix de construction à chaque coup d'œil ; mistake : chance d'un achat
## impulsif à la place (0,015 : un par séance environ) ; distraction : chance de ne rien faire ; quiz : chance de bonne réponse ;
## skip_day : chance de ne pas jouer du tout un jour donné.
const PROFILES := {
	"expert": { "sessions": [8.0, 13.0, 21.0], "minutes": 7.0, "skill": 1.0, "mistake": 0.0, "distraction": 0.0, "quiz": 0.9,
			"skip_day": 0.0, "speeds": [2, 4, 4] },
	"moyen": { "sessions": [8.0, 13.0, 21.0], "minutes": 7.0, "skill": 0.75, "mistake": 0.015, "distraction": 0.25, "quiz": 0.65,
			"skip_day": 0.0, "speeds": [1, 2, 2, 4] },
	"occasionnel": { "sessions": [20.0], "minutes": 6.0, "skill": 0.6, "mistake": 0.03, "distraction": 0.35, "quiz": 0.5,
			"skip_day": 0.2, "speeds": [1, 1, 2] },
}

var _lines: Array[String] = []


func _initialize() -> void:
	var players := 6
	var days := 45
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--players="):
			players = int(arg.trim_prefix("--players="))
		elif arg.begins_with("--days="):
			days = int(arg.trim_prefix("--days="))
		elif arg.begins_with("--profile="):
			only = arg.trim_prefix("--profile=")
	for profile: String in PROFILES:
		if not only.is_empty() and only != profile:
			continue
		var count := players if profile == "moyen" else maxi(2, players / 2)
		var runs := []
		for k in count:
			var started := Time.get_ticks_msec()
			var run := _play(profile, 100 + k * 37, days)
			runs.append(run)
			print("  %s n°%d : %s (%.0f s de calcul)" % [profile, k + 1,
					"terminé au jour %.1f" % run.milestones["fin"].day if run.milestones.has("fin") else "non terminé", (Time.get_ticks_msec() - started) / 1000.0])
		_report(profile, runs, days)
	var file := FileAccess.open("res://build/average_player%s.txt" % ("" if only.is_empty() else "_" + only), FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(_lines) + "\n")
	quit(0)


## Joue une campagne entière ; retourne les mesures.
func _play(profile_id: String, seed_value: int, max_days: int) -> Dictionary:
	var profile: Dictionary = PROFILES[profile_id]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var state := ColonyState.new()
	state.event_seed = seed_value
	var campaign := Campaign.from_engine(ColonyEngine.new(state))
	var run := { "milestones": {}, "evacuations": [], "standby": 0, "returns": 0, "looks": 0, "idle": 0, "blocked": 0,
			"play_seconds": 0.0, "sessions": 0, "days": 0.0, "quiz_right": 0, "quiz_total": 0, "dilemmas_missed": 0, "dilemmas": 0,
			"full": {}, "worst_health": 1.0 }
	# Horloge réelle, en secondes depuis l'installation.
	var clock := [0.0]
	var mark := func(id: String) -> void:
		if not run.milestones.has(id):
			run.milestones[id] = { "day": clock[0] / 86400.0, "minutes": run.play_seconds / 60.0, "sol": campaign.time, "sessions": run.sessions }
	var watch := func(colony: ColonyEngine) -> void:
		colony.objective_completed.connect(func(id: String) -> void: mark.call(id))
		colony.era_started.connect(func(era: int) -> void:
			if colony.planet_id() == "mars":
				mark.call("ère %d" % era))
		colony.colonist_evacuated.connect(func(_n: String, cause: String) -> void:
			var counts := {}
			for building in colony.state.buildings:
				counts[building.id] = counts.get(building.id, 0) + 1
			var flows := colony.average_flows()
			run.evacuations.append({ "day": clock[0] / 86400.0, "world": colony.planet_id(), "cause": cause,
					"detail": "sol %.1f, vitesse ×%d, séance %d, matériaux %.0f, énergie %+.0f, eau %+.1f, O₂ %+.1f, %s" % [colony.state.sol, colony.state.speed,
					run.sessions, colony.state.amount(R.MATERIALS), flows[R.ENERGY], flows[R.WATER], flows[R.OXYGEN], counts] }))
		colony.dilemma_resolved.connect(func(report: Dictionary) -> void:
			run.dilemmas += 1
			if report.auto:
				run.dilemmas_missed += 1)
	watch.call(campaign.engines[0])
	campaign.colony_founded.connect(func(index: int) -> void: watch.call(campaign.engines[index]))
	campaign.completed.connect(func() -> void: mark.call("fin"))

	var first := true
	for day in max_days:
		if run.milestones.has("fin"):
			break
		if day > 0 and rng.randf() < profile.skip_day:
			continue
		for hour: float in profile.sessions:
			var start: float = day * 86400.0 + (hour + rng.randf_range(-1.0, 1.0)) * 3600.0
			# Retour après une absence : le pilote automatique a tenu la colonie (8 h au plus).
			if not first and start > clock[0]:
				var report := campaign.apply_offline_seconds(start - clock[0])
				run.returns += 1
				if not str(report.get("standby", "")).is_empty():
					run.standby += 1
				for r: String in report.get("full", []):
					run.full[r] = run.full.get(r, 0) + 1
			clock[0] = maxf(clock[0], start)
			# La toute première séance est plus longue : on découvre le jeu, à vitesse normale.
			var minutes: float = 15.0 if first else profile.minutes * rng.randf_range(0.6, 1.4)
			var speed: int = 1 if first else profile.speeds[rng.randi() % profile.speeds.size()]
			first = false
			_session(campaign, profile, rng, run, clock, minutes * 60.0, speed)
			if run.milestones.has("fin"):
				break
	run.days = clock[0] / 86400.0
	run.colonists = 0
	run.rating = 0.0
	for colony in campaign.engines:
		run.colonists += colony.state.colonists.size()
		run.rating += float(colony.colony_rating().get("score", 0.0)) / campaign.engines.size()
	run.sol = campaign.time
	run.colonies = campaign.engines.size()
	run.era = campaign.engines[0].state.era
	# Partie non terminée : ce qui manque, colonie par colonie.
	run.missing = []
	if not run.milestones.has("fin"):
		for i in campaign.engines.size():
			var colony := campaign.engines[i]
			var left := []
			for objective in colony.objectives:
				if not colony.state.objectives_done.has(objective.id):
					left.append(objective.id)
			var flows := colony.average_flows()
			run.missing.append("%s : manque %s · %d colons · santé %.2f · matériaux %.0f/%.0f · méthane %.0f/%.0f · énergie %+.0f · eau %+.0f · O₂ %+.0f · vivres %+.0f · veille %s" % [
					colony.planet_id(), left, colony.state.colonists.size(), colony.average_health(), colony.state.amount(R.MATERIALS), colony.capacity(R.MATERIALS),
					colony.state.amount(R.METHANE), colony.capacity(R.METHANE), flows[R.ENERGY], flows[R.WATER], flows[R.OXYGEN], flows[R.FOOD], campaign.standby.get(i, "non")])
		for region in ["ceres", "titan", "europa", "enceladus"]:
			var found := false
			for i in campaign.engines.size():
				found = found or campaign.planet_of(i) == region
			if not found:
				run.missing.append("%s : pas fondée (%s)" % [region, campaign.founding_problem(0, region)])
	for colony in campaign.engines:
		for sig in colony.get_signal_list():
			for connection in colony.get_signal_connection_list(sig.name):
				if connection.callable.get_object() == self:
					colony.disconnect(sig.name, connection.callable)
	return run


## Une séance : le joueur regarde ses colonies l'une après l'autre et agit à chaque coup d'œil.
func _session(campaign: Campaign, profile: Dictionary, rng: RandomNumberGenerator, run: Dictionary, clock: Array, seconds: float, speed: int) -> void:
	run.sessions += 1
	var looks := int(seconds / LOOK_SECONDS)
	# Chaque colonie reçoit une part égale de la séance ; les fusées partent une fois par séance.
	var per_colony := maxi(1, looks / campaign.engines.size())
	var shipped := false
	for look in looks:
		var index := mini(look / per_colony, campaign.engines.size() - 1)
		if index != campaign.active:
			campaign.switch_to(index)
		var colony := campaign.engine()
		colony.state.speed = speed
		run.looks += 1
		run.worst_health = minf(run.worst_health, colony.average_health())
		if rng.randf() >= profile.distraction:
			var before := _fingerprint(colony)
			var wanted := _act(colony, profile, rng, run)
			if not shipped and look >= looks / 2 and rng.randf() < profile.skill:
				ColonyBot.logistics(campaign)
				shipped = true
			if _fingerprint(colony) == before:
				run.idle += 1
				if wanted:
					run.blocked += 1
		campaign.advance(LOOK_SECONDS * speed / ColonyEngine.SECONDS_PER_SOL)
		clock[0] += LOOK_SECONDS
		run.play_seconds += LOOK_SECONDS
		if campaign.is_complete():
			return


## Ce que le joueur fait en un coup d'œil. Retourne vrai s'il voulait construire sans le pouvoir
## (matériaux manquants) : c'est de l'attente subie.
func _act(colony: ColonyEngine, profile: Dictionary, rng: RandomNumberGenerator, run: Dictionary) -> bool:
	# Une décision en attente : il répond le plus souvent, parfois au hasard.
	if not colony.pending_dilemma().is_empty() and rng.randf() < 0.5:
		var choice := colony.default_choice() if rng.randf() < profile.skill else rng.randi() % 2
		if colony.dilemma_problem(choice).is_empty():
			colony.resolve_dilemma(choice)
	# Fiches : une lecture de temps en temps, et le quiz dans la foulée.
	if colony.unread_cards() > 0 and rng.randf() < 0.3:
		for id: String in colony.state.cards_unlocked:
			if not colony.state.cards_read.has(id):
				colony.read_card(id)
				var card: Defs.Card = colony.cards[id]
				if not card.quiz.is_empty() and not colony.state.quiz_answers.has(id):
					var right: bool = rng.randf() < profile.quiz
					colony.answer_quiz(id, card.answer if right else (card.answer + 1) % maxi(2, card.choices.size()))
					run.quiz_total += 1
					run.quiz_right += int(right)
				break
	# Recherche : l'ordre conseillé, ou la première venue.
	if colony.state.research_active.is_empty():
		# Les objectifs guident : il suit le plus souvent l'ordre conseillé.
		if rng.randf() < (1.0 + profile.skill) / 2.0:
			ColonyBot.research(colony)
		else:
			var open := []
			for id: String in colony.research_defs:
				if colony.research_state(id) == "available":
					open.append(id)
			if not open.is_empty():
				colony.start_research(open[rng.randi() % open.size()])
	# Entretien : il ne voit pas toujours la panne, et nettoie tard.
	for i in colony.state.buildings.size():
		if colony.is_broken(i) and rng.randf() < 0.3 + 0.7 * profile.skill:
			colony.repair(i)
	if colony.average_dust() > lerpf(0.55, 0.3, profile.skill) and rng.randf() < 0.5:
		colony.clean_panels()
	if colony.state.amount(R.METHANE) >= 30.0 and colony.state.expeditions < 4 and rng.randf() < profile.skill:
		colony.start_expedition()
	# Construction.
	var roll := rng.randf()
	if roll < profile.mistake:
		_impulse(colony, rng)
		return false
	if roll > profile.mistake + profile.skill:
		return false
	var materials := colony.state.amount(R.MATERIALS)
	var count := colony.state.buildings.size()
	ColonyBot.build(colony)
	# Rien de posé alors que les réserves sont basses : il attend des matériaux.
	return colony.state.buildings.size() == count and is_equal_approx(materials, colony.state.amount(R.MATERIALS)) \
			and materials < 120.0


## Achat impulsif : un module débloqué et payable, pris au hasard.
func _impulse(colony: ColonyEngine, rng: RandomNumberGenerator) -> void:
	var options := []
	for id: String in colony.building_defs:
		var def: Defs.Building = colony.building_defs[id]
		if def.fixed or id == "link" or not colony.is_unlocked(def) or def.cost > colony.state.amount(R.MATERIALS):
			continue
		options.append(id)
	if options.is_empty():
		return
	var pick: String = options[rng.randi() % options.size()]
	var spot := ColonyBot.connected_spot(colony, pick)
	if spot.x >= 0:
		colony.place(pick, spot)


## Ce qui change quand le joueur a fait quelque chose d'utile.
func _fingerprint(colony: ColonyEngine) -> Array:
	var levels := 0
	var broken := 0
	for i in colony.state.buildings.size():
		levels += int(colony.state.buildings[i].get("level", 1))
		broken += int(colony.is_broken(i))
	return [colony.state.buildings.size(), levels, broken, colony.state.research_active, colony.state.cards_read.size(),
			colony.state.quiz_answers.size(), colony.state.expeditions, colony.state.last_dilemma, colony.state.dilemma.is_empty()]


# ---------- Rapport ----------

func _say(line: String) -> void:
	print(line)
	_lines.append(line)


func _median(values: Array) -> float:
	if values.is_empty():
		return NAN
	values.sort()
	return values[values.size() / 2]


func _report(profile_id: String, runs: Array, days: int) -> void:
	var profile: Dictionary = PROFILES[profile_id]
	_say("\n=== Profil « %s » : %d joueurs, %d séances par jour de %.0f min, %d jours au plus ===" % [
			profile_id, runs.size(), profile.sessions.size(), profile.minutes, days])
	_say("%-13s %8s %10s %10s %9s %8s" % ["étape", "atteinte", "jour (méd.)", "jour (max)", "min de jeu", "sol"])
	for id: String in MILESTONES:
		var day := []
		var minutes := []
		var sols := []
		for run: Dictionary in runs:
			if run.milestones.has(id):
				day.append(run.milestones[id].day)
				minutes.append(run.milestones[id].minutes)
				sols.append(run.milestones[id].sol)
		if day.is_empty():
			_say("%-13s %8s" % [id, "0/%d" % runs.size()])
		else:
			_say("%-13s %8s %10.1f %10.1f %9.0f %8.0f" % [id, "%d/%d" % [day.size(), runs.size()], _median(day), day.max(), _median(minutes), _median(sols)])
	var evacuations := 0
	var causes := {}
	var standby := 0
	var returns := 0
	var looks := 0
	var idle := 0
	var blocked := 0
	var missed := 0
	var dilemmas := 0
	var full := {}
	var ratings := []
	var health := []
	for run: Dictionary in runs:
		evacuations += run.evacuations.size()
		for e: Dictionary in run.evacuations:
			var key := "%s, %s, jour %d" % [e.world, e.cause.left(24), int(e.day) + 1]
			causes[key] = causes.get(key, 0) + 1
		standby += run.standby
		returns += run.returns
		looks += run.looks
		idle += run.idle
		blocked += run.blocked
		missed += run.dilemmas_missed
		dilemmas += run.dilemmas
		ratings.append(run.rating)
		health.append(run.worst_health)
		for r: String in run.full:
			full[r] = full.get(r, 0) + run.full[r]
	for k in runs.size():
		for line: String in runs[k].missing:
			_say("  joueur %d, non terminé : %s" % [k + 1, line])
	for k in runs.size():
		for e: Dictionary in runs[k].evacuations:
			_say("  joueur %d, colon perdu (%s, %s) : %s" % [k + 1, e.world, e.cause.left(18), e.detail])
	_say("Colons perdus : %d en tout (%.1f par joueur)" % [evacuations, float(evacuations) / runs.size()])
	for key: String in causes:
		_say("    %d × %s" % [causes[key], key])
	_say("Retours avec la colonie en veille (réserve vitale vide) : %d sur %d (%.0f %%)" % [standby, returns, 100.0 * standby / maxi(1, returns)])
	_say("Retours avec une réserve pleine (production perdue) : %s" % [full])
	_say("Coups d'œil sans rien à faire : %.0f %% · dont attente de matériaux : %.0f %%" % [100.0 * idle / maxi(1, looks), 100.0 * blocked / maxi(1, looks)])
	_say("Décisions laissées sans réponse : %d sur %d" % [missed, dilemmas])
	_say("Note moyenne des colonies à la fin : %.0f · santé la plus basse vue (médiane) : %.2f" % [_median(ratings), _median(health)])
