class_name SaveStorage
extends RefCounted
## Stockage abstrait de la sauvegarde. Implémentations :
## - FileSaveStorage (game/) : fichiers dans user://
## - SaveStorage lui-même : stockage en mémoire, utilisé par les tests.
##
## Chaque écriture conserve la sauvegarde précédente comme copie de secours.

var _content := ""
var _backup := ""
## Contenus illisibles mis de côté (en mémoire, pour les tests).
var quarantined: Array[String] = []


## Retourne le contenu sauvegardé, ou une chaîne vide s'il n'y en a pas.
func read() -> String:
	return _content


## Retourne la sauvegarde précédente, ou une chaîne vide.
func read_backup() -> String:
	return _backup


func write(content: String) -> void:
	if not _content.is_empty():
		_backup = _content
	_content = content


## Met de côté une sauvegarde principale illisible pour qu'aucune écriture ne l'efface.
func quarantine() -> void:
	quarantined.append(_content)
	_content = ""
