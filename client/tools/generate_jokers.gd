extends SceneTree
## Builds the placeholder scenes client/jokers/<joker key>.tscn from simple shapes.
## Existing scenes are NOT overwritten, so your own models stay safe. To rebuild one placeholder,
## delete its .tscn first. Run from the client folder:
##   Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/generate_jokers.gd
##
## Sizes are in meters (the props stand on the real table, ~5–15 cm tall).

const OUT := "res://jokers/"

const RED := Color(0.85, 0.2, 0.2)
const WHITE := Color(0.95, 0.95, 0.92)
const GREY := Color(0.6, 0.6, 0.65)
const STONE := Color(0.55, 0.52, 0.48)
const WOOD := Color(0.45, 0.3, 0.18)
const YELLOW := Color(0.95, 0.85, 0.25)
const GOLD := Color(0.9, 0.7, 0.2)

var _written := 0
var _skipped := 0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_castle(); _mail(); _popcorn(); _seltzer(); _banner(); _loyalty(); _cavendish()
	_ice_cream(); _ramen(); _turtle_bean(); _gros_michel(); _invisible(); _ancient(); _idol()
	_todo(); _green(); _bus(); _runner(); _square(); _obelisk(); _hologram(); _lucky_cat()
	_campfire(); _wee()
	print("Joker-Szenen: %d geschrieben, %d übersprungen (existieren schon)" % [_written, _skipped])
	quit()


# ---------------------------------------------------------------- the 24 jokers

func _castle() -> void:
	var r := _root()
	_box(r, "Wall", Vector3(0.08, 0.04, 0.05), Vector3(0, 0.02, 0), GREY)
	_cyl(r, "TowerLeft", 0.013, 0.013, 0.07, Vector3(-0.035, 0.035, 0), GREY)
	_cyl(r, "TowerRight", 0.013, 0.013, 0.07, Vector3(0.035, 0.035, 0), GREY)
	_cyl(r, "Keep", 0.017, 0.017, 0.09, Vector3(0, 0.045, 0), GREY)
	_cyl(r, "Pole", 0.002, 0.002, 0.05, Vector3(0, 0.115, 0), WOOD)
	_box(r, "Flag", Vector3(0.035, 0.022, 0.002), Vector3(0.018, 0.128, 0), WHITE) # colour = wanted suit
	r.suit_node = "Flag"
	_save(r, "j_castle")


func _mail() -> void:
	var r := _root()
	_box(r, "Post", Vector3(0.01, 0.1, 0.01), Vector3(0, 0.05, 0), WOOD)
	_box(r, "Box", Vector3(0.04, 0.035, 0.07), Vector3(0, 0.115, 0), RED)
	_box(r, "Flag", Vector3(0.003, 0.03, 0.008), Vector3(0.022, 0.13, 0.02), YELLOW)
	_label(r, "Sign", Vector3(0, 0.16, 0), "?")
	r.label_node = "Sign"
	r.label_source = "target[\"rank\"]"
	r.label_format = "Discard: %s"
	_save(r, "j_mail")


func _popcorn() -> void:
	var r := _root()
	_cyl(r, "Cup", 0.035, 0.027, 0.08, Vector3(0, 0.04, 0), RED)
	var fill := _pivot(r, "Fill", Vector3(0, 0.075, 0))
	_sphere(fill, "Popcorn", 0.036, 0.05, Vector3(0, 0.02, 0), Color(1.0, 0.95, 0.75))
	r.fill_node = "Fill"
	r.fill_source = "ab[\"mult\"]"
	r.fill_max = 20.0
	r.fill_min = 0.05
	_save(r, "j_popcorn")


func _seltzer() -> void:
	var r := _root()
	_cyl(r, "Glass", 0.013, 0.013, 0.11, Vector3(0, 0.055, 0), Color(0.85, 0.95, 1.0, 0.3))
	var fill := _pivot(r, "Fill", Vector3(0, 0.003, 0))
	_cyl(fill, "Water", 0.011, 0.011, 0.09, Vector3(0, 0.045, 0), Color(0.35, 0.65, 1.0, 0.8))
	_cyl(r, "Cork", 0.0135, 0.0135, 0.016, Vector3(0, 0.118, 0), WOOD)
	r.fill_node = "Fill"
	r.fill_source = "extra[\"value\"]"   # hands left (10 -> 0)
	r.fill_max = 10.0
	r.empty_source = "extra[\"value\"]"  # last hand: the cork is gone
	r.empty_at = 1.0
	r.hide_when_empty = "Cork"
	_save(r, "j_selzer")


