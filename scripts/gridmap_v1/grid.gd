extends Node3D
class_name Grid

# Reusable container class to completely bypass the garbage collector allocations
class MeshBuffers:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uvs2 := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var vert_idx: int = 0
	
	func clear() -> void:
		verts.clear()
		normals.clear()
		uvs.clear()
		uvs2.clear()
		colors.clear()
		indices.clear()
		vert_idx = 0

@export var atlas_texture: Texture2D
@export var block_registry: BlockRegistry

@export var atlas_shader_opaque: ShaderMaterial      # Shader WITHOUT 'discard'
@export var atlas_shader_transparent: ShaderMaterial # Shader WITH 'discard'

@export_group("Base Layer Options")
@export var generate_base_layer: bool = true
@export var base_block_id: int = 2
@export var base_width: int = 64
@export var base_depth: int = 64
@export var base_y_level: int = 0

const CHUNK_SIZE: int = 32
const CHUNK_SIZE_M1: int = 31
const CHUNK_VOLUME: int = 32 * 32 * 32
const CHUNK_LAYER: int = 32 * 32
const MAX_COLLISION_BOXES: int = 64

const AO_VALUES: Array[float] = [1.0, 0.8, 0.6, 0.4]

var chunks: Dictionary = {}
var chunk_nodes: Dictionary = {}

var rebuild_queue: Dictionary = {}
var chunks_processing: Dictionary = {}
@export var chunks_per_frame_budget: int = 2

var camera: Node3D
var active_block_id: int = 1

# Optimization 2: Thread-safe Array Reuse Pool
var _buffer_pool: Array[MeshBuffers] = []
var _pool_mutex := Mutex.new()

# Optimization 4: Global Heightmap Tracking for RTS View Culling
var global_heightmap: Dictionary = {} # Vector2i(x, z) -> int (y)

func _ready() -> void:
	# Optimization 3: Lower internal 3D scale to remove fill-rate bottleneck on Mali GPU
	get_viewport().scaling_3d_scale = 0.75
	get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	
	if has_node("StaticBody3D"):
		$StaticBody3D.queue_free()
	if generate_base_layer:
		generate_world_progressive()

func _process(_delta: float) -> void:
	process_rebuild_queue()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1: active_block_id = 1
			KEY_2: active_block_id = 2
			KEY_3: active_block_id = 3
			KEY_4: active_block_id = 4
			KEY_5: active_block_id = 5
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			place_block_from_mouse(active_block_id)
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			remove_block_from_mouse()

@warning_ignore("integer_division")
func get_chunk_coord(global_pos: Vector3i) -> Vector3i:
	return Vector3i(
		floori(float(global_pos.x) / CHUNK_SIZE),
		floori(float(global_pos.y) / CHUNK_SIZE),
		floori(float(global_pos.z) / CHUNK_SIZE)
	)

func get_global_voxel(global_pos: Vector3i) -> int:
	var cc := get_chunk_coord(global_pos)
	if not chunks.has(cc): return 0
	var lx: int = posmod(global_pos.x, CHUNK_SIZE)
	var ly: int = posmod(global_pos.y, CHUNK_SIZE)
	var lz: int = posmod(global_pos.z, CHUNK_SIZE)
	return chunks[cc][lx + (ly * CHUNK_SIZE) + (lz * CHUNK_LAYER)]

func generate_world_progressive() -> void:
	var affected: Dictionary = {}
	var ly: int = posmod(base_y_level, CHUNK_SIZE)
	for z in range(base_depth):
		for x in range(base_width):
			var global_pos := Vector3i(x, base_y_level, z)
			var cc := get_chunk_coord(global_pos)
			if not chunks.has(cc):
				var c := PackedByteArray()
				c.resize(CHUNK_VOLUME)
				chunks[cc] = c
			var lx: int = posmod(x, CHUNK_SIZE)
			var lz: int = posmod(z, CHUNK_SIZE)
			chunks[cc][lx + (ly * CHUNK_SIZE) + (lz * CHUNK_LAYER)] = base_block_id
			
			# Populate initial heightmap
			global_heightmap[Vector2i(x, z)] = base_y_level
			affected[cc] = true
	for c in affected:
		rebuild_queue[c] = true

