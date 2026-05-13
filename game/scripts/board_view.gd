extends Node2D

const BOARD_RADIUS := 3
const HEX_SIZE := 52.0
const SQRT_3 := 1.7320508075688772

const PLAYER_ONE := "player_1"
const PLAYER_TWO := "player_2"

const OBJECT_CORE := "core"
const OBJECT_NODE := "node"

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

var cells: Array[Vector2i] = []
var objects: Dictionary = {}
var scores: Dictionary = {
	PLAYER_ONE: 0,
	PLAYER_TWO: 0,
}

var current_player := PLAYER_ONE
var hover_cell := Vector2i(999, 999)
var finished := false
var status_message := "Player 1: place a node"


func _ready() -> void:
	_build_cells()
	_setup_match()
	queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_update_hover(event.position)
	elif event is InputEventMouseButton and event.pressed:
		_handle_click(event)
	elif event.is_action_pressed("ui_accept"):
		_skip_turn()


func _draw() -> void:
	_draw_background()
	_draw_cells()
	_draw_links()
	_draw_objects()
	_draw_hud()


func _build_cells() -> void:
	cells.clear()

	for q in range(-BOARD_RADIUS, BOARD_RADIUS + 1):
		var r_min: int = maxi(-BOARD_RADIUS, -q - BOARD_RADIUS)
		var r_max: int = mini(BOARD_RADIUS, -q + BOARD_RADIUS)

		for r in range(r_min, r_max + 1):
			cells.append(Vector2i(q, r))


func _setup_match() -> void:
	objects.clear()
	scores[PLAYER_ONE] = 0
	scores[PLAYER_TWO] = 0
	current_player = PLAYER_ONE
	hover_cell = Vector2i(999, 999)
	finished = false
	status_message = "%s: place a node" % _player_label(current_player)

	_add_object(Vector2i(-BOARD_RADIUS, 0), OBJECT_CORE, PLAYER_ONE)
	_add_object(Vector2i(BOARD_RADIUS, 0), OBJECT_CORE, PLAYER_TWO)
	_update_active_nodes()


func _draw_background() -> void:
	draw_rect(get_viewport_rect(), Color(0.055, 0.065, 0.078), true)


func _draw_cells() -> void:
	for cell in cells:
		var center := _cell_to_screen(cell)
		var fill := Color(0.095, 0.112, 0.132)
		var outline := Color(0.22, 0.25, 0.29)

		if cell == Vector2i.ZERO:
			fill = Color(0.17, 0.145, 0.075)
			outline = Color(0.72, 0.58, 0.22)

		if cell == hover_cell:
			fill = fill.lightened(0.22)
			outline = Color(0.88, 0.9, 0.92)
		elif _can_place_node(cell):
			fill = _player_color(current_player).darkened(0.72)
			outline = _player_color(current_player).darkened(0.3)

		_draw_hex(center, HEX_SIZE - 3.0, fill, outline, 2.0)

	if cells.has(Vector2i.ZERO):
		draw_circle(_cell_to_screen(Vector2i.ZERO), 9.0, Color(0.95, 0.78, 0.28))


func _draw_links() -> void:
	for cell in cells:
		var object := _get_object(cell)
		if object.is_empty() or not object.get("active", false):
			continue

		for direction in LINK_DIRECTIONS:
			var neighbor := cell + direction
			var neighbor_object := _get_object(neighbor)

			if neighbor_object.is_empty():
				continue

			if neighbor_object.get("owner") != object.get("owner"):
				continue

			if not neighbor_object.get("active", false):
				continue

			var color := _player_color(object["owner"]).lightened(0.08)
			draw_line(_cell_to_screen(cell), _cell_to_screen(neighbor), color, 5.0, true)


func _draw_objects() -> void:
	for cell in cells:
		var object := _get_object(cell)
		if object.is_empty():
			continue

		var center := _cell_to_screen(cell)
		var owner: String = object["owner"]
		var color := _player_color(owner)

		if object["type"] == OBJECT_CORE:
			_draw_hex(center, 24.0, color, Color(0.95, 0.97, 1.0), 3.0)
			draw_circle(center, 8.0, Color(0.95, 0.97, 1.0))
		else:
			if not object.get("active", false):
				color = color.darkened(0.52)

			draw_circle(center, 18.0, color)
			draw_circle(center, 8.0, Color(0.95, 0.97, 1.0, 0.78 if object.get("active", false) else 0.35))


func _draw_hud() -> void:
	var font := ThemeDB.fallback_font
	var color := Color(0.88, 0.9, 0.92)
	var turn_label := "Turn: %s" % _player_label(current_player)
	var score_label := "Score: P1 %d / P2 %d" % [scores[PLAYER_ONE], scores[PLAYER_TWO]]

	draw_string(font, Vector2(24, 34), turn_label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18, _player_color(current_player))
	draw_string(font, Vector2(24, 60), score_label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, color)
	draw_string(font, Vector2(24, 86), status_message, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, Color(0.62, 0.66, 0.72))
	draw_string(font, Vector2(24, 112), "Left click: place node | Right click: break enemy node | Space: skip", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, Color(0.46, 0.5, 0.57))


func _draw_hex(center: Vector2, radius: float, fill: Color, outline: Color, width: float) -> void:
	var points := PackedVector2Array()

	for i in range(6):
		var angle := deg_to_rad(60.0 * i)
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)

	draw_colored_polygon(points, fill)

	var outline_points := PackedVector2Array(points)
	outline_points.append(points[0])
	draw_polyline(outline_points, outline, width, true)


