extends SceneTree

# V1.5.3 AI telemetry probe (headless, read-only).
#
# Runs complete battles with the shipping AI (AIFactory "tactician", exactly as
# BattleRunner does) and records per-battle / per-hero / per-ability telemetry
# purely by observing BattleSim public state and its per-tick event list. It
# never modifies engine or AI state.
#
# Usage:
#   <godot> --headless --path <project> --script res://tools/ai_probe_153.gd -- \
#       --mode=elimination --maps=all --n=8 --size=3 --seed0=153100 \
#       --out=D:/.../telemetry/e3.jsonl [--max_time=150] [--shard=0/4] [--ai=tactician]
#   --list                      print arena ids per mode and quit
#   --roster=<json path>        dump ability metadata (categories) and quit
#
# Comps are drawn from a seeded shuffled deck of all heroes (every hero appears
# roughly equally). The draw order only depends on seed0/mode/size/maps/n, so a
# --shard=i/K split yields the same battles as a single process.

const DT: float = 1.0 / 30.0
const HARD: Array = [&"stun", &"root", &"airborne", &"suppression", &"sleep"]
const RETREAT: Array = ["후퇴", "측면 이탈 (우)", "측면 이탈 (좌)", "재집결", "보호선으로 후퇴"]
const DAMAGING: Array = ["lava", "spikes", "eruption", "shockwave"]
const WINDOW: float = 1.5
const LATE: float = 6.0
const HARMFUL_STATUS: Array = ["slow", "root", "stun", "silence", "disarm", "taunt", "fear", "airborne", "grounded", "sleep", "suppression", "charm", "control", "damageAmp", "healReduction", "sniperVulnerable", "nexus_seal", "imprisoned", "confusion", "plague", "pain", "infection", "bladeMark", "bladeTrace", "hooked"]
const SPECIAL_EVENTS: Array = ["STAT_STOLEN", "STATS_SWAPPED", "POSITIONS_SWAPPED", "PRISON_CREATED", "DIVERSION", "PROPAGANDA", "CHAMBER_STARTED", "SKILLS_SEALED", "INFO_REVEAL", "REVEAL", "DEFENSE_STATE", "PROJECTILE_BLOCKED", "PROJECTILE_REFLECTED", "PORTAL_USED", "COIN_COLLECTED", "CONTROL_ENDED", "STATUS_REMOVED", "TURRET_UPGRADED", "GARDEN_CLOSED", "PARITY_BED_RESOLVED", "SUMMON_CONSUMED", "STRUCTURE_REPLACED", "PROJECTILE_PORTAL"]

var args: Dictionary = {}
var ai_kind: String = "tactician"
var meta_cache: Dictionary = {}
var cur_sim: BattleSim = null
var cur_H: Dictionary = {}


# Observation-only wrappers: identical to the brains AIFactory.make("tactician")
# returns (TacticianBrain / DeathmatchBrain); they call the unchanged decide()
# and then record the order that was just issued, before the simulator can void it.
class ProbeTactician extends TacticianBrain:
	var recorder: Callable
	func decide(u: BUnit) -> void:
		super.decide(u)
		if recorder.is_valid():
			recorder.call(u)


class ProbeDeathmatch extends DeathmatchBrain:
	var recorder: Callable
	func decide(u: BUnit) -> void:
		super.decide(u)
		if recorder.is_valid():
			recorder.call(u)


func _make_ai(sim: BattleSim, t: int) -> TeamController:
	# --nohook=1 uses AIFactory directly (decision-time fields then stay empty);
	# used only to prove the observer wrapper does not change outcomes.
	if ai_kind != "tactician" or args.has("nohook"):
		return AIFactory.make(ai_kind, sim, t)
	if sim.is_deathmatch():
		var d: ProbeDeathmatch = ProbeDeathmatch.new(sim, t)
		d.recorder = _on_decide
		return d
	var b: ProbeTactician = ProbeTactician.new(sim, t)
	b.recorder = _on_decide
	return b


