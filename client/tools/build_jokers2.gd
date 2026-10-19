extends "res://tools/build_jokers.gd"
## The second set of augmented jokers (jokers/j_<key>.tscn), built with the same toolkit as
## build_jokers.gd (lathe, extrusion, swept tubes, the Jimbo figure). The values come live from the
## game through AugmentedJoker (fill, count, glow, text, spin):
##   Ceremonial Dagger, Constellation, Madness, Erosion, Fortune Teller, Glass Joker, Rocket, Egg,
##   8 Ball, Credit Card, Blueprint, DNA, Space Joker, Mr. Bones, Supernova, Cloud 9,
##   and the legendaries Canio, Triboulet, Yorick, Chicot, Perkeo.
##
##   Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tools/build_jokers2.gd
##   ... --script res://tools/build_jokers2.gd -- rocket egg     (only these)


func _initialize() -> void:
	var builders := {
		"ceremonial": _ceremonial, "constellation": _constellation, "madness": _madness, "erosion": _erosion,
		"fortune_teller": _fortune_teller, "glass": _glass, "rocket": _rocket, "egg": _egg,
		"8_ball": _eight_ball, "credit_card": _credit_card, "blueprint": _blueprint, "dna": _dna,
		"space": _space, "mr_bones": _mr_bones, "supernova": _supernova, "cloud_9": _cloud_9,
		"caino": _canio, "triboulet": _triboulet, "yorick": _yorick, "chicot": _chicot, "perkeo": _perkeo,
		"vampire": _vampire, "swashbuckler": _swashbuckler, "blue_joker": _blue_joker, "steel_joker": _steel_joker,
		"brainstorm": _brainstorm, "seance": _seance, "ticket": _ticket, "smeared": _smeared,
		"walkie_talkie": _walkie_talkie,
	}
	var only := OS.get_cmdline_user_args()
	for key in builders:
		if not only.is_empty() and not only.has(key):
			continue
		_rng.seed = hash(key)
		var root: Node3D = builders[key].call()
		_save(root, key)
	quit()


## A round wooden foot most of the models stand on.
func _foot(parent: Node, r: float, colour := Color(0.28, 0.14, 0.07)) -> void:
	var wood := _mat(colour, 0.45)
	_mi(parent, _cyl(r, r + 0.002, 0.006, 24), wood, Vector3(0, 0.003, 0))
	_mi(parent, _torus(r - 0.0015, r + 0.0005, 24, 6), _gold(), Vector3(0, 0.006, 0))


## Bone white skull: cranium, cheek bones, jaw, dark eye sockets (in `eyes`) and a nose hole.
func _skull(parent: Node, name: String, s: float, eye_mat: Material) -> Node3D:
	var k := _node(parent, name)
	var bone := _mat(Color(0.93, 0.9, 0.8), 0.6)
	var dark := _mat(Color(0.06, 0.05, 0.05), 0.9)
	_mi(k, _sph(0.02 * s, -1, 20), bone, Vector3(0, 0.022 * s, 0), Vector3.ZERO, Vector3(1, 0.95, 1.08))
	# cheeks / upper jaw and the jaw: rounded, narrower than the cranium, towards the front
	_mi(k, _sph(0.0105 * s, -1, 14), bone, Vector3(0, 0.009 * s, 0.008 * s), Vector3.ZERO, Vector3(1.0, 0.75, 0.9))
	_mi(k, _sph(0.0085 * s, -1, 12), bone, Vector3(0, 0.002 * s, 0.009 * s), Vector3(8, 0, 0), Vector3(1.0, 0.55, 0.85), "Jaw")
	var eyes := _node(k, "Eyes")
	for side in [-1.0, 1.0]:
		_mi(eyes, _sph(0.0055 * s), eye_mat, Vector3(side * 0.0075, 0.019, 0.0165) * s, Vector3.ZERO, Vector3(1, 1.1, 0.5))
	_mi(k, _sph(0.0028 * s), dark, Vector3(0, 0.011, 0.019) * s, Vector3.ZERO, Vector3(0.8, 1.2, 0.5)) # nose
	_mi(k, _box(Vector3(0.014, 0.0012, 0.002) * s), dark, Vector3(0, 0.0055 * s, 0.0165 * s)) # the gap between the teeth
	for i in 6: # teeth
		_mi(k, _box(Vector3(0.0019, 0.0028, 0.0015) * s), bone, Vector3((-0.006 + i * 0.0024) * s, 0.0055 * s, 0.0172 * s))
	return k


# ================================================================ Ceremonial Dagger
## A fantasy dagger stuck point-down in a velvet cushion: a brass hilt with a skull at the guard,
## fangs curling down from it and spiked quillons, a wrapped grip and a skull pommel; the steel
## blade has two notches below the guard and a long open slot. The slot's rim and the fuller glow
## redder the more Mult it has taken.
func _ceremonial() -> Node3D:
	var j := _begin("ceremonial", {"glow_node": NodePath("Dagger/Glow"), "glow_source": "clamp(ab[\"mult\"] / 30.0, 0.05, 1.0)",
			"glow_energy": 3.0, "label_node": NodePath("Value"), "label_source": "ab[\"mult\"]", "label_format": "+%d Mult"})
	_foot(j, 0.03)
	var velvet := _mat(Color(0.45, 0.05, 0.1), 0.95)
	_mi(j, _sph(0.026, 0.02, 20), velvet, Vector3(0, 0.012, 0), Vector3.ZERO, Vector3(1, 0.55, 1))
	for i in 4: # tassels at the cushion's corners
		var a := TAU * i / 4.0 + PI / 4.0
		_mi(j, _sph(0.0035), _gold(), Vector3(cos(a) * 0.022, 0.012, sin(a) * 0.022))
	var d := _node(j, "Dagger", Vector3(0, 0.008, 0))
	d.rotation_degrees.z = 4.0
	var steel := _mat(Color(0.86, 0.86, 0.84), 0.3, 0.55) # (less metallic: in the dark casino a mirror blade looks black)
	var brass := _mat(Color(0.72, 0.62, 0.42), 0.35, 0.75)
	# the blade, tip at y = 0: the lower part with its long slot (a deep notch from above, closed by
	# the upper part), little barbs near the tip
	var blade := _node(d, "Blade")
	blade.scale = Vector3(1.35, 1, 1)
	var lower := PackedVector2Array([Vector2(0, 0), Vector2(0.0038, 0.007), Vector2(0.003, 0.0095), Vector2(0.0048, 0.012),
			Vector2(0.0048, 0.037), Vector2(0.0015, 0.037), Vector2(0, 0.016), Vector2(-0.0015, 0.037), Vector2(-0.0048, 0.037),
			Vector2(-0.0048, 0.012), Vector2(-0.003, 0.0095), Vector2(-0.0038, 0.007)])
	_mi(blade, _extrude(lower, 0.002), steel)
	var upper := PackedVector2Array([Vector2(-0.0048, 0.0365), Vector2(0.0048, 0.0365), Vector2(0.0048, 0.04),
			Vector2(0.003, 0.042), Vector2(0.0048, 0.044), Vector2(0.0052, 0.054), Vector2(-0.0052, 0.054), Vector2(-0.0048, 0.044),
			Vector2(-0.003, 0.042), Vector2(-0.0048, 0.04)])
	_mi(blade, _extrude(upper, 0.002), steel)
	# what glows: a fuller line down the upper blade and the rim of the slot
	var glow := _node(d, "Glow")
	glow.scale = Vector3(1.35, 1, 1)
	var red := _mat(Color(0.85, 0.1, 0.08), 0.3, 0.3)
	for side in [-1.0, 1.0]:
		_mi(glow, _box(Vector3(0.0008, 0.012, 0.0024)), red, Vector3(0, 0.0475, 0))
		_rod(glow, Vector3(side * 0.0015, 0.0368, 0), Vector3(0, 0.0165, 0), 0.00045, red, 4)
	# the guard: a bar with spiked ends, a skull in the middle, fangs curling down from it
	var guard_y := 0.056
	_mi(d, _box(Vector3(0.026, 0.0034, 0.0042)), brass, Vector3(0, guard_y, 0))
	for side in [-1.0, 1.0]:
		_mi(d, _sph(0.0026, -1, 8), brass, Vector3(side * 0.012, guard_y, 0))
		var spike := _mi(d, _cyl(0.0001, 0.0019, 0.008, 8), brass)
		spike.transform = Transform3D(_align_y(Vector3(side, 0.6, 0)), Vector3(side * 0.0155, guard_y + 0.0022, 0))
		for k in 3: # the fangs, curving outwards and down under the skull
			var path: Array = []
			var radii: Array = []
			for n in 6:
				var t := n / 5.0
				var spread := 0.003 + k * 0.0022
				path.append(Vector3(side * (spread + 0.004 * t), guard_y - 0.002 - 0.007 * t + 0.003 * t * t * k * 0.3, 0.0005))
				radii.append(lerpf(0.0012, 0.0002, t))
			_mi(d, _sweep(path, radii, 6), brass)
	var guard_skull := _skull(d, "GuardSkull", 0.32, _mat(Color(0.05, 0.03, 0.02), 0.8))
	guard_skull.position = Vector3(0, guard_y - 0.004, 0.0025)
	for n in guard_skull.get_children():
		if n is MeshInstance3D and (n as MeshInstance3D).name != "Eyes":
			(n as MeshInstance3D).material_override = brass
	# the grip: wrapped with rings, a little skull on it, and a skull pommel
	var grip := _mi(d, _cyl(0.0032, 0.0036, 0.022, 12), brass, Vector3(0, guard_y + 0.0135, 0))
	for i in 7:
		_mi(grip, _torus(0.0031, 0.0039, 14, 4), _mat(Color(0.6, 0.5, 0.32), 0.4, 0.7), Vector3(0, -0.009 + i * 0.003, 0))
	var pommel := _skull(d, "Pommel", 0.38, _mat(Color(0.05, 0.03, 0.02), 0.8))
	pommel.position = Vector3(0, guard_y + 0.0245, 0.0)
	for n in pommel.get_children():
		if n is MeshInstance3D:
			(n as MeshInstance3D).material_override = brass
	_mi(d, _cyl(0.002, 0.0028, 0.004, 10), brass, Vector3(0, guard_y + 0.035, 0)) # the cap on top
	_value_label(j, "Value", 0.14)
	return j


