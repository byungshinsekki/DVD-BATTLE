extends SceneTree

# V1.5.3 gimmick AI regressions (DESIGN_153 §4 "Gimmick AI" and the Wave-I
# follow-ups for the tactician / intel / control layers). Every scenario plays
# on a private fixture arena, so shipped map data can change freely:
#   artillery   public strike telegraphs (real damage, unseen points) and a
#               hero that steps out of announced strike circles;
#   gates       routes never use a gate closing within 1.5 s, a hero in a
#               closing gate frame leaves it, control route lengths stay finite;
#   jump pads   a pad is taken when it saves >= 30 % of the walk, not when it
#               saves less; portal / pad triggers are soft walls on a walk past;
#   ring        a hero leaves the zone the ring will cover before it gets there;
#   brush       ambush points toward an approaching enemy, brush caution from
#               the hidden enemy's particles, the brush switch in the belief model;
#   politician  contemplation is held while safe (no separation shuffle);
#   control     a holder stays in its circle through a weak gravity pulse.
# Run: godot --headless --path <tree> --script res://tests/ai_gimmicks_153.gd

var passed: int = 0
var failed: Array[String] = []
var metrics: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed.append(label)
		push_error("AI_GIMMICKS_153 " + label)


func fixture(id: String, obstacles: Array = [], hazards: Array = [], forests: Array = [], w: float = 1408.0, h: float = 792.0) -> Arena:
	return Arena.from_data({"id": id, "width": w, "height": h,
		"bounds": {"minX": 40, "maxX": w - 40, "minY": 40, "maxY": h - 40},
		"obstacles": obstacles, "hazards": hazards, "forests": forests})


# Team 0 gets a fresh TacticianBrain (returned via brain()), team 1 stands
# still (no controller) unless red_brain is set.
func battle(blue: Array, red: Array, spots: Array, ar: Arena, seed_v: int = 153801, red_brain: bool = false, max_time: float = 120.0) -> BattleSim:
	var sim: BattleSim = BattleSim.new({"blue": blue, "red": red, "arena_id": "classic", "seed": seed_v, "max_time": max_time})
	sim.arena = ar
	for i in sim.heroes.size():
		var u: BUnit = sim.heroes[i]
		u.pos = spots[i]
		u.prev_pos = u.pos
		u.spawn_pos = u.pos
		u.facing = Vector2.RIGHT if u.team == 0 else Vector2.LEFT
	sim.controllers[0] = TacticianBrain.new(sim, 0)
	sim.controllers[1] = TacticianBrain.new(sim, 1) if red_brain else null
	sim.start()
	return sim


func brain(sim: BattleSim) -> TacticianBrain:
	return sim.controllers[0]


# Scripted walker: the brain only steers this order (no re-decisions).
func script_move(u: BUnit, goal: Vector2) -> void:
	u.command = {"kind": "move", "goal": goal, "purpose": "test", "key": "test"}
	u.next_decision_at = 1.0e9


# New V1.5.3 helpers are reached dynamically so this file also runs on the
# Wave-I tree (there the checks fail instead of the script failing to load).
func safe_goal(b: TacticianBrain, u: BUnit, p: Vector2, r: float, ms: float) -> Vector2:
	return b.call("_gimmick_safe_goal", u, p, r, ms) if b.has_method("_gimmick_safe_goal") else p


func events_of(sim: BattleSim, type: String, idx: int = -1, hazard_type: String = "") -> int:
	var n: int = 0
	for ev: Dictionary in sim.tick_events:
		if str(ev.type) != type:
			continue
		if idx >= 0 and int(ev.get("g", -1)) != idx:
			continue
		if hazard_type != "" and str(ev.get("hazard_type", "")) != hazard_type:
			continue
		n += 1
	return n


func _run() -> void:
	DB.ensure_loaded()
	_artillery_telegraphs()
	_artillery_dodge()
	_gate_routes()
	_gate_frame_escape()
	_gate_timing()
	_gate_route_lengths()
	_jump_pad_choice()
	_portal_soft_wall()
	_ring_leave_early()
	_brush_ambush_and_caution()
	_brush_switch()
	_politician_contemplation()
	_control_gravity_hold()
	_env_costs_switch_aware()
	var result: Dictionary = {"status": "PASS" if failed.is_empty() else "FAIL", "passed": passed, "failed": failed, "metrics": metrics}
	print("AI_GIMMICKS_153 ", JSON.stringify(result))
	quit(0 if failed.is_empty() else 1)


# ------------------------------------------------------------------ artillery
const ART: = {"id": "barrage", "type": "artillery", "shape": "rect", "x": 60, "y": 60, "w": 1288, "h": 672,
	"period": 4.0, "warningDuration": 1.7, "phase": 0.0, "count": 2, "radius": 70.0, "damage": 60.0, "school": "physical", "spread": 16.0}


