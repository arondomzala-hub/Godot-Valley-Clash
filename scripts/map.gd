extends Node2D
## Match view: renders the server-authoritative state (knights, lane units,
## castle HP), sends the knight move intent on left click, and shows the
## match result popup. All gameplay lives on the server.

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const EntityView := preload("res://scripts/entity_view.gd")
const CameraPan := preload("res://scripts/camera_pan.gd")

const CASTLE_POSITIONS := {
	"blue": Vector2(5, -1863),
	"red": Vector2(8, 1832),
}
const CASTLE_BAR_SIZE := Vector2(160.0, 12.0)
## Bar centers, placed just past each castle sprite so they never overlap it.
const CASTLE_BAR_POS := {
	"blue": Vector2(5, -2090),
	"red": Vector2(8, 1608),
}

const TEAM_IDS := ["blue", "red"]


## Safe field read from synced state. get_state() returns plain Dictionaries,
## but entity callbacks (unit_added) deliver Schema wrapper objects, and dot
## access on a Dictionary hard-fails (aborting the caller) when the key is
## missing, e.g. on a partial patch or a client/server schema mismatch.
## A single-argument get() works on both Dictionary and Object.
static func _field(data: Variant, key: String) -> Variant:
	return data.get(key) if data != null else null


static func _num(data: Variant, key: String, default: float = 0.0) -> float:
	var value: Variant = _field(data, key)
	return float(value) if value != null else default

@onready var _units: Node2D = $Units
@onready var _camera: CameraPan = $Camera2D

var _knight_views: Dictionary = {}  # team id -> EntityView
var _unit_views: Dictionary = {}  # unit id -> EntityView
var _leave_dialog: ConfirmationDialog
var _castle_bars: Node2D
var _result_layer: CanvasLayer


func _ready() -> void:
	_create_leave_dialog()
	_create_castle_bars()

	var my_castle: Vector2 = CASTLE_POSITIONS.get(Network.my_team(), CASTLE_POSITIONS["blue"])
	_camera.position.y = clampf(my_castle.y, _camera.min_y, _camera.max_y)

	Network.state_ready.connect(_on_state_ready)
	Network.state_updated.connect(_on_state_updated)
	Network.unit_added.connect(_on_unit_added)
	Network.unit_removed.connect(_on_unit_removed)
	if Network.has_state():
		_on_state_ready()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_leave_dialog.popup_centered()
		get_viewport().set_input_as_handled()
		return

	# Left click on the map (not consumed by any HUD Control) = move intent.
	if event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed:
		var state: Variant = Network.get_state()
		if state != null and str(state.get("phase")) == "playing":
			Network.send_move(get_global_mouse_position())
			get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------
# State → views
# ---------------------------------------------------------------------------

func _on_state_ready() -> void:
	var state: Variant = Network.get_state()
	# The native SDK decodes schema objects/maps into plain Dictionaries.
	var units: Variant = state.get("units") if state != null else null
	if units == null or state.get("knights") == null:
		return
	_sync_knights(state)
	# Sweep units already present before the on_add callback was wired.
	for id in units.keys():
		_on_unit_added(str(id), units.get(id))


func _on_state_updated() -> void:
	var state: Variant = Network.get_state()
	var units: Variant = state.get("units") if state != null else null
	if units == null or state.get("knights") == null:
		return

	_sync_knights(state)

	for id in _unit_views.keys():
		var unit: Variant = units.get(id)
		if unit == null:
			# Prune views the on_remove callback may have missed.
			_on_unit_removed(id)
		else:
			_unit_views[id].update_state(_num(unit, "x"), _num(unit, "y"),
					_num(unit, "hp"), _num(unit, "maxHp", 1.0))

	_castle_bars.queue_redraw()

	if str(state.get("phase")) == "finished" and _result_layer == null:
		_show_result(str(state.get("winner")))


func _sync_knights(state: Variant) -> void:
	var knights: Variant = state.get("knights")
	if knights == null:
		return
	for team in TEAM_IDS:
		var knight: Variant = knights.get(team)
		if knight == null:
			continue
		var view: Variant = _knight_views.get(team)
		if view == null:
			view = EntityView.new()
			view.setup_knight(team, Vector2(_num(knight, "x"), _num(knight, "y")))
			_units.add_child(view)
			_knight_views[team] = view
		var alive: Variant = _field(knight, "alive")
		view.update_state(_num(knight, "x"), _num(knight, "y"), _num(knight, "hp"),
				_num(knight, "maxHp", 1.0), bool(alive) if alive != null else true)


func _on_unit_added(id: String, unit: Variant) -> void:
	if unit == null or _unit_views.has(id):
		return
	var view := EntityView.new()
	view.setup_unit(str(_field(unit, "type")), Vector2(_num(unit, "x"), _num(unit, "y")))
	view.update_state(_num(unit, "x"), _num(unit, "y"), _num(unit, "hp"), _num(unit, "maxHp", 1.0))
	_units.add_child(view)
	_unit_views[id] = view


func _on_unit_removed(id: String) -> void:
	var view: Variant = _unit_views.get(id)
	if view != null:
		view.queue_free()
	_unit_views.erase(id)


# ---------------------------------------------------------------------------
# Castle HP bars
# ---------------------------------------------------------------------------

func _create_castle_bars() -> void:
	_castle_bars = Node2D.new()
	_castle_bars.z_index = 40
	add_child(_castle_bars)
	_castle_bars.draw.connect(_draw_castle_bars)


func _draw_castle_bars() -> void:
	var state: Variant = Network.get_state()
	var castles: Variant = state.get("castles") if state != null else null
	if castles == null:
		return
	for team in TEAM_IDS:
		var castle: Variant = castles.get(team)
		if castle == null:
			continue
		var top_left: Vector2 = CASTLE_BAR_POS[team] - CASTLE_BAR_SIZE * 0.5
		_castle_bars.draw_rect(Rect2(top_left, CASTLE_BAR_SIZE), Color(0.06, 0.06, 0.05, 0.9))
		var ratio := clampf(_num(castle, "hp") / maxf(_num(castle, "maxHp"), 1.0), 0.0, 1.0)
		var fill_color := Color(0.30, 0.69, 0.31) if team == Network.my_team() \
				else Color(0.78, 0.16, 0.16)
		var fill := Vector2(maxf((CASTLE_BAR_SIZE.x - 4.0) * ratio, 0.0), CASTLE_BAR_SIZE.y - 4.0)
		_castle_bars.draw_rect(Rect2(top_left + Vector2(2.0, 2.0), fill), fill_color)


# ---------------------------------------------------------------------------
# Match result / leave flow
# ---------------------------------------------------------------------------

func _show_result(winner: String) -> void:
	var victory := winner == Network.my_team()

	_result_layer = CanvasLayer.new()
	_result_layer.layer = 90
	add_child(_result_layer)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_result_layer.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_result_layer.add_child(center)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("1a1712")
	style.set_border_width_all(2)
	style.border_color = Color("8a7340")
	style.set_corner_radius_all(6)
	style.content_margin_left = 40.0
	style.content_margin_right = 40.0
	style.content_margin_top = 28.0
	style.content_margin_bottom = 28.0
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(box)

	var title := Label.new()
	title.text = "Victory!" if victory else "Defeat"
	title.add_theme_font_size_override("font_size", 52)
	title.add_theme_color_override("font_color",
			Color("e8c95a") if victory else Color("c44536"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var button := Button.new()
	button.text = "Back to Menu"
	button.custom_minimum_size = Vector2(220, 46)
	button.pressed.connect(_on_leave_confirmed)
	box.add_child(button)


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
