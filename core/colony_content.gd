class_name ColonyContent
extends RefCounted
## Contenu de l'ère « Survie » : modules, recherches, fiches de découverte, objectifs, équipage.
## Les identifiants sont stockés dans la sauvegarde : ne jamais les renommer.
##
## Les quantités sont simplifiées pour le jeu, sauf mention contraire dans les fiches
## (par exemple les 0,84 kg d'oxygène par colon et par jour, valeur de la NASA).

const ENERGY := "energy"
const OXYGEN := "oxygen"
const WATER := "water"
const FOOD := "food"
const MATERIALS := "materials"
const DATA := "data"

const RESOURCES := [ENERGY, OXYGEN, WATER, FOOD, MATERIALS, DATA]
## Ressources dont le manque met les colons en danger.
const VITAL := [OXYGEN, WATER, FOOD]

const RESOURCE_NAMES := {
	ENERGY: "Énergie", OXYGEN: "Oxygène", WATER: "Eau", FOOD: "Nourriture",
	MATERIALS: "Matériaux", DATA: "Données",
}
## « manque d'énergie », « manque de nourriture »...
const RESOURCE_PARTITIVE := {
	ENERGY: "d'énergie", OXYGEN: "d'oxygène", WATER: "d'eau", FOOD: "de nourriture",
	MATERIALS: "de matériaux", DATA: "de données",
}
const RESOURCE_UNITS := {
	ENERGY: "kWh", OXYGEN: "kg", WATER: "kg", FOOD: "rations", MATERIALS: "u", DATA: "",
}

## Explications affichées quand on touche une ressource.
const RESOURCE_HELP := {
	ENERGY: "Produite par les panneaux solaires, seulement le jour, et bien moins pendant les tempêtes. Les batteries stockent le surplus de la journée pour la nuit.",
	OXYGEN: "Fabriqué à partir du CO₂ de l'air martien (électrolyseur de CO₂) ou de l'eau (électrolyseur d'eau). Chaque colon en respire 0,84 kg par sol.",
	WATER: "Extraite de la glace du sous-sol. Les colons la boivent, les serres et l'électrolyseur d'eau en consomment.",
	FOOD: "Livrée par la Terre au début, mais les ravitaillements diminuent : il faut cultiver sous serre.",
	MATERIALS: "Envoyés par la Terre à chaque ravitaillement. Ils servent à construire ; démolir un module en rend la moitié.",
	DATA: "Produites par le laboratoire de l'atterrisseur et par chaque colon. Elles financent la recherche.",
}

## Besoins d'un colon par sol.
const COLONIST_NEEDS := { OXYGEN: 0.84, WATER: 2.5, FOOD: 1.0 }
## Données scientifiques produites par chaque colon par sol.
const COLONIST_DATA := 1.0


static func buildings() -> Array[Defs.Building]:
	return [
		Defs.Building.new({
			"id": "lander", "name": "Atterrisseur", "size": Vector2i(2, 2), "fixed": true,
			"outputs": { ENERGY: 8.0, DATA: 3.0 }, "solar": true, "housing": 4,
			"storage": { ENERGY: 40.0, OXYGEN: 60.0, WATER: 120.0, FOOD: 80.0, MATERIALS: 400.0 },
			"card": "atmosphere",
			"description": "Votre vaisseau, devenu base : quelques panneaux, un labo, des réserves.",
		}),
		Defs.Building.new({
			"id": "link", "name": "Conduite", "cost": 4.0,
			"description": "Relie les modules : énergie, eau et air y circulent.",
		}),
		Defs.Building.new({
			"id": "solar", "name": "Panneau solaire", "cost": 15.0, "solar": true,
			"outputs": { ENERGY: 10.0 }, "card": "cleaning",
			"description": "Ne produit que le jour, et beaucoup moins pendant les tempêtes.",
		}),
		Defs.Building.new({
			"id": "habitat", "name": "Habitat gonflable", "size": Vector2i(2, 2), "cost": 60.0,
			"inputs": { ENERGY: 4.0 }, "housing": 4, "storage": { OXYGEN: 30.0, FOOD: 30.0 },
			"description": "Loge 4 colons de plus. Le chauffage consomme de l'énergie.",
		}),
		Defs.Building.new({
			"id": "moxie", "name": "Électrolyseur de CO₂", "cost": 30.0, "research": "moxie",
			"inputs": { ENERGY: 8.0 }, "outputs": { OXYGEN: 1.8 }, "card": "moxie",
			"description": "Extrait l'oxygène du CO₂ de l'atmosphère, comme MOXIE.",
		}),
		Defs.Building.new({
			"id": "battery", "name": "Batteries", "cost": 25.0, "research": "batteries",
			"storage": { ENERGY: 60.0 }, "card": "batteries",
			"description": "Stocke l'énergie du jour pour passer la nuit.",
		}),
		Defs.Building.new({
			"id": "extractor", "name": "Extracteur de glace", "size": Vector2i(2, 2), "cost": 45.0,
			"research": "ice", "requires_tile": ColonyMap.Tile.ICE,
			"inputs": { ENERGY: 8.0 }, "outputs": { WATER: 14.0 }, "storage": { WATER: 60.0 }, "card": "ice",
			"description": "Chauffe la glace du sous-sol et recueille l'eau. À poser sur la glace.",
		}),
		Defs.Building.new({
			"id": "greenhouse", "name": "Serre pressurisée", "size": Vector2i(2, 2), "cost": 50.0,
			"research": "greenhouse", "inputs": { ENERGY: 6.0, WATER: 3.0 },
			"outputs": { FOOD: 3.0, OXYGEN: 0.4 }, "storage": { FOOD: 40.0 }, "card": "greenhouse",
			"description": "Radis, cresson, tomates... La photosynthèse rend un peu d'oxygène.",
		}),
		Defs.Building.new({
			"id": "electrolyser", "name": "Électrolyseur d'eau", "cost": 35.0, "research": "electrolysis",
			"inputs": { ENERGY: 10.0, WATER: 3.4 }, "outputs": { OXYGEN: 3.0 }, "storage": { OXYGEN: 30.0 },
			"card": "electrolysis",
			"description": "Sépare l'eau en oxygène et hydrogène : plus efficace que le CO₂.",
		}),
	]


