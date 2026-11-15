class_name WorldScenery
extends RefCounted
## Ce qui distingue chaque monde : geysers d'Encelade, averses de méthane de Titan, taches
## brillantes de Cérès ; et le ciel du mode photo (Jupiter vue d'Europe, Saturne vue d'Encelade,
## la Terre et Phobos vues de Mars, les étoiles des mondes sans air).

## Le ciel du mode photo est posé à cette distance, autour du point visé.
const SKY_DISTANCE := 150.0
## Titan : une averse de 45 s toutes les 150 s (temps de jeu ×1).
const RAIN_PERIOD := 150.0
const RAIN_LENGTH := 45.0

## Intensité de l'averse en cours sur Titan (0 à 1), pour épaissir la brume.
var rain := 0.0

var _world: Node3D
var _engine: ColonyEngine
var _planet := ""
var _sky: Node3D
var _rain: CPUParticles3D
var _rain_clock := 30.0
var _stars: MeshInstance3D


func _init(world: Node3D, engine: ColonyEngine) -> void:
	_world = world
	_engine = engine
	_planet = engine.planet_id()
	_sky = Node3D.new()
	_sky.visible = false
	world.add_child(_sky)
	match _planet:
		"enceladus":
			_build_geysers()
			_add_saturn()
			_add_stars()
		"europa":
			_add_jupiter()
			_add_stars()
		"ceres":
			_build_bright_spots()
			_add_stars()
		"titan":
			_build_rain()
		"mars":
			_add_mars_sky()


## Ciel du mode photo : visible seulement quand la caméra se redresse.
func set_photo(on: bool) -> void:
	_sky.visible = on


func update(delta: float, rig: Node3D) -> void:
	if _sky.visible:
		_sky.position = rig.position
		if _planet == "mars" and _stars != null:
			_stars.visible = _engine.is_night()
	if _rain != null:
		_rain_clock += delta * float(_engine.state.speed)
		var phase := fmod(_rain_clock, RAIN_PERIOD)
		var raining := phase < RAIN_LENGTH and _engine.state.speed > 0
		rain = move_toward(rain, 1.0 if raining else 0.0, delta * 0.3)
		_rain.emitting = raining
		_rain.position = rig.position + Vector3(0, 9.0, 0)
		_rain.speed_scale = clampf(float(_engine.state.speed), 0.0, 2.0)


# ---------- Décor au sol ----------

## Encelade : les panaches jaillissent des « rayures du tigre », au pôle sud (Cassini, 2005).
func _build_geysers() -> void:
	# Sur les plaques de glace bleutée les plus éloignées de l'atterrisseur (les « rayures » du jeu).
	var lander := Vector2(_engine.map.lander_cell)
	var cells: Array = _engine.map.ice_cells()
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return Vector2(a).distance_to(lander) > Vector2(b).distance_to(lander))
	var spots: Array[Vector3] = []
	for cell: Vector2i in cells:
		var at := Vector3(cell.x + 0.5, 0, cell.y + 0.5)
		var apart := true
		for other in spots:
			apart = apart and other.distance_to(at) > 6.0
		if apart:
			spots.append(at)
		if spots.size() >= 3:
			break
	for spot in spots:
		var plume := _soft_particles(Color(0.72, 0.85, 1.0, 0.32), 1.1, 90, 7.0)
		plume.position = spot + Vector3(0, _world.height(spot.x, spot.z), 0)
		plume.direction = Vector3.UP
		plume.spread = 5.0
		plume.initial_velocity_min = 2.4
		plume.initial_velocity_max = 3.4
		# Gravité très faible (1 % de celle de la Terre) : le panache monte haut et s'étale.
		plume.gravity = Vector3(0.12, -0.12, 0.05)
		var growth := Curve.new()
		growth.add_point(Vector2(0.0, 0.3))
		growth.add_point(Vector2(1.0, 4.0))
		plume.scale_amount_curve = growth
		plume.emitting = true
		_world.add_child(plume)


