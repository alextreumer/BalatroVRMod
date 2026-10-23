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
const SHOP_POS := Vector3(0, TABLE_Y + 0.2, 0.06) # the shop's panel (Next Round ...) stands behind the sales counter
const SHOP_TILT := -30.0                         # leaning back (-90 would lie flat on the table)
const SHOP_SIGN_SIZE := Vector2(0.264, 0.132)  # the game's 4.4 x 2.2 sign at board scale
const SHOP_SIGN_DISTANCE := 0.26                # behind the shop's far edge (meters)
const SHOP_SIGN_HEIGHT := 0.07                  # lifted above the table
const SHOP_SIGN_TILT := 60.0                    # leaning back, facing the player
const SHOP_SIGN_FPS := 8.0
const CHIP_POS := Vector3(0.0, -0.3, 0.68)     # floating right in front of you, over the front of the joker board (play gesture)
const CHIP_SIZE := 0.8                          # (a little smaller than it was)
const SCORE_POS := Vector3(-0.42, TABLE_Y + JOKER_TABLE_TOP, 0.35)  # the score tower stands left of the play stand (on the surface)

# Joker board: a flat mat for the real table; the jokers (on pedestals) and the draw pile live on it
const JOKER_TABLE_POS := Vector3(0.0, TABLE_Y, 0.55) # right in front of you, within reach
const JOKER_TABLE_SIZE := Vector2(1.225, 0.65)  # width x depth (meters): jokers in the middle, coin slot at an end
const JOKER_TABLE_CENTER_Z := -0.1               # the mat reaches further back than to the front (front edge stays close to you)
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
const SPIN_DOCTOR_SPEED := 20.0  # rad/s (about 3 turns a second): a really hard swipe of the wheel
const TEST_TOOLS := false         # joker gallery + boss preview in the VR menu (true while developing)
const WHEEL_MODES := ["Off", "Deterministic", "Real"]
const TOWER_AFTER_STATES := ["NEW_ROUND", "ROUND_EVAL", "GAME_OVER"] # the score tower stays until the shop
const SOLATRO_PASS := ["vr_flags", "need_atlas", "slider", "menu"] # still for the game while Solatro runs
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

enum Backdrop { GREEN, DARK, ROOM } # DARK: a calm near-black backdrop for viewers (no chroma key)

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
var _hand_preview: Label3D    # under the fan: the poker hand of the selected cards ("Flush  Lvl.3")
var _hand_preview_score: Label3D # ... and its chips x mult
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
const STAR_JOKERS := ["j_supernova", "j_satellite", "j_constellation"] # the room twinkles when you get one
const STAR_SHOWER_SECONDS := 30.0
var _star_jokers_seen := {}      # uid -> true: star jokers of this run already greeted with a shower
var _star_jokers_ready := false  # false until the run's first state (jokers you already had stay quiet)
var _star_shower_until := 0.0
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
var _joker_shuffle_t := -1.0           # face-down jokers being shuffled (The Amber Acorn): time since it began
const JOKER_SHUFFLE_TIME := 1.2
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
var _hover_body = null         # the StaticBody3D the beam is on (for sliders)

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
	_stars.set_ambient(Time.get_ticks_msec() / 1000.0 < _star_shower_until) # a new star joker's shower
	_tick_achievements(delta)
	_confetti.follow(_stars.global_position)
	if _casino.visible: # the card table stays under the shop and jokers, at the Joker Board's height
		# (the felt 3 mm under where things stand: no gap you could see, and the joker board's mat in
		# the layout mode lies clearly above it instead of flickering in the same plane)
		_casino.place_table(_table_frame(), _table_surface_y() - 0.001) # (follows the joker board)
	_animate_chip(delta)
	_sync_wheel_look()
	_animate_shop_sign()
	_animate_deck(delta)
	_animate_jokers(delta)
	_update_held_joker()
	_update_held_board_item()
	_update_held_stand()
	_animate_shop_morph(delta)
	_animate_board_items(delta)
	_update_sell_glow()
	_update_fan_glow()
	_place_hand_preview()
	if _slider_body != null:
		_update_slider()
	if _main_menu != null and _main_menu.visible: # the menu sits where the joker board is calibrated
		_main_menu.global_transform = _table_top_xf()
	if _keyboard != null and _keyboard.visible: # the keyboard for a text box: over the table's front
		_keyboard.global_transform = _table_top_xf() * Transform3D(Basis(), Vector3(0.0, 0.16, 0.1))
	if _collection != null and _collection.visible: # ... the collection's cabinet too
		_collection.global_transform = _table_top_xf()
		_collection.hover(_hover_id if _hover_kind == "collect" else 999)
	if _new_run != null and _new_run.visible: # ... and so does the New Run table
		_new_run.global_transform = _table_top_xf()
		_new_run.hover(_hover_id if _hover_kind == "setup" else -1)
	if _test != null and _test.visible: # the test tools' joker gallery stands behind the joker board
		_test.global_transform = _table_top_xf()
	if _solatro != null and _solatro.visible: # ... and Solatro's info board, token chips and signs
		_solatro.global_transform = _table_top_xf()
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
			if _solatro != null and _solatro.active:
				_solatro_cache["scene"] = msg["data"] # (Solatro on the table: the game's menu waits)
			else:
				_apply_scene(msg["data"])
		"state":
			if _solatro != null and _solatro.active:
				_solatro_cache["state"] = msg["data"]
			else:
				_apply_state(msg["data"])
		"event":
			match msg["data"].get("event", ""):
				"calibrate":
					_set_calibrating(true) # "Adjust VR Layout" in the game's Options menu
				"toggle_handedness":
					_set_left_handed(not _left_handed) # "VR: Switch Hands" in the game's Options menu
				"toggle_calm":
					_set_calm(not _calm) # "VR: Calm Lights" in the game's Options menu
				"cycle_wheel":
					_set_wheel(WHEEL_MODES[(WHEEL_MODES.find(_wheel_mode) + 1) % WHEEL_MODES.size()]) # "VR: Wheel of Fortune" in VR Settings
				"wheel":
					_show_wheel(msg["data"]) # the Wheel of Fortune card was used: spin the wheel
				"toggle_ambience":
					_set_ambience(not _ambience_on) # "VR: Casino Sounds" in VR Settings
				"floor_height":
					_set_floor(float(msg["data"].get("cm", 0.0))) # "VR: Casino Floor Height" in VR Settings
				"toggle_jimbo":
					_set_jimbo(not _jimbo_on) # "VR: Jimbo" in VR Settings
				"toggle_hands":
					_set_hands(not _hands_on) # "VR: Hands" in the game's Options menu
				"cycle_spectator":
					_cycle_spectator() # "VR: Spectator" in the game's Options menu
				"show_tutorial":
					_show_tutorial() # "VR: How To Play" in the game's Options menu
				"quit_vr":
					_on_menu_action("quit_vr") # "QUIT VR" in the game's main menu; Balatro keeps running
				"shop_buy", "card_used":
					if msg["data"].get("event", "") == "card_used" and _vr: # Stargazer, Fortune Teller, Ghost Hunter
						var used_set := str(msg["data"].get("set", ""))
						if used_set == "Planet":
							_ach.add("stargazer")
						elif used_set == "Tarot":
							_ach.add("fortune_teller")
						elif used_set == "Spectral":
							_ach.add("ghost_hunter")
					if str(msg["data"].get("set", "")) == "Planet":
						_stars.burst() # a Planet card bought or taken from a pack: stars all over the room
					elif str(msg["data"].get("set", "")) == "Spectral":
						_casino.spectral_flicker() # the Spectral Lounge's sign haunts for a moment
					if msg["data"].get("event", "") == "shop_buy":
						_fly_purchase(msg["data"]) # the bought card flies from the shop to its place
						if str(msg["data"].get("set", "")) == "Joker":
							_jimbo.react("buy_joker", 0.7)
					elif str(msg["data"].get("set", "")) == "Planet":
						_jimbo.react("planet", 0.4)
				"pack_ready":
					_show_pack(msg["data"]) # a booster pack waits to be torn open
				"score":
					_score_pop(msg["data"]) # "+30", "X2" ... at the card / joker that scored
				"shatter":
					_shatter_card(msg["data"]) # a glass card broke
				"sound":
					_sounds.play(msg["data"])
		"collection":
			if _collection != null:
				_collection.set_data(msg["data"])
		"collection_info":
			if _collection != null:
				_collection.set_info(str(msg["data"].get("key", "")), str(msg["data"].get("text", "")))
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
			if _solatro != null and _solatro.active:
				_solatro.redraw() # Solatro's own cards: drawn again, a picture may have been missing (slow PCs)
			elif not _last_scene.is_empty():
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
	_board.hide_hud = _vr # (score: tower; hands, discards, ante, boss, chips x mult: the play stand; money: the coins)
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
	if _counter != null and _vr: # the shop's items on the sales counter
		_counter.sync(scene.get("items", []), int(_state.get("round", {}).get("dollars", 0)))
	for uid in _jokers: # card art for jokers without a 3D model (comes with the scene)
		if is_instance_valid(_jokers[uid]):
			_refresh_card_stand(_jokers[uid], uid)
	_set_status("Connected – %s" % scene.get("state_name", ""))


func _send(command: Dictionary) -> void:
	if _solatro != null and _solatro.active and not SOLATRO_PASS.has(str(command.get("cmd", ""))):
		_solatro.command(command) # play, discard, click, buy ... are Solatro's now, not the game's
		return
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
		_menu_atlas_asked = false
		_last_scene = {}
	_status3d.visible = not on and not _intro.is_showing()
	_set_status("Connected" if on else "Waiting for Balatro ... (start the game with the mod)")
	if on:
		_send_flags() # the Options menu shows our settings


func _set_status(text: String) -> void:
	_status.text = text


# ---------------------------------------------------------------- game state -> 3D props

## Under the fan of cards: which poker hand the selected cards make and its level, like the run
## panel shows it - so you don't have to look away from your cards.
func _build_hand_preview() -> void:
	var fan_plane := Basis(Vector3.RIGHT, deg_to_rad(FAN_TILT))
	var below := fan_plane * Vector3(0, -CARD_SIZE.y * 0.5 - 0.07, 0.004) # under the cards, clear of the curved fan
	_hand_preview = Label3D.new()
	_hand_preview.font_size = 48
	_hand_preview.pixel_size = 0.0006
	_hand_preview.outline_size = 12
	_hand_preview.outline_modulate = Color(0.05, 0.05, 0.08)
	_hand_preview.modulate = Color(1.0, 1.0, 1.0)
	_hand_preview.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hand_preview.position = below
	_hand_preview.no_depth_test = true # drawn over everything: the hand or Jimbo's glove never hides it
	_hand_preview.render_priority = 10
	_hand_preview.visible = false
	_fan_anchor.add_child(_hand_preview)
	_hand_preview_score = Label3D.new()
	_hand_preview_score.font_size = 40
	_hand_preview_score.pixel_size = 0.0006
	_hand_preview_score.outline_size = 10
	_hand_preview_score.outline_modulate = Color(0.05, 0.05, 0.08)
	_hand_preview_score.modulate = Color(1.0, 0.85, 0.35)
	_hand_preview_score.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hand_preview_score.position = below + Vector3(0, -0.032, 0)
	_hand_preview_score.no_depth_test = true
	_hand_preview_score.render_priority = 10
	_hand_preview_score.visible = false
	_fan_anchor.add_child(_hand_preview_score)
	GameFont.apply_to(_fan_anchor)


## The second line (chips X mult) always sits just under the first one as seen from your eyes - a
## fixed offset on the fan would slide it into the first line when you look down onto the cards.
func _place_hand_preview() -> void:
	if _hand_preview == null or not _hand_preview_score.visible:
		return
	var eye: Node3D = _head if _vr else _camera
	var up := eye.global_basis.y.normalized()
	var to_eye := (eye.global_position - _hand_preview.global_position).normalized()
	up = (up - to_eye * up.dot(to_eye)).normalized() # "up" across the line of sight
	var size := _hand_preview.global_basis.get_scale().x # (a bigger card fan has bigger letters: more room)
	_hand_preview_score.global_position = _hand_preview.global_position - up * 0.042 * size


func _update_hand_preview(state: Dictionary) -> void:
	if _hand_preview == null:
		return
	var hand = state.get("round", {}).get("hand")
	var name := str(hand.get("name", "")).strip_edges() if hand is Dictionary else ""
	var show := _vr and bool(state.get("in_run", false)) and name != "" and not _hand_cards.is_empty()
	_hand_preview.visible = show
	_hand_preview_score.visible = show
	if not show:
		return
	var level := str(hand.get("level", "")).strip_edges()
	_hand_preview.text = name + ("   " + level if level != "" else "")
	var chips := str(hand.get("chips", "")).strip_edges()
	var mult := str(hand.get("mult", "")).strip_edges()
	_hand_preview_score.text = "%s  X  %s" % [chips, mult] if chips != "" and mult != "" else "" # (the game font has no ×)
	if hand.has("points"): # Solatro: fixed points per poker hand
		_hand_preview_score.text = "+%d" % int(hand["points"])
	GameFont.apply_to(_hand_preview)
	GameFont.apply_to(_hand_preview_score)


func _apply_state(state: Dictionary) -> void:
	_state = state
	if state.is_empty():
		return
	var in_run: bool = state.get("in_run", false)
	if in_run and _vr and not state.get("solatro", false):
		_ach.add("welcome") # (only counts once)
		if (state.get("jokers", []) as Array).size() >= 7:
			_ach.add("real_full_house")
		if int(state.get("round", {}).get("ante", 0)) >= 9:
			_ach.add("endless")
	if not in_run and not _glass_left.is_empty(): # "Glass Breaker": the shards go with the run
		for fx in _glass_left:
			if is_instance_valid(fx):
				fx.queue_free()
		_glass_left.clear()

	# Blind chip: front = current blind, back = stake (difficulty)
	var blind: Dictionary = state.get("blind", {})
	_set_sprite_face(_chip_front, blind.get("sprite"), Vector2.ONE * CHIP_RADIUS * 2.0)
	_set_sprite_face(_chip_back, state.get("stake_sprite"), Vector2.ONE * CHIP_RADIUS * 2.0)
	_set_chip_text(str(blind.get("chip_text", "")))
	_set_chip_back_text(str(blind.get("chip_back", "")))
	# only during a round; in the shop, blind select, cash-out or packs it would just be in the way
	_chip.visible = (in_run and ROUND_STATES.has(str(state.get("state_name", "")))) or _calibrating or _chip_defeat_t >= 0.0
	# the score tower: the blind's score so far against what it needs (only while a blind is played)
	# after the blind (cash out, game over, the win screen) it stays with the blind's last score, so you
	# see by how much you overscored or how much was missing; it goes with the shop / next blind select
	var sname := str(state.get("state_name", ""))
	if in_run and ROUND_STATES.has(sname):
		_tower_last = [float(state.get("round", {}).get("chips", 0)), float(blind.get("chips", 0))]
		_score_tower.visible = true
		_tower_judged = false
	elif in_run and sname in ["NEW_ROUND", "ROUND_EVAL"] and not _tower_judged and not _tower_last.is_empty() and not _solatro.active:
		_tower_judged = true # the blind was beaten: by how much?
		var final_score: float = _tower_last[0]
		if float(blind.get("chips", 0)) == _tower_last[1]:
			final_score = maxf(final_score, float(state.get("round", {}).get("chips", 0)))
		var need: float = _tower_last[1]
		if need > 0.0 and final_score >= need:
			if final_score >= need * 10.0:
				_ach.add("sky_high")
			if final_score < need * 1.05:
				_ach.add("close_call")
	else:
		_score_tower.visible = in_run and not _tower_last.is_empty() and (TOWER_AFTER_STATES.has(sname) or state.get("won", false))
		if not _score_tower.visible:
			_tower_last = []
	_score_tower.visible = _score_tower.visible or _calibrating
	if not _tower_last.is_empty():
		_score_tower.set_score(_tower_last[0], _tower_last[1])
		if _casino != null and _casino._boss_room != null and _tower_last[1] > 0.0: # (Violet Vessel's chalice)
			_casino._boss_room.vessel_fill = _tower_last[0] / _tower_last[1]

	# Draw pile: deck colour, height = cards left, back art on top
	var deck: Dictionary = state.get("deck", {})
	var remaining := int(deck.get("remaining", 0))
	_deck_target_height = maxf(remaining, 0) * DECK_CARD_THICKNESS
	var side_mat: StandardMaterial3D = _deck_body.material_override
	side_mat.albedo_color = DECK_COLORS.get(str(deck.get("back_key", "")), Color(0.8, 0.2, 0.2))
	if _ach != null and _ach.reward("peeking"): # edges in the chosen colour
		side_mat.albedo_color = _ach.metal("peeking")
	side_mat.metallic = 0.4 if _ach != null and _ach.reward("peeking") else 0.0
	_set_sprite_face(_deck_top, deck.get("back_sprite"), DECK_CARD)
	_deck_label.text = "%d / %d" % [remaining, int(deck.get("total", 0))]
	_deck.visible = in_run or _calibrating
	_coins.visible = in_run or _calibrating
	_coins.set_amount(int(state.get("round", {}).get("dollars", 0)))
	_joker_table.visible = in_run or _calibrating
	# Solatro needs no card stand for consumables, no chip mountain, nothing to sell and no rerolls
	var solatro: bool = state.get("solatro", false)
	_bag.visible = not solatro or _calibrating
	_coin_slot.visible = true # (Solatro: only for throwing cards away - "DISCARD")
	if _slot_solatro != solatro:
		_slot_solatro = solatro
		_sell_armed = true # (the label is set anew below)
	_lever.visible = not solatro or _calibrating
	_casino.set_mountains_visible(not solatro)
	# the main menu: in VR it is the casino table (buzzer, stack, album, ...), not the flat panel
	var menu = state.get("menu")
	if menu is Dictionary and _ach != null: # the profile's name (for the "UnderTheVRadar" wall sign)
		var pname := str(menu.get("profile", ""))
		if pname != "" and str(_ach.extra("profile_name")) != pname:
			_ach.set_extra("profile_name", pname)
	_menu_on = _vr and menu is Dictionary and not in_run and not _calibrating
	if not _menu_on:
		_new_run_open = false # (left the main menu: next time it starts with the menu again)
	if _menu_on:
		if not _menu_atlas_asked: # the Solatro cards on the menu table need the card pictures
			_menu_atlas_asked = true
			_send({"cmd": "need_atlas", "names": "cards_1 centers"}) # (one string: commands are flat)
		_main_menu.hands = [_left, _right]
		_main_menu.sync(menu, func(key: String) -> Color: return DECK_COLORS.get(key, Color(0.8, 0.2, 0.2)))
		if menu.get("setup") is Dictionary:
			_new_run.setup(menu["setup"])
		_new_run.hands = [_left, _right]
	_apply_menu_visibility()

	var sign = state.get("shop_sign")
	_shop_sign_info = sign if sign is Dictionary else {}
	_shop_sign.visible = not _shop_sign_info.is_empty() or _calibrating

	_update_hand_preview(state)
	_update_jokers(state)
	_update_card_stats(state)
	_update_keyboard(state)

	# a star joker (Supernova, Satellite, Constellation) bought or gained: the room twinkles for
	# STAR_SHOWER_SECONDS, then it's quiet again (a run that already has one starts quiet)
	if not in_run:
		_star_jokers_seen.clear()
		_star_jokers_ready = false
	else:
		for j in state.get("jokers", []):
			var uid := int(j.get("uid", -1))
			if STAR_JOKERS.has(str(j.get("key", ""))) and not _star_jokers_seen.has(uid):
				_star_jokers_seen[uid] = true
				if _star_jokers_ready:
					_star_shower_until = Time.get_ticks_msec() / 1000.0 + STAR_SHOWER_SECONDS
		_star_jokers_ready = true

	# Run won (Ante 8 boss beaten) or game over: confetti from above, once per run end
	var end := ""
	if str(state.get("state_name", "")) == "GAME_OVER":
		end = "lost"
	elif in_run and state.get("won", false):
		end = "won"
	if end != _last_end and end != "" and _was_in_state:
		if end == "won" and _vr and not state.get("solatro", false):
			_ach.add("high_roller") # a run won in VR
			if _standing:
				_ach.add("ovation")
			if _ach.reward("ovation"):
				_play_applause()
		_confetti.burst(end == "won", CONFETTI_WON if end == "won" else CONFETTI_LOST)
		_jimbo.react("win" if end == "won" else "sad")
		_run_end_scene(end == "won")
	_last_end = end
	_apply_table_fun(state, in_run)
	_was_in_state = true


## Solatro's blind chip: SOLATRO in green neon on a dark face, the round underneath ("" = none).
func _set_chip_text(sub: String) -> void:
	var face := _chip_front.get_node_or_null("SolatroFace") as Node3D
	if sub == "":
		if face != null:
			face.visible = false
		return
	if face == null:
		face = Node3D.new()
		face.name = "SolatroFace"
		_chip_front.add_child(face)
		var disc := MeshInstance3D.new()
		var c := CylinderMesh.new()
		c.top_radius = CHIP_RADIUS * 0.86
		c.bottom_radius = CHIP_RADIUS * 0.86
		c.height = 0.001
		disc.mesh = c
		disc.rotation_degrees.x = 90.0
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.14, 0.04, 0.12)
		m.roughness = 0.6
		disc.material_override = m
		face.add_child(disc)
		var title := Label3D.new()
		title.name = "Title"
		title.text = "SOLATRO"
		title.font_size = 48
		title.pixel_size = 0.00042
		title.modulate = Color(0.5, 1.8, 0.9)
		title.outline_size = 6
		title.outline_modulate = Color(0.02, 0.1, 0.05)
		title.position = Vector3(0, 0.005, 0.0012)
		face.add_child(title)
		var round_label := Label3D.new()
		round_label.name = "Round"
		round_label.font_size = 28
		round_label.pixel_size = 0.00042
		round_label.modulate = Color(1.0, 0.8, 0.35)
		round_label.outline_size = 0
		round_label.position = Vector3(0, -0.016, 0.0012)
		face.add_child(round_label)
		GameFont.apply_to(face)
	face.visible = true
	(face.get_node("Round") as Label3D).text = sub


