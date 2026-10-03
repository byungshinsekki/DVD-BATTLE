extends SceneTree

# V2 토르케마다 (torquemada) mini-telemetry (H-AI-torquemada). Plays the cases
# of a balance_runner JSON file exactly like tools/balance_runner.gd
# (tactician on both sides, same configs, so the same battles) and records,
# from per-tick events and public sim state only, torquemada's casts per skill,
# the casts that achieved their purpose (S1/S3 cleansed someone, S2 rooted,
# S3 pushed an enemy hero), the opportunities he had and time spent stuck.
# One JSON line per case, then a SUMMARY line.
#   godot --headless --path . --script res://tools/torquemada_telemetry_v2.gd -- --cases=<json> --output=<jsonl> [--mask=111]
# --mask holds a slot on cooldown where it has a 0 (ablation: --mask=011 plays
# without S1). tools/torquemada_telemetry_v2_cases.json holds the wave 2 set:
# 36 seeded 3v3 elimination matchups (torquemada + 2 random partners vs 3
# random opponents from the 22 V1 heroes) on 6 maps, each mirrored by side
# (72 cases). The same file runs unchanged through tools/balance_runner.gd.

const ID: = "torquemada"
const COOLDOWN: = [13.0, 11.0, 17.0]
const HARD_LOCK: Array = [&"stun", &"airborne", &"suppression", &"sleep", &"charm", &"taunt", &"fear"]
const CLEANSE_CC: Array = ["stun", "root", "airborne", "suppression", "sleep", "charm", "taunt", "fear", "silence", "disarm", "grounded"]

