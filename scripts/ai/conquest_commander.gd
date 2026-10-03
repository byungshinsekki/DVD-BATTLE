class_name ConquestCommander
extends ControlStrategy

# V1.5 conquest planner. It keeps ControlStrategy's information boundary:
# public objective state (owner, progress, contest) and public respawn
# notices, our own heroes, and the enemy beliefs this team actually holds.
# Enemy unit arrays are never read.
#
# Compared with V1.4 it also reads capture progress on our own objectives
# (a point being taken outside our vision), counts enemies that are known to
# be respawning, refuses to send a lone hero into an observed group it cannot
# hold against, sends a spare fast hero to take an empty enemy objective, and
# spends heal trips only when the objective can spare the hero.
#
# V1.5.3 (audit_mode_layers C-1..C-5; each rule has a cfg flag "cc_<key>" so
# the developer lab can compare it against the V1.5.2 behaviour):
#  trip   (C-1) Heal trips are planned before objectives and committed until
#         the pad is used, health reaches 85% or the pad becomes unavailable
#         (cc_commit); a trip in progress keeps its pad against new requests.
#         Pads are chosen with a territory term, a path that crosses an
#         enemy-held objective is refused, one path-risk limit applies at any
#         health, the low-health penalty no longer needs an observed enemy,
#         and a hero below 25% with no pad ready waits beside an own-side pad
#         that is back within 8 s (cc_retreat, until 40%); otherwise it stays
#         in the objective pool (walking home lost head-to-head matches).
#  hold   (C-2) hold_exempt(): a holder inside its circle ignores hazards whose
#         expected damage over the next second is under 5% of its health and
#         gravity wells centred inside the circle (they pull holders in). The
#         tactician's steering must consult it (tactician_brain.gd).
#  steady (C-3) Observed-enemy counts are held for 2.5 s, and a hero that has
#         not reached its objective keeps it unless another is worth 60 more,
#         growing with the share of the route already walked.
#  backcap (C-4) Back-capture is decided before the per-point saturation, and
#         an owned objective with no enemy seen near it recently no longer
#         demands a permanent guard (cc_idle; owners keep scoring while absent
#         and capture progress is public).
#  stage  (C-5) Objective orders carry a staging point (behind the circle,
#         toward home) that the tactician's retreat anchor uses.

const SEEN_HOLD := 2.5           # C-3: observed enemies near a point are held this long
const REASSIGN_GAIN := 60.0      # C-3: an unarrived hero switches only for more than this
const PROGRESS_HYST := 50.0      # C-3: extra stickiness at the end of the route
const THREAT_MEMORY := 8.0       # C-4: an owned point stays "watched" this long after an enemy was near
const THREAT_RANGE := 700.0
const TRIP_DONE_HP := 0.85       # C-1
const RETREAT_HP := 0.25
const RETREAT_UNTIL := 0.4
const RETREAT_PAD_WAIT := 8.0    # wait beside an own-side pad only if it is back this soon
const TRIP_RISK_LIMIT := 1.2
const TERRITORY_SOFT := 0.45     # territory share (0 own spawn, 1 enemy spawn) where pads start to cost
const TERRITORY_HARD := 0.62     # pads deeper than this in enemy territory are refused
const HOLD_HAZARD_SHARE := 0.05  # C-2

var brain = null
var spawn_center: Vector2 = Vector2.ZERO
var enemy_spawn_center: Vector2 = Vector2.ZERO
var flags: Dictionary = {"progress": 1.0, "numbers": 1.0, "lone": 0.0, "backcap": 1.0, "heal": 1.0, "hyst": 1.0,
	"trip": 1.0, "hold": 1.0, "steady": 1.0, "stage": 1.0, "idle": 1.0, "commit": 1.0, "retreat": 1.0}
var seen_hold: Dictionary = {}    # point index -> {"n": int, "until": float}
var threat_seen: Dictionary = {}  # point index -> last time an observed enemy was within THREAT_RANGE
var trips: Dictionary = {}        # hero idx -> {"kind": "heal"|"retreat", "pad": id, "since": t}
var route0: Dictionary = {}       # hero idx -> {"point": index, "len": route length when assigned}
var staging: Array = []           # point index -> staging position
var counters: Dictionary = {"trips": 0, "trips_done": 0, "trips_dropped": 0, "retreats": 0, "backcaps": 0}


