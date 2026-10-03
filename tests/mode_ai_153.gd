extends SceneTree

# V1.5.3 mode-layer AI regressions (audit_mode_layers DM-1/2/3/6/7, C-1..C-5,
# DR-2, DR-3, W-1 and the conquest respawn facing of DESIGN_153 section 1).
# Rules that carry a developer-lab switch (deathmatch "dm153", conquest
# "cc_<rule>") are run with the switch off (the V1.5.2 behaviour) and on, so
# the old rule fails the check and the new one passes it in the same run.
#
# godot --headless --path . --script res://tests/mode_ai_153.gd [-- --report=res://reports/mode_ai_153.json]

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


func _run() -> void:
	DB.ensure_loaded()
	_dm_shield_hits()
	_dm_escape_rule()
	_dm_pursuit_window()
	_dm_threat()
	_dm_public_noise()
	_dm_life_reset()
	_dm_forest_recover()
	_dm_small_match_spawns()
	_dm_small_match_metrics()
	_ctl_heal_trips()
	_ctl_trip_path()
	_ctl_hold_exempt()
	_ctl_churn()
	_ctl_backcap_and_staging()
	_ctl_respawn_facing()
	_draft_map_features()
	_draft_rollout_gate()
	_wiring()
	var status: String = "PASS" if failed.is_empty() else "FAIL"
	print("MODE_AI_153 ", JSON.stringify({"status": status, "passed": passed, "failed": failed, "metrics": metrics}))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):
			var f: FileAccess = FileAccess.open(arg.substr(9), FileAccess.WRITE)
			if f:
				f.store_string(JSON.stringify({"suite": "mode_ai_153", "status": status, "passed": passed, "failed": failed, "metrics": metrics}, "  "))
	quit(0 if failed.is_empty() else 1)


# ------------------------------------------------------------------ helpers

func _dm_sim(players: Array, seed_v: int = 4242, map_id: String = "dm_open_steppe", extra: Dictionary = {}) -> BattleSim:
	var cfg: Dictionary = {"ruleset": "deathmatch", "arena_id": map_id, "players": players, "seed": seed_v, "max_time": 300.0, "kill_target": 99}
	for k in extra:
		cfg[k] = extra[k]
	return BattleSim.new(cfg)


func _dm_brains(sim: BattleSim, new_rules: bool) -> void:
	for t in sim.team_count:
		sim.controllers[t] = AIFactory.make("tactician{dm153=%d}" % (1 if new_rules else 0), sim, t)


func _place(sim: BattleSim, u: BUnit, p: Vector2) -> void:
	u.pos = sim.arena.resolve_circle(p, sim.radius(u))
	u.prev_pos = u.pos


# Two points on free, open, forest-free ground with a clear line of sight.
func _open_pair(sim: BattleSim, dist: float, around: Array = []) -> Array:
	var anchors: Array = around if not around.is_empty() else sim.arena.ffa_spawns
	for sp in anchors:
		for k in 16:
			var a: Vector2 = sp
			var b: Vector2 = a + Vector2.from_angle(k * TAU / 16.0) * dist
			if sim.arena.resolve_circle(a, 30.0).distance_to(a) > 0.5 or sim.arena.resolve_circle(b, 30.0).distance_to(b) > 0.5:
				continue
			if not sim.arena.line_of_sight(a, b) or sim.arena.forest_at(a) >= 0 or sim.arena.forest_at(b) >= 0 or sim.arena.forest_occludes(a, b):
				continue
			return [a, b]
	return []


func _refresh(sim: BattleSim, b: DeathmatchBrain) -> void:
	sim._update_visibility()
	b.intel.observe()
	b.next_intent_at = 0.0
	b._plan()


# ------------------------------------------------------------------ deathmatch

# DM-1: damage a shield swallows is a landed hit and clears an escape mark.
func _dm_shield_hits() -> void:
	for new_rules in [false, true]:
		var sim: BattleSim = _dm_sim(["swordsman", "archer"])
		sim.deathmatch.field.clear()
		var pair: Array = _open_pair(sim, 90.0)
		_place(sim, sim.heroes[0], pair[0])
		_place(sim, sim.heroes[1], pair[1])
		_dm_brains(sim, new_rules)
		sim.start()
		var b: DeathmatchBrain = sim.controllers[0]
		var t: BUnit = sim.heroes[1]
		b.escaped[t.idx] = sim.time + 12.0
		sim.tick_events = []
		sim.apply_shield(t, t, {"base": 900.0, "duration": 6.0, "frozen": true}, {"source_type": "ITEM", "proc": true})
		sim.apply_damage(sim.heroes[0], t, {"school": "physical", "base": 30.0, "frozen": true}, {"source_type": "BASIC_ATTACK", "basic": true})
		var absorbed: bool = sim.tick_events.any(func(ev): return str(ev.type) == "SHIELD_ABSORBED")
		sim.ai_events = sim.tick_events
		sim.tick_events = []
		b.pre_tick(sim)
		var counted: bool = b.last_hit_on.has(t.idx)
		var cleared: bool = not b.escaped.has(t.idx)
		if new_rules:
			_check(absorbed and counted and cleared, "DM-1 a shield-absorbed hit counts as pursuit progress and clears the escape mark")
		else:
			_check(absorbed and not counted and not cleared, "DM-1 fixture reproduces V1.5.2 ignoring shield-absorbed hits")
		sim.dispose()


# DM-1: a target that stays in sight within reach+150 is not marked escaped
# after a pursuit that landed nothing for longer than the window.
func _dm_escape_rule() -> void:
	for new_rules in [false, true]:
		var sim: BattleSim = _dm_sim(["swordsman", "archer"], 4242, "dm_open_steppe")
		sim.deathmatch.field.clear()
		var pair: Array = _open_pair(sim, 48.0 + 100.0)
		_place(sim, sim.heroes[0], pair[0])
		_place(sim, sim.heroes[1], pair[1])
		_dm_brains(sim, new_rules)
		sim.start()
		var b: DeathmatchBrain = sim.controllers[0]
		var t: BUnit = sim.heroes[1]
		b.intent = {"mode": "hunt", "goal": t.pos, "since": sim.time, "score": 0.0, "reason": "", "target": t.idx, "uid": -1, "p": 0.5}
		b.hunt_track[t.idx] = sim.time - 10.0
		b.last_hit_on.erase(t.idx)
		_refresh(sim, b)
		var seen: bool = b.intel.enemies[t.idx].visible
		var marked: bool = float(b.escaped.get(t.idx, -1.0)) > sim.time
		if new_rules:
			_check(seen and not marked, "DM-1 a visible target within reach+150 is never marked escaped")
		else:
			_check(seen and marked, "DM-1 fixture reproduces the V1.5.2 escape mark on a visible, in-reach target")
		# The same target once it is out of sight is abandoned after the window.
		if new_rules:
			b.intent = {"mode": "chase", "goal": t.pos, "since": sim.time, "score": 0.0, "reason": "", "target": t.idx, "uid": -1, "p": 0.5}
			b.hunt_track[t.idx] = sim.time - 10.0
			b.contact_on[t.idx] = sim.time - 9.0
			_place(sim, t, sim.arena.ffa_spawns[sim.arena.ffa_spawns.size() - 1])
			var far: Vector2 = t.pos
			var ok_far: bool = far.distance_to(sim.heroes[0].pos) > 900.0
			_refresh(sim, b)
			_check(not ok_far or float(b.escaped.get(t.idx, -1.0)) > sim.time, "DM-1 a pursuit out of sight and reach still expires after the window")
		sim.dispose()


