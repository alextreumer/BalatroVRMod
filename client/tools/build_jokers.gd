extends SceneTree
## Builds the detailed augmented joker scenes (jokers/j_<key>.tscn) from code: a small toolkit
## (lathe, extrusion, swept tubes, a reusable Jimbo figure) and one function per joker.
## Every scene keeps the node names its AugmentedJoker settings point at, so the live effects
## (fill, count, suit, text, glow, see-through, motion) keep working.
##
##   Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tools/build_jokers.gd
##   ... --script res://tools/build_jokers.gd -- castle obelisk     (only these)
##
## Overwrites the scenes it builds. Popcorn has its own builder (build_popcorn.gd); Runner is
## left as it is.

const AJ := "res://jokers/augmented_joker.gd"
const SUIT_SHAPE := "res://jokers/suit_shape.gd"
const WINDING := 1.0 # flip to -1.0 if faces come out inside-out

var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	var builders := {
		"campfire": _campfire, "ancient": _ancient, "ice_cream": _ice_cream, "banner": _banner,
		"loyalty_card": _loyalty_card, "wee": _wee, "invisible": _invisible, "gros_michel": _gros_michel,
		"lucky_cat": _lucky_cat, "cavendish": _cavendish, "mail": _mail, "ride_the_bus": _ride_the_bus,
		"castle": _castle, "green_joker": _green_joker, "obelisk": _obelisk, "turtle_bean": _turtle_bean,
		"ramen": _ramen, "hologram": _hologram, "todo_list": _todo_list, "square": _square,
		"selzer": _selzer, "idol": _idol, "jimbo_companion": _jimbo_companion,
	}
	var only := OS.get_cmdline_user_args()
	for key in builders:
		if not only.is_empty() and not only.has(key):
			continue
		_rng.seed = hash(key)
		var root: Node3D = builders[key].call()
		_save(root, key)
	quit()


# ================================================================ scene helpers

