class_name EventFx
extends Node2D





const INK: = Color("#060c16")
const WHITE: = Color("#f2f8ff")
const HEAL_COL: = Color("#78edba")
const SHIELD_COL: = Color("#a2dfff")
const CC_COL: = Color("#ffd77a")
const TEAM_TINT: Array[Color] = [Color("#69caff"), Color("#ff7b91")]


const FAMILIES: = {
	"swordsman": ["#80bdff", "#e5f6ff", "saber", ["triple"], ["lunge", "crescent", "swordwave", "execution"], "steel"], 
	"archer": ["#81e8b7", "#e9ffd9", "arrow", ["wind"], ["fanarrow", "ricochet", "executeArrow", "wind"], "wind"], 
	"mage": ["#b39cff", "#f2edff", "crystal", ["hourglass"], ["ice", "meteor", "flame", "blink"], "arcane"], 
	"sniper": ["#f9ce74", "#fff2c6", "bullet", ["reticle"], ["bullet", "cloak", "brand", "buckshot"], "brass"], 
	"werewolf": ["#f48799", "#ffe1dc", "claw", ["lifesteal"], ["scent", "fang", "howl", "bite"], "blood"], 
	"giant": ["#dbaf7e", "#fff1d8", "fist", ["regen", "stone"], ["quake", "regen", "boulder"], "stone"], 
	"aphrodite": ["#f8a4cf", "#ffecf8", "heart", ["aegis"], ["heart", "bed", "tether", "apple"], "petal"], 
	"blood_mage": ["#ed6e8f", "#ffd8de", "blood", ["growth"], ["bloodlink", "bloodpool", "blood", "serpent"], "blood"], 
	"fisherman": ["#78d9e2", "#dffff8", "harpoon", ["fish"], ["hook", "bait", "fish", "execution"], "water"], 
	"baseball": ["#f4a078", "#fff6dd", "bat", ["bat", "reflect"], ["baseball", "helmet", "rally"], "sport"], 
	"pirate": ["#ecc16d", "#fff3c9", "cutlass", ["dual"], ["coinbag", "grapple", "theft", "cannon"], "powder"], 
	"joker": ["#d499ff", "#fde9ff", "dagger", ["confusion"], ["knife", "swap", "flip", "banana"], "confetti"], 
	"metatron": ["#f3dc9b", "#fffbea", "feather", ["wings"], ["wings", "wing", "rescue", "landing"], "feather"], 
	"plague_doctor": ["#abdb87", "#edffd7", "needle", ["bank", "plague"], ["spore", "mist", "needle"], "spore"], 
	"hive_mind": ["#c792ef", "#f1ddff", "larva", ["neural"], ["brood", "parasite", "control", "rupture"], "organic"], 
	"nitro": ["#ff9262", "#ffedb0", "gauntlet", ["reactor", "wall"], ["bomb", "wall", "reactor"], "fire"], 
	"dimensionalist": ["#7cdaff", "#e7fbff", "prism", ["shards"], ["rift", "portal", "trajectory", "prism"], "glass"], 
	"hermes": ["#84ece4", "#e8fff6", "sickle", ["borrow", "talaria"], ["cloak", "sleep", "sickle"], "aether"], 
	"politician": ["#d6b979", "#fff1cd", "dispatch", ["contemplation", "censorship"], ["dispatch", "diversion", "propaganda"], "paper"], 
	"hades": ["#8f7cff", "#e8e2ff", "bident", ["kynee", "cerberus"], ["shade", "cleave", "harvest"], "soul"], 
	"war_machine": ["#ff8a3d", "#ffe3c2", "piston", ["fuel"], ["booster", "missile", "arc", "strip"], "fire"], 
	"torquemada": ["#e0b04a", "#fff2c9", "cross", ["faith", "ascetic"], ["pyre", "chain", "edict"], "ember"], 
	"achilles": ["#c98b3a", "#ffe8c4", "spear", ["styx"], ["pierce", "guard", "roar", "chariot"], "bronze"], 
}

const NEXUS: = {
	"world_tree": ["earth", "#76ddb0", "#eaffd9"], 
	"torturer": ["trick", "#e789ba", "#ffe5f4"], 
	"engineer": ["bullet", "#79cbed", "#e5f8ff"], 
}

const SIG_ORDER: = ["swordsman", "archer", "mage", "sniper", "werewolf", "giant", "aphrodite", "blood_mage", "fisherman", 
	"baseball", "pirate", "joker", "metatron", "plague_doctor", "hive_mind", "nitro", "dimensionalist", "hermes", 
	"world_tree", "torturer", "engineer", "politician", "hades", "war_machine", "torquemada", "achilles"]

const SUMMON_KEY: = {"snake": "blood_mage:skill:4", "brood": "hive_mind:skill:1", "parasite": "hive_mind:skill:2", 
	"turret": "engineer:skill:1", "tree": "world_tree:skill:1", "flower": "world_tree:skill:4", "bed": "aphrodite:skill:2", 
	"cerberus": "hades:passive:2", "shade": "hades:skill:1", "fuel_tank": "war_machine:passive", "chariot": "achilles:skill:4"}
const STRIKE: = ["saber", "claw", "fist", "harpoon", "bat", "cutlass", "dagger", "feather", "gauntlet", "sickle", "execution", "crescent", "bite", "swordwave", 
	"bident", "piston", "cross", "spear", "pierce"]
# V2 motifs with their own release item (see release()).
const WAVE: = ["edict", "roar"]
const SOFT: = ["wind", "regen", "aegis", "bed", "tether", "apple", "bloodlink", "helmet", "rally", "wings", "rescue", "bank", "mist", "neural", "borrow", "talaria", "shards", "brand", "theft", "scent", "fang", "cloak", "portal", "trajectory"]
const PHASED: = ["contactDash", "rescueFlight", "rescuePull", "glide"]
const C_MELEE: = ["blade", "beast", "hermes", "baseball", "trick", "pirate", "dimension"]
const C_RANGED: = ["bullet", "arrow", "fish", "love", "blood", "hive", "dimension"]

static var _reg: Dictionary = {}

var items: Array = []
var quality: int = 2
var unit_pos_cb: Callable
var extra_load: int = 0
var _ga: float = 1.0
var _budget: int = 360
var _aurora: int = 360
var _clarity: float = 1.0
var debug_p: float = -1.0






static func hash32(s: String) -> int:
	var h: = 2166136261
	for i in s.length():
		h = ((h ^ s.unicode_at(i)) * 16777619) & 4294967295
	return h



static func rnd(sd: int, i: int) -> float:
	var x: = (sd ^ ((i * 374761393) & 4294967295)) & 4294967295
	return float(((x * 668265263) & 4294967295) % 65521) / 65521.0


