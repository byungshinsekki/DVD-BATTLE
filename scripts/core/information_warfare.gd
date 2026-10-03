class_name InformationWarfare
extends RefCounted

# Knowledge effects live separately from the true combat state. Observation is
# consumed only by TeamIntel; rendering, collisions and damage retain real data.
const ACTIONS := ["fakeNews", "diversion", "propaganda", "whip", "gag", "prison", "interrogate"]
const PAIN_DURATION := 5.0
const PRISON_DURATION := 3.5
const PRISON_RADIUS := 64.0
var sim: BattleSim
var distrust: Array[int] = [0, 0]
var false_reports: Array[Dictionary] = [{}, {}]
var prisons: Array[Dictionary] = []


func _init(s: BattleSim) -> void:
	sim = s
	for _extra in range(2, s.team_count):
		distrust.append(0)
		false_reports.append({})


# Teams whose beliefs an information attack by `team` targets: the other side,
# or every other participant in a free-for-all.
func rival_teams(team: int) -> Array[int]:
	var out: Array[int] = []
	for t in sim.team_count:
		if t != team:
			out.append(t)
	return out


func enemy_distrust(team: int) -> int:
	if sim.team_count == 2:
		return distrust[1 - team]
	var worst: int = 0
	for t in rival_teams(team):
		worst = maxi(worst, distrust[t])
	return worst


func contemplating(u: BUnit) -> bool:
	return u != null and u.alive and u.def.id == "politician" and u.motion == null and u.vel.length_squared() <= 4.0 and u.pos.distance_squared_to(u.ks.get("contemplation_pos", u.pos)) <= 0.01 and bool(u.ks.get("contemplating", false))


func update(dt: float) -> void:
	for u in sim.heroes:
		if not u.alive:
			continue
		if u.def.id == "politician":
			var still: bool = u.motion == null and u.vel.length_squared() <= 4.0 and u.pos.distance_squared_to(u.ks.get("contemplation_pos", u.pos)) <= 0.01
			var held: float = float(u.ks.get("contemplation_time", 0.0)) + dt if still else 0.0
			u.ks["contemplation_time"] = held
			u.ks["contemplation_pos"] = u.pos
			var active: bool = held >= 0.45
			if active != bool(u.ks.get("contemplating", false)):
				u.ks["contemplating"] = active
				sim.emit("CONTEMPLATION", u.idx, u.idx, {"active": active, "pos": u.pos})
			if active:
				var visible_status: ST.Status = sim.get_status(u, &"contemplation")
				if visible_status:
					visible_status.end = sim.time + 0.1
				else:
					sim.push_status(u, &"contemplation", u.idx, 0.1)
				var had_cc: bool = sim.is_crowd_controlled(u)
				sim.remove_statuses_where(u, func(st): return sim.is_cc_type(st.type))
				if had_cc:
					sim.reset_commitment(u, "contemplation")
			else:
				sim.remove_statuses_where(u, func(st): return st.type == &"contemplation")
			u.resources["distrust"] = enemy_distrust(sim.eteam(u))
		for st in u.statuses.duplicate():
			if st.type == &"taunt" and st.extra.has("forced_target"):
				var target: BUnit = sim.u_at(int(st.extra.forced_target))
				var source: BUnit = sim.u_at(st.source_idx)
				if st.end <= sim.time or target == null or not target.alive or source == null or not source.alive or sim.eteam(target) == sim.eteam(u):
					u.statuses.erase(st)
					sim.reset_commitment(u, "diversion_ended")
	for p in prisons:
		if bool(p.ended):
			continue
		var source: BUnit = sim.u_at(int(p.source))
		var target: BUnit = sim.u_at(int(p.target))
		if sim.time >= float(p.end) or source == null or not source.alive or target == null or not target.alive:
			_end_prison(p)
	for team in sim.team_count:
		for idx in false_reports[team].keys():
			var report: Dictionary = false_reports[team][idx]
			var subject: BUnit = sim.u_at(int(idx))
			var source: BUnit = sim.u_at(int(report.source))
			if float(report.end) <= sim.time or distrust[team] >= 10 or subject == null or not subject.alive or source == null or not source.alive:
				false_reports[team].erase(idx)


