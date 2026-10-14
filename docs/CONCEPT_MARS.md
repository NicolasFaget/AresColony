# Concept — tycoon de colonie martienne (titre de travail : « Ares Colony »)

> Document de conception, version 0.1, à valider avant tout développement.
> Public : ados et adultes curieux. Genre : tycoon de gestion active, mobile en portrait.

## 1. Pitch

Vous dirigez la première colonie permanente sur Mars. Il faut fabriquer de l'oxygène à partir
de l'atmosphère, trouver de l'eau, cultiver un sol toxique, se protéger des radiations et des
tempêtes de poussière, puis s'étendre jusqu'à rendre la planète un peu plus habitable.

Chaque bâtiment repose sur une vraie technique, chaque recherche débloque une **fiche de
découverte** sourcée. On apprend en jouant parce que les règles du jeu sont celles de la
réalité : pas d'oxygène sans énergie, pas de culture sans traiter le sol.

## 2. Principes de conception

1. **La science est la règle du jeu.** Les recettes de production suivent de vraies réactions.
   On simplifie les quantités, jamais le principe.
2. **Découvrir avant de construire.** Une technologie se mérite : explorer, analyser, rechercher.
3. **Chaque fait est sourcé.** Une fiche sans source vérifiée n'entre pas dans le jeu.
4. **Lisible sur un téléphone.** Sessions de 5 à 20 minutes, une main, pause à tout moment.
5. **L'échec instruit.** Une panne d'oxygène n'est pas une punition gratuite : le jeu explique
   ce qui s'est passé et pourquoi (« vos électrolyseurs manquaient d'énergie pendant la tempête »).

## 3. Boucle de jeu (gestion active)

```
Explorer (rovers)  →  Découvrir (échantillons, sites)  →  Rechercher (arbre + fiches)
       ↑                                                          ↓
  S'étendre (nouvelles régions)  ←  Équilibrer (ressources, colons)  ←  Construire
```

- **Construire** : on place des modules sur une grille isométrique (habitats, électrolyseurs,
  serres, panneaux solaires...). Les modules adjacents se raccordent (énergie, eau, air).
- **Équilibrer** : tableau de bord des flux (production − consommation par sol). Les goulets
  d'étranglement s'affichent sur la maquette 3D (un module en panne clignote).
- **Explorer** : des rovers parcourent la région, ramènent des échantillons et révèlent des
  sites (glace enfouie, minerai, grotte de lave pour s'abriter des radiations).
- **Rechercher** : les échantillons et l'énergie font avancer l'arbre de recherche.
- **Temps** : un sol de jeu (une journée martienne) dure quelques minutes. Commandes
  pause / ×1 / ×2 / ×4, comme dans les tycoons classiques.

## 4. Ressources et chaînes de production

| Ressource | Comment on l'obtient (réalité simplifiée) | Sert à |
|---|---|---|
| **Énergie** | Panneaux solaires (moins efficaces que sur Terre, gênés par la poussière), puis réacteur à fission compact | Tout |
| **Oxygène (O₂)** | 1) Électrolyse du CO₂ de l'atmosphère (comme MOXIE) ; 2) électrolyse de l'eau ; 3) plus tard, plantes et algues | Respiration, carburant |
| **Eau** | Extraction de la glace du sous-sol ou des pôles, recyclage des eaux usées | Boire, cultiver, électrolyse |
| **Hydrogène** | Sous-produit de l'électrolyse de l'eau | Réaction de Sabatier |
| **Méthane** | Réaction de Sabatier : CO₂ + 4 H₂ → CH₄ + 2 H₂O | Carburant des fusées et rovers |
| **Sol cultivable** | Régolithe lavé de ses perchlorates, enrichi en matière organique | Serres |
| **Nourriture** | Serres (cultures réelles : radis, cresson, tomate, seigle...), puis spiruline | Colons |
| **Matériaux** | Briques de régolithe frittées, métaux extraits | Construction |
| **Données scientifiques** | Rovers, laboratoires, observatoire | Recherche |

**Colons** : chaque colon consomme environ 0,84 kg d'O₂ par jour (valeur de planification de la
NASA) et produit environ 1 kg de CO₂. Moral, santé et dose de radiation cumulée sont suivis.
Les colons sont des spécialistes (ingénieur, botaniste, géologue, médecin) qui débloquent ou
accélèrent certaines tâches.

## 5. Les quatre ères

| Ère | Objectif | Exemples de recherches |
|---|---|---|
| **1. Survie** | Tenir avec les réserves apportées de la Terre, produire son premier oxygène | Panneaux solaires, électrolyse du CO₂ (MOXIE), extraction de glace, habitat gonflable |
| **2. Autonomie** | Ne plus dépendre des ravitaillements | Lavage des perchlorates, serres, recyclage de l'eau, réaction de Sabatier, briques de régolithe |
| **3. Expansion** | Plusieurs régions reliées, une vraie ville | Réacteur à fission, abris en tubes de lave, bioréacteurs à algues, fusée-navette vers Phobos |
| **4. Terraformation** | Modifier lentement la planète (prospective, clairement signalée comme telle) | Usines de gaz à effet de serre, miroirs orbitaux, lichens et cyanobactéries pionniers |

