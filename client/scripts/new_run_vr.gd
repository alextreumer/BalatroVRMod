class_name NewRunVR
extends Node3D
## The "New Run" table in VR (after PLAY in the VR main menu), instead of the game's run setup panel:
##   every deck lies as a little stack on a lazy Susan (locked ones greyed) - grab the turntable at its
##   rim and spin it until the deck you want is in front of you (it clicks into place, the front deck
##   lifts a little); grab that deck and put it on the mat, then put a stake chip on it (only stakes the
##   game allows for that deck), and press START. Pointing at a deck or a chip shows its description from the game on the
##   board above the mat; the trigger on a deck or chip puts it on the mat right away. BACK returns
##   to the main menu. Positions are in the joker board's space (x right, +z towards you, y up).

signal start(deck: String, stake: int)
signal back
signal more                         # "CHALLENGES · SEED": the game's own run setup panel
signal hint(text: String, at: Node3D)
signal ticked(hand: Node3D)         # a deck passed the front of the turntable (a little click in the hand)

const CARD := Vector2(0.071, 0.095)
const MAT_POS := Vector3(0.0, 0.0, 0.12)         # right in front of you (its gold frame ends at the table's front edge)
const START_POS := Vector3(-0.58, 0.0, 0.1)
const BACK_POS := Vector3(-0.5, 0.0, -0.12)
# the lazy Susan: a turntable, the decks round its rim (the front one ~20 cm from the table's edge)
const SUSAN_POS := Vector3(0.0, 0.0, -0.32) # (right behind the mat: its front edge at the mat's frame)
const SUSAN_R := 0.34               # the plate's radius (a wide wooden rim outside the decks to turn it by)
const DECK_RING := 0.23             # the decks' distance from its middle
const PLATE_TOP := 0.016            # the decks lie on it at this height
const SPIN_GRAB_MIN := 0.285        # a hand this far (or further) from the middle - outside the gold ring - turns the plate
const SPIN_FRICTION := 1.6          # how fast a flicked turntable slows down
const SNAP_SPEED := 0.7             # slower than this (rad/s): it eases to the nearest deck in front
const GRAB_RADIUS := 0.08
const DROP_RADIUS := 0.13           # let go this close to the mat (sideways) = put on it
const STACK_H := 0.02
const CHIP_R := 0.026
const START_ID := -400
const BACK_ID := -401
const MORE_ID := -402
const MORE_POS := Vector3(-0.5, 0.0, -0.3)
const DECK_ID := -410               # - index
const CHIP_ID := -470               # - stake index

var deck_colour: Callable           # (key) -> Color
var hands: Array = []               # XRController3D: hands that can slap the START buzzer

const TOUCH_RADIUS := 0.07          # a hand this close to the buzzer's top presses it
var _armed := {}                    # hand -> may press again (it left the buzzer since)
var _press_t := 0.0                 # > 0 while the buzzer is pushed down

var _decks := {}                    # key -> {"node", "data", "home": Vector3, "index"}
var _chips := {}                    # stake index -> {"node", "data", "home": Vector3}
var _order: Array = []              # deck keys in the game's order
var _deck_on_mat := ""
var _stake_on_mat := 0
var _held: Node3D = null
var _held_kind := ""                # "deck" / "chip"
var _held_key = null
var _held_hand: Node3D = null
var _held_offset := Transform3D()
var _info: Label3D
var _start_cap: MeshInstance3D
var _start_mat: StandardMaterial3D
var _built_key := ""
var _bodies: Array[StaticBody3D] = []
var _hover := -1
var _susan: Node3D                  # the turning plate
var _angle := 0.0                   # its turn (rad, round the vertical: + = anticlockwise from above)
var _spin_vel := 0.0
var _spin_hand: Node3D = null       # the hand turning it at its rim
var _spin_last := 0.0               # that hand's angle round the middle last frame
var _last_hand: Node3D = null       # (for the click of a deck passing the front)
var _front := -1                    # the deck in front of you