func _on_decide(u: BUnit) -> void:
	var sim: BattleSim = cur_sim
	if sim == null or not cur_H.has(u.idx):
		return
	var h: Dictionary = cur_H[u.idx]
	h.decisions += 1
	h._decided_tick = sim.tick
	var cmd: Dictionary = u.command
	var kind: String = str(cmd.get("kind", ""))
	var label: String = str(cmd.get("purpose", ""))
	var plabel: String = "none"
	if kind == "ability":
		plabel = "ability:S%d" % (int(cmd.get("index", -1)) + 1)
	elif kind == "basic":
		plabel = "basic"
	elif kind != "":
		plabel = label if label != "" else kind
	h.purpose[plabel] = int(h.purpose.get(plabel, 0)) + 1
	var is_retreat: bool = kind == "move" and label in RETREAT
	if is_retreat and not (str(h._last_purpose) in RETREAT):
		h.retreats += 1
	h._last_purpose = label if kind == "move" else kind
	if kind in ["ability", "basic"]:
		var tgt: int = int(cmd.get("target", -1))
		var tb: BUnit = sim.u_at(tgt)
		if tb and tb.is_hero and sim.eteam(tb) != sim.eteam(u):
			h.attack_orders += 1
			if not sim.observes(u, tb):
				h.unobserved_orders += 1
				h.unobserved_by_kind[plabel] = int(h.unobserved_by_kind.get(plabel, 0)) + 1
			var prev: BUnit = sim.u_at(int(h._last_target))
			if prev and prev != tb and prev.alive and sim.is_seen(sim.eteam(u), prev):
				h.target_switches += 1
			h._last_target = tgt


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
	if args.has("list"):
		for mode in ["elimination", "control", "deathmatch"]:
			print("MAPS ", mode, " ", JSON.stringify(_all_maps(mode)))
		quit(0)
		return
	if args.has("roster"):
		_dump_roster(str(args.roster))
		quit(0)
		return
	ai_kind = str(args.get("ai", "tactician"))
	var mode: String = str(args.get("mode", "elimination"))
	var maps: Array = _all_maps(mode) if str(args.get("maps", "all")) == "all" else Array(str(args.maps).split(",", false))
	var n: int = int(args.get("n", 4))
	var size: int = int(args.get("size", 8 if mode == "deathmatch" else 5))
	var seed0: int = int(args.get("seed0", 153000))
	var max_time: float = float(args.get("max_time", 150.0))
	var kill_target: int = int(args.get("kill_target", 10))
	var shard: PackedStringArray = str(args.get("shard", "0/1")).split("/")
	var si: int = int(shard[0])
	var sk: int = maxi(1, int(shard[1]))
	var out_path: String = str(args.get("out", "user://ai_probe.jsonl"))
	var out: FileAccess = FileAccess.open(out_path, FileAccess.WRITE)
	if out == null:
		push_error("cannot write " + out_path)
		quit(2)
		return
	# Seeded deck: identical draw order for any shard split.
	var deck_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	deck_rng.seed = hash([seed0, mode, size, maps, n])
	var ids: Array = DB.ids()
	var deck: Array = []
	var plan: Array = []
	var per_battle: int = size if mode == "deathmatch" else size * 2
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
			plan.append({"index": plan.size(), "map": str(maps[mi]), "seed": seed0 + mi * 1000 + k * 17, "comp": picked})
	var started: int = Time.get_ticks_msec()
	var done: int = 0
	for job in plan:
		if int(job.index) % sk != si:
			continue
		var row: Dictionary = _battle(mode, str(job.map), int(job.seed), job.comp, size, max_time, kill_target)
		row["index"] = job.index
		row["probe_args"] = {"mode": mode, "size": size, "seed0": seed0, "n": n, "max_time": max_time, "ai": ai_kind}
		out.store_line(JSON.stringify(row))
		out.flush()
		done += 1
		print("PROBE ", mode, " ", job.map, " seed=", job.seed, " winner=", row.winner, " reason=", row.reason,
			" dur=", snappedf(float(row.duration), 0.1), " wall=", snappedf(float(row.wall_seconds), 0.1))
	out.close()
	print("PROBE_DONE battles=", done, " wall=", (Time.get_ticks_msec() - started) / 1000.0)
	quit(0)


func _all_maps(mode: String) -> Array:
	if mode == "deathmatch":
		return DeathmatchMapData.ORDER.duplicate()
	return DB.arenas_for(mode).map(func(a: Arena): return a.id)


# ---------------------------------------------------------------- metadata

func _collect(effects: Array, out: Dictionary) -> void:
	for f in effects:
		if not f is Dictionary:
			continue
		var ty: String = str(f.get("type", ""))
		out["t:" + ty] = true
		if f.has("status"):
			out["s:" + str(f.status)] = true
		if f.get("selfOnly", false):
			out["selfOnly:" + ty] = true
		if f.has("effects"):
			_collect(f.effects, out)
		if f.has("damageEffect"):
			out["t:damage"] = true


func _meta(a: Defs.AbilityDef) -> Dictionary:
	var key: String = _akey(a)
	if meta_cache.has(key):
		return meta_cache[key]
	var tags: Dictionary = {}
	_collect(a.effects, tags)
	var harmful: bool = false
	for s in HARMFUL_STATUS:
		if tags.has("s:" + s) and not tags.has("selfOnly:status"):
			harmful = true
	var dmg: bool = tags.has("t:damage") or tags.has("t:dot") or tags.has("t:execute")
	var friendly: bool = tags.has("t:heal") or tags.has("t:shield") or tags.has("t:buff") or tags.has("t:heal_bank")
	var deploy: bool = tags.has("t:zone") or tags.has("t:summon") or tags.has("t:delayed_area") or tags.has("t:portal_pair") or tags.has("t:parity_bed") or a.action in ["turret", "rootGarden", "thornGarden", "portalPair", "prison"]
	var cat: String = "self"
	if a.target == "enemy" or dmg or harmful or tags.has("t:steal_stat") or tags.has("t:swap_stats"):
		cat = "hostile"
	elif a.target in ["ally", "position_ally"] or (friendly and a.target == "position"):
		cat = "support"
	var m: Dictionary = {"key": key, "name": a.name, "slot": a.slot, "target": a.target, "delivery": a.delivery, "action": a.action,
		"cooldown": a.cooldown, "cast_time": a.cast_time, "range": a.range, "radius": a.radius, "virtual": a.virtual,
		"hostile_flag": a.hostile, "category": cat, "deploy": deploy, "damage": dmg, "harmful_status": harmful,
		"friendly": friendly, "types": tags.keys().filter(func(x: String): return x.begins_with("t:")).map(func(x: String): return x.substr(2))}
	meta_cache[key] = m
	return m


