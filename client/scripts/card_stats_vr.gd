class_name CardStatsVR
extends Node3D
## The game's Card Stats (Stats -> Card Stats: the most used jokers, consumables, vouchers) as columns
## standing around you in a half circle: one per card, as high as how often it was used, in the
## game's colour for its kind; the card on top, the number above it, the name at its foot. The most
## used one stands right in front of you, the others alternate to the left and right.
## Origin = where you stand (on the floor), facing -z.

const RADIUS := 1.35
const SPREAD := 150.0                # degrees of the half circle
const MAX_H := 1.1                   # the most used card's column
const BASE_Y := 0.75                 # columns stand on a dark plinth this high (about table height)
const CARD := Vector2(0.15, 0.2)

signal pressed(action: String, label: String)   # "tab" (label), "back", "close"

const BASE_ID := -800                # tab buttons: BASE_ID - index; then CLOSE
var buttons_y := 1.1                 # height of the button row (set from your eyes when it opens)
var _key := ""
var _title: Label3D
var _tabs: Array = []


## info: {title, cards: [{name, count, colour, sprite}]} from the mod; empty: nothing shown.
func show_stats(info: Dictionary) -> void:
	var key := JSON.stringify(info)
	if key == _key:
		return
	_key = key
	for c in get_children():
		c.queue_free()
	var cards: Array = info.get("cards", [])
	visible = not cards.is_empty()
	if cards.is_empty():
		return
	var top := 1.0
	for c in cards:
		top = maxf(top, float(c.get("count", 0)))
	_title = _label("MOST USED " + str(info.get("title", "")).to_upper(), 64, 0.0012, Color(1.0, 0.85, 0.4))
	_title.position = Vector3(0, BASE_Y + MAX_H + 0.55, -RADIUS - 0.2)
	for i in cards.size():
		var c: Dictionary = cards[i]
		# 0 in front, then 1 left, 2 right, 3 left ...: the ranking spreads out from the middle
		var slot: float = 0.0 if i == 0 else (ceil(i / 2.0) * (-1.0 if i % 2 == 1 else 1.0))
		var a := deg_to_rad(slot * SPREAD / 10.0)
		var holder := Node3D.new()
		holder.position = Vector3(sin(a), 0, -cos(a)) * RADIUS
		holder.rotation.y = -a # facing you
		add_child(holder)
		var colour: Color = Board.to_color(c.get("colour"))
		var h := maxf(float(c.get("count", 0)) / top * MAX_H, 0.02)
		var plinth := _box(Vector3(0.24, BASE_Y, 0.24), Vector3(0, BASE_Y * 0.5, 0), Color(0.08, 0.06, 0.1), 0.0)
		holder.add_child(plinth)
		var col := _box(Vector3(0.14, h, 0.14), Vector3(0, BASE_Y + h * 0.5, 0), colour, 0.6)
		holder.add_child(col)
		var card := Node3D.new()
		card.position = Vector3(0, BASE_Y + h + CARD.y * 0.5 + 0.03, 0)
		holder.add_child(card)
		var sprite = c.get("sprite")
		var mat := CardArt.material(sprite.get("atlas"), sprite.get("pos")) if sprite is Dictionary else null
		CardArt.apply_layers(card, [mat] if mat != null else [], CARD, 0.0, 0.0004, 1)
		var count := _label(str(int(c.get("count", 0))), 72, 0.001, Color(1.0, 0.75, 0.3))
		count.position = card.position + Vector3(0, CARD.y * 0.5 + 0.06, 0)
		holder.add_child(count)
		var name := _label(str(c.get("name", "")), 36, 0.0008, Color(1, 1, 1))
		name.position = Vector3(0, BASE_Y - 0.06, 0.125)
		name.width = 0.24 / name.pixel_size
		name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		holder.add_child(name)
		var rank := _label("#%d" % (i + 1), 48, 0.0008, Color(0.75, 0.7, 0.8))
		rank.position = Vector3(0, BASE_Y - 0.16, 0.125)
		holder.add_child(rank)
	add_child(_title)
	# the game's tabs and CLOSE as a row of buttons in front of you (the game board is hidden)
	_tabs = info.get("tabs", [])
	var labels: Array = _tabs.duplicate()
	labels.append("CLOSE") # (one way out: the game's BACK and CLOSE ended up the same in VR)
	for k in labels.size():
		var x := (k - (labels.size() - 1) * 0.5) * 0.19
		var at := Vector3(x, buttons_y, -0.75)
		var current: bool = k < _tabs.size() and str(_tabs[k]) == str(info.get("current", ""))
		var colour := Color(0.95, 0.25, 0.25) if k < _tabs.size() else (Color(0.95, 0.6, 0.1) if k == _tabs.size() else Color(0.4, 0.4, 0.45))
		if current:
			colour = colour.lightened(0.35)
		var b := _box(Vector3(0.17, 0.06, 0.02), at, colour, 0.3 if current else 0.0)
		b.rotation_degrees.x = -20.0
		add_child(b)
		var l := _label(str(labels[k]), 40, 0.0006, Color(1, 1, 1))
		l.position = at + Vector3(0, 0.0035, 0.012)
		l.rotation_degrees.x = -20.0
		add_child(l)
		var body := StaticBody3D.new()
		body.set_meta("target_id", BASE_ID - k)
		body.set_meta("kind", "cstats")
		var shape := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(0.17, 0.06, 0.04)
		shape.shape = bs
		body.add_child(shape)
		body.position = at
		body.rotation_degrees.x = -20.0
		add_child(body)
	GameFont.apply_to(self)


## A button of the row was pressed (main.gd's beam).
func press(id: int) -> void:
	var k := BASE_ID - id
	if k >= 0 and k < _tabs.size():
		pressed.emit("tab", str(_tabs[k]))
	elif k == _tabs.size():
		pressed.emit("close", "")


func hide_stats() -> void:
	_key = ""
	visible = false


func _label(text: String, size: int, pixel: float, colour: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = pixel
	l.modulate = colour
	l.outline_size = 10
	l.outline_modulate = Color(0.05, 0.03, 0.06)
	return l


func _box(size: Vector3, pos: Vector3, colour: Color, glow: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = 0.5
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = colour
		m.emission_energy_multiplier = glow
	mi.material_override = m
	mi.position = pos
	return mi
