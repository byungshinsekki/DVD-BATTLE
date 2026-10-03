extends Node


const RATE: = 22050
const VOICES: = 14

var _cache: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next: int = 0
var _last: Dictionary = {}
var enabled: bool = true


func _ready() -> void :
	for i in VOICES:
		var p: = AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)


func play(snd: String, volume: float = 0.5, pitch: float = 1.0) -> void :
	if not enabled or _players.is_empty():
		return
	var now: = Time.get_ticks_msec() / 1000.0
	if now - float(_last.get(snd, -1.0)) < 0.035:
		return
	_last[snd] = now
	var master: = float(Settings.get_v("master_volume", 0.8)) if Settings else 0.8
	var sfxv: = float(Settings.get_v("sfx_volume", 0.85)) if Settings else 0.85
	var v: = volume * master * sfxv
	if v <= 0.005:
		return
	var stream: = _stream(snd)
	if stream == null:
		return
	var p: = _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = stream
	p.volume_db = linear_to_db(v)
	p.pitch_scale = clampf(pitch, 0.5, 2.0)
	p.play()


func _stream(snd: String) -> AudioStreamWAV:
	if _cache.has(snd):
		return _cache[snd]
	var s: = _synth(snd)
	_cache[snd] = s
	return s


func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data: = PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		var v: = int(clampf(samples[i], -1.0, 1.0) * 32000.0)
		data.encode_s16(i * 2, v)
	var w: = AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w


func _synth(snd: String) -> AudioStreamWAV:
	var rng: = RandomNumberGenerator.new()
	rng.seed = hash(snd)
	var out: = PackedFloat32Array()
	match snd:
		"capture":
			out = _mix([_tone(0.42, 660.0, 990.0, 0.3, 0.015, 0.38, "sine"), _tone(0.42, 990.0, 1320.0, 0.15, 0.06, 0.34, "sine")])
		"respawn":
			out = _tone(0.32, 340.0, 880.0, 0.24, 0.03, 0.28, "sine")
		"click":
			out = _tone(0.035, 1900.0, 1500.0, 0.5, 0.002, 0.03, "sine")
		"hover":
			out = _tone(0.02, 2600.0, 2600.0, 0.18, 0.001, 0.018, "sine")
		"cast":
			out = _mix([_tone(0.16, 520.0, 980.0, 0.35, 0.01, 0.14, "tri"), _tone(0.16, 1040.0, 1960.0, 0.12, 0.01, 0.14, "sine")])
		"shoot":
			out = _tone(0.09, 1300.0, 480.0, 0.35, 0.002, 0.08, "tri")
		"hit":
			out = _mix([_noise(rng, 0.05, 0.5, 0.001, 0.045, 0.35), _tone(0.06, 180.0, 90.0, 0.5, 0.001, 0.05, "sine")])
		"crit":
			out = _mix([_noise(rng, 0.09, 0.6, 0.001, 0.08, 0.6), _tone(0.14, 1500.0, 1300.0, 0.25, 0.001, 0.13, "sine"), _tone(0.08, 160.0, 70.0, 0.6, 0.001, 0.07, "sine")])
		"swing":
			out = _noise(rng, 0.16, 0.45, 0.04, 0.11, 0.12)
		"area":
			out = _mix([_noise(rng, 0.25, 0.45, 0.005, 0.24, 0.08), _tone(0.22, 120.0, 55.0, 0.6, 0.004, 0.2, "sine")])
		"boom":
			out = _mix([_noise(rng, 0.55, 0.8, 0.002, 0.53, 0.05), _tone(0.45, 90.0, 35.0, 0.8, 0.003, 0.44, "sine")])
		"death":
			out = _mix([_tone(0.6, 620.0, 110.0, 0.45, 0.005, 0.58, "tri"), _noise(rng, 0.4, 0.35, 0.005, 0.38, 0.1)])
		"heal":
			out = _mix([_tone(0.3, 880.0, 880.0, 0.25, 0.01, 0.28, "sine"), _delay(_tone(0.26, 1108.0, 1108.0, 0.22, 0.01, 0.25, "sine"), 0.06)])
		"shield":
			out = _mix([_tone(0.25, 1400.0, 1380.0, 0.22, 0.002, 0.24, "sine"), _tone(0.25, 2100.0, 2080.0, 0.12, 0.002, 0.2, "sine")])
		"cc":
			out = _mix([_tone(0.15, 420.0, 300.0, 0.45, 0.002, 0.14, "square"), _noise(rng, 0.06, 0.25, 0.001, 0.05, 0.3)])
		"broadcast":
			out = _mix([_noise(rng, 0.18, 0.18, 0.008, 0.15, 0.4), _tone(0.22, 680.0, 940.0, 0.2, 0.01, 0.18, "tri"), _delay(_tone(0.1, 1080.0, 980.0, 0.14, 0.01, 0.09, "sine"), 0.1)])
		"cage":
			out = _mix([_tone(0.32, 260.0, 130.0, 0.35, 0.003, 0.3, "tri"), _tone(0.24, 1500.0, 1490.0, 0.12, 0.002, 0.22, "sine"), _noise(rng, 0.08, 0.3, 0.002, 0.07, 0.45)])
		"intel":
			out = _mix([_tone(0.16, 1100.0, 1100.0, 0.15, 0.005, 0.15, "sine"), _delay(_tone(0.22, 1450.0, 1450.0, 0.18, 0.005, 0.21, "sine"), 0.07)])
		"blink":
			out = _mix([_tone(0.1, 700.0, 2200.0, 0.3, 0.002, 0.09, "sine"), _noise(rng, 0.1, 0.15, 0.01, 0.08, 0.5)])
		"dash":
			out = _noise(rng, 0.2, 0.5, 0.02, 0.17, 0.2)
		"coin":
			out = _mix([_tone(0.12, 1760.0, 1760.0, 0.22, 0.002, 0.1, "square"), _delay(_tone(0.18, 2350.0, 2350.0, 0.2, 0.002, 0.16, "square"), 0.06)])
		"victory":
			out = _mix([_note(523.25, 0.0, 0.5), _note(659.25, 0.12, 0.5), _note(783.99, 0.24, 0.55), _note(1046.5, 0.36, 0.8)])
		"defeat":
			out = _mix([_note(392.0, 0.0, 0.5), _note(311.13, 0.16, 0.5), _note(261.63, 0.32, 0.8)])
		"pick":
			out = _mix([_tone(0.35, 988.0, 988.0, 0.25, 0.004, 0.33, "sine"), _tone(0.35, 1976.0, 1976.0, 0.08, 0.004, 0.3, "sine")])
		"ai_pick":
			out = _mix([_tone(0.4, 659.0, 659.0, 0.22, 0.004, 0.38, "tri"), _delay(_tone(0.35, 494.0, 494.0, 0.2, 0.004, 0.33, "tri"), 0.08)])
		"start":
			out = _mix([_note(392.0, 0.0, 0.7), _note(523.25, 0.0, 0.7), _note(659.25, 0.1, 0.7), _note(783.99, 0.2, 0.8)])
		_:
			out = _tone(0.05, 800.0, 800.0, 0.2, 0.002, 0.045, "sine")
	return _wav(out)


