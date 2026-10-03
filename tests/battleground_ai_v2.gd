extends SceneTree

# V2 battleground AI matches (B-MODE): reduced full matches with the fast
# zone, one per format and map (solo 12 on the metropolis, duo 6 teams on the
# wildwood, trio 4 teams on the highland). Each must end with a last team
# standing before the 600 s cap, with no rule-invariant errors and no path
# grid built mid-match. Reports kills, knocks, revives, item pickups, zone
# deaths, finish time and tick cost (shared with tools/br_eval_v2.gd).
# B-SQUAD scenario checks (deterministic micro-battles on the highland map):
# loot-phase pacing (no fight between even opponents, a clearly good fight
# and an attack are still answered, nearby roaming), standing outside a
# damaging circle, the public zone forecast and edge cost, contesting a knock
# then reviving, drag-away crawling, reviving in brush, the knocking side
# finishing only when the downed hero's teammates are away, third-party
# entries, early rotation, final-circle holding, the leash and enemy groups
# per visible team.

const Eval := preload("res://tools/br_eval_v2.gd")
const CASES := [
	{"format": "solo", "teams": 12, "map": "br_ashen_metropolis", "seed": 7},
	{"format": "duo", "teams": 6, "map": "br_wildwood_frontier", "seed": 11},
	{"format": "trio", "teams": 4, "map": "br_highland_ruins", "seed": 13},
]

var passed: int = 0
var failed: Array = []
var metrics: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed.append(label)
		push_error("FAIL " + label)


func _run() -> void:
	DB.ensure_loaded()
	_squad_scenarios()
	_tactics_scenarios()
	for c in CASES:
		_match(c)
	var status: String = "PASS" if failed.is_empty() else "FAIL"
	print("BATTLEGROUND_AI_V2 ", JSON.stringify({"status": status, "passed": passed, "failed": failed, "metrics": metrics}))
	# Prints the metrics; writes a JSON report only with --report=<path>.
	var path: String = ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):
			path = arg.substr(9)
	if path != "":
		var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify({"suite": "battleground_ai_v2", "status": status, "passed": passed, "failed": failed, "metrics": metrics}, "  "))
	quit(0 if failed.is_empty() else 1)


func _match(c: Dictionary) -> void:
	var fmt: String = str(c.format)
	var tag: String = "%s%d/%s" % [fmt, int(c.teams), str(c.map)]
	var r: Dictionary = Eval.run_match(fmt, int(c.teams), str(c.map), int(c.seed), "fast", BattlegroundMode.MAX_TIME)
	var teams: int = int(c.teams)
	_check(bool(r.finished) and str(r.reason) == "battleground_last", "%s ends with a last team standing (%s at %.1f s)" % [tag, str(r.reason), float(r.finish_time)])
	_check(float(r.finish_time) < BattlegroundMode.MAX_TIME, "%s finishes before the cap (%.1f s)" % [tag, float(r.finish_time)])
	_check((r.invariant_errors as Array).is_empty(), "%s keeps the rule invariants %s" % [tag, str(r.invariant_errors)])
	_check(int(r.nav_mid_builds) == 0, "%s builds no path grid mid-match (%d)" % [tag, int(r.nav_mid_builds)])
	var places: Dictionary = {}
	for team in r.placement:
		places[int(r.placement[team])] = true
	_check(places.size() == teams and places.has(1) and places.has(teams), "%s ranks every team 1..%d" % [tag, teams])
	_check(int(r.kills) >= 1 and int(r.item_pickups) >= teams, "%s has fights and looting (%d kills, %d pickups)" % [tag, int(r.kills), int(r.item_pickups)])
	var deaths: int = 0
	for k in r.death_causes:
		deaths += int(r.death_causes[k])
	_check(deaths == int(r.heroes) - _survivors(r), "%s death causes cover every eliminated hero" % tag)
	if fmt != "solo":
		_check(int(r.knocks) >= 1, "%s: heroes get downed (%d knocks)" % [tag, int(r.knocks)])
	metrics[tag] = {"finish_time": r.finish_time, "kills": r.kills, "knocks": r.knocks, "revives": r.revives,
		"revive_starts": r.revive_starts, "revive_cancels": r.revive_cancels, "item_pickups": r.item_pickups, "swaps": r.swaps,
		"zone_deaths": r.zone_deaths, "death_causes": r.death_causes, "tick_mean_ms": r.tick_mean_ms, "tick_p99_ms": r.tick_p99_ms,
		"tick_max_ms": r.tick_max_ms, "build_ms": r.build_ms, "clump_median_px": r.clump_median_px, "clump_enemy_median_px": r.clump_enemy_median_px, "winner_team": r.winner_team,
		"alive_series": _thin(r.alive_series)}
	print("BR_MATCH ", tag, " ", JSON.stringify(metrics[tag]))