func _init(s: BattleSim, t: int, b = null) -> void:
	super(s, t)
	brain = b
	spawn_center = _centroid(sim.arena.spawns.get(team, []))
	enemy_spawn_center = _centroid(sim.arena.spawns.get(1 - team, []))
	if sim.domination:
		for p in sim.domination.points:
			staging.append(_staging_point(p))


func dispose() -> void:
	brain = null
	super.dispose()


func _centroid(points: Array) -> Vector2:
	if points.is_empty():
		return sim.arena.center()
	var c: Vector2 = Vector2.ZERO
	for p in points:
		c += p
	return c / points.size()


func _flag(key: String) -> bool:
	if brain and brain.cfg.has("cc_" + key):
		return float(brain.cfg["cc_" + key]) > 0.5
	return float(flags.get(key, 1.0)) > 0.5


func _known_dead_enemies() -> Array:
	var out: Array = []
	if brain == null:
		return out
	for item in brain.intel.enemies.values():
		var b: TeamIntel.EnemyBelief = item
		if b.is_hero and b.dead and float(b.respawn_at) > sim.time:
			out.append(b)
	return out


# 0 at our spawn centroid, 1 at the enemy's, 0.5 on the line between.
func territory(p: Vector2) -> float:
	var own: float = p.distance_to(spawn_center)
	var enemy: float = p.distance_to(enemy_spawn_center)
	return own / maxf(1.0, own + enemy)


