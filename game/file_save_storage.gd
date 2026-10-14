class_name FileSaveStorage
extends SaveStorage
## Sauvegarde dans user:// (dossier de données propre à l'application, y compris sur mobile).
##
## Écriture : save.tmp, puis save.json devient save.bak, puis save.tmp devient save.json.
## Si l'application est tuée à n'importe quelle étape, save.json ou save.bak reste lisible.

var save_path: String
var backup_path: String
var temp_path: String


## `slot` permet des sauvegardes séparées (tests, captures d'écran).
func _init(directory := "user://", slot := "save") -> void:
	save_path = directory.path_join(slot + ".json")
	backup_path = directory.path_join(slot + ".bak")
	temp_path = directory.path_join(slot + ".tmp")


func read() -> String:
	return _read_file(save_path)


func read_backup() -> String:
	return _read_file(backup_path)


func write(content: String) -> void:
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		push_error("Sauvegarde impossible : %s" % error_string(FileAccess.get_open_error()))
		return
	file.store_string(content)
	file.close()

	if FileAccess.file_exists(save_path):
		_replace(save_path, backup_path)
	_replace(temp_path, save_path)


func quarantine() -> void:
	var stamp := Time.get_datetime_string_from_system(true).replace(":", "-")
	_replace(save_path, save_path.get_basename() + ".corrupt-%s.json" % stamp)


static func _read_file(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


static func _replace(from: String, to: String) -> void:
	if FileAccess.file_exists(to):
		DirAccess.remove_absolute(to)
	var err := DirAccess.rename_absolute(from, to)
	if err != OK:
		push_error("Renommage de %s impossible : %s" % [from, error_string(err)])
