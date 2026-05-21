extends Node2D

const BOARD_RADIUS := 3
const HEX_SIZE := 52.0
const DEFAULT_ACTION_TYPE := GameAction.TYPE_PLACE_NODE
const MODE_LOCAL := "local"
const MODE_ONLINE := "online"
const DEFAULT_SERVER_URL := "ws://127.0.0.1:8787"
const ROOM_REQUEST_TIMEOUT_MS := 8000
const WEB_SERVER_URL_SCRIPT := """
(() => {
	const override = globalThis.HOLLOW_GRID_WS_URL;
	if (typeof override === "string" && override.trim() !== "") {
		return override.trim();
	}

	const protocol = globalThis.location.protocol === "https:" ? "wss:" : "ws:";
	return `${protocol}//${globalThis.location.host}/ws`;
})()
"""
const NetworkClientScript := preload("res://scripts/network_client.gd")

@onready var board_view: BoardView = $BoardView
@onready var hud: GameHud = $HUD

var grid: HexGrid
var match_state: MatchState
var network_client: RefCounted = NetworkClientScript.new()
var selected_action_type := DEFAULT_ACTION_TYPE
var selected_striker_source := BoardView.HOVER_NONE
var selected_hacker_source := BoardView.HOVER_NONE
var mode := MODE_LOCAL
var assigned_player := ""
var online_room_code := ""
var online_players: Array[String] = []
var network_status := "Local sandbox"
var pending_room_request := ""
var pending_join_room_code := ""
var pending_join_player := ""
var pending_room_request_started_msec := 0
var pending_action: Dictionary = {}


func _ready() -> void:
	grid = HexGrid.new(BOARD_RADIUS, HEX_SIZE)
	match_state = MatchState.new(BOARD_RADIUS)

	hud.action_selected.connect(_select_action)
	hud.upgrade_role_selected.connect(_submit_upgrade_role)
	hud.module_kind_selected.connect(_submit_module_kind)
	hud.skip_requested.connect(_skip_turn)
	hud.restart_requested.connect(_restart_match)
	hud.online_create_requested.connect(_create_online_room)
	hud.online_join_requested.connect(_join_online_room)
	hud.online_reconnect_requested.connect(_reconnect_online_room)
	hud.online_leave_requested.connect(_leave_online_room)
	_connect_network_client_signals()

	board_view.setup(grid, match_state)
	board_view.set_selected_action_type(selected_action_type)
	board_view.set_striker_attack_source(selected_striker_source)
	board_view.set_hacker_hack_source(selected_hacker_source)
	_refresh()


func _process(_delta: float) -> void:
	network_client.poll()
	_check_room_request_timeout()


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

	if hud.is_text_input_focused():
		hud.release_text_input_focus()

	var cell := board_view.screen_to_cell(event.position)

	if not grid.contains(cell):
		return

	if event.button_index == MOUSE_BUTTON_LEFT:
		_submit_selected_cell_action(cell)
	else:
		return


func _handle_key(event: InputEventKey) -> void:
	if hud.is_text_input_focused():
		return

	match event.keycode:
		KEY_1:
			_select_action(GameAction.TYPE_PLACE_NODE)
		KEY_2:
			_select_action(GameAction.TYPE_REPAIR_NODE)
		KEY_3:
			_select_action(GameHud.ACTION_UPGRADE_NODE)
		KEY_4:
			_select_action(GameHud.ACTION_BUILD_MODULE)
		KEY_SPACE:
			_skip_turn()
		KEY_R:
			_restart_match()


func _submit_selected_cell_action(cell: Vector2i) -> Dictionary:
	if not _can_submit_gameplay_action():
		return _blocked_action_result()

	if selected_action_type == GameAction.TYPE_STRIKER_ATTACK:
		return _submit_striker_attack_target(cell)

	if selected_action_type == GameAction.TYPE_HACKER_HACK:
		return _submit_hacker_hack_target(cell)

	if selected_action_type == GameHud.ACTION_UPGRADE_NODE:
		return _open_upgrade_role_menu(cell)

	if selected_action_type == GameHud.ACTION_BUILD_MODULE:
		return _open_module_kind_menu(cell)

	if selected_action_type == DEFAULT_ACTION_TYPE and _cell_has_current_player_striker(cell):
		return _try_select_striker_source(cell)

	if selected_action_type == DEFAULT_ACTION_TYPE and _cell_has_current_player_hacker(cell):
		return _try_select_hacker_source(cell)

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


