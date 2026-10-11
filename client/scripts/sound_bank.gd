class_name SoundBank
extends Node3D
## Balatro's sound effects, played where they happen in the room. The mod sends each sound file
## once per connection (the game's own effects are muted on the PC while VR is connected) and an
## event every time the game plays one; `where` decides from the sound's name where it comes from.

const VOICES := 32

var _streams := {}               # sound code -> AudioStreamOggVorbis
var _players: Array[AudioStreamPlayer3D] = []
var _next := 0
var where: Callable              # Callable(code: String) -> Vector3 (world position)
var last_volume := 0.12          # volume of the last game sound (follows the game's volume setting)


func _ready() -> void:
	for i in VOICES:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 1.2
		p.max_db = 3.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.panning_strength = 1.0
		# no "far away" low-pass: in a room this small it only made coins and chips sound muffled
		p.attenuation_filter_db = 0.0
		p.bus = "Room" # through the room's reverb (set up by main.gd; silent in passthrough)
		add_child(p)
		_players.append(p)


func add_sound(data: Dictionary) -> void:
	var code := str(data.get("code", ""))
	var bytes := Marshalls.base64_to_raw(str(data.get("data", "")))
	var stream := AudioStreamOggVorbis.load_from_buffer(bytes)
	if stream != null:
		_streams[code] = stream


## True once the game has sent this sound's file.
func has_sound(code: String) -> bool:
	return _streams.has(code)


## A sound the game plays: {"code", "per" (pitch), "vol"}.
func play(ev: Dictionary) -> void:
	var code := str(ev.get("code", ""))
	var stream: AudioStream = _streams.get(code)
	if stream == null:
		return
	# a free voice only: cutting off a sound that is still playing makes an audible crack. If all
	# are busy (a big burst of scoring sounds), this one is left out – nobody hears it in the burst.
	var p: AudioStreamPlayer3D = null
	for i in _players.size():
		var candidate := _players[(_next + i) % _players.size()]
		if not candidate.playing:
			p = candidate
			_next = (_next + i + 1) % _players.size()
			break
	if p == null:
		return
	p.stream = stream
	p.pitch_scale = clampf(float(ev.get("per", 1.0)), 0.25, 4.0)
	var vol := float(ev.get("vol", 1.0))
	if vol > 0.01 and str(ev.get("code", "")).begins_with("coin") and not ev.get("own", false):
		last_volume = vol # the coin sounds' own level: the clinks match it
	p.volume_db = linear_to_db(maxf(vol, 0.001))
	if ev.get("at") is Vector3: # the client's own sounds may say where they happen
		p.global_position = ev["at"]
	else:
		p.global_position = where.call(code) if where.is_valid() else global_position
	p.play()
