class_name CardArt
extends RefCounted
## Texture atlases streamed from the running game (sent once per connection) and the materials
## that show a single atlas cell. Nothing from the game is shipped with the client; only the card
## swirl shown while Balatro boots keeps a copy of the card atlases in the player's own app data
## (see IntroCards).

static var _atlases := {}     # name -> {"tex": ImageTexture, "cell": Vector2 (pixels), "size": Vector2 (pixels)}
static var _materials := {}   # "name|x|y" -> StandardMaterial3D
static var _quad: QuadMesh


## Has that texture atlas arrived from the game yet?
static func has_atlas(name) -> bool:
	return _atlases.has(str(name))


static func add_atlas(data: Dictionary) -> void:
	var name := str(data.get("name", ""))
	var img := Image.new()
	var err := img.load_png_from_buffer(Marshalls.base64_to_raw(str(data.get("png", ""))))
	if err != OK or name == "":
		push_warning("Textur-Atlas '%s' konnte nicht geladen werden (Fehler %d)" % [name, err])
		return
	img.generate_mipmaps()
	var scale: float = data.get("scale", 1.0)
	_atlases[name] = {
		"tex": ImageTexture.create_from_image(img),
		"cell": Vector2(float(data.get("px", 71)) * scale, float(data.get("py", 95)) * scale),
		"size": Vector2(img.get_width(), img.get_height()),
	}
	for key in _materials.keys():
		if key.begins_with(name + "|"):
			_materials.erase(key)
	for key in _cropped.keys():
		if key.begins_with(name + "|"):
			_cropped.erase(key)
	for key in _debuff_materials.keys():
		if key.begins_with(name + "|"):
			_debuff_materials.erase(key)
	for key in _played_materials.keys():
		if key.begins_with(name + "|"):
			_played_materials.erase(key)
	_edition_materials.clear() # they mix two atlases: simply rebuild them


static func clear() -> void:
	_atlases.clear()
	_materials.clear()


## Material showing cell `pos` ([x, y]) of atlas `name`, or null while that atlas has not arrived.
## `blend`: half-transparent pixels stay half-transparent (Glass Card) instead of being cut.
static func material(name, pos, blend := false) -> StandardMaterial3D:
	if name == null or not (pos is Array) or pos.size() < 2 or not _atlases.has(str(name)):
		return null
	var x := int(pos[0])
	var y := int(pos[1])
	var key := "%s|%d|%d%s" % [name, x, y, "|blend" if blend else ""]
	if _materials.has(key):
		return _materials[key]

	var atlas: Dictionary = _atlases[str(name)]
	var cell: Vector2 = atlas["cell"]
	var size: Vector2 = atlas["size"]
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = atlas["tex"]
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS # crisp pixel art like the game
	if blend:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	else:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR # rounded card corners
		mat.alpha_scissor_threshold = 0.5
	mat.uv1_scale = Vector3(cell.x / size.x, cell.y / size.y, 1)
	mat.uv1_offset = Vector3(x * cell.x / size.x, y * cell.y / size.y, 0)
	_materials[key] = mat
	return mat


## Only the drawn part of a cell (a sticker is a small picture in a card-sized cell): a material showing
## just that, and its width / height. Null until the atlas has arrived; cached per cell.
static var _cropped := {}


static func cropped_material(name, pos) -> Array:
	if name == null or not (pos is Array) or pos.size() < 2 or not _atlases.has(str(name)):
		return []
	var key := "%s|%d|%d" % [name, int(pos[0]), int(pos[1])]
	if _cropped.has(key):
		return _cropped[key]
	var atlas: Dictionary = _atlases[str(name)]
	var cell: Vector2 = atlas["cell"]
	var size: Vector2 = atlas["size"]
	var img := (atlas["tex"] as ImageTexture).get_image()
	var cx := int(pos[0] * cell.x)
	var cy := int(pos[1] * cell.y)
	var x0 := int(cell.x); var y0 := int(cell.y); var x1 := -1; var y1 := -1
	for y in int(cell.y):
		for x in int(cell.x):
			if cx + x < img.get_width() and cy + y < img.get_height() and img.get_pixel(cx + x, cy + y).a > 0.3:
				x0 = mini(x0, x); y0 = mini(y0, y); x1 = maxi(x1, x); y1 = maxi(y1, y)
	if x1 < 0:
		return []
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = atlas["tex"]
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.5
	var w := x1 - x0 + 1
	var h := y1 - y0 + 1
	mat.uv1_scale = Vector3(w / size.x, h / size.y, 1)
	mat.uv1_offset = Vector3((cx + x0) / size.x, (cy + y0) / size.y, 0)
	_cropped[key] = [mat, float(w) / float(h)]
	return _cropped[key]


