class_name BossRoom
extends Node3D
## The casino changes with the boss blind you are playing against (the colour of the room comes
## from the boss chip, see CasinoRoom.set_boss):
##   The Wall      a brick wall rises from the floor all around you and the table
##   The Water     wave light plays over the ceiling
##   The Needle    everything goes dark but the table
##   The Flint     all lights at half strength
##   The Eye       a huge eye in the screen above BALATRO that follows you
##   The Mouth     a huge mouth in that screen, chewing
##   The Fish      bubbles rise through the room (and it turns blue)
##   The Wheel     every machine in the room runs wild
##   The Manacle   chains hang from the walls
##   The Serpent   a glowing serpent winds over the ceiling
## and the showdown bosses of ante 8 (see the end of this file):
##   Amber Acorn   acorns rain from the ceiling
##   Verdant Leaf  leaves whirl down through the room
##   Violet Vessel a chalice over the table fills with violet as your score nears the target
##   Crimson Heart a heart over the table beats, the room's light beats with it
##   Cerulean Bell a big blue bell hangs over the table and swings
## (The Ox shakes your coin pile and The Tooth takes a coin per card – both done in main.gd.)
## Calm Lights: only the calm ones stay (walls, darkness, chains, eye, mouth), no wave light,
## bubbles or racing machines.
## A child of the casino room: positions are in the room's coordinates.

var room: CasinoRoom
var eyes: Callable                 # -> Vector3: the player's eyes (The Eye looks at you)

var _key := ""
var _calm := false
var _amount := 0.0                 # fades the effect in (0 .. 1)
var _time := 0.0
var _caustics: MeshInstance3D
var _face: MeshInstance3D          # eye / mouth on the big screen
var _bubbles: CPUParticles3D
var _chains: Node3D
var _snake: Array[MeshInstance3D] = []
var _ring: MeshInstance3D          # The Wall
var _ring_rise := 0.0
const RING_RADIUS := 1.6
const RING_HEIGHT := 2.7


func _ready() -> void:
	_build_caustics()
	_build_face()
	_build_bubbles()
	_build_chains()
	_build_snake()
	_build_wall_ring()
	_build_showdown()
	_show("")


## key: the boss blind's key ("bl_wall" ...) or "" when no boss round is being played.
func apply(key: String, calm: bool) -> void:
	if key == _key and calm == _calm:
		return
	if key != _key:
		_amount = 0.0
		_ring_rise = 0.0
	_key = key
	_calm = calm
	_show(key)


func _show(key: String) -> void:
	_caustics.visible = key == "bl_water" and not _calm
	_face.visible = key == "bl_eye" or key == "bl_mouth"
	(_face.material_override as ShaderMaterial).set_shader_parameter("mouth", key == "bl_mouth")
	_bubbles.emitting = key == "bl_fish" and not _calm
	_chains.visible = key == "bl_manacle"
	_ring.visible = key == "bl_wall"
	for s in _snake:
		s.visible = key == "bl_serpent"
	_show_showdown(key)
	room.set_boss_effects(
		1.0,                                                                  # room size (unused now)
		0.85 if key == "bl_needle" else (0.5 if key == "bl_flint" else 0.0),  # darkness
		key == "bl_wheel" and not _calm)                                      # machines run wild


