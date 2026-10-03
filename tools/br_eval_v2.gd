extends SceneTree

# V2 battleground evaluation runs (B-MODE). Headless; writes nothing unless
# --out= is given.
#   <godot> --headless --path <project> --script res://tools/br_eval_v2.gd -- \
#       --format=solo|duo|trio --teams=30 --map=br_ashen_metropolis --seed=7 \
#       [--zone=fast|normal|slow] [--secs=600] [--out=<json path>] [--ai=tactician]
#       [--progress=60]  (a "BR_PROGRESS" line every 60 match seconds)
# Defaults are the full-size lobbies (solo 30, duo 15, trio 10). Prints one
# JSON line "BR_EVAL {...}" with the match metrics shared with
# tests/battleground_ai_v2.gd: kills, knocks, revives, item pickups, zone
# deaths, finish time and placements, mean / p99 / max tick ms, the clumping
# metric (median distance from each living hero to the nearest other living
# hero, and to the nearest hero of another team, sampled every 5 s; series
# rows [t, any, enemy]) and the time series of alive teams.
# B-SQUAD adds: heroes still in at fixed times and the share eliminated before
# the first shrink, zone deaths as a share of deaths, zone damage and
# hero-seconds spent outside a damaging circle, every knock with its outcome
# (revived / finished / bled out / team wipe) and whether the downed hero's
# squad could contest it (revive_eligible), revive cancels by reason, the
# squad leash (distance of each standing member to its first standing
# teammate) and the battleground AI layer's own cost (layer_ms_per_tick).

const FULL := {"solo": 30, "duo": 15, "trio": 10}
const SQUAD := {"solo": 1, "duo": 2, "trio": 3}

var args: Dictionary = {}
# Match seconds between progress lines (0 = none); set by --progress.
static var progress_every: float = 0.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var at: int = arg.find("=")
			args[arg.substr(2, at - 2)] = arg.substr(at + 1)
	DB.ensure_loaded()
	progress_every = float(args.get("progress", 0.0))
	var fmt: String = str(args.get("format", "solo"))
	var n: int = int(args.get("teams", FULL.get(fmt, 30)))
	var out: Dictionary = run_match(fmt, n, str(args.get("map", BattlegroundMapData.ORDER[0])), int(args.get("seed", 7)),
		str(args.get("zone", "normal")), float(args.get("secs", 600.0)), str(args.get("ai", "tactician")), int(args.get("prof", 0)) == 1)
	print("BR_EVAL ", JSON.stringify(out))
	if args.has("out"):
		var f: FileAccess = FileAccess.open(str(args.out), FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify(out, "  "))
	quit(0)


# Random rosters: solo may repeat heroes across players; a squad never
# repeats a hero within itself.
static func roster(squad: int, teams: int, seed_v: int) -> Array:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_v * 977 + squad
	var ids: Array = DB.ids()
	var out: Array = []
	for _t in teams:
		var pool: Array = ids.duplicate()
		var team: Array = []
		for _m in squad:
			team.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
		out.append(team)
	return out


static func make_sim(fmt: String, teams: int, map_id: String, seed_v: int, zone: String, ai: String = "tactician", extra: Dictionary = {}) -> BattleSim:
	var sq: int = int(SQUAD.get(fmt, 1))
	var cfg: Dictionary = {"ruleset": "battleground", "arena_id": map_id, "seed": seed_v, "squad": sq,
		"teams": roster(sq, teams, seed_v), "zone_speed": zone, "max_time": BattlegroundMode.MAX_TIME}
	for k in extra:
		cfg[k] = extra[k]
	var sim: BattleSim = BattleSim.new(cfg)
	for t in sim.team_count:
		sim.controllers[t] = AIFactory.make(ai, sim, t)
	return sim


