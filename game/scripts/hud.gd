class_name GameHud
extends CanvasLayer

signal action_selected(action_type: String)
signal upgrade_role_selected(action_type: String, target_cell: Vector2i)
signal module_kind_selected(action_type: String, target_cell: Vector2i)
signal skip_requested
signal restart_requested
signal online_create_requested
signal online_join_requested(room_code: String)
signal online_reconnect_requested
signal online_leave_requested

const ACTION_UPGRADE_NODE := "upgrade_node"
const ACTION_BUILD_MODULE := "build_module"
const MENU_HARVESTER := 1
const MENU_STRIKER := 2
const MENU_DEFENDER := 3
const MENU_HACKER := 4
const MENU_CONNECTION_MODULE := 5
const MENU_REPAIR_MODULE := 6

@onready var status_panel: PanelContainer = $Root/StatusPanel
@onready var command_panel: PanelContainer = $Root/CommandPanel
@onready var inspector_panel: PanelContainer = $Root/InspectorPanel
@onready var network_panel: PanelContainer = $Root/NetworkPanel
@onready var turn_label: Label = $Root/StatusPanel/StatusMargin/StatusVBox/TurnLabel
@onready var player_identity_label: Label = $Root/StatusPanel/StatusMargin/StatusVBox/PlayerIdentityLabel
@onready var core_hp_label: Label = $Root/StatusPanel/StatusMargin/StatusVBox/CoreHpLabel
@onready var action_limit_label: Label = $Root/StatusPanel/StatusMargin/StatusVBox/ActionLimitLabel
@onready var resource_label: Label = $Root/StatusPanel/StatusMargin/StatusVBox/ResourceLabel
@onready var preview_label: Label = $Root/StatusPanel/StatusMargin/StatusVBox/PreviewLabel
@onready var selected_label: Label = $Root/StatusPanel/StatusMargin/StatusVBox/SelectedLabel
@onready var command_title: Label = $Root/CommandPanel/CommandMargin/CommandVBox/CommandTitle
@onready var place_button: Button = $Root/CommandPanel/CommandMargin/CommandVBox/PlaceRow/PlaceButton
@onready var repair_button: Button = $Root/CommandPanel/CommandMargin/CommandVBox/RepairRow/RepairButton
@onready var upgrade_button: Button = $Root/CommandPanel/CommandMargin/CommandVBox/UpgradeRow/UpgradeButton
@onready var module_button: Button = $Root/CommandPanel/CommandMargin/CommandVBox/ModuleRow/ModuleButton
@onready var skip_button: Button = $Root/CommandPanel/CommandMargin/CommandVBox/SkipRow/SkipButton
@onready var network_toggle_button: Button = $Root/NetworkToggleButton
@onready var restart_button: Button = $Root/CommandPanel/CommandMargin/CommandVBox/UtilityRow/RestartButton
@onready var status_label: Label = $Root/CommandPanel/CommandMargin/CommandVBox/StatusLabel
@onready var setup_container: VBoxContainer = $Root/NetworkPanel/NetworkMargin/NetworkVBox/SetupContainer
@onready var room_code_edit: LineEdit = $Root/NetworkPanel/NetworkMargin/NetworkVBox/SetupContainer/JoinRow/RoomCodeEdit
@onready var join_room_button: Button = $Root/NetworkPanel/NetworkMargin/NetworkVBox/SetupContainer/JoinRow/JoinRoomButton
@onready var create_room_button: Button = $Root/NetworkPanel/NetworkMargin/NetworkVBox/SetupContainer/CreateRoomButton
@onready var lobby_container: VBoxContainer = $Root/NetworkPanel/NetworkMargin/NetworkVBox/LobbyContainer
@onready var lobby_code_label: Label = $Root/NetworkPanel/NetworkMargin/NetworkVBox/LobbyContainer/LobbyCodeRow/LobbyCodeLabel
@onready var copy_code_button: Button = $Root/NetworkPanel/NetworkMargin/NetworkVBox/LobbyContainer/LobbyCodeRow/CopyCodeButton
@onready var player_one_indicator: Label = $Root/NetworkPanel/NetworkMargin/NetworkVBox/LobbyContainer/LobbyCodeRow/PlayersRow/PlayerOneIndicator
@onready var player_two_indicator: Label = $Root/NetworkPanel/NetworkMargin/NetworkVBox/LobbyContainer/LobbyCodeRow/PlayersRow/PlayerTwoIndicator
@onready var reconnect_room_button: Button = $Root/NetworkPanel/NetworkMargin/NetworkVBox/LobbyContainer/ReconnectRoomButton
@onready var leave_room_button: Button = $Root/NetworkPanel/NetworkMargin/NetworkVBox/LobbyContainer/LeaveRoomButton
@onready var inspector_title: Label = $Root/InspectorPanel/InspectorMargin/InspectorVBox/InspectorTitle
@onready var inspector_cell_label: Label = $Root/InspectorPanel/InspectorMargin/InspectorVBox/InspectorCellLabel
@onready var inspector_owner_label: Label = $Root/InspectorPanel/InspectorMargin/InspectorVBox/InspectorOwnerLabel
@onready var inspector_state_label: Label = $Root/InspectorPanel/InspectorMargin/InspectorVBox/InspectorStateLabel
@onready var inspector_ready_label: Label = $Root/InspectorPanel/InspectorMargin/InspectorVBox/InspectorReadyLabel
@onready var inspector_actions_label: Label = $Root/InspectorPanel/InspectorMargin/InspectorVBox/InspectorActionsLabel
@onready var upgrade_popup: PopupMenu = $Root/UpgradePopup
@onready var key_labels: Array[Label] = [
	$Root/CommandPanel/CommandMargin/CommandVBox/PlaceRow/PlaceKeyLabel,
	$Root/CommandPanel/CommandMargin/CommandVBox/RepairRow/RepairKeyLabel,
	$Root/CommandPanel/CommandMargin/CommandVBox/UpgradeRow/UpgradeKeyLabel,
	$Root/CommandPanel/CommandMargin/CommandVBox/ModuleRow/ModuleKeyLabel,
	$Root/CommandPanel/CommandMargin/CommandVBox/SkipRow/SkipKeyLabel,
	$Root/CommandPanel/CommandMargin/CommandVBox/UtilityRow/RestartKeyLabel,
]