func set_cell(x: int, y: int, z: int, block_id: int) -> void:
	var global_pos := Vector3i(x, y, z)
	var cc := get_chunk_coord(global_pos)
	if not chunks.has(cc):
		var c := PackedByteArray()
		c.resize(CHUNK_VOLUME)
		chunks[cc] = c
	chunks[cc][posmod(x, CHUNK_SIZE) + (posmod(y, CHUNK_SIZE) * CHUNK_SIZE) + (posmod(z, CHUNK_SIZE) * CHUNK_LAYER)] = block_id
	
	# Optimization 4: Track updates on heightmap
	var h_key := Vector2i(x, z)
	if block_id != 0:
		if y > global_heightmap.get(h_key, -1):
			global_heightmap[h_key] = y
	else:
		if y == global_heightmap.get(h_key, -1):
			_recalc_heightmap_column(x, z, y)

	_queue_block_neighbors(global_pos)

func remove_cell(x: int, y: int, z: int) -> void:
	var global_pos := Vector3i(x, y, z)
	var cc := get_chunk_coord(global_pos)
	if not chunks.has(cc): return
	chunks[cc][posmod(x, CHUNK_SIZE) + (posmod(y, CHUNK_SIZE) * CHUNK_SIZE) + (posmod(z, CHUNK_SIZE) * CHUNK_LAYER)] = 0
	
	# Optimization 4: Track removals on heightmap
	var h_key := Vector2i(x, z)
	if y == global_heightmap.get(h_key, -1):
		_recalc_heightmap_column(x, z, y)
		
	_queue_block_neighbors(global_pos)

func _recalc_heightmap_column(x: int, z: int, start_y: int) -> void:
	var h_key := Vector2i(x, z)
	for y in range(start_y, -1, -1):
		if get_global_voxel(Vector3i(x, y, z)) != 0:
			global_heightmap[h_key] = y
			return
	global_heightmap[h_key] = -1

func _queue_block_neighbors(global_pos: Vector3i) -> void:
	var cc := get_chunk_coord(global_pos)
	rebuild_queue[cc] = true
	var lx: int = posmod(global_pos.x, CHUNK_SIZE)
	var ly: int = posmod(global_pos.y, CHUNK_SIZE)
	var lz: int = posmod(global_pos.z, CHUNK_SIZE)
	if lx == 0:             rebuild_queue[cc + Vector3i(-1, 0, 0)] = true
	if lx == CHUNK_SIZE_M1: rebuild_queue[cc + Vector3i(1, 0, 0)]  = true
	if ly == 0:             rebuild_queue[cc + Vector3i(0, -1, 0)] = true
	if ly == CHUNK_SIZE_M1: rebuild_queue[cc + Vector3i(0, 1, 0)]  = true
	if lz == 0:             rebuild_queue[cc + Vector3i(0, 0, -1)] = true
	if lz == CHUNK_SIZE_M1: rebuild_queue[cc + Vector3i(0, 0, 1)]  = true

