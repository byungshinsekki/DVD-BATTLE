class_name WarMachineTactics
extends RefCounted

# V2 전쟁 기계 (war_machine) tactical AI (DESIGN_V2 §2.3, §2.7). Every rule
# specific to this hero lives here as static functions; tactician_brain,
# doctrine, kit_model, intel and draft_director only carry one-line
# dispatches into it.
#
# Own side:
# - Fuel economy: 7 fuel is banked for genocide (S4) once its cooldown is
#   nearly over; guided bombing (S2) charges what is left above the bank,
#   N = clamp(fuel - bank, 2, 6), fewer when fewer missiles kill.
# - S2 is never charged next to a melee threat (the charge slows by 40%).
# - Arc protector (S3) on the damage predicted for its 3 s, or when diving in.
# - Booster (S1) closes a short gap or escapes, priced in fuel the bank needs;
#   free in overdrive, where it keeps the war machine on its target.
# - Genocide (S4) is aimed along the line holding the most enemies, discounted
#   by their chance to step out of the public line telegraph; slowed or rooted
#   enemies stay in the strip longer.
# - Overdrive (tank destroyed): all-in basics.
# Enemy side:
# - The attached fuel tank is worth breaking when the believed fuel arms
#   genocide, never when the overdrive burst would kill one of us. The fuel is
#   a belief from observed basics and spends (TeamIntel, information fair).

const ID: = "war_machine"
const FUEL: = "fuel"
const FUEL_CAP: = 10.0
const S4_FUEL: = 7.0
# Genocide is "nearly ready" when its cooldown has at most BANK_WINDOW s left
# and the fuel is within two basic hits of its cost (BANK_FROM): only then is
# fuel banked. Below that the war machine lands about one basic per 4 s in a
# real fight (telemetry), so holding 7 would starve the missiles for nothing.
const BANK_WINDOW: = 6.0
const BANK_FROM: = 5.0
# Value of one fuel by what spends it. Fuel only comes from basic hits (about
# one per 4 s in real fights, telemetry), so a fuel the booster burns is a
# missile that will not fly (MISSILE_FUEL); a missile is the fuel's purpose and
# costs little (CHARGE_FUEL, enough to prefer a fuller charge later).
const MISSILE_FUEL: = 18.0
const CHARGE_FUEL: = 4.0
# Extra cost per fuel taken out of the genocide bank.
const BANK_PENALTY: = 45.0
# Value of one banked fuel to genocide itself (waiting for a better strip).
const BANK_VALUE: = 6.0
const S4_LENGTH: = 380.0
const S4_WIDTH: = 90.0
# kit_model's share of a zone's ticks a free enemy stays in (zones: 0.3).
const ZONE_STAY: = 0.3
const OVERDRIVE_MULT: = 1.5
const BOOSTER_SPEED: = 700.0
# Booster escapes: below this health ratio, or above this share of effective
# HP in predicted damage over the next second.
const ESCAPE_HP: = 0.4
const ESCAPE_DANGER: = 0.5
# Arc protector: predicted 3 s damage below this share of effective HP is
# not worth the 15 s cooldown (outside a dive).
const GUARD_FLOOR: = 0.25

# Telemetry baseline switch (tools/wm_telemetry_v2.gd --generic=1): false
# hands the war machine's own skills back to the generic tactician paths.
static var own_planning: bool = true


# ------------------------------------------------------------------ own state

static func fuel(u: BUnit) -> float:
	return float(u.resources.get(FUEL, 0.0))


static func overdrive(sim: BattleSim, u: BUnit) -> bool:
	return not u.statuses.is_empty() and sim.has_status(u, &"overdrive")


# Fuel kept for genocide: its whole cost once it is nearly ready.
static func reserve(b: TacticianBrain, u: BUnit) -> float:
	if u.def.abilities.size() < 4 or u.sealed.has(3) or overdrive(b.sim, u):
		return 0.0
	if u.cooldowns[3] - b.sim.time > BANK_WINDOW or fuel(u) < BANK_FROM - 1e-06:
		return 0.0
	return S4_FUEL


