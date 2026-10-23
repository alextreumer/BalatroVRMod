class_name CasinoAmbience
extends Node3D
## The sound of the casino around you (only in the virtual casino): now and then a slot machine
## along the walls (a loss, a small win, now and then a big one), glasses clinking or a cocktail
## shaker at the bar, chips clicking, a dealer shuffling and dealing, a roulette ball rolling and
## dropping into its pocket, dice rattling over a table. Every sound comes from its place in the
## room and goes through the room's reverb. (No background murmur and no voices: a constant noise
## bed was more disturbing than atmospheric.)
## The bells, the reels, the glasses, the roulette, the dice and the shaker are made here (Balatro
## has no such sounds); coins, chips, cards and a crumpled ticket are the game's own sounds (the mod
## sends them when connecting - without them those parts just stay quiet).
## Positions are in the casino room's coordinates (this node is a child of it).

const RATE := 16000
const BUS := "Room"

var sounds: SoundBank              # for the game's own sounds (bus "Room" too)
var volume := 1.0                  # follows the game's sound volume (set by main.gd)
var hush := 0.0                    # 0 .. 1: the room goes quiet (the last hand)

var _clink: AudioStreamWAV
var _bell: AudioStreamWAV
var _reel: AudioStreamWAV
var _clunk: AudioStreamWAV         # the reels stopping one after the other (a loss)
var _jingle: AudioStreamWAV        # a big win: three bells going up
var _roulette: AudioStreamWAV
var _dice: AudioStreamWAV
var _shaker: AudioStreamWAV
var _oneshots: Array[AudioStreamPlayer3D] = []
var _next := 0
var _timers := {"slot": 6.0, "bar": 4.0, "chips": 9.0, "cards": 12.0, "roulette": 20.0, "dice": 28.0}
var _rng := RandomNumberGenerator.new()
var _active := false

## where things happen (casino room coordinates)
var machines: Array[Vector3] = []
var bar := Vector3(0, 1.1, 2.5)
var tables: Array[Vector3] = [Vector3(-2.7, 0.8, -3.9), Vector3(2.7, 0.8, -3.9), Vector3(-2.9, 0.8, 1.9), Vector3(2.9, 0.8, 1.9)]
## which table plays what: cards at two of them, roulette and dice at the others
const CARD_TABLES := [0, 3]
const ROULETTE_TABLE := 1
const DICE_TABLE := 2


func _ready() -> void:
	_rng.randomize()
	_clink = _make_clink()
	_bell = _make_bell()
	_reel = _make_reel()
	_clunk = _make_clunk()
	_jingle = _make_jingle()
	_roulette = _make_roulette()
	_dice = _make_dice()
	_shaker = _make_shaker()
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
			"slot": # a slot machine along the walls
				_timers[key] = _rng.randf_range(7.0, 16.0)
				if not machines.is_empty():
					var i := _rng.randi() % machines.size()
					_slot(machines[i], i, gain)
			"bar":
				_timers[key] = _rng.randf_range(5.0, 13.0)
				_bar(gain)
			"chips":
				_timers[key] = _rng.randf_range(8.0, 18.0)
				_chips(tables[_rng.randi() % tables.size()], _rng.randi_range(2, 4))
			"cards": # a dealer shuffles and deals a hand
				_timers[key] = _rng.randf_range(10.0, 22.0)
				_deal(tables[CARD_TABLES[_rng.randi() % CARD_TABLES.size()]])
			"roulette":
				_timers[key] = _rng.randf_range(24.0, 45.0)
				_spin_roulette(tables[ROULETTE_TABLE], gain)
			"dice":
				_timers[key] = _rng.randf_range(18.0, 36.0)
				var t: Vector3 = tables[DICE_TABLE]
				_play(_dice, t + Vector3(_rng.randf_range(-0.4, 0.4), 0.05, 0.0), -19.0 + gain, _rng.randf_range(0.9, 1.15))


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


