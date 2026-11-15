class_name SolarSystem
extends Node3D
## Vue 3D du Système solaire : le Soleil, les mondes du jeu (et la Terre), leurs orbites, la ceinture
## d'astéroïdes, les fusées en vol et les routes entre les colonies.
## Tailles et distances ne sont pas à l'échelle (Saturne serait sinon un point au bord de l'écran).
## Les planètes tournent à leur vraie vitesse, dans le temps du jeu (un sol de voyage ≈ un mois).

## orbit : rayon (unités de la vue) ; period : période orbitale en sols de jeu (Mars 687 jours ≈ 22,6 mois) ;
## parent : planète autour de laquelle tourne une lune (périodes des lunes ralenties pour rester lisibles).
const BODIES := {
	"earth": { "name": "Terre", "orbit": 3.2, "period": 12.0, "size": 0.26, "color": Color(0.22, 0.48, 0.95),
			"band": Color(0.9, 0.95, 1.0), "bands": 3.0, "strength": 0.25, "phase": 1.1 },
	"mars": { "name": "Mars", "orbit": 4.6, "period": 22.6, "size": 0.22, "color": Color(0.82, 0.4, 0.2),
			"band": Color(0.55, 0.25, 0.14), "bands": 2.0, "strength": 0.35, "phase": 0.0 },
	"ceres": { "name": "Cérès", "orbit": 6.6, "period": 55.4, "size": 0.12, "color": Color(0.6, 0.58, 0.55),
			"band": Color(0.85, 0.85, 0.82), "bands": 2.0, "strength": 0.2, "phase": 2.4 },
	"jupiter": { "name": "Jupiter", "orbit": 10.0, "period": 142.0, "size": 0.7, "color": Color(0.88, 0.76, 0.6),
			"band": Color(0.66, 0.44, 0.3), "bands": 9.0, "strength": 0.7, "phase": 4.2 },
	"europa": { "name": "Europe", "parent": "jupiter", "orbit": 1.25, "period": 3.0, "size": 0.11,
			"color": Color(0.94, 0.89, 0.8), "band": Color(0.7, 0.42, 0.3), "bands": 4.0, "strength": 0.35, "phase": 0.5 },
	"saturn": { "name": "Saturne", "orbit": 14.0, "period": 354.0, "size": 0.58, "color": Color(0.93, 0.84, 0.62),
			"band": Color(0.78, 0.65, 0.42), "bands": 7.0, "strength": 0.45, "phase": 5.5, "ring": true },
	"enceladus": { "name": "Encelade", "parent": "saturn", "orbit": 1.45, "period": 2.0, "size": 0.08,
			"color": Color(0.97, 0.98, 1.0), "band": Color(0.6, 0.8, 1.0), "bands": 3.0, "strength": 0.3, "phase": 2.0 },
	"titan": { "name": "Titan", "parent": "saturn", "orbit": 2.05, "period": 6.0, "size": 0.15,
			"color": Color(0.92, 0.62, 0.26), "band": Color(0.75, 0.48, 0.2), "bands": 2.0, "strength": 0.2, "phase": 4.0 },
}
const BELT_INNER := 5.7
const BELT_OUTER := 7.5
const BELT_PERIOD := 55.0
## Vue d'ensemble : tout le système tient dans la largeur de l'écran.
const OVERVIEW_DISTANCE := 29.0
const MIN_DISTANCE := 1.2
const MAX_DISTANCE := 48.0

var camera: Camera3D
var time := 0.0
## Orientation de la caméra (radians) et distance à son point visé.
var yaw := 0.35
var pitch := 0.95
var distance := OVERVIEW_DISTANCE
## Monde suivi par la caméra ("" : le Soleil, vue d'ensemble).
var focus_body := ""

var _bodies := {}
var _focus_point := Vector3.ZERO
var _belt: MultiMeshInstance3D
var _lines: MeshInstance3D
var _line_mesh: ImmediateMesh
var _rockets: Array[MeshInstance3D] = []
var _rocket_mesh: SphereMesh
var _planet_shader: Shader


