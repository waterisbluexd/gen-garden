class_name VoxelRaycast
extends RefCounted

## Requires a callable `get_voxel_func(Vector3i) -> int` to check block solidity
static func dda_raycast(ray_origin: Vector3, ray_direction: Vector3, max_distance: float, get_voxel_func: Callable) -> Dictionary:
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
		
		if get_voxel_func.call(map_pos) != 0:
			return {"hit": true, "position": map_pos, "normal": last_axis}
			
	return {"hit": false, "position": Vector3i.ZERO, "normal": Vector3i.ZERO}