## A slot machine: the reels spin, then a loss (the reels clunk to a stop, sometimes the ticket is
## crumpled), a small win (bell, a few coins) or now and then a big one (a little tune, many coins).
## Each machine has its own pitch, so they don't all sound alike.
func _slot(at: Vector3, index: int, gain: float) -> void:
	var pitch := 0.85 + float(index % 5) * 0.08
	_play(_reel, at + Vector3(0, 1.0, 0), -17.0 + gain, _rng.randf_range(0.9, 1.1))
	var roll := _rng.randf()
	if roll < 0.4: # a loss
		get_tree().create_timer(0.8).timeout.connect(func():
			_play(_clunk, at + Vector3(0, 1.0, 0), -19.0 + gain, pitch)
			if _rng.randf() < 0.35:
				get_tree().create_timer(0.9).timeout.connect(func():
					_game_sound("crumple%d" % _rng.randi_range(1, 3), at + Vector3(0.3, 1.1, 0.4), 0.18, _rng.randf_range(0.9, 1.1))))
		return
	var big := roll > 0.88
	get_tree().create_timer(0.9).timeout.connect(func():
		if big:
			_play(_jingle, at + Vector3(0, 1.4, 0), -15.0 + gain, pitch)
		else:
			_play(_bell, at + Vector3(0, 1.4, 0), -19.0 + gain, 1.25 * pitch)
		var coins := _rng.randi_range(8, 16) if big else _rng.randi_range(2, 5)
		for i in coins:
			get_tree().create_timer((0.5 if big else 0.15) + i * 0.07).timeout.connect(func():
				_game_sound("coin%d" % _rng.randi_range(1, 7), at + Vector3(0, 0.3, 0), 0.22, _rng.randf_range(0.95, 1.2))))


## At the bar: two glasses clinking (cheers), or a cocktail shaker and then the glass.
func _bar(gain: float) -> void:
	var at := bar + Vector3(_rng.randf_range(-1.2, 1.2), 0.0, -0.9)
	if _rng.randf() < 0.3:
		_play(_shaker, at, -21.0 + gain, _rng.randf_range(0.9, 1.1))
		get_tree().create_timer(2.0).timeout.connect(func(): _play(_clink, at, -23.0 + gain, _rng.randf_range(1.2, 1.4)))
		return
	_play(_clink, at, -20.0 + gain, _rng.randf_range(0.85, 1.25))
	if _rng.randf() < 0.5: # cheers: a second glass answers
		get_tree().create_timer(0.12).timeout.connect(func(): _play(_clink, at + Vector3(0.2, 0, 0), -21.0 + gain, _rng.randf_range(0.9, 1.3)))


## Chips clicking on a table (stacked, pushed, paid out).
func _chips(t: Vector3, n: int) -> void:
	for i in n:
		var code := "chips1" if _rng.randf() < 0.5 else "chips2"
		get_tree().create_timer(i * 0.11).timeout.connect(func(): _game_sound(code, t, 0.25, _rng.randf_range(1.1, 1.4)))


## A dealer shuffles (the fan of cards) and deals a few cards across the table.
func _deal(t: Vector3) -> void:
	_game_sound("cardFan2", t, 0.22, _rng.randf_range(0.95, 1.1))
	var cards := _rng.randi_range(3, 5)
	for i in cards:
		var code: String = ["cardSlide1", "cardSlide2", "card1", "card3"][_rng.randi() % 4]
		var spot := t + Vector3(_rng.randf_range(-0.5, 0.5), 0.0, _rng.randf_range(-0.3, 0.3))
		get_tree().create_timer(0.9 + i * _rng.randf_range(0.22, 0.32)).timeout.connect(func():
			_game_sound(code, spot, 0.2, _rng.randf_range(1.0, 1.25)))


## The roulette: the ball runs round, slows down, bounces and drops into a pocket; sometimes the
## croupier pays out with a few chips afterwards.
func _spin_roulette(t: Vector3, gain: float) -> void:
	_play(_roulette, t + Vector3(0, 0.05, 0), -18.0 + gain, _rng.randf_range(0.95, 1.05))
	if _rng.randf() < 0.5:
		get_tree().create_timer(5.0).timeout.connect(func(): _chips(t, _rng.randi_range(3, 5)))


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


