class_name ClassicBrain
extends TeamController



# Enemy idx -> {"pos": perceived position, "t": time last seen}. Entries
# older than LAST_SEEN_TTL are forgotten (audit D15: stale spots were parked on).
var last_seen: Dictionary = {}
const LAST_SEEN_TTL: = 6.0
var control_plan: ControlStrategy
var control_intel: TeamIntel


func _init(s: BattleSim, t: int) -> void :
	super (s, t)
	label = "기본 AI"
	if s.is_control_mode():
		control_plan = ControlStrategy.new(s, t)
		control_intel = TeamIntel.new(s, t)


func dispose() -> void:
	if control_plan:
		control_plan.dispose()
	if control_intel:
		control_intel.dispose()
	sim = null


func on_start(_s: BattleSim) -> void:
	if control_intel:
		control_intel.observe()
		control_plan.update(control_intel.visible_enemies(), true)


func pre_tick(s: BattleSim) -> void :
	if control_intel:
		control_intel.ingest(s.ai_events)
	for event in s.ai_events:
		if str(event.type) in ["HERO_RESPAWNED", "RESPAWN_SCHEDULED"]:
			last_seen.erase(int(event.g))
		if str(event.type) in ["DEATH", "EXECUTED"] and (event.gv as Array)[team]:
			last_seen.erase(int(event.g))
	if s.tick % 3 != 0:
		return
	if control_intel:
		control_intel.observe()
		control_plan.update(control_intel.visible_enemies())
	for e in s.heroes:
		if e.alive and s.eteam(e) != team and s.is_seen(team, e):
			var row: Dictionary = last_seen.get(e.idx, {})
			if row.is_empty():
				last_seen[e.idx] = row
			row["pos"] = _perceived_pos(e)
			row["t"] = s.time
	for k in last_seen.keys():
		if s.time - float(last_seen[k].t) > LAST_SEEN_TTL:
			last_seen.erase(k)


func _perceived_pos(u: BUnit) -> Vector2:
	if u.team == team:
		return u.pos
	if sim.is_seen(team, u):
		return sim.warfare.observation(team, u).get("pos", u.pos)
	var row: Dictionary = last_seen.get(u.idx, {})
	return row.pos if not row.is_empty() else sim.arena.center()


# The most recently seen enemy position still remembered, or INF.
func _latest_sighting() -> Vector2:
	var best: Vector2 = Vector2.INF
	var best_t: float = -INF
	for k in last_seen:
		var row: Dictionary = last_seen[k]
		if float(row.t) > best_t:
			best_t = float(row.t)
			best = row.pos
	return best


func _perceived_health(u: BUnit) -> float:
	return float(sim.warfare.observation(team, u).get("hp", u.hp)) / maxf(1.0, sim.max_hp(u))


func _visible_enemies(u: BUnit) -> Array:
	var out: Array = []
	for e in sim.opponents(u):
		if sim.is_seen(team, e):
			out.append(e)
	return out


