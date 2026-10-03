extends SceneTree

# V1.5 conquest AI evaluation: head-to-head matches between two AI kinds.
# Match inputs come from tools/ai_eval_15/h2h_specs_15.py. Results are
# appended as JSON lines; finished matches are skipped when resuming, and
# --worker/--workers split the list between processes.
#
# godot --headless --path . --script res://tools/ai_eval_15/h2h_15.gd -- \
#     --specs=reports/ai_eval_15/h2h_specs_15.json --out=reports/ai_eval_15/h2h_results_15.w0 \
#     --worker=0 --workers=2 --budget=140


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DB.ensure_loaded()
	var args: Dictionary = {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var i: int = arg.find("=")
			args[arg.substr(2, i - 2)] = arg.substr(i + 1)
	var specs: Array = JSON.parse_string(FileAccess.get_file_as_string(str(args.specs)))
	var out_path: String = str(args.out)
	var done: Dictionary = {}
	if FileAccess.file_exists(out_path):
		for line in FileAccess.get_file_as_string(out_path).split("\n", false):
			var row = JSON.parse_string(line)
			if row is Dictionary:
				done[str(row.id)] = true
	var only: String = str(args.get("only", ""))
	var worker: int = int(args.get("worker", "0"))
	var workers: int = int(args.get("workers", "1"))
	var budget: float = float(args.get("budget", "140"))
	var started: int = Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	var f: FileAccess = FileAccess.open(out_path, FileAccess.READ_WRITE if FileAccess.file_exists(out_path) else FileAccess.WRITE)
	f.seek_end()
	var ran: int = 0
	for k in specs.size():
		if k % workers != worker:
			continue
		var spec: Dictionary = specs[k]
		if done.has(str(spec.id)) or (only != "" and not (only.split(",") as Array).has(str(spec.id))):
			continue
		if (Time.get_ticks_msec() - started) / 1000.0 > budget:
			break
		var sim := BattleSim.new(spec.config)
		sim.controllers[0] = AIFactory.make(str(spec.config.blue_ai), sim, 0)
		sim.controllers[1] = AIFactory.make(str(spec.config.red_ai), sim, 1)
		sim.start()
		var t0: int = Time.get_ticks_msec()
		var heal_uses: Array = [0, 0]
		while sim.state == BattleSim.RUNNING:
			sim.step()
			for ev in sim.tick_events:
				if str(ev.type) == "HEAL_ZONE_USED":
					heal_uses[int(ev.get("team", 0))] += 1
		var row: Dictionary = {"id": spec.id, "winner": sim.winner, "reason": sim.finish_reason, "t": snappedf(sim.time, 0.1),
			"blue_ai": spec.config.blue_ai, "red_ai": spec.config.red_ai, "arena": spec.config.arena_id, "size": (spec.config.blue as Array).size(),
			"wall": (Time.get_ticks_msec() - t0) / 1000.0}
		if sim.is_control_mode():
			row["scores"] = [snappedf(sim.domination.scores[0], 0.1), snappedf(sim.domination.scores[1], 0.1)]
		var kills: Array = [0, 0]
		var cap: Array = [0.0, 0.0]
		var dmg: Array = [0.0, 0.0]
		for u in sim.heroes:
			kills[1 - u.team] += u.st_deaths
			cap[u.team] += u.st_capture_time
			dmg[u.team] += u.st_damage
		row["kills"] = kills
		row["capture_time"] = [snappedf(cap[0], 0.1), snappedf(cap[1], 0.1)]
		row["damage"] = [int(dmg[0]), int(dmg[1])]
		row["heal_uses"] = heal_uses
		f.store_line(JSON.stringify(row))
		f.flush()
		sim.dispose()
		ran += 1
	f.close()
	print("H2H worker=%d ran=%d" % [worker, ran])
	quit(0)
