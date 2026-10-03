extends SceneTree

# V2.0 전쟁 기계 (war_machine) AI scenario checks (H-AI-war_machine).
# Each section builds a private fixture and asserts that the tactician does a
# thing when it should and does not when it should not: fuel economy, guided
# bombing charge, genocide strip, arc protector, booster, overdrive, the enemy
# side's fuel tank value and the information-fair fuel belief.
# Run: --script res://tests/hero_ai_v2_war_machine.gd

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
		push_error("HERO_AI_V2_WAR_MACHINE " + label)


func arena_fixture(id: String, obstacles: Array = []) -> Arena:
	return Arena.from_data({"id": id, "width": 1408, "height": 792,
		"bounds": {"minX": 40, "maxX": 1368, "minY": 40, "maxY": 752}, "obstacles": obstacles, "hazards": [], "forests": []})


# Heroes are placed in roster order: blue first, then red. The fuel tank
# spawns lazily on the first tick, so a few ticks run before returning.
func make(blue: Array, red: Array, positions: Array, seed_v: int = 207401) -> BattleSim:
	var sim: BattleSim = BattleSim.new({"blue": blue, "red": red, "arena_id": "classic", "seed": seed_v, "max_time": 150.0})
	sim.arena = arena_fixture("wm_ai_%d_%d" % [seed_v, positions.size()])
	for i in mini(positions.size(), sim.heroes.size()):
		var u: BUnit = sim.heroes[i]
		u.pos = positions[i]
		u.prev_pos = u.pos
		u.vel = Vector2.ZERO
	sim.controllers = [Idle.new(sim, 0), Idle.new(sim, 1)]
	sim.start()
	for k in 3:
		sim.step()
	for i in mini(positions.size(), sim.heroes.size()):
		var u2: BUnit = sim.heroes[i]
		u2.pos = positions[i]
		u2.prev_pos = u2.pos
		u2.vel = Vector2.ZERO
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


func slot_rows(rows: Array, index: int, target: int = -2) -> Array:
	return rows.filter(func(c: Dictionary): return str(c.cmd.get("kind", "")) == "ability" and int(c.cmd.get("index", -1)) == index \
		and (target == -2 or int(c.cmd.get("target", -1)) == target))


func basic_rows(rows: Array, target: int) -> Array:
	return rows.filter(func(c: Dictionary): return str(c.cmd.get("kind", "")) == "basic" and int(c.cmd.get("target", -1)) == target)


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


func tank_of(sim: BattleSim, w: BUnit) -> BUnit:
	var list: Array[BUnit] = sim.kits.owned_entities(w, "fuel_tank")
	return list[0] if list.size() == 1 else null


func charge_of(c: Dictionary) -> int:
	return int((c.cmd.get("extra", {}) as Dictionary).get("charge", -1))


func advance(sim: BattleSim, seconds: float, intel: TeamIntel = null) -> Array:
	var events: Array = []
	var n: int = int(ceil(seconds / BattleSim.DT - 1e-6))
	for k in n:
		sim.step()
		events.append_array(sim.tick_events)
		if intel:
			intel.ingest(sim.tick_events)
			intel.observe()
	return events


func _run() -> void:
	DB.ensure_loaded()
	_fuel_economy()
	_missile_charge_risk()
	_genocide()
	_arc_protector()
	_booster()
	_booster_motion_contract()
	_overdrive()
	_enemy_tank_value()
	_fuel_belief()
	_rect_danger()
	_kit_model()
	_doctrine_and_draft()
	_battles()
	var result: Dictionary = {"status": "PASS" if failed.is_empty() else "FAIL", "passed": passed, "failed": failed, "metrics": metrics}
	print("HERO_AI_V2_WAR_MACHINE ", JSON.stringify(result))
	quit(0 if failed.is_empty() else 1)


