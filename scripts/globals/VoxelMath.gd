extends Node

# A reference to your main World node so we can look up chunk data.
# We will assign this when the World initializes.
var world_node: Node = null

## Performs a fast mathematical grid raycast without using physics.
## Returns a Dictionary with: "hit" (bool), "position" (Vector3i), "normal" (Vector3i)
func dda_raycast(ray_origin: Vector3, ray_direction: Vector3, max_distance: float) -> Dictionary:
	var dir := ray_direction.normalized()
	
	# Current voxel coordinates the ray origin is inside
	var map_pos := Vector3i(
		floor(ray_origin.x),
		floor(ray_origin.y),
		floor(ray_origin.z)
	)
	
	# How far the ray travels along each axis to cross a grid boundary
	var delta_dist := Vector3(
		abs(1.0 / (dir.x if dir.x != 0 else 0.00001)),
		abs(1.0 / (dir.y if dir.y != 0 else 0.00001)),
		abs(1.0 / (dir.z if dir.z != 0 else 0.00001))
	)
	
	var step := Vector3i.ZERO
	var side_dist := Vector3.ZERO
	
	# Initialize stepping parameters per axis
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
			
		if total_dist > max_distance:
			break
			
		# Check the voxel data using our bridge function
		if _get_voxel_at(map_pos) != 0: # 0 = AIR
			return {
				"hit": true,
				"position": map_pos,
				"normal": last_axis
			}
			
	return {"hit": false, "position": Vector3i.ZERO, "normal": Vector3i.ZERO}

## Internal helper to query your world layout
func _get_voxel_at(global_pos: Vector3i) -> int:
	if not is_instance_valid(world_node):
		return 0 # Return air if world isn't registered yet
		
	# Forward the request to your World script which knows how chunks are stored
	if world_node.has_method("get_global_voxel"):
		return world_node.get_global_voxel(global_pos)
		
	return 0
