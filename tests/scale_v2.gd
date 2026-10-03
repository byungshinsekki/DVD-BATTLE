extends SceneTree

# V2 battleground-scale performance (B-PERF, DESIGN_V2 §3.7). Headless.
#  * 30 AI heroes, free-for-all, on the synthetic 2x2 deathmatch map
#    (7200x4400, tools/br_perf_v2/br_map.gd) for 60 s: no errors, finite state,
#    no path grid built after start, at most 4 non-urgent decisions per tick,
#    far beliefs frozen.
#  * The same seed twice gives the same signature; the reference passes
#    (exhaustive visibility, collision loop, unindexed forest and hazard scans)
#    give the same battle as the fast ones.
#  * Fast visibility equals the exhaustive pass for 300 ticks.
#  * Index equivalence on existing maps: forest lookups, hazard sums, grid
#    builds (per obstacle vs per cell) and connected components (vs a flood fill).
#  * The scale rules stay off for the 12-player deathmatch and the team modes
#    (no frozen beliefs, no deferred decisions there).
#  * Eliminated-team controllers are detached (and can be attached again).
#  * B-PERF2: the AI pre-tick snapshot equals the live answers in a 30-hero
#    battle and is never taken elsewhere; the exact helpers (item gain memo,
#    hazard bound buckets, mud boxes, cached point visibility, the danger
#    profile table) equal their reference forms; per-hero route reuse runs in
#    scale battles only.

const BrMap := preload("res://tools/br_perf_v2/br_map.gd")

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
	_gates()
	_event_codes_cover_intel()
	_index_equivalence()
	_components()
	_prebuild_small()
	_small_modes_unchanged()
	_detach()
	_perf2_helpers()
	_perf2_snapshot()
	_big_battle()
	var status: String = "PASS" if failed.is_empty() else "FAIL"
	print("SCALE_V2 ", JSON.stringify({"status": status, "passed": passed, "failed": failed, "metrics": metrics}))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):
			var f: FileAccess = FileAccess.open(arg.substr(9), FileAccess.WRITE)
			if f:
				f.store_string(JSON.stringify({"suite": "scale_v2", "status": status, "passed": passed, "failed": failed, "metrics": metrics}, "  "))
	quit(0 if failed.is_empty() else 1)


# ------------------------------------------------------------------ helpers

func _players(n: int, seed_v: int) -> Array:
	var ids: Array = DB.ids()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var pool: Array = ids.duplicate()
	var out: Array = []
	while out.size() < n:
		if pool.is_empty():
			pool = ids.duplicate()
		out.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
	return out


# The synthetic big map stands in for the dm_forest_village layout of this
# seed (DB's deathmatch cache), so a deathmatch config plays on it.
func _install_big(seed_v: int) -> Arena:
	var key: String = "dm_forest_village:%d" % seed_v
	if DB.dm_cache.has(key) and (DB.dm_cache[key] as Arena).width > 7000.0:
		return DB.dm_cache[key]
	var a: Arena = Arena.from_data(BrMap.build(seed_v))
	a.shared = true
	DB.dm_cache[key] = a
	DB.dm_cache_order.append(key)
	return a


func _sim(cfg: Dictionary) -> BattleSim:
	var sim: BattleSim = BattleSim.new(cfg)
	for t in sim.team_count:
		sim.controllers[t] = AIFactory.make("tactician", sim, t)
	return sim


func _dm_cfg(players: Array, seed_v: int, map_id: String = "dm_forest_village", secs: float = 120.0) -> Dictionary:
	return {"ruleset": "deathmatch", "arena_id": map_id, "players": players, "seed": seed_v, "max_time": secs, "kill_target": 999}


