extends SceneTree

var passed: int = 0
var failed: Array[String] = []
var metrics: Dictionary = {}
var coverage: Array = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed.append(label)
		push_error("AI_AUDIT_152 " + label)

func arena_fixture(id: String = "audit_private", obstacles: Array = []) -> Arena:
	return Arena.from_data({"id": id, "width": 1408, "height": 792,
		"bounds": {"minX": 40, "maxX": 1368, "minY": 40, "maxY": 752}, "obstacles": obstacles, "hazards": []})

func fixture(blue: Array, red: Array = ["archer"]) -> BattleSim:
	var sim: BattleSim = BattleSim.new({"blue": blue, "red": red, "arena_id": "classic", "seed": 152501, "max_time": 150.0})
	sim.arena = arena_fixture()
	for u in sim.heroes:
		u.pos = Vector2(450 + 220 * u.team, 390 + 80 * u.slot)
		u.prev_pos = u.pos
	sim.start()
	return sim

func brain_for(sim: BattleSim, team: int = 0) -> TacticianBrain:
	var b: TacticianBrain = TacticianBrain.new(sim, team)
	b.on_start(sim)
	return b

func candidates(b: TacticianBrain, u: BUnit) -> Array:
	var out: Array = []
	b._ability_candidates(u, b._ctx(u), out)
	return out

func has_slot(rows: Array, slot: int) -> bool:
	return rows.any(func(c: Dictionary): return int(c.cmd.get("index", -1)) == slot)

func _run() -> void:
	DB.ensure_loaded()
	if OS.get_cmdline_user_args().has("--matches"):
		_matches()
		return
	_navigation()
	_projectile_guard()
	_self_healing_mist()
	_support_coefficients()
	_memory_expiry()
	_roster_probe()
	_environment_planning()
	_fountain_reservation()
	_mode_fountains()
	_factory_and_map_search()
	_health_expiry()
	_deathmatch_information_boundary()
	var result: Dictionary = {"status": "PASS" if failed.is_empty() else "FAIL", "passed": passed,
		"failed": failed, "metrics": metrics, "coverage": coverage}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://reports/ai_audit_152"))
	var f: FileAccess = FileAccess.open("res://reports/ai_audit_152/audit.json", FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(result, "  "))
	print("AI_AUDIT_152 ", JSON.stringify({"status": result.status, "passed": passed, "failed": failed, "heroes": coverage.size()}))
	quit(0 if failed.is_empty() else 1)

func _navigation() -> void:
	var wall: Dictionary = {"id": "divider", "shape": "rect", "x": 680, "y": 240, "w": 48, "h": 300}
	var clear_arena: Arena = arena_fixture("same_id")
	var blocked_arena: Arena = arena_fixture("same_id", [wall])
	var left: Vector2 = Vector2(500, 390)
	var right: Vector2 = Vector2(900, 390)
	var n1: Navigator = Navigator.get_for(clear_arena, 17)
	var n2: Navigator = Navigator.get_for(blocked_arena, 17)
	check(n1 != n2 and n2.arena == blocked_arena, "same map ID with distinct geometry has isolated navigator")
	check(n2.next_waypoint(left, right, 17) != right, "custom obstacle is respected after cached empty map")
	var wide: Navigator = Navigator.get_for(blocked_arena, 51.0)
	check(wide.bucket >= 51.0, "large hero path grid covers its true body radius")
	Navigator.forget(clear_arena)
	Navigator.forget(blocked_arena)
	check(not Navigator._cache.values().has(n1) and not Navigator._cache.values().has(n2), "private arena navigator can be forgotten independently")

func _projectile_guard() -> void:
	var sim: BattleSim = fixture(["baseball"])
	var u: BUnit = sim.heroes[0]
	var b: TacticianBrain = brain_for(sim)
	b.intel.projectiles = [{"pos": u.pos + Vector2(160, 0), "vel": Vector2(-400, 0), "dmg": 120.0,
		"radius": 8.0, "homing": false, "target": -1, "explode": false, "cc": false}]
	b._danger_cache.clear()
	var rows: Array = candidates(b, u)
	check(has_slot(rows, 1), "baseball helmet becomes an actionable candidate for incoming projectile")
	var fired: bool = false
	for row: Dictionary in rows:
		if int(row.cmd.get("index", -1)) == 1:
			fired = sim.start_ability(u, 1, u, u.pos)
			break
	check(fired, "AI-generated helmet command is accepted by real simulator")
	for i in 12: sim.step()
	check(sim.get_buff(u, &"projectileGuard") != null, "AI-generated helmet produces actual projectile protection")
	b.dispose()
	sim.dispose()

