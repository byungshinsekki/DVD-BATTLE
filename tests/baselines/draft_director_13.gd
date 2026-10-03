class_name LegacyDraftDirector14
extends RefCounted





const VERSION: = "GD-DRAFT-1.3"
const SHIFT: = 1 << 32
const HARD_CC: = ["stun", "root", "airborne", "suppression", "charm", "sleep", "silence", "control", "taunt"]

var ids: Array = []
var index: Dictionary = {}
var feats: Array = []
var n: int = 0
var matrix: = PackedFloat32Array()
var pairs: = PackedFloat32Array()
var team_power: = PackedFloat32Array()
var mapf: Dictionary = {}
var arena_name: String = ""
var team_size: int = 1
var arena_id: String = "classic"
var ruleset: String = "elimination"
var seed_value: int = 1
var user_history: Dictionary = {}
var budget: int = 45000

var _q_cache: Dictionary = {}
var _v_cache: Dictionary = {}
var _f_cache: Dictionary = {}
var _members_cache: Dictionary = {}
var evals: int = 0
var nodes: int = 0
var last_decision: Dictionary = {}


func _init(options: Dictionary = {}) -> void :
	DB.ensure_loaded()
	team_size = clampi(int(options.get("team_size", 1)), 1, 5)
	arena_id = str(options.get("arena_id", "classic"))
	ruleset = str(options.get("ruleset", DB.arena(arena_id).ruleset))
	seed_value = int(options.get("seed", 1))
	user_history = options.get("user_history", {})
	budget = int(options.get("budget", 45000))
	_prepare()






static func _flatten(effects: Array, out: Array) -> void :
	for e in effects:
		if not (e is Dictionary):
			continue
		out.append(e)
		if e.has("effects"):
			_flatten(e.effects, out)
		if e.has("damageEffect") and e.damageEffect is Dictionary:
			_flatten([e.damageEffect], out)
		if e.has("attack") and e.attack is Dictionary:
			_flatten([e.attack], out)
		if e.has("originPayload") and e.originPayload is Array:
			_flatten(e.originPayload, out)


static func _weighted(effects: Array, weight: float, rows: Array, inherited: String) -> void :
	for e in effects:
		if not (e is Dictionary):
			continue
		var filter: = str(e.get("filter", inherited))
		rows.append({"e": e, "w": weight, "filter": filter})
		var max_t: = float(e.get("maxTriggers", 1000000000.0))
		var ticks: = maxf(1.0, minf(max_t, floorf(float(e.get("duration", 1.0)) / maxf(0.25, float(e.get("interval", 1.0))))))
		var ty: = str(e.get("type", ""))
		if e.has("effects"):
			_weighted(e.effects, weight * (ticks * 0.55 if ty == "zone" else 1.0), rows, filter)
		if e.has("damageEffect") and e.damageEffect is Dictionary:
			_weighted([e.damageEffect], weight * (ticks if ty == "dot" else 1.0), rows, filter)
		if e.has("originPayload") and e.originPayload is Array:
			_weighted(e.originPayload, weight, rows, "")