func _ready() -> void:
	_build_susan()
	_build_mat()
	_build_start()
	_build_back()
	_build_sign("CHALLENGES\nSEED", MORE_ID, MORE_POS, Color(0.6, 1.4, 2.0))
	_info = Label3D.new()
	_info.font_size = 30
	_info.pixel_size = 0.00055
	_info.width = 0.4 / _info.pixel_size
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_info.outline_size = 8
	_info.outline_modulate = Color(0.05, 0.03, 0.06)
	_info.modulate = Color(1.0, 0.95, 0.85)
	_info.position = SUSAN_POS + Vector3(0.0, 0.2, 0.0) # (over the turntable)
	add_child(_info)
	GameFont.apply_to(self)


## The decks and stakes from the game (built again only when they change).
func setup(info: Dictionary) -> void:
	var decks: Array = info.get("decks", [])
	var stakes: Array = info.get("stakes", [])
	# (built again once the deck backs and chips have their textures: they arrive a moment later)
	var atlases := {}
	for s in decks + stakes:
		var sp = s.get("sprite")
		if sp is Dictionary:
			atlases[str(sp.get("atlas"))] = CardArt.has_atlas(sp.get("atlas"))
	var key := JSON.stringify([decks.map(func(d): return [d.get("key"), d.get("unlocked"), d.get("max_stake")]), stakes.size(), atlases])
	if key == _built_key:
		return
	_built_key = key
	for e in _decks.values():
		(e["node"] as Node3D).free()
	for e in _chips.values():
		(e["node"] as Node3D).free()
	_decks.clear()
	_chips.clear()
	_order.clear()
	_bodies = _bodies.filter(func(b): return is_instance_valid(b))
	# the decks: round the turntable's rim (their places turn with it, see _deck_home)
	var n := decks.size()
	for i in n:
		var d: Dictionary = decks[i]
		var node := _make_deck(d, i)
		_decks[str(d.get("key"))] = {"node": node, "data": d, "home": Vector3.ZERO, "index": i, "settled": false, "lift": 0.0}
		node.transform = _deck_home(i, 0.0)
		_order.append(str(d.get("key")))
	# the stake chips: one row beside the mat - the first four left of it, the other four right of it
	for j in stakes.size():
		var s: Dictionary = stakes[j]
		var index := int(s.get("index", j + 1))
		var side := -1.0 if j < 4 else 1.0
		var k := (3 - j) if j < 4 else (j - 4) # (counted out from the mat)
		var home := MAT_POS + Vector3(side * (0.215 + k * 0.066), 0.0, -0.04) # (room for "YOUR DECK" beside the mat)
		var chip := _make_chip(s, index)
		chip.position = home
		_chips[index] = {"node": chip, "data": s, "home": home}
	if not _decks.has(_deck_on_mat):
		_deck_on_mat = ""
	if not _chips.has(_stake_on_mat):
		_stake_on_mat = 0
	GameFont.apply_to(self)
	_refresh()


## Opened from the main menu's PLAY: start with an empty mat.
func open() -> void:
	_deck_on_mat = ""
	_stake_on_mat = 0
	_held = null
	_refresh()


func try_grab(hand: Node3D) -> bool:
	if not is_visible_in_tree() or _held != null:
		return false
	# the turntable's rim: grab it and turn it
	var at := to_local(hand.global_position) - SUSAN_POS
	var flat := Vector2(at.x, at.z).length()
	if _spin_hand == null and flat > SPIN_GRAB_MIN and flat < SUSAN_R + 0.05 and at.y > -0.04 and at.y < 0.1:
		_spin_hand = hand
		_last_hand = hand
		_spin_last = atan2(at.x, at.z)
		_spin_vel = 0.0
		return true
	var best: Node3D = null
	var best_d := GRAB_RADIUS
	var kind := ""
	var key = null
	for k in _decks:
		var e: Dictionary = _decks[k]
		if not e["data"].get("unlocked", false):
			continue
		var d := (e["node"] as Node3D).global_position.distance_to(hand.global_position)
		if d < best_d:
			best = e["node"]; best_d = d; kind = "deck"; key = k
	for idx in _chips:
		var e: Dictionary = _chips[idx]
		var d := (e["node"] as Node3D).global_position.distance_to(hand.global_position)
		if d < best_d:
			best = e["node"]; best_d = d; kind = "chip"; key = idx
	if best == null:
		return false
	_held = best
	if kind == "deck":
		_decks[key]["settled"] = false
	_held_kind = kind
	_held_key = key
	_held_hand = hand
	_held_offset = hand.global_transform.affine_inverse() * best.global_transform
	if kind == "deck" and _deck_on_mat == key: # taken off the mat again
		_deck_on_mat = ""
		_stake_on_mat = 0
	elif kind == "chip" and _stake_on_mat == key:
		_stake_on_mat = 0
	_refresh()
	return true