# Chained digest: each tick hashes the previous digest, every unit's state,
# the team sight arrays and the tick's events, so equal digests at tick N mean
# the two battles matched on every tick up to N.
func _chain(prev: String, sim: BattleSim) -> String:
	var row := PackedFloat64Array()
	row.append(sim.tick)
	for u in sim.units:
		row.append(u.pos.x)
		row.append(u.pos.y)
		row.append(u.hp)
		row.append(1.0 if u.alive else 0.0)
		row.append(u.next_decision_at)
		row.append(float(u.decisions))
	var bytes: PackedByteArray = prev.to_utf8_buffer()
	bytes.append_array(row.to_byte_array())
	for t in sim.team_count:
		bytes.append_array(sim.seen[t])
	var ev: String = ""
	for e in sim.tick_events:
		ev += "%s:%d:%d;" % [str(e.type), int(e.get("s", -1)), int(e.get("g", -1))]
	bytes.append_array(ev.to_utf8_buffer())
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(bytes)
	return h.finish().hex_encode()


func _frozen_steps(sim: BattleSim) -> int:
	var n: int = 0
	for c in sim.controllers:
		if c is TacticianBrain:
			n += int((c as TacticianBrain).intel.frozen_steps)
	return n


func _route_hits(sim: BattleSim) -> int:
	var n: int = 0
	for c in sim.controllers:
		if c is TacticianBrain:
			n += (c as TacticianBrain).lod_route_hits
	return n


func _steer_hits(sim: BattleSim) -> int:
	var n: int = 0
	for c in sim.controllers:
		if c is TacticianBrain:
			n += (c as TacticianBrain).lod_steer_hits
	return n


func _finite(sim: BattleSim) -> bool:
	for u in sim.units:
		if not is_finite(u.hp) or not u.pos.is_finite() or not u.vel.is_finite():
			return false
	return true


# ------------------------------------------------------------------ gates

