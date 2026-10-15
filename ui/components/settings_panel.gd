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
