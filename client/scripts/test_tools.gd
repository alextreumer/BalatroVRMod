class_name TestTools
extends Node3D
## Test tools (main.gd: TEST_TOOLS, in the VR menu ≡): look at things without having to meet them in
## a run.
##   Joker gallery  every joker with a 3D model on steps behind the joker board, its name underneath;
##                  every 2.5 s the sample values change (low -> mid -> high), so their live effects
##                  (filling, glowing, counting, suits ...) can be watched.
##   Boss preview   the casino as it looks against a boss blind, one boss after another.
## Positions are in the joker board's space (x right, +z towards you, y up).

const COLS := 9
const STEP := Vector3(0.14, 0.15, -0.13)   # spacing: along a row, up and back per row
const BOSSES := [ # key, name, the boss chip's colour (from the game)
	["bl_hook", "The Hook", "a84024"], ["bl_ox", "The Ox", "b95b08"], ["bl_house", "The House", "5186a8"],
	["bl_wall", "The Wall", "8a59a5"], ["bl_wheel", "The Wheel", "50bf7c"], ["bl_arm", "The Arm", "6865f3"],
	["bl_club", "The Club", "b9cb92"], ["bl_fish", "The Fish", "3e85bd"], ["bl_psychic", "The Psychic", "efc03c"],
	["bl_goad", "The Goad", "b95c96"], ["bl_water", "The Water", "c6e0eb"], ["bl_window", "The Window", "a9a295"],
	["bl_manacle", "The Manacle", "575757"], ["bl_eye", "The Eye", "4b71e4"], ["bl_mouth", "The Mouth", "ae718e"],
	["bl_plant", "The Plant", "709284"], ["bl_serpent", "The Serpent", "439a4f"], ["bl_pillar", "The Pillar", "7e6752"],
	["bl_needle", "The Needle", "5c6e31"], ["bl_head", "The Head", "ac9db4"], ["bl_tooth", "The Tooth", "b52d2d"],
	["bl_flint", "The Flint", "e56a2f"], ["bl_mark", "The Mark", "6a3847"],
	["bl_final_acorn", "Amber Acorn", "fda200"], ["bl_final_leaf", "Verdant Leaf", "56a786"],
	["bl_final_vessel", "Violet Vessel", "8a71e1"], ["bl_final_heart", "Crimson Heart", "ac3232"],
	["bl_final_bell", "Cerulean Bell", "009cfd"],
]
const SUITS := ["Hearts", "Diamonds", "Clubs", "Spades"]

var boss_index := -1                 # -1: off
var _models: Array = []              # [AugmentedJoker or Node3D, its label]
var _level := 0
var _timer := 0.0


func gallery_on() -> bool:
	return visible and not _models.is_empty()


## The joker gallery on or off (built the first time).
func set_gallery(on: bool) -> void:
	if on and _models.is_empty():
		_build()
	visible = on


func _build() -> void:
	var keys: Array = []
	var dir := DirAccess.open("res://jokers")
	if dir != null:
		for f in dir.get_files():
			var name := f.trim_suffix(".remap") # (in the exported game the scenes are remapped)
			if name.begins_with("j_") and name.ends_with(".tscn") and not keys.has(name):
				keys.append(name)
	keys.sort()
	for i in keys.size():
		var scene := load("res://jokers/" + keys[i]) as PackedScene
		if scene == null:
			continue
		var col := i % COLS
		var row := i / COLS
		var holder := Node3D.new()
		holder.position = Vector3((col - (COLS - 1) * 0.5) * STEP.x, 0.06 + row * STEP.y, -0.42 + row * STEP.z)
		add_child(holder)
		var step := MeshInstance3D.new() # a little black stand under each
		var c := CylinderMesh.new()
		c.top_radius = 0.045
		c.bottom_radius = 0.05
		c.height = 0.008
		step.mesh = c
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.08, 0.06, 0.09)
		step.material_override = m
		step.position.y = -0.004
		holder.add_child(step)
		var model := scene.instantiate()
		holder.add_child(model)
		var label := Label3D.new()
		label.text = _pretty(keys[i])
		label.font_size = 28
		label.pixel_size = 0.0004
		label.outline_size = 6
		label.modulate = Color(1.0, 0.85, 0.45)
		label.position = Vector3(0, -0.02, 0.05)
		holder.add_child(label)
		_models.append([model, label])
	GameFont.apply_to(self)
	_apply_level()


func _process(delta: float) -> void:
	if not visible or _models.is_empty():
		return
	_timer += delta
	if _timer > 2.5:
		_timer = 0.0
		_level = (_level + 1) % 3
		_apply_level()


## Sample values: low, mid, high - whatever the models read.
func _apply_level() -> void:
	var f: float = [0.1, 0.5, 1.0][_level]
	var joker := {
		"ab": {"mult": int(30 * f), "x_mult": 1.0 + 3.0 * f, "invis_rounds": int(2 * f), "loyalty_remaining": int(5 - 5 * f),
			"to_do": ["High Card", "Flush", "Full House"][_level]},
		"extra": {"chips": int(100 * f), "h_size": int(5 * f), "dollars": int(12 * f), "every": 5, "value": int(10 * f),
			"Xmult": 1.0 + 3.0 * f, "mult": int(20 * f)},
		"target": {"suit": SUITS[_level % 4], "rank": ["Ace", "King", "7"][_level]},
		"value": "+%d Mult" % int(40 * f), "sell": int(3 + 12 * f),
	}
	var state := {"round": {"discards_left": int(5 * f), "hands_left": int(4 * f), "dollars": int(30 * f), "ante": 1 + int(7 * f)}}
	for e in _models:
		if e[0].has_method("update_state"):
			e[0].update_state(joker, state)


static func _pretty(file: String) -> String:
	var k := file.trim_prefix("j_").trim_suffix(".tscn")
	var names := {"caino": "Canio", "selzer": "Seltzer", "8_ball": "8 Ball", "cloud_9": "Cloud 9", "mail": "Mail-In Rebate",
		"todo_list": "To Do List", "idol": "The Idol", "dna": "DNA", "mr_bones": "Mr. Bones", "ticket": "Golden Ticket", "smeared": "Smeared Joker"}
	if names.has(k):
		return names[k]
	return k.replace("_", " ").capitalize()


## The boss preview: the next one (wraps back to off).
func next_boss() -> void:
	boss_index += 1
	if boss_index >= BOSSES.size():
		boss_index = -1


func boss_key() -> String:
	return BOSSES[boss_index][0] if boss_index >= 0 else ""


func boss_name() -> String:
	return BOSSES[boss_index][1] if boss_index >= 0 else "Off"


func boss_colour() -> Color:
	return Color.html(BOSSES[boss_index][2]) if boss_index >= 0 else Color(1, 0.1, 0.1)