# C-3: counts flicker with vision; the largest count of the last 2.5 s holds.
func _held_seen(index: int, now: int) -> int:
	var h: Dictionary = seen_hold.get(index, {})
	if h.is_empty() or now >= int(h.n) or sim.time > float(h.until):
		h = {"n": now, "until": sim.time + SEEN_HOLD}
		seen_hold[index] = h
	return maxi(now, int(h.n))


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
	# Public respawn notices: how many enemies are out of the fight, and for how long.
	var enemy_heroes: int = 0
	for u in sim.heroes:
		if u.team != team:
			enemy_heroes += 1
	var dead_enemies: Array = _known_dead_enemies() if _flag("numbers") else []
	var enemy_up: int = maxi(0, enemy_heroes - dead_enemies.size())
	var ours_up: int = allies.size()
	var numbers: int = ours_up - enemy_up
	var steady: bool = _flag("steady")
	var backcap: bool = _flag("backcap")
	var old: Dictionary = assignments
	assignments = {}
	var point_rows: Array = []
	for index in mode.points.size():
		var p: Dictionary = mode.points[index]
		var seen_now: int = _enemies_near(p.center, float(p.radius) + 200.0)
		var seen: int = _held_seen(index, seen_now) if steady else seen_now
		if _enemies_near(p.center, THREAT_RANGE) > 0:
			threat_seen[index] = sim.time
		var capture_sign: float = -1.0 if team == 0 else 1.0
		var losing_progress: float = maxf(0.0, -float(p.progress) * capture_sign) if _flag("progress") else 0.0
		var priority: float = 145.0 if int(p.owner) != team else 65.0
		if int(p.owner) == 1 - team:
			priority += 65.0 * urgency
			# Enemies known to be respawning cannot defend it: push.
			if numbers > 0:
				priority += 18.0 * minf(2.0, numbers)
		if bool(p.contested):
			priority += 65.0
		if int(p.owner) == team:
			priority += 45.0 * minf(2.0, seen) + (25.0 if our_eta < enemy_eta else 0.0)
		# Progress on our own objective is public even when the taker is not.
		if losing_progress > 0.0 and int(p.owner) == team:
			priority += 95.0 + 60.0 * losing_progress
		elif losing_progress > 0.0 and int(p.owner) < 0:
			priority += 55.0 + 40.0 * losing_progress
		# C-4: an owned objective nobody threatens keeps scoring without a guard.
		var idle_home: bool = backcap and _flag("idle") and int(p.owner) == team and not bool(p.contested) and losing_progress <= 0.0 and seen == 0 \
			and sim.time - float(threat_seen.get(index, -99.0)) > THREAT_MEMORY
		point_rows.append({"id": str(p.id), "index": index, "owner": int(p.owner), "contested": bool(p.contested),
			"ours_assigned": 0, "enemy_observed": seen, "priority": priority, "losing": losing_progress, "idle_home": idle_home})
	var remaining: Array[BUnit] = allies.duplicate()
	# C-1: wounded heroes on a heal trip or a retreat leave the objective pool
	# before the objectives are shared out.
	var trip_orders: Dictionary = {}
	if _flag("trip"):
		trip_orders = _plan_trips(allies, old, point_rows, urgency)
		for u in allies:
			if trip_orders.has(u.idx):
				remaining.erase(u)
	else:
		trips.clear()
	# C-4: back-capture is chosen before saturation fills every objective.
	if backcap:
		_backcap_first(remaining, point_rows, old, urgency, numbers)
		for u in allies:
			if assignments.has(u.idx):
				remaining.erase(u)
	while not remaining.is_empty():
		var best_unit: BUnit = null
		var best_point: int = -1
		var best: float = -INF
		for u in remaining:
			var hp_r: float = sim.hp_ratio(u)
			var old_point: int = int(old.get(u.idx, {}).get("point", -1))
			for row in point_rows:
				var p: Dictionary = mode.points[int(row.index)]
				var distance: float = _route(u, p.center)
				var arrived: bool = u.pos.distance_to(p.center) < float(p.radius) * 0.8
				var assigned: int = int(row.ours_assigned)
				var wanted: int = maxi(1, mini(3, int(row.enemy_observed) + 1))
				if bool(row.idle_home):
					wanted = 0
				var saturation: float = assigned * (100.0 if wanted <= 1 else 45.0) + (100.0 if assigned >= wanted else 0.0)
				var value: float = float(row.priority) - distance * 0.075 - saturation
				if old_point == int(row.index):
					value += _hysteresis(u, int(row.index), distance, arrived) if steady else (48.0 if _flag("hyst") else 27.0)
				value += 32.0 if arrived and int(p.owner) != team else 0.0
				var capture_sign: float = -1.0 if team == 0 else 1.0
				if arrived and float(p.progress) * capture_sign > 0.0:
					value += absf(float(p.progress)) * 30.0
				value += 18.0 * hp_r if int(row.enemy_observed) > 0 else 0.0
				# C-1: a badly wounded hero is a poor holder anywhere, observed
				# enemies or not (the V1.5.2 rule needed an observed enemy).
				if hp_r < 0.35 and (int(row.enemy_observed) > 0 or _flag("trip")):
					value -= 75.0 * (1.0 - urgency * 0.65)
				# A lone hero walking into two or more observed enemies only feeds,
				# unless it is the one body that can stop an ongoing capture.
				if _flag("lone") and assigned == 0 and int(row.enemy_observed) >= 2 and float(row.losing) <= 0.0:
					value -= 70.0 * (1.0 - urgency * 0.5)
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
		var reason: String = "공개 소유·진행도·득점과 관측 적 %d명에 따라 배분" % int(row.enemy_observed)
		if float(row.losing) > 0.0:
			reason = "시야 밖 점령 진행 %.0f%% 감지 → 저지" % (float(row.losing) * 100.0)
		assignments[best_unit.idx] = _objective_order(best_unit, best_point, role, reason, float(row.priority), urgency,
			float(row.losing) > 0.0, int(row.enemy_observed) > 0 or bool(row.contested))
		remaining.erase(best_unit)
	if _flag("trip"):
		for idx in trip_orders:
			assignments[idx] = trip_orders[idx]
	elif _flag("heal"):
		_assign_healing_v15(allies, urgency)
	else:
		_assign_healing(allies, urgency)
	# C-3: remember how long the route was when a hero took its objective.
	for u in allies:
		var order: Dictionary = assignments.get(u.idx, {})
		var pt: int = int(order.get("point", -1))
		if pt < 0 or str(order.get("heal_target", "")) != "" or str(order.get("role", "")) == "후퇴":
			continue
		if int(route0.get(u.idx, {}).get("point", -2)) != pt:
			route0[u.idx] = {"point": pt, "len": maxf(1.0, _route(u, mode.points[pt].center))}
	summary = {"enabled": true, "score": [float(mode.scores[team]), float(mode.scores[1 - team])],
		"target_score": mode.target_score, "seconds_left": seconds_left, "points": point_rows,
		"assignments": assignments, "score_eta": our_eta, "enemy_score_eta": enemy_eta, "urgency": urgency,
		"enemies_respawning": dead_enemies.size(), "numbers": numbers, "planner": "V1.5.3", "counters": counters}


