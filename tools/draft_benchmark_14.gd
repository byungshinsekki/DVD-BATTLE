extends SceneTree

# Offline comparison. Uses public draft inputs, never user settings or records.
const Legacy = preload("res://tests/baselines/draft_director_13.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args: Dictionary = {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var at: int = arg.find("=")
			args[arg.substr(2, at - 2)] = arg.substr(at + 1)
	DB.ensure_loaded()
	var source_hashes: Dictionary = {"draft_director.gd": FileAccess.get_sha256("res://scripts/ai/draft_director.gd"),
		"draft_search.gd": FileAccess.get_sha256("res://scripts/ai/draft_search.gd"),
		"legacy_director.gd": FileAccess.get_sha256("res://tests/baselines/draft_director_13.gd")}
	var inputs = JSON.parse_string(FileAccess.get_file_as_string(str(args.get("cases", ""))))
	if not inputs is Array:
		push_error("Draft cases must be a JSON array")
		quit(2)
		return
	var output: FileAccess = FileAccess.open(str(args.get("output", "res://reports/draft_benchmark_14.jsonl")), FileAccess.WRITE)
	if output == null:
		push_error("Cannot open draft benchmark output")
		quit(2)
		return
	var failures: int = 0
	for cfg: Dictionary in inputs:
		var teams: Array = [[], []] # 0 = V1.4, 1 = V1.3
		var trace: Array = []
		var side: int = int(cfg.get("first", 1))
		var count: int = int(cfg.team_size)
		var valid: bool = true
		for pick_index in count * 2:
			var options: Dictionary = {"team_size": count, "arena_id": cfg.arena_id,
				"ruleset": cfg.ruleset, "seed": int(cfg.seed), "user_history": {}}
			var started: int = Time.get_ticks_usec()
			var director = DraftDirector.new(options) if side == 0 else Legacy.new(options)
			var decision: Dictionary = director.decide(teams[1 - side], teams[side])
			var wall_ms: float = (Time.get_ticks_usec() - started) / 1000.0
			var id: String = str(decision.get("id", ""))
			if id.is_empty() or DB.char_def(id) == null or id in teams[0] or id in teams[1]:
				push_error("Illegal draft choice: %s turn %d" % [str(cfg.id), pick_index])
				valid = false
				failures += 1
				break
			teams[side].append(id)
			trace.append({"version": "1.4" if side == 0 else "1.3", "side": side,
				"turn": pick_index, "id": id, "wall_ms": wall_ms, "decision": decision})
			print("PICK ", cfg.id, " ", pick_index + 1, "/", count * 2, " v", trace.back().version,
				" ", id, " wall_ms=", snappedf(wall_ms, 0.1))
			director = null
			side = 1 - side
		output.store_line(JSON.stringify({"id": cfg.id, "config": cfg, "valid": valid,
			"new_team": teams[0], "old_team": teams[1], "picks": trace, "source_sha256": source_hashes,
			"roster_count": DB.ids().size(), "cache_shift": {"current": DraftDirector.SHIFT, "legacy": Legacy.SHIFT}}))
		output.flush()
	output.close()
	print("DRAFT_BENCHMARK completed=", inputs.size(), " failures=", failures)
	quit(0 if failures == 0 else 1)
