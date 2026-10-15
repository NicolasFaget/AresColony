class_name CoachCard
extends PanelContainer
## Carte du tutoriel guidé : la consigne en cours, « Montrer » (ouvre l'onglet et met la ligne
## en évidence) et « Passer le guide ». Chaque étape se valide toute seule en jouant.

signal show_requested(tab: int, target: String)
signal skip_requested

var _step := -1
var _counter: Label
var _text: Label


func _ready() -> void:
	theme_type_variation = "WindowPanel"
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.03, 0.14, 0.16, 0.95)
	box.border_color = Palette.ACCENT
	box.set_border_width_all(2)
	box.set_corner_radius_all(18)
	box.set_content_margin_all(8)
	box.content_margin_left = 12
	add_theme_stylebox_override("panel", box)

	_counter = UiFx.label("", "CaptionLabel")
	_counter.add_theme_color_override("font_color", Palette.ACCENT)
	_text = UiFx.paragraph("", "SmallLabel")
	_text.add_theme_color_override("font_color", Palette.TEXT)
	var show := Button.new()
	show.theme_type_variation = "GreenButton"
	show.text = Tr.t("Montrer")
	show.custom_minimum_size = Vector2(118, 48)
	show.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	show.focus_mode = Control.FOCUS_NONE
	show.pressed.connect(func() -> void:
		AudioManager.play("click")
		var step: Dictionary = ColonyAdvisor.TUTORIAL[_step]
		show_requested.emit(step.tab, step.target))
	var skip := Button.new()
	skip.text = "✕"
	skip.tooltip_text = Tr.t("Passer le guide")
	skip.custom_minimum_size = Vector2(48, 48)
	skip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	skip.focus_mode = Control.FOCUS_NONE
	skip.pressed.connect(func() -> void:
		AudioManager.play("click")
		skip_requested.emit())
	var info := UiFx.vbox(0, [_counter, _text])
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(UiFx.hbox(8, [info, show, skip]))
	visible = false


## Affiche l'étape `step` (index dans ColonyAdvisor.TUTORIAL), ou masque la carte si -1.
## Retourne vrai si l'étape vient de changer (pour féliciter le joueur).
func show_step(step: int) -> bool:
	var changed := step != _step
	_step = step
	visible = step >= 0
	if step < 0:
		return changed
	_counter.text = Tr.t("GUIDE %d/%d") % [step + 1, ColonyAdvisor.TUTORIAL.size()]
	_text.text = ColonyAdvisor.TUTORIAL[step].text
	if changed:
		UiFx.pop(self, 0.04)
	return changed