func dda_raycast(ray_origin: Vector3, ray_direction: Vector3, max_distance: float) -> Dictionary:
	var dir := ray_direction.normalized()
	var map_pos := Vector3i(floori(ray_origin.x), floori(ray_origin.y), floori(ray_origin.z))
	var delta_dist := Vector3(
		abs(1.0 / (dir.x if dir.x != 0.0 else 0.00001)),
		abs(1.0 / (dir.y if dir.y != 0.0 else 0.00001)),
		abs(1.0 / (dir.z if dir.z != 0.0 else 0.00001))
	)
	var step := Vector3i.ZERO
	var side_dist := Vector3.ZERO
	if dir.x < 0:
		step.x = -1
		side_dist.x = (ray_origin.x - map_pos.x) * delta_dist.x
	else:
		step.x = 1
		side_dist.x = (map_pos.x + 1.0 - ray_origin.x) * delta_dist.x
	if dir.y < 0:
		step.y = -1
		side_dist.y = (ray_origin.y - map_pos.y) * delta_dist.y
	else:
		step.y = 1
		side_dist.y = (map_pos.y + 1.0 - ray_origin.y) * delta_dist.y
	if dir.z < 0:
		step.z = -1
		side_dist.z = (ray_origin.z - map_pos.z) * delta_dist.z
	else:
		step.z = 1
		side_dist.z = (map_pos.z + 1.0 - ray_origin.z) * delta_dist.z
	var total_dist: float = 0.0
	var last_axis := Vector3i.ZERO
	while total_dist < max_distance:
		if side_dist.x < side_dist.y and side_dist.x < side_dist.z:
			total_dist = side_dist.x
			side_dist.x += delta_dist.x
			map_pos.x += step.x
			last_axis = Vector3i(-step.x, 0, 0)
		elif side_dist.y < side_dist.z:
			total_dist = side_dist.y
			side_dist.y += delta_dist.y
			map_pos.y += step.y
			last_axis = Vector3i(0, -step.y, 0)
		else:
			total_dist = side_dist.z
			side_dist.z += delta_dist.z
			map_pos.z += step.z
			last_axis = Vector3i(0, 0, -step.z)
		if total_dist > max_distance: break
		if get_global_voxel(map_pos) != 0:
			return {"hit": true, "position": map_pos, "normal": last_axis}
	return {"hit": false, "position": Vector3i.ZERO, "normal": Vector3i.ZERO}

func place_block_from_mouse(block_id: int) -> void:
	if camera == null: return
	var ray: Dictionary = camera.raycast_from_screen(get_viewport().get_mouse_position())
	var result: Dictionary = dda_raycast(ray["origin"], ray["direction"], 500.0)
	if not result["hit"]: return
	var target: Vector3i = result["position"] + result["normal"]
	set_cell(target.x, target.y, target.z, block_id)

func remove_block_from_mouse() -> void:
	if camera == null: return
	var ray: Dictionary = camera.raycast_from_screen(get_viewport().get_mouse_position())
	var result: Dictionary = dda_raycast(ray["origin"], ray["direction"], 500.0)
	if not result["hit"]: return
	var hit: Vector3i = result["position"]
	remove_cell(hit.x, hit.y, hit.z)

func process_rebuild_queue() -> void:
	if rebuild_queue.is_empty(): return
	var budget := chunks_per_frame_budget
	for cc in rebuild_queue.keys():
		if budget <= 0: break
		if chunks_processing.has(cc): continue
		rebuild_queue.erase(cc)
		chunks_processing[cc] = true
		_dispatch_chunk_thread(cc)
		budget -= 1

func _get_pooled_buffers() -> Array[MeshBuffers]:
	_pool_mutex.lock()
	var pair: Array[MeshBuffers] = []
	while _buffer_pool.size() < 2:
		_buffer_pool.append(MeshBuffers.new())
	pair.append(_buffer_pool.pop_back())
	pair.append(_buffer_pool.pop_back())
	_pool_mutex.unlock()
	return pair

func _recycle_buffers(b1: MeshBuffers, b2: MeshBuffers) -> void:
	b1.clear()
	b2.clear()
	_pool_mutex.lock()
	_buffer_pool.append(b1)
	_buffer_pool.append(b2)
	_pool_mutex.unlock()

func _dispatch_chunk_thread(cc: Vector3i) -> void:
	var snap: Dictionary = {}
	for dir in [Vector3i(0,0,0), Vector3i(1,0,0), Vector3i(-1,0,0),
				Vector3i(0,1,0), Vector3i(0,-1,0), Vector3i(0,0,1), Vector3i(0,0,-1)]:
		var nc: Vector3i = cc + dir
		if chunks.has(nc): snap[nc] = chunks[nc].duplicate()
		
	# Optimization 2: Pull allocation-free buffers from our thread pool
	var bufs := _get_pooled_buffers()
	
	WorkerThreadPool.add_task(func():
		var result := _build_chunk_mesh(cc, snap, bufs[0], bufs[1])
		call_deferred("_apply_mesh", cc, result)
	)

