extends SceneTree

# V1.5.3 per-hero AI regression checks (key: ai_heroes).
# Each section reproduces a finding of zz_work/audit/audit_heroes_a.md,
# audit_heroes_b.md, audit_ai_core.md (D2, D6, D7, D8, D9, D13) or
# audit_mode_layers.md (DM-4) in a private fixture and asserts the fixed
# behaviour. Run: --script res://tests/ai_heroes_153.gd

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
		push_error("AI_HEROES_153 " + label)


func arena_fixture(id: String, obstacles: Array = [], forests: Array = []) -> Arena:
	return Arena.from_data({"id": id, "width": 1408, "height": 792,
		"bounds": {"minX": 40, "maxX": 1368, "minY": 40, "maxY": 752}, "obstacles": obstacles, "hazards": [], "forests": forests})


# Heroes are placed in roster order: blue first, then red.
func make(blue: Array, red: Array, positions: Array, obstacles: Array = [], seed_v: int = 153301, forests: Array = []) -> BattleSim:
	var sim: BattleSim = BattleSim.new({"blue": blue, "red": red, "arena_id": "classic", "seed": seed_v, "max_time": 150.0})
	sim.arena = arena_fixture("ai_heroes_%d_%d_%d" % [seed_v, obstacles.size(), forests.size()], obstacles, forests)
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


func set_hp(sim: BattleSim, u: BUnit, ratio: float) -> void:
	u.hp = sim.max_hp(u) * ratio


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


func note_delta(c: Dictionary, text: String) -> float:
	for n in c.get("notes", []):
		var s: String = str(n)
		if s.contains(text):
			return float(s.get_slice(" ", s.get_slice_count(" ") - 1))
	return 0.0


func unit(sim: BattleSim, id: String, team: int) -> BUnit:
	for u: BUnit in sim.heroes:
		if u.def.id == id and u.team == team:
			return u
	return null


func _run() -> void:
	DB.ensure_loaded()
	_werewolf()
	_swordsman()
	_archer()
	_pirate()
	_aphrodite()
	_blood_mage_and_baseball()
	_joker_and_homing()
	_metatron()
	_plague()
	_hive()
	_nitro()
	_dimensionalist()
	_hermes()
	_world_tree()
	_torturer()
	_engineer()
	_politician()
	_intel_models()
	_core_items()
	_extra_checks()
	var result: Dictionary = {"status": "PASS" if failed.is_empty() else "FAIL", "passed": passed, "failed": failed, "metrics": metrics}
	print("AI_HEROES_153 ", JSON.stringify(result))
	quit(0 if failed.is_empty() else 1)


# ------------------------------------------------------------------ werewolf
func _werewolf() -> void:
	# S1 gate on the game rule: any hero the werewolf itself sees at <= 40%.
	var sim: BattleSim = make(["werewolf", "archer"], ["mage", "giant"],
		[Vector2(500, 400), Vector2(420, 460), Vector2(880, 400), Vector2(980, 560)])
	var ww: BUnit = unit(sim, "werewolf", 0)
	var mg: BUnit = unit(sim, "mage", 1)
	set_hp(sim, mg, 0.33)
	var b: TacticianBrain = brain_for(sim)
	b.plan.focus = unit(sim, "giant", 1).idx
	var s1: Array = slot_rows(cands(b, ww), 0)
	check(not s1.is_empty() and float(best(s1).value) > 0.0, "werewolf S1 is a candidate for a 33% prey 380 px away that is not the focus")
	set_hp(sim, mg, 0.43)
	refresh(sim, b)
	b.plan.focus = mg.idx
	var s1b: Array = slot_rows(cands(b, ww), 0)
	check(s1b.is_empty() or float(best(s1b).value) <= 0.0, "werewolf S1 threshold is 40%: a 43% target gives no scent candidate")
	b.dispose()
	sim.dispose()
	# S4: the bite suppresses the first enemy body on the line; allies pass.
	for blocker_team in [1, 0]:
		var blue: Array = ["werewolf", "giant"] if blocker_team == 0 else ["werewolf"]
		var red: Array = ["mage", "giant"] if blocker_team == 1 else ["mage"]
		var pos: Array = [Vector2(500, 400), Vector2(590, 402), Vector2(680, 400)] if blocker_team == 0 else [Vector2(500, 400), Vector2(680, 400), Vector2(590, 402)]
		var sim2: BattleSim = make(blue, red, pos)
		var w2: BUnit = unit(sim2, "werewolf", 0)
		var m2: BUnit = unit(sim2, "mage", 1)
		set_hp(sim2, m2, 0.5)
		var b2: TacticianBrain = brain_for(sim2)
		var rows: Array = slot_rows(cands(b2, w2), 3).filter(func(c): return int(c.cmd.get("target", -1)) == m2.idx)
		if blocker_team == 1:
			check(not rows.is_empty() and has_note(rows[0], "다른 적이 먼저 닿음"), "werewolf S4 notes an enemy body in front of its target")
		else:
			check(rows.is_empty() or not has_note(rows[0], "먼저 닿음") and not has_note(rows[0], "막힘"), "werewolf S4 path check ignores allies")
		b2.dispose()
		sim2.dispose()


# ----------------------------------------------------------------- swordsman
func _swordsman() -> void:
	# S1: the dash passes through allies (sw_s1_ally_block, seed 153680).
	var sim: BattleSim = make(["swordsman", "giant"], ["mage"], [Vector2(600, 400), Vector2(680, 404), Vector2(760, 400)])
	var sw: BUnit = unit(sim, "swordsman", 0)
	set_hp(sim, unit(sim, "mage", 1), 0.6)
	var b: TacticianBrain = brain_for(sim)
	var s1: Array = slot_rows(cands(b, sw), 0)
	check(not s1.is_empty() and not has_note(s1[0], "막힘"), "swordsman S1 is not penalised for an allied body on the dash line")
	b.dispose()
	sim.dispose()
	# S2 multi-hit: a second enemy inside the 75° cone adds value.
	var sim2: BattleSim = make(["swordsman"], ["mage", "archer"], [Vector2(600, 400), Vector2(680, 400), Vector2(672, 440)])
	var sw2: BUnit = unit(sim2, "swordsman", 0)
	var mg2: BUnit = unit(sim2, "mage", 1)
	var b2: TacticianBrain = brain_for(sim2)
	var ctx2: Dictionary = b2._ctx(sw2)
	var a2: Defs.AbilityDef = sw2.def.abilities[1]
	var e2: TeamIntel.EnemyBelief = b2.intel.enemies[mg2.idx]
	var aim2: Vector2 = b2.lead_point(sw2.pos, e2, 0.0, a2.cast_time, 0.8)
	var ev2: Dictionary = b2._enemy_value(sw2, a2, e2, ctx2, b2._hit_prob(sw2, a2, e2, aim2))
	var extra: float = b2._special_enemy(sw2, 1, a2, e2, aim2, ctx2, ev2)
	check(extra > 20.0, "swordsman S2 cone values the second enemy inside it (%.0f)" % extra)
	# Ordering: in S2 reach with S2 ready and no mark, S3 waits for the mark.
	var s3: Array = slot_rows(cands(b2, sw2), 2).filter(func(c): return int(c.cmd.get("target", -1)) == mg2.idx)
	check(not s3.is_empty() and has_note(s3[0], "검흔 먼저"), "swordsman S3 in melee waits for the S2 mark")
	b2.dispose()
	sim2.dispose()
	# S4: trace expiry urgency and exemption flag for the team gates.
	var sim3: BattleSim = make(["swordsman", "mage"], ["archer", "sniper"], [Vector2(600, 400), Vector2(470, 420), Vector2(820, 400), Vector2(910, 470)])
	var sw3: BUnit = unit(sim3, "swordsman", 0)
	var ar3: BUnit = unit(sim3, "archer", 1)
	sim3.apply_mark(sw3, ar3, {"status": "bladeTrace", "duration": 1.0, "stacks": 1, "maxStacks": 1, "originOwned": true}, {"action_id": 1})
	var b3: TacticianBrain = brain_for(sim3)
	var s4: Array = slot_rows(cands(b3, sw3), 3)
	check(not s4.is_empty() and note_delta(s4[0], "추적 만료 전 회수") >= 84.0, "swordsman S4 gets at least +60 urgency when the trace has < 1.2 s left")
	check(not s4.is_empty() and bool(s4[0].get("gate_exempt", false)), "swordsman S4 on its own trace is flagged exempt from team gates")
	b3.dispose()
	sim3.dispose()


