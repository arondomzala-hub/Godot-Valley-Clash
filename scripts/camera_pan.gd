extends Camera2D

@export var scroll_speed: float = 600.0
@export var edge_margin: float = 40.0
@export var min_y: float = -1600.0
@export var max_y: float = 1600.0


func _ready() -> void:
	position.x = 0.0
	make_current()


func _process(delta: float) -> void:
	var mouse_pos := get_viewport().get_mouse_position()
	var viewport_size := get_viewport_rect().size
	var scroll_dir := 0.0

	if mouse_pos.y <= edge_margin:
		scroll_dir = -1.0
	elif mouse_pos.y >= viewport_size.y - edge_margin:
		scroll_dir = 1.0

	if scroll_dir == 0.0:
		return

	position.y = clampf(
		position.y + scroll_dir * scroll_speed * delta,
		min_y,
		max_y
	)
	position.x = 0.0