# Opportunity cost of spending `spend` fuel now on slot `slot` (1 booster,
# 2 missiles, 4 genocide). Fuel at the cap is cheaper (basic hits stop
# refilling it); fuel taken out of the genocide bank costs BANK_PENALTY more
# per unit, except for genocide itself, whose banked fuel has no other use
# than a later, better strip (BANK_VALUE per unit).
static func fuel_cost(b: TacticianBrain, u: BUnit, spend: float, slot: int) -> float:
	if spend <= 0.0:
		return 0.0
	var have: float = fuel(u)
	var for_s4: bool = slot == 4
	var unit: float = BANK_VALUE if for_s4 else (CHARGE_FUEL if slot == 2 else MISSILE_FUEL)
	var cost: float = spend * unit * (0.6 if have >= FUEL_CAP - 0.5 else 1.0)
	if not for_s4:
		var free: float = maxf(0.0, have - reserve(b, u))
		cost += maxf(0.0, spend - free) * BANK_PENALTY
	return cost


# A visible enemy melee hero within its own attack reach (+30) of u.
static func melee_adjacent(u: BUnit, ctx: Dictionary) -> bool:
	for t in ctx.targets:
		var e: TeamIntel.EnemyBelief = t
		if not e.is_hero or e.def.preferred_range >= 120.0:
			continue
		if u.pos.distance_to(e.pos) - float(ctx.r) - e.radius <= e.def.stat("attackRange") + 30.0:
			return true
	return false


# Damage predicted on u over the next `horizon` seconds (team danger model:
# visible and believed enemies, their ready skills, shots and telegraphs).
static func incoming(b: TacticianBrain, u: BUnit, horizon: float = 3.0) -> float:
	return b.danger_at(u, u.pos, horizon)


# ------------------------------------------------------------------ candidates

# Dispatch from TacticianBrain._ability_candidates: every own active of the war
# machine is planned here. Returns false for anything else.
static func candidates(b: TacticianBrain, u: BUnit, i: int, a: Defs.AbilityDef, ctx: Dictionary, out: Array) -> bool:
	if a.virtual or a.char_id != ID or not own_planning:
		return false
	match a.slot:
		1:
			_booster(b, u, i, a, ctx, out)
		2:
			_missiles(b, u, i, a, ctx, out)
		3:
			_arc_protector(b, u, i, a, ctx, out)
		4:
			_genocide(b, u, i, a, ctx, out)
		_:
			return false
	return true


static func _dash_distance(a: Defs.AbilityDef) -> float:
	for f in a.effects:
		if str(f.get("type", "")) == "move_self":
			return float(f.get("distance", 110.0))
	return 110.0


# A plain dash passes through bodies and stops at the first terrain contact,
# exactly as Kits.update_motion does. Never shorten it to the enemy's edge.
static func booster_landing(sim: BattleSim, start: Vector2, aim: Vector2, r: float, dash: float) -> Vector2:
	var end: Vector2 = start + (aim - start).normalized() * dash
	var contact: Dictionary = sim.arena.terrain_contact(start, end, r, false)
	return contact.point if not contact.is_empty() else end


