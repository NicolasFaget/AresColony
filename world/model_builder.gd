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
## Copies de matériaux qui ne diffèrent que par un paramètre (lampes éteintes, poussière des panneaux).
static var _variants := {}
## Graphismes fluides : shaders légers (lumière calculée aux sommets), voir set_lite.
static var lite := false
const LITE_SHADERS := {
	"res://world/terrain.gdshader": "res://world/terrain_lite.gdshader",
	"res://world/hull.gdshader": "res://world/hull_lite.gdshader",
	"res://world/solar.gdshader": "res://world/solar_lite.gdshader",
}
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
	if emission > 0.0 and color.a >= 1.0:
		# Lampe : sa lueur suit l'activité du module (paramètre d'instance « lit », voir lamp.gdshader).
		var lamp := ShaderMaterial.new()
		lamp.shader = preload("res://world/lamp.gdshader")
		lamp.set_shader_parameter("color", color)
		lamp.set_shader_parameter("energy", emission)
		# Balises rouges des mâts : elles clignotent.
		lamp.set_shader_parameter("blink", color == Color("#ff6f61"))
		mat = lamp
	elif color.a < 1.0 or emission > 0.0:
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


## Le shader demandé, ou sa version légère en graphismes fluides.
static func shader(path: String) -> Shader:
	return load(LITE_SHADERS[path] if lite and LITE_SHADERS.has(path) else path)


## Passe tous les matériaux déjà créés (et ceux à venir) en version légère, ou l'inverse.
static func set_lite(on: bool, extra: Array[ShaderMaterial] = []) -> void:
	lite = on
	var all: Array = _materials.values() + _variants.values() + extra
	for mat: Variant in all:
		if not mat is ShaderMaterial or (mat as ShaderMaterial).shader == null:
			continue
		var path := (mat as ShaderMaterial).shader.resource_path
		for normal: String in LITE_SHADERS:
			if path == normal or path == LITE_SHADERS[normal]:
				(mat as ShaderMaterial).shader = shader(normal)


## Copie du matériau avec un paramètre changé (gardée en cache : une copie par valeur).
static func variant(base: ShaderMaterial, param: String, value: Variant) -> ShaderMaterial:
	var key := "%d|%s|%s" % [base.get_instance_id(), param, value]
	if not _variants.has(key):
		var copy: ShaderMaterial = base.duplicate()
		copy.set_shader_parameter(param, value)
		_variants[key] = copy
	return _variants[key]


## Dans tout le sous-arbre, remplace chaque surface qui utilise ce shader (« lamp », « solar »…)
## par sa variante avec `param` = `value`. Le matériau d'origine reste celui du maillage.
static func set_surface_param(root: Node, shader_name: String, param: String, value: Variant) -> void:
	var meshes: Array[Node] = root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		meshes.append(root)
	for node in meshes:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		for s in mesh_instance.mesh.get_surface_count():
			var base := mesh_instance.mesh.surface_get_material(s) as ShaderMaterial
			if base != null and base.shader != null and base.shader.resource_path.get_file().begins_with(shader_name):
				mesh_instance.set_surface_override_material(s, variant(base, param, value))


static func hull(color: Color, metallic := 0.0, roughness := 0.62, crinkle := 0.0, dust := 0.45,
		panel_scale := 5.0) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = shader("res://world/hull.gdshader")
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
		mat.shader = shader("res://world/solar.gdshader")
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
		"kiln": _kiln(root)
		"sabatier": _sabatier(root)
		"tank": _tank(root)
		"garage": _garage(root, true)
		"garage_empty": _garage(root, false)
		"erv": _erv(root)
		"bunker": _bunker(root)
		"spaceport": _spaceport(root)
		"brine": _brine(root)
		"methane_pump": _methane_pump(root)
		"reactor": _reactor(root)
		"biodome": _biodome(root)
		"dome": _dome(root)
		"n2_compressor": _n2_compressor(root)
		"cryobot": _cryobot(root)
		"plume_trap": _plume_trap(root)
		"warehouse": _warehouse(root)
		"lab": _lab(root)
		"recycler": _recycler(root)
		"medbay": _medbay(root)
		"rtg": _rtg(root)
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
	# Antenne parabolique, qui balaie lentement le ciel.
	cylinder(r, Vector3(0.12, 1.66, 0.1), 0.02, 0.24, GREY, Vector3.ZERO, -1.0, 8)
	var dish := Node3D.new()
	dish.name = "RotorSpin"
	dish.position = Vector3(0.12, 1.8, 0.1)
	r.add_child(dish)
	var bowl := sphere(dish, Vector3(0.03, 0, 0), 0.17, WHITE, Vector3(1, 0.32, 1), 0.0, true)
	bowl.rotation_degrees = Vector3(0, 0, 28)
	strut(dish, Vector3(0.03, 0, 0), Vector3(-0.04, 0.14, 0), 0.008, DARK)
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
	# Cadre orientable : il suit le soleil (voir ColonyWorld), à plat la nuit, replié en tempête.
	var frame := Node3D.new()
	frame.name = "RotorSun"
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


