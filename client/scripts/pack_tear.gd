class_name PackTear
extends Node3D
## A booster pack waiting to be torn open: it floats in front of the player, wobbles and sparkles.
## Grab it with both hands (grip) and pull them apart – it rips along the top and the halves stay
## in the hands for a moment while paper bits fly. Pointing at it and pulling the trigger rips it
## open at once. `torn` fires the moment it rips (the client tells the game to open the pack).

signal torn

const SIZE := Vector2(0.1, 0.134)  # the pack picture's 71:95 cell, a bit bigger than a card
const GRAB_RADIUS := 0.14       # hand this close to the pack's edge can take hold of it
const TEAR_DISTANCE := 0.15     # hands this much further apart than when grabbed = rip
const AFTER := 1.1              # seconds the halves and bits stay after ripping

var _material: Material
var _hands := {}                # hand node -> its grip offset (pack-local) when it took hold
var _start_gap := 0.0
var _time := 0.0
var _ripped := false
var _rip_time := 0.0
var _halves: Array[Node3D] = []
var _half_hands: Array = []
var _half_vel: Array[Vector3] = []
var _bits: Array[Dictionary] = []
var _body: Node3D
var _glow: MeshInstance3D


func setup(material: Material) -> void:
	_material = material


func _ready() -> void:
	_body = Node3D.new()
	add_child(_body)
	# two halves side by side; together they look like one pack until it rips
	for side in [-1.0, 1.0]:
		var half := Node3D.new()
		half.position.x = side * SIZE.x * 0.25
		_body.add_child(half)
		for face in [0, 1]:
			var mi := MeshInstance3D.new()
			var quad := QuadMesh.new()
			quad.size = Vector2(SIZE.x * 0.5, SIZE.y)
			mi.mesh = quad
			if _material != null:
				var m: Material = _material.duplicate()
				if m is StandardMaterial3D: # show only this half of the pack picture
					var sm := m as StandardMaterial3D
					sm.uv1_offset.x += (0.0 if side < 0 else 0.5) * sm.uv1_scale.x
					sm.uv1_scale.x *= 0.5
				mi.material_override = m
			else:
				var plain := StandardMaterial3D.new()
				plain.albedo_color = Color(0.85, 0.3, 0.3)
				mi.material_override = plain
			mi.rotation_degrees.y = 180.0 * face
			mi.position.z = 0.001 * (1 - face * 2)
			half.add_child(mi)
		_halves.append(half)
	# a soft golden glow behind it: "open me"
	_glow = MeshInstance3D.new()
	var gq := QuadMesh.new()
	gq.size = SIZE * 1.8
	_glow.mesh = gq
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var tex := GradientTexture2D.new()
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.85, 0.4, 0.9))
	g.set_color(1, Color(1.0, 0.85, 0.4, 0.0))
	tex.gradient = g
	gm.albedo_texture = tex
	_glow.material_override = gm
	_glow.position.z = -0.01
	_body.add_child(_glow)
	# something to point the beam at (trigger = rip at once)
	var body := StaticBody3D.new()
	body.set_meta("target_id", -2)
	body.set_meta("kind", "pack")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(SIZE.x, SIZE.y, 0.02)
	shape.shape = box
	body.add_child(shape)
	_body.add_child(body)


func is_ripped() -> bool:
	return _ripped


## A hand presses grip near the pack: it takes hold of its edge. True if it did.
func grab(hand: Node3D) -> bool:
	if _ripped or _hands.has(hand) or _hands.size() >= 2:
		return false
	if hand.global_position.distance_to(global_position) > GRAB_RADIUS:
		return false
	_hands[hand] = to_local(hand.global_position)
	if _hands.size() == 2:
		var hs := _hands.keys()
		_start_gap = (hs[0] as Node3D).global_position.distance_to((hs[1] as Node3D).global_position)
	return true


func release(hand: Node3D) -> void:
	_hands.erase(hand)


func holds(hand: Node3D) -> bool:
	return _hands.has(hand)


## Rip it open (pulled apart, or the trigger shortcut).
func rip() -> void:
	if _ripped:
		return
	_ripped = true
	_rip_time = 0.0
	_glow.visible = false
	var hs := _hands.keys()
	# the half on each side goes with the hand on that side; without hands they fly apart
	for i in 2:
		var half := _halves[i]
		var hand: Node3D = null
		for h in hs:
			var side := signf(to_local((h as Node3D).global_position).x)
			if (side < 0 and i == 0) or (side >= 0 and i == 1):
				hand = h
		_half_hands.append(hand)
		_half_vel.append(Vector3((i * 2 - 1) * 0.6, 0.25, 0.1))
		var xf := half.global_transform
		half.top_level = true
		half.global_transform = xf
	_spawn_bits()
	torn.emit()


func _spawn_bits() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.008, 0.012)
	for i in 26:
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		var palette := [Color(1, 0.85, 0.3), Color(1, 1, 1), Color(0.95, 0.4, 0.5), Color(0.4, 0.75, 1.0)]
		m.albedo_color = palette[i % palette.size()] * 1.6
		mi.material_override = m
		add_child(mi)
		mi.position = Vector3(rng.randf_range(-SIZE.x, SIZE.x) * 0.4, SIZE.y * 0.45, 0)
		_bits.append({"node": mi, "vel": Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(0.4, 1.1), rng.randf_range(0.1, 0.6)),
				"spin": Vector3(rng.randf_range(-12, 12), rng.randf_range(-12, 12), rng.randf_range(-12, 12))})


func _process(delta: float) -> void:
	_time += delta
	if not _ripped:
		# waiting: it bobs and wiggles, eager to be opened
		_body.position = Vector3(0, sin(_time * 2.2) * 0.008, 0)
		_body.rotation = Vector3(0, sin(_time * 1.3) * 0.25, sin(_time * 3.1) * 0.05)
		_glow.scale = Vector3.ONE * (1.0 + 0.1 * sin(_time * 4.0))
		if _hands.size() == 2:
			var hs := _hands.keys()
			var a := (hs[0] as Node3D).global_position
			var b := (hs[1] as Node3D).global_position
			global_position = (a + b) * 0.5 # held between the hands
			if a.distance_to(b) - _start_gap > TEAR_DISTANCE:
				rip()
		elif _hands.size() == 1:
			global_position = (_hands.keys()[0] as Node3D).global_position # one hand carries it
		return
	_rip_time += delta
	for i in _halves.size():
		var half := _halves[i]
		var hand = _half_hands[i]
		if hand != null and is_instance_valid(hand) and _rip_time < 0.45:
			half.global_position = half.global_position.lerp((hand as Node3D).global_position, 0.4)
		else:
			_half_vel[i] += Vector3(0, -1.8, 0) * delta
			half.global_position += _half_vel[i] * delta
			half.rotate_z(delta * (3.0 if i == 0 else -3.0))
		half.scale = Vector3.ONE * clampf(1.0 - (_rip_time - 0.5) / 0.6, 0.01, 1.0)
	for b in _bits:
		var n: MeshInstance3D = b["node"]
		b["vel"] += Vector3(0, -1.2, 0) * delta
		n.position += b["vel"] * delta
		n.rotation += b["spin"] * delta
	if _rip_time > AFTER:
		for half in _halves:
			half.queue_free()
		queue_free()