func pain_slow(u: BUnit) -> float:
	if contemplating(u) or sim.has_status(u, &"unstoppable"):
		return 0.0
	var stacks: int = 0
	for st in u.statuses:
		if st.type == &"pain" and st.end > sim.time:
			stacks = maxi(stacks, st.stacks)
	return 0.04 * stacks


func add_pain(s: BUnit, t: BUnit, count: int, ctx: Dictionary) -> void:
	if t == null or not t.alive or s == null or not s.alive or sim.eteam(s) == sim.eteam(t):
		return
	if not sim.apply_mark(s, t, {"status": "pain", "stacks": count, "maxStacks": 6, "duration": PAIN_DURATION}, ctx):
		return
	var st: ST.Status = sim.owned_status(t, &"pain", s.idx)
	if st:
		if st.interval <= 0.0:
			st.interval = 1.0
			st.next_tick = sim.time + 1.0
		st.extra["slowPerStack"] = 0.04


func information_blocked(observer_team: int, target: BUnit) -> bool:
	if target == null or observer_team == sim.eteam(target):
		return false
	for u in sim.heroes:
		if sim.eteam(u) == sim.eteam(target) and contemplating(u):
			return true
	return false


func reveal(s: BUnit, t: BUnit, field: String, duration: float = 5.0) -> bool:
	var team: int = sim.eteam(s)
	if information_blocked(team, t):
		sim.emit("INFO_BLOCKED", s.idx, t.idx, {"team": team, "field": field})
		return false
	var value: Variant
	match field:
		"health":
			value = {"hp": t.hp, "max_hp": sim.max_hp(t)}
		"position":
			value = t.pos
		_:
			field = "cooldowns"
			value = Array(t.cooldowns)
			sim.emit("REVEAL", s.idx, t.idx, {"team": team, "ready_at": value, "duration": duration})
	sim.emit("INFO_REVEAL", s.idx, t.idx, {"team": team, "field": field, "value": value, "duration": duration})
	return true


func observation(team: int, u: BUnit) -> Dictionary:
	var data: Dictionary = {"pos": u.pos, "hp": u.hp, "ready_at": [], "misinformation": false}
	if team < 0 or team >= sim.team_count or distrust[team] >= 10 or sim.eteam(u) == team:
		return data
	var report: Dictionary = false_reports[team].get(u.idx, {})
	if not report.is_empty() and float(report.end) > sim.time:
		var source: BUnit = sim.u_at(int(report.source))
		if source and source.alive:
			data["pos"] = sim.clamp_pos(u.pos + (report.offset as Vector2), sim.radius(u))
			data["hp"] = clampf(u.hp + float(report.hp_offset) * sim.max_hp(u), 1.0, sim.max_hp(u))
			data["ready_at"] = report.ready_at
			data["misinformation"] = true
	return data


