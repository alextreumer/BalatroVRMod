extends SceneTree
## Builds jokers/j_popcorn.tscn: a red-and-white striped popcorn cup, open at the top, densely
## filled with popcorn flakes up to a dome over the rim. The flakes are children of "Popcorn",
## sorted from the bottom up, and the joker shows as many as its Mult allows (20 Mult = all):
## when Popcorn loses Mult each round, the top flakes pop away and the level sinks. Under the flakes
## a popcorn-coloured "Bed" sinks along (fill), so the empty cup bottom never shows through.
## Each flake is one merged mesh (8 shape variants), which keeps the draw calls low for VR.
##
##   Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tools/build_popcorn.gd
##
## Overwrites jokers/j_popcorn.tscn.

const OUT := "res://jokers/j_popcorn.tscn"
const CUP_HEIGHT := 0.07
const CUP_TOP := 0.033
const CUP_BOTTOM := 0.023
const FLAKES := 110
const DOME := 0.026          # how high the heap rises over the rim
const VARIANTS := 8

const CUP_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform vec3 red : source_color = vec3(0.86, 0.1, 0.12);
uniform vec3 white : source_color = vec3(0.97, 0.95, 0.9);
uniform float stripes = 12.0;

void fragment() {
	if (FRONT_FACING) {
		float s = step(0.5, fract(UV.x * stripes));
		ALBEDO = mix(white, red, s);
		ROUGHNESS = 0.55;
	} else {
		ALBEDO = white * 0.8; // the inside of the cup
		ROUGHNESS = 0.9;
	}
}
"""

var _rng := RandomNumberGenerator.new()
var _owner: Node3D
var _kernel: SphereMesh
var _hull: SphereMesh
var _mats: Array[StandardMaterial3D] = []
var _hull_mat: StandardMaterial3D
var _variants: Array[ArrayMesh] = []


func _initialize() -> void:
	_rng.seed = 2024
	_owner = Node3D.new()
	_owner.name = "j_popcorn"
	_owner.set_script(load("res://jokers/augmented_joker.gd"))
	_owner.set("count_parent", NodePath("Popcorn"))
	_owner.set("count_source", "ab[\"mult\"] / 20.0 * %d" % FLAKES)
	_owner.set("fill_node", NodePath("Bed"))
	_owner.set("fill_source", "ab[\"mult\"]")
	_owner.set("fill_max", 20.0)
	_owner.set("fill_min", 0.05)

	_kernel = SphereMesh.new()
	_kernel.radius = 0.5
	_kernel.height = 1.0
	_kernel.radial_segments = 8
	_kernel.rings = 4
	_hull = SphereMesh.new()
	_hull.radius = 0.5
	_hull.height = 0.6
	_hull.radial_segments = 6
	_hull.rings = 3
	for c in [Color(1.0, 0.96, 0.82), Color(0.99, 0.9, 0.62), Color(1.0, 0.98, 0.9)]:
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.85
		_mats.append(m)
	_hull_mat = StandardMaterial3D.new()
	_hull_mat.albedo_color = Color(0.55, 0.32, 0.12)
	_hull_mat.roughness = 0.6
	for i in VARIANTS:
		_variants.append(_flake_mesh(_mats[i % _mats.size()]))

	_build_cup()
	_build_bed()
	_build_heap()
	_build_spill()

	var scene := PackedScene.new()
	var err := scene.pack(_owner)
	if err == OK:
		err = ResourceSaver.save(scene, OUT)
	print("build_popcorn: ", "saved " + OUT if err == OK else "error %d" % err)
	_owner.free()
	quit()


func _add(node: Node, parent: Node) -> void:
	parent.add_child(node)
	node.owner = _owner


func _build_cup() -> void:
	var cup := MeshInstance3D.new()
	cup.name = "Cup"
	var mesh := CylinderMesh.new()
	mesh.top_radius = CUP_TOP
	mesh.bottom_radius = CUP_BOTTOM
	mesh.height = CUP_HEIGHT
	mesh.radial_segments = 48
	mesh.rings = 1
	mesh.cap_top = false # open: you look into the popcorn
	cup.mesh = mesh
	var mat := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = CUP_SHADER
	mat.shader = shader
	cup.material_override = mat
	cup.position.y = CUP_HEIGHT * 0.5
	_add(cup, _owner)

	var rim := MeshInstance3D.new()
	rim.name = "Rim"
	var torus := TorusMesh.new()
	torus.inner_radius = CUP_TOP - 0.0015
	torus.outer_radius = CUP_TOP + 0.0015
	torus.rings = 48
	torus.ring_segments = 8
	rim.mesh = torus
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.97, 0.95, 0.9)
	white.roughness = 0.5
	rim.material_override = white
	rim.position.y = CUP_HEIGHT
	_add(rim, _owner)


## One popcorn flake shape (about 1 unit across): lumpy kernels around a centre, merged into one
## mesh; some variants carry a brown hull bit as a second surface.
func _flake_mesh(mat: StandardMaterial3D) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lobes := 5 + _rng.randi() % 3
	for i in lobes:
		var dir := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized()
		var pos := dir * (0.0 if i == 0 else _rng.randf_range(0.42, 0.62))
		var s := 1.0 if i == 0 else _rng.randf_range(0.55, 0.85)
		var basis := Basis.from_euler(Vector3(_rng.randf() * TAU, _rng.randf() * TAU, 0))
		basis = basis.scaled(Vector3(s, s * _rng.randf_range(0.75, 1.1), s * _rng.randf_range(0.8, 1.1)))
		st.append_from(_kernel, 0, Transform3D(basis, pos))
	var mesh := st.commit()
	mesh.surface_set_material(0, mat)
	if _rng.randf() < 0.4:
		var hull := SurfaceTool.new()
		hull.begin(Mesh.PRIMITIVE_TRIANGLES)
		hull.append_from(_hull, 0, Transform3D(Basis.from_scale(Vector3.ONE * 0.45), Vector3(0, -0.45, 0)))
		hull.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _hull_mat)
	return mesh


func _flake(pos: Vector3, size: float) -> MeshInstance3D:
	var flake := MeshInstance3D.new()
	flake.mesh = _variants[_rng.randi() % _variants.size()]
	flake.position = pos
	flake.basis = Basis.from_euler(Vector3(_rng.randf() * TAU, _rng.randf() * TAU, _rng.randf() * TAU)).scaled(Vector3.ONE * size)
	return flake


## Inner radius of the cup at height y (minus a margin), or of the dome above the rim.
func _space_radius(y: float, margin: float) -> float:
	if y <= CUP_HEIGHT:
		return lerpf(CUP_BOTTOM, CUP_TOP, y / CUP_HEIGHT) - margin
	var h := (y - CUP_HEIGHT) / DOME
	return (CUP_TOP + 0.002) * sqrt(maxf(1.0 - h * h, 0.0))


## Popcorn-coloured filling under the flakes; the joker lowers it with the Mult ("fill").
func _build_bed() -> void:
	var bed := Node3D.new()
	bed.name = "Bed"
	_add(bed, _owner)
	var top := CUP_HEIGHT - 0.004
	var mesh := CylinderMesh.new()
	# straight, as narrow as the cup bottom: squashed by the fill it must never poke through the
	# tapered cup wall
	mesh.top_radius = CUP_BOTTOM - 0.0015
	mesh.bottom_radius = CUP_BOTTOM - 0.0015
	mesh.height = top
	mesh.radial_segments = 32
	mesh.rings = 1
	var surface := MeshInstance3D.new()
	surface.name = "Filling"
	surface.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.93, 0.82, 0.55)
	mat.roughness = 0.95
	surface.material_override = mat
	surface.position.y = top * 0.5
	_add(surface, bed)


## Flakes from low in the cup up to a dome above the rim, packed tightly, sorted bottom-up.
func _build_heap() -> void:
	var points: Array[Vector3] = []
	var tries := 0
	while points.size() < FLAKES and tries < 40000:
		tries += 1
		var y := _rng.randf_range(0.012, CUP_HEIGHT + DOME)
		var r_max := _space_radius(y, 0.0078) # keeps the bumpy flakes inside the cup wall
		if r_max <= 0.0:
			continue
		var a := _rng.randf() * TAU
		var r := sqrt(_rng.randf()) * r_max
		var p := Vector3(cos(a) * r, y, sin(a) * r)
		var free := true
		for q in points:
			if q.distance_to(p) < 0.0082:
				free = false
				break
		if free:
			points.append(p)
	points.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.y < b.y)

	var heap := Node3D.new()
	heap.name = "Popcorn"
	_add(heap, _owner)
	for i in points.size():
		var f := _flake(points[i], _rng.randf_range(0.0075, 0.0095))
		f.name = "Flake%03d" % (i + 1)
		_add(f, heap)
	print("build_popcorn: %d flakes" % points.size())


## A few flakes that fell next to the cup (always there, they don't count).
func _build_spill() -> void:
	var spill := Node3D.new()
	spill.name = "Spilled"
	_add(spill, _owner)
	for a in [0.6, 2.4, 4.3]:
		_add(_flake(Vector3(cos(a) * 0.03, 0.004, sin(a) * 0.03), 0.0075), spill)
