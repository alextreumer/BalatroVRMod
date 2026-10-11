class_name CasinoAmbience
extends Node3D
## The sound of the casino around you (only in the virtual casino): now and then a slot machine
## paying out along the walls, glasses clinking at the bar and chips clicking at the tables. Every
## sound comes from its place in the room and goes through the room's reverb. (No background
## murmur: a constant noise bed was more disturbing than atmospheric.)
## The bells, the reels and the glasses are made here (Balatro has no such sounds); the payout
## coins and the chips are the game's own sounds (the mod sends them when connecting).
## Positions are in the casino room's coordinates (this node is a child of it).

const RATE := 16000
const BUS := "Room"

var sounds: SoundBank              # for the game's coin / chip sounds (bus "Room" too)
var volume := 1.0                  # follows the game's sound volume (set by main.gd)
var hush := 0.0                    # 0 .. 1: the room goes quiet (the last hand)

var _clink: AudioStreamWAV
var _bell: AudioStreamWAV
var _reel: AudioStreamWAV
var _oneshots: Array[AudioStreamPlayer3D] = []
var _next := 0
var _timers := {"slot": 6.0, "glass": 4.0, "chips": 9.0}
var _rng := RandomNumberGenerator.new()
var _active := false

## where things happen (casino room coordinates)
var machines: Array[Vector3] = []
var bar := Vector3(0, 1.1, 2.5)
var tables: Array[Vector3] = [Vector3(-2.7, 0.8, -3.9), Vector3(2.7, 0.8, -3.9), Vector3(-2.9, 0.8, 1.9), Vector3(2.9, 0.8, 1.9)]


func _ready() -> void:
	_rng.randomize()
	_clink = _make_clink()
	_bell = _make_bell()
	_reel = _make_reel()
	for i in 24: # (enough for a jackpot: every machine rings at once)
		_oneshots.append(_player())


func _player() -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.bus = BUS
	p.attenuation_filter_db = 0.0
	p.unit_size = 1.5
	p.max_db = 0.0
	add_child(p)
	return p


## On in the virtual casino, off in passthrough / green.
func set_active(on: bool) -> void:
	if on == _active:
		return
	_active = on


func _process(delta: float) -> void:
	if not _active:
		return
	var gain := linear_to_db(maxf(volume * (1.0 - 0.85 * hush), 0.0001))
	for key in _timers.keys():
		_timers[key] = float(_timers[key]) - delta
		if _timers[key] > 0.0:
			continue
		match key:
			"slot": # a slot machine along the walls: reels rattle, a bell, a cascade of coins
				_timers[key] = _rng.randf_range(7.0, 16.0)
				if not machines.is_empty():
					_slot_payout(machines[_rng.randi() % machines.size()], gain)
			"glass":
				_timers[key] = _rng.randf_range(5.0, 13.0)
				var at := bar + Vector3(_rng.randf_range(-1.2, 1.2), 0.0, -0.9)
				_play(_clink, at, -20.0 + gain, _rng.randf_range(0.85, 1.25))
				if _rng.randf() < 0.5: # cheers: a second glass answers
					get_tree().create_timer(0.12).timeout.connect(func(): _play(_clink, at + Vector3(0.2, 0, 0), -21.0 + gain, _rng.randf_range(0.9, 1.3)))
			"chips":
				_timers[key] = _rng.randf_range(8.0, 18.0)
				var t: Vector3 = tables[_rng.randi() % tables.size()]
				for i in _rng.randi_range(2, 4):
					var code := "chips1" if _rng.randf() < 0.5 else "chips2"
					get_tree().create_timer(i * 0.11).timeout.connect(func(): _game_sound(code, t, 0.25, _rng.randf_range(1.1, 1.4)))