func _process(delta: float) -> void:
	if _key == "":
		return
	_time += delta
	_amount = minf(_amount + delta / 2.0, 1.0)
	if _face.visible:
		var m := _face.material_override as ShaderMaterial
		m.set_shader_parameter("open", _amount)
		if eyes.is_valid(): # the pupil looks at you
			var to: Vector3 = to_local(eyes.call()) - _face.position
			m.set_shader_parameter("look", Vector2(clampf(to.x / 3.0, -1.0, 1.0), clampf(to.y / 2.0, -1.0, 1.0)))
	if _caustics.visible:
		(_caustics.material_override as ShaderMaterial).set_shader_parameter("strength", 0.5 * _amount)
	if _ring.visible: # The Wall: rises slowly, centred between you and the table
		_ring_rise = minf(_ring_rise + delta / 6.0, 1.0)
		var r := _ring_rise * _ring_rise * (3.0 - 2.0 * _ring_rise)
		var centre := room._table.global_position
		if eyes.is_valid():
			centre = centre.lerp(eyes.call(), 0.5)
		_ring.global_position = Vector3(centre.x, -RING_HEIGHT * 0.5 + RING_HEIGHT * r, centre.z)
	_animate_showdown(delta)
	if _snake[0].visible: # the serpent winds along a slow loop over the ceiling
		for i in _snake.size():
			var t := _time * 0.35 - i * 0.018
			_snake[i].position = Vector3(3.2 * sin(t), CasinoRoom.ROOM_HEIGHT - 0.25 - 0.08 * sin(t * 5.0 + i * 0.5),
					CasinoRoom.ROOM_CENTER_Z + 2.6 * sin(t * 1.7))


# ---------------------------------------------------------------- the pieces

func _build_caustics() -> void:
	_caustics = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(CasinoRoom.ROOM_HALF.x * 2.0, CasinoRoom.ROOM_HALF.y * 2.0)
	_caustics.mesh = q
	_caustics.rotation_degrees.x = 90.0 # facing down
	_caustics.position = Vector3(0, CasinoRoom.ROOM_HEIGHT - 0.05, CasinoRoom.ROOM_CENTER_Z)
	var m := ShaderMaterial.new()
	m.shader = Shader.new()
	m.shader.code = CAUSTICS
	_caustics.material_override = m
	_caustics.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_caustics)


func _build_face() -> void:
	_face = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(2.9, 1.42)
	_face.mesh = q
	_face.position = Vector3(0, 1.92, CasinoRoom.ROOM_CENTER_Z - CasinoRoom.ROOM_HALF.y + 0.135)
	var m := ShaderMaterial.new()
	m.shader = Shader.new()
	m.shader.code = FACE
	_face.material_override = m
	_face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_face)


func _build_bubbles() -> void:
	_bubbles = CPUParticles3D.new()
	var s := SphereMesh.new()
	s.radius = 0.03
	s.height = 0.06
	s.radial_segments = 10
	s.rings = 5
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(0.5, 0.8, 1.0, 0.35)
	s.material = m
	_bubbles.mesh = s
	_bubbles.amount = 140
	_bubbles.lifetime = 7.0
	_bubbles.preprocess = 7.0
	_bubbles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_bubbles.emission_box_extents = Vector3(CasinoRoom.ROOM_HALF.x - 0.3, 0.05, CasinoRoom.ROOM_HALF.y - 0.3)
	_bubbles.position = Vector3(0, 0.1, CasinoRoom.ROOM_CENTER_Z)
	_bubbles.direction = Vector3.UP
	_bubbles.spread = 8.0
	_bubbles.gravity = Vector3(0, 0.12, 0)
	_bubbles.initial_velocity_min = 0.25
	_bubbles.initial_velocity_max = 0.5
	_bubbles.scale_amount_min = 0.4
	_bubbles.scale_amount_max = 1.6
	_bubbles.emitting = false
	add_child(_bubbles)