## Réacteur Sabatier : colonne de réaction, électrolyseur, réservoirs de méthane et tuyauterie.
static func _sabatier(r: Node3D) -> void:
	_pad(r, 1.9)
	var methane := Color("#e98a5a")
	cylinder(r, Vector3(-0.35, 0.6, -0.3), 0.2, 1.05, WHITE, Vector3.ZERO, -1.0, 20)
	sphere(r, Vector3(-0.35, 1.12, -0.3), 0.2, WHITE, Vector3.ONE, 0.0, true, 20)
	for y in [0.3, 0.6, 0.9]:
		cylinder(r, Vector3(-0.35, y, -0.3), 0.205, 0.03, GREY, Vector3.ZERO, -1.0, 20)
	box(r, Vector3(0.3, 0.28, -0.35), Vector3(0.6, 0.4, 0.4), DARK)
	light(r, Vector3(0.3, 0.42, -0.14), LIGHT, 0.03, 2.0)
	for k in 2:
		var at := Vector3(-0.3 + k * 0.6, 0.0, 0.45)
		cylinder(r, at + Vector3(0, 0.3, 0), 0.04, 0.44, GREY, Vector3.ZERO, -1.0, 8)
		sphere(r, at + Vector3(0, 0.62, 0), 0.24, methane, Vector3.ONE, 0.0, false, 20)
		cylinder(r, at + Vector3(0, 0.62, 0), 0.245, 0.04, WHITE, Vector3.ZERO, -1.0, 20)
	strut(r, Vector3(-0.15, 0.9, -0.3), Vector3(0.3, 0.5, -0.35), 0.03, GREY)
	strut(r, Vector3(-0.35, 0.3, -0.1), Vector3(-0.3, 0.45, 0.25), 0.03, GREY)
	strut(r, Vector3(0.3, 0.2, -0.15), Vector3(0.3, 0.45, 0.25), 0.03, GREY)


## Réservoir de méthane : sphère isolée sur pieds.
static func _tank(r: Node3D) -> void:
	_pad(r, 0.95)
	for angle in [45.0, 135.0, 225.0, 315.0]:
		var dir := Vector3(cos(deg_to_rad(angle)), 0, sin(deg_to_rad(angle)))
		strut(r, dir * 0.3 + Vector3(0, 0.07, 0), dir * 0.18 + Vector3(0, 0.4, 0), 0.025, GREY)
	sphere(r, Vector3(0, 0.55, 0), 0.3, Color("#e98a5a"), Vector3.ONE, 0.0, false, 24)
	cylinder(r, Vector3(0, 0.55, 0), 0.305, 0.05, WHITE, Vector3.ZERO, -1.0, 24)
	light(r, Vector3(0, 0.88, 0), LIGHT, 0.025, 2.0)


## Garage à rovers : hangar à toit voûté ; le rover est garé devant, sauf pendant une expédition.
static func _garage(r: Node3D, with_rover: bool) -> void:
	_pad(r, 1.9)
	box(r, Vector3(0, 0.35, -0.35), Vector3(1.5, 0.6, 0.9), WHITE)
	cylinder(r, Vector3(0, 0.65, -0.35), 0.45, 1.5, LIGHT.darkened(0.6), Vector3(0, 0, 90), -1.0, 16)
	box(r, Vector3(0, 0.3, 0.105), Vector3(0.8, 0.5, 0.02), DARK)
	for k in 4:
		box(r, Vector3(0, 0.12 + k * 0.12, 0.118), Vector3(0.78, 0.015, 0.01), GREY)
	light(r, Vector3(0.5, 0.58, 0.11), WARM_LIGHT, 0.03, 2.0)
	if with_rover:
		var parked := rover()
		parked.position = Vector3(0.1, 0.0, 0.5)
		r.add_child(parked)


## Rover pressurisé à six roues (avant vers +X).
static func rover() -> Node3D:
	var r := Node3D.new()
	box(r, Vector3(0, 0.28, 0), Vector3(0.7, 0.22, 0.34), WHITE)
	box(r, Vector3(0.28, 0.33, 0), Vector3(0.14, 0.14, 0.3), Color(0.35, 0.6, 0.7))
	box(r, Vector3(0, 0.4, 0), Vector3(0.5, 0.03, 0.3), Color("#e98a5a"))
	for x in [-0.25, 0.0, 0.25]:
		for z in [-0.19, 0.19]:
			cylinder(r, Vector3(x, 0.11, z), 0.09, 0.07, DARK, Vector3(90, 0, 0), -1.0, 12)
	cylinder(r, Vector3(-0.2, 0.5, 0), 0.015, 0.25, GREY, Vector3.ZERO, -1.0, 6)
	box(r, Vector3(-0.2, 0.63, 0), Vector3(0.08, 0.05, 0.12), DARK)
	light(r, Vector3(0.36, 0.3, 0.1), WARM_LIGHT, 0.025, 3.0)
	light(r, Vector3(0.36, 0.3, -0.1), WARM_LIGHT, 0.025, 3.0)
	return r


