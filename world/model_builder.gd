class_name ModelBuilder
extends RefCounted
## Modèles 3D construits à partir de primitives (pas de fichier externe), habillés par des
## matériaux procéduraux : joints de panneaux, usure, poussière martienne (hull.gdshader),
## cellules solaires (solar.gdshader).
## Unité : une case de la grille. Origine au centre de l'emprise, au niveau du sol.

const WHITE := Color("#ecebe4")
const GREY := Color("#9aa0a6")
const DARK := Color("#3e434b")
const GOLD := Color("#d9a43a")
const ORANGE := Color("#e47a26")
const RED := Color("#b8322c")
const BLUE := Color("#2c4a7a")
const GLASS := Color(0.68, 0.92, 0.88, 0.3)
const GREEN := Color("#4c9a3c")
const DARK_GREEN := Color("#2f6e2c")
const CONCRETE := Color("#9e8f80")
const LIGHT := Color("#7ff5ea")
const WARM_LIGHT := Color("#ffd9a0")
const ROCK := Color("#5e2e1c")

static var _materials := {}
static var _grime: NoiseTexture2D


# ---------- Matériaux ----------

## Texture de bruit partagée (usure, poussière), générée une seule fois.
static func grime() -> Texture2D:
	if _grime == null:
		var noise := FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.frequency = 0.035
		noise.fractal_octaves = 4
		_grime = NoiseTexture2D.new()
		_grime.width = 256
		_grime.height = 256
		_grime.seamless = true
		_grime.noise = noise
	return _grime


## Matériau d'une couleur : revêtement procédural pour les surfaces opaques,
## matériau standard pour le verre et les lumières.
static func material(color: Color, emission := 0.0, metallic := 0.0) -> Material:
	var key := "%s|%s|%s" % [color.to_html(), emission, metallic]
	if _materials.has(key):
		return _materials[key]
	var mat: Material
	if color.a < 1.0 or emission > 0.0:
		var standard := StandardMaterial3D.new()
		standard.albedo_color = color
		standard.roughness = 0.08 if color.a < 1.0 else 0.5
		standard.metallic = metallic
		if color.a < 1.0:
			standard.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			standard.metallic_specular = 0.9
		if emission > 0.0:
			standard.emission_enabled = true
			standard.emission = color
			standard.emission_energy_multiplier = emission
		mat = standard
	else:
		mat = hull(color, metallic * 0.7, 0.4 if metallic > 0.0 else 0.62)
	_materials[key] = mat
	return mat


static func hull(color: Color, metallic := 0.0, roughness := 0.62, crinkle := 0.0, dust := 0.45,
		panel_scale := 5.0) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://world/hull.gdshader")
	mat.set_shader_parameter("albedo", color)
	mat.set_shader_parameter("metallic", metallic)
	mat.set_shader_parameter("roughness", roughness)
	mat.set_shader_parameter("crinkle", crinkle)
	mat.set_shader_parameter("dust", dust)
	mat.set_shader_parameter("panel_scale", panel_scale)
	mat.set_shader_parameter("grime", grime())
	return mat


static func solar_material() -> Material:
	if not _materials.has("solar"):
		var mat := ShaderMaterial.new()
		mat.shader = preload("res://world/solar.gdshader")
		_materials["solar"] = mat
	return _materials["solar"]


## Feuille thermique dorée et froissée (atterrisseur, électrolyseur de CO₂).
static func gold_foil() -> Material:
	if not _materials.has("gold_foil"):
		_materials["gold_foil"] = hull(GOLD, 0.5, 0.38, 1.0, 0.2, 0.0)
	return _materials["gold_foil"]


# ---------- Primitives ----------

static func add(parent: Node3D, mesh: Mesh, pos: Vector3, color: Color, rot := Vector3.ZERO,
		emission := 0.0, metallic := 0.0) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = pos
	node.rotation_degrees = rot
	node.material_override = material(color, emission, metallic)
	parent.add_child(node)
	return node


static func box(parent: Node3D, center: Vector3, size: Vector3, color: Color, rot := Vector3.ZERO,
		emission := 0.0, metallic := 0.0) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return add(parent, mesh, center, color, rot, emission, metallic)


