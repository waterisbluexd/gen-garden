extends Node3D

@export var camera_path: NodePath
@export var wheat_collector: MultiMeshInstance3D

var _selected_crop: String = ""
var _occupied: Dictionary = {}  # Vector3i -> {type, position}
var _planting: bool = false

func select_crop(crop_name: String) -> void:
	_selected_crop = crop_name

func clear_selection() -> void:
	_selected_crop = ""

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_planting = event.pressed
			if event.pressed:
				_handle_plant(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_handle_remove(event.position)
	elif event is InputEventMouseMotion and _planting:
		_handle_plant(event.position)

func _handle_plant(screen_pos: Vector2) -> void:
	if _selected_crop == "":
		return
	var hit = _raycast(screen_pos)
	if hit.is_empty():
		return
	var cell = _get_cell(hit.collider, hit.position)
	if cell == null or _occupied.has(cell):
		return
	var pos = _get_spawn_pos(cell, hit.collider)
	match _selected_crop:
		"wheat":
			if wheat_collector:
				wheat_collector.plant(pos)
				_occupied[cell] = {"type": "wheat", "position": pos}

func _handle_remove(screen_pos: Vector2) -> void:
	if _selected_crop != "":
		clear_selection()
		return
	var hit = _raycast(screen_pos)
	if hit.is_empty():
		return
	var cell = _get_cell(hit.collider, hit.position)
	if cell == null or not _occupied.has(cell):
		return
	var data = _occupied[cell]
	match data["type"]:
		"wheat":
			if wheat_collector:
				wheat_collector.harvest_at(data["position"])
	_occupied.erase(cell)

func _raycast(screen_pos: Vector2) -> Dictionary:
	var cam = get_node_or_null(camera_path) as Camera3D
	if not cam:
		return {}
	var from  = cam.project_ray_origin(screen_pos)
	var to    = from + cam.project_ray_normal(screen_pos) * 1000.0
	var query = PhysicsRayQueryParameters3D.new()
	query.from = from
	query.to   = to
	query.collide_with_bodies = true
	query.collide_with_areas  = false
	query.collision_mask      = 0x7fffffff
	return get_world_3d().direct_space_state.intersect_ray(query)

func _get_cell(collider: Object, world_pos: Vector3) -> Variant:
	if not collider is GridMap:
		return null
	var gm   = collider as GridMap
	var loc  = gm.to_local(world_pos)
	var csz  = gm.cell_size
	var cell = Vector3i(
		int(floor(loc.x / csz.x)),
		int(floor((loc.y - 0.01) / csz.y)),
		int(floor(loc.z / csz.z))
	)
	for c in [cell, cell + Vector3i(0, -1, 0)]:
		if gm.get_cell_item(c) == 2:
			return c
	return null

func _get_spawn_pos(cell: Vector3i, collider: Object) -> Vector3:
	var gm  = collider as GridMap
	var csz = gm.cell_size
	var ctr = Vector3(
		cell.x * csz.x + csz.x * 0.5,
		cell.y * csz.y + csz.y * 0.5,
		cell.z * csz.z + csz.z * 0.5
	)
	return gm.to_global(ctr) + Vector3(0, 0.5, 0)
