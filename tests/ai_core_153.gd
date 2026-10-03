extends SceneTree

# V1.5.3 core-AI regressions (audit_ai_core D1-D15, audit_heroes_a X1-X8,
# audit_heroes_b X2, audit_telemetry #1-#4). Every check below failed on the
# V1.5.2 brain and passes after the fix, unless marked "invariant".
# Run: godot --headless --path <tree> --script res://tests/ai_core_153.gd

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
		push_error("AI_CORE_153 " + label)

func arena(id: String, obstacles: Array = [], hazards: Array = []) -> Arena:
	return Arena.from_data({"id": id, "width": 1408, "height": 792,
		"bounds": {"minX": 40, "maxX": 1368, "minY": 40, "maxY": 752}, "obstacles": obstacles, "hazards": hazards})

# A battle on a private arena with explicit positions. Team 0 gets a fresh
# TacticianBrain (returned), team 1 stands still (no controller).
func battle(blue: Array, red: Array, spots: Array, obstacles: Array = [], hazards: Array = [], seed_v: int = 153301) -> BattleSim:
	var sim: BattleSim = BattleSim.new({"blue": blue, "red": red, "arena_id": "classic", "seed": seed_v, "max_time": 150.0})
	sim.arena = arena("core153_%d" % seed_v, obstacles, hazards)
	for i in sim.heroes.size():
		var u: BUnit = sim.heroes[i]
		u.pos = spots[i]
		u.prev_pos = u.pos
		u.spawn_pos = u.pos
		u.facing = Vector2.RIGHT if u.team == 0 else Vector2.LEFT
	sim.controllers[0] = TacticianBrain.new(sim, 0)
	sim.controllers[1] = null
	sim.start()
	return sim

func brain(sim: BattleSim) -> TacticianBrain:
	return sim.controllers[0]

func steps(sim: BattleSim, n: int) -> void:
	for i in n:
		sim.step()

func cands_of(b: TacticianBrain, u: BUnit) -> Array:
	b.intel.observe()
	b._plan()
	var ctx: Dictionary = b._ctx(u)
	var out: Array = []
	b._ability_candidates(u, ctx, out)
	b._basic_candidates(u, ctx, out)
	return out

func slot_rows(rows: Array, index: int, target: int = -2) -> Array:
	return rows.filter(func(c: Dictionary): return str(c.cmd.get("kind", "")) == "ability" and int(c.cmd.get("index", -1)) == index \
		and (target == -2 or int(c.cmd.get("target", -1)) == target))

func _run() -> void:
	DB.ensure_loaded()
	_own_sight_orders()
	_steer_regains_sight()
	_glide_steering()
	_skillshot_range()
	_dash_prediction()
	_projectile_paths()
	_silence_value()
	_landing_danger()
	_flat_bonus_hit_scaling()
	_cluster_hint()
	_disengage_window()
	_clock_rules()
	_emergency_and_dead_config()
	_hidden_readiness_floor()
	_classic_brain()
	_caches()
	_stuck_order_guard()
	_hazard_routing()
	_stalemate_scouting()
	_retreat_anchor_local()
	var result: Dictionary = {"status": "PASS" if failed.is_empty() else "FAIL", "passed": passed, "failed": failed, "metrics": metrics}
	print("AI_CORE_153 ", JSON.stringify(result))
	quit(0 if failed.is_empty() else 1)

# ------------------------------------------------------------------ D1 / X1
const WALL: = {"id": "w", "shape": "rect", "x": 640, "y": 150, "w": 60, "h": 500}

func _own_sight_orders() -> void:
	for hero: String in ["fisherman", "swordsman", "archer"]:
		# Hero behind a wall; the allied archer sees a passive giant.
		var sim: BattleSim = battle([hero, "archer"], ["giant"], [Vector2(560, 400), Vector2(900, 180), Vector2(790, 400)], [WALL])
		var b: TacticianBrain = brain(sim)
		var h: BUnit = sim.heroes[0]
		var foe: BUnit = sim.heroes[2]
		steps(sim, 1)
		check(sim.is_seen(0, foe) and not sim.observes(h, foe), hero + " fixture: team sees the giant, the hero does not")
		var rows: Array = cands_of(b, h)
		var ctx: Dictionary = b._ctx(h)
		check((ctx.targets as Array).any(func(e): return (e as TeamIntel.EnemyBelief).idx == foe.idx) \
			and not (ctx.strike as Array).any(func(e): return (e as TeamIntel.EnemyBelief).idx == foe.idx), hero + " strike list is this hero's own sight")
		check(not rows.any(func(c: Dictionary): return int(c.cmd.get("target", -1)) == foe.idx), hero + " issues no attack order on an enemy only an ally sees")
		var moves: Array = []
		b._move_candidates(h, ctx, moves)
		var peek: Array = moves.filter(func(c: Dictionary): return str(c.label) == "시야 확보")
		check(not peek.is_empty() and sim.arena.line_of_sight(peek[0].cmd.goal, foe.pos, 3.0), hero + " gets a move point that opens a line of sight")
		var d0: int = h.decisions
		var start: Vector2 = h.pos
		var voided: int = 0
		for i in 90:
			sim.step()
			if h.command.is_empty() and h.action == null:
				voided += 1
		metrics["sight_" + hero] = {"decisions": h.decisions - d0, "moved": snappedf(h.pos.distance_to(start), 0.1), "voided_ticks": voided}
		check(h.decisions - d0 <= 30, hero + " does not re-decide every tick behind the wall (%d decisions)" % (h.decisions - d0))
		check(h.pos.distance_to(start) >= 100.0, hero + " walks to regain sight (%.0f px)" % h.pos.distance_to(start))
		check(voided <= 3, hero + " orders are not voided by the executor (%d ticks)" % voided)
		sim.dispose()