func _objective_order(u: BUnit, index: int, role: String, reason: String, priority: float, urgency: float, capturing: bool, fight: bool) -> Dictionary:
	var p: Dictionary = sim.domination.points[index]
	var offset: Vector2 = Vector2.from_angle(u.idx * 2.4) * float(p.radius) * 0.25
	var order: Dictionary = {"point": index, "id": str(p.id), "label": str(p.label), "role": role,
		"goal": sim.arena.resolve_circle(p.center + offset, sim.radius(u)), "radius": float(p.radius), "center": p.center,
		"reason": reason, "heal_target": "", "heal_reason": "", "urgency": urgency, "priority": priority,
		"enemy_capturing": capturing, "fight": fight}
	# C-5: the tactician's retreat anchor falls back to this staging ground.
	if _flag("stage") and index < staging.size():
		order["stage"] = staging[index]
	return order


# C-3: stickiness of a hero's current objective. Arrived holders keep the
# V1.5 bonus; a hero still walking keeps its objective unless another is
# worth REASSIGN_GAIN more, and more so the further along the route it is.
func _hysteresis(u: BUnit, index: int, distance: float, arrived: bool) -> float:
	if arrived:
		return 48.0
	var r0: Dictionary = route0.get(u.idx, {})
	var progress: float = 0.0
	if int(r0.get("point", -1)) == index:
		progress = clampf(1.0 - distance / maxf(1.0, float(r0.len)), 0.0, 1.0)
	return REASSIGN_GAIN + PROGRESS_HYST * progress


func _staging_point(p: Dictionary) -> Vector2:
	var toward_home: Vector2 = spawn_center - p.center
	toward_home = toward_home.normalized() if toward_home.length() > 1.0 else Vector2.LEFT
	return sim.arena.resolve_circle(p.center + toward_home * (float(p.radius) + 280.0), 20.0)


# C-4: one healthy spare hero takes an enemy objective that no observed enemy
# is near, decided before saturation hands every objective a body.
func _backcap_first(pool: Array[BUnit], rows: Array, old: Dictionary, urgency: float, numbers: int) -> void:
	if pool.size() < 3 or numbers < -1:
		return
	var mode = sim.domination
	var target: int = -1
	var target_d: float = INF
	for row in rows:
		if int(row.owner) != 1 - team or int(row.enemy_observed) > 0 or bool(row.contested):
			continue
		# Prefer the enemy objective nearest our side of the map.
		var d: float = (mode.points[int(row.index)].center as Vector2).distance_to(spawn_center)
		if d < target_d:
			target_d = d
			target = int(row.index)
	if target < 0:
		return
	var p: Dictionary = mode.points[target]
	var best: BUnit = null
	var best_v: float = -INF
	for u in pool:
		if sim.hp_ratio(u) < 0.5:
			continue
		var prev: Dictionary = old.get(u.idx, {})
		var prev_point: int = int(prev.get("point", -1))
		# Never pull a holder off an objective that is watched, contested or being taken.
		if prev_point >= 0 and prev_point != target:
			var from: Dictionary = rows[prev_point]
			var there: bool = u.pos.distance_to(mode.points[prev_point].center) < float(mode.points[prev_point].radius) + 60.0
			if there and (int(from.enemy_observed) > 0 or bool(from.contested) or float(from.losing) > 0.0):
				continue
		var eta: float = _route(u, p.center) / maxf(35.0, sim.stat(u, &"moveSpeed"))
		var v: float = -eta + (8.0 if prev_point == target else 0.0) + (6.0 if str(prev.get("role", "")) == "우회 점령" else 0.0)
		if v > best_v:
			best_v = v
			best = u
	if best == null or best_v < -22.0:
		return
	(rows[target] as Dictionary).ours_assigned = int(rows[target].ours_assigned) + 1
	if str(old.get(best.idx, {}).get("role", "")) != "우회 점령":
		counters.backcaps = int(counters.backcaps) + 1
	var order: Dictionary = _objective_order(best, target, "우회 점령", "관측 적 없는 적 거점 · 여유 병력 우회", 150.0, urgency, false, false)
	assignments[best.idx] = order