## The run is won: all machines pay out at once, bells and coins from every wall.
func jackpot() -> void:
	if not _active:
		return
	var gain := linear_to_db(maxf(volume, 0.0001))
	for i in machines.size():
		var at: Vector3 = machines[i]
		get_tree().create_timer(i * 0.25 + _rng.randf_range(0.0, 0.2)).timeout.connect(func():
			_play(_bell, at + Vector3(0, 1.4, 0), -13.0 + gain, _rng.randf_range(0.95, 1.3))
			for c in 6:
				get_tree().create_timer(0.1 + c * 0.08).timeout.connect(func():
					_game_sound("coin%d" % _rng.randi_range(1, 7), at + Vector3(0, 0.3, 0), 0.3, _rng.randf_range(0.95, 1.25))))


func _slot_payout(at: Vector3, gain: float) -> void:
	_play(_reel, at + Vector3(0, 1.0, 0), -17.0 + gain, 1.0)
	var big := _rng.randf() < 0.25
	get_tree().create_timer(0.9).timeout.connect(func():
		_play(_bell, at + Vector3(0, 1.4, 0), (-15.0 if big else -19.0) + gain, 1.0 if big else 1.25)
		var coins := _rng.randi_range(6, 14) if big else _rng.randi_range(2, 5)
		for i in coins:
			get_tree().create_timer(0.15 + i * 0.07).timeout.connect(func():
				_game_sound("coin%d" % _rng.randi_range(1, 7), at + Vector3(0, 0.3, 0), 0.22, _rng.randf_range(0.95, 1.2))))


func _play(stream: AudioStream, at: Vector3, db: float, pitch: float) -> void:
	var p := _oneshots[_next]
	_next = (_next + 1) % _oneshots.size()
	if p.playing:
		return # never cut a sound off (it would crack)
	p.stream = stream
	p.position = at
	p.volume_db = db
	p.pitch_scale = pitch
	p.play()


## One of the game's own sounds (coins, chips), if the mod has sent it.
func _game_sound(code: String, at: Vector3, vol: float, pitch: float) -> void:
	if sounds == null or not sounds.has_sound(code):
		return
	_play(sounds._streams[code], at, linear_to_db(vol) + linear_to_db(maxf(volume * (1.0 - 0.85 * hush), 0.0001)) - 6.0, pitch)


# ---------------------------------------------------------------- sounds made from scratch

static func _wav(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w


## Two glasses touching: a few high, slightly detuned partials ringing out.
func _make_clink() -> AudioStreamWAV:
	var n := int(RATE * 0.9)
	var out := PackedFloat32Array()
	out.resize(n)
	var partials := [[2350.0, 1.0, 9.0], [3720.0, 0.5, 13.0], [5150.0, 0.3, 18.0], [2385.0, 0.6, 8.0]]
	for i in n:
		var t := float(i) / RATE
		var s := 0.0
		for p in partials:
			s += sin(TAU * p[0] * t) * p[1] * exp(-p[2] * t)
		out[i] = s * 0.25 * minf(t * 2000.0, 1.0)
	return _wav(out, false)


## A slot machine's win bell: a bright ding with an octave above it.
func _make_bell() -> AudioStreamWAV:
	var n := int(RATE * 1.4)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var s := sin(TAU * 1320.0 * t) * exp(-3.0 * t) + 0.5 * sin(TAU * 2640.0 * t) * exp(-4.5 * t) \
				+ 0.3 * sin(TAU * 3960.0 * t) * exp(-6.0 * t)
		out[i] = s * 0.3 * minf(t * 1500.0, 1.0)
	return _wav(out, false)


## Spinning reels: a fast rattle of clicks that slows down.
func _make_reel() -> AudioStreamWAV:
	var n := int(RATE * 0.85)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var t := 0.0
	while t < 0.85:
		var start := int(t * RATE)
		for j in 120: # one click: a short decaying noise burst
			if start + j < n:
				out[start + j] += rng.randf_range(-1.0, 1.0) * exp(-j / 18.0) * 0.35
		t += 0.022 + t * t * 0.09 # the clicks come slower and slower
	return _wav(out, false)
