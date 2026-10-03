extends SceneTree

# V2 아킬레우스 (achilles) AI scenario checks (H-AI-achilles, DESIGN_V2 §2.7).
# Each section builds a private fixture, asks the tactician for candidates
# and asserts that a skill is proposed when it should be and not when it
# should not. Also covers the enemy side (raised guard, chariot) and the
# observable-but-untargetable chariot.
# Run: --script res://tests/hero_ai_v2_achilles.gd

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
		print("PASS ", label)
	else:
		failed.append(label)
		print("FAIL ", label)
		push_error("HERO_AI_V2_ACHILLES " + label)


func near(a: float, b: float, eps: float = 0.01) -> bool:
	return absf(a - b) <= eps


func arena_fixture(id: String) -> Arena:
	return Arena.from_data({"id": id, "width": 1408, "height": 792,
		"bounds": {"minX": 40, "maxX": 1368, "minY": 40, "maxY": 752}, "obstacles": [], "hazards": []})


# Heroes are placed in roster order: blue first, then red.
func make(blue: Array, red: Array, positions: Array, seed_v: int = 220401) -> BattleSim:
	var sim: BattleSim = BattleSim.new({"blue": blue, "red": red, "arena_id": "classic", "seed": seed_v, "max_time": 150.0})
	sim.arena = arena_fixture("hero_ai_v2_achilles_%d" % seed_v)
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


func shot(u: BUnit, from: Vector2, vel: Vector2, dmg: float, cc: bool = false) -> Dictionary:
	return {"pos": from, "vel": vel, "dmg": dmg, "radius": 8.0, "homing": false, "target": -1,
		"explode": false, "cc": cc, "target_pos": u.pos, "impact_r": 0.0}


func step_until(sim: BattleSim, seconds: float) -> Array:
	var events: Array = []
	for _i in int(ceil(seconds / BattleSim.DT)):
		if sim.state != BattleSim.RUNNING:
			break
		sim.step()
		events.append_array(sim.tick_events)
	return events


func _run() -> void:
	DB.ensure_loaded()
	_doctrine_and_model()
	_guard()
	_guard_facing()
	_roar()
	_chariot()
	_chariot_immunity_contract()
	_chariot_visibility()
	_spear()
	_enemy_side()
	_determinism()
	var result: Dictionary = {"status": "PASS" if failed.is_empty() else "FAIL", "passed": passed, "failed": failed, "metrics": metrics}
	print("HERO_AI_V2_ACHILLES ", JSON.stringify(result))
	quit(0 if failed.is_empty() else 1)


# ------------------------------------------------------------------ data

func _doctrine_and_model() -> void:
	var prof: Dictionary = Doctrine.of("achilles")
	check(not prof.is_empty() and str(prof.get("title", "")) != "" and str(prof.get("code", "")) != "", "doctrine: achilles has title and code")
	var roles: Array = prof.get("roles", [])
	var labelled: bool = not roles.is_empty()
	for r in roles:
		labelled = labelled and Doctrine.ROLE_LABEL.has(str(r))
	check(labelled, "doctrine: every role has a label %s" % str(roles))
	check((prof.get("principles", []) as Array).size() == 4, "doctrine: four principles")
	var tw: Dictionary = prof.get("target", {})
	check(tw.has("low") and tw.has("threat") and tw.has("backline") and tw.has("isolated"), "doctrine: target weights")
	check(str(prof.get("geometry", "")) != "" and not (prof.get("combos", []) as Array).is_empty(), "doctrine: geometry and combos")
	var d: Defs.CharDef = DB.char_def("achilles")
	var st: Dictionary = KitModel.stats_of_def(d)
	var s1: Dictionary = KitModel.evaluate(d.abilities[0].effects, st, {})
	var s2: Dictionary = KitModel.evaluate(d.abilities[1].effects, st, {})
	var s3: Dictionary = KitModel.evaluate(d.abilities[2].effects, st, {})
	var s4: Dictionary = KitModel.evaluate(d.abilities[3].effects, st, {})
	check(near(float(s1.true_dmg), 75.0 + 0.35 * 70.0) and near(KitModel.mitigate(s1, 200.0, 0.0), float(s1.true_dmg)), "kit model: S1 true damage ignores armour")
	check(near(float(s2.get("front_guard_dur", 0.0)), 2.0) and near(float(s2.get("guard_arc", 0.0)), deg_to_rad(120.0), 1e-4) and near(float(s2.get("guard_slow", 0.0)), 0.35), "kit model: S2 front guard (2 s, 120 deg, -35 %)")
	check(near(float(s3.get("tenacity_loss", 0.0)), 0.1) and near(float(s3.get("roar_dur", 0.0)), 6.0) and near(float(s3.get("roar_reach_ffa", 0.0)), 900.0), "kit model: S3 roar (tenacity -0.10, 6 s, 900 in free-for-all)")
	check(near(float(s4.get("knocks", 0.0)), 2.0) and near(float(s4.get("knock_dmg", 0.0)), 30.0 + 0.3 * 70.0) and near(float(s4.displace), 130.0), "kit model: S4 chariot (2 knocks of 130, 30+0.3AD)")
	var old: Dictionary = KitModel.evaluate(DB.char_def("baseball").abilities[1].effects, KitModel.stats_of_def(DB.char_def("baseball")), {})
	check(not old.has("front_guard_dur") and not old.has("knocks") and not old.has("tenacity_loss"), "kit model: existing kits get no new keys")
	var f: Dictionary = DraftDirector.kit_features(d)
	metrics["draft_features"] = {"control": f.control, "protection": f.protection, "projectile_answer": f.projectile_answer, "damage": f.damage}
	check(float(f.projectile_answer) == 1.0 and float(f.protection) >= 0.35 and float(f.control) > 0.1, "draft: front guard answers projectiles, chariot and roar add control")
	check(ItemValuation.BASIC_SHARE.has("achilles") and float(ItemValuation.BASIC_SHARE.achilles) > 0.0 and float(ItemValuation.BASIC_SHARE.achilles) < 1.0, "items: BASIC_SHARE has achilles")