static func kit_features(d: Defs.CharDef) -> Dictionary:
	var hp: = d.stat("maxHealth")
	var ad: = d.stat("attackDamage")
	var ap: = d.stat("abilityPower")
	var basic: = ad * maxf(0.1, d.stat("attackSpeed")) * (1.0 + d.stat("critChance") * (maxf(1.0, d.stat("critMultiplier")) - 1.0))
	if d.has_rule("no_basic"):
		basic = 0.0
	var spell: = 0.0
	var magic: = 0.0
	var hard: = 0.0
	var aoe: = 0.0
	var heal: = 0.0
	var ally_heal: = 0.0
	var shield: = 0.0
	var ally_shield: = 0.0
	var ally_guard: = 0.0
	var mobility: = 0.0
	var projectile: = 0.0
	var self_invuln: = false
	var ally_only: = 0
	var types: Dictionary = {}
	var support_reach: = 1.0
	var support_interval: = 30.0
	for ab in d.abilities:
		var a: Defs.AbilityDef = ab
		var es: Array = []
		_flatten(a.effects, es)
		for e in es:
			types[str(e.get("type", ""))] = true
		var cd: = maxf(0.25, a.cooldown)
		var gate: = 0.55 if not a.condition.is_empty() else (0.7 if a.action in ["detonate", "upgrade", "rootGarden", "thornGarden"] else 1.0)
		var other_ally: = bool(a.flag("originOtherAlly", false))
		var supports: = a.target in ["ally", "position_ally", "ally_area"] or other_ally
		if supports:
			support_reach = maxf(support_reach, a.range + a.radius)
			support_interval = minf(support_interval, cd)
		if other_ally:
			ally_only += 1
		var damage: = 0.0
		var rows: Array = []
		_weighted(a.effects, 1.0, rows, "")
		for row in rows:
			var e: Dictionary = row.e
			var w: float = row.w
			var filter: String = row.filter
			var ty: = str(e.get("type", ""))
			match ty:
				"damage":
					var amount: = (float(e.get("base", 0.0)) + float(e.get("ad", 0.0)) * ad + float(e.get("ap", 0.0)) * ap + float(e.get("targetMaxHp", 0.0)) * 1100.0 + float(e.get("selfMaxHp", 0.0)) * hp) * w
					damage += amount
					if str(e.get("school", "")) == "magic":
						magic += amount * gate / cd
					heal += amount * float(e.get("sourceHealRatio", 0.0)) * gate / cd
				"heal":
					if filter != "both" and filter != "enemy":
						var h: = (float(e.get("base", 0.0)) + float(e.get("ap", 0.0)) * ap) * gate * w / cd
						if not other_ally:
							heal += h
						if supports or filter == "ally" or str(e.get("applyTo", "")) == "ally_area":
							ally_heal += h
				"shield":
					if filter != "both" and filter != "enemy":
						var h2: = (float(e.get("base", 0.0)) + float(e.get("ap", 0.0)) * ap) * gate * w / cd
						if not other_ally:
							shield += h2
						if supports or filter == "ally" or str(e.get("applyTo", "")) == "ally_area":
							ally_shield += h2
				"buff":
					if str(e.get("stat", "")) == "regen":
						heal += float(e.get("amount", 0.0)) * float(e.get("duration", 0.0)) / cd
				"status":
					var s: = str(e.get("status", ""))
					if s == "invulnerable":
						if supports:
							ally_guard += 0.35
						if not other_ally:
							self_invuln = true
					if s in HARD_CC:
						hard += minf(2.0, float(e.get("duration", 0.7)) + float(e.get("originThenStun", 0.0))) * gate / cd
				"heal_bank":
					heal += 0.0
				"displace":
					if not supports:
						hard += 0.35 * gate / cd
				"move_self", "blink", "dash":
					mobility += 0.4
		if a.delivery == "projectile":
			projectile += 1.0
		if a.delivery in ["dash", "blink"] or a.action in ["contactDash", "wallRun", "rescueFlight", "portalPair", "cloak"]:
			mobility += 0.4
		var area: = a.delivery in ["area", "cone", "line"] or types.has("zone") or a.pierce > 0
		if area and damage > 0.0:
			aoe += gate * 0.3
		spell += damage * gate / cd
	if d.has_rule("damage_heal"):
		heal += basic * 0.16
	if d.has_rule("regen"):
		heal += float(d.rule("regen").get("perSecond", 0.0))
	if d.has_rule("orbit_aura"):
		heal += 8.0
		ally_heal += 8.0
		spell += 12.0
		aoe += 0.25
	if d.has_rule("nexus_seed_path"):
		heal += 35.0
		ally_heal += 35.0
	if d.id == "politician":
		ally_guard += 0.55
		hard += 0.1
		ally_only = 3
		support_reach = 440.0
	if d.id == "torturer":
		# Pain contributes sustained pressure; prison contributes control.
		spell += 6.0
		hard += 0.1
	var summons: = types.has("summon") or d.tags.has("SUMMONER")
	if summons:
		spell += {"engineer": 23.0, "hive_mind": 16.0, "blood_mage": 12.0}.get(d.id, 0.0)
	var durability: = hp * (1.0 + (d.stat("armor") + d.stat("magicResistance")) / 200.0) / 1400.0
	var healing: = clampf(heal / 22.0, 0.0, 2.0)
	var shielding: = clampf(shield / 14.0, 0.0, 1.5)
	var protection: = clampf(shielding + (0.45 if self_invuln else 0.0) + (0.35 if types.has("projectile_guard") else 0.0), 0.0, 1.7)
	var projectile_answer: = types.has("projectile_guard") or d.has_rule("projectile_reflect_arc") or d.has_rule("projectile_reflect") or d.has_rule("projectile_nullify")
	var anti_heal: = d.has_rule("plague_heal_reduction") or types.has("heal_reduction")
	var rng_: = d.stat("attackRange")
	var ms: = d.stat("moveSpeed")
	var movement: = clampf(mobility + maxf(0.0, ms - 90.0) / 90.0, 0.0, 1.5)
	var ranged: = rng_ >= 120.0
	var melee: = rng_ < 90.0
	return {
		"id": d.id, "range": rng_, "durability": durability, "healing": healing, "shielding": shielding, "protection": protection, 
		"move_speed": ms, "preferred_range": d.preferred_range, "support_reach": support_reach, "support_interval": support_interval, 
		"max_health": hp, "raw_damage": basic + spell, "ally_only": float(ally_only) / maxf(1.0, d.abilities.size()), 
		"ally_healing": clampf(ally_heal / 22.0, 0.0, 2.0), 
		"ally_protection": clampf(ally_shield / 14.0 + ally_guard + (0.3 if d.id == "dimensionalist" else 0.0), 0.0, 1.7), 
		"damage": clampf((basic + spell) / 85.0, 0.2, 2.0), "magic": clampf(magic / maxf(1.0, basic + spell), 0.0, 1.0), 
		"control": clampf(hard * 5.0 + (0.45 if d.has_rule("cone_basic") else 0.0), 0.0, 1.5), 
		"area": clampf(aoe, 0.0, 1.5), "mobility": movement, 
		"projectile": clampf(projectile / maxf(1.0, d.abilities.size()) + (0.4 if rng_ >= 120.0 else 0.0), 0.0, 1.0), 
		"projectile_answer": 1.0 if projectile_answer else 0.0, "anti_heal": 1.0 if anti_heal else 0.0, 
		"summon": 1.0 if summons else 0.0, "ranged": ranged, "melee": melee, 
		"burst": clampf(spell / 30.0, 0.0, 1.5), "execute": 1.0 if types.has("execute") or d.id == "archer" else 0.0, 
		"disengage": movement * (1.0 if ranged else 0.3), "wall": 1.0 if d.has_rule("wall_mastery") or d.id in ["baseball", "engineer"] else (0.5 if d.id == "archer" else 0.0), 
		"stationary": 1.0 if d.id in ["world_tree", "engineer", "hive_mind", "politician"] else 0.0, 
		"portal": 1.0 if d.id == "dimensionalist" else 0.0, 
		"dive": movement * (1.0 if rng_ < 100.0 else 0.35), 
		"fragile": maxf(0.0, 1.0 - durability), 
	}


