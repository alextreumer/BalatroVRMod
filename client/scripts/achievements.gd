class_name Achievements
extends Node
## VR achievements: things only VR lets you do (tear packs with both hands, push jokers around ...).
## Each one has a goal (a count), and once reached it unlocks a reward that only changes how VR looks
## - nothing that makes a run easier. Rewards start switched on and can be switched off in the
## Achievements page of the VR menu (≡). Saved in their own file, apart from the layout.

signal unlocked(id: String)
signal rewards_changed

const FILE := "user://vr_achievements.cfg"
## The colours a reward can be had in (its button cycles them; "Off" = the normal look).
const METALS := ["Off", "Gold", "Silver", "Rose Gold", "Emerald", "Sapphire", "Amethyst", "Turquoise", "Pearl"]
const METAL_COLOURS := {"Gold": Color(0.95, 0.72, 0.25), "Silver": Color(0.82, 0.84, 0.9), "Rose Gold": Color(0.93, 0.58, 0.52),
	"Emerald": Color(0.08, 0.62, 0.32), "Sapphire": Color(0.12, 0.3, 0.85), "Amethyst": Color(0.58, 0.25, 0.88),
	"Turquoise": Color(0.1, 0.78, 0.78), "Pearl": Color(0.96, 0.92, 0.9)}
