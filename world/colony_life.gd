class_name ColonyLife
extends RefCounted
## Ce qui fait vivre la colonie à l'écran : panneaux qui suivent le soleil (à plat la nuit,
## repliés en tempête), antennes qui tournent, lampes qui s'allument la nuit et s'éteignent
## quand un module s'arrête, flaques de lumière au sol, vapeur des usines, fumée des pannes.
## Pas de règle de jeu ici : tout se lit dans le ColonyEngine.

## Bouches de vapeur, par module (repère du module, origine au centre de l'emprise).
const VENTS := {
	"kiln": Vector3(-0.55, 1.45, -0.4),
	"moxie": Vector3(0.14, 1.0, 0.1),
	"sabatier": Vector3(-0.35, 1.32, -0.3),
}
## Modules sans fenêtre ni lampe : pas de lumière au sol la nuit.
const DARK_MODULES := ["link", "solar", "battery", "tank"]

var _world: Node3D
var _engine: ColonyEngine
var _sun: DirectionalLight3D
var _nodes: Array[Node3D] = []
var _rotors: Array[Node3D] = []
var _lit: Array[float] = []
var _glow: MultiMeshInstance3D
var _steam: CPUParticles3D
var _smoke: CPUParticles3D


func _init(world: Node3D, engine: ColonyEngine, sun: DirectionalLight3D) -> void:
	_world = world
	_engine = engine
	_sun = sun
	_glow = MultiMeshInstance3D.new()
	_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_glow.material_override = _glow_material()
	world.add_child(_glow)
	_steam = _vapour(Color(0.92, 0.92, 0.9, 0.42), 0.22, 2.4)
	_smoke = _vapour(Color(0.16, 0.15, 0.15, 0.6), 0.26, 2.0)
	world.add_child(_steam)
	world.add_child(_smoke)


## Les modules ont été reconstruits : on repère leurs pièces mobiles et leurs lampes.
func rebuild(nodes: Array[Node3D]) -> void:
	_nodes = nodes
	_rotors.clear()
	_lit.clear()
	_lit.resize(nodes.size())
	_lit.fill(-1.0)
	for node in nodes:
		for rotor: Node3D in node.find_children("Rotor*", "Node3D", true, false):
			rotor.set_meta("base", rotor.transform)
			rotor.set_meta("yaw", 0.0)
			rotor.set_meta("tilt", deg_to_rad(24.0))
			_rotors.append(rotor)
	var mesh := QuadMesh.new()
	mesh.orientation = PlaneMesh.FACE_Y
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = mesh
	var lit_modules: Array[int] = []
	for i in nodes.size():
		if not _engine.state.buildings[i].id in DARK_MODULES:
			lit_modules.append(i)
	multimesh.instance_count = lit_modules.size()
	for k in lit_modules.size():
		var i := lit_modules[k]
		var size := Vector2(_engine.def_of(i).size) * 2.6
		multimesh.set_instance_transform(k, Transform3D(Basis.from_scale(Vector3(size.x, 1.0, size.y)), nodes[i].position + Vector3(0, 0.08, 0)))
		multimesh.set_instance_color(k, Color(1, 1, 1, 0))
	_glow.multimesh = multimesh
	_glow.set_meta("modules", lit_modules)
	_steam.set_meta("key", "?")
	_smoke.set_meta("key", "?")


## Part de nuit (0 en plein jour, 1 en pleine nuit).
func night() -> float:
	var t := _engine.time_of_day()
	return 1.0 - clampf(cos(TAU * (t - 0.5)) * 1.6 + 0.15, 0.0, 1.0)


func _running(i: int) -> bool:
	if not _engine.is_linked(i) or _engine.is_broken(i):
		return false
	return _engine.def_of(i).inputs.is_empty() or (_engine.efficiency(i) > 0.001 and not _engine.is_idle(i))