## Solatro's blind chip, back: plays and discards left (the stake picture would mean nothing there).
func _set_chip_back_text(text: String) -> void:
	var face := _chip_back.get_node_or_null("SolatroBack") as Node3D
	if text == "":
		if face != null:
			face.visible = false
		return
	if face == null:
		face = Node3D.new()
		face.name = "SolatroBack"
		_chip_back.add_child(face)
		var disc := MeshInstance3D.new()
		var c := CylinderMesh.new()
		c.top_radius = CHIP_RADIUS * 0.86
		c.bottom_radius = CHIP_RADIUS * 0.86
		c.height = 0.001
		disc.mesh = c
		disc.rotation_degrees.x = 90.0
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.14, 0.04, 0.12)
		m.roughness = 0.6
		disc.material_override = m
		face.add_child(disc)
		var label := Label3D.new()
		label.name = "Text"
		label.font_size = 25
		label.pixel_size = 0.00042
		label.line_spacing = 6.0
		label.modulate = Color(1.0, 0.85, 0.4)
		label.outline_size = 0
		label.position = Vector3(0, 0, 0.0012)
		face.add_child(label)
		GameFont.apply_to(face)
	face.visible = true
	(face.get_node("Text") as Label3D).text = text


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
				# a floating text over the model ("+6 Mult", "Discard: King" ...) would say what the
				# pedestal says: values only at the bottom (texts printed on the model itself stay)
				if own != null and own.billboard != BaseMaterial3D.BILLBOARD_DISABLED:
					own.visible = str(j.get("value", "")) == ""
			_set_price_sticker(inst, int(j.get("sell", 0)))
			_set_sticker_badges(inst, j.get("stickers", []))
			_set_face_down(inst, str(j.get("facing", "front")) == "back", state)
			_set_pinned(inst, bool(j.get("pinned", false)))
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
	var hidden := false # face-down jokers (The Amber Acorn) are shuffled so you can't follow them
	for inst in _jokers.values():
		if is_instance_valid(inst) and inst.get_meta("face_down", false):
			hidden = true
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
	if hidden:
		_joker_shuffle_t = 0.0 # all of them fly up, whirl and come down on their new places


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
		if absf(candidate.x) <= half.x and absf(candidate.z - JOKER_TABLE_CENTER_Z) <= half.y:
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
	return Transform3D(basis, Vector3(_rng_board.randf_range(-half.x, half.x), JOKER_TABLE_TOP,
			JOKER_TABLE_CENTER_Z + _rng_board.randf_range(-half.y, half.y)))


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
	back.name = "Back"
	back.rotation_degrees.y = 180
	back.position.z = -TABLE_CARD_DEPTH - 0.0003
	card.add_child(back)
	var core := _card_core(JOKER_CARD_SIZE, TABLE_CARD_DEPTH)
	core.position.z = -TABLE_CARD_DEPTH * 0.5 # (behind the art, which lies at z = 0)
	card.add_child(core)
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
			_shape_card(card, str(it.get("key", "")), layers)
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
	var shuffling := _joker_shuffle_t >= 0.0
	if shuffling:
		_joker_shuffle_t += delta
		if _joker_shuffle_t > JOKER_SHUFFLE_TIME:
			_joker_shuffle_t = -1.0
	for inst in _jokers.values():
		if is_instance_valid(inst) and not inst.has_meta("held") and not inst.has_meta("selling"):
			if shuffling: # face down (The Amber Acorn): up into a whirl, swapped up there, down again
				var u := clampf(_joker_shuffle_t / JOKER_SHUFFLE_TIME, 0.0, 1.0)
				var target := _joker_target(inst)
				if u < 0.5: # (the first half: still over its old place; all look the same up there)
					target.origin = inst.get_meta("shuffle_from", inst.position)
				else:
					inst.set_meta("shuffle_from", target.origin)
				target.origin.y += sin(u * PI) * 0.16
				target.basis = target.basis * Basis(Vector3.UP, sin(u * PI) * TAU * 1.5)
				inst.transform = inst.transform.interpolate_with(target, 1.0 - exp(-14.0 * delta))
				continue
			inst.set_meta("shuffle_from", inst.position)
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
	if inst.get_meta("pinned", false): # it may be lifted (to look at it, or sell it) but goes back to its place
		inst.set_meta("pinned_spot", inst.get_meta("free", inst.transform))
	return true


func _update_held_joker() -> void:
	if _held_joker < 0:
		return
	var inst = _jokers.get(_held_joker)
	if inst == null or not is_instance_valid(inst): # sold or destroyed while in the hand
		_held_joker = -1
		return
	inst.global_transform = _held_hand.global_transform * _held_offset
	# held low over the board, it bumps the other pedestals out of its way, like toys on a table
	var local: Vector3 = _joker_table.global_transform.affine_inverse() * inst.global_position
	if local.y < JOKER_PUSH_HEIGHT:
		_push_board(inst, Vector2(local.x, local.z), JOKER_RADIUS, true)


## Nothing on the joker board stands inside anything else: a joker or board item (deck, money,
## coin slot, card stand) that is held or was just put down pushes the others away (they glide to
## their new spot), and those push their neighbours in turn. Each thing counts as a circle.
const JOKER_RADIUS := 0.045       # a pedestal (radius 0.042) and a hair
const JOKER_PUSH_DIST := JOKER_RADIUS * 2.0
const JOKER_PUSH_HEIGHT := 0.12   # a joker held higher above the board passes over the others


## The board items you can grab and slide, with the circle they take up on the board.
func _board_items() -> Array:
	return [[_deck, 0.055], [_coins, 0.05], [_coin_slot, 0.05], [_bag, 0.09]]


func _push_jokers(pusher: Node3D, at: Vector2) -> void:
	_push_board(pusher, at, JOKER_RADIUS, false)


## keep_slot: a held joker doesn't push the coin slot - it may be on its way there to be sold
func _push_board(pusher: Node3D, at: Vector2, pusher_radius: float, keep_slot := false) -> void:
	var spots := {}  # thing -> Vector2: where it stands on the board
	var radius := {} # thing -> its circle
	var is_item := {}
	for other in _jokers.values():
		if other == pusher or not is_instance_valid(other) or other.has_meta("held") or other.has_meta("selling"):
			continue
		var t := _joker_target(other)
		spots[other] = Vector2(t.origin.x, t.origin.z)
		radius[other] = JOKER_RADIUS
	for entry in _board_items():
		var node: Node3D = entry[0]
		if node == null or node == pusher or node == _held_item or (keep_slot and node == _coin_slot) or not node.visible:
			continue
		spots[node] = node.get_meta("board_goal", Vector2(node.position.x, node.position.z))
		radius[node] = entry[1]
		is_item[node] = true
	var moved := {}
	for _round in 10: # a few passes: pushed things push their neighbours too
		var changed := false
		for a in spots:
			for b in spots:
				if a == b:
					continue
				var d: Vector2 = spots[b] - spots[a]
				var need: float = radius[a] + radius[b]
				if d.length() < need:
					var dir := d.normalized() if d.length() > 0.001 else Vector2.RIGHT
					var gap := (need - d.length()) * 0.5
					spots[a] -= dir * gap
					spots[b] += dir * gap
					moved[a] = true
					moved[b] = true
					changed = true
		for other in spots: # last in each pass: what you hold always wins over the neighbours
			var d: Vector2 = spots[other] - at
			var need: float = pusher_radius + radius[other]
			if d.length() < need - 0.0005:
				spots[other] = at + (d.normalized() if d.length() > 0.001 else Vector2.RIGHT) * need
				moved[other] = true
				changed = true
		for other in spots: # never off the board
			spots[other] = _clamp_to_board(spots[other]) if is_item.has(other) else _clamp_to_joker_zone(spots[other])
		if not changed:
			break
	if _jokers.values().has(pusher): # "Bowling Alley": jokers this joker pushed aside in one go
		if pusher != _bowl_pusher:
			_bowl_pusher = pusher
			_bowl_hits.clear()
		for other in moved:
			if not is_item.has(other):
				_bowl_hits[other] = true
		_ach.reach("bowling", _bowl_hits.size())
	for other in moved:
		var p: Vector2 = spots[other]
		if is_item.has(other):
			other.set_meta("board_goal", p) # glides there (_animate_board_items)
			_board_save_pending = true
		else:
			var t := _joker_target(other)
			other.set_meta("free", Transform3D(t.basis, Vector3(p.x, JOKER_TABLE_TOP, p.y)))


## The play stand (whole run) and the shop counter (shop open) are two separate items; both can be
## put anywhere in the room, turned and tilted every way ("Play Stand", "Shop Counter" in the layout).
var _shop_goal := 0.0
var _stand_on := false
var _shop_machine: Node3D          # the reroll machine and Next Round, on their own stand


func _animate_shop_morph(_delta: float) -> void:
	if _counter == null:
		return
	_play_stand.visible = (_stand_on and _shop_goal < 0.5) or _calibrating # (the shop open: the counter instead)
	_counter.visible = _vr and (_shop_goal > 0.5 or _calibrating)


## The casino table goes with the joker board: this is where the layout would be if the board stood at
## its default place in it (only its turn round the vertical and its position count).
const JIMBO_SPOT := Vector3(0.45, 0.0, -0.2) # (layout space: across the table, right of the board, at its back edge)


func _table_frame() -> Transform3D:
	var jb := _joker_table.global_basis
	var yaw := Basis(Vector3.UP, jb.get_euler().y)
	var board := Transform3D(yaw, _joker_table.global_position)
	return board * Transform3D(Basis(), -Vector3(JOKER_TABLE_POS.x, 0.0, JOKER_TABLE_POS.z))


## Where things stand on the table: the joker board's mat surface (the casino's felt lies there too).
func _table_surface_y() -> float:
	return _joker_table.global_position.y + JOKER_TABLE_TOP * _joker_table.global_basis.get_scale().y


## The menu, the New Run table, Solatro and the test gallery: turned like the joker board, standing on
## its surface (not on its bottom: the casino's felt would cover them).
func _table_top_xf() -> Transform3D:
	var b := _joker_table.global_basis
	return Transform3D(b.orthonormalized(), _joker_table.global_position + b.y.normalized() * JOKER_TABLE_TOP * b.get_scale().y)


## The stand for the played cards can be gripped like the board items and put anywhere, turned and
## tilted every way. Saved with the layout ("Play Stand").
var _held_stand_hand: XRController3D = null
var _held_stand_xf := Transform3D()


func _try_grab_stand(hand: XRController3D) -> bool:
	if not _vr or _held_stand_hand != null or not _play_stand.is_visible_in_tree() or _calibrating:
		return false
	var centre := _play_stand.global_transform * _play_surface().origin
	if centre.distance_to(hand.global_position) > 0.13:
		return false
	_held_stand_hand = hand
	_held_stand_xf = hand.global_transform.affine_inverse() * _play_stand.global_transform
	_buzz_hand(hand, 0.2, 0.03)
	return true


func _update_held_stand() -> void:
	if _held_stand_hand == null:
		return
	if not is_instance_valid(_held_stand_hand) or not _play_stand.is_visible_in_tree():
		_held_stand_hand = null
		return
	_play_stand.global_transform = _held_stand_hand.global_transform * _held_stand_xf # (any place, any tilt ...
	_snap_to_table(_play_stand, _held_stand_hand) # ... but close to the table it clicks onto it, level)


## Board items may go anywhere on the mat (jokers keep to the middle, see _clamp_to_joker_zone).
func _clamp_to_board(p: Vector2) -> Vector2:
	var half := JOKER_TABLE_SIZE * 0.5 - Vector2.ONE * JOKER_TABLE_MARGIN
	return Vector2(clampf(p.x, -half.x, half.x), clampf(p.y, JOKER_TABLE_CENTER_Z - half.y, JOKER_TABLE_CENTER_Z + half.y))


# ---------------------------------------------------------------- picking up board items
# Deck, money, coin slot and card stand can be gripped while playing (like the jokers) and slid
# over the board; they stay on it, turn with the hand around the vertical axis and push everything
# else out of the way. Where they end up is saved like a calibration.

const BOARD_ITEM_GRAB_RADIUS := 0.09
var _held_item: Node3D = null
var _held_item_hand: XRController3D
var _held_item_xf := Transform3D()    # the item relative to the hand when it was taken (carried like a joker)
var _board_save_pending := false      # an item moved: save the layout once everything stands still


func _try_grab_board_item(hand: XRController3D) -> bool:
	if not _vr or _held_item != null or not _joker_table.is_visible_in_tree():
		return false
	var best: Node3D = null
	var best_dist := BOARD_ITEM_GRAB_RADIUS
	for entry in _board_items():
		var node: Node3D = entry[0]
		if node == null or not node.is_visible_in_tree():
			continue
		var d := (node.global_position + _joker_table.global_basis.y.normalized() * 0.03).distance_to(hand.global_position)
		if d < best_dist:
			best = node
			best_dist = d
	if best == null:
		return false
	_held_item = best
	_held_item_hand = hand
	_held_item_xf = hand.global_transform.affine_inverse() * best.global_transform
	best.remove_meta("board_goal")
	best.remove_meta("board_fall")
	_buzz_hand(hand, 0.2, 0.03)
	return true


func _hand_yaw_on_board(hand: Node3D) -> float:
	var f: Vector3 = _joker_table.global_basis.orthonormalized().inverse() * -hand.global_basis.z
	return atan2(-f.x, -f.z)


func _update_held_board_item() -> void:
	if _held_item == null:
		return
	if not is_instance_valid(_held_item_hand):
		_drop_board_item()
		return
	# carried freely in the hand, like a joker: it may leave the mat (and only settles on it)
	_held_item.global_transform = _held_item_hand.global_transform * _held_item_xf
	# low over the mat, it pushes the others out of its way
	var local := _joker_table.global_transform.affine_inverse() * _held_item.global_position
	var inside := absf(local.x) <= JOKER_TABLE_SIZE.x * 0.5 and absf(local.z - JOKER_TABLE_CENTER_Z) <= JOKER_TABLE_SIZE.y * 0.5
	if inside and local.y < JOKER_PUSH_HEIGHT:
		_push_board(_held_item, Vector2(local.x, local.z), _board_item_radius(_held_item))


func _drop_board_item() -> void:
	if _held_item == null:
		return
	var node := _held_item
	_held_item = null
	# let go anywhere: it is put on the mat (the nearest spot on it), upright, and comes down onto it
	var t := _joker_table.global_transform.affine_inverse() * node.global_transform
	var facing := t.basis.z
	facing.y = 0
	var yaw := atan2(facing.x, facing.z) if facing.length() > 0.001 else 0.0
	var p := _clamp_to_board(Vector2(t.origin.x, t.origin.z))
	node.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, t.origin.y, p.y))
	node.set_meta("board_fall", true)
	var which := [_deck, _coins, _coin_slot, _bag].find(node)
	if which >= 0:
		_ach.add_once("neat_freak", ["deck", "money", "coin_slot", "card_stand"][which])
	_push_board(node, p, _board_item_radius(node))
	_board_save_pending = true


func _board_item_radius(node: Node3D) -> float:
	for entry in _board_items():
		if entry[0] == node:
			return entry[1]
	return 0.05


## Pushed board items glide to their new spot; once all stand still, the layout is saved.
func _animate_board_items(delta: float) -> void:
	var k := 1.0 - exp(-10.0 * delta)
	var busy := false
	for entry in _board_items():
		var node: Node3D = entry[0]
		if node == null or node == _held_item:
			continue
		if node.has_meta("board_fall"): # let go: sinks down onto the mat
			var y := lerpf(node.position.y, JOKER_TABLE_TOP, k)
			if absf(y - JOKER_TABLE_TOP) < 0.0005:
				y = JOKER_TABLE_TOP
				node.remove_meta("board_fall")
			else:
				busy = true
			node.position.y = y
		if not node.has_meta("board_goal"):
			continue
		var goal: Vector2 = node.get_meta("board_goal")
		var p := Vector2(node.position.x, node.position.z).lerp(goal, k)
		if p.distance_to(goal) < 0.0005:
			p = goal
			node.remove_meta("board_goal")
		else:
			busy = true
		node.position = Vector3(p.x, node.position.y, p.y)
	if _board_save_pending and not busy and _held_item == null and _held_joker < 0:
		_board_save_pending = false
		_save_layout() # (like a calibration: the items stay where you put them)


func _clamp_to_joker_zone(p: Vector2) -> Vector2:
	var half := Vector2(JOKER_ZONE_HALF, JOKER_TABLE_SIZE.y * 0.5 - JOKER_TABLE_MARGIN)
	return Vector2(clampf(p.x, -half.x, half.x), clampf(p.y, JOKER_TABLE_CENTER_Z - half.y, JOKER_TABLE_CENTER_Z + half.y))


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
	var p := Vector3(clampf(t.origin.x, -half.x, half.x), JOKER_TABLE_TOP,
			clampf(t.origin.z, JOKER_TABLE_CENTER_Z - half.y, JOKER_TABLE_CENTER_Z + half.y))
	inst.set_meta("free", Transform3D(Basis(Vector3.UP, yaw), p))
	if inst.get_meta("pinned", false) and inst.has_meta("pinned_spot"): # pinned: back where it was
		inst.set_meta("free", inst.get_meta("pinned_spot"))
		inst.remove_meta("pinned_spot")
		_rack_hint(inst, "Pinned - it stays on the left")
		p = (inst.get_meta("free") as Transform3D).origin
	_push_jokers(inst, Vector2(p.x, p.z)) # where it lands, the others make room
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
		_ach.add("long_haul") # the jokers' order in the game changed
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
	base.set_meta("wood", base.material_override)
	base.name = "PedBase"
	holder.add_child(base)
	var top := MeshInstance3D.new()
	var top_mesh := CylinderMesh.new()
	top_mesh.top_radius = 0.032
	top_mesh.bottom_radius = 0.038 # the bevel
	top_mesh.height = 0.007
	top.mesh = top_mesh
	top.position.y = 0.012 + 0.0035
	top.material_override = _wood_material(Color(0.1, 0.06, 0.05))
	top.set_meta("wood", top.material_override)
	top.name = "PedTop"
	holder.add_child(top)
	_add_blob_shadow(holder, 0.085) # (mixed reality: a soft shadow on the real table)
	_style_pedestal(holder)

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
	tag.width = 0.115 / tag.pixel_size # long values ("Queen of Hearts", "+0 to +23 Mult") wrap: they stay above their own pedestal
	tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tag.outline_size = 10
	tag.outline_modulate = Color(0.05, 0.03, 0.02)
	tag.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	tag.top_level = true # placed in world space, not turned with the joker
	tag.visible = false
	holder.add_child(tag)
	return holder


## A pinned joker (challenges): a big red push pin stuck in its pedestal and a "PINNED" tag - it
## stays the leftmost joker (the mod keeps it there; VR puts it back when it is let go).
func _set_pinned(inst: Node3D, on: bool) -> void:
	inst.set_meta("pinned", on)
	var pin := inst.get_node_or_null("Pin") as Node3D
	if on and pin == null:
		pin = Node3D.new()
		pin.name = "Pin"
		pin.position = Vector3(-0.03, PEDESTAL_HEIGHT, 0.0)
		pin.rotation_degrees.z = 15.0
		inst.add_child(pin)
		var steel := StandardMaterial3D.new()
		steel.albedo_color = Color(0.8, 0.8, 0.85)
		steel.metallic = 0.8
		steel.roughness = 0.3
		var needle := MeshInstance3D.new()
		var nm := CylinderMesh.new()
		nm.top_radius = 0.0012
		nm.bottom_radius = 0.0004
		nm.height = 0.02
		needle.mesh = nm
		needle.material_override = steel
		needle.position.y = 0.006
		pin.add_child(needle)
		var red := StandardMaterial3D.new()
		red.albedo_color = Color(0.95, 0.35, 0.1) # the game's orange "Pinned" badge
		red.roughness = 0.3
		red.emission_enabled = true
		red.emission = Color(0.95, 0.35, 0.1) * 0.3
		var head := MeshInstance3D.new()
		var hm := CylinderMesh.new()
		hm.top_radius = 0.006
		hm.bottom_radius = 0.004
		hm.height = 0.012
		head.mesh = hm
		head.material_override = red
		head.position.y = 0.021
		pin.add_child(head)
		var cap := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.008
		cm.bottom_radius = 0.008
		cm.height = 0.003
		cap.mesh = cm
		cap.material_override = red
		cap.position.y = 0.028
		pin.add_child(cap)
		var tag := Label3D.new()
		tag.text = "PINNED"
		tag.font_size = 32
		tag.pixel_size = 0.0004
		tag.modulate = Color(1.0, 0.55, 0.2)
		tag.outline_size = 6
		tag.outline_modulate = Color(0.1, 0.03, 0.0)
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.position.y = 0.042
		pin.add_child(tag)
		GameFont.apply_to(pin)
	if pin != null:
		pin.visible = on


## The Amber Acorn turned this joker face down: no model, no value, no stickers - only a card
## back on its pedestal, like in the game. Turned up again, everything comes back.
func _set_face_down(inst: Node3D, down: bool, state: Dictionary) -> void:
	inst.set_meta("face_down", down)
	var back := inst.get_node_or_null("FaceDown") as Node3D
	if down and back == null:
		back = _make_card_stand()
		back.name = "FaceDown"
		inst.add_child(back)
	if back != null:
		back.visible = down
		if down: # the deck's card back
			var sprite = state.get("deck", {}).get("back_sprite")
			var mat := CardArt.material(sprite.get("atlas"), sprite.get("pos")) if sprite is Dictionary else null
			CardArt.apply_layers(back.get_node("Card"), [mat] if mat != null else [], JOKER_CARD_SIZE, 0.0003, 0.0004, 1)
	var model = inst.get_meta("model") if inst.has_meta("model") else null
	if model is Node3D:
		model.visible = not down
	var own_stand := inst.get_node_or_null("CardStand") as Node3D
	if own_stand != null:
		own_stand.visible = not down
	for n in ["StickerBadges", "ValueTag"]:
		var node := inst.get_node_or_null(n) as Node3D
		if node != null and down:
			node.visible = false


