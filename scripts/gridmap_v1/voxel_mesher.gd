class_name VoxelMesher
extends RefCounted

const CHUNK_SIZE: int = 32
const CHUNK_SIZE_M1: int = 31
const CHUNK_LAYER: int = 32 * 32
const CHUNK_VOLUME: int = 32 * 32 * 32
const MAX_COLLISION_BOXES: int = 64
const AO_VALUES: Array[float] = [1.0, 0.8, 0.6, 0.4]

static func build_chunk_mesh(cc: Vector3i, snap: Dictionary, light_snap: Dictionary, h_snap: Dictionary, block_registry: BlockRegistry, opaque_buf: MeshBuffers, trans_buf: MeshBuffers, atlas_shader_opaque: Material, atlas_shader_transparent: Material) -> Dictionary:
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

	var gl_origin := cc * CHUNK_SIZE
	var get_light_value = func(lx: int, ly: int, lz: int) -> int:
		var gx := gl_origin.x + lx
		var gy := gl_origin.y + ly
		var gz := gl_origin.z + lz
		var t_cc := Vector3i(floori(float(gx)/CHUNK_SIZE), floori(float(gy)/CHUNK_SIZE), floori(float(gz)/CHUNK_SIZE))
		if not light_snap.has(t_cc):
			return 15 if gy > h_snap.get(Vector2i(gx, gz), -1) else 0
		var t_lx := posmod(gx, CHUNK_SIZE)
		var t_ly := posmod(gy, CHUNK_SIZE)
		var t_lz := posmod(gz, CHUNK_SIZE)
		var raw: int = light_snap[t_cc][t_lx + (t_ly * CHUNK_SIZE) + (t_lz * CHUNK_LAYER)]
		return max(raw & 0x0F, (raw >> 4) & 0x0F)

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

	var top_f_o := {}; var top_f_t := {}
	var bot_f_o := {}; var bot_f_t := {}
	var front_f_o := {}; var front_f_t := {}
	var back_f_o := {}; var back_f_t := {}
	var right_f_o := {}; var right_f_t := {}
	var left_f_o := {}; var left_f_t := {}

	var greedy_cell_set: Dictionary = {}
	var greedy_visited:  Dictionary = {}

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

				var block = block_cache[id]
				var is_trans: bool = block.is_transparent if "is_transparent" in block else false
				var bh: float = float(block.height)

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
					var l_val : int = get_light_value.call(lx, ly + 1, lz)
					var k := Vector3i(ly, id, packed_ao | (l_val << 8))
					var t_map := top_f_t if is_trans else top_f_o
					if not t_map.has(k): t_map[k] = []
					t_map[k].append(Vector2i(lx, lz))

				var bot_exposed: bool
				if ly > 0:
					bot_exposed = data[lx + ly_1_stride + lz_layer] == 0
				else:
					bot_exposed = (not has_bot) or nd_bot[lx + (CHUNK_SIZE_M1 * CHUNK_SIZE) + lz_layer] == 0
				if bot_exposed:
					var l_val : int = get_light_value.call(lx, ly - 1, lz)
					var k := Vector3i(ly, id, l_val)
					var t_map := bot_f_t if is_trans else bot_f_o
					if not t_map.has(k): t_map[k] = []
					t_map[k].append(Vector2i(lx, lz))

				var front_nid: int = data[lx + ly_stride + lz1_layer] if lz < CHUNK_SIZE_M1 else (nd_front[lx + ly_stride] if has_front else 0)
				if front_nid == 0 or (block_cache.has(front_nid) and float(block_cache[front_nid].height) != bh):
					var l_val: int = get_light_value.call(lx, ly, lz + 1)
					var k := Vector3i(lz, id, l_val)
					var t_map := front_f_t if is_trans else front_f_o
					if not t_map.has(k): t_map[k] = []
					t_map[k].append(Vector2i(lx, ly))

				var back_nid: int = data[lx + ly_stride + lz_1_layer] if lz > 0 else (nd_back[lx + ly_stride + (CHUNK_SIZE_M1 * CHUNK_LAYER)] if has_back else 0)
				if back_nid == 0 or (block_cache.has(back_nid) and float(block_cache[back_nid].height) != bh):
					var l_val : int = get_light_value.call(lx, ly, lz - 1)
					var k := Vector3i(lz, id, l_val)
					var t_map := back_f_t if is_trans else back_f_o
					if not t_map.has(k): t_map[k] = []
					t_map[k].append(Vector2i(lx, ly))

				var right_nid: int = data[lx + 1 + ly_stride + lz_layer] if lx < CHUNK_SIZE_M1 else (nd_right[ly_stride + lz_layer] if has_right else 0)
				if right_nid == 0 or (block_cache.has(right_nid) and float(block_cache[right_nid].height) != bh):
					var l_val : int = get_light_value.call(lx + 1, ly, lz)
					var k := Vector3i(lx, id, l_val)
					var t_map := right_f_t if is_trans else right_f_o
					if not t_map.has(k): t_map[k] = []
					t_map[k].append(Vector2i(lz, ly))

				var left_nid: int = data[lx - 1 + ly_stride + lz_layer] if lx > 0 else (nd_left[CHUNK_SIZE_M1 + ly_stride + lz_layer] if has_left else 0)
				if left_nid == 0 or (block_cache.has(left_nid) and float(block_cache[left_nid].height) != bh):
					var l_val : int = get_light_value.call(lx - 1, ly, lz)
					var k := Vector3i(lx, id, l_val)
					var t_map := left_f_t if is_trans else left_f_o
					if not t_map.has(k): t_map[k] = []
					t_map[k].append(Vector2i(lz, ly))

	_build_pass_geometry(top_f_o, bot_f_o, front_f_o, back_f_o, right_f_o, left_f_o, block_cache, opaque_buf, greedy_cell_set, greedy_visited, collision_boxes, true)
	_build_pass_geometry(top_f_t, bot_f_t, front_f_t, back_f_t, right_f_t, left_f_t, block_cache, trans_buf, greedy_cell_set, greedy_visited, collision_boxes, false)

	output.opaque_mesh = _create_mesh_from_buffer(opaque_buf, atlas_shader_opaque)
	output.transparent_mesh = _create_mesh_from_buffer(trans_buf, atlas_shader_transparent)
	output.boxes = collision_boxes
	return output

