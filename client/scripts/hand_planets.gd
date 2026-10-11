class_name HandPlanets
extends Node3D
## Every poker hand you have levelled up (Planet cards) floats in the room as its planet: the higher
## the level, the bigger it is. Each planet has its own surface (Earth with oceans, continents and
## clouds, Jupiter's bands and red spot, Saturn's ring ...), a small "Lv. 3" floats below it.
## The orbit is centred on a fixed point in the room (a child of the layout, over the player's place),
## not on the head: the planets circle the room slowly, and moving or turning the head moves nothing.

const ORBIT_RADIUS := 2.4
const ORBIT_HEIGHT := 0.9        # above the centre (roughly eye level)
const SPEED := 0.035             # radians per second: one round in about three minutes

## poker hand -> [planet name, surface kind, colours (3), ring, atmosphere colour]
## kinds: 0 rocky/cratered, 1 earth, 2 gas bands, 3 ice giant, 4 mars, 5 cloudy (venus)
const PLANETS := {
	"High Card": ["Pluto", 0, [Color(0.78, 0.7, 0.6), Color(0.55, 0.45, 0.38), Color(0.95, 0.9, 0.85)], false, Color(0, 0, 0)],
	"Pair": ["Mercury", 0, [Color(0.62, 0.6, 0.58), Color(0.38, 0.36, 0.35), Color(0.8, 0.78, 0.75)], false, Color(0, 0, 0)],
	"Two Pair": ["Uranus", 3, [Color(0.6, 0.88, 0.9), Color(0.5, 0.78, 0.84), Color(0.75, 0.95, 0.95)], false, Color(0.6, 0.95, 1.0)],
	"Three of a Kind": ["Venus", 5, [Color(0.95, 0.82, 0.55), Color(0.82, 0.62, 0.35), Color(1.0, 0.95, 0.8)], false, Color(1.0, 0.85, 0.5)],
	"Straight": ["Saturn", 2, [Color(0.93, 0.83, 0.58), Color(0.78, 0.62, 0.4), Color(0.95, 0.9, 0.75)], true, Color(1.0, 0.9, 0.6)],
	"Flush": ["Jupiter", 2, [Color(0.92, 0.82, 0.68), Color(0.7, 0.45, 0.3), Color(0.8, 0.3, 0.2)], false, Color(1.0, 0.85, 0.7)],
	"Full House": ["Earth", 1, [Color(0.08, 0.25, 0.65), Color(0.25, 0.5, 0.2), Color(0.6, 0.5, 0.32)], false, Color(0.45, 0.7, 1.0)],
	"Four of a Kind": ["Mars", 4, [Color(0.82, 0.38, 0.2), Color(0.5, 0.2, 0.12), Color(0.95, 0.6, 0.4)], false, Color(1.0, 0.6, 0.4)],
	"Straight Flush": ["Neptune", 3, [Color(0.22, 0.38, 0.92), Color(0.15, 0.25, 0.7), Color(0.6, 0.75, 1.0)], false, Color(0.4, 0.55, 1.0)],
	"Five of a Kind": ["Planet X", 5, [Color(0.7, 0.4, 0.95), Color(0.4, 0.2, 0.7), Color(0.95, 0.7, 1.0)], false, Color(0.8, 0.5, 1.0)],
	"Flush House": ["Ceres", 0, [Color(0.6, 0.6, 0.64), Color(0.4, 0.4, 0.44), Color(0.85, 0.85, 0.9)], false, Color(0, 0, 0)],
	"Flush Five": ["Eris", 0, [Color(0.9, 0.9, 0.97), Color(0.7, 0.72, 0.8), Color(1.0, 1.0, 1.0)], false, Color(0, 0, 0)],
}