# Engine follow-up (intel.gd): environment telegraphs are public with their
# real damage, even where no ally can see the strike point.
func _artillery_telegraphs() -> void:
	var wall: Dictionary = {"id": "w", "shape": "rect", "x": 640, "y": 100, "w": 60, "h": 600}
	var sim: BattleSim = battle(["archer"], ["giant"], [Vector2(300, 400), Vector2(1200, 400)], fixture("gim_art_tg", [wall]))
	var b: TacticianBrain = brain(sim)
	var hidden: Vector2 = Vector2(1000, 400)
	sim.telegraphs.append({"id": sim.next_id(), "source": -1, "team": -1, "shape": "circle", "from": hidden, "to": hidden, "radius": 70.0,
		"width": 0.0, "range": 0.0, "angle": 0.0, "start": sim.time, "end": sim.time + 1.5, "ability": null, "action_id": -1,
		"cancelled": false, "dmg": 60.0, "env": true, "hazard": "x", "hazard_type": "artillery"})
	b.intel.observe_fast()
	var rows: Array = b.intel.telegraphs.filter(func(t: Dictionary): return bool(t.get("env", false)))
	check(rows.size() == 1, "an unseen environment strike telegraph is public to the AI")
	check(not rows.is_empty() and is_equal_approx(float(rows[0].dmg), 60.0), "environment telegraphs carry their real strike damage (not the 90 default)")
	check(b.danger_at(sim.heroes[0], hidden, 1.0) >= 60.0 * 0.9, "danger inside an announced strike circle includes the strike")
	sim.env.enabled = false
	b.intel.observe_fast()
	check(b.intel.telegraphs.filter(func(t: Dictionary): return bool(t.get("env", false))).is_empty(), "environment switched off: no environment telegraphs")
	sim.dispose()


# A hero fighting inside a barrage area steps out of announced strike circles;
# the passive target standing next to it is hit whenever a strike aims at it.
func _artillery_dodge() -> void:
	var sim: BattleSim = battle(["archer"], ["giant"], [Vector2(620, 400), Vector2(860, 400)], fixture("gim_art", [], [ART]), 153802, false, 60.0)
	var archer: BUnit = sim.heroes[0]
	var giant: BUnit = sim.heroes[1]
	var aimed: int = 0
	var hits_archer: int = 0
	var hits_giant: int = 0
	while sim.time < 34.0 and sim.state == BattleSim.RUNNING:
		sim.step()
		giant.hp = sim.max_hp(giant)
		for ev: Dictionary in sim.tick_events:
			if str(ev.type) == "ENV_ARTILLERY":
				for p in ev.points:
					if (p as Vector2).distance_to(archer.pos) < 40.0:
						aimed += 1
			elif str(ev.type) == "ENV_HIT" and str(ev.get("hazard_type", "")) == "artillery":
				if int(ev.g) == archer.idx:
					hits_archer += 1
				elif int(ev.g) == giant.idx:
					hits_giant += 1
	metrics["artillery_dodge"] = {"aimed_at_archer": aimed, "archer_hits": hits_archer, "giant_hits": hits_giant}
	check(aimed >= 3, "fixture: strikes are aimed at the archer (%d)" % aimed)
	check(hits_archer * 4 <= aimed, "the archer leaves announced strike circles (%d hits from %d strikes aimed at it)" % [hits_archer, aimed])
	check(hits_giant >= 1, "fixture: a hero that stands still is hit (%d)" % hits_giant)
	sim.dispose()


# ---------------------------------------------------------------------- gates
# A full-height wall at x 690..710 whose only passage is a gate (open for the
# first 5 s of every 10 s cycle, 1.2 s warning).
func _gate_arena(id: String) -> Arena:
	var obs: Array = [{"id": "wall_n", "shape": "rect", "x": 690, "y": 0, "w": 20, "h": 340},
		{"id": "wall_s", "shape": "rect", "x": 690, "y": 452, "w": 20, "h": 400},
		{"id": "gate_mid", "shape": "rect", "x": 690, "y": 340, "w": 20, "h": 112,
			"gate": {"group": "A", "period": 10.0, "openDuration": 5.0, "warningDuration": 1.2, "phase": 0.0}}]
	return fixture(id, obs)


func _set_time(sim: BattleSim, t: float) -> void:
	sim.time = t
	sim.env.prepare()


