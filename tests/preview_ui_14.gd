extends Node

var passed: int = 0
var failed: int = 0
var rows: Array = []
var measurements: Dictionary = {}
var app: App


func _ready() -> void:
	var custom: bool = bool(ProjectSettings.get_setting("application/config/use_custom_user_dir", false))
	var directory: String = str(ProjectSettings.get_setting("application/config/custom_user_dir_name", ""))
	if not custom or not directory.to_upper().contains("QA"):
		push_error("Run this full-UI test only in an isolated QA project/user directory.")
		get_tree().quit(2)
		return
	_run.call_deferred()


func _check(value: bool, label: String) -> void:
	rows.append({"check": label, "passed": value})
	if value:
		passed += 1
		print("PASS ", label)
	else:
		failed += 1
		push_error("FAIL " + label)


func _preview_layout(preview: SkillPreview, pixels: Vector2i) -> void:
	var tag: String = "%dx%d" % [pixels.x, pixels.y]
	var native_window: Window = get_window()
	var fullscreen: bool = DisplayServer.get_name() != "headless" and DisplayServer.screen_get_size() == pixels
	# Keep Window and DisplayServer state synchronized before changing the client size.
	# On Windows, switching mode and resizing in the same frame can retain the old
	# client dimensions (or apply the requested size to the decorated outer window).
	native_window.mode = Window.MODE_FULLSCREEN if fullscreen else Window.MODE_WINDOWED
	for frame in 3:
		await get_tree().process_frame
	await get_tree().create_timer(0.1).timeout
	if not fullscreen:
		native_window.size = pixels
	var settle_started: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - settle_started < 2000:
		await get_tree().process_frame
		if native_window.size == pixels and DisplayServer.window_get_size() == pixels:
			await RenderingServer.frame_post_draw
			if Vector2i(get_viewport().get_texture().get_size()) == pixels:
				break
	for frame in 15:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var rendered_image: Image = get_viewport().get_texture().get_image()
	var rendered_size: Vector2i = rendered_image.get_size()
	var visible_rect: Rect2 = (preview.get_parent() as Control).get_global_rect().intersection(app.get_global_rect())
	var controls_rect: Rect2 = preview.playback_controls.get_global_rect()
	var details_rect: Rect2 = preview.details_panel.get_global_rect()
	var canvas_rect: Rect2 = preview.canvas.get_global_rect()
	var tolerance: Rect2 = visible_rect.grow(1.0)
	_check(native_window.size == pixels and DisplayServer.window_get_size() == pixels, tag + " native render resolution matches")
	_check(rendered_size == pixels, tag + " rendered texture resolution matches")
	_check(absf(canvas_rect.size.x / canvas_rect.size.y - 16.0 / 9.0) < 0.01, tag + " preview retains 16:9 aspect")
	_check(tolerance.encloses(canvas_rect), tag + " preview canvas fits visible region")
	_check(tolerance.encloses(controls_rect), tag + " all playback controls stay visible")
	_check(tolerance.encloses(details_rect), tag + " description and conditions stay visible")
	_check(preview.get_combined_minimum_size().y <= visible_rect.size.y + 1.0, tag + " no vertical scroll is needed for playback or conditions")
	measurements["layout_" + tag] = {"visible_height": visible_rect.size.y, "canvas_width": canvas_rect.size.x, "canvas_height": canvas_rect.size.y, "controls_bottom": controls_rect.end.y, "conditions_bottom": details_rect.end.y, "visible_bottom": visible_rect.end.y,
		"actual_window_size": [native_window.size.x, native_window.size.y], "actual_display_size": [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y],
		"actual_render_size": [rendered_size.x, rendered_size.y], "window_mode": native_window.mode, "display_mode": DisplayServer.window_get_mode(),
		"screen_size": [DisplayServer.screen_get_size().x, DisplayServer.screen_get_size().y], "screen_usable_rect": str(DisplayServer.screen_get_usable_rect()),
		"settle_ms": Time.get_ticks_msec() - settle_started}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--layout-shots=") and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var shot_path: String = arg.substr(15).path_join("preview_responsive_" + tag + ".png")
			DirAccess.make_dir_recursive_absolute(shot_path.get_base_dir())
			rendered_image.save_png(shot_path)


