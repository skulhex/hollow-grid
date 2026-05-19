class_name GameAction
extends RefCounted

const TYPE_PLACE_NODE := "place_node"
const TYPE_REPAIR_NODE := "repair_node"
const TYPE_BREAK_NODE := "break_node"
const TYPE_CLEAR_NODE := "clear_node"
const TYPE_UPGRADE_HARVESTER := "upgrade_harvester"
const TYPE_UPGRADE_STRIKER := "upgrade_striker"
const TYPE_UPGRADE_DEFENDER := "upgrade_defender"
const TYPE_UPGRADE_HACKER := "upgrade_hacker"
const TYPE_BUILD_CONNECTION_MODULE := "build_connection_module"
const TYPE_BUILD_REPAIR_MODULE := "build_repair_module"
const TYPE_STRIKER_ATTACK := "striker_attack"
const TYPE_HACKER_HACK := "hacker_hack"
const TYPE_SKIP := "skip"

const KEY_TYPE := "type"
const KEY_PLAYER := "player"
const KEY_CELL := "cell"
const KEY_SOURCE_CELL := "source_cell"
const KEY_CELL_Q := "q"
const KEY_CELL_R := "r"

var action_type := ""
var player := ""
var cell := Vector2i.ZERO
var has_cell := false
var source_cell := Vector2i.ZERO
var has_source_cell := false
var invalid_shape := false


func _init(start_action_type: String = "", start_player: String = "", start_cell: Vector2i = Vector2i.ZERO, start_has_cell: bool = false, start_source_cell: Vector2i = Vector2i.ZERO, start_has_source_cell: bool = false) -> void:
	action_type = start_action_type
	player = start_player
	cell = start_cell
	has_cell = start_has_cell
	source_cell = start_source_cell
	has_source_cell = start_has_source_cell


static func place_node(action_player: String, action_cell: Vector2i) -> GameAction:
	return GameAction.new(TYPE_PLACE_NODE, action_player, action_cell, true)


static func repair_node(action_player: String, action_cell: Vector2i) -> GameAction:
	return GameAction.new(TYPE_REPAIR_NODE, action_player, action_cell, true)


static func break_node(action_player: String, action_cell: Vector2i) -> GameAction:
	return GameAction.new(TYPE_BREAK_NODE, action_player, action_cell, true)


static func clear_node(action_player: String, action_cell: Vector2i) -> GameAction:
	return GameAction.new(TYPE_CLEAR_NODE, action_player, action_cell, true)


static func upgrade_harvester(action_player: String, action_cell: Vector2i) -> GameAction:
	return GameAction.new(TYPE_UPGRADE_HARVESTER, action_player, action_cell, true)


static func upgrade_striker(action_player: String, action_cell: Vector2i) -> GameAction:
	return GameAction.new(TYPE_UPGRADE_STRIKER, action_player, action_cell, true)


static func upgrade_defender(action_player: String, action_cell: Vector2i) -> GameAction:
	return GameAction.new(TYPE_UPGRADE_DEFENDER, action_player, action_cell, true)


static func upgrade_hacker(action_player: String, action_cell: Vector2i) -> GameAction:
	return GameAction.new(TYPE_UPGRADE_HACKER, action_player, action_cell, true)


static func build_connection_module(action_player: String, action_cell: Vector2i) -> GameAction:
	return GameAction.new(TYPE_BUILD_CONNECTION_MODULE, action_player, action_cell, true)


static func build_repair_module(action_player: String, action_cell: Vector2i) -> GameAction:
	return GameAction.new(TYPE_BUILD_REPAIR_MODULE, action_player, action_cell, true)


static func striker_attack(action_player: String, action_source_cell: Vector2i, action_cell: Vector2i) -> GameAction:
	return GameAction.new(TYPE_STRIKER_ATTACK, action_player, action_cell, true, action_source_cell, true)


static func hacker_hack(action_player: String, action_source_cell: Vector2i, action_cell: Vector2i) -> GameAction:
	return GameAction.new(TYPE_HACKER_HACK, action_player, action_cell, true, action_source_cell, true)


static func skip(action_player: String) -> GameAction:
	return GameAction.new(TYPE_SKIP, action_player)


static func from_payload(payload: Dictionary) -> GameAction:
	var parsed_action := GameAction.new(
		str(payload.get(KEY_TYPE, "")),
		str(payload.get(KEY_PLAYER, ""))
	)

	if payload.has(KEY_CELL):
		var raw_cell: Variant = payload[KEY_CELL]

		if not _is_valid_cell_payload(raw_cell):
			parsed_action.invalid_shape = true
			return parsed_action

		parsed_action.cell = _parse_cell(raw_cell)
		parsed_action.has_cell = true

	if payload.has(KEY_SOURCE_CELL):
		var raw_source_cell: Variant = payload[KEY_SOURCE_CELL]

		if not _is_valid_cell_payload(raw_source_cell):
			parsed_action.invalid_shape = true
			return parsed_action

		parsed_action.source_cell = _parse_cell(raw_source_cell)
		parsed_action.has_source_cell = true

	return parsed_action


func to_payload() -> Dictionary:
	var payload := {
		KEY_TYPE: action_type,
		KEY_PLAYER: player,
	}

	if has_cell:
		payload[KEY_CELL] = {
			KEY_CELL_Q: cell.x,
			KEY_CELL_R: cell.y,
		}

	if has_source_cell:
		payload[KEY_SOURCE_CELL] = {
			KEY_CELL_Q: source_cell.x,
			KEY_CELL_R: source_cell.y,
		}

	return payload


func is_valid_shape() -> bool:
	if invalid_shape:
		return false

	if player.is_empty():
		return false

	if action_type == TYPE_SKIP:
		return not has_cell and not has_source_cell

	if action_type == TYPE_STRIKER_ATTACK or action_type == TYPE_HACKER_HACK:
		return has_cell and has_source_cell

	return action_type in [
		TYPE_PLACE_NODE,
		TYPE_REPAIR_NODE,
		TYPE_BREAK_NODE,
		TYPE_CLEAR_NODE,
		TYPE_UPGRADE_HARVESTER,
		TYPE_UPGRADE_STRIKER,
		TYPE_UPGRADE_DEFENDER,
		TYPE_UPGRADE_HACKER,
		TYPE_BUILD_CONNECTION_MODULE,
		TYPE_BUILD_REPAIR_MODULE,
	] and has_cell and not has_source_cell


static func _parse_cell(raw_cell: Variant) -> Vector2i:
	if raw_cell is Vector2i:
		return raw_cell

	if raw_cell is Dictionary:
		return Vector2i(int(raw_cell.get(KEY_CELL_Q, 0)), int(raw_cell.get(KEY_CELL_R, 0)))

	return Vector2i.ZERO


static func _is_valid_cell_payload(raw_cell: Variant) -> bool:
	if raw_cell is Vector2i:
		return true

	if raw_cell is Dictionary:
		if not raw_cell.has(KEY_CELL_Q) or not raw_cell.has(KEY_CELL_R):
			return false

		return _is_int_like(raw_cell[KEY_CELL_Q]) and _is_int_like(raw_cell[KEY_CELL_R])

	return false


static func _is_int_like(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true

	if typeof(value) == TYPE_FLOAT:
		return is_equal_approx(value, round(value))

	return false