## Véhicule de retour : la fusée sur son pas de tir, avec bras de remplissage.
static func _erv(r: Node3D) -> void:
	_pad(r, 1.9)
	cylinder(r, Vector3(0, 0.12, 0), 0.62, 0.1, CONCRETE.darkened(0.15), Vector3.ZERO, -1.0, 24)
	var ship := rocket()
	ship.scale = Vector3.ONE * 1.5
	ship.position = Vector3(0, 0.38, 0)
	ship.get_child(ship.get_child_count() - 1).name = "Flame"
	r.add_child(ship)
	# Tour de service et bras de remplissage.
	strut(r, Vector3(0.62, 0.1, -0.5), Vector3(0.62, 2.1, -0.5), 0.05, ORANGE)
	for y in [0.6, 1.1, 1.6]:
		strut(r, Vector3(0.62, y, -0.5), Vector3(0.2, y + 0.1, -0.15), 0.025, ORANGE)
	cylinder(r, Vector3(-0.6, 0.35, 0.55), 0.18, 0.5, Color("#e98a5a"), Vector3.ZERO, -1.0, 16)
	strut(r, Vector3(-0.5, 0.5, 0.45), Vector3(-0.15, 0.7, 0.1), 0.03, GREY)


## Pompe à méthane : derrick bas, conduite plongeant dans le lac, réservoirs isolés givrés.
static func _methane_pump(r: Node3D) -> void:
	_pad(r, 1.9)
	var frost := Color("#dfe8ef")
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		strut(r, Vector3(corner.x * 0.3 - 0.35, 0.08, corner.y * 0.3 - 0.3), Vector3(corner.x * 0.08 - 0.35, 1.1, corner.y * 0.08 - 0.3), 0.03, ORANGE)
	box(r, Vector3(-0.35, 1.15, -0.3), Vector3(0.25, 0.1, 0.25), DARK)
	cylinder(r, Vector3(-0.35, 0.5, -0.3), 0.05, 1.0, GREY, Vector3.ZERO, -1.0, 10)
	for k in 2:
		var at := Vector3(0.35, 0.0, -0.4 + k * 0.6)
		cylinder(r, at + Vector3(0, 0.3, 0), 0.22, 0.5, frost, Vector3(90, 0, 0), -1.0, 18)
		sphere(r, at + Vector3(0, 0.3, 0.25), 0.22, frost, Vector3.ONE, 0.0, true, 16)
	strut(r, Vector3(-0.35, 0.3, -0.3), Vector3(0.35, 0.3, -0.4), 0.03, GREY)
	light(r, Vector3(-0.35, 1.25, -0.3), Color("#ffb347"), 0.035, 2.5)
	box(r, Vector3(-0.4, 0.2, 0.55), Vector3(0.45, 0.3, 0.3), WHITE)
	light(r, Vector3(-0.4, 0.3, 0.71), LIGHT, 0.025, 2.0)


## Raffinerie de saumure : tête de forage, cuves d'évaporation et tas de sel blanc.
static func _brine(r: Node3D) -> void:
	_pad(r, 1.9)
	var salt := Color("#f1efe8")
	strut(r, Vector3(-0.45, 0.1, -0.45), Vector3(-0.45, 1.2, -0.45), 0.06, GREY)
	box(r, Vector3(-0.45, 1.25, -0.45), Vector3(0.3, 0.12, 0.3), DARK)
	cylinder(r, Vector3(-0.45, 0.2, -0.45), 0.22, 0.2, DARK, Vector3.ZERO, -1.0, 16)
	for k in 3:
		var at := Vector3(0.1 + k * 0.32, 0.0, -0.4)
		cylinder(r, at + Vector3(0, 0.12, 0), 0.14, 0.12, WHITE, Vector3.ZERO, -1.0, 16)
		cylinder(r, at + Vector3(0, 0.185, 0), 0.12, 0.01, Color("#9fd2f2"), Vector3.ZERO, -1.0, 16)
	box(r, Vector3(0.35, 0.28, 0.35), Vector3(0.7, 0.4, 0.45), WHITE)
	light(r, Vector3(0.35, 0.4, 0.58), LIGHT, 0.025, 2.0)
	sphere(r, Vector3(-0.4, 0.05, 0.45), 0.35, salt, Vector3(1.0, 0.55, 1.0), 0.0, true, 16)
	sphere(r, Vector3(-0.1, 0.05, 0.6), 0.22, salt, Vector3(1.0, 0.5, 1.0), 0.0, true, 12)
	strut(r, Vector3(-0.45, 0.6, -0.45), Vector3(0.1, 0.3, -0.4), 0.025, GREY)


## Astroport : aire de lancement marquée, fusée sur son socle, tour de service et réservoir.
static func _spaceport(r: Node3D) -> void:
	_pad(r, 1.9)
	cylinder(r, Vector3(0.1, 0.09, 0.1), 0.7, 0.05, CONCRETE.darkened(0.25), Vector3.ZERO, -1.0, 32)
	for k in 8:
		var a := TAU * k / 8.0
		box(r, Vector3(0.1 + cos(a) * 0.6, 0.12, 0.1 + sin(a) * 0.6), Vector3(0.12, 0.01, 0.04), ORANGE, Vector3(0, -rad_to_deg(a), 0), 1.2)
	var ship := rocket()
	ship.scale = Vector3.ONE * 1.25
	ship.position = Vector3(0.1, 0.3, 0.1)
	ship.get_child(ship.get_child_count() - 1).name = "Flame"
	r.add_child(ship)
	strut(r, Vector3(-0.65, 0.1, -0.6), Vector3(-0.65, 1.9, -0.6), 0.05, GREY)
	for y in [0.5, 1.0, 1.5]:
		strut(r, Vector3(-0.65, y, -0.6), Vector3(-0.15, y + 0.1, -0.15), 0.025, GREY)
	light(r, Vector3(-0.65, 1.95, -0.6), Color("#ff6f61"), 0.04, 3.0)
	cylinder(r, Vector3(0.65, 0.35, -0.6), 0.2, 0.55, WHITE, Vector3.ZERO, -1.0, 16)
	box(r, Vector3(0.6, 0.2, 0.7), Vector3(0.45, 0.3, 0.35), WHITE)
	light(r, Vector3(0.6, 0.3, 0.88), LIGHT, 0.025, 2.0)


