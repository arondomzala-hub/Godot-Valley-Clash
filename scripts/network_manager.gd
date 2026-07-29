extends Node
## Colyseus networking for Valley Clash (autoload "Network").
##
## The server owns all gameplay state. This node mirrors the server schema,
## re-emits state signals for the match view / HUD, and sends gameplay
## intents ("move", "buy_item", "build_mine", "spawn_unit", "set_command").
## Clients never mutate game state locally.

const ROOM_NAME := "game"
const ROOM_CODE := "xxxx"
const DEFAULT_HOST := "127.0.0.1"
const DEFAULT_PORT := 2567
const CLOUD_ENDPOINT := "wss://pl-waw-ab59d502.colyseus.cloud"

signal room_joined(room: Variant)
signal room_failed(message: String)
signal status_changed(text: String)
## First full state arrived (safe to build entity views / HUD values).
signal state_ready()
## Emitted on every state patch from the server.
signal state_updated()
signal unit_added(id: String, unit: Variant)
signal unit_removed(id: String)

## Web builds can't load the Colyseus GDExtension; they use the JS SDK adapter
## (web_network.gd), which delivers every state patch as a full JSON snapshot
## via state_changed. This node stores that snapshot and re-emits the same
## signals the desktop path gets from the native SDK.
const WebNetwork := preload("res://scripts/web_network.gd")


# ---------------------------------------------------------------------------
# GDScript mirror of the server schema (field names must match EXACTLY).
# ---------------------------------------------------------------------------

class TeamState extends Colyseus.Schema:
	static func definition() -> Array:
		return [
			Colyseus.Schema.Field.new("sessionId", Colyseus.Schema.STRING),
			Colyseus.Schema.Field.new("gold", Colyseus.Schema.NUMBER),
			Colyseus.Schema.Field.new("mines", Colyseus.Schema.NUMBER),
			Colyseus.Schema.Field.new("income", Colyseus.Schema.NUMBER),
			Colyseus.Schema.Field.new("command", Colyseus.Schema.STRING),
			Colyseus.Schema.Field.new("nextMineCost", Colyseus.Schema.NUMBER),
		]


class KnightState extends Colyseus.Schema:
	static func definition() -> Array:
		return [
			Colyseus.Schema.Field.new("team", Colyseus.Schema.STRING),
			Colyseus.Schema.Field.new("x", Colyseus.Schema.NUMBER),
			Colyseus.Schema.Field.new("y", Colyseus.Schema.NUMBER),
			Colyseus.Schema.Field.new("hp", Colyseus.Schema.NUMBER),
			Colyseus.Schema.Field.new("maxHp", Colyseus.Schema.NUMBER),
			Colyseus.Schema.Field.new("damage", Colyseus.Schema.NUMBER),
			Colyseus.Schema.Field.new("attackSpeed", Colyseus.Schema.NUMBER),
			Colyseus.Schema.Field.new("moveSpeed", Colyseus.Schema.NUMBER),
			Colyseus.Schema.Field.new("armor", Colyseus.Schema.NUMBER),
			Colyseus.Schema.Field.new("regen", Colyseus.Schema.NUMBER),
			Colyseus.Schema.Field.new("items", Colyseus.Schema.ARRAY, Colyseus.Schema.STRING),
			Colyseus.Schema.Field.new("alive", Colyseus.Schema.BOOLEAN),
			Colyseus.Schema.Field.new("respawnIn", Colyseus.Schema.NUMBER),
		]


class UnitState extends Colyseus.Schema:
	static func definition() -> Array:
		return [
			Colyseus.Schema.Field.new("team", Colyseus.Schema.STRING),
			Colyseus.Schema.Field.new("type", Colyseus.Schema.STRING),
			Colyseus.Schema.Field.new("x", Colyseus.Schema.NUMBER),
			Colyseus.Schema.Field.new("y", Colyseus.Schema.NUMBER),
			Colyseus.Schema.Field.new("hp", Colyseus.Schema.NUMBER),
			Colyseus.Schema.Field.new("maxHp", Colyseus.Schema.NUMBER),
		]


