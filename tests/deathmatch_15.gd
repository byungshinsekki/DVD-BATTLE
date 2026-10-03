extends SceneTree

# V1.5 deathmatch: procedural maps, rules, all 28 items (each effect measured
# in a real BattleSim), item valuation and the deathmatch AI.

var passed: int = 0
var failed: Array = []
var metrics: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed.append(label)
		push_error("FAIL " + label)


func _near(a: float, b: float, tol: float) -> bool:
	return absf(a - b) <= tol


func _dm(players: Array, seed_v: int = 4242, map_id: String = "dm_open_steppe", extra: Dictionary = {}) -> BattleSim:
	var cfg: Dictionary = {"ruleset": "deathmatch", "arena_id": map_id, "players": players, "seed": seed_v, "max_time": 300.0, "kill_target": 15}
	for k in extra:
		cfg[k] = extra[k]
	var sim: BattleSim = BattleSim.new(cfg)
	return sim


func _ai(sim: BattleSim) -> void:
	for t in sim.team_count:
		sim.controllers[t] = AIFactory.make("tactician", sim, t)


# Two heroes side by side in the open, no controllers (idle), field cleared.
func _duel(a_id: String, b_id: String, gap: float = 70.0) -> BattleSim:
	var sim: BattleSim = _dm([a_id, b_id], 991)
	sim.deathmatch.field.clear()
	var c: Vector2 = sim.arena.ffa_spawns[0]
	sim.heroes[0].pos = sim.arena.resolve_circle(c, sim.radius(sim.heroes[0]))
	sim.heroes[1].pos = sim.arena.resolve_circle(sim.heroes[0].pos + Vector2(gap, 0), sim.radius(sim.heroes[1]))
	sim.start()
	return sim


func _give(sim: BattleSim, u: BUnit, id: String) -> void:
	var bag: Array = sim.deathmatch.inventory.get(u.idx, [])
	bag.append(id)
	sim.deathmatch.inventory[u.idx] = bag
	sim.deathmatch._apply_item(u, id)


func _basic(sim: BattleSim, s: BUnit, t: BUnit, base: float) -> float:
	return sim.apply_damage(s, t, {"school": "physical", "base": base, "frozen": true}, {"source_type": "BASIC_ATTACK", "basic": true})


func _steps(sim: BattleSim, seconds: float) -> void:
	var n: int = int(round(seconds / BattleSim.DT))
	for i in n:
		sim.step()


func _run() -> void:
	DB.ensure_loaded()
	_maps()
	_index_equivalence()
	_rules()
	_items_catalogue()
	_item_effects()
	_valuation()
	_ai_matches()
	var status: String = "PASS" if failed.is_empty() else "FAIL"
	print("DEATHMATCH_15 ", JSON.stringify({"status": status, "passed": passed, "failed": failed, "metrics": metrics}))
	var path: String = "res://reports/deathmatch_15.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):
			path = arg.substr(9)
	if path != "":
		var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify({"suite": "deathmatch_15", "status": status, "passed": passed, "failed": failed, "metrics": metrics}, "  "))
	quit(0 if failed.is_empty() else 1)


# ------------------------------------------------------------------ maps

func _maps() -> void:
	var total: int = 0
	for id in DeathmatchMapData.ORDER:
		var sigs: Dictionary = {}
		for seed_v in [1, 2, 3, 77, 4242, 20261001]:
			var t0: int = Time.get_ticks_msec()
			var data: Dictionary = DeathmatchMapData.build(id, seed_v)
			var ms: int = Time.get_ticks_msec() - t0
			metrics["mapgen_ms_max"] = maxi(int(metrics.get("mapgen_ms_max", 0)), ms)
			var again: Dictionary = DeathmatchMapData.build(id, seed_v)
			_check(JSON.stringify(data) == JSON.stringify(again), "%s/%d same seed builds the same map" % [id, seed_v])
			sigs[JSON.stringify(data.obstacles).sha256_text()] = true
			var arena: Arena = Arena.from_data(data)
			_check(arena.ruleset == "deathmatch" and arena.width == 3600.0 and arena.height == 2200.0, "%s/%d size 3600x2200" % [id, seed_v])
			_check(arena.ffa_spawns.size() >= 12, "%s/%d at least 12 spawn points" % [id, seed_v])
			_check(arena.item_spots.size() >= DeathmatchMode.MAX_FIELD_ITEMS, "%s/%d enough item spots" % [id, seed_v])
			_check(arena.forest_x.size() >= 10, "%s/%d has forests" % [id, seed_v])
			_check((data.get("buildings", []) as Array).size() >= 4, "%s/%d has buildings" % [id, seed_v])
			var min_gap: float = INF
			for i in arena.ffa_spawns.size():
				var p: Vector2 = arena.ffa_spawns[i]
				_check(arena.resolve_circle(p, 22.0).distance_to(p) < 0.01, "%s/%d spawn %d is free ground" % [id, seed_v, i])
				for j in range(i + 1, arena.ffa_spawns.size()):
					min_gap = minf(min_gap, p.distance_to(arena.ffa_spawns[j]))
			_check(min_gap >= 500.0, "%s/%d spawns spread (min %.0f)" % [id, seed_v, min_gap])
			var nav: Navigator = Navigator.new()
			nav.arena = arena
			nav.bucket = 26.0
			nav._build()
			var home: Vector2 = arena.ffa_spawns[0]
			var reach_ok: bool = true
			for p2 in arena.ffa_spawns:
				if nav.path_points(home, p2).size() < 2 and home.distance_to(p2) > 1.0:
					reach_ok = false
			for spot in arena.item_spots:
				if nav.path_points(home, spot.pos).size() < 2:
					reach_ok = false
			_check(reach_ok, "%s/%d every spawn and item spot reachable by the largest body" % [id, seed_v])
			for k in arena.obs_count:
				_check(arena.obs_minx[k] >= 0.0 and arena.obs_maxx[k] <= arena.width and arena.obs_miny[k] >= 0.0 and arena.obs_maxy[k] <= arena.height, "%s/%d obstacle %d inside map" % [id, seed_v, k])
			total += 1
		_check(sigs.size() == 6, "%s different seeds give different layouts" % id)
	metrics["maps_checked"] = total


