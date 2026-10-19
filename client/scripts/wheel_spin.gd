class_name WheelSpin
extends Node3D
## The Wheel of Fortune in VR: when the tarot card is used, a little wheel of fortune stands in front
## of you. Swipe its rim with your hand (or point at it and pull the trigger) to spin it; the arrow
## at the top lands on WIN! (the card gives a joker an edition) or NOPE! (nothing happens).
## The wheel has as many WIN! fields as the card's chance (2 of 8 = 1 in 4, more with Oops! All 6s).
##   Real:          the wheel decides - where it stops is what happens (the mod makes the game follow it)
##   Deterministic: the game rolls as always (a seeded run stays the same) and the mod tells the result
##                  before the spin; the wheel brakes so that it stops on the right kind of field
## Origin = the wheel's hub, facing +z (towards the player).

signal tick                          # a peg passed the arrow (a little vibration)
signal landed(win: bool)
signal spun(speed: float)            # a real spin started (how hard it was swung, rad/s)
signal gripped(hand: Node3D)         # a hand took hold of the rim (trigger)

const R := 0.15                      # radius of the wheel
const N := 8                         # fields
const SPIN_MIN := 4.0                # rad/s: a swipe at least this fast spins it for real
const DECEL := 2.0                   # rad/s² braking that a spin would roughly have on its own
const TOUCH_DEPTH := 0.07            # a hand this close to the wheel's face can take hold of it
const RIM_IN := 0.05                 # the rim: from R - RIM_IN ...
const RIM_OUT := 0.06                # ... to R + RIM_OUT (where the trigger takes hold of the wheel)
const WIN_COLOURS := [Color(0.95, 0.75, 0.15), Color(0.2, 0.75, 0.35)]
const NOPE_COLOURS := [Color(0.85, 0.15, 0.2), Color(0.18, 0.32, 0.85)]

var sparks := false                  # achievement reward "Spin Doctor": sparks from the rim while it spins
var _sparks: CPUParticles3D
var golden := false                  # achievement reward "High Five": a wheel in the chosen colour ...
var golden_colour := Color(1.0, 0.76, 0.2) # ... (gold by default)
var vegas := false                   # achievement reward "Lady Luck": Las Vegas colours and light bulbs
var hands: Array = []                # XRController3D (or any Node3D) that can swipe the rim
var last_hand: Node3D = null         # the hand that spun it (for the vibration)

var _win := false                    # what the game rolled (Deterministic) / where it stopped (Real)
var _real := true                    # the wheel decides
var _fields: Array = []              # true = WIN! field
var _rotor: Node3D
var _arrow: Node3D
var _body: StaticBody3D
var _angle := 0.0
var _omega := 0.0                    # rad/s, + = counter-clockwise (seen from the front)
var _decel := 0.0
var _target := 0.0                   # the angle it stops at (once spun for real)
var _state := "idle"                 # idle / spinning / done
var _prev := {}                      # hand -> last position in the wheel's space
var _grip_hand: Node3D = null        # the hand holding the rim (trigger held)
var _grip_last := 0.0                # its angle round the hub last frame
var _was_pressed := {}               # hand -> its trigger was held last frame (a fresh press takes hold)
var _last_peg := 0
var _flap := 0.0                     # the arrow kicked by a peg
var _done_t := 0.0
var _result: Label3D
var _disc: MeshInstance3D            # the coloured fields (repainted when the look changes)
var _bulbs: Node3D                   # the light bulbs (Lady Luck), kept apart so they can come and go
var _grip_by_grip := false           # the rim is held with the grip (like the reroll lever), not the trigger
var _waiting_t := 0.0                # nobody spins it: after a while it turns by itself


## A new spin: how likely a win is (sets the WIN! fields); real = the wheel decides, otherwise it
## stops on what the game rolled (win).
func setup(chance: float, win: bool, real := false) -> void:
	_win = win
	_real = real
	var wins := clampi(int(round(N * chance)), 1, N - 1)
	_fields.clear()
	for i in N:
		_fields.append(false)
	for k in wins: # spread out round the wheel
		_fields[int(floor(k * float(N) / wins))] = true
	_build()


