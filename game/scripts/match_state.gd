class_name MatchState
extends RefCounted

const OBJECT_CORE := "core"
const OBJECT_NODE := "node"

const NODE_CONDUIT := "conduit"
const NODE_HARVESTER := "harvester"
const NODE_STRIKER := "striker"

const CONTROL_POINT := Vector2i(0, 0)

const START_CORE_HP := 5
const START_RESOURCE := 1
const CONNECTION_ACTIONS_PER_TURN := 1
const REPAIR_ACTIONS_PER_TURN := 1
const NODE_ROLE_ACTION_CHARGES_PER_TURN := 1
const HARVESTER_RESOURCE_GAIN := 1
const HARVESTER_UPGRADE_RESOURCE_COST := 1
const STRIKER_UPGRADE_RESOURCE_COST := 1

var board_radius: int
var objects: Dictionary = {}
var core_hp: Dictionary = {
	GameDefs.PLAYER_ONE: START_CORE_HP,
	GameDefs.PLAYER_TWO: START_CORE_HP,
}
var resources: Dictionary = {
	GameDefs.PLAYER_ONE: START_RESOURCE,
	GameDefs.PLAYER_TWO: START_RESOURCE,
}
var ended_turn_this_round: Dictionary = {
	GameDefs.PLAYER_ONE: false,
	GameDefs.PLAYER_TWO: false,
}
var current_player := GameDefs.PLAYER_ONE
var finished := false
var status_message := "Player 1: build, repair, upgrade, or end turn"
var turn_number := 1
var round_number := 1
var connection_actions_left := CONNECTION_ACTIONS_PER_TURN
var repair_actions_left := REPAIR_ACTIONS_PER_TURN
var upkeep_message := "Upkeep: ready"
var move_history: Array[Dictionary] = []


func _init(start_board_radius: int = 3) -> void:
	board_radius = start_board_radius
	setup_match()


func setup_match() -> void:
	objects.clear()
	core_hp[GameDefs.PLAYER_ONE] = START_CORE_HP
	core_hp[GameDefs.PLAYER_TWO] = START_CORE_HP
	resources[GameDefs.PLAYER_ONE] = START_RESOURCE
	resources[GameDefs.PLAYER_TWO] = START_RESOURCE
	_reset_round_actions()
	current_player = GameDefs.PLAYER_ONE
	_reset_turn_action_limits()
	upkeep_message = "Upkeep: ready"
	finished = false
	status_message = "%s: build, repair, upgrade, or end turn" % GameDefs.player_label(current_player)
	turn_number = 1
	round_number = 1
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
		GameAction.TYPE_REPAIR_NODE:
			return _apply_repair_node(action)
		GameAction.TYPE_BREAK_NODE:
			return _apply_break_node(action)
		GameAction.TYPE_CLEAR_NODE:
			return _apply_clear_node(action)
		GameAction.TYPE_UPGRADE_HARVESTER:
			return _apply_upgrade_node(action, NODE_HARVESTER)
		GameAction.TYPE_UPGRADE_STRIKER:
			return _apply_upgrade_node(action, NODE_STRIKER)
		GameAction.TYPE_SKIP:
			return _apply_skip(action)
		_:
			status_message = "Unknown action: %s" % action.action_type
			return _result(false, status_message, action)


func place_node(cell: Vector2i) -> Dictionary:
	return apply_action(GameAction.place_node(current_player, cell))


func repair_node(cell: Vector2i) -> Dictionary:
	return apply_action(GameAction.repair_node(current_player, cell))


func break_node(cell: Vector2i) -> Dictionary:
	return apply_action(GameAction.break_node(current_player, cell))


func clear_node(cell: Vector2i) -> Dictionary:
	return apply_action(GameAction.clear_node(current_player, cell))


func upgrade_harvester(cell: Vector2i) -> Dictionary:
	return apply_action(GameAction.upgrade_harvester(current_player, cell))


func upgrade_striker(cell: Vector2i) -> Dictionary:
	return apply_action(GameAction.upgrade_striker(current_player, cell))


