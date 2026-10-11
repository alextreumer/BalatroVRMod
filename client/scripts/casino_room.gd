class_name CasinoRoom
extends Node3D
## Late-night casino for the "virtual room" background (headsets without passthrough, e.g. Quest 2):
## a dark room lit by pink and cyan neon tubes, a green felt card table under the shop and the
## jokers in the pool of light of a pendant lamp, slot machines, side tables, a bar, flickering neon
## signs and a big Balatro-style swirl screen on the back wall.
## Everything is built from code (no external models or textures), so the project stays shareable.
## The card table follows the layout and sits at the height of the Joker Board, so a player who
## calibrated the Joker Board onto a real table also feels the virtual table edge in the right spot.

const ROOM_HALF := Vector2(5.0, 4.5)     # half width (x) / half depth (z) of the room, meters
const ROOM_CENTER_Z := -1.0              # the player stands near the front, looking at -z
const ROOM_HEIGHT := 3.4
const WAINSCOT := 1.0                    # height of the wooden lower wall panels
const TABLE_SIZE := Vector2(2.5, 1.35)   # oval card table: width (x) and depth (z)
const TABLE_CENTER := Vector3(0.1, 0.0, 0.12) # in layout space, horizontal only (y = table height)

const FELT := Color(0.05, 0.32, 0.2)
const LEATHER := Color(0.08, 0.03, 0.03)
const GOLD := Color(0.86, 0.64, 0.26)
const WARM := Color(1.0, 0.82, 0.6)
# neon colours, above 1.0 so the glow makes them shine
const NEON_PINK := Color(3.0, 0.35, 1.7)
const NEON_CYAN := Color(0.3, 2.2, 3.0)
const NEON_PURPLE := Color(1.6, 0.5, 3.0)
const SPECTRAL := Color(0.75, 1.05, 3.4)        # the Spectral Lounge's ghostly blue
const LOUNGE_Z := -0.55                        # centre of its doorway in the right wall (between the slot machines)
const LOUNGE_ARCH := Vector2(1.3, 1.95)        # doorway width, height where the round top starts
const ANTE_ROOM_X := -2.6                      # the Ante Room's doorway in the wall behind the player
const ANTE_DOOR := Vector2(1.1, 2.15)          # its width and height
const KIDS_DOOR_Z := -0.55                     # the Wee Joker Kids Corner's little door in the left wall
const CHIP_MOUNTAIN_POS := Vector3(-0.8, 0.0, -0.05) # layout space: on the left end of the card table
const LAMP_X := 0.2                            # table space: the pendant lamp, right of the chip mountain
const LAMP_WIDTH := 1.2

var _table: Node3D          # the card table (follows the layout)
var _flicker: Label3D       # one neon sign with a loose contact
var _flicker_colour: Color
var _flicker_time := 0.0
var _neon_mats: Array[Dictionary] = []   # every neon tube / ring: {"mat", "base", "energy"}
var _neon_lights: Array[Dictionary] = [] # the coloured lights of the neon: {"light", "base"}
var _mood_ante := 1
var _mood_boss := false
var _mood_heat := 0.0
var _mood_flash := 0.0
var _mood_time := 0.0
var _tension := false               # the last hand: neon dimmed
var calm := false                   # Calm Lights: no flashes or flicker, see set_calm()
const CALM_DIM := 0.45              # how dim the room always is with Calm Lights
var _tension_amount := 0.0
var _room_spots: Array[SpotLight3D] = [] # ceiling spots over the machines (dimmed in the last hand)
var _dimmed_mats: Array = []       # glowing materials of the room: {"mat", "base"}
var _dimmed_signs: Array = []      # neon signs (Label3D): {"label", "base"}
var _dimmed_lights: Array = []     # side room lights: {"light", "base"}
var _dim_applied := -1.0
var _dimmed_shafts: Array = []     # light cones of the ceiling spots and wall lamps: {"mat", "base"}
var _swirl_mat: ShaderMaterial    # the big screen on the far wall
var _machines: CasinoMachines
var ambience: CasinoAmbience       # the room's sounds
var _boss_room: BossRoom           # what each boss blind does to the room
var _boss_tint := Color(3.2, 0.25, 0.2)
var _boss_size := 1.0              # The Wall: < 1, the room closes in
var _boss_dark := 0.0              # The Needle / The Flint: how dark
var _table_base: Node3D     # its foot plate on the floor
var _ghost_cards: Array[Dictionary] = [] # floating cards in the Spectral Lounge: {"node", "base", "phase"}
var _spectral_letters: Array[Label3D] = [] # "SPECTRAL LOUNGE" over the arch
var _spectral_time := 0.0                  # > 0: the sign flickers like a ghost (a Spectral card was bought)
var _clock_hour: Node3D                    # the Ante clock's hands
var _clock_minute: Node3D
var _clock_label: Label3D
var _clock_target := Vector2.ZERO          # hour / minute hand angles to turn to
var _now_serving: Label3D                  # "ANTE 3" in the Ante Room
var _hall_fame: Array[Label3D] = []        # [names, values]
var _hall_shame: Array[Label3D] = []
var _last_stats := {}
var _chip_mountain: ChipMountain
var _sconces: Array[Node3D] = []
var _run_chips := 0.0
var _wood: StandardMaterial3D
var _gold: StandardMaterial3D
var _felt: StandardMaterial3D
var _leather: StandardMaterial3D


func _ready() -> void:
	_wood = _textured(_wood_texture(), 1.2, 0.55)
	_gold = _mat(GOLD, 0.35, 0.6)
	_gold.emission_enabled = true # stays golden even in dim corners
	_gold.emission = GOLD * 0.1
	_felt = _textured(_felt_texture(), 3.0, 0.95)
	_leather = _mat(LEATHER, 0.45)

	_build_floor_and_ceiling()
	_build_walls()
	_build_card_table()
	_build_back_wall_show()
	# a different machine in every spot along the side walls (back to front)
	var machines := CasinoMachines.new()
	_machines = machines
	add_child(machines)
	var left := ["lucky_cat", "pachinko", "jimbo", "video_poker", "claw"]
	var right := ["wheel", "cavendish", "bloodstone", "golden_ticket", "pusher"]
	var spots := [-4.1, -3.1, -2.1, 1.0, 2.0]
	for i in spots.size():
		var z: float = ROOM_CENTER_Z + spots[i] + 1.0
		machines.add_machine(left[i], Vector3(-ROOM_HALF.x + 0.45, 0, z), 90.0)
		machines.add_machine(right[i], Vector3(ROOM_HALF.x - 0.45, 0, z), -90.0)
	_side_table(Vector3(-2.7, 0, -3.9))
	_side_table(Vector3(2.7, 0, -3.9))
	_side_table(Vector3(-2.9, 0, 1.9))
	_side_table(Vector3(2.9, 0, 1.9))
	for x in [-ROOM_HALF.x + 0.6, ROOM_HALF.x - 0.6]:
		for z in [ROOM_CENTER_Z - ROOM_HALF.y + 0.6, ROOM_CENTER_Z + ROOM_HALF.y - 0.6]:
			_column(Vector3(x, 0, z))
	_build_sconces()
	_build_bar()
	_build_restroom_door()
	_build_neon_lights()
	_build_haze()
	_boss_room = BossRoom.new()
	_boss_room.room = self
	add_child(_boss_room)
	# the sound of the room: slot machines paying out, glasses
	ambience = CasinoAmbience.new()
	add_child(ambience)
	for z in [-4.1, -3.1, -2.1, 1.0, 2.0]:
		for x in [-ROOM_HALF.x + 0.45, ROOM_HALF.x - 0.45]:
			ambience.machines.append(Vector3(x, 0, ROOM_CENTER_Z + z + 1.0))


## The neon follows the game: each ante tints it a step further around the colour wheel, a boss
## blind turns it into a slow red alarm pulse, and a burning score makes it flare and flicker.
## `pulse()` flashes it once (a big hand scoring).
func set_mood(ante: int, boss: bool, heat: float) -> void:
	_mood_ante = ante
	_mood_boss = boss
	_mood_heat = heat


func set_heat(heat: float) -> void:
	_mood_heat = heat


func pulse(strength := 1.0) -> void:
	if calm:
		return
	_mood_flash = maxf(_mood_flash, strength)


## "Calm Lights" (for photosensitive players): no flashes, flicker or pulsing; the room stays dim.
func set_calm(on: bool) -> void:
	calm = on
	_mood_flash = 0.0
	if on:
		_spectral_time = 0.0
	if _machines != null:
		_machines.calm = on
	if _boss_room != null:
		_boss_room.apply(_boss_room._key, on) # (bubbles, waves, racing machines off or on)


## The run is won: every slot machine hits the jackpot, bells and coins all around.
func jackpot() -> void:
	if _machines != null:
		_machines.jackpot(6.0)
	ambience.jackpot()
	pulse(2.0)


## The boss blind being played ("" outside a boss round): the room takes the colour of its chip
## (instead of plain red; Calm Lights keeps the normal colours) and changes with it (BossRoom).
func set_boss(key: String, colour: Color) -> void:
	var peak := maxf(colour.r, maxf(colour.g, colour.b))
	if peak > 0.01: # bright HDR neon in the chip's hue
		var hue := Color(colour.r / peak, colour.g / peak, colour.b / peak)
		_boss_tint = Color.from_hsv(hue.h, maxf(hue.s, 0.92), 1.0) * 3.2 # saturated: no washing out to white
		if hue.s < 0.15: # a grey chip (The Manacle) has no colour: cold steel light
			_boss_tint = Color(1.5, 1.7, 2.2)
	_boss_room.apply(key, calm)