func _apply_mesh(cc: Vector3i, result: Dictionary) -> void:
	chunks_processing.erase(cc)
	if not chunk_nodes.has(cc):
		_ensure_chunk_node(cc)
		
	var node: Dictionary = chunk_nodes[cc]
	node.mi_opaque.mesh = result.opaque_mesh
	node.mi_trans.mesh = result.transparent_mesh
	_clear_collision(node)
	
	# Optimization 2: Safely return arrays back into the pipeline
	_recycle_buffers(result.opaque_buf, result.trans_buf)
	
	if result.opaque_mesh == null and result.transparent_mesh == null: return
	
	# Low level PhysicsServer3D Calls (Completely off SceneTree thread)
	for box in result.boxes:
		var shape_rid := PhysicsServer3D.box_shape_create()
		PhysicsServer3D.shape_set_data(shape_rid, box.size)
		var local_transform := Transform3D(Basis(), box.pos)
		PhysicsServer3D.body_add_shape(node.body_rid, shape_rid, local_transform)
		node.shapes.append(shape_rid)

func _clear_collision(node_data: Dictionary) -> void:
	for shape_rid in node_data.shapes:
		PhysicsServer3D.free_rid(shape_rid)
	node_data.shapes.clear()

func _ensure_chunk_node(cc: Vector3i) -> void:
	if chunk_nodes.has(cc): return
	var node := Node3D.new()
	add_child(node)
	node.global_position = Vector3(cc * CHUNK_SIZE)
	
	# Optimization 1: Bind discrete Mesh Instances to isolate pipelines
	var mi_opaque := MeshInstance3D.new()
	mi_opaque.material_override = atlas_shader_opaque
	node.add_child(mi_opaque)
	
	var mi_trans := MeshInstance3D.new()
	mi_trans.material_override = atlas_shader_transparent
	node.add_child(mi_trans)
	
	var body_rid := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body_rid, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_space(body_rid, get_world_3d().space)
	PhysicsServer3D.body_set_state(body_rid, PhysicsServer3D.BODY_STATE_TRANSFORM, node.global_transform)
	
	chunk_nodes[cc] = {"node": node, "mi_opaque": mi_opaque, "mi_trans": mi_trans, "body_rid": body_rid, "shapes": []}

func _exit_tree() -> void:
	for cc in chunk_nodes:
		_clear_collision(chunk_nodes[cc])
		PhysicsServer3D.free_rid(chunk_nodes[cc].body_rid)
	_buffer_pool.clear()

func _ao_score(s1: bool, s2: bool, corner: bool) -> int:
	if s1 and s2: return 3
	var sum := int(s1) + int(s2) + int(corner)
	return clampi(sum, 0, 3)

func _ao_solid(data: PackedByteArray, lx: int, ly: int, lz: int) -> bool:
	if lx < 0 or lx >= CHUNK_SIZE or ly < 0 or ly >= CHUNK_SIZE or lz < 0 or lz >= CHUNK_SIZE:
		return false
	return data[lx + (ly * CHUNK_SIZE) + (lz * CHUNK_LAYER)] != 0