## Heavy iron chains sagging along the walls under the ceiling.
func _build_chains() -> void:
	_chains = Node3D.new()
	add_child(_chains)
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.55, 0.55, 0.58)
	iron.emission_enabled = true # visible in the dark room
	iron.emission = Color(0.12, 0.12, 0.14)
	iron.metallic = 0.85
	iron.roughness = 0.4
	var link := TorusMesh.new()
	link.inner_radius = 0.035
	link.outer_radius = 0.062
	link.rings = 12
	link.ring_segments = 6
	var hx := CasinoRoom.ROOM_HALF.x - 0.12
	var front := CasinoRoom.ROOM_CENTER_Z + CasinoRoom.ROOM_HALF.y - 0.12
	var back := CasinoRoom.ROOM_CENTER_Z - CasinoRoom.ROOM_HALF.y + 0.12
	var runs := [[Vector3(-hx, 0, back), Vector3(-hx, 0, -0.9)], [Vector3(-hx, 0, 0.6), Vector3(-hx, 0, front)],
			[Vector3(hx, 0, back), Vector3(hx, 0, -1.4)], [Vector3(hx, 0, 0.3), Vector3(hx, 0, front)],
			[Vector3(-hx, 0, back), Vector3(-1.9, 0, back)], [Vector3(1.9, 0, back), Vector3(hx, 0, back)]]
	for r in runs:
		var a: Vector3 = r[0]
		var b: Vector3 = r[1]
		var n := int(a.distance_to(b) / 0.1)
		for i in n:
			var k := float(i) / n
			var p := a.lerp(b, k)
			p.y = CasinoRoom.ROOM_HEIGHT - 0.3 - 0.45 * sin(k * PI) # sagging
			var mi := MeshInstance3D.new()
			mi.mesh = link
			mi.material_override = iron
			mi.position = p
			var along := (b - a).normalized()
			mi.basis = Basis.looking_at(along, Vector3.UP).rotated(along, PI * 0.5 * (i % 2))
			_chains.add_child(mi)
		for end in [a, b]: # a shackle bolted to the wall at each end
			var bolt := MeshInstance3D.new()
			var s := SphereMesh.new()
			s.radius = 0.05
			s.height = 0.1
			bolt.mesh = s
			bolt.material_override = iron
			bolt.position = Vector3(end.x, CasinoRoom.ROOM_HEIGHT - 0.3, end.z)
			_chains.add_child(bolt)


## The Wall: a round brick wall around you and the table (open at the top), rising from the floor.
func _build_wall_ring() -> void:
	_ring = MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = RING_RADIUS
	c.bottom_radius = RING_RADIUS
	c.height = RING_HEIGHT
	c.radial_segments = 64
	c.rings = 1
	c.cap_top = false
	c.cap_bottom = false
	_ring.mesh = c
	var m := ShaderMaterial.new()
	m.shader = Shader.new()
	m.shader.code = BRICKS
	_ring.material_override = m
	_ring.visible = false
	add_child(_ring)


## A glowing serpent: a string of spheres, thick at the head and thin at the tail.
func _build_snake() -> void:
	var n := 70
	for i in n:
		var mi := MeshInstance3D.new()
		var s := SphereMesh.new()
		var r := lerpf(0.1, 0.03, float(i) / n)
		s.radius = r
		s.height = r * 2.0
		s.radial_segments = 12
		s.rings = 6
		mi.mesh = s
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0.3, 1.8, 0.6) if i % 3 != 0 else Color(0.9, 2.0, 0.4)
		if i == 0:
			m.albedo_color = Color(0.4, 2.2, 0.7)
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_snake.append(mi)


# ---------------------------------------------------------------- shaders

## Old bricks in the wall's own coordinates (they rise with it): rows offset by half a brick,
## each brick a slightly different red-brown, grey mortar, darker towards the floor.
const BRICKS := """
shader_type spatial;
render_mode cull_disabled;
varying vec3 p;

float h(vec2 v) { return fract(sin(dot(v, vec2(127.1, 311.7))) * 43758.5453); }

void vertex() { p = VERTEX; }

void fragment() {
	float around = atan(p.x, p.z) * 1.6;           // 1.6 m radius: one unit = one metre
	vec2 b = vec2(around / 0.24, (p.y + 10.0) / 0.075);
	float row = floor(b.y);
	b.x += mod(row, 2.0) * 0.5;
	vec2 id = vec2(floor(b.x), row);
	vec2 f = fract(b);
	float mortar = step(f.x, 0.05) + step(f.y, 0.12);
	vec3 brick = mix(vec3(0.42, 0.14, 0.09), vec3(0.6, 0.25, 0.15), h(id));
	brick *= 0.8 + 0.2 * h(id + floor(f * 6.0));      // a little grain
	vec3 c = mix(brick, vec3(0.32, 0.3, 0.28), clamp(mortar, 0.0, 1.0));
	ALBEDO = c;
	ROUGHNESS = 0.95;
}
"""

