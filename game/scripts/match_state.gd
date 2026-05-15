class_name MatchState
extends RefCounted

const OBJECT_CORE := "core"
const OBJECT_NODE := "node"

var board_radius: int
var objects: Dictionary = {}
var scores: Dictionary = {
	GameDefs.PLAYER_ONE: 0,
	GameDefs.PLAYER_TWO: 0,
}
var current_player := GameDefs.PLAYER_ONE
var finished := false
var status_message := "Player 1: place a node"
var turn_number := 1
var move_history: Array[Dictionary] = []


func _init(start_board_radius: int = 3) -> void:
	board_radius = start_board_radius
	setup_match()


func setup_match() -> void:
	objects.clear()
	scores[GameDefs.PLAYER_ONE] = 0
	scores[GameDefs.PLAYER_TWO] = 0
	current_player = GameDefs.PLAYER_ONE
	finished = false
	status_message = "%s: place a node" % GameDefs.player_label(current_player)
	turn_number = 1
	move_history.clear()

	_add_object(Vector2i(-board_radius, 0), OBJECT_CORE, GameDefs.PLAYER_ONE)
	_add_object(Vector2i(board_radius, 0), OBJECT_CORE, GameDefs.PLAYER_TWO)
	_update_active_nodes()


func apply_action(raw_action: Variant) -> Dictionary:
	var action := _parse_action(raw_action)

	if not action.is_valid_shape():
		status_message = "Invalid action"
		return _result(false, status_message, action)

	if finished:
		return _result(false, status_message, action)

	if action.player != current_player:
		status_message = "Expected %s, got %s" % [
			GameDefs.player_label(current_player),
			GameDefs.player_label(action.player),
		]
		return _result(false, status_message, action)

	match action.action_type:
		GameAction.TYPE_PLACE_NODE:
			return _apply_place_node(action)
		GameAction.TYPE_BREAK_NODE:
			return _apply_break_node(action)
		GameAction.TYPE_SKIP:
			return _apply_skip(action)
		_:
			status_message = "Unknown action: %s" % action.action_type
			return _result(false, status_message, action)


func place_node(cell: Vector2i) -> Dictionary:
	return apply_action(GameAction.place_node(current_player, cell))


func break_node(cell: Vector2i) -> Dictionary:
	return apply_action(GameAction.break_node(current_player, cell))


func skip_turn() -> Dictionary:
	return apply_action(GameAction.skip(current_player))


func can_place_node(cell: Vector2i) -> bool:
	if not contains_cell(cell):
		return false

	if has_object(cell):
		return false

	return has_active_neighbor(current_player, cell)


func can_break_node(cell: Vector2i) -> bool:
	if not contains_cell(cell):
		return false

	var object := get_object(cell)

	if object.is_empty():
		return false

	if object.get("type") != OBJECT_NODE:
		return false

	if object.get("owner") == current_player:
		return false

	return has_active_neighbor(current_player, cell)


func can_target_action(action_type: String, cell: Vector2i) -> bool:
	if finished:
		return false

	match action_type:
		GameAction.TYPE_PLACE_NODE:
			return can_place_node(cell)
		GameAction.TYPE_BREAK_NODE:
			return can_break_node(cell)
		_:
			return false


func contains_cell(cell: Vector2i) -> bool:
	return abs(cell.x) <= board_radius and abs(cell.y) <= board_radius and abs(cell.x + cell.y) <= board_radius


func has_active_neighbor(owner: String, cell: Vector2i) -> bool:
	for direction in HexGrid.DIRECTIONS:
		var neighbor_object := get_object(cell + direction)

		if neighbor_object.is_empty():
			continue

		if neighbor_object.get("owner") == owner and neighbor_object.get("active", false):
			return true

	return false


func has_object(cell: Vector2i) -> bool:
	return objects.has(cell_key(cell))


func get_object(cell: Vector2i) -> Dictionary:
	return objects.get(cell_key(cell), {})


func cell_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]