# Every event type TeamIntel.ingest matches on must have an AI event code;
# a type left at code 0 is skipped before the match (B-PERF2 prefilter), so a
# new intel arm without a code would silently never run.
func _event_codes_cover_intel() -> void:
	var text: String = FileAccess.get_file_as_string("res://scripts/ai/intel.gd")
	var start: int = text.find("func ingest(")
	var stop: int = text.find("
func ", start + 10)
	var body: String = text.substr(start, stop - start)
	var arm: RegEx = RegEx.create_from_string("(?m)^\t\t\t((?:\"[A-Z_]+\"(?:, )?)+):")
	var name_re: RegEx = RegEx.create_from_string("\"([A-Z_]+)\"")
	var missing: Array = []
	var seen: int = 0
	for m in arm.search_all(body):
		for n in name_re.search_all(m.get_string(1)):
			seen += 1
			if not BattleSim.AI_EV_CODES.has(n.get_string(1)):
				missing.append(n.get_string(1))
	_check(seen >= 20 and missing.is_empty(), "every intel ingest event type has an AI event code (%d arms; missing %s)" % [seen, str(missing)])


func _gates() -> void:
	var dm12: BattleSim = _sim(_dm_cfg(_players(12, 31), 31, "dm_ruined_town"))
	dm12.start()
	_check(not dm12.scale_lod, "12-player deathmatch is not a scale battle")
	dm12.dispose()
	var dm13: BattleSim = _sim(_dm_cfg(_players(13, 32), 32, "dm_ruined_town"))
	dm13.start()
	_check(dm13.scale_lod, "13 heroes make a scale battle")
	dm13.dispose()
	var e3: BattleSim = _sim({"ruleset": "elimination", "arena_id": "classic", "blue": ["swordsman", "archer", "mage"], "red": ["giant", "sniper", "hermes"], "seed": 33})
	e3.start()
	_check(not e3.scale_lod and e3.nav_prebuilt.is_empty(), "3v3 elimination is not a scale battle and keeps lazy grids")
	e3.dispose()
	_install_big(4242)
	var big8: BattleSim = _sim(_dm_cfg(_players(8, 4242), 4242))
	big8.start()
	_check(big8.arena.width > 7000.0 and big8.scale_lod, "a battleground-size map is a scale battle even with 8 heroes")
	big8.dispose()


# ------------------------------------------------------------------ indexes

func _index_maps() -> Array:
	var out: Array = [_install_big(4242), DB.deathmatch_arena("dm_forest_village", 4243), DB.deathmatch_arena("dm_open_steppe", 77)]
	for rs in ["elimination", "control"]:
		for a in DB.arenas_for(rs):
			if not (a as Arena).forest_x.is_empty() or not (a as Arena).hazards.is_empty():
				out.append(a)
	return out


func _index_equivalence() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2468
	var forest_bad: int = 0
	var hazard_bad: int = 0
	var checked: int = 0
	for item in _index_maps():
		var a: Arena = item
		for k in 400:
			var p := Vector2(rng.randf_range(-20.0, a.width + 20.0), rng.randf_range(-20.0, a.height + 20.0))
			var q: Vector2 = p + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, 700.0)
			var r: float = rng.randf_range(0.0, 30.0)
			var t: float = rng.randf_range(0.0, 200.0)
			var skip: int = 0 if k % 3 != 0 else Arena.TYPE_BITS.get("lava", 0)
			Arena.index_off = false
			var f1: int = a.forest_at(p)
			var o1: bool = a.forest_occludes(p, q)
			var h1: float = a.hazard_penalty(p, t, r, skip)
			var e1: float = a.expected_hazard_damage(p, t, r, 1.2, skip, 1500.0)
			Arena.index_off = true
			var f2: int = a.forest_at(p)
			var o2: bool = a.forest_occludes(p, q)
			var h2: float = a.hazard_penalty(p, t, r, skip)
			var e2: float = a.expected_hazard_damage(p, t, r, 1.2, skip, 1500.0)
			Arena.index_off = false
			if f1 != f2 or o1 != o2:
				forest_bad += 1
			if h1 != h2 or e1 != e2:
				hazard_bad += 1
			checked += 1
	_check(forest_bad == 0, "forest index equals the linear scan (%d / %d samples differ)" % [forest_bad, checked])
	_check(hazard_bad == 0, "hazard boxes leave penalties and expected damage unchanged (%d / %d differ)" % [hazard_bad, checked])
	var grid_bad: int = 0
	var grids: int = 0
	var t0: int = Time.get_ticks_usec()
	for item in _index_maps():
		var a2: Arena = item
		if not a2.gates.is_empty():
			continue
		for b in [12.0, 18.0, 26.0, 28.0]:
			var nav: Navigator = Navigator.for_arena(a2, b)
			grid_bad += nav.debug_build_mismatch()
			grids += 1
	metrics["grid_compare_ms"] = int((Time.get_ticks_usec() - t0) / 1000.0)
	_check(grids > 8 and grid_bad == 0, "per-obstacle grid build equals the per-cell test (%d grids, %d cells differ)" % [grids, grid_bad])


# ------------------------------------------------------------------ components

# 4-neighbour flood fill over the grid's solid flags (reference labels).
func _flood_labels(nav: Navigator) -> PackedInt32Array:
	var n: int = nav.cols * nav.rows
	var lab: PackedInt32Array = PackedInt32Array()
	lab.resize(n)
	lab.fill(-1)
	var queue: PackedInt32Array = PackedInt32Array()
	queue.resize(n)
	var next: int = 0
	for s in n:
		if lab[s] >= 0 or nav.grid.is_point_solid(Vector2i(s % nav.cols, s / nav.cols)):
			continue
		var head: int = 0
		var tail: int = 1
		queue[0] = s
		lab[s] = next
		while head < tail:
			var c: int = queue[head]
			head += 1
			var x: int = c % nav.cols
			var y: int = c / nav.cols
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + d.x
				var ny: int = y + d.y
				if nx < 0 or ny < 0 or nx >= nav.cols or ny >= nav.rows:
					continue
				var k: int = ny * nav.cols + nx
				if lab[k] >= 0 or nav.grid.is_point_solid(Vector2i(nx, ny)):
					continue
				lab[k] = next
				queue[tail] = k
				tail += 1
		next += 1
	return lab