## Water light on the ceiling: two drifting layers of bright, wobbling cells.
const CAUSTICS := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, shadows_disabled, fog_disabled;
uniform float strength = 0.5;

float cells(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	float d = 1.0;
	for (int y = -1; y <= 1; y++) for (int x = -1; x <= 1; x++) {
		vec2 g = vec2(float(x), float(y));
		vec2 o = 0.5 + 0.4 * sin(TIME * 0.8 + 6.2831 * fract(sin(dot(i + g, vec2(12.9, 78.2))) * 43758.5) + vec2(0.0, 1.6));
		d = min(d, length(g + o - f));
	}
	return d;
}

void fragment() {
	vec2 p = UV * vec2(10.0, 9.0);
	float c = pow(1.0 - cells(p + vec2(TIME * 0.05, 0.0)), 6.0) + pow(1.0 - cells(p * 1.3 - vec2(0.0, TIME * 0.04)), 6.0);
	ALBEDO = vec3(0.35, 0.75, 1.0) * c * strength;
}
"""

## The face in the big screen: an eye that follows you, or a mouth that chews.
const FACE := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, shadows_disabled, fog_disabled;
uniform bool mouth = false;
uniform float open = 1.0;
uniform vec2 look = vec2(0.0);

void fragment() {
	vec2 p = (UV - 0.5) * vec2(2.04, 1.0); // keep the shapes round on the wide screen
	p.y = -p.y;
	vec4 c = vec4(0.0);
	if (!mouth) {
		float lid = 0.42 * open * (1.0 - step(0.96, fract(TIME * 0.22))); // blinks now and then
		float eye = length(p / vec2(0.9, max(lid, 0.001)));
		if (eye < 1.0) {
			c = vec4(0.95, 0.92, 0.88, 1.0);
			vec2 iris_at = look * vec2(0.45, 0.15);
			float ir = length(p - iris_at);
			if (ir < 0.23) c.rgb = mix(vec3(0.75, 0.12, 0.1), vec3(0.35, 0.02, 0.02), ir / 0.23);
			if (ir < 0.1) c.rgb = vec3(0.02);
			if (length(p - iris_at - vec2(-0.05, 0.05)) < 0.03) c.rgb = vec3(1.0);
			c.rgb *= 1.0 - 0.5 * smoothstep(0.7, 1.0, eye);
		} else if (eye < 1.08) {
			c = vec4(0.05, 0.0, 0.02, 1.0);
		}
	} else {
		float chew = 0.5 + 0.5 * sin(TIME * 4.0);
		float h = (0.08 + 0.25 * chew) * open;
		float lips = length(p / vec2(0.85, h + 0.12));
		float inner = length(p / vec2(0.75, max(h, 0.001)));
		if (lips < 1.0) c = vec4(0.75, 0.1, 0.25, 1.0);
		if (inner < 1.0) {
			c = vec4(0.12, 0.0, 0.03, 1.0);
			if (abs(p.y) > h * 0.55 && fract(p.x * 6.0) > 0.12) c.rgb = vec3(0.95, 0.93, 0.85); // teeth
		}
	}
	ALBEDO = c.rgb;
	ALPHA = c.a;
}
"""


# ---------------------------------------------------------------- the showdown bosses (ante 8)
# Amber Acorn: acorns rain down. Verdant Leaf: leaves whirl through the room. Violet Vessel: a big
# chalice over the table fills with glowing violet as your score nears its huge target. Crimson
# Heart: a heart over the table beats, and the room's light beats with it. Cerulean Bell: a big
# blue bell hangs over the table and swings. (Calm Lights: no rain, no whirl, no beat, no swing.)

const OVER_TABLE := 1.05            # height above the table of the vessel, heart and bell

