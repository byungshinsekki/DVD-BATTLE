extends SceneTree

# Exact historical compositions are fixed: changing deck dimensions would
# change the lineup even if the battle seed remained the same.
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
		push_error("BACKLOG_V2 " + label)


func battle(map_id: String, seed_value: int, blue: Array, red: Array) -> BattleSim:
	var sim: BattleSim = BattleSim.new({"arena_id": map_id, "seed": seed_value, "ruleset": "elimination", "blue": blue, "red": red, "max_time": 150.0})
	for team in 2:
		sim.controllers[team] = AIFactory.make("tactician", sim, team)
	sim.start()
	return sim


func _run() -> void:
	DB.ensure_loaded()
	_goal_and_dodge()
	_thorn_fixture()
	_ring_detour_and_skill_portal()
	_giant_ring_cache_growth()
	_ring_reentry_from_inertia()
	_bastion_fixture()
	_link_arming_and_freeze()
	_link_reprice_retains_commit()
	_link_reprice_other_positive()
	_rift_fixture()
	_c5_balance_runtime()
	var report_path: String = "res://zz_work/measure/backlog_v2/latest.json"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):
			report_path = arg.substr(9)
	DirAccess.make_dir_recursive_absolute(report_path.get_base_dir())
	var output: FileAccess = FileAccess.open(report_path, FileAccess.WRITE)
	if output == null:
		push_error("BACKLOG_V2 cannot write report: " + report_path)
		quit(1)
		return
	output.store_string(JSON.stringify({"suite": "backlog_v2", "status": "PASS" if failed.is_empty() else "FAIL", "passed": passed, "failed": failed, "metrics": metrics}, "\t"))
	output.close()
	print("BACKLOG_V2 ", "PASS" if failed.is_empty() else "FAIL", " passed=", passed, " failed=", failed.size())
	quit(0 if failed.is_empty() else 1)


func _goal_and_dodge() -> void:
	var sim: BattleSim = BattleSim.new({"arena_id": "classic", "seed": 2202, "blue": ["mage"], "red": ["giant"]})
	sim.arena = Arena.from_data({"id": "v2_goal_dodge", "width": 1000, "height": 700,
		"bounds": {"minX": 20, "maxX": 980, "minY": 20, "maxY": 680},
		"obstacles": [{"id": "pillar", "shape": "circle", "x": 500, "y": 350, "radius": 60, "blocksUnits": true}],
		"hazards": [{"id": "small_portal", "type": "portal", "shape": "circle", "x": 218, "y": 200, "radius": 2, "pairId": "other"},
			{"id": "other", "type": "portal", "shape": "circle", "x": 800, "y": 600, "radius": 2, "pairId": "small_portal"}]})
	var brain: TacticianBrain = AIFactory.make("tactician", sim, 0)
	sim.controllers[0] = brain
	sim.start()
	var u: BUnit = sim.heroes[0]
	u.pos = Vector2(200, 200)
	u.prev_pos = u.pos
	var radius: float = sim.radius(u)
	var goal: Vector2 = brain._v2_move_goal(u, Vector2(500, 350), radius, "엄폐")
	check(goal.is_finite() and sim.arena.is_walkable(goal, radius), "grid-solid move target snaps to physical free ground")
	sim.env.enabled = false
	var off_goal: Vector2 = brain._v2_move_goal(u, Vector2(500, 350), radius, "엄폐")
	check(off_goal.is_finite() and sim.arena.is_walkable(off_goal, radius), "solid goal correction works with environment disabled")
	sim.env.enabled = true
	check(brain._v2_link_entry(u, u.pos, Vector2(240, 200), radius), "swept dodge catches portal between safe endpoints")
	check(not brain._v2_link_entry(u, Vector2(240, 200), Vector2(240, 200), radius), "far dodge endpoint alone is outside trigger")
	var dodge: Vector2 = brain._v2_safe_dodge(u, Vector2.RIGHT)
	check(dodge == Vector2.ZERO or not brain._v2_link_entry(u, u.pos, u.pos + dodge.normalized() * 40.0, radius), "filtered dodge does not cross unwanted link")
	u.pos = Vector2(40, 40)
	var corner: Vector2 = brain._v2_move_goal(u, Vector2(22, 22), radius, "재집결")
	var margin: float = 2.0 * radius + 16.0
	check(corner.is_finite() and corner.x >= sim.arena.min_x + margin and corner.y >= sim.arena.min_y + margin, "retreat stays two body radii plus sixteen pixels from both edges")
	var protection: Vector2 = brain._v2_move_goal(u, Vector2(22, 22), radius, "보호선으로 후퇴")
	check(protection.is_finite() and protection.x >= sim.arena.min_x + margin and protection.y >= sim.arena.min_y + margin, "protector retreat candidate uses the same corner margin")
	check(not brain._v2_escape_safe(u, Vector2(500, 350), radius), "blink cannot choose solid destination")
	sim.dispose()


func _thorn_fixture() -> void:
	var sim: BattleSim = battle("thorn_circuit", 171389, ["hermes", "archer", "mage"], ["blood_mage", "fisherman", "engineer"])
	var mage: BUnit = sim.heroes[2]
	var history: Array[Vector2] = []
	var streak: int = 0
	var stuck_ticks: int = 0
	while sim.state == BattleSim.RUNNING:
		sim.step()
		if not mage.alive:
			break
		var cmd: Dictionary = mage.command
		var eligible: bool = mage.action == null and mage.motion == null and mage.chamber == "" and not sim.is_crowd_controlled(mage)
		var wants: bool = eligible and str(cmd.get("kind", "")) == "move" and (cmd.get("goal", mage.pos) as Vector2).distance_to(mage.pos) > 24.0
		streak = streak + 1 if wants else 0
		history.append(mage.pos)
		if history.size() > 31:
			history.pop_front()
		if streak >= 30 and history.size() == 31 and history[0].distance_to(mage.pos) < 2.0:
			stuck_ticks += 1
	metrics["thorn_171389"] = {"stuck_ticks": stuck_ticks, "duration": sim.time, "mage_alive": mage.alive}
	check(stuck_ticks == 0, "thorn 171389 mage never pins for thirty active move ticks (%d ticks)" % stuck_ticks)
	sim.dispose()
	var problems: Array[String] = MapConnectivity.check(DB.arena("thorn_circuit").data)
	check(problems.is_empty(), "thorn physical components connect to spawn: " + str(problems))