func _same_partition(nav: Navigator) -> bool:
	var ref: PackedInt32Array = _flood_labels(nav)
	var map_a: Dictionary = {}
	var map_b: Dictionary = {}
	for i in ref.size():
		var c: Vector2i = Vector2i(i % nav.cols, i / nav.cols)
		var mine: int = nav.component_of(c)
		if (ref[i] < 0) != (mine < 0):
			return false
		if ref[i] < 0:
			continue
		if int(map_a.get(ref[i], mine)) != mine or int(map_b.get(mine, ref[i])) != ref[i]:
			return false
		map_a[ref[i]] = mine
		map_b[mine] = ref[i]
	return true


func _components() -> void:
	# A closed box (walls 24 px thick) leaves a pocket no route can enter.
	var walls: Array = [
		{"id": "n", "x": 560.0, "y": 260.0, "w": 300.0, "h": 24.0},
		{"id": "s", "x": 560.0, "y": 536.0, "w": 300.0, "h": 24.0},
		{"id": "w", "x": 560.0, "y": 260.0, "w": 24.0, "h": 300.0},
		{"id": "e", "x": 836.0, "y": 260.0, "w": 24.0, "h": 300.0}]
	var a: Arena = Arena.from_data({"id": "scale_v2_pocket", "name": "pocket", "width": 1408.0, "height": 792.0, "obstacles": walls,
		"spawns": {"blue": [{"x": 150, "y": 396}], "red": [{"x": 1250, "y": 396}]}})
	var nav: Navigator = Navigator.for_arena(a, 12.0)
	var inside := Vector2(710, 410)
	var out_a := Vector2(200, 200)
	var out_b := Vector2(1200, 600)
	_check(nav.component_count >= 2, "the closed box makes its own component (%d components)" % nav.component_count)
	_check(not nav.reachable(out_a, inside) and nav.reachable(out_a, out_b), "reachable() separates the pocket from the open floor")
	_check(nav.direct_length(out_a, inside, 12.0) == INF and nav.path_points(out_a, inside, false).is_empty(), "unreachable goals answer INF / no path without a search")
	var ca: Vector2i = nav._snap(out_a, out_b)
	var cb: Vector2i = nav._snap(out_b, out_a)
	_check(nav.path_points(out_a, out_b, false) == nav.grid.get_point_path(ca, cb, false), "reachable routes are the plain A* routes")
	_check(_same_partition(nav), "run labels equal a flood fill (pocket arena)")
	var dm_nav: Navigator = Navigator.for_arena(DB.deathmatch_arena("dm_forest_village", 4243), 18.0)
	_check(_same_partition(dm_nav), "run labels equal a flood fill (deathmatch map, bucket 18)")
	var big_nav: Navigator = Navigator.for_arena(_install_big(4242), 26.0)
	_check(big_nav.coarse != null and dm_nav.coarse == null and nav.coarse == null, "coarse routing exists only on battleground-size maps")
	metrics["big_components_b26"] = big_nav.component_count


# ------------------------------------------------------------------ small modes

func _prebuild_small() -> void:
	var players: Array = ["giant", "swordsman", "archer", "mage", "hermes", "sniper"]
	var sim: BattleSim = _sim(_dm_cfg(players, 515, "dm_open_steppe"))
	sim.start()
	_check(sim.nav_prebuilt.has(28.0) and sim.nav_prebuilt.has(26.0) and sim.nav_prebuilt.has(18.0) and sim.nav_prebuilt.has(12.0), "a giant's roster pre-builds buckets 12/18/26/28 (%s)" % str(sim.nav_prebuilt))
	var keys: Array = Navigator._cache.keys()
	for i in 150:
		sim.step()
	var fresh: int = 0
	for k in Navigator._cache.keys():
		if not keys.has(k):
			fresh += 1
	_check(fresh == 0, "no path grid is built during a deathmatch with a giant (%d new)" % fresh)
	sim.dispose()


