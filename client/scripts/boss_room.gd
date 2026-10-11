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
