class_name SettingsPanel
extends RefCounted
## Interrupteurs des réglages communs (musique, sons, vibrations), partagés par le menu et le jeu.


static func build() -> VBoxContainer:
	var box := UiFx.vbox(10)
	box.add_child(_toggle("Musique", "music", func(_on: bool) -> void: AudioManager.apply_settings()))
	box.add_child(_toggle(Tr.t("Sons et ambiance"), "sound", func(_on: bool) -> void:
		AudioManager.apply_settings()
		AudioManager.play("click")))
	box.add_child(_toggle("Vibrations", "haptics", func(_on: bool) -> void: GameManager.vibrate(20)))
	box.add_child(_graphics_button())
	# Langue : le libellé est bilingue, pour qu'on s'y retrouve dans les deux sens.
	var language := Button.new()
	language.custom_minimum_size.y = 60
	language.focus_mode = Control.FOCUS_NONE
	language.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	language.text = "Langue / Language : %s" % ("Français" if GameManager.locale == "fr" else "English")
	language.pressed.connect(func() -> void:
		AudioManager.play("click")
		GameManager.change_locale("en" if GameManager.locale == "fr" else "fr"))
	box.add_child(language)
	return box


const GRAPHICS_MODES := ["auto", "high", "medium", "low"]
const GRAPHICS_NAMES := { "auto": "automatiques", "high": "très beaux", "medium": "équilibrés", "low": "fluides" }
const LEVEL_NAMES := ["fluides", "équilibrés", "très beaux"]


## Graphismes : automatiques (le jeu s'adapte au téléphone), ou imposés. Un appui passe au suivant.
static func _graphics_button() -> Button:
	var button := Button.new()
	button.custom_minimum_size.y = 60
	button.focus_mode = Control.FOCUS_NONE
	var paint := func() -> void:
		var text := Tr.t("Graphismes : %s") % Tr.t(GRAPHICS_NAMES[GameManager.graphics])
		if GameManager.graphics == "auto":
			text += " (%s)" % Tr.t(LEVEL_NAMES[GameManager.quality_level()])
		button.text = text
	paint.call()
	button.pressed.connect(func() -> void:
		AudioManager.play("click")
		var next: String = GRAPHICS_MODES[(GRAPHICS_MODES.find(GameManager.graphics) + 1) % GRAPHICS_MODES.size()]
		if next == "auto":
			# Retour à l'automatique : nouvelle mesure, sans plafond.
			GameManager.graphics_ceiling = 2
		GameManager.set_graphics(next)
		var scene := GameManager.get_tree().current_scene
		if scene != null and scene.has_method("apply_quality"):
			scene.apply_quality(GameManager.quality_level())
		paint.call())
	return button


static func _toggle(title: String, key: String, after: Callable) -> Button:
	var value: bool = GameManager.settings[key]
	var button := Button.new()
	button.toggle_mode = true
	button.button_pressed = value
	button.custom_minimum_size.y = 60
	button.focus_mode = Control.FOCUS_NONE
	var paint := func(on: bool) -> void:
		button.theme_type_variation = "GreenButton" if on else "Button"
		button.text = Tr.t("%s : %s") % [Tr.t(title), Tr.t("activé") if on else Tr.t("désactivé")]
	paint.call(value)
	button.toggled.connect(func(on: bool) -> void:
		paint.call(on)
		GameManager.set_setting(key, on)
		after.call(on))
	return button