static func _build_pass_geometry(top_f: Dictionary, bot_f: Dictionary, front_f: Dictionary, back_f: Dictionary, right_f: Dictionary, left_f: Dictionary, block_cache: Dictionary, b: MeshBuffers, cell_set: Dictionary, visited: Dictionary, collision_boxes: Array, gen_collision: bool) -> void:
	for key: Vector3i in top_f:
		var block = block_cache[key.y]
		var y_base: float = float(key.x) + float(block.height)
		var packed_ao: int = key.z & 0xFF
		var light_val: int = (key.z >> 8) & 0xFF
		var light: float = float(light_val) / 15.0
		
		var ao0: float = AO_VALUES[packed_ao & 3]
		var ao1: float = AO_VALUES[(packed_ao >> 2) & 3]
		var ao2: float = AO_VALUES[(packed_ao >> 4) & 3]
		var ao3: float = AO_VALUES[(packed_ao >> 6) & 3]
		var bc: Color = block.color_top
		var c0 := Color(bc.r * ao0, bc.g * ao0, bc.b * ao0, 1.0)
		var c1 := Color(bc.r * ao1, bc.g * ao1, bc.b * ao1, 1.0)
		var c2 := Color(bc.r * ao2, bc.g * ao2, bc.b * ao2, 1.0)
		var c3 := Color(bc.r * ao3, bc.g * ao3, bc.b * ao3, 1.0)

		for q: Dictionary in GreedyMesher.generate(top_f[key], cell_set, visited):
			var x0: int = q.x;  var x1: int = q.x + q.w
			var z0: int = q.y;  var z1: int = q.y + q.d
			_emit_quad(b, Vector3(float(x0), y_base, float(z0)), Vector3(float(x1), y_base, float(z0)), Vector3(float(x1), y_base, float(z1)), Vector3(float(x0), y_base, float(z1)), Vector3(0, 1, 0), block.uv_top, q.w, q.d, c0, c1, c2, c3, light)
			if gen_collision and collision_boxes.size() < MAX_COLLISION_BOXES:
				collision_boxes.append({
					"pos":  Vector3(float(x0) + float(q.w)*0.5, float(key.x)+0.5, float(z0) + float(q.d)*0.5),
					"size": Vector3(float(q.w), 1.0, float(q.d))
				})

	for key: Vector3i in bot_f:
		var block = block_cache[key.y]
		var y_base: float = float(key.x)
		var light_val: int = key.z
		var light: float = float(light_val) / 15.0
		var bc: Color = block.color_bottom
		for q: Dictionary in GreedyMesher.generate(bot_f[key], cell_set, visited):
			_emit_quad(b, Vector3(float(q.x + q.w), y_base, float(q.y)), Vector3(float(q.x), y_base, float(q.y)), Vector3(float(q.x), y_base, float(q.y + q.d)), Vector3(float(q.x + q.w), y_base, float(q.y + q.d)), Vector3(0, -1, 0), block.uv_bottom, q.w, q.d, bc, bc, bc, bc, light)

	for key: Vector3i in front_f:
		var block = block_cache[key.y]
		var z1f := float(key.x + 1)
		var light_val: int = key.z
		var light: float = float(light_val) / 15.0
		var bc: Color = block.color_front
		for q: Dictionary in GreedyMesher.generate(front_f[key], cell_set, visited):
			var y0: float = float(q.y)
			var y1: float = float(q.y) + (float(q.d) * float(block.height))
			_emit_quad(b, Vector3(float(q.x + q.w), y0, z1f), Vector3(float(q.x), y0, z1f), Vector3(float(q.x), y1, z1f), Vector3(float(q.x + q.w), y1, z1f), Vector3(0, 0, 1), block.uv_side_front, q.w, q.d, bc, bc, bc, bc, light)

	for key: Vector3i in back_f:
		var block = block_cache[key.y]
		var z0b := float(key.x)
		var light_val: int = key.z
		var light: float = float(light_val) / 15.0
		var bc: Color = block.color_back
		for q: Dictionary in GreedyMesher.generate(back_f[key], cell_set, visited):
			var y0: float = float(q.y)
			var y1: float = float(q.y) + (float(q.d) * float(block.height))
			_emit_quad(b, Vector3(float(q.x), y0, z0b), Vector3(float(q.x + q.w), y0, z0b), Vector3(float(q.x + q.w), y1, z0b), Vector3(float(q.x), y1, z0b), Vector3(0, 0, -1), block.uv_side_back, q.w, q.d, bc, bc, bc, bc, light)

	for key: Vector3i in right_f:
		var block = block_cache[key.y]
		var x1r := float(key.x + 1)
		var light_val: int = key.z
		var light: float = float(light_val) / 15.0
		var bc: Color = block.color_right
		for q: Dictionary in GreedyMesher.generate(right_f[key], cell_set, visited):
			var y0: float = float(q.y)
			var y1: float = float(q.y) + (float(q.d) * float(block.height))
			_emit_quad(b, Vector3(x1r, y0, float(q.x)), Vector3(x1r, y0, float(q.x + q.w)), Vector3(x1r, y1, float(q.x + q.w)), Vector3(x1r, y1, float(q.x)), Vector3(1, 0, 0), block.uv_side_right, q.w, q.d, bc, bc, bc, bc, light)

	for key: Vector3i in left_f:
		var block = block_cache[key.y]
		var x0l := float(key.x)
		var light_val: int = key.z
		var light: float = float(light_val) / 15.0
		var bc: Color = block.color_left
		for q: Dictionary in GreedyMesher.generate(left_f[key], cell_set, visited):
			var y0: float = float(q.y)
			var y1: float = float(q.y) + (float(q.d) * float(block.height))
			_emit_quad(b, Vector3(x0l, y0, float(q.x + q.w)), Vector3(x0l, y0, float(q.x)), Vector3(x0l, y1, float(q.x)), Vector3(x0l, y1, float(q.x + q.w)), Vector3(-1, 0, 0), block.uv_side_left, q.w, q.d, bc, bc, bc, bc, light)

