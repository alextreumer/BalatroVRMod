class_name ShopCounter
extends Node3D
## The shop as a little sales counter on the table (shown while the shop is open): the jokers and
## cards for sale stand on it in small stands, the booster packs stand on the right, a voucher waits
## under a glass dome on the left; a price sign in front of each (red when you can't pay).
## Take something off the counter (grip) and pull it towards you to buy it - let go near its place
## and it goes back. Touch / point at it to read its description. Or select it with the beam
## (trigger): it lifts a little and BUY (and BUY & USE) buttons appear in front of it.
## Positions are in the counter's own coordinates: +z faces you, the top is at y = TOP.

signal buy(uid: int)
signal buy_use(uid: int)           # "buy and use": a tarot / planet / spectral card used straight from the counter

const WIDTH := 0.82
const DEPTH := 0.2
const TOP := 0.17                  # height of the counter top above the table (a real counter)
const SPACING := 0.14
const BASE := 0.063                 # width of the table card make_card builds
const CARD := Vector2(0.09, 0.126)  # cards on the counter: larger than on the table, to read them
const PACK := Vector2(0.1, 0.137)
const GRAB_RADIUS := 0.08
const TAKE_DISTANCE := 0.12        # pulled this far off its place: bought

var make_card: Callable            # -> Node3D: a card with a "Face" child (main.gd's table card)
var apply_art: Callable            # (node: Node3D, item: Dictionary) -> void

var _items := {}                   # uid -> {"node", "item", "spot": Transform3D, "price": Label3D, "kind"}
var _held := -1
var _held_hand: Node3D
var _held_offset := Transform3D()
var _held_scale := Vector3.ONE     # its size in the room when it was taken (kept while it is held)
var _pending := {}                 # uid -> time the buy was sent (back to its place if refused)
var _dollars := 0
var _wood: StandardMaterial3D
var _panels: Array[StandardMaterial3D] = []
var currency := "$"                # Solatro pays in points: "PTS" (after the number then)
var _plate_lines: Array[Label3D] = []
var _selected := -1                # selected with the beam: lifted, its buy buttons shown
var _buttons: Node3D               # the BUY / BUY & USE buttons of the selected item
const SELECT_LIFT := 0.025
const BUY_ID := -300000            # the buttons' own beam ids: BUY_ID - uid * 2 (- 1 for BUY & USE) -
var _buttons_sig := ""             # (the card's own id would keep the beam "on the card")
const PLATE := ["GRAB TO BUY  •  GAMBLE TO REROLL", "BUY & USE: DROP ON YOUR OTHER HAND  OR  TOSS IT IN THE AIR"]
const PLATE_SOLATRO := ["GRAB A TOKEN TO BUY IT", "IT WAITS ON THE TABLE UNTIL YOU USE IT"]


## Achievement reward "Big Spender": the counter in gold.
## "Big Spender" reward: the counter in the chosen colour (alpha 0: wood).
func set_metal(colour: Color) -> void:
	if _wood == null:
		return
	var on := colour.a > 0.0
	# (only a little metallic: in the dark casino a mirror-like metal would just reflect black)
	_wood.albedo_color = colour.darkened(0.05) if on else Color(0.25, 0.11, 0.05)
	_wood.metallic = 0.35 if on else 0.0
	_wood.emission_enabled = on
	_wood.emission = colour * 0.15
	for p in _panels:
		p.albedo_color = colour.darkened(0.4) if on else Color(0.16, 0.06, 0.03)


## "Hands On" reward: a brass desk bell on the counter's left end, rung when something is bought.
var _bell: Node3D


func set_bell(on: bool) -> void:
	if on and _bell == null:
		_bell = Node3D.new()
		_bell.name = "Bell"
		_bell.position = Vector3(-WIDTH * 0.5 + 0.035, TOP, DEPTH * 0.5 - 0.035)
		add_child(_bell)
		var base := MeshInstance3D.new()
		var bc := CylinderMesh.new()
		bc.top_radius = 0.022
		bc.bottom_radius = 0.024
		bc.height = 0.006
		base.mesh = bc
		base.material_override = _mat(Color(0.12, 0.08, 0.06), 0.4)
		base.position.y = 0.003
		_bell.add_child(base)
		var brass := StandardMaterial3D.new()
		brass.albedo_color = Color(0.95, 0.72, 0.3)
		brass.metallic = 0.6
		brass.roughness = 0.25
		brass.emission_enabled = true
		brass.emission = Color(0.95, 0.72, 0.3) * 0.15
		var dome := MeshInstance3D.new()
		dome.name = "Dome"
		var dm := SphereMesh.new()
		dm.radius = 0.019
		dm.height = 0.019
		dm.is_hemisphere = true
		dome.mesh = dm
		dome.material_override = brass
		dome.position.y = 0.006
		_bell.add_child(dome)
		var knob := MeshInstance3D.new()
		var km := SphereMesh.new()
		km.radius = 0.004
		km.height = 0.008
		knob.mesh = km
		knob.material_override = brass
		knob.position.y = 0.027
		_bell.add_child(knob)
	if _bell != null:
		_bell.visible = on


