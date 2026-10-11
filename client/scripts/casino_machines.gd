class_name CasinoMachines
extends Node3D
## The gaming machines along the casino's side walls – every one different: themed slot machines
## with chasing marquee lights, a pachinko machine with falling balls, the "Joker Grabber" claw
## machine full of plush jokers, a video poker cabinet, a wheel of fortune that mostly says
## "NOPE!" and a coin pusher. Built from code like the rest of the room; the moving parts are
## animated here.

const GOLD := Color(0.86, 0.64, 0.26)
const CHROME := Color(0.75, 0.76, 0.8)

## Slot machine themes: title, cabinet colour, marquee colour, reel background, reel seed
const SLOT_THEMES := {
	"lucky_cat": ["LUCKY CAT", Color(0.05, 0.3, 0.15), Color(0.3, 2.4, 0.9), Color(0.95, 0.97, 0.88), 1.3],
	"jimbo": ["JACKPOT JIMBO", Color(0.4, 0.03, 0.06), Color(3.0, 0.4, 0.5), Color(0.98, 0.94, 0.86), 4.1],
	"cavendish": ["CAVENDISH CASH", Color(0.55, 0.42, 0.05), Color(3.0, 2.6, 0.4), Color(1.0, 0.98, 0.85), 7.7],
	"bloodstone": ["BLOODSTONE", Color(0.18, 0.04, 0.22), Color(2.4, 0.4, 3.0), Color(0.92, 0.88, 0.95), 2.9],
	"golden_ticket": ["GOLDEN TICKET", Color(0.05, 0.05, 0.06), Color(3.2, 2.3, 0.5), Color(1.0, 0.95, 0.8), 5.5],
}

var _gold: StandardMaterial3D
var _chrome: StandardMaterial3D
var _leather: StandardMaterial3D
var _glass: StandardMaterial3D
var _bulbs: Array[StandardMaterial3D] = []  # marquee lights: two groups that blink in turn
var _time := 0.0
var _claws: Array[Dictionary] = []          # {"carriage", "cable", "claw", "phase"}
var _wheels: Array[Dictionary] = []         # {"node", "angle", "speed", "wait"}
var _pushers: Array[Node3D] = []
var _glows: Array = []                     # glowing materials: {"mat", "energy"} (dimmed in the last hand)
var _dim := 1.0
var calm := false                          # Calm Lights: marquee bulbs glow steadily
var _jackpot_t := 0.0                      # > 0: the run was won, all machines hit the jackpot
var _screens: Array = []                   # the machines' screen materials (their "clock" is set here)
var _clock := 0.0
var _frenzy := false                       # The Wheel: everything runs fast
var _rate := 1.0


func _init() -> void:
	_gold = _mat(GOLD, 0.35, 0.6)
	_gold.emission_enabled = true
	_gold.emission = GOLD * 0.1
	_chrome = _mat(CHROME, 0.2, 0.9)
	_leather = _mat(Color(0.08, 0.03, 0.03), 0.45)
	_glass = StandardMaterial3D.new()
	_glass.albedo_color = Color(0.7, 0.85, 1.0, 0.12)
	_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glass.roughness = 0.05
	_glass.metallic_specular = 1.0
	for i in 2:
		var b := StandardMaterial3D.new()
		b.albedo_color = Color(1.0, 0.85, 0.5)
		b.emission_enabled = true
		b.emission = Color(1.0, 0.8, 0.45)
		_bulbs.append(b)


## Puts a machine of the given kind at pos (on the floor), its front turned by yaw degrees.
func add_machine(kind: String, pos: Vector3, yaw: float) -> void:
	var m := Node3D.new()
	m.position = pos
	m.rotation_degrees.y = yaw
	add_child(m)
	match kind:
		"pachinko": _pachinko(m)
		"claw": _claw_machine(m)
		"video_poker": _video_poker(m)
		"wheel": _wheel_of_fortune(m)
		"pusher": _coin_pusher(m)
		_: _slot(m, SLOT_THEMES.get(kind, SLOT_THEMES["jimbo"]))


## The room darkens (the last hand): buttons, lamps and marquee lights glow less. The screens keep
## running – a slot machine glowing alone in the dark looks just right.
func set_dim(f: float) -> void:
	_dim = f
	for g in _glows:
		(g["mat"] as StandardMaterial3D).emission_energy_multiplier = float(g["energy"]) * f


