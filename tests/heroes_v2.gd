extends SceneTree

# V2.0 heroes (hades, war_machine, torquemada, achilles) and the engine
# primitives E1-E22 behind them (DESIGN_V2 §2). Deterministic micro-scenarios
# on the open classic arena without controllers: every unit only does what the
# test tells it. Measured numbers are written to reports/heroes_v2.json.

const NEW_IDS: Array = ["hades", "war_machine", "torquemada", "achilles"]
const OLD_IDS: Array = ["swordsman", "archer", "mage", "sniper", "werewolf", "giant", "aphrodite", "blood_mage", "fisherman", "baseball", "pirate", "joker", "metatron", "plague_doctor", "hive_mind", "nitro", "dimensionalist", "hermes", "world_tree", "torturer", "engineer", "politician"]
# sha256(JSON(raw CharData entry) + JSON(DB CharDef dump))[0:16] of every V1.5.3
# hero at the V2 base commit cfd1024. A deliberate balance change to an old hero
# (e.g. Codex' metatron/world_tree numbers) must update its row here.
const BASE_HASH: Dictionary = {"aphrodite": "85f182fb39004252", "archer": "c2ca70b3f61e8527", "baseball": "f4d11c988a04f889", "blood_mage": "da0588a9ed70a22a", "dimensionalist": "b496481314edca3e", "engineer": "562dd283d75780fc", "fisherman": "4fc94ff19a5e95bd", "giant": "63fe58049c430b5b", "hermes": "50c2d18f1806fcf4", "hive_mind": "af7813789a33facb", "joker": "c3fd9081cfdb553d", "mage": "99a0d566bba30913", "metatron": "fef32d1343fe76dd", "nitro": "ba89c3ef0be1e214", "pirate": "e46efb9850bc638a", "plague_doctor": "6721e7454ea37f68", "politician": "671ca78d68673747", "sniper": "e22ebddd8867abe7", "swordsman": "59b26d935feaba02", "torturer": "39bd015b618c47fa", "werewolf": "c7d4b5672a9cd019", "world_tree": "5b42d11b4a4244ce"}

var passed: int = 0
var failed: Array[String] = []
var metrics: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, label: String) -> void:
	if value:
		passed += 1
	else:
		failed.append(label)
		push_error("HEROES_V2: " + label)


func near(a: float, b: float, eps: float = 0.01) -> bool:
	return absf(a - b) <= eps


# ------------------------------------------------------------------ helpers

func fresh(blue: Array, red: Array, extra: Dictionary = {}) -> BattleSim:
	var cfg: Dictionary = {"blue": blue, "red": red, "arena_id": "classic", "seed": 20200, "max_time": 300.0}
	for k in extra:
		cfg[k] = extra[k]
	var sim: BattleSim = BattleSim.new(cfg)
	for u in sim.heroes:
		place(u, Vector2(400.0 + u.team * 900.0, 200.0 + u.slot * 160.0))
		u.facing = Vector2.RIGHT if u.team == 0 else Vector2.LEFT
	sim.start()
	return sim


func place(u: BUnit, p: Vector2) -> void:
	u.pos = p
	u.prev_pos = p
	u.vel = Vector2.ZERO


func advance(sim: BattleSim, seconds: float) -> Array:
	var events: Array = []
	for i in int(ceil(seconds / BattleSim.DT - 1e-6)):
		if sim.state == BattleSim.RUNNING:
			sim.step()
			events.append_array(sim.tick_events)
	return events


func step(sim: BattleSim) -> Array:
	sim.step()
	return sim.tick_events.duplicate()


func ready_cast(sim: BattleSim, u: BUnit, slot: int, target: BUnit, aim: Vector2, extra: Dictionary = {}) -> bool:
	u.action = null
	u.command = {}
	u.cooldowns[slot - 1] = sim.time
	return sim.start_ability(u, slot - 1, target, aim, {"extra": extra} if not extra.is_empty() else {})


# Starts a cast and runs until its windup resolved (plus `tail` seconds).
func cast(sim: BattleSim, u: BUnit, slot: int, target: BUnit, aim: Vector2, extra: Dictionary = {}, tail: float = 0.05) -> Array:
	if not ready_cast(sim, u, slot, target, aim, extra):
		return [false]
	var wait: float = u.action.resolve_at - sim.time if u.action else 0.0
	var events: Array = advance(sim, wait + tail)
	events.push_front(true)
	return events


func count_events(events: Array, type: String, s: int = -99, g: int = -99) -> int:
	var n: int = 0
	for ev in events:
		if ev is Dictionary and str(ev.type) == type and (s == -99 or int(ev.s) == s) and (g == -99 or int(ev.g) == g):
			n += 1
	return n


func damage_events(events: Array, g: int, ability_id: String = "", source_type: String = "") -> Array:
	var out: Array = []
	for ev in events:
		if not (ev is Dictionary) or str(ev.type) != "HEALTH_DAMAGED" or int(ev.g) != g:
			continue
		var ab = ev.get("ability")
		if ability_id != "" and not (ab is Defs.AbilityDef and (ab as Defs.AbilityDef).id == ability_id):
			continue
		if source_type != "" and str(ev.get("source_type", "")) != source_type:
			continue
		out.append(float(ev.amount))
	return out


func one(sim: BattleSim, u: BUnit, kind: String) -> BUnit:
	var list: Array[BUnit] = sim.kits.owned_entities(u, kind)
	return list[0] if list.size() == 1 else null


func drop_pet(sim: BattleSim, hades: BUnit) -> void:
	for e in sim.kits.owned_entities(hades, "cerberus"):
		e.alive = false
		e.end_time = sim.time
	hades.ks["pet_ready_at"] = 1e12