## (the first list had Ruby at 4, Emerald 5, Sapphire 6: Ruby was too close to the royal red felt)
const METALS_V1_TO_V2 := {4: 6, 5: 4, 6: 5}
const LIST := [
	{"id": "welcome", "name": "Welcome to the Casino", "text": "Start your first run in VR", "goal": 1,
		"reward": "VIP neon sign in the casino"},
	{"id": "rip_it", "name": "RIP IT!", "text": "Tear 10 booster packs open with both hands", "goal": 10,
		"reward": "Confetti when you tear a pack"},
	{"id": "bowling", "name": "Bowling Alley", "text": "Push 3 jokers aside with one joker at once", "goal": 3,
		"reward": "Marble pedestals for your jokers"},
	{"id": "neat_freak", "name": "Neat Freak", "text": "Move deck, money, coin slot and card stand", "goal": 4,
		"reward": "Royal blue casino table felt", "group": "felt"},
	{"id": "coin_slot", "name": "Coin Slot Regular", "text": "Sell 25 jokers through the coin slot", "goal": 25,
		"reward": "A coin slot in your colour", "choices": METALS},
	{"id": "lady_luck", "name": "Lady Luck", "text": "Spin WIN! on the wheel (Real mode)", "goal": 1,
		"reward": "Las Vegas wheel with light bulbs", "group": "wheel"},
	{"id": "sky_high", "name": "Sky High", "text": "Score 10 times what a blind needs", "goal": 1,
		"reward": "Purple & gold score tower chips"},
	{"id": "close_call", "name": "Close Call", "text": "Beat a blind by less than 5 percent", "goal": 1,
		"reward": "Green glowing score tower ring"},
	{"id": "high_roller", "name": "High Roller", "text": "Win a run in VR", "goal": 1,
		"reward": "Royal red casino table felt", "group": "felt"},
	{"id": "nope_x5", "name": "Nope Nope Nope", "text": "Spin NOPE! 5 times in a row", "goal": 5,
		"reward": "Midnight black table felt", "group": "felt"},
	{"id": "giga_dweeb", "name": "Ultra Mega Uber Giga-Dweeb", "text": "Reach round 10 in Solatro", "goal": 1,
		"reward": "TechDweeb's orange & black stripes", "group": "felt"},
	{"id": "over_shoulder", "name": "Over the Shoulder", "text": "Throw 50 cards over your shoulder", "goal": 50,
		"reward": "Sparks behind thrown cards"},
	{"id": "one_armed", "name": "One-Armed Bandit", "text": "Pull the reroll lever 50 times", "goal": 50,
		"reward": "A lever in your colour, coin sounds", "choices": METALS},
	{"id": "pack_rat", "name": "Pack Rat", "text": "Tear 100 booster packs open", "goal": 100,
		"reward": "Gloves in your colour", "group": "gloves", "choices": METALS},
	{"id": "three_row", "name": "High Five", "text": "Spin WIN! 5 times (Real mode)", "goal": 5,
		"reward": "A wheel in your colour", "group": "wheel", "choices": METALS},
	{"id": "card_sharp", "name": "Card Sharp", "text": "Play 10 hands in a row by grabbing them", "goal": 10,
		"reward": "A gold flash when your cards land"},
	{"id": "shuffle_master", "name": "Shuffle Master", "text": "Sort your hand 50 times (stick click)", "goal": 50,
		"reward": "Your cards glitter when you sort them"},
	{"id": "mountain", "name": "Mountain Climber", "text": "Grow the second chip mountain (2 million+)", "goal": 1,
		"reward": "A summit flag on the chip mountain"},
	{"id": "boss_slayer", "name": "Boss Slayer", "text": "Beat 10 boss blinds in VR", "goal": 10,
		"reward": "Your last boss chip as a trophy by the deck"},
	{"id": "big_spender", "name": "Big Spender", "text": "Spend $100 in one shop", "goal": 100,
		"reward": "A sales counter in your colour", "choices": METALS},
	{"id": "spin_doctor", "name": "Spin Doctor", "text": "Swipe the wheel as hard as you can", "goal": 1,
		"reward": "Sparks fly from the wheel's rim"},
	{"id": "jokes_on_you", "name": "Joke's on You", "text": "Lose both jokers in Solatro", "goal": 1,
		"reward": "Jimbo laughs at your bad luck"},
	{"id": "royal", "name": "Royal Treatment", "text": "Play a Royal Flush in Solatro", "goal": 1,
		"reward": "Golden Solatro cards"},
	{"id": "ovation", "name": "Standing Ovation", "text": "Win a run in standing mode", "goal": 1,
		"reward": "Applause when you win"},
	{"id": "streamer", "name": "Streamer", "text": "Play 1 hour with the spectator window on", "goal": 60,
		"reward": "LIVE neon sign in the casino"},
	{"id": "stargazer", "name": "Stargazer", "text": "Use 25 planet cards in VR", "goal": 25,
		"reward": "A starry sky in the casino"},
	{"id": "fortune_teller", "name": "Fortune Teller", "text": "Use 25 tarot cards in VR", "goal": 25,
		"reward": "The card stand glows mystic purple"},
	{"id": "ghost_hunter", "name": "Ghost Hunter", "text": "Use 10 spectral cards in VR", "goal": 10,
		"reward": "The Spectral Lounge haunts more often"},
	{"id": "glass_breaker", "name": "Glass Breaker", "text": "Break 10 glass cards", "goal": 10,
		"reward": "Glass shards stay on the table all run"},
	{"id": "real_full_house", "name": "Real Full House", "text": "Have 7 jokers at once", "goal": 1,
		"reward": "Spotlights over your jokers"},
	{"id": "endless", "name": "Endless", "text": "Reach ante 9 in VR (endless mode)", "goal": 1,
		"reward": "ENDLESS neon sign in the casino"},
	{"id": "peeking", "name": "Peeking", "text": "Look into the deck 50 times", "goal": 50,
		"reward": "Deck edges in your colour", "choices": METALS},
	{"id": "vradar", "name": "UnderTheVRadar", "text": "Press Subscribe on the YouTube sign", "goal": 1,
		"reward": "Your name on the wall, a radar, Jimbo in VR"},
	{"id": "ambidextrous", "name": "Ambidextrous", "text": "Switch hands and win a blind that way", "goal": 1,
		"reward": "Two-coloured gloves like Jimbo's", "group": "gloves"},
	{"id": "laser_pointer", "name": "Laser Pointer", "text": "Click 500 times with the beam", "goal": 500,
		"reward": "Beam colour of your choice", "choices": ["Cyan", "Pink", "Gold", "Green"]},
	{"id": "hand_model", "name": "Hand Model", "text": "Play with Hands off, then switch them on", "goal": 1,
		"reward": "Neon gloves that glow", "group": "gloves"},
	{"id": "long_haul", "name": "Long Haul", "text": "Change your jokers' order 50 times", "goal": 50,
		"reward": "Carried jokers leave a glitter trail"},
	{"id": "price_check", "name": "Price Check", "text": "Lift a joker and read its price 20 times", "goal": 20,
		"reward": "Price stickers in your colour", "choices": METALS},
	{"id": "window_shopper", "name": "Window Shopper", "text": "Take 20 things off the counter and put them back", "goal": 20,
		"reward": "A shop bell rings when you take something"},
	{"id": "up_close", "name": "Up Close", "text": "Put your head right next to a joker", "goal": 1,
		"reward": "Jokers turn to look at you up close"},
	{"id": "lever_frenzy", "name": "Lever Frenzy", "text": "Pull the reroll lever 5 times in 10 seconds", "goal": 1,
		"reward": "The slot machine flashes in rainbow colours"},
	{"id": "safe_travels", "name": "Safe Travels", "text": "Win a blind, then quit VR from the menu", "goal": 1,
		"reward": "SAFE TRAVELS! on the exit signs, a goodbye"},
	{"id": "going_up", "name": "Going Up!", "text": "Set the floor height all the way up and all the way down", "goal": 2,
		"reward": "An elevator ding when the floor moves"},
	{"id": "hands_on", "name": "Hands On", "text": "Buy 20 things by grabbing them off the counter", "goal": 20,
		"reward": "A shop bell that rings when you buy"},
	{"id": "say_cheese", "name": "Say Cheese!", "text": "Take a photo while the Photograph joker is yours", "goal": 1,
		"reward": "Photos get an instant-photo frame"},
	{"id": "heartbreaker", "name": "Heartbreaker", "text": "Beat the Crimson Heart in VR", "goal": 1,
		"reward": "The heart bursts into a rain of little hearts"},
	{"id": "planet_hopper", "name": "Planet Hopper", "text": "Have 6 different planets in orbit at once", "goal": 1,
		"reward": "The planets draw glowing trails"},
	{"id": "curator", "name": "Curator", "text": "Look at 50 things in the VR collection", "goal": 50,
		"reward": "Cabinet in your colour, glass doors", "choices": METALS},
	{"id": "five_kind", "name": "High Five-of-a-Kind", "text": "Play Five of a Kind 10 times in VR", "goal": 10,
		"reward": "Five flames for a Five of a Kind"},
	{"id": "token_hoarder", "name": "Token Hoarder", "text": "Buy all 6 tokens in one game of Solatro", "goal": 1,
		"reward": "The token bowl glows in your colour", "choices": METALS},
	{"id": "bargain", "name": "Bargain Hunter", "text": "Buy 10 things for $2 or less (or free)", "goal": 10,
		"reward": "SALE! stickers on cheap things in the shop"},
	{"id": "pack_surgeon", "name": "Pack Surgeon", "text": "Hold a pack with both hands for 3 s, then tear it", "goal": 1,
		"reward": "Packs burst into confetti in their own colours"},
	{"id": "hot_streak", "name": "Hot Streak", "text": "Win 3 blinds in a row with your first hand", "goal": 3,
		"reward": "Tower flames up on first-hand wins"},
	{"id": "glass_cannon", "name": "Glass Cannon", "text": "Win a blind with a hand of 3 glass cards", "goal": 1,
		"reward": "Glass cards sparkle in your hand"},
	{"id": "collector", "name": "Collector", "text": "Unlock 40 other achievements", "goal": 40,
		"reward": "Table felt in your colour", "group": "felt", "choices": METALS},
]