func _akey(a) -> String:
	if a == null or not (a is Defs.AbilityDef):
		return ""
	var ab: Defs.AbilityDef = a
	if ab.virtual:
		return "%s|V:%s" % [ab.char_id, ab.virtual_kind]
	return ab.id


func _dump_roster(path: String) -> void:
	var rows: Array = []
	for id in DB.ids():
		var d: Defs.CharDef = DB.char_def(id)
		var abilities: Array = []
		for a in d.abilities:
			abilities.append(_meta(a))
		rows.append({"id": d.id, "name": d.name, "role": d.role, "range": d.stat("attackRange"), "ms": d.stat("moveSpeed"),
			"hp": d.stat("maxHealth"), "preferred_range": d.preferred_range, "no_basic": d.has_rule("no_basic"), "abilities": abilities})
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(rows, "\t"))
	f.close()
	print("ROSTER ", rows.size())


# ---------------------------------------------------------------- battle

func _v(p: Vector2) -> Array:
	return [snappedf(p.x, 0.1), snappedf(p.y, 0.1)]


func _new_hero(sim: BattleSim, u: BUnit) -> Dictionary:
	return {"idx": u.idx, "id": u.def.id, "team": u.team, "slot": u.slot,
		"alive_s": 0.0, "walk_px": 0.0, "burst_px": 0.0, "stuck_s": 0.0, "jitter_s": 0.0, "stuck_episodes": 0,
		"wall_s": 0.0, "idle_in_range_s": 0.0, "idle_static_in_range_s": 0.0, "cc_s": 0.0, "casting_s": 0.0,
		"haz_s": {}, "haz_avoidable_s": {}, "haz_dmg": {}, "haz_hits": {}, "env_deaths": 0, "env_assisted_deaths": 0,
		"null_deaths": 0, "self_kills": 0, "gimmick": {}, "decisions": 0, "purpose": {}, "idle_purpose": {}, "stuck_purpose": {},
		"retreats": 0, "target_switches": 0, "attack_orders": 0, "unobserved_orders": 0, "unobserved_by_kind": {},
		"voided_same_tick": 0, "voided_later": 0, "voided_cc": 0, "void_stall_s": 0.0, "void_streak_max_s": 0.0, "void_streaks_1s": 0, "void_streaks_3t": 0, "idle_target_in_range_s": 0.0,
		"stance": {}, "dm_intent": {}, "control_role": {},
		"abilities": {}, "unattributed": 0,
		# private trackers (stripped before output)
		"_streak": 0, "_hist": [], "_stuck_on": false, "_idle_streak": 0, "_last_env": -99.0, "_last_purpose": "",
		"_last_target": -1, "_pending": [], "_decided_tick": -1, "_had_cmd": false, "_void_streak": 0, "_stuck_start": 0.0, "_stuck_pos": Vector2.ZERO}


func _ab(h: Dictionary, a: Defs.AbilityDef) -> Dictionary:
	var key: String = _akey(a)
	var abs_: Dictionary = h.abilities
	if not abs_.has(key):
		abs_[key] = {"casts": 0, "completed": 0, "cancelled": 0, "miss": {}, "cancel": {}, "enemy": 0, "ally": 0, "self": 0,
			"deploy": 0, "special": 0, "blocked": 0, "whiff": 0, "no_enemy": 0, "late_enemy": 0, "overheal_only": 0,
			"dist_sum": 0.0, "dist_n": 0, "range_ratio_sum": 0.0, "range_ratio_n": 0, "over_range": 0, "over_range_done": 0, "over_range_miss": 0, "in_range_done": 0, "in_range_miss": 0, "near_enemy_sum": 0.0, "near_enemy_n": 0,
			"no_enemy_near": 0, "no_visible_enemy": 0, "target_immune": 0, "target_immune_resolve": 0, "self_cost": 0.0, "self_cost_casts": 0,
			"self_damage": 0.0, "dmg": 0.0, "heal": 0.0, "heal_raw": 0.0, "shield": 0.0, "kills": 0, "cc_s": 0.0,
			"ready_s": 0.0, "ready_opp_s": 0.0, "ally_targets": 0, "self_targets": 0}
	return abs_[key]


