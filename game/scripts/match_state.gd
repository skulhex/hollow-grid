class_name MatchState
extends RefCounted

const OBJECT_CORE := "core"
const OBJECT_NODE := "node"

const CONTROL_POINT := Vector2i(0, 0)

const MAX_ENERGY := 3
const START_ENERGY := 1
const START_CORE_HP := 5
const START_RESOURCE := 0
const TURN_ENERGY_GAIN := 1
const SKIP_ENERGY_GAIN := 1
const CONTROL_POINT_RESOURCE_GAIN := 1
const CORE_DAMAGE_PER_RESOLVE := 1
const PLACE_NODE_COST := 1
const BREAK_NODE_COST := 2
const SKIP_COST := 0

var board_radius: int
var objects: Dictionary = {}
var energy: Dictionary = {
	GameDefs.PLAYER_ONE: START_ENERGY,
	GameDefs.PLAYER_TWO: START_ENERGY,
}
var core_hp: Dictionary = {
	GameDefs.PLAYER_ONE: START_CORE_HP,
	GameDefs.PLAYER_TWO: START_CORE_HP,
}
var resources: Dictionary = {
	GameDefs.PLAYER_ONE: START_RESOURCE,
	GameDefs.PLAYER_TWO: START_RESOURCE,
}
var acted_this_round: Dictionary = {
	GameDefs.PLAYER_ONE: false,
	GameDefs.PLAYER_TWO: false,
}
var current_player := GameDefs.PLAYER_ONE
var finished := false
var status_message := "Player 1: place a node"
var turn_number := 1
var round_number := 1
var move_history: Array[Dictionary] = []


func _init(start_board_radius: int = 3) -> void:
	board_radius = start_board_radius
	setup_match()


func setup_match() -> void:
	objects.clear()
	energy[GameDefs.PLAYER_ONE] = START_ENERGY
	energy[GameDefs.PLAYER_TWO] = START_ENERGY
	core_hp[GameDefs.PLAYER_ONE] = START_CORE_HP
	core_hp[GameDefs.PLAYER_TWO] = START_CORE_HP
	resources[GameDefs.PLAYER_ONE] = START_RESOURCE
	resources[GameDefs.PLAYER_TWO] = START_RESOURCE
	_reset_round_actions()
	current_player = GameDefs.PLAYER_ONE
	finished = false
	status_message = "%s: place a node" % GameDefs.player_label(current_player)
	turn_number = 1
	round_number = 1
	move_history.clear()
	_grant_energy(current_player, TURN_ENERGY_GAIN)

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


func can_target_action(action_type: String, cell: Vector2i) -> bool:
	if finished:
		return false

	if not can_afford_action(current_player, action_type):
		return false

	return can_target_action_shape(action_type, cell)


func can_target_action_shape(action_type: String, cell: Vector2i) -> bool:
	match action_type:
		GameAction.TYPE_PLACE_NODE:
			return can_place_node(cell)
		GameAction.TYPE_BREAK_NODE:
			return can_break_node(cell)
		_:
			return false


func can_afford_action(player: String, action_type: String) -> bool:
	return int(energy.get(player, 0)) >= action_cost(action_type)


func action_cost(action_type: String) -> int:
	match action_type:
		GameAction.TYPE_PLACE_NODE:
			return PLACE_NODE_COST
		GameAction.TYPE_BREAK_NODE:
			return BREAK_NODE_COST
		GameAction.TYPE_SKIP:
			return SKIP_COST
		_:
			return 0


func action_energy_requirement_message(action_type: String) -> String:
	return "%s needs %d Energy to %s" % [
		GameDefs.player_label(current_player),
		action_cost(action_type),
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
		status_message = action_energy_requirement_message(action.action_type)
		return _result(false, status_message, action)

	_spend_energy(current_player, PLACE_NODE_COST)
	_add_object(action.cell, OBJECT_NODE, current_player)
	_complete_successful_action(action, "%s placed a node" % GameDefs.player_label(current_player))
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
		status_message = action_energy_requirement_message(action.action_type)
		return _result(false, status_message, action)

	_spend_energy(current_player, BREAK_NODE_COST)
	objects[cell_key(action.cell)]["disabled"] = true
	objects[cell_key(action.cell)]["active"] = false
	_complete_successful_action(action, "%s disabled an enemy node" % GameDefs.player_label(current_player))
	return _result(true, status_message, action)


func _apply_skip(action: GameAction) -> Dictionary:
	_grant_energy(current_player, SKIP_ENERGY_GAIN)
	_complete_successful_action(action, "%s skipped" % GameDefs.player_label(current_player))
	return _result(true, status_message, action)


func _complete_successful_action(action: GameAction, message: String) -> void:
	_record_move(action, message)
	acted_this_round[action.player] = true
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
		"energy_after": energy[action.player],
		"round": round_number,
	})


