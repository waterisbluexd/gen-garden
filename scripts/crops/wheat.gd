@tool
class_name WheatCrop
extends Crop

@export var stems: Array[MeshInstance3D] = []
@export var mesh_stages: Array[MeshInstance3D] = []
# Which stage index each mesh becomes visible at
# e.g. [0, 3, 6] means mesh_stages[0] shows at stage 0, mesh_stages[1] at stage 3, etc.
@export var mesh_stage_thresholds: Array[int] = []

var _mat: ShaderMaterial

func _crop_ready() -> void:
	_setup_shader()

func _setup_shader() -> void:
	if stems.is_empty() or stage_textures.is_empty():
		return
	var source_mat = stems[0].material_override as ShaderMaterial
	if not source_mat:
		push_error("Assign ShaderMaterial to stems[0] material_override!")
		return
	for stem in stems:
		var mat = source_mat.duplicate() as ShaderMaterial
		stem.material_override = mat
		for child in stem.get_children():
			if child is MeshInstance3D:
				child.material_override = mat

func update_visual() -> void:
	if stems.is_empty() or stage_textures.is_empty():
		return

	# Update texture
	var idx = clamp(current_stage, 0, stage_textures.size() - 1)
	for stem in stems:
		var mat = stem.material_override as ShaderMaterial
		if mat:
			mat.set_shader_parameter("texture_albedo", stage_textures[idx])

	# Update mesh visibility
	_update_mesh_stages()
	print("Wheat stage %d: texture updated" % current_stage)

func _update_mesh_stages() -> void:
	if mesh_stages.is_empty() or mesh_stage_thresholds.is_empty():
		return

	# Hide all first
	for mesh in mesh_stages:
		if mesh:
			mesh.visible = false

	# Find which mesh should be visible for current_stage
	# Last threshold that is <= current_stage wins
	var active_idx = -1
	for i in range(mesh_stage_thresholds.size()):
		if current_stage >= mesh_stage_thresholds[i]:
			active_idx = i

	if active_idx >= 0 and active_idx < mesh_stages.size():
		if mesh_stages[active_idx]:
			mesh_stages[active_idx].visible = true
