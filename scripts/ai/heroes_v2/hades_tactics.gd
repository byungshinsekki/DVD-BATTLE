class_name HadesTactics
extends RefCounted

# V2 하데스 (hades) tactical AI (DESIGN_V2 §2.2, §2.7). TacticianBrain,
# Doctrine, KitModel and DraftDirector reach this file through one-line
# dispatches. Every rule reads only this team's knowledge (TeamIntel beliefs,
# our own units) and public data (hero definitions, map geometry).
#
# P1 키네에: 2% max HP/s while concealed once 1 s passed since the last hit.
#   Kits.concealed: invisible, inside active brush, or no enemy body this team
#   sees observes him. Low health: break sight or step into brush.
# P2 케르베로스: the engine pet bites hades' own command target, so the brain
#   needs no change. Enemy brains price the pet by its 15 s respawn.
# S1 망자 소환: startable only while concealed (engine gate). Cast as an ambush
#   when enemies are within ~450 or an engage is planned, never with nobody
#   near; walk through brush to reach that window.
# S2 명계 위반: extra value when the swing leaves a victim under 15% health and
#   its team heals (the 5 s heal block then denies that healing).
# S3 영혼 수확: expected ticks × enemies within 150 (contactExplosion template).

const ID: = "hades"
const SUMMON_KINDS: = ["cerberus", "shade"]
# Below this health ratio concealment (Kynee) is worth seeking.
const KYNEE_HP: = 0.6
# Seconds of regeneration a hiding spot is valued for.
const KYNEE_HORIZON: = 6.0
# S1: enemies this close make the ambush worth casting, or this close while
# the team commits to an engage.
const S1_REACH: = 450.0
const S1_ENGAGE_REACH: = 600.0
# Pet respawn (passive data) and a shade's average remaining life.
const PET_RESPAWN: = 15.0
const SHADE_LIFE_LEFT: = 3.5

static var _heal_cache: Dictionary = {}


static func is_hades(u: BUnit) -> bool:
	return u != null and u.def != null and u.def.id == ID


# ------------------------------------------------------------ kit lookups

# The S1 summon effect (shade ring) of an ability, or {}.
static func shade_effect(a: Defs.AbilityDef) -> Dictionary:
	if a == null:
		return {}
	for f in a.effects:
		if str(f.get("type", "")) == "summon" and str(f.get("originEntity", "")) == "shade":
			return f
	return {}


# The S3 aura buff effect (soulHarvest) of an ability, or {}.
static func harvest_effect(a: Defs.AbilityDef) -> Dictionary:
	if a == null:
		return {}
	for f in a.effects:
		if str(f.get("type", "")) == "buff" and str(f.get("stat", "")) == "soulHarvest":
			return f
	return {}


# The S2 conditional heal block: [threshold, duration], or [0, 0].
static func heal_block_of(a: Defs.AbilityDef) -> Array:
	if a == null:
		return [0.0, 0.0]
	for f in a.effects:
		if str(f.get("type", "")) == "status" and str(f.get("status", "")) == "healReduction" and f.has("whenTargetHpBelow") and float(f.get("magnitude", 0.0)) >= 1.0:
			return [float(f.whenTargetHpBelow), float(f.get("duration", 0.0))]
	return [0.0, 0.0]


static func _slot_index(d: Defs.CharDef, harvest: bool) -> int:
	for i in d.abilities.size():
		var a: Defs.AbilityDef = d.abilities[i]
		if (harvest and not harvest_effect(a).is_empty()) or (not harvest and not shade_effect(a).is_empty()):
			return i
	return -1


# ------------------------------------------------------------ concealment

# Whether `u` would be concealed standing at p, judged only from what this
# team sees: the clauses of Kits.concealed (the current spot uses the engine
# helper itself, which reads the same team view).
static func concealed_at(b: TacticianBrain, u: BUnit, p: Vector2) -> bool:
	var sim: BattleSim = b.sim
	if p.distance_squared_to(u.pos) < 1.0:
		return sim.kits.concealed(u)
	if sim.has_status(u, &"invisible"):
		return true
	if sim.brush_on and not sim.arena.forest_x.is_empty() and sim.arena.forest_at(p) >= 0:
		return true
	var r: float = sim.radius(u)
	for x in b.intel.visible_enemies(true):
		if _would_observe(b, x, p, r):
			return false
	return true


