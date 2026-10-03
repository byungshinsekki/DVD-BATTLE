extends SceneTree

var passed: int = 0
var failed: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	if value:
		passed += 1
	else:
		failed.append(label)
		push_error("AI INFORMATION: " + label)

func fresh(blue: Array = ["archer", "mage"], red: Array = ["mage", "politician"]) -> BattleSim:
	var sim: BattleSim = BattleSim.new({"blue": blue, "red": red, "arena_id": "classic", "seed": 314122, "max_time": 150.0})
	for u in sim.heroes:
		u.pos = Vector2(480.0 + u.team * 170.0, 280.0 + u.slot * 85.0)
		u.prev_pos = u.pos
	sim.start()
	return sim

func brain_for(sim: BattleSim, team: int = 0) -> TacticianBrain:
	var brain: TacticianBrain = TacticianBrain.new(sim, team)
	brain.on_start(sim)
	return brain

func signature(brain: TacticianBrain, unit: BUnit) -> Dictionary:
	brain.decide(unit)
	return {"kind": unit.command.get("kind", ""), "target": unit.command.get("target", -1), "index": unit.command.get("index", -1), "pos": unit.command.get("pos", Vector2.ZERO), "goal": unit.command.get("goal", Vector2.ZERO), "stance": brain.plan.stance, "lead": brain.plan.lead, "focus": brain.plan.focus}

func _run() -> void:
	DB.ensure_loaded()
	hidden_noninterference()
	hidden_entity_lifetime()
	misinformation_consumption()
	disclosure_boundaries()
	reservations_influence_value()
	observed_learning_changes_prediction()
	projectile_learning_evidence()
	var result: Dictionary = {"status": "PASS" if failed.is_empty() else "FAIL", "passed": passed, "failed": failed}
	print("AI_INFORMATION_REGRESSION ", JSON.stringify(result))
	quit(0 if failed.is_empty() else 1)

func hidden_noninterference() -> void:
	# Two histories have identical public observations but deliberately different
	# hidden health, cooldowns, positions and one unobserved environmental death.
	var left: BattleSim = fresh()
	var right: BattleSim = fresh()
	var a: TacticianBrain = brain_for(left)
	var b: TacticianBrain = brain_for(right)
	for sim in [left, right]:
		for ally in sim.heroes:
			if ally.team == 0:
				ally.pos = Vector2(130.0, 250.0 + 80.0 * ally.slot)
		sim.time = 6.0
		sim.tick = 180
	left.heroes[2].pos = Vector2(1120.0, 250.0)
	left.heroes[3].pos = Vector2(1130.0, 410.0)
	right.heroes[2].pos = Vector2(1030.0, 450.0)
	right.heroes[3].pos = Vector2(1060.0, 100.0)
	right.heroes[2].hp = 31.0
	for i in right.heroes[2].cooldowns.size():
		right.heroes[2].cooldowns[i] = 99.0
	left._update_visibility()
	right._update_visibility()
	check(not left.is_seen(0, left.heroes[2]) and not right.is_seen(0, right.heroes[2]), "noninterference fixture is outside team vision")
	a.intel.observe()
	b.intel.observe()
	var ea: TeamIntel.EnemyBelief = a.intel.enemies[2]
	var eb: TeamIntel.EnemyBelief = b.intel.enemies[2]
	check(ea.pos.is_equal_approx(eb.pos), "hidden position changes do not alter particle estimate")
	check(is_equal_approx(ea.hp, eb.hp), "hidden health changes do not alter remembered health")
	check(is_equal_approx(a.intel.ready_prob(ea, 0), b.intel.ready_prob(eb, 0)), "hidden cooldown changes do not alter readiness inference")
	left.tick_events.clear()
	right.tick_events.clear()
	right.kill_unit(right.heroes[3], null, {"environment": true})
	b.intel.ingest(right.tick_events)
	check(not (b.intel.enemies[3] as TeamIntel.EnemyBelief).dead, "unobserved environmental death is not learned")
	a._plan()
	b._plan()
	check(signature(a, left.heroes[0]) == signature(b, right.heroes[0]), "identical public histories produce identical tactical decisions")
	a.dispose()
	b.dispose()
	left.dispose()
	right.dispose()