func _ready() -> void:
	_build_environment()
	_build_sun()
	_planet_shader = Shader.new()
	_planet_shader.code = PLANET_SHADER
	for id: String in BODIES:
		_build_body(id)
	_build_orbits()
	_build_belt()
	_line_mesh = ImmediateMesh.new()
	_lines = MeshInstance3D.new()
	_lines.mesh = _line_mesh
	_lines.material_override = _line_material()
	add_child(_lines)
	_rocket_mesh = SphereMesh.new()
	_rocket_mesh.radius = 0.07
	_rocket_mesh.height = 0.14
	_rocket_mesh.radial_segments = 8
	_rocket_mesh.rings = 4
	camera = Camera3D.new()
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.fov = 55.0
	camera.near = 0.05
	camera.far = 200.0
	add_child(camera)
	_place_camera(1.0)


## Avance la vue au temps `sols` de la campagne ; `delta` : secondes réelles (glissement de la caméra).
func update(sols: float, delta: float) -> void:
	time = sols
	for id: String in BODIES:
		(_bodies[id] as Node3D).position = body_position(id)
		(_bodies[id] as Node3D).rotation.y = sols * 0.8
	_belt.rotation.y = -TAU * sols / BELT_PERIOD
	_place_camera(minf(1.0, delta * 4.0))


## Position d'un monde au temps courant (une lune suit sa planète).
func body_position(id: String) -> Vector3:
	var body: Dictionary = BODIES[id]
	var angle: float = body.phase + TAU * time / body.period
	var own: Vector3 = Vector3(cos(angle), 0.0, -sin(angle)) * float(body.orbit)
	if body.has("parent"):
		return body_position(body.parent) + own
	return own


func body_size(id: String) -> float:
	return BODIES[id].size


## Point de l'écran (pixels de la vue) d'une position 3D, ou null derrière la caméra.
func screen_position(point: Vector3) -> Variant:
	if camera.is_position_behind(point):
		return null
	return camera.unproject_position(point)


## Rayon apparent d'un monde à l'écran (pixels).
func screen_radius(id: String) -> float:
	var center := body_position(id)
	var side := camera.global_transform.basis.x * body_size(id)
	var a: Variant = screen_position(center)
	var b: Variant = screen_position(center + side)
	return (a as Vector2).distance_to(b) if a != null and b != null else 0.0


func focus_on(id: String) -> void:
	focus_body = id
	if id.is_empty():
		distance = OVERVIEW_DISTANCE
		pitch = 0.95
		return
	# Assez près pour voir la planète et ses lunes.
	var reach: float = body_size(id) * 7.0
	for other: String in BODIES:
		if BODIES[other].get("parent", "") == id:
			reach = maxf(reach, BODIES[other].orbit * 2.4)
	distance = clampf(reach, MIN_DISTANCE, MAX_DISTANCE)
	pitch = 0.6


func orbit(delta: Vector2) -> void:
	yaw -= delta.x * 0.006
	pitch = clampf(pitch + delta.y * 0.004, 0.12, 1.45)


func zoom(factor: float) -> void:
	distance = clampf(distance * factor, MIN_DISTANCE, MAX_DISTANCE)


## Routes (pointillés, vertes si la fenêtre de tir est ouverte) et fusées en vol :
## `routes` : [{ from, to, open }] ; `flights` : [{ from, to, progress, kind }] (noms de mondes).
func draw_traffic(routes: Array, flights: Array) -> void:
	_line_mesh.clear_surfaces()
	var has_lines := false
	for route: Dictionary in routes:
		if not has_lines:
			_line_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
			has_lines = true
		var color := Color(0.36, 0.9, 0.6, 0.75) if route.open else Color(0.62, 0.75, 0.85, 0.22)
		var a := body_position(route.from)
		var b := body_position(route.to)
		var steps := 40
		for k in steps:
			if k % 2 == 1:
				continue
			_line_mesh.surface_set_color(color)
			_line_mesh.surface_add_vertex(_arc(a, b, float(k) / steps))
			_line_mesh.surface_set_color(color)
			_line_mesh.surface_add_vertex(_arc(a, b, float(k + 1) / steps))
	for flight: Dictionary in flights:
		if not has_lines:
			_line_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
			has_lines = true
		var a := body_position(flight.from)
		var b := body_position(flight.to)
		var color := _flight_color(flight)
		color.a = 0.55
		var steps := 32
		for k in steps:
			var t0 := float(k) / steps
			var t1 := float(k + 1) / steps
			if t0 < flight.progress:
				continue
			_line_mesh.surface_set_color(color)
			_line_mesh.surface_add_vertex(_arc(a, b, t0))
			_line_mesh.surface_set_color(color)
			_line_mesh.surface_add_vertex(_arc(a, b, t1))
	if has_lines:
		_line_mesh.surface_end()
	while _rockets.size() < flights.size():
		var rocket := MeshInstance3D.new()
		rocket.mesh = _rocket_mesh
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rocket.material_override = material
		add_child(rocket)
		_rockets.append(rocket)
	for k in _rockets.size():
		_rockets[k].visible = k < flights.size()
		if k < flights.size():
			var flight: Dictionary = flights[k]
			_rockets[k].position = _arc(body_position(flight.from), body_position(flight.to), flight.progress)
			# Taille constante à l'écran, qu'on regarde de loin ou de près.
			_rockets[k].scale = Vector3.ONE * clampf(camera.position.distance_to(_rockets[k].position) * 0.022, 0.06, 1.6)
			(_rockets[k].material_override as StandardMaterial3D).albedo_color = _flight_color(flight)