# Public sensing geometry of a seen enemy body (sim.observes without hidden
# state): vision reach, brush occlusion and line of sight. Deathmatch vision
# items are unknown, so a margin is added there.
static func _would_observe(b: TacticianBrain, e: TeamIntel.EnemyBelief, p: Vector2, r: float) -> bool:
	var sim: BattleSim = b.sim
	var reach: float = (sim.vision_range if e.is_hero else BattleSim.ENTITY_VISION) + e.radius + r
	if sim.is_deathmatch():
		reach += 60.0
	if e.pos.distance_squared_to(p) > reach * reach:
		return false
	if sim.brush_on and not sim.arena.forest_x.is_empty() and sim.arena.forest_occludes(e.pos, p):
		return false
	return sim.arena.line_of_sight(e.pos, p, minf(8.0, r * 0.18))


static func _concealed_now(b: TacticianBrain, u: BUnit, ctx: Dictionary) -> bool:
	if not ctx.has("hd_concealed"):
		ctx["hd_concealed"] = b.sim.kits.concealed(u)
	return bool(ctx.hd_concealed)


# Kynee regeneration per second (0 without the rule).
static func regen_per_s(sim: BattleSim, u: BUnit) -> float:
	var rule: Dictionary = u.def.rule("concealed_regen")
	if rule.is_empty():
		return 0.0
	return sim.max_hp(u) * float(rule.get("perSecondRatio", 0.0)) * _heal_factor(sim, u)


# Share of a heal that lands (own statuses: heal reduction, plague).
static func _heal_factor(sim: BattleSim, u: BUnit) -> float:
	var red: float = 0.0
	for st in u.statuses:
		if st.end <= sim.time:
			continue
		if st.type == &"healReduction":
			red = maxf(red, st.magnitude if st.magnitude > 0.0 else 0.35)
		elif st.type == &"plague":
			red = maxf(red, minf(0.6, st.stacks * 0.1))
	return clampf(1.0 - red, 0.0, 1.0)


# Health worth regaining by staying hidden for `secs` from now, weighted by
# how much it matters at this health: 0 from KYNEE_HP up, 0.3 just below it,
# full weight (healing priced like an ally heal, 1 per HP) at 25% and under.
# Telemetry: with a lighter weight a hades at 35-45% kept walking back into
# the fight even with no enemy near. The regeneration only starts 1 s after
# the last hit.
static func kynee_gain(b: TacticianBrain, u: BUnit, ctx: Dictionary, secs: float) -> float:
	var sim: BattleSim = b.sim
	var per: float = regen_per_s(sim, u)
	if per <= 0.0:
		return 0.0
	var rule: Dictionary = u.def.rule("concealed_regen")
	var quiet_in: float = maxf(0.0, float(rule.get("delay", 1.0)) - (sim.time - u.last_damage_time))
	var t: float = maxf(0.0, secs - quiet_in)
	var missing: float = maxf(0.0, float(ctx.mx) - float(ctx.hp))
	if float(ctx.hpr) >= KYNEE_HP:
		return 0.0
	var weight: float = 0.3 + 0.7 * clampf((KYNEE_HP - 0.05 - float(ctx.hpr)) / 0.3, 0.0, 1.0)
	return minf(missing, per * t) * weight


# ------------------------------------------------------------ movement

# Doctrine.move_points (id "hades"): Kynee hiding spots and S1 brush approach.
static func move_points(b: TacticianBrain, u: BUnit, ctx: Dictionary, _tgt: TeamIntel.EnemyBelief, pts: Array) -> void:
	if u.chamber != "":
		return
	_kynee_points(b, u, ctx, pts)
	_ambush_points(b, u, ctx, pts)


