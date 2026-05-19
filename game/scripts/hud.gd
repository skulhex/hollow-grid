class_name GameHud
extends CanvasLayer

signal action_selected(action_type: String)
signal upgrade_role_selected(action_type: String, target_cell: Vector2i)
signal skip_requested
signal restart_requested

const ACTION_UPGRADE_NODE := "upgrade_node"
const MENU_HARVESTER := 1
const MENU_STRIKER := 2

@onready var status_panel: PanelContainer = $Root/StatusPanel
@onready var command_panel: PanelContainer = $Root/CommandPanel
@onready var inspector_panel: PanelContainer = $Root/InspectorPanel
@onready var turn_label: Label = $Root/StatusPanel/StatusMargin/StatusVBox/TurnLabel
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
@onready var restart_button: Button = $Root/CommandPanel/CommandMargin/CommandVBox/UtilityRow/RestartButton
@onready var status_label: Label = $Root/CommandPanel/CommandMargin/CommandVBox/StatusLabel
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
var current_selected_action_type := GameAction.TYPE_PLACE_NODE


func _ready() -> void:
	_apply_theme()
	_apply_button_text()
	place_button.pressed.connect(_on_place_pressed)
	repair_button.pressed.connect(_on_repair_pressed)
	upgrade_button.pressed.connect(_on_upgrade_pressed)
	skip_button.pressed.connect(_on_skip_pressed)
	restart_button.pressed.connect(_on_restart_pressed)
	upgrade_popup.id_pressed.connect(_on_upgrade_menu_id_pressed)
	module_button.disabled = true
	module_button.tooltip_text = "Modules are not available in MVP"


func refresh(match_state: MatchState, selected_action_type: String, striker_attack_source: Vector2i = BoardView.HOVER_NONE, hover_cell: Vector2i = BoardView.HOVER_NONE) -> void:
	current_selected_action_type = selected_action_type
	turn_label.text = GameDefs.player_label(match_state.current_player)
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
	selected_label.text = "Selected: %s" % _action_label(selected_action_type, striker_attack_source)
	status_label.text = match_state.status_message

	place_button.button_pressed = selected_action_type == GameAction.TYPE_PLACE_NODE
	repair_button.button_pressed = selected_action_type == GameAction.TYPE_REPAIR_NODE
	upgrade_button.button_pressed = selected_action_type == ACTION_UPGRADE_NODE
	_refresh_button_states(match_state)
	_refresh_inspector(match_state, hover_cell)

	if match_state.finished:
		status_label.add_theme_color_override("font_color", Color(1.0, 0.78, 0.28))
	else:
		status_label.add_theme_color_override("font_color", Color(0.72, 0.76, 0.82))


func show_upgrade_menu(screen_position: Vector2, target_cell: Vector2i) -> void:
	upgrade_target_cell = target_cell
	upgrade_popup.clear()
	upgrade_popup.add_item("Harvester (%dR)" % MatchState.HARVESTER_UPGRADE_RESOURCE_COST, MENU_HARVESTER)
	upgrade_popup.add_item("Striker (%dR)" % MatchState.STRIKER_UPGRADE_RESOURCE_COST, MENU_STRIKER)
	upgrade_button.button_pressed = current_selected_action_type == ACTION_UPGRADE_NODE
	upgrade_popup.position = Vector2i(int(screen_position.x), int(screen_position.y))
	upgrade_popup.popup()


func _refresh_button_states(match_state: MatchState) -> void:
	place_button.disabled = match_state.finished or not match_state.can_afford_action(match_state.current_player, GameAction.TYPE_PLACE_NODE)
	repair_button.disabled = match_state.finished or not match_state.can_afford_action(match_state.current_player, GameAction.TYPE_REPAIR_NODE)
	upgrade_button.disabled = match_state.finished or not _player_has_upgrade_option(match_state)
	skip_button.disabled = match_state.finished


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
		inspector_state_label.text = "Role: Control point"
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
	return "Next turn: %s +%dR, %d charge%s restored" % [
		GameDefs.player_label(preview_player),
		int(preview.get("resource_gain", 0)),
		int(preview.get("restored_charges", 0)),
		"" if int(preview.get("restored_charges", 0)) == 1 else "s",
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

	if match_state.can_select_striker_source(cell):
		actions.append("Striker Attack")

	if actions.is_empty():
		return "-"

	return ", ".join(actions)


func _player_has_upgrade_option(match_state: MatchState) -> bool:
	for key in match_state.objects.keys():
		var object: Dictionary = match_state.objects[key]

		if object.get("type") != MatchState.OBJECT_NODE:
			continue

		var cell: Vector2i = object.get("cell", BoardView.HOVER_NONE)

		if match_state.can_target_action(GameAction.TYPE_UPGRADE_HARVESTER, cell) or match_state.can_target_action(GameAction.TYPE_UPGRADE_STRIKER, cell):
			return true

	return false


func _object_role_text(object: Dictionary) -> String:
	if object.get("type") == MatchState.OBJECT_CORE:
		return "Core"

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

	turn_label.add_theme_font_size_override("font_size", 20)
	core_hp_label.add_theme_font_size_override("font_size", 15)
	action_limit_label.add_theme_font_size_override("font_size", 15)
	resource_label.add_theme_font_size_override("font_size", 15)
	preview_label.add_theme_font_size_override("font_size", 14)
	selected_label.add_theme_font_size_override("font_size", 14)
	command_title.add_theme_font_size_override("font_size", 13)
	status_label.add_theme_font_size_override("font_size", 14)
	inspector_title.add_theme_font_size_override("font_size", 13)

	for label in [
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
	_style_action_button(module_button, Color(0.42, 0.48, 0.58))
	_style_skip_button(skip_button)
	_style_utility_button(restart_button)

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


func _on_upgrade_menu_id_pressed(id: int) -> void:
	match id:
		MENU_HARVESTER:
			upgrade_role_selected.emit(GameAction.TYPE_UPGRADE_HARVESTER, upgrade_target_cell)
		MENU_STRIKER:
			upgrade_role_selected.emit(GameAction.TYPE_UPGRADE_STRIKER, upgrade_target_cell)


func _on_skip_pressed() -> void:
	skip_requested.emit()


func _on_restart_pressed() -> void:
	restart_requested.emit()


func _action_label(action_type: String, striker_attack_source: Vector2i = BoardView.HOVER_NONE) -> String:
	match action_type:
		GameAction.TYPE_PLACE_NODE:
			return "Build connection"
		GameAction.TYPE_REPAIR_NODE:
			return "Repair"
		ACTION_UPGRADE_NODE:
			return "Upgrade node"
		GameAction.TYPE_UPGRADE_HARVESTER:
			return "Upgrade node: Harvester"
		GameAction.TYPE_UPGRADE_STRIKER:
			return "Upgrade node: Striker"
		GameAction.TYPE_STRIKER_ATTACK:
			if striker_attack_source != BoardView.HOVER_NONE:
				return "Striker Attack (%d, %d)" % [striker_attack_source.x, striker_attack_source.y]

			return "Striker Attack"
		_:
			return action_type
