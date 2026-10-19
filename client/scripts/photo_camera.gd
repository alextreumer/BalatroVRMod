class_name PhotoCamera
extends Node3D
## Photo mode: a little instant camera (VR menu ≡ -> Photo Camera). Grab it with the grip; the
## trigger of the hand holding it takes a photo. Let go and it stays floating where it is - point
## at it with the beam and pull the trigger: a 3 second self-timer, time to strike a pose.
## A live view on its back shows what it sees; every photo is saved as a PNG in
## a Photos folder next to the program, and a little print slides out of the camera.
## Its lens looks along -z (like a Godot camera).

signal shot(path: String)

const SIZE := Vector2i(1920, 1080)
const GRAB_RADIUS := 0.12

var _view: SubViewport
var _cam: Camera3D
var _screen_mat: StandardMaterial3D
var _hand: Node3D = null
var _hand_offset := Transform3D()
var _timer := -1.0                 # self-timer running: seconds left
var _count: Label3D
var _flash: OmniLight3D
var _click: AudioStreamPlayer3D


var polaroid := false              # "Say Cheese!" reward: photos get a white instant-photo frame

func _ready() -> void:
	var body := _mat(Color(0.12, 0.12, 0.14), 0.4, 0.2)
	var red := _mat(Color(0.85, 0.15, 0.15), 0.4, 0.1)
	_box(Vector3(0.11, 0.07, 0.045), Vector3.ZERO, body)                             # body
	_box(Vector3(0.112, 0.012, 0.046), Vector3(0, 0.0302, 0), red)                   # a red stripe on top (a little above the body's top: no flicker)
	var lens := MeshInstance3D.new()
	var lm := CylinderMesh.new()
	lm.top_radius = 0.02
	lm.bottom_radius = 0.022
	lm.height = 0.02
	lens.mesh = lm
	lens.rotation_degrees.x = 90.0
	lens.position = Vector3(0, -0.004, -0.03)
	lens.material_override = _mat(Color(0.05, 0.05, 0.06), 0.2, 0.6)
	add_child(lens)
	var glass := MeshInstance3D.new()
	var gm := CylinderMesh.new()
	gm.top_radius = 0.014
	gm.bottom_radius = 0.014
	gm.height = 0.002
	glass.mesh = gm
	glass.rotation_degrees.x = 90.0
	glass.position = Vector3(0, -0.004, -0.0405)
	glass.material_override = _mat(Color(0.2, 0.35, 0.6), 0.05, 0.9)
	add_child(glass)
	_box(Vector3(0.018, 0.012, 0.004), Vector3(0.035, 0.018, -0.024), _mat(Color(0.9, 0.9, 0.95), 0.3, 0.0)) # flash window
	_box(Vector3(0.012, 0.006, 0.012), Vector3(-0.036, 0.038, 0), red)              # shutter button
	# what the camera sees: its own viewport, shown live on the back
	_view = SubViewport.new()
	_view.size = SIZE
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_view.msaa_3d = Viewport.MSAA_4X
	add_child(_view)
	_cam = Camera3D.new()
	_cam.fov = 60.0
	_cam.near = 0.03
	_view.add_child(_cam)
	var screen := MeshInstance3D.new()
	var sq := QuadMesh.new()
	sq.size = Vector2(0.09, 0.0506)
	screen.mesh = sq
	_screen_mat = StandardMaterial3D.new()
	_screen_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_screen_mat.albedo_texture = _view.get_texture()
	screen.material_override = _screen_mat
	screen.position = Vector3(0, -0.002, 0.0231) # (on the back, facing you when you aim)
	add_child(screen)
	_count = Label3D.new()
	_count.font_size = 120
	_count.pixel_size = 0.0006
	_count.modulate = Color(1.0, 0.85, 0.3)
	_count.outline_size = 16
	_count.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_count.no_depth_test = true
	_count.position = Vector3(0, 0.08, 0)
	_count.visible = false
	add_child(_count)
	_flash = OmniLight3D.new()
	_flash.light_energy = 0.0
	_flash.omni_range = 3.0
	_flash.position = Vector3(0.035, 0.018, -0.06)
	add_child(_flash)
	_click = AudioStreamPlayer3D.new()
	_click.stream = _shutter_sound()
	add_child(_click)
	var hit := StaticBody3D.new() # for the beam: the self-timer
	hit.set_meta("target_id", 0)
	hit.set_meta("kind", "photocam")
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.12, 0.08, 0.06)
	shape.shape = bs
	hit.add_child(shape)
	add_child(hit)
	GameFont.apply_to(self)


func _process(delta: float) -> void:
	if _hand != null and is_instance_valid(_hand):
		global_transform = _hand.global_transform * _hand_offset
	_cam.global_transform = global_transform.orthonormalized() * Transform3D(Basis(), Vector3(0, -0.004, -0.045)) # (in front of its own lens)
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS if visible else SubViewport.UPDATE_DISABLED
	if _timer >= 0.0:
		var before := ceili(_timer)
		_timer -= delta
		_count.text = str(maxi(ceili(_timer), 1))
		if ceili(_timer) != before and _timer > 0.0:
			_beep()
		if _timer <= 0.0:
			_timer = -1.0
			_count.visible = false
			take_photo()
	_flash.light_energy = maxf(_flash.light_energy - delta * 60.0, 0.0)


