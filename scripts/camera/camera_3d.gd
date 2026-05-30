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
