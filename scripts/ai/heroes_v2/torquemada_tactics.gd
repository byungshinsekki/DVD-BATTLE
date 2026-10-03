class_name TorquemadaTactics
extends RefCounted

# V2 토르케마다 (torquemada) tactical AI (DESIGN_V2 §2.4, §2.7). TacticianBrain,
# Doctrine and KitModel only dispatch here.
# - Cleanse value: own allies' (and his own) removable crowd control, weighted
#   by what the unit loses while it lasts, plus its harmful effects. Statuses of
#   our own team are legitimately known; enemies are read from beliefs only.
# - S1 아우토다페: a fire placed over the allies it would actually cleanse at
#   its first tick, kept in reserve while the enemy engages with no control up.
# - S3 알람브라 칙령: cleanse within 150 plus the knockback peel of enemies
#   there that threaten us (Defs marks the ability non-hostile; it is valued
#   here instead of the generic self-area path).
# - S2 형사 절차 지침: the generic enemy path (observed targets, ccSourceWithin
#   via check_condition) values the 1.25 s root; divers, carries and an expiring
#   record add to it.

const ID: = "torquemada"
const FIRE: = 1
const VERDICT: = 2
const EDICT: = 3
# Fraction of a unit's fighting value lost per second of each crowd control the
# cleanse removes. Slow is priced as a debuff; control turns the unit to the
# enemy team, out of reach of an allied cleanse.
const CC_WEIGHT: = {"stun": 1.0, "airborne": 1.0, "suppression": 1.0, "sleep": 1.0, "charm": 1.1,
	"taunt": 1.0, "fear": 1.0, "root": 0.6, "silence": 0.45, "disarm": 0.4, "grounded": 0.15}
const MOVE_LOCK: = [&"stun", &"root", &"airborne", &"suppression", &"sleep"]
const FIRE_MIN: = 30.0
const EDICT_MIN: = 35.0
const PUSH: = 140.0


# ------------------------------------------------------------- cleanse value

# Per second of crowd control removed: the unit's damage, support and the
# incoming danger it could answer or escape once free.
static func threat_value(b: TacticianBrain, x: BUnit) -> float:
	var ap: Dictionary = b.aprof.get(x.idx, {})
	var danger: float = minf(b.danger_at(x, x.pos, 1.0), x.hp + b.sim.shield_amount(x))
	return float(ap.get("dps", 40.0)) * 1.1 + float(ap.get("burst", 0.0)) * 0.25 + float(ap.get("support", 0.0)) * 1.5 + 40.0 + danger * 0.35


