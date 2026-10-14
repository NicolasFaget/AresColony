class_name ModelBuilder
extends RefCounted
## Modèles 3D low-poly construits à partir de primitives (pas de fichier externe).
## Unité : une case de la grille. Origine au centre de l'emprise, au niveau du sol.

const WHITE := Color("#ecebe4")
const GREY := Color("#9aa0a6")
const DARK := Color("#4a5056")
const GOLD := Color("#d9a43a")
const ORANGE := Color("#e47a26")
const RED := Color("#b8322c")
const BLUE := Color("#2c4a7a")
const PANEL := Color("#1d2f55")
const GLASS := Color(0.62, 0.9, 0.86, 0.35)
const GREEN := Color("#4c9a3c")
const DARK_GREEN := Color("#2f6e2c")
const CONCRETE := Color("#a89b8c")
const LIGHT := Color("#7ff5ea")

static var _materials := {}


# ---------- Matériaux et primitives ----------

static func material(color: Color, emission := 0.0, metallic := 0.0) -> StandardMaterial3D:
	var key := "%s|%s|%s" % [color.to_html(), emission, metallic]
	if not _materials.has(key):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = 0.8 if metallic == 0.0 else 0.35
		mat.metallic = metallic
		if color.a < 1.0:
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.roughness = 0.1
		if emission > 0.0:
			mat.emission_enabled = true
			mat.emission = color
			mat.emission_energy_multiplier = emission
		_materials[key] = mat
	return _materials[key]


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
		rot := Vector3.ZERO, top_radius := -1.0, sides := 16) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = radius
	mesh.top_radius = radius if top_radius < 0.0 else top_radius
	mesh.height = height
	mesh.radial_segments = sides
	mesh.rings = 1
	return add(parent, mesh, center, color, rot)


static func sphere(parent: Node3D, center: Vector3, radius: float, color: Color, scale := Vector3.ONE,
		emission := 0.0, hemisphere := false) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * (1.0 if hemisphere else 2.0)
	mesh.is_hemisphere = hemisphere
	mesh.radial_segments = 20
	mesh.rings = 10
	var node := add(parent, mesh, center, color, Vector3.ZERO, emission)
	node.scale = scale
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
	box(r, Vector3(0, 0.04, 0), Vector3(size, 0.08, size), CONCRETE)


static func _lander(r: Node3D) -> void:
	_pad(r, 1.9)
	for angle in [45, 135, 225, 315]:
		var dir := Vector3(cos(deg_to_rad(angle)), 0, sin(deg_to_rad(angle)))
		cylinder(r, dir * 0.62 + Vector3(0, 0.35, 0), 0.04, 0.7, GREY, Vector3(dir.z * 18.0, 0, -dir.x * 18.0))
		cylinder(r, dir * 0.72 + Vector3(0, 0.1, 0), 0.12, 0.04, DARK)
	cylinder(r, Vector3(0, 0.85, 0), 0.55, 0.7, GOLD, Vector3.ZERO, 0.5, 8).material_override = material(GOLD, 0.0, 0.6)
	cylinder(r, Vector3(0, 1.35, 0), 0.42, 0.3, WHITE, Vector3.ZERO, 0.3, 8)
	for side in [-1.0, 1.0]:
		box(r, Vector3(side * 0.95, 1.0, 0), Vector3(0.7, 0.03, 0.55), PANEL, Vector3(0, 0, side * 10.0), 0.0, 0.5)
		box(r, Vector3(side * 0.58, 1.0, 0), Vector3(0.12, 0.04, 0.04), GREY)
	cylinder(r, Vector3(0.15, 1.65, 0.1), 0.02, 0.3, GREY)
	sphere(r, Vector3(0.15, 1.85, 0.1), 0.16, WHITE, Vector3(1, 0.35, 1), 0.0, true)
	box(r, Vector3(0, 0.45, 0.6), Vector3(0.18, 0.5, 0.04), DARK)