static func _ensure() -> void :
	if not _reg.is_empty():
		return
	for id: String in FAMILIES:
		var f: Array = FAMILIES[id]
		var entries: Array = [[id + ":basic", str(f[2]), "basic"]]
		var ps: Array = f[3]
		for i in ps.size():
			entries.append([id + ":passive" + ("" if i == 0 else ":%d" % (i + 1)), str(ps[i]), "passive"])
		var sk: Array = f[4]
		for i in sk.size():
			entries.append(["%s:skill:%d" % [id, i + 1], str(sk[i]), "ability"])
		entries.append([id + ":death", "death", "death"])
		for e: Array in entries:
			var m: = str(e[1])
			var co: = Color(str(f[0]))
			var hi: = Color(str(f[1]))
			if m == "ice":
				co = Color("#83dcff")
				hi = Color("#effeff")
			elif m == "meteor" or m == "flame":
				co = Color("#ffac6a")
				hi = Color("#fff1cd")
			elif m == "banana":
				co = Color("#fbe181")
				hi = Color("#fff8cd")
			elif m == "mist" or m == "bank":
				co = Color("#87e9b3")
				hi = Color("#efffe6")
			elif m == "arc":
				co = Color("#6fd3ff")
				hi = Color("#e6f9ff")
			elif m == "missile" or m == "strip":
				co = Color("#ff9d4a")
				hi = Color("#fff0d0")
			elif m == "harvest" or m == "shade" or m == "kynee":
				co = Color("#b4a8ff")
				hi = Color("#f1edff")
			var key: = str(e[0])
			var sd: = hash32(key)
			_reg[key] = {"key": key, "id": id, "motif": m, "kind": str(e[2]), "color": co, "bright": hi, 
				"material": str(f[5]), "family": id, "seed": sd, "variant": sd % 17, 
				"basic": str(e[2]) == "basic", "passive": str(e[2]) == "passive", "clarity": false}
	for id2: String in NEXUS:
		var nx: Array = NEXUS[id2]
		for pair: Array in [["basic", "basic"], ["passive", "passive"], ["skill:1", "ability"], ["skill:2", "ability"], ["skill:3", "ability"], ["skill:4", "ability"], ["death", "death"]]:
			var key2: = "%s:%s" % [id2, str(pair[0])]
			var sd2: = hash32(key2)
			_reg[key2] = {"key": key2, "id": id2, "motif": "", "kind": str(pair[1]), "color": Color(str(nx[1])), "bright": Color(str(nx[2])), 
				"material": "", "family": "death" if str(pair[0]) == "death" else str(nx[0]), "seed": sd2, "variant": sd2 % 17, 
				"basic": str(pair[0]) == "basic", "passive": str(pair[0]) == "passive", "clarity": true}


static func spec(key: String) -> Dictionary:
	_ensure()
	return _reg.get(key, {})


static func ability_key(a: Defs.AbilityDef) -> String:
	return "%s:skill:%d" % [a.char_id, a.slot]



static func key_for(src: BUnit, a: Defs.AbilityDef, source_type: String = "") -> String:
	if a != null:
		return ability_key(a)
	if src == null:
		return ""
	if not src.is_hero:
		return str(SUMMON_KEY.get(src.kind, ""))
	if source_type == "PASSIVE":
		return src.def.id + ":passive"
	if source_type == "SUMMON" and src.def.id == "hades":
		# V2: cerberus bites carry no ability; they read as the companion passive.
		return "hades:passive:2"
	return src.def.id + ":basic"






func _add(kind: String, s: Dictionary, life: float, data: Dictionary) -> void :
	data["k"] = kind
	data["s"] = s
	data["t"] = 0.0
	data["life"] = maxf(0.05, life)
	items.append(data)
	if items.size() > 240:
		items.pop_front()



func impact(key: String, q: Vector2, radius: float, angle: float) -> void :
	var s: = spec(key)
	if s.is_empty():
		return
	if s.clarity:
		_add("c_impact", s, 0.5, {"q": q, "r": maxf(14.0, minf(radius, 42.0)), "ang": angle})
	else:
		_add("impact", s, 0.42, {"q": q, "r": minf(30.0 if s.basic else 58.0, maxf(14.0, radius)), "ang": angle})



func release(a: Defs.AbilityDef, from: Vector2, to: Vector2, q: Vector2, radius: float, body: float, src_idx: int, gliding: bool) -> void :
	var s: = spec(ability_key(a))
	if s.is_empty():
		return
	var ang: = (to - from).angle() if to.distance_squared_to(from) > 1.0 else 0.0
	var m: = str(s.motif)
	if s.clarity:

		if a.delivery == "projectile":
			_add("c_muzzle", s, 0.4, {"a": from, "ang": ang})
		elif a.delivery == "area" or a.delivery == "self":
			_add("c_area", s, 0.4, {"q": q, "r": clampf(radius, 24.0, 180.0)})
		elif from.distance_to(to) > 75.0 and str(s.family) in C_RANGED:
			_add("c_tracer", s, 0.4, {"a": from, "b": to, "ang": ang})
		elif str(s.family) in C_MELEE:
			_add("c_slash", s, 0.4, {"q": to, "ang": ang, "r": body + 12.0})
		else:
			_add("c_impact", s, 0.4, {"q": to, "r": body + 8.0, "ang": ang})
		return
	if a.delivery == "projectile" or a.action in PHASED or m in ["lunge", "bite", "rescue", "booster"]:
		_add("flash", s, 0.36, {"a": from, "ang": ang, "r": body})
	elif m == "landing" and gliding:
		_add("lift", s, 0.36, {"a": from})
	elif m in ["tether", "bloodlink", "control", "neural", "chain"]:
		_add("tether", s, 0.36 if m != "chain" else 0.5, {"a": from, "b": to})
	elif m in WAVE:
		# V2 shockwaves: edict (its real radius) and the war roar (a wide visual wave).
		_add("wave", s, 0.75, {"idx": src_idx, "a": from, "r": radius if m == "edict" else 260.0, "body": body})
	elif m == "strip":
		# V2 genocide: a bombing run sweeping along the strip the zone covers.
		_add("strip", s, 0.6, {"a": from, "ang": ang, "len": maxf(40.0, a.range), "w": maxf(10.0, a.width)})
	elif m in SOFT or a.target == "self":

		_add("soft", s, 0.36, {"idx": src_idx, "a": from, "r": body})
	elif m == "quake":
		_add("impact", s, 0.36, {"q": q, "r": minf(110.0, radius), "ang": ang})
	elif m in STRIKE:
		_add("arc", s, 0.36, {"a": from, "b": to, "r": clampf(from.distance_to(to), 26.0, 70.0)})
	else:
		_add("impact", s, 0.36, {"q": q, "r": minf(44.0, radius if radius > 0.0 else 28.0), "ang": ang})