func _roster_probe() -> void:
	var ability_count: int = 0
	for char_id: String in DB.ids():
		var d: Defs.CharDef = DB.char_def(char_id)
		check(not Doctrine.of(char_id).is_empty(), char_id + " has an explicit doctrine")
		var row: Dictionary = {"id": char_id, "name": d.name, "doctrine": str(Doctrine.of(char_id).get("title", "")), "abilities": []}
		for slot in d.abilities.size():
			ability_count += 1
			var scenario: SkillPreviewScenario = SkillPreviewScenario.new(char_id, "active:%d" % slot)
			scenario._main_due = 1000.0
			var a: Defs.AbilityDef = d.abilities[slot]
			var seconds: float = 10.0 if a.action in ["rootGarden", "thornGarden"] else 1.2
			for tick in int(seconds * 30): scenario.step()
			var sim: BattleSim = scenario.sim
			var u: BUnit = scenario.actor
			# Supply tactical opportunities, in addition to cast prerequisites:
			# interrupts need an actual windup, buffs need a suitable recipient,
			# wall-running needs a target down the wall, not away from it.
			if char_id == "werewolf" and slot == 2:
				sim.start_ability(scenario.target, 0, u, u.pos)
			if a.action in ["apple", "diversion"]:
				scenario.ally.def = DB.char_def("giant" if a.action == "diversion" else "swordsman")
				scenario.ally.hp = sim.max_hp(scenario.ally)
			if a.action == "wallRun":
				u.facing = Vector2.DOWN
				scenario.target.pos = u.pos + Vector2(0, 140)
				sim._update_visibility()
			if a.action == "glide":
				scenario.secondary.pos = Vector2(1200, 600)
				u.hp = sim.max_hp(u)
				sim._update_visibility()
			if a.action == "portalArming":
				u.resources["shards"] = 10.0
				# V1.5.3: arming is valued only for an allied shot that actually
				# crosses a portal toward an enemy; give the sniper that order.
				scenario.ally.command = {"kind": "basic", "target": scenario.target.idx}
			var b: TacticianBrain = brain_for(sim)
			if a.action in ["wallRun", "glide"]: b.plan.focus = scenario.target.idx
			if a.action == "rift":
				b.intel.projectiles = [{"pos": u.pos + Vector2(160, 0), "vel": Vector2(-400, 0), "dmg": 140.0,
					"radius": 8.0, "homing": false, "target": -1, "explode": false, "cc": false}]
				b._danger_cache.clear()
			var ctx: Dictionary = b._ctx(u)
			var rows: Array = candidates(b, u)
			Doctrine.adjust(b, u, ctx, rows)
			var chosen: Array = []
			for c: Dictionary in rows:
				var index: int = int(c.cmd.get("index", -1))
				check(index >= 0 and index < sim.ability_list(u).size() and is_finite(float(c.value)), char_id + " generated finite legal ability index")
				var ability: Defs.AbilityDef = sim.ability_list(u)[index]
				check(sim.ability_ready(u, index, ability), char_id + " only ready abilities enter candidates")
				if c.cmd.has("target"):
					var victim: BUnit = sim.u_at(int(c.cmd.target))
					check(victim != null and sim.target_legal(u, ability, victim) and sim.check_condition(u, victim, ability.condition), char_id + " obeys actual target conditions")
				if index == slot: chosen.append({"value": c.value, "notes": c.get("notes", []), "label": c.label})
			check(a.slot == slot + 1, char_id + " declared skill slot matches cooldown index")
			check(a.target in ["enemy", "self", "position", "ally", "position_ally"], char_id + " target dispatcher covers " + a.target)
			check(not chosen.is_empty(), "%s S%d enters the decision set when prerequisites and opportunity exist" % [char_id, slot + 1])
			row.abilities.append({"slot": slot + 1, "id": a.id, "name": a.name, "action": a.action,
				"conditions": a.condition, "ready": sim.ability_ready(u, slot, a), "candidate_count": chosen.size(), "candidates": chosen})
			u.cooldowns[slot] = sim.time + 100.0
			check(not has_slot(candidates(b, u), slot), "%s S%d is excluded during cooldown" % [char_id, slot + 1])
			b.dispose()
			scenario.dispose()
		coverage.append(row)
	check(coverage.size() == 26 and ability_count == 96, "all 26 heroes and 96 declared active skills audited")