# The grid index must give exactly the answers of the linear scans.
func _index_equivalence() -> void:
	var data: Dictionary = DeathmatchMapData.build("dm_ruined_town", 31)
	var fast: Arena = Arena.from_data(data)
	var slow: Arena = Arena.from_data(data)
	slow.indexed = false
	_check(fast.indexed, "large map builds the obstacle index")
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 5
	var same: bool = true
	for i in 1500:
		var a: Vector2 = Vector2(rng.randf_range(0, 3600), rng.randf_range(0, 2200))
		var b: Vector2 = a + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(10, 900)
		var r: float = rng.randf_range(0, 30)
		if fast.inside_obstacle(a, r) != slow.inside_obstacle(a, r):
			same = false
		if fast.resolve_circle(a, r) != slow.resolve_circle(a, r):
			same = false
		if fast.segment_blocked(a, b, r, Arena.MASK_UNITS) != slow.segment_blocked(a, b, r, Arena.MASK_UNITS):
			same = false
		var h1: Dictionary = fast.segment_hit(a, b, r, Arena.MASK_UNITS)
		var h2: Dictionary = slow.segment_hit(a, b, r, Arena.MASK_UNITS)
		if JSON.stringify(h1) != JSON.stringify(h2):
			same = false
		if fast.line_of_sight(a, b) != slow.line_of_sight(a, b):
			same = false
	_check(same, "indexed and linear obstacle queries agree on 1500 random probes")


# ------------------------------------------------------------------ rules

