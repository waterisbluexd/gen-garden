extends MultiMeshInstance3D

@export var source_mesh_node: MeshInstance3D
@export var stage_durations: Array[float] = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0]

var _positions:     Array[Vector3] = []
var _swing_offsets: PackedFloat32Array
var _stages:        PackedInt32Array
var _stage_timers:  PackedFloat32Array
var _mat:           ShaderMaterial

var _last_stage: int:
	get: return stage_durations.size() - 1

func _ready() -> void:
	if not source_mesh_node:
		push_error("source_mesh_node not set")
		return
	_mat = source_mesh_node.get_active_material(0) as ShaderMaterial
	if not _mat:
		push_error("No ShaderMaterial found")
		return
	source_mesh_node.visible = false
	material_override = _mat

func plant(world_position: Vector3) -> int:
	var t := Time.get_ticks_usec()

	var idx := _positions.size()
	_positions.append(world_position)
	_swing_offsets.resize(_positions.size())
	_stages.resize(_positions.size())
	_stage_timers.resize(_positions.size())

	_swing_offsets[idx] = randf()
	_stages[idx]        = 0
	_stage_timers[idx]  = 0.0

	_grow_multimesh()
	_schedule(idx)

	print("plant() took: %d us" % (Time.get_ticks_usec() - t))
	return idx

func _schedule(idx: int) -> void:
	if idx >= _stages.size():
		return
	if _stages[idx] >= _last_stage:
		return
	var wait := stage_durations[_stages[idx]]
	get_tree().create_timer(wait).timeout.connect(func():
		if idx >= _stages.size():
			return
		_stages[idx] += 1
		_push(idx)
		#print("crop %d → stage %d %s" % [
			#idx,
			#_stages[idx],
			#"(harvestable!)" if _stages[idx] >= _last_stage else ""
		#])
		_schedule(idx)
	)

func harvest_at(world_position: Vector3) -> void:
	var idx := _positions.find(world_position)
	if idx == -1:
		return
	_positions.remove_at(idx)
	_swing_offsets.remove_at(idx)
	_stages.remove_at(idx)
	_stage_timers.remove_at(idx)
	_rebuild()

func is_harvestable(world_position: Vector3) -> bool:
	var idx := _positions.find(world_position)
	if idx == -1:
		return false
	return _stages[idx] >= _last_stage

func _grow_multimesh() -> void:
	var t := Time.get_ticks_usec()
	var count := _positions.size()
	if not multimesh or multimesh.mesh != source_mesh_node.mesh:
		_rebuild()
		return
	multimesh.instance_count = count
	for i in count:
		multimesh.set_instance_transform(i, Transform3D(Basis(), _positions[i]))
		_push(i)
	print("_grow_multimesh() took: %d us" % (Time.get_ticks_usec() - t))

func _rebuild() -> void:
	var t := Time.get_ticks_usec()
	if not source_mesh_node:
		return
	var mm        := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data  = true
	mm.instance_count   = _positions.size()
	mm.mesh             = source_mesh_node.mesh
	multimesh           = mm
	for i in _positions.size():
		multimesh.set_instance_transform(i, Transform3D(Basis(), _positions[i]))
		_push(i)
	print("_rebuild() took: %d us" % (Time.get_ticks_usec() - t))

func _push(i: int) -> void:
	multimesh.set_instance_custom_data(i,
		Color(float(_stages[i]),
			  0.0,
			  _swing_offsets[i],
			  0.0))