func _apply_place_node(action: GameAction) -> Dictionary:
	if not can_place_node(action.cell):
		status_message = "%s cannot place there" % GameDefs.player_label(current_player)
		return _result(false, status_message, action)

	_add_object(action.cell, OBJECT_NODE, current_player)
	_complete_successful_action(action, "%s placed a node" % GameDefs.player_label(current_player))
	return _result(true, status_message, action)


func _apply_break_node(action: GameAction) -> Dictionary:
	if not contains_cell(action.cell):
		status_message = "%s cannot break that cell" % GameDefs.player_label(current_player)
		return _result(false, status_message, action)

	var object := get_object(action.cell)

	if object.is_empty() or object.get("type") != OBJECT_NODE or object.get("owner") == current_player:
		status_message = "%s cannot break that cell" % GameDefs.player_label(current_player)
		return _result(false, status_message, action)

	if not has_active_neighbor(current_player, action.cell):
		status_message = "%s needs an active neighbor to break a node" % GameDefs.player_label(current_player)
		return _result(false, status_message, action)

	objects.erase(cell_key(action.cell))
	_complete_successful_action(action, "%s broke an enemy node" % GameDefs.player_label(current_player))
	return _result(true, status_message, action)


func _apply_skip(action: GameAction) -> Dictionary:
	_complete_successful_action(action, "%s skipped" % GameDefs.player_label(current_player))
	return _result(true, status_message, action)


func _complete_successful_action(action: GameAction, message: String) -> void:
	_record_move(action, message)
	_end_turn(message)
	turn_number += 1


func _record_move(action: GameAction, message: String) -> void:
	move_history.append({
		"turn": turn_number,
		"player": action.player,
		"type": action.action_type,
		"has_cell": action.has_cell,
		"cell": action.cell,
		"message": message,
	})


func _end_turn(message: String) -> void:
	_update_active_nodes()
	_score_control_point()

	if scores[current_player] >= 5:
		finished = true
		status_message = "%s wins" % GameDefs.player_label(current_player)
	else:
		status_message = message
		current_player = GameDefs.other_player(current_player)


func _score_control_point() -> void:
	var center_object := get_object(Vector2i.ZERO)

	if center_object.is_empty():
		return

	if center_object.get("type") == OBJECT_NODE and center_object.get("owner") == current_player and center_object.get("active", false):
		scores[current_player] += 1


func _update_active_nodes() -> void:
	for key in objects.keys():
		objects[key]["active"] = objects[key]["type"] == OBJECT_CORE

	_mark_active_network(GameDefs.PLAYER_ONE)
	_mark_active_network(GameDefs.PLAYER_TWO)


func _mark_active_network(owner: String) -> void:
	var queue: Array[Vector2i] = []
	var visited := {}

	for key in objects.keys():
		var object: Dictionary = objects[key]

		if object["type"] == OBJECT_CORE and object["owner"] == owner:
			queue.append(object["cell"])
			visited[cell_key(object["cell"])] = true
			break

	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		var object_key := cell_key(cell)

		if objects.has(object_key):
			objects[object_key]["active"] = true

		for direction in HexGrid.DIRECTIONS:
			var neighbor: Vector2i = cell + direction
			var key := cell_key(neighbor)

			if visited.has(key) or not objects.has(key):
				continue

			var neighbor_object: Dictionary = objects[key]

			if neighbor_object["owner"] != owner:
				continue

			visited[key] = true
			queue.append(neighbor)


func _add_object(cell: Vector2i, type: String, owner: String) -> void:
	objects[cell_key(cell)] = {
		"cell": cell,
		"type": type,
		"owner": owner,
		"active": type == OBJECT_CORE,
	}


func _parse_action(raw_action: Variant) -> GameAction:
	if raw_action is GameAction:
		return raw_action

	if raw_action is Dictionary:
		return GameAction.from_payload(raw_action)

	return GameAction.new()


func _result(ok: bool, message: String, action: GameAction = null) -> Dictionary:
	var result := {
		"ok": ok,
		"message": message,
	}

	if action != null:
		result["action"] = action.to_payload()

	return result