func decide(u: BUnit) -> void :
	u.next_decision_at = sim.time + 0.22
	var forced: BUnit = sim.forced_target(u)
	if forced:
		u.command = {"kind": "basic", "target": forced.idx, "pos": forced.pos}
		if u.def.has_rule("no_basic"):
			u.command = {"kind": "move", "pos": forced.pos}
		return
	var enemies: = _visible_enemies(u)
	# D15/D1: attack only what this hero observes itself; the simulator voids
	# orders on enemies only an ally can see.
	var strike: Array = []
	for e in enemies:
		if sim.observes(u, e):
			strike.append(e)
	var heroes_only: Array = []
	for e in strike:
		if e.is_hero:
			heroes_only.append(e)
	var pool: = heroes_only if not heroes_only.is_empty() else strike
	var objective: Dictionary = control_plan.intent(u) if control_plan else {}
	if not objective.is_empty():
		var local_pool: Array = []
		for enemy in pool:
			var known: Vector2 = _perceived_pos(enemy)
			if known.distance_to(objective.center) < float(objective.radius) + 140.0 or known.distance_to(u.pos) < 160.0:
				local_pool.append(enemy)
		pool = local_pool
	if pool.is_empty():
		if not objective.is_empty():
			u.command = {"kind": "move", "pos": objective.goal, "purpose": "거점 " + str(objective.role)}
			return
		# An ally sees an enemy this hero cannot: walk toward it to get sight.
		var seen_by_team: BUnit = null
		var sd: float = INF
		for e in enemies:
			var dd: float = u.pos.distance_to(_perceived_pos(e)) + (0.0 if e.is_hero else 400.0)
			if dd < sd:
				sd = dd
				seen_by_team = e
		if seen_by_team:
			u.command = {"kind": "move", "pos": _perceived_pos(seen_by_team), "purpose": "시야 확보"}
			return
		# Search toward the public opposing spawn region. Fixed classic-map
		# coordinates sent scouts to unrelated corners on larger / rotated maps.
		var goal: Vector2 = sim.arena.center()
		var spawn_points: Array = sim.arena.spawns.get(1 - team, [])
		if not spawn_points.is_empty():
			goal = Vector2.ZERO
			for spawn: Vector2 in spawn_points:
				goal += spawn
			goal /= spawn_points.size()
		var latest: Vector2 = _latest_sighting()
		if latest.is_finite():
			goal = latest
		u.command = {"kind": "move", "pos": goal}
		return
	var focus_low: = float(u.def.behavior.get("focusLowHealth", 0.5)) > 0.6
	var target: BUnit = null
	var best: = INF
	for e in pool:
		var score: = u.pos.distance_to(_perceived_pos(e))
		if focus_low:
			score = _perceived_health(e) * 400.0 + score * 0.5
		if score < best:
			best = score
			target = e
	var abilities: = sim.ability_list(u)
	for i in abilities.size():
		var a: Defs.AbilityDef = abilities[i]
		if a.virtual and a.virtual_kind == "parry":
			continue
		if not sim.ability_ready(u, i, a):
			continue
		var cmd: = _try_ability(u, i, a, target, pool)
		if not cmd.is_empty():
			u.command = cmd
			return
	var rng_: = sim.stat(u, &"attackRange") + sim.radius(u) + sim.radius(target)
	var target_pos: Vector2 = _perceived_pos(target)
	if u.pos.distance_to(target_pos) <= rng_ and sim.can_basic(u):
		u.command = {"kind": "basic", "target": target.idx}
		return
	if not objective.is_empty():
		if str(objective.heal_target) != "" or target_pos.distance_to(objective.center) > float(objective.radius) + 120.0:
			u.command = {"kind": "move", "pos": objective.goal, "purpose": "거점 " + str(objective.role)}
			return
	var pref: = maxf(20.0, u.def.preferred_range)
	var dir: = (u.pos - target_pos).normalized()
	if u.def.id == "politician" and u.pos.distance_to(target_pos) > 230.0 and u.pos.distance_to(target_pos) < 440.0:
		u.command = {"kind": "move", "pos": u.pos}
		return
	u.command = {"kind": "move", "pos": target_pos + dir * (pref + sim.radius(target)), "target": target.idx}