func _environment_planning() -> void:
	var sim: BattleSim = fixture(["archer"])
	var data: Dictionary = arena_fixture().data.duplicate(true)
	data.hazards = [
		{"id": "gravity", "type": "gravity", "shape": "circle", "x": 450, "y": 390, "radius": 80, "period": 10, "activeDuration": 3, "warningDuration": 1},
		{"id": "fountain", "type": "healing_fountain", "shape": "circle", "x": 500, "y": 280, "radius": 42, "healPercent": 0.16, "cooldown": 18},
		{"id": "haste", "type": "haste", "shape": "circle", "x": 500, "y": 390, "radius": 38, "speedMultiplier": 1.25},
		{"id": "wave", "type": "shockwave", "shape": "circle", "x": 900, "y": 390, "radius": 160, "ringWidth": 22, "period": 10, "activeDuration": 2, "warningDuration": 1, "damage": 40}]
	sim.arena = Arena.from_data(data)
	var u: BUnit = sim.heroes[0]
	u.hp = sim.max_hp(u) * 0.45
	var b: TacticianBrain = brain_for(sim)
	b.eprof.clear()
	b.intel.entities.clear()
	b.intel.projectiles.clear()
	b.intel.telegraphs.clear()
	b.intel.zones.clear()
	b._danger_cache.clear()
	var enabled_danger: float = b.danger_at(u, u.pos)
	check(enabled_danger > 0.0, "non-damaging gravity contributes public movement risk")
	sim.env.enabled = false
	check(b.danger_at(u, u.pos) == 0.0, "same-tick developer gimmick toggle invalidates cached hazard risk")
	var pts: Array = []
	b._environment_move_points(u, b._ctx(u), pts)
	check(pts.is_empty(), "disabled gimmicks produce no benefit movement candidates")
	sim.env.enabled = true
	b.plan.front = u.pos + Vector2(300, 0)
	b._environment_move_points(u, b._ctx(u), pts)
	check(pts.any(func(p: Array): return str(p[1]) == "공용 회복샘 접근"), "injured elimination hero considers ready public fountain")
	check(pts.any(func(p: Array): return str(p[1]) == "가속 구역 경유"), "haste on the planned route becomes a movement opportunity")
	sim.env.cooldowns["fountain:fountain"] = sim.time + 18.0
	pts.clear()
	b._environment_move_points(u, b._ctx(u), pts)
	check(not pts.any(func(p: Array): return str(p[1]) == "공용 회복샘 접근"), "unavailable shared fountain is not chased")
	var wave_ahead: float = b.danger_at(u, Vector2(980, 390), 1.0)
	check(wave_ahead > 30.0, "expanding shockwave is anticipated before impact")
	b.dispose()
	sim.dispose()

func _fountain_reservation() -> void:
	var sim: BattleSim = fixture(["archer", "archer", "archer"])
	var data: Dictionary = arena_fixture("fountain_contention").data.duplicate(true)
	data.hazards = [{"id": "spring", "type": "healing_fountain", "shape": "circle", "x": 600.0, "y": 400.0,
		"radius": 40.0, "healPercent": 0.16, "cooldown": 18.0}]
	sim.arena = Arena.from_data(data)
	for u: BUnit in sim.heroes:
		u.pos = Vector2(350 + u.slot * 50, 300 + u.slot * 70) if u.team == 0 else Vector2(1300, 650)
		u.prev_pos = u.pos
		if u.team == 0: u.hp = sim.max_hp(u) * 0.3
	sim._update_visibility()
	var b: TacticianBrain = brain_for(sim)
	sim.controllers[0] = b
	for u: BUnit in sim.allies_of(0): b.decide(u)
	var arrivals: int = 0
	for u: BUnit in sim.allies_of(0):
		if str(u.command.get("fountain_id", "")) == "spring": arrivals += 1
	check(arrivals == 1 and b.fountain_reservations.size() == 1, "three injured elimination allies reserve one shared fountain for one mover")
	for tick in 10: sim.step()
	arrivals = 0
	for u: BUnit in sim.allies_of(0):
		if str(u.command.get("fountain_id", "")) == "spring": arrivals += 1
	check(arrivals == 1, "fountain reservation survives repeated actual decisions without allied crowding")
	var owner: BUnit = sim.u_at(int(b.fountain_reservations.spring.owner))
	owner.command = {"kind": "move", "goal": owner.pos}
	b._commit_decision(owner, {"cmd": owner.command}, b._ctx(owner))
	check(b.fountain_reservations.is_empty(), "changing the healing order releases shared fountain immediately")
	b.decide(owner)
	owner.alive = false
	b._prune_fountain_reservations()
	check(b.fountain_reservations.is_empty(), "dead owner does not retain shared fountain")
	owner.alive = true
	b.decide(owner)
	sim.env.cooldowns["fountain:spring"] = sim.time + 18.0
	b._prune_fountain_reservations()
	check(b.fountain_reservations.is_empty(), "public fountain cooldown releases its reservation")
	sim.env.cooldowns.clear()
	b.decide(owner)
	sim.env.enabled = false
	b._prune_fountain_reservations()
	check(b.fountain_reservations.is_empty(), "developer gimmick toggle releases fountain reservations")
	sim.dispose()

