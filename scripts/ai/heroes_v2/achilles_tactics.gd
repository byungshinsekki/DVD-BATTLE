class_name AchillesTactics
extends RefCounted

# V2 아킬레우스 (achilles) tactical AI, DESIGN_V2 §2.5 / §2.7. Every
# achilles-specific rule lives here as a static helper; TacticianBrain,
# Doctrine, KitModel, DraftDirector and TeamIntel only hold one-line
# dispatches. Inputs are the deciding team's own beliefs (TeamIntel), its own
# heroes' state and public rules (hard rules 1 and 2: no RNG, no hidden state).
#   S1 펠리온의 창: piercing true-damage line. The generic skillshot path aims
#      it (lead point, _line_bonus for every enemy on the line); here only the
#      armour that true damage skips is added.
#   S2 헤파이스토스의 방패: raised toward the predicted frontal damage
#      (projectiles in flight, telegraphs, wind-ups aimed at him, melee and
#      ready bursts in reach); while it is up, movement keeps the main threat
#      inside the arc (the engine locks the facing).
#   S3 포효: when allied crowd control will land inside its 6 s, or right
#      before his own S4 (Doctrine orders S3 → S4).
#   S4 크산토스와 발리오스: seen enemies x knock value, best with two or more.
# Enemy side: frontal hits on a raised guard are wasted (TacticianBrain.
# _enemy_value, enemy_notes), and a seen chariot's path is danger.

const ID: = "achilles"
const GUARD_SLOT: = 2
const ROAR_SLOT: = 3
const CHARIOT_SLOT: = 4
# Crowd control that tenacity scales (sim.apply_status leaves airborne,
# suppression and control at their exact duration), weighted by how much a
# second of it is worth next to a stun.
const ROAR_CC: = {"stun": 1.0, "root": 0.9, "sleep": 1.0, "charm": 1.0, "taunt": 0.9, "silence": 0.5}
const SLOW_WEIGHT: = 0.25
# Minimum frontal value that justifies the 14 s guard (telemetry: guards
# planned below ~150 blocked something 40 % of the time, above it 60 %).
const GUARD_MIN: = 140.0
# Opportunity costs of the long cooldowns (roar 16 s, chariot 45 s).
const ROAR_COST: = 14.0
const CHARIOT_COST: = 60.0
# Knock value beyond the contact damage: 130 px of lost position.
const KNOCK_BASE: = 35.0

# Tenacity-scaled control seconds per roster ability id (pure data; virtual
# copies are never cached because their ids repeat across battles).
static var _cc_secs: Dictionary = {}


# ------------------------------------------------------------------ kit model

# KitModel._walk arms for the new effect types. Values are written under new
# keys only (read back with .get), so no existing kit changes.
static func walk_effect(f: Dictionary, out: Dictionary) -> void:
	match str(f.get("type", "")):
		"front_guard":
			out["front_guard_dur"] = maxf(float(out.get("front_guard_dur", 0.0)), float(f.get("duration", 2.0)))
			out["guard_arc"] = maxf(float(out.get("guard_arc", 0.0)), deg_to_rad(float(f.get("arcDegrees", 120.0))))
			out["guard_slow"] = maxf(float(out.get("guard_slow", 0.0)), float(f.get("moveSlow", 0.0)))
		"roar":
			out["tenacity_loss"] = maxf(float(out.get("tenacity_loss", 0.0)), float(f.get("tenacityLoss", 0.1)))
			out["roar_dur"] = maxf(float(out.get("roar_dur", 0.0)), float(f.get("duration", 6.0)))
			out["roar_reach_ffa"] = float(f.get("radiusFfa", 900.0))


# The chariot summon: per-contact damage, knocks per enemy and distance.
static func walk_chariot(f: Dictionary, per_hit: float, out: Dictionary) -> void:
	var kn: Dictionary = f.get("knock", {})
	out.displace = maxf(float(out.displace), float(kn.get("distance", 0.0)))
	out["knocks"] = float(out.get("knocks", 0.0)) + float(f.get("maxKnocks", 2)) * float(f.get("count", 1))
	out["knock_dmg"] = maxf(float(out.get("knock_dmg", 0.0)), per_hit)
	out["chariot_speed"] = float(f.get("speed", 300.0))
	out["chariot_dur"] = float(f.get("duration", 5.0))
	out["chariot_reach_ffa"] = float(f.get("rangeFfa", 900.0))


