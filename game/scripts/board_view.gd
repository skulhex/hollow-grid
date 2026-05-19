class_name BoardView
extends Node2D

const HOVER_NONE := Vector2i(999, 999)
const MODULE_RADIUS := 18.0
const MODULE_EFFECT_RADIUS := 13.6
const NODE_RADIUS := 18.0

var grid: HexGrid
var match_state: MatchState
var hover_cell := HOVER_NONE
var selected_action_type := GameAction.TYPE_PLACE_NODE
var striker_attack_source := HOVER_NONE


func _ready() -> void:
	if grid == null or match_state == null:
		setup(HexGrid.new(), MatchState.new())


func setup(start_grid: HexGrid, start_match_state: MatchState) -> void:
	grid = start_grid
	match_state = start_match_state
	hover_cell = HOVER_NONE
	queue_redraw()


func set_selected_action_type(action_type: String) -> void:
	if action_type == selected_action_type:
		return

	selected_action_type = action_type
	queue_redraw()


func set_striker_attack_source(cell: Vector2i) -> void:
	if cell == striker_attack_source:
		return

	striker_attack_source = cell
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
	_draw_harvester_control_links()
	_draw_objects()


func _draw_background() -> void:
	draw_rect(get_viewport_rect(), Color(0.055, 0.065, 0.078), true)


func _draw_cells() -> void:
	for cell in grid.cells:
		var center := _cell_to_screen(cell)
		var fill := Color(0.095, 0.112, 0.132)
		var outline := Color(0.22, 0.25, 0.29)

		if match_state.is_control_point(cell):
			var control_color := _control_point_color(cell)
			fill = control_color.darkened(0.62)
			outline = control_color

		var is_valid_target := _is_valid_target(cell)

		if is_valid_target:
			var target_color := _target_color()
			fill = target_color.darkened(0.72)
			outline = target_color.darkened(0.22)

		if cell == hover_cell:
			if is_valid_target:
				fill = fill.lightened(0.3)
				outline = Color(0.94, 0.97, 1.0)
			else:
				fill = fill.lightened(0.08)
				outline = Color(0.43, 0.47, 0.52)

		_draw_hex(center, grid.hex_size - 3.0, fill, outline, 2.0)

	if grid.contains(MatchState.CONTROL_POINT):
		var center := _cell_to_screen(MatchState.CONTROL_POINT)
		var control_color := _control_point_color(MatchState.CONTROL_POINT)
		draw_circle(center, 10.0, control_color)
		draw_arc(center, 20.0, 0.0, TAU, 48, control_color.lightened(0.18), 3.0, true)


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


func _draw_harvester_control_links() -> void:
	if not grid.contains(MatchState.CONTROL_POINT):
		return

	var control_center := _cell_to_screen(MatchState.CONTROL_POINT)

	for direction in HexGrid.DIRECTIONS:
		var cell := MatchState.CONTROL_POINT + direction
		var object := match_state.get_object(cell)

		if object.is_empty():
			continue

		if object.get("type") != MatchState.OBJECT_NODE:
			continue

		if object.get("role", MatchState.NODE_CONDUIT) != MatchState.NODE_HARVESTER:
			continue

		if object.get("disabled", false) or not object.get("active", false):
			continue

		var owner_color := GameDefs.player_color(object["owner"])
		var resource_color := _resource_color().lerp(owner_color, 0.32)
		draw_line(_cell_to_screen(cell), control_center, resource_color, 3.0, true)
		draw_arc(control_center, 24.0, 0.0, TAU, 48, resource_color, 2.0, true)


func _draw_objects() -> void:
	for cell in grid.cells:
		var object := match_state.get_object(cell)
		if object.is_empty():
			continue

		var center := _cell_to_screen(cell)
		var object_owner: String = object["owner"]
		var owner_color := GameDefs.player_color(object_owner)
		var is_disabled := bool(object.get("disabled", false))

		if object["type"] == MatchState.OBJECT_CORE:
			_draw_hex(center, 24.0, owner_color, Color(0.95, 0.97, 1.0), 3.0)
			draw_circle(center, 8.0, Color(0.95, 0.97, 1.0))

		elif object["type"] == MatchState.OBJECT_MODULE:
			_draw_module_object(center, object, owner_color, is_disabled)

		else:
			_draw_node_object(center, object, owner_color, is_disabled)

		if _is_valid_target(cell):
			draw_arc(center, 25.0, 0.0, TAU, 48, _target_color().lightened(0.18), 3.0, true)

		if _is_selected_striker_source(cell):
			draw_arc(center, 30.0, 0.0, TAU, 48, _warning_color().lightened(0.18), 3.2, true)