func _ring_detour_and_skill_portal() -> void:
	var sim: BattleSim = BattleSim.new({"arena_id": "classic", "seed": 2203, "blue": ["mage"], "red": ["giant"]})
	sim.arena = Arena.from_data({"id": "v2_ring_skill_portal", "width": 1408, "height": 792,
		"hazards": [{"id": "ring", "type": "closing_ring", "x": 700, "y": 400, "startRadius": 500, "endRadius": 100, "startTime": 0, "endTime": 40, "damagePercent": 5, "tickInterval": 1}]})
	var brain: TacticianBrain = AIFactory.make("tactician", sim, 0)
	sim.controllers[0] = brain
	sim.start()
	var ring: Dictionary = brain._ring_def()
	var center: Vector2 = ring.center
	var start: Vector2 = center + Vector2(180, 0)
	var route: PackedVector2Array = PackedVector2Array([center + Vector2(350, 0), center + Vector2(50, 0)])
	var timing: Dictionary = brain._v2_route_slacks(ring, start, route, 100.0, 0.0, 25.0)
	check(brain._ring_time_reaching(ring, 180.0) - 25.0 > 6.0, "radial starting-point deadline alone would delay departure")
	check(float(timing.minimum) <= 6.0 and int(timing.pick) == 1, "route deadline notices outward detour and chooses first safe suffix")
	check(is_equal_approx(float(timing.slacks[0]), 15.0 - (25.0 + 1.7)), "deadline uses radial distance; ETA uses cumulative route distance")
	var u: BUnit = sim.heroes[0]
	u.pos = Vector2(800, 400)
	u.prev_pos = u.pos
	u.vel = Vector2.RIGHT * 100.0
	sim.time = 25.0
	sim.portal_pairs.append({"id": 999, "source": u.idx, "team": 0, "a": Vector2(850, 400), "b": Vector2(1200, 400), "radius": 22.0, "end": 100.0})
	check(not sim.arena.has_links, "skill-portal fixture has no environmental links")
	var avoid: Vector2 = brain._v2_skill_portal_avoidance(u)
	check(avoid.x < 0.0, "friendly skill portal with unsafe ring exit repels on a no-link map")
	sim.portal_pairs[0].team = 1
	check(brain._v2_skill_portal_avoidance(u) == Vector2.ZERO, "hidden enemy portal metadata is not used")
	sim.dispose()


func _bastion_fixture() -> void:
	var sim: BattleSim = battle("bastion_ring", 172508, ["hermes", "sniper", "werewolf"], ["baseball", "mage", "metatron"])
	var mage: BUnit = sim.heroes[4]
	var brain: TacticianBrain = sim.controllers[1]
	var ring: Dictionary = brain._ring_def()
	var outside: float = 0.0
	while sim.state == BattleSim.RUNNING:
		sim.step()
		if not mage.alive:
			break
		if Arena.ring_outside(ring, mage.pos, sim.time, 0.0):
			outside += BattleSim.DT
	metrics["bastion_172508"] = {"mage_outside_seconds": outside, "duration": sim.time, "mage_alive": mage.alive}
	check(outside < 1.0, "bastion 172508 mage leaves outwork pocket before ring (<1 s, %.3f s)" % outside)
	sim.dispose()


# Giant recovery changes exact collision radius without changing its nav
# bucket. A cached final point fits at low HP but overlaps this short wall
# after healing, so the next ring decision must build a safe route again.
func _giant_ring_cache_growth() -> void:
	var sim: BattleSim = BattleSim.new({"arena_id": "classic", "seed": 2206, "blue": ["giant"], "red": ["mage"]})
	sim.arena = Arena.from_data({"id": "v2_giant_ring_cache", "width": 1408.0, "height": 792.0,
		"obstacles": [{"id": "endpoint_wall", "shape": "rect", "x": 800.0, "y": 423.8,
			"w": 120.0, "h": 20.0, "blocksUnits": true}],
		"hazards": [{"id": "ring", "type": "closing_ring", "x": 700.0, "y": 400.0,
			"startRadius": 600.0, "endRadius": 200.0, "startTime": 0.0, "endTime": 100.0,
			"damagePercent": 5.0, "tickInterval": 1.0}]})
	var brain: TacticianBrain = AIFactory.make("tactician", sim, 0)
	sim.controllers[0] = brain
	sim.start()
	var u: BUnit = sim.heroes[0]
	u.pos = Vector2(1100.0, 400.0)
	u.prev_pos = u.pos
	u.vel = Vector2.ZERO
	u.hp = sim.max_hp(u) * 0.05
	var small: float = sim.radius(u)
	var nav: Navigator = brain.navigator_for(small)
	# Seed the ordinary shared cell-path cache for the endpoint cell. The
	# ring planner may extend its own copy, but must not mutate this query.
	var ordinary_goal: Vector2 = Vector2(854.0, 400.0)
	var ordinary_before: PackedVector2Array = nav.path_points(u.pos, ordinary_goal, false).duplicate()
	sim.time = 50.0
	var points: Array = []
	var ctx: Dictionary = {"r": small, "ms": sim.stat(u, BattleSim.S_MS), "mx": sim.max_hp(u), "risk_w": 1.0}
	brain._ring_points(u, ctx, points)
	var cached: Dictionary = (brain.mem.get(u.idx, {}) as Dictionary).get("v2_ring_route", {})
	var old_path: PackedVector2Array = cached.get("path", PackedVector2Array())
	check(not old_path.is_empty(), "giant low-HP ring plan has a real path")
	if old_path.is_empty():
		sim.dispose()
		return
	check(nav.path_points(u.pos, ordinary_goal, false) == ordinary_before, "ring planner leaves shared navigator cell path unchanged")
	var old_goal: Vector2 = old_path[-1]
	check(sim.arena.is_walkable(old_goal, small), "cached endpoint initially fits giant body")
	u.hp = sim.max_hp(u) * 0.70
	var grown: float = sim.radius(u)
	check(grown > small and brain.navigator_for(grown) == nav, "giant heals and grows inside unchanged navigation bucket")
	check(not sim.arena.is_walkable(old_goal, grown), "old endpoint actually overlaps terrain after same-bucket growth")

	# Position, nav identity and cache age still permit ordinary cache reuse;
	# body growth is the only relevant invalidation change.
	sim.time = 50.1
	ctx.r = grown
	points.clear()
	brain._ring_points(u, ctx, points)
	var renewed: Dictionary = (brain.mem.get(u.idx, {}) as Dictionary).get("v2_ring_route", {})
	var new_path: PackedVector2Array = renewed.get("path", PackedVector2Array())
	check(not new_path.is_empty() and is_equal_approx(float(renewed.get("t", -1.0)), sim.time), "body growth recomputes a nonempty ring route before cache expiry")
	check(not new_path.is_empty() and sim.arena.is_walkable(new_path[-1], grown), "renewed endpoint is physically walkable for healed giant")

	# Damage shrinks the body: the route computed for the larger body remains
	# conservative and may be reused for the rest of its half-second life.
	u.hp = sim.max_hp(u) * 0.05
	sim.time = 50.2
	ctx.r = sim.radius(u)
	points.clear()
	brain._ring_points(u, ctx, points)
	var shrunk: Dictionary = (brain.mem.get(u.idx, {}) as Dictionary).get("v2_ring_route", {})
	check(is_equal_approx(float(shrunk.get("t", -1.0)), 50.1), "smaller body reuses the conservative route")
	sim.dispose()


