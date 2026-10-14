class_name AppTheme
extends RefCounted
## Thème moderne : panneaux de verre sombre arrondis, cartes translucides, boutons « pilule »
## colorés. Les contrôles choisissent un style via `theme_type_variation`
## (par exemple "WindowPanel", "GoldButton", "MoneyLabel").

const FONT_NAMES := ["Inter", "Roboto", "SF Pro Text", "Segoe UI", "Helvetica Neue", "Arial", "sans-serif"]


static func build() -> Theme:
	var theme := Theme.new()
	var regular := _font(500)
	var bold := _font(700)
	var black := _font(800)
	var numbers := _tabular(bold)
	var big_numbers := _tabular(black)

	theme.default_font = regular
	theme.default_font_size = 22

	# ---------- Textes ----------
	theme.set_color("font_color", "Label", Palette.TEXT)
	_label(theme, "TitleLabel", bold, 26, Palette.TEXT)
	_label(theme, "HeadingLabel", bold, 23, Palette.TEXT)
	_label(theme, "BodyLabel", regular, 21, Palette.TEXT_MUTED)
	_label(theme, "SmallLabel", regular, 18, Palette.TEXT_MUTED)
	_label(theme, "CaptionLabel", bold, 16, Palette.TEXT_DIM)
	_label(theme, "NumberLabel", numbers, 21, Palette.TEXT)
	_label(theme, "IncomeLabel", numbers, 20, Palette.ACCENT)
	_label(theme, "FameLabel", numbers, 20, Palette.FAME)
	_label(theme, "MoneyLabel", big_numbers, 34, Palette.MONEY)
	_label(theme, "BigNumberLabel", big_numbers, 44, Palette.MONEY)
	_label(theme, "NewsLabel", regular, 19, Palette.NEWS)
	_label(theme, "LightLabel", bold, 20, Palette.TEXT_LIGHT)

	# ---------- Panneaux ----------
	theme.set_stylebox("panel", "PanelContainer", StyleBoxEmpty.new())
	_panel(theme, "WindowPanel", _box(Palette.GLASS, 30, 14, Palette.BORDER, true))
	_panel(theme, "TitleBar", _margins(StyleBoxEmpty.new(), 6, 2))
	_panel(theme, "Inset", _margins(StyleBoxEmpty.new(), 0, 0))
	_panel(theme, "Thumb", _box(Color(1, 1, 1, 0.06), 18, 4))
	_panel(theme, "Row", _box(Palette.CARD, 22, 12, Color(1, 1, 1, 0.06)))
	_panel(theme, "RowLocked", _box(Palette.CARD_LOCKED, 22, 12))
	_panel(theme, "Chip", _margins(_box(Color(1, 1, 1, 0.07), 999, 0), 14, 6))
	_panel(theme, "News", _margins(_box(Color(0.03, 0.09, 0.15, 0.82), 999, 0, Palette.BORDER), 18, 8))

	# ---------- Boutons ----------
	_button(theme, "Button", Color(1, 1, 1, 0.1), Palette.TEXT, bold, 21, false)
	_button(theme, "GoldButton", Palette.MONEY, Palette.ON_MONEY, bold, 21)
	_button(theme, "GreenButton", Palette.ACCENT, Palette.ON_ACCENT, bold, 22)
	_button(theme, "PurpleButton", Palette.VIOLET, Color("#1c0f45"), bold, 23)
	_toggle(theme, "SegmentButton", bold, 19)
	_toggle(theme, "TabButton", bold, 17)
	theme.set_stylebox("pressed", "TabButton", _box(Color(Palette.ACCENT, 0.14), 20, 6))
	theme.set_stylebox("hover_pressed", "TabButton", _box(Color(Palette.ACCENT, 0.14), 20, 6))
	theme.set_color("font_pressed_color", "TabButton", Palette.ACCENT)
	theme.set_color("font_hover_pressed_color", "TabButton", Palette.ACCENT)

	# ---------- Barres ----------
	_bar(theme, "ProgressBar", Palette.ACCENT, 6)
	_bar(theme, "CycleBar", Palette.ACCENT, 6)
	_bar(theme, "MilestoneBar", Palette.MONEY, 5)
	_bar(theme, "VioletBar", Palette.VIOLET, 8)

	# ---------- Défilement ----------
	theme.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	theme.set_stylebox("scroll", "VScrollBar", _margins(StyleBoxEmpty.new(), 3, 0))
	var grabber := _box(Color(1, 1, 1, 0.18), 4, 0)
	grabber.content_margin_left = 3
	grabber.content_margin_right = 3
	for state in ["grabber", "grabber_highlight", "grabber_pressed"]:
		theme.set_stylebox(state, "VScrollBar", grabber)
	return theme