## One of the game's own sounds (coins, chips, cards ...), if the mod has sent it.
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


## A short hard knock (dice, a roulette ball, a reel stopping): a damped tone plus a noise click.
static func _knock(out: PackedFloat32Array, at: float, freq: float, amp: float, decay: float, rng: RandomNumberGenerator) -> void:
	var start := int(at * RATE)
	var n := int(RATE * 0.08)
	for j in n:
		if start + j >= out.size():
			return
		var t := float(j) / RATE
		out[start + j] += (sin(TAU * freq * t) * 0.7 + rng.randf_range(-1.0, 1.0) * 0.5 * exp(-t * 400.0)) * amp * exp(-t * decay)


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


## A big win: three bells going up (C, E, G), the last one ringing out.
func _make_jingle() -> AudioStreamWAV:
	var n := int(RATE * 1.8)
	var out := PackedFloat32Array()
	out.resize(n)
	var notes := [[0.0, 1046.5], [0.14, 1318.5], [0.28, 1568.0], [0.42, 2093.0]]
	for i in n:
		var t := float(i) / RATE
		var s := 0.0
		for note in notes:
			var d: float = t - note[0]
			if d >= 0.0:
				var f: float = note[1]
				s += (sin(TAU * f * d) + 0.4 * sin(TAU * f * 2.0 * d)) * exp(-(3.0 if note[0] == 0.42 else 7.0) * d) * minf(d * 1500.0, 1.0)
		out[i] = s * 0.18
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


## The reels stopping one after the other: three heavy clunks.
func _make_clunk() -> AudioStreamWAV:
	var out := PackedFloat32Array()
	out.resize(int(RATE * 0.6))
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for k in 3:
		_knock(out, k * 0.16, 180.0, 0.55, 40.0, rng)
	return _wav(out, false)


## The roulette: the ball whirring round the rim (a soft rolling noise with the frets clicking,
## slower and slower), then a few bounces and the drop into its pocket.
func _make_roulette() -> AudioStreamWAV:
	var length := 4.2
	var n := int(RATE * length)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var low := 0.0
	for i in int(RATE * 3.0): # rolling: low-passed noise, fading as the ball slows
		var t := float(i) / RATE
		low += (rng.randf_range(-1.0, 1.0) - low) * 0.08
		out[i] += low * 0.5 * (1.0 - t / 3.0) * minf(t * 4.0, 1.0)
	var t := 0.1
	while t < 3.0: # the frets: clicks coming slower and slower
		_knock(out, t, 2600.0, 0.12 * (1.0 - t / 3.4), 160.0, rng)
		t += 0.05 + 0.09 * t * t / 3.0
	for b in [[3.15, 0.4], [3.38, 0.28], [3.55, 0.2], [3.66, 0.14], [3.74, 0.1]]: # bounces, then it lies still
		_knock(out, b[0], 1500.0, b[1], 70.0, rng)
	return _wav(out, false)


## Two dice thrown over the felt: a tumble of quick knocks, the gaps getting longer.
func _make_dice() -> AudioStreamWAV:
	var out := PackedFloat32Array()
	out.resize(int(RATE * 1.1))
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var t := 0.0
	var amp := 0.45
	for k in 11:
		_knock(out, t, rng.randf_range(1700.0, 2400.0), amp, 90.0, rng)
		t += rng.randf_range(0.03, 0.06) + k * 0.012
		amp *= 0.82
	return _wav(out, false)


## A cocktail shaker: ice rattling back and forth, about six strokes a second.
func _make_shaker() -> AudioStreamWAV:
	var length := 1.6
	var n := int(RATE * length)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var prev := 0.0
	for i in n:
		var t := float(i) / RATE
		var stroke := fposmod(t * 6.0, 1.0) # each stroke: the ice hits one end, then rattles
		var env := exp(-stroke * 9.0) * minf(t * 10.0, 1.0) * minf((length - t) * 5.0, 1.0)
		var noise := rng.randf_range(-1.0, 1.0)
		out[i] = (noise - prev) * 0.35 * env # (high-passed: the bright rattle of ice)
		prev = noise
	return _wav(out, false)