# S1 부스터: a 110 px dash toward the aim. Gap-close on an observed enemy hero
# just out of basic reach (value: basic damage over the time the dash saves,
# more against a fleeing target), or the shared escape search. Every observed
# enemy hero in dash reach gets a candidate so the planner can also decline it.
static func _booster(b: TacticianBrain, u: BUnit, i: int, a: Defs.AbilityDef, ctx: Dictionary, out: Array) -> void:
	var sim: BattleSim = b.sim
	var r: float = ctx.r
	var free: bool = sim.kits.cost_waived(u, a)
	var od: bool = overdrive(sim, u)
	var dash: float = _dash_distance(a)
	var dash_t: float = a.cast_time + dash / BOOSTER_SPEED
	var cost: float = 0.0 if free else fuel_cost(b, u, 1.0, 1)
	var reach: float = float(ctx.range) + r
	var ms: float = maxf(30.0, float(ctx.ms))
	for t in ctx.strike:
		var e: TeamIntel.EnemyBelief = t
		if not e.is_hero or e.has_status("untargetable"):
			continue
		var dist: float = u.pos.distance_to(e.pos)
		var gap: float = dist - reach - e.radius
		if gap > dash + reach + 60.0:
			continue
		var lead: Vector2 = b.lead_point(u.pos, e, 0.0, dash_t, 0.8)
		var dir: Vector2 = (lead - u.pos).normalized() if lead.distance_squared_to(u.pos) > 1.0 else u.facing
		var aim: Vector2 = u.pos + dir * dash
		var land: Vector2 = booster_landing(sim, u.pos, aim, r, dash)
		var travel_t: float = a.cast_time + u.pos.distance_to(land) / BOOSTER_SPEED
		# Time to reach basic range walking versus dashing first; a target
		# moving away keeps the walking gap open longer.
		var away: float = maxf(0.0, e.vel.dot((e.pos - u.pos).normalized()))
		var closing: float = maxf(20.0, ms - away)
		var walk_t: float = maxf(0.0, gap) / closing
		var after: Vector2 = b.lead_point(u.pos, e, 0.0, travel_t, 0.8)
		var rest: float = maxf(0.0, land.distance_to(after) - reach - e.radius)
		var saved: float = clampf(walk_t - (travel_t + rest / closing), -travel_t, 2.0)
		var est: Dictionary = KitModel._enemy_base(e.def).st
		var dps: float = float(ctx.dps) * 100.0 / (100.0 + float(est.armor))
		var worth: float = b._ew(e.idx) * (1.35 if ctx.focus and (ctx.focus as TeamIntel.EnemyBelief).idx == e.idx else 1.0)
		var v: float = dps * saved * worth
		var notes: Array = []
		if saved > 0.0 and e.hp + e.shield <= dps * 3.0:
			v += 45.0 * clampf(saved / 0.5, 0.0, 1.0)
			notes.append("처치 추격")
		if od and gap > 4.0:
			# Overdrive: the free booster keeps the war machine on its target.
			v += 22.0
			notes.append("과열 폭주: 부스터 추격")
		v -= cost
		v -= maxf(0.0, b.danger_at(u, land, 1.0) - float(ctx.danger)) * float(ctx.risk_w) * (0.3 if od else 0.6)
		if not free and fuel(u) - 1.0 < reserve(b, u) - 1e-06:
			# The gap-close would spend fuel genocide needs.
			v = minf(v, -15.0)
			notes.append("제노사이드 연료 비축")
		out.append({"value": v, "key": "a%d:%d" % [i, e.idx], "label": "%s → %s (접근)" % [a.name, e.def.name],
			"parts": {"단축": saved, "연료": cost, "이동": u.pos.distance_to(land)}, "notes": notes,
			"cmd": {"kind": "ability", "index": i, "ability_id": a.id, "pos": aim, "need": dash + r}})
	# Escape: a diver backing off 110 px mid-fight only delays the trade, so
	# only when hurt or facing near-lethal damage (not in overdrive: all-in).
	if od or (float(ctx.hpr) >= ESCAPE_HP and float(ctx.danger) < float(ctx.ehp) * ESCAPE_DANGER):
		return
	var tmp: Array = []
	b._escape_candidate(u, i, a, ctx, tmp, dash)
	for c: Dictionary in tmp:
		var land: Vector2 = booster_landing(sim, u.pos, c.cmd.pos, r, dash)
		if not b._v2_escape_safe(u, land, r):
			continue
		# The generic escape search may have snapped its aim onto terrain.
		# Price the fixed-distance dash's actual endpoint, not that aim.
		var gain: float = float(ctx.danger) - b.danger_at(u, land, 1.2)
		c.value = gain * float(ctx.risk_w) * 1.2
		(c.parts as Dictionary)["위험 감소"] = gain
		if float(c.value) <= 25.0:
			continue
		# Survival first: half the bank penalty on an escape.
		var esc_cost: float = 0.0 if free else MISSILE_FUEL + (fuel_cost(b, u, 1.0, 1) - MISSILE_FUEL) * 0.5
		c.value = float(c.value) - esc_cost
		(c.parts as Dictionary)["연료"] = esc_cost
		out.append(c)