func hidden_entity_lifetime() -> void:
	var sim: BattleSim = fresh(["archer"], ["engineer"])
	var owner: BUnit = sim.heroes[1]
	var turret: BUnit = sim.kits.make_structure(owner, owner.def.abilities[0], Vector2(640.0, 360.0), "turret")
	var intel: TeamIntel = TeamIntel.new(sim, 0)
	sim._update_visibility()
	intel.observe()
	check(intel.entities.has(turret.idx), "visible turret is initially known")
	sim.heroes[0].pos = Vector2(100.0, 100.0)
	turret.pos = Vector2(1100.0, 600.0)
	sim.time = 0.5
	sim._update_visibility()
	intel.observe()
	check(intel.entities.has(turret.idx) and not (intel.entities[turret.idx] as TeamIntel.EnemyBelief).visible, "unseen living turret retains short last-known memory")
	sim.tick_events.clear()
	sim.kill_unit(turret, null, {"environment": true})
	sim._prune_entities()
	intel.ingest(sim.tick_events)
	intel.observe()
	check(intel.entities.has(turret.idx), "unobserved turret death and physical pruning do not erase memory early")
	sim.time = 2.1
	intel.observe()
	check(not intel.entities.has(turret.idx), "unseen turret memory expires by observation age")
	intel.dispose()
	sim.dispose()

func misinformation_consumption() -> void:
	var sim: BattleSim = fresh()
	var politician: BUnit = sim.heroes[3]
	sim.heroes[2].hp *= 0.6
	check(sim.start_ability(politician, 0, null, politician.pos), "fake-news fixture starts through ordinary cast API")
	for _i in 16:
		sim.step()
	var brain: TacticianBrain = brain_for(sim)
	var archer: BUnit = sim.heroes[0]
	var target: BUnit = sim.heroes[2]
	var belief: TeamIntel.EnemyBelief = brain.intel.enemies[target.idx]
	check(belief.visible, "misinformation subject is visible")
	check(not belief.pos.is_equal_approx(target.pos), "visible enemy belief consumes false location")
	check(not is_equal_approx(belief.hp, target.hp), "visible enemy belief consumes false health")
	check(not belief.reported_cd.is_empty(), "enemy belief consumes false cooldown report")
	var actual_health: float = target.hp
	var actual_position: Vector2 = target.pos
	var actual_cd: PackedFloat64Array = target.cooldowns.duplicate()
	brain._plan()
	check(is_equal_approx(float(brain.plan.lead), ((sim.heroes[0].hp + sim.heroes[1].hp) - ((brain.intel.enemies[2] as TeamIntel.EnemyBelief).hp + (brain.intel.enemies[3] as TeamIntel.EnemyBelief).hp)) / (sim.max_hp(sim.heroes[0]) + sim.max_hp(sim.heroes[1]))), "team advantage is computed from reported enemy health")
	var projectile: Defs.AbilityDef = archer.def.abilities[0]
	var aim_before: Vector2 = brain.refine_aim(archer, projectile, target, belief.pos)
	archer.command = {"kind": "basic", "target": target.idx, "pos": belief.pos, "need": 80.0}
	var steer_before: Vector2 = brain.steer(archer)
	target.pos += Vector2(50.0, -70.0)
	target.hp = 19.0
	for i in target.cooldowns.size():
		target.cooldowns[i] = 999.0
	check(brain.refine_aim(archer, projectile, target, belief.pos).is_equal_approx(aim_before), "aim refinement cannot bypass report through live enemy position")
	check(brain.steer(archer).is_equal_approx(steer_before), "normal pursuit cannot bypass report through live enemy position")
	var before_prob: float = brain.intel.ready_prob(belief, 0)
	target.cooldowns[0] = 0.0
	check(is_equal_approx(brain.intel.ready_prob(belief, 0), before_prob), "readiness evaluation does not read live enemy cooldown")
	target.pos = actual_position
	target.hp = actual_health
	target.cooldowns = actual_cd
	sim.time += 5.2
	sim.warfare.update(0.0)
	sim._update_visibility()
	brain.intel.observe()
	check(belief.reported_cd.is_empty(), "expired fake cooldown report is removed")
	check(belief.pos.is_equal_approx(target.pos) and is_equal_approx(belief.hp, target.hp), "fresh direct observation restores correct location and health after deception")
	brain.dispose()
	sim.dispose()

