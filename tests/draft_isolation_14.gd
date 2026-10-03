extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func signature() -> String:
	var sim: BattleSim = BattleSim.new({"blue": ["world_tree", "politician", "archer"],
		"red": ["torturer", "engineer", "hermes"], "arena_id": "control_crossroads", "seed": 149881, "max_time": 45.0})
	sim.controllers[0] = AIFactory.make("tactician", sim, 0)
	sim.controllers[1] = AIFactory.make("tactician", sim, 1)
	sim.start()
	while sim.state == BattleSim.RUNNING: sim.step()
	var units: Array = []
	for u: BUnit in sim.heroes:
		units.append([u.id, u.hp, u.pos, u.st_casts, u.st_damage])
	var result: String = JSON.stringify([sim.winner, sim.time, sim.domination.scores, units]).sha256_text()
	sim.dispose()
	return result

func _run() -> void:
	DB.ensure_loaded()
	var before: String = signature()
	var settings: Node = root.get_node_or_null("Settings")
	var records_before: String = JSON.stringify(settings.get("records")) if settings else ""
	var disk_before: String = FileAccess.get_sha256("user://settings.cfg") if FileAccess.file_exists("user://settings.cfg") else "absent"
	# V1.5.3 (DR-3): force the gated engine check so the isolation of real
	# hypothetical matches is still exercised. A control check plays one
	# paired 60 s game per finalist (two games, formerly four 20 s games).
	var director: DraftDirector = DraftDirector.new({"team_size": 3, "arena_id": "control_crossroads", "seed": 140009, "rollout_gap": 1.0})
	var decision: Dictionary = director.decide(["world_tree", "politician", "archer"], ["torturer", "engineer"])
	var after: String = signature()
	var checks: Dictionary = {
		"hypothetical_matches_executed": int(decision.search.rollout.games) == 2,
		"same_process_battle_unchanged": before == after,
		"records_unchanged": records_before == (JSON.stringify(settings.get("records")) if settings else ""),
		"disk_unchanged": disk_before == (FileAccess.get_sha256("user://settings.cfg") if FileAccess.file_exists("user://settings.cfg") else "absent")}
	var failed: Array = []
	for key in checks:
		if not checks[key]: failed.append(key)
	var output: Dictionary = {"status": "PASS" if failed.is_empty() else "FAIL", "passed": checks.size() - failed.size(),
		"failed": failed, "checks": checks, "before": before, "after": after, "comparison_matches": 2}
	var file: FileAccess = FileAccess.open("res://reports/draft_isolation_14.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(output, "\t"))
	file.close()
	print("DRAFT_ISOLATION_14 ", JSON.stringify(output))
	director.cancel()
	quit(0 if failed.is_empty() else 1)