# ================================================================ Constellation
## A dark star map in a gold ring: with every Planet card used, one more star lights up.
func _constellation() -> Node3D:
	var j := _begin("constellation", {"count_parent": NodePath("Map/Stars"), "count_source": "round((ab[\"x_mult\"] - 1.0) / 0.1)",
			"label_node": NodePath("Value"), "label_source": "ab[\"x_mult\"]", "label_format": "x%.1f"})
	_foot(j, 0.024)
	_rod(j, Vector3(0, 0.005, 0), Vector3(0, 0.03, 0), 0.0025, _gold())
	var map := _node(j, "Map", Vector3(0, 0.068, 0))
	map.rotation_degrees.x = -12.0
	_mi(map, _cyl(0.038, 0.038, 0.004, 40), _mat(Color(0.03, 0.04, 0.12), 0.6), Vector3.ZERO, Vector3(90, 0, 0))
	_mi(map, _torus(0.037, 0.041, 40, 8), _gold(), Vector3.ZERO, Vector3(90, 0, 0))
	var points: Array = []
	for i in 20:
		var a := _rng.randf() * TAU
		var r := sqrt(_rng.randf()) * 0.031
		points.append(Vector3(cos(a) * r, sin(a) * r, 0.0025))
	var dim := _mat(Color(0.35, 0.38, 0.5), 0.6)
	for p in points: # every star, faint
		_mi(map, _sph(0.0013), dim, p)
	var line := _glowing(Color(0.4, 0.55, 1.0), 0.6)
	for i in 6: # a few lines of the constellation
		_rod(map, points[i], points[i + 1], 0.0004, line, 4)
	var stars := _node(map, "Stars")
	var bright := _glowing(Color(1.0, 0.95, 0.7), 3.0)
	for p in points: # lit one by one (count)
		var star := _node(stars, "Star")
		star.position = p + Vector3(0, 0, 0.0008)
		_mi(star, _sph(0.0022), bright)
		for k in 2: # a little twinkle cross
			_mi(star, _box(Vector3(0.008 if k == 0 else 0.0008, 0.0008 if k == 0 else 0.008, 0.0005)), bright)
	_value_label(j, "Value", 0.13)
	return j


# ================================================================ Madness
## A laughing mask on a stick: it cracks more and its eyes burn brighter with every joker eaten.
func _madness() -> Node3D:
	var j := _begin("madness", {"count_parent": NodePath("Mask/Cracks"), "count_source": "round((ab[\"x_mult\"] - 1.0) / 0.5)",
			"glow_node": NodePath("Mask/Eyes"), "glow_source": "clamp((ab[\"x_mult\"] - 1.0) / 4.0, 0.15, 1.0)", "glow_energy": 4.0,
			"label_node": NodePath("Value"), "label_source": "ab[\"x_mult\"]", "label_format": "x%.1f"})
	_foot(j, 0.022, Color(0.12, 0.06, 0.1))
	_rod(j, Vector3(0, 0.005, 0), Vector3(0.004, 0.05, 0), 0.0022, _mat(Color(0.2, 0.1, 0.25), 0.5))
	var mask := _node(j, "Mask", Vector3(0.004, 0.075, 0))
	mask.rotation_degrees.z = -8.0
	var face := _mat(Color(0.9, 0.85, 0.95), 0.4)
	_mi(mask, _sph(0.03, -1, 24), face, Vector3.ZERO, Vector3.ZERO, Vector3(0.9, 1.05, 0.38))
	var purple := _mat(Color(0.45, 0.1, 0.6), 0.5)
	for side in [-1.0, 1.0]: # painted brows and a diamond under each eye, like a harlequin
		_mi(mask, _box(Vector3(0.013, 0.0025, 0.002)), purple, Vector3(side * 0.01, 0.017, 0.0105), Vector3(0, 0, side * -20.0))
		_mi(mask, _box(Vector3(0.004, 0.004, 0.002)), purple, Vector3(side * 0.01, -0.002, 0.0108), Vector3(0, 0, 45))
	var eyes := _node(mask, "Eyes")
	var burn := _mat(Color(0.75, 0.2, 1.0), 0.4)
	for side in [-1.0, 1.0]:
		_mi(eyes, _sph(0.0045), burn, Vector3(side * 0.01, 0.008, 0.0095), Vector3(0, 0, side * 15.0), Vector3(1.3, 0.8, 0.4))
	# the wide grin (a curved dark tube) with teeth
	var path: Array = []
	var radii: Array = []
	for i in 11:
		var t := i / 10.0
		path.append(Vector3(-0.016 + 0.032 * t, -0.012 - 0.007 * sin(t * PI), 0.0098 + 0.0018 * sin(t * PI)))
		radii.append(0.0028)
	_mi(mask, _sweep(path, radii, 8), _mat(Color(0.08, 0.02, 0.08), 0.8))
	# the cracks: dark-purple glowing lines spreading over the face
	var cracks := _node(mask, "Cracks")
	var crack_mat := _glowing(Color(0.6, 0.1, 0.8), 1.5)
	for i in 10:
		var c := _node(cracks, "Crack")
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(0.005, 0.022)
		c.position = Vector3(cos(a) * r * 0.9, sin(a) * r, 0.0108)
		c.rotation_degrees.z = _rng.randf_range(0, 180)
		_mi(c, _box(Vector3(_rng.randf_range(0.008, 0.016), 0.0007, 0.0012)), crack_mat)
		_mi(c, _box(Vector3(0.006, 0.0006, 0.0012)), crack_mat, Vector3(0.004, 0.002, 0), Vector3(0, 0, 35))
	# jester bells at the mask's sides
	for side in [-1.0, 1.0]:
		_mi(mask, _sph(0.004), _gold(), Vector3(side * 0.028, 0.012, 0))
	_value_label(j, "Value", 0.13)
	return j


# ================================================================ Erosion
## A sandstone pillar on its plinth that crumbles away as your deck shrinks; grains at its foot.
func _erosion() -> Node3D:
	var j := _begin("erosion", {"fill_node": NodePath("Fill"), "fill_source": "60.0 - joker[\"value\"].to_int()", "fill_max": 60.0,
			"fill_min": 0.12, "label_node": NodePath("Value"), "label_source": "joker[\"value\"]"})
	var sand := _mat(Color(0.86, 0.7, 0.45), 0.95)
	var dark_sand := _mat(Color(0.7, 0.54, 0.32), 0.95)
	_mi(j, _box(Vector3(0.05, 0.008, 0.05)), dark_sand, Vector3(0, 0.004, 0))
	_mi(j, _box(Vector3(0.04, 0.006, 0.04)), sand, Vector3(0, 0.011, 0))
	var fill := _node(j, "Fill", Vector3(0, 0.014, 0))
	var profile := PackedVector2Array() # wind-worn: wavy, with a narrow waist
	for i in 13:
		var y := i / 12.0 * 0.09
		profile.append(Vector2(0.012 + 0.0025 * sin(i * 1.7) - 0.003 * sin(y / 0.09 * PI), y))
	profile.insert(0, Vector2(0, 0))
	profile.append(Vector2(0, 0.09))
	_mi(fill, _lathe(profile, 14), sand)
	for i in 5: # sandstone bands
		_mi(fill, _torus(0.0105, 0.0128, 14, 4), dark_sand, Vector3(0, 0.012 + i * 0.016, 0), Vector3(0, i * 20.0, 0),
				Vector3(1, 0.4, 1))
	_mi(fill, _box(Vector3(0.03, 0.006, 0.03)), dark_sand, Vector3(0, 0.093, 0), Vector3(0, 10, 0)) # capital
	# crumbled sand and pebbles round the plinth
	for i in 14:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(0.018, 0.026)
		_mi(j, _sph(_rng.randf_range(0.0015, 0.0035), -1, 6), sand if i % 2 == 0 else dark_sand,
				Vector3(cos(a) * r, 0.015, sin(a) * r), Vector3.ZERO, Vector3(1, 0.6, 1))
	_value_label(j, "Value", 0.13)
	return j


# ================================================================ Fortune Teller
## A crystal ball on a golden stand and a velvet cushion, tarot cards fanned before it: the mist
## inside glows brighter with every Tarot card used.
func _fortune_teller() -> Node3D:
	var j := _begin("fortune_teller", {"glow_node": NodePath("Core"), "glow_source": "clamp(joker[\"value\"].to_int() / 25.0, 0.1, 1.0)",
			"glow_energy": 3.5, "label_node": NodePath("Value"), "label_source": "joker[\"value\"]"})
	var velvet := _mat(Color(0.35, 0.08, 0.45), 0.95)
	_mi(j, _cyl(0.03, 0.032, 0.008, 24), velvet, Vector3(0, 0.004, 0))
	_mi(j, _torus(0.024, 0.032, 24, 8), velvet, Vector3(0, 0.009, 0), Vector3.ZERO, Vector3(1, 0.6, 1))
	var stand := PackedVector2Array([Vector2(0.016, 0), Vector2(0.012, 0.004), Vector2(0.007, 0.01), Vector2(0.009, 0.016),
			Vector2(0.014, 0.02), Vector2(0, 0.02)])
	_mi(j, _lathe(stand, 20), _gold(), Vector3(0, 0.01, 0))
	for i in 3: # the gold claws holding the ball
		var a := TAU * i / 3.0
		_rod(j, Vector3(cos(a) * 0.012, 0.028, sin(a) * 0.012), Vector3(cos(a) * 0.017, 0.04, sin(a) * 0.017), 0.0015, _gold(), 6)
	var core := _mi(j, _sph(0.014, -1, 16), _mat(Color(0.7, 0.35, 1.0), 0.5), Vector3(0, 0.05, 0), Vector3.ZERO, Vector3.ONE, "Core")
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var glass := _see_through(Color(0.75, 0.85, 1.0), 0.28, 0.05)
	glass.metallic_specular = 1.0
	_mi(j, _sph(0.021, -1, 28), glass, Vector3(0, 0.05, 0))
	var card_back := _mat(Color(0.3, 0.12, 0.55), 0.7)
	for i in 3: # three tarot cards fanned in front
		var c := _mi(j, _box(Vector3(0.012, 0.0008, 0.019)), card_back, Vector3((i - 1) * 0.01, 0.0135, 0.022),
				Vector3(0, (i - 1) * -20.0, 0))
		_mi(c, _box(Vector3(0.006, 0.0002, 0.009)), _gold(), Vector3(0, 0.0005, 0))
	_value_label(j, "Value", 0.12)
	return j