## Materials to draw for a card item, bottom to top. Empty if the textures are not there (yet).
## Playing cards = base (enhancement) + rank/suit; jokers & consumables = one image; face down = back.
static func card_layers(it: Dictionary) -> Array:
	var layers: Array = []
	if it.get("f", "front") != "front":
		var back := material(it.get("ba"), it.get("bp"))
		if back != null:
			layers.append(back)
		return layers
	var center := material(it.get("ca"), it.get("cp"))
	if center == null:
		return layers
	var debuffed: bool = it.get("db", false)
	if debuffed:
		# debuffed by a boss blind: drawn through the game's 'debuff' shader (faded + red X)
		layers.append(debuff_material(it.get("ca"), it.get("cp")))
		var front_db := debuff_material(it.get("fa"), it.get("fp"))
		if front_db != null:
			layers.append(front_db)
		return layers
	if it.get("gr", false):
		# already played (View Deck): drawn greyed out like the game's 'played' shader
		layers.append(played_material(it.get("ca"), it.get("cp")))
		var front_gr := played_material(it.get("fa"), it.get("fp"))
		if front_gr != null:
			layers.append(front_gr)
		return _with_overlays(layers, it)
	if str(it.get("key", "")) == "m_glass": # Glass Card: its see-through parts stay see-through
		center = material(it.get("ca"), it.get("cp"), true)
	layers.append(center)
	var front := material(it.get("fa"), it.get("fp"))
	if front != null:
		layers.append(front)
	var edition := edition_material(it)
	if edition != null:
		layers.append(edition) # foil, holo, polychrome, negative: redraws the card with the effect
	return _with_overlays(layers, it)


## Seal and stickers (Eternal, Perishable, Rental, stake stickers ...) on top of the card.
static func _with_overlays(layers: Array, it: Dictionary) -> Array:
	for ov in it.get("ov", []):
		if ov is Dictionary:
			var m := material(ov.get("a"), ov.get("p"))
			if m != null:
				layers.append(m)
	return layers


## Editions, after the game's foil / holo / polychrome / negative shaders: the card (base + rank and
## suit) is drawn again with the effect, so it replaces the plain look underneath.
const EDITION_SHADER := """
shader_type spatial;
render_mode unshaded, cull_back;
uniform sampler2D atlas_a : source_color, filter_nearest_mipmap;
uniform vec2 a_off;
uniform vec2 a_scale;
uniform sampler2D atlas_b : source_color, filter_nearest_mipmap;
uniform vec2 b_off;
uniform vec2 b_scale;
uniform bool has_b = false;
uniform int mode = 0; // 1 foil, 2 holo, 3 polychrome, 4 negative
uniform float seed = 0.0;
uniform float strength = 1.0; // how strong the effect shows (the shop counter asks for more)

vec3 hue_shift(vec3 c, float h) {
	mat3 to_yiq = mat3(vec3(0.299, 0.596, 0.211), vec3(0.587, -0.274, -0.523), vec3(0.114, -0.322, 0.312));
	mat3 to_rgb = mat3(vec3(1.0, 1.0, 1.0), vec3(0.956, -0.272, -1.106), vec3(0.621, -0.647, 1.703));
	vec3 yiq = to_yiq * c;
	float hue = atan(yiq.z, yiq.y) + h;
	float chroma = length(yiq.yz);
	return to_rgb * vec3(yiq.x, chroma * cos(hue), chroma * sin(hue));
}

void fragment() {
	vec4 c = texture(atlas_a, a_off + UV * a_scale);
	if (has_b) {
		vec4 b = texture(atlas_b, b_off + UV * b_scale);
		c.rgb = mix(c.rgb, b.rgb, b.a);
		c.a = max(c.a, b.a);
	}
	if (c.a < 0.5) discard; // rounded card corners
	float t = TIME * 0.6 + seed;
	vec3 col = c.rgb;
	if (mode == 1) { // foil: cold silver-blue metal, bright bands sweeping diagonally across
		float grey = dot(col, vec3(0.299, 0.587, 0.114));
		float band = sin((UV.x * 1.2 + UV.y) * 9.0 - t * 2.0) * 0.5 + 0.5;
		col = mix(col, vec3(grey) * vec3(0.62, 0.82, 1.25), clamp(0.7 * strength, 0.0, 1.0))
				+ vec3(0.35, 0.5, 0.9) * pow(band, 4.0) * strength;
	} else if (mode == 2) { // holo: a clear pink-red tint and a fine glinting grid of red and violet sparkles
		float g = pow(max(sin(UV.x * 60.0 + t) * sin(UV.y * 46.0 - t * 1.3), 0.0), 2.0);
		float sweep = sin((UV.x - UV.y) * 6.0 + t * 1.5) * 0.5 + 0.5;
		col = mix(col, col * vec3(1.25, 0.7, 0.95), clamp(0.65 * strength, 0.0, 1.0))
				+ (vec3(1.0, 0.25, 0.55) * g * (0.35 + sweep) + vec3(0.25, 0.1, 0.55) * (1.0 - sweep) * 0.4) * strength;
	} else if (mode == 3) { // polychrome: colours drift through the rainbow, white parts shimmer too
		float phase = (UV.x + UV.y) * 0.5 + t * 0.25;
		vec3 rainbow = 0.5 + 0.5 * cos(6.2832 * (phase + vec3(0.0, 0.33, 0.67)));
		col = mix(hue_shift(col, phase * 6.2832) * 1.15, col * (0.4 + 0.85 * rainbow), clamp(0.6 * strength, 0.0, 1.0));
	} else if (mode == 4) { // negative: inverted
		col = hue_shift(vec3(1.0) - col, 3.14159) * vec3(0.85, 0.8, 1.0);
	}
	ALBEDO = col;
}
"""
static var _edition_shader: Shader
static var _edition_materials := {}
const EDITION_MODES := {"foil": 1, "holo": 2, "holographic": 2, "polychrome": 3, "negative": 4}