## The run is won: every machine hits the jackpot for a few seconds – the marquee lights race,
## the wheels of fortune spin (with Calm Lights the bulbs just glow bright, no racing).
func jackpot(seconds: float) -> void:
	_jackpot_t = seconds
	for w in _wheels:
		w["wait"] = 0.0
		w["speed"] = randf_range(8.0, 11.0)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_rate = move_toward(_rate, 3.5 if _frenzy else 1.0, delta * 2.0)
	delta *= _rate # everything below runs faster during The Wheel
	_time += delta
	_clock += delta
	for s in _screens:
		(s as ShaderMaterial).set_shader_parameter("clock", _clock)
	if _frenzy:
		for w in _wheels: # the wheels of fortune keep spinning
			w["wait"] = 0.0
			w["speed"] = maxf(float(w["speed"]), 6.0)
	# marquee chaser lights
	_jackpot_t = maxf(_jackpot_t - delta, 0.0)
	var jackpot := _jackpot_t > 0.0
	var phase := int(_time * (10.0 if jackpot else 3.0)) % 2 # a jackpot makes the lights race
	for i in _bulbs.size():
		var e := 3.0 if i == phase else 0.4
		if calm: # steady, no chasing (a jackpot just glows brighter)
			e = 2.6 if jackpot else 1.4
		_bulbs[i].emission_energy_multiplier = e * (maxf(_dim, 0.8) if jackpot else _dim)
	# claw machines: the claw wanders over the prizes, dips down, comes back up
	for c in _claws:
		var t: float = _time * 0.25 + c["phase"]
		var carriage: Node3D = c["carriage"]
		carriage.position.x = 0.22 * sin(t * 1.3)
		carriage.position.z = 0.12 * sin(t * 0.9 + 1.0)
		var dip := maxf(sin(t * 0.7), 0.0)
		dip = dip * dip * dip
		var drop := 0.05 + 0.33 * dip
		(c["cable"] as Node3D).scale.y = drop / 0.1
		(c["cable"] as Node3D).position.y = -drop * 0.5
		(c["claw"] as Node3D).position.y = -drop
		(c["claw"] as Node3D).rotation.y = t * 0.5
	# wheels of fortune: rest, then a big spin that slowly runs out (mostly on "NOPE!")
	for w in _wheels:
		if w["wait"] > 0.0:
			w["wait"] = w["wait"] - delta
			if w["wait"] <= 0.0:
				w["speed"] = randf_range(5.0, 9.0)
		else:
			w["speed"] = maxf(float(w["speed"]) - delta * 1.4, 0.0)
			w["angle"] = float(w["angle"]) + float(w["speed"]) * delta
			if w["speed"] <= 0.0:
				w["wait"] = randf_range(8.0, 16.0)
		(w["node"] as Node3D).rotation.z = -float(w["angle"])
	# coin pushers: the shelf slides to and fro
	for p in _pushers:
		p.position.z = -0.12 + 0.06 * sin(_time * 1.2)


# ---------------------------------------------------------------- the machines

## A classic slot machine in one of the themes: rounded topper with the name and chasing lights,
## reel window, pay table, buttons, coin tray and a lever.
func _slot(m: Node3D, theme: Array) -> void:
	var body := _mat(theme[1], 0.3, 0.2)
	var trim := _mat(Color(theme[1]).lightened(0.25), 0.3, 0.3)
	_box(m, Vector3(0.66, 0.72, 0.55), Vector3(0, 0.36, 0), body)                     # base
	_box(m, Vector3(0.7, 0.04, 0.58), Vector3(0, 0.74, 0.0), _chrome)                 # belt line
	_box(m, Vector3(0.62, 0.6, 0.45), Vector3(0, 1.06, -0.05), body)                  # upper cabinet
	_box(m, Vector3(0.68, 0.06, 0.26), Vector3(0, 0.79, 0.16), trim)                  # button deck
	var colours := [Color(0.9, 0.15, 0.15), Color(0.95, 0.75, 0.15), Color(0.2, 0.75, 0.3), Color(0.2, 0.45, 0.95)]
	for i in 4:
		_cyl(m, 0.022, 0.022, 0.02, Vector3(-0.2 + i * 0.13, 0.83, 0.2), _emissive(colours[i], 1.6), 16)
	_box(m, Vector3(0.12, 0.02, 0.05), Vector3(0.22, 0.83, 0.1), _chrome)             # coin slot
	# coin tray at the bottom
	_box(m, Vector3(0.44, 0.1, 0.12), Vector3(0, 0.12, 0.31), _chrome)
	_box(m, Vector3(0.4, 0.06, 0.08), Vector3(0, 0.15, 0.31), _mat(Color(0.03, 0.03, 0.03), 0.6))
	for i in 5:
		var coin := _cyl(m, 0.016, 0.016, 0.004, Vector3(-0.1 + i * 0.045, 0.185, 0.31 + (i % 2) * 0.02), _gold, 12)
		coin.rotation_degrees.x = 20.0 * (i % 3)
	# reel window with a chrome frame
	_box(m, Vector3(0.54, 0.34, 0.04), Vector3(0, 1.1, 0.17), _chrome)
	var reels := _quad(m, Vector2(0.48, 0.28), Vector3(0, 1.1, 0.192), _shader_mat(SLOT_REELS, {"seed": theme[4], "bg": theme[3]}))
	reels.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# topper: marquee with the name and a ring of chasing bulbs
	_box(m, Vector3(0.66, 0.36, 0.3), Vector3(0, 1.55, -0.08), trim)
	var marquee := _box(m, Vector3(0.58, 0.26, 0.02), Vector3(0, 1.55, 0.075), _emissive(Color(theme[2]) * 0.12, 1.0))
	marquee.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_label(m, theme[0], 64, 0.0011 if String(theme[0]).length() > 11 else 0.0014, theme[2], Vector3(0, 1.56, 0.09))
	_bulb_ring(m, Vector3(0, 1.55, 0.085), Vector2(0.62, 0.3), 18)
	# lever on the right side
	_cyl(m, 0.03, 0.03, 0.06, Vector3(0.34, 1.0, 0.0), _chrome).rotation_degrees.z = 90.0
	_cyl(m, 0.012, 0.012, 0.36, Vector3(0.37, 1.18, 0.0), _chrome)
	_add(m, _sphere(0.04), Vector3(0.37, 1.38, 0.0), _mat(Color(0.85, 0.1, 0.1), 0.25))
	_stool(m)


