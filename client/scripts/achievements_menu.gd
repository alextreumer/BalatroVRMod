class_name AchievementsMenu
extends Node3D
## The Achievements page of the VR menu (≡ -> Achievements), fixed above the card hand like the menu:
## grouped by what the reward changes (gloves & beam, the table, the shop ...): a coloured heading for
## each group, the unlocked ones first in it; a row per achievement with a trophy (gold once unlocked),
## its name, what to do and how far you are - and once unlocked its reward with an ON / OFF switch (or
## its colour). Clicked with the beam.

const WIDTH := 0.32
const ROW := 0.04
const PER_PAGE := 13              # rows' worth of height per page (a group's heading is a thinner row)
const HEAD := 0.026                # height of a group's heading
## The groups, by what the reward changes, each with its colour (a heading, and a strip on its rows).
const GROUPS := [
	["GLOVES & BEAM", Color(0.4, 0.75, 1.0), ["pack_rat", "ambidextrous", "hand_model", "laser_pointer", "long_haul"]],
	["TABLE & FELT", Color(0.25, 0.75, 0.45), ["neat_freak", "high_roller", "nope_x5", "giga_dweeb", "collector", "bowling",
		"coin_slot", "peeking", "price_check", "fortune_teller", "real_full_house", "up_close", "glass_breaker"]],
	["SHOP", Color(1.0, 0.6, 0.15), ["big_spender", "one_armed", "lever_frenzy", "window_shopper", "hands_on", "bargain"]],
	["WHEEL OF FORTUNE", Color(0.95, 0.3, 0.4), ["lady_luck", "three_row", "spin_doctor"]],
	["CASINO ROOM", Color(0.7, 0.45, 1.0), ["welcome", "streamer", "endless", "stargazer", "ghost_hunter", "mountain", "vradar",
		"planet_hopper", "curator"]],
	["SCORE TOWER", Color(0.3, 0.85, 0.85), ["sky_high", "close_call", "hot_streak", "boss_slayer"]],
	["CARDS & PACKS", Color(1.0, 0.85, 0.3), ["rip_it", "pack_surgeon", "card_sharp", "shuffle_master", "over_shoulder",
		"glass_cannon", "five_kind"]],
	["SOLATRO", Color(1.0, 0.45, 0.75), ["royal", "jokes_on_you", "token_hoarder"]],
	["SOUNDS & SHOWS", Color(0.85, 0.85, 0.92), ["ovation", "going_up", "safe_travels", "heartbreaker", "say_cheese"]],
]
const BASE_ID := -700               # reward switch of row i: BASE_ID - i
const PREV_ID := -790
const NEXT_ID := -791
const BACK_ID := -792

var ach: Achievements
var hand: Node3D                    # the card hand it is fixed to
var offset := Transform3D()
var back: Callable                  # BACK: return to the VR menu

var _page := 0
var _bodies: Array[StaticBody3D] = []


func open() -> void:
	_build()
	visible = true


func _build() -> void:
	for c in get_children():
		c.queue_free()
	_bodies.clear()
	var all_pages := _pages()
	var pages := all_pages.size()
	_page = posmod(_page, maxi(pages, 1)) # (< on the first page: the last one, > on the last: the first)
	var page: Array = all_pages[_page] if pages > 0 else []
	var used := 0.0
	for e in page:
		used += HEAD if e.has("group") else ROW
	var h := used + 0.085
	_box(Vector3(WIDTH + 0.02, h, 0.004), Vector3(0, -h * 0.5 + 0.02, 0), Color(0.16, 0.06, 0.14)) # plum like the panels
	_box(Vector3(WIDTH + 0.026, h + 0.006, 0.003), Vector3(0, -h * 0.5 + 0.02, -0.001), Color(0.9, 0.66, 0.26)) # gold frame
	_text("ACHIEVEMENTS   %d / %d" % [ach.done_count(), Achievements.LIST.size()], 34, 0.0005, Color(1.0, 0.8, 0.3), Vector3(0, 0.003, 0.004), true)
	var cursor := -0.01 # (the top of the next row)
	for e in page:
		var colour: Color = GROUPS[e["g"]][1]
		if e.has("group"): # a group's heading: its colour, its name, how many of it are unlocked
			var y_h := cursor - HEAD * 0.5
			cursor -= HEAD
			_box(Vector3(WIDTH, HEAD - 0.006, 0.002), Vector3(0, y_h, 0.0035), colour.darkened(0.55))
			var ids: Array = GROUPS[e["g"]][2]
			var got := ids.filter(func(i): return ach.is_done(i)).size()
			_text(str(GROUPS[e["g"]][0]) + ("  (cont.)" if e.get("cont", false) else ""), 26, 0.00045, colour.lightened(0.3),
				Vector3(-WIDTH * 0.5 + 0.01, y_h, 0.005))
			_text("%d / %d" % [got, ids.size()], 24, 0.00045, colour.lightened(0.3), Vector3(WIDTH * 0.5 - 0.027, y_h, 0.005), true)
			continue
		var a: Dictionary = e["a"]
		var id: String = a["id"]
		var done := ach.is_done(id)
		var y := cursor - ROW * 0.5
		cursor -= ROW
		_box(Vector3(0.004, ROW - 0.008, 0.002), Vector3(-WIDTH * 0.5 - 0.004, y, 0.0035), colour) # the group's strip
		# the trophy
		var cup := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.011
		cm.bottom_radius = 0.008
		cm.height = 0.004
		cup.mesh = cm
		cup.rotation_degrees.x = 90.0
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.78, 0.25) if done else Color(0.3, 0.27, 0.3)
		mat.metallic = 0.8 if done else 0.0
		mat.roughness = 0.3
		if done:
			mat.emission_enabled = true
			mat.emission = Color(1.0, 0.7, 0.2)
			mat.emission_energy_multiplier = 0.4
		cup.material_override = mat
		cup.position = Vector3(-WIDTH * 0.5 + 0.014, y, 0.005)
		add_child(cup)
		var left := -WIDTH * 0.5 + 0.032
		_text(str(a["name"]), 30, 0.00045, Color(1.0, 0.95, 0.85) if done else Color(0.75, 0.72, 0.75), Vector3(left, y + 0.008, 0.004))
		var second := ("Reward: " + str(a["reward"])) if done else str(a["text"])
		_text(second, 22, 0.00045, Color(1.0, 0.8, 0.35) if done else Color(0.6, 0.58, 0.62), Vector3(left, y - 0.008, 0.004))
		if done and a.has("choices"): # a reward to choose (e.g. the beam colour): the button cycles
			var pick: String = a["choices"][ach.choice(id) if ach.reward(id) else 0]
			var tint: Color = Achievements.METAL_COLOURS.get(pick, Color(0.33, 0.45, 0.62)).darkened(0.25)
			_button(pick.to_upper(), BASE_ID - Achievements.LIST.find(a), Vector3(WIDTH * 0.5 - 0.04, y, 0.004), Vector2(0.07, 0.024), tint)
		elif done: # the reward's switch
			var on := ach.reward(id)
			_button("ON" if on else "OFF", BASE_ID - Achievements.LIST.find(a), Vector3(WIDTH * 0.5 - 0.027, y, 0.004), Vector2(0.042, 0.024),
				Color(0.2, 0.62, 0.4) if on else Color(0.4, 0.36, 0.4))
		else:
			_text("%d / %d" % [ach.progress(id), int(a["goal"])], 26, 0.00045, Color(0.6, 0.75, 1.0), Vector3(WIDTH * 0.5 - 0.027, y, 0.004), true)
	var bottom := cursor - 0.016
	_button("BACK", BACK_ID, Vector3(0, bottom, 0.004), Vector2(0.09, 0.024), Color(0.85, 0.35, 0.3))
	if pages > 1:
		_button("<", PREV_ID, Vector3(-0.1, bottom, 0.004), Vector2(0.04, 0.024), Color(0.33, 0.45, 0.62))
		_button(">", NEXT_ID, Vector3(0.1, bottom, 0.004), Vector2(0.04, 0.024), Color(0.33, 0.45, 0.62))
	GameFont.apply_to(self)