## Habitat enterré : un tumulus de régolithe, un sas en façade et des puits de lumière.
static func _bunker(r: Node3D) -> void:
	_pad(r, 1.9)
	var soil := Color("#b8714a")
	sphere(r, Vector3(0, 0.05, -0.05), 0.85, soil, Vector3(1.0, 0.55, 1.0), 0.0, true, 24)
	sphere(r, Vector3(-0.35, 0.05, 0.3), 0.45, soil.darkened(0.08), Vector3(1.0, 0.6, 1.0), 0.0, true, 16)
	# Sas d'entrée, voûté.
	box(r, Vector3(0.15, 0.22, 0.72), Vector3(0.42, 0.36, 0.3), WHITE)
	cylinder(r, Vector3(0.15, 0.4, 0.72), 0.21, 0.3, WHITE, Vector3(90, 0, 0), -1.0, 16)
	box(r, Vector3(0.15, 0.2, 0.875), Vector3(0.24, 0.3, 0.02), DARK)
	light(r, Vector3(0.36, 0.42, 0.88), Color("#5be49b"), 0.025, 2.0)
	for at in [Vector3(-0.2, 0.44, -0.2), Vector3(0.3, 0.38, -0.3)]:
		cylinder(r, at, 0.07, 0.12, WHITE, Vector3.ZERO, -1.0, 10)
		cylinder(r, at + Vector3(0, 0.065, 0), 0.06, 0.01, LIGHT, Vector3.ZERO, -1.0, 10)


## Réacteur à fission : cœur cylindrique, moteurs Stirling, grands radiateurs, clôture.
static func _reactor(r: Node3D) -> void:
	_pad(r, 1.9)
	cylinder(r, Vector3(0, 0.45, 0), 0.22, 0.8, GREY, Vector3.ZERO, -1.0, 20)
	cylinder(r, Vector3(0, 0.88, 0), 0.26, 0.08, DARK, Vector3.ZERO, -1.0, 20)
	for angle in [0.0, 90.0, 180.0, 270.0]:
		var dir := Vector3(cos(deg_to_rad(angle)), 0, sin(deg_to_rad(angle)))
		cylinder(r, dir * 0.3 + Vector3(0, 0.75, 0), 0.06, 0.2, GOLD, Vector3.ZERO, -1.0, 10)
	# Radiateurs : ils évacuent la chaleur que les moteurs Stirling ne transforment pas.
	for side in [-1.0, 1.0]:
		box(r, Vector3(side * 0.62, 0.6, 0), Vector3(0.04, 0.9, 1.3), Color("#dfe4ea"), Vector3(0, 0, side * -12.0))
		for k in 5:
			box(r, Vector3(side * 0.6, 0.6, -0.5 + k * 0.25), Vector3(0.05, 0.86, 0.02), GREY, Vector3(0, 0, side * -12.0))
	light(r, Vector3(0, 0.95, 0), Color("#7ff5ea"), 0.04, 2.5)
	for k in 6:
		var x := -0.85 + k * 0.34
		cylinder(r, Vector3(x, 0.15, 0.88), 0.012, 0.16, ORANGE, Vector3.ZERO, -1.0, 6)
	box(r, Vector3(0, 0.2, 0.88), Vector3(1.75, 0.02, 0.01), ORANGE)


## Serre géante : un grand dôme vitré sur un sol vivant, rangs de cultures et arbres fruitiers.
## Grand dôme : coupole vitrée haute, maisons à l'intérieur, sas et cuves d'azote.
static func _dome(r: Node3D) -> void:
	_pad(r, 2.9)
	var nitrogen := Color("#f29bd4")
	for at in [Vector3(-0.5, 0.0, -0.3), Vector3(0.35, 0.0, -0.45), Vector3(0.1, 0.0, 0.4), Vector3(-0.55, 0.0, 0.5)]:
		box(r, at + Vector3(0, 0.25, 0), Vector3(0.38, 0.36, 0.32), WHITE)
		box(r, at + Vector3(0, 0.46, 0), Vector3(0.42, 0.06, 0.36), GREY)
		light(r, at + Vector3(0, 0.28, 0.17), LIGHT, 0.025, 2.0)
	sphere(r, Vector3(0.6, 0.2, 0.25), 0.18, DARK_GREEN, Vector3.ONE, 0.0, false, 12)
	var glass := sphere(r, Vector3(0, 0.1, 0), 1.35, GLASS, Vector3(1.0, 0.9, 1.0), 0.0, true, 32)
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var frame := Node3D.new()
	frame.position = Vector3(0, 0.1, 0)
	frame.scale = Vector3(1.0, 0.9, 1.0)
	r.add_child(frame)
	for angle in [0.0, 60.0, 120.0]:
		var arch := TorusMesh.new()
		arch.inner_radius = 1.33
		arch.outer_radius = 1.37
		arch.rings = 32
		arch.ring_segments = 4
		add(frame, arch, Vector3.ZERO, WHITE, Vector3(90, angle, 0))
	box(r, Vector3(1.3, 0.25, 0.0), Vector3(0.3, 0.32, 0.32), WHITE)
	for k in 2:
		cylinder(r, Vector3(1.25, 0.2, -1.1 + k * 0.3), 0.11, 0.4, nitrogen, Vector3.ZERO, -1.0, 12)