var upgrade_target_cell := BoardView.HOVER_NONE
var module_target_cell := BoardView.HOVER_NONE
var current_selected_action_type := GameAction.TYPE_PLACE_NODE
var current_network_state: Dictionary = {}


func _ready() -> void:
	_apply_theme()
	_apply_button_text()
	place_button.pressed.connect(_on_place_pressed)
	repair_button.pressed.connect(_on_repair_pressed)
	upgrade_button.pressed.connect(_on_upgrade_pressed)
	module_button.pressed.connect(_on_module_pressed)
	skip_button.pressed.connect(_on_skip_pressed)
	network_toggle_button.pressed.connect(_on_network_toggle_pressed)
	restart_button.pressed.connect(_on_restart_pressed)
	create_room_button.pressed.connect(_on_create_room_pressed)
	join_room_button.pressed.connect(_on_join_room_pressed)
	copy_code_button.pressed.connect(_on_copy_code_pressed)
	reconnect_room_button.pressed.connect(_on_reconnect_room_pressed)
	leave_room_button.pressed.connect(_on_leave_room_pressed)
	room_code_edit.text_changed.connect(_on_network_text_changed)
	room_code_edit.text_submitted.connect(_on_room_code_submitted)
	upgrade_popup.id_pressed.connect(_on_upgrade_menu_id_pressed)
	module_button.tooltip_text = "Build a connected module"
	network_panel.visible = false


