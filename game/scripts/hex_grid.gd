class_name HexGrid
extends RefCounted

const SQRT_3 := 1.7320508075688772

const DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(1, -1),
	Vector2i(0, -1),
	Vector2i(-1, 0),
	Vector2i(-1, 1),
	Vector2i(0, 1),
]

const LINK_DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(1, -1),
	Vector2i(0, -1),
]

var radius: int
var hex_size: float
var cells: Array[Vector2i] = []


func _init(start_radius: int = 3, start_hex_size: float = 52.0) -> void:
	radius = start_radius
	hex_size = start_hex_size
	rebuild_cells()


func rebuild_cells() -> void:
	cells.clear()

	for q in range(-radius, radius + 1):
		var r_min: int = maxi(-radius, -q - radius)
		var r_max: int = mini(radius, -q + radius)

		for r in range(r_min, r_max + 1):
			cells.append(Vector2i(q, r))


func contains(cell: Vector2i) -> bool:
	return abs(cell.x) <= radius and abs(cell.y) <= radius and abs(cell.x + cell.y) <= radius


func cell_to_screen(cell: Vector2i, viewport_size: Vector2) -> Vector2:
	var origin := viewport_size * 0.5
	var x := hex_size * 1.5 * float(cell.x)
	var y := hex_size * SQRT_3 * (float(cell.y) + float(cell.x) * 0.5)

	return origin + Vector2(x, y)


func screen_to_cell(point: Vector2, viewport_size: Vector2) -> Vector2i:
	var origin := viewport_size * 0.5
	var relative := point - origin
	var q := (2.0 / 3.0 * relative.x) / hex_size
	var r := (-1.0 / 3.0 * relative.x + SQRT_3 / 3.0 * relative.y) / hex_size

	return _round_axial(q, r)


func _round_axial(q: float, r: float) -> Vector2i:
	var x := q
	var z := r
	var y := -x - z

	var rx: float = round(x)
	var ry: float = round(y)
	var rz: float = round(z)

	var x_diff: float = abs(rx - x)
	var y_diff: float = abs(ry - y)
	var z_diff: float = abs(rz - z)

	if x_diff > y_diff and x_diff > z_diff:
		rx = -ry - rz
	elif y_diff > z_diff:
		ry = -rx - rz
	else:
		rz = -rx - ry

	return Vector2i(int(rx), int(rz))