func _gate_routes() -> void:
	var sim: BattleSim = battle(["archer"], ["giant"], [Vector2(520, 396), Vector2(1250, 120)], _gate_arena("gim_gate"))
	var b: TacticianBrain = brain(sim)
	var u: BUnit = sim.heroes[0]
	var r: float = sim.radius(u)
	var goal: Vector2 = Vector2(940, 396)
	var frame: Rect2 = Rect2(690, 340, 20, 112).grow(r)
	_set_time(sim, 1.0)
	b._route_cache.clear()
	var wp_open: Vector2 = b._route_waypoint(u, goal, r)
	check(sim.arena.nav_sig != 0 and (wp_open - u.pos).normalized().x > 0.7, "an open gate (4 s left) is routed through (wp %s)" % str(wp_open))
	_set_time(sim, 3.9)
	b._route_cache.clear()
	var wp_closing: Vector2 = b._route_waypoint(u, goal, r)
	var crosses: bool = Geometry2D.segment_intersects_segment(u.pos, wp_closing, Vector2(700, 300), Vector2(700, 500)) != null or frame.has_point(wp_closing)
	check(sim.arena.nav_sig == 0 and not crosses, "a gate closing within 1.5 s is not routed through (wp %s)" % str(wp_closing))
	# A walker that starts 1.6 s before the gate closes never gets caught in it.
	_set_time(sim, 3.4)
	u.pos = Vector2(560, 396)
	u.prev_pos = u.pos
	script_move(u, goal)
	var pushed: int = 0
	var inside_at_close: bool = false
	while sim.time < 6.0:
		sim.step()
		pushed += events_of(sim, "ENV_PUSHED", u.idx)
		if absf(sim.time - 5.0) < 0.02 and frame.has_point(u.pos):
			inside_at_close = true
	check(pushed == 0 and not inside_at_close, "a walker heading through a closing gate is never caught in it (pushed %d)" % pushed)
	sim.dispose()


# A hero whose ability approach stops inside an open gate frame that closes
# within 1.5 s steps out across the gate (old rule: the 8-direction hazard
# probe could choose a shockwave ring or the far side and hover in the frame).
func _gate_frame_escape() -> void:
	var sim: BattleSim = battle(["mage"], ["giant"], [Vector2(694, 380), Vector2(1250, 120)], _gate_arena("gim_gate_frame"))
	var b: TacticianBrain = brain(sim)
	var u: BUnit = sim.heroes[0]
	_set_time(sim, 4.2)
	u.pos = Vector2(696, 380)
	u.prev_pos = u.pos
	u.command = {"kind": "move", "goal": u.pos, "purpose": "test", "key": "test"}
	var v: Vector2 = b.steer(u)
	check(v.x < -0.6, "a hero in a closing gate frame leaves across it on the nearer (west) side (v %s)" % str(v))
	u.pos = Vector2(704, 380)
	u.prev_pos = u.pos
	var v2: Vector2 = b.steer(u)
	check(v2.x > 0.6, "the exit side is the nearer face (east) (v %s)" % str(v2))
	_set_time(sim, 1.0)
	var v3: Vector2 = b.steer(u)
	check(absf(v3.x) < 0.3, "a gate with 4 s left does not push anyone (v %s)" % str(v3))
	# Goals in a gate frame that closes before arrival move off the frame.
	_set_time(sim, 3.0)
	u.pos = Vector2(400, 396)
	var g: Vector2 = safe_goal(b, u, Vector2(700, 396), sim.radius(u), 120.0)
	check(not Rect2(690, 340, 20, 112).grow(sim.radius(u)).has_point(g) and g.x < 700.0, "a goal in a gate that closes before arrival moves to the near side (%s)" % str(g))
	sim.dispose()


# Gate timing: a gate that opens within 2.5 s beats a long detour; the hero
# walks to it (and waits at its face) instead of going around.
func _gate_timing() -> void:
	var obs: Array = [{"id": "wall_n", "shape": "rect", "x": 690, "y": 0, "w": 20, "h": 340},
		{"id": "wall_s", "shape": "rect", "x": 690, "y": 452, "w": 20, "h": 220},
		{"id": "gate_mid", "shape": "rect", "x": 690, "y": 340, "w": 20, "h": 112,
			"gate": {"group": "A", "period": 10.0, "openDuration": 5.0, "warningDuration": 1.2, "phase": 0.0}}]
	var sim: BattleSim = battle(["archer"], ["giant"], [Vector2(560, 396), Vector2(1250, 120)], fixture("gim_gate_wait", obs))
	var b: TacticianBrain = brain(sim)
	var u: BUnit = sim.heroes[0]
	var r: float = sim.radius(u)
	_set_time(sim, 8.5)
	b._route_cache.clear()
	var wp: Vector2 = b._route_waypoint(u, Vector2(860, 396), r)
	var dir: Vector2 = (wp - u.pos).normalized()
	check(dir.x > 0.8, "a gate opening in 1.5 s is waited for instead of the detour (wp %s)" % str(wp))
	_set_time(sim, 5.5)
	b._route_cache.clear()
	var wp2: Vector2 = b._route_waypoint(u, Vector2(860, 396), r)
	check((wp2 - u.pos).normalized().y > 0.5, "a gate closed for 4.5 s more is walked around (wp %s)" % str(wp2))
	sim.dispose()


