class_name MatchState
extends RefCounted

const OBJECT_CORE := "core"
const OBJECT_NODE := "node"
const OBJECT_MODULE := "module"

const NODE_CONDUIT := "conduit"
const NODE_HARVESTER := "harvester"
const NODE_STRIKER := "striker"
const NODE_DEFENDER := "defender"
const NODE_HACKER := "hacker"

const MODULE_CONNECTION := "connection"
const MODULE_REPAIR := "repair"

const CONTROL_POINT := Vector2i(0, 0)
const INVALID_CELL := Vector2i(999, 999)

const START_CORE_HP := 5
const START_RESOURCE := 1
const CONNECTION_ACTIONS_PER_TURN := 1
const REPAIR_ACTIONS_PER_TURN := 1
const NODE_ROLE_ACTION_CHARGES_PER_TURN := 1
const HARVESTER_RESOURCE_GAIN := 1
const HARVESTER_UPGRADE_RESOURCE_COST := 1
const STRIKER_UPGRADE_RESOURCE_COST := 1
const DEFENDER_UPGRADE_RESOURCE_COST := 1
const HACKER_UPGRADE_RESOURCE_COST := 1
const MODULE_BUILD_RESOURCE_COST := 5
const STRIKER_CORE_DAMAGE := 1

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


func to_snapshot() -> Dictionary:
	return {
		"players": [
			GameDefs.PLAYER_ONE,
			GameDefs.PLAYER_TWO,
		],
		"current_player": current_player,
		"turn": turn_number,
		"round": round_number,
		"core_hp": {
			GameDefs.PLAYER_ONE: int(core_hp.get(GameDefs.PLAYER_ONE, 0)),
			GameDefs.PLAYER_TWO: int(core_hp.get(GameDefs.PLAYER_TWO, 0)),
		},
		"resources": {
			GameDefs.PLAYER_ONE: int(resources.get(GameDefs.PLAYER_ONE, 0)),
			GameDefs.PLAYER_TWO: int(resources.get(GameDefs.PLAYER_TWO, 0)),
		},
		"action_limits": {
			"connection_actions_left": connection_actions_left,
			"repair_actions_left": repair_actions_left,
		},
		"objects": _objects_to_snapshot(),
		"finished": finished,
		"status_message": status_message,
	}


func load_snapshot(snapshot: Dictionary) -> void:
	current_player = str(snapshot.get("current_player", current_player))
	turn_number = int(snapshot.get("turn", turn_number))
	round_number = int(snapshot.get("round", round_number))
	finished = bool(snapshot.get("finished", finished))
	status_message = str(snapshot.get("status_message", status_message))

	var snapshot_core_hp: Dictionary = _dictionary_from_snapshot(snapshot.get("core_hp", {}))
	core_hp[GameDefs.PLAYER_ONE] = int(snapshot_core_hp.get(GameDefs.PLAYER_ONE, core_hp[GameDefs.PLAYER_ONE]))
	core_hp[GameDefs.PLAYER_TWO] = int(snapshot_core_hp.get(GameDefs.PLAYER_TWO, core_hp[GameDefs.PLAYER_TWO]))

	var snapshot_resources: Dictionary = _dictionary_from_snapshot(snapshot.get("resources", {}))
	resources[GameDefs.PLAYER_ONE] = int(snapshot_resources.get(GameDefs.PLAYER_ONE, resources[GameDefs.PLAYER_ONE]))
	resources[GameDefs.PLAYER_TWO] = int(snapshot_resources.get(GameDefs.PLAYER_TWO, resources[GameDefs.PLAYER_TWO]))

	var action_limits: Dictionary = _dictionary_from_snapshot(snapshot.get("action_limits", {}))
	connection_actions_left = int(action_limits.get("connection_actions_left", connection_actions_left))
	repair_actions_left = int(action_limits.get("repair_actions_left", repair_actions_left))

	objects.clear()
	var snapshot_objects: Array = _array_from_snapshot(snapshot.get("objects", []))
	for raw_object in snapshot_objects:
		if not raw_object is Dictionary:
			continue

		var object := _object_from_snapshot(raw_object)
		if object.is_empty():
			continue

		objects[cell_key(object["cell"])] = object


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
		GameAction.TYPE_UPGRADE_DEFENDER:
			return _apply_upgrade_node(action, NODE_DEFENDER)
		GameAction.TYPE_UPGRADE_HACKER:
			return _apply_upgrade_node(action, NODE_HACKER)
		GameAction.TYPE_BUILD_CONNECTION_MODULE:
			return _apply_build_module(action, MODULE_CONNECTION)
		GameAction.TYPE_BUILD_REPAIR_MODULE:
			return _apply_build_module(action, MODULE_REPAIR)
		GameAction.TYPE_STRIKER_ATTACK:
			return _apply_striker_attack(action)
		GameAction.TYPE_HACKER_HACK:
			return _apply_hacker_hack(action)
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


