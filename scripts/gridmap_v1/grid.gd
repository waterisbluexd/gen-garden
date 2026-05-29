extends Node3D
class_name Grid

@export var atlas_texture: Texture2D
@export var atlas_shader: ShaderMaterial
@export var block_registry: BlockRegistry

@export_group("Base Layer Options")
@export var generate_base_layer: bool = true
@export var base_block_id: int = 2
@export var base_width: int = 512
@export var base_depth: int = 512
@export var base_y_level: int = 0

const CHUNK_SIZE: int = 32

var cells: Dictionary = {}
var chunk_to_cells: Dictionary = {}
var chunk_nodes: Dictionary = {}

var camera: Camera3D
var active_block_id: int = 1

func _ready() -> void:
	if has_node("StaticBody3D"):
		$StaticBody3D.queue_free()
		
	if generate_base_layer:
		fill(base_width, base_depth, base_block_id, base_y_level)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1: active_block_id = 1
			KEY_2: active_block_id = 2
			KEY_3: active_block_id = 3
			KEY_4: active_block_id = 4

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			place_block_from_mouse(active_block_id)
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			remove_block_from_mouse()

func get_chunk_coord(global_pos: Vector3i) -> Vector3i:
	return Vector3i(
		floori(float(global_pos.x) / CHUNK_SIZE),
		floori(float(global_pos.y) / CHUNK_SIZE),
		floori(float(global_pos.z) / CHUNK_SIZE)
	)

func ensure_chunk_node(chunk_coord: Vector3i) -> void:
	if chunk_nodes.has(chunk_coord): return
	
	var chunk_node = Node3D.new()
	chunk_node.name = "Chunk_%d_%d_%d" % [chunk_coord.x, chunk_coord.y, chunk_coord.z]
	add_child(chunk_node)
	
	var mi = MeshInstance3D.new()
	chunk_node.add_child(mi)
	
	var body = StaticBody3D.new()
	chunk_node.add_child(body)
	
	var shape = CollisionShape3D.new()
	body.add_child(shape)
	
	chunk_nodes[chunk_coord] = {
		"node": chunk_node,
		"mesh_instance": mi,
		"collision_shape": shape
	}

func place_block_from_mouse(block_id: int) -> void:
	if camera == null: return
	var result = camera.raycast_from_screen(get_viewport().get_mouse_position())
	if result.is_empty(): return
	
	var target = result.position + result.normal * 0.5
	set_cell(floori(target.x), floori(target.y), floori(target.z), block_id)

func remove_block_from_mouse() -> void:
	if camera == null: return
	var result = camera.raycast_from_screen(get_viewport().get_mouse_position())
	if result.is_empty(): return
	
	var target = result.position - result.normal * 0.5
	remove_cell(floori(target.x), floori(target.y), floori(target.z))

func set_cell(x: int, y: int, z: int, block_id: int) -> void:
	var global_pos := Vector3i(x, y, z)
	cells[global_pos] = block_id
	
	var chunk_coord = get_chunk_coord(global_pos)
	if not chunk_to_cells.has(chunk_coord):
		chunk_to_cells[chunk_coord] = {}
	chunk_to_cells[chunk_coord][global_pos] = true
	
	rebuild_chunks_for_block(global_pos)

func remove_cell(x: int, y: int, z: int) -> void:
	var global_pos := Vector3i(x, y, z)
	if not cells.has(global_pos): return
	
	cells.erase(global_pos)
	
	var chunk_coord = get_chunk_coord(global_pos)
	if chunk_to_cells.has(chunk_coord):
		chunk_to_cells[chunk_coord].erase(global_pos)
		if chunk_to_cells[chunk_coord].is_empty():
			chunk_to_cells.erase(chunk_coord)
			
	rebuild_chunks_for_block(global_pos)

