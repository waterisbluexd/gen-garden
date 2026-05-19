extends Node3D

var target_angle := 0.0
var current_angle := 0.0
var rotation_speed := 8.0
@export var pan_speed: float = 0.01
@export var pan_smoothness: float = 12.0
@export var touch_pan_enabled: bool = true
@export var touch_rotate_enabled: bool = true
@export var touch_rotate_speed: float = 0.2
var is_panning: bool = false
var target_position: Vector3
var touch_positions: Dictionary = {}
var touch_pan_active: bool = false

func _ready():
	current_angle = rad_to_deg(rotation.y)
	target_angle = current_angle
	target_position = global_position

func _process(delta):
	current_angle = lerp(current_angle, target_angle, rotation_speed * delta)
	rotation.y = deg_to_rad(current_angle)
	global_position = global_position.lerp(target_position, clamp(delta * pan_smoothness, 0.0, 1.0))

func snap_to_hit(hit_world_pos: Vector3) -> void:
	# Called from Camera3D when raycast hits — snaps pivot to that world position
	target_position = Vector3(hit_world_pos.x, global_position.y, hit_world_pos.z)

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

	if event is InputEventScreenTouch and touch_pan_enabled:
		if event.pressed:
			touch_positions[event.index] = event.position
			touch_pan_active = touch_positions.size() == 1
		else:
			touch_positions.erase(event.index)
			touch_pan_active = touch_positions.size() == 1

	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()

	if event is InputEventScreenDrag and touch_pan_enabled and touch_pan_active and touch_positions.size() == 1:
		apply_pan(event.relative)

	if event is InputEventScreenDrag and touch_rotate_enabled and touch_positions.size() == 2:
		target_angle += -event.relative.x * touch_rotate_speed

	if event is InputEventMouseMotion and is_panning:
		apply_pan(event.relative)
