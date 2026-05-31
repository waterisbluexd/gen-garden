class_name MeshBuffers
extends RefCounted

var verts := PackedVector3Array()
var normals := PackedVector3Array()
var uvs := PackedVector2Array()
var uvs2 := PackedVector2Array()
var colors := PackedColorArray()
var indices := PackedInt32Array()
var vert_idx: int = 0

func clear() -> void:
	verts.clear()
	normals.clear()
	uvs.clear()
	uvs2.clear()
	colors.clear()
	indices.clear()
	vert_idx = 0