## Called by BossRoom: room size (The Wall), darkness (The Needle, The Flint), racing machines (The Wheel).
func set_boss_effects(size: float, dark: float, frenzy: bool) -> void:
	_boss_size = size
	_boss_dark = dark
	if _machines != null:
		_machines.set_frenzy(frenzy)


## The last hand of a round that isn't won yet: the room holds its breath.
func set_tension(on: bool) -> void:
	_tension = on


## How dark the room is right now (0 normal .. 1 the last hand), for main.gd's ambient light.
func tension_amount() -> float:
	return _tension_amount


## Darkens everything that glows in the room – signs, lamps, bottles, machines, side rooms, light
## cones – by the tension (only the table lamp stays). Only when it changed.
func _apply_dim() -> void:
	if is_equal_approx(_dim_applied, _tension_amount):
		return
	_dim_applied = _tension_amount
	var f := 1.0 - 0.9 * _tension_amount
	for d in _dimmed_mats:
		var b: Color = d["base"]
		(d["mat"] as StandardMaterial3D).albedo_color = Color(b.r * f, b.g * f, b.b * f, b.a)
	for d in _dimmed_signs:
		var label: Label3D = d["label"]
		if label == _flicker:
			continue # it sets its own colour every frame (with the same dimming)
		var b: Color = d["base"]
		label.modulate = Color(b.r * f, b.g * f, b.b * f, label.modulate.a)
	for d in _dimmed_lights:
		(d["light"] as Light3D).light_energy = float(d["base"]) * f
	for d in _dimmed_shafts:
		(d["mat"] as ShaderMaterial).set_shader_parameter("strength", float(d["base"]) * (1.0 - 0.95 * _tension_amount))
	if _machines != null:
		_machines.set_dim(f)
	if _swirl_mat != null:
		_swirl_mat.set_shader_parameter("brightness", 0.75 * (1.0 - 0.85 * _tension_amount))


func _neon_mat(colour: Color, energy: float) -> StandardMaterial3D:
	var m := _emissive(colour, energy, false) # (dimmed with the rest of the neon in _update_mood)
	_neon_mats.append({"mat": m, "base": colour, "energy": energy})
	return m


## `c` (bright HDR neon colour) turned `shift` around the colour wheel, same brightness.
static func _hue_shift(c: Color, shift: float) -> Color:
	var peak := maxf(c.r, maxf(c.g, c.b))
	var n := Color(c.r / peak, c.g / peak, c.b / peak)
	var shifted := Color.from_hsv(fposmod(n.h + shift, 1.0), n.s, n.v)
	return Color(shifted.r * peak, shifted.g * peak, shifted.b * peak)


func _update_mood(delta: float) -> void:
	_mood_time += delta
	_mood_flash = maxf(_mood_flash - delta * 2.5, 0.0)
	var shift := (maxi(_mood_ante, 1) - 1) * 0.09
	# a boss round tints the room in the colour of its chip, pulsing slowly (Calm Lights: normal colours)
	var tinted := _mood_boss and not calm
	var alarm := 0.5 + 0.5 * sin(_mood_time * 2.6) if tinted else 0.0
	var flicker := 1.0
	if _mood_heat > 0.05 and not calm: # a burning score makes the tubes flare and stutter
		flicker = 1.0 + _mood_heat * (0.45 + 0.35 * sin(_mood_time * 37.0) * sin(_mood_time * 23.0))
	# the last hand: the neon sinks to a glimmer (the table lamp stays), a flash when it's beaten
	# calm: the room always stays dim and never jumps back to bright
	var rest := CALM_DIM if calm else 0.0
	var target := maxf(1.0 if _tension else rest, _boss_dark) # The Needle / The Flint darken it too
	_tension_amount = move_toward(_tension_amount, target, delta * (0.8 if _tension or calm or _boss_dark > 0.0 else 4.0))
	# The Wall: the room closes in (the table is placed again every frame, it stays where it is)
	var sz := move_toward(scale.x, _boss_size, delta * 0.12)
	scale = Vector3(sz, 1.0, sz)
	var dim := 1.0 - 0.93 * _tension_amount
	var boost := (flicker + _mood_flash * 1.5) * dim
	for s in _room_spots:
		s.light_energy = 1.6 * (1.0 - 0.95 * _tension_amount)
	_apply_dim()
	for n in _neon_mats:
		var c := _hue_shift(n["base"], shift)
		if tinted:
			c = c.lerp(_boss_tint, 0.75) * (0.55 + 0.6 * alarm)
		var e: float = n["energy"] * boost
		(n["mat"] as StandardMaterial3D).albedo_color = Color(c.r * e, c.g * e, c.b * e)
	for l in _neon_lights:
		var c := _hue_shift(l["base"], shift)
		if tinted:
			c = c.lerp(_boss_tint, 0.75)
		var light: OmniLight3D = l["light"]
		light.light_color = Color(c.r, c.g, c.b).clamp()
		light.light_energy = 1.4 * boost * (0.6 + 0.6 * alarm if tinted else 1.0)


func _process(delta: float) -> void:
	if not visible or _flicker == null:
		return
	_update_mood(delta)
	# a neon sign with a loose contact: mostly on, now and then a short burst of flickering
	_flicker_time += delta
	# every 35 s: three short flickers, then the letters jumble to "NOPE 24/7" for 10 s
	var loop := fmod(_flicker_time, 35.0)
	var cycle := fmod(loop, 7.0)
	var on := true
	var text := "OPEN 24/7"
	if loop >= 21.0:
		var flick := (loop < 21.6) or (loop > 31.5 and loop < 32.1)
		on = not flick or sin(loop * 53.0) + sin(loop * 31.0) > -0.2
		if loop > 21.4 and loop < 31.7:
			text = "NOPE 24/7"
	elif cycle > 5.6:
		on = sin(cycle * 53.0) + sin(cycle * 31.0) > -0.2
	if calm:
		on = true # no flicker; the letters still swap now and then
	if _flicker.text != text:
		_flicker.text = text
	_flicker.modulate = (_flicker_colour if on else _flicker_colour * 0.12) * (1.0 - 0.9 * _tension_amount)
	_flicker.modulate.a = 1.0
	_update_spectral_sign(delta)
	_update_clock(delta)
	var whirl := 1.0 + 4.0 * clampf(_spectral_time, 0.0, 1.0) # the ghost cards whirl while the sign haunts
	for g in _ghost_cards: # the spectral cards drift and turn slowly
		g["spin"] = float(g.get("spin", 0.0)) + delta * 0.6 * whirl
		var t: float = g["spin"] + g["phase"]
		var card: Node3D = g["node"]
		card.position = g["base"] + Vector3(0.05 * sin(t * 0.7), 0.08 * sin(t), 0.05 * cos(t * 0.5))
		card.rotation = Vector3(0.2 * sin(t * 0.8), t * 0.4, 0.15 * cos(t))


## Put the card table under the layout (shop, jokers): turned with it, top at `table_y`.
func place_table(layout: Transform3D, table_y: float) -> void:
	var yaw := Basis(Vector3.UP, layout.basis.get_euler().y)
	var origin := layout.origin + yaw * TABLE_CENTER
	origin.y = table_y
	_table.global_transform = Transform3D(yaw, origin)
	_table_base.global_position = Vector3(origin.x, 0.0, origin.z)
	_table_base.global_basis = yaw
	if _chip_mountain == null: # built once the table height is known (it reaches up to the ceiling)
		_chip_mountain = ChipMountain.new()
		_chip_mountain.ceiling = ROOM_HEIGHT - table_y - 0.05
		_chip_mountain.position = CHIP_MOUNTAIN_POS - TABLE_CENTER
		_table.add_child(_chip_mountain)
		_chip_mountain.set_total(_run_chips)
	_chip_mountain.ceiling = ROOM_HEIGHT - table_y - 0.05


## Every chip scored in this run: the chip mountain on the left of the table.
func set_run_chips(total: float) -> void:
	_run_chips = total
	if _chip_mountain != null:
		_chip_mountain.set_total(total)


# ---------------------------------------------------------------- room shell

func _build_floor_and_ceiling() -> void:
	var size := Vector3(ROOM_HALF.x * 2.0, 0.02, ROOM_HALF.y * 2.0)
	_box(self, size, Vector3(0, -0.01, ROOM_CENTER_Z), _textured(_carpet_texture(), 0.7, 0.95))
	var ceiling := _mat(Color(0.015, 0.012, 0.02), 0.9)
	_box(self, size, Vector3(0, ROOM_HEIGHT + 0.01, ROOM_CENTER_Z), ceiling)
	# coffered ceiling: a dark grid with a few purple neon lines
	var beam := _mat(Color(0.04, 0.03, 0.05), 0.6)
	for i in range(-4, 5):
		_box(self, Vector3(0.05, 0.04, size.z), Vector3(i * 1.1, ROOM_HEIGHT - 0.02, ROOM_CENTER_Z), _neon_mat(NEON_PURPLE, 0.5) if abs(i) == 2 else beam)
	for i in range(-4, 5):
		_box(self, Vector3(size.x, 0.04, 0.05), Vector3(0, ROOM_HEIGHT - 0.02, ROOM_CENTER_Z + i * 1.0), beam)


