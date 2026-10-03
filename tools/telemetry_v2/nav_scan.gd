extends SceneTree

# V2 navigation telemetry (read-only observer). Runs shipping-AI battles
# (AIFactory "tactician", exactly as BattleRunner) and records, per battle:
#  - ring: per hero time outside the closing ring, ring damage, outside
#    episodes (start, duration, pos, purpose at start, cmd kinds while out,
#    cc / motion / stuck ticks while out);
#  - stuck episodes (ai_probe_153 definition: 30 ticks of an active move /
#    approach order with < 2 px net displacement);
#  - portal / jump-pad trips: against the goal (walk length landing->goal >
#    takeoff->goal + 40) and the cause at the trigger tick (motion kind before
#    the tick, burst displacement, dodge active, forced steer (charm/fear/
#    taunt), deliberately taken link, purpose).
# Args (after --):
#   --maps=a,b|all --n=8 --size=3 --seed0=163100 --max_time=150 --shard=i/K
#     (same seeded deck as tools/ai_probe_153.gd -> identical battles)
#   or --cases=map:seed:size:h1,h2,..;...
#   --out=<abs jsonl> --ai=tactician|res://path/to/brain.gd
# Legacy fields retain their meaning; censored_stuck records episodes open on
# death/end, which the original scratch probe omitted. No sim/AI mutation.

const DT: float = 1.0 / 30.0
const HARD: Array = [&"stun", &"root", &"airborne", &"suppression", &"sleep"]

var args: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--"):
			var body: String = arg.substr(2)
			var at: int = body.find("=")
			if at >= 0:
				args[body.substr(0, at)] = body.substr(at + 1)
			else:
				args[body] = "1"
	DB.ensure_loaded()
	var plan: Array = []
	var max_time: float = float(args.get("max_time", 150.0))
	if args.has("cases"):
		for c in str(args.cases).split(";", false):
			var p: PackedStringArray = c.split(":")
			plan.append({"index": plan.size(), "map": p[0], "seed": int(p[1]), "size": int(p[2]), "comp": Array(p[3].split(","))})
	else:
		var mode: String = "elimination"
		var maps: Array = DB.arenas_for(mode).map(func(a: Arena): return a.id) if str(args.get("maps", "all")) == "all" else Array(str(args.maps).split(",", false))
		var n: int = int(args.get("n", 4))
		var size: int = int(args.get("size", 3))
		var seed0: int = int(args.get("seed0", 153000))
		var deck_rng: RandomNumberGenerator = RandomNumberGenerator.new()
		deck_rng.seed = hash([seed0, mode, size, maps, n])
		var ids: Array = DB.ids()
		var deck: Array = []
		var per_battle: int = size * 2
		for mi in maps.size():
			for k in n:
				var picked: Array = []
				while picked.size() < per_battle:
					if deck.size() < per_battle * 2:
						var fresh: Array = ids.duplicate()
						for i in range(fresh.size() - 1, 0, -1):
							var j: int = deck_rng.randi_range(0, i)
							var tmp = fresh[i]
							fresh[i] = fresh[j]
							fresh[j] = tmp
						fresh.append_array(deck)
						deck = fresh
					var pos: int = deck.size() - 1
					while picked.has(deck[pos]):
						pos -= 1
					picked.append(deck[pos])
					deck.remove_at(pos)
				plan.append({"index": plan.size(), "map": str(maps[mi]), "seed": seed0 + mi * 1000 + k * 17, "size": size, "comp": picked})
	var shard: PackedStringArray = str(args.get("shard", "0/1")).split("/")
	var si: int = int(shard[0])
	var sk: int = maxi(1, int(shard[1]))
	var out: FileAccess = FileAccess.open(str(args.get("out", "user://scan.jsonl")), FileAccess.WRITE)
	if out == null:
		push_error("cannot write navigation telemetry output")
		quit(2)
		return
	var t0: int = Time.get_ticks_msec()
	for job in plan:
		if int(job.index) % sk != si:
			continue
		var row: Dictionary = _battle(str(job.map), int(job.seed), int(job.size), job.comp, max_time)
		row["index"] = job.index
		out.store_line(JSON.stringify(row))
		out.flush()
		print("SCAN ", job.map, " seed=", job.seed, " winner=", row.winner, " t=", row.duration, " ring_out_s=", row.ring_out_s,
			" ring_dmg=", row.ring_dmg, " trips=", row.trips.size(), " stuck=", row.stuck.size(), " wall=", row.wall)
	out.close()
	print("SCAN_DONE ", (Time.get_ticks_msec() - t0) / 1000.0)
	quit(0)


