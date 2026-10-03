extends SceneTree

var passed: int = 0
var failed: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed.append(label)
		push_error("CONTROL INFORMATION: " + label)

func fresh(enemy: String = "fisherman") -> BattleSim:
	var sim: BattleSim = BattleSim.new({"arena_id": "control_crossroads", "seed": 13131, "blue": ["swordsman", "mage"], "red": [enemy]})
	sim.start()
	return sim

func packet(kind: String, target: int, at: float) -> Dictionary:
	return {"type": kind, "s": target, "g": target, "t": at, "sv": [false, true], "gv": [false, true], "team": 1}

func _run() -> void:
	DB.ensure_loaded()
	objective_noninterference()
	respawn_information()
	objective_visibility()
	var report: Dictionary = {"status": "PASS" if failed.is_empty() else "FAIL", "passed": passed, "failed": failed}
	var file: FileAccess = FileAccess.open("res://reports/control_information_13.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("CONTROL_INFORMATION_13 ", JSON.stringify(report))
	quit(0 if failed.is_empty() else 1)

func objective_noninterference() -> void:
	var sim: BattleSim = fresh()
	var intel: TeamIntel = TeamIntel.new(sim, 0)
	var strategy: ControlStrategy = ControlStrategy.new(sim, 0)
	intel.observe()
	var enemy: BUnit = sim.heroes[2]
	var b: TeamIntel.EnemyBelief = intel.enemies[enemy.idx]
	check(not b.visible, "enemy starts beyond allied vision")
	strategy.update(intel.visible_enemies(), true)
	var first: String = JSON.stringify(strategy.summary)
	enemy.pos = sim.domination.points[0].center
	enemy.hp = 1.0
	enemy.cooldowns[0] = 999.0
	enemy.resources["fish"] = 2.0
	sim.push_status(enemy, &"invulnerable", enemy.idx, 30.0)
	strategy.update(intel.visible_enemies(), true)
	check(JSON.stringify(strategy.summary) == first, "hidden true position HP CD and status do not change objective plan")
	# Feed a perceived location deliberately different from authoritative truth.
	b.visible = true
	b.pos = sim.domination.points[2].center
	strategy.update([b], true)
	check(int(strategy.summary.points[0].enemy_observed) == 0 and int(strategy.summary.points[2].enemy_observed) == 1,
		"objective danger uses perceived location rather than true location")
	var reported: String = JSON.stringify(strategy.summary)
	enemy.pos = sim.domination.points[1].center
	strategy.update([b], true)
	check(JSON.stringify(strategy.summary) == reported, "true movement cannot override a supplied visible report")
	b.visible = false
	strategy.update([b], true)
	check(int(strategy.summary.points[2].enemy_observed) == 0, "stale unseen beliefs do not become exact occupancy counts")
	var urgency: float = strategy.summary.urgency
	for point in sim.domination.points: point.owner = 1
	sim.domination.scores[1] = 299.0
	strategy.update([], true)
	check(float(strategy.summary.urgency) > urgency, "public losing score changes strategic urgency")
	check(strategy.assignments.size() == 2, "both living allies receive objective assignments")
	for assignment in strategy.assignments.values():
		check((assignment.goal as Vector2).distance_to(assignment.center) < float(assignment.radius), "objective destination actually lies inside capture circle")
	# Public heal cooldown is shared; selecting a pad cannot use hidden enemies.
	var ally: BUnit = sim.heroes[0]
	ally.hp = sim.max_hp(ally) * 0.2
	sim.domination.heal_zones.clear()
	sim.domination.heal_zones.append({"id": "LOCAL", "center": ally.pos + Vector2(55, 0), "radius": 45.0, "ready_at": sim.time})
	strategy.update([], true)
	check(str(strategy.intent(ally).heal_target) == "LOCAL", "available nearby public pad attracts wounded ally")
	sim.domination.heal_zones[0].ready_at = sim.time + 25.0
	strategy.update([], true)
	check(str(strategy.intent(ally).heal_target).is_empty(), "unavailable public pad does not receive healing assignment")
	strategy.dispose()
	intel.dispose()
	sim.dispose()

func respawn_information() -> void:
	var a: BattleSim = fresh()
	var b_sim: BattleSim = fresh()
	var ia: TeamIntel = TeamIntel.new(a, 0)
	var ib: TeamIntel = TeamIntel.new(b_sim, 0)
	var enemy_idx: int = a.heroes[2].idx
	var ba: TeamIntel.EnemyBelief = ia.enemies[enemy_idx]
	var bb: TeamIntel.EnemyBelief = ib.enemies[enemy_idx]
	a.time = 100.0
	b_sim.time = 100.0
	for belief in [ba, bb]:
		belief.visible = true
		belief.max_hp *= 1.7
		belief.hp = 3.0
		belief.radius *= 1.8
		belief.shield = 120.0
		belief.cd_last[0] = 98.0
		belief.cd_disc[0] = 999.0
		belief.cd_disc_until = 1000.0
		belief.cd_disc_t = 99.0
		belief.reported_cd = [700.0]
		belief.reports_until = 1000.0
		belief.statuses = [{"type": "pain", "stacks": 6}]
		belief.casting = {"slot": 1}
		belief.pos = Vector2(990, 333)
		belief.last_seen_pos = belief.pos
		belief.vel = Vector2(80, -40)
		belief.sealed = [0, 1]
		belief.fish_used = 5
		belief.rage = 6.0
		belief.shards = 30.0
		belief.heal_bank = 300.0
	var scheduled: Dictionary = packet("RESPAWN_SCHEDULED", enemy_idx, 88.0)
	scheduled.respawn_at = 100.0
	ia.ingest([scheduled])
	ib.ingest([scheduled])
	check(ba.dead and not ba.visible, "public respawn timer communicates death without vision")
	a.heroes[2].pos = Vector2(1200, 90)
	b_sim.heroes[2].pos = Vector2(2000, 1100)
	a.heroes[2].cooldowns[0] = 1000.0
	b_sim.heroes[2].cooldowns[0] = 0.0
	var respawn: Dictionary = packet("HERO_RESPAWNED", enemy_idx, 100.0)
	respawn.life_id = 3
	respawn.protected_until = 102.0
	ia.ingest([respawn])
	ib.ingest([respawn])
	check(not ba.dead and not ba.visible, "respawn event revives belief without marking enemy seen")
	check(ba.pos == bb.pos and ba.particles == bb.particles, "hidden respawn true positions cannot affect new-life prior")
	check(ba.pos != a.heroes[2].pos and bb.pos != b_sim.heroes[2].pos, "respawn prior is not actual current location")
	check(ba.confidence < 0.5 and ba.spread > 0.0, "respawn region is represented with uncertainty")
	check(ba.cd_last[0] == 98.0 and bb.cd_last[0] == 98.0, "observed prior-life casts survive death")
	check(ia.ready_eta(ba, 0) == ib.ready_eta(bb, 0), "respawn does not reveal actual cooldown")
	check(ba.reported_cd.is_empty() and ba.cd_disc_until < a.time, "old-life false and exact disclosures expire")
	check(ba.statuses.is_empty() and ba.casting.is_empty() and ba.sealed.is_empty(), "old-life statuses cast and seals clear")
	check(is_zero_approx(ba.shield) and is_zero_approx(ba.rage) and is_zero_approx(ba.shards) and is_zero_approx(ba.heal_bank), "new life resets transient resources and shields")
	check(is_equal_approx(ba.max_hp, ba.def.stat("maxHealth")) and is_equal_approx(ba.hp, ba.max_hp), "new life full health uses base stats rather than expired growth")
	check(is_equal_approx(ba.radius, ba.def.stat("bodyRadius")), "new life removes old size modification")
	var resource_skill: Defs.AbilityDef = Defs.AbilityDef.new()
	resource_skill.condition = {"selfResource": {"key": "fish", "min": 1.0}}
	check(not ia._resource_ok(ba, resource_skill), "late respawn does not instantly invent fish resources")
	a.time = 107.9
	check(not ia._resource_ok(ba, resource_skill), "fish generation waits eight seconds after respawn")
	a.time = 108.01
	check(ia._resource_ok(ba, resource_skill), "public fish generation timer starts from respawn")
	# Unseen further true movement must not refresh a prior as a live tracker.
	a.heroes[2].pos = Vector2(1800, 1000)
	b_sim.time = a.time
	a._update_visibility()
	b_sim._update_visibility()
	ia.observe()
	ib.observe()
	check(not ba.visible and not bb.visible and ba.pos == bb.pos, "unseen observation cannot track respawned true location")
	ia.dispose()
	ib.dispose()
	a.dispose()
	b_sim.dispose()

func objective_visibility() -> void:
	var sim: BattleSim = fresh()
	# UI references autoloads, so load after the SceneTree autoload setup.
	var view_script: Script = load("res://scripts/view/battle_view.gd")
	if view_script == null or not view_script.can_instantiate():
		check(false, "battle view can load for visibility routing test")
		sim.dispose()
		return
	var view = view_script.new()
	view.sim = sim
	view.perspective = 0
	var hidden: Dictionary = packet("HERO_RESPAWNED", sim.heroes[2].idx, 12.0)
	check(not view._ev_vis(hidden), "enemy respawn position effect remains vision gated")
	hidden.type = "HEAL_ZONE_USED"
	check(not view._ev_vis(hidden), "hidden pad user position effect remains vision gated")
	for kind in ["CONTROL_CAPTURED", "CONTROL_NEUTRALIZED", "CONTROL_CONTESTED", "CONTROL_SCORE"]:
		hidden.type = kind
		check(view._ev_vis(hidden), "public objective event visible through fog: " + kind)
	view.free()
	sim.dispose()
