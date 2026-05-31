extends Node3D
class_name Grid

@export var atlas_texture: Texture2D
@export var block_registry: BlockRegistry

@export var atlas_shader_opaque: ShaderMaterial      
@export var atlas_shader_transparent: ShaderMaterial 

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

# State Dictionaries
var chunks: Dictionary = {}
var light_chunks: Dictionary = {}
var chunk_nodes: Dictionary = {}
var global_heightmap: Dictionary = {}

# Systems & Threading
var rebuild_queue: Dictionary = {}
var chunks_processing: Dictionary = {}
@export var chunks_per_frame_budget: int = 2

var lighting: VoxelLighting

# Mutex guards chunks, light_chunks, global_heightmap.
# Must be locked by ANY thread reading/writing those dicts
# (BFS worker thread AND snapshot in _dispatch_chunk_thread).
var _light_mutex := Mutex.new()

var _buffer_pool: Array[MeshBuffers] = []
var _pool_mutex := Mutex.new()

var camera: Node3D
var active_block_id: int = 1

func _ready() -> void:
	get_viewport().scaling_3d_scale = 0.75
	get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	
	if has_node("StaticBody3D"):
		$StaticBody3D.queue_free()
		
	# No rebuild_queue passed — lighting is now side-effect free
	lighting = VoxelLighting.new(light_chunks, chunks, global_heightmap, block_registry)
	
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

# --- Voxel Data Access ---

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

# --- State Modifications ---

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
			
			global_heightmap[Vector2i(x, z)] = base_y_level
			affected[cc] = true
			
	var sun_init_queue: Array[Vector3i] = []
	for z in range(base_depth):
		for x in range(base_width):
			var h = global_heightmap.get(Vector2i(x, z), -1)
			for y in range(base_y_level + CHUNK_SIZE, base_y_level - 1, -1):
				var g_pos := Vector3i(x, y, z)
				if y > h:
					lighting.set_sunlight(g_pos, 15)
					if y == h + 1: sun_init_queue.append(g_pos)
				else:
					lighting.set_sunlight(g_pos, 0)
					var bid := get_global_voxel(g_pos)
					var emiss := 0
					if bid != 0:
						var block = block_registry.get_block(bid)
						if block and "emission" in block:
							emiss = block.emission
					if emiss > 0:
						lighting.set_blocklight(g_pos, emiss)
						
	if not sun_init_queue.is_empty():
		lighting.update_sunlight_propagation(sun_init_queue)
	for c in affected: rebuild_queue[c] = true

func set_cell(x: int, y: int, z: int, block_id: int) -> void:
	var global_pos := Vector3i(x, y, z)
	var cc := get_chunk_coord(global_pos)

	# Write voxel data on main thread (fast, no BFS)
	_light_mutex.lock()
	if not chunks.has(cc):
		var c := PackedByteArray()
		c.resize(CHUNK_VOLUME)
		chunks[cc] = c
	chunks[cc][posmod(x, CHUNK_SIZE) + (posmod(y, CHUNK_SIZE) * CHUNK_SIZE) + (posmod(z, CHUNK_SIZE) * CHUNK_LAYER)] = block_id
	
	var h_key := Vector2i(x, z)
	if block_id != 0:
		if y > global_heightmap.get(h_key, -1):
			global_heightmap[h_key] = y
	else:
		if y == global_heightmap.get(h_key, -1):
			_recalc_heightmap_column_locked(x, z, y)

	# Capture lighting state needed for BFS before releasing lock
	var is_opaque := lighting._is_opaque(block_id)
	var sa_above := lighting.get_sunlight(global_pos + Vector3i.UP)
	var emiss := 0
	if not is_opaque and block_id != 0:
		var block = block_registry.get_block(block_id)
		if block and "emission" in block:
			emiss = block.emission
	_light_mutex.unlock()

	# Queue BFS on worker thread — main thread is free immediately
	_queue_block_neighbors(global_pos)  # queue mesh rebuild of neighbors now
	WorkerThreadPool.add_task(func():
		_light_mutex.lock()
		var affected := {}
		if is_opaque:
			var a1 := lighting.remove_sunlight(global_pos)
			var a2 := lighting.remove_blocklight(global_pos)
			for c in a1: affected[c] = true
			for c in a2: affected[c] = true
		else:
			if emiss > 0:
				lighting.set_blocklight(global_pos, emiss)
				var a := lighting.update_blocklight_propagation([global_pos])
				for c in a: affected[c] = true
			var sun_val := 15 if sa_above == 15 else clampi(sa_above - 1, 0, 15)
			lighting.set_sunlight(global_pos, sun_val)
			var a := lighting.update_sunlight_propagation([global_pos])
			for c in a: affected[c] = true
		_light_mutex.unlock()
		call_deferred("_apply_light_affected", affected)
	)