## Compresseur d'azote : prise d'air, colonne de séparation et réservoirs roses.
static func _n2_compressor(r: Node3D) -> void:
	_pad(r, 1.9)
	var nitrogen := Color("#f29bd4")
	box(r, Vector3(-0.35, 0.3, -0.3), Vector3(0.6, 0.45, 0.5), WHITE)
	for k in 3:
		cylinder(r, Vector3(-0.55 + k * 0.2, 0.62, -0.3), 0.07, 0.2, DARK, Vector3.ZERO, -1.0, 10)
	cylinder(r, Vector3(0.45, 0.6, -0.4), 0.12, 1.1, GREY, Vector3.ZERO, -1.0, 14)
	sphere(r, Vector3(0.45, 1.15, -0.4), 0.12, GREY, Vector3.ONE, 0.0, false, 12)
	for k in 2:
		var at := Vector3(-0.3 + k * 0.6, 0.0, 0.45)
		cylinder(r, at + Vector3(0, 0.22, 0), 0.2, 0.44, nitrogen, Vector3(0, 0, 90), -1.0, 16)
	strut(r, Vector3(-0.05, 0.3, -0.3), Vector3(0.45, 0.3, -0.4), 0.03, GREY)
	strut(r, Vector3(0.45, 0.2, -0.3), Vector3(0.3, 0.22, 0.45), 0.03, GREY)
	light(r, Vector3(-0.35, 0.4, -0.04), LIGHT, 0.025, 2.0)


## Collecteur de panache : une grande voile froide sur deux mâts, où se collent les grains des geysers.
static func _plume_trap(r: Node3D) -> void:
	_pad(r, 1.9)
	for x in [-0.6, 0.6]:
		strut(r, Vector3(x, 0, 0), Vector3(x, 1.7, 0), 0.04, GREY)
	box(r, Vector3(0, 1.05, 0), Vector3(1.2, 1.1, 0.04), Color(0.75, 0.88, 0.95))
	box(r, Vector3(0, 0.45, 0), Vector3(1.25, 0.06, 0.12), GREY)
	cylinder(r, Vector3(0.55, 0.22, 0.55), 0.18, 0.44, WHITE, Vector3.ZERO, -1.0, 14)
	box(r, Vector3(-0.5, 0.18, 0.55), Vector3(0.5, 0.36, 0.35), WHITE)
	light(r, Vector3(0, 1.75, 0), RED, 0.03, 2.0)
	light(r, Vector3(-0.5, 0.4, 0.75), LIGHT, 0.04, 2.0)


## Sonde cryobot : un derrick qui descend une sonde chauffée dans un puits de glace fondue.
static func _cryobot(r: Node3D) -> void:
	_pad(r, 1.9)
	cylinder(r, Vector3(0, 0.03, 0), 0.32, 0.06, Color("#1d3550"), Vector3.ZERO, -1.0, 20)
	for corner in [Vector3(-0.45, 0, -0.45), Vector3(0.45, 0, -0.45), Vector3(-0.45, 0, 0.45), Vector3(0.45, 0, 0.45)]:
		strut(r, corner, Vector3(0, 1.5, 0), 0.04, GREY)
	box(r, Vector3(0, 1.5, 0), Vector3(0.3, 0.12, 0.3), WHITE)
	cylinder(r, Vector3(0, 0.95, 0), 0.015, 1.1, DARK, Vector3.ZERO, -1.0, 6)
	cylinder(r, Vector3(0, 0.45, 0), 0.07, 0.3, ORANGE, Vector3.ZERO, -1.0, 12)
	box(r, Vector3(0.7, 0.25, -0.55), Vector3(0.45, 0.4, 0.4), WHITE)
	cylinder(r, Vector3(-0.65, 0.2, 0.6), 0.16, 0.4, GREY, Vector3.ZERO, -1.0, 14)
	light(r, Vector3(0, 0.08, 0), LIGHT, 0.06, 3.0)
	light(r, Vector3(0, 1.6, 0), RED, 0.03, 2.0)