static func research() -> Array[Defs.Research]:
	return [
		Defs.Research.new({ "id": "moxie", "name": "Électrolyse du CO₂", "cost": 6.0, "duration": 0.5,
				"card": "moxie", "summary": "Débloque l'électrolyseur de CO₂ : votre premier oxygène." }),
		Defs.Research.new({ "id": "ice", "name": "Glace souterraine", "cost": 12.0, "duration": 1.0,
				"card": "ice", "summary": "Révèle la glace enfouie et débloque l'extracteur." }),
		Defs.Research.new({ "id": "batteries", "name": "Batteries lithium-ion", "cost": 15.0, "duration": 1.0,
				"card": "batteries", "summary": "Débloque les batteries pour tenir la nuit." }),
		Defs.Research.new({ "id": "greenhouse", "name": "Serre pressurisée", "cost": 20.0, "duration": 1.5,
				"requires": ["ice"], "card": "greenhouse", "summary": "Débloque la serre : cultiver sur Mars." }),
		Defs.Research.new({ "id": "electrolysis", "name": "Électrolyse de l'eau", "cost": 25.0, "duration": 1.5,
				"requires": ["ice"], "card": "electrolysis", "summary": "Débloque l'électrolyseur d'eau." }),
		Defs.Research.new({ "id": "cleaning", "name": "Nettoyage des panneaux", "cost": 25.0, "duration": 1.0,
				"requires": ["batteries"], "effects": { "solar": 1.25, "storm_solar": 1.5 }, "card": "cleaning",
				"summary": "Panneaux solaires +25 %, mieux protégés des tempêtes." }),
		Defs.Research.new({ "id": "perchlorate", "name": "Lavage des perchlorates", "cost": 35.0, "duration": 2.0,
				"requires": ["greenhouse"], "effects": { "food": 2.0 }, "card": "perchlorate",
				"summary": "Sol des serres assaini : récoltes ×2." }),
		Defs.Research.new({ "id": "recycling", "name": "Recyclage de l'eau", "cost": 40.0, "duration": 2.0,
				"requires": ["ice"], "effects": { "colonist_water": 0.4 }, "card": "recycling",
				"summary": "Les colons consomment 60 % d'eau en moins." }),
	]


static func objectives() -> Array[Defs.Objective]:
	return [
		Defs.Objective.new({ "id": "first_breath", "title": "Premier souffle",
				"description": "Produire de l'oxygène sur place.", "reward": { DATA: 10.0 } }),
		Defs.Objective.new({ "id": "water", "title": "Source vitale",
				"description": "Construire un extracteur de glace.", "reward": { MATERIALS: 40.0 } }),
		Defs.Objective.new({ "id": "green", "title": "Main verte",
				"description": "Construire une serre.", "reward": { DATA: 15.0 } }),
		Defs.Objective.new({ "id": "nights", "title": "Nuits sereines",
				"description": "Atteindre 150 kWh de stockage d'énergie.", "reward": { MATERIALS: 40.0 } }),
		Defs.Objective.new({ "id": "crew", "title": "Équipage complet",
				"description": "Accueillir 8 colons.", "reward": { DATA: 20.0 } }),
		Defs.Objective.new({ "id": "autonomy", "title": "Autonomie",
				"description": "Avec au moins 8 colons, tenir 10 sols d'affilée sans déficit d'oxygène, d'eau ni de nourriture.",
				"reward": { MATERIALS: 100.0 } }),
	]