func upgrade_defender(cell: Vector2i) -> Dictionary:
	return apply_action(GameAction.upgrade_defender(current_player, cell))


func upgrade_hacker(cell: Vector2i) -> Dictionary:
	return apply_action(GameAction.upgrade_hacker(current_player, cell))


func build_connection_module(cell: Vector2i) -> Dictionary:
	return apply_action(GameAction.build_connection_module(current_player, cell))


func build_repair_module(cell: Vector2i) -> Dictionary:
	return apply_action(GameAction.build_repair_module(current_player, cell))


func striker_attack(source_cell: Vector2i, cell: Vector2i) -> Dictionary:
	return apply_action(GameAction.striker_attack(current_player, source_cell, cell))


func hacker_hack(source_cell: Vector2i, cell: Vector2i) -> Dictionary:
	return apply_action(GameAction.hacker_hack(current_player, source_cell, cell))


func skip_turn() -> Dictionary:
	return apply_action(GameAction.skip(current_player))


func can_place_node(cell: Vector2i) -> bool:
	if not contains_cell(cell):
		return false

	if is_control_point(cell):
		return false

	if has_object(cell):
		return false

	return has_active_network_neighbor(current_player, cell)


func can_build_module(cell: Vector2i) -> bool:
	return _can_build_module(current_player, cell)


func can_break_node(cell: Vector2i) -> bool:
	if not contains_cell(cell):
		return false

	var object := get_object(cell)

	if object.is_empty():
		return false

	if not _is_disable_target(object):
		return false

	if object.get("disabled", false):
		return false

	if object.get("owner") == current_player:
		return false

	return has_active_network_neighbor(current_player, cell)


func can_repair_node(cell: Vector2i) -> bool:
	if not contains_cell(cell):
		return false

	var object := get_object(cell)

	if object.is_empty():
		return false

	if object.get("type") != OBJECT_NODE and object.get("type") != OBJECT_MODULE:
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

	if not _is_clear_target(object):
		return false

	if not object.get("disabled", false):
		return false

	if object.get("owner") == current_player:
		return true

	return has_active_network_neighbor(current_player, cell)


func can_upgrade_node(cell: Vector2i) -> bool:
	return _can_upgrade_node(current_player, cell)


func can_select_striker_source(cell: Vector2i) -> bool:
	return _can_select_striker_source(current_player, cell)


func can_select_hacker_source(cell: Vector2i) -> bool:
	return _can_select_hacker_source(current_player, cell)


func striker_source_status_message(cell: Vector2i) -> String:
	return _striker_source_status_message(current_player, cell)


func hacker_source_status_message(cell: Vector2i) -> String:
	return _hacker_source_status_message(current_player, cell)


func role_node_charge_preview(player: String) -> int:
	return _preview_role_node_action_charges(player)


func upkeep_preview(player: String) -> Dictionary:
	return {
		"player": player,
		"resource_gain": _harvester_resource_gain(player),
		"restored_charges": _preview_role_node_action_charges(player),
		"connection_bonus": _preview_module_bonus(player, MODULE_CONNECTION),
		"repair_bonus": _preview_module_bonus(player, MODULE_REPAIR),
	}


func can_striker_attack(source_cell: Vector2i, target_cell: Vector2i) -> bool:
	return _can_striker_attack(current_player, source_cell, target_cell)


func can_hacker_hack(source_cell: Vector2i, target_cell: Vector2i) -> bool:
	return _can_hacker_hack(current_player, source_cell, target_cell)


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
		GameAction.TYPE_UPGRADE_HARVESTER, GameAction.TYPE_UPGRADE_STRIKER, GameAction.TYPE_UPGRADE_DEFENDER, GameAction.TYPE_UPGRADE_HACKER:
			return can_upgrade_node(cell)
		GameAction.TYPE_BUILD_CONNECTION_MODULE, GameAction.TYPE_BUILD_REPAIR_MODULE:
			return can_build_module(cell)
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
		GameAction.TYPE_UPGRADE_DEFENDER:
			return DEFENDER_UPGRADE_RESOURCE_COST
		GameAction.TYPE_UPGRADE_HACKER:
			return HACKER_UPGRADE_RESOURCE_COST
		GameAction.TYPE_BUILD_CONNECTION_MODULE, GameAction.TYPE_BUILD_REPAIR_MODULE:
			return MODULE_BUILD_RESOURCE_COST

	return 0