static func _biodome(r: Node3D) -> void:
	_pad(r, 2.9)
	cylinder(r, Vector3(0, 0.1, 0), 1.3, 0.06, Color("#5a3b26"), Vector3.ZERO, -1.0, 32)
	for row in 5:
		for k in 7:
			var at := Vector3(-0.9 + k * 0.3, 0.17, -0.8 + row * 0.4)
			if at.length() < 1.15:
				sphere(r, at, 0.1, GREEN if (row + k) % 2 == 0 else DARK_GREEN, Vector3(1.0, 0.8, 1.0), 0.0, false, 8)
	for at in [Vector3(-0.4, 0.0, 0.3), Vector3(0.45, 0.0, -0.25)]:
		cylinder(r, at + Vector3(0, 0.3, 0), 0.03, 0.4, Color("#6b4a2f"), Vector3.ZERO, -1.0, 8)
		sphere(r, at + Vector3(0, 0.6, 0), 0.2, DARK_GREEN, Vector3.ONE, 0.0, false, 12)
	var dome := sphere(r, Vector3(0, 0.1, 0), 1.35, GLASS, Vector3(1.0, 0.75, 1.0), 0.0, true, 32)
	dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Armature : arceaux et anneaux (tores dans un repère aplati comme le dôme).
	var frame := Node3D.new()
	frame.position = Vector3(0, 0.1, 0)
	frame.scale = Vector3(1.0, 0.75, 1.0)
	r.add_child(frame)
	for angle in [0.0, 45.0, 90.0, 135.0]:
		var arch := TorusMesh.new()
		arch.inner_radius = 1.33
		arch.outer_radius = 1.37
		arch.rings = 32
		arch.ring_segments = 4
		add(frame, arch, Vector3.ZERO, WHITE, Vector3(90, angle, 0))
	for h in [0.45, 0.9]:
		var ring := TorusMesh.new()
		var radius := sqrt(1.35 * 1.35 - h * h)
		ring.inner_radius = radius - 0.02
		ring.outer_radius = radius + 0.02
		ring.rings = 32
		ring.ring_segments = 4
		add(frame, ring, Vector3(0, h, 0), WHITE)
	box(r, Vector3(0, 0.22, 1.33), Vector3(0.4, 0.3, 0.2), WHITE)
	light(r, Vector3(0, 1.12, 0), WARM_LIGHT, 0.04, 2.0)


## Four à régolithe : four, concentrateur solaire sur mât, tapis et piles de briques.
static func _kiln(r: Node3D) -> void:
	_pad(r, 1.9)
	var brick := Color("#b5643a")
	box(r, Vector3(-0.3, 0.38, -0.2), Vector3(0.9, 0.62, 0.72), Color("#6b5a4c"))
	box(r, Vector3(-0.3, 0.71, -0.2), Vector3(0.96, 0.05, 0.78), DARK)
	box(r, Vector3(-0.3, 0.3, 0.165), Vector3(0.5, 0.12, 0.02), ORANGE, Vector3.ZERO, 2.4)
	for k in 4:
		box(r, Vector3(-0.72, 0.25 + k * 0.1, -0.2), Vector3(0.012, 0.06, 0.6), GREY)
	cylinder(r, Vector3(-0.55, 1.05, -0.4), 0.07, 0.7, GREY, Vector3.ZERO, -1.0, 12)
	cylinder(r, Vector3(-0.55, 1.42, -0.4), 0.085, 0.05, DARK, Vector3.ZERO, -1.0, 12)
	# Concentrateur : un réflecteur incliné vers le four.
	strut(r, Vector3(0.5, 0.08, 0.4), Vector3(0.5, 0.78, 0.4), 0.035, GREY)
	cylinder(r, Vector3(0.5, 0.86, 0.4), 0.06, 0.1, Color("#dfe8ef"), Vector3(-35, 0, 25), 0.44, 24)
	light(r, Vector3(0.2, 0.62, 0.1), WARM_LIGHT, 0.03, 2.0)
	# Tapis de sortie et briques empilées.
	box(r, Vector3(0.2, 0.12, -0.45), Vector3(0.7, 0.05, 0.22), DARK)
	for k in 3:
		for h in 2 - (k % 2):
			box(r, Vector3(0.25 + k * 0.2, 0.18 + h * 0.08, -0.45), Vector3(0.16, 0.07, 0.1), brick)
	for k in 2:
		box(r, Vector3(0.62, 0.12 + k * 0.08, 0.0), Vector3(0.2, 0.07, 0.12), brick)


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


## Entrepôt : hangar voûté bas, portes roulantes, caisses empilées devant.
static func _warehouse(r: Node3D) -> void:
	_pad(r, 1.9)
	box(r, Vector3(0, 0.27, -0.15), Vector3(1.6, 0.4, 1.1), WHITE)
	cylinder(r, Vector3(0, 0.47, -0.15), 0.55, 1.6, Color("#d6d4cc"), Vector3(0, 0, 90), -1.0, 18)
	for x in [-0.8, 0.8]:
		cylinder(r, Vector3(x, 0.47, -0.15), 0.56, 0.04, GREY, Vector3(0, 0, 90), -1.0, 18)
	for x in [-0.4, 0.4]:
		box(r, Vector3(x, 0.26, 0.405), Vector3(0.6, 0.36, 0.02), DARK)
		for k in 4:
			box(r, Vector3(x, 0.12 + k * 0.08, 0.418), Vector3(0.58, 0.012, 0.01), GREY)
	var crate := Color("#b88a4a")
	box(r, Vector3(-0.6, 0.17, 0.68), Vector3(0.22, 0.2, 0.22), crate)
	box(r, Vector3(-0.36, 0.17, 0.7), Vector3(0.22, 0.2, 0.22), crate.darkened(0.15))
	box(r, Vector3(-0.48, 0.37, 0.69), Vector3(0.22, 0.2, 0.22), crate.lightened(0.1))
	box(r, Vector3(0.55, 0.15, 0.7), Vector3(0.3, 0.16, 0.2), BLUE)
	light(r, Vector3(0, 0.58, 0.42), WARM_LIGHT, 0.03, 2.0)


