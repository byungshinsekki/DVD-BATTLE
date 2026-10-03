extends SceneTree

# Same-process replay catches preview side effects that file hashes cannot detect.
const Preview = preload("res://scripts/preview/skill_preview_scenario.gd")
var passed: int = 0
var failed: Array = []

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if condition: passed += 1
	else: failed.append(message)

func _match_signature(arena: String, seed_value: int) -> String:
	var sim: BattleSim = BattleSim.new({"blue": ["politician", "torturer", "dimensionalist"],
		"red": ["hive_mind", "world_tree", "engineer"], "arena_id": arena, "seed": seed_value, "max_time": 40.0})
	sim.controllers[0] = AIFactory.make("tactician", sim, 0)
	sim.controllers[1] = AIFactory.make("tactician", sim, 1)
	sim.start()
	while sim.state == BattleSim.RUNNING: sim.step()
	var units: Array = []
	for u: BUnit in sim.heroes:
		units.append([u.id, u.hp, u.pos, u.st_damage, u.st_healing, u.st_casts])
	var signature: String = JSON.stringify([sim.result().winner, sim.time, units,
		sim.domination.scores if sim.is_control_mode() else []]).sha256_text()
	sim.dispose()
	return signature

func _run() -> void:
	DB.ensure_loaded()
	var settings: Node = root.get_node_or_null("Settings")
	var records_before: String = JSON.stringify(settings.get("records")) if settings else ""
	var path: String = "user://settings.cfg"
	var disk_before: String = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "absent"
	var before: Array = [_match_signature("classic", 140081), _match_signature("control_citadel", 140082)]
	var entries: int = 0
	for d in DB.characters:
		for entry in Preview.entries(d.id):
			var scenario = Preview.new(d.id, entry.id)
			var steps: int = 0
			while not scenario.finished and steps < 900:
				scenario.step()
				steps += 1
			_check(scenario.finished and steps < 900, "%s/%s terminated" % [d.id, entry.id])
			scenario.dispose()
			_check(scenario.sim == null and not scenario.step(), "%s/%s disposed safely" % [d.id, entry.id])
			scenario = null
			entries += 1
		await process_frame
	var after: Array = [_match_signature("classic", 140081), _match_signature("control_citadel", 140082)]
	_check(before[0] == after[0], "Elimination replay unchanged after every preview")
	_check(before[1] == after[1], "Control replay unchanged after every preview")
	_check(records_before == (JSON.stringify(settings.get("records")) if settings else ""), "In-memory records unchanged")
	_check(disk_before == (FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "absent"), "On-disk settings unchanged")
	var output: Dictionary = {"status": "PASS" if failed.is_empty() else "FAIL", "passed": passed, "failed": failed,
		"entries": entries, "replay_before": before, "replay_after": after, "matches": 4}
	var file: FileAccess = FileAccess.open("res://reports/preview_isolation_14.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(output, "\t"))
	file.close()
	print("PREVIEW_ISOLATION_14 ", JSON.stringify(output))
	quit(0 if failed.is_empty() else 1)
