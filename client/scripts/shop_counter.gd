class_name ShopCounter
extends Node3D
## The shop as a little sales counter on the table (shown while the shop is open): the jokers and
## cards for sale stand on it in small stands, the booster packs stand on the right, a voucher waits
## under a glass dome on the left; a price sign in front of each (red when you can't pay).
## Take something off the counter (grip) and pull it towards you to buy it - let go near its place
## and it goes back. Touch / point at it to read its description.
## Positions are in the counter's own coordinates: +z faces you, the top is at y = TOP.

signal buy(uid: int)

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


func _ready() -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.25, 0.11, 0.05)
	wood.roughness = 0.3
	var felt := StandardMaterial3D.new()
	felt.albedo_color = Color(0.1, 0.32, 0.18)
	felt.roughness = 1.0
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.86, 0.66, 0.3)
	brass.metallic = 0.8
	brass.roughness = 0.3
	_box(Vector3(WIDTH, TOP - 0.004, DEPTH), Vector3(0, (TOP - 0.004) * 0.5, 0), wood)       # body
	_box(Vector3(WIDTH - 0.01, 0.004, DEPTH - 0.01), Vector3(0, TOP - 0.002, 0), felt)        # green top
	_box(Vector3(WIDTH + 0.008, 0.006, 0.008), Vector3(0, TOP - 0.003, DEPTH * 0.5), brass)   # front edge
	# the front: two dark inset panels, a brass plinth, and a brass plate that says what to do
	for side in [-1.0, 1.0]:
		_box(Vector3(WIDTH * 0.5 - 0.03, TOP - 0.05, 0.004), Vector3(side * WIDTH * 0.25, TOP * 0.5 + 0.01, DEPTH * 0.5 + 0.001),
				_mat(Color(0.16, 0.06, 0.03), 0.4))
	_box(Vector3(WIDTH + 0.006, 0.014, DEPTH + 0.006), Vector3(0, 0.007, 0), brass)              # plinth
	# a black enamel plate in a brass frame, the words in glowing gold: readable in the shadow of the
	# counter edge and in the dark casino
	_box(Vector3(0.376, 0.03, 0.003), Vector3(0, TOP - 0.021, DEPTH * 0.5 + 0.003), brass)       # frame
	_box(Vector3(0.366, 0.022, 0.003), Vector3(0, TOP - 0.021, DEPTH * 0.5 + 0.0045), _mat(Color(0.03, 0.02, 0.02), 0.6)) # plate
	var hint := Label3D.new()
	hint.text = "GRAB TO BUY  •  GAMBLE TO REROLL"
	hint.font_size = 32
	hint.pixel_size = 0.00045
	hint.outline_size = 0
	hint.modulate = Color(1.0, 0.82, 0.35) # (a Label3D is unshaded: this stays bright in any light)
	hint.position = Vector3(0, TOP - 0.021, DEPTH * 0.5 + 0.0068) # (just in front of the plate)
	add_child(hint)
	GameFont.apply_to(hint)


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
		var x := (i - (n - 1) / 2.0) * minf(SPACING, (WIDTH - 0.08) / maxf(n - 1, 1))
		var size: Vector2 = PACK if e["kind"] == "pack" else CARD
		var lean := Basis(Vector3.RIGHT, deg_to_rad(-12.0))
		e["spot"] = Transform3D(lean, Vector3(x, TOP + 0.004 + size.y * 0.5, -0.02))
		var cost := int(it.get("cost", 0))
		var price: Label3D = e["price"]
		price.text = "$%d" % cost
		price.modulate = Color(0.95, 0.85, 0.4) if cost <= dollars else Color(0.95, 0.25, 0.2)
		price.position = Vector3(x, TOP + 0.002, DEPTH * 0.5 - 0.022) # a price tag lying on the felt in front of it
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


func _make_item(it: Dictionary) -> Dictionary:
	var area := str(it.get("area", ""))
	var kind := "pack" if area == "shop_booster" else ("voucher" if area == "shop_vouchers" else "card")
	var node: Node3D = make_card.call()
	add_child(node)
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
	var price := Label3D.new()
	price.font_size = 40
	price.pixel_size = 0.0005
	price.rotation_degrees.x = -70.0 # lying on the counter, readable from where you stand
	price.outline_size = 6
	price.outline_modulate = Color(0.1, 0.05, 0.02)
	add_child(price)
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
	var g := (_items[best]["node"] as Node3D).global_transform
	_held_offset = hand.global_transform.affine_inverse() * Transform3D(g.basis.orthonormalized(), g.origin)
	_held_scale = g.basis.get_scale()
	return true


func holds(hand: Node3D) -> bool:
	return _held >= 0 and _held_hand == hand


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