func _banner() -> void:
	var r := _root()
	_cyl(r, "Pole", 0.003, 0.003, 0.16, Vector3(0, 0.08, 0), WOOD)
	var cloth := _box(r, "Cloth", Vector3(0.07, 0.05, 0.002), Vector3(0.036, 0.13, 0), Color(0.9, 0.85, 0.7))
	var stripes := Node3D.new()
	stripes.name = "Stripes"
	stripes.position = Vector3(0, 0, 0.0015)
	cloth.add_child(stripes)
	for i in 3:
		_box(stripes, "Stripe%d" % (i + 1), Vector3(0.06, 0.008, 0.001), Vector3(0, 0.015 - i * 0.015, 0), Color(0.08, 0.08, 0.08))
	var white := _box(r, "WhiteFlag", Vector3(0.07, 0.05, 0.002), Vector3(0.036, 0.13, 0), Color(1, 1, 1))
	white.visible = false
	r.count_parent = "Cloth/Stripes"
	r.count_source = "run[\"discards_left\"]"
	r.empty_source = "run[\"discards_left\"]"
	r.show_when_empty = "WhiteFlag"
	r.hide_when_empty = "Cloth"
	_save(r, "j_banner")


func _loyalty() -> void:
	var r := _root()
	_box(r, "Card", Vector3(0.085, 0.002, 0.055), Vector3(0, 0.001, 0), Color(0.95, 0.9, 0.75))
	var stamps := Node3D.new()
	stamps.name = "Stamps"
	stamps.position = Vector3(0, 0.003, 0)
	r.add_child(stamps)
	for i in 5:
		_cyl(stamps, "Stamp%d" % (i + 1), 0.006, 0.006, 0.002, Vector3(-0.03 + i * 0.015, 0, 0), RED)
	r.count_parent = "Stamps"
	r.count_source = "extra[\"every\"] - ab[\"loyalty_remaining\"]"
	r.glow_node = "Card"
	r.glow_source = "1.0 - min(ab[\"loyalty_remaining\"], 1.0)"  # glows when the x4 is ready
	r.glow_energy = 2.0
	_save(r, "j_loyalty_card")


func _cavendish() -> void:
	var r := _root()
	_capsule(r, "Banana", 0.012, 0.09, Vector3(0, 0.02, 0), Vector3(0, 0, 70), Color(1.0, 0.95, 0.4))
	r.glow_node = "Banana"
	r.glow_energy = 6.0   # so bright it outshines its neighbours
	_save(r, "j_cavendish")


func _ice_cream() -> void:
	var r := _root()
	_cyl(r, "Cone", 0.02, 0.002, 0.06, Vector3(0, 0.03, 0), Color(0.85, 0.65, 0.35))
	var fill := _pivot(r, "Fill", Vector3(0, 0.06, 0))
	_sphere(fill, "Scoop", 0.022, 0.044, Vector3(0, 0.016, 0), Color(1.0, 0.7, 0.8))
	r.fill_node = "Fill"
	r.fill_source = "extra[\"chips\"]"   # melts 100 -> 0
	r.fill_max = 100.0
	r.fill_min = 0.1
	r.fill_uniform = true
	_save(r, "j_ice_cream")


func _ramen() -> void:
	var r := _root()
	_cyl(r, "Bowl", 0.045, 0.03, 0.035, Vector3(0, 0.0175, 0), WHITE)
	var fill := _pivot(r, "Fill", Vector3(0, 0.02, 0))
	_cyl(fill, "Noodles", 0.04, 0.04, 0.014, Vector3(0, 0.007, 0), Color(0.95, 0.85, 0.45))
	_box(r, "Chopsticks", Vector3(0.11, 0.004, 0.004), Vector3(0.01, 0.045, 0.01), WOOD, Vector3(0, 20, 15))
	r.fill_node = "Fill"
	r.fill_source = "ab[\"x_mult\"] - 1.0"   # x2 -> x1
	r.fill_max = 1.0
	r.fill_min = 0.05
	_save(r, "j_ramen")


