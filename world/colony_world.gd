class_name ColonyWorld
extends Node3D
## Le monde 3D isométrique : le cratère, les modules, les astronautes, le cycle jour/nuit,
## les tempêtes et le fantôme de placement. Lit l'état du jeu via GameManager ; ne le modifie jamais.

## Toucher sur une case (hors placement), avec le module qui l'occupe (-1 s'il n'y en a pas).
signal cell_tapped(cell: Vector2i, building_index: int)
## Le fantôme de placement a changé de case.
signal ghost_moved(cell: Vector2i)

const MARGIN := 9.0
const TERRAIN_STEP := 0.5
const BASE_Y := -6.0
const MAX_ASTRONAUTS := 10

const DAY_SKY := Color(0.78, 0.55, 0.38)
const NIGHT_SKY := Color(0.05, 0.06, 0.11)
const STORM_SKY := Color(0.62, 0.42, 0.28)

var rig: CameraRig

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
var _astronauts: Array[Node3D] = []
var _env: Environment
var _sun: DirectionalLight3D
var _dust: CPUParticles3D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_engine = GameManager.engine
	_rng.seed = 11
	_build_environment()
	_build_terrain()
	_build_rocks()
	_build_ice()
	_build_grid()
	rig = CameraRig.new()
	rig.bounds = Rect2(-2, -2, ColonyMap.SIZE + 4, ColonyMap.SIZE + 4)
	add_child(rig)
	rig.position = cell_center(_engine.map.lander_cell + Vector2i.ONE) - Vector3(0.5, 0, 0.5)
	sync_with_game()


func _process(delta: float) -> void:
	_update_sky()
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
		var node := ModelBuilder.building(def.id)
		node.position = footprint_center(_engine.cell_of(i), def.size)
		add_child(node)
		_building_nodes.append(node)
		var light: MeshInstance3D = null
		if not def.inputs.is_empty() or def.id != "link":
			light = ModelBuilder.sphere(node, Vector3(def.size.x * 0.32, _model_height(node) + 0.08, def.size.y * 0.32), 0.045, Color.GREEN, Vector3.ONE, 1.2)
			light.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_lights.append(light)
	# Un module vient d'être posé : il tombe en place avec un nuage de poussière.
	if _building_nodes.size() == previous + 1 and previous > 0:
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

func _update_sky() -> void:
	var t := _engine.time_of_day()
	var daylight := clampf(cos(TAU * (t - 0.5)) * 1.6 + 0.15, 0.0, 1.0)
	var storm := 1.0 if _engine.is_storm() else 0.0
	var sky := NIGHT_SKY.lerp(DAY_SKY, daylight).lerp(STORM_SKY * maxf(daylight, 0.35), storm * 0.8)
	_env.background_color = sky
	_env.ambient_light_color = Color(0.4, 0.45, 0.65).lerp(Color(0.95, 0.78, 0.65), daylight)
	_env.ambient_light_energy = lerpf(0.3, 0.42, daylight)
	_env.fog_density = lerpf(_env.fog_density, 0.018 * storm, 0.02)
	_env.fog_light_color = sky
	# Le soleil se lève à l'est (+X), culmine à midi, se couche à l'ouest.
	var angle := TAU * (t - 0.25)
	_sun.rotation = Vector3(-maxf(0.12, sin(angle)) * 1.2, -0.6 + cos(angle) * 0.9, 0)
	_sun.light_energy = lerpf(0.0, 1.0, daylight) * (1.0 - storm * 0.6)
	_dust.emitting = storm > 0.0