func ring_bell() -> void:
	if _bell == null or not _bell.visible:
		return
	var tw := create_tween()
	for k in 4: # a little wobble
		tw.tween_property(_bell, "rotation_degrees:z", 8.0 * (1 if k % 2 == 0 else -1) / (k + 1), 0.05)
	tw.tween_property(_bell, "rotation_degrees:z", 0.0, 0.05)


## "Bargain Hunter" reward: a red SALE! sticker on everything that costs $2 or less.
var sale := false


func cost_of(uid: int) -> int:
	var e: Dictionary = _items.get(uid, {})
	return 999 if e.is_empty() else int(e["item"].get("cost", 0))


func _sale_sticker(node: Node3D, on: bool) -> void:
	var l := node.get_node_or_null("Sale") as Label3D
	if l == null and on:
		l = Label3D.new()
		l.name = "Sale"
		l.text = "SALE!"
		l.font_size = 48
		l.pixel_size = 0.0005
		l.modulate = Color(1.0, 0.95, 0.85)
		l.outline_size = 14
		l.outline_modulate = Color(0.85, 0.08, 0.1)
		l.rotation_degrees.z = 18.0
		l.position = Vector3(BASE * 0.3, BASE * 0.55, 0.004)
		l.render_priority = 4
		node.add_child(l)
		GameFont.apply_to(l)
	if l != null:
		l.visible = on


## Solatro's Bonus Shoppe: no rerolls and no buy & use - the brass plate says what it is there.
func set_solatro(on: bool) -> void:
	currency = "PTS" if on else "$" # (capitals: the font's small p looks like an o)
	for i in _plate_lines.size():
		_plate_lines[i].text = (PLATE_SOLATRO if on else PLATE)[i]


func _ready() -> void:
	var wood := StandardMaterial3D.new()
	_wood = wood
	wood.albedo_color = Color(0.25, 0.11, 0.05)
	wood.roughness = 0.3
	# the top: dark, almost black wood (no green felt: in the Green background that colour would be
	# keyed out by the passthrough and the counter top would vanish)
	var felt := StandardMaterial3D.new()
	felt.albedo_color = Color(0.09, 0.045, 0.025)
	felt.roughness = 0.35
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.86, 0.66, 0.3)
	brass.metallic = 0.8
	brass.roughness = 0.3
	_box(Vector3(WIDTH, TOP - 0.004, DEPTH), Vector3(0, (TOP - 0.004) * 0.5, 0), wood)       # body
	_box(Vector3(WIDTH - 0.01, 0.004, DEPTH - 0.01), Vector3(0, TOP - 0.002, 0), felt)        # dark wood top
	_box(Vector3(WIDTH + 0.008, 0.006, 0.008), Vector3(0, TOP - 0.003, DEPTH * 0.5), brass)   # front edge
	# the front: two dark inset panels, a brass plinth, and a brass plate that says what to do
	for side in [-1.0, 1.0]:
		var panel := _mat(Color(0.16, 0.06, 0.03), 0.4)
		_panels.append(panel)
		_box(Vector3(WIDTH * 0.5 - 0.03, TOP - 0.05, 0.004), Vector3(side * WIDTH * 0.25, TOP * 0.5 + 0.01, DEPTH * 0.5 + 0.001), panel)
	_box(Vector3(WIDTH + 0.006, 0.014, DEPTH + 0.006), Vector3(0, 0.007, 0), brass)              # plinth
	# a black enamel plate in a brass frame, the words in glowing gold: readable in the shadow of the
	# counter edge and in the dark casino
	# (two lines: how to buy and reroll, and how to buy and use a tarot / spectral / planet at once)
	_box(Vector3(0.376, 0.048, 0.003), Vector3(0, TOP - 0.03, DEPTH * 0.5 + 0.003), brass)       # frame
	_box(Vector3(0.366, 0.04, 0.003), Vector3(0, TOP - 0.03, DEPTH * 0.5 + 0.0045), _mat(Color(0.03, 0.02, 0.02), 0.6)) # plate
	var hint := Label3D.new()
	_plate_lines.append(hint)
	hint.text = PLATE[0]
	hint.font_size = 32
	hint.pixel_size = 0.00045
	hint.outline_size = 0
	hint.modulate = Color(1.0, 0.82, 0.35) # (a Label3D is unshaded: this stays bright in any light)
	hint.position = Vector3(0, TOP - 0.021, DEPTH * 0.5 + 0.0068) # (just in front of the plate)
	add_child(hint)
	GameFont.apply_to(hint)
	var use_hint := Label3D.new()
	_plate_lines.append(use_hint)
	use_hint.text = PLATE[1]
	use_hint.font_size = 26
	use_hint.pixel_size = 0.00042
	use_hint.outline_size = 0
	use_hint.modulate = Color(0.95, 0.7, 0.3)
	use_hint.position = Vector3(0, TOP - 0.039, DEPTH * 0.5 + 0.0068)
	add_child(use_hint)
	GameFont.apply_to(use_hint)


