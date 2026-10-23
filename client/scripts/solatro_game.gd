class_name SolatroGame
extends Node3D
## SOLATRO - the solo pen-and-paper mix of Balatro and solitaire (game idea by the YouTuber TechDweeb), played in VR on its
## own: Balatro itself stays in its main menu and only lends the card pictures.
##   54 cards (52 + 2 jokers). Round n needs 25 * n points. 8 cards in hand, 3 plays of up to 5
##   cards, 3 discards of 1-5 cards. A poker hand scores fixed points (High Card 5 ... Royal Flush
##   150). A drawn joker is banked as a wildcard (shown in the hand, select it to use it); a second
##   joker while one is banked: both are lost. Points beyond the target buy tokens in the Bonus
##   Shoppe (one of each): Extra Card, Extra Discard, Pocket Points, Extra Hand, Double Score, Shield.
##   Fail a round without a Shield and the game is over; the result is the round reached.
## The game hands main.gd the same kind of "scene" and "state" the real game sends, so the card fan,
## the gestures, the score tower, the blind chip and the sales counter all just work; main.gd sends
## its commands (click, play, discard, buy, next_round ...) here instead of to the game.
## The table props (info board, token chips with their bowl, EXIT / PLAY AGAIN / MENU signs) live in
## the joker board's space (x right, +z towards you, y up).

signal publish(scene: Dictionary, state: Dictionary)
signal hint(text: String)
signal scored(text: String)
signal leave                        # back to the main menu
signal double_joker                 # a second joker while one was banked: both lost

const RANKS := ["2", "3", "4", "5", "6", "7", "8", "9", "10", "Jack", "Queen", "King", "Ace"]
const SUITS := ["Hearts", "Clubs", "Diamonds", "Spades"] # (their rows in the game's card atlas)
const HAND_POINTS := {"High Card": 5, "Pair": 10, "Two Pair": 20, "Three of a Kind": 30, "Straight": 40,
	"Flush": 50, "Full House": 60, "Four of a Kind": 100, "Straight Flush": 125, "Royal Flush": 150}
const TOKENS := [
	{"key": "extra_card", "name": "Extra Card", "cost": 10, "text": "1 more card in your hand this round"},
	{"key": "extra_discard", "name": "Extra Discard", "cost": 25, "text": "1 more discard this round"},
	{"key": "pocket_points", "name": "Pocket Points", "cost": 50, "text": "Add 25 points to this round"},
	{"key": "extra_hand", "name": "Extra Hand", "cost": 75, "text": "Play one more hand this round"},
	{"key": "double_score", "name": "Double Score", "cost": 100, "text": "Double the points of your next play"},
	{"key": "shield", "name": "Shield", "cost": 150, "text": "Ignore one failed round (used by itself)"},
]
const RANKS_TABLE := [[3, "Cat Food"], [5, "Little Dweeb"], [7, "Official Dweeb"], [10, "Ultra Mega Uber Giga-Dweeb"]]
const JOKER_ID := 900               # the banked joker, as a card in the hand
const TOKEN_ID := 1000              # + index: tokens on the sales counter
const EXIT_ID := -600
const AGAIN_ID := -601
const MENU_ID := -602
const HELP_ID := -603               # HOW TO PLAY: the rules board
const HELP_PREV_ID := -604          # its < BACK and NEXT > buttons
const HELP_NEXT_ID := -605
const CHIP_ID := -610               # - index: owned token chips on the table
const DECK_CARD := Vector2(0.045, 0.06) # a card in the deck view
const HOLD_IN_HAND := Transform3D(Basis(), Vector3(0.0, -0.01, -0.03)) # a held chip, from the controller
const BOWL_POS := Vector3(-0.42, 0.0, 0.0)   # where the token pedestal starts (it can be carried elsewhere)
const PEDESTAL_R := 0.11                     # the stone pedestal: its six-sided plinth (corner radius) ...
const PEDESTAL_TOP := 0.028                  # ... and the height of its top
const SOCKET_R := 0.068                      # a socket for each token, round the edge
const CENTRE_R := 0.036                      # the well in the middle: a token placed there is used
const FITTING := Color(0.48, 0.38, 0.24)     # the sockets' and the rune ring's metal (dark bronze)
const HELP_POS := Vector3(0.38, 0.0, -0.3)   # HOW TO PLAY ...
const EXIT_POS := Vector3(0.55, 0.0, -0.3)   # ... and EXIT right of it (swapped for left-handers)


## Left-handed: EXIT goes to the left of HOW TO PLAY.
func set_left_handed(on: bool) -> void:
	if _signs.has(EXIT_ID) and _signs.has(HELP_ID):
		(_signs[HELP_ID] as Node3D).position = EXIT_POS if on else HELP_POS
		(_signs[EXIT_ID] as Node3D).position = HELP_POS if on else EXIT_POS

var active := false
var gold_cards := false             # achievement reward "Royal Treatment": the cards are gold cards
var best := 0                       # best round reached (main.gd loads / saves it)
var hands: Array = []               # XRController3D (for grabbing token chips)

var _rng := RandomNumberGenerator.new()
var _round := 1
var _deck: Array = []               # card ids left to draw (1..52 cards, 53 / 54 jokers)
var _hand: Array = []
var _played: Array = []             # on the play stand right now (shown while scoring)
var _banked := false                # a joker kept as a wildcard
var _selected := {}                 # id -> true (cards in the hand and the banked joker)
var _target := 25
var _score := 0
var _plays := 3
var _discards := 3
var _limit := 8
var _double := false
var _bonus := 0                     # points to spend in the Bonus Shoppe (after a won round)
var _owned := {}                    # token key -> true
var _phase := "play"                # play / scoring / shop / over
var _timer := 0.0
var _by_suit := false
var _last_hand := ""

var _info: Label3D
var _chips := {}                    # token key -> Node3D (owned tokens on the table)
var _bodies: Array[StaticBody3D] = []
var _held: Node3D = null
var _held_hand: Node3D = null
var _held_key := ""
var _held_offset := Transform3D()
signal bowl_moved(at: Vector3)      # the bowl was put somewhere else (main.gd remembers it)
signal note_moved(xf: Transform3D)  # the HAND POINTS card was put somewhere else (anywhere, any tilt)
signal hoarded                      # every token bought in one game ("Token Hoarder")
signal sfx(kind: String, cards: int) # "play" / "discard" with how many cards: main.gd plays the game's sounds
var _bought_game := {}              # token key -> true: bought in this game (used ones too)
var _bowl_mat: StandardMaterial3D    # the pedestal's metal fittings (sockets, rune ring)
var _rune_mat: StandardMaterial3D    # the runes round the well: they light up when a token is used
var _rune_flash := 0.0
var _pedestal_label: Label3D        # "USE A TOKEN: PLACE IT IN THE MIDDLE" ...
var _hints_off := false             # ... and the tokens' names: gone once a token was used in this game


## "Token Hoarder" reward: the pedestal's fittings in the chosen colour (a plain colour, no glow).
func set_golden_bowl(on: bool, colour := Color(1.0, 0.75, 0.25)) -> void:
	if _bowl_mat == null:
		return
	_bowl_mat.albedo_color = colour if on else FITTING
	_rune_mat.albedo_color = _bowl_mat.albedo_color