static func _kynee_points(b: TacticianBrain, u: BUnit, ctx: Dictionary, pts: Array) -> void:
	var sim: BattleSim = b.sim
	if float(ctx.hpr) >= KYNEE_HP or regen_per_s(sim, u) <= 0.0:
		return
	if kynee_gain(b, u, ctx, KYNEE_HORIZON + 1.0) < 8.0:
		return
	# Out of immediate danger the regeneration pays off; under fire the danger
	# term of the move itself decides and hiding only adds a little.
	var quiet: float = clampf(1.0 - float(ctx.danger) / maxf(1.0, float(ctx.ehp) * 0.6), 0.25, 1.0)
	if _concealed_now(b, u, ctx):
		pts.append([u.pos, "교리: 은신 회복 유지", kynee_gain(b, u, ctx, KYNEE_HORIZON) * quiet * 0.9])
		return
	var r: float = ctx.r
	var ms: float = maxf(40.0, float(ctx.ms))
	var spots: Array = []
	var ar: Arena = sim.arena
	if sim.brush_on and not ar.forest_x.is_empty():
		for k in ar.forest_x.size():
			var fc: Vector2 = Vector2(ar.forest_x[k], ar.forest_y[k])
			var d: float = u.pos.distance_to(fc)
			if d > 320.0 or b._brush_suspect(fc):
				continue
			var p: Vector2 = ar.resolve_circle(fc + (u.pos - fc).limit_length(ar.forest_r[k] * 0.45), r)
			if ar.forest_at(p) < 0 or ar.segment_blocked(u.pos, p, r, Arena.MASK_UNITS):
				continue
			spots.append([p, "교리: 수풀 은신 회복"])
	if not b.intel.visible_enemies(true).is_empty():
		for dist in [90.0, 170.0]:
			for k in 12:
				var want: Vector2 = u.pos + Vector2.from_angle(k * TAU / 12.0) * float(dist)
				var p2: Vector2 = ar.resolve_circle(want, r)
				if p2.distance_to(u.pos) < float(dist) * 0.5 or not ar.is_walkable(p2, r) or ar.segment_blocked(u.pos, p2, r, Arena.MASK_UNITS):
					continue
				if concealed_at(b, u, p2):
					spots.append([p2, "교리: 시야 차단 회복"])
	# The three spots that regain the most within the horizon (nearest first
	# on ties: the scan order is fixed, so this is deterministic).
	var scored: Array = []
	for s in spots:
		var p3: Vector2 = s[0]
		var gain: float = kynee_gain(b, u, ctx, KYNEE_HORIZON - u.pos.distance_to(p3) / ms)
		if gain >= 6.0:
			scored.append([gain - u.pos.distance_to(p3) * 0.01, p3, str(s[1]), gain])
	scored.sort_custom(func(x, y): return float(x[0]) > float(y[0]))
	for i in mini(3, scored.size()):
		var spot: Vector2 = scored[i][1]
		# Unseen, hades cannot be struck directly: the generic danger of the
		# spot overstates what the enemies there can do to him (except an
		# enemy close enough to see into the brush).
		var cover: float = 0.0
		if _beyond_reveal(b, u, spot):
			cover = b.danger_at(u, spot, 1.0) * float(ctx.risk_w) * 0.5
		pts.append([spot, scored[i][2], float(scored[i][3]) * quiet + cover])


# No seen enemy body stands within brush reveal range of p.
static func _beyond_reveal(b: TacticianBrain, u: BUnit, p: Vector2) -> bool:
	var r: float = b.sim.radius(u)
	for x in b.intel.visible_enemies(true):
		var e: TeamIntel.EnemyBelief = x
		if e.pos.distance_to(p) <= 130.0 + r + e.radius:
			return false
	return true


# S1 only starts while concealed: with S1 (nearly) ready, approach the enemy
# through brush that lies on the way instead of walking in the open.
static func _ambush_points(b: TacticianBrain, u: BUnit, ctx: Dictionary, pts: Array) -> void:
	var sim: BattleSim = b.sim
	var ar: Arena = sim.arena
	if not sim.brush_on or ar.forest_x.is_empty() or float(ctx.hpr) < 0.4 or str(b.plan.stance) == "DISENGAGE":
		return
	var i1: int = _slot_index(u.def, false)
	if i1 < 0 or u.sealed.has(i1) or u.cooldowns[i1] > sim.time + 1.5 or _concealed_now(b, u, ctx):
		return
	var e: TeamIntel.EnemyBelief = null
	var ed: float = INF
	for x in ctx.targets:
		var eb: TeamIntel.EnemyBelief = x
		var dx: float = u.pos.distance_to(eb.pos)
		if eb.is_hero and dx < ed:
			ed = dx
			e = eb
	if e == null or ed < 220.0 or ed > 820.0:
		return
	var bonus: float = 14.0 + (10.0 if bool(b.plan.get("go", false)) else 0.0)
	var rows: Array = []
	for k in ar.forest_x.size():
		var fc: Vector2 = Vector2(ar.forest_x[k], ar.forest_y[k])
		var d: float = u.pos.distance_to(fc)
		var de: float = fc.distance_to(e.pos)
		if d > 380.0 or de > S1_REACH or de >= ed or de < ar.forest_r[k] + 120.0 or b._brush_suspect(fc):
			continue
		var p: Vector2 = ar.resolve_circle(fc + (u.pos - fc).limit_length(ar.forest_r[k] * 0.45), ctx.r)
		if ar.forest_at(p) < 0:
			continue
		rows.append([d, p])
	rows.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
	for i in mini(2, rows.size()):
		pts.append([rows[i][1], "교리: 수풀 경유 매복", bonus])


# ------------------------------------------------------------ doctrine notes

