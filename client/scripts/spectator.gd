class_name Spectator
extends Node
## A calm camera for recording and streaming, in its own window on the PC ("Balatro in VR – Spectator",
## e.g. for OBS). The headset view on the monitor shakes with every head movement; this one is
## smoothed and can look from elsewhere:
##   EYES      your view, steadied and a bit wider
##   TRIPOD    like your view, but on a tripod: fixed above and behind your place, looking at the table
##   SHOULDER  from behind and above you: your hands, the table and the board
##   OVERHEAD  straight down onto the table, like a poker broadcast
##   ROOM      a slow, wide shot of the casino table from the corner
## Keys in the window: 1 - 5 choose the view, F11 full screen. In the shoulder, overhead and room
## views the player wears Jimbo's jester hat (only the spectator sees it).

enum Mode { OFF, EYES, TRIPOD, SHOULDER, OVERHEAD, ROOM }
const NAMES := ["Off", "Eyes", "Tripod", "Shoulder", "Overhead", "Room"]
const HAT_LAYER := 1 << 19         # render layer of the player's hat: hidden from the headset
const PLAYER_LAYER := 1 << 18      # the LIVE badge and the camera model: hidden from the spectator window

signal mode_changed(mode: int)

var mode := Mode.OFF
var head: Node3D                   # the XR camera
var focus: Callable                # -> Vector3: what the shoulder / room views look at (the table)
var place: Callable                # -> Transform3D: the player's place (origin) and facing (-Z), fixed in the room
var overview: Callable             # -> Vector3: the middle of everything on the table (overhead view)
var badge_hand: Callable           # -> Node3D: the hand that wears the LIVE badge (the card hand)

var _win: Window
var _cam: Camera3D
var _hat: Node3D
var _pos := Vector3.ZERO
var _look := Vector3.ZERO
var _basis := Basis()
var _time := 0.0
var _snap := true                  # jump to the target the first frame (no swoop from the origin)
var last_view := Mode.EYES        # the view the window opens with
var _badge: Label3D
var _badge_pop := 0.0
var _rig: Node3D                   # the film camera model
var _tally: MeshInstance3D         # its red light


func _ready() -> void:
	_build_hat()
	_build_feedback()


func set_mode(m: int) -> void:
	mode = clampi(m, 0, Mode.ROOM) as Mode
	if mode != Mode.OFF:
		last_view = mode
	if mode == Mode.OFF:
		if _win != null:
			_win.queue_free()
			_win = null
			_cam = null
	elif _win == null:
		_open_window()
	_snap = true
	_hat.visible = mode == Mode.SHOULDER or mode == Mode.OVERHEAD or mode == Mode.ROOM
	_update_feedback()
	mode_changed.emit(mode)


func next_mode() -> void:
	set_mode((mode + 1) % NAMES.size())


## For the VR menu: the window on / off (it comes back with the view it had) ...
func toggle() -> void:
	set_mode(Mode.OFF if mode != Mode.OFF else last_view)


## ... and the next view without closing the window (OBS keeps capturing it).
func next_view() -> void:
	set_mode(Mode.EYES if mode == Mode.OFF or mode == Mode.ROOM else mode + 1)


func _open_window() -> void:
	_win = Window.new()
	_win.visible = false # force_native can only be set while the window is hidden (shown below)
	_win.title = "Balatro in VR – Spectator"
	_win.size = Vector2i(1280, 720)
	_win.min_size = Vector2i(320, 180)
	_win.force_native = true # a real window on the desktop (OBS can capture it), not inside the game view
	_win.transient = false
	_win.unresizable = false
	_win.close_requested.connect(func(): set_mode(Mode.OFF))
	_win.window_input.connect(_on_window_input)
	add_child(_win)
	_win.popup_centered() # now it opens as its own window on the desktop
	_win.world_3d = get_viewport().world_3d # the same world as the headset sees
	_win.msaa_3d = Viewport.MSAA_4X # smooth edges in the recording too
	_cam = Camera3D.new()
	_cam.fov = 70.0
	_cam.near = 0.03
	_cam.cull_mask &= ~PLAYER_LAYER # (the LIVE badge and the camera model are only for the headset)
	_win.add_child(_cam)
	_cam.current = true
	var hint := Label.new()
	hint.text = "1 Eyes · 2 Tripod · 3 Shoulder · 4 Overhead · 5 Room · F11 full screen"
	hint.position = Vector2(12, 8)
	hint.modulate = Color(1, 1, 1, 0.55)
	_win.add_child(hint)
	# the hint fades away after a few seconds
	var tw := create_tween()
	tw.tween_interval(5.0)
	tw.tween_property(hint, "modulate:a", 0.0, 1.0)