func _enemy(sim: BattleSim, owner: BUnit, g: int) -> int:
	# 1 enemy, 0 ally/self, -1 unknown. Base teams: a "control" status flips
	# eteam() of the victim, which must not turn a hit into an "ally" effect.
	var t: BUnit = sim.u_at(g)
	if t == null:
		return -1
	if not t.is_hero:
		var o: BUnit = _owner_hero(sim, t.idx)
		return 1 if (o != null and o.team != owner.team) or (o == null and t.team != owner.team) else 0
	return 1 if t.team != owner.team else 0


func _owner_hero(sim: BattleSim, s: int) -> BUnit:
	var u: BUnit = sim.u_at(s)
	var guard: int = 0
	while u != null and not u.is_hero and guard < 4:
		u = sim.u_at(u.owner_idx)
		guard += 1
	return u


func _find_pending(h: Dictionary, key: String, t: float) -> Dictionary:
	var pend: Array = h._pending
	for i in range(pend.size() - 1, -1, -1):
		var rec: Dictionary = pend[i]
		if (key == "" or rec.key == key) and float(rec.t) <= t + 1e-6 and t <= float(rec.late_end):
			return rec
	return {}


func _close_cast(h: Dictionary, rec: Dictionary) -> void:
	var st: Dictionary = h.abilities[rec.key]
	var f: Dictionary = rec.f
	if rec.completed: st.completed += 1
	if rec.cancelled != "":
		st.cancelled += 1
		st.cancel[rec.cancelled] = int(st.cancel.get(rec.cancelled, 0)) + 1
	if rec.miss != "":
		st.miss[rec.miss] = int(st.miss.get(rec.miss, 0)) + 1
	for k in ["enemy", "ally", "self", "deploy", "special", "blocked"]:
		if f.get(k, false):
			st[k] += 1
	var any: bool = f.get("enemy", false) or f.get("ally", false) or f.get("self", false) or f.get("deploy", false) or f.get("special", false)
	if not any and rec.cancelled == "":
		st.whiff += 1
		if f.get("overheal", false):
			st.overheal_only += 1
	if rec.over:
		st.over_range_done += 1
		if not f.get("enemy", false) and rec.cancelled == "":
			st.over_range_miss += 1
	elif bool(rec.ranged) and rec.cancelled == "":
		st.in_range_done += 1
		if not f.get("enemy", false):
			st.in_range_miss += 1
	if not f.get("enemy", false) and rec.cancelled == "":
		st.no_enemy += 1
		if f.get("late_enemy", false):
			st.late_enemy += 1