func skip_turn() -> Dictionary:
	return apply_action(GameAction.skip(current_player))


func can_place_node(cell: Vector2i) -> bool:
	if not contains_cell(cell):
		return false

	if is_control_point(cell):
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

	if object.get("disabled", false):
		return false

	if object.get("owner") == current_player:
		return false

	return has_active_neighbor(current_player, cell)


func can_repair_node(cell: Vector2i) -> bool:
	if not contains_cell(cell):
		return false

	var object := get_object(cell)

	if object.is_empty():
		return false

	if object.get("type") != OBJECT_NODE:
		return false

	if object.get("owner") != current_player:
		return false

	return object.get("disabled", false)


func can_clear_node(cell: Vector2i) -> bool:
	if not contains_cell(cell):
		return false

	var object := get_object(cell)

	if object.is_empty():
		return false

	if object.get("type") != OBJECT_NODE:
		return false

	if not object.get("disabled", false):
		return false

	if object.get("owner") == current_player:
		return true

	return has_active_neighbor(current_player, cell)


func can_upgrade_node(cell: Vector2i) -> bool:
	return _can_upgrade_node(current_player, cell)


func can_target_action(action_type: String, cell: Vector2i) -> bool:
	if finished:
		return false

	if not can_target_action_shape(action_type, cell):
		return false

	return can_afford_target_action(current_player, action_type, cell)


func can_target_action_shape(action_type: String, cell: Vector2i) -> bool:
	match action_type:
		GameAction.TYPE_PLACE_NODE:
			return can_place_node(cell)
		GameAction.TYPE_REPAIR_NODE:
			return can_repair_node(cell)
		GameAction.TYPE_BREAK_NODE:
			return can_break_node(cell)
		GameAction.TYPE_CLEAR_NODE:
			return can_clear_node(cell)
		GameAction.TYPE_UPGRADE_HARVESTER, GameAction.TYPE_UPGRADE_STRIKER:
			return can_upgrade_node(cell)
		_:
			return false


func can_afford_action(player: String, action_type: String) -> bool:
	if action_uses_resource(action_type):
		return int(resources.get(player, 0)) >= action_resource_cost(action_type)

	if action_uses_connection_limit(action_type):
		return connection_actions_left > 0

	if action_uses_repair_limit(action_type):
		return repair_actions_left > 0

	return true


func can_afford_target_action(player: String, action_type: String, cell: Vector2i) -> bool:
	if action_uses_resource(action_type):
		return int(resources.get(player, 0)) >= action_target_resource_cost(player, action_type, cell)

	if action_uses_connection_limit(action_type):
		return connection_actions_left > 0

	if action_uses_repair_limit(action_type):
		return repair_actions_left > 0

	return true


func action_resource_cost(action_type: String) -> int:
	match action_type:
		GameAction.TYPE_UPGRADE_HARVESTER:
			return HARVESTER_UPGRADE_RESOURCE_COST
		GameAction.TYPE_UPGRADE_STRIKER:
			return STRIKER_UPGRADE_RESOURCE_COST

	return 0


func action_target_resource_cost(_player: String, action_type: String, _cell: Vector2i) -> int:
	return action_resource_cost(action_type)


func action_uses_resource(action_type: String) -> bool:
	return action_type == GameAction.TYPE_UPGRADE_HARVESTER or action_type == GameAction.TYPE_UPGRADE_STRIKER


func action_uses_connection_limit(action_type: String) -> bool:
	return action_type == GameAction.TYPE_PLACE_NODE


func action_uses_repair_limit(action_type: String) -> bool:
	return action_type == GameAction.TYPE_REPAIR_NODE


func action_limit_requirement_message(action_type: String) -> String:
	var limit_label := "action"

	if action_uses_connection_limit(action_type):
		limit_label = "connection action"
	elif action_uses_repair_limit(action_type):
		limit_label = "repair action"

	return "%s needs a %s to %s" % [
		GameDefs.player_label(current_player),
		limit_label,
		_action_verb(action_type),
	]


