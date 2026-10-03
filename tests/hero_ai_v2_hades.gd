extends SceneTree

# V2 하데스 (hades) tactical AI checks (key: H-AI-hades, DESIGN_V2 §2.2/§2.7).
# Every section pairs a situation where the AI should act with one where it
# should not: Kynee hiding, S1 ambush, S2 heal block, S3 harvest, the
# cerberus following hades' attack order, and enemy brains facing the pet and
# the shades. Private fixtures on an open arena (optional walls and brush);
# full battles at the end check casts, information fairness and determinism.
# Run: --script res://tests/hero_ai_v2_hades.gd

class Idle:
	extends TeamController
	func decide(u: BUnit) -> void:
		u.next_decision_at = sim.time + 10.0
		u.command = {}

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
		push_error("HERO_AI_V2_HADES " + label)


func arena_fixture(id: String, obstacles: Array = [], forests: Array = []) -> Arena:
	return Arena.from_data({"id": id, "width": 1408, "height": 792,
		"bounds": {"minX": 40, "maxX": 1368, "minY": 40, "maxY": 752}, "obstacles": obstacles, "hazards": [], "forests": forests})


# Heroes are placed in roster order: blue first, then red. Idle controllers.
func make(blue: Array, red: Array, positions: Array, obstacles: Array = [], forests: Array = [], seed_v: int = 202601) -> BattleSim:
	var sim: BattleSim = BattleSim.new({"blue": blue, "red": red, "arena_id": "classic", "seed": seed_v, "max_time": 150.0})
	sim.arena = arena_fixture("hades_ai_%d_%d_%d" % [seed_v, obstacles.size(), forests.size()], obstacles, forests)
	for i in mini(positions.size(), sim.heroes.size()):
		var u: BUnit = sim.heroes[i]
		u.pos = positions[i]
		u.prev_pos = u.pos
		u.vel = Vector2.ZERO
		u.facing = Vector2.RIGHT if u.team == 0 else Vector2.LEFT
	sim.controllers = [Idle.new(sim, 0), Idle.new(sim, 1)]
	sim.start()
	return sim


func brain_for(sim: BattleSim, team: int = 0) -> TacticianBrain:
	sim._update_visibility()
	var b: TacticianBrain = TacticianBrain.new(sim, team)
	b.on_start(sim)
	return b


func refresh(sim: BattleSim, b: TacticianBrain) -> void:
	sim._update_visibility()
	b.intel.observe()
	b.intel.observe_fast()
	b._danger_cache.clear()
	b._plan()


# The pet spawns lazily on the first passive update; park it out of the way.
func park_pet(sim: BattleSim, h: BUnit, at: Vector2 = Vector2(80, 80)) -> BUnit:
	sim.kits.update_passives(0.0)
	var pets: Array[BUnit] = sim.kits.owned_entities(h, "cerberus")
	if pets.is_empty():
		return null
	pets[0].pos = at
	pets[0].prev_pos = at
	return pets[0]


func cands(b: TacticianBrain, u: BUnit, doctrine: bool = true, basics: bool = false) -> Array:
	var ctx: Dictionary = b._ctx(u)
	var out: Array = []
	b._ability_candidates(u, ctx, out)
	if basics:
		b._basic_candidates(u, ctx, out)
	if doctrine:
		Doctrine.adjust(b, u, ctx, out)
	return out


func slot_rows(rows: Array, index: int) -> Array:
	return rows.filter(func(c: Dictionary): return str(c.cmd.get("kind", "")) == "ability" and int(c.cmd.get("index", -1)) == index)


func best(rows: Array) -> Dictionary:
	var out: Dictionary = {}
	for c: Dictionary in rows:
		if out.is_empty() or float(c.value) > float(out.value):
			out = c
	return out


func has_note(c: Dictionary, text: String) -> bool:
	for n in c.get("notes", []):
		if str(n).contains(text):
			return true
	return false


func points(b: TacticianBrain, u: BUnit) -> Array:
	var ctx: Dictionary = b._ctx(u)
	var pts: Array = []
	Doctrine.move_points(b, u, ctx, null, pts)
	return pts


func point_rows(pts: Array, text: String) -> Array:
	return pts.filter(func(p: Array): return str(p[1]).contains(text))


func set_hp(sim: BattleSim, u: BUnit, ratio: float) -> void:
	u.hp = sim.max_hp(u) * ratio


func _run() -> void:
	DB.ensure_loaded()
	_doctrine_and_kit()
	_kynee()
	_kynee_tradeoff()
	_s1_ambush()
	_s2_heal_block()
	_s3_harvest()
	_coefficient_contract()
	_cerberus_command()
	_enemy_side()
	_information()
	_battles()
	var result: Dictionary = {"status": "PASS" if failed.is_empty() else "FAIL", "passed": passed, "failed": failed, "metrics": metrics}
	print("HERO_AI_V2_HADES ", JSON.stringify(result))
	quit(0 if failed.is_empty() else 1)


# ------------------------------------------------------------ doctrine / kit model

