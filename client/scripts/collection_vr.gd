class_name CollectionVR
extends Node3D
## COLLECTIONS AND STATS in VR (main menu -> the album): a wooden display cabinet on the table with
## everything the game collects, page by page - jokers (as their 3D model when there is one),
## decks, vouchers, tarots, planets, spectrals, enhancements, editions, seals, boosters, tags and
## blinds. What you haven't found yet stands there as the game's own "?" / locked picture.
## Left: a column of signs for the collections, STATS (the card stats' columns around you) and
## BACK. Right: an info plate - point at something on the shelves and it shows its name and the
## game's own description. Above the cabinet: the collection's name, how many you found, the pages.
## Coordinates: the table surface, +z towards the player (placed like the menu by main.gd).

signal request(msg: Dictionary)    # to the mod: {"cmd": "collection", ...}
signal closed                      # BACK
signal stats                       # STATS: the card stats instead
signal looked(key: String)          # the beam rests on something on the shelves ("Curator")

const COLS := 8
const ROWS := 4
const CELL := Vector2(0.12, 0.16)
const SHELF_Z := -0.24              # the cabinet's middle (behind the menu's place)
const SHELF_DEPTH := 0.16
const BOARD := 0.012                # shelf board thickness
const CARD := Vector2(0.075, 0.1)
const DISC := 0.07                  # tags and blinds: round
const CAT_ID := -700                # - index: the collection signs
const PREV_ID := -730
const NEXT_ID := -731
const STATS_ID := -732
const BACK_ID := -733
const ITEM_ID := -800               # - slot on the page
const PER_PAGE := COLS * ROWS

var make_model: Callable            # (key) -> Node3D or null: the joker's 3D model, if it has one
var _cats: Array = []
var _cat := 0
var _page := 0
var _hover := 999
var _texts := {}                    # key -> description (asked once)
var _items_root: Node3D
var _slots: Array = []              # [{"node", "item", "home": Vector3}]
var _cat_buttons: Array = []        # [MeshInstance3D (its plate), Label3D]
var _title: Label3D
var _page_label: Label3D
var _info_name: Label3D
var _info_kind: Label3D
var _info_text: Label3D
var _loading: Label3D
var _wood: StandardMaterial3D
var _plum: StandardMaterial3D
var _orange: StandardMaterial3D
var _pending = null                 # data that came before the cabinet was built

const KIND_NAMES := {"Joker": "Joker", "Back": "Deck", "Voucher": "Voucher", "Tarot": "Tarot", "Planet": "Planet",
	"Spectral": "Spectral", "Enhanced": "Enhancement", "Edition": "Edition", "Seal": "Seal", "Booster": "Booster Pack",
	"Tag": "Tag", "Blind": "Blind"}


func _ready() -> void:
	_wood = _mat(Color(0.32, 0.15, 0.07), 0.55, 0.0)
	_plum = _mat(Color(0.3, 0.09, 0.22), 0.6, 0.0)
	_orange = _mat(Color(0.95, 0.55, 0.12), 0.5, 0.0)
	_orange.emission_enabled = true
	_orange.emission = Color(0.95, 0.55, 0.12) * 0.3
	_build_cabinet()
	_build_column()
	_build_info()
	_items_root = Node3D.new()
	add_child(_items_root)
	_loading = _label("Opening the collection ...", 40, 0.0008, Color(1.0, 0.85, 0.45))
	_loading.position = Vector3(0, ROWS * CELL.y * 0.5, SHELF_Z + SHELF_DEPTH * 0.5 + 0.02)
	add_child(_loading)
	GameFont.apply_to(self)
	if _golden:
		set_golden(true, _golden_colour) # (asked for before it was built)
	if _pending is Dictionary:
		set_data(_pending)
		_pending = null


## The mod's answer to {"action": "open"}: every collection with its items.
func set_data(data: Dictionary) -> void:
	if not is_node_ready():
		_pending = data
		return
	_cats = data.get("cats", [])
	_cat = clampi(_cat, 0, maxi(_cats.size() - 1, 0))
	_loading.visible = _cats.is_empty()
	for i in _cat_buttons.size():
		var l: Label3D = _cat_buttons[i][1]
		if i < _cats.size():
			var c: Dictionary = _cats[i]
			l.text = "%s  %d/%d" % [c.get("title", ""), int(c.get("found", 0)), (c.get("items", []) as Array).size()]
	_show_page()