func _submit_hacker_hack_target(cell: Vector2i) -> Dictionary:
	if cell == selected_hacker_source:
		_clear_hacker_hack_mode(true)
		match_state.status_message = "Hacker hack canceled"
		_refresh()
		return {
			"ok": false,
			"message": match_state.status_message,
		}

	if _cell_has_current_player_hacker(cell):
		return _try_select_hacker_source(cell)

	if not match_state.can_hacker_hack(selected_hacker_source, cell):
		match_state.status_message = "Select a highlighted target for Hacker Hack"
		_refresh()
		return {
			"ok": false,
			"message": match_state.status_message,
		}

	var result := _submit_action(GameAction.hacker_hack(match_state.current_player, selected_hacker_source, cell))

	if bool(result.get("ok", false)):
		_clear_hacker_hack_mode(true)
		_refresh()

	return result


func _submit_action(action: GameAction) -> Dictionary:
	if mode == MODE_ONLINE:
		return _submit_online_action(action)

	var result := match_state.apply_action(action.to_payload())
	_refresh()
	return result


func _select_action(action_type: String) -> void:
	if action_type not in [
			GameAction.TYPE_PLACE_NODE,
			GameAction.TYPE_REPAIR_NODE,
			GameHud.ACTION_UPGRADE_NODE,
			GameHud.ACTION_BUILD_MODULE,
		]:
		return

	selected_action_type = action_type
	selected_striker_source = BoardView.HOVER_NONE
	selected_hacker_source = BoardView.HOVER_NONE
	board_view.set_selected_action_type(selected_action_type)
	board_view.set_striker_attack_source(selected_striker_source)
	board_view.set_hacker_hack_source(selected_hacker_source)
	_refresh()


func _submit_upgrade_role(action_type: String, target_cell: Vector2i) -> void:
	match action_type:
		GameAction.TYPE_UPGRADE_HARVESTER:
			_submit_action(GameAction.upgrade_harvester(match_state.current_player, target_cell))
		GameAction.TYPE_UPGRADE_STRIKER:
			_submit_action(GameAction.upgrade_striker(match_state.current_player, target_cell))
		GameAction.TYPE_UPGRADE_DEFENDER:
			_submit_action(GameAction.upgrade_defender(match_state.current_player, target_cell))
		GameAction.TYPE_UPGRADE_HACKER:
			_submit_action(GameAction.upgrade_hacker(match_state.current_player, target_cell))


func _submit_module_kind(action_type: String, target_cell: Vector2i) -> void:
	match action_type:
		GameAction.TYPE_BUILD_CONNECTION_MODULE:
			_submit_action(GameAction.build_connection_module(match_state.current_player, target_cell))
		GameAction.TYPE_BUILD_REPAIR_MODULE:
			_submit_action(GameAction.build_repair_module(match_state.current_player, target_cell))


func _skip_turn() -> void:
	if match_state.finished:
		return

	if not _can_submit_gameplay_action():
		_blocked_action_result()
		return

	_clear_striker_attack_mode(false)
	_clear_hacker_hack_mode(false)
	_submit_action(GameAction.skip(match_state.current_player))


func _restart_match() -> void:
	if mode == MODE_ONLINE:
		match_state.status_message = "Restart is local-only in online mode"
		_refresh()
		return

	match_state.setup_match()
	selected_action_type = DEFAULT_ACTION_TYPE
	selected_striker_source = BoardView.HOVER_NONE
	selected_hacker_source = BoardView.HOVER_NONE
	board_view.set_selected_action_type(selected_action_type)
	board_view.set_striker_attack_source(selected_striker_source)
	board_view.set_hacker_hack_source(selected_hacker_source)
	board_view.set_hover_cell(BoardView.HOVER_NONE)
	_refresh()


func _update_hover(mouse_position: Vector2) -> void:
	var next_hover := board_view.screen_to_cell(mouse_position)

	if not grid.contains(next_hover):
		next_hover = BoardView.HOVER_NONE

	if next_hover == board_view.hover_cell:
		return

	board_view.set_hover_cell(next_hover)
	_refresh()