L'ère 4 relève de la recherche prospective : les fiches le disent explicitement
(« hypothèse scientifique », « jamais testé »), c'est aussi une leçon sur la démarche scientifique.

## 6. Régions (lieux réels)

| Région | Intérêt réel | Dans le jeu |
|---|---|---|
| Cratère Jezero | Ancien delta, site de Perseverance et de MOXIE | Région de départ, échantillons d'argiles |
| Utopia Planitia | Glace enfouie à faible profondeur | Eau abondante |
| Cratère Gale | Site de Curiosity, couches sédimentaires | Laboratoire de géologie, données |
| Valles Marineris | Canyon de plusieurs milliers de km | Minerais, abris naturels contre les radiations |
| Hellas Planitia | Point bas : pression atmosphérique plus élevée | Meilleur rendement des machines à CO₂ |
| Calotte polaire nord | Glace d'eau et de CO₂ | Eau en grande quantité, froid extrême |
| Olympus Mons | Plus grand volcan connu du système solaire | Objectif d'expédition, panorama |

## 7. Événements tirés de la réalité

- **Tempête de poussière** : la production solaire chute pendant des sols, voire des semaines.
  En 2018, une tempête planétaire a mis fin à la mission du rover Opportunity. Leçon : diversifier
  l'énergie (batteries, fission).
- **Éruption solaire** : pic de radiation, les colons doivent rejoindre un abri.
- **Saisons** : une année martienne dure environ 687 jours terrestres ; la pression et la
  température varient avec les saisons.
- **Découvertes** : glace dans un cratère récent, grotte de lave, météorite... qui ouvrent des
  recherches spéciales.

## 8. L'apprentissage

### Fiches de découverte
Débloquées par la recherche et l'exploration, rangées dans une **encyclopédie** à compléter.

Structure d'une fiche :
- **Titre** et illustration (le modèle 3D du bâtiment ou du lieu) ;
- **Le fait**, en 2 ou 3 phrases, avec un chiffre marquant ;
- **Dans le jeu** : à quoi ça sert concrètement ;
- **Pour aller plus loin** : la source (NASA, ESA, CNES, publication scientifique) ;
- **Statut** : « mesuré », « expérimenté » ou « hypothèse ».

### Quiz facultatifs
Après quelques fiches, une question à choix multiple rapporte un bonus de recherche.
Jamais bloquant, jamais punitif.

### Règle d'exactitude
Chaque fiche cite au moins une source primaire ou institutionnelle. Les valeurs
simplifiées pour l'équilibrage du jeu sont distinguées des valeurs réelles. Toutes les fiches
sont relues avant publication.

## 9. Premières fiches (exemples sourcés)