var vessel_fill := 0.0              # set by main.gd: score / target of the blind (Violet Vessel)
var _acorns: CPUParticles3D
var _leaves: CPUParticles3D
var _vessel: Node3D
var _vessel_liquid: MeshInstance3D
var _vessel_level := 0.0
var _heart: Node3D


## Where the Crimson Heart is (its middle), or null when it isn't there: the joker bolts start there.
func heart_point():
	if _heart == null or not _heart.is_visible_in_tree():
		return null
	return _heart.global_position + _heart.global_basis.y * 0.03
var _bell: Node3D
var _bell_clapper: Node3D


func _build_showdown() -> void:
	# Amber Acorn: little acorns falling from the ceiling
	var acorn := _acorn_mesh()
	_acorns = _rain(acorn, 160, 5.0, Vector3(0, -0.6, 0), 0.0)
	_acorns.scale_amount_min = 1.4
	_acorns.scale_amount_max = 2.2
	_acorns.angular_velocity_min = -90.0 # (tumbling as they fall)
	_acorns.angular_velocity_max = 90.0
	# Verdant Leaf: leaves drifting and whirling down
	var leaf := QuadMesh.new()
	leaf.size = Vector2(0.1, 0.066)
	var lm := StandardMaterial3D.new()
	lm.albedo_texture = _leaf_texture()
	lm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	lm.cull_mode = BaseMaterial3D.CULL_DISABLED
	lm.vertex_color_use_as_albedo = true
	lm.emission_enabled = true # (lit a little from inside: visible in the dark casino)
	lm.emission = Color(0.2, 0.45, 0.15)
	leaf.material = lm
	_leaves = _rain(leaf, 260, 9.0, Vector3(0.15, -0.3, 0.05), 3.0)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.35, 0.85, 0.3))
	ramp.set_color(1, Color(0.75, 0.8, 0.2))
	_leaves.color_initial_ramp = ramp
	_leaves.angular_velocity_min = -180.0
	_leaves.angular_velocity_max = 180.0
	_leaves.angle_min = 0.0
	_leaves.angle_max = 360.0
	# Violet Vessel: a chalice of gold and violet glass
	_vessel = Node3D.new()
	add_child(_vessel)
	var gold := _sd_mat(Color(0.9, 0.68, 0.28), 0.3, 0.8)
	_sd_cyl(_vessel, 0.16, 0.18, 0.04, Vector3(0, -0.36, 0), gold)            # foot
	_sd_cyl(_vessel, 0.035, 0.05, 0.22, Vector3(0, -0.23, 0), gold)          # stem
	_sd_sphere(_vessel, 0.07, Vector3(0, -0.2, 0), gold)                     # knot
	var glass := _sd_mat(Color(0.55, 0.25, 0.85, 0.35), 0.05, 0.0)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	_sd_cyl(_vessel, 0.34, 0.12, 0.36, Vector3(0, 0.06, 0), glass)           # the cup
	_sd_torus(_vessel, 0.33, 0.36, Vector3(0, 0.24, 0), gold)                # its golden rim
	var liquid := _sd_mat(Color(0.7, 0.2, 1.0), 0.2, 0.0)
	liquid.emission_enabled = true
	liquid.emission = Color(0.7, 0.2, 1.0)
	liquid.emission_energy_multiplier = 1.8
	var holder := Node3D.new()
	holder.position.y = -0.12 # (the liquid grows up from the cup's bottom)
	_vessel.add_child(holder)
	_vessel_liquid = _sd_cyl(holder, 0.12, 0.112, 0.002, Vector3(0, 0.001, 0), liquid)
	_vessel_liquid.mesh = (_vessel_liquid.mesh as CylinderMesh).duplicate() # (its own: reshaped as it fills)
	# Crimson Heart: a heart of two round lobes and a point
	_heart = Node3D.new()
	add_child(_heart)
	var red := _sd_mat(Color(0.9, 0.06, 0.12), 0.35, 0.1)
	red.emission_enabled = true
	red.emission = Color(1.0, 0.05, 0.12)
	red.emission_energy_multiplier = 0.8
	for side in [-1.0, 1.0]:
		_sd_sphere(_heart, 0.17, Vector3(side * 0.12, 0.06, 0), red)
	var point := MeshInstance3D.new()
	var pb := BoxMesh.new()
	pb.size = Vector3(0.24, 0.24, 0.2)
	point.mesh = pb
	point.material_override = red
	point.rotation_degrees.z = 45.0
	point.position.y = -0.07
	_heart.add_child(point)
	# Cerulean Bell: a big blue bell on a chain from the ceiling, with its clapper
	_bell = Node3D.new()
	add_child(_bell)
	var blue := _sd_mat(Color(0.2, 0.5, 1.0), 0.25, 0.7)
	blue.emission_enabled = true
	blue.emission = Color(0.15, 0.4, 1.0)
	blue.emission_energy_multiplier = 0.35
	_sd_cyl(_bell, 0.12, 0.3, 0.38, Vector3(0, -0.25, 0), blue)             # the bell's body
	_sd_sphere(_bell, 0.12, Vector3(0, -0.06, 0), blue)                      # its crown
	_sd_torus(_bell, 0.29, 0.33, Vector3(0, -0.44, 0), _sd_mat(Color(0.9, 0.7, 0.3), 0.3, 0.8)) # lip
	_sd_cyl(_bell, 0.012, 0.012, 1.4, Vector3(0, 0.66, 0), _sd_mat(Color(0.4, 0.4, 0.45), 0.4, 0.8)) # chain
	_bell_clapper = Node3D.new()
	_bell_clapper.position.y = -0.08
	_bell.add_child(_bell_clapper)
	_sd_cyl(_bell_clapper, 0.015, 0.015, 0.36, Vector3(0, -0.2, 0), _sd_mat(Color(0.3, 0.3, 0.35), 0.4, 0.8))
	_sd_sphere(_bell_clapper, 0.06, Vector3(0, -0.4, 0), _sd_mat(Color(0.85, 0.65, 0.25), 0.3, 0.8))