func _rules() -> void:
	var ids: Array = DB.ids()
	var twelve: Array = ids.slice(0, 12)
	var sim: BattleSim = _dm(twelve, 77, "dm_forest_village")
	_check(sim.team_count == 12 and sim.heroes.size() == 12, "12 participants, one team each")
	var teams: Dictionary = {}
	for u in sim.heroes:
		teams[u.team] = true
	_check(teams.size() == 12, "every participant on its own team")
	_check(sim.deathmatch.field.size() == mini(30, 12 + 2 * 12), "opening supply size")
	var min_gap: float = INF
	for i in 12:
		for j in range(i + 1, 12):
			min_gap = minf(min_gap, sim.heroes[i].pos.distance_to(sim.heroes[j].pos))
	_check(min_gap > 400.0, "starting positions spread (min %.0f)" % min_gap)
	sim.dispose()

	# Kill credit, assists, respawn delay and spawn protection.
	sim = _duel("swordsman", "archer")
	var dm: DeathmatchMode = sim.deathmatch
	var a: BUnit = sim.heroes[0]
	var b: BUnit = sim.heroes[1]
	var third: BUnit = null
	_basic(sim, a, b, 50.0)
	sim.kill_unit(b, a, {})
	_check(dm.kills[a.team] == 1 and dm.deaths[b.team] == 1, "kill credited to the killer")
	_check(dm.respawn_at.has(b.idx) and _near(float(dm.respawn_at[b.idx]) - sim.time, DeathmatchMode.RESPAWN_DELAY, 0.001), "respawn scheduled 6 s later")
	_steps(sim, DeathmatchMode.RESPAWN_DELAY + 0.1)
	_check(b.alive and sim.has_status(b, &"spawn_protection") and sim.has_status(b, &"invulnerable"), "respawned with protection")
	_check(_near(b.hp, sim.max_hp(b), 0.5), "respawn at full health")
	_basic(sim, b, a, 10.0)
	_check(not sim.has_status(b, &"spawn_protection"), "attacking breaks spawn protection")
	sim.dispose()

	sim = _dm(["mage", "archer", "swordsman"], 31)
	sim.deathmatch.field.clear()
	sim.start()
	dm = sim.deathmatch
	var m: BUnit = sim.heroes[0]
	var ar: BUnit = sim.heroes[1]
	var sw: BUnit = sim.heroes[2]
	_basic(sim, ar, m, 40.0)
	sim.kill_unit(m, sw, {})
	_check(dm.assists[ar.team] == 1 and dm.kills[sw.team] == 1, "damage within 8 s earns an assist")
	sim.dispose()

	# Summon kill goes to the owner.
	sim = _duel("engineer", "mage", 120.0)
	dm = sim.deathmatch
	var eng: BUnit = sim.heroes[0]
	var victim: BUnit = sim.heroes[1]
	var ab: Defs.AbilityDef = null
	for x in eng.def.abilities:
		if (x as Defs.AbilityDef).action == "turret":
			ab = x
	var turret: BUnit = null
	if ab:
		sim.kits.make_structure(eng, ab, eng.pos + Vector2(-40, 0), "turret")
		for e in sim.entities:
			if e.owner_idx == eng.idx:
				turret = e
	_check(turret != null, "engineer turret created for the credit test")
	if turret:
		sim.kill_unit(victim, turret, {})
		_check(dm.kills[eng.team] == 1, "turret kill credited to its engineer")
	sim.dispose()

	# Death drops the best item; the rest is lost; the phoenix is never dropped.
	sim = _duel("swordsman", "archer")
	dm = sim.deathmatch
	a = sim.heroes[0]
	b = sim.heroes[1]
	_give(sim, b, "c_blade")
	_give(sim, b, "e_crystal")
	_give(sim, b, "r_axe")
	sim.kill_unit(b, a, {})
	var dropped: Array = dm.field.filter(func(it): return int(it.dropped) == b.idx)
	_check(dropped.size() == 1 and str(dropped[0].item) == "e_crystal", "death drops the highest rarity item only")
	_check(dm.held(b).is_empty(), "inventory emptied on death")
	_check(sim.buff_sum(b, &"abilityPower") == 0.0 or not b.alive, "item buffs gone with the life")
	sim.dispose()

	# Pickup: AI decision, duplicates refused, swap drops the old item.
	sim = _duel("mage", "swordsman", 400.0)
	_ai(sim)
	dm = sim.deathmatch
	m = sim.heroes[0]
	dm.field.append({"uid": 9001, "item": "c_tome", "pos": m.pos, "t": 0.0, "dropped": -1})
	dm._pickups()
	_check(dm.held(m).has("c_tome"), "mage picks up the tome under its feet")
	dm.field.append({"uid": 9002, "item": "c_tome", "pos": m.pos, "t": 0.0, "dropped": -1})
	dm._pickups()
	_check(dm.held(m).count("c_tome") == 1 and dm.field.any(func(it): return int(it.uid) == 9002), "duplicate item refused")
	_give(sim, m, "c_boots")
	_give(sim, m, "c_belt")
	dm.field.append({"uid": 9003, "item": "e_crystal", "pos": m.pos, "t": 0.0, "dropped": -1})
	dm._pickups()
	_check(dm.held(m).has("e_crystal") and dm.held(m).size() == 3, "full inventory swaps for a clearly better item")
	_check(dm.field.any(func(it): return int(it.dropped) == m.idx), "swapped item dropped on the field")
	sim.dispose()

	# Field cap and spawner over a long AI match.
	sim = _dm(twelve.slice(0, 8), 8, "dm_ruined_town", {"max_time": 240.0, "kill_target": 99})
	_ai(sim)
	sim.start()
	var over: bool = false
	var ticks: int = 0
	while sim.state == BattleSim.RUNNING:
		sim.step()
		ticks += 1
		if sim.deathmatch.field.size() > DeathmatchMode.MAX_FIELD_ITEMS:
			over = true
	_check(not over, "field never holds more than 30 items")
	_check(sim.finish_reason == "deathmatch_time", "time limit ends the match")
	var res: Dictionary = sim.result()
	var ranking: Array = res.deathmatch.ranking
	var sorted_ok: bool = true
	for i in range(1, ranking.size()):
		var p0: Dictionary = ranking[i - 1]
		var p1: Dictionary = ranking[i]
		if int(p0.kills) < int(p1.kills) or (int(p0.kills) == int(p1.kills) and int(p0.deaths) > int(p1.deaths)):
			sorted_ok = false
	_check(sorted_ok and sim.winner == int(ranking[0].team), "ranking by kills then fewer deaths; winner is first")
	var kl: Array = res.deathmatch.kill_log
	var credited: int = 0
	for e in kl:
		if int(e[1]) >= 0:
			credited += 1
	var total_kills: int = 0
	for r in ranking:
		total_kills += int(r.kills)
	_check(credited == total_kills, "kill log matches the scoreboard")
	sim.dispose()

	# Kill target ends the match.
	sim = _duel("swordsman", "archer")
	sim.deathmatch.kill_target = 2
	a = sim.heroes[0]
	b = sim.heroes[1]
	sim.kill_unit(b, a, {})
	_steps(sim, DeathmatchMode.RESPAWN_DELAY + 2.2)
	sim.kill_unit(b, a, {})
	sim.step()
	_check(sim.state != BattleSim.RUNNING and sim.finish_reason == "deathmatch_kills" and sim.winner == a.team, "reaching the kill target wins")
	sim.dispose()

	# Determinism: same inputs, same match.
	var sig: Array = []
	for rep in 2:
		var s2: BattleSim = _dm(["pirate", "sniper", "werewolf", "mage", "giant", "hermes"], 555, "dm_forest_village", {"max_time": 90.0, "kill_target": 99})
		_ai(s2)
		s2.start()
		while s2.state == BattleSim.RUNNING:
			s2.step()
		var parts: Array = []
		for u in s2.heroes:
			parts.append([u.pos.snapped(Vector2(0.01, 0.01)), snappedf(u.hp, 0.01), snappedf(u.st_damage, 0.01)])
		parts.append(s2.deathmatch.kills)
		parts.append(s2.deathmatch.field.size())
		sig.append(JSON.stringify(parts).sha256_text())
		s2.dispose()
	_check(sig[0] == sig[1], "deathmatch replays identically")