var _note: Node3D
var _held_note_offset := Transform3D()
var clamp_board: Callable           # (Vector2) -> Vector2: a spot on the joker board (main.gd)
var _bowl: Node3D
var _held_bowl_offset := Transform3D()
var _signs := {}                    # id -> Node3D
var _rules_title: Label3D
var _rules_body: Node3D
var _rules_page: Label3D
var _rules_next: Label3D
var _rules_index := 0
var _rules: Node3D                  # the HOW TO PLAY board (instead of the info board while open)
var _deck_view: Node3D              # a hand over the 3D deck: which cards are still in it
var _deck_cards := {}               # card id -> its dark cover (shown once the card left the deck)
var _deck_title: Label3D
var _rules_before := false          # (the rules board comes back after the deck view)


func _ready() -> void:
	_rng.randomize()
	_info = Label3D.new()
	_info.font_size = 40
	_info.pixel_size = 0.0007
	_info.outline_size = 10
	_info.outline_modulate = Color(0.05, 0.03, 0.06)
	_info.modulate = Color(1.0, 0.92, 0.75)
	_info.width = 0.5 / _info.pixel_size
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.position = Vector3(0.0, 0.3, -0.42)
	_info.visible = false # (round, target, score, plays and discards are on the tower, the stand and the chip)
	add_child(_info)
	_build_bowl()
	# EXIT: right of HOW TO PLAY (left of it for left-handers), red - back to the main menu at any time
	_signs[EXIT_ID] = _build_sign("EXIT", EXIT_ID, EXIT_POS, Color(1.0, 0.95, 0.9), Color(0.6, 0.08, 0.1))
	_signs[AGAIN_ID] = _build_sign("PLAY\nAGAIN", AGAIN_ID, Vector3(-0.12, 0.0, -0.1), Color(0.6, 2.0, 0.8)) # (in front of the play stand)
	_signs[MENU_ID] = _build_sign("MENU", MENU_ID, Vector3(0.12, 0.0, -0.1), Color(1.6, 1.2, 0.5))
	_signs[HELP_ID] = _build_sign("HOW TO\nPLAY", HELP_ID, HELP_POS, Color(0.6, 1.4, 2.0))
	_build_rules()
	_build_cheat_sheet()
	GameFont.apply_to(self)
	visible = false


# ---------------------------------------------------------------- the game

func start() -> void:
	active = true
	visible = true
	_round = 1
	_owned.clear()
	_bought_game.clear()
	_bonus = 0
	_show_token_hints(true) # (a new game: the pedestal's help and the tokens' names again)
	_new_round()
	show_rules(best == 0) # the first games start with the rules


func stop() -> void:
	active = false
	show_deck(false)
	visible = false
	_held = null


func _new_round() -> void:
	_deck.clear()
	for id in range(1, 55):
		_deck.append(id)
	_shuffle(_deck)
	_hand.clear()
	_played.clear()
	_selected.clear()
	_banked = false
	_target = 25 * _round
	_score = 0
	_plays = 3
	_discards = 3
	_limit = 8
	_double = false
	_last_hand = ""
	_phase = "play"
	_draw()
	_publish()


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t


## Draw back up to the hand limit. A joker is banked as a wildcard; a second one while one is banked:
## both are gone ("Joke's on you, DWEEB!").
func _draw() -> void:
	while _hand.size() < _limit and not _deck.is_empty():
		var id: int = _deck.pop_back()
		if id > 52:
			if _banked:
				_banked = false
				_selected.erase(JOKER_ID)
				hint.emit("A second joker! You lose both - joke's on you, DWEEB!")
				double_joker.emit()
			else:
				_banked = true
				hint.emit("Joker banked: a wildcard for a later play")
			continue
		_hand.append(id)
	_sort_hand()


func _sort_hand() -> void:
	_hand.sort_custom(func(a: int, b: int) -> bool:
		var ra := (a - 1) % 13
		var rb := (b - 1) % 13
		var sa := (a - 1) / 13
		var sb := (b - 1) / 13
		if _by_suit:
			return sa < sb if sa != sb else ra > rb
		return ra > rb if ra != rb else sa < sb)


## main.gd's commands (what would go to the game).
func command(c: Dictionary) -> void:
	match str(c.get("cmd", "")):
		"click":
			_toggle(int(c.get("target", -1)))
		"play":
			_play()
		"discard":
			_discard()
		"sort":
			_by_suit = not _by_suit
			_sort_hand()
			_publish()
		"move":
			_move(int(c.get("target", -1)), int(c.get("to", -1)))
		"buy":
			_buy(int(c.get("target", -1)) - TOKEN_ID)
		"next_round":
			if _phase == "shop":
				_round += 1
				_bonus = 0 # points don't last between rounds
				_new_round()
		"reroll":
			hint.emit("No rerolls in Solatro")
		"deck_view":
			show_deck(bool(c.get("on", false)))


func _toggle(id: int) -> void:
	if _phase != "play":
		return
	if not (_hand.has(id) or (id == JOKER_ID and _banked)):
		return
	if _selected.has(id):
		_selected.erase(id)
	elif _selected.size() >= 5:
		hint.emit("Up to 5 cards")
		return
	else:
		_selected[id] = true
	_publish()


func _move(id: int, to: int) -> void:
	var a := _hand.find(id)
	var b := _hand.find(to)
	if a < 0 or b < 0:
		return
	_hand.remove_at(a)
	_hand.insert(b, id)
	_publish()


func _play() -> void:
	if _phase != "play":
		return
	if _selected.is_empty():
		hint.emit("Select up to 5 cards first")
		return
	var cards: Array = []
	for id in _selected:
		if id != JOKER_ID:
			cards.append(id)
	var wild := 1 if _selected.has(JOKER_ID) else 0
	var res := _evaluate(cards, wild)
	var points: int = res[1]
	if _double:
		points *= 2
		_double = false
	_score += points
	_plays -= 1
	_last_hand = "%s  +%d" % [res[0], points]
	scored.emit(_last_hand)
	sfx.emit("play", cards.size())
	for id in cards:
		_hand.erase(id)
	_played = cards
	if wild > 0:
		_banked = false
	_selected.clear()
	_phase = "scoring"
	_timer = 1.6
	_publish()


func _discard() -> void:
	if _phase != "play":
		return
	var cards: Array = []
	for id in _selected:
		if id != JOKER_ID:
			cards.append(id)
	if cards.is_empty():
		hint.emit("Select 1 to 5 cards to discard")
		return
	if _discards <= 0:
		hint.emit("0 Discards remaining")
		return
	_discards -= 1
	sfx.emit("discard", cards.size())
	for id in cards:
		_hand.erase(id)
		_selected.erase(id)
	_draw()
	_publish()