func strike(key: String, from: Vector2, to: Vector2) -> void :
	var s: = spec(key)
	if s.is_empty():
		return
	if s.clarity:
		_add("c_slash", s, 0.42, {"q": to, "ang": (to - from).angle(), "r": 26.0})
	else:
		_add("arc", s, 0.42, {"a": from, "b": to, "r": clampf(from.distance_to(to), 26.0, 68.0)})



func muzzle(key: String, from: Vector2, to: Vector2, body: float) -> void :
	var s: = spec(key)
	if s.is_empty():
		return
	var ang: = (to - from).angle()
	if s.clarity:
		_add("c_muzzle", s, 0.4, {"a": from, "ang": ang})
	else:
		_add("flash", s, 0.36, {"a": from, "ang": ang, "r": body})



func cone(key: String, o: Vector2, dir: Vector2, rng_: float, arc: float, team: int, bat: bool = false) -> void :
	var s: = spec(key)
	if s.is_empty():
		return
	_add("cone", s, 0.55, {"a": o, "dir": dir.normalized() if dir != Vector2.ZERO else Vector2.RIGHT, "r": rng_, "arc": arc, 
		"tint": TEAM_TINT[clampi(team, 0, 1)], "bat": bat})


func status(key: String, q: Vector2, body: float, st: String) -> void :
	var s: = spec(key)
	if not s.is_empty() and s.clarity:
		if st in ["stun", "root", "suppression", "airborne", "sleep", "control", "silence", "taunt", "imprisoned"]:
			_add("c_status", s, 0.5, {"q": q, "r": body})
		return
	_add("status", s, 0.55, {"q": q, "r": body + 5.0, "st": st, "col": s.get("color", CC_COL)})


func death(key: String, q: Vector2, body: float) -> void :
	var s: = spec(key)
	if s.is_empty():
		return
	_add("c_death" if s.clarity else "death", s, 0.82, {"q": q, "r": maxf(22.0, body + 28.0)})


func blink(key: String, a: Vector2, b: Vector2, body: float) -> void :
	var s: = spec(key)
	if s.is_empty():
		return
	_add("c_blink" if s.clarity else "blink", s, 0.55, {"a": a, "b": b, "r": body})


# V2 event helpers (battle_view._handle_event).
func cleanse(q: Vector2, body: float, col: Color) -> void :
	_add("cleanse", {"color": col}, 0.6, {"q": q, "r": body})


func block(q: Vector2, ang: float, body: float, col: Color) -> void :
	_add("block", {"color": col}, 0.4, {"q": q, "ang": ang, "r": body})


func heal(q: Vector2, body: float) -> void :
	_add("heal", {}, 0.5, {"q": q, "r": body})


func shield(q: Vector2, body: float, hit: bool) -> void :
	_add("shield", {}, 0.5, {"q": q, "r": body, "hit": hit})



func move(key: String, a: Vector2, idx: int) -> void :
	var s: = spec(key)
	if s.is_empty():
		return
	_add("move", s, 0.55, {"a": a, "idx": idx})



func sig(id: String, q: Vector2, radius: float, col: Color, slot: int, life: float) -> void :
	_add("sig", {}, life, {"id": id, "q": q, "r": minf(65.0, radius if radius > 0.0 else 30.0), "col": col, "slot": slot})


func clear_all() -> void :
	items.clear()


func step(dt: float) -> void :
	if dt > 0.0:
		var keep: Array = []
		for it in items:
			it.t += dt
			if it.t < it.life:
				keep.append(it)
		items = keep
	queue_redraw()






func _col(c: Color, a: float = 1.0) -> Color:
	return Color(c.r, c.g, c.b, clampf(a, 0.0, 1.0) * _ga)


func _ring(c: Vector2, r: float, col: Color, w: float, a: float, a0: float = 0.0, a1: float = TAU) -> void :
	if r < 0.1 or absf(a1 - a0) < 0.005:
		return
	var seg: = clampi(int(absf(a1 - a0) * sqrt(maxf(r, 1.0)) * 2.4), 6, 72)
	draw_arc(c, r, a0, a1, seg, _col(col, a), w, true)


func _line(a: Vector2, b: Vector2, col: Color, w: float, al: float) -> void :
	draw_line(a, b, _col(col, al), w, true)


func _pts(r: float, n: int, rot: float, c: Vector2 = Vector2.ZERO) -> PackedVector2Array:
	var out: = PackedVector2Array()
	for i in n:
		out.append(c + Vector2.from_angle(rot + TAU * i / n) * r)
	return out


# A small regular polygon drawn in local space. Triangulating a few-pixel
# polygon at large world coordinates (battleground maps, 7000+ px) loses
# float precision and fails ("Invalid polygon data"), so the shape is built
# around the origin and moved there with the canvas transform instead.
func _poly_at(c: Vector2, r: float, n: int, rot: float, col: Color) -> void:
	draw_set_transform(c, 0.0, Vector2.ONE)
	draw_colored_polygon(_pts(r, n, rot), col)
	_reset()


func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	var o: = pts.duplicate()
	if o.size() > 0:
		o.append(o[0])
	return o


func _glow(q: Vector2, r: float, col: Color, a: float) -> void :
	if FxSystem.soft_tex == null or r < 1.0 or quality <= 0:
		return
	draw_texture_rect(FxSystem.soft_tex, Rect2(q - Vector2(r, r), Vector2(r, r) * 2.0), false, _col(col, a))


func _reset() -> void :
	draw_set_transform_matrix(Transform2D.IDENTITY)


func _weapon(m: String, at: Vector2, rot: float, r: float, s: Dictionary) -> void :
	Motifs.draw(self, m, at, rot, r, s.color, s.bright, 0.0, _ga)


func _particle_count(base: int) -> int:
	if quality <= 0:
		return 0
	var k: = 0.7 * (0.5 if quality == 1 else 1.0)
	var n: = mini(_budget, int(round(base * k * _clarity)))
	_budget -= n
	return maxi(0, n)


