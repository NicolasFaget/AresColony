class_name RenderBench
extends RefCounted
## Version de développement seulement : si le fichier user://bench existe, la vue de la colonie
## essaie un réglage de rendu à la fois (8 s chacun) et note dans le journal ce qu'il coûte.
## Sert à trouver ce qui ralentit le téléphone. Lire avec : adb logcat | grep BENCH

const SETTLE := 3.0
const MEASURE := 5.0
const CONFIGS := ["base", "fluide", "base", "fluide", "base", "fluide"]

var _world: Node3D
var _sun: DirectionalLight3D
var _env: Environment
var _index := -1
var _time := 0.0
var _frames := 0
var _measured := 0.0
var _cpu := 0.0
var _gpu := 0.0
var _render_cpu := 0.0
var _scale := 1.0
var _aa := Viewport.SCREEN_SPACE_AA_DISABLED
## Vrai pendant l'essai « sans_scripts » : le monde saute ses animations.
var skip_scripts := false


## Dans le journal et dans user://bench.log (le journal du téléphone s'efface vite).
static func _log(line: String) -> void:
	print(line)
	var file := FileAccess.open("user://bench.log", FileAccess.READ_WRITE if FileAccess.file_exists("user://bench.log") else FileAccess.WRITE)
	if file != null:
		file.seek_end()
		file.store_line(line)


static func wanted() -> bool:
	return OS.is_debug_build() and FileAccess.file_exists("user://bench")


func _init(world: Node3D, sun: DirectionalLight3D, env: Environment) -> void:
	_world = world
	_sun = sun
	_env = env
	RenderingServer.viewport_set_measure_render_time(world.get_viewport().get_viewport_rid(), true)
	var vp := world.get_viewport()
	_log("BENCH écran %s · échelle 3D %.2f · mode %d · rendu %s" % [vp.get_visible_rect().size, vp.scaling_3d_scale,
		vp.scaling_3d_mode, RenderingServer.get_video_adapter_name()])
	_log("BENCH départ (%d essais de %d s)" % [CONFIGS.size(), int(SETTLE + MEASURE)])
	_next()


func update(delta: float) -> void:
	if _index >= CONFIGS.size():
		return
	_time += delta
	if _time > SETTLE:
		_frames += 1
		_measured += delta
		_cpu += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		_gpu += RenderingServer.viewport_get_measured_render_time_gpu(_world.get_viewport().get_viewport_rid())
		_render_cpu += RenderingServer.viewport_get_measured_render_time_cpu(_world.get_viewport().get_viewport_rid())
	if _time >= SETTLE + MEASURE:
		_log("BENCH %-16s FPS %5.1f · CPU %5.1f ms · rendu CPU %5.1f ms · GPU %5.1f ms · primitives %d" % [CONFIGS[_index],
			_frames / maxf(_measured, 0.001), _cpu / maxi(_frames, 1), _render_cpu / maxi(_frames, 1), _gpu / maxi(_frames, 1),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])
		_apply(CONFIGS[_index], false)
		_next()


func _next() -> void:
	_index += 1
	_time = 0.0
	_frames = 0
	_measured = 0.0
	_cpu = 0.0
	_gpu = 0.0
	_render_cpu = 0.0
	if _index < CONFIGS.size():
		_apply(CONFIGS[_index], true)
	else:
		_log("BENCH fin")