func _end_round() -> void:
	if _score >= _target:
		_bonus = _score - _target
		_phase = "shop"
		hint.emit("Round %d beaten! %d bonus points for the Bonus Shoppe" % [_round, _bonus])
	elif _owned.has("shield"):
		_owned.erase("shield")
		_bonus = 0
		_phase = "shop"
		hint.emit("Your Shield saved you: on to round %d" % (_round + 1))
	else:
		_phase = "over"
		if _round > best:
			best = _round
	_publish()


func _buy(i: int) -> void:
	if _phase != "shop" or i < 0 or i >= TOKENS.size():
		return
	var t: Dictionary = TOKENS[i]
	if _owned.has(t["key"]):
		hint.emit("You already own that one")
	elif int(t["cost"]) > _bonus:
		hint.emit("Not enough bonus points")
	else:
		_bonus -= int(t["cost"])
		_owned[t["key"]] = true
		_bought_game[t["key"]] = true
		if _bought_game.size() == TOKENS.size():
			hoarded.emit()
	_publish()


## A token thrown into the bowl (or the trigger on its chip).
func _use_token(key: String) -> void:
	if _phase != "play":
		hint.emit("Tokens are used during a round")
		return
	match key:
		"extra_card":
			_limit += 1
			_draw()
		"extra_discard":
			_discards += 1
		"pocket_points":
			_score += 25
		"extra_hand":
			_plays += 1
		"double_score":
			_double = true
		"shield":
			hint.emit("The Shield works by itself when a round fails")
			return
	_owned.erase(key)
	_rune_flash = 1.0 # (the runes round the well light up for a moment)
	_show_token_hints(false) # (you know how it works now: less text on the table)
	hint.emit(_token(key)["name"] + " used")
	_publish()


func _token(key: String) -> Dictionary:
	for t in TOKENS:
		if t["key"] == key:
			return t
	return {}


func _process(delta: float) -> void:
	if not active:
		return
	if _phase == "scoring":
		_timer -= delta
		if _timer <= 0.0:
			_played.clear()
			_phase = "play"
			if _plays <= 0:
				_end_round() # (no drawing after the last play: the round is over)
			else:
				_draw()
				_publish()
	_animate_chips(delta)


# ---------------------------------------------------------------- poker hands (one wildcard)

## [hand name, points] of the best poker hand the cards make; a wildcard becomes any card.
func _evaluate(ids: Array, wild: int) -> Array:
	var cards: Array = []
	for id in ids:
		cards.append(Vector2i(2 + (id - 1) % 13, (id - 1) / 13)) # rank 2..14, suit 0..3
	if wild <= 0:
		return _classify(cards)
	var best_hand := ["High Card", 0]
	for r in range(2, 15):
		for s in 4:
			var h := _classify(cards + [Vector2i(r, s)])
			if int(h[1]) > int(best_hand[1]):
				best_hand = h
	return best_hand


static func _classify(cards: Array) -> Array:
	var n := cards.size()
	var counts := {}
	for c in cards:
		counts[c.x] = int(counts.get(c.x, 0)) + 1
	var groups: Array = counts.values()
	groups.sort()
	groups.reverse()
	var flush := false
	var straight := false
	if n == 5:
		flush = true
		for c in cards:
			if c.y != cards[0].y:
				flush = false
		if counts.size() == 5:
			var ranks: Array = counts.keys()
			ranks.sort()
			straight = ranks[4] - ranks[0] == 4 or ranks == [2, 3, 4, 5, 14]
	var name := "High Card"
	if straight and flush:
		var ranks: Array = counts.keys()
		ranks.sort()
		name = "Royal Flush" if ranks == [10, 11, 12, 13, 14] else "Straight Flush"
	elif groups.size() > 0 and int(groups[0]) >= 4:
		name = "Four of a Kind"
	elif groups.size() > 1 and int(groups[0]) == 3 and int(groups[1]) >= 2:
		name = "Full House"
	elif flush:
		name = "Flush"
	elif straight:
		name = "Straight"
	elif groups.size() > 0 and int(groups[0]) == 3:
		name = "Three of a Kind"
	elif groups.size() > 1 and int(groups[0]) == 2 and int(groups[1]) == 2:
		name = "Two Pair"
	elif groups.size() > 0 and int(groups[0]) == 2:
		name = "Pair"
	return [name, HAND_POINTS[name]]


# ---------------------------------------------------------------- what main.gd shows

func _card_item(id: int, area: String) -> Dictionary:
	var r := (id - 1) % 13
	var s := (id - 1) / 13
	return {"k": "c", "id": id, "area": area, "f": "front", "set": "Default", "rank": RANKS[r], "suit": SUITS[s],
		"ca": "centers", "cp": [6, 0] if gold_cards else [1, 0], "fa": "cards_1", "fp": [r, s], "hl": _selected.has(id),
		"x": 0.0, "y": 0.0, "w": 1.4, "h": 1.9}


## Draws the current state again (a card picture arrived late).
func redraw() -> void:
	_publish()