func _refresh() -> void:
	board_view.set_selected_action_type(selected_action_type)
	board_view.set_striker_attack_source(selected_striker_source)
	board_view.set_hacker_hack_source(selected_hacker_source)
	board_view.queue_redraw()
	hud.refresh(match_state, selected_action_type, selected_striker_source, selected_hacker_source, board_view.hover_cell, _network_hud_state())


func _connect_network_client_signals() -> void:
	network_client.connected.connect(_on_network_connected)
	network_client.disconnected.connect(_on_network_disconnected)
	network_client.room_created.connect(_on_room_created)
	network_client.joined.connect(_on_room_joined)
	network_client.player_joined.connect(_on_player_joined)
	network_client.presence_updated.connect(_on_presence_updated)
	network_client.snapshot_received.connect(_on_snapshot_received)
	network_client.error_received.connect(_on_network_error)
	network_client.connection_status_changed.connect(_on_connection_status_changed)


func _server_url() -> String:
	if OS.has_feature("web"):
		var resolved_url: Variant = JavaScriptBridge.eval(WEB_SERVER_URL_SCRIPT)
		if resolved_url is String and not resolved_url.strip_edges().is_empty():
			return resolved_url.strip_edges()

	return DEFAULT_SERVER_URL


func _create_online_room() -> void:
	if not _can_start_room_request():
		_refresh()
		return

	mode = MODE_ONLINE
	assigned_player = ""
	online_room_code = ""
	online_players.clear()
	pending_action.clear()
	pending_room_request = "create"
	pending_join_room_code = ""
	pending_join_player = ""
	pending_room_request_started_msec = Time.get_ticks_msec()
	network_status = "Connecting"
	match_state.status_message = "Connecting to server"
	var error: int = network_client.connect_to_server(_server_url())
	if error != OK:
		pending_room_request = ""
		pending_room_request_started_msec = 0
		match_state.status_message = "Connect failed: %s" % error_string(error)
	_refresh()


func _join_online_room(room_code: String) -> void:
	if not _can_start_room_request():
		_refresh()
		return

	var normalized_room_code := room_code.strip_edges().to_upper()
	if normalized_room_code.is_empty():
		match_state.status_message = "Room code is required"
		_refresh()
		return

	mode = MODE_ONLINE
	assigned_player = ""
	online_room_code = normalized_room_code
	online_players.clear()
	pending_action.clear()
	pending_room_request = "join"
	pending_join_room_code = online_room_code
	pending_join_player = ""
	pending_room_request_started_msec = Time.get_ticks_msec()
	network_status = "Connecting"
	match_state.status_message = "Joining %s..." % pending_join_room_code
	var error: int = network_client.connect_to_server(_server_url())
	if error != OK:
		pending_room_request = ""
		pending_room_request_started_msec = 0
		match_state.status_message = "Connect failed: %s" % error_string(error)
	_refresh()


func _reconnect_online_room() -> void:
	if pending_room_request != "":
		match_state.status_message = "Network request is already in progress"
		_refresh()
		return

	if online_room_code.is_empty() or assigned_player.is_empty():
		match_state.status_message = "No online room to reconnect"
		_refresh()
		return

	if network_client.is_socket_connected():
		match_state.status_message = "Already connected"
		_refresh()
		return

	mode = MODE_ONLINE
	online_players.clear()
	pending_action.clear()
	pending_room_request = "join"
	pending_join_room_code = online_room_code
	pending_join_player = assigned_player
	pending_room_request_started_msec = Time.get_ticks_msec()
	network_status = "Reconnecting"
	match_state.status_message = "Reconnecting as %s..." % GameDefs.player_label(assigned_player)
	var error: int = network_client.connect_to_server(_server_url())
	if error != OK:
		pending_room_request = ""
		pending_room_request_started_msec = 0
		match_state.status_message = "Reconnect failed: %s" % error_string(error)
	_refresh()


func _on_network_connected() -> void:
	if pending_room_request == "create":
		var error: int = network_client.create_room()
		if error != OK:
			pending_room_request = ""
			pending_room_request_started_msec = 0
			match_state.status_message = "Create room failed: %s" % error_string(error)
	elif pending_room_request == "join":
		var error: int = network_client.join_room(pending_join_room_code, pending_join_player)
		if error != OK:
			pending_room_request = ""
			pending_room_request_started_msec = 0
			match_state.status_message = "Join room failed: %s" % error_string(error)

	_refresh()