# ================================================================ Glass Joker
## Jimbo made of glass: with every Glass card destroyed, another crack shines in him.
func _glass() -> Node3D:
	var j := _begin("glass", {"count_parent": NodePath("Cracks"), "count_source": "round((ab[\"x_mult\"] - 1.0) / 0.75)",
			"label_node": NodePath("Value"), "label_source": "ab[\"x_mult\"]", "label_format": "x%.2f"})
	_foot(j, 0.026, Color(0.2, 0.25, 0.3))
	var glass := _see_through(Color(0.7, 0.92, 1.0), 0.38, 0.05)
	glass.metallic_specular = 1.0
	glass.emission_enabled = true
	glass.emission = Color(0.4, 0.7, 0.9)
	glass.emission_energy_multiplier = 0.25
	var fig := _jester(j, "Figure", 1.0, Color.WHITE, Color.WHITE, glass)
	fig.position.y = 0.006
	var cracks := _node(j, "Cracks")
	var shine := _glowing(Color(0.9, 0.97, 1.0), 2.5)
	for i in 12:
		var c := _node(cracks, "Crack")
		var y := _rng.randf_range(0.02, 0.1)
		var a := _rng.randf_range(-1.2, 1.2)
		var r := 0.016 if y < 0.075 else 0.014
		c.position = Vector3(sin(a) * r, y, cos(a) * r)
		c.rotation_degrees = Vector3(0, rad_to_deg(a), _rng.randf_range(0, 180))
		_mi(c, _box(Vector3(_rng.randf_range(0.007, 0.013), 0.0007, 0.0007)), shine)
		_mi(c, _box(Vector3(0.005, 0.0006, 0.0006)), shine, Vector3(0.003, 0.0015, 0), Vector3(0, 0, 40))
	_value_label(j, "Value", 0.14)
	return j


# ================================================================ Rocket
## A retro rocket on its launch pad: the exhaust flame grows with the payout.
func _rocket() -> Node3D:
	var j := _begin("rocket", {"fill_node": NodePath("Rocket/Flame"), "fill_source": "extra[\"dollars\"]", "fill_max": 12.0,
			"fill_min": 0.25, "label_node": NodePath("Value"), "label_source": "extra[\"dollars\"]", "label_format": "$%d"})
	var steel := _mat(Color(0.45, 0.47, 0.52), 0.5, 0.6)
	_mi(j, _cyl(0.03, 0.032, 0.006, 24), steel, Vector3(0, 0.003, 0))
	_mi(j, _cyl(0.024, 0.024, 0.0015, 24), _mat(Color(0.95, 0.75, 0.1), 0.6), Vector3(0, 0.0065, 0)) # hazard ring
	for i in 3: # launch towers
		var a := TAU * i / 3.0 + 0.5
		_rod(j, Vector3(cos(a) * 0.024, 0.006, sin(a) * 0.024), Vector3(cos(a) * 0.016, 0.03, sin(a) * 0.016), 0.0012, steel, 6)
	var r := _node(j, "Rocket", Vector3(0, 0.03, 0))
	var white := _mat(Color(0.95, 0.95, 0.97), 0.35, 0.2)
	var red := _mat(Color(0.88, 0.12, 0.12), 0.35, 0.2)
	var body := PackedVector2Array([Vector2(0, 0), Vector2(0.009, 0.0), Vector2(0.0115, 0.012), Vector2(0.012, 0.034),
			Vector2(0.0105, 0.046), Vector2(0, 0.046)])
	_mi(r, _lathe(body, 20), white)
	var nose := PackedVector2Array([Vector2(0.0106, 0), Vector2(0.008, 0.012), Vector2(0.004, 0.02), Vector2(0, 0.024)])
	_mi(r, _lathe(nose, 20), red, Vector3(0, 0.046, 0))
	_mi(r, _torus(0.0108, 0.0122, 20, 4), red, Vector3(0, 0.012, 0))
	var fin := PackedVector2Array([Vector2(0, 0), Vector2(0.012, -0.008), Vector2(0.012, 0.0), Vector2(0, 0.02)])
	for i in 3:
		var holder := _node(r, "Fin")
		holder.rotation.y = TAU * i / 3.0
		_mi(holder, _extrude(fin, 0.0016), red, Vector3(0.009, 0.002, 0))
	# porthole
	_mi(r, _torus(0.0035, 0.0048, 16, 6), _gold(), Vector3(0, 0.03, 0.0115), Vector3(90, 0, 0))
	_mi(r, _cyl(0.0036, 0.0036, 0.001, 16), _glowing(Color(0.4, 0.8, 1.0), 0.8), Vector3(0, 0.03, 0.0116), Vector3(90, 0, 0))
	_mi(r, _cyl(0.007, 0.0095, 0.006, 16), steel, Vector3(0, -0.002, 0)) # nozzle
	# the flame: points down from the nozzle, so its length is the fill
	var flame := _node(r, "Flame", Vector3(0, -0.005, 0))
	var hot := _glowing(Color(1.0, 0.55, 0.1), 3.0)
	hot.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hot.albedo_color.a = 0.85
	_mi(flame, _cyl(0.007, 0.001, 0.025, 12), hot, Vector3(0, -0.0125, 0))
	_mi(flame, _cyl(0.004, 0.0005, 0.018, 10), _glowing(Color(1.0, 0.95, 0.6), 4.0), Vector3(0, -0.009, 0))
	_value_label(j, "Value", 0.14)
	return j


# ================================================================ Egg
## An egg in a twig nest: it grows and turns golden as its sell value rises.
func _egg() -> Node3D:
	var j := _begin("egg", {"fill_node": NodePath("Fill"), "fill_source": "joker[\"sell\"]", "fill_max": 15.0, "fill_min": 0.7,
			"fill_uniform": true, "glow_node": NodePath("Fill"), "glow_source": "clamp((joker[\"sell\"] - 3.0) / 12.0, 0.0, 1.0)",
			"glow_energy": 1.2, "label_node": NodePath("Value"), "label_source": "joker[\"sell\"]", "label_format": "$%d"})
	var twig := _mat(Color(0.42, 0.28, 0.14), 0.95)
	var twig2 := _mat(Color(0.55, 0.38, 0.2), 0.95)
	for i in 16: # the nest: twigs wound round
		var path: Array = []
		var radii: Array = []
		var a0 := _rng.randf() * TAU
		var y := _rng.randf_range(0.004, 0.014)
		var rr := _rng.randf_range(0.02, 0.028)
		for k in 7:
			var a := a0 + k * 0.32
			path.append(Vector3(cos(a) * rr, y + sin(k * 0.9) * 0.002, sin(a) * rr))
			radii.append(0.0016)
		_mi(j, _sweep(path, radii, 5), twig if i % 2 == 0 else twig2)
	_mi(j, _cyl(0.02, 0.012, 0.006, 16), twig, Vector3(0, 0.004, 0))
	var fill := _node(j, "Fill", Vector3(0, 0.008, 0))
	var profile := PackedVector2Array()
	for i in 21: # an ellipse, a little wider below the middle and rounder at the bottom: an egg
		var th := PI * i / 20.0
		var y := (1.0 - cos(th)) * 0.5 * 0.048
		var r := sin(th) * 0.0165 * (1.0 + 0.13 * cos(th))
		profile.append(Vector2(maxf(r, 0.0), y))
	_mi(fill, _lathe(profile, 24), _mat(Color(0.98, 0.85, 0.45), 0.35, 0.3))
	for i in 5: # speckles
		var a := _rng.randf() * TAU
		var y := _rng.randf_range(0.012, 0.035)
		_mi(fill, _sph(0.0016, -1, 6), _mat(Color(0.75, 0.55, 0.25), 0.6), Vector3(cos(a) * 0.016, y, sin(a) * 0.016))
	_value_label(j, "Value", 0.11)
	return j


# ================================================================ 8 Ball
## A glossy black billiard ball turning slowly on a brass ring.
func _eight_ball() -> Node3D:
	var j := _begin("8_ball", {"spin_node": NodePath("Ball"), "spin_speed": 0.6})
	_mi(j, _torus(0.012, 0.016, 24, 8), _gold(), Vector3(0, 0.004, 0))
	_mi(j, _cyl(0.016, 0.018, 0.003, 24), _mat(Color(0.12, 0.3, 0.16), 0.95), Vector3(0, 0.0015, 0)) # billiard felt
	var ball := _node(j, "Ball", Vector3(0, 0.032, 0))
	var black := _mat(Color(0.03, 0.03, 0.04), 0.12, 0.1)
	black.metallic_specular = 0.9
	_mi(ball, _sph(0.028, -1, 32), black)
	var white := _mat(Color(0.97, 0.97, 0.95), 0.25)
	# the white circle: a flat cap sitting on the surface, the 8 printed on it
	_mi(ball, _sph(0.011, -1, 24), white, Vector3(0, 0.004, 0.0238), Vector3(-8, 0, 0), Vector3(1, 1, 0.3))
	_print(ball, "8", Vector3(0, 0.0045, 0.0275), Vector3(-8, 0, 0), 0.0006, Color(0.05, 0.05, 0.05))
	return j


# ================================================================ Credit Card
## A credit card in a little stand: embossed numbers, a gold chip, the holder JIMBO.
func _credit_card() -> Node3D:
	var j := _begin("credit_card", {})
	var stand := _mat(Color(0.12, 0.12, 0.14), 0.3, 0.6)
	_mi(j, _box(Vector3(0.05, 0.006, 0.022)), stand, Vector3(0, 0.003, 0))
	_mi(j, _box(Vector3(0.05, 0.008, 0.003)), stand, Vector3(0, 0.009, -0.006))
	var card := _node(j, "Card", Vector3(0, 0.035, 0))
	card.rotation_degrees.x = -12.0
	var blue := _mat(Color(0.12, 0.25, 0.65), 0.3, 0.5)
	_mi(card, _extrude(_rounded_rect(0.07, 0.045, 0.004), 0.0015), blue)
	var shine := _mat(Color(0.25, 0.45, 0.9), 0.3, 0.6) # a lighter swoosh across it
	_mi(card, _box(Vector3(0.07, 0.008, 0.0004)), shine, Vector3(0, 0.006, 0.0009), Vector3(0, 0, 14))
	_mi(card, _extrude(_rounded_rect(0.011, 0.008, 0.0015), 0.0006), _gold(), Vector3(-0.022, 0.006, 0.001)) # chip
	for i in 3:
		_mi(card, _box(Vector3(0.011, 0.0004, 0.0004)), _mat(Color(0.6, 0.45, 0.15), 0.5, 0.6), Vector3(-0.022, 0.003 + i * 0.003, 0.0014))
	var emboss := Color(0.92, 0.92, 0.96)
	_print(card, "4000 1234 5678 9010", Vector3(0, -0.006, 0.0009), Vector3.ZERO, 0.00009, emboss)
	_print(card, "JIMBO", Vector3(-0.018, -0.016, 0.0009), Vector3.ZERO, 0.00008, emboss)
	_print(card, "VALID THRU 08/ANTE", Vector3(0.016, -0.016, 0.0009), Vector3.ZERO, 0.00005, emboss)
	for k in 2: # the card company's two overlapping circles
		_mi(card, _cyl(0.0045, 0.0045, 0.0005, 20), _mat(Color(0.95, 0.2, 0.2) if k == 0 else Color(1.0, 0.65, 0.1), 0.4),
				Vector3(0.022 + k * 0.005, 0.012, 0.001), Vector3(90, 0, 0))
	_mi(card, _box(Vector3(0.07, 0.008, 0.0004)), _mat(Color(0.05, 0.05, 0.05), 0.4), Vector3(0, 0.012, -0.0009)) # magnetic stripe
	return j