# Engine follow-up (control_strategy / conquest_commander): route lengths are
# keyed by the gate state and a goal behind a closed gate stays finite.
func _gate_route_lengths() -> void:
	var sim: BattleSim = BattleSim.new({"ruleset": "control", "arena_id": "control_crossroads", "blue": ["giant"], "red": ["archer"], "seed": 153803, "max_time": 120.0})
	sim.arena = _gate_arena("gim_gate_ctl")
	var u: BUnit = sim.heroes[0]
	u.pos = Vector2(520, 396)
	sim.start()
	var cs: ControlStrategy = ControlStrategy.new(sim, 0)
	_set_time(sim, 7.0)
	var closed: float = cs._route(u, Vector2(940, 396))
	_set_time(sim, 1.0)
	var open: float = cs._route(u, Vector2(940, 396))
	check(is_finite(closed) and closed > open + 100.0, "a route behind a closed gate is finite and longer than the open route (%.0f vs %.0f)" % [closed, open])
	check(open < 520.0, "the open-gate route is not served from the closed-gate cache (%.0f)" % open)
	cs.dispose()
	sim.dispose()


# ------------------------------------------------------------------ jump pads
# A body-only chasm across the map with a walking gap at its east end; one pad
# on the south rim leaps it. flight is chosen so the pad saves `save` of the walk.
func _pad_arena(id: String, flight: float) -> Arena:
	var chasm: Dictionary = {"id": "chasm", "shape": "rect", "x": 0, "y": 380, "w": 1240, "h": 44, "blocksProjectiles": false, "blocksVision": false}
	var pad: Dictionary = {"id": "leap", "type": "jump_pad", "shape": "circle", "x": 600, "y": 470, "radius": 28.0,
		"target": {"x": 600, "y": 330}, "flightTime": flight, "cooldown": 2.0}
	return fixture(id, [chasm], [pad])


func _pad_trial(save: float) -> Dictionary:
	var probe: Arena = _pad_arena("gim_pad_probe", 0.1)
	var start: Vector2 = Vector2(760, 600)
	var goal: Vector2 = Vector2(760, 230)
	var sim0: BattleSim = battle(["archer"], ["giant"], [start, Vector2(120, 120)], probe)
	var u0: BUnit = sim0.heroes[0]
	var r: float = sim0.radius(u0)
	var nav: Navigator = Navigator.for_arena(probe, r)
	var walk: float = nav.direct_length(start, goal, r)
	var ms: float = sim0.stat(u0, BattleSim.S_MS)
	var parts: float = nav._to_entry(0, start) + nav._from_exit(0, goal)
	sim0.dispose()
	var flight: float = maxf(0.05, ((1.0 - save) * walk - parts) / ms)
	var sim: BattleSim = battle(["archer"], ["giant"], [start, Vector2(120, 120)], _pad_arena("gim_pad_%d" % int(save * 100), flight), 153804, false, 60.0)
	var u: BUnit = sim.heroes[0]
	script_move(u, goal)
	var jumps: int = 0
	var arrived: float = -1.0
	while sim.time < 20.0 and arrived < 0.0:
		sim.step()
		jumps += events_of(sim, "ENV_JUMP", u.idx)
		if u.pos.distance_to(goal) < 30.0:
			arrived = sim.time
	sim.dispose()
	return {"walk": snappedf(walk, 1.0), "flight": snappedf(flight, 0.01), "jumps": jumps, "arrived": snappedf(arrived, 0.01)}


func _jump_pad_choice() -> void:
	var big: Dictionary = _pad_trial(0.5)
	var small: Dictionary = _pad_trial(0.2)
	metrics["jump_pad"] = {"save_50": big, "save_20": small}
	check(int(big.jumps) == 1 and float(big.arrived) > 0.0, "a pad that saves 50%% of the walk is taken (%s)" % str(big))
	check(int(small.jumps) == 0 and float(small.arrived) > 0.0, "a pad that saves only 20%% is not taken; the hero walks (%s)" % str(small))