## Pachinko: a tall cabinet behind glass, silver balls bouncing down through brass pins.
func _pachinko(m: Node3D) -> void:
	var body := _mat(Color(0.85, 0.85, 0.9), 0.25, 0.3)
	_box(m, Vector3(0.62, 0.75, 0.45), Vector3(0, 0.375, 0), _mat(Color(0.1, 0.1, 0.14), 0.4))
	_box(m, Vector3(0.62, 1.0, 0.3), Vector3(0, 1.25, -0.06), body)
	var field := _quad(m, Vector2(0.52, 0.72), Vector3(0, 1.25, 0.095), _shader_mat(PACHINKO, {}))
	field.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var glass := _quad(m, Vector2(0.54, 0.74), Vector3(0, 1.25, 0.105), _glass)
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# chrome ring around the play field and a ball tray with a handle below it
	_box(m, Vector3(0.6, 0.04, 0.06), Vector3(0, 1.63, 0.1), _chrome)
	_box(m, Vector3(0.6, 0.04, 0.06), Vector3(0, 0.87, 0.1), _chrome)
	for x in [-1.0, 1.0]:
		_box(m, Vector3(0.04, 0.8, 0.06), Vector3(x * 0.28, 1.25, 0.1), _chrome)
	_box(m, Vector3(0.5, 0.08, 0.14), Vector3(0, 0.8, 0.2), _chrome)
	for i in 9:
		_add(m, _sphere(0.012), Vector3(-0.16 + i * 0.04, 0.85, 0.22 + (i % 2) * 0.015), _chrome)
	_cyl(m, 0.045, 0.045, 0.05, Vector3(0.2, 0.68, 0.25), _mat(Color(0.1, 0.1, 0.1), 0.4)).rotation_degrees.x = 90.0
	_box(m, Vector3(0.62, 0.16, 0.32), Vector3(0, 1.83, -0.05), _mat(Color(0.9, 0.15, 0.3), 0.3))
	_label(m, "PACHINKO", 64, 0.0014, Color(3.0, 2.8, 2.6), Vector3(0, 1.83, 0.115))
	_bulb_row(m, Vector3(0, 1.93, 0.1), 0.58, 10)
	_stool(m)