func _battle(mode: String, arena_id: String, seed: int, comp: Array, size: int, max_time: float, kill_target: int) -> Dictionary:
	var cfg: Dictionary = {"seed": seed, "arena_id": arena_id, "max_time": max_time}
	if mode == "deathmatch":
		cfg["ruleset"] = "deathmatch"
		cfg["players"] = comp
		cfg["kill_target"] = kill_target
	else:
		cfg["ruleset"] = mode
		cfg["blue"] = comp.slice(0, size)
		cfg["red"] = comp.slice(size, size * 2)
	var wall0: int = Time.get_ticks_usec()
	var sim: BattleSim = BattleSim.new(cfg)
	for t in sim.team_count:
		sim.controllers[t] = _make_ai(sim, t)
	var H: Dictionary = {}
	for u in sim.heroes:
		H[u.idx] = _new_hero(sim, u)
	cur_sim = sim
	cur_H = H
	sim.start()
	var events: Dictionary = {}
	var first_dmg: float = -1.0
	var last_dmg: float = -1.0
	var max_lull: float = 0.0
	var first_kill: float = -1.0
	var stuck_log: Array = []
	var focus_prev: Dictionary = {}
	var focus_switches: Array = []
	focus_switches.resize(sim.team_count)
	focus_switches.fill(0)
	var hazards: Array = sim.arena.hazards
	var tick_us: Array[int] = []
	var max_ticks: int = int(ceil(sim.max_time * 30.0)) + 30
	var pre_pos: Dictionary = {}
	var pre_alive: Dictionary = {}
	while sim.state == BattleSim.RUNNING:
		for u in sim.heroes:
			pre_pos[u.idx] = u.pos
			pre_alive[u.idx] = u.alive
		var t0: int = Time.get_ticks_usec()
		sim.step()
		tick_us.append(Time.get_ticks_usec() - t0)
		var now: float = sim.time
		# ---------------- events
		for ev: Dictionary in sim.tick_events:
			var typ: String = str(ev.type)
			events[typ] = int(events.get(typ, 0)) + 1
			var s: int = int(ev.get("s", -1))
			var g: int = int(ev.get("g", -1))
			var gu: BUnit = sim.u_at(g)
			if typ == "HEALTH_DAMAGED" and gu != null and gu.is_hero and s != g and s >= 0:
				if first_dmg < 0.0: first_dmg = now
				if last_dmg >= 0.0: max_lull = maxf(max_lull, now - last_dmg)
				last_dmg = now
			if typ == "CAST_STARTED":
				var hu: BUnit = sim.u_at(s)
				if hu == null or not H.has(hu.idx) or not (ev.get("ability") is Defs.AbilityDef):
					continue
				var h: Dictionary = H[hu.idx]
				var a: Defs.AbilityDef = ev.ability
				_meta(a)
				var st: Dictionary = _ab(h, a)
				st.casts += 1
				var from: Vector2 = ev.get("from", hu.pos)
				var aim: Vector2 = ev.get("pos", hu.pos)
				var tu: BUnit = sim.u_at(g)
				var over: bool = false
				var d: float = from.distance_to(tu.pos if tu else aim)
				if a.target != "self":
					st.dist_sum += d
					st.dist_n += 1
					var reach: float = a.range + sim.radius(hu)
					st.range_ratio_sum += d / maxf(1.0, reach)
					st.range_ratio_n += 1
					if d > reach + 8.0 + (sim.radius(tu) if tu else 0.0):
						st.over_range += 1
						over = true
				if tu != null:
					if sim.eteam(tu) != sim.eteam(hu):
						if sim.has_status(tu, &"invulnerable") or sim.has_status(tu, &"untargetable"):
							st.target_immune += 1
					elif tu == hu:
						st.self_targets += 1
					else:
						st.ally_targets += 1
				var near: float = INF
				var seen_any: bool = false
				for e in sim.heroes:
					if e.alive and sim.eteam(e) != sim.eteam(hu) and e.chamber == hu.chamber:
						near = minf(near, from.distance_to(e.pos))
						if sim.is_seen(sim.eteam(hu), e): seen_any = true
				if near < INF:
					st.near_enemy_sum += near
					st.near_enemy_n += 1
				if near > 700.0: st.no_enemy_near += 1
				if not seen_any: st.no_visible_enemy += 1
				var ct: float = float(ev.get("cast_time", a.cast_time))
				(h._pending as Array).append({"key": _akey(a), "t": now, "resolve": now + ct, "window_end": now + ct + WINDOW, "late_end": now + ct + LATE,
					"target": g, "completed": false, "cancelled": "", "miss": "", "f": {}, "immune_checked": false, "over": over, "ranged": a.target != "self"})
				continue
			if typ in ["CAST_COMPLETED", "CAST_CANCELLED", "MISS"]:
				var hu2: BUnit = sim.u_at(s)
				if hu2 == null or not H.has(hu2.idx):
					continue
				var rec: Dictionary = _find_pending(H[hu2.idx], _akey(ev.get("ability")), now)
				if rec.is_empty():
					continue
				if typ == "CAST_COMPLETED": rec.completed = true
				elif typ == "CAST_CANCELLED": rec.cancelled = str(ev.get("reason", "?"))
				else: rec.miss = str(ev.get("reason", "?"))
				continue
			if typ == "ENV_HIT":
				if H.has(g):
					var hh: Dictionary = H[g]
					var ht: String = str(ev.get("hazard_type", "?"))
					hh.haz_dmg[ht] = float(hh.haz_dmg.get(ht, 0.0)) + float(ev.get("amount", 0.0)) + float(ev.get("absorbed", 0.0))
					hh.haz_hits[ht] = int(hh.haz_hits.get(ht, 0)) + 1
					hh._last_env = now
				continue
			if typ in ["ENV_PORTAL", "ENV_HASTE", "ENV_FOUNTAIN", "HEAL_ZONE_USED", "DM_ITEM_PICKED"]:
				var who: int = g if typ != "HEAL_ZONE_USED" else g
				if H.has(who):
					H[who].gimmick[typ] = int(H[who].gimmick.get(typ, 0)) + 1
				continue
			if typ in ["DEATH", "EXECUTED"] and H.has(g):
				if first_kill < 0.0: first_kill = now
				var hd: Dictionary = H[g]
				if s < 0:
					if float(hd._last_env) >= now - 1e-6:
						hd.env_deaths += 1
					else:
						hd.null_deaths += 1
				elif s == g:
					hd.self_kills += 1
				if now - float(hd._last_env) <= 2.0:
					hd.env_assisted_deaths += 1
			# ---- ability effect attribution
			var ab = ev.get("ability")
			var owner: BUnit = null
			var key: String = ""
			if ab is Defs.AbilityDef:
				key = _akey(ab)
				owner = _owner_hero(sim, s)
			elif typ in SPECIAL_EVENTS or typ == "CC_IMMUNE":
				owner = _owner_hero(sim, s)
			if owner == null or not H.has(owner.idx):
				continue
			var ho: Dictionary = H[owner.idx]
			var r: Dictionary = _find_pending(ho, key, now)
			if r.is_empty():
				if key != "" and typ in ["HEALTH_DAMAGED", "HEAL_APPLIED", "SHIELD_APPLIED", "CC_APPLIED"]:
					ho.unattributed += 1
				continue
			var st2: Dictionary = ho.abilities[r.key]
			var fl: Dictionary = r.f
			var immediate: bool = now <= float(r.window_end) + 1e-6 and str(ev.get("source_type", "")) != "PERSISTENT"
			var rel: int = _enemy(sim, owner, g)
			match typ:
				"HEALTH_DAMAGED", "SHIELD_ABSORBED":
					var amt: float = float(ev.get("amount", 0.0)) + float(ev.get("absorbed", 0.0))
					if g == owner.idx:
						st2.self_damage += amt
					elif rel == 1 and amt > 0.0:
						st2.dmg += float(ev.get("amount", 0.0))
						if immediate: fl["enemy"] = true
						else: fl["late_enemy"] = true
				"HEAL_APPLIED":
					st2.heal += float(ev.get("amount", 0.0))
					st2.heal_raw += float(ev.get("raw", 0.0))
					if float(ev.get("amount", 0.0)) > 0.5:
						if immediate: fl["self" if g == owner.idx else "ally"] = true
					else:
						fl["overheal"] = true
				"SHIELD_APPLIED":
					st2.shield += float(ev.get("amount", 0.0))
					if immediate:
						if rel == 1: fl["enemy"] = true
						else: fl["self" if g == owner.idx else "ally"] = true
				"CC_APPLIED", "STATUS_APPLIED", "BUFF_APPLIED", "STAT_STOLEN", "STATS_SWAPPED", "POSITIONS_SWAPPED":
					if typ == "CC_APPLIED" and rel == 1:
						st2.cc_s += float(ev.get("duration", 0.0))
					if g == owner.idx or g < 0:
						if immediate: fl["self"] = true
					elif rel == 1:
						if immediate: fl["enemy"] = true
						else: fl["late_enemy"] = true
					elif rel == 0:
						if immediate: fl["ally"] = true
				"DAMAGE_IMMUNE", "CC_IMMUNE":
					fl["blocked"] = true
				"SUMMON_CREATED", "ZONE_SPAWNED":
					if immediate: fl["deploy"] = true
				"DASH_STARTED", "BLINKED", "ABILITY_RECAST", "HEALTH_COST":
					if typ == "HEALTH_COST":
						st2.self_cost += float(ev.get("amount", 0.0))
						st2.self_cost_casts += 1
					elif immediate:
						fl["self"] = true
				"DEATH", "EXECUTED":
					if rel == 1: st2.kills += 1
				_:
					if typ in SPECIAL_EVENTS or typ == "FAKE_NEWS":
						if immediate:
							fl["special"] = true
							if rel == 1 and g != owner.idx: fl["enemy"] = true
		# ---------------- per-tick hero state
		for u in sim.heroes:
			var h: Dictionary = H[u.idx]
			# finalize expired pending casts
			var pend: Array = h._pending
			while not pend.is_empty() and float(pend[0].late_end) < now:
				_close_cast(h, pend.pop_front())
			for rec in pend:
				if not rec.immune_checked and now >= float(rec.resolve):
					rec.immune_checked = true
					var tu2: BUnit = sim.u_at(int(rec.target))
					if tu2 and tu2.alive and sim.eteam(tu2) != sim.eteam(u) and (sim.has_status(tu2, &"invulnerable") or sim.has_status(tu2, &"untargetable")):
						h.abilities[rec.key].target_immune_resolve += 1
			if not u.alive:
				h._streak = 0
				h._idle_streak = 0
				h._hist = []
				h._stuck_on = false
				continue
			h.alive_s += DT
			# The simulator voids an order whose enemy target the caster cannot
			# observe (sim.gd _try_execute_command); steer() then re-adds only
			# "arrive", so a voided order is a command dictionary without "kind".
			var has_cmd: bool = u.command.has("kind")
			if not has_cmd and int(h.decisions) > 0 and u.action == null and u.motion == null and not sim.is_crowd_controlled(u):
				h.void_stall_s += DT
				h._void_streak = int(h._void_streak) + 1
			else:
				if int(h._void_streak) > 0:
					h.void_streak_max_s = maxf(float(h.void_streak_max_s), int(h._void_streak) * DT)
					if int(h._void_streak) >= 30: h.void_streaks_1s += 1
					if int(h._void_streak) >= 3: h.void_streaks_3t += 1
				h._void_streak = 0
			if not has_cmd:
				if int(h._decided_tick) == sim.tick:
					h.voided_same_tick += 1
					if sim.is_crowd_controlled(u): h.voided_cc += 1
				elif bool(h._had_cmd):
					h.voided_later += 1
					if sim.is_crowd_controlled(u): h.voided_cc += 1
			h._had_cmd = has_cmd
			# displacement
			var p0: Vector2 = pre_pos[u.idx]
			if bool(pre_alive[u.idx]):
				var disp: float = p0.distance_to(u.pos)
				if u.motion != null or disp > sim.stat(u, &"moveSpeed") * DT * 1.6 + 1.0:
					h.burst_px += disp
				else:
					h.walk_px += disp
			var hard: bool = sim.has_any(u, HARD)
			if hard or sim.is_crowd_controlled(u): h.cc_s += DT
			if u.action != null: h.casting_s += DT
			# stuck: an active movement order that does not displace the body.
			var wants: bool = false
			if u.action == null and u.motion == null and not hard and not sim.is_crowd_controlled(u) and u.chamber == "" and sim.stat(u, &"moveSpeed") > 5.0:
				var cmd2: Dictionary = u.command
				var k2: String = str(cmd2.get("kind", "move"))
				if k2 == "move":
					var goal: Vector2 = cmd2.get("goal", u.pos)
					wants = goal.distance_to(u.pos) > 24.0
				elif k2 in ["ability", "basic"]:
					var tt: BUnit = sim.u_at(int(cmd2.get("target", -1)))
					var tp: Vector2 = tt.pos if tt else cmd2.get("pos", u.pos)
					var need: float = float(cmd2.get("need", 60.0))
					wants = need > 1.0 and u.pos.distance_to(tp) > need * 0.95 + 10.0
			var hist: Array = h._hist
			hist.append(u.pos)
			if hist.size() > 31:
				hist.pop_front()
			h._streak = int(h._streak) + 1 if wants else 0
			var stuck_now: bool = false
			if int(h._streak) >= 30 and hist.size() >= 31:
				var net: float = (hist[0] as Vector2).distance_to(u.pos)
				if net < 2.0:
					stuck_now = true
					h.stuck_s += DT
					var sp: String = str(u.command.get("purpose", u.command.get("kind", "")))
					h.stuck_purpose[sp] = float(h.stuck_purpose.get(sp, 0.0)) + DT
				elif net < 10.0:
					var path: float = 0.0
					for i in range(1, hist.size()):
						path += (hist[i - 1] as Vector2).distance_to(hist[i])
					if path > 40.0:
						h.jitter_s += DT
			if stuck_now and not h._stuck_on:
				h.stuck_episodes += 1
				h._stuck_start = now
				h._stuck_pos = u.pos
			if not stuck_now and h._stuck_on and stuck_log.size() < 80:
				stuck_log.append({"hero": u.def.id, "t": snappedf(float(h._stuck_start), 0.1), "dur": snappedf(now - float(h._stuck_start) + 1.0, 0.1),
					"pos": _v(h._stuck_pos), "purpose": str(u.command.get("purpose", "")), "wall": snappedf(sim.arena.distance_to_wall(u.pos) - sim.radius(u), 0.1)})
			h._stuck_on = stuck_now
			# wall proximity (every 3 ticks)
			if sim.tick % 3 == 0 and sim.arena.distance_to_wall(u.pos) - sim.radius(u) < 10.0:
				h.wall_s += DT * 3.0
			# idle with a visible enemy inside basic range while able to attack
			var idle: bool = false
			var idle_target: bool = false
			if u.action == null and u.motion == null and sim.can_basic(u):
				var rng_: float = sim.stat(u, &"attackRange") + sim.radius(u)
				var ordered: int = int(u.command.get("target", -1)) if str(u.command.get("kind", "")) in ["basic", "ability"] else -1
				for e in sim.heroes:
					if not e.alive or sim.eteam(e) == sim.eteam(u) or sim.has_status(e, &"untargetable"):
						continue
					if u.pos.distance_to(e.pos) <= rng_ + sim.radius(e) and sim.observes(u, e):
						idle = true
						if e.idx == ordered: idle_target = true
			h._idle_streak = int(h._idle_streak) + 1 if idle else 0
			if int(h._idle_streak) >= 9:
				h.idle_in_range_s += DT
				if idle_target: h.idle_target_in_range_s += DT
				if u.vel.length() < 10.0: h.idle_static_in_range_s += DT
				var ip: String = str(u.command.get("purpose", u.command.get("kind", "none")))
				h.idle_purpose[ip] = float(h.idle_purpose.get(ip, 0.0)) + DT
			# hazards
			if not hazards.is_empty() and sim.env.enabled and u.chamber == "":
				var rr: float = sim.radius(u) * 0.28
				for hz in hazards:
					var ty: String = str(hz.type)
					if not Arena.hazard_effect_contains(hz, u.pos, now, rr):
						continue
					var clk: Dictionary = Arena.hazard_clock(hz, now)
					var live: bool = bool(clk.active) or ty == "shockwave"
					if not live:
						continue
					h.haz_s[ty] = float(h.haz_s.get(ty, 0.0)) + DT
					if (ty in DAMAGING or ty == "gravity") and not hard and u.motion == null:
						h.haz_avoidable_s[ty] = float(h.haz_avoidable_s.get(ty, 0.0)) + DT
			# ability readiness (every 6 ticks): ready while an enemy is seen in reach
			if sim.tick % 6 == 0 and not hard:
				for i in u.def.abilities.size():
					var a: Defs.AbilityDef = u.def.abilities[i]
					if not sim.ability_ready(u, i, a):
						continue
					var st3: Dictionary = _ab(h, a)
					_meta(a)
					st3.ready_s += DT * 6.0
					var reach2: float = (a.range if a.target != "self" else maxf(a.radius, 140.0)) + sim.radius(u)
					for e in sim.heroes:
						if e.alive and sim.eteam(e) != sim.eteam(u) and sim.is_seen(sim.eteam(u), e) and u.pos.distance_to(e.pos) <= reach2 + sim.radius(e):
							st3.ready_opp_s += DT * 6.0
							break
		# ---------------- team-level AI state (1 Hz)
		if sim.tick % 30 == 0:
			for t in sim.team_count:
				var c = sim.controllers[t]
				if c == null or not (c is TacticianBrain):
					continue
				var tb2: TacticianBrain = c
				var stance: String = str(tb2.plan.get("stance", ""))
				var fidx: int = int(tb2.plan.get("focus", -1))
				if focus_prev.has(t) and int(focus_prev[t]) != fidx and fidx >= 0 and int(focus_prev[t]) >= 0:
					var pf: BUnit = sim.u_at(int(focus_prev[t]))
					if pf and pf.alive:
						focus_switches[t] += 1
				focus_prev[t] = fidx
				for u in sim.heroes:
					if not u.alive or u.team != t:
						continue
					var h2: Dictionary = H[u.idx]
					h2.stance[stance] = int(h2.stance.get(stance, 0)) + 1
					if c is DeathmatchBrain:
						var im: String = str((c as DeathmatchBrain).intent.get("mode", ""))
						h2.dm_intent[im] = int(h2.dm_intent.get(im, 0)) + 1
					if tb2.control_plan:
						var obj: Dictionary = tb2.control_plan.intent(u)
						var role: String = str(obj.get("role", "none")) if not obj.is_empty() else "none"
						if str(obj.get("heal_target", "")) != "": role = "heal"
						h2.control_role[role] = int(h2.control_role.get(role, 0)) + 1
		if sim.tick > max_ticks:
			break
	for u in sim.heroes:
		var h3: Dictionary = H[u.idx]
		for rec in h3._pending:
			_close_cast(h3, rec)
		h3._pending = []
	if last_dmg >= 0.0:
		max_lull = maxf(max_lull, sim.time - last_dmg)
	var wall_s: float = (Time.get_ticks_usec() - wall0) / 1000000.0
	var res: Dictionary = sim.result()
	var heroes: Array = []
	var used_meta: Dictionary = {}
	var dm_rank: Dictionary = {}
	if sim.deathmatch:
		for row in res.deathmatch.ranking:
			dm_rank[int(row.idx)] = {"rank": int(row.rank), "kills": int(row.kills), "deaths": int(row.deaths), "assists": int(row.assists), "items": int(row.items)}
	for u in sim.heroes:
		var h4: Dictionary = H[u.idx]
		for k in h4.keys():
			if str(k).begins_with("_"):
				h4.erase(k)
		h4["damage"] = u.st_damage
		h4["taken"] = u.st_taken
		h4["healing"] = u.st_healing
		h4["shielding"] = u.st_shielding
		h4["mitigated"] = u.st_mitigated
		h4["cc_dealt"] = u.st_cc
		h4["kills"] = u.st_kills
		h4["deaths"] = u.st_deaths
		h4["casts"] = u.st_casts
		h4["basic_hits"] = u.st_basic_hits
		h4["health_cost"] = u.st_health_cost
		h4["capture_time"] = u.st_capture_time
		h4["zone_healing"] = u.st_zone_healing
		h4["alive_end"] = u.alive
		h4["hp_end"] = sim.hp_ratio(u) if u.alive else 0.0
		if dm_rank.has(u.idx):
			h4["dm"] = dm_rank[u.idx]
		for k in h4.abilities.keys():
			if meta_cache.has(k): used_meta[k] = meta_cache[k]
		heroes.append(h4)
	tick_us.sort()
	var out: Dictionary = {"mode": sim.ruleset, "map": sim.arena.id, "seed": seed, "comp": comp, "winner": sim.winner, "reason": sim.finish_reason,
		"duration": sim.time, "wall_seconds": wall_s, "p95_tick_ms": tick_us[int((tick_us.size() - 1) * 0.95)] / 1000.0 if not tick_us.is_empty() else 0.0,
		"first_damage": first_dmg, "first_kill": first_kill, "max_lull": max_lull, "events": events, "stuck_log": stuck_log,
		"focus_switches": focus_switches, "arena": {"w": sim.arena.width, "h": sim.arena.height, "hazards": hazards.map(func(hz: Dictionary): return str(hz.type)),
		"bounds": [sim.arena.min_x, sim.arena.min_y, sim.arena.max_x, sim.arena.max_y]}, "heroes": heroes, "ability_meta": used_meta}
	if sim.is_control_mode():
		out["scores"] = sim.domination.scores.duplicate()
	cur_sim = null
	cur_H = {}
	sim.dispose()
	return out
