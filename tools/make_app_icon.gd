extends SceneTree
## Génère l'icône de l'application : un diorama martien (vrais modèles du jeu) devant un crépuscule
## au soleil bleu (sur Mars, la poussière fine rend le soleil couchant bleuté).
##
## Usage (rendu nécessaire, pas en --headless) :
##   godot --path . -s tools/make_app_icon.gd
## Écrit dans art/app_icon/ : icon.png (1024, coins arrondis), icon_192.png, et les calques adaptatifs
## Android 432×432 (icon_foreground, icon_background, icon_monochrome).

const OUT := "res://art/app_icon"

const SKY_SHADER := """
shader_type canvas_item;
uniform vec2 sun = vec2(0.76, 0.24);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void fragment() {
	vec2 uv = UV;
	// Ciel : nuit indigo en haut, violet poussiéreux, caramel près de l'horizon.
	vec3 top = vec3(0.07, 0.08, 0.2);
	vec3 mid = vec3(0.36, 0.25, 0.42);
	vec3 low = vec3(0.86, 0.52, 0.34);
	vec3 col = mix(top, mid, smoothstep(0.0, 0.45, uv.y));
	col = mix(col, low, smoothstep(0.42, 0.72, uv.y));
	// Soleil couchant bleuté et son halo.
	float d = distance(uv, sun);
	col += vec3(0.4, 0.62, 1.0) * exp(-d * 6.0) * 0.9;
	col += vec3(0.88, 0.95, 1.0) * smoothstep(0.06, 0.05, d);
	// Quelques étoiles dans le haut.
	vec2 cell = floor(uv * 90.0);
	float star = step(0.985, hash(cell)) * smoothstep(0.45, 0.05, uv.y);
	col += vec3(star) * 0.8 * step(distance(fract(uv * 90.0), vec2(0.5)), 0.18);
	// Collines lointaines en silhouette.
	float hills = 0.74 + 0.03 * sin(uv.x * 9.0 + 1.3) + 0.02 * sin(uv.x * 23.0);
	col = mix(col, vec3(0.42, 0.17, 0.11), smoothstep(hills - 0.004, hills + 0.004, uv.y));
	col = mix(col, vec3(0.3, 0.12, 0.08), smoothstep(0.86, 1.0, uv.y));
	COLOR = vec4(col, 1.0);
}
"""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var foreground := await _render_diorama(1024)
	var sky := await _render_sky(1024)

	# Calques adaptatifs : le diorama tient dans la zone sûre (cercle central de 61 %).
	_save(_scaled(_frame(foreground, 0.62), 432), "icon_foreground.png")
	_save(_scaled(sky, 432), "icon_background.png")
	_save(_scaled(_monochrome(_frame(foreground, 0.62)), 432), "icon_monochrome.png")

	# Icône classique : ciel + diorama plus grand, coins arrondis.
	var full := sky.duplicate()
	full.blend_rect(_frame(foreground, 0.86), Rect2i(0, 0, 1024, 1024), Vector2i.ZERO)
	_round_corners(full, 0.22)
	_save(full, "icon.png")
	_save(_scaled(full, 192), "icon_192.png")
	print("icône écrite dans ", OUT)
	quit()