# DM-1: the patience window is max(6 s, 2.5 attack intervals).
func _dm_pursuit_window() -> void:
	var sim: BattleSim = _dm_sim(["giant", "archer"])
	_dm_brains(sim, true)
	sim.start()
	var b: DeathmatchBrain = sim.controllers[0]
	var g: BUnit = sim.heroes[0]
	_check(is_equal_approx(b.pursuit_window(), maxf(6.0, 2.5 / maxf(0.2, sim.stat(g, &"attackSpeed")))), "DM-1 pursuit window follows the formula at base attack speed")
	sim.add_buff(g, &"attackSpeed", -0.6, 30.0, g.idx, {"tag": "test_slow"})
	var as_: float = sim.stat(g, &"attackSpeed")
	_check(as_ < 0.4 and b.pursuit_window() > 6.0 and is_equal_approx(b.pursuit_window(), 2.5 / maxf(0.2, as_)), "DM-1 a slowed attacker gets 2.5 attack intervals of patience (%.2f s)" % b.pursuit_window())
	var old_rules: DeathmatchBrain = AIFactory.make("tactician{dm153=0}", sim, 0) as DeathmatchBrain
	_check(old_rules.pursuit_window() == 6.0, "DM-1 fixture: V1.5.2 abandoned after a fixed 6 s")
	sim.dispose()


# DM-2: a hero at 12% health with a pursuer on it does not walk to the
# fountain (or roam, loot, listen); it fights back or runs.
func _dm_threat() -> void:
	var picked: Dictionary = {}
	for new_rules in [false, true]:
		var sim: BattleSim = _dm_sim(["torturer", "archer"], 200, "dm_forest_village")
		sim.deathmatch.field.clear()
		var fountains: Array = sim.env.public_fountains()
		_check(not fountains.is_empty(), "DM-2 fixture map has a public fountain")
		if fountains.is_empty():
			sim.dispose()
			return
		var f: Vector2 = fountains[0].center
		var spot: Array = []
		for k in 16:
			var dir: Vector2 = Vector2.from_angle(k * TAU / 16.0)
			var me: Vector2 = f + dir * 330.0
			var foe: Vector2 = me + dir * 190.0
			if sim.arena.resolve_circle(me, 30.0).distance_to(me) > 0.5 or sim.arena.resolve_circle(foe, 30.0).distance_to(foe) > 0.5:
				continue
			if not sim.arena.line_of_sight(me, foe) or not sim.arena.line_of_sight(me, f) or sim.arena.forest_at(me) >= 0 or sim.arena.forest_at(foe) >= 0:
				continue
			spot = [me, foe]
			break
		_check(not spot.is_empty(), "DM-2 fixture finds open ground beside the fountain")
		if spot.is_empty():
			sim.dispose()
			return
		var hero: BUnit = sim.heroes[0]
		var archer: BUnit = sim.heroes[1]
		_place(sim, hero, spot[0])
		_place(sim, archer, spot[1])
		_dm_brains(sim, new_rules)
		sim.start()
		hero.hp = sim.max_hp(hero) * 0.12
		var b: DeathmatchBrain = sim.controllers[0]
		b.fight_with[archer.idx] = sim.time
		b.last_attacker = archer.idx
		b.last_attacked_at = sim.time
		_refresh(sim, b)
		var mode: String = str(b.intent.get("mode", ""))
		picked[new_rules] = mode
		if new_rules:
			_check(mode in ["hunt", "evade"], "DM-2 a threatened 12%% hero fights or runs instead of walking to the fountain (%s)" % mode)
		else:
			_check(mode == "recover", "DM-2 fixture reproduces the V1.5.2 fountain walk under threat (%s)" % mode)
		sim.dispose()
	metrics["dm2_threatened_choice"] = {"v152": picked.get(false, ""), "v153": picked.get(true, "")}


# DM-3: items vanishing from the public field and a fountain's public ready
# time jumping become noises; with nothing else to do the hero follows one.
func _dm_public_noise() -> void:
	for new_rules in [false, true]:
		var sim: BattleSim = _dm_sim(["swordsman", "archer"], 4242, "dm_open_steppe")
		var pair: Array = _open_pair(sim, 60.0)
		_place(sim, sim.heroes[0], pair[0])
		_place(sim, sim.heroes[1], sim.arena.ffa_spawns[sim.arena.ffa_spawns.size() - 1])
		_dm_brains(sim, new_rules)
		sim.start()
		var b: DeathmatchBrain = sim.controllers[0]
		_refresh(sim, b)
		# Somebody picked up every item on the field.
		var gone: Array = []
		for it in sim.deathmatch.field:
			gone.append(it.pos)
		sim.deathmatch.field.clear()
		# ... and somebody drank from a fountain far from us.
		var drank: Vector2 = Vector2.INF
		for f: Dictionary in sim.env.public_fountains():
			if (f.center as Vector2).distance_to(sim.heroes[0].pos) > 400.0:
				sim.env.cooldowns["fountain:" + str(f.id)] = sim.time + 18.0
				drank = f.center
				break
		sim.time += 0.5
		_refresh(sim, b)
		var item_noise: bool = b.public_noise.any(func(n): return str(n.kind) == "item")
		var fountain_noise: bool = drank == Vector2.INF or b.public_noise.any(func(n): return str(n.kind) == "fountain" and (n.pos as Vector2).distance_to(drank) < 1.0)
		var mode: String = str(b.intent.get("mode", ""))
		var visible_foe: bool = not b.intel.visible_enemies().is_empty()
		if new_rules:
			_check(item_noise and fountain_noise, "DM-3 vanished items and a used fountain register as public noises")
			_check(visible_foe or mode == "listen", "DM-3 with nothing in sight the hero follows the freshest public noise (%s)" % mode)
		else:
			_check(b.public_noise.is_empty() and mode != "listen", "DM-3 fixture: V1.5.2 ignored public signals (%s)" % mode)
		sim.dispose()
	_dm_noise_across_death()