func _build_walls() -> void:
	var paper := _textured(_wallpaper_texture(), 1.4, 0.9)
	var back := ROOM_CENTER_Z - ROOM_HALF.y
	var front := ROOM_CENTER_Z + ROOM_HALF.y
	var back_wall := _wall(Vector3(0, 0, back), ROOM_HALF.x * 2.0, 0.0, paper)
	_build_halls(back_wall)
	# behind the player, left of the bar: the open doorway to the Ante Room (local x = -world x)
	var ante := Vector3(-ANTE_ROOM_X, ANTE_DOOR.x, ANTE_DOOR.y)
	var front_wall := _wall(Vector3(0, 0, front), ROOM_HALF.x * 2.0, 180.0, paper, ante, false)
	_build_ante_room(front_wall, ante)
	_wall(Vector3(-ROOM_HALF.x, 0, ROOM_CENTER_Z), ROOM_HALF.y * 2.0, 90.0, paper)
	_build_kids_door()
	# the right wall has the round-arched opening to the Spectral Lounge (between the slot machines)
	var arch := Vector3(LOUNGE_Z - ROOM_CENTER_Z, LOUNGE_ARCH.x, LOUNGE_ARCH.y)
	var right := _wall(Vector3(ROOM_HALF.x, 0, ROOM_CENTER_Z), ROOM_HALF.y * 2.0, -90.0, paper, arch)
	_build_spectral_lounge(right, arch)


## One wall; local +z points into the room. `arch` (x = centre along the wall, y = width,
## z = height where the round top starts) cuts an open doorway with a semicircular top.
func _wall(base: Vector3, length: float, yaw: float, paper: Material, arch := Vector3.ZERO, round_top := true) -> Node3D:
	var w := Node3D.new()
	w.position = base
	w.rotation_degrees.y = yaw
	add_child(w)
	if arch.y > 0.0:
		var shell := CSGBox3D.new()
		shell.size = Vector3(length, ROOM_HEIGHT, 0.1)
		shell.position = Vector3(0, ROOM_HEIGHT * 0.5, -0.05)
		shell.material = paper
		w.add_child(shell)
		var cut := CSGBox3D.new()
		cut.operation = CSGShape3D.OPERATION_SUBTRACTION
		cut.size = Vector3(arch.y, arch.z + 0.02, 0.4)
		cut.position = Vector3(arch.x, (arch.z - 0.02) * 0.5 - ROOM_HEIGHT * 0.5, 0)
		shell.add_child(cut)
		if round_top:
			var round := CSGCylinder3D.new()
			round.operation = CSGShape3D.OPERATION_SUBTRACTION
			round.radius = arch.y * 0.5
			round.height = 0.4
			round.sides = 40
			round.rotation_degrees.x = 90.0
			round.position = Vector3(arch.x, arch.z - ROOM_HEIGHT * 0.5, 0)
			shell.add_child(round)
	else:
		_box(w, Vector3(length, ROOM_HEIGHT, 0.1), Vector3(0, ROOM_HEIGHT * 0.5, -0.05), paper)
	_wall_strip(w, length, arch, Vector3(0, WAINSCOT, 0.03), Vector3(0, WAINSCOT * 0.5, 0.015), _wood)
	# raised panels on the wainscot (not in the doorway)
	var count := int(length / 1.1)
	for i in count:
		var x := (i - (count - 1) * 0.5) * (length / count)
		var half := (length / count - 0.25) * 0.5
		if arch.y > 0.0 and x + half > arch.x - arch.y * 0.5 - 0.1 and x - half < arch.x + arch.y * 0.5 + 0.1:
			continue
		_box(w, Vector3(half * 2.0, WAINSCOT - 0.35, 0.02), Vector3(x, WAINSCOT * 0.5 + 0.03, 0.035), _wood)
	_wall_strip(w, length, arch, Vector3(0, 0.05, 0.05), Vector3(0, WAINSCOT, 0.03), _gold)     # chair rail
	_wall_strip(w, length, arch, Vector3(0, 0.12, 0.045), Vector3(0, 0.06, 0.02), _gold)        # baseboard
	_box(w, Vector3(length, 0.1, 0.08), Vector3(0, ROOM_HEIGHT - 0.05, 0.04), _gold) # crown
	# neon tubes: pink under the ceiling, cyan just above the floor
	_box(w, Vector3(length, 0.025, 0.025), Vector3(0, ROOM_HEIGHT - 0.22, 0.05), _neon_mat(NEON_PINK, 1.0))
	_wall_strip(w, length, arch, Vector3(0, 0.02, 0.02), Vector3(0, 0.16, 0.055), _neon_mat(NEON_CYAN, 1.0))
	return w


## A strip along the whole wall (size.x is ignored), left out where the doorway is.
func _wall_strip(w: Node3D, length: float, arch: Vector3, size: Vector3, pos: Vector3, mat: Material) -> void:
	if arch.y <= 0.0:
		_box(w, Vector3(length, size.y, size.z), pos, mat)
		return
	var gap_from := arch.x - arch.y * 0.5 - 0.08 # the gold frame covers the ends
	var gap_to := arch.x + arch.y * 0.5 + 0.08
	for part in [[-length * 0.5, gap_from], [gap_to, length * 0.5]]:
		var a: float = part[0]
		var b: float = part[1]
		_box(w, Vector3(b - a, size.y, size.z), Vector3((a + b) * 0.5, pos.y, pos.z), mat)


## Behind the round arch in the right wall: a small, dim lounge in ghostly blue and violet, with
## a velvet sofa, crystal balls and spectral cards floating in the air. "SPECTRAL LOUNGE" is
## written in neon letters along the arch.
func _build_spectral_lounge(w: Node3D, arch: Vector3) -> void:
	var cx := arch.x
	var r := arch.y * 0.5
	# gold frame: two posts and the arch made of short pieces
	for side in [-1.0, 1.0]:
		_box(w, Vector3(0.08, arch.z, 0.14), Vector3(cx + side * (r + 0.04), arch.z * 0.5, 0.0), _gold)
	var pieces := 20
	for i in pieces:
		var a := PI * (i + 0.5) / pieces
		var seg := _box(w, Vector3(PI * (r + 0.04) / pieces * 1.15, 0.08, 0.14),
				Vector3(cx + cos(a) * (r + 0.04), arch.z + sin(a) * (r + 0.04), 0.0), _gold)
		seg.rotation.z = a - PI * 0.5
	# the room behind (local -z is outside the casino)
	var depth := 2.6
	var width := 3.2
	var height := 3.0
	var velvet := _mat(Color(0.1, 0.05, 0.18), 0.85)
	var floor_mat := _mat(Color(0.06, 0.03, 0.1), 0.9)
	_box(w, Vector3(width, 0.02, depth), Vector3(cx, -0.01, -0.1 - depth * 0.5), floor_mat)
	_box(w, Vector3(width, 0.02, depth), Vector3(cx, height, -0.1 - depth * 0.5), _mat(Color(0.02, 0.01, 0.04), 0.9))
	_box(w, Vector3(width, height, 0.05), Vector3(cx, height * 0.5, -0.1 - depth), velvet)
	for side in [-1.0, 1.0]:
		_box(w, Vector3(0.05, height, depth), Vector3(cx + side * width * 0.5, height * 0.5, -0.1 - depth * 0.5), velvet)
	# glowing violet tube along the lounge's ceiling edge and a round carpet
	_box(w, Vector3(width, 0.025, 0.025), Vector3(cx, height - 0.15, -0.1 - depth + 0.05), _neon_mat(SPECTRAL, 0.8))
	var rug := _cyl(w, 0.9, 0.9, 0.01, Vector3(cx, 0.005, -1.4), _mat(Color(0.2, 0.08, 0.32), 0.95), 40)
	rug.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# velvet sofa along the back wall
	var sofa := _mat(Color(0.32, 0.1, 0.45), 0.55)
	_box(w, Vector3(2.0, 0.42, 0.7), Vector3(cx, 0.21, -0.1 - depth + 0.4), sofa)
	_box(w, Vector3(2.0, 0.55, 0.18), Vector3(cx, 0.65, -0.1 - depth + 0.14), sofa)
	for side in [-1.0, 1.0]:
		_box(w, Vector3(0.18, 0.62, 0.7), Vector3(cx + side * 1.0, 0.31, -0.1 - depth + 0.4), sofa)
	# two little tables, each with a glowing crystal ball
	for side in [-1.0, 1.0]:
		var at := Vector3(cx + side * 0.75, 0, -1.3)
		_cyl(w, 0.22, 0.22, 0.03, at + Vector3(0, 0.55, 0), _mat(Color(0.05, 0.03, 0.06), 0.3, 0.4), 24)
		_cyl(w, 0.03, 0.03, 0.55, at + Vector3(0, 0.275, 0), _gold)
		_add(w, _sphere(0.09), at + Vector3(0, 0.66, 0), _emissive(Color(0.55, 0.75, 1.0), 1.6))
	# spectral cards floating in the air
	var card_mat := StandardMaterial3D.new()
	card_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	card_mat.albedo_color = Color(0.6, 0.8, 1.0, 0.55)
	card_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	card_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i in 7:
		var card := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(0.18, 0.25)
		card.mesh = quad
		card.material_override = card_mat
		card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		card.position = Vector3(cx - 1.1 + i * 0.37, 1.3 + 0.35 * sin(i * 2.1), -0.7 - 1.5 * fmod(i * 0.37, 1.0))
		w.add_child(card)
		_ghost_cards.append({"node": card, "base": card.position, "phase": i * 1.3})
	var light := OmniLight3D.new()
	light.light_color = Color(0.55, 0.45, 1.0)
	light.light_energy = 2.2
	_dimmed_lights.append({"light": light, "base": 2.2})
	light.omni_range = 3.2
	light.position = Vector3(cx, 2.2, -1.4)
	w.add_child(light)
	# "SPECTRAL LOUNGE" letter by letter along the arch
	var text := "SPECTRAL LOUNGE"
	var radius := r + 0.3
	for i in text.length():
		if text[i] == " ":
			continue
		var a := deg_to_rad(165.0 - 150.0 * i / (text.length() - 1))
		var letter := _neon(text[i], Vector3.ZERO, 0.0, SPECTRAL, 0.0026)
		letter.reparent(w, false)
		letter.position = Vector3(cx + cos(a) * radius, arch.z + sin(a) * radius, 0.09)
		letter.rotation = Vector3(0, 0, a - PI * 0.5)
		letter.set_meta("base", letter.position)
		_spectral_letters.append(letter)