var file := FILE                    # (tests use their own)
var _progress := {}                 # id -> count
var _done := {}                     # id -> true
var _reward_on := {}                # id -> bool
var _seen := {}                     # id -> {key: true}: things counted once (e.g. which item was moved)
var _extra := {}                    # things a reward remembers (e.g. the last boss chip beaten)


func _ready() -> void:
	load_data()


func load_data() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(file) != OK:
		return
	var metals_v := int(cfg.get_value("meta", "metals", 1))
	for a in LIST:
		var id: String = a["id"]
		_progress[id] = int(cfg.get_value("progress", id, 0))
		if cfg.get_value("done", id, false):
			_done[id] = true
		_reward_on[id] = bool(cfg.get_value("reward", id, true))
		if cfg.has_section_key("extra", id):
			_extra[id] = cfg.get_value("extra", id)
		if metals_v < 2 and a.get("choices") == METALS and METALS_V1_TO_V2.has(choice(id)):
			_extra[id] = METALS_V1_TO_V2[choice(id)] # (saved with the first colour list)
		if a.has("choices") and _done.has(id) and bool(_reward_on.get(id, true)) and choice(id) == 0:
			_extra[id] = 1 # (from before there were choices: on = the first one, gold)
		var seen = cfg.get_value("seen", id, [])
		if seen is Array:
			_seen[id] = {}
			for k in seen:
				_seen[id][str(k)] = true
	if metals_v < 2:
		save_data() # (the colours moved to the new list: saved right away, so it happens only once)