func _draw() -> void :
	_budget = 360
	_aurora = 360 if quality >= 1 else 90
	_clarity = clampf(1.0 - float(items.size() + extra_load) / 220.0, 0.45, 1.0)
	for it in items:
		var p: float = clampf(it.t / it.life, 0.0, 1.0) if debug_p < 0.0 else debug_p
		var s: Dictionary = it.s
		var kind: = str(it.k)
		_ga = pow(1.0 - p, 1.35 if kind.begins_with("c_") or kind in ["heal", "shield"] else 1.25)
		match kind:
			"impact":
				_impact(s, p, float(it.r), float(it.ang), it.q)
			"arc":
				_attack_arc(it.a, it.b, s, p, float(it.r))
			"flash":
				_cast_flash(it.a, float(it.ang), s, p, float(it.r))
			"cone":
				_cone(it, s, p)
			"tether":
				_tether(it.a, it.b, s, p)
			"lift":
				_ring(it.a, 26.0 + p * 12.0, s.color, 1.5, 0.55)
			"soft":
				_soft(it, s, p)
			"status":
				_status(str(it.st), it.q, float(it.r), it.col, p)
			"death":
				_death(it.q, float(it.r), s, p)
			"blink":
				_blink(it.a, it.b, s, p)
			"heal":
				_heal(it.q, float(it.r), p)
			"shield":
				_shield(it.q, float(it.r), p, bool(it.hit))
			"move":
				_move(it, s)
			"sig":
				_sig(it, p)
			"c_impact":
				_c_burst(s, p, float(it.r), it.q, float(it.ang))
			"c_slash":
				_c_slash(it.q, float(it.ang), s, p, float(it.r))
			"c_muzzle":
				_c_muzzle(it.a, float(it.ang), s, p)
			"c_area":
				_c_area(it.q, float(it.r), s, p)
			"c_tracer":
				_line(it.a, it.b, s.color, 7.0, 0.14)
				_line(it.a, it.b, s.bright, 1.5, 0.9)
				_c_muzzle(it.a, float(it.ang), s, p)
			"c_status":
				draw_polyline(_closed(_pts(float(it.r) + 9.0 + p * 6.0, 4, PI * 0.25, it.q)), _col(CC_COL), 2.0, true)
			"c_death":
				_c_death(it.q, float(it.r), s, p)
			"c_blink":
				_c_blink(it.a, it.b, float(it.r), s, p)
			"wave":
				_wave(it, s, p)
			"strip":
				_strip(it, s, p)
			"cleanse":
				_cleanse(it.q, float(it.r), s.color, p)
			"block":
				_block(it.q, float(it.ang), float(it.r), s.color, p)
	_ga = 1.0
	_reset()



func _impact(s: Dictionary, p: float, r: float, angle: float, q: Vector2) -> void :
	var ez: = 1.0 - pow(1.0 - p, 3.0)
	var co: Color = s.color
	var hi: Color = s.bright
	var m: = str(s.motif)
	var sd: = int(s.seed)
	_glow(q, r * 0.9, co, 0.18 * (1.0 - p))
	if m in STRIKE or m in ["knife", "needle", "prism"]:
		var count: = 3 if (m == "claw" or m == "bite") else (2 if m == "execution" else 1)
		for i in count:
			var xf: = Transform2D(angle - 0.6, q)
			if m == "execution":
				xf = xf * Transform2D(i * PI * 0.5, Vector2.ZERO)
			else:
				xf = xf * Transform2D(0.0, Vector2(0, (i - (count - 1) * 0.5) * 7.0))
			draw_set_transform_matrix(xf)
			_line(Vector2( - r * 0.6 * ez, r * 0.2 * ez), Vector2(r * 0.75 * ez, - r * 0.2 * ez), co, 5.0 * (1.0 - p) + 1.0, 0.7)
			_line(Vector2( - r * 0.5 * ez, r * 0.2 * ez), Vector2(r * 0.8 * ez, - r * 0.2 * ez), hi, 1.4, 0.95)
	elif m in ["arrow", "fanarrow", "ricochet", "executeArrow", "bullet", "buckshot"]:

		draw_set_transform_matrix(Transform2D(angle, q))
		var ext: = r * (0.3 + 0.7 * ez)
		_line(Vector2( - ext, 0), Vector2(ext * 0.55, 0), co, 3.0 * (1.0 - p) + 0.5, 0.8)
		_line(Vector2( - ext * 0.65, 0), Vector2(ext * 0.6, 0), hi, 1.3, 0.95)
		for sg: float in [-1.0, 1.0]:
			_line(Vector2(0, sg * 2.0), Vector2(ext * 0.25, sg * ext * 0.32), co, 1.0, 0.7)
	elif m == "pyre":
		# V2 purification fire: tongues of flame rising around the ring.
		var ezp: = r * (0.35 + 0.65 * ez)
		_ring(q, ezp, co, 2.2 * (1.0 - p) + 0.6, 0.8)
		for i in 8:
			var a: = i * TAU / 8.0 + rnd(sd, i) * 0.3
			var base: = q + Vector2.from_angle(a) * ezp
			var tip: = base + Vector2(0, - (7.0 + rnd(sd, i + 9) * 8.0) * (1.0 - p * 0.6))
			draw_colored_polygon(PackedVector2Array([base + Vector2(-3, 0), tip, base + Vector2(3, 0)]), _col(hi if i % 2 == 0 else co, 0.85))
	elif m in ["meteor", "flame", "cannon", "bomb", "reactor", "missile"]:
		draw_set_transform_matrix(Transform2D(0.0, q))
		var ext2: = r * (0.18 + 0.78 * ez)
		var lobes: = 4 if quality <= 0 else 7
		_ring(Vector2.ZERO, ext2, co, 2.6 * (1.0 - p) + 0.5, 0.75)
		for i in lobes:
			var a: = i * TAU / lobes + rnd(sd, i) * 0.25
			var ln: = ext2 * (0.7 + rnd(sd, i + 11) * 0.35)
			if ln < 2.0:
				continue
			var petal: = Motifs.quad(Vector2(ln * 0.16, - ln * 0.09), Vector2(ln * 0.56, - ln * 0.2), Vector2(ln, 0), 6)
			petal.append_array(Motifs.quad(Vector2(ln, 0), Vector2(ln * 0.43, ln * 0.17), Vector2(ln * 0.16, ln * 0.09), 6))
			var rp: = PackedVector2Array()
			for v in petal:
				rp.append(v.rotated(a))
			draw_colored_polygon(rp, _col(co, 0.35 * (1.0 - p)))
			_line(Vector2.from_angle(a) * ln * 0.2, Vector2.from_angle(a) * ln * 0.8, hi, maxf(0.5, 2.0 * (1.0 - p)), 0.7)
		if p < 0.22:
			draw_circle(Vector2.ZERO, maxf(1.0, ext2 * 0.18), _col(hi))
	elif m == "ice":
		draw_set_transform_matrix(Transform2D(sd * 0.01, q))
		for i in 6:
			var d: = Vector2.from_angle(i * TAU / 6.0)
			_line(d * 6.0, d * maxf(6.0, r * ez), co, 2.0, 0.85)
		_reset()
		_ring(q, r * ez, hi, 1.0, 0.5)
	elif m == "heart" or m == "apple":
		_weapon(m, q, 0.0, 9.0 * (0.6 + ez * 0.65), s)
	elif m in ["quake", "boulder", "fist"]:
		draw_set_transform_matrix(Transform2D(0.0, q))
		for i in 7:
			var a2: = i * TAU / 7.0 + rnd(sd, i) * 0.2
			var rr: = r * (0.6 + rnd(sd, i + 7) * 0.4) * ez
			draw_polyline(PackedVector2Array([Vector2.from_angle(a2) * 7.0, Vector2.from_angle(a2 - 0.12) * rr * 0.65, Vector2.from_angle(a2) * rr]), _col(co, 0.7), 1.8, true)
		_ring(Vector2.ZERO, r * ez, co, 2.0, 0.7)
	elif m == "baseball":
		_ring(q, 6.0 + ez * r * 0.7, hi, 2.0, 0.9)
		draw_set_transform_matrix(Transform2D(angle, q))
		_line(Vector2(-5, 0), Vector2( - r * ez, 0), co, 2.0, 0.8)
	elif m == "banana" or str(s.material) == "confetti":
		draw_polyline(_closed(_pts(6.0 + r * ez * 0.6, 4, 0.3 + ez * 0.6, q)), _col(co), 2.0, true)
	elif str(s.material) == "blood" or m == "rupture":
		for i in 4:
			var a3: = i * TAU / 4.0 + int(s.variant)
			_weapon("blood", q + Vector2.from_angle(a3) * ez * r * 0.45, a3, 3.0 + 3.0 * (1.0 - p), s)
	else:
		_ring(q, 3.0 + r * ez * 0.8, co, 2.5 * (1.0 - p) + 0.6, 0.8)
		if p < 0.25:
			draw_circle(q, 3.5 * (1.0 - p / 0.25), _col(hi))
	_reset()
	_flecks(s, p, r * 1.1, 5 if s.basic else 11, q)