## Laboratoire : module blanc, bandeau de hublots, petite antenne et mât de capteurs.
static func _lab(r: Node3D) -> void:
	_pad(r, 0.95)
	box(r, Vector3(0, 0.3, 0), Vector3(0.7, 0.46, 0.6), WHITE)
	box(r, Vector3(0, 0.55, 0), Vector3(0.74, 0.04, 0.64), DARK)
	box(r, Vector3(0, 0.36, 0.305), Vector3(0.56, 0.1, 0.02), Color("#2b3f52"))
	for k in 3:
		box(r, Vector3(-0.19 + k * 0.19, 0.36, 0.312), Vector3(0.13, 0.07, 0.01), Color("#9fd8ff"), Vector3.ZERO, 1.2)
	cylinder(r, Vector3(0.22, 0.72, -0.15), 0.015, 0.3, GREY, Vector3.ZERO, -1.0, 6)
	var dish := sphere(r, Vector3(0.22, 0.88, -0.15), 0.11, WHITE, Vector3(1, 0.32, 1), 0.0, true)
	dish.rotation_degrees = Vector3(0, 0, 30)
	cylinder(r, Vector3(-0.22, 0.7, -0.12), 0.012, 0.28, GREY, Vector3.ZERO, -1.0, 6)
	box(r, Vector3(-0.22, 0.85, -0.12), Vector3(0.1, 0.04, 0.04), DARK)
	light(r, Vector3(-0.22, 0.89, -0.12), Color("#5be49b"), 0.02)


## Atelier de recyclage : bâti gris, trémie de broyage, sortie de granulés et bac de matière.
static func _recycler(r: Node3D) -> void:
	_pad(r, 0.95)
	box(r, Vector3(-0.08, 0.27, 0), Vector3(0.5, 0.4, 0.5), Color("#7d858e"))
	box(r, Vector3(-0.08, 0.48, 0), Vector3(0.54, 0.03, 0.54), DARK)
	var hopper := cylinder(r, Vector3(-0.08, 0.62, 0), 0.22, 0.24, GREY, Vector3.ZERO, 0.1, 4)
	hopper.rotation_degrees.y = 45.0
	box(r, Vector3(-0.08, 0.3, 0.255), Vector3(0.3, 0.18, 0.02), DARK)
	box(r, Vector3(-0.08, 0.36, 0.262), Vector3(0.26, 0.02, 0.01), ORANGE, Vector3.ZERO, 1.2)
	strut(r, Vector3(0.17, 0.22, 0.1), Vector3(0.33, 0.12, 0.25), 0.03, DARK)
	box(r, Vector3(0.32, 0.1, 0.27), Vector3(0.18, 0.08, 0.16), Color("#5a6470"))
	for k in 3:
		sphere(r, Vector3(0.28 + k * 0.04, 0.15, 0.25 + (k % 2) * 0.04), 0.03, Color("#d9c7a3"), Vector3.ONE, 0.0, false, 8)
	light(r, Vector3(0.12, 0.42, 0.255), LIGHT, 0.022)


## Infirmerie : module cylindrique blanc, croix rouge, hublot éclairé.
static func _medbay(r: Node3D) -> void:
	_pad(r, 0.95)
	cylinder(r, Vector3(0, 0.3, 0), 0.36, 0.46, WHITE, Vector3.ZERO, -1.0, 24)
	sphere(r, Vector3(0, 0.53, 0), 0.36, WHITE, Vector3(1, 0.35, 1), 0.0, true, 24)
	cylinder(r, Vector3(0, 0.1, 0), 0.37, 0.04, GREY, Vector3.ZERO, -1.0, 24)
	box(r, Vector3(0, 0.34, 0.355), Vector3(0.22, 0.07, 0.03), RED)
	box(r, Vector3(0, 0.34, 0.355), Vector3(0.07, 0.22, 0.03), RED)
	sphere(r, Vector3(0.25, 0.34, 0.26), 0.06, WARM_LIGHT, Vector3(1, 1, 0.3), 1.5, false, 12)
	light(r, Vector3(0, 0.66, 0), Color("#ff6f61"), 0.025)


## Générateur à radio-isotopes : cylindre sombre hérissé d'ailettes, sur un petit socle.
static func _rtg(r: Node3D) -> void:
	_pad(r, 0.95)
	box(r, Vector3(0, 0.1, 0), Vector3(0.36, 0.06, 0.36), GREY)
	cylinder(r, Vector3(0, 0.42, 0), 0.12, 0.6, DARK, Vector3.ZERO, -1.0, 16)
	for k in 8:
		var a := k * TAU / 8.0
		box(r, Vector3(cos(a) * 0.2, 0.42, sin(a) * 0.2), Vector3(0.16, 0.56, 0.02), Color("#4a525c"), Vector3(0, -rad_to_deg(a), 0))
	cylinder(r, Vector3(0, 0.74, 0), 0.13, 0.04, GREY, Vector3.ZERO, -1.0, 16)
	cylinder(r, Vector3(0, 0.12, 0), 0.13, 0.04, GREY, Vector3.ZERO, -1.0, 16)
	# Le cœur reste chaud : une lueur orangée au sommet.
	var core := cylinder(r, Vector3(0, 0.77, 0), 0.06, 0.02, ORANGE, Vector3.ZERO, -1.0, 12)
	core.material_override = material(ORANGE, 1.4)
	strut(r, Vector3(0.12, 0.2, 0.12), Vector3(0.36, 0.08, 0.36), 0.02, ORANGE)
	box(r, Vector3(-0.32, 0.12, 0.3), Vector3(0.14, 0.1, 0.1), Color("#e0c341"))


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