# ================================================================ Blueprint
## A half unrolled blueprint of a joker, weighted down by a pencil and a ruler.
func _blueprint() -> Node3D:
	var j := _begin("blueprint", {})
	var paper := _mat(Color(0.12, 0.32, 0.72), 0.85)
	var ink := _mat(Color(0.88, 0.94, 1.0), 0.6)
	# the rolled part at the back and the sheet sloping towards you
	_mi(j, _cyl(0.008, 0.008, 0.066, 20), paper, Vector3(0, 0.03, -0.018), Vector3(0, 0, 90))
	_mi(j, _torus(0.0035, 0.008, 20, 6), _mat(Color(0.08, 0.2, 0.5), 0.8), Vector3(0.033, 0.03, -0.018), Vector3(0, 0, 90))
	var sheet := _node(j, "Sheet", Vector3(0, 0.02, 0.006))
	sheet.rotation_degrees.x = -55.0
	_mi(sheet, _box(Vector3(0.064, 0.05, 0.0008)), paper)
	_mi(sheet, _box(Vector3(0.056, 0.0006, 0.0003)), ink, Vector3(0, 0.02, 0.0006))
	for i in 7: # grid
		_mi(sheet, _box(Vector3(0.0003, 0.042, 0.0002)), _mat(Color(0.4, 0.6, 0.9), 0.7), Vector3(-0.027 + i * 0.009, -0.002, 0.0005))
	# printed on it: the emblem of Blue Prince (a holly-leaf crest with two wings and the dots)
	var crest := _node(sheet, "Crest", Vector3(0, 0.002, 0))
	var light := _mat(Color(0.55, 0.82, 1.0), 0.6)
	var line := _mat(Color(0.04, 0.1, 0.28), 0.7)
	var body := PackedVector2Array([Vector2(0, 0.016), Vector2(0.0045, 0.006), Vector2(0.012, 0.0), Vector2(0.018, -0.0045),
			Vector2(0.012, -0.004), Vector2(0.0145, -0.0085), Vector2(0.008, -0.006), Vector2(0.0062, -0.0115),
			Vector2(0.003, -0.0065), Vector2(0, -0.009), Vector2(-0.003, -0.0065), Vector2(-0.0062, -0.0115),
			Vector2(-0.008, -0.006), Vector2(-0.0145, -0.0085), Vector2(-0.012, -0.004), Vector2(-0.018, -0.0045),
			Vector2(-0.012, 0.0), Vector2(-0.0045, 0.006)])
	_mi(crest, _extrude(body, 0.0003), light, Vector3(0, 0, 0.0006))
	for side in [-1.0, 1.0]: # the wings, with their feathers drawn in
		var wing := PackedVector2Array([Vector2(side * 0.0035, 0.0035), Vector2(side * 0.009, 0.0095), Vector2(side * 0.0125, 0.0105),
				Vector2(side * 0.0135, 0.0085), Vector2(side * 0.0165, 0.0015), Vector2(side * 0.0095, 0.0005), Vector2(side * 0.0045, 0.0015)])
		_mi(crest, _extrude(wing, 0.0003), light, Vector3(0, 0, 0.0009))
		for k in 4:
			var x0: float = side * (0.006 + k * 0.0022)
			_rod(crest, Vector3(x0, 0.0015, 0.0011), Vector3(x0 + side * 0.0022, 0.0085 - k * 0.0012, 0.0011), 0.00022, line, 4)
		_mi(crest, _torus(0.0016, 0.0022, 16, 3), line, Vector3(side * 0.0058, -0.0052, 0.0009), Vector3(90, 0, 0)) # scrolls
		_rod(crest, Vector3(side * 0.0035, 0.0015, 0.0011), Vector3(side * 0.0048, -0.004, 0.0011), 0.0002, line, 4)
	_mi(crest, _box(Vector3(0.0004, 0.009, 0.0002)), line, Vector3(0, 0.0105, 0.0011)) # the line down from the top
	_mi(crest, _cyl(0.0016, 0.0016, 0.0002, 16), line, Vector3(0, 0.0038, 0.0011), Vector3(90, 0, 0)) # the dots
	for p in [Vector2(-0.0014, 0.0012), Vector2(0.0014, 0.0012), Vector2(0, -0.0002)]:
		_mi(crest, _cyl(0.0009, 0.0009, 0.0002, 12), line, Vector3(p.x, p.y, 0.0011), Vector3(90, 0, 0))
	_mi(crest, _box(Vector3(0.0004, 0.006, 0.0002)), line, Vector3(0, -0.005, 0.0011)) # and on down to the bottom
	_print(sheet, "BLUEPRINT", Vector3(0.016, -0.019, 0.0007), Vector3.ZERO, 0.00008, ink.albedo_color)
	# a pencil lying across
	var yellow := _mat(Color(0.98, 0.78, 0.15), 0.6)
	var pencil := _node(j, "Pencil", Vector3(0.018, 0.006, 0.034))
	pencil.rotation_degrees = Vector3(0, 30, 90)
	_mi(pencil, _cyl(0.0022, 0.0022, 0.04, 6), yellow)
	_mi(pencil, _cyl(0.0001, 0.0022, 0.006, 6), _mat(Color(0.85, 0.7, 0.5), 0.8), Vector3(0, 0.023, 0))
	_mi(pencil, _cyl(0.0023, 0.0023, 0.004, 8), _mat(Color(0.95, 0.5, 0.55), 0.8), Vector3(0, -0.022, 0))
	return j


# ================================================================ DNA
## A turning double helix of coloured bases on a lab stand.
func _dna() -> Node3D:
	var j := _begin("dna", {"spin_node": NodePath("Helix"), "spin_speed": 0.9})
	var metal := _mat(Color(0.75, 0.78, 0.82), 0.3, 0.8)
	_mi(j, _cyl(0.022, 0.025, 0.006, 24), metal, Vector3(0, 0.003, 0))
	_mi(j, _cyl(0.0025, 0.0025, 0.1, 8), metal, Vector3(0, 0.055, 0))
	var helix := _node(j, "Helix", Vector3(0, 0.012, 0))
	var blue := _mat(Color(0.2, 0.45, 0.95), 0.35)
	var red := _mat(Color(0.95, 0.25, 0.3), 0.35)
	var base_cols := [Color(0.98, 0.8, 0.2), Color(0.3, 0.85, 0.5), Color(0.6, 0.35, 0.9), Color(0.98, 0.5, 0.2)]
	var n := 40
	var pa: Array = []
	var pb: Array = []
	var radii: Array = []
	for i in n:
		var t := float(i) / (n - 1)
		var a := t * TAU * 1.6
		var y := t * 0.09
		pa.append(Vector3(cos(a) * 0.016, y, sin(a) * 0.016))
		pb.append(Vector3(cos(a + PI) * 0.016, y, sin(a + PI) * 0.016))
		radii.append(0.0022)
	_mi(helix, _sweep(pa, radii, 8), blue)
	_mi(helix, _sweep(pb, radii, 8), red)
	for i in range(1, n - 1, 3): # base pairs
		var mid: Vector3 = (pa[i] + pb[i]) * 0.5
		_rod(helix, pa[i], mid, 0.0012, _mat(base_cols[i % 4], 0.4), 6)
		_rod(helix, mid, pb[i], 0.0012, _mat(base_cols[(i + 2) % 4], 0.4), 6)
	return j


# ================================================================ Space Joker
## A little planet with a ring, a moon going round it and a tiny Jimbo in a space helmet on top.
func _space() -> Node3D:
	var j := _begin("space", {"spin_node": NodePath("Orbit"), "spin_speed": 0.8})
	_mi(j, _cyl(0.024, 0.026, 0.006, 24), _mat(Color(0.05, 0.05, 0.12), 0.5), Vector3(0, 0.003, 0))
	for i in 10: # stars on the base
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(0.006, 0.022)
		_mi(j, _sph(0.0009, -1, 4), _glowing(Color(1, 1, 0.85), 2.0), Vector3(cos(a) * r, 0.0062, sin(a) * r))
	_rod(j, Vector3(0, 0.006, 0), Vector3(0, 0.02, 0), 0.0018, _mat(Color(0.3, 0.3, 0.35), 0.4, 0.6))
	var planet := _node(j, "Planet", Vector3(0, 0.045, 0))
	_mi(planet, _sph(0.022, -1, 28), _mat(Color(0.25, 0.45, 0.9), 0.6))
	for i in 5: # continents
		var a := _rng.randf() * TAU
		var b := _rng.randf_range(-0.8, 0.8)
		var p := Vector3(cos(a) * cos(b), sin(b), sin(a) * cos(b)) * 0.0205
		_mi(planet, _sph(0.007, -1, 8), _mat(Color(0.3, 0.7, 0.35), 0.7), p, Vector3.ZERO, Vector3(1, 0.5, 1))
	_mi(planet, _torus(0.027, 0.036, 40, 4), _mat(Color(0.9, 0.75, 0.45), 0.5), Vector3.ZERO, Vector3(18, 0, 10), Vector3(1, 0.08, 1))
	var orbit := _node(j, "Orbit", Vector3(0, 0.045, 0))
	_mi(orbit, _sph(0.0055, -1, 12), _mat(Color(0.75, 0.75, 0.78), 0.8), Vector3(0.036, 0.01, 0))
	var jimbo := _jester(planet, "Astronaut", 0.32)
	jimbo.position = Vector3(0, 0.021, 0)
	_mi(jimbo, _sph(0.0065, -1, 12), _see_through(Color(0.7, 0.9, 1.0), 0.35), Vector3(0, 0.028, 0)) # space helmet
	return j


