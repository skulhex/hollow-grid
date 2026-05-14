class_name GameHud
extends CanvasLayer

@onready var turn_label: Label = $Root/MarginContainer/VBoxContainer/TurnLabel
@onready var score_label: Label = $Root/MarginContainer/VBoxContainer/ScoreLabel
@onready var status_label: Label = $Root/MarginContainer/VBoxContainer/StatusLabel
@onready var help_label: Label = $Root/MarginContainer/VBoxContainer/HelpLabel


func _ready() -> void:
	turn_label.add_theme_font_size_override("font_size", 18)
	score_label.add_theme_font_size_override("font_size", 16)
	status_label.add_theme_font_size_override("font_size", 15)
	help_label.add_theme_font_size_override("font_size", 14)

	score_label.add_theme_color_override("font_color", Color(0.88, 0.9, 0.92))
	status_label.add_theme_color_override("font_color", Color(0.62, 0.66, 0.72))
	help_label.add_theme_color_override("font_color", Color(0.46, 0.5, 0.57))


func refresh(match_state: MatchState) -> void:
	turn_label.text = "Turn: %s" % GameDefs.player_label(match_state.current_player)
	turn_label.add_theme_color_override("font_color", GameDefs.player_color(match_state.current_player))

	score_label.text = "Score: P1 %d / P2 %d" % [
		match_state.scores[GameDefs.PLAYER_ONE],
		match_state.scores[GameDefs.PLAYER_TWO],
	]
	status_label.text = match_state.status_message
	help_label.text = "Left click: place node | Right click: break enemy node | Space: skip"