func _doctrine_and_kit() -> void:
	var prof: Dictionary = Doctrine.of("hades")
	check(not prof.is_empty() and str(prof.get("title", "")) != "" and str(prof.get("code", "")) != "", "hades has a doctrine with title and code")
	check((prof.get("principles", []) as Array).size() == 4 and not (prof.get("combos", []) as Array).is_empty() and str(prof.get("geometry", "")) != "", "doctrine has four principles, combos and a geometry")
	for role in prof.get("roles", []):
		check(Doctrine.ROLE_LABEL.has(str(role)), "doctrine role %s has a Korean label" % role)
	var d: Defs.CharDef = DB.char_def("hades")
	var st: Dictionary = KitModel.stats_of_def(d)
	var s1: Dictionary = KitModel.evaluate(d.abilities[0].effects, st, {"max_hp": 1000.0, "hp": 800.0})
	var s2: Dictionary = KitModel.evaluate(d.abilities[1].effects, st, {"max_hp": 1000.0, "hp": 120.0})
	var s3: Dictionary = KitModel.evaluate(d.abilities[2].effects, st, {"max_hp": 1000.0, "hp": 800.0})
	check(float(s1.summon) > 0.0 and float(s1.get("screen", 0.0)) > 800.0, "kit model values the escort shades (bites and screening bodies)")
	# The 22 V1.5.3 heroes' kits produce none of the new keys (unchanged values).
	var new_keys: int = 0
	for id in DB.ids().slice(0, 22):
		var od: Defs.CharDef = DB.char_def(id)
		for oa in od.abilities:
			var oe: Dictionary = KitModel.evaluate((oa as Defs.AbilityDef).effects, KitModel.stats_of_def(od), {"max_hp": 1000.0, "hp": 800.0})
			for k in ["screen", "heal_block", "drain"]:
				if oe.has(k):
					new_keys += 1
		if KitModel.companion_dps(od, 70.0) != 0.0:
			new_keys += 1
	check(new_keys == 0, "old heroes' kit valuations are untouched by the hades effect types")
	check(is_equal_approx(float(s2.get("heal_block", 0.0)), 5.0) and is_equal_approx(float(s2.get("heal_block_below", 0.0)), 0.15), "kit model reads the conditional heal block (5 s under 15%)")
	check(float(s3.magic) > 50.0 and float(s3.get("drain", 0.0)) > 0.0 and not (s3.buffs as Array).is_empty(), "kit model values the soul harvest aura damage and drain")
	check(KitModel.companion_dps(d, 68.0) > 28.0 and KitModel.companion_dps(DB.char_def("giant"), 70.0) == 0.0, "companion dps only for the cerberus rule")
	var base: Dictionary = KitModel._enemy_base(d)
	check(float(base.dps) > KitModel.basic_dps(st, d) * 100.0 / 130.0, "enemy profile of hades includes the cerberus bites")
	var f: Dictionary = DraftDirector.kit_features(d)
	check(float(f.anti_heal) == 1.0 and float(f.healing) > 0.2 and float(f.summon) == 1.0, "draft features: anti-heal, Kynee/harvest sustain, summoner")
	metrics["draft_healing"] = float(f.healing)
	metrics["draft_raw_damage"] = float(f.raw_damage)
	check(ItemValuation.BASIC_SHARE.has("hades"), "item valuation has a measured basic-attack share for hades")


# ------------------------------------------------------------ Kynee