# ------------------------------------------------------------------ own skills

# TacticianBrain._self_candidates dispatch for S2/S3/S4. Returns true when the
# slot is handled here (the generic self path is then skipped).
static func self_candidates(b: TacticianBrain, u: BUnit, i: int, a: Defs.AbilityDef, ctx: Dictionary, out: Array) -> bool:
	if a.virtual:
		return false
	match a.slot:
		GUARD_SLOT:
			_guard_candidate(b, u, i, a, ctx, out)
		ROAR_SLOT:
			_roar_candidate(b, u, i, a, ctx, out)
		CHARIOT_SLOT:
			_chariot_candidate(b, u, i, a, ctx, out)
		_:
			return false
	return true


static func _guard_candidate(b: TacticianBrain, u: BUnit, i: int, a: Defs.AbilityDef, ctx: Dictionary, out: Array) -> void:
	if b.sim.get_status(u, &"frontGuard") != null:
		return
	var plan: Dictionary = guard_plan(b, u, a, ctx)
	if plan.is_empty() or float(plan.blocked) < GUARD_MIN:
		return
	var blocked: float = plan.blocked
	var v: float = blocked * 0.85
	if float(ctx.danger) > float(ctx.ehp) * 0.3:
		v *= 1.2
	# -35 % move speed for the guard: it costs a chase.
	var nearest: float = INF
	for t in ctx.targets:
		var e: TeamIntel.EnemyBelief = t
		if e.is_hero:
			nearest = minf(nearest, u.pos.distance_to(e.pos) - e.radius - float(ctx.r))
	if nearest > float(ctx.range) + 40.0:
		v -= 25.0
	v -= 35.0 + b._cost(u, a, ctx)
	if v <= 0.0:
		return
	var dir: Vector2 = plan.dir
	out.append({"value": v, "key": "a%d:guard" % i, "label": "%s (정면 차단 %.0f)" % [a.name, blocked],
		"parts": {"차단": blocked, "예상 피해": plan.total},
		"cmd": {"kind": "ability", "index": i, "ability_id": a.id, "pos": u.pos + dir * 60.0, "need": 0.0}})


# Guard direction and the frontal value it stops: {dir, blocked, total, dur}.
static func guard_plan(b: TacticianBrain, u: BUnit, a: Defs.AbilityDef, ctx: Dictionary) -> Dictionary:
	var ev: Dictionary = KitModel.evaluate(a.effects, ctx.st, {})
	var dur: float = float(ev.get("front_guard_dur", 2.0))
	var arc: float = float(ev.get("guard_arc", deg_to_rad(120.0)))
	var rows: Array = guard_threats(b, u, a, ctx, dur)
	if rows.is_empty():
		return {}
	var dirs: Array[Vector2] = []
	var mean: Vector2 = Vector2.ZERO
	var total: float = 0.0
	for row in rows:
		var rd: Vector2 = row[0]
		total += float(row[1])
		if rd != Vector2.ZERO:
			dirs.append(rd)
			mean += rd * float(row[1])
	if mean.length() > 0.001:
		dirs.append(mean.normalized())
	if dirs.is_empty():
		dirs.append(u.facing)
	# A small margin: the sources move during the 2 s.
	var edge: float = cos(arc * 0.5 - 0.12)
	var best_dir: Vector2 = dirs[0]
	var best_v: float = -1.0
	for d in dirs:
		var v: float = 0.0
		for row in rows:
			var rd2: Vector2 = row[0]
			if rd2 == Vector2.ZERO:
				v += float(row[1]) * 0.5
			elif rd2.dot(d) >= edge:
				v += float(row[1])
		if v > best_v + 1e-6:
			best_v = v
			best_dir = d
	return {"dir": best_dir, "blocked": best_v, "total": total, "dur": dur}


