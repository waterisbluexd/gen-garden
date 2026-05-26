extends Node3D

var target_angle := 0.0
var current_angle := 0.0
var rotation_speed := 8.0

@export var pan_speed: float = 0.01
@export var pan_smoothness: float = 12.0
@export var touch_pan_enabled: bool = true
@export var touch_rotate_enabled: bool = true
@export var touch_rotate_speed: float = 0.3

var is_panning: bool = false
var target_position: Vector3
var touch_positions: Dictionary = {}
var prev_pinch_distance: float = 0.0

func _ready():
	current_angle = rad_to_deg(rotation.y)
	target_angle = current_angle
	target_position = global_position

func _process(delta):
	current_angle = lerp(current_angle, target_angle, rotation_speed * delta)
	rotation.y = deg_to_rad(current_angle)
	global_position = global_position.lerp(target_position, clamp(delta * pan_smoothness, 0.0, 1.0))

func snap_to_hit(hit_world_pos: Vector3) -> void:
	target_position = Vector3(hit_world_pos.x, global_position.y, hit_world_pos.z)

func apply_pan(relative: Vector2) -> void:
	var right = transform.basis.x
	var forward = transform.basis.z
	var camera_size = $Camera3D.size
	target_position -= right * relative.x * pan_speed * camera_size
	target_position -= forward * relative.y * pan_speed * camera_size

func _input(event):
	# --- Keyboard rotate ---
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_E:
			target_angle -= 45.0
		elif event.keycode == KEY_Q:
			target_angle += 45.0

	# --- Mouse middle-click pan ---
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			is_panning = event.pressed

	if event is InputEventMouseMotion and is_panning:
		apply_pan(event.relative)

	# --- Mouse scroll zoom (desktop) ---
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			$Camera3D.adjust_zoom(-$Camera3D.zoom_speed)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			$Camera3D.adjust_zoom($Camera3D.zoom_speed)

	# --- Track touch contacts ---
	if event is InputEventScreenTouch:
		if event.pressed:
			touch_positions[event.index] = event.position
		else:
			touch_positions.erase(event.index)
		# Reset pinch baseline whenever finger count changes
		if touch_positions.size() == 2:
			var pts = touch_positions.values()
			prev_pinch_distance = pts[0].distance_to(pts[1])

	# --- Touch drag ---
	if event is InputEventScreenDrag:
		touch_positions[event.index] = event.position  # keep positions current

		var count = touch_positions.size()

		if count == 1 and touch_pan_enabled:
			# 1 finger → pan
			apply_pan(event.relative)

		elif count == 2:
			var pts = touch_positions.values()
			var current_dist = pts[0].distance_to(pts[1])

			if touch_rotate_enabled:
				# 2 finger horizontal drag → rotate
				target_angle += -event.relative.x * touch_rotate_speed

			# Pinch → zoom
			if prev_pinch_distance > 0.0:
				var delta_dist = prev_pinch_distance - current_dist  # shrink = zoom out
				$Camera3D.adjust_zoom(delta_dist * 0.05)
			prev_pinch_distance = current_dist

	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()