# Doctrine.adjust branch for our own hades: an attack while hidden at low
# health trades away the Kynee regeneration (weighed against its value).
static func adjust(b: TacticianBrain, u: BUnit, ctx: Dictionary, c: Dictionary, kind: String, a: Defs.AbilityDef, e: TeamIntel.EnemyBelief) -> void:
	if kind != "basic" and kind != "ability":
		return
	if a != null and a.target == "self":
		return
	if e == null or float(ctx.hpr) >= KYNEE_HP * 0.8:
		return
	var parts: Dictionary = c.get("parts", {})
	if float(parts.get("처치", 0.0)) > 0.0 or (kind == "basic" and float(parts.get("피해", 0.0)) >= e.hp + e.shield):
		return
	if not _concealed_now(b, u, ctx):
		return
	var loss: float = kynee_gain(b, u, ctx, 3.0) * 0.8
	Doctrine._note(c, -loss, "교리: 은신 회복 유지")


# ------------------------------------------------------------ self casts

# TacticianBrain._self_candidates dispatch. True when the ability is one of
# hades' self casts (handled here, candidate or not).
static func self_candidate(b: TacticianBrain, u: BUnit, i: int, a: Defs.AbilityDef, ctx: Dictionary, out: Array) -> bool:
	var shade: Dictionary = shade_effect(a)
	if not shade.is_empty():
		_summon_candidate(b, u, i, a, shade, ctx, out)
		return true
	var harvest: Dictionary = harvest_effect(a)
	if not harvest.is_empty():
		var hv: Dictionary = harvest_value(b, u, harvest, ctx)
		if int(hv.n) > 0:
			var v: float = float(hv.value) - b._cost(u, a, ctx)
			if v > 0.0:
				out.append({"value": v, "key": "a%d:self" % i, "label": "%s (%d명 · %.0f틱)" % [a.name, int(hv.n), float(hv.ticks)],
					"parts": {"피해": float(hv.dmg), "흡수": float(hv.gain)},
					"cmd": {"kind": "ability", "index": i, "ability_id": a.id, "pos": u.pos, "need": 0.0}})
		return true
	return false


# S1: the ring of shades holds its slots (r + ringPadding) and bites only
# within reach, so it pays against enemies that come to hades during the 7 s,
# and its bodies screen skillshots. Ready implies concealed (engine gate).
static func _summon_candidate(b: TacticianBrain, u: BUnit, i: int, a: Defs.AbilityDef, f: Dictionary, ctx: Dictionary, out: Array) -> void:
	var engage: bool = str(b.plan.stance) == "ENGAGE" and (bool(b.plan.get("go", false)) or bool(b.plan.get("fighting", false)))
	var dur: float = float(f.get("duration", 7.0))
	var count: float = float(f.get("count", 5))
	var atk: Dictionary = f.get("attack", {})
	var bite: float = float(atk.get("base", 0.0)) + (float(atk.get("ad", 0.0)) * float(ctx.st.ad) + float(atk.get("ap", 0.0)) * float(ctx.st.ap)) * float(ctx.st.get("coefficient", 1.0))
	var interval: float = maxf(0.25, float(f.get("interval", 1.0)))
	var ring: float = float(ctx.r) + float(f.get("ringPadding", 30.0)) + float(f.get("reach", 24.0))
	var ms: float = float(ctx.ms)
	var near: int = 0
	var dmg_v: float = 0.0
	var screen: float = 0.0
	var best_active: float = 0.0
	for x in ctx.targets:
		var e: TeamIntel.EnemyBelief = x
		if not e.is_hero:
			continue
		var d: float = u.pos.distance_to(e.pos)
		var reach: float = S1_ENGAGE_REACH if engage else S1_REACH
		if d > reach:
			continue
		if d <= S1_REACH:
			near += 1
		var melee: bool = e.def.preferred_range < 120.0
		# Time until this enemy stands inside the ring: hades walks in about
		# half the time (other orders compete), plus the enemy's observed
		# approach. Telemetry: rings cast beyond ~300 px of an enemy that did not
		# come closer rarely bit anyone.
		var approach: float = maxf(0.0, e.vel.dot((u.pos - e.pos).normalized()))
		var closing: float = ms * (0.65 if engage else 0.5) + approach
		var contact_t: float = maxf(0.0, d - ring - e.radius) / maxf(30.0, closing)
		var active: float = clampf((dur - a.cast_time - contact_t) / dur, 0.0, 1.0)
		best_active = maxf(best_active, active)
		var est: Dictionary = KitModel._enemy_base(e.def).st
		var per: float = bite / interval * 100.0 / (100.0 + float(est.mr))
		var biting: float = minf(count, 2.0 if melee else 0.8)
		dmg_v += per * dur * active * biting * b._ew(e.idx)
		# Shade bodies stop enemy skillshots aimed at hades (not piercing ones).
		for ab in e.def.abilities:
			var ea: Defs.AbilityDef = ab
			if ea.hostile and ea.delivery == "projectile" and not ea.homing and ea.pierce == 0 and ea.target in ["enemy", "position"]:
				screen += 30.0 * active
				break
	# Nobody near, or nobody expected inside the ring for a third of its life
	# (telemetry: such rings almost never bit or screened anything).
	if (near == 0 and not (engage and dmg_v > 0.0)) or best_active < 0.3:
		return
	# The concealment window is rare (+20) and an engage wants the ring now
	# (+25), both only as far as the ring will actually meet someone.
	var v: float = dmg_v * 0.8 + screen + (20.0 + (25.0 if engage else 0.0)) * best_active
	match str(b.plan.stance):
		"DISENGAGE":
			# The ring follows hades: chasers still run into it.
			v *= 0.7
	v -= b._cost(u, a, ctx)
	if v > 0.0:
		out.append({"value": v, "key": "a%d:self" % i, "label": "%s (매복 %d명)" % [a.name, near],
			"parts": {"소환": dmg_v, "차폐": screen},
			"cmd": {"kind": "ability", "index": i, "ability_id": a.id, "pos": u.pos, "need": 0.0}})