func holds(hand: Node3D) -> bool:
	return (_held != null and _held_hand == hand) or (_spin_hand != null and _spin_hand == hand)


func release(hand: Node3D) -> void:
	if _spin_hand != null and _spin_hand == hand:
		_spin_hand = null # it spins on with the hand's swing, then clicks into place
		return
	if not holds(hand):
		return
	var node := _held
	_held = null
	var local := to_local(node.global_position)
	var near := Vector2(local.x - MAT_POS.x, local.z - MAT_POS.z).length() < DROP_RADIUS and local.y < 0.3
	if near:
		if _held_kind == "deck":
			_put_deck(str(_held_key))
		else:
			_put_chip(int(_held_key))
	_refresh()


## The trigger on something of the table: START, BACK, or a deck / chip straight onto the mat.
func press(id: int) -> void:
	if id == START_ID:
		_press_t = 0.18 # the dome goes down for a moment
		if _deck_on_mat != "" and _stake_on_mat > 0:
			start.emit(_deck_on_mat, _stake_on_mat)
		else:
			hint.emit("Put a deck and a stake chip on the mat", _start_cap)
	elif id == BACK_ID:
		back.emit()
	elif id == MORE_ID:
		more.emit()
	elif id <= DECK_ID and id > CHIP_ID:
		var i := DECK_ID - id
		if i < _order.size():
			var key: String = _order[i]
			if _decks[key]["data"].get("unlocked", false):
				_put_deck(key)
			else:
				hint.emit("This deck is still locked", _decks[key]["node"])
	elif id <= CHIP_ID:
		_put_chip(CHIP_ID - id)
	_refresh()


## The beam points at something (-1: at nothing of the table): its description on the board.
func hover(id: int) -> void:
	if id == _hover:
		return
	_hover = id
	_refresh()


func _put_deck(key: String) -> void:
	if _deck_on_mat != "" and _decks.has(_deck_on_mat):
		_decks[_deck_on_mat]["settled"] = false # (the one that was there goes back to its place)
	_decks[key]["settled"] = false
	_deck_on_mat = key
	var max_stake := int(_decks[key]["data"].get("max_stake", 1))
	if _stake_on_mat > max_stake:
		hint.emit("This deck allows stakes up to %s" % _stake_name(max_stake), _chips[_stake_on_mat]["node"])
		_stake_on_mat = 0


func _put_chip(index: int) -> void:
	if not _chips.has(index):
		return
	if _deck_on_mat == "":
		hint.emit("Put a deck on the mat first", _chips[index]["node"])
		return
	var max_stake := int(_decks[_deck_on_mat]["data"].get("max_stake", 1))
	if index > max_stake:
		hint.emit("Win with this deck on %s first" % _stake_name(index - 1), _chips[index]["node"])
		return
	_stake_on_mat = index


func _stake_name(index: int) -> String:
	return str(_chips[index]["data"].get("name", "Stake %d" % index)) if _chips.has(index) else "Stake %d" % index


