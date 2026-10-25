class_name MainMenuVR
extends Node3D
## The main menu in VR: the casino table itself is the menu, instead of the game's flat panel.
##   PLAY      a big red buzzer: point at it and pull the trigger, or slap it with your hand
##   CONTINUE  the saved run's deck as a stack of cards (only when there is a saved run)
##   COLLECTION a card album, OPTIONS a reception bell, a YouTube sign
##   QUIT ONLY VR / QUIT VR AND GAME  two exit signs at the back
##   SOLATRO   a little spread of cards on felt: the solo card game, played on its own (SolatroGame)
## A name plate shows the profile (point at it and pull the trigger: the game's profile select) (the BALATRO in VR sign is on the back wall). Positions are in the joker board's space (x right, +z towards you, y up), so the
## menu sits where the board is calibrated. main.gd turns presses into commands for the game.

signal pressed(action: String)

const ACTIONS := ["play", "continue", "collection", "options", "youtube", "quit_vr", "quit_both", "solatro", "profile"]
const BASE_ID := -300              # target ids of the objects: BASE_ID - index in ACTIONS
const TOUCH_RADIUS := 0.07         # a hand this close to the buzzer's top presses it
const CARD := Vector2(0.071, 0.095)
const VERSION := "1.01"       # shown at the front edge of the menu table

var hands: Array = []              # XRController3D: hands that can slap the buzzer

var _bodies := {}                  # action -> StaticBody3D
var _cap: MeshInstance3D           # the buzzer's red dome
var _cap_rest := 0.0
var _press_t := 0.0                # > 0 while the buzzer is pushed down
var _armed := {}                   # hand -> may press again (it left the buzzer since)
var _continue_root: Node3D
var _continue_top: Node3D          # the back of the top card
var _continue_sides: StandardMaterial3D
var _continue_label: Label3D
var _profile_label: Label3D
var _has_save := false
var _exit_labels := {}             # action -> [Label3D, its normal text]
var _solatro_cards: Array = []     # [node, rank column, suit row] of the cards on the Solatro felt
var _solatro_art := false


func _ready() -> void:
	_build_buzzer(Vector3(0.0, 0.0, -0.02))
	_build_continue(Vector3(-0.34, 0.0, -0.02))
	_build_album(Vector3(0.34, 0.0, -0.08))
	_build_bell(Vector3(-0.46, 0.0, -0.36))
	_build_youtube(Vector3(-0.16, 0.0, -0.36))
	_build_exit("QUIT\nONLY VR", "quit_vr", Vector3(0.15, 0.0, -0.36), Color(0.75, 0.35, 1.0))
	_build_exit("QUIT VR\nAND GAME", "quit_both", Vector3(0.45, 0.0, -0.36), Color(1.0, 0.3, 0.3))
	_build_name_plate(Vector3(0.0, 0.0, 0.17))
	_build_solatro(Vector3(0.34, 0.0, 0.12))
	_build_version(Vector3(-0.34, 0.0, 0.19))
	GameFont.apply_to(self)


## What the game tells about the menu: the saved run and the profile name.
func sync(menu: Dictionary, deck_colour: Callable) -> void:
	var saved = menu.get("saved")
	_has_save = saved is Dictionary
	_continue_root.visible = _has_save
	_enable(_bodies["continue"], _has_save and is_visible_in_tree())
	if _has_save:
		_continue_label.text = "CONTINUE\nAnte %d · Round %d" % [int(saved.get("ante", 1)), int(saved.get("round", 1))]
		_continue_sides.albedo_color = deck_colour.call(str(saved.get("deck_key", "")))
		var sprite = saved.get("sprite")
		var mat: StandardMaterial3D = null
		if sprite is Dictionary:
			mat = CardArt.material(sprite.get("atlas"), sprite.get("pos"))
		CardArt.apply_layers(_continue_top, [mat] if mat != null else [], CARD, 0.0, 0.0004, 1)
	var name := str(menu.get("profile", ""))
	_profile_label.text = ("PLAYER: " + name) if name != "" else "PLAYER"
	if not _solatro_art and CardArt.has_atlas("cards_1") and CardArt.has_atlas("centers"):
		_solatro_art = true # the card pictures arrived: the Solatro cards get their faces
		for c in _solatro_cards:
			var layers := [CardArt.material("centers", [1, 0]), CardArt.material("cards_1", [c[1], c[2]])]
			CardArt.apply_layers(c[0], layers, CARD * 0.8, 0.0002, 0.0002, 2)
	GameFont.apply_to(self)


