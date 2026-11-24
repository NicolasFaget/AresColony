class_name Story
extends RefCounted
## Le fil du récit : une Terre à bout de souffle finance une dernière mission, et Claire, directrice
## de vol, écrit aux moments clés. Chaque message est dû quand l'état de la campagne le dit (et non
## sur un signal) : il survit ainsi aux absences, aux sauvegardes et aux colonies en arrière-plan.
## Les messages déjà montrés sont dans Campaign.story_seen.

const R = preload("res://core/colony_content.gd")

## Identifiant de l'introduction dans Campaign.story_seen.
const INTRO_ID := "intro"
## Introduction : une phrase par plan (la Terre, le décollage, le voyage, l'arrivée).
const INTRO := [
	"Années 2040. La Terre fatigue : trop chaude, trop pleine, et chaque année un peu plus à court.",
	"Les budgets de l'espace ferment un à un. Il reste de quoi financer une mission. Une seule.",
	"Sept mois de route. Quatre volontaires : Ada, Malik, Inès et Tom. Et vous, pour les commander.",
	"Votre mission : prouver qu'on peut vivre ailleurs. Si vous y arrivez, d'autres suivront.",
]

## Messages de Claire, du premier au dernier : { "id", "text" }. Les conditions sont dans `_is_due`.
const MESSAGES := [
	{ "id": "oxygen", "text": "Ici Claire, contrôle de mission. Vous respirez un air fabriqué sur Mars. Ici, beaucoup n'y croyaient pas." },
	{ "id": "water", "text": "De l'eau martienne. J'ai montré vos chiffres en réunion : pour une fois, personne n'a parlé de vous rappeler." },
	{ "id": "storm", "text": "La tempête couvre toute votre région. Nous ne pouvons rien faire d'ici. Tenez bon." },
	{ "id": "last_but_one", "text": "Je ne vais pas vous mentir : le prochain vol sera le dernier. Le budget n'ira pas plus loin." },
	{ "id": "last_cargo", "text": "C'est le dernier cargo. Après lui, tout ce que vous aurez, vous l'aurez fait vous-mêmes. Bonne chance, commandant." },
	{ "id": "autonomy", "text": "Dix sols sans rien nous demander. Vous n'avez plus besoin de nous. C'est exactement ce qu'il fallait prouver." },
	{ "id": "era2", "text": "Votre colonie fait la une ici. Des gens demandent à partir. Explorez, et préparez de quoi rentrer, au cas où." },
	{ "id": "evacuation", "text": "Nous avons appris pour l'évacuation. Personne ne vous le reproche. Mais chaque retour donne des arguments à ceux qui veulent tout arrêter." },
	{ "id": "era3", "text": "Le véhicule de retour est prêt, et personne ne veut le prendre. Je crois que vous êtes chez vous." },
	{ "id": "era4", "text": "Le vote est passé : la mission continue, et elle s'agrandit. Mars n'est plus le but. C'est le point de départ." },
	{ "id": "colony", "text": "Un deuxième monde habité. Dans les écoles, on redessine les cartes du Système solaire." },
	{ "id": "capital", "text": "Trente habitants, un grand dôme. Ma fille m'a demandé si elle pourrait y vivre un jour. J'ai répondu oui." },
	{ "id": "far", "text": "Vous êtes à plus d'une heure de radio. Je vous parle, et vous m'entendrez quand j'aurai fini mon café." },
	{ "id": "farewell", "text": "Commandant, ici Claire, pour la dernière fois : je pars à la retraite. Quand vous êtes partis, on se demandait s'il fallait encore regarder le ciel. Vous avez répondu sur cinq mondes. La Terre ne va pas mieux d'un coup. Mais elle a de nouveau envie d'essayer. Merci." },
]


## Texte d'un message ("" s'il n'existe pas).
static func text(id: String) -> String:
	for message: Dictionary in MESSAGES:
		if message.id == id:
			return message.text
	return ""


## Messages dont le moment est venu, dans l'ordre du récit (déjà montrés ou non).
static func due(campaign: Campaign) -> Array[String]:
	var list: Array[String] = []
	for message: Dictionary in MESSAGES:
		if _is_due(campaign, message.id):
			list.append(message.id)
	return list


## Prochain message à montrer ("" : aucun).
static func next(campaign: Campaign) -> String:
	for id in due(campaign):
		if not campaign.story_seen.has(id):
			return id
	return ""


static func _is_due(campaign: Campaign, id: String) -> bool:
	var mars := campaign.engines[0]
	var done := mars.state.objectives_done
	match id:
		"oxygen":
			return done.has("first_breath")
		"water":
			return done.has("water")
		"storm":
			return mars.is_storm()
		"last_but_one":
			return mars.planet_id() == "mars" and mars.resupplies_left() <= 1
		"last_cargo":
			return mars.planet_id() == "mars" and mars.resupplies_left() == 0
		"autonomy":
			return done.has("autonomy")
		"era2":
			return mars.state.era >= 2
		"evacuation":
			for colony in campaign.colonies:
				if colony.evacuated > 0:
					return true
			return false
		"era3":
			return mars.state.era >= 3
		"era4":
			return mars.state.era >= 4
		"colony":
			return campaign.colonies.size() >= 2
		"capital":
			return done.has("capital")
		"far":
			for i in campaign.colonies.size():
				if campaign.planet_of(i) in ["europa", "enceladus"]:
					return true
			return false
		"farewell":
			return campaign.is_complete()
	return false