static func _link(r: Node3D) -> void:
	box(r, Vector3(0, 0.05, 0), Vector3(0.96, 0.1, 0.96), CONCRETE)
	cylinder(r, Vector3(0, 0.16, 0), 0.07, 0.98, GREY, Vector3(0, 0, 90), -1.0, 8)
	cylinder(r, Vector3(0, 0.16, 0), 0.07, 0.98, GREY, Vector3(90, 0, 0), -1.0, 8)
	cylinder(r, Vector3(0, 0.18, 0), 0.12, 0.12, ORANGE, Vector3.ZERO, -1.0, 8)


static func _solar(r: Node3D) -> void:
	cylinder(r, Vector3(0, 0.25, 0), 0.04, 0.5, GREY)
	var panel := box(r, Vector3(0, 0.55, 0), Vector3(0.9, 0.04, 0.8), PANEL, Vector3(-25, 0, 0), 0.0, 0.5)
	for i in 3:
		box(panel, Vector3(-0.3 + i * 0.3, 0.025, 0), Vector3(0.015, 0.01, 0.78), Color("#5d7bb0"))


static func _habitat(r: Node3D) -> void:
	_pad(r, 1.9)
	cylinder(r, Vector3(0, 0.2, 0), 0.85, 0.24, GREY, Vector3.ZERO, -1.0, 24)
	sphere(r, Vector3(0, 0.32, 0), 0.82, WHITE, Vector3(1, 0.85, 1), 0.0, true)
	for i in 4:
		var angle := i * TAU / 4.0 + 0.4
		sphere(r, Vector3(cos(angle) * 0.62, 0.62, sin(angle) * 0.62), 0.09, Color("#ffd9a0"), Vector3(1, 0.7, 1), 1.5)
	box(r, Vector3(0, 0.3, 0.88), Vector3(0.36, 0.42, 0.3), WHITE)
	box(r, Vector3(0, 0.3, 1.03), Vector3(0.2, 0.3, 0.02), DARK)
	cylinder(r, Vector3(-0.4, 1.0, -0.3), 0.015, 0.4, GREY)
	sphere(r, Vector3(-0.4, 1.22, -0.3), 0.04, Color("#ff6f61"), Vector3.ONE, 3.0)


static func _moxie(r: Node3D) -> void:
	_pad(r, 0.95)
	box(r, Vector3(0, 0.38, 0), Vector3(0.62, 0.6, 0.62), GOLD).material_override = material(GOLD, 0.0, 0.7)
	box(r, Vector3(0, 0.38, 0.32), Vector3(0.4, 0.3, 0.02), DARK)
	cylinder(r, Vector3(0.18, 0.85, 0.12), 0.06, 0.34, GREY)
	cylinder(r, Vector3(-0.2, 0.3, -0.38), 0.05, 0.6, WHITE, Vector3(90, 0, 0), -1.0, 8)
	sphere(r, Vector3(0.18, 1.04, 0.12), 0.05, LIGHT, Vector3.ONE, 2.0)


static func _battery(r: Node3D) -> void:
	_pad(r, 0.95)
	box(r, Vector3(0, 0.3, 0), Vector3(0.78, 0.46, 0.6), Color("#5a6470"))
	box(r, Vector3(0, 0.3, 0.305), Vector3(0.7, 0.08, 0.02), Color("#5be49b"), Vector3.ZERO, 1.2)
	for i in 3:
		box(r, Vector3(-0.24 + i * 0.24, 0.56, 0), Vector3(0.12, 0.06, 0.4), DARK)


static func _extractor(r: Node3D) -> void:
	_pad(r, 1.9)
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var base := Vector3(corner.x * 0.32, 0.08, corner.y * 0.32 - 0.25)
		var top := Vector3(corner.x * 0.08, 1.7, corner.y * 0.08 - 0.25)
		var leg := box(r, (base + top) / 2.0, Vector3(0.05, (top - base).length(), 0.05), ORANGE)
		leg.basis = Basis(Quaternion(Vector3.UP, (top - base).normalized()))
	box(r, Vector3(0, 1.7, -0.25), Vector3(0.3, 0.1, 0.3), ORANGE)
	cylinder(r, Vector3(0, 0.5, -0.25), 0.05, 1.0, GREY)
	cylinder(r, Vector3(0.45, 0.42, 0.45), 0.32, 0.7, Color("#d8e6f0"))
	cylinder(r, Vector3(0.45, 0.8, 0.45), 0.33, 0.06, BLUE)
	box(r, Vector3(-0.45, 0.25, 0.45), Vector3(0.5, 0.34, 0.5), WHITE)
	cylinder(r, Vector3(0.0, 0.22, 0.45), 0.04, 0.5, BLUE, Vector3(0, 0, 90), -1.0, 8)