func _ring_reentry_from_inertia() -> void:
	var center: Vector2 = Vector2(704, 396)
	var ring: Dictionary = {"id": "seal", "type": "closing_ring", "shape": "circle", "x": 704, "y": 396, "radius": 640.0,
		"startTime": 5.0, "endTime": 17.0, "startRadius": 640.0, "endRadius": 170.0, "damagePercent": 3.0, "tickInterval": 0.5}
	var sim: BattleSim = BattleSim.new({"arena_id": "classic", "seed": 153806, "blue": ["archer"], "red": ["giant"]})
	sim.arena = Arena.from_data({"id": "v2_ring_reentry", "width": 1408.0, "height": 792.0,
		"bounds": {"minX": 40.0, "maxX": 1368.0, "minY": 40.0, "maxY": 752.0}, "obstacles": [], "hazards": [ring]})
	var b: TacticianBrain = AIFactory.make("tactician", sim, 0)
	sim.controllers[0] = b
	sim.controllers[1] = null
	sim.start()
	sim.time = 20.0
	var a: BUnit = sim.heroes[0]
	a.pos = center + Vector2(123, 0)
	a.prev_pos = a.pos
	var radius: float = sim.radius(a)
	var ctx: Dictionary = {"r": radius, "ms": sim.stat(a, BattleSim.S_MS), "mx": sim.max_hp(a), "risk_w": 1.0}
	var pts: Array = []
	a.next_decision_at = sim.time + 0.2
	a.vel = Vector2.ZERO
	b._ring_points(a, ctx, pts)
	check(pts.is_empty(), "a stationary hero inside the final target has no false ring urgency")
	a.vel = Vector2(-120, 0)
	b._ring_points(a, ctx, pts)
	check(pts.is_empty(), "an inward moving hero inside the final target has no false ring urgency")
	a.vel = Vector2(120, 0)
	b._ring_points(a, ctx, pts)
	check(pts.size() == 1, "outward drift before the next decision offers an actual ring escape route")
	var goal: Vector2 = pts[0][0] if not pts.is_empty() else Vector2.INF
	check(goal.is_finite() and sim.arena.is_walkable(goal, radius), "drift response has a physically walkable endpoint")
	check(goal.is_finite() and goal.distance_to(center) < a.pos.distance_to(center) - 30.0, "drift response is materially inward, not an outward or nearby no-op endpoint")
	check(goal.is_finite() and a.pos.distance_to(goal) >= 30.0, "drift response requests more than a tiny grid correction")
	if goal.is_finite():
		a.command = {"kind": "move", "goal": goal, "purpose": "결계 안으로"}
		var steering: Vector2 = b.steer(a)
		check(steering.dot(a.pos - center) < 0.0, "the real steering path opposes outward momentum")
	# Crossing back beyond the final target must resume a final-circle
	# route instead of reusing the recent deeper braking destination.
	var coast_goal: Vector2 = goal
	sim.time += 0.1
	a.pos = center + Vector2(140, 0)
	a.prev_pos = a.pos
	a.next_decision_at = sim.time + 0.2
	pts.clear()
	b._ring_points(a, ctx, pts)
	var resumed: Dictionary = (b.mem.get(a.idx, {}) as Dictionary).get("v2_ring_route", {})
	var route: PackedVector2Array = resumed.get("path", PackedVector2Array())
	check(not route.is_empty() and route[-1].distance_to(center) > coast_goal.distance_to(center) + 30.0 and route[-1].distance_to(center) < 170.0,
		"regular final-circle route does not reuse the deeper inertia-braking endpoint")
	sim.dispose()


func _link_arming_and_freeze() -> void:
	var sim: BattleSim = battle("rift_harbor", 2204, ["torturer"], ["mage"])
	var brain: TacticianBrain = sim.controllers[0]
	var u: BUnit = sim.heroes[0]
	var radius: float = sim.radius(u)
	var nav: Navigator = brain.navigator_for(radius)
	check(not nav.links.is_empty(), "arming fixture has navigable links")
	if nav.links.is_empty():
		sim.dispose()
		return
	var link: Dictionary = nav.links[0]
	var trigger: float = float(link.entry_r) + (radius * 0.28 if str(link.kind) == "portal" else 0.0)
	u.pos = (link.entry as Vector2) - Vector2(trigger + 30.0, 0.0)
	u.prev_pos = u.pos
	sim.time = 0.0
	check(brain._v2_arm_link_choice(u, nav, 0, radius) == -1, "near-entry link choice starts unarmed")
	sim.time = 0.349
	check(brain._v2_arm_link_choice(u, nav, 0, radius) == -1, "arming does not activate before 0.35 seconds")
	sim.time = 0.35
	check(brain._v2_arm_link_choice(u, nav, 0, radius) == 0, "persistent link choice activates at 0.35 seconds")
	brain._v2_arm_link_choice(u, nav, -1, radius)
	check(brain._v2_arm_link_choice(u, nav, 0, radius) == -1, "a lost choice restarts arming delay")
	u.pos = (link.entry as Vector2) - Vector2(trigger + 5.0, 0.0)
	u.vel = Vector2.RIGHT * 120.0
	u.command = {"kind": "move", "goal": link.exit, "purpose": "test committed link", "key": "test_link"}
	brain._taking_link[u.idx] = str(link.hazard)
	check(brain._v2_link_frozen(u), "an armed approach inside stopping distance freezes decision")
	var saved: Dictionary = u.command.duplicate(true)
	var decisions: int = brain.decisions_made
	brain.decide(u)
	check(u.command == saved and brain.decisions_made == decisions, "freeze preserves chosen command without running a new decision")
	sim.env.enabled = false
	check(not brain._v2_link_frozen(u), "disabled environmental link cannot keep decision frozen")
	sim.env.enabled = true
	u.vel = Vector2.LEFT * 120.0
	check(not brain._v2_link_frozen(u), "moving away from the trigger releases freeze")
	u.vel = Vector2.RIGHT * 250.0
	var fast: float = brain._v2_stopping_distance(u)
	u.vel = Vector2.RIGHT * 100.0
	check(fast > brain._v2_stopping_distance(u) * 6.0, "lookahead grows with actual velocity squared at fixed hero stats")
	sim.dispose()