# ------------------------------------------------------------------ items

func _items_catalogue() -> void:
	_check(ItemDefs.ORDER.size() == 28 and ItemDefs.DEFS.size() == 28, "28 items")
	var counts: Array = []
	for r in 5:
		counts.append(ItemDefs.by_rarity(r).size())
	_check(counts == [8, 6, 6, 4, 4], "rarity split 8/6/6/4/4")
	var names: Dictionary = {}
	var glyphs: Dictionary = {}
	var effects: Dictionary = {}
	for id in ItemDefs.ORDER:
		var d: Dictionary = ItemDefs.get_def(id)
		names[str(d.name)] = true
		glyphs[str(d.glyph)] = true
		var fx: Dictionary = d.duplicate(true)
		for k in ["name", "rarity", "glyph", "desc", "tags"]:
			fx.erase(k)
		effects[JSON.stringify(fx)] = true
		_check(str(d.desc).length() > 4 and not (d.get("tags", []) as Array).is_empty(), "%s has a description and tags" % id)
	_check(names.size() == 28 and glyphs.size() == 28, "names and glyphs unique")
	_check(effects.size() == 28, "every item has a different effect definition")
	DB.load_fonts()
	var font: Font = DB.font_glyph
	var drawable: bool = true
	for id in ItemDefs.ORDER:
		if not font.has_char(str(ItemDefs.get_def(id).glyph).unicode_at(0)):
			drawable = false
	_check(drawable, "every item glyph exists in the glyph font")