static func median(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var s: Array = values.duplicate()
	s.sort()
	var n: int = s.size()
	return float(s[n / 2]) if n % 2 == 1 else 0.5 * (float(s[n / 2 - 1]) + float(s[n / 2]))


# Plays one match to the end (or `secs`) and returns its metrics.
static func run_match(fmt: String, teams: int, map_id: String, seed_v: int, zone: String, secs: float, ai: String = "tactician", prof: bool = false) -> Dictionary:
	var t_build: int = Time.get_ticks_msec()
	var sim: BattleSim = make_sim(fmt, teams, map_id, seed_v, zone, ai)
	sim.start()
	var build_ms: int = Time.get_ticks_msec() - t_build
	var grid_keys: Dictionary = {}
	for k in Navigator._cache.keys():
		grid_keys[k] = true
	var br: BattlegroundMode = sim.battleground
	var ticks: Array = []
	var clump: Array = []
	var picks: int = 0
	var swaps: int = 0
	var revives_started: int = 0
	var revive_cancels: int = 0
	var cancel_reasons: Dictionary = {}
	var knock_rows: Array = []        # {t, victim, team, eligible, outcome, t_end}
	var open_knock: Dictionary = {}   # downed hero idx -> row index
	var leash: Array = []
	var zone_damage: float = 0.0
	var outside_s: float = 0.0
	var early_kills: Array = []       # [t, killer intent mode, victim intent mode, cause] before the first shrink
	var mode_share: Dictionary = {}   # stage -> intent mode -> samples (every 5 s)
	var invariants: Array = []
	BattlegroundAIProfile.lprof.clear()
	BattlegroundAIProfile.lprof_on = true
	# --prof=1: the simulator's section profile (BattleSim._step_profiled),
	# in total and for the slowest ticks.
	sim.profiling = prof
	var worst: Array = []
	var next_progress: float = progress_every if progress_every > 0.0 else INF
	while sim.state == BattleSim.RUNNING and sim.time < secs:
		if sim.time >= next_progress:
			next_progress += progress_every
			var sum_ms: float = 0.0
			for v0 in ticks:
				sum_ms += float(v0)
			print("BR_PROGRESS t=%.0f teams=%d heroes=%d tick_mean_ms=%.1f wall_s=%.0f" % [sim.time, br.alive_team_count(), br.alive_hero_count(),
				sum_ms / maxf(1.0, float(ticks.size())), (Time.get_ticks_msec() - t_build) / 1000.0])
		var before: Dictionary = sim.prof.duplicate() if prof else {}
		var t0: int = Time.get_ticks_usec()
		sim.step()
		var ms: float = (Time.get_ticks_usec() - t0) / 1000.0
		ticks.append(ms)
		if prof and ms > 60.0:
			var parts: Dictionary = {}
			for k in sim.prof:
				var d: float = (float(sim.prof[k]) - float(before.get(k, 0))) / 1000.0
				if d > 2.0:
					parts[k] = snappedf(d, 0.1)
			worst.append([snappedf(sim.time, 0.1), snappedf(ms, 0.1), parts])
		for ev in sim.tick_events:
			match str(ev.type):
				"DM_ITEM_PICKED":
					picks += 1
				"BR_ITEM_SWAP":
					swaps += 1
				"BR_REVIVE_START":
					revives_started += 1
				"BR_REVIVE_CANCEL":
					revive_cancels += 1
					cancel_reasons[str(ev.reason)] = int(cancel_reasons.get(str(ev.reason), 0)) + 1
				"BR_DOWNED":
					var vu: BUnit = sim.u_at(int(ev.g))
					open_knock[int(ev.g)] = knock_rows.size()
					var elig: bool = revive_eligible(sim, vu)
					knock_rows.append({"t": snappedf(sim.time, 0.1), "victim": int(ev.g), "team": vu.team if vu else -1,
						"eligible": elig, "eligible_any": elig, "site": revive_site_ok(sim, vu), "outcome": "open", "t_end": -1.0})
				"BR_REVIVED":
					if open_knock.has(int(ev.g)):
						var row: Dictionary = knock_rows[int(open_knock[int(ev.g)])]
						row["outcome"] = "revived"
						row["t_end"] = snappedf(sim.time, 0.1)
						open_knock.erase(int(ev.g))
				"BR_ELIMINATED":
					if sim.time <= float(br.zone.shrink_start[1]) + 1e-6 and early_kills.size() < 40:
						early_kills.append([snappedf(sim.time, 0.1), _mode_of(sim, int(ev.s)), _mode_of(sim, int(ev.g)), str(ev.cause)])
					if open_knock.has(int(ev.g)):
						var row2: Dictionary = knock_rows[int(open_knock[int(ev.g)])]
						var cz: String = str(ev.cause)
						row2["outcome"] = "finished" if cz == "kill" else cz
						row2["t_end"] = snappedf(sim.time, 0.1)
						open_knock.erase(int(ev.g))
				"ENV_HIT":
					if str(ev.get("hazard", "")) == "br_zone":
						zone_damage += float(ev.get("amount", 0.0))
		if sim.tick % 15 == 0:
			for kv in open_knock:
				var krow: Dictionary = knock_rows[int(open_knock[kv])]
				if not bool(krow.eligible_any) and revive_eligible(sim, sim.u_at(int(kv))):
					krow["eligible_any"] = true
		if sim.tick % 15 == 0 and br.zone.dps_ratio_at(sim.time) > 0.0:
			for u0 in sim.heroes:
				if u0.alive and br.zone.outside(u0.pos, sim.time):
					outside_s += 0.5
		if sim.tick % 150 == 0:
			_leash_sample(sim, leash)
			_mode_sample(sim, mode_share)
			var living: Array = []
			for u in sim.heroes:
				if u.alive:
					living.append(u)
			var near: Array = []
			var near_enemy: Array = []
			for a in living:
				var best: float = INF
				var best_e: float = INF
				for b in living:
					if a != b:
						var d: float = (a as BUnit).pos.distance_to((b as BUnit).pos)
						best = minf(best, d)
						if (a as BUnit).team != (b as BUnit).team:
							best_e = minf(best_e, d)
				if best < INF:
					near.append(best)
				if best_e < INF:
					near_enemy.append(best_e)
			if not near.is_empty():
				clump.append([snappedf(sim.time, 0.1), snappedf(median(near), 0.1), snappedf(median(near_enemy), 0.1)])
			var err: String = invariant_error(sim)
			if err != "" and invariants.size() < 8:
				invariants.append("%.1f %s" % [sim.time, err])
	BattlegroundAIProfile.lprof_on = false
	var res: Dictionary = sim.result()
	var hs: Dictionary = br.hstats
	var kills: int = 0
	var knocks: int = 0
	var revives: int = 0
	var zone_deaths: int = 0
	var causes: Dictionary = {}
	for idx in hs:
		kills += int(hs[idx].kills)
		knocks += int(hs[idx].knocks)
		revives += int(hs[idx].revives)
		var cause: String = str(hs[idx].death_cause)
		if cause != "":
			causes[cause] = int(causes.get(cause, 0)) + 1
		if cause == "zone":
			zone_deaths += 1
	var fresh: int = 0
	for k2 in Navigator._cache.keys():
		if not grid_keys.has(k2):
			fresh += 1
	var sorted: Array = ticks.duplicate()
	sorted.sort()
	var total: float = 0.0
	for v in sorted:
		total += float(v)
	var nt: int = maxi(1, sorted.size())
	var clump_vals: Array = []
	var clump_enemy: Array = []
	for row in clump:
		clump_vals.append(float(row[1]))
		clump_enemy.append(float(row[2]))
	var out: Dictionary = {"format": fmt, "teams": teams, "heroes": sim.heroes.size(), "map": map_id, "seed": seed_v, "zone": zone,
		"finished": sim.state == BattleSim.FINISHED, "reason": str(res.reason), "finish_time": snappedf(sim.time, 0.01),
		"winner_team": br.winner_team, "kills": kills, "knocks": knocks, "revives": revives, "revive_starts": revives_started,
		"revive_cancels": revive_cancels, "item_pickups": picks, "swaps": swaps, "zone_deaths": zone_deaths, "death_causes": causes,
		"tick_mean_ms": snappedf(total / nt, 0.001), "tick_p99_ms": snappedf(float(sorted[mini(nt - 1, int(nt * 0.99))]) if not sorted.is_empty() else 0.0, 0.001),
		"tick_max_ms": snappedf(float(sorted[nt - 1]) if not sorted.is_empty() else 0.0, 0.001), "build_ms": build_ms,
		"clump_median_px": snappedf(median(clump_vals), 0.1), "clump_enemy_median_px": snappedf(median(clump_enemy), 0.1), "clump_series": clump, "alive_series": br.series.duplicate(true),
		"placement": br.placement.duplicate(), "elim_time": br.elim_time.duplicate(), "invariant_errors": invariants,
		"nav_mid_builds": fresh}
	_add_squad_metrics(out, sim, knock_rows, cancel_reasons, leash, zone_damage, outside_s)
	out["early_kills"] = early_kills
	out["mode_share"] = mode_share
	var layer: Dictionary = {}
	var layer_sum: float = 0.0
	for k3 in BattlegroundAIProfile.lprof:
		var per_tick: float = float(BattlegroundAIProfile.lprof[k3]) / 1000.0 / maxf(1.0, float(sim.tick))
		layer[k3] = snappedf(per_tick, 0.001)
		if k3 != "plan_core":
			layer_sum += per_tick
	# plan_total includes the shared tactician fight plan (plan_core).
	layer_sum -= float(BattlegroundAIProfile.lprof.get("plan_core", 0)) / 1000.0 / maxf(1.0, float(sim.tick))
	out["layer_ms_per_tick"] = layer
	out["layer_own_ms_per_tick"] = snappedf(layer_sum, 0.001)
	if prof:
		var per: Dictionary = {}
		for k in sim.prof:
			per[k] = snappedf(float(sim.prof[k]) / 1000.0 / maxf(1.0, float(sim.tick)), 0.001)
		out["prof_ms_per_tick"] = per
		worst.sort_custom(func(a: Array, b: Array) -> bool: return float(a[1]) > float(b[1]))
		out["worst_ticks"] = worst.slice(0, 25)
		out["slow_ticks_over_60ms"] = worst.size()
	sim.dispose()
	return out


# Rule invariants that must hold at every sample (empty string = fine).
static func invariant_error(sim: BattleSim) -> String:
	var br: BattlegroundMode = sim.battleground
	var alive_teams: int = 0
	for team in br.team_count:
		var standing: int = br.team_standing(team)
		var alive: int = br.team_alive(team)
		if br.is_eliminated(team):
			if alive > 0:
				return "eliminated team %d still has %d alive" % [team, alive]
			if not br.placement.has(team):
				return "eliminated team %d has no placement" % team
		else:
			alive_teams += 1
			if standing == 0 and sim.state == BattleSim.RUNNING:
				return "team %d in play without a standing member" % team
	if alive_teams != br.alive_team_count():
		return "alive team count mismatch"
	for u in sim.heroes:
		if br.is_downed(u):
			if not u.alive:
				return "dead hero %d still downed" % u.idx
			if u.hp > BattlegroundMode.DOWNED_HP + 0.01:
				return "downed hero %d above downed health" % u.idx
			if br.squad <= 1:
				return "solo hero %d downed" % u.idx
		if not u.alive and not (br.inventory.get(u.idx, []) as Array).is_empty():
			return "dead hero %d holds items" % u.idx
		if (br.inventory.get(u.idx, []) as Array).size() > DeathmatchMode.SLOTS:
			return "hero %d holds more than %d items" % [u.idx, DeathmatchMode.SLOTS]
	for r_idx in br.reviving:
		var tgt: BUnit = sim.u_at(int(br.reviving[r_idx]))
		if tgt == null or not br.is_downed(tgt):
			return "revive channel on a hero who is not downed"
	return ""


# Knock, pacing, zone and leash metrics (B-SQUAD).
static func _add_squad_metrics(out: Dictionary, sim: BattleSim, knock_rows: Array, cancel_reasons: Dictionary, leash: Array, zone_damage: float, outside_s: float) -> void:
	var br: BattlegroundMode = sim.battleground
	var deaths: int = 0
	var z1: float = float(br.zone.shrink_start[1])
	var by_z1: int = 0
	var alive_at: Dictionary = {}
	var marks: Array = [45.0, 75.0, 135.0, 195.0, 240.0, 280.0, 315.0, 345.0, 370.0, 410.0, 455.0]
	for t in marks:
		alive_at[str(int(t))] = 0
	for u in sim.heroes:
		var dt: float = float(br.hstats[u.idx].death_time)
		if dt >= 0.0:
			deaths += 1
			if dt <= z1 + 1e-6:
				by_z1 += 1
		for t2 in marks:
			if (dt < 0.0 or dt > float(t2)) and float(t2) <= sim.time + 1e-6:
				alive_at[str(int(t2))] = int(alive_at[str(int(t2))]) + 1
	out["elim_by_z1"] = by_z1
	out["elim_frac_z1"] = snappedf(float(by_z1) / maxf(1.0, float(sim.heroes.size())), 0.001)
	out["z1_start"] = z1
	out["alive_at"] = alive_at
	out["deaths"] = deaths
	out["zone_death_share"] = snappedf(float(out.zone_deaths) / maxf(1.0, float(deaths)), 0.001)
	out["zone_damage"] = snappedf(zone_damage, 1.0)
	out["outside_hero_s"] = snappedf(outside_s, 0.5)
	var outcomes: Dictionary = {}
	var eligible: int = 0
	var eligible_revived: int = 0
	var any_n: int = 0
	var any_revived: int = 0
	var site_n: int = 0
	var site_revived: int = 0
	for row in knock_rows:
		var oc: String = str(row.outcome)
		outcomes[oc] = int(outcomes.get(oc, 0)) + 1
		if bool(row.eligible):
			eligible += 1
			if oc == "revived":
				eligible_revived += 1
		if bool(row.eligible_any):
			any_n += 1
			if oc == "revived":
				any_revived += 1
		if bool(row.get("site", false)):
			site_n += 1
			if oc == "revived":
				site_revived += 1
	out["knocks_eligible_any"] = any_n
	out["knocks_eligible_any_revived"] = any_revived
	out["knocks_site"] = site_n
	out["knocks_site_revived"] = site_revived
	out["knock_outcomes"] = outcomes
	out["knocks_eligible"] = eligible
	out["knocks_eligible_revived"] = eligible_revived
	out["revive_rate_eligible"] = snappedf(float(eligible_revived) / maxf(1.0, float(eligible)), 0.001)
	out["revive_rate_all"] = snappedf(float(outcomes.get("revived", 0)) / maxf(1.0, float(knock_rows.size())), 0.001)
	out["knock_rows"] = knock_rows
	out["revive_cancel_reasons"] = cancel_reasons
	if not leash.is_empty():
		var over600: int = 0
		var over900: int = 0
		for d in leash:
			if float(d) > 600.0:
				over600 += 1
			if float(d) > 900.0:
				over900 += 1
		var srt: Array = leash.duplicate()
		srt.sort()
		out["leash_median_px"] = snappedf(median(leash), 0.1)
		out["leash_p90_px"] = snappedf(float(srt[mini(srt.size() - 1, int(srt.size() * 0.9))]), 0.1)
		out["leash_over600"] = snappedf(float(over600) / float(leash.size()), 0.001)
		out["leash_over900"] = snappedf(float(over900) / float(leash.size()), 0.001)


# Squads: each standing member's distance to its team's first standing member.
static func _leash_sample(sim: BattleSim, leash: Array) -> void:
	var br: BattlegroundMode = sim.battleground
	if br.squad <= 1:
		return
	for team in br.team_count:
		var lead: BUnit = null
		for u in br.team_members(team):
			if not u.alive or br.is_downed(u):
				continue
			if lead == null:
				lead = u
			else:
				leash.append(u.pos.distance_to(lead.pos))


# Ground truth (tool only): a knock the downed hero's squad can contest. Some
# standing teammate is not itself losing a fight: the standing enemy heroes
# within 800 px of it have at most 1.25x the health of its own standing side
# there.
static func revive_eligible(sim: BattleSim, victim: BUnit) -> bool:
	if victim == null:
		return false
	var br: BattlegroundMode = sim.battleground
	for m in br.team_members(victim.team):
		if m == victim or not m.alive or br.is_downed(m):
			continue
		var own_hp: float = 0.0
		var foe_hp: float = 0.0
		for u in sim.heroes:
			if not u.alive or br.is_downed(u) or u.pos.distance_to(m.pos) > 800.0:
				continue
			if u.team == m.team:
				own_hp += u.hp
			else:
				foe_hp += u.hp
		if foe_hp <= own_hp * 1.25:
			return true
	return false


# Intent mode of the controller of unit idx's team ("" when none).
static func _mode_of(sim: BattleSim, idx: int) -> String:
	var u: BUnit = sim.u_at(idx)
	if u == null or u.team < 0 or u.team >= sim.controllers.size() or sim.controllers[u.team] == null:
		return ""
	var c = sim.controllers[u.team]
	var it = c.get("squad_intent")
	if not (it is Dictionary):
		it = c.get("intent")
	return str((it as Dictionary).get("mode", "")) if it is Dictionary else ""


# Intent modes of every controller still playing, by stage of the match.
static func _mode_sample(sim: BattleSim, share: Dictionary) -> void:
	var br: BattlegroundMode = sim.battleground
	var stage: String = "loot" if sim.time < br.zone.shrink_start[1] else ("mid" if sim.time < br.zone.shrink_start[3] else "late")
	if not share.has(stage):
		share[stage] = {}
	var row: Dictionary = share[stage]
	for c in sim.controllers:
		if c == null:
			continue
		var it = c.get("squad_intent")
		if not (it is Dictionary):
			it = c.get("intent")
		if it is Dictionary:
			var m: String = str((it as Dictionary).get("mode", ""))
			if m != "" and m != "dead":
				row[m] = int(row.get(m, 0)) + 1


# Ground truth (tool only), stricter companion of revive_eligible: the squad
# still stands and could win at the knock site (standing enemy heroes within
# 800 px of the downed hero have at most 1.25x the health of all its standing
# teammates).
static func revive_site_ok(sim: BattleSim, victim: BUnit) -> bool:
	if victim == null:
		return false
	var br: BattlegroundMode = sim.battleground
	var own_hp: float = 0.0
	for m in br.team_members(victim.team):
		if m != victim and m.alive and not br.is_downed(m):
			own_hp += m.hp
	if own_hp <= 0.0:
		return false
	var foe_hp: float = 0.0
	for u in sim.heroes:
		if u.alive and u.team != victim.team and not br.is_downed(u) and u.pos.distance_to(victim.pos) <= 800.0:
			foe_hp += u.hp
	return foe_hp <= own_hp * 1.25
