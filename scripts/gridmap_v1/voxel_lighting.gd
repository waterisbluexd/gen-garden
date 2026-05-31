class_name VoxelLighting
extends RefCounted

const CHUNK_SIZE: int = 32
const CHUNK_LAYER: int = 32 * 32
const CHUNK_VOLUME: int = 32 * 32 * 32

# Optimization 3: flat array heightmap — O(1) vs O(log n) Dictionary
const HM_WIDTH: int = 256
const HM_NONE: int = -1

var light_chunks: Dictionary
var chunks: Dictionary
var _heightmap_flat: PackedInt32Array  # replaces global_heightmap Dictionary
var block_registry: BlockRegistry

func _init(_light_chunks: Dictionary, _chunks: Dictionary, _heightmap: PackedInt32Array, _registry: BlockRegistry) -> void:
	light_chunks = _light_chunks
	chunks = _chunks
	_heightmap_flat = _heightmap
	block_registry = _registry

# --- Heightmap access ---

func _hm_get(x: int, z: int) -> int:
	if x < 0 or x >= HM_WIDTH or z < 0 or z >= HM_WIDTH: return HM_NONE
	return _heightmap_flat[x + z * HM_WIDTH]

# --- Utility ---

func _ensure_light_chunk(cc: Vector3i) -> PackedByteArray:
	if light_chunks.has(cc): return light_chunks[cc]
	var lc := PackedByteArray()
	lc.resize(CHUNK_VOLUME)
	light_chunks[cc] = lc
	return lc

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

func _is_opaque(block_id: int) -> bool:
	if block_id == 0: return false
	if block_registry == null: return true
	var b = block_registry.get_block(block_id)
	if b and "is_transparent" in b:
		return not b.is_transparent
	return true

# --- Sunlight API ---

func get_sunlight(pos: Vector3i) -> int:
	var cc := get_chunk_coord(pos)
	if not light_chunks.has(cc):
		# Optimization 3: flat array O(1) lookup instead of Dictionary.get()
		var h: int = _hm_get(pos.x, pos.z)
		if h == HM_NONE: return 0
		return 15 if pos.y > h else 0
	var lx := posmod(pos.x, CHUNK_SIZE)
	var ly := posmod(pos.y, CHUNK_SIZE)
	var lz := posmod(pos.z, CHUNK_SIZE)
	return light_chunks[cc][lx + (ly * CHUNK_SIZE) + (lz * CHUNK_LAYER)] & 0x0F

func set_sunlight(pos: Vector3i, val: int) -> void:
	var cc := get_chunk_coord(pos)
	var lc := _ensure_light_chunk(cc)
	var lx := posmod(pos.x, CHUNK_SIZE)
	var ly := posmod(pos.y, CHUNK_SIZE)
	var lz := posmod(pos.z, CHUNK_SIZE)
	var idx := lx + (ly * CHUNK_SIZE) + (lz * CHUNK_LAYER)
	lc[idx] = (lc[idx] & 0xF0) | (val & 0x0F)

# Returns affected chunk coords dict — caller queues mesh rebuilds
func update_sunlight_propagation(queue: Array) -> Dictionary:
	var dirs := [Vector3i.RIGHT, Vector3i.LEFT, Vector3i.UP, Vector3i.DOWN, Vector3i.FORWARD, Vector3i.BACK]
	var affected_chunks := {}
	# Optimization 4: ring buffer — head/tail pointers, no pop_front() O(n) shifts
	var head := 0
	while head < queue.size():
		var pos: Vector3i = queue[head]
		head += 1
		var curr_light := get_sunlight(pos)
		for d in dirs:
			var n: Vector3i = pos + d
			if _is_opaque(get_global_voxel(n)): continue
			var target_light := curr_light - 1
			if d == Vector3i.DOWN and curr_light == 15:
				target_light = 15
			if get_sunlight(n) < target_light:
				set_sunlight(n, target_light)
				queue.append(n)
				affected_chunks[get_chunk_coord(n)] = true
	return affected_chunks

