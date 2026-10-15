class_name Tr
## Traduction des textes du jeu. La clé est le texte français d'origine : sans traduction chargée
## (tests, français), le texte est rendu tel quel.


static func t(text: String) -> String:
	return String(TranslationServer.translate(text))
