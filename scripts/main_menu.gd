extends Control

@onready var _background: TextureRect = $Background
@onready var _status: Label = $Center/MenuColumn/Status
@onready var _host_field: LineEdit = $Center/MenuColumn/HostRow/HostField
@onready var _code_label: Label = $Center/MenuColumn/CodeLabel

var _quit_dialog: ConfirmationDialog


func _ready() -> void:
	_load_background()
	_create_quit_dialog()
	_host_field.text = Network.server_host
	_host_field.placeholder_text = "Cloud URL or LAN IP"
	_code_label.text = "Room code: %s" % Network.ROOM_CODE
	_set_status("Create or Join — code is always xxxx.")
	if not Network.status_changed.is_connected(_on_network_status):
		Network.status_changed.connect(_on_network_status)
	if not Network.room_failed.is_connected(_on_network_failed):
		Network.room_failed.connect(_on_network_failed)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_quit_dialog.popup_centered()
		get_viewport().set_input_as_handled()


func _create_quit_dialog() -> void:
	_quit_dialog = ConfirmationDialog.new()
	_quit_dialog.title = "Exit game"
	_quit_dialog.dialog_text = "Do you want to leave?"
	_quit_dialog.ok_button_text = "Yes"
	_quit_dialog.cancel_button_text = "No"
	_quit_dialog.exclusive = true
	_quit_dialog.confirmed.connect(func() -> void: get_tree().quit())
	add_child(_quit_dialog)


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
