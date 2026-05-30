extends Node3D

# --- Configuration & State ---
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

# --- Lifecycle ---

func _ready():
	current_angle = rad_to_deg(rotation.y)
	target_angle = current_angle
	target_position = global_position
	_locate_cords()

func _process(delta: float):
	current_angle = lerp(current_angle, target_angle, rotation_speed * delta)
	rotation.y = deg_to_rad(current_angle)
	global_position = global_position.lerp(target_position, clamp(delta * pan_smoothness, 0.0, 1.0))

func raycast_from_screen(screen_pos: Vector2) -> Dictionary:
	var cam := $Camera3D
	return {
		"origin": cam.project_ray_origin(screen_pos),
		"direction": cam.project_ray_normal(screen_pos)
	}

# --- Camera Movement & Logic ---

func snap_to_cell(cell_coord: Vector3i) -> void:
	target_position = Vector3(float(cell_coord.x) + 0.5, target_position.y, float(cell_coord.z) + 0.5)

func apply_pan(relative: Vector2) -> void:
	var right = transform.basis.x
	var forward = transform.basis.z
	var camera_size = $Camera3D.size
	target_position -= right * relative.x * pan_speed * camera_size
	target_position -= forward * relative.y * pan_speed * camera_size

func _click_to_snap_camera() -> void:
	if not grid_node or not grid_node.has_method("dda_raycast"): 
		return
		
	var mouse_pos := get_viewport().get_mouse_position()
	var ray := raycast_from_screen(mouse_pos)
	
	# The Grid script now receives the dictionary format it expects
	var result: Dictionary = grid_node.dda_raycast(ray["origin"], ray["direction"], 100.0)
	
	if result.get("hit", false):
		snap_to_cell(result["position"])

# --- Input Handling ---

func _input(event: InputEvent):
	# Key Rotation
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_E: target_angle -= 45.0
		elif event.keycode == KEY_Q: target_angle += 45.0

	# Mouse Input
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			is_panning = event.pressed
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_click_to_snap_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			$Camera3D.adjust_zoom(-$Camera3D.zoom_speed)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			$Camera3D.adjust_zoom($Camera3D.zoom_speed)

	if event is InputEventMouseMotion and is_panning:
		apply_pan(event.relative)

	# Touch Input
	if event is InputEventScreenTouch:
		if event.pressed: touch_positions[event.index] = event.position
		else: touch_positions.erase(event.index)
		if touch_positions.size() == 2:
			prev_pinch_distance = touch_positions.values()[0].distance_to(touch_positions.values()[1])

	if event is InputEventScreenDrag:
		touch_positions[event.index] = event.position
		if touch_positions.size() == 1 and touch_pan_enabled:
			apply_pan(event.relative)
		elif touch_positions.size() == 2:
			var pts = touch_positions.values()
			var current_dist = pts[0].distance_to(pts[1])
			if touch_rotate_enabled: target_angle += -event.relative.x * touch_rotate_speed
			if prev_pinch_distance > 0.0:
				$Camera3D.adjust_zoom((prev_pinch_distance - current_dist) * 0.05)
			prev_pinch_distance = current_dist

	if event.is_action_pressed("ui_cancel"): get_tree().quit()

# --- Setup ---

func _locate_cords():
	if gridmapinuse:
		grid_node = gridmapinuse
	if grid_node and "camera" in grid_node:
		grid_node.camera = self