func save_data() -> void:
	var cfg := ConfigFile.new()
	for a in LIST:
		var id: String = a["id"]
		cfg.set_value("progress", id, int(_progress.get(id, 0)))
		cfg.set_value("done", id, _done.has(id))
		cfg.set_value("reward", id, bool(_reward_on.get(id, true)))
		if _seen.has(id):
			cfg.set_value("seen", id, (_seen[id] as Dictionary).keys())
		if _extra.has(id):
			cfg.set_value("extra", id, _extra[id])
	cfg.set_value("meta", "metals", 2)
	cfg.save(file)


static func info(id: String) -> Dictionary:
	for a in LIST:
		if a["id"] == id:
			return a
	return {}


## A streak broke (e.g. NOPE! after two WIN!s): back to 0, unless it was already reached.
func reset(id: String) -> void:
	if _done.has(id) or int(_progress.get(id, 0)) == 0:
		return
	_progress[id] = 0
	save_data()


## One more towards the goal.
func add(id: String, n := 1) -> void:
	if _done.has(id) or info(id).is_empty():
		return
	_progress[id] = int(_progress.get(id, 0)) + n
	_check(id)
	save_data()


## The best so far in one go (e.g. jokers pushed with one joker): counts if it beats the old best.
func reach(id: String, value: int) -> void:
	if _done.has(id) or value <= int(_progress.get(id, 0)):
		return
	_progress[id] = value
	_check(id)
	save_data()


## Something that counts only once (e.g. each board item moved once).
func add_once(id: String, key: String) -> void:
	if _done.has(id):
		return
	if not _seen.has(id):
		_seen[id] = {}
	if _seen[id].has(key):
		return
	_seen[id][key] = true
	_progress[id] = (_seen[id] as Dictionary).size()
	_check(id)
	save_data()


func _check(id: String) -> void:
	if int(_progress.get(id, 0)) >= int(info(id).get("goal", 1)):
		_progress[id] = int(info(id)["goal"])
		_done[id] = true
		_switch_on(id) # a new reward is shown at once (the others of its group step back)
		unlocked.emit(id)
		rewards_changed.emit()
	if id != "collector" and not _done.has("collector"): # Collector: all the others
		var others := 0
		for a in LIST:
			if a["id"] != "collector" and _done.has(a["id"]):
				others += 1
		_progress["collector"] = others
		_check("collector")


## Rewards of one group (table felts, wheel looks) exclude each other: only one is on.
## A reward with choices (e.g. the beam colour): which one (0 = the normal look = off).
func choice(id: String) -> int:
	return int(_extra.get(id, 0))


func cycle_choice(id: String) -> void:
	var n: int = (info(id).get("choices", []) as Array).size()
	if n == 0:
		return
	var now := choice(id) if reward(id) else 0 # (switched off by another of its group: starts again)
	_extra[id] = (now + 1) % n
	if choice(id) > 0:
		_switch_on(id)
	else:
		_reward_on[id] = false
	save_data()
	rewards_changed.emit()


func _switch_on(id: String) -> void:
	if info(id).has("choices") and choice(id) == 0:
		_extra[id] = 1 # newly unlocked: show the first new choice
	var group := str(info(id).get("group", ""))
	if group != "":
		for a in LIST:
			if a["id"] != id and str(a.get("group", "")) == group:
				_reward_on[a["id"]] = false
	_reward_on[id] = true


func set_extra(id: String, value) -> void:
	_extra[id] = value
	save_data()
	rewards_changed.emit()


## The colour a reward with METALS is shown in (alpha 0: it is off).
func metal(id: String) -> Color:
	if not reward(id) or not info(id).has("choices"):
		return Color(0, 0, 0, 0)
	var pick: String = (info(id)["choices"] as Array)[choice(id)]
	return METAL_COLOURS.get(pick, Color(0, 0, 0, 0))


func extra(id: String):
	return _extra.get(id)


func is_done(id: String) -> bool:
	return _done.has(id)


func progress(id: String) -> int:
	return int(_progress.get(id, 0))


func done_count() -> int:
	return _done.size()


## Is this achievement's reward to be shown? (only once it is unlocked)
func reward(id: String) -> bool:
	return _done.has(id) and bool(_reward_on.get(id, true))


func set_reward(id: String, on: bool) -> void:
	if on:
		_switch_on(id)
	else:
		_reward_on[id] = false
	save_data()
	rewards_changed.emit()