# Squad brain micro-scenarios on the highland map (no enemy in sight):
# the nearest standing member revives a downed one while the third covers,
# and members claim different items (one member per item).
func _squad_scenarios() -> void:
	var sim: BattleSim = BattleSim.new({"ruleset": "battleground", "arena_id": "br_highland_ruins", "map_seed": 7, "seed": 808,
		"squad": 3, "teams": [["archer", "mage", "giant"], ["swordsman", "nitro", "sniper"]], "zone_speed": "normal"})
	var br: BattlegroundMode = sim.battleground
	br.field.clear()
	br._field_dirty = true
	var c: Vector2 = br.zone.centers[0]
	var a: Array = br.team_members(0)
	var b: Array = br.team_members(1)
	var offs: Array = [Vector2(0, 0), Vector2(260, 0), Vector2(420, 120)]
	for k in 3:
		(a[k] as BUnit).pos = sim.arena.resolve_circle(c + offs[k], sim.radius(a[k]))
		(b[k] as BUnit).pos = sim.arena.resolve_circle(c + Vector2(0, 2200) + offs[k], sim.radius(b[k]))
	for t in sim.team_count:
		sim.controllers[t] = AIFactory.make("tactician", sim, t)
	sim.start()
	var down: BUnit = a[0]
	sim.apply_damage(b[0], down, {"school": "true", "base": 100000.0, "frozen": true}, {"source_type": "ABILITY"})
	_check(br.is_downed(down), "scenario: hero downed with two teammates up")
	var brain: BattlegroundSquadBrain = sim.controllers[0]
	var revived_by: int = -1
	var roles: Dictionary = {}
	var t_end: float = sim.time + 20.0
	while sim.time < t_end and sim.state == BattleSim.RUNNING:
		sim.step()
		if roles.is_empty() and str(brain.squad_intent.get("mode", "")) == "revive":
			for m in a:
				roles[(m as BUnit).idx] = str((brain.member_goal.get((m as BUnit).idx, {}) as Dictionary).get("role", ""))
		for ev in sim.tick_events:
			if str(ev.type) == "BR_REVIVED" and int(ev.g) == down.idx:
				revived_by = int(ev.s)
		if revived_by >= 0:
			break
	var nearest: BUnit = a[1]
	_check(revived_by == nearest.idx, "scenario: the nearest standing teammate revives (by %d, expected %d)" % [revived_by, nearest.idx])
	_check(str(roles.get((a[1] as BUnit).idx, "")) == "reviver" and str(roles.get((a[2] as BUnit).idx, "")) == "cover", "scenario: one reviver, the other covers (%s)" % str(roles))
	metrics["scenario_revive_s"] = snappedf(sim.time, 0.1)
	# Loot claims: two known items near the squad, at most one member each.
	for k in 2:
		br.uid_seq += 1
		var p: Vector2 = sim.arena.resolve_circle(c + Vector2(-200.0 + 150.0 * k, -220.0), 14.0)
		br.field.append({"uid": br.uid_seq, "item": "l_heart" if k == 0 else "l_crown", "pos": p, "t": sim.time, "dropped": -1})
	br._field_dirty = true
	var claimed_ok: bool = true
	var saw_claims: bool = false
	for i in 60:
		sim.step()
		var owners: Dictionary = {}
		for uid in brain.claims:
			var who: int = int(brain.claims[uid])
			if owners.has(who):
				claimed_ok = false
			owners[who] = true
			saw_claims = true
	_check(saw_claims and claimed_ok, "scenario: loot claims give each item to one member and each member one item")
	sim.dispose()


func _survivors(r: Dictionary) -> int:
	var rows: Array = r.alive_series
	return int((rows[rows.size() - 1] as Array)[2]) if not rows.is_empty() else 0


# Alive-team counts only where they change.
func _thin(rows: Array) -> Array:
	var out: Array = []
	var last: int = -1
	for row in rows:
		if int(row[1]) != last:
			out.append([snappedf(float(row[0]), 0.1), int(row[1])])
			last = int(row[1])
	return out


# ---------------------------------------------------------------- B-SQUAD scenarios

const SCN_MAP := "br_highland_ruins"


func _tactics_scenarios() -> void:
	var t0: int = Time.get_ticks_msec()
	_scn_pacing()
	_scn_outside_zone()
	_scn_zone_forecast()
	_scn_contest_then_revive()
	_scn_drag_away()
	_scn_revive_in_brush()
	_scn_knocker_weighs()
	_scn_third_party()
	_scn_rotate_early()
	_scn_hold_late()
	_scn_leash()
	_scn_groups()
	_scn_revive_information()
	metrics["scenarios_ms"] = Time.get_ticks_msec() - t0


# A battleground on the highland map, no field items, team t's members at
# spots[t][k], teams in `passive` without orders (TeamController), every
# other team on the battleground AI, the match clock started at `t0` s and
# hero health ratios from `hp` (hero index -> ratio) set before the start.
func _scn(teams: Array, squad: int, spots: Array, passive: Array = [], t0: float = 0.0, hp: Dictionary = {}, seed_v: int = 808) -> BattleSim:
	var sim: BattleSim = BattleSim.new({"ruleset": "battleground", "arena_id": SCN_MAP, "map_seed": 7, "seed": seed_v, "squad": squad,
		"teams": teams, "zone_speed": "normal"})
	var br: BattlegroundMode = sim.battleground
	br.field.clear()
	br._field_dirty = true
	for t in teams.size():
		var mem: Array = br.team_members(t)
		for k in mem.size():
			var u: BUnit = mem[k]
			u.pos = sim.arena.resolve_circle(spots[t][k], sim.radius(u))
			u.prev_pos = u.pos
	for k2 in hp:
		var hu: BUnit = sim.heroes[int(k2)]
		hu.hp = sim.max_hp(hu) * float(hp[k2])
	for t2 in sim.team_count:
		sim.controllers[t2] = TeamController.new(sim, t2) if passive.has(t2) else AIFactory.make("tactician", sim, t2)
	sim.time = t0
	sim.start()
	return sim


func _steps(sim: BattleSim, seconds: float) -> void:
	for i in int(round(seconds / BattleSim.DT)):
		sim.step()


func _down(sim: BattleSim, by: BUnit, who: BUnit) -> void:
	sim.apply_damage(by, who, {"school": "true", "base": 100000.0, "frozen": true}, {"source_type": "ABILITY"})


func _set_hp(sim: BattleSim, u: BUnit, ratio: float) -> void:
	u.hp = sim.max_hp(u) * ratio