# -------------------------------------------------------------------- archer
func _archer() -> void:
	for hp in [0.6, 0.15]:
		var sim: BattleSim = make(["archer"], ["swordsman"], [Vector2(500, 400), Vector2(780, 400)])
		set_hp(sim, unit(sim, "swordsman", 1), hp)
		var ar: BUnit = unit(sim, "archer", 0)
		var b: TacticianBrain = brain_for(sim)
		var s3: Array = slot_rows(cands(b, ar), 2)
		if hp > 0.5:
			check(s3.is_empty() or (float(s3[0].value) < 0.0 and has_note(s3[0], "처형 보존")), "archer S3 is held on a 60% target (execute preserved)")
		else:
			check(not s3.is_empty() and float(s3[0].value) > 0.0 and has_note(s3[0], "처형 경계"), "archer S3 fires on a 15% target")
		b.dispose()
		sim.dispose()


# -------------------------------------------------------------------- pirate
func _pirate() -> void:
	# S2 grapple landing next to the mage's friends (pi_s2_landing, seed 153610).
	var sim: BattleSim = make(["pirate", "archer"], ["mage", "werewolf", "giant"],
		[Vector2(500, 400), Vector2(380, 430), Vector2(770, 400), Vector2(820, 350), Vector2(830, 455)], [], 153610)
	var pi: BUnit = unit(sim, "pirate", 0)
	set_hp(sim, unit(sim, "mage", 1), 0.8)
	for k in [0, 2, 3]:
		pi.cooldowns[k] = sim.time + 30.0
	var b: TacticianBrain = brain_for(sim)
	var s2: Array = slot_rows(cands(b, pi), 1).filter(func(c): return int(c.cmd.get("target", -1)) == unit(sim, "mage", 1).idx)
	check(not s2.is_empty() and has_note(s2[0], "갈고리 착지 위험") and float(s2[0].value) < 0.0, "pirate S2 prices the landing beside three enemies")
	b.dispose()
	sim.dispose()
	# S4 cone model (pi_s4_cone, seed 153600): lateral pair vs inline pair.
	for layout in [["lateral", Vector2(780, 362), Vector2(780, 438)], ["inline", Vector2(760, 400), Vector2(830, 400)]]:
		var sim2: BattleSim = make(["pirate"], ["archer", "mage"], [Vector2(560, 400), layout[1], layout[2]], [], 153600)
		var p2: BUnit = unit(sim2, "pirate", 0)
		for k in [0, 1, 2]:
			p2.cooldowns[k] = sim2.time + 30.0
		var b2: TacticianBrain = brain_for(sim2)
		var rows: Array = slot_rows(cands(b2, p2), 3)
		var max_hits: int = -1
		var mid_hits: int = -1
		for c: Dictionary in rows:
			var h: int = int((c.parts as Dictionary).get("부채꼴", -1))
			max_hits = maxi(max_hits, h)
			if (c.cmd.pos as Vector2).distance_to(Vector2(780, 400)) < 4.0:
				mid_hits = h
		if layout[0] == "lateral":
			check(max_hits <= 1 and mid_hits == 0, "pirate S4 cone model: a shot between two lateral enemies hits nobody (max %d, mid %d)" % [max_hits, mid_hits])
		else:
			check(max_hits == 2, "pirate S4 cone model: an inline pair is hit twice")
		b2.dispose()
		sim2.dispose()


# ----------------------------------------------------------------- aphrodite
func _aphrodite() -> void:
	# S2 bed: needed only with injured allies, placed at them.
	for injured in [false, true]:
		var sim: BattleSim = make(["aphrodite", "swordsman", "archer"], ["mage"],
			[Vector2(500, 400), Vector2(580, 330), Vector2(430, 500), Vector2(1250, 660)])
		var ap: BUnit = unit(sim, "aphrodite", 0)
		var arc: BUnit = unit(sim, "archer", 0)
		if injured:
			set_hp(sim, arc, 0.4)
		var b: TacticianBrain = brain_for(sim)
		var s2: Array = slot_rows(cands(b, ap), 1)
		if not injured:
			check(s2.is_empty(), "aphrodite S2 bed is not cast when nobody is injured")
		else:
			var ok: bool = not s2.is_empty() and (s2[0].cmd.pos as Vector2).distance_to(arc.pos) < (s2[0].cmd.pos as Vector2).distance_to(unit(sim, "swordsman", 0).pos)
			check(ok, "aphrodite S2 bed is placed at the injured ally")
		b.dispose()
		sim.dispose()
	# Alone (last hero or deathmatch): the bed heals herself.
	var solo: BattleSim = make(["aphrodite"], ["mage"], [Vector2(500, 400), Vector2(1250, 660)])
	set_hp(solo, solo.heroes[0], 0.45)
	var bs: TacticianBrain = brain_for(solo)
	check(not slot_rows(cands(bs, solo.heroes[0]), 1).is_empty(), "aphrodite S2 bed is cast on herself when alone")
	bs.dispose()
	solo.dispose()
	# S3 kill window (ap_pull, seed 153660): werewolf 55% on a 20% archer.
	var sim3: BattleSim = make(["aphrodite", "werewolf"], ["archer", "mage", "sniper"],
		[Vector2(450, 400), Vector2(700, 400), Vector2(745, 400), Vector2(820, 360), Vector2(840, 450)], [], 153660)
	set_hp(sim3, unit(sim3, "werewolf", 0), 0.55)
	set_hp(sim3, unit(sim3, "archer", 1), 0.2)
	var b3: TacticianBrain = brain_for(sim3)
	var ctx3: Dictionary = b3._ctx(sim3.heroes[0])
	var s3: Array = []
	b3._ally_candidates(sim3.heroes[0], 2, sim3.heroes[0].def.abilities[2], ctx3, s3)
	metrics["aphrodite_pull_value"] = float(s3[0].value) if not s3.is_empty() else 0.0
	check(s3.is_empty() or float(s3[0].value) < 250.0, "aphrodite S3 subtracts the ally's kill window (value %.0f, was 398)" % float(metrics.aphrodite_pull_value))
	b3.dispose()
	sim3.dispose()
	# S4 apple: the ally must see a target itself (wall between ally and enemy).
	var wall: Dictionary = {"id": "w", "shape": "rect", "x": 640, "y": 250, "w": 40, "h": 300}
	var sim4: BattleSim = make(["aphrodite", "swordsman", "sniper"], ["mage"],
		[Vector2(520, 560), Vector2(560, 400), Vector2(760, 600), Vector2(800, 400)], [wall])
	set_hp(sim4, unit(sim4, "mage", 1), 0.3)
	var b4: TacticianBrain = brain_for(sim4)
	b4.plan.go = true
	b4.plan.punish = unit(sim4, "mage", 1).idx
	var ctx4: Dictionary = b4._ctx(sim4.heroes[0])
	var s4: Array = []
	b4._ally_candidates(sim4.heroes[0], 3, sim4.heroes[0].def.abilities[3], ctx4, s4)
	var on_blind: Array = s4.filter(func(c): return int(c.cmd.target) == unit(sim4, "swordsman", 0).idx)
	check(sim4.is_seen(0, unit(sim4, "mage", 1)) and not sim4.observes(unit(sim4, "swordsman", 0), unit(sim4, "mage", 1)) and on_blind.is_empty(),
		"aphrodite S4 apple needs the ally's own sight of a target")
	b4.dispose()
	sim4.dispose()


