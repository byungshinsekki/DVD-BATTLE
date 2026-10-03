extends SceneTree

# V1.5 deathmatch evaluation for small matches: how quickly 2-4 AI
# participants find each other on the 3600x2200 maps. One match per map
# preset with random heroes; no kill target, fixed duration.
#
# godot --headless --path . --script res://tools/ai_eval_15/dm_small_15.gd -- \
#     --n=2 --t=300 --m=3 --out=reports/ai_eval_15/dm_small_2.jsonl


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DB.ensure_loaded()
	var args: Dictionary = {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var i: int = arg.find("=")
			args[arg.substr(2, i - 2)] = arg.substr(i + 1)
	var n: int = int(args.get("n", "2"))
	var duration: float = float(args.get("t", "300"))
	var out_path: String = str(args.get("out", ""))
	var out: FileAccess = null
	if out_path != "":
		DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
		out = FileAccess.open(out_path, FileAccess.READ_WRITE if FileAccess.file_exists(out_path) else FileAccess.WRITE)
		out.seek_end()
	for m in int(args.get("m", "3")):
		var rng := RandomNumberGenerator.new()
		rng.seed = 500 + m * 17 + n
		var pool: Array = DB.ids().duplicate()
		var players: Array = []
		for k in n:
			players.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
		var map_id: String = DeathmatchMapData.ORDER[m % 3]
		var sim := BattleSim.new({"ruleset": "deathmatch", "arena_id": map_id, "players": players, "seed": 900 + m, "max_time": duration, "kill_target": 99})
		for t in sim.team_count:
			sim.controllers[t] = AIFactory.make("tactician", sim, t)
		sim.start()
		var first_contact: float = -1.0
		var seen_samples: int = 0
		var alive_samples: int = 0
		var kill_times: Array = []
		while sim.state == BattleSim.RUNNING:
			sim.step()
			for ev in sim.tick_events:
				if str(ev.type) == "DM_KILL":
					kill_times.append(snappedf(sim.time, 0.1))
			if sim.tick % 15 == 0:
				for u in sim.heroes:
					if not u.alive:
						continue
					alive_samples += 1
					for b in sim.controllers[u.team].intel.visible_enemies():
						if (b as TeamIntel.EnemyBelief).is_hero:
							seen_samples += 1
							if first_contact < 0.0:
								first_contact = sim.time
							break
		var row: Dictionary = {"players": players, "map": map_id, "duration": duration, "first_contact": snappedf(first_contact, 0.1),
			"seen_share": snappedf(float(seen_samples) / maxf(1.0, alive_samples), 0.01), "kills": kill_times.size(), "kill_times": kill_times}
		print("MATCH ", JSON.stringify(row))
		if out:
			out.store_line(JSON.stringify(row))
			out.flush()
		sim.dispose()
	if out:
		out.close()
	quit(0)