# Open ground near the first circle's centre: walkable for a 30 px body, out
# of brush, with clear sight and walking lines `reach` px out in 8 directions
# (deterministic spiral search).
func _open_spot(sim: BattleSim, reach: float) -> Vector2:
	var a: Arena = sim.arena
	var c: Vector2 = sim.battleground.zone.centers[0]
	for ring in 40:
		var n: int = maxi(1, ring * 6)
		for k in n:
			var p: Vector2 = c + Vector2.from_angle(TAU * float(k) / float(n)) * 120.0 * float(ring)
			if not a.is_walkable(p, 30.0) or a.forest_at(p) >= 0:
				continue
			var ok: bool = true
			for d in 8:
				var q: Vector2 = p + Vector2.from_angle(TAU * float(d) / 8.0) * reach
				if not a.is_walkable(q, 30.0) or a.forest_at(q) >= 0 or a.segment_blocked(p, q, 30.0, Arena.MASK_UNITS) \
						or not a.line_of_sight(p, q, 2.0) or a.forest_occludes(p, q):
					ok = false
					break
			if ok:
				return p
	return c


# Loot-phase pacing (solo): the same hero twice, 420 px apart in the open.
func _scn_pacing() -> void:
	var probe: BattleSim = _scn([["swordsman"], ["swordsman"]], 1, [[Vector2.ZERO], [Vector2.ZERO]], [0, 1])
	var o: Vector2 = _open_spot(probe, 500.0)
	probe.dispose()
	var spots: Array = [[o], [o + Vector2(420.0, 0.0)]]
	# Even odds in the loot phase: nobody starts the fight; both step aside.
	var sim: BattleSim = _scn([["swordsman"], ["swordsman"]], 1, spots)
	sim.step()
	var both_seen: bool = sim.is_seen(0, sim.heroes[1]) and sim.is_seen(1, sim.heroes[0])
	var hunted: Array = []
	var spaced: bool = false
	for i in 90:
		sim.step()
		for t in 2:
			var it: Dictionary = (sim.controllers[t] as BattlegroundSoloBrain).intent
			var m: String = str(it.get("mode", ""))
			if m in ["hunt", "chase", "listen"] and not hunted.has(m):
				hunted.append(m)
			if m == "evade" and str(it.get("sub", "")) == "space":
				spaced = true
	_check(both_seen and hunted.is_empty() and spaced, "pacing: even opponents in sight during the loot phase step aside, no fight (seen %s, modes %s, spaced %s)" % [str(both_seen), str(hunted), str(spaced)])
	var roam: Vector2 = (sim.controllers[0] as BattlegroundSoloBrain).roam_goal
	_check(roam.is_finite() and roam.distance_to(sim.heroes[0].pos) < 1300.0, "pacing: loot-phase roaming stays near (%.0f px)" % (roam.distance_to(sim.heroes[0].pos) if roam.is_finite() else -1.0))
	sim.dispose()
	# Attacked in the loot phase: the hero answers (fights back or runs).
	var sim1: BattleSim = _scn([["swordsman"], ["swordsman"]], 1, spots)
	sim1.step()
	sim1.apply_damage(sim1.heroes[1], sim1.heroes[0], {"school": "true", "base": 60.0, "frozen": true}, {"source_type": "BASIC_ATTACK", "basic": true})
	var answer: String = ""
	for i2 in 45:
		sim1.step()
		var it2: Dictionary = (sim1.controllers[0] as BattlegroundSoloBrain).intent
		if str(it2.get("mode", "")) == "hunt" or (str(it2.get("mode", "")) == "evade" and str(it2.get("sub", "")) != "space"):
			answer = str(it2.get("mode", ""))
			break
	_check(answer != "", "pacing: a hero attacked in the loot phase fights back or flees (%s)" % answer)
	sim1.dispose()
	# Clearly good odds in the loot phase: the healthy hero takes the fight.
	var sim2: BattleSim = _scn([["swordsman"], ["swordsman"]], 1, spots, [], 0.0, {1: 0.25})
	var took: bool = false
	for i3 in 60:
		sim2.step()
		if str((sim2.controllers[0] as BattlegroundSoloBrain).intent.get("mode", "")) == "hunt":
			took = true
			break
	_check(took, "pacing: clearly good odds are still taken in the loot phase")
	# The calm factor: 1 before the first shrink, easing out over it.
	var z: BrZone = sim2.battleground.zone
	var rows: Array = BrZone.schedule_rows("normal")
	var c0: float = BattlegroundSoloBrain.calm_factor(z.public_view(10.0), rows, 10.0)
	var c1: float = BattlegroundSoloBrain.calm_factor(z.public_view(74.0), rows, 74.0)
	var c2: float = BattlegroundSoloBrain.calm_factor(z.public_view(105.0), rows, 105.0)
	var c3: float = BattlegroundSoloBrain.calm_factor(z.public_view(140.0), rows, 140.0)
	_check(c0 == 1.0 and c1 == 1.0 and absf(c2 - 0.5) < 0.02 and c3 == 0.0, "pacing: calm factor 1 / 1 / 0.5 / 0 at 10 / 74 / 105 / 140 s (%.2f %.2f %.2f %.2f)" % [c0, c1, c2, c3])
	sim2.dispose()