## A price sticker under the pedestal, like at a flea market: what the joker sells for. Only seen
## when you pick the joker up and turn it over (it is shown only while held).
## The stickers a joker wears (Eternal, Rental, Perishable, stake, mods) as small badges on the
## front-left of its pedestal, the way the card would show them. Rebuilt only when they change.
const BADGE_SIZE := 0.025 # (the sticker itself, cut out of its card-sized cell: well readable)
func _set_sticker_badges(inst: Node3D, stickers: Array) -> void:
	var key := JSON.stringify(stickers)
	if inst.get_meta("badge_key", "") == key:
		return
	inst.set_meta("badge_key", key)
	var old := inst.get_node_or_null("StickerBadges")
	if old != null:
		old.free()
	if stickers.is_empty():
		return
	var row := Node3D.new()
	row.name = "StickerBadges"
	inst.add_child(row)
	for i in stickers.size():
		var s = stickers[i]
		if not (s is Dictionary):
			continue
		var cut := CardArt.cropped_material(s.get("a"), s.get("p")) # empty until that atlas has arrived
		if cut.is_empty():
			continue
		var badge := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(BADGE_SIZE * float(cut[1]), BADGE_SIZE)
		badge.mesh = quad
		badge.material_override = cut[0]
		# leaning against the front of the pedestal, side by side (the model above stays free)
		var n_badges := stickers.size()
		var bx := (row.get_child_count() - (n_badges - 1) * 0.5) * (BADGE_SIZE + 0.003)
		badge.position = Vector3(bx, BADGE_SIZE * 0.5 + 0.002, 0.045)
		badge.rotation_degrees.x = -20.0
		badge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		row.add_child(badge)
	if row.get_child_count() == 0:
		row.free()
		inst.set_meta("badge_key", "") # try again once the atlases are there


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
	elif "$" in value:
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
	rim.position = Vector3(0, (JOKER_TABLE_TOP - 0.002) * 0.5, JOKER_TABLE_CENTER_Z)
	rim.material_override = _wood_material(Color(0.36, 0.43, 0.5))
	_joker_mat.add_child(rim)
	var felt := MeshInstance3D.new()
	var felt_mesh := BoxMesh.new()
	felt_mesh.size = Vector3(JOKER_TABLE_SIZE.x, JOKER_TABLE_TOP, JOKER_TABLE_SIZE.y)
	felt.mesh = felt_mesh
	felt.position = Vector3(0, JOKER_TABLE_TOP * 0.5 + 0.0005, JOKER_TABLE_CENTER_Z)
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
	var p := Vector3(clampf(t.origin.x, -half.x, half.x), JOKER_TABLE_TOP,
			clampf(t.origin.z, JOKER_TABLE_CENTER_Z - half.y, JOKER_TABLE_CENTER_Z + half.y))
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
	var over := _deck.is_visible_in_tree() and (_hand_over_deck(_right) or _hand_over_deck(_left)) \
			and _held_item != _deck # carrying the deck around doesn't open the deck view
	if over == _deck_hover:
		return
	if over and _state.get("overlay", false) and not _state.get("viewing_deck", false):
		return # another menu is open; don't stack "View Deck" on top of it
	_deck_hover = over
	_send({"cmd": "deck_view", "on": over})
	if over:
		_ach.add("peeking")


func _hand_over_deck(hand: XRController3D) -> bool:
	var local := _deck.to_local(hand.global_position)
	var flat := Vector2(local.x, local.z).length()
	return flat < DECK_HOVER_RADIUS and local.y > -0.03 and local.y < _deck_height + 0.15


# ---------------------------------------------------------------- pointing, clicking, tooltips

func _ray_target() -> Dictionary:
	# things that are hidden (the shop counter while a pack is open ...) keep their collision bodies:
	# the beam goes through them
	_ray.clear_exceptions()
	for i in 8:
		var hidden := _ray.get_collider() as Node3D if _ray.is_colliding() else null
		if hidden == null or hidden.is_visible_in_tree():
			break
		_ray.add_exception(hidden)
		_ray.force_raycast_update()
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
			"area": str(body.get_meta("area", "")), "body": body}
	return {}


func _update_pointer(target: Dictionary, delta: float) -> void:
	var id: int = target.get("id", -1)
	if id != _hover_id:
		if _hover_sent:
			_send({"cmd": "unhover", "target": _hover_id})
		_hover_id = id
		_hover_kind = target.get("kind", "")
		_hover_area = target.get("area", "")
		_hover_body = target.get("body") # (a slider needs the track itself to know where the beam is on it)
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
	elif id >= 0 and not _hover_sent and _hover_kind in ["card", "tip", "shopitem"]:
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
	if _vr and target.get("kind", "") != "":
		_ach.add("laser_pointer") # a click with the beam
	if target.get("kind", "") == "card" and REORDER_AREAS.has(target.get("area", "")):
		_drag_id = id
		_drag_area = target["area"]
		_drop_target = -1
		_drag_armed = false
		_drag_pressed_at = Time.get_ticks_msec() / 1000.0
	elif target.get("kind", "") == "pack":
		if _pack != null and is_instance_valid(_pack):
			_pack.rip() # the shortcut: trigger on the waiting booster pack
	elif target.get("kind", "") == "nextround":
		_send({"cmd": "next_round"}) # the red button above the reroll machine
		_buzz(0.4, 0.05)
	elif target.get("kind", "") == "wrist":
		if _wrist != null and _wrist.visible: # (a closed menu never reacts)
			_wrist.press(id) # a button of the menu above the card hand
	elif target.get("kind", "") == "slider":
		_slider_body = target.get("body") # a slider track (volume ...): follows the beam while the trigger is held
		_slider_id = id
		_slider_last = -1.0
		_update_slider()
	elif target.get("kind", "") == "setup":
		if _new_run != null and _new_run.visible: # START, BACK, a deck or a stake chip on the New Run table
			_new_run.press(id)
			_buzz(0.3, 0.04)
	elif target.get("kind", "") == "kbd":
		if _keyboard != null and _keyboard.visible: # a key of the keyboard for the seed / a profile name
			_keyboard.press(id)
			_buzz(0.15, 0.02)
	elif target.get("kind", "") == "collect":
		if _collection != null and _collection.visible: # a collection sign, the pages, STATS, BACK
			_collection.press(id)
			_buzz(0.25, 0.03)
	elif target.get("kind", "") == "ach":
		if _ach_menu != null and _ach_menu.visible:
			_ach_menu.press(id) # a reward's ON / OFF, BACK, or a page
	elif target.get("kind", "") == "photocam":
		if _photo != null and _photo.visible:
			_photo.self_timer() # 3, 2, 1 ... (time to strike a pose)
	elif target.get("kind", "") == "cstats":
		if _card_stats != null and _card_stats.visible:
			_card_stats.press(id) # a tab, BACK or CLOSE of the card stats
	elif target.get("kind", "") == "wheel":
		pass # (the Wheel of Fortune: spun by holding its rim with the trigger, not by the beam)
	elif target.get("kind", "") == "solatro":
		if _solatro != null and _solatro.visible: # EXIT, PLAY AGAIN, MENU, or a token chip (= use it)
			_solatro.press(id)
			_buzz(0.3, 0.04)
	elif target.get("kind", "") == "menu":
		if _main_menu != null and _main_menu.visible: # buzzer, stack, album, bell, signs on the menu table
			_main_menu.press(_main_menu.action_for(id))
	elif target.get("kind", "") == "tutorial":
		if _tutorial != null and _tutorial.visible:
			_tutorial.press(id) # "Next" / "Skip" on Jimbo's tips
	elif target.get("kind", "") == "consumable":
		_use_consumable(id, false) # trigger on a tarot / planet / spectral card in the rack
	elif target.get("kind", "") == "shopitem" and _counter != null and _counter.has_item(id):
		_counter.select(id) # selected: its BUY (and BUY & USE) buttons appear in front of it
		_buzz(0.2, 0.03)
	elif target.get("kind", "") == "shopbuy" and _counter != null:
		_counter_result(_counter.press_buy(id), null)
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
	if _slider_body != null: # let go of a slider: it stays where the beam was
		_update_slider()
		_slider_body = null
		return
	if _drag_id < 0:
		return
	var released_on: int = target.get("id", -1)
	var was_hand := _drag_area == "hand"
	if _drag_armed and _drop_target >= 0:
		_send({"cmd": "move", "target": _drag_id, "to": _drop_target})
		_buzz(0.25, 0.04)
		if was_hand and not (_solatro != null and _solatro.active): # (Solatro has already moved it)
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
	if _solatro != null and _solatro.active:
		return # Solatro answers at once: its scene already shows the card selected (flipping it again would undo that)
	if str(_state.get("blind", {}).get("key", "")) == "bl_final_bell":
		return # Cerulean Bell keeps one card selected: the game decides, no quick flip that it would undo
	for i in _hand_items.size():
		if int(_hand_items[i].get("id", -1)) == id:
			var it: Dictionary = _hand_items[i].duplicate()
			it["hl"] = not it.get("hl", false)
			_hand_items[i] = it
			_hl_pending[id] = [it["hl"], Time.get_ticks_msec() / 1000.0]
			break


## Short vibration on the pointing hand.
## Sliders in the game's menus (volume ...): while the trigger is held on a slider's track, the
## point where the beam crosses the track's plane sets the value (0 at its left end, 1 at its right).
var _slider_body: StaticBody3D = null
var _slider_id := -1
var _slider_last := -1.0


func _update_slider() -> void:
	if _slider_body == null or not is_instance_valid(_slider_body) or not _slider_body.is_inside_tree():
		_slider_body = null
		return
	var p := _pointer_point
	if _vr: # along the beam, even when it slips off the thin track
		var plane := Plane(_slider_body.global_basis.z.normalized(), _slider_body.global_position)
		var hit = plane.intersects_ray(_ray.global_position, -_ray.global_basis.z)
		if hit != null:
			p = hit
	var box := (_slider_body.get_child(0) as CollisionShape3D).shape as BoxShape3D
	var local := _slider_body.to_local(p)
	var f := clampf(local.x / maxf(box.size.x, 0.0001) + 0.5, 0.0, 1.0)
	if absf(f - _slider_last) > 0.005:
		_slider_last = f
		_send({"cmd": "slider", "target": _slider_id, "frac": snappedf(f, 0.001)})


## SOLATRO from the menu table: played here in the client; the game stays in its main menu and only
## sends the card pictures. Its scene and state wait in _solatro_cache until Solatro is left.
func _start_solatro() -> void:
	_send({"cmd": "need_atlas", "names": "cards_1 centers Joker blind_chips"}) # (one string: commands are flat)
	_solatro_cache = {"scene": _last_scene, "state": _state}
	_new_run_open = false
	_solatro.hands = [_left, _right]
	_solatro.best = _solatro_best(-1)
	_solatro.set_left_handed(_left_handed)
	_coins_home = _coins.transform # the money goes behind the bought tokens (back again after Solatro)
	_coins.transform = Transform3D(_coins.basis, SOLATRO_COINS_POS)
	var cfg := ConfigFile.new()
	cfg.load(LAYOUT_FILE)
	var bowl = cfg.get_value("solatro", "bowl") if cfg.has_section_key("solatro", "bowl") else null
	if bowl is Vector3:
		_solatro.set_bowl(bowl) # where you put it last time
	var note = cfg.get_value("solatro", "note") if cfg.has_section_key("solatro", "note") else null
	if note is Transform3D:
		_solatro.set_note(note) # the HAND POINTS card too
	_board.visible = false # (the game's flat panels: nothing of Solatro there)
	_counter.set_solatro(true) # the Bonus Shoppe sells for points
	_solatro.start()


func _on_solatro_publish(scene: Dictionary, state: Dictionary) -> void:
	_apply_state(state)
	_apply_scene(scene)
	if int(state.get("round", {}).get("round", 0)) >= 10:
		_ach.add("giga_dweeb") # round 10 in Solatro
	if str(state.get("state_name", "")) == "GAME_OVER" and _solatro.best > _solatro_best(-1):
		_solatro_best(_solatro.best)


## Solatro is played by VR alone, so the game makes no sound for it: its own cards' sounds, made of
## Balatro's (the mod sends them when VR connects). Played: the cards slide onto the stand one by one,
## then chips for each and the mult hit. (Discarding stays quiet.)
func _solatro_sound(kind: String, cards: int) -> void:
	var stand := _play_stand.global_transform * _play_surface().origin
	var at_time := func(t: float, ev: Dictionary):
		get_tree().create_timer(t).timeout.connect(func(): _sounds.play(ev))
	if kind == "play":
		for i in cards:
			at_time.call(0.07 * i, {"code": "cardSlide1", "per": 0.9 + 0.05 * i, "vol": 0.7, "at": stand, "own": true})
		for i in cards:
			at_time.call(0.55 + 0.13 * i, {"code": "chips1", "per": 0.9 + 0.08 * i, "vol": 0.55, "at": stand, "own": true})
		at_time.call(0.6 + 0.13 * cards, {"code": "multhit1", "per": 1.0, "vol": 0.6, "at": stand, "own": true})


## Solatro's messages float up over the table; several at once stack instead of overlapping.
func _solatro_hint(text: String) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	_solatro_hints = _solatro_hints.filter(func(t: float) -> bool: return now - t < 2.0)
	_rack_hint(_solatro, text, 0.05 * _solatro_hints.size())
	_solatro_hints.append(now)


## Solatro: the money lies behind the row of bought tokens, about in the middle.
const SOLATRO_COINS_POS := Vector3(-0.15, JOKER_TABLE_TOP, -0.08)
var _coins_home := Transform3D()


func _leave_solatro() -> void:
	_solatro.stop()
	_coins.transform = _coins_home
	_board.visible = true
	_counter.set_solatro(false)
	var state: Dictionary = _solatro_cache.get("state", {})
	var scene: Dictionary = _solatro_cache.get("scene", {})
	_solatro_cache = {}
	_apply_state(state)
	_apply_scene(scene) # (an empty one too: the Solatro cards leave the hand)


## Solatro's best round: read (value < 0) or saved.
func _solatro_best(value: int) -> int:
	var cfg := ConfigFile.new()
	cfg.load(LAYOUT_FILE)
	if value < 0:
		return int(cfg.get_value("solatro", "best_round", 0))
	cfg.set_value("solatro", "best_round", value)
	cfg.save(LAYOUT_FILE)
	return value


## Main menu table or New Run table (or neither), and the game's own menu panel hidden for both.
func _apply_menu_visibility() -> void:
	_board.hide_main_menu = _menu_on
	if _collection_open and not _menu_on:
		_close_collection() # (left the main menu)
	_main_menu.visible = _menu_on and not _new_run_open and not _stats_shown and not _collection_open # (the card stats' columns stand there)
	_new_run.visible = _menu_on and _new_run_open and not _stats_shown and not _collection_open
	if _collection != null:
		_collection.visible = _menu_on and _collection_open and not _stats_shown


## Something on the menu table was pressed. "QUIT ONLY VR" closes just this client (Balatro keeps
## running); "QUIT VR AND GAME" asks the game to quit too, then closes. PLAY opens the New Run
## table (the very first time the game's tutorial run starts instead).
func _on_menu_action(action: String) -> void:
	_buzz(0.5, 0.08)
	var setup = _state.get("menu", {}).get("setup") if _state.get("menu") is Dictionary else null
	if action == "play" and setup is Dictionary and setup.get("tutorial_done", false):
		_new_run_open = true
		_new_run.open()
		_apply_menu_visibility()
		return
	if action == "collection" and _vr: # COLLECTIONS AND STATS: the display cabinet on the table
		_open_collection()
		return
	if action == "youtube":
		_ach.add("vradar") # Subscribe to UnderTheVRadar
	match action:
		"solatro":
			_start_solatro()
		"quit_vr", "quit_both":
			if _session_blind_won:
				_ach.add("safe_travels") # a blind won in this session, then quit the proper way
			var farewell := _ach.reward("safe_travels")
			if farewell:
				_safe_travels_farewell() # Jimbo waves, "Safe Travels", the view fades out
			var wait := 3.2 if farewell else 0.0
			get_tree().create_timer(wait).timeout.connect(func():
				if action == "quit_both":
					_send({"cmd": "menu", "action": "quit_game"})
					get_tree().create_timer(0.5).timeout.connect(func(): get_tree().quit()) # (time for the message to leave)
				else:
					get_tree().quit())
		_:
			_send({"cmd": "menu", "action": action})


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
	if _counter != null and _counter.has_item(owner_id): # an item on the shop counter: above it
		return _counter.tip_anchor(owner_id)
	var card = _hand_cards.get(owner_id)
	if card == null or not is_instance_valid(card):
		return null
	return card.get_node("TipAnchor")


## Both controllers report here; what a button does depends on the controller's role:
## the pointing hand (beam, clicks, gestures) or the card hand (holds the fan).
func _on_button(button_name: String, controller: XRController3D) -> void:
	if button_name == "trigger_click" and _measure_step >= 0 and controller == _point:
		_measure_point() # measuring the real table
		return
	if button_name == "trigger_click" and _photo != null and _photo.holds(controller):
		_photo.take_photo() # the trigger of the hand holding the camera takes the photo
		_buzz_hand(controller, 0.6, 0.06)
		return
	# the VR menu: X on the card hand's controller (A in left-handed mode) - under SteamVR the menu
	# button opens SteamVR's own dashboard; the menu button still works where it reaches the game
	if button_name == "menu_button" or (button_name == "ax_button" and controller == _holder):
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
			_press_target({"id": _hover_id, "kind": _hover_kind, "area": _hover_area, "body": _hover_body})
		"grip_click":
			if not _grip_table(_point): # pack, lever, consumable or joker within reach win over the hand cards
				_try_grab()
		"ax_button":
			_ach.reset("card_sharp") # (played with the button: the streak starts again)
			_jimbo_play()
			_send({"cmd": "play"})
		"by_button":
			_jimbo_discard() # (before sending: Solatro answers at once and the count would already be down)
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
		"primary_click":
			if not _calibrating:
				_toggle_sort() # stick click on the card hand
				_ach.add("shuffle_master")
				if _ach.reward("shuffle_master") and _fan_anchor != null:
					_gold_burst(_fan_anchor.global_position, 30)


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

	body.add_child(_card_core(Vector2(CARD_SIZE.x, CARD_SIZE.y), HAND_CARD_DEPTH)) # the card's edge, seen from the side

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
	var surface := HAND_CARD_DEPTH / 2 + 0.0002 # (the art lies right on the card stock)
	var layers := CardArt.card_layers(it)
	var has_art := not layers.is_empty()
	CardArt.apply_layers(body, layers, size, surface)
	var back := CardArt.material(it.get("ba"), it.get("bp"))
	CardArt.apply_layers(body.get_node("BackSide"), [back] if back != null else [], size, surface, 0.0004, 1)

	_sparkle(body, _ach != null and _ach.reward("glass_cannon") and str(it.get("key", "")) == "m_glass")
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
	var by_box := false
	if _chip.visible and pos.distance_to(_chip.global_position) < CHIP_HIT_RADIUS:
		sent = "play"
	elif _is_behind_shoulder(pos):
		sent = "discard"
	elif _coin_slot.is_visible_in_tree() and pos.distance_to(_coin_slot.global_position) < SLOT_RADIUS:
		sent = "discard" # into the SELL / DISCARD box
		by_box = true
	if sent == "":
		_return_grabbed_cards()
		return
	if sent == "discard" and int(_state.get("round", {}).get("discards_left", 1)) <= 0:
		# no discards left: the game would refuse them – straight back into the hand, and say why
		_return_grabbed_cards()
		_rack_hint(_fan_anchor, "0 Discards remaining")
		_buzz_hand(_point, 0.3, 0.15)
		return
	if sent == "discard":
		if by_box:
			_jimbo.react("square_hole", 0.3) # now and then
		_jimbo_discard() # (before sending, see above)
	_send({"cmd": sent})
	if sent == "play":
		_jimbo_play()
		_ach.add("card_sharp") # played by grabbing the cards
		if _ach.reward("card_sharp"):
			_gold_burst(_chip.global_position, 50)
	if sent == "discard" and not by_box: # (over the shoulder, not into the box)
		_ach.add("over_shoulder", _grabbed.size())
		if _ach.reward("over_shoulder"):
			for id in _grabbed:
				if _hand_cards.has(id) and is_instance_valid(_hand_cards[id]):
					_spark_trail(_hand_cards[id])
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
	"Spieltafel": "Game Board", "Blind-Chip": "Blind Chip", "Score-Turm": "Score Tower", "Joker-Tafel": "Joker Board",
	"Kartenstapel": "Deck", "Geldstapel": "Money","Kartenfächer": "Card Fan", "Gegriffene Karten": "Grabbed Cards",
	"Run-Panel": "Run Panel", "Shop": "Shop", "Reroll-Automat": "Reroll Machine", "Münzschlitz": "Coin Slot", "Kartentasche": "Card Stand", "Ladentheke": "Shop Counter",
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
		item.get_node("CalibHandle").visible = on and not item.has_meta("no_handle")
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
		_score_tower.visible = true
		_deck.visible = true
		_coins.visible = true
		_joker_table.visible = true
		if _shop_machine != null:
			_shop_machine.visible = true
		if _vr:
			_counter.visible = true
		_set_status("Calibration active")
	else:
		_save_layout()
		_chip.visible = false
		_score_tower.visible = false
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
		_try_grab_board_item(hand) # deck, money, coin slot, card stand: gripped directly, no handle
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
	var before := Transform3D(node.global_basis.orthonormalized(), node.global_position)
	node.global_transform = Transform3D(t.basis * Basis.from_scale(Vector3.ONE * _calib_scale), t.origin)
	if _calib_grabbed == "Joker-Tafel": # it stands upright, turned only around the vertical (the shop / play stand
		# and the reroll machine turn every way)
		_keep_level(node)
		# everything else of the table goes along (moved and turned the same way, not resized): the
		# game board, the blind chip, the score tower, the play stand, the shop and its machine - and
		# the casino table under it all follows the board anyway (_table_frame)
		var after := Transform3D(node.global_basis.orthonormalized(), node.global_position)
		var moved := after * before.affine_inverse()
		for label in _calib_items:
			var other: Node3D = _calib_items[label]
			if label == "Joker-Tafel" or _calib_on_table.has(label) or label in ["Kartenfächer", "Gegriffene Karten"] 					or node.is_ancestor_of(other):
				continue
			other.global_transform = moved * other.global_transform
	elif _calib_grabbed in TABLE_SNAP_ITEMS:
		_snap_to_table(node, _calib_hand)
	if on_table:
		_keep_on_joker_table(node)


## Play stand, shop counter and reroll machine can be tilted every way, but brought close to the
## table's height they click onto it: standing straight on the surface, keeping only their turn
## around the vertical (a little buzz when they click in) - easy to get them level again.
const TABLE_SNAP_ITEMS := ["Play Stand", "Ladentheke", "Reroll-Automat"]
const TABLE_SNAP_DIST := 0.04