func action_target_resource_cost(_player: String, action_type: String, _cell: Vector2i) -> int:
	return action_resource_cost(action_type)


func action_uses_resource(action_type: String) -> bool:
	return action_type in [
		GameAction.TYPE_UPGRADE_HARVESTER,
		GameAction.TYPE_UPGRADE_STRIKER,
		GameAction.TYPE_UPGRADE_DEFENDER,
		GameAction.TYPE_UPGRADE_HACKER,
		GameAction.TYPE_BUILD_CONNECTION_MODULE,
		GameAction.TYPE_BUILD_REPAIR_MODULE,
	]


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


func has_active_network_neighbor(owner: String, cell: Vector2i) -> bool:
	for direction in HexGrid.DIRECTIONS:
		var neighbor_object := get_object(cell + direction)

		if neighbor_object.is_empty():
			continue

		if neighbor_object.get("owner") != owner:
			continue

		if not neighbor_object.get("active", false):
			continue

		if _is_network_object(neighbor_object):
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
		status_message = "%s cannot repair that object" % GameDefs.player_label(current_player)
		return _result(false, status_message, action)

	if not can_afford_action(current_player, action.action_type):
		status_message = action_limit_requirement_message(action.action_type)
		return _result(false, status_message, action)

	_spend_repair_action()
	objects[cell_key(action.cell)]["disabled"] = false
	if objects[cell_key(action.cell)].get("type") == OBJECT_MODULE:
		objects[cell_key(action.cell)]["ready"] = false
	_complete_successful_action(action, "%s repaired a %s" % [
		GameDefs.player_label(current_player),
		_object_type_label(get_object(action.cell)),
	])
	return _result(true, status_message, action)


func _apply_build_module(action: GameAction, module_kind: String) -> Dictionary:
	if not can_build_module(action.cell):
		status_message = "%s cannot build a module there" % GameDefs.player_label(current_player)
		return _result(false, status_message, action)

	if not can_afford_target_action(current_player, action.action_type, action.cell):
		var module_cost := action_target_resource_cost(current_player, action.action_type, action.cell)
		status_message = action_resource_requirement_message(action.action_type, module_cost)
		return _result(false, status_message, action)

	_spend_resource(current_player, action_resource_cost(action.action_type))
	_add_object(action.cell, OBJECT_MODULE, current_player, module_kind)
	_complete_successful_action(action, "%s built a %s Module" % [
		GameDefs.player_label(current_player),
		_module_kind_label(module_kind),
	])
	return _result(true, status_message, action)


func _apply_break_node(action: GameAction) -> Dictionary:
	if not contains_cell(action.cell):
		status_message = "%s cannot break that cell" % GameDefs.player_label(current_player)
		return _result(false, status_message, action)

	var object := get_object(action.cell)

	if object.is_empty() or not _is_disable_target(object) or object.get("disabled", false) or object.get("owner") == current_player:
		status_message = "%s cannot break that cell" % GameDefs.player_label(current_player)
		return _result(false, status_message, action)

	if not has_active_network_neighbor(current_player, action.cell):
		status_message = "%s needs an active network neighbor to break that object" % GameDefs.player_label(current_player)
		return _result(false, status_message, action)

	if not can_afford_action(current_player, action.action_type):
		status_message = action_limit_requirement_message(action.action_type)
		return _result(false, status_message, action)

	objects[cell_key(action.cell)]["disabled"] = true
	objects[cell_key(action.cell)]["active"] = false
	_complete_successful_action(action, "%s disabled an enemy %s" % [
		GameDefs.player_label(current_player),
		_object_type_label(object),
	])
	return _result(true, status_message, action)