static func map_features(arena: Arena) -> Dictionary:
	var area: = maxf(1.0, (arena.max_x - arena.min_x) * (arena.max_y - arena.min_y))
	var occupied: = 0.0
	var blockers: = 0
	for i in arena.obs_count:
		occupied += PI * arena.obs_r[i] * arena.obs_r[i] if arena.obs_circle[i] == 1 else arena.obs_w[i] * arena.obs_h[i]
		if (arena.obs_mask[i] & Arena.MASK_VISION) != 0:
			blockers += 1
	var harmful: = 0
	var wind: = 0.0
	var portals: = 0.0
	for h in arena.hazards:
		if float(h.get("damage", 0.0)) > 0.0:
			harmful += 1
		if str(h.get("type", "")) == "wind":
			wind = 1.0
		if str(h.get("type", "")) == "portal":
			portals = 1.0
	return {"id": arena.id, "name": arena.name, "walls": clampf(arena.obs_count / 9.0 + occupied / area * 2.0, 0.0, 1.0), 
		"sight": clampf(blockers / 8.0, 0.0, 1.0), "hazard": clampf(harmful / 4.0, 0.0, 1.0), "wind": wind, "portals": portals, "control": 1.0 if arena.ruleset == "control" else 0.0}


static func map_fit(f: Dictionary, m: Dictionary) -> float:
	return float(m.walls) * (0.22 * float(f.wall) + 0.1 * float(f.area) + 0.06 * float(f.stationary) - 0.13 * float(f.projectile))\
	+ (1.0 - float(m.sight)) * 0.09 * minf(1.0, float(f.range) / 240.0)\
	+ float(m.hazard) * (0.09 * float(f.mobility) + 0.06 * float(f.healing) - 0.12 * float(f.stationary))\
	+ float(m.portals) * (0.22 * float(f.portal) + 0.07 * float(f.dive)) + float(m.wind) * 0.04 * float(f.durability)\
	+ float(m.get("control", 0.0)) * (0.12 * float(f.mobility) + 0.10 * float(f.durability) + 0.06 * float(f.healing) + 0.07 * float(f.control) + 0.06 * float(f.ally_protection) + 0.04 * float(f.ally_healing) - 0.05 * float(f.fragile))