func action_resource_requirement_message(action_type: String, required_cost: int = -1) -> String:
	var cost := required_cost

	if cost < 0:
		cost = action_resource_cost(action_type)

	return "%s needs %d Resource to %s" % [
		GameDefs.player_label(current_player),
		cost,
		_action_verb(action_type),
	]


func is_control_point(cell: Vector2i) -> bool:
	return cell == CONTROL_POINT


func control_point_owner(cell: Vector2i) -> String:
	if not is_control_point(cell):
		return ""

	var player_one_influence := control_point_influence(cell, GameDefs.PLAYER_ONE)
	var player_two_influence := control_point_influence(cell, GameDefs.PLAYER_TWO)

	if player_one_influence > player_two_influence:
		return GameDefs.PLAYER_ONE

	if player_two_influence > player_one_influence:
		return GameDefs.PLAYER_TWO

	return ""


func control_point_influence(cell: Vector2i, player: String) -> int:
	if not is_control_point(cell):
		return 0

	var influence := 0

	for direction in HexGrid.DIRECTIONS:
		var object := get_object(cell + direction)

		if object.is_empty():
			continue

		if object.get("owner") != player:
			continue

		if object.get("disabled", false):
			continue

		if not object.get("active", false):
			continue

		if object.get("type") == OBJECT_NODE or object.get("type") == OBJECT_CORE:
			influence += 1

	return influence


func contains_cell(cell: Vector2i) -> bool:
	return abs(cell.x) <= board_radius and abs(cell.y) <= board_radius and abs(cell.x + cell.y) <= board_radius


func has_active_neighbor(owner: String, cell: Vector2i) -> bool:
	for direction in HexGrid.DIRECTIONS:
		var neighbor_object := get_object(cell + direction)

		if neighbor_object.is_empty():
			continue

		if neighbor_object.get("disabled", false):
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

	if not can_afford_action(current_player, action.action_type):
		status_message = action_limit_requirement_message(action.action_type)
		return _result(false, status_message, action)

	_spend_connection_action()
	_add_object(action.cell, OBJECT_NODE, current_player)
	_complete_successful_action(action, "%s placed a node" % GameDefs.player_label(current_player))
	return _result(true, status_message, action)


func _apply_repair_node(action: GameAction) -> Dictionary:
	if not can_repair_node(action.cell):
		status_message = "%s cannot repair that node" % GameDefs.player_label(current_player)
		return _result(false, status_message, action)

	if not can_afford_action(current_player, action.action_type):
		status_message = action_limit_requirement_message(action.action_type)
		return _result(false, status_message, action)

	_spend_repair_action()
	objects[cell_key(action.cell)]["disabled"] = false
	_complete_successful_action(action, "%s repaired a node" % GameDefs.player_label(current_player))
	return _result(true, status_message, action)


func _apply_break_node(action: GameAction) -> Dictionary:
	if not contains_cell(action.cell):
		status_message = "%s cannot break that cell" % GameDefs.player_label(current_player)
		return _result(false, status_message, action)

	var object := get_object(action.cell)

	if object.is_empty() or object.get("type") != OBJECT_NODE or object.get("disabled", false) or object.get("owner") == current_player:
		status_message = "%s cannot break that cell" % GameDefs.player_label(current_player)
		return _result(false, status_message, action)

	if not has_active_neighbor(current_player, action.cell):
		status_message = "%s needs an active neighbor to break a node" % GameDefs.player_label(current_player)
		return _result(false, status_message, action)

	if not can_afford_action(current_player, action.action_type):
		status_message = action_limit_requirement_message(action.action_type)
		return _result(false, status_message, action)

	objects[cell_key(action.cell)]["disabled"] = true
	objects[cell_key(action.cell)]["active"] = false
	_complete_successful_action(action, "%s disabled an enemy node" % GameDefs.player_label(current_player))
	return _result(true, status_message, action)