# S2 유도폭격: homing missiles, N = clamp(fuel - bank, 2, min(6, fuel)), fewer
# when fewer kill; only the minimum (no extra charge) next to a melee threat.
# A kill may dip into the bank. Charging slows by 40%: its exposure is priced.
static func _missiles(b: TacticianBrain, u: BUnit, i: int, a: Defs.AbilityDef, ctx: Dictionary, out: Array) -> void:
	var sim: BattleSim = b.sim
	var ch: Dictionary = a.flag("originCharge", {})
	var lo: int = int(ch.get("min", 2))
	var have: float = fuel(u)
	var hi: int = mini(int(ch.get("max", 6)), int(floor(have + 1e-06)))
	if hi < lo:
		return
	var surplus: int = int(floor(have - reserve(b, u) + 1e-06))
	var base_n: int = clampi(surplus, lo, hi)
	var adjacent: bool = melee_adjacent(u, ctx)
	var pressed: bool = float(ctx.danger) > float(ctx.ehp) * 0.35
	var r: float = ctx.r
	var proj_r: float = maxf(3.0, a.width * 0.5)
	var need: float = a.range + r
	var per_ev: Dictionary = KitModel.evaluate(a.effects, ctx.st, {})
	for t in ctx.strike:
		var e: TeamIntel.EnemyBelief = t
		var tu: BUnit = sim.u_at(e.idx)
		if tu == null or not sim.check_condition(u, tu, a.condition) or not sim.target_legal(u, a, tu):
			continue
		var dist: float = u.pos.distance_to(e.pos)
		var appr: float = b._approach_factor(u, dist, need, ctx)
		if appr <= 0.02:
			continue
		var hit: float = b._hit_prob(u, a, e, e.pos)
		var victim: TeamIntel.EnemyBelief = e
		if dist <= need:
			# Homing missiles still die on walls and on the first enemy body.
			var start: Vector2 = u.pos + (e.pos - u.pos).normalized() * minf(r + 4.0, dist)
			if sim.arena.segment_blocked(start, e.pos, proj_r, Arena.MASK_PROJECTILES):
				continue
			var first: TeamIntel.EnemyBelief = b._first_contact(start, e.pos, proj_r, e, ctx)
			if first != null:
				victim = first
				hit = 0.9
		# Missiles the victim needs: overkill is wasted fuel.
		var est: Dictionary = KitModel._enemy_base(victim.def).st
		var per: float = KitModel.mitigate(per_ev, float(est.armor), float(est.mr)) * hit
		var kill_n: int = int(ceil((victim.hp + victim.shield) / maxf(1.0, per))) if victim.is_hero else 99
		var n: int = base_n
		var finish: bool = kill_n <= hi
		if finish:
			n = clampi(kill_n, lo, hi)
		var why: String = ""
		if adjacent and n > lo:
			n = lo
			why = "근접 위협: 충전 없음"
		elif pressed and n > lo + 1:
			n = lo + 1
			why = "위험: 짧은 충전"
		var charge_t: float = sim.kits.cast_time_for(u, a, {"charge": n})
		var ev: Dictionary = b._enemy_value(u, a, victim, ctx, hit, float(n))
		var kill: bool = float(ev.kill) > 0.0
		var cost: float = fuel_cost(b, u, float(n), 2)
		if kill:
			# A finishing volley outweighs the bank.
			var plain: float = float(n) * CHARGE_FUEL
			cost = plain + maxf(0.0, cost - plain) * 0.15
		var v: float = float(ev.value) * appr - cost
		v -= float(ctx.danger) * float(ctx.risk_w) * charge_t * (0.45 if adjacent else 0.25)
		v -= b._cost(u, a, ctx)
		var label: String = "%s ×%d → %s" % [a.name, n, e.def.name]
		if victim != e:
			label += " (선행 피격: %s)" % victim.def.name
		elif dist > need:
			label += " (접근)"
		var notes: Array = []
		if why != "":
			notes.append(why)
		if surplus < lo and not kill:
			# Fewer than two missiles above the bank: hold them unless they kill.
			v = minf(v, -20.0)
			notes.append("제노사이드 연료 비축")
		out.append({"value": v, "key": "a%d:%d" % [i, e.idx], "label": label, "notes": notes,
			"parts": {"피해": ev.dmg, "처치": ev.kill, "명중": hit, "충전": n, "연료": cost},
			"cmd": {"kind": "ability", "index": i, "ability_id": a.id, "target": e.idx, "pos": e.pos, "need": need,
				"extra": {"charge": n}}})


