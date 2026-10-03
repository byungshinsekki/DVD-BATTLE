extends SceneTree

var passed: int = 0
var failed: Array[String] = []
var matches: Array = []

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failed.append(label)
		push_error("CONTROL AI: " + label)

func _run() -> void:
	DB.ensure_loaded()
	for arena in DB.arenas_for("control"):
		for kind in ["tactician", "classic"]:
			capture_behavior(str(arena.id), kind)
	for kind in ["tactician", "classic"]:
		healing_behavior(kind)
	fairness_and_assignments()
	var report: Dictionary = {"status": "PASS" if failed.is_empty() else "FAIL", "passed": passed, "failed": failed, "matches": matches}
	var file: FileAccess = FileAccess.open("res://reports/control_ai_13.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("CONTROL AI ", report.status, " passed=", passed, " failures=", failed.size())
	quit(0 if failed.is_empty() else 1)

func fresh(arena: String, blue: Array, red: Array) -> BattleSim:
	return BattleSim.new({"ruleset": "control", "arena_id": arena, "blue": blue, "red": red, "seed": 130013, "max_time": 90.0})

func capture_behavior(arena: String, kind: String) -> void:
	var sim: BattleSim = fresh(arena, ["giant", "archer", "politician"], ["giant"])
	sim.controllers[0] = AIFactory.make(kind, sim, 0)
	sim.start()
	var captures: int = 0
	var peak_owned: int = 0
	var assignments_seen: Dictionary = {}
	for tick in 1800:
		if sim.state != BattleSim.RUNNING:
			break
		sim.step()
		for event in sim.tick_events:
			if str(event.type) == "CONTROL_CAPTURED":
				captures += 1
		if tick % 30 == 0:
			var owned: int = 0
			for p in sim.domination.points:
				if int(p.owner) == 0:
					owned += 1
			peak_owned = maxi(peak_owned, owned)
			for u in sim.allies_of(0):
				var explanation: Dictionary = sim.controllers[0].explain(u)
				var order: Dictionary = explanation.get("control", {}).get("assignment", {})
				if not order.is_empty():
					assignments_seen[int(order.point)] = true
	check(peak_owned >= 2, kind + " captures at least two objectives on " + arena)
	check(float(sim.domination.scores[0]) > 10.0, kind + " keeps objectives long enough to score on " + arena)
	check(assignments_seen.size() == 3, kind + " uses all three objective assignments on " + arena)
	var positions: Array = []
	for u in sim.allies_of(0):
		positions.append({"id": u.id, "pos": [u.pos.x, u.pos.y], "command": str(u.command.get("purpose", ""))})
	matches.append({"arena": arena, "ai": kind, "peak_owned": peak_owned, "score": sim.domination.scores[0], "captures": captures, "positions": positions})
	print("CAPTURE ", arena, " ", kind, " owned=", peak_owned, " score=", sim.domination.scores[0])
	sim.dispose()

func healing_behavior(kind: String) -> void:
	var sim: BattleSim = fresh("control_crossroads", ["archer", "mage"], ["giant"])
	var wounded: BUnit = sim.heroes[0]
	var other: BUnit = sim.heroes[1]
	var pad: Dictionary = sim.domination.heal_zones[0]
	wounded.pos = pad.center + Vector2(-140.0, 0.0)
	wounded.prev_pos = wounded.pos
	wounded.hp = sim.max_hp(wounded) * 0.25
	other.pos = pad.center + Vector2(-190.0, 100.0)
	other.prev_pos = other.pos
	other.hp = sim.max_hp(other) * 0.6
	sim.controllers[0] = AIFactory.make(kind, sim, 0)
	sim.start()
	var before: float = wounded.hp
	var entered: bool = false
	var selected: bool = false
	for tick in 600:
		if sim.state != BattleSim.RUNNING:
			break
		sim.step()
		if wounded.pos.distance_to(pad.center) <= float(pad.radius):
			entered = true
		var control: Dictionary = sim.controllers[0].explain(wounded).get("control", {})
		if str(control.get("heal_target", "")) == str(pad.id):
			selected = true
		if float(pad.ready_at) > sim.time and wounded.hp > before + sim.max_hp(wounded) * 0.2:
			break
	check(selected, kind + " selects a ready safe healing pad for wounded ally")
	check(entered, kind + " physically enters selected healing pad")
	check(float(pad.ready_at) > sim.time, kind + " actually consumes healing cooldown")
	check(wounded.hp > before + sim.max_hp(wounded) * 0.2, kind + " actually gains health from pad")
	sim.dispose()

func fairness_and_assignments() -> void:
	var sim: BattleSim = fresh("control_crossroads", ["giant", "archer", "politician", "mage", "torturer"], ["sniper", "hermes"])
	sim.start()
	var planner: ControlStrategy = ControlStrategy.new(sim, 0)
	planner.update([], true)
	var before: String = JSON.stringify(planner.summary)
	for enemy in sim.heroes:
		if enemy.team == 1:
			enemy.pos = Vector2(1000.0, 300.0)
			enemy.hp = 1.0
			for index in enemy.cooldowns.size():
				enemy.cooldowns[index] = 900.0
	var second: ControlStrategy = ControlStrategy.new(sim, 0)
	second.update([], true)
	check(JSON.stringify(second.summary) == before, "hidden enemy position/health/cooldown changes cannot alter objective assignments")
	var destinations: Dictionary = {}
	for row in planner.assignments.values():
		destinations[int(row.point)] = int(destinations.get(int(row.point), 0)) + 1
	check(destinations.size() == 3, "5v5 planner distributes across all three objectives")
	var max_assignment: int = 0
	for count in destinations.values():
		max_assignment = maxi(max_assignment, int(count))
	check(max_assignment <= 3, "planner avoids sending all five heroes to one objective")
	sim.domination.points[0].owner = 1
	sim.domination.points[1].owner = 1
	sim.domination.scores[1] = 280.0
	planner.update([], true)
	check(float(planner.summary.urgency) > 0.6, "enemy approaching score victory raises retake urgency")
	check(float(planner.summary.enemy_score_eta) < float(planner.summary.score_eta), "planner estimates time-to-score victory")
	var wound: BUnit = sim.heroes[0]
	wound.hp = sim.max_hp(wound) * 0.25
	for pad in sim.domination.heal_zones:
		pad.ready_at = sim.time + 25.0
	planner.update([], true)
	check(str(planner.intent(wound).heal_target) == "", "planner does not travel to pads with long cooldowns")
	var pad: Dictionary = sim.domination.heal_zones[0]
	pad.ready_at = 0.0
	wound.pos = pad.center + Vector2(-110.0, 0.0)
	var visible: TeamIntel.EnemyBelief = TeamIntel.EnemyBelief.new()
	visible.idx = 99
	visible.visible = true
	visible.is_hero = true
	visible.pos = pad.center
	planner.update([visible], true)
	check(str(planner.intent(wound).heal_target) == "", "observed enemy at healing pad prevents unsafe contested visit")
	planner.dispose()
	second.dispose()
	sim.dispose()
