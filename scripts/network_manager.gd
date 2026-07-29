extends Node
## Colyseus multiplayer bootstrap for Valley Clash.
## Create Game hosts a room with code "xxxx"; Join Game joins that room over LAN.

const ROOM_NAME := "game"
const ROOM_CODE := "xxxx"
const DEFAULT_HOST := "127.0.0.1"
const DEFAULT_PORT := 2567

signal room_joined(room: Variant)
signal room_failed(message: String)
signal status_changed(text: String)

var client: Colyseus.Client
var room: Colyseus.Room
var is_host: bool = false
var server_host: String = DEFAULT_HOST
var room_code: String = ROOM_CODE


func set_server_host(host: String) -> void:
	server_host = host.strip_edges()
	if server_host.is_empty():
		server_host = DEFAULT_HOST


func get_endpoint() -> String:
	return "ws://%s:%d" % [server_host, DEFAULT_PORT]


func create_game() -> void:
	is_host = true
	room_code = ROOM_CODE
	_start_matchmaking(true)


func join_game(code: String = ROOM_CODE) -> void:
	is_host = false
	room_code = code.strip_edges().to_lower()
	if room_code.is_empty():
		room_code = ROOM_CODE
	_start_matchmaking(false)


func leave_room() -> void:
	if room != null and room.connected:
		room.leave()
	room = null
	client = null


func _start_matchmaking(as_host: bool) -> void:
	leave_room()
	status_changed.emit("Connecting to %s ..." % get_endpoint())

	client = Colyseus.Client.new(get_endpoint())
	var options := {"code": room_code}
	if as_host:
		room = client.create(ROOM_NAME, options)
	else:
		room = client.join(ROOM_NAME, options)

	if room == null:
		var msg := "Failed to start matchmaking."
		status_changed.emit(msg)
		room_failed.emit(msg)
		return

	room.joined.connect(_on_room_joined)
	room.error.connect(_on_room_error)
	room.left.connect(_on_room_left)


func _on_room_joined() -> void:
	var role := "host" if is_host else "guest"
	status_changed.emit("Joined as %s — code %s" % [role, room_code])
	room_joined.emit(room)
	get_tree().change_scene_to_file("res://scenes/map.tscn")


func _on_room_error(code: int, message: String) -> void:
	var msg := "Room error [%d]: %s" % [code, message]
	push_error(msg)
	status_changed.emit(msg)
	room_failed.emit(msg)


func _on_room_left(code: int, reason: String) -> void:
	status_changed.emit("Left room [%d]: %s" % [code, reason])
	room = null