func _steer_regains_sight() -> void:
	var sim: BattleSim = battle(["archer", "sniper"], ["mage"], [Vector2(560, 400), Vector2(730, 640), Vector2(830, 400)],
		[{"id": "w", "shape": "rect", "x": 700, "y": 300, "w": 30, "h": 200}])
	var b: TacticianBrain = brain(sim)
	var h: BUnit = sim.heroes[0]
	var e: BUnit = sim.heroes[2]
	steps(sim, 2)
	b.intel.observe()
	check(sim.is_seen(0, e) and not sim.observes(h, e), "steer fixture: enemy seen by ally only")
	h.command = {"kind": "ability", "index": 1, "ability_id": h.def.abilities[1].id, "target": e.idx, "pos": e.pos, "need": 400.0}
	check(b.steer(h).length() > 0.2, "steer walks toward an unobserved enemy target instead of holding")
	h.command = {}
	b.steer(h)
	check(h.command.is_empty(), "steer writes nothing into an order the executor voided (D14)")
	sim.dispose()

# ------------------------------------------------------------------- D10
func _glide_steering() -> void:
	var sim: BattleSim = battle(["metatron"], ["archer"], [Vector2(500, 400), Vector2(760, 520)])
	var b: TacticianBrain = brain(sim)
	var mt: BUnit = sim.heroes[0]
	var foe: BUnit = sim.heroes[1]
	steps(sim, 2)
	b.intel.observe()
	b._plan()
	b.plan.focus = foe.idx
	var ctx: Dictionary = b._ctx(mt)
	var gi: int = -1
	for i in mt.def.abilities.size():
		if mt.def.abilities[i].action == "glide":
			gi = i
	check(gi >= 0, "glide fixture: metatron has a glide ability")
	b._commit_decision(mt, {"key": "glide", "value": 1.0, "parts": {}, "cmd": {"kind": "ability", "index": gi, "ability_id": mt.def.abilities[gi].id, "pos": mt.pos, "need": 0.0}}, ctx)
	check(int(b._glide_to.get(mt.idx, -1)) == foe.idx, "a glide order remembers the enemy it is launched at")
	# Mid-glide with an unrelated move order: steering still flies at the target.
	mt.ks["glide_until"] = sim.time + 1.0
	mt.command = {"kind": "move", "goal": mt.pos + Vector2(-200, 0)}
	var toward: Vector2 = (foe.pos - mt.pos).normalized()
	check(b.steer(mt).normalized().dot(toward) > 0.8, "steer follows the glide target while the glide lasts")
	mt.ks["glide_until"] = sim.time - 0.1
	check(b.steer(mt).normalized().dot(toward) < 0.0, "invariant: after the glide, the move order steers again")
	sim.dispose()
	_glide_planned_target()

# Review 1.5.3 (tactician_brain.gd:4420): the glide candidate planned its
# landing on one enemy (mem.glide_target) while _commit_decision launched the
# glide at the team focus, and steer() flew at the focus's raw position. One
# target now: the planned one, aimed at its predicted landing position.
func _glide_planned_target() -> void:
	var sim: BattleSim = battle(["metatron"], ["archer", "mage"], [Vector2(500, 400), Vector2(760, 520), Vector2(700, 230)])
	var b: TacticianBrain = brain(sim)
	var mt: BUnit = sim.heroes[0]
	var focus: BUnit = sim.heroes[1]
	var planned: BUnit = sim.heroes[2]
	steps(sim, 2)
	b.intel.observe()
	b._plan()
	b.plan.focus = focus.idx
	var ctx: Dictionary = b._ctx(mt)
	var gi: int = -1
	for i in mt.def.abilities.size():
		if mt.def.abilities[i].action == "glide":
			gi = i
	b.mem[mt.idx] = {"glide_target": planned.idx}
	b._commit_decision(mt, {"key": "glide", "value": 1.0, "parts": {}, "cmd": {"kind": "ability", "index": gi, "ability_id": mt.def.abilities[gi].id, "pos": mt.pos, "need": 0.0}}, ctx)
	check(int(b._glide_to.get(mt.idx, -1)) == planned.idx, "the glide flies at the enemy its landing was planned on, not the team focus (%d)" % int(b._glide_to.get(mt.idx, -1)))
	# Refreshed prediction: a target running south is led, not chased.
	mt.ks["glide_until"] = sim.time + 1.0
	mt.command = {"kind": "move", "goal": mt.pos + Vector2(-200, 0)}
	var eb: TeamIntel.EnemyBelief = b.intel.enemies[planned.idx]
	eb.vel = Vector2(0, 160)
	var lead: Vector2 = b.lead_point(mt.pos, eb, 0.0, 1.0, 0.8)
	var dir: Vector2 = b.steer(mt).normalized()
	check(lead.distance_to(eb.pos) > 60.0 and dir.dot((lead - mt.pos).normalized()) > 0.97 and dir.dot((lead - mt.pos).normalized()) > dir.dot((eb.pos - mt.pos).normalized()),
		"steer aims the glide at the planned target's predicted landing position")
	# A lost target (dead) is replaced by the doctrine at the next decision.
	eb.dead = true
	check(b.has_method("_glide_target") and b.call("_glide_target", mt) == null, "a dead glide target is dropped")
	eb.dead = false
	sim.dispose()

# ------------------------------------------------------------ telemetry #3
func _skillshot_range() -> void:
	var sim: BattleSim = battle(["mage"], ["giant"], [Vector2(400, 400), Vector2(806, 400)])
	var b: TacticianBrain = brain(sim)
	var m: BUnit = sim.heroes[0]
	var g: BUnit = sim.heroes[1]
	steps(sim, 2)
	for i in range(1, m.cooldowns.size()):
		m.cooldowns[i] = sim.time + 99.0
	var a: Defs.AbilityDef = m.def.abilities[0]
	var reach: float = a.range + sim.radius(m)
	var rows: Array = slot_rows(cands_of(b, m), 0, g.idx)
	check(not rows.is_empty(), "out-of-range skillshot stays a candidate (approach)")
	if rows.is_empty():
		sim.dispose()
		return
	var aim: Vector2 = rows[0].cmd.pos
	check(aim.distance_to(m.pos) > reach + 8.0, "out-of-range skillshot keeps its true aim instead of max range")
	check(b.refine_aim(m, a, g, aim).distance_to(m.pos) > reach + 8.0, "refine_aim makes the executor wait while out of reach")
	# Execute exactly this order (no re-decisions): the executor must wait and
	# steer must close in; the V1.5.2 brain fired at once from 406 px.
	m.command = rows[0].cmd.duplicate()
	m.next_decision_at = 999.0
	var cast_at: float = -1.0
	for i in 180:
		sim.step()
		for ev: Dictionary in sim.tick_events:
			if cast_at < 0.0 and str(ev.type) == "CAST_STARTED" and int(ev.get("s", -1)) == m.idx and int(ev.get("slot", 0)) == 1:
				cast_at = (ev.get("from", m.pos) as Vector2).distance_to(g.pos)
		if cast_at >= 0.0:
			break
	metrics["skillshot_cast_distance"] = cast_at
	check(cast_at >= 0.0 and cast_at <= reach + sim.radius(g) + 8.0, "skillshot fires only once the target is in reach (%.0f)" % cast_at)
	sim.dispose()

