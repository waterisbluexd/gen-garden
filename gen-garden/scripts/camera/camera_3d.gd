extends Camera3D

@export var zoom_speed: float = 4.0
@export var zoom_smoothness: float = 10.0
@export var min_size: float = 2.0
@export var max_size: float = 20.0
@export var main_map: Node3D

var target_size: float

func _ready() -> void:
	target_size = size

func adjust_zoom(amount: float) -> void:
	target_size = clamp(target_size + amount, min_size, max_size)

func _process(delta: float) -> void:
	size = lerp(size, target_size, delta * zoom_smoothness)

func raycast_from_screen(screen_pos: Vector2) -> Dictionary:
	var from = project_ray_origin(screen_pos)
	var to   = from + project_ray_normal(screen_pos) * 1000.0
	var query = PhysicsRayQueryParameters3D.new()
	query.from = from
	query.to   = to
	query.collide_with_bodies = true
	query.collide_with_areas  = false
	query.collision_mask      = 0x7fffffff
	return get_world_3d().direct_space_state.intersect_ray(query)