func _mode_fountains() -> void:
	var data: Dictionary = arena_fixture("mode_spring").data.duplicate(true)
	data.hazards = [{"id": "spring", "type": "healing_fountain", "shape": "circle", "x": 450.0, "y": 250.0,
		"radius": 40.0, "healPercent": 0.16, "cooldown": 18.0}]
	var sim: BattleSim = BattleSim.new({"ruleset": "control", "arena_id": DB.arenas_for("control")[0].id,
		"blue": ["archer", "mage", "politician"], "red": ["archer"], "seed": 152091})
	sim.arena = Arena.from_data(data)
	sim.domination.heal_zones.clear()
	for u: BUnit in sim.heroes:
		u.pos = Vector2(300, 200 + u.slot * 40) if u.team == 0 else Vector2(1300, 650)
		u.prev_pos = u.pos
		u.hp = sim.max_hp(u) * (0.2 + u.slot * 0.1)
	sim.start()
	var planner: ControlStrategy = ControlStrategy.new(sim, 0)
	var allies: Array[BUnit] = sim.allies_of(0)
	for u: BUnit in allies: planner.assignments[u.idx] = {"role": "점령", "goal": Vector2(800, 400)}
	planner._assign_healing(allies, 0.0)
	var receivers: int = 0
	for u: BUnit in allies:
		if str(planner.intent(u).get("heal_target", "")) == "spring": receivers += 1
	check(receivers == 1 and str(planner.intent(allies[0]).get("heal_target", "")) == "spring", "control reserves one public fountain for the most injured ally")
	sim.env.enabled = false
	for u: BUnit in allies: planner.assignments[u.idx] = {"role": "점령", "goal": Vector2(800, 400)}
	planner._assign_healing(allies, 0.0)
	check(not planner.assignments.values().any(func(a: Dictionary): return a.has("heal_target")), "control does not leave capture objectives for disabled fountains")
	planner.dispose()
	sim.dispose()
	var dm: BattleSim = BattleSim.new({"ruleset": "deathmatch", "arena_id": "dm_open_steppe", "players": ["archer", "mage"], "seed": 152092})
	dm.arena = Arena.from_data(data)
	dm.deathmatch.field.clear()
	dm.heroes[0].pos = Vector2(300, 250)
	dm.heroes[1].pos = Vector2(1300, 650)
	dm.heroes[0].hp = dm.max_hp(dm.heroes[0]) * 0.45
	dm.start()
	var b: DeathmatchBrain = DeathmatchBrain.new(dm, 0)
	b.on_start(dm)
	check(str(b.intent.mode) == "recover" and (b.intent.goal as Vector2).is_equal_approx(Vector2(450, 250)), "deathmatch selects ready public healing over unproductive idle recovery")
	dm.env.cooldowns["fountain:spring"] = dm.time + 18.0
	b._update_intent()
	check(not (b.intent.goal as Vector2).is_equal_approx(Vector2(450, 250)), "deathmatch abandons a fountain with a distant public cooldown")
	b.dispose()
	dm.dispose()

