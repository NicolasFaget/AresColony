"""Extrait les textes affichés du projet (littéraux GDScript en français) vers un JSON.

Usage : python i18n_extract.py <racine du projet> <sortie.json>
"""
import glob
import json
import os
import re
import sys

root = sys.argv[1]
out = sys.argv[2]
SKIP_WORDS = {"Fermer", "Annuler", "Construire", "Colonie", "Recherche", "Savoir", "Placer", "Lire", "Fiche",
              "Retour", "Compris", "Supprimer", "Charger", "Commencer", "Recommencer", "Réglages", "Sauvegardes",
              "Continuer", "Terminer", "Mesuré", "Expérimenté", "Chimie", "Hypothèse", "Expéditions", "Entretien",
              "Synergies", "Montrer", "Partir"}
EXTRA = {"maintenant", "rations", "pilote", "chimiste", "biologiste", "botaniste", "Eau", "Nourriture", "Batteries",
         "Atterrisseur", "Conduite", "Expéditions", "Garage", "Musique", "Vibrations"}
pat = re.compile(r'"((?:[^"\\]|\\.)*)"')
found = {}
for f in glob.glob(os.path.join(root, "**", "*.gd"), recursive=True):
    rel = os.path.relpath(f, root).replace("\\", "/")
    if rel.startswith(("tests/", "addons/", "tools/")):
        continue
    for n, line in enumerate(open(f, encoding="utf-8"), 1):
        stripped = line.strip()
        if stripped.startswith("#"):
            continue
        # Messages pour les développeurs (journal, avertissements, options de ligne de commande,
        # clés internes de couleur) : jamais affichés au joueur.
        if re.search(r"\b(push_warning|push_error|printerr|print|assert)\(|--[a-z]+=|: Color\(", line):
            continue
        for m in pat.finditer(line):
            t = m.group(1)
            if not re.search(r"[A-Za-zÀ-ÿ]", t):
                continue
            if t in EXTRA:
                found.setdefault(t, f"{rel}:{n}")
                continue
            if re.fullmatch(r"[a-z0-9_./:%-]+", t):
                continue
            if re.fullmatch(r"[A-Z][A-Za-z0-9]+", t) and t not in SKIP_WORDS:
                continue
            if t.startswith(("res://", "user://", "http", "#")):
                continue
            if re.fullmatch(r"[A-Za-z_]+\|.*", t):
                continue
            found.setdefault(t, f"{rel}:{n}")
json.dump(found, open(out, "w", encoding="utf-8"), ensure_ascii=False, indent=0)
print(len(found), "textes,", sum(len(k) for k in found), "caractères")
