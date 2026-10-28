extends SceneTree
## Fabrique la partie de test « ère 4 » proposée au menu des versions de développement.
## Usage : godot --headless --path . -s tools/make_test_save.gd
## Le joueur simulé joue Mars jusqu'au début de l'ère 4 ; la campagne est écrite dans
## game/test_saves/ere4.json.

const OUT := "res://game/test_saves/ere4.json"


func _initialize() -> void:
	var engine := ColonyEngine.new(ColonyState.new())
	while engine.state.era < 4 and engine.state.sol < 400.0:
		ColonyBot.play(engine, engine.state.sol + 1.0)
	var campaign := Campaign.from_engine(engine)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.get_base_dir()))
	var file := FileAccess.open(OUT, FileAccess.WRITE)
	file.store_string(JSON.stringify(campaign.to_dict(), "", true, true))
	file.close()
	print("ère %d au sol %.1f, %d colons → %s" % [engine.state.era, engine.state.sol, engine.state.colonists.size(), OUT])
	quit()
