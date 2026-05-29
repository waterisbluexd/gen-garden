extends Resource
class_name BlockRegistry

@export var blocks: Array[BlockType] = []

func get_block(id: int) -> BlockType:
	for block in blocks:
		if block.id == id:
			return block
	return null

func get_block_by_name(name: String) -> BlockType:
	for block in blocks:
		if block.block_name == name:
			return block
	return null