# ------------------------------------------------------ blood mage, baseball
func _blood_mage_and_baseball() -> void:
	var sim: BattleSim = make(["blood_mage"], ["swordsman"], [Vector2(600, 400), Vector2(700, 400)])
	var bm: BUnit = sim.heroes[0]
	var b: TacticianBrain = brain_for(sim)
	var ctx: Dictionary = b._ctx(bm)
	var rows: Array = []
	b._ally_candidates(bm, 0, bm.def.abilities[0], ctx, rows)
	check(not rows.is_empty() and int(rows[0].cmd.target) == bm.idx, "blood mage S1 links itself when no ally can take it")
	b.dispose()
	sim.dispose()
	var sim2: BattleSim = make(["blood_mage", "swordsman"], ["archer"], [Vector2(600, 400), Vector2(660, 430), Vector2(760, 400)])
	var b2: TacticianBrain = brain_for(sim2)
	var rows2: Array = []
	b2._ally_candidates(sim2.heroes[0], 0, sim2.heroes[0].def.abilities[0], b2._ctx(sim2.heroes[0]), rows2)
	check(not rows2.is_empty() and rows2.all(func(c): return int(c.cmd.target) != sim2.heroes[0].idx), "blood mage S1 prefers an ally over itself")
	b2.dispose()
	sim2.dispose()
	# Baseball S3 alone in a 2v1 melee (bb_s3_solo, seed 153620).
	var sim3: BattleSim = make(["baseball"], ["swordsman", "werewolf"], [Vector2(600, 400), Vector2(650, 380), Vector2(650, 430)], [], 153620)
	set_hp(sim3, sim3.heroes[0], 0.6)
	var b3: TacticianBrain = brain_for(sim3)
	var s3: Array = slot_rows(cands(b3, sim3.heroes[0]), 2)
	check(not s3.is_empty() and float(s3[0].value) > 0.0, "baseball S3 buffs itself when alone under threat")
	b3.dispose()
	sim3.dispose()


# ------------------------------------------------ joker S1, homing shots (X2)
func _joker_and_homing() -> void:
	var sim: BattleSim = make(["joker"], ["archer"], [Vector2(500, 400), Vector2(580, 400)])
	var jk: BUnit = sim.heroes[0]
	var b: TacticianBrain = brain_for(sim)
	var ctx: Dictionary = b._ctx(jk)
	var a: Defs.AbilityDef = jk.def.abilities[0]
	var e: TeamIntel.EnemyBelief = b.intel.enemies[sim.heroes[1].idx]
	var ev: Dictionary = b._enemy_value(jk, a, e, ctx, 0.9)
	var close: float = b._special_enemy(jk, 0, a, e, e.pos, ctx, ev)
	check(close >= float(ev.dmg) * 2.0, "joker S1 counts several knives on a close target")
	b.dispose()
	sim.dispose()
	# Banana / blade through a wall: the team sees the enemy, the caster does not.
	var wall: Dictionary = {"id": "w", "shape": "rect", "x": 540, "y": 250, "w": 40, "h": 300}
	for id in ["joker", "dimensionalist"]:
		var sim2: BattleSim = make([id, "sniper"], ["archer"], [Vector2(450, 400), Vector2(600, 620), Vector2(700, 400)], [wall])
		var u: BUnit = sim2.heroes[0]
		u.resources["shards"] = 30.0
		var b2: TacticianBrain = brain_for(sim2)
		var rows: Array = slot_rows(cands(b2, u), 3)
		check(sim2.is_seen(0, sim2.heroes[2]) and (rows.is_empty() or float(best(rows).value) <= 0.0), "%s S4 homing shot is not cast into a wall" % id)
		b2.dispose()
		sim2.dispose()


# ------------------------------------------------------------------ metatron
func _metatron() -> void:
	var sim: BattleSim = make(["metatron"], ["swordsman", "mage"], [Vector2(420, 400), Vector2(640, 400), Vector2(680, 440)])
	var mt: BUnit = sim.heroes[0]
	var b: TacticianBrain = brain_for(sim)
	b.plan.focus = sim.heroes[1].idx
	var rows: Array = slot_rows(cands(b, mt), 3)
	check(not rows.is_empty() and not mt.ks.has("glide_target") and int((b.mem.get(mt.idx, {}) as Dictionary).get("glide_target", -1)) >= 0,
		"metatron S4 keeps its landing target in brain memory, not in kit state")
	# During the glide steer() flies at the planned target whatever the move
	# order (D10; review 1.5.3: one steering path, no duplicate move point).
	var planned: int = int((b.mem.get(mt.idx, {}) as Dictionary).get("glide_target", -1))
	var gi: int = 3
	b._commit_decision(mt, {"key": "glide", "value": 1.0, "parts": {}, "cmd": {"kind": "ability", "index": gi, "ability_id": mt.def.abilities[gi].id, "pos": mt.pos, "need": 0.0}}, b._ctx(mt))
	mt.ks["glide_until"] = sim.time + 1.0
	b.plan.stance = "DISENGAGE"
	var ctx: Dictionary = b._ctx(mt)
	var moves: Array = []
	b._move_candidates(mt, ctx, moves)
	Doctrine.adjust(b, mt, ctx, moves)
	var top: Dictionary = best(moves)
	mt.command = top.get("cmd", {})
	var pe: BUnit = sim.u_at(planned)
	check(planned >= 0 and int(b._glide_to.get(mt.idx, -1)) == planned and b.steer(mt).normalized().dot((pe.pos - mt.pos).normalized()) > 0.9,
		"metatron glide steers to its target even when the stance turns to disengage")
	check(not moves.any(func(c: Dictionary): return str(c.get("label", "")) == "교리: 활공 착지 유도"), "the glide has one steering path (no duplicate doctrine move point)")
	b.dispose()
	sim.dispose()
	# The glide walks: a landing behind a wall needs a detour it cannot make.
	var wall: Dictionary = {"id": "w", "shape": "rect", "x": 520, "y": 300, "w": 40, "h": 200}
	var sim2: BattleSim = make(["metatron", "sniper"], ["swordsman", "mage"], [Vector2(420, 400), Vector2(560, 600), Vector2(640, 400), Vector2(680, 440)], [wall])
	var b2: TacticianBrain = brain_for(sim2)
	check(sim2.is_seen(0, sim2.heroes[2]) and slot_rows(cands(b2, sim2.heroes[0]), 3).is_empty(), "metatron S4 does not glide at a landing behind a wall")
	b2.dispose()
	sim2.dispose()