static func cards() -> Array[Defs.Card]:
	return [
		Defs.Card.new({ "id": "atmosphere", "title": "L'air de Mars", "status": "Mesuré",
			"fact": "L'atmosphère martienne contient environ 95 % de dioxyde de carbone, 3 % d'azote et 1,6 % d'argon. Sa pression moyenne, 6 à 7 millibars, vaut moins de 1 % de celle de la Terre au niveau de la mer.",
			"in_game": "Impossible de respirer dehors : tout l'oxygène doit être fabriqué. Mais ce CO₂ est une ressource.",
			"sources": [["Arizona State University – Mars Education", "https://marsed.asu.edu/mep/atmosphere"]] }),
		Defs.Card.new({ "id": "oxygen_need", "title": "Ce que respire un astronaute", "status": "Valeur de planification",
			"fact": "Pour dimensionner ses systèmes de survie, la NASA compte environ 0,84 kg d'oxygène par membre d'équipage et par jour, et environ 1 kg de CO₂ rejeté.",
			"in_game": "Chaque colon consomme 0,84 kg d'oxygène par sol. Les autres besoins (eau, nourriture) sont simplifiés.",
			"sources": [["NASA – Baseline Values and Assumptions Document (2018)", "https://ntrs.nasa.gov/citations/20180001338"]] }),
		Defs.Card.new({ "id": "moxie", "title": "Fabriquer de l'oxygène avec l'air de Mars", "status": "Expérimenté",
			"fact": "L'instrument MOXIE, à bord du rover Perseverance, a séparé le CO₂ martien en oxygène et en monoxyde de carbone. De 2021 à 2023, il a produit 122 g d'oxygène en 16 essais, jusqu'à 12 g par heure, pur à 98 % ou plus.",
			"in_game": "L'électrolyseur de CO₂ est une version agrandie de MOXIE. Il consomme beaucoup d'énergie.",
			"sources": [["NASA JPL", "https://www.jpl.nasa.gov/news/nasas-perseverance-mars-rover-extracts-first-oxygen-from-red-planet/"],
					["MIT News", "https://news.mit.edu/2021/aboard-nasa-perseverance-mars-rover-moxie-creates-oxygen-0421"]] }),
		Defs.Card.new({ "id": "ice", "title": "De la glace sous la poussière", "status": "Mesuré",
			"fact": "En juin 2008, l'atterrisseur Phoenix a creusé une tranchée et mis au jour des morceaux blancs. En quatre jours, ils ont disparu : ils se sont sublimés, passant directement de la glace à la vapeur. La preuve qu'il s'agissait de glace d'eau.",
			"in_game": "La recherche révèle les plaques de glace du cratère. L'extracteur doit être posé dessus.",
			"sources": [["NASA JPL", "https://www.jpl.nasa.gov/news/bright-chunks-at-phoenix-landers-mars-site-must-have-been-ice/"]] }),
		Defs.Card.new({ "id": "batteries", "title": "Passer la nuit", "status": "Mesuré",
			"fact": "Le rover Perseverance tire son énergie d'un générateur nucléaire d'environ 110 watts, qui recharge deux batteries lithium-ion. Ce sont elles qui fournissent les pics de puissance, jusqu'à 900 watts.",
			"in_game": "Les panneaux ne produisent rien la nuit : sans batteries, vos machines s'arrêtent au coucher du soleil.",
			"sources": [["NASA JPL – dossier de presse Mars 2020", "https://www.jpl.nasa.gov/news/press_kits/mars_2020/launch/mission/spacecraft/power/"]] }),
		Defs.Card.new({ "id": "greenhouse", "title": "Des tomates dans de la « terre martienne »", "status": "Expérimenté",
			"fact": "À l'université de Wageningen, l'équipe de Wieger Wamelink a cultivé dix espèces sur un simulant de sol martien enrichi en matière organique : neuf ont donné une récolte, dont la tomate, le radis, le seigle et les petits pois. Le simulant ne contenait pas de perchlorates.",
			"in_game": "La serre produit de la nourriture et un peu d'oxygène, mais consomme de l'eau et de l'énergie.",
			"sources": [["Wageningen University", "https://research.wur.nl/en/publications/can-plants-grow-on-mars-and-the-moon-a-growth-experiment-on-mars-/"]] }),
		Defs.Card.new({ "id": "electrolysis", "title": "Casser l'eau", "status": "Chimie",
			"fact": "L'électrolyse sépare l'eau : 2 H₂O → 2 H₂ + O₂. Comme l'oxygène est bien plus lourd que l'hydrogène, 9 kg d'eau donnent 8 kg d'oxygène. C'est ainsi que la Station spatiale internationale produit l'essentiel de son air.",
			"in_game": "L'électrolyseur d'eau transforme 3,4 kg d'eau en 3 kg d'oxygène par sol : le vrai rapport chimique.",
			"sources": [["NASA – Oxygen Generation Assembly (NTRS)", "https://ntrs.nasa.gov/citations/19990087366"]] }),
		Defs.Card.new({ "id": "cleaning", "title": "Le vent, meilleur ami des rovers", "status": "Mesuré",
			"fact": "La poussière qui se dépose sur les panneaux solaires réduit leur production. Les rovers Spirit et Opportunity ont plusieurs fois été « nettoyés » par des rafales de vent ou des tourbillons de poussière, retrouvant d'un coup une partie de leur puissance.",
			"in_game": "La recherche simule des panneaux mieux entretenus : +25 % de production.",
			"sources": [["Sky & Telescope", "https://skyandtelescope.org/astronomy-news/opportunity-rover-gets-cleaning/"]] }),
		Defs.Card.new({ "id": "perchlorate", "title": "Le sol martien est toxique", "status": "Mesuré",
			"fact": "En 2008, l'atterrisseur Phoenix a mesuré environ 0,4 à 0,6 % de perchlorates dans le sol martien. Ces sels sont toxiques pour l'humain et gênent les cultures : il faut laver le régolithe avant de s'en servir.",
			"in_game": "Une fois le sol des serres assaini, les récoltes doublent.",
			"sources": [["NASA JPL", "https://www.jpl.nasa.gov/news/nasa-phoenix-results-point-to-martian-climate-cycles/"],
					["Université d'Arizona (Hecht et al., Science, 2009)", "https://experts.arizona.edu/en/publications/detection-of-perchlorate-and-the-soluble-chemistry-of-martian-soi/"]] }),
		Defs.Card.new({ "id": "recycling", "title": "Recycler 98 % de l'eau", "status": "Mesuré",
			"fact": "En 2023, la NASA a annoncé que le système de survie de la Station spatiale récupère environ 98 % de l'eau, y compris celle de l'urine et de la transpiration des astronautes.",
			"in_game": "Les colons consomment 60 % d'eau en moins (le jeu reste prudent).",
			"sources": [["ABC News (annonce de la NASA, juin 2023)", "https://abc7.com/post/nasa-recycle-urine-sweat/13433546/"]] }),
		Defs.Card.new({ "id": "storm", "title": "La tempête qui a eu raison d'Opportunity", "status": "Mesuré",
			"fact": "En juin 2018, une tempête de poussière a recouvert toute la planète. Le rover solaire Opportunity, prévu pour 90 jours, avait roulé plus de 45 km en 15 ans : privé de lumière, il s'est tu. Le rover nucléaire Curiosity, lui, n'a pas été affecté.",
			"in_game": "Pendant une tempête, les panneaux produisent beaucoup moins. Batteries et réserves sont vitales.",
			"sources": [["Sky & Telescope", "https://skyandtelescope.org/astronomy-news/opportunity-end-long-road/"]] }),
	]