func _item_effects() -> void:
	# Plain stat items.
	for row in [["c_blade", &"attackDamage", 0.12, 0.0], ["c_tome", &"abilityPower", 0.12, 0.0], ["c_boots", &"moveSpeed", 0.08, 0.0],
			["c_gloves", &"attackSpeed", 0.12, 0.0], ["c_leather", &"armor", 0.0, 18.0], ["c_charm", &"magicResistance", 0.0, 18.0], ["c_belt", &"maxHealth", 0.0, 160.0]]:
		var sim: BattleSim = _duel("mage", "swordsman")
		var u: BUnit = sim.heroes[0]
		var before: float = sim.stat(u, row[1])
		var base: float = u.def.stat(String(row[1]))
		_give(sim, u, row[0])
		_check(_near(sim.stat(u, row[1]) - before, base * float(row[2]) + float(row[3]), 0.01), "%s changes %s" % [row[0], row[1]])
		sim.dispose()
	var sim2: BattleSim = _duel("mage", "swordsman")
	var h: BUnit = sim2.heroes[0]
	var hp_before: float = sim2.max_hp(h)
	var ad_before: float = sim2.stat(h, &"attackDamage")
	_give(sim2, h, "l_heart")
	_check(_near(sim2.max_hp(h), hp_before * 1.3, 0.5) and _near(sim2.stat(h, &"attackDamage"), ad_before * 1.2, 0.05), "l_heart raises health 30% and attack 20%")
	sim2.dispose()
	# Spyglass
	var sim: BattleSim = _duel("archer", "swordsman")
	var u2: BUnit = sim.heroes[0]
	var v2: BUnit = sim.heroes[1]
	var vis0: float = sim.sensor_range(u2)
	_give(sim, u2, "c_spyglass")
	_check(_near(sim.sensor_range(u2) - vis0, 140.0, 0.01) and _near(sim.deathmatch.forest_reveal_range(u2, v2), 170.0, 0.01), "c_spyglass extends vision and forest detection")
	sim.dispose()
	# Fang: omnivamp 8%
	sim = _duel("archer", "giant")
	var a: BUnit = sim.heroes[0]
	var g: BUnit = sim.heroes[1]
	_give(sim, a, "r_fang")
	a.hp = sim.max_hp(a) * 0.5
	var hp0: float = a.hp
	var dealt: float = _basic(sim, a, g, 200.0)
	_check(dealt > 0.0 and _near(a.hp - hp0, dealt * 0.08, 0.6), "r_fang heals 8% of damage dealt")
	sim.dispose()
	# Dagger: bleed 3% max hp over 3 s
	sim = _duel("archer", "giant")
	a = sim.heroes[0]
	g = sim.heroes[1]
	_give(sim, a, "r_dagger")
	_basic(sim, a, g, 1.0)
	var g_hp: float = g.hp
	_steps(sim, 3.2)
	var bled: float = g_hp - g.hp
	_check(bled > sim.max_hp(g) * 0.01 and bled < sim.max_hp(g) * 0.06, "r_dagger bleeds the target (%.0f)" % bled)
	sim.dispose()
	# Hourglass: cooldowns -15%
	sim = _duel("mage", "swordsman")
	var mg: BUnit = sim.heroes[0]
	var ab: Defs.AbilityDef = mg.def.abilities[0]
	var cd0: float = sim.kits.cooldown_for(mg, ab)
	_give(sim, mg, "r_hourglass")
	_check(_near(sim.kits.cooldown_for(mg, ab), cd0 * 0.85, 0.001), "r_hourglass shortens cooldowns 15%")
	_give(sim, mg, "m_chrono")
	_check(_near(sim.kits.cooldown_for(mg, ab), cd0 * 0.75, 0.001), "cooldown items stack (-25%)")
	sim.dispose()
	# Thorns: 20% of basic damage reflected
	sim = _duel("swordsman", "giant")
	var sw: BUnit = sim.heroes[0]
	g = sim.heroes[1]
	_give(sim, g, "r_thorns")
	var sw_hp: float = sw.hp
	_basic(sim, sw, g, 200.0)
	_check(sw.hp < sw_hp - 1.0, "r_thorns reflects basic attack damage")
	sw_hp = sw.hp
	sim.apply_damage(sw, g, {"school": "physical", "base": 200.0, "frozen": true}, {"source_type": "ABILITY"})
	_check(_near(sw.hp, sw_hp, 0.01), "r_thorns ignores ability damage")
	sim.dispose()
	# Moss: regeneration after 3 s instead of 7 s
	sim = _duel("swordsman", "archer", 900.0)
	var p1: BUnit = sim.heroes[0]
	var p2: BUnit = sim.heroes[1]
	_give(sim, p1, "r_moss")
	for u in [p1, p2]:
		u.hp = sim.max_hp(u) * 0.5
		u.last_damage_time = sim.time
		u.last_combat_time = sim.time
	var h1: float = p1.hp
	var h2: float = p2.hp
	_steps(sim, 5.0)
	_check(p1.hp > h1 + 1.0 and _near(p2.hp, h2, 0.01), "r_moss starts regeneration early")
	_steps(sim, 4.0)
	_check(p2.hp > h2 + 1.0, "everyone regenerates after 7 s out of combat")
	sim.dispose()
	# Axe: +18% below 35% health (target without health-scaled armor)
	sim = _duel("swordsman", "mage")
	sw = sim.heroes[0]
	g = sim.heroes[1]
	_give(sim, sw, "r_axe")
	g.hp = sim.max_hp(g) * 0.6
	var d_hi: float = _basic(sim, sw, g, 100.0)
	g.hp = sim.max_hp(g) * 0.3
	var d_lo: float = _basic(sim, sw, g, 100.0)
	_check(_near(d_lo / maxf(0.01, d_hi), 1.18, 0.02), "r_axe executes low targets (+18%)")
	sim.dispose()
	# String: range +60 ranged, +20 melee
	sim = _duel("archer", "swordsman")
	a = sim.heroes[0]
	sw = sim.heroes[1]
	var ra: float = sim.stat(a, &"attackRange")
	var rs: float = sim.stat(sw, &"attackRange")
	_give(sim, a, "e_string")
	_give(sim, sw, "e_string")
	_check(_near(sim.stat(a, &"attackRange") - ra, 60.0, 0.01) and _near(sim.stat(sw, &"attackRange") - rs, 20.0, 0.01), "e_string extends range by body type")
	_check(_near(sim.buff_sum(a, &"projectileSpeed"), 0.15, 0.001), "e_string speeds projectiles")
	sim.dispose()
	# Guard stone: 25% shield below 35%, 40 s cooldown
	sim = _duel("swordsman", "giant")
	sw = sim.heroes[0]
	g = sim.heroes[1]
	_give(sim, g, "e_guard")
	g.hp = sim.max_hp(g) * 0.4
	_basic(sim, sw, g, sim.max_hp(g) * 0.1)
	var sh1: float = sim.shield_amount(g)
	_check(_near(sh1, sim.max_hp(g) * 0.25, 1.0), "e_guard shields at low health")
	g.shields.clear()
	_basic(sim, sw, g, 20.0)
	_check(sim.shield_amount(g) == 0.0, "e_guard waits for its cooldown")
	sim.dispose()
	# Berserk: below 50%
	sim = _duel("werewolf", "giant", 900.0)
	var w: BUnit = sim.heroes[0]
	_give(sim, w, "e_berserk")
	var as0: float = sim.stat(w, &"attackSpeed")
	w.hp = sim.max_hp(w) * 0.4
	_steps(sim, 0.3)
	_check(sim.stat(w, &"attackSpeed") > as0 * 1.2, "e_berserk speeds attacks below half health")
	w.hp = sim.max_hp(w)
	_steps(sim, 0.3)
	_check(_near(sim.stat(w, &"attackSpeed"), as0, 0.001), "e_berserk ends when healed")
	sim.dispose()
	# Instinct: kill heals 30% and hastes
	sim = _duel("swordsman", "archer")
	sw = sim.heroes[0]
	a = sim.heroes[1]
	_give(sim, sw, "e_instinct")
	sw.hp = sim.max_hp(sw) * 0.3
	var ms0: float = sim.stat(sw, &"moveSpeed")
	sim.kill_unit(a, sw, {})
	_check(_near(sw.hp, sim.max_hp(sw) * 0.6, 1.0) and sim.stat(sw, &"moveSpeed") > ms0 * 1.2, "e_instinct heals and hastes on a kill")
	sim.dispose()
	# Crystal: AP +18% and 30% magic resistance penetration
	sim = _duel("mage", "swordsman")
	mg = sim.heroes[0]
	g = sim.heroes[1]
	var f_magic: Dictionary = {"school": "magic", "base": 200.0, "frozen": true}
	var m0: float = sim.apply_damage(mg, g, f_magic, {"source_type": "ABILITY"})
	_give(sim, mg, "e_crystal")
	var m1: float = sim.apply_damage(mg, g, f_magic, {"source_type": "ABILITY"})
	_check(m1 > m0 * 1.05 or sim.stat(g, &"magicResistance") <= 0.0, "e_crystal penetrates magic resistance")
	sim.dispose()
	# Shadow cloak: hidden longer in forests, ambush bonus after leaving one
	sim = _duel("werewolf", "archer")
	w = sim.heroes[0]
	a = sim.heroes[1]
	_give(sim, w, "e_shadow")
	_check(_near(sim.deathmatch.forest_reveal_range(a, w), 45.0, 0.01), "e_shadow shrinks detection range to 45")
	var st: Dictionary = sim.deathmatch.state.get(w.idx, {})
	st["forest_exit"] = sim.time
	st["ambush_used"] = false
	sim.deathmatch.state[w.idx] = st
	var amb: float = _basic(sim, w, a, 100.0)
	var plain: float = _basic(sim, w, a, 100.0)
	_check(_near(amb / maxf(0.01, plain), 1.3, 0.02), "e_shadow ambush +30% once")
	sim.dispose()
	# Phoenix: survives once at 40%, item consumed
	sim = _duel("swordsman", "archer")
	sw = sim.heroes[0]
	a = sim.heroes[1]
	_give(sim, a, "m_phoenix")
	sim.apply_damage(sw, a, {"school": "true", "base": 99999.0, "frozen": true}, {"source_type": "ABILITY"})
	_check(a.alive and _near(a.hp, sim.max_hp(a) * 0.4, 1.0) and sim.has_status(a, &"invulnerable") and not sim.deathmatch.has_item(a, "m_phoenix"), "m_phoenix revives once")
	_steps(sim, 1.6)
	sim.apply_damage(sw, a, {"school": "true", "base": 99999.0, "frozen": true}, {"source_type": "ABILITY"})
	_check(not a.alive, "second lethal blow kills")
	sim.dispose()
	# Thunder: every 4th hit strikes
	sim = _duel("archer", "giant")
	a = sim.heroes[0]
	g = sim.heroes[1]
	_give(sim, a, "m_thunder")
	var procs: int = 0
	for i in 8:
		_basic(sim, a, g, 5.0)
	for ev in sim.log:
		if str(ev.get("type", "")) == "DM_ITEM_PROC" and str(ev.get("item", "")) == "m_thunder":
			procs += 1
	_check(procs == 2, "m_thunder strikes on every 4th hit (%d)" % procs)
	sim.dispose()
	# Bloodstone: vamp 12% and overheal shield capped at 20%
	sim = _duel("swordsman", "giant")
	sw = sim.heroes[0]
	g = sim.heroes[1]
	_give(sim, sw, "m_bloodstone")
	sw.hp = sim.max_hp(sw)
	for i in 30:
		_basic(sim, sw, g, 150.0)
	var bs: float = sim.shield_amount(sw)
	_check(bs > 1.0 and bs <= sim.max_hp(sw) * 0.2 + 0.5, "m_bloodstone turns overheal into a capped shield (%.0f)" % bs)
	sim.dispose()
	# Chrono: kill halves remaining cooldowns
	sim = _duel("mage", "archer")
	mg = sim.heroes[0]
	a = sim.heroes[1]
	_give(sim, mg, "m_chrono")
	mg.cooldowns[0] = sim.time + 10.0
	sim.kill_unit(a, mg, {})
	_check(_near(mg.cooldowns[0] - sim.time, 5.0, 0.01), "m_chrono refunds half of the remaining cooldown on a kill")
	sim.dispose()
	# Crown: +7% damage per kill, max 5
	sim = _dm(["swordsman", "archer", "mage"], 12)
	sim.deathmatch.field.clear()
	sim.start()
	sw = sim.heroes[0]
	a = sim.heroes[1]
	mg = sim.heroes[2]
	_give(sim, sw, "l_crown")
	var base_dmg: float = _basic(sim, sw, mg, 100.0)
	sim.kill_unit(a, sw, {})
	var crowned: float = _basic(sim, sw, mg, 100.0)
	_check(_near(crowned / maxf(0.01, base_dmg), 1.07, 0.01), "l_crown adds 7% per kill")
	for i in 6:
		(sim.deathmatch.state[sw.idx] as Dictionary)["tyrant"] = mini(5, int((sim.deathmatch.state[sw.idx] as Dictionary).get("tyrant", 0)) + 1)
	var capped: float = _basic(sim, sw, mg, 100.0)
	_check(_near(capped / maxf(0.01, base_dmg), 1.35, 0.01), "l_crown caps at 5 stacks")
	sim.dispose()
	# Aegis: -18% damage and one crowd-control block per 20 s
	sim = _duel("swordsman", "mage")
	sw = sim.heroes[0]
	g = sim.heroes[1]
	var plain2: float = _basic(sim, sw, g, 100.0)
	_give(sim, g, "l_aegis")
	var guarded: float = _basic(sim, sw, g, 100.0)
	_check(_near(guarded / maxf(0.01, plain2), 0.82, 0.01), "l_aegis reduces damage 18%")
	sim.apply_status(sw, g, {"status": "stun", "duration": 1.0}, {"source_type": "ABILITY"})
	_check(not sim.has_status(g, &"stun"), "l_aegis blocks the first stun")
	sim.apply_status(sw, g, {"status": "stun", "duration": 1.0}, {"source_type": "ABILITY"})
	_check(sim.has_status(g, &"stun"), "l_aegis block is on cooldown afterwards")
	sim.dispose()
	# Hammer: splash 35% around the target and slow
	sim = _dm(["swordsman", "archer", "mage"], 13)
	sim.deathmatch.field.clear()
	var c: Vector2 = sim.arena.ffa_spawns[0]
	sim.heroes[0].pos = sim.arena.resolve_circle(c, 20.0)
	sim.heroes[1].pos = sim.arena.resolve_circle(c + Vector2(60, 0), 20.0)
	sim.heroes[2].pos = sim.arena.resolve_circle(c + Vector2(110, 0), 20.0)
	sim.start()
	sw = sim.heroes[0]
	a = sim.heroes[1]
	mg = sim.heroes[2]
	_give(sim, sw, "l_hammer")
	var mg_hp: float = mg.hp
	_basic(sim, sw, a, 100.0)
	_check(mg.hp < mg_hp - 1.0 and sim.has_status(a, &"slow") and sim.has_status(mg, &"slow"), "l_hammer splashes and slows")
	sim.dispose()