func _try_ability(u: BUnit, i: int, a: Defs.AbilityDef, target: BUnit, _enemies: Array) -> Dictionary:
	var target_pos: Vector2 = _perceived_pos(target)
	var d: = u.pos.distance_to(target_pos)
	if a.action == "fakeNews":
		return {"kind": "ability", "index": i, "pos": u.pos, "ability_id": a.id} if sim.warfare.enemy_distrust(team) < 10 else {}
	match a.target:
		"enemy":
			if not sim.check_condition(u, target, a.condition):
				return {}
			if d <= a.range + sim.radius(u):
				return {"kind": "ability", "index": i, "target": target.idx, "pos": target_pos, "ability_id": a.id, "extra": {"info_kind": "cooldowns"}}
		"position":
			if a.action == "pointBlink":
				if sim.hp_ratio(u) < 0.45 and d < 200.0:
					return {"kind": "ability", "index": i, "pos": u.pos + (u.pos - target_pos).normalized() * a.range, "ability_id": a.id}
				return {}
			if a.action == "detonate":
				return {"kind": "ability", "index": i, "pos": target_pos, "ability_id": a.id}
			if d <= a.range + sim.radius(u):
				return {"kind": "ability", "index": i, "pos": target_pos, "ability_id": a.id}
		"self":
			if a.virtual_kind == "eat":
				return {"kind": "ability", "index": i, "pos": u.pos, "ability_id": a.id}
			if not sim.check_condition(u, target, a.condition):
				return {}
			var r: = maxf(a.radius, 220.0) if a.delivery != "area" else a.radius + 20.0
			if d <= r:
				return {"kind": "ability", "index": i, "pos": u.pos, "ability_id": a.id}
		"ally":
			var best: BUnit = null
			for al in sim.allies_of(team):
				if (a.flag("originOtherAlly", false) and al == u) or u.pos.distance_to(al.pos) > a.range:
					continue
				if a.action == "diversion":
					if al != u and (best == null or al.hp * (1.0 + sim.stat(al, &"armor") / 100.0) > best.hp * (1.0 + sim.stat(best, &"armor") / 100.0)):
						best = al
				elif best == null or sim.hp_ratio(al) < sim.hp_ratio(best):
					best = al
			if best and (sim.hp_ratio(best) < 0.7 or a.action in ["apple", "bloodLink", "diversion"]):
				return {"kind": "ability", "index": i, "target": best.idx, "pos": best.pos, "ability_id": a.id}
		"position_ally":
			if a.action == "portalPair":
				var pa: = u.pos + (target_pos - u.pos).normalized() * 40.0
				var pb: = u.pos + (target_pos - u.pos).normalized() * minf(a.range - 5.0, 260.0)
				return {"kind": "ability", "index": i, "pos": pb, "ability_id": a.id, "extra": {"portal_a": pa, "portal_b": pb}}
			if a.action == "healingMist":
				return {"kind": "ability", "index": i, "pos": u.pos + (target_pos - u.pos).normalized() * 100.0, "ability_id": a.id}
			if d < 500.0:
				var p: = u.pos + (target_pos - u.pos).normalized() * minf(a.range * 0.5, 100.0)
				return {"kind": "ability", "index": i, "pos": p, "ability_id": a.id}
	return {}


func steer(u: BUnit) -> Vector2:
	var forced: BUnit = sim.forced_target(u)
	if forced:
		var reach: float = sim.stat(u, &"attackRange") + sim.radius(u) + sim.radius(forced)
		return Vector2.ZERO if u.pos.distance_to(forced.pos) <= reach * 0.9 else (forced.pos - u.pos).normalized()
	var c: = u.command
	var goal: Vector2 = u.pos
	if c.is_empty():
		return Vector2.ZERO
	var kind: = str(c.get("kind", "move"))
	if kind == "move":
		goal = c.get("pos", u.pos)
	else:
		var t: = sim.u_at(int(c.get("target", -1)))
		if t and t.alive:
			var rng_: = sim.stat(u, &"attackRange") if kind == "basic" else 0.0
			if kind == "ability":
				var abilities: = sim.ability_list(u)
				var i: = int(c.get("index", 0))
				if i < abilities.size():
					rng_ = (abilities[i] as Defs.AbilityDef).range
			var perceived: Vector2 = _perceived_pos(t)
			var dirv: = (u.pos - perceived).normalized()
			goal = perceived + dirv * maxf(10.0, rng_ * 0.8)
		elif c.has("pos"):
			goal = c.pos
	# Links priced with this hero's speed and its own portal / pad cooldowns;
	# switched-off link types (and the environment switch) never qualify.
	var wp: = Navigator.unit_waypoint(sim, u, goal)
	var d: = wp - u.pos
	if d.length() < 6.0:
		return Vector2.ZERO
	var v: = d.normalized()
	v += sim.arena.avoidance_vector(u.pos, sim.radius(u), 40.0) * 0.3
	return v.normalized()


func explain(u: BUnit) -> Dictionary:
	return {"control": control_plan.explain(u) if control_plan else {}, "label": label}