func _snap_to_table(node: Node3D, hand: XRController3D) -> void:
	var surface := _table_surface_y()
	var on := absf(node.global_position.y - surface) < TABLE_SNAP_DIST
	if on != bool(node.get_meta("snapped", false)):
		node.set_meta("snapped", on)
		if on:
			_buzz_hand(hand, 0.35, 0.05)
	if not on:
		return
	var up := _joker_table.global_basis.y.normalized()
	var fwd := node.global_basis.z - up * node.global_basis.z.dot(up)
	if fwd.length() < 0.01: # (lying on its back: face the way the joker board faces)
		fwd = _joker_table.global_basis.z
	var b := Basis.looking_at(-fwd.normalized(), up).scaled(node.global_basis.get_scale())
	node.global_transform = Transform3D(b, Vector3(node.global_position.x, surface, node.global_position.z))


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
	_load_floor() # each mode has its own casino floor height
	_send_flags()
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
		_wrist.setup(([
			# left: you and your room (layout, height, hands, looks, sound)
			{"col": 0, "label": func(): return "Adjust VR Layout", "action": func():
				_wrist.visible = false
				_set_calibrating(true)},
			{"col": 0, "label": func(): return "Recenter", "action": func(): _place_layout()},
			{"col": 0, "label": func(): return "Floor: %+d cm" % int(round(_floor_cm)), "action": func(): pass,
				"minus": func():
					_set_floor(_floor_cm - 5.0)
					_send_flags(),
				"plus": func():
					_set_floor(_floor_cm + 5.0)
					_send_flags()},
			{"col": 0, "label": func(): return "Mode: " + ("Standing" if _standing else "Sitting"), "action": func(): _set_standing(not _standing)},
			{"col": 0, "label": func(): return "Switch Hands", "action": func(): _set_left_handed(not _left_handed)},
			{"col": 0, "label": func(): return "Background: " + ["Green", "Dark", "Casino"][_backdrop], "action": func(): _next_backdrop()},
			{"col": 0, "label": func(): return "Calm Lights: " + ("On" if _calm else "Off"), "action": func(): _set_calm(not _calm)},
			{"col": 0, "label": func(): return "Casino Sounds: " + ("On" if _ambience_on else "Off"), "action": func(): _set_ambience(not _ambience_on)},
			# right: the game (its Run Info and Options in their colours from the game), help, extras
			{"col": 1, "colour": Color(0.996, 0.373, 0.333), "label": func(): return "Run Info", "action": func(): # (the run panel's buttons: not shown in VR)
				_wrist.visible = false
				_send({"cmd": "game_menu", "action": "run_info"})},
			{"col": 1, "colour": Color(0.992, 0.635, 0.0), "label": func(): return "Game Options", "action": func():
				_wrist.visible = false
				_send({"cmd": "game_menu", "action": "options"})},
			{"col": 1, "label": func(): return "How To Play", "action": func():
				_wrist.visible = false
				_show_tutorial()},
			{"col": 1, "label": func(): return "Achievements  %d / %d" % [_ach.done_count(), Achievements.LIST.size()], "action": func():
				_wrist.visible = false
				_open_achievements()},
			{"col": 1, "label": func(): return "Photo Camera: " + ("On" if _photo != null and _photo.visible else "Off"), "action": func(): _toggle_photo()},
			{"col": 1, "label": func(): return "Spectator: " + Spectator.NAMES[_spectator.mode], "action": func(): _spectator.next_mode()},
			{"col": 1, "label": func(): return "Hands: " + ("On" if _hands_on else "Off"), "action": func(): _set_hands(not _hands_on)},
			{"col": 1, "label": func(): return "Jimbo: " + ("On" if _jimbo_on else "Off"), "action": func(): _set_jimbo(not _jimbo_on)},
			{"col": 1, "label": func(): return "Wheel of Fortune: " + _wheel_mode, "action": func():
				_set_wheel(WHEEL_MODES[(WHEEL_MODES.find(_wheel_mode) + 1) % WHEEL_MODES.size()])},
			{"col": 0, "label": func(): return "Test: Joker Gallery " + ("On" if _test.gallery_on() else "Off"), "action": func():
				_test.set_gallery(not _test.gallery_on()), "test": true},
			{"col": 0, "label": func(): return "Boss: " + _test.boss_name(), "action": func(): _step_test_boss(1),
				"minus": func(): _step_test_boss(-1), "plus": func(): _step_test_boss(1), "test": true},
			{"label": func(): return "Close", "action": func(): _wrist.visible = false},
		] as Array).filter(func(e): return TEST_TOOLS or not e.get("test", false)))
		_wrist.visible = false
	_place_wrist_menu()
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
		_hand_start = int(_left_handed) # ("Ambidextrous": the hands switched from how they started)
		_calm = cfg.get_value("settings", "calm_lights", false)
		_hands_on = cfg.get_value("settings", "hands", true)
		_ambience_on = cfg.get_value("settings", "casino_sounds", true)
		_jimbo_on = cfg.get_value("settings", "jimbo", true)
		# (a real table measured earlier is no longer applied: "Measure Real Table" left the VR menu)
		_wheel_mode = str(cfg.get_value("settings", "wheel_mode", "Real"))
		if not WHEEL_MODES.has(_wheel_mode):
			_wheel_mode = "Real"
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
	_load_floor()


## The casino floor height (slider "VR: Casino Floor Height" in the game's VR Settings), in cm. Kept
## separately for sitting and standing: the headset's floor can be off in one mode but not the other.
var _floor_cm := 0.0


func _floor_key() -> String:
	return "floor_cm_standing" if _standing else "floor_cm"


func _load_floor() -> void:
	var cfg := ConfigFile.new()
	_floor_cm = float(cfg.get_value("settings", _floor_key(), 0.0)) if cfg.load(LAYOUT_FILE) == OK else 0.0
	_casino.set_floor(_floor_cm / 100.0)


func _set_floor(cm: float) -> void:
	var before := _floor_cm
	_floor_cm = clampf(cm, -60.0, 60.0)
	if _ach != null:
		if _floor_cm >= 60.0:
			_ach.add_once("going_up", "top") # "Going Up!": all the way up ...
		elif _floor_cm <= -60.0:
			_ach.add_once("going_up", "bottom") # ... and all the way down
		var now := Time.get_ticks_msec() / 1000.0
		if _ach.reward("going_up") and not is_equal_approx(before, _floor_cm) and now - _floor_ding_at > 0.6:
			_floor_ding_at = now # (a slider drag dings once, not at every step)
			_play_ding()
	_casino.set_floor(_floor_cm / 100.0)
	var cfg := ConfigFile.new()
	cfg.load(LAYOUT_FILE)
	cfg.set_value("settings", _floor_key(), _floor_cm)
	cfg.save(LAYOUT_FILE)


## Jimbo's tips: on the very first start in VR, and from the game's Options menu ("VR: How To Play").
## The texts name the buttons of the current hand mode.
func _show_tutorial() -> void:
	if not _vr:
		return
	if _first_hint != null and is_instance_valid(_first_hint):
		_first_hint.queue_free() # found them
	var point := "left" if _left_handed else "right"
	var cards := "right" if _left_handed else "left"
	var play := "X" if _left_handed else "A"
	var discard := "Y" if _left_handed else "B"
	var recenter := "B" if _left_handed else "Y"
	var pages := [
		["Hi, my name is Alex and welcome to UnderTheVRadar's Balatro in VR mod!", "Once a round starts, your cards are in your %s hand. Point at them with your %s hand and pull the trigger to select them - just like clicking. Press the thumbstick of your %s hand to sort them by rank or by suit." % [cards, point, cards]],
		["Play & discard", "Grab the selected cards with your %s grip and let go over the golden blind chip to play them (or press %s). Throw them over your shoulder to discard (or press %s)." % [point, play, discard]],
		["Your table", "Jokers stand on the board: touch one to read it, grab it to move it - left to right is their order. Drop one into the SELL / DISCARD box to sell it - the box lights up when letting go would sell. Cards you grabbed from your hand and let go over the box are discarded. Lift it and look underneath for its price. In the shop, take what you want off the sales counter and pull it towards you to buy it; pull the slot machine's lever to reroll."],
		["Packs & cards", "Booster packs float up to you: grab them with both hands and tear them open (or point and pull the trigger). Tarot and planet cards stand in the card stand - point at one and pull the trigger to use it."],
		["The deck", "Hold your hand over the 3D deck on the table: it shows which cards are still left in it. Take your hand away and the view closes again."],
		["Put things where you like", "Everything can be moved: X on your card hand's controller (A when left-handed) opens the VR menu, then Adjust VR Layout. Grab an orange handle with the grip and move, turn or resize the game board, run panel, shop, joker board, deck, money, slot machine, coin slot, card stand, blind chip and your card fan. Press X (A) again to save. Sitting and standing each keep their own layout."],
		["Make it yours", "The VR menu (X / A) also has the background, Calm Lights, sounds, the spectator camera and this How To Play. %s brings everything in front of you. Have fun!" % [recenter]],
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
# ---------------------------------------------------------------- VR achievements

func _open_achievements() -> void:
	if _ach_menu == null:
		_ach_menu = AchievementsMenu.new()
		_ach_menu.ach = _ach
		_ach_menu.back = func(): _toggle_wrist_menu()
		add_child(_ach_menu)
	var side := -1.0 if _left_handed else 1.0
	var fan_plane := Basis(Vector3.RIGHT, deg_to_rad(FAN_TILT))
	_ach_menu.hand = _fan_anchor
	# beside the card hand, not over it: the glove that holds the cards mustn't cover the text
	_ach_menu.offset = Transform3D(fan_plane, fan_plane * Vector3(side * 0.22, 0.38, 0.02))
	_ach_menu.open()


## An achievement was unlocked: a golden plaque rises in front of you (several: one after another).
func _on_achievement(id: String) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var wait := maxf(_ach_next_popup - now, 0.0)
	_ach_next_popup = now + wait + 4.6
	if wait > 0.0:
		get_tree().create_timer(wait).timeout.connect(_show_plaque.bind(id))
	else:
		_show_plaque(id)


func _show_plaque(id: String) -> void:
	var a := Achievements.info(id)
	var plaque := Node3D.new()
	add_child(plaque)
	var looker: Node3D = _head if _vr else _camera
	var fwd := -looker.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	plaque.global_transform = Transform3D(Basis.looking_at(fwd), _eyes() + fwd * 0.7 + Vector3(0, -0.12, 0))
	var lines := [["ACHIEVEMENT UNLOCKED", 30, Color(1.0, 0.8, 0.3), 0.045], [str(a.get("name", id)), 56, Color(1, 1, 1), 0.0],
		["Reward: " + str(a.get("reward", "")), 26, Color(1.0, 0.85, 0.5), -0.042],
		["(switch it on or off: menu -> Achievements)", 20, Color(0.8, 0.75, 0.8), -0.066]]
	var panel := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.42, 0.16, 0.006)
	panel.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.16, 0.06, 0.14, 0.92)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.render_priority = 30
	panel.material_override = mat
	panel.position.y = -0.01
	plaque.add_child(panel)
	for l in lines:
		var label := Label3D.new()
		label.text = l[0]
		label.font_size = l[1]
		label.pixel_size = 0.0006
		label.modulate = l[2]
		label.outline_size = 0
		label.no_depth_test = true
		label.render_priority = 31
		label.position = Vector3(0, l[3], 0.005)
		plaque.add_child(label)
	GameFont.apply_to(plaque)
	plaque.scale = Vector3.ONE * 0.2
	var tw := create_tween()
	tw.tween_property(plaque, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(3.5)
	tw.tween_property(plaque, "position", plaque.position + Vector3(0, 0.15, 0), 0.6)
	tw.parallel().tween_property(plaque, "scale", Vector3.ONE * 0.01, 0.6)
	tw.tween_callback(plaque.queue_free)
	if _vr:
		_buzz_hand(_left, 0.6, 0.2)
		_buzz_hand(_right, 0.6, 0.2)
	if _wrist != null:
		_wrist.refresh()


## The rewards that are switched on (and the normal look for the others).
func _apply_rewards() -> void:
	if _ach == null:
		return
	_casino.set_vip(_ach.reward("welcome"))
	# table felts (only one of them is on at a time, see Achievements group "felt")
	if _ach.reward("neat_freak"):
		_casino.set_felt(Color(0.07, 0.17, 0.5)) # royal blue
	elif _ach.reward("high_roller"):
		_casino.set_felt(Color(0.32, 0.02, 0.045)) # royal red
	elif _ach.reward("nope_x5"):
		_casino.set_felt(Color(0.035, 0.035, 0.045)) # midnight black
	elif _ach.reward("giga_dweeb"):
		_casino.set_felt(Color(0.92, 0.42, 0.2), Color(0.04, 0.04, 0.06)) # TechDweeb's orange and black stripes
	elif _ach.reward("collector"):
		_casino.set_felt(_ach.metal("collector").darkened(0.47)) # the chosen colour (darker than the gold line on it)
	else:
		_casino.set_felt(CasinoRoom.FELT)
	var glove_style := "gold" if _ach.reward("pack_rat") else ("split" if _ach.reward("ambidextrous") else ("neon" if _ach.reward("hand_model") else "white"))
	for g in _gloves:
		if is_instance_valid(g):
			g.set_style(glove_style, _ach.metal("pack_rat"))
	if _beam != null: # "Laser Pointer": the beam's colour
		var beam_colour: Color = [Color(0.4, 0.8, 1.0), Color(1.0, 0.3, 0.75), Color(1.0, 0.78, 0.25), Color(0.35, 1.0, 0.45)][_ach.choice("laser_pointer") if _ach.is_done("laser_pointer") else 0]
		var bm := _beam.material_override as StandardMaterial3D
		bm.albedo_color = beam_colour
		bm.emission = beam_colour
	for inst in _jokers.values(): # "Price Check": golden price stickers
		if is_instance_valid(inst):
			_gild_sticker(inst)
	if _lever != null:
		_lever.set_metal(_ach.metal("one_armed"))
		_lever.rainbow = _ach.reward("lever_frenzy")
	_casino.set_summit_flag(_ach.reward("mountain"))
	_planets.set_trails(_ach.reward("planet_hopper"))
	if _collection != null:
		_collection.set_golden(_ach.reward("curator"), _ach.metal("curator"))
	if _solatro != null:
		_solatro.set_golden_bowl(_ach.reward("token_hoarder") and _ach.metal("token_hoarder").a > 0.0, _ach.metal("token_hoarder"))
	if _counter != null:
		_counter.sale = _ach.reward("bargain")
	_casino.set_reward_signs(_ach.reward("streamer"), _ach.reward("endless"))
	if _main_menu != null:
		_main_menu.set_safe_travels(_ach.reward("safe_travels"))
	_casino.set_star_ceiling(_ach.reward("stargazer"))
	_casino.set_wall_name(str(_ach.extra("profile_name")) if _ach.reward("vradar") and _ach.extra("profile_name") != null else "")
	_jimbo.set_goggles(_ach.reward("vradar"))
	_set_radar(_ach.reward("vradar"))
	_style_card_stand()
	if _deck_body != null: # the deck's gilded edges ("Peeking")
		var side: StandardMaterial3D = _deck_body.material_override
		var gilded: bool = _ach.reward("peeking")
		side.albedo_color = _ach.metal("peeking") if gilded else DECK_COLORS.get(str(_state.get("deck", {}).get("back_key", "")), Color(0.8, 0.2, 0.2))
		side.metallic = 0.4 if gilded else 0.0
	_counter.set_metal(_ach.metal("big_spender"))
	_counter.set_bell(_ach.reward("hands_on"))
	if _photo != null:
		_photo.polaroid = _ach.reward("say_cheese")
	_solatro.gold_cards = _ach.reward("royal")
	_update_boss_trophy()
	var body = (_coin_slot.get_meta("body_mat") if _coin_slot.has_meta("body_mat") else null) if _coin_slot != null else null
	if body is StandardMaterial3D:
		var gold: bool = _ach.reward("coin_slot")
		body.albedo_color = _ach.metal("coin_slot").darkened(0.1) if gold else Color(0.12, 0.1, 0.12)
		body.metallic = 0.85 if gold else 0.0
	_score_tower.set_style(_ach.reward("sky_high"), _ach.reward("close_call"))
	for inst in _jokers.values():
		if is_instance_valid(inst):
			_style_pedestal(inst)
	if _ach_menu != null and _ach_menu.visible:
		_ach_menu.open()


## A burst of gold glitter (rewards "Card Sharp": the played cards land, "Shuffle Master": sorting).
func _gold_burst(at: Vector3, amount: int) -> void:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = 0.7
	p.one_shot = true
	p.explosiveness = 0.9
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 0.15
	p.initial_velocity_max = 0.45
	p.gravity = Vector3(0, -0.8, 0)
	var dot := SphereMesh.new()
	dot.radius = 0.0025
	dot.height = 0.005
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(3.0, 2.2, 0.6)
	dot.material = glow
	p.mesh = dot
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 1))
	ramp.set_color(1, Color(1, 0.8, 0.3, 0))
	p.color_ramp = ramp
	add_child(p)
	p.global_position = at
	p.emitting = true
	get_tree().create_timer(1.5).timeout.connect(p.queue_free)


## "Standing Ovation" reward: a crowd claps when a run is won (made here: bursts of noise, one per
## clap, from a few dozen clappers that start, speed up and fade out).
func _play_applause() -> void:
	if _applause == null:
		const RATE := 22050
		const SECONDS := 4.0
		var n := int(RATE * SECONDS)
		var buf := PackedFloat32Array()
		buf.resize(n)
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		for clapper in 30:
			var t := rng.randf_range(0.0, 0.5)
			var pace := rng.randf_range(0.22, 0.32)
			var loud := rng.randf_range(0.3, 0.7)
			while t < SECONDS - 0.1:
				var fade := clampf((SECONDS - 0.4 - t) / 1.2, 0.0, 1.0) # the crowd calms down at the end
				var start := int(t * RATE)
				var length := int(0.018 * RATE)
				for k in length:
					if start + k < n:
						buf[start + k] += rng.randf_range(-1.0, 1.0) * loud * fade * exp(-k / (0.004 * RATE))
				t += pace * rng.randf_range(0.8, 1.2)
		var bytes := PackedByteArray()
		bytes.resize(n * 2)
		for i in n:
			bytes.encode_s16(i * 2, int(clampf(buf[i] * 0.18, -1.0, 1.0) * 32767.0))
		var wav := AudioStreamWAV.new()
		wav.format = AudioStreamWAV.FORMAT_16_BITS
		wav.mix_rate = RATE
		wav.data = bytes
		_applause = AudioStreamPlayer.new()
		_applause.stream = wav
		_applause.volume_db = -4.0
		add_child(_applause)
	_applause.play()


## "Boss Slayer" reward: the last boss chip beaten stands as a little trophy beside the deck.
func _update_boss_trophy() -> void:
	var trophy := _deck.get_node_or_null("BossTrophy") as Node3D
	var sprite = _ach.extra("boss_slayer")
	var on: bool = _ach.reward("boss_slayer") and sprite is Dictionary
	if not on:
		if trophy != null:
			trophy.visible = false
		return
	if trophy == null:
		trophy = Node3D.new()
		trophy.name = "BossTrophy"
		trophy.position = Vector3(0.075, 0, 0.0)
		_deck.add_child(trophy)
		var gold := StandardMaterial3D.new()
		gold.albedo_color = Color(0.9, 0.68, 0.25)
		gold.metallic = 0.85
		gold.roughness = 0.3
		var foot := MeshInstance3D.new()
		var fm := CylinderMesh.new()
		fm.top_radius = 0.016
		fm.bottom_radius = 0.02
		fm.height = 0.008
		foot.mesh = fm
		foot.position.y = 0.004
		foot.material_override = gold
		trophy.add_child(foot)
		var disc := MeshInstance3D.new()
		var dm := CylinderMesh.new()
		dm.top_radius = 0.022
		dm.bottom_radius = 0.022
		dm.height = 0.004
		disc.mesh = dm
		disc.rotation_degrees.x = 90.0
		disc.position.y = 0.032
		disc.material_override = gold
		trophy.add_child(disc)
		var face := Node3D.new()
		face.name = "Face"
		face.position = Vector3(0, 0.032, 0.0025)
		trophy.add_child(face)
	trophy.visible = true
	_set_sprite_face(trophy.get_node("Face"), sprite, Vector2.ONE * 0.042)


## Achievements that count time: "Streamer" (minutes with the spectator window on), and the
## "Ghost Hunter" reward (the Spectral Lounge haunts every half minute or so).
func _tick_achievements(delta: float) -> void:
	if _ach == null:
		return
	if _vr and _spectator != null and _spectator.mode != 0:
		_stream_secs += delta
		if _stream_secs >= 60.0:
			_stream_secs -= 60.0
			_ach.add("streamer")
	_tick_vr_handling(delta)
	_tick_jimbo(delta)
	if _ach.reward("ghost_hunter") and _casino.visible:
		_ghost_next -= delta
		if _ghost_next <= 0.0:
			_ghost_next = randf_range(25.0, 45.0)
			_casino.spectral_flicker()


## The VR-handling achievements that are watched every frame: "Price Check" (a lifted joker turned so
## that its underside faces you), "Up Close" (your head right next to a joker) and the rewards
## "Long Haul" (a glitter trail behind the carried joker) and "Up Close" (jokers look at you).
func _tick_vr_handling(delta: float) -> void:
	if _hand_start < 0:
		_hand_start = int(_left_handed)
	if not _vr:
		return
	var eyes := _eyes()
	var held = _jokers.get(_held_joker) if _held_joker >= 0 else null
	if held != null and is_instance_valid(held):
		_gild_sticker(held)
		var under: Vector3 = -(held as Node3D).global_basis.y.normalized()
		var to_eyes: Vector3 = (eyes - (held as Node3D).global_position).normalized()
		if under.dot(to_eyes) > 0.6 and _price_seen != _held_joker:
			_price_seen = _held_joker # (once per lift)
			_ach.add("price_check")
	elif _held_joker < 0:
		_price_seen = -1
	var glitter: bool = _ach.reward("long_haul")
	var look: bool = _ach.reward("up_close")
	for uid in _jokers:
		var inst = _jokers[uid]
		if not is_instance_valid(inst):
			continue
		var top: Vector3 = (inst as Node3D).global_position + (inst as Node3D).global_basis.y * 0.08
		var near := eyes.distance_to(top)
		if near < 0.15:
			_ach.add("up_close")
		# glitter behind the joker in the hand
		var trail := (inst as Node3D).get_node_or_null("Glitter") as CPUParticles3D
		var carried: bool = glitter and uid == _held_joker
		if carried and trail == null:
			trail = _glitter_trail()
			(inst as Node3D).add_child(trail)
		if trail != null:
			trail.emitting = carried
		# a joker you come close to turns its head (its model) to look at you
		var model = ((inst as Node3D).get_meta("model") if (inst as Node3D).has_meta("model") else null)
		if look and model is Node3D and is_instance_valid(model): # (only with the reward: models keep their own turn otherwise)
			var want := 0.0
			if look and near < 0.3 and uid != _held_joker:
				var d: Vector3 = (inst as Node3D).to_local(eyes)
				want = atan2(d.x, d.z)
			(model as Node3D).rotation.y = lerp_angle((model as Node3D).rotation.y, want, 1.0 - exp(-5.0 * delta))