static func directed_counter(a: Dictionary, b: Dictionary) -> float:
	return 0.32 * float(a.anti_heal) * float(b.healing) + 0.25 * float(a.projectile_answer) * float(b.projectile)\
	+ 0.15 * float(a.area) * float(b.summon) + 0.09 * float(a.control) * float(b.mobility)\
	+ 0.13 * float(a.dive) * (1.0 if b.ranged else 0.0) * (1.0 + float(b.fragile))\
	+ 0.08 * float(a.disengage) * (1.0 if b.melee else 0.0)\
	+ 0.08 * float(a.protection) * float(b.burst) + 0.07 * float(a.execute) * float(b.healing)


static func _power(f: Dictionary) -> float:
	return log(maxf(0.1, float(f.damage) * float(f.durability))) * 0.24 + float(f.healing) * 0.09 + float(f.control) * 0.07


static func mechanics_matchup(a: Dictionary, b: Dictionary, m: Dictionary) -> float:
	return clampf(_power(a) - _power(b) + directed_counter(a, b) - directed_counter(b, a) + map_fit(a, m) - map_fit(b, m), -1.0, 1.0)


static func support_delivery(a: Dictionary, b: Dictionary) -> float:
	var drift: = maxf(0.0, float(b.move_speed) - float(a.move_speed)) * float(a.support_interval) if float(a.stationary) > 0.0 and b.melee else 0.0
	return float(a.support_reach) / (float(a.support_reach) + drift + absf(float(a.preferred_range) - float(b.preferred_range)))


static func pair_synergy(a: Dictionary, b: Dictionary) -> float:
	var v: = 0.09 * (float(a.ally_protection) * float(b.damage) + float(b.ally_protection) * float(a.damage))\
	+ 0.08 * (float(a.ally_healing) * float(b.durability) * support_delivery(a, b) + float(b.ally_healing) * float(a.durability) * support_delivery(b, a))\
	+ 0.09 * (float(a.control) * float(b.burst) + float(b.control) * float(a.burst))\
	+ 0.1 * minf(float(a.dive), float(b.dive)) + 0.09 * minf(float(a.stationary), float(b.stationary))\
	+ 0.05 * (float(a.portal) * (1.0 if b.melee else 0.0) + float(b.portal) * (1.0 if a.melee else 0.0))
	v -= 0.09 * maxf(0.0, float(a.ally_healing) + float(b.ally_healing) - 2.2)
	return v


static func composition(fs: Array) -> float:
	if fs.size() <= 1:
		return 0.0
	var nn: = float(fs.size())
	var damage: = 0.0
	var front: = 0.0
	var protection: = 0.0
	var fragile: = 0.0
	var heal: = 0.0
	for f in fs:
		damage += float(f.damage)
		front += clampf((float(f.durability) - 0.7) * 2.0, 0.0, 1.4) * (1.0 if f.melee else 0.45)
		protection += float(f.ally_protection) + float(f.control) * 0.45
		fragile += float(f.fragile) + (0.2 if f.ranged else 0.0)
		heal += float(f.ally_healing)
	return 0.17 * minf(1.5, front) + 0.12 * minf(1.5, heal) - 0.55 * maxf(0.0, 0.8 * nn - damage)\
	- 0.24 * maxf(0.0, fragile - front * 0.6 - protection) - 0.12 * maxf(0.0, heal - nn * 0.65)






