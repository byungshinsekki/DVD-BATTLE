extends SceneTree

# Run before changing TEAM selection or regenerating the table. Both --before
# and --before-search must be unmodified C5 snapshots. The previous director
# receives its own previous search script, never the changed production search.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DB.ensure_loaded()
	var before: String = ""
	var before_search: String = ""
	var output: String = "res://reports/draft_bugfix_v2.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--before="): before = arg.substr(9)
		if arg.begins_with("--before-search="): before_search = arg.substr(16)
		if arg.begins_with("--out="): output = arg.substr(6)
	if DB.ids().size() != 22 or before.is_empty() or not FileAccess.file_exists(before) or before_search.is_empty() or not FileAccess.file_exists(before_search):
		push_error("Paired audit requires a 22-hero roster and both original director/search snapshots")
		quit(1)
		return
	var old_search: GDScript = GDScript.new()
	old_search.source_code = FileAccess.get_file_as_string(before_search).replace("class_name DraftSearch14", "")
	if old_search.reload() != OK:
		quit(1)
		return
	var old: GDScript = GDScript.new()
	var original_source: String = FileAccess.get_file_as_string(before)
	var search_preload: String = 'preload("res://scripts/ai/draft_search.gd")'
	if original_source.count(search_preload) != 1:
		push_error("Original director search preload contract changed")
		quit(1)
		return
	old.source_code = original_source.replace("class_name DraftDirector", "").replace(search_preload, "_audit_search_script") + "\nvar _audit_search_script: GDScript\n"
	if old.reload() != OK:
		quit(1)
		return
	var rows: Array = []
	var failed: Array = []
	for mode: String in ["elimination", "control"]:
		for size: int in [1, 3, 5]:
			for budget: int in [1, 21, 22, 23, 800, 4500]:
				for occupied: bool in [false, true]:
					var options: Dictionary = {"ruleset": mode, "arena_id": "classic" if mode == "elimination" else "control_crossroads",
						"team_size": size, "seed": 200606, "budget": budget, "rollout_enabled": false}
					var user: Array = ["archer"] if occupied else []
					var previous: RefCounted = old.new(options)
					previous.set("_audit_search_script", old_search)
					var current: DraftDirector = DraftDirector.new(options)
					var a: Dictionary = previous.decide(user, [])
					var b: Dictionary = current.decide(user, [])
					var equal: bool = a == b
					var label: String = "%s/%d/%d/%s" % [mode, size, budget, str(occupied)]
					if not equal: failed.append(label)
					rows.append({"case": label, "same": equal, "before": a, "after": b})
					previous.cancel()
					current.cancel()
	var report: Dictionary = {"status": "PASS" if failed.is_empty() else "FAIL", "passed": rows.size() - failed.size(),
		"failed": failed, "rows": rows, "roster_count": DB.ids().size(), "before_sha": FileAccess.get_sha256(before),
		"before_search_sha": FileAccess.get_sha256(before_search), "after_sha": FileAccess.get_sha256("res://scripts/ai/draft_director.gd"),
		"after_search_sha": FileAccess.get_sha256("res://scripts/ai/draft_search.gd"), "rollout_enabled": false}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	var file: FileAccess = FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write paired draft audit report: " + output)
		quit(1)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		push_error("Cannot finish paired draft audit report: " + output)
		quit(1)
		return
	print("DRAFT_BUGFIX_V2 ", JSON.stringify({"status": report.status, "passed": report.passed, "failed": failed}))
	quit(0 if failed.is_empty() else 1)