## Achievement reward "Safe Travels": the exit signs say goodbye like UnderTheVRadar does.
func set_safe_travels(on: bool) -> void:
	var texts := {"quit_vr": "SAFE TRAVELS!\n(QUIT VR)", "quit_both": "SAFE TRAVELS!\n(QUIT ALL)"}
	for action in _exit_labels:
		var l: Label3D = _exit_labels[action][0]
		l.text = texts[action] if on else str(_exit_labels[action][1])
		l.font_size = 30 if on else 40
	GameFont.apply_to(self)


func action_for(id: int) -> String:
	var i := BASE_ID - id
	return ACTIONS[i] if i >= 0 and i < ACTIONS.size() else ""


func press(action: String) -> void:
	if action == "":
		return
	if action == "play":
		_press_t = 0.18 # the dome goes down for a moment
	pressed.emit(action)


func _process(delta: float) -> void:
	if not visible:
		return
	if _press_t > 0.0:
		_press_t = maxf(_press_t - delta, 0.0)
	_cap.position.y = _cap_rest - (0.012 if _press_t > 0.0 else 0.0)
	# slapping the buzzer with a hand
	var top := _cap.global_position + global_basis.y.normalized() * 0.035
	for hand in hands:
		if hand == null or not is_instance_valid(hand) or not hand.is_inside_tree():
			continue
		var d: float = (hand as Node3D).global_position.distance_to(top)
		if d < TOUCH_RADIUS and _armed.get(hand, true):
			_armed[hand] = false
			press("play")
		elif d > TOUCH_RADIUS * 1.8:
			_armed[hand] = true


## Hidden objects must not be hit: an invisible body still stops the beam in Godot.
func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		var on := is_visible_in_tree()
		for action in _bodies:
			_enable(_bodies[action], on and (action != "continue" or _has_save))


func _enable(body: StaticBody3D, on: bool) -> void:
	body.collision_layer = 1 if on else 0


# ---------------------------------------------------------------- the objects

func _build_buzzer(at: Vector3) -> void:
	var root := _holder(at)
	_cylinder(root, 0.09, 0.095, 0.035, Vector3(0, 0.0175, 0), _mat(Color(0.08, 0.08, 0.09), 0.4, 0.6))
	_cylinder(root, 0.082, 0.082, 0.006, Vector3(0, 0.038, 0), _mat(Color(0.85, 0.65, 0.25), 0.3, 0.8)) # brass ring
	_cap = MeshInstance3D.new()
	var dome := SphereMesh.new()
	dome.radius = 0.07
	dome.height = 0.07
	dome.is_hemisphere = true
	_cap.mesh = dome
	var red := _mat(Color(0.9, 0.08, 0.06), 0.25, 0.1)
	red.emission_enabled = true
	red.emission = Color(1.0, 0.15, 0.1)
	red.emission_energy_multiplier = 0.6
	_cap.material_override = red
	_cap_rest = 0.04
	_cap.position.y = _cap_rest
	root.add_child(_cap)
	_label(root, "PLAY", 64, 0.001, Color(1.0, 0.95, 0.85), Vector3(0, 0.13, 0.03))
	_body(root, "play", Vector3(0.19, 0.12, 0.19), Vector3(0, 0.05, 0))