# ================================================================ Mr. Bones
## A skeleton sitting on the pedestal's edge, legs dangling, grinning.
func _mr_bones() -> Node3D:
	var j := _begin("mr_bones", {})
	var bone := _mat(Color(0.93, 0.9, 0.8), 0.6)
	var dark := _mat(Color(0.06, 0.05, 0.05), 0.9)
	_mi(j, _box(Vector3(0.05, 0.012, 0.03)), _mat(Color(0.25, 0.22, 0.2), 0.8), Vector3(0, 0.006, -0.004)) # a crate to sit on
	var hip := Vector3(0, 0.016, -0.002)
	_mi(j, _sph(0.009, -1, 10), bone, hip, Vector3.ZERO, Vector3(1.3, 0.6, 0.9)) # pelvis
	# spine and ribs
	var chest := hip + Vector3(0, 0.038, -0.002)
	for i in 8:
		_mi(j, _cyl(0.0022, 0.0022, 0.004, 8), bone, hip.lerp(chest, i / 7.0))
	for i in 4:
		var y := 0.034 + i * 0.006
		_mi(j, _torus(0.007 - i * 0.0005, 0.0085 - i * 0.0005, 16, 4), bone, Vector3(0, y, 0.0), Vector3(0, 0, 0), Vector3(1, 0.5, 0.8))
	_mi(j, _box(Vector3(0.02, 0.002, 0.002)), bone, Vector3(0, 0.056, 0)) # collar bones
	# legs: thigh forward, shin hanging down over the crate's edge
	for side in [-1.0, 1.0]:
		var knee := Vector3(side * 0.007, 0.016, 0.022)
		var foot := Vector3(side * 0.008, -0.004, 0.026)
		_rod(j, hip + Vector3(side * 0.006, 0, 0), knee, 0.0022, bone, 8)
		_rod(j, knee, foot, 0.002, bone, 8)
		_mi(j, _sph(0.0028), bone, knee)
		_mi(j, _box(Vector3(0.006, 0.002, 0.01)), bone, foot + Vector3(0, -0.001, 0.003))
	# arms: one resting on the knee, one waving
	var shoulder_l := Vector3(-0.011, 0.055, 0)
	var shoulder_r := Vector3(0.011, 0.055, 0)
	_rod(j, shoulder_l, Vector3(-0.015, 0.036, 0.012), 0.0018, bone, 6)
	_rod(j, Vector3(-0.015, 0.036, 0.012), Vector3(-0.009, 0.019, 0.021), 0.0016, bone, 6)
	_rod(j, shoulder_r, Vector3(0.024, 0.066, 0.004), 0.0018, bone, 6)
	_rod(j, Vector3(0.024, 0.066, 0.004), Vector3(0.026, 0.084, 0.006), 0.0016, bone, 6)
	for k in 4: # waving fingers
		_rod(j, Vector3(0.026, 0.084, 0.006), Vector3(0.022 + k * 0.0025, 0.091, 0.006), 0.0006, bone, 4)
	var skull := _skull(j, "Skull", 1.0, dark)
	skull.position = Vector3(0, 0.06, 0)
	skull.rotation_degrees = Vector3(-5, 0, -8)
	return j


# ================================================================ Supernova
## A star about to explode: a blazing core, spikes of light turning round it, a hot shell.
func _supernova() -> Node3D:
	var j := _begin("supernova", {"spin_node": NodePath("Rays"), "spin_speed": 0.7, "label_node": NodePath("Value"),
			"label_source": "joker[\"value\"]"})
	_mi(j, _cyl(0.022, 0.025, 0.006, 24), _mat(Color(0.06, 0.04, 0.1), 0.5), Vector3(0, 0.003, 0))
	_rod(j, Vector3(0, 0.006, 0), Vector3(0, 0.03, 0), 0.0015, _mat(Color(0.3, 0.25, 0.35), 0.5, 0.5))
	_mi(j, _sph(0.013, -1, 20), _glowing(Color(1.0, 0.95, 0.75), 5.0), Vector3(0, 0.055, 0))
	var shell := _see_through(Color(1.0, 0.5, 0.15), 0.3, 0.4)
	shell.emission_enabled = true
	shell.emission = Color(1.0, 0.45, 0.1)
	shell.emission_energy_multiplier = 1.5
	shell.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mi(j, _sph(0.02, -1, 20), shell, Vector3(0, 0.055, 0))
	var rays := _node(j, "Rays", Vector3(0, 0.055, 0))
	var spike := _glowing(Color(1.0, 0.7, 0.25), 3.0)
	for i in 14:
		var dir := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.7, 1), _rng.randf_range(-1, 1)).normalized()
		var length := _rng.randf_range(0.018, 0.034)
		var m := _mi(rays, _cyl(0.0001, 0.0028, length, 6), spike)
		m.transform = Transform3D(_align_y(dir), dir * (0.014 + length * 0.5))
	_value_label(j, "Value", 0.12)
	return j


# ================================================================ Cloud 9
## A fluffy cloud with a big golden 9 on it, coins dripping like rain.
func _cloud_9() -> Node3D:
	var j := _begin("cloud_9", {"label_node": NodePath("Value"), "label_source": "joker[\"value\"]"})
	_mi(j, _cyl(0.02, 0.023, 0.006, 24), _mat(Color(0.5, 0.75, 0.95), 0.6), Vector3(0, 0.003, 0))
	_rod(j, Vector3(0, 0.006, 0), Vector3(0, 0.03, 0), 0.0015, _mat(Color(0.8, 0.85, 0.9), 0.4, 0.5))
	var cloud := _node(j, "Cloud", Vector3(0, 0.04, 0))
	var white := _mat(Color(0.97, 0.98, 1.0), 0.9)
	for p in [Vector3(-0.018, 0, 0), Vector3(0.018, 0, 0), Vector3(0, 0.006, 0), Vector3(-0.009, 0.01, 0.004),
			Vector3(0.01, 0.009, -0.003), Vector3(0, 0, 0.01), Vector3(0, -0.002, -0.009), Vector3(-0.025, -0.004, 0.004),
			Vector3(0.026, -0.004, 0.002)]:
		_mi(cloud, _sph(_rng.randf_range(0.011, 0.015), -1, 14), white, p)
	var nine := Label3D.new()
	nine.text = "9"
	nine.font_size = 96
	nine.pixel_size = 0.0006
	nine.modulate = Color(1.0, 0.8, 0.25)
	nine.outline_size = 12
	nine.outline_modulate = Color(0.5, 0.3, 0.05)
	nine.position = Vector3(0, 0.032, 0.006)
	cloud.add_child(nine)
	for i in 4: # coins falling like rain
		var coin := _mi(j, _cyl(0.0035, 0.0035, 0.001, 14), _gold(), Vector3(-0.015 + i * 0.01, 0.022 - (i % 2) * 0.006, 0.006),
				Vector3(70, 0, i * 20.0))
		coin.name = "Coin%d" % i
	_value_label(j, "Value", 0.13)
	return j


# ================================================================ the legendaries

## Canio: a sad clown holding wilted flowers; his tears glow brighter with every face card destroyed.
func _canio() -> Node3D:
	var j := _begin("caino", {"glow_node": NodePath("Tears"), "glow_source": "clamp((ab[\"x_mult\"] - 1.0) / 4.0, 0.15, 1.0)",
			"glow_energy": 4.0, "label_node": NodePath("Value"), "label_source": "ab[\"x_mult\"]", "label_format": "x%.0f"})
	_foot(j, 0.028, Color(0.18, 0.12, 0.2))
	var fig := _jester(j, "Figure", 1.05, Color(0.3, 0.3, 0.45), Color(0.85, 0.85, 0.9))
	fig.position.y = 0.006
	var tears := _node(j, "Tears")
	var tear := _mat(Color(0.35, 0.6, 1.0), 0.2)
	for side in [-1.0, 1.0]:
		for k in 2:
			_mi(tears, _sph(0.0014, -1, 8), tear, Vector3(side * 0.0055, 0.095 - k * 0.006, 0.0148), Vector3.ZERO, Vector3(1, 1.5, 1))
	# wilted flowers in his hand
	var stem := _mat(Color(0.3, 0.5, 0.2), 0.7)
	var hand := Vector3(0.029, 0.048, 0.008)
	for k in 3:
		var top := hand + Vector3(0.004 * (k - 1), 0.014, 0.004 + k * 0.002)
		_rod(j, hand, top, 0.0007, stem, 4)
		var petals := [Color(0.85, 0.3, 0.5), Color(0.95, 0.75, 0.2), Color(0.6, 0.35, 0.85)]
		_mi(j, _sph(0.0035, -1, 8), _mat(petals[k], 0.6), top + Vector3(0.002, -0.002, 0), Vector3.ZERO, Vector3(1, 0.6, 1))
	_value_label(j, "Value", 0.14)
	return j


## Triboulet: a royal jester in red and gold, a crown on his hat and a sceptre in his hand.
func _triboulet() -> Node3D:
	var j := _begin("triboulet", {})
	_foot(j, 0.028, Color(0.35, 0.06, 0.08))
	var fig := _jester(j, "Figure", 1.05, Color(0.75, 0.1, 0.12), Color(0.95, 0.75, 0.2))
	fig.position.y = 0.006
	var crown := _node(j, "Crown", Vector3(0, 0.119, -0.001))
	_mi(crown, _cyl(0.0095, 0.0095, 0.004, 20), _gold())
	for i in 6:
		var a := TAU * i / 6.0
		_mi(crown, _cyl(0.0001, 0.0018, 0.006, 4), _gold(), Vector3(cos(a) * 0.0088, 0.004, sin(a) * 0.0088))
		_mi(crown, _sph(0.0012, -1, 6), _glowing([Color(0.9, 0.1, 0.2), Color(0.2, 0.5, 1.0), Color(0.2, 0.85, 0.4)][i % 3], 1.0),
				Vector3(cos(a) * 0.0095, 0.0, sin(a) * 0.0095))
	var hand := Vector3(0.028, 0.042, 0.008)
	_rod(j, hand + Vector3(0, -0.012, 0), hand + Vector3(0, 0.035, 0), 0.0012, _gold(), 8) # sceptre
	_mi(j, _sph(0.0045, -1, 12), _glowing(Color(0.95, 0.2, 0.3), 1.2), hand + Vector3(0, 0.038, 0))
	_mi(j, _torus(0.003, 0.0045, 12, 4), _gold(), hand + Vector3(0, 0.034, 0))
	return j