## Cérès : taches très brillantes de sels (carbonate de sodium) au fond du cratère Occator (Dawn, 2015).
func _build_bright_spots() -> void:
	var c := ColonyMap.SIZE / 2.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.97, 0.97, 0.95)
	mat.roughness = 0.9
	mat.emission_enabled = true
	mat.emission = Color(0.9, 0.9, 0.88)
	mat.emission_energy_multiplier = 0.25
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for center: Vector2 in [Vector2(c + 14, c - 11), Vector2(c + 18, c - 15)]:
		for k in 5:
			var p := center + Vector2(rng.randf_range(-1.6, 1.6), rng.randf_range(-1.6, 1.6))
			var disc := CylinderMesh.new()
			disc.top_radius = rng.randf_range(0.5, 1.4)
			disc.bottom_radius = disc.top_radius
			disc.height = 0.3
			disc.radial_segments = 12
			disc.rings = 1
			st.append_from(disc, 0, Transform3D(Basis.IDENTITY, Vector3(p.x, _world.height(p.x, p.y) - 0.1, p.y)))
	var spots := MeshInstance3D.new()
	spots.mesh = st.commit()
	spots.material_override = mat
	spots.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_world.add_child(spots)


## Titan : de grosses gouttes de méthane qui tombent lentement (gravité faible, air dense).
func _build_rain() -> void:
	_rain = CPUParticles3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.025, 0.32)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.62, 0.48, 0.3, 0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mesh.material = mat
	_rain.mesh = mesh
	_rain.amount = 260
	_rain.lifetime = 4.0
	_rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_rain.emission_box_extents = Vector3(16, 0.5, 16)
	_rain.direction = Vector3(0.1, -1, 0)
	_rain.spread = 2.0
	_rain.initial_velocity_min = 2.0
	_rain.initial_velocity_max = 2.6
	_rain.gravity = Vector3(0, -0.15, 0)
	_rain.local_coords = false
	_rain.emitting = false
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_world.add_child(_rain)


func _soft_particles(color: Color, size: float, amount: int, lifetime: float) -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(size, size)
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	gradient.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.4), Color(1, 1, 1, 0)])
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
	particles.amount = amount
	particles.lifetime = lifetime
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 0.3
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.15, 1.0])
	fade.colors = PackedColorArray([Color(color, 0.0), color, Color(color, 0.0)])
	particles.color_ramp = fade
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return particles


# ---------- Ciel du mode photo ----------

## Direction dans le ciel : azimut compté depuis le regard initial de la caméra, hauteur en degrés.
static func _sky_direction(azimuth: float, elevation: float) -> Vector3:
	# Regard initial de la caméra : vers +X et −Z (lacet de −45°).
	var a := deg_to_rad(-45.0 - azimuth)
	var e := deg_to_rad(elevation)
	return Vector3(cos(e) * cos(a), sin(e), cos(e) * sin(a))


func _body(radius: float, direction: Vector3, shader_code: String, params := {}) -> MeshInstance3D:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 48
	sphere.rings = 24
	var shader := Shader.new()
	shader.code = shader_code
	var mat := ShaderMaterial.new()
	mat.shader = shader
	for key: String in params:
		mat.set_shader_parameter(key, params[key])
	var body := MeshInstance3D.new()
	body.mesh = sphere
	body.material_override = mat
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.position = direction * SKY_DISTANCE
	_sky.add_child(body)
	return body


const BODY_SHADER := """
shader_type spatial;
render_mode unshaded, fog_disabled, shadows_disabled;
uniform vec3 light_dir = vec3(0.5, 0.4, 0.6);
uniform vec3 light_color : source_color = vec3(0.86, 0.74, 0.6);
uniform vec3 dark_color : source_color = vec3(0.62, 0.45, 0.32);
uniform float bands = 22.0;
uniform float spot = 0.0;
varying vec3 local_pos;
varying vec3 world_normal;
void vertex() {
	local_pos = normalize(VERTEX);
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	float wobble = sin(local_pos.x * 7.0 + local_pos.z * 3.0) * 0.015;
	float b = sin((local_pos.y + wobble) * bands) * 0.5 + 0.5;
	vec3 col = mix(light_color, dark_color, b * (bands > 0.0 ? 1.0 : 0.0));
	// Grande Tache rouge (Jupiter).
	float red = (1.0 - smoothstep(0.0, 0.1, length(vec2((local_pos.x - 0.3) * 0.55, local_pos.y + 0.35)))) * spot;
	col = mix(col, vec3(0.78, 0.36, 0.22), red);
	float light = clamp(dot(world_normal, normalize(light_dir)) * 1.15 + 0.05, 0.03, 1.0);
	ALBEDO = col * light;
}
"""