# Review 1.5.3 (deathmatch_brain.gd:191): the public-signal scan stopped while
# the hero was dead, so the first scan of the next life stamped every pickup
# of the death as "0 s ago", and the hero's OWN death drop (far away after the
# respawn) became a fresh "drop" noise pointing back at its killer.
func _dm_noise_across_death() -> void:
	var sim: BattleSim = _dm_sim(["swordsman", "archer", "mage"], 4242, "dm_open_steppe")
	_dm_brains(sim, true)
	for t in range(1, sim.team_count):
		sim.controllers[t] = null
	sim.start()
	var b: DeathmatchBrain = sim.controllers[0]
	var me: BUnit = sim.heroes[0]
	var dm: DeathmatchMode = sim.deathmatch
	_refresh(sim, b)
	var loot: String = ""
	for it in dm.field:
		if str(it.item) != "m_phoenix":
			loot = str(it.item)
			break
	dm.inventory[me.idx] = [loot]
	var death_pos: Vector2 = me.pos
	sim.kill_unit(me, sim.heroes[1], {})
	for i in 60:
		sim.step()
	# Somebody picks up an item far from the corpse while we wait.
	var gone: Vector2 = Vector2.INF
	for k in dm.field.size():
		var p: Vector2 = dm.field[k].pos
		if int(dm.field[k].get("dropped", -1)) < 0 and p.distance_to(death_pos) > 300.0:
			gone = p
			dm.field.remove_at(k)
			break
	var picked_t: float = sim.time
	var guard: int = 0
	while not me.alive and guard < 900:
		sim.step()
		guard += 1
	for i in 60:
		sim.step()
	var own: Array = b.public_noise.filter(func(n): return str(n.kind) == "drop" and (n.pos as Vector2).distance_to(death_pos) < 40.0)
	var item: Array = b.public_noise.filter(func(n): return str(n.kind) == "item" and (n.pos as Vector2).distance_to(gone) < 1.0)
	metrics["dm_noise_across_death"] = {"loot": loot, "respawn_dist": snappedf(me.pos.distance_to(death_pos), 1.0), "own_drop_noises": own.size(),
		"pickup_noise_age": snappedf(float(item[0].t) - picked_t, 0.01) if not item.is_empty() else -1.0}
	_check(loot != "" and me.alive and me.pos.distance_to(death_pos) > 90.0 and own.is_empty(), "DM our own death drop is never a public 'drop' noise (%d)" % own.size())
	_check(gone.is_finite() and not item.is_empty() and float(item[0].t) - picked_t <= INTENT_SCAN + 0.05, "DM a pickup made while we were dead keeps its real time (%s)" % JSON.stringify(metrics["dm_noise_across_death"]))
	sim.dispose()


const INTENT_SCAN: = 0.5


# DM-6: our own respawn clears the previous life's grudges and timers; an
# opponent's death in the kill feed clears marks on it.
func _dm_life_reset() -> void:
	for new_rules in [false, true]:
		var sim: BattleSim = _dm_sim(["swordsman", "archer", "mage"])
		_dm_brains(sim, new_rules)
		sim.start()
		var b: DeathmatchBrain = sim.controllers[0]
		var me: BUnit = sim.heroes[0]
		var foe: BUnit = sim.heroes[1]
		var other: BUnit = sim.heroes[2]
		b.escaped[foe.idx] = sim.time + 12.0
		b.hunt_track[foe.idx] = sim.time
		b.fight_with[foe.idx] = sim.time
		b.last_attacker = foe.idx
		b.last_attacked_at = sim.time
		b.escaped[other.idx] = sim.time + 12.0
		var ev1: Dictionary = sim.emit("DM_KILL", foe.idx, other.idx, {"t": sim.time, "killer": foe.idx, "victim": other.idx})
		sim.ai_events = [ev1]
		b.pre_tick(sim)
		var other_cleared: bool = not b.escaped.has(other.idx)
		var ev2: Dictionary = sim.emit("HERO_RESPAWNED", me.idx, me.idx, {"team": me.team, "life_id": me.life_id, "protected_until": sim.time + 2.0, "pos": me.pos})
		sim.ai_events = [ev2]
		b.pre_tick(sim)
		var reset: bool = b.escaped.is_empty() and b.hunt_track.is_empty() and b.fight_with.is_empty() and b.last_attacker == -1
		if new_rules:
			_check(other_cleared, "DM-6 an opponent's public death clears our escape mark on it")
			_check(reset, "DM-6 our respawn resets escape marks, pursuit timers, fight partners and last attacker")
		else:
			_check(not other_cleared and not reset, "DM-6 fixture: V1.5.2 carried per-life memory across lives")
		sim.dispose()


# DM-7: once hiding in a forest, the hero stays until 80% health instead of
# walking out at half health.
func _dm_forest_recover() -> void:
	for new_rules in [false, true]:
		var sim: BattleSim = _dm_sim(["swordsman", "archer"], 4242, "dm_forest_village")
		sim.deathmatch.field.clear()
		sim.env.enabled = false
		var forest: Vector2 = Vector2(sim.arena.forest_x[0], sim.arena.forest_y[0])
		_place(sim, sim.heroes[0], forest)
		var far: Vector2 = forest
		for sp in sim.arena.ffa_spawns:
			if (sp as Vector2).distance_to(forest) > far.distance_to(forest):
				far = sp
		_place(sim, sim.heroes[1], far)
		_dm_brains(sim, new_rules)
		sim.start()
		var h: BUnit = sim.heroes[0]
		var b: DeathmatchBrain = sim.controllers[0]
		h.hp = sim.max_hp(h) * 0.62
		b.intent = {"mode": "recover", "sub": "hide", "goal": forest, "since": sim.time, "score": 0.0, "reason": "", "target": -1, "uid": -1}
		_refresh(sim, b)
		var mode: String = str(b.intent.get("mode", ""))
		if new_rules:
			_check(mode == "recover", "DM-7 a hiding hero at 62%% keeps recovering (%s)" % mode)
			h.hp = sim.max_hp(h) * 0.86
			b.intent = {"mode": "recover", "sub": "hide", "goal": forest, "since": sim.time, "score": 0.0, "reason": "", "target": -1, "uid": -1}
			_refresh(sim, b)
			_check(str(b.intent.get("mode", "")) != "recover", "DM-7 hiding ends above 80%% health")
		else:
			_check(mode != "recover", "DM-7 fixture: V1.5.2 left the forest at half health (%s)" % mode)
		sim.dispose()


# DM-3: two or three players play on the inner region and respawn about
# 600 px from the nearest opponent; larger matches keep every spawn point.
func _dm_small_match_spawns() -> void:
	var dists: Dictionary = {}
	for new_rules in [false, true]:
		var sim: BattleSim = _dm_sim(["swordsman", "archer"], 777, "dm_ruined_town", {"dm153": new_rules})
		var dm: DeathmatchMode = sim.deathmatch
		var inner: Rect2 = dm.inner_region()
		var a: BUnit = sim.heroes[0]
		var o: BUnit = sim.heroes[1]
		var start_gap: float = a.pos.distance_to(o.pos)
		var ds: Array = []
		for k in 24:
			ds.append(dm.choose_spawn(a).distance_to(o.pos))
		var mean: float = 0.0
		for d in ds:
			mean += float(d)
		mean /= ds.size()
		dists[new_rules] = {"start_gap": snappedf(start_gap, 1.0), "respawn_mean": snappedf(mean, 1.0), "respawn_min": snappedf(float(ds.min()), 1.0)}
		if new_rules:
			var inside: bool = true
			for p in dm.spawn_candidates():
				inside = inside and inner.has_point(p)
			_check(dm.small_match() and inside and dm.spawn_candidates().size() >= 4, "DM-3 a 2-player match uses the inner spawn region")
			_check(float(ds.min()) >= 450.0, "DM-3 small-match respawns stay out of immediate reach (min %.0f)" % float(ds.min()))
		sim.dispose()
	_check(float(dists[true].respawn_mean) < float(dists[false].respawn_mean) - 200.0, "DM-3 small-match respawns land nearer the opponent (%s)" % JSON.stringify(dists))
	_check(float(dists[true].start_gap) < float(dists[false].start_gap), "DM-3 small-match openings start closer (%s)" % JSON.stringify(dists))
	metrics["dm3_spawn_distance"] = {"v152": dists[false], "v153": dists[true]}
	var ids: Array = DB.ids().slice(0, 12)
	var big: BattleSim = _dm_sim(ids, 4242, "dm_open_steppe")
	_check(not big.deathmatch.small_match() and big.deathmatch.spawn_candidates().size() == big.arena.ffa_spawns.size(), "DM-3 12-player matches keep every spawn point")
	big.dispose()
	_dm_small_match_prior()