## Yorick: a skull resting on a pile of old books; its eyes glow brighter as its xMult grows.
func _yorick() -> Node3D:
	var j := _begin("yorick", {"glow_node": NodePath("Skull/Eyes"), "glow_source": "clamp((ab[\"x_mult\"] - 1.0) / 4.0, 0.15, 1.0)",
			"glow_energy": 4.0, "label_node": NodePath("Value"), "label_source": "joker[\"value\"]"})
	var covers := [Color(0.45, 0.08, 0.1), Color(0.12, 0.25, 0.15), Color(0.2, 0.12, 0.35)]
	var pages := _mat(Color(0.92, 0.88, 0.75), 0.9)
	var y := 0.0
	for i in 3:
		var h := 0.009 - i * 0.001
		var book := _node(j, "Book%d" % i, Vector3(0, y + h * 0.5, 0))
		book.rotation_degrees.y = (i - 1) * 12.0
		_mi(book, _box(Vector3(0.048 - i * 0.006, h, 0.034 - i * 0.004)), _mat(covers[i], 0.7))
		_mi(book, _box(Vector3(0.045 - i * 0.006, h * 0.8, 0.032 - i * 0.004)), pages, Vector3(0.002, 0, 0.0015))
		_mi(book, _box(Vector3(0.0015, h * 1.02, 0.034 - i * 0.004)), _gold(), Vector3(-(0.048 - i * 0.006) * 0.5, 0, 0))
		y += h
	var skull := _skull(j, "Skull", 1.25, _mat(Color(0.3, 1.0, 0.45), 0.4))
	skull.position = Vector3(0, y + 0.002, 0)
	skull.rotation_degrees.y = -10.0
	_mi(j, _cyl(0.0035, 0.004, 0.012, 10), _mat(Color(0.95, 0.92, 0.8), 0.8), Vector3(0.018, y + 0.006, 0.008)) # a candle
	_mi(j, _sph(0.002, 0.005, 8), _glowing(Color(1.0, 0.7, 0.25), 3.0), Vector3(0.018, y + 0.0145, 0.008))
	_value_label(j, "Value", 0.12)
	return j


## Chicot: a jester in blue and yellow behind a round shield, a Boss Blind chip bouncing off it.
func _chicot() -> Node3D:
	var j := _begin("chicot", {})
	_foot(j, 0.028, Color(0.1, 0.15, 0.3))
	var fig := _jester(j, "Figure", 1.05, Color(0.2, 0.3, 0.8), Color(0.95, 0.8, 0.2))
	fig.position.y = 0.006
	var shield := _node(j, "Shield", Vector3(-0.026, 0.05, 0.016))
	shield.rotation_degrees = Vector3(0, -30, 0)
	_mi(shield, _cyl(0.017, 0.017, 0.003, 28), _mat(Color(0.2, 0.3, 0.8), 0.4, 0.3), Vector3.ZERO, Vector3(90, 0, 0))
	_mi(shield, _torus(0.016, 0.018, 28, 6), _gold(), Vector3.ZERO, Vector3(90, 0, 0))
	_mi(shield, _cyl(0.005, 0.005, 0.004, 16), _gold(), Vector3(0, 0, 0.001), Vector3(90, 0, 0)) # boss (the centre)
	for k in 2: # a gold cross on it
		_mi(shield, _box(Vector3(0.026 if k == 0 else 0.003, 0.003 if k == 0 else 0.026, 0.001)), _gold(), Vector3(0, 0, 0.0018))
	# a red Boss Blind chip bouncing off, with little impact lines
	var chip := _node(j, "Chip", Vector3(-0.04, 0.072, 0.034))
	chip.rotation_degrees = Vector3(70, 30, 20)
	_mi(chip, _cyl(0.008, 0.008, 0.002, 20), _mat(Color(0.85, 0.12, 0.12), 0.4))
	_mi(chip, _torus(0.0068, 0.0078, 20, 4), _mat(Color(0.98, 0.95, 0.9), 0.4))
	var spark := _glowing(Color(1.0, 0.9, 0.5), 2.5)
	for i in 3:
		var a := deg_to_rad(-40 + i * 40)
		_rod(j, Vector3(-0.034, 0.062, 0.03), Vector3(-0.034, 0.062, 0.03) + Vector3(cos(a), sin(a), 0.5).normalized() * 0.008, 0.0006, spark, 4)
	return j


## Perkeo: a jester leaning on a wine barrel, negative-glowing bottles circling him.
func _perkeo() -> Node3D:
	var j := _begin("perkeo", {"spin_node": NodePath("Bottles"), "spin_speed": 0.7})
	_foot(j, 0.03, Color(0.2, 0.1, 0.05))
	var fig := _jester(j, "Figure", 0.95, Color(0.55, 0.15, 0.6), Color(0.15, 0.6, 0.55))
	fig.position = Vector3(0.008, 0.006, 0)
	var barrel := _node(j, "Barrel", Vector3(-0.022, 0.006, -0.004))
	var staves := PackedVector2Array()
	for i in 9:
		var t := i / 8.0
		staves.append(Vector2(0.011 + 0.003 * sin(t * PI), t * 0.03))
	staves.insert(0, Vector2(0, 0))
	staves.append(Vector2(0, 0.03))
	_mi(barrel, _lathe(staves, 16), _mat(Color(0.5, 0.3, 0.14), 0.7))
	for y in [0.004, 0.026, 0.015]:
		_mi(barrel, _torus(0.0118 + (0.0025 if y == 0.015 else 0.0005), 0.013 + (0.0025 if y == 0.015 else 0.0005), 20, 4),
				_mat(Color(0.3, 0.3, 0.32), 0.4, 0.7), Vector3(0, y, 0))
	_mi(barrel, _cyl(0.0015, 0.0015, 0.006, 8), _mat(Color(0.3, 0.2, 0.1), 0.6), Vector3(0, 0.015, 0.016), Vector3(90, 0, 0)) # tap
	# bottles circling, in the purple shimmer of Negative cards
	var bottles := _node(j, "Bottles", Vector3(0, 0.07, 0))
	var neg := _see_through(Color(0.55, 0.35, 0.95), 0.6, 0.1)
	neg.emission_enabled = true
	neg.emission = Color(0.55, 0.3, 1.0)
	neg.emission_energy_multiplier = 1.2
	var bottle := PackedVector2Array([Vector2(0, 0), Vector2(0.0045, 0), Vector2(0.0045, 0.009), Vector2(0.0018, 0.013),
			Vector2(0.0016, 0.017), Vector2(0, 0.017)])
	for i in 4:
		var a := TAU * i / 4.0
		var holder := _node(bottles, "Bottle", Vector3(cos(a) * 0.034, sin(i * 1.3) * 0.006, sin(a) * 0.034))
		holder.rotation_degrees = Vector3(0, 0, 20)
		_mi(holder, _lathe(bottle, 12), neg)
		_mi(holder, _cyl(0.0017, 0.0017, 0.003, 8), _mat(Color(0.5, 0.35, 0.2), 0.8), Vector3(0, 0.018, 0)) # cork
	return j


# ================================================================ the third set

## Vampire: a little coffin with candles, its lid swung open; Jimbo as a vampire stands inside.
## His eyes burn redder the more xMult he has drained.
func _vampire() -> Node3D:
	var j := _begin("vampire", {"glow_node": NodePath("Box/Inside/Eyes"),
			"glow_source": "clamp((ab[\"x_mult\"] - 1.0) / 2.0, 0.2, 1.0)", "glow_energy": 4.0,
			"label_node": NodePath("Value"), "label_source": "ab[\"x_mult\"]", "label_format": "x%.1f"})
	var wood := _mat(Color(0.18, 0.08, 0.06), 0.6)
	var velvet := _mat(Color(0.6, 0.05, 0.08), 0.9)
	var coffin := PackedVector2Array([Vector2(0, 0.0), Vector2(0.016, 0.006), Vector2(0.021, 0.042), Vector2(0.014, 0.068),
			Vector2(-0.014, 0.068), Vector2(-0.021, 0.042), Vector2(-0.016, 0.006)])
	# the coffin box, standing up a little leaned back, its velvet lining inside
	var box := _node(j, "Box", Vector3(0, 0.004, -0.004))
	box.rotation_degrees.x = -12.0
	_mi(box, _extrude(coffin, 0.006), wood, Vector3(0, 0, -0.012))                  # back
	for side in [-1.0, 1.0]: # walls (a slab per edge)
		_rod(box, Vector3(side * 0.016, 0.006, -0.006), Vector3(side * 0.021, 0.042, -0.006), 0.0035, wood, 6)
		_rod(box, Vector3(side * 0.021, 0.042, -0.006), Vector3(side * 0.014, 0.068, -0.006), 0.0035, wood, 6)
	_rod(box, Vector3(-0.016, 0.004, -0.006), Vector3(0.016, 0.004, -0.006), 0.0035, wood, 6)
	_rod(box, Vector3(-0.014, 0.068, -0.006), Vector3(0.014, 0.068, -0.006), 0.0035, wood, 6)
	_mi(box, _extrude(coffin, 0.002), velvet, Vector3(0, 0, -0.008), Vector3.ZERO, Vector3(0.9, 0.95, 1))
	# inside: a pale vampire Jimbo in a black cape with a red collar
	var inside := _node(box, "Inside", Vector3(0, 0.004, -0.004))
	var fig := _jester(inside, "Figure", 0.55, Color(0.08, 0.06, 0.1), Color(0.55, 0.05, 0.08))
	fig.position = Vector3(0, 0.0, 0)
	var eyes := _node(inside, "Eyes")
	var red := _mat(Color(1.0, 0.1, 0.1), 0.3)
	for side in [-1.0, 1.0]:
		_mi(eyes, _sph(0.0016, -1, 8), red, Vector3(side * 0.0028, 0.0492, 0.0072))
	for side in [-1.0, 1.0]: # fangs
		_mi(inside, _cyl(0.0001, 0.0009, 0.0025, 4), _mat(Color(1, 1, 1), 0.3), Vector3(side * 0.0018, 0.0425, 0.0074), Vector3(180, 0, 0))
	# the lid on a hinge at the coffin's left edge
	var hinge := _node(box, "Hinge", Vector3(-0.021, 0.0, 0.002))
	hinge.rotation_degrees.y = -75.0 # swung open
	var lid_pivot := _node(hinge, "Lid")
	_mi(lid_pivot, _extrude(coffin, 0.004), wood, Vector3(0.021, 0, 0))
	_mi(lid_pivot, _box(Vector3(0.004, 0.026, 0.001)), _gold(), Vector3(0.021, 0.04, 0.0025))   # gold cross
	_mi(lid_pivot, _box(Vector3(0.016, 0.004, 0.001)), _gold(), Vector3(0.021, 0.046, 0.0025))
	# candles
	for side in [-1.0, 1.0]:
		var c := Vector3(side * 0.03, 0, 0.012)
		_mi(j, _cyl(0.0032, 0.0036, 0.022, 10), _mat(Color(0.95, 0.92, 0.8), 0.8), c + Vector3(0, 0.011, 0))
		_mi(j, _sph(0.002, 0.005, 8), _glowing(Color(1.0, 0.65, 0.2), 3.5), c + Vector3(0, 0.025, 0))
	_mi(j, _cyl(0.04, 0.042, 0.004, 24), _mat(Color(0.12, 0.08, 0.1), 0.6), Vector3(0, 0.002, 0))
	_value_label(j, "Value", 0.12)
	return j