func _kynee() -> void:
	# Brush 70 px to the side of hades; an archer 520 px east sees him but
	# none of its attacks reaches (out of immediate danger).
	var forests: Array = [{"x": 600, "y": 330, "radius": 50, "patch": 0}]
	for hp in [0.3, 0.95]:
		var sim: BattleSim = make(["hades"], ["archer"], [Vector2(600, 400), Vector2(1120, 400)], [], forests)
		var h: BUnit = sim.heroes[0]
		park_pet(sim, h)
		set_hp(sim, h, hp)
		h.last_damage_time = -10.0
		var b: TacticianBrain = brain_for(sim)
		refresh(sim, b)
		check(not sim.kits.concealed(h), "kynee fixture: the archer sees hades")
		var pts: Array = points(b, h)
		var hide: Array = point_rows(pts, "은신 회복")
		b._decide(h)
		var goal: Vector2 = h.command.get("goal", h.pos)
		var hidden_goal: bool = str(h.command.get("kind", "")) == "move" and HadesTactics.concealed_at(b, h, goal) and goal.distance_to(h.pos) > 20.0
		if hp < 0.5:
			check(not hide.is_empty(), "low health: hiding spots are offered (brush %d)" % point_rows(pts, "수풀 은신").size())
			check(hidden_goal and sim.arena.forest_at(goal) >= 0, "low health out of immediate danger: hades steps into the nearby brush (%s)" % str(h.command.get("purpose", "")))
			metrics["kynee_low_choice"] = str(h.command.get("purpose", ""))
		else:
			check(hide.is_empty(), "healthy: no hiding spots")
			check(not (str(h.command.get("purpose", "")).contains("은신 회복")), "healthy: hades does not go hiding (%s)" % str(h.command.get("purpose", "")))
		b.dispose()
		sim.dispose()
	# Under an archer's long shot: any concealed spot (out of its sight) wins.
	var simp: BattleSim = make(["hades"], ["archer"], [Vector2(600, 400), Vector2(1050, 400)], [], [{"x": 600, "y": 250, "radius": 60, "patch": 0}])
	var hp_: BUnit = simp.heroes[0]
	park_pet(simp, hp_)
	set_hp(simp, hp_, 0.3)
	hp_.last_damage_time = -10.0
	var bp: TacticianBrain = brain_for(simp)
	refresh(simp, bp)
	bp._decide(hp_)
	var gp: Vector2 = hp_.command.get("goal", hp_.pos)
	check(str(hp_.command.get("kind", "")) == "move" and HadesTactics.concealed_at(bp, hp_, gp) and gp.distance_to(hp_.pos) > 20.0, "low health under the archer's long shot: hades moves out of its sight (%s)" % str(hp_.command.get("purpose", "")))
	bp.dispose()
	simp.dispose()
	# No brush: a wall north-east of hades blocks the archer's sight.
	var wall: Array = [{"id": "wall", "shape": "rect", "x": 640, "y": 180, "w": 40, "h": 160}]
	for hp2 in [0.3, 0.95]:
		var sim2: BattleSim = make(["hades"], ["archer"], [Vector2(600, 400), Vector2(1050, 400)], wall)
		var h2: BUnit = sim2.heroes[0]
		park_pet(sim2, h2)
		set_hp(sim2, h2, hp2)
		h2.last_damage_time = -10.0
		var b2: TacticianBrain = brain_for(sim2)
		refresh(sim2, b2)
		var pts2: Array = point_rows(points(b2, h2), "시야 차단 회복")
		var all_hidden: bool = true
		for p in pts2:
			all_hidden = all_hidden and HadesTactics.concealed_at(b2, h2, p[0])
		b2._decide(h2)
		var goal2: Vector2 = h2.command.get("goal", h2.pos)
		if hp2 < 0.5:
			check(not pts2.is_empty() and all_hidden, "low health: sight-breaking spots behind the wall are offered and hidden (%d)" % pts2.size())
			check(str(h2.command.get("kind", "")) == "move" and HadesTactics.concealed_at(b2, h2, goal2), "low health: hades breaks the archer's line of sight (%s)" % str(h2.command.get("purpose", "")))
			# Walking there for real conceals him and the regeneration runs.
			sim2.controllers[0] = b2
			var hp0: float = h2.hp
			for i in 150:
				sim2.step()
			check(sim2.kits.concealed(h2) and h2.hp > hp0 + 30.0, "behind the wall hades is concealed and regenerates (+%.0f)" % (h2.hp - hp0))
			metrics["kynee_wall_regen_5s"] = h2.hp - hp0
		else:
			check(pts2.is_empty(), "healthy: no sight-breaking spots")
		b2.dispose()
		sim2.dispose()


# Hidden at low health: attacking gives up the regeneration (unless it kills).
func _kynee_tradeoff() -> void:
	var forests: Array = [{"x": 500, "y": 400, "radius": 70, "patch": 0}]
	for case in ["low", "kill", "healthy"]:
		var sim: BattleSim = make(["hades"], ["swordsman"], [Vector2(500, 400), Vector2(640, 400)], [], forests)
		var h: BUnit = sim.heroes[0]
		var e: BUnit = sim.heroes[1]
		park_pet(sim, h)
		set_hp(sim, h, 0.95 if case == "healthy" else 0.3)
		h.last_damage_time = -10.0
		if case == "kill":
			e.hp = 30.0
		var b: TacticianBrain = brain_for(sim)
		refresh(sim, b)
		var rows: Array = cands(b, h, true, true)
		var basic: Array = rows.filter(func(c: Dictionary): return str(c.cmd.get("kind", "")) == "basic" and int(c.cmd.get("target", -1)) == e.idx)
		check(sim.kits.concealed(h) and not basic.is_empty(), "tradeoff fixture (%s): hidden in brush with a basic on the swordsman" % case)
		var noted: bool = not basic.is_empty() and has_note(basic[0], "은신 회복 유지")
		match case:
			"low":
				check(noted, "hidden at 30%: a basic attack is charged the lost regeneration")
			"kill":
				check(not noted, "hidden at 30%: a killing blow is not held back")
			"healthy":
				check(not noted, "hidden at 95%: no regeneration penalty")
		b.dispose()
		sim.dispose()


# ------------------------------------------------------------ S1

