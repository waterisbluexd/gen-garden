extends Node3D
class_name Grid

@export var atlas_texture: Texture2D
@export var atlas_shader: ShaderMaterial
@export var block_registry: BlockRegistry

var cells: Dictionary = {}
var mesh_instance: MeshInstance3D
var camera: Camera3D

# Tracks which block ID is selected via hotkeys (1, 2, or 3)
var active_block_id: int = 1

@onready var static_body_3d: StaticBody3D = $StaticBody3D

func _ready() -> void:
	mesh_instance = MeshInstance3D.new()
	add_child(mesh_instance)

func _unhandled_input(event: InputEvent) -> void:
	# Handle hotkey block selection (Keys 1, 2, and 3)
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1:
				active_block_id = 1
				print("Selected Block ID 1")
			KEY_2:
				active_block_id = 2
				print("Selected Block ID 2")
			KEY_3:
				active_block_id = 3
				print("Selected Block ID 3")

	# Handle mouse click placement/removal
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			place_block_from_mouse(active_block_id)
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			remove_block_from_mouse()

func place_block_from_mouse(block_id: int) -> void:
	if camera == null: return
	var result = camera.raycast_from_screen(get_viewport().get_mouse_position())
	if result.is_empty(): return
	var target = result.position + result.normal * 0.5
	var x = floori(target.x)
	var z = floori(target.z)
	set_cell(x, z, block_id)

func remove_block_from_mouse() -> void:
	if camera == null: return
	var result = camera.raycast_from_screen(get_viewport().get_mouse_position())
	if result.is_empty(): return
	var target = result.position - result.normal * 0.5
	var x = floori(target.x)
	var z = floori(target.z)
	remove_cell(x, z)

func set_cell(x: int, z: int, block_id: int) -> void:
	cells[Vector2i(x, z)] = block_id
	rebuild_mesh()

func remove_cell(x: int, z: int) -> void:
	var coord := Vector2i(x, z)
	if not cells.has(coord): return
	cells.erase(coord)
	rebuild_mesh()

func fill(width: int, height: int, block_id: int) -> void:
	for z in range(height):
		for x in range(width):
			cells[Vector2i(x, z)] = block_id
	rebuild_mesh()

func rebuild_mesh() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var vertex_counter: int = 0

	var by_type: Dictionary = {}
	for coord in cells.keys():
		var id: int = cells[coord]
		if not by_type.has(id):
			by_type[id] = []
		by_type[id].append(coord)

	for block_id in by_type.keys():
		var block: BlockType = block_registry.get_block(block_id)
		if block == null:
			push_warning("BlockRegistry: no block with id %d" % block_id)
			continue

		var coords: Array = by_type[block_id]
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

			vertex_counter = add_box(st, coord.x, coord.y, w, d, block, vertex_counter)

	var mat: ShaderMaterial = atlas_shader.duplicate()
	mat.set_shader_parameter("albedo_texture", atlas_texture) 
	st.set_material(mat)

	var array_mesh := ArrayMesh.new()
	st.commit(array_mesh)

	mesh_instance.mesh = array_mesh
	for child in mesh_instance.get_children():
		child.queue_free()
	
	mesh_instance.create_trimesh_collision()

func add_box(st: SurfaceTool, x: int, z: int, w: int, d: int, block: BlockType, start_vertex: int) -> int:
	var x0 := float(x)
	var x1 := float(x + w)
	var z0 := float(z)
	var z1 := float(z + d)
	var y0 := 0.0
	var y1 := 1.0

	var current_vertex: int = start_vertex

	# 1. TOP FACE (Normal: 0, 1, 0)
	current_vertex = add_face(st, [
		Vector3(x0, y1, z0), Vector3(x1, y1, z0),
		Vector3(x1, y1, z1), Vector3(x0, y1, z1)
	], Vector3(0, 1, 0), block.uv_top, w, d, current_vertex, block.albedo_color)

	# NOTE: BOTTOM FACE CULLED (REMOVED)

	# 2. FRONT FACE (Normal: 0, 0, 1) - Facing toward +Z
	current_vertex = add_face(st, [
		Vector3(x1, y0, z1), Vector3(x0, y0, z1),
		Vector3(x0, y1, z1), Vector3(x1, y1, z1)
	], Vector3(0, 0, 1), block.uv_side_front, w, 1, current_vertex, block.albedo_color)

	# 3. BACK FACE (Normal: 0, 0, -1) - Facing toward -Z
	current_vertex = add_face(st, [
		Vector3(x0, y0, z0), Vector3(x1, y0, z0),
		Vector3(x1, y1, z0), Vector3(x0, y1, z0)
	], Vector3(0, 0, -1), block.uv_side_back, w, 1, current_vertex, block.albedo_color)

	# 4. RIGHT FACE (Normal: 1, 0, 0) - Facing toward +X
	current_vertex = add_face(st, [
		Vector3(x1, y0, z0), Vector3(x1, y0, z1),
		Vector3(x1, y1, z1), Vector3(x1, y1, z0)
	], Vector3(1, 0, 0), block.uv_side_right, d, 1, current_vertex, block.albedo_color)

	# 5. LEFT FACE (Normal: -1, 0, 0) - Facing toward -X
	current_vertex = add_face(st, [
		Vector3(x0, y0, z1), Vector3(x0, y0, z0),
		Vector3(x0, y1, z0), Vector3(x0, y1, z1)
	], Vector3(-1, 0, 0), block.uv_side_left, d, 1, current_vertex, block.albedo_color)

	return current_vertex

func add_face(st: SurfaceTool, verts: Array, normal: Vector3,
			  tile_index: int, u_tiles: int, v_tiles: int, start_idx: int, face_color: Color) -> int:

	var uvs := [
		Vector2(0,       v_tiles),
		Vector2(u_tiles, v_tiles),
		Vector2(u_tiles, 0      ),
		Vector2(0,       0      ),
	]
	
	for i in range(4):
		st.set_uv(uvs[i])
		st.set_uv2(Vector2(float(tile_index), 0.0))
		st.set_normal(normal)
		st.set_color(face_color)
		st.add_vertex(verts[i])
		
	# Standard CCW Triangulation Indices
	st.add_index(start_idx + 0)
	st.add_index(start_idx + 1)
	st.add_index(start_idx + 2)
	
	st.add_index(start_idx + 0)
	st.add_index(start_idx + 2)
	st.add_index(start_idx + 3)

	return start_idx + 4
