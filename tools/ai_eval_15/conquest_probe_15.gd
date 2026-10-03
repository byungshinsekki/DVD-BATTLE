extends SceneTree

# V1.5 conquest AI evaluation: behaviour statistics of one AI kind playing a
# mirrored 5v5 conquest match (both teams use the same AI) with an engineer
# forced into both teams. Measures turret placement quality, casts with no
# enemy near, deaths while outnumbered and time on objectives.
#
# godot --headless --path . --script res://tools/ai_eval_15/conquest_probe_15.gd -- \
#     --ai=tactician --first=0 --n=6 --out=reports/ai_eval_15/conquest_probe_tactician.jsonl
# Options: --ai (tactician | tactician14), --first, --n, --size=5, --seed=7001,
# --force=engineer, --max_time=480. One JSON line per match is appended to --out.

var ROSTER: Array = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DB.ensure_loaded()
	for d in DB.characters:
		ROSTER.append(d.id)
	var args: Dictionary = {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var i: int = arg.find("=")
			args[arg.substr(2, i - 2)] = arg.substr(i + 1)
	var ai: String = str(args.get("ai", "tactician"))
	var first: int = int(args.get("first", "0"))
	var n_matches: int = int(args.get("n", "6"))
	var size: int = int(args.get("size", "5"))
	var seed0: int = int(args.get("seed", "7001"))
	var max_time: float = float(args.get("max_time", "480"))
	var force: String = str(args.get("force", "engineer"))
	var out_path: String = str(args.get("out", ""))
	var arenas: Array = []
	for a in DB.arenas_for("control"):
		arenas.append(str(a.id))
	var out: FileAccess = null
	if out_path != "":
		DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
		out = FileAccess.open(out_path, FileAccess.READ_WRITE if FileAccess.file_exists(out_path) else FileAccess.WRITE)
		out.seek_end()
	for m in range(first, first + n_matches):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed0 + m * 101
		var pool: Array = ROSTER.duplicate()
		var blue: Array = []
		var red: Array = []
		for k in size:
			blue.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
			red.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
		if force != "":
			blue.erase(force)
			red.erase(force)
			while blue.size() >= size:
				blue.pop_back()
			while red.size() >= size:
				red.pop_back()
			blue.insert(0, force)
			red.insert(0, force)
		var arena: String = arenas[m % arenas.size()]
		var sim := BattleSim.new({"ruleset": "control", "arena_id": arena, "blue": blue, "red": red, "seed": seed0 + m, "max_time": max_time})
		sim.controllers[0] = AIFactory.make(ai, sim, 0)
		sim.controllers[1] = AIFactory.make(ai, sim, 1)
		sim.start()
		var st: Dictionary = _stats_run(sim)
		var row: Dictionary = {"ai": ai, "match": m, "arena": arena, "blue": blue, "red": red, "seed": seed0 + m,
			"winner": sim.winner, "reason": sim.finish_reason, "t": snappedf(sim.time, 0.1),
			"scores": [snappedf(sim.domination.scores[0], 0.1), snappedf(sim.domination.scores[1], 0.1)], "stats": st}
		print("MATCH ", JSON.stringify(row))
		if out:
			out.store_line(JSON.stringify(row))
			out.flush()
		sim.dispose()
	if out:
		out.close()
	quit(0)


func _stats_run(sim: BattleSim) -> Dictionary:
	var spawn_c: Array = []
	for t in 2:
		var c := Vector2.ZERO
		for p in sim.arena.spawns[t]:
			c += p
		spawn_c.append(c / maxf(1, sim.arena.spawns[t].size()))
	var placements: Dictionary = {}
	var stats: Dictionary = {"turrets": 0, "turret_spawnside": 0, "turret_no_damage": 0, "turret_far_obj": 0,
		"casts": 0, "casts_no_enemy": 0, "casts_no_enemy_spawn": 0,
		"deaths": 0, "deaths_outnumbered": 0, "alive_samples": 0, "on_point_samples": 0,
		"near_spawn_idle": 0, "far_idle": 0, "captures": 0, "neutralized": 0}
	var ent_damage: Dictionary = {}
	while sim.state == BattleSim.RUNNING:
		sim.step()
		for ev in sim.tick_events:
			var ty: String = str(ev.type)
			if ty == "CAST_STARTED":
				var caster: BUnit = sim.u_at(int(ev.s))
				var ab = ev.get("ability")
				if caster and caster.is_hero and ab is Defs.AbilityDef:
					var nearest: float = INF
					for o in sim.heroes:
						if o.alive and o.team != caster.team:
							nearest = minf(nearest, o.pos.distance_to(caster.pos))
					stats.casts += 1
					if nearest > 750.0:
						stats.casts_no_enemy += 1
						if caster.pos.distance_to(spawn_c[caster.team]) < 450.0:
							stats.casts_no_enemy_spawn += 1
			elif ty == "SUMMON_CREATED":
				var e: BUnit = sim.u_at(int(ev.g))
				var owner: BUnit = sim.u_at(int(ev.s))
				if e and owner and owner.is_hero:
					var near_obj: float = INF
					for p in sim.domination.points:
						near_obj = minf(near_obj, e.pos.distance_to(p.center) - float(p.radius))
					placements[e.idx] = {"kind": e.kind, "spawn_d": e.pos.distance_to(spawn_c[owner.team]), "obj_d": near_obj}
			elif ty == "HEALTH_DAMAGED":
				if placements.has(int(ev.s)):
					ent_damage[int(ev.s)] = float(ent_damage.get(int(ev.s), 0.0)) + float(ev.get("amount", 0.0))
			elif ty == "DEATH":
				var v: BUnit = sim.u_at(int(ev.g))
				if v and v.is_hero:
					stats.deaths += 1
					var al: int = 0
					var en: int = 0
					for o in sim.heroes:
						if not o.alive or o == v:
							continue
						if o.pos.distance_to(v.pos) < 520.0:
							if o.team == v.team:
								al += 1
							else:
								en += 1
					if en > al + 1:
						stats.deaths_outnumbered += 1
			elif ty == "CONTROL_CAPTURED":
				stats.captures += 1
			elif ty == "CONTROL_NEUTRALIZED":
				stats.neutralized += 1
		for q in sim.proj.list:
			if placements.has(q.shooter_idx):
				ent_damage[q.shooter_idx] = float(ent_damage.get(q.shooter_idx, 0.0)) + 1.0
		if sim.tick % 30 == 0:
			for u in sim.heroes:
				if not u.alive:
					continue
				stats.alive_samples += 1
				var on_point: bool = false
				for p in sim.domination.points:
					if u.pos.distance_to(p.center) <= float(p.radius):
						on_point = true
				if on_point:
					stats.on_point_samples += 1
				var in_combat: bool = sim.time - u.last_combat_time < 4.0
				if not in_combat and u.pos.distance_to(spawn_c[u.team]) < 330.0 and sim.time - u.spawn_time > 4.0 and u.vel.length() < 20.0:
					stats.near_spawn_idle += 1
				if not in_combat and not on_point and u.vel.length() < 15.0:
					stats.far_idle += 1
	for idx in placements:
		var pl: Dictionary = placements[idx]
		if pl.kind != "turret":
			continue
		stats.turrets += 1
		if float(pl.spawn_d) < 450.0:
			stats.turret_spawnside += 1
		if float(ent_damage.get(idx, 0.0)) <= 0.0:
			stats.turret_no_damage += 1
		if float(pl.obj_d) > 300.0:
			stats.turret_far_obj += 1
	return stats