func _glitter_trail() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Glitter"
	p.amount = 50
	p.lifetime = 0.8
	p.local_coords = false # (left behind where the joker was: a trail)
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 0.01
	p.initial_velocity_max = 0.05
	p.gravity = Vector3(0, -0.15, 0)
	p.position.y = 0.04
	var dot := SphereMesh.new()
	dot.radius = 0.0022
	dot.height = 0.0044
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.vertex_color_use_as_albedo = true
	dot.material = glow
	p.mesh = dot
	var ramp := Gradient.new()
	ramp.set_color(0, Color(2.5, 2.0, 0.8, 1))
	ramp.set_color(1, Color(1.0, 0.5, 1.5, 0))
	p.color_ramp = ramp
	p.emitting = false
	return p


## "Price Check" reward: the price sticker under a joker turns gold.
func _gild_sticker(inst: Node3D) -> void:
	var sticker := inst.get_node_or_null("PriceSticker")
	if sticker == null or sticker.get_child_count() == 0:
		return
	var paper := sticker.get_child(0) as MeshInstance3D
	var m := paper.material_override as StandardMaterial3D
	var gold: bool = _ach.reward("price_check")
	m.albedo_color = _ach.metal("price_check").lightened(0.1) if gold else Color(1.0, 0.62, 0.15)
	m.metallic = 0.7 if gold else 0.0
	m.roughness = 0.3 if gold else 0.8


## "Window Shopper" reward: a little shop bell ("ding") - made here from two ringing tones.
func _play_ding() -> void:
	if _ding == null:
		const RATE := 22050
		var n := int(RATE * 0.9)
		var bytes := PackedByteArray()
		bytes.resize(n * 2)
		for i in n:
			var t := float(i) / RATE
			var v := (sin(TAU * 1568.0 * t) * 0.6 + sin(TAU * 2349.0 * t) * 0.3 + sin(TAU * 3136.0 * t) * 0.1) * exp(-t * 5.0)
			v *= minf(t / 0.003, 1.0) # (no click at the start)
			bytes.encode_s16(i * 2, int(clampf(v * 0.5, -1.0, 1.0) * 32767.0))
		var wav := AudioStreamWAV.new()
		wav.format = AudioStreamWAV.FORMAT_16_BITS
		wav.mix_rate = RATE
		wav.data = bytes
		_ding = AudioStreamPlayer.new()
		_ding.stream = wav
		_ding.volume_db = -8.0
		add_child(_ding)
	_ding.play()


## Stats -> Card Stats in the game: its chart as columns in a half circle around you (CardStatsVR),
## placed where you stand when it opens, facing the way the layout faces.
func _update_card_stats(state: Dictionary) -> void:
	var info = state.get("card_stats")
	if not (_vr and info is Dictionary and not (info.get("cards", []) as Array).is_empty()):
		if _card_stats != null and _card_stats.visible:
			_card_stats.hide_stats()
		_set_stats_shown(false)
		return
	if _card_stats == null:
		_card_stats = CardStatsVR.new()
		add_child(_card_stats)
		_card_stats.pressed.connect(func(action: String, label: String):
			_buzz(0.3, 0.04)
			if _stats_from_collection and action in ["back", "close"]:
				_stats_from_collection = false # (opened from the collection: back to its cabinet)
				_send({"cmd": "card_stats", "action": "close"})
				_open_collection()
				return
			_send({"cmd": "card_stats", "action": action, "label": label}))
	if not _stats_shown:
		_set_stats_shown(true) # table, board and menu out of the way of the columns
		_card_stats.buttons_y = _eyes().y - (_casino.floor_y if _casino != null else 0.0) - 0.45
		var eye := _eyes()
		var fwd := -_layout.global_basis.z
		fwd.y = 0.0
		fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
		var floor_y := _casino.floor_y if _casino != null else 0.0
		_card_stats.global_transform = Transform3D(Basis.looking_at(fwd), Vector3(eye.x, floor_y, eye.z))
	_card_stats.show_stats(info)


var _stats_shown := false


func _set_stats_shown(on: bool) -> void:
	if on != _stats_shown:
		_stats_shown = on
		_show_for_stats(not on)


## The card stats' columns stand all around you: the game board, the table and what is on it step
## aside while they are shown (their own buttons switch the game's tabs).
func _show_for_stats(on: bool) -> void:
	_layout.visible = on
	if _casino != null:
		_casino._table.visible = on
		_casino._table_base.visible = on
	if on:
		_apply_menu_visibility()
	else:
		_main_menu.visible = false
		_new_run.visible = false


## A text box on screen (a seeded run's seed, a new profile's name): a keyboard pops up over the
## table. OK puts it away until the box is clicked again (or another one appears).
var _keyboard: KeyboardVR
var _keyboard_dismissed := false


func _update_keyboard(state: Dictionary) -> void:
	var box = state.get("text_input")
	if not (_vr and box is Dictionary):
		_keyboard_dismissed = false
		if _keyboard != null:
			_keyboard.visible = false
		return
	if bool(box.get("hooked", false)):
		_keyboard_dismissed = false # (the box was clicked: typing again)
	if _keyboard == null:
		_keyboard = KeyboardVR.new()
		add_child(_keyboard)
		_keyboard.typed.connect(func(k: String, caps: bool): _send({"cmd": "text_key", "key": k, "caps": caps}))
		_keyboard.done.connect(func():
			_keyboard_dismissed = true
			_keyboard.visible = false)
	_keyboard.visible = not _keyboard_dismissed
	if _keyboard.visible:
		_keyboard.global_transform = _table_top_xf() * Transform3D(Basis(), Vector3(0.0, 0.16, 0.1))
		_keyboard.show_box(box)


## COLLECTIONS AND STATS (VR main menu): the display cabinet with everything the game collects.
var _collection: CollectionVR
var _collection_open := false
var _stats_from_collection := false


func _open_collection() -> void:
	if _collection == null:
		_collection = CollectionVR.new()
		_collection.make_model = func(key: String):
			var scene := _joker_scene(key)
			if scene == null:
				return null
			return scene.instantiate()
		add_child(_collection)
		_collection.set_golden(_ach.reward("curator"), _ach.metal("curator"))
		_collection.looked.connect(func(key: String):
			if key != "":
				_ach.add_once("curator", key))
		_collection.request.connect(func(msg: Dictionary): _send(msg))
		_collection.closed.connect(_close_collection)
		_collection.stats.connect(func():
			_stats_from_collection = true
			_close_collection()
			_send({"cmd": "collection", "action": "stats"}))
	_collection.reset()
	_collection_open = true
	_board.visible = false # (the game's main menu panels: the cabinet stands there)
	_send({"cmd": "collection", "action": "open"})
	_apply_menu_visibility()


func _close_collection() -> void:
	if not _collection_open:
		return
	_collection_open = false
	_board.visible = true
	_apply_menu_visibility()


## Photo mode: the instant camera appears in front of you (or is put away again).
func _toggle_photo() -> void:
	if _photo == null:
		_photo = PhotoCamera.new()
		add_child(_photo)
		_photo.visible = false
		_photo.polaroid = _ach.reward("say_cheese")
		_photo.shot.connect(func(path: String):
			_set_status("Photo saved: " + path)
			if _vr and _has_joker("j_photograph"):
				_ach.add("say_cheese")
				_photo.polaroid = _ach.reward("say_cheese")
			_jimbo.react("photo", 0.8))
	_photo.visible = not _photo.visible
	if _photo.visible:
		var eye: Node3D = _head if _vr else _camera
		var fwd := -eye.global_basis.z
		fwd.y = 0.0
		fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
		# in front of you, its lens looking away from you (the live view on its back faces you)
		_photo.global_transform = Transform3D(Basis.looking_at(fwd), eye.global_position + fwd * 0.4 + Vector3(0, -0.2, 0))
	else:
		for h in [_left, _right]:
			if h != null:
				_photo.release(h)


# ---------------------------------------------------------------- mixed reality: the real table
# In passthrough (and with the Green background for Virtual Desktop) the joker board can sit exactly on your real table: VR menu -> Measure Real Table,
# then lay the controller on the left and on the right end of the table's front edge and pull the
# trigger each time. The board is put flat onto the table, its front edge along the real one, and
# soft shadows under jokers, deck, money and stands ground them on the real wood. Saved in tracking space (it is your room's table), applied again after every
# Recenter and every start in passthrough.

const MEASURE_CONTROLLER_HALF := 0.02  # the controller lying on the table: its centre is this high above it
var _real_table := Transform3D()     # +z towards you, the front edge along x, y = the tabletop
var _real_table_set := false
var _measure_step := -1              # 0: left end, 1: right end, -1: not measuring
var _measure_points: Array = []
var _measure_hint: Label3D


func _start_table_measure() -> void:
	if not _vr:
		return
	_measure_step = 0
	_measure_points.clear()
	if _measure_hint == null:
		_measure_hint = Label3D.new()
		_measure_hint.font_size = 40
		_measure_hint.pixel_size = 0.0006
		_measure_hint.outline_size = 10
		_measure_hint.modulate = Color(1.0, 0.85, 0.4)
		_measure_hint.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_measure_hint.no_depth_test = true
		_measure_hint.render_priority = 20
		_measure_hint.position = Vector3(0, 0.12, 0)
		GameFont.apply_to(_measure_hint)
	if _measure_hint.get_parent() != _point:
		if _measure_hint.get_parent() != null:
			_measure_hint.get_parent().remove_child(_measure_hint)
		_point.add_child(_measure_hint)
	_measure_hint.visible = true
	_measure_hint.text = "Lay this controller on the LEFT end\\nof your table's front edge\\nand pull the trigger"


## The trigger while measuring: one end of the front edge.
func _measure_point() -> void:
	_measure_points.append(_point.global_position - Vector3(0, MEASURE_CONTROLLER_HALF, 0))
	_buzz_hand(_point, 0.5, 0.08)
	_measure_step += 1
	if _measure_step == 1:
		_measure_hint.text = "Now the RIGHT end\\nof the front edge"
		return
	_measure_step = -1
	_measure_hint.visible = false
	_set_real_table(_measure_points[0], _measure_points[1])


func _set_real_table(left: Vector3, right: Vector3) -> void:
	var edge := right - left
	edge.y = 0.0
	if edge.length() < 0.1:
		_set_status("Measuring failed: the two points were too close together")
		return
	var x := edge.normalized()
	var z := x.cross(Vector3.UP).normalized() # +z: off the edge, towards the player ...
	var centre := (left + right) * 0.5
	centre.y = (left.y + right.y) * 0.5
	if (_eyes() - centre).dot(z) < 0.0: # ... unless the ends were taken the other way round
		x = -x
		z = -z
	_real_table = Transform3D(Basis(x, Vector3.UP, z), centre)
	_real_table_set = true
	var cfg := ConfigFile.new()
	cfg.load(LAYOUT_FILE)
	cfg.set_value("settings", "real_table", _real_table)
	cfg.save(LAYOUT_FILE)
	_apply_real_table()
	_set_status("Real table measured")


## The joker board onto the real table (front edges together), and soft shadows under the things
## standing on it. (The renderer can't draw real shadows on a see-through surface, so every joker,
## the deck, the money and the stands get a soft dark "blob" under them - like in many AR apps.)
func _apply_real_table() -> void:
	# the board onto the real table with the Green background (Virtual Desktop keys the green out);
	# the soft shadows are a test there: a dark patch on the green may not key out cleanly
	var on := _real_table_set and _backdrop == Backdrop.GREEN
	_set_blob_shadows(false) # (no shadow blobs: on the green they showed as dark green patches)
	if not on:
		return
	var s := _joker_table.global_basis.get_scale().x
	var front := (JOKER_TABLE_CENTER_Z + JOKER_TABLE_SIZE.y * 0.5) * s
	_joker_table.global_transform = Transform3D(_real_table.basis.scaled(Vector3.ONE * s),
			_real_table * Vector3(0, -JOKER_TABLE_TOP * s + 0.002, -front - 0.02))


var _blobs_on := false
var _blob_mat: StandardMaterial3D


## A soft round shadow under a thing (shown only in passthrough on a measured real table).
func _add_blob_shadow(parent: Node3D, radius: float, y := 0.0005) -> void:
	if _blob_mat == null:
		var n := 64
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		for py in n:
			for px in n:
				var d := Vector2(px - n * 0.5 + 0.5, py - n * 0.5 + 0.5).length() / (n * 0.5)
				var a := clampf(1.0 - d, 0.0, 1.0)
				img.set_pixel(px, py, Color(0, 0, 0, pow(a, 1.5) * 0.85))
		_blob_mat = StandardMaterial3D.new()
		_blob_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_blob_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_blob_mat.albedo_texture = ImageTexture.create_from_image(img)
		_blob_mat.render_priority = -1
	var blob := MeshInstance3D.new()
	blob.name = "Blob"
	var q := PlaneMesh.new()
	q.size = Vector2(radius * 2.0, radius * 2.0)
	blob.mesh = q
	blob.material_override = _blob_mat
	blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	blob.position.y = y
	blob.visible = _blobs_on
	blob.add_to_group("mr_blob")
	parent.add_child(blob)


func _set_blob_shadows(on: bool) -> void:
	if on and not _blobs_on and _deck.get_node_or_null("Blob") == null: # the first time: under the board items
		for entry in [[_deck, 0.09], [_coins, 0.08], [_coin_slot, 0.1], [_bag, 0.14], [_play_stand, 0.34]]:
			_add_blob_shadow(entry[0], entry[1])
	_blobs_on = on
	get_tree().call_group("mr_blob", "set", "visible", on)


## "UnderTheVRadar" reward: a little radar at the left front corner of the joker board, its blips
## are the jokers (and a booster pack that waits to be torn).
func _set_radar(on: bool) -> void:
	if on and _radar == null:
		_radar = RadarScreen.new()
		_radar.position = Vector3(-JOKER_TABLE_SIZE.x * 0.5 - 0.06, 0.0, JOKER_TABLE_CENTER_Z + JOKER_TABLE_SIZE.y * 0.5 - 0.04)
		_radar.rotation_degrees.y = 25.0 # turned a little towards you
		_radar.blips = func() -> Array:
			var out: Array = []
			var half := JOKER_TABLE_SIZE * 0.5
			for inst in _jokers.values():
				if is_instance_valid(inst) and inst.get_parent() == _joker_table:
					out.append(Vector2(inst.position.x / half.x, -(inst.position.z - JOKER_TABLE_CENTER_Z) / half.y))
			if _pack != null and is_instance_valid(_pack) and not _pack.is_ripped():
				var p := _joker_table.to_local(_pack.global_position)
				out.append(Vector2(p.x / half.x, -(p.z - JOKER_TABLE_CENTER_Z) / half.y))
			return out
		_joker_table.add_child(_radar)
	if _radar != null:
		_radar.visible = on


## "Fortune Teller" reward: the card stand's velvet and wood glow mystic purple.
func _style_card_stand() -> void:
	if _bag == null:
		return
	var on: bool = _ach.reward("fortune_teller")
	var felt = (_bag.get_meta("felt") if _bag.has_meta("felt") else null)
	var wood = (_bag.get_meta("wood") if _bag.has_meta("wood") else null)
	if felt is StandardMaterial3D:
		felt.albedo_color = Color(0.4, 0.1, 0.6) if on else Color(0.35, 0.05, 0.07)
		felt.emission_enabled = on
		felt.emission = Color(0.6, 0.2, 1.0)
		felt.emission_energy_multiplier = 0.8
	if wood is StandardMaterial3D:
		wood.emission_enabled = on
		wood.emission = Color(0.35, 0.1, 0.6)
		wood.emission_energy_multiplier = 0.25


## "Real Full House" reward: a soft cone of light from above onto each joker's pedestal.
func _pedestal_spot(holder: Node3D, on: bool) -> void:
	var spot := holder.get_node_or_null("Spot") as MeshInstance3D
	if not on:
		if spot != null:
			spot.visible = false
		return
	if spot == null:
		spot = MeshInstance3D.new()
		spot.name = "Spot"
		var cone := CylinderMesh.new()
		cone.top_radius = 0.008
		cone.bottom_radius = 0.05
		cone.height = 0.32
		cone.cap_top = false
		cone.cap_bottom = false
		spot.mesh = cone
		var light := StandardMaterial3D.new()
		light.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		light.albedo_color = Color(1.0, 0.92, 0.7, 0.13)
		light.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		light.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		light.cull_mode = BaseMaterial3D.CULL_DISABLED
		light.no_depth_test = false
		spot.material_override = light
		spot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		spot.position.y = 0.16
		holder.add_child(spot)
	spot.visible = true


## "Safe Travels" reward: quitting VR, Jimbo waves goodbye, the words "Safe Travels" glow in front of
## you and the view fades to black (UnderTheVRadar's farewell).
func _safe_travels_farewell() -> void:
	if _jimbo != null and _jimbo.visible:
		_jimbo.say("Safe Travels!")
		_jimbo.react("win") # (he cheers and waves)
	var eye: Node3D = _head if _vr else _camera
	var fwd := -eye.global_basis.z
	var words := Label3D.new()
	words.text = "Safe Travels"
	words.font_size = 120
	words.pixel_size = 0.0012
	words.modulate = Color(0.45, 2.0, 2.6)
	words.outline_size = 18
	words.outline_modulate = Color(0.05, 0.25, 0.35)
	words.no_depth_test = true
	words.render_priority = 50
	add_child(words)
	words.global_transform = Transform3D(Basis.looking_at(fwd), eye.global_position + fwd * 1.2)
	GameFont.apply_to(words)
	words.modulate.a = 0.0
	var fade := MeshInstance3D.new() # a black veil right in front of the eyes
	var q := QuadMesh.new()
	q.size = Vector2(2.0, 2.0)
	fade.mesh = q
	var black := StandardMaterial3D.new()
	black.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	black.albedo_color = Color(0, 0, 0, 0)
	black.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	black.no_depth_test = true
	black.render_priority = 25 # (under the achievement plaque and the words)
	fade.material_override = black
	eye.add_child(fade)
	fade.position = Vector3(0, 0, -0.3)
	var tw := create_tween()
	tw.tween_property(words, "modulate:a", 1.0, 0.6).set_delay(0.4)
	tw.parallel().tween_property(black, "albedo_color:a", 0.85, 2.4).set_delay(0.6)


## Jimbo comments now and then: on discards, the hand you play, a long think ...
var _jimbo_idle := 0.0
var _jimbo_money_said := false


func _jimbo_discard() -> void:
	_jimbo_idle = 0.0
	var left := int(_state.get("round", {}).get("discards_left", 0))
	if left <= 0:
		return # no discards left: nothing is thrown away, nothing to say
	if left == 1:
		_jimbo.react("last_discard", 0.8) # (this was the last one)
	else:
		_jimbo.react("discard", 0.35)


func _jimbo_play() -> void:
	_jimbo_idle = 0.0
	var hand = _state.get("round", {}).get("hand")
	var name := str(hand.get("name", "")).strip_edges() if hand is Dictionary else ""
	if name == "Five of a Kind" and _vr:
		_ach.add("five_kind")
		if _ach.reward("five_kind"):
			_five_flames()
	var rare := name in ["Four of a Kind", "Straight Flush", "Five of a Kind", "Flush House", "Flush Five"]
	_jimbo.react("hand_" + name, 0.9 if rare else 0.3)


func _tick_jimbo(delta: float) -> void:
	if _jimbo == null or not _jimbo.visible:
		return
	var name := str(_state.get("state_name", ""))
	if _state.get("in_run", false) and name == "SELECTING_HAND" and not _state.get("solatro", false):
		_jimbo_idle += delta
		if _jimbo_idle > 50.0: # a long think
			_jimbo_idle = 0.0
			_jimbo.react("idle", 0.7)
	else:
		_jimbo_idle = 0.0
	var dollars := int(_state.get("round", {}).get("dollars", 0))
	if _state.get("in_run", false) and not _state.get("solatro", false):
		if dollars >= 50 and not _jimbo_money_said:
			_jimbo_money_said = true
			_jimbo.react("money", 0.8)
		elif dollars < 25:
			_jimbo_money_said = false
		if dollars <= 0 and name == "SHOP" and _last_broke_said != _state.get("round", {}).get("ante", 0):
			_last_broke_said = _state.get("round", {}).get("ante", 0)
			_jimbo.react("broke", 0.6)
var _last_broke_said = -1


## "Over the Shoulder" reward: a thrown card leaves a trail of sparks for a moment.
func _spark_trail(card: Node3D) -> void:
	var sparks := CPUParticles3D.new()
	sparks.amount = 40
	sparks.lifetime = 0.6
	sparks.local_coords = false # (the sparks stay where the card was: a trail)
	sparks.direction = Vector3.UP
	sparks.spread = 180.0
	sparks.initial_velocity_min = 0.05
	sparks.initial_velocity_max = 0.2
	sparks.gravity = Vector3(0, -0.6, 0)
	sparks.scale_amount_min = 0.5
	sparks.scale_amount_max = 1.0
	var dot := SphereMesh.new()
	dot.radius = 0.003
	dot.height = 0.006
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(3.0, 1.8, 0.5)
	dot.material = glow
	sparks.mesh = dot
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 1))
	ramp.set_color(1, Color(1, 0.4, 0.1, 0))
	sparks.color_ramp = ramp
	card.add_child(sparks)
	sparks.emitting = true
	var sparks_ref: WeakRef = weakref(sparks) # (the card may be gone by then: discarded, played)
	get_tree().create_timer(1.2).timeout.connect(func():
		var sp = sparks_ref.get_ref()
		if sp != null:
			sp.emitting = false)


## Wood, or marble with the "Bowling Alley" reward.
func _style_pedestal(holder: Node3D) -> void:
	var base := holder.get_node_or_null("PedBase") as MeshInstance3D
	var top := holder.get_node_or_null("PedTop") as MeshInstance3D
	if base == null or top == null:
		return
	if _ach != null and _ach.reward("bowling"):
		if _marble == null:
			_marble = StandardMaterial3D.new()
			var noise := FastNoiseLite.new()
			noise.noise_type = FastNoiseLite.TYPE_CELLULAR
			noise.frequency = 0.06
			var tex := NoiseTexture2D.new()
			tex.noise = noise
			tex.width = 128
			tex.height = 128
			var ramp := Gradient.new()
			ramp.set_color(0, Color(0.55, 0.53, 0.56))
			ramp.set_color(1, Color(0.96, 0.95, 0.93))
			ramp.add_point(0.15, Color(0.93, 0.92, 0.9))
			tex.color_ramp = ramp
			_marble.albedo_texture = tex
			_marble.roughness = 0.12
		base.material_override = _marble
		top.material_override = _marble
	elif base.has_meta("wood"):
		base.material_override = base.get_meta("wood")
		top.material_override = top.get_meta("wood")
	_pedestal_spot(holder, _ach != null and _ach.reward("real_full_house"))
	if _ach != null:
		_gild_sticker(holder)