func disclosure_boundaries() -> void:
	var sim: BattleSim = fresh(["torturer"], ["mage"])
	var source: BUnit = sim.heroes[0]
	var target: BUnit = sim.heroes[1]
	var intel: TeamIntel = TeamIntel.new(sim, 0)
	var belief: TeamIntel.EnemyBelief = intel.enemies[target.idx]
	belief.pos = Vector2(20.0, 30.0)
	belief.hp = 111.0
	target.hp = 543.0
	sim.tick_events.clear()
	check(sim.warfare.reveal(source, target, "health"), "health disclosure succeeds without a protecting politician")
	intel.ingest(sim.tick_events)
	check(is_equal_approx(belief.hp, 543.0), "selected health field is disclosed")
	check(belief.pos == Vector2(20.0, 30.0), "health disclosure does not disclose location")
	check(belief.cd_disc[0] < 0.0, "health disclosure does not disclose cooldowns")
	var private_event: Dictionary = sim.emit("INFO_REVEAL", source.idx, target.idx, {"team": 1, "field": "health", "value": {"hp": 17.0, "max_hp": 999.0}, "duration": 5.0})
	intel.ingest([private_event])
	check(is_equal_approx(belief.hp, 543.0), "disclosure addressed to another team is ignored")
	sim.tick_events.clear()
	check(sim.warfare.reveal(source, target, "position"), "position disclosure succeeds")
	intel.ingest(sim.tick_events)
	check(belief.pos.is_equal_approx(target.pos) and is_equal_approx(belief.hp, 543.0) and belief.cd_disc[0] < 0.0, "position disclosure changes only positional knowledge")
	var disclosed_position: Vector2 = belief.pos
	target.pos += Vector2(120.0, 40.0)
	check(belief.pos.is_equal_approx(disclosed_position), "position disclosure is a snapshot, not live hidden tracking")
	sim.tick_events.clear()
	target.cooldowns[0] = sim.time + 40.0
	check(sim.warfare.reveal(source, target, "cooldowns", 1.0), "cooldown disclosure succeeds")
	intel.ingest(sim.tick_events)
	check(is_zero_approx(intel.ready_prob(belief, 0)), "live disclosure reports the selected cooldown accurately")
	check(is_equal_approx(intel.ready_eta(belief, 0), 40.0), "cooldown ETA uses a live explicit disclosure")
	sim.time += 1.1
	check(intel.ready_prob(belief, 0) > 0.01, "expired disclosure falls back to uncertainty rather than permanent exact cooldown knowledge")
	intel.dispose()
	sim.dispose()

func reservations_influence_value() -> void:
	var sim: BattleSim = fresh(["archer", "mage"], ["mage"])
	var brain: TacticianBrain = brain_for(sim)
	var evaluator: BUnit = sim.heroes[0]
	var ally: BUnit = sim.heroes[1]
	var target: BUnit = sim.heroes[2]
	var belief: TeamIntel.EnemyBelief = brain.intel.enemies[target.idx]
	belief.hp = 40.0
	brain._plan()
	var ctx: Dictionary = brain._ctx(evaluator)
	var ability: Defs.AbilityDef = evaluator.def.abilities[0]
	var before: Dictionary = brain._enemy_value(evaluator, ability, belief, ctx, 0.95)
	check(sim.start_ability(ally, 0, target, target.pos), "ally starts a real windup for reservation")
	brain._compute_reserved()
	check(float(brain.reserved.get(target.idx, 0.0)) > 0.0, "real ally windup reserves expected damage")
	var after: Dictionary = brain._enemy_value(evaluator, ability, belief, ctx, 0.95)
	check(float(after.value) < float(before.value), "existing ally commitment reduces redundant damage value")
	sim.cancel_action(ally, "test_interrupt")
	brain._compute_reserved()
	check(is_zero_approx(float(brain.reserved.get(target.idx, 0.0))), "interrupted windup releases damage reservation")
	var real_hp: float = target.hp
	brain._plan()
	brain.decide(evaluator)
	check(is_equal_approx(real_hp, target.hp) and sim.winner == -1, "planning itself does not mutate combat health or choose an outcome")
	brain.dispose()
	sim.dispose()