## Diorama : un îlot de sol martien avec un habitat, une serre et un panneau solaire.
func _render_diorama(side: int) -> Image:
	var viewport := _viewport(side, true)
	var island := Node3D.new()
	viewport.add_child(island)
	# Îlot : sol rouille, puis strates rocheuses de plus en plus sombres.
	_slab(island, -0.15, 2.7, 2.7, 0.3, Color("#b24a24"))
	_slab(island, -0.45, 2.7, 2.3, 0.3, Color("#8c3a1e"))
	_slab(island, -0.85, 2.3, 1.6, 0.5, Color("#6e2c17"))
	_slab(island, -1.35, 1.6, 0.6, 0.5, Color("#52200f"))
	_slab(island, 0.006, 0.55, 0.55, 0.02, Color("#9fd2f2"), Vector3(-1.5, 0, 1.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for at in [Vector3(1.9, 0, 1.3), Vector3(-2.1, 0, -0.6), Vector3(0.4, 0, 2.2), Vector3(-0.9, 0, -2.0)]:
		var rock := ModelBuilder.rock(rng)
		rock.position = at
		island.add_child(rock)

	var habitat := ModelBuilder.building("habitat")
	habitat.position = Vector3(-0.35, 0, 0.25)
	island.add_child(habitat)
	var greenhouse := ModelBuilder.building("greenhouse")
	greenhouse.position = Vector3(0.95, 0, -0.85)
	greenhouse.rotation_degrees.y = -20.0
	island.add_child(greenhouse)
	var solar := ModelBuilder.building("solar")
	solar.position = Vector3(1.35, 0, 1.05)
	island.add_child(solar)
	for node in island.find_children("Flame", "", true, false):
		node.visible = false

	# Lumière chaude de face, contre-jour bleuté (le soleil couchant derrière).
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, -35, 0)
	key.light_energy = 1.05
	key.light_color = Color(1.0, 0.88, 0.75)
	key.shadow_enabled = true
	viewport.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-15, 160, 0)
	rim.light_energy = 0.9
	rim.light_color = Color(0.6, 0.75, 1.0)
	viewport.add_child(rim)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.62, 0.66)
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	viewport.add_child(world_env)

	var pivot := Node3D.new()
	pivot.rotation_degrees = Vector3(-27, 32, 0)
	pivot.position = Vector3(0.1, -0.1, 0)
	viewport.add_child(pivot)
	var camera := Camera3D.new()
	camera.fov = 30.0
	camera.position = Vector3(0, 0, 13.5)
	pivot.add_child(camera)
	return await _grab(viewport)


func _slab(parent: Node3D, y: float, top_radius: float, bottom_radius: float, height: float, color: Color,
		offset := Vector3.ZERO) -> void:
	var mesh := ModelBuilder.cylinder(parent, offset + Vector3(0, y, 0), bottom_radius, height, color, Vector3.ZERO, top_radius, 48)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.95
	mesh.material_override = material


func _render_sky(side: int) -> Image:
	var viewport := _viewport(side, false)
	var rect := ColorRect.new()
	rect.size = Vector2(side, side)
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = SKY_SHADER
	material.shader = shader
	rect.material = material
	viewport.add_child(rect)
	return await _grab(viewport)


func _viewport(side: int, transparent: bool) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(side, side)
	viewport.transparent_bg = transparent
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_8X
	viewport.msaa_2d = Viewport.MSAA_8X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	return viewport


func _grab(viewport: SubViewport) -> Image:
	for i in 6:
		await process_frame
	var image := viewport.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	viewport.queue_free()
	return image


## Recadre le contenu visible pour qu'il occupe `share` du côté, centré.
func _frame(image: Image, share: float) -> Image:
	var used := image.get_used_rect()
	var side := image.get_width()
	var crop := image.get_region(used)
	var scale := share * side / maxf(used.size.x, used.size.y)
	crop.resize(int(used.size.x * scale), int(used.size.y * scale), Image.INTERPOLATE_LANCZOS)
	var out := Image.create(side, side, false, Image.FORMAT_RGBA8)
	out.blit_rect(crop, Rect2i(Vector2i.ZERO, crop.get_size()), (Vector2i(side, side) - crop.get_size()) / 2)
	return out


func _monochrome(image: Image) -> Image:
	var out := Image.create(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8)
	for y in image.get_height():
		for x in image.get_width():
			out.set_pixel(x, y, Color(1, 1, 1, image.get_pixel(x, y).a))
	return out


func _round_corners(image: Image, radius_share: float) -> void:
	var side := image.get_width()
	var r := radius_share * side
	for y in side:
		for x in side:
			var cx := clampf(x + 0.5, r, side - r)
			var cy := clampf(y + 0.5, r, side - r)
			var d := Vector2(x + 0.5 - cx, y + 0.5 - cy).length()
			if d > r - 1.0:
				var c := image.get_pixel(x, y)
				c.a *= clampf(r - d, 0.0, 1.0)
				image.set_pixel(x, y, c)


func _scaled(image: Image, side: int) -> Image:
	var copy := image.duplicate()
	copy.resize(side, side, Image.INTERPOLATE_LANCZOS)
	return copy


func _save(image: Image, file_name: String) -> void:
	image.save_png(ProjectSettings.globalize_path(OUT.path_join(file_name)))