func _flecks(s: Dictionary, p: float, r: float, base: int, q: Vector2) -> void :
	var count: = _particle_count(base)
	if count <= 0:
		return
	var ez: = 1.0 - pow(1.0 - p, 2.0)
	var sd: = int(s.seed)
	var mat: = str(s.material)
	var co: Color = s.color
	var hi: Color = s.bright
	var fall: = mat == "stone" or mat == "powder"
	for i in count:
		var a: = rnd(sd, i) * TAU
		var rr: = (r * 0.25 + rnd(sd, i + 20) * r) * ez
		var at: = q + Vector2(cos(a) * rr, sin(a) * rr + (p * p * 14.0 if fall else 0.0))
		var rot: = a + p * (1.0 if i % 2 == 1 else -1.0)
		var fc: = co if i % 4 != 0 else hi
		var sz: = (1.0 - p) * (1.7 + rnd(sd, i + 40) * 2.0) + 0.4
		match mat:
			"steel", "glass", "arcane", "bronze":
				_poly_at(at, sz, 4, rot, _col(fc))
			"petal", "feather":
				draw_set_transform(at, rot + 0.3, Vector2(1.6, 0.65))
				draw_circle(Vector2.ZERO, sz, _col(fc))
				_reset()
			"blood", "spore", "organic", "soul":
				draw_circle(at, sz, _col(fc))
			"confetti":
				draw_set_transform(at, rot, Vector2.ONE)
				draw_rect(Rect2( - sz, - sz * 0.5, sz * 2.0, sz), _col(fc))
				_reset()
			"stone":
				draw_set_transform(at, 0.0, Vector2.ONE)
				var sp: = _pts(sz * 1.5, 5, float(i) + rot)
				draw_colored_polygon(sp, _col(fc))
				draw_polyline(_closed(sp), _col(hi), 0.6, true)
				_reset()
			_:
				draw_set_transform(at, rot, Vector2.ONE)
				draw_rect(Rect2( - sz * 2.0, -0.7, sz * 3.0, 1.4), _col(fc))
				_reset()



func _attack_arc(a: Vector2, b: Vector2, s: Dictionary, p: float, r: float) -> void :
	var angle: = (b - a).angle()
	var m: = str(s.motif)
	var spread: = 1.3 if m == "claw" else 1.9
	var grow: = 1.0 - pow(1.0 - p, 3.0)
	var st: = - spread * 0.6
	var en: = st + spread * grow
	if en - st > 0.03:
		draw_set_transform(a, angle, Vector2.ONE)
		var band: = PackedVector2Array()
		var n: = 12
		for i in n + 1:
			band.append(Vector2.from_angle(lerpf(st, en, float(i) / n)) * r)
		for i in n + 1:
			band.append(Vector2.from_angle(lerpf(en, st, float(i) / n)) * r * 0.65)
		draw_colored_polygon(band, _col(s.color, 0.22))
		_ring(Vector2.ZERO, r, s.bright, 2.2, 0.9, st, en)
		if m == "claw":
			for i in range(1, 3):
				_ring(Vector2.ZERO, r - i * 6.0, s.color, 1.4, 0.7, st, en)
		_reset()
	_weapon(m, a + Vector2.from_angle(angle + en) * r * 0.76, angle + en, 7.0, s)



func _cast_flash(a: Vector2, angle: float, s: Dictionary, p: float, body: float) -> void :
	draw_set_transform_matrix(Transform2D(angle, a) * Transform2D(0.0, Vector2(body + 5.0, 0)))
	if str(s.motif) in ["bullet", "buckshot", "cannon", "cutlass"]:
		var k: = 1.0 - p
		if k > 0.06:
			draw_colored_polygon(PackedVector2Array([Vector2.ZERO, Vector2(12 * k, -5), Vector2(9 * k, -1), Vector2(23 * k, 0), Vector2(9 * k, 2), Vector2(12 * k, 5)]), _col(s.bright, 0.8))
	else:
		_ring(Vector2.ZERO, 4.0 + 8.0 * p, s.color, 1.6, 0.6, -1.2, 1.2)
	_reset()