func _show_showdown(key: String) -> void:
	_acorns.emitting = key == "bl_final_acorn" and not _calm
	_leaves.emitting = key == "bl_final_leaf" and not _calm
	_vessel.visible = key == "bl_final_vessel"
	_heart.visible = key == "bl_final_heart"
	_bell.visible = key == "bl_final_bell"


func _animate_showdown(delta: float) -> void:
	var over := room._table.global_position + Vector3(0, OVER_TABLE, 0)
	var appear := _amount * _amount * (3.0 - 2.0 * _amount) # (comes down from the ceiling as the round starts)
	var drop := Vector3(0, (1.0 - appear) * 1.2, 0)
	if _vessel.visible: # stands on the table behind the joker board (comes down onto it)
		_vessel.global_position = room._table.global_transform * Vector3(-0.4, 0.38, -0.45) + drop # (left of Jimbo across the table)
		_vessel.rotation.y += delta * 0.2
		# the liquid fills the cup from its narrow bottom: its surface is always as wide as the cup is
		# at that height (the cup: 0.12 at the bottom, 0.34 at the top, 0.36 high)
		_vessel_level = lerpf(_vessel_level, clampf(vessel_fill, 0.0, 1.0), 1.0 - exp(-2.0 * delta))
		var h := maxf(0.34 * _vessel_level, 0.002)
		var m := _vessel_liquid.mesh as CylinderMesh
		m.height = h
		m.bottom_radius = 0.112
		m.top_radius = 0.12 + 0.22 * h / 0.36 - 0.008
		_vessel_liquid.position.y = h * 0.5
	if _heart.visible:
		_heart.global_position = over + drop
		var beat := 0.0
		if not _calm: # two quick beats a second, like a pulse
			var t := fmod(_time * 1.2, 1.0)
			beat = maxf(exp(-pow((t - 0.05) * 18.0, 2.0)), 0.6 * exp(-pow((t - 0.25) * 18.0, 2.0)))
		_heart.scale = Vector3.ONE * (1.0 + 0.12 * beat)
		if eyes.is_valid(): # turned towards you
			var to: Vector3 = eyes.call() - _heart.global_position
			to.y = 0.0
			if to.length() > 0.01:
				_heart.global_basis = Basis.looking_at(-to.normalized()).scaled(_heart.scale)
		room.set_boss_effects(1.0, 0.35 * beat, false) # the room's light beats with it
	if _bell.visible:
		_bell.global_position = over + drop + Vector3(0, 0.2, 0)
		var swing := 0.0 if _calm else sin(_time * 1.6) * 0.18
		_bell.rotation.z = swing
		_bell_clapper.rotation.z = (0.0 if _calm else sin(_time * 1.6 - 0.6) * 0.35) # lagging behind: it strikes