# Review 1.5.3 (intel.gd:483): the belief prior spread unseen opponents over
# every public spawn point, farthest first, while a 2-3 player match only
# starts and respawns on the inner points, about 600 px from the nearest
# opponent. The prior now follows the same public rule.
func _dm_small_match_prior() -> void:
	var sim: BattleSim = _dm_sim(["archer", "swordsman"], 5153, "dm_open_steppe", {"max_time": 200.0})
	_dm_brains(sim, true)
	sim.start()
	var b: DeathmatchBrain = sim.controllers[0]
	var foe: BUnit = sim.heroes[1]
	var inner: Rect2 = sim.deathmatch.inner_region().grow(60.0)
	var eb: TeamIntel.EnemyBelief = b.intel.enemies[foe.idx]
	var outside: int = 0
	for p in eb.particles:
		if not inner.has_point(p):
			outside += 1
	_check(sim.deathmatch.small_match() and outside == 0, "DM a 2-player opening prior stays on the inner spawn region (%d of %d particles outside)" % [outside, eb.particles.size()])
	var total: int = 0
	var covered: int = 0
	for round_i in 8:
		if not foe.alive or not sim.heroes[0].alive:
			for i in 420:
				sim.step()
		if not foe.alive or not sim.heroes[0].alive:
			continue
		sim.kill_unit(foe, sim.heroes[0], {})
		var guard: int = 0
		while not foe.alive and guard < 600:
			sim.step()
			guard += 1
		sim.step()
		eb = b.intel.enemies[foe.idx]
		if not eb.visible:
			total += 1
			var near: float = INF
			for p in eb.particles:
				near = minf(near, (p as Vector2).distance_to(foe.spawn_pos))
			if near < 150.0:
				covered += 1
		for i in 240:
			sim.step()
	metrics["dm_small_respawn_prior"] = {"unseen_respawns": total, "covered_150": covered}
	_check(total >= 3 and covered == total, "DM small-match respawn prior covers the true respawn point (%d/%d)" % [covered, total])
	sim.dispose()


# DM-3 regression metric: kills and first contact in short 2-player matches,
# V1.5.2 rules (AI and spawn) versus V1.5.3.
func _dm_small_match_metrics() -> void:
	var res: Dictionary = {}
	for new_rules in [false, true]:
		var kills: int = 0
		var contact_sum: float = 0.0
		var matches: int = 0
		for m in 4:
			var rng: RandomNumberGenerator = RandomNumberGenerator.new()
			rng.seed = 400 + m * 17 + 2
			var pool: Array = DB.ids().duplicate()
			var players: Array = []
			for k in 2:
				players.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
			var sim: BattleSim = _dm_sim(players, 400 + m, DeathmatchMapData.ORDER[m % 3], {"max_time": 150.0, "dm153": new_rules})
			_dm_brains(sim, new_rules)
			sim.start()
			var first: float = 150.0
			while sim.state == BattleSim.RUNNING:
				sim.step()
				if first >= 150.0 and sim.tick % 15 == 0:
					for u in sim.heroes:
						var c: DeathmatchBrain = sim.controllers[u.team]
						if u.alive and c.intel.visible_enemies().any(func(e): return (e as TeamIntel.EnemyBelief).is_hero):
							first = minf(first, sim.time)
			for t in sim.team_count:
				kills += sim.deathmatch.kills[t]
			contact_sum += first
			matches += 1
			sim.dispose()
		res[new_rules] = {"kills": kills, "first_contact": snappedf(contact_sum / matches, 0.1)}
	metrics["dm3_two_player_150s_x4"] = {"v152": res[false], "v153": res[true]}
	_check(float(res[true].first_contact) < float(res[false].first_contact), "DM-3 2-player first contact comes sooner (%s)" % JSON.stringify(metrics["dm3_two_player_150s_x4"]))
	_check(int(res[true].kills) >= int(res[false].kills) and int(res[true].kills) >= 4, "DM-3 2-player matches produce at least as many kills (%s)" % JSON.stringify(metrics["dm3_two_player_150s_x4"]))


# ------------------------------------------------------------------ conquest

func _ctl_sim(blue: Array, red: Array, arena: String = "control_crossroads", seed_v: int = 9) -> BattleSim:
	return BattleSim.new({"ruleset": "control", "arena_id": arena, "blue": blue, "red": red, "seed": seed_v, "max_time": 240.0})


func _ctl_brain(sim: BattleSim, team: int, flags: String = "") -> TacticianBrain:
	var kind: String = "tactician" if flags == "" else "tactician{%s}" % flags
	var b: TacticianBrain = AIFactory.make(kind, sim, team)
	sim.controllers[team] = b
	return b


func _pads_by_side(sim: BattleSim, cc: ConquestCommander) -> Dictionary:
	var own: Array = []
	var enemy: Array = []
	for pad in sim.domination.heal_zones:
		var terr: float = cc.territory(pad.center)
		if terr < 0.5:
			own.append(pad)
		elif terr > ConquestCommander.TERRITORY_HARD:
			enemy.append(pad)
	return {"own": own, "enemy": enemy}


