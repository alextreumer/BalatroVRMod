class_name CoinPile
extends Node3D
## The player's money as stacks of gold coins on the table: one coin per dollar (up to MAX_COINS),
## ten per stack. New coins drop onto the stacks one after another, spent coins vanish from the top.
## No number on top: the exact amount is in the Run Panel. In debt (Credit Card) the coins are gone
## and an IOU note lies there instead, with the amount owed.

const MAX_COINS := 100
const PER_STACK := 10
const COIN_RADIUS := 0.013
const COIN_THICK := 0.0032
const STEP := 0.03                # distance between stacks
const DROP := 0.06                # coins fall from this height
const COIN_INTERVAL := 0.035      # seconds between two coins
const GOLD := Color(0.98, 0.74, 0.22)

## stack positions: a tight cluster growing outwards from the middle
const STACKS := [Vector2(0, 0), Vector2(1, 0), Vector2(0.5, -0.87), Vector2(-0.5, -0.87), Vector2(-1, 0),
		Vector2(-0.5, 0.87), Vector2(0.5, 0.87), Vector2(2, 0), Vector2(1.5, -0.87), Vector2(-2, 0)]

var _coins: Array[MeshInstance3D] = []
var _drop_time: Array[float] = []    # per coin: seconds since it started falling
var _target := 0
var _timer := 0.0
var _mesh: CylinderMesh
var _mat: StandardMaterial3D
var _iou: Node3D            # the debt note
var _iou_amount: Label3D
var _money: Label3D         # "$13" in front of the pile
var _iou_scale := 0.0       # pop-in animation 0..1
var _rng := RandomNumberGenerator.new()
var _flyers: Array[Dictionary] = []   # coins on their way in or out
var _held_back := 0                   # earned coins still in the air (they join the pile on landing)
const FLY_TIME := 0.55
var tremble := false                  # The Ox: the coins rattle
signal landed                         # a flying coin reached the pile (clink)


func _ready() -> void:
	_rng.seed = 11
	_mesh = CylinderMesh.new()
	_mesh.top_radius = COIN_RADIUS
	_mesh.bottom_radius = COIN_RADIUS
	_mesh.height = COIN_THICK
	_mesh.radial_segments = 20
	_mesh.rings = 1
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = GOLD
	_mat.metallic = 0.6
	_mat.roughness = 0.3
	_mat.emission_enabled = true # keeps the gold bright in dim rooms
	_mat.emission = GOLD * 0.3
	_build_iou()
	_money = Label3D.new()
	_money.font_size = 48
	_money.pixel_size = 0.0007
	_money.outline_size = 8
	_money.modulate = GOLD
	_money.outline_modulate = Color(0.25, 0.15, 0.02)
	_money.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_money.position = Vector3(0, 0.012, STEP * 1.9) # just in front of the stacks, towards you
	add_child(_money)


func set_amount(dollars: int) -> void:
	_target = clampi(dollars, 0, MAX_COINS)
	_iou.visible = dollars < 0
	_iou_amount.text = "$%d" % -dollars
	# the money you have right now, in front of the pile (in debt the IOU note says it)
	_money.visible = dollars >= 0
	_money.text = "$%d" % dollars


## A small cream paper note lying flat on the table: "IOU", the debt in red, a scribbled signature.
func _build_iou() -> void:
	_iou = Node3D.new()
	_iou.rotation_degrees.y = 14.0 # dropped casually, not quite straight
	_iou.visible = false
	add_child(_iou)
	var paper := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.1, 0.0008, 0.065)
	paper.mesh = box
	var paper_mat := StandardMaterial3D.new()
	paper_mat.albedo_color = Color(0.96, 0.92, 0.8)
	paper_mat.roughness = 0.95
	paper.material_override = paper_mat
	paper.position.y = 0.0004
	_iou.add_child(paper)
	var red := Color(0.75, 0.12, 0.12)
	var ink := Color(0.15, 0.13, 0.2)
	var frame := StandardMaterial3D.new()
	frame.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	frame.albedo_color = red
	for z in [-0.0285, 0.0285]: # thin red border
		_line(Vector3(0.092, 0.0002, 0.0012), Vector3(0, 0.0009, z), frame)
	for x in [-0.0455, 0.0455]:
		_line(Vector3(0.0012, 0.0002, 0.058), Vector3(x, 0.0009, 0), frame)
	_text("IOU", Vector3(0, 0, -0.017), 0.00028, ink)
	_iou_amount = _text("$0", Vector3(0, 0, 0.002), 0.0004, red)
	_text("~ Jimbo ~", Vector3(0.02, 0, 0.019), 0.00014, ink)