func execute(s: BUnit, act: ST.Action) -> void:
	var a: Defs.AbilityDef = act.ability
	var t: BUnit = sim.u_at(act.target_idx)
	var ctx: Dictionary = sim.context(s, a, {"action_id": act.id, "team": act.source_team})
	if not s.alive or not sim.check_condition(s, t, a.condition) or not sim.target_legal(s, a, t):
		sim.emit("MISS", s.idx, act.target_idx, {"ability": a, "reason": "condition_changed"})
		return
	if a.target in ["enemy", "ally"] and (not sim.realm_allowed(s, t, ctx) or not sim.los(s.pos, t.pos, 1.0)):
		sim.emit("MISS", s.idx, act.target_idx, {"ability": a, "reason": "target_blocked"})
		return
	sim.emit("CAST_COMPLETED", s.idx, act.target_idx, {"ability": a, "pos": act.target_pos, "from": s.pos})
	sim.kits._on_cast_completed(s)
	sim.fx("cast", s.pos, {"ability": a, "to": act.target_pos, "source": s.idx})
	match a.action:
		"fakeNews":
			_fake_news(s, a)
		"diversion":
			_diversion(s, t, ctx)
		"propaganda":
			_propaganda(s, ctx)
		"whip":
			var dir: Vector2 = (act.target_pos - s.pos).normalized()
			if dir.length_squared() < 0.01:
				dir = s.facing
			for enemy in sim.query_cone(s.pos, dir, a.range, a.angle, sim.opponents(s)):
				if not sim.los(s.pos, enemy.pos, 1.0):
					continue
				var edge: bool = s.pos.distance_to(enemy.pos) >= a.range * 0.75
				sim.apply_damage(s, enemy, {"school": "physical", "base": 38.0 + (28.0 if edge else 0.0), "ad": 0.45 + (0.30 if edge else 0.0)}, ctx)
				add_pain(s, enemy, 2 if edge else 1, ctx)
			sim.fx("cone", s.pos, {"dir": dir, "range": a.range, "angle": a.angle, "ability": a, "source": s.idx})
		"gag":
			sim.apply_status(s, t, {"status": "silence", "duration": 2.1}, ctx)
		"prison":
			_create_prison(s, t, ctx)
		"interrogate":
			reveal(s, t, str(act.extra.get("info_kind", "cooldowns")))


func _fake_news(s: BUnit, a: Defs.AbilityDef) -> void:
	for enemy_team in rival_teams(sim.eteam(s)):
		distrust[enemy_team] = mini(10, distrust[enemy_team] + 1)
		var believed: bool = distrust[enemy_team] < 10
		if believed:
			for ally in sim.allies_of(sim.eteam(s)):
				var phase: float = float(ally.idx * 7 + distrust[enemy_team] * 3) * 1.37
				var cds: Array = []
				for ability in ally.def.abilities:
					cds.append(sim.time + float(ability.cooldown) * (0.2 if ally.idx % 2 == 0 else 0.85))
				false_reports[enemy_team][ally.idx] = {"source": s.idx, "end": sim.time + 5.0, "offset": Vector2.from_angle(phase) * 100.0, "hp_offset": 0.35 if ally.idx % 2 == 0 else -0.35, "ready_at": cds}
		else:
			false_reports[enemy_team].clear()
		s.resources["distrust"] = distrust[enemy_team]
		sim.emit("FAKE_NEWS", s.idx, -1, {"team": enemy_team, "distrust": distrust[enemy_team], "duration": 5.0, "believed": believed, "ability": a})


func _diversion(s: BUnit, ally: BUnit, ctx: Dictionary) -> void:
	if ally == null:
		return
	for enemy_team in rival_teams(sim.eteam(s)):
		distrust[enemy_team] = 0
		sim.emit("DISTRUST_RESET", s.idx, ally.idx, {"team": enemy_team})
	for enemy in sim.opponents(s):
		if enemy.is_hero and enemy.pos.distance_to(ally.pos) <= 450.0 and sim.is_seen(sim.eteam(s), enemy) and sim.los(ally.pos, enemy.pos, 1.0):
			sim.apply_status(s, enemy, {"status": "taunt", "duration": 1.6, "forced_target": ally.idx}, ctx)
	sim.emit("DIVERSION", s.idx, ally.idx, {"ally": ally.idx, "duration": 1.6})


func _propaganda(s: BUnit, ctx: Dictionary) -> void:
	var ap: float = sim.stat(s, &"abilityPower")
	# Propaganda never amplifies itself through an existing propaganda buff.
	var coeff: float = 1.3 if contemplating(s) else 1.0
	var armor: float = 0.18 + 0.0012 * ap * coeff
	var ability: float = minf(0.30, 0.08 + 0.001 * ap * coeff)
	for ally in sim.allies_of(sim.eteam(s)):
		if ally.pos.distance_to(s.pos) <= 440.0 and sim.realm_allowed(s, ally, ctx):
			# Same-team duplicates refresh their own effects; stat readers use strongest.
			sim.add_buff(ally, &"armor", armor, 5.0, s.idx, {"tag": "propaganda"})
			sim.add_buff(ally, &"abilityCoefficient", ability, 5.0, s.idx, {"tag": "propaganda"})
	sim.emit("PROPAGANDA", s.idx, s.idx, {"duration": 5.0, "armor": armor, "coefficient": ability})