## The shop's items from the scene (areas shop_jokers / shop_vouchers / shop_booster).
func sync(items: Array, dollars: int) -> void:
	_dollars = dollars
	var alive := {}
	var order: Array = []
	for area in ["shop_vouchers", "shop_jokers", "shop_booster"]: # left to right
		for it in items:
			if it.get("k", "") == "c" and it.get("area", "") == area:
				order.append(it)
	var n := order.size()
	var now := Time.get_ticks_msec() / 1000.0
	for i in n:
		var it: Dictionary = order[i]
		var uid := int(it.get("id", -1))
		alive[uid] = true
		var e: Dictionary = _items.get(uid, {})
		if e.is_empty():
			e = _make_item(it)
			_items[uid] = e
		e["item"] = it
		apply_art.call(e["node"].get_node("Face"), it)
		apply_art.call(e["node"].get_node("BackArt"), it)
		var x := (i - (n - 1) / 2.0) * minf(SPACING, (WIDTH - 0.08) / maxf(n - 1, 1))
		var size: Vector2 = PACK if e["kind"] == "pack" else CARD
		var lean := Basis(Vector3.RIGHT, deg_to_rad(-12.0))
		e["spot"] = Transform3D(lean, Vector3(x, TOP + 0.004 + size.y * 0.5, -0.02))
		var cost := int(it.get("cost", 0))
		var price: Label3D = e["price"]
		price.text = ("$%d" % cost) if currency == "$" else ("%d %s" % [cost, currency])
		price.modulate = Color(0.95, 0.85, 0.4) if cost <= dollars else Color(0.95, 0.25, 0.2)
		price.position = Vector3(x, TOP + 0.016, DEPTH * 0.5 - 0.02) # a little price sign standing in front of it
		var w := 0.014 + price.text.length() * 0.0125 # (as wide as its text: "$4" ... "100 PTS")
		(price.get_node("Plate") as MeshInstance3D).scale.x = w / 0.062
		(price.get_node("Edge") as MeshInstance3D).scale.x = (w + 0.004) / 0.066
		_sale_sticker(e["node"], sale and currency == "$" and cost <= 2)
		var plaque_cost := e["node"].get_node_or_null("PlaqueCost") as Label3D
		if plaque_cost != null:
			plaque_cost.text = price.text
			plaque_cost.modulate = price.modulate
		var dome := e["node"].get_node_or_null("Dome") as Node3D
		if dome != null:
			dome.visible = _held != uid
		# a buy that the game refused: back to its place
		if _pending.has(uid) and now - float(_pending[uid]) > 1.5:
			_pending.erase(uid)
			e["node"].visible = true
	for uid in _items.keys():
		if not alive.has(uid):
			var e: Dictionary = _items[uid]
			(e["node"] as Node3D).queue_free()
			(e["price"] as Node3D).queue_free()
			_items.erase(uid)
			_pending.erase(uid)
			if _held == uid:
				_held = -1
	if _selected >= 0 and not _items.has(_selected):
		select(-1)
	elif _selected >= 0:
		select(_selected, true) # (its price or whether it can be used may have changed)


