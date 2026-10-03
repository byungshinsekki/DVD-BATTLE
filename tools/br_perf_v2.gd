extends SceneTree

# V2 battleground-scale performance tool (B-PERF). Headless, read-only for
# project files and user data. Built from the zz_work/v2probe/br probe.
#
# Timing run (30 AI heroes on the synthetic 2x2 deathmatch map, 7200x4400):
#   <godot> --headless --path <project> --script res://tools/br_perf_v2.gd -- \
#       --players=30 --secs=60 --map=big|dm --teams=1 --seed=4242 [--aiprof=1]
#   Prints mean / p50 / p95 / p99 / max tick ms, the simulator's per-section
#   profile (BattleSim._step_profiled) and, with --aiprof=1, AI sub-sections
#   from timing wrappers (they add some overhead of their own).
#   --teams=2|3 groups heroes into duos / trios with the team brain (cost probe).
#   --vis=old runs the exhaustive visibility pass (BattleSim.vis_exhaustive).
#
# Determinism signatures for existing modes (compare two builds):
#   ... --script res://tools/br_perf_v2.gd -- --sig=1 [--secs=60]
#   Runs fixed 3v3 / 5v5 / conquest / 12-player deathmatch cases and prints one
#   SHA-256 per case over every tick's unit state, visibility and events.

const BrMap := preload("res://tools/br_perf_v2/br_map.gd")
const P := preload("res://tools/br_perf_v2/br_prof.gd")
const ProfBrain := preload("res://tools/br_perf_v2/br_prof_brain.gd")

var args: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _mem() -> float:
	return OS.get_static_memory_usage() / 1048576.0


func _stats(arr: Array) -> String:
	if arr.is_empty():
		return "n=0"
	var s: Array = arr.duplicate()
	s.sort()
	var total: float = 0.0
	for v in s:
		total += float(v)
	var n: int = s.size()
	return "n=%d mean=%.3f p50=%.3f p95=%.3f p99=%.3f max=%.3f" % [n, total / n, float(s[n / 2]), float(s[int(n * 0.95)]), float(s[mini(n - 1, int(n * 0.99))]), float(s[n - 1])]


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var at: int = arg.find("=")
			args[arg.substr(2, at - 2)] = arg.substr(at + 1)
	DB.ensure_loaded()
	if int(args.get("sig", 0)) == 1:
		_signatures(float(args.get("secs", 60)))
	elif str(args.get("part", "")) == "nav":
		_nav_bench(int(args.get("seed", 4242)))
	else:
		_timing(str(args.get("map", "big")), int(args.get("players", 30)), float(args.get("secs", 60)), int(args.get("seed", 4242)), int(args.get("teams", 1)))
	quit(0)


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


# Registers the synthetic big map as the cached deathmatch arena for this seed,
# so a deathmatch config on "dm_forest_village" plays on it.
static func install_big_map(seed_v: int) -> Arena:
	var big: Dictionary = BrMap.build(seed_v)
	var a: Arena = Arena.from_data(big)
	a.shared = true
	var key: String = "dm_forest_village:%d" % seed_v
	DB.dm_cache[key] = a
	DB.dm_cache_order.append(key)
	return a