# A hero walking a corridor that passes beside a portal does not step into it.
func _portal_soft_wall() -> void:
	var walls: Array = [{"id": "n", "shape": "rect", "x": 300, "y": 300, "w": 800, "h": 40},
		{"id": "s", "shape": "rect", "x": 300, "y": 488, "w": 800, "h": 40}]
	var portals: Array = [{"id": "pa", "type": "portal", "shape": "circle", "x": 700, "y": 366, "radius": 26.0, "pairId": "pb", "cooldown": 2.5},
		{"id": "pb", "type": "portal", "shape": "circle", "x": 160, "y": 120, "radius": 26.0, "pairId": "pa", "cooldown": 2.5}]
	var trips: int = 0
	var arrived: int = 0
	for k in 3:
		var y0: float = 426.0 + float(k) * 8.0
		var sim: BattleSim = battle(["giant"], ["archer"], [Vector2(330, y0), Vector2(1300, 700)], fixture("gim_portal_%d" % k, walls, portals), 153805 + k, false, 60.0)
		var u: BUnit = sim.heroes[0]
		var goal: Vector2 = Vector2(1180, y0)
		script_move(u, goal)
		while sim.time < 12.0:
			sim.step()
			trips += events_of(sim, "ENV_PORTAL", u.idx)
			if u.pos.distance_to(goal) < 30.0:
				arrived += 1
				break
		sim.dispose()
	metrics["portal_corridor"] = {"trips": trips, "arrived": arrived}
	check(trips == 0, "a walk past a portal never steps into it (%d trips)" % trips)
	check(arrived == 3, "the corridor walk still arrives (%d/3)" % arrived)
	# Unit form: steering straight at a trigger from just outside loses its
	# inward part and slides around the rim toward the goal.
	var sim2: BattleSim = battle(["giant"], ["archer"], [Vector2(652, 366), Vector2(1300, 700)], fixture("gim_portal_unit", [], portals))
	var b2: TacticianBrain = brain(sim2)
	var g2: BUnit = sim2.heroes[0]
	var v: Vector2 = b2.call("_link_soft_walls", g2, Vector2(1, 0), sim2.radius(g2), Vector2(900, 380)) if b2.has_method("_link_soft_walls") else Vector2(1, 0)
	check(v.x <= 0.05 and absf(v.y) > 0.2, "steering into a portal it is not taking turns along the rim (%s)" % str(v))
	sim2.dispose()


# ----------------------------------------------------------------------- ring
func _ring_leave_early() -> void:
	var ring: Dictionary = {"id": "seal", "type": "closing_ring", "shape": "circle", "x": 704, "y": 396, "radius": 640.0,
		"startTime": 5.0, "endTime": 17.0, "startRadius": 640.0, "endRadius": 170.0, "damagePercent": 3.0, "tickInterval": 0.5}
	# The archer fights a passive giant parked outside the final circle.
	var sim: BattleSim = battle(["archer"], ["giant"], [Vector2(1010, 470), Vector2(1250, 470)], fixture("gim_ring", [], [ring]), 153806, false, 60.0)
	var a: BUnit = sim.heroes[0]
	var g: BUnit = sim.heroes[1]
	var ring_hits: int = 0
	while sim.time < 20.0 and sim.state == BattleSim.RUNNING:
		sim.step()
		g.hp = sim.max_hp(g)
		ring_hits += events_of(sim, "ENV_HIT", a.idx, "closing_ring")
	var c: Vector2 = Vector2(704, 396)
	metrics["ring"] = {"archer_ring_hits": ring_hits, "archer_dist": snappedf(a.pos.distance_to(c), 1.0)}
	check(ring_hits <= 1, "the hero leaves the zone before the ring covers it (%d ring hits)" % ring_hits)
	check(a.alive and a.pos.distance_to(c) <= 170.0, "the hero ends inside the final circle (%.0f)" % a.pos.distance_to(c))
	# Goals are kept inside the circle that is safe on arrival.
	var b: TacticianBrain = brain(sim)
	var q: Vector2 = safe_goal(b, a, Vector2(1300, 396), sim.radius(a), 120.0)
	check(q.distance_to(c) <= Arena.ring_radius_at(ring, sim.time + 2.0), "a goal outside the future safe circle is pulled inside (%s)" % str(q))
	sim.dispose()
	_ring_stone_notch()
	_ring_escape_skill()


