extends SceneTree

var passed: int = 0
var failed: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed.append(label)
		push_error("ENVIRONMENT_152: " + label)

func near(a: float, b: float, label: String) -> void:
	check(absf(a - b) < 0.0001, label)

func hazard(type: String, extra: Dictionary = {}) -> Dictionary:
	var h: Dictionary = {"id": type, "type": type, "shape": "circle", "x": 600.0, "y": 400.0, "radius": 200.0,
		"period": 4.0, "activeDuration": 1.0, "warningDuration": 1.0, "phase": 0.0}
	h.merge(extra, true)
	return h

func fresh(hazards: Array, blue: Array = ["swordsman"], red: Array = ["archer"], obstacles: Array = []) -> BattleSim:
	var sim: BattleSim = BattleSim.new({"blue": blue, "red": red, "arena_id": "classic", "seed": 152171})
	sim.arena = Arena.from_data({"id": "environment_152_test", "hazards": hazards, "obstacles": obstacles})
	sim.start()
	for u in sim.heroes:
		u.pos = Vector2(600, 400)
		u.prev_pos = u.pos
		u.vel = Vector2.ZERO
	return sim

func at(sim: BattleSim, t: float, dt: float = BattleSim.DT) -> void:
	sim.time = t
	sim.env.update(dt)