static func cylinder(parent: Node3D, center: Vector3, radius: float, height: float, color: Color,
		rot := Vector3.ZERO, top_radius := -1.0, sides := 18) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = radius
	mesh.top_radius = radius if top_radius < 0.0 else top_radius
	mesh.height = height
	mesh.radial_segments = sides
	mesh.rings = 1
	return add(parent, mesh, center, color, rot)


static func sphere(parent: Node3D, center: Vector3, radius: float, color: Color, scale := Vector3.ONE,
		emission := 0.0, hemisphere := false, segments := 24) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * (1.0 if hemisphere else 2.0)
	mesh.is_hemisphere = hemisphere
	mesh.radial_segments = segments
	mesh.rings = segments / 2
	var node := add(parent, mesh, center, color, Vector3.ZERO, emission)
	node.scale = scale
	return node


## Barre entre deux points (montants, entretoises, rampes).
static func strut(parent: Node3D, from: Vector3, to: Vector3, radius: float, color: Color) -> MeshInstance3D:
	var node := cylinder(parent, (from + to) / 2.0, radius, from.distance_to(to), color, Vector3.ZERO, -1.0, 8)
	node.basis = Basis(Quaternion(Vector3.UP, (to - from).normalized()))
	return node


static func light(parent: Node3D, pos: Vector3, color: Color, radius := 0.03, energy := 3.0) -> MeshInstance3D:
	var node := sphere(parent, pos, radius, color, Vector3.ONE, energy, false, 8)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


# ---------- Modules ----------

## Modèle d'un module de la colonie (identifiant de ColonyContent).
static func building(building_id: String) -> Node3D:
	var root := Node3D.new()
	root.name = building_id
	match building_id:
		"lander": _lander(root)
		"link": _link(root)
		"solar": _solar(root)
		"habitat": _habitat(root)
		"moxie": _moxie(root)
		"battery": _battery(root)
		"extractor": _extractor(root)
		"greenhouse": _greenhouse(root)
		"electrolyser": _electrolyser(root)
	return root


static func _pad(r: Node3D, size: float) -> void:
	box(r, Vector3(0, 0.035, 0), Vector3(size, 0.07, size), CONCRETE)
	# Bordure de dalles, un peu plus sombre.
	for side in [-1.0, 1.0]:
		box(r, Vector3(side * (size / 2.0 - 0.03), 0.075, 0), Vector3(0.06, 0.02, size), Color("#857767"))
		box(r, Vector3(0, 0.075, side * (size / 2.0 - 0.03)), Vector3(size, 0.02, 0.06), Color("#857767"))