# Review 1.5.3 (tactician_brain.gd:4180): '결계 밖 교전 자제' also charged
# the blink that would take the hero back inside, so it walked instead.
func _ring_escape_skill() -> void:
	var ring: Dictionary = {"id": "seal", "type": "closing_ring", "shape": "circle", "x": 704, "y": 396, "radius": 640.0,
		"startTime": 5.0, "endTime": 17.0, "startRadius": 640.0, "endRadius": 170.0, "damagePercent": 3.0, "tickInterval": 0.5}
	var c: Vector2 = Vector2(704, 396)
	var sim: BattleSim = battle(["mage"], ["giant"], [c + Vector2(240, 0), Vector2(1300, 120)], fixture("gim_ring_blink", [], [ring]), 153807, false, 60.0)
	_set_time(sim, 20.0)
	var b: TacticianBrain = brain(sim)
	var m: BUnit = sim.heroes[0]
	b.intel.observe()
	b._plan()
	var bi: int = -1
	for i in m.def.abilities.size():
		if m.def.abilities[i].action == "pointBlink":
			bi = i
	var ctx: Dictionary = b._ctx(m)
	var cands: Array = [
		{"value": 100.0, "key": "a%d:esc" % bi, "label": "inside", "parts": {}, "cmd": {"kind": "ability", "index": bi, "ability_id": m.def.abilities[bi].id, "pos": c + Vector2(80, 0)}},
		{"value": 100.0, "key": "a%d:esc" % bi, "label": "outward", "parts": {}, "cmd": {"kind": "ability", "index": bi, "ability_id": m.def.abilities[bi].id, "pos": c + Vector2(400, 0)}},
		{"value": 100.0, "key": "b:%d" % sim.heroes[1].idx, "label": "basic", "parts": {}, "cmd": {"kind": "basic", "target": sim.heroes[1].idx}}]
	b._gimmick_adjust(m, ctx, cands)
	var inside: float = float(cands[0].value)
	var outward: float = float(cands[1].value)
	var basic: float = float(cands[2].value)
	metrics["ring_escape_values"] = {"blink_inside": snappedf(inside, 0.1), "blink_outward": snappedf(outward, 0.1), "basic": snappedf(basic, 0.1)}
	check(bi >= 0 and is_equal_approx(inside, 100.0), "a blink that lands back inside the ring is not charged as fighting outside (%.1f)" % inside)
	check(outward < 100.0 and basic < 100.0, "invariant: staying or blinking further out still carries the ring note (%.1f / %.1f)" % [outward, basic])
	sim.dispose()


# Review 1.5.3 (tactician_brain.gd:4762): bastion_ring seed 164151 pinned the
# mage in the notch between two standing stones for 7 s while the ring closed
# and killed it. The hazard look-ahead scored side turns into a stone as
# hazard-free (the line probe stops at the first unwalkable point) and the
# escape push picked a sample inside a stone (no ring penalty nearer the
# centre). Fixture: the same stone circle and ring, the same wedge position.
func _notch_battle(wedge: Vector2, t0: float) -> BattleSim:
	var obs: Array = []
	for k in [1, 2, 3, 4, 6, 7, 8, 9, 11, 12, 13, 14, 16, 17, 18, 19]:
		var ang: float = deg_to_rad(9.0 + 18.0 * k)
		obs.append({"id": "stone_%02d" % k, "shape": "circle", "x": snappedf(576.0 + 250.0 * cos(ang), 0.1), "y": snappedf(440.0 + 250.0 * sin(ang), 0.1), "radius": 30})
	var sim: BattleSim = battle(["mage"], ["giant"], [wedge, Vector2(1080, 110)], fixture("gim_notch", obs, [NOTCH_RING], [], 1152.0, 880.0), 164151, false, 150.0)
	_set_time(sim, t0)
	return sim


const NOTCH_RING: = {"id": "seal", "type": "closing_ring", "shape": "circle", "x": 576, "y": 440, "radius": 700.0,
	"startTime": 35.0, "endTime": 85.0, "startRadius": 700.0, "endRadius": 200.0, "damagePercent": 3.0, "tickInterval": 0.5}


func _ring_stone_notch() -> void:
	var c: Vector2 = Vector2(576, 440)
	# Unit check at the wedge of the seed: no side turn into a stone.
	var wedge: Vector2 = Vector2(356.6, 599.4)
	var sim0: BattleSim = _notch_battle(wedge, 74.0)
	var b0: TacticianBrain = brain(sim0)
	var m0: BUnit = sim0.heroes[0]
	var r: float = sim0.radius(m0)
	b0.intel.observe()
	b0._plan()
	var spd: float = maxf(40.0, sim0.stat(m0, &"moveSpeed"))
	var first: float = clampf(spd * 0.3, 24.0, 130.0)
	var la: Vector2 = b0._hazard_lookahead(m0, (wedge - c).normalized().rotated(-0.3), r)
	var q0: Vector2 = m0.pos + la.normalized() * first
	check(la.length() > 0.01 and sim0.arena.is_walkable(q0, r) and not sim0.arena.segment_blocked(m0.pos, q0, r * 0.9, Arena.MASK_UNITS), "ring look-ahead never turns into a standing stone (%s)" % str(la))
	sim0.dispose()
	# End to end: wedged in the notch at t=74.5 (pinned 7.9 s before the fix).
	var sim: BattleSim = _notch_battle(Vector2(341, 598), 74.5)
	var m: BUnit = sim.heroes[0]
	var g: BUnit = sim.heroes[1]
	var ring: Dictionary = NOTCH_RING
	var moved_at: float = sim.time
	var last: Vector2 = m.pos
	var still_max: float = 0.0
	var hits: int = 0
	var inside_at: float = -1.0
	while sim.time < 82.0 and sim.state == BattleSim.RUNNING and m.alive:
		sim.step()
		g.hp = sim.max_hp(g)
		hits += events_of(sim, "ENV_HIT", m.idx, "closing_ring")
		if m.pos.distance_to(last) > 6.0:
			last = m.pos
			moved_at = sim.time
		still_max = maxf(still_max, sim.time - moved_at)
		if inside_at < 0.0 and m.pos.distance_to(c) + r * 0.3 < Arena.ring_radius_at(ring, sim.time):
			if m.pos.distance_to(c) < 250.0:
				inside_at = sim.time
	metrics["ring_notch"] = {"still_max_s": snappedf(still_max, 0.1), "ring_hits": hits, "inside_stones_at": snappedf(inside_at, 0.1), "alive": m.alive}
	check(still_max < 2.0, "a hero wedged between stones keeps moving while the ring closes (still %.1f s)" % still_max)
	check(m.alive and inside_at > 0.0 and inside_at < 80.0, "the wedged hero walks around into the stone circle by t=80 (%.1f)" % inside_at)
	sim.dispose()