func _build_chunk_mesh(cc: Vector3i, snap: Dictionary, opaque_buf: MeshBuffers, trans_buf: MeshBuffers) -> Dictionary:
	var output := {"opaque_mesh": null, "transparent_mesh": null, "boxes": [], "opaque_buf": opaque_buf, "trans_buf": trans_buf}
	if not snap.has(cc): return output
	var data: PackedByteArray = snap[cc]

	var block_cache: Dictionary = {}
	var empty := true
	for i in range(CHUNK_VOLUME):
		var id: int = data[i]
		if id != 0:
			empty = false
			if not block_cache.has(id):
				block_cache[id] = block_registry.get_block(id)
	if empty: return output

	# Optimization 4: Slice the Loop boundaries. Find highest block to skip scanning air layers completely
	var max_ly := -1
	for ly in range(CHUNK_SIZE_M1, -1, -1):
		var layer_has_blocks := false
		var stride := ly * CHUNK_SIZE
		for lz in range(CHUNK_SIZE):
			var layer := lz * CHUNK_LAYER
			for lx in range(CHUNK_SIZE):
				if data[lx + stride + layer] != 0:
					layer_has_blocks = true
					break
			if layer_has_blocks: break
		if layer_has_blocks:
			max_ly = ly
			break
			
	if max_ly == -1: return output

	var nc_top   := Vector3i(cc.x, cc.y + 1, cc.z)
	var nc_bot   := Vector3i(cc.x, cc.y - 1, cc.z)
	var nc_front := Vector3i(cc.x, cc.y, cc.z + 1)
	var nc_back  := Vector3i(cc.x, cc.y, cc.z - 1)
	var nc_right := Vector3i(cc.x + 1, cc.y, cc.z)
	var nc_left  := Vector3i(cc.x - 1, cc.y, cc.z)

	var nd_top:   PackedByteArray = snap[nc_top]   if snap.has(nc_top)   else PackedByteArray()
	var nd_bot:   PackedByteArray = snap[nc_bot]   if snap.has(nc_bot)   else PackedByteArray()
	var nd_front: PackedByteArray = snap[nc_front] if snap.has(nc_front) else PackedByteArray()
	var nd_back:  PackedByteArray = snap[nc_back]  if snap.has(nc_back)  else PackedByteArray()
	var nd_right: PackedByteArray = snap[nc_right] if snap.has(nc_right) else PackedByteArray()
	var nd_left:  PackedByteArray = snap[nc_left]  if snap.has(nc_left)  else PackedByteArray()

	var has_top:   bool = nd_top.size()   > 0
	var has_bot:   bool = nd_bot.size()   > 0
	var has_front: bool = nd_front.size() > 0
	var has_back:  bool = nd_back.size()  > 0
	var has_right: bool = nd_right.size() > 0
	var has_left:  bool = nd_left.size()  > 0

	var collision_boxes: Array = []

	# Face registries split by Opaque (o) and Transparent (t)
	var top_f_o := {};   var top_f_t := {}
	var bot_f_o := {};   var bot_f_t := {}
	var front_f_o := {}; var front_f_t := {}
	var back_f_o := {};  var back_f_t := {}
	var right_f_o := {}; var right_f_t := {}
	var left_f_o := {};  var left_f_t := {}

	var greedy_cell_set: Dictionary = {}
	var greedy_visited:  Dictionary = {}

	# Loop optimization applied: scans only up to max_ly instead of CHUNK_SIZE
	for ly in range(max_ly + 1):
		var ly_stride:   int = ly * CHUNK_SIZE
		var ly1_stride:  int = (ly + 1) * CHUNK_SIZE
		var ly_1_stride: int = (ly - 1) * CHUNK_SIZE
		for lz in range(CHUNK_SIZE):
			var lz_layer:   int = lz * CHUNK_LAYER
			var lz1_layer:  int = (lz + 1) * CHUNK_LAYER
			var lz_1_layer: int = (lz - 1) * CHUNK_LAYER
			for lx in range(CHUNK_SIZE):
				var idx: int = lx + ly_stride + lz_layer
				var id: int = data[idx]
				if id == 0: continue

				var block: BlockType = block_cache[id]
				var is_trans: bool = block.get(&"is_transparent") if "is_transparent" in block else false
				var bh: float = block.height

				var top_exposed: bool
				if ly < CHUNK_SIZE_M1:
					top_exposed = data[lx + ly1_stride + lz_layer] == 0 or bh < 1.0
				else:
					top_exposed = (not has_top) or nd_top[lx + lz_layer] == 0 or bh < 1.0
				if top_exposed:
					var aly := ly + 1
					var s0 := _ao_score(_ao_solid(data, lx-1, aly, lz), _ao_solid(data, lx, aly, lz-1), _ao_solid(data, lx-1, aly, lz-1))
					var s1 := _ao_score(_ao_solid(data, lx+1, aly, lz), _ao_solid(data, lx, aly, lz-1), _ao_solid(data, lx+1, aly, lz-1))
					var s2 := _ao_score(_ao_solid(data, lx+1, aly, lz), _ao_solid(data, lx, aly, lz+1), _ao_solid(data, lx+1, aly, lz+1))
					var s3 := _ao_score(_ao_solid(data, lx-1, aly, lz), _ao_solid(data, lx, aly, lz+1), _ao_solid(data, lx-1, aly, lz+1))
					
					var packed_ao := s0 | (s1 << 2) | (s2 << 4) | (s3 << 6)
					var k := Vector3i(ly, id, packed_ao)
					var t_map := top_f_t if is_trans else top_f_o
					if not t_map.has(k): t_map[k] = []
					t_map[k].append(Vector2i(lx, lz))

				var bot_exposed: bool
				if ly > 0:
					bot_exposed = data[lx + ly_1_stride + lz_layer] == 0
				else:
					bot_exposed = (not has_bot) or nd_bot[lx + (CHUNK_SIZE_M1 * CHUNK_SIZE) + lz_layer] == 0
				if bot_exposed:
					var k := Vector2i(ly, id)
					var t_map := bot_f_t if is_trans else bot_f_o
					if not t_map.has(k): t_map[k] = []
					t_map[k].append(Vector2i(lx, lz))

				var front_nid: int = data[lx + ly_stride + lz1_layer] if lz < CHUNK_SIZE_M1 else (nd_front[lx + ly_stride] if has_front else 0)
				if front_nid == 0 or (block_cache.has(front_nid) and block_cache[front_nid].height != bh):
					var k := Vector2i(lz, id)
					var t_map := front_f_t if is_trans else front_f_o
					if not t_map.has(k): t_map[k] = []
					t_map[k].append(Vector2i(lx, ly))

				var back_nid: int = data[lx + ly_stride + lz_1_layer] if lz > 0 else (nd_back[lx + ly_stride + (CHUNK_SIZE_M1 * CHUNK_LAYER)] if has_back else 0)
				if back_nid == 0 or (block_cache.has(back_nid) and block_cache[back_nid].height != bh):
					var k := Vector2i(lz, id)
					var t_map := back_f_t if is_trans else back_f_o
					if not t_map.has(k): t_map[k] = []
					t_map[k].append(Vector2i(lx, ly))

				var right_nid: int = data[lx + 1 + ly_stride + lz_layer] if lx < CHUNK_SIZE_M1 else (nd_right[ly_stride + lz_layer] if has_right else 0)
				if right_nid == 0 or (block_cache.has(right_nid) and block_cache[right_nid].height != bh):
					var k := Vector2i(lx, id)
					var t_map := right_f_t if is_trans else right_f_o
					if not t_map.has(k): t_map[k] = []
					t_map[k].append(Vector2i(lz, ly))

				var left_nid: int = data[lx - 1 + ly_stride + lz_layer] if lx > 0 else (nd_left[CHUNK_SIZE_M1 + ly_stride + lz_layer] if has_left else 0)
				if left_nid == 0 or (block_cache.has(left_nid) and block_cache[left_nid].height != bh):
					var k := Vector2i(lx, id)
					var t_map := left_f_t if is_trans else left_f_o
					if not t_map.has(k): t_map[k] = []
					t_map[k].append(Vector2i(lz, ly))

	# --- Generate Opaque Pass ---
	_build_pass_geometry(top_f_o, bot_f_o, front_f_o, back_f_o, right_f_o, left_f_o, block_cache, opaque_buf, greedy_cell_set, greedy_visited, collision_boxes, true)
	
	# --- Generate Transparent Pass ---
	_build_pass_geometry(top_f_t, bot_f_t, front_f_t, back_f_t, right_f_t, left_f_t, block_cache, trans_buf, greedy_cell_set, greedy_visited, collision_boxes, false)

	output.opaque_mesh = _create_mesh_from_buffer(opaque_buf, atlas_shader_opaque)
	output.transparent_mesh = _create_mesh_from_buffer(trans_buf, atlas_shader_transparent)
	output.boxes = collision_boxes
	return output

