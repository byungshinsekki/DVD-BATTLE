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
		push_error("REGRESSION: " + label)

func fresh(blue: Array, red: Array) -> BattleSim:
	var sim: BattleSim = BattleSim.new({"blue": blue, "red": red, "arena_id": "classic", "seed": 9122, "max_time": 150.0})
	for u in sim.heroes:
		u.pos = Vector2(500.0 + u.team * 145.0, 300.0 + u.slot * 92.0)
		u.prev_pos = u.pos
	sim.start()
	return sim

func advance(sim: BattleSim, seconds: float) -> void:
	for i in int(ceil(seconds / BattleSim.DT)):
		if sim.state == BattleSim.RUNNING:
			sim.step()

func cast(sim: BattleSim, u: BUnit, slot: int, target: BUnit, extra: Dictionary = {}) -> bool:
	u.action = null
	u.command = {}
	u.cooldowns[slot - 1] = sim.time
	var aim: Vector2 = target.pos if target else u.pos
	var started: bool = sim.start_ability(u, slot - 1, target, aim, {"extra": extra})
	if started:
		var a: Defs.AbilityDef = u.def.abilities[slot - 1]
		advance(sim, a.cast_time + a.recovery + 0.10)
	return started

func _run() -> void:
	DB.ensure_loaded()
	check(DB.characters.size() == 26, "26 playable characters")
	check(DB.char_def("politician").abilities.size() == 3, "politician has three active skills")
	check(DB.char_def("torturer").abilities.size() == 4, "torturer has four reworked skills")
	politician_stance()
	news_and_diversion()
	propaganda()
	pain_and_whip()
	gag_and_prison()
	information_privacy()
	configured_balance_rules()
	var report: Dictionary = {"passed": passed, "failed": failed, "status": "PASS" if failed.is_empty() else "FAIL"}
	var file: FileAccess = FileAccess.open("res://reports/mechanics_regression.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("MECHANICS_REGRESSION ", JSON.stringify(report))
	quit(0 if failed.is_empty() else 1)

func politician_stance() -> void:
	var sim: BattleSim = fresh(["politician", "archer"], ["mage"])
	var p: BUnit = sim.heroes[0]
	var enemy: BUnit = sim.heroes[2]
	check(not sim.can_basic(p) and not sim.start_basic(p, enemy), "politician cannot basic attack")
	advance(sim, 0.6)
	check(sim.warfare.contemplating(p), "stationary contemplation activates")
	check(is_equal_approx(sim.ability_coefficient(p), 1.3), "contemplation coefficient is +30%")
	for cc in Defs.CC_TYPES:
		check(not sim.apply_status(enemy, p, {"status": String(cc), "duration": 2.0, "magnitude": 0.4}), "contemplation blocks " + String(cc))
	var boosted: float = sim.apply_damage(p, enemy, {"school": "true", "base": 17.0, "ap": 0.5})
	check(absf(boosted - (17.0 + p.def.stat("abilityPower") * 0.5 * 1.3)) < 0.001, "only scaling term is amplified")
	var frozen: Array = sim.freeze_effects(p, enemy, [{"type": "damage", "school": "true", "base": 17.0, "ap": 0.5}], false, true)
	var frozen_damage: float = sim.apply_damage(p, enemy, frozen[0])
	check(absf(frozen_damage - boosted) < 0.001, "frozen projectile scaling is applied exactly once")
	p.vel = Vector2(10, 0)
	check(not sim.warfare.contemplating(p), "movement immediately ends contemplation")
	check(sim.apply_status(enemy, p, {"status": "silence", "duration": 0.2}), "moving politician can be silenced")
	sim.dispose()

func news_and_diversion() -> void:
	var sim: BattleSim = fresh(["politician", "giant"], ["archer", "politician"])
	var p: BUnit = sim.heroes[0]
	var ally: BUnit = sim.heroes[1]
	var enemy: BUnit = sim.heroes[2]
	ally.hp = sim.max_hp(ally) * 0.4
	var real_pos: Vector2 = ally.pos
	check(cast(sim, p, 1, p), "fake news can be cast")
	var real_hp: float = ally.hp
	var report: Dictionary = sim.warfare.observation(1, ally)
	check(bool(report.misinformation) and report.pos != ally.pos and not is_equal_approx(report.hp, ally.hp), "fake news changes perceived position and health")
	check(report.ready_at.size() == ally.cooldowns.size(), "fake cooldown report covers actual ability slots")
	check(ally.pos == real_pos and is_equal_approx(ally.hp, real_hp), "news does not mutate real combat state")
	check(not bool(sim.warfare.observation(0, ally).misinformation), "allied observations remain honest")
	for i in 12:
		cast(sim, p, 1, p)
	check(sim.warfare.distrust[1] == 10, "distrust caps at ten")
	check(not bool(sim.warfare.observation(1, ally).misinformation), "ten distrust rejects all false reports")
	check(cast(sim, p, 2, ally), "diversion can select an ally")
	check(sim.warfare.distrust[1] == 0, "diversion resets distrust")
	check(sim.forced_target(enemy) == ally, "diversion forces selected ally rather than caster")
	check(not sim.can_cast(enemy), "hard taunt blocks ability casts")
	check(sim.forced_target(sim.heroes[3]) == null, "contemplating enemy politician resists hard taunt")
	enemy.command = {"kind": "move", "pos": Vector2(1200, 100)}
	sim._try_execute_command(enemy)
	check(sim.forced_target(enemy) == ally, "manual AI command cannot bypass active diversion")
	advance(sim, 2.0)
	check(sim.forced_target(enemy) == null, "taunt target clears on expiry")
	cast(sim, p, 2, ally)
	sim.kill_unit(ally, enemy, {})
	check(sim.forced_target(enemy) == null, "taunt ends when designated ally dies")
	sim.dispose()

func propaganda() -> void:
	var sim: BattleSim = fresh(["politician", "mage"], ["archer"])
	var p: BUnit = sim.heroes[0]
	var ally: BUnit = sim.heroes[1]
	advance(sim, 0.6)
	var armor_before: float = sim.stat(ally, &"armor")
	cast(sim, p, 3, p)
	var armor_after: float = sim.stat(ally, &"armor")
	var coeff_after: float = sim.ability_coefficient(ally)
	check(armor_after > armor_before and coeff_after > 1.0, "propaganda grants armor and ability coefficients")
	cast(sim, p, 3, p)
	check(is_equal_approx(sim.stat(ally, &"armor"), armor_after), "recast does not stack armor")
	check(is_equal_approx(sim.ability_coefficient(ally), coeff_after), "propaganda does not recursively compound itself")
	advance(sim, 5.2)
	check(is_equal_approx(sim.stat(ally, &"armor"), armor_before), "armor bonus expires")
	check(is_equal_approx(sim.ability_coefficient(ally), 1.0), "coefficient bonus expires")
	sim.dispose()

func pain_and_whip() -> void:
	var sim: BattleSim = fresh(["torturer", "torturer"], ["archer"])
	var t: BUnit = sim.heroes[0]
	var other: BUnit = sim.heroes[1]
	var enemy: BUnit = sim.heroes[2]
	var normal_speed: float = sim.stat(enemy, &"moveSpeed")
	sim.warfare.add_pain(t, enemy, 8, {})
	check(sim.owned_status(enemy, &"pain", t.idx).stacks == 6, "pain caps at six")
	check(sim.stat(enemy, &"moveSpeed") < normal_speed, "pain reduces move speed")
	var hp: float = enemy.hp
	advance(sim, 1.05)
	check(enemy.hp < hp, "pain deals periodic damage")
	check(sim.owned_status(enemy, &"pain", t.idx).stacks == 6, "pain ticks do not add recursive stacks")
	check(not sim.check_condition(other, enemy, other.def.abilities[1].condition), "other torturer cannot spend another source's pain")
	advance(sim, 3.0)
	sim.warfare.add_pain(t, enemy, 1, {})
	advance(sim, 1.2)
	check(sim.owned_status(enemy, &"pain", t.idx) != null, "fresh hit refreshes pain expiry")
	advance(sim, 4.0)
	check(sim.owned_status(enemy, &"pain", t.idx) == null, "unmaintained pain fully resets")
	check(is_equal_approx(sim.stat(enemy, &"moveSpeed"), normal_speed), "pain slow ends with stacks")
	sim.dispose()
	var damage: Array[float] = []
	for distance in [100.0, 190.0]:
		sim = fresh(["torturer"], ["archer"])
		t = sim.heroes[0]
		enemy = sim.heroes[1]
		enemy.pos = t.pos + Vector2(distance, 0)
		hp = enemy.hp
		cast(sim, t, 1, enemy)
		damage.append(hp - enemy.hp)
		check(sim.owned_status(enemy, &"pain", t.idx).stacks == (1 if distance < 165 else 2), "whip inner/outer pain at " + str(distance))
		sim.dispose()
	check(damage[1] > damage[0], "outer whip deals bonus damage")
	sim = fresh(["torturer"], ["archer"])
	t = sim.heroes[0]
	enemy = sim.heroes[1]
	check(sim.start_ability(t, 0, enemy, enemy.pos), "whip windup starts")
	enemy.pos = t.pos + Vector2(0, 250)
	advance(sim, 0.7)
	check(sim.owned_status(enemy, &"pain", t.idx) == null, "whip misses a target that dodges its fixed cone")
	sim.dispose()

func gag_and_prison() -> void:
	var sim: BattleSim = fresh(["torturer", "torturer"], ["archer"])
	var t: BUnit = sim.heroes[0]
	var enemy: BUnit = sim.heroes[2]
	check(not cast(sim, t, 2, enemy), "gag rejects targets below three pain")
	sim.warfare.add_pain(t, enemy, 3, {})
	check(cast(sim, t, 2, enemy), "gag accepts three owned pain")
	check(sim.has_status(enemy, &"silence") and not sim.can_cast(enemy), "gag prevents skills")
	check(sim.can_basic(enemy), "silence still allows basic attacks")
	check(not cast(sim, t, 4, enemy), "interrogation rejects unconfined targets")
	advance(sim, 2.2)
	enemy.pos = t.pos + Vector2(90, 0)
	var armor_before: float = sim.stat(enemy, &"armor")
	check(cast(sim, t, 3, enemy), "close-range prison succeeds")
	check(sim.stat(enemy, &"armor") < armor_before, "prison lowers armor")
	check(not sim.check_condition(sim.heroes[1], enemy, sim.heroes[1].def.abilities[3].condition), "interrogation requires own prison")
	var center: Vector2 = enemy.pos
	enemy.pos = center + Vector2(200, 0)
	sim.warfare.constrain(enemy, center)
	check(enemy.pos.distance_to(center) < InformationWarfare.PRISON_RADIUS, "prison prevents captive crossing wall")
	var outside: Vector2 = t.pos
	t.pos = center
	sim.warfare.constrain(t, outside)
	check(t.pos.distance_to(center) >= InformationWarfare.PRISON_RADIUS, "prison also blocks outside allies")
	advance(sim, 4.0)
	check(not sim.has_status(enemy, &"imprisoned"), "prison and armor reduction expire")
	check(is_equal_approx(sim.stat(enemy, &"armor"), armor_before), "prison armor penalty restores")
	sim.dispose()

func information_privacy() -> void:
	var sim: BattleSim = fresh(["torturer"], ["archer", "politician"])
	var t: BUnit = sim.heroes[0]
	var target: BUnit = sim.heroes[1]
	var p: BUnit = sim.heroes[2]
	advance(sim, 0.6)
	check(not sim.warfare.reveal(t, target, "health"), "press control blocks hostile disclosure for allies")
	check(not sim.warfare.reveal(t, target, "position"), "press control blocks position disclosure")
	check(not sim.warfare.reveal(t, target, "cooldowns"), "press control blocks cooldown disclosure")
	p.vel = Vector2(10, 0)
	for field in ["position", "health", "cooldowns"]:
		sim.tick_events.clear()
		check(sim.warfare.reveal(t, target, field), "moving politician permits " + field + " disclosure")
		var disclosed: Array = []
		for ev in sim.tick_events:
			if ev.type == "INFO_REVEAL":
				disclosed.append(ev)
		check(disclosed.size() == 1 and str(disclosed[0].field) == field and int(disclosed[0].team) == 0, "one information field sent only to requesting team: " + field)
	sim.dispose()

func configured_balance_rules() -> void:
	var sim: BattleSim = fresh(["world_tree"], ["archer"])
	var tree: BUnit = sim.heroes[0]
	var rule: Dictionary = tree.def.rule("nexus_seed_path")
	check(sim.kits._close_garden(tree, [Vector2(400,200), Vector2(460,200), Vector2(460,260), Vector2(400,260)]), "closed seed path creates a garden")
	var garden: Dictionary = sim.gardens.back()
	check(is_equal_approx(garden.rate, float(rule.rateCap)), "actual garden rate follows published balance data")
	check(is_equal_approx(garden.budget, float(rule.budgetBase) + float(rule.budgetAp) * sim.stat(tree, &"abilityPower")), "actual garden budget follows published balance data")
	check(is_equal_approx(float(rule.selfHealingRatio), 0.45), "self healing is separated from full ally healing")
	sim.dispose()