# -------------------------------------------------------------- X2 (dashes)
func _dash_prediction() -> void:
	var pillar: Dictionary = {"id": "p", "shape": "rect", "x": 660, "y": 330, "w": 60, "h": 60}
	var sim: BattleSim = battle(["swordsman"], ["mage"], [Vector2(600, 400), Vector2(740, 404)], [pillar])
	var b: TacticianBrain = brain(sim)
	var sw: BUnit = sim.heroes[0]
	var mg: BUnit = sim.heroes[1]
	steps(sim, 2)
	check(sim.observes(sw, mg) and sim.arena.segment_blocked(sw.pos, mg.pos, sim.radius(sw), Arena.MASK_UNITS), "corner fixture: eye line clear, body corridor blocked")
	check(slot_rows(cands_of(b, sw), 0, mg.idx).is_empty(), "contact dash is not proposed through a blocked body corridor")
	sim.dispose()
	var sim2: BattleSim = battle(["werewolf"], ["sniper"], [Vector2(420, 400), Vector2(625, 400)])
	var b2: TacticianBrain = brain(sim2)
	var ww: BUnit = sim2.heroes[0]
	var sn: BUnit = sim2.heroes[1]
	steps(sim2, 2)
	b2.intel.observe()
	var belief: TeamIntel.EnemyBelief = b2.intel.enemies[sn.idx]
	var s4: Defs.AbilityDef = ww.def.abilities[3]
	var limit: float = s4.range + sim2.radius(ww) + 8.0
	belief.vel = Vector2(94.0, 0.0)
	check(b2.refine_aim(ww, s4, sn, sn.pos).distance_to(ww.pos) > limit, "dash waits when the fleeing target will be out of reach at contact")
	belief.vel = Vector2.ZERO
	check(b2.refine_aim(ww, s4, sn, sn.pos).distance_to(ww.pos) <= limit, "invariant: dash fires at a standing target in reach")
	sim2.dispose()

# -------------------------------------------------------- X3 / B-X2 (paths)
func _projectile_paths() -> void:
	# The pillar clears the eye line by 6.5 px but not a 12 px homing shot.
	var corner: Dictionary = {"id": "c", "shape": "rect", "x": 590, "y": 380, "w": 20, "h": 13.5}
	var sim: BattleSim = battle(["mage"], ["archer"], [Vector2(500, 400), Vector2(700, 400)], [corner])
	var b: TacticianBrain = brain(sim)
	var m: BUnit = sim.heroes[0]
	var ar: BUnit = sim.heroes[1]
	steps(sim, 2)
	check(sim.observes(m, ar), "homing fixture: the mage sees its target")
	check(slot_rows(cands_of(b, m), 2, ar.idx).is_empty(), "homing shot is not cast into a wall on its path")
	sim.dispose()
	# An enemy body in front of the intended target takes the knife.
	var sim2: BattleSim = battle(["joker"], ["archer", "giant"], [Vector2(480, 400), Vector2(700, 400), Vector2(590, 404)])
	var b2: TacticianBrain = brain(sim2)
	var jk: BUnit = sim2.heroes[0]
	steps(sim2, 2)
	var rows: Array = slot_rows(cands_of(b2, jk), 0, sim2.heroes[1].idx)
	check(not rows.is_empty() and str(rows[0].label).contains("선행 피격"), "projectile value is scored on the first body it will hit")
	sim2.dispose()
	# Position-targeted blast behind a wall detonates on the wall: no candidate.
	var sim3: BattleSim = battle(["giant", "archer"], ["mage", "sniper"], [Vector2(560, 400), Vector2(720, 620), Vector2(810, 390), Vector2(820, 440)],
		[{"id": "w", "shape": "rect", "x": 700, "y": 300, "w": 30, "h": 200}])
	var b3: TacticianBrain = brain(sim3)
	steps(sim3, 2)
	check(slot_rows(cands_of(b3, sim3.heroes[0]), 2).is_empty(), "thrown blast is not valued where a wall stops it")
	sim3.dispose()

# ----------------------------------------------------------------------- X4
func _silence_value() -> void:
	var sim: BattleSim = battle(["werewolf"], ["mage", "archer"], [Vector2(600, 400), Vector2(670, 390), Vector2(660, 460)])
	var b: TacticianBrain = brain(sim)
	var ww: BUnit = sim.heroes[0]
	steps(sim, 3)
	check(not slot_rows(cands_of(b, ww), 2).is_empty(), "silence roar is valued by expected enemy casts, not only mid-cast")
	sim.dispose()