func remove_sunlight(pos: Vector3i) -> Dictionary:
	var dirs := [Vector3i.RIGHT, Vector3i.LEFT, Vector3i.UP, Vector3i.DOWN, Vector3i.FORWARD, Vector3i.BACK]
	# Optimization 4: ring buffers for both removal and propagation queues
	var rem_queue := [{"pos": pos, "val": get_sunlight(pos)}]
	var rem_head := 0
	var prop_queue := []
	var affected_chunks := {}

	set_sunlight(pos, 0)
	affected_chunks[get_chunk_coord(pos)] = true

	while rem_head < rem_queue.size():
		var curr = rem_queue[rem_head]
		rem_head += 1
		var cp: Vector3i = curr.pos
		var cv: int = curr.val
		for d in dirs:
			var n: Vector3i = cp + d
			var nv := get_sunlight(n)
			if nv != 0 and (nv < cv or (d == Vector3i.DOWN and cv == 15)):
				set_sunlight(n, 0)
				rem_queue.append({"pos": n, "val": nv})
				affected_chunks[get_chunk_coord(n)] = true
			elif nv >= cv:
				prop_queue.append(n)

	var prop_affected := update_sunlight_propagation(prop_queue)
	for cc in prop_affected:
		affected_chunks[cc] = true
	return affected_chunks

# --- Blocklight API ---

func get_blocklight(pos: Vector3i) -> int:
	var cc := get_chunk_coord(pos)
	if not light_chunks.has(cc): return 0
	var lx := posmod(pos.x, CHUNK_SIZE)
	var ly := posmod(pos.y, CHUNK_SIZE)
	var lz := posmod(pos.z, CHUNK_SIZE)
	return (light_chunks[cc][lx + (ly * CHUNK_SIZE) + (lz * CHUNK_LAYER)] >> 4) & 0x0F

func set_blocklight(pos: Vector3i, val: int) -> void:
	var cc := get_chunk_coord(pos)
	var lc := _ensure_light_chunk(cc)
	var lx := posmod(pos.x, CHUNK_SIZE)
	var ly := posmod(pos.y, CHUNK_SIZE)
	var lz := posmod(pos.z, CHUNK_SIZE)
	var idx := lx + (ly * CHUNK_SIZE) + (lz * CHUNK_LAYER)
	lc[idx] = (lc[idx] & 0x0F) | ((val & 0x0F) << 4)

# Optimization 4: ring buffer — no pop_front() shifts
func update_blocklight_propagation(queue: Array) -> Dictionary:
	var dirs := [Vector3i.RIGHT, Vector3i.LEFT, Vector3i.UP, Vector3i.DOWN, Vector3i.FORWARD, Vector3i.BACK]
	var affected_chunks := {}
	var head := 0
	while head < queue.size():
		var pos: Vector3i = queue[head]
		head += 1
		var curr_light := get_blocklight(pos)
		for d in dirs:
			var n: Vector3i = pos + d
			if _is_opaque(get_global_voxel(n)): continue
			if get_blocklight(n) < curr_light - 1:
				set_blocklight(n, curr_light - 1)
				queue.append(n)
				affected_chunks[get_chunk_coord(n)] = true
	return affected_chunks

func remove_blocklight(pos: Vector3i) -> Dictionary:
	var dirs := [Vector3i.RIGHT, Vector3i.LEFT, Vector3i.UP, Vector3i.DOWN, Vector3i.FORWARD, Vector3i.BACK]
	var rem_queue := [{"pos": pos, "val": get_blocklight(pos)}]
	var rem_head := 0
	var prop_queue := []
	var affected_chunks := {}

	set_blocklight(pos, 0)
	affected_chunks[get_chunk_coord(pos)] = true

	while rem_head < rem_queue.size():
		var curr = rem_queue[rem_head]
		rem_head += 1
		var cp: Vector3i = curr.pos
		var cv: int = curr.val
		for d in dirs:
			var n: Vector3i = cp + d
			var nv := get_blocklight(n)
			if nv != 0 and nv < cv:
				set_blocklight(n, 0)
				rem_queue.append({"pos": n, "val": nv})
				affected_chunks[get_chunk_coord(n)] = true
			elif nv >= cv:
				prop_queue.append(n)

	var prop_affected := update_blocklight_propagation(prop_queue)
	for cc in prop_affected:
		affected_chunks[cc] = true
	return affected_chunks
