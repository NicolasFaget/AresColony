class_name NumberFormatter
extends RefCounted
## Affichage compact des grands nombres : 1.23K, 4.56M, ... puis notation scientifique.

const SUFFIXES := ["", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc"]


static func format(value: float) -> String:
	if is_nan(value) or is_inf(value):
		return "∞"
	if value < 0.0:
		return "-" + format(-value)

	# Boucle plutôt que log10 : évite que 1000 donne un palier de 0 par arrondi flottant.
	# L'arrondi se fait avant de choisir le suffixe, pour que 999 996 s'affiche « 1M » et non « 1000K ».
	var scaled := value
	var tier := 0
	var decimals := _decimals(scaled, tier)
	var rounded := snappedf(scaled, pow(10.0, -decimals))
	while rounded >= 1000.0 and tier < SUFFIXES.size() - 1:
		scaled /= 1000.0
		tier += 1
		decimals = _decimals(scaled, tier)
		rounded = snappedf(scaled, pow(10.0, -decimals))

	if rounded >= 1000.0:
		return _scientific(value)
	return _num(rounded, decimals) + SUFFIXES[tier]


## Durée lisible : « 45 s », « 12 min », « 3 h 05 », « 2 j 04 h ».
@warning_ignore("integer_division")
static func duration(seconds: float) -> String:
	var total := maxi(0, int(seconds))
	if total < 60:
		return "%d s" % total
	var minutes := total / 60
	if minutes < 60:
		return "%d min" % minutes
	var hours := minutes / 60
	if hours < 24:
		return "%d h" % hours if minutes % 60 == 0 else "%d h %02d" % [hours, minutes % 60]
	return "%d j %02d h" % [hours / 24, hours % 24]


static func _decimals(scaled: float, tier: int) -> int:
	if tier == 0 and scaled >= 10.0:
		return 1
	return 2


static func _scientific(value: float) -> String:
	var exponent := floori(log(value) / log(10.0))
	var mantissa := value / pow(10.0, exponent)
	if snappedf(mantissa, 0.01) >= 10.0:
		mantissa /= 10.0
		exponent += 1
	return "%se%d" % [_num(snappedf(mantissa, 0.01), 2), exponent]


## String.num garde « .0 » sur les valeurs entières (« 1.0K ») : on le retire.
static func _num(value: float, decimals: int) -> String:
	return String.num(value, decimals).trim_suffix(".0")