func refresh(match_state: MatchState, selected_action_type: String, striker_attack_source: Vector2i = BoardView.HOVER_NONE, hacker_hack_source: Vector2i = BoardView.HOVER_NONE, hover_cell: Vector2i = BoardView.HOVER_NONE, network_state: Dictionary = {}) -> void:
	current_network_state = network_state.duplicate()
	current_selected_action_type = selected_action_type
	turn_label.text = "%s turn" % GameDefs.player_label(match_state.current_player)
	turn_label.add_theme_color_override("font_color", GameDefs.player_color(match_state.current_player))

	core_hp_label.text = "Core HP: P1 %d / P2 %d" % [
		match_state.core_hp[GameDefs.PLAYER_ONE],
		match_state.core_hp[GameDefs.PLAYER_TWO],
	]
	action_limit_label.text = "Action limits: Connection %d / Repair %d" % [
		match_state.connection_actions_left,
		match_state.repair_actions_left,
	]
	resource_label.text = "Resource: P1 %d / P2 %d" % [
		match_state.resources[GameDefs.PLAYER_ONE],
		match_state.resources[GameDefs.PLAYER_TWO],
	]
	preview_label.text = _format_next_turn_preview(match_state)
	selected_label.text = "Selected: %s" % _action_label(selected_action_type, striker_attack_source, hacker_hack_source)
	status_label.text = match_state.status_message
	_refresh_player_identity(match_state, network_state)

	place_button.button_pressed = selected_action_type == GameAction.TYPE_PLACE_NODE
	repair_button.button_pressed = selected_action_type == GameAction.TYPE_REPAIR_NODE
	upgrade_button.button_pressed = selected_action_type == ACTION_UPGRADE_NODE
	module_button.button_pressed = selected_action_type == ACTION_BUILD_MODULE
	_refresh_button_states(match_state, network_state)
	_refresh_inspector(match_state, hover_cell)
	_refresh_network_state(network_state)

	if match_state.finished:
		status_label.add_theme_color_override("font_color", Color(1.0, 0.78, 0.28))
	else:
		status_label.add_theme_color_override("font_color", Color(0.72, 0.76, 0.82))


func show_upgrade_menu(screen_position: Vector2, target_cell: Vector2i) -> void:
	upgrade_target_cell = target_cell
	upgrade_popup.clear()
	upgrade_popup.add_item("Harvester (free)" if MatchState.HARVESTER_UPGRADE_RESOURCE_COST == 0 else "Harvester (%dR)" % MatchState.HARVESTER_UPGRADE_RESOURCE_COST, MENU_HARVESTER)
	upgrade_popup.add_item("Striker (%dR)" % MatchState.STRIKER_UPGRADE_RESOURCE_COST, MENU_STRIKER)
	upgrade_popup.add_item("Defender (%dR)" % MatchState.DEFENDER_UPGRADE_RESOURCE_COST, MENU_DEFENDER)
	upgrade_popup.add_item("Hacker (%dR)" % MatchState.HACKER_UPGRADE_RESOURCE_COST, MENU_HACKER)
	upgrade_button.button_pressed = current_selected_action_type == ACTION_UPGRADE_NODE
	upgrade_popup.position = Vector2i(int(screen_position.x), int(screen_position.y))
	upgrade_popup.popup()


func show_module_menu(screen_position: Vector2, target_cell: Vector2i) -> void:
	module_target_cell = target_cell
	upgrade_popup.clear()
	upgrade_popup.add_item("Connection Module (%dR)" % MatchState.MODULE_BUILD_RESOURCE_COST, MENU_CONNECTION_MODULE)
	upgrade_popup.add_item("Repair Module (%dR)" % MatchState.MODULE_BUILD_RESOURCE_COST, MENU_REPAIR_MODULE)
	module_button.button_pressed = current_selected_action_type == ACTION_BUILD_MODULE
	upgrade_popup.position = Vector2i(int(screen_position.x), int(screen_position.y))
	upgrade_popup.popup()


func _refresh_button_states(match_state: MatchState, network_state: Dictionary) -> void:
	var gameplay_locked := _gameplay_locked(match_state, network_state)
	var lock_reason := _gameplay_lock_reason(match_state, network_state)
	place_button.disabled = gameplay_locked or not match_state.can_afford_action(match_state.current_player, GameAction.TYPE_PLACE_NODE)
	repair_button.disabled = gameplay_locked or not match_state.can_afford_action(match_state.current_player, GameAction.TYPE_REPAIR_NODE)
	upgrade_button.disabled = gameplay_locked or not _player_has_upgrade_option(match_state)
	module_button.disabled = gameplay_locked or not match_state.can_afford_action(match_state.current_player, GameAction.TYPE_BUILD_CONNECTION_MODULE)
	skip_button.disabled = gameplay_locked
	restart_button.disabled = str(network_state.get("mode", "local")) == "online"
	for button in [place_button, repair_button, upgrade_button, module_button, skip_button]:
		button.tooltip_text = lock_reason