func _handle_click(event: InputEventMouseButton) -> void:
	if finished:
		return

	var cell := _screen_to_cell(event.position)

	if not cells.has(cell):
		return

	if event.button_index == MOUSE_BUTTON_LEFT:
		_try_place_node(cell)
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		_try_break_node(cell)


func _update_hover(mouse_position: Vector2) -> void:
	var next_hover := _screen_to_cell(mouse_position)

	if not cells.has(next_hover):
		next_hover = Vector2i(999, 999)

	if next_hover == hover_cell:
		return

	hover_cell = next_hover
	queue_redraw()


func _try_place_node(cell: Vector2i) -> void:
	if not _can_place_node(cell):
		status_message = "%s cannot place there" % _player_label(current_player)
		queue_redraw()
		return

	_add_object(cell, OBJECT_NODE, current_player)
	_end_turn("%s placed a node" % _player_label(current_player))


func _try_break_node(cell: Vector2i) -> void:
	var object := _get_object(cell)

	if object.is_empty() or object.get("type") != OBJECT_NODE or object.get("owner") == current_player:
		status_message = "%s cannot break that cell" % _player_label(current_player)
		queue_redraw()
		return

	if not _has_active_neighbor(current_player, cell):
		status_message = "%s needs an active neighbor to break a node" % _player_label(current_player)
		queue_redraw()
		return

	objects.erase(_cell_key(cell))
	_end_turn("%s broke an enemy node" % _player_label(current_player))


func _skip_turn() -> void:
	if finished:
		return

	_end_turn("%s skipped" % _player_label(current_player))


func _end_turn(message: String) -> void:
	_update_active_nodes()
	_score_control_point()

	if scores[current_player] >= 5:
		finished = true
		status_message = "%s wins" % _player_label(current_player)
	else:
		status_message = message
		current_player = _other_player(current_player)

	queue_redraw()


func _score_control_point() -> void:
	var center_object := _get_object(Vector2i.ZERO)

	if center_object.is_empty():
		return

	if center_object.get("type") == OBJECT_NODE and center_object.get("owner") == current_player and center_object.get("active", false):
		scores[current_player] += 1


func _can_place_node(cell: Vector2i) -> bool:
	if _has_object(cell):
		return false

	return _has_active_neighbor(current_player, cell)


func _has_active_neighbor(owner: String, cell: Vector2i) -> bool:
	for direction in DIRECTIONS:
		var neighbor_object := _get_object(cell + direction)

		if neighbor_object.is_empty():
			continue

		if neighbor_object.get("owner") == owner and neighbor_object.get("active", false):
			return true

	return false


func _update_active_nodes() -> void:
	for key in objects.keys():
		objects[key]["active"] = objects[key]["type"] == OBJECT_CORE

	_mark_active_network(PLAYER_ONE)
	_mark_active_network(PLAYER_TWO)


func _mark_active_network(owner: String) -> void:
	var queue: Array[Vector2i] = []
	var visited := {}

	for key in objects.keys():
		var object: Dictionary = objects[key]

		if object["type"] == OBJECT_CORE and object["owner"] == owner:
			queue.append(object["cell"])
			visited[_cell_key(object["cell"])] = true
			break

	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		var object_key := _cell_key(cell)

		if objects.has(object_key):
			objects[object_key]["active"] = true

		for direction in DIRECTIONS:
			var neighbor: Vector2i = cell + direction
			var key := _cell_key(neighbor)

			if visited.has(key) or not objects.has(key):
				continue

			var neighbor_object: Dictionary = objects[key]

			if neighbor_object["owner"] != owner:
				continue

			visited[key] = true
			queue.append(neighbor)


func _add_object(cell: Vector2i, type: String, owner: String) -> void:
	objects[_cell_key(cell)] = {
		"cell": cell,
		"type": type,
		"owner": owner,
		"active": type == OBJECT_CORE,
	}


func _has_object(cell: Vector2i) -> bool:
	return objects.has(_cell_key(cell))


func _get_object(cell: Vector2i) -> Dictionary:
	return objects.get(_cell_key(cell), {})


func _cell_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]


func _cell_to_screen(cell: Vector2i) -> Vector2:
	var origin := get_viewport_rect().size * 0.5
	var x := HEX_SIZE * 1.5 * float(cell.x)
	var y := HEX_SIZE * SQRT_3 * (float(cell.y) + float(cell.x) * 0.5)

	return origin + Vector2(x, y)


func _screen_to_cell(point: Vector2) -> Vector2i:
	var origin := get_viewport_rect().size * 0.5
	var relative := point - origin
	var q := (2.0 / 3.0 * relative.x) / HEX_SIZE
	var r := (-1.0 / 3.0 * relative.x + SQRT_3 / 3.0 * relative.y) / HEX_SIZE

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


func _player_color(player: String) -> Color:
	if player == PLAYER_ONE:
		return Color(0.22, 0.58, 1.0)

	return Color(1.0, 0.37, 0.28)


func _player_label(player: String) -> String:
	if player == PLAYER_ONE:
		return "Player 1"

	return "Player 2"


func _other_player(player: String) -> String:
	if player == PLAYER_ONE:
		return PLAYER_TWO

	return PLAYER_ONE
