# Ares Colony — conception technique

Tycoon de colonie martienne en gestion active, pour ados et adultes curieux. Godot 4.5+
(testé avec 4.7.2), GDScript, mobile en portrait (base 720×1280, renderer Mobile).
Vision et choix de conception : [docs/CONCEPT_MARS.md](docs/CONCEPT_MARS.md).

État : **prototype jouable de l'ère 1 « Survie »** (cratère Jezero).

## Lancer

- Ouvrir le dossier dans Godot, puis F5. Au premier lancement :
  `godot --headless --path . --import` pour enregistrer les `class_name`.
- Tests (simulation, sauvegarde, équilibrage par un joueur simulé) :
  `godot --headless --path . -s tests/run_tests.gd` (code de sortie 0 si tout passe).
- Captures d'écran (avec fenêtre) :
  `godot --path . --resolution 720x1400 -s tests/capture.gd -- --save=capture --out=<dossier> --scenario=<nom>`
  avec `debut`, `milieu`, `nuit`, `tempete` ou `interaction` (touchers simulés).
- Icônes : `python tools/make_icons.py` ; sons : `python tools/make_sounds.py` (aucune dépendance).
- Android : preset « Android » (arm64, vibrations) dans `export_presets.cfg`.

## Comment on joue

- **Construire** : choisir un module, toucher le sol pour placer le fantôme (vert : valide et
  raccordé ; jaune : isolé ; rouge : impossible), « Construire ici ». On reste en placement pour
  enchaîner (conduites, panneaux).
- **Raccorder** : un module ne fonctionne que s'il touche, de proche en proche, l'atterrisseur.
  Les conduites (4 matériaux) servent à aller loin, par exemple jusqu'à la glace.
- **Équilibrer** : six ressources (énergie, oxygène, eau, nourriture, matériaux, données),
  bilan moyen par sol affiché en haut. Toucher une ressource explique d'où elle vient.
- **Rechercher** : les données (atterrisseur + colons) financent 8 recherches ; chacune débloque
  une fiche de découverte sourcée.
- **Survivre** : nuits sans soleil (batteries), tempêtes annoncées un sol à l'avance (20 % de
  lumière), ravitaillements de la Terre tous les 8 sols (matériaux, nourriture qui diminue,
  recrues s'il y a de la place).
- **Temps** : pause, ×1, ×2, ×4. Un sol dure 60 s à ×1.

## Architecture

```
AresColony/
├── core/                  logique pure : RefCounted, aucun nœud, aucun accès disque
│   ├── definitions.gd     types : module, recherche, fiche, objectif
│   ├── colony_content.gd  contenu de l'ère 1 (modules, recherches, fiches sourcées, objectifs, équipage, humour)
│   ├── colony_map.gd      grille 24×24 du cratère (plaines, rochers, rebord, glace)
│   ├── colony_state.gd    état sauvegardable, lecture tolérante
│   ├── colony_engine.gd   simulation : flux, jour/nuit, raccordements, recherche, colons, événements, hors-ligne
│   ├── save_service.gd, save_storage.gd, number_formatter.gd   (repris de Seabed Tycoon)
├── game/                  pont avec Godot : GameManager (boucle, sauvegarde, cycle de vie), AudioManager, fichiers
├── world/                 monde 3D : terrain, modules, ciel, tempêtes, astronautes, placement, caméra, vignettes
├── ui/                    interface : thème, bandeau des ressources, panneau à onglets, pages, fenêtres
├── art/                   icônes (SVG) et sons (WAV) générés
├── tools/                 générateurs d'icônes et de sons
├── tests/                 run_tests.gd, colony_bot.gd (joueur simulé), capture.gd
└── docs/                  concept
```

Règles de séparation (comme Seabed Tycoon) : `core/` ne connaît ni nœud ni disque ; `world/`
et `ui/` lisent `GameManager.engine` et n'inventent aucune règle ; seul `game/` connaît le cycle
de vie de l'application.

## Simulation (ColonyEngine)

- Pas de 0,02 sol. À chaque pas : production des modules sans entrée (panneaux) ; pour chaque
  ressource demandée, part satisfaisable = (réserve + production passive) / demande ; chaque module
  tourne au minimum des parts de ses entrées ; les colons consomment ; stocks bornés par les capacités.
- Soleil : `max(0, cos(2π(heure − midi))) · π` (moyenne 1 par sol), ×0,2 en tempête, ×1,25 avec
  la recherche « Nettoyage des panneaux ».
- Santé : un manque d'oxygène vide les réserves de secours en environ un sol, puis le colon est
  évacué (jamais de mort). La cause et la parade sont expliquées.
- Synergies (`ColonyContent.SYNERGIES`) : un module qui touche directement un voisin du bon type
  gagne un multiplicateur sur ses entrées ou sorties (une fois par type de synergie). Calculées dans
  `_rebuild()` ; `preview_synergies()` alimente l'aperçu au placement ; jonctions dorées dans le monde.
- Améliorations (`ColonyContent.UPGRADES`) : deux niveaux par module, chacun une vraie technologie ;
  coût = 0,8 puis 1,2 × le prix du module en matériaux, et 15 puis 30 données.
- Note d'efficacité (`colony_rating()`) sur 100 : fonctionnement 40 (rendement lissé des modules
  consommateurs), raccordement 10, synergies 25, améliorations 25. A ≥ 85, B ≥ 70, C ≥ 55, D ≥ 40.
