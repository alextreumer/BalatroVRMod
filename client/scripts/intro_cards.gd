class_name IntroCards
extends Node3D
## Swirl of flying cards shown while Balatro boots (it loads all assets before mods – and with
## them our bridge – are started, then plays its own splash). Cards orbit, spin and breathe in
## front of the player; when the game is ready they burst outwards and vanish.
##
## The cards are real Balatro cards: random fronts, and on the back a wild mix of every deck in
## the game. The mod can't send anything while Balatro boots, so the client remembers the card
## atlases from the last connection in the player's app data (user://intro_cache). Before the very
## first connection simple drawn cards stand in.

const CARD_COUNT := 36
const CARD_SIZE := Vector2(0.066, 0.088)
const FACE_COLOR := Color(0.96, 0.95, 0.9)
const BACK_COLOR := Color(0.85, 0.27, 0.24) # Balatro's red deck
const RANKS := ["A", "K", "Q", "J", "10", "9", "8", "7"]
const FADE_IN := 0.6
const LEAVE_TIME := 0.9
const CACHE := "user://intro_cache"

var _cards: Array[Node3D] = []
var _params: Array[Dictionary] = []
var _label: Label3D
var _time := 0.0
var _mode := "off"         # off · on · leaving
var _mode_time := 0.0

static var _wanted_atlases := {} # atlas names the last "intro" message referred to


# ---------------------------------------------------------------- cache (called by the client)