func _apply_clear_node(action: GameAction) -> Dictionary:
	if not can_clear_node(action.cell):
		status_message = "%s cannot clear that cell" % GameDefs.player_label(current_player)
		return _result(false, status_message, action)

	if not can_afford_target_action(current_player, action.action_type, action.cell):
		status_message = action_limit_requirement_message(action.action_type)
		return _result(false, status_message, action)

	var object := get_object(action.cell)
	var object_owner: String = object.get("owner", "")
	var object_label := _object_type_label(object)
	objects.erase(cell_key(action.cell))

	var clear_message := "%s cleared an enemy disabled %s" % [
		GameDefs.player_label(current_player),
		object_label,
	]

	if object_owner == current_player:
		clear_message = "%s cleared a friendly disabled %s" % [
			GameDefs.player_label(current_player),
			object_label,
		]

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
	objects[cell_key(action.cell)]["ready"] = false
	objects[cell_key(action.cell)]["action_charges"] = 0
	_complete_successful_action(action, "%s upgraded a %s" % [
		GameDefs.player_label(current_player),
		_node_role_label(role),
	])
	return _result(true, status_message, action)


func _apply_striker_attack(action: GameAction) -> Dictionary:
	if not _can_striker_attack(current_player, action.source_cell, action.cell):
		status_message = _striker_attack_status_message(current_player, action.source_cell, action.cell)
		return _result(false, status_message, action)

	var target := get_object(action.cell)
	var target_type: String = target.get("type", "")
	var defender_cell := _blocking_defender_cell(current_player, action.cell)

	if defender_cell != INVALID_CELL:
		objects[cell_key(action.source_cell)]["action_charges"] = 0
		objects[cell_key(defender_cell)]["action_charges"] = 0
		_complete_successful_action(action, "%s Defender blocked a Striker attack" % GameDefs.player_label(target.get("owner", "")))
		return _result(true, status_message, action)

	if target_type == OBJECT_NODE or target_type == OBJECT_MODULE:
		objects[cell_key(action.cell)]["disabled"] = true
		objects[cell_key(action.cell)]["active"] = false
		if target_type == OBJECT_MODULE:
			objects[cell_key(action.cell)]["ready"] = false
		objects[cell_key(action.source_cell)]["action_charges"] = 0
		_complete_successful_action(action, "%s Striker disabled an enemy %s" % [
			GameDefs.player_label(current_player),
			_object_type_label(target),
		])
		return _result(true, status_message, action)

	if target_type == OBJECT_CORE:
		var target_owner: String = target.get("owner", "")
		core_hp[target_owner] = maxi(0, int(core_hp.get(target_owner, 0)) - STRIKER_CORE_DAMAGE)
		objects[cell_key(action.source_cell)]["action_charges"] = 0
		_complete_successful_action(action, "%s Striker hit the enemy Core" % GameDefs.player_label(current_player))
		_check_finished_after_action(status_message)
		return _result(true, status_message, action)

	status_message = "%s cannot strike that target" % GameDefs.player_label(current_player)
	return _result(false, status_message, action)


func _apply_hacker_hack(action: GameAction) -> Dictionary:
	if not _can_hacker_hack(current_player, action.source_cell, action.cell):
		status_message = _hacker_hack_status_message(current_player, action.source_cell, action.cell)
		return _result(false, status_message, action)

	var target_key := cell_key(action.cell)
	objects[target_key]["owner"] = current_player
	objects[target_key]["disabled"] = true
	objects[target_key]["active"] = false
	objects[target_key]["ready"] = false
	objects[target_key]["action_charges"] = 0
	objects[cell_key(action.source_cell)]["action_charges"] = 0
	_complete_successful_action(action, "%s Hacker took control of a disabled Node" % GameDefs.player_label(current_player))
	return _result(true, status_message, action)


func _apply_skip(action: GameAction) -> Dictionary:
	_complete_turn(action, "%s ended turn" % GameDefs.player_label(current_player))
	return _result(true, status_message, action)


func _complete_successful_action(action: GameAction, message: String) -> void:
	_record_move(action, message)
	_update_active_nodes()
	status_message = message
	turn_number += 1


func _check_finished_after_action(message: String) -> void:
	if _is_draw():
		finished = true
		status_message = "%s. Draw: both Cores destroyed" % message
		return

	var winner := _winner()

	if not winner.is_empty():
		finished = true
		status_message = "%s. %s wins" % [message, GameDefs.player_label(winner)]


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
		"has_source_cell": action.has_source_cell,
		"source_cell": action.source_cell,
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
	_mark_active_modules(GameDefs.PLAYER_ONE)
	_mark_active_modules(GameDefs.PLAYER_TWO)


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

			if not _is_network_object(neighbor_object):
				continue

			visited[key] = true
			queue.append(neighbor)