# ------------------------------------------------------------ fuel economy
func _fuel_economy() -> void:
	var sim: BattleSim = make(["war_machine"], ["archer", "giant"], [Vector2(500, 400), Vector2(720, 400), Vector2(1250, 650)])
	var w: BUnit = unit(sim, "war_machine", 0)
	var ar: BUnit = unit(sim, "archer", 1)
	var b: TacticianBrain = brain_for(sim)
	# S4 far off: S2 charges everything up to six.
	w.resources["fuel"] = 10.0
	w.cooldowns[3] = sim.time + 20.0
	var r1: Dictionary = best(slot_rows(cands(b, w), 1, ar.idx))
	metrics["s2_far"] = [charge_of(r1), float(r1.get("value", 0.0))]
	check(not r1.is_empty() and charge_of(r1) == 6 and float(r1.value) > 0.0, "S2 charges 6 with 10 fuel when genocide is far (N=%d)" % charge_of(r1))
	# S4 nearly ready: 7 fuel banked, N = 10 - 7 = 3.
	w.cooldowns[3] = sim.time + 3.0
	refresh(sim, b)
	var r2: Dictionary = best(slot_rows(cands(b, w), 1, ar.idx))
	check(not r2.is_empty() and charge_of(r2) == 3 and float(r2.value) > 0.0, "S2 charges fuel - bank = 3 when genocide is nearly ready (N=%d)" % charge_of(r2))
	# Fewer than two above the bank: no S2 on a healthy target.
	w.resources["fuel"] = 8.0
	refresh(sim, b)
	var r3: Dictionary = best(slot_rows(cands(b, w), 1, ar.idx))
	check(not r3.is_empty() and float(r3.value) < 0.0 and has_note(r3, "비축"), "S2 is held with 1 fuel above the bank (value %.0f)" % float(r3.get("value", 0.0)))
	# ... unless the target is low: two missiles kill it.
	ar.hp = 60.0
	refresh(sim, b)
	var r4: Dictionary = best(slot_rows(cands(b, w), 1, ar.idx))
	check(not r4.is_empty() and charge_of(r4) == 2 and float(r4.value) > 0.0 and float(r4.parts.get("처치", 0.0)) > 0.0, "S2 dips into the bank for a kill on a low target (N=%d, value %.0f)" % [charge_of(r4), float(r4.get("value", 0.0))])
	# Overkill is wasted fuel: S4 far, 10 fuel, a 60 HP target needs two.
	w.resources["fuel"] = 10.0
	w.cooldowns[3] = sim.time + 20.0
	refresh(sim, b)
	var r5: Dictionary = best(slot_rows(cands(b, w), 1, ar.idx))
	check(not r5.is_empty() and charge_of(r5) == 2, "S2 fires only the missiles a low target needs (N=%d)" % charge_of(r5))
	# The engine accepts the planned charge and spends exactly N.
	ar.hp = sim.max_hp(ar)
	refresh(sim, b)
	var r6: Dictionary = best(slot_rows(cands(b, w), 1, ar.idx))
	var ok: bool = not r6.is_empty() and sim.start_ability(w, 1, ar, r6.cmd.pos, r6.cmd)
	var charged: int = int(w.action.extra.get("charge", -1)) if ok and w.action else -1
	if ok:
		advance(sim, w.action.resolve_at - sim.time + 0.05)
	check(ok and charged == 6 and absf(float(w.resources.fuel) - 4.0) < 1e-6, "AI charge order is accepted: 6 missiles for 6 fuel (charge %d, fuel %.0f)" % [charged, float(w.resources.fuel)])
	b.dispose()
	sim.dispose()


# ------------------------------------------------- S2 slow risk / adjacency
func _missile_charge_risk() -> void:
	var sim: BattleSim = make(["war_machine"], ["swordsman", "archer"], [Vector2(500, 400), Vector2(555, 400), Vector2(820, 430)])
	var w: BUnit = unit(sim, "war_machine", 0)
	var sw: BUnit = unit(sim, "swordsman", 1)
	var ar: BUnit = unit(sim, "archer", 1)
	w.resources["fuel"] = 10.0
	w.cooldowns[3] = sim.time + 20.0
	var b: TacticianBrain = brain_for(sim)
	var r1: Dictionary = best(slot_rows(cands(b, w), 1, ar.idx))
	check(not r1.is_empty() and charge_of(r1) == 2 and has_note(r1, "근접 위협"), "S2 is not charged with a melee threat adjacent (N=%d)" % charge_of(r1))
	sw.pos = Vector2(1250, 700)
	sw.prev_pos = sw.pos
	refresh(sim, b)
	var r2: Dictionary = best(slot_rows(cands(b, w), 1, ar.idx))
	check(not r2.is_empty() and charge_of(r2) == 6, "S2 charges fully once the melee threat is gone (N=%d)" % charge_of(r2))
	b.dispose()
	sim.dispose()