# ----------------------------------------------------------------------- X5
func _landing_danger() -> void:
	var sim: BattleSim = battle(["pirate", "archer"], ["mage", "werewolf", "giant"],
		[Vector2(500, 400), Vector2(380, 430), Vector2(770, 400), Vector2(820, 350), Vector2(830, 455)])
	var b: TacticianBrain = brain(sim)
	var pi: BUnit = sim.heroes[0]
	pi.hp = sim.max_hp(pi) * 0.35
	steps(sim, 3)
	pi.cooldowns[0] = sim.time + 30.0
	pi.cooldowns[2] = sim.time + 30.0
	pi.cooldowns[3] = sim.time + 30.0
	var rows: Array = slot_rows(cands_of(b, pi), 1, sim.heroes[2].idx)
	check(not rows.is_empty() and float(rows[0].value) < 0.0, "grapple into two enemies at 35%% HP prices the landing danger (%s)" % str(rows.map(func(c): return snappedf(float(c.value), 0.1))))
	sim.dispose()
	var sim2: BattleSim = battle(["swordsman"], ["archer"], [Vector2(600, 400), Vector2(800, 400)])
	var b2: TacticianBrain = brain(sim2)
	steps(sim2, 2)
	b2.intel.observe()
	var e: TeamIntel.EnemyBelief = b2.intel.enemies[sim2.heroes[1].idx]
	var land: Vector2 = b2._landing_point(sim2.heroes[0], sim2.heroes[0].def.abilities[3], e, e.pos, sim2.radius(sim2.heroes[0]))
	check(land.is_finite() and (land - e.pos).dot(e.pos - sim2.heroes[0].pos) > 0.0, "behind-target blink lands behind the target")
	sim2.dispose()

# ----------------------------------------------------------------------- D6
func _flat_bonus_hit_scaling() -> void:
	var sim: BattleSim = battle(["swordsman"], ["mage"], [Vector2(500, 400), Vector2(700, 400)])
	var b: TacticianBrain = brain(sim)
	var sw: BUnit = sim.heroes[0]
	steps(sim, 2)
	b.intel.observe()
	b._plan()
	var ctx: Dictionary = b._ctx(sw)
	var e: TeamIntel.EnemyBelief = b.intel.enemies[sim.heroes[1].idx]
	e.casting = {"slot": 1, "until": sim.time + 0.3}
	var s3: Defs.AbilityDef = sw.def.abilities[2]
	var low: float = float(b._enemy_value(sw, s3, e, ctx, 0.1).cc)
	var high: float = float(b._enemy_value(sw, s3, e, ctx, 0.9).cc)
	check(high > 0.0 and low <= high * 0.2, "flat silence bonuses scale with hit chance (%.1f vs %.1f)" % [low, high])
	sim.dispose()

# ----------------------------------------------------------------------- X8
func _cluster_hint() -> void:
	var sim: BattleSim = battle(["plague_doctor"], ["mage", "archer"], [Vector2(500, 400), Vector2(640, 400), Vector2(650, 425)])
	var b: TacticianBrain = brain(sim)
	var pd: BUnit = sim.heroes[0]
	steps(sim, 2)
	var mg: int = sim.heroes[1].idx
	var both: Array = slot_rows(cands_of(b, pd), 0, mg)
	var ctx: Dictionary = b._ctx(pd)
	var primary: TeamIntel.EnemyBelief = b.intel.enemies[mg]
	var a: Defs.AbilityDef = pd.def.abilities[0]
	# Review 1.5.3 (tactician_brain.gd:2089): a cone's extra victims are valued
	# once, in _special_enemy (LOS, own hit chance); the cluster hint no longer
	# adds them a second time (plague S1 counted each 1.31x, swordsman S2 1.15x).
	var bonus: float = b._cluster_bonus(pd, a, primary.pos, primary, ctx)
	var sec: TeamIntel.EnemyBelief = b.intel.enemies[sim.heroes[2].idx]
	var aim: Vector2 = both[0].cmd.pos if not both.is_empty() else primary.pos
	var hp: float = b._hit_prob(pd, a, primary, aim)
	var ev: Dictionary = b._enemy_value(pd, a, primary, ctx, hp)
	var cone_part: float = b._special_enemy(pd, 0, a, primary, aim, ctx, ev) * clampf(hp / maxf(0.05, KitModel.delivery_hit(a)), 0.0, 1.0)
	var once: float = float(b._enemy_value(pd, a, sec, ctx, b._hit_prob(pd, a, sec, b.lead_point(pd.pos, sec, 0.0, a.cast_time, 0.8))).value)
	metrics["cone_second_enemy"] = {"cone_block": snappedf(cone_part, 0.1), "cluster": snappedf(bonus, 0.1), "once": snappedf(once, 0.1)}
	check(not both.is_empty() and cone_part > 0.0 and is_zero_approx(bonus), "a cone counts its second enemy in the cone block only, not again via ai.cluster (cluster %.1f)" % bonus)
	check(cone_part + bonus <= once + 0.5, "a second enemy in the cone is counted at most once (%.1f vs %.1f)" % [cone_part + bonus, once])
	sec.pos = Vector2(1200, 700)
	check(is_zero_approx(b._cluster_bonus(pd, a, primary.pos, primary, b._ctx(pd))), "invariant: no cluster bonus without a second enemy in the cone")
	sim.dispose()

# ----------------------------------------------------------------------- D3
func _disengage_window() -> void:
	var sim: BattleSim = BattleSim.new({"blue": ["archer"], "red": ["giant", "werewolf", "swordsman", "baseball", "nitro"], "arena_id": "classic", "seed": 153902, "max_time": 480.0})
	sim.arena = arena("core153_stance")
	sim.heroes[0].pos = Vector2(400, 400)
	for i in range(1, 6):
		sim.heroes[i].pos = Vector2(760, 240 + 70 * i)
	for u in sim.heroes:
		u.prev_pos = u.pos
	sim.start()
	var b: TacticianBrain = TacticianBrain.new(sim, 0)
	b.on_start(sim)
	var runs: Array = []
	var last: String = ""
	var since: float = 0.0
	for k in 100:
		sim.time += 0.25
		sim._update_visibility()
		b.intel.observe()
		b._plan()
		var st: String = str(b.plan.stance)
		if st != last:
			if last != "":
				runs.append([last, sim.time - since])
			last = st
			since = sim.time
	var poke: float = 0.0
	for r in runs:
		if str(r[0]) == "POKE":
			poke = maxf(poke, float(r[1]))
	metrics["disengage_poke_window"] = poke
	check(poke >= 3.5, "fruitless retreat turns into a real 4 s poke window (%.2f s)" % poke)
	b.dispose()
	sim.dispose()