# Standing outside a damaging circle is urgent: rotate inward at once.
func _scn_outside_zone() -> void:
	var probe: BattleSim = _scn([["archer"], ["giant"]], 1, [[Vector2.ZERO], [Vector2.ZERO]], [0, 1])
	var z: BrZone = probe.battleground.zone
	var t0: float = 200.0
	var c: Vector2 = z.center_at(t0)
	var r: float = z.radius_at(t0)
	var spot: Vector2 = Vector2.INF
	for k in 16:
		var p: Vector2 = c + Vector2.from_angle(TAU * float(k) / 16.0) * (r + 160.0)
		if probe.arena.is_walkable(p, 30.0) and p.x > probe.arena.min_x + 80.0 and p.x < probe.arena.max_x - 80.0 and p.y > probe.arena.min_y + 80.0 and p.y < probe.arena.max_y - 80.0:
			spot = p
			break
	probe.dispose()
	if not spot.is_finite():
		_check(false, "zone: found a walkable spot outside the circle")
		return
	var sim: BattleSim = _scn([["archer"], ["giant"]], 1, [[spot], [c + (c - spot).normalized() * 600.0]], [1], t0)
	var hero: BUnit = sim.heroes[0]
	var d0: float = hero.pos.distance_to(c) - r
	_steps(sim, 0.6)
	var brain: BattlegroundSoloBrain = sim.controllers[0]
	_check(str(brain.intent.get("mode", "")) == "rotate" and brain.lod_urgent(hero), "zone: a hero outside a damaging circle rotates at once (%s)" % str(brain.intent.get("mode", "")))
	_steps(sim, 6.0)
	var d1: float = hero.pos.distance_to(sim.battleground.zone.center_at(sim.time)) - sim.battleground.zone.radius_at(sim.time)
	_check(d1 < d0 - 150.0 or d1 <= 0.0, "zone: it walks back in (%.0f -> %.0f px outside)" % [d0, d1])
	sim.dispose()


# The forecast the AI makes from the public view and timetable matches the
# real circle wherever the coming circle is public; the edge cost is 0 deep
# inside and high on a closing edge.
func _scn_zone_forecast() -> void:
	var sim: BattleSim = _scn([["archer"], ["giant"]], 1, [[Vector2.ZERO], [Vector2.ZERO]], [0, 1])
	var z: BrZone = sim.battleground.zone
	var rows: Array = BrZone.schedule_rows("normal")
	var worst: float = 0.0
	var cases: int = 0
	for t in [50.0, 70.0, 100.0, 150.0, 190.0, 210.0, 250.0, 300.0, 330.0, 400.0]:
		var v: Dictionary = z.public_view(t)
		if not bool(v.next_known):
			continue
		var target: int = int(v.phase) + (0 if str(v.state) == "shrink" else 1)
		for dt in [4.0, 12.0, 30.0]:
			if z.phase_at(t + dt) > target:
				continue
			var circ: Array = BattlegroundSoloBrain.circle_at(v, rows, t, dt)
			worst = maxf(worst, maxf((circ[0] as Vector2).distance_to(z.center_at(t + dt)), absf(float(circ[1]) - z.radius_at(t + dt))))
			cases += 1
	_check(cases >= 12 and worst < 1.0, "zone: public forecast matches the circle (%d cases, worst %.2f px)" % [cases, worst])
	var v2: Dictionary = z.public_view(100.0)
	var deep: float = BattlegroundSoloBrain.edge_cost_at(v2, rows, 100.0, v2.center)
	var edge_p: Vector2 = (v2.center as Vector2) + Vector2.RIGHT * float(v2.radius)
	var at_edge: float = BattlegroundSoloBrain.edge_cost_at(v2, rows, 100.0, edge_p)
	_check(deep == 0.0 and at_edge > 15.0, "zone: edge cost 0 deep inside, %.1f on a closing edge" % at_edge)
	sim.dispose()


# A knock with decent odds: the squad contests it, then revives.
func _scn_contest_then_revive() -> void:
	var probe: BattleSim = _scn([["swordsman", "archer"], ["swordsman", "archer"]], 2, [[Vector2.ZERO, Vector2.ZERO], [Vector2.ZERO, Vector2.ZERO]], [0, 1])
	var o: Vector2 = _open_spot(probe, 450.0)
	probe.dispose()
	var spots: Array = [[o, o + Vector2(-330.0, 0.0)], [o + Vector2(150.0, 0.0), o + Vector2(0.0, 2600.0)]]
	var sim: BattleSim = _scn([["swordsman", "archer"], ["swordsman", "archer"]], 2, spots)
	var br: BattlegroundMode = sim.battleground
	var a1: BUnit = br.team_members(0)[0]
	var a2: BUnit = br.team_members(0)[1]
	var b1: BUnit = br.team_members(1)[0]
	_set_hp(sim, b1, 0.3)
	_down(sim, b1, a1)
	_check(br.is_downed(a1), "contest: the hero is downed")
	var brain: BattlegroundSquadBrain = sim.controllers[0]
	var saw_contest: bool = false
	var guard: bool = false
	var revived: bool = false
	var t_end: float = sim.time + 28.0
	while sim.time < t_end and sim.state == BattleSim.RUNNING:
		sim.step()
		if str(brain.squad_intent.get("mode", "")) == "contest" and int(brain.squad_intent.get("target", -1)) == a1.idx:
			saw_contest = true
			if str((brain.member_goal.get(a2.idx, {}) as Dictionary).get("role", "")) in ["guard", "reviver"]:
				guard = true
		for ev in sim.tick_events:
			if str(ev.type) == "BR_REVIVED" and int(ev.g) == a1.idx:
				revived = true
		if revived:
			break
	_check(saw_contest and guard, "contest: the squad fights for its downed member (contest %s, guard %s)" % [str(saw_contest), str(guard)])
	_check(revived, "contest: then revives it (b1 %s)" % ("downed" if br.is_downed(b1) else ("dead" if not b1.alive else "standing %.0f%%" % (sim.hp_ratio(b1) * 100.0))))
	metrics["scenario_contest_revive_s"] = snappedf(sim.time, 0.1)
	sim.dispose()