func _battle(map_id: String, seed_v: int, size: int, comp: Array, max_time: float) -> Dictionary:
	var w0: int = Time.get_ticks_usec()
	var sim: BattleSim = BattleSim.new({"seed": seed_v, "arena_id": map_id, "max_time": max_time, "ruleset": "elimination",
		"blue": comp.slice(0, size), "red": comp.slice(size, size * 2)})
	for t in 2:
		sim.controllers[t] = AIFactory.make(str(args.get("ai", "tactician")), sim, t)
	sim.start()
	var ring: Dictionary = {}
	for h in sim.arena.hazards:
		if str(h.type) == "closing_ring":
			ring = h
	var navs: Dictionary = {}
	var H: Dictionary = {}
	for u in sim.heroes:
		H[u.idx] = {"id": u.def.id, "team": u.team, "out_s": 0.0, "ring_dmg": 0.0, "ep": null, "eps": [], "hist": [], "streak": 0,
			"stuck_on": false, "stuck_t": 0.0, "stuck_pos": Vector2.ZERO, "stuck_purpose": ""}
	var trips: Array = []
	var stuck: Array = []
	var censored_stuck: Array = []
	var pre: Dictionary = {}
	var taking_seen: Dictionary = {}   # "idx|hazard" -> last time the brain walked into it on purpose
	var last_motion: Dictionary = {}   # idx -> [kind, time] of the latest forced / self motion seen before a tick
	while sim.state == BattleSim.RUNNING:
		pre.clear()
		for u in sim.heroes:
			var cd: Dictionary = u.command
			var goal: Vector2 = cd.get("goal", cd.get("pos", u.pos))
			var tu: BUnit = sim.u_at(int(cd.get("target", -1)))
			if tu:
				goal = tu.pos
			if u.motion != null:
				last_motion[u.idx] = [u.motion.kind, sim.time]
			pre[u.idx] = {"goal": goal, "motion": (u.motion.kind if u.motion != null else ""), "pos": u.pos, "alive": u.alive,
				"purpose": str(cd.get("purpose", cd.get("kind", ""))), "kind": str(cd.get("kind", ""))}
		sim.step()
		for ev: Dictionary in sim.tick_events:
			var typ: String = str(ev.type)
			if typ == "ENV_HIT" and str(ev.get("hazard_type", "")) == "closing_ring" and H.has(int(ev.g)):
				H[int(ev.g)].ring_dmg += float(ev.get("amount", 0.0)) + float(ev.get("absorbed", 0.0))
			elif typ == "ENV_PORTAL" or typ == "ENV_JUMP":
				var u: BUnit = sim.u_at(int(ev.g))
				if u == null or not pre.has(u.idx):
					continue
				var r: float = sim.radius(u)
				var key: int = int(round(r))
				if not navs.has(key):
					navs[key] = Navigator.for_arena(sim.arena, r, sim.arena.all_gates_open_bits() if sim.arena.has_gates() else -1)
				var nav: Navigator = navs[key]
				var p0: Dictionary = pre[u.idx]
				var from: Vector2 = ev.get("from", u.pos)
				var to: Vector2 = ev.get("to", u.pos)
				var before: float = nav.path_length(from, p0.goal, r, 0.0, 0.0, 0.0, false)
				var after: float = nav.path_length(to, p0.goal, r, 0.0, 0.0, 0.0, false)
				var b: TacticianBrain = sim.controllers[sim.eteam(u)] as TacticianBrain
				var m: Dictionary = b.mem.get(u.idx, {}) if b else {}
				var dodging: bool = absf(float(m.get("dodging", -9.0)) - sim.time) < 1e-6
				var taking: String = str(b._taking_link.get(u.idx, "")) if b else ""
				var disp: float = (p0.pos as Vector2).distance_to(from)
				var burst: bool = disp > sim.stat(u, &"moveSpeed") * DT * 1.6 + 1.0
				var forced: String = ""
				for st in u.statuses:
					if st.type in [&"charm", &"fear", &"taunt"] and st.end > sim.time - DT:
						forced = str(st.type)
				var since: float = sim.time - float(taking_seen.get("%d|%s" % [u.idx, str(ev.get("hazard", ""))], -99.0))
				var cause: String = "walk"
				if str(p0.motion) != "":
					cause = "motion:" + str(p0.motion)
				elif burst:
					cause = "burst"
				elif forced != "":
					cause = "forced:" + forced
				elif dodging:
					cause = "dodge"
				elif taking == str(ev.get("hazard", "")):
					cause = "taken"
				elif since <= 1.0:
					cause = "dropped_commit"
				elif last_motion.has(u.idx) and sim.time - float(last_motion[u.idx][1]) <= 0.6:
					cause = "after_motion:" + str(last_motion[u.idx][0])
				trips.append({"t": snappedf(sim.time, 0.01), "hero": u.def.id, "team": u.team, "type": typ, "hazard": str(ev.get("hazard", "")),
					"from": [snappedf(from.x, 0.1), snappedf(from.y, 0.1)], "to": [snappedf(to.x, 0.1), snappedf(to.y, 0.1)],
					"goal": [snappedf((p0.goal as Vector2).x, 0.1), snappedf((p0.goal as Vector2).y, 0.1)],
					"before": snappedf(before, 1.0), "after": snappedf(after, 1.0), "against": after > before + 40.0,
					"cause": cause, "dodging": dodging, "taking": taking, "motion": p0.motion, "burst": burst, "disp": snappedf(disp, 0.1),
					"purpose": p0.purpose, "kind": p0.kind, "since_taking": snappedf(since, 0.01), "speed": snappedf(u.vel.length(), 0.1)})
		for c in sim.controllers:
			if c is TacticianBrain:
				for k in (c as TacticianBrain)._taking_link:
					taking_seen["%d|%s" % [int(k), str((c as TacticianBrain)._taking_link[k])]] = sim.time
		for u in sim.heroes:
			var h: Dictionary = H[u.idx]
			if not u.alive:
				if h.stuck_on:
					censored_stuck.append(_open_stuck(sim, u, h, "death"))
					h.stuck_on = false
				if h.ep != null:
					h.ep.dur = snappedf(sim.time - float(h.ep.t), 0.01)
					h.ep.dmg = snappedf(h.ring_dmg - float(h.ep.dmg0), 0.1)
					h.ep["died"] = true
					h.eps.append(h.ep)
					h.ep = null
				continue
			# ---- ring
			if not ring.is_empty():
				var outside: bool = Arena.ring_outside(ring, u.pos, sim.time, 0.0)
				if outside:
					h.out_s += DT
					if h.ep == null:
						var cpos: Vector2 = ring.center
						h.ep = {"t": snappedf(sim.time, 0.01), "pos": [snappedf(u.pos.x, 0.1), snappedf(u.pos.y, 0.1)],
							"d": snappedf(u.pos.distance_to(cpos), 0.1), "ring_r": snappedf(Arena.ring_radius_at(ring, sim.time), 0.1),
							"purpose0": str(pre[u.idx].purpose), "kinds": {}, "purposes": {}, "cc": 0, "motion": 0, "still": 0, "inward_ticks": 0, "ticks": 0,
							"dmg0": h.ring_dmg, "enemy_near": 0}
					var e: Dictionary = h.ep
					e.ticks += 1
					var k: String = str(pre[u.idx].kind)
					e.kinds[k] = int(e.kinds.get(k, 0)) + 1
					var pp: String = str(pre[u.idx].purpose)
					e.purposes[pp] = int(e.purposes.get(pp, 0)) + 1
					if sim.has_any(u, HARD) or sim.is_crowd_controlled(u):
						e.cc += 1
					if str(pre[u.idx].motion) != "":
						e.motion += 1
					var c2: Vector2 = ring.center
					var dprev: float = (pre[u.idx].pos as Vector2).distance_to(c2)
					var dnow: float = u.pos.distance_to(c2)
					if dnow < dprev - 0.3:
						e.inward_ticks += 1
					if (pre[u.idx].pos as Vector2).distance_to(u.pos) < 0.3:
						e.still += 1
					for o in sim.heroes:
						if o.alive and o.team != u.team and o.pos.distance_to(u.pos) < 260.0:
							e.enemy_near += 1
							break
				elif h.ep != null:
					h.ep.dur = snappedf(sim.time - float(h.ep.t), 0.01)
					h.ep.dmg = snappedf(h.ring_dmg - float(h.ep.dmg0), 0.1)
					h.ep.end_pos = [snappedf(u.pos.x, 0.1), snappedf(u.pos.y, 0.1)]
					h.eps.append(h.ep)
					h.ep = null
			# ---- stuck (ai_probe_153 definition)
			var wants: bool = false
			if u.action == null and u.motion == null and not sim.has_any(u, HARD) and not sim.is_crowd_controlled(u) and u.chamber == "" and sim.stat(u, &"moveSpeed") > 5.0:
				var cmd2: Dictionary = u.command
				var k2: String = str(cmd2.get("kind", "move"))
				if k2 == "move":
					var g2: Vector2 = cmd2.get("goal", u.pos)
					wants = g2.distance_to(u.pos) > 24.0
				elif k2 in ["ability", "basic"]:
					var tt: BUnit = sim.u_at(int(cmd2.get("target", -1)))
					var tp: Vector2 = tt.pos if tt else cmd2.get("pos", u.pos)
					var need: float = float(cmd2.get("need", 60.0))
					wants = need > 1.0 and u.pos.distance_to(tp) > need * 0.95 + 10.0
			var hist: Array = h.hist
			hist.append(u.pos)
			if hist.size() > 31:
				hist.pop_front()
			h.streak = int(h.streak) + 1 if wants else 0
			var stuck_now: bool = int(h.streak) >= 30 and hist.size() >= 31 and (hist[0] as Vector2).distance_to(u.pos) < 2.0
			if stuck_now and not h.stuck_on:
				h.stuck_t = sim.time
				h.stuck_pos = u.pos
				h.stuck_purpose = str(u.command.get("purpose", u.command.get("kind", "")))
			if not stuck_now and h.stuck_on:
				stuck.append({"hero": h.id, "team": h.team, "t": snappedf(float(h.stuck_t), 0.1), "dur": snappedf(sim.time - float(h.stuck_t) + 1.0, 0.1),
					"pos": [snappedf((h.stuck_pos as Vector2).x, 0.1), snappedf((h.stuck_pos as Vector2).y, 0.1)], "purpose": h.stuck_purpose,
					"wall": snappedf(sim.arena.distance_to_wall(h.stuck_pos) - sim.radius(u), 0.1)})
			h.stuck_on = stuck_now
	var heroes: Array = []
	var out_total: float = 0.0
	var dmg_total: float = 0.0
	for u in sim.heroes:
		var h: Dictionary = H[u.idx]
		if h.stuck_on:
			censored_stuck.append(_open_stuck(sim, u, h, "match_end"))
		if h.ep != null:
			h.ep.dur = snappedf(sim.time - float(h.ep.t), 0.01)
			h.ep.dmg = snappedf(h.ring_dmg - float(h.ep.dmg0), 0.1)
			h.ep["open"] = true
			h.eps.append(h.ep)
		for e in h.eps:
			e.erase("dmg0")
		out_total += float(h.out_s)
		dmg_total += float(h.ring_dmg)
		heroes.append({"id": h.id, "team": h.team, "r": sim.radius(u), "ms": sim.stat(u, &"moveSpeed"), "out_s": snappedf(float(h.out_s), 0.01),
			"ring_dmg": snappedf(float(h.ring_dmg), 0.1), "eps": h.eps, "alive": u.alive})
	var row: Dictionary = {"map": map_id, "seed": seed_v, "size": size, "comp": comp, "winner": sim.winner, "reason": str(sim.finish_reason),
		"duration": snappedf(sim.time, 0.01), "ring_out_s": snappedf(out_total, 0.1), "ring_dmg": snappedf(dmg_total, 0.1),
		"heroes": heroes, "trips": trips, "stuck": stuck, "censored_stuck": censored_stuck,
		"arena_bounds": [sim.arena.min_x, sim.arena.min_y, sim.arena.max_x, sim.arena.max_y],
		"arena_size": [sim.arena.width, sim.arena.height], "wall": snappedf((Time.get_ticks_usec() - w0) / 1e6, 0.1)}
	sim.dispose()
	return row


func _open_stuck(sim: BattleSim, u: BUnit, h: Dictionary, ended_by: String) -> Dictionary:
	var p: Vector2 = h.stuck_pos
	return {"hero": h.id, "team": h.team, "t": snappedf(float(h.stuck_t), 0.1),
		"dur": snappedf(sim.time - float(h.stuck_t) + 1.0, 0.1),
		"pos": [snappedf(p.x, 0.1), snappedf(p.y, 0.1)], "purpose": h.stuck_purpose,
		"wall": snappedf(sim.arena.distance_to_wall(p) - sim.radius(u), 0.1), "ended_by": ended_by}
