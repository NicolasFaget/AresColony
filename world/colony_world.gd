class_name ColonyWorld
extends Node3D
## Le monde 3D isométrique : le cratère, les modules, les astronautes, le cycle jour/nuit,
## les tempêtes et le fantôme de placement. Lit l'état du jeu via GameManager ; ne le modifie jamais.

## Toucher sur une case (hors placement), avec le module qui l'occupe (-1 s'il n'y en a pas).
signal cell_tapped(cell: Vector2i, building_index: int)
## Le fantôme de placement a changé de case.
signal ghost_moved(cell: Vector2i)

## Le paysage s'étend bien au-delà du cratère et se perd dans la brume.
const TERRAIN_EXTENT := 36.0
const TERRAIN_STEP := 0.8
const MAX_ASTRONAUTS := 10
const DIRS: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]
## Galeries vitrées : largeur, hauteur.
const CORRIDOR_WIDTH := 0.42
const CORRIDOR_HEIGHT := 0.5
const CORRIDOR_GLASS := Color(0.72, 0.9, 1.0, 0.32)

const DAY_SKY := Color(0.74, 0.5, 0.34)
const NIGHT_SKY := Color(0.03, 0.035, 0.07)
const STORM_SKY := Color(0.62, 0.4, 0.26)

var rig: CameraRig
## Colonie affichée ; par défaut, la partie en cours.
var engine: ColonyEngine

var _engine: ColonyEngine
var _building_nodes: Array[Node3D] = []
var _lights: Array[MeshInstance3D] = []
var _signature := ""
var _ice_root: Node3D
var _ice_visible := false
var _grid: MeshInstance3D
var _ghost: Node3D
var _ghost_def := ""
var _ghost_cell := Vector2i(-1, -1)
var _ghost_pad: MeshInstance3D
var _agents: Array[Dictionary] = []
var _network_root: Node3D
var _flow_on: ShaderMaterial
var _flow_off: ShaderMaterial
## Cases de déplacement : intérieur du réseau (modules raccordés), galeries, extérieur proche.
var _inside_cells := {}
var _link_cells := {}
var _free_cells := {}
var _env: Environment
var _sky_mat: ProceduralSkyMaterial
var _sun: DirectionalLight3D
var _dust: CPUParticles3D
var _motes: CPUParticles3D
var _noise: FastNoiseLite
var _storm_level := 0.0
var _sky_timer := 0.0
var _devil_timer := 12.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_engine = engine if engine != null else GameManager.engine
	_rng.seed = 11
	_build_environment()
	_build_terrain()
	_build_rocks()
	_build_ice()
	_build_grid()
	_flow_on = _flow_material(1.0)
	_flow_off = _flow_material(0.0)
	_network_root = Node3D.new()
	add_child(_network_root)
	rig = CameraRig.new()
	rig.bounds = Rect2(-2, -2, ColonyMap.SIZE + 4, ColonyMap.SIZE + 4)
	add_child(rig)
	rig.position = cell_center(_engine.map.lander_cell + Vector2i.ONE) - Vector3(0.5, 0, 0.5)
	sync_with_game()


func _process(delta: float) -> void:
	_update_sky(delta)
	_update_dust_devils(delta)
	_update_astronauts(delta)


# ---------- Coordonnées ----------

static func cell_center(cell: Vector2i) -> Vector3:
	return Vector3(cell.x + 0.5, 0.0, cell.y + 0.5)


static func footprint_center(cell: Vector2i, size: Vector2i) -> Vector3:
	return Vector3(cell.x + size.x / 2.0, 0.0, cell.y + size.y / 2.0)


func cell_under(screen_position: Vector2) -> Vector2i:
	var hit: Variant = rig.ground_point(screen_position)
	if hit == null:
		return Vector2i(-1, -1)
	return Vector2i(floori(hit.x), floori(hit.z))


# ---------- Synchronisation avec la partie ----------

## Met le monde en accord avec la partie : modules, voyants, glace révélée, astronautes.
func sync_with_game() -> void:
	var signature := JSON.stringify(_engine.state.buildings)
	if signature != _signature:
		_signature = signature
		_rebuild_buildings()
	_update_lights()
	var ice := _engine.state.research_done.has("ice")
	if ice != _ice_visible:
		_ice_visible = ice
		_ice_root.visible = ice
	_sync_astronauts()


func _rebuild_buildings() -> void:
	var previous := _building_nodes.size()
	for node in _building_nodes:
		node.queue_free()
	_building_nodes.clear()
	_lights.clear()
	for i in _engine.state.buildings.size():
		var def := _engine.def_of(i)
		var node := ModelBuilder.bake(_corridor(i) if def.id == "link" else ModelBuilder.building(def.id))
		node.position = footprint_center(_engine.cell_of(i), def.size)
		add_child(node)
		_building_nodes.append(node)
		var light: MeshInstance3D = null
		if def.id != "link":
			light = ModelBuilder.sphere(node, Vector3(def.size.x * 0.32, _model_height(node) + 0.08, def.size.y * 0.32), 0.045, Color.GREEN, Vector3.ONE, 1.2)
			light.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_lights.append(light)
	_rebuild_connectors()
	_rebuild_walk_cells()
	# Un module vient d'être posé : il tombe en place avec un nuage de poussière.
	if _building_nodes.size() == previous + 1 and previous > 0 and _engine.state.buildings.back().id != "link":
		_drop_in(_building_nodes.back())