func _mark_active_modules(owner: String) -> void:
	for key in objects.keys():
		var object: Dictionary = objects[key]

		if object.get("type") != OBJECT_MODULE:
			continue

		if object.get("owner") != owner:
			continue

		if object.get("disabled", false):
			object["active"] = false
			object["ready"] = false
			objects[key] = object
			continue

		object["active"] = has_active_network_neighbor(owner, object.get("cell", Vector2i.ZERO))
		if not object["active"]:
			object["ready"] = false
		objects[key] = object


func _can_build_module(player: String, cell: Vector2i) -> bool:
	if not contains_cell(cell):
		return false

	if is_control_point(cell):
		return false

	if has_object(cell):
		return false

	return has_active_network_neighbor(player, cell)


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


func _can_select_striker_source(player: String, cell: Vector2i) -> bool:
	if not contains_cell(cell):
		return false

	var object := get_object(cell)

	if object.is_empty():
		return false

	if object.get("type") != OBJECT_NODE:
		return false

	if object.get("owner") != player:
		return false

	if object.get("role", NODE_CONDUIT) != NODE_STRIKER:
		return false

	if object.get("disabled", false):
		return false

	if not object.get("active", false):
		return false

	if not object.get("ready", false):
		return false

	return int(object.get("action_charges", 0)) > 0


func _can_select_hacker_source(player: String, cell: Vector2i) -> bool:
	if not contains_cell(cell):
		return false

	var object := get_object(cell)

	if object.is_empty():
		return false

	if object.get("type") != OBJECT_NODE:
		return false

	if object.get("owner") != player:
		return false

	if object.get("role", NODE_CONDUIT) != NODE_HACKER:
		return false

	if object.get("disabled", false):
		return false

	if not object.get("active", false):
		return false

	if not object.get("ready", false):
		return false

	return int(object.get("action_charges", 0)) > 0


func _striker_source_status_message(player: String, cell: Vector2i) -> String:
	var object := get_object(cell)

	if object.is_empty() or object.get("type") != OBJECT_NODE or object.get("owner") != player or object.get("role", NODE_CONDUIT) != NODE_STRIKER:
		return "Select your ready Striker to attack"

	if object.get("disabled", false):
		return "%s Striker is disabled" % GameDefs.player_label(player)

	if not object.get("active", false):
		return "%s Striker is inactive" % GameDefs.player_label(player)

	if not object.get("ready", false):
		return "%s Striker is not ready" % GameDefs.player_label(player)

	if int(object.get("action_charges", 0)) <= 0:
		return "%s Striker has no charge" % GameDefs.player_label(player)

	return "%s Striker ready" % GameDefs.player_label(player)


func _hacker_source_status_message(player: String, cell: Vector2i) -> String:
	var object := get_object(cell)

	if object.is_empty() or object.get("type") != OBJECT_NODE or object.get("owner") != player or object.get("role", NODE_CONDUIT) != NODE_HACKER:
		return "Select your ready Hacker to hack"

	if object.get("disabled", false):
		return "%s Hacker is disabled" % GameDefs.player_label(player)

	if not object.get("active", false):
		return "%s Hacker is inactive" % GameDefs.player_label(player)

	if not object.get("ready", false):
		return "%s Hacker is not ready" % GameDefs.player_label(player)

	if int(object.get("action_charges", 0)) <= 0:
		return "%s Hacker has no charge" % GameDefs.player_label(player)

	return "%s Hacker ready" % GameDefs.player_label(player)


func _can_striker_attack(player: String, source_cell: Vector2i, target_cell: Vector2i) -> bool:
	if not _can_select_striker_source(player, source_cell):
		return false

	if not contains_cell(target_cell):
		return false

	if source_cell == target_cell:
		return false

	if not _are_neighbors(source_cell, target_cell):
		return false

	var target := get_object(target_cell)

	if target.is_empty():
		return false

	if target.get("owner") == player:
		return false

	match str(target.get("type", "")):
		OBJECT_NODE:
			return not target.get("disabled", false)
		OBJECT_MODULE:
			return not target.get("disabled", false) and target.get("active", false)
		OBJECT_CORE:
			return true
		_:
			return false


func _can_hacker_hack(player: String, source_cell: Vector2i, target_cell: Vector2i) -> bool:
	if not _can_select_hacker_source(player, source_cell):
		return false

	if not contains_cell(target_cell):
		return false

	if source_cell == target_cell:
		return false

	if not _are_neighbors(source_cell, target_cell):
		return false

	var target := get_object(target_cell)

	if target.is_empty():
		return false

	if target.get("owner") == player:
		return false

	if target.get("type") != OBJECT_NODE:
		return false

	return target.get("disabled", false)