static func _greenhouse(r: Node3D) -> void:
	_pad(r, 1.9)
	box(r, Vector3(0, 0.14, 0), Vector3(1.7, 0.12, 1.7), Color("#6b4a32"))
	for x in [-0.45, 0.0, 0.45]:
		for z in [-0.45, 0.0, 0.45]:
			sphere(r, Vector3(x, 0.3, z), 0.16, GREEN if fposmod(x + z, 0.9) < 0.1 else DARK_GREEN, Vector3(1, 0.8, 1))
	sphere(r, Vector3(0.45, 0.4, -0.45), 0.07, RED)
	sphere(r, Vector3(-0.3, 0.38, 0.2), 0.06, RED)
	box(r, Vector3(0, 0.62, 0), Vector3(1.8, 0.86, 1.8), GLASS)
	box(r, Vector3(0, 1.06, 0), Vector3(1.82, 0.04, 1.82), GREY)
	for x in [-0.9, 0.9]:
		box(r, Vector3(x, 0.62, 0), Vector3(0.04, 0.88, 1.82), GREY)
	box(r, Vector3(0, 1.1, 0), Vector3(1.4, 0.05, 0.08), Color("#ff7ad9"), Vector3.ZERO, 1.6)


static func _electrolyser(r: Node3D) -> void:
	_pad(r, 0.95)
	cylinder(r, Vector3(-0.2, 0.42, 0), 0.17, 0.7, WHITE)
	sphere(r, Vector3(-0.2, 0.77, 0), 0.17, WHITE)
	cylinder(r, Vector3(0.2, 0.36, 0.08), 0.13, 0.56, Color("#8fb8e8"))
	sphere(r, Vector3(0.2, 0.64, 0.08), 0.13, Color("#8fb8e8"))
	box(r, Vector3(0.1, 0.18, -0.28), Vector3(0.5, 0.22, 0.2), DARK)
	sphere(r, Vector3(0.28, 0.32, -0.28), 0.03, LIGHT, Vector3.ONE, 2.5)


# ---------- Personnages et véhicules ----------

static func astronaut() -> Node3D:
	var r := Node3D.new()
	cylinder(r, Vector3(0, 0.17, 0), 0.06, 0.22, WHITE, Vector3.ZERO, 0.07, 10)
	sphere(r, Vector3(0, 0.33, 0), 0.075, WHITE)
	sphere(r, Vector3(0, 0.335, 0.045), 0.05, ORANGE, Vector3(1, 0.8, 0.6), 0.6)
	box(r, Vector3(0, 0.2, -0.07), Vector3(0.1, 0.14, 0.05), GREY)
	for x in [-0.03, 0.03]:
		box(r, Vector3(x, 0.04, 0), Vector3(0.04, 0.08, 0.05), WHITE)
	return r


static func capsule() -> Node3D:
	var r := Node3D.new()
	cylinder(r, Vector3(0, 0.45, 0), 0.45, 0.7, WHITE, Vector3.ZERO, 0.22, 16)
	cylinder(r, Vector3(0, 0.08, 0), 0.47, 0.1, Color("#3a2a24"), Vector3.ZERO, -1.0, 16)
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


static func rock(rng: RandomNumberGenerator, color := Color("#7a4632")) -> Node3D:
	var r := Node3D.new()
	sphere(r, Vector3.ZERO, rng.randf_range(0.15, 0.35), color,
			Vector3(rng.randf_range(0.9, 1.4), rng.randf_range(0.5, 0.8), rng.randf_range(0.8, 1.3)))
	return r


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