func _build_continue(at: Vector3) -> void:
	_continue_root = _holder(at)
	_continue_sides = _mat(Color(0.8, 0.2, 0.2), 0.6, 0.0)
	var stack := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(CARD.x, 0.03, CARD.y)
	stack.mesh = box
	stack.material_override = _continue_sides
	stack.position.y = 0.015
	_continue_root.add_child(stack)
	_continue_top = Node3D.new()
	_continue_top.position.y = 0.0305
	_continue_top.rotation_degrees.x = -90.0 # lying on top of the stack, face up
	_continue_root.add_child(_continue_top)
	_continue_label = _label(_continue_root, "CONTINUE", 44, 0.0009, Color(1.0, 0.85, 0.4), Vector3(0, 0.12, 0))
	_body(_continue_root, "continue", Vector3(0.12, 0.1, 0.14), Vector3(0, 0.04, 0))


func _build_album(at: Vector3) -> void:
	var root := _holder(at)
	root.rotation_degrees.y = -12.0
	_box(root, Vector3(0.13, 0.035, 0.17), Vector3(0, 0.0175, 0), _mat(Color(0.4, 0.08, 0.1), 0.7, 0.0)) # cover (red leather: green would vanish in the Green background)
	_box(root, Vector3(0.124, 0.03, 0.164), Vector3(0.004, 0.0175, 0), _mat(Color(0.93, 0.9, 0.82), 0.9, 0.0)) # pages
	_box(root, Vector3(0.012, 0.037, 0.17), Vector3(-0.065, 0.0185, 0), _mat(Color(0.28, 0.05, 0.07), 0.6, 0.0)) # spine
	var title := _label(root, "COLLECTION", 28, 0.0006, Color(0.95, 0.8, 0.35), Vector3(0, 0.0356, 0))
	title.rotation_degrees.x = -90.0 # printed on the cover
	_label(root, "COLLECTIONS\nAND STATS", 36, 0.0009, Color(1.0, 0.85, 0.5), Vector3(0, 0.13, 0))
	_body(root, "collection", Vector3(0.15, 0.1, 0.19), Vector3(0, 0.04, 0))


func _build_bell(at: Vector3) -> void:
	var root := _holder(at)
	var brass := _mat(Color(0.88, 0.68, 0.3), 0.25, 0.9)
	_cylinder(root, 0.05, 0.055, 0.01, Vector3(0, 0.005, 0), _mat(Color(0.1, 0.08, 0.06), 0.5, 0.2))
	var dome := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.04
	s.height = 0.04
	s.is_hemisphere = true
	dome.mesh = s
	dome.material_override = brass
	dome.position.y = 0.01
	root.add_child(dome)
	_cylinder(root, 0.006, 0.006, 0.014, Vector3(0, 0.057, 0), brass) # the plunger
	_label(root, "OPTIONS", 44, 0.0009, Color(1.0, 0.75, 0.35), Vector3(0, 0.12, 0))
	_body(root, "options", Vector3(0.12, 0.1, 0.12), Vector3(0, 0.04, 0))


func _build_youtube(at: Vector3) -> void:
	var root := _holder(at)
	_box(root, Vector3(0.006, 0.07, 0.006), Vector3(0, 0.035, 0), _mat(Color(0.2, 0.2, 0.22), 0.5, 0.5)) # post
	var sign := _mat(Color(1.0, 0.0, 0.0), 0.4, 0.0)
	sign.emission_enabled = true
	sign.emission = Color(1.0, 0.1, 0.1)
	sign.emission_energy_multiplier = 0.5
	_box(root, Vector3(0.15, 0.065, 0.012), Vector3(0, 0.1, 0), sign)
	_label(root, "YouTube", 48, 0.0009, Color(1, 1, 1), Vector3(0, 0.1, 0.0065))
	_label(root, "Please subscribe to\nUnderTheVRadar", 28, 0.0007, Color(1.0, 0.85, 0.4), Vector3(0, 0.165, 0))
	_body(root, "youtube", Vector3(0.16, 0.08, 0.04), Vector3(0, 0.1, 0))