func _build_environment() -> void:
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = DAY_SKY
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.tonemap_exposure = 1.0
	_env.glow_enabled = true
	_env.glow_intensity = 0.5
	_env.glow_hdr_threshold = 1.2
	_env.fog_enabled = true
	_env.fog_density = 0.0
	var world_env := WorldEnvironment.new()
	world_env.environment = _env
	add_child(world_env)

	_sun = DirectionalLight3D.new()
	_sun.light_color = Color(1.0, 0.9, 0.78)
	_sun.shadow_enabled = true
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	_sun.directional_shadow_max_distance = 80.0
	add_child(_sun)

	# Poussière soufflée par le vent pendant les tempêtes.
	_dust = CPUParticles3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.08, 0.08)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.55, 0.35, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mesh.material = mat
	_dust.mesh = mesh
	_dust.amount = 400
	_dust.lifetime = 4.0
	_dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_dust.emission_box_extents = Vector3(18, 2, 18)
	_dust.position = Vector3(ColonyMap.SIZE / 2.0, 2.0, ColonyMap.SIZE / 2.0)
	_dust.direction = Vector3(1, 0, 0.3)
	_dust.spread = 10.0
	_dust.gravity = Vector3.ZERO
	_dust.initial_velocity_min = 4.0
	_dust.initial_velocity_max = 8.0
	_dust.emitting = false
	add_child(_dust)


# ---------- Terrain ----------

## Hauteur du sol : plat dans le cratère (on y construit), puis le rebord qui monte.
func height(x: float, z: float) -> float:
	var c := ColonyMap.SIZE / 2.0
	var r := Vector2(x - c, z - c).length()
	var wobble := sin(atan2(z - c, x - c) * 5.0) * 0.6
	var rim := smoothstep(c - 1.5 + wobble, c + 2.5 + wobble, r) * 2.6
	var outside := smoothstep(c + 2.5, c + 7.0, r) * -1.0
	var bumps := 0.12 * (sin(x * 1.7) * cos(z * 1.3) + sin((x + z) * 0.9)) * smoothstep(c - 2.0, c + 1.0, r)
	return rim + outside + bumps


func _ground_color(x: float, z: float, y: float) -> Color:
	var n := 0.04 * (sin(x * 3.1 + z * 1.7) + sin(x * 0.7 - z * 2.3))
	var base := Color(0.64, 0.29, 0.15).lightened(n)
	return base.lerp(Color(0.45, 0.2, 0.12), clampf(y / 2.6, 0.0, 1.0)).lerp(Color(0.55, 0.26, 0.15), clampf(-y, 0.0, 1.0))


func _build_terrain() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lo := -MARGIN
	var hi := ColonyMap.SIZE + MARGIN
	var count := int((hi - lo) / TERRAIN_STEP)
	for i in count:
		for j in count:
			var x0 := lo + i * TERRAIN_STEP
			var z0 := lo + j * TERRAIN_STEP
			var quad := [_vertex(x0, z0), _vertex(x0 + TERRAIN_STEP, z0),
					_vertex(x0 + TERRAIN_STEP, z0 + TERRAIN_STEP), _vertex(x0, z0 + TERRAIN_STEP)]
			for k in [0, 1, 2, 0, 2, 3]:
				var v: Vector3 = quad[k]
				st.set_color(_ground_color(v.x, v.z, v.y))
				st.add_vertex(v)
	# Coupe de la maquette sur les deux faces visibles.
	for i in count:
		var a := lo + i * TERRAIN_STEP
		var b := a + TERRAIN_STEP
		_skirt(st, Vector3(a, height(a, hi), hi), Vector3(b, height(b, hi), hi))
		_skirt(st, Vector3(lo, height(lo, b), b), Vector3(lo, height(lo, a), a))
	st.generate_normals()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	var terrain := MeshInstance3D.new()
	terrain.mesh = st.commit()
	terrain.material_override = mat
	add_child(terrain)


func _vertex(x: float, z: float) -> Vector3:
	return Vector3(x, height(x, z), z)


