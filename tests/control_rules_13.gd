extends SceneTree

var passed: int = 0
var failed: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed.append(label)
		push_error("CONTROL RULES: " + label)

func near(a: float, b: float, label: String) -> void:
	check(absf(a - b) < 0.0001, label)

func fresh(blue: Array = ["swordsman"], red: Array = ["archer"]) -> BattleSim:
	var sim: BattleSim = BattleSim.new({"blue": blue, "red": red, "arena_id": "control_crossroads", "seed": 13001})
	sim.start()
	sim.domination.points.clear()
	sim.domination.points.append({"id": "TEST", "label": "TEST", "center": Vector2(600, 400), "radius": 80.0,
		"owner": -1, "progress": 0.0, "contested": false, "_capture_team": -1, "_elapsed": 0.0})
	sim.domination.heal_zones.clear()
	for u in sim.heroes:
		u.pos = Vector2(100.0 + u.team * 1800.0, 100.0 + u.slot * 80.0)
		u.prev_pos = u.pos
	return sim

func occupy(u: BUnit) -> void:
	u.pos = Vector2(600, 400)
	u.prev_pos = u.pos

func away(u: BUnit) -> void:
	u.pos = Vector2(100.0 + u.team * 1800.0, 100)
	u.prev_pos = u.pos

func advance_mode(sim: BattleSim, seconds: float) -> void:
	var steps: int = int(round(seconds / BattleSim.DT))
	for _i in steps:
		sim.time += BattleSim.DT
		sim.domination.update(BattleSim.DT)