static func rock_material(color := ROCK, dust := 0.55) -> Material:
	var key := "rock|%s|%s" % [color.to_html(), dust]
	if not _materials.has(key):
		_materials[key] = hull(color, 0.0, 0.95, 0.6, dust, 0.0)
	return _materials[key]


static var _baked := {}


## Modèle fusionné d'un module, mis en cache : les modules identiques partagent leurs maillages, et
## une pose ne reconstruit plus toute la colonie. Le maillage opaque reçoit des niveaux de détail :
## vu de loin, le moteur dessine une version simplifiée (et ses ombres aussi).
static func baked_building(building_id: String) -> Node3D:
	if not _baked.has(building_id):
		var model := bake(building(building_id))
		_baked[building_id] = _spec(model)
		model.free()
	return _from_spec(_baked[building_id])


## Description d'un modèle fusionné (maillages, ombres, pièces mobiles) : le cache garde des
## ressources, pas des nœuds hors de l'arbre.
static func _spec(node: Node3D) -> Dictionary:
	var spec := { "name": str(node.name), "transform": node.transform, "parts": [], "rotors": [] }
	for child in node.get_children():
		if child is MeshInstance3D:
			var part := child as MeshInstance3D
			var mesh: Mesh = part.mesh
			if part.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				mesh = with_lods(mesh)
			spec.parts.append([mesh, part.cast_shadow])
		elif child is Node3D:
			spec.rotors.append(_spec(child))
	return spec


static func _from_spec(spec: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = spec.name
	root.transform = spec.transform
	for part: Array in spec.parts:
		var instance := MeshInstance3D.new()
		instance.mesh = part[0]
		instance.cast_shadow = part[1]
		root.add_child(instance)
	for rotor: Dictionary in spec.rotors:
		root.add_child(_from_spec(rotor))
	return root


## Copie d'un maillage avec des niveaux de détail simplifiés (choisis selon la taille à l'écran).
static func with_lods(mesh: Mesh) -> Mesh:
	var importer := ImporterMesh.new()
	for s in mesh.get_surface_count():
		importer.add_surface(mesh.surface_get_primitive_type(s), mesh.surface_get_arrays(s), [], {}, mesh.surface_get_material(s))
	importer.generate_lods(25.0, 60.0, [])
	return importer.get_mesh()


## Caillou : un octaèdre à faces planes (8 triangles), aplati et tourné par son instance.
static func pebble_mesh() -> Mesh:
	var tips := [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]
	var faces := [[0, 2, 4], [4, 2, 1], [1, 2, 5], [5, 2, 0], [4, 3, 0], [1, 3, 4], [5, 3, 1], [0, 3, 5]]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for face: Array in faces:
		var a: Vector3 = tips[face[0]]
		var b: Vector3 = tips[face[1]]
		var c: Vector3 = tips[face[2]]
		# Godot dessine les faces vues dans le sens des aiguilles d'une montre : (c − a) × (b − a)
		# doit pointer vers l'extérieur.
		var normal := (c - a).cross(b - a).normalized()
		if normal.dot(a + b + c) < 0.0:
			var swap := b
			b = c
			c = swap
			normal = -normal
		for v in [a, b, c]:
			st.set_normal(normal)
			st.add_vertex(v)
	return st.commit()


## Fusionne toutes les pièces d'un modèle en un seul maillage (une surface par matériau) :
## bien moins d'objets à dessiner, ce qui compte beaucoup sur téléphone.
## Les pièces transparentes forment un second maillage, qui ne projette pas d'ombre.
static func bake(root: Node3D) -> Node3D:
	var tools := {}
	var order: Array[Material] = []
	# Pièces mobiles (nœuds « Rotor… ») : fusionnées à part, elles restent orientables.
	var rotors: Array[Node3D] = []
	for node in root.find_children("Rotor*", "Node3D", true, false):
		if not _under_rotor(node, root):
			rotors.append(node)
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var part: MeshInstance3D = node
		if part.name == "Flame" or part.mesh == null or _under_rotor(part, root):
			continue
		var mat: Material = part.material_override
		if not tools.has(mat):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			tools[mat] = st
			order.append(mat)
		tools[mat].append_from(part.mesh, 0, _relative_transform(root, part))
	var baked := Node3D.new()
	if not str(root.name).is_empty():
		baked.name = root.name
	baked.transform = root.transform
	var opaque := ArrayMesh.new()
	var clear := ArrayMesh.new()
	for mat in order:
		var target := clear if mat is BaseMaterial3D and (mat as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED else opaque
		# Sommets partagés (indexés) : moins de sommets à transformer, et simplifiable en niveaux de détail.
		tools[mat].index()
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
	for rotor in rotors:
		var placed := _relative_transform(root, rotor)
		var rotor_name := rotor.name
		rotor.get_parent().remove_child(rotor)
		var moving := bake(rotor)
		moving.name = rotor_name
		moving.transform = placed
		baked.add_child(moving)
	root.free()
	return baked


static func _under_rotor(node: Node, root: Node) -> bool:
	var parent := node.get_parent()
	while parent != null and parent != root:
		if str(parent.name).begins_with("Rotor"):
			return true
		parent = parent.get_parent()
	return false


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