func _apply_clear_node(action: GameAction) -> Dictionary:
	if not can_clear_node(action.cell):
		status_message = "%s cannot clear that cell" % GameDefs.player_label(current_player)
		return _result(false, status_message, action)

	if not can_afford_target_action(current_player, action.action_type, action.cell):
		status_message = action_limit_requirement_message(action.action_type)
		return _result(false, status_message, action)

	var object_owner: String = get_object(action.cell).get("owner", "")
	objects.erase(cell_key(action.cell))

	var clear_message := "%s cleared an enemy disabled node" % GameDefs.player_label(current_player)

	if object_owner == current_player:
		clear_message = "%s cleared a friendly disabled node" % GameDefs.player_label(current_player)

	_complete_successful_action(action, clear_message)
	return _result(true, status_message, action)


func _apply_upgrade_node(action: GameAction, role: String) -> Dictionary:
	if not can_upgrade_node(action.cell):
		status_message = "%s cannot upgrade that node" % GameDefs.player_label(current_player)
		return _result(false, status_message, action)

	if not can_afford_target_action(current_player, action.action_type, action.cell):
		var upgrade_cost := action_target_resource_cost(current_player, action.action_type, action.cell)
		status_message = action_resource_requirement_message(action.action_type, upgrade_cost)
		return _result(false, status_message, action)

	_spend_resource(current_player, action_resource_cost(action.action_type))
	objects[cell_key(action.cell)]["role"] = role
	objects[cell_key(action.cell)]["action_charges"] = NODE_ROLE_ACTION_CHARGES_PER_TURN
	_complete_successful_action(action, "%s upgraded a %s" % [
		GameDefs.player_label(current_player),
		_node_role_label(role),
	])
	return _result(true, status_message, action)


func _apply_skip(action: GameAction) -> Dictionary:
	_complete_turn(action, "%s ended turn" % GameDefs.player_label(current_player))
	return _result(true, status_message, action)


func _complete_successful_action(action: GameAction, message: String) -> void:
	_record_move(action, message)
	_update_active_nodes()
	status_message = message
	turn_number += 1


func _complete_turn(action: GameAction, message: String) -> void:
	_record_move(action, message)
	ended_turn_this_round[action.player] = true
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
		"connection_actions_left": connection_actions_left,
		"repair_actions_left": repair_actions_left,
		"round": round_number,
	})


func _end_turn(message: String) -> void:
	_update_active_nodes()
	var final_message := message

	if _round_ready_to_advance():
		round_number += 1
		_reset_round_actions()

	if _is_draw():
		finished = true
		status_message = "%s. Draw: both Cores destroyed" % final_message
	else:
		var winner := _winner()
		if not winner.is_empty():
			finished = true
			status_message = "%s. %s wins" % [final_message, GameDefs.player_label(winner)]
		else:
			current_player = GameDefs.other_player(current_player)
			_start_turn_for_player(current_player)
			status_message = "%s. %s" % [final_message, upkeep_message]


func _round_ready_to_advance() -> bool:
	return bool(ended_turn_this_round[GameDefs.PLAYER_ONE]) and bool(ended_turn_this_round[GameDefs.PLAYER_TWO])


func _reset_round_actions() -> void:
	ended_turn_this_round[GameDefs.PLAYER_ONE] = false
	ended_turn_this_round[GameDefs.PLAYER_TWO] = false


func _is_draw() -> bool:
	return int(core_hp[GameDefs.PLAYER_ONE]) <= 0 and int(core_hp[GameDefs.PLAYER_TWO]) <= 0


func _winner() -> String:
	if _is_draw():
		return ""

	if int(core_hp[GameDefs.PLAYER_ONE]) <= 0:
		return GameDefs.PLAYER_TWO

	if int(core_hp[GameDefs.PLAYER_TWO]) <= 0:
		return GameDefs.PLAYER_ONE

	return ""


func _update_active_nodes() -> void:
	for key in objects.keys():
		objects[key]["active"] = objects[key]["type"] == OBJECT_CORE and not objects[key].get("disabled", false)

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

			if neighbor_object.get("disabled", false):
				continue

			visited[key] = true
			queue.append(neighbor)