const SURFACE := """
shader_type spatial;
uniform float kind = 0.0;
uniform vec3 col_a : source_color;
uniform vec3 col_b : source_color;
uniform vec3 col_c : source_color;
uniform vec3 atmo : source_color;
uniform float seed = 0.0;
uniform float spot = 0.0;   // Jupiter's great red spot
varying vec3 p;

float hash(vec3 q) { return fract(sin(dot(q, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float noise(vec3 x) {
	vec3 i = floor(x); vec3 f = fract(x); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1,0,0)), f.x), mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x), mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}
float fbm(vec3 x) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 5; i++) { v += a * noise(x); x = x * 2.03 + vec3(1.7, 9.2, 3.1); a *= 0.5; }
	return v;
}

void vertex() { p = normalize(VERTEX); }

void fragment() {
	vec3 n = normalize(p);
	vec3 q = n + vec3(seed);
	float lat = n.y;
	vec3 c = col_a;
	float rough = 0.85;
	if (kind < 0.5) { // rocky, cratered
		float h = fbm(q * 3.0);
		float craters = smoothstep(0.62, 0.7, fbm(q * 7.0 + 4.0)) - smoothstep(0.7, 0.76, fbm(q * 7.0 + 4.0)) * 0.6;
		c = mix(col_b, col_a, h);
		c = mix(c, col_c, smoothstep(0.6, 0.75, fbm(q * 2.0 + 11.0)) * 0.6);
		c *= 1.0 - craters * 0.35;
	} else if (kind < 1.5) { // earth
		float h = fbm(q * 2.2);
		float land = smoothstep(0.5, 0.53, h);
		vec3 ocean = mix(col_a * 0.7, col_a * 1.5, smoothstep(0.35, 0.5, h));
		vec3 ground = mix(col_b, col_c, smoothstep(0.45, 0.7, fbm(q * 6.0 + 3.0)));
		ground = mix(ground, col_c * 1.2, smoothstep(0.6, 0.66, h) * 0.5); // mountains
		c = mix(ocean, ground, land);
		rough = mix(0.25, 0.9, land);
		float ice = smoothstep(0.8, 0.86, abs(lat) + (fbm(q * 4.0) - 0.5) * 0.2);
		c = mix(c, vec3(0.95), ice);
		float clouds = smoothstep(0.55, 0.72, fbm(q * 3.0 + vec3(TIME * 0.01, 7.0, 0.0)));
		c = mix(c, vec3(1.0), clouds * 0.85);
	} else if (kind < 2.5) { // gas giant bands
		float warp = (fbm(q * 3.0) - 0.5) * 0.35;
		float band = sin((lat + warp) * 22.0 + seed * 3.0);
		float band2 = sin((lat + warp * 0.5) * 9.0);
		c = mix(col_a, col_b, smoothstep(-0.3, 0.6, band) * 0.75);
		c = mix(c, col_a * 1.1, smoothstep(0.4, 1.0, band2) * 0.3);
		float d = distance(n, normalize(vec3(0.75, -0.35, 0.55)));
		float s = smoothstep(0.24, 0.12, d + (fbm(n * 12.0) - 0.5) * 0.08) * spot;
		c = mix(c, col_c, s);
	} else if (kind < 3.5) { // ice giant: soft, nearly even bands
		float band = sin((lat + (fbm(q * 2.0) - 0.5) * 0.15) * 10.0);
		c = mix(col_a, col_b, band * 0.25 + 0.25);
		c = mix(c, col_c, smoothstep(0.75, 0.95, abs(lat)) * 0.4);
		rough = 0.6;
	} else if (kind < 4.5) { // mars
		float h = fbm(q * 3.0);
		c = mix(col_a, col_b, smoothstep(0.45, 0.7, h));
		c = mix(c, col_c, smoothstep(0.55, 0.75, fbm(q * 6.0 + 2.0)) * 0.35);
		float ice = smoothstep(0.86, 0.9, abs(lat) + (fbm(q * 5.0) - 0.5) * 0.1);
		c = mix(c, vec3(0.97, 0.95, 0.92), ice);
	} else { // thick swirling clouds
		vec3 w = q * 2.0 + vec3(fbm(q * 2.5), fbm(q * 2.5 + 5.0), 0.0) * 1.5;
		float h = fbm(w + vec3(TIME * 0.008, 0.0, 0.0));
		c = mix(col_b, col_a, h);
		c = mix(c, col_c, smoothstep(0.6, 0.8, h) * 0.6);
		rough = 0.7;
	}
	ALBEDO = c;
	ROUGHNESS = rough;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	// glow a little: readable in passthrough and in the dark casino; the atmosphere shines at the rim
	EMISSION = c * 0.35 + atmo * rim * 1.2;
}
"""

static var _shader: Shader

var _planets := {}   # hand name -> {"node", "body", "label", "level", "grow", "slot"}
var _time := 0.0