func _run() -> void:
	DB.ensure_loaded()
	clock_contract()
	haste_contract()
	fountain_contract()
	gravity_contract()
	portal_contract()
	wave_contract()
	protection_contract()
	determinism_and_public_state()
	var report: Dictionary = {"status": "PASS" if failed.is_empty() else "FAIL", "passed": passed, "failed": failed,
		"coverage": ["phase clock", "haste refresh and expiration", "shared deterministic fountain", "wall and prison sweeps", "protection states", "one-hit expanding wave", "AI opportunity and forecast", "independent simulations", "all 22 characters"]}
	var file: FileAccess = FileAccess.open("res://reports/environment_152.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("ENVIRONMENT_152 ", JSON.stringify(report))
	quit(0 if failed.is_empty() else 1)

func clock_contract() -> void:
	for type in ["haste", "healing_fountain", "wind", "portal"]:
		var clock: Dictionary = Arena.hazard_clock(hazard(type), 71.7)
		check(bool(clock.active) and not bool(clock.warning), type + " is continuously available")
		near(float(clock.remaining), 0.0, type + " has no phase countdown")
	for type in ["gravity", "shockwave"]:
		var h: Dictionary = hazard(type)
		var active: Dictionary = Arena.hazard_clock(h, 0.25)
		check(bool(active.active) and not bool(active.warning), type + " active phase")
		near(float(active.remaining), 0.75, type + " active remaining")
		var idle: Dictionary = Arena.hazard_clock(h, 2.0)
		check(not bool(idle.active) and not bool(idle.warning), type + " idle phase")
		near(float(idle.remaining), 1.0, type + " time to warning")
		var warning: Dictionary = Arena.hazard_clock(h, 3.25)
		check(bool(warning.warning) and not bool(warning.active), type + " warning phase")
		near(float(warning.remaining), 0.75, type + " warning remaining")
		check(int(Arena.hazard_clock(h, 4.25).cycle) == 1, type + " cycle advances")

func haste_contract() -> void:
	var sim: BattleSim = fresh([hazard("haste", {"speedMultiplier": 1.25, "duration": 1.6, "refreshInterval": 0.5}), hazard("haste", {"id": "overlap", "speedMultiplier": 1.4})])
	var u: BUnit = sim.heroes[0]
	var base: float = sim.stat(u, BattleSim.S_MS)
	check(sim.env.benefit_at(u.pos, u) > 0.0, "haste opportunity before collection")
	at(sim, 0.0)
	near(sim.stat(u, BattleSim.S_MS), base * 1.4, "overlapping pads use strongest instead of stacking")
	var count: int = 0
	for buff in u.buffs:
		if buff.tag == "environment_haste": count += 1
	check(count == 1, "one environment speed buff per unit")
	for tick in 20:
		at(sim, float(tick) * BattleSim.DT)
	near(sim.stat(u, BattleSim.S_MS), base * 1.4, "standing on pad refreshes without compounding")
	near(sim.env.benefit_at(u.pos, u), 0.0, "active speed is not repeatedly valued as new benefit")
	sim.arena.hazards[1]["x"] = 1050.0
	sim.arena.hazards[1]["center"] = Vector2(1050, 400)
	at(sim, 1.1)
	near(sim.stat(u, BattleSim.S_MS), base * 1.25, "weaker pad cannot prolong departed stronger pad bonus")
	u.pos = Vector2(100, 100)
	at(sim, 3.0)
	near(sim.stat(u, BattleSim.S_MS), base, "speed expires after leaving pad")
	u.pos = Vector2(600, 400)
	at(sim, 4.0)
	sim.env.enabled = false
	near(sim.stat(u, BattleSim.S_MS), base, "debug disable removes remaining environment buff immediately")
	near(sim.env.benefit_at(u.pos, u), 0.0, "disabled pads offer no AI benefit")
	at(sim, 5.0)
	near(sim.stat(u, BattleSim.S_MS), base, "disabled environment does not refresh speed")
	sim.dispose()

func fountain_contract() -> void:
	var h: Dictionary = hazard("healing_fountain", {"healPercent": 0.16, "cooldown": 18.0})
	var sim: BattleSim = fresh([h], ["swordsman"], ["swordsman"])
	var a: BUnit = sim.heroes[0]
	var b: BUnit = sim.heroes[1]
	var hp: float = sim.max_hp(a)
	a.hp = hp * 0.6
	b.hp = hp * 0.3
	check(sim.env.public_fountains()[0].ready, "fountain starts ready")
	check(sim.env.benefit_at(b.pos, b) > sim.env.benefit_at(Vector2(100, 100), b), "AI values available healing position")
	at(sim, 0.0)
	near(a.hp, hp * 0.6, "shared fountain does not heal both teams")
	near(b.hp, hp * 0.46, "lowest health ratio receives fountain")
	near(float(sim.env.state_snapshot()[0].cooldown_remaining), 18.0, "fountain starts shared cooldown")
	check(not bool(sim.env.public_fountains()[0].ready), "public fountain becomes unavailable")
	near(sim.env.benefit_at(b.pos, b), 0.0, "AI does not value cooling fountain")
	at(sim, 17.99)
	near(b.hp, hp * 0.46, "cooldown prevents early use")
	at(sim, 18.0)
	near(b.hp, hp * 0.62, "cooldown reopens at exact deadline")
	a.hp = hp * 0.4
	b.hp = hp * 0.4
	sim.heroes.reverse()
	at(sim, 36.0)
	near(a.hp, hp * 0.56, "tie selects stable idx despite reversed hero array")
	near(b.hp, hp * 0.4, "tie consumes only one charge")
	var other: BattleSim = fresh([])
	other.arena = sim.arena
	check(other.env.public_fountains()[0].ready, "shared Arena carries no cooldown to another simulation")
	check(not sim.arena.hazards[0].has("ready_at"), "map definition has no mutable fountain ready time")
	other.dispose()
	sim.env.enabled = false
	check(not bool(sim.env.public_fountains()[0].ready), "disabled fountain is publicly unavailable")
	sim.dispose()
	var immune: BattleSim = fresh([h])
	var patient: BUnit = immune.heroes[0]
	patient.hp = immune.max_hp(patient) * 0.5
	immune.apply_status(patient, patient, {"status": "healReduction", "duration": 10.0, "magnitude": 0.5})
	var before: float = patient.hp
	at(immune, 0.1)
	near(patient.hp - before, immune.max_hp(patient) * 0.08, "fountain respects healing reduction")
	immune.dispose()
	var full: BattleSim = fresh([h])
	at(full, 0.1)
	check(full.env.public_fountains()[0].ready, "full-health units do not waste fountain charge")
	full.dispose()

func gravity_contract() -> void:
	var h: Dictionary = hazard("gravity", {"force": 150.0, "damage": 0.0})
	var sim: BattleSim = fresh([h])
	var u: BUnit = sim.heroes[0]
	u.pos = Vector2(740, 400)
	u.prev_pos = u.pos
	at(sim, 0.1)
	check(u.pos.x < 740.0 and u.pos.x > 600.0, "gravity pulls toward center")
	var before: Vector2 = u.pos
	at(sim, 3.4)
	check(u.pos == before, "warning is harmless before activation")
	check(sim.arena.hazard_penalty(Vector2(700, 400), 0.1) > sim.arena.hazard_penalty(Vector2(700, 400), 2.0), "AI recognizes active gravity risk")
	sim.arena.hazards[0]["damage"] = 6.0
	near(sim.arena.expected_hazard_damage(Vector2(700, 400), 2.0, 0.0, 0.1), 0.0, "AI predicts no gravity damage wholly inside idle phase")
	near(sim.arena.expected_hazard_damage(Vector2(700, 400), 0.0, 0.0, 1.0), 12.0, "AI gravity forecast integrates active tick intervals")
	sim.dispose()
	var wall: Dictionary = {"id": "wall", "shape": "rect", "x": 540.0, "y": 250.0, "w": 30.0, "h": 300.0}
	sim = fresh([hazard("gravity", {"x": 400.0, "radius": 500.0, "force": 10000.0})], ["swordsman"], ["archer"], [wall])
	u = sim.heroes[0]
	u.pos = Vector2(700, 400)
	u.prev_pos = u.pos
	at(sim, 0.1, 0.2)
	check(u.pos.x >= 570.0 + sim.radius(u) - 0.01, "large gravity displacement cannot tunnel through wall")
	check(not sim.arena.inside_obstacle(u.pos, sim.radius(u) - 0.02), "gravity leaves body outside obstacle")
	sim.dispose()
	sim = fresh([hazard("gravity", {"x": 300.0, "radius": 700.0, "force": 10000.0})], ["torturer"], ["archer"])
	var captive: BUnit = sim.heroes[1]
	captive.pos = Vector2(700, 400)
	captive.prev_pos = captive.pos
	sim.heroes[0].pos = Vector2(650, 400)
	sim.warfare._create_prison(sim.heroes[0], captive, {})
	at(sim, 0.1, 0.2)
	check(captive.pos.distance_to(Vector2(700, 400)) <= InformationWarfare.PRISON_RADIUS - sim.radius(captive) - 0.99, "gravity cannot pull captive through prison wall")
	sim.dispose()

func wave_contract() -> void:
	var h: Dictionary = hazard("shockwave", {"damage": 40.0, "school": "true", "ringWidth": 10.0})
	check(Arena.hazard_effect_contains(h, Vector2(650, 400), 0.25), "wave ring reaches radius 50 at quarter duration")
	check(not Arena.hazard_effect_contains(h, Vector2(750, 400), 0.25), "wave does not damage outer area early")
	check(not Arena.hazard_effect_contains(h, Vector2(600, 400), 0.75), "wave center becomes safe after ring passes")
	check(Arena.hazard_effect_contains(h, Vector2(740, 400), 0.75, 0.0, 0.65), "swept wave catches crossing between ticks")
	check(Arena.hazard_effect_contains(h, Vector2(780, 400), 0.5, 0.0, 0.49, Vector2(620, 400)), "wave catches moving unit crossing ring")
	var t0: float = 0.5
	var t1: float = t0 + BattleSim.DT
	var previous: Vector2 = Vector2(600.0 + 200.0 * t0 + 12.0, 400)
	var current: Vector2 = Vector2(600.0 + 200.0 * t1 + 12.0, 400)
	check(not Arena.hazard_effect_contains(h, current, t1, 5.0, t0, previous), "runner maintaining safe lead is not hit by independent swept ranges")
	check(Arena.hazard_effect_contains(h, Vector2(750, 400), 0.5, 0.0, 0.49, Vector2(450, 400)), "dash through ring center is detected with equal start and end radii")
	check(Arena.hazard_effect_contains(h, Vector2(800, 400), 1.01, 0.0, 0.99), "final partial activation slice reaches outer edge")
	check(not Arena.hazard_effect_contains(h, Vector2(800, 400), 4.01, 0.0, 3.99), "cycle restart does not retain old outer wave")
	var sim: BattleSim = fresh([h])
	var u: BUnit = sim.heroes[0]
	u.pos = Vector2(750, 400)
	u.prev_pos = u.pos
	var before: float = u.hp
	for tick in range(1, 34):
		at(sim, float(tick) * BattleSim.DT)
	near(before - u.hp, 40.0, "one hit per expanding-wave cycle")
	for tick in range(121, 154):
		at(sim, float(tick) * BattleSim.DT)
	near(before - u.hp, 80.0, "new cycle can hit same target again")
	near(sim.arena.expected_hazard_damage(Vector2(750, 400), 0.1, 0.0, 0.9), 40.0, "AI predicts one upcoming wave hit")
	near(sim.arena.expected_hazard_damage(Vector2(610, 400), 0.8, 0.0, 0.1), 0.0, "AI predicts no damage behind passed wave")
	near(sim.arena.expected_hazard_damage(Vector2(900, 400), 0.0, 0.0, 5.0), 0.0, "AI predicts no damage beyond wave radius")
	near(sim.arena.expected_hazard_damage(Vector2(750, 400), 0.1, 0.0, 5.0), 80.0, "AI counts separate cycles within horizon")
	check(sim.arena.hazard_penalty(Vector2(750, 400), 0.75) > 1.0, "active wave ring carries high path penalty")
	check(sim.arena.hazard_penalty(Vector2(802, 400), 0.99) > 1.0, "AI penalty includes outer half of rendered ring width")
	near(sim.arena.hazard_penalty(Vector2(610, 400), 0.8), 0.0, "passed ring does not falsely block safe interior")
	sim.dispose()

func portal_contract() -> void:
	var portals: Array = [hazard("portal", {"id": "a", "radius": 30.0, "pairId": "b", "cooldown": 3.2}),
		hazard("portal", {"id": "b", "x": 1100.0, "radius": 30.0, "pairId": "a", "cooldown": 2.35})]
	var sim: BattleSim = fresh(portals, ["torturer"], ["archer"])
	var captive: BUnit = sim.heroes[1]
	sim.heroes[0].pos = Vector2(530, 400)
	sim.warfare._create_prison(sim.heroes[0], captive, {})
	at(sim, 0.1)
	check(captive.pos.distance_to(Vector2(600, 400)) <= InformationWarfare.PRISON_RADIUS - sim.radius(captive) - 0.99, "environment portal respects prison before objectives update")
	near(captive.portal_until, 3.3, "environment portal uses authored cooldown")
	check(captive.prev_pos == captive.pos, "portal previous position uses final constrained location")
	sim.dispose()
	for status in [&"grounded", &"suppression"]:
		sim = fresh(portals)
		var u: BUnit = sim.heroes[0]
		sim.push_status(u, status, u.idx, 5.0)
		at(sim, 0.1)
		check(u.pos == Vector2(600, 400), str(status) + " blocks environment portal like skill portal")
		near(u.portal_until, 0.0, str(status) + " does not consume portal cooldown")
		sim.dispose()
	sim = fresh(portals)
	var u: BUnit = sim.heroes[0]
	at(sim, 0.0)
	near(u.portal_until, 3.2, "first portal endpoint cooldown")
	u.pos = Vector2(1100, 400)
	u.prev_pos = u.pos
	at(sim, 3.19)
	check(u.pos == Vector2(1100, 400), "portal cannot return before shared transit deadline")
	at(sim, 3.2)
	check(u.pos.distance_to(Vector2(600, 400)) < 100.0, "portal returns at cooldown boundary")
	near(u.portal_until, 5.55, "return endpoint applies its own cooldown")
	sim.dispose()

func protection_contract() -> void:
	for status in [&"invulnerable", &"untargetable", &"unstoppable"]:
		var sim: BattleSim = fresh([hazard("gravity", {"force": 150.0, "damage": 30.0, "school": "true"})])
		var u: BUnit = sim.heroes[0]
		u.pos = Vector2(730, 400)
		u.prev_pos = u.pos
		sim.push_status(u, status, u.idx, 3.0)
		var before: float = u.hp
		at(sim, 0.1)
		check(u.pos == Vector2(730, 400), str(status) + " prevents gravity displacement")
		near(before - u.hp, 30.0 if status == &"unstoppable" else 0.0, str(status) + " damage contract")
		sim.dispose()
	var sim: BattleSim = fresh([hazard("gravity", {"force": 150.0})], ["politician"], ["archer"])
	var u: BUnit = sim.heroes[0]
	u.pos = Vector2(730, 400)
	u.prev_pos = u.pos
	u.ks["contemplating"] = true
	u.ks["contemplation_pos"] = u.pos
	at(sim, 0.1)
	check(u.pos == Vector2(730, 400), "politician contemplation prevents environment displacement")
	u.chamber = "test_realm"
	u.ks["contemplating"] = false
	at(sim, 0.2)
	check(u.pos == Vector2(730, 400), "separate chamber is excluded from map effects")
	sim.dispose()
	for status in [&"invulnerable", &"untargetable", &"unstoppable"]:
		sim = fresh([hazard("shockwave", {"damage": 30.0, "school": "true", "knockback": 80.0})])
		u = sim.heroes[0]
		u.pos = Vector2(700, 400)
		u.prev_pos = u.pos
		sim.push_status(u, status, u.idx, 3.0)
		at(sim, 0.5)
		check(u.motion == null, str(status) + " prevents shockwave knockback")
		sim.dispose()

func determinism_and_public_state() -> void:
	var ids: Array = []
	for def in DB.characters:
		ids.append(def.id)
	check(ids.size() == 26, "all 26-character roster enumerated")
	var before: String = var_to_str(DB.arena("classic").data)
	var signatures: Array = []
	for run in 2:
		var result: Array = []
		for id in ids:
			var sim: BattleSim = fresh([hazard("haste"), hazard("healing_fountain"), hazard("shockwave", {"damage": 8.0, "school": "magic"})], [str(id)], ["archer"])
			var u: BUnit = sim.heroes[0]
			u.hp = sim.max_hp(u) * 0.6
			for tick in range(1, 46):
				sim.step()
			check(u.pos.is_finite() and is_finite(u.hp) and u.hp > 0.0, "character environment integration " + str(id) + " run " + str(run))
			result.append([str(id), u.hp, u.pos, sim.stat(u, BattleSim.S_MS), sim.env.state_snapshot()])
			for row in sim.env.state_snapshot():
				check(not row.has("occupants") and not row.has("target") and not row.has("health"), "public environment row contains no hidden unit data " + str(id) + " " + str(row.type))
			sim.dispose()
		signatures.append(var_to_str(result))
	check(signatures[0] == signatures[1], "all 26 character simulations reproduce exactly")
	check(before == var_to_str(DB.arena("classic").data), "private tests leave DB shared arena definition unchanged")