func _refresh_network_state(network_state: Dictionary) -> void:
	var mode := str(network_state.get("mode", "local"))
	var room_code := str(network_state.get("room_code", ""))
	var assigned_player := str(network_state.get("assigned_player", ""))
	var players: Array = _players_from_network_state(network_state)
	var pending_room_request := str(network_state.get("pending_room_request", ""))
	var connected := bool(network_state.get("connected", false))
	var reconnect_available := bool(network_state.get("reconnect_available", false))
	var is_online := mode == "online"
	var in_room := is_online and not room_code.is_empty() and not assigned_player.is_empty()
	var is_busy := is_online and pending_room_request != ""

	if in_room and room_code_edit.text != room_code:
		room_code_edit.text = room_code

	setup_container.visible = not in_room
	lobby_container.visible = in_room
	create_room_button.disabled = is_busy or in_room
	join_room_button.disabled = is_busy or in_room or _normalized_room_code(room_code_edit.text).is_empty()
	lobby_code_label.text = "Room %s" % room_code
	copy_code_button.text = "Copy"
	_set_player_indicator(player_one_indicator, GameDefs.PLAYER_ONE in players, GameDefs.PLAYER_ONE, assigned_player == GameDefs.PLAYER_ONE)
	_set_player_indicator(player_two_indicator, GameDefs.PLAYER_TWO in players, GameDefs.PLAYER_TWO, assigned_player == GameDefs.PLAYER_TWO)
	reconnect_room_button.disabled = is_busy or connected
	reconnect_room_button.text = "Reconnect as %s" % GameDefs.player_label(assigned_player) if reconnect_available else "Connected as %s" % GameDefs.player_label(assigned_player)
	leave_room_button.text = "Leave room"


func _refresh_player_identity(match_state: MatchState, network_state: Dictionary) -> void:
	var mode := str(network_state.get("mode", "local"))
	if mode != "online":
		player_identity_label.visible = true
		player_identity_label.text = "Local sandbox"
		player_identity_label.add_theme_color_override("font_color", Color(0.72, 0.76, 0.82))
		return

	var assigned_player := str(network_state.get("assigned_player", ""))
	player_identity_label.visible = true
	if assigned_player.is_empty():
		player_identity_label.text = "Online connecting"
		player_identity_label.add_theme_color_override("font_color", Color(0.72, 0.76, 0.82))
		return

	var connected := bool(network_state.get("connected", false))
	var mode_text := "Online as %s" % GameDefs.player_label(assigned_player)
	if not connected:
		mode_text = "Offline as %s" % GameDefs.player_label(assigned_player)
	player_identity_label.text = mode_text
	player_identity_label.add_theme_color_override("font_color", GameDefs.player_color(assigned_player))


func _gameplay_locked(match_state: MatchState, network_state: Dictionary) -> bool:
	if match_state.finished:
		return true

	if str(network_state.get("mode", "local")) != "online":
		return false

	if not bool(network_state.get("connected", false)):
		return true

	var assigned_player := str(network_state.get("assigned_player", ""))
	if assigned_player.is_empty():
		return true

	if bool(network_state.get("pending_action", false)):
		return true

	return assigned_player != match_state.current_player


func _gameplay_lock_reason(match_state: MatchState, network_state: Dictionary) -> String:
	if match_state.finished:
		return "Match finished"

	if str(network_state.get("mode", "local")) != "online":
		return ""

	if not bool(network_state.get("connected", false)):
		return "Reconnect to continue"

	var assigned_player := str(network_state.get("assigned_player", ""))
	if assigned_player.is_empty():
		return "Waiting for room assignment"

	if bool(network_state.get("pending_action", false)):
		return "Waiting for server snapshot"

	if assigned_player != match_state.current_player:
		return "Waiting for %s" % GameDefs.player_label(match_state.current_player)

	return ""


func is_text_input_focused() -> bool:
	return room_code_edit.has_focus()


func release_text_input_focus() -> void:
	_release_network_focus()


func clear_room_code_input() -> void:
	room_code_edit.text = ""