var blocked: Array = [false, false, false]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args: Dictionary = {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var at: int = arg.find("=")
			args[arg.substr(2, at - 2)] = arg.substr(at + 1)
	DB.ensure_loaded()
	var data = JSON.parse_string(FileAccess.get_file_as_string(str(args.get("cases", ""))))
	if not data is Array:
		push_error("cases must be a JSON array")
		quit(2)
		return
	var mask: String = str(args.get("mask", "111"))
	for j in 3:
		blocked[j] = j < mask.length() and mask[j] == "0"
	var out: FileAccess = FileAccess.open(str(args.get("output", "user://torquemada_telemetry.jsonl")), FileAccess.WRITE)
	var rows: Array = []
	for config in data:
		var row: Dictionary = _play(config)
		rows.append(row)
		out.store_line(JSON.stringify(row))
		out.flush()
		print("CASE ", rows.size(), "/", data.size(), " ", row.id, " winner=", row.winner, " side=", row.side, " t=", snappedf(float(row.duration), 0.01))
	out.close()
	print("SUMMARY ", JSON.stringify(_summary(rows)))
	quit(0)


func _play(config: Dictionary) -> Dictionary:
	var sim: BattleSim = BattleSim.new(config)
	sim.controllers[0] = AIFactory.make(str(config.get("blue_ai", "tactician")), sim, 0)
	sim.controllers[1] = AIFactory.make(str(config.get("red_ai", "tactician")), sim, 1)
	sim.start()
	var tq: BUnit = null
	for u in sim.heroes:
		if u.def.id == ID:
			tq = u
	var casts: Array = [0, 0, 0]
	var purpose: Array = [0, 0, 0]
	var cancelled: Array = [0, 0, 0]
	var hit: Array = [false, false, false]
	var cleansed_units: Array = [0, 0, 0]
	var cleansed_hard: Array = [0, 0, 0]
	var self_cleansed: int = 0
	var s3_cleanse: int = 0
	var s3_push: int = 0
	var s3_push_enemies: int = 0
	# Opportunity episodes: S1 an own unit hard-controlled with >= 0.6 s left
	# within 330 while S1 is ready; S2 a fresh cc_by record on an observed enemy
	# within 440 while S2 is ready.
	var opp: Array = [0, 0]
	var opp_on: Array = [false, false]
	var stuck: float = 0.0
	var still_t: float = 0.0
	var still_pos: Vector2 = Vector2.INF
	var alive_t: float = 0.0
	var cc_taken: int = 0
	while sim.state == BattleSim.RUNNING:
		for j in 3:
			if blocked[j]:
				tq.cooldowns[j] = sim.time + 100.0
		sim.step()
		for ev in sim.tick_events:
			var ty: String = str(ev.type)
			if ty == "CC_APPLIED" and int(ev.g) == tq.idx and str(ev.get("status", "")) != "slow":
				cc_taken += 1
			var ab = ev.get("ability")
			if not (ab is Defs.AbilityDef) or (ab as Defs.AbilityDef).char_id != ID or int(ev.s) != tq.idx:
				continue
			var k: int = (ab as Defs.AbilityDef).slot - 1
			match ty:
				"CAST_STARTED":
					casts[k] += 1
					hit[k] = false
				"CAST_CANCELLED":
					cancelled[k] += 1
				"CLEANSED":
					cleansed_units[k] += 1
					if int(ev.g) == tq.idx:
						self_cleansed += 1
					for r in ev.get("removed", []):
						if str(r) in CLEANSE_CC:
							cleansed_hard[k] += 1
							break
					if not hit[k]:
						hit[k] = true
						purpose[k] += 1
						if k == 2:
							s3_cleanse += 1
				"CC_APPLIED":
					if k == 1 and not hit[1]:
						hit[1] = true
						purpose[1] += 1
				"DASH_STARTED":
					var victim: BUnit = sim.u_at(int(ev.g))
					if k == 2 and victim and victim.is_hero and victim.team != tq.team:
						s3_push_enemies += 1
						if not hit[2]:
							hit[2] = true
							purpose[2] += 1
							s3_push += 1
		if not tq.alive:
			opp_on = [false, false]
			still_pos = Vector2.INF
			continue
		alive_t += BattleSim.DT
		var abl: Array = sim.ability_list(tq)
		var o1: bool = false
		if sim.ability_ready(tq, 0, abl[0]):
			for x in sim.allies_of(tq.team):
				if x.pos.distance_to(tq.pos) > 330.0:
					continue
				for st in x.statuses:
					if st.end - sim.time >= 0.6 and (st.type in HARD_LOCK or st.type == &"root") and not st.extra.has("motion_id") and not st.extra.has("chamber"):
						o1 = true
		var o2: bool = false
		if sim.ability_ready(tq, 1, abl[1]):
			var by: Dictionary = tq.ks.get("cc_by", {})
			for idx in by:
				var e: BUnit = sim.u_at(int(idx))
				if e and e.alive and sim.time - float(by[idx]) <= 6.0 and sim.observes(tq, e) and e.pos.distance_to(tq.pos) <= 440.0:
					o2 = true
		for j in 2:
			var now: bool = o1 if j == 0 else o2
			if now and not opp_on[j]:
				opp[j] += 1
			opp_on[j] = now
		# Stuck: an ability order that neither starts nor moves the hero.
		var waiting: bool = str(tq.command.get("kind", "")) == "ability" and tq.action == null and tq.motion == null and not sim.has_any(tq, HARD_LOCK)
		if waiting and still_pos.is_finite() and tq.pos.distance_to(still_pos) < 3.0:
			still_t += BattleSim.DT
		else:
			if still_t >= 1.0:
				stuck += still_t
			still_t = 0.0
			still_pos = tq.pos
	if still_t >= 1.0:
		stuck += still_t
	var res: Dictionary = sim.result()
	var row: Dictionary = {"id": config.get("id", ""), "map": config.arena_id, "side": tq.team, "winner": res.winner,
		"duration": res.duration, "timeout": str(res.reason) == "time_limit", "alive_t": alive_t,
		"casts": casts, "purpose": purpose, "cancelled": cancelled, "s3_cleanse": s3_cleanse, "s3_push": s3_push,
		"s3_push_enemies": s3_push_enemies, "cleansed_units": cleansed_units, "cleansed_hard": cleansed_hard,
		"self_cleansed": self_cleansed, "opp1": opp[0], "opp2": opp[1], "stuck": stuck, "cc_taken": cc_taken,
		"damage": tq.st_damage}
	sim.dispose()
	return row


func _summary(rows: Array) -> Dictionary:
	var wins: int = 0
	var losses: int = 0
	var timeouts: int = 0
	var alive: float = 0.0
	var stuck: float = 0.0
	var casts: Array = [0, 0, 0]
	var purpose: Array = [0, 0, 0]
	var zero: Array = [0, 0, 0]
	for r: Dictionary in rows:
		if int(r.winner) == int(r.side):
			wins += 1
		elif int(r.winner) == 1 - int(r.side):
			losses += 1
		if bool(r.timeout):
			timeouts += 1
		alive += float(r.alive_t) / 60.0
		stuck += float(r.stuck)
		for k in 3:
			casts[k] += int(r.casts[k])
			purpose[k] += int(r.purpose[k])
			if int(r.casts[k]) == 0:
				zero[k] += 1
	var skills: Array = []
	for k in 3:
		var per_min: float = float(casts[k]) / maxf(0.01, alive)
		skills.append({"slot": k + 1, "casts": casts[k], "per_min_alive": snappedf(per_min, 0.01),
			"max_per_min": snappedf(60.0 / COOLDOWN[k], 0.01), "use_ratio": snappedf(per_min * COOLDOWN[k] / 60.0, 0.01),
			"purpose": purpose[k], "purpose_share": snappedf(float(purpose[k]) / maxf(1.0, casts[k]), 0.01), "zero_cast_cases": zero[k]})
	return {"cases": rows.size(), "wins": wins, "losses": losses, "win_rate": snappedf(float(wins) / maxf(1.0, wins + losses), 0.001),
		"timeouts": timeouts, "alive_min": snappedf(alive, 0.1), "stuck_s": snappedf(stuck, 0.1), "skills": skills}