# S3 아크 프로텍터: the cut plus the arc shield against the damage predicted
# for its 3 s; held while little is coming unless the war machine dives in.
static func _arc_protector(b: TacticianBrain, u: BUnit, i: int, a: Defs.AbilityDef, ctx: Dictionary, out: Array) -> void:
	var sim: BattleSim = b.sim
	var ev: Dictionary = KitModel.evaluate(a.effects, ctx.st, {})
	var horizon: float = maxf(1.0, float(ev.guard_dur))
	var inc: float = incoming(b, u, horizon)
	var v: float = KitModel.guard_value(ev, inc)
	# The 3 s danger model counts every nearby threat's full output; the guard
	# waits until that is a real share of the effective HP.
	var press: float = clampf((inc - float(ctx.ehp) * GUARD_FLOOR) / maxf(1.0, float(ctx.ehp) * 0.3), 0.0, 1.0)
	v *= press * clampf(float(ctx.risk_w), 0.6, 1.6)
	var nearest: float = INF
	var close: int = 0
	for t in ctx.targets:
		var e: TeamIntel.EnemyBelief = t
		if not e.is_hero:
			continue
		var d: float = u.pos.distance_to(e.pos) - float(ctx.r) - e.radius
		nearest = minf(nearest, d)
		if d < 320.0:
			close += 1
	var lbl: String = a.name
	if _diving(b, u, ctx, nearest, close):
		v += 30.0 + KitModel.guard_value(ev, incoming(b, u, 1.0)) * 0.5
		lbl += " (진입)"
	elif sim.get_buff(u, &"damageTaken") != null:
		v -= 40.0
	v -= b._cost(u, a, ctx)
	if v > 0.0 or nearest < 260.0:
		out.append({"value": v, "key": "a%d:self" % i, "label": lbl, "parts": {"예상 피해": inc, "가치": v},
			"cmd": {"kind": "ability", "index": i, "ability_id": a.id, "pos": u.pos, "need": 0.0}})


# Entering a fight: an enemy hero just outside basic reach with others behind
# it, while the team pushes in (or the war machine already boosts in).
static func _diving(b: TacticianBrain, u: BUnit, ctx: Dictionary, nearest: float, close: int) -> bool:
	if nearest > float(ctx.range) + 150.0 or nearest < float(ctx.range) - 10.0:
		return false
	if close < 2:
		return false
	return bool(b.plan.get("go", false)) or str(b.plan.get("stance", "")) == "ENGAGE"