func fill(width: int, depth: int, block_id: int, y: int = 0) -> void:
	var affected_chunks := {}
	
	for z in range(depth):
		for x in range(width):
			var global_pos := Vector3i(x, y, z)
			cells[global_pos] = block_id
			
			var chunk_coord = get_chunk_coord(global_pos)
			if not chunk_to_cells.has(chunk_coord):
				chunk_to_cells[chunk_coord] = {}
			chunk_to_cells[chunk_coord][global_pos] = true
			affected_chunks[chunk_coord] = true
			
	for c in affected_chunks.keys():
		rebuild_chunk_mesh(c)

func rebuild_chunks_for_block(global_pos: Vector3i) -> void:
	var chunk_coord = get_chunk_coord(global_pos)
	var chunks_to_rebuild := { chunk_coord: true }
	
	var local_x = posmod(global_pos.x, CHUNK_SIZE)
	var local_y = posmod(global_pos.y, CHUNK_SIZE)
	var local_z = posmod(global_pos.z, CHUNK_SIZE)
	
	if local_x == 0: chunks_to_rebuild[chunk_coord + Vector3i(-1, 0, 0)] = true
	if local_x == CHUNK_SIZE - 1: chunks_to_rebuild[chunk_coord + Vector3i(1, 0, 0)] = true
	if local_y == 0: chunks_to_rebuild[chunk_coord + Vector3i(0, -1, 0)] = true
	if local_y == CHUNK_SIZE - 1: chunks_to_rebuild[chunk_coord + Vector3i(0, 1, 0)] = true
	if local_z == 0: chunks_to_rebuild[chunk_coord + Vector3i(0, 0, -1)] = true
	if local_z == CHUNK_SIZE - 1: chunks_to_rebuild[chunk_coord + Vector3i(0, 0, 1)] = true
	
	for c in chunks_to_rebuild.keys():
		rebuild_chunk_mesh(c)

func rebuild_chunk_mesh(chunk_coord: Vector3i) -> void:
	var new_mesh = generate_chunk_mesh_data(chunk_coord)
	apply_mesh_to_chunk_node(chunk_coord, new_mesh)