## [{"name": "Flush", "level": 3}, ...] from the game state (hands above level 1).
func set_levels(levels: Array) -> void:
	var alive := {}
	for h in levels:
		var name := str(h.get("name", ""))
		var level := int(h.get("level", 1))
		alive[name] = true
		var p: Dictionary = _planets.get(name, {})
		if p.is_empty():
			p = _make_planet(name)
			_planets[name] = p
		if int(p["level"]) != level:
			p["level"] = level
			p["grow"] = 0.0 # pop when it levels up
			(p["label"] as Label3D).text = "%s  Lv.%d" % [name, level]
	for name in _planets.keys():
		if not alive.has(name):
			(_planets[name]["node"] as Node3D).queue_free()
			_planets.erase(name)
	# spread evenly around the orbit, in the order of the game's hand list (a new planet makes room:
	# the others glide apart, see _process)
	var names: Array = _planets.keys()
	names.sort_custom(func(a, b): return PLANETS.keys().find(a) < PLANETS.keys().find(b))
	for i in names.size():
		_planets[names[i]]["slot"] = TAU * i / names.size()


## Diameter in metres: clearly bigger with every level.
static func planet_size(level: int) -> float:
	return 0.12 + 0.07 * clampi(level - 1, 0, 14)


func _make_planet(hand: String) -> Dictionary:
	var info: Array = PLANETS.get(hand, [hand, 0, [Color(0.8, 0.8, 0.85), Color(0.5, 0.5, 0.55), Color(1, 1, 1)], false, Color(0, 0, 0)])
	var colours: Array = info[2]
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SURFACE
	var node := Node3D.new()
	add_child(node)
	var body := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 48
	sphere.rings = 24
	body.mesh = sphere
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mat.set_shader_parameter("kind", float(info[1]))
	mat.set_shader_parameter("col_a", colours[0])
	mat.set_shader_parameter("col_b", colours[1])
	mat.set_shader_parameter("col_c", colours[2])
	mat.set_shader_parameter("atmo", info[4])
	mat.set_shader_parameter("seed", float(hand.hash() % 97) * 0.37)
	mat.set_shader_parameter("spot", 1.0 if info[0] == "Jupiter" else 0.0)
	body.material_override = mat
	body.rotation_degrees.z = 12.0 + float(hand.hash() % 15) # a little axial tilt
	node.add_child(body)
	if info[3]: # Saturn's ring
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.7
		torus.outer_radius = 1.1
		torus.rings = 48
		torus.ring_segments = 4
		ring.mesh = torus
		ring.scale = Vector3(1, 0.04, 1)
		var rm := StandardMaterial3D.new()
		rm.albedo_color = Color(0.95, 0.88, 0.7, 0.85)
		rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		rm.emission_enabled = true
		rm.emission = Color(0.95, 0.88, 0.7)
		rm.emission_energy_multiplier = 0.3
		ring.material_override = rm
		body.add_child(ring)
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 40
	label.pixel_size = 0.0016
	label.outline_size = 8
	label.modulate = Color(1, 1, 1, 0.85)
	node.add_child(label)
	return {"node": node, "body": body, "label": label, "level": 0, "grow": 1.0, "slot": 0.0}


func _process(delta: float) -> void:
	_time += delta
	for p in _planets.values():
		var size := planet_size(int(p["level"]))
		p["grow"] = minf(float(p["grow"]) + delta * 1.5, 1.0)
		var g: float = p["grow"]
		var pop := 1.0 + 0.5 * sin(g * PI) * (1.0 - g) * 2.0 # swells up for a moment when it levels up
		var body: MeshInstance3D = p["body"]
		body.scale = Vector3.ONE * size * pop
		body.rotate_object_local(Vector3.UP, delta * 0.15)
		var slot: float = p["slot"]
		# glide to a new spot when planets join (a new one starts right at its spot)
		p["at"] = lerp_angle(float(p.get("at", slot)), slot, 1.0 - exp(-0.8 * delta))
		var a: float = p["at"] + _time * SPEED # all planets circle the room together, keeping their distance
		var node: Node3D = p["node"]
		node.position = Vector3(cos(a) * ORBIT_RADIUS, ORBIT_HEIGHT + 0.1 * sin(_time * 0.3 + slot * 3.0), sin(a) * ORBIT_RADIUS)
		(p["label"] as Label3D).position = Vector3(0, -size * 0.5 - 0.1, 0)