func _build() -> void:
	for c in get_children():
		c.queue_free()
	# the stand: a post down to the table and a foot
	var wood := _mat(Color(0.3, 0.12, 0.05), 0.5, 0.0)
	var gold := _mat(Color(0.9, 0.68, 0.28), 0.25, 0.85)
	_box(self, Vector3(0.025, 0.2, 0.02), Vector3(0, -R - 0.08, -0.03), wood)
	_box(self, Vector3(0.14, 0.02, 0.1), Vector3(0, -R - 0.17, -0.03), wood)
	_rotor = Node3D.new()
	add_child(_rotor)
	# the fields: coloured wedges (painted by _paint, see there)
	var dm := StandardMaterial3D.new()
	dm.vertex_color_use_as_albedo = true
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED # (bright like a fairground wheel, even in the dark casino)
	dm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_disc = MeshInstance3D.new()
	_disc.material_override = dm
	_rotor.add_child(_disc)
	_bulbs = Node3D.new() # (on the stand: they don't turn)
	add_child(_bulbs)
	_paint()
	_cyl(_rotor, R + 0.006, 0.018, Vector3(0, 0, -0.0105), _mat(Color(0.12, 0.05, 0.08), 0.5, 0.2)) # back plate (behind the fields)
	var rim := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = R - 0.004
	torus.outer_radius = R + 0.008
	rim.mesh = torus
	rim.rotation_degrees.x = 90.0
	rim.material_override = gold
	_rotor.add_child(rim)
	for i in N: # pegs between the fields, and the words
		var a := TAU * i / N
		var peg := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.006
		sm.height = 0.012
		peg.mesh = sm
		peg.material_override = gold
		peg.position = Vector3(cos(a), sin(a), 0) * (R - 0.012) + Vector3(0, 0, 0.006)
		_rotor.add_child(peg)
		var mid := a + PI / N
		var l := Label3D.new()
		l.text = "WIN!" if _fields[i] else "NOPE!"
		l.font_size = 40
		l.pixel_size = 0.0006
		l.outline_size = 8
		l.outline_modulate = Color(0.05, 0.03, 0.06)
		l.modulate = Color(1, 1, 1)
		l.position = Vector3(cos(mid), sin(mid), 0) * R * 0.62 + Vector3(0, 0, 0.002)
		l.rotation.z = mid if cos(mid) >= 0.0 else mid + PI # along the radius, never upside down
		_rotor.add_child(l)
	_cyl(_rotor, 0.022, 0.016, Vector3(0, 0, 0.008), gold) # hub
	# the arrow at the top (doesn't turn): a red wedge pointing down onto the fields
	_arrow = Node3D.new()
	_arrow.position = Vector3(0, R + 0.03, 0.02)
	add_child(_arrow)
	var arrow := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(0.035, 0.045, 0.012)
	arrow.mesh = pm
	arrow.rotation_degrees.z = 180.0 # point down
	arrow.position.y = -0.012
	var red := _mat(Color(0.95, 0.1, 0.1), 0.3, 0.2)
	red.emission_enabled = true
	red.emission = Color(1.0, 0.15, 0.1)
	red.emission_energy_multiplier = 0.5
	arrow.material_override = red
	_arrow.add_child(arrow)
	var hint := Label3D.new()
	hint.text = "HOLD THE RIM WITH TRIGGER OR GRIP" + "\n" + "AND SPIN IT!"
	hint.name = "Hint"
	hint.font_size = 40
	hint.pixel_size = 0.0007
	hint.outline_size = 8
	hint.outline_modulate = Color(0.05, 0.03, 0.06)
	hint.modulate = Color(1.0, 0.85, 0.4)
	hint.position = Vector3(0, R + 0.085, 0.02)
	add_child(hint)
	_result = Label3D.new()
	_result.font_size = 96
	_result.pixel_size = 0.0008
	_result.outline_size = 16
	_result.outline_modulate = Color(0.05, 0.03, 0.06)
	_result.position = Vector3(0, 0, 0.06)
	_result.no_depth_test = true
	_result.render_priority = 10
	_result.visible = false
	add_child(_result)
	# for the beam: trigger on the wheel spins it too
	_body = StaticBody3D.new()
	_body.set_meta("target_id", 0)
	_body.set_meta("kind", "wheel")
	var shape := CollisionShape3D.new()
	var cs := CylinderShape3D.new()
	cs.radius = R + 0.01
	cs.height = 0.04
	shape.shape = cs
	shape.rotation_degrees.x = 90.0
	_body.add_child(shape)
	add_child(_body)
	GameFont.apply_to(self)
	_angle = randf() * TAU
	_rotor.rotation.z = _angle
	_omega = 0.0
	_state = "idle"
	_waiting_t = 0.0
	_prev.clear()
	_last_peg = _peg_index()


## (The beam's trigger on the wheel no longer spins it: it is spun by holding its rim.)


