extends Node3D

@export var camera_path: NodePath = "camera/camera_pivot/Camera3D"
@export var gridmap_path: NodePath = "Main_map/main_map/GridMap"
@export var crop_root_path: NodePath = "Main_map/main_map/crop_collector"
@export var wheat_crop_scene: PackedScene = preload("res://scenes/blocks/crops/wheat/crop_wheat.tscn")

var selected_crop_scene: PackedScene = null
var selected_crop_name: String = ""
var occupied_crops: Dictionary = {}

func _ready() -> void:
	if not get_node_or_null(crop_root_path):
		var fallback = Node3D.new()
		fallback.name = "crop_collector"
		get_node("Main_map/main_map").add_child(fallback)

func select_crop(crop_name: String) -> void:
	match crop_name:
		"wheat":
			selected_crop_scene = wheat_crop_scene
			selected_crop_name = crop_name
		_:
			selected_crop_scene = null
			selected_crop_name = ""
	print("Selected crop:", selected_crop_name)

func clear_selection() -> void:
	selected_crop_scene = null
	selected_crop_name = ""
	print("Crop selection cleared")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and not event.is_echo():
		if event.button_index == MOUSE_BUTTON_LEFT:
			print("Farming controller left click", event.position)
			_handle_left_click(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			print("Farming controller right click", event.position)
			_handle_right_click(event.position)

func _handle_left_click(screen_position: Vector2) -> void:
	if not selected_crop_scene:
		print("No crop selected")
		return
	var hit = _raycast_world(screen_position)
	print("Raycast hit:", hit)
	if hit.is_empty():
		return
	var place_key = _get_farmland_key(hit.collider, hit.position)
	print("Farmland key:", place_key)
	if place_key == null:
		return
	if occupied_crops.has(place_key):
		print("Slot already occupied", place_key)
		return
	var spawn_position = _get_crop_world_position(place_key, hit.collider, hit.position)
	if spawn_position == null:
		return
	var crop = selected_crop_scene.instantiate() as Node3D
	var crop_root = get_node_or_null(crop_root_path) as Node3D
	if not crop_root:
		return
	crop_root.add_child(crop)
	crop.global_transform = Transform3D(crop.global_transform.basis, spawn_position)
	occupied_crops[place_key] = crop
	print("Placed crop", selected_crop_name, "at", place_key)

func _handle_right_click(screen_position: Vector2) -> void:
	var hit = _raycast_world(screen_position)
	if hit.is_empty():
		if selected_crop_scene:
			clear_selection()
			print("Placement canceled")
		return
	var place_key = _get_farmland_key(hit.collider, hit.position)
	if place_key == null:
		if selected_crop_scene:
			clear_selection()
			print("Placement canceled")
		return
	if not occupied_crops.has(place_key):
		if selected_crop_scene:
			clear_selection()
			print("Placement canceled")
		return
	var crop = occupied_crops[place_key]
	if crop and crop.is_inside_tree():
		if crop.has_method("harvest") and crop.is_harvestable:
			crop.harvest()
			print("Harvested crop at", place_key)
		else:
			if crop.has_method("remove_crop"):
				crop.remove_crop()
			else:
				crop.queue_free()
			print("Removed crop at", place_key)
	occupied_crops.erase(place_key)

func _raycast_world(screen_position: Vector2) -> Dictionary:
	var camera = get_node_or_null(camera_path) as Camera3D
	if not camera:
		return {}
	var from = camera.project_ray_origin(screen_position)
	var to = from + camera.project_ray_normal(screen_position) * 1000.0
	var query = PhysicsRayQueryParameters3D.new()
	query.from = from
	query.to = to
	query.exclude = []
	query.collision_mask = 0x7fffffff
	query.collide_with_bodies = true
	query.collide_with_areas = false
	return get_world_3d().direct_space_state.intersect_ray(query)

func _get_farmland_key(collider: Object, world_position: Vector3) -> Variant:
	if collider is GridMap:
		var gridmap = collider as GridMap
		var local_pos = gridmap.to_local(world_position)
		var cell_size = gridmap.cell_size
		var cell_pos = Vector3i(
			int(floor(local_pos.x / cell_size.x)),
			int(floor((local_pos.y - 0.01) / cell_size.y)),
			int(floor(local_pos.z / cell_size.z))
		)
		var candidates = [
			cell_pos,
			cell_pos + Vector3i(0, -1, 0)
		]
		for candidate in candidates:
			var item = gridmap.get_cell_item(candidate)
			print("GridMap candidate:", candidate, "item:", item, "local_pos:", local_pos)
			if item == 2:
				return candidate
		return null
	var node = collider as Node
	while node:
		if node.name == "block_farmland":
			return node
		node = node.get_parent()
	return null

func _get_crop_world_position(place_key: Variant, collider: Object, world_position: Vector3) -> Vector3:
	if place_key is Vector3i:
		var gridmap = collider as GridMap
		var cell_pos = place_key as Vector3i
		var cell_size = gridmap.cell_size
		var cell_center = Vector3(
			cell_pos.x * cell_size.x + cell_size.x * 0.5,
			cell_pos.y * cell_size.y + cell_size.y * 0.5,
			cell_pos.z * cell_size.z + cell_size.z * 0.5
		)
		var world_center = gridmap.to_global(cell_center)
		return world_center + Vector3(0, 0.5, 0)
	if place_key is Node:
		return (place_key as Node3D).global_transform.origin + Vector3(0, 0.5, 0)
	return world_position