# S4 제노사이드: a 380 x 90 strip from the war machine along the aim. Aims at
# each enemy hero (lead position) and between pairs; each enemy in the strip is
# worth its zone value (kit_model, 30% of the ticks) times its chance to still
# be inside after the 0.6 s public telegraph, more when slowed or rooted.
static func _genocide(b: TacticianBrain, u: BUnit, i: int, a: Defs.AbilityDef, ctx: Dictionary, out: Array) -> void:
	var length: float = S4_LENGTH
	var width: float = S4_WIDTH
	for f in a.effects:
		if str(f.get("type", "")) == "zone" and f.get("originRect", false):
			length = float(f.get("length", length))
			width = float(f.get("width", width))
	var dirs: Array = []
	var pts: Array = []
	for t in ctx.targets:
		var e: TeamIntel.EnemyBelief = t
		if not e.is_hero or e.has_status("untargetable"):
			continue
		var p: Vector2 = b.lead_point(u.pos, e, 0.0, a.cast_time + 0.25, 0.8)
		if u.pos.distance_to(p) > length + e.radius + 40.0 or p.distance_squared_to(u.pos) < 1.0:
			continue
		pts.append(p)
		dirs.append((p - u.pos).normalized())
	for x in pts.size():
		for y in range(x + 1, pts.size()):
			var d1: Vector2 = dirs[x]
			var d2: Vector2 = dirs[y]
			if absf(d1.angle_to(d2)) < 0.7:
				dirs.append((d1 + d2).normalized())
	if dirs.is_empty():
		return
	var cost: float = fuel_cost(b, u, S4_FUEL, 4)
	# Standing through the 0.6 s windup only matters when the damage around
	# is near lethal (the same threshold as the tactician's survival check).
	var still: float = maxf(0.0, float(ctx.danger) - float(ctx.ehp) * 0.45) * float(ctx.risk_w) * a.cast_time
	var seen: Dictionary = {}
	for d0 in dirs:
		var d: Vector2 = d0
		var key: int = int(roundf(d.angle() * 20.0))
		if seen.has(key):
			continue
		seen[key] = true
		var sv: Dictionary = strip_value(b, u, a, u.pos, d, length, width, ctx)
		if int(sv.hits) == 0:
			continue
		var v: float = float(sv.value) - cost - still - b._cost(u, a, ctx)
		out.append({"value": v, "key": "a%d:%d" % [i, key], "label": "%s (%d명)" % [a.name, int(sv.hits)],
			"parts": {"범위": sv.value, "연료": cost}, "notes": sv.notes,
			"cmd": {"kind": "ability", "index": i, "ability_id": a.id, "pos": u.pos + d * minf(200.0, a.range), "need": a.range + float(ctx.r)}})


# Value of a genocide strip from `origin` along `dir`.
static func strip_value(b: TacticianBrain, u: BUnit, a: Defs.AbilityDef, origin: Vector2, dir: Vector2, length: float, width: float, ctx: Dictionary) -> Dictionary:
	var sim: BattleSim = b.sim
	var end: Vector2 = origin + dir * length
	var total: float = 0.0
	var hits: int = 0
	var notes: Array = []
	for t in ctx.targets:
		var e: TeamIntel.EnemyBelief = t
		if e.has_status("untargetable"):
			continue
		var p: Vector2 = b.lead_point(origin, e, 0.0, a.cast_time, 0.8)
		var near: Vector2 = Geometry2D.get_closest_point_to_segment(p, origin, end)
		var margin: float = width * 0.5 + e.radius - p.distance_to(near)
		if margin <= -12.0:
			continue
		if not sim.arena.line_of_sight(near, p, 1.0):
			continue
		# The line telegraph is public: a free enemy steps out sideways.
		var lock: float = e.movement_lock_remaining()
		var move_t: float = maxf(0.0, a.cast_time - 0.22 - lock)
		var esc: float = e.ms() * move_t * (0.35 + 0.65 * e.dodge_rate())
		var hp: float = 0.9
		if margin <= 0.0:
			hp = 0.15
		elif esc > margin:
			hp = clampf(margin / esc, 0.1, 0.9)
		# Rooted / stunned past the windup: ticks while held; slowed: longer.
		var stay: float = ZONE_STAY
		var held: float = maxf(0.0, lock - a.cast_time)
		if held > 0.0:
			stay = minf(1.0, stay + held / 4.0 * (1.0 - ZONE_STAY) * 2.0)
		if e.has_status("slow"):
			stay = minf(1.0, stay + 0.15)
		elif e.is_hero and e.def.preferred_range < 120.0 and origin.distance_to(p) - e.radius - float(ctx.r) <= e.def.stat("attackRange") + 30.0:
			# A melee enemy trading blows at the strip's root tends to stay.
			stay = maxf(stay, 0.45)
		if stay > ZONE_STAY + 0.01 and e.is_hero:
			notes.append("둔화·속박 대상 %s" % e.def.name)
		total += float(b._enemy_value(u, a, e, ctx, hp, stay / ZONE_STAY).value)
		if e.is_hero:
			hits += 1
	return {"value": total, "hits": hits, "notes": notes}


