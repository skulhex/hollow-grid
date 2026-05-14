class_name GameHud
extends CanvasLayer

signal action_selected(action_type: String)
signal skip_requested
signal restart_requested

@onready var status_panel: PanelContainer = $Root/StatusPanel
@onready var command_panel: PanelContainer = $Root/CommandPanel
@onready var turn_label: Label = $Root/StatusPanel/StatusMargin/StatusVBox/TurnLabel
@onready var score_label: Label = $Root/StatusPanel/StatusMargin/StatusVBox/ScoreLabel
@onready var selected_label: Label = $Root/StatusPanel/StatusMargin/StatusVBox/SelectedLabel
@onready var command_title: Label = $Root/CommandPanel/CommandMargin/CommandVBox/CommandTitle
@onready var place_button: Button = $Root/CommandPanel/CommandMargin/CommandVBox/PlaceRow/PlaceButton
@onready var break_button: Button = $Root/CommandPanel/CommandMargin/CommandVBox/BreakRow/BreakButton
@onready var skip_button: Button = $Root/CommandPanel/CommandMargin/CommandVBox/SkipRow/SkipButton
@onready var restart_button: Button = $Root/CommandPanel/CommandMargin/CommandVBox/UtilityRow/RestartButton
@onready var status_label: Label = $Root/CommandPanel/CommandMargin/CommandVBox/StatusLabel
@onready var key_labels: Array[Label] = [
	$Root/CommandPanel/CommandMargin/CommandVBox/PlaceRow/PlaceKeyLabel,
	$Root/CommandPanel/CommandMargin/CommandVBox/BreakRow/BreakKeyLabel,
	$Root/CommandPanel/CommandMargin/CommandVBox/SkipRow/SkipKeyLabel,
	$Root/CommandPanel/CommandMargin/CommandVBox/UtilityRow/RestartKeyLabel,
]


func _ready() -> void:
	_apply_theme()
	place_button.pressed.connect(_on_place_pressed)
	break_button.pressed.connect(_on_break_pressed)
	skip_button.pressed.connect(_on_skip_pressed)
	restart_button.pressed.connect(_on_restart_pressed)


func refresh(match_state: MatchState, selected_action_type: String) -> void:
	turn_label.text = GameDefs.player_label(match_state.current_player)
	turn_label.add_theme_color_override("font_color", GameDefs.player_color(match_state.current_player))

	score_label.text = "P1 %d  |  P2 %d" % [
		match_state.scores[GameDefs.PLAYER_ONE],
		match_state.scores[GameDefs.PLAYER_TWO],
	]
	selected_label.text = "Mode: %s" % _action_label(selected_action_type)
	status_label.text = match_state.status_message

	place_button.button_pressed = selected_action_type == GameAction.TYPE_PLACE_NODE
	break_button.button_pressed = selected_action_type == GameAction.TYPE_BREAK_NODE

	if match_state.finished:
		status_label.add_theme_color_override("font_color", Color(1.0, 0.78, 0.28))
	else:
		status_label.add_theme_color_override("font_color", Color(0.72, 0.76, 0.82))


func _apply_theme() -> void:
	status_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.07, 0.082, 0.098, 0.8)))
	command_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.065, 0.078, 0.094, 0.92)))

	turn_label.add_theme_font_size_override("font_size", 20)
	score_label.add_theme_font_size_override("font_size", 16)
	selected_label.add_theme_font_size_override("font_size", 14)
	command_title.add_theme_font_size_override("font_size", 13)
	status_label.add_theme_font_size_override("font_size", 15)

	score_label.add_theme_color_override("font_color", Color(0.88, 0.9, 0.92))
	selected_label.add_theme_color_override("font_color", Color(0.55, 0.6, 0.68))
	command_title.add_theme_color_override("font_color", Color(0.55, 0.6, 0.68))

	_style_action_button(place_button, Color(0.22, 0.58, 1.0))
	_style_action_button(break_button, Color(1.0, 0.62, 0.22))
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
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", Color(0.92, 0.95, 0.98))
	button.add_theme_color_override("font_pressed_color", Color(1.0, 1.0, 1.0))


func _style_skip_button(button: Button) -> void:
	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_stylebox_override("normal", _button_style(Color(0.17, 0.19, 0.14), Color(0.42, 0.47, 0.28)))
	button.add_theme_stylebox_override("hover", _button_style(Color(0.22, 0.245, 0.17), Color(0.72, 0.78, 0.38)))
	button.add_theme_stylebox_override("pressed", _button_style(Color(0.33, 0.37, 0.2), Color(0.9, 0.95, 0.48)))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", Color(0.96, 0.98, 0.86))


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


func _on_place_pressed() -> void:
	action_selected.emit(GameAction.TYPE_PLACE_NODE)


func _on_break_pressed() -> void:
	action_selected.emit(GameAction.TYPE_BREAK_NODE)


func _on_skip_pressed() -> void:
	skip_requested.emit()


func _on_restart_pressed() -> void:
	restart_requested.emit()


func _action_label(action_type: String) -> String:
	match action_type:
		GameAction.TYPE_PLACE_NODE:
			return "Place Node"
		GameAction.TYPE_BREAK_NODE:
			return "Break Node"
		_:
			return action_type