func _end_turn(message: String) -> void:
	_update_active_nodes()
	var final_message := message

	if _round_ready_to_resolve():
		var resolve_result := _resolve_round()
		_annotate_last_move(resolve_result)
		final_message = "%s. %s" % [message, _resolve_result_message(resolve_result)]
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
			status_message = final_message
			current_player = GameDefs.other_player(current_player)
			_grant_energy(current_player, TURN_ENERGY_GAIN)


func _round_ready_to_resolve() -> bool:
	return bool(acted_this_round[GameDefs.PLAYER_ONE]) and bool(acted_this_round[GameDefs.PLAYER_TWO])


func _reset_round_actions() -> void:
	acted_this_round[GameDefs.PLAYER_ONE] = false
	acted_this_round[GameDefs.PLAYER_TWO] = false


func _resolve_round() -> Dictionary:
	_update_active_nodes()

	var owner := control_point_owner(CONTROL_POINT)
	var resource_awarded := 0

	if not owner.is_empty():
		resources[owner] += CONTROL_POINT_RESOURCE_GAIN
		resource_awarded = CONTROL_POINT_RESOURCE_GAIN

	var core_damage := _apply_core_damage()

	return {
		"round": round_number,
		"resource_player": owner,
		"resource_awarded": resource_awarded,
		"core_damage": core_damage,
		"winner": _winner(),
		"draw": _is_draw(),
	}


func _apply_core_damage() -> Dictionary:
	var damage := {
		GameDefs.PLAYER_ONE: 0,
		GameDefs.PLAYER_TWO: 0,
	}

	if _player_threatens_core(GameDefs.PLAYER_TWO, GameDefs.PLAYER_ONE):
		damage[GameDefs.PLAYER_ONE] = CORE_DAMAGE_PER_RESOLVE

	if _player_threatens_core(GameDefs.PLAYER_ONE, GameDefs.PLAYER_TWO):
		damage[GameDefs.PLAYER_TWO] = CORE_DAMAGE_PER_RESOLVE

	for player in damage.keys():
		var damage_amount: int = damage[player]

		if damage_amount <= 0:
			continue

		core_hp[player] = maxi(0, int(core_hp[player]) - damage_amount)

	return damage


func _player_threatens_core(attacker: String, defender: String) -> bool:
	var defender_core_cell := _core_cell(defender)

	if not contains_cell(defender_core_cell):
		return false

	for direction in HexGrid.DIRECTIONS:
		var object := get_object(defender_core_cell + direction)

		if object.is_empty():
			continue

		if object.get("owner") != attacker:
			continue

		if object.get("type") != OBJECT_NODE:
			continue

		if object.get("disabled", false):
			continue

		if object.get("active", false):
			return true

	return false


func _core_cell(owner: String) -> Vector2i:
	for key in objects.keys():
		var object: Dictionary = objects[key]

		if object.get("type") == OBJECT_CORE and object.get("owner") == owner:
			return object["cell"]

	return Vector2i(999, 999)


func _resolve_result_message(resolve_result: Dictionary) -> String:
	var messages: Array[String] = []
	var resource_player: String = resolve_result.get("resource_player", "")

	if resource_player.is_empty():
		messages.append("Round contested: no resource")
	else:
		messages.append("Round resource: %s +%dR" % [
			GameDefs.player_label(resource_player),
			int(resolve_result.get("resource_awarded", 0)),
		])

	var core_damage: Dictionary = resolve_result.get("core_damage", {})

	for player in [GameDefs.PLAYER_ONE, GameDefs.PLAYER_TWO]:
		var damage_amount := int(core_damage.get(player, 0))

		if damage_amount > 0:
			messages.append("%s Core -%dHP" % [GameDefs.player_label(player), damage_amount])

	return ". ".join(messages)


func _annotate_last_move(resolve_result: Dictionary) -> void:
	if move_history.is_empty():
		return

	var last_index := move_history.size() - 1
	move_history[last_index]["round"] = resolve_result["round"]
	move_history[last_index]["resource_player"] = resolve_result["resource_player"]
	move_history[last_index]["resource_awarded"] = resolve_result["resource_awarded"]
	move_history[last_index]["core_damage"] = resolve_result["core_damage"]
	move_history[last_index]["winner"] = resolve_result["winner"]
	move_history[last_index]["draw"] = resolve_result["draw"]


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


func _add_object(cell: Vector2i, type: String, owner: String) -> void:
	objects[cell_key(cell)] = {
		"cell": cell,
		"type": type,
		"owner": owner,
		"active": type == OBJECT_CORE,
		"disabled": false,
	}


func _spend_energy(player: String, amount: int) -> void:
	energy[player] = maxi(0, int(energy.get(player, 0)) - amount)


func _grant_energy(player: String, amount: int) -> void:
	energy[player] = mini(MAX_ENERGY, int(energy.get(player, 0)) + amount)


func _action_verb(action_type: String) -> String:
	match action_type:
		GameAction.TYPE_PLACE_NODE:
			return "place"
		GameAction.TYPE_BREAK_NODE:
			return "break"
		GameAction.TYPE_SKIP:
			return "skip"
		_:
			return action_type


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