# TacticianBrain._buff_value dispatch for the V2 buff stats damageTaken and
# arcConvert (also when another path values them one buff at a time).
static func buff_value(b: TacticianBrain, u: BUnit, f: Dictionary, fighting: bool) -> float:
	var ev: Dictionary = KitModel.evaluate([f], KitModel.stats_of_unit(b.sim, u), {})
	var inc: float = b.danger_at(u, u.pos, maxf(1.0, float(f.get("duration", 3.0))))
	return KitModel.guard_value(ev, inc) * (1.0 if fighting else 0.3)


# ------------------------------------------------------------------ doctrine

# Doctrine.adjust branch for the war machine's own candidates.
static func adjust(b: TacticianBrain, u: BUnit, ctx: Dictionary, c: Dictionary, kind: String, _a: Defs.AbilityDef, e: TeamIntel.EnemyBelief) -> void:
	if not own_planning:
		return
	var sim: BattleSim = b.sim
	var od: bool = overdrive(sim, u)
	match kind:
		"basic":
			if e == null:
				return
			if od:
				Doctrine._note(c, maxf(0.0, float(c.value)) * 0.4 + 18.0, "과열 폭주: 평타 올인")
				return
			var tu: BUnit = sim.u_at(e.idx)
			if fuel(u) < FUEL_CAP - 0.5 and sim.kits.tank_attached(u) and tu and (tu.is_hero or not tu.structure):
				Doctrine._note(c, CHARGE_FUEL * 1.5, "평타 연료 충전")
		"move":
			if not od or float(ctx.hpr) < 0.25:
				return
			# All-in: in overdrive the war machine does not back off a fight.
			var foe: TeamIntel.EnemyBelief = null
			var best: float = 420.0
			for t in ctx.strike:
				var x: TeamIntel.EnemyBelief = t
				if x.is_hero and u.pos.distance_to(x.pos) < best:
					best = u.pos.distance_to(x.pos)
					foe = x
			if foe == null:
				return
			var goal: Vector2 = c.cmd.get("goal", u.pos)
			var back: float = goal.distance_to(foe.pos) - best
			if back > 30.0:
				Doctrine._note(c, - minf(60.0, back * 0.3), "과열 폭주: 후퇴 자제")


# Doctrine.adjust hook run for every hero: a basic attack on an enemy war
# machine's fuel tank is worth the tank's pop value times the share of its
# remaining HP the hit removes.
static func enemy_notes(b: TacticianBrain, u: BUnit, _ctx: Dictionary, cands: Array) -> void:
	if u.team != b.team:
		return
	var any: bool = false
	for k in b.intel.entities:
		if (b.intel.entities[k] as TeamIntel.EnemyBelief).kind == "fuel_tank":
			any = true
			break
	if not any:
		return
	for c: Dictionary in cands:
		var cmd: Dictionary = c.cmd
		if str(cmd.get("kind", "")) != "basic":
			continue
		var tank: TeamIntel.EnemyBelief = b.intel.entities.get(int(cmd.get("target", -1)))
		if tank == null or tank.kind != "fuel_tank":
			continue
		var dmg: float = float((c.get("parts", {}) as Dictionary).get("피해", 0.0))
		Doctrine._note(c, tank_hit_value(b, tank, dmg), "연료탱크 파괴 가치")


# TacticianBrain._enemy_value dispatch: extra value of `dmg` on a seen tank.
static func tank_hit_value(b: TacticianBrain, tank: TeamIntel.EnemyBelief, dmg: float) -> float:
	if tank == null or dmg <= 0.0:
		return 0.0
	var owner: TeamIntel.EnemyBelief = b.intel.enemies.get(tank.owner_idx)
	if owner == null or owner.dead:
		return 0.0
	var share: float = clampf(dmg / maxf(1.0, tank.hp), 0.0, 1.0)
	return tank_pop_value(b, owner) * share