func _refresh() -> void:
	var ready := _deck_on_mat != "" and _stake_on_mat > 0
	if _start_mat != null:
		_start_mat.albedo_color = Color(0.9, 0.08, 0.06) if ready else Color(0.35, 0.3, 0.3)
		_start_mat.emission_energy_multiplier = 0.9 if ready else 0.0
	# chips this deck can't be played on are greyed
	var max_stake := int(_decks[_deck_on_mat]["data"].get("max_stake", 99)) if _deck_on_mat != "" else 99
	for idx in _chips:
		var top: MeshInstance3D = ((_chips[idx]["node"] as Node3D).get_meta("top") if (_chips[idx]["node"] as Node3D).has_meta("top") else null)
		if top != null and top.material_override is StandardMaterial3D:
			(top.material_override as StandardMaterial3D).albedo_color = Color.WHITE if idx <= max_stake else Color(0.3, 0.3, 0.3)
	# the board: what the beam points at, otherwise the choice so far
	if _info == null:
		return
	var text := ""
	if _hover <= DECK_ID and _hover > CHIP_ID and DECK_ID - _hover < _order.size():
		var d: Dictionary = _decks[_order[DECK_ID - _hover]]["data"]
		text = "%s\n%s" % [d.get("name", ""), d.get("text", "")]
	elif _hover <= CHIP_ID and _chips.has(CHIP_ID - _hover):
		var s: Dictionary = _chips[CHIP_ID - _hover]["data"]
		text = "%s\n%s" % [s.get("name", ""), s.get("text", "")]
	elif _deck_on_mat == "":
		text = "Grab a deck and put it on the mat"
	elif _stake_on_mat == 0:
		text = "%s\nNow put a stake chip on it" % _decks[_deck_on_mat]["data"].get("name", "")
	else:
		text = "%s  •  %s\nPress START" % [_decks[_deck_on_mat]["data"].get("name", ""), _stake_name(_stake_on_mat)]
	_info.text = text


func _process(delta: float) -> void:
	if not visible:
		return
	if _held != null and is_instance_valid(_held_hand):
		_held.global_transform = _held_hand.global_transform * _held_offset
	# slapping the START buzzer with a hand (like the main menu's PLAY)
	if _press_t > 0.0:
		_press_t = maxf(_press_t - delta, 0.0)
	_start_cap.position.y = 0.03 - (0.01 if _press_t > 0.0 else 0.0)
	var top := _start_cap.global_position + global_basis.y.normalized() * 0.03
	for hand in hands:
		if hand == null or not is_instance_valid(hand) or not hand.is_inside_tree() or hand == _held_hand and _held != null:
			continue
		var d: float = (hand as Node3D).global_position.distance_to(top)
		if d < TOUCH_RADIUS and _armed.get(hand, true):
			_armed[hand] = false
			press(START_ID)
		elif d > TOUCH_RADIUS * 1.8:
			_armed[hand] = true
	_turn_susan(delta)
	var k := 1.0 - exp(-12.0 * delta)
	for key in _decks:
		var e: Dictionary = _decks[key]
		var node: Node3D = e["node"]
		if node == _held:
			continue
		if key == _deck_on_mat:
			node.transform = node.transform.interpolate_with(Transform3D(Basis(), MAT_POS + Vector3(0, 0.004, 0)), k)
			continue
		var i: int = e["index"]
		e["lift"] = lerpf(float(e["lift"]), 0.012 if i == _front and _spin_hand == null else 0.0, k)
		var want := _deck_home(i, float(e["lift"]))
		if e["settled"]: # lying on the plate: it turns with it exactly
			node.transform = want
		else: # coming back from the hand or the mat
			node.transform = node.transform.interpolate_with(want, k)
			e["settled"] = node.transform.origin.distance_to(want.origin) < 0.004
	for idx in _chips:
		var e: Dictionary = _chips[idx]
		var node: Node3D = e["node"]
		if node == _held:
			continue
		var want: Vector3 = (MAT_POS + Vector3(0, 0.004 + STACK_H + 0.002, 0)) if idx == _stake_on_mat else e["home"]
		node.transform = node.transform.interpolate_with(Transform3D(Basis(), want), k)


## Deck i's place on the turntable as it is turned now: lying on the plate, pointing out from its middle.
func _deck_home(i: int, lift: float) -> Transform3D:
	var step := TAU / maxf(_order.size(), 1)
	var g := i * step + _angle
	var at := SUSAN_POS + Vector3(sin(g) * DECK_RING, PLATE_TOP + 0.0008 + lift, cos(g) * DECK_RING)
	return Transform3D(Basis(Vector3.UP, g), at)