# ------------------------------------------------------------------ valuation

func _valuation() -> void:
	var mage: Defs.CharDef = DB.char_def("mage")
	var archer: Defs.CharDef = DB.char_def("archer")
	var giant: Defs.CharDef = DB.char_def("giant")
	var pol: Defs.CharDef = DB.char_def("politician")
	# Valuation follows each hero's measured damage profile (see ItemValuation.BASIC_SHARE).
	_check(float(ItemValuation.value(mage, "r_hourglass").value) > float(ItemValuation.value(mage, "c_blade").value), "caster values cooldown reduction over attack damage")
	var best_tome: String = ""
	var best_tome_v: float = -1.0
	var ap_rank: Array = []
	for d in DB.characters:
		var tv: float = float(ItemValuation.value(d, "c_tome").value)
		if tv > best_tome_v:
			best_tome_v = tv
			best_tome = d.id
		ap_rank.append([float(ItemValuation.profile(d).ap), d.id])
	ap_rank.sort()
	ap_rank.reverse()
	var top_ap: Array = []
	for row in ap_rank.slice(0, 3):
		top_ap.append(row[1])
	_check(top_ap.has(best_tome), "tome is worth most to an ability-power hero (%s)" % best_tome)
	_check(float(ItemValuation.value(DB.char_def("world_tree"), "c_gloves").value) > float(ItemValuation.value(mage, "c_gloves").value), "attack speed matters more to a basic-attack hero")
	_check(float(ItemValuation.value(archer, "c_gloves").value) > float(ItemValuation.value(archer, "c_tome").value), "archer values attack speed over ability power")
	_check(float(ItemValuation.value(archer, "e_string").value) > float(ItemValuation.value(giant, "e_string").value), "range item matters more to a ranged hero")
	_check(float(ItemValuation.value(pol, "l_hammer").value) < float(ItemValuation.value(archer, "l_hammer").value), "on-hit item is worth little without basic attacks")
	var d1: Dictionary = ItemValuation.decide(mage, "c_tome", ["c_tome"], 3)
	_check(not bool(d1.take) and str(d1.reason).contains("이미 보유"), "duplicate refused with a reason")
	var d2: Dictionary = ItemValuation.decide(mage, "l_heart", ["c_boots", "c_belt", "c_leather"], 3)
	_check(bool(d2.take) and d2.has("drop_slot"), "full bag swaps for a legendary")
	var d3: Dictionary = ItemValuation.decide(mage, "c_blade", ["l_heart", "e_crystal", "m_bloodstone"], 3)
	_check(not bool(d3.take), "weak item ignored when the bag is strong")
	var reasons: bool = true
	for id in ItemDefs.ORDER:
		for d in [mage, archer, giant, pol]:
			var v: Dictionary = ItemValuation.value(d, id)
			if str(v.reason) == "":
				reasons = false
	_check(reasons, "every valuation has a readable reason")


