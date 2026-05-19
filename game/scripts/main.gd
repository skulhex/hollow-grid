extends Node2D

const BOARD_RADIUS := 3
const HEX_SIZE := 52.0
const DEFAULT_ACTION_TYPE := GameAction.TYPE_PLACE_NODE

@onready var board_view: BoardView = $BoardView
@onready var hud: GameHud = $HUD

var grid: HexGrid
var match_state: MatchState
var selected_action_type := DEFAULT_ACTION_TYPE


func _ready() -> void:
	grid = HexGrid.new(BOARD_RADIUS, HEX_SIZE)
	match_state = MatchState.new(BOARD_RADIUS)

	hud.action_selected.connect(_select_action)
	hud.skip_requested.connect(_skip_turn)
	hud.restart_requested.connect(_restart_match)

	board_view.setup(grid, match_state)
	board_view.set_selected_action_type(selected_action_type)
	_refresh()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_update_hover(event.position)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_handle_click(event)
	elif event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event)


func _handle_click(event: InputEventMouseButton) -> void:
	if match_state.finished:
		return

	var cell := board_view.screen_to_cell(event.position)

	if not grid.contains(cell):
		return

	if event.button_index == MOUSE_BUTTON_LEFT:
		_submit_selected_cell_action(cell)
	else:
		return


func _handle_key(event: InputEventKey) -> void:
	match event.keycode:
		KEY_1:
			_select_action(GameAction.TYPE_PLACE_NODE)
		KEY_2:
			_select_action(GameAction.TYPE_REPAIR_NODE)
		KEY_3:
			_select_action(GameAction.TYPE_UPGRADE_HARVESTER)
		KEY_4:
			_select_action(GameAction.TYPE_UPGRADE_STRIKER)
		KEY_SPACE:
			_skip_turn()
		KEY_R:
			_restart_match()


func _submit_selected_cell_action(cell: Vector2i) -> Dictionary:
	if not match_state.can_target_action(selected_action_type, cell):
		if match_state.can_target_action_shape(selected_action_type, cell) and not match_state.can_afford_target_action(match_state.current_player, selected_action_type, cell):
			if match_state.action_uses_resource(selected_action_type):
				var required_resource_cost := match_state.action_target_resource_cost(match_state.current_player, selected_action_type, cell)
				match_state.status_message = match_state.action_resource_requirement_message(selected_action_type, required_resource_cost)
			else:
				match_state.status_message = match_state.action_limit_requirement_message(selected_action_type)
		else:
			match_state.status_message = "Select a highlighted target for %s" % _action_label(selected_action_type)

		_refresh()
		return {
			"ok": false,
			"message": match_state.status_message,
		}

	match selected_action_type:
		GameAction.TYPE_PLACE_NODE:
			return _submit_action(GameAction.place_node(match_state.current_player, cell))
		GameAction.TYPE_REPAIR_NODE:
			return _submit_action(GameAction.repair_node(match_state.current_player, cell))
		GameAction.TYPE_UPGRADE_HARVESTER:
			return _submit_action(GameAction.upgrade_harvester(match_state.current_player, cell))
		GameAction.TYPE_UPGRADE_STRIKER:
			return _submit_action(GameAction.upgrade_striker(match_state.current_player, cell))
		_:
			return {
				"ok": false,
				"message": "Unsupported action",
			}


func _submit_action(action: GameAction) -> Dictionary:
	var result := match_state.apply_action(action.to_payload())
	_refresh()
	return result


func _select_action(action_type: String) -> void:
	if action_type not in [
		GameAction.TYPE_PLACE_NODE,
		GameAction.TYPE_REPAIR_NODE,
		GameAction.TYPE_UPGRADE_HARVESTER,
		GameAction.TYPE_UPGRADE_STRIKER,
	]:
		return

	selected_action_type = action_type
	board_view.set_selected_action_type(selected_action_type)
	_refresh()


func _skip_turn() -> void:
	if match_state.finished:
		return

	_submit_action(GameAction.skip(match_state.current_player))


func _restart_match() -> void:
	match_state.setup_match()
	selected_action_type = DEFAULT_ACTION_TYPE
	board_view.set_selected_action_type(selected_action_type)
	board_view.set_hover_cell(BoardView.HOVER_NONE)
	_refresh()


func _update_hover(mouse_position: Vector2) -> void:
	var next_hover := board_view.screen_to_cell(mouse_position)

	if not grid.contains(next_hover):
		next_hover = BoardView.HOVER_NONE

	board_view.set_hover_cell(next_hover)


func _refresh() -> void:
	board_view.set_selected_action_type(selected_action_type)
	board_view.queue_redraw()
	hud.refresh(match_state, selected_action_type)


func _action_label(action_type: String) -> String:
	match action_type:
		GameAction.TYPE_PLACE_NODE:
			return "Place"
		GameAction.TYPE_REPAIR_NODE:
			return "Repair"
		GameAction.TYPE_UPGRADE_HARVESTER:
			return "Upgrade Harvester"
		GameAction.TYPE_UPGRADE_STRIKER:
			return "Upgrade Striker"
		_:
			return action_type