func _rift_fixture() -> void:
	var sim: BattleSim = battle("rift_harbor", 173100, ["archer", "baseball", "joker"], ["fisherman", "torturer", "dimensionalist"])
	var torturer: BUnit = sim.heroes[4]
	var brain: TacticianBrain = sim.controllers[1]
	var last_taking: Dictionary = {}
	var dropped: int = 0
	var trips: int = 0
	while sim.state == BattleSim.RUNNING and sim.time < 5.0:
		var taking_before: String = str(brain._taking_link.get(torturer.idx, ""))
		if not taking_before.is_empty():
			last_taking[taking_before] = sim.time
		sim.step()
		for event: Dictionary in sim.tick_events:
			if str(event.type) not in ["ENV_PORTAL", "ENV_JUMP"] or int(event.g) != torturer.idx:
				continue
			trips += 1
			var hazard: String = str(event.get("hazard", ""))
			var taking_now: String = str(brain._taking_link.get(torturer.idx, ""))
			if taking_now != hazard and sim.time - float(last_taking.get(hazard, -100.0)) <= 1.0:
				dropped += 1
	metrics["rift_173100"] = {"trips_first_five_seconds": trips, "dropped_links": dropped}
	check(dropped == 0, "rift 173100 torturer does not abandon a link before triggering (dropped=%d)" % dropped)
	sim.dispose()


# Exercises real steer -> route repricing. The first walk establishes an
# intentional portal from its actual cost; a nearby changed goal then makes
# the normal policy reject all links (distance < LINK_MIN_DIST). We observe
# the command's routing intent, not the new keep helper's arithmetic.
func _link_reprice_retains_commit() -> void:
	var sim: BattleSim = BattleSim.new({"arena_id": "classic", "seed": 2205, "blue": ["torturer"], "red": ["mage"]})
	sim.arena = Arena.from_data({"id": "v2_link_reprice_fixture", "width": 1600.0, "height": 800.0,
		"hazards": [
			{"id": "link_a", "type": "portal", "shape": "circle", "x": 400.0, "y": 400.0,
				"radius": 30.0, "pairId": "link_b", "exitFacing": {"x": -1.0, "y": 0.0}, "cooldown": 2.5},
			{"id": "link_b", "type": "portal", "shape": "circle", "x": 1200.0, "y": 400.0,
				"radius": 30.0, "pairId": "link_a", "exitFacing": {"x": 1.0, "y": 0.0}, "cooldown": 2.5}]})
	var brain: TacticianBrain = AIFactory.make("tactician", sim, 0)
	sim.controllers[0] = brain
	sim.start()
	var u: BUnit = sim.heroes[0]
	var radius: float = sim.radius(u)
	var trigger: float = 30.0 + radius * 0.28
	var entry: Vector2 = Vector2(400.0, 400.0)
	var long_goal: Vector2 = Vector2(1400.0, 400.0)
	sim.time = 1.0
	u.pos = entry - Vector2(trigger + 90.0, 0.0)
	u.prev_pos = u.pos
	u.vel = Vector2.RIGHT * 120.0
	u.command = {"kind": "move", "goal": long_goal, "purpose": "link reprice setup", "key": "link_reprice"}
	brain.steer(u)
	check(str(brain._taking_link.get(u.idx, "")) == "link_a", "real route establishes beneficial link before approach")

	# Expire the route cache, approach within three pixels of the trigger,
	# and request a short walk. That new goal is intentionally under 200px.
	sim.time = 2.0
	u.pos = entry - Vector2(trigger + 3.0, 0.0)
	u.prev_pos = u.pos
	u.vel = Vector2.RIGHT * 120.0
	var nearby_goal: Vector2 = u.pos + Vector2(0.0, 80.0)
	u.command = {"kind": "move", "goal": nearby_goal, "purpose": "short goal repricing", "key": "link_reprice_short"}
	var nav: Navigator = brain.navigator_for(radius)
	check(brain._link_choice(u, nav, nearby_goal, radius, {}) == -1, "short goal genuinely reprices the normal link choice to walking")
	brain.steer(u)
	check(str(brain._taking_link.get(u.idx, "")) == "link_a", "steer keeps committed link when braking cannot prevent entry despite negative reprice")

	# The same route must release its intent once motion points away. This
	# catches an unconditional keep-forever patch to the previous assertion.
	sim.time = 2.2
	u.vel = Vector2.LEFT * 120.0
	brain.steer(u)
	check(str(brain._taking_link.get(u.idx, "")).is_empty(), "route releases prior link when the body is already moving away")
	sim.dispose()


