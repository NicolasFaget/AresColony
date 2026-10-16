class_name Splash
extends Control
## Écran du studio Kassándra Games (repris de Dune Hawk) : l'œil se dessine, puis l'iris, trois rayons
## et le nom du studio. Émet `done` après MIN secondes, une fois `ready_to_go` vrai ; un toucher l'abrège.

signal done

const MIN := 2.6
const AMBER := Color("e0a050")
const CREAM := Color("f4e2b8")
const DARK := Color("0b0906")

var ready_to_go := false
var _t := 0.0
var _out := -1.0
var _skip := false
var _font: Font
var _glow: GradientTexture2D


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = get_theme_default_font()
	_glow = GradientTexture2D.new()
	_glow.fill = GradientTexture2D.FILL_RADIAL
	_glow.fill_from = Vector2(0.5, 0.5)
	_glow.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.set_color(0, Color(AMBER, 1.0))
	g.set_color(1, Color(AMBER, 0.0))
	_glow.gradient = g
	_glow.width = 256
	_glow.height = 256


func _gui_input(e: InputEvent) -> void:
	if (e is InputEventScreenTouch and e.pressed) or (e is InputEventMouseButton and e.pressed):
		_skip = true


func _process(dt: float) -> void:
	# Une image très longue (chargement derrière) ne doit pas faire sauter l'animation.
	_t += minf(dt, 0.05)
	if _out < 0 and ready_to_go and (_t > MIN or (_skip and _t > 0.6)):
		_out = _t
	if _out >= 0 and _t - _out > 0.45:
		set_process(false)
		done.emit()
	queue_redraw()


static func _ease(x: float) -> float:
	return 1.0 - pow(1.0 - clampf(x, 0.0, 1.0), 3.0)


func _draw() -> void:
	var vs := get_viewport_rect().size
	var cx := vs.x / 2
	# Le logo a été dessiné pour un écran de 720 px de haut : on le centre verticalement.
	var oy := vs.y / 2.0 - 370.0
	var fade := 1.0 if _out < 0 else 1.0 - (_t - _out) / 0.45
	draw_rect(Rect2(Vector2.ZERO, vs), DARK)
	var glow := 0.13 * _ease(_t / 1.2) * fade
	draw_texture_rect(_glow, Rect2(cx - 420, oy + 300 - 420, 840, 840), false, Color(1, 1, 1, glow))
	var amber := Color(AMBER, fade)
	# Contour de l'œil, tracé progressivement.
	var ey := oy + 268.0
	var k := _ease(_t / 0.9)
	var pts := PackedVector2Array()
	var n := 64
	for i in n + 1:
		var u := float(i) / n
		var p: Vector2
		if u <= 0.5:
			p = _quad(Vector2(cx - 92, ey), Vector2(cx, ey - 74), Vector2(cx + 92, ey), u * 2.0)
		else:
			p = _quad(Vector2(cx + 92, ey), Vector2(cx, ey + 74), Vector2(cx - 92, ey), (u - 0.5) * 2.0)
		if u <= k:
			pts.append(p)
	if pts.size() > 1:
		draw_polyline(pts, amber, 5.0, true)
	var ki := _ease((_t - 0.5) / 0.5)
	if ki > 0:
		draw_arc(Vector2(cx, ey), 26 * ki, 0, TAU, 48, amber, 5.0, true)
		draw_circle(Vector2(cx, ey), 10 * ki, amber)
	for i in 3:
		var a: float = [-0.55, 0.0, 0.55][i]
		var kr := _ease((_t - 0.8 - i * 0.08) / 0.35)
		if kr <= 0:
			continue
		var p0 := Vector2(cx + sin(a) * 66, ey - 46 - cos(a) * 12)
		draw_line(p0, p0 + Vector2(sin(a), -cos(a)) * 26 * kr, amber, 5.0, true)
	# Le nom du studio monte un peu en apparaissant.
	var kn := _ease((_t - 0.6) / 0.7)
	_spaced("KASSÁNDRA", Vector2(cx, oy + 424 + 12 * (1 - kn)), 66, 16, Color(CREAM, fade * kn))
	var ks := _ease((_t - 1.0) / 0.6)
	_spaced("GAMES", Vector2(cx, oy + 470), 18, 12, Color(AMBER, fade * ks))
	draw_rect(Rect2(cx - 70 - 120 * ks, oy + 462, 120 * ks, 2), Color(AMBER, fade * ks))
	draw_rect(Rect2(cx + 70, oy + 462, 120 * ks, 2), Color(AMBER, fade * ks))
	if not ready_to_go and _t > MIN:
		var c := Color("c8b898", fade * (0.45 + 0.25 * sin(_t * 4)))
		draw_string(_font, Vector2(cx - 300, vs.y - 52), Tr.t("CHARGEMENT…"), HORIZONTAL_ALIGNMENT_CENTER, 600, 16, c)


static func _quad(a: Vector2, c: Vector2, b: Vector2, u: float) -> Vector2:
	return a.lerp(c, u).lerp(c.lerp(b, u), u)


## Texte espacé, centré sur `at`.
func _spaced(s: String, at: Vector2, size: int, spacing: float, col: Color) -> void:
	var w := 0.0
	for ch in s:
		w += _font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + spacing
	w -= spacing
	var x := at.x - w / 2
	for ch in s:
		draw_string(_font, Vector2(x, at.y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
		x += _font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + spacing