# ------------------------------------------------------------- D4 / DM-5
func _clock_rules() -> void:
	var sim: BattleSim = BattleSim.new({"ruleset": "control", "arena_id": DB.arenas_for("control")[0].id, "seed": 153907, "max_time": 480.0,
		"blue": ["archer", "mage", "giant"], "red": ["swordsman", "werewolf", "baseball"]})
	sim.start()
	var ahead: TacticianBrain = TacticianBrain.new(sim, 0)
	ahead.on_start(sim)
	var behind: TacticianBrain = TacticianBrain.new(sim, 1)
	behind.on_start(sim)
	for u in sim.heroes:
		u.pos = Vector2(600 + 120 * u.team, 300 + 60 * u.slot)
		u.prev_pos = u.pos
		if u.team == 0:
			u.hp = sim.max_hp(u) * 0.45
	sim.time = 462.0
	sim.domination.scores = [float(sim.domination.target_score) * 0.9, float(sim.domination.target_score) * 0.2]
	sim._update_visibility()
	for b: TacticianBrain in [ahead, behind]:
		b.intel.observe()
		b._plan()
	check(str(ahead.plan.stance) == "POKE", "control endgame: leading on score (behind on health) keeps a safe poke, got " + str(ahead.plan.stance))
	check(str(behind.plan.stance) == "ENGAGE", "control endgame: trailing on score (ahead on health) commits, got " + str(behind.plan.stance))
	ahead.dispose()
	behind.dispose()
	sim.dispose()
	var dm: BattleSim = BattleSim.new({"ruleset": "deathmatch", "arena_id": "dm_open_steppe", "players": ["archer", "mage", "giant"], "seed": 153908, "max_time": 150.0})
	dm.arena = arena("core153_dm")
	dm.deathmatch.field.clear()
	for u: BUnit in dm.heroes:
		u.pos = Vector2(500 + 90 * u.team, 400)
		u.prev_pos = u.pos
	dm.start()
	var d: DeathmatchBrain = DeathmatchBrain.new(dm, 0)
	d.on_start(dm)
	dm.time = dm.max_time - 10.0
	dm._update_visibility()
	d.intel.observe()
	d._plan()
	check(not str(d.plan.get("why", "")).contains("시간 판정"), "deathmatch ignores the team time-limit stance rule (DM-5)")
	d.dispose()
	dm.dispose()

# ------------------------------------------------------------------- D11
func _emergency_and_dead_config() -> void:
	var sim: BattleSim = battle(["mage"], ["archer"], [Vector2(500, 400), Vector2(760, 400)])
	var b: TacticianBrain = brain(sim)
	var m: BUnit = sim.heroes[0]
	steps(sim, 2)
	m.hp = 150.0
	check(sim.start_ability(m, 0, sim.heroes[1], sim.heroes[1].pos), "emergency fixture: a wind-up is in progress")
	b.intel.projectiles = [{"pos": m.pos + Vector2(60, 0), "vel": Vector2(-400, 0), "dmg": 200.0, "radius": 8.0, "homing": false,
		"target": -1, "explode": false, "cc": false}]
	check(not b.emergency(m), "the brain never cancels its own wind-up (the cooldown would be lost)")
	check(not b.cfg.has("hunt"), "dead cfg.hunt option removed")
	sim.dispose()

# ------------------------------------------------------------------- D12
func _hidden_readiness_floor() -> void:
	var sim: BattleSim = battle(["archer"], ["mage"], [Vector2(150, 150), Vector2(1250, 650)])
	var b: TacticianBrain = brain(sim)
	var e: BUnit = sim.heroes[1]
	sim.time = 40.0
	sim.tick = 1200
	sim._update_visibility()
	b.intel.observe()
	var belief: TeamIntel.EnemyBelief = b.intel.enemies[e.idx]
	check(not belief.visible, "floor fixture: enemy hidden for a long time")
	var raw: float = b.intel.ready_prob(belief, 0)
	b._plan()
	var p: float = 0.0
	for row: Dictionary in b.eprof[e.idx].abilities:
		if int(row.slot) == 1:
			p = float(row.p)
	metrics["hidden_ready"] = {"raw": raw, "profile": p}
	check(raw < 0.3 and p >= 0.6 - 0.001, "two-team hidden enemy keeps a readiness floor (raw %.2f, profile %.2f)" % [raw, p])
	var dm_profile: Dictionary = KitModel.enemy_profile(b.intel, belief, 0.0)
	check(is_equal_approx(float(dm_profile.abilities[0].p), raw), "invariant: no floor when disabled (deathmatch)")
	sim.dispose()

# ------------------------------------------------------------------- D15
func _classic_brain() -> void:
	var sim: BattleSim = battle(["fisherman", "archer"], ["giant"], [Vector2(560, 400), Vector2(900, 180), Vector2(790, 400)], [WALL])
	var simple: ClassicBrain = ClassicBrain.new(sim, 0)
	var h: BUnit = sim.heroes[0]
	var foe: BUnit = sim.heroes[2]
	sim._update_visibility()
	simple.decide(h)
	check(str(h.command.get("kind", "")) == "move" and int(h.command.get("target", -1)) != foe.idx, "classic AI does not order attacks on enemies only an ally sees")
	sim.tick = 3
	simple.pre_tick(sim)
	check(simple.last_seen.has(foe.idx), "classic AI remembers a seen enemy")
	foe.pos = Vector2(1300, 700)
	sim.time += 7.0
	sim.tick = 300
	sim._update_visibility()
	simple.pre_tick(sim)
	check(not simple.last_seen.has(foe.idx), "classic AI forgets sightings older than 6 s")
	simple.dispose()
	sim.dispose()
	_classic_links_switched_off()
	_nominal_damage_pure()

