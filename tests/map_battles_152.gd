extends SceneTree

# Integration smoke: unchanged real AI, public maps and normal battle rules.
# No winner-strength comparison and no injected movement or gimmick triggers.
# V1.5.3: also records the time to first contact (first hero-on-enemy-hero
# damage) per map, so the reworked formats can be compared with V1.5.2.
const TICKS: int = 600
const EMBED_LIMIT: int = 90 # 3 seconds: tolerate transient contact resolution.
var passed: int = 0
var failed: Array = []
var battles: Array = []
var roster_seen: Dictionary = {}
var environment_totals: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed.append(label)
		push_error("MAP_BATTLES_152 " + label)

func _battle(map_id: String, ruleset: String, index: int) -> void:
	var ids: Array = DB.ids()
	var roster: Array = []
	for slot in 6:
		var id: String = str(ids[(index * 5 + slot) % ids.size()])
		roster.append(id)
		roster_seen[id] = true
	var config: Dictionary = {"ruleset": ruleset, "arena_id": map_id, "seed": 152100 + index * 31, "max_time": 20.0}
	if ruleset == "deathmatch":
		config.players = roster
		config.kill_target = 99
	else:
		config.blue = roster.slice(0, 3)
		config.red = roster.slice(3, 6)
	var sim: BattleSim = BattleSim.new(config)
	for team in sim.team_count:
		sim.controllers[team] = AIFactory.make("tactician", sim, team)
	sim.start()
	var events: Dictionary = {}
	var environment: Dictionary = {}
	var hazards: Dictionary = {}
	for h: Dictionary in sim.arena.hazards:
		hazards[str(h.id)] = str(h.type)
	# V1.5.3 gates are obstacle entries with a "gate" schedule; their ENV_GATE
	# events reference the obstacle id.
	for o: Dictionary in sim.arena.obstacles:
		if o.has("gate"):
			hazards[str(o.id)] = "gate"
	var finite_errors: Array = []
	var health_errors: Array = []
	var event_errors: Array = []
	var embed_streak: Dictionary = {}
	var embed_peak: Dictionary = {}
	var overlap_samples: int = 0
	var outside_peak: float = 0.0
	var max_hp_excess: float = 0.0
	var over_hp_streak: Dictionary = {}
	var life_ids: Dictionary = {}
	var travel: Dictionary = {}
	var last_positions: Dictionary = {}
	var peak_entities: int = 0
	var first_contact: float = -1.0
	var begin_us: int = Time.get_ticks_usec()
	for tick in TICKS:
		if sim.state != BattleSim.RUNNING:
			break
		sim.step()
		peak_entities = maxi(peak_entities, sim.entities.size())
		for ev: Dictionary in sim.tick_events:
			var type: String = str(ev.type)
			events[type] = int(events.get(type, 0)) + 1
			if type == "HEALTH_DAMAGED" and first_contact < 0.0:
				var src: int = int(ev.get("s", -1))
				var dst: BUnit = sim.u_at(int(ev.get("g", -1)))
				if src >= 0 and dst != null and dst.is_hero and src != dst.idx and sim.u_at(src) != null and sim.eteam(sim.u_at(src)) != sim.eteam(dst):
					first_contact = sim.time
			if type.begins_with("ENV_"):
				var hazard_id: String = str(ev.get("hazard", ""))
				if not hazards.has(hazard_id):
					event_errors.append({"tick": sim.tick, "type": type, "hazard": hazard_id})
				var label: String = type + ":" + str(hazards.get(hazard_id, "unknown"))
				environment[label] = int(environment.get(label, 0)) + 1
				environment_totals[label] = int(environment_totals.get(label, 0)) + 1
		for u: BUnit in sim.units:
			if not is_finite(u.hp) or not u.pos.is_finite() or not u.vel.is_finite():
				finite_errors.append({"tick": sim.tick, "unit": u.id})
			if u.hp < -0.01 or (u.is_hero and not u.alive and u.hp > 0.01):
				health_errors.append({"tick": sim.tick, "unit": u.id, "hp": u.hp, "alive": u.alive})
			if not u.is_hero:
				continue
			if int(life_ids.get(u.idx, -1)) != u.life_id:
				life_ids[u.idx] = u.life_id
				embed_streak[u.idx] = 0
				over_hp_streak[u.idx] = 0
				last_positions[u.idx] = u.pos
			travel[u.idx] = float(travel.get(u.idx, 0.0)) + u.pos.distance_to(last_positions.get(u.idx, u.pos))
			last_positions[u.idx] = u.pos
			if not u.alive:
				embed_streak[u.idx] = 0
				over_hp_streak[u.idx] = 0
				continue
			var hp_limit: float = sim.max_hp(u)
			max_hp_excess = maxf(max_hp_excess, u.hp - hp_limit)
			# Timed max-HP buffs can expire at a tick boundary. Only a persistent
			# excess beyond rounding tolerance violates the living HP contract.
			var excess: bool = u.hp > hp_limit + maxf(0.05, hp_limit * 0.002)
			over_hp_streak[u.idx] = int(over_hp_streak.get(u.idx, 0)) + 1 if excess else 0
			if int(over_hp_streak[u.idx]) == 4:
				health_errors.append({"tick": sim.tick, "unit": u.id, "hp": u.hp, "max_hp": hp_limit, "reason": "persistent maximum HP excess"})
			if u.chamber != "":
				embed_streak[u.idx] = 0
				continue
			var radius: float = maxf(1.0, sim.radius(u) - 0.75)
			var resolved: Vector2 = sim.arena.resolve_circle(u.pos, radius)
			var depth: float = resolved.distance_to(u.pos)
			outside_peak = maxf(outside_peak, depth)
			var embedded: bool = depth > 1.5
			if embedded:
				overlap_samples += 1
			embed_streak[u.idx] = int(embed_streak.get(u.idx, 0)) + 1 if embedded else 0
			embed_peak[u.idx] = maxi(int(embed_peak.get(u.idx, 0)), int(embed_streak[u.idx]))
	var permanent: Array = []
	for idx in embed_peak:
		if int(embed_peak[idx]) >= EMBED_LIMIT:
			permanent.append({"unit_index": idx, "ticks": embed_peak[idx]})
	var moved: int = 0
	for distance in travel.values():
		if float(distance) > 20.0:
			moved += 1
	check(finite_errors.is_empty(), map_id + " all unit positions, velocity and health finite")
	check(health_errors.is_empty(), map_id + " living/dead and maximum HP contract")
	check(permanent.is_empty(), map_id + " no hero embedded in static terrain for three seconds")
	check(event_errors.is_empty(), map_id + " environment event references match this arena")
	check(moved >= 2, map_id + " multiple AI heroes actually navigate the map")
	check(sim.tick <= TICKS + 1 and sim.time <= 20.0 + BattleSim.DT, map_id + " bounded 20-second run")
	check(sim.time >= 20.0 - BattleSim.DT or (sim.state == BattleSim.FINISHED and str(sim.finish_reason) != ""), map_id + " full interval or legitimate early battle completion")
	var row: Dictionary = {"map": map_id, "ruleset": ruleset, "config": config, "roster": roster, "sim_seconds": sim.time, "ticks": sim.tick,
		"early_finish": sim.time < 20.0 - BattleSim.DT, "finish_reason": sim.finish_reason, "first_contact": first_contact, "wall_seconds": (Time.get_ticks_usec() - begin_us) / 1000000.0,
		"events": events, "environment_events": environment, "configured_hazards": hazards, "moved_heroes": moved, "hero_travel": travel,
		"finite_errors": finite_errors, "health_errors": health_errors, "event_errors": event_errors,
		"terrain_overlap_samples": overlap_samples, "max_contact_correction": outside_peak, "max_embed_ticks_by_hero": embed_peak,
		"permanent_embeds": permanent, "max_hp_excess": max_hp_excess, "peak_entities": peak_entities}
	battles.append(row)
	print("MAP_BATTLE ", map_id, " seconds=", snappedf(sim.time, 0.01), " first_contact=", snappedf(first_contact, 0.01), " env=", JSON.stringify(environment), " overlap=", overlap_samples, " failures=", failed.size())
	sim.dispose()