func _build_exit(text: String, action: String, at: Vector3, colour: Color) -> void:
	var root := _holder(at)
	_box(root, Vector3(0.006, 0.07, 0.006), Vector3(0, 0.035, 0), _mat(Color(0.2, 0.2, 0.22), 0.5, 0.5))
	_box(root, Vector3(0.17, 0.075, 0.014), Vector3(0, 0.105, 0), _mat(Color(0.05, 0.03, 0.06), 0.5, 0.0))
	var glow := _label(root, text, 40, 0.0008, Color(colour.r * 2.2, colour.g * 2.2, colour.b * 2.2), Vector3(0, 0.105, 0.0075))
	glow.width = 0.16 / glow.pixel_size # (stays on the sign)
	glow.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_exit_labels[action] = [glow, text]
	glow.outline_size = 8
	glow.outline_modulate = Color(colour.r * 0.2, colour.g * 0.2, colour.b * 0.2)
	_body(root, action, Vector3(0.18, 0.09, 0.04), Vector3(0, 0.105, 0))


func _build_name_plate(at: Vector3) -> void:
	var root := _holder(at)
	root.rotation_degrees.x = -60.0 # tipped towards you, like a desk name plate
	_box(root, Vector3(0.2, 0.035, 0.004), Vector3(0, 0.018, 0), _mat(Color(0.85, 0.66, 0.3), 0.3, 0.8))
	_profile_label = _label(root, "PLAYER", 36, 0.0006, Color(0.15, 0.08, 0.02), Vector3(0, 0.018, 0.0025))
	_profile_label.outline_size = 0
	var change := _label(root, "CHANGE PROFILE", 28, 0.0006, Color(1.0, 0.85, 0.45), Vector3(0, 0.047, 0.0025))
	change.outline_size = 4
	_body(root, "profile", Vector3(0.22, 0.06, 0.03), Vector3(0, 0.025, 0))


## The mod's version, printed small on the felt at the front edge of the table.
func _build_version(at: Vector3) -> void:
	var root := _holder(at)
	var l := _label(root, VERSION, 30, 0.0006, Color(1.0, 0.85, 0.5, 0.8), Vector3(0, 0.001, 0))
	l.rotation_degrees.x = -90.0 # lying on the table, readable from your seat
	l.outline_size = 4


## A green felt with a fanned spread of cards (Ace of Spades, King of Hearts ...): SOLATRO.
func _build_solatro(at: Vector3) -> void:
	var root := _holder(at)
	root.rotation_degrees.y = -10.0
	_box(root, Vector3(0.2, 0.004, 0.12), Vector3(0, 0.002, 0), _mat(Color(0.1, 0.32, 0.2), 0.9, 0.0)) # felt
	var spread := [[12, 3], [11, 0], [10, 1], [9, 2]] # A of Spades, K of Hearts, Q of Clubs, J of Diamonds
	for i in spread.size():
		var card := Node3D.new()
		card.position = Vector3(-0.054 + i * 0.036, 0.0045 + i * 0.0008, 0.0)
		card.rotation_degrees = Vector3(-90.0, 0.0, (1.5 - i) * 8.0) # lying face up, fanned
		root.add_child(card)
		_box(card, Vector3(CARD.x * 0.8, CARD.y * 0.8, 0.0004), Vector3.ZERO, _mat(Color(0.95, 0.93, 0.88), 0.8, 0.0)) # (until the art is there)
		_solatro_cards.append([card, spread[i][0], spread[i][1]])
	_label(root, "SOLATRO", 52, 0.0009, Color(0.5, 1.8, 0.9), Vector3(0, 0.085, 0.03))
	_label(root, "game idea by TechDweeb", 26, 0.0007, Color(1.0, 0.85, 0.5), Vector3(0, 0.055, 0.03))
	_body(root, "solatro", Vector3(0.21, 0.1, 0.13), Vector3(0, 0.04, 0))


# ---------------------------------------------------------------- helpers

func _holder(at: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = at
	add_child(n)
	return n


func _body(parent: Node3D, action: String, size: Vector3, pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.set_meta("target_id", BASE_ID - ACTIONS.find(action))
	body.set_meta("kind", "menu")
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	shape.shape = bs
	body.add_child(shape)
	body.position = pos
	parent.add_child(body)
	_bodies[action] = body


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