func _s1_ambush() -> void:
	# Concealed in brush, a swordsman 200 px away (outside, cannot see in).
	var forests: Array = [{"x": 500, "y": 400, "radius": 70, "patch": 0}]
	var sim: BattleSim = make(["hades"], ["swordsman"], [Vector2(500, 400), Vector2(700, 400)], [], forests)
	var h: BUnit = sim.heroes[0]
	park_pet(sim, h)
	var b: TacticianBrain = brain_for(sim)
	refresh(sim, b)
	var rows: Array = slot_rows(cands(b, h), 0)
	check(sim.kits.concealed(h) and sim.ability_ready(h, 0, h.def.abilities[0]), "S1 fixture: concealed in brush, S1 ready")
	check(not rows.is_empty() and float(rows[0].value) > 0.0, "concealed with an enemy at 200: S1 ambush candidate (%.0f)" % (float(rows[0].value) if not rows.is_empty() else 0.0))
	b._decide(h)
	check(str(h.command.get("kind", "")) == "ability" and int(h.command.get("index", -1)) == 0, "concealed with an enemy at 200: hades casts S1 (%s)" % str(h.command.get("purpose", "")))
	metrics["s1_value_200"] = float(rows[0].value) if not rows.is_empty() else 0.0
	# The same enemy 420 px away and standing still: the ring would expire
	# before anyone reaches it.
	sim.heroes[1].pos = Vector2(920, 400)
	sim.heroes[1].prev_pos = sim.heroes[1].pos
	refresh(sim, b)
	var far_rows: Array = slot_rows(cands(b, h), 0)
	var v_far: float = float(far_rows[0].value) if not far_rows.is_empty() else 0.0
	check(v_far < metrics.s1_value_200 * 0.5, "a still enemy at 420 makes the ring worth much less (%.0f vs %.0f)" % [v_far, metrics.s1_value_200])
	b.dispose()
	sim.dispose()
	# Enemy beyond the ambush reach and no engage: never with nobody near.
	var sim2: BattleSim = make(["hades", "archer"], ["swordsman"], [Vector2(400, 400), Vector2(800, 400), Vector2(960, 400)], [], [{"x": 400, "y": 400, "radius": 70, "patch": 0}])
	var h2: BUnit = sim2.heroes[0]
	park_pet(sim2, h2)
	var b2: TacticianBrain = brain_for(sim2)
	refresh(sim2, b2)
	b2.plan.stance = "POKE"
	b2.plan.go = false
	check(sim2.is_seen(0, sim2.heroes[2]) and sim2.ability_ready(h2, 0, h2.def.abilities[0]), "S1 far fixture: enemy seen by the ally, S1 ready")
	# The swordsman charges hades (its observed velocity).
	(b2.intel.enemies[sim2.heroes[2].idx] as TeamIntel.EnemyBelief).vel = Vector2(-120, 0)
	check(slot_rows(cands(b2, h2), 0).is_empty(), "enemy 560 px away and no engage: no S1")
	b2.plan.stance = "ENGAGE"
	b2.plan.go = true
	check(not slot_rows(cands(b2, h2), 0).is_empty(), "enemy 560 px away charging in while the team engages: S1 allowed")
	b2.dispose()
	sim2.dispose()
	# Nobody visible at all: no S1 even though hades is concealed.
	var sim3: BattleSim = make(["hades"], ["swordsman"], [Vector2(300, 400), Vector2(1300, 650)])
	var h3: BUnit = sim3.heroes[0]
	park_pet(sim3, h3)
	var b3: TacticianBrain = brain_for(sim3)
	refresh(sim3, b3)
	check(sim3.kits.concealed(h3) and slot_rows(cands(b3, h3), 0).is_empty(), "concealed but no enemy near: no S1")
	b3.dispose()
	sim3.dispose()
	# Spotted: the engine gate keeps S1 out of the decision set.
	var sim4: BattleSim = make(["hades"], ["swordsman"], [Vector2(500, 400), Vector2(700, 400)])
	var h4: BUnit = sim4.heroes[0]
	park_pet(sim4, h4)
	var b4: TacticianBrain = brain_for(sim4)
	refresh(sim4, b4)
	check(not sim4.kits.concealed(h4) and slot_rows(cands(b4, h4), 0).is_empty(), "spotted: no S1 candidate")
	# Brush on the way to the enemy (off the sight line): approach through it.
	b4.dispose()
	sim4.dispose()
	var sim5: BattleSim = make(["hades"], ["swordsman"], [Vector2(350, 400), Vector2(900, 400)], [], [{"x": 600, "y": 300, "radius": 60, "patch": 0}])
	var h5: BUnit = sim5.heroes[0]
	park_pet(sim5, h5)
	var b5: TacticianBrain = brain_for(sim5)
	refresh(sim5, b5)
	check(not sim5.kits.concealed(h5), "ambush approach fixture: hades is seen")
	b5.plan.stance = "POKE"
	var amb: Array = point_rows(points(b5, h5), "수풀 경유 매복")
	check(not amb.is_empty() and sim5.arena.forest_at(amb[0][0]) >= 0, "S1 ready and spotted: the brush on the way is an approach point")
	b5.plan.stance = "DISENGAGE"
	check(point_rows(points(b5, h5), "수풀 경유 매복").is_empty(), "retreating: no brush detour")
	b5.plan.stance = "POKE"
	h5.cooldowns[0] = sim5.time + 10.0
	check(point_rows(points(b5, h5), "수풀 경유 매복").is_empty(), "S1 on cooldown: no brush detour")
	b5.dispose()
	sim5.dispose()


# ------------------------------------------------------------ S2