func _refresh_inspector(match_state: MatchState, hover_cell: Vector2i) -> void:
	if hover_cell == BoardView.HOVER_NONE:
		inspector_cell_label.text = "Cell: none"
		inspector_owner_label.text = "Owner: -"
		inspector_state_label.text = "State: move over a hex"
		inspector_ready_label.text = "Ready: -"
		inspector_actions_label.text = "Actions: -"
		return

	inspector_cell_label.text = "Cell: (%d, %d)" % [hover_cell.x, hover_cell.y]

	if match_state.is_control_point(hover_cell):
		var control_owner := match_state.control_point_owner(hover_cell)
		inspector_owner_label.text = "Owner: %s" % _owner_label(control_owner)
		inspector_state_label.text = "Role: Resource site"
		inspector_ready_label.text = "Ready: passive"
		inspector_actions_label.text = "Actions: %s" % _possible_actions_text(match_state, hover_cell)
		return

	var object := match_state.get_object(hover_cell)

	if object.is_empty():
		inspector_owner_label.text = "Owner: -"
		inspector_state_label.text = "State: Empty"
		inspector_ready_label.text = "Ready: -"
		inspector_actions_label.text = "Actions: %s" % _possible_actions_text(match_state, hover_cell)
		return

	inspector_owner_label.text = "Owner: %s" % _owner_label(str(object.get("owner", "")))
	inspector_state_label.text = "State: %s, %s" % [
		_object_role_text(object),
		_object_state_text(object),
	]
	inspector_ready_label.text = "Ready: %s" % _object_ready_text(object)
	inspector_actions_label.text = "Actions: %s" % _possible_actions_text(match_state, hover_cell)


func _format_next_turn_preview(match_state: MatchState) -> String:
	var preview_player := GameDefs.other_player(match_state.current_player)
	var preview := match_state.upkeep_preview(preview_player)
	return "Next turn: %s +%dR, %d charge%s, +%d Conn, +%d Repair" % [
		GameDefs.player_label(preview_player),
		int(preview.get("resource_gain", 0)),
		int(preview.get("restored_charges", 0)),
		"" if int(preview.get("restored_charges", 0)) == 1 else "s",
		int(preview.get("connection_bonus", 0)),
		int(preview.get("repair_bonus", 0)),
	]


func _possible_actions_text(match_state: MatchState, cell: Vector2i) -> String:
	var actions: Array[String] = []

	if match_state.can_target_action(GameAction.TYPE_PLACE_NODE, cell):
		actions.append("Build connection")

	if match_state.can_target_action(GameAction.TYPE_REPAIR_NODE, cell):
		actions.append("Repair")

	if match_state.can_target_action(GameAction.TYPE_UPGRADE_HARVESTER, cell):
		actions.append("Upgrade Harvester")

	if match_state.can_target_action(GameAction.TYPE_UPGRADE_STRIKER, cell):
		actions.append("Upgrade Striker")

	if match_state.can_target_action(GameAction.TYPE_UPGRADE_DEFENDER, cell):
		actions.append("Upgrade Defender")

	if match_state.can_target_action(GameAction.TYPE_UPGRADE_HACKER, cell):
		actions.append("Upgrade Hacker")

	if match_state.can_target_action(GameAction.TYPE_BUILD_CONNECTION_MODULE, cell):
		actions.append("Build Connection Module")

	if match_state.can_target_action(GameAction.TYPE_BUILD_REPAIR_MODULE, cell):
		actions.append("Build Repair Module")

	if match_state.can_select_striker_source(cell):
		actions.append("Striker Attack")

	if match_state.can_select_hacker_source(cell):
		actions.append("Hacker Hack")

	if actions.is_empty():
		return "-"

	return ", ".join(actions)


func _player_has_upgrade_option(match_state: MatchState) -> bool:
	for key in match_state.objects.keys():
		var object: Dictionary = match_state.objects[key]

		if object.get("type") != MatchState.OBJECT_NODE:
			continue

		var cell: Vector2i = object.get("cell", BoardView.HOVER_NONE)

		if match_state.can_target_action(GameAction.TYPE_UPGRADE_HARVESTER, cell) or match_state.can_target_action(GameAction.TYPE_UPGRADE_STRIKER, cell) or match_state.can_target_action(GameAction.TYPE_UPGRADE_DEFENDER, cell) or match_state.can_target_action(GameAction.TYPE_UPGRADE_HACKER, cell):
			return true

	return false