func _line(size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = mat
	mi.position = pos
	_iou.add_child(mi)


func _text(text: String, pos: Vector3, pixel: float, colour: Color) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = 64
	label.pixel_size = pixel
	label.modulate = colour
	label.outline_size = 0
	label.rotation_degrees.x = -90.0 # printed on the paper, readable from the player's side
	label.position = pos + Vector3(0, 0.001, 0)
	_iou.add_child(label)
	return label


func _process(delta: float) -> void:
	# the note pops onto the table with a little overshoot
	_iou_scale = minf(_iou_scale + delta * 4.0, 1.0) if _iou.visible else 0.0
	var u := _iou_scale - 1.0
	_iou.scale = Vector3.ONE * maxf(1.0 + 2.7 * u * u * u + 1.7 * u * u, 0.001) # ease-out-back
	_timer -= delta
	var allowed := _target - _held_back # coins still flying in land on the pile only when they arrive
	if _timer <= 0.0 and _coins.size() != allowed:
		_timer = COIN_INTERVAL
		if _coins.size() < allowed:
			_add_coin()
		elif _coins.size() > _target:
			_coins.pop_back().queue_free()
			_drop_time.pop_back()
	_update_flyers(delta)
	for i in _coins.size():
		_drop_time[i] += delta
		var coin := _coins[i]
		var rest := _rest_position(i)
		var t := clampf(_drop_time[i] / 0.22, 0.0, 1.0)
		coin.position = Vector3(rest.x, rest.y + DROP * (1.0 - t * t), rest.z) # falls faster and faster
		if tremble: # The Ox: every coin rattles nervously on the pile
			coin.position += Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)) * 0.0012


## Money earned: `count` coins fly in arcs from `from` (world) onto the pile, one after another.
func fly_in(from: Vector3, count: int) -> void:
	count = mini(count, 15)
	for i in count:
		_held_back += 1
		_spawn_flyer(from, Vector3.ZERO, i * 0.07, true)


## Money spent: `count` coins jump off the pile towards `to` (world) and vanish there.
func fly_out(to: Vector3, count: int) -> void:
	count = mini(count, 10)
	var top := Vector3(0, minf(_coins.size(), PER_STACK) * COIN_THICK + 0.01, 0)
	for i in count:
		_spawn_flyer(to_global(top), to, i * 0.05, false)


func _spawn_flyer(from: Vector3, to: Vector3, delay: float, incoming: bool) -> void:
	var coin := MeshInstance3D.new()
	coin.mesh = _mesh
	coin.material_override = _mat
	coin.top_level = true
	coin.visible = false
	add_child(coin)
	coin.global_position = from
	var jitter := Vector3(_rng.randf_range(-0.03, 0.03), 0, _rng.randf_range(-0.03, 0.03))
	_flyers.append({"node": coin, "from": from + jitter, "to": to, "t": -delay, "incoming": incoming,
			"spin": _rng.randf_range(10.0, 18.0)})


func _update_flyers(delta: float) -> void:
	for f in _flyers.duplicate():
		f["t"] += delta / FLY_TIME
		var t: float = f["t"]
		var coin: MeshInstance3D = f["node"]
		if t < 0.0:
			continue
		coin.visible = true
		var dest: Vector3 = to_global(_rest_position(_coins.size()) + Vector3(0, 0.02, 0)) if f["incoming"] else f["to"]
		var from: Vector3 = f["from"]
		var p := from.lerp(dest, t)
		p.y += sin(t * PI) * (0.12 + from.distance_to(dest) * 0.25) # an arc through the air
		coin.global_position = p
		coin.rotation = Vector3(t * float(f["spin"]), t * 7.0, 0)
		if t >= 1.0:
			coin.queue_free()
			_flyers.erase(f)
			if f["incoming"]:
				_held_back = maxi(_held_back - 1, 0) # lands: the pile grows by this coin
				landed.emit()


func _add_coin() -> void:
	var coin := MeshInstance3D.new()
	coin.mesh = _mesh
	coin.material_override = _mat
	coin.rotation = Vector3(_rng.randf_range(-0.04, 0.04), _rng.randf() * TAU, _rng.randf_range(-0.04, 0.04))
	add_child(coin)
	_coins.append(coin)
	_drop_time.append(0.0)
	coin.position = _rest_position(_coins.size() - 1) + Vector3(0, DROP, 0)


## Where coin `i` lies: stack i / PER_STACK, height i % PER_STACK, a little untidy like real coins.
func _rest_position(i: int) -> Vector3:
	var stack: Vector2 = STACKS[mini(i / PER_STACK, STACKS.size() - 1)] * STEP
	var level := i % PER_STACK
	var jitter := Vector2(sin(i * 12.9898), cos(i * 78.233)) * 0.0015
	return Vector3(stack.x + jitter.x, COIN_THICK * (level + 0.5), stack.y + jitter.y)
