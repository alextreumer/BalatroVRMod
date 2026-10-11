class_name VRTutorial
extends Node3D
## Jimbo's tips: a small board floating in front of you on the very first start in VR (and again
## from the game's Options menu, "VR: Show Tips"). A few pages on the gestures; "Next" and "Skip"
## are clicked with the beam like everything else. Jimbo stands beside it.

signal finished

const SIZE := Vector2(0.54, 0.36)
const NEXT_ID := -10
const SKIP_ID := -11

var _pages: Array = []      # [title, text]
var _page := 0
var _title: Label3D
var _text: Label3D
var _dots: Label3D
var _next_label: Label3D
var _jimbo: Node3D
var _time := 0.0


func setup(pages: Array) -> void:
	_pages = pages
	_page = 0
	if _title == null:
		_build()
	_show()


func _build() -> void:
	var panel := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(SIZE.x, SIZE.y, 0.008)
	panel.mesh = box
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.2, 0.25, 0.28) # the game's dark slate panels
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED # readable in a dark room too
	m.roughness = 0.7
	panel.material_override = m
	add_child(panel)
	var rim := MeshInstance3D.new()
	var rim_box := BoxMesh.new()
	rim_box.size = Vector3(SIZE.x + 0.016, SIZE.y + 0.016, 0.004)
	rim.mesh = rim_box
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(0.85, 0.85, 0.88)
	rim.material_override = rm
	rim.position.z = -0.004
	add_child(rim)
	_title = _label(48, 0.001, Color(1.0, 0.8, 0.3), Vector3(0, SIZE.y * 0.5 - 0.035, 0.006))
	_text = _label(32, 0.00072, Color(0.95, 0.95, 0.95), Vector3(0, -0.005, 0.006))
	_text.width = (SIZE.x - 0.06) / _text.pixel_size
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_dots = _label(40, 0.0008, Color(0.7, 0.75, 0.8), Vector3(0, -SIZE.y * 0.5 + 0.03, 0.006))
	_next_label = _button("Next", Vector3(SIZE.x * 0.5 - 0.07, -SIZE.y * 0.5 + 0.03, 0.006), Color(0.95, 0.4, 0.3), NEXT_ID)
	_button("Skip", Vector3(-SIZE.x * 0.5 + 0.06, -SIZE.y * 0.5 + 0.03, 0.006), Color(0.4, 0.45, 0.5), SKIP_ID)
	var scene := load("res://jokers/jimbo_companion.tscn") as PackedScene
	if scene != null:
		_jimbo = scene.instantiate()
		_jimbo.scale = Vector3.ONE * 1.6
		_jimbo.position = Vector3(-SIZE.x * 0.5 - 0.09, -SIZE.y * 0.5 - 0.02, 0.03)
		_jimbo.rotation_degrees.y = 20.0
		add_child(_jimbo)
	GameFont.apply_to(self)


func _label(size: int, pixel: float, colour: Color, pos: Vector3) -> Label3D:
	var l := Label3D.new()
	l.font_size = size
	l.pixel_size = pixel
	l.modulate = colour
	l.outline_size = 0
	l.position = pos
	add_child(l)
	return l


## A clickable button (the beam finds it by its body, like the board's buttons).
func _button(text: String, pos: Vector3, colour: Color, id: int) -> Label3D:
	var b := MeshInstance3D.new()
	var q := BoxMesh.new()
	q.size = Vector3(0.1, 0.035, 0.006)
	b.mesh = q
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	b.material_override = m
	b.position = pos
	add_child(b)
	var l := _label(40, 0.0008, Color(1, 1, 1), pos + Vector3(0, 0, 0.004))
	l.text = text
	var body := StaticBody3D.new()
	body.set_meta("target_id", id)
	body.set_meta("kind", "tutorial")
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.1, 0.035, 0.02)
	shape.shape = bs
	body.add_child(shape)
	body.position = pos
	add_child(body)
	return l


## Hidden buttons must not be hit: an invisible body still stops the beam in Godot.
func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		for c in get_children():
			if c is StaticBody3D:
				(c as StaticBody3D).collision_layer = 1 if is_visible_in_tree() else 0


func press(id: int) -> void:
	if id == SKIP_ID or _page >= _pages.size() - 1:
		visible = false
		finished.emit()
		return
	_page += 1
	_show()


func _show() -> void:
	visible = true
	var p: Array = _pages[_page]
	_title.text = p[0]
	_text.text = p[1]
	var dots := ""
	for i in _pages.size():
		dots += ("● " if i == _page else "○ ")
	_dots.text = dots.strip_edges()
	_next_label.text = "Let's go!" if _page == _pages.size() - 1 else "Next"


func _process(delta: float) -> void:
	_time += delta
	if _jimbo != null and visible: # Jimbo bobs a little while he talks
		_jimbo.position.y = -SIZE.y * 0.5 - 0.02 + absf(sin(_time * 3.0)) * 0.01
