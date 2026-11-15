class_name CameraRig
extends Node3D
## Caméra isométrique orthographique : glisser pour se déplacer, pincer (ou molette) pour zoomer.

const PITCH_DEGREES := -35.0
const YAW_DEGREES := -45.0
const MIN_SIZE := 6.0
const MAX_SIZE := 30.0
const DISTANCE := 60.0

var camera: Camera3D
## Zone où le point visé peut se déplacer (plan XZ).
var bounds := Rect2(0, 0, 24, 24)
## Part de l'écran masquée en bas par l'interface : le point visé est recentré dans la partie visible.
var covered_fraction := 0.5:
	set(value):
		covered_fraction = value
		_update_offset()

var _focus_tween: Tween
## Mode photo : caméra en perspective, qu'on fait tourner autour du point visé.
var photo := false
var _saved := {}


func _ready() -> void:
	rotation_degrees = Vector3(PITCH_DEGREES, YAW_DEGREES, 0.0)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 14.0
	camera.near = 1.0
	camera.far = 200.0
	camera.position = Vector3(0, 0, DISTANCE)
	add_child(camera)
	_update_offset()


func pan_pixels(delta: Vector2) -> void:
	if photo:
		photo_orbit(delta)
		return
	if _focus_tween != null:
		_focus_tween.kill()
	var units_per_pixel := camera.size / get_viewport().get_visible_rect().size.y
	var right := global_basis.x
	right.y = 0.0
	var up := -global_basis.z
	up.y = 0.0
	var vertical_scale := 1.0 / absf(sin(deg_to_rad(PITCH_DEGREES)))
	position -= right.normalized() * delta.x * units_per_pixel
	position += up.normalized() * delta.y * units_per_pixel * vertical_scale
	_clamp()


func zoom(factor: float) -> void:
	if photo:
		photo_zoom(factor)
		return
	camera.size = clampf(camera.size * factor, MIN_SIZE, MAX_SIZE)
	_update_offset()


func focus(point: Vector3, duration := 0.8) -> void:
	if _focus_tween != null:
		_focus_tween.kill()
	_focus_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_focus_tween.tween_property(self, "position", Vector3(point.x, 0.0, point.z), duration)


## Point du sol (y = 0) sous une position de l'écran, ou null.
func ground_point(screen_position: Vector2) -> Variant:
	var origin := camera.project_ray_origin(screen_position)
	var normal := camera.project_ray_normal(screen_position)
	if absf(normal.y) < 0.001:
		return null
	return origin + normal * (-origin.y / normal.y)


func _clamp() -> void:
	position.x = clampf(position.x, bounds.position.x, bounds.end.x)
	position.z = clampf(position.z, bounds.position.y, bounds.end.y)
	position.y = 0.0


# ---------- Mode photo ----------

func enter_photo() -> void:
	if photo:
		return
	photo = true
	_saved = { "rotation": rotation_degrees, "size": camera.size }
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 50.0
	camera.near = 0.1
	camera.v_offset = 0.0
	camera.position = Vector3(0, 0, 14.0)
	rotation_degrees = Vector3(-16.0, rotation_degrees.y, 0.0)


func exit_photo() -> void:
	if not photo:
		return
	photo = false
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = 1.0
	camera.position = Vector3(0, 0, DISTANCE)
	rotation_degrees = _saved.rotation
	camera.size = _saved.size
	_update_offset()


## Glisser : tourner autour du point visé (horizontalement) et lever ou baisser le regard.
func photo_orbit(delta: Vector2) -> void:
	rotation_degrees.y -= delta.x * 0.25
	rotation_degrees.x = clampf(rotation_degrees.x - delta.y * 0.2, -75.0, -5.0)


func photo_zoom(factor: float) -> void:
	camera.position.z = clampf(camera.position.z * factor, 5.0, 32.0)


func _update_offset() -> void:
	if photo:
		return
	if camera != null:
		camera.v_offset = -camera.size * covered_fraction / 2.0
