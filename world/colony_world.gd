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
const DIRS: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]
## Galeries vitrées : largeur, hauteur.
const CORRIDOR_WIDTH := 0.42
const CORRIDOR_HEIGHT := 0.5
const CORRIDOR_GLASS := Color(0.72, 0.9, 1.0, 0.32)

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
var _agents: Array[Dictionary] = []
var _network_root: Node3D
var _flow_on: ShaderMaterial
var _flow_off: ShaderMaterial
## Cases de déplacement : intérieur du réseau (modules raccordés), galeries, extérieur proche.
var _inside_cells := {}
var _link_cells := {}
var _free_cells := {}
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
		var node := _corridor(i) if def.id == "link" else ModelBuilder.building(def.id)
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


# ---------- Réseau : galeries vitrées et passages ----------

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
func _joint(parent: Node3D, dir: Vector2i, flow: Material) -> void:
	var rot := Vector3(90, 0, 0) if dir.y != 0 else Vector3(0, 0, 90)
	var along := Vector3(dir.x, 0, dir.y)
	ModelBuilder.box(parent, Vector3(0, 0.03, 0), Vector3(0.5 if dir.x != 0 else 0.3, 0.06, 0.5 if dir.y != 0 else 0.3), ModelBuilder.CONCRETE)
	ModelBuilder.cylinder(parent, Vector3(0, 0.12, 0), 0.09, 0.5, ModelBuilder.WHITE, rot, -1.0, 12)
	for side in [-0.22, 0.22]:
		ModelBuilder.cylinder(parent, along * side + Vector3(0, 0.12, 0), 0.11, 0.05, ModelBuilder.GREY, rot, -1.0, 12)
	var cable := ModelBuilder.cylinder(parent, Vector3(0, 0.215, 0), 0.025, 0.52, Color.WHITE, rot, -1.0, 8)
	cable.material_override = flow
	cable.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


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
						pairs[key] = { "points": [], "dir": dir, "linked": _engine.is_linked(i) }
					pairs[key].points.append(cell_center(c) + Vector3(dir.x, 0, dir.y) * 0.5)
	for pair: Dictionary in pairs.values():
		var mid := Vector3.ZERO
		for point: Vector3 in pair.points:
			mid += point
		mid /= pair.points.size()
		var dir: Vector2i = pair.dir
		var passage := Node3D.new()
		passage.position = mid
		_network_root.add_child(passage)
		_joint(passage, dir, _flow_on if pair.linked else _flow_off)


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
