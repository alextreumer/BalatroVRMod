class_name Board
extends Node3D
## Draws Balatro's mirrored scene (panels, texts, cards, sprites) as flat 3D objects.
## Positions arrive in Balatro room units (origin top-left, y pointing down) and are mapped to meters.
## Every top-level UI box / card area is a "group" with its own container node: by default it sits on
## this board at its in-game position, but a group can be hung onto an anchor elsewhere in the room
## (run panel at the side, shop on the table, tooltip above a hand card) without touching its layout.

const SCALE := 0.06         # meters per room unit (20 units = 1.2 m wide)
const Z_STEP := 0.00006     # depth per item: enough against z-fighting, small enough to look flat
const FONT_SIZE := 48

var room_size := Vector2(20, 11.5)
var keep_hand_separate := true      # in VR the hand is drawn in the left hand, played cards, jokers and consumables on the table, not on the board
## For chroma-key passthrough: nothing may be see-through, or the green behind it turns into a
## darker green the key no longer removes. Translucent panels become solid, faint ones disappear.
var opaque_mode := false
## Passthrough modes: drop the game's full-screen dimmers (overlay menus darken the screen with a
## grey rect 5x the room size) so the real room stays visible behind menus like "View Deck".
var hide_dimmers := false
## Outside of a round (shop, blind select, cash out, packs) the run panel only shows what matters
## there: money, ante, round and the Run Info / Options buttons.
var compact_hud := false
const COMPACT_KEEP := "/row_round/"                      # lower block of the run panel
const COMPACT_DROP := ["/hud_hands/", "/hud_discards/"]  # ... minus hands and discards
## Game boxes the VR client replaces with its own 3D version (SHOP sign + "Improve your run!")
const REPLACED_ROLES := ["SHOP_SIGN"]

## role -> {"node": Node3D, "ref": role whose rect is centered on the anchor (default: the role itself)}
var anchors := {}
## Callable(owner_card_id: int) -> Node3D or null: where to show the tooltip of that card
var popup_anchor_for: Callable

## Score flames (like the game's 'flame' shader): rise from the bottom of the chips/mult box,
## flicker, and grow with the intensity the game reports.
const FLAME_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec4 colour_1 : source_color = vec4(0.0, 0.6, 1.0, 1.0);
uniform vec4 colour_2 : source_color = vec4(1.0, 0.9, 0.3, 1.0);
uniform float intensity = 0.0;
uniform bool hard_edges = false;
uniform float phase = 0.0; // lets several flames flicker out of step
uniform float opacity = 1.0; // < 1: what is behind shows through (flames lying on a card)