func _striker_attack_status_message(player: String, source_cell: Vector2i, target_cell: Vector2i) -> String:
	if not _can_select_striker_source(player, source_cell):
		return _striker_source_status_message(player, source_cell)

	if not contains_cell(target_cell):
		return "%s Striker target is outside the board" % GameDefs.player_label(player)

	if not _are_neighbors(source_cell, target_cell):
		return "%s Striker can only hit adjacent targets" % GameDefs.player_label(player)

	var target := get_object(target_cell)

	if target.is_empty():
		return "%s Striker needs an enemy target" % GameDefs.player_label(player)

	if target.get("owner") == player:
		return "%s Striker cannot target friendly objects" % GameDefs.player_label(player)

	if _is_disable_target(target) and target.get("disabled", false):
		return "%s Striker target is already disabled" % GameDefs.player_label(player)

	if target.get("type") == OBJECT_MODULE and not target.get("active", false):
		return "%s Striker target module is inactive" % GameDefs.player_label(player)

	return "%s cannot strike that target" % GameDefs.player_label(player)


func _hacker_hack_status_message(player: String, source_cell: Vector2i, target_cell: Vector2i) -> String:
	if not _can_select_hacker_source(player, source_cell):
		return _hacker_source_status_message(player, source_cell)

	if not contains_cell(target_cell):
		return "%s Hacker target is outside the board" % GameDefs.player_label(player)

	if not _are_neighbors(source_cell, target_cell):
		return "%s Hacker can only hack adjacent targets" % GameDefs.player_label(player)

	var target := get_object(target_cell)

	if target.is_empty():
		return "%s Hacker needs a disabled enemy Node" % GameDefs.player_label(player)

	if target.get("owner") == player:
		return "%s Hacker cannot target friendly nodes" % GameDefs.player_label(player)

	if target.get("type") != OBJECT_NODE:
		return "%s Hacker can only target Nodes" % GameDefs.player_label(player)

	if not target.get("disabled", false):
		return "%s Hacker target must be disabled" % GameDefs.player_label(player)

	return "%s cannot hack that target" % GameDefs.player_label(player)


func _blocking_defender_cell(attacker: String, target_cell: Vector2i) -> Vector2i:
	var target := get_object(target_cell)

	if target.is_empty():
		return INVALID_CELL

	var target_owner: String = target.get("owner", "")

	if target_owner.is_empty() or target_owner == attacker:
		return INVALID_CELL

	for direction in HexGrid.DIRECTIONS:
		var defender_cell := target_cell + direction

		if defender_cell == target_cell:
			continue

		var defender := get_object(defender_cell)

		if defender.is_empty():
			continue

		if defender.get("type") != OBJECT_NODE:
			continue

		if defender.get("owner") != target_owner:
			continue

		if defender.get("role", NODE_CONDUIT) != NODE_DEFENDER:
			continue

		if defender.get("disabled", false):
			continue

		if not defender.get("active", false):
			continue

		if not defender.get("ready", false):
			continue

		if int(defender.get("action_charges", 0)) > 0:
			return defender_cell

	return INVALID_CELL


func _are_neighbors(first_cell: Vector2i, second_cell: Vector2i) -> bool:
	for direction in HexGrid.DIRECTIONS:
		if first_cell + direction == second_cell:
			return true

	return false


func _is_network_object(object: Dictionary) -> bool:
	return object.get("type") == OBJECT_CORE or object.get("type") == OBJECT_NODE


func _is_disable_target(object: Dictionary) -> bool:
	return object.get("type") == OBJECT_NODE or object.get("type") == OBJECT_MODULE


func _is_clear_target(object: Dictionary) -> bool:
	return object.get("type") == OBJECT_NODE or object.get("type") == OBJECT_MODULE


func _active_module_bonus(player: String, module_kind: String) -> int:
	var bonus := 0

	for key in objects.keys():
		var object: Dictionary = objects[key]

		if object.get("type") != OBJECT_MODULE:
			continue

		if object.get("owner") != player:
			continue

		if object.get("module_kind", "") != module_kind:
			continue

		if object.get("disabled", false):
			continue

		if object.get("active", false) and object.get("ready", false):
			bonus += 1

	return bonus