## The "Joker Grabber": a glass box full of plush jokers and a claw that keeps trying.
func _claw_machine(m: Node3D) -> void:
	var body := _mat(Color(0.15, 0.35, 0.85), 0.3, 0.2)
	_box(m, Vector3(0.72, 0.85, 0.66), Vector3(0, 0.425, 0), body)
	_box(m, Vector3(0.74, 0.05, 0.68), Vector3(0, 0.875, 0), _chrome)
	# glass box
	var h := 0.85
	for side in [[Vector3(0.7, h, 0.01), Vector3(0, 0.9 + h * 0.5, 0.33)], [Vector3(0.7, h, 0.01), Vector3(0, 0.9 + h * 0.5, -0.33)],
			[Vector3(0.01, h, 0.66), Vector3(0.35, 0.9 + h * 0.5, 0)], [Vector3(0.01, h, 0.66), Vector3(-0.35, 0.9 + h * 0.5, 0)]]:
		var pane := _box(m, side[0], side[1], _glass)
		pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for x in [-1.0, 1.0]:
		for z in [-1.0, 1.0]:
			_box(m, Vector3(0.025, h, 0.025), Vector3(x * 0.35, 0.9 + h * 0.5, z * 0.33), _chrome)
	# prize pile: plush jokers (a body, a head and a two-coloured hat) and coloured balls
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var plush := [Color(0.9, 0.2, 0.2), Color(0.2, 0.45, 0.95), Color(0.95, 0.8, 0.2), Color(0.3, 0.8, 0.4), Color(0.75, 0.3, 0.85)]
	for i in 14:
		var p := Vector3(rng.randf_range(-0.27, 0.27), 0.93 + rng.randf_range(0.0, 0.08), rng.randf_range(-0.25, 0.22))
		var c: Color = plush[i % plush.size()]
		if i % 3 == 0:
			_add(m, _sphere(0.045), p, _mat(c, 0.9))
			continue
		var j := Node3D.new()
		j.position = p
		j.rotation = Vector3(rng.randf_range(-0.6, 0.6), rng.randf() * TAU, rng.randf_range(-0.6, 0.6))
		m.add_child(j)
		_add(j, _sphere(0.04), Vector3.ZERO, _mat(c, 0.9))
		_add(j, _sphere(0.03), Vector3(0, 0.055, 0), _mat(Color(0.98, 0.9, 0.82), 0.9))
		for s in [-1.0, 1.0]:
			var hat := _cyl(j, 0.0, 0.016, 0.05, Vector3(s * 0.022, 0.09, 0), _mat(plush[(i + 1) % plush.size()] if s < 0 else c, 0.9), 8)
			hat.rotation.z = -s * 0.6
	# the claw: a carriage under the roof, a cable and three prongs
	var carriage := Node3D.new()
	carriage.position = Vector3(0, 1.72, 0)
	m.add_child(carriage)
	_box(m, Vector3(0.66, 0.02, 0.02), Vector3(0, 1.73, 0), _chrome)
	_box(carriage, Vector3(0.08, 0.03, 0.08), Vector3.ZERO, _chrome)
	var cable := _cyl(carriage, 0.003, 0.003, 0.1, Vector3(0, -0.05, 0), _chrome, 6)
	var claw := Node3D.new()
	claw.position.y = -0.1
	carriage.add_child(claw)
	_cyl(claw, 0.025, 0.02, 0.04, Vector3.ZERO, _chrome, 12)
	for k in 3:
		var a := TAU * k / 3.0
		var prong := _box(claw, Vector3(0.008, 0.07, 0.008), Vector3(cos(a) * 0.025, -0.04, sin(a) * 0.025), _chrome)
		prong.rotation = Vector3(sin(a) * 0.4, 0, -cos(a) * 0.4)
	_claws.append({"carriage": carriage, "cable": cable, "claw": claw, "phase": rng.randf() * TAU})
	# joystick, button, prize chute
	_cyl(m, 0.008, 0.008, 0.08, Vector3(-0.12, 0.92, 0.3), _chrome)
	_add(m, _sphere(0.022), Vector3(-0.12, 0.97, 0.3), _mat(Color(0.9, 0.1, 0.1), 0.3))
	_cyl(m, 0.03, 0.03, 0.02, Vector3(0.12, 0.89, 0.3), _emissive(Color(1.0, 0.8, 0.2), 1.6), 16)
	_box(m, Vector3(0.2, 0.18, 0.04), Vector3(0.18, 0.35, 0.34), _mat(Color(0.03, 0.03, 0.03), 0.6))
	# roof sign
	_box(m, Vector3(0.74, 0.2, 0.68), Vector3(0, 1.85, 0), body)
	_label(m, "JOKER GRABBER", 64, 0.001, Color(3.0, 2.6, 0.5), Vector3(0, 1.85, 0.345))
	_bulb_row(m, Vector3(0, 1.96, 0.345), 0.7, 12)