# Review 1.5.3 (team_controller.gd:39): the classic AI routed into portals and
# jump pads whose type (or the whole environment) was switched off, so the
# trigger never fired and every hero circled the pad until the time limit.
func _classic_links_switched_off() -> void:
	for mode: String in ["env_off", "pad_off"]:
		var sim: BattleSim = BattleSim.new({"ruleset": "elimination", "arena_id": "gale_corridor", "seed": 7, "max_time": 60.0,
			"blue": ["politician", "werewolf", "baseball"], "red": ["hive_mind", "torturer", "mage"]})
		for t in sim.team_count:
			sim.controllers[t] = AIFactory.make("classic", sim, t)
		sim.start()
		if mode == "env_off":
			sim.env.enabled = false
		else:
			sim.env.set_type_enabled("jump_pad", false)
		var first: float = -1.0
		var jumps: int = 0
		while sim.state == BattleSim.RUNNING and first < 0.0:
			sim.step()
			for ev: Dictionary in sim.tick_events:
				if str(ev.type) == "HEALTH_DAMAGED":
					first = sim.time
				elif str(ev.type) == "ENV_JUMP":
					jumps += 1
		metrics["classic_gale_" + mode + "_first_hit"] = snappedf(first, 0.1)
		check(first >= 0.0 and first < 60.0 and jumps == 0, "classic AI with %s fights instead of parking on the inert pad (first hit %.1f s)" % [mode, first])
		sim.dispose()
	# Lab switch tactician{glk=0}: geometric link routing still respects the
	# environment switch (walking waypoint once the pad is off).
	var sim2: BattleSim = BattleSim.new({"ruleset": "elimination", "arena_id": "gale_corridor", "seed": 7, "max_time": 60.0,
		"blue": ["archer"], "red": ["giant"]})
	sim2.controllers[0] = AIFactory.make("tactician{glk=0}", sim2, 0)
	sim2.controllers[1] = null
	sim2.start()
	var tb: TacticianBrain = sim2.controllers[0]
	var u: BUnit = sim2.heroes[0]
	var r: float = sim2.radius(u)
	var nav: Navigator = tb.navigator_for(r)
	u.pos = Vector2(420, 170)
	var goal: Vector2 = Vector2(860, 170)
	var walk: Vector2 = nav.next_waypoint(u.pos, goal, r, 0.0, 0.0, 0.0, false)
	tb._route_cache.clear()
	var on_wp: Vector2 = tb._route_waypoint(u, goal, r)
	check(float(tb.cfg.get("glk", 1.0)) < 0.5 and on_wp.distance_to(walk) > 4.0, "glk=0 fixture: with the environment on the pad route differs from walking")
	sim2.env.enabled = false
	tb._route_cache.clear()
	var off_wp: Vector2 = tb._route_waypoint(u, goal, r)
	check(off_wp.distance_to(walk) < 0.5, "glk=0 routing walks when the environment is off (%s vs %s)" % [str(off_wp), str(walk)])
	sim2.dispose()

# fix_ai (hard rule 1): KitModel.nominal_damage cached by ability id alone, so
# whichever caster asked first (a telegraph without a live source, hermes with
# a borrowed skill, a virtual "borrow_<n>" copy from an earlier battle) fixed
# the value for the whole process: a telemetry shard and a fresh process
# played rift_harbor seed 163202 differently (time-out vs 62.7 s).
func _nominal_damage_pure() -> void:
	var mage: Defs.CharDef = DB.char_def("mage")
	var giant: Defs.CharDef = DB.char_def("giant")
	var hermes: Defs.CharDef = DB.char_def("hermes")
	var a: Defs.AbilityDef = mage.abilities[0]
	KitModel._nominal.clear()
	var fresh: float = KitModel.nominal_damage(a, mage)
	KitModel._nominal.clear()
	var orphan: float = KitModel.nominal_damage(a, null)
	var borrowed: float = KitModel.nominal_damage(a, hermes)
	var later: float = KitModel.nominal_damage(a, mage)
	check(not is_equal_approx(orphan, fresh) and is_equal_approx(later, fresh), "an ability's nominal damage does not depend on who asked first (%.1f / %.1f / %.1f vs %.1f)" % [orphan, borrowed, later, fresh])
	var b1: Defs.AbilityDef = mage.abilities[0].duplicate_def()
	var b2: Defs.AbilityDef = giant.abilities[2].duplicate_def()
	for b: Defs.AbilityDef in [b1, b2]:
		b.virtual = true
		b.virtual_kind = "borrow"
		b.id = "borrow_1"
	KitModel._nominal.clear()
	var fresh2: float = KitModel.nominal_damage(b2, hermes)
	KitModel._nominal.clear()
	KitModel.nominal_damage(b1, hermes)
	var second: float = KitModel.nominal_damage(b2, hermes)
	check(not is_equal_approx(KitModel.nominal_damage(b1, hermes), fresh2) and is_equal_approx(second, fresh2), "virtual copies sharing an id ('borrow_1') never share a cached value (%.1f vs %.1f)" % [second, fresh2])
	KitModel._nominal.clear()

# -------------------------------------------------------------------- D5
func _caches() -> void:
	var sim: BattleSim = battle(["archer", "mage"], ["giant"], [Vector2(500, 380), Vector2(500, 440), Vector2(700, 410)])
	var b: TacticianBrain = brain(sim)
	steps(sim, 2)
	b.intel.observe()
	b._plan()
	b.decide(sim.heroes[0])
	b.decide(sim.heroes[1])
	var shared: Dictionary = b.reserved.duplicate()
	b._compute_reserved()
	check(shared == b.reserved, "one reservation per tick plus incremental pledges stays equal to a fresh recomputation")
	var top: Array = b.mem.get(sim.heroes[0].idx, {}).get("top", [])
	var sorted: bool = top.size() <= 6 and not top.is_empty()
	for i in range(1, top.size()):
		sorted = sorted and float(top[i - 1].score) >= float(top[i].score)
	check(sorted, "invariant: debug top list is the six best in order")
	sim.dispose()
	var sim2: BattleSim = battle(["archer"], ["giant"], [Vector2(560, 400), Vector2(1200, 700)], [WALL])
	var b2: TacticianBrain = brain(sim2)
	var u: BUnit = sim2.heroes[0]
	var goal: Vector2 = Vector2(800, 400)
	var first: Vector2 = b2._route_waypoint(u, goal, sim2.radius(u))
	check(b2._route_cache.has(u.idx) and b2._route_waypoint(u, goal, sim2.radius(u)) == first, "blocked route waypoint is reused instead of a grid search every tick")
	sim2.dispose()