func _run() -> void:
	DB.ensure_loaded()
	var index: int = 0
	for mode in ["elimination", "control"]:
		for a: Arena in DB.arenas_for(mode):
			_battle(a.id, mode, index)
			index += 1
	for id in DeathmatchMapData.ORDER:
		_battle(id, "deathmatch", index)
		index += 1
	check(battles.size() == 18, "every shipped map runs real AI")
	check(roster_seen.size() == 26, "all twenty-six heroes represented in map smoke battles")
	var report: Dictionary = {"suite": "map_battles_152", "status": "PASS" if failed.is_empty() else "FAIL", "passed": passed, "failed": failed,
		"battle_count": battles.size(), "roster_count": roster_seen.size(), "environment_totals": environment_totals, "battles": battles,
		"method": "Real tactician AI; 3v3 or six-player deathmatch; 20-second ceiling; no forced gimmick triggers and no winner-strength evaluation. Per-map absence of a gimmick event is recorded rather than fabricated."}
	DirAccess.make_dir_recursive_absolute("res://reports/maps_152")
	var file: FileAccess = FileAccess.open("res://reports/maps_152/battles.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("MAP_BATTLES_152 ", report.status, " passed=", passed, " failed=", failed.size())
	quit(0 if failed.is_empty() else 1)