func _env(i: int, n: int, attack: float, release: float) -> float:
	var t: = float(i) / RATE
	var total: = float(n) / RATE
	var a: = clampf(t / maxf(0.0005, attack), 0.0, 1.0)
	var r: = clampf((total - t) / maxf(0.0005, release), 0.0, 1.0)
	return a * r * r


func _tone(dur: float, f0: float, f1: float, amp: float, attack: float, release: float, wave: String) -> PackedFloat32Array:
	var n: = int(dur * RATE)
	var out: = PackedFloat32Array()
	out.resize(n)
	var ph: = 0.0
	for i in n:
		var k: = float(i) / maxf(1, n - 1)
		var f: = lerpf(f0, f1, k)
		ph += f / RATE
		var x: = fmod(ph, 1.0)
		var v: = 0.0
		match wave:
			"sine":
				v = sin(ph * TAU)
			"tri":
				v = 4.0 * absf(x - 0.5) - 1.0
			"square":
				v = 0.6 if x < 0.5 else -0.6
			_:
				v = sin(ph * TAU)
		out[i] = v * amp * _env(i, n, attack, release)
	return out


func _noise(rng: RandomNumberGenerator, dur: float, amp: float, attack: float, release: float, smooth: float) -> PackedFloat32Array:
	var n: = int(dur * RATE)
	var out: = PackedFloat32Array()
	out.resize(n)
	var y: = 0.0
	for i in n:
		y = lerpf(y, rng.randf_range(-1.0, 1.0), clampf(1.0 - smooth, 0.02, 1.0))
		out[i] = y * amp * _env(i, n, attack, release)
	return out


func _note(freq: float, start: float, dur: float) -> PackedFloat32Array:
	var body: = _mix([_tone(dur, freq, freq, 0.22, 0.01, dur * 0.8, "tri"), _tone(dur, freq * 2.0, freq * 2.0, 0.06, 0.01, dur * 0.6, "sine")])
	return _delay(body, start)


func _delay(a: PackedFloat32Array, sec: float) -> PackedFloat32Array:
	var pad: = int(sec * RATE)
	var out: = PackedFloat32Array()
	out.resize(pad + a.size())
	for i in a.size():
		out[pad + i] = a[i]
	return out


func _mix(list: Array) -> PackedFloat32Array:
	var n: = 0
	for a in list:
		n = maxi(n, (a as PackedFloat32Array).size())
	var out: = PackedFloat32Array()
	out.resize(n)
	for a in list:
		var arr: PackedFloat32Array = a
		for i in arr.size():
			out[i] += arr[i]
	return out
