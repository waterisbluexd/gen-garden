extends Camera3D

@export var zoom_speed: float = 4.0
@export var zoom_smoothness: float = 10.0
@export var min_size: float = 2.0
@export var max_size: float = 20.0

var target_size: float

func _ready() -> void:
	target_size = size


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:

		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			target_size -= zoom_speed

		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			target_size += zoom_speed

		target_size = clamp(target_size, min_size, max_size)


func _process(delta: float) -> void:
	size = lerp(size, target_size, delta * zoom_smoothness)