# C-1: territory-aware pad choice, retreat without a safe pad, and trip
# commitment.
func _ctl_heal_trips() -> void:
	var roles: Dictionary = {}
	for new_rules in [false, true]:
		var sim: BattleSim = _ctl_sim(["nitro", "giant", "archer"], ["werewolf", "mage", "sniper"])
		var b: TacticianBrain = _ctl_brain(sim, 0, "" if new_rules else "cc_trip=0")
		sim.controllers[1] = null
		var cc: ConquestCommander = b.control_plan
		var sides: Dictionary = _pads_by_side(sim, cc)
		_check(not sides.own.is_empty() and not sides.enemy.is_empty(), "C-1 fixture map has own-side and enemy-side pads")
		if sides.own.is_empty() or sides.enemy.is_empty():
			sim.dispose()
			return
		var hurt: BUnit = sim.heroes[0]
		# Midway between our spawn and the enemy-side pad, own pads on cooldown.
		var enemy_pad: Dictionary = sides.enemy[0]
		_place(sim, hurt, cc.spawn_center.lerp(enemy_pad.center, 0.55))
		for e in sim.heroes:
			if e.team == 1:
				_place(sim, e, cc.enemy_spawn_center)
		sim.start()
		for pad in sim.domination.heal_zones:
			if str(pad.id) != str(enemy_pad.id):
				pad.ready_at = sim.time + 25.0
		hurt.hp = sim.max_hp(hurt) * 0.19
		cc.update([], true)
		var order: Dictionary = cc.intent(hurt)
		roles[new_rules] = [str(order.get("role", "")), str(order.get("heal_target", ""))]
		if new_rules:
			_check(str(order.get("heal_target", "")) != str(enemy_pad.id), "C-1 a pad deep in enemy territory is refused")
			# Own pads 25 s away: no point waiting, the hero stays in the objective pool.
			_check(str(order.get("role", "")) not in ["후퇴", "회복"] and int(order.get("point", -1)) >= 0,
				"C-1 with no pad back soon the wounded hero keeps an objective (%s)" % str(order.get("role", "")))
			# An own-side pad back within 8 s: wait beside it on our side.
			var soon: Dictionary = sides.own[0]
			soon.ready_at = sim.time + 7.5   # beyond a trip (6 s), within the 8 s wait
			cc.update([], true)
			order = cc.intent(hurt)
			_check(str(order.get("role", "")) == "후퇴" and cc.territory(order.goal) < 0.5 and (order.goal as Vector2).distance_to(soon.center) < float(soon.radius) + 80.0,
				"C-1 below 25%% with an own-side pad back soon the hero waits beside it (%s)" % str(order.get("role", "")))
			roles["v153_pad_soon"] = [str(order.get("role", "")), str(order.get("heal_target", ""))]
			# Commitment: a started trip survives a drop in its value.
			for pad in sim.domination.heal_zones:
				pad.ready_at = 0.0
			var own_pad: Dictionary = sides.own[0]
			_place(sim, hurt, (own_pad.center as Vector2).lerp(cc.spawn_center, 0.0) + ((sim.domination.points[0].center as Vector2) - (own_pad.center as Vector2)).limit_length(260.0))
			hurt.hp = sim.max_hp(hurt) * 0.2
			cc.update([], true)
			var trip_pad: String = str(cc.intent(hurt).get("heal_target", ""))
			# Healthier and further away: the V1.5.2 value rule would drop the trip.
			hurt.hp = sim.max_hp(hurt) * 0.75
			_place(sim, hurt, hurt.pos + ((sim.domination.points[1].center as Vector2) - hurt.pos).limit_length(420.0))
			cc.update([], true)
			var kept: String = str(cc.intent(hurt).get("heal_target", ""))
			_check(trip_pad != "" and kept == trip_pad, "C-1 a started heal trip stays committed until the pad is used (%s -> %s)" % [trip_pad, kept])
			# A more wounded ally arriving later does not take the committed pad.
			var other: BUnit = sim.heroes[1]
			for pad in sim.domination.heal_zones:
				if str(pad.id) == trip_pad:
					_place(sim, other, (pad.center as Vector2) + ((cc.spawn_center - (pad.center as Vector2)).normalized() * 70.0))
			other.hp = sim.max_hp(other) * 0.15
			cc.update([], true)
			_check(str(cc.intent(hurt).get("heal_target", "")) == trip_pad and str(cc.intent(other).get("heal_target", "")) != trip_pad,
				"C-1 a committed trip keeps its pad when a more wounded ally shows up (%s / %s)" % [str(cc.intent(hurt).get("heal_target", "")), str(cc.intent(other).get("heal_target", ""))])
			other.hp = sim.max_hp(other)
			_place(sim, other, cc.spawn_center)
			hurt.hp = sim.max_hp(hurt) * 0.9
			cc.update([], true)
			_check(str(cc.intent(hurt).get("heal_target", "")) == "", "C-1 the trip ends at 85%% health")
		else:
			_check(str(order.get("heal_target", "")) == str(enemy_pad.id), "C-1 fixture reproduces the V1.5.2 trip into enemy territory (%s)" % JSON.stringify(roles[new_rules]))
		sim.dispose()
	metrics["c1_wounded_midfield_order"] = {"v152": roles.get(false, []), "v153": roles.get(true, []), "v153_own_pad_back_in_7s": roles.get("v153_pad_soon", [])}


# C-1: a heal route through an objective the enemy holds is refused.
func _ctl_trip_path() -> void:
	var sim: BattleSim = _ctl_sim(["nitro"], ["werewolf"])
	var b: TacticianBrain = _ctl_brain(sim, 0)
	sim.controllers[1] = null
	sim.start()
	var cc: ConquestCommander = b.control_plan
	var found: bool = false
	for pi in sim.domination.points.size():
		var p: Dictionary = sim.domination.points[pi]
		for pad in sim.domination.heal_zones:
			var away: Vector2 = (p.center as Vector2) + ((p.center as Vector2) - (pad.center as Vector2)).normalized() * (float(p.radius) + 170.0)
			if sim.arena.resolve_circle(away, 30.0).distance_to(away) > 0.5:
				continue
			var path: PackedVector2Array = Navigator.get_for(sim.arena, sim.radius(sim.heroes[0])).path_points(away, pad.center)
			var through: bool = false
			var prev: Vector2 = away
			for q in path:
				through = through or Geometry2D.get_closest_point_to_segment(p.center, prev, q).distance_to(p.center) < float(p.radius) * 0.5
				prev = q
			if not through:
				continue
			_place(sim, sim.heroes[0], away)
			p.owner = 1
			var blocked_enemy: bool = bool(cc._trip_path(sim.heroes[0], pad.center).blocked)
			p.owner = 0
			var blocked_own: bool = bool(cc._trip_path(sim.heroes[0], pad.center).blocked)
			p.owner = -1
			_check(blocked_enemy and not blocked_own, "C-1 a heal route through an enemy-held objective is refused, through our own is not")
			found = true
			break
		if found:
			break
	_check(found, "C-1 fixture finds a heal route crossing an objective")
	sim.dispose()


# C-2: holders ignore gravity centred in their circle and small hazards; a
# hero outside its circle or standing in heavy damage is not exempt.
# V1.5.3 control maps keep damaging hazards off the capture points, so the
# fixture is a private copy of a control map with a weak well in one circle
# (independent of the shipped map data).
func _gravity_fixture(base: Arena, point: Dictionary) -> Arena:
	var data: Dictionary = base.data.duplicate(true)
	var hz: Array = (data.get("hazards", []) as Array).duplicate(true)
	var c: Vector2 = point.center
	hz.append({"id": "test_well", "type": "gravity", "shape": "circle", "x": c.x, "y": c.y, "radius": 120.0,
		"period": 7.0, "activeDuration": 2.4, "warningDuration": 1.0, "phase": 0.0, "damage": 6.0, "tickInterval": 0.5,
		"force": 120.0, "school": "magic"})
	data["hazards"] = hz
	data["id"] = "ctl_gravity_fixture"
	return Arena.from_data(data)


