extends SceneTree

const ARENAS: Array[String] = ["classic", "ruined_gate", "thorn_circuit", "furnace_basin", "wind_temple", "dimensional_lattice",
	"crossroads", "moon_garden", "twin_foundry", "gale_corridor", "rift_harbor", "bastion_ring",
	"control_crossroads", "control_citadel", "control_waterway"]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DB.ensure_loaded()
	var output: String = "res://reports/first_pick_v2.json"
	var only_seed: int = -1
	var only_size: int = -1
	var only_arena: String = ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output = arg.substr(6)
		if arg.begins_with("--seed="): only_seed = int(arg.substr(7))
		if arg.begins_with("--team-size="): only_size = int(arg.substr(12))
		if arg.begins_with("--arena="): only_arena = arg.substr(8)
	if not only_arena.is_empty() and (not ARENAS.has(only_arena) or only_seed not in [1, 2, 3] or only_size not in [1, 3]):
		push_error("A single --arena measurement requires a valid --seed and --team-size")
		quit(1)
		return
	var rows: Array = []
	var groups: Array = []
	var accepted: bool = true
	for size: int in [1, 3]:
		if only_size >= 0 and only_size != size: continue
		for seed_value: int in [1, 2, 3]:
			if only_seed >= 0 and only_seed != seed_value: continue
			var counts: Dictionary = {}
			for arena_id: String in ARENAS:
				if not only_arena.is_empty() and arena_id != only_arena: continue
				var director: DraftDirector = DraftDirector.new({"team_size": size, "arena_id": arena_id,
					"ruleset": "control" if arena_id.begins_with("control_") else "elimination", "seed": seed_value})
				var decision: Dictionary = director.decide([], [])
				var id: String = str(decision.get("id", ""))
				if DB.char_def(id) == null:
					push_error("First-pick audit produced an invalid hero: " + id)
					quit(1)
					return
				counts[id] = int(counts.get(id, 0)) + 1
				rows.append({"team_size": size, "seed": seed_value, "arena_id": arena_id, "id": id,
					"score": decision.score, "score_basis": decision.score_basis, "search": decision.search})
				print("FIRST_PICK size=", size, " seed=", seed_value, " arena=", arena_id, " id=", id)
				director.cancel()
			var most: int = 0
			for value in counts.values(): most = maxi(most, int(value))
			var ok: bool = int(counts.get("werewolf", 0)) <= 3 and most <= 5
			accepted = accepted and ok
			groups.append({"team_size": size, "seed": seed_value, "counts": counts, "maps": ARENAS.size(),
				"werewolf": int(counts.get("werewolf", 0)), "maximum_hero": most, "status": "PASS" if ok else "FAIL"})
	if groups.is_empty():
		push_error("No valid first-pick audit group selected")
		quit(1)
		return
	var report: Dictionary = {"status": "PASS" if accepted else "FAIL", "rows": rows, "groups": groups,
		"criteria": {"werewolf_max_per_15": 3, "any_hero_max_per_15": 5}, "roster": DB.ids()}
	if not only_arena.is_empty():
		# A single pick is evidence only; acceptance requires the full 15-map group.
		report.status = "MEASURED"
		report["scope"] = "single_pick"
		report.groups = []
	else:
		report["scope"] = "groups"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	var file: FileAccess = FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write first-pick audit: " + output)
		quit(1)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		push_error("Cannot finish first-pick audit report: " + output)
		quit(1)
		return
	print("FIRST_PICK_AUDIT ", JSON.stringify({"status": report.status, "groups": report.groups, "cases": rows.size()}))
	# Acceptance misses are reported, never hidden by changing director weights.
	quit(0)