func _cone(it: Dictionary, s: Dictionary, p: float) -> void :
	var o: Vector2 = it.a
	var dir: Vector2 = it.dir
	var r: = float(it.r)
	var arc: = float(it.arc)
	var th: = dir.angle()
	var pts: = PackedVector2Array([o])
	var n: = 18
	for i in n + 1:
		pts.append(o + Vector2.from_angle(th - arc * 0.5 + arc * i / n) * r)
	draw_colored_polygon(pts, _col(s.color, 0.055))
	draw_polyline(_closed(pts), _col(it.tint as Color, 0.6), 1.2, true)
	if str(s.id) == "torturer":
		_ring(o, r * 0.75, s.color, 1.2, 0.65, th - arc * 0.5, th + arc * 0.5)
		_ring(o, r * 0.94, s.bright, 3.0, 0.65, th - arc * 0.5, th + arc * 0.5)
	elif str(s.motif) == "cleave":
		# V2 hades S2: an underworld crescent with soul wisps torn off its edge.
		var sw: = th - arc * 0.5 + arc * (1.0 - pow(1.0 - p, 2.0))
		if sw - (th - arc * 0.5) > 0.05:
			var band: = PackedVector2Array()
			for i in 13:
				band.append(o + Vector2.from_angle(lerpf(th - arc * 0.5, sw, i / 12.0)) * r * 0.98)
			for i in range(12, -1, -1):
				band.append(o + Vector2.from_angle(lerpf(th - arc * 0.5, sw, i / 12.0)) * r * 0.7)
			draw_colored_polygon(band, _col(Color("#2a2147"), 0.55))
		_ring(o, r * 0.98, s.bright, 1.6, 0.8, th - arc * 0.5, sw)
		for i in 5:
			var wa: = th - arc * 0.5 + arc * (i + 0.5) / 5.0
			var wp: = o + Vector2.from_angle(wa) * r * (0.9 + p * 0.35) + Vector2(0, - p * 14.0)
			draw_circle(wp, 2.4 * (1.0 - p) + 0.6, _col(s.bright, 0.8))
	_ring(o, r * 0.88, s.bright, 2.5, 0.9, th - arc * 0.5, th - arc * 0.5 + arc * (1.0 - pow(1.0 - p, 3.0)))
	if bool(it.bat):

		var ang: = th - arc * 0.5 + arc * p
		_weapon("bat", o + Vector2.from_angle(ang) * r * 0.68, ang, 8.0, s)


func _tether(a: Vector2, b: Vector2, s: Dictionary, p: float) -> void :
	_line(a, b, s.color, 1.7, 0.6)
	for i in 3:
		var z: = a.lerp(b, clampf(p + i * 0.2, 0.0, 1.0))
		_poly_at(z, 3.0, 4, 0.0, _col(s.bright))



func _soft(it: Dictionary, s: Dictionary, p: float) -> void :
	var at: Vector2 = it.a
	if unit_pos_cb.is_valid():
		var live: Vector2 = unit_pos_cb.call(int(it.idx))
		if live != Vector2.INF:
			at = live
	var r: = float(it.r)
	var rr0: = r + 7.0 + 6.0 * p
	var m: = str(s.motif)
	var co: Color = s.color
	match m:
		"regen", "bank", "aegis":
			for sg: float in [-1.0, 1.0]:
				var cp: = at + Vector2(sg * (r + 4.0), -5.0 - p * 9.0)
				_line(cp - Vector2(3, 0), cp + Vector2(3, 0), co, 2.0, 1.0)
				_line(cp - Vector2(0, 3), cp + Vector2(0, 3), co, 2.0, 1.0)
			_ring(at, rr0, co, 1.4, 0.7, 0.3, PI - 0.3)
		"neural":
			for i in 4:
				var a: = i * TAU / 4.0
				_ring(at, rr0, co, 1.8, 0.8, a + 0.15, a + 0.55)
		"helmet", "guard":
			draw_polyline(_closed(_pts(rr0, 6, PI / 6.0, at)), _col(co), 2.0, true)
		"shade", "harvest":
			# V2 hades: souls rising (shade call) or spiralling in (harvest).
			for i in 6:
				var a4: = i * TAU / 6.0 + (p * 1.6 if m == "harvest" else 0.0)
				var d4: = (r + 26.0) * (1.0 - p * 0.7) if m == "harvest" else rr0 + p * 10.0
				var sp4: = at + Vector2.from_angle(a4) * d4 + Vector2(0, 0.0 if m == "harvest" else - p * 16.0)
				draw_circle(sp4, 2.6 * (1.0 - p) + 1.0, _col(s.bright, 0.85))
				draw_line(sp4, sp4 + Vector2(0, 5.0), _col(co, 0.5), 1.2, true)
		"arc":
			# V2 arc protector: a hexagonal shell with arcing sparks.
			var hx: = _pts(rr0 + 2.0, 6, PI / 6.0, at)
			draw_polyline(_closed(hx), _col(s.bright), 2.0, true)
			for i in 3:
				var v0: Vector2 = hx[i * 2]
				var v1: Vector2 = hx[(i * 2 + 2) % 6]
				var mid: = v0.lerp(v1, 0.5) + (v1 - v0).orthogonal().normalized() * (4.0 * sin(p * 30.0 + i))
				draw_polyline(PackedVector2Array([v0, mid, v1]), _col(co, 0.8), 1.3, true)
		"borrow", "wings", "talaria":
			for i in 2:
				var a2: = i * TAU / 2.0 + PI * 0.25
				_ring(at, rr0 + i * 2.0, co, 1.8, 0.7, a2 + p * 0.5, a2 + p * 0.5 + 0.9)
		_:
			for i in 3:
				var a3: = i * TAU / 3.0 + PI * 0.25
				_ring(at, rr0 + i * 2.0, co, 1.8, 0.7, a3 + p * 0.5, a3 + p * 0.5 + 0.9)
	_flecks(s, p, r + 14.0, 5, at)



func _status(st: String, q: Vector2, r: float, color: Color, p: float) -> void :
	var co: = Color("#b4eaff") if st in ["invulnerable", "untargetable", "unstoppable"] else Color("#ffda89")
	match st:
		"root", "suppression", "control":
			_ring(q + Vector2(0, r * 0.32), r * 0.82, co, 1.6, 0.75)
			for sg: float in [-1.0, 1.0]:
				_line(q + Vector2(sg * r * 0.6, r * 0.5), q + Vector2(sg * r * 0.8, - r * 0.4), co, 1.4, 0.8)
		"sleep":
			var f: = DB.font_bold
			draw_string_outline(f, q + Vector2(r * 0.4 - 4.0, - r - p * 10.0 + 5.0), "z", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 3, _col(INK, 0.9))
			draw_string(f, q + Vector2(r * 0.4 - 4.0, - r - p * 10.0 + 5.0), "z", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, _col(co))
		"silence":
			_ring(q + Vector2(0, - r - 4.0), 5.0, co, 1.3, 1.0)
			_line(q + Vector2(-4, - r), q + Vector2(4, - r - 8.0), co, 1.5, 1.0)
		"stun", "airborne":
			draw_polyline(_closed(_pts(5.0, 4, 0.3, q + Vector2(0, - r - 7.0))), _col(co), 1.5, true)
		_:
			_ring(q, r + 3.0 + 6.0 * p, color, 1.3, 0.7)


