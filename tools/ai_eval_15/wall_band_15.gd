extends SceneTree

# V1.5 wall-contact evaluation. Replays the reference battles of
# reports/regression_cases_14.json and counts hero ticks spent inside the thin
# collision pad of an obstacle (between r - 0.1 and r + 0.3), and how many of
# those ticks left a hero that was ordered to move frozen in place. With
# --legacy_walls=1 the V1.4 wall handling is used (BattleSim.wall_unpin off).
#
# godot --headless --path . --script res://tools/ai_eval_15/wall_band_15.gd -- \
#     --ruleset=control --legacy_walls=1 --out=reports/ai_eval_15/wall_band_legacy.jsonl
# --ruleset: control | elimination | all


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DB.ensure_loaded()
	var args: Dictionary = {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var i: int = arg.find("=")
			args[arg.substr(2, i - 2)] = arg.substr(i + 1)
	var legacy: bool = str(args.get("legacy_walls", "0")) == "1"
	var ruleset: String = str(args.get("ruleset", "control"))
	var out_path: String = str(args.get("out", ""))
	BattleSim.wall_unpin = not legacy
	var cases: Array = JSON.parse_string(FileAccess.get_file_as_string("res://reports/regression_cases_14.json"))
	var out: FileAccess = null
	if out_path != "":
		DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
		out = FileAccess.open(out_path, FileAccess.READ_WRITE if FileAccess.file_exists(out_path) else FileAccess.WRITE)
		out.seek_end()
	for c in cases:
		var cfg: Dictionary = c
		if ruleset != "all" and str(cfg.get("ruleset", "elimination")) != ruleset:
			continue
		var sim := BattleSim.new(cfg)
		for t in 2:
			sim.controllers[t] = AIFactory.make(str(cfg.get("blue_ai" if t == 0 else "red_ai", "tactician")), sim, t)
		sim.start()
		var inside: int = 0
		var frozen: int = 0
		var last: Dictionary = {}
		while sim.state == BattleSim.RUNNING:
			sim.step()
			for u in sim.heroes:
				if not u.alive or u.motion:
					continue
				var r: float = sim.radius(u)
				var band: bool = sim.arena.inside_obstacle(u.pos, r + 0.3) and not sim.arena.inside_obstacle(u.pos, r - 0.1)
				if band:
					inside += 1
					if last.has(u.idx) and (last[u.idx] as Vector2).distance_to(u.pos) < 0.05 and str(u.command.get("kind", "")) == "move" and float(u.command.get("arrive", 0.0)) > 10.0:
						frozen += 1
				last[u.idx] = u.pos
		var row: Dictionary = {"case_id": str(cfg.get("id", "?")), "ruleset": str(cfg.get("ruleset", "elimination")), "legacy_walls": legacy,
			"band_ticks": inside, "frozen_ticks": frozen, "winner": sim.winner, "t": snappedf(sim.time, 0.01)}
		print("CASE ", JSON.stringify(row))
		if out:
			out.store_line(JSON.stringify(row))
			out.flush()
		sim.dispose()
	if out:
		out.close()
	BattleSim.wall_unpin = true
	quit(0)