# Frontal threats within the guard window as [unit direction toward the
# source, expected value]. The guard stops projectiles, direct hits, crowd
# control and knockbacks from the front; zone ticks and DoT pass.
static func guard_threats(b: TacticianBrain, u: BUnit, a: Defs.AbilityDef, ctx: Dictionary, window: float) -> Array:
	var rows: Array = []
	var r: float = ctx.r
	var up: float = a.cast_time + 0.02
	for pj in b.intel.projectiles:
		var vel: Vector2 = pj.vel
		var sp: float = vel.length()
		if sp < 1.0:
			continue
		var ppos: Vector2 = pj.pos
		var rel: Vector2 = u.pos - ppos
		var eta: float = 0.0
		var from: Vector2 = -vel / sp
		if pj.homing:
			if int(pj.target) != u.idx:
				continue
			eta = rel.length() / sp
			from = -rel.normalized() if rel.length() > 1.0 else from
		else:
			var along: float = rel.dot(vel) / sp
			if along <= 0.0 or (ppos + vel / sp * along).distance_to(u.pos) > float(pj.radius) + r + 6.0:
				continue
			eta = along / sp
		if eta < up or eta > window:
			continue
		rows.append([from, float(pj.dmg) * (1.5 if pj.cc else 1.0)])
	for tg in b.intel.telegraphs:
		if bool(tg.get("env", false)):
			continue
		var due: float = float(tg.due) - b.sim.time
		if due < up or due > window or not b._in_telegraph(u.pos, r, tg):
			continue
		var src: Vector2 = tg.to if str(tg.shape) == "circle" else tg.from
		var off: Vector2 = src - u.pos
		rows.append([off.normalized() if off.length() > r else Vector2.ZERO, float(tg.dmg) * (1.4 if tg.cc else 1.0)])
	for k in b.eprof:
		var pr: Dictionary = b.eprof[k]
		var eb: TeamIntel.EnemyBelief = pr.b
		if not eb.visible or eb.dead:
			continue
		var off2: Vector2 = eb.pos - u.pos
		var gap: float = off2.length() - r - eb.radius
		var ms: float = maxf(30.0, float(pr.ms))
		var val: float = 0.0
		var brange: float = pr.range
		if gap <= brange + ms * 0.5:
			val += float(pr.dps) * clampf(window - maxf(0.0, gap - brange) / ms, 0.0, window) * 0.8
		for ab in pr.abilities:
			if gap <= float(ab.range) + ms * 0.4 + 10.0:
				val += (float(ab.dmg) + float(ab.cc) * 55.0) * float(ab.get("hit", 0.6)) * 0.55
		# Another of our heroes stands nearer: part of that pressure goes there.
		for x in b.allies_cache:
			if x != u and x.alive and x.pos.distance_to(eb.pos) + 30.0 < off2.length():
				val *= 0.6
				break
		if not eb.casting.is_empty():
			var cpos: Vector2 = eb.casting.get("pos", Vector2.INF)
			if int(eb.casting.get("target", -1)) == u.idx or (cpos.is_finite() and cpos.distance_to(u.pos) <= r + 50.0):
				var cab = eb.casting.get("ability")
				if bool(eb.casting.get("basic", false)):
					val += eb.def.stat("attackDamage") * 1.1
				elif cab is Defs.AbilityDef:
					var cad: Defs.AbilityDef = cab
					val += KitModel.nominal_damage(cad, eb.def) + (70.0 if not cad.cc_types.is_empty() else 0.0)
		if val > 0.0:
			rows.append([off2.normalized() if off2.length() > 1.0 else u.facing, val * float(pr.w)])
	return rows


static func _roar_candidate(b: TacticianBrain, u: BUnit, i: int, a: Defs.AbilityDef, ctx: Dictionary, out: Array) -> void:
	var plan: Dictionary = roar_plan(b, u, a, ctx)
	if plan.is_empty():
		return
	var v: float = float(plan.value) - ROAR_COST - b._cost(u, a, ctx)
	if v <= 0.0:
		return
	out.append({"value": v, "key": "a%d:roar" % i, "label": "%s (적 %d · 제어 %d)" % [a.name, int(plan.victims), int(plan.sources)],
		"parts": {"제어 연장": plan.cc, "전차 연계": plan.combo},
		"cmd": {"kind": "ability", "index": i, "ability_id": a.id, "pos": u.pos, "need": 0.0}})


