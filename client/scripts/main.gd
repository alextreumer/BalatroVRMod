extends Node3D
# Balatro in VR – the client.
# The Balatro mod connects to this program over TCP and mirrors the complete game UI;
# this script lays it out around the player in VR and sends clicks/hovers/gestures back.
#
# Layout (all relative to the player, set with Y):
#   board in front · run panel on the right (the left hand holds the cards) · shop flat on the table ·
#   joker board on the table with the augmented jokers on pedestals and the 3D draw pile
#   (hover with a hand = "View Deck") · spinning blind chip in front of you.
#
# VR (Quest 3 over Virtual Desktop):
#   Right controller: aim with the blue beam, Trigger = click, Grip near the left hand = grab the
#   selected cards (release at the chip = play, behind the shoulder = discard), A = play, B = discard.
#   Pointing at a card for a moment shows its tooltip.
#   Left controller: holds the hand. Y = move everything in front of you, X = switch background
#   (passthrough / green for Virtual Desktop's chroma key / virtual room), Menu = layout calibration.
# Desktop test (no headset): left click = click, right mouse button held on a card = tooltip,
#   P = play, D = discard, B = switch background, C = calibration on/off.

const PORT := 27801
const HOST := "127.0.0.1"

const CARD_SIZE := Vector3(0.08, 0.107, 0.004)  # same 71:95 aspect as the game's card art
const FAN_RADIUS := 0.32                        # cards sit on an arc of this radius (meters) ...
const FAN_ANGLE := 9.0                          # ... turned this much apart (≈ 5 cm between cards)
const FAN_TILT := -70.0                         # the fan leans back towards the player (degrees)
const FAN_SELECT_LIFT := 0.025                  # selected cards slide out of the fan by this much
const HAND_GRAB_RADIUS := 0.12                  # right hand this close to a selected card = grab
const HAND_OFFSET := Vector3(0.0, 0.0, -0.05)   # fan position relative to the controller holding it
const TOOLTIP_SCALE := 0.5                      # tooltips above hand cards are shown at half size

const BOARD_DISTANCE := 1.0                     # board center in front of the head (meters)
const BOARD_HALF_WIDTH := 0.6                   # 20 room units * Board.SCALE / 2
const TABLE_Y := -0.5                           # table height relative to the board center
const SHOULDER_RADIUS := 0.6

# Default layout (relative to the layout frame; the player can change and save it, see calibration)
const PANEL_POS := Vector3(BOARD_HALF_WIDTH + 0.12, 0.0, 0.2)  # run panel right of the board
const PANEL_YAW := -25.0
const PANEL_SCALE := 0.75
const SHOP_POS := Vector3(0, TABLE_Y, 0.4)
const SHOP_SIGN_SIZE := Vector2(0.264, 0.132)  # the game's 4.4 x 2.2 sign at board scale
const SHOP_SIGN_DISTANCE := 0.26                # behind the shop's far edge (meters)
const SHOP_SIGN_HEIGHT := 0.07                  # lifted above the table
const SHOP_SIGN_TILT := 60.0                    # leaning back, facing the player
const SHOP_SIGN_FPS := 8.0
const CHIP_POS := Vector3(0, -0.12, 0.55)       # in front of the player, a bit below eye level

# Joker board: a flat mat for the real table; the jokers (on pedestals) and the draw pile live on it
const JOKER_TABLE_POS := Vector3(0.6, TABLE_Y, 0.25) # on the table right of the shop
const JOKER_TABLE_SIZE := Vector2(0.925, 0.45)  # width x depth (meters): jokers in the middle, reroll machine and coin slot at the ends
const JOKER_TABLE_TOP := 0.012                  # height of the mat surface
const JOKER_TABLE_MARGIN := 0.05                # keeps pedestals/pile inside the mat when moved
const JOKER_SLOTS := 8                          # anchor points; slot N = N-th joker in the game
const JOKER_COLUMNS := 4                        # two rows of four: slots 1-4 at the back, 5-8 in front
const JOKER_SPACING := 0.13                     # between pedestals in a row
const JOKER_ROW_DEPTH := 0.13                   # between the two rows
const JOKER_ROW_Z := -0.12                      # back row
const JOKER_SCENES := "res://jokers/%s.tscn"    # one scene per joker key, e.g. j_castle.tscn
const DECK_POS := Vector3(0.22, JOKER_TABLE_TOP, 0.13) # draw pile at the front right corner of the mat
const COINS_POS := Vector3(-0.2, JOKER_TABLE_TOP, 0.14) # money at the front left corner
const PEDESTAL_HEIGHT := 0.019                  # jokers stand on top of their wooden pedestal

const CHIP_RADIUS := 0.045                      # visual size of the blind chip
const ROUND_STATES := ["SELECTING_HAND", "HAND_PLAYED", "DRAW_TO_HAND"] # chip only while a blind is being played
const CHIP_HIT_RADIUS := 0.13                   # how close the hand must be to "lay cards on it"
const LAYOUT_FILE := "user://vr_layout.cfg"
const LAYOUT_VERSION := 3                       # v2: pile + slots on the joker board, v3: board reshaped (0.5 x 0.6)
const CALIB_GRAB_RADIUS := 0.15

const DECK_CARD := Vector2(0.063, 0.088)        # real playing card size (meters)
const DECK_CARD_THICKNESS := 0.0011             # per card in the pile
const DECK_HOVER_RADIUS := 0.09

const HOVER_DELAY := 0.15                       # seconds of pointing before a tooltip is requested
const BALATRO_CHECK_INTERVAL := 1.5             # seconds between "is Balatro.exe running?" checks
const BEAM_LENGTH := 4.0                        # pointer beam / ray reach when it hits nothing (meters)
const REORDER_AREAS := ["hand", "jokers"]       # rows whose order matters for scoring (left to right)
const DRAG_GHOST_SIZE := Vector2(0.05, 0.067)   # small copy of the dragged card at the pointer

# Deck colour for the sides of the 3D pile (the top shows the real back art)
const DECK_COLORS := {
	"b_red": Color(0.8, 0.2, 0.2), "b_blue": Color(0.2, 0.4, 0.85), "b_yellow": Color(0.95, 0.75, 0.2),
	"b_green": Color(0.25, 0.65, 0.35), "b_black": Color(0.15, 0.15, 0.18), "b_magic": Color(0.55, 0.3, 0.8),
	"b_nebula": Color(0.25, 0.25, 0.55), "b_ghost": Color(0.75, 0.85, 0.9), "b_abandoned": Color(0.5, 0.5, 0.5),
	"b_checkered": Color(0.6, 0.25, 0.5), "b_zodiac": Color(0.15, 0.2, 0.45), "b_painted": Color(0.9, 0.5, 0.7),
	"b_anaglyph": Color(0.3, 0.75, 0.8), "b_plasma": Color(0.6, 0.3, 0.85), "b_erratic": Color(0.9, 0.45, 0.15),
}

enum Backdrop { PASSTHROUGH, GREEN, ROOM }

var _server := TCPServer.new()
var _peer: StreamPeerTCP
var _rx := PackedByteArray()
var _connected := false
var _cmd_id := 0
var _last_scene := {}
var _state := {}

var _vr := false
var _xr: XRInterface
var _camera: Camera3D
var _head: XRCamera3D
var _left: XRController3D
var _right: XRController3D
var _point: XRController3D    # beam, clicks, grabbing & gestures (right hand; left in left-handed mode)
var _holder: XRController3D   # holds the fan of cards (the other hand)
var _beam: MeshInstance3D
var _fan_anchor: Node3D       # where the fan sits on the card hand (calibratable, relative to that hand)
var _grab_anchor: Node3D      # where grabbed cards sit in the pointing hand (calibratable)
var _calib_hand: XRController3D # the hand holding the calibration handle
var _left_handed := false
var _ray: RayCast3D
var _reticle: MeshInstance3D

var _layout: Node3D           # yaw-only frame in front of the player; everything hangs off it
var _board: Board
var _status: Label
var _status3d: Label3D
var _casino: CasinoRoom       # virtual casino when there is no passthrough
var _sun: DirectionalLight3D
var _env: Environment
var _backdrop := Backdrop.ROOM
var _layout_placed := false

# Balatro boot: it loads all assets before mods (and our bridge) start, so we watch for the
# process itself and show flying cards until the game's main menu is up.
var _intro: IntroCards
var _stars: StarField         # twinkling stars in the room (Planet cards, star jokers)
const STAR_JOKERS := ["j_supernova", "j_satellite", "j_constellation"] # keep the room twinkling
var _confetti: Confetti       # raining down on run won / game over
const CONFETTI_WON := 10.0    # seconds of confetti for a won run ...
const CONFETTI_LOST := 6.0    # ... and for game over
var _last_end := ""           # "", "won" or "lost" – confetti only when this changes
var _was_in_state := false    # no confetti for the very first state (e.g. reconnecting on the Game Over screen)
var _balatro_running := false
var _proc_thread: Thread
var _proc_timer := 0.0

var _shop_sign: Node3D        # animated SHOP sign at the shop
var _shop_sign_info := {}     # {"atlas": ..., "frames": n} while the shop is open
var _chip: Node3D             # placed by layout/calibration
var _chip_spinner: Node3D     # spins and bobs inside _chip
var _chip_front: Node3D
var _chip_back: Node3D
var _chip_time := 0.0

var _deck: Node3D
var _deck_body: MeshInstance3D
var _deck_top: Node3D
var _deck_label: Label3D
var _coins: CoinPile           # the player's money as gold coins on the joker board
var _deck_height := 0.0
var _shuffle_t := -1.0            # >= 0: the deck is being shuffled (start of a round)
var _shuffle_next_card := 0.0
var _shuffle_halves: Array = []   # the two halves of the deck while shuffling
const SHUFFLE_TIME := 0.9
var _deck_target_height := 0.0
var _deck_hover := false

var _joker_table: Node3D
var _joker_mat: Node3D        # the visible mat; only shown while calibrating
var _joker_slots: Array[Node3D] = []
var _jokers := {}             # joker uid -> pedestal node (with the AugmentedJoker model on top)
var _held_joker := -1         # uid of the joker picked up with a grip (-1 = none)
var _held_joker_uid_last := -1
var _pending_order: Array = [] # joker order (uids) we asked the game for, until it confirms
var _pending_time := 0.0
var _rng_board := RandomNumberGenerator.new()
const JOKER_CARD_SIZE := Vector2(0.06, 0.08) # a joker without a 3D model shows its card this big
var _held_hand: XRController3D
var _held_offset := Transform3D()
var _joker_scenes := {}       # joker key -> PackedScene (or null if that joker has no 3D model)

var _hand_cards := {}         # scene id -> StaticBody3D in the left hand
var _hand_items: Array = []   # latest hand card items from the scene
var _hand_flames: Array = []  # the score's burning flames (chips / mult) – the hand burns with them

var _hover_id := -1
var _hover_kind := ""
var _hover_time := 0.0
var _hover_sent := false
var _hover_area := ""

# Reordering: hold the trigger on a hand card or joker, point at another one of the same row, release
var _drag_id := -1
var _drag_area := ""
# Card whose place the dragged one would take. Sticky while the pointer is over the dragged card
# itself: the fan preview moves the dragged card under the pointer, which must not undo the preview.
var _drop_target := -1
var _drag_armed := false        # held long enough: the press is a drag, not a tap
var _drag_pressed_at := 0.0
const DRAG_HOLD := 0.2          # seconds: shorter presses are taps (select)
var _hl_pending := {}           # hand card id -> [selected, time]: our click, until the game shows it
var _drag_ghost: Node3D       # card copy following the pointer while dragging
var _pointer_point := Vector3.ZERO
var _pointer_valid := false

var _grab_active := false
var _grabbed: Array = []

# Calibration: the player moves/rotates/resizes these and the result is saved
var _calib_items := {}        # name -> Node3D
var _calib_defaults := {}     # name -> Transform3D (local)
var _calib_on_table := {}     # names that may only slide over the joker board
var _calibrating := false
var _calib_grabbed := ""
var _calib_offset := Transform3D()
var _calib_scale := 1.0
var _calib_help: Label3D


func _ready() -> void:
	_vr = _start_xr()
	_setup_room_bus()
	get_tree().node_added.connect(_on_node_added)
	_build_scene()
	var port := int(OS.get_environment("BALATRO_VR_PORT")) if OS.get_environment("BALATRO_VR_PORT") != "" else PORT # tests run on another port
	var err := _server.listen(port, HOST)
	if err != OK:
		_set_status("Port %d is in use (error %d)" % [port, err])
		push_error(_status.text)


func _exit_tree() -> void:
	if _peer != null:
		_peer.disconnect_from_host()
	_server.stop()
	if _proc_thread != null:
		_proc_thread.wait_to_finish()


# ---------------------------------------------------------------- Balatro start-up (flying cards)

func _poll_balatro_process(delta: float) -> void:
	if OS.get_name() != "Windows":
		return
	if _proc_thread != null and not _proc_thread.is_alive():
		_balatro_running = _proc_thread.wait_to_finish()
		_proc_thread = null
	if _connected:
		_balatro_running = true
		return
	_proc_timer -= delta
	if _proc_timer > 0.0 or _proc_thread != null:
		return
	_proc_timer = BALATRO_CHECK_INTERVAL
	_proc_thread = Thread.new() # tasklist takes ~0.1 s: never on the render thread
	_proc_thread.start(_is_balatro_running)


func _is_balatro_running() -> bool:
	var output: Array = []
	OS.execute("tasklist", ["/FI", "IMAGENAME eq Balatro.exe", "/NH"], output)
	return output.size() > 0 and str(output[0]).to_lower().contains("balatro.exe")


## The game counts as ready once it sends anything past its own splash screen (usually the main menu).
func _game_ready() -> bool:
	return _connected and not _last_scene.is_empty() and str(_last_scene.get("state_name", "")) != "SPLASH"


func _update_intro() -> void:
	_intro.set_active((_balatro_running or _connected) and not _game_ready())
	_status3d.visible = not _connected and not _intro.is_showing()


func _process(delta: float) -> void:
	_poll_network()
	_poll_balatro_process(delta)
	_update_intro()
	_stars.global_position = _head.global_position if _vr else _camera.global_position # around the player
	_confetti.follow(_stars.global_position)
	if _casino.visible: # the card table stays under the shop and jokers, at the Joker Board's height
		_casino.place_table(_layout.global_transform, _joker_table.global_position.y)
	_animate_chip(delta)
	_animate_shop_sign()
	_animate_deck(delta)
	_animate_jokers(delta)
	_update_held_joker()
	_animate_table_fun(delta)
	_animate_game_feel(delta)
	_animate_run_end(delta)
	_update_drag_hold()
	_update_drag_feedback()
	if _vr:
		if not _layout_placed and _head.global_position.y > 0.5:
			_place_layout()
		_update_pointer(_ray_target(), delta)
		if _calibrating:
			_update_calibration(delta)
			return
		_update_deck_hover()
		if _grab_active:
			_update_bundle()


# ---------------------------------------------------------------- network (TCP, one JSON per line)

func _poll_network() -> void:
	if _server.is_connection_available():
		_peer = _server.take_connection()
		_peer.set_no_delay(true)
		_rx.clear()
	if _peer == null:
		_set_connected(false)
		return

	_peer.poll()
	var status := _peer.get_status()
	if status != StreamPeerTCP.STATUS_CONNECTED:
		if status == StreamPeerTCP.STATUS_NONE or status == StreamPeerTCP.STATUS_ERROR:
			_peer = null
			_set_connected(false)
		return
	_set_connected(true)

	var available := _peer.get_available_bytes()
	if available > 0:
		var result: Array = _peer.get_partial_data(available)
		if result[0] == OK:
			_rx.append_array(result[1])

	# Only the newest scene per frame matters; everything else is handled in order.
	var latest_scene := ""
	var start := 0
	while true:
		var nl := _rx.find(10, start)
		if nl < 0:
			break
		var line := _rx.slice(start, nl).get_string_from_utf8()
		start = nl + 1
		if line.begins_with('{"type":"scene"'):
			latest_scene = line
		else:
			_handle_message(line)
	if start > 0:
		_rx = _rx.slice(start)
	if latest_scene != "":
		_handle_message(latest_scene)


func _handle_message(line: String) -> void:
	var msg = JSON.parse_string(line)
	if typeof(msg) != TYPE_DICTIONARY:
		return
	match msg.get("type", ""):
		"scene":
			_apply_scene(msg["data"])
		"state":
			_apply_state(msg["data"])
		"event":
			match msg["data"].get("event", ""):
				"calibrate":
					_set_calibrating(true) # "Adjust VR Layout" in the game's Options menu
				"toggle_handedness":
					_set_left_handed(not _left_handed) # "VR: Switch Hands" in the game's Options menu
				"toggle_calm":
					_set_calm(not _calm) # "VR: Calm Lights" in the game's Options menu
				"toggle_ambience":
					_set_ambience(not _ambience_on) # "VR: Casino Sounds" in VR Settings
				"toggle_hands":
					_set_hands(not _hands_on) # "VR: Hands" in the game's Options menu
				"cycle_spectator":
					_cycle_spectator() # "VR: Spectator" in the game's Options menu
				"show_tutorial":
					_show_tutorial() # "VR: Show Tips" in the game's Options menu
				"quit_vr":
					get_tree().quit() # "QUIT VR" in the game's main menu; Balatro keeps running
				"shop_buy", "card_used":
					if str(msg["data"].get("set", "")) == "Planet":
						_stars.burst() # a Planet card bought or taken from a pack: stars all over the room
					elif str(msg["data"].get("set", "")) == "Spectral":
						_casino.spectral_flicker() # the Spectral Lounge's sign haunts for a moment
					if msg["data"].get("event", "") == "shop_buy":
						_fly_purchase(msg["data"]) # the bought card flies from the shop to its place
				"pack_ready":
					_show_pack(msg["data"]) # a booster pack waits to be torn open
				"score":
					_score_pop(msg["data"]) # "+30", "X2" ... at the card / joker that scored
				"shatter":
					_shatter_card(msg["data"]) # a glass card broke
				"sound":
					_sounds.play(msg["data"])
		"sound_data":
			_sounds.add_sound(msg["data"])
		"font":
			if GameFont.load_from(msg["data"]):
				GameFont.apply_to(self) # every label that already exists; new ones via _on_node_added
		"intro":
			IntroCards.remember_assets(msg["data"])
		"atlas":
			IntroCards.remember_atlas(msg["data"])
			CardArt.add_atlas(msg["data"])
			if not _last_scene.is_empty():
				_apply_scene(_last_scene) # redraw with the new textures right away
			_apply_state(_state)


## New 3D labels (board texts, tooltips, joker signs ...) get the game font as soon as it is known.
func _on_node_added(node: Node) -> void:
	if node is Label3D and GameFont.font != null:
		node.font = GameFont.font


func _apply_scene(scene: Dictionary) -> void:
	_last_scene = scene
	# compact run panel whenever no blind is being played (shop, blind select, cash out, packs)
	_board.compact_hud = _state.get("in_run", false) and not ROUND_STATES.has(str(scene.get("state_name", "")))
	if _vr:
		# the hand first, so tooltips of hand cards find their card
		var hand: Array = []
		_hand_flames = []
		var now := Time.get_ticks_msec() / 1000.0
		for it in scene.get("items", []):
			if it.get("k", "") == "c" and it.get("area", "") == "hand":
				var id := int(it.get("id", -1))
				if _hl_pending.has(id): # our click is on its way: don't let an older scene undo it
					var want: bool = _hl_pending[id][0]
					if bool(it.get("hl", false)) == want or now - float(_hl_pending[id][1]) > 0.6:
						_hl_pending.erase(id)
					else:
						it = it.duplicate()
						it["hl"] = want
				hand.append(it)
			elif it.get("k", "") == "fl": # the score is on fire (only sent while it burns)
				_hand_flames.append(it)
		_rebuild_hand(hand)
		_sync_play_cards(scene.get("items", []))
		_fly_discards(scene.get("items", [])) # hand cards that were discarded fly to the discard pile
		_set_heat(_hand_flames)
	_board.apply_scene(scene)
	_update_bag_counts(scene) # "JOKERS 3/5", "CONSUMABLES 1/2" on the card stand
	for uid in _jokers: # card art for jokers without a 3D model (comes with the scene)
		if is_instance_valid(_jokers[uid]):
			_refresh_card_stand(_jokers[uid], uid)
	_set_status("Connected – %s" % scene.get("state_name", ""))


func _send(command: Dictionary) -> void:
	if _peer == null or not _connected:
		return
	_cmd_id += 1
	command["id"] = _cmd_id
	_peer.put_data((JSON.stringify(command) + "\n").to_utf8_buffer())


func _set_connected(on: bool) -> void:
	if on == _connected:
		return
	_connected = on
	if not on:
		_balatro_running = false # re-checked within 1.5 s; avoids "starting" while Balatro closes
		_last_scene = {}
	_status3d.visible = not on and not _intro.is_showing()
	_set_status("Connected" if on else "Waiting for Balatro ... (start the game with the mod)")
	if on:
		_send_flags() # the Options menu shows our settings


func _set_status(text: String) -> void:
	_status.text = text


# ---------------------------------------------------------------- game state -> 3D props