func _draw_module_object(center: Vector2, object: Dictionary, owner_color: Color, is_disabled: bool) -> void:
	var fill := _object_fill_color(owner_color, object, is_disabled)
	var outline := _module_outline_color(is_disabled)
	var module_kind: String = object.get("module_kind", MatchState.MODULE_CONNECTION)
	var is_effective := bool(object.get("active", false)) and bool(object.get("ready", false)) and not is_disabled

	_draw_hex(center, MODULE_RADIUS, fill, outline, 2.2)

	if is_effective:
		_draw_module_effect_indicator(center, _module_kind_color(module_kind))

	_draw_module_kind_mark(center, module_kind, is_effective)

	if is_disabled:
		_draw_disabled_module_overlay(center)


func _draw_node_object(center: Vector2, object: Dictionary, owner_color: Color, is_disabled: bool) -> void:
	var fill := _object_fill_color(owner_color, object, is_disabled)
	draw_circle(center, NODE_RADIUS, fill)

	if is_disabled:
		_draw_node_role_mark(center, object.get("role", MatchState.NODE_CONDUIT), false)
		_draw_disabled_overlay(center, owner_color)
		return

	draw_circle(center, 8.0, Color(0.95, 0.97, 1.0, 0.78 if object.get("active", false) else 0.35))
	var role_ready := bool(object.get("active", false)) and bool(object.get("ready", false))
	_draw_node_role_mark(center, object.get("role", MatchState.NODE_CONDUIT), role_ready)

	if _is_ready_striker(object):
		draw_arc(center, 21.5, 0.0, TAU, 48, _warning_color().lightened(0.12), 2.2, true)


func _draw_hex(center: Vector2, radius: float, fill: Color, outline: Color, width: float) -> void:
	var points := _hex_points(center, radius)

	draw_colored_polygon(points, fill)
	_draw_hex_outline(center, radius, outline, width)


func _draw_hex_outline(center: Vector2, radius: float, color: Color, width: float) -> void:
	var points := _hex_points(center, radius)

	var outline_points := PackedVector2Array(points)
	outline_points.append(points[0])
	draw_polyline(outline_points, color, width, true)


func _hex_points(center: Vector2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()

	for i in range(6):
		var angle := deg_to_rad(60.0 * i)
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)

	return points


func _cell_to_screen(cell: Vector2i) -> Vector2:
	return grid.cell_to_screen(cell, get_viewport_rect().size)


func _target_color() -> Color:
	if selected_action_type == GameAction.TYPE_STRIKER_ATTACK:
		return _warning_color()

	if selected_action_type == GameAction.TYPE_REPAIR_NODE:
		return Color(0.48, 0.78, 0.38)

	if selected_action_type == GameHud.ACTION_UPGRADE_NODE:
		return _resource_color().lerp(_warning_color(), 0.45)

	if selected_action_type == GameHud.ACTION_BUILD_MODULE:
		return _module_color()

	if selected_action_type == GameAction.TYPE_UPGRADE_HARVESTER:
		return _resource_color()

	if selected_action_type == GameAction.TYPE_UPGRADE_STRIKER:
		return _warning_color()

	return GameDefs.player_color(match_state.current_player)


func _control_point_color(_cell: Vector2i) -> Color:
	return Color(0.95, 0.78, 0.28)


func _disabled_owner_fill(owner_color: Color) -> Color:
	return owner_color.darkened(0.42).lerp(Color(0.13, 0.145, 0.165), 0.24)


func _object_fill_color(owner_color: Color, object: Dictionary, is_disabled: bool) -> Color:
	if is_disabled:
		return _disabled_owner_fill(owner_color)

	if not object.get("active", false):
		return owner_color.darkened(0.52)

	return owner_color


func _module_outline_color(is_disabled: bool) -> Color:
	var outline := Color(0.9, 0.92, 0.96)
	outline.a = 0.82 if not is_disabled else 0.36
	return outline


func _draw_disabled_overlay(center: Vector2, owner_color: Color) -> void:
	var owner_outline := owner_color.lightened(0.16)
	var disabled_shadow := Color(0.05, 0.06, 0.075, 0.58)
	var disabled_mark := Color(0.9, 0.93, 0.96, 0.78)
	var cross_size := 7.0

	draw_arc(center, 19.0, 0.0, TAU, 48, owner_outline, 2.4, true)
	draw_line(center + Vector2(-cross_size, -cross_size), center + Vector2(cross_size, cross_size), disabled_shadow, 4.2, true)
	draw_line(center + Vector2(cross_size, -cross_size), center + Vector2(-cross_size, cross_size), disabled_shadow, 4.2, true)
	draw_line(center + Vector2(-cross_size, -cross_size), center + Vector2(cross_size, cross_size), disabled_mark, 2.4, true)
	draw_line(center + Vector2(cross_size, -cross_size), center + Vector2(-cross_size, cross_size), disabled_mark, 2.4, true)


