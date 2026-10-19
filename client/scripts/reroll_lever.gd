class_name RerollLever
extends Node3D
## A little slot machine at one end of the joker board. In the shop, grab the red ball with a grip
## and pull the lever down: the reels spin and the shop rerolls. The price of the next reroll is
## shown on the front; when you can't afford it the machine goes dark and the lever is stiff.

signal pulled

const GRAB_RADIUS := 0.08
const PULL_ANGLE := 55.0          # degrees down that count as a pull
const MAX_ANGLE := 75.0

var _arm: Node3D                  # pivot of the lever
var _ball: MeshInstance3D
var _price: Label3D
var _reels: Array[MeshInstance3D] = []
var _reel_mat: ShaderMaterial
var _screen_mat: StandardMaterial3D
var _hand: Node3D
var _angle := 0.0                 # current pull, degrees
var _fired := false
var _spin := 0.0                  # reel spin left (seconds)
var _enabled := false
var rainbow := false               # achievement reward "Lever Frenzy": the cabinet flashes in rainbow colours while the reels spin
var _cabinet: StandardMaterial3D

const REEL_SHADER := """
shader_type spatial;
render_mode unshaded;
uniform float offset = 0.0;
uniform float lit = 1.0;
void fragment() {
	float y = UV.y + offset;
	float sym = floor(y * 3.0);
	float h = fract(sin(sym * 12.9898) * 43758.5453);
	vec3 col = h < 0.25 ? vec3(0.95, 0.2, 0.2) : (h < 0.5 ? vec3(0.2, 0.5, 1.0) : (h < 0.75 ? vec3(1.0, 0.78, 0.15) : vec3(0.25, 0.85, 0.35)));
	float shape = smoothstep(0.32, 0.26, length(vec2(UV.x - 0.5, fract(y * 3.0) - 0.5)));
	ALBEDO = mix(vec3(0.95, 0.93, 0.86), col, shape) * (0.25 + 0.95 * lit);
}
"""


func _ready() -> void:
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.7, 0.08, 0.1)
	red.roughness = 0.35
	_cabinet = red
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(0.9, 0.68, 0.25)
	gold.metallic = 0.6
	gold.roughness = 0.3
	gold.emission_enabled = true
	gold.emission = Color(0.9, 0.68, 0.25)
	gold.emission_energy_multiplier = 0.15
	_box(Vector3(0.1, 0.11, 0.07), Vector3(0, 0.055, 0), red)          # cabinet
	_box(Vector3(0.104, 0.008, 0.074), Vector3(0, 0.112, 0), gold)    # top trim
	_box(Vector3(0.084, 0.044, 0.004), Vector3(0, 0.07, 0.036), gold) # window frame
	var shader := Shader.new()
	shader.code = REEL_SHADER
	for i in 3:
		var reel := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(0.024, 0.036)
		reel.mesh = quad
		var m := ShaderMaterial.new()
		m.shader = shader
		m.set_shader_parameter("offset", float(i) * 0.37)
		reel.material_override = m
		reel.position = Vector3(-0.026 + i * 0.026, 0.07, 0.0385)
		add_child(reel)
		_reels.append(reel)
	# price display under the window
	_screen_mat = StandardMaterial3D.new()
	_screen_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_screen_mat.albedo_color = Color(0.05, 0.05, 0.06)
	_box(Vector3(0.06, 0.02, 0.003), Vector3(0, 0.027, 0.0365), _screen_mat)
	_price = Label3D.new()
	_price.text = "REROLL"
	_price.font_size = 32
	_price.pixel_size = 0.00045
	_price.outline_size = 0
	_price.modulate = Color(0.3, 1.0, 0.5)
	_price.position = Vector3(0, 0.027, 0.0385)
	add_child(_price)
	# the lever on the right side: pivot at mid height, arm up, red ball on top
	_arm = Node3D.new()
	_arm.position = Vector3(0.058, 0.06, 0)
	add_child(_arm)
	var rod := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.004
	cyl.bottom_radius = 0.004
	cyl.height = 0.08
	rod.mesh = cyl
	rod.material_override = gold
	rod.position = Vector3(0.006, 0.04, 0)
	_arm.add_child(rod)
	_ball = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.012
	sphere.height = 0.024
	_ball.mesh = sphere
	var ball_mat := StandardMaterial3D.new()
	ball_mat.albedo_color = Color(0.9, 0.08, 0.1)
	ball_mat.roughness = 0.25
	ball_mat.emission_enabled = true
	ball_mat.emission = Color(0.9, 0.08, 0.1)
	ball_mat.emission_energy_multiplier = 0.25
	_ball.material_override = ball_mat
	_ball.position = Vector3(0.006, 0.082, 0)
	_arm.add_child(_ball)
	_box(Vector3(0.012, 0.02, 0.02), Vector3(0.053, 0.06, 0), gold) # hinge