func _make_item(it: Dictionary) -> Dictionary:
	var area := str(it.get("area", ""))
	var kind := "pack" if area == "shop_booster" else ("voucher" if area == "shop_vouchers" else "card")
	var node: Node3D = make_card.call()
	add_child(node)
	# seen from behind it shows its front picture again (a pack has no card back), not a plain back
	if kind != "card": # a pack or a voucher is slimmer than a card: no pale card body around it
		var core := node.get_node_or_null("Core") as Node3D
		if core != null:
			core.visible = false
	var plain_back := node.get_node_or_null("Back") as Node3D
	if plain_back != null:
		plain_back.visible = false
	var face := node.get_node("Face") as Node3D
	var back_art := Node3D.new()
	back_art.name = "BackArt"
	back_art.rotation_degrees.y = 180.0
	back_art.position.z = -face.position.z
	node.add_child(back_art)
	if kind == "pack":
		node.scale = Vector3.ONE * (PACK.x / BASE)
	else:
		node.scale = Vector3.ONE * (CARD.x / BASE)
	# for the beam and the tooltip
	var body := StaticBody3D.new()
	body.set_meta("target_id", int(it.get("id", -1)))
	body.set_meta("kind", "shopitem")
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(BASE, BASE * 1.4, 0.01) # (in the scaled card's own size)
	shape.shape = bs
	body.add_child(shape)
	node.add_child(body)
	if it.has("token"): # Solatro's tokens: the little model on a glass base, its name above it
		for n in ["Face", "Core", "Back"]:
			var part := node.get_node_or_null(n) as Node3D
			if part != null:
				part.visible = false
		var base := MeshInstance3D.new()
		var bm := CylinderMesh.new()
		bm.top_radius = 0.022
		bm.bottom_radius = 0.024
		bm.height = 0.005
		base.mesh = bm
		var glass := StandardMaterial3D.new()
		glass.albedo_color = Color(0.8, 0.9, 1.0, 0.35)
		glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		glass.roughness = 0.05
		base.material_override = glass
		base.position.y = -BASE * 0.7 + 0.0025
		node.add_child(base)
		var model := SolatroGame.token_model(str(it["token"]))
		model.position.y = -BASE * 0.7 + 0.005
		model.scale = Vector3.ONE * 0.8
		node.add_child(model)
		var name := Label3D.new()
		name.text = str(it.get("name", ""))
		name.font_size = 28
		name.pixel_size = 0.0003
		name.outline_size = 6
		name.outline_modulate = Color(0.05, 0.03, 0.06)
		name.modulate = Color(1.0, 0.85, 0.45)
		name.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		name.position.y = -BASE * 0.7 + 0.065
		node.add_child(name)
		GameFont.apply_to(node)
	elif it.has("label"): # no card picture: a dark plaque with its name and what it does
		var core := node.get_node_or_null("Core") as Node3D
		if core != null:
			core.visible = false # (the plaque is the token: no pale card body around / in front of it)
		var plaque := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(BASE, BASE * 1.4)
		plaque.mesh = q
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0.12, 0.06, 0.16)
		plaque.material_override = m
		plaque.position.z = 0.0012
		node.add_child(plaque)
		var text := Label3D.new()
		text.text = str(it["label"])
		text.font_size = 40
		text.pixel_size = 0.00022
		text.width = BASE * 0.9 / text.pixel_size
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.outline_size = 0
		text.modulate = Color(1.0, 0.85, 0.4)
		text.position = Vector3(0, 0.0, 0.0016)
		node.add_child(text)
		GameFont.apply_to(text)
	var tip := Node3D.new()
	tip.name = "TipAnchor"
	tip.position = Vector3(0, BASE * 0.7 + 0.03, 0.0)
	node.add_child(tip)
	if kind == "voucher": # under a glass dome, like something precious
		var dome := MeshInstance3D.new()
		dome.name = "Dome"
		var s := SphereMesh.new()
		s.radius = 0.045
		s.height = 0.11
		s.is_hemisphere = false
		dome.mesh = s
		var glass := StandardMaterial3D.new()
		glass.albedo_color = Color(0.8, 0.9, 1.0, 0.15)
		glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		glass.roughness = 0.05
		glass.metallic_specular = 1.0
		dome.material_override = glass
		dome.position = Vector3(0, -0.005, 0.0)
		node.add_child(dome)
	# the price: a little black tent sign with a brass edge standing on the counter in front of the
	# item, leaning back towards you - big gold numbers (red when you can't pay)
	var price := Label3D.new()
	price.font_size = 64
	price.pixel_size = 0.0005
	price.rotation_degrees.x = -25.0
	price.outline_size = 10
	price.outline_modulate = Color(0.05, 0.03, 0.02)
	price.render_priority = 2
	add_child(price)
	var sign_mat := StandardMaterial3D.new()
	sign_mat.albedo_color = Color(0.05, 0.04, 0.05)
	sign_mat.roughness = 0.5
	var plate := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.062, 0.03, 0.002)
	plate.mesh = pm
	plate.material_override = sign_mat
	plate.position.z = -0.0016
	plate.name = "Plate"
	price.add_child(plate)
	var edge := MeshInstance3D.new()
	var em := BoxMesh.new()
	em.size = Vector3(0.066, 0.034, 0.0015)
	edge.mesh = em
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.86, 0.66, 0.3)
	brass.metallic = 0.7
	brass.roughness = 0.35
	edge.material_override = brass
	edge.position.z = -0.0028
	edge.name = "Edge"
	price.add_child(edge)
	GameFont.apply_to(price)
	node.position = Vector3(0, TOP + 0.2, -0.05) # drops onto the counter (position only: keeps the size above)
	return {"node": node, "item": it, "spot": Transform3D(), "price": price, "kind": kind}