## Swashbuckler: a pirate hat and a cutlass on a treasure chest; the gold heaped in the chest grows
## with the sell value of your other jokers.
func _swashbuckler() -> Node3D:
	var j := _begin("swashbuckler", {"fill_node": NodePath("Gold"), "fill_source": "ab[\"mult\"]", "fill_max": 30.0,
			"fill_min": 0.15, "label_node": NodePath("Value"), "label_source": "ab[\"mult\"]", "label_format": "+%d Mult"})
	var wood := _mat(Color(0.45, 0.24, 0.1), 0.6)
	var iron := _mat(Color(0.25, 0.25, 0.28), 0.4, 0.7)
	_mi(j, _box(Vector3(0.06, 0.03, 0.036)), wood, Vector3(0, 0.015, 0))                      # the chest
	for x in [-0.024, 0.024]:
		_mi(j, _box(Vector3(0.004, 0.031, 0.037)), iron, Vector3(x, 0.015, 0))               # iron bands
	_mi(j, _box(Vector3(0.008, 0.01, 0.002)), _gold(), Vector3(0, 0.022, 0.0185))            # lock
	# the lid, open and leaning back
	var lid := _node(j, "Lid", Vector3(0, 0.03, -0.018))
	lid.rotation_degrees.x = -70.0
	_mi(lid, _cyl(0.018, 0.018, 0.06, 16), wood, Vector3(0, 0.0, 0.018), Vector3(0, 0, 90), Vector3(1, 1, 0.5))
	# gold coins heaped inside (fills up)
	var gold := _node(j, "Gold", Vector3(0, 0.03, 0))
	for i in 22:
		var p := Vector3(_rng.randf_range(-0.024, 0.024), _rng.randf_range(0.0, 0.012), _rng.randf_range(-0.014, 0.014))
		_mi(gold, _cyl(0.005, 0.005, 0.0015, 12), _gold(), p, Vector3(_rng.randf_range(-40, 40), 0, _rng.randf_range(-40, 40)))
	_mi(gold, _sph(0.026, 0.016, 16), _gold(), Vector3(0, -0.002, 0), Vector3.ZERO, Vector3(1, 0.4, 0.6))
	# the pirate hat on top, a cutlass leaning against the chest
	var hat := _node(j, "Hat", Vector3(-0.012, 0.05, 0.004))
	hat.rotation_degrees = Vector3(0, 20, -12)
	var black := _mat(Color(0.06, 0.05, 0.07), 0.6)
	var brim := PackedVector2Array([Vector2(-0.03, 0), Vector2(-0.02, 0.012), Vector2(0, 0.02), Vector2(0.02, 0.012),
			Vector2(0.03, 0), Vector2(0, 0.006)])
	_mi(hat, _extrude(brim, 0.022), black)
	_mi(hat, _box(Vector3(0.012, 0.009, 0.001)), _mat(Color(0.95, 0.95, 0.9), 0.5), Vector3(0, 0.011, 0.0115)) # skull patch
	var blade := PackedVector2Array([Vector2(0, 0), Vector2(0.004, 0.004), Vector2(0.006, 0.04), Vector2(0.002, 0.05),
			Vector2(-0.002, 0.04), Vector2(-0.003, 0.004)])
	var sword := _node(j, "Cutlass", Vector3(0.036, 0.0, 0.012))
	sword.rotation_degrees.z = 18.0
	_mi(sword, _extrude(blade, 0.0015), _mat(Color(0.85, 0.85, 0.88), 0.25, 0.8), Vector3(0, 0.0, 0))
	_mi(sword, _torus(0.004, 0.0055, 12, 4), _gold(), Vector3(0, 0.052, 0), Vector3(90, 0, 0))
	_mi(sword, _cyl(0.0022, 0.0022, 0.012, 8), _mat(Color(0.3, 0.15, 0.06), 0.6), Vector3(0, 0.059, 0))
	_value_label(j, "Value", 0.12)
	return j


## Blue Joker: a tower of blue cards; it shrinks storey by storey as the deck gets smaller.
func _blue_joker() -> Node3D:
	var j := _begin("blue_joker", {"fill_node": NodePath("Tower"), "fill_source": "joker[\"value\"].to_int()", "fill_max": 104.0,
			"fill_min": 0.08, "label_node": NodePath("Value"), "label_source": "joker[\"value\"]"})
	_mi(j, _cyl(0.038, 0.04, 0.004, 24), _mat(Color(0.08, 0.15, 0.35), 0.5), Vector3(0, 0.002, 0))
	var tower := _node(j, "Tower", Vector3(0, 0.004, 0))
	var blue := _mat(Color(0.25, 0.5, 0.95), 0.6)
	var white := _mat(Color(0.9, 0.93, 1.0), 0.6)
	var levels := 5
	for lvl in levels: # a classic card house: leaning pairs and a flat card on top of each storey
		var y := lvl * 0.021
		var pairs := levels - lvl
		for p in pairs:
			var x := (p - (pairs - 1) * 0.5) * 0.017
			for side in [-1.0, 1.0]:
				var c := _mi(tower, _box(Vector3(0.0008, 0.022, 0.014)), blue if side < 0 else white,
						Vector3(x + side * 0.0035, y + 0.0105, 0))
				c.rotation_degrees.z = side * 18.0 # (the tops lean together: a roof, not a V)
		if lvl < levels - 1:
			_mi(tower, _box(Vector3(pairs * 0.017, 0.0008, 0.014)), white, Vector3(0, y + 0.0215, 0))
	_value_label(j, "Value", 0.13)
	return j


## Steel Joker: shining steel ingots stacked up, one for every Steel card in your deck.
func _steel_joker() -> Node3D:
	var j := _begin("steel_joker", {"count_parent": NodePath("Bars"),
			"count_source": "round((joker[\"value\"].substr(1).to_float() - 1.0) / 0.2)",
			"label_node": NodePath("Value"), "label_source": "joker[\"value\"]"})
	_mi(j, _box(Vector3(0.07, 0.006, 0.05)), _mat(Color(0.18, 0.18, 0.2), 0.5, 0.4), Vector3(0, 0.003, 0))
	var bars := _node(j, "Bars")
	var steel := _mat(Color(0.82, 0.85, 0.9), 0.3, 0.45) # (half metallic: shines without going dark in the casino)
	steel.emission_enabled = true
	steel.emission = Color(0.25, 0.28, 0.32)
	var ingot := PackedVector2Array([Vector2(-0.014, 0), Vector2(0.014, 0), Vector2(0.011, 0.008), Vector2(-0.011, 0.008)])
	var n := 0
	for layer in 4: # a pyramid of ingots, the bottom layer first
		var count := 4 - layer
		for k in count:
			var bar := _node(bars, "Bar%d" % n)
			bar.position = Vector3((k - (count - 1) * 0.5) * 0.017, 0.006 + layer * 0.0085, 0)
			bar.rotation_degrees.y = 90.0 if layer % 2 == 1 else 0.0
			_mi(bar, _extrude(ingot, 0.012), steel)
			n += 1
	_value_label(j, "Value", 0.11)
	return j


## Brainstorm: a pink brain under a glass dome on a brass stand, little lightning bolts flashing round it.
func _brainstorm() -> Node3D:
	var j := _begin("brainstorm", {"spin_node": NodePath("Sparks"), "spin_speed": 2.5})
	var brass := _mat(Color(0.75, 0.55, 0.25), 0.3, 0.8)
	_mi(j, _cyl(0.03, 0.033, 0.008, 24), brass, Vector3(0, 0.004, 0))
	_mi(j, _cyl(0.024, 0.026, 0.004, 24), _mat(Color(0.12, 0.1, 0.12), 0.5), Vector3(0, 0.01, 0))
	var brain := _node(j, "Brain", Vector3(0, 0.032, 0))
	var pink := _mat(Color(0.95, 0.55, 0.65), 0.55)
	for side in [-1.0, 1.0]: # the two halves, with folds
		_mi(brain, _sph(0.014, -1, 16), pink, Vector3(side * 0.007, 0, 0), Vector3.ZERO, Vector3(0.8, 0.85, 1.15))
		for k in 5:
			var path: Array = []
			var radii: Array = []
			for t in 7:
				var a := -1.2 + t * 0.4
				path.append(Vector3(side * (0.007 + 0.0105 * cos(a) * 0.75), 0.012 * sin(a) * 0.9 + 0.001, -0.014 + k * 0.007))
				radii.append(0.0018)
			_mi(brain, _sweep(path, radii, 5), _mat(Color(0.88, 0.45, 0.55), 0.6))
	_mi(brain, _cyl(0.004, 0.003, 0.014, 8), pink, Vector3(0, -0.014, -0.004)) # brain stem
	var glass := _see_through(Color(0.75, 0.88, 1.0), 0.2, 0.05)
	_mi(j, _sph(0.026, -1, 24), glass, Vector3(0, 0.033, 0), Vector3.ZERO, Vector3(1, 1.15, 1))
	var sparks := _node(j, "Sparks", Vector3(0, 0.034, 0))
	var bolt := _glowing(Color(0.6, 0.85, 1.0), 4.0)
	for i in 4:
		var a := TAU * i / 4.0
		var p0 := Vector3(cos(a), 0.3, sin(a)) * 0.017
		var p1 := Vector3(cos(a + 0.3), -0.1, sin(a + 0.3)) * 0.021
		var p2 := Vector3(cos(a), -0.5, sin(a)) * 0.019
		_rod(sparks, p0, p1, 0.0006, bolt, 4)
		_rod(sparks, p1, p2, 0.0006, bolt, 4)
	return j


