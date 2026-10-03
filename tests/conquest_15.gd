extends SceneTree

# V1.5 conquest AI and the wall-contact fix.

var passed: int = 0
var failed: Array = []
var metrics: Dictionary = {}


class Pusher extends TeamController:
	var dir: Vector2 = Vector2.RIGHT
	func steer(_u: BUnit) -> Vector2:
		return dir


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
	_wall_contact()
	_commander()
	_turrets()
	var status: String = "PASS" if failed.is_empty() else "FAIL"
	print("CONQUEST_15 ", JSON.stringify({"status": status, "passed": passed, "failed": failed, "metrics": metrics}))
	var f: FileAccess = FileAccess.open("res://reports/conquest_15.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"suite": "conquest_15", "status": status, "passed": passed, "failed": failed, "metrics": metrics}, "  "))
	quit(0 if failed.is_empty() else 1)


# A unit resting inside the collision padding of a wall must still be able to
# slide along it or step away (V1.4 zeroed its velocity every tick).
func _wall_contact() -> void:
	var arena_id: String = ""
	var wall: int = -1
	for a in DB.arenas_for("control"):
		var ar: Arena = a
		for i in ar.obs_count:
			if ar.obs_circle[i] == 0 and ar.obs_w[i] >= 80.0 and ar.obs_h[i] >= 20.0:
				arena_id = ar.id
				wall = i
				break
		if wall >= 0:
			break
	_check(wall >= 0, "found a rectangular wall on a conquest map")
	if wall < 0:
		return
	var results: Dictionary = {}
	for legacy in [false, true]:
		BattleSim.wall_unpin = not legacy
		for dir in [Vector2.LEFT, Vector2(0.0, -1.0), Vector2(1.0, -1.0).normalized()]:
			var sim: BattleSim = BattleSim.new({"ruleset": "control", "arena_id": arena_id, "blue": ["swordsman"], "red": ["archer"], "seed": 5, "max_time": 60.0})
			var ar2: Arena = sim.arena
			var u: BUnit = sim.heroes[0]
			var r: float = sim.radius(u)
			# Top-left corner of the wall, just inside the swept-test padding.
			u.pos = Vector2(ar2.obs_x[wall] - r - 0.1, ar2.obs_y[wall] + 4.0)
			u.pos = ar2.resolve_circle(u.pos, r)
			var pusher: Pusher = Pusher.new(sim, 0)
			pusher.dir = dir
			sim.controllers[0] = pusher
			sim.controllers[1] = null
			sim.heroes[1].pos = sim.arena.resolve_circle(u.pos + Vector2(900, 0), 20.0)
			sim.start()
			var start: Vector2 = u.pos
			for k in 30:
				sim.step()
			results["%s:%s" % [str(legacy), str(dir)]] = u.pos.distance_to(start)
			sim.dispose()
	BattleSim.wall_unpin = true
	var fixed_ok: bool = true
	for k in results:
		if str(k).begins_with("false") and float(results[k]) < 20.0:
			fixed_ok = false
	_check(fixed_ok, "units against a wall move away or slide (%s)" % JSON.stringify(results))
	var legacy_stuck: bool = false
	for k in results:
		if str(k).begins_with("true") and float(results[k]) < 1.0:
			legacy_stuck = true
	metrics["legacy_wall_freeze_reproduced"] = legacy_stuck
	metrics["wall_contact_moves"] = results


func _commander() -> void:
	var sim: BattleSim = BattleSim.new({"ruleset": "control", "arena_id": "control_crossroads", "blue": ["engineer", "mage", "giant"], "red": ["archer", "swordsman", "pirate"], "seed": 9, "max_time": 60.0})
	sim.controllers[0] = AIFactory.make("tactician", sim, 0)
	sim.controllers[1] = AIFactory.make("tactician14", sim, 1)
	sim.start()
	_check(sim.controllers[0].control_plan is ConquestCommander, "V1.5 tactician plans conquest with the commander")
	_check(not (sim.controllers[1].control_plan is ConquestCommander) and sim.controllers[1].control_plan is ControlStrategy, "V1.4 comparison AI keeps the old planner")
	for k in 600:
		sim.step()
	var assigned: int = 0
	var alive: int = 0
	for u in sim.heroes:
		if u.team == 0 and u.alive:
			alive += 1
			if not sim.controllers[0].control_plan.intent(u).is_empty():
				assigned += 1
	_check(alive > 0 and assigned == alive, "every living hero has an objective order")
	sim.dispose()


# Engineers must not spend turrets next to their own spawn with no enemy near.
func _turrets() -> void:
	var stats: Dictionary = {}
	for kind in ["tactician", "tactician14"]:
		var spawn_side: int = 0
		var total: int = 0
		for m in 2:
			var arena_id: String = ["control_crossroads", "control_citadel"][m]
			var sim: BattleSim = BattleSim.new({"ruleset": "control", "arena_id": arena_id, "blue": ["engineer", "mage", "giant", "archer", "hermes"],
				"red": ["engineer", "sniper", "swordsman", "metatron", "pirate"], "seed": 400 + m, "max_time": 120.0})
			sim.controllers[0] = AIFactory.make(kind, sim, 0)
			sim.controllers[1] = AIFactory.make(kind, sim, 1)
			sim.start()
			var spawn_c: Array = []
			for t in 2:
				var c: Vector2 = Vector2.ZERO
				for p in sim.arena.spawns[t]:
					c += p
				spawn_c.append(c / maxf(1.0, sim.arena.spawns[t].size()))
			while sim.state == BattleSim.RUNNING:
				sim.step()
				for ev in sim.tick_events:
					if str(ev.type) != "SUMMON_CREATED":
						continue
					var e: BUnit = sim.u_at(int(ev.g))
					var owner: BUnit = sim.u_at(int(ev.s))
					if e == null or owner == null or e.kind != "turret":
						continue
					total += 1
					var near_enemy: float = INF
					for o in sim.heroes:
						if o.alive and o.team != owner.team:
							near_enemy = minf(near_enemy, o.pos.distance_to(e.pos))
					if e.pos.distance_to(spawn_c[owner.team]) < 450.0 and near_enemy > 750.0:
						spawn_side += 1
			sim.dispose()
		stats[kind] = {"turrets": total, "idle_spawn_turrets": spawn_side}
	metrics["turrets"] = stats
	_check(int(stats.tactician.turrets) > 0, "V1.5 engineers still build turrets")
	_check(int(stats.tactician.idle_spawn_turrets) == 0, "V1.5 builds no idle turret at its own spawn")