# ------------------------------------------------------------- plague doctor
func _plague() -> void:
	for case in ["solo", "ally_230"]:
		var blue: Array = ["plague_doctor"] if case == "solo" else ["plague_doctor", "swordsman"]
		var pos: Array = [Vector2(500, 400)]
		if case != "solo":
			pos.append(Vector2(730, 400))
		pos.append(Vector2(1300, 700))
		var sim: BattleSim = make(blue, ["archer"], pos)
		var doc: BUnit = sim.heroes[0]
		if case == "solo":
			set_hp(sim, doc, 0.25)
		else:
			set_hp(sim, sim.heroes[1], 0.3)
		doc.resources["healBank"] = 350.0
		var b: TacticianBrain = brain_for(sim)
		var rows: Array = slot_rows(cands(b, doc), 1)
		check(not rows.is_empty() and (rows[0].cmd.pos as Vector2).distance_to(doc.pos) > 30.0, "plague S2 never aims at itself (%s)" % case)
		if not rows.is_empty():
			sim.start_ability(doc, 1, null, rows[0].cmd.pos)
		var before: float = float(doc.resources.get("healBank", 0.0))
		var healed: float = 0.0
		sim.controllers = [b, Idle.new(sim, 1)]
		for i in 120:
			sim.step()
			for ev: Dictionary in sim.tick_events:
				if str(ev.type) == "HEAL_APPLIED" and int(ev.s) == doc.idx and ev.get("ability") is Defs.AbilityDef and (ev.ability as Defs.AbilityDef).action == "healingMist":
					healed += float(ev.amount)
		metrics["mist_heal_" + case] = healed
		check(healed >= 100.0, "plague S2 mist delivers most ticks (%s healed %.0f, was 29/88)" % [case, healed])
		b.dispose()
		sim.dispose()


# ----------------------------------------------------------------- hive mind
func _hive() -> void:
	for d in [360.0, 220.0]:
		var sim: BattleSim = make(["hive_mind"], ["archer"], [Vector2(500, 400), Vector2(500 + d, 400)])
		var h: BUnit = sim.heroes[0]
		var b: TacticianBrain = brain_for(sim)
		var s2: Array = slot_rows(cands(b, h), 1)
		if d > 300.0:
			check(s2.is_empty() or float(best(s2).value) <= 10.0, "hive S2 parasites are not cast at an enemy beyond summon sight")
		else:
			check(not s2.is_empty() and float(best(s2).value) > 60.0, "hive S2 parasites are cast at an enemy inside summon sight")
		b.dispose()
		sim.dispose()
	# S4 timing: must fire when the control ends within the wind-up window.
	var values: Dictionary = {}
	for rem in [2.8, 0.6]:
		var sim2: BattleSim = make(["hive_mind", "swordsman"], ["giant", "mage"], [Vector2(400, 400), Vector2(470, 460), Vector2(600, 400), Vector2(900, 480)])
		var h2: BUnit = sim2.heroes[0]
		var gi: BUnit = unit(sim2, "giant", 1)
		sim2.apply_status(h2, gi, {"status": "control", "duration": rem, "originExactDuration": true}, sim2.context(h2, h2.def.abilities[2], {}))
		var b2: TacticianBrain = brain_for(sim2)
		b2.reserved[gi.idx] = 5000.0
		var rows: Array = []
		b2._controlled_target_candidates(h2, 3, h2.def.abilities[3], b2._ctx(h2), rows)
		values[rem] = float(rows[0].value) if not rows.is_empty() else -INF
		if not rows.is_empty():
			check(bool(rows[0].get("objective_exempt", false)), "hive S4 is flagged exempt from the objective chase penalty")
		b2.dispose()
		sim2.dispose()
	check(float(values[0.6]) >= 200.0 and float(values[0.6]) > float(values[2.8]) + 150.0, "hive S4 must fire before the control expires (%.0f vs %.0f)" % [float(values[0.6]), float(values[2.8])])


# --------------------------------------------------------------------- nitro
func _nitro() -> void:
	for d in [70.0, 190.0]:
		var sim: BattleSim = make(["nitro"], ["archer"], [Vector2(500, 400), Vector2(500 + d, 400)])
		var n: BUnit = sim.heroes[0]
		var b: TacticianBrain = brain_for(sim)
		b.plan.stance = "ENGAGE"
		var s3: Array = slot_rows(cands(b, n), 2)
		if d > 150.0:
			check(s3.is_empty() or float(best(s3).value) <= 0.0, "nitro S3 aura (body + 20) is not cast 190 px from the nearest enemy")
		else:
			check(not s3.is_empty() and float(best(s3).value) > 60.0, "nitro S3 aura is cast in contact")
		b.dispose()
		sim.dispose()


# ------------------------------------------------------------ dimensionalist
func _dimensionalist() -> void:
	# S1 rift faces the incoming shot (the engine uses target_pos).
	var sim: BattleSim = make(["dimensionalist"], ["archer"], [Vector2(600, 400), Vector2(800, 400)])
	var dim: BUnit = sim.heroes[0]
	dim.facing = Vector2.LEFT
	var b: TacticianBrain = brain_for(sim)
	b.intel.projectiles = [{"pos": dim.pos + Vector2(160, 0), "vel": Vector2(-420, 0), "dmg": 90.0, "radius": 8.0, "homing": false,
		"target": -1, "explode": false, "cc": false, "impact_r": 0.0, "target_pos": dim.pos}]
	b._danger_cache.clear()
	var rows: Array = slot_rows(cands(b, dim), 0)
	check(not rows.is_empty() and ((rows[0].cmd.pos as Vector2) - dim.pos).normalized().dot(Vector2.RIGHT) > 0.9, "dimensionalist S1 rift is aimed toward the incoming projectile")
	b.dispose()
	sim.dispose()
	# S3 arming with portals off every allied firing line: no cast.
	var sim2: BattleSim = make(["dimensionalist", "archer"], ["mage"], [Vector2(500, 400), Vector2(460, 400), Vector2(760, 400)])
	var d2: BUnit = sim2.heroes[0]
	sim2.start_ability(d2, 1, null, d2.pos + Vector2(0, 250), {"extra": {"portal_a": d2.pos + Vector2(0, -60), "portal_b": d2.pos + Vector2(0, 250)}})
	for i in 12:
		sim2.step()
	var b2: TacticianBrain = brain_for(sim2)
	sim2.heroes[1].command = {"kind": "basic", "target": sim2.heroes[2].idx}
	check(not sim2.portal_pairs.is_empty() and slot_rows(cands(b2, d2), 2).is_empty(), "dimensionalist S3 is not armed when no allied shot crosses a portal")
	b2.dispose()
	sim2.dispose()
	_dimensionalist_ring_portals()
	_fisherman_hook_scaling()


