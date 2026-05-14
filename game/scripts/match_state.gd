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

	_add_object(Vector2i(-board_radius, 0), OBJECT_CORE, GameDefs.PLAYER_ONE)
	_add_object(Vector2i(board_radius, 0), OBJECT_CORE, GameDefs.PLAYER_TWO)
	_update_active_nodes()


func place_node(cell: Vector2i) -> Dictionary:
	if finished:
		return _result(false, status_message)

	if not can_place_node(cell):
		status_message = "%s cannot place there" % GameDefs.player_label(current_player)
		return _result(false, status_message)

	_add_object(cell, OBJECT_NODE, current_player)
	_end_turn("%s placed a node" % GameDefs.player_label(current_player))
	return _result(true, status_message)


func break_node(cell: Vector2i) -> Dictionary:
	if finished:
		return _result(false, status_message)

	var object := get_object(cell)

	if object.is_empty() or object.get("type") != OBJECT_NODE or object.get("owner") == current_player:
		status_message = "%s cannot break that cell" % GameDefs.player_label(current_player)
		return _result(false, status_message)

	if not has_active_neighbor(current_player, cell):
		status_message = "%s needs an active neighbor to break a node" % GameDefs.player_label(current_player)
		return _result(false, status_message)

	objects.erase(cell_key(cell))
	_end_turn("%s broke an enemy node" % GameDefs.player_label(current_player))
	return _result(true, status_message)


func skip_turn() -> Dictionary:
	if finished:
		return _result(false, status_message)

	_end_turn("%s skipped" % GameDefs.player_label(current_player))
	return _result(true, status_message)


func can_place_node(cell: Vector2i) -> bool:
	if has_object(cell):
		return false

	return has_active_neighbor(current_player, cell)


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


func _result(ok: bool, message: String) -> Dictionary:
	return {
		"ok": ok,
		"message": message,
	}
