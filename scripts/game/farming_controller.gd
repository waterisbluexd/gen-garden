extends Node3D

@export var camera_path: NodePath
@export var wheat_collector: MultiMeshInstance3D

var _selected_crop: String = ""
var _occupied: Dictionary = {}
var _planting: bool = false

const TAP_MAX_MOVE: float = 12.0
const TAP_MAX_TIME: float = 0.35
var _touch_start_pos: Vector2 = Vector2.ZERO
var _touch_start_time: float = 0.0
var _touch_moved_too_far: bool = false
var _touch_active: bool = false

var _is_mobile: bool = false

func _ready() -> void:
	_is_mobile = OS.get_name() in ["Android", "iOS"]

func select_crop(crop_name: String) -> void:
	_selected_crop = crop_name  # pivot panning untouched

func clear_selection() -> void:
	_selected_crop = ""  # pivot panning untouched

func _input(event: InputEvent) -> void:
	if _is_mobile:
		_handle_mobile_input(event)
	else:
		_handle_desktop_input(event)

func _handle_desktop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_planting = event.pressed
			if event.pressed:
				_handle_plant(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_handle_remove(event.position)
	elif event is InputEventMouseMotion and _planting:
		_handle_plant(event.position)

func _handle_mobile_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.index == 0:
		if event.pressed:
			_touch_active = true
			_touch_start_pos = event.position
			_touch_start_time = Time.get_ticks_msec() / 1000.0
			_touch_moved_too_far = false
		else:
			if _touch_active and not _touch_moved_too_far and _selected_crop != "":
				var held = (Time.get_ticks_msec() / 1000.0) - _touch_start_time
				if held <= TAP_MAX_TIME:
					_handle_plant(event.position)
			_touch_active = false

	elif event is InputEventScreenDrag and event.index == 0:
		if _touch_active:
			var dist = event.position.distance_to(_touch_start_pos)
			if dist > TAP_MAX_MOVE:
				_touch_moved_too_far = true  # pan wins, planting suppressed

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
	return cam.raycast_from_screen(screen_pos)

func _get_cell(collider: Object, world_pos: Vector3) -> Variant:
	if not collider is GridMap:
		return null
	var gm  = collider as GridMap
	var loc = gm.to_local(world_pos)
	var csz = gm.cell_size
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