## The turntable: turned by the hand at its rim, then spinning on with that swing and slowing down,
## and at last easing so that a deck lies right in front of you. A deck passing the front: a click.
func _turn_susan(delta: float) -> void:
	var n := _order.size()
	if n == 0:
		return
	var step := TAU / n
	if _spin_hand != null and is_instance_valid(_spin_hand):
		var at := to_local(_spin_hand.global_position) - SUSAN_POS
		var now := atan2(at.x, at.z)
		var turn := wrapf(now - _spin_last, -PI, PI)
		_spin_last = now
		_angle += turn
		_spin_vel = lerpf(_spin_vel, turn / maxf(delta, 0.001), 0.5) # (the swing it keeps when let go)
	else:
		_spin_hand = null
		_angle += _spin_vel * delta
		_spin_vel *= exp(-SPIN_FRICTION * delta)
		if absf(_spin_vel) < SNAP_SPEED: # slow: ease to the nearest deck in front
			var target := roundf(_angle / step) * step
			_angle = lerp_angle(_angle, target, 1.0 - exp(-6.0 * delta))
			_spin_vel = lerpf(_spin_vel, 0.0, 1.0 - exp(-6.0 * delta))
	_susan.rotation.y = _angle
	# the deck in front: its place's angle (i * step + _angle) closest to 0 (towards you)
	var front := posmod(int(roundf(-_angle / step)), n)
	if front != _front:
		if _front >= 0 and _last_hand != null:
			ticked.emit(_last_hand)
		_front = front


## Hidden objects must not be hit: an invisible body still stops the beam in Godot.
func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		var on := is_visible_in_tree()
		for b in _bodies:
			if is_instance_valid(b):
				b.collision_layer = 1 if on else 0


# ---------------------------------------------------------------- building

func _make_deck(d: Dictionary, i: int) -> Node3D:
	var node := Node3D.new()
	add_child(node)
	var unlocked: bool = d.get("unlocked", false)
	var colour: Color = deck_colour.call(str(d.get("key", ""))) if deck_colour.is_valid() else Color(0.8, 0.2, 0.2)
	if not unlocked:
		colour = colour.darkened(0.7)
	_box(node, Vector3(CARD.x, STACK_H, CARD.y), Vector3(0, STACK_H * 0.5, 0), _mat(colour, 0.6, 0.0))
	var top := Node3D.new()
	top.position.y = STACK_H + 0.0005
	top.rotation_degrees.x = -90.0 # the back of the top card, face up
	node.add_child(top)
	var sprite = d.get("sprite")
	var mat: StandardMaterial3D = null
	if sprite is Dictionary:
		mat = CardArt.material(sprite.get("atlas"), sprite.get("pos"))
	if mat != null and not unlocked:
		mat = mat.duplicate()
		mat.albedo_color = Color(0.25, 0.25, 0.25)
	CardArt.apply_layers(top, [mat] if mat != null else [], CARD, 0.0, 0.0004, 1)
	_body(node, DECK_ID - i, Vector3(CARD.x, 0.05, CARD.y), Vector3(0, 0.02, 0))
	return node


func _make_chip(s: Dictionary, index: int) -> Node3D:
	var node := Node3D.new()
	add_child(node)
	_cylinder(node, CHIP_R, CHIP_R, 0.007, Vector3(0, 0.0035, 0), _mat(Color(0.92, 0.92, 0.9), 0.5, 0.0))
	var top := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(CHIP_R * 2.0, CHIP_R * 2.0)
	top.mesh = quad
	top.rotation_degrees.x = -90.0
	top.position.y = 0.0075
	var sprite = s.get("sprite")
	if sprite is Dictionary:
		var mat := CardArt.material(sprite.get("atlas"), sprite.get("pos"))
		if mat != null:
			top.material_override = mat.duplicate() # (greyed per chip, see _refresh)
	node.add_child(top)
	node.set_meta("top", top) # (greyed in _refresh when the deck on the mat doesn't allow this stake)
	var bottom := MeshInstance3D.new() # the same print on the underside: a picked-up chip looks right from below
	bottom.mesh = quad
	bottom.rotation_degrees.x = 90.0
	bottom.position.y = -0.0005
	bottom.material_override = top.material_override
	node.add_child(bottom)
	_body(node, CHIP_ID - index, Vector3(CHIP_R * 2.2, 0.04, CHIP_R * 2.2), Vector3(0, 0.015, 0))
	return node


