class_name JimboHand
extends Node3D
## A cartoon glove in Jimbo's style (white, with a red and blue cuff and a little golden bell) that
## shows what your real hand does on the controller:
##   grip pressed -> fist          trigger touched / pressed -> index finger curls
##   finger off the trigger -> points   thumb off the buttons -> thumbs up
## It hangs on an XRController3D with the "grip" pose. In that (OpenXR) frame the controller's
## handle runs along Z (index finger at -Z), the palm faces +X on the left hand / -X on the right,
## the wrist is at +Y (towards you) and stretched fingers point to -Y (forward).
## Built from code; `pose_override` lets tests set a pose without a controller.

const WHITE := Color(0.97, 0.96, 0.93)
const RED := Color(0.85, 0.12, 0.15)
const BLUE := Color(0.15, 0.3, 0.85)
const GOLD := Color(0.95, 0.75, 0.25)

## per finger: [z position at the knuckle, segment lengths]
const FINGERS := [
	[-0.03, [0.03, 0.022, 0.018]],    # index
	[-0.01, [0.033, 0.024, 0.019]],   # middle
	[0.01, [0.031, 0.022, 0.018]],    # ring
	[0.029, [0.025, 0.018, 0.016]],   # pinky
]
const FIST := [1.25, 1.45, 1.1]      # joint angles (radians) of a full fist, wrapped round the handle
const OPEN := 0.18                   # a relaxed hand is never quite flat

@export var left := true
var pose_override := {}              # e.g. {"grip": 1.0, "trigger": 0.0, "trigger_touch": false, "thumb_touch": true}

var _fingers: Array = []             # per finger: [joint1, joint2, joint3] (Node3D pivots)
var _thumb: Node3D
var _curl := [0.0, 0.0, 0.0, 0.0]    # smoothed curl per finger (0 open .. 1 fist)
var _thumb_down := 1.0


func _ready() -> void:
	_build()


func _process(delta: float) -> void:
	var grip := 0.0
	var trigger := 0.0
	var trigger_touch := true
	var thumb_touch := true
	var c := get_parent() as XRController3D
	if not pose_override.is_empty():
		grip = float(pose_override.get("grip", 0.0))
		trigger = float(pose_override.get("trigger", 0.0))
		trigger_touch = bool(pose_override.get("trigger_touch", true))
		thumb_touch = bool(pose_override.get("thumb_touch", true))
	elif c != null:
		grip = c.get_float("grip")
		trigger = c.get_float("trigger")
		trigger_touch = c.is_button_pressed("trigger_touch") or trigger > 0.05
		thumb_touch = c.is_button_pressed("ax_touch") or c.is_button_pressed("by_touch") \
				or c.is_button_pressed("primary_touch") or c.is_button_pressed("ax_button") \
				or c.is_button_pressed("by_button")
	var want := [
		lerpf(0.3, 1.0, trigger) if trigger_touch else 0.0, # index: points when the finger is off the trigger
		lerpf(OPEN, 1.0, grip), lerpf(OPEN, 1.0, grip), lerpf(OPEN, 1.0, grip),
	]
	var k := 1.0 - exp(-22.0 * delta) # quick, but no jitter
	for i in 4:
		_curl[i] = lerpf(_curl[i], want[i], k)
		var joints: Array = _fingers[i]
		for j in 3:
			(joints[j] as Node3D).rotation.z = _side() * FIST[j] * _curl[i] # curls round the handle
	_thumb_down = lerpf(_thumb_down, 1.0 if thumb_touch else 0.0, k)
	# thumbs up: along the handle (-Z, "up"); resting: lying forward on the controller's face
	_thumb.rotation = Vector3(-0.2 - 1.15 * _thumb_down, -_side() * (0.25 + 0.3 * _thumb_down), 0.0)


## +1 for the left hand, -1 for the right (everything is mirrored along X).
func _side() -> float:
	return 1.0 if left else -1.0


