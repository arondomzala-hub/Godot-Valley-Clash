extends CharacterBody2D

@export var speed: float = 300.0
@export var stop_distance: float = 8.0

var _target: Vector2
var _has_target: bool = false


func _ready() -> void:
	_target = global_position


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed:
		_target = get_global_mouse_position()
		_has_target = true
		# Let the other players see this move (no-op in single player).
		Network.send_move(global_position, _target)
		get_viewport().set_input_as_handled()


func _physics_process(_delta: float) -> void:
	if not _has_target:
		velocity = Vector2.ZERO
		return

	var to_target := _target - global_position
	if to_target.length() <= stop_distance:
		_has_target = false
		velocity = Vector2.ZERO
		return

	velocity = to_target.normalized() * speed
	move_and_slide()