# ----------------------------------------------------------------- genocide
func _genocide() -> void:
	var sim: BattleSim = make(["war_machine"], ["archer", "mage", "sniper"], [Vector2(400, 400), Vector2(600, 404), Vector2(730, 396), Vector2(420, 700)])
	var w: BUnit = unit(sim, "war_machine", 0)
	var ar: BUnit = unit(sim, "archer", 1)
	var mg: BUnit = unit(sim, "mage", 1)
	var sn: BUnit = unit(sim, "sniper", 1)
	w.resources["fuel"] = 6.0
	var b: TacticianBrain = brain_for(sim)
	check(slot_rows(cands(b, w), 3).is_empty(), "no S4 candidate with 6 fuel (needs 7)")
	w.resources["fuel"] = 7.0
	refresh(sim, b)
	var rows: Array = slot_rows(cands(b, w), 3)
	var top: Dictionary = best(rows)
	var dir: Vector2 = ((top.cmd.pos as Vector2) - w.pos).normalized() if not top.is_empty() else Vector2.ZERO
	metrics["s4_line"] = [float(top.get("value", 0.0)), str(top.get("label", ""))]
	check(not top.is_empty() and float(top.value) > 0.0 and top.label.contains("2명") and absf(dir.angle()) < 0.15, "S4 aims along the line holding two enemies (%s, %.0f)" % [str(top.get("label", "")), float(top.get("value", 0.0))])
	var down: Array = rows.filter(func(c: Dictionary): return ((c.cmd.pos as Vector2) - w.pos).normalized().dot(Vector2.DOWN) > 0.9)
	check(down.is_empty() or float(best(down).value) < float(top.value), "a single enemy line is worth less than the two-enemy line")
	# The order is legal and the strip lands on both enemies.
	var ok: bool = sim.start_ability(w, 3, null, top.cmd.pos, top.cmd) if not top.is_empty() else false
	var ev: Array = advance(sim, 1.2) if ok else []
	var hit_a: bool = false
	var hit_m: bool = false
	var hit_s: bool = false
	for e in ev:
		if str(e.type) == "HEALTH_DAMAGED" and e.get("ability") is Defs.AbilityDef and (e.ability as Defs.AbilityDef).id == "war_machine_4":
			hit_a = hit_a or int(e.g) == ar.idx
			hit_m = hit_m or int(e.g) == mg.idx
			hit_s = hit_s or int(e.g) == sn.idx
	check(ok and hit_a and hit_m and not hit_s, "AI genocide order hits the two lined-up enemies and not the one aside")
	b.dispose()
	sim.dispose()
	# Rooted enemies stay in the strip: worth more than a free one.
	var vals: Array = []
	for rooted in [false, true]:
		var s2: BattleSim = make(["war_machine"], ["mage"], [Vector2(400, 400), Vector2(640, 400)])
		var w2: BUnit = unit(s2, "war_machine", 0)
		var m2: BUnit = unit(s2, "mage", 1)
		w2.resources["fuel"] = 7.0
		if rooted:
			s2.apply_status(w2, m2, {"status": "root", "duration": 2.5, "originExactDuration": true}, {})
		var b2: TacticianBrain = brain_for(s2)
		refresh(s2, b2)
		var t2: Dictionary = best(slot_rows(cands(b2, w2), 3))
		vals.append(float(t2.get("value", -999.0)))
		b2.dispose()
		s2.dispose()
	metrics["s4_free_vs_rooted"] = vals
	check(float(vals[1]) > float(vals[0]) + 40.0, "S4 values a rooted enemy above a free one (%.0f vs %.0f)" % [float(vals[1]), float(vals[0])])
	check(float(vals[1]) > 0.0, "S4 on one rooted enemy is worth casting (%.0f)" % float(vals[1]))


# ---------------------------------------------------------- arc protector
func _arc_protector() -> void:
	# Surrounded at half health: high predicted damage.
	var sim: BattleSim = make(["war_machine"], ["swordsman", "werewolf", "giant"], [Vector2(500, 400), Vector2(550, 400), Vector2(470, 445), Vector2(470, 350)])
	var w: BUnit = unit(sim, "war_machine", 0)
	w.hp = sim.max_hp(w) * 0.5
	var b: TacticianBrain = brain_for(sim)
	var r1: Dictionary = best(slot_rows(cands(b, w), 2))
	metrics["s3_surrounded"] = float(r1.get("value", 0.0))
	check(not r1.is_empty() and float(r1.value) > 60.0, "S3 is cast under heavy predicted damage (%.0f)" % float(r1.get("value", 0.0)))
	b.dispose()
	sim.dispose()
	# Nobody near: held.
	var s2: BattleSim = make(["war_machine"], ["archer"], [Vector2(300, 400), Vector2(1300, 700)])
	var w2: BUnit = unit(s2, "war_machine", 0)
	var b2: TacticianBrain = brain_for(s2)
	var r2: Dictionary = best(slot_rows(cands(b2, w2), 2))
	check(r2.is_empty() or float(r2.value) <= 0.0, "S3 is held with no damage coming")
	b2.dispose()
	s2.dispose()
	# Diving into two enemies while the team goes in.
	var s3: BattleSim = make(["war_machine", "giant"], ["archer", "mage"], [Vector2(500, 400), Vector2(430, 400), Vector2(640, 380), Vector2(660, 440)])
	var w3: BUnit = unit(s3, "war_machine", 0)
	var b3: TacticianBrain = brain_for(s3)
	b3.plan["go"] = true
	var r3: Dictionary = best(slot_rows(cands(b3, w3), 2))
	check(not r3.is_empty() and str(r3.label).contains("진입") and float(r3.value) > 0.0, "S3 goes up when diving into a fight (%s)" % str(r3.get("label", "")))
	b3.dispose()
	s3.dispose()