func _turtle_bean() -> void:
	var r := _root()
	var fill := _pivot(r, "Fill", Vector3(0, 0, 0))
	var bean := _sphere(fill, "Bean", 0.03, 0.04, Vector3(0, 0.02, 0), Color(0.35, 0.6, 0.25))
	bean.scale = Vector3(1.2, 1.0, 0.8)
	r.fill_node = "Fill"
	r.fill_source = "extra[\"h_size\"]"   # +5 hand size, shrinks each round
	r.fill_max = 5.0
	r.fill_min = 0.15
	r.fill_uniform = true
	_save(r, "j_turtle_bean")


func _gros_michel() -> void:
	var r := _root()
	_capsule(r, "Banana", 0.013, 0.1, Vector3(0, 0.02, 0), Vector3(0, 0, 70), Color(0.85, 0.9, 0.3))
	r.shake_node = "Banana"
	_save(r, "j_gros_michel")


func _invisible() -> void:
	var r := _root()
	var figure := Node3D.new()
	figure.name = "Figure"
	r.add_child(figure)
	_capsule(figure, "Body", 0.015, 0.07, Vector3(0, 0.035, 0), Vector3.ZERO, WHITE)
	_sphere(figure, "Head", 0.013, 0.026, Vector3(0, 0.083, 0), WHITE)
	r.alpha_node = "Figure"
	r.alpha_source = "0.15 + 0.85 * min(ab[\"invis_rounds\"] / 2.0, 1.0)"  # becomes solid when ready
	_save(r, "j_invisible")


func _ancient() -> void:
	var r := _root()
	_box(r, "Tablet", Vector3(0.06, 0.08, 0.015), Vector3(0, 0.04, 0), STONE)
	_box(r, "Gem", Vector3(0.018, 0.018, 0.006), Vector3(0, 0.05, 0.009), WHITE, Vector3(0, 0, 45))
	r.suit_node = "Gem"
	_save(r, "j_ancient")


func _idol() -> void:
	var r := _root()
	_box(r, "Pedestal", Vector3(0.04, 0.03, 0.04), Vector3(0, 0.015, 0), STONE)
	_capsule(r, "Statue", 0.012, 0.05, Vector3(0, 0.055, 0), Vector3.ZERO, GOLD)
	_label(r, "Sign", Vector3(0, 0.11, 0), "?")
	r.suit_node = "Statue"
	r.label_node = "Sign"
	r.label_source = "target[\"rank\"] + \" of \" + target[\"suit\"]"
	_save(r, "j_idol")


func _todo() -> void:
	var r := _root()
	_box(r, "Paper", Vector3(0.06, 0.002, 0.08), Vector3(0, 0.001, 0), WHITE, Vector3(0, 12, 0))
	_label(r, "Task", Vector3(0, 0.04, 0), "?")
	r.label_node = "Task"
	r.label_source = "ab[\"to_do\"]"
	_save(r, "j_todo_list")


func _green() -> void:
	var r := _root()
	var fill := _pivot(r, "Fill", Vector3(0, 0, 0))
	_cyl(fill, "Column", 0.015, 0.015, 0.12, Vector3(0, 0.06, 0), Color(0.3, 0.8, 0.35))
	_label(r, "Value", Vector3(0, 0.15, 0), "")
	r.fill_node = "Fill"
	r.fill_source = "ab[\"mult\"]"
	r.fill_max = 20.0
	r.fill_min = 0.02
	r.label_node = "Value"
	r.label_source = "ab[\"mult\"]"
	r.label_format = "+%d Mult"
	_save(r, "j_green_joker")