func generate_chunk_mesh_data(chunk_coord: Vector3i) -> ArrayMesh:
	if not chunk_to_cells.has(chunk_coord) or chunk_to_cells[chunk_coord].is_empty():
		return null

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var vertex_counter: int = 0

	var top_faces: Dictionary = {}
	var bottom_faces: Dictionary = {}
	var front_faces: Dictionary = {}
	var back_faces: Dictionary = {}
	var right_faces: Dictionary = {}
	var left_faces: Dictionary = {}

	for coord in chunk_to_cells[chunk_coord].keys():
		var id: int = cells[coord]
		var block = block_registry.get_block(id)
		var key := Vector2i(coord.y, id)
		var key_z := Vector2i(coord.z, id)
		var key_x := Vector2i(coord.x, id)

		var top_coord = Vector3i(coord.x, coord.y + 1, coord.z)
		if not cells.has(top_coord) or block.height < 1.0:
			if not top_faces.has(key): top_faces[key] = []
			top_faces[key].append(Vector2i(coord.x, coord.z))
			
		var bottom_coord = Vector3i(coord.x, coord.y - 1, coord.z)
		if not cells.has(bottom_coord) or block_registry.get_block(cells[bottom_coord]).height < 1.0:
			if not bottom_faces.has(key): bottom_faces[key] = []
			bottom_faces[key].append(Vector2i(coord.x, coord.z))

		var front_coord = Vector3i(coord.x, coord.y, coord.z + 1)
		if not cells.has(front_coord) or block_registry.get_block(cells[front_coord]).height < block.height:
			if not front_faces.has(key_z): front_faces[key_z] = []
			front_faces[key_z].append(Vector2i(coord.x, coord.y))
			
		var back_coord = Vector3i(coord.x, coord.y, coord.z - 1)
		if not cells.has(back_coord) or block_registry.get_block(cells[back_coord]).height < block.height:
			if not back_faces.has(key_z): back_faces[key_z] = []
			back_faces[key_z].append(Vector2i(coord.x, coord.y))

		var right_coord = Vector3i(coord.x + 1, coord.y, coord.z)
		if not cells.has(right_coord) or block_registry.get_block(cells[right_coord]).height < block.height:
			if not right_faces.has(key_x): right_faces[key_x] = []
			right_faces[key_x].append(Vector2i(coord.z, coord.y))
			
		var left_coord = Vector3i(coord.x - 1, coord.y, coord.z)
		if not cells.has(left_coord) or block_registry.get_block(cells[left_coord]).height < block.height:
			if not left_faces.has(key_x): left_faces[key_x] = []
			left_faces[key_x].append(Vector2i(coord.z, coord.y))

	for key in top_faces.keys():
		var block = block_registry.get_block(key.y)
		var quads = greedy_mesh_2d(top_faces[key], true)
		for q in quads:
			vertex_counter = add_top_face(st, q.x, key.x, q.y, q.w, q.d, block, vertex_counter)

	for key in bottom_faces.keys():
		var block = block_registry.get_block(key.y)
		var quads = greedy_mesh_2d(bottom_faces[key], true)
		for q in quads:
			vertex_counter = add_bottom_face(st, q.x, key.x, q.y, q.w, q.d, block, vertex_counter)

	for key in front_faces.keys():
		var block = block_registry.get_block(key.y)
		var quads = greedy_mesh_2d(front_faces[key], block.height == 1.0)
		for q in quads:
			vertex_counter = add_front_face(st, q.x, q.y, key.x, q.w, q.d, block, vertex_counter)

	for key in back_faces.keys():
		var block = block_registry.get_block(key.y)
		var quads = greedy_mesh_2d(back_faces[key], block.height == 1.0)
		for q in quads:
			vertex_counter = add_back_face(st, q.x, q.y, key.x, q.w, q.d, block, vertex_counter)

	for key in right_faces.keys():
		var block = block_registry.get_block(key.y)
		var quads = greedy_mesh_2d(right_faces[key], block.height == 1.0)
		for q in quads:
			vertex_counter = add_right_face(st, key.x, q.y, q.x, q.d, q.w, block, vertex_counter)

	for key in left_faces.keys():
		var block = block_registry.get_block(key.y)
		var quads = greedy_mesh_2d(left_faces[key], block.height == 1.0)
		for q in quads:
			vertex_counter = add_left_face(st, key.x, q.y, q.x, q.d, q.w, block, vertex_counter)

	var mat: ShaderMaterial = atlas_shader.duplicate()
	mat.set_shader_parameter("albedo_texture", atlas_texture)
	st.set_material(mat)

	var array_mesh := ArrayMesh.new()
	st.commit(array_mesh)
	return array_mesh

func apply_mesh_to_chunk_node(chunk_coord: Vector3i, array_mesh: ArrayMesh) -> void:
	if array_mesh == null:
		if chunk_nodes.has(chunk_coord):
			chunk_nodes[chunk_coord].mesh_instance.mesh = null
			chunk_nodes[chunk_coord].collision_shape.shape = null
		return

	ensure_chunk_node(chunk_coord)
	var chunk_data = chunk_nodes[chunk_coord]
	
	chunk_data.mesh_instance.mesh = array_mesh
	chunk_data.collision_shape.shape = array_mesh.create_trimesh_shape()

func greedy_mesh_2d(coords: Array, allow_vertical_expansion: bool = true) -> Array:
	var result := []
	coords.sort_custom(func(a, b): return a.x < b.x if a.x != b.x else a.y < b.y)

	var cell_set: Dictionary = {}
	for c in coords:
		cell_set[c] = true

	var visited: Dictionary = {}

	for coord in coords:
		if visited.has(coord):
			continue

		var w := 1
		while cell_set.has(Vector2i(coord.x + w, coord.y)) and not visited.has(Vector2i(coord.x + w, coord.y)):
			w += 1

		var d := 1
		if allow_vertical_expansion:
			var can_expand := true
			while can_expand:
				for i in range(w):
					if not cell_set.has(Vector2i(coord.x + i, coord.y + d)) or visited.has(Vector2i(coord.x + i, coord.y + d)):
						can_expand = false
						break
				if can_expand:
					d += 1

		for iz in range(d):
			for ix in range(w):
				visited[Vector2i(coord.x + ix, coord.y + iz)] = true

		result.append({"x": coord.x, "y": coord.y, "w": w, "d": d})
	return result

