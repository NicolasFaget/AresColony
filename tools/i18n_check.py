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
subprocess.run([sys.executable, os.path.join(root, "tools", "i18n_extract.py"), root, out], check=True)
texts = json.load(open(out, encoding="utf-8"))
english = json.load(open(os.path.join(root, "i18n", "en.json"), encoding="utf-8"))
missing = [t for t in texts if t.replace("\n", "\n") not in english]
for text in missing:
    print(texts[text], "|", text)
print(len(missing), "textes sans traduction (noms propres et nombres compris)")