# ------------------------------------------------------------------ S2

func _guard() -> void:
	var far: Array = [Vector2(500, 400), Vector2(300, 620), Vector2(1250, 150), Vector2(1260, 400), Vector2(1250, 680)]
	var sim: BattleSim = make(["achilles", "archer"], ["sniper", "mage", "giant"], far)
	var u: BUnit = sim.heroes[0]
	var b: TacticianBrain = brain_for(sim)
	check(slot_rows(cands(b, u), 1).is_empty(), "S2: no guard without a frontal threat")
	b.intel.projectiles = [shot(u, u.pos + Vector2(150, 0), Vector2(-900, 0), 200.0, true)]
	b._danger_cache.clear()
	var rows: Array = slot_rows(cands(b, u), 1)
	check(rows.size() == 1, "S2: guard against a projectile in flight toward him")
	if rows.size() == 1:
		var aim: Vector2 = rows[0].cmd.pos
		check((aim - u.pos).normalized().dot(Vector2.RIGHT) > 0.95, "S2: guard aimed at the incoming projectile")
		metrics["guard_projectile_value"] = rows[0].value
	# The whole decision picks the guard.
	b.decide(u)
	check(str(u.command.get("kind", "")) == "ability" and int(u.command.get("index", -1)) == 1, "S2: the decision raises the guard (%s)" % str(u.command.get("purpose", "")))
	# The AI order really blocks: cast it and fire from the same side.
	if rows.size() == 1:
		var started: bool = sim.start_ability(u, 1, null, rows[0].cmd.pos, rows[0].cmd)
		step_until(sim, 0.15)
		var g: ST.Status = sim.get_status(u, &"frontGuard")
		check(started and g != null and (g.extra.dir as Vector2).dot(Vector2.RIGHT) > 0.95, "S2: the AI command raises the guard toward the threat")
		var pa: Defs.AbilityDef = Defs.AbilityDef.new()
		pa.speed = 900.0
		pa.range = 500.0
		pa.width = 8.0
		pa.id = "test_shot"
		var hp0: float = u.hp
		var shooter: BUnit = sim.heroes[3]
		shooter.pos = u.pos + Vector2(300, 10)
		shooter.prev_pos = shooter.pos
		sim.proj.spawn(shooter, u, u.pos, pa, [{"type": "damage", "school": "true", "base": 60.0}], {"source_type": "ABILITY", "team": 1})
		var blocked: bool = false
		for ev in step_until(sim, 1.2):
			if str(ev.type) == "PROJECTILE_BLOCKED" and str(ev.get("reason", "")) == "front_guard":
				blocked = true
		check(blocked and near(u.hp, hp0), "S2: the frontal shot is consumed by the AI's guard")
	# A shot passing wide is no reason.
	var sim2: BattleSim = make(["achilles", "archer"], ["sniper", "mage", "giant"], far, 220402)
	var u2: BUnit = sim2.heroes[0]
	var b2: TacticianBrain = brain_for(sim2)
	b2.intel.projectiles = [shot(u2, u2.pos + Vector2(150, 120), Vector2(-900, 0), 200.0, true), shot(u2, u2.pos + Vector2(-150, 0), Vector2(-900, 0), 200.0)]
	b2._danger_cache.clear()
	check(slot_rows(cands(b2, u2), 1).is_empty(), "S2: no guard for shots that miss or fly away")
	b.dispose()
	sim.dispose()
	b2.dispose()
	sim2.dispose()
	# Melee and ready bursts in front.
	var sim3: BattleSim = make(["achilles", "archer"], ["swordsman", "werewolf", "mage"],
		[Vector2(500, 400), Vector2(300, 620), Vector2(565, 385), Vector2(568, 430), Vector2(1250, 150)], 220403)
	var u3: BUnit = sim3.heroes[0]
	var b3: TacticianBrain = brain_for(sim3)
	var rows3: Array = slot_rows(cands(b3, u3), 1)
	check(rows3.size() == 1, "S2: guard against melee and ready bursts in front")
	if rows3.size() == 1:
		check(((rows3[0].cmd.pos as Vector2) - u3.pos).normalized().dot(Vector2.RIGHT) > 0.8, "S2: guard faces the melee pair")
		metrics["guard_melee_value"] = rows3[0].value
	b3.dispose()
	sim3.dispose()
	# The bigger threat decides the side: a melee pair behind, a light shot ahead.
	var sim4: BattleSim = make(["achilles", "archer"], ["swordsman", "werewolf", "mage"],
		[Vector2(500, 400), Vector2(300, 650), Vector2(435, 385), Vector2(432, 430), Vector2(1250, 150)], 220404)
	var u4: BUnit = sim4.heroes[0]
	var b4: TacticianBrain = brain_for(sim4)
	b4.intel.projectiles = [shot(u4, u4.pos + Vector2(200, 0), Vector2(-900, 0), 30.0)]
	b4._danger_cache.clear()
	var rows4: Array = slot_rows(cands(b4, u4), 1)
	check(rows4.size() == 1 and ((rows4[0].cmd.pos as Vector2) - u4.pos).normalized().dot(Vector2.LEFT) > 0.8, "S2: the guard turns to the bigger threat behind")
	# Already guarding: no recast candidate.
	sim4.push_status(u4, &"frontGuard", u4.idx, 2.0, {"dir": Vector2.LEFT, "arc": deg_to_rad(120.0)})
	u4.cooldowns[1] = sim4.time
	check(slot_rows(cands(b4, u4), 1).is_empty(), "S2: no candidate while the guard is up")
	b4.dispose()
	sim4.dispose()