# Drag-away: the downed hero crawls toward its squad and away from the enemy.
func _scn_drag_away() -> void:
	var probe: BattleSim = _scn([["mage", "giant"], ["werewolf", "sniper"]], 2, [[Vector2.ZERO, Vector2.ZERO], [Vector2.ZERO, Vector2.ZERO]], [0, 1])
	var o: Vector2 = _open_spot(probe, 480.0)
	probe.dispose()
	var spots: Array = [[o, o + Vector2(-460.0, 0.0)], [o + Vector2(250.0, 0.0), o + Vector2(0.0, 2600.0)]]
	var sim: BattleSim = _scn([["mage", "giant"], ["werewolf", "sniper"]], 2, spots, [1])
	var br: BattlegroundMode = sim.battleground
	var a1: BUnit = br.team_members(0)[0]
	var a2: BUnit = br.team_members(0)[1]
	var b1: BUnit = br.team_members(1)[0]
	_down(sim, b1, a1)
	var d_enemy: float = a1.pos.distance_to(b1.pos)
	var d_team: float = a1.pos.distance_to(a2.pos)
	var p0: Vector2 = a1.pos
	_steps(sim, 2.0)
	var moved: Vector2 = a1.pos - p0
	var away: float = moved.dot((p0 - b1.pos).normalized())
	_check(br.is_downed(a1) and away > 25.0 and a1.pos.distance_to(b1.pos) > d_enemy + 20.0, "drag-away: crawls away from the standing enemy (%.0f px)" % away)
	_check(moved.dot((a2.pos - p0).normalized()) > 0.0 or a1.pos.distance_to(a2.pos) < d_team, "drag-away: toward its squad")
	sim.dispose()


# Brush and a hero standing outside it, both in the open: [downed spot,
# outward direction, forest index].
func _brush_site(sim: BattleSim) -> Array:
	var a: Arena = sim.arena
	var c: Vector2 = sim.battleground.zone.centers[0]
	var order: Array = []
	for k in a.forest_x.size():
		if a.forest_r[k] >= 45.0:
			order.append([Vector2(a.forest_x[k], a.forest_y[k]).distance_to(c), k])
	order.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) < float(y[0]))
	for row in order:
		var k2: int = int(row[1])
		var fc: Vector2 = Vector2(a.forest_x[k2], a.forest_y[k2])
		for d in 8:
			var dir: Vector2 = Vector2.from_angle(TAU * float(d) / 8.0)
			var p: Vector2 = fc + dir * (a.forest_r[k2] + 110.0)
			var threat: Vector2 = p + dir * 300.0
			var mate: Vector2 = p + dir.rotated(PI * 0.5) * 240.0
			var ok: bool = a.is_walkable(p, 30.0) and a.forest_at(p) < 0 and a.is_walkable(threat, 30.0) and a.forest_at(threat) < 0 \
				and a.is_walkable(mate, 30.0) and a.forest_at(mate) < 0 and not a.segment_blocked(p, fc, 26.0, Arena.MASK_UNITS) \
				and a.line_of_sight(p, threat, 2.0) and a.line_of_sight(p, mate, 2.0) and not a.forest_occludes(p, threat)
			if ok:
				return [p, dir, k2]
	return []


# Revive in brush: a threat was seen near the downed hero and has gone; the
# hero crawls into the nearby brush and is revived there.
func _scn_revive_in_brush() -> void:
	var probe: BattleSim = _scn([["mage", "giant"], ["werewolf", "sniper"]], 2, [[Vector2.ZERO, Vector2.ZERO], [Vector2.ZERO, Vector2.ZERO]], [0, 1])
	var site: Array = _brush_site(probe)
	probe.dispose()
	if site.is_empty():
		_check(false, "brush revive: found a brush site")
		return
	var p: Vector2 = site[0]
	var dir: Vector2 = site[1]
	var spots: Array = [[p, p + dir.rotated(PI * 0.5) * 240.0], [p + dir * 300.0, p + Vector2(0.0, 2600.0)]]
	var sim: BattleSim = _scn([["mage", "giant"], ["werewolf", "sniper"]], 2, spots, [1])
	var br: BattlegroundMode = sim.battleground
	var a1: BUnit = br.team_members(0)[0]
	var b1: BUnit = br.team_members(1)[0]
	_down(sim, b1, a1)
	_steps(sim, 1.0)
	# The threat leaves.
	b1.pos = sim.arena.resolve_circle(b1.pos + dir * 2400.0, sim.radius(b1))
	b1.prev_pos = b1.pos
	var brain: BattlegroundSquadBrain = sim.controllers[0]
	var spot: Vector2 = Vector2.INF
	var revived_in: int = -2
	var t_end: float = sim.time + 22.0
	while sim.time < t_end and sim.state == BattleSim.RUNNING:
		sim.step()
		if not spot.is_finite() and str(brain.squad_intent.get("mode", "")) == "revive":
			spot = brain.squad_intent.get("spot", Vector2.INF)
		for ev in sim.tick_events:
			if str(ev.type) == "BR_REVIVED" and int(ev.g) == a1.idx:
				revived_in = sim.arena.forest_at(a1.pos)
		if revived_in != -2:
			break
	_check(spot.is_finite() and sim.arena.forest_at(spot) >= 0, "brush revive: the revive spot is in the brush")
	_check(revived_in >= 0, "brush revive: revived inside the brush (%d)" % revived_in)
	sim.dispose()