# ------------------------------------------------------------------ booster
func _booster() -> void:
	var sim: BattleSim = make(["war_machine"], ["mage"], [Vector2(500, 400), Vector2(685, 400)])
	var w: BUnit = unit(sim, "war_machine", 0)
	var mg: BUnit = unit(sim, "mage", 1)
	w.resources["fuel"] = 5.0
	w.cooldowns[3] = sim.time + 20.0
	var b: TacticianBrain = brain_for(sim)
	var r1: Dictionary = best(slot_rows(cands(b, w), 0))
	metrics["s1_gap"] = float(r1.get("value", 0.0))
	check(not r1.is_empty() and float(r1.value) > 0.0, "S1 closes a gap slightly out of reach (%.0f)" % float(r1.get("value", 0.0)))
	var ok: bool = sim.start_ability(w, 0, null, r1.cmd.pos, r1.cmd) if not r1.is_empty() else false
	advance(sim, 0.3)
	check(ok and w.pos.distance_to(mg.pos) <= sim.stat(w, &"attackRange") + sim.radius(w) + sim.radius(mg) + 2.0, "AI booster order lands in basic reach (%.0f)" % w.pos.distance_to(mg.pos))
	# In reach already: no dash.
	w.cooldowns[0] = sim.time
	refresh(sim, b)
	var r2: Dictionary = best(slot_rows(cands(b, w), 0))
	check(r2.is_empty() or float(r2.value) < 0.0, "S1 is not used with the target already in reach")
	# The bank: genocide nearly ready with exactly 7 fuel.
	mg.pos = Vector2(w.pos.x + 185.0, 400.0)
	mg.prev_pos = mg.pos
	w.resources["fuel"] = 7.0
	w.cooldowns[3] = sim.time + 3.0
	refresh(sim, b)
	var r3: Dictionary = best(slot_rows(cands(b, w), 0))
	check(not r3.is_empty() and float(r3.value) < 0.0 and has_note(r3, "비축"), "S1 does not spend fuel genocide needs (%.0f)" % float(r3.get("value", 0.0)))
	b.dispose()
	sim.dispose()
	# Escape: low and surrounded.
	var s2: BattleSim = make(["war_machine"], ["swordsman", "werewolf", "giant"], [Vector2(500, 400), Vector2(550, 400), Vector2(470, 445), Vector2(470, 350)])
	var w2: BUnit = unit(s2, "war_machine", 0)
	w2.hp = s2.max_hp(w2) * 0.15
	w2.resources["fuel"] = 3.0
	var b2: TacticianBrain = brain_for(s2)
	var esc: Array = slot_rows(cands(b2, w2), 0).filter(func(c: Dictionary): return str(c.label).contains("탈출"))
	check(not esc.is_empty() and float(best(esc).value) > 0.0, "S1 escapes when low and surrounded")
	b2.dispose()
	s2.dispose()


# ---------------------------------------------------------------- overdrive
func _booster_motion_contract() -> void:
	for blocked in [false, true]:
		var sim: BattleSim = make(["war_machine"], ["mage"], [Vector2(500, 400), Vector2(555, 400)])
		if blocked:
			sim.arena = arena_fixture("booster_first_wall", [{"shape": "rect", "x": 590, "y": 340, "w": 12, "h": 120}])
		var w: BUnit = sim.heroes[0]
		w.resources["fuel"] = 5.0
		w.cooldowns[3] = sim.time + 20.0
		var b: TacticianBrain = brain_for(sim)
		var row: Dictionary = best(slot_rows(cands(b, w, false), 0))
		check(not row.is_empty(), "booster contract: close target still has an evaluated candidate (%s)" % str(blocked))
		if not row.is_empty():
			var start: Vector2 = w.pos
			var land: Vector2 = WarMachineTactics.booster_landing(sim, start, row.cmd.pos, sim.radius(w), 110.0)
			var expected_x: float = 590.0 - sim.radius(w) if blocked else 610.0
			check(absf(land.x - expected_x) < 0.01 and absf(float(row.parts["이동"]) - start.distance_to(land)) < 0.01,
				"booster prices full 110 path / first wall, never the close enemy's edge (%s)" % str(blocked))
			for effect in w.def.abilities[0].effects:
				if str(effect.get("type", "")) == "move_self":
					sim.kits.move_self(w, null, effect, {"target_pos": row.cmd.pos})
			for k in 12:
				sim.time += BattleSim.DT
				sim.kits.update_motion(w, BattleSim.DT)
			check(w.motion == null and w.pos.distance_to(land) < 0.01, "booster prediction matches engine motion (%s)" % str(blocked))
		b.dispose()
		sim.dispose()