func _build_pass_geometry(top_f: Dictionary, bot_f: Dictionary, front_f: Dictionary, back_f: Dictionary, right_f: Dictionary, left_f: Dictionary, block_cache: Dictionary, b: MeshBuffers, cell_set: Dictionary, visited: Dictionary, collision_boxes: Array, gen_collision: bool) -> void:
	for key in top_f:
		var block: BlockType = block_cache[key.y]
		var y_base: float = float(key.x) + block.height
		var packed_ao: int = key.z
		var ao0: float = AO_VALUES[packed_ao & 3]
		var ao1: float = AO_VALUES[(packed_ao >> 2) & 3]
		var ao2: float = AO_VALUES[(packed_ao >> 4) & 3]
		var ao3: float = AO_VALUES[(packed_ao >> 6) & 3]
		var bc := block.color_top
		var c0 := Color(bc.r * ao0, bc.g * ao0, bc.b * ao0, 1.0)
		var c1 := Color(bc.r * ao1, bc.g * ao1, bc.b * ao1, 1.0)
		var c2 := Color(bc.r * ao2, bc.g * ao2, bc.b * ao2, 1.0)
		var c3 := Color(bc.r * ao3, bc.g * ao3, bc.b * ao3, 1.0)

		for q in _greedy(top_f[key], cell_set, visited):
			var x0: int = q.x;  var x1: int = q.x + q.w
			var z0: int = q.y;  var z1: int = q.y + q.d
			_emit_quad(b, Vector3(float(x0), y_base, float(z0)), Vector3(float(x1), y_base, float(z0)), Vector3(float(x1), y_base, float(z1)), Vector3(float(x0), y_base, float(z1)), Vector3(0, 1, 0), block.uv_top, q.w, q.d, c0, c1, c2, c3)
			if gen_collision and collision_boxes.size() < MAX_COLLISION_BOXES:
				collision_boxes.append({
					"pos":  Vector3(float(x0) + float(q.w)*0.5, float(key.x)+0.5, float(z0) + float(q.d)*0.5),
					"size": Vector3(float(q.w), 1.0, float(q.d))
				})

	for key in bot_f:
		var block: BlockType = block_cache[key.y]
		var y_base: float = float(key.x)
		var bc := block.color_bottom
		for q in _greedy(bot_f[key], cell_set, visited):
			_emit_quad(b, Vector3(float(q.x + q.w), y_base, float(q.y)), Vector3(float(q.x), y_base, float(q.y)), Vector3(float(q.x), y_base, float(q.y + q.d)), Vector3(float(q.x + q.w), y_base, float(q.y + q.d)), Vector3(0, -1, 0), block.uv_bottom, q.w, q.d, bc, bc, bc, bc)

	for key in front_f:
		var block: BlockType = block_cache[key.y]
		var z1f := float(key.x + 1)
		var bc := block.color_front
		for q in _greedy(front_f[key], cell_set, visited):
			var y0 := float(q.y); var y1 := float(q.y) + float(q.d) * block.height
			_emit_quad(b, Vector3(float(q.x + q.w), y0, z1f), Vector3(float(q.x), y0, z1f), Vector3(float(q.x), y1, z1f), Vector3(float(q.x + q.w), y1, z1f), Vector3(0, 0, 1), block.uv_side_front, q.w, q.d, bc, bc, bc, bc)

	for key in back_f:
		var block: BlockType = block_cache[key.y]
		var z0b := float(key.x)
		var bc := block.color_back
		for q in _greedy(back_f[key], cell_set, visited):
			var y0 := float(q.y); var y1 := float(q.y) + float(q.d) * block.height
			_emit_quad(b, Vector3(float(q.x), y0, z0b), Vector3(float(q.x + q.w), y0, z0b), Vector3(float(q.x + q.w), y1, z0b), Vector3(float(q.x), y1, z0b), Vector3(0, 0, -1), block.uv_side_back, q.w, q.d, bc, bc, bc, bc)

	for key in right_f:
		var block: BlockType = block_cache[key.y]
		var x1r := float(key.x + 1)
		var bc := block.color_right
		for q in _greedy(right_f[key], cell_set, visited):
			var y0 := float(q.y); var y1 := float(q.y) + float(q.d) * block.height
			_emit_quad(b, Vector3(x1r, y0, float(q.x)), Vector3(x1r, y0, float(q.x + q.w)), Vector3(x1r, y1, float(q.x + q.w)), Vector3(x1r, y1, float(q.x)), Vector3(1, 0, 0), block.uv_side_right, q.w, q.d, bc, bc, bc, bc)

	for key in left_f:
		var block: BlockType = block_cache[key.y]
		var x0l := float(key.x)
		var bc := block.color_left
		for q in _greedy(left_f[key], cell_set, visited):
			var y0 := float(q.y); var y1 := float(q.y) + float(q.d) * block.height
			_emit_quad(b, Vector3(x0l, y0, float(q.x + q.w)), Vector3(x0l, y0, float(q.x)), Vector3(x0l, y1, float(q.x)), Vector3(x0l, y1, float(q.x + q.w)), Vector3(-1, 0, 0), block.uv_side_left, q.w, q.d, bc, bc, bc, bc)