# Review 1.5.3 (tactician_brain.gd:1886): the fisherman S1 follow-up bonus was
# scaled by the hit chance inside _special_enemy and again by the generic D6
# rule of the caller, ~(p/0.6)^2 of nominal for a mid-range hook.
func _fisherman_hook_scaling() -> void:
	var sim: BattleSim = make(["fisherman", "swordsman"], ["mage"], [Vector2(500, 400), Vector2(470, 440), Vector2(770, 400)])
	var fish: BUnit = sim.heroes[0]
	var b: TacticianBrain = brain_for(sim)
	refresh(sim, b)
	var e: TeamIntel.EnemyBelief = b.intel.enemies[sim.heroes[2].idx]
	var ctx: Dictionary = b._ctx(fish)
	var a: Defs.AbilityDef = fish.def.abilities[0]
	var aim: Vector2 = b.lead_point(fish.pos, e, a.speed, a.cast_time, 1.0 - 0.45 * e.dodge_rate())
	var hp: float = b._hit_prob(fish, a, e, aim)
	var ev: Dictionary = b._enemy_value(fish, a, e, ctx, hp)
	var special: float = b._special_enemy(fish, 0, a, e, aim, ctx, ev)
	var near_allies: float = 0.0
	for a2: BUnit in ctx.allies:
		if a2.pos.distance_to(fish.pos) < 280.0:
			near_allies += float(b.aprof.get(a2.idx, {}).get("dps", 40.0))
	var nominal: float = near_allies * 1.2 + (80.0 if e.def.preferred_range > 150.0 else 20.0)
	var applied: float = special * clampf(hp / maxf(0.05, KitModel.delivery_hit(a)), 0.0, 1.0)
	metrics["fisherman_hook_bonus"] = {"hit": snappedf(hp, 0.01), "nominal": snappedf(nominal, 0.1), "special": snappedf(special, 0.1), "applied": snappedf(applied, 0.1)}
	check(hp < 0.5 and absf(special - nominal) < 0.5, "fisherman S1 follow-up bonus is not pre-scaled by hit chance (%s)" % JSON.stringify(metrics["fisherman_hook_bonus"]))
	check(absf(applied - nominal * clampf(hp / KitModel.delivery_hit(a), 0.0, 1.0)) < 0.5, "fisherman S1 follow-up bonus follows the hit chance exactly once")
	b.dispose()
	sim.dispose()


# Review 1.5.3 (tactician_brain.gd:3144): bastion_ring seed 164202 cast the
# retreat portal with its exit 326 px from the centre of a 200 px ring and
# teleported itself out to die; the doctrine shard walk took any own pair
# whatever its far end landed in.
const DIM_RING: = {"id": "seal", "type": "closing_ring", "shape": "circle", "x": 704, "y": 396, "radius": 640.0,
	"startTime": 5.0, "endTime": 17.0, "startRadius": 640.0, "endRadius": 170.0, "damagePercent": 3.0, "tickInterval": 0.5}


func _dimensionalist_ring_portals() -> void:
	for t0 in [20.0, 0.0]:
		var sim: BattleSim = BattleSim.new({"blue": ["dimensionalist"], "red": ["archer"], "arena_id": "classic", "seed": 153301, "max_time": 150.0})
		sim.arena = Arena.from_data({"id": "ai_heroes_dim_ring", "width": 1408, "height": 792,
			"bounds": {"minX": 40, "maxX": 1368, "minY": 40, "maxY": 752}, "obstacles": [], "hazards": [DIM_RING]})
		var spots: Array = [Vector2(784, 396), Vector2(690, 396)]
		for i in 2:
			sim.heroes[i].pos = spots[i]
			sim.heroes[i].prev_pos = spots[i]
		sim.controllers = [Idle.new(sim, 0), Idle.new(sim, 1)]
		sim.start()
		sim.time = t0
		sim.env.prepare()
		var dim: BUnit = sim.heroes[0]
		var r: float = sim.radius(dim)
		var b: TacticianBrain = brain_for(sim)
		refresh(sim, b)
		b.plan.stance = "DISENGAGE"
		b.plan.dir = Vector2.LEFT
		var ctx: Dictionary = b._ctx(dim)
		var out: Array = []
		b._portal_candidates(dim, 1, dim.def.abilities[1], ctx, out)
		var ring: Dictionary = sim.arena.hazards[0]
		var outside: Array = out.filter(func(c: Dictionary):
			var pa: Vector2 = c.cmd.extra.portal_a
			var pb: Vector2 = c.cmd.extra.portal_b
			var land: Vector2 = pb + (pb - pa).normalized() * (25.0 + r)
			return Arena.ring_outside(ring, land, sim.time + 2.0, 0.0))
		if t0 > 0.0:
			check(outside.is_empty(), "dimensionalist retreat portal never exits outside the closing ring (%d of %d)" % [outside.size(), out.size()])
		else:
			check(not out.is_empty() and outside.is_empty(), "invariant: before the ring starts the retreat portal is still offered")
		# Doctrine shard walk: only through pairs that land inside the ring.
		b.plan.stance = "POKE"
		dim.resources["shards"] = 0.0
		var labels: Array = []
		for far: Vector2 in [Vector2(1104, 396), Vector2(744, 300)]:
			sim.portal_pairs = [{"id": 9001, "source": dim.idx, "team": 0, "a": dim.pos + Vector2(40, 0), "b": far, "radius": 22.0, "end": sim.time + 10.0, "enhanced": false, "ctx": {}}]
			var pts: Array = []
			Doctrine._portal_points(b, dim, b._ctx(dim), pts)
			labels.append(pts.filter(func(p: Array): return str(p[1]).contains("포탈 통과")).size())
		sim.portal_pairs = []
		if t0 > 0.0:
			check(int(labels[0]) == 0 and int(labels[1]) == 1, "doctrine shard walk skips a pair whose far end lands outside the ring (%s)" % str(labels))
		b.dispose()
		sim.dispose()


# -------------------------------------------------------------------- hermes
func _hermes() -> void:
	for near in [true, false]:
		var sim: BattleSim = make(["hermes", "archer"], ["mage"], [Vector2(660 if near else 300, 400), Vector2(500, 420), Vector2(720, 400)])
		var h: BUnit = sim.heroes[0]
		var arc: BUnit = sim.heroes[1]
		var mg: BUnit = sim.heroes[2]
		sim.apply_status(h, mg, {"status": "sleep", "duration": 1.8, "breaksOnDamage": true}, sim.context(h, h.def.abilities[1], {}))
		# Our hermes' order still names the sleeper (the sleep it just cast).
		h.command = {"kind": "ability", "index": 1, "target": mg.idx}
		var b: TacticianBrain = brain_for(sim)
		var rows: Array = cands(b, arc, true, true).filter(func(c): return str(c.cmd.get("kind", "")) == "basic" and int(c.cmd.target) == mg.idx)
		if near:
			check(sim.has_status(mg, &"sleep") and not rows.is_empty() and has_note(rows[0], "하르페 대기"), "allies hold damage on a target our hermes slept (S3 ready nearby)")
		else:
			check(rows.is_empty() or not has_note(rows[0], "하르페 대기"), "no hold when our hermes is far from the slept target")
		b.dispose()
		sim.dispose()
	# An area cast landing on the slept target is held too (it would wake it).
	var sim3: BattleSim = make(["hermes", "giant"], ["mage"], [Vector2(660, 400), Vector2(470, 440), Vector2(720, 400)])
	var h3: BUnit = sim3.heroes[0]
	sim3.apply_status(h3, sim3.heroes[2], {"status": "sleep", "duration": 1.8, "breaksOnDamage": true}, sim3.context(h3, h3.def.abilities[1], {}))
	h3.command = {"kind": "ability", "index": 2, "target": sim3.heroes[2].idx}
	var b3: TacticianBrain = brain_for(sim3)
	var arc3: Array = []
	# A hermes that turned away (cloak, no order on the sleeper) frees allies.
	var h3_saved: Dictionary = h3.command
	h3.command = {"kind": "ability", "index": 0}
	arc3 = slot_rows(cands(b3, sim3.heroes[1]), 2)
	check(not arc3.is_empty() and not arc3.any(func(c): return has_note(c, "하르페 대기")), "no hold once our hermes' order leaves the sleeper")
	h3.command = h3_saved
	var rock: Array = slot_rows(cands(b3, sim3.heroes[1]), 2)
	check(not rock.is_empty() and rock.all(func(c): return has_note(c, "하르페 대기")), "allies hold an area cast that would wake our hermes' sleeper")
	b3.dispose()
	sim3.dispose()
	# Sleep is not cast into our own shot already in flight at the target.
	var sim2: BattleSim = make(["hermes", "giant"], ["mage"], [Vector2(640, 400), Vector2(520, 460), Vector2(720, 400)])
	var h2: BUnit = sim2.heroes[0]
	sim2.start_ability(sim2.heroes[1], 2, null, sim2.heroes[2].pos)
	for i in 12:
		sim2.step()
	var b2: TacticianBrain = brain_for(sim2)
	var s2: Array = slot_rows(cands(b2, h2), 1)
	check(not sim2.proj.list.is_empty() and (s2.is_empty() or has_note(s2[0], "수면을 깸")), "hermes S2 waits while an allied shot would wake the target")
	b2.dispose()
	sim2.dispose()