func _publish() -> void:
	var items: Array = []
	for id in _hand:
		items.append(_card_item(id, "hand"))
	if _banked: # the banked joker, as a card in the hand: select it to play it as a wildcard
		items.append({"k": "c", "id": JOKER_ID, "area": "hand", "f": "front", "set": "Joker", "name": "JOKER (wild)",
			"ca": "Joker", "cp": [0, 0], "hl": _selected.has(JOKER_ID), "x": 0.0, "y": 0.0, "w": 1.4, "h": 1.9})
	for id in _played:
		items.append(_card_item(id, "play"))
	if _phase == "shop":
		for i in TOKENS.size():
			var t: Dictionary = TOKENS[i]
			if not _owned.has(t["key"]):
				items.append({"k": "c", "id": TOKEN_ID + i, "area": "shop_jokers", "f": "front", "set": "Voucher",
					"name": t["name"], "label": t["name"] + "\n" + t["text"], "token": t["key"], "cost": t["cost"], "x": 0.0, "y": 0.0, "w": 1.4, "h": 1.9})
	var preview := {}
	if _phase == "play" and not _selected.is_empty():
		var cards: Array = []
		for id in _selected:
			if id != JOKER_ID:
				cards.append(id)
		var res := _evaluate(cards, 1 if _selected.has(JOKER_ID) else 0)
		preview = {"name": res[0], "level": "", "points": int(res[1]) * (2 if _double else 1)}
	var state_name: String = {"play": "SELECTING_HAND", "scoring": "HAND_PLAYED", "shop": "SHOP", "over": "GAME_OVER"}[_phase]
	var state := {
		"in_run": true, "state_name": state_name, "won": false, "solatro": true,
		"round": {"ante": _round, "round": _round, "hands_left": _plays, "discards_left": _discards,
			"chips": _score, "dollars": _bonus, "hand": preview},
		"blind": {"name": "Round %d" % _round, "chips": _target, "boss": false,
			"chip_text": "ROUND %d" % _round,
			"chip_back": "PLAYS LEFT: %d
DISCARDS LEFT: %d" % [_plays, _discards]}, # the blind chip says SOLATRO (see main.gd _set_chip_text)
		"deck": {"remaining": _deck.size(), "total": 54, "back_key": "b_red", "back_sprite": {"atlas": "centers", "pos": [0, 0]}},
		"jokers": [], "consumables": [], "shop_open": _phase == "shop", "reroll_cost": 0, "can_reroll": false,
	}
	var scene := {"room": {"w": 20, "h": 11.5}, "state_name": state_name, "groups": [], "items": items}
	_refresh_table()
	publish.emit(scene, state)


func _refresh_table() -> void:
	var lines: Array = ["SOLATRO   •   ROUND %d" % _round]
	match _phase:
		"play", "scoring":
			lines.append("Target %d   •   Score %d" % [_target, _score])
			lines.append("Plays left %d   •   Discards left %d" % [_plays, _discards])
			if _double:
				lines.append("Next play counts double!")
			if _last_hand != "":
				lines.append("Last: " + _last_hand)
		"shop":
			lines.append("BONUS SHOPPE: %d points to spend" % _bonus)
			lines.append("Take a token off the counter, then NEXT ROUND")
		"over":
			lines.append("GAME OVER - you reached round %d" % _round)
			lines.append("Rank: " + _rank_name(_round))
			lines.append("Best: round %d" % best)
	_info.text = "\n".join(lines)
	_signs[AGAIN_ID].visible = _phase == "over"
	_signs[MENU_ID].visible = _phase == "over"
	_enable_sign(AGAIN_ID, _phase == "over")
	_enable_sign(MENU_ID, _phase == "over")
	_signs[EXIT_ID].visible = _phase != "over" # (game over: MENU does the same)
	_enable_sign(EXIT_ID, _phase != "over")
	# owned tokens as chips on the table
	for key in _chips.keys():
		if not _owned.has(key):
			(_chips[key] as Node3D).queue_free()
			_chips.erase(key)
	for t in TOKENS: # each token in its own socket of the pedestal
		if _owned.has(t["key"]):
			if not _chips.has(t["key"]):
				_chips[t["key"]] = _make_chip(t, TOKENS.find(t))
			(_chips[t["key"]] as Node3D).set_meta("socket", TOKENS.find(t))


static func _rank_name(round_reached: int) -> String:
	var name := "Not yet a Dweeb"
	for r in RANKS_TABLE:
		if round_reached >= int(r[0]):
			name = str(r[1])
	return name


# ---------------------------------------------------------------- the table props

func press(id: int) -> void:
	if id == HELP_ID:
		show_rules(not _rules.visible)
	elif id == HELP_PREV_ID and _rules.visible:
		_show_rules_page(_rules_index - 1)
	elif id == HELP_NEXT_ID and _rules.visible:
		if _rules_index >= _rules_pages().size() - 1:
			show_rules(false) # (the last page: CLOSE)
		else:
			_show_rules_page(_rules_index + 1)
	elif id == EXIT_ID or id == MENU_ID:
		leave.emit()
	elif id == AGAIN_ID:
		start()
	elif id <= CHIP_ID and id > CHIP_ID - TOKENS.size():
		_use_token(TOKENS[CHIP_ID - id]["key"])


## A hand over the 3D deck (main.gd's "deck_view"): all 52 cards by suit where the info board is,
## the ones still in the deck bright, the drawn ones dark - like the game's View Deck.
func show_deck(on: bool) -> void:
	if on and _deck_view == null:
		_build_deck_view()
	if _deck_view == null or on == _deck_view.visible:
		return
	if on:
		_rules_before = _rules.visible
		_rules.visible = false
		_info.visible = false
		var left := {}
		for id in _deck:
			left[id] = true
		for id in _deck_cards:
			var shade: Node3D = _deck_cards[id]
			shade.visible = not left.has(id)
			CardArt.apply_layers(shade.get_parent(), CardArt.card_layers(_card_item(id, "deck")), DECK_CARD, 0.0, 0.0003) # (pictures may have come late)
		var jokers := 0
		for id in _deck:
			if id > 52:
				jokers += 1
		_deck_title.text = "IN THE DECK: %d of 54 cards   •   jokers: %d" % [_deck.size(), jokers]
		GameFont.apply_to(_deck_title)
		_deck_view.visible = true
	else:
		_deck_view.visible = false
		show_rules(_rules_before)


func _build_deck_view() -> void:
	_deck_view = Node3D.new()
	_deck_view.position = Vector3(0.0, 0.2, -0.5)
	_deck_view.rotation_degrees.x = -12.0
	add_child(_deck_view)
	var size := DECK_CARD
	var board := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.68, 0.34, 0.012)
	board.mesh = bm
	board.material_override = _mat(Color(0.12, 0.04, 0.1), 0.8, 0.0)
	board.position.y = 0.17
	_deck_view.add_child(board)
	_deck_title = Label3D.new()
	_deck_title.font_size = 36
	_deck_title.pixel_size = 0.0006
	_deck_title.modulate = Color(1.0, 0.85, 0.4)
	_deck_title.outline_size = 0
	_deck_title.position = Vector3(0, 0.315, 0.007)
	_deck_view.add_child(_deck_title)
	var dark := StandardMaterial3D.new()
	dark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dark.albedo_color = Color(0.05, 0.02, 0.05, 0.75)
	dark.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var cover := QuadMesh.new()
	cover.size = size
	for s in 4: # rows by suit (Spades, Hearts, Clubs, Diamonds like the game), Ace .. 2 from the left
		var suit: int = [3, 0, 1, 2][s]
		for r in 13:
			var id := suit * 13 + (12 - r) + 1
			var card := Node3D.new()
			card.position = Vector3(-0.3 + r * 0.05, 0.255 - s * 0.068, 0.007)
			_deck_view.add_child(card)
			var shade := MeshInstance3D.new()
			shade.mesh = cover
			shade.material_override = dark
			shade.position.z = 0.002
			card.add_child(shade)
			_deck_cards[id] = shade
	_deck_view.visible = false


## A little note on a stand at the front right of the table: every poker hand and its points.
func _build_cheat_sheet() -> void:
	var note := Node3D.new()
	note.position = Vector3(0.44, 0.0, 0.08) # (in front of the HOW TO PLAY sign; can be carried anywhere)
	note.rotation_degrees.y = -20.0 # turned a little towards you
	add_child(note)
	_note = note
	var wood := _mat(Color(0.3, 0.15, 0.07), 0.5, 0.0)
	var foot := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(0.11, 0.008, 0.03)
	foot.mesh = fm
	foot.position = Vector3(0, 0.004, -0.01)
	foot.material_override = wood
	note.add_child(foot)
	var card := Node3D.new()
	card.position = Vector3(0, 0.07, -0.012)
	card.rotation_degrees.x = -30.0 # leaning back on its stand
	note.add_child(card)
	var paper := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.115, 0.13, 0.0012)
	paper.mesh = pm
	paper.material_override = _mat(Color(0.97, 0.94, 0.84), 0.9, 0.0) # cream paper
	card.add_child(paper)
	var pin := MeshInstance3D.new() # a red push pin at the top
	var sm := SphereMesh.new()
	sm.radius = 0.004
	sm.height = 0.008
	pin.mesh = sm
	pin.material_override = _mat(Color(0.85, 0.12, 0.12), 0.4, 0.0)
	pin.position = Vector3(0, 0.058, 0.002)
	card.add_child(pin)
	var ink := Color(0.15, 0.1, 0.08)
	var title := Label3D.new()
	title.text = "HAND POINTS"
	title.font_size = 34
	title.pixel_size = 0.00045
	title.modulate = Color(0.7, 0.12, 0.12)
	title.outline_size = 0
	title.position = Vector3(0, 0.047, 0.0008)
	card.add_child(title)
	var row := 0
	for hand in HAND_POINTS: # one line per hand (in the dictionary's order: High Card ... Royal Flush)
		for col in 2: # the name on the left, its points on the right, on exactly the same line
			var l := Label3D.new()
			l.text = hand if col == 0 else "%d pts" % HAND_POINTS[hand]
			l.font_size = 22
			l.pixel_size = 0.00042
			l.modulate = ink
			l.outline_size = 0
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if col == 0 else HORIZONTAL_ALIGNMENT_RIGHT
			l.position = Vector3(-0.051 if col == 0 else 0.051, 0.033 - row * 0.0095, 0.0008)
			card.add_child(l)
		row += 1
	GameFont.apply_to(note)


