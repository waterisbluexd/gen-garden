extends Resource
class_name BlockType

@export var id: int
@export var block_name: String

@export var height: float = 1.0

@export var uv_top:         int
@export var uv_bottom:      int
@export var uv_side_front:  int
@export var uv_side_back:   int
@export var uv_side_left:   int
@export var uv_side_right:  int

@export var color_top:    Color = Color(1.0,  1.0,  1.0,  1.0)
@export var color_front:  Color = Color(0.85, 0.85, 0.85, 1.0)
@export var color_back:   Color = Color(0.75, 0.75, 0.75, 1.0)
@export var color_left:   Color = Color(0.7,  0.7,  0.7,  1.0)
@export var color_right:  Color = Color(0.7,  0.7,  0.7,  1.0)
@export var color_bottom: Color = Color(0.5,  0.5,  0.5,  1.0)