## The mod's list of fronts, card base and deck backs: remembered for the next boot.
static func remember_assets(data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(CACHE)
	var f := FileAccess.open(CACHE + "/intro.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data))
	_wanted_atlases.clear()
	for list in [data.get("backs", []), data.get("fronts", []), [data.get("base", {})]]:
		for ref in list:
			if ref is Dictionary and ref.has("atlas"):
				_wanted_atlases[str(ref["atlas"])] = true


## An atlas from the mod: kept if the swirl needs it.
static func remember_atlas(data: Dictionary) -> void:
	var name := str(data.get("name", ""))
	if not _wanted_atlases.has(name):
		return
	DirAccess.make_dir_recursive_absolute(CACHE)
	var png := FileAccess.open(CACHE + "/%s.png" % name, FileAccess.WRITE)
	if png != null:
		png.store_buffer(Marshalls.base64_to_raw(str(data.get("png", ""))))
	var meta := FileAccess.open(CACHE + "/%s.json" % name, FileAccess.WRITE)
	if meta != null:
		meta.store_string(JSON.stringify({"px": data.get("px", 71), "py": data.get("py", 95), "scale": data.get("scale", 1.0)}))


## {"fronts": [[material, material], ...], "backs": [material, ...]} or {} without a cache.
func _load_cache() -> Dictionary:
	if not FileAccess.file_exists(CACHE + "/intro.json"):
		return {}
	var info = JSON.parse_string(FileAccess.get_file_as_string(CACHE + "/intro.json"))
	if not (info is Dictionary):
		return {}
	var atlases := {}
	var base = _cell_material(info.get("base"), atlases)
	var fronts: Array = []
	for ref in info.get("fronts", []):
		var m = _cell_material(ref, atlases)
		if m != null:
			fronts.append([base, m] if base != null else [m])
	var backs: Array = []
	for ref in info.get("backs", []):
		var m = _cell_material(ref, atlases)
		if m != null:
			backs.append(m)
	if fronts.is_empty() or backs.is_empty():
		return {}
	return {"fronts": fronts, "backs": backs}


## Material showing one atlas cell ({"atlas": name, "pos": [x, y]}), atlases loaded once.
func _cell_material(ref, atlases: Dictionary) -> StandardMaterial3D:
	if not (ref is Dictionary) or not ref.has("atlas") or not (ref.get("pos") is Array):
		return null
	var name := str(ref["atlas"])
	if not atlases.has(name):
		atlases[name] = null
		var png := CACHE + "/%s.png" % name
		if FileAccess.file_exists(png) and FileAccess.file_exists(CACHE + "/%s.json" % name):
			var img := Image.new()
			if img.load_png_from_buffer(FileAccess.get_file_as_bytes(png)) == OK:
				img.generate_mipmaps()
				var meta = JSON.parse_string(FileAccess.get_file_as_string(CACHE + "/%s.json" % name))
				var scale := float(meta.get("scale", 1.0)) if meta is Dictionary else 1.0
				atlases[name] = {
					"tex": ImageTexture.create_from_image(img),
					"cell": Vector2(float(meta.get("px", 71)), float(meta.get("py", 95))) * scale if meta is Dictionary else Vector2(71, 95),
					"size": Vector2(img.get_width(), img.get_height()),
				}
	var atlas = atlases[name]
	if atlas == null:
		return null
	var pos: Array = ref["pos"]
	var cell: Vector2 = atlas["cell"]
	var size: Vector2 = atlas["size"]
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = atlas["tex"]
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR # rounded card corners
	mat.alpha_scissor_threshold = 0.5
	mat.uv1_scale = Vector3(cell.x / size.x, cell.y / size.y, 1)
	mat.uv1_offset = Vector3(int(pos[0]) * cell.x / size.x, int(pos[1]) * cell.y / size.y, 0)
	return mat


# ---------------------------------------------------------------- the swirl

func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize() # a new mix of cards every boot
	var quad := QuadMesh.new()
	quad.size = CARD_SIZE
	var art := _load_cache()
	for i in CARD_COUNT:
		var card := Node3D.new()
		if art.is_empty():
			_drawn_card(card, quad, i)
		else:
			var front: Array = art["fronts"][rng.randi() % art["fronts"].size()]
			for k in front.size(): # card base, then rank and suit on top
				var layer := MeshInstance3D.new()
				layer.mesh = quad
				layer.material_override = front[k]
				layer.position.z = 0.0003 + k * 0.0003
				card.add_child(layer)
			var back := MeshInstance3D.new()
			back.mesh = quad
			back.material_override = art["backs"][rng.randi() % art["backs"].size()]
			back.rotation_degrees.y = 180
			back.position.z = -0.0003
			card.add_child(back)
		add_child(card)
		_cards.append(card)
		_params.append({
			"phase": rng.randf() * TAU,
			"radius": rng.randf_range(0.16, 0.6),
			"height": rng.randf_range(-0.26, 0.26),
			"speed": rng.randf_range(0.5, 1.3) * (1.0 if i % 3 != 0 else -1.0),
			"spin": rng.randf_range(1.5, 3.8) * (1.0 if rng.randf() < 0.7 else -1.0),
			"tilt": rng.randf_range(-0.8, 0.8),
			"flip": rng.randf_range(0.6, 2.2), # tumbling end over end, so both sides flash by
		})
	_label = Label3D.new()
	_label.text = "Balatro is starting …"
	_label.font_size = 64
	_label.pixel_size = 0.0012
	_label.outline_size = 12
	_label.position = Vector3(0, -0.38, 0.05)
	add_child(_label)
	visible = false


## Before the first connection: a simply drawn card (white face with a rank, red back).
func _drawn_card(card: Node3D, quad: QuadMesh, i: int) -> void:
	card.add_child(_side(quad, FACE_COLOR, false))
	card.add_child(_side(quad, BACK_COLOR, true))
	var rank := Label3D.new()
	rank.text = RANKS[i % RANKS.size()]
	rank.modulate = Color(0.85, 0.15, 0.15) if i % 2 == 0 else Color(0.12, 0.12, 0.18)
	rank.font_size = 64
	rank.pixel_size = 0.0006
	rank.position.z = 0.0006
	card.add_child(rank)


func _side(quad: QuadMesh, colour: Color, back: bool) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = colour
	mesh.material_override = mat
	if back:
		mesh.rotation_degrees.y = 180
	return mesh


## Show the swirl while Balatro is starting; hiding it lets the cards fly off first.
func set_active(on: bool) -> void:
	if on and _mode != "on":
		_mode = "on"
		_mode_time = 0.0
		visible = true
	elif not on and _mode == "on":
		_mode = "leaving"
		_mode_time = 0.0


func is_showing() -> bool:
	return _mode != "off"


func _process(delta: float) -> void:
	if _mode == "off":
		return
	_time += delta
	_mode_time += delta
	var appear := clampf(_mode_time / FADE_IN, 0.0, 1.0) if _mode == "on" else 1.0
	var leave := clampf(_mode_time / LEAVE_TIME, 0.0, 1.0) if _mode == "leaving" else 0.0
	if _mode == "leaving" and leave >= 1.0:
		_mode = "off"
		visible = false
		return

	var burst := leave * leave # accelerating outwards
	for i in _cards.size():
		var p: Dictionary = _params[i]
		var angle: float = p["phase"] + _time * float(p["speed"])
		# the swirl breathes in and out like the game's splash vortex
		var radius: float = float(p["radius"]) * (0.75 + 0.25 * sin(_time * 0.9 + float(p["phase"]))) * (1.0 + 4.0 * burst)
		var card := _cards[i]
		card.position = Vector3(cos(angle) * radius, float(p["height"]) + 0.03 * sin(_time * 2.0 + i) + 0.3 * burst, sin(angle) * radius * 0.6)
		card.rotation = Vector3(float(p["tilt"]) + sin(_time * float(p["flip"]) + i) * 0.9,
				_time * float(p["spin"]) + i, 0.25 * sin(_time + i))
		card.scale = Vector3.ONE * maxf(_ease_out(appear) * (1.0 - leave), 0.001)
	_label.modulate.a = (1.0 - leave) * appear
	_label.outline_modulate.a = _label.modulate.a


func _ease_out(x: float) -> float:
	return 1.0 - (1.0 - x) * (1.0 - x)