func _s2_heal_block() -> void:
	var cases: Array = [
		["healer_team", ["archer", "aphrodite"], 0.0, true],
		["no_healing", ["archer", "sniper"], 0.0, false],
		["healthy_target", ["archer", "aphrodite"], 0.8, false],
		["lethal_swing", ["archer", "aphrodite"], -1.0, false],
	]
	var a2: Defs.AbilityDef = DB.char_def("hades").abilities[1]
	var value_with: float = 0.0
	var value_without: float = 0.0
	for row in cases:
		var sim: BattleSim = make(["hades"], row[1], [Vector2(500, 400), Vector2(590, 400), Vector2(900, 400)])
		var h: BUnit = sim.heroes[0]
		var e: BUnit = sim.heroes[1]
		park_pet(sim, h)
		var est: Dictionary = KitModel._enemy_base(e.def).st
		var dmg: float = KitModel.mitigate(KitModel.evaluate(a2.effects, KitModel.stats_of_unit(sim, h), {}), float(est.armor), float(est.mr))
		var mx: float = sim.max_hp(e)
		if float(row[2]) > 0.0:
			e.hp = mx * float(row[2])
		elif float(row[2]) < 0.0:
			e.hp = dmg * 0.6
		else:
			e.hp = mx * 0.15 + dmg * 0.6
		var b: TacticianBrain = brain_for(sim)
		refresh(sim, b)
		var ctx: Dictionary = b._ctx(h)
		var eb: TeamIntel.EnemyBelief = b.intel.enemies[e.idx]
		var hb: float = HadesTactics.special_enemy(b, h, a2, eb, e.pos, ctx)
		var s2: Array = slot_rows(cands(b, h, false), 1).filter(func(c: Dictionary): return int(c.cmd.get("target", -1)) == e.idx)
		check(not s2.is_empty(), "S2 fixture %s: cone candidate on the archer" % row[0])
		if bool(row[3]):
			check(hb > 40.0, "S2 leaves the archer under 15%% and its team heals: heal block bonus (%.0f)" % hb)
			value_with = float(s2[0].value) if not s2.is_empty() else 0.0
			metrics["s2_heal_block_bonus"] = hb
		else:
			check(is_zero_approx(hb), "S2 %s: no heal block bonus (%.1f)" % [row[0], hb])
			if str(row[0]) == "no_healing":
				value_without = float(s2[0].value) if not s2.is_empty() else 0.0
		b.dispose()
		sim.dispose()
	check(value_with > value_without + 30.0, "S2 is worth more against a healing team at the threshold (%.0f vs %.0f)" % [value_with, value_without])
	# The real swing applies the block exactly in the predicted case.
	var sim2: BattleSim = make(["hades"], ["archer", "aphrodite"], [Vector2(500, 400), Vector2(590, 400), Vector2(900, 400)])
	var h2: BUnit = sim2.heroes[0]
	var e2: BUnit = sim2.heroes[1]
	park_pet(sim2, h2)
	var est2: Dictionary = KitModel._enemy_base(e2.def).st
	var dmg2: float = KitModel.mitigate(KitModel.evaluate(a2.effects, KitModel.stats_of_unit(sim2, h2), {}), float(est2.armor), float(est2.mr))
	e2.hp = sim2.max_hp(e2) * 0.15 + dmg2 * 0.6
	h2.facing = Vector2.RIGHT
	check(sim2.start_ability(h2, 1, e2, e2.pos), "S2 real cast starts")
	var blocked: bool = false
	for i in 20:
		sim2.step()
		for ev in sim2.tick_events:
			if str(ev.type) == "HEAL_BLOCKED" and int(ev.g) == e2.idx:
				blocked = true
	check(blocked and e2.alive, "the predicted swing really heal-blocks the archer")
	sim2.dispose()


# ------------------------------------------------------------ S3

func _s3_harvest() -> void:
	var setups: Array = [
		["two", [Vector2(500, 400), Vector2(600, 400), Vector2(560, 470)]],
		["one", [Vector2(500, 400), Vector2(600, 400), Vector2(1000, 650)]],
		["none", [Vector2(500, 400), Vector2(820, 400), Vector2(800, 520)]],
	]
	var values: Dictionary = {}
	for row in setups:
		var sim: BattleSim = make(["hades"], ["swordsman", "giant"], row[1])
		var h: BUnit = sim.heroes[0]
		park_pet(sim, h)
		var b: TacticianBrain = brain_for(sim)
		refresh(sim, b)
		var rows: Array = slot_rows(cands(b, h), 2)
		values[row[0]] = float(rows[0].value) if not rows.is_empty() else 0.0
		if str(row[0]) == "none":
			check(rows.is_empty(), "S3 with no enemy within 150: no candidate")
		else:
			check(not rows.is_empty() and float(rows[0].value) > 60.0, "S3 with %s enemies in the aura: candidate (%.0f)" % [row[0], values[row[0]]])
		if str(row[0]) == "two":
			b._decide(h)
			check(str(h.command.get("kind", "")) == "ability" and int(h.command.get("index", -1)) == 2, "two melee enemies around hades: S3 is the decision (%s)" % str(h.command.get("purpose", "")))
		b.dispose()
		sim.dispose()
	check(float(values.two) > float(values.one) * 1.5, "S3 value grows with the enemies in range (%.0f vs %.0f)" % [values.two, values.one])
	metrics["s3_value"] = values
	# The buff hook prices the same aura.
	var sim2: BattleSim = make(["hades"], ["swordsman"], [Vector2(500, 400), Vector2(600, 400)])
	var h2: BUnit = sim2.heroes[0]
	park_pet(sim2, h2)
	var b2: TacticianBrain = brain_for(sim2)
	refresh(sim2, b2)
	var ctx2: Dictionary = b2._ctx(h2)
	var f3: Dictionary = HadesTactics.harvest_effect(h2.def.abilities[2])
	check(b2._buff_value(h2, f3, ctx2, true, 100.0) > 60.0, "_buff_value soulHarvest uses the harvest model")
	b2.dispose()
	sim2.dispose()


