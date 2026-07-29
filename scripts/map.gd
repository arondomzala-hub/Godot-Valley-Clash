extends Node2D
## Map controller: multiplayer spawn points, remote knight rendering,
## and the ESC "leave game" confirmation dialog.

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const RemoteHero := preload("res://scripts/remote_hero.gd")
const REMOTE_HERO_TEXTURE := preload("res://assets/characters/player_A.png")

## Host spawns by the blue castle (top), guest by the red castle (bottom).
const HOST_SPAWN := Vector2(0, -1600)
const GUEST_SPAWN := Vector2(0, 1600)

@onready var _units: Node2D = $Units
@onready var _hero: CharacterBody2D = $Units/Hero
@onready var _camera: Camera2D = $Camera2D

var _remote_heroes: Dictionary = {}  # session_id -> RemoteHero node
var _leave_dialog: ConfirmationDialog


func _ready() -> void:
	_create_leave_dialog()

	if not Network.is_in_multiplayer():
		return

	var spawn: Vector2 = HOST_SPAWN if Network.is_host else GUEST_SPAWN
	_hero.global_position = spawn
	_camera.position.y = clampf(spawn.y, _camera.min_y, _camera.max_y)

	# Tell the other players where our knight starts.
	Network.send_move(spawn, spawn)

	# Spawn knights for players already in the room, then track live updates.
	for id in Network.remote_players:
		var info: Dictionary = Network.remote_players[id]
		_on_remote_player_moved(id, info["pos"], info["target"])
	Network.remote_player_moved.connect(_on_remote_player_moved)
	Network.remote_player_left.connect(_on_remote_player_left)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_leave_dialog.popup_centered()
		get_viewport().set_input_as_handled()


func _create_leave_dialog() -> void:
	_leave_dialog = ConfirmationDialog.new()
	_leave_dialog.title = "Leave game"
	_leave_dialog.dialog_text = "Do you want to leave?"
	_leave_dialog.ok_button_text = "Yes"
	_leave_dialog.cancel_button_text = "No"
	_leave_dialog.exclusive = true
	_leave_dialog.confirmed.connect(_on_leave_confirmed)
	add_child(_leave_dialog)


func _on_leave_confirmed() -> void:
	Network.leave_room()
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _on_remote_player_moved(id: String, pos: Vector2, target: Vector2) -> void:
	var hero: Node2D = _remote_heroes.get(id)
	if hero == null:
		hero = RemoteHero.new()
		var sprite := Sprite2D.new()
		sprite.texture = REMOTE_HERO_TEXTURE
		sprite.scale = Vector2(0.55, 0.55)
		hero.add_child(sprite)
		_units.add_child(hero)
		_remote_heroes[id] = hero
	hero.set_movement(pos, target)


func _on_remote_player_left(id: String) -> void:
	var hero: Node2D = _remote_heroes.get(id)
	if hero != null:
		hero.queue_free()
	_remote_heroes.erase(id)