func def_dump(d: Defs.CharDef) -> Dictionary:
	var abilities: Array = []
	for a: Defs.AbilityDef in d.abilities:
		var values: Dictionary = {}
		for property in a.get_property_list():
			if (int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0:
				values[str(property.name)] = a.get(str(property.name))
		abilities.append(values)
	return {"id": d.id, "name": d.name, "glyph": d.glyph, "accent": d.accent.to_html(), "role": d.role, "tags": Array(d.tags),
		"summary": d.summary, "stats": d.stats, "preferred_range": d.preferred_range, "behavior": d.behavior, "doctrine": d.doctrine,
		"nexus": d.nexus, "passives": d.passives, "rules": d.rules, "arming_time": d.arming_time, "abilities": abilities}


# ------------------------------------------------------------------ run

func _run() -> void:
	DB.ensure_loaded()
	data_checks()
	kynee()
	cerberus()
	hades_s1()
	hades_s2()
	hades_s3()
	fuel()
	tank()
	tank_destroyed()
	booster()
	missiles()
	arc_protector()
	genocide()
	torquemada_tenacity()
	cleanse()
	torquemada_s2()
	alhambra()
	torquemada_v3_effects()
	achilles_passive()
	spear()
	front_guard()
	roar()
	chariot()
	hermes()
	respawn_modes()
	determinism()
	var report: Dictionary = {"suite": "heroes_v2", "status": "PASS" if failed.is_empty() else "FAIL", "passed": passed, "failed": failed, "metrics": metrics}
	var file: FileAccess = FileAccess.open("res://reports/heroes_v2.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print("HEROES_V2 ", JSON.stringify({"status": report.status, "passed": passed, "failed": failed}))
	print("HEROES_V2_METRICS ", JSON.stringify(metrics))
	quit(0 if failed.is_empty() else 1)


# ------------------------------------------------------------------ data

func data_checks() -> void:
	check(DB.characters.size() == 26, "26 playable characters")
	var ids: Array = DB.ids()
	check(ids.slice(0, 22) == OLD_IDS, "the 22 V1.5.3 heroes keep their DB order")
	check(ids.slice(22, 26) == NEW_IDS, "new heroes appended after politician: hades, war_machine, torquemada, achilles")
	var changed: Array = []
	for e in CharData.LIST:
		var id: String = str(e.id)
		if BASE_HASH.has(id):
			var h: String = (JSON.stringify(e) + JSON.stringify(def_dump(DB.char_def(id)))).sha256_text().substr(0, 16)
			if h != str(BASE_HASH[id]):
				changed.append(id)
	check(changed.is_empty(), "old hero data byte-identical to the V2 base %s" % str(changed))
	var table: Dictionary = {
		"hades": [1220, 68, 24, 35, 32, 82, 0.68, 62, 0.05, 19, 60, "하데스", "冥", "FRONTLINE", "#8f7cff"],
		"war_machine": [1020, 105, 15, 24, 24, 116, 0.92, 45, 0.05, 18, 44, "전쟁 기계", "機", "DAMAGE", "#ff8a3d"],
		"torquemada": [1140, 62, 30, 41, 40, 90, 0.9, 56, 0.35, 17, 58, "토르케마다", "審", "SUPPORT", "#e0b04a"],
		"achilles": [1220, 70, 15, 48, 40, 82, 0.72, 62, 0.05, 19, 60, "아킬레우스", "槍", "FRONTLINE", "#c98b3a"]}
	var keys: Array = ["maxHealth", "attackDamage", "abilityPower", "armor", "magicResistance", "moveSpeed", "attackSpeed", "attackRange", "tenacity", "bodyRadius"]
	var active_total: int = 0
	for id in NEW_IDS:
		var d: Defs.CharDef = DB.char_def(id)
		var row: Array = table[id]
		var ok: bool = d != null
		if ok:
			for i in keys.size():
				ok = ok and near(d.stat(keys[i]), float(row[i]), 1e-6)
			ok = ok and near(d.preferred_range, float(row[10]), 1e-6) and d.name == row[11] and d.glyph == row[12] and d.role == row[13]
			ok = ok and d.accent.to_html(false) == str(row[14]).substr(1) and near(d.stat("critChance"), 0.08) and near(d.stat("critMultiplier"), 1.65)
			for k in ["behavior", "doctrine", "nexus"]:
				ok = ok and not (d.get(k) as Dictionary).is_empty()
		check(ok, id + " identity and stat table match DESIGN §2.1")
		var enums_ok: bool = true
		for i in d.abilities.size():
			var a: Defs.AbilityDef = d.abilities[i]
			active_total += 1
			enums_ok = enums_ok and a.slot == i + 1 and a.target in ["enemy", "ally", "self", "position", "position_ally"] and a.delivery in ["direct", "projectile", "cone", "area", "self"]
			enums_ok = enums_ok and a.vfx_glyph != "" and a.vfx_glyph != str(a.slot) and a.pattern != "" and a.description != ""
		check(enums_ok, id + " abilities use allowed target/delivery values, slots and vfx")
	check(active_total == 14, "14 new active skills (82 -> 96)")
	check(DB.char_def("hades").abilities.size() == 3 and DB.char_def("war_machine").abilities.size() == 4 and DB.char_def("torquemada").abilities.size() == 3 and DB.char_def("achilles").abilities.size() == 4, "ability counts 3/4/3/4")
	var names_ok: bool = true
	for pair in [["cerberus", "犬"], ["shade", "亡"], ["fuel_tank", "油"], ["chariot", "車"]]:
		var ed: Defs.CharDef = Defs.entity_def(str(pair[0]), DB.char_def("hades"), 10.0, 10.0, 0.0)
		names_ok = names_ok and ed.glyph == str(pair[1]) and ed.name != str(pair[0])
	check(names_ok, "entity names and glyphs in Defs.entity_def")
	var labels_ok: bool = true
	for st in ["roar", "overdrive", "frontGuard", "bg_downed"]:
		labels_ok = labels_ok and DB.STATUS_LABELS.has(st)
	check(labels_ok and DB.status_label("roar") == "포효" and DB.status_label("overdrive") == "과열 폭주" and DB.status_label("frontGuard") == "전방 방패" and DB.status_label("bg_downed") == "다운", "E20 status labels")
	var logs_ok: bool = true
	for ev in ["CLEANSED", "FRONT_BLOCKED", "TANK_DESTROYED", "OVERDRIVE", "HEAL_BLOCKED", "CHARIOT_KNOCK"]:
		logs_ok = logs_ok and BattleSim.LOG_TYPES.has(ev)
	check(logs_ok, "E20 log event types")
	check(CodexData.RESOURCES.has("fuel") and str(CodexData.RESOURCES.fuel[0]) == "연료", "E20 resource label fuel = 연료")


# ------------------------------------------------------------------ hades

func kynee() -> void:
	var sim: BattleSim = fresh(["hades"], ["archer"])
	var h: BUnit = sim.heroes[0]
	var e: BUnit = sim.heroes[1]
	place(h, Vector2(400, 400))
	place(e, Vector2(1300, 400))
	advance(sim, 0.1)
	drop_pet(sim, h)
	var mx: float = sim.max_hp(h)
	check(sim.kits.concealed(h), "concealed when no enemy the team sees observes hades")
	h.hp = 600.0
	h.last_damage_time = sim.time - 5.0
	var hp0: float = h.hp
	advance(sim, 1.0)
	var regen: float = h.hp - hp0
	metrics["kynee_regen_per_s"] = regen
	check(near(regen, mx * 0.02, 0.5), "kynee regenerates 2%% max HP per second while concealed (%.2f)" % regen)
	# Delay: damage resets the 1 s quiet timer.
	sim.apply_damage(e, h, {"type": "damage", "school": "true", "base": 10.0, "frozen": true}, {"source_type": "ABILITY"})
	var hit_hp: float = h.hp
	advance(sim, 0.9)
	check(near(h.hp, hit_hp, 0.001), "no regen within 1.0 s of the last hit")
	advance(sim, 0.4)
	check(h.hp > hit_hp + 1.0, "regen resumes after the 1.0 s delay")
	# Off while an enemy the team sees observes hades.
	place(e, h.pos + Vector2(250, 0))
	advance(sim, 0.1)
	check(not sim.kits.concealed(h) and sim.observes(e, h), "an observing seen enemy breaks concealment")
	var watched: float = h.hp
	advance(sim, 1.0)
	check(near(h.hp, watched, 0.001), "no regen while watched")
	# Invisible counts as concealed even next to the watcher.
	sim.push_status(h, &"invisible", h.idx, 3.0)
	check(sim.kits.concealed(h), "invisible is concealed")
	var inv: float = h.hp
	advance(sim, 1.0)
	check(h.hp > inv + 10.0, "regen while invisible")
	sim.remove_statuses_where(h, func(x): return x.type == &"invisible")
	# Heal block (healReduction 1.0) stops the regen through apply_heal.
	place(e, Vector2(1300, 400))
	sim.apply_status(e, h, {"status": "healReduction", "magnitude": 1.0, "duration": 5.0})
	advance(sim, 0.1)
	var blocked: float = h.hp
	advance(sim, 1.0)
	check(sim.kits.concealed(h) and near(h.hp, blocked, 0.001), "heal block stops kynee regen")
	sim.dispose()
	# Brush clause: inside a patch hades is concealed even when an enemy observes him.
	var bs: BattleSim = fresh(["hades"], ["archer"], {"arena_id": "moon_garden"})
	var bh: BUnit = bs.heroes[0]
	var be: BUnit = bs.heroes[1]
	var fp: Vector2 = Vector2(bs.arena.forest_x[0], bs.arena.forest_y[0])
	place(bh, fp)
	place(be, fp + Vector2(70, 0))
	advance(bs, 0.1)
	check(bs.brush_on and bs.arena.forest_at(bh.pos) >= 0 and bs.kits.concealed(bh), "standing in active brush is concealed")
	bs.brush_on = false
	check(not bs.kits.concealed(bh) or not bs.observes(be, bh), "brush clause needs brush switched on")
	bs.dispose()


func cerberus() -> void:
	var sim: BattleSim = fresh(["hades"], ["archer", "mage"])
	var h: BUnit = sim.heroes[0]
	var a: BUnit = sim.heroes[1]
	var m: BUnit = sim.heroes[2]
	place(h, Vector2(400, 400))
	place(a, Vector2(1300, 250))
	place(m, Vector2(1300, 550))
	step(sim)
	var pet: BUnit = one(sim, h, "cerberus")
	check(pet != null, "cerberus spawns lazily on the first tick")
	if pet == null:
		sim.dispose()
		return
	check(near(pet.hp, 420.0) and near(sim.stat(pet, &"armor"), 30.0) and near(sim.stat(pet, &"magicResistance"), 30.0) and near(pet.base_radius, 14.0), "cerberus HP 420, armor/MR 30, radius 14")
	check(str(pet.ks.get("mode", "")) == "companion" and not pet.structure, "cerberus is a companion entity")
	# Follow: 40 px behind hades.
	place(h, Vector2(600, 400))
	h.facing = Vector2.RIGHT
	advance(sim, 3.0)
	check(pet.pos.distance_to(h.pos + Vector2(-40, 0)) < 3.0, "cerberus follows 40 px behind hades (%.1f)" % pet.pos.distance_to(h.pos + Vector2(-40, 0)))
	# Speed max(110, 1.2 x 82) = 110.
	place(h, Vector2(900, 400))
	var p0: Vector2 = pet.pos
	step(sim)
	var spd: float = pet.pos.distance_to(p0) / BattleSim.DT
	metrics["cerberus_speed"] = spd
	check(near(spd, 110.0, 0.5), "cerberus speed max(110, 1.2 x hades MS) = 110 (%.1f)" % spd)
	advance(sim, 3.5)
	# Guard: nearest observed enemy within 160 of hades.
	place(a, h.pos + Vector2(120, 0))
	var ev: Array = advance(sim, 2.0)
	var bites: Array = damage_events(ev, a.idx, "", "SUMMON")
	var expect: float = (14.0 + 0.22 * sim.stat(h, &"attackDamage")) * sim.resist_mult(sim.stat(a, &"armor"))
	metrics["cerberus_bite"] = bites[0] if not bites.is_empty() else 0.0
	check(not bites.is_empty() and near(float(bites[0]), expect, 0.01), "cerberus bites the guarded enemy for 14+0.22AD physical (%s vs %.2f)" % [str(bites), expect])
	check(pet.target_idx == a.idx, "cerberus targets the nearest enemy within 160 of hades")
	var gaps: Array = []
	var last_t: float = -1.0
	ev.append_array(advance(sim, 1.5))
	for x in ev:
		if str(x.type) == "HEALTH_DAMAGED" and int(x.g) == a.idx and str(x.get("source_type", "")) == "SUMMON":
			if last_t >= 0.0:
				gaps.append(float(x.t) - last_t)
			last_t = float(x.t)
	check(not gaps.is_empty() and near(float(gaps[0]), 1.0, 0.04), "cerberus bites every 1.0 s %s" % str(gaps))
	# Command target beats the guard target (within 280 of hades).
	place(m, h.pos + Vector2(250, 60))
	h.command = {"kind": "basic", "target": m.idx, "pos": m.pos}
	var ev2: Array = advance(sim, 2.5)
	check(pet.target_idx == m.idx and not damage_events(ev2, m.idx, "", "SUMMON").is_empty(), "cerberus attacks hades' command target first")
	# Beyond 280 the command is ignored.
	place(m, h.pos + Vector2(330, 0))
	place(a, Vector2(1300, 250))
	advance(sim, 0.2)
	check(pet.target_idx != m.idx, "command target beyond 280 of hades is ignored")
	h.command = {}
	advance(sim, 3.0)
	check(pet.pos.distance_to(h.pos) < 60.0, "cerberus returns behind hades without targets")
	# Leash: a pet outside 150 of hades does not take guard targets.
	place(a, h.pos + Vector2(140, 0))
	place(pet, h.pos + Vector2(-240, 0))
	var d0: float = pet.pos.distance_to(h.pos)
	step(sim)
	check(pet.target_idx == -1 and pet.pos.distance_to(h.pos) < d0, "outside the 150 leash cerberus returns instead of guarding")
	place(a, Vector2(1300, 250))
	# Concealment: summon bites never refresh hades' combat timer.
	advance(sim, 2.0)
	sim.push_status(h, &"invisible", h.idx, 30.0)
	h.last_combat_time = -999.0
	place(a, h.pos + Vector2(130, 0))
	var ev3: Array = advance(sim, 2.5)
	check(not damage_events(ev3, a.idx, "", "SUMMON").is_empty(), "cerberus bites while hades is invisible")
	check(near(h.last_combat_time, -999.0) and pet.last_combat_time > 0.0, "summon damage does not refresh hades' combat timer (E22)")
	check(not sim.observes(a, h) and sim.kits.concealed(h), "cerberus bites keep hades concealed")
	# Respawn 15 s after it dies.
	sim.kill_unit(pet, a, {})
	var died: float = sim.time
	check(near(float(h.ks.pet_ready_at), died + 15.0, 1e-6), "cerberus respawn scheduled 15 s after death")
	advance(sim, 14.8)
	check(sim.kits.owned_entities(h, "cerberus").is_empty(), "no cerberus before 15 s")
	advance(sim, 0.4)
	var pet2: BUnit = one(sim, h, "cerberus")
	check(pet2 != null and pet2 != pet and near(pet2.hp, 420.0), "cerberus is back 15 s after death at full HP")
	# Owner death removes the companion.
	sim.kill_unit(h, a, {})
	check(pet2 != null and not pet2.alive, "cerberus disappears with hades")
	sim.dispose()


func hades_s1() -> void:
	var sim: BattleSim = fresh(["hades"], ["archer", "mage"])
	var h: BUnit = sim.heroes[0]
	var a: BUnit = sim.heroes[1]
	var m: BUnit = sim.heroes[2]
	place(h, Vector2(400, 400))
	place(a, Vector2(650, 400))
	place(m, Vector2(1300, 600))
	advance(sim, 0.1)
	drop_pet(sim, h)
	var s1: Defs.AbilityDef = h.def.abilities[0]
	check(not sim.kits.concealed(h) and not sim.ability_ready(h, 0, s1) and not ready_cast(sim, h, 1, h, h.pos), "S1 is blocked when hades is not concealed")
	place(a, Vector2(1300, 300))
	advance(sim, 0.1)
	check(sim.ability_ready(h, 0, s1), "S1 ready while concealed")
	# Concealment is only checked to start: being spotted in the windup is fine.
	check(ready_cast(sim, h, 1, h, h.pos), "S1 starts while concealed")
	place(a, Vector2(650, 400))
	advance(sim, 0.36)
	var shades: Array[BUnit] = sim.kits.owned_entities(h, "shade")
	check(shades.size() == 5, "S1 summons exactly 5 shades (%d)" % shades.size())
	var ring_ok: bool = shades.size() == 5
	var hp_ok: bool = shades.size() == 5
	for i in shades.size():
		var sh: BUnit = shades[i]
		var slot: Vector2 = h.pos + Vector2.from_angle(i * TAU / 5.0) * (sim.radius(h) + 30.0)
		ring_ok = ring_ok and sh.pos.distance_to(slot) < 1.0 and str(sh.ks.get("mode", "")) == "escort"
		hp_ok = hp_ok and near(sh.hp, 110.0 + 0.05 * 1220.0) and near(sim.stat(sh, &"armor"), 15.0) and near(sh.end_time - sh.spawn_time, 7.0, 1e-6)
	check(ring_ok, "shades stand in a ring of radius r+30 around hades")
	check(hp_ok, "shade HP 110+5% max HP (171), armor 15, 7 s")
	metrics["shade_hp"] = shades[0].hp if not shades.is_empty() else 0.0
	place(a, Vector2(1300, 300))
	# Escort keeps the slots when hades moves (owner MS + 60).
	place(h, h.pos + Vector2(100, 0))
	advance(sim, 1.0)
	var keep_ok: bool = true
	for i in shades.size():
		var slot2: Vector2 = h.pos + Vector2.from_angle(float(shades[i].ks.slot_angle)) * float(shades[i].ks.slot_radius)
		keep_ok = keep_ok and shades[i].pos.distance_to(slot2) < 1.5
	check(keep_ok, "escort shades keep their ring slots")
	# Bite only within 24 px of a shade; no chasing.
	var s0: BUnit = shades[0]
	place(a, s0.pos + Vector2(sim.radius(s0) + sim.radius(a) + 20.0, 0))
	place(m, s0.pos + Vector2(0, -(sim.radius(s0) + sim.radius(m) + 90.0)))
	var slot_before: Vector2 = s0.pos
	h.last_combat_time = -999.0
	var ev: Array = advance(sim, 1.6)
	var hits: Array = damage_events(ev, a.idx, "", "SUMMON")
	var expect: float = (8.0 + 0.12 * sim.stat(h, &"attackDamage")) * sim.resist_mult(sim.stat(a, &"magicResistance"))
	metrics["shade_bite"] = hits[0] if not hits.is_empty() else 0.0
	check(not hits.is_empty() and near(float(hits[0]), expect, 0.01), "shade bites within 24 px for 8+0.12AD magic (%s vs %.2f)" % [str(hits), expect])
	check(damage_events(ev, m.idx).is_empty() and s0.pos.distance_to(slot_before) < 1.0, "shades never chase an enemy 90 px away")
	check(near(h.last_combat_time, -999.0), "shade bites do not refresh hades' combat timer")
	# Skillshots hit the shade bodies.
	place(a, Vector2(1300, 300))
	place(m, Vector2(1300, 600))
	advance(sim, 0.5)
	var shooter: BUnit = m
	place(shooter, s0.pos + Vector2(250, 0))
	var pa: Defs.AbilityDef = Defs.AbilityDef.new()
	pa.speed = 700.0
	pa.range = 500.0
	pa.width = 8.0
	pa.id = "test_shot"
	var hp_h: float = h.hp
	var hp_s: float = s0.hp
	sim.proj.spawn(shooter, h, h.pos, pa, [{"type": "damage", "school": "true", "base": 40.0}], {"source_type": "ABILITY", "team": sim.eteam(shooter)})
	advance(sim, 0.6)
	check(s0.hp < hp_s and near(h.hp, hp_h, 0.001), "a skillshot is blocked by a shade body")
	sim.dispose()


func hades_s2() -> void:
	for case in [["low", 0.15, 25.0, true], ["high", 0.15, 160.0, false], ["shield", 0.14, 0.0, true]]:
		var sim: BattleSim = fresh(["hades"], ["archer"])
		var h: BUnit = sim.heroes[0]
		var t: BUnit = sim.heroes[1]
		place(h, Vector2(400, 400))
		place(t, Vector2(500, 400))
		advance(sim, 0.1)
		drop_pet(sim, h)
		var mx: float = sim.max_hp(t)
		var expect: float = (58.0 + 0.7 * sim.stat(h, &"attackDamage")) * sim.resist_mult(sim.stat(t, &"armor"))
		t.hp = mx * float(case[1]) + (expect if str(case[0]) != "shield" else 0.0) - float(case[2]) * (1.0 if str(case[0]) == "low" else -1.0)
		if str(case[0]) == "shield":
			sim.apply_shield(t, t, {"base": 500.0, "duration": 5.0})
		var hp0: float = t.hp
		var ev: Array = cast(sim, h, 2, t, t.pos)
		var dealt: float = hp0 - t.hp
		if str(case[0]) == "low":
			metrics["hades_s2_damage"] = dealt
			check(near(dealt, expect, 0.01), "S2 deals 58+0.7AD physical (%.2f vs %.2f)" % [dealt, expect])
		var hr: ST.Status = sim.get_status(t, &"healReduction")
		var blocked: bool = hr != null and near(hr.magnitude, 1.0) and near(hr.end - hr.start, 5.0 * 1.0, 1e-6)
		check(blocked == bool(case[3]), "S2 heal block only when HP < 15%% after the hit (%s: hp %.1f%%)" % [case[0], 100.0 * t.hp / mx])
		check((count_events(ev, "HEAL_BLOCKED", h.idx, t.idx) > 0) == bool(case[3]), "HEAL_BLOCKED event follows the heal block (%s)" % case[0])
		if bool(case[3]):
			var before: float = t.hp
			var r: Dictionary = sim.apply_heal(t, t, {"base": 200.0})
			check(near(float(r.effective), 0.0) and near(t.hp, before), "heal block stops all healing (%s)" % case[0])
		sim.dispose()


func hades_s3() -> void:
	# Below the cap: the gain equals the HP damage dealt.
	var sim: BattleSim = fresh(["hades"], ["swordsman"])
	var h: BUnit = sim.heroes[0]
	var g: BUnit = sim.heroes[1]
	place(h, Vector2(400, 400))
	place(g, Vector2(500, 400))
	advance(sim, 0.1)
	drop_pet(sim, h)
	var cast_t: float = sim.time
	var ev: Array = cast(sim, h, 3, h, h.pos, {}, 5.2)
	var ticks: Array = damage_events(ev, g.idx, "hades_3")
	var total: float = 0.0
	for x in ticks:
		total += float(x)
	metrics["soul_harvest_ticks_1_enemy"] = ticks.size()
	metrics["soul_harvest_first_tick"] = ticks[0] if not ticks.is_empty() else 0.0
	metrics["soul_harvest_gain_1_enemy"] = sim.max_hp(h) - 1220.0
	check(ticks.size() == 10, "soul harvest ticks 10 times in 5 s (%d)" % ticks.size())
	var first: float = (4.0 + 0.04 * 68.0 + 0.005 * 1220.0) * sim.resist_mult(sim.stat(g, &"magicResistance"))
	check(not ticks.is_empty() and near(float(ticks[0]), first, 0.01), "first harvest tick 4+0.04AD+0.5%% max HP magic (%.2f vs %.2f)" % [float(ticks[0]) if not ticks.is_empty() else 0.0, first])
	check(near(sim.max_hp(h) - 1220.0, total, 0.01) and near(h.hp, sim.max_hp(h), 0.01), "temporary max HP equals harvested damage and raises current HP (%.2f)" % total)
	sim.dispose()
	# Cap 15% of base max HP, expiry 8 s after the aura with an HP clamp.
	var sim2: BattleSim = fresh(["hades"], ["giant", "archer", "mage", "sniper"])
	var h2: BUnit = sim2.heroes[0]
	place(h2, Vector2(400, 400))
	for i in range(1, 5):
		place(sim2.heroes[i], h2.pos + Vector2.from_angle(i * TAU / 4.0) * 95.0)
	advance(sim2, 0.1)
	drop_pet(sim2, h2)
	var start: float = sim2.time
	cast(sim2, h2, 3, h2, h2.pos, {}, 5.2)
	metrics["soul_harvest_cap"] = sim2.max_hp(h2) - 1220.0
	check(near(sim2.max_hp(h2), 1220.0 * 1.15, 0.01), "harvested max HP caps at 15%% of base (%.2f)" % sim2.max_hp(h2))
	advance(sim2, (start + 0.1 + 5.0 + 8.0) - sim2.time - 0.3)
	check(near(sim2.max_hp(h2), 1403.0, 0.01), "temporary max HP lasts until 8 s after the aura")
	h2.hp = sim2.max_hp(h2)
	advance(sim2, 0.6)
	check(near(sim2.max_hp(h2), 1220.0, 0.01) and h2.hp <= 1220.0 + 1e-6, "after expiry max HP returns to 1220 and HP is clamped (%.1f)" % h2.hp)
	sim2.dispose()
	# Only enemies hades observes: an invisible enemy is not harvested.
	var sim3: BattleSim = fresh(["hades"], ["giant"])
	var h3: BUnit = sim3.heroes[0]
	var g3: BUnit = sim3.heroes[1]
	place(h3, Vector2(400, 400))
	place(g3, Vector2(400 + 19 + 24 + 64 + 20, 400))
	advance(sim3, 0.1)
	drop_pet(sim3, h3)
	sim3.push_status(g3, &"invisible", g3.idx, 10.0)
	var ev3: Array = cast(sim3, h3, 3, h3, h3.pos, {}, 2.0)
	check(not sim3.observes(h3, g3) and damage_events(ev3, g3.idx, "hades_3").is_empty(), "harvest skips enemies hades cannot see")
	sim3.dispose()


# ------------------------------------------------------------------ war machine

func fuel() -> void:
	var sim: BattleSim = fresh(["war_machine"], ["giant", "hades"])
	var w: BUnit = sim.heroes[0]
	var g: BUnit = sim.heroes[1]
	var hd: BUnit = sim.heroes[2]
	place(w, Vector2(400, 400))
	place(g, Vector2(400 + 18 + 24 + 30, 400))
	place(hd, Vector2(1300, 600))
	advance(sim, 0.1)
	check(near(float(w.resources.get("fuel", -1.0)), 0.0), "fuel starts at 0")
	for i in 12:
		g.hp = sim.max_hp(g)
		w.attack_ready_at = sim.time
		sim.start_basic(w, g)
		advance(sim, 0.4)
		if i == 0:
			check(near(float(w.resources.fuel), 2.0), "one basic hit adds 2 fuel (%.1f)" % float(w.resources.fuel))
	metrics["fuel_after_12_basics"] = float(w.resources.fuel)
	check(near(float(w.resources.fuel), 10.0), "basic hits add 2 fuel each, capped at 10")
	w.resources["fuel"] = 3.0
	sim.apply_damage(w, g, {"type": "damage", "school": "physical", "base": 50.0}, sim.context(w, w.def.abilities[1], {}))
	check(near(float(w.resources.fuel), 3.0), "ability damage does not refuel")
	# Enemy structure (another fuel tank) gives nothing, an enemy summon does.
	var pet: BUnit = one(sim, hd, "cerberus")
	if pet:
		place(pet, w.pos + Vector2(0, 18 + 14 + 25))
		pet.ks["mode"] = "test_idle"
		w.attack_ready_at = sim.time
		check(sim.start_basic(w, pet), "war machine can basic the enemy cerberus")
		advance(sim, 0.3)
		check(near(float(w.resources.fuel), 5.0), "basic on a non-structure summon refuels (+2)")
	sim.dispose()
	var sim2: BattleSim = fresh(["war_machine"], ["war_machine"])
	var w1: BUnit = sim2.heroes[0]
	var w2: BUnit = sim2.heroes[1]
	place(w1, Vector2(400, 400))
	place(w2, Vector2(800, 400))
	w2.facing = Vector2.LEFT
	advance(sim2, 0.1)
	var tank2: BUnit = one(sim2, w2, "fuel_tank")
	place(w2, Vector2(400 + 80, 400))
	w2.facing = Vector2.RIGHT
	advance(sim2, 0.05)
	w1.attack_ready_at = sim2.time
	var ok: bool = tank2 != null and sim2.start_basic(w1, tank2)
	advance(sim2, 0.3)
	check(ok and tank2.hp < 300.0 and near(float(w1.resources.fuel), 0.0), "basic on an enemy structure (fuel tank) does not refuel")
	sim2.dispose()


func tank() -> void:
	var sim: BattleSim = fresh(["war_machine"], ["archer", "mage"])
	var w: BUnit = sim.heroes[0]
	var a: BUnit = sim.heroes[1]
	var m: BUnit = sim.heroes[2]
	place(w, Vector2(500, 400))
	w.facing = Vector2.RIGHT
	place(a, Vector2(1300, 250))
	place(m, Vector2(1300, 550))
	step(sim)
	var t: BUnit = one(sim, w, "fuel_tank")
	check(t != null, "fuel tank spawns lazily on the first tick")
	if t == null:
		sim.dispose()
		return
	check(t.structure and near(t.hp, 300.0) and near(sim.stat(t, &"armor"), 40.0) and near(sim.stat(t, &"magicResistance"), 40.0) and near(t.base_radius, 10.0), "tank HP 300, armor/MR 40, radius 10, structure")
	check(t.pos.distance_to(w.pos - Vector2.RIGHT * (18.0 + 10.0 + 2.0)) < 0.01, "tank attached at pos - facing x (r_o + r_t + 2)")
	w.facing = Vector2.UP
	step(sim)
	check(t.pos.distance_to(w.pos - Vector2.UP * 30.0) < 0.01, "tank follows the facing")
	w.facing = Vector2.RIGHT
	step(sim)
	var pa: Defs.AbilityDef = Defs.AbilityDef.new()
	pa.speed = 600.0
	pa.range = 600.0
	pa.width = 8.0
	pa.id = "test_shot"
	# From behind: the tank is hit first.
	place(a, w.pos + Vector2(-300, 0))
	var hp_w: float = w.hp
	var hp_t: float = t.hp
	sim.proj.spawn(a, w, w.pos, pa, [{"type": "damage", "school": "true", "base": 40.0}], {"source_type": "ABILITY", "team": sim.eteam(a)})
	advance(sim, 0.7)
	check(t.hp < hp_t and near(w.hp, hp_w), "a projectile from behind hits the tank first")
	# From the front: the hero is hit.
	place(a, w.pos + Vector2(300, 0))
	hp_t = t.hp
	sim.proj.spawn(a, w, w.pos, pa, [{"type": "damage", "school": "true", "base": 40.0}], {"source_type": "ABILITY", "team": sim.eteam(a)})
	advance(sim, 0.7)
	check(w.hp < hp_w and near(t.hp, hp_t), "a projectile from the front hits war machine")
	place(a, Vector2(1300, 250))
	# Area / zone / cone hits on the tank count x0.5, single hits in full.
	hp_t = t.hp
	sim.apply_damage(a, t, {"type": "damage", "school": "true", "base": 40.0, "frozen": true}, {"source_type": "ABILITY"})
	var single: float = hp_t - t.hp
	hp_t = t.hp
	sim.resolve_area(a, t.pos, 4.0, [{"type": "damage", "school": "true", "base": 40.0, "frozen": true}], {"source_type": "ABILITY", "team": sim.eteam(a)})
	var area: float = hp_t - t.hp
	metrics["tank_single_vs_area"] = [single, area]
	check(near(single, 40.0) and near(area, 20.0), "tank takes area damage x0.5 (%.1f vs %.1f)" % [single, area])
	hp_t = t.hp
	sim.zones.spawn(a, t.pos, 4.0, 0.2, 1.0, [{"type": "damage", "school": "true", "base": 40.0, "frozen": true}], "enemy", {"team": sim.eteam(a)}, "zone")
	step(sim)
	check(near(hp_t - t.hp, 20.0), "tank takes zone ticks x0.5 (%.1f)" % (hp_t - t.hp))
	sim.dispose()


func tank_destroyed() -> void:
	var sim: BattleSim = fresh(["war_machine"], ["giant"])
	var w: BUnit = sim.heroes[0]
	var g: BUnit = sim.heroes[1]
	place(w, Vector2(400, 400))
	place(g, Vector2(1300, 400))
	advance(sim, 0.1)
	var t: BUnit = one(sim, w, "fuel_tank")
	w.resources["fuel"] = 6.0
	var ev: Array = []
	sim.apply_damage(g, t, {"type": "damage", "school": "true", "base": 1000.0, "frozen": true}, {"source_type": "ABILITY"})
	var died: float = sim.time
	ev.append_array(sim.tick_events)
	check(t != null and not t.alive, "tank can be destroyed")
	check(near(float(w.resources.fuel), 0.0), "tank destruction empties the fuel")
	var od: ST.Status = sim.get_status(w, &"overdrive")
	check(od != null and near(od.end - od.start, 10.0, 1e-6), "overdrive lasts 10 s")
	check(count_events(sim.tick_events, "TANK_DESTROYED") == 1 and count_events(sim.tick_events, "OVERDRIVE", w.idx) == 1, "TANK_DESTROYED and OVERDRIVE events")
	metrics["overdrive_as_ms"] = [sim.stat(w, &"attackSpeed"), sim.stat(w, &"moveSpeed")]
	check(near(sim.stat(w, &"attackSpeed"), 0.92 * 1.5, 1e-4) and near(sim.stat(w, &"moveSpeed"), 116.0 * 1.5, 1e-4), "overdrive multiplies AS and MS by 1.5")
	w.resources["fuel"] = 10.0
	var locked: bool = true
	for i in range(1, 4):
		w.cooldowns[i] = 0.0
		locked = locked and not sim.ability_ready(w, i, w.def.abilities[i])
	check(locked, "overdrive locks slots 2-4")
	w.resources["fuel"] = 0.0
	w.cooldowns[0] = 0.0
	check(sim.ability_ready(w, 0, w.def.abilities[0]), "S1 is ready with 0 fuel in overdrive")
	var from: Vector2 = w.pos
	var r: Array = cast(sim, w, 1, null, w.pos + Vector2(110, 0), {}, 0.3)
	check(bool(r[0]) and near(float(w.resources.fuel), 0.0) and w.pos.distance_to(from) > 100.0, "S1 is free in overdrive (moved %.1f)" % w.pos.distance_to(from))
	# No fuel while the tank is down.
	place(g, w.pos + Vector2(18 + 24 + 30, 0))
	w.attack_ready_at = sim.time
	sim.start_basic(w, g)
	advance(sim, 0.3)
	check(near(float(w.resources.fuel), 0.0), "no fuel while the tank is destroyed")
	place(g, Vector2(1300, 400))
	advance(sim, died + 9.8 - sim.time)
	check(sim.kits.owned_entities(w, "fuel_tank").is_empty(), "no tank before 10 s")
	advance(sim, 0.4)
	var t2: BUnit = one(sim, w, "fuel_tank")
	check(t2 != null and near(t2.hp, 300.0) and sim.get_status(w, &"overdrive") == null and near(sim.stat(w, &"attackSpeed"), 0.92, 1e-6), "tank is back after 10 s and overdrive ended")
	sim.dispose()


func booster() -> void:
	var sim: BattleSim = fresh(["war_machine"], ["giant"])
	var w: BUnit = sim.heroes[0]
	place(w, Vector2(400, 400))
	advance(sim, 0.1)
	w.resources["fuel"] = 3.0
	var from: Vector2 = w.pos
	var r: Array = cast(sim, w, 1, null, w.pos + Vector2(110, 0), {}, 0.3)
	metrics["booster_distance"] = w.pos.distance_to(from)
	check(bool(r[0]) and near(float(w.resources.fuel), 2.0) and near(w.pos.distance_to(from), 110.0, 1.0), "booster dashes 110 for 1 fuel")
	w.resources["fuel"] = 0.0
	w.cooldowns[0] = 0.0
	check(not sim.ability_ready(w, 0, w.def.abilities[0]), "booster needs 1 fuel outside overdrive")
	sim.dispose()


func missiles() -> void:
	var times: Dictionary = {}
	for n in range(2, 7):
		var sim: BattleSim = fresh(["war_machine"], ["swordsman"])
		var w: BUnit = sim.heroes[0]
		var g: BUnit = sim.heroes[1]
		place(w, Vector2(400, 400))
		place(g, Vector2(700, 400))
		advance(sim, 0.1)
		w.resources["fuel"] = 10.0
		var expect: float = (24.0 + 0.3 * 105.0) * sim.resist_mult(sim.stat(g, &"armor"))
		check(ready_cast(sim, w, 2, g, g.pos, {"charge": n}), "missiles start with charge %d" % n)
		var ct: float = w.action.resolve_at - w.action.started_at
		times[n] = ct
		check(near(ct, 0.2 + 0.3 * (n - 2), 1e-6), "cast time 0.2+0.3(N-2) for N=%d (%.2f)" % [n, ct])
		check(near(sim.stat(w, &"moveSpeed"), 116.0 * 0.6, 1e-4), "move speed -40%% while charging (N=%d)" % n)
		var ev: Array = advance(sim, ct + 0.05)
		var shots: int = 0
		for e in ev:
			if str(e.type) == "PROJECTILE_CREATED" and int(e.s) == w.idx and e.get("ability") is Defs.AbilityDef and (e.ability as Defs.AbilityDef).id == "war_machine_2":
				shots += 1
		check(shots == n, "N=%d missiles fired (%d)" % [n, shots])
		check(near(float(w.resources.fuel), 10.0 - n), "1 fuel per missile (N=%d, fuel %.0f)" % [n, float(w.resources.fuel)])
		check(near(sim.stat(w, &"moveSpeed"), 116.0, 1e-4), "charge slow ends at release")
		ev.append_array(advance(sim, 1.5))
		var hits: Array = damage_events(ev, g.idx, "war_machine_2")
		check(hits.size() == n and near(float(hits[0]), expect, 0.01), "N=%d homing missiles hit for 24+0.3AD each (%d hits, %.2f vs %.2f)" % [n, hits.size(), float(hits[0]) if not hits.is_empty() else 0.0, expect])
		if n == 6:
			metrics["missile_hit"] = hits[0] if not hits.is_empty() else 0.0
		sim.dispose()
	metrics["missile_cast_times"] = times
	var s2: BattleSim = fresh(["war_machine"], ["giant"])
	var w2: BUnit = s2.heroes[0]
	var g2: BUnit = s2.heroes[1]
	place(w2, Vector2(400, 400))
	place(g2, Vector2(700, 400))
	advance(s2, 0.1)
	w2.resources["fuel"] = 3.0
	check(not ready_cast(s2, w2, 2, g2, g2.pos, {"charge": 4}), "charge above the fuel is rejected")
	check(ready_cast(s2, w2, 2, g2, g2.pos) and int(w2.action.extra.charge) == 3, "default charge = min(6, fuel)")
	s2.cancel_action(w2, "test")
	w2.resources["fuel"] = 10.0
	check(ready_cast(s2, w2, 2, g2, g2.pos, {"charge": 6}), "6-missile charge starts")
	advance(s2, 0.5)
	s2.apply_status(g2, w2, {"status": "stun", "duration": 0.5})
	advance(s2, 1.2)
	check(near(float(w2.resources.fuel), 10.0) and w2.action == null, "hard CC cancels the charge without spending fuel")
	check(near(s2.stat(w2, &"moveSpeed"), 116.0, 1e-4), "cancel removes the charge slow")
	s2.dispose()


func arc_protector() -> void:
	var sim: BattleSim = fresh(["war_machine"], ["giant"])
	var w: BUnit = sim.heroes[0]
	var g: BUnit = sim.heroes[1]
	place(w, Vector2(400, 400))
	place(g, Vector2(1300, 400))
	advance(sim, 0.1)
	cast(sim, w, 3, w, w.pos)
	check(near(sim.incoming_mult(w), 0.6, 1e-6), "arc protector: damage taken -40%")
	var hp0: float = w.hp
	sim.apply_damage(g, w, {"type": "damage", "school": "true", "base": 100.0, "frozen": true}, {"source_type": "ABILITY"})
	metrics["arc_hit_100"] = hp0 - w.hp
	check(near(hp0 - w.hp, 60.0, 1e-4), "100 true damage becomes 60")
	var arc: float = 0.0
	for sh in w.shields:
		if sh.tag == "arc":
			arc += sh.amount
	metrics["arc_shield_from_60"] = arc
	check(near(arc, 9.0, 1e-4), "15%% of the reduced damage becomes a shield (%.2f)" % arc)
	# Cap: arc shields never exceed 20% max HP (a shorter outer shield soaks the hits).
	sim.apply_shield(w, w, {"base": 5000.0, "duration": 2.0})
	for i in 4:
		sim.apply_damage(g, w, {"type": "damage", "school": "true", "base": 1000.0, "frozen": true}, {"source_type": "ABILITY"})
	arc = 0.0
	for sh in w.shields:
		if sh.tag == "arc" and sh.end > sim.time:
			arc += sh.amount
	metrics["arc_shield_cap"] = arc
	check(near(arc, 0.2 * 1020.0, 1e-3), "arc shield caps at 20%% max HP (%.2f)" % arc)
	var arc_end: float = 0.0
	for sh in w.shields:
		if sh.tag == "arc":
			arc_end = maxf(arc_end, sh.end - sim.time)
	check(near(arc_end, 4.0, 1e-6), "arc shield lasts 4 s")
	advance(sim, 3.2)
	check(near(sim.incoming_mult(w), 1.0, 1e-6), "damage reduction ends after 3 s")
	sim.dispose()


func genocide() -> void:
	var sim: BattleSim = fresh(["war_machine"], ["swordsman", "archer", "mage", "sniper"])
	var w: BUnit = sim.heroes[0]
	var inside: BUnit = sim.heroes[1]
	var side: BUnit = sim.heroes[2]
	var far: BUnit = sim.heroes[3]
	var back: BUnit = sim.heroes[4]
	place(w, Vector2(300, 400))
	for u in [inside, side, far, back]:
		place(u, Vector2(1300, 100))
	advance(sim, 0.1)
	w.resources["fuel"] = 6.0
	w.cooldowns[3] = 0.0
	check(not sim.ability_ready(w, 3, w.def.abilities[3]), "genocide needs 7 fuel")
	w.resources["fuel"] = 7.0
	check(ready_cast(sim, w, 4, null, w.pos + Vector2(300, 0)), "genocide starts with 7 fuel")
	var line: bool = false
	for tg in sim.telegraphs:
		if int(tg.source) == w.idx and str(tg.shape) == "line" and near(float(tg.width), 90.0):
			line = true
	check(line, "genocide shows a public line telegraph during its 0.6 s cast")
	place(inside, w.pos + Vector2(200, 30))
	place(side, w.pos + Vector2(200, 80))
	place(far, w.pos + Vector2(460, 0))
	place(back, w.pos + Vector2(-100, 0))
	var ev: Array = advance(sim, 0.65)
	check(near(float(w.resources.fuel), 0.0), "genocide spends 7 fuel")
	var zone: ST.Zone = null
	for z in sim.zones.list:
		if z.source_idx == w.idx and z.shape == "rect":
			zone = z
	check(zone != null and near(zone.range, 380.0) and near(zone.width, 90.0) and near(zone.end - zone.start, 4.0, 1e-6), "rect zone 380 x 90 for 4 s")
	ev.append_array(advance(sim, 4.2))
	var hits: Array = damage_events(ev, inside.idx, "war_machine_4")
	var expect: float = (12.0 + 0.15 * 105.0) * sim.resist_mult(sim.stat(inside, &"armor"))
	metrics["genocide_ticks"] = hits.size()
	metrics["genocide_tick"] = hits[0] if not hits.is_empty() else 0.0
	check(hits.size() >= 8 and near(float(hits[0]), expect, 0.01), "inside the rect: 12+0.15AD every 0.5 s (%d ticks, %.2f vs %.2f)" % [hits.size(), float(hits[0]) if not hits.is_empty() else 0.0, expect])
	check(damage_events(ev, side.idx).is_empty() and damage_events(ev, far.idx).is_empty() and damage_events(ev, back.idx).is_empty(), "outside the rect (side, beyond the end, behind) nothing")
	var slowed: bool = false
	for e in ev:
		if str(e.type) == "CC_APPLIED" and int(e.g) == inside.idx and str(e.status) == "slow":
			slowed = true
	check(slowed, "genocide slows 35% for 0.6 s")
	sim.dispose()


# ------------------------------------------------------------------ torquemada

func torquemada_tenacity() -> void:
	var sim: BattleSim = fresh(["torquemada"], ["archer"])
	var t: BUnit = sim.heroes[0]
	var a: BUnit = sim.heroes[1]
	advance(sim, 0.1)
	check(near(sim.stat(t, &"tenacity"), 0.35), "torquemada tenacity 0.35")
	sim.apply_status(a, t, {"status": "stun", "duration": 1.0})
	var st: ST.Status = sim.get_status(t, &"stun")
	metrics["torquemada_stun_1s"] = st.duration if st else 0.0
	check(st != null and near(st.duration, 0.65, 1e-6), "a 1.0 s stun lasts 0.65 s")
	sim.remove_statuses_where(t, func(x): return true)
	sim.apply_status(a, t, {"status": "charm", "duration": 1.0})
	var ch: ST.Status = sim.get_status(t, &"charm")
	metrics["torquemada_charm_1s"] = ch.duration if ch else 0.0
	check(ch != null and near(ch.duration, 0.325, 1e-6), "a 1.0 s charm lasts 0.325 s (multiplicative)")
	sim.dispose()


func cleanse() -> void:
	var sim: BattleSim = fresh(["torquemada", "swordsman"], ["archer", "mage"])
	var t: BUnit = sim.heroes[0]
	var ally: BUnit = sim.heroes[1]
	var a: BUnit = sim.heroes[2]
	var m: BUnit = sim.heroes[3]
	place(t, Vector2(400, 400))
	place(ally, Vector2(600, 400))
	place(a, Vector2(1300, 300))
	place(m, Vector2(1300, 500))
	advance(sim, 0.1)
	for f in [{"status": "stun", "duration": 4.0}, {"status": "root", "duration": 4.0}, {"status": "slow", "duration": 4.0, "magnitude": 0.3},
			{"status": "silence", "duration": 4.0}, {"status": "roar", "duration": 6.0, "tenacityLoss": 0.1}]:
		sim.apply_status(a, ally, f)
	sim.apply_status(m, ally, {"status": "healReduction", "magnitude": 0.5, "duration": 4.0})
	sim.apply_status(m, ally, {"status": "damageAmp", "damageAmp": 0.2, "duration": 4.0})
	sim.push_status(ally, &"sniperVulnerable", a.idx, 4.0, {"damageAmp": 0.16})
	sim.apply_mark(a, ally, {"status": "confusion", "stacks": 2, "duration": 7.0, "maxStacks": 5})
	sim.apply_mark(a, ally, {"status": "pain", "stacks": 2, "duration": 4.0, "maxStacks": 6})
	sim.apply_dot(a, ally, {"interval": 1.0, "duration": 4.0, "damageEffect": {"type": "damage", "school": "true", "base": 1.0}})
	sim.add_buff(ally, &"attackDamageFlat", -10.0, 5.0, a.idx, {"tag": "theft:test"})
	sim.add_buff(ally, &"originStatSwap", 1.0, 5.0, m.idx, {"tag": "statSwap"})
	# Kept: marks, imprisonment, seals, chamber / motion statuses, own and allied effects.
	sim.apply_mark(a, ally, {"status": "hooked", "duration": 3.0, "stacks": 1, "maxStacks": 1})
	sim.apply_mark(a, ally, {"status": "bladeMark", "duration": 4.0})
	sim.apply_mark(a, ally, {"status": "infection", "duration": 8.0})
	sim.push_status(ally, &"imprisoned", a.idx, 3.5)
	sim.push_status(ally, &"nexus_seal", a.idx, 100.0, {"slots": []})
	sim.push_status(ally, &"suppression", a.idx, 3.0, {"chamber": "chamber_test"})
	sim.push_status(ally, &"stun", a.idx, 3.0, {"motion_id": 4242})
	sim.push_status(ally, &"overdrive", ally.idx, 5.0)
	sim.push_status(ally, &"frenzy", t.idx, 3.0)
	sim.add_buff(ally, &"attackDamage", 0.2, 5.0, t.idx, {"tag": "ally_buff"})
	sim.add_buff(ally, &"attackDamage", -0.15, 4.0, t.idx, {"tag": "ally_debuff"})
	ally.command = {"kind": "move", "pos": Vector2(700, 400)}
	var r: Array = cast(sim, t, 1, null, ally.pos, {}, 0.0)
	var ev: Array = r.slice(1)
	var removed_ok: bool = true
	for st in [&"root", &"slow", &"silence", &"roar", &"healReduction", &"damageAmp", &"sniperVulnerable", &"confusion", &"pain", &"dot"]:
		removed_ok = removed_ok and not sim.has_status(ally, st)
	var stun_left: Array = []
	for x in ally.statuses:
		if x.type == &"stun":
			stun_left.append(x.extra.has("motion_id"))
	check(bool(r[0]) and removed_ok and stun_left == [true], "cleanse removes CC, harmful statuses and enemy DoT (motion stun kept) %s" % str(stun_left))
	var buffs_ok: bool = sim.get_buff(ally, &"attackDamageFlat") == null and sim.get_buff(ally, &"originStatSwap") == null
	var ally_buffs: int = 0
	for b in ally.buffs:
		if b.stat == &"attackDamage":
			ally_buffs += 1
	check(buffs_ok and ally_buffs == 2, "cleanse removes enemy stat debuffs and keeps allied buffs")
	var kept_ok: bool = true
	for st2 in [&"hooked", &"bladeMark", &"infection", &"imprisoned", &"nexus_seal", &"suppression", &"overdrive", &"frenzy"]:
		kept_ok = kept_ok and sim.has_status(ally, st2)
	check(kept_ok, "cleanse keeps marks, imprisoned, nexus_seal, chamber statuses, overdrive and allied statuses")
	check(count_events(ev, "CLEANSED", t.idx, ally.idx) == 1, "CLEANSED event")
	check(ally.command.is_empty(), "removing crowd control resets the ally's commitment")
	# oncePerUnit: a new stun inside the same fire stays.
	sim.remove_statuses_where(ally, func(x): return x.extra.has("motion_id"))
	sim.apply_status(a, ally, {"status": "stun", "duration": 1.5})
	advance(sim, 0.5)
	check(sim.has_status(ally, &"stun"), "one fire cleanses each ally only once (oncePerUnit)")
	# Another ally entering later is still cleansed once.
	sim.apply_status(a, t, {"status": "root", "duration": 3.0})
	place(t, ally.pos + Vector2(30, 0))
	advance(sim, 0.25)
	check(not sim.has_status(t, &"root"), "a unit entering later is cleansed on its first tick")
	# One fire per caster.
	place(t, Vector2(400, 400))
	sim.remove_statuses_where(t, func(x): return true)
	cast(sim, t, 1, null, Vector2(400, 600), {}, 0.0)
	var live: int = 0
	var filters: Dictionary = {}
	var same_fire: bool = true
	for z in sim.zones.list:
		if z.source_idx == t.idx and not z.finished and z.end > sim.time:
			live += 1
			filters[z.filter] = int(filters.get(z.filter, 0)) + 1
			same_fire = same_fire and z.pos.distance_to(Vector2(400, 600)) < 0.01
	check(live == 2 and filters.get("ally", 0) == 1 and filters.get("enemy", 0) == 1 and same_fire,
		"torquemada replaces the previous fire with exactly one ally/enemy zone pair (%d)" % live)
	# Enemies inside an ally fire are not cleansed.
	place(m, Vector2(400, 600))
	sim.apply_status(t, m, {"status": "root", "duration": 2.0})
	advance(sim, 0.3)
	check(sim.has_status(m, &"root"), "the fire cleanses allies only")
	sim.dispose()


func torquemada_s2() -> void:
	var sim: BattleSim = fresh(["torquemada"], ["archer", "mage"])
	var t: BUnit = sim.heroes[0]
	var a: BUnit = sim.heroes[1]
	var m: BUnit = sim.heroes[2]
	place(t, Vector2(400, 400))
	place(a, Vector2(700, 400))
	place(m, Vector2(700, 520))
	advance(sim, 0.1)
	var s2: Defs.AbilityDef = t.def.abilities[1]
	check(near(s2.cooldown, 9.0) and near(float(s2.condition.ccSourceWithin), 8.0), "v3 S2 pins: cooldown 9, retaliatory window 8")
	check(not sim.check_condition(t, a, s2.condition) and not ready_cast(sim, t, 2, a, a.pos), "S2 needs an enemy that crowd-controlled torquemada")
	sim.apply_status(a, t, {"status": "slow", "duration": 1.0, "magnitude": 0.3})
	check(not sim.check_condition(t, a, s2.condition), "a slow does not count")
	sim.apply_status(a, t, {"status": "stun", "duration": 0.5})
	check(not sim.ability_ready(t, 1, s2), "S2 cannot be cast while stunned")
	advance(sim, 0.4)
	check(sim.check_condition(t, a, s2.condition) and not sim.check_condition(t, m, s2.condition), "the stunning enemy is recorded, the other is not")
	var r: Array = cast(sim, t, 2, a, a.pos)
	var root: ST.Status = sim.get_status(a, &"root")
	metrics["torquemada_s2_root"] = root.duration if root else 0.0
	check(bool(r[0]) and root != null and near(root.duration, 1.25 * (1.0 - 0.05), 1e-6), "S2 roots for 1.25 s (tenacity applies: %.4f)" % (root.duration if root else 0.0))
	# The engine's current condition window remains the authority.
	advance(sim, float(s2.condition.ccSourceWithin))
	check(not sim.check_condition(t, a, s2.condition), "the CC record expires after its configured window")
	# Knockback counts.
	sim.kits.displace(m, t, {"mode": "knockback", "distance": 40.0, "speed": 400.0}, {})
	check(sim.check_condition(t, m, s2.condition), "a knockback counts as crowd control")
	advance(sim, 0.3)
	# Zone crowd control is recorded to the zone owner.
	sim.zones.spawn(a, t.pos, 60.0, 0.3, 0.2, [{"type": "status", "status": "stun", "duration": 0.2}], "enemy", {"team": sim.eteam(a)}, "zone")
	step(sim)
	check(sim.check_condition(t, a, s2.condition), "zone crowd control is recorded to its owner")
	advance(sim, 0.4)
	# The command path only targets enemies torquemada observes.
	sim.push_status(a, &"invisible", a.idx, 5.0)
	place(a, Vector2(800, 400))
	step(sim)
	t.cooldowns[1] = 0.0
	t.command = {"kind": "ability", "index": 1, "ability_id": s2.id, "target": a.idx, "pos": a.pos}
	sim._try_execute_command(t)
	check(not sim.observes(t, a) and t.action == null and t.command.is_empty(), "S2 cannot target an enemy torquemada does not observe")
	sim.dispose()


func alhambra() -> void:
	var sim: BattleSim = fresh(["torquemada", "swordsman"], ["archer", "mage"])
	var t: BUnit = sim.heroes[0]
	var ally: BUnit = sim.heroes[1]
	var a: BUnit = sim.heroes[2]
	var m: BUnit = sim.heroes[3]
	place(t, Vector2(500, 400))
	place(ally, Vector2(560, 400))
	place(m, Vector2(600, 460))
	place(a, Vector2(800, 400))
	advance(sim, 0.1)
	sim.apply_status(a, ally, {"status": "stun", "duration": 3.0})
	var d0: float = m.pos.distance_to(t.pos)
	var a0: Vector2 = a.pos
	cast(sim, t, 3, t, t.pos, {}, 0.5)
	var moved: float = m.pos.distance_to(t.pos) - d0
	metrics["alhambra_push"] = moved
	check(not sim.has_status(ally, &"stun"), "alhambra cleanses allies within 150")
	check(near(moved, 140.0, 1.5), "alhambra pushes enemies 140 outward (%.1f)" % moved)
	check(a.pos.distance_to(a0) < 0.01, "enemies outside 150 are not pushed")
	sim.dispose()


# H-BALANCE tq_v3: real casts, per-unit event counts and actual effect amounts.
func tq_v3_events(events: Array, type: String, source: int, target: int, ability_id: String) -> Array:
	var out: Array = []
	for ev in events:
		if not (ev is Dictionary) or str(ev.type) != type or int(ev.s) != source or int(ev.g) != target:
			continue
		var ab = ev.get("ability")
		if ab is Defs.AbilityDef and (ab as Defs.AbilityDef).id == ability_id:
			out.append(ev)
	return out


func tq_v3_amounts(events: Array, expected: float) -> bool:
	if events.is_empty(): return false
	for ev in events:
		if float(ev.amount) <= 0.0 or not near(float(ev.amount), expected, 1e-3): return false
	return true


func torquemada_v3_effects() -> void:
	var sim: BattleSim = fresh(["torquemada", "swordsman"], ["archer", "mage"])
	var t: BUnit = sim.heroes[0]
	var ally: BUnit = sim.heroes[1]
	var enemy: BUnit = sim.heroes[2]
	var outside: BUnit = sim.heroes[3]
	var center: Vector2 = Vector2(600, 400)
	place(t, Vector2(400, 400))
	place(ally, center)
	place(enemy, center + Vector2(40, 40))
	place(outside, Vector2(1000, 400))
	ally.hp = sim.max_hp(ally) - 400.0
	var hp0: float = ally.hp
	sim.apply_status(enemy, ally, {"status": "stun", "duration": 3.0})
	sim.apply_status(enemy, ally, {"status": "healReduction", "magnitude": 0.5, "duration": 3.0})
	var ev: Array = cast(sim, t, 1, null, center, {}, 1.1)
	var heals: Array = tq_v3_events(ev, "HEAL_APPLIED", t.idx, ally.idx, "torquemada_1")
	var hits: Array = tq_v3_events(ev, "HEALTH_DAMAGED", t.idx, enemy.idx, "torquemada_1")
	var tick_damage: float = 35.0 * 100.0 / (100.0 + sim.stat(enemy, &"magicResistance"))
	check(bool(ev[0]) and tq_v3_events(ev, "CLEANSED", t.idx, ally.idx, "torquemada_1").size() == 1
		and not sim.has_status(ally, &"stun") and not sim.has_status(ally, &"healReduction"), "v3 S1 cleanses its ally once before healing")
	check(heals.size() == 1 and tq_v3_amounts(heals, 110.0) and near(ally.hp - hp0, 110.0), "v3 S1 heals its wounded ally exactly 110 once after removing heal reduction")
	check(hits.size() == 3 and tq_v3_amounts(hits, tick_damage), "v3 S1 deals three positive, resistance-adjusted 35 magic ticks during its first 1.1 seconds")
	check(hits.size() == 3 and near(float(hits[1].t) - float(hits[0].t), 0.5, BattleSim.DT)
		and near(float(hits[2].t) - float(hits[1].t), 0.5, BattleSim.DT), "v3 S1 repeats enemy damage at 0.5-second intervals")
	check(tq_v3_events(ev, "HEALTH_DAMAGED", t.idx, ally.idx, "torquemada_1").is_empty()
		and tq_v3_events(ev, "HEAL_APPLIED", t.idx, enemy.idx, "torquemada_1").is_empty()
		and tq_v3_events(ev, "CLEANSED", t.idx, enemy.idx, "torquemada_1").is_empty(), "v3 S1 separates ally cleanse/heal from enemy damage")
	check(tq_v3_events(ev, "HEALTH_DAMAGED", t.idx, outside.idx, "torquemada_1").is_empty(), "v3 S1 does not damage the enemy outside its fire")
	# Same ally, a fresh debuff and new missing health: oncePerUnit covers both effects.
	ally.hp -= 40.0
	var after_first_heal: float = ally.hp
	sim.apply_status(enemy, ally, {"status": "stun", "duration": 1.5})
	var repeated: Array = advance(sim, 0.6)
	check(sim.has_status(ally, &"stun") and near(ally.hp, after_first_heal)
		and tq_v3_events(repeated, "HEAL_APPLIED", t.idx, ally.idx, "torquemada_1").is_empty()
		and tq_v3_events(repeated, "CLEANSED", t.idx, ally.idx, "torquemada_1").is_empty(), "v3 S1 never repeats cleanse or heal on an already served ally")
	check(tq_v3_amounts(tq_v3_events(repeated, "HEALTH_DAMAGED", t.idx, enemy.idx, "torquemada_1"), tick_damage), "v3 S1 continues enemy damage while ally effects stay once per unit")
	var old_ids: Array = []
	for z in sim.zones.list:
		if z.source_idx == t.idx and z.end > sim.time and not z.finished: old_ids.append(z.id)
	var new_center: Vector2 = Vector2(400, 600)
	place(outside, new_center + Vector2(40, 40))
	var recast: Array = cast(sim, t, 1, null, new_center, {}, 0.1)
	var new_filters: Dictionary = {}
	var replaced: bool = true
	for z in sim.zones.list:
		if z.source_idx != t.idx or z.end <= sim.time or z.finished: continue
		replaced = replaced and not old_ids.has(z.id) and z.pos.distance_to(new_center) < 0.01
		new_filters[z.filter] = int(new_filters.get(z.filter, 0)) + 1
	check(bool(recast[0]) and old_ids.size() == 2 and replaced and new_filters.get("ally", 0) == 1
		and new_filters.get("enemy", 0) == 1 and new_filters.size() == 2, "v3 S1 recast replaces both old layers with one new ally/enemy pair")
	var old_enemy_hp: float = enemy.hp
	var after_recast: Array = advance(sim, 0.6)
	check(near(enemy.hp, old_enemy_hp) and tq_v3_events(after_recast, "HEALTH_DAMAGED", t.idx, enemy.idx, "torquemada_1").is_empty()
		and tq_v3_amounts(tq_v3_events(after_recast, "HEALTH_DAMAGED", t.idx, outside.idx, "torquemada_1"),
			35.0 * 100.0 / (100.0 + sim.stat(outside, &"magicResistance"))), "v3 S1 damage stops at the old fire and continues at the new fire")
	metrics["torquemada_v3_fire"] = {"heal": float(heals[0].amount) if not heals.is_empty() else 0.0,
		"first_ticks": hits.size(), "tick_damage": tick_damage, "old_layers": old_ids.size(), "new_layers": new_filters}
	sim.dispose()

	var sim2: BattleSim = fresh(["torquemada", "swordsman"], ["archer", "mage"])
	var t2: BUnit = sim2.heroes[0]
	var ally2: BUnit = sim2.heroes[1]
	var enemy2: BUnit = sim2.heroes[2]
	var outside2: BUnit = sim2.heroes[3]
	place(t2, Vector2(500, 400))
	place(ally2, Vector2(560, 430))
	place(enemy2, Vector2(600, 360))
	place(outside2, Vector2(850, 600))
	sim2.apply_status(enemy2, ally2, {"status": "root", "duration": 4.0})
	var enemy_hp0: float = enemy2.hp
	var edict: Array = cast(sim2, t2, 3, t2, t2.pos, {}, 0.05)
	var shields: Array = tq_v3_events(edict, "SHIELD_APPLIED", t2.idx, ally2.idx, "torquemada_3")
	var self_shields: Array = tq_v3_events(edict, "SHIELD_APPLIED", t2.idx, t2.idx, "torquemada_3")
	var enemy_hits: Array = tq_v3_events(edict, "HEALTH_DAMAGED", t2.idx, enemy2.idx, "torquemada_3")
	var physical_damage: float = 109.6 * 100.0 / (100.0 + sim2.stat(enemy2, &"armor"))
	check(bool(edict[0]) and not sim2.has_status(ally2, &"root")
		and tq_v3_events(edict, "CLEANSED", t2.idx, ally2.idx, "torquemada_3").size() == 1, "v3 S3 retains its ally cleanse")
	check(shields.size() == 1 and self_shields.size() == 1 and tq_v3_amounts(shields, 135.0)
		and tq_v3_amounts(self_shields, 135.0) and near(sim2.shield_amount(ally2), 135.0)
		and near(sim2.shield_amount(t2), 135.0), "v3 S3 grants a real 135 shield once to both its ally and self")
	check(enemy_hits.size() == 1 and tq_v3_amounts(enemy_hits, physical_damage) and near(enemy_hp0 - enemy2.hp, physical_damage),
		"v3 S3 deals one positive, armor-adjusted 109.6 physical hit to its enemy")
	check(tq_v3_events(edict, "HEALTH_DAMAGED", t2.idx, ally2.idx, "torquemada_3").is_empty()
		and tq_v3_events(edict, "HEALTH_DAMAGED", t2.idx, t2.idx, "torquemada_3").is_empty()
		and tq_v3_events(edict, "SHIELD_APPLIED", t2.idx, enemy2.idx, "torquemada_3").is_empty()
		and tq_v3_events(edict, "CLEANSED", t2.idx, enemy2.idx, "torquemada_3").is_empty(), "v3 S3 keeps friendly protection and enemy damage separate")
	check(tq_v3_events(edict, "HEALTH_DAMAGED", t2.idx, outside2.idx, "torquemada_3").is_empty()
		and tq_v3_events(edict, "SHIELD_APPLIED", t2.idx, outside2.idx, "torquemada_3").is_empty(), "v3 S3 leaves an outside enemy unaffected")
	var expires: float = float(shields[0].t) + 3.0 if not shields.is_empty() else sim2.time + 3.0
	advance(sim2, maxf(0.0, expires - sim2.time - 0.06))
	check(near(sim2.shield_amount(ally2), 135.0) and near(sim2.shield_amount(t2), 135.0), "v3 S3 shields remain immediately before their three-second expiry")
	advance(sim2, 0.12)
	check(near(sim2.shield_amount(ally2), 0.0) and near(sim2.shield_amount(t2), 0.0), "v3 S3 shields expire after three seconds without incoming damage")
	metrics["torquemada_v3_edict"] = {"shield": float(shields[0].amount) if not shields.is_empty() else 0.0,
		"physical_damage": physical_damage, "enemy_hits": enemy_hits.size(), "expires": expires}
	sim2.dispose()


# ------------------------------------------------------------------ achilles

func achilles_passive() -> void:
	var sim: BattleSim = fresh(["achilles"], ["archer"])
	var c: BUnit = sim.heroes[0]
	var a: BUnit = sim.heroes[1]
	advance(sim, 0.1)
	var hp0: float = c.hp
	sim.apply_damage(a, c, {"type": "damage", "school": "physical", "base": 100.0, "frozen": true}, {"basic": true, "source_type": "BASIC_ATTACK"})
	var basic: float = hp0 - c.hp
	hp0 = c.hp
	sim.apply_damage(a, c, {"type": "damage", "school": "physical", "base": 100.0, "frozen": true}, {"source_type": "ABILITY"})
	var ability: float = hp0 - c.hp
	metrics["achilles_basic_vs_ability_100"] = [basic, ability]
	check(near(basic, 100.0 * 100.0 / (100.0 + 48.0 * 1.3), 1e-4), "basic attacks see armor x1.3 (%.3f)" % basic)
	check(near(ability, 100.0 * 100.0 / 148.0, 1e-4), "ability damage sees the normal armor (%.3f)" % ability)
	sim.dispose()


func spear() -> void:
	var sim: BattleSim = fresh(["achilles"], ["archer", "mage", "sniper"])
	var c: BUnit = sim.heroes[0]
	place(c, Vector2(400, 400))
	place(sim.heroes[1], Vector2(500, 400))
	place(sim.heroes[2], Vector2(570, 405))
	place(sim.heroes[3], Vector2(720, 400))
	advance(sim, 0.1)
	var ev: Array = cast(sim, c, 1, sim.heroes[1], sim.heroes[1].pos, {}, 0.5)
	var expect: float = 75.0 + 0.35 * 70.0
	var h1: Array = damage_events(ev, sim.heroes[1].idx, "achilles_1")
	var h2: Array = damage_events(ev, sim.heroes[2].idx, "achilles_1")
	metrics["spear_true_damage"] = h1[0] if not h1.is_empty() else 0.0
	check(h1.size() == 1 and h2.size() == 1, "the spear pierces through both enemies on the line")
	check(not h1.is_empty() and near(float(h1[0]), expect, 1e-3) and not h2.is_empty() and near(float(h2[0]), expect, 1e-3), "spear deals 75+0.35AD true damage (%.2f)" % expect)
	check(damage_events(ev, sim.heroes[3].idx, "achilles_1").is_empty(), "the spear stops after 220")
	sim.dispose()


func front_guard() -> void:
	var sim: BattleSim = fresh(["achilles"], ["archer", "mage"])
	var c: BUnit = sim.heroes[0]
	var fr: BUnit = sim.heroes[1]
	var bk: BUnit = sim.heroes[2]
	place(c, Vector2(500, 400))
	place(fr, Vector2(800, 400))
	place(bk, Vector2(200, 400))
	advance(sim, 0.1)
	c.facing = Vector2.UP
	var r: Array = cast(sim, c, 2, c, c.pos + Vector2(100, 0))
	var g: ST.Status = sim.get_status(c, &"frontGuard")
	check(bool(r[0]) and g != null and near(g.end - g.start, 2.0, 1e-6) and (g.extra.dir as Vector2).distance_to(Vector2.RIGHT) < 1e-4, "front guard faces the aim for 2 s")
	check(near(sim.stat(c, &"moveSpeed"), 82.0 * 0.65, 1e-4), "move speed -35% while guarding")
	var pa: Defs.AbilityDef = Defs.AbilityDef.new()
	pa.speed = 900.0
	pa.range = 500.0
	pa.width = 8.0
	pa.id = "test_shot"
	var hp0: float = c.hp
	var ev: Array = []
	sim.proj.spawn(fr, c, c.pos, pa, [{"type": "damage", "school": "true", "base": 50.0}], {"source_type": "ABILITY", "team": sim.eteam(fr)})
	ev.append_array(advance(sim, 0.4))
	var blocked: bool = false
	for e in ev:
		if str(e.type) == "PROJECTILE_BLOCKED" and str(e.get("reason", "")) == "front_guard":
			blocked = true
	check(blocked and near(c.hp, hp0), "a frontal projectile is consumed (PROJECTILE_BLOCKED front_guard)")
	sim.proj.spawn(bk, c, c.pos, pa, [{"type": "damage", "school": "true", "base": 50.0}], {"source_type": "ABILITY", "team": sim.eteam(bk)})
	advance(sim, 0.4)
	check(c.hp < hp0, "a projectile from behind hits")
	hp0 = c.hp
	var d1: float = sim.apply_damage(fr, c, {"type": "damage", "school": "true", "base": 50.0, "frozen": true}, {"source_type": "ABILITY"})
	check(near(d1, 0.0) and near(c.hp, hp0) and count_events(sim.tick_events, "FRONT_BLOCKED", fr.idx, c.idx) > 0, "frontal direct damage is blocked (FRONT_BLOCKED)")
	var d2: float = sim.apply_damage(bk, c, {"type": "damage", "school": "true", "base": 50.0, "frozen": true}, {"source_type": "ABILITY"})
	check(near(d2, 50.0), "direct damage from behind lands")
	check(not sim.apply_status(fr, c, {"status": "stun", "duration": 1.0}), "frontal crowd control is blocked")
	check(not sim.kits.displace(fr, c, {"mode": "knockback", "distance": 80.0}, {}) and c.motion == null, "frontal knockback is blocked")
	# Area centre decides for area hits.
	hp0 = c.hp
	sim.resolve_area(bk, c.pos + Vector2(40, 0), 50.0, [{"type": "damage", "school": "true", "base": 30.0, "frozen": true}], {"source_type": "ABILITY", "team": sim.eteam(bk)})
	check(near(c.hp, hp0), "an area hit centred in front is blocked even from a rear caster")
	# Zone ticks and DoT pass from the front.
	hp0 = c.hp
	sim.zones.spawn(fr, c.pos + Vector2(30, 0), 60.0, 0.2, 1.0, [{"type": "damage", "school": "true", "base": 20.0, "frozen": true}], "enemy", {"team": sim.eteam(fr)}, "zone")
	sim.apply_dot(fr, c, {"interval": 0.25, "duration": 0.6, "damageEffect": {"type": "damage", "school": "true", "base": 5.0, "frozen": true}})
	advance(sim, 0.6)
	check(c.hp <= hp0 - 20.0 - 10.0 + 1e-3, "zone ticks and DoT are not blocked (%.1f)" % (hp0 - c.hp))
	# Facing is locked on the guard direction while moving backwards.
	c.vel = Vector2(-80, 0)
	sim._locomotion(c, BattleSim.DT)
	check(c.facing.distance_to(Vector2.RIGHT) < 1e-4, "facing locked while guarding")
	advance(sim, 1.2)
	check(sim.get_status(c, &"frontGuard") == null, "guard ends after 2 s")
	hp0 = c.hp
	sim.apply_damage(fr, c, {"type": "damage", "school": "true", "base": 50.0, "frozen": true}, {"source_type": "ABILITY"})
	check(near(hp0 - c.hp, 50.0), "frontal damage lands after the guard")
	c.vel = Vector2(-80, 0)
	sim._locomotion(c, BattleSim.DT)
	check(c.facing.x < 0.999, "facing follows movement again without the guard")
	sim.dispose()


func roar() -> void:
	var sim: BattleSim = fresh(["achilles"], ["archer", "mage", "sniper"])
	var c: BUnit = sim.heroes[0]
	var a: BUnit = sim.heroes[1]
	var m: BUnit = sim.heroes[2]
	var s: BUnit = sim.heroes[3]
	place(c, Vector2(200, 400))
	place(a, Vector2(1300, 150))
	place(m, Vector2(1300, 650))
	place(s, Vector2(1250, 400))
	advance(sim, 0.1)
	check(not sim.is_seen(0, a) and not sim.is_seen(0, m), "roar targets are out of sight")
	var r: Array = cast(sim, c, 3, c, c.pos)
	var all: bool = bool(r[0])
	for e in [a, m, s]:
		var st: ST.Status = sim.get_status(e, &"roar")
		all = all and st != null and near(st.end - st.start, 6.0, 1e-6)
	check(all, "roar reaches every enemy hero in elimination for 6 s")
	metrics["roar_tenacity"] = sim.stat(a, &"tenacity")
	check(near(sim.stat(a, &"tenacity"), -0.05, 1e-6), "roar pushes tenacity below zero (0.05 - 0.10)")
	sim.apply_status(c, a, {"status": "stun", "duration": 1.0})
	var stun: ST.Status = sim.get_status(a, &"stun")
	metrics["roar_stun_1s"] = stun.duration if stun else 0.0
	check(stun != null and near(stun.duration, 1.05, 1e-6), "negative tenacity extends crowd control (1.05 s)")
	sim.apply_status(c, m, {"status": "roar", "duration": 6.0, "tenacityLoss": 0.6})
	check(near(sim.stat(m, &"tenacity"), -0.3, 1e-6), "roar tenacity floor -0.3")
	sim.apply_mark(c, s, {"status": "confusion", "stacks": 5, "duration": 7.0, "maxStacks": 5, "damageAmp": 0.03, "tenacityLoss": 0.025})
	check(near(sim.stat(s, &"tenacity"), -0.1, 1e-6), "confusion keeps its 0 floor, roar applies below it")
	sim.dispose()
	var s2: BattleSim = fresh(["achilles"], ["archer"])
	var c2: BUnit = s2.heroes[0]
	var a2: BUnit = s2.heroes[1]
	s2.apply_mark(c2, a2, {"status": "confusion", "stacks": 5, "duration": 7.0, "maxStacks": 5, "damageAmp": 0.03, "tenacityLoss": 0.025})
	check(near(s2.stat(a2, &"tenacity"), 0.0, 1e-6), "joker confusion floor unchanged without roar")
	s2.push_status(a2, &"invulnerable", a2.idx, 3.0)
	cast(s2, c2, 3, c2, c2.pos)
	check(s2.get_status(a2, &"roar") == null, "invulnerable enemies ignore roar")
	s2.dispose()
	# Deathmatch: radius 900.
	var dm: BattleSim = BattleSim.new({"ruleset": "deathmatch", "arena_id": "dm_forest_village", "seed": 77, "players": ["achilles", "archer", "mage"], "kill_target": 99, "max_time": 60.0})
	dm.start()
	var dc: BUnit = dm.heroes[0]
	place(dc, dm.arena.center())
	place(dm.heroes[1], dc.pos + Vector2(850, 0))
	place(dm.heroes[2], dc.pos + Vector2(0, 950))
	for u in dm.heroes:
		dm.remove_statuses_where(u, func(x): return true)
	cast(dm, dc, 3, dc, dc.pos)
	check(dm.get_status(dm.heroes[1], &"roar") != null and dm.get_status(dm.heroes[2], &"roar") == null, "deathmatch roar reaches 900, not beyond")
	dm.dispose()


func chariot() -> void:
	var sim: BattleSim = fresh(["achilles"], ["archer", "mage", "sniper", "giant"])
	var c: BUnit = sim.heroes[0]
	place(c, Vector2(300, 400))
	c.facing = Vector2.RIGHT
	place(sim.heroes[1], Vector2(520, 330))
	place(sim.heroes[2], Vector2(560, 470))
	place(sim.heroes[3], Vector2(640, 400))
	var hidden: BUnit = sim.heroes[4]
	place(hidden, Vector2(1350, 750))
	advance(sim, 0.1)
	check(not sim.is_seen(0, hidden), "one enemy is not seen by achilles' team")
	var r: Array = cast(sim, c, 4, c, c.pos, {}, 0.0)
	var ch: BUnit = one(sim, c, "chariot")
	check(bool(r[0]) and ch != null, "S4 summons the chariot")
	if ch == null:
		sim.dispose()
		return
	check(near(ch.base_radius, 30.0) and near(ch.move_speed_ent, 300.0) and near(ch.end_time - ch.spawn_time, 5.0, 1e-6), "chariot radius 30, speed 300, 5 s")
	check(sim.has_status(ch, &"invulnerable") and sim.has_status(ch, &"untargetable"), "chariot is invulnerable and untargetable")
	var hp0: float = ch.hp
	sim.apply_damage(sim.heroes[1], ch, {"type": "damage", "school": "true", "base": 500.0, "frozen": true}, {})
	check(ch.alive and near(ch.hp, hp0), "the chariot cannot be damaged")
	check(not sim.opponents(sim.heroes[1]).has(ch), "opponents() skips the untargetable chariot (E21)")
	var ev: Array = advance(sim, 5.2)
	var knocks: Dictionary = {}
	for e in ev:
		if str(e.type) == "CHARIOT_KNOCK":
			knocks[int(e.g)] = int(knocks.get(int(e.g), 0)) + 1
	metrics["chariot_knocks"] = knocks
	var max_ok: bool = true
	for k in knocks:
		max_ok = max_ok and int(knocks[k]) <= 2
	check(max_ok and not knocks.is_empty(), "each enemy is knocked back at most twice %s" % str(knocks))
	check(not knocks.has(hidden.idx), "the chariot never hunts an enemy its team does not see")
	var hits: Array = damage_events(ev, sim.heroes[1].idx, "", "SUMMON")
	if not hits.is_empty():
		metrics["chariot_hit"] = hits[0]
	var expect: float = (30.0 + 0.3 * 70.0) * sim.resist_mult(sim.stat(sim.heroes[1], &"armor"))
	check(not hits.is_empty() and near(float(hits[0]), expect, 0.01), "chariot contact deals 30+0.3AD physical (%.2f)" % expect)
	check(not ch.alive or ch.end_time <= sim.time, "the chariot expires after 5 s")
	sim.dispose()


# ------------------------------------------------------------------ hermes / modes / determinism

func hermes() -> void:
	var w: Defs.CharDef = DB.char_def("war_machine")
	var sim: BattleSim = fresh(["hermes", "war_machine"], ["archer"])
	check(sim.kits.uses_resource(w.abilities[0]) and sim.kits.uses_resource(w.abilities[1]) and sim.kits.uses_resource(w.abilities[3]) and not sim.kits.uses_resource(w.abilities[2]), "booster, missiles and genocide use fuel")
	var h: BUnit = sim.heroes[0]
	advance(sim, 0.1)
	h.ks.borrow_next = sim.time
	step(sim)
	check((h.ks.borrowed as Dictionary).is_empty(), "hermes cannot borrow the war machine booster")
	sim.dispose()
	var s2: BattleSim = fresh(["hermes", "war_machine", "swordsman"], ["archer"])
	var h2: BUnit = s2.heroes[0]
	advance(s2, 0.1)
	var picks: Dictionary = {}
	for i in 10:
		h2.ks.borrowed = {}
		h2.ks.borrow_next = s2.time
		step(s2)
		var b: Dictionary = h2.ks.borrowed
		if not b.is_empty():
			picks[(b.ability as Defs.AbilityDef).id] = true
	check(picks.keys() == ["swordsman_1"], "hermes only borrows resource-free mobility %s" % str(picks.keys()))
	s2.dispose()


func respawn_modes() -> void:
	var sim: BattleSim = BattleSim.new({"ruleset": "control", "arena_id": "control_crossroads", "seed": 31, "blue": ["hades", "war_machine"], "red": ["archer"], "max_time": 120.0})
	sim.start()
	advance(sim, 0.2)
	var h: BUnit = sim.heroes[0]
	var w: BUnit = sim.heroes[1]
	var pet: BUnit = one(sim, h, "cerberus")
	var tk: BUnit = one(sim, w, "fuel_tank")
	check(pet != null and tk != null, "control mode: pet and tank spawn")
	sim.kill_unit(h, sim.heroes[2], {})
	sim.kill_unit(w, sim.heroes[2], {})
	check(pet != null and not pet.alive and tk != null and not tk.alive, "owner death removes the pet and the tank")
	sim.domination._respawn(h)
	sim.domination._respawn(w)
	step(sim)
	var pet2: BUnit = one(sim, h, "cerberus")
	var tk2: BUnit = one(sim, w, "fuel_tank")
	check(pet2 != null and pet2 != pet and tk2 != null and tk2 != tk, "respawned owners get a new pet and tank lazily")
	sim.dispose()


func _signature(cfg: Dictionary, ticks: int) -> String:
	var sim: BattleSim = BattleSim.new(cfg)
	for team in sim.team_count:
		sim.controllers[team] = AIFactory.make("tactician", sim, team)
	sim.start()
	var ctx: HashingContext = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var kinds: Dictionary = {}
	for i in ticks:
		if sim.state != BattleSim.RUNNING:
			break
		sim.step()
		var line: String = ""
		for ev: Dictionary in sim.tick_events:
			line += "%s|%d|%d|%s;" % [str(ev.type), int(ev.get("s", -1)), int(ev.get("g", -1)), str(ev.get("amount", ""))]
		for u in sim.units:
			line += "%s:%s:%s:%s," % [u.id, var_to_str(u.pos), var_to_str(u.hp), str(u.alive)]
			if not u.is_hero and u.alive:
				kinds[u.kind] = true
		ctx.update(line.to_utf8_buffer())
	var out: String = "%s|%.2f|%d|%s" % [ctx.finish().hex_encode().substr(0, 16), sim.time, sim.winner, ",".join(PackedStringArray(kinds.keys()))]
	sim.dispose()
	return out


func determinism() -> void:
	var cfgs: Array = [
		{"arena_id": "moon_garden", "seed": 2611, "blue": ["hades", "war_machine", "torquemada", "achilles"], "red": ["swordsman", "archer", "mage", "giant"], "max_time": 150.0},
		{"ruleset": "deathmatch", "arena_id": "dm_forest_village", "seed": 2612, "players": ["hades", "war_machine", "torquemada", "achilles", "hermes", "nitro"], "kill_target": 99, "max_time": 90.0},
	]
	for cfg in cfgs:
		var a: String = _signature(cfg, 1500)
		var b: String = _signature(cfg, 1500)
		metrics["signature_" + str(cfg.arena_id)] = a
		check(a == b, "same config and seed reproduce the battle exactly (%s)" % str(cfg.arena_id))
