class_name Palette
extends RefCounted
## Couleurs de l'interface : verre sombre posé sur le monde 3D, accents vifs.

const TEXT := Color("#eaf6ff")
const TEXT_MUTED := Color("#9db8cb")
const TEXT_DIM := Color("#5f7d92")
const TEXT_LIGHT := Color("#ffffff")

const GLASS := Color(0.03, 0.09, 0.15, 0.95)
const CARD := Color(1.0, 1.0, 1.0, 0.055)
const CARD_LOCKED := Color(1.0, 1.0, 1.0, 0.025)
const BORDER := Color(0.62, 0.9, 1.0, 0.12)
const SHADOW := Color(0.0, 0.02, 0.06, 0.45)
const DIM_OVERLAY := Color(0.0, 0.03, 0.08, 0.6)

## Cyan : action principale. Or : argent et achats. Violet : renommée.
const ACCENT := Color("#2ee6d6")
const ON_ACCENT := Color("#04302c")
const MONEY := Color("#ffc94d")
const ON_MONEY := Color("#3d2700")
const FAME := Color("#c4b0ff")
const VIOLET := Color("#9b7bff")
const INCOME := ACCENT
const NEWS := Color("#eaf6ff")
const OUTLINE := Color(0.0, 0.04, 0.08, 0.85)
const SUCCESS := Color("#5be49b")
const DANGER := Color("#ff6f61")

const WARNING := Color("#ffb347")

## Couleur de chaque ressource (icônes, barres).
const RESOURCE_COLORS := {
	"energy": Color("#ffd24d"),
	"oxygen": Color("#7fe8ff"),
	"water": Color("#4f9dff"),
	"food": Color("#7ddc6a"),
	"materials": Color("#e0a070"),
	"data": Color("#c4b0ff"),
	"methane": Color("#ff8a5c"),
}

## Couleur du statut d'une fiche de découverte.
const STATUS_COLORS := {
	"Mesuré": Color("#5be49b"),
	"Expérimenté": Color("#7fe8ff"),
	"Valeur de planification": Color("#ffd24d"),
	"Chimie": Color("#c4b0ff"),
	"Hypothèse": Color("#ffb347"),
}


static func resource_color(resource: String) -> Color:
	return RESOURCE_COLORS.get(resource, TEXT)