func add_top_face(st: SurfaceTool, x: int, y: int, z: int, w: int, d: int, block: BlockType, start_idx: int) -> int:
	var x0 := float(x); var x1 := float(x + w); var z0 := float(z); var z1 := float(z + d); var y1 := float(y) + block.height
	var verts := [Vector3(x0, y1, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3(x0, y1, z1)]
	return add_face(st, verts, Vector3(0, 1, 0), block.uv_top, w, d, start_idx, block.color_top)

func add_bottom_face(st: SurfaceTool, x: int, y: int, z: int, w: int, d: int, block: BlockType, start_idx: int) -> int:
	var x0 := float(x); var x1 := float(x + w); var z0 := float(z); var z1 := float(z + d); var y0 := float(y)
	var verts := [Vector3(x1, y0, z0), Vector3(x0, y0, z0), Vector3(x0, y0, z1), Vector3(x1, y0, z1)]
	return add_face(st, verts, Vector3(0, -1, 0), block.uv_bottom, w, d, start_idx, block.color_bottom)

func add_front_face(st: SurfaceTool, x: int, y: int, z: int, w: int, h: int, block: BlockType, start_idx: int) -> int:
	var x0 := float(x); var x1 := float(x + w); var z1 := float(z + 1); var y0 := float(y); var y1 := float(y) + (float(h) * block.height)
	var verts := [Vector3(x1, y0, z1), Vector3(x0, y0, z1), Vector3(x0, y1, z1), Vector3(x1, y1, z1)]
	return add_face(st, verts, Vector3(0, 0, 1), block.uv_side_front, w, h, start_idx, block.color_front)

func add_back_face(st: SurfaceTool, x: int, y: int, z: int, w: int, h: int, block: BlockType, start_idx: int) -> int:
	var x0 := float(x); var x1 := float(x + w); var z0 := float(z); var y0 := float(y); var y1 := float(y) + (float(h) * block.height)
	var verts := [Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y1, z0), Vector3(x0, y1, z0)]
	return add_face(st, verts, Vector3(0, 0, -1), block.uv_side_back, w, h, start_idx, block.color_back)

func add_right_face(st: SurfaceTool, x: int, y: int, z: int, h: int, d: int, block: BlockType, start_idx: int) -> int:
	var x1 := float(x + 1); var z0 := float(z); var z1 := float(z + d); var y0 := float(y); var y1 := float(y) + (float(h) * block.height)
	var verts := [Vector3(x1, y0, z0), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x1, y1, z0)]
	return add_face(st, verts, Vector3(1, 0, 0), block.uv_side_right, d, h, start_idx, block.color_right)

func add_left_face(st: SurfaceTool, x: int, y: int, z: int, h: int, d: int, block: BlockType, start_idx: int) -> int:
	var x0 := float(x); var z0 := float(z); var z1 := float(z + d); var y0 := float(y); var y1 := float(y) + (float(h) * block.height)
	var verts := [Vector3(x0, y0, z1), Vector3(x0, y0, z0), Vector3(x0, y1, z0), Vector3(x0, y1, z1)]
	return add_face(st, verts, Vector3(-1, 0, 0), block.uv_side_left, d, h, start_idx, block.color_left)

func add_face(st: SurfaceTool, verts: Array, normal: Vector3, tile_index: int, u_tiles: int, v_tiles: int, start_idx: int, face_color: Color) -> int:
	var uvs := [Vector2(0, v_tiles), Vector2(u_tiles, v_tiles), Vector2(u_tiles, 0), Vector2(0, 0)]
	for i in range(4):
		st.set_uv(uvs[i])
		st.set_uv2(Vector2(float(tile_index), 0.0))
		st.set_normal(normal)
		st.set_color(face_color)
		st.add_vertex(verts[i])
	st.add_index(start_idx + 0); st.add_index(start_idx + 1); st.add_index(start_idx + 2)
	st.add_index(start_idx + 0); st.add_index(start_idx + 2); st.add_index(start_idx + 3)
	return start_idx + 4