func _factory_and_map_search() -> void:
	var dm: BattleSim = BattleSim.new({"ruleset": "deathmatch", "arena_id": "dm_open_steppe", "players": ["mage", "archer"], "seed": 152003})
	for kind: String in ["tactician", "classic", "tactician14", "tactician{risk=0.8}"]:
		var brain: TeamController = AIFactory.make(kind, dm, 0)
		check(brain is DeathmatchBrain, "deathmatch retains its survival architecture for " + kind)
		if kind.contains("{"): check(is_equal_approx(float((brain as TacticianBrain).cfg.risk), 0.8), "deathmatch debug options are preserved")
		brain.dispose()
	dm.dispose()
	var sim: BattleSim = fixture(["archer"])
	sim.heroes[1].pos = Vector2(1280, 650)
	sim._update_visibility()
	sim.arena.spawns[1] = [Vector2(1200, 650), Vector2(1220, 630)]
	var simple: ClassicBrain = ClassicBrain.new(sim, 0)
	simple.decide(sim.heroes[0])
	check((sim.heroes[0].command.pos as Vector2).is_equal_approx(Vector2(1210, 640)), "classic scout uses this map's public spawn geometry")
	simple.dispose()
	sim.dispose()

func _matches() -> void:
	var rows: Array = []
	var roster: Dictionary = {}
	var ids: Array = DB.ids()
	var arena_ids: Dictionary = {"elimination": ["ruined_gate", "moon_garden", "twin_foundry"],
		"control": ["control_crossroads", "control_citadel", "control_conduits"], "deathmatch": DeathmatchMapData.ORDER}
	# Read the current catalogue rather than inventing an unavailable control ID.
	arena_ids.control = DB.arenas_for("control").map(func(a: Arena): return a.id)
	for mode: String in ["elimination", "control", "deathmatch"]:
		for case in 3:
			var chosen: Array = []
			for k in (8 if mode == "deathmatch" else 10): chosen.append(ids[(case * 8 + k) % ids.size()])
			var config: Dictionary = {"ruleset": mode, "arena_id": arena_ids[mode][case], "seed": 152901 + case * 113,
				"max_time": 60.0, "kill_target": 99, "players": chosen, "blue": chosen.slice(0, 5), "red": chosen.slice(5, 10)}
			var sim: BattleSim = BattleSim.new(config)
			for t in sim.team_count: sim.controllers[t] = AIFactory.make("tactician", sim, t)
			var distances: Dictionary = {}
			var tick_us: Array[int] = []
			var events: Dictionary = {}
			var invalid: String = ""
			var modes: Dictionary = {}
			var started: int = Time.get_ticks_usec()
			sim.start()
			while sim.state == BattleSim.RUNNING:
				var old_positions: Array = sim.heroes.map(func(u: BUnit): return u.pos)
				var t0: int = Time.get_ticks_usec()
				sim.step()
				tick_us.append(Time.get_ticks_usec() - t0)
				for ev: Dictionary in sim.tick_events: events[ev.type] = int(events.get(ev.type, 0)) + 1
				for u: BUnit in sim.heroes:
					distances[u.idx] = float(distances.get(u.idx, 0)) + u.pos.distance_to(old_positions[u.idx])
					if not u.pos.is_finite() or not u.vel.is_finite() or not is_finite(u.hp): invalid = "non-finite body " + u.def.id
					if u.hp < -0.001 or u.hp > sim.max_hp(u) + 0.01: invalid = "health bounds " + u.def.id
					if u.statuses.size() > 100 or u.buffs.size() > 200: invalid = "unbounded modifiers " + u.def.id
					if sim.tick % 30 == 0 and u.alive:
						var brain: TacticianBrain = sim.controllers[u.team]
						var stance: String = str(brain.plan.stance)
						if brain is DeathmatchBrain: stance = str((brain as DeathmatchBrain).intent.mode)
						modes[stance] = int(modes.get(stance, 0)) + 1
				if not invalid.is_empty() or sim.tick > 1810: break
			var elapsed: float = (Time.get_ticks_usec() - started) / 1000000.0
			check(invalid.is_empty() and sim.state == BattleSim.FINISHED, "%s seed %d terminates with finite bounded state" % [mode, config.seed])
			var heroes: Array = []
			for u: BUnit in sim.heroes:
				var brain: TacticianBrain = sim.controllers[u.team]
				var hero_row: Dictionary = {"id": u.def.id, "casts": u.st_casts, "damage": u.st_damage,
					"healing": u.st_healing, "distance": distances.get(u.idx, 0), "kills": u.st_kills, "decisions": brain.decisions_made}
				heroes.append(hero_row)
				roster[u.def.id] = true
				check(brain.decisions_made > 0 and float(distances.get(u.idx, 0)) > 20.0, mode + " " + u.def.id + " makes decisions and navigates")
			tick_us.sort()
			rows.append({"config": config, "winner": sim.winner, "duration": sim.time, "wall_seconds": elapsed,
				"p95_tick_ms": tick_us[int(tick_us.size() * 0.95)] / 1000.0, "max_tick_ms": tick_us.back() / 1000.0,
				"invariant_error": invalid, "events": events, "intent_samples": modes, "heroes": heroes})
			print("AI_MATCH_152 ", mode, " seed=", config.seed, " seconds=", sim.time, " wall=", snappedf(elapsed, 0.01))
			sim.dispose()
	check(roster.size() == 26 and rows.size() == 9, "nine live AI matches cover all 26 heroes and three modes")
	var hashes: Dictionary = {}
	for file: String in ["scripts/ai/ai_factory.gd", "scripts/ai/classic_brain.gd", "scripts/ai/control_strategy.gd", "scripts/ai/conquest_commander.gd", "scripts/ai/deathmatch_brain.gd", "scripts/ai/doctrine.gd", "scripts/ai/intel.gd", "scripts/ai/kit_model.gd", "scripts/ai/navigator.gd", "scripts/ai/tactician_brain.gd", "scripts/data/arena_data.gd", "scripts/data/control_arena_data.gd", "scripts/data/deathmatch_map_data.gd", "scripts/core/sim.gd", "scripts/core/arena.gd", "scripts/core/arena_env.gd"]:
		hashes[file] = FileAccess.get_sha256("res://" + file)
	var result: Dictionary = {"status": "PASS" if failed.is_empty() else "FAIL", "passed": passed, "failed": failed,
		"method": "Three fixed seeds per mode; complete matches at a 60-second test limit. Functional and runtime measurements, not a win-rate strength claim.",
		"matches": rows, "source_sha256": hashes, "roster": roster.keys()}
	var f: FileAccess = FileAccess.open("res://reports/ai_audit_152/matches.json", FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(result, "  "))
	print("AI_MATCHES_152 ", JSON.stringify({"status": result.status, "passed": passed, "failed": failed, "matches": rows.size(), "heroes": roster.size()}))
	quit(0 if failed.is_empty() else 1)