## The pages: the groups one after the other (the unlocked ones first in each), a heading before
## each group - and again "(cont.)" at the top of a page where a group goes on.
func _pages() -> Array:
	var pages: Array = []
	var page: Array = []
	var room := PER_PAGE * ROW
	for g in GROUPS.size():
		var ids: Array = GROUPS[g][2]
		var items: Array = Achievements.LIST.filter(func(a): return ids.has(a["id"]) and ach.is_done(a["id"])) 				+ Achievements.LIST.filter(func(a): return ids.has(a["id"]) and not ach.is_done(a["id"]))
		var head_done := false
		for a in items:
			var need := ROW + (0.0 if head_done else HEAD)
			if room < need - 0.0001: # a new page
				pages.append(page)
				page = []
				room = PER_PAGE * ROW
				head_done = false
			if not head_done:
				page.append({"group": true, "g": g, "cont": items.find(a) > 0})
				room -= HEAD
				head_done = true
			page.append({"a": a, "g": g})
			room -= ROW
	if not page.is_empty():
		pages.append(page)
	return pages


func press(id: int) -> void:
	if id == BACK_ID:
		visible = false
		if back.is_valid():
			back.call()
		return
	if id == PREV_ID:
		_page -= 1
	elif id == NEXT_ID:
		_page += 1
	else:
		var i := BASE_ID - id
		if i >= 0 and i < Achievements.LIST.size():
			var key: String = Achievements.LIST[i]["id"]
			if Achievements.LIST[i].has("choices"):
				ach.cycle_choice(key)
			else:
				ach.set_reward(key, not ach.reward(key))
	_build()


func _process(_delta: float) -> void:
	if not visible or hand == null:
		return
	var h := hand.global_transform
	global_transform = Transform3D(h.basis.orthonormalized(), h.origin) * offset


## Hidden buttons must not be hit: an invisible body still stops the beam in Godot.
func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		for b in _bodies:
			if is_instance_valid(b):
				b.collision_layer = 1 if is_visible_in_tree() else 0


func _button(label: String, id: int, at: Vector3, size: Vector2, colour: Color) -> void:
	_box(Vector3(size.x, size.y, 0.004), at, colour)
	_text(label, 28, 0.00045, Color(1, 1, 1), at + Vector3(0, 0, 0.0032), true)
	var body := StaticBody3D.new()
	body.set_meta("target_id", id)
	body.set_meta("kind", "ach")
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(size.x, size.y, 0.01)
	shape.shape = bs
	body.add_child(shape)
	body.position = at
	body.collision_layer = 1 if is_visible_in_tree() else 0
	add_child(body)
	_bodies.append(body)


func _text(s: String, size: int, pixel: float, colour: Color, at: Vector3, centred := false) -> void:
	var l := Label3D.new()
	l.text = s
	l.font_size = size
	l.pixel_size = pixel
	l.outline_size = 0
	l.modulate = colour
	l.position = at
	if not centred:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT # (starts at its origin)
	add_child(l)


func _box(size: Vector3, at: Vector3, colour: Color) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = colour
	mi.material_override = m
	mi.position = at
	add_child(mi)
