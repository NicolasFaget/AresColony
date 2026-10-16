class_name NewsTicker
extends PanelContainer
## Messages éphémères : un à la fois, qui apparaît en fondu puis s'efface.

const DISPLAY_SECONDS := 4.0
const MAX_QUEUE := 4

var _label: Label
var _clip: Control
var _queue: Array[String] = []
var _timer := 0.0
var _showing := false


func _ready() -> void:
	theme_type_variation = "News"
	custom_minimum_size.y = 50
	_label = UiFx.label("", "NewsLabel")
	_clip = Control.new()
	_clip.clip_contents = true
	_clip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.add_child(_label)
	add_child(UiFx.hbox(10, [UiFx.image(UiFx.icon("news"), 26, Palette.ACCENT), _clip]))
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.text = Tr.t("Bienvenue, commandant !")
	_showing = true
	_timer = DISPLAY_SECONDS


func post(message: String) -> void:
	_queue.append(message)
	while _queue.size() > MAX_QUEUE:
		_queue.pop_front()
	if not _showing:
		_next()


func _process(delta: float) -> void:
	_label.position.y = (_clip.size.y - _label.size.y) / 2.0
	modulate.a = move_toward(modulate.a, 1.0 if _showing else 0.0, delta * 3.0)
	if not _showing:
		return
	_timer -= delta
	if _timer <= 0.0:
		_showing = false
		if not _queue.is_empty():
			_next()


func _next() -> void:
	_label.text = _queue.pop_front()
	_label.reset_size()
	_showing = true
	_timer = DISPLAY_SECONDS
	_label.position.x = _clip.size.x
	var tween := _label.create_tween()
	tween.tween_property(_label, "position:x", 0.0, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