func _check_room_request_timeout() -> void:
	if pending_room_request == "" or pending_room_request_started_msec <= 0:
		return

	var elapsed := Time.get_ticks_msec() - pending_room_request_started_msec
	if elapsed < ROOM_REQUEST_TIMEOUT_MS:
		return

	var timed_out_request := pending_room_request
	var timed_out_player := pending_join_player
	pending_room_request = ""
	pending_join_room_code = ""
	pending_join_player = ""
	pending_room_request_started_msec = 0
	pending_action.clear()
	network_client.disconnect_from_server()

	if not assigned_player.is_empty() and not online_room_code.is_empty():
		network_status = "Disconnected"
		match_state.status_message = "Reconnect timed out"
	else:
		mode = MODE_LOCAL
		assigned_player = ""
		online_room_code = ""
		online_players.clear()
		network_status = "Local sandbox"
		match_state.status_message = "%s timed out" % ("Reconnect" if not timed_out_player.is_empty() else "Connection" if timed_out_request == "create" else "Join")

	_refresh()


func _on_network_disconnected() -> void:
	network_status = "Disconnected"
	online_players.clear()
	pending_action.clear()
	pending_room_request = ""
	pending_room_request_started_msec = 0
	if not assigned_player.is_empty() and not online_room_code.is_empty():
		match_state.status_message = "Disconnected. Reconnect as %s" % GameDefs.player_label(assigned_player)
	else:
		match_state.status_message = "Disconnected from server"
	_refresh()


func _on_room_created(room_code: String, player: String, snapshot: Dictionary) -> void:
	pending_room_request = ""
	pending_room_request_started_msec = 0
	pending_join_player = ""
	online_room_code = room_code
	assigned_player = player
	online_players.assign([player])
	network_status = "Room %s as %s" % [online_room_code, GameDefs.player_label(assigned_player)]
	_apply_server_snapshot(snapshot)


func _on_room_joined(room_code: String, player: String, snapshot: Dictionary) -> void:
	pending_room_request = ""
	pending_room_request_started_msec = 0
	pending_join_player = ""
	online_room_code = room_code
	assigned_player = player
	online_players.assign([player])
	network_status = "Room %s as %s" % [online_room_code, GameDefs.player_label(assigned_player)]
	_apply_server_snapshot(snapshot)


func _on_player_joined(players: Array, snapshot: Dictionary) -> void:
	online_players.clear()
	for player in players:
		online_players.append(str(player))

	network_status = "Room %s ready" % online_room_code
	_apply_server_snapshot(snapshot)


func _on_presence_updated(_players: Array, connected_players: Array, snapshot: Dictionary) -> void:
	online_players.clear()
	for player in connected_players:
		online_players.append(str(player))

	if not assigned_player.is_empty():
		network_status = "Room %s - %s" % [online_room_code, GameDefs.player_label(assigned_player)]
	_apply_server_snapshot(snapshot)


func _on_snapshot_received(snapshot: Dictionary) -> void:
	_apply_server_snapshot(snapshot)


func _on_network_error(message: String) -> void:
	pending_action.clear()
	pending_room_request = ""
	pending_room_request_started_msec = 0
	pending_join_player = ""
	match_state.status_message = message
	_refresh()


func _on_connection_status_changed(status_text: String) -> void:
	if assigned_player.is_empty():
		network_status = status_text
	else:
		network_status = "%s - %s" % [status_text, GameDefs.player_label(assigned_player)]

	_refresh()


func _leave_online_room() -> void:
	network_client.disconnect_from_server()
	mode = MODE_LOCAL
	assigned_player = ""
	online_room_code = ""
	online_players.clear()
	pending_action.clear()
	pending_room_request = ""
	pending_join_room_code = ""
	pending_join_player = ""
	pending_room_request_started_msec = 0
	network_status = "Local sandbox"
	match_state.setup_match()
	selected_action_type = DEFAULT_ACTION_TYPE
	selected_striker_source = BoardView.HOVER_NONE
	selected_hacker_source = BoardView.HOVER_NONE
	board_view.set_selected_action_type(selected_action_type)
	board_view.set_striker_attack_source(selected_striker_source)
	board_view.set_hacker_hack_source(selected_hacker_source)
	board_view.set_hover_cell(BoardView.HOVER_NONE)
	hud.clear_room_code_input()
	_refresh()


