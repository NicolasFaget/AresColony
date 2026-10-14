class_name Astronaut
extends Node3D
## Astronaute articulé : casque à visière dorée, sac de survie, bande de couleur selon la spécialité.
## Marche le long d'un chemin (liste de points) avec balancement des bras et des jambes.

const ROLE_COLORS := {
	"ingénieure": Color("#ff8a3d"), "ingénieur": Color("#ff8a3d"),
	"botaniste": Color("#5bd46a"), "géologue": Color("#c08552"),
	"médecin": Color("#ff5a5a"), "chimiste": Color("#b48cff"),
	"pilote": Color("#4f9dff"), "biologiste": Color("#2ec9b8"),
	"électricien": Color("#ffd24d"),
}

const WHITE := Color("#f2f1ec")
const SUIT_SHADE := Color("#d8d6cf")
const DARK := Color("#3c4048")

var walk_speed := 0.55
var path: Array[Vector3] = []

var _hips: Node3D
var _left_leg: Node3D
var _right_leg: Node3D
var _left_arm: Node3D
var _right_arm: Node3D
var _head: Node3D
var _phase := 0.0
var _idle_phase := 0.0


func _init(role := "") -> void:
	var accent: Color = ROLE_COLORS.get(role, Color("#7fe8ff"))
	_hips = Node3D.new()
	_hips.position.y = 0.14
	add_child(_hips)

	_left_leg = _limb(_hips, Vector3(-0.032, 0, 0), 0.03, 0.13, WHITE)
	_right_leg = _limb(_hips, Vector3(0.032, 0, 0), 0.03, 0.13, WHITE)
	for leg in [_left_leg, _right_leg]:
		ModelBuilder.box(leg, Vector3(0, -0.135, 0.012), Vector3(0.05, 0.035, 0.075), DARK)

	# Torse, bande de couleur, panneau de contrôle.
	_capsule(_hips, Vector3(0, 0.1, 0), 0.062, 0.17, WHITE)
	ModelBuilder.cylinder(_hips, Vector3(0, 0.07, 0), 0.064, 0.025, accent)
	ModelBuilder.box(_hips, Vector3(0, 0.12, 0.058), Vector3(0.05, 0.035, 0.015), DARK)
	ModelBuilder.sphere(_hips, Vector3(0.012, 0.125, 0.067), 0.006, Color("#5be49b"), Vector3.ONE, 3.0)
	# Sac de survie et antenne.
	ModelBuilder.box(_hips, Vector3(0, 0.12, -0.065), Vector3(0.1, 0.13, 0.05), SUIT_SHADE)
	ModelBuilder.cylinder(_hips, Vector3(0.035, 0.22, -0.075), 0.004, 0.09, DARK)

	_left_arm = _limb(_hips, Vector3(-0.078, 0.165, 0), 0.024, 0.12, WHITE)
	_right_arm = _limb(_hips, Vector3(0.078, 0.165, 0), 0.024, 0.12, WHITE)
	for arm in [_left_arm, _right_arm]:
		ModelBuilder.sphere(arm, Vector3(0, -0.125, 0), 0.022, DARK)
		ModelBuilder.cylinder(arm, Vector3(0, -0.03, 0), 0.026, 0.02, accent)

	# Casque : coque blanche, visière dorée réfléchissante, liseré de couleur.
	_head = Node3D.new()
	_head.position.y = 0.235
	_hips.add_child(_head)
	ModelBuilder.sphere(_head, Vector3.ZERO, 0.068, WHITE)
	var visor := ModelBuilder.sphere(_head, Vector3(0, 0.005, 0.03), 0.056, Color("#e0a93a"), Vector3(1.0, 0.82, 0.75))
	visor.material_override = ModelBuilder.material(Color("#e0a93a"), 0.15, 0.85)
	ModelBuilder.cylinder(_head, Vector3(0, 0.0, 0), 0.07, 0.012, accent, Vector3(90, 0, 0))
	ModelBuilder.sphere(_head, Vector3(-0.055, 0.035, 0.0), 0.012, Color("#fff4c0"), Vector3.ONE, 3.0)

	for node in find_children("*", "GeometryInstance3D", true, false):
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func is_walking() -> bool:
	return not path.is_empty()


## Avance le long du chemin ; anime la marche ou la respiration au repos.
func update(delta: float, time_scale: float) -> void:
	if time_scale <= 0.0:
		return
	if path.is_empty():
		_idle(delta)
		return
	var target: Vector3 = path[0]
	var to := Vector3(target.x - position.x, 0.0, target.z - position.z)
	var distance := to.length()
	var step := walk_speed * time_scale * delta
	if distance <= step:
		position.x = target.x
		position.z = target.z
		path.pop_front()
	else:
		position += to / distance * step
		rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), minf(1.0, delta * 10.0))
	_phase += delta * 9.0 * time_scale
	var swing := sin(_phase)
	_left_leg.rotation.x = swing * 0.55
	_right_leg.rotation.x = -swing * 0.55
	_left_arm.rotation.x = -swing * 0.45
	_right_arm.rotation.x = swing * 0.45
	# Petits bonds : la gravité martienne n'est que 38 % de celle de la Terre.
	_hips.position.y = 0.14 + absf(sin(_phase)) * 0.018


func _idle(delta: float) -> void:
	_idle_phase += delta
	for limb in [_left_leg, _right_leg, _left_arm, _right_arm]:
		limb.rotation.x = lerpf(limb.rotation.x, 0.0, minf(1.0, delta * 8.0))
	_hips.position.y = 0.14 + sin(_idle_phase * 2.0) * 0.003
	_head.rotation.y = sin(_idle_phase * 0.7) * 0.5


## Membre articulé : pivot à l'épaule ou à la hanche, segment qui pend en dessous.
func _limb(parent: Node3D, pivot: Vector3, radius: float, length: float, color: Color) -> Node3D:
	var joint := Node3D.new()
	joint.position = pivot
	parent.add_child(joint)
	_capsule(joint, Vector3(0, -length / 2.0, 0), radius, length, color)
	return joint


static func _capsule(parent: Node3D, center: Vector3, radius: float, height: float, color: Color) -> MeshInstance3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = maxf(height, radius * 2.0)
	mesh.radial_segments = 12
	mesh.rings = 4
	return ModelBuilder.add(parent, mesh, center, color)