func _prepare() -> void :
	ids = DB.ids().duplicate()
	ids.sort()
	n = ids.size()
	index.clear()
	feats.clear()
	for i in n:
		index[ids[i]] = i
		feats.append(kit_features(DB.char_def(ids[i])))
	var arena: = DB.arena(arena_id)
	mapf = map_features(arena)
	mapf["control"] = 1.0 if ruleset == "control" else 0.0
	arena_name = arena.name
	var baseline: = {"walls": 0.0, "sight": 0.0, "hazard": 0.0, "portals": 0.0, "wind": 0.0}
	matrix.resize(n * n)
	pairs.resize(n * n)
	team_power.resize(n)
	var cal: Dictionary = _calibration()
	var duel: Dictionary = cal.get("duel", {})
	var team: Dictionary = cal.get("team", {})
	for i in n:
		team_power[i] = float(team.get(ids[i], 0.0))
		for j in n:
			pairs[i * n + j] = pair_synergy(feats[i], feats[j]) if i != j else 0.0
			if i == j:
				matrix[i * n + j] = 0.0
				continue
			var mech: = mechanics_matchup(feats[i], feats[j], mapf)
			var a: String = ids[i]
			var b: String = ids[j]
			var key: = "%s|%s" % [a, b] if a < b else "%s|%s" % [b, a]
			if duel.has(key):
				var obs: = float(duel[key]) * (1.0 if a < b else -1.0)

				var dep: = maxf(float(feats[i].ally_only), float(feats[j].ally_only)) if team_size > 1 else 0.0
				var m_adj: = (map_fit(feats[i], mapf) - map_fit(feats[j], mapf)) - (map_fit(feats[i], baseline) - map_fit(feats[j], baseline))
				matrix[i * n + j] = obs * 0.78 * (1.0 - dep) + mech * 0.22 + m_adj * 0.55
			else:
				matrix[i * n + j] = mech


static var _cal_cache: Dictionary = {}


static func _calibration() -> Dictionary:
	if not _cal_cache.is_empty():
		return _cal_cache
	var path: = "res://scripts/data/draft_calibration.gd"
	if ResourceLoader.exists(path):
		var sc: GDScript = load(path)
		if sc:
			var consts: = sc.get_script_constant_map()
			_cal_cache = {"duel": consts.get("DUEL", {}), "team": consts.get("TEAM", {}), "games": consts.get("GAMES", 0), 
				"engine": consts.get("ENGINE", "")}
	if _cal_cache.is_empty():
		_cal_cache = {"duel": {}, "team": {}, "games": 0, "engine": ""}
	return _cal_cache


func calibration_games() -> int:
	return int(_calibration().get("games", 0))






func members(mask: int) -> PackedInt32Array:
	if _members_cache.has(mask):
		return _members_cache[mask]
	var out: = PackedInt32Array()
	for i in n:
		if mask & (1 << i):
			out.append(i)
	_members_cache[mask] = out
	return out


func mask_of(team: Array) -> int:
	var m: = 0
	for id in team:
		if index.has(id):
			m |= 1 << int(index[id])
	return m


func team_quality(mask: int) -> float:
	if _q_cache.has(mask):
		return _q_cache[mask]
	var ms: = members(mask)
	var fs: Array = []
	var fit: = 0.0
	var power: = 0.0
	for i in ms:
		fs.append(feats[i])
		fit += map_fit(feats[i], mapf)
		power += team_power[i]
	var pv: = 0.0
	for x in ms.size():
		for y in range(x + 1, ms.size()):
			pv += pairs[ms[x] * n + ms[y]]
	var cnt: = maxf(1.0, ms.size())
	var v: = composition(fs) + pv / maxf(1.0, ms.size() - 1) * 0.65 + fit / cnt * 0.35

	if team_size > 1:
		v += power * 0.55
	_q_cache[mask] = v
	return v


func value(ai: int, user: int) -> float:
	if ai == user:
		return 0.0
	var key: = ai * SHIFT + user
	if _v_cache.has(key):
		return _v_cache[key]
	evals += 1
	var as_: = members(ai)
	var us: = members(user)
	var cross: = 0.0
	for i in as_:
		for j in us:
			cross += matrix[i * n + j]
	var cover_a: = 0.0
	for j in us:
		var best: = -1.0
		for i in as_:
			best = maxf(best, matrix[i * n + j])
		if not as_.is_empty():
			cover_a += best
	var cover_u: = 0.0
	for i in as_:
		var best2: = -1.0
		for j in us:
			best2 = maxf(best2, matrix[j * n + i])
		if not us.is_empty():
			cover_u += best2
	var duel_w: = 3.2 if team_size <= 1 else 1.9
	var v: = cross / maxf(1.0, as_.size() * us.size()) * duel_w + team_quality(ai) - team_quality(user)
	v += 0.22 * (cover_a / maxf(1.0, us.size()) - cover_u / maxf(1.0, as_.size()))
	v -= 1.6 * (_exposure(as_, us) - _exposure(us, as_))
	_v_cache[key] = v
	_v_cache[user * SHIFT + ai] = - v
	return v



