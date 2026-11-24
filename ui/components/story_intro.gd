class_name StoryIntro
extends Control
## Introduction d'une nouvelle partie : quatre plans en 3D (la Terre, le décollage, le voyage,
## l'arrivée sur Mars), une phrase par plan (voir Story.INTRO). Un toucher passe au plan suivant,
## le bouton « Passer » saute tout. Émet `done` à la fin, après un fondu.

signal done

## Durée d'un plan, en secondes, s'il n'est pas abrégé.
const SHOT_SECONDS := 7.0
const FADE_SECONDS := 0.6
const EARTH := Vector3.ZERO
## Rotation de départ de la Terre : l'Europe et l'Afrique face à la caméra du premier plan.
const EARTH_TURN := -3.35
const MARS := Vector3(60.0, 0.0, 0.0)

var _viewport: SubViewport
var _camera: Camera3D
var _sun: DirectionalLight3D
## Orientation du soleil pour chaque plan : la planète montrée est éclairée presque de face.
const SUN_ANGLES := [Vector3(-20, -25, 0), Vector3(-25, 55, 0), Vector3(-20, -65, 0), Vector3(-30, 15, 0)]
var _earth: MeshInstance3D
var _mars: MeshInstance3D
var _rocket: Node3D
var _capsule: Node3D
var _text: Label
var _fade: ColorRect
var _shot := 0
var _t := 0.0
var _leaving := false


static func open(host: Control) -> StoryIntro:
	var intro := StoryIntro.new()
	host.add_child(intro)
	return intro


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var back := ColorRect.new()
	back.color = Color(0.008, 0.014, 0.03)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)

	var container := SubViewportContainer.new()
	# La taille de la vue est tenue à la main (voir _process) : l'image n'est jamais étirée.
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_2X
	container.add_child(_viewport)
	add_child(container)
	_build_scene()

	# Un voile sombre en bas, pour que le texte se lise sur n'importe quel plan.
	var shade := TextureRect.new()
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0, 0, 0, 0))
	gradient.set_color(1, Color(0, 0, 0, 0.85))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0, 0)
	texture.fill_to = Vector2(0, 1)
	shade.texture = texture
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	shade.offset_top = -520
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	_text = UiFx.paragraph("", "HeadingLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_text.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_text.offset_left = 36
	_text.offset_right = -36
	_text.offset_top = -330
	_text.offset_bottom = -150
	_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_text.add_theme_font_size_override("font_size", 30)
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_text)

	var hint := UiFx.label(Tr.t("Touchez pour continuer"), "CaptionLabel", HORIZONTAL_ALIGNMENT_CENTER)
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -110
	hint.offset_bottom = -80
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.modulate.a = 0.7
	add_child(hint)

	var skip := Button.new()
	skip.text = Tr.t("Passer")
	skip.focus_mode = Control.FOCUS_NONE
	skip.custom_minimum_size = Vector2(120, 52)
	skip.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	skip.offset_left = -144
	skip.offset_right = -24
	skip.offset_top = 64
	skip.offset_bottom = 116
	skip.pressed.connect(_leave)
	add_child(skip)

	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)
	_start_shot(0)


func _gui_input(event: InputEvent) -> void:
	if (event is InputEventScreenTouch and event.pressed) or (event is InputEventMouseButton and event.pressed):
		accept_event()
		# Un toucher pendant le fondu d'entrée ne fait rien : le plan vient à peine de commencer.
		if _t > FADE_SECONDS:
			_next_shot()


func _process(delta: float) -> void:
	var wanted := Vector2i(size)
	if wanted.x > 0 and wanted.y > 0 and _viewport.size != wanted:
		_viewport.size = wanted
	_t += minf(delta, 0.05)
	_animate()
	if _leaving:
		_fade.color.a = move_toward(_fade.color.a, 1.0, delta / FADE_SECONDS)
		if _fade.color.a >= 1.0:
			set_process(false)
			done.emit()
			queue_free()
		return
	# Fondu au début et à la fin de chaque plan.
	var edge := minf(_t, SHOT_SECONDS - _t)
	_fade.color.a = 1.0 - clampf(edge / FADE_SECONDS, 0.0, 1.0)
	_text.modulate.a = clampf((_t - 0.3) / 0.8, 0.0, 1.0)
	if _t >= SHOT_SECONDS:
		_next_shot()


func _next_shot() -> void:
	if _leaving:
		return
	if _shot + 1 >= Story.INTRO.size():
		_leave()
	else:
		_start_shot(_shot + 1)


func _leave() -> void:
	_leaving = true


func _start_shot(index: int) -> void:
	_shot = index
	_t = 0.0
	_text.text = Tr.t(Story.INTRO[index])
	_text.modulate.a = 0.0
	_sun.rotation_degrees = SUN_ANGLES[index]
	_rocket.visible = index == 1
	# Au dernier plan, Mars est toute proche : on la grossit, et on la penche pour cacher son pôle.
	_mars.scale = Vector3.ONE * (3.0 if index == 3 else 1.0)
	_mars.rotation.x = 0.9 if index == 3 else 0.0
	_capsule.visible = index >= 2
	_animate()