# ------------------------------------------------------------ D2 general
func _stuck_order_guard() -> void:
	var sim: BattleSim = battle(["hermes", "nitro"], ["sniper", "archer"], [Vector2(600, 400), Vector2(500, 400), Vector2(820, 380), Vector2(840, 440)])
	var h: BUnit = sim.heroes[0]
	var n: BUnit = sim.heroes[1]
	h.ks.borrowed = {"id": 777001, "owner": n.idx, "ability": n.def.abilities[1], "expires": sim.time + 24.0}
	h.ks.borrow_next = 999.0
	for i in h.cooldowns.size():
		h.cooldowns[i] = 999.0
	var idle: int = 0
	for tick in 90:
		sim.step()
		h.hp = sim.max_hp(h) * 0.5
		if str(h.command.get("ability_id", "")).begins_with("borrow_") and not bool(h.command.get("started", false)) and h.action == null:
			idle += 1
	metrics["refused_order_ticks"] = idle
	check(idle < 45, "an order the executor keeps refusing is dropped after 0.6 s (%d/90 idle ticks)" % idle)
	sim.dispose()
	_basic_belief_stall()

# Review 1.5.3 (tactician_brain.gd:1449): classic seed 153185, nitro held a
# basic order on the politician for 2+ s: fake news showed it 60 px away
# (steer holds inside need * 0.92) while it really stood 119 px away
# (start_basic measures the true distance). Basic orders join the guard.
func _basic_belief_stall() -> void:
	var sim: BattleSim = battle(["nitro"], ["politician", "archer"], [Vector2(500, 400), Vector2(620, 400), Vector2(1250, 700)])
	var n: BUnit = sim.heroes[0]
	var pol: BUnit = sim.heroes[1]
	var still_ticks: int = 0
	var basic_ticks: int = 0
	var hits: int = 0
	var start: Vector2 = n.pos
	for tick in 180:
		sim.warfare.false_reports[0][pol.idx] = {"source": pol.idx, "end": sim.time + 1.0, "offset": Vector2(-60, 0), "hp_offset": 0.0, "ready_at": []}
		pol.pos = Vector2(620, 400)
		pol.hp = sim.max_hp(pol)
		for i in n.cooldowns.size():
			n.cooldowns[i] = sim.time + 60.0
		var before: Vector2 = n.pos
		sim.step()
		for ev: Dictionary in sim.tick_events:
			if str(ev.type) == "HEALTH_DAMAGED" and int(ev.get("s", -1)) == n.idx:
				hits += 1
		if str(n.command.get("kind", "")) == "basic" and int(n.command.get("target", -1)) == pol.idx:
			basic_ticks += 1
			if n.pos.distance_to(before) < 0.2:
				still_ticks += 1
	metrics["basic_belief_stall"] = {"basic_order_ticks": basic_ticks, "still_with_basic_order": still_ticks, "hits": hits, "moved": snappedf(n.pos.distance_to(start), 0.1)}
	check(basic_ticks > 10 and still_ticks <= 75, "a basic order the misleading belief keeps short of range is dropped within ~1 s (%s)" % JSON.stringify(metrics["basic_belief_stall"]))
	sim.dispose()

# ---------------------------------------------------------- telemetry #4
func _hazard_routing() -> void:
	var lava: Dictionary = {"id": "pool", "type": "lava", "shape": "circle", "x": 650, "y": 400, "radius": 80, "damage": 34, "tickInterval": 0.5, "alwaysActive": true}
	var sim: BattleSim = battle(["archer"], ["giant"], [Vector2(500, 400), Vector2(800, 400)], [], [lava])
	var b: TacticianBrain = brain(sim)
	var u: BUnit = sim.heroes[0]
	var r: float = sim.radius(u)
	steps(sim, 2)
	b.intel.observe()
	b._plan()
	var inside: Vector2 = Vector2(650, 400)
	check(not Arena.shape_contains(lava, b._hazard_free_goal(u, inside, r), r), "a goal inside an always-on damage field is moved out of it")
	var moves: Array = []
	b._move_candidates(u, b._ctx(u), moves)
	var wet: Array = moves.filter(func(c: Dictionary): return Arena.shape_contains(lava, c.cmd.goal, r))
	check(not moves.is_empty() and wet.is_empty(), "no movement goal is parked in lava (%d)" % wet.size())
	check(b._route_hazard_cost(u, Vector2(820, 400), r, 120.0) > 0.0 and is_zero_approx(b._route_hazard_cost(u, Vector2(500, 220), r, 120.0)), "route cost prices crossing the lava, not walking beside it")
	sim.dispose()
	var pool: Dictionary = {"id": "ahead", "type": "lava", "shape": "circle", "x": 550, "y": 400, "radius": 50, "damage": 34, "tickInterval": 0.5, "alwaysActive": true}
	var sim2: BattleSim = battle(["archer"], ["giant"], [Vector2(400, 400), Vector2(1250, 700)], [], [pool])
	var b2: TacticianBrain = brain(sim2)
	var w: BUnit = sim2.heroes[0]
	var v: Vector2 = b2._hazard_lookahead(w, Vector2(1, 0), sim2.radius(w))
	check(v.normalized().dot(Vector2(1, 0)) < 0.95, "lookahead sees a field beyond the old 72 px probe and turns")
	sim2.dispose()
	_hazard_bounds_exact()

