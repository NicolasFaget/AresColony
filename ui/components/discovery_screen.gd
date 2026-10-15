class_name DiscoveryScreen
extends Control
## Écran plein de découverte : quand une fiche se débloque, elle s'affiche en grand avec son
## illustration et son chiffre clé, et invite à la lire (la première lecture rapporte des données).

signal read_requested(card_id: String)
signal closed

var _card: Defs.Card
var _glow: TextureRect
var _time := 0.0


static func open(host: Control, card: Defs.Card) -> DiscoveryScreen:
	var screen := DiscoveryScreen.new()
	screen._card = card
	host.add_child(screen)
	return screen


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.01, 0.03, 0.06, 0.94)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	# Halo doré qui respire derrière l'illustration.
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(Palette.MONEY, 0.55), Color(Palette.ACCENT, 0.12), Color(Palette.ACCENT, 0.0)])
	gradient.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 256
	texture.height = 256
	_glow = TextureRect.new()
	_glow.texture = texture
	_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_glow)

	var caption := UiFx.label("✦  NOUVELLE DÉCOUVERTE  ✦", "CaptionLabel", HORIZONTAL_ALIGNMENT_CENTER)
	caption.add_theme_color_override("font_color", Palette.MONEY)
	caption.add_theme_font_size_override("font_size", 20)
	var status := UiFx.label(_card.status.to_upper(), "CaptionLabel", HORIZONTAL_ALIGNMENT_CENTER)
	status.add_theme_color_override("font_color", Palette.STATUS_COLORS.get(_card.status, Palette.TEXT_MUTED))
	var picture := UiFx.building_icon(_card.visual, Vector2(340, 270))
	picture.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	picture.name = "Picture"
	var title := UiFx.paragraph(_card.title, "TitleLabel", HORIZONTAL_ALIGNMENT_CENTER)
	title.add_theme_font_size_override("font_size", 32)
	var figure := UiFx.label(_card.figure, "NumberLabel", HORIZONTAL_ALIGNMENT_CENTER)
	figure.add_theme_font_size_override("font_size", 64)
	figure.add_theme_color_override("font_color", Palette.MONEY)
	figure.add_theme_color_override("font_outline_color", Palette.OUTLINE)
	figure.add_theme_constant_override("outline_size", 10)
	figure.name = "Figure"
	var figure_label := UiFx.paragraph(_card.figure_label, "BodyLabel", HORIZONTAL_ALIGNMENT_CENTER)
	figure_label.add_theme_color_override("font_color", Palette.TEXT_MUTED)

	var read := Button.new()
	read.theme_type_variation = "GoldButton"
	read.text = "Lire la fiche  ·  +%d données" % int(ColonyEngine.CARD_READ_REWARD)
	read.custom_minimum_size = Vector2(0, 78)
	read.focus_mode = Control.FOCUS_NONE
	read.pressed.connect(func() -> void:
		AudioManager.play("click")
		_close()
		read_requested.emit(_card.id))
	var later := Button.new()
	later.text = "Plus tard (onglet Savoir)"
	later.custom_minimum_size = Vector2(0, 60)
	later.focus_mode = Control.FOCUS_NONE
	later.pressed.connect(func() -> void:
		AudioManager.play("click")
		_close())

	var content := UiFx.vbox(10, [caption, status, picture, title, figure, figure_label,
			UiFx.spacer(), read, later])
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 32
	content.offset_right = -32
	content.offset_top = 90
	content.offset_bottom = -60
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(content)

	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.3)
	_entrance.call_deferred(picture, figure)
	AudioManager.play("milestone")
	GameManager.vibrate(30)


func _entrance(picture: Control, figure: Control) -> void:
	for node: Control in [picture, figure]:
		node.pivot_offset = node.size / 2.0
		node.scale = Vector2.ONE * 0.4
	var tween := create_tween()
	tween.tween_property(picture, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(figure, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	_time += delta
	var picture: Control = find_child("Picture", true, false)
	if picture == null:
		return
	var side := 560.0 * (1.0 + 0.06 * sin(_time * 2.0))
	_glow.size = Vector2(side, side)
	_glow.global_position = picture.global_position + picture.size / 2.0 - _glow.size / 2.0


func _close() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.2)
	tween.tween_callback(func() -> void:
		closed.emit()
		queue_free())
