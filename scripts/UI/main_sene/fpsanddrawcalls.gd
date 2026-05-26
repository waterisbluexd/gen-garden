extends Label

func _process(_delta: float) -> void:
	var fps        = Engine.get_frames_per_second()
	var nodes      = get_tree().get_node_count()
	var draw_calls = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var objects    = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
	var primitives = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	
	# Crop specific
	var wheat = get_tree().get_first_node_in_group("crop_renderer")
	var crop_count = 0
	if wheat and wheat.multimesh:
		crop_count = wheat.multimesh.instance_count

	text = """FPS:        %d
Nodes:      %d
Draw Calls: %d
Objects:    %d
Primitives: %d
--------------
Crops:      %d
Per Crop DC: %.2f""" % [
		fps, nodes, draw_calls, objects, primitives,
		crop_count,
		float(draw_calls) / max(crop_count, 1)
	]