func _death(q: Vector2, r: float, s: Dictionary, p: float) -> void :
	_ring(q, r * (0.7 + p * 0.5), s.color, 2.0 * (1.0 - p) + 0.6, 0.6)
	for i in 6:
		var aa: = i * TAU / 6.0 + int(s.variant) * 0.1
		var c: = q + Vector2.from_angle(aa) * r * p
		draw_polyline(_closed(_pts((1.0 - p) * r * 0.25 + 1.0, 3, aa, c)), _col(s.bright), 1.0, true)


func _blink(a: Vector2, b: Vector2, s: Dictionary, p: float) -> void :
	for at: Vector2 in [a, b]:
		draw_set_transform(at, 0.0, Vector2(0.6, 1.0))
		_ring(Vector2.ZERO, 22.0 + p * 10.0, s.color, 2.5, 0.9)
		_ring(Vector2.ZERO, 17.0 + p * 9.0, s.bright, 1.0, 0.8)
	_reset()



func _heal(q: Vector2, body: float, p: float) -> void :
	var c: = q + Vector2( - body * 0.75, - body - p * 18.0)
	_line(c - Vector2(5, 0), c + Vector2(5, 0), HEAL_COL, 2.4, 1.0)
	_line(c - Vector2(0, 5), c + Vector2(0, 5), HEAL_COL, 2.4, 1.0)
	_ring(q, body + 4.0 + p * 9.0, HEAL_COL, 1.8, 0.6, 0.1, PI - 0.1)



func _shield(q: Vector2, body: float, p: float, hit: bool) -> void :
	draw_polyline(_closed(_pts(body + 7.0 + p * 5.0, 6, PI / 6.0, q)), _col(SHIELD_COL), 3.0 if hit else 1.8, true)


func _move(it: Dictionary, s: Dictionary) -> void :
	if not unit_pos_cb.is_valid():
		return
	var live: Vector2 = unit_pos_cb.call(int(it.idx))
	if live == Vector2.INF:
		return
	_line(it.a, live, s.color, 2.0, 0.35)
	if str(s.motif) == "booster" and quality >= 1:
		# V2 war machine S1: exhaust puffs left along the dash path.
		var path: Vector2 = live - (it.a as Vector2)
		var n: = clampi(int(path.length() / 14.0), 0, 10)
		for i in n:
			var f: = (i + 0.5) / n
			var q: Vector2 = it.a + path * f + path.orthogonal().normalized() * sin(i * 2.3 + float(it.t) * 20.0) * 2.5
			draw_circle(q, (2.0 + 3.0 * f) * _ga + 0.5, _col(Color(2.0, 0.9 + 0.5 * f, 0.35), 0.6 * f))



func _sig(it: Dictionary, p: float) -> void :
	var age: = float(it.t)
	var prog: = clampf(age / 0.8, 0.0, 1.0)
	var f: = 1.0 - prog
	_ga = 1.0 if p < 0.85 else (1.0 - p) / 0.15
	var r: = float(it.r)
	var col: Color = it.col
	var q: Vector2 = it.q
	var id: = str(it.id)
	var slot: = int(it.slot)
	Motifs.signature(self, id, q, 0.0, r * (0.4 + prog * 0.5), _col(col, 0.8 * f), age)
	_ring(q, r * (0.6 + prog * 0.7), col, 1.2, 0.3 * f, 0.2, 5.7)
	if quality <= 0:
		return
	var mi: = maxi(0, SIG_ORDER.find(id))
	var count: = mini(_aurora, 6 + (3 + mi % 6) + slot * 2)
	_aurora -= count
	for i in count:
		var h: = float((((i + 1) * 107 + mi * 17) * 2654435761 & 4294967295) % 4096) / 4096.0
		var a: = TAU * h + slot * 0.6
		var rr: = r * (0.25 + prog * (0.7 + h))
		draw_set_transform(q + Vector2(cos(a), sin(a)) * rr, a + age, Vector2.ONE)
		draw_rect(Rect2(-1, -1, 2.0 + (i % 3), 1.5 + (slot % 2)), _col(col, 0.65 * f * f))
	_reset()






func _c_burst(s: Dictionary, p: float, r: float, q: Vector2, angle: float) -> void :
	var ez: = 1.0 - pow(1.0 - p, 3.0)
	var fam: = str(s.family)
	if fam in ["blade", "beast", "hermes", "trick", "dimension"]:
		_c_slash(q, angle, s, p, r)
	elif fam == "love":
		Motifs.draw(self, "heart", q, 0.0, 5.0 + ez * r * 0.4, s.color, WHITE, 0.0, _ga)
	else:
		_ring(q, 4.0 + ez * r, s.color, maxf(0.4, 2.4 - p * 1.7), 0.72)
		if p < 0.22:
			draw_circle(q, maxf(1.0, 5.0 * (1.0 - p / 0.22)), _col(s.bright))
	_c_sparks(s, p, r, q, 1.0)


func _c_slash(q: Vector2, angle: float, s: Dictionary, p: float, r: float) -> void :
	var count: = 3 if str(s.family) == "beast" else 1
	for i in count:
		draw_set_transform_matrix(Transform2D(angle - 0.8 + p * 0.55, q) * Transform2D(0.0, Vector2(0, (i - (count - 1) * 0.5) * 9.0)))
		var outer: = Motifs.quad(Vector2( - r * 0.7, - r * 0.65), Vector2(r * 1.6, - r * 0.5), Vector2(r * 0.55, r * 0.7), 10)
		var shape: = outer.duplicate()
		shape.append_array(Motifs.quad(Vector2(r * 0.55, r * 0.7), Vector2(r * 0.75, - r * 0.2), Vector2( - r * 0.7, - r * 0.65), 10))
		draw_colored_polygon(shape, _col(s.color, 0.65))
		draw_polyline(outer, _col(s.bright), 2.0, true)
	_reset()


func _c_sparks(s: Dictionary, p: float, r: float, q: Vector2, alpha: float) -> void :
	if quality <= 0:
		return
	var count: = maxi(2, int(round((4 if s.basic else 7) * _clarity * (0.6 if quality == 1 else 1.0))))
	var ez: = 1.0 - pow(1.0 - p, 2.0)
	var fam: = str(s.family)
	for i in count:
		var a: = i * 2.399 + int(s.variant) * 0.41
		var rr: = (8.0 + r * (0.65 + (i % 3) * 0.23)) * ez
		var at: = q + Vector2(cos(a), sin(a)) * rr
		var fc: Color = s.color if i % 3 != 0 else s.bright
		if fam in ["earth", "dimension", "magic"]:
			_poly_at(at, 2.2 * (1.0 - p) + 0.7, 4, a + 0.5, _col(fc, alpha))
		else:
			draw_set_transform(at, a, Vector2.ONE)
			draw_rect(Rect2(-3.0 * (1.0 - p), -0.8, 5.0 * (1.0 - p) + 0.7, 1.6), _col(fc, alpha))
			_reset()