func _ctl_hold_exempt() -> void:
	var sim: BattleSim = _ctl_sim(["giant", "archer", "mage"], ["swordsman"], "control_waterway")
	var b: TacticianBrain = _ctl_brain(sim, 0)
	sim.controllers[1] = null
	var point: int = 0
	var p: Dictionary = sim.domination.points[point]
	var fixture: Arena = _gravity_fixture(sim.arena, p)
	sim.arena = fixture
	var vortex: Dictionary = {}
	for h in sim.arena.hazards:
		if str(h.type) == "gravity" and str(h.id) == "test_well":
			vortex = h
	_check(not vortex.is_empty() and (vortex.center as Vector2).distance_to(p.center) <= float(p.radius), "C-2 fixture gravity well is centred in a capture circle")
	if vortex.is_empty():
		sim.dispose()
		return
	var holder: BUnit = sim.heroes[0]
	_place(sim, holder, (p.center as Vector2) + Vector2(18.0, 0.0))
	sim.start()
	var cc: ConquestCommander = b.control_plan
	cc.update([], true)
	cc.assignments[holder.idx] = cc._objective_order(holder, point, "수비", "test", 100.0, 0.0, false, false)
	# A moment while the well is pulling.
	var t_active: float = -1.0
	for k in 400:
		var t: float = k * 0.05
		if bool(Arena.hazard_clock(vortex, t).active):
			t_active = t + 0.1
			break
	sim.time = t_active
	var raw: float = sim.arena.expected_hazard_damage(holder.pos, sim.time, sim.radius(holder), 1.0)
	_check(raw > 0.0 and cc.expected_hold_damage(holder) == 0.0 and cc.hold_exempt(holder), "C-2 a holder ignores the gravity well centred in its circle (raw %.1f)" % raw)
	var outside: Vector2 = (p.center as Vector2) + Vector2(float(p.radius) + 80.0, 0.0)
	_place(sim, holder, outside)
	_check(not cc.hold_exempt(holder), "C-2 a hero outside its circle is not exempt")
	# Heavy damage in the circle: a private copy of the map with a lava pool.
	var data: Dictionary = fixture.data.duplicate(true)
	(data.hazards as Array).append({"id": "test_lava", "type": "lava", "shape": "circle", "x": (p.center as Vector2).x, "y": (p.center as Vector2).y,
		"radius": 60.0, "damage": 60.0, "tickInterval": 0.5, "alwaysActive": true, "school": "magic"})
	sim.arena = Arena.from_data(data)
	_place(sim, holder, (p.center as Vector2) + Vector2(10.0, 0.0))
	_check(not cc.hold_exempt(holder), "C-2 a holder standing in lava is not exempt")
	b.cfg["cc_hold"] = 0.0
	sim.arena = fixture
	_place(sim, holder, (p.center as Vector2) + Vector2(18.0, 0.0))
	_check(not cc.hold_exempt(holder), "C-2 the lab switch cc_hold=0 turns the exemption off")
	sim.dispose()


# C-3: counts are held 2.5 s, walking heroes are sticky, and a short match
# reassigns fewer heroes before they arrive than the V1.5.2 planner.
func _ctl_churn() -> void:
	var sim: BattleSim = _ctl_sim(["giant", "archer", "mage"], ["swordsman"])
	var b: TacticianBrain = _ctl_brain(sim, 0)
	sim.start()
	var cc: ConquestCommander = b.control_plan
	var a: int = cc._held_seen(0, 2)
	sim.time += 1.0
	var held: int = cc._held_seen(0, 0)
	sim.time += 2.0
	var dropped: int = cc._held_seen(0, 0)
	_check(a == 2 and held == 2 and dropped == 0, "C-3 observed enemies near a point are held for 2.5 s")
	var u: BUnit = sim.heroes[0]
	cc.route0[u.idx] = {"point": 1, "len": 1000.0}
	_check(is_equal_approx(cc._hysteresis(u, 1, 300.0, false), ConquestCommander.REASSIGN_GAIN + ConquestCommander.PROGRESS_HYST * 0.7)
		and is_equal_approx(cc._hysteresis(u, 1, 20.0, true), 48.0), "C-3 hysteresis grows with route progress and needs a 60 gain to switch")
	sim.dispose()
	var unarrived: Dictionary = {false: 0, true: 0}
	for map_id in ["control_crossroads", "control_waterway"]:
		for new_rules in [false, true]:
			var s2: BattleSim = _ctl_sim(["engineer", "giant", "archer", "hermes", "mage"], ["swordsman", "sniper", "metatron", "pirate", "torturer"], map_id, 7100)
			var flags: String = "" if new_rules else "cc_steady=0"
			_ctl_brain(s2, 0, flags)
			_ctl_brain(s2, 1, flags)
			s2.start()
			var last: Dictionary = {}
			var arrived: Dictionary = {}
			var early: int = 0
			var upd: Array = [-1.0, -1.0]
			while s2.state == BattleSim.RUNNING and s2.time < 120.0:
				s2.step()
				for t in 2:
					var cp: ControlStrategy = s2.controllers[t].control_plan
					if cp.last_update == upd[t]:
						continue
					upd[t] = cp.last_update
					for h in s2.heroes:
						if h.team != t or not h.alive:
							continue
						var pt: int = int(cp.intent(h).get("point", -1))
						if pt < 0:
							continue
						if last.has(h.idx) and int(last[h.idx]) != pt:
							if not bool(arrived.get(h.idx, false)):
								early += 1
							arrived[h.idx] = false
						last[h.idx] = pt
						var pp: Dictionary = s2.domination.points[pt]
						if h.pos.distance_to(pp.center) <= float(pp.radius):
							arrived[h.idx] = true
			unarrived[new_rules] = int(unarrived[new_rules]) + early
			s2.dispose()
	metrics["c3_unarrived_reassignments_2x120s"] = {"v152": unarrived[false], "v153": unarrived[true]}
	_check(int(unarrived[true]) < int(unarrived[false]), "C-3 fewer reassignments before arrival (%s)" % JSON.stringify(metrics["c3_unarrived_reassignments_2x120s"]))


# C-4 and C-5: an unwatched enemy objective draws a back-capture, an owned
# objective nobody threatens needs no permanent guard, and orders carry a
# staging point for the retreat anchor.
func _ctl_backcap_and_staging() -> void:
	for new_rules in [false, true]:
		var sim: BattleSim = _ctl_sim(["engineer", "giant", "archer", "hermes", "mage"], ["swordsman", "sniper", "metatron", "pirate", "torturer"])
		var b: TacticianBrain = _ctl_brain(sim, 0, "" if new_rules else "cc_backcap=0,cc_stage=0")
		sim.controllers[1] = null
		sim.start()
		var cc: ConquestCommander = b.control_plan
		# The enemy owns the objective nearest to its spawn and nobody is seen.
		var far_i: int = 0
		var near_i: int = 0
		for i in sim.domination.points.size():
			if cc.territory(sim.domination.points[i].center) > cc.territory(sim.domination.points[far_i].center):
				far_i = i
			if cc.territory(sim.domination.points[i].center) < cc.territory(sim.domination.points[near_i].center):
				near_i = i
		sim.domination.points[far_i].owner = 1
		sim.domination.points[near_i].owner = 0
		sim.time = 30.0
		cc.update([], true)
		var backcaps: int = 0
		var staged: bool = true
		var idle_home: bool = bool(cc.summary.points[near_i].get("idle_home", false))
		for u in sim.heroes:
			if u.team != 0:
				continue
			var o: Dictionary = cc.intent(u)
			if str(o.get("role", "")) == "우회 점령" and int(o.point) == far_i:
				backcaps += 1
			if str(o.get("heal_target", "")) == "" and str(o.get("role", "")) != "후퇴":
				staged = staged and o.has("stage") and (o.stage as Vector2).is_equal_approx(cc.staging[int(o.point)])
		if new_rules:
			_check(backcaps == 1, "C-4 one spare hero back-captures the unwatched enemy objective")
			_check(idle_home, "C-4 an owned objective nobody threatens loses its free guard slot")
			_check(staged, "C-5 objective orders carry the staging point for the retreat anchor")
		else:
			_check(backcaps == 0 and not idle_home, "C-4 fixture: the V1.5.2 planner never back-captured")
		sim.dispose()


