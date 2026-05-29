extends Node3D

var target_angle := 0.0
var current_angle := 0.0
var rotation_speed := 8.0

@export var pan_speed: float = 0.01
@export var pan_smoothness: float = 12.0
@export var touch_pan_enabled: bool = true
@export var touch_rotate_enabled: bool = true
@export var touch_rotate_speed: float = 0.3

@export var gridmapinuse: Node3D
var grid_node: Node3D
var is_panning: bool = false
var target_position: Vector3
var touch_positions: Dictionary = {}
var prev_pinch_distance: float = 0.0

func _ready():
	current_angle = rad_to_deg(rotation.y)
	target_angle = current_angle
	target_position = global_position
	_locate_cords()

func _process(delta):
	current_angle = lerp(current_angle, target_angle, rotation_speed * delta)
	rotation.y = deg_to_rad(current_angle)
	global_position = global_position.lerp(target_position, clamp(delta * pan_smoothness, 0.0, 1.0))

func snap_to_cell(cell_coord: Vector3i) -> void:
	# Retain target_position.y so the camera doesn't plunge through the floor
	target_position = Vector3(float(cell_coord.x) + 0.5, target_position.y, float(cell_coord.z) + 0.5)

func apply_pan(relative: Vector2) -> void:
	var right = transform.basis.x
	var forward = transform.basis.z
	var camera_size = $Camera3D.size
	target_position -= right * relative.x * pan_speed * camera_size
	target_position -= forward * relative.y * pan_speed * camera_size

func _input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_E:
			target_angle -= 45.0
		elif event.keycode == KEY_Q:
			target_angle += 45.0

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			is_panning = event.pressed
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_raycast_to_grid()

	if event is InputEventMouseMotion and is_panning:
		apply_pan(event.relative)

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			$Camera3D.adjust_zoom(-$Camera3D.zoom_speed)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			$Camera3D.adjust_zoom($Camera3D.zoom_speed)

	if event is InputEventScreenTouch:
		if event.pressed:
			touch_positions[event.index] = event.position
		else:
			touch_positions.erase(event.index)
		if touch_positions.size() == 2:
			var pts = touch_positions.values()
			prev_pinch_distance = pts[0].distance_to(pts[1])

	if event is InputEventScreenDrag:
		touch_positions[event.index] = event.position

		var count = touch_positions.size()

		if count == 1 and touch_pan_enabled:
			apply_pan(event.relative)

		elif count == 2:
			var pts = touch_positions.values()
			var current_dist = pts[0].distance_to(pts[1])

			if touch_rotate_enabled:
				target_angle += -event.relative.x * touch_rotate_speed

			if prev_pinch_distance > 0.0:
				var delta_dist = prev_pinch_distance - current_dist
				$Camera3D.adjust_zoom(delta_dist * 0.05)
			prev_pinch_distance = current_dist

	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()

func _locate_cords():
	if gridmapinuse and gridmapinuse != self:
		if gridmapinuse.has_node("grid"):
			grid_node = gridmapinuse.get_node("grid")
		elif gridmapinuse is Grid:
			grid_node = gridmapinuse
		elif gridmapinuse.get_child_count() > 0:
			grid_node = gridmapinuse.get_child(0)

func _raycast_to_grid():
	var space_state = get_world_3d().direct_space_state
	var mouse_pos = get_viewport().get_mouse_position()
	var origin = $Camera3D.project_ray_origin(mouse_pos)
	var end = origin + $Camera3D.project_ray_normal(mouse_pos) * 1000.0
	
	var query = PhysicsRayQueryParameters3D.create(origin, end)
	var result = space_state.intersect_ray(query)
	
	if not result.is_empty() and result.collider:
		var hit_node = result.collider
		var valid_hit := false
		
		if grid_node and (grid_node.is_ancestor_of(hit_node) or hit_node == grid_node):
			valid_hit = true
		else:
			var check_node = hit_node
			while check_node != null:
				if check_node is Grid:
					valid_hit = true
					grid_node = check_node 
					break
				check_node = check_node.get_parent()
				
		if valid_hit:
			var hit_inside = result.position - result.normal * 0.1
			var cell_coord = Vector3i(
				floori(hit_inside.x),
				floori(hit_inside.y),
				floori(hit_inside.z)
			)
			snap_to_cell(cell_coord)