func _exposure(own: PackedInt32Array, foe: PackedInt32Array) -> float:
	var shooters: Array = []
	for j in foe:
		if feats[j].ranged:
			shooters.append(j)
	if own.size() <= 1 or shooters.size() < 2:
		return 0.0
	var total: = 0.0
	for i in own:
		total += float(feats[i].raw_damage)
	var out: = 0.0
	for i in own:
		var f: Dictionary = feats[i]
		if not f.melee:
			continue
		var crossing: = 0.0
		for j in shooters:
			var e: Dictionary = feats[j]
			crossing += float(e.raw_damage) * 0.32 * maxf(0.0, float(e.range) - float(f.range)) / maxf(1.0, float(f.move_speed))
		out += crossing / float(f.max_health) * float(f.raw_damage) / maxf(1.0, total)
	return out






func legal(ai: int, user: int) -> PackedInt32Array:
	var used: = ai | user
	var out: = PackedInt32Array()
	for i in n:
		if not (used & (1 << i)):
			out.append(i)
	return out


func ranked(ai: int, user: int, turn: int) -> Array:
	var rows: Array = []
	for i in legal(ai, user):
		var v: = value(ai | (1 << i), user) if turn == 1 else value(ai, user | (1 << i))
		rows.append([i, v])
	rows.sort_custom( func(a, b):
		var da: = float(a[1]) * turn
		var db: = float(b[1]) * turn
		if absf(da - db) > 1e-09:
			return da > db
		return String(ids[int(a[0])]) < String(ids[int(b[0])]))
	return rows


func finish(ai: int, user: int, turn: int) -> Dictionary:
	var key: = str(ai) + ":" + str(user) + ":" + str(turn)
	if _f_cache.has(key):
		return _f_cache[key]
	var a: = ai
	var u: = user
	var t: = turn
	var line: Array = []
	var guard: = 0
	while (members(a).size() < team_size or members(u).size() < team_size) and guard < 12:
		guard += 1
		if members(a if t == 1 else u).size() >= team_size:
			t = - t
			continue
		var rows: = ranked(a, u, t)
		if rows.is_empty():
			break
		var pick: = int(rows[0][0])
		line.append({"side": "ai" if t == 1 else "user", "id": ids[pick]})
		if t == 1:
			a |= 1 << pick
		else:
			u |= 1 << pick
		t = - t
	var res: = {"value": value(a, u), "line": line}
	_f_cache[key] = res
	return res


func search(ai: int, user: int, turn: int, depth: int, ply: int, alpha: float, beta: float) -> Dictionary:
	nodes += 1
	var an: = members(ai).size()
	var un: = members(user).size()
	if an == team_size and un == team_size:
		return {"value": value(ai, user), "line": []}
	if depth <= 0 or evals > budget:
		return finish(ai, user, turn)
	if (an if turn == 1 else un) >= team_size:
		return search(ai, user, - turn, depth, ply, alpha, beta)
	var remaining: = 2 * team_size - an - un
	var rows: = ranked(ai, user, turn)
	var width: = rows.size() if remaining <= 2 else (6 if ply == 1 else (4 if ply == 2 else 3))
	var moves: Array = rows.slice(0, width)

	if turn == -1 and remaining > 2:
		var habitual: Array = []
		var best_h: = 0.0
		for row in rows.slice(width):
			var c: = float(user_history.get(ids[int(row[0])], 0))
			if c > best_h:
				best_h = c
				habitual = row
		if not habitual.is_empty():
			moves.append(habitual)
	var best: = {"value": - INF if turn == 1 else INF, "line": []}
	for row in moves:
		var i: = int(row[0])
		var child: = search(ai | (1 << i) if turn == 1 else ai, user | (1 << i) if turn == -1 else user, - turn, depth - 1, ply + 1, alpha, beta)
		if turn * float(child.value) > turn * float(best.value):
			var line: Array = [{"side": "ai" if turn == 1 else "user", "id": ids[i]}]
			line.append_array(child.line)
			best = {"value": child.value, "line": line}
		if turn == 1:
			alpha = maxf(alpha, float(best.value))
		else:
			beta = minf(beta, float(best.value))
		if beta <= alpha:
			break
	return best



