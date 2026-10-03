extends SceneTree

# V2 war_machine mini-telemetry (H-AI-war_machine). Headless, read-only.
#
# --write_cases=<path> [--comps=32] [--seed0=207500] [--max_time=150]
#     writes seeded 3v3 elimination cases in tools/balance_runner.gd format:
#     war_machine plus two random partners against three random opponents,
#     six maps in turn, every comp played twice with the sides mirrored.
# --cases=<path> --out=<jsonl> [--shard=i/K]
#     plays the cases with the shipping tactician (as balance_runner does) and
#     records, per case, the war machine's casts per skill and whether each
#     cast reached its purpose, observing only the simulator's public state and
#     its per-tick events.
#
# Purposes: S1 approach -> a basic starts within 1.2 s; S1 escape -> alive
# 2.5 s later; S2 -> at least one missile of the volley hits a unit; S3 -> at
# least 80 damage taken while the guard is up; S4 -> at least one enemy hero
# takes a strip tick. "Stuck": alive, no action, not moving, no basic for 1 s,
# with an enemy hero seen by its team within 500 px but outside basic reach.

const MAPS: Array = ["classic", "ruined_gate", "furnace_basin", "wind_temple", "crossroads", "moon_garden"]
const WM: = "war_machine"

var args: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var at: int = arg.find("=")
			args[arg.substr(2, at - 2)] = arg.substr(at + 1)
	DB.ensure_loaded()
	WarMachineTactics.own_planning = str(args.get("generic", "0")) != "1"
	if args.has("write_cases"):
		_write_cases()
		quit(0)
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(str(args.get("cases", ""))))
	if not data is Array:
		push_error("cases must be a JSON array")
		quit(2)
		return
	var shard: PackedStringArray = str(args.get("shard", "0/1")).split("/")
	var si: int = int(shard[0])
	var sk: int = maxi(1, int(shard[1]))
	var out: FileAccess = FileAccess.open(str(args.get("out", "user://wm_telemetry.jsonl")), FileAccess.WRITE)
	var n: int = 0
	for ci in (data as Array).size():
		if ci % sk != si:
			continue
		var row: Dictionary = _play(data[ci])
		out.store_line(JSON.stringify(row))
		out.flush()
		n += 1
		print("CASE ", row.case_id, " wm_team=", row.wm_team, " winner=", row.winner, " dur=", snappedf(float(row.duration), 0.1), " casts=", row.casts)
	out.close()
	print("TELEMETRY done=", n)
	quit(0)


func _write_cases() -> void:
	var comps: int = int(args.get("comps", "32"))
	var seed0: int = int(args.get("seed0", "207500"))
	var max_time: float = float(args.get("max_time", "150"))
	var pool: Array = []
	for id in DB.ids():
		if str(id) != WM:
			pool.append(str(id))
	var cases: Array = []
	for k in comps:
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = seed0 * 31 + k
		var deck: Array = pool.duplicate()
		for i in range(deck.size() - 1, 0, -1):
			var j: int = rng.randi_range(0, i)
			var tmp = deck[i]
			deck[i] = deck[j]
			deck[j] = tmp
		var mine: Array = [WM, deck[0], deck[1]]
		var theirs: Array = [deck[2], deck[3], deck[4]]
		var map_id: String = MAPS[k % MAPS.size()]
		var s: int = seed0 + k
		cases.append({"id": "wm%02d_b" % k, "blue": mine, "red": theirs, "arena_id": map_id, "seed": s, "max_time": max_time})
		cases.append({"id": "wm%02d_r" % k, "blue": theirs, "red": mine, "arena_id": map_id, "seed": s, "max_time": max_time})
	var f: FileAccess = FileAccess.open(str(args.write_cases), FileAccess.WRITE)
	f.store_string(JSON.stringify(cases, "\t"))
	f.close()
	print("CASES ", cases.size())