func _apply_state(state: Dictionary) -> void:
	_state = state
	if state.is_empty():
		return
	var in_run: bool = state.get("in_run", false)

	# Blind chip: front = current blind, back = stake (difficulty)
	var blind: Dictionary = state.get("blind", {})
	_set_sprite_face(_chip_front, blind.get("sprite"), Vector2.ONE * CHIP_RADIUS * 2.0)
	_set_sprite_face(_chip_back, state.get("stake_sprite"), Vector2.ONE * CHIP_RADIUS * 2.0)
	# only during a round; in the shop, blind select, cash-out or packs it would just be in the way
	_chip.visible = (in_run and ROUND_STATES.has(str(state.get("state_name", "")))) or _calibrating or _chip_defeat_t >= 0.0

	# Draw pile: deck colour, height = cards left, back art on top
	var deck: Dictionary = state.get("deck", {})
	var remaining := int(deck.get("remaining", 0))
	_deck_target_height = maxf(remaining, 0) * DECK_CARD_THICKNESS
	var side_mat: StandardMaterial3D = _deck_body.material_override
	side_mat.albedo_color = DECK_COLORS.get(str(deck.get("back_key", "")), Color(0.8, 0.2, 0.2))
	_set_sprite_face(_deck_top, deck.get("back_sprite"), DECK_CARD)
	_deck_label.text = "%d / %d" % [remaining, int(deck.get("total", 0))]
	_deck.visible = in_run or _calibrating
	_coins.visible = in_run or _calibrating
	_coins.set_amount(int(state.get("round", {}).get("dollars", 0)))
	_joker_table.visible = in_run or _calibrating

	var sign = state.get("shop_sign")
	_shop_sign_info = sign if sign is Dictionary else {}
	_shop_sign.visible = not _shop_sign_info.is_empty() or _calibrating

	_update_jokers(state)

	# a star joker in a slot (Supernova, Satellite, Constellation): the room keeps twinkling
	var starry := false
	if in_run:
		for j in state.get("jokers", []):
			if STAR_JOKERS.has(str(j.get("key", ""))):
				starry = true
	_stars.set_ambient(starry)

	# Run won (Ante 8 boss beaten) or game over: confetti from above, once per run end
	var end := ""
	if str(state.get("state_name", "")) == "GAME_OVER":
		end = "lost"
	elif in_run and state.get("won", false):
		end = "won"
	if end != _last_end and end != "" and _was_in_state:
		_confetti.burst(end == "won", CONFETTI_WON if end == "won" else CONFETTI_LOST)
		_jimbo.react("win" if end == "won" else "sad")
		_run_end_scene(end == "won")
	_last_end = end
	_apply_table_fun(state, in_run)
	_was_in_state = true


func _set_sprite_face(face: Node3D, sprite, size: Vector2) -> void:
	var mat: StandardMaterial3D = null
	if sprite is Dictionary:
		mat = CardArt.material(sprite.get("atlas"), sprite.get("pos"))
	CardArt.apply_layers(face, [mat] if mat != null else [], size, 0.0, 0.0004, 1)


# ---------------------------------------------------------------- augmented jokers on the joker board

func _joker_scene(key: String) -> PackedScene:
	if not _joker_scenes.has(key):
		var path := JOKER_SCENES % key
		_joker_scenes[key] = load(path) if ResourceLoader.exists(path) else null
	return _joker_scenes[key]


## Every joker stands on the joker board: its 3D model if there is one, otherwise its card on a
## little stand. Each has a free spot ("free", in board space); reading the board from left to
## right gives the order of the jokers in the game.
func _update_jokers(state: Dictionary) -> void:
	var alive := {}
	var game_order: Array = []
	if state.get("in_run", false):
		var list: Array = state.get("jokers", []).duplicate()
		list.sort_custom(func(a, b) -> bool: return int(a.get("slot", 0)) < int(b.get("slot", 0)))
		for j in list:
			var uid := int(j.get("uid", 0))
			alive[uid] = true
			game_order.append(uid)
			var inst = _jokers.get(uid)
			if inst == null or not is_instance_valid(inst):
				inst = _make_pedestal()
				var scene := _joker_scene(str(j.get("key", "")))
				# each joker gets its own fixed random turn, so some have to be walked around
				var rng := RandomNumberGenerator.new()
				rng.seed = uid
				if scene != null:
					var model := scene.instantiate()
					model.position.y = PEDESTAL_HEIGHT
					inst.add_child(model)
					inst.set_meta("model", model)
					inst.set_meta("yaw", deg_to_rad(rng.randf_range(-70.0, 70.0)))
				else: # no 3D model: the joker's card stands on the pedestal (only a slight turn: readable)
					inst.add_child(_make_card_stand())
					inst.set_meta("yaw", deg_to_rad(rng.randf_range(-20.0, 20.0)))
				inst.set_meta("slot", int(j.get("slot", 1)))
				_joker_table.add_child(inst)
				_jokers[uid] = inst
				inst.set_meta("free", _spot_for_new_joker(inst))
				inst.transform = inst.get_meta("free")
			inst.set_meta("slot", int(j.get("slot", 1)))
			inst.set_meta("key", str(j.get("key", "")))
			var model = inst.get_meta("model") if inst.has_meta("model") else null
			if model is AugmentedJoker:
				model.update_state(j, state)
				var edition := str(j.get("edition", "")).trim_prefix("e_")
				if inst.get_meta("edition", "") != edition:
					inst.set_meta("edition", edition)
					_apply_edition(model, edition)
			_refresh_card_stand(inst, uid)
			inst.get_node("DebuffMark").visible = j.get("debuffed", false)
			_set_value_tag(inst, str(j.get("value", "")))
			# the model's own floating number ("+6 Mult", "x1.50") would say the same as the
			# pedestal: hide it (texts like "Discard: King" are other information and stay)
			if model is AugmentedJoker:
				var own := model.get_node_or_null(model.label_node) as Label3D
				var fmt: String = model.label_format
				if own != null and (fmt.begins_with("+") or fmt.begins_with("x")):
					own.visible = str(j.get("value", "")) == ""
			_set_price_sticker(inst, int(j.get("sell", 0)))
	for uid in _jokers.keys():
		if not alive.has(uid):
			if is_instance_valid(_jokers[uid]):
				_jokers[uid].queue_free()
			_jokers.erase(uid)
	_joker_order = game_order
	_follow_game_order(game_order)


## Editions on the 3D joker models, after the card shaders: foil, holo and polychrome shine over
## every part of the model (an extra additive pass), negative darkens it to a violet shade.
## Pedestal, texts and glow effects (billboards, additive light) are left alone.
const MODEL_EDITION_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never;
uniform int mode = 1; // 1 foil, 2 holo, 3 polychrome
varying vec3 p;

void vertex() {
	p = VERTEX;
}

void fragment() {
	float t = TIME * 0.6;
	vec3 add = vec3(0.0);
	if (mode == 1) {
		float band = sin((p.x + p.y * 1.3 + p.z) * 90.0 - t * 3.0) * 0.5 + 0.5;
		add = vec3(0.1, 0.17, 0.35) + vec3(0.25, 0.35, 0.6) * pow(band, 4.0);
	} else if (mode == 2) {
		float grid = max(sin(p.x * 300.0 + t) * sin(p.y * 260.0 - t * 1.3), 0.0);
		float sweep = sin((p.x - p.y) * 60.0 + t * 1.5) * 0.5 + 0.5;
		add = vec3(0.5, 0.1, 0.28) * grid * sweep + vec3(0.06, 0.12, 0.35) * (1.0 - sweep) * 0.5;
	} else {
		add = (0.5 + 0.5 * cos(6.2832 * ((p.x + p.y + p.z) * 8.0 + t * 0.3 + vec3(0.0, 0.33, 0.67)))) * 0.35;
	}
	ALBEDO = add;
}
"""
const MODEL_NEGATIVE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mul, depth_draw_never;
void fragment() {
	ALBEDO = vec3(0.34, 0.28, 0.46);
}
"""
static var _model_edition_materials := {}


func _apply_edition(model: Node, edition: String) -> void:
	var mat: ShaderMaterial = null
	var modes := {"foil": 1, "holo": 2, "holographic": 2, "polychrome": 3, "negative": 4}
	if modes.has(edition):
		if not _model_edition_materials.has(edition):
			var shader := Shader.new()
			shader.code = MODEL_NEGATIVE_SHADER if edition == "negative" else MODEL_EDITION_SHADER
			var m := ShaderMaterial.new()
			m.shader = shader
			if edition != "negative":
				m.set_shader_parameter("mode", int(modes[edition]))
			_model_edition_materials[edition] = m
		mat = _model_edition_materials[edition]
	_set_edition_overlay(model, mat)


func _set_edition_overlay(node: Node, mat: Material) -> void:
	if node is GeometryInstance3D and not (node is Label3D):
		var own = node.material_override
		var effect: bool = own is BaseMaterial3D and (own.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED \
				or own.blend_mode == BaseMaterial3D.BLEND_MODE_ADD)
		if not effect:
			node.material_overlay = mat
	for child in node.get_children():
		_set_edition_overlay(child, mat)


## "Right" as the player sees it, in joker-board space (the board can be turned by calibration).
func _board_right() -> Vector3:
	var r := _joker_table.global_basis.inverse() * _layout.global_basis.x
	r.y = 0
	return r.normalized() if r.length() > 0.001 else Vector3.RIGHT


## The jokers on the board from left to right (uids).
func _board_order() -> Array:
	var right := _board_right()
	var uids: Array = []
	for uid in _jokers:
		if is_instance_valid(_jokers[uid]):
			uids.append(uid)
	uids.sort_custom(func(a, b) -> bool:
		var ta: Transform3D = _jokers[a].get_meta("free")
		var tb: Transform3D = _jokers[b].get_meta("free")
		return ta.origin.dot(right) < tb.origin.dot(right))
	return uids


## The game changed the order (reordered on the board above, a joker bought, sold, created):
## the jokers swap spots so the board reads in the game's order again. The layout itself stays.
func _follow_game_order(game_order: Array) -> void:
	if _held_joker >= 0:
		return
	if not _pending_order.is_empty():
		var waited := Time.get_ticks_msec() / 1000.0 - _pending_time
		if game_order == _pending_order or waited > 3.0:
			_pending_order = []
		if game_order != _pending_order and waited <= 3.0:
			return # our own reorder is still on its way to the game
	var board := _board_order()
	if board == game_order:
		return
	var spots: Array = []
	for uid in board:
		spots.append(_jokers[uid].get_meta("free").origin)
	for i in mini(game_order.size(), spots.size()):
		var inst: Node3D = _jokers[game_order[i]]
		var t: Transform3D = inst.get_meta("free")
		t.origin = spots[i] # keeps its own turn
		inst.set_meta("free", t)


## A new joker goes to the right of the others (it is the last one in the game), or onto the
## first free joker place if there is no room left on the right.
func _spot_for_new_joker(inst: Node3D) -> Transform3D:
	var basis := Basis(Vector3.UP, float(inst.get_meta("yaw", 0.0)))
	var half := JOKER_TABLE_SIZE * 0.5 - Vector2.ONE * JOKER_TABLE_MARGIN
	var right := _board_right()
	var others: Array = []
	for uid in _jokers:
		var n = _jokers[uid]
		if n != inst and is_instance_valid(n) and n.has_meta("free"):
			others.append(n.get_meta("free").origin)
	if not others.is_empty():
		var rightmost: Vector3 = others[0]
		for p in others:
			if p.dot(right) > rightmost.dot(right):
				rightmost = p
		var candidate: Vector3 = rightmost + right * JOKER_SPACING * 0.8
		if absf(candidate.x) <= half.x and absf(candidate.z) <= half.y:
			return Transform3D(basis, Vector3(candidate.x, JOKER_TABLE_TOP, candidate.z))
	for anchor in _joker_slots:
		var p: Vector3 = anchor.transform.origin
		var taken := false
		for q in others:
			if Vector2(q.x - p.x, q.z - p.z).length() < 0.07:
				taken = true
				break
		if not taken:
			return Transform3D(basis, Vector3(p.x, JOKER_TABLE_TOP, p.z))
	return Transform3D(basis, Vector3(_rng_board.randf_range(-half.x, half.x), JOKER_TABLE_TOP, _rng_board.randf_range(-half.y, half.y)))


## A joker without a 3D model: its card, leaning back a little on the pedestal.
func _make_card_stand() -> Node3D:
	var stand := Node3D.new()
	stand.name = "CardStand"
	var foot := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.05, 0.006, 0.014)
	foot.mesh = box
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.35, 0.2, 0.1)
	foot.material_override = wood
	foot.position = Vector3(0, PEDESTAL_HEIGHT + 0.003, -0.012)
	stand.add_child(foot)
	var card := Node3D.new()
	card.name = "Card"
	card.position = Vector3(0, PEDESTAL_HEIGHT + JOKER_CARD_SIZE.y * 0.5 + 0.002, -0.004)
	card.rotation_degrees.x = -10
	stand.add_child(card)
	var back := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = JOKER_CARD_SIZE
	back.mesh = quad
	var back_mat := StandardMaterial3D.new()
	back_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	back_mat.albedo_color = Color(0.85, 0.27, 0.24) # Balatro's red card back
	back.material_override = back_mat
	back.rotation_degrees.y = 180
	back.position.z = -0.0003
	card.add_child(back)
	return stand


## Puts the joker's card art on its stand (once the scene with the card's textures is there).
func _refresh_card_stand(inst: Node3D, uid: int) -> void:
	var card: Node3D = inst.get_node_or_null("CardStand/Card")
	if card == null:
		return
	for it in _last_scene.get("items", []):
		if it.get("k", "") == "c" and int(it.get("id", -1)) == uid:
			var layers := CardArt.card_layers(it)
			if not layers.is_empty():
				CardArt.apply_layers(card, layers, JOKER_CARD_SIZE, 0.0003)
			return


## Where a joker stands: its free spot on the board (a slot anchor only before it has one).
func _joker_target(inst: Node3D) -> Transform3D:
	if inst.has_meta("free"):
		return inst.get_meta("free")
	var slot: int = inst.get_meta("slot", 1)
	var anchor := _joker_slots[clampi(slot - 1, 0, JOKER_SLOTS - 1)]
	var t := anchor.transform
	if slot > JOKER_SLOTS: # more jokers than anchors (negative jokers): keep lining up
		t.origin += anchor.transform.basis.x * JOKER_SPACING * 0.5 * (slot - JOKER_SLOTS)
	return t * Transform3D(Basis(Vector3.UP, float(inst.get_meta("yaw", 0.0))), Vector3.ZERO)


func _animate_jokers(delta: float) -> void:
	var k := 1.0 - exp(-6.0 * delta) # glide when jokers are reordered or a slot is moved
	for inst in _jokers.values():
		if is_instance_valid(inst) and not inst.has_meta("held") and not inst.has_meta("selling"):
			inst.transform = inst.transform.interpolate_with(_joker_target(inst), k)
			var bump: float = inst.get_meta("bump", 0.0) # it just scored: a little jump
			if bump > 0.0:
				bump = maxf(bump - delta * 4.0, 0.0)
				inst.set_meta("bump", bump)
				inst.scale = Vector3.ONE * (1.0 + 0.3 * sin(bump * PI))
				inst.position.y += sin(bump * PI) * 0.02
		if is_instance_valid(inst):
			var sticker := inst.get_node_or_null("PriceSticker") as Node3D
			if sticker != null: # only lifted jokers show their underside
				sticker.visible = inst.has_meta("held") and int(sticker.get_meta("price", 0)) > 0
			var tag := inst.get_node("ValueTag") as Label3D
			tag.visible = tag.text != "" and not inst.has_meta("held") # lifted: the price sticker speaks
			if tag.visible: # on the pedestal's edge, on the side that faces you
				var to: Vector3 = _eyes() - inst.global_position
				to.y = 0.0
				to = to.normalized() if to.length() > 0.01 else Vector3.BACK
				var s := _joker_table.global_basis.get_scale().x # the board may be scaled in calibration
				tag.global_position = inst.global_position + to * 0.044 * s + inst.global_basis.y * 0.011
				tag.scale = Vector3.ONE * s


# ---------------------------------------------------------------- picking up jokers
# Grip near a joker on the table (either hand, any time outside calibration): it comes off the
# board with its pedestal and can be turned and looked at. Let go and it settles on the nearest
# joker place of the board – and the game moves it to that slot too, so the order on the table is
# always the order of the jokers in the game (which matters for Blueprint, Brainstorm, ...).

const JOKER_GRAB_RADIUS := 0.09


func _try_grab_joker(hand: XRController3D) -> bool:
	if not _vr or _calibrating or _held_joker >= 0 or not _joker_table.is_visible_in_tree():
		return false
	var best := -1
	var best_dist := JOKER_GRAB_RADIUS
	for uid in _jokers:
		var inst = _jokers[uid]
		if not is_instance_valid(inst):
			continue
		var centre: Vector3 = inst.global_position + inst.global_basis.y * 0.05 # the model on the pedestal
		var dist := centre.distance_to(hand.global_position)
		if dist < best_dist:
			best = uid
			best_dist = dist
	if best < 0:
		return false
	var inst: Node3D = _jokers[best]
	_held_joker = best
	_held_hand = hand
	_held_offset = hand.global_transform.affine_inverse() * inst.global_transform
	inst.set_meta("held", true)
	return true


func _update_held_joker() -> void:
	if _held_joker < 0:
		return
	var inst = _jokers.get(_held_joker)
	if inst == null or not is_instance_valid(inst): # sold or destroyed while in the hand
		_held_joker = -1
		return
	inst.global_transform = _held_hand.global_transform * _held_offset


func _drop_joker() -> void:
	if _held_joker < 0:
		return
	var inst = _jokers.get(_held_joker)
	_held_joker_uid_last = _held_joker
	_held_joker = -1
	if inst == null or not is_instance_valid(inst):
		return
	inst.remove_meta("held")
	if _sell_dropped_joker(inst, _held_joker_uid_last):
		return # let go above the coin slot: sold
	# straight down onto the board where it was let go, upright, keeping its turn
	var t: Transform3D = _joker_table.global_transform.affine_inverse() * inst.global_transform
	var facing := t.basis.z
	facing.y = 0
	var yaw := atan2(facing.x, facing.z) if facing.length() > 0.001 else 0.0
	var half := Vector2(JOKER_ZONE_HALF, JOKER_TABLE_SIZE.y * 0.5 - JOKER_TABLE_MARGIN) # the ends belong to machine and slot
	var p := Vector3(clampf(t.origin.x, -half.x, half.x), JOKER_TABLE_TOP, clampf(t.origin.z, -half.y, half.y))
	inst.set_meta("free", Transform3D(Basis(Vector3.UP, yaw), p))
	# the board, read from left to right, is the new order of the jokers in the game
	var board := _board_order()
	var game: Array = []
	var list: Array = _state.get("jokers", []).duplicate()
	list.sort_custom(func(a, b) -> bool: return int(a.get("slot", 0)) < int(b.get("slot", 0)))
	for j in list:
		game.append(int(j.get("uid", -1)))
	if board != game and board.size() == game.size():
		var ids := PackedStringArray()
		for uid in board:
			ids.append(str(uid))
		_send({"cmd": "order", "ids": ";".join(ids)})
		_pending_order = board
		_pending_time = Time.get_ticks_msec() / 1000.0
		for i in board.size(): # show the new slots right away; the game confirms them
			_jokers[board[i]].set_meta("slot", i + 1)


## Round wooden pedestal (like a display stand): wide reddish-brown base, dark bevelled top.
func _make_pedestal() -> Node3D:
	var holder := Node3D.new()
	var base := MeshInstance3D.new()
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 0.04
	base_mesh.bottom_radius = 0.042
	base_mesh.height = 0.012
	base.mesh = base_mesh
	base.position.y = 0.006
	base.material_override = _wood_material(Color(0.3, 0.12, 0.08))
	holder.add_child(base)
	var top := MeshInstance3D.new()
	var top_mesh := CylinderMesh.new()
	top_mesh.top_radius = 0.032
	top_mesh.bottom_radius = 0.038 # the bevel
	top_mesh.height = 0.007
	top.mesh = top_mesh
	top.position.y = 0.012 + 0.0035
	top.material_override = _wood_material(Color(0.1, 0.06, 0.05))
	holder.add_child(top)

	# a boss blind debuffed this joker: big red cross floating above it, like the game's card cross
	var mark := Label3D.new()
	mark.name = "DebuffMark"
	mark.text = "X"
	mark.modulate = Color(0.95, 0.15, 0.15)
	mark.outline_modulate = Color(0.2, 0.0, 0.0)
	mark.outline_size = 12
	mark.font_size = 96
	mark.pixel_size = 0.0009
	mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	mark.position.y = 0.19
	mark.visible = false
	holder.add_child(mark)

	# what the joker has collected so far ("+12 Mult", "X1.5 Mult" ...), on the pedestal's edge
	# facing you (placed each frame in _animate_jokers)
	var tag := Label3D.new()
	tag.name = "ValueTag"
	tag.font_size = 40
	tag.pixel_size = 0.0005
	tag.outline_size = 10
	tag.outline_modulate = Color(0.05, 0.03, 0.02)
	tag.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	tag.top_level = true # placed in world space, not turned with the joker
	tag.visible = false
	holder.add_child(tag)
	return holder


## A price sticker under the pedestal, like at a flea market: what the joker sells for. Only seen
## when you pick the joker up and turn it over (it is shown only while held).
func _set_price_sticker(inst: Node3D, price: int) -> void:
	var sticker := inst.get_node_or_null("PriceSticker") as Node3D
	if sticker == null:
		sticker = Node3D.new()
		sticker.name = "PriceSticker"
		sticker.position.y = -0.0008 # on the underside of the base
		sticker.rotation_degrees.x = 90.0 # its face looks down
		sticker.visible = false
		inst.add_child(sticker)
		var paper := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(0.04, 0.026)
		paper.mesh = quad
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(1.0, 0.62, 0.15) # the classic orange price label
		m.roughness = 0.8
		paper.material_override = m
		sticker.add_child(paper)
		var edge := MeshInstance3D.new() # a slightly peeled-off corner
		var corner := QuadMesh.new()
		corner.size = Vector2(0.008, 0.008)
		edge.mesh = corner
		var cm := StandardMaterial3D.new()
		cm.albedo_color = Color(0.95, 0.93, 0.88)
		edge.material_override = cm
		edge.position = Vector3(0.017, 0.010, 0.0004)
		edge.rotation.z = 0.785
		sticker.add_child(edge)
		var text := Label3D.new()
		text.name = "Price"
		text.font_size = 48
		text.pixel_size = 0.00035
		text.outline_size = 0
		text.modulate = Color(0.12, 0.08, 0.05)
		text.position.z = 0.0005
		text.double_sided = false
		sticker.add_child(text)
		var small := Label3D.new()
		small.text = "SELL"
		small.font_size = 24
		small.pixel_size = 0.00025
		small.outline_size = 0
		small.modulate = Color(0.25, 0.15, 0.05)
		small.position = Vector3(0, -0.009, 0.0005)
		small.double_sided = false
		sticker.add_child(small)
		GameFont.apply_to(sticker)
	(sticker.get_node("Price") as Label3D).text = "$%d" % price
	sticker.set_meta("price", price)


