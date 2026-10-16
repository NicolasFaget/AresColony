"""Générateur des icônes vectorielles d'Ares Colony (SVG, sans dépendance).

Icônes blanches : l'interface les teinte (couleur de chaque ressource, onglet actif...).
Usage : python tools/make_icons.py            (écrit dans art/icons/)
"""
import os

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "art", "icons")
W = "#FFFFFF"
icons = {}


def ui(body):
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="96" height="96" viewBox="0 0 64 64">{body}</svg>\n'


def stroke(d, width=5):
    return f'<path d="{d}" stroke="{W}" stroke-width="{width}" fill="none" stroke-linecap="round" stroke-linejoin="round"/>'


# ---------- Ressources ----------
icons["energy"] = ui(f'<path d="M36 4 L12 36 H30 L26 60 L52 26 H34 Z" fill="{W}" stroke="{W}" stroke-width="2" stroke-linejoin="round"/>')
icons["oxygen"] = ui(f'<circle cx="26" cy="36" r="20" stroke="{W}" stroke-width="5" fill="none"/>'
                     f'<circle cx="48" cy="16" r="10" stroke="{W}" stroke-width="5" fill="none"/>'
                     f'<path d="M18 30 a10 10 0 0 1 8 -6" stroke="{W}" stroke-width="4" fill="none" stroke-linecap="round"/>')
icons["water"] = ui(f'<path d="M32 4 C24 18 12 28 12 40 a20 20 0 0 0 40 0 C52 28 40 18 32 4 Z" fill="{W}"/>')
icons["food"] = ui(stroke("M32 60 V30") + f'<path d="M32 34 C32 18 20 10 6 12 C6 26 18 34 32 34 Z" fill="{W}"/>'
                   f'<path d="M32 28 C34 14 46 6 58 8 C58 22 46 30 32 28 Z" fill="{W}"/>')
icons["materials"] = ui(f'<path d="M8 22 L32 10 L56 22 L32 34 Z" fill="{W}"/>'
                        f'<path d="M8 26 L30 37 V60 L8 48 Z M56 26 L34 37 V60 L56 48 Z" fill="{W}"/>')
icons["data"] = ui(f'<rect x="16" y="16" width="32" height="32" rx="6" stroke="{W}" stroke-width="5" fill="none"/>'
                   f'<rect x="26" y="26" width="12" height="12" rx="2" fill="{W}"/>'
                   + stroke("M24 6 V16 M40 6 V16 M24 48 V58 M40 48 V58 M6 24 H16 M6 40 H16 M48 24 H58 M48 40 H58", 4))

# ---------- Onglets ----------
icons["tab_build"] = ui(f'<path d="M10 54 L36 28" stroke="{W}" stroke-width="8" stroke-linecap="round"/>'
                        f'<path d="M30 10 L54 10 L54 22 L44 22 L44 34 L34 34 L34 22 L30 22 Z" fill="{W}"/>')
icons["tab_colony"] = ui(f'<circle cx="22" cy="18" r="9" fill="{W}"/><circle cx="44" cy="22" r="7" fill="{W}"/>'
                         f'<path d="M4 56 a18 18 0 0 1 36 0 Z" fill="{W}"/><path d="M34 56 a14 14 0 0 1 26 0 Z" fill="{W}"/>')
icons["tab_research"] = ui(stroke("M24 6 H40 M27 6 V24 L12 50 a5 5 0 0 0 4 8 H48 a5 5 0 0 0 4 -8 L37 24 V6")
                           + f'<path d="M18 42 H46 L51 51 a3 3 0 0 1 -3 4 H16 a3 3 0 0 1 -3 -4 Z" fill="{W}"/>')
icons["tab_knowledge"] = ui(f'<path d="M6 12 C18 8 26 10 31 14 V56 C26 52 18 50 6 54 Z" fill="{W}"/>'
                            f'<path d="M58 12 C46 8 38 10 33 14 V56 C38 52 46 50 58 54 Z" fill="{W}" opacity=".75"/>')

# ---------- Temps ----------
icons["pause"] = ui(f'<rect x="14" y="10" width="12" height="44" rx="3" fill="{W}"/><rect x="38" y="10" width="12" height="44" rx="3" fill="{W}"/>')
icons["play"] = ui(f'<path d="M16 8 L54 32 L16 56 Z" fill="{W}" stroke="{W}" stroke-width="3" stroke-linejoin="round"/>')
icons["fast"] = ui(f'<path d="M6 12 L32 32 L6 52 Z M32 12 L58 32 L32 52 Z" fill="{W}" stroke="{W}" stroke-width="3" stroke-linejoin="round"/>')
icons["sun"] = ui(f'<circle cx="32" cy="32" r="12" fill="{W}"/>'
                  + stroke("M32 4 V12 M32 52 V60 M4 32 H12 M52 32 H60 M12 12 L18 18 M46 46 L52 52 M12 52 L18 46 M46 18 L52 12", 4))
