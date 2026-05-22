extends TextureButton

func _ready() -> void:
	pass

func _on_pressed() -> void:
	var controller = _find_farming_controller()
	if controller:
		controller.select_crop("wheat")
		print("wheat_from_main_ui_pressed! selected crop on", controller)
	else:
		print("wheat_from_main_ui_pressed! no controller found")

func _find_farming_controller() -> Node:
	var root = get_tree().get_current_scene()
	if not root and get_tree().get_root().get_child_count() > 0:
		root = get_tree().get_root().get_child(0)
	if not root:
		return null
	if root.has_method("select_crop"):
		return root
	return _find_controller_recursive(root)

func _find_controller_recursive(node: Node) -> Node:
	for child in node.get_children():
		if child is Node:
			if child.has_method("select_crop"):
				return child
			var found = _find_controller_recursive(child)
			if found:
				return found
	return null