# What a cleanse landing on x `delay` seconds from now removes, valued.
# Mirrors BattleSim.cleanse: every crowd control and harmful status without a
# chamber or motion tie, enemy damage over time and enemy stat debuffs.
static func unit_value(b: TacticianBrain, x: BUnit, delay: float) -> Dictionary:
	var sim: BattleSim = b.sim
	var at: float = sim.time + delay
	var team: int = sim.eteam(x)
	var hard: float = 0.0
	var deb: float = 0.0
	var n: int = 0
	var danger: float = -1.0
	var hpr: float = sim.hp_ratio(x)
	for st: ST.Status in x.statuses:
		if st.end <= at or st.extra.has("chamber") or st.extra.has("motion_id"):
			continue
		var rem: float = st.end - at
		var ty: String = String(st.type)
		if CC_WEIGHT.has(ty):
			var w: float = float(CC_WEIGHT[ty])
			if ty == "root":
				w = 0.75 if x.def.preferred_range < 120.0 else 0.45
			hard = maxf(hard, rem * w)
			n += 1
		elif ty == "slow":
			deb += clampf(st.magnitude if st.magnitude > 0.0 else 0.3, 0.0, 0.9) * minf(rem, 4.0) * 30.0
			n += 1
		elif ty in ["damageAmp", "sniperVulnerable", "confusion"]:
			var amp: float = float(st.extra.get("damageAmp", 0.0))
			if ty == "confusion" and amp == 0.0:
				amp = 0.03
			if ty == "damageAmp" and amp == 0.0:
				amp = maxf(0.0, st.magnitude)
			if danger < 0.0:
				danger = b.danger_at(x, x.pos, 1.0)
			# danger_at assumes every enemy in reach commits; half of it lands.
			deb += amp * st.stacks * minf(rem, 5.0) * (danger * 0.5 + 25.0)
			if ty == "confusion":
				# Joker's flip consumes the stacks for burst damage.
				deb += st.stacks * 10.0
			n += 1
		elif ty in ["healReduction", "plague"]:
			var red: float = minf(0.6, st.stacks * 0.1) if ty == "plague" else (st.magnitude if st.magnitude > 0.0 else 0.35)
			deb += red * minf(rem, 5.0) * (6.0 + 22.0 * (1.0 - hpr))
			if ty == "plague":
				deb += st.stacks * 4.0
			n += 1
		elif ty == "pain":
			# Slows per stack and opens the torturer's gag at 3 stacks.
			deb += st.stacks * 7.0 + (25.0 if st.stacks >= 3 else 0.0)
			n += 1
		elif ty == "roar":
			deb += float(st.extra.get("tenacityLoss", 0.1)) * 150.0 * minf(rem, 6.0) / 6.0
			n += 1
		elif ty == "dot":
			var src: BUnit = sim.u_at(st.source_idx)
			if src == null or sim.eteam(src) == team or st.interval <= 0.0 or st.dmg.is_empty():
				continue
			var ticks: float = floorf(rem / st.interval) + 1.0
			var est: Dictionary = KitModel._enemy_base(src.def).st if src.is_hero else {"ad": 40.0, "ap": 40.0}
			var per: float = KitModel.mitigate(KitModel.evaluate([st.dmg], est, {}), sim.stat(x, &"armor"), sim.stat(x, &"magicResistance"))
			deb += per * ticks * 0.9
			n += 1
	for bf: ST.Buff in x.buffs:
		if bf.end <= at:
			continue
		var src2: BUnit = sim.u_at(bf.source_idx)
		if src2 == null or sim.eteam(src2) == team:
			continue
		if bf.stat == &"originStatSwap":
			deb += 40.0
			n += 1
		elif bf.amount < 0.0:
			var rem2: float = minf(bf.end - at, 5.0)
			var amt: float = absf(bf.amount)
			# Fractional stat debuffs scale the unit's output, flat ones are points.
			deb += amt * rem2 * (float(b.aprof.get(x.idx, {}).get("dps", 40.0)) + 25.0) if amt <= 2.0 else amt * rem2 * 0.8
			n += 1
	var value: float = deb
	if hard > 0.0:
		value += hard * threat_value(b, x)
	return {"value": value, "hard": hard, "debuff": deb, "n": n}


# Where a unit will stand when the cleanse lands: movement-locked units stay.
static func predicted(b: TacticianBrain, x: BUnit, delay: float) -> Vector2:
	if b.sim.has_any(x, MOVE_LOCK):
		return x.pos
	return x.pos + x.vel * minf(delay, 0.5)


static func pool(u: BUnit, ctx: Dictionary) -> Array[BUnit]:
	var out: Array[BUnit] = [u]
	for x: BUnit in ctx.allies:
		if x.alive:
			out.append(x)
	return out


# Ready-weighted crowd-control seconds of visible enemy heroes closing on us.
static func pending_cc(b: TacticianBrain, u: BUnit, ctx: Dictionary) -> float:
	var total: float = 0.0
	for t in ctx.targets:
		var e: TeamIntel.EnemyBelief = t
		if not e.is_hero:
			continue
		var pr: Dictionary = b.eprof.get(e.idx, {})
		var cc: float = float(pr.get("cc", 0.0)) * float(pr.get("w", 1.0))
		if cc <= 0.05:
			continue
		var reach: float = float(pr.get("reach", 200.0)) + 220.0
		var near: bool = e.pos.distance_to(u.pos) <= reach
		for x: BUnit in ctx.allies:
			near = near or e.pos.distance_to(x.pos) <= reach
		if near:
			total += cc
	return total


# DESIGN §2.7: during an enemy engage window with no control up yet, a cleanse
# spent on minor debuffs is missing when the stuns land.
static func reserve_cost(b: TacticianBrain, u: BUnit, ctx: Dictionary) -> float:
	var engaging: bool = bool(ctx.engaged) or bool(b.plan.get("fighting", false)) or str(b.plan.stance) == "ENGAGE"
	if not engaging:
		return 0.0
	var pending: float = pending_cc(b, u, ctx)
	if pending < 0.6:
		return 0.0
	return 30.0 + 35.0 * minf(pending, 3.0)


# ----------------------------------------------------------- S1 아우토다페