## The HOW TO PLAY board stands where the info board is (press the sign again to close it).
func show_rules(on: bool) -> void:
	if on and not _rules.visible:
		_show_rules_page(0) # (opened again: from the start)
	_rules.visible = on
	_info.visible = false
	_enable_sign(HELP_PREV_ID, on)
	_enable_sign(HELP_NEXT_ID, on)


func _build_rules() -> void:
	_rules = Node3D.new()
	_rules.position = Vector3(0.0, 0.2, -0.5) # (above the blind chip and the cards on the table)
	_rules.rotation_degrees.x = -12.0 # leaning back a little, towards your eyes
	add_child(_rules)
	var frame := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(0.7, 0.5, 0.01)
	frame.mesh = fm
	frame.material_override = _mat(Color(0.85, 0.65, 0.25), 0.3, 0.8)
	frame.position.y = 0.25
	_rules.add_child(frame)
	var board := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.68, 0.48, 0.012)
	board.mesh = bm
	board.material_override = _mat(Color(0.12, 0.04, 0.1), 0.8, 0.0)
	board.position.y = 0.25
	_rules.add_child(board)
	var header := _rules_label("HOW TO PLAY SOLATRO", 34, Color(0.5, 1.8, 0.9), Vector3(0, 0.475, 0.007))
	header.outline_size = 8
	header.outline_modulate = Color(0.05, 0.03, 0.06)
	_rules_title = _rules_label("", 56, Color(1.0, 0.8, 0.35), Vector3(0, 0.428, 0.007))
	_rules_title.outline_size = 8
	_rules_title.outline_modulate = Color(0.05, 0.03, 0.06)
	_rules_body = Node3D.new() # one text block per paragraph (an empty line in a wrapped text would be dropped)
	_rules_body.position = Vector3(-0.31, 0.39, 0.007)
	_rules.add_child(_rules_body)
	_rules_page = _rules_label("", 32, Color(0.75, 0.7, 0.8), Vector3(0, 0.035, 0.007))
	# the buttons: < BACK and NEXT > at the bottom corners
	for k in 2:
		var at := Vector3(-0.26 if k == 0 else 0.26, 0.04, 0.0)
		var btn := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(0.11, 0.04, 0.012)
		btn.mesh = pm
		btn.material_override = _mat(Color(0.33, 0.45, 0.62) if k == 0 else Color(0.2, 0.62, 0.4), 0.5, 0.0)
		btn.position = at + Vector3(0, 0, 0.008)
		_rules.add_child(btn)
		var l := _rules_label("< BACK" if k == 0 else "NEXT >", 38, Color(1, 1, 1), at + Vector3(0, 0, 0.0145))
		if k == 1:
			_rules_next = l
		_body(_rules, HELP_PREV_ID if k == 0 else HELP_NEXT_ID, Vector3(0.12, 0.05, 0.03), at + Vector3(0, 0, 0.01))
	GameFont.apply_to(_rules)
	_rules.visible = false
	_show_rules_page(0)


func _rules_label(text: String, size: int, colour: Color, at: Vector3) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.0005
	l.modulate = colour
	l.outline_size = 0
	l.position = at
	_rules.add_child(l)
	return l


## The steps of the game, one page each (main.gd's buttons: BACK / NEXT on the board).
func _rules_pages() -> Array:
	var tokens: Array = []
	for t in TOKENS:
		tokens.append("%s (%d): %s" % [t["name"], t["cost"], t["text"].to_lower()])
	return [
		["Welcome!", "SOLATRO is a solo card game in the spirit of Balatro - the game idea comes from the YouTuber TechDweeb.\n\nYou play round after round with a normal deck of 52 cards and 2 jokers. Every round has a target score. Reach it and you go on - how many rounds can you survive?\n\nPress NEXT for the steps of a round."],
		["Step 1: Your round", "At the start of a round the deck is shuffled and you draw 8 cards into your hand.\n\nThe target grows every round: round 1 needs 25 points, round 2 needs 50, round 3 needs 75 and so on.\n\nYou have 3 PLAYS and 3 DISCARDS per round. The chip in the middle shows the round on its front and your plays and discards left on its back; the glass tube beside it fills up with your score."],
		["Step 2: Play a hand", "Select up to 5 cards with the beam and the trigger. Under your cards you see which poker hand they make and how many points it is worth.\n\nThen grab the selected cards with your grip and let go over the chip in the middle - or press A (X when left-handed).\n\nEvery poker hand scores fixed points: from High Card (5) up to Royal Flush (150). The little note on the table lists them all. After a play you draw back up to 8 cards."],
		["Step 3: Discard", "Cards you don't want? Select 1 to 5 of them, grab them and throw them over your shoulder - or press B (Y when left-handed).\n\nYou draw new cards for them right away. Use your 3 discards to build better hands!\n\nHold your hand over the deck to see which cards are still in it."],
		["Step 4: The jokers", "A joker you draw waits in your hand as a WILDCARD. Select it together with your cards and it becomes whatever card makes your hand best.\n\nBut careful: if you draw the second joker while the first one still waits in your hand, BOTH are gone - joke's on you, DWEEB!"],
		["Step 5: End of the round", "After your 3rd play the round ends.\n\nScore at least the target: the round is beaten, and every point ABOVE the target becomes a bonus point for the Bonus Shoppe.\n\nMiss the target: the game is over - unless you own a Shield."],
		["Step 6: The Bonus Shoppe", "Between the rounds the tokens stand on the sales counter. Grab one and pull it towards you to buy it with your bonus points (each token only once):\n\n" + "\n".join(tokens) + "\n\nBonus points you don't spend are lost. Press NEXT ROUND when you are ready."],
		["Step 7: Use your tokens", "Your tokens sit in the sockets of the stone pedestal. To use one during a round, grab it and place it in the well in the middle - or point at it and pull the trigger.\n\nYou can carry the pedestal to any place on the table you like.\n\nThe Shield works by itself: it saves you once when you miss a target."],
		["Game over", "When you miss a target without a Shield, the game ends. The board shows how far you came and your rank:\n\nRound 3: Cat Food\nRound 5: Little Dweeb\nRound 7: Official Dweeb\nRound 10: Ultra Mega Uber Giga-Dweeb\n\nYour best round is kept. PLAY AGAIN starts a new game. Good luck - and Safe Travels!"],
	]