icons["moon"] = ui(f'<path d="M40 6 A26 26 0 1 0 58 42 A20 20 0 1 1 40 6 Z" fill="{W}"/>')
icons["storm"] = ui(stroke("M6 22 H40 a8 8 0 1 0 -8 -8 M6 34 H52 a8 8 0 1 1 -8 8 M10 46 H30", 5))

# ---------- Divers ----------
icons["gear"] = ui(f'<path fill-rule="evenodd" d="M27 4 h10 l2 7 l5 2 l6 -4 l7 7 l-4 6 l2 5 l7 2 v10 l-7 2 l-2 5 l4 6 l-7 7 l-6 -4 l-5 2 l-2 7 h-10 l-2 -7 l-5 -2 l-6 4 l-7 -7 l4 -6 l-2 -5 l-7 -2 v-10 l7 -2 l2 -5 l-4 -6 l7 -7 l6 4 l5 -2 Z M32 23 a9 9 0 1 0 0.01 0 Z" fill="{W}"/>')
icons["lock"] = ui(f'<path d="M20 28 V20 a12 12 0 0 1 24 0 V28" stroke="{W}" stroke-width="6" fill="none"/><rect x="12" y="28" width="40" height="30" rx="7" fill="{W}"/>')
icons["check"] = ui(stroke("M12 34 L26 48 L52 18", 8))
icons["clock"] = ui(f'<circle cx="32" cy="32" r="24" stroke="{W}" stroke-width="5" fill="none"/>' + stroke("M32 18 V32 L42 38"))
icons["close"] = ui(stroke("M16 16 L48 48 M48 16 L16 48", 7))
icons["warning"] = ui(f'<path d="M32 6 L60 56 H4 Z" fill="{W}" stroke="{W}" stroke-width="4" stroke-linejoin="round"/>'
                      f'<path d="M32 24 V38" stroke="#000" stroke-width="6" stroke-linecap="round" opacity=".55"/><circle cx="32" cy="47" r="3.5" fill="#000" opacity=".55"/>')
icons["news"] = ui(f'<path d="M8 26 V38 H16 L40 50 V14 L16 26 Z" fill="{W}" stroke="{W}" stroke-width="3" stroke-linejoin="round"/>'
                   + stroke("M47 22 q6 10 0 20 M53 16 q10 16 0 32", 4))
icons["rocket"] = ui(f'<path d="M32 4 C44 14 46 30 42 44 H22 C18 30 20 14 32 4 Z" fill="{W}"/>'
                     f'<path d="M22 36 L12 48 L22 46 Z M42 36 L52 48 L42 46 Z" fill="{W}"/><path d="M26 48 L32 60 L38 48 Z" fill="{W}" opacity=".7"/>')
icons["person"] = ui(f'<circle cx="32" cy="16" r="11" fill="{W}"/><path d="M12 58 a20 20 0 0 1 40 0 Z" fill="{W}"/>')
icons["trash"] = ui(stroke("M10 16 H54 M24 16 V8 H40 V16", 5) + f'<path d="M16 20 H48 L45 58 H19 Z" fill="{W}"/>')
icons["target"] = ui(f'<circle cx="32" cy="32" r="24" stroke="{W}" stroke-width="5" fill="none"/>'
                     f'<circle cx="32" cy="32" r="12" stroke="{W}" stroke-width="5" fill="none"/><circle cx="32" cy="32" r="4" fill="{W}"/>')
icons["methane"] = ui(f'<path d="M32 4 C40 18 52 26 52 42 a20 20 0 0 1 -40 0 C12 32 18 26 22 18 C24 26 28 30 32 30 C30 22 28 14 32 4 Z" fill="{W}"/>'
                      f'<path d="M32 58 a9 9 0 0 1 -9 -9 C23 42 28 38 32 34 C36 38 41 42 41 49 a9 9 0 0 1 -9 9 Z" fill="#000" opacity=".35"/>')
icons["rover"] = ui(f'<rect x="10" y="20" width="44" height="20" rx="5" fill="{W}"/>'
                    f'<circle cx="16" cy="48" r="7" fill="{W}"/><circle cx="32" cy="48" r="7" fill="{W}"/><circle cx="48" cy="48" r="7" fill="{W}"/>'
                    + stroke("M44 20 V8 M38 8 H50", 4))
icons["planet"] = ui(f'<circle cx="32" cy="32" r="16" fill="{W}"/>'
                     f'<ellipse cx="32" cy="34" rx="29" ry="9" stroke="{W}" stroke-width="4" fill="none" transform="rotate(-20 32 34)"/>'
                     f'<circle cx="26" cy="27" r="4" fill="#000" opacity=".3"/><circle cx="37" cy="37" r="3" fill="#000" opacity=".25"/>')
icons["link"] = ui(stroke("M26 38 L38 26", 6) + stroke("M22 30 L16 36 a8 8 0 0 0 12 12 L34 42 M42 34 L48 28 a8 8 0 0 0 -12 -12 L30 22", 5))


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, svg in icons.items():
        with open(os.path.join(OUT, name + ".svg"), "w", encoding="utf-8", newline="\n") as f:
            f.write(svg)
    print("%d icônes écrites dans %s" % (len(icons), OUT))


if __name__ == "__main__":
    main()