# S3 (also TacticianBrain._buff_value "soulHarvest"): expected ticks × enemies
# within the radius that hades observes (the engine only harvests those). The
# HP damage dealt returns as temporary max HP, capped at capRatio of the base.
static func harvest_value(b: TacticianBrain, u: BUnit, f: Dictionary, ctx: Dictionary) -> Dictionary:
	var out: Dictionary = {"value": 0.0, "n": 0, "ticks": 0.0, "dmg": 0.0, "gain": 0.0}
	if not ctx.has("strike"):
		return out
	var sim: BattleSim = b.sim
	var radius: float = float(f.get("radius", 150.0))
	var interval: float = maxf(0.05, float(f.get("interval", 0.5)))
	var total_ticks: float = roundf(float(f.get("duration", 5.0)) / interval)
	var raw: Dictionary = f.get("damage", {})
	var st: Dictionary = ctx.st
	var tick_raw: float = float(raw.get("base", 0.0)) + (float(raw.get("ad", 0.0)) * float(st.ad) + float(raw.get("ap", 0.0)) * float(st.ap) \
		+ float(raw.get("selfMaxHp", 0.0)) * float(st.maxhp)) * float(st.get("coefficient", 1.0))
	var dmg_v: float = 0.0
	var hp_dmg: float = 0.0
	var tick_sum: float = 0.0
	for x in ctx.strike:
		var e: TeamIntel.EnemyBelief = x
		if e.has_status("invulnerable"):
			continue
		var d: float = u.pos.distance_to(e.pos)
		var edge: float = radius + e.radius
		var melee: bool = e.is_hero and e.def.preferred_range < 120.0
		var stay: float = 0.0
		if d <= edge:
			var lock: float = e.movement_lock_remaining()
			if not e.is_hero:
				stay = total_ticks * interval
			elif melee:
				stay = total_ticks * interval * (0.55 + 0.45 * e.aggression)
			else:
				stay = lock + (edge - d) / maxf(30.0, e.ms() * 0.7)
		elif d <= edge + 40.0 and melee:
			# Just outside: a melee enemy fighting hades walks back in.
			stay = total_ticks * interval * 0.35 * e.aggression
		if stay <= 0.0:
			continue
		var ticks: float = minf(total_ticks, floorf(stay / interval) + 1.0)
		var mr: float = float(KitModel._enemy_base(e.def).st.mr) if e.is_hero else e.def.stat("magicResistance")
		var per: float = tick_raw * 100.0 / (100.0 + maxf(0.0, mr))
		var hit: float = minf(per * ticks, e.hp + e.shield)
		dmg_v += hit * (b._ew(e.idx) if e.is_hero else 0.35)
		# Only health damage becomes max HP; a shield soaks the first ticks.
		hp_dmg += clampf(per * ticks - e.shield, 0.0, e.hp)
		tick_sum += ticks
		# Only an enemy hero already inside the aura opens it: one walking back
		# in adds value but never starts the cast on its own.
		if e.is_hero and d <= edge:
			out.n = int(out.n) + 1
	if int(out.n) == 0:
		return out
	var cap: float = u.base_max_hp * float(f.get("capRatio", 0.25))
	for hb in u.buffs:
		if hb.stat == &"maxHealth" and hb.tag == "soulHarvest" and hb.end > sim.time:
			cap -= hb.amount * u.base_max_hp
	var gain: float = clampf(hp_dmg, 0.0, maxf(0.0, cap))
	out.value = dmg_v + gain * (0.6 + 0.6 * (1.0 - float(ctx.hpr)))
	out.ticks = tick_sum
	out.dmg = dmg_v
	out.gain = gain
	return out