func _process(delta: float) -> void:
	if _rotor == null or not visible:
		return
	match _state:
		"idle":
			_hold(delta)
			_waiting_t += delta
			if _waiting_t > 40.0: # (the game waits for it: after a while it spins by itself)
				_start(9.0)
		"spinning":
			var speed := absf(_omega)
			var next := maxf(speed - _decel * delta, 0.0)
			var step := (speed + next) * 0.5 * delta
			var dir := signf(_omega)
			if _real:
				_angle += dir * step # free running: it stops where it stops
				_omega = dir * next
				if next <= 0.0:
					_win = _under_arrow()
					_finish()
			elif dir * (_target - _angle) <= step or next <= 0.0:
				_angle = _target # stops exactly on the planned spot
				_omega = 0.0
				_finish()
			else:
				_angle += dir * step
				_omega = dir * next
	_rotor.rotation.z = _angle
	# the arrow flicks when a peg passes it
	var peg := _peg_index()
	if peg != _last_peg:
		_last_peg = peg
		_flap = 1.0
		tick.emit()
	_flap = maxf(_flap - delta * 8.0, 0.0)
	_arrow.rotation.z = -signf(_omega) * _flap * 0.35
	if _state == "done":
		_done_t += delta
		_result.scale = Vector3.ONE * (1.0 + 0.15 * sin(_done_t * 8.0) * exp(-_done_t * 2.0))


## The fields' colours from the look now (gold, Las Vegas, the chosen metal): the look can change while
## the wheel stands here (an achievement's colour picked in the menu, Lady Luck earned on the wheel).
func _paint() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := 8
	for i in N:
		var c: Color = (WIN_COLOURS if _fields[i] else NOPE_COLOURS)[i % 2]
		if golden: # bright gold WIN!, dark gold NOPE!
			var g := golden_colour # bright for WIN!, dark for NOPE!
			c = ([g.lightened(0.15), g] if _fields[i] else [g.darkened(0.55), g.darkened(0.68)])[i % 2]
		elif vegas: # gold and green for WIN!, black and red for NOPE!, like a casino wheel
			c = ([Color(1.0, 0.8, 0.1), Color(0.1, 0.7, 0.3)] if _fields[i] else [Color(0.08, 0.06, 0.08), Color(0.8, 0.05, 0.1)])[i % 2]
		var a0 := TAU * i / N
		for s in steps:
			var p := a0 + TAU / N * s / steps
			var q := a0 + TAU / N * (s + 1) / steps
			for v in [Vector3.ZERO, Vector3(cos(p), sin(p), 0) * R, Vector3(cos(q), sin(q), 0) * R]:
				st.set_color(c)
				st.set_normal(Vector3.BACK)
				st.add_vertex(v)
	_disc.mesh = st.commit()
	_paint_bulbs()


## A ring of light bulbs round the rim while Lady Luck is on (see _paint).
func _paint_bulbs() -> void:
	for c in _bulbs.get_children():
		_bulbs.remove_child(c)
		c.queue_free()
	if not vegas:
		return
	var bulb := StandardMaterial3D.new()
	bulb.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bulb.albedo_color = Color(2.0, 1.7, 0.9)
	for i in 24:
		var a := TAU * i / 24.0
		var b := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.0045
		sm.height = 0.009
		b.mesh = sm
		b.material_override = bulb
		b.position = Vector3(cos(a), sin(a), 0) * (R + 0.02) + Vector3(0, 0, 0.002)
		_bulbs.add_child(b)


## The look may change while the wheel is here: it is repainted only when something really changed.
func set_look(lady: bool, gold: bool, colour: Color) -> void:
	if lady == vegas and gold == golden and colour == golden_colour:
		return
	vegas = lady
	golden = gold
	golden_colour = colour
	if _disc != null:
		_paint()


## Is this hand's trigger held? (a test may set it as meta "trigger")
func _trigger(hand: Node3D) -> bool:
	if hand.has_meta("trigger"):
		return bool(hand.get_meta("trigger"))
	return hand is XRController3D and (hand as XRController3D).is_button_pressed("trigger_click")


## Take hold of the rim with the trigger and turn it: the wheel follows the hand; let go with a good
## swing and it spins (slower: it turns a little and comes to rest). Only touching it does nothing.
func _hold(delta: float) -> void:
	for hand in hands:
		if hand == null or not is_instance_valid(hand) or not (hand as Node3D).is_inside_tree():
			continue
		var pressed := _trigger(hand)
		var fresh: bool = pressed and not bool(_was_pressed.get(hand, false))
		_was_pressed[hand] = pressed
		if _grip_hand == null and fresh:
			var p := to_local((hand as Node3D).global_position)
			var r := Vector2(p.x, p.y).length()
			if absf(p.z) < TOUCH_DEPTH and r > R - RIM_IN and r < R + RIM_OUT: # on the rim: take hold
				_grip_hand = hand
				_grip_last = atan2(p.y, p.x)
				_omega = 0.0
				last_hand = hand
				gripped.emit(hand)
	if _grip_hand != null:
		var still := is_instance_valid(_grip_hand) and (_grip_by_grip or _trigger(_grip_hand))
		if still:
			var p := to_local(_grip_hand.global_position)
			var a := atan2(p.y, p.x)
			var turn := wrapf(a - _grip_last, -PI, PI)
			_grip_last = a
			_angle += turn # the wheel goes with the hand
			_omega = lerpf(_omega, turn / maxf(delta, 0.001), 0.5)
			return
		_grip_hand = null # let go
		_grip_by_grip = false
		if absf(_omega) >= SPIN_MIN:
			_start(_omega) # with a good swing: it spins
			return
	# turned slowly and let go: it rolls on a little and comes to rest again
	_angle += _omega * delta
	_omega = move_toward(_omega, 0.0, 6.0 * delta)