func _link_reprice_other_positive() -> void:
	var outcomes: Array = []
	for scenario: String in ["committed", "moving_away", "can_stop", "cooldown", "disabled"]:
		var sim: BattleSim = BattleSim.new({"arena_id": "classic", "seed": 2207, "blue": ["torturer"], "red": ["mage"]})
		sim.arena = Arena.from_data({"id": "v2_competing_links_" + scenario, "width": 1900.0, "height": 1200.0,
			"obstacles": [], "hazards": [
				{"id": "commit_a", "type": "portal", "shape": "circle", "x": 400.0, "y": 400.0,
					"radius": 30.0, "pairId": "commit_exit", "exitFacing": {"x": -1.0, "y": 0.0}, "cooldown": 2.5},
				{"id": "commit_exit", "type": "portal", "shape": "circle", "x": 1400.0, "y": 400.0,
					"radius": 30.0, "pairId": "commit_a", "exitFacing": {"x": 1.0, "y": 0.0}, "cooldown": 2.5},
				{"id": "alternative_b", "type": "jump_pad", "shape": "circle", "x": 400.0, "y": 640.0,
					"radius": 28.0, "target": {"x": 1500.0, "y": 950.0}, "flightTime": 0.3, "cooldown": 2.5}]})
		var brain: TacticianBrain = AIFactory.make("tactician", sim, 0)
		sim.controllers[0] = brain
		sim.controllers[1] = null
		sim.start()
		var u: BUnit = sim.heroes[0]
		var radius: float = sim.radius(u)
		var trigger: float = 30.0 + radius * 0.28
		var entry: Vector2 = Vector2(400.0, 400.0)
		sim.time = 1.0
		u.pos = entry - Vector2(trigger + 90.0, 0.0)
		u.prev_pos = u.pos
		u.vel = Vector2.RIGHT * 120.0
		u.command = {"kind": "move", "goal": Vector2(1600.0, 400.0), "purpose": "initial link A", "key": "first_A"}
		brain.steer(u)
		check(str(brain._taking_link.get(u.idx, "")) == "commit_a", scenario + ": real route first chooses portal A")

		# A goal change expires the real route cache. The pad wins normal
		# repricing by a large geometric margin, despite a positive A choice
		# already being established from the first, different destination.
		sim.time = 2.0
		u.pos = entry - Vector2(trigger + 3.0, 0.0)
		u.prev_pos = u.pos
		u.vel = Vector2.RIGHT * 120.0
		if scenario == "moving_away":
			u.vel = Vector2.LEFT * 120.0
		elif scenario == "can_stop":
			u.pos = entry - Vector2(trigger + 90.0, 0.0)
			u.prev_pos = u.pos
		elif scenario == "cooldown":
			u.portal_until = sim.time + 5.0
		elif scenario == "disabled":
			sim.env.set_type_enabled("portal", false)
		var other_goal: Vector2 = Vector2(1700.0, 950.0)
		u.command = {"kind": "move", "goal": other_goal, "purpose": "alternative link B", "key": "new_B"}
		check(brain._v2_link_frozen(u) == (scenario == "committed"), scenario + ": decision freeze and route retention share the active approach condition")
		var nav: Navigator = brain.navigator_for(radius)
		var raw: int = brain._link_choice(u, nav, other_goal, radius, brain._route_cache.get(u.idx, {}))
		var raw_id: String = str(nav.links[raw].hazard) if raw >= 0 and raw < nav.links.size() else ""
		check(raw >= 0 and raw_id == "alternative_b", scenario + ": normal pricing really selects another positive link B")
		brain.steer(u)
		var expected: String = "commit_a" if scenario == "committed" else "alternative_b"
		var actual: String = str(brain._taking_link.get(u.idx, ""))
		check(actual == expected, scenario + ": real steer keeps A only for its unstoppable active approach (got " + actual + ")")
		outcomes.append({"case": scenario, "raw_choice": raw_id, "expected": expected, "actual": actual})
		sim.dispose()
	metrics["competing_link_reprice"] = outcomes


# C5 runtime balance regressions.
# The unchanged helper body passed 207 checks in the isolated ad60 preflight;
# restoring only starting char_data/kits values produced 149 PASS / 58 FAIL.
# Evidence: zz_work/measure/C5/fixture_probe/{first_results,
# negative_baseline_results,validation_evidence}.json.
# That preflight does not replace this suite's post-C4 integration run.
# These ability/passive checks use AP, never perform basic attacks, and stay
# valid for either scoped metatron attackDamage candidate (60 or 52).
# S3 and flower base healing intentionally retain their ownership-limited
# runtime values; the assertions protect those unchanged effects as well.
#
# All balance assertions below observe HP, actual emitted combat events, or
# actual runtime status expiration after BattleSim.start_ability + sim.step.
# They never invoke apply_heal/apply_damage/apply_status to simulate the skill,
# and never substitute expected effect dictionaries or rewrite shared DB defs.
# Only the private fixture's positions, starting HP, and ordinary AP/tenacity
# buffs are set. Controllers remain null and the empty arena has no hazards.
# Two AP values distinguish base-only/AP-only/self+ally ratio mistakes.
#
# Execution paths (line numbers before C5; function names are authoritative):
# - world_tree S1/S4: BattleSim.start_ability -> _update_action ->
#   Kits.execute_ability -> _execute_nexus (plantTree/plantFlowers) ->
#   make_structure -> real entities -> BattleSim.step -> Kits.nexus_tick ->
#   BattleSim.apply_heal. Assertions cover actual HP, HEAL_APPLIED raw/amount,
#   pulse cadence, flower consumption, and unchanged allied healing.
# - metatron orbit: BattleSim.step -> Kits.update_contacts -> swept wing/body
#   contact + per-wing cycle dedupe -> apply_damage/apply_heal. S1 is itself
#   cast through the engine before checking its 1.25 multiplier on contact.
# - metatron S2: execute_ability/_deliver -> ProjectileSystem.spawn_from ->
#   freeze_effects -> swept body hit -> _return_leg (70%) -> apply_effects;
#   the first DoT then executes in BattleSim._update_statuses. The initial
#   enemy distance makes the first DoT tick precede the return-leg refresh;
#   this avoids asserting a new rule for the existing 70%-scaled return DoT.
# - metatron S4: Kits.execute_ability("glide") separates non-buff effects ->
#   schedule(1.2, land) -> ZoneSystem.update -> resolve_area -> apply_status;
#   subsequent normal sim.step calls prove 0.5 s airborne expiration and
#   restoration of cast/basic access even with substantial tenacity.
# - S3 unchanged: rescueFlight -> begin_motion/update_motion ->
#   _finish_motion -> apply_shield. Ownership excludes this hardcoded branch,
#   so 95 + 0.75 AP is deliberately the required current behavior.
#
# Mutation sensitivity / expected failures when C5 is absent or incomplete:
# - Removing either self-ratio line fails owner HP/raw amounts at both APs.
# - Applying the ratio to every target fails allied tree/flower amounts.
# - Scaling only base or only AP fails both AP fixtures and self/ally ratio.
# - Changing data/description without the world_tree Kits branch still fails.
# - Keeping old orbit/S2 numbers fails actual damage/heal events.
# - Updating S4 text only, dropping the scheduled status, or retaining 1.0 s
#   fails contact/status presence/duration/expiry, never a data-key check.
# - Scaling S3 despite the conservative ownership decision fails the guard.


func _c5_balance_runtime() -> void:
	for ap_boost: float in [0.0, 1.0]:
		_c5_world_tree_tree(ap_boost)
		_c5_world_tree_flowers(ap_boost, true)
		_c5_world_tree_flowers(ap_boost, false)
		_c5_metatron_orbit(ap_boost, false)
		_c5_metatron_orbit(ap_boost, true)
		_c5_metatron_boomerang(ap_boost)
		_c5_metatron_rescue_unchanged(ap_boost)
	_c5_metatron_landing(0.0)
	_c5_metatron_landing(0.5)


