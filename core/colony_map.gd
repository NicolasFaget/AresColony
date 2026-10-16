class_name ColonyMap
extends RefCounted
## Grille du cratère : plaines constructibles, rochers, rebord du cratère, plaques de glace.
## Générée de façon déterministe à partir d'une graine : la même partie a toujours la même carte.

enum Tile { PLAIN, ROCK, RIM, ICE }

const SIZE := 24

var tiles := PackedByteArray()
## Case centrale de l'atterrisseur (coin haut-gauche de son emprise 2×2).
var lander_cell := Vector2i(11, 11)


## Arcadia Planitia : une plaine du nord, peu de rochers et beaucoup de glace.
var region := "jezero"


func _init(seed_value := 1, p_region := "jezero") -> void:
	region = p_region
	var arcadia := region == "arcadia"
	var ceres := region == "ceres"
	var titan := region == "titan"
	tiles.resize(SIZE * SIZE)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var center := Vector2(SIZE / 2.0, SIZE / 2.0)

	for y in SIZE:
		for x in SIZE:
			var distance := Vector2(x + 0.5, y + 0.5).distance_to(center)
			var tile := Tile.PLAIN
			if distance > SIZE / 2.0 - 1.0 + sin(atan2(y - center.y, x - center.x) * 5.0) * 0.6:
				tile = Tile.RIM
			elif rng.randf() < (0.02 if arcadia or titan else 0.06) and distance > 3.5:
				tile = Tile.ROCK
			set_tile(Vector2i(x, y), tile)

	# Plaques de glace enfouie, loin de l'atterrisseur : il faudra s'étendre pour les exploiter.
	for i in (6 if arcadia else (5 if ceres or titan else 3)):
		var angle := rng.randf() * TAU
		var radius := rng.randf_range(4.0, 9.0) if arcadia else rng.randf_range(6.0, 8.5)
		var patch := center + Vector2(cos(angle), sin(angle)) * radius
		for y in SIZE:
			for x in SIZE:
				if Vector2(x + 0.5, y + 0.5).distance_to(patch) < 2.2 and tile_at(Vector2i(x, y)) == Tile.PLAIN:
					set_tile(Vector2i(x, y), Tile.ICE)

	# L'atterrisseur et ses abords restent dégagés.
	for y in range(lander_cell.y - 1, lander_cell.y + 3):
		for x in range(lander_cell.x - 1, lander_cell.x + 3):
			set_tile(Vector2i(x, y), Tile.PLAIN)


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < SIZE and cell.y < SIZE


func tile_at(cell: Vector2i) -> int:
	return tiles[cell.y * SIZE + cell.x] if in_bounds(cell) else Tile.RIM


func set_tile(cell: Vector2i, tile: int) -> void:
	tiles[cell.y * SIZE + cell.x] = tile


## Case où l'on peut bâtir (la glace est une plaine particulière).
func is_buildable(cell: Vector2i) -> bool:
	var tile := tile_at(cell)
	return tile == Tile.PLAIN or tile == Tile.ICE


func ice_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in SIZE:
		for x in SIZE:
			if tiles[y * SIZE + x] == Tile.ICE:
				cells.append(Vector2i(x, y))
	return cells
