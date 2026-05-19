class_name NetworkClient
extends RefCounted

signal connected
signal disconnected
signal room_created(room_code: String, player: String, snapshot: Dictionary)
signal joined(room_code: String, player: String, snapshot: Dictionary)
signal player_joined(players: Array, snapshot: Dictionary)
signal snapshot_received(snapshot: Dictionary)
signal error_received(message: String)
signal connection_status_changed(status_text: String)

const STATUS_DISCONNECTED := "Disconnected"
const STATUS_CONNECTING := "Connecting"
const STATUS_CONNECTED := "Connected"

var socket := WebSocketPeer.new()
var server_url := ""
var status_text := STATUS_DISCONNECTED
var was_connected := false


func connect_to_server(url: String) -> int:
	server_url = url.strip_edges()
	if server_url.is_empty():
		_set_status("Server URL is required")
		return ERR_INVALID_PARAMETER

	disconnect_from_server()
	socket = WebSocketPeer.new()
	var error := socket.connect_to_url(server_url)
	if error != OK:
		_set_status("Connect failed: %s" % error_string(error))
		return error

	was_connected = false
	_set_status(STATUS_CONNECTING)
	return OK


func create_room() -> int:
	return _send_message({
		"type": "create_room",
	})


func join_room(room_code: String) -> int:
	return _send_message({
		"type": "join_room",
		"room_code": room_code.strip_edges().to_upper(),
	})


func send_action(action_payload: Dictionary) -> int:
	return _send_message({
		"type": "action",
		"action": action_payload,
	})


func disconnect_from_server() -> void:
	if socket.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		socket.close()

	if was_connected:
		disconnected.emit()

	was_connected = false
	_set_status(STATUS_DISCONNECTED)


func poll() -> void:
	socket.poll()
	var state := socket.get_ready_state()

	if state == WebSocketPeer.STATE_OPEN:
		if not was_connected:
			was_connected = true
			_set_status(STATUS_CONNECTED)
			connected.emit()

		while socket.get_available_packet_count() > 0:
			_handle_packet(socket.get_packet().get_string_from_utf8())
	elif state == WebSocketPeer.STATE_CLOSED:
		if was_connected:
			was_connected = false
			disconnected.emit()

		if status_text != STATUS_DISCONNECTED:
			_set_status(STATUS_DISCONNECTED)


func is_socket_connected() -> bool:
	return socket.get_ready_state() == WebSocketPeer.STATE_OPEN


func _send_message(message: Dictionary) -> int:
	if not is_socket_connected():
		_set_status("Socket is not connected")
		return ERR_UNCONFIGURED

	var text := JSON.stringify(message)
	var error := socket.send_text(text)
	if error != OK:
		_set_status("Send failed: %s" % error_string(error))

	return error


func _handle_packet(text: String) -> void:
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		error_received.emit("Invalid server message")
		return

	var message: Dictionary = parsed
	match str(message.get("type", "")):
		"room_created":
			room_created.emit(
				str(message.get("room_code", "")),
				str(message.get("player", "")),
				_dictionary_value(message, "snapshot")
			)
		"joined":
			joined.emit(
				str(message.get("room_code", "")),
				str(message.get("player", "")),
				_dictionary_value(message, "snapshot")
			)
		"player_joined":
			player_joined.emit(
				_array_value(message, "players"),
				_dictionary_value(message, "snapshot")
			)
		"snapshot":
			snapshot_received.emit(_dictionary_value(message, "snapshot"))
		"error":
			error_received.emit(str(message.get("message", "Server error")))
		_:
			error_received.emit("Unknown server message: %s" % str(message.get("type", "")))


func _dictionary_value(message: Dictionary, key: String) -> Dictionary:
	var value: Variant = message.get(key, {})
	if value is Dictionary:
		return value

	return {}


func _array_value(message: Dictionary, key: String) -> Array:
	var value: Variant = message.get(key, [])
	if value is Array:
		return value

	return []


func _set_status(next_status: String) -> void:
	if next_status == status_text:
		return

	status_text = next_status
	connection_status_changed.emit(status_text)