func try_grab(hand: Node3D) -> bool:
	if not visible or _hand != null or hand.global_position.distance_to(global_position) > GRAB_RADIUS:
		return false
	_hand = hand
	_hand_offset = hand.global_transform.affine_inverse() * global_transform
	return true


func holds(hand: Node3D) -> bool:
	return _hand != null and _hand == hand


func release(hand: Node3D) -> void:
	if holds(hand):
		_hand = null # it stays floating where it was let go


## Trigger on the floating camera: 3 ... 2 ... 1 ... click.
func self_timer() -> void:
	if _timer >= 0.0:
		return
	_timer = 3.0
	_count.visible = true
	_beep()


## The photo: what the camera sees, saved as PNG. A print slides out of the camera.
func take_photo() -> String:
	var img := _view.get_texture().get_image()
	if polaroid: # "Say Cheese!" reward: a white instant-photo frame, wider at the bottom
		var w := img.get_width()
		var h := img.get_height()
		var side := int(w * 0.05)
		var framed := Image.create(w + side * 2, h + side + int(h * 0.2), false, img.get_format())
		framed.fill(Color(0.97, 0.96, 0.92))
		framed.blit_rect(img, Rect2i(0, 0, w, h), Vector2i(side, side))
		img = framed
	var t := Time.get_datetime_dict_from_system()
	var file := "BalatroVR_%04d-%02d-%02d_%02d-%02d-%02d.png" % [t.year, t.month, t.day, t.hour, t.minute, t.second]
	# a "Photos" folder next to Balatro in VR.exe (when run from the project: next to it); if that
	# can't be written (e.g. under Program Files), the Pictures folder instead
	var base := OS.get_executable_path().get_base_dir() if OS.has_feature("template") else ProjectSettings.globalize_path("res://").path_join("..")
	var path := ""
	for dir in [base.path_join("Photos"), OS.get_system_dir(OS.SYSTEM_DIR_PICTURES).path_join("Balatro in VR")]:
		DirAccess.make_dir_recursive_absolute(dir)
		path = dir.simplify_path().path_join(file)
		if img.save_png(path) == OK:
			break
	_flash.light_energy = 12.0
	_click.play()
	_print_out(ImageTexture.create_from_image(img))
	shot.emit(path)
	return path


## A little instant print slides out of the camera's top and fades after a while.
func _print_out(tex: Texture2D) -> void:
	var print_node := Node3D.new()
	add_child(print_node)
	var paper := MeshInstance3D.new()
	var pq := QuadMesh.new()
	pq.size = Vector2(0.07, 0.05)
	paper.mesh = pq
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.97, 0.96, 0.92)
	pm.cull_mode = BaseMaterial3D.CULL_DISABLED
	paper.material_override = pm
	print_node.add_child(paper)
	var photo := MeshInstance3D.new()
	var phq := QuadMesh.new()
	phq.size = Vector2(0.062, 0.035)
	photo.mesh = phq
	var phm := StandardMaterial3D.new()
	phm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	phm.albedo_texture = tex
	photo.material_override = phm
	photo.position = Vector3(0, 0.004, 0.0005)
	print_node.add_child(photo)
	print_node.position = Vector3(0, 0.02, 0.0)
	print_node.rotation_degrees.x = -90.0 + 75.0 # (standing up out of the top, towards you)
	var tw := create_tween()
	tw.tween_property(print_node, "position", Vector3(0, 0.07, 0.01), 0.6).set_ease(Tween.EASE_OUT)
	tw.tween_interval(3.0)
	tw.tween_property(print_node, "scale", Vector3.ONE * 0.01, 0.4)
	tw.tween_callback(print_node.queue_free)


func _beep() -> void:
	var p := AudioStreamPlayer3D.new()
	p.stream = _tone(1320.0, 0.08)
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


static func _tone(freq: float, seconds: float) -> AudioStreamWAV:
	const RATE := 22050
	var n := int(RATE * seconds)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		var v := sin(TAU * freq * i / RATE) * (1.0 - float(i) / n) * 0.4
		bytes.encode_s16(i * 2, int(v * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = bytes
	return w


## The shutter: two short clicks of noise.
static func _shutter_sound() -> AudioStreamWAV:
	const RATE := 22050
	var n := int(RATE * 0.18)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	for i in n:
		var t := float(i) / RATE
		var env := exp(-t * 90.0) + 0.7 * exp(-maxf(t - 0.08, 0.0) * 90.0) * float(t > 0.08)
		bytes.encode_s16(i * 2, int(clampf(rng.randf_range(-1, 1) * env * 0.6, -1, 1) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = bytes
	return w


func _box(size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.position = pos
	mi.material_override = mat
	add_child(mi)


func _mat(c: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m
