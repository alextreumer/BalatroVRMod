class_name AugmentedJoker
extends Node3D
## Root script of every augmented joker scene (client/jokers/<joker key>.tscn, e.g. j_castle.tscn).
##
## Nothing here is joker specific: each scene says in the Inspector WHICH of its nodes react and
## to WHAT, using small expressions over the joker's live data from the game:
##   ab["mult"]  ab["x_mult"]  ab["invis_rounds"]  ab["loyalty_remaining"]  ab["to_do"]
##   extra["chips"]  extra["h_size"]  extra["every"] ...   (extra["value"] if the game stores one number)
##   target["suit"]  target["rank"]                          (Castle, Mail-In Rebate, Ancient Joker, The Idol)
##   run["discards_left"]  run["hands_left"]  run["dollars"]  run["ante"] ...   (the current round)
## Models can be replaced freely (see jokers/README.md) – only the node names used below must stay.

@export_group("Fill (scale 0..1 along Y)")
@export var fill_node: NodePath
@export var fill_source := ""
@export var fill_max := 1.0
@export var fill_min := 0.0            ## scale when the value is 0
@export var fill_uniform := false      ## scale in all directions instead of only Y

@export_group("Count (show the first N children)")
@export var count_parent: NodePath
@export var count_source := ""

@export_group("Empty state")
@export var empty_source := ""         ## counts as empty when the value is <= empty_at
@export var empty_at := 0.0
@export var show_when_empty: NodePath
@export var hide_when_empty: NodePath

@export_group("Suit colour")
@export var suit_node: NodePath
@export var suit_source := "target[\"suit\"]"
@export var suit_shapes: NodePath      ## a node with children named Hearts/Diamonds/Clubs/Spades: only the current suit is shown

@export_group("Text")
@export var label_node: NodePath
@export var label_source := ""
@export var label_format := "%s"

@export_group("Glow")
@export var glow_node: NodePath
@export var glow_source := ""          ## 0..1; empty = always glowing
@export var glow_energy := 3.0

@export_group("See-through")
@export var alpha_node: NodePath
@export var alpha_source := ""         ## 0 = invisible .. 1 = solid

@export_group("Motion")
@export var shake_node: NodePath       ## trembles (e.g. Gros Michel, which may spoil any round)
@export var spin_node: NodePath
@export var spin_speed := 0.0

## Balatro's suit colours, a little brighter so dark Spades / Clubs still read in a dim room
const SUIT_COLORS := {
	"Hearts": Color(0.95, 0.2, 0.35), "Diamonds": Color(0.96, 0.45, 0.2),
	"Clubs": Color(0.15, 0.6, 0.5), "Spades": Color(0.4, 0.33, 0.8),
}

var _inputs := {}
var _time := 0.0
var _shake_base := Vector3.ZERO


func _ready() -> void:
	_make_materials_unique(self) # scenes share materials; every joker instance needs its own
	var shaker := _node(shake_node)
	if shaker != null:
		_shake_base = shaker.rotation


func _process(delta: float) -> void:
	_time += delta
	var shaker := _node(shake_node)
	if shaker != null:
		shaker.rotation = _shake_base + Vector3(0, 0, sin(_time * 31.0) * 0.06 * (0.5 + 0.5 * sin(_time * 2.3)))
	var spinner := _node(spin_node)
	if spinner != null and spin_speed != 0.0:
		spinner.rotate_y(spin_speed * delta)
	_animate_count(delta)


## Counted parts pop away (hop up, shrink) and pop back in instead of switching on and off.
func _animate_count(delta: float) -> void:
	var counter := _node(count_parent)
	if counter == null:
		return
	for child in counter.get_children():
		if not (child is Node3D) or not child.has_meta("count_base"):
			continue
		var on: bool = child.get_meta("count_on", true)
		var t: float = child.get_meta("count_t", 1.0)
		var goal := 1.0 if on else 0.0
		if is_equal_approx(t, goal):
			continue
		t = move_toward(t, goal, delta / 0.3)
		child.set_meta("count_t", t)
		var base: Transform3D = child.get_meta("count_base")
		var s := maxf(t, 0.001)
		var hop := (1.0 - t) * 0.02 if not on else 0.0 # leaving: jumps up a little while it vanishes
		child.transform = Transform3D(base.basis.scaled(Vector3.ONE * s), base.origin + Vector3(0, hop, 0))
		if not on and t <= 0.0:
			child.visible = false