void fragment() {
	float x = UV.x;
	float up = 1.0 - UV.y;                       // 0 at the bottom, 1 at the top
	float t = TIME + phase;
	float wave = 0.10 * sin(x * 13.0 + t * 7.0) + 0.06 * sin(x * 29.0 - t * 11.0) + 0.04 * sin(t * 17.0 + x * 5.0);
	float height = clamp(intensity, 0.0, 1.5) / 1.5 * (0.85 + wave);
	float body = clamp((height - up) * 5.0, 0.0, 1.0);
	float sides = smoothstep(0.0, 0.18, x) * smoothstep(1.0, 0.82, x);
	float a = body * sides * opacity;
	if (hard_edges) {
		if (a < 0.5) discard;                    // chroma-key mode: no green-mixed rims
		a = 1.0;
	}
	ALBEDO = mix(colour_1.rgb, colour_2.rgb, clamp(up / max(height, 0.01), 0.0, 1.0));
	ALPHA = a;
}
"""
static var _flame_shader: Shader

var _visuals := {}                  # item id -> Node3D
var _time := 0.0                    # animation clock
var _juice := {}                    # item id -> time its text last changed (bounce)
var _animated := {}                 # item id -> "Letters" node of an animated text
var _groups := {}                   # group id -> container Node3D
var _dim: MeshInstance3D            # darkens everything below an overlay menu
var _backing: MeshInstance3D        # the "felt" behind the board


func _ready() -> void:
	_backing = _make_quad(Color(0.13, 0.27, 0.22, 1.0))
	_backing.position.z = -0.003
	add_child(_backing)
	_dim = _make_quad(Color(0, 0, 0, 0.6))
	_dim.visible = false
	add_child(_dim)
	_resize_backing()


func set_backing_visible(on: bool) -> void:
	_backing.visible = on


func apply_scene(scene: Dictionary) -> void:
	var room: Dictionary = scene.get("room", {})
	var new_size := Vector2(float(room.get("w", 20.0)), float(room.get("h", 11.5)))
	if new_size != room_size:
		room_size = new_size
		_resize_backing()

	# group id -> info, role -> rect (for anchors that align to another group)
	var group_info := {}
	var role_rect := {}
	for g in scene.get("groups", []):
		group_info[int(g.get("id", 0))] = g
		var role := str(g.get("role", ""))
		if role != "" and not role_rect.has(role):
			role_rect[role] = g

	var containers := {}
	var items: Array = scene.get("items", [])
	var seen := {}
	for i in items.size():
		var it: Dictionary = items[i]
		var kind: String = it.get("k", "")
		if keep_hand_separate and kind == "c" and (it.get("area", "") == "hand" or it.get("area", "") == "play"): # VR: played cards lie on the table
			continue
		var gid := int(it.get("g", 0))
		var group_role := str(group_info.get(gid, {}).get("role", ""))
		# VR: jokers and consumables stand on the joker board as 3D models / cards in the rack
		if keep_hand_separate and (group_role in ["area:jokers", "area:consumeables"]
				or (kind == "c" and it.get("area", "") in ["jokers", "consumeables"])):
			continue
		if _hidden_in_compact(it, group_role):
			continue
		if _off_screen(it):
			continue
		if not containers.has(gid):
			containers[gid] = _container_for(gid, group_info.get(gid, {}), group_info, role_rect)
		var container: Node3D = containers[gid]

		var id := int(it.get("id", 0))
		seen[id] = true
		var v = _visuals.get(id) # untyped: may hold a freed node (e.g. tooltip above a discarded hand card)
		if v != null and (not is_instance_valid(v) or v.get_meta("kind") != kind):
			if is_instance_valid(v):
				v.queue_free()
			v = null
		if v == null:
			v = Node3D.new()
			v.set_meta("kind", kind)
			container.add_child(v)
			_visuals[id] = v
		elif v.get_parent() != container:
			v.reparent(container, false)
		_update_item(v, kind, it, i)

	for id in _visuals.keys():
		if not seen.has(id):
			if is_instance_valid(_visuals[id]):
				_visuals[id].queue_free()
			_visuals.erase(id)
			_juice.erase(id)
			_animated.erase(id)
	for gid in _groups.keys():
		if not containers.has(gid):
			if is_instance_valid(_groups[gid]):
				_groups[gid].queue_free()
			_groups.erase(gid)

	var overlay: bool = scene.get("overlay", false)
	_dim.visible = overlay and not hide_dimmers
	if overlay:
		_dim.position.z = (float(scene.get("overlay_from", 0)) + 0.5) * Z_STEP


## The game "parks" panels it doesn't need outside the screen instead of hiding them (cash out
## after paying, shop and blind select between their phases). On a monitor you never see them,
## so in VR they are not drawn either; sliding back in, they reappear on their own.
func _off_screen(it: Dictionary) -> bool:
	const MARGIN := 1.0 # room units; things just peeking in at the edge stay visible
	var x: float = it.get("x", 0.0)
	var y: float = it.get("y", 0.0)
	var w: float = it.get("w", 0.0)
	var h: float = it.get("h", 0.0)
	return x > room_size.x + MARGIN or x + w < -MARGIN or y > room_size.y + MARGIN or y + h < -MARGIN


func _hidden_in_compact(it: Dictionary, role: String) -> bool:
	if REPLACED_ROLES.has(role):
		return true
	if not compact_hud:
		return false
	if role == "HUD_blind":
		return true # blind name, target score and reward only matter while playing the blind
	if role != "HUD":
		return false
	var ids := str(it.get("ids", ""))
	if not ids.contains(COMPACT_KEEP):
		return true # round score, chips x mult and the panel background
	for drop in COMPACT_DROP:
		if ids.contains(drop):
			return true
	return false


# ---------------------------------------------------------------- groups & anchors

func _container_for(gid: int, g: Dictionary, group_info: Dictionary, role_rect: Dictionary) -> Node3D:
	var placement := _placement(g, group_info, role_rect)
	var parent: Node3D = placement[0]
	var c = _groups.get(gid)
	if c == null or not is_instance_valid(c):
		c = Node3D.new()
		c.name = "Group%d" % gid
		parent.add_child(c)
		_groups[gid] = c
	elif c.get_parent() != parent:
		c.reparent(parent, false)
	c.position = placement[1]
	return c


## Returns [parent node, offset]: the offset moves the reference rect's center onto the parent's origin.
func _placement(g: Dictionary, group_info: Dictionary, role_rect: Dictionary) -> Array:
	var role := str(g.get("role", ""))
	if role == "popup" and g.has("owner"):
		if popup_anchor_for.is_valid():
			var n = popup_anchor_for.call(int(g["owner"]))
			if n != null:
				return [n, -_center(g)]
		# the tooltip goes exactly where its card is drawn right now: same parent, same offset
		# (the shop on the table, the board, a booster pack ...)
		var owner_visual = _visuals.get(int(g["owner"]))
		if owner_visual != null and is_instance_valid(owner_visual):
			var owner_container: Node3D = owner_visual.get_parent()
			if owner_container != null and owner_container.get_parent() is Node3D:
				return [owner_container.get_parent(), owner_container.position]
		if g.has("owner_group"): # tooltip of a shop card: travel with the shop
			var owner_group: Dictionary = group_info.get(int(g["owner_group"]), {})
			role = str(owner_group.get("role", ""))
	if anchors.has(role):
		var a: Dictionary = anchors[role]
		var ref: Dictionary = role_rect.get(a.get("ref", role), g)
		return [a["node"], -_center(ref)]
	return [self, Vector3.ZERO]


func _center(rect: Dictionary) -> Vector3:
	var x: float = rect.get("x", 0.0)
	var y: float = rect.get("y", 0.0)
	var w: float = rect.get("w", 0.0)
	var h: float = rect.get("h", 0.0)
	return Vector3((x + w * 0.5 - room_size.x * 0.5) * SCALE, -(y + h * 0.5 - room_size.y * 0.5) * SCALE, 0.0)


# ---------------------------------------------------------------- items

func _update_item(v: Node3D, kind: String, it: Dictionary, order: int) -> void:
	var w: float = it.get("w", 0.0)
	var h: float = it.get("h", 0.0)
	v.position = _center(it) + Vector3(0, 0, order * Z_STEP)
	var size := Vector2(maxf(w, 0.001) * SCALE, maxf(h, 0.001) * SCALE)
	var id := int(it.get("id", 0))
	var clickable: bool = it.get("b", false)

	# Rects larger than the game screen are never drawn: they only darken everything behind a menu
	# (the board has its own _dim for that) or are the endless sidebar background behind the
	# Run Panel (minh = 30), which would stand as a grey wall next to the panel in VR.
	if kind == "r" and (w > room_size.x * 1.5 or h > room_size.y * 1.5):
		_set_quad(v, size, Color.WHITE, false)
		_set_label(v, "", size.y, size.x, Color.WHITE)
		_set_body(v, false, size, id, "", "")
		return

	match kind:
		"r":
			var c = it.get("c")
			var has_colour := c != null
			_set_quad(v, size, to_color(c) if has_colour else Color(0, 0, 0, 0), has_colour)
			_set_label(v, "", size.y, size.x, Color.WHITE)
			_set_body(v, clickable, size, id, "ui", "")
		"t":
			_set_quad(v, size, Color.WHITE, false)
			var text_col := to_color(it.get("c"))
			if it.get("off", false):
				text_col = Color(0.55, 0.55, 0.55)
			# vertical labels (e.g. "ANTE 2 VOUCHER" in the shop) are tall and narrow: their letter
			# height is the element's width, not its height
			var vertical: bool = it.get("vert", false)
			var text := str(it.get("s", ""))
			var height := size.x if vertical else size.y
			var is_new := not v.has_meta("text")
			var changed: bool = not is_new and v.get_meta("text") != text
			v.set_meta("text", text)
			if it.get("dyn", false) and not vertical:
				# the game's animated texts: letter by letter, so they can bump, float, wobble and pop in
				_set_label(v, "", height, 0.0, text_col)
				_set_letters(v, id, text, height, text_col, it.get("fx", {}), is_new or changed)
			else:
				_hide_letters(v, id)
				_set_label(v, text, height, 0.0, text_col, vertical)
			if changed:
				_juice[id] = _time # a value changed: give it a little bounce like the game does
			_set_body(v, clickable, size, id, "ui", "")
		"c":
			var layers := CardArt.card_layers(it)
			var has_art := not layers.is_empty()
			# the art layers stay within this item's own depth step: deeper than Z_STEP they would
			# poke through whatever the game draws next (e.g. the SELL tab of the card on the left)
			CardArt.apply_layers(v, layers, size, Z_STEP * 0.2, Z_STEP * 0.1) # up to 7 layers in 0.8 steps
			_set_quad(v, size, card_color(it), not has_art)
			_set_label(v, "" if has_art else card_text(it), size.y * 0.13, size.x, card_text_color(it))
			_set_body(v, true, size, id, "card", str(it.get("area", "")))
		"fl":
			_set_quad(v, size, Color.WHITE, false)
			_set_label(v, "", size.y, size.x, Color.WHITE)
			_set_body(v, false, size, id, "", "")
			_set_flame(v, size, it)
		"s":
			var art := CardArt.material(it.get("a"), it.get("p"))
			CardArt.apply_layers(v, [art] if art != null else [], size, Z_STEP * 0.3, Z_STEP * 0.3, 1)
			_set_quad(v, size, Color(1, 1, 1, 0.18), art == null)
			_set_label(v, "", size.y, size.x, Color.WHITE)
			# a sprite with a tooltip in the game (the skip tag on the blind select, tags in the run
			# panel): the beam can point at it to show the tooltip
			_set_body(v, bool(it.get("hv", false)), size, id, "tip", "")


# ---------------------------------------------------------------- text animation ("juice")
# Same formulas as the game's DynaText (engine/text.lua), driven by our own clock so letters move
# smoothly at headset frame rate instead of the 15 scene updates per second.

func _process(delta: float) -> void:
	_time += delta
	for id in _juice.keys():
		var v = _visuals.get(id)
		var age: float = _time - _juice[id]
		if v == null or not is_instance_valid(v) or age > 0.45:
			if v != null and is_instance_valid(v):
				v.scale = Vector3.ONE
			_juice.erase(id)
			continue
		v.scale = Vector3.ONE * (1.0 + 0.18 * sin(age * 28.0) * exp(-age * 7.0))
	for id in _animated.keys():
		var box = _animated[id]
		if box == null or not is_instance_valid(box) or not box.visible:
			_animated.erase(id)
			continue
		_animate_letters(box)


func _letter_font() -> Font:
	return GameFont.font if GameFont.font != null else ThemeDB.fallback_font


func _set_letters(v: Node3D, id: int, text: String, height: float, colour: Color, fx: Dictionary, pop: bool) -> void:
	var box: Node3D = v.get_node_or_null("Letters")
	if box == null:
		box = Node3D.new()
		box.name = "Letters"
		box.position.z = 0.0003
		v.add_child(box)
	box.visible = true
	_animated[id] = box
	box.set_meta("fx", fx)
	box.set_meta("height", height)
	if pop:
		box.set_meta("pop_t0", _time) # letters pop in one after another

	var font := _letter_font()
	if box.get_meta("built_text", "") != text or box.get_meta("built_height", 0.0) != height \
			or box.get_meta("built_font", null) != font:
		for child in box.get_children():
			child.queue_free()
			box.remove_child(child)
		var px := maxf(height, 0.001) / FONT_SIZE
		var widths: Array[float] = []
		var total := 0.0
		for i in text.length():
			var w := font.get_char_size(text.unicode_at(i), FONT_SIZE).x * px
			widths.append(w)
			total += w
		var x := -total * 0.5
		for i in text.length():
			var letter := Label3D.new()
			letter.text = text[i]
			letter.font = font
			letter.font_size = FONT_SIZE
			letter.pixel_size = px
			letter.outline_size = 0
			letter.position = Vector3(x + widths[i] * 0.5, 0, 0)
			letter.set_meta("base", letter.position)
			x += widths[i]
			box.add_child(letter)
		box.set_meta("built_text", text)
		box.set_meta("built_height", height)
		box.set_meta("built_font", font)
	for letter in box.get_children():
		letter.modulate = colour
		_text_sorting(letter)


func _hide_letters(v: Node3D, id: int) -> void:
	var box: Node3D = v.get_node_or_null("Letters")
	if box != null:
		box.visible = false
	_animated.erase(id)


func _animate_letters(box: Node3D) -> void:
	var fx: Dictionary = box.get_meta("fx", {})
	var height: float = box.get_meta("height", 0.0)
	var pop_t0: float = box.get_meta("pop_t0", -100.0)
	var n := box.get_child_count()
	var t := _time
	for i in n:
		var letter: Label3D = box.get_child(i)
		var k := float(i + 1) # the game counts letters from 1
		var y := 0.0          # vertical offset as a fraction of the letter height
		var r := 0.0          # rotation (game: clockwise with y pointing down)
		var s := 1.0
		if fx.has("rot"):
			r = float(fx["rot"]) * (0.2 * (-n / 2.0 - 0.5 + k) / n + 0.02 * sin(2.0 * t + k))
		if fx.has("q"): # quiver while a number is counting up
			var a := float(fx["q"])
			var sp := float(fx.get("qs", 0.5))
			s += 0.1 * a
			r += 0.3 * a * (sin(41.12342 * t * sp + k * 1223.2) + cos(63.21231 * t * sp + k * 1112.2) * sin(36.1231 * t * sp)
				+ cos(95.123 * t * sp + k * 1233.2) - sin(30.133421 * t * sp + k * 123.2))
		if fx.has("float"):
			y = 0.1 * sin(2.666 * t + 200.0 * k)
		if fx.has("bump"): # a wave of hops running through the letters
			var br := float(fx.get("br", 2.666))
			y = 0.1 * float(fx["bump"]) * maxf(0.0, (5.0 + br) * sin(br * t + 200.0 * k) - 3.0 - br)
		var p := clampf((t - pop_t0) * n * 3.0 - k + 1.0, 0.0, 1.0) # pop-in, about 1/3 s for the word
		s *= p * p
		letter.position = letter.get_meta("base") + Vector3(0, y * height, 0)
		letter.rotation.z = -r
		letter.scale = Vector3.ONE * maxf(s, 0.001)


func _set_flame(v: Node3D, size: Vector2, it: Dictionary) -> void:
	var flame: MeshInstance3D = v.get_node_or_null("Flame")
	if flame == null:
		flame = make_flame()
		v.add_child(flame)
	# flames start at the bottom of the box and rise up to 2.5 box heights, behind its content
	var height := size.y * 2.5
	flame.scale = Vector3(size.x, height, 1)
	flame.position = Vector3(0, -size.y * 0.5 + height * 0.5, -Z_STEP * 0.5)
	set_flame(flame, it, opaque_mode)


## A unit quad drawing a score flame (rises from its bottom edge); scale it to the wanted size.
static func make_flame() -> MeshInstance3D:
	if _flame_shader == null:
		_flame_shader = Shader.new()
		_flame_shader.code = FLAME_SHADER
	var flame := MeshInstance3D.new()
	flame.name = "Flame"
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	flame.mesh = quad
	var mat := ShaderMaterial.new()
	mat.shader = _flame_shader
	flame.material_override = mat
	return flame


## Colours and strength from a flame item of the scene ({"c", "c2", "i"}).
static func set_flame(flame: MeshInstance3D, it: Dictionary, hard_edges: bool, phase := 0.0) -> void:
	var mat: ShaderMaterial = flame.material_override
	mat.set_shader_parameter("colour_1", to_color(it.get("c")))
	mat.set_shader_parameter("colour_2", to_color(it.get("c2")))
	mat.set_shader_parameter("intensity", float(it.get("i", 0.0)))
	mat.set_shader_parameter("hard_edges", hard_edges)
	mat.set_shader_parameter("phase", phase)


## Text must never end up behind the panel it is printed on. Blended (see-through) things are
## sorted by their distance to the eye, so the left half of a title could get the translucent
## panel drawn over it ("Jugg" grey, "ler" white). The solid parts of the letters go through the
## depth pre-pass instead, and text is drawn after the panels anyway.
func _text_sorting(label: Label3D) -> void:
	label.alpha_cut = Label3D.ALPHA_CUT_DISCARD if opaque_mode else Label3D.ALPHA_CUT_OPAQUE_PREPASS
	label.render_priority = 10
	label.outline_render_priority = 9


func _surface(c: Color) -> Color:
	if not opaque_mode or c.a >= 0.999:
		return c
	if c.a < 0.2:
		return Color(0, 0, 0, 0)
	var base := Color(0.1, 0.11, 0.14) # what the translucent panel would show through in the game
	return Color(lerpf(base.r, c.r, c.a), lerpf(base.g, c.g, c.a), lerpf(base.b, c.b, c.a), 1.0)


func _set_quad(v: Node3D, size: Vector2, colour: Color, visible_quad: bool) -> void:
	var mesh: MeshInstance3D = v.get_node_or_null("Mesh")
	colour = _surface(colour)
	if colour.a <= 0.0:
		visible_quad = false
	if not visible_quad:
		if mesh != null:
			mesh.visible = false
		return
	if mesh == null:
		mesh = _make_quad(colour)
		mesh.name = "Mesh"
		v.add_child(mesh)
	mesh.visible = true
	mesh.scale = Vector3(size.x, size.y, 1.0)
	var mat: StandardMaterial3D = mesh.material_override
	if mat.albedo_color != colour:
		mat.albedo_color = colour
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if colour.a < 0.999 else BaseMaterial3D.TRANSPARENCY_DISABLED


func _set_label(v: Node3D, text: String, text_height: float, wrap_width: float, colour: Color, vertical := false) -> void:
	var label: Label3D = v.get_node_or_null("Label")
	if text == "":
		if label != null:
			label.visible = false
		return
	if label == null:
		label = Label3D.new()
		label.name = "Label"
		label.font_size = FONT_SIZE
		label.outline_size = 0
		label.position.z = 0.0003
		v.add_child(label)
	label.visible = true
	label.text = text
	label.modulate = colour
	# hard text edges in chroma-key mode, otherwise the anti-aliased rim mixes with the green
	_text_sorting(label)
	label.pixel_size = maxf(text_height, 0.001) / FONT_SIZE
	label.rotation_degrees = Vector3(0, 0, 90 if vertical else 0)
	if wrap_width > 0.0:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.width = wrap_width / label.pixel_size
	else:
		label.autowrap_mode = TextServer.AUTOWRAP_OFF


func _set_body(v: Node3D, enabled: bool, size: Vector2, id: int, kind: String, area: String) -> void:
	var body: StaticBody3D = v.get_node_or_null("Body")
	if not enabled:
		if body != null:
			body.queue_free()
		return
	if body == null:
		body = StaticBody3D.new()
		body.name = "Body"
		var shape := CollisionShape3D.new()
		shape.shape = BoxShape3D.new()
		body.add_child(shape)
		v.add_child(body)
	var box: BoxShape3D = body.get_child(0).shape
	box.size = Vector3(size.x, size.y, 0.004)
	body.set_meta("target_id", id)
	body.set_meta("kind", kind)
	body.set_meta("area", area)


func _resize_backing() -> void:
	if _backing == null:
		return
	var size := Vector3(room_size.x * SCALE, room_size.y * SCALE, 1.0)
	_backing.scale = size
	_dim.scale = size


static func _make_quad(colour: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	mesh.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = colour
	if colour.a < 0.999:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material_override = mat
	return mesh


# ---------------------------------------------------------------- shared card look (board + hand fan)

static func to_color(c) -> Color:
	if c is Array and c.size() >= 3:
		return Color(float(c[0]), float(c[1]), float(c[2]), float(c[3]) if c.size() > 3 else 1.0)
	return Color.WHITE


static func is_playing_card(it: Dictionary) -> bool:
	return it.has("rank")


static func card_color(it: Dictionary) -> Color:
	if it.get("f", "front") != "front":
		return Color(0.55, 0.16, 0.16)
	if is_playing_card(it):
		return Color(0.95, 0.93, 0.88)
	match str(it.get("set", "")):
		"Joker": return Color(0.33, 0.27, 0.52)
		"Tarot": return Color(0.55, 0.38, 0.7)
		"Planet": return Color(0.22, 0.42, 0.75)
		"Spectral": return Color(0.18, 0.52, 0.58)
		"Voucher": return Color(0.75, 0.55, 0.18)
		"Booster": return Color(0.62, 0.24, 0.24)
	return Color(0.5, 0.5, 0.55)


static func card_text_color(it: Dictionary) -> Color:
	if it.get("f", "front") == "front" and is_playing_card(it):
		match str(it.get("suit", "")):
			"Hearts": return Color(0.85, 0.15, 0.15)
			"Diamonds": return Color(0.9, 0.45, 0.1)
			"Clubs": return Color(0.1, 0.3, 0.25)
			"Spades": return Color(0.12, 0.12, 0.2)
	return Color.WHITE


static func card_text(it: Dictionary) -> String:
	if it.get("f", "front") != "front":
		return "?"
	var text := ""
	if is_playing_card(it):
		text = "%s\n%s" % [it.get("rank", "?"), it.get("suit", "")]
	else:
		text = str(it.get("name", "?"))
	if it.has("ed"):
		text += "\n" + str(it["ed"])
	if it.get("db", false):
		text += "\n(debuff)"
	return text
