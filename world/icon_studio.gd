class_name IconStudio
extends Node
## Studio photo : rend chaque modèle 3D de module une seule fois dans une petite vue isométrique.
## Les listes de l'interface affichent ces vignettes, cohérentes avec le monde 3D.

const ICON_SIZE := Vector2i(192, 160)

static var _instance: IconStudio
var _textures := {}


func _enter_tree() -> void:
	_instance = self


func _exit_tree() -> void:
	if _instance == self:
		_instance = null


## Vignette d'un module (rendue à la première demande).
static func texture(building_id: String) -> Texture2D:
	assert(_instance != null, "IconStudio absent de l'arbre")
	if not _instance._textures.has(building_id):
		_instance._textures[building_id] = _instance._render(building_id)
	return _instance._textures[building_id]


func _render(building_id: String) -> Texture2D:
	var viewport := SubViewport.new()
	viewport.size = ICON_SIZE
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)

	var model := ModelBuilder.building(building_id)
	viewport.add_child(model)
	var bounds := _bounds(model)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.light_energy = 1.2
	sun.light_color = Color(1.0, 0.93, 0.85)
	viewport.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, 150, 0)
	fill.light_energy = 0.5
	viewport.add_child(fill)

	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.75, 0.68)
	env.ambient_light_energy = 0.6
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	viewport.add_child(world_env)

	var pivot := Node3D.new()
	pivot.rotation_degrees = Vector3(CameraRig.PITCH_DEGREES, CameraRig.YAW_DEGREES, 0)
	pivot.position = bounds.get_center()
	viewport.add_child(pivot)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.size = maxf(maxf(bounds.size.x, bounds.size.z), bounds.size.y) * 1.25 + 0.1
	camera.position = Vector3(0, 0, 20)
	camera.far = 60.0
	pivot.add_child(camera)
	return viewport.get_texture()


static func _bounds(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_node: MeshInstance3D = node
		var transform := root.global_transform.affine_inverse() * mesh_node.global_transform if root.is_inside_tree() \
				else _local_transform(root, mesh_node)
		var mesh_box: AABB = transform * mesh_node.get_aabb()
		box = mesh_box if first else box.merge(mesh_box)
		first = false
	return box


static func _local_transform(root: Node3D, node: Node3D) -> Transform3D:
	var t := node.transform
	var parent := node.get_parent()
	while parent != null and parent != root:
		t = (parent as Node3D).transform * t
		parent = parent.get_parent()
	return t
