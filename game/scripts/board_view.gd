class_name BoardView
extends Node2D

const HOVER_NONE := Vector2i(999, 999)

var grid: HexGrid
var match_state: MatchState
var hover_cell := HOVER_NONE


func _ready() -> void:
	if grid == null or match_state == null:
		setup(HexGrid.new(), MatchState.new())


func setup(start_grid: HexGrid, start_match_state: MatchState) -> void:
	grid = start_grid
	match_state = start_match_state
	hover_cell = HOVER_NONE
	queue_redraw()


func set_hover_cell(cell: Vector2i) -> void:
	if cell == hover_cell:
		return

	hover_cell = cell
	queue_redraw()


func screen_to_cell(point: Vector2) -> Vector2i:
	return grid.screen_to_cell(point, get_viewport_rect().size)


func _draw() -> void:
	if grid == null or match_state == null:
		return

	_draw_background()
	_draw_cells()
	_draw_links()
	_draw_objects()


func _draw_background() -> void:
	draw_rect(get_viewport_rect(), Color(0.055, 0.065, 0.078), true)


func _draw_cells() -> void:
	for cell in grid.cells:
		var center := _cell_to_screen(cell)
		var fill := Color(0.095, 0.112, 0.132)
		var outline := Color(0.22, 0.25, 0.29)

		if cell == Vector2i.ZERO:
			fill = Color(0.17, 0.145, 0.075)
			outline = Color(0.72, 0.58, 0.22)

		if cell == hover_cell:
			fill = fill.lightened(0.22)
			outline = Color(0.88, 0.9, 0.92)
		elif match_state.can_place_node(cell):
			fill = GameDefs.player_color(match_state.current_player).darkened(0.72)
			outline = GameDefs.player_color(match_state.current_player).darkened(0.3)

		_draw_hex(center, grid.hex_size - 3.0, fill, outline, 2.0)

	if grid.contains(Vector2i.ZERO):
		draw_circle(_cell_to_screen(Vector2i.ZERO), 9.0, Color(0.95, 0.78, 0.28))


func _draw_links() -> void:
	for cell in grid.cells:
		var object := match_state.get_object(cell)
		if object.is_empty() or not object.get("active", false):
			continue

		for direction in HexGrid.LINK_DIRECTIONS:
			var neighbor := cell + direction
			var neighbor_object := match_state.get_object(neighbor)

			if neighbor_object.is_empty():
				continue

			if neighbor_object.get("owner") != object.get("owner"):
				continue

			if not neighbor_object.get("active", false):
				continue

			var color := GameDefs.player_color(object["owner"]).lightened(0.08)
			draw_line(_cell_to_screen(cell), _cell_to_screen(neighbor), color, 5.0, true)


func _draw_objects() -> void:
	for cell in grid.cells:
		var object := match_state.get_object(cell)
		if object.is_empty():
			continue

		var center := _cell_to_screen(cell)
		var owner: String = object["owner"]
		var color := GameDefs.player_color(owner)

		if object["type"] == MatchState.OBJECT_CORE:
			_draw_hex(center, 24.0, color, Color(0.95, 0.97, 1.0), 3.0)
			draw_circle(center, 8.0, Color(0.95, 0.97, 1.0))
		else:
			if not object.get("active", false):
				color = color.darkened(0.52)

			draw_circle(center, 18.0, color)
			draw_circle(center, 8.0, Color(0.95, 0.97, 1.0, 0.78 if object.get("active", false) else 0.35))


func _draw_hex(center: Vector2, radius: float, fill: Color, outline: Color, width: float) -> void:
	var points := PackedVector2Array()

	for i in range(6):
		var angle := deg_to_rad(60.0 * i)
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)

	draw_colored_polygon(points, fill)

	var outline_points := PackedVector2Array(points)
	outline_points.append(points[0])
	draw_polyline(outline_points, outline, width, true)


func _cell_to_screen(cell: Vector2i) -> Vector2:
	return grid.cell_to_screen(cell, get_viewport_rect().size)
