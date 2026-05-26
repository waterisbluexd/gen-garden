extends MultiMeshInstance3D

var _types: Dictionary = {}

func register_type(type: String, mesh: Mesh, material: ShaderMaterial, fps: float, anim_columns: int, anim_stages: int) -> void:
	if _types.has(type):
		return
	_types[type] = {
		"mesh":         mesh,
		"material":     material,
		"fps":          fps,
		"anim_columns": anim_columns,
		"anim_stages":  anim_stages,
		"multimesh":    null,
		"node":         null,       # MultiMeshInstance3D node per type
		"crops":        [],
		"anim_frames":  PackedInt32Array(),
		"growth_stages":PackedInt32Array(),
		"elapsed":      0.0,
		"count":        0,
	}
	# Create a dedicated MultiMeshInstance3D node per crop type
	var mmi := MultiMeshInstance3D.new()
	mmi.material_override = material
	add_child(mmi)
	_types[type]["node"] = mmi

func register_crop(type: String, crop: Node3D) -> int:
	assert(_types.has(type), "CropRenderer: type '%s' not registered" % type)
	var d: Dictionary = _types[type]
	d["crops"].append(crop)
	d["count"] = d["crops"].size()
	_rebuild(type)
	return d["count"] - 1

func set_crop_stage(type: String, index: int, stage: int) -> void:
	if not _types.has(type):
		return
	var d: Dictionary = _types[type]
	if index < 0 or index >= d["count"]:
		return
	d["growth_stages"][index] = clamp(stage, 0, d["anim_stages"] - 1)
	_push(type, index)

func _rebuild(type: String) -> void:
	var d: Dictionary = _types[type]
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data  = true
	mm.instance_count   = d["count"]
	mm.mesh             = d["mesh"]

	d["multimesh"] = mm
	d["node"].multimesh = mm

	var af := PackedInt32Array()
	var gs := PackedInt32Array()
	af.resize(d["count"])
	gs.resize(d["count"])

	# Preserve existing stage data when rebuilding
	for i in d["count"]:
		af[i] = d["anim_frames"][i] if i < d["anim_frames"].size() else randi() % d["anim_columns"]
		gs[i] = d["growth_stages"][i] if i < d["growth_stages"].size() else 0
		mm.set_instance_transform(i, d["crops"][i].global_transform)
		_push_direct(d, i)

	d["anim_frames"]   = af
	d["growth_stages"] = gs

func _process(delta: float) -> void:
	for type in _types:
		var d: Dictionary = _types[type]
		if d["count"] == 0:
			continue
		d["elapsed"] += delta
		if d["elapsed"] < 1.0 / d["fps"]:
			continue
		d["elapsed"] = 0.0
		for i in d["count"]:
			d["anim_frames"][i] = (d["anim_frames"][i] + 1) % d["anim_columns"]
			_push_direct(d, i)

func _push(type: String, index: int) -> void:
	_push_direct(_types[type], index)

func _push_direct(d: Dictionary, i: int) -> void:
	d["multimesh"].set_instance_custom_data(i,
		Color(float(d["anim_frames"][i]),
			  float(d["growth_stages"][i]),
			  0.0, 0.0))