func _create_prison(s: BUnit, t: BUnit, ctx: Dictionary) -> void:
	if t == null or not t.alive or sim.has_any(t, [&"invulnerable", &"untargetable"]):
		return
	if s.pos.distance_to(t.pos) > 110.0 + sim.radius(s) + sim.radius(t):
		sim.emit("MISS", s.idx, t.idx, {"ability": ctx.get("ability"), "reason": "prison_out_of_range"})
		return
	var id: int = sim.next_id()
	var center: Vector2 = t.pos
	var sides: Dictionary = {}
	for body in sim.bodies_alive():
		sides[body.idx] = body.pos.distance_to(center) < PRISON_RADIUS
	var p: Dictionary = {"id": id, "source": s.idx, "target": t.idx, "center": center, "radius": PRISON_RADIUS, "end": sim.time + PRISON_DURATION, "ended": false, "inside": sides}
	prisons.append(p)
	sim.push_status(t, &"imprisoned", s.idx, PRISON_DURATION, {"prison_id": id, "armorReduction": 0.25})
	sim.emit("PRISON_CREATED", s.idx, t.idx, {"id": id, "pos": center, "radius": PRISON_RADIUS, "duration": PRISON_DURATION})


func _end_prison(p: Dictionary) -> void:
	if bool(p.ended):
		return
	p.ended = true
	var target: BUnit = sim.u_at(int(p.target))
	if target:
		sim.remove_statuses_where(target, func(st): return int(st.extra.get("prison_id", -1)) == int(p.id))
	sim.emit("PRISON_ENDED", int(p.source), int(p.target), {"id": p.id})


func constrain(u: BUnit, start: Vector2) -> void:
	if not u.alive:
		return
	for p in prisons:
		if bool(p.ended) or float(p.end) <= sim.time:
			continue
		var center: Vector2 = p.center
		var inside: bool = bool((p.inside as Dictionary).get(u.idx, false))
		var edge: float = maxf(6.0, float(p.radius) - sim.radius(u) - 1.0) if inside else float(p.radius) + sim.radius(u) + 1.0
		var delta: Vector2 = u.pos - center
		var crossing: bool = delta.length() > edge if inside else delta.length() < edge
		var hit: float = Arena.seg_circle_t(start, u.pos, center, edge)
		if not inside and hit >= 0.0 and hit < 1.0:
			crossing = true
			var hit_delta: Vector2 = start.lerp(u.pos, hit) - center
			if hit_delta.length_squared() > 0.01:
				delta = hit_delta
		if crossing:
			var dir: Vector2 = delta.normalized() if delta.length_squared() > 0.01 else Vector2.RIGHT
			u.pos = sim.arena.resolve_circle(center + dir * edge, sim.radius(u))
			# Arena overlap cannot push a captive across its cage; fall back to origin.
			if inside and u.pos.distance_to(center) > edge + 0.01:
				u.pos = start if start.distance_to(center) <= edge else center
			u.vel = Vector2.ZERO
			if u.motion:
				sim.kits._clear_transit(u)


func on_death(dead: BUnit) -> void:
	for p in prisons:
		if not bool(p.ended) and (int(p.source) == dead.idx or int(p.target) == dead.idx):
			_end_prison(p)
	for u in sim.heroes:
		for st in u.statuses.duplicate():
			if st.type == &"taunt" and (st.source_idx == dead.idx or int(st.extra.get("forced_target", -1)) == dead.idx):
				u.statuses.erase(st)
				sim.reset_commitment(u, "diversion_death")