## Video poker: a slanted screen with a hand of five cards and HOLD buttons.
func _video_poker(m: Node3D) -> void:
	var body := _mat(Color(0.08, 0.08, 0.1), 0.3, 0.4)
	_box(m, Vector3(0.62, 0.78, 0.5), Vector3(0, 0.39, 0), body)
	_box(m, Vector3(0.64, 0.04, 0.52), Vector3(0, 0.8, 0), _gold)
	for i in 5:
		_box(m, Vector3(0.08, 0.025, 0.05), Vector3(-0.22 + i * 0.11, 0.83, 0.17), _emissive(Color(1.0, 0.9, 0.5), 1.4))
	_box(m, Vector3(0.1, 0.025, 0.05), Vector3(0.0, 0.83, 0.07), _emissive(Color(0.95, 0.2, 0.2), 1.8)) # DEAL
	var head := Node3D.new()
	head.position = Vector3(0, 1.08, -0.02)
	head.rotation_degrees.x = -15.0
	m.add_child(head)
	_box(head, Vector3(0.6, 0.48, 0.3), Vector3(0, 0, -0.08), body)
	_box(head, Vector3(0.54, 0.4, 0.02), Vector3(0, 0, 0.075), _gold)
	var screen := _quad(head, Vector2(0.5, 0.36), Vector3(0, 0, 0.088), _shader_mat(VIDEO_POKER, {}))
	screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_box(m, Vector3(0.62, 0.2, 0.3), Vector3(0, 1.48, -0.1), _mat(Color(0.6, 0.05, 0.1), 0.3))
	_label(m, "BALA-RETRO", 64, 0.0012, Color(3.0, 2.7, 1.2), Vector3(0, 1.51, 0.055))
	_label(m, "VIDEO POKER", 40, 0.0011, Color(1.0, 0.85, 0.5), Vector3(0, 1.43, 0.055))
	_bulb_row(m, Vector3(0, 1.6, 0.05), 0.58, 10)
	_stool(m)


## A big wheel of fortune on the wall that now and then spins – and mostly stops on "NOPE!".
func _wheel_of_fortune(m: Node3D) -> void:
	_box(m, Vector3(0.3, 1.0, 0.3), Vector3(0, 0.5, -0.1), _mat(Color(0.25, 0.05, 0.08), 0.4))
	_box(m, Vector3(0.9, 0.9, 0.06), Vector3(0, 1.55, -0.2), _mat(Color(0.12, 0.04, 0.06), 0.4))
	var wheel := Node3D.new()
	wheel.position = Vector3(0, 1.55, -0.13)
	m.add_child(wheel)
	var disc := _quad(wheel, Vector2(0.86, 0.86), Vector3.ZERO, _shader_mat(WHEEL, {}))
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var words := ["NOPE!", "$1", "NOPE!", "x2", "NOPE!", "NOPE!", "$5", "NOPE!", "NOPE!", "JACKPOT", "NOPE!", "x1.5"]
	for i in words.size():
		var a := TAU * (i + 0.5) / words.size()
		var l := _label(wheel, words[i], 40, 0.0011, Color(0.1, 0.05, 0.05) if words[i] == "NOPE!" else Color(1, 1, 1),
				Vector3(sin(a) * 0.27, cos(a) * 0.27, 0.004))
		l.rotation.z = -a + PI * 0.5
		l.outline_size = 0
	_cyl(wheel, 0.05, 0.05, 0.03, Vector3(0, 0, 0.015), _gold, 24).rotation_degrees.x = 90.0
	_torus(m, 0.43, 0.46, Vector3(0, 1.55, -0.13), _gold).rotation_degrees.x = 90.0
	for i in 16: # light bulbs around the rim
		var a := TAU * i / 16.0
		_add(m, _sphere(0.014), Vector3(sin(a) * 0.445, 1.55 + cos(a) * 0.445, -0.1), _bulbs[i % 2])
	# pointer at the top
	var pointer := _cyl(m, 0.0, 0.035, 0.09, Vector3(0, 2.0, -0.09), _mat(Color(0.9, 0.1, 0.1), 0.3), 3)
	pointer.rotation_degrees.z = 180.0
	_label(m, "WHEEL OF FORTUNE", 64, 0.0011, Color(3.0, 2.4, 0.5), Vector3(0, 2.12, -0.12))
	_label(m, "1 in 4 chance", 32, 0.0009, Color(1.0, 0.8, 0.6), Vector3(0, 0.92, 0.06))
	_wheels.append({"node": wheel, "angle": randf() * TAU, "speed": 0.0, "wait": randf_range(2.0, 10.0)})