## Take hold of the rim with the grip (like the reroll lever): the same as the trigger on the rim.
func try_grab(hand: Node3D) -> bool:
	if _state != "idle" or _grip_hand != null or not visible:
		return false
	var p := to_local(hand.global_position)
	var r := Vector2(p.x, p.y).length()
	if not (absf(p.z) < TOUCH_DEPTH and r > R - RIM_IN and r < R + RIM_OUT):
		return false
	_grip_hand = hand
	_grip_by_grip = true
	_grip_last = atan2(p.y, p.x)
	_omega = 0.0
	last_hand = hand
	gripped.emit(hand)
	return true


func holds(hand: Node3D) -> bool:
	return _grip_by_grip and _grip_hand == hand


## The grip is let go: a good swing spins the wheel, like letting go of the trigger.
func release(hand: Node3D) -> void:
	if not holds(hand):
		return
	_grip_hand = null
	_grip_by_grip = false
	if absf(_omega) >= SPIN_MIN:
		_start(_omega)


## Spin for real. Real: it just brakes (a little differently every time, like a real wheel's bearing).
## Deterministic: plan where it stops (a field of the rolled kind, somewhere inside it) and brake just
## so that it gets there.
func _start(omega: float) -> void:
	spun.emit(absf(omega))
	var speed := clampf(absf(omega), 6.0, 16.0)
	if sparks:
		_spark_on()
	var dir := signf(omega) if omega != 0.0 else 1.0
	var hint := get_node_or_null("Hint")
	if hint != null:
		hint.visible = false
	_omega = dir * speed
	_state = "spinning"
	if _real:
		_decel = DECEL * randf_range(0.8, 1.2)
		return
	var candidates: Array = []
	for i in N:
		if _fields[i] == _win:
			candidates.append(i)
	var field: int = candidates[randi() % candidates.size()]
	var half := PI / N
	# the arrow is at the top (PI/2): field i's middle is at TAU*i/N + half on the rotor
	var stop := PI * 0.5 - (TAU * field / N + half) + randf_range(-half * 0.7, half * 0.7)
	var natural := speed * speed / (2.0 * DECEL)
	var d := fposmod(dir * (stop - _angle), TAU)
	while d < natural - PI:
		d += TAU
	while d < TAU * 1.5: # at least one and a half turns, even after a weak swipe
		d += TAU
	_target = _angle + dir * d
	_decel = speed * speed / (2.0 * d)


func _spark_on() -> void:
	_sparks = CPUParticles3D.new()
	_sparks.amount = 60
	_sparks.lifetime = 0.5
	_sparks.local_coords = false
	_sparks.direction = Vector3(0, 1, 0.3)
	_sparks.spread = 60.0
	_sparks.initial_velocity_min = 0.3
	_sparks.initial_velocity_max = 0.8
	_sparks.gravity = Vector3(0, -2.0, 0)
	var dot := SphereMesh.new()
	dot.radius = 0.002
	dot.height = 0.004
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(3.0, 2.0, 0.6)
	dot.material = glow
	_sparks.mesh = dot
	_sparks.position = Vector3(0, R + 0.012, 0.01) # where the pegs pass the arrow
	add_child(_sparks)
	_sparks.emitting = true


func _finish() -> void:
	if _sparks != null:
		_sparks.emitting = false
	_state = "done"
	_done_t = 0.0
	_result.text = "WIN!" if _win else "NOPE!"
	_result.modulate = Color(1.0, 0.85, 0.2) if _win else Color(1.0, 0.3, 0.3)
	_result.visible = true
	GameFont.apply_to(_result)
	landed.emit(_win)


## Is the arrow on a WIN! field?
func _under_arrow() -> bool:
	var a := fposmod(PI * 0.5 - _angle, TAU)
	return _fields[int(floor(a / (TAU / N))) % N]


func _peg_index() -> int:
	return int(floor((_angle - PI * 0.5) / (TAU / N)))


func is_done() -> bool:
	return _state == "done"


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)


func _cyl(parent: Node3D, radius: float, height: float, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = height
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