func _create_mesh_from_buffer(b: MeshBuffers, mat: Material) -> ArrayMesh:
	if b.vert_idx == 0: return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]  = b.verts
	arrays[Mesh.ARRAY_NORMAL]  = b.normals
	arrays[Mesh.ARRAY_TEX_UV]  = b.uvs
	arrays[Mesh.ARRAY_TEX_UV2] = b.uvs2
	arrays[Mesh.ARRAY_COLOR]   = b.colors
	arrays[Mesh.ARRAY_INDEX]   = b.indices
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	am.surface_set_material(0, mat)
	return am

func _emit_quad(b: MeshBuffers, v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3, normal: Vector3, tile_index: int, u_tiles: int, v_tiles: int, c0: Color, c1: Color, c2: Color, c3: Color) -> void:
	var vi = b.vert_idx
	b.verts.append(v0); b.verts.append(v1); b.verts.append(v2); b.verts.append(v3)
	b.normals.append(normal); b.normals.append(normal); b.normals.append(normal); b.normals.append(normal)
	b.uvs.append(Vector2(0, v_tiles)); b.uvs.append(Vector2(u_tiles, v_tiles))
	b.uvs.append(Vector2(u_tiles, 0)); b.uvs.append(Vector2(0, 0))
	var ti := Vector2(float(tile_index), 0.0)
	b.uvs2.append(ti); b.uvs2.append(ti); b.uvs2.append(ti); b.uvs2.append(ti)
	b.colors.append(c0); b.colors.append(c1); b.colors.append(c2); b.colors.append(c3)
	b.indices.append(vi); b.indices.append(vi+1); b.indices.append(vi+2)
	b.indices.append(vi); b.indices.append(vi+2); b.indices.append(vi+3)
	b.vert_idx += 4

func _greedy(coords: Array, cell_set: Dictionary, visited: Dictionary) -> Array:
	cell_set.clear()
	visited.clear()
	for c in coords:
		cell_set[c] = true
	coords.sort()
	var result: Array = []
	for coord in coords:
		if visited.has(coord): continue
		var cx: int = coord.x
		var cy: int = coord.y
		var w := 1
		while cell_set.has(Vector2i(cx + w, cy)) and not visited.has(Vector2i(cx + w, cy)):
			w += 1
		var d := 1
		var can_expand := true
		while can_expand:
			for i in range(w):
				if not cell_set.has(Vector2i(cx + i, cy + d)) or visited.has(Vector2i(cx + i, cy + d)):
					can_expand = false
					break
			if can_expand: d += 1
		for iz in range(d):
			for ix in range(w):
				visited[Vector2i(cx + ix, cy + iz)] = true
		result.append({"x": cx, "y": cy, "w": w, "d": d})
	return result
