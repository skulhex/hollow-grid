extends Node2D

const BOARD_RADIUS := 3
const HEX_SIZE := 52.0
const DEFAULT_ACTION_TYPE := GameAction.TYPE_PLACE_NODE

@onready var board_view: BoardView = $BoardView
@onready var hud: GameHud = $HUD

var grid: HexGrid
var match_state: MatchState
var selected_action_type := DEFAULT_ACTION_TYPE
var selected_striker_source := BoardView.HOVER_NONE


func _ready() -> void:
	grid = HexGrid.new(BOARD_RADIUS, HEX_SIZE)
	match_state = MatchState.new(BOARD_RADIUS)

	hud.action_selected.connect(_select_action)
	hud.skip_requested.connect(_skip_turn)
	hud.restart_requested.connect(_restart_match)

	board_view.setup(grid, match_state)
	board_view.set_selected_action_type(selected_action_type)
	board_view.set_striker_attack_source(selected_striker_source)
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
	if selected_action_type == GameAction.TYPE_STRIKER_ATTACK:
		return _submit_striker_attack_target(cell)

	if selected_action_type == DEFAULT_ACTION_TYPE and _cell_has_current_player_striker(cell):
		return _try_select_striker_source(cell)

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


func _submit_striker_attack_target(cell: Vector2i) -> Dictionary:
	if cell == selected_striker_source:
		_clear_striker_attack_mode(true)
		match_state.status_message = "Striker attack canceled"
		_refresh()
		return {
			"ok": false,
			"message": match_state.status_message,
		}

	if _cell_has_current_player_striker(cell):
		return _try_select_striker_source(cell)

	if not match_state.can_striker_attack(selected_striker_source, cell):
		match_state.status_message = "Select a highlighted target for Striker Attack"
		_refresh()
		return {
			"ok": false,
			"message": match_state.status_message,
		}

	var result := _submit_action(GameAction.striker_attack(match_state.current_player, selected_striker_source, cell))

	if bool(result.get("ok", false)):
		_clear_striker_attack_mode(true)
		_refresh()

	return result


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
	selected_striker_source = BoardView.HOVER_NONE
	board_view.set_selected_action_type(selected_action_type)
	board_view.set_striker_attack_source(selected_striker_source)
	_refresh()


func _skip_turn() -> void:
	if match_state.finished:
		return

	_clear_striker_attack_mode(false)
	_submit_action(GameAction.skip(match_state.current_player))


func _restart_match() -> void:
	match_state.setup_match()
	selected_action_type = DEFAULT_ACTION_TYPE
	selected_striker_source = BoardView.HOVER_NONE
	board_view.set_selected_action_type(selected_action_type)
	board_view.set_striker_attack_source(selected_striker_source)
	board_view.set_hover_cell(BoardView.HOVER_NONE)
	_refresh()


func _update_hover(mouse_position: Vector2) -> void:
	var next_hover := board_view.screen_to_cell(mouse_position)

	if not grid.contains(next_hover):
		next_hover = BoardView.HOVER_NONE

	board_view.set_hover_cell(next_hover)


func _refresh() -> void:
	board_view.set_selected_action_type(selected_action_type)
	board_view.set_striker_attack_source(selected_striker_source)
	board_view.queue_redraw()
	hud.refresh(match_state, selected_action_type, selected_striker_source)


func _try_select_striker_source(cell: Vector2i) -> Dictionary:
	if selected_action_type == GameAction.TYPE_STRIKER_ATTACK and cell == selected_striker_source:
		_clear_striker_attack_mode(true)
		match_state.status_message = "Striker attack canceled"
		_refresh()
		return {
			"ok": false,
			"message": match_state.status_message,
		}

	if not match_state.can_select_striker_source(cell):
		match_state.status_message = match_state.striker_source_status_message(cell)
		_refresh()
		return {
			"ok": false,
			"message": match_state.status_message,
		}

	selected_action_type = GameAction.TYPE_STRIKER_ATTACK
	selected_striker_source = cell
	match_state.status_message = "Select a target for Striker Attack"
	_refresh()
	return {
		"ok": true,
		"message": match_state.status_message,
	}


func _clear_striker_attack_mode(reset_to_default: bool) -> void:
	selected_striker_source = BoardView.HOVER_NONE

	if reset_to_default and selected_action_type == GameAction.TYPE_STRIKER_ATTACK:
		selected_action_type = DEFAULT_ACTION_TYPE


func _cell_has_current_player_striker(cell: Vector2i) -> bool:
	var object := match_state.get_object(cell)

	if object.is_empty():
		return false

	if object.get("type") != MatchState.OBJECT_NODE:
		return false

	if object.get("owner") != match_state.current_player:
		return false

	return object.get("role", MatchState.NODE_CONDUIT) == MatchState.NODE_STRIKER


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
		GameAction.TYPE_STRIKER_ATTACK:
			return "Striker Attack"
		_:
			return action_type