func _overdrive() -> void:
	var sim: BattleSim = make(["war_machine"], ["mage"], [Vector2(500, 400), Vector2(600, 400)])
	var w: BUnit = unit(sim, "war_machine", 0)
	var mg: BUnit = unit(sim, "mage", 1)
	var tank: BUnit = tank_of(sim, w)
	check(tank != null, "fixture: tank attached")
	if tank == null:
		sim.dispose()
		return
	sim.apply_damage(mg, tank, {"type": "damage", "school": "true", "base": 1000.0, "frozen": true}, {"source_type": "ABILITY"})
	check(WarMachineTactics.overdrive(sim, w) and float(w.resources.get("fuel", 0.0)) == 0.0, "fixture: tank destroyed, overdrive, fuel 0")
	for k in 4:
		w.cooldowns[k] = sim.time
	w.attack_ready_at = sim.time
	var b: TacticianBrain = brain_for(sim)
	var rows: Array = cands(b, w, true, true)
	check(slot_rows(rows, 1).is_empty() and slot_rows(rows, 2).is_empty() and slot_rows(rows, 3).is_empty(), "overdrive: no S2/S3/S4 candidates (locked)")
	var s1: Dictionary = best(slot_rows(rows, 0))
	check(not s1.is_empty() and float(s1.value) > 0.0 and has_note(s1, "과열 폭주") and float(s1.parts.get("연료", 1.0)) == 0.0, "overdrive: free booster sticks to a target 20 px out of reach (%.0f)" % float(s1.get("value", 0.0)))
	mg.pos = Vector2(560, 400)
	mg.prev_pos = mg.pos
	refresh(sim, b)
	var bas: Dictionary = best(basic_rows(cands(b, w, true, true), mg.idx))
	check(not bas.is_empty() and has_note(bas, "평타 올인") and note_delta(bas, "평타 올인") >= 18.0, "overdrive: basics are pushed all-in")
	b.dispose()
	sim.dispose()
	# Outside overdrive a basic on a hero also earns fuel.
	var s2: BattleSim = make(["war_machine"], ["mage"], [Vector2(500, 400), Vector2(560, 400)])
	var w2: BUnit = unit(s2, "war_machine", 0)
	w2.attack_ready_at = s2.time
	var b2: TacticianBrain = brain_for(s2)
	var bas2: Dictionary = best(basic_rows(cands(b2, w2, true, true), unit(s2, "mage", 1).idx))
	check(not bas2.is_empty() and has_note(bas2, "연료 충전") and not has_note(bas2, "평타 올인"), "basics refuel outside overdrive (no all-in note)")
	b2.dispose()
	s2.dispose()


# ------------------------------------------------------ enemy: fuel tank
func _enemy_tank_value() -> void:
	var notes: Array = []
	for case in ["armed", "empty", "ally_low"]:
		var sim: BattleSim = make(["swordsman", "archer"], ["war_machine"], [Vector2(560, 400), Vector2(470, 470), Vector2(640, 400)])
		var sw: BUnit = unit(sim, "swordsman", 0)
		var ar: BUnit = unit(sim, "archer", 0)
		var w: BUnit = unit(sim, "war_machine", 1)
		w.facing = Vector2.LEFT
		sim.step()
		w.pos = Vector2(640, 400)
		var tank: BUnit = tank_of(sim, w)
		sw.attack_ready_at = sim.time
		if case == "ally_low":
			ar.hp = sim.max_hp(ar) * 0.18
		var b: TacticianBrain = brain_for(sim)
		refresh(sim, b)
		var wb: TeamIntel.EnemyBelief = b.intel.enemies[w.idx]
		wb.fuel = 2.0 if case == "empty" else 8.0
		var row: Dictionary = best(basic_rows(cands(b, sw, true, true), tank.idx if tank else -1))
		notes.append(note_delta(row, "연료탱크") if not row.is_empty() else -9999.0)
		b.dispose()
		sim.dispose()
	metrics["tank_notes_armed_empty_allylow"] = notes
	check(float(notes[0]) > 0.0, "enemy: breaking the tank is valued when the believed fuel arms genocide (%.1f)" % float(notes[0]))
	check(float(notes[1]) < 0.0, "enemy: the tank is left alone at low believed fuel (overdrive threat, %.1f)" % float(notes[1]))
	check(float(notes[2]) < float(notes[0]) and float(notes[2]) < 0.0, "enemy: not popped when the overdrive burst would kill a low ally (%.1f)" % float(notes[2]))