## The tooltip of an item on the counter appears above it.
func tip_anchor(uid: int) -> Node3D:
	var e: Dictionary = _items.get(uid, {})
	return null if e.is_empty() else (e["node"] as Node3D).get_node("TipAnchor")


func has_item(uid: int) -> bool:
	return _items.has(uid)


func item_node(uid: int) -> Node3D:
	var e: Dictionary = _items.get(uid, {})
	return null if e.is_empty() else e["node"]


func try_grab(hand: Node3D) -> bool:
	if not is_visible_in_tree() or _held >= 0:
		return false
	var best := -1
	var best_d := GRAB_RADIUS
	for uid in _items:
		var node: Node3D = _items[uid]["node"]
		if not node.visible:
			continue
		var d := node.global_position.distance_to(hand.global_position)
		if d < best_d:
			best = uid
			best_d = d
	if best < 0:
		return false
	_held = best
	_held_hand = hand
	select(-1)
	var g := (_items[best]["node"] as Node3D).global_transform
	_held_offset = hand.global_transform.affine_inverse() * Transform3D(g.basis.orthonormalized(), g.origin)
	_held_scale = g.basis.get_scale()
	return true


func holds(hand: Node3D) -> bool:
	return _held >= 0 and _held_hand == hand


## The hand holding an item off the counter (null if none), and that item's scene data.
func held_hand() -> Node3D:
	return _held_hand if _held >= 0 else null


func held_item() -> Dictionary:
	var e: Dictionary = _items.get(_held, {})
	return {} if e.is_empty() else e["item"]


## Let go with the "use" gesture (dropped on the card hand / a planet thrown up): "used" (bought and
## used), "poor" (can't be paid) or "cant" (can't be used right now) - those two go back.
func release_use(hand: Node3D) -> String:
	if not holds(hand):
		return ""
	var uid := _held
	_held = -1
	var e: Dictionary = _items.get(uid, {})
	if e.is_empty():
		return ""
	if int(e["item"].get("cost", 0)) > _dollars:
		return "poor"
	if not e["item"].get("cu", false):
		return "cant"
	_pending[uid] = Time.get_ticks_msec() / 1000.0
	buy_use.emit(uid)
	return "used"


## Let go: far enough off its place = bought (if it can be paid), otherwise it goes back.
## Returns "bought", "poor" or "" (put back).
func release(hand: Node3D) -> String:
	if not holds(hand):
		return ""
	var uid := _held
	_held = -1
	var e: Dictionary = _items.get(uid, {})
	if e.is_empty():
		return ""
	var node: Node3D = e["node"]
	var spot: Vector3 = global_transform * (e["spot"] as Transform3D).origin
	if node.global_position.distance_to(spot) < TAKE_DISTANCE:
		return ""
	if int(e["item"].get("cost", 0)) > _dollars:
		return "poor"
	_pending[uid] = Time.get_ticks_msec() / 1000.0
	buy.emit(uid) # (main.gd lets a copy fly to its place; this one hides until the game confirms)
	return "bought"