## The turntable's wood: turned from one piece - growth rings round its middle, a little wavy, with a
## fine grain and darker lines (in the disc's own space, so no texture coordinates are needed).
const WOOD_SHADER := """
shader_type spatial;
varying vec3 p;
float hash(vec2 v) { return fract(sin(dot(v, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 v) {
	vec2 i = floor(v); vec2 f = fract(v);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
void vertex() { p = VERTEX; }
void fragment() {
	vec2 q = p.xz;
	float wobble = noise(q * 7.0) * 0.02 + noise(q * 23.0) * 0.006;
	float r = length(q) + wobble;
	float rings = fract(r * 38.0 + noise(q * 4.0) * 0.6); // (uneven widths, like real growth rings)
	float line = smoothstep(0.0, 0.12, rings) * smoothstep(1.0, 0.75, rings);
	float grain = noise(vec2(atan(q.y, q.x) * 40.0, r * 300.0)) * 0.5 + noise(q * 160.0) * 0.5;
	vec3 light = vec3(0.56, 0.33, 0.16);
	vec3 dark = vec3(0.30, 0.15, 0.06);
	vec3 col = mix(dark, light, 0.55 + 0.45 * line);
	col *= 0.85 + 0.3 * grain;
	if (abs(p.y) < 0.0055) { col *= 0.8; } // (the edge a little darker than the top)
	ALBEDO = col;
	ROUGHNESS = 0.55 - 0.15 * line;
	SPECULAR = 0.35;
}
"""


func _build_susan() -> void:
	var base := Node3D.new() # what stays still: a dark foot under the plate
	base.position = SUSAN_POS
	add_child(base)
	_cylinder(base, SUSAN_R - 0.04, SUSAN_R - 0.03, 0.006, Vector3(0, 0.003, 0), _mat(Color(0.08, 0.06, 0.07), 0.5, 0.3))
	_susan = Node3D.new() # what turns: the plate with its gold rim, the felt, knobs to grab and a hub
	_susan.position = SUSAN_POS
	add_child(_susan)
	var gold := _mat(Color(0.88, 0.66, 0.28), 0.3, 0.75)
	# one wooden disc (its top at PLATE_TOP - nothing else lies in that plane: no flicker)
	var wood := ShaderMaterial.new()
	wood.shader = Shader.new()
	wood.shader.code = WOOD_SHADER
	var disc := _cylinder(_susan, SUSAN_R, SUSAN_R, 0.012, Vector3(0, PLATE_TOP - 0.006, 0), wood)
	(disc.mesh as CylinderMesh).radial_segments = 96
	# a gold inlay ring near the edge and the gold rim round it, both standing a little above the wood
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = SUSAN_R - 0.004
	tm.outer_radius = SUSAN_R + 0.004
	tm.rings = 96
	ring.mesh = tm
	ring.material_override = gold
	ring.position.y = PLATE_TOP - 0.002
	ring.scale = Vector3(1, 0.6, 1)
	_susan.add_child(ring)
	var inlay := MeshInstance3D.new()
	var im := TorusMesh.new()
	im.inner_radius = SPIN_GRAB_MIN - 0.002 # (the gold ring: outside it you hold the plate, inside are the decks)
	im.outer_radius = SPIN_GRAB_MIN + 0.002
	im.rings = 96
	inlay.mesh = im
	inlay.material_override = gold
	inlay.position.y = PLATE_TOP
	inlay.scale = Vector3(1, 0.2, 1)
	_susan.add_child(inlay)
	_cylinder(_susan, 0.05, 0.055, 0.012, Vector3(0, PLATE_TOP + 0.004, 0), gold) # the hub
	var knob_mat := _mat(Color(0.95, 0.75, 0.35), 0.25, 0.8)
	for i in 12: # little knobs round the rim: hold one and turn
		var a := TAU * i / 12.0
		var knob := _cylinder(_susan, 0.009, 0.011, 0.012, Vector3(sin(a) * (SUSAN_R - 0.004), PLATE_TOP + 0.005, cos(a) * (SUSAN_R - 0.004)), knob_mat)
		knob.name = "Knob%d" % i
	var l := _label(_susan, "SPIN ME", 26, 0.0006, Color(1.0, 0.85, 0.45), Vector3(0, PLATE_TOP + 0.0115, 0))
	l.rotation_degrees.x = -90.0