func _preview_module_bonus(player: String, module_kind: String) -> int:
	var bonus := 0

	for key in objects.keys():
		var object: Dictionary = objects[key]

		if object.get("type") != OBJECT_MODULE:
			continue

		if object.get("owner") != player:
			continue

		if object.get("module_kind", "") != module_kind:
			continue

		if object.get("disabled", false):
			continue

		if object.get("active", false):
			bonus += 1

	return bonus


func _harvester_resource_gain(player: String) -> int:
	var gain := 0

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

		if not object.get("ready", false):
			continue

		if object.get("active", false):
			gain += HARVESTER_RESOURCE_GAIN

	return gain


func _add_object(cell: Vector2i, type: String, owner: String, module_kind: String = "") -> void:
	var object := {
		"cell": cell,
		"type": type,
		"owner": owner,
		"active": type == OBJECT_CORE,
		"disabled": false,
	}

	if type == OBJECT_NODE:
		object["role"] = NODE_CONDUIT
		object["ready"] = false
		object["action_charges"] = 0
	elif type == OBJECT_MODULE:
		object["module_kind"] = module_kind
		object["ready"] = false

	objects[cell_key(cell)] = object


func _start_turn_for_player(player: String) -> void:
	_update_active_nodes()
	_ready_modules_for_player(player)
	_reset_turn_action_limits(player)

	var charged_nodes := _reset_role_node_action_charges(player)
	var resource_gain := _harvester_resource_gain(player)

	if resource_gain > 0:
		resources[player] += resource_gain

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
			object["ready"] = false
			object["action_charges"] = 0
			objects[key] = object
			continue

		if object.get("disabled", false):
			object["ready"] = false
			object["action_charges"] = 0
			objects[key] = object
			continue

		object["ready"] = true
		object["action_charges"] = NODE_ROLE_ACTION_CHARGES_PER_TURN
		objects[key] = object
		charged_nodes += 1

	return charged_nodes


func _ready_modules_for_player(player: String) -> int:
	var ready_modules := 0

	for key in objects.keys():
		var object: Dictionary = objects[key]

		if object.get("type") != OBJECT_MODULE:
			continue

		if object.get("owner") != player:
			continue

		var is_ready: bool = bool(object.get("active", false)) and not object.get("disabled", false)
		object["ready"] = is_ready
		objects[key] = object

		if is_ready:
			ready_modules += 1

	return ready_modules


func _preview_role_node_action_charges(player: String) -> int:
	var charged_nodes := 0

	for key in objects.keys():
		var object: Dictionary = objects[key]

		if object.get("type") != OBJECT_NODE:
			continue

		if object.get("owner") != player:
			continue

		if object.get("role", NODE_CONDUIT) == NODE_CONDUIT:
			continue

		if object.get("disabled", false):
			continue

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

	var connection_bonus := _active_module_bonus(player, MODULE_CONNECTION)
	var repair_bonus := _active_module_bonus(player, MODULE_REPAIR)

	if connection_bonus > 0:
		messages.append("+%d connection action%s" % [
			connection_bonus,
			"" if connection_bonus == 1 else "s",
		])

	if repair_bonus > 0:
		messages.append("+%d repair action%s" % [
			repair_bonus,
			"" if repair_bonus == 1 else "s",
		])

	if messages.is_empty():
		messages.append("ready")

	return "Upkeep: %s %s" % [
		GameDefs.player_label(player),
		", ".join(messages),
	]


func _spend_resource(player: String, amount: int) -> void:
	resources[player] = maxi(0, int(resources.get(player, 0)) - amount)


func _reset_turn_action_limits(player: String = current_player) -> void:
	connection_actions_left = CONNECTION_ACTIONS_PER_TURN + _active_module_bonus(player, MODULE_CONNECTION)
	repair_actions_left = REPAIR_ACTIONS_PER_TURN + _active_module_bonus(player, MODULE_REPAIR)


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
		GameAction.TYPE_UPGRADE_DEFENDER:
			return "upgrade a Defender"
		GameAction.TYPE_UPGRADE_HACKER:
			return "upgrade a Hacker"
		GameAction.TYPE_BUILD_CONNECTION_MODULE:
			return "build a Connection Module"
		GameAction.TYPE_BUILD_REPAIR_MODULE:
			return "build a Repair Module"
		GameAction.TYPE_STRIKER_ATTACK:
			return "strike"
		GameAction.TYPE_HACKER_HACK:
			return "hack"
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
		NODE_DEFENDER:
			return "Defender"
		NODE_HACKER:
			return "Hacker"
		_:
			return "Conduit"


