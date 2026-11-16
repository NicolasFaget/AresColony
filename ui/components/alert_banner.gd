class_name AlertBanner
extends PanelContainer
## Bandeau d'alerte sous la barre des ressources, sur une ligne : ce qui va manquer, et une flèche.
## Rouge s'il reste moins d'un sol, orange sinon. Toucher le bandeau emmène à la solution
## (le conseil détaillé s'affiche dans les nouvelles à ce moment-là).

signal action_requested(tab: int, target: String)

var _icon: TextureRect
var _title: Label
var _advice: Label
var _alert := {}
var _danger_box: StyleBoxFlat
var _warning_box: StyleBoxFlat
var _phase := 0.0
## Vrai pendant qu'une nouvelle occupe la ligne : l'alerte attend.
var muted := false


func _ready() -> void:
	_danger_box = _box(Color(0.55, 0.08, 0.08, 0.92), Palette.DANGER)
	_warning_box = _box(Color(0.45, 0.25, 0.02, 0.92), Palette.WARNING)
	_icon = UiFx.image(UiFx.icon("warning"), 24, Color.WHITE)
	_title = UiFx.label("", "BodyLabel")
	_title.add_theme_font_size_override("font_size", 18)
	_title.clip_text = true
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_advice = UiFx.label("", "SmallLabel")
	_advice.visible = false
	var go := UiFx.label("›", "HeadingLabel")
	go.add_theme_font_size_override("font_size", 28)
	add_child(UiFx.hbox(10, [_icon, _title, go]))
	for child in get_child(0).get_children():
		child.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			AudioManager.play("click")
			action_requested.emit(_alert.tab, _alert.target))
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
	visible = not alert.is_empty() and not muted
	if alert.is_empty():
		return
	var danger: bool = alert.level == "danger"
	add_theme_stylebox_override("panel", _danger_box if danger else _warning_box)
	self_modulate = Color.WHITE
	_icon.texture = UiFx.icon(alert.resource if not str(alert.resource).is_empty() else "warning")
	_title.text = alert.title + (Tr.t("   (+%d)") % others if others > 0 else "")
	_advice.text = alert.advice


func has_alert() -> bool:
	return not _alert.is_empty()


func advice() -> String:
	return str(_alert.get("advice", ""))


func set_muted(on: bool) -> void:
	muted = on
	visible = has_alert() and not muted


static func _box(color: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = border
	box.set_border_width_all(2)
	box.set_corner_radius_all(16)
	box.content_margin_left = 14
	box.content_margin_right = 10
	box.content_margin_top = 4
	box.content_margin_bottom = 4
	return box