# ---------------------------------------------------------------- world tree
func _world_tree() -> void:
	var sim: BattleSim = BattleSim.new({"blue": ["world_tree", "archer", "swordsman"], "red": ["mage", "giant"], "arena_id": "classic", "seed": 152501, "max_time": 150.0})
	sim.arena = arena_fixture("ai_heroes_tree")
	var pos: Array = [Vector2(400, 400), Vector2(380, 470), Vector2(460, 430), Vector2(1300, 700), Vector2(1320, 640)]
	for i in 5:
		sim.heroes[i].pos = pos[i]
		sim.heroes[i].prev_pos = pos[i]
		if i < 3:
			sim.heroes[i].hp = sim.max_hp(sim.heroes[i]) * 0.55
	var b: TacticianBrain = TacticianBrain.new(sim, 0)
	sim.controllers = [b, Idle.new(sim, 1)]
	sim.start()
	var t: BUnit = sim.heroes[0]
	var gardens: int = 0
	var anchors: Dictionary = {}
	var moved_anchor: bool = false
	var with_allies: int = 0
	for i in 450:
		sim.step()
		for ev: Dictionary in sim.tick_events:
			if str(ev.type) == "GARDEN_CLOSED" and int(ev.s) == t.idx:
				gardens += 1
				var poly: PackedVector2Array = (sim.gardens.back() as Dictionary).points
				for k in [1, 2]:
					if Geometry2D.is_point_in_polygon(sim.heroes[k].pos, poly):
						with_allies += 1
						break
		var g: Dictionary = (b.mem.get(t.idx, {}) as Dictionary).get("grove", {})
		if not g.is_empty():
			var key: String = str(g.t0)
			if anchors.has(key) and (anchors[key] as Vector2) != (g.c as Vector2):
				moved_anchor = true
			anchors[key] = g.c
	metrics["tree_gardens_15s"] = gardens
	check(gardens >= 1, "world tree closes a garden within 15 s (was 0)")
	metrics["tree_gardens_with_allies"] = with_allies
	check(with_allies >= 1, "world tree's garden encloses an injured ally when it closes")
	check(not anchors.is_empty() and not moved_anchor, "world tree keeps each loop's anchor fixed until it closes")
	sim.dispose()


# ------------------------------------------------------------------ torturer
func _torturer() -> void:
	var sim: BattleSim = make(["torturer"], ["mage"], [Vector2(500, 400), Vector2(620, 400)])
	var tt: BUnit = sim.heroes[0]
	var mg: BUnit = sim.heroes[1]
	var b: TacticianBrain = brain_for(sim)
	var s3: Array = slot_rows(cands(b, tt), 2)
	check(not s3.is_empty() and (s3[0].cmd.pos as Vector2).distance_to(tt.pos) > tt.pos.distance_to(mg.pos) and float(s3[0].cmd.need) < 110.0 + sim.radius(tt),
		"torturer S3 aims past the target and closes in before the range re-check")
	# S4 always asks for cooldowns (health/position of a prisoner are visible).
	sim.start_ability(tt, 2, mg, mg.pos)
	for i in 12:
		sim.step()
	refresh(sim, b)
	set_hp(sim, mg, 0.2)
	refresh(sim, b)
	# Every cooldown already observed: the old picker then asked for health.
	var mb: TeamIntel.EnemyBelief = b.intel.enemies[mg.idx]
	for k in mb.cd_last.size():
		mb.cd_last[k] = 0.0
	var s4: Array = slot_rows(cands(b, tt), 3)
	check(sim.has_status(mg, &"imprisoned") and not s4.is_empty() and str((s4[0].cmd.get("extra", {}) as Dictionary).get("info_kind", "")) == "cooldowns",
		"torturer S4 interrogation asks for cooldowns")
	b.dispose()
	sim.dispose()


# ------------------------------------------------------------------ engineer
func _engineer() -> void:
	# S1 without coverage (micro3 turret_without_coverage): no turret.
	var sim: BattleSim = make(["engineer"], ["archer"], [Vector2(700, 400), Vector2(1260, 400)])
	var en: BUnit = sim.heroes[0]
	var b: TacticianBrain = brain_for(sim)
	check(slot_rows(cands(b, en), 0).is_empty(), "engineer S1 builds no turret that covers nobody")
	b.dispose()
	sim.dispose()
	# S4 upgrades the lowest-level turret in reach (the engine's choice).
	var sim2: BattleSim = make(["engineer"], ["archer"], [Vector2(500, 400), Vector2(1300, 700)])
	var e2: BUnit = sim2.heroes[0]
	sim2.start_ability(e2, 0, null, e2.pos + Vector2(60, 0))
	for i in 18:
		sim2.step()
	e2.cooldowns[0] = 0.0
	sim2.start_ability(e2, 0, null, e2.pos + Vector2(-60, 0))
	for i in 12:
		sim2.step()
	var towers: Array = sim2.kits.owned_entities(e2, "turret")
	if towers.size() >= 2:
		# The newest turret is upgraded already; the engine picks the older L1.
		(towers[towers.size() - 1] as BUnit).level = 2
	var b2: TacticianBrain = brain_for(sim2)
	var s4: Array = slot_rows(cands(b2, e2, false), 3)
	check(towers.size() >= 2 and not s4.is_empty() and float(s4[0].value) >= 100.0, "engineer S4 values the level-1 turret the engine will upgrade")
	b2.dispose()
	sim2.dispose()
	# S2 demolition behind a wall is not worth its damage (LOS at resolve).
	var wall: Dictionary = {"id": "w", "shape": "rect", "x": 640, "y": 300, "w": 30, "h": 200}
	var sim3: BattleSim = make(["engineer", "sniper"], ["archer"], [Vector2(560, 400), Vector2(700, 620), Vector2(700, 400)], [wall])
	var e3: BUnit = sim3.heroes[0]
	sim3.start_ability(e3, 0, null, Vector2(610, 400))
	for i in 45:
		sim3.step()
	var b3: TacticianBrain = brain_for(sim3)
	var s2: Array = slot_rows(cands(b3, e3), 1)
	check(not sim3.kits.owned_entities(e3, "turret").is_empty() and (s2.is_empty() or float(best(s2).value) <= 0.0), "engineer S2 does not detonate into a wall")
	b3.dispose()
	sim3.dispose()