func _apply(config: String, on: bool) -> void:
	if "+" in config:
		for part in config.split("+"):
			_apply(part, on)
		return
	var viewport := _world.get_viewport()
	match config:
		"echelle_1":
			if on:
				_scale = viewport.scaling_3d_scale
			viewport.scaling_3d_scale = 1.0 if on else _scale
		"rien_scene":
			for node: Node in _world.find_children("*", "VisualInstance3D", true, false):
				if node is GeometryInstance3D:
					(node as Node3D).visible = not on
		"sans_soleil":
			_sun.visible = not on
		"fluide":
			_world.call("apply_quality", 0 if on else GameManager.quality_level())
		"matieres_legeres":
			_swap_shaders(on)
		"sans_reflets":
			_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR if on else Environment.AMBIENT_SOURCE_SKY
			_env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED if on else Environment.REFLECTION_SOURCE_SKY
		"sans_ombres":
			_sun.shadow_enabled = not on
		"echelle_040":
			if on:
				_scale = viewport.scaling_3d_scale
			viewport.scaling_3d_scale = 0.4 if on else _scale
		"sans_sol":
			for node: Node in _world.get_tree().get_nodes_in_group("bench_ground"):
				(node as Node3D).visible = not on
		"sans_modules":
			for node: Node3D in _world.get("_building_nodes"):
				if is_instance_valid(node):
					node.visible = not on
		"sans_brouillard":
			_env.fog_enabled = not on
			_env.adjustment_enabled = not on
			_env.tonemap_mode = Environment.TONE_MAPPER_LINEAR if on else Environment.TONE_MAPPER_ACES
		"sans_particules":
			for node: Node in _world.find_children("*", "GeometryInstance3D", true, false):
				if node is CPUParticles3D or node is GPUParticles3D:
					(node as Node3D).visible = not on
		"sans_fxaa":
			if on:
				_aa = viewport.screen_space_aa
			viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED if on else _aa
		"sans_scripts":
			skip_scripts = on
		"fond_uni":
			_env.background_mode = Environment.BG_COLOR if on else Environment.BG_SKY
			_env.background_color = Color(0.5, 0.3, 0.2)
			_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR if on else Environment.AMBIENT_SOURCE_SKY
			_env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED if on else Environment.REFLECTION_SOURCE_SKY
		"rien_que_ciel", "rien_du_tout_3d":
			for node: Node in _world.find_children("*", "VisualInstance3D", true, false):
				if node != _sun:
					(node as Node3D).visible = not on
			if config == "rien_du_tout_3d":
				_apply("fond_uni", on)
				_sun.visible = not on
		"echelle_025":
			if on:
				_scale = viewport.scaling_3d_scale
			viewport.scaling_3d_scale = 0.25 if on else _scale
		"sans_interface":
			_hide_interface(on)
		"sans_3d":
			_camera(not on)
		"sans_tout":
			_hide_interface(on)
			_camera(not on)


const LITE := {
	"res://world/terrain.gdshader": "res://world/terrain_lite.gdshader",
	"res://world/hull.gdshader": "res://world/hull_lite.gdshader",
	"res://world/solar.gdshader": "res://world/solar_lite.gdshader",
}


## Remplace les shaders du sol, des coques et des panneaux par leur version légère (ou l'inverse).
func _swap_shaders(on: bool) -> void:
	var seen := {}
	for node: Node in _world.find_children("*", "GeometryInstance3D", true, false):
		var materials: Array[Material] = [(node as GeometryInstance3D).material_override]
		if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
			var mesh := (node as MeshInstance3D).mesh
			for i in mesh.get_surface_count():
				materials.append(mesh.surface_get_material(i))
				materials.append((node as MeshInstance3D).get_surface_override_material(i))
		elif node is MultiMeshInstance3D and (node as MultiMeshInstance3D).multimesh != null and (node as MultiMeshInstance3D).multimesh.mesh != null:
			var mesh := (node as MultiMeshInstance3D).multimesh.mesh
			for i in mesh.get_surface_count():
				materials.append(mesh.surface_get_material(i))
		for mat in materials:
			if mat is ShaderMaterial and not seen.has(mat):
				seen[mat] = true
				var path := (mat as ShaderMaterial).shader.resource_path
				for normal: String in LITE:
					if path == (normal if on else LITE[normal]):
						(mat as ShaderMaterial).shader = load(LITE[normal] if on else normal)
	_log("BENCH   %d matériaux changés" % seen.size())


func _camera(on: bool) -> void:
	var camera: Camera3D = _world.get("rig").camera
	if on:
		camera.make_current()
	else:
		camera.clear_current(false)


## Cache tout le 2D de l'écran de jeu (panneaux, onglets, nouvelles).
func _hide_interface(on: bool) -> void:
	var scene := _world.get_tree().current_scene
	if scene == null:
		return
	for child in scene.get_children():
		if child is CanvasItem and not child.is_ancestor_of(_world) and child != _world:
			(child as CanvasItem).visible = not on
		elif child is CanvasLayer:
			(child as CanvasLayer).visible = not on