# ------------------------------------------------------------ cerberus

func _coefficient_contract() -> void:
	var sim: BattleSim = make(["hades"], ["swordsman"], [Vector2(500, 400), Vector2(600, 400)])
	var h: BUnit = sim.heroes[0]
	var target: BUnit = sim.heroes[1]
	park_pet(sim, h)
	var b: TacticianBrain = brain_for(sim)
	b.plan.stance = "POKE"
	var f1: Dictionary = HadesTactics.shade_effect(h.def.abilities[0])
	var f3: Dictionary = HadesTactics.harvest_effect(h.def.abilities[2])
	var rows: Array = []
	HadesTactics._summon_candidate(b, h, 0, h.def.abilities[0], f1, b._ctx(h), rows)
	var base_s1: float = float(best(rows).get("parts", {}).get("소환", 0.0))
	var base_bite: float = float(sim.freeze_effects(h, null, [f1.attack], false, false)[0].base)
	var base_harvest: Dictionary = HadesTactics.harvest_value(b, h, f3, b._ctx(h))
	var hp_before: float = target.hp
	var base_tick: float = sim.apply_damage(h, target, f3.damage, {"source_type": "ABILITY"})
	target.hp = hp_before
	sim.add_buff(h, &"abilityCoefficient", 0.5, 5.0, h.idx)
	var buff_bite: float = float(sim.freeze_effects(h, null, [f1.attack], false, false)[0].base)
	rows.clear()
	HadesTactics._summon_candidate(b, h, 0, h.def.abilities[0], f1, b._ctx(h), rows)
	var buff_s1: float = float(best(rows).get("parts", {}).get("소환", 0.0))
	var buff_harvest: Dictionary = HadesTactics.harvest_value(b, h, f3, b._ctx(h))
	var buff_tick: float = sim.apply_damage(h, target, f3.damage, {"source_type": "ABILITY"})
	check(base_s1 > 0.0 and buff_s1 > base_s1 and absf(buff_s1 / base_s1 - buff_bite / base_bite) < 0.0001,
		"S1 own coefficient changes predicted bites by the engine's frozen damage ratio")
	check(float(base_harvest.dmg) > 0.0 and float(buff_harvest.dmg) > float(base_harvest.dmg)
		and absf(float(buff_harvest.dmg) / float(base_harvest.dmg) - buff_tick / base_tick) < 0.0001,
		"S3 own coefficient changes predicted harvest by the actual damage ratio")
	b.dispose()
	sim.dispose()


func _cerberus_command() -> void:
	# A wounded archer 140 px ahead (hades' target), a swordsman behind hades
	# right next to the pet (its own guard choice would be the swordsman).
	var sim: BattleSim = make(["hades"], ["archer", "swordsman"], [Vector2(500, 400), Vector2(640, 400), Vector2(400, 400)])
	var h: BUnit = sim.heroes[0]
	var a: BUnit = sim.heroes[1]
	var s: BUnit = sim.heroes[2]
	a.hp = sim.max_hp(a) * 0.25
	# Skills on cooldown: hades keeps a basic-attack order on the archer.
	for k in h.cooldowns.size():
		h.cooldowns[k] = 99.0
	var b: TacticianBrain = brain_for(sim)
	sim.controllers[0] = b
	var pet: BUnit = null
	var followed: bool = false
	var bitten: bool = false
	var ordered: bool = false
	for i in 120:
		sim.step()
		if pet == null:
			var pets: Array[BUnit] = sim.kits.owned_entities(h, "cerberus")
			pet = pets[0] if not pets.is_empty() else null
		if pet == null or not a.alive:
			continue
		if int(h.command.get("target", -1)) == a.idx:
			ordered = true
			if pet.target_idx == a.idx and pet.pos.distance_to(s.pos) < pet.pos.distance_to(a.pos):
				followed = true
		for ev in sim.tick_events:
			if str(ev.type) == "HEALTH_DAMAGED" and int(ev.g) == a.idx and str(ev.get("source_type", "")) == "SUMMON":
				bitten = true
	check(ordered, "hades orders an attack on the wounded archer")
	check(followed, "the pet takes hades' order target although the swordsman is nearer to it")
	check(bitten, "the pet bites hades' order target")
	b.dispose()
	sim.dispose()


# ------------------------------------------------------------ enemy side