func _c5_fixture(blue: Array, red: Array, positions: Array) -> BattleSim:
	var sim: BattleSim = BattleSim.new({"arena_id": "classic", "ruleset": "elimination", "seed": 225005,
		"blue": blue, "red": red, "max_time": 30.0})
	sim.arena = Arena.from_data({"id": "c5_balance_runtime", "width": 1408, "height": 792,
		"bounds": {"minX": 40, "maxX": 1368, "minY": 40, "maxY": 752}, "obstacles": [], "hazards": []})
	for i in sim.heroes.size():
		_c5_position(sim.heroes[i], positions[i])
		sim.heroes[i].spawn_pos = sim.heroes[i].pos
		sim.heroes[i].facing = Vector2.RIGHT if sim.heroes[i].team == 0 else Vector2.LEFT
	sim.start()
	sim.env.enabled = false
	return sim


func _c5_position(u: BUnit, position: Vector2) -> void:
	u.pos = position
	u.prev_pos = position
	u.vel = Vector2.ZERO
	u.command = {}


func _c5_ap(sim: BattleSim, source: BUnit, boost: float) -> float:
	if boost > 0.0:
		sim.add_buff(source, &"abilityPower", boost, 20.0, source.idx, {"tag": "c5_ap_fixture"})
	return sim.stat(source, &"abilityPower")


func _c5_ticks(sim: BattleSim, count: int) -> Array:
	var events: Array = []
	for _tick in count:
		if not sim.step():
			check(false, "C5 fixture finished before its bounded observation window")
			break
		events.append_array(sim.tick_events)
	return events


func _c5_events(events: Array, event_type: String, source: int, target: int, slot: int = -1, source_type: String = "") -> Array:
	var out: Array = []
	for event: Dictionary in events:
		if str(event.get("type", "")) != event_type or int(event.get("s", -1)) != source:
			continue
		if target >= 0 and int(event.get("g", -1)) != target:
			continue
		if slot >= 0:
			var ability: Defs.AbilityDef = event.get("ability") as Defs.AbilityDef
			if ability == null or ability.slot != slot:
				continue
		if source_type != "" and str(event.get("source_type", "")) != source_type:
			continue
		out.append(event)
	return out


func _c5_amounts(events: Array) -> Array:
	var amounts: Array = []
	for event: Dictionary in events:
		amounts.append(float(event.get("amount", 0.0)))
	return amounts


func _c5_heal_amounts(events: Array, expected: float, label: String) -> void:
	check(not events.is_empty(), label + " emitted a real heal event")
	for event: Dictionary in events:
		check(absf(float(event.get("raw", -1.0)) - expected) < 0.0001, label + " raw heal matches independent balance formula")
		check(absf(float(event.get("amount", -1.0)) - expected) < 0.0001, label + " effective heal matches with sufficient missing HP")


func _c5_magic_expected(sim: BattleSim, target: BUnit, raw: float) -> float:
	# Fixtures use ordinary archer MR, with no shields, vulnerability or items.
	# Expected balance numbers are literals in tests, not copied from effects.
	var resistance: float = sim.stat(target, &"magicResistance")
	check(resistance >= 0.0, "C5 magic-damage fixture has non-negative resistance")
	return raw * 100.0 / (100.0 + resistance)


func _c5_world_tree_tree(ap_boost: float) -> void:
	var sim: BattleSim = _c5_fixture(["world_tree", "archer"], ["archer"],
		[Vector2(420, 400), Vector2(580, 400), Vector2(500, 480)])
	var owner: BUnit = sim.heroes[0]
	var ally: BUnit = sim.heroes[1]
	var enemy: BUnit = sim.heroes[2]
	var ap: float = _c5_ap(sim, owner, ap_boost)
	for u: BUnit in sim.heroes:
		u.hp = sim.max_hp(u) * 0.4
	var owner_before: float = owner.hp
	var ally_before: float = ally.hp
	var enemy_before: float = enemy.hp
	var label: String = "C5 world_tree tree AP=%.1f" % ap
	var started: bool = sim.start_ability(owner, 0, null, Vector2(500, 400))
	check(started, label + " S1 cast starts")
	if not started:
		sim.dispose()
		return
	# Cast finishes around 0.3 s, first pulse at 0.8 s, next at 1.8 s.
	var first_window: Array = _c5_ticks(sim, 36)
	check(sim.kits.owned_entities(owner, "tree").size() == 1, label + " S1 creates one living tree")
	var self_heals: Array = _c5_events(first_window, "HEAL_APPLIED", owner.idx, owner.idx, 1)
	var ally_heals: Array = _c5_events(first_window, "HEAL_APPLIED", owner.idx, ally.idx, 1)
	var full: float = 14.0 + 0.12 * ap
	check(self_heals.size() == 1 and ally_heals.size() == 1, label + " first pulse heals owner and ally once")
	_c5_heal_amounts(self_heals, full * 0.45, label + " self")
	_c5_heal_amounts(ally_heals, full, label + " ally")
	check(absf(owner.hp - owner_before - full * 0.45) < 0.0001, label + " actual owner HP receives 45%")
	check(absf(ally.hp - ally_before - full) < 0.0001, label + " actual ally HP keeps 100%")
	check(absf(enemy.hp - enemy_before) < 0.0001, label + " enemy inside aura is not healed")
	check(sim.gardens.is_empty(), label + " no incidental garden contributes healing")
	var second_window: Array = _c5_ticks(sim, 30)
	var self_again: Array = _c5_events(second_window, "HEAL_APPLIED", owner.idx, owner.idx, 1)
	var ally_again: Array = _c5_events(second_window, "HEAL_APPLIED", owner.idx, ally.idx, 1)
	check(self_again.size() == 1 and ally_again.size() == 1, label + " later pulse preserves cadence")
	_c5_heal_amounts(self_again, full * 0.45, label + " later self")
	_c5_heal_amounts(ally_again, full, label + " later ally")
	if self_heals.size() == 1 and self_again.size() == 1:
		check(absf(float(self_again[0].t) - float(self_heals[0].t) - 1.0) <= BattleSim.DT + 0.0001, label + " one-second pulse interval")
	metrics["c5_tree_ap_%d" % int(ap)] = {"ap": ap, "self": _c5_amounts(self_heals), "ally": _c5_amounts(ally_heals), "self_second": _c5_amounts(self_again)}
	sim.dispose()


