extends Control

@onready var _background: TextureRect = $Background
@onready var _status: Label = $Center/MenuColumn/Status
@onready var _host_field: LineEdit = $Center/MenuColumn/HostRow/HostField
@onready var _code_label: Label = $Center/MenuColumn/CodeLabel


func _ready() -> void:
	_load_background()
	_host_field.text = Network.server_host
	_code_label.text = "Room code: %s" % Network.ROOM_CODE
	_set_status("Start the Colyseus server, then create or join.")
	if not Network.status_changed.is_connected(_on_network_status):
		Network.status_changed.connect(_on_network_status)
	if not Network.room_failed.is_connected(_on_network_failed):
		Network.room_failed.connect(_on_network_failed)


func _load_background() -> void:
	var abs_path := ProjectSettings.globalize_path("res://assets/ui/main_menu_bg.png")
	var image := Image.load_from_file(abs_path)
	if image == null:
		push_error("Failed to load main menu background: %s" % abs_path)
		return

	_background.texture = ImageTexture.create_from_image(image)


func _apply_host() -> void:
	Network.set_server_host(_host_field.text)


func _set_status(text: String) -> void:
	_status.text = text


func _on_network_status(text: String) -> void:
	_set_status(text)


func _on_network_failed(message: String) -> void:
	_set_status(message)


func _on_single_player_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/map.tscn")


func _on_create_game_pressed() -> void:
	_apply_host()
	_code_label.text = "Share this code: %s" % Network.ROOM_CODE
	_set_status("Creating game...")
	Network.create_game()


func _on_join_game_pressed() -> void:
	_apply_host()
	_code_label.text = "Joining with code: %s" % Network.ROOM_CODE
	_set_status("Joining game...")
	Network.join_game(Network.ROOM_CODE)


func _on_admin_pressed() -> void:
	print("Admin — not implemented yet")
