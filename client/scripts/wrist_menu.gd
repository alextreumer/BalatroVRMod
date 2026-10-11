class_name WristMenu
extends Node3D
## A small menu that floats just above your card hand (the menu button ≡ on the left controller
## opens and closes it): the VR settings right where you are, without Balatro's Options menu.
## Buttons are clicked with the beam like everything else; `items` says what they are called right
## now and what they do.

const BUTTON := Vector2(0.15, 0.028)
const GAP := 0.006
const BASE_ID := -100              # target ids of the buttons: BASE_ID - index

## [{"label": Callable -> String, "action": Callable}]
var items: Array = []
var hand: Node3D                   # the card hand it floats above
var eyes: Callable                 # -> Vector3

var _labels: Array[Label3D] = []
var _panel: MeshInstance3D
var _height := 0.2                 # of all the buttons (set in setup)


func setup(entries: Array) -> void:
	items = entries
	for c in get_children():
		c.queue_free()
	_labels.clear()
	var h := items.size() * (BUTTON.y + GAP) + 0.03
	_height = h
	_panel = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(BUTTON.x + 0.02, h + 0.025, 0.004)
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
		var y := -0.025 - i * (BUTTON.y + GAP)
		var b := MeshInstance3D.new()
		var q := BoxMesh.new()
		q.size = Vector3(BUTTON.x, BUTTON.y, 0.004)
		b.mesh = q
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0.33, 0.62, 0.5) if i < items.size() - 1 else Color(0.85, 0.35, 0.3)
		b.material_override = m
		b.position = Vector3(0, y, 0.003)
		add_child(b)
		var l := Label3D.new()
		l.font_size = 32
		l.pixel_size = 0.00045
		l.outline_size = 0
		l.position = Vector3(0, y, 0.0062)
		add_child(l)
		_labels.append(l)
		var body := StaticBody3D.new()
		body.set_meta("target_id", BASE_ID - i)
		body.set_meta("kind", "wrist")
		var shape := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(BUTTON.x, BUTTON.y, 0.01)
		shape.shape = bs
		body.add_child(shape)
		body.position = Vector3(0, y, 0.004)
		add_child(body)
	GameFont.apply_to(self)
	refresh()


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
	var i := BASE_ID - id
	if i < 0 or i >= items.size():
		return
	(items[i]["action"] as Callable).call()
	refresh()


func _process(_delta: float) -> void:
	if not visible or hand == null:
		return
	# above the card hand, turned towards you
	# its lower edge a little above the hand: the hand (or the clown glove) never covers the buttons
	var at := hand.global_position + Vector3(0, _height + 0.05, 0)
	var e: Vector3 = eyes.call() if eyes.is_valid() else at + Vector3.BACK
	var to := e - at
	if to.length() > 0.01:
		global_transform = Transform3D(Basis.looking_at(-to, Vector3.UP), at)