func remove_cell(x: int, y: int, z: int) -> void:
	var global_pos := Vector3i(x, y, z)
	var cc := get_chunk_coord(global_pos)

	_light_mutex.lock()
	if not chunks.has(cc):
		_light_mutex.unlock()
		return
	chunks[cc][posmod(x, CHUNK_SIZE) + (posmod(y, CHUNK_SIZE) * CHUNK_SIZE) + (posmod(z, CHUNK_SIZE) * CHUNK_LAYER)] = 0
	
	var h_key := Vector2i(x, z)
	if y == global_heightmap.get(h_key, -1):
		_recalc_heightmap_column_locked(x, z, y)

	# Sample neighbor light before releasing for BFS seed values
	var dirs := [Vector3i.UP, Vector3i.DOWN, Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]
	var max_sun := 0
	var max_blk := 0
	for d in dirs:
		var n: Vector3i = global_pos + d
		var s := lighting.get_sunlight(n)
		max_sun = 15 if (d == Vector3i.UP and s == 15) else max(max_sun, s - 1)
		max_blk = max(max_blk, lighting.get_blocklight(n) - 1)
	_light_mutex.unlock()

	_queue_block_neighbors(global_pos)
	WorkerThreadPool.add_task(func():
		_light_mutex.lock()
		var affected := {}
		if max_sun > 0:
			lighting.set_sunlight(global_pos, max_sun)
			var a := lighting.update_sunlight_propagation([global_pos])
			for c in a: affected[c] = true
		if max_blk > 0:
			lighting.set_blocklight(global_pos, max_blk)
			var a := lighting.update_blocklight_propagation([global_pos])
			for c in a: affected[c] = true
		_light_mutex.unlock()
		call_deferred("_apply_light_affected", affected)
	)

# Called on main thread after BFS completes — safe to write rebuild_queue
func _apply_light_affected(affected: Dictionary) -> void:
	for cc in affected:
		rebuild_queue[cc] = true

# Must be called with _light_mutex already held
func _recalc_heightmap_column_locked(x: int, z: int, start_y: int) -> void:
	var h_key := Vector2i(x, z)
	for y in range(start_y, -1, -1):
		var cc := get_chunk_coord(Vector3i(x, y, z))
		if not chunks.has(cc): continue
		var lx: int = posmod(x, CHUNK_SIZE)
		var ly: int = posmod(y, CHUNK_SIZE)
		var lz: int = posmod(z, CHUNK_SIZE)
		if chunks[cc][lx + (ly * CHUNK_SIZE) + (lz * CHUNK_LAYER)] != 0:
			global_heightmap[h_key] = y
			return
	global_heightmap[h_key] = -1

func _queue_block_neighbors(global_pos: Vector3i) -> void:
	var cc := get_chunk_coord(global_pos)
	rebuild_queue[cc] = true
	var lx: int = posmod(global_pos.x, CHUNK_SIZE)
	var ly: int = posmod(global_pos.y, CHUNK_SIZE)
	var lz: int = posmod(global_pos.z, CHUNK_SIZE)
	
	if lx == 0:              rebuild_queue[cc + Vector3i(-1, 0, 0)] = true
	if lx == CHUNK_SIZE_M1: rebuild_queue[cc + Vector3i(1, 0, 0)]  = true
	if ly == 0:              rebuild_queue[cc + Vector3i(0, -1, 0)] = true
	if ly == CHUNK_SIZE_M1: rebuild_queue[cc + Vector3i(0, 1, 0)]  = true
	if lz == 0:              rebuild_queue[cc + Vector3i(0, 0, -1)] = true
	if lz == CHUNK_SIZE_M1: rebuild_queue[cc + Vector3i(0, 0, 1)]  = true

# --- Inputs & Raycasting ---

func place_block_from_mouse(block_id: int) -> void:
	if camera == null: return
	var ray: Dictionary = camera.raycast_from_screen(get_viewport().get_mouse_position())
	var result: Dictionary = VoxelRaycast.dda_raycast(ray["origin"], ray["direction"], 500.0, get_global_voxel)
	if not result["hit"]: return
	var target: Vector3i = result["position"] + result["normal"]
	set_cell(target.x, target.y, target.z, block_id)

func remove_block_from_mouse() -> void:
	if camera == null: return
	var ray: Dictionary = camera.raycast_from_screen(get_viewport().get_mouse_position())
	var result: Dictionary = VoxelRaycast.dda_raycast(ray["origin"], ray["direction"], 500.0, get_global_voxel)
	if not result["hit"]: return
	var hit: Vector3i = result["position"]
	remove_cell(hit.x, hit.y, hit.z)

# --- Threading & Meshing Orchestration ---

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
	# Snapshot under lock so BFS worker can't write while we read
	_light_mutex.lock()
	var snap: Dictionary = {}
	var light_snap: Dictionary = {}
	for dir in [Vector3i(0,0,0), Vector3i(1,0,0), Vector3i(-1,0,0),
				Vector3i(0,1,0), Vector3i(0,-1,0), Vector3i(0,0,1), Vector3i(0,0,-1)]:
		var nc: Vector3i = cc + dir
		if chunks.has(nc): snap[nc] = chunks[nc].duplicate()
		if light_chunks.has(nc): light_snap[nc] = light_chunks[nc].duplicate()
		
	var h_snap := {}
	var margin := 5 
	var start_x := cc.x * CHUNK_SIZE - margin
	var end_x := (cc.x + 1) * CHUNK_SIZE + margin
	var start_z := cc.z * CHUNK_SIZE - margin
	var end_z := (cc.z + 1) * CHUNK_SIZE + margin
	for cz in range(start_z, end_z):
		for cx in range(start_x, end_x):
			var h_key := Vector2i(cx, cz)
			if global_heightmap.has(h_key):
				h_snap[h_key] = global_heightmap[h_key]
	_light_mutex.unlock()
	
	var bufs := _get_pooled_buffers()
	
	WorkerThreadPool.add_task(func():
		var result := VoxelMesher.build_chunk_mesh(cc, snap, light_snap, h_snap, block_registry, bufs[0], bufs[1], atlas_shader_opaque, atlas_shader_transparent)
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
	
	_recycle_buffers(result.opaque_buf, result.trans_buf)
	
	if result.opaque_mesh == null and result.transparent_mesh == null: return
	
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
	light_chunks.clear()