func _column(pos: Vector3) -> void:
	_cyl(self, 0.22, 0.22, ROOM_HEIGHT, pos + Vector3(0, ROOM_HEIGHT * 0.5, 0), _mat(Color(0.03, 0.02, 0.03), 0.4))
	for y in [0.08, ROOM_HEIGHT - 0.12]:
		_cyl(self, 0.26, 0.26, 0.08, pos + Vector3(0, y, 0), _gold)
	for y in [1.2, 2.2]: # glowing neon rings around the column
		_cyl(self, 0.235, 0.235, 0.025, pos + Vector3(0, y, 0), _neon_mat(NEON_PURPLE if y < 2.0 else NEON_CYAN, 1.0))


func _build_sconces() -> void:
	var spots := [
		[Vector3(-ROOM_HALF.x + 0.05, 2.1, ROOM_CENTER_Z - 1.45), 90.0],
		[Vector3(-ROOM_HALF.x + 0.05, 2.1, ROOM_CENTER_Z + 1.6), 90.0],
		[Vector3(ROOM_HALF.x - 0.05, 2.1, ROOM_CENTER_Z - 1.45), -90.0], # right wall: clear of the lounge arch
		[Vector3(ROOM_HALF.x - 0.05, 2.1, ROOM_CENTER_Z + 2.0), -90.0],
		[Vector3(-3.4, 2.1, ROOM_CENTER_Z + ROOM_HALF.y - 0.05), 180.0],
		[Vector3(3.4, 2.1, ROOM_CENTER_Z + ROOM_HALF.y - 0.05), 180.0],
	]
	var glow := _emissive(WARM, 0.9) # dimmed late at night; the neon does the lighting
	for s in spots:
		var n := Node3D.new()
		n.position = s[0]
		n.rotation_degrees.y = s[1]
		add_child(n)
		_sconces.append(n)
		_box(n, Vector3(0.12, 0.2, 0.05), Vector3(0, 0, 0.02), _gold)
		var bulb := _cyl(n, 0.07, 0.04, 0.16, Vector3(0, 0.12, 0.12), glow)
		bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Smoky air: visible cones of light under the table lamp and the ceiling spots over the machines,
## soft fans of light above the wall lamps and dust drifting in the table lamp's beam. (The
## Compatibility renderer has no volumetric fog, so the beams are soft additive shapes; the room's
## depth fog is set in main.gd.)
func _build_haze() -> void:
	# the table lamp: a wide, flat beam down onto the felt (in table space, it moves with the table)
	var beam := _light_shaft(_table, Vector3(LAMP_X, 1.42, -0.1), 0.5, 0.82, 1.42, WARM, 0.14)
	beam.scale.z = 0.42
	var dust := CPUParticles3D.new()
	dust.amount = 90
	dust.lifetime = 9.0
	dust.preprocess = 9.0
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	dust.emission_box_extents = Vector3(0.6, 0.6, 0.25)
	dust.direction = Vector3(0.3, 1, 0)
	dust.spread = 180.0
	dust.gravity = Vector3(0, -0.004, 0)
	dust.initial_velocity_min = 0.005
	dust.initial_velocity_max = 0.02
	dust.scale_amount_min = 0.5
	dust.scale_amount_max = 1.2
	var mote := QuadMesh.new()
	mote.size = Vector2(0.004, 0.004)
	var mote_mat := StandardMaterial3D.new()
	mote_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mote_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mote_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mote_mat.albedo_color = Color(1.0, 0.85, 0.6, 0.35)
	mote_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mote.material = mote_mat
	dust.mesh = mote
	dust.position = Vector3(LAMP_X, 0.75, -0.1)
	_table.add_child(dust)
	# ceiling spots over the machines along the side walls: real light and a visible cone
	for x in [-ROOM_HALF.x + 0.7, ROOM_HALF.x - 0.7]:
		for z in [ROOM_CENTER_Z - 2.1, ROOM_CENTER_Z + 1.5]:
			var top := Vector3(x, ROOM_HEIGHT - 0.05, z)
			_cyl(self, 0.09, 0.11, 0.06, top + Vector3(0, -0.01, 0), _mat(Color(0.05, 0.05, 0.06), 0.3, 0.6), 16)
			var lens := _cyl(self, 0.07, 0.07, 0.01, top + Vector3(0, -0.045, 0), _emissive(WARM, 2.0), 16)
			lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var shaft := _light_shaft(self, top + Vector3(0, -0.05, 0), 0.08, 0.75, ROOM_HEIGHT - 0.1, WARM, 0.16)
			_dimmed_shafts.append({"mat": shaft.material_override, "base": 0.16})
			var spot := SpotLight3D.new()
			spot.light_color = WARM
			spot.light_energy = 1.6
			_room_spots.append(spot)
			spot.spot_range = ROOM_HEIGHT + 0.5
			spot.spot_angle = 20.0
			spot.position = top + Vector3(0, -0.06, 0)
			spot.rotation_degrees.x = -90.0
			add_child(spot)
	# the wall lamps throw a soft fan of light up the wall
	for n in _sconces:
		# narrow end down at the bulb, wide end up the wall, flat against it
		var fan := _light_shaft(n, Vector3(0, 0.75, 0.1), 0.32, 0.06, 0.6, WARM, 0.18)
		_dimmed_shafts.append({"mat": fan.material_override, "base": 0.18})
		fan.scale.z = 0.35
		(fan.material_override as ShaderMaterial).set_shader_parameter("upward", true)