# ------------------------------------------------------------ S2 heal block

# TacticianBrain._special_enemy dispatch for hades S2 (cone): the heal block
# only lands on victims the swing leaves under the threshold (and alive); it
# is worth the healing their team would give them meanwhile.
static func special_enemy(b: TacticianBrain, u: BUnit, a: Defs.AbilityDef, e: TeamIntel.EnemyBelief, aim: Vector2, ctx: Dictionary) -> float:
	var hb: Array = heal_block_of(a)
	if float(hb[0]) <= 0.0:
		return 0.0
	var v: float = heal_block_value(b, u, a, e, ctx, 1.0)
	if a.delivery == "cone":
		var cdir: Vector2 = (aim - u.pos).normalized() if aim.distance_squared_to(u.pos) > 1.0 else (e.pos - u.pos).normalized()
		for x in ctx.targets:
			var sec: TeamIntel.EnemyBelief = x
			if sec.idx == e.idx or not sec.is_hero:
				continue
			var sp: Vector2 = b.lead_point(u.pos, sec, 0.0, a.cast_time, 0.8)
			var off: Vector2 = sp - u.pos
			var od: float = off.length()
			if od < 1.0 or od > a.range + sec.radius or absf(cdir.angle_to(off)) > a.angle * 0.5 + sec.radius / od:
				continue
			if not b.sim.arena.line_of_sight(u.pos, sp, 2.0):
				continue
			v += heal_block_value(b, u, a, sec, ctx, b._hit_prob(u, a, sec, sp))
	return v


static func heal_block_value(b: TacticianBrain, u: BUnit, a: Defs.AbilityDef, x: TeamIntel.EnemyBelief, ctx: Dictionary, hit_p: float) -> float:
	var hb: Array = heal_block_of(a)
	var thr: float = float(hb[0])
	var dur: float = float(hb[1])
	if thr <= 0.0 or not x.is_hero or x.has_status("invulnerable") or x.has_status("unstoppable") or x.has_status("untargetable"):
		return 0.0
	var ev: Dictionary = KitModel.evaluate(a.effects, ctx.st, {"max_hp": x.max_hp, "hp": x.hp})
	var est: Dictionary = KitModel._enemy_base(x.def).st
	var dmg: float = KitModel.mitigate(ev, float(est.armor), float(est.mr))
	var hp_after: float = x.hp - maxf(0.0, dmg - x.shield)
	if hp_after <= 0.0 or hp_after >= x.max_hp * thr:
		return 0.0
	# Our own block already covering most of the window adds nothing.
	for s in x.statuses:
		if str(s.type) == "healReduction" and bool(s.get("own", false)) and float(s.get("remaining", 0.0)) > dur * 0.6:
			return 0.0
	var rate: float = team_heal_rate(b, x)
	if rate <= 0.5:
		return 0.0
	var denied: float = minf(rate * dur, x.max_hp * thr * 2.0)
	return (denied + 20.0) * hit_p


# Healing per second an enemy hero can receive: its own sustain plus what its
# visible-or-remembered teammates give allies (public kit data), plus the
# deathmatch out-of-combat regeneration.
static func team_heal_rate(b: TacticianBrain, x: TeamIntel.EnemyBelief) -> float:
	var sim: BattleSim = b.sim
	var xu: BUnit = sim.u_at(x.idx)
	var rate: float = float(heal_profile(x.def)[0])
	if xu != null:
		for k in b.intel.enemies:
			var o: TeamIntel.EnemyBelief = b.intel.enemies[k]
			if o == x or o.dead or o.controlled_by_us:
				continue
			var ou: BUnit = sim.u_at(o.idx)
			if ou == null or ou.team != xu.team:
				continue
			rate += float(heal_profile(o.def)[1]) * (1.0 if o.pos.distance_to(x.pos) < 600.0 else 0.4)
	if sim.is_deathmatch():
		rate += 0.015 * x.max_hp * 0.25
	return rate