func _update_lights() -> void:
	for i in mini(_lights.size(), _engine.state.buildings.size()):
		var light := _lights[i]
		if light == null:
			continue
		var color := Color("#5be49b")
		if not _engine.is_linked(i):
			color = Color("#8a8a8a")
		elif _engine.efficiency(i) <= 0.001 and not _engine.def_of(i).inputs.is_empty():
			color = Color("#ff4d4d")
		elif _engine.efficiency(i) < 0.999 and not _engine.def_of(i).inputs.is_empty():
			color = Color("#ffb347")
		light.material_override = ModelBuilder.material(color, 1.2)
		light.visible = color != Color("#5be49b")


static func _model_height(node: Node3D) -> float:
	var top := 0.3
	for mesh_node in node.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mesh_node
		top = maxf(top, (m.transform * m.get_aabb()).end.y)
	return top


func _drop_in(node: Node3D) -> void:
	var target := node.position
	node.position = target + Vector3(0, 2.5, 0)
	node.scale = Vector3(0.6, 1.4, 0.6)
	var tween := node.create_tween().set_parallel()
	tween.tween_property(node, "position", target, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(node, "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT).set_delay(0.3)
	tween.chain().tween_callback(func() -> void: _dust_puff(target, 1.0))


func _dust_puff(at: Vector3, strength: float) -> void:
	var puff := CPUParticles3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.12
	mesh.height = 0.24
	mesh.radial_segments = 6
	mesh.rings = 3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.78, 0.5, 0.34, 0.6)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mat
	puff.mesh = mesh
	puff.amount = int(18 * strength)
	puff.one_shot = true
	puff.explosiveness = 0.9
	puff.lifetime = 1.0
	puff.direction = Vector3.UP
	puff.spread = 80.0
	puff.initial_velocity_min = 0.6 * strength
	puff.initial_velocity_max = 1.6 * strength
	puff.gravity = Vector3(0, -1.0, 0)
	puff.scale_amount_min = 0.5
	puff.scale_amount_max = 1.5 * strength
	puff.position = at + Vector3(0, 0.1, 0)
	add_child(puff)
	puff.emitting = true
	get_tree().create_timer(1.5).timeout.connect(puff.queue_free)


# ---------- Placement ----------

## Mode placement : un fantôme du module suit les touchers ; vert si possible et raccordé,
## jaune si possible mais isolé, rouge si impossible.
func start_placement(def_id: String) -> void:
	stop_placement()
	_ghost_def = def_id
	var def: Defs.Building = _engine.building_defs[def_id]
	_ghost = ModelBuilder.building(def_id)
	add_child(_ghost)
	_ghost_pad = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(def.size)
	_ghost_pad.mesh = plane
	_ghost_pad.position.y = 0.03
	_ghost.add_child(_ghost_pad)
	_grid.visible = true
	var center := rig.position
	move_ghost(Vector2i(floori(center.x), floori(center.z)))


func stop_placement() -> void:
	if _ghost != null:
		_ghost.queue_free()
		_ghost = null
	_ghost_def = ""
	_grid.visible = false


func is_placing() -> bool:
	return _ghost != null


func ghost_cell() -> Vector2i:
	return _ghost_cell


func move_ghost(cell: Vector2i) -> void:
	if _ghost == null:
		return
	var def: Defs.Building = _engine.building_defs[_ghost_def]
	_ghost_cell = cell
	_ghost.position = footprint_center(cell, def.size)
	refresh_ghost()
	ghost_moved.emit(cell)


func refresh_ghost() -> void:
	if _ghost == null:
		return
	var color := Color(0.3, 0.95, 0.55, 0.55)
	if not _engine.placement_problem(_ghost_def, _ghost_cell).is_empty():
		color = Color(1.0, 0.3, 0.3, 0.55)
	elif not _engine.would_connect(_ghost_def, _ghost_cell):
		color = Color(1.0, 0.8, 0.25, 0.55)
	ModelBuilder.make_ghost(_ghost, color)


# ---------- Touchers ----------

func tap(screen_position: Vector2) -> void:
	var cell := cell_under(screen_position)
	if not _engine.map.in_bounds(cell):
		return
	if is_placing():
		move_ghost(cell)
	else:
		cell_tapped.emit(cell, _engine.building_at(cell))


func focus_cell(cell: Vector2i) -> void:
	rig.focus(cell_center(cell))


# ---------- Événements visuels ----------

## Une capsule de ravitaillement se pose près de l'atterrisseur.
func land_capsule() -> void:
	var spot := cell_center(_engine.map.lander_cell) + Vector3(-2.5, 0, -2.0)
	var capsule := ModelBuilder.capsule()
	capsule.position = spot + Vector3(0, 14, 0)
	add_child(capsule)
	var tween := capsule.create_tween()
	tween.tween_property(capsule, "position", spot, 2.2).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func() -> void:
		capsule.get_node("Flame").visible = false
		_dust_puff(spot, 2.0))
	tween.tween_interval(6.0)
	tween.tween_property(capsule, "scale", Vector3.ONE * 0.01, 0.6)
	tween.tween_callback(capsule.queue_free)


