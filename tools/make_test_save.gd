extends SceneTree
## Fabrique les parties de test proposées au menu des versions de développement.
## Usage : godot --headless --path . -s tools/make_test_save.gd
## - ere4.json : Mars jouée par le joueur simulé jusqu'au début de l'ère 4 ;
## - titan.json : le réseau joué jusqu'à la fondation de la colonie de Titan, affichée au chargement.

const DIR := "res://game/test_saves/"


func _initialize() -> void:
	var engine := ColonyEngine.new(ColonyState.new())
	while engine.state.era < 4 and engine.state.sol < 400.0:
		ColonyBot.play(engine, engine.state.sol + 1.0)
	_write("ere4", Campaign.from_engine(engine))

	var campaign := Campaign.from_engine(ColonyEngine.new(ColonyState.new()))
	var titan := -1
	while titan < 0 and campaign.time < 900.0:
		ColonyBot.network(campaign)
		campaign.advance(0.25)
		for i in campaign.colonies.size():
			if campaign.planet_of(i) == "titan":
				titan = i
	if titan < 0:
		push_error("Titan jamais fondée")
		quit(1)
		return
	# Quelques sols pour que le joueur simulé pose ses premiers modules.
	var until := campaign.time + 3.0
	while campaign.time < until:
		ColonyBot.network(campaign)
		campaign.advance(0.25)
	campaign.switch_to(titan)
	_write("titan", campaign)
	quit()


func _write(file_name: String, campaign: Campaign) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var file := FileAccess.open(DIR + file_name + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(campaign.to_dict(), "", true, true))
	file.close()
	var state := campaign.engine().state
	print("%s : %d colonies, colonie affichée « %s » (ère %d), sol %.1f, %d colons" % [file_name,
			campaign.colonies.size(), state.name, state.era, campaign.time, state.colonists.size()])