## Place la caméra et les vaisseaux selon le plan et le temps écoulé.
func _animate() -> void:
	var k := clampf(_t / SHOT_SECONDS, 0.0, 1.0)
	_earth.rotation.y = EARTH_TURN + _t * 0.03
	_mars.rotation.y = 1.0 + _t * 0.02
	match _shot:
		0:
			# La Terre, de loin, qui dérive lentement.
			_look(EARTH + Vector3(-1.2 + k * 0.5, 1.0, 10.5 - k * 1.0), EARTH + Vector3(0, -0.9, 0))
		1:
			# Le décollage : la fusée monte au-dessus de l'horizon courbe.
			var up := Vector3(0.25, 1.0, 0.2).normalized()
			_rocket.position = EARTH + up * (3.05 + k * k * 2.6)
			_rocket.basis = Basis(Quaternion(Vector3.UP, up)) * Basis.from_scale(Vector3.ONE * 0.22)
			_look(EARTH + up * 3.6 + Vector3(2.6, -0.4, 2.2), EARTH + up * (3.3 + k * 1.2))
		2:
			# Le voyage : la capsule au premier plan, Mars grossit au loin.
			var from := MARS + Vector3(-34.0 + k * 14.0, 1.5, 6.0)
			_look(from, MARS + Vector3(0, 0.6, 0))
			_capsule.position = _camera.to_global(Vector3(-0.35 + k * 0.4, -0.2, -5.0))
			_capsule.basis = _camera.global_basis * Basis.from_euler(Vector3(0.5, _t * 0.12, 1.25)) * Basis.from_scale(Vector3.ONE * 0.9)
		3:
			# L'arrivée : Mars, immense, emplit le bas de l'image ; la capsule s'éloigne vers elle, bouclier en avant,
			# sans jamais atteindre le sol (le fondu enchaîne sur l'atterrissage dans le jeu).
			_look(MARS + Vector3(-3.0 + k * 0.6, 4.0, 17.0), MARS + Vector3(2.0, 11.0, 0.0))
			_capsule.position = _camera.to_global(Vector3(0.3, -0.2 - k * 0.5, -2.5 - k * 4.0))
			_capsule.basis = _camera.global_basis * Basis.from_euler(Vector3(1.25, 0.3 + _t * 0.05, 0.2)) * Basis.from_scale(Vector3.ONE * 0.7)


func _look(from: Vector3, target: Vector3) -> void:
	_camera.position = from
	_camera.look_at(target, Vector3.UP)


# ---------- Décor ----------

func _build_scene() -> void:
	var root := Node3D.new()
	_viewport.add_child(root)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.008, 0.014, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.38, 0.5)
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	root.add_child(world_env)
	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = SUN_ANGLES[0]
	_sun.light_energy = 1.25
	root.add_child(_sun)
	_camera = Camera3D.new()
	_camera.fov = 50.0
	_camera.far = 400.0
	root.add_child(_camera)
	_camera.make_current()

	# Étoiles lointaines : une sphère de points (comme dans la vue du Système solaire).
	var stars := MeshInstance3D.new()
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_POINTS)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 900:
		var dir := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
		var shade := rng.randf_range(0.35, 1.0)
		mesh.surface_set_color(Color(shade, shade, shade * rng.randf_range(0.95, 1.15)))
		mesh.surface_add_vertex(dir * 300.0)
	mesh.surface_end()
	stars.mesh = mesh
	var star_material := StandardMaterial3D.new()
	star_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	star_material.vertex_color_use_as_albedo = true
	star_material.use_point_size = true
	star_material.point_size = 2.0
	stars.material_override = star_material
	root.add_child(stars)

	_earth = _build_earth(root)
	_mars = _planet(root, MARS, 4.0, Color(0.82, 0.4, 0.2), Color(0.5, 0.22, 0.12), 2.0, 0.6, 5.0)
	_rocket = ModelBuilder.rocket()
	root.add_child(_rocket)
	_capsule = ModelBuilder.capsule()
	# En vol libre, moteur coupé.
	var flame := _capsule.get_node_or_null("Flame")
	if flame != null:
		flame.visible = false
	root.add_child(_capsule)


## La Terre : la carte Blue Marble de la NASA (un peu ternie), des nuages qui dérivent et un liseré d'atmosphère.
func _build_earth(root: Node3D) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 3.0
	mesh.height = 6.0
	mesh.radial_segments = 128
	mesh.rings = 64
	node.mesh = mesh
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.012
	noise.fractal_octaves = 5
	noise.seed = 4
	var clouds := NoiseTexture2D.new()
	clouds.width = 512
	clouds.height = 256
	clouds.seamless = true
	clouds.noise = noise
	var shader := Shader.new()
	shader.code = EARTH_SHADER
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("map", preload("res://art/textures/earth.jpg"))
	material.set_shader_parameter("clouds", clouds)
	node.material_override = material
	node.position = EARTH
	root.add_child(node)
	return node


const EARTH_SHADER := """
shader_type spatial;
uniform sampler2D map : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D clouds : filter_linear, repeat_enable;

void fragment() {
	vec3 ground = texture(map, UV).rgb;
	// Les océans de la carte sont presque noirs : on les éclaircit un peu.
	ground = max(ground, vec3(0.03, 0.07, 0.16));
	float cover = texture(clouds, UV * vec2(4.0, 2.0) + vec2(TIME * 0.004, 0.0)).r;
	cover = smoothstep(0.6, 0.85, cover) * 0.7;
	ALBEDO = mix(ground, vec3(0.93, 0.94, 0.95), cover);
	ROUGHNESS = 0.8;
	// Liseré bleuté de l'atmosphère, sur le bord du disque.
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = vec3(0.25, 0.5, 1.0) * rim * 0.5;
}
"""


func _planet(root: Node3D, at: Vector3, radius: float, base: Color, band: Color, bands: float, strength: float, seed_value: float) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 128
	mesh.rings = 64
	node.mesh = mesh
	var shader := Shader.new()
	shader.code = SolarSystem.PLANET_SHADER
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("base", base)
	material.set_shader_parameter("band", band)
	material.set_shader_parameter("bands", bands)
	material.set_shader_parameter("strength", strength)
	material.set_shader_parameter("seed", seed_value)
	node.material_override = material
	node.position = at
	root.add_child(node)
	return node
