class_name AlertBanner
extends PanelContainer
## Bandeau d'alerte sous la barre des ressources : ce qui va manquer, quand, et la marche à suivre.
## Rouge s'il reste moins d'un sol, orange sinon. « Que faire ? » emmène à la solution.

signal action_requested(tab: int, target: String)

var _icon: TextureRect
var _title: Label
var _advice: Label
var _alert := {}
var _danger_box: StyleBoxFlat
var _warning_box: StyleBoxFlat
var _phase := 0.0


func _ready() -> void:
	_danger_box = _box(Color(0.55, 0.08, 0.08, 0.92), Palette.DANGER)
	_warning_box = _box(Color(0.45, 0.25, 0.02, 0.92), Palette.WARNING)
	_icon = UiFx.image(UiFx.icon("warning"), 30, Color.WHITE)
	_title = UiFx.label("", "HeadingLabel")
	_title.add_theme_font_size_override("font_size", 20)
	_advice = UiFx.paragraph("", "SmallLabel")
	_advice.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	var info := UiFx.vbox(0, [_title, _advice])
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var button := Button.new()
	button.theme_type_variation = "GoldButton"
	button.text = "Que faire ?"
	button.custom_minimum_size = Vector2(150, 56)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(func() -> void:
		AudioManager.play("click")
		action_requested.emit(_alert.tab, _alert.target))
	add_child(UiFx.hbox(10, [_icon, info, button]))
	visible = false


func _process(delta: float) -> void:
	# Une alerte rouge pulse doucement pour attirer l'œil.
	if visible and _alert.get("level") == "danger":
		_phase += delta * 4.0
		self_modulate = Color(1, 1, 1, 0.8 + 0.2 * sin(_phase))


## Affiche l'alerte la plus urgente (ou masque le bandeau s'il n'y en a pas).
## `others` : nombre d'autres alertes en attente.
func show_alert(alert: Dictionary, others := 0) -> void:
	_alert = alert
	visible = not alert.is_empty()
	if alert.is_empty():
		return
	var danger: bool = alert.level == "danger"
	add_theme_stylebox_override("panel", _danger_box if danger else _warning_box)
	self_modulate = Color.WHITE
	_icon.texture = UiFx.icon(alert.resource if not str(alert.resource).is_empty() else "warning")
	_title.text = alert.title + ("   (+%d)" % others if others > 0 else "")
	_advice.text = alert.advice


static func _box(color: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = border
	box.set_border_width_all(2)
	box.set_corner_radius_all(20)
	box.content_margin_left = 14
	box.content_margin_right = 10
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	return box