func _show_rules_page(i: int) -> void:
	var pages := _rules_pages()
	_rules_index = clampi(i, 0, pages.size() - 1)
	_rules_title.text = pages[_rules_index][0]
	for c in _rules_body.get_children():
		c.free()
	var y := 0.0
	for para in str(pages[_rules_index][1]).split("\n\n"):
		var l := Label3D.new()
		l.text = para
		l.font_size = 40
		l.pixel_size = 0.0005
		l.width = 0.62 / l.pixel_size
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		l.modulate = Color(1.0, 0.95, 0.85)
		l.outline_size = 0
		l.position.y = y
		_rules_body.add_child(l)
		var font: Font = GameFont.font if GameFont.font != null else ThemeDB.fallback_font
		var h := font.get_multiline_string_size(para, HORIZONTAL_ALIGNMENT_LEFT, l.width, l.font_size, -1,
				TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE).y
		y -= h * l.pixel_size + 0.012 # (and a gap between the paragraphs)
	_rules_page.text = "%d / %d" % [_rules_index + 1, pages.size()]
	_rules_next.text = "CLOSE" if _rules_index == pages.size() - 1 else "NEXT >"
	GameFont.apply_to(_rules)


func try_grab(hand: Node3D) -> bool:
	if not visible or _held != null:
		return false
	# the chip nearest to the hand (measured from its middle): with several close together the right one
	var best := ""
	var best_d := 0.07
	for key in _chips:
		var chip: Node3D = _chips[key]
		var d := (chip.global_position + global_basis.y.normalized() * 0.025).distance_to(hand.global_position) # (the token's middle)
		if d < best_d:
			best = key
			best_d = d
	if best != "":
		_held = _chips[best]
		_held_key = best
		_held_hand = hand
		_held_offset = HOLD_IN_HAND # into the hand (not where it was): it sits between the fingers
		return true
	# the pedestal itself: carried to another spot on the board
	if (_bowl.global_position + global_basis.y.normalized() * 0.02).distance_to(hand.global_position) < PEDESTAL_R:
		_held = _bowl
		_held_key = ""
		_held_hand = hand
		_held_bowl_offset = hand.global_transform.affine_inverse() * _bowl.global_transform
		return true
	# the HAND POINTS card: carried anywhere, turned and tilted any way
	if _note != null and (_note.global_transform * Vector3(0, 0.07, -0.012)).distance_to(hand.global_position) < 0.09:
		_held = _note
		_held_key = ""
		_held_hand = hand
		_held_note_offset = hand.global_transform.affine_inverse() * _note.global_transform
		return true
	return false


## The HAND POINTS card where it was put last time (in the Solatro table's own space).
func set_note(xf: Transform3D) -> void:
	if _note != null:
		_note.transform = xf


## The bowl, put down: upright, on the joker board where it was let go.
func set_bowl(at: Vector3) -> void:
	if _bowl == null:
		return
	var p := Vector2(at.x, at.z)
	if clamp_board.is_valid():
		p = clamp_board.call(p)
	_bowl.transform = Transform3D(Basis(), Vector3(p.x, 0.0, p.y))


func holds(hand: Node3D) -> bool:
	return _held != null and _held_hand == hand


func release(hand: Node3D) -> void:
	if not holds(hand):
		return
	var local := to_local(_held.global_position)
	var was := _held
	_held = null
	if was == _bowl:
		set_bowl(local)
		bowl_moved.emit(_bowl.position)
		return
	if was == _note:
		note_moved.emit(_note.transform)
		return
	if Vector2(local.x - _bowl.position.x, local.z - _bowl.position.z).length() < CENTRE_R + 0.015 and local.y < 0.3:
		_use_token(_held_key) # into the well in the middle: used (anywhere else: back to its socket)


func _animate_chips(delta: float) -> void:
	var k := 1.0 - exp(-12.0 * delta)
	if _held == _bowl and is_instance_valid(_held_hand): # the bowl in the hand
		var g := _held_hand.global_transform * _held_bowl_offset
		_bowl.global_transform = Transform3D(global_basis.orthonormalized(), g.origin) # (stays upright)
	if _held == _note and is_instance_valid(_held_hand): # the HAND POINTS card in the hand
		_note.global_transform = _held_hand.global_transform * _held_note_offset
	for key in _chips:
		var chip: Node3D = _chips[key]
		if chip == _held:
			if is_instance_valid(_held_hand): # (glides into the hand in a moment, then stays there)
				chip.global_transform = chip.global_transform.interpolate_with(_held_hand.global_transform * _held_offset, 1.0 - exp(-30.0 * delta))
			continue
		var home: Vector3 = _bowl.transform * socket_pos(int(chip.get_meta("socket", 0)))
		chip.transform = chip.transform.interpolate_with(Transform3D(Basis(), home), k)
	if _rune_flash > 0.0:
		_rune_flash = maxf(_rune_flash - delta * 1.6, 0.0)
		_rune_mat.emission_energy_multiplier = 2.5 * _rune_flash


func _make_chip(t: Dictionary, index: int) -> Node3D:
	var node := Node3D.new()
	add_child(node)
	node.add_child(token_model(t["key"])) # the token itself, ready to be thrown into the bowl
	var l := Label3D.new() # its name, small, floating above it
	l.text = str(t["name"])
	l.font_size = 22
	l.pixel_size = 0.0004
	l.outline_size = 6
	l.outline_modulate = Color(0.05, 0.03, 0.06)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position.y = 0.075
	l.name = "Name"
	l.visible = not _hints_off
	node.add_child(l)
	GameFont.apply_to(node)
	_body(node, CHIP_ID - index, Vector3(0.05, 0.07, 0.05), Vector3(0, 0.03, 0))
	return node


## Where token i sits on the pedestal (in the pedestal's space): round the edge, the first one at
## the front, the others going round.
static func socket_pos(i: int) -> Vector3:
	var a := PI * 0.5 + TAU * i / TOKENS.size()
	return Vector3(cos(a) * SOCKET_R, PEDESTAL_TOP + 0.001, sin(a) * SOCKET_R)