static func _ao_score(s1: bool, s2: bool, corner: bool) -> int:
	if s1 and s2: return 3
	var sum := int(s1) + int(s2) + int(corner)
	return clampi(sum, 0, 3)

static func _ao_solid(data: PackedByteArray, lx: int, ly: int, lz: int) -> bool:
	if lx < 0 or lx >= CHUNK_SIZE or ly < 0 or ly >= CHUNK_SIZE or lz < 0 or lz >= CHUNK_SIZE:
		return false
	return data[lx + (ly * CHUNK_SIZE) + (lz * CHUNK_LAYER)] != 0

static func _create_mesh_from_buffer(b: MeshBuffers, mat: Material) -> ArrayMesh:
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

static func _emit_quad(b: MeshBuffers, v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3, normal: Vector3, tile_index: int, u_tiles: int, v_tiles: int, c0: Color, c1: Color, c2: Color, c3: Color, light: float) -> void:
	var vi = b.vert_idx
	b.verts.append_array([v0, v1, v2, v3])
	b.normals.append_array([normal, normal, normal, normal])
	b.uvs.append_array([Vector2(0, v_tiles), Vector2(u_tiles, v_tiles), Vector2(u_tiles, 0), Vector2(0, 0)])
	
	var ti := Vector2(float(tile_index), 0.0)
	b.uvs2.append_array([ti, ti, ti, ti])
	
	b.colors.append_array([
		Color(c0.r, c0.g, c0.b, light),
		Color(c1.r, c1.g, c1.b, light),
		Color(c2.r, c2.g, c2.b, light),
		Color(c3.r, c3.g, c3.b, light)
	])
	
	b.indices.append_array([vi, vi+1, vi+2, vi, vi+2, vi+3])
	b.vert_idx += 4