# ------------------------------------------------------------ fuel belief
func _fuel_belief() -> void:
	var sim: BattleSim = make(["archer"], ["war_machine"], [Vector2(500, 400), Vector2(565, 400)])
	var ar: BUnit = unit(sim, "archer", 0)
	var w: BUnit = unit(sim, "war_machine", 1)
	var intel: TeamIntel = TeamIntel.new(sim, 0)
	sim._update_visibility()
	intel.observe()
	var wb: TeamIntel.EnemyBelief = intel.enemies[w.idx]
	# Fuel per basic hit is part of the measured H-BALANCE hero data.
	var per: float = float(w.def.rule("fuel_tank").get("perBasic", 1.0))
	var earned: float = 3.0 * per
	# Observed basic hits on an observed target count.
	for k in 3:
		w.attack_ready_at = sim.time
		w.action = null
		var started: bool = sim.start_basic(w, ar)
		advance(sim, 0.35, intel)
		if not started:
			break
	check(absf(intel.fuel_now(wb) - float(w.resources.fuel)) < 1e-6 and float(w.resources.fuel) == earned, "belief counts observed basics (belief %.0f, real %.0f)" % [intel.fuel_now(wb), float(w.resources.fuel)])
	# Never read from the unit: a hidden refill is unknown.
	w.resources["fuel"] = 10.0
	advance(sim, 0.1, intel)
	check(intel.fuel_now(wb) == earned, "belief ignores fuel it did not observe being earned")
	# Unobserved hits (source not seen) do not count.
	intel.ingest([{"type": "HEALTH_DAMAGED", "t": sim.time, "s": w.idx, "g": ar.idx, "amount": 50.0, "absorbed": 0.0, "basic": true, "sv": [false, true], "gv": [true, true]}])
	check(intel.fuel_now(wb) == earned, "belief ignores a hit whose source was not seen")
	# Hits on a structure do not refuel.
	var tw: Dictionary = {"type": "HEALTH_DAMAGED", "t": sim.time, "s": w.idx, "g": w.idx, "amount": 50.0, "absorbed": 0.0, "basic": true, "sv": [true, true], "gv": [true, true]}
	intel.ingest([tw])
	check(intel.fuel_now(wb) == earned, "belief ignores a basic on the war machine's own side")
	# Observed spends: a charge (N from its public cast time) after its windup.
	var s2: Defs.AbilityDef = w.def.abilities[1]
	var t0: float = sim.time
	intel.ingest([{"type": "CAST_STARTED", "t": t0, "s": w.idx, "g": ar.idx, "slot": 2, "ability": s2, "cast_time": 0.2, "sv": [true, true], "gv": [true, true]}])
	check(intel.fuel_now(wb) == earned, "a charge is pending during its windup")
	sim.time = t0 + 0.25
	check(intel.fuel_now(wb) == earned - 2.0, "an observed 2-missile charge spends 2")
	# A cancel seen during the windup refunds the pending spend.
	wb.fuel = 8.0
	var s4: Defs.AbilityDef = w.def.abilities[3]
	intel.ingest([{"type": "CAST_STARTED", "t": sim.time, "s": w.idx, "g": -1, "slot": 4, "ability": s4, "cast_time": 0.6, "sv": [true, true], "gv": [true, true]},
		{"type": "CAST_CANCELLED", "t": sim.time + 0.1, "s": w.idx, "g": -1, "sv": [true, true], "gv": [true, true]}])
	sim.time += 1.0
	check(intel.fuel_now(wb) == 8.0, "a cancelled genocide spends nothing")
	intel.ingest([{"type": "CAST_STARTED", "t": sim.time, "s": w.idx, "g": -1, "slot": 4, "ability": s4, "cast_time": 0.6, "sv": [true, true], "gv": [true, true]}])
	sim.time += 0.7
	check(intel.fuel_now(wb) == 1.0, "an observed genocide spends 7")
	# Belief gates readiness: genocide needs believed 7.
	wb.cd_last[3] = -999.0
	check(intel.ready_prob(wb, 3) == 0.0, "genocide is believed not ready at believed fuel 1")
	wb.fuel = 7.0
	check(intel.ready_prob(wb, 3) > 0.9, "genocide is believed ready at believed fuel 7")
	# Tank destroyed (seen): fuel 0, overdrive, S2-S4 locked, S1 free.
	intel.ingest([{"type": "TANK_DESTROYED", "t": sim.time, "s": ar.idx, "g": w.idx, "sv": [true, true], "gv": [true, true]}])
	wb.cd_last[0] = -999.0
	wb.cd_last[1] = -999.0
	wb.cd_last[2] = -999.0
	check(intel.fuel_now(wb) == 0.0 and intel.overdrive_believed(wb) and intel.tank_down(wb), "seen tank destruction: fuel 0, overdrive and tank down believed")
	check(intel.ready_prob(wb, 1) == 0.0 and intel.ready_prob(wb, 2) == 0.0 and intel.ready_prob(wb, 3) == 0.0 and intel.ready_prob(wb, 0) > 0.9, "overdrive: S2-S4 believed locked, S1 believed free")
	intel.dispose()
	sim.dispose()
	# Unseen destruction by a third party is not known.
	var sim2: BattleSim = make(["archer"], ["war_machine"], [Vector2(300, 400), Vector2(900, 400)])
	var i2: TeamIntel = TeamIntel.new(sim2, 0)
	var w2: BUnit = unit(sim2, "war_machine", 1)
	var b2: TeamIntel.EnemyBelief = i2.enemies[w2.idx]
	b2.fuel = 6.0
	i2.ingest([{"type": "TANK_DESTROYED", "t": sim2.time, "s": w2.idx, "g": w2.idx, "sv": [false, true], "gv": [false, true]}])
	check(i2.fuel_now(b2) == 6.0 and not i2.overdrive_believed(b2), "unseen tank destruction leaves the belief unchanged")
	i2.dispose()
	sim2.dispose()