# C-1: heal trips and retreats, planned before the objectives. Returns
# hero idx -> order for heroes that leave the objective pool.
func _plan_trips(allies: Array[BUnit], old: Dictionary, rows: Array, urgency: float) -> Dictionary:
	var out: Dictionary = {}
	var pads: Array = sim.domination.heal_zones.duplicate()
	if sim.env.enabled:
		pads.append_array(sim.env.public_fountains())
	var by_id: Dictionary = {}
	for pad in pads:
		by_id[str(pad.id)] = pad
	var order: Array[BUnit] = allies.duplicate()
	order.sort_custom(func(a: BUnit, b: BUnit): return sim.hp_ratio(a) < sim.hp_ratio(b) or (is_equal_approx(sim.hp_ratio(a), sim.hp_ratio(b)) and a.idx < b.idx))
	var alive: Dictionary = {}
	for u in allies:
		alive[u.idx] = true
	for idx in trips.keys():
		if not alive.has(idx):
			trips.erase(idx)
	var reserved: Dictionary = {}
	# A committed heal trip continues until it is used up or impossible, and
	# keeps its pad: trips in progress are settled before new ones are planned.
	for u in order:
		var trip0: Dictionary = trips.get(u.idx, {})
		if str(trip0.get("kind", "")) != "heal" or not _flag("commit"):
			continue
		var hp0: float = sim.hp_ratio(u)
		var pad: Dictionary = by_id.get(str(trip0.pad), {})
		var keep: bool = not pad.is_empty() and hp0 < TRIP_DONE_HP and not reserved.has(str(trip0.pad))
		if keep:
			var eta: float = _route(u, pad.center) / maxf(30.0, sim.stat(u, &"moveSpeed"))
			if float(pad.ready_at) > sim.time + minf(eta + 0.5, 6.0):
				keep = false   # used (by us or somebody else) or not back in time
			elif _enemies_near(pad.center, float(pad.radius) + 90.0) > 0:
				keep = false   # observed enemy on the pad
		if keep:
			reserved[str(trip0.pad)] = u.idx
			out[u.idx] = _heal_order(u, pad, old, rows, urgency, "진행 중인 회복 이동 유지")
			continue
		if hp0 >= TRIP_DONE_HP or hp0 > float(trip0.get("hp0", 1.0)) + 0.15:
			counters.trips_done = int(counters.trips_done) + 1
		else:
			counters.trips_dropped = int(counters.trips_dropped) + 1
		trips.erase(u.idx)
	for u in order:
		if out.has(u.idx):
			continue
		var hp_r: float = sim.hp_ratio(u)
		var trip: Dictionary = trips.get(u.idx, {})
		if hp_r >= TRIP_DONE_HP:
			trips.erase(u.idx)
			continue
		# A hero holding a fight or stopping a capture stays while it can still trade.
		var prev: Dictionary = old.get(u.idx, {})
		var busy: bool = false
		if int(prev.get("point", -1)) >= 0 and str(prev.get("role", "")) not in ["회복", "후퇴"]:
			var row: Dictionary = rows[int(prev.point)]
			var p: Dictionary = sim.domination.points[int(prev.point)]
			var inside: bool = u.pos.distance_to(p.center) < float(p.radius) + 40.0
			busy = float(row.losing) > 0.0 or (inside and (int(row.enemy_observed) > 0 or bool(row.contested)))
		if busy and hp_r > 0.3:
			trips.erase(u.idx)
			continue
		var best_pad: Dictionary = {}
		var best: float = 0.0
		for pad in pads:
			if reserved.has(str(pad.id)):
				continue
			var distance: float = _route(u, pad.center)
			var eta2: float = distance / maxf(30.0, sim.stat(u, &"moveSpeed"))
			if float(pad.ready_at) > sim.time + minf(eta2 + 0.5, 6.0):
				continue
			if _enemies_near(pad.center, float(pad.radius) + 90.0) > 0:
				continue
			var there: bool = distance < float(pad.radius) + 25.0
			var terr: float = territory(pad.center)
			if terr > TERRITORY_HARD and not there:
				continue
			var value: float = (1.0 - hp_r) * 210.0 - eta2 * 7.0 - urgency * 20.0 - maxf(0.0, terr - TERRITORY_SOFT) * 200.0
			if there:
				value += 55.0
			# Path risk only lowers the value: skip the path search for a pad
			# that could not win or could not start a trip anyway.
			if value <= best or (value <= 35.0 and hp_r >= 0.3):
				continue
			var check: Dictionary = _trip_path(u, pad.center)
			if bool(check.blocked) or float(check.risk) > TRIP_RISK_LIMIT:
				continue
			value -= float(check.risk) * 70.0
			if value > best:
				best = value
				best_pad = pad
		if not best_pad.is_empty() and (best > 35.0 or hp_r < 0.3):
			reserved[str(best_pad.id)] = u.idx
			trips[u.idx] = {"kind": "heal", "pad": str(best_pad.id), "since": sim.time, "hp0": hp_r}
			counters.trips = int(counters.trips) + 1
			out[u.idx] = _heal_order(u, best_pad, old, rows, urgency, "체력 %.0f%% · 준비시간·아군 진영·경로 위험 확인" % (hp_r * 100.0))
			continue
		# No pad now: a badly wounded hero waits beside an own-side pad that
		# is back within a few seconds instead of walking into the fight.
		var retreating: bool = str(trip.get("kind", "")) == "retreat"
		var wait_pad: Dictionary = {}
		if _flag("retreat") and (hp_r < RETREAT_HP or (retreating and hp_r < RETREAT_UNTIL)):
			wait_pad = _retreat_pad(u, pads, reserved)
		if not wait_pad.is_empty():
			if not retreating:
				counters.retreats = int(counters.retreats) + 1
			reserved[str(wait_pad.id)] = u.idx
			trips[u.idx] = {"kind": "retreat", "pad": str(wait_pad.id), "since": float(trip.get("since", sim.time)) if retreating else sim.time}
			out[u.idx] = _retreat_order(u, wait_pad, old, rows, urgency)
		else:
			trips.erase(u.idx)
	return out