func _health_expiry() -> void:
	var sim: BattleSim = fixture(["fisherman"])
	var u: BUnit = sim.heroes[0]
	var base_hp: float = sim.max_hp(u)
	sim.add_buff(u, &"maxHealth", 0.1, 0.4, u.idx, {"tag": "fishHealth"})
	check(u.hp > base_hp and u.statuses.is_empty(), "fish health expiry fixture has temporary max HP and no status")
	for i in 18: sim.step()
	check(u.hp <= sim.max_hp(u) + 0.001, "max HP expiry clamps health even when status list is empty")
	sim.dispose()

func _deathmatch_information_boundary() -> void:
	var sims: Array[BattleSim] = []
	var brains: Array[DeathmatchBrain] = []
	for i in 2:
		var sim: BattleSim = BattleSim.new({"ruleset": "deathmatch", "arena_id": "dm_open_steppe", "players": ["archer", "mage", "politician"], "seed": 152088})
		sim.arena = arena_fixture("information_boundary")
		sim.deathmatch.field.clear()
		for u: BUnit in sim.heroes:
			u.pos = Vector2(100, 100) if u.team == 0 else Vector2(1200, 600 + u.team * 40)
			u.prev_pos = u.pos
		sim.start()
		var brain: DeathmatchBrain = DeathmatchBrain.new(sim, 0)
		brain.on_start(sim)
		sims.append(sim)
		brains.append(brain)
	var right: BattleSim = sims[1]
	right.heroes[1].pos = Vector2(1300, 600)
	right.heroes[1].hp = 31.0
	right.heroes[1].cooldowns.fill(99.0)
	right.heroes[2].resources["shards"] = 99.0
	right.deathmatch.inventory[1] = [ItemDefs.ORDER[0]]
	var signatures: Array = []
	for i in 2:
		var sim: BattleSim = sims[i]
		var b: DeathmatchBrain = brains[i]
		sim.time = 5.0
		sim.tick = 150
		sim._update_visibility()
		check(not sim.is_seen(0, sim.heroes[1]) and not sim.is_seen(0, sim.heroes[2]), "deathmatch boundary fixture remains outside vision")
		b.intel.observe()
		b._plan()
		b.decide(sim.heroes[0])
		signatures.append({"intent": b.intent, "command": sim.heroes[0].command,
			"belief_hp": b.intel.enemies[1].hp, "belief_pos": b.intel.enemies[1].pos, "ready": b.intel.ready_prob(b.intel.enemies[1], 0)})
	check(signatures[0] == signatures[1], "hidden deathmatch health position cooldown resource and inventory cannot change a decision")
	for b in brains: b.dispose()
	for sim in sims: sim.dispose()

