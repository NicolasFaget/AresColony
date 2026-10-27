"""Liste les textes du code absents de i18n/en.json (à traduire après un ajout).

Usage : python tools/i18n_check.py
"""
import json
import os
import subprocess
import sys
import tempfile

sys.stdout.reconfigure(encoding="utf-8")
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
out = os.path.join(tempfile.gettempdir(), "ares_strings.json")
subprocess.run([sys.executable, os.path.join(root, "tools", "i18n_extract.py"), root, out], check=True,
               stdout=subprocess.DEVNULL)
texts = json.load(open(out, encoding="utf-8"))
english = json.load(open(os.path.join(root, "i18n", "en.json"), encoding="utf-8"))
# Textes identiques dans les deux langues (noms propres, sources, unités, formats) : i18n/same.txt.
same_path = os.path.join(root, "i18n", "same.txt")
same = set(open(same_path, encoding="utf-8").read().splitlines()) if os.path.exists(same_path) else set()
missing = [t for t in texts if t.replace("\\n", "\n").replace('\\"', '"') not in english and t not in same]
for text in missing:
    print(texts[text], "|", text)
print(len(missing), "textes sans traduction (ajoutez-les à i18n/en.json, ou à i18n/same.txt s'ils restent identiques)")
sys.exit(1 if missing else 0)