func _c_muzzle(a: Vector2, angle: float, s: Dictionary, p: float) -> void :
	var d: = Vector2.from_angle(angle)
	_line(a + d * 18.0, a + d * (18.0 + 12.0 * (1.0 - p)), s.bright, 2.0, 0.9)


func _c_area(q: Vector2, r: float, s: Dictionary, p: float) -> void :
	_ring(q, r * (0.62 + 0.38 * (1.0 - pow(1.0 - p, 3.0))), s.color, 2.2, 0.8)
	if not s.basic:
		_c_sparks(s, p, minf(r, 50.0), q, 0.5)


func _c_death(q: Vector2, r: float, s: Dictionary, p: float) -> void :
	var ez: = 1.0 - pow(1.0 - p, 3.0)
	_ring(q, r * (0.5 + ez), s.color, 2.0 * (1.0 - p) + 0.6, 1.0)
	for i in 8:
		var a: = i * TAU / 8.0 + int(s.variant)
		var d: = r * (0.35 + ez * 1.2)
		_poly_at(q + Vector2.from_angle(a) * d, 3.5 * (1.0 - p) + 1.0, 3, a + p, _col(s.color if i % 3 != 0 else WHITE))


func _c_blink(a: Vector2, b: Vector2, body: float, s: Dictionary, p: float) -> void :
	for at: Vector2 in [a, b]:
		draw_set_transform(at, 0.0, Vector2(0.45, 1.0))
		_ring(Vector2.ZERO, body + 10.0 + p * 14.0, s.color, 3.0, 1.0)
		_ring(Vector2.ZERO, body + 10.0 + p * 14.0, WHITE, 1.0, 1.0)
	_reset()


# ------------------------------------------------------------------ V2 items

func _wave(it: Dictionary, s: Dictionary, p: float) -> void :
	var at: Vector2 = it.a
	if unit_pos_cb.is_valid():
		var live: Vector2 = unit_pos_cb.call(int(it.idx))
		if live != Vector2.INF:
			at = live
	var rr: = float(it.r)
	var body: = float(it.body)
	var roar: = str(s.motif) == "roar"
	for k in 3:
		var kp: = clampf(p * 1.25 - k * 0.14, 0.0, 1.0)
		if kp <= 0.0 or kp >= 1.0:
			continue
		var rad: = body + 6.0 + (rr - body - 6.0) * (1.0 - pow(1.0 - kp, 2.0))
		var al: = (1.0 - kp) * (0.8 - k * 0.2)
		if roar:
			# Broken sound-wave arcs.
			for j in 6:
				var a0: = j * TAU / 6.0 + k * 0.4
				_ring(at, rad, s.color if k > 0 else s.bright, 3.0 - k * 0.8, al, a0, a0 + 0.75)
		else:
			_ring(at, rad, s.bright if k == 0 else s.color, 3.2 - k * 0.9, al)
			if k == 0:
				for j in 12:
					var d: = Vector2.from_angle(j * TAU / 12.0)
					_line(at + d * (rad - 7.0), at + d * (rad + 3.0), s.bright, 1.4, al)
	_flecks(s, p, rr * 0.4, 6, at)


func _strip(it: Dictionary, s: Dictionary, p: float) -> void :
	var a: Vector2 = it.a
	var d: = Vector2.from_angle(float(it.ang))
	var n: = d.orthogonal()
	var ln: = float(it.len)
	var hw: = float(it.w) * 0.5
	var head: = ln * clampf(p * 1.6, 0.0, 1.0)
	if head > 1.0:
		var quad_pts: = PackedVector2Array([a + n * hw, a + n * hw + d * head, a - n * hw + d * head, a - n * hw])
		draw_colored_polygon(quad_pts, _col(s.color, 0.16))
		_line(a + n * hw, a + n * hw + d * head, s.bright, 1.6, 0.8)
		_line(a - n * hw, a - n * hw + d * head, s.bright, 1.6, 0.8)
	var count: = 7
	for i in count:
		var f: = (i + 0.5) / count
		if f * ln > head:
			break
		var q: = a + d * f * ln + n * (rnd(int(s.seed), i) - 0.5) * hw * 1.2
		var age: = clampf(p * 1.6 - f, 0.0, 1.0)
		_ring(q, 6.0 + age * 18.0, s.bright if i % 2 == 0 else s.color, 2.2 * (1.0 - age) + 0.4, 0.9 * (1.0 - age))
		if age < 0.3:
			draw_circle(q, 4.0 * (1.0 - age / 0.3) + 1.0, _col(s.bright))


func _cleanse(q: Vector2, r: float, col: Color, p: float) -> void :
	var ez: = 1.0 - pow(1.0 - p, 3.0)
	_glow(q, r + 18.0, col, 0.35 * (1.0 - p))
	_ring(q, r + 4.0 + ez * 16.0, col, 2.4 * (1.0 - p) + 0.6, 0.9)
	_ring(q, r + 2.0 + ez * 8.0, WHITE, 1.2, 0.7)
	# Broken shackle links flying off, then rising sparks.
	for i in 4:
		var a: = i * TAU / 4.0 + PI * 0.25
		var c: = q + Vector2.from_angle(a) * (r + 6.0 + ez * 14.0)
		draw_polyline(_closed(_pts(3.0, 4, a + p * 3.0, c)), _col(col, 0.9), 1.4, true)
	for i in 5:
		var x: = (i - 2) * r * 0.42
		var c2: = q + Vector2(x, - r * 0.4 - ez * (14.0 + (i % 2) * 8.0))
		draw_circle(c2, 1.8 * (1.0 - p) + 0.6, _col(WHITE, 0.9))


func _block(q: Vector2, ang: float, r: float, col: Color, p: float) -> void :
	var ez: = 1.0 - pow(1.0 - p, 2.0)
	_ring(q, r + 9.0 + ez * 4.0, col, 4.0 * (1.0 - p) + 1.0, 0.95, ang - 0.7, ang + 0.7)
	_ring(q, r + 9.0 + ez * 4.0, WHITE, 1.4, 0.9, ang - 0.45, ang + 0.45)
	var hit: = q + Vector2.from_angle(ang) * (r + 11.0)
	for i in 6:
		var a: = ang + (i - 2.5) * 0.35
		_line(hit + Vector2.from_angle(a) * 3.0, hit + Vector2.from_angle(a) * (6.0 + ez * 14.0), WHITE if i % 2 == 0 else col, 1.6, 0.9)