# Roar value: the extra crowd-control seconds our team lands on roared
# enemies during the 6 s (ready or soon-ready allied control that can reach a
# seen enemy in time; allies' cooldowns are our own knowledge), plus the
# S3 → S4 combo when the chariot is about to go. Hidden enemies are not
# counted (the roar reaches them, but the team does not know where they are).
static func roar_plan(b: TacticianBrain, u: BUnit, a: Defs.AbilityDef, ctx: Dictionary) -> Dictionary:
	var ev: Dictionary = KitModel.evaluate(a.effects, ctx.st, {})
	var loss: float = float(ev.get("tenacity_loss", 0.1))
	var dur: float = float(ev.get("roar_dur", 6.0))
	var reach: float = float(ev.get("roar_reach_ffa", 900.0)) if b.sim.deathmatch else INF
	var victims: Array = []
	for t in ctx.targets:
		var e: TeamIntel.EnemyBelief = t
		if not e.is_hero or e.has_status("invulnerable") or e.has_status("unstoppable") or e.has_status("untargetable"):
			continue
		if u.pos.distance_to(e.pos) > reach:
			continue
		var held: float = 0.0
		for row in e.statuses:
			if str(row.type) == "roar" and bool(row.get("own", false)):
				held = maxf(held, float(row.get("remaining", 0.0)))
		if held > dur * 0.5:
			continue
		victims.append(e)
	if victims.is_empty():
		return {}
	var cc_v: float = 0.0
	var sources: int = 0
	var team: Array = [u]
	team.append_array(ctx.allies)
	for x0 in team:
		var x: BUnit = x0
		if not x.alive or not x.is_hero:
			continue
		var abilities: Array = b.sim.ability_list(x)
		var xms: float = maxf(30.0, b.sim.stat(x, &"moveSpeed"))
		for j in abilities.size():
			var ab: Defs.AbilityDef = abilities[j]
			var secs: float = cc_seconds(ab)
			if secs <= 0.0:
				continue
			var casting: bool = x.action != null and x.action.windup and x.action.ability == ab
			var wait: float = 0.0
			if not casting:
				if ab.virtual or j >= x.cooldowns.size() or x.sealed.has(j):
					continue
				wait = maxf(0.0, x.cooldowns[j] - b.sim.time)
				if wait > dur - 1.5:
					continue
			var reach_x: float = ab.range + b.sim.radius(x) + (ab.radius if ab.target == "self" else 0.0)
			var best: TeamIntel.EnemyBelief = null
			var best_gap: float = INF
			for v0 in victims:
				var e2: TeamIntel.EnemyBelief = v0
				var gap: float = x.pos.distance_to(e2.pos) - e2.radius - reach_x
				if maxf(wait, maxf(0.0, gap) / xms) > dur - 1.0:
					continue
				if gap < best_gap:
					best_gap = gap
					best = e2
			if best == null:
				continue
			var p_land: float = 0.9 if casting else (0.65 if best_gap <= 0.0 and wait <= 0.3 else 0.4)
			# Roar alone may push tenacity below zero, down to -0.3.
			var extra: float = secs * minf(loss, best.def.stat("tenacity") + 0.3)
			var pr: Dictionary = b.eprof.get(best.idx, {})
			var per_s: float = float(pr.get("dps", 60.0)) * 1.1 + float(pr.get("burst", 80.0)) * 0.25 + 85.0
			cc_v += extra * per_s * p_land * b._ew(best.idx)
			sources += 1
	var combo: float = 0.0
	var s4: Defs.AbilityDef = Doctrine._ab(b, u, CHARIOT_SLOT)
	if s4 and Doctrine._ready(b, u, CHARIOT_SLOT):
		var cp: Dictionary = chariot_plan(b, u, s4, ctx)
		if not cp.is_empty() and float(cp.value) > CHARIOT_COST:
			combo = 0.45 * (float(cp.value) - CHARIOT_COST) + 20.0
	if sources == 0 and combo <= 0.0:
		return {}
	# Once a control window exists, the 6 s debuff on everyone in the fight
	# also lengthens the slows and control our follow-up adds.
	var fighting: int = 0
	for v1 in victims:
		var e3: TeamIntel.EnemyBelief = v1
		for x1 in team:
			if (x1 as BUnit).alive and (x1 as BUnit).pos.distance_to(e3.pos) < 320.0:
				fighting += 1
				break
	cc_v += 6.0 * fighting
	return {"value": cc_v * 2.4 + combo, "cc": cc_v, "combo": combo, "victims": victims.size(), "sources": sources}