func _object_role_text(object: Dictionary) -> String:
	if object.get("type") == MatchState.OBJECT_CORE:
		return "Core"

	if object.get("type") == MatchState.OBJECT_MODULE:
		return "%s Module" % str(object.get("module_kind", "")).capitalize()

	return str(object.get("role", MatchState.NODE_CONDUIT)).capitalize()


func _object_state_text(object: Dictionary) -> String:
	if object.get("disabled", false):
		return "disabled"

	if object.get("active", false):
		return "active"

	return "inactive"


func _object_ready_text(object: Dictionary) -> String:
	if object.get("type") == MatchState.OBJECT_CORE:
		return "always"

	if object.get("type") == MatchState.OBJECT_MODULE:
		if object.get("active", false) and object.get("ready", false):
			return "effect on"

		if object.get("active", false):
			return "pending"

		return "-"

	if object.get("role", MatchState.NODE_CONDUIT) == MatchState.NODE_CONDUIT:
		return "-"

	var ready_text := "yes" if object.get("ready", false) else "no"
	return "%s, charges %d" % [ready_text, int(object.get("action_charges", 0))]


func _owner_label(owner_id: String) -> String:
	if owner_id.is_empty():
		return "Neutral"

	return GameDefs.player_label(owner_id)


func _apply_theme() -> void:
	status_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.07, 0.082, 0.098, 0.82)))
	command_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.065, 0.078, 0.094, 0.94)))
	inspector_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.065, 0.078, 0.094, 0.88)))
	network_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.065, 0.078, 0.094, 0.88)))

	turn_label.add_theme_font_size_override("font_size", 20)
	player_identity_label.add_theme_font_size_override("font_size", 14)
	core_hp_label.add_theme_font_size_override("font_size", 15)
	action_limit_label.add_theme_font_size_override("font_size", 15)
	resource_label.add_theme_font_size_override("font_size", 15)
	preview_label.add_theme_font_size_override("font_size", 14)
	selected_label.add_theme_font_size_override("font_size", 14)
	command_title.add_theme_font_size_override("font_size", 13)
	status_label.add_theme_font_size_override("font_size", 14)
	inspector_title.add_theme_font_size_override("font_size", 13)

	for label in [
		player_identity_label,
		core_hp_label,
		action_limit_label,
		resource_label,
		inspector_cell_label,
		inspector_owner_label,
		inspector_state_label,
		inspector_ready_label,
		inspector_actions_label,
	]:
		label.add_theme_font_size_override("font_size", 13)
		label.add_theme_color_override("font_color", Color(0.84, 0.88, 0.92))

	preview_label.add_theme_color_override("font_color", Color(0.95, 0.78, 0.28))
	selected_label.add_theme_color_override("font_color", Color(0.55, 0.6, 0.68))
	command_title.add_theme_color_override("font_color", Color(0.55, 0.6, 0.68))
	inspector_title.add_theme_color_override("font_color", Color(0.55, 0.6, 0.68))

	_style_action_button(place_button, Color(0.22, 0.58, 1.0))
	_style_action_button(repair_button, Color(0.48, 0.78, 0.38))
	_style_action_button(upgrade_button, Color(0.95, 0.78, 0.28))
	_style_action_button(module_button, Color(0.72, 0.58, 0.96))
	_style_skip_button(skip_button)
	_style_utility_button(network_toggle_button)
	_style_utility_button(restart_button)
	_style_utility_button(create_room_button)
	_style_utility_button(join_room_button)
	_style_utility_button(copy_code_button)
	_style_utility_button(reconnect_room_button)
	_style_utility_button(leave_room_button)
	_style_line_edit(room_code_edit)
	lobby_code_label.add_theme_font_size_override("font_size", 16)
	lobby_code_label.add_theme_color_override("font_color", Color(0.92, 0.95, 0.98))
	network_toggle_button.text = "Online"

	for key_label in key_labels:
		key_label.add_theme_font_size_override("font_size", 12)
		key_label.add_theme_color_override("font_color", Color(0.72, 0.76, 0.82))
		key_label.add_theme_stylebox_override("normal", _key_style())