static func _lander(r: Node3D) -> void:
	_pad(r, 1.9)
	# Pieds, jambes et entretoises.
	for angle in [45.0, 135.0, 225.0, 315.0]:
		var dir := Vector3(cos(deg_to_rad(angle)), 0, sin(deg_to_rad(angle)))
		strut(r, dir * 0.45 + Vector3(0, 0.62, 0), dir * 0.78 + Vector3(0, 0.1, 0), 0.035, GREY)
		strut(r, dir * 0.3 + Vector3(0, 0.5, 0), dir * 0.7 + Vector3(0, 0.15, 0), 0.02, DARK)
		cylinder(r, dir * 0.8 + Vector3(0, 0.1, 0), 0.12, 0.04, DARK, Vector3.ZERO, 0.09)
	# Tuyères sous la caisse.
	for k in 3:
		var a := k * TAU / 3.0
		cylinder(r, Vector3(cos(a) * 0.18, 0.42, sin(a) * 0.18), 0.09, 0.18, DARK, Vector3.ZERO, 0.05, 12)
	# Caisse octogonale en feuille dorée, pont supérieur blanc.
	var body := cylinder(r, Vector3(0, 0.82, 0), 0.56, 0.62, GOLD, Vector3.ZERO, 0.52, 8)
	body.material_override = gold_foil()
	cylinder(r, Vector3(0, 1.16, 0), 0.54, 0.06, DARK, Vector3.ZERO, -1.0, 8)
	cylinder(r, Vector3(0, 1.34, 0), 0.42, 0.32, WHITE, Vector3.ZERO, 0.32, 8)
	cylinder(r, Vector3(0, 1.52, 0), 0.32, 0.05, GREY, Vector3.ZERO, -1.0, 8)
	# Propulseurs d'attitude.
	for angle in [0.0, 90.0, 180.0, 270.0]:
		var dir := Vector3(cos(deg_to_rad(angle)), 0, sin(deg_to_rad(angle)))
		box(r, dir * 0.58 + Vector3(0, 1.05, 0), Vector3(0.08, 0.08, 0.08), DARK, Vector3(0, -angle, 0))
	# Ailes solaires sur bras.
	for side in [-1.0, 1.0]:
		strut(r, Vector3(side * 0.45, 1.3, 0), Vector3(side * 0.7, 1.32, 0), 0.025, GREY)
		var wing := box(r, Vector3(side * 1.02, 1.32, 0), Vector3(0.62, 0.035, 0.5), BLUE, Vector3(0, 0, side * 12.0))
		wing.material_override = solar_material()
		box(r, Vector3(side * 1.02, 1.3, 0), Vector3(0.66, 0.02, 0.54), GREY, Vector3(0, 0, side * 12.0))
	# Antenne parabolique.
	cylinder(r, Vector3(0.12, 1.66, 0.1), 0.02, 0.24, GREY, Vector3.ZERO, -1.0, 8)
	sphere(r, Vector3(0.12, 1.8, 0.1), 0.17, WHITE, Vector3(1, 0.32, 1), 0.0, true)
	strut(r, Vector3(0.12, 1.8, 0.1), Vector3(0.12, 1.95, 0.1), 0.008, DARK)
	light(r, Vector3(-0.2, 1.58, -0.15), Color("#ff6f61"), 0.025)
	# Échelle et écoutille.
	for side in [-0.07, 0.07]:
		strut(r, Vector3(side, 0.08, 0.72), Vector3(side, 0.85, 0.55), 0.012, GREY)
	for k in 5:
		var t := (k + 1) / 6.0
		var p := Vector3(0, 0.08, 0.72).lerp(Vector3(0, 0.85, 0.55), t)
		box(r, p, Vector3(0.15, 0.012, 0.02), GREY)
	box(r, Vector3(0, 0.85, 0.53), Vector3(0.24, 0.28, 0.04), DARK)
	sphere(r, Vector3(0, 0.9, 0.555), 0.05, WARM_LIGHT, Vector3(1, 1, 0.3), 1.5, false, 12)


static func _link(r: Node3D) -> void:
	box(r, Vector3(0, 0.025, 0), Vector3(0.42, 0.05, 0.42), CONCRETE)
	box(r, Vector3(0, 0.3, 0), Vector3(0.42, 0.5, 0.42), Color(0.72, 0.9, 1.0, 0.32))
	box(r, Vector3(0, 0.565, 0), Vector3(0.44, 0.03, 0.08), WHITE)


static func _solar(r: Node3D) -> void:
	cylinder(r, Vector3(0, 0.03, 0), 0.12, 0.06, CONCRETE)
	cylinder(r, Vector3(0, 0.27, 0), 0.035, 0.48, GREY, Vector3.ZERO, -1.0, 10)
	box(r, Vector3(0, 0.5, 0), Vector3(0.12, 0.06, 0.1), DARK)
	var frame := Node3D.new()
	frame.position = Vector3(0, 0.56, 0)
	frame.rotation_degrees = Vector3(-24, 0, 0)
	r.add_child(frame)
	box(frame, Vector3(0, -0.02, 0), Vector3(0.94, 0.02, 0.84), GREY)
	var panel := box(frame, Vector3(0, 0.01, 0), Vector3(0.9, 0.035, 0.8), BLUE)
	panel.material_override = solar_material()
	box(frame, Vector3(0.38, -0.04, -0.3), Vector3(0.1, 0.04, 0.08), DARK)


