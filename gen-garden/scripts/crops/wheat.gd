@tool
class_name WheatCrop
extends Crop

@export var stems: Array[MeshInstance3D] = []

func _crop_ready() -> void:
	_setup_shader()

func _setup_shader() -> void:
	if stems.is_empty() or stage_textures.is_empty():
		return
	var source_mat = stems[0].material_override as ShaderMaterial
	if not source_mat:
		push_error("Assign ShaderMaterial to stems[0] material_override in Inspector!")
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
	var idx = clamp(current_stage, 0, stage_textures.size() - 1)
	for stem in stems:
		var mat = stem.material_override as ShaderMaterial
		if mat:
			mat.set_shader_parameter("texture_albedo", stage_textures[idx])
	super()  # runs _update_mesh_stages() from Crop
	print("Wheat stage %d: texture updated" % current_stage)