## The joker's current value on its pedestal, coloured like the game: Mult red, Chips blue, $ gold.
func _set_value_tag(inst: Node3D, value: String) -> void:
	var tag := inst.get_node("ValueTag") as Label3D
	tag.visible = value != ""
	if tag.text == value:
		return
	tag.text = value
	if "Chip" in value:
		tag.modulate = Color(0.35, 0.65, 1.0)
	elif value.begins_with("$"):
		tag.modulate = Color(1.0, 0.8, 0.3)
	elif "Mult" in value:
		tag.modulate = Color(1.0, 0.35, 0.3)
	else:
		tag.modulate = Color(1.0, 0.95, 0.85)


func _wood_material(colour: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.roughness = 0.35 # polished
	return mat


func _build_joker_table() -> void:
	_joker_table = Node3D.new()
	_joker_table.name = "JokerTable"
	_joker_table.position = JOKER_TABLE_POS
	_layout.add_child(_joker_table)

	# the mat: dark felt with a lighter rim, in the style of the game's panels. Only a placement aid:
	# while playing, the pedestals and the pile stand directly on the real table.
	_joker_mat = Node3D.new()
	_joker_mat.name = "Mat"
	_joker_mat.visible = false
	_joker_table.add_child(_joker_mat)
	var rim := MeshInstance3D.new()
	var rim_mesh := BoxMesh.new()
	rim_mesh.size = Vector3(JOKER_TABLE_SIZE.x + 0.02, JOKER_TABLE_TOP - 0.002, JOKER_TABLE_SIZE.y + 0.02)
	rim.mesh = rim_mesh
	rim.position.y = (JOKER_TABLE_TOP - 0.002) * 0.5
	rim.material_override = _wood_material(Color(0.36, 0.43, 0.5))
	_joker_mat.add_child(rim)
	var felt := MeshInstance3D.new()
	var felt_mesh := BoxMesh.new()
	felt_mesh.size = Vector3(JOKER_TABLE_SIZE.x, JOKER_TABLE_TOP, JOKER_TABLE_SIZE.y)
	felt.mesh = felt_mesh
	felt.position.y = JOKER_TABLE_TOP * 0.5
	var felt_mat := StandardMaterial3D.new()
	felt_mat.albedo_color = Color(0.17, 0.23, 0.27)
	felt_mat.roughness = 0.95
	felt.material_override = felt_mat
	_joker_mat.add_child(felt)

	for i in JOKER_SLOTS:
		var slot := Node3D.new()
		slot.name = "Slot%d" % (i + 1)
		var column := i % JOKER_COLUMNS
		var row := i / JOKER_COLUMNS
		slot.position = Vector3((column - (JOKER_COLUMNS - 1) / 2.0) * JOKER_SPACING, JOKER_TABLE_TOP,
				JOKER_ROW_Z + row * JOKER_ROW_DEPTH)
		_joker_table.add_child(slot)
		_joker_slots.append(slot)
	_joker_table.visible = false


## Slots and the draw pile can only slide over the joker board, turn around the vertical axis
## and never leave the mat.
func _keep_on_joker_table(node: Node3D) -> void:
	var t := node.transform # relative to the joker board
	var facing := t.basis.z
	facing.y = 0
	var yaw := atan2(facing.x, facing.z) if facing.length() > 0.001 else 0.0
	var half := JOKER_TABLE_SIZE * 0.5 - Vector2.ONE * JOKER_TABLE_MARGIN
	var p := Vector3(clampf(t.origin.x, -half.x, half.x), JOKER_TABLE_TOP, clampf(t.origin.z, -half.y, half.y))
	node.transform = Transform3D(Basis(Vector3.UP, yaw), p)


# ---------------------------------------------------------------- chip & draw pile

func _animate_shop_sign() -> void:
	if not _shop_sign.visible:
		return
	var atlas: String = _shop_sign_info.get("atlas", "shop_sign")
	var frames := maxi(int(_shop_sign_info.get("frames", 4)), 1)
	var frame := int(_chip_time * SHOP_SIGN_FPS) % frames # the sign's lights run like in the game
	var mat := CardArt.material(atlas, [frame, 0])
	CardArt.apply_layers(_shop_sign, [mat] if mat != null else [], SHOP_SIGN_SIZE, 0.0, 0.0004, 1)


func _animate_chip(delta: float) -> void:
	_chip_time += delta
	# spins and floats up and down like a coin in Super Mario
	_chip_spinner.rotation.y = _chip_time * 1.8
	_chip_spinner.position = Vector3(0, sin(_chip_time * 2.4) * 0.015, 0)


func _animate_deck(delta: float) -> void:
	_deck_height = lerpf(_deck_height, _deck_target_height, 1.0 - exp(-8.0 * delta))
	var h := maxf(_deck_height, 0.0005)
	_deck_body.scale = Vector3(DECK_CARD.x, h, DECK_CARD.y)
	_deck_body.position.y = h * 0.5
	_deck_top.position.y = h + 0.0004
	_deck_label.position.y = h + 0.05
	_animate_shuffle(delta, h)


## A new round: the deck is shuffled on the table before the cards fly to your hand - it splits
## into two halves that lift and tilt apart, the cards riffle into each other from both sides
## (with the game's own card sound, from the deck) and the pile is tapped square again.
func _start_shuffle() -> void:
	if not _deck.is_visible_in_tree() or _shuffle_t >= 0.0:
		return
	_shuffle_t = 0.0
	_shuffle_next_card = 0.0
	if _shuffle_halves.is_empty():
		for side in [-1.0, 1.0]:
			var half := MeshInstance3D.new()
			half.mesh = _deck_body.mesh
			half.material_override = _deck_body.material_override
			half.set_meta("side", side)
			_deck.add_child(half)
			_shuffle_halves.append(half)
	# cards already on their way to the hand wait for the shuffle
	for id in _hand_cards:
		var body = _hand_cards[id]
		if is_instance_valid(body) and body.has_meta("fly_t") and float(body.get_meta("fly_t")) < 0.2:
			body.set_meta("fly_t", float(body.get_meta("fly_t")) - SHUFFLE_TIME)


func _animate_shuffle(delta: float, h: float) -> void:
	if _shuffle_t < 0.0:
		return
	_shuffle_t += delta
	var t := _shuffle_t
	var split := clampf(t / 0.22, 0.0, 1.0)                       # the halves lift and tilt apart
	var riffle := clampf((t - 0.22) / 0.5, 0.0, 1.0)              # ... and riffle into the middle
	var close := clampf((t - 0.72) / 0.12, 0.0, 1.0)              # tap the pile square
	var e := split * split * (3.0 - 2.0 * split)
	for half in _shuffle_halves:
		var side: float = half.get_meta("side")
		var hh := h * 0.5 * (1.0 - riffle)
		half.visible = riffle < 1.0
		half.scale = Vector3(DECK_CARD.x, maxf(hh, 0.0005), DECK_CARD.y)
		half.position = Vector3(side * 0.05 * e * (1.0 - close), 0.015 * e * (1.0 - riffle) + hh * 0.5, 0.0)
		half.rotation = Vector3(0.0, 0.0, side * 0.22 * e * (1.0 - riffle)) # inner edges up, like bending the halves for a riffle
	# the real pile grows in the middle as the cards fall in
	var grow := riffle
	_deck_body.scale.y = maxf(h * grow, 0.0005)
	_deck_body.position.y = h * grow * 0.5
	_deck_top.visible = riffle >= 1.0
	if riffle > 0.0 and riffle < 1.0:
		_shuffle_next_card -= delta
		if _shuffle_next_card <= 0.0: # a card flicks from one half into the middle: tick
			_shuffle_next_card = 0.035
			_sounds.play({"code": "card1", "per": randf_range(1.5, 1.9), "vol": _sounds.last_volume * 0.35, "at": _deck.global_position})
			_buzz_hand(_holder, 0.06, 0.01)
	if close > 0.0 and close < 1.0:
		_deck_body.scale.y = h * (1.0 + 0.15 * sin(close * PI)) # the tap
	if t >= SHUFFLE_TIME:
		_shuffle_t = -1.0
		_deck_top.visible = true
		for half in _shuffle_halves:
			half.visible = false
		_sounds.play({"code": "cardSlide1", "per": 1.1, "vol": _sounds.last_volume * 0.6, "at": _deck.global_position})


func _update_deck_hover() -> void:
	var over := _deck.is_visible_in_tree() and (_hand_over_deck(_right) or _hand_over_deck(_left))
	if over == _deck_hover:
		return
	if over and _state.get("overlay", false) and not _state.get("viewing_deck", false):
		return # another menu is open; don't stack "View Deck" on top of it
	_deck_hover = over
	_send({"cmd": "deck_view", "on": over})


func _hand_over_deck(hand: XRController3D) -> bool:
	var local := _deck.to_local(hand.global_position)
	var flat := Vector2(local.x, local.z).length()
	return flat < DECK_HOVER_RADIUS and local.y > -0.03 and local.y < _deck_height + 0.15


# ---------------------------------------------------------------- pointing, clicking, tooltips

func _ray_target() -> Dictionary:
	_pointer_valid = _ray.is_colliding()
	if not _pointer_valid:
		_reticle.visible = false
		_set_beam_length(BEAM_LENGTH)
		return {}
	_pointer_point = _ray.get_collision_point()
	_set_beam_length(_ray.global_position.distance_to(_pointer_point)) # the beam ends where it hits
	_reticle.visible = true
	_reticle.global_position = _pointer_point
	_reticle.scale = Vector3.ONE * (1.8 if _drag_id >= 0 and _drag_armed else 1.0) # bigger dot while dragging a card
	return _target_info(_ray.get_collider())


## The beam is a cylinder along the pointer's -Z axis; scaling its own axis shortens it.
func _set_beam_length(length: float) -> void:
	length = maxf(length, 0.001)
	_beam.scale = Vector3(1, length / BEAM_LENGTH, 1)
	_beam.position = Vector3(0, 0, -length * 0.5)


func _target_info(body) -> Dictionary:
	if body != null and body.has_meta("target_id"):
		return {"id": int(body.get_meta("target_id")), "kind": str(body.get_meta("kind")),
			"area": str(body.get_meta("area", ""))}
	return {}


func _update_pointer(target: Dictionary, delta: float) -> void:
	var id: int = target.get("id", -1)
	if id != _hover_id:
		if _hover_sent:
			_send({"cmd": "unhover", "target": _hover_id})
		_hover_id = id
		_hover_kind = target.get("kind", "")
		_hover_area = target.get("area", "")
		_hover_time = 0.0
		_hover_sent = false
		if _drag_id >= 0 and _drag_armed:
			if id == _drag_id:
				pass # keep the target: the preview moved the dragged card under the pointer
			elif id >= 0 and _hover_kind == "card" and _hover_area == _drag_area:
				_drop_target = id
			else:
				_drop_target = -1 # pointing elsewhere: releasing now cancels
			if _drag_area == "hand" and _vr:
				_rebuild_hand(_hand_items) # live preview of the new order in the fan
	elif id >= 0 and not _hover_sent and (_hover_kind == "card" or _hover_kind == "tip"):
		_hover_time += delta
		if _hover_time >= HOVER_DELAY:
			_send({"cmd": "hover", "target": id})
			_hover_sent = true


func _click(id: int) -> void:
	if id >= 0:
		_send({"cmd": "click", "target": id})


## Trigger / mouse button pressed on something. Hand cards and jokers decide on the release:
## a short tap (< DRAG_HOLD) always selects the pressed card, even if the beam slipped a little;
## only holding longer turns it into dragging – released on another card of the row = move there.
func _press_target(target: Dictionary) -> void:
	var id: int = target.get("id", -1)
	if target.get("kind", "") == "card" and REORDER_AREAS.has(target.get("area", "")):
		_drag_id = id
		_drag_area = target["area"]
		_drop_target = -1
		_drag_armed = false
		_drag_pressed_at = Time.get_ticks_msec() / 1000.0
	elif target.get("kind", "") == "pack":
		if _pack != null and is_instance_valid(_pack):
			_pack.rip() # the shortcut: trigger on the waiting booster pack
	elif target.get("kind", "") == "wrist":
		if _wrist != null and _wrist.visible: # (a closed menu never reacts)
			_wrist.press(id) # a button of the menu above the card hand
	elif target.get("kind", "") == "tutorial":
		if _tutorial != null and _tutorial.visible:
			_tutorial.press(id) # "Next" / "Skip" on Jimbo's tips
	elif target.get("kind", "") == "consumable":
		_use_consumable(id, false) # trigger on a tarot / planet / spectral card in the rack
	else:
		_click(id)


## Called every frame while a card is pressed: after DRAG_HOLD the press becomes a drag.
func _update_drag_hold() -> void:
	if _drag_id < 0 or _drag_armed:
		return
	if Time.get_ticks_msec() / 1000.0 - _drag_pressed_at < DRAG_HOLD:
		return
	_drag_armed = true
	_buzz(0.15, 0.03) # a light tick: now it is being dragged
	if _hover_id >= 0 and _hover_id != _drag_id and _hover_kind == "card" and _hover_area == _drag_area:
		_drop_target = _hover_id
	if _drag_area == "hand" and _vr:
		_rebuild_hand(_hand_items) # the card stands out of the fan now


func _release_target(target: Dictionary) -> void:
	if _drag_id < 0:
		return
	var released_on: int = target.get("id", -1)
	var was_hand := _drag_area == "hand"
	if _drag_armed and _drop_target >= 0:
		_send({"cmd": "move", "target": _drag_id, "to": _drop_target})
		_buzz(0.25, 0.04)
		if was_hand:
			_hand_items = _moved(_hand_items, _drag_id, _drop_target) # keep the preview until the game confirms
	elif not _drag_armed or released_on == _drag_id:
		_select(_drag_id) # a tap (or held without moving): select
	# otherwise dragged off and released somewhere else: cancelled
	_drag_id = -1
	_drop_target = -1
	_drag_armed = false
	if was_hand and _vr:
		_rebuild_hand(_hand_items)
	_update_drag_feedback()


## Click a card – a hand card lifts (or drops) right away instead of waiting for the game.
func _select(id: int) -> void:
	_click(id)
	_buzz(0.35, 0.05)
	for i in _hand_items.size():
		if int(_hand_items[i].get("id", -1)) == id:
			var it: Dictionary = _hand_items[i].duplicate()
			it["hl"] = not it.get("hl", false)
			_hand_items[i] = it
			_hl_pending[id] = [it["hl"], Time.get_ticks_msec() / 1000.0]
			break


## Short vibration on the pointing hand.
func _buzz(amplitude: float, seconds: float) -> void:
	if _vr and _point != null:
		_point.trigger_haptic_pulse("haptic", 0.0, amplitude, seconds, 0.0)


## `items` with card `id` put where card `to` is (same rule as the mod's move command).
func _moved(items: Array, id: int, to: int) -> Array:
	var from_i := -1
	var to_i := -1
	for i in items.size():
		var item_id := int(items[i].get("id", -1))
		if item_id == id:
			from_i = i
		if item_id == to:
			to_i = i
	if from_i < 0 or to_i < 0:
		return items
	var out := items.duplicate()
	var card = out.pop_at(from_i)
	out.insert(to_i, card)
	return out


func _card_item(id: int) -> Dictionary:
	for it in _hand_items:
		if int(it.get("id", -1)) == id:
			return it
	for it in _last_scene.get("items", []):
		if int(it.get("id", -1)) == id:
			return it
	return {}


## The card copy that follows the pointer while dragging.
func _update_drag_feedback() -> void:
	var show_ghost := _drag_id >= 0 and _drag_armed and _hover_id != _drag_id and _pointer_valid
	_drag_ghost.visible = show_ghost
	if not show_ghost:
		return
	if _drag_ghost.get_meta("card", -1) != _drag_id:
		_drag_ghost.set_meta("card", _drag_id)
		CardArt.apply_layers(_drag_ghost, CardArt.card_layers(_card_item(_drag_id)), DRAG_GHOST_SIZE, 0.0)
	var eye := _head.global_position if _vr else _camera.global_position
	_drag_ghost.global_position = _pointer_point + (eye - _pointer_point).normalized() * 0.04
	_drag_ghost.look_at(eye, Vector3.UP)
	_drag_ghost.rotate_object_local(Vector3.UP, PI) # quads face +Z, look_at points -Z at the eye




## Board callback: tooltips of hand cards appear right above that card in the left hand.
func _popup_anchor_for(owner_id: int):
	if owner_id == _touch_uid and _touched_node() != null:
		return _joker_tip_anchor(_touched_node()) # a touched 3D joker / rack card: its tooltip above it
	var card = _hand_cards.get(owner_id)
	if card == null or not is_instance_valid(card):
		return null
	return card.get_node("TipAnchor")


## Both controllers report here; what a button does depends on the controller's role:
## the pointing hand (beam, clicks, gestures) or the card hand (holds the fan).
func _on_button(button_name: String, controller: XRController3D) -> void:
	if button_name == "menu_button": # only the left controller has one
		if _calibrating:
			_set_calibrating(false) # (saves and leaves the calibration)
		else:
			_toggle_wrist_menu()
	elif controller == _point:
		_on_pointer_button(button_name)
	else:
		_on_holder_button(button_name)


func _on_button_released(button_name: String, controller: XRController3D) -> void:
	if button_name == "grip_click" and _calib_grabbed != "" and controller == _calib_hand:
		_calib_grabbed = ""
		return
	if button_name == "grip_click":
		_release_table(controller) # pack, lever, consumable or joker in this hand
	if controller != _point:
		return
	if button_name == "trigger_click":
		_release_target({"id": _hover_id, "kind": _hover_kind, "area": _hover_area})
	elif button_name == "grip_click" and _grab_active:
		_release_bundle()


func _on_pointer_button(button_name: String) -> void:
	if _calibrating:
		match button_name:
			"trigger_click":
				_click(_hover_id)
			"grip_click":
				_calib_grab(_point)
			"ax_button":
				_set_calibrating(false) # save & leave
		return
	match button_name:
		"trigger_click":
			_press_target({"id": _hover_id, "kind": _hover_kind, "area": _hover_area})
		"grip_click":
			if not _grip_table(_point): # pack, lever, consumable or joker within reach win over the hand cards
				_try_grab()
		"ax_button":
			_send({"cmd": "play"})
		"by_button":
			_send({"cmd": "discard"})


func _on_holder_button(button_name: String) -> void:
	match button_name:
		"grip_click":
			if _calibrating:
				_calib_grab(_holder) # e.g. the grabbed-cards spot on the pointing hand
			else:
				_grip_table(_holder)
		"by_button":
			if _calibrating:
				_reset_layout()
			else:
				_place_layout()
		"ax_button":
			_next_backdrop()
		"primary_click":
			if not _calibrating:
				_toggle_sort() # stick click on the card hand


## Sorted by rank -> sort by suit and vice versa (the mod reads the game's current order).
func _toggle_sort() -> void:
	_send({"cmd": "sort", "by": "toggle"})


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_P:
				_send({"cmd": "play"})
			KEY_D:
				_send({"cmd": "discard"})
			KEY_S:
				_toggle_sort()
			KEY_B:
				_next_backdrop()
			KEY_C:
				_set_calibrating(not _calibrating)
			KEY_H:
				_set_left_handed(not _left_handed)
			KEY_K:
				# test: K = won, Shift+K = game over
				_confetti.burst(not event.shift_pressed, CONFETTI_LOST if event.shift_pressed else CONFETTI_WON)
				_run_end_scene(not event.shift_pressed)
			KEY_R:
				if _vr:
					_place_layout()
	elif event is InputEventMouseMotion and _camera != null and _drag_id >= 0:
		_update_pointer(_mouse_target(event.position), 0.0) # drag feedback follows the mouse
	elif event is InputEventMouseButton and _camera != null:
		var target := _mouse_target(event.position)
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_press_target(target)
			else:
				_release_target(target)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed and target.get("kind", "") == "card":
				_send({"cmd": "hover", "target": target["id"]})
				_hover_id = target["id"]
			elif not event.pressed and _hover_id >= 0:
				_send({"cmd": "unhover", "target": _hover_id})
				_hover_id = -1


func _mouse_target(screen_pos: Vector2) -> Dictionary:
	var from := _camera.project_ray_origin(screen_pos)
	var to := from + _camera.project_ray_normal(screen_pos) * 10.0
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))
	_pointer_valid = hit.has("position")
	if _pointer_valid:
		_pointer_point = hit["position"]
	return _target_info(hit.get("collider"))


# ---------------------------------------------------------------- hand fan (left hand)

func _rebuild_hand(items: Array) -> void:
	_hand_items = items
	# while a hand card is dragged over another one, lay the fan out as it will be after dropping
	var shown := _moved(items, _drag_id, _drop_target) if _drag_area == "hand" and _drop_target >= 0 else items
	var alive := {}
	var n := shown.size()
	var drawn := 0
	for i in n:
		var it: Dictionary = shown[i]
		var id := int(it.get("id", 0))
		alive[id] = true
		_hand_item_by_id[id] = it
		if not _hand_cards.has(id):
			_hand_cards[id] = _make_hand_card(id)
			# drawn from the deck: it flies from the 3D pile into the hand, one after the other
			if _vr and _deck.is_visible_in_tree():
				_hand_cards[id].set_meta("fly_t", -0.09 * drawn)
				drawn += 1
		var body: StaticBody3D = _hand_cards[id]
		_style_hand_card(body, it)
		_style_hand_flame(body, id)
		if _grab_active and _grabbed.has(id):
			continue # follows the right hand
		if _released.has(id):
			continue # let go to be played / discarded: waits where it was released
		# Round fan: every card sits on an arc in the (tilted) card plane and points away from its
		# center; a selected card slides further out along its own direction.
		var offset := float(i) - (n - 1) / 2.0
		var angle := deg_to_rad(offset * FAN_ANGLE)
		var lift := FAN_SELECT_LIFT if it.get("hl", false) else 0.0
		if id == _drag_id and _drag_armed:
			lift += 0.03 # the card being dragged stands out of the fan
		var fan_plane := Basis(Vector3.RIGHT, deg_to_rad(FAN_TILT))
		var on_arc := Vector3(sin(angle), cos(angle), 0.0) * (FAN_RADIUS + lift) - Vector3(0, FAN_RADIUS, 0)
		var depth := Vector3(0, 0, offset * 0.0015) # right card lies on top of the left one, like a real hand
		# relative to the fan anchor on the card hand (a card still flying in from the deck goes there)
		var home := Transform3D(fan_plane * Basis(Vector3.BACK, -angle), fan_plane * (on_arc + depth))
		body.set_meta("home", home)
		if not body.has_meta("fly_t"):
			body.transform = home

	for id in _hand_cards.keys():
		if not alive.has(id):
			if is_instance_valid(_hand_cards[id]) and _hand_cards[id].is_inside_tree():
				_hand_last[id] = _hand_cards[id].global_transform # played: it flies to the table from here
				_hand_removed.append(id) # ... or, if it wasn't played, to the discard pile
			_released.erase(id)
			_hand_cards[id].queue_free()
			_hand_cards.erase(id)
	if _hand_last.size() > 60:
		_hand_last.clear()