# The knocking side: standing enemies first while they are near; with the
# downed hero's teammate away, finish it.
func _scn_knocker_weighs() -> void:
	var probe: BattleSim = _scn([["archer", "mage", "giant"], ["swordsman", "nitro"]], 3, [[Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], [Vector2.ZERO, Vector2.ZERO]], [0, 1])
	var o: Vector2 = _open_spot(probe, 450.0)
	probe.dispose()
	for near in [true, false]:
		var mate: Vector2 = o + (Vector2(260.0, -160.0) if near else Vector2(0.0, 2600.0))
		var spots: Array = [[o, o + Vector2(-80.0, 60.0), o + Vector2(-80.0, -60.0)], [o + Vector2(260.0, 0.0), mate]]
		var sim: BattleSim = _scn([["archer", "mage", "giant"], ["swordsman", "nitro"]], 3, spots, [1])
		var br: BattlegroundMode = sim.battleground
		var b1: BUnit = br.team_members(1)[0]
		var b2: BUnit = br.team_members(1)[1]
		_down(sim, br.team_members(0)[0], b1)
		_steps(sim, 1.0)
		var brain: BattlegroundSquadBrain = sim.controllers[0]
		var focus: int = int(brain.squad_intent.get("focus", -1))
		var mode: String = str(brain.squad_intent.get("mode", ""))
		if near:
			_check(mode in ["engage", "third"] and focus == b2.idx, "knocker: its standing teammate first (%s, focus %d, b2 %d)" % [mode, focus, b2.idx])
		else:
			_check(mode in ["engage", "third"] and focus == b1.idx, "knocker: with the teammate away, finish the downed hero (%s, focus %d)" % [mode, focus])
		sim.dispose()


# Third party: two other teams trading blows in sight.
func _scn_third_party() -> void:
	var probe: BattleSim = _scn([["archer", "mage"], ["swordsman", "nitro"], ["giant", "sniper"]], 2, [[Vector2.ZERO, Vector2.ZERO], [Vector2.ZERO, Vector2.ZERO], [Vector2.ZERO, Vector2.ZERO]], [0, 1, 2], 150.0)
	var o: Vector2 = _open_spot(probe, 500.0)
	probe.dispose()
	var spots: Array = [[o, o + Vector2(-60.0, 50.0)], [o + Vector2(460.0, 0.0), o + Vector2(0.0, 2600.0)], [o + Vector2(460.0, 120.0), o + Vector2(0.0, -2600.0)]]
	var sim: BattleSim = _scn([["archer", "mage"], ["swordsman", "nitro"], ["giant", "sniper"]], 2, spots, [1, 2], 150.0)
	var br: BattlegroundMode = sim.battleground
	var b1: BUnit = br.team_members(1)[0]
	var c1: BUnit = br.team_members(2)[0]
	_set_hp(sim, b1, 0.5)
	_set_hp(sim, c1, 0.5)
	var brain: BattlegroundSquadBrain = sim.controllers[0]
	var saw: bool = false
	for i in 60:
		if i % 10 == 0:
			sim.apply_damage(b1, c1, {"school": "true", "base": 5.0, "frozen": true}, {"source_type": "BASIC_ATTACK", "basic": true})
			sim.apply_damage(c1, b1, {"school": "true", "base": 5.0, "frozen": true}, {"source_type": "BASIC_ATTACK", "basic": true})
		sim.step()
		if str(brain.squad_intent.get("mode", "")) == "third":
			saw = true
			break
	_check(saw, "third party: joins a fight between two other teams in sight (%s)" % str(brain.squad_intent.get("mode", "")))
	sim.dispose()


# Rotation: outside the announced circle in the loot phase the squad rotates,
# and squads start earlier than solo heroes (slack 45 s vs 30 s).
func _scn_rotate_early() -> void:
	var probe: BattleSim = _scn([["archer", "mage"], ["swordsman", "nitro"]], 2, [[Vector2.ZERO, Vector2.ZERO], [Vector2.ZERO, Vector2.ZERO]], [0, 1], 50.0)
	var z: BrZone = probe.battleground.zone
	var nc: Vector2 = z.centers[1]
	var nr: float = z.radii[1]
	var spot: Vector2 = Vector2.INF
	for k in 16:
		var p: Vector2 = nc + Vector2.from_angle(TAU * float(k) / 16.0) * (nr + 500.0)
		if probe.arena.is_walkable(p, 30.0) and p.x > probe.arena.min_x + 150.0 and p.x < probe.arena.max_x - 150.0 and p.y > probe.arena.min_y + 150.0 and p.y < probe.arena.max_y - 150.0:
			spot = p
			break
	probe.dispose()
	if not spot.is_finite():
		_check(false, "rotate: found a spot outside the announced circle")
		return
	var sim: BattleSim = _scn([["archer", "mage"], ["swordsman", "nitro"]], 2, [[spot, spot + Vector2(0.0, 60.0)], [nc, nc + Vector2(60.0, 0.0)]], [1], 50.0)
	var brain: BattlegroundSquadBrain = sim.controllers[0]
	var a1: BUnit = sim.battleground.team_members(0)[0]
	var d0: float = a1.pos.distance_to(nc)
	_steps(sim, 1.0)
	_check(str(brain.squad_intent.get("mode", "")) == "rotate", "rotate: the squad heads for the announced circle (%s)" % str(brain.squad_intent.get("mode", "")))
	_steps(sim, 6.0)
	_check(a1.pos.distance_to(nc) < d0 - 250.0, "rotate: and walks in (%.0f -> %.0f px from its centre)" % [d0, a1.pos.distance_to(nc)])
	var rows: Array = BrZone.schedule_rows("normal")
	var v: Dictionary = sim.battleground.zone.public_view(60.0)
	var never_less: bool = true
	var sooner: int = 0
	for extra in [300.0, 600.0, 900.0, 1200.0, 1500.0]:
		var far: Vector2 = nc + (spot - nc).normalized() * (nr + extra)
		var squad_u: float = float(BattlegroundSoloBrain.zone_sense(v, far, 95.0, rows, 60.0, BattlegroundSquadBrain.ROTATE_SLACK).urgency)
		var solo_u: float = float(BattlegroundSoloBrain.zone_sense(v, far, 95.0, rows, 60.0).urgency)
		if squad_u < solo_u:
			never_less = false
		if squad_u > solo_u:
			sooner += 1
	_check(never_less and sooner >= 1, "rotate: squads feel the zone sooner than solo heroes (%d of 5 distances)" % sooner)
	sim.dispose()