func _run() -> void:
	DB.ensure_loaded()
	mode_contract()
	capture_and_contest()
	occupancy_rules()
	heal_rules()
	respawn_rules(false)
	respawn_rules(true)
	life_cleanup()
	protection_rules()
	dead_source_guards()
	finish_rules()
	var report: Dictionary = {"status": "PASS" if failed.is_empty() else "FAIL", "passed": passed, "failed": failed}
	var file: FileAccess = FileAccess.open("res://reports/control_rules_13.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("CONTROL_RULES_13 ", JSON.stringify(report))
	quit(0 if failed.is_empty() else 1)

func mode_contract() -> void:
	var sim: BattleSim = BattleSim.new({"arena_id": "control_crossroads"})
	check(sim.is_control_mode(), "map infers control ruleset")
	near(sim.max_time, 480.0, "control default time limit")
	check(sim.domination.points.size() == 3 and not sim.domination.heal_zones.is_empty(), "map objects initialize mode")
	check(sim.domination.public_points()[0].size() == 7, "public points omit private occupant/progress internals")
	sim.dispose()
	sim = BattleSim.new({"arena_id": "classic", "mode": "draft"})
	check(not sim.is_control_mode(), "draft composition setting does not change ruleset")
	near(sim.max_time, 150.0, "elimination default unchanged")
	sim.start()
	sim.kill_unit(sim.heroes[1], sim.heroes[0], {})
	sim._check_end()
	check(sim.state == BattleSim.FINISHED and sim.winner == 0 and sim.domination.respawn_at.is_empty(), "elimination retains wipe finish and no respawn")
	sim.dispose()

func capture_and_contest() -> void:
	var sim: BattleSim = fresh()
	var p: Dictionary = sim.domination.points[0]
	occupy(sim.heroes[0])
	advance_mode(sim, 4.0)
	check(int(p.owner) == -1 and float(p.progress) < -0.79, "neutral point needs full five seconds")
	near(sim.heroes[0].st_capture_time, 4.0, "capture participation measured")
	occupy(sim.heroes[1])
	var progress: float = p.progress
	advance_mode(sim, 3.0)
	check(bool(p.contested) and int(p.owner) == -1, "two teams contest neutral point")
	near(p.progress, progress, "contest freezes capture progress")
	away(sim.heroes[1])
	advance_mode(sim, 1.0)
	check(int(p.owner) == 0 and sim.heroes[0].st_captures == 1, "five uncontested seconds captures for blue")
	away(sim.heroes[0])
	advance_mode(sim, 2.0)
	near(sim.domination.scores[0], 2.0, "owned empty point continues scoring")
	occupy(sim.heroes[0])
	occupy(sim.heroes[1])
	advance_mode(sim, 2.0)
	near(sim.domination.scores[0], 2.0, "contested owned point pauses scoring")
	away(sim.heroes[0])
	advance_mode(sim, 4.0)
	check(int(p.owner) == 0 and float(p.progress) > 0.79, "enemy cannot instantly steal owner point")
	advance_mode(sim, 1.0)
	check(int(p.owner) == -1 and is_zero_approx(float(p.progress)), "five seconds neutralizes enemy point")
	near(sim.domination.scores[0], 7.0, "previous owner scores until neutralization")
	advance_mode(sim, 5.0)
	check(int(p.owner) == 1, "ten uninterrupted seconds steals enemy point")
	near(sim.domination.scores[1], 0.0, "new owner scores only after capture boundary")
	advance_mode(sim, 1.0)
	near(sim.domination.scores[1], 1.0, "new owner scores normally")
	check(sim.result().control_history.size() > 3 and sim.result().units[0].captures == 1, "result exports objective history and contribution")
	sim.dispose()

func occupancy_rules() -> void:
	var sim: BattleSim = fresh()
	var blue: BUnit = sim.heroes[0]
	var entity: BUnit = sim.kits.create_entity(blue, Vector2(600, 400), "snake", 80, 8, {}, {"duration": 40.0})
	entity.pos = Vector2(600, 400)
	advance_mode(sim, 6.0)
	check(int(sim.domination.points[0].owner) == -1, "summon cannot capture")
	occupy(blue)
	blue.chamber = "separate_realm"
	advance_mode(sim, 6.0)
	check(int(sim.domination.points[0].owner) == -1, "separate realm cannot capture")
	blue.chamber = ""
	sim.push_status(blue, &"untargetable", blue.idx, 20.0)
	advance_mode(sim, 6.0)
	check(int(sim.domination.points[0].owner) == -1, "untargetable cannot capture")
	blue.statuses.clear()
	sim.push_status(blue, &"spawn_protection", blue.idx, 20.0, {"respawn_protection": true})
	advance_mode(sim, 6.0)
	check(int(sim.domination.points[0].owner) == -1, "spawn protection cannot capture")
	blue.statuses.clear()
	sim.push_status(blue, &"invisible", blue.idx, 20.0)
	advance_mode(sim, 2.0)
	away(blue)
	advance_mode(sim, 1.0)
	near(sim.domination.points[0].progress, 0.0, "leaving resets unfinished progress")
	occupy(blue)
	advance_mode(sim, 5.0)
	check(int(sim.domination.points[0].owner) == 0, "invisible physical hero can capture")
	sim.dispose()

func heal_rules() -> void:
	var sim: BattleSim = fresh(["swordsman", "mage"], ["archer"])
	var z: Dictionary = {"id": "PAD", "center": Vector2(600, 400), "radius": 80.0, "ready_at": 0.0, "cooldown": 25.0, "heal_ratio": 0.35}
	sim.domination.heal_zones.append(z)
	var blue: BUnit = sim.heroes[0]
	var ally: BUnit = sim.heroes[1]
	var red: BUnit = sim.heroes[2]
	occupy(blue)
	blue.hp = sim.max_hp(blue) * 0.85
	sim.domination.update(BattleSim.DT)
	near(z.ready_at, 0.0, "pad requires strictly under 85 percent")
	blue.hp = sim.max_hp(blue) * 0.5
	occupy(ally)
	ally.hp = sim.max_hp(ally) * 0.2
	occupy(red)
	sim.domination.update(BattleSim.DT)
	near(z.ready_at, 0.0, "contested pad does not consume cooldown")
	away(red)
	sim.domination.update(BattleSim.DT)
	near(ally.hp, sim.max_hp(ally) * 0.55, "pad heals lowest ratio hero by 35 percent max HP")
	near(blue.hp, sim.max_hp(blue) * 0.5, "pad heals exactly one hero")
	near(z.ready_at, 25.0, "pad has shared 25 second cooldown")
	near(ally.st_zone_healing, sim.max_hp(ally) * 0.35, "zone healing contribution records actual gain")
	away(blue)
	away(ally)
	occupy(red)
	red.hp = sim.max_hp(red) * 0.2
	sim.time = 24.9
	sim.domination.update(BattleSim.DT)
	near(red.hp, sim.max_hp(red) * 0.2, "enemy shares same pad cooldown")
	sim.time = 25.0
	sim.domination.update(BattleSim.DT)
	near(red.hp, sim.max_hp(red) * 0.55, "enemy may use pad when shared cooldown ends")
	var reduction: ST.Status = sim.push_status(red, &"healReduction", blue.idx, 100.0)
	reduction.magnitude = 2.0
	var before: float = red.hp
	var healing: float = red.st_healing
	var result: Dictionary = sim.apply_heal(red, red, {"base": 500.0})
	near(red.hp, before, "out of range healing reduction cannot cause damage")
	near(result.effective, 0.0, "effective healing is nonnegative")
	near(red.st_healing, healing, "healing statistics cannot go negative")
	sim.time = 50.0
	sim.domination.update(BattleSim.DT)
	near(z.ready_at, 50.0, "zero gain does not consume ready pad")
	red.statuses.clear()
	red.hp = sim.max_hp(red) * 0.8
	sim.domination.update(BattleSim.DT)
	near(red.hp, sim.max_hp(red), "pad clamps healing to missing HP")
	sim.dispose()

func respawn_rules(profiled: bool) -> void:
	var sim: BattleSim = fresh(["fisherman"], ["archer"])
	sim.profiling = profiled
	var u: BUnit = sim.heroes[0]
	u.st_damage = 71.0
	u.st_captures = 2
	u.cooldowns[0] = 100.0
	u.resources["fish"] = 5.0
	sim.kill_unit(u, sim.heroes[1], {})
	sim._check_end()
	check(sim.state == BattleSim.RUNNING, "control team wipe does not end match (profiled=%s)" % profiled)
	near(sim.domination.respawn_at[u.idx], 12.0, "respawn scheduled 12 seconds after death")
	for _i in 359: sim.step()
	check(not u.alive, "hero cannot respawn early")
	sim.step()
	check(u.alive and u.idx == 0 and u.life_id == 1, "same index gains a new life at exactly 12 seconds")
	near(u.hp, sim.max_hp(u), "respawn restores full health")
	check(u.pos.distance_to(u.spawn_pos) < 0.1, "respawn returns to original spawn")
	check(sim.has_status(u, &"spawn_protection") and sim.has_status(u, &"invulnerable"), "respawn grants protection")
	near(u.st_damage, 71.0, "lifetime damage survives respawn")
	check(u.st_captures == 2 and u.st_deaths == 1, "lifetime objective and death statistics survive")
	near(u.cooldowns[0], 100.0, "death does not reset long cooldown")
	near(u.resources.fish, 0.0, "temporary passive resources reset")
	near(u.ks.fish_next, sim.time + 8.0, "respawn passive timers restart relative to new life")
	check(sim.domination.respawn_at.is_empty(), "respawn countdown removed")
	var event: Dictionary = sim.tick_events[-1]
	for e in sim.tick_events:
		if str(e.type) == "HERO_RESPAWNED": event = e
	check(str(event.type) == "HERO_RESPAWNED" and not event.has("pos"), "public respawn event has no hidden position")
	sim.domination.break_protection(u)
	check(not sim.has_status(u, &"invulnerable"), "breaking protection removes tagged invulnerability")
	sim.dispose()

func life_cleanup() -> void:
	var sim: BattleSim = fresh()
	var blue: BUnit = sim.heroes[0]
	var red: BUnit = sim.heroes[1]
	var summon: BUnit = sim.kits.create_entity(blue, blue.pos, "snake", 80, 8, {}, {"duration": 100.0})
	sim.push_status(red, &"slow", blue.idx, 40.0)
	sim.add_buff(red, &"armor", -0.2, 40.0, blue.idx)
	sim.zones.spawn(blue, blue.pos, 80, 40, 1, [], "enemy", {}, "test")
	sim.schedule(40.0, {"kind": "area", "source": blue.idx, "pos": blue.pos, "radius": 10.0, "effects": [], "ctx": {}})
	var projectile: ST.Projectile = ST.Projectile.new()
	projectile.source_idx = blue.idx
	projectile.shooter_idx = summon.idx
	projectile.target_idx = red.idx
	sim.proj.list.append(projectile)
	sim.kill_unit(blue, red, {})
	check(not summon.alive and sim.entities.is_empty(), "death removes all owned summons")
	check(sim.proj.list.is_empty() and sim.zones.list.is_empty() and sim.delayed.is_empty(), "death removes projectile zone and delayed residues")
	check(red.statuses.is_empty() and red.buffs.is_empty(), "old life cannot retain sourced status or stat effects")
	check(blue.action == null and blue.motion == null and blue.command.is_empty(), "dead unit has no executing action")
	sim.dispose()

func finish_rules() -> void:
	var sim: BattleSim = fresh()
	sim.heroes[0].hp = 1.0
	sim.time = 480.0
	sim.domination.scores = [20.0, 20.0]
	sim._check_end()
	check(sim.winner == 2 and sim.finish_reason == "control_time_limit", "equal score time limit draws regardless of remaining HP")
	sim.dispose()
	sim = fresh()
	sim.domination.scores = [300.0, 299.0]
	sim._check_end()
	check(sim.winner == 0 and sim.finish_reason == "control_score", "target score finishes match")
	sim.dispose()
	sim = fresh()
	sim.domination.scores = [300.0, 300.0]
	sim._check_end()
	check(sim.winner == 2, "simultaneous equal target score draws")
	sim.dispose()

func protection_rules() -> void:
	var sim: BattleSim = fresh(["werewolf"], ["archer"])
	var u: BUnit = sim.heroes[0]
	var enemy: BUnit = sim.heroes[1]
	for status: StringName in [&"spawn_protection", &"invulnerable"]:
		sim.push_status(u, status, u.idx, 2.0, {"respawn_protection": true})
	check(sim.start_ability(u, 1, u, u.pos), "friendly self buff can cast during protection")
	check(sim.has_status(u, &"spawn_protection"), "friendly self buff retains protection")
	u.action = null
	check(sim.start_ability(u, 2, u, u.pos), "self centered crowd control can cast")
	check(not sim.has_status(u, &"spawn_protection"), "self centered hostile skill breaks protection at cast start")
	u.action = null
	for status: StringName in [&"spawn_protection", &"invulnerable"]:
		sim.push_status(u, status, u.idx, 2.0, {"respawn_protection": true})
	sim.apply_damage(u, enemy, {"base": 1.0, "school": "true"}, {"source_type": "PASSIVE"})
	check(not sim.has_status(u, &"spawn_protection"), "passive hostile damage also breaks protection")
	sim.kill_unit(u, enemy, {})
	var hp: float = enemy.hp
	sim.apply_damage(u, enemy, {"base": 200.0, "school": "true"})
	near(enemy.hp, hp, "dead previous life cannot deal queued damage")
	sim.dispose()

func dead_source_guards() -> void:
	var sim: BattleSim = fresh()
	var source: BUnit = sim.heroes[0]
	var target: BUnit = sim.heroes[1]
	source.hp = 1.0
	target.hp = sim.max_hp(target) * 0.4
	var hp: float = target.hp
	# A source can die during an already-running multi-effect resolution.
	sim.apply_effects(source, target, [
		{"type": "damage", "selfOnly": true, "base": 10.0, "school": "true"},
		{"type": "heal", "base": 100.0},
		{"type": "status", "status": "silence", "duration": 10.0},
		{"type": "buff", "stat": "armor", "amount": 0.5, "duration": 10.0}], {})
	check(not source.alive, "source can die in middle of effect sequence")
	check(target.hp == hp and target.statuses.is_empty() and target.buffs.is_empty(), "remaining effects stop immediately when source life ends")
	check(not sim.apply_status(source, target, {"status": "slow", "duration": 2.0}), "dead source cannot apply direct status")
	check(not sim.apply_mark(source, target, {"status": "infection", "duration": 2.0}), "dead source cannot apply direct mark")
	check(not sim.apply_dot(source, target, {"duration": 2.0, "interval": 1.0, "damageEffect": {"base": 1.0}}), "dead source cannot create direct damage over time")
	near(sim.apply_heal(source, target, {"base": 100.0}).effective, 0.0, "dead source cannot apply direct healing")
	near(sim.apply_shield(source, target, {"base": 100.0, "duration": 2.0}), 0.0, "dead source cannot apply direct shield")
	check(sim.apply_status(null, target, {"status": "slow", "duration": 1.0}), "source-less environmental status remains valid")
	sim.dispose()