func _make_hand_card(id: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.set_meta("target_id", id)
	body.set_meta("kind", "card")
	body.set_meta("area", "hand")

	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	var box := BoxMesh.new()
	box.size = CARD_SIZE
	mesh.mesh = box
	mesh.material_override = StandardMaterial3D.new()
	body.add_child(mesh)

	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = CARD_SIZE
	shape.shape = box_shape
	body.add_child(shape)

	# Fallback text until the game has sent its card textures
	for side in [1.0, -1.0]:
		var label := Label3D.new()
		label.name = "Front" if side > 0 else "Back"
		label.font_size = 40
		label.pixel_size = 0.0008
		label.position = Vector3(0, 0, side * (CARD_SIZE.z / 2 + 0.001))
		label.rotation_degrees = Vector3(0, 0 if side > 0 else 180, 0)
		body.add_child(label)

	# The card art of the back side faces the other way
	var back_side := Node3D.new()
	back_side.name = "BackSide"
	back_side.rotation_degrees = Vector3(0, 180, 0)
	body.add_child(back_side)

	# Tooltips of this card are shown here, just above it
	var tip := Node3D.new()
	tip.name = "TipAnchor"
	tip.position = Vector3(0, CARD_SIZE.y * 0.5 + 0.045, 0.01)
	tip.scale = Vector3.ONE * TOOLTIP_SCALE
	body.add_child(tip)

	_fan_anchor.add_child(body)
	return body


## While the score burns, every card in the hand burns too: flames lie on the card's face and rise
## from its bottom edge – the hotter the score, the higher, up over the top – in the chips (blue)
## and mult (red) colours by turns, each card flickering out of step.
func _style_hand_flame(body: StaticBody3D, id: int) -> void:
	var flame: MeshInstance3D = body.get_node_or_null("Flame")
	if _hand_flames.is_empty():
		if flame != null:
			flame.visible = false
		return
	if flame == null:
		flame = Board.make_flame()
		var height := CARD_SIZE.y * 1.15
		flame.scale = Vector3(CARD_SIZE.x * 1.05, height, 1)
		# bottom edge on the card's bottom edge, just in front of the card art
		flame.position = Vector3(0, -CARD_SIZE.y * 0.5 + height * 0.5, CARD_SIZE.z / 2 + 0.0035) # above art, seal and stickers
		(flame.material_override as ShaderMaterial).set_shader_parameter("opacity", 0.8) # the card shows through
		body.add_child(flame)
	var source: Dictionary = _hand_flames[id % _hand_flames.size()]
	Board.set_flame(flame, source, _board.opaque_mode, float(id % 13) * 0.77)
	flame.visible = true


func _style_hand_card(body: StaticBody3D, it: Dictionary) -> void:
	var size := Vector2(CARD_SIZE.x, CARD_SIZE.y)
	var surface := CARD_SIZE.z / 2 + 0.0005
	var layers := CardArt.card_layers(it)
	var has_art := not layers.is_empty()
	CardArt.apply_layers(body, layers, size, surface)
	var back := CardArt.material(it.get("ba"), it.get("bp"))
	CardArt.apply_layers(body.get_node("BackSide"), [back] if back != null else [], size, surface, 0.0004, 1)

	var mesh: MeshInstance3D = body.get_node("Mesh")
	mesh.visible = not has_art
	var mat: StandardMaterial3D = mesh.material_override
	mat.albedo_color = Board.card_color(it)
	var text := Board.card_text(it)
	var text_col := Board.card_text_color(it)
	for label_name in ["Front", "Back"]:
		var label: Label3D = body.get_node(label_name)
		label.visible = not has_art
		label.text = text
		label.modulate = text_col


# ---------------------------------------------------------------- gestures

func _try_grab() -> void:
	if _grab_active:
		return
	var selected: Array = []
	for it in _hand_items:
		if it.get("hl", false):
			selected.append(int(it.get("id", -1)))
	if selected.is_empty():
		return
	# near any selected card (also the outermost ones of a full fan) or near the left hand itself
	var near := _point.global_position.distance_to(_holder.global_position) < 0.2
	for id in selected:
		if _hand_cards.has(id) and _point.global_position.distance_to(_hand_cards[id].global_position) < HAND_GRAB_RADIUS:
			near = true
			break
	if not near:
		return
	_grab_active = true
	_grabbed = selected
	# the grabbed cards now belong to the grabbing hand: they follow its position AND rotation
	for id in _grabbed:
		if _hand_cards.has(id):
			_hand_cards[id].reparent(_grab_anchor, true)


## Grabbed cards glide into a small fan between the fingers of the grabbing hand.
func _update_bundle() -> void:
	var k := 1.0 - exp(-14.0 * get_process_delta_time())
	var fan_plane := Basis(Vector3.RIGHT, deg_to_rad(FAN_TILT))
	var n := _grabbed.size()
	for i in n:
		var id: int = _grabbed[i]
		if not _hand_cards.has(id):
			continue
		var offset := float(i) - (n - 1) / 2.0
		var target := Transform3D(fan_plane * Basis(Vector3.BACK, deg_to_rad(-offset * 6.0)),
			fan_plane * Vector3(offset * 0.03, 0.0, offset * 0.0015)) # relative to the grab anchor
		var card: Node3D = _hand_cards[id]
		card.transform = card.transform.interpolate_with(target, k)


## Puts grabbed cards back into the card hand (after a gesture, or when grabbing is interrupted).
func _return_grabbed_cards() -> void:
	for id in _grabbed:
		if _hand_cards.has(id) and is_instance_valid(_hand_cards[id]):
			_hand_cards[id].reparent(_fan_anchor, true)
	_grab_active = false
	_grabbed = []
	_rebuild_hand(_hand_items)


func _release_bundle() -> void:
	var pos := _point.global_position
	var sent := ""
	if _chip.visible and pos.distance_to(_chip.global_position) < CHIP_HIT_RADIUS:
		sent = "play"
	elif _is_behind_shoulder(pos):
		sent = "discard"
	if sent == "":
		_return_grabbed_cards()
		return
	_send({"cmd": sent})
	# played or thrown away: the cards stay right where they were let go and fly on from there
	# (to the table or the discard pile) – not back through the card hand first. If the game
	# doesn't take them (e.g. a hand the boss forbids), they return to the hand after a moment.
	var now := Time.get_ticks_msec() / 1000.0
	for id in _grabbed:
		if _hand_cards.has(id) and is_instance_valid(_hand_cards[id]):
			_hand_cards[id].reparent(self, true)
			_released[id] = now
	_grab_active = false
	_grabbed = []
	_rebuild_hand(_hand_items)


func _is_behind_shoulder(pos: Vector3) -> bool:
	var head_pos := _head.global_position
	var forward := -_head.global_transform.basis.z
	forward.y = 0
	forward = forward.normalized()
	var flat := pos - head_pos
	flat.y = 0
	var behind := flat.dot(forward) < -0.15
	var near := flat.length() < SHOULDER_RADIUS
	var height_ok := pos.y > head_pos.y - 0.7 and pos.y < head_pos.y + 0.1
	return behind and near and height_ok


# ---------------------------------------------------------------- calibration (move / rotate / resize + save)
# Started from the game's Options menu ("Adjust VR Layout"), the left menu button or C (desktop).
# Right grip at an orange handle = move & rotate, right stick up/down while holding = size,
# A = save & leave, Y = back to the default layout. Saved relative to the player, so Y (re-center)
# keeps the personal layout. Joker slots and the draw pile stay on the joker board.

## Shown names of the calibratable items. The keys stay German: they are the keys in the saved
## vr_layout.cfg, so renaming them would throw away everybody's calibration.
const CALIB_LABELS := {
	"Spieltafel": "Game Board", "Blind-Chip": "Blind Chip", "Joker-Tafel": "Joker Board",
	"Kartenstapel": "Deck", "Geldstapel": "Money","Kartenfächer": "Card Fan", "Gegriffene Karten": "Grabbed Cards",
	"Run-Panel": "Run Panel", "Shop": "Shop", "Reroll-Automat": "Reroll Machine", "Münzschlitz": "Coin Slot", "Kartentasche": "Card Stand",
}


## handle_height < 0: default height of the orange grab handle above the item's origin.
## handle_at: put the handle at this point of the item instead (in the item's own coordinates).
func _register_calibratable(label: String, node: Node3D, on_joker_table := false, handle_height := -1.0, handle_at = null) -> void:
	_calib_items[label] = node
	_calib_defaults[label] = node.transform
	if on_joker_table:
		_calib_on_table[label] = true

	var handle := MeshInstance3D.new()
	handle.name = "CalibHandle"
	var sphere := SphereMesh.new()
	sphere.radius = 0.02
	sphere.height = 0.04
	handle.mesh = sphere
	handle.material_override = _glow_material(Color(1.0, 0.55, 0.1), 1.0)
	if handle_height < 0.0:
		handle_height = 0.06 if on_joker_table else 0.0 # above pedestal/pile, easy to reach
	handle.position.y = handle_height
	if handle_at is Vector3:
		handle.position = handle_at
		handle.quaternion = node.quaternion.inverse() # keep the name label above it, even on a tilted item
	handle.visible = false
	if handle_height > 0.1: # raised handle: a thin stem shows what it belongs to
		var stem := MeshInstance3D.new()
		var stem_mesh := CylinderMesh.new()
		stem_mesh.top_radius = 0.003
		stem_mesh.bottom_radius = 0.003
		stem_mesh.height = handle_height
		stem.mesh = stem_mesh
		stem.position.y = -handle_height * 0.5
		stem.material_override = _glow_material(Color(1.0, 0.55, 0.1), 0.6)
		handle.add_child(stem)
	var text := Label3D.new()
	text.text = CALIB_LABELS.get(label, label)
	text.font_size = 40
	text.pixel_size = 0.0008
	text.outline_size = 8
	text.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	text.no_depth_test = true
	text.position = Vector3(0, 0.045, 0)
	handle.add_child(text)
	node.add_child(handle)


func _build_calibration_help() -> void:
	_calib_help = Label3D.new() # text depends on the hand mode, see _update_calibration_help()
	_calib_help.font_size = 40
	_calib_help.pixel_size = 0.0009
	_calib_help.outline_size = 10
	_calib_help.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_calib_help.no_depth_test = true
	_calib_help.position = Vector3(0, 0.42, 0.45)
	_calib_help.visible = false
	_layout.add_child(_calib_help)


func _set_calibrating(on: bool) -> void:
	if on == _calibrating:
		return
	_calibrating = on
	_calib_grabbed = ""
	_drop_joker() # a joker still in the hand goes back onto the board first
	for item in _calib_items.values():
		item.get_node("CalibHandle").visible = on
	_calib_help.visible = on
	_joker_mat.visible = on
	if _grab_anchor != null:
		_grab_anchor.get_node("CalibPreview").visible = on
	_shop_sign.visible = on or not _shop_sign_info.is_empty()
	if on:
		if _grab_active:
			_return_grabbed_cards()
		# show chip, joker board and pile even outside a run so they can be placed
		_chip.visible = true
		_deck.visible = true
		_coins.visible = true
		_joker_table.visible = true
		_set_status("Calibration active")
	else:
		_save_layout()
		_chip.visible = false
		_deck.visible = false
		_coins.visible = false
		_joker_table.visible = false
		_apply_state(_state)
		_set_status("Layout saved")


## Either hand can grab in calibration, but never a handle that hangs on that hand itself
## (the card fan sits on the card hand, the grabbed-cards spot on the pointing hand).
func _calib_grab(hand: XRController3D) -> void:
	var best := ""
	var best_dist := CALIB_GRAB_RADIUS
	for label in _calib_items:
		var handle: Node3D = _calib_items[label].get_node("CalibHandle")
		if not handle.is_visible_in_tree() or hand.is_ancestor_of(handle):
			continue
		var dist := handle.global_position.distance_to(hand.global_position)
		if dist < best_dist:
			best_dist = dist
			best = label
	if best == "":
		return
	var node: Node3D = _calib_items[best]
	_calib_grabbed = best
	_calib_hand = hand
	_calib_scale = node.scale.x
	var unscaled := Transform3D(node.global_transform.basis.orthonormalized(), node.global_transform.origin)
	_calib_offset = hand.global_transform.affine_inverse() * unscaled


func _update_calibration(delta: float) -> void:
	if _calib_grabbed == "":
		return
	var node: Node3D = _calib_items[_calib_grabbed]
	var on_table: bool = _calib_on_table.has(_calib_grabbed)
	var stick := _calib_hand.get_vector2("primary")
	if absf(stick.y) > 0.3 and not on_table:
		_calib_scale = clampf(_calib_scale * (1.0 + stick.y * delta * 0.8), 0.2, 4.0)
	var t := _calib_hand.global_transform * _calib_offset
	node.global_transform = Transform3D(t.basis * Basis.from_scale(Vector3.ONE * _calib_scale), t.origin)
	if _calib_grabbed == "Joker-Tafel":
		_keep_level(node)
	if on_table:
		_keep_on_joker_table(node)


## The joker board always lies flat: it can be moved freely, scaled, and turned only around the
## vertical axis (tilting it by accident made it hard to get level again).
func _keep_level(node: Node3D) -> void:
	var t := node.transform
	var facing := t.basis.z
	facing.y = 0
	var yaw := atan2(facing.x, facing.z) if facing.length() > 0.001 else 0.0
	node.transform = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * t.basis.get_scale().x), t.origin)


func _reset_layout() -> void:
	for label in _calib_items:
		_calib_items[label].transform = _default_transform(label)
	_calib_grabbed = ""


## Default place of an item; mirrored left/right for left-handers (run panel left, pile left ...).
func _default_transform(label: String) -> Transform3D:
	var t: Transform3D = _calib_defaults[label]
	if not _left_handed:
		return t
	var flip := Basis.from_scale(Vector3(-1, 1, 1))
	return Transform3D(flip * t.basis * flip, Vector3(-t.origin.x, t.origin.y, t.origin.z))


## Each hand mode keeps its own calibration.
func _layout_section() -> String:
	# seated and standing each keep their own layout (a desk at sitting height, or a high table)
	return ("layout_left_handed" if _left_handed else "layout") + ("_standing" if _standing else "")


## Sitting / standing: switches to the other mode's own calibration and puts everything in front
## of you again (at the new head height).
func _set_standing(on: bool) -> void:
	if on == _standing:
		return
	if _calibrating:
		_set_calibrating(false) # saves the current mode's layout first
	_standing = on
	var cfg := ConfigFile.new()
	cfg.load(LAYOUT_FILE)
	cfg.set_value("settings", "standing", on)
	if not cfg.has_section(_layout_section()) and cfg.has_section(_layout_section().trim_suffix("_standing")):
		# the first time standing: start from the seated layout (then adjust it standing)
		for key in cfg.get_section_keys(_layout_section().trim_suffix("_standing")):
			cfg.set_value(_layout_section(), key, cfg.get_value(_layout_section().trim_suffix("_standing"), key))
	cfg.save(LAYOUT_FILE)
	_load_layout()
	if _vr:
		_place_layout()
	_set_status("Standing" if on else "Sitting")


## The menu button (≡): the VR settings above your card hand.
func _toggle_wrist_menu() -> void:
	if not _vr:
		return
	if _wrist == null:
		_wrist = WristMenu.new()
		add_child(_wrist)
		_wrist.eyes = _eyes
		_wrist.setup([
			{"label": func(): return "Adjust VR Layout", "action": func():
				_wrist.visible = false
				_set_calibrating(true)},
			{"label": func(): return "Recenter", "action": func(): _place_layout()},
			{"label": func(): return "Mode: " + ("Standing" if _standing else "Sitting"), "action": func(): _set_standing(not _standing)},
			{"label": func(): return "Background: " + ["Passthrough", "Green", "Casino"][_backdrop], "action": func(): _next_backdrop()},
			{"label": func(): return "Calm Lights: " + ("On" if _calm else "Off"), "action": func(): _set_calm(not _calm)},
			{"label": func(): return "Hands: " + ("On" if _hands_on else "Off"), "action": func(): _set_hands(not _hands_on)},
			{"label": func(): return "Casino Sounds: " + ("On" if _ambience_on else "Off"), "action": func(): _set_ambience(not _ambience_on)},
			{"label": func(): return "Spectator: " + Spectator.NAMES[_spectator.mode], "action": func(): _spectator.next_mode()},
			{"label": func(): return "Switch Hands", "action": func(): _set_left_handed(not _left_handed)},
			{"label": func(): return "Show Tips", "action": func():
				_wrist.visible = false
				_show_tutorial()},
			{"label": func(): return "Close", "action": func(): _wrist.visible = false},
		])
		_wrist.visible = false
	_wrist.hand = _holder
	_wrist.visible = not _wrist.visible
	_wrist.refresh()


func _save_layout() -> void:
	var cfg := ConfigFile.new()
	cfg.load(LAYOUT_FILE) # keep the other hand mode's layout and the settings
	cfg.set_value("meta", "version", LAYOUT_VERSION)
	cfg.set_value("settings", "left_handed", _left_handed)
	for label in _calib_items:
		cfg.set_value(_layout_section(), label, _calib_items[label].transform)
	var err := cfg.save(LAYOUT_FILE)
	if err != OK:
		push_warning("Layout konnte nicht gespeichert werden (Fehler %d)" % err)


func _load_layout() -> void:
	for label in _calib_items:
		_calib_items[label].transform = _default_transform(label)
	var cfg := ConfigFile.new()
	if cfg.load(LAYOUT_FILE) != OK:
		return
	var version: int = cfg.get_value("meta", "version", 1)
	var section := _layout_section()
	for label in _calib_items:
		if not cfg.has_section_key(section, label):
			if label == "Kartentasche": # new: it starts next to the coin slot, towards the middle of the board
				var inward := -signf(_coin_slot.position.x) if absf(_coin_slot.position.x) > 0.01 else 1.0
				_bag.transform = Transform3D(_coin_slot.basis, _coin_slot.position + Vector3(inward * 0.15, 0, 0))
				_keep_on_joker_table(_bag)
			continue # saved before this item existed: keep its default
		if version < 3 and _calib_on_table.has(label):
			continue # the joker board changed shape: slots and pile start fresh on it
		var t = cfg.get_value(section, label)
		if t is Transform3D:
			_calib_items[label].transform = t
			if label == "Joker-Tafel":
				_keep_level(_calib_items[label]) # a board saved tilted lies flat again
			if _calib_on_table.has(label):
				_keep_on_joker_table(_calib_items[label]) # the mat may have changed size since saving


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(LAYOUT_FILE) == OK:
		_left_handed = cfg.get_value("settings", "left_handed", false)
		_calm = cfg.get_value("settings", "calm_lights", false)
		_hands_on = cfg.get_value("settings", "hands", true)
		_ambience_on = cfg.get_value("settings", "casino_sounds", true)
		_standing = cfg.get_value("settings", "standing", false)
		if _spectator != null:
			var spec = cfg.get_value("settings", "spectator", "Off")
			if spec is int: # saved as a number before there were five views: 0 off, 1 eyes, 2 shoulder, 3 room
				spec = ["Off", "Eyes", "Shoulder", "Room"][clampi(spec, 0, 3)]
			_spectator.set_mode(maxi(Spectator.NAMES.find(str(spec)), 0))
	_casino.ambience.set_active(_backdrop == Backdrop.ROOM and _ambience_on)
	_casino.set_calm(_calm)
	for g in _gloves:
		g.visible = _hands_on


## Jimbo's tips: on the very first start in VR, and from the game's Options menu ("VR: Show Tips").
## The texts name the buttons of the current hand mode.
func _show_tutorial() -> void:
	if not _vr:
		return
	var point := "left" if _left_handed else "right"
	var cards := "right" if _left_handed else "left"
	var play := "X" if _left_handed else "A"
	var discard := "Y" if _left_handed else "B"
	var recenter := "B" if _left_handed else "Y"
	var backdrop := "A" if _left_handed else "X"
	var pages := [
		["Hi, I'm Jimbo!", "Welcome to Balatro in VR. Your cards are in your %s hand. Point at them with your %s hand and pull the trigger to select them - just like clicking." % [cards, point]],
		["Play & discard", "Grab the selected cards with your %s grip and let go over the golden blind chip to play them (or press %s). Throw them over your shoulder to discard (or press %s)." % [point, play, discard]],
		["Your table", "Jokers stand on the board: touch one to read it, grab it to move it - left to right is their order. Drop one into the SELL slot to sell it. Lift it and look underneath for its price. Pull the slot machine's lever to reroll the shop."],
		["Packs & cards", "Booster packs float up to you: grab them with both hands and tear them open (or point and pull the trigger). Tarot and planet cards wait in the little bag - point at one and pull the trigger to use it."],
		["Make it yours", "The menu button (≡) on your left controller opens the VR settings above your card hand: layout, sitting / standing, background, Calm Lights, sounds, spectator camera. %s brings everything in front of you, %s changes the background. Have fun!" % [recenter, backdrop]],
	]
	if _tutorial == null:
		_tutorial = VRTutorial.new()
		add_child(_tutorial)
		_tutorial.finished.connect(func():
			var cfg := ConfigFile.new()
			cfg.load(LAYOUT_FILE)
			cfg.set_value("settings", "tutorial_done", true)
			cfg.save(LAYOUT_FILE))
	# in front of you, a little below eye level, turned to you
	var fwd := -_head.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var at := _head.global_position + fwd * 0.7 + Vector3(0, -0.12, 0)
	_tutorial.global_transform = Transform3D(Basis(Vector3.UP, atan2(-fwd.x, -fwd.z)), at)
	_tutorial.setup(pages)