## A coin pusher: two shelves of gold coins behind glass, the upper shelf sliding to and fro.
func _coin_pusher(m: Node3D) -> void:
	var body := _mat(Color(0.75, 0.1, 0.45), 0.3, 0.2)
	_box(m, Vector3(0.72, 0.8, 0.62), Vector3(0, 0.4, 0), body)
	_box(m, Vector3(0.72, 0.6, 0.06), Vector3(0, 1.1, -0.28), body)
	_box(m, Vector3(0.64, 0.5, 0.01), Vector3(0, 1.08, -0.245), _emissive(Color(0.9, 0.3, 0.7), 0.5)) # lit back wall
	for x in [-1.0, 1.0]:
		_box(m, Vector3(0.04, 0.6, 0.6), Vector3(x * 0.34, 1.1, 0), body)
	var pane := _box(m, Vector3(0.66, 0.5, 0.01), Vector3(0, 1.05, 0.3), _glass)
	pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var shelf := _mat(Color(0.75, 0.78, 0.82), 0.15, 0.9)
	_box(m, Vector3(0.64, 0.02, 0.5), Vector3(0, 0.83, 0.02), shelf)
	var pusher := Node3D.new()
	pusher.position = Vector3(0, 0.95, -0.12)
	m.add_child(pusher)
	_box(pusher, Vector3(0.64, 0.02, 0.3), Vector3.ZERO, shelf)
	_box(pusher, Vector3(0.64, 0.1, 0.03), Vector3(0, -0.05, 0.15), shelf)
	_pushers.append(pusher)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 46: # coins on the lower shelf, piling up at the edge
		var x := rng.randf_range(-0.29, 0.29)
		var z := rng.randf_range(0.0, 0.25)
		var coin := _cyl(m, 0.022, 0.022, 0.005, Vector3(x, 0.843 + (0.006 if z > 0.15 and i % 2 == 0 else 0.0), z), _gold, 12)
		coin.rotation = Vector3(rng.randf_range(-0.1, 0.1), rng.randf() * TAU, rng.randf_range(-0.1, 0.1))
	for i in 20: # and on the moving shelf
		var coin := _cyl(pusher, 0.022, 0.022, 0.005, Vector3(rng.randf_range(-0.29, 0.29), 0.013, rng.randf_range(-0.12, 0.12)), _gold, 12)
		coin.rotation.y = rng.randf() * TAU
	var drop := _box(m, Vector3(0.34, 0.12, 0.08), Vector3(0, 0.2, 0.33), _chrome) # prize tray
	drop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_box(m, Vector3(0.72, 0.26, 0.62), Vector3(0, 1.53, 0), _mat(Color(0.12, 0.02, 0.1), 0.3))
	_label(m, "COIN PUSHER", 64, 0.0012, Color(3.0, 2.5, 0.5), Vector3(0, 1.55, 0.315))
	_label(m, "interest guaranteed*", 32, 0.0008, Color(1.0, 0.75, 0.9), Vector3(0, 1.45, 0.315))
	_bulb_row(m, Vector3(0, 1.67, 0.315), 0.68, 12)


func _stool(m: Node3D) -> void:
	_cyl(m, 0.18, 0.18, 0.08, Vector3(0, 0.62, 0.65), _leather, 24)
	_cyl(m, 0.03, 0.03, 0.58, Vector3(0, 0.29, 0.65), _gold)
	_cyl(m, 0.2, 0.22, 0.03, Vector3(0, 0.015, 0.65), _gold, 24)


func _bulb_ring(m: Node3D, centre: Vector3, size: Vector2, count: int) -> void:
	var per_side := count / 4
	var i := 0
	for side in 4:
		for k in per_side:
			var t := (k + 0.5) / per_side
			var p: Vector2
			match side:
				0: p = Vector2(-size.x * 0.5 + t * size.x, size.y * 0.5)
				1: p = Vector2(size.x * 0.5, size.y * 0.5 - t * size.y)
				2: p = Vector2(size.x * 0.5 - t * size.x, -size.y * 0.5)
				_: p = Vector2(-size.x * 0.5, -size.y * 0.5 + t * size.y)
			_add(m, _sphere(0.011), centre + Vector3(p.x, p.y, 0), _bulbs[i % 2])
			i += 1


func _bulb_row(m: Node3D, centre: Vector3, width: float, count: int) -> void:
	for i in count:
		_add(m, _sphere(0.011), centre + Vector3(-width * 0.5 + width * (i + 0.5) / count, 0, 0), _bulbs[i % 2])


# ---------------------------------------------------------------- helpers

func _label(parent: Node3D, text: String, size: int, pixel: float, colour: Color, pos: Vector3) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = pixel
	l.modulate = colour
	l.outline_modulate = Color(colour.r * 0.12, colour.g * 0.12, colour.b * 0.12, 1.0)
	l.outline_size = 6
	l.position = pos
	parent.add_child(l)
	return l


func _quad(parent: Node3D, size: Vector2, pos: Vector3, mat: Material) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


static var _shaders := {}

