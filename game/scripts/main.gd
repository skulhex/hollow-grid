extends Node2D

const BOARD_RADIUS := 3
const HEX_SIZE := 52.0

@onready var board_view: BoardView = $BoardView
@onready var hud: GameHud = $HUD

var grid: HexGrid
var match_state: MatchState


func _ready() -> void:
	grid = HexGrid.new(BOARD_RADIUS, HEX_SIZE)
	match_state = MatchState.new(BOARD_RADIUS)

	board_view.setup(grid, match_state)
	_refresh()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_update_hover(event.position)
	elif event is InputEventMouseButton and event.pressed:
		_handle_click(event)
	elif event.is_action_pressed("ui_accept"):
		match_state.skip_turn()
		_refresh()


func _handle_click(event: InputEventMouseButton) -> void:
	if match_state.finished:
		return

	var cell := board_view.screen_to_cell(event.position)

	if not grid.contains(cell):
		return

	if event.button_index == MOUSE_BUTTON_LEFT:
		match_state.place_node(cell)
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		match_state.break_node(cell)
	else:
		return

	_refresh()


func _update_hover(mouse_position: Vector2) -> void:
	var next_hover := board_view.screen_to_cell(mouse_position)

	if not grid.contains(next_hover):
		next_hover = BoardView.HOVER_NONE

	board_view.set_hover_cell(next_hover)


func _refresh() -> void:
	board_view.queue_redraw()
	hud.refresh(match_state)