# ---------- Polices ----------

static func _font(weight: int) -> Font:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(FONT_NAMES)
	font.font_weight = weight
	return font


## Chiffres à chasse fixe : les montants qui défilent ne font pas trembler la mise en page.
static func _tabular(base: Font) -> Font:
	var font := FontVariation.new()
	font.base_font = base
	var tnum := TextServerManager.get_primary_interface().name_to_tag("tnum")
	font.opentype_features = { tnum: 1 }
	return font


# ---------- Styles ----------

static func _box(color: Color, radius: int, margin: int, border := Color.TRANSPARENT, shadow := false) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	box.set_content_margin_all(margin)
	box.corner_detail = 10
	if border.a > 0.0:
		box.border_color = border
		box.set_border_width_all(2)
	if shadow:
		box.shadow_color = Palette.SHADOW
		box.shadow_size = 16
		box.shadow_offset = Vector2(0, 6)
	return box


static func _margins(box: StyleBox, horizontal: float, vertical: float) -> StyleBox:
	box.content_margin_left = horizontal
	box.content_margin_right = horizontal
	box.content_margin_top = vertical
	box.content_margin_bottom = vertical
	return box


static func _label(theme: Theme, variation: String, font: Font, size: int, color: Color) -> void:
	theme.set_type_variation(variation, "Label")
	theme.set_font("font", variation, font)
	theme.set_font_size("font_size", variation, size)
	theme.set_color("font_color", variation, color)


static func _panel(theme: Theme, variation: String, box: StyleBox) -> void:
	theme.set_type_variation(variation, "PanelContainer")
	theme.set_stylebox("panel", variation, box)


## Bouton plein arrondi, avec une lueur de sa couleur sous lui.
static func _button(theme: Theme, type: String, color: Color, text: Color, font: Font, size: int, glow := true) -> void:
	if type != "Button":
		theme.set_type_variation(type, "Button")
	var normal := _margins(_box(color, 18, 0), 18, 10) as StyleBoxFlat
	if glow:
		normal.shadow_color = Color(color, 0.3)
		normal.shadow_size = 10
		normal.shadow_offset = Vector2(0, 4)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = color.lightened(0.12)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = color.darkened(0.15)
	pressed.shadow_size = 2
	var disabled := _margins(_box(Color(1, 1, 1, 0.06), 18, 0), 18, 10)

	theme.set_stylebox("normal", type, normal)
	theme.set_stylebox("hover", type, hover)
	theme.set_stylebox("pressed", type, pressed)
	theme.set_stylebox("hover_pressed", type, pressed)
	theme.set_stylebox("disabled", type, disabled)
	theme.set_stylebox("focus", type, StyleBoxEmpty.new())
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		theme.set_color(state, type, text)
	theme.set_color("font_disabled_color", type, Palette.TEXT_DIM)
	theme.set_font("font", type, font)
	theme.set_font_size("font_size", type, size)
	theme.set_constant("h_separation", type, 8)


## Bouton à bascule transparent, plein (cyan) quand il est enfoncé.
static func _toggle(theme: Theme, type: String, font: Font, size: int) -> void:
	theme.set_type_variation(type, "Button")
	var normal := _margins(_box(Color(1, 1, 1, 0.0), 999, 0), 12, 6)
	var hover := _margins(_box(Color(1, 1, 1, 0.06), 999, 0), 12, 6)
	var active := _margins(_box(Palette.ACCENT, 999, 0), 12, 6)
	theme.set_stylebox("normal", type, normal)
	theme.set_stylebox("hover", type, hover)
	theme.set_stylebox("pressed", type, active)
	theme.set_stylebox("hover_pressed", type, active)
	theme.set_stylebox("disabled", type, normal)
	theme.set_stylebox("focus", type, StyleBoxEmpty.new())
	theme.set_color("font_color", type, Palette.TEXT_MUTED)
	theme.set_color("font_hover_color", type, Palette.TEXT)
	theme.set_color("font_focus_color", type, Palette.TEXT_MUTED)
	theme.set_color("font_pressed_color", type, Palette.ON_ACCENT)
	theme.set_color("font_hover_pressed_color", type, Palette.ON_ACCENT)
	theme.set_font("font", type, font)
	theme.set_font_size("font_size", type, size)


static func _bar(theme: Theme, type: String, fill: Color, height: int) -> void:
	if type != "ProgressBar":
		theme.set_type_variation(type, "ProgressBar")
	var background := _box(Color(1, 1, 1, 0.08), height, 0)
	background.content_margin_top = height / 2.0
	background.content_margin_bottom = height / 2.0
	theme.set_stylebox("background", type, background)
	theme.set_stylebox("fill", type, _box(fill, height, 0))