static func fire_candidates(b: TacticianBrain, u: BUnit, i: int, a: Defs.AbilityDef, ctx: Dictionary, out: Array) -> void:
	var sim: BattleSim = b.sim
	var r: float = ctx.r
	var base_delay: float = a.cast_time + 0.05
	var rows: Array = []
	var any_hard: bool = false
	for x in pool(u, ctx):
		var uv: Dictionary = unit_value(b, x, base_delay)
		if int(uv.n) == 0 or float(uv.value) <= 0.5:
			continue
		rows.append({"u": x, "p": predicted(b, x, base_delay), "uv": uv})
		any_hard = any_hard or float(uv.hard) > 0.0
	if rows.is_empty():
		return
	# Centres: every unit to cleanse, and the midpoint of each close pair.
	var centers: Array = []
	for row: Dictionary in rows:
		centers.append(row.p)
	for j in rows.size():
		for k in range(j + 1, rows.size()):
			var pj: Vector2 = rows[j].p
			var pk: Vector2 = rows[k].p
			if pj.distance_to(pk) <= a.radius * 2.0:
				centers.append((pj + pk) * 0.5)
	var reserve: float = 0.0 if any_hard else reserve_cost(b, u, ctx)
	var seen: Dictionary = {}
	for c0 in centers:
		var center: Vector2 = sim.arena.resolve_circle(c0, 8.0)
		var key: String = "a%d:%d:%d" % [i, int(center.x / 20), int(center.y / 20)]
		if seen.has(key):
			continue
		seen[key] = true
		var dist: float = u.pos.distance_to(center)
		var need: float = a.range + r
		var appr: float = b._approach_factor(u, dist, need, ctx)
		if appr <= 0.02:
			continue
		var delay: float = base_delay + maxf(0.0, dist - need) / maxf(30.0, float(ctx.ms))
		var total: float = 0.0
		var covered: int = 0
		var hard_n: int = 0
		for row: Dictionary in rows:
			var x: BUnit = row.u
			var xp: Vector2 = row.p if delay <= base_delay + 0.01 else predicted(b, x, delay)
			if xp.distance_to(center) > a.radius + sim.radius(x) - 4.0 or not sim.los(center, xp, 1.0):
				continue
			var uv2: Dictionary = row.uv if delay <= base_delay + 0.01 else unit_value(b, x, delay)
			total += float(uv2.value)
			covered += 1
			if float(uv2.hard) > 0.0:
				hard_n += 1
		if covered == 0:
			continue
		var v: float = total * appr - b._cost(u, a, ctx) - reserve
		if v <= FIRE_MIN:
			continue
		var label: String = "%s (정화 %d명%s)" % [a.name, covered, ", 제어 %d" % hard_n if hard_n > 0 else ""]
		var parts: Dictionary = {"정화": total, "인원": covered}
		if reserve > 0.0:
			parts["보존"] = -reserve
		out.append({"value": v, "key": key, "label": label, "parts": parts,
			"cmd": {"kind": "ability", "index": i, "ability_id": a.id, "pos": center, "need": need}})


# ------------------------------------------------------- S3 알람브라 칙령

# First collision along the actual push. Use observed body positions only:
# an unseen blocker must not leak into the planner, even when the engine
# will later stop the motion there. Teams are read only for visible bodies.
static func edict_landing(b: TacticianBrain, e: TeamIntel.EnemyBelief, start: Vector2, end: Vector2) -> Vector2:
	var contact: Dictionary = b.sim.arena.terrain_contact(start, end, e.radius, false)
	var hit_t: float = float(contact.t) if not contact.is_empty() else 1.0
	var target: BUnit = b.sim.u_at(e.idx)
	if target == null or not e.visible:
		return start.lerp(end, hit_t)
	var team: int = b.sim.eteam(target)
	var bodies: Array = b.intel.enemies.values() + b.intel.entities.values()
	bodies.sort_custom(func(x: TeamIntel.EnemyBelief, y: TeamIntel.EnemyBelief): return x.idx < y.idx)
	for item in bodies:
		var body: TeamIntel.EnemyBelief = item
		if body.idx == e.idx or not body.visible or body.dead:
			continue
		var unit: BUnit = b.sim.u_at(body.idx)
		if unit == null or b.sim.eteam(unit) != team:
			continue
		var t: float = Arena.seg_circle_t(start, end, body.pos, e.radius + body.radius)
		if t >= 0.0 and t < hit_t:
			hit_t = t
	return start.lerp(end, hit_t)