# Weighted, tenacity-scaled control seconds one cast of `ab` deals.
static func cc_seconds(ab: Defs.AbilityDef) -> float:
	var cacheable: bool = not ab.virtual and ab.id != ""
	if cacheable and _cc_secs.has(ab.id):
		return float(_cc_secs[ab.id])
	var ev: Dictionary = KitModel.evaluate(ab.effects, {}, {})
	var secs: float = 0.0
	for k in ev.cc:
		secs = maxf(secs, float(ev.cc[k]) * float(ROAR_CC.get(str(k), 0.0)))
	secs += float(ev.slow_dur) * SLOW_WEIGHT if float(ev.slow) > 0.0 else 0.0
	if cacheable:
		_cc_secs[ab.id] = secs
	return secs


static func _chariot_candidate(b: TacticianBrain, u: BUnit, i: int, a: Defs.AbilityDef, ctx: Dictionary, out: Array) -> void:
	var plan: Dictionary = chariot_plan(b, u, a, ctx)
	if plan.is_empty():
		return
	var v: float = float(plan.value) - CHARIOT_COST - b._cost(u, a, ctx)
	if v <= 0.0:
		return
	out.append({"value": v, "key": "a%d:chariot" % i, "label": "%s (넉백 대상 %d)" % [a.name, int(plan.n)],
		"parts": {"넉백": plan.value, "대상": plan.n},
		"cmd": {"kind": "ability", "index": i, "ability_id": a.id, "pos": u.pos, "need": 0.0}})


# Chariot value: every enemy hero the team sees (within 900 in free-for-all)
# is hunted, knocked back up to twice and hit for 30+0.3AD each time. A knock
# is worth its damage plus the lost position, more on a diver at our carry, a
# wind-up. Displacement immunity removes the peel value, not contact damage.
# One seen enemy alone pays the 45 s
# cooldown only as an urgent peel.
static func chariot_plan(b: TacticianBrain, u: BUnit, a: Defs.AbilityDef, ctx: Dictionary) -> Dictionary:
	var ev: Dictionary = KitModel.evaluate(a.effects, ctx.st, {})
	var knocks: float = maxf(1.0, float(ev.get("knocks", 2.0)))
	var hit: float = float(ev.get("knock_dmg", 50.0))
	var travel: float = float(ev.get("chariot_speed", 300.0)) * float(ev.get("chariot_dur", 5.0))
	var reach: float = float(ev.get("chariot_reach_ffa", 900.0)) if b.sim.deathmatch else INF
	var carry: BUnit = b.sim.u_at(int(b.plan.get("carry", -1)))
	var focus: int = (ctx.focus as TeamIntel.EnemyBelief).idx if ctx.focus else -1
	var total: float = 0.0
	var n: int = 0
	var fight: bool = false
	for t in ctx.targets:
		var e: TeamIntel.EnemyBelief = t
		if not e.is_hero or e.has_status("invulnerable") or e.has_status("untargetable"):
			continue
		var d: float = u.pos.distance_to(e.pos)
		if d > reach:
			continue
		var armor: float = float(KitModel._enemy_base(e.def).st.armor)
		var kv: float = hit * 100.0 / (100.0 + maxf(0.0, armor))
		if not e.has_status("contemplation") and not e.has_status("unstoppable"):
			kv += KNOCK_BASE
			var pr: Dictionary = b.eprof.get(e.idx, {})
			if carry and carry != u and carry.alive and e.def.preferred_range < 120.0 and e.pos.distance_to(carry.pos) < 170.0:
				kv += float(pr.get("threat", 300.0)) * 0.12
			if not e.casting.is_empty() and not bool(e.casting.get("basic", false)):
				kv += 30.0
		if e.idx == focus:
			kv += 15.0
		var reach_f: float = clampf(1.0 - (d - 450.0) / (travel * 0.6), 0.2, 1.0)
		total += kv * knocks * reach_f * b._ew(e.idx)
		n += 1
		if d < 320.0:
			fight = true
		else:
			for x in ctx.allies:
				if (x as BUnit).pos.distance_to(e.pos) < 320.0:
					fight = true
					break
	if n == 0:
		return {}
	if n == 1:
		total *= 0.3
	if not fight:
		total *= 0.6
	return {"value": total, "n": n}


