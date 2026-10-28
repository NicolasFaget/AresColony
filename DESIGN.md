# Ares Colony — conception technique

Tycoon de colonie martienne en gestion active, pour ados et adultes curieux. Godot 4.5+
(testé avec 4.7.2), GDScript, mobile en portrait (base 720×1280, renderer Mobile).
Vision et choix de conception : [docs/CONCEPT_MARS.md](docs/CONCEPT_MARS.md).

État : **jeu complet en démo** : quatre ères sur Mars (Survie, Autonomie, Expansion, Interplanétaire),
deux régions martiennes (Jezero, Arcadia), avant-postes sur Cérès et Titan, français et anglais.
Reste avant publication : fiche Google Play, signature, politique de confidentialité.

## Lancer

- Ouvrir le dossier dans Godot, puis F5. Au premier lancement :
  `godot --headless --path . --import` pour enregistrer les `class_name`.
- Tests (simulation, sauvegarde, équilibrage par un joueur simulé) :
  `godot --headless --path . -s tests/run_tests.gd` (code de sortie 0 si tout passe).
- Captures d'écran (avec fenêtre) :
  `godot --path . --resolution 720x1400 -s tests/capture.gd -- --save=capture --out=<dossier> --scenario=<nom>`
  avec `menu`, `debut`, `milieu`, `synergies`, `fiches`, `ameliorations`, `entretien`, `ere2`, `ere3`,
  `biodome`, `rover`, `arcadia`, `reseau`, `ceres`, `titan`, `splash` ou `interaction` (touchers simulés),
  et `--lang=en` pour l'anglais.
- Contrôle du menu : `godot --headless --path . -s tests/ui_menu_check.gd` (sauvegardes dans
  `user://ui_check`, jamais celles du joueur).
