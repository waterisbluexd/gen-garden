extends Node3D
class_name Grid

@export var atlas_texture: Texture2D
@export var atlas_shader: ShaderMaterial
@export var block_registry: BlockRegistry

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

var chunks: Dictionary = {}
var chunk_nodes: Dictionary = {}

var rebuild_queue: Dictionary = {}
var chunks_processing: Dictionary = {}
@export var chunks_per_frame_budget: int = 2

var camera: Node3D
var active_block_id: int = 1

func _ready() -> void:
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
	if not chunks.has(cc):
		return 0
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
	_queue_block_neighbors(global_pos)

func remove_cell(x: int, y: int, z: int) -> void:
	var global_pos := Vector3i(x, y, z)
	var cc := get_chunk_coord(global_pos)
	if not chunks.has(cc): return
	chunks[cc][posmod(x, CHUNK_SIZE) + (posmod(y, CHUNK_SIZE) * CHUNK_SIZE) + (posmod(z, CHUNK_SIZE) * CHUNK_LAYER)] = 0
	_queue_block_neighbors(global_pos)

func _queue_block_neighbors(global_pos: Vector3i) -> void:
	var cc := get_chunk_coord(global_pos)
	rebuild_queue[cc] = true
	var lx: int = posmod(global_pos.x, CHUNK_SIZE)
	var ly: int = posmod(global_pos.y, CHUNK_SIZE)
	var lz: int = posmod(global_pos.z, CHUNK_SIZE)
	if lx == 0: rebuild_queue[cc + Vector3i(-1, 0, 0)] = true
	if lx == CHUNK_SIZE_M1: rebuild_queue[cc + Vector3i(1, 0, 0)] = true
	if ly == 0: rebuild_queue[cc + Vector3i(0, -1, 0)] = true
	if ly == CHUNK_SIZE_M1: rebuild_queue[cc + Vector3i(0, 1, 0)] = true
	if lz == 0: rebuild_queue[cc + Vector3i(0, 0, -1)] = true
	if lz == CHUNK_SIZE_M1: rebuild_queue[cc + Vector3i(0, 0, 1)] = true

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

func _dispatch_chunk_thread(cc: Vector3i) -> void:
	var snap: Dictionary = {}
	for dir in [Vector3i(0,0,0), Vector3i(1,0,0), Vector3i(-1,0,0), Vector3i(0,1,0), Vector3i(0,-1,0), Vector3i(0,0,1), Vector3i(0,0,-1)]:
		var nc: Vector3i = cc + dir
		if chunks.has(nc): snap[nc] = chunks[nc].duplicate()
	WorkerThreadPool.add_task(func():
		var result := _build_chunk_mesh(cc, snap)
		call_deferred("_apply_mesh", cc, result)
	)

func _apply_mesh(cc: Vector3i, result: Dictionary) -> void:
	chunks_processing.erase(cc)
	if result.mesh == null:
		if chunk_nodes.has(cc):
			chunk_nodes[cc].mi.mesh = null
			_clear_collision(chunk_nodes[cc].body)
		return
	_ensure_chunk_node(cc)
	var node: Dictionary = chunk_nodes[cc]
	node.mi.mesh = result.mesh
	_clear_collision(node.body)
	for box in result.boxes:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = box.size
		cs.position = box.pos
		cs.shape = bs
		node.body.add_child(cs)

func _clear_collision(body: StaticBody3D) -> void:
	for c in body.get_children(): c.queue_free()

func _ensure_chunk_node(cc: Vector3i) -> void:
	if chunk_nodes.has(cc): return
	var node := Node3D.new()
	add_child(node)
	node.global_position = Vector3(cc * CHUNK_SIZE)
	var mi := MeshInstance3D.new()
	node.add_child(mi)
	var body := StaticBody3D.new()
	node.add_child(body)
	chunk_nodes[cc] = {"node": node, "mi": mi, "body": body}