## Left-handed mode: the lever moves to the machine's left side, towards the left (pointing) hand.
func set_mirrored(on: bool) -> void:
	if _arm == null:
		return
	var s := -1.0 if on else 1.0
	_arm.position.x = 0.058 * s
	for c in _arm.get_children():
		(c as Node3D).position.x = 0.006 * s


func _box(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	return mi


## In the shop or not, can the player pay, and what the next reroll costs.
## Achievement reward "One-Armed Bandit": a golden knob (main.gd adds the coin sound).
## "One-Armed Bandit" reward: the lever's ball in the chosen colour (alpha 0: the normal red).
func set_metal(colour: Color) -> void:
	var m := _ball.material_override as StandardMaterial3D
	var on := colour.a > 0.0
	var c := colour if on else Color(0.9, 0.08, 0.1)
	m.albedo_color = c
	m.emission = c
	m.metallic = 0.85 if on else 0.0


func set_shop(open: bool, can_afford: bool, cost: int) -> void:
	_enabled = open and can_afford
	_price.text = ("$%d" % cost) if open else "REROLL"
	_price.modulate = Color(0.3, 1.0, 0.5) if _enabled else Color(0.5, 0.2, 0.2)
	for reel in _reels:
		(reel.material_override as ShaderMaterial).set_shader_parameter("lit", 1.0 if open else 0.2)


func try_grab(hand: Node3D) -> bool:
	if _hand != null or hand.global_position.distance_to(_ball.global_position) > GRAB_RADIUS:
		return false
	_hand = hand
	_fired = false
	return true


func release(hand: Node3D) -> void:
	if hand == _hand:
		_hand = null


func holds(hand: Node3D) -> bool:
	return hand == _hand


func _process(delta: float) -> void:
	if _hand != null and is_instance_valid(_hand):
		# the lever follows the hand: how far down (around the pivot, in the machine's side plane)
		var local := _arm.get_parent_node_3d().to_local(_hand.global_position) - _arm.position
		var down := rad_to_deg(atan2(local.z, local.y)) # 0 = upright, + = pulled towards the player
		var limit := MAX_ANGLE if _enabled else 12.0 # stiff when there is no reroll to buy
		_angle = clampf(down, 0.0, limit)
		if _angle >= PULL_ANGLE and not _fired and _enabled:
			_fired = true
			_spin = 1.0
			pulled.emit()
	else:
		_angle = move_toward(_angle, 0.0, delta * 260.0) # springs back up
	_arm.rotation_degrees.x = _angle
	if rainbow and _cabinet != null:
		var on := _spin > 0.0
		_cabinet.emission_enabled = on
		if on:
			var c := Color.from_hsv(fmod(Time.get_ticks_msec() / 1000.0 * 2.5, 1.0), 0.85, 1.0)
			_cabinet.albedo_color = c
			_cabinet.emission = c
			_cabinet.emission_energy_multiplier = 1.2
		else:
			_cabinet.albedo_color = Color(0.7, 0.08, 0.1)
	if _spin > 0.0:
		_spin -= delta
		for i in _reels.size():
			var m := _reels[i].material_override as ShaderMaterial
			m.set_shader_parameter("offset", float(m.get_shader_parameter("offset")) + delta * (4.0 + i * 1.5) * _spin)