func _can_start_room_request() -> bool:
	if pending_room_request != "":
		match_state.status_message = "Network request is already in progress"
		return false

	if mode == MODE_ONLINE and not assigned_player.is_empty():
		match_state.status_message = "Leave the current room first"
		return false

	return true


func _submit_online_action(action: GameAction) -> Dictionary:
	if not _can_submit_gameplay_action():
		return _blocked_action_result()

	var payload := action.to_payload()
	payload[GameAction.KEY_PLAYER] = assigned_player
	var error: int = network_client.send_action(payload)
	if error != OK:
		match_state.status_message = "Send action failed: %s" % error_string(error)
		_refresh()
		return {
			"ok": false,
			"message": match_state.status_message,
		}

	pending_action = payload
	match_state.status_message = "Waiting for server snapshot"
	_refresh()
	return {
		"ok": true,
		"message": match_state.status_message,
		"action": payload,
	}


func _apply_server_snapshot(snapshot: Dictionary) -> void:
	var completed_action := pending_action.duplicate()
	pending_action.clear()
	match_state.load_snapshot(snapshot)

	if not completed_action.is_empty():
		var completed_type := str(completed_action.get(GameAction.KEY_TYPE, ""))
		if completed_type == GameAction.TYPE_STRIKER_ATTACK:
			_clear_striker_attack_mode(true)
		elif completed_type == GameAction.TYPE_HACKER_HACK:
			_clear_hacker_hack_mode(true)

	_refresh()


func _can_submit_gameplay_action() -> bool:
	if match_state.finished:
		return false

	if mode == MODE_LOCAL:
		return true

	if not network_client.is_socket_connected():
		return false

	if assigned_player.is_empty():
		return false

	if not pending_action.is_empty():
		return false

	return match_state.current_player == assigned_player


func _blocked_action_result() -> Dictionary:
	if mode == MODE_ONLINE:
		if not network_client.is_socket_connected():
			match_state.status_message = "Connect or join a room first"
		elif assigned_player.is_empty():
			match_state.status_message = "Waiting for room assignment"
		elif not pending_action.is_empty():
			match_state.status_message = "Waiting for server snapshot"
		elif match_state.current_player != assigned_player:
			match_state.status_message = "Waiting for %s" % GameDefs.player_label(match_state.current_player)
		else:
			match_state.status_message = "Action is blocked"

		_refresh()

	return {
		"ok": false,
		"message": match_state.status_message,
	}


func _network_hud_state() -> Dictionary:
	return {
		"mode": mode,
		"connected": network_client.is_socket_connected(),
		"assigned_player": assigned_player,
		"room_code": online_room_code,
		"players": online_players,
		"pending_action": not pending_action.is_empty(),
		"pending_room_request": pending_room_request,
		"reconnect_available": mode == MODE_ONLINE and not online_room_code.is_empty() and not assigned_player.is_empty() and not network_client.is_socket_connected(),
		"status": network_status,
	}


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
	selected_hacker_source = BoardView.HOVER_NONE
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


func _try_select_hacker_source(cell: Vector2i) -> Dictionary:
	if selected_action_type == GameAction.TYPE_HACKER_HACK and cell == selected_hacker_source:
		_clear_hacker_hack_mode(true)
		match_state.status_message = "Hacker hack canceled"
		_refresh()
		return {
			"ok": false,
			"message": match_state.status_message,
		}

	if not match_state.can_select_hacker_source(cell):
		match_state.status_message = match_state.hacker_source_status_message(cell)
		_refresh()
		return {
			"ok": false,
			"message": match_state.status_message,
		}

	selected_action_type = GameAction.TYPE_HACKER_HACK
	selected_hacker_source = cell
	selected_striker_source = BoardView.HOVER_NONE
	match_state.status_message = "Select a target for Hacker Hack"
	_refresh()
	return {
		"ok": true,
		"message": match_state.status_message,
	}


func _clear_hacker_hack_mode(reset_to_default: bool) -> void:
	selected_hacker_source = BoardView.HOVER_NONE

	if reset_to_default and selected_action_type == GameAction.TYPE_HACKER_HACK:
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