## The token pedestal: a six-sided stone plinth with a socket for each token round its edge (a token
## you buy sits there) and a dark well with a ring of runes in the middle - place a token there and
## it is used. Matt stone and dark bronze, no glow (the runes only light up when a token is used).
func _build_bowl() -> void:
	var root := Node3D.new()
	_bowl = root
	root.position = BOWL_POS
	add_child(root)
	var stone := _mat(Color(0.4, 0.39, 0.37), 0.95, 0.0)
	var top_stone := _mat(Color(0.5, 0.49, 0.46), 0.9, 0.0)
	var dark := _mat(Color(0.07, 0.065, 0.06), 1.0, 0.0)
	_bowl_mat = _mat(FITTING, 0.6, 0.5)
	_rune_mat = _mat(FITTING, 0.6, 0.5)
	_rune_mat.emission_enabled = true
	_rune_mat.emission = Color(0.55, 0.8, 1.0)
	_rune_mat.emission_energy_multiplier = 0.0
	_slab6(root, PEDESTAL_R, 0.022, 0.011, stone)                  # the plinth ...
	_slab6(root, PEDESTAL_R - 0.012, 0.006, 0.025, top_stone)      # ... and its top
	for i in TOKENS.size(): # the sockets: a dark recess in a metal ring
		var p := socket_pos(i)
		_disc(root, 0.017, Vector3(p.x, PEDESTAL_TOP + 0.0004, p.z), dark)
		_ring(root, 0.0165, 0.021, Vector3(p.x, PEDESTAL_TOP + 0.0015, p.z), _bowl_mat)
	# the well in the middle, with its ring of runes (short engraved strokes)
	_disc(root, CENTRE_R - 0.006, Vector3(0, PEDESTAL_TOP + 0.0004, 0), dark)
	_ring(root, CENTRE_R - 0.006, CENTRE_R, Vector3(0, PEDESTAL_TOP + 0.0015, 0), _rune_mat)
	for k in 12:
		var a := TAU * k / 12.0
		var mark := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.0016, 0.0012, 0.008 if k % 3 == 0 else 0.005)
		mark.mesh = bm
		mark.material_override = _rune_mat
		mark.position = Vector3(cos(a) * (CENTRE_R + 0.008), PEDESTAL_TOP + 0.0006, sin(a) * (CENTRE_R + 0.008))
		mark.rotation.y = -a + (0.35 if k % 2 == 0 else -0.35)
		root.add_child(mark)
	var l := Label3D.new()
	_pedestal_label = l
	l.text = "USE A TOKEN:\nPLACE IT IN THE MIDDLE"
	l.font_size = 26
	l.pixel_size = 0.0006
	l.outline_size = 6
	l.outline_modulate = Color(0.05, 0.03, 0.06)
	l.modulate = Color(1.0, 0.85, 0.4)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position.y = 0.1
	root.add_child(l)


## The help over the pedestal and the names over the tokens: shown until the first token of a game
## is used, then hidden (easier to read the table); a new game shows them again.
func _show_token_hints(on: bool) -> void:
	_hints_off = not on
	if _pedestal_label != null:
		_pedestal_label.visible = on
	for key in _chips:
		var name_label := (_chips[key] as Node3D).get_node_or_null("Name")
		if name_label != null:
			name_label.visible = on