- Icônes : `python tools/make_icons.py` ; sons : `python tools/make_sounds.py` (aucune dépendance).
- Android : preset « Android » (arm64, vibrations) dans `export_presets.cfg`.
- Intégration continue (`.github/workflows/ci.yml`, à chaque envoi sur GitHub) : tests de simulation,
  contrôle du menu, traductions (`tools/i18n_check.py` échoue s'il manque un texte), puis APK de
  débogage téléchargeable dans l'onglet Actions.

## Comment on joue

- **Construire** : choisir un module, toucher le sol pour placer le fantôme (vert : valide et
  raccordé ; jaune : isolé ; rouge : impossible), « Construire ici ». On reste en placement pour
  enchaîner (conduites, panneaux).
- **Raccorder** : un module ne fonctionne que s'il touche, de proche en proche, l'atterrisseur.
  Les conduites (4 matériaux) servent à aller loin, par exemple jusqu'à la glace.
- **Équilibrer** : sept ressources (énergie, oxygène, eau, nourriture, matériaux, données, méthane),
  bilan moyen par sol affiché en haut. Toucher une ressource explique d'où elle vient ; la fiche d'un
  module et le détail d'une ressource utilisent les mêmes débits que le bandeau
  (`ColonyEngine.building_flows`) : soleil moyen, poussière, synergies, améliorations, pannes.
- **Rechercher** : les données (atterrisseur + colons) financent 18 recherches réparties sur quatre ères ;
  chacune débloque une fiche de découverte sourcée (quiz facultatif).
- **Optimiser** : synergies entre modules voisins, améliorations (niveaux 2 et 3), note de colonie.
- **Entretenir** : poussière sur les panneaux, pannes à réparer, expéditions en rover.
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

Mesures d'octobre 2026 (Jezero, `_simulate_campaign`) :

| Objectif | Sol atteint |
|---|---|
| Premier souffle (premier oxygène) | 0,8 |
| Source vitale (extracteur de glace) | 3,1 |
| Main verte (serre) | 8,3 |
| Équipage complet (8 colons) | 40 |
| Ingénierie fine (4 synergies actives) | 42,8 |
| Nuits sereines (150 kWh de stockage) | 43,8 |
| Colonie modèle (note B, 12 modules) | 44,8 |
| Autonomie (10 sols sans déficit réel, 8 colons) | 50,2 |
| Carburant martien (ère 2) | 60,8 |
| Ville (ère 2) | 64 |
| Explorateurs (3 expéditions) | 85,6 |
| Retour assuré (véhicule de retour) | 119,9 |
| Abri, Nucléaire, Jardin (ère 3) | 139,5 à 148,3 |
| Enracinés (fin de l'ère 3) | 148,3 |
| Porte des étoiles (astroport) | 157 |
| Deuxième foyer, Cérès (fondation) | 251 |
| Aux confins (Titan fondé), première livraison | 327 à 328 |
| Capitale martienne (30 colons, un grand dôme pressurisé) | 404 |
| Mine de la ceinture (Cérès exporte 200 matériaux) | 410 |
| Station-service de Saturne (Titan exporte 200 kg de méthane) | 442 |

L'ère 4 est jouée pour de vrai par le joueur simulé (`ColonyBot.network`) : astroport, fondation de
Cérès puis de Titan, matériaux de Cérès vers les colonies qui ont de la place, méthane de Mars vers
Cérès (qui n'en produit pas), méthane de Titan vers le réseau. Le trajet Mars ⇄ Titan (78 sols) fait
l'essentiel de la durée de l'ère 4.

Avant-postes seuls, sans aucune cargaison de Mars (80 sols, `_simulate_outposts`) : Cérès respire au
sol 1,5 et raffine la saumure au sol 29 ; Titan respire au sol 0,8 et pompe le méthane au sol 16
(générateur à radio-isotopes de l'atterrisseur, +20 kWh/sol, comme Dragonfly ; pompe à 45 matériaux
et 4 kWh/sol) ; aucune évacuation.

Réacteur à fission : 60 kWh/sol jour et nuit, mais 1 matériau/sol d'entretien (moteurs Stirling,
radiateurs). Sans matériaux, il ralentit, et une alerte « Réacteur à l'arrêt » le signale.

Production : un module dont toutes les sorties sont pleines se met en veille et ne consomme rien
(un réacteur ne mange plus de matériaux quand les batteries sont pleines). La place réservée par une
cargaison en route compte comme pleine. Prévisions, bandeau et alertes utilisent les débits réels
(rendement récent des modules) ; le conseiller juge l'énergie sur le bilan réel (`energy_balance`).

Autonomie : 10 sols d'affilée sans déficit ; les tempêtes (plus 2 sols de remise en route) et les
pannes en cours mettent le compteur en pause au lieu de le remettre à zéro, tant qu'aucune réserve
vitale n'est vide. Une panne ne fait pas baisser le rendement moyen d'un module.

Sans évacuation pour un joueur raisonnable. Un joueur qui ne fait rien perd son premier colon au
sol 9,4 : le danger est réel mais laisse le temps d'apprendre. Les tests vérifient ces
fourchettes ; mettre ce tableau à jour après chaque rééquilibrage.

## Campagne : plusieurs colonies

- `Campaign` (core/campaign.gd) : colonies (un `ColonyEngine` chacune), horloge commune, fusées en
  vol, savoir partagé (recherches, fiches, quiz : `sync_knowledge`). Seule la colonie affichée est
  simulée image par image ; les autres en pilote automatique (`run_autopilot`, veille si une réserve
  vitale baisse). Sauvegarde v2 = `Campaign.to_dict()` ; une ancienne sauvegarde devient une campagne.
- Le besoin de Mars en ère 4 : l'azote (8ᵉ ressource). L'air martien n'en a qu'environ 2,6 %, sous
  moins de 1 % de la pression terrestre ; Titan en est faite (≈ 95 %) ; Cérès a des sels d'ammonium.
  La Terre envoie une seconde vague de 16 volontaires (`RECRUITS_ERA4`, Mars, ère 4) ; l'objectif
  « Capitale martienne » demande 30 colons et un grand dôme pressurisé. Grand dôme (recherche « Air à
  l'azote ») : 10 places, 0,8 kg d'azote/sol de fuites, ne loge personne sous 90 % de rendement
  (`is_pressurized`). Compresseur d'azote : 4 kg/sol × part d'azote de l'air (Titan 1, Mars 0,05,
  interdit sur Cérès) ; la raffinerie de saumure de Cérès en donne 1 kg/sol. Un dôme demande donc
  4 compresseurs martiens (240 matériaux, 24 kWh/sol), ou des livraisons de Cérès (19 sols) et
  Titan (78 sols). Joueur simulé : 175 kg importés, Capitale au sol 404.
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
- Recherches : une colonie peut lancer toute recherche de l'ère la plus avancée du réseau
  (`research_era()`, `campaign_era`) ; un avant-poste d'ère 1 peut donc étudier les saumures ou la
  cryogénie sur place. Les guides de Cérès et Titan commencent par ces recherches.
- Cargaisons : refusées si la colonie d'arrivée ne peut pas loger les colons ou stocker la cargaison
  dans sa place libre (stock actuel et fusées déjà en route compris) ; une perte à l'arrivée est
  annoncée. Les exportations comptent au départ, et ce qui est perdu à l'arrivée en est retiré.
  Sur Cérès, le méthane demande un réservoir (étape du guide).
- Guides : chaque colonie garde ses propres guides passés. Cérès : électrolyseur, extracteur, four,
  saumures, réservoir, garage, astroport, première cargaison. Titan : électrolyseur, extracteur, four,
  cryogénie, pompe, garage, expédition, astroport, première cargaison.
- Colonies en arrière-plan : pas d'événements, mais les rovers rentrent quand même.
- Sauvegarde : une campagne illisible est mise de côté et signalée (`CORRUPTED`) ; modules, régions,
  recherches et cargaisons inconnus d'une autre version sont écartés au chargement ; niveaux bornés,
  atterrisseur toujours en tête (reposé s'il manque).
- Absence : l'horloge de la campagne avance du temps écoulé, même si la colonie affichée se met en
  veille (les fusées continuent leur route).

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
  Les textes identiques dans les deux langues (noms propres, sources, unités) vont dans
  `i18n/same.txt`.
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

1. Publication Google Play : AAB signé, fiche FR/EN, politique de confidentialité.
2. Conception : branches de recherche exclusives (choix stratégiques).
3. Plus d'événements (météorites, aurores) ; sauvegarde dans le cloud.