func _guard_facing() -> void:
	var sim: BattleSim = make(["achilles", "archer"], ["swordsman", "mage", "giant"],
		[Vector2(500, 400), Vector2(300, 650), Vector2(600, 400), Vector2(1250, 150), Vector2(1250, 680)], 220405)
	var u: BUnit = sim.heroes[0]
	sim.push_status(u, &"frontGuard", u.idx, 2.0, {"dir": Vector2.RIGHT, "arc": deg_to_rad(120.0)})
	u.facing = Vector2.RIGHT
	var b: TacticianBrain = brain_for(sim)
	var ctx: Dictionary = b._ctx(u)
	var past: Dictionary = {"value": 50.0, "key": "m1", "cmd": {"kind": "move", "goal": Vector2(700, 400)}}
	var back: Dictionary = {"value": 50.0, "key": "m2", "cmd": {"kind": "move", "goal": Vector2(440, 410)}}
	var side: Dictionary = {"value": 50.0, "key": "m3", "cmd": {"kind": "move", "goal": Vector2(560, 520)}}
	Doctrine.adjust(b, u, ctx, [past, back, side])
	check(has_note(past, "방패 정면 유지") and float(past.value) < 0.0, "S2: a move past the threat (turning the back to it) is penalised")
	check(not has_note(back, "방패 정면 유지") and near(float(back.value), 50.0), "S2: backpedalling with the threat in front is free")
	check(has_note(side, "방패 정면 유지"), "S2: a move that leaves the threat on the side is penalised")
	# The tactician's own move options: whatever it prefers keeps the threat in the arc.
	var out: Array = []
	b._move_candidates(u, ctx, out)
	Doctrine.adjust(b, u, ctx, out)
	var top: Dictionary = best(out)
	var goal: Vector2 = top.cmd.get("goal", u.pos) if not top.is_empty() else u.pos
	var to_t: Vector2 = sim.heroes[2].pos - goal
	check(not top.is_empty() and (to_t.length() < 1.0 or to_t.normalized().dot(Vector2.RIGHT) >= cos(deg_to_rad(60.0)) - 0.02), "S2: the chosen move keeps the main threat inside the arc (%s)" % str(top.get("label", "")))
	# Without the guard the same moves carry no such note.
	sim.remove_statuses_where(u, func(x): return x.type == &"frontGuard")
	var free: Dictionary = {"value": 50.0, "key": "m1", "cmd": {"kind": "move", "goal": Vector2(700, 400)}}
	Doctrine.adjust(b, u, b._ctx(u), [free])
	check(not has_note(free, "방패 정면 유지"), "S2: no facing constraint without the guard")
	b.dispose()
	sim.dispose()