# TacticianBrain._special_enemy dispatch (S1): true damage skips armour, so
# next to the physical damage the same action buys it gains most on armour.
static func special_enemy(_b: TacticianBrain, _u: BUnit, a: Defs.AbilityDef, e: TeamIntel.EnemyBelief, _aim: Vector2, _ctx: Dictionary, ev: Dictionary) -> float:
	if a.slot != 1 or not e.is_hero:
		return 0.0
	var armor: float = float(KitModel._enemy_base(e.def).st.armor)
	return float(ev.get("dmg", 0.0)) * armor / (100.0 + maxf(0.0, armor)) * 0.3


# Doctrine.adjust branch for achilles' own candidates.
static func adjust(b: TacticianBrain, u: BUnit, ctx: Dictionary, c: Dictionary, kind: String, a: Defs.AbilityDef, _e: TeamIntel.EnemyBelief) -> void:
	if kind == "move":
		_keep_front(b, u, ctx, c)
		return
	if kind != "ability" or a == null or a.virtual:
		return
	if a.slot == CHARIOT_SLOT and Doctrine._ready(b, u, ROAR_SLOT):
		# S3 → S4: the 0.3 s roar goes first so the knocked enemies meet our
		# control at -10 % tenacity.
		Doctrine._note(c, -maxf(0.0, float(c.value)) * 0.7, "포효 먼저 (S3 → S4)")


# While the guard is up the facing is locked: a move that would leave the
# main frontal threat outside the arc turns his unguarded side to it.
static func _keep_front(b: TacticianBrain, u: BUnit, ctx: Dictionary, c: Dictionary) -> void:
	var g: ST.Status = b.sim.get_status(u, &"frontGuard") if not u.statuses.is_empty() else null
	if g == null:
		return
	var threat: TeamIntel.EnemyBelief = main_threat(b, u, ctx, g)
	if threat == null:
		return
	var goal: Vector2 = c.cmd.get("goal", u.pos)
	var to_t: Vector2 = threat.pos - goal
	if to_t.length() < 1.0:
		return
	var dir: Vector2 = g.extra.get("dir", u.facing)
	var arc: float = float(g.extra.get("arc", deg_to_rad(120.0)))
	if to_t.normalized().dot(dir) >= cos(arc * 0.5):
		return
	var rem: float = maxf(0.0, g.end - b.sim.time)
	var pr: Dictionary = b.eprof.get(threat.idx, {})
	Doctrine._note(c, -(float(pr.get("dps", 60.0)) * rem * 1.2 + 25.0), "방패 정면 유지")


# The strongest visible enemy hero within 420 px that the raised guard faces.
static func main_threat(b: TacticianBrain, u: BUnit, ctx: Dictionary, g: ST.Status) -> TeamIntel.EnemyBelief:
	var dir: Vector2 = g.extra.get("dir", u.facing)
	var edge: float = cos(float(g.extra.get("arc", deg_to_rad(120.0))) * 0.5)
	var best: TeamIntel.EnemyBelief = null
	var best_v: float = 0.0
	for t in ctx.targets:
		var e: TeamIntel.EnemyBelief = t
		if not e.is_hero:
			continue
		var off: Vector2 = e.pos - u.pos
		if off.length() > 420.0 or off.length() < 1.0 or off.normalized().dot(dir) < edge:
			continue
		var v: float = float(b.eprof.get(e.idx, {}).get("threat", 300.0)) / maxf(60.0, off.length())
		if v > best_v:
			best_v = v
			best = e
	return best