func _shader_mat(code: String, params: Dictionary) -> ShaderMaterial:
	if not _shaders.has(code):
		var s := Shader.new()
		s.code = code
		_shaders[code] = s
	var mat := ShaderMaterial.new()
	mat.shader = _shaders[code]
	for k in params:
		mat.set_shader_parameter(k, params[k])
	if code != WHEEL:
		_screens.append(mat) # its clock runs in _process
	return mat


## The Wheel (boss blind): every machine in the room runs wild – reels, balls, cards and lights
## spin several times as fast, the wheels of fortune never stop.
func set_frenzy(on: bool) -> void:
	_frenzy = on


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return _add(parent, b, pos, mat)


func _cyl(parent: Node3D, top: float, bottom: float, height: float, pos: Vector3, mat: Material, segments := 16) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = height
	c.radial_segments = segments
	c.rings = 1
	return _add(parent, c, pos, mat)


func _torus(parent: Node3D, inner: float, outer: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	t.rings = 48
	t.ring_segments = 8
	return _add(parent, t, pos, mat)


func _sphere(radius: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = 12
	s.rings = 6
	return s


func _add(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _mat(colour: Color, roughness := 0.8, metallic := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = roughness
	m.metallic = metallic
	return m


func _emissive(colour: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.emission_enabled = true
	m.emission = colour
	m.emission_energy_multiplier = energy
	_glows.append({"mat": m, "energy": energy})
	return m


# ---------------------------------------------------------------- shaders

## Slot reels: card suits, sevens and bars rolling by in three reels.
const SLOT_REELS := """
shader_type spatial;
render_mode unshaded;
uniform float clock = 0.0; // driven by the script (runs faster during The Wheel)
uniform float seed = 0.0;
uniform vec3 bg : source_color = vec3(0.97, 0.94, 0.86);

float heart(vec2 p) { p.y = -p.y + 0.05; p.x = abs(p.x); return length(p - vec2(0.1, 0.05)) < 0.13 || (p.y < 0.05 && p.y > -0.25 + p.x * 1.4) ? 1.0 : 0.0; }
float diamond(vec2 p) { return abs(p.x) * 1.4 + abs(p.y) < 0.27 ? 1.0 : 0.0; }
float club(vec2 p) { return length(p - vec2(0.0, 0.1)) < 0.1 || length(p - vec2(0.1, -0.05)) < 0.1 || length(p - vec2(-0.1, -0.05)) < 0.1 || (abs(p.x) < 0.03 && p.y < 0.0 && p.y > -0.25) ? 1.0 : 0.0; }
float seven(vec2 p) { return (p.y > 0.15 && p.y < 0.25 && abs(p.x) < 0.17) || (abs(p.x + p.y * 0.55 - 0.02) < 0.05 && p.y < 0.2 && p.y > -0.25) ? 1.0 : 0.0; }
float bar(vec2 p) { return abs(p.x) < 0.24 && abs(p.y) < 0.09 ? 1.0 : 0.0; }

void fragment() {
	float reel = floor(UV.x * 3.0);
	float x = fract(UV.x * 3.0);
	float speed = 0.22 + 0.1 * reel + 0.02 * seed;
	// each reel spins for a while, then stops for a moment on a symbol
	float t = clock * speed + seed + reel * 0.37;
	float y = UV.y + t;
	float sym = floor(y * 2.5);
	vec2 p = vec2(x - 0.5, -(fract(y * 2.5) - 0.5));
	float h = fract(sin(sym * 12.9898 + reel * 78.233 + seed * 3.1) * 43758.5453);
	vec3 col; float s;
	if (h < 0.2) { col = vec3(0.9, 0.15, 0.2); s = heart(p); }
	else if (h < 0.4) { col = vec3(0.95, 0.45, 0.1); s = diamond(p); }
	else if (h < 0.6) { col = vec3(0.15, 0.25, 0.7); s = club(p); }
	else if (h < 0.8) { col = vec3(0.85, 0.1, 0.1); s = seven(p); }
	else { col = vec3(0.1, 0.1, 0.1); s = bar(p); }
	float sep = step(0.97, x) + step(x, 0.03);
	float shade = 1.0 - 0.35 * pow(abs(UV.y - 0.5) * 2.0, 2.0); // curved reels: darker at top and bottom
	vec3 c = mix(bg, col, s) * shade * (1.0 - sep * 0.85);
	c = mix(c, vec3(0.95, 0.15, 0.15), smoothstep(0.006, 0.0, abs(UV.y - 0.5)) * 0.8); // pay line
	ALBEDO = c * 1.1;
}
"""

## Pachinko play field: pastel background, brass pins, silver balls falling through them.
const PACHINKO := """
shader_type spatial;
render_mode unshaded;
uniform float clock = 0.0; // driven by the script (runs faster during The Wheel)

void fragment() {
	vec2 uv = UV;
	vec3 bg = mix(vec3(0.98, 0.6, 0.75), vec3(0.45, 0.75, 1.0), uv.y);
	bg = mix(bg, vec3(1.0, 0.95, 0.6), smoothstep(0.18, 0.0, length(uv - vec2(0.5, 0.55))) * 0.8); // centre pocket
	vec3 c = bg;
	// brass pins on a staggered grid
	vec2 g = vec2(uv.x * 14.0 + (mod(floor(uv.y * 20.0), 2.0) * 0.5), uv.y * 20.0);
	float pin = smoothstep(0.16, 0.1, length(fract(g) - 0.5));
	c = mix(c, vec3(0.85, 0.65, 0.25), pin);
	// a few balls zig-zagging down
	for (int i = 0; i < 7; i++) {
		float fi = float(i);
		float t = fract(clock * (0.18 + fi * 0.023) + fi * 0.31);
		vec2 b = vec2(0.5 + 0.38 * sin(fi * 2.3 + t * 9.0 + sin(t * 23.0) * 0.4) * (0.4 + 0.6 * t), t);
		float d = length((uv - b) * vec2(1.0, 1.4));
		c = mix(c, vec3(0.92, 0.94, 1.0) * (1.25 - d * 20.0), smoothstep(0.032, 0.024, d));
	}
	// a frame line around the field
	float edge = step(0.98, max(abs(uv.x - 0.5), abs(uv.y - 0.5)) * 2.0);
	ALBEDO = mix(c, vec3(0.85, 0.65, 0.25), edge);
}
"""

## Video poker screen: blue felt, five cards with HOLD tags, a win line.
const VIDEO_POKER := """
shader_type spatial;
render_mode unshaded;
uniform float clock = 0.0; // driven by the script (runs faster during The Wheel)

void fragment() {
	vec2 uv = UV;
	vec3 c = vec3(0.02, 0.06, 0.35);
	float card = floor(uv.x * 5.0);
	vec2 p = vec2(fract(uv.x * 5.0), uv.y);
	bool inside = p.x > 0.08 && p.x < 0.92 && uv.y > 0.25 && uv.y < 0.78;
	if (inside) {
		c = vec3(0.97);
		float h = fract(sin(card * 17.3 + floor(clock * 0.25) * 3.7) * 43758.5);
		vec3 suit = h < 0.5 ? vec3(0.85, 0.1, 0.15) : vec3(0.05);
		float r = length((p - vec2(0.5, 0.52)) * vec2(1.0, 0.75));
		c = mix(c, suit, smoothstep(0.17, 0.14, r));
		c = mix(c, suit, step(abs(p.x - 0.2), 0.06) * step(abs(uv.y - 0.72), 0.03));
	}
	// HOLD tags under some cards, blinking
	float hold = step(0.5, fract(sin(card * 7.1 + floor(clock * 0.25)) * 911.3));
	if (uv.y > 0.8 && uv.y < 0.88 && p.x > 0.15 && p.x < 0.85 && hold > 0.5)
		c = mix(vec3(1.0, 0.85, 0.2), vec3(0.4, 0.3, 0.05), step(0.5, fract(clock * 1.5)));
	// pay line text area at the bottom
	if (uv.y < 0.18) c = vec3(0.9, 0.15, 0.1) * (0.6 + 0.4 * step(0.5, fract(uv.x * 20.0 + clock)));
	ALBEDO = c;
}
"""

## The wheel's face: twelve segments in alternating colours, the NOPE! ones dark.
const WHEEL := """
shader_type spatial;
render_mode unshaded, cull_disabled;

void fragment() {
	vec2 p = UV - 0.5;
	float r = length(p);
	if (r > 0.5) discard;
	float a = atan(p.x, -p.y);
	float seg = floor((a / 6.2831853 + 0.5) * 12.0);
	vec3 cols[4] = { vec3(0.95, 0.85, 0.2), vec3(0.15, 0.45, 0.95), vec3(0.9, 0.2, 0.25), vec3(0.25, 0.75, 0.4) };
	vec3 c = cols[int(mod(seg, 4.0))];
	float edge = smoothstep(0.02, 0.0, fract((a / 6.2831853 + 0.5) * 12.0) * r * 6.0); // gold divider lines
	c = mix(c, vec3(0.9, 0.75, 0.4), edge);
	c *= 0.75 + 0.25 * smoothstep(0.5, 0.2, r);
	ALBEDO = c;
}
"""