# Knockback peel, judged on where each enemy lands (pushed straight away from
# torquemada, 140): the time it needs to walk back into reach of the unit of
# ours it threatens most, minus the contact our own melee (torquemada
# included) loses on it. An enemy between him and an ally is pushed onto that
# ally, which costs instead. Torquemada himself only counts as the threatened
# unit when hurt (tenacity and armour make him the one to stay hit).
static func edict_peel(b: TacticianBrain, u: BUnit, a: Defs.AbilityDef, ctx: Dictionary, delay: float) -> Dictionary:
	var sim: BattleSim = b.sim
	var v: float = 0.0
	var hits: int = 0
	var carry: int = int(b.plan.get("carry", -1))
	var peel_threats: Dictionary = b.plan.get("peel_threats", {})
	var ours: Array[BUnit] = pool(u, ctx)
	for t in ctx.targets:
		var e: TeamIntel.EnemyBelief = t
		if not e.is_hero:
			continue
		if e.has_status("unstoppable") or e.has_status("invulnerable") or e.has_status("untargetable") or e.has_status("contemplation"):
			continue
		var pred: Vector2 = b.lead_point(u.pos, e, 0.0, delay, 0.7)
		if pred.distance_to(u.pos) > a.radius + e.radius - 4.0 or not sim.los(u.pos, pred, 1.0):
			continue
		var away: Vector2 = pred - u.pos
		away = away.normalized() if away.length_squared() > 1.0 else u.facing
		var land: Vector2 = edict_landing(b, e, pred, pred + away * PUSH)
		var pr: Dictionary = b.eprof.get(e.idx, {})
		var dps: float = float(pr.get("dps", 50.0)) + float(pr.get("burst", 0.0)) * 0.15
		var ms_e: float = maxf(60.0, e.ms())
		var melee: bool = e.def.preferred_range < 120.0
		var protect: float = 0.0
		var onto: float = 0.0
		var lost: float = 0.0
		for x in ours:
			var rx: float = sim.radius(x)
			var reach: float = float(pr.get("range", 60.0)) + e.radius + rx + 35.0
			var d_now: float = pred.distance_to(x.pos)
			var d_after: float = land.distance_to(x.pos)
			var w: float = 1.0 + 0.6 * (1.0 - sim.hp_ratio(x))
			if x == u:
				w = 0.25 + maxf(0.0, 0.6 - sim.hp_ratio(u)) * 4.0
			else:
				if x.idx == carry:
					w += 0.3
				if bool(b.aprof.get(x.idx, {}).get("backline", false)):
					w += 0.3
			if peel_threats.has(e.idx) and x != u:
				w += 0.4
			if melee:
				if d_now <= reach + 40.0:
					protect = maxf(protect, dps * clampf((d_after - reach) / ms_e, 0.0, 2.2) * w)
				if d_after < d_now - 20.0 and d_after <= reach + 20.0:
					onto = maxf(onto, dps * 1.2 * w)
			elif x != u and bool(b.aprof.get(x.idx, {}).get("backline", false)) and d_now <= 120.0 and d_after > d_now + 60.0:
				# A ranged diver on our backline is pushed out of its face.
				protect = maxf(protect, dps * 0.5 * w)
			# Our melee loses contact with it for the push over its own speed.
			if x.def.preferred_range < 120.0:
				var contact: float = sim.stat(x, &"attackRange") + rx + e.radius + 25.0
				if d_now <= contact and d_after > contact:
					var xdps: float = float(b.aprof.get(x.idx, {}).get("dps", 40.0))
					if x == u:
						# Badly hurt, he wants the distance, not the contact.
						xdps *= clampf((sim.hp_ratio(u) - 0.3) / 0.4, 0.0, 1.0)
					lost += xdps * clampf((d_after - contact) / maxf(60.0, sim.stat(x, &"moveSpeed")), 0.0, 2.0) * 0.9
		var gain: float = protect - onto - lost
		if e.has_status("frontGuard") and gain > 0.0:
			gain *= 0.4
		# The focus target pushed away from our hitters escapes.
		if ctx.focus and (ctx.focus as TeamIntel.EnemyBelief).idx == e.idx:
			gain -= 25.0 + (40.0 if e.hp / maxf(1.0, e.max_hp) < 0.25 else 0.0)
		v += gain
		hits += 1
	return {"value": v, "hits": hits}


