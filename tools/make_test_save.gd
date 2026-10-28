extends SceneTree
## Fabrique les parties de test proposées au menu des versions de développement.
## Usage : godot --headless --path . -s tools/make_test_save.gd
## - ere1.json : Mars au milieu de l'ère 1 (sol ERA1_SOL), premiers modules posés ;
## - ere2.json à ere4.json : Mars jouée par le joueur simulé jusqu'au début de cette ère ;
## - ceres.json, titan.json : le réseau joué jusqu'à la fondation de cette colonie (plus quelques
##   sols pour ses premiers modules), affichée au chargement.

const DIR := "res://game/test_saves/"
## Sols joués après la fondation, le temps que le joueur simulé pose les premiers modules.
const SETTLE_SOLS := 3.0
## La partie « ère 1 » : à mi-chemin de l'ère 2 (vers le sol 51 avec le joueur simulé).
const ERA1_SOL := 25.0


func _initialize() -> void:
	var engine := ColonyEngine.new(ColonyState.new())
	ColonyBot.play(engine, ERA1_SOL)
	_write("ere1", Campaign.from_engine(engine).to_dict())
	for era in [2, 3, 4]:
		while engine.state.era < era and engine.state.sol < 400.0:
			ColonyBot.play(engine, engine.state.sol + 1.0)
		_write("ere%d" % era, Campaign.from_engine(engine).to_dict())

	var campaign := Campaign.from_engine(ColonyEngine.new(ColonyState.new()))
	var pending := ["ceres", "titan"]
	## Planète -> sol où écrire sa partie.
	var founded := {}
	while not pending.is_empty() and campaign.time < 900.0:
		ColonyBot.network(campaign)
		campaign.advance(0.25)
		for i in campaign.colonies.size():
			var planet := campaign.planet_of(i)
			if planet in pending and not founded.has(planet):
				founded[planet] = campaign.time + SETTLE_SOLS
			if planet in pending and campaign.time >= founded.get(planet, INF):
				var data := campaign.to_dict()
				data.active = i
				_write(planet, data)
				pending.erase(planet)
	if not pending.is_empty():
		push_error("Jamais fondée(s) : %s" % [pending])
		quit(1)
		return
	quit()


func _write(file_name: String, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var file := FileAccess.open(DIR + file_name + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "", true, true))
	file.close()
	var campaign := Campaign.from_dict(data)
	var state := campaign.engine().state
	print("%s : %d colonies, colonie affichée « %s » (ère %d), sol %.1f, %d colons" % [file_name,
			campaign.colonies.size(), state.name, state.era, campaign.time, state.colonists.size()])