static func edition_material(it: Dictionary) -> ShaderMaterial:
	var ed := str(it.get("ed", "")).trim_prefix("e_")
	if not EDITION_MODES.has(ed) or it.get("db", false):
		return null
	var a = it.get("ca")
	var ap = it.get("cp")
	if a == null or not (ap is Array) or not _atlases.has(str(a)):
		return null
	var b = it.get("fa")
	var bp = it.get("fp")
	var has_b: bool = b != null and bp is Array and _atlases.has(str(b))
	var key := "%s|%s|%s|%s|%s" % [ed, a, ap, b, bp]
	if _edition_materials.has(key):
		return _edition_materials[key]
	if _edition_shader == null:
		_edition_shader = Shader.new()
		_edition_shader.code = EDITION_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = _edition_shader
	var atlas_a: Dictionary = _atlases[str(a)]
	mat.set_shader_parameter("atlas_a", atlas_a["tex"])
	mat.set_shader_parameter("a_off", _cell_offset(atlas_a, ap))
	mat.set_shader_parameter("a_scale", _cell_scale(atlas_a))
	if has_b:
		var atlas_b: Dictionary = _atlases[str(b)]
		mat.set_shader_parameter("atlas_b", atlas_b["tex"])
		mat.set_shader_parameter("b_off", _cell_offset(atlas_b, bp))
		mat.set_shader_parameter("b_scale", _cell_scale(atlas_b))
	mat.set_shader_parameter("has_b", has_b)
	mat.set_shader_parameter("mode", int(EDITION_MODES[ed]))
	mat.set_shader_parameter("seed", float(hash(key) % 100) * 0.1)
	_edition_materials[key] = mat
	return mat


static func _cell_offset(atlas: Dictionary, pos: Array) -> Vector2:
	var cell: Vector2 = atlas["cell"]
	var size: Vector2 = atlas["size"]
	return Vector2(int(pos[0]) * cell.x / size.x, int(pos[1]) * cell.y / size.y)


static func _cell_scale(atlas: Dictionary) -> Vector2:
	var cell: Vector2 = atlas["cell"]
	var size: Vector2 = atlas["size"]
	return Vector2(cell.x / size.x, cell.y / size.y)


## A played card in View Deck: washed-out grey, so the cards still in the deck stand out.
const PLAYED_SHADER := """
shader_type spatial;
render_mode unshaded, cull_back;
uniform sampler2D atlas : source_color, filter_nearest_mipmap;
uniform vec2 cell_offset;
uniform vec2 cell_scale;

void fragment() {
	vec4 tex = texture(atlas, cell_offset + UV * cell_scale);
	if (tex.a < 0.5) discard; // rounded card corners
	float l = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
	ALBEDO = mix(vec3(l), tex.rgb, 0.15) * 0.45 + vec3(0.13, 0.14, 0.16);
}
"""
static var _played_shader: Shader
static var _played_materials := {}