## Lampes, lumière au sol, vapeur et fumée : suit l'état des modules (appelé à chaque mise à jour).
func refresh() -> void:
	var count := mini(_nodes.size(), _engine.state.buildings.size())
	var dark := night()
	var modules: Array = _glow.get_meta("modules", [])
	# Lueur des lampes la nuit : un seul paramètre pour toute la scène.
	RenderingServer.global_shader_parameter_set("night_glow", snappedf(dark, 0.05))
	var glow_on := false
	for i in count:
		# Lampes éteintes quand le module s'arrête : on ne touche aux surfaces que si ça change.
		var lit := 1.0 if _running(i) else 0.0
		if lit != _lit[i]:
			_lit[i] = lit
			ModelBuilder.set_surface_param(_nodes[i], "lamp", "off", lit == 0.0)
	if _glow.multimesh != null:
		for k in modules.size():
			var i: int = modules[k]
			var strength := dark * (1.0 if i < count and _running(i) else 0.15)
			glow_on = glow_on or strength > 0.02
			_glow.multimesh.set_instance_color(k, Color(1, 1, 1, strength))
	_glow.visible = glow_on

	var vents := PackedVector3Array()
	var smoke := PackedVector3Array()
	for i in count:
		var id: String = _engine.state.buildings[i].id
		if _engine.is_broken(i):
			smoke.append(_nodes[i].position + Vector3(0, float(_nodes[i].get_meta("top", 0.8)), 0))
		elif VENTS.has(id) and _running(i):
			vents.append(_nodes[i].position + VENTS[id])
	_set_points(_steam, vents, 7)
	_set_points(_smoke, smoke, 10)
	var pace := clampf(float(_engine.state.speed), 0.0, 2.0)
	_steam.speed_scale = pace
	_smoke.speed_scale = pace


func _set_points(particles: CPUParticles3D, points: PackedVector3Array, per_point: int) -> void:
	var key := str(points)
	if particles.has_meta("key") and particles.get_meta("key") == key:
		return
	particles.set_meta("key", key)
	particles.emitting = not points.is_empty()
	if points.is_empty():
		return
	particles.emission_points = points
	particles.amount = clampi(points.size() * per_point, per_point, 80)


## Panneaux : orientés vers le soleil, à plat la nuit, repliés à la verticale si l'équipage l'a
## décidé pour une tempête. Antennes : tournent tant que la partie avance.
func update(delta: float) -> void:
	if _rotors.is_empty():
		return
	var to_sun := _sun.global_basis.z
	var folded := _engine.is_storm() and _engine.state.shelter
	var daylight := _engine.time_of_day() > 0.27 and _engine.time_of_day() < 0.73
	var target_yaw := atan2(-to_sun.x, -to_sun.z)
	var target_tilt := clampf(PI / 2.0 - asin(clampf(to_sun.y, -1.0, 1.0)), 0.15, 0.75)
	if folded:
		target_tilt = deg_to_rad(84.0)
	elif not daylight:
		target_tilt = 0.0
	var turn := minf(1.0, delta * 0.8)
	var moving := _engine.state.speed > 0
	for rotor in _rotors:
		if not is_instance_valid(rotor):
			continue
		var base: Transform3D = rotor.get_meta("base")
		var yaw: float = rotor.get_meta("yaw")
		var tilt: float = rotor.get_meta("tilt")
		if str(rotor.name).begins_with("RotorSun"):
			if daylight or folded:
				yaw = lerp_angle(yaw, target_yaw, turn)
			tilt = lerpf(tilt, target_tilt, turn)
			rotor.transform = Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -tilt), base.origin)
		elif moving:
			yaw = fmod(yaw + delta * 0.5 * _engine.state.speed, TAU)
			rotor.transform = Transform3D(Basis(Vector3.UP, yaw) * base.basis, base.origin)
		rotor.set_meta("yaw", yaw)
		rotor.set_meta("tilt", tilt)


func _glow_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
// Flaque de lumière chaude au pied des modules éclairés, la nuit.
void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float a = 1.0 - smoothstep(0.25, 1.0, d);
	ALBEDO = vec3(1.0, 0.7, 0.38) * a * a * COLOR.a * 0.55;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	return mat


func _vapour(color: Color, size: float, lifetime: float) -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(size, size)
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	gradient.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 32
	texture.height = 32
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = texture
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.vertex_color_use_as_albedo = true
	mesh.material = mat
	particles.mesh = mesh
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINTS
	particles.emission_points = PackedVector3Array([Vector3.ZERO])
	particles.amount = 8
	particles.lifetime = lifetime
	particles.direction = Vector3.UP
	particles.spread = 12.0
	particles.initial_velocity_min = 0.25
	particles.initial_velocity_max = 0.5
	particles.gravity = Vector3(0.08, 0.06, 0.04)
	particles.scale_amount_min = 0.6
	particles.scale_amount_max = 1.4
	var growth := Curve.new()
	growth.add_point(Vector2(0.0, 0.5))
	growth.add_point(Vector2(1.0, 2.2))
	particles.scale_amount_curve = growth
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	fade.colors = PackedColorArray([Color(color, 0.0), color, Color(color, 0.0)])
	particles.color_ramp = fade
	particles.local_coords = true
	particles.emitting = false
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return particles