## "Curator" reward: gold instead of wood, and glass doors that swing open each time it opens.
var _golden := false
var _golden_colour := Color(0.9, 0.66, 0.22)
var _doors: Array[Node3D] = []
var _door_t := 0.0
var _door_mats: Array[StandardMaterial3D] = [] # (they fade while they swing: nothing stands in front of the signs)


func set_golden(on: bool, colour := Color(0.9, 0.66, 0.22)) -> void:
	_golden = on
	_golden_colour = colour
	if _wood == null:
		return
	_wood.albedo_color = colour if on else Color(0.32, 0.15, 0.07)
	_wood.metallic = 0.45 if on else 0.0
	_wood.emission_enabled = on
	_wood.emission = colour * 0.12
	if on and _doors.is_empty():
		var w := COLS * CELL.x + 0.04
		var h := ROWS * CELL.y + BOARD
		var glass := _mat(Color(0.8, 0.92, 1.0, 0.18), 0.05, 0.0)
		glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		glass.metallic_specular = 1.0
		var trim := _mat(Color(colour.r, colour.g, colour.b, 1.0), 0.3, 0.6)
		trim.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_door_mats = [glass, trim]
		for side in [-1.0, 1.0]:
			var hinge := Node3D.new() # at the cabinet's outer edge, at its front
			hinge.position = Vector3(side * w * 0.5, 0.0, SHELF_Z + SHELF_DEPTH * 0.5 + 0.006)
			add_child(hinge)
			var pane := MeshInstance3D.new()
			var pm := BoxMesh.new()
			pm.size = Vector3(w * 0.5, h, 0.004)
			pane.mesh = pm
			pane.material_override = glass
			pane.position = Vector3(-side * w * 0.25, h * 0.5, 0)
			hinge.add_child(pane)
			var frame := MeshInstance3D.new()
			var fm := BoxMesh.new()
			fm.size = Vector3(0.012, h, 0.01)
			frame.mesh = fm
			frame.material_override = trim
			frame.position = Vector3(-side * (w * 0.5 - 0.006), h * 0.5, 0)
			hinge.add_child(frame)
			_doors.append(hinge)
	for d in _doors:
		d.visible = on
	_door_t = 0.0


## Opened again: a fresh look (the data comes anew, the texts are kept).
func reset() -> void:
	_door_t = 0.0 # (the glass doors swing open again)
	if not is_node_ready():
		return
	_cats = []
	_loading.visible = true
	_clear_items()
	_show_info({})


func set_info(key: String, text: String) -> void:
	_texts[key] = text
	var shown = _hovered_item()
	if shown is Dictionary and str(shown.get("key", "")) == key:
		_info_text.text = text


func press(id: int) -> void:
	if id <= CAT_ID and id > CAT_ID - 20:
		_cat = mini(CAT_ID - id, maxi(_cats.size() - 1, 0))
		_page = 0
		_show_page()
	elif id == PREV_ID:
		_page = posmod(_page - 1, _pages())
		_show_page()
	elif id == NEXT_ID:
		_page = posmod(_page + 1, _pages())
		_show_page()
	elif id == STATS_ID:
		stats.emit()
	elif id == BACK_ID:
		closed.emit()


## The beam is on this id (anything else: 999).
func hover(id: int) -> void:
	if id == _hover:
		return
	_hover = id
	var it = _hovered_item()
	_show_info(it if it is Dictionary else {})


func _hovered_item():
	var slot := ITEM_ID - _hover
	if _hover > ITEM_ID or slot >= _slots.size():
		return null
	return _slots[slot]["item"]


func _show_info(it: Dictionary) -> void:
	if not it.is_empty():
		looked.emit(str(it.get("key", "")))
	if it.is_empty():
		_info_name.text = "Point at something"
		_info_kind.text = "on the shelves"
		_info_text.text = ""
		return
	var known: bool = it.get("disc", false) and it.get("unl", true)
	_info_name.text = str(it.get("name", ""))
	_info_kind.text = KIND_NAMES.get(str(it.get("set", "")), str(it.get("set", ""))) if known else \
			("Locked" if not it.get("unl", true) else "Not discovered yet")
	var key := str(it.get("key", ""))
	if _texts.has(key):
		_info_text.text = _texts[key]
	else:
		_info_text.text = "..."
		request.emit({"cmd": "collection", "action": "info", "key": key, "set": str(it.get("set", ""))})