# ---------------------------------------------------------------------- brush
func _brush_ambush_and_caution() -> void:
	var forests: Array = [{"x": 660, "y": 396, "radius": 64, "patch": 0}, {"x": 1000, "y": 200, "radius": 70, "patch": 1}]
	var sim: BattleSim = battle(["swordsman", "giant"], ["archer"], [Vector2(480, 396), Vector2(430, 470), Vector2(1020, 396)], fixture("gim_brush", [], [], forests))
	var b: TacticianBrain = brain(sim)
	var sw: BUnit = sim.heroes[0]
	sim.step()
	b.intel.observe()
	b._plan()
	var moves: Array = []
	b._move_candidates(sw, b._ctx(sw), moves)
	var ambush: Array = moves.filter(func(c: Dictionary): return str(c.label) == "수풀 매복")
	check(not ambush.is_empty() and (ambush[0].cmd.goal as Vector2).distance_to(Vector2(660, 396)) < 70.0, "a melee hero gets a brush ambush point toward the approaching enemy")
	# Caution: the enemy is last seen beside brush 1 and walks into it while
	# our heroes watch the ground around it (but not inside, beyond 110).
	var foe: BUnit = sim.heroes[2]
	sw.pos = Vector2(820, 330)
	sw.prev_pos = sw.pos
	sim.heroes[1].pos = Vector2(780, 420)
	sim.heroes[1].prev_pos = sim.heroes[1].pos
	foe.pos = Vector2(1000, 290)
	foe.prev_pos = foe.pos
	sim._update_visibility()
	b.intel.observe()
	b.intel.observe_fast()
	foe.pos = Vector2(1000, 200)
	foe.prev_pos = foe.pos
	for k in 45:
		sim._update_visibility()
		b.intel.observe()
		b.intel._propagate(0.1)
		sim.time += 0.1
	b._plan()
	var threats: Array = b.get("_brush_threats") if b.get("_brush_threats") != null else []
	var near: Array = threats.filter(func(z: Dictionary): return (z.c as Vector2).distance_to(Vector2(1000, 200)) < 90.0)
	metrics["brush_threats"] = threats.size()
	check(not near.is_empty(), "the hidden enemy's particles mark brush 1 as a possible ambush")
	var probe: Vector2 = Vector2(860, 260)
	var giant: BUnit = sim.heroes[1]
	var with_threat: float = b._danger_raw(giant, probe, 1.0)
	var saved: Array = threats.duplicate()
	threats.clear()
	var without: float = b._danger_raw(giant, probe, 1.0)
	if b.get("_brush_threats") != null:
		b.set("_brush_threats", saved)
	check(with_threat > without, "danger next to suspicious brush is higher (%.0f vs %.0f)" % [with_threat, without])
	var gm: Array = []
	b._move_candidates(giant, b._ctx(giant), gm)
	check(gm.any(func(c: Dictionary): return str(c.label) == "수풀 확인"), "a sturdy hero gets a point that checks the suspicious brush")
	sim.dispose()


# Engine follow-up (intel): the developer brush switch also turns concealment
# off in the belief model.
func _brush_switch() -> void:
	var forests: Array = [{"x": 900, "y": 396, "radius": 70, "patch": 0}]
	var sim: BattleSim = battle(["archer"], ["giant"], [Vector2(500, 396), Vector2(1250, 120)], fixture("gim_brush_sw", [], [], forests))
	var b: TacticianBrain = brain(sim)
	check(b.intel.brush_hides(Vector2(500, 396), Vector2(900, 396)), "brush on: a point in brush is hidden from afar")
	sim.env.set_type_enabled("brush", false)
	check(not sim.brush_on and not b.intel.brush_hides(Vector2(500, 396), Vector2(900, 396)), "brush switched off: the belief model no longer hides it")
	sim.dispose()