**Fabriquer de l'oxygène avec l'air de Mars** — *expérimenté*
L'atmosphère martienne est composée à environ 95 % de CO₂, avec une pression moyenne de
6 à 7 millibars, moins de 1 % de celle de la Terre. L'instrument MOXIE, à bord du rover
Perseverance, a séparé ce CO₂ en oxygène et en monoxyde de carbone. Entre 2021 et 2023, il a
produit 122 g d'oxygène en 16 essais, jusqu'à 12 g par heure, pur à 98 % ou plus.
*Dans le jeu* : premier bâtiment producteur d'oxygène ; il consomme beaucoup d'énergie.
Sources : [NASA JPL](https://www.jpl.nasa.gov/news/nasas-perseverance-mars-rover-extracts-first-oxygen-from-red-planet/),
[MIT News](https://news.mit.edu/2021/aboard-nasa-perseverance-mars-rover-moxie-creates-oxygen-0421),
[ASU Mars Education](https://marsed.asu.edu/mep/atmosphere).

**Le sol martien est toxique** — *mesuré*
En 2008, l'atterrisseur Phoenix a mesuré environ 0,4 à 0,6 % de perchlorates dans le sol
(Hecht et al., *Science*, 2009). Ces sels sont toxiques pour les humains et gênent les cultures :
il faut laver le régolithe avant de s'en servir comme sol.
*Dans le jeu* : la station de lavage débloque la culture en pleine serre.
Sources : [NASA JPL](https://www.jpl.nasa.gov/news/nasa-phoenix-results-point-to-martian-climate-cycles/),
[Université d'Arizona](https://experts.arizona.edu/en/publications/detection-of-perchlorate-and-the-soluble-chemistry-of-martian-soi/).

**Des tomates dans de la « terre martienne »** — *expérimenté (sol simulé)*
À l'université de Wageningen (Pays-Bas), l'équipe de Wieger Wamelink a cultivé dix espèces sur
un simulant de sol martien de la NASA enrichi en matière organique : neuf ont produit une partie
comestible, dont la tomate, le radis, le seigle et les petits pois (2019). Le simulant ne contient
pas de perchlorates : c'est une limite de l'expérience.
*Dans le jeu* : chaque culture débloquée a ses besoins et ses rendements.
Sources : [Wageningen University](https://research.wur.nl/en/publications/can-plants-grow-on-mars-and-the-moon-a-growth-experiment-on-mars-/),
article *Open Agriculture*, 2019, DOI 10.1515/opag-2019-0051.

**Les radiations à la surface** — *mesuré*
L'instrument RAD du rover Curiosity a mesuré environ 0,64 mSv par jour à la surface, et
1,84 mSv par jour pendant le voyage. Une mission de 360 jours de voyage et 500 jours sur place
exposerait un astronaute à environ 1 sievert.
*Dans le jeu* : dose cumulée par colon ; abris enterrés et tubes de lave la réduisent.
Sources : [Space.com](https://space.com/23875-mars-radiation-life-manned-mission.html),
[DLR](https://elib.dlr.de/106090).

**Combien d'oxygène respire un astronaute ?** — *valeur de planification*
La NASA retient environ 0,84 kg d'oxygène par membre d'équipage et par jour pour dimensionner
ses systèmes de survie (document BVAD).
*Dans le jeu* : chaque colon consomme cette quantité ; c'est la base de l'équilibrage.
Source : [NASA BVAD, NASA/TP-2015-218570/REV1](https://ntrs.nasa.gov/citations/20180001338).
À vérifier dans la table du document avant publication.

### À sourcer avant d'écrire les fiches correspondantes
Gravité (environ 38 % de la Terre), durée d'un sol (environ 24 h 40), ensoleillement (environ
43 % de celui de la Terre), réaction de Sabatier à bord de l'ISS, programme MELiSSA de l'ESA
(recyclage par algues), réacteur Kilopower de la NASA, fin d'Opportunity en 2018,
glace d'Utopia Planitia, dimensions d'Olympus Mons et de Valles Marineris.

## 10. Ce qu'on garde de Seabed Tycoon

| Garde | Change |
|---|---|
| Architecture : cœur pur testé, `GameManager`, pont Godot, interface séparée | Économie : plusieurs ressources et des flux par sol, au lieu d'une monnaie unique |
| Sauvegarde robuste (secours, migration, lecture tolérante) | Construction libre sur une grille (placement, raccordements) |
| Maquette 3D isométrique, caméra, `ModelBuilder`, studio de vignettes | Arbre de recherche à embranchements, encyclopédie, quiz |
| Interface moderne, thème, fenêtres, bandeau d'actualités | Colons avec besoins et spécialités |
| Audio : effets synthétisés, musique adaptative | Événements (tempêtes, éruptions solaires), commandes de vitesse |
| Tests et simulation du rythme | Simulation d'équilibre des flux (aucune ressource ne doit être structurellement impossible) |

Seabed Tycoon reste intact dans son dépôt : ce nouveau jeu partirait d'une copie.

## 11. Plan proposé

1. **Prototype jouable « Survie »** (première tranche verticale) :
   le cratère Jezero, 6 modules (atterrisseur, habitat, panneau solaire, MOXIE, extracteur de
   glace, serre), 4 ressources (énergie, oxygène, eau, nourriture), 4 colons, 8 recherches,
   8 fiches, la tempête de poussière. But : vérifier que la gestion active est amusante sur mobile.
2. **Ère Autonomie** : Sabatier, lavage des perchlorates, recyclage, briques, deuxième région.
3. **Encyclopédie et quiz**, puis les ères 3 et 4.
4. **Finitions** : tutoriel, équilibrage, traduction anglaise, publication.

## 12. Décisions

1. **Construction libre** sur une grille : on place ses modules où l'on veut. Sur téléphone :
   aperçu fantôme du module, validation par un bouton, rotation d'un toucher, raccordements
   affichés en direct (vert : raccordé, rouge : isolé).
2. **Pas de mort : l'évacuation.** Un colon en danger (manque d'oxygène, dose de radiation trop
   élevée, santé à zéro) est rapatrié vers la Terre. Coût : ses compétences, une baisse de moral
   et de réputation. Le jeu explique toujours la cause et la parade.
3. **Hors-ligne : pilote automatique sécurisé.**
   - La colonie continue avec les flux du moment (production − consommation par sol) ;
     la recherche avance à vitesse réduite.
   - Aucun événement ni aucune crise pendant l'absence.
   - Si une ressource vitale allait manquer, la colonie se met en **veille sécurisée** à ce
     moment précis ; au retour, le rapport explique la cause (« l'eau allait manquer : il vous
     faut un deuxième extracteur »).
   - Absence plafonnée à 8 h ; production limitée par les capacités de stockage.
4. **Ton : sérieux sur la science, avec une touche d'humour** dans les messages des colons, le
   bandeau d'actualités et les messages de la Terre. Les fiches restent factuelles.
   Exemples : « Le botaniste demande s'il peut appeler le radis "Bob". Demande refusée. »,
   « Contrôle de mission : merci de ne plus envoyer de selfies devant Olympus Mons. »
5. **Titre de travail : Ares Colony.**