# Breaking the tank: denies the believed fuel (genocide when 7+) and locks
# S2-S4 for the overdrive, but frees 10 s of x1.5 attack and move speed. An
# ally the overdrive burst could kill makes it a clear loss.
static func tank_pop_value(b: TacticianBrain, owner: TeamIntel.EnemyBelief) -> float:
	var sim: BattleSim = b.sim
	var intel: TeamIntel = b.intel
	var f: float = intel.fuel_now(owner)
	var deny: float = f * 8.0
	if f >= S4_FUEL and owner.def.abilities.size() >= 4:
		deny += 150.0 * maxf(0.35, intel.ready_prob(owner, 3)) + 20.0 * (f - S4_FUEL)
	var lock: float = 0.0
	if owner.def.abilities.size() >= 3:
		lock = intel.ready_prob(owner, 1) * 35.0 + intel.ready_prob(owner, 2) * 45.0
	var dps: float = float(KitModel._enemy_base(owner.def).dps)
	var r: Dictionary = owner.def.rule("fuel_tank") if owner.def.has_rule("fuel_tank") else {}
	var mult: float = float(r.get("overdriveMult", OVERDRIVE_MULT))
	var od_threat: float = dps * (mult - 1.0) * 6.0
	var reach: float = owner.def.stat("moveSpeed") * mult * 2.0 + 60.0
	var burst: float = dps * 1.3 * mult * 4.0
	var kill_risk: float = 0.0
	for a: BUnit in b.allies_cache:
		if not a.alive or a.pos.distance_to(owner.pos) > reach:
			continue
		var ehp: float = a.hp + sim.shield_amount(a)
		if ehp < burst * 100.0 / (100.0 + sim.stat(a, &"armor")):
			kill_risk += 260.0 + float(b.aprof.get(a.idx, {}).get("contrib", 60.0))
	return deny + lock - od_threat - kill_risk


# ------------------------------------------------------------------ danger

# TacticianBrain._danger_raw dispatch for a seen rect zone (genocide strip):
# inside when the point is within width/2 + r of the strip's segment.
static func rect_zone_danger(z: Dictionary, p: Vector2, r: float, horizon: float) -> float:
	var a: Vector2 = z.get("data_a", z.pos)
	var e: Vector2 = z.get("data_b", z.pos)
	var near: Vector2 = Geometry2D.get_closest_point_to_segment(p, a, e)
	if p.distance_to(near) > float(z.radius) + r:
		return 0.0
	return 36.0 * horizon


# ------------------------------------------------------------------ draft

# DraftDirector.kit_features lines: the director counts one shot per cast and
# prices only heal/shield effects, so add the mid charge of S2, the S3 guard
# (as shield per second against ~60 dps) and the 2.5 s booster's reach.
static func draft_features(d: Defs.CharDef) -> Dictionary:
	var out: Dictionary = {"spell": 0.0, "shield": 0.0, "mobility": 0.0}
	var st: Dictionary = KitModel.stats_of_def(d)
	for a0 in d.abilities:
		var a: Defs.AbilityDef = a0
		var cd: float = maxf(0.25, a.cooldown)
		var ev: Dictionary = KitModel.evaluate(a.effects, st, {})
		if not a.flag("originCharge", {}).is_empty():
			var per: float = float(ev.phys) + float(ev.magic) + float(ev.true_dmg)
			var gate: float = 0.55 if not a.condition.is_empty() else 1.0
			out.spell = float(out.spell) + per * float(KitModel.charge_count(a) - 1) * gate / cd
		if float(ev.guard) > 0.0 or float(ev.arc) > 0.0:
			var taken: float = 60.0 * maxf(1.0, float(ev.guard_dur))
			out.shield = float(out.shield) + KitModel.guard_value(ev, taken) / cd
		if float(ev.mobility) > 0.0 and a.cooldown <= 3.0:
			out.mobility = float(out.mobility) + 0.2
	return out