## "VR: Wheel of Fortune": Off (the card works at once, like in the game), Deterministic (the wheel
## shows what the game rolled) or Real (the wheel decides).
func _set_wheel(mode: String) -> void:
	_wheel_mode = mode
	var cfg := ConfigFile.new()
	cfg.load(LAYOUT_FILE)
	cfg.set_value("settings", "wheel_mode", mode)
	cfg.save(LAYOUT_FILE)
	_send_flags()
	_set_status("Wheel of Fortune: " + mode)


## The Wheel of Fortune card was used: a little wheel of fortune stands in front of you. The game
## waits until it has stopped. "chance": as many WIN! fields; "real": the wheel decides and the game
## follows it (wheel_done with "win"), otherwise "win" is what the game already rolled.
## The wheel's colours follow the achievements at once: a colour picked in the menu, or Lady Luck
## earned while the wheel turns. (A metal set to "Off" is transparent: then the wheel stays plain.)
func _sync_wheel_look() -> void:
	if _wheel == null or not is_instance_valid(_wheel):
		return
	var gold := _ach.reward("three_row") and _ach.metal("three_row").a > 0.0
	_wheel.set_look(_ach.reward("lady_luck"), gold, _ach.metal("three_row") if gold else Color(1.0, 0.76, 0.2))


func _show_wheel(data: Dictionary) -> void:
	if _wheel != null and is_instance_valid(_wheel):
		_wheel.queue_free()
	_wheel = WheelSpin.new()
	add_child(_wheel)
	_wheel.vegas = _ach.reward("lady_luck")
	_wheel.golden = _ach.reward("three_row") and _ach.metal("three_row").a > 0.0 # ("Off": plain)
	if _wheel.golden:
		_wheel.golden_colour = _ach.metal("three_row")
	_wheel.sparks = _ach.reward("spin_doctor")
	_wheel.spun.connect(func(speed: float):
		if speed >= SPIN_DOCTOR_SPEED:
			_ach.add("spin_doctor"))
	_wheel.setup(float(data.get("chance", 0.25)), bool(data.get("win", false)), bool(data.get("real", false)))
	_wheel.hands = [_left, _right] if _vr else []
	var eye: Node3D = _head if _vr else _camera
	var fwd := -eye.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var at := eye.global_position + fwd * 0.42 + Vector3(0, -0.18, 0)
	_wheel.global_transform = Transform3D(Basis.looking_at(fwd), at) # its face (+z) towards you
	_wheel.scale = Vector3.ONE * 0.01
	create_tween().tween_property(_wheel, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var wheel := _wheel
	_wheel.tick.connect(func():
		if wheel.last_hand is XRController3D:
			_buzz_hand(wheel.last_hand, 0.15, 0.015))
	_wheel.gripped.connect(func(hand: Node3D): # took hold of the rim
		if hand is XRController3D:
			_buzz_hand(hand, 0.35, 0.04))
	_wheel.landed.connect(func(win: bool):
		if win and wheel._real:
			_ach.add("lady_luck")
		_jimbo.react("wheel_win" if win else "wheel_nope", 0.8)
		if win: # NOPE! x5 in a row (any mode), WIN! x5 in all (Real)
			_ach.reset("nope_x5")
			if wheel._real:
				_ach.add("three_row")
		else:
			_ach.add("nope_x5")
			if _ach.reward("jokes_on_you"):
				_jimbo.react("laugh")
		if wheel.last_hand is XRController3D:
			_buzz_hand(wheel.last_hand, 0.7 if win else 0.3, 0.15)
		get_tree().create_timer(0.8).timeout.connect(func(): _send({"cmd": "wheel_done", "win": win})) # (Real: the game follows this)
		var wheel_ref: WeakRef = weakref(wheel) # (it may be gone by then: a new wheel replaced it)
		get_tree().create_timer(2.4).timeout.connect(func():
			var w = wheel_ref.get_ref()
			if w != null:
				var tw := create_tween()
				tw.tween_property(w, "scale", Vector3.ONE * 0.01, 0.3)
				tw.tween_callback(w.queue_free)))


## Test tools (TEST_TOOLS): the boss preview, one step forwards or back (Off between the last and first).
func _step_test_boss(dir: int) -> void:
	var n := TestTools.BOSSES.size()
	_test.boss_index = posmod(_test.boss_index + 1 + dir, n + 1) - 1
	_apply_test_boss()
	if _test.boss_index >= 0:
		_set_status("Boss preview: " + _test.boss_name())


func _apply_test_boss() -> void:
	if _test.boss_index >= 0:
		_casino.set_boss(_test.boss_key(), _test.boss_colour())
		_casino._boss_room.vessel_fill = 0.6 # (Violet Vessel: a half full chalice)
		_casino.set_mood(8 if _test.boss_key().begins_with("bl_final") else 4, true, _heat)
	else:
		_casino.set_boss(_boss_key, Color(1.0, 0.1, 0.1))
		_casino.set_mood(1, false, _heat)
		if not _state.is_empty():
			_apply_state(_state) # back to what the game says


## "VR: Jimbo": Jimbo at the casino table across from you, or not.
func _set_jimbo(on: bool) -> void:
	_jimbo_on = on
	_jimbo.visible = on and _backdrop == Backdrop.ROOM
	var cfg := ConfigFile.new()
	cfg.load(LAYOUT_FILE)
	cfg.set_value("settings", "jimbo", on)
	cfg.save(LAYOUT_FILE)
	_send_flags()
	_set_status("Jimbo on" if on else "Jimbo off")


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
		"spec": Spectator.NAMES[_spectator.mode] if _spectator != null else "Off", "amb": _ambience_on,
		"floor": _floor_cm, "wheel": _wheel_mode, "jimbo": _jimbo_on})


## "VR: Hands" in the game's Options menu: Jimbo's gloves on or off (then only the beam).
func _set_hands(on: bool) -> void:
	if not on and _state.get("in_run", false):
		_hands_off_played = true
	elif on and _hands_off_played:
		_ach.add("hand_model") # played without hands, then put them on again
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


## The VR menu sits fixed on the card hand, in the plane of the fan: 20 cm up and a few cm towards
## the middle of your body, so the hand (or Jimbo's glove) doesn't cover the buttons. It follows
## the fan, so in left-handed mode it is on the right hand (the menu button stays on the left).
func _place_wrist_menu() -> void:
	if _wrist == null or _fan_anchor == null:
		return
	var side := -1.0 if _left_handed else 1.0 # towards the middle of the body
	var fan_plane := Basis(Vector3.RIGHT, deg_to_rad(FAN_TILT))
	_wrist.hand = _fan_anchor
	_wrist.offset = Transform3D(fan_plane, fan_plane * Vector3(side * 0.17, 0.2, 0.02)) # (two columns wide: beside the hand)


## Gives the beam and the fan of cards to the right hands for the current mode.
func _apply_handedness() -> void:
	_update_calibration_help()
	if _solatro != null:
		_solatro.set_left_handed(_left_handed) # (HOW TO PLAY and EXIT swap sides)
	if _lever != null:
		_lever.set_mirrored(_left_handed) # the lever on the side of the pointing hand
		_place_shop_props()
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
	_place_wrist_menu() # the menu goes along with the fan, shifted to the other side
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
	var save_button := "X" if _left_handed else "A"
	var reset_button := "B" if _left_handed else "Y"
	_calib_help.text = "Adjust VR Layout (%s)\n" % ("left-handed" if _left_handed else "right-handed") \
		+ "Grip (%s controller) on an orange dot: move & rotate\n" % point_hand \
		+ "While holding, stick up/down: size\n" \
		+ "%s: save & exit   ·   %s: default layout" % [save_button, reset_button]


# ---------------------------------------------------------------- background / passthrough

func _available_backdrops() -> Array:
	var modes: Array = [] # (Virtual Desktop shows your room through the Green background - chroma key)
	modes.append(Backdrop.GREEN)
	modes.append(Backdrop.DARK)
	modes.append(Backdrop.ROOM)
	return modes


func _next_backdrop() -> void:
	var modes := _available_backdrops()
	var i := modes.find(_backdrop)
	_set_backdrop(modes[(i + 1) % modes.size()])


func _set_backdrop(mode: Backdrop) -> void:
	_backdrop = mode
	if mode != Backdrop.GREEN:
		_set_blob_shadows(false)
	var see_through := mode != Backdrop.ROOM
	_casino.visible = not see_through
	# the casino is lit by its own warm lamps; in passthrough the neutral light shows models best
	_sun.light_energy = 0.08 if not see_through else 1.0 # late at night: neon and the table lamp light the room
	_env.ambient_light_color = Color(0.2, 0.17, 0.26) if not see_through else Color(0.6, 0.6, 0.6)
	_board.set_backing_visible(false) # panels float freely in every mode; a green felt wall breaks the casino
	var flat := mode == Backdrop.GREEN or mode == Backdrop.DARK # plain backdrops: no casino, no glow
	_board.opaque_mode = flat
	CardArt.solid_debuff = flat # faded debuffed cards would mix with the flat colour
	if _vr and not _hand_items.is_empty():
		_rebuild_hand(_hand_items)
	_board.hide_dimmers = see_through
	_env.glow_enabled = not flat # bloom halos would tint the chroma-key green
	# the casino: smoky air that swallows the far corners, filmic colours with a bit more contrast
	# (passthrough and green stay neutral)
	_env.fog_enabled = mode == Backdrop.ROOM
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC if mode == Backdrop.ROOM else Environment.TONE_MAPPER_LINEAR
	_env.adjustment_enabled = mode == Backdrop.ROOM
	_jimbo.visible = mode == Backdrop.ROOM and _jimbo_on # Jimbo only sits at the virtual casino table (and can be sent away)
	_casino.ambience.set_active(mode == Backdrop.ROOM and _ambience_on) # the casino's slot machines, glasses, chips
	_set_room_reverb(mode == Backdrop.ROOM)
	_stars.set_hard_edges(flat)
	_confetti.set_hard_edges(flat)
	if not _last_scene.is_empty():
		_board.apply_scene(_last_scene) # redraw translucent panels for the new mode
	match mode:
		Backdrop.GREEN:
			# pure green for Virtual Desktop's chroma-key passthrough
			_apply_real_table.call_deferred()
			if _vr:
				_xr.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_OPAQUE
			get_viewport().transparent_bg = false
			_env.background_mode = Environment.BG_COLOR
			_env.background_color = Color(0, 1, 0)
			_set_status("Background: green (Virtual Desktop passthrough)")
		Backdrop.DARK:
			# a calm near-black backdrop: easy on the eyes for whoever watches the recording
			if _vr:
				_xr.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_OPAQUE
			get_viewport().transparent_bg = false
			_env.background_mode = Environment.BG_COLOR
			_env.background_color = Color(0.03, 0.03, 0.035)
			_set_status("Background: dark")
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
	_board.casino_skin = _vr
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
		_set_backdrop(Backdrop.ROOM) # always starts in the casino (passthrough / green / dark via the VR menu)
	else:
		_camera = Camera3D.new()
		add_child(_camera)
		_layout.position = Vector3(0, 1.2, 0)
		_camera.position = Vector3(0.25, 1.15, 1.9)
		_camera.look_at(Vector3(0.25, 0.85, 0.2))
		_set_backdrop(Backdrop.ROOM)

	_register_calibratable("Spieltafel", _board)
	_register_calibratable("Blind-Chip", _chip)
	_score_tower = ScoreTower.new() # the blind's score so far against its target, beside the chip
	_score_tower.name = "ScoreTower"
	_score_tower.position = SCORE_POS
	_score_tower.visible = false
	_layout.add_child(_score_tower)
	_register_calibratable("Score-Turm", _score_tower, false, 0.27) # handle above the gold ring
	# handle well above the mat: lower it onto the real table without the controller hitting the table
	_register_calibratable("Joker-Tafel", _joker_table, false, 0.25)
	_register_calibratable("Kartenstapel", _deck, true, 0.17) # handle above the "52 / 52" count
	_register_calibratable("Geldstapel", _coins, true)
	_register_calibratable("Münzschlitz", _coin_slot, true, 0.1)
	_register_calibratable("Kartentasche", _bag, true, 0.16) # handle above the cards in the stand
	# deck, money, coin slot and card stand are simply gripped and slid (always, also while calibrating):
	# they keep their saved place and the reset, but need no orange handle
	for node in [_deck, _coins, _coin_slot, _bag]:
		node.set_meta("no_handle", true)
	_register_calibratable("Play Stand", _play_stand, false, 0.12) # the stand the played cards lie on
	if _shop_machine != null:
		_register_calibratable("Reroll-Automat", _shop_machine, false, 0.42) # reroll machine and Next Round: anywhere
	if _vr:
		_register_calibratable("Ladentheke", _counter, false, 0.2) # the shop's sales counter: anywhere, any tilt
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
	# until the tips have been looked at once: a single line pointing to them (not the tips
	# themselves - on the first start nothing of the game is there yet that they talk about)
	var cfg := ConfigFile.new()
	cfg.load(LAYOUT_FILE)
	if _vr and not cfg.get_value("settings", "tutorial_done", false):
		_first_hint = Label3D.new()
		_first_hint.text = "First time? Check How To Play: X on your card hand's controller opens the VR menu,\nor Options → VR Settings → How To Play in Balatro"
		_first_hint.font_size = 40
		_first_hint.pixel_size = 0.0009
		_first_hint.outline_size = 10
		_first_hint.modulate = Color(1.0, 0.85, 0.4)
		_first_hint.position = Vector3(0, 0.43, 0.02) # just above the game board
		_layout.add_child(_first_hint)
		get_tree().create_timer(90.0).timeout.connect(func(): # don't nag for the whole session
			if is_instance_valid(_first_hint):
				_first_hint.queue_free())
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
	if _vr:
		hud.set_meta("no_handle", true) # (VR shows no run panel)

	# Shop on the table behind the joker board, leaning towards the player like a counter display
	var shop := Node3D.new()
	shop.name = "ShopAnchor"
	shop.position = SHOP_POS
	shop.rotation_degrees = Vector3(SHOP_TILT, 0, 0)
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
	# (in VR the shop is the sales counter, calibrated on its own - "Shop Counter")
	if not _vr:
		_register_calibratable("Shop", shop, false, -1.0,
				Vector3(0, SHOP_SIGN_DISTANCE, SHOP_SIGN_HEIGHT + SHOP_SIGN_SIZE.y * 0.5 + 0.03))


func _build_chip() -> void:
	_chip = Node3D.new()
	_chip.name = "BlindChip"
	_chip.position = CHIP_POS
	_chip.scale = Vector3.ONE * CHIP_SIZE
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
	_apply_real_table.call_deferred() # (passthrough: the board stays on your real table)


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
	_spectator.badge_hand = func(): return _holder # the LIVE badge sits on the card hand's wrist
	add_child(_spectator)

	# beam and fan get their hand in _apply_handedness()
	_fan_anchor = Node3D.new()
	_fan_anchor.name = "FanAnchor"
	_fan_anchor.position = HAND_OFFSET
	_build_hand_preview()
	_build_fan_glow()
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

const JOKER_ZONE_HALF := 0.44                   # jokers stand in the middle of the board, the ends hold the coin slot
const LEVER_POS := Vector3(0.43, JOKER_TABLE_TOP, 0.14)   # reroll machine without VR (front right of the board, clear of the card stand)
const SLOT_POS := Vector3(-0.385, JOKER_TABLE_TOP, 0.1)    # coin slot (other end)
const BAG_POS := Vector3(0.36, JOKER_TABLE_TOP, 0.18)    # the card stand with the consumables: front right, in front of the reroll
const BAG_TURN := -10.0                                    # machine and a little left of it (its price stays in view), turned to you
const BAG_SIZE := Vector3(0.2, 0.03, 0.07)    # the card stand: width, height, depth
const PLAY_ROW := Vector3(0.0, TABLE_Y + JOKER_TABLE_TOP, 0.3) # the played-cards stand (layout space): at the back of the joker board, on its surface
# the sales counter's default (layout space): closer, floating over the back of the joker board and
# leaning towards you - its cards within reach, the jokers below still in view
const SHOP_COUNTER_POS := Vector3(0.0, TABLE_Y + 0.25, 0.33)
const SHOP_COUNTER_TILT := 30.0
# the reroll machine's default: right of the joker board (left for left-handers), bigger, turned to you
const SHOP_MACHINE_POS := Vector3(0.52, TABLE_Y + JOKER_TABLE_TOP, 0.62)
const SHOP_MACHINE_TURN := -30.0
const SHOP_MACHINE_SIZE := 1.3
const PLAY_SPACING := 0.085
const PLAY_STAND_SIZE := Vector2(0.5, 0.13)     # width x depth of the slanted board
const PLAY_TILT := 35.0                         # degrees; the back edge is raised
const PLAY_STAND_LIFT := 0.05                   # height of its front edge above the table
const PLANET_CENTER := Vector3(0, 0.3, 1.0)     # layout space: about the player's head
const TABLE_CARD := Vector2(0.063, 0.088)
const HAND_CARD_DEPTH := 0.002    # card stock of the cards in your hand (they are bigger than real cards)
const TABLE_CARD_DEPTH := 0.0016   # card stock between front and back art (visible from the side)
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
var _counter: ShopCounter         # the shop as a sales counter on the table (VR)
var _next_round: Node3D          # the Next Round button above the reroll machine (VR)
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
	_main_menu = MainMenuVR.new() # the main menu on the casino table (VR only, see _apply_state)
	add_child(_main_menu)
	_main_menu.visible = false
	_main_menu.pressed.connect(_on_menu_action)
	_new_run = NewRunVR.new() # the "New Run" table after PLAY (VR only)
	_new_run.deck_colour = func(key: String) -> Color: return DECK_COLORS.get(key, Color(0.8, 0.2, 0.2))
	add_child(_new_run)
	_new_run.visible = false
	_new_run.start.connect(func(deck: String, stake: int):
		_buzz(0.6, 0.1)
		_send({"cmd": "menu", "action": "start", "deck": deck, "stake": stake}))
	_new_run.back.connect(func():
		_new_run_open = false
		_apply_menu_visibility())
	_new_run.more.connect(func(): # challenges and seeded runs: the game's own run setup panel on the board
		_new_run_open = false
		_apply_menu_visibility()
		_send({"cmd": "menu", "action": "play"}))
	_new_run.hint.connect(func(text: String, at: Node3D): _rack_hint(at, text))
	_new_run.ticked.connect(func(hand: Node3D): # a deck passes the front of the turntable
		if hand is XRController3D:
			_buzz_hand(hand, 0.18, 0.015))
	_ach = Achievements.new()
	add_child(_ach)
	_ach.unlocked.connect(_on_achievement)
	_ach.rewards_changed.connect(_apply_rewards)
	_apply_rewards.call_deferred()
	_test = TestTools.new() # (TEST_TOOLS: joker gallery and boss preview in the VR menu)
	_test.visible = false
	add_child(_test)
	_solatro = SolatroGame.new() # the solo card game from the menu table (VR only)
	add_child(_solatro)
	_solatro.publish.connect(_on_solatro_publish)
	_solatro.hint.connect(_solatro_hint)
	_solatro.scored.connect(func(text: String):
		_rack_hint(_play_stand, text)
		if text.begins_with("Royal Flush"):
			_ach.add("royal"))
	_solatro.double_joker.connect(func():
		_ach.add("jokes_on_you")
		if _ach.reward("jokes_on_you"):
			_jimbo.react("laugh"))
	_solatro.leave.connect(_leave_solatro)
	_solatro.clamp_board = _clamp_to_board
	_solatro.hoarded.connect(func(): _ach.add("token_hoarder"))
	_solatro.sfx.connect(_solatro_sound)
	_solatro.note_moved.connect(func(xf: Transform3D):
		var cfg := ConfigFile.new()
		cfg.load(LAYOUT_FILE)
		cfg.set_value("solatro", "note", xf)
		cfg.save(LAYOUT_FILE))
	_solatro.bowl_moved.connect(func(at: Vector3):
		var cfg := ConfigFile.new()
		cfg.load(LAYOUT_FILE)
		cfg.set_value("solatro", "bowl", at)
		cfg.save(LAYOUT_FILE))
	_lever = RerollLever.new()
	_joker_table.add_child(_lever)
	if _vr:
		_lever.hands = [_left, _right] # (the ball flashes when a hand reaches it)
	_lever.pulled.connect(_on_lever_pulled)
	_coin_slot = _make_coin_slot()
	_joker_table.add_child(_coin_slot)
	# right-handed defaults; left-handers get them mirrored (and both are calibratable)
	_lever.position = LEVER_POS
	_coin_slot.position = SLOT_POS
	_bag = _make_card_bag()
	_joker_table.add_child(_bag)
	_bag.position = BAG_POS
	_bag.rotation_degrees.y = BAG_TURN
	_play_stand = _make_play_stand()
	_layout.add_child(_play_stand)
	_play_stand.position = PLAY_ROW
	_play_stand.visible = false
	_counter = ShopCounter.new()
	_counter.make_card = _make_table_card
	_counter.apply_art = func(face: Node3D, it: Dictionary):
		CardArt.apply_layers(face, CardArt.card_layers(it), TABLE_CARD, 0.0003)
		_shape_card(face.get_parent(), str(it.get("key", "")), [])
		# the items stand small in the shop: the edition effect is turned up on them (own copy of the
		# material, so the same card on the table keeps its normal look)
		for child in face.get_children():
			var mi := child as MeshInstance3D
			if mi != null and mi.material_override is ShaderMaterial and (mi.material_override as ShaderMaterial).shader.code.find("strength") >= 0:
				var own := (mi.material_override as ShaderMaterial).duplicate() as ShaderMaterial
				own.set_shader_parameter("strength", 2.2)
				mi.material_override = own
	_layout.add_child(_counter)
	_counter.position = SHOP_COUNTER_POS
	_counter.rotation_degrees.x = SHOP_COUNTER_TILT
	_counter.visible = false
	_counter.buy.connect(func(uid: int):
		_count_bargain(uid)
		_send({"cmd": "buy", "target": uid}))
	_counter.buy_use.connect(func(uid: int):
		_count_bargain(uid)
		_send({"cmd": "buy", "target": uid, "use": true}))
	if _vr: # the shop is the counter (its own item); the reroll machine and Next Round
		# stand on their own, anywhere in the room ("Reroll Machine" in the layout)
		_shop_machine = Node3D.new()
		_shop_machine.name = "ShopMachine"
		_layout.add_child(_shop_machine)
		_shop_machine.position = SHOP_MACHINE_POS
		_shop_machine.rotation_degrees.y = SHOP_MACHINE_TURN
		_shop_machine.scale = Vector3.ONE * SHOP_MACHINE_SIZE
		_shop_machine.visible = false
		_lever.reparent(_shop_machine, false)
		_build_next_round_button()
		_shop_sign.reparent(_counter, false)
		_shop_sign.position = Vector3(0, ShopCounter.TOP * 0.45, ShopCounter.DEPTH * 0.5 + 0.012)
		_shop_sign.rotation_degrees = Vector3(-10, 0, 0)
		_shop_sign.scale = Vector3.ONE * 0.62
		_place_shop_props()
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
	_jimbo.position = JIMBO_SPOT + Vector3(0, TABLE_Y, 0) # across the table from you, on its far edge (a little to the right, clear of the board)
	_jimbo.look_at_target = _eyes
	_jimbo.visible = false