func _on_window_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_1: set_mode(Mode.EYES)
		KEY_2: set_mode(Mode.TRIPOD)
		KEY_3: set_mode(Mode.SHOULDER)
		KEY_4: set_mode(Mode.OVERHEAD)
		KEY_5: set_mode(Mode.ROOM)
		KEY_F11:
			_win.mode = Window.MODE_WINDOWED if _win.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN


func _process(delta: float) -> void:
	if head == null:
		return
	_time += delta
	# the hat sits on the player's head (seen only in the spectator window)
	var yaw := _yaw_basis(head.global_basis)
	_hat.global_transform = Transform3D(yaw.scaled(Vector3.ONE * 0.7), head.global_position + Vector3(0, 0.08, 0) + yaw.z * 0.02)
	_process_feedback(delta)
	if _cam == null:
		return
	var eyes := head.global_position
	var table: Vector3 = focus.call() if focus.is_valid() else eyes + yaw * Vector3(0, -0.5, -0.8)
	var want_pos := eyes
	var want_basis := head.global_basis.orthonormalized()
	var k_pos := 1.0 - exp(-6.0 * delta)
	var k_rot := 1.0 - exp(-3.0 * delta)
	match mode:
		Mode.EYES:
			_cam.fov = 80.0
			# keep the horizon level: no rolling with the head
			var f := -want_basis.z
			want_basis = Basis.looking_at(f, Vector3.UP)
		Mode.TRIPOD:
			# fixed, not following the head: a little above and behind your place, looking at the
			# middle of the table; only moves when the layout is re-centred
			_cam.fov = 65.0
			var p: Transform3D = place.call() if place.is_valid() else Transform3D(yaw, eyes)
			want_pos = p.origin + p.basis * Vector3(0.0, 0.08, 0.1) # about where your eyes are
			var target := table.lerp(p.origin, 0.25) + Vector3(0, -0.05, 0)
			want_basis = Basis.looking_at(target - want_pos, Vector3.UP)
			k_pos = 1.0 - exp(-3.0 * delta)
			k_rot = 1.0 - exp(-3.0 * delta)
		Mode.OVERHEAD:
			# straight down onto the table, turned so that "up" in the picture is away from you
			_cam.fov = 60.0
			var p: Transform3D = place.call() if place.is_valid() else Transform3D(yaw, eyes)
			var middle: Vector3 = overview.call() if overview.is_valid() else table
			want_pos = middle + Vector3(0, 0.9, 0)
			want_basis = Basis.looking_at(Vector3.DOWN, -p.basis.z)
			k_pos = 1.0 - exp(-3.0 * delta)
			k_rot = 1.0 - exp(-3.0 * delta)
		Mode.SHOULDER:
			_cam.fov = 70.0
			want_pos = eyes + yaw * Vector3(0.4, 0.3, 0.75) # behind, above, to the right: past your head
			var target := eyes.lerp(table, 0.6) + Vector3(0, -0.15, 0)
			want_basis = Basis.looking_at(target - want_pos, Vector3.UP)
			k_pos = 1.0 - exp(-2.5 * delta)
			k_rot = 1.0 - exp(-2.0 * delta)
		Mode.ROOM:
			_cam.fov = 55.0
			var a := 0.6 + 0.25 * sin(_time * 0.05) # drifts slowly to and fro around the table
			want_pos = table + Vector3(sin(a) * 2.6, 1.15, cos(a) * 2.6)
			want_basis = Basis.looking_at(table + Vector3(0, 0.25, 0) - want_pos, Vector3.UP)
			k_pos = 1.0 - exp(-1.0 * delta)
			k_rot = 1.0 - exp(-1.0 * delta)
	if _snap:
		_snap = false
		k_pos = 1.0
		k_rot = 1.0
	_pos = _pos.lerp(want_pos, k_pos)
	_basis = _basis.orthonormalized().slerp(want_basis.orthonormalized(), k_rot)
	_cam.global_transform = Transform3D(_basis, _pos)


static func _yaw_basis(b: Basis) -> Basis:
	var f := -b.z
	f.y = 0.0
	if f.length() < 0.01:
		return Basis()
	f = f.normalized()
	return Basis(Vector3.UP, atan2(-f.x, -f.z))