# ---------------------------------------------------------------- politician
func _politician() -> void:
	var sim: BattleSim = make(["politician", "giant"], ["archer", "mage"], [Vector2(300, 400), Vector2(335, 400), Vector2(760, 380), Vector2(780, 450)])
	var p: BUnit = sim.heroes[0]
	var b: TacticianBrain = brain_for(sim)
	var ctx: Dictionary = b._ctx(p)
	var moves: Array = []
	b._move_candidates(p, ctx, moves)
	Doctrine.adjust(b, p, ctx, moves)
	var hold: Array = moves.filter(func(c): return str(c.label) == "위치 유지")
	check(not hold.is_empty() and note_delta(hold[0], "관조 유지") >= 80.0, "politician holds still for contemplation (+80 when safe)")
	# Fake news at distrust 9 would wipe the reports (micro fake_news_10th).
	sim.warfare.distrust[1] = 9
	check(slot_rows(cands(b, p), 0).is_empty(), "politician S1 fake news is saved at distrust 9")
	b.dispose()
	sim.dispose()
	# Diversion: never on itself, never through a wall.
	var solo: BattleSim = make(["politician"], ["swordsman", "werewolf"], [Vector2(400, 400), Vector2(560, 380), Vector2(560, 440)])
	var bs: TacticianBrain = brain_for(solo)
	check(slot_rows(cands(bs, solo.heroes[0]), 1).is_empty(), "politician S2 diversion never targets the politician")
	bs.dispose()
	solo.dispose()
	var wall: Dictionary = {"id": "w", "shape": "rect", "x": 380, "y": 330, "w": 40, "h": 140}
	var sim3: BattleSim = make(["politician", "giant"], ["swordsman", "werewolf"], [Vector2(300, 400), Vector2(520, 400), Vector2(700, 380), Vector2(720, 450)], [wall])
	var b3: TacticianBrain = brain_for(sim3)
	check(slot_rows(cands(b3, sim3.heroes[0]), 1).is_empty(), "politician S2 diversion needs line of sight to the ally")
	b3.dispose()
	sim3.dispose()


# -------------------------------------------------------------- intel models
func _intel_models() -> void:
	# D8: fish grants every 8 s with overflow, not two per life.
	var sim: BattleSim = make(["archer"], ["fisherman"], [Vector2(400, 400), Vector2(700, 400)])
	var intel: TeamIntel = TeamIntel.new(sim, 0)
	var fb: TeamIntel.EnemyBelief = intel.enemies[sim.heroes[1].idx]
	var throw: int = -1
	for i in fb.def.abilities.size():
		if (fb.def.abilities[i] as Defs.AbilityDef).condition.has("selfResource") and str((fb.def.abilities[i] as Defs.AbilityDef).condition.selfResource.key) == "fish":
			throw = i
	for t in [8.5, 16.5, 25.0, 33.0]:
		sim.time = t
		intel._fish_consume(fb, t)
	sim.time = 41.0
	check(throw >= 0 and intel._resource_ok(fb, fb.def.abilities[throw]), "D8: enemy fisherman still has a fish after four throws in 41 s")
	intel.dispose()
	sim.dispose()
	# D9: rage comes from health damage by others and decays after 4-5 s.
	var sim2: BattleSim = make(["archer"], ["nitro"], [Vector2(400, 400), Vector2(700, 400)])
	var i2: TeamIntel = TeamIntel.new(sim2, 0)
	var nb: TeamIntel.EnemyBelief = i2.enemies[sim2.heroes[1].idx]
	var n: int = sim2.heroes[1].idx
	var a: int = sim2.heroes[0].idx
	i2.ingest([{"type": "HEALTH_DAMAGED", "t": 1.0, "s": n, "g": n, "amount": 200.0, "sv": [true, true], "gv": [true, true]},
		{"type": "SHIELD_ABSORBED", "t": 1.0, "s": a, "g": n, "amount": 0.0, "absorbed": 300.0, "sv": [true, true], "gv": [true, true]}])
	check(i2.rage_now(nb, 1.1) == 0.0, "D9: self damage and absorbed damage grant no rage")
	i2.ingest([{"type": "HEALTH_DAMAGED", "t": 2.0, "s": a, "g": n, "amount": 140.0, "sv": [true, true], "gv": [true, true]}])
	check(i2.rage_now(nb, 2.1) == 2.0, "D9: 140 health damage grants two rage")
	check(i2.rage_now(nb, 9.2) == 0.0, "D9: rage decays one per second after the delay")
	i2.dispose()
	sim2.dispose()
	# D13: brush hides a unit from an outside observer; no negative evidence.
	var forest: Array = [{"x": 700, "y": 400, "radius": 120, "patch": 0}]
	var sim3: BattleSim = make(["archer"], ["mage"], [Vector2(400, 400), Vector2(700, 400)], [], 153313, forest)
	var i3: TeamIntel = TeamIntel.new(sim3, 0)
	sim3._update_visibility()
	i3.observe()
	var mb: TeamIntel.EnemyBelief = i3.enemies[sim3.heroes[1].idx]
	check(not mb.visible and not i3._point_visible(Vector2(700, 400)), "D13: a point inside brush is not visible from outside")
	for k in i3.n_part:
		mb.particles[k] = Vector2(700, 400) if k % 2 == 0 else Vector2(560, 400)
		mb.weights[k] = 1.0 / i3.n_part
	i3._propagate(0.1)
	var inside: float = 0.0
	for k in i3.n_part:
		if sim3.arena.forest_at(mb.particles[k]) >= 0:
			inside += mb.weights[k]
	check(inside >= 0.8, "D13: belief mass stays on the brush that hides the enemy (%.2f)" % inside)
	i3.dispose()
	sim3.dispose()
	# DM-4: the deathmatch opening prior is the public spawn list, not the truth.
	var dm: BattleSim = BattleSim.new({"ruleset": "deathmatch", "arena_id": "dm_open_steppe", "players": ["archer", "torturer", "mage", "giant"], "seed": 4242, "max_time": 300.0, "kill_target": 99})
	var i4: TeamIntel = TeamIntel.new(dm, 0)
	var worst: float = INF
	var conf: float = 0.0
	for k in i4.enemies:
		var eb: TeamIntel.EnemyBelief = i4.enemies[k]
		worst = minf(worst, eb.pos.distance_to(dm.u_at(eb.idx).pos))
		conf = maxf(conf, eb.confidence)
	check(conf <= 0.2 and worst > 150.0, "DM-4: opening beliefs are spread over public spawns (min error %.0f, confidence %.2f)" % [worst, conf])
	i4.dispose()
	dm.dispose()


