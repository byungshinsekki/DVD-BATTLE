extends SceneTree

# V2.0 토르케마다 (torquemada) AI scenario checks (DESIGN_V2 §2.4, §2.7; key
# H-AI-torquemada). Private fixtures with idle controllers: each section sets
# up an opportunity and asserts the brain takes it, and a near miss where it
# must not. Run: --script res://tests/hero_ai_v2_torquemada.gd

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
		push_error("HERO_AI_V2_TORQUEMADA " + label)


func arena_fixture(id: String) -> Arena:
	return Arena.from_data({"id": id, "width": 1408, "height": 792,
		"bounds": {"minX": 40, "maxX": 1368, "minY": 40, "maxY": 752}, "obstacles": [], "hazards": []})


# Heroes are placed in roster order: blue first, then red.
func make(blue: Array, red: Array, positions: Array, seed_v: int = 200401) -> BattleSim:
	var sim: BattleSim = BattleSim.new({"blue": blue, "red": red, "arena_id": "classic", "seed": seed_v, "max_time": 150.0})
	sim.arena = arena_fixture("ai_torquemada_%d" % seed_v)
	for i in mini(positions.size(), sim.heroes.size()):
		var u: BUnit = sim.heroes[i]
		u.pos = positions[i]
		u.prev_pos = u.pos
		u.vel = Vector2.ZERO
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


func advance(sim: BattleSim, seconds: float) -> void:
	for i in int(ceil(seconds / BattleSim.DT - 1e-6)):
		sim.step()


func cands(b: TacticianBrain, u: BUnit, basics: bool = false) -> Array:
	var ctx: Dictionary = b._ctx(u)
	var out: Array = []
	b._ability_candidates(u, ctx, out)
	if basics:
		b._basic_candidates(u, ctx, out)
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


func value_of(rows: Array) -> float:
	return float(best(rows).value) if not rows.is_empty() else -INF


func has_note(c: Dictionary, text: String) -> bool:
	for n in c.get("notes", []):
		if str(n).contains(text):
			return true
	return false


# The order the brain actually issues (full decision, all layers).
func decided_index(b: TacticianBrain, u: BUnit) -> int:
	u.next_decision_at = 0.0
	b.decide(u)
	return int(u.command.get("index", -1)) if str(u.command.get("kind", "")) == "ability" else -1


func unit(sim: BattleSim, id: String, team: int) -> BUnit:
	for u: BUnit in sim.heroes:
		if u.def.id == id and u.team == team:
			return u
	return null


# Every ability of every enemy belief was just seen used (cooldowns running).
func enemy_cooldowns_seen(sim: BattleSim, b: TacticianBrain) -> void:
	for k in b.intel.enemies:
		var eb: TeamIntel.EnemyBelief = b.intel.enemies[k]
		for i in eb.cd_last.size():
			eb.cd_last[i] = sim.time
	b._plan()