func _small_modes_unchanged() -> void:
	var dm: BattleSim = _sim(_dm_cfg(_players(12, 4040), 4040, "dm_forest_village", 30.0))
	dm.start()
	for i in 600:
		dm.step()
	_check(not dm.scale_lod and _frozen_steps(dm) == 0 and dm.lod_deferred == 0, "12-player deathmatch: no frozen beliefs, no deferred decisions (frozen %d, deferred %d)" % [_frozen_steps(dm), dm.lod_deferred])
	_check(dm.lod_decisions[0] + dm.lod_decisions[1] + dm.lod_decisions[2] == 0, "12-player deathmatch keeps the roster-size decision interval")
	_check(dm.ai_snapshot_builds == 0 and _route_hits(dm) == 0, "12-player deathmatch: no pre-tick snapshot, no long route reuse (B-PERF2)")
	_check(_steer_hits(dm) == 0, "12-player deathmatch: steering is never reused (B-PERF2)")
	dm.dispose()
	var e5: BattleSim = _sim({"ruleset": "elimination", "arena_id": "classic", "blue": ["swordsman", "archer", "mage", "giant", "world_tree"], "red": ["sniper", "hermes", "joker", "metatron", "pirate"], "seed": 4041})
	e5.start()
	for i in 600:
		e5.step()
	_check(_frozen_steps(e5) == 0 and e5.lod_deferred == 0 and e5.lod_decisions[1] == 0, "5v5 elimination: scale rules stay off")
	_check(e5.ai_snapshot_builds == 0 and _route_hits(e5) == 0, "5v5 elimination: no pre-tick snapshot, no long route reuse (B-PERF2)")
	_check(_steer_hits(e5) == 0, "5v5 elimination: steering is never reused (B-PERF2)")
	e5.dispose()


# ------------------------------------------------------------------ detach

func _detach() -> void:
	var sim: BattleSim = _sim(_dm_cfg(_players(6, 606), 606, "dm_open_steppe"))
	sim.start()
	for i in 30:
		sim.step()
	var victim: BUnit = sim.heroes[2]
	var old = sim.controllers[2]
	sim.kill_unit(victim, null, {})
	sim.detach_controller(2)
	_check(sim.controllers[2] == null and (old as TeamController).sim == null, "detach_controller empties the slot and disposes the controller")
	var made: int = victim.decisions
	for i in 240:
		sim.step()
	_check(victim.decisions == made and sim.state == BattleSim.RUNNING, "a detached team makes no decisions while the battle runs on")
	sim.attach_controller(2, AIFactory.make("tactician", sim, 2))
	for i in 120:
		sim.step()
	_check(sim.controllers[2] != null and victim.decisions > made, "attach_controller brings a controller back")
	sim.dispose()


# ------------------------------------------------------------------ big battle