## Position d'une fusée en vol (pour son étiquette).
func flight_position(flight: Dictionary) -> Vector3:
	return _arc(body_position(flight.from), body_position(flight.to), flight.progress)


func _flight_color(flight: Dictionary) -> Color:
	return Palette.MONEY if flight.kind == "colony" else Palette.ACCENT


## Trajet courbe entre deux mondes ; un saut sur un même monde fait une petite boucle au-dessus.
func _arc(a: Vector3, b: Vector3, t: float) -> Vector3:
	var span := a.distance_to(b)
	var control := (a + b) * 0.5 + Vector3.UP * maxf(0.5, span * 0.22)
	return a.lerp(control, t).lerp(control.lerp(b, t), t)


func _place_camera(weight: float) -> void:
	var target := body_position(focus_body) if not focus_body.is_empty() else Vector3.ZERO
	_focus_point = _focus_point.lerp(target, weight) if weight < 1.0 else target
	var offset := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	var wanted := _focus_point + offset
	camera.position = camera.position.lerp(wanted, weight) if weight < 1.0 else wanted
	camera.look_at(_focus_point, Vector3.UP)


# ---------- Construction ----------

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.008, 0.014, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.38, 0.5)
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	# Étoiles lointaines : une sphère de points.
	var stars := MeshInstance3D.new()
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_POINTS)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for k in 700:
		var dir := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
		var shade := rng.randf_range(0.35, 1.0)
		mesh.surface_set_color(Color(shade, shade, shade * rng.randf_range(0.95, 1.15)))
		mesh.surface_add_vertex(dir * 120.0)
	mesh.surface_end()
	stars.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.use_point_size = true
	material.point_size = 2.0
	stars.material_override = material
	add_child(stars)


func _build_sun() -> void:
	var sun := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.9
	mesh.height = 1.8
	sun.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.86, 0.45)
	sun.material_override = material
	add_child(sun)
	# Halo : un disque toujours face à la caméra, qui s'efface vers l'extérieur.
	var halo := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(5.0, 5.0)
	halo.mesh = quad
	var shader := Shader.new()
	shader.code = HALO_SHADER
	var halo_material := ShaderMaterial.new()
	halo_material.shader = shader
	halo.material_override = halo_material
	add_child(halo)
	var light := OmniLight3D.new()
	light.omni_range = 60.0
	light.omni_attenuation = 0.25
	light.light_energy = 2.2
	light.light_color = Color(1.0, 0.95, 0.85)
	add_child(light)


func _build_body(id: String) -> void:
	var body: Dictionary = BODIES[id]
	var node := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = body.size
	mesh.height = body.size * 2.0
	mesh.radial_segments = 32
	mesh.rings = 16
	node.mesh = mesh
	var material := ShaderMaterial.new()
	material.shader = _planet_shader
	material.set_shader_parameter("base", body.color)
	material.set_shader_parameter("band", body.band)
	material.set_shader_parameter("bands", body.bands)
	material.set_shader_parameter("strength", body.strength)
	material.set_shader_parameter("seed", float(id.hash() % 97))
	node.material_override = material
	add_child(node)
	_bodies[id] = node
	if body.get("ring", false):
		var ring := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(body.size * 4.4, body.size * 4.4)
		ring.mesh = plane
		var shader := Shader.new()
		shader.code = RING_SHADER
		var ring_material := ShaderMaterial.new()
		ring_material.shader = shader
		ring.material_override = ring_material
		# Les anneaux suivent l'inclinaison de Saturne (27°), sans tourner avec elle.
		var holder := Node3D.new()
		holder.rotation.x = deg_to_rad(27.0)
		holder.add_child(ring)
		add_child(holder)
		holder.set_meta("follows", id)
		set_process(true)
		_rings.append(holder)


