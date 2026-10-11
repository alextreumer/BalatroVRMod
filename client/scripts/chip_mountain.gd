class_name ChipMountain
extends Node3D
## A mountain of poker chips on the casino table: every chip scored in this run, added up.
## It starts as a little stack (a few hundred points) and grows with the run's score – the scale
## is logarithmic, so about 10 million points reach the ceiling. The colour of the chips changes
## with each power of ten (white hundreds, red thousands, blue ten-thousands, green hundred-thousands,
## black millions, purple ten millions, gold beyond). Beyond 10 million a second mountain (log_from / log_to) grows on.
##
## Thousands of chips are drawn with one MultiMesh. Every chip slot is prepared once, sorted by the
## mountain height at which it appears, so growing only means showing more of them.

const CHIP_RADIUS := 0.023
const CHIP_HEIGHT := 0.0075
const SPACING := 0.048          # between neighbouring stacks
const BASE_RADIUS := 0.05       # foot of the mountain when it is tiny ...
const SPREAD := 0.105          # ... and how much wider it gets per metre of height
const MAX_HEIGHT := 2.8
const LOG_FROM := 2.0           # 100 points: the very first chip
const LOG_TO := 7.0             # 10 million points: up to the ceiling
const CURVE := 1.6              # small scores stay small, then it takes off
const BANDS := [Color(0.92, 0.92, 0.9), Color(0.85, 0.12, 0.12), Color(0.15, 0.35, 0.9),
		Color(0.1, 0.6, 0.25), Color(0.08, 0.08, 0.09), Color(0.55, 0.2, 0.75), Color(0.95, 0.75, 0.2),
		# (the second mountain, beyond 10 million: orange, cyan, pink, silver)
		Color(1.0, 0.45, 0.1), Color(0.2, 0.85, 0.9), Color(1.0, 0.4, 0.7), Color(0.85, 0.88, 0.95)]

var ceiling := MAX_HEIGHT       # local height of the room's ceiling (set by the casino)
var log_from := LOG_FROM        # the score range of this mountain (powers of ten); a second mountain
var log_to := LOG_TO            # takes over where the first one reaches the ceiling
var label_until := INF          # from this total on another mountain shows the count
var _mm: MultiMeshInstance3D
var _thresholds := PackedFloat32Array()   # mountain height at which each instance appears (sorted)
var _target := 0.0              # run total from the game
var _shown := 0.0               # the total currently shown (eases towards the target)
var _label: Label3D


func _ready() -> void:
	_build()
	_label = Label3D.new()
	_label.font_size = 32
	_label.pixel_size = 0.0012
	_label.outline_size = 8
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.modulate = Color(1.0, 0.9, 0.6)
	add_child(_label)
	_update_view()


## The run's total score; 0 outside a run (the mountain is cleared away).
func set_total(total: float) -> void:
	_target = maxf(total, 0.0)
	if _target < _shown * 0.5: # a new run: start again from nothing
		_shown = 0.0


func height_for(total: float) -> float:
	if total < pow(10.0, log_from):
		return CHIP_HEIGHT if total > 0.0 and log_from <= LOG_FROM else 0.0 # (a second mountain waits)
	var k := clampf((log(total) / log(10.0) - log_from) / (log_to - log_from), 0.0, 1.0)
	return maxf(minf(ceiling, MAX_HEIGHT) * pow(k, CURVE), CHIP_HEIGHT)


func _process(delta: float) -> void:
	if is_equal_approx(_shown, _target):
		return
	# ease in log space: a big hand makes the mountain grow over a second, chip by chip
	var a := log(maxf(_shown, 1.0))
	var b := log(maxf(_target, 1.0))
	var step := maxf(absf(b - a) * (1.0 - exp(-2.5 * delta)), 0.02 * delta)
	a = move_toward(a, b, step)
	_shown = exp(a) if absf(a - b) > 0.0005 else _target
	if _target <= 0.0:
		_shown = 0.0
	_update_view()