func _style_action_button(button: Button, accent: Color) -> void:
	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_stylebox_override("normal", _button_style(Color(0.1, 0.12, 0.145), Color(0.22, 0.25, 0.29)))
	button.add_theme_stylebox_override("hover", _button_style(Color(0.13, 0.155, 0.185), accent.darkened(0.1)))
	button.add_theme_stylebox_override("pressed", _button_style(accent.darkened(0.32), accent.lightened(0.12)))
	button.add_theme_stylebox_override("disabled", _button_style(Color(0.078, 0.088, 0.102), Color(0.15, 0.17, 0.2)))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", Color(0.92, 0.95, 0.98))
	button.add_theme_color_override("font_pressed_color", Color(1.0, 1.0, 1.0))
	button.add_theme_color_override("font_disabled_color", Color(0.42, 0.46, 0.52))


func _style_skip_button(button: Button) -> void:
	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_stylebox_override("normal", _button_style(Color(0.17, 0.19, 0.14), Color(0.42, 0.47, 0.28)))
	button.add_theme_stylebox_override("hover", _button_style(Color(0.22, 0.245, 0.17), Color(0.72, 0.78, 0.38)))
	button.add_theme_stylebox_override("pressed", _button_style(Color(0.33, 0.37, 0.2), Color(0.9, 0.95, 0.48)))
	button.add_theme_stylebox_override("disabled", _button_style(Color(0.09, 0.1, 0.085), Color(0.2, 0.22, 0.16)))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", Color(0.96, 0.98, 0.86))
	button.add_theme_color_override("font_disabled_color", Color(0.44, 0.46, 0.36))


func _style_utility_button(button: Button) -> void:
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_stylebox_override("normal", _button_style(Color(0.085, 0.095, 0.11), Color(0.2, 0.23, 0.27)))
	button.add_theme_stylebox_override("hover", _button_style(Color(0.12, 0.135, 0.155), Color(0.36, 0.4, 0.46)))
	button.add_theme_stylebox_override("pressed", _button_style(Color(0.16, 0.18, 0.205), Color(0.52, 0.58, 0.66)))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", Color(0.64, 0.7, 0.78))
	button.add_theme_color_override("font_disabled_color", Color(0.42, 0.46, 0.52))


func _style_line_edit(line_edit: LineEdit) -> void:
	line_edit.add_theme_font_size_override("font_size", 13)
	line_edit.add_theme_stylebox_override("normal", _line_edit_style(Color(0.055, 0.065, 0.078), Color(0.2, 0.23, 0.27)))
	line_edit.add_theme_stylebox_override("focus", _line_edit_style(Color(0.075, 0.09, 0.11), Color(0.36, 0.4, 0.46)))
	line_edit.add_theme_color_override("font_color", Color(0.86, 0.9, 0.94))
	line_edit.add_theme_color_override("font_placeholder_color", Color(0.42, 0.46, 0.52))


func _panel_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color(0.22, 0.25, 0.29, 0.95)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	return style


func _button_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	return style


func _line_edit_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := _button_style(fill, border)
	style.set_content_margin(SIDE_LEFT, 10.0)
	style.set_content_margin(SIDE_RIGHT, 10.0)
	style.set_content_margin(SIDE_TOP, 4.0)
	style.set_content_margin(SIDE_BOTTOM, 4.0)
	return style


func _key_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.14, 0.165, 0.92)
	style.border_color = Color(0.3, 0.34, 0.39)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	return style


func _apply_button_text() -> void:
	place_button.text = "Build connection"
	repair_button.text = "Repair"
	upgrade_button.text = "Upgrade node"
	module_button.text = "Build module"
	skip_button.text = "End turn"


func _on_place_pressed() -> void:
	action_selected.emit(GameAction.TYPE_PLACE_NODE)


func _on_repair_pressed() -> void:
	action_selected.emit(GameAction.TYPE_REPAIR_NODE)


func _on_upgrade_pressed() -> void:
	action_selected.emit(ACTION_UPGRADE_NODE)


func _on_module_pressed() -> void:
	action_selected.emit(ACTION_BUILD_MODULE)