# D5: the hazard early-outs (bounding circles) must never hide a cost. On every
# shipped team/deathmatch arena, wherever _hazard_near says "clear", the exact
# public helpers must also report no damage and no positive penalty.
func _hazard_bounds_exact() -> void:
	var arenas: Array = []
	for mode: String in ["elimination", "control"]:
		for a: Arena in DB.arenas_for(mode):
			arenas.append(a)
	var dm: BattleSim = BattleSim.new({"ruleset": "deathmatch", "arena_id": "dm_ruined_town", "players": ["archer", "mage"], "seed": 153911, "max_time": 60.0})
	arenas.append(dm.arena)
	var probes: int = 0
	var skipped: int = 0
	var leaks: Array = []
	for ar: Arena in arenas:
		if ar.hazards.is_empty():
			continue
		var sim: BattleSim = BattleSim.new({"blue": ["giant"], "red": ["archer"], "arena_id": "classic", "seed": 153912, "max_time": 60.0})
		sim.arena = ar
		var b: TacticianBrain = TacticianBrain.new(sim, 0)
		var r: float = sim.radius(sim.heroes[0])
		var y: float = ar.min_y
		while y <= ar.max_y:
			var x: float = ar.min_x
			while x <= ar.max_x:
				var p: Vector2 = Vector2(x, y)
				if b._hazard_near(p, r + 2.0):
					skipped += 1
				else:
					for t: float in [0.0, 1.35, 2.9, 4.45, 7.1]:
						probes += 1
						if sim.arena.expected_hazard_damage(p, t, r, 1.0) > 0.0 or sim.arena.hazard_penalty(p, t, r) > 0.0:
							leaks.append("%s@(%d,%d) t=%.2f" % [ar.id, int(x), int(y), t])
				x += 37.0
			y += 37.0
		b.dispose()
		sim.dispose()
	dm.dispose()
	metrics["hazard_bounds"] = {"clear_probes": probes, "near_points": skipped}
	check(probes > 1000 and leaks.is_empty(), "hazard early-out never hides a real hazard cost (%d probes, leaks %s)" % [probes, str(leaks.slice(0, 4))])

# ------------------------------------------------------------------ C-5
func _retreat_anchor_local() -> void:
	var sim: BattleSim = battle(["archer", "mage"], ["werewolf"], [Vector2(600, 400), Vector2(520, 400), Vector2(800, 400)])
	var b: TacticianBrain = brain(sim)
	var u: BUnit = sim.heroes[0]
	var foe: BUnit = sim.heroes[2]
	steps(sim, 2)
	b.intel.observe()
	b._plan()
	var anchor: Vector2 = b._retreat_anchor(u, b._ctx(u))
	check(anchor.distance_to(foe.pos) >= u.pos.distance_to(foe.pos) + 100.0, "retreat anchor backs away from the local threat instead of onto an adjacent ally")
	sim.dispose()

# ---------------------------------------------------------- telemetry #2
func _stalemate_scouting() -> void:
	var sim: BattleSim = BattleSim.new({"seed": 154117, "arena_id": "ruined_gate", "max_time": 60.0, "ruleset": "elimination",
		"blue": ["engineer", "dimensionalist", "mage"], "red": ["blood_mage", "hive_mind", "archer"]})
	for t in 2:
		sim.controllers[t] = AIFactory.make("tactician", sim, t)
	sim.start()
	var first: float = -1.0
	while sim.state == BattleSim.RUNNING and sim.time < 45.0 and first < 0.0:
		sim.step()
		for ev: Dictionary in sim.tick_events:
			if str(ev.type) == "HEALTH_DAMAGED":
				var g: BUnit = sim.u_at(int(ev.get("g", -1)))
				if g and g.is_hero and int(ev.get("s", -1)) >= 0 and int(ev.get("s", -1)) != g.idx:
					first = sim.time
	metrics["ruined_gate_154117_first_damage"] = first
	check(first >= 0.0 and first < 45.0, "ruined_gate stalemate seed makes contact within 45 s (%.1f)" % first)
	sim.dispose()
	_mirror_scout_routes()

# Scout routes of the two teams on a point-symmetric map (the map rework's
# diagonal / top-bottom layouts) must be 180-degree images of each other. Raw
# grid paths zig-zag by search direction (tie-breaking), so sampled scout
# points differed by ~10 px median and one side got the better approach.
func _mirror_scout_routes() -> void:
	var walls: Array = [{"id": "a", "shape": "rect", "x": 380, "y": 240, "w": 240, "h": 68},
		{"id": "b", "shape": "rect", "x": 788, "y": 484, "w": 240, "h": 68},
		{"id": "c", "shape": "rect", "x": 625, "y": 340, "w": 158, "h": 112}]
	var sim: BattleSim = battle(["archer"], ["archer"], [Vector2(200, 300), Vector2(1208, 492)], walls)
	var b: TacticianBrain = brain(sim)
	var u: BUnit = sim.heroes[0]
	var r: float = sim.radius(u)
	var nav: Navigator = b.navigator_for(r)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 153913
	var pairs: int = 0
	var off: int = 0
	var errors: Array = []
	for trial in 90:
		var a: Vector2 = Vector2(rng.randf_range(70.0, 630.0), rng.randf_range(70.0, 722.0))
		var z: Vector2 = Vector2(rng.randf_range(780.0, 1338.0), rng.randf_range(70.0, 722.0))
		if not sim.arena.is_walkable(a, r) or not sim.arena.is_walkable(z, r) or nav.clear(a, z, r):
			continue
		var worst: float = 0.0
		u.pos = a
		b._scout_cache.clear()
		var p1: PackedVector2Array = b._cached_path(u, z, r)
		var a2: Vector2 = Vector2(1408.0 - a.x, 792.0 - a.y)
		var z2: Vector2 = Vector2(1408.0 - z.x, 792.0 - z.y)
		u.pos = a2
		b._scout_cache.clear()
		var p2: PackedVector2Array = b._cached_path(u, z2, r)
		for d: float in [120.0, 240.0]:
			var q1: Vector2 = b._along_route(a, z, p1, d)
			var q2: Vector2 = b._along_route(a2, z2, p2, d)
			worst = maxf(worst, q1.distance_to(Vector2(1408.0 - q2.x, 792.0 - q2.y)))
		pairs += 1
		errors.append(worst)
		if worst > 8.0:
			off += 1
	errors.sort()
	var median: float = errors[errors.size() / 2] if not errors.is_empty() else INF
	metrics["point_symmetric_scout"] = {"pairs": pairs, "median_px": snappedf(median, 0.1), "over_8px": off}
	check(pairs >= 30 and median <= 5.0 and off * 4 <= pairs, "both teams get 180-degree-image scout points (median %.1f px, %d/%d over 8 px)" % [median, off, pairs])
	sim.dispose()