# DESIGN_153 section 1: a respawned conquest hero faces the enemy spawn
# centroid, also on maps where teams start top and bottom.
func _ctl_respawn_facing() -> void:
	var sim: BattleSim = _ctl_sim(["giant"], ["archer"])
	var data: Dictionary = sim.arena.data.duplicate(true)
	var w: float = float(data.get("width", Arena.WIDTH))
	var h: float = float(data.get("height", Arena.HEIGHT))
	data.spawns = {"blue": [{"x": w * 0.5, "y": h * 0.15}], "red": [{"x": w * 0.5 + 40.0, "y": h * 0.85}]}
	sim.arena = Arena.from_data(data)
	sim.start()
	var u: BUnit = sim.heroes[0]
	u.spawn_pos = Vector2(w * 0.5, h * 0.15)
	sim.kill_unit(u, null, {})
	sim.domination.respawn_at[u.idx] = sim.time
	sim.domination.pre_tick()
	var want: Vector2 = (Vector2(w * 0.5 + 40.0, h * 0.85) - u.pos).normalized()
	_check(u.alive and u.facing.dot(want) > 0.999, "respawned conquest hero faces the enemy spawn centroid (%s)" % str(u.facing))
	_check(u.facing.dot(Vector2.RIGHT) < 0.2, "respawn facing is no longer a fixed left/right")
	sim.dispose()


# ------------------------------------------------------------------ draft

func _fixture_arena(hazards: Array, extra: Dictionary = {}) -> Arena:
	var d: Dictionary = {"id": "draft_fixture", "width": 1408, "height": 792, "ruleset": "elimination",
		"bounds": {"minX": 37.4, "maxX": 1370.6, "minY": 37.4, "maxY": 754.6}, "obstacles": [], "hazards": hazards,
		"spawns": {"blue": [{"x": 200, "y": 396}], "red": [{"x": 1208, "y": 396}]}}
	for k in extra:
		d[k] = extra[k]
	return Arena.from_data(d)


func _draft_map_features() -> void:
	var lava: Dictionary = DraftDirector.map_features(_fixture_arena([{"id": "l", "type": "lava", "shape": "circle", "x": 704, "y": 396, "radius": 90,
		"damage": 34, "tickInterval": 0.5, "alwaysActive": true}]))
	var well: Dictionary = DraftDirector.map_features(_fixture_arena([{"id": "g", "type": "gravity", "shape": "circle", "x": 704, "y": 396, "radius": 90,
		"period": 9, "activeDuration": 2, "damage": 6, "tickInterval": 0.5, "force": 120}]))
	_check(float(lava.hazard) > float(well.hazard) * 4.0 and float(well.pull) > 0.0, "DR-2 a gravity well is a pull, not lava-grade damage (%.3f vs %.3f)" % [float(lava.hazard), float(well.hazard)])
	var busy: Dictionary = DraftDirector.map_features(_fixture_arena([
		{"id": "h1", "type": "haste", "shape": "circle", "x": 300, "y": 200, "radius": 40},
		{"id": "f1", "type": "healing_fountain", "shape": "circle", "x": 704, "y": 120, "radius": 48, "healPercent": 0.16, "cooldown": 18},
		{"id": "e1", "type": "eruption", "shape": "circle", "x": 704, "y": 396, "radius": 120, "period": 5, "activeDuration": 0.7, "damage": 90, "knockback": 115},
		{"id": "a1", "type": "artillery", "shape": "rect", "x": 400, "y": 200, "w": 600, "h": 400, "period": 12, "warningDuration": 1.5, "count": 3, "radius": 70, "damage": 60},
		{"id": "j1", "type": "jump_pad", "shape": "circle", "x": 250, "y": 600, "radius": 36, "target": {"x": 600, "y": 600}, "flightTime": 0.8},
		{"id": "r1", "type": "closing_ring", "x": 704, "y": 396, "startTime": 60, "endTime": 120, "startRadius": 700, "endRadius": 250, "damagePercent": 0.04, "tickInterval": 1.0},
		{"id": "m1", "type": "mud", "shape": "rect", "x": 500, "y": 500, "w": 300, "h": 120, "slow": 0.35}],
		{"obstacles": [{"id": "gate_a", "shape": "rect", "x": 690, "y": 250, "w": 28, "h": 120, "gate": {"group": "A", "period": 12, "openDuration": 6, "warningDuration": 1.5, "phase": 0}}],
		"forests": [{"x": 400, "y": 600, "radius": 90, "patch": 0}, {"x": 1000, "y": 200, "radius": 90, "patch": 1}]}))
	var missing: Array = []
	for key in ["haste", "fountain", "knockback", "artillery", "jump_pads", "ring", "mud", "gates", "concealment"]:
		if not (float(busy.get(key, 0.0)) > 0.0):
			missing.append(key)
	_check(missing.is_empty(), "DR-2 haste, fountain, knockback and the new gimmick types are read by name %s" % str(missing))
	# Spawn orientation: teams at top and bottom of a wide map have flanks.
	var side_by_side: Dictionary = DraftDirector.map_features(_fixture_arena([]))
	var top_bottom: Dictionary = DraftDirector.map_features(_fixture_arena([], {"spawns": {"blue": [{"x": 704, "y": 110}], "red": [{"x": 704, "y": 682}]}}))
	_check(float(top_bottom.flank) > float(side_by_side.flank) + 0.4 and float(top_bottom.approach) < float(side_by_side.approach),
		"DR-2 spawn orientation is a feature (flank %.2f vs %.2f)" % [float(top_bottom.flank), float(side_by_side.flank)])
	var bad: Array = []
	var saturated: Array = []
	var top3: Dictionary = {}
	var fits: Dictionary = {}
	var ids: Array = DB.ids().duplicate()
	ids.sort()
	for rs in ["elimination", "control"]:
		for a in DB.arenas_for(rs):
			var ar: Arena = a
			var mf: Dictionary = DraftDirector.map_features(ar)
			mf["control"] = 1.0 if rs == "control" else 0.0
			for key in DraftDirector.MAP_FEATURE_KEYS:
				var v: float = float(mf.get(key, -1.0))
				if not (v >= 0.0 and v <= 1.0) or is_nan(v):
					bad.append("%s.%s=%s" % [ar.id, key, str(v)])
			if float(mf.walls) > 0.985 or float(mf.sight) > 0.985:
				saturated.append(ar.id)
			if rs == "control":
				# What the map itself adds on top of the conquest mode term (the
				# mode term is the same on every control map and cannot move picks).
				var rows: Array = []
				for id in ids:
					var kf: Dictionary = DraftDirector.kit_features(DB.char_def(id))
					rows.append([id, DraftDirector.map_fit(kf, mf) - DraftDirector.map_fit(kf, {"control": 1.0})])
				rows.sort_custom(func(x, y): return float(x[1]) > float(y[1]))
				top3[ar.id] = [rows[0][0], rows[1][0], rows[2][0]]
				var vec: Dictionary = {}
				for row in rows:
					vec[row[0]] = float(row[1])
				fits[ar.id] = vec
	_check(bad.is_empty(), "DR-2 every feature of every arena is a finite value in [0, 1] %s" % str(bad))
	_check(saturated.is_empty(), "DR-2 wall and sight densities no longer saturate on large maps %s" % str(saturated))
	metrics["dr2_control_top3_map_specific_fit"] = top3
	# The three V1.5.2 control maps share size and spawn geometry; their own
	# features (objective hazards, pulls, pads, point layout) must still move
	# the per-hero fit, and on control fixtures that differ only in an
	# objective hazard the ranking itself must change.
	var keys: Array = fits.keys()
	var max_diff: float = 0.0
	for i in keys.size():
		for j in range(i + 1, keys.size()):
			for id in ids:
				max_diff = maxf(max_diff, absf(float(fits[keys[i]][id]) - float(fits[keys[j]][id])))
	_check(max_diff >= 0.02, "DR-2 control maps give heroes different map fit (max difference %.3f)" % max_diff)
	var ctl_extra: Dictionary = {"ruleset": "control", "control_points": [{"id": "A", "x": 400, "y": 396, "radius": 90}, {"id": "B", "x": 704, "y": 396, "radius": 90}, {"id": "C", "x": 1008, "y": 396, "radius": 90}]}
	var calm_fix: Dictionary = DraftDirector.map_features(_fixture_arena([], ctl_extra))
	var hot_fix: Dictionary = DraftDirector.map_features(_fixture_arena([{"id": "pulse", "type": "eruption", "shape": "circle", "x": 704, "y": 396, "radius": 120,
		"period": 6, "activeDuration": 0.8, "damage": 110, "knockback": 120, "tickInterval": 0.8}], ctl_extra))
	calm_fix["control"] = 1.0
	hot_fix["control"] = 1.0
	var rank_calm: Array = []
	var rank_hot: Array = []
	for id in ids:
		var kf: Dictionary = DraftDirector.kit_features(DB.char_def(id))
		rank_calm.append([id, DraftDirector.map_fit(kf, calm_fix)])
		rank_hot.append([id, DraftDirector.map_fit(kf, hot_fix)])
	rank_calm.sort_custom(func(x, y): return float(x[1]) > float(y[1]))
	rank_hot.sort_custom(func(x, y): return float(x[1]) > float(y[1]))
	var order_calm: Array = rank_calm.map(func(x): return x[0])
	var order_hot: Array = rank_hot.map(func(x): return x[0])
	_check(float(hot_fix.point_hazard) > 0.3 and float(hot_fix.point_push) > 0.3 and order_calm.slice(0, 5) != order_hot.slice(0, 5),
		"DR-2 a hazard on an objective changes the control map-fit ranking %s vs %s" % [str(order_calm.slice(0, 5)), str(order_hot.slice(0, 5))])