## "VR: Spectator" in the game's Options menu: off -> eyes -> shoulder -> room -> off. Also the keys
## 1 / 2 / 3 in the spectator window. Kept in the settings.
func _cycle_spectator() -> void:
	if _spectator == null:
		return
	_spectator.next_mode() # (saved by the mode_changed signal)


func _save_spectator() -> void:
	var cfg := ConfigFile.new()
	cfg.load(LAYOUT_FILE)
	cfg.set_value("settings", "spectator", Spectator.NAMES[_spectator.mode]) # by name: survives new views
	cfg.save(LAYOUT_FILE)
	_send_flags()
	_set_status("Spectator camera: " + Spectator.NAMES[_spectator.mode])


## Tells the mod our settings, so the Options menu buttons show their state.
## "VR: Casino Sounds" in VR Settings: the casino's own sounds (slot machines, glasses, chips) on
## or off. The game's sounds are not affected.
func _set_ambience(on: bool) -> void:
	_ambience_on = on
	_casino.ambience.set_active(_backdrop == Backdrop.ROOM and on)
	var cfg := ConfigFile.new()
	cfg.load(LAYOUT_FILE)
	cfg.set_value("settings", "casino_sounds", on)
	cfg.save(LAYOUT_FILE)
	_send_flags()
	_set_status("Casino sounds on" if on else "Casino sounds off")


func _send_flags() -> void:
	_send({"cmd": "vr_flags", "calm": _calm, "hands": _hands_on,
		"spec": Spectator.NAMES[_spectator.mode] if _spectator != null else "Off", "amb": _ambience_on})


## "VR: Hands" in the game's Options menu: Jimbo's gloves on or off (then only the beam).
func _set_hands(on: bool) -> void:
	_hands_on = on
	for g in _gloves:
		g.visible = on
	var cfg := ConfigFile.new()
	cfg.load(LAYOUT_FILE)
	cfg.set_value("settings", "hands", on)
	cfg.save(LAYOUT_FILE)
	_send_flags()
	_set_status("Hands on" if on else "Hands off")


## "VR: Calm Lights" in the game's Options menu: no flashes, flicker or pulsing light (for
## photosensitive players); the casino stays dim. Kept in the settings and told to the mod, whose
## button shows the current state.
func _set_calm(on: bool) -> void:
	_calm = on
	_casino.set_calm(on)
	var cfg := ConfigFile.new()
	cfg.load(LAYOUT_FILE)
	cfg.set_value("settings", "calm_lights", on)
	cfg.save(LAYOUT_FILE)
	_send_flags()
	_set_status("Calm Lights on" if on else "Calm Lights off")


# ---------------------------------------------------------------- left-handed mode
# Toggled with "VR: Switch Hands" in the game's Options menu or H on the desktop.

func _set_left_handed(on: bool) -> void:
	if on == _left_handed:
		return
	if _calibrating:
		_set_calibrating(false) # saves the current mode's layout first
	_left_handed = on
	var cfg := ConfigFile.new()
	cfg.load(LAYOUT_FILE)
	cfg.set_value("settings", "left_handed", on)
	cfg.save(LAYOUT_FILE)
	_load_layout()
	_apply_handedness()
	_set_status("Left-handed mode" if on else "Right-handed mode")


## Gives the beam and the fan of cards to the right hands for the current mode.
func _apply_handedness() -> void:
	_update_calibration_help()
	if not _vr:
		return
	_point = _left if _left_handed else _right
	_holder = _right if _left_handed else _left
	for node in [_ray, _beam]:
		if node.get_parent() != _point:
			if node.get_parent() != null:
				node.get_parent().remove_child(node)
			_point.add_child(node)
	# the fan anchor keeps its (calibrated) place relative to whichever hand holds the cards
	if _grab_anchor.get_parent() != _point:
		if _grab_anchor.get_parent() != null:
			_grab_anchor.get_parent().remove_child(_grab_anchor)
		_point.add_child(_grab_anchor)
	if _fan_anchor.get_parent() != _holder:
		if _fan_anchor.get_parent() != null:
			_fan_anchor.get_parent().remove_child(_fan_anchor)
		_holder.add_child(_fan_anchor)
	if _grab_active:
		_grab_active = false
		_grabbed = []
	for id in _hand_cards.keys(): # rebuild the fan in the other hand
		_hand_cards[id].queue_free()
	_hand_cards.clear()
	_rebuild_hand(_hand_items)


func _update_calibration_help() -> void:
	if _calib_help == null:
		return
	var point_hand := "left" if _left_handed else "right"
	var card_hand := "right" if _left_handed else "left"
	var save_button := "X" if _left_handed else "A"
	var reset_button := "B" if _left_handed else "Y"
	_calib_help.text = "Adjust VR Layout (%s)\n" % ("left-handed" if _left_handed else "right-handed") \
		+ "Grip (%s controller) on an orange dot: move & rotate\n" % point_hand \
		+ "\"Grabbed Cards\" sits on this hand: grab it with the %s grip\n" % card_hand \
		+ "While holding, stick up/down: size\n" \
		+ "Deck, money, machine, coin slot and card bag stay on the Joker Board\n" \
		+ "%s: save & exit   ·   %s: default layout" % [save_button, reset_button]


# ---------------------------------------------------------------- background / passthrough

func _available_backdrops() -> Array:
	var modes: Array = []
	if _vr and _xr.get_supported_environment_blend_modes().has(XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND):
		modes.append(Backdrop.PASSTHROUGH)
	modes.append(Backdrop.GREEN)
	modes.append(Backdrop.ROOM)
	return modes


func _next_backdrop() -> void:
	var modes := _available_backdrops()
	var i := modes.find(_backdrop)
	_set_backdrop(modes[(i + 1) % modes.size()])


func _set_backdrop(mode: Backdrop) -> void:
	_backdrop = mode
	var see_through := mode != Backdrop.ROOM
	_casino.visible = not see_through
	# the casino is lit by its own warm lamps; in passthrough the neutral light shows models best
	_sun.light_energy = 0.08 if not see_through else 1.0 # late at night: neon and the table lamp light the room
	_env.ambient_light_color = Color(0.2, 0.17, 0.26) if not see_through else Color(0.6, 0.6, 0.6)
	_board.set_backing_visible(false) # panels float freely in every mode; a green felt wall breaks the casino
	_board.opaque_mode = mode == Backdrop.GREEN
	CardArt.solid_debuff = mode == Backdrop.GREEN # faded debuffed cards would mix with the green
	if _vr and not _hand_items.is_empty():
		_rebuild_hand(_hand_items)
	_board.hide_dimmers = see_through
	_env.glow_enabled = mode != Backdrop.GREEN # bloom halos would tint the chroma-key green
	# the casino: smoky air that swallows the far corners, filmic colours with a bit more contrast
	# (passthrough and green stay neutral)
	_env.fog_enabled = mode == Backdrop.ROOM
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC if mode == Backdrop.ROOM else Environment.TONE_MAPPER_LINEAR
	_env.adjustment_enabled = mode == Backdrop.ROOM
	_jimbo.visible = mode == Backdrop.ROOM # Jimbo only sits at the virtual casino table
	_casino.ambience.set_active(mode == Backdrop.ROOM and _ambience_on) # the casino's slot machines, glasses, chips
	_set_room_reverb(mode == Backdrop.ROOM)
	_stars.set_hard_edges(mode == Backdrop.GREEN)
	_confetti.set_hard_edges(mode == Backdrop.GREEN)
	if not _last_scene.is_empty():
		_board.apply_scene(_last_scene) # redraw translucent panels for the new mode
	match mode:
		Backdrop.PASSTHROUGH:
			# real passthrough from the runtime (Virtual Desktop supports alpha blending)
			_xr.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND
			get_viewport().transparent_bg = true
			_env.background_mode = Environment.BG_COLOR
			_env.background_color = Color(0, 0, 0, 0)
			_set_status("Background: passthrough")
		Backdrop.GREEN:
			# pure green for Virtual Desktop's chroma-key passthrough
			if _vr:
				_xr.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_OPAQUE
			get_viewport().transparent_bg = false
			_env.background_mode = Environment.BG_COLOR
			_env.background_color = Color(0, 1, 0)
			_set_status("Background: green (Virtual Desktop passthrough)")
		Backdrop.ROOM:
			if _vr:
				_xr.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_OPAQUE
			get_viewport().transparent_bg = false
			_env.background_mode = Environment.BG_COLOR
			_env.background_color = Color(0.01, 0.008, 0.015)
			_set_status("Background: virtual room")


# ---------------------------------------------------------------- scene setup

## The audio bus "Room": every game sound and the casino's own sounds go through it. In the
## virtual casino it adds the reverb of a big hall (tiles, glass, a high ceiling), so sounds sit
## in the room instead of right in your ears; in passthrough / green it stays dry (your own room).
func _setup_room_bus() -> void:
	if AudioServer.get_bus_index("Room") >= 0:
		return
	AudioServer.add_bus()
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, "Room")
	AudioServer.set_bus_send(idx, "Master")
	var reverb := AudioEffectReverb.new()
	reverb.room_size = 0.6
	reverb.damping = 0.55
	reverb.spread = 0.85
	reverb.predelay_msec = 25.0
	reverb.hipass = 0.12
	reverb.dry = 1.0
	reverb.wet = 0.0
	AudioServer.add_bus_effect(idx, reverb)


func _set_room_reverb(on: bool) -> void:
	var idx := AudioServer.get_bus_index("Room")
	if idx < 0:
		return
	var reverb := AudioServer.get_bus_effect(idx, 0) as AudioEffectReverb
	reverb.wet = 0.17 if on else 0.0


func _start_xr() -> bool:
	_xr = XRServer.find_interface("OpenXR")
	if _xr == null or not _xr.initialize():
		return false
	get_viewport().use_xr = true
	get_viewport().msaa_3d = Viewport.MSAA_4X # smooth edges: jaggies and shimmering are far more visible in a headset
	return true


func _build_scene() -> void:
	_env = Environment.new()
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.6, 0.6, 0.6)
	_env.glow_enabled = true # bright emission (Cavendish, campfire) blooms into its surroundings
	_env.glow_hdr_threshold = 1.0
	# casino look (switched on in _set_backdrop): dark violet haze, thicker near the floor
	_env.fog_light_color = Color(0.2, 0.13, 0.26) # lit haze: a faint violet veil, not just darkness
	_env.fog_density = 0.04
	_env.fog_sky_affect = 0.0
	_env.fog_height = 0.4
	_env.fog_height_density = 0.12
	_env.tonemap_exposure = 1.15
	_env.tonemap_white = 6.0
	_env.adjustment_contrast = 1.1
	_env.adjustment_saturation = 1.08
	var world_env := WorldEnvironment.new()
	world_env.environment = _env
	add_child(world_env)

	var light := DirectionalLight3D.new()
	add_child(light)
	light.rotation_degrees = Vector3(-50, 30, 0)

	_sun = light
	_casino = CasinoRoom.new() # the "virtual room" background
	add_child(_casino)

	var layer := CanvasLayer.new()
	add_child(layer)
	_status = Label.new()
	_status.position = Vector2(20, 20)
	layer.add_child(_status)

	_layout = Node3D.new()
	_layout.name = "Layout"
	add_child(_layout)
	_layout.position = Vector3(0, 1.3, -1.0)

	_board = Board.new()
	_board.keep_hand_separate = _vr
	_board.popup_anchor_for = _popup_anchor_for
	_layout.add_child(_board)

	_build_anchors()
	_drag_ghost = Node3D.new()
	_drag_ghost.name = "DragGhost"
	_drag_ghost.visible = false
	add_child(_drag_ghost)
	_build_chip()
	_build_joker_table()
	_build_deck()
	_build_table_fun()

	_stars = StarField.new()
	add_child(_stars)
	_confetti = Confetti.new()
	add_child(_confetti)

	_intro = IntroCards.new()
	_intro.position = Vector3(0, 0, 0.25) # a little in front of the board
	_layout.add_child(_intro)

	_status3d = Label3D.new()
	_status3d.text = "Waiting for Balatro ...\nStart the game with the Balatro in VR mod"
	_status3d.font_size = 64
	_status3d.pixel_size = 0.0015
	_status3d.position = Vector3(0, 0, 0.01)
	_board.add_child(_status3d)
	_set_status("Waiting for Balatro ... (start the game with the mod)")

	if _vr:
		_build_xr_rig()
		_board.rotation_degrees = Vector3(-10, 0, 0) # lean back a little like a lectern
		_set_backdrop(_available_backdrops()[0])
	else:
		_camera = Camera3D.new()
		add_child(_camera)
		_layout.position = Vector3(0, 1.2, 0)
		_camera.position = Vector3(0.25, 1.15, 1.9)
		_camera.look_at(Vector3(0.25, 0.85, 0.2))
		_set_backdrop(Backdrop.ROOM)

	_register_calibratable("Spieltafel", _board)
	_register_calibratable("Blind-Chip", _chip)
	# handle well above the mat: lower it onto the real table without the controller hitting the table
	_register_calibratable("Joker-Tafel", _joker_table, false, 0.25)
	_register_calibratable("Kartenstapel", _deck, true, 0.17) # handle above the "52 / 52" count
	_register_calibratable("Geldstapel", _coins, true)
	_register_calibratable("Reroll-Automat", _lever, true, 0.19) # handle above the lever's red ball
	_register_calibratable("Münzschlitz", _coin_slot, true, 0.1)
	_register_calibratable("Kartentasche", _bag, true, 0.16) # handle above the cards in the stand
	# (no handles for the joker places: every joker is simply picked up and put where you like)
	if _vr: # position, tilt and size of the card fan, relative to the hand that holds it
		_register_calibratable("Kartenfächer", _fan_anchor)
		# where grabbed cards sit in the pointing hand – grabbed with the other hand's grip
		_register_calibratable("Gegriffene Karten", _grab_anchor)
	_build_calibration_help()
	_load_settings()
	if _spectator != null: # from here on every change (Options button or keys 1-3 in its window) is kept
		_spectator.mode_changed.connect(func(_m): _save_spectator())
	_load_layout()
	if _vr: # the very first start: Jimbo's tips, once the headset knows where you look
		var cfg := ConfigFile.new()
		cfg.load(LAYOUT_FILE)
		if not cfg.get_value("settings", "tutorial_done", false):
			get_tree().create_timer(2.0).timeout.connect(_show_tutorial)
	_apply_handedness()


func _build_anchors() -> void:
	# Run panel (score, hands, money ...) on the right: the left hand with the cards covers the left side
	var hud := Node3D.new()
	hud.name = "RunPanelAnchor"
	hud.position = PANEL_POS
	hud.rotation_degrees = Vector3(0, PANEL_YAW, 0) # turned towards the player
	hud.scale = Vector3.ONE * PANEL_SCALE
	_layout.add_child(hud)
	_board.anchors["HUD"] = {"node": hud}
	_board.anchors["HUD_blind"] = {"node": hud, "ref": "HUD"} # blind info stays on top of the panel
	_register_calibratable("Run-Panel", hud)

	# Shop lies flat on the table in front of the player
	var shop := Node3D.new()
	shop.name = "ShopAnchor"
	shop.position = SHOP_POS
	shop.rotation_degrees = Vector3(-90, 0, 0)
	_layout.add_child(shop)
	_board.anchors["shop"] = {"node": shop}

	# Animated SHOP sign, leaning back at the far edge of the shop like a counter display
	# (the shop anchor lies flat: its local +Y points away from the player, +Z points up)
	_shop_sign = Node3D.new()
	_shop_sign.name = "ShopSign"
	_shop_sign.position = Vector3(0, SHOP_SIGN_DISTANCE, SHOP_SIGN_HEIGHT)
	_shop_sign.rotation_degrees = Vector3(SHOP_SIGN_TILT, 0, 0)
	_shop_sign.visible = false
	shop.add_child(_shop_sign)
	# grab the shop by its SHOP sign: the handle sits right above the sign
	_register_calibratable("Shop", shop, false, -1.0,
			Vector3(0, SHOP_SIGN_DISTANCE, SHOP_SIGN_HEIGHT + SHOP_SIGN_SIZE.y * 0.5 + 0.03))


func _build_chip() -> void:
	_chip = Node3D.new()
	_chip.name = "BlindChip"
	_chip.position = CHIP_POS
	_layout.add_child(_chip)
	_chip_spinner = Node3D.new()
	_chip.add_child(_chip_spinner)

	var disc := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = CHIP_RADIUS
	cylinder.bottom_radius = CHIP_RADIUS
	cylinder.height = 0.008
	disc.mesh = cylinder
	disc.rotation_degrees = Vector3(90, 0, 0) # faces forward/backward like a coin
	disc.material_override = _glow_material(Color(0.85, 0.65, 0.2), 0.25)
	_chip_spinner.add_child(disc)

	_chip_front = Node3D.new()
	_chip_front.position.z = 0.0045
	_chip_spinner.add_child(_chip_front)
	_chip_back = Node3D.new()
	_chip_back.position.z = -0.0045
	_chip_back.rotation_degrees = Vector3(0, 180, 0)
	_chip_spinner.add_child(_chip_back)
	_chip.visible = false


func _build_deck() -> void:
	_deck = Node3D.new()
	_deck.name = "DrawPile"
	_deck.position = DECK_POS
	_joker_table.add_child(_deck) # front left corner of the joker board

	_deck_body = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	_deck_body.mesh = box
	var side_mat := StandardMaterial3D.new()
	side_mat.albedo_color = Color(0.8, 0.2, 0.2)
	_deck_body.material_override = side_mat
	_deck.add_child(_deck_body)

	# the back art lies face up on top of the pile
	_deck_top = Node3D.new()
	_deck_top.rotation_degrees = Vector3(-90, 0, 0)
	_deck.add_child(_deck_top)

	_deck_label = Label3D.new()
	_deck_label.font_size = 48
	_deck_label.pixel_size = 0.0007
	_deck_label.outline_size = 8
	_deck_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_deck.add_child(_deck_label)
	_deck.visible = false

	_coins = CoinPile.new()
	_coins.name = "Coins"
	_coins.position = COINS_POS
	_joker_table.add_child(_coins)
	_coins.visible = false


func _place_layout() -> void:
	var head_pos := _head.global_position
	var forward := -_head.global_transform.basis.z
	forward.y = 0
	if forward.length() < 0.01:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	var center := head_pos + forward * BOARD_DISTANCE
	center.y = head_pos.y - 0.1
	_layout.global_position = center
	_layout.look_at(center + forward, Vector3.UP) # layout front (+Z) faces the player
	_layout_placed = true


func _build_xr_rig() -> void:
	var origin := XROrigin3D.new()
	add_child(origin)

	_head = XRCamera3D.new()
	origin.add_child(_head)

	_left = XRController3D.new()
	_left.tracker = "left_hand"
	origin.add_child(_left)
	_right = XRController3D.new()
	_right.tracker = "right_hand"
	origin.add_child(_right)
	for controller in [_left, _right]:
		controller.button_pressed.connect(_on_button.bind(controller))
		controller.button_released.connect(_on_button_released.bind(controller))
	# Jimbo's gloves: on the grip pose (where the hand holds the controller), posed by the controls
	for side in [true, false]:
		var grip := XRController3D.new()
		grip.tracker = "left_hand" if side else "right_hand"
		grip.pose = &"grip"
		origin.add_child(grip)
		var glove := JimboHand.new()
		glove.left = side
		grip.add_child(glove)
		_gloves.append(glove)
	# the calm spectator camera in its own window (for recording); the headset never sees the
	# player's jester hat that only this camera shows
	_head.cull_mask &= ~Spectator.HAT_LAYER
	_spectator = Spectator.new()
	_spectator.head = _head
	_spectator.focus = func(): # the middle of the table, at its (calibrated) height
		var p := _layout.to_global(PLAY_ROW)
		p.y = _joker_table.global_position.y
		return p
	_spectator.place = func(): # your place in the room (fixed; moves only when re-centred)
		var yaw := Basis(Vector3.UP, _layout.global_basis.get_euler().y)
		return Transform3D(yaw, _layout.to_global(PLANET_CENTER))
	_spectator.overview = func(): # between the played cards and the joker board
		var p := _layout.to_global(PLAY_ROW).lerp(_joker_table.global_position, 0.5)
		p.y = _joker_table.global_position.y
		return p
	add_child(_spectator)

	# beam and fan get their hand in _apply_handedness()
	_fan_anchor = Node3D.new()
	_fan_anchor.name = "FanAnchor"
	_fan_anchor.position = HAND_OFFSET
	_grab_anchor = Node3D.new()
	_grab_anchor.name = "GrabAnchor"
	_grab_anchor.position = HAND_OFFSET
	# see-through stand-in card, shown while calibrating: this is where grabbed cards will sit
	var preview := MeshInstance3D.new()
	preview.name = "CalibPreview"
	var card_shape := BoxMesh.new()
	card_shape.size = CARD_SIZE
	preview.mesh = card_shape
	var preview_mat := StandardMaterial3D.new()
	preview_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	preview_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	preview_mat.albedo_color = Color(1.0, 0.85, 0.5, 0.45)
	preview.material_override = preview_mat
	preview.basis = Basis(Vector3.RIGHT, deg_to_rad(FAN_TILT)) # tilted like the cards
	preview.visible = false
	_grab_anchor.add_child(preview)
	_ray = RayCast3D.new()
	_ray.target_position = Vector3(0, 0, -BEAM_LENGTH)
	_ray.enabled = true

	_beam = MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.002
	cylinder.bottom_radius = 0.002
	cylinder.height = BEAM_LENGTH
	_beam.mesh = cylinder
	_beam.rotation_degrees = Vector3(90, 0, 0)
	_set_beam_length(BEAM_LENGTH)
	_beam.material_override = _glow_material(Color(0.4, 0.8, 1.0), 1.0)

	_reticle = MeshInstance3D.new()
	var dot := SphereMesh.new()
	dot.radius = 0.006
	dot.height = 0.012
	_reticle.mesh = dot
	_reticle.material_override = _glow_material(Color(1, 1, 1), 1.0)
	_reticle.visible = false
	add_child(_reticle)


