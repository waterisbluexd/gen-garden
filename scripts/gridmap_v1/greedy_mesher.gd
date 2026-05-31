class_name GreedyMesher
extends RefCounted

static func generate(coords: Array, cell_set: Dictionary, visited: Dictionary) -> Array[Dictionary]:
	cell_set.clear()
	visited.clear()
	for c in coords:
		cell_set[c] = true
	coords.sort()
	var result: Array[Dictionary] = []
	for coord: Vector2i in coords:
		if visited.has(coord): continue
		var cx: int = coord.x
		var cy: int = coord.y
		var w := 1
		while cell_set.has(Vector2i(cx + w, cy)) and not visited.has(Vector2i(cx + w, cy)):
			w += 1
		var d := 1
		var can_expand := true
		while can_expand:
			for i in range(w):
				if not cell_set.has(Vector2i(cx + i, cy + d)) or visited.has(Vector2i(cx + i, cy + d)):
					can_expand = false
					break
			if can_expand: d += 1
		for iz in range(d):
			for ix in range(w):
				visited[Vector2i(cx + ix, cy + iz)] = true
		result.append({"x": cx, "y": cy, "w": w, "d": d})
	return result