# DR-3: the engine check runs only for close finalists, a control check lasts
# 60 s, and building the check battle is split across work units.
func _draft_rollout_gate() -> void:
	var opts: Dictionary = {"team_size": 1, "arena_id": "classic", "ruleset": "elimination", "seed": 9173, "budget": 4000}
	var dd: DraftDirector = DraftDirector.new(opts)
	var dec: Dictionary = dd.decide(["giant"], [])
	var ro: Dictionary = dec.search.rollout
	var gap: float = float(dec.search_score) - float(dec.alternatives[0].search_score) if not dec.alternatives.is_empty() else 0.0
	_check((gap > 0.03) == (int(ro.games) == 0) and (int(ro.games) == 0) == (str(ro.skipped) == "gap"), "DR-3 the engine check runs exactly when finalists are within 0.03 (gap %.3f, games %d)" % [gap, int(ro.games)])
	metrics["dr3_default_final_pick"] = {"gap": snappedf(gap, 0.0001), "games": ro.games, "skipped": ro.skipped}
	var copts: Dictionary = {"team_size": 1, "arena_id": "control_crossroads", "ruleset": "control", "seed": 9173, "budget": 4000, "rollout_gap": 1.0}
	var cd: DraftDirector = DraftDirector.new(copts)
	cd.begin(["giant"], [])
	while str(cd.progress().phase) != "rollout" and not bool(cd.progress().done):
		cd.advance(1)
	_check(str(cd.progress().phase) == "rollout", "DR-3 a forced control final pick enters the engine check")
	cd.advance(1)
	var built_not_started: bool = cd._job.rollout_sim != null and cd._job.rollout_sim.state == BattleSim.IDLE
	_check(built_not_started, "DR-3 building the check battle and starting it are separate work units")
	var job = cd._job
	while int(job.rollout_stage) != 3 and not bool(cd.progress().done):
		cd.advance(1)
	var ticks_before: int = int(job.rollout_ticks)
	job.rollout_unit_usec = 1.0e9
	cd.advance_until(Time.get_ticks_usec() + 50000)
	_check(int(job.rollout_ticks) - ticks_before == 1, "DR-3 a slice never starts a battle tick expected to overrun its frame deadline (%d ticks)" % (int(job.rollout_ticks) - ticks_before))
	job.rollout_unit_usec = 0.0
	var slices: Array = []
	while not bool(cd.progress().done):
		var t0: int = Time.get_ticks_usec()
		cd.advance_until(t0 + 8000)
		slices.append(Time.get_ticks_usec() - t0)
	var cres: Dictionary = cd.result()
	var cro: Dictionary = cres.search.rollout
	var long_games: bool = true
	var paired: bool = true
	for row: Dictionary in cro.rows:
		long_games = long_games and (int(row.ticks) >= 1800 or bool(row.finished))
		paired = paired and int(row.side) == 0
	_check(int(cro.games) == 2 and int(cro.horizon_ticks) >= 1800 and long_games, "DR-3 a control engine check lasts 60 s per game")
	_check(paired and int(cro.ticks) <= 3600, "DR-3 a control check plays each finalist once on the same side (paired, %d ticks)" % int(cro.ticks))
	slices.sort()
	metrics["dr3_control_1v1_forced"] = {"ticks": cro.ticks, "slices": slices.size(), "largest_slice_ms": snappedf(slices.back() / 1000.0, 0.1) if not slices.is_empty() else 0.0}


# W-1: every AI kind plays deathmatch with DeathmatchBrain; the V1.5.2 rules
# stay reachable for a meaningful lab comparison.
func _wiring() -> void:
	var sim: BattleSim = _dm_sim(["swordsman", "archer"])
	var kinds_ok: bool = true
	for kind in ["tactician", "tactician14", "classic"]:
		kinds_ok = kinds_ok and AIFactory.make(kind, sim, 0) is DeathmatchBrain
	_check(kinds_ok, "W-1 every AI kind is the deathmatch brain in deathmatch (documented)")
	var old: DeathmatchBrain = AIFactory.make("tactician{dm153=0}", sim, 0)
	var new_: DeathmatchBrain = AIFactory.make("tactician", sim, 0)
	_check(not old.v153() and new_.v153(), "W-1 the lab can compare V1.5.2 and V1.5.3 deathmatch rules with tactician{dm153=0}")
	sim.dispose()