func _enemy_side() -> void:
	# An enemy archer brain sees hades and the pet in basic range.
	var sim: BattleSim = make(["hades"], ["archer"], [Vector2(600, 400), Vector2(800, 400)])
	var h: BUnit = sim.heroes[0]
	var ar: BUnit = sim.heroes[1]
	var pet: BUnit = park_pet(sim, h, Vector2(650, 450))
	var b: TacticianBrain = brain_for(sim, 1)
	refresh(sim, b)
	var rows: Array = cands(b, ar, true, true)
	var on_h: Array = rows.filter(func(c: Dictionary): return str(c.cmd.get("kind", "")) == "basic" and int(c.cmd.get("target", -1)) == h.idx)
	var on_p: Array = rows.filter(func(c: Dictionary): return str(c.cmd.get("kind", "")) == "basic" and int(c.cmd.get("target", -1)) == pet.idx)
	check(not on_h.is_empty() and not on_p.is_empty() and float(on_h[0].value) > float(on_p[0].value) * 1.8, "enemy basics prefer hades over a healthy pet (%.0f vs %.0f)" % [float(on_h[0].value) if not on_h.is_empty() else 0.0, float(on_p[0].value) if not on_p.is_empty() else 0.0])
	b._decide(ar)
	check(int(ar.command.get("target", -1)) != pet.idx, "the enemy archer does not tunnel on the pet")
	# The killing blow on the pet buys its respawn time.
	pet.hp = 20.0
	refresh(sim, b)
	var rows2: Array = cands(b, ar, true, true)
	var kill_p: Array = rows2.filter(func(c: Dictionary): return str(c.cmd.get("kind", "")) == "basic" and int(c.cmd.get("target", -1)) == pet.idx)
	check(not kill_p.is_empty() and has_note(kill_p[0], "케르베로스 처치"), "a basic that kills the pet is valued for the 15 s respawn")
	# Danger: standing next to the pet costs its bites.
	pet.hp = 420.0
	refresh(sim, b)
	var near_d: float = b.danger_at(ar, pet.pos + Vector2(30, 0), 1.0)
	var far_d: float = b.danger_at(ar, pet.pos + Vector2(0, 260), 1.0)
	check(HadesTactics.entity_danger(b, ar, b.intel.entities[pet.idx], pet.pos + Vector2(30, 0), 1.0) > 10.0 and near_d > far_d, "enemy danger counts the pet's bites (%.0f vs %.0f)" % [near_d, far_d])
	b.dispose()
	sim.dispose()
	# Shades block skillshots: a sniper stun (no pierce) aimed at hades
	# through a shade.
	var sim2: BattleSim = make(["hades"], ["sniper"], [Vector2(600, 400), Vector2(830, 400)])
	var h2: BUnit = sim2.heroes[0]
	var m: BUnit = sim2.heroes[1]
	park_pet(sim2, h2)
	sim2.push_status(h2, &"invisible", h2.idx, 1.0)
	check(sim2.start_ability(h2, 0, h2, h2.pos), "shade fixture: S1 cast")
	for i in 15:
		sim2.step()
	sim2.remove_statuses_where(h2, func(x): return x.type == &"invisible")
	var shades: Array[BUnit] = sim2.kits.owned_entities(h2, "shade")
	check(shades.size() == 5, "shade fixture: five shades")
	for sh in shades:
		sh.pos = Vector2(600 + 60 * (shades.find(sh) + 1), 120)
		sh.prev_pos = sh.pos
	h2.pos = Vector2(600, 400)
	var b2: TacticianBrain = brain_for(sim2, 1)
	refresh(sim2, b2)
	var clear: Array = slot_rows(cands(b2, m), 3).filter(func(c: Dictionary): return int(c.cmd.get("target", -1)) == h2.idx)
	shades[0].pos = Vector2(715, 400)
	shades[0].prev_pos = shades[0].pos
	refresh(sim2, b2)
	var blocked: Array = slot_rows(cands(b2, m), 3).filter(func(c: Dictionary): return int(c.cmd.get("target", -1)) == h2.idx)
	var v_clear: float = float(clear[0].value) if not clear.is_empty() else 0.0
	var v_block: float = float(blocked[0].value) if not blocked.is_empty() else 0.0
	check(not clear.is_empty() and v_clear > 60.0, "sniper stun on hades with a clear line is valued (%.0f)" % v_clear)
	check(blocked.is_empty() or v_block < v_clear * 0.4, "the same stun into a shade is not worth it (%.0f vs %.0f)" % [v_block, v_clear])
	var direct: Array = slot_rows(cands(b2, m), 3).filter(func(c: Dictionary): return int(c.cmd.get("target", -1)) == shades[0].idx)
	check(direct.is_empty() or float(direct[0].value) < v_clear * 0.4, "stunning a shade itself is not worth a stun on hades (%.0f)" % (float(direct[0].value) if not direct.is_empty() else 0.0))
	metrics["sniper_stun_clear_vs_shade"] = [v_clear, v_block]
	b2.dispose()
	sim2.dispose()


# ------------------------------------------------------------ information