## Jimbo's jester hat: a red and a blue horn with golden bells (render layer 20: the headset never
## sees it, so it can't get in your own way).
func _build_hat() -> void:
	_hat = Node3D.new()
	_hat.visible = false
	add_child(_hat)
	var band := _part(CylinderMesh.new(), Color(0.95, 0.85, 0.3))
	(band.mesh as CylinderMesh).top_radius = 0.1
	(band.mesh as CylinderMesh).bottom_radius = 0.105
	(band.mesh as CylinderMesh).height = 0.04
	band.position.y = -0.02
	for side in [-1.0, 1.0]:
		var horn := _part(CylinderMesh.new(), Color(0.85, 0.12, 0.15) if side < 0 else Color(0.15, 0.3, 0.85))
		var c := horn.mesh as CylinderMesh
		c.top_radius = 0.0
		c.bottom_radius = 0.075
		c.height = 0.24
		horn.position = Vector3(side * 0.085, 0.09, 0.0)
		horn.rotation.z = -side * 0.75
		var bell := _part(SphereMesh.new(), Color(0.95, 0.75, 0.25))
		(bell.mesh as SphereMesh).radius = 0.025
		(bell.mesh as SphereMesh).height = 0.05
		bell.position = Vector3(side * 0.18, 0.15, 0.0)


func _part(mesh: Mesh, colour: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = 0.5
	mi.material_override = m
	mi.layers = HAT_LAYER
	_hat.add_child(mi)
	return mi


# ---------------------------------------------------------------- feedback in the headset

## What only the player sees (render layer 19, hidden from the spectator window): a "● LIVE · Tripod"
## badge on the wrist while the window runs, and a little film camera with a red light where the
## spectator camera is (not in the Eyes view: that one is your own head).
func _build_feedback() -> void:
	_badge = Label3D.new()
	_badge.font_size = 32
	_badge.pixel_size = 0.0006
	_badge.outline_size = 8
	_badge.outline_modulate = Color(0.1, 0.0, 0.0)
	_badge.modulate = Color(1.0, 0.3, 0.25)
	_badge.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_badge.layers = PLAYER_LAYER
	_badge.visible = false
	add_child(_badge)
	_rig = Node3D.new()
	_rig.visible = false
	add_child(_rig)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.08, 0.08, 0.09)
	dark.roughness = 0.4
	dark.metallic = 0.5
	_rig_part(BoxMesh.new(), Vector3(0.09, 0.07, 0.13), Vector3(0, 0, 0.02), dark)                  # body
	var lens := _rig_part(CylinderMesh.new(), Vector3(0.05, 0.05, 0.05), Vector3(0, 0, -0.07), dark) # lens
	lens.rotation_degrees.x = 90.0
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.2, 0.35, 0.6)
	glass.metallic = 1.0
	glass.roughness = 0.05
	var front := _rig_part(CylinderMesh.new(), Vector3(0.04, 0.004, 0.04), Vector3(0, 0, -0.096), glass)
	front.rotation_degrees.x = 90.0
	var red := StandardMaterial3D.new()
	red.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	red.albedo_color = Color(2.5, 0.15, 0.1)
	_tally = _rig_part(SphereMesh.new(), Vector3(0.016, 0.016, 0.016), Vector3(0.028, 0.045, -0.02), red)


func _rig_part(mesh: PrimitiveMesh, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	if mesh is BoxMesh:
		(mesh as BoxMesh).size = size
	elif mesh is CylinderMesh:
		(mesh as CylinderMesh).top_radius = size.x * 0.5
		(mesh as CylinderMesh).bottom_radius = size.x * 0.5
		(mesh as CylinderMesh).height = size.y
	elif mesh is SphereMesh:
		(mesh as SphereMesh).radius = size.x * 0.5
		(mesh as SphereMesh).height = size.x
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = mat
	mi.layers = PLAYER_LAYER
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rig.add_child(mi)
	return mi


func _update_feedback() -> void:
	var on := mode != Mode.OFF
	_badge.text = "● LIVE · " + NAMES[mode]
	_badge_pop = 1.0 # a little bigger for a moment: you just switched
	_rig.visible = on and mode != Mode.EYES


func _process_feedback(delta: float) -> void:
	var hand: Node3D = badge_hand.call() if badge_hand.is_valid() else null
	_badge.visible = mode != Mode.OFF and hand != null and hand.is_visible_in_tree()
	_badge_pop = maxf(_badge_pop - delta * 0.7, 0.0)
	if _badge.visible:
		# above the wrist of the card hand, where a watch would be
		_badge.global_position = hand.global_position + hand.global_basis * Vector3(0, 0.05, 0.07)
		_badge.scale = Vector3.ONE * (1.0 + 1.2 * _badge_pop)
		_badge.modulate.a = 0.75 + 0.25 * sin(_time * 4.0) # the red light blinks
	if _rig.visible and _cam != null:
		_rig.global_transform = _cam.global_transform
		_tally.visible = fmod(_time, 1.0) < 0.6