func _build() -> void:
	var s := _side()
	var glove := _mat(WHITE, 0.55)
	# palm: a puffy cartoon shape on the outer side of the handle, from the wrist to the knuckles
	_ellipsoid(self, Vector3(-0.029 * s, 0.032, 0.0), Vector3(0.034, 0.085, 0.09), glove)
	# back-of-hand seams, like on Jimbo's gloves
	var seam := _mat(Color(0.82, 0.8, 0.76), 0.6)
	for z in [-0.015, 0.0, 0.015]:
		var line := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.002, 0.035, 0.0025)
		line.mesh = b
		line.material_override = seam
		line.position = Vector3(-0.046 * s, 0.045, z)
		add_child(line)
	# four fingers, three joints each, bending towards the palm side (around the handle)
	for f in FINGERS:
		var joints: Array = []
		var parent: Node3D = self
		var pos := Vector3(-0.03 * s, -0.004, float(f[0]))
		var lengths: Array = f[1]
		for j in 3:
			var pivot := Node3D.new()
			pivot.position = pos
			parent.add_child(pivot)
			var length: float = lengths[j]
			var radius := 0.0105 - j * 0.0012
			_capsule(pivot, Vector3(0, -length * 0.5, 0), radius, length + radius, glove)
			joints.append(pivot)
			parent = pivot
			pos = Vector3(0, -length, 0)
		_fingers.append(joints)
	# thumb: from the index side of the palm, two segments
	_thumb = Node3D.new()
	_thumb.position = Vector3(-0.022 * s, 0.03, -0.04)
	add_child(_thumb)
	_capsule(_thumb, Vector3(0, 0, -0.016), 0.012, 0.036, glove, true)
	var tip := Node3D.new()
	tip.position = Vector3(0, 0, -0.03)
	tip.rotation.x = -0.25
	_thumb.add_child(tip)
	_capsule(tip, Vector3(0, 0, -0.012), 0.0105, 0.028, glove, true)
	# cuff around the wrist: half red, half blue (like Jimbo's collar), with a golden bell
	var cuff_y := 0.085
	for half in 2: # a short, flared sleeve end: the hand side red, the arm side blue
		var part := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.042 if half == 1 else 0.038
		cyl.bottom_radius = 0.036 if half == 1 else 0.031
		cyl.height = 0.014
		cyl.radial_segments = 20
		cyl.rings = 1
		part.mesh = cyl
		part.material_override = _mat(RED if half == 0 else BLUE, 0.5)
		part.position = Vector3(-0.027 * s, cuff_y + half * 0.014, 0.0)
		part.scale = Vector3(0.62, 1.0, 1.0) # flat like the wrist
		if half == 1:
			cyl.cap_top = false # open towards you: you look into the glove, not at a lid
		add_child(part)
	# the dark inside of the glove's opening
	var inside := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.034
	disc.bottom_radius = 0.034
	disc.height = 0.002
	disc.radial_segments = 20
	inside.mesh = disc
	inside.material_override = _mat(Color(0.12, 0.1, 0.12), 0.9)
	inside.position = Vector3(-0.027 * s, cuff_y + 0.012, 0.0)
	inside.scale = Vector3(0.62, 1.0, 1.0)
	add_child(inside)
	var inner_wall := MeshInstance3D.new()
	var tube := CylinderMesh.new()
	tube.top_radius = 0.0405
	tube.bottom_radius = 0.0355
	tube.height = 0.0135
	tube.cap_top = false
	tube.cap_bottom = false
	tube.flip_faces = true # seen from inside
	tube.radial_segments = 20
	inner_wall.mesh = tube
	inner_wall.material_override = _mat(BLUE.darkened(0.5), 0.6)
	inner_wall.position = Vector3(-0.027 * s, cuff_y + 0.014, 0.0)
	inner_wall.scale = Vector3(0.62, 1.0, 1.0)
	add_child(inner_wall)
	var bell := MeshInstance3D.new()
	var bs := SphereMesh.new()
	bs.radius = 0.008
	bs.height = 0.016
	bell.mesh = bs
	var gold := _mat(GOLD, 0.3)
	gold.metallic = 0.7
	bell.material_override = gold
	bell.position = Vector3(-0.052 * s, cuff_y + 0.007, 0.0)
	add_child(bell)


func _ellipsoid(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.5
	s.height = 1.0
	s.radial_segments = 20
	s.rings = 10
	mi.mesh = s
	mi.material_override = mat
	mi.position = pos
	mi.scale = size
	parent.add_child(mi)


## A finger segment: a capsule along Y (or along Z with `along_z`).
func _capsule(parent: Node3D, pos: Vector3, radius: float, height: float, mat: Material, along_z := false) -> void:
	var mi := MeshInstance3D.new()
	var c := CapsuleMesh.new()
	c.radius = radius
	c.height = maxf(height, radius * 2.0)
	c.radial_segments = 12
	c.rings = 4
	mi.mesh = c
	mi.material_override = mat
	mi.position = pos
	if along_z:
		mi.rotation.x = PI * 0.5
	parent.add_child(mi)


func _mat(colour: Color, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = roughness
	return m