# Hidden enemy state (health, cooldowns) cannot change hades' decision or his
# concealment estimate.
func _information() -> void:
	var sigs: Array = []
	for variant in 2:
		var sim: BattleSim = make(["hades"], ["archer", "swordsman"], [Vector2(500, 400), Vector2(860, 400), Vector2(1300, 700)], [], [{"x": 1300, "y": 700, "radius": 60, "patch": 0}])
		var h: BUnit = sim.heroes[0]
		var hidden: BUnit = sim.heroes[2]
		park_pet(sim, h)
		set_hp(sim, h, 0.35)
		h.last_damage_time = -10.0
		var b: TacticianBrain = brain_for(sim)
		refresh(sim, b)
		# The hidden swordsman changes after the beliefs exist (its start
		# position is public in team modes).
		if variant == 1:
			hidden.hp = 40.0
			hidden.cooldowns.fill(99.0)
			hidden.pos = Vector2(1250, 690)
			hidden.prev_pos = hidden.pos
		refresh(sim, b)
		check(not sim.is_seen(0, hidden), "information fixture: the swordsman is hidden")
		b._decide(h)
		var probe: Array = []
		for p in [Vector2(450, 300), Vector2(560, 520), Vector2(1200, 650)]:
			probe.append(HadesTactics.concealed_at(b, h, p))
		sigs.append([h.command.get("kind", ""), h.command.get("goal", Vector2.ZERO), h.command.get("index", -1), h.command.get("target", -1), probe])
		b.dispose()
		sim.dispose()
	check(sigs[0] == sigs[1], "hidden enemy health, cooldowns and position do not change hades' decision")


# ------------------------------------------------------------ battles

# Full tactician battles with hades: S1 is only cast with an enemy hero the
# team sees within the ambush/engage reach, S3 only with an enemy body inside
# the aura; the same seed reproduces the battle.
func _battles() -> void:
	var configs: Array = [
		{"blue": ["hades", "archer", "aphrodite"], "red": ["swordsman", "mage", "giant"], "arena_id": "moon_garden", "seed": 7301},
		{"blue": ["giant", "sniper", "plague_doctor"], "red": ["hades", "werewolf", "blood_mage"], "arena_id": "crossroads", "seed": 7302},
	]
	var bad_s1: int = 0
	var bad_s3: int = 0
	var casts: Dictionary = {1: 0, 2: 0, 3: 0}
	for cfg in configs:
		var sigs: Array = []
		for rep in 2:
			var c: Dictionary = cfg.duplicate(true)
			c["max_time"] = 90.0
			var sim: BattleSim = BattleSim.new(c)
			for t in sim.team_count:
				sim.controllers[t] = AIFactory.make("tactician", sim, t)
			sim.start()
			var h: BUnit = null
			for u in sim.heroes:
				if u.def.id == "hades":
					h = u
			var seen_at: Dictionary = {}
			while sim.state == BattleSim.RUNNING and sim.tick < 2800:
				sim.step()
				for e0 in sim.heroes:
					if e0.team != h.team and sim.is_seen(h.team, e0):
						seen_at[e0.idx] = sim.time
				for ev in sim.tick_events:
					if str(ev.type) != "CAST_STARTED" or int(ev.s) != h.idx or rep == 1:
						continue
					var slot: int = int(ev.get("slot", 0))
					casts[slot] = int(casts.get(slot, 0)) + 1
					if slot == 1:
						var ok1: bool = false
						# The team's beliefs refresh every few ticks: a sighting up
						# to 0.15 s old is the latest knowledge.
						for e in sim.heroes:
							if e.alive and e.team != h.team and sim.time - float(seen_at.get(e.idx, -9.0)) <= 0.15 and e.pos.distance_to(h.pos) <= HadesTactics.S1_ENGAGE_REACH + 40.0:
								ok1 = true
						if not ok1:
							bad_s1 += 1
					elif slot == 3:
						var ok3: bool = false
						for e2 in sim.opponents(h):
							if sim.observes(h, e2) and e2.pos.distance_to(h.pos) <= 150.0 + sim.radius(e2) + 45.0:
								ok3 = true
						if not ok3:
							bad_s3 += 1
			var fin: Array = []
			for u2 in sim.heroes:
				fin.append([u2.def.id, snappedf(u2.hp, 0.01), snappedf(u2.pos.x, 0.01), snappedf(u2.pos.y, 0.01), u2.st_casts])
			sigs.append(JSON.stringify([sim.winner, snappedf(sim.time, 0.001), fin]).sha256_text())
			sim.dispose()
		check(sigs[0] == sigs[1], "battle %s seed %d with hades reproduces exactly" % [cfg.arena_id, cfg.seed])
	check(bad_s1 == 0, "S1 is never cast without a seen enemy hero in reach (%d bad of %d)" % [bad_s1, casts[1]])
	check(bad_s3 == 0, "S3 is never cast without an enemy in the aura (%d bad of %d)" % [bad_s3, casts[3]])
	check(int(casts[2]) > 0 and int(casts[3]) > 0, "hades uses S2 and S3 in battle (%s)" % str(casts))
	metrics["battle_casts"] = casts