## Une fusée d'évacuation décolle de l'atterrisseur.
func launch_evacuation() -> void:
	var start := cell_center(_engine.map.lander_cell) + Vector3(-1.2, 0, 1.5)
	var rocket := ModelBuilder.rocket()
	rocket.position = start
	add_child(rocket)
	_dust_puff(start, 1.6)
	var tween := rocket.create_tween()
	tween.tween_property(rocket, "position", start + Vector3(0, 18, 0), 3.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(rocket.queue_free)


# ---------- Ciel, soleil, tempête ----------

## Couleurs du ciel martien : caramel le jour, bleuté autour du soleil couchant
## (la poussière fine diffuse le bleu vers l'avant), nuit bleu sombre.
func _update_sky(delta: float) -> void:
	var t := _engine.time_of_day()
	var daylight := clampf(cos(TAU * (t - 0.5)) * 1.6 + 0.15, 0.0, 1.0)
	var twilight := clampf(1.0 - absf(cos(TAU * (t - 0.5))) * 3.0, 0.0, 1.0) * (1.0 if daylight > 0.0 else 0.4)
	_storm_level = move_toward(_storm_level, 1.0 if _engine.is_storm() else 0.0, delta * 0.5)
	var storm := _storm_level

	# Le jour, le soleil se lève à l'est (+X) et se couche à l'ouest ; la nuit, une lumière
	# lunaire bleutée (Phobos et Deimos) garde la colonie lisible.
	var angle := TAU * (t - 0.25)
	if daylight > 0.08:
		_sun.rotation = Vector3(-maxf(0.1, sin(angle)) * 1.15, -0.6 + cos(angle) * 0.9, 0)
		_sun.light_energy = lerpf(0.0, 1.35, daylight) * (1.0 - storm * 0.65)
		_sun.light_color = Color(1.0, 0.9, 0.78).lerp(Color(0.78, 0.85, 1.0), twilight * 0.6)
	else:
		_sun.rotation = Vector3(-0.95, -0.2, 0)
		_sun.light_energy = lerpf(0.42, 0.1, daylight / 0.08)
		_sun.light_color = Color(0.62, 0.72, 1.0)
	_env.ambient_light_sky_contribution = lerpf(0.25, 1.0, daylight)
	_env.ambient_light_color = Color(0.38, 0.45, 0.7)
	_env.ambient_light_energy = lerpf(0.9, 0.75, daylight) * (1.0 - storm * 0.25)
	_env.fog_density = 0.006 + 0.014 * storm
	_env.fog_light_color = _sky_mat.sky_horizon_color
	_motes.emitting = daylight > 0.1
	_dust.emitting = storm > 0.5

	# Le ciel (et donc l'éclairage d'ambiance) n'est recalculé que de temps en temps : coûteux sur mobile.
	_sky_timer -= delta
	if _sky_timer > 0.0:
		return
	_sky_timer = 10.0 if OS.has_feature("mobile") else 0.4
	var top := NIGHT_SKY.lerp(DAY_SKY, daylight)
	var horizon := Color(0.1, 0.1, 0.18).lerp(Color(0.9, 0.68, 0.5), daylight)
	horizon = horizon.lerp(Color(0.55, 0.68, 0.9), twilight * 0.7)
	top = top.lerp(STORM_SKY * maxf(daylight, 0.3), storm * 0.85)
	horizon = horizon.lerp(STORM_SKY * maxf(daylight, 0.35), storm * 0.9)
	_sky_mat.sky_top_color = top
	_sky_mat.sky_horizon_color = horizon
	_sky_mat.ground_horizon_color = horizon.darkened(0.2)
	_sky_mat.ground_bottom_color = Color(0.3, 0.14, 0.08).lerp(Color(0.04, 0.03, 0.05), 1.0 - daylight)


func _build_environment() -> void:
	_sky_mat = ProceduralSkyMaterial.new()
	_sky_mat.sky_top_color = DAY_SKY
	_sky_mat.sky_horizon_color = Color(0.9, 0.68, 0.5)
	_sky_mat.ground_bottom_color = Color(0.3, 0.14, 0.08)
	_sky_mat.ground_horizon_color = Color(0.7, 0.5, 0.36)
	_sky_mat.sun_angle_max = 20.0
	_sky_mat.sun_curve = 0.08
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32

	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	_env.tonemap_exposure = 1.05
	_env.tonemap_white = 6.0
	# Halo lumineux : coûteux sur mobile pour peu de différence visible.
	_env.glow_enabled = not OS.has_feature("mobile")
	_env.glow_intensity = 0.55
	_env.glow_bloom = 0.02
	_env.glow_hdr_threshold = 1.1
	_env.fog_enabled = true
	_env.fog_density = 0.006
	_env.fog_sky_affect = 0.3
	_env.adjustment_enabled = true
	_env.adjustment_contrast = 1.08
	_env.adjustment_saturation = 1.12
	var world_env := WorldEnvironment.new()
	world_env.environment = _env
	add_child(world_env)

	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	_sun.shadow_blur = 1.5
	# Sur mobile, une seule cascade d'ombres : nettement moins coûteux.
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL if OS.has_feature("mobile") else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	_sun.directional_shadow_max_distance = 70.0
	_sun.light_angular_distance = 0.6
	add_child(_sun)

	# Poussière soufflée par le vent pendant les tempêtes.
	_dust = _particles(Color(0.85, 0.55, 0.35, 0.35), 0.07, 300, 4.0)
	_dust.emission_box_extents = Vector3(22, 2.5, 22)
	_dust.position = Vector3(ColonyMap.SIZE / 2.0, 2.0, ColonyMap.SIZE / 2.0)
	_dust.direction = Vector3(1, 0, 0.3)
	_dust.spread = 10.0
	_dust.initial_velocity_min = 4.0
	_dust.initial_velocity_max = 8.0
	add_child(_dust)

	# Fines particules en suspension, visibles dans la lumière du jour.
	_motes = _particles(Color(1.0, 0.88, 0.7, 0.3), 0.03, 90, 8.0)
	_motes.emission_box_extents = Vector3(16, 2.0, 16)
	_motes.position = Vector3(ColonyMap.SIZE / 2.0, 1.5, ColonyMap.SIZE / 2.0)
	_motes.direction = Vector3(1, 0.1, 0.4)
	_motes.spread = 40.0
	_motes.initial_velocity_min = 0.1
	_motes.initial_velocity_max = 0.35
	add_child(_motes)


## Point de poussière : disque au bord doux (et non un carré).
func _soft_particle(color: Color) -> StandardMaterial3D:
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
	mat.albedo_color = color
	mat.albedo_texture = texture
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	return mat


func _particles(color: Color, size: float, amount: int, lifetime: float) -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(size, size)
	mesh.material = _soft_particle(color)
	particles.mesh = mesh
	particles.amount = amount
	particles.lifetime = lifetime
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	particles.gravity = Vector3.ZERO
	particles.emitting = false
	return particles


# ---------- Tourbillons de poussière ----------

## De temps en temps, un tourbillon de poussière traverse le paysage (les rovers en ont filmé).
func _update_dust_devils(delta: float) -> void:
	if _engine.state.speed == 0 or _engine.is_night() or _engine.is_storm():
		return
	_devil_timer -= delta * _engine.state.speed
	if _devil_timer > 0.0:
		return
	_devil_timer = _rng.randf_range(25.0, 60.0)
	var c := ColonyMap.SIZE / 2.0
	var angle := _rng.randf() * TAU
	var start := Vector3(c + cos(angle) * 20.0, 0, c + sin(angle) * 20.0)
	var end := Vector3(c - cos(angle + 0.6) * 20.0, 0, c - sin(angle + 0.6) * 20.0)
	var devil := CPUParticles3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.28, 0.28)
	mesh.material = _soft_particle(Color(0.8, 0.52, 0.34, 0.16))
	devil.mesh = mesh
	devil.amount = 90
	devil.lifetime = 2.5
	devil.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	devil.emission_ring_axis = Vector3.UP
	devil.emission_ring_radius = 0.35
	devil.emission_ring_inner_radius = 0.1
	devil.emission_ring_height = 0.1
	devil.direction = Vector3.UP
	devil.spread = 8.0
	devil.gravity = Vector3(0, 0.6, 0)
	devil.initial_velocity_min = 0.8
	devil.initial_velocity_max = 1.4
	devil.tangential_accel_min = 4.0
	devil.tangential_accel_max = 6.0
	devil.radial_accel_min = 0.4
	devil.radial_accel_max = 0.8
	devil.scale_amount_min = 0.6
	devil.scale_amount_max = 1.5
	devil.position = start + Vector3(0, height(start.x, start.z), 0)
	add_child(devil)
	devil.emitting = true
	var tween := devil.create_tween()
	tween.tween_property(devil, "position", end + Vector3(0, height(end.x, end.z), 0), 30.0)
	tween.tween_callback(func() -> void: devil.emitting = false)
	tween.tween_interval(3.0)
	tween.tween_callback(devil.queue_free)