func _can_upgrade_node(player: String, cell: Vector2i) -> bool:
	if not contains_cell(cell):
		return false

	var object := get_object(cell)

	if object.is_empty():
		return false

	if object.get("type") != OBJECT_NODE:
		return false

	if object.get("owner") != player:
		return false

	if object.get("disabled", false):
		return false

	if not object.get("active", false):
		return false

	return object.get("role", NODE_CONDUIT) == NODE_CONDUIT


func _harvester_resource_gain(player: String) -> int:
	for direction in HexGrid.DIRECTIONS:
		var object := get_object(CONTROL_POINT + direction)

		if object.is_empty():
			continue

		if object.get("owner") != player:
			continue

		if object.get("type") != OBJECT_NODE:
			continue

		if object.get("role", NODE_CONDUIT) != NODE_HARVESTER:
			continue

		if object.get("disabled", false):
			continue

		if object.get("active", false):
			return HARVESTER_RESOURCE_GAIN

	return 0


func _add_object(cell: Vector2i, type: String, owner: String) -> void:
	var object := {
		"cell": cell,
		"type": type,
		"owner": owner,
		"active": type == OBJECT_CORE,
		"disabled": false,
	}

	if type == OBJECT_NODE:
		object["role"] = NODE_CONDUIT
		object["action_charges"] = 0

	objects[cell_key(cell)] = object


func _start_turn_for_player(player: String) -> void:
	_update_active_nodes()
	_reset_turn_action_limits()

	var resource_gain := _harvester_resource_gain(player)

	if resource_gain > 0:
		resources[player] += resource_gain

	var charged_nodes := _reset_role_node_action_charges(player)
	upkeep_message = _format_upkeep_message(player, resource_gain, charged_nodes)


func _reset_role_node_action_charges(player: String) -> int:
	var charged_nodes := 0

	for key in objects.keys():
		var object: Dictionary = objects[key]

		if object.get("type") != OBJECT_NODE:
			continue

		if object.get("owner") != player:
			continue

		if object.get("role", NODE_CONDUIT) == NODE_CONDUIT:
			object["action_charges"] = 0
			objects[key] = object
			continue

		object["action_charges"] = NODE_ROLE_ACTION_CHARGES_PER_TURN
		objects[key] = object
		charged_nodes += 1

	return charged_nodes


func _format_upkeep_message(player: String, resource_gain: int, charged_nodes: int) -> String:
	var messages: Array[String] = []

	if resource_gain > 0:
		messages.append("+%dR" % resource_gain)

	if charged_nodes > 0:
		messages.append("%d role charge%s ready" % [
			charged_nodes,
			"" if charged_nodes == 1 else "s",
		])

	if messages.is_empty():
		messages.append("ready")

	return "Upkeep: %s %s" % [
		GameDefs.player_label(player),
		", ".join(messages),
	]


func _spend_resource(player: String, amount: int) -> void:
	resources[player] = maxi(0, int(resources.get(player, 0)) - amount)


func _reset_turn_action_limits() -> void:
	connection_actions_left = CONNECTION_ACTIONS_PER_TURN
	repair_actions_left = REPAIR_ACTIONS_PER_TURN


func _spend_connection_action() -> void:
	connection_actions_left = maxi(0, connection_actions_left - 1)


func _spend_repair_action() -> void:
	repair_actions_left = maxi(0, repair_actions_left - 1)


func _action_verb(action_type: String) -> String:
	match action_type:
		GameAction.TYPE_PLACE_NODE:
			return "place"
		GameAction.TYPE_REPAIR_NODE:
			return "repair"
		GameAction.TYPE_BREAK_NODE:
			return "break"
		GameAction.TYPE_CLEAR_NODE:
			return "clear"
		GameAction.TYPE_UPGRADE_HARVESTER:
			return "upgrade a Harvester"
		GameAction.TYPE_UPGRADE_STRIKER:
			return "upgrade a Striker"
		GameAction.TYPE_SKIP:
			return "skip"
		_:
			return action_type


func _node_role_label(role: String) -> String:
	match role:
		NODE_HARVESTER:
			return "Harvester"
		NODE_STRIKER:
			return "Striker"
		_:
			return "Conduit"


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