# [self HP/s, ally HP/s] from the public kit (DraftDirector.kit_features),
# with the plague doctor's banked mist that the feature table leaves out.
static func heal_profile(d: Defs.CharDef) -> Array:
	if _heal_cache.has(d.id):
		return _heal_cache[d.id]
	var f: Dictionary = DraftDirector.kit_features(d)
	var row: Array = [float(f.healing) * 22.0, float(f.ally_healing) * 22.0]
	if d.id == "plague_doctor":
		row = [row[0] + 8.0, row[1] + 8.0]
	_heal_cache[d.id] = row
	return row


# ------------------------------------------------------------ enemy side

# TacticianBrain._enemy_value for a hades summon (enemy brains). The pet is
# worth the bites its death denies until it returns 15 s later; a shade only
# its remaining bites on us. Control on a summon is worth little, and a
# summon kill is not a hero kill ("처치" stays 0).
static func summon_value(b: TacticianBrain, u: BUnit, a: Defs.AbilityDef, e: TeamIntel.EnemyBelief, ctx: Dictionary, hit_p: float, mult: float) -> Dictionary:
	var ev: Dictionary = KitModel.evaluate(a.effects, ctx.st, {"max_hp": e.max_hp, "hp": e.hp})
	var dmg: float = KitModel.mitigate(ev, e.def.stat("armor"), e.def.stat("magicResistance")) * hit_p * mult
	if e.has_status("invulnerable"):
		dmg = 0.0
	var bite: float = summon_bite(b, u, e)
	var v: float = 0.0
	var cc_v: float = 0.0
	var cc: float = KitModel.cc_total(ev)
	if e.kind == "cerberus":
		v = minf(dmg, e.hp) * 0.35
		if dmg >= e.hp:
			v += bite * PET_RESPAWN * 0.4 * hit_p
		cc_v = minf(cc, 3.0) * bite * 0.5 * hit_p
	else:
		v = minf(dmg, e.hp) * 0.25
		if dmg >= e.hp:
			v += bite * SHADE_LIFE_LEFT * (1.0 if _adjacent(b, u, e) else 0.3) * hit_p
	return {"value": v + cc_v, "dmg": dmg, "kill": 0.0, "cc": cc_v, "ev": ev}


# Expected damage per second of a hades summon on unit u (owner's public base
# stats; a shade only bites within reach of its ring slot).
static func summon_bite(b: TacticianBrain, u: BUnit, e: TeamIntel.EnemyBelief) -> float:
	var sim: BattleSim = b.sim
	var eu: BUnit = sim.u_at(e.idx)
	var owner: BUnit = sim.u_at(eu.owner_idx) if eu else null
	if owner == null or owner.def == null:
		return 0.0
	var ad: float = owner.def.stat("attackDamage")
	if e.kind == "cerberus":
		var r: Dictionary = owner.def.rule("companion")
		var atk: Dictionary = r.get("attack", {})
		var raw: float = float(atk.get("base", 14.0)) + float(atk.get("ad", 0.22)) * ad
		return raw / maxf(0.25, float(r.get("interval", 1.0))) * 100.0 / (100.0 + sim.stat(u, &"armor"))
	for ab in owner.def.abilities:
		var f: Dictionary = shade_effect(ab)
		if f.is_empty():
			continue
		var atk2: Dictionary = f.get("attack", {})
		var raw2: float = float(atk2.get("base", 8.0)) + float(atk2.get("ad", 0.12)) * ad
		return raw2 / maxf(0.25, float(f.get("interval", 1.0))) * 100.0 / (100.0 + sim.stat(u, &"magicResistance"))
	return 0.0


static func _adjacent(b: TacticianBrain, u: BUnit, e: TeamIntel.EnemyBelief) -> bool:
	return u.pos.distance_to(e.pos) <= b.sim.radius(u) + e.radius + 30.0


# Doctrine.adjust (every hero of a brain facing hades): basic attacks into a
# shade that is not biting us are mostly wasted (7 s summon), while the hit
# that kills the pet buys its 15 s respawn.
static func enemy_notes(b: TacticianBrain, u: BUnit, _ctx: Dictionary, cands: Array) -> void:
	var any: bool = false
	for k in b.intel.entities:
		var eb: TeamIntel.EnemyBelief = b.intel.entities[k]
		if eb.visible and eb.kind in SUMMON_KINDS:
			any = true
			break
	if not any:
		return
	for c in cands:
		var cmd: Dictionary = c.cmd
		if str(cmd.get("kind", "")) != "basic":
			continue
		var e: TeamIntel.EnemyBelief = b.intel.entities.get(int(cmd.get("target", -1)))
		if e == null or not (e.kind in SUMMON_KINDS):
			continue
		var per: float = float((c.get("parts", {}) as Dictionary).get("피해", 0.0))
		if e.kind == "shade":
			if not _adjacent(b, u, e):
				Doctrine._note(c, -maxf(0.0, float(c.value)) * 0.4, "망자 무시 (7초 소환)")
		elif per >= e.hp:
			Doctrine._note(c, summon_bite(b, u, e) * PET_RESPAWN * 0.4, "케르베로스 처치 (15초 부재)")