func _run() -> void:
	app = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(app)
	app.goto("setup")
	await get_tree().process_frame
	var records_before: Dictionary = Settings.records.duplicate(true)
	var codex: CodexScreen = app.screens.codex
	var preview: SkillPreview = codex.preview
	_check(preview.scenario == null, "hidden codex does not create a simulation")
	_check(not (app.screens.setup as SetupScreen).detail.preview_enabled, "setup detail has no preview player")
	_check(not (app.screens.draft as DraftScreen).detail.preview_enabled, "draft detail has no preview player")
	app.goto("codex", {"character": "torturer", "entry": "active:2"})
	await get_tree().process_frame
	_check(preview.scenario != null and preview.entry_id == "active:2", "requested character and skill open")
	_check(preview.runner.sim == preview.scenario.sim and preview.view.sim == preview.scenario.sim, "runner and view share the scenario simulation")
	_check(not preview.runner.is_processing(), "preview facade cannot independently advance the simulation")
	_check(absf(preview.canvas.size.x / maxf(1, preview.canvas.size.y) - 16.0 / 9.0) < 0.04, "preview canvas keeps 16:9 aspect")
	preview.set_process(false)
	for i in 25:
		preview._process(0.1)
	_check(preview.scenario.cast_started, "preview dispatches a real ability")
	_check(preview.scenario.sim.warfare.prisons.size() > 0, "real prison terrain exists in the preview")
	await _preview_layout(preview, Vector2i(3440, 1440))
	await _preview_layout(preview, Vector2i(1600, 900))
	preview.toggle_playback()
	var paused_time: float = preview.scenario.elapsed
	preview._process(0.1)
	_check(preview.scenario.elapsed == paused_time, "pause freezes simulation time")
	preview.toggle_playback()
	preview.set_speed(2.0)
	preview._process(0.1)
	_check(preview.scenario.elapsed >= paused_time + 0.16, "2x speed advances twice the simulation time")
	var old: SkillPreviewScenario = preview.scenario
	preview.restart()
	_check(old.sim == null and preview.scenario != old, "restart disposes and replaces the previous scenario")
	_check(preview.scenario.elapsed == 0.0, "restart resets the timeline")
	old = null
	preview.repeating = false
	for i in 90:
		preview._process(0.1)
	_check(preview.finished and preview.runner.paused, "non-looping preview stops at its duration")
	preview.repeating = true
	var loops: int = preview.loop_count
	preview._process(0.9)
	_check(preview.loop_count == loops + 1 and preview.scenario.elapsed == 0.0, "loop starts a clean new scenario")
	preview.set_speed(1.0)
	for definition in DB.characters:
		codex._select_character(definition.id)
		preview.select_entry("active:0")
		preview._process(0.1)
		var selected: SkillPreviewScenario = preview.scenario
		if not definition.passives.is_empty():
			preview.select_entry("passive:0")
			_check(selected.sim == null, "%s rapid skill switch disposes old state" % definition.id)
			selected = null
		codex._mode("arenas")
		_check(preview.scenario == null and preview.view.sim == null and preview.runner.sim == null, "%s arena tab detaches all simulation references" % definition.id)
		await get_tree().process_frame
		codex._mode("chars")
		_check(preview.scenario != null and preview.scenario.elapsed == 0.0, "%s character tab restarts cleanly" % definition.id)
		await get_tree().process_frame
	app.goto("setup")
	await get_tree().process_frame
	_check(preview.scenario == null and not preview.view.visible, "leaving codex stops and disposes the preview")
	_check(Settings.records == records_before, "all preview operations preserve player records")
	app.start_battle({"blue": ["swordsman"], "red": ["giant"], "arena_id": "classic", "seed": 1414}, "setup")
	var battle: BattleScreen = app.screens.battle
	battle.runner.paused = true
	var battle_sim: BattleSim = battle.runner.sim
	var battle_time: float = battle_sim.time
	app.goto("codex", {"character": "politician", "entry": "passive:0"})
	preview._process(0.1)
	app.goto("setup")
	_check(battle.runner.sim == battle_sim and battle_sim.time == battle_time, "preview leaves an existing match untouched")
	battle.runner.dispose_sim()
	battle_sim = null
	app.goto("draft")
	var draft: DraftScreen = app.screens.draft
	draft._reset()
	draft.user = ["politician"]
	draft._ai_think()
	draft._refresh()
	draft._process(0.02)
	_check(draft.director != null and draft.search_controls.visible, "draft exposes incremental search progress")
	var cancel_start: int = Time.get_ticks_usec()
	draft._search_button_pressed()
	measurements["cancel_ms"] = (Time.get_ticks_usec() - cancel_start) / 1000.0
	_check(draft.director == null and draft.turn == "ai_paused", "draft cancellation releases the search")
	_check(draft.user == ["politician"] and draft.ai.is_empty(), "cancel preserves the chosen roster")
	draft._search_button_pressed()
	_check(draft.director != null and draft.turn == "ai", "cancelled search can restart")
	app.goto("setup")
	_check(draft.director == null and draft.turn == "ai_paused", "leaving draft cancels active search")
	app.goto("draft")
	draft._reset()
	draft._set_team_size(5)
	draft.user = ["swordsman", "archer", "mage", "giant", "politician"]
	draft.ai = ["werewolf", "sniper", "metatron", "engineer"]
	draft.seed_edit.text = "1414"
	var started: int = Time.get_ticks_usec()
	draft._ai_think()
	# This fixture exercises rollout rendering even when calibration separates the finalists.
	# Measure that separation without rollout; keep the production gate unchanged.
	var static_opts: Dictionary = draft.director.search_options.duplicate(true)
	static_opts["rollout_enabled"] = false
	var static_result: Dictionary = DraftDirector.new(static_opts).decide(draft.user, draft.ai)
	var alternatives: Array = static_result.get("alternatives", [])
	_check(not alternatives.is_empty(), "final pick fixture has two scored candidates")
	if not alternatives.is_empty():
		var static_gap: float = float(static_result.search_score) - float(alternatives[0].search_score)
		_check(is_finite(static_gap) and static_gap >= 0.0, "final pick fixture measures a valid score gap")
		if is_finite(static_gap) and static_gap >= 0.0:
			measurements["final_static_gap"] = static_gap
			measurements["fixture_rollout_gap"] = static_gap + 1.0
			draft.director.search_options["rollout_gap"] = static_gap + 1.0
			draft.director.begin(draft.user.duplicate(), draft.ai.duplicate())
	draft._refresh()
	var frames: int = 0
	while draft.turn == "ai" and Time.get_ticks_usec() - started < 90000000:
		await get_tree().process_frame
		frames += 1
	measurements["final_5v5_seconds"] = (Time.get_ticks_usec() - started) / 1000000.0
	measurements["final_5v5_frames"] = frames
	measurements["search_peak_slice_ms"] = draft.search_peak_ms
	measurements["render_backend"] = DisplayServer.get_name()
	_check(draft.turn == "done" and draft.ai.size() == 5, "incremental final 5v5 pick completes")
	_check(not draft.decision.is_empty() and int(draft.decision.get("search", {}).get("rollout", {}).get("games", 0)) > 0, "final pick uses actual battle verification")
	_check(Settings.records == records_before, "UI validation does not write player records")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-shot=") and DisplayServer.get_name() != "headless":
			for frame in 15:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(arg.substr(10))
	var output: String = "res://reports/preview_ui_14.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ui-report="):
			output = arg.substr(12)
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var file: FileAccess = FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify({"suite": "preview_ui_14", "status": "PASS" if failed == 0 else "FAIL", "passed": passed, "failed": failed, "measurements": measurements, "checks": rows}, "  "))
	print("PREVIEW_UI_14 ", passed, " PASS / ", failed, " FAIL ", JSON.stringify(measurements))
	draft._cancel_search()
	preview.set_active(false)
	app.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0 if failed == 0 else 1)