func _timing(map_kind: String, n: int, secs: float, seed_v: int, k_team: int) -> void:
	var players: Array = _players(n, seed_v)
	var aiprof: bool = int(args.get("aiprof", 0)) == 1
	print("PERF map=%s players=%d secs=%.0f seed=%d teams=%d aiprof=%s ids=%s" % [map_kind, n, secs, seed_v, k_team, str(aiprof), str(players)])
	var m0: float = _mem()
	var t0: int = Time.get_ticks_usec()
	if map_kind == "big":
		install_big_map(seed_v)
	var t_map: float = (Time.get_ticks_usec() - t0) / 1000.0
	if str(args.get("vis", "")) == "old":
		(load("res://scripts/core/sim.gd") as GDScript).set("vis_exhaustive", true)
	# --snapcheck=1: compare every pre-tick snapshot read with the live answer.
	var snapcheck: bool = int(args.get("snapcheck", 0)) == 1
	(load("res://scripts/core/sim.gd") as GDScript).set("ai_snapshot_check", snapcheck)
	t0 = Time.get_ticks_usec()
	var sim: BattleSim = BattleSim.new({"ruleset": "deathmatch", "arena_id": "dm_forest_village", "players": players, "seed": seed_v, "max_time": secs + 5.0, "kill_target": 999})
	var t_sim: float = (Time.get_ticks_usec() - t0) / 1000.0
	if k_team > 1:
		# Cost probe: group heroes into teams of k (duo / trio) with the team
		# brain and put teammates next to their leader.
		for u in sim.heroes:
			u.team = u.idx / k_team
			if u.idx % k_team != 0:
				var lead: BUnit = sim.heroes[u.idx - u.idx % k_team]
				u.pos = sim.arena.resolve_circle(lead.pos + Vector2(60.0 * (u.idx % k_team), 40.0), u.base_radius)
				u.prev_pos = u.pos
				u.spawn_pos = u.pos
		sim.team_count = (sim.heroes.size() + k_team - 1) / k_team
		sim.controllers = []
		sim.controllers.resize(sim.team_count)
	t0 = Time.get_ticks_usec()
	for t in sim.team_count:
		if k_team > 1:
			sim.controllers[t] = TacticianBrain.new(sim, t)
		else:
			sim.controllers[t] = ProfBrain.new(sim, t) if aiprof else AIFactory.make("tactician", sim, t)
	var t_ctl: float = (Time.get_ticks_usec() - t0) / 1000.0
	t0 = Time.get_ticks_usec()
	sim.start()
	var t_start: float = (Time.get_ticks_usec() - t0) / 1000.0
	var nav_keys0: int = Navigator._cache.size()
	print("PERF setup: map_ms=%.1f sim_new_ms=%.1f controllers_ms=%.1f start_ms=%.1f mem_MB=%.1f (delta %.1f) arena=%dx%d nav_grids=%d" % [t_map, t_sim, t_ctl, t_start, _mem(), _mem() - m0, int(sim.arena.width), int(sim.arena.height), nav_keys0])
	sim.profiling = true
	P.reset()
	var ticks: Array = []
	var slow: Array = []
	var wall0: int = Time.get_ticks_usec()
	var nonfinite: int = 0
	var worst: Array = []   # [ms, "t=..", sections] of the 5 slowest ticks
	while sim.state == BattleSim.RUNNING and sim.time < secs:
		var snap: Dictionary = sim.prof.duplicate()
		var t1: int = Time.get_ticks_usec()
		sim.step()
		var dt_ms: float = (Time.get_ticks_usec() - t1) / 1000.0
		ticks.append(dt_ms)
		if dt_ms > 40.0 and slow.size() < 12:
			slow.append("t=%.2f %.1fms" % [sim.time, dt_ms])
		if worst.size() < 5 or dt_ms > float(worst[worst.size() - 1][0]):
			var parts: Array = []
			for k in sim.prof:
				var dd: float = (int(sim.prof[k]) - int(snap.get(k, 0))) / 1000.0
				if dd >= 2.0:
					parts.append("%s=%.1f" % [k, dd])
			worst.append([dt_ms, "t=%.2f" % sim.time, ", ".join(parts)])
			worst.sort_custom(func(x, y): return float(x[0]) > float(y[0]))
			if worst.size() > 5:
				worst.pop_back()
		if sim.tick % 30 == 0:
			for u in sim.units:
				if not is_finite(u.hp) or not u.pos.is_finite():
					nonfinite += 1
	var wall: float = (Time.get_ticks_usec() - wall0) / 1000000.0
	print("PERF ticks ms: %s" % _stats(ticks))
	print("PERF wall=%.1fs sim=%.1fs realtime_factor=%.2fx mem_MB=%.1f nonfinite=%d nav_grids_after=%d (built mid-match: %d)" % [wall, sim.time, sim.time / maxf(0.001, wall), _mem(), nonfinite, Navigator._cache.size(), Navigator._cache.size() - nav_keys0])
	print("PERF slow ticks: %s" % str(slow))
	for w in worst:
		print("PERF worst tick %s %.1fms: %s" % [w[1], float(w[0]), w[2]])
	var kills: int = 0
	if sim.deathmatch:
		for t in sim.deathmatch.kills.size():
			kills += sim.deathmatch.kills[t]
	var dec: int = 0
	for u in sim.heroes:
		dec += u.decisions
	print("PERF kills=%d decisions=%d (%.2f /hero/s)" % [kills, dec, dec / maxf(1.0, n * sim.time)])
	var nt: float = maxf(1.0, ticks.size())
	var keys: Array = sim.prof.keys()
	keys.sort_custom(func(x, y): return int(sim.prof[x]) > int(sim.prof[y]))
	for k in keys:
		print("PROF sim.%s ms/tick=%.3f" % [k, int(sim.prof[k]) / 1000.0 / nt])
	if aiprof:
		var ks: Array = P.T.keys()
		ks.sort_custom(func(x, y): return int(P.T[x]) > int(P.T[y]))
		for k in ks:
			print("PROF %s ms/tick=%.3f calls/tick=%.2f us/call=%.1f" % [k, int(P.T[k]) / 1000.0 / nt, int(P.N[k]) / nt, float(P.T[k]) / maxf(1.0, float(P.N[k]))])
	var nav_script: GDScript = load("res://scripts/ai/navigator.gd")
	if nav_script.get("astar_calls") != null:
		print("PERF nav A* searches (path memo misses) per tick=%.2f" % [int(nav_script.get("astar_calls")) / nt])
	var extra: Dictionary = sim.get("perf_counters") if "perf_counters" in sim else {}
	for k in extra:
		print("PERF counter %s=%s (per tick %.2f)" % [k, str(extra[k]), float(extra[k]) / nt])
	var route_hits: int = 0
	var steer_hits: int = 0
	for c in sim.controllers:
		if c != null and "lod_route_hits" in c:
			route_hits += int(c.get("lod_route_hits"))
		if c != null and "lod_steer_hits" in c:
			steer_hits += int(c.get("lod_steer_hits"))
	print("PERF counter lod_route_hits=%d (per tick %.2f)" % [route_hits, route_hits / nt])
	print("PERF counter lod_steer_hits=%d (per tick %.2f)" % [steer_hits, steer_hits / nt])
	if snapcheck:
		print("PERF snapshot check: mismatches=%d" % int(sim.get("ai_snapshot_mismatch")))
	sim.dispose()