# _danger_raw, enemy entity loop: the pet bites what is near hades, a shade
# only what touches its slot.
static func entity_danger(b: TacticianBrain, u: BUnit, eb: TeamIntel.EnemyBelief, p: Vector2, horizon: float) -> float:
	var dd: float = p.distance_to(eb.pos)
	var r: float = b.sim.radius(u)
	if eb.kind == "cerberus":
		if dd > r + eb.radius + 90.0:
			return 0.0
		return summon_bite(b, u, eb) * horizon * (1.0 if dd <= r + eb.radius + 30.0 else 0.5)
	if eb.kind == "shade" and dd <= r + eb.radius + 30.0:
		return summon_bite(b, u, eb) * horizon
	return 0.0


# _danger_raw, enemy hero loop: a hades whose harvest aura is running (its
# S3 cast was observed by this team) drains everyone within the radius.
static func aura_danger(b: TacticianBrain, u: BUnit, eb: TeamIntel.EnemyBelief, p: Vector2, horizon: float) -> float:
	var i3: int = _slot_index(eb.def, true)
	if i3 < 0 or i3 >= eb.cd_last.size() or eb.cd_last[i3] < -100.0:
		return 0.0
	var a: Defs.AbilityDef = eb.def.abilities[i3]
	var f: Dictionary = harvest_effect(a)
	var left: float = eb.cd_last[i3] + a.cast_time + float(f.get("duration", 5.0)) - b.sim.time
	if left <= 0.0:
		return 0.0
	var r: float = b.sim.radius(u)
	if p.distance_to(eb.pos) > float(f.get("radius", 150.0)) + r + 10.0:
		return 0.0
	var raw: Dictionary = f.get("damage", {})
	var tick: float = float(raw.get("base", 0.0)) + float(raw.get("ad", 0.0)) * eb.def.stat("attackDamage") + float(raw.get("selfMaxHp", 0.0)) * eb.max_hp
	return tick / maxf(0.05, float(f.get("interval", 0.5))) * 100.0 / (100.0 + b.sim.stat(u, &"magicResistance")) * minf(horizon, left)


# ------------------------------------------------------------ draft

# DraftDirector.kit_features lines for hades: Kynee regeneration (share of a
# fight spent concealed), harvested max HP and harvest damage (about 1.5
# enemies for 60% of the ticks), cerberus bites and the ambush shades.
static func draft_features(d: Defs.CharDef) -> Dictionary:
	var hp: float = d.stat("maxHealth")
	var ad: float = d.stat("attackDamage")
	var heal: float = 0.0
	var spell: float = 0.0
	var magic: float = 0.0
	var regen: Dictionary = d.rule("concealed_regen")
	if not regen.is_empty():
		heal += hp * float(regen.get("perSecondRatio", 0.0)) * 0.15
	spell += KitModel.companion_dps(d, ad) * 0.6
	for ab in d.abilities:
		var a: Defs.AbilityDef = ab
		var cd: float = maxf(1.0, a.cooldown)
		var h: Dictionary = harvest_effect(a)
		if not h.is_empty():
			var raw: Dictionary = h.get("damage", {})
			var tick: float = float(raw.get("base", 0.0)) + float(raw.get("ad", 0.0)) * ad + float(raw.get("selfMaxHp", 0.0)) * hp
			var ticks: float = roundf(float(h.get("duration", 5.0)) / maxf(0.05, float(h.get("interval", 0.5))))
			var dealt: float = tick * ticks * 1.5 * 0.6
			spell += dealt / cd
			if str(raw.get("school", "")) == "magic":
				magic += dealt / cd
			heal += minf(dealt * 0.75, hp * float(h.get("capRatio", 0.25))) / cd
		var s: Dictionary = shade_effect(a)
		if not s.is_empty():
			var atk: Dictionary = s.get("attack", {})
			var bite: float = float(atk.get("base", 0.0)) + float(atk.get("ad", 0.0)) * ad
			var shade_dps: float = bite * float(s.get("count", 1)) * float(s.get("duration", 7.0)) / maxf(0.25, float(s.get("interval", 1.0))) * 0.15 * 0.55 / cd
			spell += shade_dps
			if str(atk.get("school", "")) == "magic":
				magic += shade_dps
	return {"heal": heal, "spell": spell, "magic": magic}