static func _habitat(r: Node3D) -> void:
	_pad(r, 1.9)
	cylinder(r, Vector3(0, 0.18, 0), 0.86, 0.2, GREY, Vector3.ZERO, -1.0, 32)
	cylinder(r, Vector3(0, 0.29, 0), 0.84, 0.04, DARK, Vector3.ZERO, -1.0, 32)
	sphere(r, Vector3(0, 0.3, 0), 0.82, WHITE, Vector3(1, 0.86, 1), 0.0, true, 32)
	# Côtes de renfort du dôme gonflable.
	for k in 6:
		var a := k * TAU / 6.0
		for i in 5:
			var t0 := i / 5.0 * PI / 2.0
			var t1 := (i + 1) / 5.0 * PI / 2.0
			var p0 := Vector3(cos(a) * cos(t0) * 0.83, 0.3 + sin(t0) * 0.71, sin(a) * cos(t0) * 0.83)
			var p1 := Vector3(cos(a) * cos(t1) * 0.83, 0.3 + sin(t1) * 0.71, sin(a) * cos(t1) * 0.83)
			strut(r, p0, p1, 0.018, Color("#d6d4cc"))
	for k in 5:
		var a := k * TAU / 5.0 + 0.3
		sphere(r, Vector3(cos(a) * 0.68, 0.62, sin(a) * 0.68), 0.075, WARM_LIGHT, Vector3(1, 0.65, 1), 1.6, false, 12)
	# Sas cylindrique avec porte et marches.
	cylinder(r, Vector3(0, 0.32, 0.86), 0.2, 0.42, WHITE, Vector3(90, 0, 0), -1.0, 16)
	cylinder(r, Vector3(0, 0.32, 1.07), 0.21, 0.03, DARK, Vector3(90, 0, 0), -1.0, 16)
	box(r, Vector3(0, 0.3, 1.085), Vector3(0.18, 0.26, 0.01), Color("#5a6470"))
	light(r, Vector3(0.14, 0.48, 1.09), Color("#5be49b"), 0.02)
	for k in 2:
		box(r, Vector3(0, 0.03 + k * 0.05, 1.12 + (1 - k) * 0.06), Vector3(0.3, 0.05, 0.08), CONCRETE)
	# Mât, balise, coffret technique.
	cylinder(r, Vector3(-0.45, 1.0, -0.35), 0.015, 0.45, GREY, Vector3.ZERO, -1.0, 6)
	light(r, Vector3(-0.45, 1.24, -0.35), Color("#ff6f61"), 0.035)
	box(r, Vector3(0.75, 0.2, -0.55), Vector3(0.22, 0.26, 0.26), GREY)
	strut(r, Vector3(0.68, 0.25, -0.42), Vector3(0.55, 0.35, -0.3), 0.02, DARK)


static func _moxie(r: Node3D) -> void:
	_pad(r, 0.95)
	var body := box(r, Vector3(0, 0.36, 0), Vector3(0.56, 0.54, 0.56), GOLD)
	body.material_override = gold_foil()
	box(r, Vector3(0, 0.64, 0), Vector3(0.6, 0.04, 0.6), DARK)
	# Grille d'admission de l'air martien.
	box(r, Vector3(0, 0.38, 0.285), Vector3(0.36, 0.26, 0.02), DARK)
	for k in 5:
		box(r, Vector3(0, 0.28 + k * 0.05, 0.296), Vector3(0.34, 0.012, 0.01), GREY)
	# Ailettes de refroidissement (l'électrolyse se fait vers 800 °C).
	for k in 6:
		box(r, Vector3(0.3, 0.36, -0.2 + k * 0.08), Vector3(0.06, 0.42, 0.012), GREY)
	cylinder(r, Vector3(0.14, 0.82, 0.1), 0.05, 0.32, WHITE, Vector3.ZERO, -1.0, 12)
	cylinder(r, Vector3(0.14, 0.99, 0.1), 0.06, 0.03, DARK, Vector3.ZERO, -1.0, 12)
	strut(r, Vector3(-0.2, 0.45, -0.28), Vector3(-0.2, 0.15, -0.46), 0.03, WHITE)
	light(r, Vector3(-0.18, 0.69, 0.2), LIGHT, 0.03, 2.0)


