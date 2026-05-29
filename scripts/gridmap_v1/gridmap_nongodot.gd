extends Node3D

@export var camera3d: Camera3D
@onready var grid: Grid = $grid

func _init() -> void:
	RenderingServer.set_debug_generate_wireframes(true)

func _ready() -> void:
	grid.camera = camera3d
	get_viewport().debug_draw = Viewport.DEBUG_DRAW_WIREFRAME

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_P:
			var vp = get_viewport()
			vp.debug_draw = (vp.debug_draw + 1) % 5