class CastleState extends Colyseus.Schema:
	static func definition() -> Array:
		return [
			Colyseus.Schema.Field.new("team", Colyseus.Schema.STRING),
			Colyseus.Schema.Field.new("hp", Colyseus.Schema.NUMBER),
			Colyseus.Schema.Field.new("maxHp", Colyseus.Schema.NUMBER),
		]


class ConfigSnapshotState extends Colyseus.Schema:
	static func definition() -> Array:
		return [
			Colyseus.Schema.Field.new("itemPrices", Colyseus.Schema.MAP, Colyseus.Schema.NUMBER),
			Colyseus.Schema.Field.new("unitCosts", Colyseus.Schema.MAP, Colyseus.Schema.NUMBER),
			Colyseus.Schema.Field.new("maxItems", Colyseus.Schema.NUMBER),
			Colyseus.Schema.Field.new("incomePerMine", Colyseus.Schema.NUMBER),
			Colyseus.Schema.Field.new("unitKillReward", Colyseus.Schema.NUMBER),
			Colyseus.Schema.Field.new("knightKillReward", Colyseus.Schema.NUMBER),
		]


class MatchState extends Colyseus.Schema:
	static func definition() -> Array:
		return [
			Colyseus.Schema.Field.new("code", Colyseus.Schema.STRING),
			Colyseus.Schema.Field.new("phase", Colyseus.Schema.STRING),
			Colyseus.Schema.Field.new("winner", Colyseus.Schema.STRING),
			Colyseus.Schema.Field.new("teams", Colyseus.Schema.MAP, TeamState),
			Colyseus.Schema.Field.new("knights", Colyseus.Schema.MAP, KnightState),
			Colyseus.Schema.Field.new("castles", Colyseus.Schema.MAP, CastleState),
			Colyseus.Schema.Field.new("units", Colyseus.Schema.MAP, UnitState),
			Colyseus.Schema.Field.new("config", Colyseus.Schema.REF, ConfigSnapshotState),
		]


# ---------------------------------------------------------------------------
# Connection state
# ---------------------------------------------------------------------------

var client: Colyseus.Client
var room: Colyseus.Room
var web_room: RefCounted
var is_host: bool = false
## Raw value from the Server IP field (host, URL, or full ws/wss endpoint).
var server_host: String = CLOUD_ENDPOINT
var room_code: String = ROOM_CODE

var _callbacks  # Colyseus.Callbacks, wired once the first state arrives.
var _has_state: bool = false
## Web only: latest full state snapshot from the JS SDK adapter.
var _web_state: Dictionary = {}


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


# ---------------------------------------------------------------------------
# Matchmaking
# ---------------------------------------------------------------------------

func create_game() -> void:
	is_host = true
	room_code = ROOM_CODE
	_start_matchmaking(true, "pvp")


func join_game(code: String = ROOM_CODE) -> void:
	is_host = false
	room_code = code.strip_edges().to_lower()
	if room_code.is_empty():
		room_code = ROOM_CODE
	_start_matchmaking(false, "pvp")


## Solo match against the server-side bot. config_overrides is a flat
## dictionary of numeric dev settings (validated server-side, solo only).
func create_solo_game(config_overrides: Dictionary = {}) -> void:
	is_host = true
	room_code = ROOM_CODE
	_start_matchmaking(true, "solo", config_overrides)


func leave_room() -> void:
	if web_room != null:
		web_room.leave()
		web_room = null
	if room != null and room.connected:
		room.leave()
	room = null
	client = null
	_callbacks = null
	_has_state = false
	_web_state = {}


func is_in_multiplayer() -> bool:
	return room != null or web_room != null


# ---------------------------------------------------------------------------
# State access
# ---------------------------------------------------------------------------

## Root match state, or null before the first patch. Desktop returns the
## native SDK's decoded state; web returns the latest JSON snapshot. Both are
## plain Dictionaries with identical field names.
func get_state() -> Variant:
	if web_room != null:
		return _web_state if _has_state else null
	if room == null:
		return null
	return room.get_state()


func has_state() -> bool:
	return _has_state