# ---------- Terrain ----------

## Hauteur du sol : plat dans le cratère (on y construit), le rebord, puis des collines au loin.
func height(x: float, z: float) -> float:
	var c := ColonyMap.SIZE / 2.0
	var r := Vector2(x - c, z - c).length()
	var wobble := sin(atan2(z - c, x - c) * 5.0) * 0.6
	var rim := smoothstep(c - 1.0 + wobble, c + 2.5 + wobble, r) * 2.8
	var beyond := smoothstep(c + 2.5, c + 9.0, r)
	var hills := (_noise.get_noise_2d(x, z) * 2.6 + 0.6) * beyond
	var mesas := smoothstep(0.25, 0.4, _noise.get_noise_2d(x * 0.35 + 40.0, z * 0.35)) * 4.5 * smoothstep(c + 14.0, c + 26.0, r)
	var bumps := _noise.get_noise_2d(x * 4.0, z * 4.0) * 0.18 * smoothstep(c - 1.5, c + 1.0, r)
	return rim * (1.0 - beyond * 0.6) + hills + mesas + bumps


func _build_terrain() -> void:
	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.045
	_noise.fractal_octaves = 4
	_noise.seed = 3

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lo := -TERRAIN_EXTENT
	var hi := ColonyMap.SIZE + TERRAIN_EXTENT
	var count := int((hi - lo) / TERRAIN_STEP)
	for i in count:
		for j in count:
			var x0 := lo + i * TERRAIN_STEP
			var z0 := lo + j * TERRAIN_STEP
			var quad := [_vertex(x0, z0), _vertex(x0 + TERRAIN_STEP, z0),
					_vertex(x0 + TERRAIN_STEP, z0 + TERRAIN_STEP), _vertex(x0, z0 + TERRAIN_STEP)]
			for k in [0, 1, 2, 0, 2, 3]:
				st.add_vertex(quad[k])
	st.generate_normals()

	var mat := ShaderMaterial.new()
	mat.shader = preload("res://world/terrain.gdshader")
	mat.set_shader_parameter("noise_large", _noise_texture(0.012, 5, false, 1))
	mat.set_shader_parameter("noise_fine", _noise_texture(0.08, 2, false, 2))
	mat.set_shader_parameter("detail_normal", _noise_texture(0.05, 4, true, 3))
	var terrain := MeshInstance3D.new()
	terrain.mesh = st.commit()
	terrain.material_override = mat
	add_child(terrain)
	_build_pebbles()