func _glow_material(colour: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.emission_enabled = true
	mat.emission = colour
	mat.emission_energy_multiplier = energy
	return mat


# ================================================================ table fun
# Booster packs to tear open, played cards scoring on the table, the reroll lever, the coin slot,
# consumables to use by gesture, touching jokers, shattering chips and glass, flying coins,
# hand-level planets, spatial sound, Jimbo at the table and neon that follows the game.

const JOKER_ZONE_HALF := 0.29                   # jokers stand in the middle of the board, the ends hold machine and slot
const LEVER_POS := Vector3(0.385, JOKER_TABLE_TOP, 0.06)   # reroll machine (pointing-hand end of the board)
const SLOT_POS := Vector3(-0.385, JOKER_TABLE_TOP, 0.1)    # coin slot (other end)
const BAG_POS := Vector3(-0.385, JOKER_TABLE_TOP, -0.1)   # the bag with the consumables (other end of the board)
const BAG_SIZE := Vector3(0.2, 0.03, 0.07)    # the card stand: width, height, depth
const PLAY_ROW := Vector3(0.0, TABLE_Y, 0.3)    # the played-cards stand (layout space; the shop's spot)
const PLAY_SPACING := 0.085
const PLAY_STAND_SIZE := Vector2(0.5, 0.13)     # width x depth of the slanted board
const PLAY_TILT := 35.0                         # degrees; the back edge is raised
const PLAY_STAND_LIFT := 0.05                   # height of its front edge above the table
const PLANET_CENTER := Vector3(0, 0.3, 1.0)     # layout space: about the player's head
const TABLE_CARD := Vector2(0.063, 0.088)
const TOUCH_RADIUS := 0.08                      # a hand this close (sideways) to a joker model "touches" it
const SLOT_RADIUS := 0.09                       # let go this close to the coin slot = sell

var _sounds: SoundBank
var _planets: HandPlanets
var _jimbo: JimboCompanion
var _pack: PackTear
var _lever: RerollLever
var _coin_slot: Node3D
var _bag: Node3D                 # the leather bag the consumables stand in
var _play_stand: Node3D
var _play_cards := {}            # card id -> card lying on the table
var _hand_last := {}             # hand card id -> its last transform (played cards fly from there)
var _consumables := {}           # uid -> card standing in the rack
var _held_consumable := -1
var _held_consumable_hand: XRController3D
var _held_consumable_offset := Transform3D()
var _held_prev := Vector3.ZERO
var _held_velocity := Vector3.ZERO
var _touch_uid := -1
var _touch_left := 0.0
var _heat := 0.0
var _last_dollars := -999999
var _last_state_name := ""
var _money_from := Vector3.ZERO
var _money_from_time := -10.0
var _last_clink := 0.0


func _build_table_fun() -> void:
	_lever = RerollLever.new()
	_joker_table.add_child(_lever)
	_lever.pulled.connect(_on_lever_pulled)
	_coin_slot = _make_coin_slot()
	_joker_table.add_child(_coin_slot)
	# right-handed defaults; left-handers get them mirrored (and both are calibratable)
	_lever.position = LEVER_POS
	_coin_slot.position = SLOT_POS
	_bag = _make_card_bag()
	_joker_table.add_child(_bag)
	_bag.position = BAG_POS
	_play_stand = _make_play_stand()
	_layout.add_child(_play_stand)
	_play_stand.position = PLAY_ROW
	_play_stand.visible = false
	_sounds = SoundBank.new()
	add_child(_sounds)
	_sounds.where = _sound_position
	_casino.ambience.sounds = _sounds
	_casino._boss_room.eyes = _eyes # The Eye looks at you
	_coins.landed.connect(_on_coin_landed) # every coin that lands on the pile clinks
	_planets = HandPlanets.new()
	_layout.add_child(_planets) # fixed in the room, centred over the player's place
	_planets.position = PLANET_CENTER
	_planets.visible = false
	_jimbo = JimboCompanion.new()
	_layout.add_child(_jimbo)
	_jimbo.position = Vector3(-1.0, TABLE_Y, 0.35) # on the left end of the table, beside the chip mountain
	_jimbo.look_at_target = _eyes
	_jimbo.visible = false


func _eyes() -> Vector3:
	return _head.global_position if _vr else _camera.global_position


## The card stand on the joker board: a low block of dark polished wood with a groove, the tarot /
## planet / spectral cards you carry stand in it, leaning back a little and fanned out - nothing in
## front of them. A brass plate on its slanted front shows how full your joker and consumable
## slots are ("JOKERS 3/5", "CONSUMABLES 1/2"; a full row turns red). Its own calibratable
## item (local +z faces you); the saved name is still "Kartentasche".
func _make_card_bag() -> Node3D:
	var stand := Node3D.new()
	stand.name = "CardStand"
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.22, 0.1, 0.05)
	wood.roughness = 0.3 # polished
	var felt := StandardMaterial3D.new()
	felt.albedo_color = Color(0.35, 0.05, 0.07) # red velvet in the groove
	felt.roughness = 1.0
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.85, 0.66, 0.3)
	brass.metallic = 0.8
	brass.roughness = 0.3
	var w := BAG_SIZE.x
	var d := BAG_SIZE.z
	for part in [[Vector3(w, 0.014, d), Vector3(0, 0.007, 0), wood],                     # base
			[Vector3(w, 0.03, 0.016), Vector3(0, 0.015, -d * 0.5 + 0.008), wood],          # back rest
			[Vector3(w - 0.004, 0.002, 0.022), Vector3(0, 0.0145, -0.004), felt]]:         # the groove
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = part[0]
		mi.mesh = box
		mi.position = part[1]
		mi.material_override = part[2]
		stand.add_child(mi)
	# the slanted front with the brass plate
	var front := Node3D.new()
	front.position = Vector3(0, 0.014, d * 0.5 - 0.012)
	front.rotation.x = deg_to_rad(-55.0) # leaning towards you
	stand.add_child(front)
	var slope := MeshInstance3D.new()
	var sb := BoxMesh.new()
	sb.size = Vector3(w, 0.03, 0.012)
	slope.mesh = sb
	slope.material_override = wood
	slope.position = Vector3(0, 0.0, 0.0)
	front.add_child(slope)
	var plate := MeshInstance3D.new()
	var pb := BoxMesh.new()
	pb.size = Vector3(w - 0.016, 0.024, 0.002)
	plate.mesh = pb
	plate.material_override = brass
	plate.position = Vector3(0, 0.0, 0.007)
	front.add_child(plate)
	for i in 2:
		var l := Label3D.new()
		l.name = "Jokers" if i == 0 else "Consumables"
		l.font_size = 32
		l.pixel_size = 0.00033
		l.outline_size = 0
		l.modulate = Color(0.15, 0.08, 0.03)
		l.position = Vector3(-w * 0.25 + i * w * 0.5 - 0.004 * i, 0.0, 0.0085)
		front.add_child(l)
	GameFont.apply_to(stand)
	return stand


## The counts on the stand's plate, from the game's card areas ("3/5"; red when full).
func _update_bag_counts(scene: Dictionary) -> void:
	if _bag == null:
		return
	for a in scene.get("areas", []):
		var area := str(a.get("name", ""))
		var label_name := "Jokers" if area == "jokers" else ("Consumables" if area == "consumeables" else "")
		if label_name == "":
			continue
		var l := _bag.find_child(label_name, true, false) as Label3D
		if l == null:
			continue
		var n := int(a.get("n", 0))
		var lim := int(a.get("lim", 0))
		l.text = "%s %d/%d" % [label_name.to_upper(), n, lim]
		l.modulate = Color(0.6, 0.02, 0.02) if lim > 0 and n >= lim else Color(0.15, 0.08, 0.03)


## Where the i-th of n consumables stands in the groove (in joker board space): fanned out,
## leaning back against the rest.
func _bag_spot(i: int, n: int) -> Transform3D:
	var off := i - (n - 1) / 2.0
	var local := Transform3D(Basis(Vector3.BACK, -off * 0.08) * Basis(Vector3.RIGHT, deg_to_rad(-14.0)),
			Vector3(off * minf(0.04, (BAG_SIZE.x - 0.07) / maxf(n - 1, 1)), 0.016 + TABLE_CARD.y * 0.5, -0.006 - (i % 2) * 0.004))
	return _bag.transform * local


## A slanted wooden board on the table: played cards lie on it, raised and tipped towards you,
## so the jokers in front don't hide them. Its foot follows the calibrated table height.
func _make_play_stand() -> Node3D:
	var stand := Node3D.new()
	stand.name = "PlayStand"
	var tilt := deg_to_rad(PLAY_TILT)
	var plank := MeshInstance3D.new()
	var plank_mesh := BoxMesh.new()
	plank_mesh.size = Vector3(PLAY_STAND_SIZE.x, 0.012, PLAY_STAND_SIZE.y)
	plank.mesh = plank_mesh
	plank.material_override = _wood_material(Color(0.42, 0.24, 0.12))
	plank.transform = _play_surface()
	plank.position -= plank.basis.y * 0.006 # top face = the surface
	stand.add_child(plank)
	var dark := _wood_material(Color(0.22, 0.12, 0.07))
	# a lip along the front edge the cards rest against, and a support under the back edge
	var lip := MeshInstance3D.new()
	var lip_mesh := BoxMesh.new()
	lip_mesh.size = Vector3(PLAY_STAND_SIZE.x, 0.022, 0.012)
	lip.mesh = lip_mesh
	lip.material_override = dark
	lip.transform = _play_surface() * Transform3D(Basis(), Vector3(0, 0.005, PLAY_STAND_SIZE.y * 0.5 - 0.006))
	stand.add_child(lip)
	var back_height := PLAY_STAND_SIZE.y * sin(tilt) + PLAY_STAND_LIFT
	for x in [-1.0, 1.0]:
		var leg := MeshInstance3D.new()
		var leg_mesh := BoxMesh.new()
		leg_mesh.size = Vector3(0.025, back_height, 0.025)
		leg.mesh = leg_mesh
		leg.material_override = dark
		leg.position = Vector3(x * (PLAY_STAND_SIZE.x * 0.5 - 0.03), back_height * 0.5, -PLAY_STAND_SIZE.y * cos(tilt) * 0.5 + 0.015)
		stand.add_child(leg)
	var foot := MeshInstance3D.new()
	var foot_mesh := BoxMesh.new()
	foot_mesh.size = Vector3(PLAY_STAND_SIZE.x, PLAY_STAND_LIFT, 0.03)
	foot.mesh = foot_mesh
	foot.material_override = dark
	foot.position = Vector3(0, PLAY_STAND_LIFT * 0.5, PLAY_STAND_SIZE.y * cos(tilt) * 0.5 - 0.015)
	stand.add_child(foot)
	return stand


## The board's top surface in the stand's coordinates: centred, y = its normal.
func _play_surface() -> Transform3D:
	var tilt := deg_to_rad(PLAY_TILT)
	var centre := Vector3(0, PLAY_STAND_LIFT + PLAY_STAND_SIZE.y * 0.5 * sin(tilt), 0)
	return Transform3D(Basis(Vector3.RIGHT, tilt), centre)


func _make_coin_slot() -> Node3D:
	var slot := Node3D.new()
	slot.name = "CoinSlot"
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.12, 0.1, 0.12)
	dark.roughness = 0.4
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(0.9, 0.68, 0.25)
	gold.metallic = 0.6
	gold.roughness = 0.3
	gold.emission_enabled = true
	gold.emission = Color(0.9, 0.68, 0.25)
	gold.emission_energy_multiplier = 0.2
	var hole := StandardMaterial3D.new()
	hole.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hole.albedo_color = Color(0, 0, 0)
	for part in [[Vector3(0.08, 0.05, 0.06), Vector3(0, 0.025, 0), dark], [Vector3(0.084, 0.006, 0.064), Vector3(0, 0.051, 0), gold],
			[Vector3(0.05, 0.002, 0.008), Vector3(0, 0.0545, 0), hole]]:
		var mi := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = part[0]
		mi.mesh = b
		mi.position = part[1]
		mi.material_override = part[2]
		slot.add_child(mi)
	var label := Label3D.new()
	label.text = "SELL"
	label.font_size = 40
	label.pixel_size = 0.0005
	label.modulate = Color(1.0, 0.85, 0.35)
	label.outline_size = 0
	label.position = Vector3(0, 0.025, 0.0305)
	slot.add_child(label)
	return slot


func _sound_position(code: String) -> Vector3:
	if code.begins_with("coin"):
		return _coins.global_position
	if (code.begins_with("card") or code.begins_with("paper")) and _vr and _fan_anchor != null:
		return _fan_anchor.global_position
	var scoring := code.begins_with("chips") or code.begins_with("multhit") or code.begins_with("xchip") or code.begins_with("glass")
	if scoring and not _play_cards.is_empty():
		return _layout.to_global(PLAY_ROW)
	if code in ["button", "highlight1", "highlight2", "cancel"] and _vr:
		return _point.global_position
	return _board.global_position + _board.global_basis.y * -0.2


## A flying coin landed on the pile: a bright clink from the game's own coin sounds (higher, so a
## payout rings like money). At most one every 50 ms, so a big payout doesn't turn into noise.
func _on_coin_landed() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_clink < 0.05:
		return
	var codes: Array = []
	for c in ["coin1", "coin2", "coin3", "coin4", "coin5", "coin6", "coin7"]:
		if _sounds.has_sound(c):
			codes.append(c)
	if codes.is_empty():
		return # the game hasn't played (and sent) any coin sound yet
	_last_clink = now
	_sounds.play({"code": codes.pick_random(), "per": randf_range(1.2, 1.5), "vol": _sounds.last_volume * 0.8, "own": true})


func _buzz_hand(hand: XRController3D, amplitude: float, seconds: float) -> void:
	if _vr and hand != null:
		hand.trigger_haptic_pulse("haptic", 0.0, amplitude, seconds, 0.0)


# ---------------------------------------------------------------- state & scene

func _apply_table_fun(state: Dictionary, in_run: bool) -> void:
	var name := str(state.get("state_name", ""))
	_play_stand.visible = _vr and in_run and ROUND_STATES.has(name)
	_lever.set_shop(bool(state.get("shop_open", false)), bool(state.get("can_reroll", false)), int(state.get("reroll_cost", 0)))
	_planets.visible = in_run
	_planets.set_levels(state.get("hand_levels", []) if in_run else [])
	_sync_consumables(state.get("consumables", []) if in_run else [])
	if ROUND_STATES.has(_last_state_name) and name == "ROUND_EVAL":
		_defeat_chip(bool(state.get("blind", {}).get("boss", false))) # blind beaten: the chip cracks and bursts
	var round_info: Dictionary = state.get("round", {})
	_update_tension(state, in_run, name)
	if in_run and ROUND_STATES.has(name) and not ROUND_STATES.has(_last_state_name):
		_start_shuffle() # a new round begins: the deck is shuffled before the cards are drawn
	var dollars := int(round_info.get("dollars", 0))
	if in_run and _last_dollars > -999999 and dollars != _last_dollars:
		if dollars > _last_dollars:
			_coins.fly_in(_money_source(), dollars - _last_dollars)
		elif dollars >= 0:
			_coins.fly_out(_money_sink(state), _last_dollars - dollars)
	_last_dollars = dollars if in_run else -999999
	var blind: Dictionary = state.get("blind", {})
	var ante := int(round_info.get("ante", 1)) if in_run else 1
	var boss_round := in_run and bool(blind.get("boss", false)) and ROUND_STATES.has(name)
	_casino.set_mood(ante, boss_round, _heat)
	# the boss blind changes the room: its chip's colour and its own effect (walls, eye, chains ...)
	_boss_key = str(blind.get("key", "")) if boss_round else ""
	_casino.set_boss(_boss_key, Board.to_color(blind.get("colour")) if blind.get("colour") != null else Color(1.0, 0.1, 0.1))
	_casino.set_ante(ante, str(state.get("blind_on_deck", "")), in_run) # the Ante clock, "NOW SERVING"
	_casino.set_run_chips(float(round_info.get("run_chips", 0)) if in_run else 0.0) # the chip mountain
	_casino.set_stats(state.get("stats", {}) if state.get("stats") is Dictionary else {}) # Hall of Fame / Shame
	if _pack != null and is_instance_valid(_pack) and not _pack.is_ripped() and not state.get("pack_waiting", false):
		_pack.queue_free() # the game opened it by itself (time out)
		_pack = null
	_last_state_name = name


func _money_source() -> Vector3:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _money_from_time < 2.0:
		return _money_from
	if _chip.visible:
		return _chip.global_position
	return _board.global_position + _board.global_basis.y * -0.25 # the cash-out panel


func _money_sink(state: Dictionary) -> Vector3:
	if state.get("shop_open", false) and _board.anchors.has("shop"):
		return (_board.anchors["shop"]["node"] as Node3D).global_position
	return _board.global_position


## How hot the score burns (the game's flames), for the neon and Jimbo.
func _set_heat(flames: Array) -> void:
	var h := 0.0
	for f in flames:
		h = maxf(h, float(f.get("i", 0.0)))
	if h > 0.45 and _heat <= 0.45:
		_jimbo.react("cheer")
	_heat = h
	_casino.set_heat(h)


# ---------------------------------------------------------------- played cards on the table

func _make_table_card() -> Node3D:
	var card := Node3D.new()
	var face := Node3D.new()
	face.name = "Face"
	card.add_child(face)
	var back := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = TABLE_CARD
	back.mesh = quad
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.85, 0.27, 0.24)
	back.material_override = m
	back.rotation_degrees.y = 180
	back.position.z = -0.0003
	card.add_child(back)
	return card


## Cards in the game's play area lie on the table in front of you; they fly there from the fan.
func _sync_play_cards(items: Array) -> void:
	var played: Array = []
	for it in items:
		if it.get("k", "") == "c" and it.get("area", "") == "play":
			played.append(it)
	var alive := {}
	var n := played.size()
	for i in n:
		var it: Dictionary = played[i]
		var id := int(it.get("id", -1))
		alive[id] = true
		var card = _play_cards.get(id)
		if card == null or not is_instance_valid(card):
			card = _make_table_card()
			add_child(card)
			_play_cards[id] = card
			var start: Transform3D = _layout.global_transform * Transform3D(Basis(), PLAY_ROW + Vector3(0, 0.25, -0.1))
			if _hand_last.has(id):
				start = _hand_last[id]
			card.global_transform = start
			card.set_meta("from", start)
			card.set_meta("t", 0.0)
		CardArt.apply_layers(card.get_node("Face"), CardArt.card_layers(it), TABLE_CARD, 0.0003)
		# lying on the slanted stand, face up (towards you), side by side
		var on_board := Vector3((i - (n - 1) / 2.0) * PLAY_SPACING, 0.002, 0.0)
		card.set_meta("target", _play_surface() * Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-90.0)), on_board))
	for id in _play_cards.keys():
		if not alive.has(id) and is_instance_valid(_play_cards[id]):
			# scored and gone: off to the discard pile beside the deck
			var card: Node3D = _play_cards[id]
			_play_cards.erase(id)
			var pose := _discard_pose()
			_fly(card, card.global_transform, func(): return pose, 0.45, 1.0, 1.0, Callable(), true, 0.08)


func _animate_play_cards(delta: float) -> void:
	for id in _play_cards.keys():
		var card = _play_cards[id]
		if not is_instance_valid(card):
			_play_cards.erase(id)
			continue
		if card.has_meta("leaving"): # scored and gone: off to the discard pile
			var l: float = float(card.get_meta("leaving")) + delta / 0.4
			card.set_meta("leaving", l)
			card.global_position += Vector3(0.9, 0.5, -0.4) * delta
			card.scale = Vector3.ONE * maxf(1.0 - l, 0.01)
			if l >= 1.0:
				card.queue_free()
				_play_cards.erase(id)
			continue
		var target: Transform3D = _play_stand.global_transform * (card.get_meta("target") as Transform3D)
		var t: float = minf(float(card.get_meta("t", 1.0)) + delta / 0.35, 1.0)
		card.set_meta("t", t)
		var from: Transform3D = card.get_meta("from", target)
		var e := 1.0 - (1.0 - t) * (1.0 - t)
		var xf := from.interpolate_with(target, e)
		xf.origin.y += sin(t * PI) * 0.06 # a little hop through the air
		card.global_transform = xf
		var bump: float = card.get_meta("bump", 0.0)
		if bump > 0.0:
			bump = maxf(bump - delta * 4.0, 0.0)
			card.set_meta("bump", bump)
		card.scale = Vector3.ONE * (1.0 + 0.25 * sin(bump * PI))


## "+30", "X2", "$3": the card (or joker) that scored pops and its number floats up from it.
func _score_pop(ev: Dictionary) -> void:
	var uid := int(ev.get("uid", -1))
	var at := Vector3.ZERO
	var found := false
	if _play_cards.has(uid) and is_instance_valid(_play_cards[uid]):
		var card: Node3D = _play_cards[uid]
		card.set_meta("bump", 1.0)
		at = card.global_position + Vector3(0, 0.06, 0)
		found = true
	elif _jokers.has(uid) and is_instance_valid(_jokers[uid]):
		var j: Node3D = _jokers[uid]
		j.set_meta("bump", 1.0)
		at = j.global_position + j.global_basis.y * 0.15
		found = true
	elif _hand_cards.has(uid) and is_instance_valid(_hand_cards[uid]):
		at = (_hand_cards[uid] as Node3D).global_position + Vector3(0, 0.08, 0)
		found = true
	if not found:
		return
	var label := Label3D.new()
	label.text = str(ev.get("text", ""))
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 64
	label.pixel_size = 0.0009
	label.outline_size = 14
	label.modulate = Board.to_color(ev.get("c"))
	label.no_depth_test = true
	label.render_priority = 20
	add_child(label)
	label.global_position = at
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(label, "global_position", at + Vector3(0, 0.07, 0), 0.9).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(label, "scale", Vector3.ONE * 1.3, 0.12).from(Vector3.ONE * 0.3)
	tw.tween_property(label, "modulate:a", 0.0, 0.35).set_delay(0.6)
	tw.chain().tween_callback(label.queue_free)
	_score_feel(ev, uid, at)


# ---------------------------------------------------------------- shattering

## The chip's face bursts into shards (the build-up before it: _defeat_chip).
func _shatter_chip(power := 1.0) -> void:
	var art := _chip_front.get_node_or_null("Art0") as MeshInstance3D
	if art == null or art.material_override == null:
		return
	var xform := _chip_front.global_transform
	ShatterFX.burst(self, xform, [art.material_override], Vector2.ONE * CHIP_RADIUS * 2.0, true, power)