func decide(user_team: Array, ai_team: Array) -> Dictionary:
	evals = 0
	nodes = 0
	var am: = mask_of(ai_team)
	var um: = mask_of(user_team)
	var avail: = legal(am, um)
	if avail.is_empty() or ai_team.size() >= team_size:
		return {}
	var remaining: = 2 * team_size - ai_team.size() - user_team.size()
	var depth: = mini(7, remaining)

	var root: = ranked(am, um, 1)
	var candidates: Array = []
	for row in root:
		var i: = int(row[0])
		var next: = am | (1 << i)
		var branch: = search(next, um, -1, depth - 1, 1, - INF, INF)
		var reply: = ""
		for step in branch.line:
			if str(step.side) == "user":
				reply = str(step.id)
				break
		candidates.append({"id": ids[i], "score": float(branch.value), "static": float(row[1]), "reply": reply, "line": branch.line})
	candidates.sort_custom( func(a, b):
		if absf(float(a.score) - float(b.score)) > 1e-09:
			return float(a.score) > float(b.score)
		var ha: = hash(str(seed_value) + ":" + str(a.id))
		var hb: = hash(str(seed_value) + ":" + str(b.id))
		if ha != hb:
			return ha < hb
		return str(a.id) < str(b.id))
	var chosen: Dictionary = candidates[0]
	var ci: = int(index[chosen.id])
	var f: Dictionary = feats[ci]
	var reasons: Array = []

	var best_counter: = {"id": "", "v": - INF}
	for e in user_team:
		var v: = matrix[ci * n + int(index[e])]
		if v > float(best_counter.v):
			best_counter = {"id": e, "v": v}
	if float(best_counter.v) > 0.12:
		reasons.append("%s 상성 대응 (%+.2f)" % [DB.char_def(best_counter.id).name, float(best_counter.v)])
	var user_heal: = false
	var user_proj: = false
	var user_summon: = false
	for e in user_team:
		var ef: Dictionary = feats[int(index[e])]
		user_heal = user_heal or float(ef.healing) > 0.3
		user_proj = user_proj or float(ef.projectile) > 0.5
		user_summon = user_summon or float(ef.summon) > 0.0
	if float(f.anti_heal) > 0.0 and user_heal:
		reasons.append("상대 회복 차단")
	if float(f.projectile_answer) > 0.0 and user_proj:
		reasons.append("상대 투사체에 방어·반사 수단 확보")
	if float(f.area) > 0.3 and user_summon:
		reasons.append("소환물과 밀집 진형에 광역 대응")
	var team_gain: = team_quality(am | (1 << ci)) - team_quality(am)
	if not ai_team.is_empty() and team_gain > 0.15:
		reasons.append("아군의 제어·화력·생존 연계 보완")
	if team_size > 1 and team_power[ci] > 0.15:
		reasons.append("자기 대전 팀전 기여도 상위")
	if arena_id != "classic" and absf(map_fit(f, mapf)) > 0.04:
		reasons.append("%s의 지형·위험 구역 반영" % arena_name)
	if str(chosen.reply) != "":
		reasons.append("%s 응수 이후 최종 조합까지 비교" % DB.char_def(chosen.reply).name)
	if reasons.is_empty():
		reasons.append("남은 후보 중 상대 조합에 대한 평가가 가장 높음")
	var alts: Array = []
	for k in range(1, mini(4, candidates.size())):
		alts.append({"id": candidates[k].id, "name": DB.char_def(candidates[k].id).name, "score": candidates[k].score})
	last_decision = {"id": chosen.id, "name": DB.char_def(chosen.id).name, "score": chosen.score, "reasons": reasons, 
		"alternatives": alts, "forecast": chosen.line, "reply": chosen.reply, "version": VERSION, 
		"search": {"nodes": nodes, "evals": evals, "depth": depth, "candidates": candidates.size(), "budget": budget}, 
		"calibration_games": calibration_games()}
	return last_decision



func evaluate_state(user_team: Array, ai_team: Array) -> float:
	return value(mask_of(ai_team), mask_of(user_team))
