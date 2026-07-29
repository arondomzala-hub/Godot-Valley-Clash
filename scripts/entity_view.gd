extends Node2D
## Visual for one server-driven entity (knight or lane unit).
##
## Pure view: a sprite + a small health bar. Each frame it lerps toward the
## last position received from the server; no physics, no gameplay.

const KNIGHT_TEXTURES := {
	"blue": "res://assets/characters/player_B.png",
	"red": "res://assets/characters/player_A.png",
}

## NOTE: "Achilles .png" really contains a space before ".png" on disk.
const UNIT_TEXTURES := {
	"achilles": "res://assets/characters/Achilles .png",
	"executioner": "res://assets/characters/executioner.png",
	"ghost": "res://assets/characters/ghost.png",
	"ninja": "res://assets/characters/ninja.png",
	"peasant": "res://assets/characters/peasant.png",
	"pirate": "res://assets/characters/pirate.png",
	"priest": "res://assets/characters/priest.png",
	"shaman": "res://assets/characters/shaman.png",
	"viking": "res://assets/characters/viking.png",
	"zombie": "res://assets/characters/zombie.png",
}

const SPRITE_SCALE := 0.55
const LERP_FACTOR := 10.0
## Beyond this distance we snap instead of lerping (teleports, respawns).
const SNAP_DISTANCE := 400.0
const BAR_SIZE := Vector2(44.0, 6.0)
const BAR_GAP := 12.0

var _sprite: Sprite2D
var _target := Vector2.ZERO
var _hp := 1.0
var _max_hp := 1.0
var _alive := true
var _bar_offset_y := -52.0


func setup_unit(type: String, start: Vector2) -> void:
	var path: String = UNIT_TEXTURES.get(type, UNIT_TEXTURES["peasant"])
	_setup(path, start)


func setup_knight(team: String, start: Vector2) -> void:
	var path: String = KNIGHT_TEXTURES.get(team, KNIGHT_TEXTURES["blue"])
	_setup(path, start)


func _setup(texture_path: String, start: Vector2) -> void:
	global_position = start
	_target = start
	_sprite = Sprite2D.new()
	var texture: Texture2D = load(texture_path)
	_sprite.texture = texture
	_sprite.scale = Vector2(SPRITE_SCALE, SPRITE_SCALE)
	add_child(_sprite)
	if texture != null:
		_bar_offset_y = -(texture.get_height() * SPRITE_SCALE * 0.5) - BAR_GAP


## Push the latest authoritative values into this view.
func update_state(x: float, y: float, hp: float, max_hp: float, alive: bool = true) -> void:
	_target = Vector2(x, y)
	if hp != _hp or max_hp != _max_hp or alive != _alive:
		_hp = hp
		_max_hp = max_hp
		_alive = alive
		modulate = Color(1, 1, 1, 1) if _alive else Color(1, 1, 1, 0.25)
		queue_redraw()


func _process(delta: float) -> void:
	var to_target := _target - global_position
	if to_target.length() > SNAP_DISTANCE:
		global_position = _target
	else:
		global_position = global_position.lerp(_target, clampf(LERP_FACTOR * delta, 0.0, 1.0))
	if _sprite != null and absf(to_target.x) > 1.0:
		_sprite.flip_h = to_target.x < 0.0


func _draw() -> void:
	if not _alive:
		return
	var top_left := Vector2(-BAR_SIZE.x * 0.5, _bar_offset_y)
	draw_rect(Rect2(top_left, BAR_SIZE), Color(0.07, 0.07, 0.06, 0.9))
	var ratio := clampf(_hp / maxf(_max_hp, 1.0), 0.0, 1.0)
	var fill := Vector2(maxf((BAR_SIZE.x - 2.0) * ratio, 0.0), BAR_SIZE.y - 2.0)
	draw_rect(Rect2(top_left + Vector2(1.0, 1.0), fill), Color(0.30, 0.69, 0.31))