func _shatter_card(ev: Dictionary) -> void:
	var uid := int(ev.get("uid", -1))
	var node: Node3D = null
	var size := TABLE_CARD
	if _play_cards.has(uid) and is_instance_valid(_play_cards[uid]):
		node = _play_cards[uid]
	elif _hand_cards.has(uid) and is_instance_valid(_hand_cards[uid]):
		node = _hand_cards[uid]
		size = Vector2(CARD_SIZE.x, CARD_SIZE.y)
	if node == null:
		return
	var layers := CardArt.card_layers({"f": "front", "ca": ev.get("ca"), "cp": ev.get("cp"), "fa": ev.get("fa"), "fp": ev.get("fp"), "key": "m_glass"})
	ShatterFX.burst(self, node.global_transform, layers, size, false, 0.7)
	node.visible = false
	_buzz_hand(_holder, 0.6, 0.08)


# ---------------------------------------------------------------- booster packs

func _show_pack(ev: Dictionary) -> void:
	if not _vr:
		_send({"cmd": "open_pack"}) # no hands on the desktop: just open it
		return
	if _pack != null and is_instance_valid(_pack):
		_pack.queue_free()
	_pack = PackTear.new()
	_pack.setup(CardArt.material(ev.get("atlas"), ev.get("pos")))
	add_child(_pack)
	var head := _head.global_transform
	var forward := -head.basis.z
	forward.y = 0
	forward = forward.normalized() if forward.length() > 0.01 else Vector3.FORWARD
	var pos := head.origin + forward * 0.42 + Vector3(0, -0.22, 0)
	_pack.global_transform = Transform3D(Basis(Vector3.UP, atan2(-forward.x, -forward.z)), pos)
	_pack.torn.connect(_on_pack_torn)


func _on_pack_torn() -> void:
	_send({"cmd": "open_pack"})
	_buzz_hand(_point, 1.0, 0.15)
	_buzz_hand(_holder, 1.0, 0.15)
	_casino.pulse(0.7)
	_jimbo.react("pack")


# ---------------------------------------------------------------- reroll lever

func _on_lever_pulled() -> void:
	_send({"cmd": "reroll"})
	_buzz_hand(_point, 0.7, 0.1)
	_buzz_hand(_holder, 0.7, 0.1)
	_jimbo.react("reroll")


# ---------------------------------------------------------------- consumables in the rack

## Tarot / planet / spectral cards stand in a little rack on the joker board. Grab one: drop it
## on your card hand to use a tarot or spectral card (on the cards you selected), throw a planet
## up into the sky, or drop any of them into the coin slot to sell it.
func _sync_consumables(list: Array) -> void:
	var alive := {}
	var n := list.size()
	for i in n:
		var c: Dictionary = list[i]
		var uid := int(c.get("uid", -1))
		alive[uid] = true
		var card = _consumables.get(uid)
		if card == null or not is_instance_valid(card):
			card = _make_table_card()
			_joker_table.add_child(card)
			_consumables[uid] = card
			# something for the beam: trigger on a card in the rack uses it
			var body := StaticBody3D.new()
			body.set_meta("target_id", uid)
			body.set_meta("kind", "consumable")
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(TABLE_CARD.x, TABLE_CARD.y, 0.01)
			shape.shape = box
			body.add_child(shape)
			card.add_child(body)
			card.transform = _bag.transform * Transform3D(Basis(), Vector3(0, 0.15, 0)) # drops into the bag
		card.set_meta("set", str(c.get("set", "")))
		card.set_meta("can_use", bool(c.get("can_use", false)))
		card.set_meta("can_sell", bool(c.get("can_sell", false)))
		card.set_meta("slot", Vector2i(i, n)) # its place in the bag (_bag_spot; the bag may be moved)
		_refresh_rack_art(card, uid)
	for uid in _consumables.keys():
		if not alive.has(uid):
			if is_instance_valid(_consumables[uid]):
				_consumables[uid].queue_free()
			_consumables.erase(uid)
			if _held_consumable == uid:
				_held_consumable = -1


func _refresh_rack_art(card: Node3D, uid: int) -> void:
	for it in _last_scene.get("items", []):
		if it.get("k", "") == "c" and int(it.get("id", -1)) == uid:
			CardArt.apply_layers(card.get_node("Face"), CardArt.card_layers(it), TABLE_CARD, 0.0003)
			return


func _try_grab_consumable(hand: XRController3D) -> bool:
	if not _vr or _calibrating or _held_consumable >= 0 or not _joker_table.is_visible_in_tree():
		return false
	var best := -1
	var best_dist := 0.08
	for uid in _consumables:
		var card = _consumables[uid]
		if not is_instance_valid(card) or card.has_meta("gone"):
			continue
		var d: float = (card as Node3D).global_position.distance_to(hand.global_position)
		if d < best_dist:
			best = uid
			best_dist = d
	if best < 0:
		return false
	_held_consumable = best
	_held_consumable_hand = hand
	_held_consumable_offset = hand.global_transform.affine_inverse() * (_consumables[best] as Node3D).global_transform
	_held_prev = hand.global_position
	_held_velocity = Vector3.ZERO
	_buzz_hand(hand, 0.2, 0.03)
	return true


func _drop_consumable() -> void:
	var uid := _held_consumable
	_held_consumable = -1
	var card = _consumables.get(uid)
	if card == null or not is_instance_valid(card):
		return
	var pos: Vector3 = (card as Node3D).global_position
	var kind := str(card.get_meta("set", ""))
	if pos.distance_to(_coin_slot.global_position) < SLOT_RADIUS and card.get_meta("can_sell", false):
		_send({"cmd": "sell", "target": uid})
		_money_from = _coin_slot.global_position
		_money_from_time = Time.get_ticks_msec() / 1000.0
		card.set_meta("gone", 0.0)
		return
	var thrown_up := kind == "Planet" and (pos.y > _eyes().y + 0.05 or _held_velocity.y > 1.2)
	# dropped onto the card hand – only counts from the other hand (the card hand is always there)
	var on_hand := kind != "Planet" and _fan_anchor != null and _held_consumable_hand != _holder \
			and pos.distance_to(_fan_anchor.global_position) < 0.25
	if thrown_up or on_hand:
		_use_consumable(uid, thrown_up)
	# not used: it glides back into the rack (the animation does that)


## Uses a tarot / planet / spectral card from the rack (beam + trigger, dropped on the hand, or a
## planet thrown up). If the game won't take it right now, a hint appears above it instead.
func _use_consumable(uid: int, launch: bool) -> void:
	var card = _consumables.get(uid)
	if card == null or not is_instance_valid(card) or card.has_meta("gone"):
		return
	if not card.get_meta("can_use", false):
		var hint := "Can't be used right now"
		if _last_state_name == "SELECTING_HAND" and str(card.get_meta("set", "")) != "Planet":
			hint = "Select the cards it works on first"
		_rack_hint(card, hint)
		_buzz_hand(_point, 0.2, 0.05)
		return
	_send({"cmd": "use", "target": uid})
	card.set_meta("gone", 0.0)
	card.set_meta("launch", launch or str(card.get_meta("set", "")) == "Planet")
	_buzz_hand(_point, 0.6, 0.08)


func _rack_hint(card: Node3D, text: String) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 40
	label.pixel_size = 0.0008
	label.outline_size = 10
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.render_priority = 20
	label.modulate = Color(1.0, 0.85, 0.5)
	add_child(label)
	label.global_position = card.global_position + Vector3(0, 0.1, 0)
	var tw := create_tween()
	tw.tween_property(label, "global_position", label.global_position + Vector3(0, 0.04, 0), 2.0)
	tw.parallel().tween_property(label, "modulate:a", 0.0, 0.6).set_delay(1.6)
	tw.tween_callback(label.queue_free)


func _animate_table_fun(delta: float) -> void:
	_animate_play_cards(delta)
	if _vr and _held_consumable >= 0 and is_instance_valid(_held_consumable_hand):
		var hp := _held_consumable_hand.global_position
		_held_velocity = _held_velocity.lerp((hp - _held_prev) / maxf(delta, 0.001), 0.3)
		_held_prev = hp
	var k := 1.0 - exp(-8.0 * delta)
	for uid in _consumables.keys():
		var card = _consumables[uid]
		if not is_instance_valid(card):
			continue
		if uid == _held_consumable and _held_consumable_hand != null:
			card.global_transform = _held_consumable_hand.global_transform * _held_consumable_offset
		elif card.has_meta("gone"): # used or sold: up into the sky / down into the slot / fade
			var g: float = float(card.get_meta("gone")) + delta / 0.5
			card.set_meta("gone", g)
			if card.get_meta("launch", false):
				card.global_position += Vector3(0, 2.5, 0) * delta
			elif card.global_position.distance_to(_coin_slot.global_position) < 0.2:
				card.global_position = card.global_position.lerp(_coin_slot.global_position + Vector3(0, 0.05, 0), k)
			card.scale = Vector3.ONE * maxf(1.0 - g, 0.01)
			if g >= 1.5: # the game did not take it (e.g. it can't be used now): back to the rack
				card.remove_meta("gone")
				card.remove_meta("launch")
				card.scale = Vector3.ONE
		else:
			var slot: Vector2i = card.get_meta("slot", Vector2i(0, 1)) # follows the bag, also while it is calibrated
			card.transform = card.transform.interpolate_with(_bag_spot(slot.x, slot.y), k)
	_animate_selling_jokers(delta)
	_update_touch(delta)
	if _jimbo.visible: # he sits on the table surface, wherever the table was calibrated to
		_jimbo.global_position.y = _joker_table.global_position.y
	_play_stand.global_position.y = _joker_table.global_position.y # same for the played-cards stand


# ---------------------------------------------------------------- coin slot for jokers

## A joker let go right above the coin slot is sold (with a little "into the slot" animation).
func _sell_dropped_joker(inst: Node3D, uid: int) -> bool:
	if inst.global_position.distance_to(_coin_slot.global_position) > SLOT_RADIUS:
		return false
	_send({"cmd": "sell", "target": uid})
	inst.set_meta("selling", 0.0)
	_money_from = _coin_slot.global_position
	_money_from_time = Time.get_ticks_msec() / 1000.0
	_buzz_hand(_point, 0.6, 0.08)
	return true


func _animate_selling_jokers(delta: float) -> void:
	for uid in _jokers:
		var inst = _jokers[uid]
		if not is_instance_valid(inst) or not inst.has_meta("selling"):
			continue
		var s: float = float(inst.get_meta("selling")) + delta / 0.45
		inst.set_meta("selling", s)
		inst.global_position = inst.global_position.lerp(_coin_slot.global_position + Vector3(0, 0.05, 0), 0.25)
		inst.scale = Vector3.ONE * maxf(1.0 - s, 0.01)
		if s > 3.0: # still there after a while: the game refused (e.g. Eternal) – it comes back
			inst.remove_meta("selling")
			inst.scale = Vector3.ONE


# ---------------------------------------------------------------- touching jokers

## Touch a 3D joker with either hand: its tooltip appears right above it, turned to you.
func _update_touch(delta: float) -> void:
	if not _vr or _calibrating:
		return
	var found := -1
	for hand in [_point, _holder]:
		# (a hand that holds a joker or a card right now doesn't touch)
		if hand == null or (hand == _held_hand and _held_joker >= 0) or (hand == _held_consumable_hand and _held_consumable >= 0):
			continue
		var hp: Vector3 = (hand as Node3D).global_position
		for uid in _jokers:
			var inst = _jokers[uid]
			if not is_instance_valid(inst) or inst.has_meta("held"):
				continue
			# anywhere on the joker: within reach sideways, from the pedestal up to the top of the model
			var base: Vector3 = (inst as Node3D).global_position
			var up := hp.y - base.y
			if Vector2(hp.x - base.x, hp.z - base.z).length() < TOUCH_RADIUS and up > -0.03 and up < 0.28:
				found = uid
		for uid in _consumables: # the tarot / planet cards in the rack too
			var card = _consumables[uid]
			if not is_instance_valid(card) or uid == _held_consumable or card.has_meta("gone"):
				continue
			if (card as Node3D).global_position.distance_to((hand as Node3D).global_position) < TOUCH_RADIUS * 0.8:
				found = uid
	if found >= 0:
		_touch_left = 0.0
		if found != _touch_uid:
			if _touch_uid >= 0:
				_send({"cmd": "unhover", "target": _touch_uid})
			_touch_uid = found
			_send({"cmd": "hover", "target": found})
			_buzz_hand(_point, 0.15, 0.02)
	elif _touch_uid >= 0:
		_touch_left += delta
		if _touch_left > 1.2: # the tooltip stays a moment after letting go
			_send({"cmd": "unhover", "target": _touch_uid})
			_touch_uid = -1
	var touched = _touched_node()
	if touched != null:
		var anchor := _joker_tip_anchor(touched)
		var to := _eyes() - anchor.global_position
		anchor.global_basis = Basis(Vector3.UP, atan2(to.x, to.z)).scaled(Vector3.ONE * TOOLTIP_SCALE)


## The touched 3D joker or rack card, or null.
func _touched_node():
	for list in [_jokers, _consumables]:
		if list.has(_touch_uid) and is_instance_valid(list[_touch_uid]):
			return list[_touch_uid]
	return null


func _joker_tip_anchor(inst: Node3D) -> Node3D:
	var anchor := inst.get_node_or_null("TipAnchor") as Node3D
	if anchor == null:
		anchor = Node3D.new()
		anchor.name = "TipAnchor"
		inst.add_child(anchor)
	# above a joker model; a rack card is lower, its tooltip right above it
	anchor.global_position = inst.global_position + Vector3(0, 0.24 if _jokers.has(_touch_uid) else 0.16, 0)
	return anchor


# ---------------------------------------------------------------- grips

## A grip goes to the first thing within reach: the booster pack, the reroll lever, a consumable,
## a joker. False if nothing was there (then the pointing hand may grab its cards).
func _grip_table(hand: XRController3D) -> bool:
	if _pack != null and is_instance_valid(_pack) and not _pack.is_ripped() and _pack.grab(hand):
		_buzz_hand(hand, 0.3, 0.04)
		return true
	if _lever.is_visible_in_tree() and _lever.try_grab(hand):
		_buzz_hand(hand, 0.2, 0.03)
		return true
	if _try_grab_consumable(hand):
		return true
	return _try_grab_joker(hand)


func _release_table(hand: XRController3D) -> void:
	if _pack != null and is_instance_valid(_pack):
		_pack.release(hand)
	_lever.release(hand)
	if _held_consumable >= 0 and _held_consumable_hand == hand:
		_drop_consumable()
	if _held_joker >= 0 and _held_hand == hand:
		_drop_joker()


# ================================================================ game feel
# Cards fly from the deck into the hand and on to the discard pile, bought cards fly from the shop
# to their place, the last hand holds its breath, joker triggers are linked to the cards that set
# them off, vibrations follow the score, a boss presents itself – and a beaten blind's chip cracks
# and bursts.

var _hand_item_by_id := {}       # hand card id -> its last scene item (art for the discard flight)
var _hand_removed: Array = []    # hand cards that left the hand in the last scene
var _released := {}              # hand card id -> time it was let go to be played / discarded
var _flights: Array = []         # cards flying somewhere, see _fly()
var _tension := false
var _calm := false               # Calm Lights: no flashes, flicker or pulsing (photosensitive players)
var _hands_on := true            # Jimbo's gloves shown
var _ambience_on := true         # the casino's own sounds (slot machines, glasses, chips)
var _gloves: Array = []          # the two JimboHands (VR only)
var _spectator: Spectator        # the spectator camera window (VR only)
var _tutorial: VRTutorial        # Jimbo's tips
var _wrist: WristMenu            # the VR settings above the card hand (menu button)
var _standing := false           # standing mode: its own layout
var _beat_time := 0.0
var _last_chips := -1.0
var _last_card_pop := {"t": -10.0, "pos": Vector3.ZERO}
var _joker_order: Array = []     # joker uids in the game's slot order (Blueprint, Brainstorm)
var _boss_seen := ""
var _boss_key := ""              # the boss blind being played ("" if none)
var _intro_scale := 2.4          # how big the boss chip comes up to you (final bosses: bigger)
var _boss_intro_t := -1.0
var _boss_label: Label3D
var _boss_light: OmniLight3D
var _chip_home := Transform3D()
var _chip_defeat_t := -1.0
var _chip_defeat_boss := false
var _chip_burst := false
var _number := RegEx.create_from_string("[0-9]+(\\.[0-9]+)?")


func _animate_game_feel(delta: float) -> void:
	_return_refused_cards()
	# The Ox (takes your money for your most played hand): the coin pile trembles nervously
	_coins.tremble = _boss_key == "bl_ox" and not _calm
	# the room's sounds follow the game's sound volume and go quiet in the last hand
	_casino.ambience.volume = clampf(_sounds.last_volume / 0.15, 0.0, 1.5)
	_casino.ambience.hush = move_toward(_casino.ambience.hush, 1.0 if _tension else 0.0, delta * 0.7)
	if _backdrop == Backdrop.ROOM: # the last hand: the room's own light and the haze go dark too
		var a := _casino.tension_amount()
		_env.ambient_light_color = Color(0.2, 0.17, 0.26).lerp(Color(0.02, 0.015, 0.03), a)
		_env.glow_intensity = 0.55 if _calm else 0.8 # Calm Lights: softer bloom halos
		_env.fog_light_color = Color(0.2, 0.13, 0.26).lerp(Color(0.015, 0.01, 0.02), a)
	_animate_hand_draw(delta)
	_animate_flights(delta)
	_animate_boss_intro(delta)
	_animate_chip_defeat(delta)
	if _tension: # heartbeat in both hands: lub - dub ... lub - dub
		var prev := _beat_time
		_beat_time = fmod(_beat_time + delta, 0.95)
		if _beat_time < prev:
			_buzz_hand(_point, 0.45, 0.06)
			_buzz_hand(_holder, 0.45, 0.06)
		elif prev < 0.2 and _beat_time >= 0.2:
			_buzz_hand(_point, 0.28, 0.05)
			_buzz_hand(_holder, 0.28, 0.05)


# ---------------------------------------------------------------- the deck, the hand, the discard pile

## Cards let go to be played / discarded that are still in the hand after a while: the game
## didn't take them – back into the card hand.
func _return_refused_cards() -> void:
	if _released.is_empty():
		return
	var now := Time.get_ticks_msec() / 1000.0
	var back := false
	for id in _released.keys():
		if now - float(_released[id]) < 2.5: # (the game may still be busy with an animation)
			continue
		_released.erase(id)
		if _hand_cards.has(id) and is_instance_valid(_hand_cards[id]) and _fan_anchor != null:
			_hand_cards[id].reparent(_fan_anchor, true)
			back = true
	if back:
		_rebuild_hand(_hand_items)


## The top of the 3D draw pile, a card lying on it face down.
func _deck_pose() -> Transform3D:
	var b := _deck.global_basis.orthonormalized()
	var top := _deck.global_position + b.y * (_deck_target_height + 0.01)
	return Transform3D(b * Basis(Vector3.RIGHT, deg_to_rad(90.0)), top)


## A spot beside the draw pile (towards the middle of the board), a card lying on it face up.
func _discard_pose() -> Transform3D:
	var b := _joker_table.global_basis.orthonormalized()
	var inward := -signf(_deck.position.x) if absf(_deck.position.x) > 0.01 else -1.0
	var p := _deck.global_position + b.x * inward * 0.11 + b.y * 0.006
	return Transform3D(b * Basis(Vector3.RIGHT, deg_to_rad(-90.0)) * Basis(Vector3.BACK, randf_range(-0.4, 0.4)), p)


## New hand cards come flying from the draw pile, one after the other, flipping over on the way.
func _animate_hand_draw(delta: float) -> void:
	if not _vr:
		return
	for id in _hand_cards:
		var body = _hand_cards[id]
		if not is_instance_valid(body) or not body.has_meta("fly_t"):
			continue
		var t: float = float(body.get_meta("fly_t")) + delta / 0.38
		body.set_meta("fly_t", t)
		if t < 0.0: # still waiting for its turn
			body.visible = false
			continue
		body.visible = true
		var home: Transform3D = body.get_meta("home", body.transform)
		if t >= 1.0:
			body.remove_meta("fly_t")
			body.transform = home
			_buzz_hand(_holder, 0.12, 0.02) # a little tick as it lands in the hand
			continue
		var to: Transform3D = (body.get_parent() as Node3D).global_transform * home
		var e := 1.0 - pow(1.0 - t, 3.0)
		var xf := _deck_pose().interpolate_with(to, e)
		xf.origin.y += sin(t * PI) * 0.1
		body.global_transform = xf


## Hand cards that left the hand without being played: discarded – they fly to the discard pile.
## At the end of a round the hand goes back into the deck instead.
func _fly_discards(items: Array) -> void:
	if _hand_removed.is_empty():
		return
	var played := {}
	for it in items:
		if it.get("k", "") == "c" and it.get("area", "") == "play":
			played[int(it.get("id", -1))] = true
	var to_deck := not ROUND_STATES.has(_last_state_name)
	var n := 0
	for id in _hand_removed:
		if played.has(id) or not _hand_last.has(id) or not _hand_item_by_id.has(id):
			continue
		var card := _make_table_card()
		add_child(card)
		CardArt.apply_layers(card.get_node("Face"), CardArt.card_layers(_hand_item_by_id[id]), TABLE_CARD, 0.0003)
		var pose := _deck_pose() if to_deck else _discard_pose()
		_fly(card, _hand_last[id], func(): return pose, 0.4 + n * 0.05, CARD_SIZE.x / TABLE_CARD.x, 1.0, Callable(), true, 0.1)
		n += 1
	_hand_removed.clear()
	if _hand_item_by_id.size() > 80:
		_hand_item_by_id.clear()