func _big_battle() -> void:
	var seed_v: int = 4242
	_install_big(seed_v)
	var players: Array = _players(30, seed_v)
	var cfg: Dictionary = _dm_cfg(players, seed_v, "dm_forest_village", 70.0)
	# A: 60 s with every check.
	var sim: BattleSim = _sim(cfg)
	sim.start()
	_check(sim.scale_lod and sim.heroes.size() == 30, "30-hero battle on the big map runs with the scale rules")
	var grid_keys: Array = Navigator._cache.keys()
	var chain: String = ""
	var vis_bad: int = 0
	var finite_ok: bool = true
	var digest_300: String = ""
	var digest_600: String = ""
	var worst: float = 0.0
	var total: float = 0.0
	while sim.state == BattleSim.RUNNING and sim.time < 60.0 - 0.001:
		var t0: int = Time.get_ticks_usec()
		sim.step()
		var ms: float = (Time.get_ticks_usec() - t0) / 1000.0
		total += ms
		worst = maxf(worst, ms)
		chain = _chain(chain, sim)
		if sim.tick <= 300:
			vis_bad += sim.debug_visibility_mismatch()
		if sim.tick % 30 == 0 and not _finite(sim):
			finite_ok = false
		if sim.tick == 300:
			digest_300 = chain
		if sim.tick == 600:
			digest_600 = chain
	var fresh: int = 0
	for k in Navigator._cache.keys():
		if not grid_keys.has(k):
			fresh += 1
	metrics["big_mean_tick_ms"] = snappedf(total / maxf(1.0, sim.tick), 0.01)
	metrics["big_worst_tick_ms"] = snappedf(worst, 0.1)
	metrics["big_frozen_steps"] = _frozen_steps(sim)
	metrics["big_deferred"] = sim.lod_deferred
	metrics["big_decisions"] = [sim.lod_decisions[0], sim.lod_decisions[1], sim.lod_decisions[2]]
	metrics["big_prebuilt"] = sim.nav_prebuilt
	_check(sim.tick >= 1800, "the 30-hero battle ran 60 s (%d ticks)" % sim.tick)
	_check(finite_ok, "no non-finite unit state in the 30-hero battle")
	_check(vis_bad == 0, "fast visibility equals the exhaustive pass for 300 ticks (%d entries differ)" % vis_bad)
	_check(fresh == 0, "no path grid is built after start (%d built mid-match)" % fresh)
	_check(sim.lod_max_nonurgent <= BattleSim.LOD_NON_URGENT_PER_TICK and sim.lod_deferred > 0, "at most %d non-urgent decisions per tick (most in one tick: %d; %d deferrals)" % [BattleSim.LOD_NON_URGENT_PER_TICK, sim.lod_max_nonurgent, sim.lod_deferred])
	_check(_frozen_steps(sim) > 0, "far, long-unseen beliefs are frozen on the big map")
	var d_sum: int = sim.lod_decisions[0] + sim.lod_decisions[1] + sim.lod_decisions[2]
	_check(sim.lod_decisions[2] > 0 and sim.lod_decisions[1] > 0 and d_sum > 0, "decisions use the calm and contact detail levels")
	metrics["big_route_reuse"] = _route_hits(sim)
	metrics["big_snapshot_builds"] = sim.ai_snapshot_builds
	_check(_route_hits(sim) > 0 and sim.ai_snapshot_builds >= sim.tick, "scale battle reuses routes and takes one pre-tick snapshot per tick (B-PERF2: %d reuses, %d snapshots)" % [_route_hits(sim), sim.ai_snapshot_builds])
	metrics["big_steer_reuse"] = _steer_hits(sim)
	_check(_steer_hits(sim) > 0 and _steer_hits(sim) < sim.tick * sim.heroes.size() / 2, "calm walkers reuse their steering on at most every other tick (B-PERF2: %d reuses)" % _steer_hits(sim))
	var final_a: String = chain
	sim.dispose()
	# B: the same seed again (20 s) must replay tick for tick.
	var sim_b: BattleSim = _sim(cfg)
	sim_b.start()
	var chain_b: String = ""
	while sim_b.tick < 600:
		sim_b.step()
		chain_b = _chain(chain_b, sim_b)
	_check(chain_b == digest_600, "the same seed gives the same battle (every tick up to 20 s)")
	sim_b.dispose()
	# C: reference passes (exhaustive visibility, collision loop, unindexed
	# forest and hazard scans) for 10 s give the same battle.
	BattleSim.vis_exhaustive = true
	BattleSim.collide_exhaustive = true
	Arena.index_off = true
	var sim_c: BattleSim = _sim(cfg)
	sim_c.start()
	var ref_300: String = ""
	while sim_c.tick < 300:
		sim_c.step()
		ref_300 = _chain(ref_300, sim_c)
	sim_c.dispose()
	BattleSim.vis_exhaustive = false
	BattleSim.collide_exhaustive = false
	Arena.index_off = false
	_check(ref_300 == digest_300, "reference passes replay the fast battle exactly (every tick up to 10 s)")
	metrics["big_final"] = final_a.substr(0, 16)


