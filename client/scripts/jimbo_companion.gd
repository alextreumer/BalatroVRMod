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
	"laugh": ["HA HA HA!", "Joke's on you!", "Hehehe!", "Unlucky!"],
	# the chatty ones (said now and then, see react's chance)
	"discard": ["Bye bye!", "Into the bin!", "Good riddance.", "Wasn't feeling those either.", "Yeet!", "Safe Travels!"],
	"last_discard": ["That was the last discard...", "No more discards. Choose wisely!"],
	"square_hole": ["It goes in the square hole!"], # (the SELL / DISCARD box)
	"sell": ["Sold! No hard feelings.", "Cha-ching!", "Farewell, old friend.", "One less mouth to feed."],
	"buy_joker": ["Ooh, a new friend!", "Welcome to the table!", "Nice pick!", "Another clown? I love it."],
	"boss": ["Uh oh... a boss.", "Here comes trouble.", "Stay sharp now!", "This one looks mean."],
	"last_hand": ["Last hand. Make it count!", "All or nothing!", "No pressure... ha.", "I can't watch!"],
	"idle": ["Take your time... I'll wait.", "Thinking hard, huh?", "Hello? Anybody there?", "*yawn*", "Psst, play something!"],
	"planet": ["To the stars!", "Level up!", "Ooh, shiny planet!"],
	"glass": ["Oops, butterfingers!", "Crash!", "That was fragile..."],
	"wheel_win": ["Lucky you!", "The wheel loves you!", "Jackpot!"],
	"wheel_nope": ["Nope!", "Haha, NOPE!", "Better luck next spin."],
	"photo": ["Say cheese!", "Get my good side!", "Smile!", "Ooh, a photo!"],
	"money": ["Look at all that money!", "We're rich!", "Big spender, huh?"],
	"broke": ["Empty pockets...", "We're broke!", "Who needs money anyway?"],
	"hand_High Card": ["A High Card? Bold.", "High Card... really?", "Living dangerously!"],
	"hand_Pair": ["A pair. Classic.", "Two of a kind!"],
	"hand_Two Pair": ["Two pairs, double fun!", "Two Pair, nice."],
	"hand_Three of a Kind": ["Three of a kind!", "Trips!"],
	"hand_Straight": ["Straight as an arrow!", "Look at that ladder!"],
	"hand_Flush": ["Flushed it!", "All one suit, fancy!"],
	"hand_Full House": ["Full House! Party time!", "The house is full!"],
	"hand_Four of a Kind": ["FOUR of a kind?!", "Quads! Wow!"],
	"hand_Straight Flush": ["A STRAIGHT FLUSH!", "I've never seen that before!"],
	"hand_Five of a Kind": ["FIVE of a kind?! Cheater!", "That's not even legal!"],
	"hand_Flush House": ["A Flush House! Amazing!"],
	"hand_Flush Five": ["FLUSH FIVE! I need to sit down."],
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
## Achievement reward "UnderTheVRadar": Jimbo wears a little VR headset.
func set_goggles(on: bool) -> void:
	if _figure == null:
		return
	var g := _figure.get_node_or_null("Goggles") as Node3D
	if on and g == null:
		g = Node3D.new()
		g.name = "Goggles"
		g.position = Vector3(0, 0.089, 0.0)
		_figure.add_child(g)
		var shell := StandardMaterial3D.new()
		shell.albedo_color = Color(0.92, 0.92, 0.95)
		shell.roughness = 0.35
		var box := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.03, 0.013, 0.011)
		box.mesh = bm
		box.position.z = 0.0155
		box.material_override = shell
		g.add_child(box)
		var visor := StandardMaterial3D.new()
		visor.albedo_color = Color(0.05, 0.05, 0.08)
		visor.metallic = 0.6
		visor.roughness = 0.1
		var front := MeshInstance3D.new()
		var fm := BoxMesh.new()
		fm.size = Vector3(0.027, 0.0105, 0.001)
		front.mesh = fm
		front.position.z = 0.0212
		front.material_override = visor
		g.add_child(front)
		var strap := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.0145
		tm.outer_radius = 0.0165
		strap.mesh = tm
		strap.material_override = visor
		g.add_child(strap)
		var light := StandardMaterial3D.new() # a little green status light
		light.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		light.albedo_color = Color(0.3, 1.6, 0.5)
		var led := MeshInstance3D.new()
		var lm := SphereMesh.new()
		lm.radius = 0.0012
		lm.height = 0.0024
		led.mesh = lm
		led.position = Vector3(0.011, 0.003, 0.0218)
		led.material_override = light
		g.add_child(led)
	if g != null:
		g.visible = on


## what: the mood / line to show; chance < 1: a chatty line that only comes now and then (and never
## over a line still showing).
func react(what: String, chance := 1.0) -> void:
	if chance < 1.0 and (randf() > chance or _bubble_time > 0.0):
		return
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