func _draw_disabled_module_overlay(center: Vector2) -> void:
	var disabled_shadow := Color(0.04, 0.048, 0.06, 0.62)
	var disabled_mark := Color(0.9, 0.93, 0.96, 0.74)

	var crack := PackedVector2Array([
		center + Vector2(-4.0, -10.0),
		center + Vector2(1.0, -3.0),
		center + Vector2(-2.0, 2.0),
		center + Vector2(5.0, 10.0),
	])
	draw_polyline(crack, disabled_shadow, 4.2, true)
	draw_polyline(crack, disabled_mark, 2.2, true)


func _draw_node_role_mark(center: Vector2, role: String, is_active: bool) -> void:
	var alpha := 0.9 if is_active else 0.42

	if role == MatchState.NODE_HARVESTER:
		var resource_color := _resource_color()
		resource_color.a = alpha
		draw_arc(center, 10.5, 0.0, TAU, 36, resource_color, 2.8, true)
	elif role == MatchState.NODE_STRIKER:
		var warning_color := _warning_color()
		warning_color.a = alpha
		draw_arc(center, 10.5, 0.0, TAU, 36, warning_color, 2.8, true)
		draw_line(center + Vector2(-5.0, 4.0), center + Vector2(5.0, -4.0), warning_color, 2.2, true)


func _draw_module_kind_mark(center: Vector2, module_kind: String, is_active: bool) -> void:
	var mark_color := _module_kind_color(module_kind) if is_active else _module_inactive_mark_color()

	if module_kind == MatchState.MODULE_CONNECTION:
		_draw_module_bolt(center, mark_color)
	elif module_kind == MatchState.MODULE_REPAIR:
		draw_line(center + Vector2(-7.0, 0.0), center + Vector2(7.0, 0.0), mark_color, 2.6, true)
		draw_line(center + Vector2(0.0, -7.0), center + Vector2(0.0, 7.0), mark_color, 2.6, true)

	if is_active:
		_draw_module_effect_indicator(center, _module_kind_color(module_kind))


func _draw_module_bolt(center: Vector2, color: Color) -> void:
	var bolt := PackedVector2Array([
		center + Vector2(1.0, -10.0),
		center + Vector2(-5.0, 1.0),
		center + Vector2(-1.0, 1.0),
		center + Vector2(-4.0, 10.0),
		center + Vector2(6.0, -3.0),
		center + Vector2(1.0, -3.0),
	])
	draw_colored_polygon(bolt, color)


func _draw_module_effect_indicator(center: Vector2, color: Color) -> void:
	var indicator_color := color.lightened(0.12)
	indicator_color.a = 0.96
	_draw_hex_outline(center, MODULE_EFFECT_RADIUS, indicator_color, 2.6)


func _resource_color() -> Color:
	return Color(0.45, 0.86, 0.46)


func _module_color() -> Color:
	return Color(0.72, 0.58, 0.96)


func _module_kind_color(module_kind: String) -> Color:
	if module_kind == MatchState.MODULE_CONNECTION:
		return Color(0.82, 0.58, 1.0)

	if module_kind == MatchState.MODULE_REPAIR:
		return Color(0.38, 0.95, 0.58)

	return _module_color()


func _module_inactive_mark_color() -> Color:
	return Color(0.86, 0.88, 0.92, 0.58)


func _warning_color() -> Color:
	return Color(1.0, 0.72, 0.24)


func _is_valid_target(cell: Vector2i) -> bool:
	if selected_action_type == GameAction.TYPE_STRIKER_ATTACK:
		return striker_attack_source != HOVER_NONE and match_state.can_striker_attack(striker_attack_source, cell)

	if selected_action_type == GameHud.ACTION_UPGRADE_NODE:
		return match_state.can_target_action(GameAction.TYPE_UPGRADE_HARVESTER, cell) or match_state.can_target_action(GameAction.TYPE_UPGRADE_STRIKER, cell)

	if selected_action_type == GameHud.ACTION_BUILD_MODULE:
		return match_state.can_target_action(GameAction.TYPE_BUILD_CONNECTION_MODULE, cell) or match_state.can_target_action(GameAction.TYPE_BUILD_REPAIR_MODULE, cell)

	return match_state.can_target_action(selected_action_type, cell)


func _is_selected_striker_source(cell: Vector2i) -> bool:
	return selected_action_type == GameAction.TYPE_STRIKER_ATTACK and cell == striker_attack_source


func _is_ready_striker(object: Dictionary) -> bool:
	if object.get("type") != MatchState.OBJECT_NODE:
		return false

	if object.get("role", MatchState.NODE_CONDUIT) != MatchState.NODE_STRIKER:
		return false

	if object.get("disabled", false):
		return false

	if not object.get("active", false):
		return false

	if not object.get("ready", false):
		return false

	return int(object.get("action_charges", 0)) > 0