# ------------------------------------------------------------------ S3

func _roar() -> void:
	var pos: Array = [Vector2(500, 400), Vector2(430, 470), Vector2(620, 400), Vector2(700, 330), Vector2(1250, 700)]
	# Ally mage with a ready root in reach; S4 on cooldown.
	var sim: BattleSim = make(["achilles", "mage"], ["swordsman", "archer", "giant"], pos, 220410)
	var u: BUnit = sim.heroes[0]
	u.cooldowns[3] = sim.time + 30.0
	var b: TacticianBrain = brain_for(sim)
	var rows: Array = slot_rows(cands(b, u), 2)
	check(rows.size() == 1 and float(rows[0].parts.get("제어 연장", 0.0)) > 0.0, "S3: roar when an ally's ready control will land in 6 s")
	if rows.size() == 1:
		metrics["roar_with_mage_root"] = rows[0].value
	# The same ally with its control on cooldown: no roar.
	var mage: BUnit = sim.heroes[1]
	for j in mage.cooldowns.size():
		mage.cooldowns[j] = sim.time + 30.0
	b._plan()
	check(slot_rows(cands(b, u), 2).is_empty(), "S3: no roar while allied control is on cooldown and S4 is down")
	# A cast in progress counts even with the cooldown already started.
	mage.cooldowns[0] = sim.time + 7.0
	var act: ST.Action = ST.Action.new()
	act.kind = "ability"
	act.ability = mage.def.abilities[0]
	act.ability_index = 0
	act.windup = true
	act.resolve_at = sim.time + 0.2
	act.recover_at = sim.time + 0.4
	mage.action = act
	check(slot_rows(cands(b, u), 2).size() == 1, "S3: roar when an ally is winding up a control")
	mage.action = null
	b.dispose()
	sim.dispose()
	# No control in the team (archer ally), S4 down: no roar.
	var sim2: BattleSim = make(["achilles", "archer"], ["swordsman", "mage", "giant"], pos, 220411)
	var u2: BUnit = sim2.heroes[0]
	u2.cooldowns[3] = sim2.time + 30.0
	var b2: TacticianBrain = brain_for(sim2)
	check(slot_rows(cands(b2, u2), 2).is_empty(), "S3: no roar without allied control or S4")
	# Right before S4: roar is proposed and outranks the chariot (S3 → S4).
	u2.cooldowns[3] = sim2.time
	var rows2: Array = cands(b2, u2)
	var roar2: Array = slot_rows(rows2, 2)
	var char2: Array = slot_rows(rows2, 3)
	check(roar2.size() == 1 and float(roar2[0].parts.get("전차 연계", 0.0)) > 0.0, "S3: roar right before a ready S4")
	check(char2.size() == 1 and has_note(char2[0], "포효 먼저"), "S4: waits for the roar when S3 is ready")
	check(roar2.size() == 1 and char2.size() == 1 and float(roar2[0].value) > float(char2[0].value), "S3 → S4: roar outranks the chariot")
	u2.cooldowns[2] = sim2.time + 16.0
	var char3: Array = slot_rows(cands(b2, u2), 3)
	check(char3.size() == 1 and not has_note(char3[0], "포효 먼저"), "S4: goes once the roar is spent")
	b2.dispose()
	sim2.dispose()
	# Hidden enemies are not counted: nothing seen near the root, no roar.
	var hidden: Array = [Vector2(150, 400), Vector2(120, 470), Vector2(1250, 400), Vector2(1260, 330), Vector2(1250, 700)]
	var sim3: BattleSim = make(["achilles", "mage"], ["swordsman", "archer", "giant"], hidden, 220412)
	var u3: BUnit = sim3.heroes[0]
	u3.cooldowns[3] = sim3.time + 30.0
	var b3: TacticianBrain = brain_for(sim3)
	var seen_any: bool = false
	for e in [sim3.heroes[2], sim3.heroes[3], sim3.heroes[4]]:
		seen_any = seen_any or sim3.is_seen(0, e)
	check(not seen_any and slot_rows(cands(b3, u3), 2).is_empty(), "S3: unseen enemies give the roar no value (team knowledge only)")
	b3.dispose()
	sim3.dispose()