func _build_mat() -> void:
	var root := Node3D.new()
	root.position = MAT_POS
	add_child(root)
	# red felt in a gold frame (no green: it would vanish in the Green background)
	_box(root, Vector3(0.16, 0.003, 0.2), Vector3(0, 0.0015, 0), _mat(Color(0.85, 0.65, 0.25), 0.3, 0.8))
	_box(root, Vector3(0.148, 0.004, 0.188), Vector3(0, 0.002, 0), _mat(Color(0.35, 0.05, 0.07), 0.9, 0.0))
	# "YOUR DECK" lying beside the mat, on its left (its front edge is the table's edge)
	var l := _label(root, "YOUR DECK", 26, 0.0006, Color(1.0, 0.8, 0.4), Vector3(-0.135, 0.0045, 0.0))
	l.rotation_degrees.x = -90.0


func _build_start() -> void:
	var root := Node3D.new()
	root.position = START_POS
	add_child(root)
	_cylinder(root, 0.075, 0.08, 0.03, Vector3(0, 0.015, 0), _mat(Color(0.08, 0.08, 0.09), 0.4, 0.6))
	_start_cap = MeshInstance3D.new()
	var dome := SphereMesh.new()
	dome.radius = 0.06
	dome.height = 0.06
	dome.is_hemisphere = true
	_start_cap.mesh = dome
	_start_mat = _mat(Color(0.35, 0.3, 0.3), 0.25, 0.1)
	_start_mat.emission_enabled = true
	_start_mat.emission = Color(1.0, 0.15, 0.1)
	_start_cap.material_override = _start_mat
	_start_cap.position.y = 0.03
	root.add_child(_start_cap)
	_label(root, "START", 56, 0.001, Color(1.0, 0.95, 0.85), Vector3(0, 0.12, 0.02))
	_body(root, START_ID, Vector3(0.16, 0.1, 0.16), Vector3(0, 0.04, 0))


func _build_back() -> void:
	var root := Node3D.new()
	root.position = BACK_POS
	add_child(root)
	_box(root, Vector3(0.006, 0.07, 0.006), Vector3(0, 0.035, 0), _mat(Color(0.2, 0.2, 0.22), 0.5, 0.5))
	_box(root, Vector3(0.12, 0.06, 0.014), Vector3(0, 0.1, 0), _mat(Color(0.05, 0.03, 0.06), 0.5, 0.0))
	var l := _label(root, "BACK", 44, 0.0008, Color(1.6, 1.2, 0.5), Vector3(0, 0.1, 0.0075))
	l.outline_size = 8
	_body(root, BACK_ID, Vector3(0.13, 0.08, 0.04), Vector3(0, 0.1, 0))


func _build_sign(text: String, id: int, at: Vector3, colour: Color) -> void:
	var root := Node3D.new()
	root.position = at
	add_child(root)
	_box(root, Vector3(0.006, 0.07, 0.006), Vector3(0, 0.035, 0), _mat(Color(0.2, 0.2, 0.22), 0.5, 0.5))
	_box(root, Vector3(0.14, 0.075, 0.014), Vector3(0, 0.105, 0), _mat(Color(0.05, 0.03, 0.06), 0.5, 0.0))
	var l := _label(root, text, 36, 0.0008, colour, Vector3(0, 0.105, 0.0075))
	l.outline_size = 8
	_body(root, id, Vector3(0.15, 0.09, 0.04), Vector3(0, 0.105, 0))


func _body(parent: Node3D, id: int, size: Vector3, pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.set_meta("target_id", id)
	body.set_meta("kind", "setup")
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	shape.shape = bs
	body.add_child(shape)
	body.position = pos
	body.collision_layer = 1 if is_visible_in_tree() else 0
	parent.add_child(body)
	_bodies.append(body)


func _label(parent: Node3D, text: String, size: int, pixel: float, colour: Color, pos: Vector3) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = pixel
	l.modulate = colour
	l.outline_size = 6
	l.outline_modulate = Color(0.05, 0.03, 0.06)
	l.position = pos
	parent.add_child(l)
	return l


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _cylinder(parent: Node3D, top: float, bottom: float, height: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = height
	mi.mesh = c
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _mat(colour: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = rough
	m.metallic = metal
	return m
