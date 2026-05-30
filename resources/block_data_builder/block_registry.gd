extends Resource
class_name BlockRegistry

@export var blocks: Array[BlockType] = []
var _cache: Dictionary = {}

func _build_cache() -> void:
	_cache.clear()
	for block in blocks:
		_cache[block.id] = block

func get_block(id: int) -> BlockType:
	if _cache.is_empty():
		_build_cache()
	return _cache.get(id, null)

func get_block_by_name(bname: String) -> BlockType:
	for block in blocks:
		if block.block_name == bname:
			return block
	return null