func _update_view() -> void:
	var h := height_for(_shown)
	# binary search: how many chip slots appear at this height
	var lo := 0
	var hi := _thresholds.size()
	while lo < hi:
		var mid := (lo + hi) / 2
		if _thresholds[mid] <= h:
			lo = mid + 1
		else:
			hi = mid
	_mm.multimesh.visible_instance_count = lo
	if _label != null:
		_label.visible = h > 0.0 and _shown < label_until
		_label.text = "%s chips this run" % _big(_shown)
		# at the foot of the mountain, on your side
		_label.position = Vector3(0, 0.05, BASE_RADIUS + SPREAD * h + 0.04)


## Column height when the mountain is `h` high: the middle reaches the top, the slopes fall off
## in a curve (steep peak, wide foot) like a real heap.
static func _column_height(h: float, d: float) -> float:
	var r := BASE_RADIUS + SPREAD * h
	return h * pow(maxf(1.0 - d / r, 0.0), 1.5) if d > 0.001 else h


func _build() -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = CHIP_RADIUS
	mesh.bottom_radius = CHIP_RADIUS
	mesh.height = CHIP_HEIGHT * 0.92
	mesh.radial_segments = 10
	mesh.rings = 1
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.45
	mat.albedo_texture = _edge_texture()
	mesh.material = mat
	# hexagonal grid of stacks out to the foot of the full-grown mountain
	var columns: Array[Vector2] = []
	var r_max := BASE_RADIUS + SPREAD * MAX_HEIGHT
	var rows := int(r_max / (SPACING * 0.866)) + 1
	for row in range(-rows, rows + 1):
		for col in range(-rows - 1, rows + 2):
			var p := Vector2(col * SPACING + (SPACING * 0.5 if row % 2 != 0 else 0.0), row * SPACING * 0.866)
			if p.length() <= r_max:
				columns.append(p)
	# every chip slot with the mountain height at which it appears
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var slots := []
	for c in columns:
		var d := c.length()
		var jitter := rng.randf_range(0.85, 1.0) # stacks aren't all exactly the same height
		var level := 0
		while true:
			var need := (level + 1) * CHIP_HEIGHT / jitter
			var h := _height_for_column(need, d)
			if h < 0.0 or h > MAX_HEIGHT:
				break
			slots.append([h, c, level, rng.randf_range(-0.003, 0.003), rng.randf_range(-0.003, 0.003), rng.randf() * TAU])
			level += 1
	slots.sort_custom(func(x, y): return x[0] < y[0])
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = slots.size()
	_thresholds.resize(slots.size())
	for i in slots.size():
		var s: Array = slots[i]
		var c: Vector2 = s[1]
		var y: float = (int(s[2]) + 0.5) * CHIP_HEIGHT
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, s[5]), Vector3(c.x + s[3], y, c.y + s[4])))
		mm.set_instance_color(i, _band_colour(y))
		_thresholds[i] = s[0]
	mm.visible_instance_count = 0
	_mm = MultiMeshInstance3D.new()
	_mm.multimesh = mm
	_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mm)


## Smallest mountain height at which a column at distance d is at least `need` high (-1: never).
func _height_for_column(need: float, d: float) -> float:
	if _column_height(MAX_HEIGHT, d) < need:
		return -1.0
	if d <= 0.001:
		return need
	var lo := need # a column is never higher than the peak
	var hi := MAX_HEIGHT
	for i in 22:
		var mid := (lo + hi) * 0.5
		if _column_height(mid, d) >= need:
			hi = mid
		else:
			lo = mid
	return hi


## Chips at the height that a given power of ten reaches get that power's colour.
func _band_colour(y: float) -> Color:
	var k := pow(clampf(y / minf(ceiling, MAX_HEIGHT), 0.0, 1.0), 1.0 / CURVE)
	var decade := int(log_from + k * (log_to - log_from)) - 2
	return BANDS[clampi(decade, 0, BANDS.size() - 1)]


## The white stripes on a chip's edge (multiplied with the chip colour).
static func _edge_texture() -> ImageTexture:
	var img := Image.create(64, 8, false, Image.FORMAT_RGB8)
	for x in 64:
		var stripe := (x / 8) % 2 == 0
		for y in 8:
			img.set_pixel(x, y, Color(1, 1, 1) if stripe else Color(0.72, 0.72, 0.72))
	return ImageTexture.create_from_image(img)


static func _big(v: float) -> String:
	var s := str(int(v))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out