func _on_upgrade_menu_id_pressed(id: int) -> void:
	match id:
		MENU_HARVESTER:
			upgrade_role_selected.emit(GameAction.TYPE_UPGRADE_HARVESTER, upgrade_target_cell)
		MENU_STRIKER:
			upgrade_role_selected.emit(GameAction.TYPE_UPGRADE_STRIKER, upgrade_target_cell)
		MENU_DEFENDER:
			upgrade_role_selected.emit(GameAction.TYPE_UPGRADE_DEFENDER, upgrade_target_cell)
		MENU_HACKER:
			upgrade_role_selected.emit(GameAction.TYPE_UPGRADE_HACKER, upgrade_target_cell)
		MENU_CONNECTION_MODULE:
			module_kind_selected.emit(GameAction.TYPE_BUILD_CONNECTION_MODULE, module_target_cell)
		MENU_REPAIR_MODULE:
			module_kind_selected.emit(GameAction.TYPE_BUILD_REPAIR_MODULE, module_target_cell)


func _on_skip_pressed() -> void:
	skip_requested.emit()


func _on_restart_pressed() -> void:
	restart_requested.emit()


func _on_network_toggle_pressed() -> void:
	network_panel.visible = not network_panel.visible
	if not network_panel.visible:
		_release_network_focus()


func _on_create_room_pressed() -> void:
	_release_network_focus()
	online_create_requested.emit()


func _on_join_room_pressed() -> void:
	online_join_requested.emit(_normalized_room_code(room_code_edit.text))
	_release_network_focus()


func _on_copy_code_pressed() -> void:
	var room_code := str(current_network_state.get("room_code", ""))
	if room_code.is_empty():
		return

	DisplayServer.clipboard_set(room_code)
	copy_code_button.text = "Copied"


func _on_reconnect_room_pressed() -> void:
	online_reconnect_requested.emit()
	_release_network_focus()


func _on_network_text_changed(text: String) -> void:
	var normalized := _normalized_room_code(text)
	if text != normalized:
		var caret := room_code_edit.caret_column
		room_code_edit.text = normalized
		room_code_edit.caret_column = mini(caret, normalized.length())

	_refresh_network_state(current_network_state)


func _on_room_code_submitted(_text: String) -> void:
	if not join_room_button.disabled:
		_on_join_room_pressed()


func _on_leave_room_pressed() -> void:
	_release_network_focus()
	online_leave_requested.emit()


func _release_network_focus() -> void:
	room_code_edit.release_focus()


func _normalized_room_code(text: String) -> String:
	return text.strip_edges().to_upper()


func _players_from_network_state(network_state: Dictionary) -> Array:
	var value: Variant = network_state.get("players", [])
	if value is Array:
		return value

	return []


func _set_player_indicator(label: Label, present: bool, player: String, is_self: bool) -> void:
	var color := GameDefs.player_color(player)
	label.text = _short_player_label(player)
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0) if present else Color(0.38, 0.42, 0.48))
	var fill := color.darkened(0.2) if present else Color(0.07, 0.08, 0.095)
	var border := Color(1.0, 1.0, 1.0) if is_self else color if present else Color(0.18, 0.2, 0.23)
	label.add_theme_stylebox_override("normal", _button_style(fill, border))
	label.tooltip_text = "%s%s" % [GameDefs.player_label(player), " (you)" if is_self else ""] if present else "%s disconnected" % GameDefs.player_label(player)


func _short_player_label(player: String) -> String:
	if player == GameDefs.PLAYER_ONE:
		return "P1"
	if player == GameDefs.PLAYER_TWO:
		return "P2"
	return "P?"


func _action_label(action_type: String, striker_attack_source: Vector2i = BoardView.HOVER_NONE, hacker_hack_source: Vector2i = BoardView.HOVER_NONE) -> String:
	match action_type:
		GameAction.TYPE_PLACE_NODE:
			return "Build connection"
		GameAction.TYPE_REPAIR_NODE:
			return "Repair"
		ACTION_UPGRADE_NODE:
			return "Upgrade node"
		ACTION_BUILD_MODULE:
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
			if striker_attack_source != BoardView.HOVER_NONE:
				return "Striker Attack (%d, %d)" % [striker_attack_source.x, striker_attack_source.y]

			return "Striker Attack"
		GameAction.TYPE_HACKER_HACK:
			if hacker_hack_source != BoardView.HOVER_NONE:
				return "Hacker Hack (%d, %d)" % [hacker_hack_source.x, hacker_hack_source.y]

			return "Hacker Hack"
		_:
			return action_type