## Our team id: room creator (host / solo) is "blue", the joiner is "red".
func my_team() -> String:
	return "blue" if is_host else "red"


func enemy_team() -> String:
	return "red" if is_host else "blue"


# ---------------------------------------------------------------------------
# Intents (the server validates everything; we only express wishes)
# ---------------------------------------------------------------------------

func send_move(pos: Vector2) -> void:
	_send("move", {"x": pos.x, "y": pos.y})


func send_buy_item(item: String) -> void:
	_send("buy_item", {"item": item})


func send_build_mine() -> void:
	_send("build_mine", {})


func send_spawn_unit(type: String) -> void:
	_send("spawn_unit", {"type": type})


func send_set_command(cmd: String) -> void:
	_send("set_command", {"command": cmd})


func _send(type: String, payload: Dictionary) -> void:
	if web_room != null:
		web_room.send_message(type, payload)
	elif room != null and room.connected:
		room.send_message(type, payload)


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

func _start_matchmaking(as_host: bool, mode: String, config_overrides: Dictionary = {}) -> void:
	leave_room()
	status_changed.emit("Connecting to %s ..." % get_endpoint())

	var options := {"code": room_code, "mode": mode}
	if mode == "solo":
		options["configOverrides"] = config_overrides

	if OS.has_feature("web"):
		web_room = WebNetwork.new()
		web_room.joined.connect(_on_room_joined)
		web_room.error.connect(_on_room_error)
		web_room.left.connect(_on_room_left)
		web_room.state_changed.connect(_on_web_state_changed)
		web_room.join_room(get_endpoint(), ROOM_NAME, options, as_host)
		return

	client = Colyseus.Client.new(get_endpoint())
	if as_host:
		room = client.create(ROOM_NAME, options)
	else:
		room = client.join(ROOM_NAME, options)

	if room == null:
		var msg := "Failed to start matchmaking."
		status_changed.emit(msg)
		room_failed.emit(msg)
		return

	room.set_state_type(MatchState)
	room.joined.connect(_on_room_joined)
	room.error.connect(_on_room_error)
	room.left.connect(_on_room_left)
	room.state_changed.connect(_on_state_changed)


func _on_state_changed() -> void:
	if not _has_state:
		var state: Variant = get_state()
		if state == null:
			return
		_has_state = true
		_wire_entity_callbacks(state)
		state_ready.emit()
	state_updated.emit()


## Web path: every server patch arrives as a full JSON snapshot. Store it,
## then emit the same signals the native SDK path produces — including
## unit_added/unit_removed derived by diffing unit ids between snapshots
## (map.gd only creates unit views from state_ready sweeps and unit_added).
func _on_web_state_changed(state: Dictionary) -> void:
	var old_units: Dictionary = {}
	if _has_state and _web_state.get("units") is Dictionary:
		old_units = _web_state["units"]
	var new_units: Dictionary = {}
	if state.get("units") is Dictionary:
		new_units = state["units"]

	var first := not _has_state
	_web_state = state
	_has_state = true

	if first:
		state_ready.emit()
	else:
		for id in new_units:
			if not old_units.has(id):
				unit_added.emit(str(id), new_units[id])
		for id in old_units:
			if not new_units.has(id):
				unit_removed.emit(str(id))
	state_updated.emit()


func _wire_entity_callbacks(state: Variant) -> void:
	_callbacks = Colyseus.Callbacks.of(room)
	if _callbacks == null:
		return
	_callbacks.on_add(state, "units", _on_unit_add)
	_callbacks.on_remove(state, "units", _on_unit_remove)


## The native callback argument order isn't documented; tolerate both
## (item, key) and (key, item). The key is always the String, the unit a Schema.
func _on_unit_add(a = null, b = null) -> void:
	if a is String or a is StringName:
		unit_added.emit(str(a), b)
	else:
		unit_added.emit(str(b), a)


func _on_unit_remove(a = null, b = null) -> void:
	if a is String or a is StringName:
		unit_removed.emit(str(a))
	else:
		unit_removed.emit(str(b))


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
	_callbacks = null
	_has_state = false