## Trigger on an item: select it (again: unselect). uid -1: nothing selected.
func select(uid: int, refresh := false) -> void:
	if uid == _selected and not refresh:
		uid = -1
	var e0: Dictionary = _items.get(uid, {})
	var sig := "" if e0.is_empty() else "%d|%s|%s" % [uid, e0["item"].get("cu", false), currency]
	if refresh and sig == _buttons_sig:
		return # nothing changed: the buttons stay (rebuilding them would make the beam slip off)
	_buttons_sig = sig
	_selected = uid
	if _buttons != null:
		_buttons.queue_free()
		_buttons = null
	var e: Dictionary = _items.get(uid, {})
	if e.is_empty():
		_selected = -1
		return
	_buttons = Node3D.new()
	add_child(_buttons)
	var spot: Transform3D = e["spot"]
	_buttons.position = Vector3(spot.origin.x, TOP + 0.05, DEPTH * 0.5 - 0.03)
	_buttons.rotation_degrees.x = -25.0
	var can_use: bool = e["item"].get("cu", false) and currency == "$"
	if can_use:
		_buy_button("BUY", Color(0.9, 0.3, 0.22), uid, false, Vector3(-0.032, 0, 0), 0.058)
		_buy_button("BUY & USE", Color(0.25, 0.6, 0.35), uid, true, Vector3(0.032, 0, 0), 0.058)
	else:
		_buy_button("BUY", Color(0.9, 0.3, 0.22), uid, false, Vector3.ZERO, 0.07)


func _buy_button(text: String, colour: Color, uid: int, use: bool, pos: Vector3, w: float) -> void:
	var body := StaticBody3D.new()
	body.set_meta("target_id", BUY_ID - uid * 2 - (1 if use else 0))
	body.set_meta("kind", "shopbuy")
	body.set_meta("use", use)
	body.position = pos
	_buttons.add_child(body)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(w, 0.026, 0.006)
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = 0.5
	m.emission_enabled = true
	m.emission = colour
	m.emission_energy_multiplier = 0.25
	mi.material_override = m
	body.add_child(mi)
	var l := Label3D.new()
	l.text = text
	l.font_size = 48 if text.length() < 5 else 30
	l.pixel_size = 0.0004
	l.outline_size = 8
	l.outline_modulate = Color(0.1, 0.05, 0.05)
	l.position.z = 0.0035
	l.render_priority = 3
	body.add_child(l)
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(w, 0.026, 0.012)
	shape.shape = bs
	body.add_child(shape)
	GameFont.apply_to(body)


## A buy button pressed: like taking it off the counter - "bought" / "used", "poor" or "cant".
func press_buy(button_id: int) -> String:
	var uid := (BUY_ID - button_id) / 2
	var use := (BUY_ID - button_id) % 2 == 1
	var e: Dictionary = _items.get(uid, {})
	if e.is_empty() or _pending.has(uid):
		return ""
	if int(e["item"].get("cost", 0)) > _dollars:
		return "poor"
	if use and not e["item"].get("cu", false):
		return "cant"
	select(-1)
	_pending[uid] = Time.get_ticks_msec() / 1000.0
	if use:
		buy_use.emit(uid)
		return "used"
	buy.emit(uid)
	return "bought"


func _process(delta: float) -> void:
	var k := 1.0 - exp(-10.0 * delta)
	for uid in _items:
		var e: Dictionary = _items[uid]
		var node: Node3D = e["node"]
		if uid == _held and _held_hand != null and is_instance_valid(_held_hand):
			# (the room size, not node.scale: on a scaled counter that would grow it a bit every frame)
			node.global_transform = (_held_hand.global_transform * _held_offset).scaled_local(_held_scale)
			continue
		if _pending.has(uid):
			continue # bought: it flies off (main.gd) or comes back if refused (sync)
		var target: Transform3D = e["spot"]
		if uid == _selected:
			target.origin.y += SELECT_LIFT
		var s := node.scale
		node.transform = Transform3D(node.transform.basis.orthonormalized().slerp(target.basis, k), node.position.lerp(target.origin, k)).scaled_local(s)


func _box(size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.position = pos
	mi.material_override = mat
	add_child(mi)


func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m