## Lets `node` fly from `from` to where `to` says (a Callable returning a Transform3D, or null while
## the place doesn't exist yet – then it waits, at most 1.5 s), in `seconds`, on a little arc.
## Its size goes from s0 to s1 (relative), `arrive` is called on landing, `vanish` shrinks it away
## afterwards (otherwise it is removed right away). `hide` (optional) returns the node the card
## turns into, which stays invisible until the card lands on it.
func _fly(node: Node3D, from: Transform3D, to: Callable, seconds: float, s0: float, s1: float,
		arrive: Callable, vanish: bool, arc: float, hide: Callable = Callable()) -> void:
	if node.get_parent() != self:
		if node.get_parent() != null:
			node.reparent(self)
		else:
			add_child(node)
	node.global_transform = from.scaled_local(Vector3.ONE * s0)
	_flights.append({"node": node, "from": from, "to": to, "t": 0.0, "dur": seconds, "s0": s0, "s1": s1,
		"arrive": arrive, "vanish": vanish, "arc": arc, "wait": 0.0, "done": false, "v": 0.0, "hide": hide})


func _animate_flights(delta: float) -> void:
	for f in _flights.duplicate():
		var node = f["node"]
		if not is_instance_valid(node):
			_flights.erase(f)
			continue
		if (f["hide"] as Callable).is_valid() and not f["done"]:
			var target = (f["hide"] as Callable).call()
			if target != null and is_instance_valid(target):
				target.visible = false
		if f["done"]:
			if f["vanish"]:
				f["v"] = float(f["v"]) + delta / 0.3
				node.scale = node.scale.lerp(Vector3.ONE * 0.01, minf(float(f["v"]), 1.0))
				if float(f["v"]) >= 1.0:
					node.queue_free()
					_flights.erase(f)
			continue
		var to = (f["to"] as Callable).call()
		if to == null:
			f["wait"] = float(f["wait"]) + delta
			if float(f["wait"]) > 1.5:
				node.queue_free()
				_flights.erase(f)
			continue
		f["t"] = float(f["t"]) + delta / float(f["dur"])
		var t := minf(float(f["t"]), 1.0)
		var e := t * t * (3.0 - 2.0 * t)
		var xf: Transform3D = (f["from"] as Transform3D).interpolate_with(to, e)
		xf.origin.y += sin(t * PI) * float(f["arc"])
		node.global_transform = xf.scaled_local(Vector3.ONE * lerpf(float(f["s0"]), float(f["s1"]), e))
		if t >= 1.0:
			f["done"] = true
			if (f["arrive"] as Callable).is_valid():
				(f["arrive"] as Callable).call()
			if not f["vanish"]:
				node.queue_free()
				_flights.erase(f)


# ---------------------------------------------------------------- bought cards fly to their place

## Bought in the shop: the card lifts off the shop and flies to where it belongs – a joker to its
## place on the joker board (where it then pops up as its 3D model), a tarot / planet / spectral
## card into the bag, a playing card onto the deck, a voucher up and away.
func _fly_purchase(ev: Dictionary) -> void:
	var uid := int(ev.get("uid", -1))
	var kind := str(ev.get("set", ""))
	if uid < 0 or kind == "Booster": # packs: they float up to be torn open (pack_ready)
		return
	var v = _board._visuals.get(uid)
	if v == null or not is_instance_valid(v):
		return
	var item := {}
	for it in _last_scene.get("items", []):
		if int(it.get("id", -1)) == uid:
			item = it
			break
	if item.is_empty():
		return
	var card := _make_table_card()
	add_child(card)
	CardArt.apply_layers(card.get_node("Face"), CardArt.card_layers(item), TABLE_CARD, 0.0003)
	var from := Transform3D((v as Node3D).global_basis.orthonormalized(), (v as Node3D).global_position)
	var s0 := float(item.get("w", 1.4)) * Board.SCALE / TABLE_CARD.x
	var to: Callable
	var hide := Callable()
	var arrive := Callable()
	var stays := false # lands on the real thing (which pops up) instead of shrinking away
	match kind:
		"Joker":
			stays = true
			to = func():
				var j = _jokers.get(uid)
				if j == null or not is_instance_valid(j):
					return null
				return Transform3D((j as Node3D).global_basis.orthonormalized(), (j as Node3D).global_position + (j as Node3D).global_basis.y * 0.07)
			hide = func(): return _jokers.get(uid)
			arrive = func():
				var j = _jokers.get(uid)
				if j != null and is_instance_valid(j):
					j.visible = true
					j.set_meta("bump", 1.0) # pops up out of the card
				_buzz_hand(_point, 0.5, 0.08)
				_casino.pulse(0.4)
		"Tarot", "Planet", "Spectral":
			stays = true
			to = func():
				var c = _consumables.get(uid)
				return (c as Node3D).global_transform if c != null and is_instance_valid(c) else null
			hide = func(): return _consumables.get(uid)
			arrive = func():
				var c = _consumables.get(uid)
				if c != null and is_instance_valid(c):
					c.visible = true
				_buzz_hand(_point, 0.3, 0.05)
		"Voucher":
			var up := Transform3D(from.basis, from.origin + Vector3(0, 0.5, 0))
			to = func(): return up
		_: # a playing card: onto the deck
			to = func(): return _deck_pose() if _deck.is_visible_in_tree() else null
	_fly(card, from, to, 0.6, s0, 1.0, arrive, not stays, 0.15, hide)


# ---------------------------------------------------------------- the last hand

## The last hand of a round that isn't won yet: the neon sinks to a glimmer, a heartbeat throbs
## in both hands. When the score goes past the blind the room lights up again with a bang.
func _update_tension(state: Dictionary, in_run: bool, name: String) -> void:
	var round_info: Dictionary = state.get("round", {})
	var chips := float(round_info.get("chips", 0))
	var blind: Dictionary = state.get("blind", {})
	var need := float(blind.get("chips", 0))
	var hands_left := int(round_info.get("hands_left", 0))
	var tense := in_run and ROUND_STATES.has(name) and need > 0.0 and chips < need and hands_left <= 1
	if tense != _tension:
		_tension = tense
		_casino.set_tension(tense)
		_beat_time = 0.0
	# the score just went past the blind: a big rumble and a flash
	if in_run and ROUND_STATES.has(name) and need > 0.0 and _last_chips >= 0.0 and _last_chips < need and chips >= need:
		_buzz_hand(_point, 1.0, 0.35)
		_buzz_hand(_holder, 1.0, 0.35)
		_casino.pulse(2.5)
		_jimbo.react("cheer")
	_last_chips = chips if in_run else -1.0
	# a boss blind steps up once per blind, when its round starts
	if not in_run:
		_boss_seen = ""
	elif name == "SELECTING_HAND" and bool(blind.get("boss", false)):
		var key := "%d %s" % [int(round_info.get("ante", 0)), str(blind.get("name", ""))]
		if key != _boss_seen:
			_boss_seen = key
			_start_boss_intro(blind)


# ---------------------------------------------------------------- scoring: joker links, vibration

## Every scoring pop: a vibration that grows with the number, and when a joker fires, a short
## beam from the card that set it off (or from the played cards) to the joker. Blueprint and
## Brainstorm also show which joker they copy.
func _score_feel(ev: Dictionary, uid: int, at: Vector3) -> void:
	var kind := str(ev.get("kind", ""))
	var text := str(ev.get("text", ""))
	var value := 0.0
	var m := _number.search(text)
	if m != null:
		value = m.get_string().to_float()
	var colour := Board.to_color(ev.get("c"))
	var amp := 0.2
	match kind:
		"chips": amp = 0.12 + clampf(log(maxf(value, 1.0)) / log(10.0) / 6.0, 0.0, 0.35)
		"mult": amp = 0.18 + clampf(value / 40.0, 0.0, 0.32)
		"x_mult": amp = 0.45 + clampf((value - 1.0) / 4.0, 0.0, 0.5)
		"dollars": amp = 0.25
	var now := Time.get_ticks_msec() / 1000.0
	if kind == "debuff": # a boss blind switched the card off: a twitch in the card hand
		_buzz_hand(_holder, 0.7, 0.03)
		get_tree().create_timer(0.09).timeout.connect(func(): _buzz_hand(_holder, 0.7, 0.03))
		return
	_buzz_hand(_point, amp, 0.035)
	_casino.pulse(0.8 if kind == "x_mult" else 0.3)
	if _play_cards.has(uid) or _hand_cards.has(uid):
		_last_card_pop = {"t": now, "pos": at - Vector3(0, 0.06, 0)}
	elif _jokers.has(uid) and is_instance_valid(_jokers[uid]):
		var j: Node3D = _jokers[uid]
		var joker_at := j.global_position + j.global_basis.y * 0.08
		if now - float(_last_card_pop["t"]) < 0.8:
			_zap(_last_card_pop["pos"], joker_at, colour)
		elif not _play_cards.is_empty():
			_zap(_play_stand.global_transform * _play_surface().origin, joker_at, colour)
		var key := str(j.get_meta("key", ""))
		var i := _joker_order.find(uid)
		var copied := -1
		if key == "j_blueprint" and i >= 0 and i + 1 < _joker_order.size():
			copied = int(_joker_order[i + 1])
		elif key == "j_brainstorm" and not _joker_order.is_empty() and int(_joker_order[0]) != uid:
			copied = int(_joker_order[0])
		if copied >= 0 and _jokers.has(copied) and is_instance_valid(_jokers[copied]):
			var c: Node3D = _jokers[copied]
			_zap(joker_at, c.global_position + c.global_basis.y * 0.08, Color(0.45, 0.7, 1.0))
			c.set_meta("bump", 0.7)


## A short beam of light from a to b (fades in about 0.4 s), with a spark at both ends.
func _zap(a: Vector3, b: Vector3, colour: Color) -> void:
	if _calm:
		return # Calm Lights: no flashing beams
	var d := b - a
	var length := d.length()
	if length < 0.01:
		return
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(colour.r * 1.6, colour.g * 1.6, colour.b * 1.6, 1.0)
	var beam := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.0035
	cyl.bottom_radius = 0.0035
	cyl.height = 1.0
	cyl.radial_segments = 6
	cyl.rings = 1
	beam.mesh = cyl
	beam.material_override = mat
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)
	var y := d / length
	var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	beam.global_transform = Transform3D(Basis(x, y * length, z), (a + b) * 0.5)
	for p in [a, b]:
		var spark := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 0.008
		s.height = 0.016
		spark.mesh = s
		spark.material_override = mat
		add_child(spark)
		spark.global_position = p
		get_tree().create_timer(0.5).timeout.connect(spark.queue_free)
	var tw := create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.4).set_delay(0.08)
	tw.tween_callback(beam.queue_free)


# ---------------------------------------------------------------- the boss blind

## A boss blind steps up: its chip flies right in front of you, big and turning, in red light,
## with its name and rule – then goes back to its place.
func _start_boss_intro(blind: Dictionary) -> void:
	if _calibrating or _boss_intro_t >= 0.0 or not _chip.is_visible_in_tree():
		return
	if _boss_label == null:
		_boss_label = Label3D.new()
		_boss_label.font_size = 48
		_boss_label.pixel_size = 0.0008
		_boss_label.outline_size = 12
		_boss_label.outline_modulate = Color(0.25, 0.0, 0.0)
		_boss_label.modulate = Color(1.0, 0.85, 0.8)
		_boss_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_boss_label.no_depth_test = true
		_boss_label.render_priority = 20
		_boss_label.width = 600
		_boss_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(_boss_label)
		_boss_light = OmniLight3D.new()
		_boss_light.light_color = Color(1.0, 0.15, 0.1)
		_boss_light.omni_range = 2.5
		add_child(_boss_light)
	GameFont.apply_to(_boss_label)
	var desc := str(blind.get("desc", ""))
	_boss_label.text = str(blind.get("name", "Boss")).to_upper() + ("\n" + desc if desc != "" else "")
	# a final boss (Ante 8) makes a bigger entrance
	var final := str(blind.get("key", "")).begins_with("bl_final")
	_intro_scale = 3.4 if final else 2.4
	if final:
		_casino.pulse(3.0)
		_buzz_hand(_point, 1.0, 0.6)
		_buzz_hand(_holder, 1.0, 0.6)
	_chip_home = _chip.transform
	_boss_intro_t = 0.0
	_buzz_hand(_point, 0.6, 0.4)
	_buzz_hand(_holder, 0.6, 0.4)
	_casino.pulse(1.5)


func _animate_boss_intro(delta: float) -> void:
	if _boss_intro_t < 0.0:
		return
	if _calibrating or _chip_defeat_t >= 0.0:
		_end_boss_intro()
		return
	_boss_intro_t += delta
	var t := _boss_intro_t
	var home := (_chip.get_parent() as Node3D).global_transform * _chip_home
	var eyes := _eyes()
	var fwd := -(_head.global_basis.z if _vr else _camera.global_basis.z)
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var at := eyes + fwd * 0.55 + Vector3(0, -0.06, 0)
	var show := Transform3D(Basis(Vector3.UP, atan2(-fwd.x, -fwd.z) + 0.15 * sin(t * 2.0)).scaled(Vector3.ONE * _intro_scale), at)
	var e := 0.0
	if t < 0.6:
		e = 1.0 - pow(1.0 - t / 0.6, 3.0)
	elif t < 2.9:
		e = 1.0
	elif t < 3.5:
		e = 1.0 - (t - 2.9) / 0.6
		e = e * e * (3.0 - 2.0 * e)
	else:
		_end_boss_intro()
		return
	_chip.global_transform = home.interpolate_with(show, e)
	_boss_light.global_position = _chip.global_position - fwd * 0.15 + Vector3(0, 0.1, 0)
	_boss_light.light_energy = 3.0 * e * (0.6 if _calm else 0.8 + 0.2 * sin(t * 9.0)) # calm: steady, softer
	_boss_label.visible = e > 0.6
	_boss_label.modulate.a = clampf((e - 0.6) / 0.4, 0.0, 1.0)
	_boss_label.global_position = at + Vector3(0, 0.17, 0)


func _end_boss_intro() -> void:
	_boss_intro_t = -1.0
	_chip.transform = _chip_home
	if _boss_label != null:
		_boss_label.visible = false
		_boss_light.light_energy = 0.0


## The blind is beaten: the chip trembles and glows (a boss longer and harder), then bursts into
## shards with a flash of light and a shock wave; a beaten boss also gets a "DEFEATED!".
func _defeat_chip(boss: bool) -> void:
	if _boss_intro_t >= 0.0:
		_end_boss_intro()
	_chip_defeat_t = 0.0
	_chip_defeat_boss = boss
	_chip_burst = false
	_chip.visible = true


func _animate_chip_defeat(delta: float) -> void:
	if _chip_defeat_t < 0.0:
		return
	_chip_defeat_t += delta
	var crack := 0.75 if _chip_defeat_boss else 0.45
	if _chip_defeat_t < crack: # the build-up: shaking harder and harder, the hands buzz along
		var k := _chip_defeat_t / crack
		_chip_spinner.position += Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), 0.0) * 0.007 * k
		_chip_spinner.scale = Vector3.ONE * (1.0 + 0.15 * k)
		_buzz_hand(_point, 0.15 + 0.45 * k, 0.02)
		_buzz_hand(_holder, 0.15 + 0.45 * k, 0.02)
		return
	if not _chip_burst:
		_chip_burst = true
		var power := 2.6 if _chip_defeat_boss else 1.5
		var at := _chip_front.global_position
		_shatter_chip(power)
		_chip_spinner.visible = false
		_chip_spinner.scale = Vector3.ONE
		var colour := Color(1.0, 0.35, 0.2) if _chip_defeat_boss else Color(1.0, 0.8, 0.4)
		if not _calm: # Calm Lights: shards and the text, but no flash or shock wave
			_shock_ring(at, colour, 2.2 if _chip_defeat_boss else 1.2, 0.0)
			if _chip_defeat_boss:
				_shock_ring(at, Color(1.0, 0.85, 0.4), 1.6, 0.12)
		if _chip_defeat_boss:
			_pop_text(at + Vector3(0, 0.12, 0), "DEFEATED!", Color(1.0, 0.75, 0.3))
		if not _calm:
			var flash := OmniLight3D.new()
			flash.light_color = colour
			flash.omni_range = 4.0 if _chip_defeat_boss else 2.5
			flash.light_energy = 8.0 if _chip_defeat_boss else 4.0
			add_child(flash)
			flash.global_position = at
			var tw := create_tween()
			tw.tween_property(flash, "light_energy", 0.0, 0.6)
			tw.tween_callback(flash.queue_free)
		var hold := 0.6 if _chip_defeat_boss else 0.25
		_buzz_hand(_point, 1.0, hold)
		_buzz_hand(_holder, 1.0, hold)
		_casino.pulse(3.0 if _chip_defeat_boss else 1.5)
		_jimbo.react("win" if _chip_defeat_boss else "won_blind")
	if _chip_defeat_t > crack + 1.0:
		_chip_defeat_t = -1.0
		_chip_spinner.visible = true
		_chip.visible = _calibrating or (not _state.is_empty() and ROUND_STATES.has(str(_state.get("state_name", ""))))


## An expanding ring of light that faces you and fades: the shock wave of a burst.
func _shock_ring(at: Vector3, colour: Color, size: float, delay: float) -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.92
	torus.outer_radius = 1.0
	torus.rings = 48
	torus.ring_segments = 6
	ring.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(colour.r * 2.0, colour.g * 2.0, colour.b * 2.0, 0.0)
	ring.material_override = mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	var y := (_eyes() - at).normalized() # the ring's axis points at you
	var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
	ring.global_transform = Transform3D(Basis(x, y, x.cross(y)), at)
	ring.scale = Vector3(0.03, 0.03, 0.03)
	var tw := create_tween()
	tw.tween_interval(delay)
	tw.tween_property(mat, "albedo_color:a", 1.0, 0.02)
	tw.tween_property(ring, "scale", Vector3(size, 0.03, size), 0.55).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.5).set_delay(0.05)
	tw.tween_callback(ring.queue_free)


## Big text that pops up and floats away (e.g. "DEFEATED!").
func _pop_text(at: Vector3, text: String, colour: Color) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 96
	label.pixel_size = 0.0012
	label.outline_size = 18
	label.outline_modulate = Color(0.2, 0.05, 0.0)
	label.modulate = colour
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.render_priority = 21
	GameFont.apply_to(label)
	add_child(label)
	label.global_position = at
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(label, "scale", Vector3.ONE * 1.2, 0.18).from(Vector3.ONE * 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(label, "global_position", at + Vector3(0, 0.12, 0), 1.6)
	tw.tween_property(label, "modulate:a", 0.0, 0.5).set_delay(1.1)
	tw.chain().tween_callback(label.queue_free)


# ---------------------------------------------------------------- the end of a run (casino only)

var _end_t := -1.0               # seconds since the run ended (-1: no end scene running)
var _end_won := false
var _end_spot: SpotLight3D
var _chip_rain: CPUParticles3D

const END_DARK := 7.0            # how long the room stays dark after a game over


## Won: casino chips rain from the ceiling over the table and every slot machine hits the jackpot.
## Lost: the lights go out, a single spotlight falls on Jimbo, the room goes quiet - then slowly
## everything comes back.
func _run_end_scene(won: bool) -> void:
	if _backdrop != Backdrop.ROOM:
		return # passthrough / green: the confetti says it
	_end_t = 0.0
	_end_won = won
	if won:
		_start_chip_rain()
		_casino.jackpot()
	else:
		if _end_spot == null:
			_end_spot = SpotLight3D.new()
			_end_spot.light_color = Color(1.0, 0.92, 0.8)
			_end_spot.spot_angle = 14.0
			_end_spot.spot_range = 3.5
			_end_spot.shadow_enabled = true
			add_child(_end_spot)
		_end_spot.light_energy = 0.0


func _animate_run_end(delta: float) -> void:
	if _end_t < 0.0:
		return
	_end_t += delta
	if _end_won:
		if _chip_rain != null and _end_t > 4.0:
			_chip_rain.emitting = false
		if _end_t > 7.0:
			_end_t = -1.0
		return
	# game over: dark room, spotlight on Jimbo
	var dark := _end_t < END_DARK
	_casino.set_tension(dark or _tension)
	_casino.ambience.hush = maxf(_casino.ambience.hush, 1.0 if dark else 0.0)
	if _end_spot != null:
		var target := _jimbo.global_position
		_end_spot.global_transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), target + Vector3(0, 2.2, 0))
		var e := clampf(_end_t / 1.2, 0.0, 1.0) * clampf((END_DARK + 1.5 - _end_t) / 1.5, 0.0, 1.0)
		_end_spot.light_energy = 9.0 * e
		_end_spot.visible = _jimbo.visible and e > 0.0
	if _end_t > END_DARK + 1.5:
		_end_t = -1.0
		_casino.set_tension(_tension)


## Colourful casino chips falling from the ceiling over the card table for a few seconds.
func _start_chip_rain() -> void:
	if _chip_rain == null:
		_chip_rain = CPUParticles3D.new()
		var chip := CylinderMesh.new()
		chip.top_radius = 0.028
		chip.bottom_radius = 0.028
		chip.height = 0.008
		chip.radial_segments = 12
		chip.rings = 1
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.roughness = 0.45
		chip.material = m
		_chip_rain.mesh = chip
		_chip_rain.amount = 420
		_chip_rain.lifetime = 1.15 # long enough to fall from the ceiling to the floor
		_chip_rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		_chip_rain.emission_box_extents = Vector3(1.4, 0.05, 1.0)
		_chip_rain.direction = Vector3(0, -1, 0)
		_chip_rain.spread = 15.0
		_chip_rain.initial_velocity_min = 0.3
		_chip_rain.initial_velocity_max = 1.2
		_chip_rain.gravity = Vector3(0, -5.5, 0)
		_chip_rain.angular_velocity_min = -400.0
		_chip_rain.angular_velocity_max = 400.0
		_chip_rain.particle_flag_rotate_y = true
		var colours := Gradient.new()
		colours.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
		colours.offsets = PackedFloat32Array([0.0, 0.2, 0.4, 0.6, 0.8])
		colours.colors = PackedColorArray([Color(0.9, 0.15, 0.15), Color(0.15, 0.35, 0.9), Color(0.95, 0.95, 0.92),
				Color(0.15, 0.65, 0.3), Color(0.95, 0.75, 0.2)])
		_chip_rain.color_initial_ramp = colours
		_chip_rain.emitting = false
		add_child(_chip_rain)
	var centre: Vector3 = _layout.to_global(PLAY_ROW)
	_chip_rain.global_position = Vector3(centre.x, 3.2, centre.z - 0.2)
	_chip_rain.restart()
	_chip_rain.emitting = true