func observed_learning_changes_prediction() -> void:
	var sim: BattleSim = fresh(["archer"], ["mage"])
	var brain: TacticianBrain = brain_for(sim)
	var archer: BUnit = sim.heroes[0]
	var enemy: BUnit = sim.heroes[1]
	for sample in 14:
		sim.time = 0.35 * (sample + 1)
		sim.tick += 11
		enemy.pos = Vector2(660.0, 230.0 + 12.0 * sample)
		sim._update_visibility()
		brain.intel.observe()
	var learned: TeamIntel.EnemyBelief = brain.intel.enemies[enemy.idx]
	check(learned.movement_samples >= 8 and absf(learned.strafe_bias) > 0.15, "repeated observed lateral movement creates bounded learned evidence")
	var prediction: Vector2 = brain.lead_point(archer.pos, learned, 400.0, 0.3)
	var novice: TeamIntel.EnemyBelief = TeamIntel.EnemyBelief.new()
	novice.def = learned.def
	novice.pos = learned.pos
	novice.vel = learned.vel
	novice.radius = learned.radius
	var unlearned: Vector2 = brain.lead_point(archer.pos, novice, 400.0, 0.3)
	check(prediction.distance_to(unlearned) > 0.5, "learned tendency changes an actual aiming prediction")
	var samples: int = learned.movement_samples
	archer.pos = Vector2(100.0, 100.0)
	enemy.pos = Vector2(1130.0, 600.0)
	sim.time += 1.0
	sim._update_visibility()
	brain.intel.observe()
	check(learned.movement_samples == samples, "hidden enemy movement does not create learning samples")
	brain.dispose()
	sim.dispose()

func projectile_learning_evidence() -> void:
	var sim: BattleSim = fresh(["archer"], ["mage"])
	var intel: TeamIntel = TeamIntel.new(sim, 0)
	intel.observe()
	var source: BUnit = sim.heroes[0]
	var target: BUnit = sim.heroes[1]
	var belief: TeamIntel.EnemyBelief = intel.enemies[target.idx]
	var hit_before: float = belief.dodge_hits
	var miss_before: float = belief.dodge_miss
	sim.tick_events.clear()
	sim.apply_damage(source, target, {"base": 5.0, "school": "physical"}, {"source_type": "ABILITY", "pain_tick": true, "proc": true})
	intel.ingest(sim.tick_events)
	check(is_equal_approx(belief.dodge_hits, hit_before), "damage over time is not evidence of projectile aim accuracy")
	intel.ingest([sim.emit("MISS", source.idx, target.idx, {"reason": "condition_changed"})])
	check(is_equal_approx(belief.dodge_miss, miss_before), "conditional cast failure is not evidence of enemy evasion")
	var skillshot: Defs.AbilityDef = source.def.abilities[0].duplicate_def()
	skillshot.homing = false
	skillshot.pierce = 1
	skillshot.range = 300.0
	skillshot.max_distance = 300.0
	sim.tick_events.clear()
	var projectile: ST.Projectile = sim.proj.spawn(source, target, target.pos, skillshot, [{"type": "damage", "base": 5.0, "school": "physical"}], {"source_type": "ABILITY", "ability": skillshot})
	intel.ingest(sim.tick_events)
	for _step in 40:
		sim.tick_events.clear()
		sim.time += BattleSim.DT
		sim.proj.update(BattleSim.DT)
		intel.ingest(sim.tick_events)
	check(projectile.dead, "piercing projectile reaches its natural end")
	check(is_equal_approx(belief.dodge_hits, hit_before + 0.5), "one actual observed projectile hit yields one learning sample")
	check(is_equal_approx(belief.dodge_miss, miss_before), "piercing range expiry after a hit is not counted as a dodge")
	intel.dispose()
	sim.dispose()