## A visible beam of light in hazy air: a soft cone (top radius r_top at `top`, bottom radius
## r_bottom, `height` long, pointing down). Additive, brightest in the middle, fading at its rim
## and towards its end, with a slow drift of smoke in it.
func _light_shaft(parent: Node3D, top: Vector3, r_top: float, r_bottom: float, height: float, colour: Color, strength: float) -> MeshInstance3D:
	var cone := CylinderMesh.new()
	cone.top_radius = r_top
	cone.bottom_radius = r_bottom
	cone.height = height
	cone.radial_segments = 32
	cone.rings = 4
	cone.cap_top = false
	cone.cap_bottom = false
	var mat := ShaderMaterial.new()
	mat.shader = _shader(SHAFT_SHADER)
	mat.set_shader_parameter("colour", colour)
	mat.set_shader_parameter("strength", strength)
	var mi := _add(parent, cone, top - Vector3(0, height * 0.5, 0), mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Coloured light from the neon tubes, so walls, floor and furniture pick up pink and cyan.
func _build_neon_lights() -> void:
	var back := ROOM_CENTER_Z - ROOM_HALF.y
	var front := ROOM_CENTER_Z + ROOM_HALF.y
	var lights := [
		[Vector3(-ROOM_HALF.x + 0.6, 2.6, ROOM_CENTER_Z - 1.5), NEON_PINK],
		[Vector3(ROOM_HALF.x - 0.6, 2.6, ROOM_CENTER_Z - 1.5), NEON_PINK],
		[Vector3(-ROOM_HALF.x + 0.6, 0.4, ROOM_CENTER_Z + 1.2), NEON_CYAN],
		[Vector3(ROOM_HALF.x - 0.6, 0.4, ROOM_CENTER_Z + 1.2), NEON_CYAN],
		[Vector3(0, 2.4, back + 0.8), NEON_PURPLE],
		[Vector3(0, 2.4, front - 0.8), NEON_PINK],
	]
	for l in lights:
		var c: Color = l[1]
		var light := OmniLight3D.new()
		light.light_color = Color(c.r, c.g, c.b).clamp() # the light's hue; the strength is energy
		light.light_energy = 1.4
		light.omni_range = 4.5
		light.omni_attenuation = 1.4
		light.position = l[0]
		add_child(light)
		_neon_lights.append({"light": light, "base": c})


# ---------------------------------------------------------------- the card table

func _build_card_table() -> void:
	_table = Node3D.new()
	_table.name = "CardTable"
	add_child(_table)
	var oval := Vector3(TABLE_SIZE.x, 1.0, TABLE_SIZE.y)
	# felt top: its surface lies just below the table height, so shop and jokers sit on it
	var felt := _cyl(_table, 0.49, 0.49, 0.03, Vector3(0, -0.017, 0), _felt, 64)
	felt.scale = oval
	# printed gold line on the felt
	var line := _torus(_table, 0.395, 0.405, Vector3(0, -0.0015, 0), _gold)
	line.scale = Vector3(TABLE_SIZE.x, 0.05, TABLE_SIZE.y)
	# padded leather rail around the edge
	var rail := _torus(_table, 0.465, 0.53, Vector3(0, 0.0, 0), _leather)
	rail.scale = Vector3(TABLE_SIZE.x, 0.9, TABLE_SIZE.y)
	# wooden apron, gold trim, and a strong central leg
	var apron := _cyl(_table, 0.5, 0.47, 0.12, Vector3(0, -0.09, 0), _wood, 64)
	apron.scale = oval
	var trim := _torus(_table, 0.49, 0.505, Vector3(0, -0.15, 0), _neon_mat(NEON_CYAN, 0.8)) # neon under-glow
	trim.scale = Vector3(TABLE_SIZE.x, 0.4, TABLE_SIZE.y)
	_cyl(_table, 0.14, 0.1, 1.2, Vector3(0, -0.75, 0), _wood) # long enough for any table height; the floor hides the rest
	_table_base = Node3D.new()
	add_child(_table_base)
	var foot := _cyl(_table_base, 0.45, 0.5, 0.06, Vector3(0, 0.03, 0), _wood, 48)
	foot.scale = Vector3(1.6, 1.0, 1.0)
	_torus(_table_base, 0.44, 0.47, Vector3(0, 0.06, 0), _neon_mat(NEON_PINK, 0.8)).scale = Vector3(1.6, 0.4, 1.0)

	# pendant lamp above the table: it lights the jokers on the table (shifted right, so the chip
	# mountain on the left end can grow up to the ceiling past it)
	var lamp_x := LAMP_X
	var shade := _mat(Color(0.02, 0.02, 0.025), 0.3)
	_box(_table, Vector3(LAMP_WIDTH, 0.08, 0.32), Vector3(lamp_x, 1.48, -0.1), shade)
	_box(_table, Vector3(LAMP_WIDTH, 0.02, 0.34), Vector3(lamp_x, 1.53, -0.1), _gold)
	_box(_table, Vector3(LAMP_WIDTH + 0.02, 0.012, 0.012), Vector3(lamp_x, 1.44, 0.065), _neon_mat(NEON_PINK, 0.8)) # neon edge
	_box(_table, Vector3(LAMP_WIDTH, 0.07, 0.02), Vector3(lamp_x, 1.41, 0.05), shade) # skirts hide the bulb from the player
	_box(_table, Vector3(LAMP_WIDTH, 0.07, 0.02), Vector3(lamp_x, 1.41, -0.25), shade)
	var under := _box(_table, Vector3(LAMP_WIDTH - 0.1, 0.01, 0.26), Vector3(lamp_x, 1.435, -0.1), _emissive(WARM, 0.45, false)) # the table lamp stays lit
	under.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for x in [-0.5, 0.5]:
		_cyl(_table, 0.008, 0.008, 1.6, Vector3(lamp_x + x, 1.53 + 0.8, -0.1), _gold)
	var spot := SpotLight3D.new()
	spot.light_color = WARM
	spot.light_energy = 2.5
	spot.spot_range = 3.0
	spot.spot_angle = 55.0
	spot.shadow_enabled = true # jokers, chips and cards cast soft shadows on the felt
	spot.shadow_blur = 2.0
	spot.position = Vector3(lamp_x, 1.4, -0.1)
	spot.rotation_degrees.x = -90.0
	_table.add_child(spot)


func _chip_stack(parent: Node3D, pos: Vector3, count: int, colour: Color) -> void:
	var mat := _mat(colour, 0.5)
	var edge := _mat(Color(1, 1, 1), 0.5)
	for i in count:
		var y := pos.y + 0.0035 + i * 0.0045
		var chip := _cyl(parent, 0.02, 0.02, 0.004, Vector3(pos.x, y, pos.z), mat if i % 3 != 2 else edge, 16)
		chip.rotation_degrees.y = i * 37.0


# ---------------------------------------------------------------- decoration

func _build_back_wall_show() -> void:
	var z := ROOM_CENTER_Z - ROOM_HALF.y + 0.03
	# a big screen with a Balatro-like paint swirl, framed in gold
	# hung above the chair rail and well in front of the wall panels: no surfaces at the same depth,
	# which would flicker (z-fighting)
	var frame := Vector2(3.0, 1.5)
	var centre_y := 1.92
	_box(self, Vector3(frame.x + 0.16, frame.y + 0.16, 0.04), Vector3(0, centre_y, z + 0.07), _gold)
	var screen := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = frame
	screen.mesh = quad
	var swirl := ShaderMaterial.new()
	_swirl_mat = swirl
	swirl.shader = _shader(SWIRL_SHADER)
	screen.material_override = swirl
	screen.position = Vector3(0, centre_y, z + 0.095)
	screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(screen)
	_neon("BALATRO", Vector3(0, 2.95, z + 0.12), 0.0, Color(3.6, 0.5, 0.6), 0.006)
	_neon("UNDER THE VRADAR", Vector3(-ROOM_HALF.x + 0.05, 2.55, ROOM_CENTER_Z + 0.1), 90.0, NEON_CYAN, 0.0028) # between the window and LATE NIGHT
	# on the right wall, out of the way of the Spectral Lounge's arch; this one has the loose contact
	_flicker_colour = NEON_PINK
	_flicker = _neon("OPEN 24/7", Vector3(ROOM_HALF.x - 0.05, 2.6, ROOM_CENTER_Z + 2.6), -90.0, _flicker_colour, 0.0022)
	_neon("LATE NIGHT", Vector3(-ROOM_HALF.x + 0.05, 2.45, ROOM_CENTER_Z + 2.5), 90.0, NEON_PURPLE, 0.0022) # above video poker and claw machine, clear of the wall lamp


func _neon(text: String, pos: Vector3, yaw: float, colour: Color, pixel: float) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = 96
	label.pixel_size = pixel
	label.modulate = colour # above 1.0 so the glow makes it shine like neon
	label.outline_modulate = Color(colour.r * 0.15, colour.g * 0.15, colour.b * 0.15, 1.0)
	label.outline_size = 10
	label.position = pos
	label.rotation_degrees.y = yaw
	add_child(label)
	_dimmed_signs.append({"label": label, "base": colour})
	return label


## A bar on the wall behind the player: counter, stools, shelves with glowing bottles.
func _build_bar() -> void:
	var b := Node3D.new()
	b.position = Vector3(0, 0, ROOM_CENTER_Z + ROOM_HALF.y)
	b.rotation_degrees.y = 180.0 # local +z points into the room
	add_child(b)
	_box(b, Vector3(3.2, 1.05, 0.6), Vector3(0, 0.525, 1.3), _wood)
	_box(b, Vector3(3.3, 0.05, 0.7), Vector3(0, 1.075, 1.3), _mat(Color(0.08, 0.04, 0.03), 0.25))
	_box(b, Vector3(3.2, 0.04, 0.04), Vector3(0, 0.95, 1.61), _gold)
	_box(b, Vector3(3.2, 0.04, 0.04), Vector3(0, 0.1, 1.61), _gold)
	for i in 5:
		var x := -1.3 + i * 0.65
		_cyl(b, 0.18, 0.18, 0.07, Vector3(x, 0.78, 1.95), _leather, 24)
		_cyl(b, 0.025, 0.025, 0.74, Vector3(x, 0.37, 1.95), _gold)
		_cyl(b, 0.2, 0.22, 0.03, Vector3(x, 0.015, 1.95), _gold, 24)
	# back shelves with bottles in many colours
	var bottle_colours := [Color(0.2, 0.7, 0.3), Color(0.8, 0.5, 0.1), Color(0.6, 0.1, 0.15),
			Color(0.3, 0.5, 0.9), Color(0.9, 0.85, 0.6), Color(0.5, 0.2, 0.6)]
	for row in 3:
		var y := 1.25 + row * 0.42
		_box(b, Vector3(3.0, 0.03, 0.25), Vector3(0, y, 0.14), _gold)
		for k in 14:
			var colour: Color = bottle_colours[(k * 7 + row * 3) % bottle_colours.size()]
			var glass := _emissive(colour, 0.9)
			var h := 0.22 + 0.06 * ((k + row) % 3)
			var x := -1.38 + k * 0.212
			_cyl(b, 0.035, 0.04, h, Vector3(x, y + 0.015 + h * 0.5, 0.14), glass, 12)
			_cyl(b, 0.012, 0.012, 0.07, Vector3(x, y + 0.015 + h + 0.035, 0.14), glass, 8)
	_box(b, Vector3(3.2, 1.4, 0.02), Vector3(0, 1.75, 0.01), _mat(Color(0.12, 0.1, 0.1), 0.15, 0.6)) # dark mirror
	# "BAR-LATRO": the bar behind you, in two neon colours (BAR purple, -LATRO in the BALATRO red)
	var bar := _neon("BAR", Vector3(-0.42, 2.95, 0.06), 0.0, Color(2.4, 0.6, 2.8), 0.005)
	bar.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var latro := _neon("-LATRO", Vector3(-0.42, 2.95, 0.06), 0.0, Color(3.6, 0.5, 0.6), 0.005)
	latro.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var sub := _neon("cocktails  ·  jokers  ·  chips  ·  bananas", Vector3(0, 2.6, 0.06), 0.0, NEON_CYAN, 0.0016)
	for sign in [bar, latro, sub]: # hang them on the bar's wall (they are made in room coordinates)
		sign.reparent(b, false)


# ---------------------------------------------------------------- what the game tells the room

## A Spectral card was bought or used: the lounge's sign flickers like a ghost for a moment.
func spectral_flicker() -> void:
	if calm:
		return
	_spectral_time = 2.8


## The clock shows the ante instead of the time ("Ante 8 o'clock"), the minute hand the blind
## (small :00, big :20, boss :40); the Ante Room's display calls the ante.
func set_ante(ante: int, on_deck: String, in_run: bool) -> void:
	var hour := ((maxi(ante, 1) - 1) % 12) + 1
	var minute := {"Small": 0, "Big": 20, "Boss": 40}.get(on_deck, 0) as int
	_clock_target = Vector2(TAU * hour / 12.0 + TAU * minute / 720.0, TAU * minute / 60.0)
	if _clock_label != null:
		_clock_label.text = "ANTE %d O'CLOCK" % maxi(ante, 1) if in_run else "NOT YET ANTE"
	if _now_serving != null:
		_now_serving.text = "ANTE %d" % ante if in_run else "- - -"


## Profile statistics for the Hall of Fame / Hall of Shame.
func set_stats(stats: Dictionary) -> void:
	if stats.is_empty() or stats == _last_stats or _hall_fame.is_empty():
		return
	_last_stats = stats
	var fav_hand := str(stats.get("fav_hand", ""))
	var fav_joker := str(stats.get("fav_joker", ""))
	_fill_hall(_hall_fame, [
		["Best Hand", "naneinf" if float(stats.get("best_hand", 0)) < 0.0 else _big(stats.get("best_hand", 0))],
		["Highest Ante", _big(stats.get("furthest_ante", 0))],
		["Highest Round", _big(stats.get("furthest_round", 0))],
		["Most Money", "$" + _big(stats.get("most_money", 0))],
		["Best Win Streak", _big(stats.get("win_streak", 0))],
		["Bosses in a Row", _big(stats.get("boss_streak", 0))],
		["Runs Won", _big(stats.get("wins", 0))],
		["Favourite Hand", "%s (%sx)" % [fav_hand, _big(stats.get("fav_hand_n", 0))] if fav_hand != "" else "-"],
		["Favourite Joker", "%s (%sx)" % [fav_joker, _big(stats.get("fav_joker_n", 0))] if fav_joker != "" else "-"],
	])
	_fill_hall(_hall_shame, [
		["Runs Lost", _big(stats.get("losses", 0))],
		["Cards Discarded", _big(stats.get("discarded", 0))],
		["Shop Rerolls", _big(stats.get("rerolls", 0))],
		["Jokers Sold", _big(stats.get("jokers_sold", 0))],
		["Money Spent in Shops", "$" + _big(stats.get("spent", 0))],
		["Hands Played", _big(stats.get("hands_played", 0))],
		["Rounds Survived", _big(stats.get("rounds", 0))],
	])


func _fill_hall(hall: Array[Label3D], rows: Array) -> void:
	var names := PackedStringArray()
	var values := PackedStringArray()
	for r in rows:
		names.append(r[0])
		values.append(r[1])
	hall[0].text = "\n".join(names)
	hall[1].text = "\n".join(values)


## 1234567 -> "1,234,567"; huge scores in short form.
static func _big(v) -> String:
	var x := float(v)
	if x >= 1e11: # like the game: 1.234e15 (GDScript's % has no %e)
		var e := int(floor(log(x) / log(10.0)))
		var mant := x / pow(10.0, e)
		if mant >= 9.9995: # rounding up to the next power of ten
			mant /= 10.0
			e += 1
		return "%.3fe%d" % [mant, e]
	var s := str(int(x))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out


func _update_spectral_sign(delta: float) -> void:
	if _spectral_time <= 0.0:
		return
	_spectral_time = maxf(_spectral_time - delta, 0.0)
	var haunt := _spectral_time > 0.0
	for i in _spectral_letters.size():
		var l := _spectral_letters[i]
		var base: Vector3 = l.get_meta("base")
		if not haunt:
			l.modulate = SPECTRAL
			l.position = base
			continue
		# each letter fades in and out on its own, turns pale and drifts like a ghost
		var n := sin(_flicker_time * 23.0 + i * 1.7) + sin(_flicker_time * 37.0 + i * 0.9)
		var ghost := Color(2.6, 2.8, 3.2) if n > 1.2 else SPECTRAL
		var a := 1.0 if n > -0.4 else 0.15
		l.modulate = Color(ghost.r, ghost.g, ghost.b, a)
		l.position = base + Vector3(0, 0.02 * sin(_flicker_time * 9.0 + i), 0.01 * sin(_flicker_time * 13.0 + i * 2.0))


func _update_clock(delta: float) -> void:
	if _clock_hour == null:
		return
	var k := 1.0 - exp(-3.0 * delta)
	_clock_hour.rotation.z = lerp_angle(_clock_hour.rotation.z, -_clock_target.x, k)
	_clock_minute.rotation.z = lerp_angle(_clock_minute.rotation.z, -_clock_target.y, k)


# ---------------------------------------------------------------- side rooms and doors

## Behind you, left of the bar: an open doorway into the Ante Room, a little waiting room with red
## chairs, a ticket dispenser and a "NOW SERVING" display that calls the current ante. Above the
## doorway hangs the clock that tells the ante instead of the time.
func _build_ante_room(w: Node3D, door: Vector3) -> void:
	var cx := door.x
	var hw := door.y * 0.5
	var h := door.z
	for side in [-1.0, 1.0]:
		_box(w, Vector3(0.08, h + 0.08, 0.14), Vector3(cx + side * (hw + 0.04), (h + 0.08) * 0.5, 0.0), _gold)
	_box(w, Vector3(door.y + 0.16, 0.08, 0.14), Vector3(cx, h + 0.04, 0.0), _gold)
	var sign := _neon("THE ANTE ROOM", Vector3(cx, h + 0.27, 0.07), 0.0, Color(3.2, 2.0, 0.5), 0.0019)
	sign.reparent(w, false)
	sign.position = Vector3(cx, h + 0.27, 0.07)
	# the room behind the wall
	var depth := 2.4
	var width := 2.6
	var height := 2.8
	var paper := _mat(Color(0.28, 0.06, 0.08), 0.85)
	_box(w, Vector3(width, 0.02, depth), Vector3(cx, -0.01, -0.1 - depth * 0.5), _wood)
	_box(w, Vector3(width, 0.02, depth), Vector3(cx, height, -0.1 - depth * 0.5), _mat(Color(0.05, 0.02, 0.02), 0.9))
	_box(w, Vector3(width, height, 0.05), Vector3(cx, height * 0.5, -0.1 - depth), paper)
	for side in [-1.0, 1.0]:
		_box(w, Vector3(0.05, height, depth), Vector3(cx + side * width * 0.5, height * 0.5, -0.1 - depth * 0.5), paper)
		_box(w, Vector3(0.03, 0.05, depth), Vector3(cx + side * (width * 0.5 - 0.03), WAINSCOT, -0.1 - depth * 0.5), _gold)
		for i in 3: # waiting chairs along both side walls, facing each other
			_chair(w, Vector3(cx + side * (width * 0.5 - 0.35), 0, -0.75 - i * 0.6), -90.0 * side)
	# NOW SERVING display on the back wall
	var back_z := -0.1 - depth + 0.06
	_box(w, Vector3(0.9, 0.42, 0.06), Vector3(cx, 2.0, back_z), _mat(Color(0.02, 0.02, 0.02), 0.3, 0.3))
	var title := Label3D.new()
	title.text = "NOW SERVING"
	title.font_size = 48
	title.pixel_size = 0.0018
	title.modulate = Color(1.0, 0.9, 0.7)
	title.outline_size = 0
	title.position = Vector3(cx, 2.13, back_z + 0.035)
	w.add_child(title)
	_now_serving = Label3D.new()
	_now_serving.text = "- - -"
	_now_serving.font_size = 96
	_now_serving.pixel_size = 0.0022
	_now_serving.modulate = Color(3.0, 0.3, 0.2) # red LED digits
	_now_serving.outline_size = 0
	_now_serving.position = Vector3(cx, 1.94, back_z + 0.035)
	w.add_child(_now_serving)
	# "take a number" dispenser on a post, a potted plant in the corner
	var post := Vector3(cx - width * 0.5 + 0.35, 0, -0.35)
	_cyl(w, 0.025, 0.025, 1.05, post + Vector3(0, 0.525, 0), _gold)
	_box(w, Vector3(0.16, 0.2, 0.12), post + Vector3(0, 1.15, 0), _mat(Color(0.75, 0.08, 0.1), 0.4))
	var take := Label3D.new()
	take.text = "TAKE A\nNUMBER"
	take.font_size = 32
	take.pixel_size = 0.0011
	take.outline_size = 0
	take.modulate = Color(1, 1, 1)
	take.position = post + Vector3(0, 1.16, 0.061)
	w.add_child(take)
	var plant := Vector3(cx, 0, -0.1 - depth + 0.3) # under the display, between the chair rows
	_cyl(w, 0.14, 0.11, 0.3, plant + Vector3(0, 0.15, 0), _mat(Color(0.5, 0.25, 0.12), 0.7))
	_add(w, _sphere(0.25), plant + Vector3(0, 0.55, 0), _mat(Color(0.12, 0.35, 0.12), 0.9))
	var light := OmniLight3D.new()
	light.light_color = WARM
	light.light_energy = 1.6
	light.omni_range = 3.0
	light.position = Vector3(cx, 2.4, -1.3)
	_dimmed_lights.append({"light": light, "base": 1.6})
	w.add_child(light)
	_build_ante_clock(w, Vector3(cx, h + 0.73, 0.06))


## A wall clock whose hour hand points at the ante ("Ante 8 o'clock").
func _build_ante_clock(w: Node3D, at: Vector3) -> void:
	var clock := Node3D.new()
	clock.position = at
	w.add_child(clock)
	var r := 0.22
	var face := _cyl(clock, r, r, 0.03, Vector3.ZERO, _emissive(Color(0.95, 0.92, 0.82), 0.25), 40)
	face.rotation_degrees.x = 90.0
	var rim := _torus(clock, r - 0.005, r + 0.025, Vector3(0, 0, 0.0), _gold)
	rim.rotation_degrees.x = 90.0
	for i in 12:
		var a := TAU * (i + 1) / 12.0
		var num := Label3D.new()
		num.text = str(i + 1)
		num.font_size = 32
		num.pixel_size = 0.0016
		num.outline_size = 0
		num.modulate = Color(0.1, 0.08, 0.08)
		num.position = Vector3(sin(a) * r * 0.78, cos(a) * r * 0.78, 0.018)
		clock.add_child(num)
	_clock_label = Label3D.new()
	_clock_label.text = "NOT YET ANTE"
	_clock_label.font_size = 24
	_clock_label.pixel_size = 0.0012
	_clock_label.outline_size = 0
	_clock_label.modulate = Color(0.55, 0.1, 0.1)
	_clock_label.position = Vector3(0, r * 0.4, 0.018)
	clock.add_child(_clock_label)
	var dark := _mat(Color(0.08, 0.06, 0.06), 0.4)
	_clock_hour = Node3D.new()
	_clock_hour.position.z = 0.022
	clock.add_child(_clock_hour)
	_box(_clock_hour, Vector3(0.016, r * 0.55, 0.006), Vector3(0, r * 0.25, 0), dark)
	_clock_minute = Node3D.new()
	_clock_minute.position.z = 0.028
	clock.add_child(_clock_minute)
	_box(_clock_minute, Vector3(0.01, r * 0.8, 0.006), Vector3(0, r * 0.37, 0), dark)
	_add(clock, _sphere(0.014), Vector3(0, 0, 0.03), _gold)
	set_ante(1, "Small", false)


## A tiny, colourful door at knee height in the left wall: the Wee Joker Kids Corner.
func _build_kids_door() -> void:
	var d := Node3D.new()
	d.position = Vector3(-ROOM_HALF.x, 0, KIDS_DOOR_Z)
	d.rotation_degrees.y = 90.0 # local +z points into the room
	add_child(d)
	var w := 0.44
	var h := 0.68
	var red := _mat(Color(0.85, 0.15, 0.15), 0.5)
	_box(d, Vector3(w + 0.1, 0.05, 0.08), Vector3(0, h + 0.025, 0.06), red)
	for x in [-1.0, 1.0]:
		_box(d, Vector3(0.05, h + 0.05, 0.08), Vector3(x * (w * 0.5 + 0.025), (h + 0.05) * 0.5, 0.06), red)
	_box(d, Vector3(w, h, 0.03), Vector3(0, h * 0.5, 0.075), _mat(Color(1.0, 0.82, 0.15), 0.5))
	var window := _cyl(d, 0.07, 0.07, 0.01, Vector3(0, h * 0.7, 0.092), _emissive(Color(0.4, 0.85, 1.0), 0.8), 24)
	window.rotation_degrees.x = 90.0
	var ring := _torus(d, 0.068, 0.085, Vector3(0, h * 0.7, 0.092), red)
	ring.rotation_degrees.x = 90.0
	_add(d, _sphere(0.018), Vector3(w * 0.5 - 0.06, h * 0.42, 0.1), _gold)
	# the Wee Joker's "2" card on the door
	_box(d, Vector3(0.09, 0.125, 0.006), Vector3(0, h * 0.32, 0.093), _mat(Color(0.97, 0.95, 0.9), 0.5))
	var two := Label3D.new()
	two.text = "2"
	two.font_size = 64
	two.pixel_size = 0.0012
	two.outline_size = 0
	two.modulate = Color(0.8, 0.1, 0.15)
	two.position = Vector3(0, h * 0.32, 0.097)
	d.add_child(two)
	# colourful sign above it and a "you must be this small" line beside it
	var colours := [NEON_PINK, Color(3.2, 2.6, 0.4), NEON_CYAN]
	var words := ["WEE", "JOKER", "KIDS CORNER"]
	var spots := [[Vector3(-0.1, 1.22, 0.06), HORIZONTAL_ALIGNMENT_RIGHT], [Vector3(-0.05, 1.22, 0.06), HORIZONTAL_ALIGNMENT_LEFT],
			[Vector3(0, 1.1, 0.06), HORIZONTAL_ALIGNMENT_CENTER]]
	for i in words.size():
		var l := _neon(words[i], Vector3.ZERO, 0.0, colours[i], 0.0016 if i < 2 else 0.0012)
		l.reparent(d, false)
		l.position = spots[i][0]
		l.horizontal_alignment = spots[i][1]
	_box(d, Vector3(0.22, 0.012, 0.012), Vector3(w * 0.5 + 0.2, h + 0.02, 0.06), _gold)
	var small := Label3D.new()
	small.text = "You must be\nthis small\nto enter"
	small.font_size = 32
	small.pixel_size = 0.0009
	small.outline_size = 0
	small.modulate = Color(1, 0.95, 0.8)
	small.position = Vector3(w * 0.5 + 0.2, h + 0.1, 0.06)
	d.add_child(small)


## On the wall in front of you, left and right of the big screen: the Hall of Fame (your best
## runs) and the Hall of Shame (the not so proud numbers), filled from your Balatro profile.
func _build_halls(w: Node3D) -> void:
	for side in [-1.0, 1.0]:
		var fame: bool = side < 0.0
		var cx: float = side * 2.95
		var size := Vector2(1.5, 1.05)
		var y := 1.75
		_box(w, Vector3(size.x + 0.12, size.y + 0.12, 0.04), Vector3(cx, y, 0.04), _gold)
		var bg := _mat(Color(0.03, 0.16, 0.08) if fame else Color(0.2, 0.03, 0.04), 0.9)
		_box(w, Vector3(size.x, size.y, 0.02), Vector3(cx, y, 0.065), bg)
		var title := _neon("HALL OF FAME" if fame else "HALL OF SHAME", Vector3.ZERO, 0.0,
				Color(3.2, 2.4, 0.5) if fame else Color(3.4, 0.4, 0.4), 0.0024)
		title.reparent(w, false)
		title.position = Vector3(cx, y + size.y * 0.5 + 0.2, 0.07)
		var sub := Label3D.new()
		sub.text = "legends of the felt" if fame else "we don't talk about these"
		sub.font_size = 32
		sub.pixel_size = 0.0012
		sub.outline_size = 0
		sub.modulate = Color(0.9, 0.85, 0.6) if fame else Color(0.9, 0.6, 0.6)
		sub.position = Vector3(cx, y + size.y * 0.5 - 0.07, 0.08)
		w.add_child(sub)
		var labels: Array[Label3D] = []
		for col in 2:
			var l := Label3D.new()
			l.font_size = 32
			l.pixel_size = 0.0018
			l.line_spacing = 6
			l.outline_size = 0
			l.modulate = Color(0.95, 0.92, 0.85)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if col == 0 else HORIZONTAL_ALIGNMENT_RIGHT
			l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
			l.position = Vector3(cx + (-0.68 if col == 0 else 0.68), y + size.y * 0.5 - 0.15, 0.08)
			l.text = "No records yet" if col == 0 else ""
			w.add_child(l)
			labels.append(l)
		if fame:
			_hall_fame = labels
		else:
			_hall_shame = labels


## A white door next to the bar: the restrooms, "The Flush".
func _build_restroom_door() -> void:
	var d := Node3D.new()
	d.position = Vector3(2.5, 0, ROOM_CENTER_Z + ROOM_HALF.y)
	d.rotation_degrees.y = 180.0 # local +z points into the room
	add_child(d)
	var white := _mat(Color(0.93, 0.93, 0.9), 0.35)
	white.emission_enabled = true # stays white in the dim casino light
	white.emission = Color(0.93, 0.93, 0.9) * 0.12
	var frame := _mat(Color(0.85, 0.85, 0.82), 0.4)
	var w := 0.9
	var h := 2.1
	# frame (covers the wainscot and the floor neon behind it)
	_box(d, Vector3(w + 0.16, 0.08, 0.1), Vector3(0, h + 0.04, 0.05), frame)
	for x in [-1.0, 1.0]:
		_box(d, Vector3(0.08, h + 0.08, 0.1), Vector3(x * (w * 0.5 + 0.04), (h + 0.08) * 0.5, 0.05), frame)
	var door := _box(d, Vector3(w, h, 0.04), Vector3(0, h * 0.5, 0.07), white)
	door.name = "RestroomDoor"
	# two raised panels on the door
	for y in [0.55, 1.5]:
		_box(d, Vector3(w - 0.24, 0.7 if y > 1.0 else 0.75, 0.015), Vector3(0, y, 0.095), white)
	# gold handle and kick plate
	_box(d, Vector3(0.14, 0.025, 0.03), Vector3(w * 0.5 - 0.14, 1.0, 0.11), _gold)
	_cyl(d, 0.03, 0.03, 0.02, Vector3(w * 0.5 - 0.1, 1.0, 0.095), _gold).rotation_degrees.x = 90.0
	_box(d, Vector3(w - 0.08, 0.18, 0.006), Vector3(0, 0.1, 0.093), _gold)
	# restroom pictograms on a plate at eye level: a man and a woman
	var plate_y := 1.62
	_box(d, Vector3(0.3, 0.2, 0.008), Vector3(0, plate_y, 0.107), _mat(Color(0.1, 0.1, 0.12), 0.3))
	var icon := _emissive(Color(0.95, 0.95, 0.95), 0.6)
	for side in [-1.0, 1.0]:
		var x: float = side * 0.065
		_add(d, _sphere(0.018), Vector3(x, plate_y + 0.055, 0.113), icon)
		if side < 0.0: # man: straight body
			_box(d, Vector3(0.04, 0.09, 0.004), Vector3(x, plate_y - 0.012, 0.113), icon)
		else: # woman: dress
			var dress := _cyl(d, 0.008, 0.032, 0.09, Vector3(x, plate_y - 0.012, 0.11), icon, 12)
			dress.scale.z = 0.12
	_box(d, Vector3(0.006, 0.15, 0.004), Vector3(0, plate_y, 0.113), icon) # divider
	# name on the door and a neon sign above it
	var name_plate := Label3D.new()
	name_plate.text = "THE FLUSH"
	name_plate.font_size = 64
	name_plate.pixel_size = 0.0018
	name_plate.modulate = Color(0.12, 0.1, 0.1)
	name_plate.outline_size = 0
	name_plate.position = Vector3(0, 1.4, 0.104)
	d.add_child(name_plate)
	var sub := _neon("restrooms", Vector3(0, h + 0.3, 0.06), 0.0, NEON_PINK, 0.0022)
	sub.reparent(d, false)


func _sphere(radius: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	return s


func _side_table(pos: Vector3) -> void:
	var t := Node3D.new()
	t.position = pos
	add_child(t)
	_cyl(t, 0.62, 0.62, 0.03, Vector3(0, 0.765, 0), _felt, 48)
	_torus(t, 0.6, 0.68, Vector3(0, 0.78, 0), _leather)
	_cyl(t, 0.64, 0.6, 0.1, Vector3(0, 0.71, 0), _wood, 48)
	_cyl(t, 0.08, 0.08, 0.66, Vector3(0, 0.33, 0), _wood)
	_cyl(t, 0.35, 0.4, 0.04, Vector3(0, 0.02, 0), _gold, 32)
	_chip_stack(t, Vector3(0.2, 0.78, 0.1), 6, Color(0.85, 0.15, 0.15))
	_chip_stack(t, Vector3(0.25, 0.78, 0.16), 9, Color(0.15, 0.35, 0.85))
	_chip_stack(t, Vector3(-0.3, 0.78, -0.05), 5, Color(0.1, 0.1, 0.1))
	for i in 4:
		var a := i * TAU / 4.0 + 0.4
		_chair(t, Vector3(sin(a) * 0.95, 0, cos(a) * 0.95), rad_to_deg(a) + 180.0)


func _chair(parent: Node3D, pos: Vector3, yaw: float) -> void:
	var c := Node3D.new()
	c.position = pos
	c.rotation_degrees.y = yaw
	parent.add_child(c)
	var seat := _mat(Color(0.42, 0.05, 0.07), 0.5)
	_box(c, Vector3(0.46, 0.08, 0.44), Vector3(0, 0.47, 0), seat)
	_box(c, Vector3(0.46, 0.5, 0.06), Vector3(0, 0.76, -0.2), seat)
	_box(c, Vector3(0.48, 0.04, 0.08), Vector3(0, 1.02, -0.2), _gold)
	for x in [-0.19, 0.19]:
		for z in [-0.18, 0.18]:
			_cyl(c, 0.02, 0.018, 0.43, Vector3(x, 0.215, z), _wood, 8)


# ---------------------------------------------------------------- mesh / material helpers

func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _add(parent, mesh, pos, mat)


func _cyl(parent: Node3D, top: float, bottom: float, height: float, pos: Vector3, mat: Material, segments := 24) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = 1
	return _add(parent, mesh, pos, mat)


func _torus(parent: Node3D, inner: float, outer: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.rings = 64
	mesh.ring_segments = 12
	return _add(parent, mesh, pos, mat)


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


func _emissive(colour: Color, energy: float, dims := true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(colour.r * energy, colour.g * energy, colour.b * energy)
	if dims: # glowing things of the room go dark in the last hand (see _apply_dim)
		_dimmed_mats.append({"mat": m, "base": m.albedo_color})
	return m


## Texture repeated over world space (`per_meter` tiles per meter), so any box size tiles evenly.
func _textured(tex: Texture2D, per_meter: float, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.roughness = roughness
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * per_meter
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


func _shader(code: String) -> Shader:
	var s := Shader.new()
	s.code = code
	return s


# ---------------------------------------------------------------- procedural textures

## Casino carpet: dark burgundy diamonds with a purple lattice and teal medallions.
func _carpet_texture() -> ImageTexture:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var base := Color(0.1, 0.02, 0.05)
	var dark := Color(0.05, 0.01, 0.03)
	var gold := Color(0.3, 0.12, 0.35)    # dim purple lattice
	var blue := Color(0.02, 0.15, 0.22)   # teal medallions
	for y in n:
		for x in n:
			var u := (x + 0.5) / n
			var v := (y + 0.5) / n
			var a := fposmod(u + v, 0.5)
			var b := fposmod(u - v, 0.5)
			var c: Color
			if a < 0.018 or b < 0.018:
				c = gold
			else:
				var d := Vector2(a - 0.25, b - 0.25).length()
				if d < 0.055:
					c = blue
				elif d < 0.075:
					c = gold
				else:
					var cell := int(floor((u + v) / 0.5) + floor((u - v + 1.0) / 0.5))
					c = base if cell % 2 == 0 else dark
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Near-black damask wallpaper with a purple sheen.
func _wallpaper_texture() -> ImageTexture:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var base := Color(0.025, 0.022, 0.04)
	var orn := Color(0.06, 0.045, 0.09)
	var line := Color(0.14, 0.08, 0.18)
	for y in n:
		for x in n:
			var u := (x + 0.5) / n
			var v := (y + 0.5) / n
			var shift := 0.5 if fposmod(u * 2.0, 2.0) >= 1.0 else 0.0
			var du := absf(fposmod(u * 2.0, 1.0) - 0.5)
			var dv := absf(fposmod(v * 2.0 + shift, 1.0) - 0.5)
			var lobe := du * 1.6 + dv + 0.06 * sin(dv * 40.0)
			var c := base
			if lobe < 0.3:
				c = orn
			if absf(lobe - 0.33) < 0.012:
				c = line
			if absf(fposmod(u * 2.0, 1.0)) < 0.01:
				c = line
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Dark ebony-like wood grain.
func _wood_texture() -> ImageTexture:
	var noise := FastNoiseLite.new()
	noise.seed = 3
	noise.frequency = 0.02
	var w := 128
	var h := 256
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var dark := Color(0.07, 0.03, 0.025)
	var light := Color(0.15, 0.07, 0.045)
	for y in h:
		for x in w:
			var g := noise.get_noise_2d(x * 3.0, y * 0.25)
			var t := fposmod(g * 7.0, 1.0)
			img.set_pixel(x, y, dark.lerp(light, t * t))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Green felt with a fine fuzz.
func _felt_texture() -> ImageTexture:
	var noise := FastNoiseLite.new()
	noise.seed = 9
	noise.frequency = 0.25
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		for x in n:
			var k := 1.0 + noise.get_noise_2d(x, y) * 0.12
			img.set_pixel(x, y, Color(FELT.r * k, FELT.g * k, FELT.b * k))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


# ---------------------------------------------------------------- shaders

## A beam of light in smoky air: brightest where you look through most of it (the middle of the
## cone), soft at its rim, fading towards its end; slow wisps of smoke drift through it.
const SHAFT_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform vec3 colour : source_color = vec3(1.0, 0.82, 0.6);
uniform float strength = 0.08;
uniform bool upward = false;              // the light comes from the bottom end (wall lamps)
varying vec3 world;

float hash(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float noise(vec3 x) {
	vec3 i = floor(x); vec3 f = fract(x); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1,0,0)), f.x), mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x), mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}

void vertex() { world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float core = pow(facing, 2.0);                  // soft rim
	float along = 1.0 - (upward ? 1.0 - UV.y : UV.y) * 0.75; // fades towards the end of the beam
	vec3 drift = vec3(TIME * 0.05, -TIME * 0.03, TIME * 0.04);
	float smoke = 0.6 + 0.8 * noise(world * 3.0 + drift) * noise(world * 1.3 - drift);
	ALBEDO = colour * strength * core * along * smoke;
}
"""

## A slowly turning paint swirl in Balatro's red and blue, pixelated like the game's background.
const SWIRL_SHADER := """
shader_type spatial;
render_mode unshaded;
uniform vec3 colour_1 = vec3(0.87, 0.27, 0.23);
uniform vec3 colour_2 = vec3(0.0, 0.42, 0.71);
uniform vec3 colour_3 = vec3(0.09, 0.14, 0.15);
uniform float brightness = 0.75;
uniform vec2 pixels = vec2(200.0, 100.0);

void fragment() {
	vec2 uv = (floor(UV * pixels) + 0.5) / pixels;
	uv = (uv - 0.5) * vec2(2.0, 1.0);
	float len = length(uv);
	float angle = atan(uv.y, uv.x) + TIME * 0.08 - 2.5 * len;
	uv = vec2(cos(angle), sin(angle)) * len * 9.0;
	vec2 uv2 = vec2(uv.x + uv.y);
	float speed = TIME * 0.9;
	for (int i = 0; i < 5; i++) {
		uv2 += sin(max(uv.x, uv.y)) + uv;
		uv += 0.5 * vec2(cos(5.1123 + 0.353 * uv2.y + speed * 0.131), sin(uv2.x - 0.113 * speed));
		uv -= cos(uv.x + uv.y) - sin(uv.x * 0.711 - uv.y);
	}
	float cm = 2.2;
	float paint = clamp(length(uv) * 0.035 * cm, 0.0, 2.0);
	float c1 = max(0.0, 1.0 - cm * abs(1.0 - paint));
	float c2 = max(0.0, 1.0 - cm * abs(paint));
	float c3 = 1.0 - min(1.0, c1 + c2);
	vec3 col = 0.1 * colour_1 + 0.9 * (colour_1 * c1 + colour_2 * c2 + colour_3 * c3);
	ALBEDO = col * brightness;
}
"""