func _cell_has_current_player_hacker(cell: Vector2i) -> bool:
	var object := match_state.get_object(cell)

	if object.is_empty():
		return false

	if object.get("type") != MatchState.OBJECT_NODE:
		return false

	if object.get("owner") != match_state.current_player:
		return false

	return object.get("role", MatchState.NODE_CONDUIT) == MatchState.NODE_HACKER


func _open_upgrade_role_menu(cell: Vector2i) -> Dictionary:
	if not _can_select_upgrade_target(cell):
		if match_state.can_target_action_shape(GameAction.TYPE_UPGRADE_HARVESTER, cell) and not match_state.can_afford_target_action(match_state.current_player, GameAction.TYPE_UPGRADE_HARVESTER, cell):
			var required_resource_cost := match_state.action_target_resource_cost(match_state.current_player, GameAction.TYPE_UPGRADE_HARVESTER, cell)
			match_state.status_message = match_state.action_resource_requirement_message(GameAction.TYPE_UPGRADE_HARVESTER, required_resource_cost)
		else:
			match_state.status_message = "Select a highlighted node to upgrade"

		_refresh()
		return {
			"ok": false,
			"message": match_state.status_message,
		}

	hud.show_upgrade_menu(get_viewport().get_mouse_position(), cell)
	match_state.status_message = "Choose a role for this node"
	_refresh()
	return {
		"ok": true,
		"message": match_state.status_message,
	}


func _can_select_upgrade_target(cell: Vector2i) -> bool:
	return match_state.can_target_action(GameAction.TYPE_UPGRADE_HARVESTER, cell) or match_state.can_target_action(GameAction.TYPE_UPGRADE_STRIKER, cell) or match_state.can_target_action(GameAction.TYPE_UPGRADE_DEFENDER, cell) or match_state.can_target_action(GameAction.TYPE_UPGRADE_HACKER, cell)


func _open_module_kind_menu(cell: Vector2i) -> Dictionary:
	if not _can_select_module_target(cell):
		if match_state.can_target_action_shape(GameAction.TYPE_BUILD_CONNECTION_MODULE, cell) and not match_state.can_afford_target_action(match_state.current_player, GameAction.TYPE_BUILD_CONNECTION_MODULE, cell):
			var required_resource_cost := match_state.action_target_resource_cost(match_state.current_player, GameAction.TYPE_BUILD_CONNECTION_MODULE, cell)
			match_state.status_message = match_state.action_resource_requirement_message(GameAction.TYPE_BUILD_CONNECTION_MODULE, required_resource_cost)
		else:
			match_state.status_message = "Select a highlighted hex to build a module"

		_refresh()
		return {
			"ok": false,
			"message": match_state.status_message,
		}

	hud.show_module_menu(get_viewport().get_mouse_position(), cell)
	match_state.status_message = "Choose a module for this hex"
	_refresh()
	return {
		"ok": true,
		"message": match_state.status_message,
	}


func _can_select_module_target(cell: Vector2i) -> bool:
	return match_state.can_target_action(GameAction.TYPE_BUILD_CONNECTION_MODULE, cell) or match_state.can_target_action(GameAction.TYPE_BUILD_REPAIR_MODULE, cell)


func _action_label(action_type: String) -> String:
	match action_type:
		GameAction.TYPE_PLACE_NODE:
			return "Build connection"
		GameAction.TYPE_REPAIR_NODE:
			return "Repair"
		GameHud.ACTION_UPGRADE_NODE:
			return "Upgrade node"
		GameHud.ACTION_BUILD_MODULE:
			return "Build module"
		GameAction.TYPE_UPGRADE_HARVESTER:
			return "Upgrade node: Harvester"
		GameAction.TYPE_UPGRADE_STRIKER:
			return "Upgrade node: Striker"
		GameAction.TYPE_UPGRADE_DEFENDER:
			return "Upgrade node: Defender"
		GameAction.TYPE_UPGRADE_HACKER:
			return "Upgrade node: Hacker"
		GameAction.TYPE_BUILD_CONNECTION_MODULE:
			return "Build module: Connection"
		GameAction.TYPE_BUILD_REPAIR_MODULE:
			return "Build module: Repair"
		GameAction.TYPE_STRIKER_ATTACK:
			return "Striker Attack"
		GameAction.TYPE_HACKER_HACK:
			return "Hacker Hack"
		_:
			return action_type