var _rings: Array[Node3D] = []


func _process(_delta: float) -> void:
	for holder in _rings:
		holder.position = body_position(holder.get_meta("follows"))


func _build_orbits() -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for id: String in BODIES:
		if BODIES[id].has("parent"):
			continue
		_circle(mesh, Vector3.ZERO, BODIES[id].orbit, Color(0.6, 0.8, 1.0, 0.14))
	mesh.surface_end()
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _line_material()
	add_child(node)
	# Orbites des lunes : elles suivent leur planète.
	for id: String in BODIES:
		var body: Dictionary = BODIES[id]
		if not body.has("parent"):
			continue
		var moon_mesh := ImmediateMesh.new()
		moon_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		_circle(moon_mesh, Vector3.ZERO, body.orbit, Color(0.6, 0.8, 1.0, 0.12))
		moon_mesh.surface_end()
		var moon_orbit := MeshInstance3D.new()
		moon_orbit.mesh = moon_mesh
		moon_orbit.material_override = _line_material()
		moon_orbit.set_meta("follows", body.parent)
		add_child(moon_orbit)
		_rings.append(moon_orbit)


func _circle(mesh: ImmediateMesh, center: Vector3, radius: float, color: Color) -> void:
	var segments := 128
	for k in segments:
		var a := TAU * k / segments
		var b := TAU * (k + 1) / segments
		mesh.surface_set_color(color)
		mesh.surface_add_vertex(center + Vector3(cos(a), 0.0, sin(a)) * radius)
		mesh.surface_set_color(color)
		mesh.surface_add_vertex(center + Vector3(cos(b), 0.0, sin(b)) * radius)


func _build_belt() -> void:
	var rock := SphereMesh.new()
	rock.radius = 0.025
	rock.height = 0.05
	rock.radial_segments = 6
	rock.rings = 3
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = rock
	multimesh.instance_count = 420
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for k in multimesh.instance_count:
		var angle := rng.randf() * TAU
		var radius := rng.randf_range(BELT_INNER, BELT_OUTER)
		var spot := Vector3(cos(angle) * radius, rng.randfn() * 0.12, sin(angle) * radius)
		multimesh.set_instance_transform(k, Transform3D(Basis().scaled(Vector3.ONE * rng.randf_range(0.5, 1.6)), spot))
	_belt = MultiMeshInstance3D.new()
	_belt.multimesh = multimesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.55, 0.52, 0.48)
	_belt.material_override = material
	add_child(_belt)


func _line_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material


const PLANET_SHADER := """
shader_type spatial;
uniform vec3 base : source_color;
uniform vec3 band : source_color;
uniform float bands = 4.0;
uniform float strength = 0.4;
uniform float seed = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7)) + seed) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	float n = noise(UV * vec2(18.0, 9.0)) * 0.6 + noise(UV * vec2(40.0, 20.0)) * 0.4;
	float stripes = 0.5 + 0.5 * sin((UV.y + n * 0.06) * bands * 6.2832);
	float mixer = clamp(stripes * strength + (n - 0.5) * 0.35, 0.0, 1.0);
	ALBEDO = mix(base, band, mixer);
	ROUGHNESS = 0.85;
}
"""

const HALO_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	float d = distance(UV, vec2(0.5)) * 2.0;
	float glow = pow(clamp(1.0 - d, 0.0, 1.0), 2.2);
	ALBEDO = vec3(1.0, 0.72, 0.32) * glow * 1.4;
}
"""

const RING_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

void fragment() {
	float d = distance(UV, vec2(0.5)) * 2.0;
	if (d < 0.55 || d > 1.0) {
		discard;
	}
	float t = (d - 0.55) / 0.45;
	float rings = 0.7 + 0.18 * sin(t * 40.0) + 0.12 * sin(t * 11.0 + 1.0);
	float gap = smoothstep(0.6, 0.62, t) * (1.0 - smoothstep(0.66, 0.68, t));
	ALBEDO = vec3(0.78, 0.7, 0.55);
	ALPHA = clamp(rings * 0.5 * (1.0 - gap * 0.85) * smoothstep(0.0, 0.08, t) * (1.0 - smoothstep(0.9, 1.0, t)), 0.0, 1.0);
}
"""