# ------------------------------------------------------------ nav / queries

# --part=nav: grid build per bucket, component count and query costs on the
# big map (cold and warm next_waypoint, long segment tests, forest lookups).
func _nav_bench(seed_v: int) -> void:
	var a: Arena = install_big_map(seed_v)
	print("NAV map %dx%d obstacles=%d forests=%d hazards=%d" % [int(a.width), int(a.height), a.obs_count, a.forest_x.size(), a.hazards.size()])
	for b in [12.0, 18.0, 26.0, 28.0]:
		var t0: int = Time.get_ticks_usec()
		var nav: Navigator = Navigator.for_arena(a, b)
		var comps: int = int(nav.get("component_count")) if "component_count" in nav else -1
		print("NAV bucket=%d cells=%d build_ms=%.1f components=%d" % [int(b), nav.cols * nav.rows, (Time.get_ticks_usec() - t0) / 1000.0, comps])
	var nav18: Navigator = Navigator.for_arena(a, 18.0)
	if nav18.has_method("debug_build_mismatch"):
		print("NAV fast build vs per-cell reference: mismatched cells=%d" % int(nav18.call("debug_build_mismatch")))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var pairs: Array = []
	while pairs.size() < 200:
		var p := Vector2(rng.randf_range(a.min_x + 40, a.max_x - 40), rng.randf_range(a.min_y + 40, a.max_y - 40))
		var q := Vector2(rng.randf_range(a.min_x + 40, a.max_x - 40), rng.randf_range(a.min_y + 40, a.max_y - 40))
		if a.is_walkable(p, 18.0) and a.is_walkable(q, 18.0):
			pairs.append([p, q])
	var cold: Array = []
	var warm: Array = []
	var seg: Array = []
	for pr in pairs:
		var t1: int = Time.get_ticks_usec()
		nav18.next_waypoint(pr[0], pr[1], 18.0, 0.0, 0.0, 0.0, false)
		cold.append((Time.get_ticks_usec() - t1) / 1000.0)
		t1 = Time.get_ticks_usec()
		nav18.next_waypoint(pr[0], pr[1], 18.0, 0.0, 0.0, 0.0, false)
		warm.append((Time.get_ticks_usec() - t1) / 1000.0)
		t1 = Time.get_ticks_usec()
		a.segment_blocked(pr[0], pr[1], 20.0, Arena.MASK_UNITS)
		seg.append((Time.get_ticks_usec() - t1) / 1000.0)
	print("NAV next_waypoint cold ms: %s" % _stats(cold))
	print("NAV next_waypoint warm ms: %s" % _stats(warm))
	print("NAV segment_blocked(long) ms: %s" % _stats(seg))
	var t2: int = Time.get_ticks_usec()
	for pr in pairs:
		a.forest_at(pr[0])
	print("ARENA forest_at us/call=%.2f" % ((Time.get_ticks_usec() - t2) / float(pairs.size())))
	t2 = Time.get_ticks_usec()
	for pr in pairs:
		a.forest_occludes(pr[0], pr[0] + (pr[1] - pr[0]).limit_length(560.0))
	print("ARENA forest_occludes(<=560) us/call=%.2f" % ((Time.get_ticks_usec() - t2) / float(pairs.size())))
	t2 = Time.get_ticks_usec()
	for pr in pairs:
		a.hazard_penalty(pr[0], 3.0, 18.0)
	print("ARENA hazard_penalty us/call=%.2f" % ((Time.get_ticks_usec() - t2) / float(pairs.size())))
	Navigator.forget(a)


