extends SceneTree

# Reproducible offline matches. This runner never touches user settings or records.
var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args: Dictionary = {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var split_at: int = arg.find("=")
			args[arg.substr(2, split_at - 2)] = arg.substr(split_at + 1)
	DB.ensure_loaded()
	# V1.5 regression hook: reproduce the 1.4 wall-contact behaviour exactly.
	if str(args.get("legacy_walls", "0")) == "1":
		BattleSim.wall_unpin = false
	if args.has("roster"):
		var roster: Array = []
		for d in DB.characters:
			var abilities: Array = []
			for a in d.abilities:
				abilities.append({"slot": a.slot, "name": a.name, "cooldown": a.cooldown,
					"effects": a.effects, "action": a.action, "flags": a.flags})
			roster.append({"id": d.id, "name": d.name, "role": d.role, "stats": d.stats,
				"abilities": abilities, "passives": d.passives})
		var roster_file: FileAccess = FileAccess.open(str(args.roster), FileAccess.WRITE)
		roster_file.store_string(JSON.stringify(roster, "\t"))
		roster_file.close()
		print("ROSTER ", roster.size())
		quit(0)
		return
	var source: String = str(args.get("cases", ""))
	var data = JSON.parse_string(FileAccess.get_file_as_string(source))
	if not data is Array:
		push_error("Cases must be a JSON array: " + source)
		quit(2)
		return
	var output: FileAccess = FileAccess.open(str(args.get("output", "user://balance.jsonl")), FileAccess.WRITE)
	if output == null:
		push_error("Cannot write output")
		quit(2)
		return
	var completed: int = 0
	var start_ms: int = Time.get_ticks_msec()
	for config in data:
		var valid: bool = true
		for id in config.blue + config.red:
			if DB.char_def(str(id)) == null:
				push_error("Unknown roster ID: " + str(id))
				valid = false
		if not valid:
			failures += 1
			continue
		var sim: BattleSim = BattleSim.new(config)
		sim.controllers[0] = AIFactory.make(str(config.get("blue_ai", "tactician")), sim, 0)
		sim.controllers[1] = AIFactory.make(str(config.get("red_ai", "tactician")), sim, 1)
		sim.start()
		var events: Dictionary = {}
		var tick_us: Array[int] = []
		var started: int = Time.get_ticks_usec()
		var invariant_error: String = ""
		var peak_entities: int = 0
		var score_samples: Array = []
		while sim.state == BattleSim.RUNNING:
			var before: int = Time.get_ticks_usec()
			sim.step()
			tick_us.append(Time.get_ticks_usec() - before)
			peak_entities = maxi(peak_entities, sim.entities.size())
			for ev in sim.tick_events:
				var key: String = str(ev.type)
				events[key] = int(events.get(key, 0)) + 1
			if sim.tick % 30 == 0:
				if sim.is_control_mode():
					for point: Dictionary in sim.domination.points:
						if not is_finite(float(point.progress)) or absf(float(point.progress)) > 1.00001 or int(point.owner) not in [-1, 0, 1]:
							invariant_error = "invalid objective state"
					for score in sim.domination.scores:
						if not is_finite(float(score)) or float(score) < 0.0:
							invariant_error = "invalid control score"
					if sim.tick % 300 == 0:
						score_samples.append([sim.time, float(sim.domination.scores[0]), float(sim.domination.scores[1])])
				for u in sim.units:
					if not is_finite(u.hp) or not u.pos.is_finite() or not u.vel.is_finite():
						invariant_error = "non-finite state: " + u.id
					# Timed summons can expire while retaining positive health.
					if u.hp < -0.001 or (u.is_hero and not u.alive and u.hp > 0.001):
						invariant_error = "invalid death/health state: " + u.id
					if u.statuses.size() > 100 or u.buffs.size() > 200:
						invariant_error = "unbounded status/buff growth: " + u.id
			if sim.tick > int(sim.max_time * 30.0) + 10:
				invariant_error = "simulation failed to terminate"
			if invariant_error != "":
				break
		var elapsed_us: int = Time.get_ticks_usec() - started
		var result: Dictionary = sim.result()
		result.erase("history")
		var final_state: Array = []
		for u in sim.heroes:
			final_state.append([u.id, u.hp, u.pos.x, u.pos.y, u.st_damage, u.st_casts])
		var control_state: Dictionary = {}
		if sim.is_control_mode():
			var owners: Array = []
			for point: Dictionary in sim.domination.points:
				owners.append([point.id, point.owner, point.progress, point.contested])
			control_state = {"scores": sim.domination.scores.duplicate(), "points": owners, "score_samples": score_samples}
		result["control_validation"] = control_state
		result["signature"] = JSON.stringify([result.winner, result.duration, final_state, control_state] if sim.is_control_mode() else [result.winner, result.duration, final_state]).sha256_text()
		result["case_id"] = config.get("id", str(completed))
		result["config"] = config
		result["events"] = events
		result["peak_entities"] = peak_entities
		result["wall_seconds"] = elapsed_us / 1000000.0
		tick_us.sort()
		result["p95_tick_ms"] = tick_us[int((tick_us.size() - 1) * 0.95)] / 1000.0 if not tick_us.is_empty() else 0.0
		result["max_tick_ms"] = tick_us.back() / 1000.0 if not tick_us.is_empty() else 0.0
		result["invariant_error"] = invariant_error
		if invariant_error != "":
			failures += 1
			push_error(str(result.case_id) + ": " + invariant_error)
		output.store_line(JSON.stringify(result))
		output.flush()
		sim.dispose()
		completed += 1
		print("MATCH ", completed, "/", data.size(), " ", result.case_id, " winner=", result.winner,
			" duration=", snappedf(result.duration, 0.01), " wall=", snappedf(result.wall_seconds, 0.01))
	output.close()
	print("SUITE completed=", completed, " failures=", failures, " wall_seconds=", (Time.get_ticks_msec() - start_ms) / 1000.0)
	quit(0 if failures == 0 else 1)