static func _battery(r: Node3D) -> void:
	_pad(r, 0.95)
	box(r, Vector3(0, 0.3, 0), Vector3(0.76, 0.44, 0.56), Color("#5a6470"), Vector3.ZERO, 0.0, 0.4)
	for k in 7:
		box(r, Vector3(-0.33 + k * 0.11, 0.3, 0.29), Vector3(0.03, 0.4, 0.02), Color("#4a525c"))
	box(r, Vector3(0, 0.46, 0.295), Vector3(0.7, 0.04, 0.02), Color("#5be49b"), Vector3.ZERO, 1.4)
	box(r, Vector3(0, 0.54, 0), Vector3(0.78, 0.04, 0.58), DARK)
	for k in 2:
		cylinder(r, Vector3(-0.2 + k * 0.4, 0.6, -0.1), 0.05, 0.08, GREY, Vector3.ZERO, -1.0, 10)
	strut(r, Vector3(0.38, 0.2, -0.2), Vector3(0.47, 0.06, -0.3), 0.025, DARK)


static func _extractor(r: Node3D) -> void:
	_pad(r, 1.9)
	# Derrick de forage à treillis.
	var top := Vector3(0, 1.8, -0.25)
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		strut(r, Vector3(corner.x * 0.34, 0.08, corner.y * 0.34 - 0.25), Vector3(corner.x * 0.08, 1.75, corner.y * 0.08 - 0.25), 0.03, ORANGE)
	for k in 4:
		var y := 0.4 + k * 0.35
		var w := 0.34 - (y - 0.08) / 1.67 * 0.26
		for edge in [[Vector2(-1, -1), Vector2(1, -1)], [Vector2(1, -1), Vector2(1, 1)], [Vector2(1, 1), Vector2(-1, 1)], [Vector2(-1, 1), Vector2(-1, -1)]]:
			strut(r, Vector3(edge[0].x * w, y, edge[0].y * w - 0.25), Vector3(edge[1].x * w, y, edge[1].y * w - 0.25), 0.012, ORANGE)
	box(r, top, Vector3(0.28, 0.12, 0.28), DARK)
	light(r, top + Vector3(0, 0.1, 0), Color("#ff6f61"), 0.03)
	cylinder(r, Vector3(0, 0.6, -0.25), 0.045, 1.2, GREY, Vector3.ZERO, -1.0, 10)
	cylinder(r, Vector3(0, 0.12, -0.25), 0.16, 0.1, DARK, Vector3.ZERO, -1.0, 16)
	# Réservoir d'eau isolé, bandes de repérage.
	cylinder(r, Vector3(0.45, 0.45, 0.45), 0.32, 0.74, Color("#e2e9ee"), Vector3.ZERO, -1.0, 24)
	for y in [0.2, 0.7]:
		cylinder(r, Vector3(0.45, y, 0.45), 0.325, 0.04, BLUE, Vector3.ZERO, -1.0, 24)
	sphere(r, Vector3(0.45, 0.82, 0.45), 0.32, Color("#e2e9ee"), Vector3(1, 0.3, 1), 0.0, true)
	# Fondoir et conduite chauffée.
	box(r, Vector3(-0.45, 0.24, 0.45), Vector3(0.5, 0.34, 0.5), WHITE)
	box(r, Vector3(-0.45, 0.42, 0.45), Vector3(0.52, 0.03, 0.52), DARK)
	strut(r, Vector3(-0.2, 0.3, 0.45), Vector3(0.14, 0.3, 0.45), 0.04, BLUE)
	strut(r, Vector3(0, 0.25, -0.12), Vector3(-0.35, 0.25, 0.2), 0.035, ORANGE)
	light(r, Vector3(-0.3, 0.38, 0.71), LIGHT, 0.025)