func _c5_world_tree_flowers(ap_boost: float, self_pickup: bool) -> void:
	var sim: BattleSim = _c5_fixture(["world_tree", "archer"], ["archer"],
		[Vector2(420, 400), Vector2(600, 400), Vector2(1100, 650)])
	var owner: BUnit = sim.heroes[0]
	var ally: BUnit = sim.heroes[1]
	var recipient: BUnit = owner if self_pickup else ally
	var other: BUnit = ally if self_pickup else owner
	var ap: float = _c5_ap(sim, owner, ap_boost)
	owner.hp = sim.max_hp(owner) * 0.3
	ally.hp = sim.max_hp(ally) * 0.3
	var before: float = recipient.hp
	var other_before: float = other.hp
	var expected: float = (45.0 + 0.35 * ap) * (0.45 if self_pickup else 1.0)
	var label: String = "C5 world_tree flower AP=%.1f %s" % [ap, "self" if self_pickup else "ally"]
	var started: bool = sim.start_ability(owner, 3, null, recipient.pos)
	check(started, label + " S4 cast starts")
	if not started:
		sim.dispose()
		return
	var events: Array = _c5_ticks(sim, 24)
	var created: Array = _c5_events(events, "SUMMON_CREATED", owner.idx, -1, 4)
	check(created.size() == 3, label + " real cast creates three flowers")
	var heals: Array = _c5_events(events, "HEAL_APPLIED", owner.idx, recipient.idx, 4)
	check(heals.size() == 3, label + " all three nearby flowers are picked up once")
	_c5_heal_amounts(heals, expected, label)
	check(absf(recipient.hp - before - expected * 3.0) < 0.0001, label + " actual HP equals three correctly scaled pickups")
	check(absf(other.hp - other_before) < 0.0001, label + " distant nonrecipient HP is unchanged")
	check(sim.kits.owned_entities(owner, "flower").is_empty(), label + " consumed flowers are no longer active")
	var later: Array = _c5_ticks(sim, 18)
	check(_c5_events(later, "HEAL_APPLIED", owner.idx, -1, 4).is_empty(), label + " consumed flowers cannot heal again")
	check(absf(recipient.hp - before - expected * 3.0) < 0.0001, label + " no repeated HP gain after consumption")
	metrics["c5_flower_ap_%d_%s" % [int(ap), "self" if self_pickup else "ally"]] = {"ap": ap, "per_flower": _c5_amounts(heals), "hp_delta": recipient.hp - before}
	sim.dispose()


func _c5_metatron_orbit(ap_boost: float, empowered: bool) -> void:
	var sim: BattleSim = _c5_fixture(["metatron", "archer"], ["archer"],
		[Vector2(600, 400), Vector2(300, 400), Vector2(1000, 400)])
	var source: BUnit = sim.heroes[0]
	var ally: BUnit = sim.heroes[1]
	var enemy: BUnit = sim.heroes[2]
	var ap: float = _c5_ap(sim, source, ap_boost)
	var label: String = "C5 metatron orbit AP=%.1f empowered=%s" % [ap, str(empowered)]
	if empowered:
		var started: bool = sim.start_ability(source, 0, source, source.pos)
		check(started, label + " S1 cast starts")
		if not started:
			sim.dispose()
			return
		_c5_ticks(sim, 12)
	# Put targets at the actual current tips, without resetting kit cycle state.
	var angle: float = float(source.ks.wing_angle)
	var tip: Vector2 = Vector2(cos(angle), sin(angle)) * 72.0
	_c5_position(enemy, source.pos + tip)
	_c5_position(ally, source.pos - tip)
	source.hp = sim.max_hp(source) * 0.5
	ally.hp = sim.max_hp(ally) * 0.4
	var self_before: float = source.hp
	var ally_before: float = ally.hp
	var enemy_before: float = enemy.hp
	var mult: float = 1.25 if empowered else 1.0
	var damage: float = _c5_magic_expected(sim, enemy, (10.0 + 0.11 * ap) * mult)
	var healing: float = (8.0 + 0.08 * ap) * mult
	var events: Array = _c5_ticks(sim, 1)
	var hits: Array = _c5_events(events, "HEALTH_DAMAGED", source.idx, enemy.idx, -1, "PASSIVE")
	var heals: Array = _c5_events(events, "HEAL_APPLIED", source.idx, ally.idx, -1, "PASSIVE")
	check(hits.size() == 1 and heals.size() == 1, label + " opposing wing contacts damage/heal once")
	if hits.size() == 1:
		check(absf(float(hits[0].amount) - damage) < 0.0001, label + " contact damage is 10+0.11AP before MR")
	_c5_heal_amounts(heals, healing, label + " ally contact")
	check(absf(enemy_before - enemy.hp - damage) < 0.0001, label + " actual enemy HP matches contact event")
	check(absf(ally.hp - ally_before - healing) < 0.0001, label + " actual ally HP matches contact event")
	check(absf(source.hp - self_before) < 0.0001, label + " own wing does not self-heal")
	var repeated: Array = _c5_ticks(sim, 2)
	check(_c5_events(repeated, "HEALTH_DAMAGED", source.idx, enemy.idx, -1, "PASSIVE").is_empty(), label + " same sweep cannot repeatedly damage")
	check(_c5_events(repeated, "HEAL_APPLIED", source.idx, ally.idx, -1, "PASSIVE").is_empty(), label + " same sweep cannot repeatedly heal")
	metrics["c5_orbit_ap_%d_%s" % [int(ap), str(empowered)]] = {"ap": ap, "damage": _c5_amounts(hits), "heal": _c5_amounts(heals)}
	sim.dispose()