func _bus() -> void:
	var r := _root()
	_box(r, "Bus", Vector3(0.09, 0.04, 0.035), Vector3(0, 0.027, 0), YELLOW)
	_box(r, "Windows", Vector3(0.07, 0.012, 0.036), Vector3(0, 0.035, 0), Color(0.3, 0.5, 0.7))
	for i in 2:
		_cyl(r, "Wheel%d" % (i + 1), 0.008, 0.008, 0.037, Vector3(-0.028 + i * 0.056, 0.008, 0), Color(0.1, 0.1, 0.1), Vector3(90, 0, 0))
	_label(r, "Value", Vector3(0, 0.08, 0), "")
	r.label_node = "Value"
	r.label_source = "ab[\"mult\"]"
	r.label_format = "+%d Mult"
	_save(r, "j_ride_the_bus")


func _runner() -> void:
	var r := _root()
	_box(r, "Shoe", Vector3(0.06, 0.025, 0.025), Vector3(0, 0.0125, 0), RED)
	_box(r, "Sole", Vector3(0.062, 0.006, 0.027), Vector3(0, 0.003, 0), WHITE)
	_label(r, "Value", Vector3(0, 0.06, 0), "")
	r.label_node = "Value"
	r.label_source = "extra[\"chips\"]"
	r.label_format = "+%d Chips"
	_save(r, "j_runner")


func _square() -> void:
	var r := _root()
	var fill := _pivot(r, "Fill", Vector3(0, 0, 0))
	_box(fill, "Cube", Vector3(0.05, 0.05, 0.05), Vector3(0, 0.025, 0), Color(0.3, 0.45, 0.85))
	_label(r, "Value", Vector3(0, 0.08, 0), "")
	r.fill_node = "Fill"
	r.fill_source = "extra[\"chips\"]"
	r.fill_max = 64.0
	r.fill_min = 0.25
	r.fill_uniform = true
	r.label_node = "Value"
	r.label_source = "extra[\"chips\"]"
	r.label_format = "+%d Chips"
	_save(r, "j_square")


func _obelisk() -> void:
	var r := _root()
	var fill := _pivot(r, "Fill", Vector3(0, 0, 0))
	_box(fill, "Pillar", Vector3(0.025, 0.12, 0.025), Vector3(0, 0.06, 0), Color(0.8, 0.7, 0.5))
	_label(r, "Value", Vector3(0, 0.16, 0), "")
	r.fill_node = "Fill"
	r.fill_source = "ab[\"x_mult\"] - 1.0"
	r.fill_max = 3.0
	r.fill_min = 0.15
	r.label_node = "Value"
	r.label_source = "ab[\"x_mult\"]"
	r.label_format = "x%.1f"
	_save(r, "j_obelisk")


func _hologram() -> void:
	var r := _root()
	var figure := Node3D.new()
	figure.name = "Figure"
	r.add_child(figure)
	_capsule(figure, "Body", 0.015, 0.07, Vector3(0, 0.035, 0), Vector3.ZERO, Color(0.4, 0.9, 1.0, 0.5))
	_sphere(figure, "Head", 0.013, 0.026, Vector3(0, 0.083, 0), Color(0.4, 0.9, 1.0, 0.5))
	_label(r, "Value", Vector3(0, 0.12, 0), "")
	r.glow_node = "Figure"
	r.glow_source = "(ab[\"x_mult\"] - 1.0) / 3.0"
	r.spin_node = "Figure"
	r.spin_speed = 1.5
	r.label_node = "Value"
	r.label_source = "ab[\"x_mult\"]"
	r.label_format = "x%.2f"
	_save(r, "j_hologram")


func _lucky_cat() -> void:
	var r := _root()
	_sphere(r, "Body", 0.025, 0.05, Vector3(0, 0.025, 0), WHITE)
	_sphere(r, "Head", 0.018, 0.036, Vector3(0, 0.062, 0), WHITE)
	_cyl(r, "EarLeft", 0.0, 0.007, 0.012, Vector3(-0.01, 0.082, 0), WHITE)
	_cyl(r, "EarRight", 0.0, 0.007, 0.012, Vector3(0.01, 0.082, 0), WHITE)
	_capsule(r, "Paw", 0.005, 0.03, Vector3(0.022, 0.06, 0.005), Vector3(0, 0, -15), WHITE)
	_label(r, "Value", Vector3(0, 0.11, 0), "")
	r.glow_node = "Body"
	r.glow_source = "(ab[\"x_mult\"] - 1.0) / 3.0"
	r.label_node = "Value"
	r.label_source = "ab[\"x_mult\"]"
	r.label_format = "x%.2f"
	_save(r, "j_lucky_cat")