func _noise_texture(frequency: float, octaves: int, normal_map: bool, seed_value: int) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.fractal_octaves = octaves
	noise.seed = seed_value
	var texture := NoiseTexture2D.new()
	texture.width = 512
	texture.height = 512
	texture.seamless = true
	texture.noise = noise
	if normal_map:
		texture.as_normal_map = true
		texture.bump_strength = 6.0
	return texture


func _vertex(x: float, z: float) -> Vector3:
	return Vector3(x, height(x, z), z)


## Milliers de petits cailloux (une seule instance multiple : peu coûteux).
func _build_pebbles() -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 5
	mesh.rings = 2
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	var transforms: Array[Transform3D] = []
	var lander := cell_center(_engine.map.lander_cell + Vector2i.ONE) - Vector3(0.5, 0, 0.5)
	for i in 2600:
		var x := _rng.randf_range(-14.0, ColonyMap.SIZE + 14.0)
		var z := _rng.randf_range(-14.0, ColonyMap.SIZE + 14.0)
		if Vector2(x - lander.x, z - lander.z).length() < 2.2:
			continue
		var s := _rng.randf_range(0.015, 0.055) * (2.5 if _rng.randf() < 0.05 else 1.0)
		var basis := Basis.from_euler(Vector3(_rng.randf() * TAU, _rng.randf() * TAU, 0)).scaled(Vector3(s * _rng.randf_range(1.0, 1.6), s * 0.6, s))
		transforms.append(Transform3D(basis, Vector3(x, height(x, z) + s * 0.2, z)))
	multimesh.instance_count = transforms.size()
	for i in transforms.size():
		multimesh.set_instance_transform(i, transforms[i])
	var pebbles := MultiMeshInstance3D.new()
	pebbles.multimesh = multimesh
	pebbles.material_override = ModelBuilder.rock_material(Color("#4e2516"))
	pebbles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pebbles)


## Rochers : tous dans une seule instance multiple (un seul objet à dessiner).
func _build_rocks() -> void:
	var transforms: Array[Transform3D] = []
	for y in ColonyMap.SIZE:
		for x in ColonyMap.SIZE:
			if _engine.map.tile_at(Vector2i(x, y)) == ColonyMap.Tile.ROCK:
				for k in 3:
					var at := cell_center(Vector2i(x, y)) + Vector3(_rng.randf_range(-0.3, 0.3), 0.04, _rng.randf_range(-0.3, 0.3))
					transforms.append(_rock_transform(at, _rng.randf_range(0.15, 0.3)))
	# Blocs sur le rebord du cratère et dans les collines.
	for i in 180:
		var angle := _rng.randf() * TAU
		var radius := _rng.randf_range(ColonyMap.SIZE / 2.0 + 0.3, ColonyMap.SIZE / 2.0 + 16.0)
		var x := ColonyMap.SIZE / 2.0 + cos(angle) * radius
		var z := ColonyMap.SIZE / 2.0 + sin(angle) * radius
		transforms.append(_rock_transform(Vector3(x, height(x, z), z), _rng.randf_range(0.15, 0.6)))
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 7
	mesh.rings = 4
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for i in transforms.size():
		multimesh.set_instance_transform(i, transforms[i])
	var rocks := MultiMeshInstance3D.new()
	rocks.multimesh = multimesh
	rocks.material_override = ModelBuilder.rock_material()
	add_child(rocks)