# ------------------------------------------------------------------ S4

func _chariot_value(n_seen: int, seed_v: int) -> Array:
	var pos: Array = [Vector2(500, 400), Vector2(420, 470), Vector2(640, 380), Vector2(650, 450), Vector2(700, 330)]
	for k in range(n_seen, 3):
		pos[2 + k] = Vector2(1300, 120 + 280 * k)
	var sim: BattleSim = make(["achilles", "archer"], ["swordsman", "mage", "sniper"], pos, seed_v)
	var u: BUnit = sim.heroes[0]
	u.cooldowns[2] = sim.time + 16.0
	var b: TacticianBrain = brain_for(sim)
	var seen: int = 0
	for k in 3:
		if sim.is_seen(0, sim.heroes[2 + k]):
			seen += 1
	var rows: Array = slot_rows(cands(b, u), 3)
	b.dispose()
	sim.dispose()
	return [seen, rows]


func _chariot() -> void:
	var three: Array = _chariot_value(3, 220420)
	var two: Array = _chariot_value(2, 220421)
	var one: Array = _chariot_value(1, 220422)
	check(int(three[0]) == 3 and int(two[0]) == 2 and int(one[0]) == 1, "S4 fixtures: 3 / 2 / 1 enemies seen")
	var v3: float = float((three[1] as Array)[0].value) if (three[1] as Array).size() == 1 else -1.0
	var v2: float = float((two[1] as Array)[0].value) if (two[1] as Array).size() == 1 else -1.0
	metrics["chariot_value_3_2_1"] = [v3, v2, (one[1] as Array).size()]
	check(v3 > 0.0 and v2 > 0.0, "S4: chariot with two or more seen enemies")
	check(v3 > v2, "S4: more seen enemies, more knock value (%.0f > %.0f)" % [v3, v2])
	check((one[1] as Array).is_empty(), "S4: no chariot for a single seen enemy")
	# Nobody in sight: no chariot.
	var none: Array = _chariot_value(0, 220423)
	check(int(none[0]) == 0 and (none[1] as Array).is_empty(), "S4: no chariot without seen enemies")


func _chariot_immunity_contract() -> void:
	var sim: BattleSim = make(["achilles"], ["politician"], [Vector2(500, 400), Vector2(620, 400)])
	var u: BUnit = sim.heroes[0]
	var target: BUnit = sim.heroes[1]
	var b: TacticianBrain = brain_for(sim)
	var a: Defs.AbilityDef = u.def.abilities[3]
	var ctx: Dictionary = b._ctx(u)
	var belief: TeamIntel.EnemyBelief = b.intel.enemies[target.idx]
	var normal: Dictionary = AchillesTactics.chariot_plan(b, u, a, ctx)
	target.ks["contemplating"] = true
	target.ks["contemplation_pos"] = target.pos
	sim.push_status(target, &"contemplation", target.idx, 5.0)
	b.intel.observe()
	var immune: Dictionary = AchillesTactics.chariot_plan(b, u, a, ctx)
	var ev: Dictionary = KitModel.evaluate(a.effects, ctx.st, {})
	var expected_delta: float = AchillesTactics.KNOCK_BASE * float(ev.knocks) * b._ew(belief.idx) * 0.3
	check(float(immune.value) > 0.0 and near(float(normal.value) - float(immune.value), expected_delta),
		"chariot keeps contact damage but gives contemplation zero knockback value")
	for effect in a.effects:
		if str(effect.get("type", "")) == "summon":
			sim.kits.spawn_summons(u, effect, {"ability": a, "team": u.team})
	var chariots: Array[BUnit] = sim.kits.owned_entities(u, "chariot")
	check(chariots.size() == 1, "chariot immunity fixture has its actual summon")
	if not chariots.is_empty():
		var chariot: BUnit = chariots[0]
		chariot.pos = target.pos + Vector2(10, 0)
		var hp_before: float = target.hp
		sim.kits._chariot_step(chariot, u, 0.0)
		check(target.hp < hp_before and target.motion == null and int(chariot.ks.knocks.get(target.idx, 0)) == 0,
			"real chariot damages contemplation without moving it or recording a knockback")
	belief.statuses = [{"type": "unstoppable", "remaining": 3.0}]
	var unstoppable: Dictionary = AchillesTactics.chariot_plan(b, u, a, ctx)
	check(not unstoppable.is_empty() and near(float(unstoppable.value), float(immune.value)),
		"unstoppable also retains damage while removing the same knockback value")
	b.dispose()
	sim.dispose()