# ------------------------------------------------ core items in owned code
func _core_items() -> void:
	# D6: the fisherman hook bonus scales with the real hit chance.
	var wall: Dictionary = {"id": "w", "shape": "rect", "x": 640, "y": 300, "w": 60, "h": 200}
	var sim: BattleSim = make(["fisherman", "archer"], ["giant"], [Vector2(560, 400), Vector2(700, 180), Vector2(790, 400)], [wall])
	var b: TacticianBrain = brain_for(sim)
	var ctx: Dictionary = b._ctx(sim.heroes[0])
	var a: Defs.AbilityDef = sim.heroes[0].def.abilities[0]
	var e: TeamIntel.EnemyBelief = b.intel.enemies[sim.heroes[2].idx]
	var ev: Dictionary = b._enemy_value(sim.heroes[0], a, e, ctx, 0.1)
	var special: float = b._special_enemy(sim.heroes[0], 0, a, e, e.pos, ctx, ev)
	check(special < 30.0, "D6: hook follow-up bonus behind a wall is scaled by its hit chance (%.0f)" % special)
	b.dispose()
	sim.dispose()
	# D7: rescue flight judges each ally, not only the lowest absolute HP.
	var sim2: BattleSim = make(["metatron", "archer", "giant"], ["swordsman", "werewolf"],
		[Vector2(400, 400), Vector2(540, 400), Vector2(1200, 650), Vector2(600, 380), Vector2(610, 440)])
	set_hp(sim2, sim2.heroes[1], 0.38)
	sim2.heroes[2].hp = 300.0
	var b2: TacticianBrain = brain_for(sim2)
	var rows: Array = []
	b2._ally_candidates(sim2.heroes[0], 2, sim2.heroes[0].def.abilities[2], b2._ctx(sim2.heroes[0]), rows)
	check(rows.any(func(c): return int(c.cmd.target) == sim2.heroes[1].idx), "D7: rescue flight considers the endangered archer next to it")
	b2.dispose()
	sim2.dispose()


# ------------------------------------------------ in-engine confirmations
func _extra_checks() -> void:
	# Pirate S4: the chosen broadside hits exactly the enemies the cone model
	# predicted (engine: impact at the first body, forward cone from there).
	var sim: BattleSim = make(["pirate"], ["archer", "mage"], [Vector2(560, 400), Vector2(760, 400), Vector2(830, 400)], [], 153600)
	var p: BUnit = sim.heroes[0]
	for k in [0, 1, 2]:
		p.cooldowns[k] = sim.time + 30.0
	var b: TacticianBrain = brain_for(sim)
	var top: Dictionary = best(slot_rows(cands(b, p), 3))
	var predicted: int = int((top.get("parts", {}) as Dictionary).get("부채꼴", -1))
	var hit: Dictionary = {}
	if not top.is_empty():
		sim.start_ability(p, 3, null, top.cmd.pos, top.cmd)
		for i in 45:
			sim.step()
			for ev: Dictionary in sim.tick_events:
				if str(ev.type) == "HEALTH_DAMAGED" and int(ev.s) == p.idx and int(ev.get("slot", 0)) == 4:
					hit[int(ev.g)] = true
	check(predicted >= 1 and hit.size() == predicted, "pirate S4 cone prediction matches the engine (%d predicted, %d hit)" % [predicted, hit.size()])
	b.dispose()
	sim.dispose()
	# Hermes: while cloaked next to an enemy, the recast stun comes first.
	var sim2: BattleSim = make(["hermes"], ["mage"], [Vector2(600, 400), Vector2(660, 400)])
	var h: BUnit = sim2.heroes[0]
	sim2.start_ability(h, 0, null, h.pos)
	for i in 15:
		sim2.step()
	var b2: TacticianBrain = brain_for(sim2)
	var rows2: Array = cands(b2, h, true, true)
	var basic2: Array = rows2.filter(func(c): return str(c.cmd.get("kind", "")) == "basic")
	var recast: Array = slot_rows(rows2, 0)
	check(float(h.ks.get("cloak_until", 0.0)) > sim2.time and not recast.is_empty() and (basic2.is_empty() or has_note(basic2[0], "은신 재시전 기절 먼저"))
		and float(best(rows2).value) == float(best(recast).value), "hermes recasts the cloak for its stun before breaking stealth")
	b2.dispose()
	sim2.dispose()
	# Engineer S1 still builds when the turret covers a visible enemy.
	var sim3: BattleSim = make(["engineer"], ["archer"], [Vector2(600, 400), Vector2(860, 400)])
	var b3: TacticianBrain = brain_for(sim3)
	var tur: Array = slot_rows(cands(b3, sim3.heroes[0]), 0)
	check(not tur.is_empty() and int((tur[0].parts as Dictionary).get("사선", 0)) >= 1, "engineer S1 builds a turret that covers a visible enemy")
	b3.dispose()
	sim3.dispose()
	# Aphrodite bed: an injured ally gets a move point onto our bed.
	var sim4: BattleSim = make(["aphrodite", "archer"], ["mage"], [Vector2(500, 400), Vector2(760, 420), Vector2(1300, 700)])
	var ap: BUnit = sim4.heroes[0]
	var arc: BUnit = sim4.heroes[1]
	set_hp(sim4, arc, 0.4)
	sim4.start_ability(ap, 1, null, Vector2(560, 400))
	for i in 15:
		sim4.step()
	var b4: TacticianBrain = brain_for(sim4)
	var pts: Array = []
	Doctrine.move_points(b4, arc, b4._ctx(arc), null, pts)
	var bed_pt: Array = pts.filter(func(q): return str(q[1]) == "침상 회복")
	check(not bed_pt.is_empty() and (bed_pt[0][0] as Vector2).distance_to(Vector2(560, 400)) < 60.0, "an injured ally is pointed onto our aphrodite bed")
	b4.dispose()
	sim4.dispose()
	# Hive: an enemy we control is kept near our hive mind (S4 range).
	var sim5: BattleSim = make(["hive_mind"], ["giant"], [Vector2(400, 400), Vector2(700, 400)])
	var hv: BUnit = sim5.heroes[0]
	var gi: BUnit = sim5.heroes[1]
	sim5.apply_status(hv, gi, {"status": "control", "duration": 3.0, "originExactDuration": true}, sim5.context(hv, hv.def.abilities[2], {}))
	var b5: TacticianBrain = brain_for(sim5)
	var pts5: Array = []
	Doctrine._support_points(b5, gi, {}, pts5)
	check(sim5.eteam(gi) == 0 and not pts5.is_empty() and str(pts5[0][1]) == "조종 대상: 군체 곁" and (pts5[0][0] as Vector2).distance_to(hv.pos) <= 151.0,
		"a controlled enemy is walked back beside our hive mind")
	b5.dispose()
	sim5.dispose()
	# DM-4: a deathmatch respawn is believed over the far public spawns.
	var dm: BattleSim = BattleSim.new({"ruleset": "deathmatch", "arena_id": "dm_open_steppe", "players": ["archer", "torturer", "mage", "giant"], "seed": 4242, "max_time": 300.0, "kill_target": 99})
	var i6: TeamIntel = TeamIntel.new(dm, 0)
	var foe: BUnit = dm.heroes[2]
	var no: Array = []
	no.resize(dm.heroes.size())
	no.fill(false)
	i6.ingest([{"type": "HERO_RESPAWNED", "t": 30.0, "s": foe.idx, "g": foe.idx, "sv": no, "gv": no, "pos": foe.pos}])
	var fb: TeamIntel.EnemyBelief = i6.enemies[foe.idx]
	check(fb.confidence <= 0.2 and fb.spread > 150.0 and not fb.visible, "DM-4: a deathmatch respawn is a spread over public spawns (spread %.0f)" % fb.spread)
	i6.dispose()
	dm.dispose()