# Final circles: with nobody in sight the squad holds a spot deep inside.
func _scn_hold_late() -> void:
	var probe: BattleSim = _scn([["archer", "mage"], ["swordsman", "nitro"]], 2, [[Vector2.ZERO, Vector2.ZERO], [Vector2.ZERO, Vector2.ZERO]], [0, 1], 330.0)
	var z: BrZone = probe.battleground.zone
	var sc: Vector2 = z.centers[4]
	var sr: float = z.radii[4]
	var far: Vector2 = z.center_at(330.0) + Vector2(0.0, z.radius_at(330.0) + 1200.0)
	probe.dispose()
	var sim: BattleSim = _scn([["archer", "mage"], ["swordsman", "nitro"]], 2, [[sc, sc + Vector2(50.0, 40.0)], [far, far + Vector2(60.0, 0.0)]], [1], 330.0)
	var brain: BattlegroundSquadBrain = sim.controllers[0]
	_steps(sim, 1.0)
	var hg: Vector2 = brain.hold_goal
	_check(str(brain.squad_intent.get("mode", "")) == "hold" and hg.is_finite() and hg.distance_to(sc) <= sr * 0.75 + 1.0,
		"hold: final circle, nobody in sight: hold deep inside (%s, %.0f of %.0f px)" % [str(brain.squad_intent.get("mode", "")), hg.distance_to(sc) if hg.is_finite() else -1.0, sr])
	_check(BattlegroundSoloBrain.late_factor(z.public_view(330.0), BattlegroundSoloBrain.half_diag(sim)) == 1.0
		and BattlegroundSoloBrain.late_factor(z.public_view(100.0), BattlegroundSoloBrain.half_diag(sim)) == 0.0, "hold: late factor 0 in the first circles, 1 in the final ones")
	sim.dispose()


# The leash: a member far from the leader comes back.
func _scn_leash() -> void:
	var probe: BattleSim = _scn([["archer", "mage", "giant"], ["swordsman", "nitro", "sniper"]], 3, [[Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]], [0, 1])
	var o: Vector2 = _open_spot(probe, 300.0)
	var a: Arena = probe.arena
	var far: Vector2 = Vector2.INF
	for k in 16:
		var p: Vector2 = o + Vector2.from_angle(TAU * float(k) / 16.0) * 1100.0
		if a.is_walkable(p, 30.0):
			far = p
			break
	var enemy: Vector2 = o + Vector2(0.0, 3000.0)
	probe.dispose()
	var sim: BattleSim = _scn([["archer", "mage", "giant"], ["swordsman", "nitro", "sniper"]], 3,
		[[o, o + Vector2(70.0, 0.0), far], [enemy, enemy + Vector2(60.0, 0.0), enemy + Vector2(-60.0, 0.0)]], [1])
	var br: BattlegroundMode = sim.battleground
	var brain: BattlegroundSquadBrain = sim.controllers[0]
	var lead: BUnit = br.team_members(0)[0]
	var stray: BUnit = br.team_members(0)[2]
	_steps(sim, 1.0)
	var g: Dictionary = brain.member_goal.get(stray.idx, {})
	_check(str(brain.squad_intent.get("mode", "")) == "regroup" or str(g.get("label", "")) == "집결", "leash: a member 1100 px away regroups (%s / %s)" % [str(brain.squad_intent.get("mode", "")), str(g.get("label", ""))])
	_steps(sim, 14.0)
	var spread: float = 0.0
	for m in br.team_members(0):
		spread = maxf(spread, (m as BUnit).pos.distance_to(br.team_members(0)[0].pos))
	_check(spread <= BattlegroundSquadBrain.LEASH_MAX + 50.0, "leash: the squad is back within the leash (%.0f px)" % spread)
	sim.dispose()


# Enemies are grouped by their visible team.
func _scn_groups() -> void:
	var probe: BattleSim = _scn([["archer", "mage"], ["swordsman", "nitro"], ["giant", "sniper"], ["werewolf", "hermes"]], 2,
		[[Vector2.ZERO, Vector2.ZERO], [Vector2.ZERO, Vector2.ZERO], [Vector2.ZERO, Vector2.ZERO], [Vector2.ZERO, Vector2.ZERO]], [0, 1, 2, 3])
	var o: Vector2 = _open_spot(probe, 450.0)
	probe.dispose()
	var spots: Array = [[o, o + Vector2(-60.0, 0.0)], [o + Vector2(380.0, -80.0), o + Vector2(420.0, -20.0)], [o + Vector2(-300.0, 300.0), o + Vector2(0.0, 2600.0)],
		[o + Vector2(2600.0, 0.0), o + Vector2(2660.0, 0.0)]]
	var sim: BattleSim = _scn([["archer", "mage"], ["swordsman", "nitro"], ["giant", "sniper"], ["werewolf", "hermes"]], 2, spots, [1, 2, 3])
	_steps(sim, 0.5)
	var brain: BattlegroundSquadBrain = sim.controllers[0]
	var groups: Dictionary = brain._enemy_groups(brain._standing())
	var sizes: Dictionary = {}
	for tm in groups:
		sizes[int(tm)] = (groups[tm].units as Array).size()
	_check(sizes == {1: 2, 2: 1}, "groups: visible enemies grouped by team, the unseen team left out (%s)" % str(sizes))
	sim.dispose()