# ------------------------------------------------------------------ B-PERF2

# The old _mud_cost body (reference for the box pre-test).
func _mud_ref(b: TacticianBrain, u: BUnit, p: Vector2, r: float, kiting: bool) -> float:
	if b._gim_mud.is_empty() or not b.sim.env.type_active("mud") or float(b.cfg.get("gmd", 1.0)) < 0.5:
		return 0.0
	var slow: float = 0.0
	for f: float in [0.34, 0.67, 1.0]:
		var q: Vector2 = u.pos.lerp(p, f)
		var worst: float = 0.0
		for h: Dictionary in b._gim_mud:
			if Arena.shape_contains(h, q, r * 0.28):
				worst = maxf(worst, clampf(float(h.get("slow", 0.3)), 0.0, 0.6))
		slow += worst
	if slow <= 0.0:
		return 0.0
	slow /= 3.0
	return slow * (u.pos.distance_to(p) * 0.08 + 14.0) * (2.0 if kiting else 1.0)


func _hero_of_team(sim: BattleSim, team: int) -> BUnit:
	var u: BUnit = null
	for h in sim.heroes:
		if h.team == team and h.alive:
			u = h
	return u


func _perf2_helpers() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 97531
	# Item gain memo: the cached answer is gain() itself (asked twice).
	var ids: Array = DB.ids()
	var items: Array = ItemDefs.ORDER.duplicate()
	var gain_bad: int = 0
	for k in 300:
		var d: Defs.CharDef = DB.char_def(str(ids[rng.randi_range(0, ids.size() - 1)]))
		var held: Array = []
		for h in rng.randi_range(0, 3):
			held.append(str(items[rng.randi_range(0, items.size() - 1)]))
		var item: String = str(items[rng.randi_range(0, items.size() - 1)])
		var g1: float = ItemValuation.gain(d, item, held, 3)
		if g1 != ItemValuation.gain_cached(d, item, held, 3) or g1 != ItemValuation.gain_cached(d, item, held, 3):
			gain_bad += 1
	_check(not items.is_empty() and gain_bad == 0, "item gain memo equals gain() (%d / 300 differ)" % gain_bad)
	# Hazard bound buckets, mud boxes, cached point visibility and the danger
	# profile table on the big map (hazards, mud), 8 s into a 30-hero battle.
	_install_big(4242)
	var sim: BattleSim = _sim(_dm_cfg(_players(30, 4242), 4242, "dm_forest_village", 30.0))
	sim.start()
	for i in 240:
		sim.step()
	var near_bad: int = 0
	var seg_bad: int = 0
	var mud_bad: int = 0
	var mud_hits: int = 0
	var vis_bad: int = 0
	var probes: int = 0
	for ci in sim.controllers.size():
		var b: TacticianBrain = sim.controllers[ci]
		var u: BUnit = _hero_of_team(sim, ci)
		if b == null or u == null:
			continue
		b._refresh_hazard_bounds()
		b._refresh_gimmicks()
		for k in 60:
			var p := Vector2(rng.randf_range(-40.0, sim.arena.width + 40.0), rng.randf_range(-40.0, sim.arena.height + 40.0))
			var q: Vector2 = p + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, 900.0)
			var pad: float = rng.randf_range(0.0, 320.0)
			var ref_near: bool = false
			var ref_seg: bool = false
			for hb: Vector3 in b._haz_bounds:
				var rr: float = hb.z + pad
				var c: Vector2 = Vector2(hb.x, hb.y)
				if p.distance_squared_to(c) <= rr * rr:
					ref_near = true
				if Geometry2D.get_closest_point_to_segment(c, p, q).distance_to(c) <= hb.z + pad:
					ref_seg = true
			if b._haz_bounds_near(p, pad) != ref_near:
				near_bad += 1
			if b._haz_bounds_near_segment(p, q, pad) != ref_seg:
				seg_bad += 1
			probes += 1
		# Mud: probes between points around each patch.
		var saved: Vector2 = u.pos
		for h: Dictionary in b._gim_mud:
			var hc: Vector2 = Arena._shape_center(h)
			for k2 in 6:
				u.pos = hc + Vector2(rng.randf_range(-260.0, 260.0), rng.randf_range(-260.0, 260.0))
				var target: Vector2 = hc + Vector2(rng.randf_range(-260.0, 260.0), rng.randf_range(-260.0, 260.0))
				var r: float = rng.randf_range(10.0, 30.0)
				var m2: float = _mud_ref(b, u, target, r, k2 % 2 == 0)
				if b._mud_cost(u, target, r, k2 % 2 == 0) != m2:
					mud_bad += 1
				if m2 > 0.0:
					mud_hits += 1
		u.pos = saved
		# Cached point visibility equals _point_visible.
		b.intel._pv_ready = false
		for k3 in 20:
			var vp: Vector2 = u.pos + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, 900.0)
			if b.intel._point_visible_cached(vp) != b.intel._point_visible(vp):
				vis_bad += 1
	_check(probes > 0 and near_bad == 0 and seg_bad == 0, "hazard bound buckets equal the full scan (%d point, %d segment of %d probes differ)" % [near_bad, seg_bad, probes])
	_check(mud_bad == 0 and mud_hits > 0, "mud box pre-test leaves _mud_cost unchanged (%d differ, %d probes in mud)" % [mud_bad, mud_hits])
	_check(vis_bad == 0, "cached point visibility equals _point_visible (%d differ)" % vis_bad)
	# Danger profile table: equal to a fresh build, and it follows eprof edits.
	var table_bad: int = 0
	var edits: int = 0
	var changed: int = 0
	for ci2 in sim.controllers.size():
		var b2: TacticianBrain = sim.controllers[ci2]
		var u2: BUnit = _hero_of_team(sim, ci2)
		if b2 == null or u2 == null or b2.eprof.is_empty():
			continue
		var k0 = b2.eprof.keys()[0]
		var eb0: TeamIntel.EnemyBelief = b2.eprof[k0].b
		var p2: Vector2 = eb0.pos.lerp(u2.pos, 0.3)
		var d1: float = b2._danger_raw(u2, p2, 1.0)
		b2._dt_src = {}
		var d2: float = b2._danger_raw(u2, p2, 1.0)
		var pr2: Dictionary = (b2.eprof[k0] as Dictionary).duplicate()
		pr2["w"] = maxf(0.06, float(pr2.w) * 3.0)
		pr2["reach"] = float(pr2.reach) + 2000.0
		b2.eprof[k0] = pr2
		var d3: float = b2._danger_raw(u2, p2, 1.0)
		b2._dt_src = {}
		var d4: float = b2._danger_raw(u2, p2, 1.0)
		edits += 1
		if d1 != d2 or d3 != d4:
			table_bad += 1
		if d3 != d1:
			changed += 1
	_check(edits > 0 and table_bad == 0 and changed > 0, "danger profile table equals a fresh build and follows eprof edits (%d / %d differ, %d changed)" % [table_bad, edits, changed])
	sim.dispose()


# The pre-tick snapshot answers (allies, effective teams, team heroes) equal
# the live ones on every read for 10 s of a 30-hero battle.
func _perf2_snapshot() -> void:
	_install_big(4242)
	BattleSim.ai_snapshot_check = true
	var sim: BattleSim = _sim(_dm_cfg(_players(30, 4242), 4242, "dm_forest_village", 30.0))
	sim.start()
	while sim.tick < 300:
		sim.step()
	BattleSim.ai_snapshot_check = false
	metrics["snapshot_reads"] = sim.ai_snapshot_reads
	_check(sim.ai_snapshot_reads > 1000 and sim.ai_snapshot_mismatch == 0, "pre-tick snapshot equals live answers (%d reads, %d differ)" % [sim.ai_snapshot_reads, sim.ai_snapshot_mismatch])
	sim.dispose()