static func _greenhouse(r: Node3D) -> void:
	_pad(r, 1.9)
	box(r, Vector3(0, 0.12, 0), Vector3(1.7, 0.1, 1.7), Color("#5a3c28"))
	# Rangées de cultures : radis, cresson, tomates (cf. expériences de Wageningen).
	for row in 3:
		var z := -0.5 + row * 0.5
		box(r, Vector3(0, 0.19, z), Vector3(1.5, 0.05, 0.3), Color("#3d2a1c"))
		for k in 6:
			var x := -0.62 + k * 0.25
			var tone := GREEN if (k + row) % 2 == 0 else DARK_GREEN
			sphere(r, Vector3(x, 0.28, z), 0.1, tone, Vector3(1, 0.8, 1), 0.0, false, 10)
			if row == 1 and k % 2 == 0:
				sphere(r, Vector3(x + 0.05, 0.33, z + 0.06), 0.035, RED, Vector3.ONE, 0.0, false, 8)
	# Voûte vitrée sur arceaux blancs.
	var vault := cylinder(r, Vector3(0, 0.15, 0), 0.86, 1.78, Color(0.72, 0.95, 0.88, 0.28), Vector3(0, 0, 90), -1.0, 28)
	vault.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for k in 5:
		var x := -0.85 + k * 0.425
		for i in 8:
			var a0 := i / 8.0 * PI
			var a1 := (i + 1) / 8.0 * PI
			strut(r, Vector3(x, 0.15 + sin(a0) * 0.86, cos(a0) * 0.86), Vector3(x, 0.15 + sin(a1) * 0.86, cos(a1) * 0.86), 0.022, WHITE)
	strut(r, Vector3(-0.88, 1.01, 0), Vector3(0.88, 1.01, 0), 0.025, WHITE)
	# Rampes de lampes de culture (lumière rose : rouge + bleu, ce qu'absorbe la chlorophylle).
	for z in [-0.3, 0.3]:
		box(r, Vector3(0, 0.82, z), Vector3(1.3, 0.04, 0.06), Color("#ff7ad9"), Vector3.ZERO, 1.8)


static func _electrolyser(r: Node3D) -> void:
	_pad(r, 0.95)
	# Réservoir d'oxygène (blanc) et d'hydrogène (bleu), cerclés.
	cylinder(r, Vector3(-0.2, 0.42, 0.05), 0.17, 0.62, WHITE, Vector3.ZERO, -1.0, 20)
	sphere(r, Vector3(-0.2, 0.73, 0.05), 0.17, WHITE, Vector3.ONE, 0.0, true, 20)
	cylinder(r, Vector3(-0.2, 0.3, 0.05), 0.175, 0.03, LIGHT.darkened(0.3))
	cylinder(r, Vector3(0.2, 0.36, 0.12), 0.13, 0.5, Color("#8fb8e8"), Vector3.ZERO, -1.0, 20)
	sphere(r, Vector3(0.2, 0.61, 0.12), 0.13, Color("#8fb8e8"), Vector3.ONE, 0.0, true, 20)
	cylinder(r, Vector3(0.2, 0.3, 0.12), 0.135, 0.03, BLUE)
	# Cellule d'électrolyse et tuyauterie.
	box(r, Vector3(0.05, 0.2, -0.28), Vector3(0.6, 0.24, 0.24), DARK)
	strut(r, Vector3(-0.2, 0.25, -0.18), Vector3(-0.2, 0.25, -0.09), 0.03, GREY)
	strut(r, Vector3(0.2, 0.25, -0.18), Vector3(0.2, 0.25, 0.0), 0.03, GREY)
	cylinder(r, Vector3(0.3, 0.36, -0.28), 0.04, 0.02, RED, Vector3(90, 0, 0), -1.0, 10)
	light(r, Vector3(-0.1, 0.27, -0.405), LIGHT, 0.022, 2.5)


# ---------- Personnages et véhicules ----------

