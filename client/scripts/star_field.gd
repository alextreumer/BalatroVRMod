class_name StarField
extends Node3D
## Little twinkling stars all over the room around the player:
##  - ambient: a gentle, constant sparkle (while Supernova sits in a joker slot)
##  - burst:   a few seconds of many stars (buying / taking a Planet card)
## Stars stay where they appear in the room (world space) while the field follows the player.

const NEAR := 0.8                       # no stars closer than this to the face (meters)
const FAR := 3.0                        # ... nor farther away than this
const HEIGHT := Vector2(-1.3, 1.4)      # below / above eye level
const AMBIENT_AMOUNT := 60
const BURST_AMOUNT := 200

var _ambient: CPUParticles3D
var _burst: CPUParticles3D
var _burst_left := 0.0
var _material: StandardMaterial3D
var _soft_texture: ImageTexture
var _hard_texture: ImageTexture


func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.vertex_color_use_as_albedo = true
	_soft_texture = _star_texture()
	_material.albedo_texture = _soft_texture
	var points := _shell_points(900)
	_ambient = _make_emitter(AMBIENT_AMOUNT, 2.2, Vector2(0.015, 0.035), points)
	_burst = _make_emitter(BURST_AMOUNT, 1.4, Vector2(0.02, 0.045), points)


## Constant sparkle on/off.
func set_ambient(on: bool) -> void:
	_ambient.emitting = on


## Many stars for `seconds`.
func burst(seconds := 3.5) -> void:
	_burst_left = maxf(_burst_left, seconds)
	_burst.emitting = true


## Chroma-key mode: no soft glow may mix with the green, so a small crisp sparkle with hard edges
## replaces the soft star (cutting the soft star at some alpha would leave its whole halo as a
## big flat blob).
func set_hard_edges(on: bool) -> void:
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR if on else BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.alpha_scissor_threshold = 0.5
	if on and _hard_texture == null:
		_hard_texture = _sparkle_texture()
	_material.albedo_texture = _hard_texture if on else _soft_texture


func _process(delta: float) -> void:
	if _burst_left > 0.0:
		_burst_left -= delta
		if _burst_left <= 0.0:
			_burst.emitting = false # stars already out keep twinkling until they fade


## Random spots in a ring-shaped shell around the player: all over the room, never in the face.
func _shell_points(count: int) -> PackedVector3Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var points := PackedVector3Array()
	for i in count:
		var angle := rng.randf() * TAU
		var dist := sqrt(rng.randf_range(NEAR * NEAR, FAR * FAR)) # even spread over the area
		points.append(Vector3(cos(angle) * dist, rng.randf_range(HEIGHT.x, HEIGHT.y), sin(angle) * dist))
	return points


func _make_emitter(amount: int, lifetime: float, size: Vector2, points: PackedVector3Array) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.randomness = 0.6
	p.local_coords = false # a star stays at its spot in the room
	p.emitting = false
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = _material
	p.mesh = quad
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINTS
	p.emission_points = points
	p.direction = Vector3.UP
	p.spread = 180.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = 0.0
	p.initial_velocity_max = 0.03 # barely drifting
	p.scale_amount_min = size.x
	p.scale_amount_max = size.y
	# twinkle: pop up quickly, fade out slowly
	var twinkle := Curve.new()
	twinkle.add_point(Vector2(0.0, 0.0))
	twinkle.add_point(Vector2(0.15, 1.0))
	twinkle.add_point(Vector2(0.35, 0.55))
	twinkle.add_point(Vector2(0.5, 0.9))
	twinkle.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = twinkle
	# white, gold and pale blue stars
	var colours := Gradient.new()
	colours.set_color(0, Color(1.0, 0.95, 0.7))
	colours.set_color(1, Color(0.75, 0.88, 1.0))
	colours.add_point(0.5, Color(1, 1, 1))
	p.color_initial_ramp = colours
	add_child(p)
	return p


## A crisp pixel sparkle for the chroma-key mode: a slim four-pointed star in the middle third of
## the texture, fully opaque or fully clear (no soft rim).
func _sparkle_texture() -> ImageTexture:
	var size := 128
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for py in size:
		for px in size:
			var x := absf((px + 0.5) / size * 2.0 - 1.0)
			var y := absf((py + 0.5) / size * 2.0 - 1.0)
			var d := pow(x, 0.5) + pow(y, 0.5) # concave diamond: slim pointed rays
			# a soft ramp only inside the texture, the alpha scissor cuts it into a clean edge;
			# the sparkle only fills the middle of the quad (the soft star's faint halo does the rest)
			img.set_pixel(px, py, Color(1, 1, 1, clampf((0.52 - d) * 16.0 + 0.5, 0.0, 1.0)))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## A soft four-pointed star (core glow + horizontal and vertical rays).
func _star_texture() -> ImageTexture:
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for py in size:
		for px in size:
			var x := (px + 0.5) / size * 2.0 - 1.0
			var y := (py + 0.5) / size * 2.0 - 1.0
			var core := exp(-(x * x + y * y) * 28.0)
			var rays := exp(-x * x * 900.0) * exp(-y * y * 5.0) + exp(-y * y * 900.0) * exp(-x * x * 5.0)
			var a := clampf(core + rays * 0.85, 0.0, 1.0)
			img.set_pixel(px, py, Color(1, 1, 1, a))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