# ---------------------------------------------------- rect zone danger
func _rect_danger() -> void:
	var sim: BattleSim = make(["archer", "giant"], ["war_machine"], [Vector2(700, 400), Vector2(700, 600), Vector2(400, 400)])
	var ar: BUnit = unit(sim, "archer", 0)
	var w: BUnit = unit(sim, "war_machine", 1)
	w.resources["fuel"] = 7.0
	w.cooldowns[3] = sim.time
	var ok: bool = sim.start_ability(w, 3, null, Vector2(700, 400), {})
	advance(sim, 0.7)
	ar.pos = Vector2(1250, 150)
	var b: TacticianBrain = brain_for(sim)
	refresh(sim, b)
	var rect: bool = false
	for z in b.intel.zones:
		rect = rect or str(z.shape) == "rect"
	check(ok and rect, "a seen genocide strip enters the enemy team's zones as a rect")
	var g: BUnit = unit(sim, "giant", 0)
	var inside: float = WarMachineTactics.rect_zone_danger(b.intel.zones[0], Vector2(650, 405), 18.0, 1.0) if not b.intel.zones.is_empty() else 0.0
	var aside: float = WarMachineTactics.rect_zone_danger(b.intel.zones[0], Vector2(650, 520), 18.0, 1.0) if not b.intel.zones.is_empty() else 0.0
	var start_cap: float = WarMachineTactics.rect_zone_danger(b.intel.zones[0], Vector2(760, 400), 18.0, 1.0) if not b.intel.zones.is_empty() else 0.0
	check(inside > 0.0 and aside == 0.0 and start_cap > 0.0, "rect danger covers the whole strip, not a circle at its start (%.0f / %.0f / %.0f)" % [inside, aside, start_cap])
	b._danger_cache.clear()
	check(b.danger_at(g, Vector2(650, 405), 1.0) > b.danger_at(g, Vector2(650, 560), 1.0), "brain danger is higher inside the strip than beside it")
	b.dispose()
	sim.dispose()


# ----------------------------------------------------------------- kit model
func _kit_model() -> void:
	var d: Defs.CharDef = DB.char_def("war_machine")
	var st: Dictionary = KitModel.stats_of_def(d)
	var ev3: Dictionary = KitModel.evaluate(d.abilities[2].effects, st, {})
	check(absf(float(ev3.guard) - 0.4) < 1e-6 and absf(float(ev3.arc) - 0.15) < 1e-6 and absf(float(ev3.arc_cap) - 204.0) < 1e-6, "kit model reads damageTaken -40% and arcConvert 15% (cap 204)")
	check(absf(KitModel.guard_value(ev3, 300.0) - (120.0 + 27.0)) < 1e-6, "guard value: 40% cut plus 15% of what lands as shield")
	var ev2: Dictionary = KitModel.evaluate(d.abilities[1].effects, st, {"charge": 4})
	check(float(ev2.resource_cost) == 4.0, "perProjectile cost scales with the charge (4)")
	var ev4: Dictionary = KitModel.evaluate(d.abilities[3].effects, st, {})
	check(float(ev4.resource_cost) == 7.0 and float(ev4.phys) > 0.0 and float(ev4.slow) > 0.3, "rect zone is valued (damage and slow) and costs 7")
	var s2: Defs.AbilityDef = d.abilities[1]
	check(KitModel.charge_count(s2) == 4 and KitModel.charge_count(s2, 3.0) == 3 and KitModel.charge_count(s2, 9.0) == 6 and KitModel.charge_count(s2, 1.0) == 2, "charge_count: unknown 4, else clamp(fuel, 2, 6)")
	var rows: Array = KitModel._enemy_base(d).rows
	var single: float = KitModel.mitigate(KitModel.evaluate(s2.effects, st, {"max_hp": 1000.0, "hp": 800.0}), 35.0, 30.0)
	check(absf(float(rows[1].dmg) - single * 4.0) < 1e-3, "enemy profile prices a mid charge of four missiles")
	var archer: Defs.CharDef = DB.char_def("archer")
	check(KitModel.charge_count(archer.abilities[0]) == maxi(1, archer.abilities[0].count), "abilities without a charge keep their count")