# ------------------------------------------------------------------ enemy side

# Frontal-guard multiplier for one of our attacks on a seen achilles
# (TacticianBrain._enemy_value): ~0 when it would land from the front while
# the guard is still up. The guard direction is his visible facing (locked
# while guarding); its end comes from the observed S2 cast time.
static func guard_factor(b: TacticianBrain, u: BUnit, a: Defs.AbilityDef, e: TeamIntel.EnemyBelief) -> float:
	if not e.visible or not e.has_status("frontGuard"):
		return 1.0
	var impact: float = a.cast_time + (u.pos.distance_to(e.pos) / maxf(50.0, a.speed) if a.delivery == "projectile" else 0.0)
	var dropped: bool = a.delivery == "area" and a.target != "self"
	for f in a.effects:
		match str(f.get("type", "")):
			# Zone ticks and damage over time pass the guard.
			"zone", "dot":
				return 1.0
			"delayed_area":
				impact += float(f.get("delay", 0.5))
				dropped = true
	if impact > guard_remaining(b, e) + 0.05:
		return 1.0
	# An area dropped on him is tested from its centre (sim.front_blocks), not
	# from the caster: right beside his body that side is close to a coin toss.
	if dropped:
		return 0.6
	return frontal_factor(u.pos, e)


static func frontal_factor(from: Vector2, e: TeamIntel.EnemyBelief) -> float:
	var off: Vector2 = from - e.pos
	if off.length() < 1.0:
		return 0.05
	var spec: Dictionary = guard_spec(e.def)
	var edge: float = cos(float(spec.arc) * 0.5)
	var c: float = off.normalized().dot(e.facing)
	if c >= edge + 0.12:
		return 0.05
	if c >= edge - 0.05:
		return 0.5
	return 1.0


# Seconds the seen guard still lasts (public: the observed S2 cast time).
static func guard_remaining(b: TacticianBrain, e: TeamIntel.EnemyBelief) -> float:
	var spec: Dictionary = guard_spec(e.def)
	var si: int = GUARD_SLOT - 1
	if si < e.cd_last.size() and e.cd_last[si] > -100.0:
		return maxf(0.0, e.cd_last[si] + float(spec.cast) + float(spec.dur) - b.sim.time)
	return 1.0


static func guard_spec(d: Defs.CharDef) -> Dictionary:
	if d and d.abilities.size() >= GUARD_SLOT:
		var a: Defs.AbilityDef = d.abilities[GUARD_SLOT - 1]
		for f in a.effects:
			if str(f.get("type", "")) == "front_guard":
				return {"dur": float(f.get("duration", 2.0)), "arc": deg_to_rad(float(f.get("arcDegrees", 120.0))), "cast": a.cast_time}
	return {"dur": 2.0, "arc": deg_to_rad(120.0), "cast": 0.05}