func _run() -> void:
	DB.ensure_loaded()
	_doctrine_and_models()
	_fire_cluster()
	_nothing_to_cleanse()
	_debuff_values()
	_fire_reserve()
	_edict_peel()
	_edict_motion_contract()
	_edict_versus_fire()
	_verdict()
	_tenacity_view()
	_live_battles()
	var result: Dictionary = {"status": "PASS" if failed.is_empty() else "FAIL", "passed": passed, "failed": failed, "metrics": metrics}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://reports/hero_ai_v2"))
	var f: FileAccess = FileAccess.open("res://reports/hero_ai_v2/torquemada.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(result, "  "))
	print("HERO_AI_V2_TORQUEMADA ", JSON.stringify(result))
	quit(0 if failed.is_empty() else 1)


# ------------------------------------------------------- doctrine and models
func _doctrine_and_models() -> void:
	var prof: Dictionary = Doctrine.of("torquemada")
	check(not prof.is_empty() and str(prof.get("title", "")) != "" and str(prof.get("code", "")) != "", "torquemada doctrine has a title and a code")
	check((prof.get("principles", []) as Array).size() == 4 and (prof.get("combos", []) as Array).size() >= 1 and str(prof.get("geometry", "")) != "", "doctrine has four principles, combos and a geometry")
	var tw: Dictionary = prof.get("target", {})
	check(tw.has("low") and tw.has("threat") and tw.has("backline") and tw.has("isolated"), "doctrine has the four target weights")
	var roles_ok: bool = true
	for r in prof.get("roles", []):
		roles_ok = roles_ok and Doctrine.ROLE_LABEL.has(str(r))
	check(roles_ok and (prof.roles as Array).has("CLEANSER"), "every doctrine role has a label (CLEANSER = %s)" % str(Doctrine.ROLE_LABEL.get("CLEANSER", "")))
	var d: Defs.CharDef = DB.char_def("torquemada")
	var st: Dictionary = KitModel.stats_of_def(d)
	var s1: Dictionary = KitModel.evaluate(d.abilities[0].effects, st, {})
	var s3: Dictionary = KitModel.evaluate(d.abilities[2].effects, st, {})
	check(is_equal_approx(float(s1.cleanse), 1.0), "kit model: the fire cleanses each ally once (oncePerUnit, %.2f)" % float(s1.cleanse))
	check(is_equal_approx(float(s3.cleanse), 1.0) and is_equal_approx(float(s3.displace), 140.0), "kit model: the edict cleanses and pushes 140")
	var sw: Defs.CharDef = DB.char_def("swordsman")
	check(float(KitModel.evaluate(sw.abilities[1].effects, KitModel.stats_of_def(sw), {}).cleanse) == 0.0, "kit model: V1 abilities have no cleanse")
	var rate: float = KitModel.support_rate(d)
	metrics["support_rate"] = rate
	check(rate > 10.0, "support rate counts the two cleanses and the peel (%.1f)" % rate)
	var feat: Dictionary = DraftDirector.kit_features(d)
	metrics["draft_features"] = {"cleanse": feat.cleanse, "ally_protection": feat.ally_protection, "control": feat.control}
	check(float(feat.cleanse) == 1.0 and float(feat.ally_protection) > 0.3 and float(DraftDirector.kit_features(sw).cleanse) == 0.0, "draft features: torquemada cleanses and protects allies")
	check(ItemValuation.BASIC_SHARE.has("torquemada"), "item valuation has a basic-attack share for torquemada")


# ---------------------------------------------- S1: fire over CC'd allies
func _fire_cluster() -> void:
	var sim: BattleSim = make(["torquemada", "archer", "mage", "swordsman"], ["giant", "werewolf"],
		[Vector2(500, 400), Vector2(640, 340), Vector2(650, 420), Vector2(420, 600), Vector2(980, 400), Vector2(1020, 520)])
	var t: BUnit = sim.heroes[0]
	var ar: BUnit = unit(sim, "archer", 0)
	var mg: BUnit = unit(sim, "mage", 0)
	var sw: BUnit = unit(sim, "swordsman", 0)
	var gi: BUnit = unit(sim, "giant", 1)
	sim.apply_status(gi, ar, {"status": "stun", "duration": 1.6})
	sim.apply_status(gi, mg, {"status": "stun", "duration": 1.6})
	sim.apply_status(gi, sw, {"status": "root", "duration": 1.6})
	var b: TacticianBrain = brain_for(sim)
	refresh(sim, b)
	var rows: Array = slot_rows(cands(b, t, true), 0)
	var top: Dictionary = best(rows)
	var p: Vector2 = top.cmd.pos if not top.is_empty() else Vector2.INF
	var both: bool = p.is_finite() and p.distance_to(ar.pos) <= 90.0 + sim.radius(ar) and p.distance_to(mg.pos) <= 90.0 + sim.radius(mg)
	metrics["fire_cluster"] = {"value": float(top.get("value", 0.0)), "label": str(top.get("label", "")), "rows": rows.size()}
	check(both, "S1 is placed over both stunned allies at once (%s)" % str(top.get("label", "none")))
	var lone: Array = rows.filter(func(c): return (c.cmd.pos as Vector2).distance_to(sw.pos) < 30.0)
	check(not lone.is_empty() and float(lone[0].value) < float(top.value), "the cluster of two stunned allies beats the rooted ally alone")
	check(decided_index(b, t) == 0, "the brain casts S1 on the stunned allies")
	# The real cast frees them.
	var started: bool = sim.start_ability(t, 0, null, p)
	advance(sim, 0.35)
	check(started and not sim.has_status(ar, &"stun") and not sim.has_status(mg, &"stun"), "the cast fire cleanses both stunned allies")
	b.dispose()
	sim.dispose()


func _nothing_to_cleanse() -> void:
	var sim: BattleSim = make(["torquemada", "archer", "mage"], ["giant", "werewolf"],
		[Vector2(500, 400), Vector2(560, 340), Vector2(570, 450), Vector2(980, 400), Vector2(1020, 520)])
	var t: BUnit = sim.heroes[0]
	var b: TacticianBrain = brain_for(sim)
	refresh(sim, b)
	var rows: Array = cands(b, t, true)
	check(slot_rows(rows, 0).is_empty(), "no S1 candidate when no ally has anything to cleanse")
	check(slot_rows(rows, 2).is_empty(), "no S3 candidate with nothing to cleanse and no enemy within 150")
	check(slot_rows(rows, 1).is_empty(), "no S2 candidate when nobody crowd-controlled torquemada")
	# An allied buff and an own slow on an ally are not cleansed.
	var ar: BUnit = unit(sim, "archer", 0)
	sim.add_buff(ar, &"attackDamage", -0.15, 4.0, t.idx, {"tag": "ally_debuff"})
	b._danger_cache.clear()
	check(slot_rows(cands(b, t), 0).is_empty(), "an allied stat change on an ally is not something to cleanse")
	b.dispose()
	sim.dispose()


# ------------------------------------------- every cleansable debuff counts
func _debuff_values() -> void:
	var sim: BattleSim = make(["torquemada", "archer", "mage"], ["plague_doctor", "joker"],
		[Vector2(500, 400), Vector2(560, 440), Vector2(600, 350), Vector2(900, 400), Vector2(950, 500)])
	var ar: BUnit = unit(sim, "archer", 0)
	var mg: BUnit = unit(sim, "mage", 0)
	var pd: BUnit = unit(sim, "plague_doctor", 1)
	var jk: BUnit = unit(sim, "joker", 1)
	var b: TacticianBrain = brain_for(sim)
	refresh(sim, b)
	var burn: Dictionary = {"interval": 0.5, "duration": 3.0, "damageEffect": {"type": "damage", "school": "magic", "base": 20, "ap": 0.2}}
	var kinds: Array = [
		["치유 감소", func(): sim.apply_status(pd, ar, {"status": "healReduction", "magnitude": 0.35, "duration": 4.0})],
		["받는 피해 증가", func(): sim.apply_status(pd, ar, {"status": "damageAmp", "damageAmp": 0.2, "duration": 4.0})],
		["역병", func(): sim.apply_mark(pd, ar, {"status": "plague", "stacks": 3, "duration": 4.0})],
		["혼란", func(): sim.apply_mark(jk, ar, {"status": "confusion", "stacks": 2, "duration": 4.0})],
		["포효", func(): sim.apply_status(pd, ar, {"status": "roar", "tenacityLoss": 0.1, "duration": 6.0})],
		["둔화", func(): sim.apply_status(pd, ar, {"status": "slow", "magnitude": 0.35, "duration": 3.0})],
		["지속 피해", func(): sim.apply_dot(pd, ar, burn)],
		["능력치 감소", func(): sim.add_buff(ar, &"attackDamage", -0.15, 4.0, pd.idx, {"tag": "enemy_debuff"})],
	]
	var values: Dictionary = {}
	for k: Array in kinds:
		ar.statuses.clear()
		ar.buffs.clear()
		(k[1] as Callable).call()
		b._danger_cache.clear()
		var uv: Dictionary = TorquemadaTactics.unit_value(b, ar, 0.3)
		values[str(k[0])] = snappedf(float(uv.value), 0.1)
		var ok: bool = float(uv.value) > 0.0 and int(uv.n) == 1 and float(uv.hard) == 0.0
		check(ok, "debuff value: %s on an ally is worth cleansing (%.1f)" % [str(k[0]), float(uv.value)])
	metrics["debuff_values"] = values
	# What our own team put on an ally is not removed by the cleanse.
	ar.statuses.clear()
	ar.buffs.clear()
	sim.apply_dot(mg, ar, burn)
	check(int(TorquemadaTactics.unit_value(b, ar, 0.3).n) == 0, "an allied damage over time on an ally has no cleanse value")
	# Values add up over allies: two debuffed allies under one fire beat one.
	ar.statuses.clear()
	sim.apply_status(pd, ar, {"status": "healReduction", "magnitude": 0.35, "duration": 5.0})
	sim.apply_status(pd, ar, {"status": "damageAmp", "damageAmp": 0.25, "duration": 5.0})
	sim.apply_status(pd, mg, {"status": "damageAmp", "damageAmp": 0.25, "duration": 5.0})
	sim.apply_dot(pd, mg, burn)
	enemy_cooldowns_seen(sim, b)
	b._danger_cache.clear()
	var rows: Array = slot_rows(cands(b, unit(sim, "torquemada", 0)), 0)
	var top: Dictionary = best(rows)
	check(not top.is_empty() and int((top.parts as Dictionary).get("인원", 0)) == 2, "the fire covers both debuffed allies (%s)" % str(top.get("label", "none")))
	b.dispose()
	sim.dispose()


# ------------------------------------- S1 reserve in an enemy engage window
func _fire_reserve() -> void:
	var sim: BattleSim = make(["torquemada", "archer"], ["giant", "mage"],
		[Vector2(500, 400), Vector2(560, 470), Vector2(780, 400), Vector2(800, 500)])
	var t: BUnit = sim.heroes[0]
	var ar: BUnit = unit(sim, "archer", 0)
	var mg: BUnit = unit(sim, "mage", 1)
	sim.apply_status(mg, ar, {"status": "damageAmp", "damageAmp": 0.2, "duration": 4.0})
	var b: TacticianBrain = brain_for(sim)
	refresh(sim, b)
	var ctx: Dictionary = b._ctx(t)
	var pending: float = TorquemadaTactics.pending_cc(b, t, ctx)
	var reserve: float = TorquemadaTactics.reserve_cost(b, t, ctx)
	metrics["reserve"] = {"pending_cc": pending, "cost": reserve, "engaged": ctx.engaged}
	check(pending >= 0.6 and reserve > 0.0, "an engaging giant and mage with ready control open the reserve (%.2f s, %.0f)" % [pending, reserve])
	check(slot_rows(cands(b, t), 0).is_empty(), "S1 is held when only a debuff is up and the enemy control is still to come")
	# The same debuff once the enemy control has been spent.
	enemy_cooldowns_seen(sim, b)
	var after: Array = slot_rows(cands(b, t), 0)
	metrics["reserve_spent"] = {"pending_cc": TorquemadaTactics.pending_cc(b, t, b._ctx(t)), "value": value_of(after)}
	check(not after.is_empty(), "with the enemy control spent the debuffed ally gets the fire")
	b.dispose()
	sim.dispose()
	# Hard control is up: no reserve.
	var sim2: BattleSim = make(["torquemada", "archer"], ["giant", "mage"],
		[Vector2(500, 400), Vector2(560, 470), Vector2(780, 400), Vector2(800, 500)])
	var t2: BUnit = sim2.heroes[0]
	sim2.apply_status(unit(sim2, "giant", 1), unit(sim2, "archer", 0), {"status": "stun", "duration": 1.5})
	var b2: TacticianBrain = brain_for(sim2)
	refresh(sim2, b2)
	var rows2: Array = slot_rows(cands(b2, t2), 0)
	check(not rows2.is_empty() and not (best(rows2).parts as Dictionary).has("보존"), "a stunned ally is cleansed during the engage, no reserve")
	b2.dispose()
	sim2.dispose()


# ------------------------------------------------------- S3 edict peel
func _edict_peel() -> void:
	var sim: BattleSim = make(["torquemada", "archer"], ["swordsman", "werewolf"],
		[Vector2(500, 400), Vector2(460, 470), Vector2(540, 470), Vector2(1100, 300)])
	var t: BUnit = sim.heroes[0]
	var ar: BUnit = unit(sim, "archer", 0)
	ar.hp = sim.max_hp(ar) * 0.5
	var b: TacticianBrain = brain_for(sim)
	refresh(sim, b)
	var rows: Array = slot_rows(cands(b, t, true), 2)
	var peel: float = float((best(rows).get("parts", {}) as Dictionary).get("견제", 0.0)) if not rows.is_empty() else 0.0
	metrics["edict_peel"] = {"value": value_of(rows), "peel": peel}
	check(not rows.is_empty() and peel > 60.0, "S3 values pushing a melee diver off our backline archer (%.0f)" % peel)
	check(decided_index(b, t) == 2, "the brain casts S3 to peel the swordsman")
	var sw: BUnit = unit(sim, "swordsman", 1)
	var d0: float = sw.pos.distance_to(t.pos)
	sim.start_ability(t, 2, t, t.pos)
	advance(sim, 0.7)
	check(sw.pos.distance_to(t.pos) - d0 > 100.0, "the edict pushes the swordsman away")
	b.dispose()
	sim.dispose()
	# Enemies outside 150 are not peeled; a ranged enemy inside is not pushed
	# away from our own melee ally either.
	var sim2: BattleSim = make(["torquemada", "swordsman"], ["archer", "werewolf"],
		[Vector2(500, 400), Vector2(600, 330), Vector2(620, 380), Vector2(820, 430)])
	var t2: BUnit = sim2.heroes[0]
	var b2: TacticianBrain = brain_for(sim2)
	refresh(sim2, b2)
	var rows2: Array = slot_rows(cands(b2, t2), 2)
	check(rows2.is_empty(), "no S3 for a ranged enemy our swordsman is fighting and a diver 330 away")
	b2.dispose()
	sim2.dispose()
	# A diver between torquemada and our archer would be pushed onto her.
	var sim3: BattleSim = make(["torquemada", "archer"], ["swordsman", "mage"],
		[Vector2(500, 400), Vector2(700, 400), Vector2(600, 400), Vector2(1200, 650)])
	var t3: BUnit = sim3.heroes[0]
	var b3: TacticianBrain = brain_for(sim3)
	refresh(sim3, b3)
	var peel3: Dictionary = TorquemadaTactics.edict_peel(b3, t3, t3.def.abilities[2], b3._ctx(t3), 0.25)
	metrics["edict_onto_carry"] = float(peel3.value)
	check(float(peel3.value) < 0.0 and slot_rows(cands(b3, t3), 2).is_empty(), "no S3 that would push a diver onto our archer (%.0f)" % float(peel3.value))
	b3.dispose()
	sim3.dispose()
	# A healthy torquemada does not push away the melee enemy he is fighting.
	var sim4: BattleSim = make(["torquemada", "archer"], ["swordsman", "mage"],
		[Vector2(500, 400), Vector2(260, 400), Vector2(560, 400), Vector2(1200, 650)])
	var t4: BUnit = sim4.heroes[0]
	var b4: TacticianBrain = brain_for(sim4)
	refresh(sim4, b4)
	var self_rows: Array = slot_rows(cands(b4, t4), 2)
	check(self_rows.is_empty(), "no S3 self-peel at full health against the swordsman he is fighting")
	t4.hp = sim4.max_hp(t4) * 0.2
	b4._danger_cache.clear()
	b4._plan()
	var low_rows: Array = slot_rows(cands(b4, t4), 2)
	metrics["edict_self_low"] = value_of(low_rows)
	check(not low_rows.is_empty(), "at 20% health he pushes the swordsman off himself")
	b4.dispose()
	sim4.dispose()


# ----------------------------------------------------- S3 versus S1 for a cleanse
func _edict_motion_contract() -> void:
	for obstacle in ["open", "wall", "body"]:
		var sim: BattleSim = make(["torquemada"], ["swordsman", "mage"], [Vector2(500, 400), Vector2(560, 400), Vector2(650, 400)])
		var u: BUnit = sim.heroes[0]
		var e: BUnit = sim.heroes[1]
		var body: BUnit = sim.heroes[2]
		if obstacle != "body":
			body.pos = Vector2(850, 600)
		if obstacle == "wall":
			sim.arena = Arena.from_data({"id": "edict_wall", "width": 1408, "height": 792,
				"bounds": {"minX": 40, "maxX": 1368, "minY": 40, "maxY": 752},
				"obstacles": [{"shape": "rect", "x": 625, "y": 340, "w": 12, "h": 120}], "hazards": []})
		var b: TacticianBrain = brain_for(sim)
		var belief: TeamIntel.EnemyBelief = b.intel.enemies[e.idx]
		var start: Vector2 = e.pos
		var end: Vector2 = start + Vector2.RIGHT * TorquemadaTactics.PUSH
		var land: Vector2 = TorquemadaTactics.edict_landing(b, belief, start, end)
		var expected_x: float = end.x
		if obstacle == "wall":
			expected_x = 625.0 - sim.radius(e)
		elif obstacle == "body":
			expected_x = body.pos.x - sim.radius(e) - sim.radius(body)
		check(absf(land.x - expected_x) < 0.01, "edict predicts first %s contact" % obstacle)
		var started: bool = sim.kits.displace(u, e, {"distance": TorquemadaTactics.PUSH}, {})
		for k in 15:
			sim.time += BattleSim.DT
			sim.kits.update_motion(e, BattleSim.DT)
		check(started and e.motion == null and e.pos.distance_to(land) < 0.01, "edict prediction matches real %s motion" % obstacle)
		if obstacle == "body":
			var hidden: TeamIntel.EnemyBelief = b.intel.enemies[body.idx]
			hidden.visible = false
			var unknown_a: Vector2 = TorquemadaTactics.edict_landing(b, belief, start, end)
			body.pos = Vector2(620, 400)
			var unknown_b: Vector2 = TorquemadaTactics.edict_landing(b, belief, start, end)
			check(unknown_a == end and unknown_b == end, "edict cannot read an unseen body's actual position")
		b.dispose()
		sim.dispose()


func _edict_versus_fire() -> void:
	var sim: BattleSim = make(["torquemada", "archer"], ["giant", "mage"],
		[Vector2(500, 400), Vector2(560, 470), Vector2(1000, 400), Vector2(1050, 520)])
	var t: BUnit = sim.heroes[0]
	sim.apply_status(unit(sim, "giant", 1), unit(sim, "archer", 0), {"status": "stun", "duration": 1.6})
	var b: TacticianBrain = brain_for(sim)
	refresh(sim, b)
	var rows: Array = cands(b, t)
	var s1: Array = slot_rows(rows, 0)
	var s3: Array = slot_rows(rows, 2)
	check(not s1.is_empty() and (s3.is_empty() or value_of(s1) > value_of(s3)), "for a cleanse alone the fire is preferred and the edict is kept")
	check(s3.is_empty() or has_note(s3[0], "아우토다페로 충분"), "the edict notes the fire is enough")
	t.cooldowns[0] = sim.time + 8.0
	var s3b: Array = slot_rows(cands(b, t), 2)
	check(not s3b.is_empty(), "with the fire on cooldown the edict cleanses the stunned ally within 150")
	b.dispose()
	sim.dispose()


# ------------------------------------------------------------ S2 verdict
func _verdict() -> void:
	var sim: BattleSim = make(["torquemada", "archer"], ["werewolf", "mage"],
		[Vector2(500, 400), Vector2(430, 470), Vector2(640, 400), Vector2(700, 520)])
	var t: BUnit = sim.heroes[0]
	var ww: BUnit = unit(sim, "werewolf", 1)
	var mg: BUnit = unit(sim, "mage", 1)
	sim.apply_status(ww, t, {"status": "stun", "duration": 0.4})
	advance(sim, 0.4)
	var b: TacticianBrain = brain_for(sim)
	refresh(sim, b)
	var rows: Array = slot_rows(cands(b, t), 1)
	var on_ww: Array = rows.filter(func(c): return int(c.cmd.target) == ww.idx)
	var on_mg: Array = rows.filter(func(c): return int(c.cmd.target) == mg.idx)
	check(not on_ww.is_empty(), "S2 targets the werewolf that stunned torquemada")
	check(on_mg.is_empty(), "S2 never targets an enemy that did not crowd-control him")
	var ctx: Dictionary = b._ctx(t)
	var e: TeamIntel.EnemyBelief = b.intel.enemies[ww.idx]
	var bonus: float = TorquemadaTactics.verdict_bonus(b, t, e, ctx)
	metrics["verdict"] = {"value": value_of(on_ww), "diver_bonus": bonus}
	check(bonus >= 28.0, "a diver is worth more to root (%.0f)" % bonus)
	check(decided_index(b, t) == 1 and int(t.command.get("target", -1)) == ww.idx, "the brain roots the werewolf with S2")
	# Not observed: no order even with the record.
	sim.push_status(ww, &"invisible", ww.idx, 3.0)
	refresh(sim, b)
	check(slot_rows(cands(b, t), 1).is_empty(), "S2 is not ordered on an enemy torquemada does not observe")
	sim.remove_statuses_where(ww, func(x): return x.type == &"invisible")
	# The record expires after the current S2 condition window.
	advance(sim, float(t.def.abilities[1].condition.ccSourceWithin) + 0.2)
	refresh(sim, b)
	check(slot_rows(cands(b, t), 1).is_empty(), "the record expires after its configured window")
	b.dispose()
	sim.dispose()
	# Expiry urgency: the record about to lapse adds value.
	var sim2: BattleSim = make(["torquemada"], ["mage"], [Vector2(500, 400), Vector2(760, 400)])
	var t2: BUnit = sim2.heroes[0]
	var m2: BUnit = sim2.heroes[1]
	sim2.apply_status(m2, t2, {"status": "root", "duration": 0.3})
	var b2: TacticianBrain = brain_for(sim2)
	refresh(sim2, b2)
	var fresh_v: float = TorquemadaTactics.verdict_bonus(b2, t2, b2.intel.enemies[m2.idx], b2._ctx(t2))
	var window: float = float(t2.def.abilities[1].condition.ccSourceWithin)
	advance(sim2, window - 3.0)
	refresh(sim2, b2)
	var early_v: float = TorquemadaTactics.verdict_bonus(b2, t2, b2.intel.enemies[m2.idx], b2._ctx(t2))
	check(is_equal_approx(early_v, fresh_v), "S2 expiry urgency does not begin three seconds before the current window ends")
	advance(sim2, 2.0)
	refresh(sim2, b2)
	var late_v: float = TorquemadaTactics.verdict_bonus(b2, t2, b2.intel.enemies[m2.idx], b2._ctx(t2))
	check(late_v > fresh_v + 15.0, "a record about to expire raises the S2 value (%.0f -> %.0f)" % [fresh_v, late_v])
	b2.dispose()
	sim2.dispose()


# ------------------------------------------------ enemies controlling him
func _tenacity_view() -> void:
	var d: Defs.CharDef = DB.char_def("torquemada")
	var out: Dictionary = {"cc": {"stun": 1.0, "charm": 1.0, "airborne": 1.0}, "slow_dur": 2.0}
	KitModel.apply_tenacity(out, d)
	check(is_equal_approx(float(out.cc.stun), 0.65 / 0.95) and is_equal_approx(float(out.cc.charm), 0.65 / 0.95 * 0.5) and is_equal_approx(float(out.cc.airborne), 1.0),
		"kit model: a stun on torquemada lasts 0.65/0.95, a charm half of that, airborne unchanged")
	var same: Dictionary = {"cc": {"stun": 1.0}, "slow_dur": 2.0}
	KitModel.apply_tenacity(same, DB.char_def("swordsman"))
	check(float(same.cc.stun) == 1.0 and float(same.slow_dur) == 2.0, "kit model: a V1 hero's crowd control is valued as before")
	# Through the enemy brain: the mage's root on torquemada versus on an archer.
	var sim: BattleSim = make(["torquemada", "archer"], ["mage"], [Vector2(500, 400), Vector2(500, 520), Vector2(760, 450)])
	var mg: BUnit = unit(sim, "mage", 1)
	var b: TacticianBrain = brain_for(sim, 1)
	refresh(sim, b)
	var ctx: Dictionary = b._ctx(mg)
	var root_ab: Defs.AbilityDef = mg.def.abilities[0]
	var on_t: Dictionary = b._enemy_value(mg, root_ab, b.intel.enemies[sim.heroes[0].idx], ctx, 1.0)
	var on_a: Dictionary = b._enemy_value(mg, root_ab, b.intel.enemies[sim.heroes[1].idx], ctx, 1.0)
	var rt: float = KitModel.cc_total(on_t.ev)
	var ra: float = KitModel.cc_total(on_a.ev)
	metrics["enemy_root_on"] = {"torquemada": rt, "archer": ra}
	check(ra > 0.0 and is_equal_approx(rt, ra * 0.65 / 0.95), "the enemy brain values its root on torquemada 0.65/0.95 as long")
	b.dispose()
	sim.dispose()


# ------------------------------------------------------ live battles
func _cast_metrics(cfg: Dictionary, seconds: float) -> Dictionary:
	var sim: BattleSim = BattleSim.new(cfg)
	sim.controllers[0] = AIFactory.make("tactician", sim, 0)
	sim.controllers[1] = AIFactory.make("tactician", sim, 1)
	sim.start()
	var casts: Array = [0, 0, 0]
	var purpose: Array = [0, 0, 0]
	var pending: Dictionary = {}
	var sig: Array = []
	var t_idx: Array = []
	for u in sim.heroes:
		if u.def.id == "torquemada":
			t_idx.append(u.idx)
	while sim.state == BattleSim.RUNNING and sim.time < seconds:
		sim.step()
		for ev in sim.tick_events:
			var ty: String = str(ev.type)
			var ab = ev.get("ability")
			if not (ab is Defs.AbilityDef) or (ab as Defs.AbilityDef).char_id != "torquemada" or not t_idx.has(int(ev.s)):
				continue
			var slot: int = (ab as Defs.AbilityDef).slot
			var key: String = "%d:%d" % [int(ev.s), slot]
			if ty == "CAST_STARTED":
				casts[slot - 1] += 1
				pending[key] = false
			elif ty == "CLEANSED" and slot != 2 and pending.has(key) and not bool(pending[key]):
				pending[key] = true
				purpose[slot - 1] += 1
			elif ty == "CC_APPLIED" and slot == 2 and pending.has(key) and not bool(pending[key]):
				pending[key] = true
				purpose[1] += 1
			elif ty == "DASH_STARTED" and slot == 3 and pending.has(key) and not bool(pending[key]):
				pending[key] = true
				purpose[2] += 1
	for u in sim.heroes:
		sig.append([u.id, snappedf(u.hp, 0.001), snappedf(u.pos.x, 0.01), snappedf(u.pos.y, 0.01), u.st_casts])
	var res: Dictionary = {"casts": casts, "purpose": purpose, "sig": JSON.stringify(sig).sha256_text(), "time": sim.time}
	sim.dispose()
	return res


func _live_battles() -> void:
	var cfg: Dictionary = {"blue": ["torquemada", "swordsman", "archer"], "red": ["giant", "mage", "werewolf"], "arena_id": "classic", "seed": 200477, "max_time": 150.0}
	var a: Dictionary = _cast_metrics(cfg, 75.0)
	var b: Dictionary = _cast_metrics(cfg, 75.0)
	metrics["live_classic"] = a
	check(str(a.sig) == str(b.sig), "same configuration and seed give the same battle")
	var total: int = int(a.casts[0]) + int(a.casts[2])
	check(total > 0, "torquemada casts a cleanse in a battle against crowd control (S1 %d, S3 %d)" % [int(a.casts[0]), int(a.casts[2])])
	check(int(a.casts[0]) == 0 or float(a.purpose[0]) / float(a.casts[0]) >= 0.6, "most fires cleanse someone (%d / %d)" % [int(a.purpose[0]), int(a.casts[0])])
	var dm: Dictionary = _cast_metrics({"ruleset": "deathmatch", "arena_id": "dm_forest_village", "seed": 200478,
		"players": ["torquemada", "giant", "mage", "werewolf", "archer", "hermes"], "kill_target": 99, "max_time": 60.0}, 45.0)
	metrics["live_deathmatch"] = dm
	check(int(dm.casts[0]) == 0 or float(dm.purpose[0]) / float(dm.casts[0]) >= 0.5, "free-for-all: the fire is a self-cleanse that removes something (%d / %d)" % [int(dm.purpose[0]), int(dm.casts[0])])
