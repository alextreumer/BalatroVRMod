class_name ShatterFX
extends Node3D
## Something breaks apart: shards of its own picture fly off, tumble, fall and fade.
## Used for the blind chip when a blind is beaten and for glass cards that break.

const LIFE := 1.4
const GRAVITY := 1.6

var _shards: Array[Dictionary] = []
var _time := 0.0
var _rest_y := INF                  # settle_at(): the shards stay on a table at this height (world)


## Achievement reward "Glass Breaker": the shards fall onto the table and stay there (main.gd frees
## them when the run ends) instead of fading away.
func settle_at(table_y: float) -> void:
	_rest_y = table_y


## Breaks a flat picture of `size` (its material(s) drawn on each shard) at `xform` (world).
## `round` cuts it like a pie (chip), otherwise into a rough grid (card).
static func burst(parent: Node, xform: Transform3D, layers: Array, size: Vector2, round := false, power := 1.0) -> ShatterFX:
	var fx := ShatterFX.new()
	parent.add_child(fx)
	fx.global_transform = xform
	fx._build(layers, size, round, power)
	return fx


func _build(layers: Array, size: Vector2, round: bool, power: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var pieces: Array = [] # polygons in UV space (0..1)
	if round:
		var n := 9
		for i in n:
			var a0 := TAU * i / n + rng.randf_range(-0.1, 0.1)
			var a1 := TAU * (i + 1) / n + rng.randf_range(-0.1, 0.1)
			pieces.append(PackedVector2Array([Vector2(0.5, 0.5), Vector2(0.5, 0.5) + Vector2(cos(a0), sin(a0)) * 0.5,
					Vector2(0.5, 0.5) + Vector2(cos((a0 + a1) * 0.5), sin((a0 + a1) * 0.5)) * 0.5, Vector2(0.5, 0.5) + Vector2(cos(a1), sin(a1)) * 0.5]))
	else:
		var cols := 3
		var rows := 4
		var pts := {}
		for y in rows + 1:
			for x in cols + 1:
				var j := Vector2(rng.randf_range(-0.08, 0.08), rng.randf_range(-0.06, 0.06)) if x > 0 and x < cols and y > 0 and y < rows else Vector2.ZERO
				pts[Vector2i(x, y)] = Vector2(float(x) / cols, float(y) / rows) + j
		for y in rows:
			for x in cols:
				var a: Vector2 = pts[Vector2i(x, y)]
				var b: Vector2 = pts[Vector2i(x + 1, y)]
				var c: Vector2 = pts[Vector2i(x + 1, y + 1)]
				var d: Vector2 = pts[Vector2i(x, y + 1)]
				if rng.randf() < 0.5: # two triangles per cell, split either way
					pieces.append(PackedVector2Array([a, b, c]))
					pieces.append(PackedVector2Array([a, c, d]))
				else:
					pieces.append(PackedVector2Array([a, b, d]))
					pieces.append(PackedVector2Array([b, c, d]))
	for poly in pieces:
		var centre := Vector2.ZERO
		for p in poly:
			centre += p
		centre /= poly.size()
		var shard := Node3D.new()
		shard.position = Vector3((centre.x - 0.5) * size.x, (0.5 - centre.y) * size.y, 0.0)
		add_child(shard)
		for k in layers.size():
			var mi := MeshInstance3D.new()
			mi.mesh = _piece_mesh(poly, centre, size)
			mi.material_override = layers[k]
			mi.position.z = 0.0003 * k
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			shard.add_child(mi)
		var out := Vector3(shard.position.x, shard.position.y, 0.0).normalized()
		if out.length() < 0.01:
			out = Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), 0).normalized()
		_shards.append({
			"node": shard,
			"vel": (out * rng.randf_range(0.35, 0.8) + Vector3(0, rng.randf_range(0.2, 0.6), rng.randf_range(0.1, 0.5))) * power,
			"spin": Vector3(rng.randf_range(-9, 9), rng.randf_range(-9, 9), rng.randf_range(-9, 9)),
		})


func _settle(delta: float) -> void:
	for s in _shards:
		if s.get("rest", false):
			continue
		var n: Node3D = s["node"]
		var v: Vector3 = s["vel"]
		v += global_basis.inverse() * Vector3(0, -GRAVITY, 0) * delta
		s["vel"] = v
		n.position += v * delta
		n.rotation += s["spin"] * delta
		if n.global_position.y <= _rest_y: # down on the table: lying flat, glinting
			var yaw := randf() * TAU
			n.global_transform = Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -PI * 0.5),
				Vector3(n.global_position.x, _rest_y, n.global_position.z))
			s["rest"] = true


## One shard: its outline in the card plane, UVs from the picture, both sides.
func _piece_mesh(poly: PackedVector2Array, centre: Vector2, size: Vector2) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(1, poly.size() - 1):
		for tri in [[0, i, i + 1], [0, i + 1, i]]: # front and back face
			for k in tri:
				var p: Vector2 = poly[k]
				st.set_uv(p)
				st.set_normal(Vector3.BACK)
				st.add_vertex(Vector3((p.x - centre.x) * size.x, (centre.y - p.y) * size.y, 0.0))
	return st.commit()


func _process(delta: float) -> void:
	_time += delta
	if _rest_y < INF:
		_settle(delta)
		return
	var fade := clampf(1.0 - (_time - LIFE * 0.6) / (LIFE * 0.4), 0.0, 1.0)
	for s in _shards:
		var n: Node3D = s["node"]
		var v: Vector3 = s["vel"]
		v += global_basis.inverse() * Vector3(0, -GRAVITY, 0) * delta
		s["vel"] = v
		n.position += v * delta
		n.rotation += s["spin"] * delta
		n.scale = Vector3.ONE * maxf(fade, 0.01)
	if _time >= LIFE:
		queue_free()