func _skirt(st: SurfaceTool, top_a: Vector3, top_b: Vector3) -> void:
	var bottom_a := Vector3(top_a.x, BASE_Y, top_a.z)
	var bottom_b := Vector3(top_b.x, BASE_Y, top_b.z)
	for v: Vector3 in [top_a, bottom_b, top_b, top_a, bottom_a, bottom_b]:
		var band := int(floor(-v.y * 1.4 + sin(v.x + v.z) * 0.5)) % 3
		var color: Color = [Color(0.5, 0.27, 0.17), Color(0.42, 0.22, 0.14), Color(0.58, 0.33, 0.2)][absi(band)]
		st.set_color(color.darkened(clampf(-v.y / 14.0, 0.0, 0.4)))
		st.add_vertex(v)


func _build_rocks() -> void:
	for y in ColonyMap.SIZE:
		for x in ColonyMap.SIZE:
			if _engine.map.tile_at(Vector2i(x, y)) == ColonyMap.Tile.ROCK:
				for k in 2:
					var rock := ModelBuilder.rock(_rng)
					rock.position = cell_center(Vector2i(x, y)) + Vector3(_rng.randf_range(-0.25, 0.25), 0.05, _rng.randf_range(-0.25, 0.25))
					add_child(rock)
	# Rochers épars sur le rebord, pour le décor.
	for i in 60:
		var angle := _rng.randf() * TAU
		var radius := _rng.randf_range(ColonyMap.SIZE / 2.0 + 0.5, ColonyMap.SIZE / 2.0 + 6.0)
		var x := ColonyMap.SIZE / 2.0 + cos(angle) * radius
		var z := ColonyMap.SIZE / 2.0 + sin(angle) * radius
		var rock := ModelBuilder.rock(_rng, Color("#6a3826"))
		rock.position = Vector3(x, height(x, z), z)
		add_child(rock)


func _build_ice() -> void:
	_ice_root = Node3D.new()
	_ice_root.visible = false
	add_child(_ice_root)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.7, 0.86, 1.0, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.2
	for cell in _engine.map.ice_cells():
		var patch := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(1.0, 1.0)
		patch.mesh = plane
		patch.material_override = mat
		patch.position = cell_center(cell) + Vector3(0, 0.015, 0)
		patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_ice_root.add_child(patch)


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


# ---------- Astronautes ----------

func _sync_astronauts() -> void:
	var wanted := mini(_engine.state.colonists.size(), MAX_ASTRONAUTS)
	while _astronauts.size() < wanted:
		var a := ModelBuilder.astronaut()
		a.position = cell_center(_engine.map.lander_cell) + Vector3(_rng.randf_range(-1, 2), 0, 2.2)
		a.set_meta("target", a.position)
		a.set_meta("wait", _rng.randf_range(0.0, 2.0))
		add_child(a)
		_astronauts.append(a)
	while _astronauts.size() > wanted:
		_astronauts.pop_back().queue_free()


## Les astronautes vont d'un module à l'autre, et rentrent la nuit.
func _update_astronauts(delta: float) -> void:
	var speed := 0.9 * maxf(1.0, _engine.state.speed)
	if _engine.state.speed == 0:
		return
	for a in _astronauts:
		var target: Vector3 = a.get_meta("target")
		var to := target - a.position
		if to.length() < 0.05:
			var wait: float = a.get_meta("wait") - delta
			a.set_meta("wait", wait)
			if wait <= 0.0:
				a.set_meta("target", _wander_target())
				a.set_meta("wait", _rng.randf_range(1.0, 4.0))
			continue
		var step := minf(to.length(), speed * delta)
		a.position += to.normalized() * step
		a.rotation.y = atan2(to.x, to.z)
		a.position.y = absf(sin(Time.get_ticks_msec() / 120.0)) * 0.03
		a.visible = not _engine.is_night() or to.length() > 0.5


func _wander_target() -> Vector3:
	var n := _engine.state.buildings.size()
	var i := _rng.randi_range(0, n - 1)
	var def := _engine.def_of(i)
	var center := footprint_center(_engine.cell_of(i), def.size)
	return center + Vector3(def.size.x * 0.5 + 0.25, 0, _rng.randf_range(-0.4, 0.4))
