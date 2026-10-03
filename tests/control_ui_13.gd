extends Node

var checks: int = 0
var failures: int = 0
var records: Array = []

func _ready() -> void:
	# This test instantiates the full app and must use a separate settings folder.
	var isolated: bool = bool(ProjectSettings.get_setting("application/config/use_custom_user_dir", false))
	var directory: String = str(ProjectSettings.get_setting("application/config/custom_user_dir_name", ""))
	if not isolated or not directory.to_upper().contains("QA"):
		push_error("UI validation requires an isolated QA project with a custom QA user directory.")
		get_tree().quit(2)
		return
	_run.call_deferred()

func _check(condition: bool, label: String) -> void:
	records.append({"check": label, "passed": condition})
	if not condition:
		failures += 1
		push_error("FAIL " + label)
	else:
		checks += 1
		print("PASS ", label)

func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var app: App = scene.instantiate()
	get_tree().root.add_child(app)
	app.goto("setup", {"ruleset": "control"})
	await get_tree().process_frame
	var setup: SetupScreen = app.screens.setup
	_check(setup.ruleset == "control", "setup accepts control ruleset")
	_check(setup.arena_cards.filter(func(c): return c.visible).size() == 3, "control map filter has exactly 3 maps")
	_check(DB.arena(setup.arena_id).ruleset == "control", "selected map follows ruleset")
	setup._set_ruleset("elimination")
	_check(setup.arena_cards.filter(func(c): return c.visible).size() == 12, "elimination retains 12 maps")
	setup._set_ruleset("control")
	setup._start()
	await get_tree().process_frame
	var battle: BattleScreen = app.screens.battle
	battle.runner.paused = true
	_check(battle.runner.config.ruleset == "control", "ruleset reaches runner")
	_check(battle.runner.sim.max_time == 480.0, "control time limit is 480 seconds")
	_check(battle.objectives.visible, "objective rail is visible")
	_check(battle.view.cam_mode == "full", "large map starts in full camera")
	_check(battle.view.fog.vp.size.x == ceili(battle.runner.sim.arena.width * 0.25), "fog width follows map")
	_check(battle.view.fog.vp.size.y == ceili(battle.runner.sim.arena.height * 0.25), "fog height follows map")
	app.goto("draft", {"ruleset": "control"})
	var draft: DraftScreen = app.screens.draft
	_check(draft.arena_opt.item_count == 3, "draft control map filter")
	_check(str(draft.arena_opt.get_item_metadata(0)) == draft.arena_id, "draft selection metadata")
	draft._set_ruleset("elimination")
	_check(draft.arena_opt.item_count == 12, "draft elimination map filter")
	var sim: BattleSim = battle.runner.sim
	sim.time = 160.0
	sim.domination.scores = [300.0, 198.0]
	sim.domination.history = [[0.0, 0.0, 0.0], [40.0, 52.0, 35.0], [80.0, 150.0, 91.0], [120.0, 220.0, 146.0]]
	sim.heroes[0].st_capture_time = 25.0
	sim.heroes[0].st_captures = 3
	sim.heroes[0].st_zone_healing = 420.0
	sim.domination.history.append([sim.time, 300.0, 198.0])
	sim.finish(0, "control_score")
	app.show_result(sim.result(), battle.config)
	await get_tree().process_frame
	_check(app.current == "result", "control result screen builds")
	print("UI_VALIDATION_13 ", checks, " PASS / ", failures, " FAIL")
	var report_path: String = "res://reports/control_ui_13.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ui-report="):
			report_path = arg.substr(12)
	DirAccess.make_dir_recursive_absolute(report_path.get_base_dir())
	var file: FileAccess = FileAccess.open(report_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"suite": "control_ui_13", "passed": checks, "failed": failures, "isolated_user_dir": ProjectSettings.get_setting("application/config/custom_user_dir_name"), "result_fixture": true, "checks": records}, "  "))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-shot="):
			for frame in 20:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(arg.substr(10))
	battle.runner.dispose_sim()
	sim = null
	app.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(1 if failures else 0)
