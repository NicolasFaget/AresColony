class_name Defs
extends RefCounted
## Types de données statiques du jeu (jamais sauvegardés). Regroupés ici car ce sont de simples
## conteneurs : bâtiments, recherches, fiches de découverte, objectifs.


## Module que l'on peut construire sur la grille.
class Building:
	var id: String
	var name: String
	## Emprise en cases.
	var size: Vector2i
	## Coût en matériaux.
	var cost: float
	## Consommation et production par sol, par ressource.
	var inputs: Dictionary
	var outputs: Dictionary
	## Capacités de stockage ajoutées, par ressource.
	var storage: Dictionary
	## Colons hébergés.
	var housing: int
	## Production d'énergie dépendante du soleil (jour/nuit, tempêtes).
	var solar: bool
	## Type de case exigé sous le module ("" : n'importe quelle case constructible).
	var requires_tile: int
	## Recherche qui débloque le module ("" : disponible dès le départ).
	var research: String
	## Fiche de découverte liée.
	var card: String
	var description: String
	## Module de départ, ni constructible ni démolissable.
	var fixed: bool

	## Colons protégés des radiations pendant une éruption solaire.
	var shelter: int

	func _init(p: Dictionary) -> void:
		id = p.id
		name = p.name
		size = p.get("size", Vector2i.ONE)
		cost = p.get("cost", 0.0)
		inputs = p.get("inputs", {})
		outputs = p.get("outputs", {})
		storage = p.get("storage", {})
		housing = p.get("housing", 0)
		solar = p.get("solar", false)
		requires_tile = p.get("requires_tile", -1)
		research = p.get("research", "")
		card = p.get("card", "")
		description = p.get("description", "")
		fixed = p.get("fixed", false)
		shelter = p.get("shelter", 0)


## Recherche : coûte des données scientifiques et prend un peu de temps.
class Research:
	var id: String
	var name: String
	var cost: float
	## Durée en sols.
	var duration: float
	var requires: Array
	## Effets permanents (multiplicateurs), par exemple { "solar": 1.25 }.
	var effects: Dictionary
	## Fiche débloquée à la fin.
	var card: String
	var summary: String
	## Ère à partir de laquelle la recherche est possible.
	var era: int
	## Choix exclusif : la recherche concurrente (lancer l'une écarte l'autre pour toute la partie).
	var rival: String

	func _init(p: Dictionary) -> void:
		id = p.id
		name = p.name
		era = p.get("era", 1)
		cost = p.cost
		duration = p.get("duration", 1.0)
		requires = p.get("requires", [])
		effects = p.get("effects", {})
		card = p.get("card", "")
		summary = p.get("summary", "")
		rival = p.get("rival", "")


## Fiche de découverte : un fait réel, sourcé.
class Card:
	var id: String
	var title: String
	## « Mesuré », « Expérimenté », « Valeur de planification », « Chimie », « Hypothèse ».
	var status: String
	var fact: String
	var in_game: String
	## [[libellé, url], ...]
	var sources: Array
	## Chiffre clé mis en avant et sa légende.
	var figure: String
	var figure_label: String
	## Module qui illustre la fiche.
	var visual: String
	## Question de quiz, ses choix et l'index de la bonne réponse.
	var quiz: String
	var choices: Array
	var answer: int

	func _init(p: Dictionary) -> void:
		id = p.id
		title = p.title
		status = p.status
		fact = p.fact
		in_game = p.in_game
		sources = p.sources
		figure = p.get("figure", "")
		figure_label = p.get("figure_label", "")
		visual = p.get("visual", "lander")
		quiz = p.get("quiz", "")
		choices = p.get("choices", [])
		answer = p.get("answer", 0)


## Objectif de l'ère en cours.
class Objective:
	var id: String
	var title: String
	var description: String
	## Récompense : ressource -> quantité.
	var reward: Dictionary
	var era: int
	## Monde où l'objectif s'applique.
	var planet: String

	func _init(p: Dictionary) -> void:
		era = p.get("era", 1)
		planet = p.get("planet", "mars")
		id = p.id
		title = p.title
		description = p.description
		reward = p.get("reward", {})
