class_name SettingsPanel
extends RefCounted
## Interrupteurs des réglages communs (musique, sons, vibrations), partagés par le menu et le jeu.


static func build() -> VBoxContainer:
	var box := UiFx.vbox(10)
	box.add_child(_toggle("Musique", "music", func(_on: bool) -> void: AudioManager.apply_settings()))
	box.add_child(_toggle("Sons et ambiance", "sound", func(_on: bool) -> void:
		AudioManager.apply_settings()
		AudioManager.play("click")))
	box.add_child(_toggle("Vibrations", "haptics", func(_on: bool) -> void: GameManager.vibrate(20)))
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
		button.text = "%s : %s" % [title, "activé" if on else "désactivé"]
	paint.call(value)
	button.toggled.connect(func(on: bool) -> void:
		paint.call(on)
		GameManager.set_setting(key, on)
		after.call(on))
	return button