## Seance: a crystal ball on a dark stand between candles; a ghostly hand reaches up inside it.
func _seance() -> Node3D:
	var j := _begin("seance", {"spin_node": NodePath("Ball/Hand"), "spin_speed": 0.5})
	var dark := _mat(Color(0.1, 0.08, 0.14), 0.4, 0.3)
	_mi(j, _cyl(0.032, 0.035, 0.006, 24), _mat(Color(0.2, 0.1, 0.3), 0.8), Vector3(0, 0.003, 0))
	var stand := PackedVector2Array([Vector2(0.015, 0), Vector2(0.008, 0.006), Vector2(0.006, 0.012), Vector2(0.012, 0.018), Vector2(0, 0.018)])
	_mi(j, _lathe(stand, 16), dark, Vector3(0, 0.006, 0))
	var ball := _node(j, "Ball", Vector3(0, 0.044, 0))
	var glass := _see_through(Color(0.55, 0.85, 1.0), 0.25, 0.05)
	glass.emission_enabled = true
	glass.emission = Color(0.3, 0.6, 1.0)
	glass.emission_energy_multiplier = 0.6
	_mi(ball, _sph(0.021, -1, 28), glass)
	var ghost := _see_through(Color(0.75, 0.95, 1.0), 0.6, 0.3)
	ghost.emission_enabled = true
	ghost.emission = Color(0.6, 0.9, 1.0)
	ghost.emission_energy_multiplier = 1.5
	var hand := _node(ball, "Hand", Vector3(0, -0.012, 0))
	_mi(hand, _cyl(0.004, 0.003, 0.012, 8), ghost, Vector3(0, 0.003, 0))          # wrist
	_mi(hand, _sph(0.006, -1, 10), ghost, Vector3(0, 0.011, 0), Vector3.ZERO, Vector3(1, 0.8, 0.5))
	for k in 5: # fingers reaching up
		var x := -0.0045 + k * 0.00225
		var top := Vector3(x * 1.4, 0.024 - absf(k - 2) * 0.0015, 0)
		if k == 0:
			top = Vector3(-0.009, 0.015, 0.002)
		_rod(hand, Vector3(x, 0.014, 0), top, 0.0011, ghost, 6)
	for side in [-1.0, 1.0]:
		var c := Vector3(side * 0.03, 0, 0.0)
		_mi(j, _cyl(0.003, 0.0035, 0.024, 10), _mat(Color(0.3, 0.2, 0.45), 0.7), c + Vector3(0, 0.012, 0))
		_mi(j, _sph(0.002, 0.005, 8), _glowing(Color(0.5, 0.75, 1.0), 3.5), c + Vector3(0, 0.0265, 0))
	return j


## Golden Ticket: a golden ticket turning slowly and glinting over a little stand.
func _ticket() -> Node3D:
	var j := _begin("ticket", {"spin_node": NodePath("Ticket"), "spin_speed": 0.8})
	_mi(j, _cyl(0.022, 0.025, 0.006, 24), _mat(Color(0.25, 0.12, 0.06), 0.5), Vector3(0, 0.003, 0))
	_rod(j, Vector3(0, 0.006, 0), Vector3(0, 0.02, 0), 0.0015, _gold())
	var t := _node(j, "Ticket", Vector3(0, 0.045, 0))
	# a ticket with a notch in each side and a perforated stub
	var shape := PackedVector2Array([Vector2(-0.032, -0.018), Vector2(0.032, -0.018), Vector2(0.032, -0.005),
			Vector2(0.028, 0), Vector2(0.032, 0.005), Vector2(0.032, 0.018), Vector2(-0.032, 0.018), Vector2(-0.032, 0.005),
			Vector2(-0.028, 0), Vector2(-0.032, -0.005)])
	var g := _mat(Color(1.0, 0.8, 0.25), 0.3, 0.5)
	g.emission_enabled = true
	g.emission = Color(1.0, 0.75, 0.2)
	g.emission_energy_multiplier = 0.7
	_mi(t, _extrude(shape, 0.0012), g)
	var ink := Color(0.45, 0.25, 0.05)
	for face in [1.0, -1.0]:
		_print(t, "GOLDEN TICKET", Vector3(-0.004 * face, 0.004, 0.0008 * face), Vector3(0, 0 if face > 0 else 180, 0), 0.00011, ink)
		_print(t, "ADMIT ONE", Vector3(-0.004 * face, -0.007, 0.0008 * face), Vector3(0, 0 if face > 0 else 180, 0), 0.00008, ink)
	for k in 7: # the perforation to the stub
		_mi(t, _cyl(0.0009, 0.0009, 0.0016, 6), _mat(Color(0.5, 0.35, 0.1), 0.6), Vector3(0.019, -0.015 + k * 0.005, 0), Vector3(90, 0, 0))
	return j


## Smeared Joker: a painter's palette where the colours have run together - red into orange
## (Hearts and Diamonds) and blue into green (Spades and Clubs) - with a brush.
func _smeared() -> Node3D:
	var j := _begin("smeared", {})
	var pal := _node(j, "Palette", Vector3(0, 0.03, 0))
	pal.rotation_degrees.x = -55.0
	var outline := PackedVector2Array()
	for i in 28: # an oval with the thumb hole's bite
		var a := TAU * i / 28.0
		var p := Vector2(cos(a) * 0.036, sin(a) * 0.026)
		if a > 3.6 and a < 4.4:
			p *= 0.7
		outline.append(p)
	_mi(pal, _extrude(outline, 0.003), _mat(Color(0.75, 0.55, 0.32), 0.6))
	_mi(pal, _cyl(0.004, 0.004, 0.0035, 12), _mat(Color(0.1, 0.08, 0.1), 0.8), Vector3(-0.018, -0.008, 0), Vector3(90, 0, 0))
	# the smears: blobs running into each other
	var pairs := [[Color(0.9, 0.12, 0.2), Color(0.98, 0.5, 0.12), Vector2(0.006, 0.012)],
			[Color(0.2, 0.3, 0.85), Color(0.15, 0.65, 0.45), Vector2(0.008, -0.01)]]
	for pr in pairs:
		var at: Vector2 = pr[2]
		for k in 5:
			var c: Color = (pr[0] as Color).lerp(pr[1], k / 4.0)
			_mi(pal, _sph(0.0065, -1, 12), _mat(c, 0.2), Vector3(at.x - 0.014 + k * 0.007, at.y + sin(k * 1.3) * 0.002, 0.002),
					Vector3.ZERO, Vector3(1.0, 0.8, 0.35))
	# the brush lying across
	var brush := _node(j, "Brush", Vector3(0.01, 0.016, 0.022))
	brush.rotation_degrees = Vector3(0, -25, 80)
	_mi(brush, _cyl(0.0018, 0.0022, 0.05, 8), _mat(Color(0.15, 0.1, 0.08), 0.5), Vector3(0, 0, 0))
	_mi(brush, _cyl(0.0025, 0.0022, 0.006, 8), _mat(Color(0.75, 0.75, 0.8), 0.3, 0.8), Vector3(0, 0.027, 0))
	_mi(brush, _cyl(0.0005, 0.0026, 0.01, 8), _mat(Color(0.9, 0.3, 0.25), 0.4), Vector3(0, 0.035, 0))
	return j


## Walkie Talkie: a chunky teal walkie talkie on a little stand, antenna up, "10-4" on its display.
func _walkie_talkie() -> Node3D:
	var j := _begin("walkie_talkie", {})
	_foot(j, 0.022)
	var w := _node(j, "Walkie", Vector3(0, 0.038, 0))
	w.rotation_degrees.x = -8.0
	var teal := _mat(Color(0.12, 0.62, 0.66), 0.45, 0.1)
	var dark := _mat(Color(0.06, 0.12, 0.14), 0.5, 0.2)
	_mi(w, _extrude(_rounded_rect(0.032, 0.058, 0.005), 0.016), teal)
	_mi(w, _box(Vector3(0.026, 0.004, 0.017)), dark, Vector3(0, -0.027, 0)) # rubber bottom
	# speaker grille: rows of holes
	for r in 4:
		for c in 5:
			_mi(w, _cyl(0.0012, 0.0012, 0.0012, 8), dark, Vector3(-0.009 + c * 0.0045, -0.019 + r * 0.0045, 0.0082), Vector3(90, 0, 0))
	# the little display with 10-4 (the cards it likes: tens and fours)
	_mi(w, _box(Vector3(0.022, 0.012, 0.0012)), _mat(Color(0.08, 0.1, 0.08), 0.3), Vector3(0, 0.013, 0.0082))
	var lcd := _mat(Color(0.55, 0.95, 0.6), 0.3)
	lcd.emission_enabled = true
	lcd.emission = Color(0.4, 1.0, 0.5)
	lcd.emission_energy_multiplier = 1.2
	_mi(w, _box(Vector3(0.019, 0.009, 0.0006)), lcd, Vector3(0, 0.013, 0.0089))
	_print(w, "10-4", Vector3(0, 0.013, 0.0094), Vector3.ZERO, 0.00011, Color(0.05, 0.2, 0.08))
	# antenna, knobs and the red light on top
	_rod(w, Vector3(-0.01, 0.029, 0), Vector3(-0.01, 0.07, 0), 0.0022, dark)
	_mi(w, _sph(0.0035, -1, 10), dark, Vector3(-0.01, 0.071, 0))
	_mi(w, _cyl(0.0035, 0.0035, 0.006, 12), dark, Vector3(0.006, 0.032, 0))
	var led := _mat(Color(1.0, 0.15, 0.1), 0.3)
	led.emission_enabled = true
	led.emission = Color(1.0, 0.1, 0.05)
	led.emission_energy_multiplier = 2.0
	_mi(w, _sph(0.0018, -1, 8), led, Vector3(0.0115, 0.0305, 0.004))
	_mi(w, _box(Vector3(0.003, 0.016, 0.006)), dark, Vector3(-0.0175, 0.008, 0)) # push-to-talk button
	_print(w, "JIMBO", Vector3(0, 0.0025, 0.0084), Vector3.ZERO, 0.00008, Color(0.9, 0.95, 0.95))
	return j