func _module_kind_label(module_kind: String) -> String:
	match module_kind:
		MODULE_CONNECTION:
			return "Connection"
		MODULE_REPAIR:
			return "Repair"
		_:
			return str(module_kind).capitalize()


func _object_type_label(object: Dictionary) -> String:
	match str(object.get("type", "")):
		OBJECT_MODULE:
			return "%s module" % _module_kind_label(str(object.get("module_kind", ""))).to_lower()
		OBJECT_NODE:
			return "node"
		OBJECT_CORE:
			return "Core"
		_:
			return "object"


func _parse_action(raw_action: Variant) -> GameAction:
	if raw_action is GameAction:
		return raw_action

	if raw_action is Dictionary:
		return GameAction.from_payload(raw_action)

	return GameAction.new()


func _cell_to_payload(cell: Vector2i) -> Dictionary:
	return {
		GameAction.KEY_CELL_Q: cell.x,
		GameAction.KEY_CELL_R: cell.y,
	}


func _cell_from_payload(raw_cell: Variant) -> Vector2i:
	if raw_cell is Vector2i:
		return raw_cell

	if raw_cell is Dictionary:
		return Vector2i(
			int(raw_cell.get(GameAction.KEY_CELL_Q, 0)),
			int(raw_cell.get(GameAction.KEY_CELL_R, 0))
		)

	return Vector2i.ZERO


func _dictionary_from_snapshot(value: Variant) -> Dictionary:
	if value is Dictionary:
		return value

	return {}


func _array_from_snapshot(value: Variant) -> Array:
	if value is Array:
		return value

	return []


func _object_from_snapshot(snapshot: Dictionary) -> Dictionary:
	if not snapshot.has("cell"):
		return {}

	var object_type := str(snapshot.get("type", ""))
	if object_type not in [OBJECT_CORE, OBJECT_NODE, OBJECT_MODULE]:
		return {}

	var object := {
		"cell": _cell_from_payload(snapshot.get("cell", {})),
		"type": object_type,
		"owner": str(snapshot.get("owner", "")),
		"active": bool(snapshot.get("active", false)),
		"disabled": bool(snapshot.get("disabled", false)),
	}

	if object_type == OBJECT_NODE:
		object["role"] = str(snapshot.get("role", NODE_CONDUIT))
		object["ready"] = bool(snapshot.get("ready", false))
		object["action_charges"] = int(snapshot.get("action_charges", 0))
	elif object_type == OBJECT_MODULE:
		object["module_kind"] = str(snapshot.get("module_kind", ""))
		object["ready"] = bool(snapshot.get("ready", false))

	return object


func _objects_to_snapshot() -> Array[Dictionary]:
	var object_snapshots: Array[Dictionary] = []

	for key in objects.keys():
		object_snapshots.append(_object_to_snapshot(objects[key]))

	object_snapshots.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		var first_cell: Dictionary = first["cell"]
		var second_cell: Dictionary = second["cell"]
		var first_q := int(first_cell[GameAction.KEY_CELL_Q])
		var second_q := int(second_cell[GameAction.KEY_CELL_Q])

		if first_q == second_q:
			return int(first_cell[GameAction.KEY_CELL_R]) < int(second_cell[GameAction.KEY_CELL_R])

		return first_q < second_q
	)

	return object_snapshots


func _object_to_snapshot(object: Dictionary) -> Dictionary:
	var object_type := str(object.get("type", ""))
	var snapshot := {
		"cell": _cell_to_payload(object.get("cell", Vector2i.ZERO)),
		"type": object_type,
		"owner": str(object.get("owner", "")),
		"active": bool(object.get("active", false)),
		"disabled": bool(object.get("disabled", false)),
	}

	if object_type == OBJECT_NODE:
		snapshot["role"] = str(object.get("role", NODE_CONDUIT))
		snapshot["ready"] = bool(object.get("ready", false))
		snapshot["action_charges"] = int(object.get("action_charges", 0))
	elif object_type == OBJECT_MODULE:
		snapshot["module_kind"] = str(object.get("module_kind", ""))
		snapshot["ready"] = bool(object.get("ready", false))

	return snapshot


func _result(ok: bool, message: String, action: GameAction = null) -> Dictionary:
	var result := {
		"ok": ok,
		"message": message,
		"snapshot": to_snapshot(),
	}

	if action != null:
		result["action"] = action.to_payload()

	return result