func _pages() -> int:
	if _cats.is_empty():
		return 1
	return maxi(1, ceili((_cats[_cat].get("items", []) as Array).size() / float(PER_PAGE)))


func _process(delta: float) -> void:
	if not visible:
		return
	var k := 1.0 - exp(-12.0 * delta)
	for i in _slots.size():
		var node: Node3D = _slots[i]["node"]
		var lifted := ITEM_ID - _hover == i
		var home: Vector3 = _slots[i]["home"]
		node.position = node.position.lerp(home + (Vector3(0, 0.012, 0.03) if lifted else Vector3.ZERO), k)
		node.scale = node.scale.lerp(Vector3.ONE * (1.18 if lifted else 1.0), k)
		if _slots[i].get("model", false):
			node.rotation.y += delta * (1.2 if lifted else 0.25) # the models turn slowly on their shelf
	for i in _cat_buttons.size():
		(_cat_buttons[i][0] as MeshInstance3D).material_override = _orange if i == _cat else _plum
	if not _doors.is_empty(): # the glass doors swing open (a moment after it appears)
		_door_t = minf(_door_t + delta * 0.8, 1.0)
		var open := clampf(_door_t * 1.4 - 0.2, 0.0, 1.0)
		open = open * open * (3.0 - 2.0 * open)
		for i in _doors.size():
			_doors[i].rotation.y = (-1.0 if i == 0 else 1.0) * deg_to_rad(100.0) * open
			_doors[i].visible = _golden and open < 1.0
		var fade := clampf(1.0 - (open - 0.4) / 0.6, 0.0, 1.0) # (gone by the time they stand open)
		_door_mats[0].albedo_color.a = 0.18 * fade
		_door_mats[1].albedo_color.a = fade


# ---------------------------------------------------------------- the page

func _clear_items() -> void:
	for c in _items_root.get_children():
		c.queue_free()
	_slots.clear()


func _show_page() -> void:
	_clear_items()
	if _cats.is_empty():
		return
	_page = clampi(_page, 0, _pages() - 1)
	var cat: Dictionary = _cats[_cat]
	var items: Array = cat.get("items", [])
	_title.text = "%s   %d / %d" % [str(cat.get("title", "")).to_upper(), int(cat.get("found", 0)), items.size()]
	_page_label.text = "%d / %d" % [_page + 1, _pages()]
	var first := _page * PER_PAGE
	for slot in mini(PER_PAGE, items.size() - first):
		var it: Dictionary = items[first + slot]
		var col := slot % COLS
		var row := slot / COLS
		var home := Vector3((col - (COLS - 1) * 0.5) * CELL.x, _shelf_y(row), SHELF_Z + 0.015)
		var node := Node3D.new()
		node.position = home
		_items_root.add_child(node)
		var is_model := false
		if str(it.get("set", "")) == "Joker" and it.get("disc", false) and it.get("unl", true) and make_model.is_valid():
			var model = make_model.call(str(it.get("key", "")))
			if model is Node3D:
				_fit(model, 0.13, 0.1)
				node.add_child(model)
				if model.has_method("update_state"): # what the model shows: a middling sample
					model.update_state({"ab": {"mult": 8, "x_mult": 2.0}, "extra": {"chips": 40, "mult": 8, "Xmult": 2.0},
						"value": "", "sell": 3}, {"round": {"discards_left": 3, "hands_left": 4, "dollars": 10, "ante": 2}})
				is_model = true
		if not is_model:
			_add_picture(node, it)
		_body(node, ITEM_ID - slot, Vector3(CELL.x * 0.85, CELL.y * 0.85, 0.08), Vector3(0, CELL.y * 0.42, 0))
		_slots.append({"node": node, "item": it, "home": home, "model": is_model})
	_hover = 999
	_show_info({})
	GameFont.apply_to(_items_root)


## The top of shelf `row` (0 = the top shelf).
func _shelf_y(row: int) -> float:
	return BOARD + (ROWS - 1 - row) * CELL.y + BOARD * 0.5


## A card (or a round tag / blind chip) standing on a little stand, leaning back.
func _add_picture(node: Node3D, it: Dictionary) -> void:
	var round: bool = it.get("round", false)
	var size := Vector2(DISC, DISC) if round else CARD
	var stand := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(size.x * 0.7, 0.008, 0.025)
	stand.mesh = sm
	stand.material_override = _mat(Color(0.12, 0.07, 0.05), 0.5, 0.2)
	stand.position = Vector3(0, 0.004, -0.008)
	node.add_child(stand)
	var face := Node3D.new()
	face.position = Vector3(0, size.y * 0.5 + 0.006, 0)
	face.rotation_degrees.x = -10.0
	node.add_child(face)
	var layers := CardArt.card_layers(it)
	if not (it.get("disc", false) and it.get("unl", true)): # the "?" / locked pictures are partly see-through
		var m := CardArt.material(it.get("ca"), it.get("cp"), true)
		layers = [m] if m != null else []
	CardArt.apply_layers(face, layers, size, 0.0, 0.0004)
	if not round: # a card back, so it isn't see-through from the side
		var back := MeshInstance3D.new()
		var bq := QuadMesh.new()
		bq.size = size - Vector2(0.004, 0.004)
		back.mesh = bq
		back.rotation_degrees.y = 180.0
		back.position.z = -0.0006
		back.material_override = _mat(Color(0.2, 0.08, 0.15), 0.8, 0.0)
		face.add_child(back)


## Shrinks a model until it fits the shelf (height and width, from its meshes' bounds).
func _fit(model: Node3D, max_h: float, max_w: float) -> void:
	var box := AABB()
	var first := true
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var b := _relative_xf(model, m) * m.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if first:
		return
	var s := minf(1.0, minf(max_h / maxf(box.size.y, 0.001), max_w / maxf(maxf(box.size.x, box.size.z), 0.001)))
	model.scale = Vector3.ONE * s


func _relative_xf(root: Node3D, n: Node3D) -> Transform3D:
	var t := Transform3D()
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t


# ---------------------------------------------------------------- the furniture

func _build_cabinet() -> void:
	var w := COLS * CELL.x + 0.04
	var h := ROWS * CELL.y + BOARD
	var z := SHELF_Z
	_box(Vector3(w, h, 0.012), Vector3(0, h * 0.5, z - SHELF_DEPTH * 0.5), _plum) # back wall
	for side in [-1.0, 1.0]:
		_box(Vector3(0.02, h + 0.02, SHELF_DEPTH), Vector3(side * (w * 0.5 + 0.01), h * 0.5, z), _wood)
	_box(Vector3(w + 0.06, 0.025, SHELF_DEPTH + 0.02), Vector3(0, h + 0.012, z), _wood) # top
	var brass := _mat(Color(0.9, 0.68, 0.3), 0.3, 0.7)
	for r in ROWS + 1: # the shelves, a brass edge on each
		var y := r * CELL.y + BOARD * 0.5
		_box(Vector3(w, BOARD, SHELF_DEPTH), Vector3(0, y, z), _wood)
		_box(Vector3(w, 0.004, 0.004), Vector3(0, y + BOARD * 0.5, z + SHELF_DEPTH * 0.5), brass)
	var glow := OmniLight3D.new() # a warm light inside the cabinet
	glow.light_color = Color(1.0, 0.85, 0.6)
	glow.light_energy = 0.8
	glow.omni_range = 0.9
	glow.position = Vector3(0, h * 0.6, z + 0.25)
	add_child(glow)
	# above it: the collection's name and the pages
	var front := z + SHELF_DEPTH * 0.5
	_title = _label("", 56, 0.0009, Color(1.0, 0.85, 0.45))
	_title.position = Vector3(0, h + 0.085, front)
	add_child(_title)
	_page_label = _label("1 / 1", 34, 0.0008, Color(0.95, 0.92, 0.85))
	_page_label.position = Vector3(0, h + 0.04, front)
	add_child(_page_label)
	_button("<", PREV_ID, Vector3(-0.4, h + 0.07, front), Vector2(0.08, 0.06), _orange, self)
	_button(">", NEXT_ID, Vector3(0.4, h + 0.07, front), Vector2(0.08, 0.06), _orange, self)


## Left of the cabinet: a column of signs, one per collection, then STATS and BACK.
func _build_column() -> void:
	var col := Node3D.new()
	col.position = Vector3(-(COLS * CELL.x * 0.5 + 0.2), 0.0, SHELF_Z + SHELF_DEPTH * 0.5 + 0.03)
	col.rotation_degrees.y = 15.0 # turned a little towards you
	add_child(col)
	var post := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.012, 0.64, 0.012)
	post.mesh = pm
	post.material_override = _mat(Color(0.2, 0.2, 0.22), 0.5, 0.5)
	post.position = Vector3(0, 0.32, -0.015)
	col.add_child(post)
	for i in 12:
		_cat_buttons.append(_button("", CAT_ID - i, Vector3(0, 0.64 - i * 0.044, 0), Vector2(0.24, 0.037), _plum, col))
	_button("STATS", STATS_ID, Vector3(0, 0.085, 0), Vector2(0.24, 0.042), _mat(Color(0.2, 0.45, 0.75), 0.5, 0.0), col)
	_button("BACK", BACK_ID, Vector3(0, 0.035, 0), Vector2(0.24, 0.042), _mat(Color(0.75, 0.2, 0.2), 0.5, 0.0), col)


## Right of the cabinet: the info plate for what the beam is on.
func _build_info() -> void:
	var root := Node3D.new()
	root.position = Vector3(COLS * CELL.x * 0.5 + 0.22, 0.0, SHELF_Z + SHELF_DEPTH * 0.5 + 0.03)
	root.rotation_degrees.y = -15.0 # turned a little towards you
	add_child(root)
	var stand := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.012, 0.18, 0.012)
	stand.mesh = sm
	stand.material_override = _mat(Color(0.2, 0.2, 0.22), 0.5, 0.5)
	stand.position.y = 0.09
	root.add_child(stand)
	var plate := Node3D.new()
	plate.position.y = 0.36
	plate.rotation_degrees.x = -8.0
	root.add_child(plate)
	var bg := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.3, 0.38, 0.01)
	bg.mesh = bm
	bg.material_override = _mat(Color(0.12, 0.05, 0.11), 0.6, 0.0)
	plate.add_child(bg)
	var rim := MeshInstance3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(0.31, 0.39, 0.006)
	rim.mesh = rm
	rim.material_override = _orange
	rim.position.z = -0.004
	plate.add_child(rim)
	_info_name = _label("", 40, 0.0008, Color(1.0, 0.88, 0.5))
	_info_name.position = Vector3(0, 0.16, 0.007)
	_info_name.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_info_name.width = 0.27 / 0.0008
	_info_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	plate.add_child(_info_name)
	_info_kind = _label("", 30, 0.0007, Color(0.6, 0.85, 1.0))
	_info_kind.position = Vector3(0, 0.085, 0.007)
	plate.add_child(_info_kind)
	_info_text = _label("", 30, 0.0007, Color(0.96, 0.94, 0.9))
	_info_text.position = Vector3(0, 0.06, 0.007)
	_info_text.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_info_text.width = 0.27 / 0.0007
	_info_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	plate.add_child(_info_text)
	_show_info({})


# ---------------------------------------------------------------- helpers

func _button(text: String, id: int, at: Vector3, size: Vector2, mat: Material, parent: Node3D) -> Array:
	var root := Node3D.new()
	root.position = at
	parent.add_child(root)
	var plate := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(size.x, size.y, 0.01)
	plate.mesh = bm
	plate.material_override = mat
	root.add_child(plate)
	var l := _label(text, 30 if size.y < 0.04 else 44, 0.0006, Color(1.0, 0.97, 0.92))
	l.position.z = 0.006
	root.add_child(l)
	_body(root, id, Vector3(size.x, size.y, 0.02), Vector3.ZERO)
	return [plate, l]


func _body(parent: Node3D, id: int, size: Vector3, pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.set_meta("target_id", id)
	body.set_meta("kind", "collect")
	body.position = pos
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	shape.shape = bs
	body.add_child(shape)
	parent.add_child(body)


func _label(text: String, size: int, pixel: float, colour: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = pixel
	l.modulate = colour
	l.outline_size = 8
	l.outline_modulate = Color(0.05, 0.03, 0.06)
	return l


func _box(size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.position = pos
	mi.material_override = mat
	add_child(mi)


func _mat(c: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m
