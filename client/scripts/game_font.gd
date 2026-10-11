class_name GameFont
extends RefCounted
## The game's own font (m6x11plus for most languages), streamed from the running game once per
## connection – like the card textures it is never stored on disk or shipped with the client.
## Rendered as MSDF so the pixel font stays crisp at every size in VR.

static var font: FontFile


## Loads the font from a "font" message; returns false if the data was unusable.
static func load_from(data: Dictionary) -> bool:
	var bytes := Marshalls.base64_to_raw(str(data.get("data", "")))
	if bytes.is_empty():
		return false
	var f := FontFile.new()
	f.data = bytes
	f.multichannel_signed_distance_field = true # sharp pixel edges at any distance
	f.msdf_pixel_range = 8
	f.generate_mipmaps = true
	if f.get_font_name() == "":
		push_warning("Schrift '%s' konnte nicht gelesen werden" % data.get("file", "?"))
		return false
	font = f
	return true


## Uses the game font on every 3D label below `node`.
static func apply_to(node: Node) -> void:
	if font == null:
		return
	if node is Label3D:
		node.font = font
	for child in node.get_children():
		apply_to(child)
