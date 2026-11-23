class_name Tr
## Traduction des textes du jeu. La clé est le texte français d'origine : sans traduction chargée
## (tests, français), le texte est rendu tel quel.


static func t(text: String) -> String:
	return _keep_numbers(String(TranslationServer.translate(text)))


## « 2 000 W » ne doit pas être coupé en fin de ligne : l'espace des milliers devient insécable.
static func _keep_numbers(text: String) -> String:
	var from := 0
	while true:
		var at := text.find(" ", from)
		if at < 0 or at + 3 >= text.length():
			return text
		if at > 0 and text[at - 1].is_valid_int() and text.substr(at + 1, 3).is_valid_int() 				and (at + 4 >= text.length() or not text[at + 4].is_valid_int()):
			text[at] = " "
		from = at + 1
	return text