func _begin(key: String, props: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "j_" + key
	root.set_script(load(AJ))
	for k in props:
		root.set(k, props[k])
	return root


func _save(root: Node3D, key: String) -> void:
	_own(root, root)
	var scene := PackedScene.new()
	var err := scene.pack(root)
	var path := ("res://jokers/%s.tscn" if key == "jimbo_companion" else "res://jokers/j_%s.tscn") % key
	if err == OK:
		err = ResourceSaver.save(scene, path)
	print("build_jokers: %s %s" % [path, "ok" if err == OK else "ERROR %d" % err])
	root.free()


func _own(node: Node, owner: Node) -> void:
	for child in node.get_children():
		child.owner = owner
		_own(child, owner)


func _node(parent: Node, name: String, pos := Vector3.ZERO) -> Node3D:
	var n := Node3D.new()
	n.name = name
	n.position = pos
	parent.add_child(n)
	return n


func _mi(parent: Node, mesh: Mesh, mat: Material, pos := Vector3.ZERO, rot_deg := Vector3.ZERO,
		scl := Vector3.ONE, name := "") -> MeshInstance3D:
	var m := MeshInstance3D.new()
	if name != "":
		m.name = name
	m.mesh = mesh
	m.material_override = mat
	m.position = pos
	m.rotation_degrees = rot_deg
	m.scale = scl
	parent.add_child(m)
	return m


## A floating value text above the joker (billboard), filled in live by the joker script.
func _value_label(parent: Node, name: String, y: float) -> Label3D:
	var l := Label3D.new()
	l.name = name
	l.text = "?"
	l.position = Vector3(0, y, 0)
	l.pixel_size = 0.0005
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font_size = 36
	l.outline_size = 8
	parent.add_child(l)
	return l


## Printed text lying on a surface (not turning to the player).
func _print(parent: Node, text: String, pos: Vector3, rot_deg: Vector3, pixel: float, colour: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.rotation_degrees = rot_deg
	l.pixel_size = pixel
	l.font_size = 48
	l.modulate = colour
	l.outline_size = 0
	parent.add_child(l)
	return l


func _suit_shapes(parent: Node, name: String, pos: Vector3, size: float, depth: float, mat: Material) -> Node3D:
	var holder := _node(parent, name, pos)
	for suit in ["Hearts", "Diamonds", "Clubs", "Spades"]:
		var s := CSGCombiner3D.new()
		s.name = suit
		s.set_script(load(SUIT_SHAPE))
		s.set("suit", suit)
		s.set("size", size)
		s.set("depth", depth)
		s.material_override = mat
		s.visible = suit == "Spades"
		holder.add_child(s)
	return holder


## Basis whose Y axis points along `dir` (to orient cylinders).
func _align_y(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var helper := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := y.cross(helper).normalized()
	var z := x.cross(y)
	return Basis(x, y, z)


## A cylinder from a to b.
func _rod(parent: Node, a: Vector3, b: Vector3, r: float, mat: Material, seg := 12) -> MeshInstance3D:
	var m := _mi(parent, _cyl(r, r, a.distance_to(b), seg), mat)
	m.transform = Transform3D(_align_y(b - a), (a + b) * 0.5)
	return m


# ================================================================ materials

func _mat(c: Color, rough := 0.7, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _glowing(c: Color, energy := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m


func _see_through(c: Color, alpha: float, rough := 0.15) -> StandardMaterial3D:
	var m := _mat(Color(c.r, c.g, c.b, alpha), rough)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _gold() -> StandardMaterial3D:
	var m := _mat(Color(0.9, 0.68, 0.25), 0.3, 0.7)
	m.emission_enabled = true
	m.emission = Color(0.9, 0.68, 0.25)
	m.emission_energy_multiplier = 0.15
	return m


func _shader_mat(code: String) -> ShaderMaterial:
	var s := Shader.new()
	s.code = code
	var m := ShaderMaterial.new()
	m.shader = s
	return m


# ================================================================ meshes

func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


func _sph(r: float, h := -1.0, seg := 16) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0 if h < 0.0 else h
	m.radial_segments = seg
	m.rings = maxi(seg / 2, 4)
	return m


func _cyl(top: float, bottom: float, h: float, seg := 16) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	m.radial_segments = seg
	m.rings = 1
	return m


func _torus(inner: float, outer: float, rings := 24, seg := 8) -> TorusMesh:
	var m := TorusMesh.new()
	m.inner_radius = inner
	m.outer_radius = outer
	m.rings = rings
	m.ring_segments = seg
	return m


## Adds one triangle with explicit normals; turns it so it faces where its normals point.
func _tri(st: SurfaceTool, a: Array, b: Array, c: Array) -> void:
	var face: Vector3 = (b[0] - a[0]).cross(c[0] - a[0])
	var n: Vector3 = a[1] + b[1] + c[1]
	if face.dot(n) * WINDING > 0.0:
		var t := b
		b = c
		c = t
	for v in [a, b, c]:
		st.set_normal(v[1])
		if v.size() > 2:
			st.set_uv(v[2])
		st.add_vertex(v[0])


func _quad(st: SurfaceTool, a: Array, b: Array, c: Array, d: Array) -> void:
	_tri(st, a, b, c)
	_tri(st, a, c, d)


## Surface of revolution around Y. `profile` = (radius, height) points; normals face to the
## left of the walking direction, i.e. outwards when the profile climbs up the outside.
func _lathe(profile: PackedVector2Array, seg := 24, offset_deg := 0.0, sweep_deg := 360.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var m := profile.size()
	var normals: Array[Vector2] = []
	for j in m:
		var prev := profile[maxi(j - 1, 0)]
		var next := profile[mini(j + 1, m - 1)]
		var t := (next - prev).normalized()
		normals.append(Vector2(t.y, -t.x))
	var rings: Array = []
	for i in seg + 1:
		var a := deg_to_rad(offset_deg + sweep_deg * i / seg)
		var ring: Array = []
		for j in m:
			var p := profile[j]
			var n2: Vector2 = normals[j]
			ring.append([Vector3(p.x * cos(a), p.y, p.x * sin(a)),
					Vector3(n2.x * cos(a), n2.y, n2.x * sin(a)).normalized(),
					Vector2(float(i) / seg, float(j) / (m - 1))])
		rings.append(ring)
	for i in seg:
		for j in m - 1:
			_quad(st, rings[i][j], rings[i + 1][j], rings[i + 1][j + 1], rings[i][j + 1])
	return st.commit()


## A flat outline pulled to a slab of `depth` (centred on z = 0).
func _extrude(poly: PackedVector2Array, depth: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var idx := Geometry2D.triangulate_polygon(poly)
	var hz := depth * 0.5
	for k in range(0, idx.size(), 3):
		var p := [poly[idx[k]], poly[idx[k + 1]], poly[idx[k + 2]]]
		_tri(st, [Vector3(p[0].x, p[0].y, hz), Vector3.BACK], [Vector3(p[1].x, p[1].y, hz), Vector3.BACK],
				[Vector3(p[2].x, p[2].y, hz), Vector3.BACK])
		_tri(st, [Vector3(p[0].x, p[0].y, -hz), Vector3.FORWARD], [Vector3(p[1].x, p[1].y, -hz), Vector3.FORWARD],
				[Vector3(p[2].x, p[2].y, -hz), Vector3.FORWARD])
	var area := 0.0
	for i in poly.size():
		var q := poly[(i + 1) % poly.size()]
		area += poly[i].x * q.y - q.x * poly[i].y
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var e := b - a
		var n2 := Vector2(e.y, -e.x) if area > 0.0 else Vector2(-e.y, e.x)
		var n := Vector3(n2.x, n2.y, 0).normalized()
		_quad(st, [Vector3(a.x, a.y, hz), n], [Vector3(b.x, b.y, hz), n], [Vector3(b.x, b.y, -hz), n], [Vector3(a.x, a.y, -hz), n])
	return st.commit()


## A tube along `path` with a radius per point (closed with caps).
func _sweep(path: Array, radii: Array, seg := 8) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := path.size()
	var rings: Array = []
	var x := Vector3.ZERO
	var tangents: Array = []
	for i in n:
		var t: Vector3
		if i == 0:
			t = path[1] - path[0]
		elif i == n - 1:
			t = path[i] - path[i - 1]
		else:
			t = path[i + 1] - path[i - 1]
		t = t.normalized()
		tangents.append(t)
		if i == 0:
			x = t.cross(Vector3.UP if absf(t.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT).normalized()
		else:
			x = (x - t * x.dot(t)).normalized() # carried along without twisting
		var y := t.cross(x)
		var ring: Array = []
		for k in seg:
			var a := TAU * k / seg
			var d := x * cos(a) + y * sin(a)
			ring.append([path[i] + d * float(radii[i]), d])
		rings.append(ring)
	for i in n - 1:
		for k in seg:
			var k2 := (k + 1) % seg
			_quad(st, rings[i][k], rings[i][k2], rings[i + 1][k2], rings[i + 1][k])
	for end in [0, n - 1]:
		var nrm: Vector3 = -tangents[0] if end == 0 else tangents[n - 1]
		var centre: Vector3 = path[end]
		for k in seg:
			_tri(st, [centre, nrm], [rings[end][k][0], nrm], [rings[end][(k + 1) % seg][0], nrm])
	return st.commit()


func _circle_poly(r: float, n := 24, centre := Vector2.ZERO) -> PackedVector2Array:
	var p := PackedVector2Array()
	for i in n:
		var a := TAU * i / n
		p.append(centre + Vector2(cos(a), sin(a)) * r)
	return p


## Rectangle with rounded corners.
func _rounded_rect(w: float, h: float, r: float) -> PackedVector2Array:
	var p := PackedVector2Array()
	var corners := [Vector2(w / 2 - r, h / 2 - r), Vector2(-w / 2 + r, h / 2 - r), Vector2(-w / 2 + r, -h / 2 + r), Vector2(w / 2 - r, -h / 2 + r)]
	for c in 4:
		for i in 5:
			var a := PI / 2 * c + PI / 2 * i / 4.0
			p.append(corners[c] + Vector2(cos(a), sin(a)) * r)
	return p


# ================================================================ shared models

## Jimbo, Balatro's jester: harlequin body, white face, ruff, a two-horned hat with bells.
## About 0.11 m tall at s = 1. `override` replaces every material (e.g. a hologram).
func _jester(parent: Node, name: String, s: float, col_a := Color(0.85, 0.15, 0.2),
		col_b := Color(0.16, 0.36, 0.85), override: Material = null) -> Node3D:
	var j := _node(parent, name)
	var a := override if override != null else _mat(col_a, 0.6)
	var b := override if override != null else _mat(col_b, 0.6)
	var face := override if override != null else _mat(Color(0.97, 0.95, 0.92), 0.5)
	var dark := override if override != null else _mat(Color(0.08, 0.08, 0.1), 0.4)
	var bell := override if override != null else _gold()
	var cheek := override if override != null else _mat(Color(0.95, 0.4, 0.45), 0.6)
	# legs and shoes
	_mi(j, _cyl(0.0065 * s, 0.006 * s, 0.03 * s, 10), a, Vector3(-0.0075 * s, 0.017 * s, 0))
	_mi(j, _cyl(0.0065 * s, 0.006 * s, 0.03 * s, 10), b, Vector3(0.0075 * s, 0.017 * s, 0))
	_mi(j, _sph(0.0075 * s), dark, Vector3(-0.0075 * s, 0.003 * s, 0.003 * s), Vector3.ZERO, Vector3(1, 0.6, 1.4))
	_mi(j, _sph(0.0075 * s), dark, Vector3(0.0075 * s, 0.003 * s, 0.003 * s), Vector3.ZERO, Vector3(1, 0.6, 1.4))
	# body: harlequin halves in the two colours
	var torso := PackedVector2Array([Vector2(0, 0), Vector2(0.016, 0.002), Vector2(0.018, 0.016),
			Vector2(0.015, 0.03), Vector2(0.008, 0.038), Vector2(0, 0.039)])
	_mi(j, _lathe(torso, 10, 90.0, 180.0), a, Vector3(0, 0.03 * s, 0), Vector3.ZERO, Vector3.ONE * s)
	_mi(j, _lathe(torso, 10, -90.0, 180.0), b, Vector3(0, 0.03 * s, 0), Vector3.ZERO, Vector3.ONE * s)
	# buttons
	for i in 3:
		_mi(j, _sph(0.0024 * s), bell, Vector3(0, (0.04 + i * 0.008) * s, 0.0172 * s))
	# ruff collar
	_mi(j, _torus(0.004 * s, 0.017 * s, 16, 6), face, Vector3(0, 0.07 * s, 0), Vector3.ZERO, Vector3(1, 0.45, 1))
	# arms with white gloves
	for side in [-1.0, 1.0]:
		var sh := Vector3(side * 0.017, 0.062, 0) * s
		var hand := Vector3(side * 0.027, 0.04, 0.006) * s
		_rod(j, sh, hand, 0.0045 * s, a if side < 0 else b, 8)
		_mi(j, _sph(0.005 * s), face, hand)
	# head
	_mi(j, _sph(0.0135 * s, -1, 20), face, Vector3(0, 0.086 * s, 0))
	for side in [-1.0, 1.0]:
		_mi(j, _sph(0.0022 * s), dark, Vector3(side * 0.005, 0.089, 0.0122) * s, Vector3.ZERO, Vector3(1, 1.4, 0.6))
		_mi(j, _sph(0.0028 * s), cheek, Vector3(side * 0.0075, 0.082, 0.0105) * s, Vector3.ZERO, Vector3(1, 0.7, 0.5))
	_mi(j, _box(Vector3(0.008, 0.0016, 0.002) * s), dark, Vector3(0, 0.0795, 0.0128) * s) # smile
	# hat: a band and two drooping horns ending in bells
	_mi(j, _torus(0.011 * s, 0.0145 * s, 20, 6), a, Vector3(0, 0.094 * s, 0), Vector3(-8, 0, 0))
	_mi(j, _sph(0.0128 * s, 0.013 * s), b, Vector3(0, 0.097 * s, -0.001 * s))
	for side in [-1.0, 1.0]:
		var path: Array = []
		var radii: Array = []
		for i in 9:
			var t := i / 8.0
			path.append(Vector3(side * (0.004 + 0.026 * t), 0.1 + 0.022 * sin(t * PI * 0.8) - 0.012 * t * t, -0.002) * s)
			radii.append(lerpf(0.0085, 0.0018, t) * s)
		_mi(j, _sweep(path, radii, 10), a if side < 0 else b)
		_mi(j, _sph(0.0042 * s), bell, path[8])
	return j


## A banana: a curved, six-sided tube with brown tips and a stem.
func _banana_mesh(length: float) -> ArrayMesh:
	var path: Array = []
	var radii: Array = []
	var bend := 1.5
	var r_arc := length / bend
	for i in 13:
		var t := i / 12.0
		var a := -bend / 2.0 + bend * t
		path.append(Vector3(sin(a) * r_arc, r_arc - cos(a) * r_arc, 0))
		radii.append(length * 0.085 * pow(sin(PI * clampf(t * 0.94 + 0.03, 0.0, 1.0)), 0.55) + 0.0012)
	return _sweep(path, radii, 6)


func _banana(parent: Node, length: float, peel: Color, pos: Vector3, rot_deg: Vector3) -> Node3D:
	var b := _node(parent, "Piece", pos)
	b.rotation_degrees = rot_deg
	var mesh := _banana_mesh(length)
	_mi(b, mesh, _mat(peel, 0.45))
	var r_arc := length / 1.5
	var tip := _mat(Color(0.3, 0.2, 0.1), 0.6)
	var a := 0.75
	_mi(b, _sph(0.0028), tip, Vector3(sin(a) * r_arc, r_arc - cos(a) * r_arc, 0))
	var stem_base := Vector3(-sin(a) * r_arc, r_arc - cos(a) * r_arc, 0)
	_rod(b, stem_base, stem_base + Vector3(-0.007, 0.006, 0), 0.0028, _mat(Color(0.45, 0.5, 0.2), 0.7), 6)
	return b


# ================================================================ the jokers

func _campfire() -> Node3D:
	var j := _begin("campfire", {"fill_node": NodePath("Fill"), "fill_source": "ab[\"x_mult\"] - 1.0",
			"fill_max": 3.0, "fill_min": 0.4, "glow_node": NodePath("Fill"), "glow_energy": 2.5,
			"shake_node": NodePath("Fill/Flames")})
	_mi(j, _cyl(0.027, 0.028, 0.003, 20), _mat(Color(0.18, 0.16, 0.15), 0.95), Vector3(0, 0.0015, 0))
	for i in 9:
		var a := TAU * i / 9.0
		var g := _rng.randf_range(0.38, 0.55)
		_mi(j, _sph(0.0085, -1, 10), _mat(Color(g, g * 0.97, g * 0.93), 0.9), Vector3(cos(a) * 0.03, 0.005, sin(a) * 0.03),
				Vector3(0, rad_to_deg(a), 0), Vector3(1.35, 0.8, 1.0))
	var wood := _mat(Color(0.42, 0.25, 0.12), 0.85)
	var cut := _mat(Color(0.78, 0.6, 0.38), 0.8)
	for i in 4:
		var a := TAU * i / 4.0 + 0.4
		var foot := Vector3(cos(a) * 0.024, 0.003, sin(a) * 0.024)
		var top := Vector3(cos(a) * 0.003, 0.04, sin(a) * 0.003)
		_rod(j, foot, top, 0.0045, wood, 8)
		_rod(j, foot - (top - foot).normalized() * 0.0012, foot, 0.0042, cut, 8)
	var fill := _node(j, "Fill", Vector3(0, 0.006, 0))
	var flames := _node(fill, "Flames")
	var flame := PackedVector2Array([Vector2(0, 0), Vector2(0.015, 0.008), Vector2(0.018, 0.02), Vector2(0.013, 0.036),
			Vector2(0.006, 0.054), Vector2(0, 0.075)])
	var lathe := _lathe(flame, 12)
	_mi(flames, lathe, _see_through(Color(1.0, 0.3, 0.05), 0.75), Vector3.ZERO, Vector3.ZERO, Vector3(1.15, 1.0, 1.15))
	_mi(flames, lathe, _glowing(Color(1.0, 0.4, 0.08), 1.5), Vector3.ZERO, Vector3(0, 60, 0), Vector3(0.9, 0.92, 0.9))
	_mi(flames, lathe, _glowing(Color(1.0, 0.75, 0.15), 1.8), Vector3(0, 0.002, 0), Vector3(0, 30, 0), Vector3(0.7, 0.78, 0.7))
	_mi(flames, lathe, _glowing(Color(1.0, 0.95, 0.7), 2.0), Vector3(0, 0.003, 0), Vector3.ZERO, Vector3(0.4, 0.5, 0.4))
	for i in 3: # little side flames
		var a := TAU * i / 3.0 + 1.0
		_mi(flames, lathe, _glowing(Color(1.0, 0.5, 0.1), 1.5), Vector3(cos(a) * 0.009, 0.0, sin(a) * 0.009),
				Vector3(cos(a) * 15, 0, sin(a) * 15), Vector3(0.45, 0.55, 0.45))
	for i in 5:
		var a := _rng.randf() * TAU
		_mi(fill, _sph(0.0013, -1, 6), _glowing(Color(1.0, 0.55, 0.1), 3.0),
				Vector3(cos(a) * 0.012, _rng.randf_range(0.065, 0.085), sin(a) * 0.012))
	return j


func _ancient() -> Node3D:
	var j := _begin("ancient", {"suit_node": NodePath("Gem"), "suit_shapes": NodePath("Gem"),
			"glow_node": NodePath("Gem"), "glow_energy": 1.6})
	var stone := _mat(Color(0.62, 0.55, 0.42), 0.95)
	var dark_stone := _mat(Color(0.42, 0.37, 0.28), 0.95)
	_mi(j, _box(Vector3(0.08, 0.012, 0.032)), dark_stone, Vector3(0, 0.006, 0))
	var arch := PackedVector2Array([Vector2(-0.032, 0), Vector2(0.032, 0)])
	for i in 13:
		var a := PI * i / 12.0
		arch.append(Vector2(cos(a) * 0.032, 0.058 + sin(a) * 0.032))
	_mi(j, _extrude(arch, 0.016), stone, Vector3(0, 0.012, 0), Vector3.ZERO, Vector3.ONE, "Tablet")
	var inner := PackedVector2Array()
	for p in arch:
		inner.append(Vector2(p.x * 0.84, 0.004 + p.y * 0.9))
	_mi(j, _extrude(inner, 0.0165), dark_stone, Vector3(0, 0.012, 0))
	_mi(j, _extrude(arch, 0.0168), stone, Vector3(0, 0.012, 0), Vector3.ZERO, Vector3(0.8, 0.88, 1.0)) # raised face inside the border
	# carved glyph rows below the gem
	for row in 3:
		for col in 4:
			var w := _rng.randf_range(0.004, 0.009)
			_mi(j, _box(Vector3(w, 0.0025, 0.002)), dark_stone, Vector3(-0.015 + col * 0.01, 0.02 + row * 0.007, 0.0085))
	_mi(j, _torus(0.0175, 0.0215, 24, 6), _gold(), Vector3(0, 0.07, 0.009), Vector3(90, 0, 0), Vector3.ONE, "Setting")
	_suit_shapes(j, "Gem", Vector3(0, 0.07, 0.0115), 0.027, 0.008, _mat(Color(0.95, 0.95, 0.92), 0.2))
	return j


const WAFFLE := """
shader_type spatial;
void fragment() {
	float a = abs(fract(UV.x * 14.0 + UV.y * 5.0) - 0.5);
	float b = abs(fract(UV.x * 14.0 - UV.y * 5.0) - 0.5);
	float line = 1.0 - smoothstep(0.06, 0.12, min(a, b));
	ALBEDO = mix(vec3(0.86, 0.62, 0.32), vec3(0.6, 0.36, 0.15), line);
	ROUGHNESS = 0.8;
}
"""


func _ice_cream() -> Node3D:
	var j := _begin("ice_cream", {"fill_node": NodePath("Fill"), "fill_source": "extra[\"chips\"]",
			"fill_max": 100.0, "fill_min": 0.12, "fill_uniform": true})
	var gold := _gold()
	_mi(j, _torus(0.014, 0.0165, 24, 6), gold, Vector3(0, 0.03, 0))
	for i in 3:
		var a := TAU * i / 3.0
		_rod(j, Vector3(cos(a) * 0.022, 0.0, sin(a) * 0.022), Vector3(cos(a) * 0.0155, 0.03, sin(a) * 0.0155), 0.0013, gold, 6)
	var cone := PackedVector2Array([Vector2(0, 0.008), Vector2(0.006, 0.02), Vector2(0.0175, 0.068), Vector2(0.0195, 0.072), Vector2(0.0185, 0.074)])
	_mi(j, _lathe(cone, 24), _shader_mat(WAFFLE), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, "Cone")
	var fill := _node(j, "Fill", Vector3(0, 0.072, 0))
	var cream := _mat(Color(0.98, 0.72, 0.8), 0.55)
	_mi(fill, _sph(0.021, -1, 20), cream, Vector3(0, 0.014, 0), Vector3.ZERO, Vector3.ONE, "Scoop")
	for i in 10: # the lumpy drippy rim of the scoop
		var a := TAU * i / 10.0
		_mi(fill, _sph(0.0065, -1, 10), cream, Vector3(cos(a) * 0.017, 0.003 - (i % 3) * 0.002, sin(a) * 0.017))
	var sprinkles := [Color(0.3, 0.6, 1.0), Color(1.0, 0.85, 0.2), Color(0.4, 0.85, 0.4), Color(1, 1, 1), Color(0.6, 0.3, 0.9)]
	for i in 22:
		var u := _rng.randf_range(0.25, 1.0)
		var a := _rng.randf() * TAU
		var dir := Vector3(cos(a) * sqrt(1.0 - u * u), u, sin(a) * sqrt(1.0 - u * u))
		var m := _mi(fill, _box(Vector3(0.0045, 0.0012, 0.0012)), _mat(sprinkles[i % sprinkles.size()], 0.5),
				Vector3(0, 0.014, 0) + dir * 0.0208)
		m.rotation = Vector3(_rng.randf() * TAU, _rng.randf() * TAU, 0)
	_mi(fill, _sph(0.0055, -1, 12), _mat(Color(0.85, 0.05, 0.1), 0.25), Vector3(0, 0.0395, 0))
	_rod(fill, Vector3(0, 0.044, 0), Vector3(0.004, 0.054, 0), 0.0006, _mat(Color(0.3, 0.45, 0.15)), 5)
	return j


func _banner() -> Node3D:
	var j := _begin("banner", {"count_parent": NodePath("Cloth/Stripes"), "count_source": "run[\"discards_left\"]",
			"empty_source": "run[\"discards_left\"]", "show_when_empty": NodePath("WhiteFlag"),
			"hide_when_empty": NodePath("Cloth")})
	var wood := _mat(Color(0.4, 0.24, 0.12), 0.7)
	var gold := _gold()
	_mi(j, _cyl(0.014, 0.017, 0.008, 16), wood, Vector3(-0.022, 0.004, 0))
	_mi(j, _cyl(0.0025, 0.0025, 0.15, 10), wood, Vector3(-0.022, 0.08, 0), Vector3.ZERO, Vector3.ONE, "Pole")
	_mi(j, _sph(0.0055), gold, Vector3(-0.022, 0.158, 0))
	_rod(j, Vector3(-0.026, 0.146, 0), Vector3(0.034, 0.146, 0), 0.0018, gold, 8)
	var cloth_poly := PackedVector2Array([Vector2(0, 0), Vector2(0.05, 0), Vector2(0.05, -0.085), Vector2(0.025, -0.07), Vector2(0, -0.085)])
	var cloth := _mi(j, _extrude(cloth_poly, 0.002), _mat(Color(0.75, 0.1, 0.15), 0.85), Vector3(-0.019, 0.144, 0),
			Vector3.ZERO, Vector3.ONE, "Cloth")
	_mi(cloth, _box(Vector3(0.05, 0.003, 0.0026)), gold, Vector3(0.025, -0.004, 0))
	var stripes := _node(cloth, "Stripes")
	for i in 5:
		_mi(stripes, _box(Vector3(0.042, 0.0055, 0.003)), _mat(Color(0.98, 0.85, 0.3), 0.5),
				Vector3(0.025, -0.014 - i * 0.011, 0), Vector3.ZERO, Vector3.ONE, "Stripe%d" % (i + 1))
	var white := PackedVector2Array([Vector2(0, 0), Vector2(0.045, -0.004), Vector2(0.05, -0.016), Vector2(0.044, -0.03), Vector2(0, -0.034)])
	var flag := _mi(j, _extrude(white, 0.0015), _mat(Color(0.97, 0.97, 0.95), 0.8), Vector3(-0.019, 0.142, 0),
			Vector3.ZERO, Vector3.ONE, "WhiteFlag")
	flag.visible = false
	return j


func _loyalty_card() -> Node3D:
	var j := _begin("loyalty_card", {"count_parent": NodePath("Stamps"),
			"count_source": "extra[\"every\"] - ab[\"loyalty_remaining\"]", "glow_node": NodePath("Card"),
			"glow_source": "1.0 - min(ab[\"loyalty_remaining\"], 1.0)", "glow_energy": 1.5})
	var wood := _mat(Color(0.4, 0.24, 0.12), 0.7)
	_mi(j, _box(Vector3(0.07, 0.006, 0.03)), wood, Vector3(0, 0.003, 0))
	_mi(j, _box(Vector3(0.07, 0.008, 0.004)), wood, Vector3(0, 0.01, 0.01))
	var tilt := Vector3(-14, 0, 0)
	var card_pos := Vector3(0, 0.046, 0.002)
	var card := _mi(j, _extrude(_rounded_rect(0.085, 0.06, 0.006), 0.003), _mat(Color(0.97, 0.94, 0.86), 0.6),
			card_pos, tilt, Vector3.ONE, "Card")
	_mi(card, _box(Vector3(0.082, 0.016, 0.0034)), _mat(Color(0.8, 0.12, 0.16), 0.6), Vector3(0, 0.019, 0))
	_print(card, "LOYALTY", Vector3(0, 0.019, 0.0019), Vector3.ZERO, 0.00032, Color(1, 0.9, 0.6))
	var ring := _mat(Color(0.6, 0.55, 0.5), 0.6)
	var stamps := _node(j, "Stamps", card_pos)
	stamps.rotation_degrees = tilt
	for i in 5:
		var x := -0.032 + i * 0.016
		_mi(card, _torus(0.0058, 0.0068, 16, 4), ring, Vector3(x, -0.008, 0.0016), Vector3(90, 0, 0))
		var stamp := _node(stamps, "Stamp%d" % (i + 1), Vector3(x, -0.008, 0.0019))
		_mi(stamp, _cyl(0.0056, 0.0056, 0.001, 16), _mat(Color(0.82, 0.1, 0.15), 0.6), Vector3.ZERO, Vector3(90, 0, 0))
		_mi(stamp, _extrude(_star(0.0038, 0.0016), 0.0013), _mat(Color(1, 0.85, 0.85), 0.6), Vector3(0, 0, 0.0004))
	_print(card, "x4", Vector3(0.033, -0.021, 0.0019), Vector3.ZERO, 0.00026, Color(0.8, 0.12, 0.16))
	return j


func _star(outer: float, inner: float) -> PackedVector2Array:
	var p := PackedVector2Array()
	for i in 10:
		var a := PI / 2 + PI * i / 5.0
		p.append(Vector2(cos(a), sin(a)) * (outer if i % 2 == 0 else inner))
	return p


func _wee() -> Node3D:
	var j := _begin("wee", {"label_node": NodePath("Value"), "label_source": "extra[\"chips\"]", "label_format": "+%d Chips"})
	_jester(j, "Jimbo", 0.55)
	# a big "2" card behind the little fellow (Wee Joker loves twos)
	var card := _mi(j, _extrude(_rounded_rect(0.034, 0.048, 0.003), 0.0015), _mat(Color(0.97, 0.96, 0.92), 0.6),
			Vector3(0.014, 0.024, -0.016), Vector3(0, -15, 8))
	_print(card, "2", Vector3(0, 0.002, 0.001), Vector3.ZERO, 0.0006, Color(0.85, 0.1, 0.15))
	_value_label(j, "Value", 0.085)
	return j


func _invisible() -> Node3D:
	var j := _begin("invisible", {"alpha_node": NodePath("Figure"),
			"alpha_source": "0.15 + 0.85 * min(ab[\"invis_rounds\"] / 2.0, 1.0)"})
	_jester(j, "Figure", 1.0, Color(0.55, 0.55, 0.6), Color(0.3, 0.3, 0.36))
	return j


func _gros_michel() -> Node3D:
	var j := _begin("gros_michel", {"shake_node": NodePath("Banana")})
	var holder := _node(j, "Banana", Vector3(0, 0.008, 0))
	_banana(holder, 0.1, Color(0.98, 0.84, 0.2), Vector3(0, 0, 0), Vector3(0, 20, -6))
	_mi(holder, _cyl(0.0055, 0.0055, 0.0008, 16), _mat(Color(0.15, 0.35, 0.8), 0.5), Vector3(-0.004, 0.0035, 0.0088),
			Vector3(90, 20, 0)) # the sticker
	# brown spots: this banana is getting old
	for i in 4:
		_mi(holder, _sph(0.0016, -1, 6), _mat(Color(0.35, 0.22, 0.1), 0.7),
				Vector3(-0.025 + i * 0.016, 0.006 + abs(i - 1.5) * 0.004, 0.007))
	return j


func _lucky_cat() -> Node3D:
	var j := _begin("lucky_cat", {"label_node": NodePath("Value"), "label_source": "ab[\"x_mult\"]",
			"label_format": "x%.2f", "glow_node": NodePath("Body"), "glow_source": "(ab[\"x_mult\"] - 1.0) / 3.0"})
	var body := _node(j, "Body")
	var white := _mat(Color(0.97, 0.96, 0.93), 0.5)
	var red := _mat(Color(0.85, 0.1, 0.12), 0.5)
	var dark := _mat(Color(0.08, 0.08, 0.1), 0.5)
	var pink := _mat(Color(0.98, 0.6, 0.65), 0.6)
	var gold := _gold()
	_mi(body, _sph(0.026, -1, 20), white, Vector3(0, 0.026, 0), Vector3.ZERO, Vector3(1.0, 1.05, 0.88))
	_mi(body, _sph(0.021, -1, 20), white, Vector3(0, 0.068, 0.002), Vector3.ZERO, Vector3(1.08, 0.95, 0.95))
	for side in [-1.0, 1.0]:
		_mi(body, _cyl(0.0005, 0.0075, 0.013, 10), white, Vector3(side * 0.012, 0.087, 0), Vector3(0, 0, -side * 22))
		_mi(body, _cyl(0.0003, 0.0045, 0.009, 8), pink, Vector3(side * 0.012, 0.0865, 0.0018), Vector3(0, 0, -side * 22))
		# closed happy eyes: little arcs
		_mi(body, _torus(0.0026, 0.0036, 12, 4), dark, Vector3(side * 0.0075, 0.071, 0.0185), Vector3(90, 0, 0), Vector3(1, 1, 0.5))
		for w in 2: # whiskers
			_mi(body, _box(Vector3(0.011, 0.0006, 0.0006)), dark, Vector3(side * 0.016, 0.063 + w * 0.003, 0.016), Vector3(0, 0, side * (8 - w * 14)))
	_mi(body, _sph(0.0022), pink, Vector3(0, 0.065, 0.0205))
	_mi(body, _box(Vector3(0.006, 0.001, 0.001)), dark, Vector3(0, 0.0605, 0.0198))
	# orange and black patches
	_mi(body, _sph(0.008, -1, 10), _mat(Color(0.95, 0.55, 0.15), 0.6), Vector3(-0.012, 0.079, 0.01), Vector3.ZERO, Vector3(1, 0.7, 0.4))
	_mi(body, _sph(0.007, -1, 10), dark, Vector3(0.017, 0.03, 0.01), Vector3.ZERO, Vector3(0.5, 0.8, 0.8))
	# collar with a golden bell
	_mi(body, _torus(0.017, 0.021, 24, 6), red, Vector3(0, 0.05, 0.001), Vector3(-10, 0, 0), Vector3(1, 1, 0.9))
	_mi(body, _sph(0.0045), gold, Vector3(0, 0.046, 0.021))
	# raised beckoning paw
	_rod(body, Vector3(0.018, 0.045, 0.005), Vector3(0.024, 0.08, 0.008), 0.0065, white, 10)
	_mi(body, _sph(0.0075), white, Vector3(0.024, 0.083, 0.008))
	_mi(body, _sph(0.003), pink, Vector3(0.024, 0.083, 0.0145), Vector3.ZERO, Vector3(1, 1, 0.4))
	# the other paw holds a golden koban coin
	_mi(body, _cyl(0.012, 0.012, 0.0025, 24), gold, Vector3(-0.004, 0.028, 0.023), Vector3(90, 0, 0), Vector3(0.75, 1, 1.2))
	_print(body, "$", Vector3(-0.004, 0.028, 0.0247), Vector3.ZERO, 0.00035, Color(0.6, 0.35, 0.05))
	_mi(body, _sph(0.0065), white, Vector3(-0.015, 0.03, 0.02))
	_value_label(j, "Value", 0.115)
	return j


func _cavendish() -> Node3D:
	# Cavendish is meant to outshine everything: a blazing halo, slowly turning sun rays and a real
	# light that bathes the neighbouring jokers in yellow
	var j := _begin("cavendish", {"glow_node": NodePath("Banana"), "glow_energy": 1.1,
			"spin_node": NodePath("Rays"), "spin_speed": 0.4})
	var gold_light := Color(1.0, 0.85, 0.35)
	var halo_tex := GradientTexture2D.new()
	halo_tex.fill = GradientTexture2D.FILL_RADIAL
	halo_tex.fill_from = Vector2(0.5, 0.5)
	halo_tex.fill_to = Vector2(1.0, 0.5)
	halo_tex.width = 128
	halo_tex.height = 128
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.25, Color(1, 1, 1, 0.55))
	halo_tex.gradient = g
	for layer in [[0.42, 2.2], [0.2, 2.2]]: # wide soft halo + bright core
		var halo := StandardMaterial3D.new()
		halo.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		halo.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		halo.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		halo.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		halo.albedo_texture = halo_tex
		halo.albedo_color = Color(gold_light.r * layer[1], gold_light.g * layer[1], gold_light.b * layer[1], 1.0)
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE * float(layer[0])
		var h := _mi(j, quad, halo, Vector3(0, 0.03, 0), Vector3.ZERO, Vector3.ONE, "Halo" if layer[0] > 0.3 else "Core")
		h.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ray_mat := StandardMaterial3D.new()
	ray_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ray_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ray_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	ray_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ray_mat.albedo_color = Color(1.6, 1.3, 0.5, 0.35)
	var rays := _node(j, "Rays", Vector3(0, 0.03, 0))
	for i in 14: # spikes of light in every direction
		var dir := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.4, 1), _rng.randf_range(-1, 1)).normalized()
		var length := _rng.randf_range(0.09, 0.16)
		var ray := _mi(rays, _cyl(0.0004, 0.006, length, 6), ray_mat)
		ray.transform = Transform3D(_align_y(dir), dir * (length * 0.5 + 0.01))
		ray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var lamp := OmniLight3D.new()
	lamp.name = "Shine"
	lamp.light_color = gold_light
	lamp.light_energy = 4.0
	lamp.omni_range = 0.55 # reaches the neighbouring pedestals
	lamp.position = Vector3(0, 0.05, 0)
	j.add_child(lamp)
	var bunch := _node(j, "Banana", Vector3(0.008, 0.004, 0))
	var peel := Color(0.98, 0.84, 0.12)
	for i in 3: # a bunch of three, fanned out from one crown
		_banana(bunch, 0.085, peel, Vector3(0, (1 - absi(i - 1)) * 0.006, (i - 1) * 0.012), Vector3((i - 1) * 12, (i - 1) * -14, 0))
	_mi(bunch, _cyl(0.0045, 0.0055, 0.014, 8), _mat(Color(0.4, 0.45, 0.18), 0.7), Vector3(-0.045, 0.02, 0), Vector3(0, 0, 55))
	_mi(bunch, _cyl(0.0055, 0.0055, 0.0008, 16), _mat(Color(0.15, 0.35, 0.8), 0.5), Vector3(-0.004, 0.0105, 0.012),
			Vector3(80, 0, 0)) # the sticker
	return j


func _mail() -> Node3D:
	var j := _begin("mail", {"label_node": NodePath("Sign"), "label_source": "target[\"rank\"]", "label_format": "Discard: %s"})
	var wood := _mat(Color(0.4, 0.24, 0.12), 0.7)
	var red := _mat(Color(0.82, 0.12, 0.14), 0.4)
	_mi(j, _box(Vector3(0.03, 0.005, 0.03)), wood, Vector3(0, 0.0025, 0))
	_mi(j, _box(Vector3(0.008, 0.07, 0.008)), wood, Vector3(0, 0.04, 0), Vector3.ZERO, Vector3.ONE, "Post")
	var arch := PackedVector2Array([Vector2(-0.018, 0), Vector2(0.018, 0)])
	for i in 13:
		var a := PI * i / 12.0
		arch.append(Vector2(cos(a) * 0.018, 0.02 + sin(a) * 0.018))
	var box := _mi(j, _extrude(arch, 0.07), red, Vector3(0, 0.075, 0), Vector3.ZERO, Vector3.ONE, "Box")
	_mi(box, _extrude(PackedVector2Array(arch), 0.002), _mat(Color(0.6, 0.08, 0.1), 0.4), Vector3(0, 0, 0.036), Vector3.ZERO, Vector3(0.92, 0.92, 1))
	_mi(box, _sph(0.0025), _gold(), Vector3(0, 0.022, 0.0375))
	# the little flag on the side, raised: you've got mail
	_mi(box, _box(Vector3(0.002, 0.03, 0.003)), _mat(Color(0.95, 0.8, 0.2), 0.5), Vector3(0.019, 0.025, -0.015))
	_mi(box, _box(Vector3(0.002, 0.01, 0.014)), _mat(Color(0.95, 0.8, 0.2), 0.5), Vector3(0.019, 0.036, -0.009))
	# a letter sticking out of the front
	var letter := _mi(box, _box(Vector3(0.026, 0.017, 0.012)), _mat(Color(0.98, 0.97, 0.93), 0.7), Vector3(0, 0.016, 0.039), Vector3(-15, 0, 0))
	_mi(letter, _box(Vector3(0.006, 0.006, 0.0006)), _mat(Color(0.2, 0.45, 0.85), 0.6), Vector3(0.008, 0.003, 0.0062))
	_mi(letter, _box(Vector3(0.026, 0.0015, 0.0005)), red, Vector3(0, -0.0078, 0.0062))
	_value_label(j, "Sign", 0.15)
	return j


func _ride_the_bus() -> Node3D:
	var j := _begin("ride_the_bus", {"label_node": NodePath("Value"), "label_source": "ab[\"mult\"]", "label_format": "+%d Mult"})
	var bus := _node(j, "Bus", Vector3(0, 0, 0))
	bus.rotation_degrees.y = -25
	var yellow := _mat(Color(0.98, 0.72, 0.1), 0.5)
	var glass := _mat(Color(0.12, 0.2, 0.3), 0.15, 0.3)
	var black := _mat(Color(0.06, 0.06, 0.07), 0.8)
	var chrome := _mat(Color(0.8, 0.8, 0.85), 0.25, 0.8)
	_mi(bus, _box(Vector3(0.075, 0.034, 0.034)), yellow, Vector3(-0.006, 0.026, 0))
	_mi(bus, _box(Vector3(0.017, 0.02, 0.032)), yellow, Vector3(0.039, 0.019, 0)) # the hood
	_mi(bus, _box(Vector3(0.077, 0.004, 0.035)), _mat(Color(0.95, 0.95, 0.9), 0.5), Vector3(-0.006, 0.0445, 0)) # roof
	for side in [-1.0, 1.0]:
		for i in 5:
			_mi(bus, _box(Vector3(0.0105, 0.011, 0.001)), glass, Vector3(-0.036 + i * 0.0135, 0.033, side * 0.0172))
		_mi(bus, _box(Vector3(0.075, 0.0022, 0.0008)), black, Vector3(-0.006, 0.021, side * 0.0173))
	_mi(bus, _box(Vector3(0.001, 0.013, 0.028)), glass, Vector3(0.0315, 0.033, 0)) # windscreen
	_mi(bus, _box(Vector3(0.002, 0.004, 0.036)), black, Vector3(0.048, 0.01, 0)) # bumper
	for side in [-1.0, 1.0]:
		_mi(bus, _sph(0.0028), _glowing(Color(1.0, 0.95, 0.7), 2.0), Vector3(0.0475, 0.019, side * 0.011))
		_mi(bus, _box(Vector3(0.006, 0.006, 0.001)), _mat(Color(0.85, 0.1, 0.1), 0.5), Vector3(-0.044, 0.028, side * 0.013) + Vector3(0, 0, side * 0.004)) # tail light
		for x in [-0.03, 0.033]:
			_mi(bus, _cyl(0.0085, 0.0085, 0.006, 16), black, Vector3(x, 0.0085, side * 0.016), Vector3(90, 0, 0))
			_mi(bus, _cyl(0.004, 0.004, 0.0065, 12), chrome, Vector3(x, 0.0085, side * 0.016), Vector3(90, 0, 0))
	_mi(bus, _box(Vector3(0.001, 0.008, 0.026)), black, Vector3(-0.0436, 0.035, 0)) # rear window frame
	_print(bus, "SCHOOL BUS", Vector3(-0.006, 0.0405, 0.0176), Vector3.ZERO, 0.00018, Color(0.1, 0.1, 0.1))
	_value_label(j, "Value", 0.1)
	return j


func _castle() -> Node3D:
	var j := _begin("castle", {"suit_node": NodePath("Flag/Symbol"), "suit_shapes": NodePath("Flag/Symbol"),
			"glow_node": NodePath("Flag/Symbol"), "glow_energy": 1.2})
	var stone := _mat(Color(0.64, 0.62, 0.6), 0.9)
	var dark := _mat(Color(0.35, 0.33, 0.32), 0.9)
	var roof := _mat(Color(0.2, 0.3, 0.7), 0.6)
	_mi(j, _box(Vector3(0.066, 0.028, 0.05)), stone, Vector3(0, 0.014, 0), Vector3.ZERO, Vector3.ONE, "Wall")
	for x in range(5):
		for z in [-1.0, 1.0]:
			_mi(j, _box(Vector3(0.007, 0.006, 0.004)), stone, Vector3(-0.026 + x * 0.013, 0.031, z * 0.023))
	# gate
	var arch := PackedVector2Array([Vector2(-0.008, 0), Vector2(0.008, 0)])
	for i in 9:
		var a := PI * i / 8.0
		arch.append(Vector2(cos(a) * 0.008, 0.01 + sin(a) * 0.008))
	_mi(j, _extrude(arch, 0.002), _mat(Color(0.25, 0.15, 0.08), 0.8), Vector3(0, 0, 0.0252))
	# corner towers with pointed roofs
	for x in [-1.0, 1.0]:
		for z in [-1.0, 1.0]:
			var p := Vector3(x * 0.033, 0, z * 0.025)
			_mi(j, _cyl(0.0105, 0.011, 0.045, 14), stone, p + Vector3(0, 0.0225, 0))
			_mi(j, _cyl(0.0005, 0.013, 0.022, 14), roof, p + Vector3(0, 0.056, 0))
			_mi(j, _box(Vector3(0.0018, 0.006, 0.001)), dark, p + Vector3(0, 0.032, 0.011 * z) * Vector3(1, 1, 1))
	# keep in the middle, with battlements and the flag pole
	_mi(j, _cyl(0.014, 0.015, 0.066, 16), stone, Vector3(0, 0.033, -0.004), Vector3.ZERO, Vector3.ONE, "Keep")
	for i in 8:
		var a := TAU * i / 8.0
		_mi(j, _box(Vector3(0.006, 0.006, 0.004)), stone, Vector3(cos(a) * 0.0135, 0.069, -0.004 + sin(a) * 0.0135), Vector3(0, -rad_to_deg(a), 0))
	_mi(j, _box(Vector3(0.002, 0.008, 0.001)), dark, Vector3(0, 0.05, 0.0105))
	_mi(j, _cyl(0.0018, 0.0018, 0.05, 8), _mat(Color(0.45, 0.3, 0.18), 0.7), Vector3(0, 0.091, -0.004), Vector3.ZERO, Vector3.ONE, "Pole")
	var flag_mat := _mat(Color(0.95, 0.95, 0.92), 0.8)
	flag_mat.emission_enabled = true
	flag_mat.emission = Color(0.95, 0.95, 0.92)
	flag_mat.emission_energy_multiplier = 0.45
	var flag := _mi(j, _box(Vector3(0.042, 0.028, 0.002)), flag_mat, Vector3(0.022, 0.1, -0.004), Vector3.ZERO, Vector3.ONE, "Flag")
	_suit_shapes(flag, "Symbol", Vector3.ZERO, 0.02, 0.004, _mat(Color(0.95, 0.95, 0.92), 0.6))
	return j


func _green_joker() -> Node3D:
	var j := _begin("green_joker", {"fill_node": NodePath("Meter/Fill"), "fill_source": "ab[\"mult\"]", "fill_max": 20.0,
			"fill_min": 0.02, "label_node": NodePath("Value"), "label_source": "ab[\"mult\"]", "label_format": "+%d Mult"})
	var jim := _jester(j, "Jimbo", 0.9, Color(0.2, 0.7, 0.3), Color(0.08, 0.4, 0.18))
	jim.position.x = -0.01
	var meter := _node(j, "Meter", Vector3(0.03, 0, 0))
	_mi(meter, _cyl(0.008, 0.009, 0.004, 14), _gold(), Vector3(0, 0.002, 0))
	_mi(meter, _cyl(0.0068, 0.0068, 0.08, 14), _see_through(Color(0.8, 0.95, 0.9), 0.25), Vector3(0, 0.044, 0))
	_mi(meter, _cyl(0.008, 0.008, 0.003, 14), _gold(), Vector3(0, 0.0855, 0))
	var fill := _node(meter, "Fill", Vector3(0, 0.004, 0))
	_mi(fill, _cyl(0.006, 0.006, 0.08, 14), _glowing(Color(0.3, 1.0, 0.4), 1.2), Vector3(0, 0.04, 0))
	_value_label(j, "Value", 0.13)
	return j


func _obelisk() -> Node3D:
	var j := _begin("obelisk", {"fill_node": NodePath("Fill"), "fill_source": "ab[\"x_mult\"] - 1.0", "fill_max": 3.0,
			"fill_min": 0.35, "label_node": NodePath("Value"), "label_source": "ab[\"x_mult\"]", "label_format": "x%.1f"})
	var stone := _mat(Color(0.3, 0.27, 0.36), 0.8)
	var light := _mat(Color(0.45, 0.42, 0.5), 0.8)
	_mi(j, _box(Vector3(0.05, 0.007, 0.05)), light, Vector3(0, 0.0035, 0))
	_mi(j, _box(Vector3(0.038, 0.007, 0.038)), stone, Vector3(0, 0.0105, 0))
	var fill := _node(j, "Fill", Vector3(0, 0.014, 0))
	var shaft := PackedVector2Array([Vector2(0, 0), Vector2(0.0155, 0), Vector2(0.0115, 0.09), Vector2(0.0115, 0.0905), Vector2(0, 0.0905)])
	_mi(fill, _lathe(shaft, 4, 45.0), stone)
	var tip := PackedVector2Array([Vector2(0.0118, 0), Vector2(0, 0.014)])
	_mi(fill, _lathe(tip, 4, 45.0), _gold(), Vector3(0, 0.0905, 0))
	# glowing hieroglyphs up the front
	var glyph := _glowing(Color(0.4, 0.9, 1.0), 1.5)
	for i in 7:
		var y := 0.012 + i * 0.011
		var w := 0.0105 - y * 0.035
		_mi(fill, _box(Vector3(_rng.randf_range(0.004, w), 0.0028, 0.001)), glyph,
				Vector3(_rng.randf_range(-0.002, 0.002), y, 0.0149 - y * 0.0445), Vector3(rad_to_deg(atan(0.0445)), 0, 0))
	_value_label(j, "Value", 0.14)
	return j


func _turtle_bean() -> Node3D:
	var j := _begin("turtle_bean", {"fill_node": NodePath("Fill"), "fill_source": "extra[\"h_size\"]", "fill_max": 5.0,
			"fill_min": 0.2, "fill_uniform": true})
	var fill := _node(j, "Fill")
	var shell := _mat(Color(0.3, 0.52, 0.22), 0.6)
	var plate := _mat(Color(0.48, 0.66, 0.3), 0.6)
	var skin := _mat(Color(0.55, 0.7, 0.35), 0.7)
	var dark := _mat(Color(0.08, 0.08, 0.1), 0.4)
	var dome := SphereMesh.new()
	dome.radius = 0.028
	dome.height = 0.028
	dome.is_hemisphere = true
	dome.radial_segments = 20
	dome.rings = 8
	_mi(fill, dome, shell, Vector3(0, 0.008, 0), Vector3.ZERO, Vector3(1, 0.85, 1.15))
	_mi(fill, _torus(0.026, 0.031, 24, 6), _mat(Color(0.25, 0.42, 0.18), 0.6), Vector3(0, 0.008, 0), Vector3.ZERO, Vector3(1, 0.6, 1.15))
	# shell plates: one on top, a ring of six around it
	_mi(fill, _cyl(0.008, 0.008, 0.003, 6), plate, Vector3(0, 0.0315, 0), Vector3.ZERO, Vector3(1, 1, 1.15))
	for i in 6:
		var a := TAU * i / 6.0
		var p := Vector3(cos(a) * 0.016, 0.026, sin(a) * 0.018)
		var m := _mi(fill, _cyl(0.0065, 0.0065, 0.003, 6), plate, p)
		m.basis = _align_y(Vector3(cos(a) * 0.6, 1.0, sin(a) * 0.6))
	# head with eyes, legs, tail
	_mi(fill, _sph(0.0095, -1, 14), skin, Vector3(0, 0.012, 0.038), Vector3.ZERO, Vector3(1, 0.9, 1.2))
	for side in [-1.0, 1.0]:
		_mi(fill, _sph(0.0018), dark, Vector3(side * 0.005, 0.0155, 0.0465))
		for z in [-1.0, 1.0]:
			_mi(fill, _sph(0.0065, -1, 10), skin, Vector3(side * 0.024, 0.004, z * 0.022), Vector3.ZERO, Vector3(1.2, 0.6, 1.0))
	_mi(fill, _cyl(0.0005, 0.004, 0.01, 8), skin, Vector3(0, 0.007, -0.035), Vector3(-80, 0, 0))
	return j


func _ramen() -> Node3D:
	var j := _begin("ramen", {"fill_node": NodePath("Fill"), "fill_source": "ab[\"x_mult\"] - 1.0", "fill_min": 0.08})
	var bowl_profile := PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.017, 0.0), Vector2(0.018, 0.005),
			Vector2(0.03, 0.017), Vector2(0.036, 0.034), Vector2(0.0335, 0.035), Vector2(0.028, 0.018), Vector2(0.0, 0.007)])
	_mi(j, _lathe(bowl_profile, 32), _mat(Color(0.82, 0.15, 0.12), 0.35), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, "Bowl")
	_mi(j, _torus(0.0335, 0.0365, 32, 6), _mat(Color(0.97, 0.95, 0.9), 0.4), Vector3(0, 0.0345, 0))
	var fill := _node(j, "Fill", Vector3(0, 0.007, 0))
	_mi(fill, _cyl(0.029, 0.021, 0.018, 28), _mat(Color(0.8, 0.55, 0.25), 0.25), Vector3(0, 0.009, 0), Vector3.ZERO, Vector3.ONE, "Broth")
	var noodle := _mat(Color(0.98, 0.88, 0.55), 0.5)
	for n in 7: # wavy noodles lying on the broth
		var path: Array = []
		var radii: Array = []
		var z0 := -0.016 + n * 0.0052
		for i in 11:
			var t := i / 10.0
			var x := lerpf(-0.022, 0.022, t)
			path.append(Vector3(x, 0.0185 + 0.0012 * sin(t * 20.0 + n), z0 + 0.003 * sin(t * 12.0 + n * 2.0)))
			radii.append(0.0012)
		var lim := sqrt(maxf(0.026 * 0.026 - z0 * z0, 0.0))
		var clipped: Array = []
		for p in path:
			if absf(p.x) < lim - 0.002:
				clipped.append(p)
		if clipped.size() >= 3:
			_mi(fill, _sweep(clipped, radii.slice(0, clipped.size()), 6), noodle)
	# toppings: half an egg, a fish cake, nori, spring onions
	var egg := SphereMesh.new()
	egg.radius = 0.0085
	egg.height = 0.0085
	egg.is_hemisphere = true
	_mi(fill, egg, _mat(Color(0.98, 0.97, 0.94), 0.4), Vector3(0.011, 0.0185, 0.009), Vector3(-90, 0, 0), Vector3(1, 1.2, 1))
	_mi(fill, _cyl(0.004, 0.004, 0.001, 14), _mat(Color(1.0, 0.65, 0.1), 0.4), Vector3(0.011, 0.0186, 0.009), Vector3.ZERO, Vector3(1, 1, 1.2))
	_mi(fill, _cyl(0.0065, 0.0065, 0.002, 18), _mat(Color(0.98, 0.96, 0.95), 0.5), Vector3(-0.011, 0.02, 0.008))
	_mi(fill, _torus(0.0022, 0.0034, 14, 4), _mat(Color(0.95, 0.45, 0.6), 0.5), Vector3(-0.011, 0.0212, 0.008))
	_mi(fill, _box(Vector3(0.016, 0.022, 0.001)), _mat(Color(0.08, 0.15, 0.1), 0.6), Vector3(0.0, 0.026, -0.019), Vector3(-15, 0, 0))
	for i in 6:
		_mi(fill, _torus(0.0008, 0.0016, 10, 4), _mat(Color(0.35, 0.75, 0.25), 0.5),
				Vector3(_rng.randf_range(-0.01, 0.006), 0.0195, _rng.randf_range(-0.004, 0.004)))
	# chopsticks across the rim
	var wood := _mat(Color(0.75, 0.55, 0.3), 0.6)
	for k in 2:
		_rod(j, Vector3(-0.045, 0.036 + k * 0.001, 0.012 + k * 0.006), Vector3(0.04, 0.039 + k * 0.001, -0.004 + k * 0.006), 0.0016, wood, 6)
	return j


func _hologram() -> Node3D:
	var j := _begin("hologram", {"label_node": NodePath("Value"), "label_source": "ab[\"x_mult\"]", "label_format": "x%.2f",
			"glow_node": NodePath("Figure"), "glow_source": "(ab[\"x_mult\"] - 1.0) / 3.0", "spin_node": NodePath("Figure"),
			"spin_speed": 1.5})
	var metal := _mat(Color(0.18, 0.2, 0.25), 0.3, 0.7)
	var cyan := Color(0.35, 0.9, 1.0)
	_mi(j, _cyl(0.028, 0.031, 0.009, 24), metal, Vector3(0, 0.0045, 0))
	_mi(j, _torus(0.022, 0.025, 32, 6), _glowing(cyan, 2.0), Vector3(0, 0.009, 0))
	_mi(j, _cyl(0.012, 0.012, 0.002, 20), _glowing(cyan, 2.5), Vector3(0, 0.0095, 0))
	var beam := _see_through(cyan, 0.12)
	beam.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mi(j, _cyl(0.03, 0.012, 0.1, 24), beam, Vector3(0, 0.06, 0))
	var holo := _see_through(cyan, 0.55, 0.3)
	holo.emission_enabled = true
	holo.emission = cyan
	holo.emission_energy_multiplier = 0.8
	var fig := _jester(j, "Figure", 0.85, cyan, cyan, holo)
	fig.position.y = 0.012
	_value_label(j, "Value", 0.13)
	return j


func _todo_list() -> Node3D:
	var j := _begin("todo_list", {"label_node": NodePath("Clipboard/Paper/Task"), "label_source": "ab[\"to_do\"]"})
	var board := _mi(j, _box(Vector3(0.06, 0.08, 0.004)), _mat(Color(0.55, 0.36, 0.18), 0.6), Vector3(0, 0.045, 0),
			Vector3(-18, 0, 0), Vector3.ONE, "Clipboard")
	_mi(j, _box(Vector3(0.05, 0.03, 0.006)), _mat(Color(0.4, 0.26, 0.12), 0.6), Vector3(0, 0.003, -0.012)) # stand foot
	var paper := _mi(board, _box(Vector3(0.052, 0.068, 0.001)), _mat(Color(0.98, 0.98, 0.95), 0.8), Vector3(0, -0.004, 0.0025),
			Vector3.ZERO, Vector3.ONE, "Paper")
	var metal := _mat(Color(0.75, 0.75, 0.8), 0.3, 0.8)
	_mi(board, _box(Vector3(0.026, 0.008, 0.005)), metal, Vector3(0, 0.036, 0.003))
	_mi(board, _torus(0.003, 0.0045, 12, 4), metal, Vector3(0, 0.041, 0.003), Vector3(90, 0, 0))
	_print(paper, "TO DO", Vector3(0, 0.026, 0.0006), Vector3.ZERO, 0.0003, Color(0.15, 0.15, 0.2))
	var grey := _mat(Color(0.6, 0.6, 0.65), 0.7)
	var red := _mat(Color(0.85, 0.12, 0.15), 0.5)
	for row in 3:
		var y := 0.014 - row * 0.012
		for e in 4: # check box outline
			var horizontal := e < 2
			_mi(paper, _box(Vector3(0.007 if horizontal else 0.0008, 0.0008 if horizontal else 0.007, 0.0006)), grey,
					Vector3(-0.018 + (0.0 if horizontal else (-0.0035 if e == 2 else 0.0035)), y + (0.0 if not horizontal else (-0.0035 if e == 0 else 0.0035)), 0.0006))
		if row < 2: # done: a grey line of old tasks and a red tick
			_mi(paper, _box(Vector3(0.028, 0.0012, 0.0006)), grey, Vector3(0.006, y, 0.0006))
			_mi(paper, _box(Vector3(0.0045, 0.0013, 0.0007)), red, Vector3(-0.0195, y - 0.0005, 0.0009), Vector3(0, 0, -45))
			_mi(paper, _box(Vector3(0.008, 0.0013, 0.0007)), red, Vector3(-0.0162, y + 0.0012, 0.0009), Vector3(0, 0, 55))
	# the open task: the poker hand the game wants, written in blue ink on the paper (long names wrap)
	var task := Label3D.new()
	task.name = "Task"
	task.text = "?"
	task.font_size = 48
	task.pixel_size = 0.00013
	task.modulate = Color(0.12, 0.2, 0.6)
	task.outline_size = 0
	task.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	task.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	task.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	task.width = 0.034 / task.pixel_size
	task.position = Vector3(-0.0125, -0.0065, 0.0008) # right of the open box, room for two lines below
	paper.add_child(task)
	# a pencil lying in front
	var pencil := _node(j, "Pencil", Vector3(0.004, 0.003, 0.022))
	pencil.rotation_degrees = Vector3(0, 12, 90)
	_mi(pencil, _cyl(0.003, 0.003, 0.05, 6), _mat(Color(0.98, 0.8, 0.15), 0.5))
	_mi(pencil, _cyl(0.0003, 0.003, 0.008, 6), _mat(Color(0.9, 0.75, 0.55), 0.6), Vector3(0, 0.029, 0))
	_mi(pencil, _cyl(0.0031, 0.0031, 0.005, 8), _mat(Color(0.95, 0.5, 0.55), 0.6), Vector3(0, -0.0275, 0))
	return j


func _square() -> Node3D:
	var j := _begin("square", {"fill_node": NodePath("Fill"), "fill_source": "extra[\"chips\"]", "fill_max": 64.0,
			"fill_min": 0.3, "fill_uniform": true, "label_node": NodePath("Value"), "label_source": "extra[\"chips\"]",
			"label_format": "+%d Chips"})
	var fill := _node(j, "Fill")
	var face := _mat(Color(0.96, 0.94, 0.9), 0.5)
	var dark := _mat(Color(0.08, 0.08, 0.1), 0.4)
	_mi(fill, _box(Vector3(0.05, 0.05, 0.05)), face, Vector3(0, 0.025, 0))
	# square eyes, rosy cheeks, a square grin
	for side in [-1.0, 1.0]:
		_mi(fill, _box(Vector3(0.007, 0.007, 0.001)), dark, Vector3(side * 0.011, 0.032, 0.0252))
		_mi(fill, _box(Vector3(0.008, 0.005, 0.0008)), _mat(Color(0.95, 0.45, 0.5), 0.6), Vector3(side * 0.016, 0.021, 0.0252))
	_mi(fill, _box(Vector3(0.022, 0.006, 0.001)), dark, Vector3(0, 0.014, 0.0252))
	_mi(fill, _box(Vector3(0.018, 0.0025, 0.0012)), _mat(Color(0.95, 0.95, 0.95), 0.5), Vector3(0, 0.0155, 0.0253))
	# a square jester hat on top
	var red := _mat(Color(0.85, 0.15, 0.2), 0.6)
	var blue := _mat(Color(0.16, 0.36, 0.85), 0.6)
	_mi(fill, _box(Vector3(0.052, 0.008, 0.052)), red, Vector3(0, 0.054, 0))
	for side in [-1.0, 1.0]:
		_mi(fill, _box(Vector3(0.016, 0.016, 0.016)), blue if side > 0 else red, Vector3(side * 0.018, 0.066, 0), Vector3(0, 0, -side * 20))
		_mi(fill, _box(Vector3(0.008, 0.008, 0.008)), _gold(), Vector3(side * 0.03, 0.074, 0), Vector3(0, 45, 45))
	_value_label(j, "Value", 0.1)
	return j


func _selzer() -> Node3D:
	var j := _begin("selzer", {"fill_node": NodePath("Fill"), "fill_source": "extra[\"value\"]", "fill_max": 10.0,
			"empty_source": "extra[\"value\"]", "empty_at": 1.0, "hide_when_empty": NodePath("Fizz")})
	var chrome := _mat(Color(0.86, 0.87, 0.92), 0.22, 0.35)
	chrome.emission_enabled = true # bright metal even without reflections
	chrome.emission = Color(0.86, 0.87, 0.92)
	chrome.emission_energy_multiplier = 0.12
	var bottle := PackedVector2Array([Vector2(0, 0.002), Vector2(0.019, 0.002), Vector2(0.021, 0.006), Vector2(0.021, 0.062),
			Vector2(0.017, 0.072), Vector2(0.011, 0.078), Vector2(0.011, 0.082)])
	_mi(j, _cyl(0.0215, 0.0215, 0.004, 24), chrome, Vector3(0, 0.002, 0))
	var fill := _node(j, "Fill", Vector3(0, 0.005, 0))
	_mi(fill, _cyl(0.0185, 0.0185, 0.058, 24), _see_through(Color(0.55, 0.85, 1.0), 0.55, 0.05), Vector3(0, 0.029, 0), Vector3.ZERO, Vector3.ONE, "Water")
	for i in 14:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(0.0, 0.015)
		_mi(fill, _sph(_rng.randf_range(0.0009, 0.0016), -1, 6), _see_through(Color(1, 1, 1), 0.7),
				Vector3(cos(a) * r, _rng.randf_range(0.005, 0.055), sin(a) * r))
	_mi(j, _lathe(bottle, 28), _see_through(Color(0.7, 0.9, 1.0), 0.22, 0.05), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, "Glass")
	# the siphon head: collar, body, lever and spout
	_mi(j, _cyl(0.0125, 0.0125, 0.006, 20), chrome, Vector3(0, 0.083, 0))
	_mi(j, _cyl(0.009, 0.011, 0.016, 20), chrome, Vector3(0, 0.094, 0))
	_mi(j, _sph(0.009, -1, 16), chrome, Vector3(0, 0.102, 0), Vector3.ZERO, Vector3(1, 0.6, 1))
	_rod(j, Vector3(0.006, 0.096, 0), Vector3(0.026, 0.091, 0), 0.0025, chrome, 10)
	_rod(j, Vector3(-0.004, 0.104, 0), Vector3(-0.026, 0.098, 0), 0.0022, chrome, 8)
	_mi(j, _sph(0.0035), _mat(Color(0.15, 0.15, 0.18), 0.4), Vector3(-0.027, 0.098, 0))
	var fizz := _node(j, "Fizz")
	for i in 7:
		_mi(fizz, _sph(0.0012 + i * 0.0002, -1, 6), _see_through(Color(1, 1, 1), 0.85),
				Vector3(0.028 + _rng.randf_range(0.0, 0.004), 0.093 + i * 0.004, _rng.randf_range(-0.002, 0.002)))
	return j


func _idol() -> Node3D:
	var j := _begin("idol", {"suit_node": NodePath("Plaque/Symbol"), "suit_shapes": NodePath("Plaque/Symbol"),
			"glow_node": NodePath("Plaque/Symbol"), "glow_energy": 1.4, "label_node": NodePath("Sign"),
			"label_source": "target[\"rank\"] + \" of \" + target[\"suit\"]"})
	var stone := _mat(Color(0.3, 0.27, 0.25), 0.9)
	var gold := _gold()
	_mi(j, _box(Vector3(0.05, 0.012, 0.04)), stone, Vector3(0, 0.006, 0))
	_mi(j, _box(Vector3(0.04, 0.01, 0.032)), stone, Vector3(0, 0.017, 0))
	var statue := _node(j, "Statue", Vector3(0, 0.022, 0))
	# a seated golden idol: crossed legs, round belly, arms, big head with a pointed crown
	_mi(statue, _sph(0.017, -1, 18), gold, Vector3(0, 0.006, 0), Vector3.ZERO, Vector3(1.4, 0.45, 1.0))
	_mi(statue, _sph(0.013, -1, 18), gold, Vector3(0, 0.022, 0), Vector3.ZERO, Vector3(1.0, 1.15, 0.9))
	for side in [-1.0, 1.0]:
		_rod(statue, Vector3(side * 0.011, 0.03, 0), Vector3(side * 0.013, 0.014, 0.008), 0.0035, gold, 8)
		_mi(statue, _sph(0.0035), gold, Vector3(side * 0.008, 0.013, 0.01))
	_mi(statue, _sph(0.0115, -1, 18), gold, Vector3(0, 0.046, 0))
	var dark := _mat(Color(0.25, 0.12, 0.05), 0.5)
	for side in [-1.0, 1.0]:
		_mi(statue, _box(Vector3(0.004, 0.0012, 0.001)), dark, Vector3(side * 0.0045, 0.048, 0.011))
		_mi(statue, _sph(0.0035), gold, Vector3(side * 0.0115, 0.046, 0), Vector3.ZERO, Vector3(0.5, 1.4, 0.8)) # ears
	_mi(statue, _box(Vector3(0.006, 0.0012, 0.001)), dark, Vector3(0, 0.041, 0.0108))
	for i in 5:
		var a := TAU * i / 5.0
		_mi(statue, _cyl(0.0003, 0.0026, 0.009, 6), gold, Vector3(cos(a) * 0.006, 0.0605, sin(a) * 0.006))
	_mi(statue, _torus(0.0065, 0.0085, 16, 4), gold, Vector3(0, 0.0565, 0))
	_mi(statue, _sph(0.0022), _mat(Color(0.85, 0.1, 0.15), 0.2), Vector3(0, 0.057, 0.0085))
	var plaque := _mi(j, _box(Vector3(0.026, 0.009, 0.002)), _mat(Color(0.12, 0.1, 0.1), 0.5), Vector3(0, 0.0125, 0.021), Vector3.ZERO, Vector3.ONE, "Plaque")
	_suit_shapes(plaque, "Symbol", Vector3(0, 0, 0.0012), 0.0085, 0.002, _mat(Color(0.95, 0.95, 0.92), 0.4))
	_value_label(j, "Sign", 0.15)
	return j


## Jimbo for the casino table (no joker script: JimboCompanion animates him). Not a joker scene.
func _jimbo_companion() -> Node3D:
	var root := Node3D.new()
	root.name = "JimboCompanion"
	_jester(root, "Jimbo", 1.0)
	return root