func _base_point(u: BUnit, old: Dictionary) -> int:
	var pt: int = int(old.get(u.idx, {}).get("point", -1))
	if pt >= 0 and pt < sim.domination.points.size():
		return pt
	var best: int = 0
	var bd: float = INF
	for i in sim.domination.points.size():
		var d: float = u.pos.distance_to(sim.domination.points[i].center)
		if d < bd:
			bd = d
			best = i
	return best


func _heal_order(u: BUnit, pad: Dictionary, old: Dictionary, rows: Array, urgency: float, why: String) -> Dictionary:
	var index: int = _base_point(u, old)
	var order: Dictionary = _objective_order(u, index, "회복", "회복 구역 이동", float(rows[index].priority), urgency, false, false)
	order.goal = pad.center
	order.heal_target = str(pad.id)
	order.heal_reason = why
	order.erase("stage")
	return order


# C-1 retreat: an own-side pad that comes back within RETREAT_PAD_WAIT and is
# safe to reach, for a badly wounded hero to wait beside. Without one the hero
# stays in the objective pool: holding back at spawn or on a quiet point kept
# it out of the game longer than a 12 s respawn and lost head-to-head matches
# (V1.5.2 planner won 24 of 32 while heroes walked home).
func _retreat_pad(u: BUnit, pads: Array, reserved: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_v: float = INF
	for pad in pads:
		if reserved.has(str(pad.id)) or territory(pad.center) > 0.5:
			continue
		var wait: float = float(pad.ready_at) - sim.time
		if wait > RETREAT_PAD_WAIT or _enemies_near(pad.center, float(pad.radius) + 90.0) > 0:
			continue
		var v: float = maxf(0.0, wait) * 60.0 + _route(u, pad.center)
		if v < best_v:
			best_v = v
			best = pad
	if best.is_empty():
		return {}
	var check: Dictionary = _trip_path(u, best.center)
	if bool(check.blocked) or float(check.risk) > TRIP_RISK_LIMIT:
		return {}
	return best


func _retreat_order(u: BUnit, pad: Dictionary, old: Dictionary, rows: Array, urgency: float) -> Dictionary:
	var index: int = _base_point(u, old)
	var center: Vector2 = pad.center
	var goal: Vector2 = sim.arena.resolve_circle(center + (spawn_center - center).limit_length(float(pad.radius) + 40.0), sim.radius(u))
	var why: String = "체력 %.0f%% · 아군 진영 회복 구역 %.0f초 뒤 준비 → 옆에서 대기" % [sim.hp_ratio(u) * 100.0, maxf(0.0, float(pad.ready_at) - sim.time)]
	var order: Dictionary = _objective_order(u, index, "후퇴", why, float(rows[index].priority), urgency, false, false)
	order.goal = goal
	order.center = goal
	order.radius = 70.0
	order.erase("stage")
	return order


# One path search per candidate pad: observed-enemy and hazard risk along the
# route, and whether it passes through an objective the enemy holds.
func _trip_path(u: BUnit, goal: Vector2) -> Dictionary:
	var path: PackedVector2Array = Navigator.for_sim(sim, sim.radius(u)).path_points(u.pos, goal)
	if path.is_empty():
		return {"risk": INF, "blocked": true}
	var worst: float = 0.0
	for portion in [0.25, 0.5, 0.75, 1.0]:
		var sample: Vector2 = path[mini(path.size() - 1, int((path.size() - 1) * portion))]
		var danger: float = _enemies_near(sample, 260.0) * 0.65
		if sim.env.enabled:
			danger += sim.env.hazard_penalty(sample, sim.time + 1.0, sim.radius(u))
		worst = maxf(worst, danger)
	var blocked: bool = false
	for p in sim.domination.points:
		if int(p.owner) != 1 - team and not bool(p.contested):
			continue
		if u.pos.distance_to(p.center) < float(p.radius) + 60.0 or goal.distance_to(p.center) < float(p.radius) + 60.0:
			continue
		var reach: float = float(p.radius) + 90.0
		var prev: Vector2 = u.pos
		for k in path.size():
			# Segment distance: a simplified path may jump straight across a circle.
			var closest: Vector2 = Geometry2D.get_closest_point_to_segment(p.center, prev, path[k])
			prev = path[k]
			if closest.distance_squared_to(p.center) < reach * reach:
				blocked = true
				break
		if blocked:
			break
	return {"risk": worst, "blocked": blocked}


# C-2: expected hazard damage over the next horizon seconds at the hero's
# position, not counting gravity wells whose pull centre is inside the
# hero's assigned circle.
func expected_hold_damage(u: BUnit, horizon: float = 1.0) -> float:
	if not sim.env.enabled:
		return 0.0
	var order: Dictionary = assignments.get(u.idx, {})
	var center: Vector2 = order.get("center", Vector2.INF)
	var radius: float = float(order.get("radius", 0.0))
	var r: float = sim.radius(u)
	# Switch-aware, announced artillery strikes and the closing ring included.
	var total: float = sim.env.expected_hazard_damage(u.pos, sim.time, r, horizon, u)
	if center == Vector2.INF:
		return total
	for h in sim.arena.hazards:
		if (sim.env.disabled_mask & int(h.get("tbit", 0))) != 0:
			continue
		if str(h.get("type", "")) != "gravity" or not Arena.shape_contains(h, u.pos, r):
			continue
		if (h.center as Vector2).distance_to(center) <= radius:
			total -= float(h.get("damage", 0.0)) * Arena.periodic_damage_ticks(h, sim.time, horizon)
	return maxf(0.0, total)


# C-2: true when this hero holds its capture circle and the hazards there are
# not worth leaving it for. For the tactician's steering and move scoring.
func hold_exempt(u: BUnit, horizon: float = 1.0) -> bool:
	if not _flag("hold") or u == null or not u.alive:
		return false
	var order: Dictionary = assignments.get(u.idx, {})
	if order.is_empty() or str(order.get("heal_target", "")) != "" or str(order.get("role", "")) == "후퇴":
		return false
	if u.pos.distance_to(order.center) > float(order.radius) + 10.0:
		return false
	return expected_hold_damage(u, horizon) < HOLD_HAZARD_SHARE * maxf(1.0, u.hp)


func _assign_healing_v15(allies: Array[BUnit], urgency: float) -> void:
	# The V1.4 heal-trip rules, except that a hero who is the body contesting
	# an ongoing capture, or holding a fight on its objective, stays while it
	# can still survive the next exchanges.
	var keep: Dictionary = {}
	for u in allies:
		var order: Dictionary = assignments.get(u.idx, {})
		if order.is_empty():
			continue
		var inside: bool = u.pos.distance_to(order.center) < float(order.radius) + 40.0
		var busy: bool = bool(order.get("enemy_capturing", false)) or (inside and bool(order.get("fight", false)))
		if busy and sim.hp_ratio(u) > 0.3:
			keep[u.idx] = true
	var saved: Dictionary = {}
	for idx in keep:
		saved[idx] = assignments[idx]
		assignments.erase(idx)
	_assign_healing(allies, urgency)
	for idx in saved:
		assignments[idx] = saved[idx]
