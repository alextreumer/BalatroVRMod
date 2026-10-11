class_name Confetti
extends Node3D
## Confetti raining down from above the player (run won / game over).
## Each scrap spins and flips (its width oscillates) while drifting down, then fades out at the floor.

const ABOVE_HEAD := 1.3                 # confetti starts this far above the eyes (meters)
const AREA := Vector3(1.6, 0.15, 1.6)   # half size of the spawn box around the player
const LIFETIME := 5.0
const AMOUNT := 600

## Balatro-ish palettes
const WIN_COLORS := [Color(0.99, 0.64, 0.0), Color(0.0, 0.58, 1.0), Color(0.99, 0.37, 0.33),
		Color(0.29, 0.75, 0.55), Color(0.53, 0.44, 0.91), Color(1, 1, 1)]
const LOSE_COLORS := [Color(0.06, 0.06, 0.07), Color(0.4, 0.4, 0.42), Color(0.45, 0.04, 0.06)] # black, grey, dark red

var _particles: CPUParticles3D
var _material: StandardMaterial3D
var _left := 0.0


func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.vertex_color_use_as_albedo = true
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	var p := CPUParticles3D.new()
	p.amount = AMOUNT
	p.lifetime = LIFETIME
	p.randomness = 0.3
	p.local_coords = false # once falling, a scrap stays in the room even when the player moves
	p.emitting = false
	var quad := QuadMesh.new()
	quad.size = Vector2(0.018, 0.03)
	quad.material = _material
	p.mesh = quad
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = AREA
	p.direction = Vector3.DOWN
	p.spread = 30.0
	p.initial_velocity_min = 0.1
	p.initial_velocity_max = 0.4
	p.gravity = Vector3(0, -0.5, 0)
	p.damping_min = 0.25 # air drag: they flutter instead of dropping like stones
	p.damping_max = 0.45
	# spin in the view plane ...
	p.angle_min = -180.0
	p.angle_max = 180.0
	p.angular_velocity_min = -220.0
	p.angular_velocity_max = 220.0
	# ... and flip over: the width swings between full and edge-on several times per life
	p.split_scale = true
	var flip := Curve.new()
	for i in 25:
		var t := i / 24.0
		flip.add_point(Vector2(t, 0.15 + 0.85 * absf(cos(t * TAU * 4.0))))
	p.scale_curve_x = flip
	var flat := Curve.new()
	flat.add_point(Vector2(0, 1))
	flat.add_point(Vector2(1, 1))
	p.scale_curve_y = flat
	p.scale_curve_z = flat
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.3
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	fade.add_point(0.8, Color(1, 1, 1, 1))
	p.color_ramp = fade
	add_child(p)
	_particles = p


## Let it rain confetti for `seconds`. `won` = colourful party, otherwise gloomy black/grey/dark red.
func burst(won: bool, seconds := 4.0) -> void:
	var colours := Gradient.new()
	var palette: Array = WIN_COLORS if won else LOSE_COLORS
	colours.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT # pure colours, no blends
	var offsets := PackedFloat32Array()
	var cols := PackedColorArray()
	for i in palette.size():
		offsets.append(float(i) / palette.size())
		cols.append(palette[i])
	colours.offsets = offsets
	colours.colors = cols
	_particles.color_initial_ramp = colours
	_particles.amount = AMOUNT if won else AMOUNT / 2
	_left = maxf(_left, seconds)
	_particles.emitting = true


## Follow the player: the spawn box hangs above `eyes` (already fallen scraps stay put).
func follow(eyes: Vector3) -> void:
	global_position = eyes + Vector3(0, ABOVE_HEAD, 0)


## Chroma-key mode: hard edges so no soft rim mixes with the green.
func set_hard_edges(on: bool) -> void:
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR if on else BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.alpha_scissor_threshold = 0.5


func _process(delta: float) -> void:
	if _left > 0.0:
		_left -= delta
		if _left <= 0.0:
			_particles.emitting = false # the last scraps keep falling until they fade