func _self_healing_mist() -> void:
	var sim: BattleSim = fixture(["plague_doctor"])
	var u: BUnit = sim.heroes[0]
	u.hp = sim.max_hp(u) * 0.25
	u.resources["healBank"] = 350.0
	var b: TacticianBrain = brain_for(sim)
	var rows: Array = candidates(b, u)
	check(has_slot(rows, 1), "solo plague doctor can spend stored healing on self")
	var before: float = u.hp
	var fired: bool = false
	for row: Dictionary in rows:
		if int(row.cmd.get("index", -1)) == 1:
			fired = sim.start_ability(u, 1, null, row.cmd.pos)
			break
	check(fired, "AI-generated self healing mist command is accepted")
	for i in 45: sim.step()
	check(u.hp > before + 20.0 and float(u.resources.get("healBank", 0)) < 350, "AI self heal consumes bank and restores actual health")
	b.dispose()
	sim.dispose()

func _support_coefficients() -> void:
	var sim: BattleSim = fixture(["mage", "swordsman"])
	var u: BUnit = sim.heroes[0]
	var ally: BUnit = sim.heroes[1]
	ally.hp = 300
	sim.add_buff(u, &"abilityCoefficient", 0.30, 6.0, u.idx)
	var st: Dictionary = KitModel.stats_of_unit(sim, u)
	var heal: Dictionary = {"type": "heal", "base": 20, "ap": 0.5, "missingHp": 0.05}
	var shield: Dictionary = {"type": "shield", "base": 30, "ap": 0.7, "duration": 3}
	var estimate: Dictionary = KitModel.evaluate([heal, shield], st, {"hp": ally.hp, "max_hp": sim.max_hp(ally)})
	var actual_heal: float = float(sim.apply_heal(u, ally, heal).raw)
	var actual_shield: float = sim.apply_shield(u, ally, shield)
	check(is_equal_approx(float(estimate.heal), actual_heal), "healing model includes ability coefficient and target missing health")
	check(is_equal_approx(float(estimate.shield), actual_shield), "shield model agrees with buffed real simulator")
	var zone: Dictionary = KitModel.evaluate([{"type": "zone", "duration": 3, "interval": 1,
		"effects": [{"type": "status", "status": "root", "duration": 1.2}, shield], "filter": "enemy"}], st, {})
	check(float(zone.cc.get("root", 0)) > 0.0 and float(zone.shield) > 0.0, "nested zone retains control and protection channels")
	sim.dispose()

func _memory_expiry() -> void:
	var sim: BattleSim = fixture(["mage"])
	var u: BUnit = sim.heroes[0]
	var enemy: BUnit = sim.heroes[1]
	sim.apply_status(u, enemy, {"status": "root", "duration": 1.2})
	var intel: TeamIntel = TeamIntel.new(sim, 0)
	sim._update_visibility()
	intel.observe()
	var belief: TeamIntel.EnemyBelief = intel.enemies[enemy.idx]
	check(belief.hard_cc_remaining() > 1.0, "owned root duration is known from visible evidence")
	enemy.pos = Vector2(1280, 600)
	sim.time = 0.6
	sim._update_visibility()
	intel.observe()
	check(belief.hard_cc_remaining() < 0.7 and belief.hard_cc_remaining() > 0.0, "remembered CC duration ages after loss of vision")
	sim.time = 2.0
	intel.observe()
	check(not belief.has_status("root") and belief.hard_cc_remaining() == 0.0, "expired remembered control cannot create a permanent combo window")
	intel.dispose()
	sim.dispose()