func _campfire() -> void:
	var r := _root()
	_box(r, "Log1", Vector3(0.07, 0.012, 0.012), Vector3(0, 0.006, 0), WOOD, Vector3(0, 30, 0))
	_box(r, "Log2", Vector3(0.07, 0.012, 0.012), Vector3(0, 0.006, 0), WOOD, Vector3(0, -30, 0))
	var fill := _pivot(r, "Fill", Vector3(0, 0.01, 0))
	_cyl(fill, "Flame", 0.0, 0.022, 0.06, Vector3(0, 0.03, 0), Color(1.0, 0.55, 0.1))
	r.fill_node = "Fill"
	r.fill_source = "ab[\"x_mult\"] - 1.0"   # grows with every card sold
	r.fill_max = 3.0
	r.fill_min = 0.1
	r.glow_node = "Fill"
	r.glow_energy = 3.0
	_save(r, "j_campfire")


func _wee() -> void:
	var r := _root()
	_capsule(r, "Body", 0.008, 0.035, Vector3(0, 0.0175, 0), Vector3.ZERO, Color(0.9, 0.3, 0.3))
	_sphere(r, "Head", 0.007, 0.014, Vector3(0, 0.042, 0), WHITE)
	_label(r, "Value", Vector3(0, 0.07, 0), "")
	r.label_node = "Value"
	r.label_source = "extra[\"chips\"]"
	r.label_format = "+%d Chips"
	_save(r, "j_wee")


# ---------------------------------------------------------------- building blocks

func _root() -> AugmentedJoker:
	return AugmentedJoker.new()


func _mat(colour: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	if colour.a < 0.999:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat


func _mesh(parent: Node, node_name: String, mesh: Mesh, pos: Vector3, colour: Color, rot := Vector3.ZERO) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.name = node_name
	m.mesh = mesh
	m.position = pos
	m.rotation_degrees = rot
	m.material_override = _mat(colour)
	parent.add_child(m)
	return m


func _box(parent: Node, node_name: String, size: Vector3, pos: Vector3, colour: Color, rot := Vector3.ZERO) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _mesh(parent, node_name, mesh, pos, colour, rot)


func _cyl(parent: Node, node_name: String, top: float, bottom: float, height: float, pos: Vector3, colour: Color, rot := Vector3.ZERO) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	return _mesh(parent, node_name, mesh, pos, colour, rot)


func _sphere(parent: Node, node_name: String, radius: float, height: float, pos: Vector3, colour: Color) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = height
	return _mesh(parent, node_name, mesh, pos, colour)


func _capsule(parent: Node, node_name: String, radius: float, height: float, pos: Vector3, rot: Vector3, colour: Color) -> MeshInstance3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	return _mesh(parent, node_name, mesh, pos, colour, rot)


## Empty node whose origin is the bottom of what it holds, so scaling it grows/shrinks from the bottom.
func _pivot(parent: Node, node_name: String, pos: Vector3) -> Node3D:
	var p := Node3D.new()
	p.name = node_name
	p.position = pos
	parent.add_child(p)
	return p


func _label(parent: Node, node_name: String, pos: Vector3, text: String) -> Label3D:
	var l := Label3D.new()
	l.name = node_name
	l.text = text
	l.position = pos
	l.font_size = 36
	l.pixel_size = 0.0005
	l.outline_size = 8
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	parent.add_child(l)
	return l


func _own(node: Node, root: Node) -> void:
	for child in node.get_children():
		child.owner = root
		_own(child, root)


func _save(root: AugmentedJoker, key: String) -> void:
	var path := OUT + key + ".tscn"
	root.name = key
	if FileAccess.file_exists(path):
		_skipped += 1
		root.free()
		return
	_own(root, root)
	var scene := PackedScene.new()
	var err := scene.pack(root)
	if err == OK:
		err = ResourceSaver.save(scene, path)
	if err != OK:
		push_error("%s konnte nicht gespeichert werden (Fehler %d)" % [path, err])
	else:
		_written += 1
	root.free()
