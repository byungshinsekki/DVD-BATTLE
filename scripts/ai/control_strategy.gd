class_name ControlStrategy
extends RefCounted

# Only public objective state, our living heroes and observed EnemyBelief
# objects enter this planner. Enemy unit arrays are never queried here.
var sim: BattleSim
var team: int
var assignments: Dictionary = {}
var summary: Dictionary = {}
var last_update: float = -99.0
var observed: Array = []
var route_cache: Dictionary = {}
var route_cache_at: float = -99.0

func _init(s: BattleSim, t: int) -> void:
	sim = s
	team = t

func dispose() -> void:
	sim = null
	observed.clear()

func update(beliefs: Array, force: bool = false) -> void:
	if not sim.is_control_mode() or sim.domination == null:
		return
	if not force and sim.time - last_update < 0.75:
		return
	last_update = sim.time
	observed.clear()
	for item in beliefs:
		var b: TeamIntel.EnemyBelief = item
		if b.visible and not b.dead and b.is_hero and not b.controlled_by_us:
			observed.append(b)
	if sim.time - route_cache_at > 8.0:
		route_cache.clear()
		route_cache_at = sim.time
	var allies: Array[BUnit] = []
	for u in sim.allies_of(team):
		if u.team == team and u.is_hero and u.chamber == "":
			allies.append(u)
	var mode = sim.domination
	var owned: Array[int] = [0, 0]
	for p in mode.points:
		if int(p.owner) >= 0 and not bool(p.contested):
			owned[int(p.owner)] += 1
	var our_eta: float = maxf(0.0, mode.target_score - float(mode.scores[team])) / maxf(0.05, owned[team])
	var enemy_eta: float = maxf(0.0, mode.target_score - float(mode.scores[1 - team])) / maxf(0.05, owned[1 - team])
	var seconds_left: float = maxf(0.0, sim.max_time - sim.time)
	var score_gap: float = float(mode.scores[1 - team]) - float(mode.scores[team])
	var urgency: float = clampf(score_gap / mode.target_score + (0.35 if enemy_eta + 15.0 < our_eta else 0.0)
		+ (0.35 if score_gap > 0.0 and seconds_left < 75.0 else 0.0), 0.0, 1.0)
	var old: Dictionary = assignments
	assignments = {}
	var point_rows: Array = []
	for index in mode.points.size():
		var p: Dictionary = mode.points[index]
		var seen: int = _enemies_near(p.center, float(p.radius) + 200.0)
		var priority: float = 145.0 if int(p.owner) != team else 65.0
		if int(p.owner) == 1 - team:
			priority += 65.0 * urgency
		if bool(p.contested):
			priority += 65.0
		if int(p.owner) == team:
			priority += 45.0 * minf(2.0, seen) + (25.0 if our_eta < enemy_eta else 0.0)
		point_rows.append({"id": str(p.id), "index": index, "owner": int(p.owner), "contested": bool(p.contested),
			"ours_assigned": 0, "enemy_observed": seen, "priority": priority})
	# At most 5*5*3 evaluations. Hysteresis keeps a unit committed to a
	# capture while marginal value sends spare allies to another objective.
	var remaining: Array[BUnit] = allies.duplicate()
	while not remaining.is_empty():
		var best_unit: BUnit = null
		var best_point: int = -1
		var best: float = -INF
		for u in remaining:
			for row in point_rows:
				var p: Dictionary = mode.points[int(row.index)]
				var distance: float = _route(u, p.center)
				var arrived: bool = u.pos.distance_to(p.center) < float(p.radius) * 0.8
				var assigned: int = int(row.ours_assigned)
				var wanted: int = maxi(1, mini(3, int(row.enemy_observed) + 1))
				var saturation: float = assigned * (100.0 if wanted == 1 else 45.0) + (100.0 if assigned >= wanted else 0.0)
				var value: float = float(row.priority) - distance * 0.075 - saturation
				value += 27.0 if int(old.get(u.idx, {}).get("point", -1)) == int(row.index) else 0.0
				value += 32.0 if arrived and int(p.owner) != team else 0.0
				var capture_sign: float = -1.0 if team == 0 else 1.0
				if arrived and float(p.progress) * capture_sign > 0.0:
					value += absf(float(p.progress)) * 30.0
				value += 18.0 * sim.hp_ratio(u) if int(row.enemy_observed) > 0 else 0.0
				if sim.hp_ratio(u) < 0.35 and int(row.enemy_observed) > 0:
					value -= 75.0 * (1.0 - urgency * 0.65)
				if value > best:
					best = value
					best_unit = u
					best_point = int(row.index)
		if best_unit == null or best_point < 0:
			break
		var chosen: Dictionary = mode.points[best_point]
		var row: Dictionary = point_rows[best_point]
		row.ours_assigned = int(row.ours_assigned) + 1
		var role: String = "수비" if int(chosen.owner) == team else ("점령" if int(chosen.owner) < 0 else "탈환")
		var offset: Vector2 = Vector2.from_angle(best_unit.idx * 2.4) * float(chosen.radius) * 0.25
		var goal: Vector2 = sim.arena.resolve_circle(chosen.center + offset, sim.radius(best_unit))
		assignments[best_unit.idx] = {"point": best_point, "id": str(chosen.id), "label": str(chosen.label), "role": role,
			"goal": goal, "radius": float(chosen.radius), "center": chosen.center, "reason": "공개 소유·득점과 관측 적 %d명에 따라 배분" % int(row.enemy_observed),
			"heal_target": "", "heal_reason": "", "urgency": urgency, "priority": float(row.priority)}
		remaining.erase(best_unit)
	_assign_healing(allies, urgency)
	summary = {"enabled": true, "score": [float(mode.scores[team]), float(mode.scores[1 - team])],
		"target_score": mode.target_score, "seconds_left": seconds_left, "points": point_rows,
		"assignments": assignments, "score_eta": our_eta, "enemy_score_eta": enemy_eta, "urgency": urgency}