# Doctrine.adjust hook for every hero: basic attacks into a raised guard's
# front are wasted (abilities are discounted in _enemy_value), and melee
# moves that reach his side are preferred while the guard lasts.
static func enemy_notes(b: TacticianBrain, u: BUnit, ctx: Dictionary, cands: Array) -> void:
	var guards: Array = []
	for t in ctx.get("targets", []):
		var g: TeamIntel.EnemyBelief = t
		if g.is_hero and g.visible and g.def.id == ID and g.has_status("frontGuard"):
			guards.append(g)
	if guards.is_empty():
		return
	var melee: bool = u.def.preferred_range < 120.0
	var reach: float = float(ctx.get("range", 60.0)) + float(ctx.get("r", 17.0)) + 30.0
	for c in cands:
		var cmd: Dictionary = c.cmd
		var kind: String = str(cmd.get("kind", ""))
		if kind == "basic":
			var ti: int = int(cmd.get("target", -1))
			for g0 in guards:
				var g1: TeamIntel.EnemyBelief = g0
				if g1.idx != ti or guard_remaining(b, g1) < 0.3:
					continue
				var k: float = frontal_factor(u.pos, g1)
				if k < 1.0:
					Doctrine._note(c, -(maxf(0.0, float(c.value)) + 8.0) * (1.0 - k), "방패 정면 공격 무효")
		elif kind == "move" and melee:
			var goal: Vector2 = cmd.get("goal", u.pos)
			for g2 in guards:
				var g3: TeamIntel.EnemyBelief = g2
				if guard_remaining(b, g3) < 0.6 or frontal_factor(u.pos, g3) >= 1.0:
					continue
				if goal.distance_to(g3.pos) <= reach + g3.radius and frontal_factor(goal, g3) >= 1.0:
					Doctrine._note(c, 14.0, "방패 측면 공략")
					break


# TacticianBrain._danger_raw entity arm: a seen chariot hunts the hero with
# the fewest knocks (ties: nearest) and hits whoever it touches on the way.
# Knocks our heroes took are public to us (TeamIntel.chariot_knocks); a hero
# knocked twice is safe from it.
static func chariot_danger(b: TacticianBrain, u: BUnit, eb: TeamIntel.EnemyBelief, p: Vector2, horizon: float) -> float:
	var knocks: Dictionary = b.intel.chariot_knocks.get(eb.idx, {})
	if int(knocks.get(u.idx, 0)) >= 2:
		return 0.0
	var prey: BUnit = null
	var prey_k: int = 1 << 30
	var prey_d: float = INF
	for x in b.sim.heroes:
		if not x.alive or x.team != b.team or int(knocks.get(x.idx, 0)) >= 2:
			continue
		var k: int = int(knocks.get(x.idx, 0))
		var dx: float = x.pos.distance_to(eb.pos)
		if k < prey_k or (k == prey_k and dx < prey_d):
			prey = x
			prey_k = k
			prey_d = dx
	var r: float = b.sim.radius(u)
	var touch: float = eb.radius + r
	var sp: float = maxf(150.0, eb.vel.length())
	var dc: float = p.distance_to(eb.pos)
	var hit: float = 85.0
	if prey == u:
		var reach: float = sp * horizon + touch + 60.0
		return hit * clampf(1.2 - dc / reach, 0.3, 1.0) if dc <= reach else 0.0
	var to: Vector2 = prey.pos if prey else eb.pos + eb.vel * horizon
	if Geometry2D.get_closest_point_to_segment(p, eb.pos, to).distance_to(p) <= touch + 12.0 and dc <= sp * horizon + touch + 30.0:
		return hit * 0.8
	if dc <= touch + 40.0:
		return hit * 0.5
	return 0.0


# ------------------------------------------------------------------ draft

# DraftDirector.kit_features terms the generic effect walk misses: the
# chariot's contacts (damage and two knockbacks on each of about two enemies
# per cast) and the roar's team-control amplification.
static func draft_terms(d: Defs.CharDef) -> Dictionary:
	var spell: float = 0.0
	var hard: float = 0.0
	for a0 in d.abilities:
		var a: Defs.AbilityDef = a0
		var cd: float = maxf(0.25, a.cooldown)
		for f in a.effects:
			match str(f.get("type", "")):
				"summon":
					if f.has("knock"):
						var atk: Dictionary = f.get("attack", {})
						var per: float = float(atk.get("base", 0.0)) + float(atk.get("ad", 0.0)) * d.stat("attackDamage") + float(atk.get("ap", 0.0)) * d.stat("abilityPower")
						var contacts: float = float(f.get("maxKnocks", 2)) * 2.0
						spell += per * contacts / cd
						hard += 0.35 * contacts / cd
				"roar":
					hard += float(f.get("tenacityLoss", 0.1)) * float(f.get("duration", 6.0)) * 0.5 / cd
	return {"spell": spell, "hard": hard}