static func played_material(name, pos) -> ShaderMaterial:
	if name == null or not (pos is Array) or pos.size() < 2 or not _atlases.has(str(name)):
		return null
	var key := "%s|%d|%d" % [name, int(pos[0]), int(pos[1])]
	if _played_materials.has(key):
		return _played_materials[key]
	if _played_shader == null:
		_played_shader = Shader.new()
		_played_shader.code = PLAYED_SHADER
	var atlas: Dictionary = _atlases[str(name)]
	var cell: Vector2 = atlas["cell"]
	var size: Vector2 = atlas["size"]
	var mat := ShaderMaterial.new()
	mat.shader = _played_shader
	mat.set_shader_parameter("atlas", atlas["tex"])
	mat.set_shader_parameter("cell_offset", Vector2(int(pos[0]) * cell.x / size.x, int(pos[1]) * cell.y / size.y))
	mat.set_shader_parameter("cell_scale", Vector2(cell.x / size.x, cell.y / size.y))
	_played_materials[key] = mat
	return mat


## Chroma-key mode: debuffed cards must not be see-through (they would mix with the green).
static var solid_debuff := false

## Port of the game's resources/shaders/debuff.fs: reddish, desaturated and faded card with a red X
## along both diagonals (10 % wide), where the X keeps the card's full opacity.
const DEBUFF_SHADER := """
shader_type spatial;
render_mode unshaded, cull_back;
uniform sampler2D atlas : source_color, filter_nearest_mipmap;
uniform vec2 cell_offset;
uniform vec2 cell_scale;
uniform bool solid = false;

void fragment() {
	vec4 tex = texture(atlas, cell_offset + UV * cell_scale);
	if (tex.a < 0.5) discard; // rounded card corners
	vec3 c = tex.rgb * 0.8 + vec3(0.2, 0.0, 0.0);
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	float w = 0.1;
	bool on_x = abs(UV.x + UV.y - 1.0) < w || abs((1.0 - UV.x) + UV.y - 1.0) < w;
	float a = tex.a;
	if (on_x) {
		float l2 = l * 0.8;                       // HSL(hue 0 = red, saturation 0.7, lightness 0.8 l)
		float k = 0.7 * min(l2, 1.0 - l2);
		ALBEDO = vec3(l2 + k, l2 - k, l2 - k);
	} else {
		ALBEDO = mix(vec3(l), c, 0.25) * 0.7;     // saturation halved, a bit darker
		a = solid ? 1.0 : tex.a * 0.3;           // faded
	}
	ALPHA = a;
}
"""
static var _debuff_shader: Shader
static var _debuff_materials := {}


static func debuff_material(name, pos) -> ShaderMaterial:
	if name == null or not (pos is Array) or pos.size() < 2 or not _atlases.has(str(name)):
		return null
	var key := "%s|%d|%d|%s" % [name, int(pos[0]), int(pos[1]), solid_debuff]
	if _debuff_materials.has(key):
		return _debuff_materials[key]
	if _debuff_shader == null:
		_debuff_shader = Shader.new()
		_debuff_shader.code = DEBUFF_SHADER
	var atlas: Dictionary = _atlases[str(name)]
	var cell: Vector2 = atlas["cell"]
	var size: Vector2 = atlas["size"]
	var mat := ShaderMaterial.new()
	mat.shader = _debuff_shader
	mat.set_shader_parameter("atlas", atlas["tex"])
	mat.set_shader_parameter("cell_offset", Vector2(int(pos[0]) * cell.x / size.x, int(pos[1]) * cell.y / size.y))
	mat.set_shader_parameter("cell_scale", Vector2(cell.x / size.x, cell.y / size.y))
	mat.set_shader_parameter("solid", solid_debuff)
	_debuff_materials[key] = mat
	return mat


## Shows `layers` as stacked quads named Art0, Art1, ... under `parent`; extra quads are hidden.
static func apply_layers(parent: Node3D, layers: Array, size: Vector2, z_base: float, z_step := 0.0004, max_layers := 7) -> void:
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2.ONE
	for i in max_layers:
		var q: MeshInstance3D = parent.get_node_or_null("Art%d" % i)
		if i < layers.size():
			if q == null:
				q = MeshInstance3D.new()
				q.name = "Art%d" % i
				q.mesh = _quad
				parent.add_child(q)
			q.visible = true
			q.scale = Vector3(size.x, size.y, 1)
			q.position = Vector3(0, 0, z_base + z_step * i)
			q.material_override = layers[i]
		elif q != null:
			q.visible = false