## A six-sided stone slab (radius to its corners), height h, centred at height y.
func _slab6(parent: Node3D, r: float, h: float, y: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 6
	c.rings = 1
	mi.mesh = c
	mi.material_override = mat
	mi.position.y = y
	parent.add_child(mi)


## A thin flat disc lying on the pedestal.
func _disc(parent: Node3D, r: float, at: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = 0.0008
	c.radial_segments = 24
	c.rings = 1
	mi.mesh = c
	mi.material_override = mat
	mi.position = at
	parent.add_child(mi)


## A flat metal ring lying on the pedestal (inner and outer radius).
func _ring(parent: Node3D, inner: float, outer: float, at: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	t.rings = 28
	t.ring_segments = 6
	mi.mesh = t
	mi.material_override = mat
	mi.position = at
	mi.scale = Vector3(1.0, 0.4, 1.0) # (flat)
	parent.add_child(mi)


func _build_sign(text: String, id: int, at: Vector3, colour: Color, board_colour := Color(0.05, 0.03, 0.06)) -> Node3D:
	var root := Node3D.new()
	root.position = at
	add_child(root)
	var post := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.006, 0.07, 0.006)
	post.mesh = pm
	post.position.y = 0.035
	post.material_override = _mat(Color(0.2, 0.2, 0.22), 0.5, 0.5)
	root.add_child(post)
	var board := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.13, 0.075, 0.014)
	board.mesh = bm
	board.position.y = 0.105
	board.material_override = _mat(board_colour, 0.5, 0.0)
	root.add_child(board)
	var l := Label3D.new()
	l.text = text
	l.font_size = 40
	l.pixel_size = 0.0008
	l.modulate = colour
	l.outline_size = 8
	l.outline_modulate = Color(0.05, 0.03, 0.06)
	l.position = Vector3(0, 0.105, 0.0075)
	root.add_child(l)
	_body(root, id, Vector3(0.14, 0.09, 0.04), Vector3(0, 0.105, 0))
	return root


func _enable_sign(id: int, on: bool) -> void:
	for b in _bodies:
		if is_instance_valid(b) and int(b.get_meta("target_id")) == id:
			b.collision_layer = 1 if (on and is_visible_in_tree()) else 0


func _body(parent: Node3D, id: int, size: Vector3, pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.set_meta("target_id", id)
	body.set_meta("kind", "solatro")
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	shape.shape = bs
	body.add_child(shape)
	body.position = pos
	parent.add_child(body)
	_bodies.append(body)


## Hidden objects must not be hit: an invisible body still stops the beam in Godot.
func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		_bodies = _bodies.filter(func(b): return is_instance_valid(b))
		var on := is_visible_in_tree()
		for b in _bodies:
			var id := int(b.get_meta("target_id"))
			var sign_on: bool = not (id == AGAIN_ID or id == MENU_ID) or _phase == "over"
			if id == HELP_PREV_ID or id == HELP_NEXT_ID:
				sign_on = _rules != null and _rules.visible
			b.collision_layer = 1 if (on and sign_on) else 0


func _mat(colour: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = rough
	m.metallic = metal
	return m


# ---------------------------------------------------------------- the tokens as little models
# On the counter and on the table each token is a small object that says what it does (about 5 cm):
#   Extra Card      a card sticking out of a card shoe     Extra Discard  a golden waste bin
#   Pocket Points   a leather pouch spilling chips, "+25"   Extra Hand     a white glove, finger up
#   Double Score    a little "x2" sign                      Shield         a green and gold shield

static func token_model(key: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Token"
	match key:
		"extra_card":
			var shoe := _tm_box(root, Vector3(0.04, 0.022, 0.03), Vector3(0, 0.011, 0), _tm_mat(Color(0.12, 0.25, 0.15), 0.6, 0.0))
			shoe.rotation_degrees.x = -10.0
			_tm_box(root, Vector3(0.042, 0.004, 0.032), Vector3(0, 0.024, 0), _tm_mat(Color(0.85, 0.65, 0.25), 0.3, 0.8))
			var card := _tm_box(root, Vector3(0.025, 0.036, 0.0015), Vector3(0, 0.038, 0.004), _tm_mat(Color(0.97, 0.96, 0.92), 0.6, 0.0))
			card.rotation_degrees.x = -15.0
			_tm_label(card, "+1", 64, Color(0.85, 0.15, 0.2), Vector3(0, 0, 0.001))
		"extra_discard":
			var gold := _tm_mat(Color(0.92, 0.7, 0.25), 0.3, 0.8)
			_tm_cyl(root, 0.017, 0.013, 0.036, Vector3(0, 0.018, 0), gold)
			var lid := _tm_cyl(root, 0.019, 0.019, 0.004, Vector3(0.006, 0.04, 0), gold)
			lid.rotation_degrees.z = 20.0 # (a little open)
			_tm_sph(lid, 0.004, Vector3(0, 0.004, 0), gold)
			for i in 6: # ribs
				var a := TAU * i / 6.0
				_tm_box(root, Vector3(0.002, 0.034, 0.002), Vector3(cos(a) * 0.0155, 0.018, sin(a) * 0.0155), _tm_mat(Color(0.7, 0.5, 0.15), 0.4, 0.8))
		"pocket_points":
			var leather := _tm_mat(Color(0.45, 0.25, 0.1), 0.8, 0.0)
			_tm_sph(root, 0.02, Vector3(0, 0.019, 0), leather).scale = Vector3(1, 0.9, 1)
			_tm_cyl(root, 0.008, 0.012, 0.012, Vector3(0, 0.04, 0), leather)
			var cord := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = 0.008
			tm.outer_radius = 0.0095
			cord.mesh = tm
			cord.material_override = _tm_mat(Color(0.85, 0.65, 0.25), 0.4, 0.6)
			cord.position.y = 0.036
			root.add_child(cord)
			var chip_cols := [Color(0.9, 0.2, 0.2), Color(0.2, 0.45, 0.95), Color(0.95, 0.95, 0.9)]
			for i in 3: # chips spilling out
				var c := _tm_cyl(root, 0.007, 0.007, 0.002, Vector3(0.015 + i * 0.006, 0.003 + i * 0.002, 0.012 - i * 0.004), _tm_mat(chip_cols[i], 0.4, 0.1))
				c.rotation_degrees = Vector3(20 * i, 0, 15)
			_tm_label(root, "+25", 56, Color(1.0, 0.85, 0.3), Vector3(0, 0.022, 0.0205))
		"extra_hand":
			var white := _tm_mat(Color(0.97, 0.96, 0.93), 0.55, 0.0)
			_tm_cyl(root, 0.011, 0.012, 0.012, Vector3(0, 0.006, 0), _tm_mat(Color(0.85, 0.15, 0.2), 0.5, 0.0)) # red cuff
			_tm_sph(root, 0.013, Vector3(0, 0.022, 0), white).scale = Vector3(1.0, 1.1, 0.6)  # palm
			_tm_cyl(root, 0.0035, 0.004, 0.026, Vector3(0.002, 0.045, 0.002), white)             # index finger up
			_tm_sph(root, 0.0037, Vector3(0.002, 0.058, 0.002), white)
			for k in 3: # the other fingers curled
				_tm_sph(root, 0.0045, Vector3(-0.005 + k * 0.0055, 0.031, 0.008), white)
			_tm_sph(root, 0.0045, Vector3(0.012, 0.02, 0.004), white) # thumb
		"double_score":
			_tm_cyl(root, 0.012, 0.014, 0.004, Vector3(0, 0.002, 0), _tm_mat(Color(0.2, 0.12, 0.08), 0.5, 0.2))
			_tm_cyl(root, 0.002, 0.002, 0.03, Vector3(0, 0.017, 0), _tm_mat(Color(0.6, 0.6, 0.65), 0.3, 0.8))
			var sign := _tm_box(root, Vector3(0.04, 0.026, 0.004), Vector3(0, 0.044, 0), _tm_mat(Color(0.97, 0.96, 0.92), 0.5, 0.0))
			_tm_box(sign, Vector3(0.043, 0.029, 0.003), Vector3(0, 0, -0.001), _tm_mat(Color(0.85, 0.15, 0.2), 0.4, 0.0))
			_tm_label(sign, "x2", 96, Color(0.9, 0.15, 0.2), Vector3(0, 0, 0.0025))
			_tm_label(sign, "x2", 96, Color(0.9, 0.15, 0.2), Vector3(0, 0, -0.0035), true)
		"shield":
			var pts := PackedVector2Array([Vector2(-0.018, 0.024), Vector2(0.018, 0.024), Vector2(0.018, 0.008), Vector2(0.012, -0.006),
					Vector2(0, -0.016), Vector2(-0.012, -0.006), Vector2(-0.018, 0.008)])
			var holder := Node3D.new()
			holder.position.y = 0.03
			holder.rotation_degrees.x = -12.0
			root.add_child(holder)
			var rim := MeshInstance3D.new()
			rim.mesh = _tm_slab(pts, 0.004, 1.15)
			rim.material_override = _tm_mat(Color(0.9, 0.7, 0.25), 0.3, 0.8)
			holder.add_child(rim)
			var face := MeshInstance3D.new()
			face.mesh = _tm_slab(pts, 0.006, 1.0)
			face.material_override = _tm_mat(Color(0.15, 0.55, 0.3), 0.4, 0.2)
			holder.add_child(face)
			_tm_label(holder, "S", 90, Color(1.0, 0.82, 0.3), Vector3(0, 0.006, 0.0035))
			_tm_box(root, Vector3(0.03, 0.006, 0.014), Vector3(0, 0.003, -0.004), _tm_mat(Color(0.2, 0.12, 0.08), 0.5, 0.2)) # its stand
	GameFont.apply_to(root)
	return root


static func _tm_mat(c: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


static func _tm_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi


static func _tm_cyl(parent: Node3D, top: float, bottom: float, h: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = 20
	mi.mesh = c
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi


static func _tm_sph(parent: Node3D, r: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	mi.mesh = s
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi


static func _tm_label(parent: Node3D, text: String, size: int, colour: Color, pos: Vector3, back := false) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.0002
	l.modulate = colour
	l.outline_size = 0
	l.position = pos
	if back:
		l.rotation_degrees.y = 180.0
	parent.add_child(l)


## A flat outline as a slab (front, back and sides), scaled around its centre.
static func _tm_slab(poly: PackedVector2Array, depth: float, scl: float) -> ArrayMesh:
	var pts := PackedVector2Array()
	for p in poly:
		pts.append(p * scl)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var idx := Geometry2D.triangulate_polygon(pts)
	for side in [1.0, -1.0]:
		for k in range(0, idx.size(), 3):
			var order := [k, k + 1, k + 2] if side > 0 else [k, k + 2, k + 1]
			for o in order:
				st.set_normal(Vector3(0, 0, side))
				st.add_vertex(Vector3(pts[idx[o]].x, pts[idx[o]].y, side * depth * 0.5))
	for i in pts.size():
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		var n := Vector3(b.y - a.y, a.x - b.x, 0).normalized()
		for v in [Vector3(a.x, a.y, depth * 0.5), Vector3(b.x, b.y, depth * 0.5), Vector3(b.x, b.y, -depth * 0.5),
				Vector3(a.x, a.y, depth * 0.5), Vector3(b.x, b.y, -depth * 0.5), Vector3(a.x, a.y, -depth * 0.5)]:
			st.set_normal(n)
			st.add_vertex(v)
	return st.commit()
