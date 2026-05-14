class_name GameAction
extends RefCounted

const TYPE_PLACE_NODE := "place_node"
const TYPE_BREAK_NODE := "break_node"
const TYPE_SKIP := "skip"

const KEY_TYPE := "type"
const KEY_PLAYER := "player"
const KEY_CELL := "cell"
const KEY_CELL_Q := "q"
const KEY_CELL_R := "r"

var action_type := ""
var player := ""
var cell := Vector2i.ZERO
var has_cell := false


func _init(start_action_type: String = "", start_player: String = "", start_cell: Vector2i = Vector2i.ZERO, start_has_cell: bool = false) -> void:
	action_type = start_action_type
	player = start_player
	cell = start_cell
	has_cell = start_has_cell


static func place_node(action_player: String, action_cell: Vector2i) -> GameAction:
	return GameAction.new(TYPE_PLACE_NODE, action_player, action_cell, true)


static func break_node(action_player: String, action_cell: Vector2i) -> GameAction:
	return GameAction.new(TYPE_BREAK_NODE, action_player, action_cell, true)


static func skip(action_player: String) -> GameAction:
	return GameAction.new(TYPE_SKIP, action_player)


static func from_payload(payload: Dictionary) -> GameAction:
	var parsed_action := GameAction.new(
		str(payload.get(KEY_TYPE, "")),
		str(payload.get(KEY_PLAYER, ""))
	)

	if payload.has(KEY_CELL):
		parsed_action.cell = _parse_cell(payload[KEY_CELL])
		parsed_action.has_cell = true

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

	return payload


func is_valid_shape() -> bool:
	if player.is_empty():
		return false

	if action_type == TYPE_SKIP:
		return not has_cell

	return action_type in [TYPE_PLACE_NODE, TYPE_BREAK_NODE] and has_cell


static func _parse_cell(raw_cell: Variant) -> Vector2i:
	if raw_cell is Vector2i:
		return raw_cell

	if raw_cell is Vector2:
		return Vector2i(int(raw_cell.x), int(raw_cell.y))

	if raw_cell is Dictionary:
		return Vector2i(int(raw_cell.get(KEY_CELL_Q, 0)), int(raw_cell.get(KEY_CELL_R, 0)))

	return Vector2i.ZERO