func _revive_memory(brain: BattlegroundSquadBrain) -> Array:
	return [brain.enemy_revives.duplicate(true), brain.enemy_revive_until.duplicate(true), brain.enemy_revivers.duplicate(true)]


func _clear_revive_memory(brain: BattlegroundSquadBrain) -> void:
	brain.enemy_revives.clear()
	brain.enemy_revive_until.clear()
	brain.enemy_revivers.clear()


# Replay real mode-produced events through the actual pre_tick entry point,
# with explicit per-observer visibility snapshots. Reset the event time to
# the replay time so this tests information boundaries rather than expiry.
func _replay_revive(sim: BattleSim, brain: BattlegroundSquadBrain, event: Dictionary, source_seen: bool, target_seen: bool) -> void:
	var observed: Dictionary = event.duplicate(true)
	observed.sv[brain.team] = source_seen
	observed.gv[brain.team] = target_seen
	observed.t = sim.time
	sim.ai_events = [observed]
	brain.next_intent_at = INF
	brain.pre_tick(sim)


func _scn_revive_information() -> void:
	var sim: BattleSim = _scn([["archer", "mage"], ["swordsman", "nitro"], ["giant", "sniper"]], 2,
		[[Vector2.ZERO, Vector2.ZERO], [Vector2.ZERO, Vector2.ZERO], [Vector2.ZERO, Vector2.ZERO]], [0, 1, 2])
	var o: Vector2 = _open_spot(sim, 200.0)
	var br: BattlegroundMode = sim.battleground
	var target: BUnit = br.team_members(1)[0]
	var reviver: BUnit = br.team_members(1)[1]
	target.pos = o
	reviver.pos = o + Vector2(70, 0)
	_down(sim, br.team_members(0)[0], target)
	_check(br.start_revive(reviver, target), "revive information: real mode starts the enemy channel")
	var start: Dictionary = sim.tick_events.back().duplicate(true)
	_check(str(start.type) == "BR_REVIVE_START" and start.sv is Array and start.gv is Array,
		"revive information: mode emits source and target visibility snapshots")
	br.cancel_revive(target.idx, "information_fixture")
	var cancel: Dictionary = sim.tick_events.back().duplicate(true)
	_check(str(cancel.type) == "BR_REVIVE_CANCEL", "revive information: real mode emits cancellation")
	_check(br.start_revive(reviver, target), "revive information: real mode restarts the channel")
	sim.time += BattlegroundMode.REVIVE_TIME
	br._update_downed()
	var complete: Dictionary = sim.tick_events.back().duplicate(true)
	_check(str(complete.type) == "BR_REVIVED", "revive information: real mode completes the channel")
	var brain: BattlegroundSquadBrain = BattlegroundSquadBrain.new(sim, 0)
	sim.attach_controller(0, brain)
	_replay_revive(sim, brain, start, true, true)
	_check(int(brain.enemy_revives.get(target.idx, -1)) == reviver.idx and brain.enemy_revivers.has(reviver.idx),
		"revive information: both seen participants may be associated")
	var before: Array = _revive_memory(brain)
	_replay_revive(sim, brain, cancel, false, false)
	_check(_revive_memory(brain) == before, "revive information: hidden cancellation cannot change memory")
	_replay_revive(sim, brain, complete, false, false)
	_check(_revive_memory(brain) == before, "revive information: hidden completion cannot change memory")
	_replay_revive(sim, brain, start, false, false)
	_check(_revive_memory(brain) == before, "revive information: hidden start cannot change memory")
	# A visible target tells us it is being revived, not who the hidden source is.
	_clear_revive_memory(brain)
	_replay_revive(sim, brain, start, false, true)
	_check(brain.enemy_revives.has(target.idx) and int(brain.enemy_revives[target.idx]) == -1 and brain.enemy_revivers.is_empty(),
		"revive information: target-only sight does not reveal the hidden reviver")
	_replay_revive(sim, brain, cancel, false, true)
	_check(brain.enemy_revives.is_empty(), "revive information: observed target cancellation clears target memory")
	# A visible source is worth interrupting, but its hidden target ID is unknown.
	_clear_revive_memory(brain)
	_replay_revive(sim, brain, start, true, false)
	_check(brain.enemy_revives.is_empty() and brain.enemy_revive_until.is_empty() and brain.enemy_revivers.has(reviver.idx),
		"revive information: source-only sight does not reveal the hidden target")
	_replay_revive(sim, brain, complete, true, false)
	_check(brain.enemy_revivers.is_empty(), "revive information: observed source completion clears source memory")
	_replay_revive(sim, brain, start, true, true)
	_replay_revive(sim, brain, cancel, true, false)
	_check(brain.enemy_revives.is_empty() and brain.enemy_revivers.is_empty(),
		"revive information: an observed source ending clears its previously observed association")
	_replay_revive(sim, brain, start, true, true)
	var deadline: float = float(brain.enemy_revive_until[target.idx])
	sim.time = deadline - BattleSim.DT
	sim.ai_events = []
	brain.pre_tick(sim)
	_check(brain.enemy_revives.has(target.idx), "revive information: observed channel memory lasts to its known deadline")
	sim.time = deadline
	sim.ai_events = []
	brain.pre_tick(sim)
	_check(brain.enemy_revives.is_empty() and brain.enemy_revive_until.is_empty() and brain.enemy_revivers.is_empty(),
		"revive information: channel memory expires by public duration without hidden completion")
	sim.dispose()