## Called by the client with this joker's data and the whole game state.
func update_state(joker: Dictionary, state: Dictionary) -> void:
	_inputs = {
		"ab": joker.get("ab", {}),
		"extra": joker.get("extra", {}),
		"target": joker.get("target", {}),
		"run": state.get("round", {}), # not "round": that is a built-in function in expressions
		"joker": joker,
		"state": state,
	}
	_apply()


func _apply() -> void:
	var fill := _node(fill_node)
	if fill != null and fill_source != "":
		var f := clampf(_num(fill_source) / maxf(fill_max, 0.0001), 0.0, 1.0)
		var s := maxf(lerpf(fill_min, 1.0, f), 0.001)
		fill.scale = Vector3.ONE * s if fill_uniform else Vector3(1, s, 1)

	var counter := _node(count_parent)
	if counter != null and count_source != "":
		var n := int(round(_num(count_source)))
		for i in counter.get_child_count():
			var child := counter.get_child(i) as Node3D
			if child == null:
				continue
			if not child.has_meta("count_base"): # first update: no animation, just the state
				child.set_meta("count_base", child.transform)
				child.set_meta("count_t", 1.0 if i < n else 0.0)
				child.visible = i < n
			child.set_meta("count_on", i < n)
			if i < n:
				child.visible = true

	if empty_source != "":
		var empty := _num(empty_source) <= empty_at
		var shown := _node(show_when_empty)
		if shown != null:
			shown.visible = empty
		var hidden := _node(hide_when_empty)
		if hidden != null:
			hidden.visible = not empty

	var suit := _node(suit_node)
	if suit != null:
		var suit_name := str(_eval(suit_source, ""))
		if SUIT_COLORS.has(suit_name):
			_tint(suit, SUIT_COLORS[suit_name])
	var shapes := _node(suit_shapes)
	if shapes != null:
		var shown := str(_eval(suit_source, ""))
		if SUIT_COLORS.has(shown):
			for child in shapes.get_children():
				child.visible = child.name == shown

	var label := _node(label_node) as Label3D
	if label != null and label_source != "":
		var value = _eval(label_source, "")
		var numeric: bool = value is int or value is float
		if label_format.count("%") == 1 and (numeric or label_format.contains("%s")):
			label.text = label_format % value
		else:
			label.text = str(value) # (a value the game hasn't set yet: no number to format)

	var glow := _node(glow_node)
	if glow != null:
		var g := 1.0 if glow_source == "" else clampf(_num(glow_source), 0.0, 1.0)
		_glow(glow, g * glow_energy)

	var see := _node(alpha_node)
	if see != null and alpha_source != "":
		_alpha(see, clampf(_num(alpha_source), 0.0, 1.0))


# ---------------------------------------------------------------- helpers

func _node(path: NodePath) -> Node3D:
	if path.is_empty():
		return null
	return get_node_or_null(path) as Node3D


func _eval(source: String, fallback = 0.0):
	if source == "":
		return fallback
	var expr := Expression.new()
	if expr.parse(source, PackedStringArray(_inputs.keys())) != OK:
		push_warning("%s: Formel '%s' ungültig: %s" % [name, source, expr.get_error_text()])
		return fallback
	var result = expr.execute(_inputs.values(), null, false)
	if expr.has_execute_failed() or result == null:
		return fallback # e.g. a value the game has not set (yet)
	return result


func _num(source: String) -> float:
	var v = _eval(source, 0.0)
	return float(v) if (v is float or v is int or v is bool) else 0.0


func _materials(node: Node) -> Array:
	var mats: Array = []
	if node is GeometryInstance3D and node.material_override is StandardMaterial3D:
		mats.append(node.material_override)
	for child in node.get_children():
		mats.append_array(_materials(child))
	return mats


func _make_materials_unique(node: Node) -> void:
	if node is GeometryInstance3D and node.material_override != null:
		node.material_override = node.material_override.duplicate()
	for child in node.get_children():
		_make_materials_unique(child)


func _tint(node: Node, colour: Color) -> void:
	for mat in _materials(node):
		mat.albedo_color = Color(colour.r, colour.g, colour.b, mat.albedo_color.a)


func _glow(node: Node, energy: float) -> void:
	for mat in _materials(node):
		mat.emission_enabled = energy > 0.01
		mat.emission = mat.albedo_color
		mat.emission_energy_multiplier = energy


func _alpha(node: Node, a: float) -> void:
	for mat in _materials(node):
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color.a = a
	if node is Label3D:
		node.modulate.a = a
	for child in node.get_children():
		if child is Label3D:
			child.modulate.a = a