func _play(config: Dictionary) -> Dictionary:
	var sim: BattleSim = BattleSim.new(config)
	sim.controllers[0] = AIFactory.make(str(config.get("blue_ai", "tactician")), sim, 0)
	sim.controllers[1] = AIFactory.make(str(config.get("red_ai", "tactician")), sim, 1)
	sim.start()
	var w: BUnit = null
	for u in sim.heroes:
		if u.def.id == WM:
			w = u
	var casts: Dictionary = {"S1": 0, "S2": 0, "S3": 0, "S4": 0}
	var ok: Dictionary = {"S1": 0, "S2": 0, "S3": 0, "S4": 0}
	var s1_kind: Dictionary = {"approach": 0, "escape": 0, "other": 0}
	var charges: Array = []
	var fuel_at_s4: Array = []
	var s4_heroes: Array = []
	var missiles_fired: int = 0
	var missiles_hit: int = 0
	var pending: Array = []
	var alive_t: float = 0.0
	var stuck_t: float = 0.0
	var od_t: float = 0.0
	var cap_t: float = 0.0
	var s4_ready_t: float = 0.0
	var fuel_max: float = 0.0
	var purposes: Dictionary = {}
	var peers: Dictionary = {}
	var tanks_lost: int = 0
	var last_basic: float = -99.0
	var still_since: float = -1.0
	var guard: int = 0
	var limit: int = int(float(config.get("max_time", 150.0)) * 30.0) + 120
	while sim.state == BattleSim.RUNNING and guard < limit:
		sim.step()
		guard += 1
		var now: float = sim.time
		for ev in sim.tick_events:
			var ty: String = str(ev.type)
			var src: int = int(ev.s)
			var tgt: int = int(ev.g)
			if ty == "CAST_STARTED" and src == w.idx and int(ev.get("slot", 0)) > 0:
				var slot: int = int(ev.slot)
				var key: String = "S%d" % slot
				casts[key] = int(casts[key]) + 1
				var row: Dictionary = {"slot": slot, "t": now, "done": false}
				match slot:
					1:
						var purpose: String = str(w.command.get("purpose", ""))
						var kind: String = "approach" if purpose.contains("접근") else ("escape" if purpose.contains("탈출") else "other")
						s1_kind[kind] = int(s1_kind[kind]) + 1
						row["kind"] = kind
					2:
						charges.append(int(ev.get("charge", 0)))
						row["hits"] = 0
					3:
						row["taken"] = 0.0
					4:
						fuel_at_s4.append(float(w.resources.get("fuel", 0.0)))
						row["heroes"] = {}
				pending.append(row)
			elif ty == "PROJECTILE_CREATED" and src == w.idx and _ability_id(ev) == "war_machine_2":
				missiles_fired += 1
			elif ty in ["HEALTH_DAMAGED", "SHIELD_ABSORBED"]:
				var aid: String = _ability_id(ev)
				if src == w.idx and aid == "war_machine_2":
					missiles_hit += 1
					for p in pending:
						if int(p.slot) == 2 and now - float(p.t) <= 4.0:
							p["hits"] = int(p.hits) + 1
				elif src == w.idx and aid == "war_machine_4":
					var victim: BUnit = sim.u_at(tgt)
					if victim and victim.is_hero:
						for p in pending:
							if int(p.slot) == 4 and now - float(p.t) <= 5.0:
								(p.heroes as Dictionary)[tgt] = true
				if tgt == w.idx:
					for p in pending:
						if int(p.slot) == 3 and now - float(p.t) <= 3.1:
							p["taken"] = float(p.taken) + float(ev.get("amount", 0.0)) + float(ev.get("absorbed", 0.0))
				if src == w.idx and bool(ev.get("basic", false)):
					last_basic = now
			elif ty == "ATTACK_DECLARED" and src == w.idx:
				last_basic = now
				for p in pending:
					if int(p.slot) == 1 and str(p.get("kind", "")) == "approach" and now - float(p.t) <= 1.2:
						p["done"] = true
			elif ty == "TANK_DESTROYED" and tgt == w.idx:
				tanks_lost += 1
		# Settle purposes whose window has passed.
		var keep: Array = []
		for p in pending:
			var age: float = now - float(p.t)
			var slot2: int = int(p.slot)
			var window: float = [0.0, 2.5, 4.0, 3.1, 5.0][slot2]
			if age < window and w.alive:
				keep.append(p)
				continue
			var good: bool = false
			match slot2:
				1:
					good = bool(p.done) if str(p.get("kind", "")) == "approach" else (w.alive if str(p.get("kind", "")) == "escape" else bool(p.done))
				2:
					good = int(p.hits) > 0
				3:
					good = float(p.taken) >= 80.0
				4:
					good = not (p.heroes as Dictionary).is_empty()
					s4_heroes.append((p.heroes as Dictionary).size())
			if good:
				ok["S%d" % slot2] = int(ok["S%d" % slot2]) + 1
		pending = keep
		if w.alive:
			alive_t += BattleSim.DT
			if sim.has_status(w, &"overdrive"):
				od_t += BattleSim.DT
			if float(w.resources.get("fuel", 0.0)) >= 9.999:
				cap_t += BattleSim.DT
			fuel_max = maxf(fuel_max, float(w.resources.get("fuel", 0.0)))
			if guard % 15 == 0:
				var pk: String = str(w.command.get("kind", "")) + ":" + str(w.command.get("purpose", "")).get_slice(" →", 0).get_slice(" (", 0)
				purposes[pk] = int(purposes.get(pk, 0)) + 1
			if float(w.resources.get("fuel", 0.0)) >= 7.0 and w.cooldowns[3] <= now and not sim.has_status(w, &"overdrive"):
				s4_ready_t += BattleSim.DT
			var idle: bool = w.action == null and w.motion == null and w.vel.length() < 2.0 and now - last_basic > 1.0
			var want: bool = false
			if idle:
				# Stuck = an order that wants movement or an attack, but nothing happens.
				var kind: String = str(w.command.get("kind", ""))
				if kind in ["basic", "ability"]:
					want = true
				elif kind == "move":
					want = (w.command.get("goal", w.pos) as Vector2).distance_to(w.pos) > 40.0
			if idle and want:
				if still_since < 0.0:
					still_since = now
				elif now - still_since >= 1.0:
					stuck_t += BattleSim.DT
			else:
				still_since = -1.0
	var r: Dictionary = sim.result()
	for ur in r.units:
		peers[str(ur.id) + ("" if int(ur.team) == w.team else "*")] = [snappedf(float(ur.damage), 1.0), int(ur.deaths)]
	var row_out: Dictionary = {"case_id": config.get("id", ""), "arena": config.get("arena_id", ""), "seed": config.get("seed", 0),
		"wm_team": w.team, "winner": r.winner, "reason": r.reason, "duration": r.duration,
		"wm_win": int(r.winner) == w.team, "draw": int(r.winner) == 2, "timeout": str(r.reason) == "time_limit",
		"alive_t": alive_t, "casts": casts, "ok": ok, "s1_kind": s1_kind, "charges": charges, "missiles_fired": missiles_fired,
		"missiles_hit": missiles_hit, "fuel_at_s4": fuel_at_s4, "s4_heroes": s4_heroes, "stuck_t": stuck_t, "overdrive_t": od_t,
		"fuel_cap_t": cap_t, "fuel_max": fuel_max, "s4_ready_t": s4_ready_t, "tanks_lost": tanks_lost, "wm_damage": w.st_damage, "wm_deaths": w.st_deaths,
		"purposes": purposes, "peers": peers, "signature": JSON.stringify([r.winner, r.duration]).sha256_text()}
	sim.dispose()
	return row_out


func _ability_id(ev: Dictionary) -> String:
	var ab = ev.get("ability")
	return (ab as Defs.AbilityDef).id if ab is Defs.AbilityDef else ""