func _eyes() -> Vector3:
	return _head.global_position if _vr else _camera.global_position


## The reroll machine stands at the end of the shop counter on the side of your pointing hand,
## with the Next Round button above it (left-handed: the other end, lever mirrored).
func _place_shop_props() -> void:
	if _shop_machine == null or _lever.get_parent() != _shop_machine:
		return
	const MACHINE_SCALE := 1.6 # a bit taller than the counter (cabinet 0.116 -> 0.19): the lever is easy to reach
	var x := 0.0
	_lever.position = Vector3(x, 0.0, 0.0)
	_lever.rotation = Vector3.ZERO
	_lever.scale = Vector3.ONE * MACHINE_SCALE
	_lever.set_mirrored(_left_handed)
	_next_round.position = Vector3(x, 0.3, 0.0) # above the machine and its raised lever


## "Next Round" as a big red button above the reroll machine: point at it and pull the trigger.
func _build_next_round_button() -> void:
	_next_round = Node3D.new()
	_next_round.name = "NextRound"
	_shop_machine.add_child(_next_round)
	var box := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(0.12, 0.05, 0.025)
	box.mesh = b
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.9, 0.24, 0.2) # the game's red
	m.emission_enabled = true
	m.emission = Color(0.9, 0.24, 0.2) * 0.25
	box.material_override = m
	box.rotation_degrees.x = -15.0
	_next_round.add_child(box)
	var label := Label3D.new()
	label.text = "NEXT\nROUND"
	label.font_size = 40
	label.pixel_size = 0.00045
	label.outline_size = 0
	label.line_spacing = -6
	label.position = Vector3(0, 0.0, 0.0135)
	box.add_child(label)
	GameFont.apply_to(label)
	var body := StaticBody3D.new()
	body.set_meta("target_id", -50)
	body.set_meta("kind", "nextround")
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.12, 0.05, 0.03)
	shape.shape = bs
	body.add_child(shape)
	box.add_child(body)


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
	stand.set_meta("felt", felt) # (purple glow with the "Fortune Teller" reward)
	stand.set_meta("wood", wood)
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
	# on the lip's front: hands and discards left, in the game's blue and red
	for k in 2:
		var l := Label3D.new()
		l.name = "Hands" if k == 0 else "Discards"
		l.font_size = 52
		l.pixel_size = 0.00045
		l.outline_size = 10
		l.outline_modulate = Color(0.05, 0.03, 0.03)
		l.modulate = Color(0.3, 0.7, 1.0) if k == 0 else Color(1.0, 0.4, 0.35)
		# on the dark front of the stand, under the lip, facing you
		l.position = Vector3((-0.17 if k == 0 else 0.17), PLAY_STAND_LIFT * 0.5, PLAY_STAND_SIZE.y * cos(tilt) * 0.5 + 0.0012)
		stand.add_child(l)
	# between them: ante and round
	var ante := Label3D.new()
	ante.name = "Ante"
	ante.font_size = 34
	ante.pixel_size = 0.00045
	ante.outline_size = 10
	ante.outline_modulate = Color(0.05, 0.03, 0.03)
	ante.modulate = Color(1.0, 0.85, 0.45)
	ante.position = Vector3(0, PLAY_STAND_LIFT * 0.5, PLAY_STAND_SIZE.y * cos(tilt) * 0.5 + 0.0012)
	stand.add_child(ante)
	# at the back edge: a plaque with the boss blind's rule (only during a boss blind)
	var back_y := PLAY_STAND_LIFT + PLAY_STAND_SIZE.y * sin(tilt)
	var back_z := -PLAY_STAND_SIZE.y * cos(tilt) * 0.5
	var plaque := Node3D.new()
	plaque.name = "Boss"
	plaque.position = Vector3(0, back_y + 0.042, back_z - 0.004)
	plaque.visible = false
	stand.add_child(plaque)
	var rim := MeshInstance3D.new()
	var rim_mesh := BoxMesh.new()
	rim_mesh.size = Vector3(PLAY_STAND_SIZE.x - 0.02, 0.078, 0.006)
	rim.mesh = rim_mesh
	rim.name = "Rim"
	rim.material_override = StandardMaterial3D.new()
	plaque.add_child(rim)
	var plate := MeshInstance3D.new()
	var plate_mesh := BoxMesh.new()
	plate_mesh.size = Vector3(PLAY_STAND_SIZE.x - 0.03, 0.068, 0.008)
	plate.mesh = plate_mesh
	plate.material_override = _wood_material(Color(0.1, 0.06, 0.08))
	plaque.add_child(plate)
	for k in 2: # the boss's name (in its colour) and its rule
		var t := Label3D.new()
		t.name = "Name" if k == 0 else "Rule"
		t.font_size = 44 if k == 0 else 30
		t.pixel_size = 0.00045
		t.outline_size = 8
		t.outline_modulate = Color(0.05, 0.03, 0.03)
		t.modulate = Color(1, 1, 1) if k == 1 else Color(1, 0.6, 0.4)
		t.position = Vector3(0, 0.02 if k == 0 else -0.01, 0.0045)
		if k == 1:
			t.width = (PLAY_STAND_SIZE.x - 0.06) / t.pixel_size
			t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		plaque.add_child(t)
	# over it all: the hand's chips x mult, blue and red with the game's score flames
	var score := Node3D.new()
	score.name = "Score"
	score.position = Vector3(0, back_y + 0.14, back_z)
	score.visible = false
	stand.add_child(score)
	# in its place at Solatro's game over: how far you got
	var over := Label3D.new()
	over.name = "GameOver"
	over.font_size = 72
	over.pixel_size = 0.00045
	over.outline_size = 12
	over.outline_modulate = Color(0.05, 0.03, 0.06)
	over.modulate = Color(1.0, 0.35, 0.3)
	over.position = Vector3(0, back_y + 0.14, back_z)
	over.visible = false
	stand.add_child(over)
	for k in 2:
		var box := Node3D.new()
		box.name = "Chips" if k == 0 else "Mult"
		box.position.x = -0.065 if k == 0 else 0.065
		score.add_child(box)
		var flame := Board.make_flame()
		flame.scale = Vector3(0.12, 0.2, 1) # (rises well above the box, behind it)
		flame.position = Vector3(0, -0.023 + 0.1, -0.004)
		flame.visible = false
		box.add_child(flame)
		var panel := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(0.1, 0.046, 0.006)
		panel.mesh = pm
		var pmat := StandardMaterial3D.new()
		pmat.albedo_color = Color(0.0, 0.58, 1.0) if k == 0 else Color(1.0, 0.27, 0.27)
		pmat.emission_enabled = true
		pmat.emission = pmat.albedo_color
		pmat.emission_energy_multiplier = 0.25
		panel.material_override = pmat
		box.add_child(panel)
		var v := Label3D.new()
		v.name = "Value"
		v.font_size = 72
		v.pixel_size = 0.00045
		v.outline_size = 10
		v.outline_modulate = Color(0.05, 0.03, 0.06)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if k == 0 else HORIZONTAL_ALIGNMENT_LEFT
		v.position = Vector3(0.042 if k == 0 else -0.042, 0, 0.0035)
		box.add_child(v)
	var x := Label3D.new()
	x.text = "X"
	x.font_size = 64
	x.pixel_size = 0.00045
	x.outline_size = 10
	x.outline_modulate = Color(0.05, 0.03, 0.06)
	x.modulate = Color(1.0, 0.3, 0.3)
	x.position.z = 0.003
	score.add_child(x)
	return stand


## The play stand's information: ante and round, the boss's rule, the hand's chips x mult.
func _update_stand_info(state: Dictionary) -> void:
	if not _play_stand.has_node("Ante"):
		return
	var r: Dictionary = state.get("round", {})
	var in_round := bool(state.get("in_run", false)) and ROUND_STATES.has(str(state.get("state_name", "")))
	(_play_stand.get_node("Ante") as Label3D).text = "ANTE %d  ·  ROUND %d" % [int(r.get("ante", 0)), int(r.get("round", 0))]
	var blind: Dictionary = state.get("blind", {})
	var plaque := _play_stand.get_node("Boss") as Node3D
	plaque.visible = in_round and bool(blind.get("boss", false)) and str(blind.get("desc", "")) != ""
	if plaque.visible:
		var c: Color = Board.to_color(blind.get("colour")) if blind.get("colour") != null else Color(1, 0.5, 0.3)
		(plaque.get_node("Name") as Label3D).text = str(blind.get("name", "")).to_upper()
		(plaque.get_node("Name") as Label3D).modulate = c.lightened(0.25)
		(plaque.get_node("Rule") as Label3D).text = str(blind.get("desc", ""))
		var rim_mat := (plaque.get_node("Rim") as MeshInstance3D).material_override as StandardMaterial3D
		rim_mat.albedo_color = c
		rim_mat.emission_enabled = true
		rim_mat.emission = c
		rim_mat.emission_energy_multiplier = 0.4
	var hand = r.get("hand")
	var score := _play_stand.get_node("Score") as Node3D
	var solatro := bool(state.get("solatro", false)) # (Solatro scores in points, not chips x mult)
	score.visible = in_round and not solatro and hand is Dictionary and str(hand.get("name", "")).strip_edges() != ""
	if score.visible:
		for k in ["Chips", "Mult"]:
			var box := score.get_node(k) as Node3D
			(box.get_node("Value") as Label3D).text = str(hand.get("chips" if k == "Chips" else "mult", "0"))
			var f = hand.get("cf" if k == "Chips" else "mf")
			var flame := box.get_node("Flame") as MeshInstance3D
			flame.visible = f is Dictionary
			if f is Dictionary:
				Board.set_flame(flame, f, false, 0.0 if k == "Chips" else 0.5)
	var over := _play_stand.get_node_or_null("GameOver") as Label3D
	if over != null: # Solatro's game over, where chips x mult would be
		over.visible = solatro and str(state.get("state_name", "")) == "GAME_OVER"
		if over.visible:
			over.text = "GAME OVER - You Reached Round %d" % int(r.get("round", 0))


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
	slot.set_meta("body_mat", dark) # (golden with the "Coin Slot Regular" reward)
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
	label.text = "SELL /\nDISCARD"
	label.font_size = 30
	label.pixel_size = 0.0005
	label.modulate = Color(1.0, 0.85, 0.35)
	label.outline_size = 0
	label.position = Vector3(0, 0.025, 0.0305)
	slot.add_child(label)
	slot.set_meta("gold", gold)   # (lights up when letting go would sell, see _update_sell_glow)
	slot.set_meta("label", label)
	return slot


## A joker or card held over the coin slot lights it up and shows the price: let go now and it is
## sold. A short buzz when that starts, so a joker being moved around isn't sold by accident.
var _sell_armed := false
var _slot_solatro := false         # Solatro: the box is only a DISCARD box (nothing to sell)


func _slot_idle_text() -> String:
	return "DISCARD" if _slot_solatro else "SELL /\nDISCARD"


func _update_sell_glow() -> void:
	if _coin_slot == null or not _coin_slot.has_meta("gold"):
		return
	var armed := false
	var price := -1
	var hand: XRController3D = null
	var discard := false
	if _grab_active and not _grabbed.is_empty() and _coin_slot.is_visible_in_tree() 			and _point.global_position.distance_to(_coin_slot.global_position) < SLOT_RADIUS:
		armed = true # grabbed hand cards over the box: let go = discard them
		discard = true
		hand = _point
	elif _slot_solatro:
		pass # (Solatro: nothing to sell)
	elif _held_joker >= 0 and is_instance_valid(_jokers.get(_held_joker)):
		if (_jokers[_held_joker] as Node3D).global_position.distance_to(_coin_slot.global_position) < SLOT_RADIUS:
			armed = true
			hand = _held_hand
			for j in _state.get("jokers", []):
				if int(j.get("uid", -1)) == _held_joker:
					price = int(j.get("sell", -1))
	elif _held_consumable >= 0 and is_instance_valid(_consumables.get(_held_consumable)):
		var card: Node3D = _consumables[_held_consumable]
		if card.global_position.distance_to(_coin_slot.global_position) < SLOT_RADIUS and card.get_meta("can_sell", false):
			armed = true
			hand = _held_consumable_hand
			for c in _state.get("consumables", []): # its sell price, like a joker's
				if int(c.get("uid", -1)) == _held_consumable:
					price = int(c.get("sell", -1))
	var gold: StandardMaterial3D = _coin_slot.get_meta("gold")
	var label: Label3D = _coin_slot.get_meta("label")
	if armed:
		var t := Time.get_ticks_msec() / 1000.0
		gold.emission_energy_multiplier = 2.5 if _calm else 2.0 + 1.2 * sin(t * 10.0) # (Calm Lights: steady)
		if discard:
			label.text = "0 DISCARDS" if int(_state.get("round", {}).get("discards_left", 1)) <= 0 else "DISCARD!"
		else:
			label.text = "SELL $%d" % price if price >= 0 else "SELL!"
		label.modulate = Color(1.0, 1.0, 0.6)
		if not _sell_armed and hand != null:
			_buzz_hand(hand, 0.4, 0.06)
	elif _sell_armed:
		gold.emission_energy_multiplier = 0.2
		label.text = _slot_idle_text()
		label.modulate = Color(1.0, 0.85, 0.35)
	_sell_armed = armed


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
	_stand_on = _vr and in_run # the play stand stays on the table the whole run ...
	_shop_goal = 1.0 if (_vr and in_run and bool(state.get("shop_open", false))) else 0.0 # the counter: while the shop is open
	if _shop_machine != null:
		_shop_machine.visible = _shop_goal > 0.5 or _calibrating
	_update_stand_info(state)
	if _play_stand.has_node("Hands"):
		var r: Dictionary = state.get("round", {})
		(_play_stand.get_node("Hands") as Label3D).text = "HANDS  %d" % int(r.get("hands_left", 0))
		(_play_stand.get_node("Discards") as Label3D).text = "DISCARDS  %d" % int(r.get("discards_left", 0))

	_lever.set_shop(bool(state.get("shop_open", false)), bool(state.get("can_reroll", false)), int(state.get("reroll_cost", 0)))
	_planets.visible = in_run
	_planets.set_levels(state.get("hand_levels", []) if in_run else [])
	_planets.set_halved(in_run and _boss_key == "bl_flint") # The Flint: base chips and mult halved
	_planets.set_arm(in_run and _boss_key == "bl_arm") # The Arm: a level off the played hand, the planets hang lower
	if _vr and in_run and (state.get("hand_levels", []) as Array).size() >= 6:
		_ach.add("planet_hopper") # six planets in orbit at once
	_sync_consumables(state.get("consumables", []) if in_run else [])
	# a blind is being played: remember what it is (between the last hand and the round's evaluation
	# the game passes NEW_ROUND, so the step from playing to ROUND_EVAL is hardly ever direct)
	if in_run and ROUND_STATES.has(name):
		_round_live = true
		_round_blind = (state.get("blind", {}) as Dictionary).duplicate()
		_round_hands_left = int(state.get("round", {}).get("hands_left", 0))
	if name == "ROUND_EVAL" and _round_live: # the blind was beaten
		_round_live = false
		var won_boss := bool(_round_blind.get("boss", false))
		_defeat_chip(won_boss) # the chip cracks and bursts
		if not state.get("solatro", false):
			_session_blind_won = true # ("Safe Travels")
		if _vr and _hand_start >= 0 and int(_left_handed) != _hand_start and not state.get("solatro", false):
			_ach.add("ambidextrous") # a blind won with the hands switched
		if _vr and won_boss and not state.get("solatro", false):
			if _round_blind.get("sprite") is Dictionary: # (the trophy shows the last boss beaten)
				_ach.set_extra("boss_slayer", _round_blind["sprite"])
			_ach.add("boss_slayer")
		if _vr and not state.get("solatro", false):
			_blind_won_extras()
	elif not in_run or name in ["GAME_OVER", "SHOP", "BLIND_SELECT"]:
		_round_live = false # (lost, or the round left some other way)
	var round_info: Dictionary = state.get("round", {})
	_update_tension(state, in_run, name)
	if in_run and ROUND_STATES.has(name) and not ROUND_STATES.has(_last_state_name):
		_start_shuffle() # a new round begins: the deck is shuffled before the cards are drawn
		_round_hands_start = int(state.get("round", {}).get("hands_left", 0)) # ("Hot Streak")
		_last_play_glass = 0
	var dollars := int(round_info.get("dollars", 0))
	if in_run and _last_dollars > -999999 and dollars != _last_dollars:
		if dollars > _last_dollars:
			_coins.fly_in(_money_source(), dollars - _last_dollars)
		elif dollars >= 0:
			_coins.fly_out(_money_sink(state), _last_dollars - dollars)
	if in_run and name == "SHOP" and _last_dollars > -999999 and dollars < _last_dollars:
		_shop_spent += _last_dollars - dollars
		_ach.reach("big_spender", _shop_spent) # money spent in this shop
	elif name == "BLIND_SELECT" or not in_run:
		_shop_spent = 0
	_last_dollars = dollars if in_run else -999999
	var blind: Dictionary = state.get("blind", {})
	var ante := int(round_info.get("ante", 1)) if in_run else 1
	var boss_round := in_run and bool(blind.get("boss", false)) and ROUND_STATES.has(name)
	_casino.set_mood(ante, boss_round, _heat)
	# the boss blind changes the room: its chip's colour and its own effect (walls, eye, chains ...)
	var boss_was := _boss_key
	_boss_key = str(blind.get("key", "")) if boss_round else ""
	if _boss_key != "" and boss_was == "" and not state.get("solatro", false):
		_jimbo.react("boss", 0.9)
	if _test != null and _test.boss_index >= 0: # (the test tools' boss preview wins)
		_apply_test_boss()
	else:
		_casino.set_boss(_boss_key, Board.to_color(blind.get("colour")) if blind.get("colour") != null else Color(1.0, 0.1, 0.1))
	_casino.set_ante(ante, str(state.get("blind_on_deck", "")), in_run) # the Ante clock, "NOW SERVING"
	_casino.set_run_chips(float(round_info.get("run_chips", 0)) if in_run else 0.0) # the chip mountain
	if in_run and _vr and float(round_info.get("run_chips", 0)) >= pow(10.0, ChipMountain.LOG_TO):
		_ach.add("mountain") # the second mountain grows
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
	face.position.z = TABLE_CARD_DEPTH * 0.5 # (art on the front of the card body)
	card.add_child(face)
	card.add_child(_card_core(TABLE_CARD, TABLE_CARD_DEPTH))
	var back := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = TABLE_CARD
	back.mesh = quad
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.85, 0.27, 0.24)
	back.material_override = m
	back.name = "Back"
	back.rotation_degrees.y = 180
	back.position.z = -TABLE_CARD_DEPTH * 0.5 - 0.0003
	card.add_child(back)
	return card


## A card is a thin slab of card stock: its pictures lie on the front and back of this, so from the
## side it shows a pale edge instead of vanishing. A little smaller than the picture, so its square
## corners hide behind the picture's rounded ones.
## Jokers whose picture isn't a whole card (Half Joker is half a card, Wee Joker small, Square Joker
## square, Joker Stencil and Hanging Chad with a hole in them): no card body and no plain back around
## them, so they keep their own shape and you can look through their holes.
const SHAPED_JOKERS := ["j_half", "j_wee", "j_square", "j_photograph", "j_stencil", "j_hanging_chad"]


func _shape_card(card: Node, key: String, layers: Array) -> void:
	if card == null or not SHAPED_JOKERS.has(key):
		return # (a whole card: as it was built - packs and vouchers on the counter keep their body hidden)
	for n in ["Core", "Back"]:
		var part := card.get_node_or_null(n) as Node3D
		if part != null:
			part.visible = false
	# from behind it shows its own picture again (half a card has no card back)
	if not layers.is_empty() and card.get_node_or_null("BackArt") == null:
		var back_art := Node3D.new()
		back_art.name = "BackArt"
		back_art.rotation_degrees.y = 180.0
		back_art.position.z = -0.0006
		card.add_child(back_art)
	var ba := card.get_node_or_null("BackArt") as Node3D
	if ba != null and not layers.is_empty() and card.get_parent() is Node3D and card.name == "Card": # (the stand's card)
		CardArt.apply_layers(ba, layers, JOKER_CARD_SIZE, 0.0003)


func _card_core(size: Vector2, depth: float) -> MeshInstance3D:
	var core := MeshInstance3D.new()
	core.name = "Core"
	var box := BoxMesh.new()
	box.size = Vector3(size.x - 0.004, size.y - 0.004, depth)
	core.mesh = box
	if _card_stock == null:
		_card_stock = StandardMaterial3D.new()
		_card_stock.albedo_color = Color(0.93, 0.91, 0.86)
		_card_stock.roughness = 0.85
	core.material_override = _card_stock
	return core


## Cards in the game's play area lie on the table in front of you; they fly there from the fan.
func _sync_play_cards(items: Array) -> void:
	var played: Array = []
	for it in items:
		if it.get("k", "") == "c" and it.get("area", "") == "play":
			played.append(it)
	# "Glass Cannon": the glass cards of the hand as it was played - the most seen at once (after
	# scoring the cards leave one by one, and glass may break: the last look would count too few)
	if played.is_empty():
		_play_seen = false
	else:
		var glass := played.filter(func(c) -> bool: return str(c.get("key", "")) == "m_glass").size()
		_last_play_glass = glass if not _play_seen else maxi(_last_play_glass, glass)
		_play_seen = true
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
	var fx := ShatterFX.burst(self, node.global_transform, layers, size, false, 0.7)
	_jimbo.react("glass", 0.7)
	if _vr:
		_ach.add("glass_breaker")
	if _ach.reward("glass_breaker"): # the shards stay on the table until the run is over
		fx.settle_at(_table_surface_y() + 0.002)
		_glass_left.append(fx)
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
	if _ach.reward("pack_surgeon"):
		_pack.confetti = _pack_colours(str(ev.get("name", "")))
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
	_ach.add("pack_rat")
	if _pack != null and is_instance_valid(_pack) and _pack.pull_seconds() >= 3.0:
		_ach.add("pack_surgeon") # pulled apart slowly
	if _pack != null and is_instance_valid(_pack) and _pack.hand_count() >= 2:
		_ach.add("rip_it") # torn with both hands
		if _ach.reward("rip_it"):
			_confetti.burst(true, 1.2)
	_buzz_hand(_point, 1.0, 0.15)
	_buzz_hand(_holder, 1.0, 0.15)
	_casino.pulse(0.7)
	_jimbo.react("pack")


