class_name Crop
extends Node3D

@export var stage_textures: Array[Texture2D] = []
@export var stage_times: Array[float] = []

var current_stage := 0
var timer := 0.0
var is_harvestable := false

func _ready() -> void:
	_crop_ready()    
	update_visual()  

func _crop_ready() -> void:
	pass  

func _process(delta: float) -> void:
	if is_harvestable:
		return
	timer += delta
	if current_stage < stage_times.size():
		if timer >= stage_times[current_stage]:
			timer = 0.0
			current_stage += 1
			update_visual()
			if current_stage >= stage_textures.size() - 1:
				is_harvestable = true
				print(name, " is harvestable")

func update_visual() -> void:
	pass

func harvest():
	if is_harvestable:
		queue_free()

func remove_crop():
	queue_free()