func _chariot_visibility() -> void:
	var sim: BattleSim = make(["achilles", "archer"], ["swordsman", "mage", "sniper"],
		[Vector2(400, 400), Vector2(320, 470), Vector2(560, 380), Vector2(620, 460), Vector2(700, 330)], 220430)
	var u: BUnit = sim.heroes[0]
	var started: bool = sim.start_ability(u, 3, u, u.pos)
	step_until(sim, 0.6)
	var ch: BUnit = null
	for e in sim.entities:
		if e.alive and e.kind == "chariot":
			ch = e
	check(started and ch != null, "chariot: S4 summons it")
	if ch == null:
		sim.dispose()
		return
	sim._update_visibility()
	var sw: BUnit = sim.heroes[2]
	check(sim.is_seen(1, ch) and sim.observes(sw, ch), "chariot: enemies see it (visible_untargetable)")
	check(not sim.opponents(sw).has(ch), "chariot: still not in opponents()")
	check(not sim.target_legal(sw, sw.def.abilities[0], ch), "chariot: abilities cannot target it")
	ch.pos = sw.pos + Vector2(40, 0)
	check(not sim.start_basic(sw, ch), "chariot: basic attacks cannot target it")
	var nl: int = sim.debug_visibility_mismatch()
	check(nl == 0, "chariot: fast and exhaustive visibility agree (%d)" % nl)
	# The enemy team's beliefs: a danger, never a target.
	var b1: TacticianBrain = brain_for(sim, 1)
	refresh(sim, b1)
	var eb: TeamIntel.EnemyBelief = b1.intel.entities.get(ch.idx)
	check(eb != null and eb.kind == "chariot" and eb.untargetable, "chariot: enemy intel believes a chariot (kind copied, untargetable)")
	var listed: bool = false
	for x in b1.intel.visible_enemies(true):
		listed = listed or (x as TeamIntel.EnemyBelief).idx == ch.idx
	check(not listed, "chariot: never in the enemy's target lists")
	var aimed: bool = false
	for hero_i in [2, 3, 4]:
		var e2: BUnit = sim.heroes[hero_i]
		var rows: Array = cands(b1, e2, true, true)
		for c in rows:
			aimed = aimed or int(c.cmd.get("target", -1)) == ch.idx
	check(not aimed, "chariot: no enemy candidate aims at it")
	if eb:
		var prey: BUnit = null
		for hero_i2 in [2, 3, 4]:
			var e3: BUnit = sim.heroes[hero_i2]
			if prey == null or e3.pos.distance_to(ch.pos) < prey.pos.distance_to(ch.pos):
				prey = e3
		var on_path: float = AchillesTactics.chariot_danger(b1, prey, eb, prey.pos, 1.0)
		var far_p: float = AchillesTactics.chariot_danger(b1, prey, eb, ch.pos + (prey.pos - ch.pos).normalized() * -700.0, 1.0)
		check(on_path > 0.0 and on_path > far_p, "chariot: its predicted prey sees danger at its own position (%.0f > %.0f)" % [on_path, far_p])
		b1._danger_cache.clear()
		check(b1.danger_at(prey, prey.pos, 1.0) >= on_path, "chariot: danger_at includes the chariot")
		b1.intel.chariot_knocks[ch.idx] = {prey.idx: 2}
		check(near(AchillesTactics.chariot_danger(b1, prey, eb, prey.pos, 1.0), 0.0), "chariot: a hero knocked twice is safe")
		b1.intel.chariot_knocks.erase(ch.idx)
	b1.dispose()
	sim.dispose()
	# Knocks the team took are counted from public CHARIOT_KNOCK events.
	var sim2: BattleSim = make(["achilles", "archer"], ["swordsman", "mage", "sniper"],
		[Vector2(400, 400), Vector2(320, 470), Vector2(560, 380), Vector2(620, 460), Vector2(700, 330)], 220431)
	var u2: BUnit = sim2.heroes[0]
	var b2: TacticianBrain = brain_for(sim2, 1)
	sim2.start_ability(u2, 3, u2, u2.pos)
	var truth: Dictionary = {}
	for _i in int(6.0 / BattleSim.DT):
		sim2.step()
		b2.intel.ingest(sim2.tick_events)
		for ev in sim2.tick_events:
			if str(ev.type) == "CHARIOT_KNOCK":
				truth[int(ev.g)] = int(truth.get(int(ev.g), 0)) + 1
	var counted: Dictionary = {}
	for k in b2.intel.chariot_knocks:
		var per: Dictionary = b2.intel.chariot_knocks[k]
		for g in per:
			counted[int(g)] = int(counted.get(int(g), 0)) + int(per[g])
	metrics["chariot_knocks"] = truth
	check(not truth.is_empty() and counted == truth, "chariot: enemy intel counts its own knocks %s" % str(counted))
	b2.dispose()
	sim2.dispose()


