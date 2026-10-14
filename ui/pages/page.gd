class_name Page
extends VBoxContainer
## Page d'un onglet : un en-tête fixe, puis une liste de cartes qui défile.

var header: VBoxContainer
var list: VBoxContainer
var scroll: ScrollContainer


func _init() -> void:
	add_theme_constant_override("separation", 8)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	header = UiFx.vbox(10)
	add_child(header)

	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.follow_focus = false
	add_child(scroll)

	list = UiFx.vbox(6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.add_child(list)


## Ligne d'information sous les onglets. Retourne le libellé pour le mettre à jour.
func add_subtitle(subtitle := "") -> Label:
	var sub := UiFx.label(subtitle, "SmallLabel")
	header.add_child(sub)
	return sub


## Appelé à chaque changement d'état, seulement quand la page est visible.
func refresh() -> void:
	pass


## Appelé quand l'onglet devient actif.
func on_shown() -> void:
	refresh()


## Fait défiler jusqu'à une ligne et la fait clignoter (guide, alertes).
func flash_row(row: Control) -> void:
	if row == null:
		return
	# Deux images : la liste vient peut-être d'être réordonnée, attendre sa mise en page.
	await get_tree().process_frame
	await get_tree().process_frame
	scroll.scroll_vertical = int(maxf(0.0, row.position.y - 8.0))
	var tween := row.create_tween()
	for i in 3:
		tween.tween_property(row, "modulate", Color(1.6, 1.5, 0.8), 0.18)
		tween.tween_property(row, "modulate", Color.WHITE, 0.28)


## Met en évidence l'élément `target` (module, recherche...). Redéfini par les pages concernées.
func highlight(_target: String) -> void:
	pass


## Marge en bas de liste, pour que la dernière carte ne colle pas à la barre d'onglets.
func add_bottom_padding() -> void:
	var pad := Control.new()
	pad.custom_minimum_size.y = 8
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	list.add_child(pad)