# ------------------------------------------------------- doctrine / draft
func _doctrine_and_draft() -> void:
	var p: Dictionary = Doctrine.of("war_machine")
	check(not p.is_empty() and str(p.get("title", "")) != "" and str(p.get("code", "")) != "" and (p.get("roles", []) as Array).size() >= 2
		and (p.get("principles", []) as Array).size() == 4 and (p.get("target", {}) as Dictionary).has_all(["low", "threat", "backline", "isolated"])
		and str(p.get("geometry", "")) != "" and not (p.get("combos", []) as Array).is_empty(), "doctrine profile: title, code, roles, 4 principles, target weights, geometry, combos")
	for r in p.get("roles", []):
		check(Doctrine.ROLE_LABEL.has(str(r)), "doctrine role %s has a label" % str(r))
	var f: Dictionary = DraftDirector.kit_features(DB.char_def("war_machine"))
	metrics["draft_features"] = {"protection": f.protection, "mobility": f.mobility, "burst": f.burst, "damage": f.damage}
	check(float(f.protection) > 0.2 and float(f.mobility) > 0.6, "draft features count the arc protector and the booster")
	var wm: Dictionary = WarMachineTactics.draft_features(DB.char_def("war_machine"))
	check(float(wm.spell) > 5.0, "draft features add the charged missiles beyond the first (%.1f)" % float(wm.spell))


# ---------------------------------------------------- battles: smoke + determinism
func _signature(cfg: Dictionary) -> Dictionary:
	var sim: BattleSim = BattleSim.new(cfg)
	sim.controllers[0] = AIFactory.make("tactician", sim, 0)
	sim.controllers[1] = AIFactory.make("tactician", sim, 1)
	sim.start()
	var casts: Dictionary = {}
	var charges: Array = []
	var guard: int = 0
	while sim.state == BattleSim.RUNNING and guard < 30 * 200:
		sim.step()
		guard += 1
		for ev in sim.tick_events:
			if str(ev.type) != "CAST_STARTED":
				continue
			var su: BUnit = sim.u_at(int(ev.s))
			if su and su.def.id == "war_machine" and int(ev.get("slot", 0)) > 0:
				var k: String = "S%d" % int(ev.slot)
				casts[k] = int(casts.get(k, 0)) + 1
				if ev.has("charge"):
					charges.append(int(ev.charge))
	var r: Dictionary = sim.result()
	var final: Array = []
	for u in sim.heroes:
		final.append([u.id, snappedf(u.hp, 0.001), snappedf(u.pos.x, 0.001), snappedf(u.pos.y, 0.001), u.st_casts])
	var sig: String = JSON.stringify([r.winner, snappedf(float(r.duration), 0.001), final]).sha256_text()
	sim.dispose()
	return {"sig": sig, "casts": casts, "charges": charges, "winner": r.winner, "duration": r.duration}


func _battles() -> void:
	var cfg: Dictionary = {"blue": ["war_machine", "archer", "giant"], "red": ["swordsman", "mage", "aphrodite"], "arena_id": "classic", "seed": 207411, "max_time": 120.0}
	var a: Dictionary = _signature(cfg)
	var b: Dictionary = _signature(cfg)
	check(str(a.sig) == str(b.sig), "same config and seed reproduce the same war machine battle")
	var total: Dictionary = (a.casts as Dictionary).duplicate()
	var charges: Array = (a.charges as Array).duplicate()
	for extra in [{"blue": ["swordsman", "mage", "aphrodite"], "red": ["war_machine", "sniper", "giant"], "arena_id": "moon_garden", "seed": 207412, "max_time": 120.0},
			{"blue": ["war_machine", "plague_doctor", "baseball"], "red": ["werewolf", "archer", "metatron"], "arena_id": "crossroads", "seed": 207413, "max_time": 120.0}]:
		var r: Dictionary = _signature(extra)
		for k in r.casts:
			total[k] = int(total.get(k, 0)) + int(r.casts[k])
		charges.append_array(r.charges)
	metrics["battle_casts"] = total
	metrics["battle_charges"] = charges
	for s in ["S1", "S2", "S3"]:
		check(int(total.get(s, 0)) > 0, "war machine uses %s in AI battles (%d casts)" % [s, int(total.get(s, 0))])
	var legal: bool = not charges.is_empty()
	for n in charges:
		legal = legal and int(n) >= 2 and int(n) <= 6
	check(legal, "every S2 cast carries a charge of 2-6 (%s)" % str(charges))