func _c5_metatron_boomerang(ap_boost: float) -> void:
	var sim: BattleSim = _c5_fixture(["metatron"], ["archer"], [Vector2(500, 400), Vector2(640, 400)])
	var source: BUnit = sim.heroes[0]
	var enemy: BUnit = sim.heroes[1]
	var ap: float = _c5_ap(sim, source, ap_boost)
	var label: String = "C5 metatron S2 AP=%.1f" % ap
	var before: float = enemy.hp
	var started: bool = sim.start_ability(source, 1, enemy, enemy.pos)
	check(started, label + " starts an actual projectile cast")
	if not started:
		sim.dispose()
		return
	var events: Array = _c5_ticks(sim, 60)
	var direct: Array = _c5_events(events, "HEALTH_DAMAGED", source.idx, enemy.idx, 2, "ABILITY")
	var ticks: Array = _c5_events(events, "HEALTH_DAMAGED", source.idx, enemy.idx, 2, "PERSISTENT")
	var outward: float = _c5_magic_expected(sim, enemy, 41.0 + 0.45 * ap)
	var dot: float = _c5_magic_expected(sim, enemy, 5.0 + 0.07 * ap)
	check(direct.size() == 2, label + " actual outward and return legs hit once each")
	if direct.size() == 2:
		check(absf(float(direct[0].amount) - outward) < 0.0001, label + " outward damage is 41+0.45AP before MR")
		check(absf(float(direct[1].amount) - outward * 0.7) < 0.0001, label + " return damage remains 70%")
	check(not ticks.is_empty(), label + " applied DoT produces a real delayed damage event")
	if not ticks.is_empty():
		check(absf(float(ticks[0].amount) - dot) < 0.0001, label + " first DoT is 5+0.07AP before MR")
		if direct.size() == 2:
			check(float(ticks[0].t) < float(direct[1].t), label + " initial DoT precedes return-leg refresh")
	var accounted: float = 0.0
	for event: Dictionary in direct + ticks:
		accounted += float(event.amount)
	check(absf(before - enemy.hp - accounted) < 0.0001, label + " actual HP loss equals only observed S2 damage")
	metrics["c5_s2_ap_%d" % int(ap)] = {"ap": ap, "direct": _c5_amounts(direct), "dot": _c5_amounts(ticks), "hp_loss": before - enemy.hp}
	sim.dispose()


func _c5_metatron_landing(tenacity_flat: float) -> void:
	var sim: BattleSim = _c5_fixture(["metatron", "archer"], ["archer", "archer"],
		[Vector2(500, 400), Vector2(500, 290), Vector2(610, 400), Vector2(730, 400)])
	var source: BUnit = sim.heroes[0]
	var ally: BUnit = sim.heroes[1]
	var enemy: BUnit = sim.heroes[2]
	var outside: BUnit = sim.heroes[3]
	if tenacity_flat > 0.0:
		sim.add_buff(enemy, &"tenacityFlat", tenacity_flat, 20.0, enemy.idx, {"tag": "c5_tenacity_fixture"})
	var tenacity: float = sim.stat(enemy, &"tenacity")
	var label: String = "C5 metatron S4 tenacity=%.2f" % tenacity
	if tenacity_flat > 0.0:
		check(tenacity > 0.5, label + " fixture really has substantial tenacity")
	var started: bool = sim.start_ability(source, 3, source, source.pos)
	check(started, label + " glide cast starts")
	if not started:
		sim.dispose()
		return
	var events: Array = []
	var landed: Array = []
	# At most 3 seconds; stop on the first actual landing CC to inspect its
	# live status and then advance the real fixed-step clock through expiry.
	for _tick in 90:
		events.append_array(_c5_ticks(sim, 1))
		landed = _c5_events(sim.tick_events, "CC_APPLIED", source.idx, enemy.idx, 4)
		if not landed.is_empty():
			break
	check(landed.size() == 1, label + " scheduled landing actually applies CC once")
	var airborne: ST.Status = sim.owned_status(enemy, &"airborne", source.idx)
	check(airborne != null, label + " target has an actual airborne status")
	var completed: Array = _c5_events(events, "CAST_COMPLETED", source.idx, -1, 4)
	check(completed.size() == 1, label + " the actual glide cast completes once")
	if landed.size() == 1 and completed.size() == 1:
		check(absf(float(landed[0].t) - float(completed[0].t) - 1.2) <= BattleSim.DT + 0.0001, label + " CC comes from delayed 1.2-second landing")
	var damage: Array = _c5_events(events, "HEALTH_DAMAGED", source.idx, enemy.idx, 4, "DELAYED")
	check(damage.size() == 1, label + " landing also executes its area damage")
	if damage.size() == 1:
		var expected: float = _c5_magic_expected(sim, enemy, 50.0 + 0.45 * sim.stat(source, &"abilityPower"))
		check(absf(float(damage[0].amount) - expected) < 0.0001, label + " landing damage remains unchanged")
	check(not sim.has_status(ally, &"airborne") and not sim.has_status(outside, &"airborne"), label + " landing excludes allies and distant enemies")
	if airborne != null:
		var began: float = airborne.start
		var duration: float = airborne.end - began
		check(absf(duration - 0.5) < 0.0001, label + " runtime airborne lifetime is exactly 0.5 seconds")
		check(not sim.can_cast(enemy) and not sim.can_basic(enemy), label + " airborne blocks casts and basic attacks")
		_c5_ticks(sim, 13)
		check(sim.has_status(enemy, &"airborne"), label + " CC remains active before 0.5 seconds")
		_c5_ticks(sim, 3)
		check(not sim.has_status(enemy, &"airborne"), label + " CC expires by the first fixed step after 0.5 seconds")
		check(sim.can_cast(enemy) and sim.can_basic(enemy), label + " controls resume after CC expiration")
		metrics["c5_s4_tenacity_%d" % int(tenacity_flat * 100.0)] = {"tenacity": tenacity, "status_seconds": duration, "observed_expired_after": sim.time - began}
	sim.dispose()


func _c5_metatron_rescue_unchanged(ap_boost: float) -> void:
	var sim: BattleSim = _c5_fixture(["metatron", "archer"], ["archer"],
		[Vector2(500, 400), Vector2(700, 400), Vector2(1100, 650)])
	var source: BUnit = sim.heroes[0]
	var ally: BUnit = sim.heroes[1]
	var ap: float = _c5_ap(sim, source, ap_boost)
	ally.hp = sim.max_hp(ally) * 0.3
	var label: String = "C5 metatron S3 unchanged AP=%.1f" % ap
	var started: bool = sim.start_ability(source, 2, ally, ally.pos)
	check(started, label + " actual rescue flight starts")
	if not started:
		sim.dispose()
		return
	var events: Array = _c5_ticks(sim, 45)
	var shields: Array = _c5_events(events, "SHIELD_APPLIED", source.idx, ally.idx, 3)
	var expected: float = 95.0 + 0.75 * ap
	check(shields.size() == 1, label + " completing the actual flight gives one shield")
	if shields.size() == 1:
		check(absf(float(shields[0].amount) - expected) < 0.0001, label + " hardcoded runtime remains 95+0.75AP")
	check(ally.shields.size() == 1 and absf(ally.shields[0].amount - expected) < 0.0001, label + " live shield stores the unchanged amount")
	if ally.shields.size() == 1 and shields.size() == 1:
		check(absf(ally.shields[0].end - float(shields[0].t) - 4.0) < 0.0001, label + " live shield retains four-second lifetime")
	metrics["c5_s3_unchanged_ap_%d" % int(ap)] = {"ap": ap, "shield": _c5_amounts(shields)}
	sim.dispose()
