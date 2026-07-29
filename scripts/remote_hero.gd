extends Node2D
## Knight controlled by another player. It never reads local input; it only
## replays movement received over the network (snap to position, walk to target).

@export var speed: float = 300.0
@export var stop_distance: float = 8.0

var _target: Vector2
var _has_target: bool = false


## Snap to the sender's current position and start walking to their target.
func set_movement(pos: Vector2, target: Vector2) -> void:
	global_position = pos
	_target = target
	_has_target = true


func _process(delta: float) -> void:
	if not _has_target:
		return

	var to_target := _target - global_position
	if to_target.length() <= stop_distance:
		global_position = _target
		_has_target = false
		return

	global_position += to_target.normalized() * minf(speed * delta, to_target.length())