static func capsule() -> Node3D:
	var r := Node3D.new()
	cylinder(r, Vector3(0, 0.45, 0), 0.45, 0.7, WHITE, Vector3.ZERO, 0.22, 24)
	cylinder(r, Vector3(0, 0.08, 0), 0.47, 0.1, Color("#3a2a24"), Vector3.ZERO, -1.0, 24)
	cylinder(r, Vector3(0, 0.85, 0), 0.22, 0.12, DARK)
	box(r, Vector3(0, 0.5, 0.36), Vector3(0.16, 0.16, 0.02), BLUE)
	var flame := cylinder(r, Vector3(0, -0.35, 0), 0.25, 0.7, Color("#ffb347"), Vector3(180, 0, 0), 0.0, 10)
	flame.material_override = material(Color("#ffb347"), 3.0)
	flame.name = "Flame"
	return r


static func rocket() -> Node3D:
	var r := Node3D.new()
	cylinder(r, Vector3(0, 0.6, 0), 0.16, 1.0, WHITE)
	cylinder(r, Vector3(0, 1.25, 0), 0.16, 0.3, RED, Vector3.ZERO, 0.0)
	for angle in [0, 120, 240]:
		var dir := Vector3(cos(deg_to_rad(angle)), 0, sin(deg_to_rad(angle)))
		box(r, dir * 0.18 + Vector3(0, 0.2, 0), Vector3(0.04, 0.3, 0.16), RED, Vector3(0, -angle, 0))
	var flame := cylinder(r, Vector3(0, -0.15, 0), 0.12, 0.4, Color("#ffb347"), Vector3(180, 0, 0), 0.0, 10)
	flame.material_override = material(Color("#ffb347"), 3.0)
	return r


## Rocher facetté (peu de segments, échelle irrégulière).
static func rock(rng: RandomNumberGenerator, color := ROCK) -> Node3D:
	var r := Node3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = rng.randf_range(0.14, 0.34)
	mesh.height = mesh.radius * 2.0
	mesh.radial_segments = 7
	mesh.rings = 4
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = rock_material(color)
	node.scale = Vector3(rng.randf_range(0.9, 1.5), rng.randf_range(0.45, 0.8), rng.randf_range(0.8, 1.4))
	node.rotation = Vector3(rng.randf_range(-0.3, 0.3), rng.randf() * TAU, rng.randf_range(-0.3, 0.3))
	r.add_child(node)
	return r


static func rock_material(color := ROCK) -> Material:
	var key := "rock|" + color.to_html()
	if not _materials.has(key):
		_materials[key] = hull(color, 0.0, 0.95, 0.6, 0.55, 0.0)
	return _materials[key]


## Fusionne toutes les pièces d'un modèle en un seul maillage (une surface par matériau) :
## bien moins d'objets à dessiner, ce qui compte beaucoup sur téléphone.
## Les pièces transparentes forment un second maillage, qui ne projette pas d'ombre.
static func bake(root: Node3D) -> Node3D:
	var tools := {}
	var order: Array[Material] = []
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var part: MeshInstance3D = node
		if part.name == "Flame" or part.mesh == null:
			continue
		var mat: Material = part.material_override
		if not tools.has(mat):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			tools[mat] = st
			order.append(mat)
		tools[mat].append_from(part.mesh, 0, _relative_transform(root, part))
	var baked := Node3D.new()
	baked.name = root.name
	baked.transform = root.transform
	var opaque := ArrayMesh.new()
	var clear := ArrayMesh.new()
	for mat in order:
		var target := clear if mat is BaseMaterial3D and (mat as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED else opaque
		tools[mat].commit(target)
		target.surface_set_material(target.get_surface_count() - 1, mat)
	for mesh in [opaque, clear]:
		if mesh.get_surface_count() == 0:
			continue
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		if mesh == clear:
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		baked.add_child(instance)
	root.free()
	return baked


static func _relative_transform(root: Node3D, node: Node3D) -> Transform3D:
	var t := node.transform
	var parent := node.get_parent()
	while parent != null and parent != root:
		t = (parent as Node3D).transform * t
		parent = parent.get_parent()
	return t


## Remplace tous les matériaux d'un modèle par un matériau transparent (fantôme de placement).
static func make_ghost(root: Node, color: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_apply_material(root, mat)


static func _apply_material(node: Node, mat: Material) -> void:
	if node is GeometryInstance3D:
		node.material_override = mat
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_apply_material(child, mat)
