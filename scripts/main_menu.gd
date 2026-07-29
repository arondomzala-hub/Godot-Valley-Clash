extends Control
## Main menu: solo (server bot match), create/join pvp, and a dev admin
## panel that edits local config overrides for solo matches only.

const CONFIG_PATH := "user://game_config.cfg"
const CONFIG_SECTION := "overrides"

## Defaults mirror the server's GameConfig (display / editing only — the
## server always re-validates and multiplayer ignores overrides entirely).
const BASE_DEFAULTS := {
	"starting_gold": 100,
	"mine_base_cost": 100,
	"mine_income": 10,
	"unit_kill_reward": 15,
	"knight_kill_reward": 50,
	"castle_hp": 1000,
	"knight_respawn_seconds": 5,
	"knight_hp": 100,
	"knight_move_speed": 260,
	"knight_armor": 1,
	"item_price_sword": 50,
	"item_price_hammer": 80,
	"item_price_boots": 60,
	"item_price_armor": 70,
	"max_items": 4,
}

## Per unit type: [cost, hp, damage, speed].
const UNIT_DEFAULTS := {
	"peasant": [20, 50, 5, 220],
	"zombie": [30, 90, 6, 140],
	"ghost": [40, 60, 10, 260],
	"ninja": [50, 70, 14, 280],
	"pirate": [60, 100, 12, 220],
	"shaman": [70, 80, 10, 210],
	"priest": [70, 70, 8, 210],
	"viking": [80, 140, 14, 200],
	"executioner": [90, 120, 20, 190],
	"achilles": [120, 180, 22, 240],
}

@onready var _background: TextureRect = $Background
@onready var _status: Label = $Center/MenuColumn/Status
@onready var _host_field: LineEdit = $Center/MenuColumn/HostRow/HostField
@onready var _code_label: Label = $Center/MenuColumn/CodeLabel

var _quit_dialog: ConfirmationDialog
var _config: Dictionary = {}
var _admin_panel: Control
var _spin_boxes: Dictionary = {}  # config key -> SpinBox


static func default_config() -> Dictionary:
	var out := {}
	out.merge(BASE_DEFAULTS)
	for unit_type in UNIT_DEFAULTS:
		var stats: Array = UNIT_DEFAULTS[unit_type]
		out["unit_%s_cost" % unit_type] = stats[0]
		out["unit_%s_hp" % unit_type] = stats[1]
		out["unit_%s_damage" % unit_type] = stats[2]
		out["unit_%s_speed" % unit_type] = stats[3]
	return out


func _ready() -> void:
	_load_background()
	_create_quit_dialog()
	_load_config()
	_host_field.text = Network.server_host
	_host_field.placeholder_text = "Cloud URL or LAN IP"
	_code_label.text = "Room code: %s" % Network.ROOM_CODE
	_set_status("All modes need the server. Single player: run `npm start` in server/ and use host 127.0.0.1.")
	if not Network.status_changed.is_connected(_on_network_status):
		Network.status_changed.connect(_on_network_status)
	if not Network.room_failed.is_connected(_on_network_failed):
		Network.room_failed.connect(_on_network_failed)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _admin_panel != null and _admin_panel.visible:
			_admin_panel.visible = false
		else:
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
	# The file has a .png extension but actually contains JPEG data, so it
	# can't be imported normally; detect the real format and load manually.
	const BG_PATH := "res://assets/ui/main_menu_bg.png"
	var bytes := FileAccess.get_file_as_bytes(BG_PATH)
	if bytes.is_empty():
		push_error("Failed to read main menu background: %s" % BG_PATH)
		return

	var image := Image.new()
	var err: int
	if bytes.size() > 4 and bytes[0] == 0x89 and bytes[1] == 0x50:  # real PNG
		err = image.load_png_from_buffer(bytes)
	else:  # JPEG (FF D8 ...)
		err = image.load_jpg_from_buffer(bytes)
	if err != OK:
		push_error("Failed to decode main menu background (error %d)" % err)
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


# ---------------------------------------------------------------------------
# Buttons
# ---------------------------------------------------------------------------

func _on_single_player_pressed() -> void:
	_apply_host()
	_set_status("Starting solo match... (needs a running server — e.g. 127.0.0.1 with `npm start`)")
	Network.create_solo_game(_config_overrides())


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
	if _admin_panel == null:
		_admin_panel = _build_admin_panel()
	for key in _spin_boxes:
		_spin_boxes[key].value = float(_config[key])
	_admin_panel.visible = true


# ---------------------------------------------------------------------------
# Dev config (solo matches only; multiplayer uses server defaults)
# ---------------------------------------------------------------------------

func _load_config() -> void:
	_config = default_config()
	var file := ConfigFile.new()
	if file.load(CONFIG_PATH) != OK:
		return
	for key in _config:
		if file.has_section_key(CONFIG_SECTION, key):
			_config[key] = float(file.get_value(CONFIG_SECTION, key, _config[key]))


func _save_config() -> void:
	var file := ConfigFile.new()
	for key in _config:
		file.set_value(CONFIG_SECTION, key, _config[key])
	var err := file.save(CONFIG_PATH)
	if err != OK:
		push_error("Failed to save %s (error %d)" % [CONFIG_PATH, err])


## Only the values that differ from defaults are sent as configOverrides.
func _config_overrides() -> Dictionary:
	var defaults := default_config()
	var out := {}
	for key in _config:
		if not is_equal_approx(float(_config[key]), float(defaults[key])):
			out[key] = float(_config[key])
	return out


func _build_admin_panel() -> Control:
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false
	add_child(overlay)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("1a1712")
	style.set_border_width_all(2)
	style.border_color = Color("8a7340")
	style.set_corner_radius_all(6)
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 14.0
	style.content_margin_bottom = 14.0
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	var title := Label.new()
	title.text = "Admin — Game Config"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color("e8c95a"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var note := Label.new()
	note.text = "Applies to solo matches only. Multiplayer always uses server defaults."
	note.add_theme_font_size_override("font_size", 11)
	note.add_theme_color_override("font_color", Color("9a917d"))
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(note)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(460, 380)
	box.add_child(scroll)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 4)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)

	for key in _config:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		rows.add_child(row)

		var name_label := Label.new()
		name_label.text = str(key)
		name_label.add_theme_font_size_override("font_size", 12)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)

		var spin := SpinBox.new()
		spin.min_value = 0
		spin.max_value = 999999
		spin.step = 1
		spin.allow_greater = true
		spin.custom_minimum_size = Vector2(120, 0)
		spin.value = float(_config[key])
		row.add_child(spin)
		_spin_boxes[key] = spin

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(buttons)

	var save := Button.new()
	save.text = "Save"
	save.custom_minimum_size = Vector2(120, 38)
	save.pressed.connect(_on_admin_save)
	buttons.add_child(save)

	var reset := Button.new()
	reset.text = "Reset"
	reset.custom_minimum_size = Vector2(120, 38)
	reset.pressed.connect(_on_admin_reset)
	buttons.add_child(reset)

	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(120, 38)
	close.pressed.connect(func() -> void: overlay.visible = false)
	buttons.add_child(close)

	return overlay


func _on_admin_save() -> void:
	for key in _spin_boxes:
		_config[key] = float(_spin_boxes[key].value)
	_save_config()
	_set_status("Config saved. Overrides apply to the next solo match.")


func _on_admin_reset() -> void:
	_config = default_config()
	for key in _spin_boxes:
		_spin_boxes[key].value = float(_config[key])
	_save_config()
	_set_status("Config reset to defaults.")