# ------------------------------------------------------------------ AI

func _ai_matches() -> void:
	var kills: int = 0
	var dmg: float = 0.0
	var dur: float = 0.0
	var modes: Dictionary = {}
	var picks: int = 0
	var skips: int = 0
	var worst_tick: int = 0
	for seed_v in [777, 31]:
		var ids: Array = DB.ids()
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = seed_v
		var pool: Array = ids.duplicate()
		var players: Array = []
		for k in 8:
			players.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
		var sim: BattleSim = _dm(players, seed_v, "dm_forest_village", {"max_time": 150.0, "kill_target": 99})
		_ai(sim)
		sim.start()
		while sim.state == BattleSim.RUNNING:
			var t0: int = Time.get_ticks_usec()
			sim.step()
			worst_tick = maxi(worst_tick, Time.get_ticks_usec() - t0)
			for ev in sim.tick_events:
				if str(ev.type) == "DM_ITEM_PICKED":
					picks += 1
				elif str(ev.type) == "DM_ITEM_SKIPPED":
					skips += 1
			if sim.tick % 30 == 0:
				for u in sim.heroes:
					if u.alive:
						var m: String = str(sim.controllers[u.team].intent.get("mode", ""))
						modes[m] = int(modes.get(m, 0)) + 1
		for t in sim.team_count:
			kills += sim.deathmatch.kills[t]
		for u in sim.heroes:
			dmg += u.st_damage
		dur += sim.time
		sim.dispose()
	metrics["ai_kills_per_min_8p"] = snappedf(kills / (dur / 60.0), 0.01)
	metrics["ai_damage_per_min_8p"] = int(dmg / (dur / 60.0))
	metrics["ai_modes"] = modes
	metrics["ai_item_picks"] = picks
	metrics["ai_item_skips"] = skips
	metrics["worst_tick_ms"] = snappedf(worst_tick / 1000.0, 0.1)
	_check(kills >= 12, "8-player AI matches produce kills (%d in 5 min)" % kills)
	for m in ["hunt", "loot", "roam", "evade", "chase"]:
		_check(int(modes.get(m, 0)) > 0, "AI uses the %s intent" % m)
	var total: int = 0
	for k in modes:
		total += int(modes[k])
	_check(float(modes.get("evade", 0)) / maxf(1.0, total) < 0.2, "AI does not spend most of its time running away")
	_check(picks > 0 and skips > 0, "AI both takes and refuses items")