func _enemies_near(point: Vector2, radius: float) -> int:
	var count: int = 0
	for item in observed:
		var b: TeamIntel.EnemyBelief = item
		if b.pos.distance_to(point) < radius:
			count += 1
	return count

# Walking length to goal under the CURRENT gate state (the key carries
# Arena.nav_sig, so a gate opening or closing never reuses a stale length).
# A goal behind a closed gate (INF) is priced as the all-open route plus the
# wait for the gate: finite, so ETA / progress arithmetic never sees INF.
func _route(u: BUnit, goal: Vector2) -> float:
	var r: float = sim.radius(u)
	var key: String = "%d:%d:%d:%d:%d:%d:%d" % [u.idx, int(ceilf(r)), int(u.pos.x / 64.0), int(u.pos.y / 64.0), int(goal.x), int(goal.y), sim.arena.nav_sig]
	if not route_cache.has(key):
		var d: float = Navigator.for_sim(sim, r).path_length(u.pos, goal, r)
		if d == INF:
			d = _gated_route(u, goal, r)
		route_cache[key] = d
	return float(route_cache[key])


func _gated_route(u: BUnit, goal: Vector2, r: float) -> float:
	var a: Arena = sim.arena
	var straight: float = u.pos.distance_to(goal)
	if a.gates.is_empty():
		return straight * 3.0 + 2000.0
	var open: float = Navigator.for_arena(a, r, a.all_gates_open_bits(), sim.env.skip_mask()).path_length(u.pos, goal, r)
	if open == INF:
		return straight * 3.0 + 2000.0
	var wait: float = INF
	for g in a.gates:
		var clk: Dictionary = Arena.gate_clock(g, sim.time)
		wait = minf(wait, 0.0 if bool(clk.open) else float(clk.remaining))
	if wait == INF:
		wait = 0.0
	return open + wait * maxf(30.0, sim.stat(u, &"moveSpeed"))

func _path_danger(u: BUnit, goal: Vector2) -> float:
	var path: PackedVector2Array = Navigator.for_sim(sim, sim.radius(u)).path_points(u.pos, goal)
	if path.is_empty():
		return INF
	var worst: float = 0.0
	for portion in [0.25, 0.5, 0.75, 1.0]:
		var sample: Vector2 = path[mini(path.size() - 1, int((path.size() - 1) * portion))]
		var danger: float = _enemies_near(sample, 260.0) * 0.65
		if sim.env.enabled:
			danger += sim.env.hazard_penalty(sample, sim.time + 1.0, sim.radius(u))
		worst = maxf(worst, danger)
	return worst

func _assign_healing(allies: Array[BUnit], urgency: float) -> void:
	var order: Array[BUnit] = allies.duplicate()
	order.sort_custom(func(a: BUnit, b: BUnit): return sim.hp_ratio(a) < sim.hp_ratio(b) or (is_equal_approx(sim.hp_ratio(a), sim.hp_ratio(b)) and a.idx < b.idx))
	var reserved: Dictionary = {}
	var pads: Array = sim.domination.heal_zones.duplicate()
	if sim.env.enabled:
		pads.append_array(sim.env.public_fountains())
	for u in order:
		if not assignments.has(u.idx) or sim.hp_ratio(u) >= 0.85:
			continue
		var best_pad: Dictionary = {}
		var best: float = 0.0
		for pad in pads:
			if reserved.has(str(pad.id)):
				continue
			var distance: float = _route(u, pad.center)
			var eta: float = distance / maxf(30.0, sim.stat(u, &"moveSpeed"))
			if float(pad.ready_at) > sim.time + minf(eta + 0.5, 6.0):
				continue
			if _enemies_near(pad.center, float(pad.radius) + 90.0) > 0:
				continue
			var risk: float = _path_danger(u, pad.center)
			if risk > (0.7 if sim.hp_ratio(u) < 0.3 else 1.2):
				continue
			var value: float = (1.0 - sim.hp_ratio(u)) * 210.0 - eta * 7.0 - risk * 70.0 - urgency * 20.0
			if distance < float(pad.radius) + 25.0:
				value += 55.0
			if value > best:
				best = value
				best_pad = pad
		if not best_pad.is_empty() and (best > 35.0 or sim.hp_ratio(u) < 0.3):
			var intent: Dictionary = assignments[u.idx]
			intent.heal_target = str(best_pad.id)
			intent.heal_reason = "체력 %.0f%% · 회복 준비시간과 관측 경로 위험 확인" % (sim.hp_ratio(u) * 100.0)
			intent.goal = best_pad.center
			intent.role = "회복"
			reserved[str(best_pad.id)] = u.idx

func intent(u: BUnit) -> Dictionary:
	return assignments.get(u.idx, {})

func explain(u: BUnit) -> Dictionary:
	var out: Dictionary = summary.duplicate()
	out["assignment"] = intent(u)
	out["heal_target"] = intent(u).get("heal_target", "")
	out["heal_reason"] = intent(u).get("heal_reason", "")
	return out