# ---------------------------------------------------------------- reroll lever

func _on_lever_pulled() -> void:
	_send({"cmd": "reroll"})
	_ach.add("one_armed")
	var now := Time.get_ticks_msec() / 1000.0 # "Lever Frenzy": 5 pulls within 10 seconds
	_lever_pulls = _lever_pulls.filter(func(t: float) -> bool: return now - t < 10.0)
	_lever_pulls.append(now)
	if _lever_pulls.size() >= 5:
		_ach.add("lever_frenzy")
	if _ach.reward("one_armed"): # the golden lever pays out a little jingle
		for k in 3:
			get_tree().create_timer(0.12 * k).timeout.connect(func():
				_sounds.play({"code": "coin%d" % randi_range(1, 7), "per": randf_range(0.9, 1.2), "vol": _sounds.last_volume * 0.5, "at": _lever.global_position}))
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
		_jimbo.react("square_hole", 0.3)
		_money_from = _coin_slot.global_position
		_money_from_time = Time.get_ticks_msec() / 1000.0
		card.set_meta("gone", 0.0)
		return
	# every tarot / planet / spectral card works both ways: thrown up, or dropped onto the card hand
	# (only counts from the other hand - the card hand is always there)
	var thrown_up := pos.y > _eyes().y + 0.05 or _held_velocity.y > 1.2
	var on_hand := _over_card_hand(pos, _held_consumable_hand)
	if thrown_up or on_hand:
		_use_consumable(uid, thrown_up and kind == "Planet") # (a planet flies off into the sky)
	# not used: it glides back into the rack (the animation does that)


var _counter_prev := Vector3.ZERO
var _counter_velocity := Vector3.ZERO
var _counter_track_hand: Node3D = null # the hand whose movement _counter_velocity measures


## Is the item taken off the shop counter being let go with a "use" gesture? A tarot / spectral
## card dropped onto the card hand (from the other hand), or a planet thrown up into the sky.
func _counter_use_gesture(hand: XRController3D) -> bool:
	var it := _counter.held_item()
	var kind := str(it.get("set", ""))
	if not kind in ["Tarot", "Planet", "Spectral"]:
		return false
	var node := _counter.item_node(int(it.get("id", -1)))
	if node == null:
		return false
	var pos := node.global_position
	# every buy-and-use card works both ways: thrown up, or dropped onto the card hand
	var thrown_up := pos.y > _eyes().y + 0.05 or _counter_velocity.y > 1.2
	return thrown_up or _over_card_hand(pos, hand)


## The card hand lights up while a tarot / planet / spectral card is held at it (from the card stand
## or the shop counter): gold = let go and it is used, red = it can't be used now (or can't be
## paid). A small glowing ball around the hand - the drop point is the hand itself, not the fan
## (in the shop there is no fan to aim at).
var _fan_glow: MeshInstance3D
var _fan_glow_mat: StandardMaterial3D


func _build_fan_glow() -> void:
	_fan_glow = MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = HAND_DROP_RADIUS
	ball.height = HAND_DROP_RADIUS * 2.0
	_fan_glow.mesh = ball
	_fan_glow_mat = StandardMaterial3D.new()
	_fan_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fan_glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fan_glow_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_fan_glow_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_fan_glow.material_override = _fan_glow_mat
	_fan_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fan_glow.top_level = true # (placed at the card hand every frame)
	_fan_glow.visible = false
	add_child(_fan_glow)


func _update_fan_glow() -> void:
	if _fan_glow == null:
		return
	var pos := Vector3.ZERO
	var hand: Node3D = null
	var works := false
	var it := _counter.held_item() if _counter != null else {}
	if not it.is_empty() and str(it.get("set", "")) in ["Tarot", "Planet", "Spectral"]:
		var node := _counter.item_node(int(it.get("id", -1)))
		if node != null:
			pos = node.global_position
			hand = _counter.held_hand()
			works = it.get("cu", false) and int(it.get("cost", 0)) <= int(_state.get("round", {}).get("dollars", 0))
	elif _held_consumable >= 0 and is_instance_valid(_consumables.get(_held_consumable)):
		var card: Node3D = _consumables[_held_consumable]
		pos = card.global_position
		hand = _held_consumable_hand
		works = card.get_meta("can_use", false)
	var on := hand != null and _over_card_hand(pos, hand)
	_fan_glow.visible = on
	if on:
		_fan_glow.global_position = _holder.global_position
		var t := Time.get_ticks_msec() / 1000.0
		var a := 0.4 if _calm else 0.3 + 0.12 * sin(t * 8.0) # (Calm Lights: no pulsing)
		_fan_glow_mat.albedo_color = Color(1.0, 0.75, 0.2, a) if works else Color(1.0, 0.2, 0.15, a)


## A card held this close to the card hand (by the other hand) is used when let go there. Small on
## purpose: only a card brought right to the hand counts.
const HAND_DROP_RADIUS := 0.1
func _over_card_hand(pos: Vector3, hand: Node3D) -> bool:
	return _holder != null and hand != _holder and pos.distance_to(_holder.global_position) < HAND_DROP_RADIUS


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


func _rack_hint(card: Node3D, text: String, lift := 0.0) -> void:
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
	label.global_position = card.global_position + Vector3(0, 0.1 + lift, 0)
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
	var counter_hand := _counter.held_hand() if _counter != null else null
	if counter_hand != _counter_track_hand: # taken (or let go): start measuring afresh
		_counter_track_hand = counter_hand
		_counter_velocity = Vector3.ZERO
		if counter_hand != null:
			_counter_prev = counter_hand.global_position
	elif _vr and counter_hand != null and is_instance_valid(counter_hand): # (a planet thrown up from the counter)
		var cp := counter_hand.global_position
		_counter_velocity = _counter_velocity.lerp((cp - _counter_prev) / maxf(delta, 0.001), 0.3)
		_counter_prev = cp
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
	if _jimbo.visible: # he sits across the table, on its surface - wherever the joker board was put
		var at := _table_frame() * JIMBO_SPOT
		_jimbo.global_position = Vector3(at.x, _table_surface_y(), at.z)


# ---------------------------------------------------------------- coin slot for jokers

## A joker let go right above the coin slot is sold (with a little "into the slot" animation).
func _sell_dropped_joker(inst: Node3D, uid: int) -> bool:
	if _slot_solatro or inst.global_position.distance_to(_coin_slot.global_position) > SLOT_RADIUS:
		return false
	_send({"cmd": "sell", "target": uid})
	_ach.add("coin_slot")
	_jimbo.react("square_hole", 0.3) # now and then (otherwise his usual line)
	_jimbo.react("sell", 0.6)
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
	if _photo != null and _photo.try_grab(hand): # the photo camera
		_buzz_hand(hand, 0.2, 0.03)
		return true
	if _wheel != null and is_instance_valid(_wheel) and _wheel.try_grab(hand): # the Wheel of Fortune's rim
		return true
	if _try_grab_stand(hand): # the stand the played cards lie on
		return true
	if _solatro != null and _solatro.visible and _solatro.try_grab(hand): # a token chip
		_buzz_hand(hand, 0.2, 0.03)
		return true
	if _new_run != null and _new_run.visible and _new_run.try_grab(hand): # a deck or a stake chip
		_buzz_hand(hand, 0.2, 0.03)
		return true
	if _pack != null and is_instance_valid(_pack) and not _pack.is_ripped() and _pack.grab(hand):
		_buzz_hand(hand, 0.3, 0.04)
		return true
	if _lever.is_visible_in_tree() and _lever.try_grab(hand):
		_buzz_hand(hand, 0.2, 0.03)
		return true
	if _try_grab_consumable(hand):
		return true
	if _counter.try_grab(hand): # something off the shop counter
		_buzz_hand(hand, 0.2, 0.03)
		if _ach.reward("window_shopper"):
			_play_ding()
		return true
	if _try_grab_joker(hand):
		return true
	return _try_grab_board_item(hand) # deck, money, coin slot or card stand


## A blind won in VR (not Solatro): Heartbreaker, Hot Streak and Glass Cannon.
var _round_hands_start := 0
var _round_live := false            # a blind is being played (its win is counted once, at ROUND_EVAL)
var _round_blind := {}              # that blind (boss? which one? its chip)
var _round_hands_left := 0          # hands left after the last hand played in it
var _last_play_glass := 0
var _play_seen := false             # cards of the current hand are in the play area


func _blind_won_extras() -> void:
	var blind: Dictionary = _round_blind # (the blind as it was while it was played)
	if bool(blind.get("boss", false)) and str(blind.get("key", "")) == "bl_final_heart":
		_ach.add("heartbreaker")
		if _ach.reward("heartbreaker"):
			_heart_rain()
	var used := _round_hands_start - _round_hands_left
	if used == 1: # won with the first hand
		_ach.add("hot_streak")
		if _ach.reward("hot_streak"):
			_tower_flames()
	else:
		_ach.reset("hot_streak") # (in a row)
	if _last_play_glass >= 3:
		_ach.add("glass_cannon")


## Particles that burst out once and fade (hearts, flames ...).
func _burst(at: Vector3, amount: int, colour: Color, size: float, speed: Vector2, lifetime: float,
		gravity: Vector3, spread: float, mesh: Mesh = null) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = true
	p.explosiveness = 0.85
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = spread
	p.initial_velocity_min = speed.x
	p.initial_velocity_max = speed.y
	p.gravity = gravity
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	if mesh == null:
		var dot := SphereMesh.new()
		dot.radius = size
		dot.height = size * 2.0
		mesh = dot
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.vertex_color_use_as_albedo = true
	glow.cull_mode = BaseMaterial3D.CULL_DISABLED
	if mesh is PrimitiveMesh:
		(mesh as PrimitiveMesh).material = glow
	p.mesh = mesh
	var ramp := Gradient.new()
	ramp.set_color(0, Color(colour.r * 1.6, colour.g * 1.6, colour.b * 1.6, 1.0))
	ramp.set_color(1, Color(colour.r, colour.g, colour.b, 0.0))
	p.color_ramp = ramp
	add_child(p)
	p.global_position = at
	p.emitting = true
	get_tree().create_timer(lifetime + 0.5).timeout.connect(p.queue_free)
	return p


## "Heartbreaker" reward: the Crimson Heart bursts into a rain of little hearts.
func _heart_rain() -> void:
	var at = _casino._boss_room.heart_point() if _casino != null and _casino._boss_room != null else null
	if not (at is Vector3):
		at = Vector3(0, _table_surface_y() + 1.05, 0) + _layout.global_position * Vector3(1, 0, 1)
	var heart := PrismMesh.new() # (a little heart: a point and two lobes would be costly here - a red diamond does)
	heart.size = Vector3(0.03, 0.03, 0.01)
	_burst(at, 90, Color(1.0, 0.15, 0.3), 0.0, Vector2(0.4, 1.4), 2.6, Vector3(0, -0.9, 0), 180.0, heart)
	_burst(at, 40, Color(1.0, 0.55, 0.7), 0.012, Vector2(0.2, 0.9), 1.6, Vector3(0, -0.5, 0), 180.0)
	_play_applause()


## "Hot Streak" reward: the score tower bursts into flames.
func _tower_flames() -> void:
	if _score_tower == null or not _score_tower.is_visible_in_tree():
		return
	var base := _score_tower.global_position
	for i in 3:
		var p := _burst(base + _score_tower.global_basis.y * (0.08 + i * 0.08), 60, Color(1.0, 0.45 - i * 0.1, 0.08), 0.014,
				Vector2(0.15, 0.5), 1.1, Vector3(0, 0.6, 0), 25.0)
		p.explosiveness = 0.3


## "High Five-of-a-Kind" reward: five flames over the play stand.
func _five_flames() -> void:
	var surface := _play_stand.global_transform * _play_surface()
	for i in 5:
		var at: Vector3 = surface * Vector3((i - 2) * PLAY_SPACING, 0.03, 0.0)
		var p := _burst(at, 30, Color(1.0, 0.5, 0.1), 0.01, Vector2(0.1, 0.3), 0.9, Vector3(0, 0.4, 0), 15.0)
		p.explosiveness = 0.2
		p.one_shot = false
		var p_ref: WeakRef = weakref(p) # (_burst frees it after 1.4 s: stop well before, so its flames die down)
		get_tree().create_timer(0.5).timeout.connect(func():
			var fl = p_ref.get_ref()
			if fl != null:
				fl.emitting = false)


## "Glass Cannon" reward: a glass card in the fan sparkles.
func _sparkle(body: Node3D, on: bool) -> void:
	var s := body.get_node_or_null("Sparkle") as CPUParticles3D
	if s == null and on:
		s = CPUParticles3D.new()
		s.name = "Sparkle"
		s.amount = 10
		s.lifetime = 0.8
		s.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		s.emission_box_extents = Vector3(CARD_SIZE.x * 0.45, CARD_SIZE.y * 0.45, 0.002)
		s.gravity = Vector3.ZERO
		s.initial_velocity_max = 0.01
		var star := QuadMesh.new()
		star.size = Vector2(0.006, 0.006)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.vertex_color_use_as_albedo = true
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		star.material = m
		s.mesh = star
		var ramp := Gradient.new()
		ramp.set_color(0, Color(1.6, 1.8, 2.0, 0.0))
		ramp.add_point(0.4, Color(1.6, 1.8, 2.0, 1.0))
		ramp.set_color(ramp.get_point_count() - 1, Color(0.8, 0.9, 1.0, 0.0))
		s.color_ramp = ramp
		body.add_child(s)
	if s != null:
		s.emitting = on
		s.visible = on


## "Bargain Hunter": something for $2 or less (or free) bought off the counter.
func _count_bargain(uid: int) -> void:
	if _vr and not _solatro.active and _counter.cost_of(uid) <= 2:
		_ach.add("bargain")


## "Pack Surgeon" reward: the confetti in the pack's own colours.
func _pack_colours(name: String) -> Array:
	var n := name.to_lower()
	if n.contains("arcana"):
		return [Color(0.65, 0.35, 1.0), Color(1.0, 0.85, 0.4), Color(0.85, 0.6, 1.0)]
	if n.contains("celestial"):
		return [Color(0.3, 0.6, 1.0), Color(0.6, 0.9, 1.0), Color(1.0, 1.0, 1.0)]
	if n.contains("spectral"):
		return [Color(0.3, 0.9, 0.9), Color(0.2, 0.5, 0.9), Color(0.85, 1.0, 1.0)]
	if n.contains("buffoon"):
		return [Color(1.0, 0.35, 0.3), Color(1.0, 0.7, 0.2), Color(0.3, 0.6, 1.0)]
	if n.contains("standard"):
		return [Color(0.95, 0.25, 0.3), Color(1.0, 1.0, 1.0), Color(0.2, 0.2, 0.25)]
	return [Color(1, 0.85, 0.3), Color(1, 1, 1), Color(0.95, 0.4, 0.5), Color(0.4, 0.75, 1.0)]


## Is that joker on the table now?
func _has_joker(key: String) -> bool:
	for j in _state.get("jokers", []):
		if j is Dictionary and str(j.get("key", "")) == key:
			return true
	return false


## "Hands On" reward: the bell on the counter rings when something is bought.
func _ring_shop_bell() -> void:
	_counter.ring_bell()
	_play_ding()


## What came of buying off the counter (grabbed or with the buy buttons): a buzz, or a hint.
func _counter_result(result: String, hand: XRController3D) -> void:
	if hand == null:
		hand = _point
	match result:
		"bought", "used":
			_buzz_hand(hand, 0.5, 0.08)
			if _ach.reward("hands_on"):
				_ring_shop_bell()
		"poor": # not enough money: a hint, and it goes back onto the counter
			_rack_hint(_counter, "Not enough points" if _solatro.active else "Not enough money")
			_buzz_hand(hand, 0.2, 0.05)
		"cant": # the game's BUY AND USE wouldn't be there either: back onto the counter
			_rack_hint(_counter, "Can't be used right now")
			_buzz_hand(hand, 0.2, 0.05)


func _release_table(hand: XRController3D) -> void:
	if _photo != null and _photo.holds(hand):
		_photo.release(hand) # it stays floating there (beam + trigger on it: self-timer)
	if _wheel != null and is_instance_valid(_wheel):
		_wheel.release(hand) # let go of the rim: a good swing spins it
	if _held_stand_hand == hand:
		_held_stand_hand = null # put down where it is, kept for next time
		_save_layout()
		_buzz_hand(hand, 0.25, 0.04)
	if _solatro != null and _solatro.holds(hand):
		_solatro.release(hand) # into the bowl: the token is used
		_buzz_hand(hand, 0.25, 0.04)
	if _new_run != null and _new_run.holds(hand):
		_new_run.release(hand)
		_buzz_hand(hand, 0.25, 0.04)
	if _pack != null and is_instance_valid(_pack):
		_pack.release(hand)
	_lever.release(hand)
	if _counter.holds(hand):
		# "buy and use": a tarot / spectral card dropped onto the card hand, a planet thrown up -
		# the same gestures as using a card from the card stand
		var result := _counter.release_use(hand) if _counter_use_gesture(hand) else _counter.release(hand)
		if result == "":
			_ach.add("window_shopper") # taken and put back
		elif result in ["bought", "used"] and _vr:
			_ach.add("hands_on") # bought by grabbing it
		_counter_result(result, hand)
	if _held_consumable >= 0 and _held_consumable_hand == hand:
		_drop_consumable()
	if _held_joker >= 0 and _held_hand == hand:
		_drop_joker()
	if _held_item != null and _held_item_hand == hand:
		_drop_board_item()


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
var _jimbo_on := true            # "VR: Jimbo": he sits at the casino table
var _ambience_on := true         # the casino's own sounds (slot machines, glasses, chips)
var _gloves: Array = []          # the two JimboHands (VR only)
var _spectator: Spectator        # the spectator camera window (VR only)
var _tutorial: VRTutorial        # Jimbo's tips
var _wrist: WristMenu            # the VR settings above the card hand (menu button)
var _main_menu: MainMenuVR       # the main menu as objects on the casino table (VR)
var _score_tower: ScoreTower     # the blind's score against its target, beside the blind chip
var _new_run: NewRunVR           # the "New Run" table: decks, stake chips, START (VR)
var _new_run_open := false       # PLAY was pressed: the New Run table instead of the main menu
var _menu_on := false            # the game is in its main menu and VR shows it on the table
var _ach: Achievements           # VR achievements and their rewards
var _ach_menu: AchievementsMenu  # their page in the VR menu (≡ -> Achievements)
var _bowl_pusher: Node3D = null  # "Bowling Alley": the joker pushing right now ...
var _bowl_hits := {}             # ... and the jokers it pushed aside in this go
var _tower_judged := false       # "Sky High" / "Close Call" checked for the blind just played
var _hand_start := -1            # "Ambidextrous": left-handed (1) or not (0) when the client started
var _hands_off_played := false   # "Hand Model": the hands were switched off during a run
var _price_seen := -1            # "Price Check": the joker whose price was read in this lift
var _ding: AudioStreamPlayer     # "Window Shopper" reward
var _card_stock: StandardMaterial3D  # the pale edge of every card (see _card_core)
var _test: TestTools             # test tools (TEST_TOOLS)
var _card_stats: CardStatsVR     # Stats -> Card Stats as columns around you
var _photo: PhotoCamera          # photo mode (VR menu: Photo Camera)
var _radar: RadarScreen          # "UnderTheVRadar" reward
var _glass_left: Array = []      # "Glass Breaker" reward: shard groups lying on the table this run
var _stream_secs := 0.0          # "Streamer": seconds with the spectator window on
var _ghost_next := 30.0          # "Ghost Hunter" reward: seconds until the lounge haunts again
var _session_blind_won := false  # "Safe Travels": a blind was won in this session
var _floor_ding_at := -10.0      # "Going Up!" reward: when the elevator dinged last
var _lever_pulls: Array = []     # "Lever Frenzy": times of the last pulls
var _shop_spent := 0             # "Big Spender": dollars spent in this shop
var _applause: AudioStreamPlayer # "Standing Ovation" reward
var _ach_next_popup := 0.0       # when the next achievement plaque may appear
var _marble: StandardMaterial3D  # "Bowling Alley" reward: marble pedestals
var _wheel: WheelSpin            # the Wheel of Fortune card's wheel (while it is used)
var _wheel_mode := "Real"        # "VR: Wheel of Fortune": Off / Deterministic / Real (see _set_wheel)
var _solatro: SolatroGame        # SOLATRO, the solo card game (the game itself waits in its menu)
var _tower_last: Array = []      # [score, target] of the blind last played (shown on through cash out)
var _menu_atlas_asked := false   # card pictures asked for once per connection (menu table)
var _solatro_hints: Array = []   # times of Solatro's messages still floating (to stack them)
var _solatro_cache := {}         # "scene" / "state": the game's latest, shown again when Solatro ends
var _first_hint: Label3D         # "First time? Check How To Play" until they were opened once
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
	var from_counter: Node3D = _counter.item_node(uid) if _counter != null and _vr else null
	if from_counter != null: # taken off the shop counter: it flies on from your hand
		v = from_counter
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
	if from_counter != null:
		s0 = from_counter.scale.x
		from_counter.visible = false
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
	# the game counts the hand as used when it is played, so "1 left" already shows while the second
	# to last hand is still being scored: the room only darkens once that scoring is over and the
	# cards for the last try are drawn (and the score still isn't enough); then it stays dark through
	# the last hand
	if tense and not _tension and name != "DRAW_TO_HAND" and name != "SELECTING_HAND":
		tense = false
	if tense != _tension:
		_tension = tense
		_casino.set_tension(tense)
		if tense:
			_jimbo.react("last_hand", 0.8)
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
		var heart = _casino._boss_room.heart_point() if _casino != null and _casino._boss_room != null else null
		if heart is Vector3: # Crimson Heart: the bolts come from the heart over the table
			_zap(heart, joker_at, colour)
		elif now - float(_last_card_pop["t"]) < 0.8:
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