# ------------------------------------------------------------------ S1

func _spear_value(line: bool, seed_v: int) -> float:
	var second: Vector2 = Vector2(700, 402) if line else Vector2(690, 560)
	var sim: BattleSim = make(["achilles", "archer"], ["mage", "sniper", "giant"],
		[Vector2(500, 400), Vector2(320, 600), Vector2(610, 400), second, Vector2(1250, 120)], seed_v)
	var u: BUnit = sim.heroes[0]
	for j in [1, 2, 3]:
		u.cooldowns[j] = sim.time + 30.0
	var b: TacticianBrain = brain_for(sim)
	var v: float = -1.0
	for c in slot_rows(cands(b, u, false), 0):
		if int(c.cmd.get("target", -1)) == sim.heroes[2].idx:
			v = float(c.value)
	b.dispose()
	sim.dispose()
	return v


func _spear() -> void:
	var single: float = _spear_value(false, 220440)
	var lined: float = _spear_value(true, 220441)
	metrics["spear_single_vs_line"] = [single, lined]
	check(single > 0.0, "S1: spear on a single enemy in reach")
	check(lined > single + 30.0, "S1: a second enemy on the line raises the spear's value (%.0f > %.0f)" % [lined, single])
	# True damage: the same damage on any armour, and a bonus on armour.
	var sim: BattleSim = make(["achilles", "archer"], ["mage", "giant", "sniper"],
		[Vector2(500, 400), Vector2(320, 600), Vector2(640, 330), Vector2(640, 470), Vector2(1250, 120)], 220442)
	var u: BUnit = sim.heroes[0]
	var b: TacticianBrain = brain_for(sim)
	var ctx: Dictionary = b._ctx(u)
	var a: Defs.AbilityDef = u.def.abilities[0]
	var mage: TeamIntel.EnemyBelief = b.intel.enemies[sim.heroes[2].idx]
	var giant: TeamIntel.EnemyBelief = b.intel.enemies[sim.heroes[3].idx]
	var em: Dictionary = b._enemy_value(u, a, mage, ctx, 1.0)
	var eg: Dictionary = b._enemy_value(u, a, giant, ctx, 1.0)
	check(near(float(em.dmg), float(eg.dmg), 0.01), "S1: true damage is the same on 18 and 42 armour (%.1f)" % float(em.dmg))
	var sm: float = AchillesTactics.special_enemy(b, u, a, mage, mage.pos, ctx, em)
	var sg: float = AchillesTactics.special_enemy(b, u, a, giant, giant.pos, ctx, eg)
	check(sg > sm and sm > 0.0, "S1: true damage is worth more against high armour (%.1f > %.1f)" % [sg, sm])
	b.dispose()
	sim.dispose()


# ------------------------------------------------------------------ enemy side

func _guarded(attacker_pos: Vector2, cast_ago: float, seed_v: int) -> Dictionary:
	var sim: BattleSim = make(["swordsman", "archer"], ["achilles", "mage", "giant"],
		[attacker_pos, Vector2(250, 650), Vector2(600, 400), Vector2(1250, 150), Vector2(1250, 680)], seed_v)
	var sw: BUnit = sim.heroes[0]
	var ach: BUnit = sim.heroes[2]
	sw.facing = (ach.pos - sw.pos).normalized()
	ach.facing = Vector2.LEFT
	sim.push_status(ach, &"frontGuard", ach.idx, maxf(0.05, 2.0 - cast_ago), {"dir": Vector2.LEFT, "arc": deg_to_rad(120.0)})
	var b: TacticianBrain = brain_for(sim)
	var eb: TeamIntel.EnemyBelief = b.intel.enemies[ach.idx]
	eb.cd_last[1] = sim.time - cast_ago - 0.05
	var ctx: Dictionary = b._ctx(sw)
	var a: Defs.AbilityDef = sw.def.abilities[1]
	var k: float = AchillesTactics.guard_factor(b, sw, a, eb)
	var ev: Dictionary = b._enemy_value(sw, a, eb, ctx, 1.0)
	var basics: Array = []
	b._basic_candidates(sw, ctx, basics)
	var side: Dictionary = {"value": 30.0, "key": "s", "cmd": {"kind": "move", "goal": ach.pos + Vector2(0, 70)}}
	var front: Dictionary = {"value": 30.0, "key": "f", "cmd": {"kind": "move", "goal": ach.pos + Vector2(-70, 0)}}
	var all: Array = basics.duplicate()
	all.append(side)
	all.append(front)
	Doctrine.adjust(b, sw, ctx, all)
	var basic_note: bool = false
	for c in basics:
		if int(c.cmd.get("target", -1)) == ach.idx:
			basic_note = has_note(c, "방패 정면 공격 무효")
	# An area dropped on his position is tested from its centre, not the caster.
	var drop: Defs.AbilityDef = Defs.AbilityDef.new()
	drop.id = "test_drop"
	drop.target = "position"
	drop.delivery = "area"
	drop.cast_time = 0.2
	drop.effects = [{"type": "damage", "school": "magic", "base": 80.0}]
	var k_drop: float = AchillesTactics.guard_factor(b, sw, drop, eb)
	var out: Dictionary = {"k": k, "k_drop": k_drop, "dmg": float(ev.dmg), "basic_note": basic_note, "side": has_note(side, "방패 측면 공략"), "front": has_note(front, "방패 측면 공략"), "seen": eb.visible and eb.has_status("frontGuard")}
	b.dispose()
	sim.dispose()
	return out


