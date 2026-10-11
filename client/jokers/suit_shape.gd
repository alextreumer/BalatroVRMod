@tool
class_name SuitShape
extends CSGCombiner3D
## A playing-card suit symbol (heart, diamond, club, spade) as a thick 3D shape, built from code.
## Used by augmented jokers that show a suit (Ancient Joker). Visible in the editor too.
## Colour it with material_override on this node.

@export_enum("Hearts", "Diamonds", "Clubs", "Spades") var suit := "Hearts":
	set(value):
		suit = value
		_build()
@export var size := 0.03:              ## height of the symbol in meters
	set(value):
		size = value
		_build()
@export var depth := 0.008:            ## thickness
	set(value):
		depth = value
		_build()


func _ready() -> void:
	_build()


func _build() -> void:
	if not is_inside_tree():
		return
	for child in get_children():
		if child.has_meta("suit_part"):
			remove_child(child)
			child.free()
	match suit:
		"Hearts":
			_part(_heart(false))
		"Diamonds":
			_part(PackedVector2Array([Vector2(0, 0.56), Vector2(0.42, 0), Vector2(0, -0.56), Vector2(-0.42, 0)]))
		"Spades":
			_part(_spade())
		"Clubs":
			for c in [Vector2(0, 0.24), Vector2(-0.23, -0.08), Vector2(0.23, -0.08)]:
				_part(_circle(c, 0.21))
			_part(_stem(-0.04))


func _part(points: PackedVector2Array) -> void:
	var poly := CSGPolygon3D.new()
	var scaled := PackedVector2Array()
	for p in points:
		scaled.append(p * size)
	poly.polygon = scaled
	poly.depth = depth
	poly.position.z = depth * 0.5 # centred on this node
	poly.set_meta("suit_part", true)
	add_child(poly) # not saved into the scene: no owner


## Classic heart curve, about 1 unit tall, centred. Flipped = upside down (for the spade).
func _heart(flipped: bool) -> PackedVector2Array:
	var points := PackedVector2Array()
	var n := 40
	for i in n:
		var t := TAU * i / n
		var x := 16.0 * pow(sin(t), 3)
		var y := 13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)
		var p := Vector2(x, y + 2.5) / 30.0 # height ~29 units -> ~1, centred
		if flipped:
			p.y = -p.y
		points.append(p)
	if flipped: # keep the outline counter-clockwise
		points.reverse()
	return points


## An upside-down heart with a flared stem below.
func _spade() -> PackedVector2Array:
	var points := PackedVector2Array()
	for p in _heart(true):
		points.append(p * 0.85 + Vector2(0, 0.08))
	return _merge_stem(points)


func _merge_stem(points: PackedVector2Array) -> PackedVector2Array:
	var stem := _stem(0.0) # reaches up into the notch, so both melt into one outline
	var merged := Geometry2D.merge_polygons(points, stem)
	return merged[0] if merged.size() > 0 else points


## A little flared foot under club and spade, top at `top_y`.
func _stem(top_y: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(-0.05, top_y), Vector2(0.05, top_y), Vector2(0.17, -0.5), Vector2(-0.17, -0.5)])


func _circle(centre: Vector2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 24:
		var a := TAU * i / 24.0
		points.append(centre + Vector2(cos(a), sin(a)) * radius)
	return points
