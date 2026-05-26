class_name Crop
extends Node3D

@export var stage_textures: Array[Texture2D] = []
@export var stage_times: Array[float] = []
@export var mesh_stages: Array[MeshInstance3D] = []
@export var mesh_stage_thresholds: Array[int] = []

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
	_update_mesh_stages()

func _update_mesh_stages() -> void:
	# Safe — does nothing if arrays not set in Inspector
	if mesh_stages.is_empty() or mesh_stage_thresholds.is_empty():
		return
	for mesh in mesh_stages:
		if mesh:
			mesh.visible = false
	var active_idx = -1
	for i in range(mesh_stage_thresholds.size()):
		if current_stage >= mesh_stage_thresholds[i]:
			active_idx = i
	if active_idx >= 0 and active_idx < mesh_stages.size():
		if mesh_stages[active_idx]:
			mesh_stages[active_idx].visible = true

func harvest():
	if is_harvestable:
		queue_free()

func remove_crop():
	queue_free()
