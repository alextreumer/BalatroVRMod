class_name JimboCompanion
extends Node3D
## Jimbo sits with you at the casino table (only in the virtual casino). He idles, looks at you,
## cheers when the score burns or a blind is beaten, jumps at a torn pack, slumps at Game Over and
## says a line in a speech bubble now and then.

const SCENE := "res://jokers/jimbo_companion.tscn"

var _figure: Node3D
var _bubble: Label3D
var _bubble_bg: MeshInstance3D
var _bubble_time := 0.0
var _mood := "idle"              # idle · cheer · sad · hop
var _mood_time := 0.0
var _time := 0.0
var look_at_target: Callable     # Callable() -> Vector3: where the player's head is

const LINES := {
	"cheer": ["Now THAT'S a hand!", "Ooh, it burns!", "Keep it coming!", "Ha! Beautiful!"],
	"won_blind": ["Blind beaten!", "On to the next one!", "Easy money!"],
	"pack": ["Ooh, what's inside?", "Rip it!", "Treats!"],
	"sad": ["Oh no...", "We'll get them next time.", "That hurts."],
	"win": ["We did it!!", "Champion!", "Unbelievable run!"],
	"reroll": ["Spin it!", "Again!"],
}


func _ready() -> void:
	if ResourceLoader.exists(SCENE):
		_figure = load(SCENE).instantiate()
		_figure.scale = Vector3.ONE * 2.6 # a proper little fellow sitting on the table edge
		add_child(_figure)
	_bubble_bg = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.3, 0.09)
	_bubble_bg.mesh = quad
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.97, 0.96, 0.92)
	_bubble_bg.material_override = m
	_bubble_bg.position = Vector3(0, 0.38, 0)
	_bubble_bg.visible = false
	add_child(_bubble_bg)
	_bubble = Label3D.new()
	_bubble.font_size = 40
	_bubble.pixel_size = 0.0011
	_bubble.modulate = Color(0.12, 0.12, 0.18)
	_bubble.outline_size = 0
	_bubble.position = Vector3(0, 0.38, 0.002)
	_bubble.visible = false
	add_child(_bubble)


## React to something: "cheer", "won_blind", "pack", "sad", "win", "reroll".
func react(what: String) -> void:
	match what:
		"sad":
			_mood = "sad"
		"cheer", "win", "won_blind":
			_mood = "cheer"
		_:
			_mood = "hop"
	_mood_time = 0.0
	if LINES.has(what) and (_bubble_time <= 0.0 or what in ["sad", "win"]):
		var lines: Array = LINES[what]
		say(lines[randi() % lines.size()])


func say(text: String) -> void:
	_bubble.text = text
	(_bubble_bg.mesh as QuadMesh).size = Vector2(maxf(text.length() * 0.026 + 0.04, 0.12), 0.08)
	_bubble.visible = true
	_bubble_bg.visible = true
	_bubble_time = 3.0


func _process(delta: float) -> void:
	_time += delta
	_mood_time += delta
	if _figure == null:
		return
	# turn towards the player (only around the vertical axis)
	if look_at_target.is_valid():
		var target: Vector3 = look_at_target.call()
		var to := target - global_position
		to.y = 0
		if to.length() > 0.01:
			var want := atan2(to.x, to.z) # local +z (his face) towards the player
			global_rotation.y = lerp_angle(global_rotation.y, want, 1.0 - exp(-3.0 * delta))
	var y := 0.0
	var tilt := 0.0
	var squash := 1.0
	match _mood:
		"cheer":
			y = absf(sin(_mood_time * 9.0)) * 0.05 # bouncing
			tilt = sin(_mood_time * 12.0) * 0.15
			if _mood_time > 1.6:
				_mood = "idle"
		"hop":
			y = maxf(sin(_mood_time * 6.0), 0.0) * 0.06 if _mood_time < 0.55 else 0.0
			if _mood_time > 0.8:
				_mood = "idle"
		"sad":
			tilt = 0.35 # slumped forward
			squash = 0.9
			if _mood_time > 6.0:
				_mood = "idle"
		_:
			y = sin(_time * 1.8) * 0.004 # breathing
			tilt = sin(_time * 0.7) * 0.04
	_figure.position = Vector3(0, y, 0)
	_figure.rotation = Vector3(tilt if _mood == "sad" else 0.0, 0, tilt if _mood != "sad" else 0.0)
	_figure.scale = Vector3(2.6, 2.6 * squash, 2.6)
	if _bubble_time > 0.0:
		_bubble_time -= delta
		if _bubble_time <= 0.0:
			_bubble.visible = false
			_bubble_bg.visible = false