## Europe : Jupiter occupe 12° du ciel, 24 fois la Pleine Lune vue de la Terre.
func _add_jupiter() -> void:
	var dir := _sky_direction(10.0, 18.0)
	_body(SKY_DISTANCE * tan(deg_to_rad(6.0)), dir, BODY_SHADER, {
		"light_dir": (-dir).rotated(Vector3.UP, 1.0).normalized(), "spot": 1.0,
	}).rotation_degrees = Vector3(0, 0, 3)


## Encelade : Saturne s'étale sur près de 30° ; ses anneaux sont vus par la tranche, car
## Encelade tourne dans leur plan.
func _add_saturn() -> void:
	var dir := _sky_direction(-8.0, 13.0)
	var radius := SKY_DISTANCE * tan(deg_to_rad(11.0))
	# Éclairée de trois quarts, côté colonie.
	var lit := (-dir + Vector3(0.0, 0.0, 0.0)).rotated(Vector3.UP, 0.9).normalized()
	var saturn := _body(radius, dir, BODY_SHADER, {
		"light_dir": lit, "light_color": Color(0.92, 0.85, 0.66),
		"dark_color": Color(0.8, 0.7, 0.5), "bands": 14.0,
	})
	var ring := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(radius * 4.6, radius * 4.6)
	ring.mesh = plane
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, fog_disabled, shadows_disabled, cull_disabled, depth_draw_never;
void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float band = smoothstep(0.5, 0.53, r) * (1.0 - smoothstep(0.96, 1.0, r));
	float gap = 1.0 - (smoothstep(0.78, 0.8, r) - smoothstep(0.82, 0.84, r)) * 0.85;
	ALBEDO = vec3(0.86, 0.8, 0.66);
	ALPHA = band * gap * (0.55 + 0.25 * sin(r * 90.0));
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	ring.material_override = mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Presque par la tranche (incliné de 3° pour rester visible).
	ring.rotation_degrees = Vector3(3, 0, 8)
	saturn.add_child(ring)


## Mars : la Terre, une petite étoile bleue ; Phobos, une lune grise et cabossée.
func _add_mars_sky() -> void:
	var earth := _body(0.55, _sky_direction(-20.0, 14.0), BODY_SHADER, {
		"light_dir": Vector3(0, 0, 1), "light_color": Color(0.7, 0.85, 1.0), "dark_color": Color(0.7, 0.85, 1.0), "bands": 0.0,
	})
	earth.material_override.set_shader_parameter("light_dir", -earth.position.normalized())
	_body(1.4, _sky_direction(25.0, 30.0), BODY_SHADER, {
		"light_dir": Vector3(-0.6, 0.2, 0.3), "light_color": Color(0.55, 0.5, 0.46), "dark_color": Color(0.45, 0.41, 0.38), "bands": 3.0,
	})
	_add_stars()


func _add_stars() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	for k in 500:
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.02, 1.0), rng.randf_range(-1, 1)).normalized()
		points.append(dir * (SKY_DISTANCE + 20.0))
		var shade := rng.randf_range(0.35, 1.0)
		colors.append(Color(shade, shade, shade * rng.randf_range(0.9, 1.1)))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, arrays)
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, fog_disabled, shadows_disabled;
void vertex() { POINT_SIZE = 2.0; }
void fragment() { ALBEDO = COLOR.rgb; }
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	_stars = MeshInstance3D.new()
	_stars.mesh = mesh
	_stars.material_override = mat
	_stars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sky.add_child(_stars)
