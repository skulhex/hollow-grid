class_name GameDefs
extends RefCounted

const PLAYER_ONE := "player_1"
const PLAYER_TWO := "player_2"


static func player_color(player: String) -> Color:
	if player == PLAYER_ONE:
		return Color(0.22, 0.58, 1.0)

	return Color(1.0, 0.37, 0.28)


static func player_label(player: String) -> String:
	if player == PLAYER_ONE:
		return "Player 1"

	if player == PLAYER_TWO:
		return "Player 2"

	return player


static func other_player(player: String) -> String:
	if player == PLAYER_ONE:
		return PLAYER_TWO

	return PLAYER_ONE