func _rock_transform(at: Vector3, size: float) -> Transform3D:
	var basis := Basis.from_euler(Vector3(_rng.randf_range(-0.3, 0.3), _rng.randf() * TAU, _rng.randf_range(-0.3, 0.3)))
	basis = basis.scaled(Vector3(_rng.randf_range(0.9, 1.5), _rng.randf_range(0.45, 0.8), _rng.randf_range(0.8, 1.4)) * size)
	return Transform3D(basis, at)


func _build_ice() -> void:
	_ice_root = Node3D.new()
	_ice_root.visible = false
	add_child(_ice_root)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.84, 0.88, 0.28)
	mat.roughness = 0.6
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.2
	# Toutes les plaques de glace dans un seul maillage.
	var plane := PlaneMesh.new()
	plane.size = Vector2(1.0, 1.0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for cell in _engine.map.ice_cells():
		st.append_from(plane, 0, Transform3D(Basis.IDENTITY, cell_center(cell) + Vector3(0, 0.015, 0)))
	var patches := MeshInstance3D.new()
	patches.mesh = st.commit()
	patches.material_override = mat
	patches.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ice_root.add_child(patches)


func _build_grid() -> void:
	_grid = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(ColonyMap.SIZE, ColonyMap.SIZE)
	_grid.mesh = plane
	_grid.position = Vector3(ColonyMap.SIZE / 2.0, 0.02, ColonyMap.SIZE / 2.0)
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
void fragment() {
	vec2 cell = fract(UV * %d.0);
	float line = step(cell.x, 0.04) + step(cell.y, 0.04);
	ALBEDO = vec3(1.0);
	ALPHA = clamp(line, 0.0, 1.0) * 0.25;
}
""" % ColonyMap.SIZE
	var mat := ShaderMaterial.new()
	mat.shader = shader
	_grid.material_override = mat
	_grid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_grid.visible = false
	add_child(_grid)


# ---------- Réseau : galeries vitrées et passages ----------

const SYNERGY_GOLD := Color("#ffc94a")


func _flow_material(active: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://world/flow.gdshader")
	mat.set_shader_parameter("active", active)
	return mat


## Galerie vitrée d'une conduite, avec un tronçon vers chaque voisin (droite, coude, T, croix).
func _corridor(index: int) -> Node3D:
	var root := Node3D.new()
	var cell := _engine.cell_of(index)
	var flow := _flow_on if _engine.is_linked(index) else _flow_off
	_gallery(root, Vector3.ZERO, Vector2(CORRIDOR_WIDTH, CORRIDOR_WIDTH), Vector2i.ZERO, flow)
	for dir in DIRS:
		var other := _engine.building_at(cell + dir)
		if other < 0:
			continue
		var length := 0.5 - CORRIDOR_WIDTH / 2.0
		var center := Vector3(dir.x, 0, dir.y) * (CORRIDOR_WIDTH / 2.0 + length / 2.0)
		var size := Vector2(length if dir.x != 0 else CORRIDOR_WIDTH, length if dir.y != 0 else CORRIDOR_WIDTH)
		_gallery(root, center, size, dir, flow)
		if _engine.state.buildings[other].id != "link":
			_airlock(root, Vector3(dir.x, 0, dir.y) * 0.5, dir)
	return root


## Tronçon de galerie : sol, vitrage, arête de toit, câble d'énergie le long du sol.
func _gallery(parent: Node3D, center: Vector3, size: Vector2, dir: Vector2i, flow: Material) -> void:
	ModelBuilder.box(parent, center + Vector3(0, 0.025, 0), Vector3(size.x, 0.05, size.y), ModelBuilder.CONCRETE)
	var glass := ModelBuilder.box(parent, center + Vector3(0, CORRIDOR_HEIGHT / 2.0 + 0.05, 0),
			Vector3(size.x, CORRIDOR_HEIGHT, size.y), CORRIDOR_GLASS)
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var spine := Vector3(size.x, 0.03, 0.07) if dir.x != 0 else (Vector3(0.07, 0.03, size.y) if dir.y != 0 else Vector3(0.07, 0.03, 0.07))
	ModelBuilder.box(parent, center + Vector3(0, CORRIDOR_HEIGHT + 0.065, 0), spine, ModelBuilder.WHITE)
	if dir == Vector2i.ZERO:
		return
	var side := Vector3(-dir.y, 0, dir.x) * (CORRIDOR_WIDTH / 2.0 - 0.04)
	var length := (size.x if dir.x != 0 else size.y) + 0.02
	var cable := ModelBuilder.cylinder(parent, center + side + Vector3(0, 0.08, 0), 0.022, length, Color.WHITE,
			Vector3(90, 0, 0) if dir.y != 0 else Vector3(0, 0, 90), -1.0, 8)
	cable.material_override = flow
	cable.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Sas : cadre blanc et voyant vert là où une galerie entre dans un module.
func _airlock(parent: Node3D, at: Vector3, dir: Vector2i) -> void:
	var across := Vector3(absf(dir.y), 0, absf(dir.x))
	var w := CORRIDOR_WIDTH + 0.06
	for side in [-1.0, 1.0]:
		ModelBuilder.box(parent, at + across * (w / 2.0) * side + Vector3(0, CORRIDOR_HEIGHT / 2.0 + 0.05, 0),
				Vector3(0.05, CORRIDOR_HEIGHT + 0.06, 0.05), ModelBuilder.WHITE)
	ModelBuilder.box(parent, at + Vector3(0, CORRIDOR_HEIGHT + 0.08, 0), across * w + Vector3(0.05, 0.05, 0.05),
			ModelBuilder.WHITE)
	ModelBuilder.box(parent, at + across * (w / 2.0 + 0.04) + Vector3(0, CORRIDOR_HEIGHT * 0.7, 0),
			Vector3(0.04, 0.04, 0.04), Color("#5be49b"), Vector3.ZERO, 2.0)


## Jonction basse entre deux modules qui se touchent : gaine, deux colliers et câble lumineux.
func _joint(parent: Node3D, dir: Vector2i, flow: Material, synergy := false) -> void:
	var rot := Vector3(90, 0, 0) if dir.y != 0 else Vector3(0, 0, 90)
	var along := Vector3(dir.x, 0, dir.y)
	ModelBuilder.box(parent, Vector3(0, 0.03, 0), Vector3(0.5 if dir.x != 0 else 0.3, 0.06, 0.5 if dir.y != 0 else 0.3), ModelBuilder.CONCRETE)
	ModelBuilder.cylinder(parent, Vector3(0, 0.12, 0), 0.09, 0.5, ModelBuilder.WHITE, rot, -1.0, 12)
	for side in [-0.22, 0.22]:
		ModelBuilder.cylinder(parent, along * side + Vector3(0, 0.12, 0), 0.11, 0.05, ModelBuilder.GREY, rot, -1.0, 12)
	var cable := ModelBuilder.cylinder(parent, Vector3(0, 0.215, 0), 0.025, 0.52, Color.WHITE, rot, -1.0, 8)
	cable.material_override = flow
	cable.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if synergy:
		# Synergie active : bague dorée lumineuse au milieu de la gaine.
		var ring := ModelBuilder.cylinder(parent, Vector3(0, 0.12, 0), 0.15, 0.2, SYNERGY_GOLD, rot, -1.0, 14)
		ring.material_override = ModelBuilder.material(SYNERGY_GOLD, 2.2)
		ModelBuilder.box(parent, Vector3(0, 0.33, 0), Vector3(0.13, 0.13, 0.13), SYNERGY_GOLD, Vector3(45, 45, 0), 2.5)


## Vrai si les modules i et j se touchent et que l'un tire une synergie de l'autre.
func _in_synergy(i: int, j: int) -> bool:
	for pair in [[i, j], [j, i]]:
		var neighbor_id: String = _engine.state.buildings[pair[1]].id
		for synergy: Dictionary in _engine.synergies_of(pair[0]):
			if synergy.neighbor == neighbor_id:
				return true
	return false


## Jonctions entre modules qui se touchent (les conduites ont déjà leurs galeries).
func _rebuild_connectors() -> void:
	for child in _network_root.get_children():
		child.queue_free()
	var pairs := {}
	for i in _engine.state.buildings.size():
		if _engine.state.buildings[i].id == "link":
			continue
		var def := _engine.def_of(i)
		var origin := _engine.cell_of(i)
		for y in def.size.y:
			for x in def.size.x:
				var c := origin + Vector2i(x, y)
				for dir in DIRS:
					var j := _engine.building_at(c + dir)
					if j <= i or _engine.state.buildings[j].id == "link":
						continue
					var key := "%d-%d" % [i, j]
					if not pairs.has(key):
						pairs[key] = { "points": [], "dir": dir, "linked": _engine.is_linked(i),
								"synergy": _engine.is_linked(i) and _in_synergy(i, j) }
					pairs[key].points.append(cell_center(c) + Vector3(dir.x, 0, dir.y) * 0.5)
	for pair: Dictionary in pairs.values():
		var mid := Vector3.ZERO
		for point: Vector3 in pair.points:
			mid += point
		mid /= pair.points.size()
		var dir: Vector2i = pair.dir
		var passage := Node3D.new()
		passage.position = mid
		_joint(passage, dir, _flow_on if pair.linked else _flow_off, pair.synergy)
		_network_root.add_child(ModelBuilder.bake(passage))


# ---------- Astronautes ----------

## Recalcule les cases praticables : intérieur (modules raccordés et galeries), extérieur proche.
func _rebuild_walk_cells() -> void:
	_inside_cells.clear()
	_link_cells.clear()
	_free_cells.clear()
	var near := {}
	for i in _engine.state.buildings.size():
		var def := _engine.def_of(i)
		var origin := _engine.cell_of(i)
		for y in def.size.y:
			for x in def.size.x:
				var c := origin + Vector2i(x, y)
				if _engine.is_linked(i):
					_inside_cells[c] = true
					if def.id == "link":
						_link_cells[c] = true
				for dy in range(-3, 4):
					for dx in range(-3, 4):
						near[c + Vector2i(dx, dy)] = true
	for c: Vector2i in near:
		if _engine.map.is_buildable(c) and _engine.building_at(c) < 0:
			_free_cells[c] = true


func _sync_astronauts() -> void:
	var colonists := _engine.state.colonists
	var wanted := mini(colonists.size(), MAX_ASTRONAUTS)
	while _agents.size() < wanted:
		var a := Astronaut.new(colonists[_agents.size()].role)
		a.position = cell_center(_engine.map.lander_cell)
		add_child(a)
		_agents.append({ "node": a, "mode": "inside", "wait": _rng.randf_range(0.5, 4.0), "trips": 0 })
	while _agents.size() > wanted:
		_agents.pop_back().node.queue_free()


func _update_astronauts(delta: float) -> void:
	var speed := float(_engine.state.speed)
	for agent in _agents:
		var a: Astronaut = agent.node
		a.update(delta, speed)
		var cell := Vector2i(floori(a.position.x), floori(a.position.z))
		# Dans un module, on ne le voit pas ; dans une galerie vitrée ou dehors, si.
		a.visible = not _inside_cells.has(cell) or _link_cells.has(cell)
		a.position.y = 0.05 if _link_cells.has(cell) else 0.0
		if a.is_walking() or speed <= 0.0:
			continue
		agent.wait -= delta * speed
		if agent.wait <= 0.0:
			_plan(agent, cell)


## Choisit la prochaine promenade : dans le réseau, sortie, balade dehors ou retour à l'abri.
func _plan(agent: Dictionary, cell: Vector2i) -> void:
	var a: Astronaut = agent.node
	agent.wait = _rng.randf_range(1.0, 4.0)
	# Le terrain a changé sous ses pieds (module construit ou démoli) : retour à l'atterrisseur.
	var lost: bool = (agent.mode == "eva" and not _free_cells.has(cell)) \
			or (agent.mode == "inside" and not _inside_cells.has(cell))
	if lost:
		a.position = cell_center(_engine.map.lander_cell)
		agent.mode = "inside"
		return
	var cells: Array[Vector2i] = []
	if agent.mode == "inside":
		if not _engine.is_night() and _rng.randf() < 0.45:
			var door := _random_door()
			if not door.is_empty():
				cells = _path(cell, door[0], _inside_cells)
				if not cells.is_empty() or cell == door[0]:
					cells.append(door[1])
					agent.mode = "eva"
					agent.trips = 0
		if cells.is_empty() and agent.mode == "inside":
			var targets := _inside_cells.keys()
			cells = _path(cell, targets[_rng.randi_range(0, targets.size() - 1)], _inside_cells)
	else:
		if _engine.is_night() or agent.trips >= 2:
			var door := _random_door()
			if not door.is_empty():
				cells = _path(cell, door[1], _free_cells)
				if not cells.is_empty() or cell == door[1]:
					cells.append(door[0])
					agent.mode = "inside"
		else:
			var targets := _free_cells.keys()
			cells = _path(cell, targets[_rng.randi_range(0, targets.size() - 1)], _free_cells)
			agent.trips += 1
	var points: Array[Vector3] = []
	for c in cells:
		var jitter := Vector3.ZERO if _inside_cells.has(c) else Vector3(_rng.randf_range(-0.15, 0.15), 0, _rng.randf_range(-0.15, 0.15))
		points.append(cell_center(c) + jitter)
	a.path = points


## Une « porte » au hasard : [case d'un module raccordé, case libre voisine].
func _random_door() -> Array:
	var doors: Array = []
	for c: Vector2i in _inside_cells:
		if _link_cells.has(c):
			continue
		for dir in DIRS:
			if _free_cells.has(c + dir):
				doors.append([c, c + dir])
	return doors[_rng.randi_range(0, doors.size() - 1)] if not doors.is_empty() else []


## Plus court chemin sur la grille (4 voisins) parmi les cases autorisées, sans la case de départ.
func _path(from: Vector2i, to: Vector2i, allowed: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if from == to or not allowed.has(to):
		return result
	var previous := { from: from }
	var queue: Array[Vector2i] = [from]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		if c == to:
			break
		for dir in DIRS:
			var n := c + dir
			if allowed.has(n) and not previous.has(n):
				previous[n] = c
				queue.append(n)
	if not previous.has(to):
		return result
	var step := to
	while step != from:
		result.push_front(step)
		step = previous[step]
	return result