# ----------------------------------------------------------------- politician
func _politician_contemplation() -> void:
	var sim: BattleSim = battle(["politician", "giant"], ["archer"], [Vector2(500, 396), Vector2(536, 412), Vector2(1100, 396)], fixture("gim_pol"), 153807)
	var pol: BUnit = sim.heroes[0]
	var ally: BUnit = sim.heroes[1]
	ally.command = {"kind": "move", "goal": ally.pos, "purpose": "test", "key": "test"}
	ally.next_decision_at = 1.0e9
	var start: Vector2 = pol.pos
	var held: float = 0.0
	while sim.time < 4.0:
		sim.step()
		ally.next_decision_at = 1.0e9
		if sim.warfare.contemplating(pol):
			held += BattleSim.DT
	metrics["politician"] = {"contemplating_s": snappedf(held, 0.01), "drift": snappedf(pol.pos.distance_to(start), 0.1)}
	check(held >= 2.0, "the politician holds contemplation beside a close ally (%.2f s)" % held)
	sim.dispose()


# -------------------------------------------------------------------- control
func _control_gravity_hold() -> void:
	var sim: BattleSim = BattleSim.new({"ruleset": "control", "arena_id": "control_waterway", "blue": ["giant", "archer"], "red": ["swordsman"], "seed": 153808, "max_time": 120.0})
	var p: Dictionary = sim.domination.points[0]
	var data: Dictionary = sim.arena.data.duplicate(true)
	var hz: Array = (data.get("hazards", []) as Array).duplicate(true)
	var c: Vector2 = p.center
	hz.append({"id": "well", "type": "gravity", "shape": "circle", "x": c.x, "y": c.y, "radius": 120.0,
		"period": 6.0, "activeDuration": 2.0, "warningDuration": 1.0, "phase": 3.0, "damage": 5.0, "tickInterval": 0.5, "force": 110.0, "school": "magic"})
	data["hazards"] = hz
	sim.arena = Arena.from_data(data)
	var b: TacticianBrain = AIFactory.make("tactician", sim, 0)
	sim.controllers[0] = b
	sim.controllers[1] = null
	var holder: BUnit = sim.heroes[0]
	holder.pos = sim.arena.resolve_circle(c + Vector2(30, 0), sim.radius(holder))
	holder.prev_pos = holder.pos
	sim.heroes[2].pos = sim.arena.resolve_circle(c + Vector2(900, 0), 20.0)
	sim.start()
	var cc: ConquestCommander = b.control_plan
	var worst: float = 0.0
	var active: float = 0.0
	while sim.time < 9.0:
		cc.update([], true)
		cc.assignments[holder.idx] = cc._objective_order(holder, 0, "수비", "test", 100.0, 0.0, false, false)
		holder.command = {"kind": "move", "goal": holder.pos, "purpose": "test", "key": "test"}
		holder.next_decision_at = 1.0e9
		sim.step()
		if bool(Arena.hazard_clock(hz[hz.size() - 1], sim.time).active):
			active += BattleSim.DT
		worst = maxf(worst, holder.pos.distance_to(c))
	metrics["control_gravity_hold"] = {"max_dist": snappedf(worst, 0.1), "radius": float(p.radius), "active_s": snappedf(active, 0.01)}
	check(active > 1.0 and worst <= float(p.radius), "a holder stays in its circle through a weak gravity pulse (max %.0f / r %.0f)" % [worst, float(p.radius)])
	sim.dispose()


# Wave-I engine follow-up: the brain prices the switch-aware ArenaEnv costs.
func _env_costs_switch_aware() -> void:
	var lava: Dictionary = {"id": "pool", "type": "lava", "shape": "circle", "x": 700, "y": 396, "radius": 70, "damage": 34, "tickInterval": 0.5, "alwaysActive": true}
	var sim: BattleSim = battle(["archer"], ["giant"], [Vector2(500, 396), Vector2(1250, 120)], fixture("gim_env", [], [lava]))
	var b: TacticianBrain = brain(sim)
	var u: BUnit = sim.heroes[0]
	var r: float = sim.radius(u)
	var on: float = b._route_hazard_cost(u, Vector2(900, 396), r, 120.0)
	sim.env.set_type_enabled("lava", false)
	b._danger_cache.clear()
	var off: float = b._route_hazard_cost(u, Vector2(900, 396), r, 120.0)
	var d_off: float = b._danger_raw(u, Vector2(700, 396), 1.0)
	check(on > 0.0 and is_zero_approx(off) and d_off < 20.0, "a switched-off hazard type costs nothing (route %.0f -> %.0f)" % [on, off])
	sim.dispose()