static func edict_candidates(b: TacticianBrain, u: BUnit, i: int, a: Defs.AbilityDef, ctx: Dictionary, out: Array) -> void:
	var sim: BattleSim = b.sim
	var delay: float = a.cast_time + 0.02
	var cleanse: float = 0.0
	var covered: int = 0
	var any_hard: bool = false
	for x in pool(u, ctx):
		var xp: Vector2 = predicted(b, x, delay)
		if xp.distance_to(u.pos) > a.radius + sim.radius(x) - 2.0 or not sim.los(u.pos, xp, 1.0):
			continue
		var uv: Dictionary = unit_value(b, x, delay)
		if int(uv.n) == 0:
			continue
		cleanse += float(uv.value)
		covered += 1
		any_hard = any_hard or float(uv.hard) > 0.0
	if not any_hard and cleanse > 0.0:
		cleanse = maxf(0.0, cleanse - reserve_cost(b, u, ctx))
	var peel: Dictionary = edict_peel(b, u, a, ctx, a.cast_time)
	var pv: float = float(peel.value)
	var v: float = cleanse + pv - b._cost(u, a, ctx)
	var notes: Array = []
	# The fire (cd 13) cleanses the same allies; keep the edict (cd 17) for the
	# peel unless both are wanted now.
	if cleanse > 0.0 and pv < 30.0 and Doctrine._ready(b, u, FIRE):
		var keep: float = cleanse * 0.35 + 15.0
		v -= keep
		notes.append("아우토다페로 충분 %+.0f" % -keep)
	if v <= EDICT_MIN:
		return
	var label: String = "%s (정화 %d, 밀침 %d)" % [a.name, covered, int(peel.hits)]
	out.append({"value": v, "key": "a%d:self" % i, "label": label, "parts": {"정화": cleanse, "견제": pv}, "notes": notes,
		"cmd": {"kind": "ability", "index": i, "ability_id": a.id, "pos": u.pos, "need": 0.0}})


# -------------------------------------------------- S2 형사 절차 지침

# Extra value of the retaliatory root over the generic root (DESIGN §2.7):
# divers and carries lose most, and the self-knowledge record (ks.cc_by)
# expires after the current S2 condition window.
static func verdict_bonus(b: TacticianBrain, u: BUnit, e: TeamIntel.EnemyBelief, ctx: Dictionary) -> float:
	if not e.is_hero:
		return 0.0
	var v: float = 0.0
	var roles: Array = Doctrine.of(e.def.id).get("roles", [])
	var diver: bool = roles.has("DIVER") or roles.has("FLANKER") or roles.has("HUNTER") or roles.has("ENGAGE") \
		or e.def.tags.has("ENGAGE") or (e.def.tags.has("MOBILITY") and e.def.preferred_range < 120.0)
	if diver:
		var near_back: bool = false
		for x in pool(u, ctx):
			if (x == u or bool(b.aprof.get(x.idx, {}).get("backline", false))) and e.pos.distance_to(x.pos) < 320.0:
				near_back = true
		v += 45.0 if near_back else 28.0
	if roles.has("CARRY") or roles.has("MARKSMAN") or roles.has("FINISHER"):
		var thr: float = float(b.eprof.get(e.idx, {}).get("threat", 300.0)) / maxf(1.0, float(b.plan.get("max_threat", 600.0)))
		v += 20.0 + 25.0 * clampf(thr, 0.0, 1.0)
	var cc_window: float = 0.0
	for ability: Defs.AbilityDef in b.sim.ability_list(u):
		if ability.slot == VERDICT:
			cc_window = float(ability.condition.get("ccSourceWithin", 0.0))
			break
	var by: Dictionary = u.ks.get("cc_by", {})
	if cc_window > 0.0 and by.has(e.idx):
		var age: float = b.sim.time - float(by[e.idx])
		if age >= cc_window - 2.0:
			v += 20.0 + (age - (cc_window - 2.0)) * 15.0
	if e.hard_cc_remaining() > 0.6:
		v *= 0.3
	return v


# ---------------------------------------------------------- doctrine notes

static func doctrine_adjust(b: TacticianBrain, u: BUnit, _ctx: Dictionary, c: Dictionary, kind: String, a: Defs.AbilityDef, e: TeamIntel.EnemyBelief) -> void:
	if kind != "ability" or a == null or a.virtual:
		return
	if a.slot == VERDICT and e:
		if (b.plan.get("peel_threats", {}) as Dictionary).has(e.idx):
			Doctrine._note(c, 30.0, "후열 위협자 즉결 속박")
		elif b.sim.hp_ratio(u) < 0.45 and e.def.preferred_range < 120.0 and u.pos.distance_to(e.pos) < 160.0:
			Doctrine._note(c, 20.0, "나를 제어한 근접 적 속박")


# ------------------------------------------------- enemies valuing him

# An enemy controlling torquemada: tenacity 0.35 and the charm rule shorten
# every duration (KitModel.apply_tenacity; public hero definition).
static func enemy_view(e: TeamIntel.EnemyBelief, ev: Dictionary) -> void:
	KitModel.apply_tenacity(ev, e.def)