func _enemy_side() -> void:
	var front: Dictionary = _guarded(Vector2(530, 400), 0.1, 220450)
	var behind: Dictionary = _guarded(Vector2(670, 400), 0.1, 220451)
	var late: Dictionary = _guarded(Vector2(530, 400), 1.98, 220452)
	metrics["enemy_guard"] = {"front": front, "behind": behind, "late": late}
	check(bool(front.seen), "enemy side: the raised guard is seen (status + facing)")
	check(float(front.k) < 0.1 and float(front.dmg) < float(behind.dmg) * 0.1, "enemy side: frontal ability hits on the guard are wasted (%.1f vs %.1f)" % [float(front.dmg), float(behind.dmg)])
	check(near(float(behind.k), 1.0) and float(behind.dmg) > 0.0, "enemy side: hits from behind keep their value")
	check(near(float(late.k), 1.0), "enemy side: a guard about to end does not void the hit")
	check(bool(front.basic_note) and not bool(behind.basic_note), "enemy side: frontal basic attacks into the guard are discouraged, rear ones are not")
	check(bool(front.side) and not bool(front.front), "enemy side: melee prefers moving to the guard's side")
	check(near(float(front.k_drop), float(behind.k_drop)) and float(front.k_drop) > 0.3 and float(front.k_drop) < 1.0 and near(float(late.k_drop), 1.0), "enemy side: an area dropped on him is judged from its centre, not the caster's side (%.2f)" % float(front.k_drop))


# ------------------------------------------------------------------ determinism

func _battle(seed_v: int) -> Dictionary:
	var sim: BattleSim = BattleSim.new({"blue": ["achilles", "mage", "archer"], "red": ["swordsman", "giant", "sniper"], "arena_id": "classic", "seed": seed_v, "max_time": 60.0})
	for t in 2:
		sim.controllers[t] = AIFactory.make("tactician", sim, t)
	sim.start()
	var casts: Dictionary = {}
	var blocked: int = 0
	var knocks: int = 0
	var ach: BUnit = sim.heroes[0]
	while sim.state == BattleSim.RUNNING:
		sim.step()
		for ev in sim.tick_events:
			var ty: String = str(ev.type)
			if ty == "CAST_STARTED" and int(ev.s) == ach.idx:
				var key: String = "S%d" % int(ev.get("slot", 0))
				casts[key] = int(casts.get(key, 0)) + 1
			elif ty == "FRONT_BLOCKED" and int(ev.g) == ach.idx:
				blocked += 1
			elif ty == "CHARIOT_KNOCK" and int(ev.s) == ach.idx:
				knocks += 1
	var state: Array = []
	for u in sim.heroes:
		state.append([u.id, snappedf(u.hp, 0.001), snappedf(u.pos.x, 0.001), snappedf(u.pos.y, 0.001), u.st_casts])
	var out: Dictionary = {"sig": JSON.stringify([sim.winner, snappedf(sim.time, 0.001), state]).sha256_text(), "casts": casts, "blocked": blocked, "knocks": knocks}
	sim.dispose()
	return out


func _determinism() -> void:
	var a: Dictionary = _battle(220460)
	var b: Dictionary = _battle(220460)
	metrics["battle"] = {"casts": a.casts, "front_blocked": a.blocked, "knocks": a.knocks}
	check(str(a.sig) == str(b.sig), "determinism: the same seed replays the same battle")
	check(not (a.casts as Dictionary).is_empty(), "battle: achilles casts skills under the tactician %s" % str(a.casts))