# ------------------------------------------------------------ signatures

func _sig_cases() -> Array:
	var out: Array = []
	var ids: Array = DB.ids()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261001
	var pick := func(k: int) -> Array:
		var pool: Array = ids.duplicate()
		var r: Array = []
		for i in k:
			r.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
		return r
	var elim: Array = []
	for a in DB.arenas_for("elimination"):
		elim.append((a as Arena).id)
	var ctl: Array = []
	for a in DB.arenas_for("control"):
		ctl.append((a as Arena).id)
	for i in 3:
		var t: Array = pick.call(6)
		out.append({"id": "e3_%d" % i, "ruleset": "elimination", "arena_id": elim[(i * 3) % elim.size()], "blue": t.slice(0, 3), "red": t.slice(3, 6), "seed": 5100 + i})
	for i in 2:
		var t: Array = pick.call(10)
		out.append({"id": "e5_%d" % i, "ruleset": "elimination", "arena_id": elim[(i * 5 + 1) % elim.size()], "blue": t.slice(0, 5), "red": t.slice(5, 10), "seed": 5200 + i})
	if not ctl.is_empty():
		var t2: Array = pick.call(10)
		out.append({"id": "ctl5", "ruleset": "control", "arena_id": ctl[0], "blue": t2.slice(0, 5), "red": t2.slice(5, 10), "seed": 5300})
	for i in 2:
		out.append({"id": "dm12_%d" % i, "ruleset": "deathmatch", "arena_id": DeathmatchMapData.ORDER[i % DeathmatchMapData.ORDER.size()], "players": pick.call(12), "seed": 5400 + i, "kill_target": 15})
	out.append({"id": "dm8", "ruleset": "deathmatch", "arena_id": DeathmatchMapData.ORDER[2 % DeathmatchMapData.ORDER.size()], "players": pick.call(8), "seed": 5500, "kill_target": 15})
	return out


func _signatures(secs: float) -> void:
	var only: String = str(args.get("case", ""))
	for c in _sig_cases():
		var cfg: Dictionary = c
		if only != "" and str(cfg.id) != only:
			continue
		cfg["max_time"] = minf(secs, 150.0) if str(cfg.ruleset) == "elimination" else secs
		var sim: BattleSim = BattleSim.new(cfg)
		for t in sim.team_count:
			sim.controllers[t] = AIFactory.make("tactician", sim, t)
		sim.start()
		var h := HashingContext.new()
		h.start(HashingContext.HASH_SHA256)
		var wall0: int = Time.get_ticks_usec()
		while sim.state == BattleSim.RUNNING:
			sim.step()
			var row := PackedFloat64Array()
			row.append(sim.tick)
			row.append(sim.tick_events.size())
			for u in sim.units:
				row.append(u.pos.x)
				row.append(u.pos.y)
				row.append(u.hp)
				row.append(1.0 if u.alive else 0.0)
				row.append(u.next_decision_at)
			h.update(row.to_byte_array())
			for t in sim.team_count:
				if not (sim.seen[t] as PackedByteArray).is_empty():
					h.update(sim.seen[t])
			var ev: String = ""
			for e in sim.tick_events:
				ev += "%s:%d:%d;" % [str(e.type), int(e.get("s", -1)), int(e.get("g", -1))]
			if not ev.is_empty():
				h.update(ev.to_utf8_buffer())
			if sim.tick > int(sim.max_time * 30.0) + 10:
				break
		var digest: String = h.finish().hex_encode()
		print("SIG %s %s ticks=%d winner=%d reason=%s wall=%.1fs" % [str(cfg.id), digest.substr(0, 24), sim.tick, sim.winner, sim.finish_reason, (Time.get_ticks_usec() - wall0) / 1000000.0])
		sim.dispose()
