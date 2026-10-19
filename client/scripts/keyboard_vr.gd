class_name KeyboardVR
extends Node3D
## A small keyboard over the table for the game's text boxes: the seed of a seeded run, a new
## profile's name. It pops up when such a box is on screen and types into it with the beam:
## 1-9 (and 0 for names), A-Z, BACKSPACE, SPACE (names only), SHIFT (names: lower case) and OK. What is typed shows on
## a strip above the keys (the game's box on the board shows it too).
## Coordinates: +z towards the player, the keys on a slanted plate like a laptop keyboard.

signal typed(k: String, caps: bool) # to the mod: {"cmd": "text_key", "key": k, "caps": caps}
signal done                        # OK: the box is filled in

const KEY := 0.042
const GAP := 0.006
# (the 0 only for names: in a seed the game turns a 0 into an O - seeds never have one)
const ROWS := ["1234567890", "QWERTYUIOP", "ASDFGHJKL", "ZXCVBNM"]
const ID := -900                   # - index of the key in _keys

var _keys: Array = []              # [{"name", "plate": MeshInstance3D, "label": Label3D}]
var _text: Label3D
var _shift := false                # names: lower case letters while on
var _extended := false             # names allow a space (and lower case)
var _caps_only := false
var _mat_key: StandardMaterial3D
var _mat_wide: StandardMaterial3D
var _mat_ok: StandardMaterial3D
var _mat_on: StandardMaterial3D
var _press := {}                   # key index -> time left of its press flash


func _ready() -> void:
	_mat_key = _mat(Color(0.18, 0.08, 0.16))
	_mat_wide = _mat(Color(0.3, 0.12, 0.25))
	_mat_ok = _mat(Color(0.2, 0.6, 0.35))
	_mat_on = _mat(Color(0.95, 0.55, 0.12))
	var plate := Node3D.new()
	plate.name = "Plate"
	plate.rotation_degrees.x = -40.0 # slanted towards you
	add_child(plate)
	var width := 10 * (KEY + GAP) + 0.03
	var depth := 5 * (KEY + GAP) + 0.03
	var base := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(width, depth, 0.012)
	base.mesh = bm
	base.material_override = _mat(Color(0.06, 0.04, 0.07))
	base.position.z = -0.008
	plate.add_child(base)
	var rim := MeshInstance3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(width + 0.008, depth + 0.008, 0.008)
	rim.mesh = rm
	rim.material_override = _mat(Color(0.95, 0.55, 0.12))
	rim.position.z = -0.012
	plate.add_child(rim)
	# the typed text, on a strip above the keys
	_text = Label3D.new()
	_text.font_size = 56
	_text.pixel_size = 0.0007
	_text.outline_size = 10
	_text.outline_modulate = Color(0.05, 0.03, 0.06)
	_text.position = Vector3(0, depth * 0.5 + 0.035, 0.004)
	plate.add_child(_text)
	var y := depth * 0.5 - 0.015 - KEY * 0.5
	for r in ROWS.size():
		var row: String = ROWS[r]
		var x0 := -(row.length() - 1) * (KEY + GAP) * 0.5
		for i in row.length():
			_add_key(plate, row[i], Vector3(x0 + i * (KEY + GAP), y, 0), KEY)
		if r == ROWS.size() - 1: # BACKSPACE at the end of the last letter row
			_add_key(plate, "BACKSPACE", Vector3(x0 + row.length() * (KEY + GAP) + KEY * 0.3, y, 0), KEY * 1.6)
		y -= KEY + GAP
	_add_key(plate, "SHIFT", Vector3(-3.25 * (KEY + GAP), y, 0), KEY * 2.5)
	_add_key(plate, "SPACE", Vector3(0, y, 0), KEY * 4.2)
	_add_key(plate, "OK", Vector3(3.25 * (KEY + GAP), y, 0), KEY * 2.5)
	GameFont.apply_to(self)


## What the box on screen holds and allows (the mod's state "text_input").
var _info := {}                    # the box as the mod last described it


func show_box(info: Dictionary) -> void:
	_info = info
	_extended = bool(info.get("extended", false))
	_caps_only = bool(info.get("caps", false))
	var t := str(info.get("text", ""))
	var room := int(info.get("max", 0))
	_text.text = (t if t != "" else str(info.get("prompt", ""))) + ("   %d/%d" % [t.length(), room] if room > 0 else "")
	_text.modulate = Color(1.0, 0.92, 0.75) if t != "" else Color(0.6, 0.55, 0.6)
	for k in _keys:
		var n: String = k["name"]
		if n == "SPACE" or n == "0":
			(k["plate"] as Node3D).get_parent().visible = _extended
		elif n == "SHIFT":
			(k["plate"] as Node3D).get_parent().visible = _extended and not _caps_only
		elif n.length() == 1 and n >= "A" and n <= "Z":
			(k["label"] as Label3D).text = n.to_lower() if _shift and _extended and not _caps_only else n


func press(id: int) -> void:
	var i := ID - id
	if i < 0 or i >= _keys.size():
		return
	var n: String = _keys[i]["name"]
	_press[i] = 0.15
	match n:
		"SHIFT":
			_shift = not _shift
			show_box(_info)
		"BACKSPACE":
			typed.emit("backspace", false)
		"SPACE":
			typed.emit("space", false)
		"OK":
			typed.emit("return", false)
			done.emit()
		_:
			var lower := _shift and _extended and not _caps_only
			typed.emit(n.to_lower(), not lower) # (caps: the game turns it upper case)


func _process(delta: float) -> void:
	for i in _keys.size():
		var k: Dictionary = _keys[i]
		var t: float = _press.get(i, 0.0)
		if t > 0.0:
			_press[i] = t - delta
		var base: StandardMaterial3D = _mat_ok if k["name"] == "OK" else (_mat_wide if str(k["name"]).length() > 1 else _mat_key)
		if k["name"] == "SHIFT" and _shift:
			base = _mat_on
		(k["plate"] as MeshInstance3D).material_override = _mat_on if t > 0.0 else base
		(k["plate"] as MeshInstance3D).position.z = -0.004 if t > 0.0 else 0.0 # (pressed down a little)


func _add_key(parent: Node3D, n: String, at: Vector3, w: float) -> void:
	var root := Node3D.new()
	root.position = at
	parent.add_child(root)
	var plate := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(w, KEY, 0.01)
	plate.mesh = bm
	plate.material_override = _mat_key
	root.add_child(plate)
	var l := Label3D.new()
	l.text = {"BACKSPACE": "<-", "SPACE": "SPACE", "SHIFT": "SHIFT", "OK": "OK"}.get(n, n)
	l.font_size = 40 if n.length() == 1 else 28
	l.pixel_size = 0.0006
	l.outline_size = 6
	l.outline_modulate = Color(0.05, 0.03, 0.06)
	l.position.z = 0.006
	root.add_child(l)
	var body := StaticBody3D.new()
	body.set_meta("target_id", ID - _keys.size())
	body.set_meta("kind", "kbd")
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(w, KEY, 0.02)
	shape.shape = bs
	body.add_child(shape)
	root.add_child(body)
	_keys.append({"name": n, "plate": plate, "label": l})


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.5
	return m
