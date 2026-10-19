class_name RadarScreen
extends Node3D
## Achievement reward "UnderTheVRadar": a little radar screen at the edge of the joker board. A green
## beam sweeps round; the jokers on the board (and a waiting booster pack) light up as blips when
## it passes them, then fade until the next sweep. main.gd says where they are.
## Origin = the foot of its stand on the table; the screen leans back towards you.

const R := 0.07                     # radius of the screen
const SWEEP := 1.6                  # rad/s

var blips: Callable                 # -> Array of Vector2 in -1..1 (x right, y away from you)

var _screen: Node3D
var _beam: MeshInstance3D
var _angle := 0.0
var _dots: Array[MeshInstance3D] = []
var _seen := {}                     # dot index -> time it was last lit


func _ready() -> void:
	var dark := _mat(Color(0.1, 0.1, 0.12), 0.4, 0.6)
	var foot := MeshInstance3D.new()
	var fm := CylinderMesh.new()
	fm.top_radius = 0.03
	fm.bottom_radius = 0.035
	fm.height = 0.01
	foot.mesh = fm
	foot.position.y = 0.005
	foot.material_override = dark
	add_child(foot)
	var post := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.006
	pm.bottom_radius = 0.006
	pm.height = 0.05
	post.mesh = pm
	post.position.y = 0.035
	post.material_override = dark
	add_child(post)
	_screen = Node3D.new()
	_screen.position = Vector3(0, 0.07 + R * 0.5, -0.01)
	_screen.rotation_degrees.x = -35.0 # leaning back, towards your eyes
	add_child(_screen)
	# bezel and the dark green glass
	_disc(_screen, R + 0.008, 0.012, Vector3(0, 0, -0.006), _mat(Color(0.15, 0.15, 0.17), 0.3, 0.8))
	var glass := StandardMaterial3D.new()
	glass.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glass.albedo_color = Color(0.0, 0.12, 0.05)
	_disc(_screen, R, 0.002, Vector3.ZERO, glass)
	# range rings and a cross
	var line := StandardMaterial3D.new()
	line.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line.albedo_color = Color(0.1, 0.6, 0.25)
	for k in [0.33, 0.66, 0.97]:
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = R * k - 0.0008
		tm.outer_radius = R * k + 0.0008
		tm.rings = 48
		ring.mesh = tm
		ring.rotation_degrees.x = 90.0
		ring.position.z = 0.0012
		ring.material_override = line
		_screen.add_child(ring)
	for k in 2:
		var bar := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(R * 2.0, 0.0012, 0.0005) if k == 0 else Vector3(0.0012, R * 2.0, 0.0005)
		bar.mesh = bm
		bar.position.z = 0.0012
		bar.material_override = line
		_screen.add_child(bar)
	# the sweeping beam: a fading wedge
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := 16
	var width := 0.7
	for i in steps:
		var a0 := width * i / steps # (the glow trails behind the beam: it turns clockwise)
		var a1 := width * (i + 1) / steps
		var c0 := Color(0.2, 1.0, 0.4, 0.55 * (1.0 - float(i) / steps))
		var c1 := Color(0.2, 1.0, 0.4, 0.55 * (1.0 - float(i + 1) / steps))
		st.set_color(Color(0.2, 1.0, 0.4, 0.55))
		st.add_vertex(Vector3.ZERO)
		st.set_color(c0)
		st.add_vertex(Vector3(cos(a0), sin(a0), 0) * R)
		st.set_color(c1)
		st.add_vertex(Vector3(cos(a1), sin(a1), 0) * R)
	_beam = MeshInstance3D.new()
	_beam.mesh = st.commit()
	var bmat := StandardMaterial3D.new()
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat.vertex_color_use_as_albedo = true
	bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_beam.material_override = bmat
	_beam.position.z = 0.0018
	_screen.add_child(_beam)
	var label := Label3D.new()
	label.text = "VRADAR"
	label.font_size = 28
	label.pixel_size = 0.0004
	label.modulate = Color(0.3, 1.0, 0.5)
	label.outline_size = 0
	label.position = Vector3(0, -R - 0.012, 0.001)
	_screen.add_child(label)
	GameFont.apply_to(self)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_angle = fmod(_angle + SWEEP * delta, TAU)
	_beam.rotation.z = -_angle # clockwise, like a real radar
	var points: Array = blips.call() if blips.is_valid() else []
	while _dots.size() < points.size():
		var dot := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.0035
		sm.height = 0.002
		dot.mesh = sm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(0.5, 1.0, 0.6, 0.0)
		dot.material_override = m
		_screen.add_child(dot)
		_dots.append(dot)
	var now := Time.get_ticks_msec() / 1000.0
	for i in _dots.size():
		var dot := _dots[i]
		if i >= points.size():
			dot.visible = false
			continue
		dot.visible = true
		var p: Vector2 = (points[i] as Vector2).limit_length(0.95)
		dot.position = Vector3(p.x * R, p.y * R, 0.0025)
		# lit when the beam passes over it, then it fades
		var a := fposmod(-atan2(p.y, p.x), TAU)
		if absf(angle_difference(a, _angle)) < SWEEP * delta * 1.5 + 0.02:
			_seen[i] = now
		var age := now - float(_seen.get(i, -10.0))
		(dot.material_override as StandardMaterial3D).albedo_color.a = clampf(1.0 - age / 3.5, 0.0, 1.0)


func _disc(parent: Node3D, radius: float, height: float, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = 48
	mi.mesh = c
	mi.rotation_degrees.x = 90.0
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)


func _mat(colour: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = rough
	m.metallic = metal
	return m