## Équipage de départ : [prénom, spécialité].
const CREW := [["Ada", "ingénieure"], ["Malik", "botaniste"], ["Inès", "géologue"], ["Tom", "médecin"]]
## Renforts envoyés par la Terre.
const RECRUITS := [["Yuki", "chimiste"], ["Léo", "pilote"], ["Sofia", "ingénieure"], ["Omar", "biologiste"],
		["Nina", "géologue"], ["Paul", "médecin"], ["Zoé", "botaniste"], ["Kofi", "électricien"]]

## Messages d'ambiance du bandeau (avec une touche d'humour).
const CHATTER := [
	"Malik demande s'il peut appeler le premier radis « Bob ». Demande en cours d'examen.",
	"Contrôle de mission : merci de ne plus envoyer de selfies devant le rebord du cratère.",
	"Inès affirme que ce caillou ressemble à un chat. Inès a besoin de vacances.",
	"Tom rappelle que la poussière martienne ne se mange pas. Même salée.",
	"Ada a réparé la machine à café avec une pièce de rover. La NASA n'est pas au courant.",
	"Rappel : un sol dure 24 h 39 min. Non, ces 39 minutes ne sont pas des heures sup.",
	"Météo du jour : ciel couleur caramel, −60 °C, risque de poussière : élevé.",
	"La Terre se lève à l'horizon. Les colons font coucou. La Terre ne répond pas.",
	"Le recyclage de l'eau fonctionne parfaitement. Personne ne veut savoir comment.",
	"Message de la Terre : « Pensez à vous hydrater. » Merci, la Terre.",
	"Malik parle aux tomates. Elles poussent mieux. La science n'explique pas tout.",
	"Concours de lancer de pierres : record battu grâce à la gravité réduite.",
]