- Difficulté : poussière sur les panneaux (1,5 %/sol, 6 %/sol en tempête, jusqu'à −70 % ; tourbillons
  qui en nettoient quelques-uns tous les 5 à 9 sols ; sortie de nettoyage = 0,3 kg d'O₂ par panneau) ;
  pannes des machines (2 % par machine et par sol dès le sol 6, réparation = 30 % du prix, jamais
  en pilote automatique) ; chaque colon consomme 0,5 kWh/sol ; six ravitaillements avec matériaux,
  ensuite seulement des volontaires : le four à régolithe (recherche « Frittage du régolithe »)
  fabrique les matériaux. Les tests coupent poussière et pannes (`dust_rate`, `breakdown_rate`).
- Ère 2 « Expansion » (dès que l'ère 1 est accomplie) : méthane (7ᵉ ressource), réacteur Sabatier
  (4,5 kg d'eau → 2 kg de CH₄ + 8 kg d'O₂, proportions réelles 36:16:64), réservoirs, garage et
  expéditions (20 kg de méthane, 2 sols, 4 sites réels autour de Jezero puis des prospections),
  véhicule de retour (Mars Direct) à remplir de 200 kg de méthane. Joueur simulé : ère 2 vers le sol 120.
- Ère 3 « Racines » : éruptions solaires (préavis 0,5 sol, durée 0,3 sol, tous les 10 à 16 sols) ;
  les colons au-delà des places d'abri (habitats enterrés, 4 places) perdent 1 de santé par sol.
  Réacteur à fission (60 kWh/sol constants), serre géante (sol vivant). Fin : 20 colons, tous abrités,
  note A. Joueur simulé : ère 3 vers le sol 150.
- Fiches : chacune a un chiffre clé, une illustration et un quiz à trois choix, tirés uniquement de
  son texte sourcé. Déblocage = écran plein « Nouvelle découverte » ; première lecture +5 données,
  bonne réponse au quiz +10 (une seule tentative).
- Hors-ligne (pilote automatique) : un sol toutes les 20 minutes d'absence, 8 h au plus, sans
  événement ni perte de santé ; veille sécurisée dès qu'une ressource vitale descend sous un quart
  de sol de consommation. Les échéances (tempêtes, ravitaillements) sont décalées d'autant.

## Équilibrage mesuré (joueur simulé, tests/run_tests.gd)

| Objectif | Sol atteint |
|---|---|
| Premier souffle (premier oxygène) | 0,8 |
| Source vitale (extracteur de glace) | 2,8 |
| Main verte (serre) | 8 |
| Équipage complet (8 colons) | 40 |
| Nuits sereines (150 kWh de stockage) | 24,5 |
| Ingénierie fine (4 synergies actives) | 32 |
| Colonie modèle (note B, 12 modules) | 49 |
| Autonomie (10 sols sans déficit, 8 colons) | 50 |

Sans évacuation pour un joueur raisonnable. Un joueur qui ne fait rien perd son premier colon au
sol 9 environ : le danger est réel mais laisse le temps d'apprendre. Les tests vérifient ces
fourchettes.

## Campagne : plusieurs colonies

- `Campaign` (core/campaign.gd) : colonies (un `ColonyEngine` chacune), horloge commune, fusées en
  vol, savoir partagé (recherches, fiches, quiz : `sync_knowledge`). Seule la colonie affichée est
  simulée image par image ; les autres en pilote automatique (`run_autopilot`, veille si une réserve
  vitale baisse). Sauvegarde v2 = `Campaign.to_dict()` ; une ancienne sauvegarde devient une campagne.
- Ère 4 « Interplanétaire » (après « Racines ») : astroport, fondation d'une colonie (4 colons,
  150 matériaux, 60 kg de méthane), cargaisons (soute 300 unités, un colon = 10 ; carburant
  20 kg + 0,1 kg par unité). Saut entre deux sites de Mars : 1 sol.
- Une nouvelle colonie : savoir partagé, pas de ravitaillement de matériaux depuis la Terre ni de
  volontaires (le réseau s'en charge), calendrier de la colonie de départ, carte propre.
- Cérès (région « Cratère Occator ») : soleil ×0,3, chauffage ×1,5, pas d'air (ni tempêtes ni poussière,
  pas d'électrolyseur de CO₂ ni de Sabatier), décollage ×0,25 en carburant. Route Mars ⇄ Cérès :
  19 sols de trajet, fenêtre de 6 sols tous les 38 sols (1 sol de voyage ≈ 1 mois réel). L'avant-poste
  arrive avec un petit réacteur. Objectifs propres (PLANET_ERAS, `Objective.planet`).
- Titan (région « Rives de Ligeia Mare ») : soleil ×0,01, chauffage ×2, air épais sans CO₂ ni tempêtes,
  sol de glace d'eau (extracteur partout), lacs de méthane (pompe à méthane sur les cases de lac).
  Routes : Mars ⇄ Titan 78 sols (fenêtre tous les 24 sols), Cérès ⇄ Titan 92 sols (tous les 65).
  Décollage ×0,5. Objectifs propres ; objectif martien « Aux confins ».
- Modules propres à un monde : `PLANETS[...].forbidden` (raison affichée), masqués de la liste.

## Performances

- Le jeu avance d'un tout petit pas à chaque image : tout ce qui est appelé dans `_step` doit être
  léger. Caches : multiplicateurs par module (`rate_factor`), effets des recherches (`effect`),
  capacités de stockage (`capacity`), bilan d'autonomie (rafraîchi tous les STEP sols). Ils sont vidés
  dans `_rebuild()` et `upgrade()`. Mesure : ~370 µs par image sur PC pour 33 modules (1 200 avant).
- `_simulate_realtime()` (tests) rejoue l'ère 1 image par image à ×4 : mêmes résultats qu'en gros pas.
- Téléphone (Mali-G57) : ~43 images/s en début de partie, ~39 avec 64 modules (limite : le GPU).

## Langues

- Le français est la langue source ; `i18n/en.json` associe chaque texte français à l'anglais.
  `Tr.t("…")` traduit un modèle (`Tr.t("Sol %d") % n`) et les noms de contenu insérés ; les
  libellés et boutons se traduisent seuls quand leur texte correspond exactement à une clé.
- Après un ajout de texte : `python tools/i18n_check.py` liste ce qui manque dans `en.json`.
- La langue suit celle du téléphone, puis le réglage « Langue / Language ».

## Pièges

- Une lambda GDScript capture la *valeur* d'une variable à sa création : une fenêtre ouverte après
  la création de ses boutons se partage via un tableau (`var holder: Array[Modal] = []`).
- `trait` est un mot réservé de GDScript (ne pas l'utiliser comme nom de variable).
- `is_connected` est une méthode native de `Object` : d'où `is_linked`.
- Un script lancé par `-s` ne doit pas typer une classe qui utilise un autoload (`GameManager`).
- Sauter dans le temps en test déclenche les ravitaillements en retard : utiliser `_calm_engine()`.
- Le contenu (`colony_content.gd`) mêle valeurs réelles (fiches) et valeurs de jeu simplifiées :
  ne citer dans les fiches que des faits sourcés.

## Prochaines étapes

1. Troisième région ? Plus d'événements (météorites, aurores) ; sauvegarde dans le cloud.
2. Rovers d'exploration et sites à découvrir ; quiz facultatifs.
3. Ère 2 « Autonomie » : Sabatier, briques de régolithe, recyclage, deuxième région.
4. Tutoriel guidé, traduction anglaise.
