class_name ScoreTower
extends Node3D
## The score of the blind being played, next to the blind chip: a glass tube that fills with a
## stack of chips as the score grows, with a gold ring at the top for the score the blind needs.
## The current score rides along beside the top of the stack, the target beside the ring. Once the
## blind is beaten the chips turn gold and glow. Origin = the foot of the tube on the table.

const H := 0.22                     # height of the tube = the blind's target
const R := 0.03                     # radius of the chips
const DISC_H := 0.0075
const N := int(H / DISC_H)          # chips in a full tube

var _mm: MultiMeshInstance3D
var _fill := 0.0                    # shown (eases towards _want)
var _want := 0.0
var _beaten := false
var _score_label: Label3D
var _goal_label: Label3D
var _ring_mat: StandardMaterial3D
var _royal := false                 # achievement reward "Sky High": purple and gold chips
var _green_ring := false            # achievement reward "Close Call": the ring glows green


func _ready() -> void:
	# foot and glass
	var foot := _cyl(R + 0.014, R + 0.018, 0.012, Vector3(0, 0.006, 0), _mat(Color(0.25, 0.11, 0.05), 0.4, 0.0))
	foot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.8, 0.9, 1.0, 0.12)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.05
	glass.metallic_specular = 1.0
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var tube := _cyl(R + 0.006, R + 0.006, H + 0.01, Vector3(0, 0.012 + (H + 0.01) * 0.5, 0), glass)
	tube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(tube.mesh as CylinderMesh).cap_bottom = false # (a glass floor on the foot's top flickered)
	(tube.mesh as CylinderMesh).cap_top = false
	# the goal: a gold ring at the top of the tube
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = R + 0.005
	torus.outer_radius = R + 0.012
	ring.mesh = torus
	_ring_mat = _mat(Color(1.0, 0.78, 0.25), 0.25, 0.9)
	_ring_mat.emission_enabled = true
	_ring_mat.emission = Color(1.0, 0.7, 0.2)
	_ring_mat.emission_energy_multiplier = 0.4
	ring.material_override = _ring_mat
	ring.position.y = 0.012 + H
	add_child(ring)
	# the chips: one MultiMesh, shown up to the score
	var disc := CylinderMesh.new()
	disc.top_radius = R
	disc.bottom_radius = R
	disc.height = DISC_H * 0.92
	disc.radial_segments = 16
	disc.rings = 1
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.45
	m.albedo_texture = ChipMountain._edge_texture()
	disc.material = m
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = disc
	mm.instance_count = N
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in N:
		var jitter := Vector3(rng.randf_range(-0.002, 0.002), 0, rng.randf_range(-0.002, 0.002))
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(0, 0.012 + (i + 0.5) * DISC_H, 0) + jitter))
	mm.visible_instance_count = 0
	_mm = MultiMeshInstance3D.new()
	_mm.multimesh = mm
	_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mm)
	_colour_chips(false)
	# the numbers beside the tube
	_goal_label = _label(Color(1.0, 0.8, 0.35), 34)
	_goal_label.position = Vector3(R + 0.02, 0.012 + H, 0)
	_score_label = _label(Color(0.5, 0.75, 1.0), 40)
	GameFont.apply_to(self)


## The score so far in this blind and the score the blind needs.
func set_score(score: float, target: float) -> void:
	_want = clampf(score / target, 0.0, 1.0) if target > 0.0 else 0.0
	_goal_label.text = "TARGET  " + _big(target)
	_score_label.text = "SCORE  " + _big(score)
	var beaten := target > 0.0 and score >= target
	if beaten != _beaten:
		_beaten = beaten
		_colour_chips(beaten)
	GameFont.apply_to(self)


func _process(delta: float) -> void:
	if not visible:
		return
	# the stack grows chip by chip over a moment (and is emptied at once for a new blind)
	_fill = _want if _want < _fill else move_toward(_fill, _want, maxf(_want - _fill, 0.05) * delta * 3.0)
	_mm.multimesh.visible_instance_count = int(round(_fill * N))
	# beside the top of the stack; near the ring it stays just under the target, so both can be read
	_score_label.position = Vector3(R + 0.02, minf(0.012 + _fill * H + 0.012, 0.012 + H - 0.03), 0)
	if _beaten:
		var t := Time.get_ticks_msec() / 1000.0
		_ring_mat.emission_energy_multiplier = 1.5 + 0.8 * sin(t * 6.0)
	else:
		_ring_mat.emission_energy_multiplier = 0.4


## Achievement rewards: purple and gold chips, a green ring.
func set_style(royal: bool, green_ring: bool) -> void:
	_royal = royal
	_green_ring = green_ring
	var ring := Color(0.3, 1.0, 0.45) if green_ring else Color(1.0, 0.78, 0.25)
	_ring_mat.albedo_color = ring
	_ring_mat.emission = ring * 0.9
	_colour_chips(_beaten)


func _colour_chips(gold: bool) -> void:
	for i in N:
		var a := Color(0.5, 0.15, 0.8) if _royal else Color(0.15, 0.4, 0.95)
		var b := Color(1.0, 0.78, 0.25) if _royal else Color(0.92, 0.92, 0.9)
		var c := Color(1.0, 0.78, 0.2) if gold else (a if i % 2 == 0 else b)
		_mm.multimesh.set_instance_color(i, c)


## 1,234,567 - and from 100 billion on like the game: 2.90e13
static func _big(v: float) -> String:
	if v >= 1e11:
		var e := int(floor(log(v) / log(10.0)))
		return "%.2fe%d" % [v / pow(10.0, e), e]
	var s := str(int(v))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out


func _label(colour: Color, size: int) -> Label3D:
	var l := Label3D.new()
	l.font_size = size
	l.pixel_size = 0.0006
	l.modulate = colour
	l.outline_size = 8
	l.outline_modulate = Color(0.05, 0.03, 0.06)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_child(l)
	return l


func _cyl(top: float, bottom: float, height: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = height
	mi.mesh = c
	mi.position = pos
	mi.material_override = mat
	add_child(mi)
	return mi


func _mat(colour: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = rough
	m.metallic = metal
	return m
