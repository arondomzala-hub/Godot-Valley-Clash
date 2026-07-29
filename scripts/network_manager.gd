extends Node
## Colyseus multiplayer bootstrap for Valley Clash.
## Create Game hosts a room with code "xxxx"; Join Game joins that room.

const ROOM_NAME := "game"
const ROOM_CODE := "xxxx"
const DEFAULT_HOST := "127.0.0.1"
const DEFAULT_PORT := 2567
const CLOUD_ENDPOINT := "wss://pl-waw-ab59d502.colyseus.cloud"

signal room_joined(room: Variant)
signal room_failed(message: String)
signal status_changed(text: String)
signal remote_player_moved(id: String, pos: Vector2, target: Vector2)
signal remote_player_left(id: String)

## Web builds can't load the Colyseus GDExtension; they use the JS SDK adapter.
const WebNetwork := preload("res://scripts/web_network.gd")

var client: Colyseus.Client
var room: Colyseus.Room
var web_room: RefCounted
var is_host: bool = false
## Raw value from the Server IP field (host, URL, or full ws/wss endpoint).
var server_host: String = CLOUD_ENDPOINT
var room_code: String = ROOM_CODE
## Last known state of every other player in the room:
## session_id -> {"pos": Vector2, "target": Vector2}
var remote_players: Dictionary = {}


func set_server_host(host: String) -> void:
	server_host = host.strip_edges()
	if server_host.is_empty():
		server_host = CLOUD_ENDPOINT


func get_endpoint() -> String:
	var value := server_host.strip_edges()
	if value.is_empty():
		value = CLOUD_ENDPOINT

	# Full endpoint pasted from Cloud / docs.
	if value.begins_with("wss://") or value.begins_with("ws://"):
		return value.trim_suffix("/")

	# https://… from the browser → secure WebSocket
	if value.begins_with("https://"):
		return "wss://" + value.substr(8).trim_suffix("/")
	if value.begins_with("http://"):
		return "ws://" + value.substr(7).trim_suffix("/")

	# Colyseus Cloud hostnames use wss on 443 (no :2567).
	if value.contains("colyseus.cloud"):
		return "wss://%s" % value.trim_suffix("/")

	# Local / LAN Node server on port 2567.
	return "ws://%s:%d" % [value, DEFAULT_PORT]


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
	if web_room != null:
		web_room.leave()
		web_room = null
	if room != null and room.connected:
		room.leave()
	room = null
	client = null
	remote_players.clear()


func is_in_multiplayer() -> bool:
	return room != null or web_room != null


## Broadcast our knight's movement (current position + click target) to the
## other players in the room. No-op in single player.
func send_move(pos: Vector2, target: Vector2) -> void:
	var payload := {"x": pos.x, "y": pos.y, "tx": target.x, "ty": target.y}
	if web_room != null:
		web_room.send_message("move", payload)
	elif room != null and room.connected:
		room.send_message("move", payload)


func _start_matchmaking(as_host: bool) -> void:
	leave_room()
	status_changed.emit("Connecting to %s ..." % get_endpoint())

	if OS.has_feature("web"):
		web_room = WebNetwork.new()
		web_room.joined.connect(_on_room_joined)
		web_room.error.connect(_on_room_error)
		web_room.left.connect(_on_room_left)
		web_room.message_received.connect(_handle_message)
		web_room.join_room(get_endpoint(), ROOM_NAME, {"code": room_code}, as_host)
		return

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
	room.message_received.connect(_handle_message)


## Handles messages relayed by the server (both native and web paths).
func _handle_message(type: Variant, data: Variant) -> void:
	match str(type):
		"move":
			if data is Dictionary:
				var id := str(data.get("id", ""))
				var pos := Vector2(data.get("x", 0.0), data.get("y", 0.0))
				var target := Vector2(data.get("tx", 0.0), data.get("ty", 0.0))
				remote_players[id] = {"pos": pos, "target": target}
				remote_player_moved.emit(id, pos, target)
		"roster":
			if data is Array:
				for entry in data:
					if entry is Dictionary:
						var id := str(entry.get("id", ""))
						var pos := Vector2(entry.get("x", 0.0), entry.get("y", 0.0))
						remote_players[id] = {"pos": pos, "target": pos}
						remote_player_moved.emit(id, pos, pos)
		"player_left":
			if data is Dictionary:
				var id := str(data.get("id", ""))
				remote_players.erase(id)
				remote_player_left.emit(id)


func _on_room_joined() -> void:
	var role := "host" if is_host else "guest"
	status_changed.emit("Joined as %s — code %s" % [role, room_code])
	room_joined.emit(room if room != null else web_room)
	get_tree().change_scene_to_file("res://scenes/map.tscn")


func _on_room_error(code: int, message: String) -> void:
	var msg := "Room error [%d]: %s" % [code, message]
	push_error(msg)
	status_changed.emit(msg)
	room_failed.emit(msg)


func _on_room_left(code: int, reason: String) -> void:
	status_changed.emit("Left room [%d]: %s" % [code, reason])
	room = null
	web_room = null
	remote_players.clear()