func _build_chunk_mesh(cc: Vector3i, snap: Dictionary) -> Dictionary:
	var output := {"mesh": null, "boxes": []}
	if not snap.has(cc): return output
	var data: PackedByteArray = snap[cc]

	# FIX 1: Block cache + empty check in one pass, no second loop
	var block_cache: Dictionary = {}
	var empty := true
	for i in range(CHUNK_VOLUME):
		var id: int = data[i]
		if id != 0:
			empty = false
			if not block_cache.has(id):
				block_cache[id] = block_registry.get_block(id)
	if empty: return output

	# FIX 2: Pre-compute all 6 neighbor chunk coords ONCE before the hot loop
	# Avoids allocating new Vector3i objects on every boundary voxel check
	var nc_top   := Vector3i(cc.x, cc.y + 1, cc.z)
	var nc_bot   := Vector3i(cc.x, cc.y - 1, cc.z)
	var nc_front := Vector3i(cc.x, cc.y, cc.z + 1)
	var nc_back  := Vector3i(cc.x, cc.y, cc.z - 1)
	var nc_right := Vector3i(cc.x + 1, cc.y, cc.z)
	var nc_left  := Vector3i(cc.x - 1, cc.y, cc.z)

	# FIX 3: Pre-fetch neighbor data arrays once (null if chunk doesn't exist)
	# Avoids repeated Dictionary lookups inside the hot loop
	var nd_top:   PackedByteArray = snap[nc_top]   if snap.has(nc_top)   else PackedByteArray()
	var nd_bot:   PackedByteArray = snap[nc_bot]   if snap.has(nc_bot)   else PackedByteArray()
	var nd_front: PackedByteArray = snap[nc_front] if snap.has(nc_front) else PackedByteArray()
	var nd_back:  PackedByteArray = snap[nc_back]  if snap.has(nc_back)  else PackedByteArray()
	var nd_right: PackedByteArray = snap[nc_right] if snap.has(nc_right) else PackedByteArray()
	var nd_left:  PackedByteArray = snap[nc_left]  if snap.has(nc_left)  else PackedByteArray()

	# Empty PackedByteArray means neighbor chunk is air — all boundary faces exposed
	var has_top:   bool = nd_top.size()   > 0
	var has_bot:   bool = nd_bot.size()   > 0
	var has_front: bool = nd_front.size() > 0
	var has_back:  bool = nd_back.size()  > 0
	var has_right: bool = nd_right.size() > 0
	var has_left:  bool = nd_left.size()  > 0

	var verts   := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs     := PackedVector2Array()
	var uvs2    := PackedVector2Array()
	var colors  := PackedColorArray()
	var indices := PackedInt32Array()
	var vert_idx: int = 0
	var collision_boxes: Array = []

	var top_f:   Dictionary = {}
	var bot_f:   Dictionary = {}
	var front_f: Dictionary = {}
	var back_f:  Dictionary = {}
	var right_f: Dictionary = {}
	var left_f:  Dictionary = {}

	var greedy_cell_set: Dictionary = {}
	var greedy_visited:  Dictionary = {}

	# ── Hot loop — neighbor arrays accessed directly, no Dictionary hits ──
	for ly in range(CHUNK_SIZE):
		var ly_stride:  int = ly * CHUNK_SIZE
		var ly1_stride: int = (ly + 1) * CHUNK_SIZE
		var ly_1_stride: int = (ly - 1) * CHUNK_SIZE
		for lz in range(CHUNK_SIZE):
			var lz_layer:  int = lz * CHUNK_LAYER
			var lz1_layer: int = (lz + 1) * CHUNK_LAYER
			var lz_1_layer: int = (lz - 1) * CHUNK_LAYER
			for lx in range(CHUNK_SIZE):
				var idx: int = lx + ly_stride + lz_layer
				var id: int = data[idx]
				if id == 0: continue

				var block: BlockType = block_cache[id]
				var bh: float = block.height

				# ── TOP ──
				var top_exposed: bool
				if ly < CHUNK_SIZE_M1:
					top_exposed = data[lx + ly1_stride + lz_layer] == 0 or bh < 1.0
				else:
					top_exposed = (not has_top) or nd_top[lx + lz_layer] == 0 or bh < 1.0
				if top_exposed:
					var k := Vector2i(ly, id)
					if not top_f.has(k): top_f[k] = []
					top_f[k].append(Vector2i(lx, lz))

				# ── BOTTOM ──
				var bot_exposed: bool
				if ly > 0:
					bot_exposed = data[lx + ly_1_stride + lz_layer] == 0
				else:
					bot_exposed = (not has_bot) or nd_bot[lx + (CHUNK_SIZE_M1 * CHUNK_SIZE) + lz_layer] == 0
				if bot_exposed:
					var k := Vector2i(ly, id)
					if not bot_f.has(k): bot_f[k] = []
					bot_f[k].append(Vector2i(lx, lz))

				# FRONT
				var front_nid: int = data[lx + ly_stride + lz1_layer] if lz < CHUNK_SIZE_M1 else (nd_front[lx + ly_stride] if has_front else 0)
				if front_nid == 0 or (block_cache.has(front_nid) and block_cache[front_nid].height != bh):
					var k := Vector2i(lz, id)
					if not front_f.has(k): front_f[k] = []
					front_f[k].append(Vector2i(lx, ly))
				
				# BACK
				var back_nid: int = data[lx + ly_stride + lz_1_layer] if lz > 0 else (nd_back[lx + ly_stride + (CHUNK_SIZE_M1 * CHUNK_LAYER)] if has_back else 0)
				if back_nid == 0 or (block_cache.has(back_nid) and block_cache[back_nid].height != bh):
					var k := Vector2i(lz, id)
					if not back_f.has(k): back_f[k] = []
					back_f[k].append(Vector2i(lx, ly))
				
				# RIGHT
				var right_nid: int = data[lx + 1 + ly_stride + lz_layer] if lx < CHUNK_SIZE_M1 else (nd_right[ly_stride + lz_layer] if has_right else 0)
				if right_nid == 0 or (block_cache.has(right_nid) and block_cache[right_nid].height != bh):
					var k := Vector2i(lx, id)
					if not right_f.has(k): right_f[k] = []
					right_f[k].append(Vector2i(lz, ly))
				
				# LEFT
				var left_nid: int = data[lx - 1 + ly_stride + lz_layer] if lx > 0 else (nd_left[CHUNK_SIZE_M1 + ly_stride + lz_layer] if has_left else 0)
				if left_nid == 0 or (block_cache.has(left_nid) and block_cache[left_nid].height != bh):
					var k := Vector2i(lx, id)
					if not left_f.has(k): left_f[k] = []
					left_f[k].append(Vector2i(lz, ly))

	# ── Greedy mesh + emit ──
	for key in top_f:
		var block: BlockType = block_cache[key.y]
		var y_base: float = float(key.x) + block.height
		for q in _greedy(top_f[key], greedy_cell_set, greedy_visited):
			vert_idx = _emit_quad(verts, normals, uvs, uvs2, colors, indices, vert_idx,
				Vector3(float(q.x), y_base, float(q.y)),
				Vector3(float(q.x + q.w), y_base, float(q.y)),
				Vector3(float(q.x + q.w), y_base, float(q.y + q.d)),
				Vector3(float(q.x), y_base, float(q.y + q.d)),
				Vector3(0, 1, 0), block.uv_top, q.w, q.d, block.color_top)
			if collision_boxes.size() < MAX_COLLISION_BOXES:
				collision_boxes.append({
					"pos": Vector3(float(q.x) + float(q.w) * 0.5, float(key.x) + 0.5, float(q.y) + float(q.d) * 0.5),
					"size": Vector3(float(q.w), 1.0, float(q.d))
				})

	for key in bot_f:
		var block: BlockType = block_cache[key.y]
		var y_base: float = float(key.x)
		for q in _greedy(bot_f[key], greedy_cell_set, greedy_visited):
			vert_idx = _emit_quad(verts, normals, uvs, uvs2, colors, indices, vert_idx,
				Vector3(float(q.x + q.w), y_base, float(q.y)),
				Vector3(float(q.x), y_base, float(q.y)),
				Vector3(float(q.x), y_base, float(q.y + q.d)),
				Vector3(float(q.x + q.w), y_base, float(q.y + q.d)),
				Vector3(0, -1, 0), block.uv_bottom, q.w, q.d, block.color_bottom)

	for key in front_f:
		var block: BlockType = block_cache[key.y]
		var z1f := float(key.x + 1)
		for q in _greedy(front_f[key], greedy_cell_set, greedy_visited):
			vert_idx = _emit_quad(verts, normals, uvs, uvs2, colors, indices, vert_idx,
				Vector3(float(q.x + q.w), float(q.y), z1f),
				Vector3(float(q.x), float(q.y), z1f),
				Vector3(float(q.x), float(q.y) + float(q.d) * block.height, z1f),
				Vector3(float(q.x + q.w), float(q.y) + float(q.d) * block.height, z1f),
				Vector3(0, 0, 1), block.uv_side_front, q.w, q.d, block.color_front)

	for key in back_f:
		var block: BlockType = block_cache[key.y]
		var z0b := float(key.x)
		for q in _greedy(back_f[key], greedy_cell_set, greedy_visited):
			vert_idx = _emit_quad(verts, normals, uvs, uvs2, colors, indices, vert_idx,
				Vector3(float(q.x), float(q.y), z0b),
				Vector3(float(q.x + q.w), float(q.y), z0b),
				Vector3(float(q.x + q.w), float(q.y) + float(q.d) * block.height, z0b),
				Vector3(float(q.x), float(q.y) + float(q.d) * block.height, z0b),
				Vector3(0, 0, -1), block.uv_side_back, q.w, q.d, block.color_back)

	for key in right_f:
		var block: BlockType = block_cache[key.y]
		var x1r := float(key.x + 1)
		for q in _greedy(right_f[key], greedy_cell_set, greedy_visited):
			vert_idx = _emit_quad(verts, normals, uvs, uvs2, colors, indices, vert_idx,
				Vector3(x1r, float(q.y), float(q.x)),
				Vector3(x1r, float(q.y), float(q.x + q.w)),
				Vector3(x1r, float(q.y) + float(q.d) * block.height, float(q.x + q.w)),
				Vector3(x1r, float(q.y) + float(q.d) * block.height, float(q.x)),
				Vector3(1, 0, 0), block.uv_side_right, q.w, q.d, block.color_right)

	for key in left_f:
		var block: BlockType = block_cache[key.y]
		var x0l := float(key.x)
		for q in _greedy(left_f[key], greedy_cell_set, greedy_visited):
			vert_idx = _emit_quad(verts, normals, uvs, uvs2, colors, indices, vert_idx,
				Vector3(x0l, float(q.y), float(q.x + q.w)),
				Vector3(x0l, float(q.y), float(q.x)),
				Vector3(x0l, float(q.y) + float(q.d) * block.height, float(q.x)),
				Vector3(x0l, float(q.y) + float(q.d) * block.height, float(q.x + q.w)),
				Vector3(-1, 0, 0), block.uv_side_left, q.w, q.d, block.color_left)

	if vert_idx == 0: return output

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]  = verts
	arrays[Mesh.ARRAY_NORMAL]  = normals
	arrays[Mesh.ARRAY_TEX_UV]  = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uvs2
	arrays[Mesh.ARRAY_COLOR]   = colors
	arrays[Mesh.ARRAY_INDEX]   = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, atlas_shader)
	output.mesh = mesh
	output.boxes = collision_boxes
	return output

func _emit_quad(verts, normals, uvs, uvs2, colors, indices, vi, v0, v1, v2, v3, normal, tile_index, u_tiles, v_tiles, col) -> int:
	verts.append(v0); verts.append(v1); verts.append(v2); verts.append(v3)
	normals.append(normal); normals.append(normal); normals.append(normal); normals.append(normal)
	uvs.append(Vector2(0, v_tiles)); uvs.append(Vector2(u_tiles, v_tiles)); uvs.append(Vector2(u_tiles, 0)); uvs.append(Vector2(0, 0))
	var ti := Vector2(float(tile_index), 0.0)
	uvs2.append(ti); uvs2.append(ti); uvs2.append(ti); uvs2.append(ti)
	colors.append(col); colors.append(col); colors.append(col); colors.append(col)
	indices.append(vi); indices.append(vi+1); indices.append(vi+2); indices.append(vi); indices.append(vi+2); indices.append(vi+3)
	return vi + 4

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