func _rain(mesh: Mesh, amount: int, life: float, gravity: Vector3, spin: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.mesh = mesh
	p.amount = amount
	p.lifetime = life
	p.preprocess = life
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(CasinoRoom.ROOM_HALF.x - 0.3, 0.05, CasinoRoom.ROOM_HALF.y - 0.3)
	p.position = Vector3(0, CasinoRoom.ROOM_HEIGHT - 0.1, CasinoRoom.ROOM_CENTER_Z)
	p.direction = Vector3.DOWN
	p.spread = 20.0
	p.gravity = gravity
	p.initial_velocity_min = 0.1
	p.initial_velocity_max = 0.3
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.3
	if spin > 0.0: # leaves sway from side to side as they fall
		p.tangential_accel_min = -spin * 0.1
		p.tangential_accel_max = spin * 0.1
	p.emitting = false
	add_child(p)
	return p


## An acorn: a brown nut with its cap.
func _acorn_mesh() -> Mesh:
	var st := SurfaceTool.new()
	var nut := SphereMesh.new()
	nut.radius = 0.022
	nut.height = 0.055
	nut.radial_segments = 10
	nut.rings = 6
	st.append_from(nut, 0, Transform3D(Basis(), Vector3(0, -0.012, 0)))
	var cap := SphereMesh.new()
	cap.radius = 0.025
	cap.height = 0.025
	cap.is_hemisphere = true
	cap.radial_segments = 10
	cap.rings = 4
	st.append_from(cap, 0, Transform3D(Basis(), Vector3(0, 0.008, 0)))
	var stem := CylinderMesh.new()
	stem.top_radius = 0.003
	stem.bottom_radius = 0.004
	stem.height = 0.014
	stem.radial_segments = 6
	st.append_from(stem, 0, Transform3D(Basis(), Vector3(0, 0.028, 0)))
	var m := st.commit()
	var shell := _sd_mat(Color(0.75, 0.45, 0.15), 0.45, 0.1)
	shell.emission_enabled = true # (a warm amber glow: visible in the dark casino)
	shell.emission = Color(0.8, 0.45, 0.1)
	shell.emission_energy_multiplier = 0.6
	m.surface_set_material(0, shell)
	return m


## A leaf shape (pointed oval with a midrib) on a transparent texture.
func _leaf_texture() -> ImageTexture:
	var w := 48
	var h := 32
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var u := (x + 0.5) / w * 2.0 - 1.0
			var v := (y + 0.5) / h * 2.0 - 1.0
			var inside := v * v < (1.0 - u * u) * (1.0 - u * u) * 0.95
			var rib := absf(v) < 0.07 and absf(u) < 0.9
			if inside:
				img.set_pixel(x, y, Color(0.6, 0.85, 0.5) if rib else Color(1, 1, 1))
			else:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)


func _sd_mat(c: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _sd_cyl(parent: Node3D, top: float, bottom: float, h: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = 32
	mi.mesh = c
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _sd_sphere(parent: Node3D, r: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	mi.mesh = s
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _sd_torus(parent: Node3D, inner: float, outer: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	t.rings = 40
	mi.mesh = t
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi
