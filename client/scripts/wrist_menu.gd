class_name WristMenu
extends Node3D
## A small menu that floats just above your card hand (the menu button ≡ on the left controller
## opens and closes it): the VR settings right where you are, without Balatro's Options menu.
## Two columns (each entry says which: "col" 0 = left, 1 = right; without it the first half goes
## left, the rest right); the last entry (Close) runs across both at the bottom.
## Buttons are clicked with the beam like everything else; `items` says what they are called right
## now and what they do.

const BUTTON := Vector2(0.15, 0.028)
const GAP := 0.006
const BASE_ID := -100              # target ids of the buttons: BASE_ID - index
const MINUS_ID := -150             # its − button: MINUS_ID - index, + button: PLUS_ID - index
const PLUS_ID := -175
const COLUMN_GAP := 0.008
const SIDE := 0.026                # width of a − / + button

## [{"label": Callable -> String, "action": Callable}] - optional "minus" / "plus": Callable puts a
## small − and + button at the ends of that row (e.g. the floor height); optional "colour": Color
## gives the button its own colour (the game's red Run Info, orange Options)
var items: Array = []
var hand: Node3D                   # the card hand it is fixed to (the fan of cards)
var offset := Transform3D()        # its place relative to that hand (set by main.gd)
var eyes: Callable                 # -> Vector3 (unused since the menu sits fixed on the hand)

var _labels: Array[Label3D] = []
var _panel: MeshInstance3D


func setup(entries: Array) -> void:
	items = entries
	for c in get_children():
		c.queue_free()
	_labels.clear()
	var half := int(ceil((items.size() - 1) / 2.0))
	var col: Array[int] = [] # each entry's column and its row in it
	var row_of: Array[int] = []
	var rows := [0, 0]
	for i in items.size() - 1:
		var c := int(items[i].get("col", 0 if i < half else 1))
		col.append(c)
		row_of.append(rows[c])
		rows[c] += 1
	var per_column := maxi(rows[0], rows[1])
	var h := (per_column + 1) * (BUTTON.y + GAP) + 0.03
	var full := BUTTON.x * 2.0 + COLUMN_GAP
	_panel = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(full + 0.02, h + 0.025, 0.004)
	_panel.mesh = box
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.albedo_color = Color(0.16, 0.2, 0.23) # the game's dark slate
	_panel.material_override = pm
	_panel.position.y = -h * 0.5 + 0.012
	add_child(_panel)
	var title := Label3D.new()
	title.text = "VR SETTINGS"
	title.font_size = 32
	title.pixel_size = 0.0005
	title.outline_size = 0
	title.modulate = Color(1.0, 0.8, 0.3)
	title.position = Vector3(0, 0.0, 0.004)
	add_child(title)
	for i in items.size():
		var last := i == items.size() - 1
		var row := per_column if last else row_of[i]
		var y := -0.025 - row * (BUTTON.y + GAP)
		var bx := 0.0 if last else (BUTTON.x + COLUMN_GAP) * 0.5 * (-1.0 if col[i] == 0 else 1.0)
		var bw := full if last else BUTTON.x
		var b := MeshInstance3D.new()
		var q := BoxMesh.new()
		q.size = Vector3(bw, BUTTON.y, 0.004)
		b.mesh = q
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = items[i].get("colour", Color(0.33, 0.62, 0.5) if not last else Color(0.85, 0.35, 0.3))
		b.material_override = m
		b.position = Vector3(bx, y, 0.003)
		add_child(b)
		var l := Label3D.new()
		l.font_size = 32
		l.pixel_size = 0.00045
		l.outline_size = 0
		l.position = Vector3(bx, y, 0.0062)
		add_child(l)
		_labels.append(l)
		if items[i].has("minus"):
			for k in 2: # − at the left end, + at the right end of the row
				var x := bx + (BUTTON.x - SIDE) * 0.5 * (-1.0 if k == 0 else 1.0)
				var sb := MeshInstance3D.new()
				var sq := BoxMesh.new()
				sq.size = Vector3(SIDE, BUTTON.y, 0.004)
				sb.mesh = sq
				var sm := StandardMaterial3D.new()
				sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				sm.albedo_color = Color(0.2, 0.42, 0.34)
				sb.material_override = sm
				sb.position = Vector3(x, y, 0.0045)
				add_child(sb)
				var sl := Label3D.new()
				sl.text = "-" if k == 0 else "+"
				sl.font_size = 40
				sl.pixel_size = 0.0005
				sl.outline_size = 0
				sl.position = Vector3(x, y, 0.0072)
				add_child(sl)
				_add_body((MINUS_ID if k == 0 else PLUS_ID) - i, Vector3(SIDE, BUTTON.y, 0.012), Vector3(x, y, 0.006))
		_add_body(BASE_ID - i, Vector3(bw, BUTTON.y, 0.01), Vector3(bx, y, 0.004))
	GameFont.apply_to(self)
	refresh()


func _add_body(id: int, size: Vector3, at: Vector3) -> void:
	var body := StaticBody3D.new()
	body.set_meta("target_id", id)
	body.set_meta("kind", "wrist")
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	shape.shape = bs
	body.add_child(shape)
	body.position = at
	add_child(body)


## Hidden buttons must not be hit: an invisible body still stops the beam in Godot.
func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		for c in get_children():
			if c is StaticBody3D:
				(c as StaticBody3D).collision_layer = 1 if is_visible_in_tree() else 0


func refresh() -> void:
	for i in _labels.size():
		_labels[i].text = (items[i]["label"] as Callable).call()


func press(id: int) -> void:
	for key in ["minus", "plus"]:
		var j := (MINUS_ID if key == "minus" else PLUS_ID) - id
		if j >= 0 and j < items.size() and items[j].has(key):
			(items[j][key] as Callable).call()
			refresh()
			return
	var i := BASE_ID - id
	if i < 0 or i >= items.size():
		return
	(items[i]["action"] as Callable).call()
	refresh()


func _process(_delta: float) -> void:
	if not visible or hand == null:
		return
	# fixed to the card hand like the cards themselves: it moves and turns with the hand
	# (unscaled, even if the fan was made bigger or smaller)
	var h := hand.global_transform
	global_transform = Transform3D(h.basis.orthonormalized(), h.origin) * offset
