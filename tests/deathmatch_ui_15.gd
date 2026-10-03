extends Node

# Full-app deathmatch flow: home card, setup screen, battle screen widgets and
# panels, perspective switching, result screen. Needs an isolated QA project.

var checks: int = 0
var failures: int = 0
var records: Array = []
var shots: Dictionary = {}


func _ready() -> void:
	var isolated: bool = bool(ProjectSettings.get_setting("application/config/use_custom_user_dir", false))
	var directory: String = str(ProjectSettings.get_setting("application/config/custom_user_dir_name", ""))
	if not isolated or not directory.to_upper().contains("QA"):
		push_error("UI validation requires an isolated QA project with a custom QA user directory.")
		get_tree().quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-dir="):
			shots["dir"] = arg.substr(9)
	_run.call_deferred()


func _check(condition: bool, label: String) -> void:
	records.append({"check": label, "passed": condition})
	if not condition:
		failures += 1
		push_error("FAIL " + label)
	else:
		checks += 1
		print("PASS ", label)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	if not shots.has("dir") or DisplayServer.get_name() == "headless":
		return
	await _frames(12)
	await RenderingServer.frame_post_draw
	var path: String = str(shots.dir).path_join(name + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	print("SHOT ", path)


func _find_text(node: Node, text: String) -> bool:
	if (node is Label and (node as Label).text.contains(text)) or (node is Button and (node as Button).text.contains(text)):
		return true
	for c in node.get_children():
		if _find_text(c, text):
			return true
	return false


func _run() -> void:
	var records_before: String = JSON.stringify(Settings.records)
	var scene: PackedScene = load("res://scenes/main.tscn")
	var app: App = scene.instantiate()
	get_tree().root.add_child(app)
	await _frames(3)
	_check(App.VERSION == "V2 프리뷰 · 드래프트 핫픽스", "app version V2 preview")
	_check(app.nav_buttons.has("deathmatch"), "sidebar has the deathmatch entry")
	_check(_find_text(app.screens.home, "데스매치"), "home shows the deathmatch mode card")
	_check(_find_text(app.screens.home, "V2 프리뷰"), "home lists the V2 preview changes")
	await _shot("home_15")

	app.goto("deathmatch")
	await _frames(3)
	var dm: DeathmatchScreen = app.screens.deathmatch
	_check(app.current == "deathmatch", "deathmatch setup opens")
	_check(dm.players.size() == 8 and not dm.start_btn.disabled, "defaults to 8 random participants, ready to start")
	_check(dm.map_cards.size() == 3, "three procedural maps offered")
	var seen: Dictionary = {}
	for id in dm.players:
		seen[id] = true
	_check(seen.size() == dm.players.size(), "participants are distinct")
	dm._set_player_count(12)
	_check(dm.players.size() == 8 and dm.start_btn.disabled, "raising the count waits for new picks")
	dm._fill_rest()
	_check(dm.players.size() == 12 and not dm.start_btn.disabled, "fill completes 12 participants")
	dm._set_player_count(4)
	_check(dm.players.size() == 4, "lowering the count trims the list")
	dm._set_player_count(12)
	dm._fill_rest()
	dm._set_kills(5)
	dm._set_time(180.0)
	dm.seed_edit.text = "4242"
	dm._rebuild_maps(true)
	dm._set_map("dm_ruined_town")
	_check((dm.map_cards["dm_ruined_town"] as ArenaCard).arena.data.get("preset", "") == "dm_ruined_town" and (dm.map_cards["dm_ruined_town"] as ArenaCard).selected, "map selection")
	dm.right_tabs.current_tab = 1
	await _frames(2)
	_check(dm.items_wrap.visible and _find_text(dm.items_wrap, "용의 심장") and _find_text(dm.items_wrap, "전설 4종"), "item codex lists the items by rarity")
	await _shot("deathmatch_setup_15")
	dm.right_tabs.current_tab = 0
	var chosen: Array = dm.players.duplicate()
	dm._start()
	await _frames(3)
	var battle: BattleScreen = app.screens.battle
	var sim: BattleSim = battle.runner.sim
	_check(app.current == "battle" and battle.dm, "battle screen in deathmatch mode")
	_check(battle.runner.config.ruleset == "deathmatch" and sim.is_deathmatch(), "ruleset reaches the runner")
	_check(sim.team_count == 12 and sim.heroes.size() == 12, "12 participants in the battle")
	var ids: Array = []
	for u in sim.heroes:
		ids.append(u.def.id)
	_check(ids == chosen, "participants in chosen order")
	_check(sim.deathmatch.kill_target == 5 and is_equal_approx(sim.max_time, 180.0), "kill target and time limit applied")
	_check(str(sim.arena.data.get("preset", "")) == "dm_ruined_town" and sim.seed_value == 4242, "map and seed applied")
	_check(battle.dm_chips.size() == 12, "12 scoreboard chips")
	_check(battle.dm_view_opt.visible and battle.dm_view_opt.item_count == 13, "perspective picker lists every participant")
	_check(not battle.team_tags[0].visible and not battle.team_tags[1].visible, "team tags hidden")
	var titles: Array = []
	for i in battle.tabs.tab_count:
		titles.append(battle.tabs.get_tab_title(i))
	_check(titles == ["순위", "유닛", "이벤트", "AI 판단"], "deathmatch panel tabs")
	battle.runner.warp(40.0)
	battle.runner.paused = false
	battle.runner.speed = 4.0
	await _frames(30)
	var target: BUnit = null
	for u in sim.heroes:
		if u.alive:
			target = u
			break
	battle._select(target.idx)
	for tab in 4:
		battle.tabs.current_tab = tab
		await _frames(2)
		_check(battle.tab_body.get_child_count() > 0 or battle.log_rt.visible, "panel %s renders" % titles[tab])
	battle.tabs.current_tab = 3
	battle._refresh_panel(true)
	await _frames(2)
	_check(_find_text(battle.tab_body, "이게 나에게 필요한가"), "AI panel explains item decisions")
	_check(_find_text(battle.tab_body, "초째 유지"), "AI panel shows the current intent")
	await _shot("deathmatch_battle_ai_15")
	battle.tabs.current_tab = 0
	battle._refresh_panel(true)
	await _frames(2)
	_check(_find_text(battle.tab_body, "킬"), "ranking panel lists kills")
	await _shot("deathmatch_battle_rank_15")
	battle._set_vision(target.team)
	await _frames(3)
	_check(battle.view.perspective == target.team and battle.dm_view_opt.selected == target.team + 1, "perspective follows the picker")
	_check(battle.view.fog.visible, "fog of war on in a participant view")
	await _shot("deathmatch_battle_view_15")
	battle._set_vision(-1)
	await _frames(2)
	_check(battle.view.perspective == -1 and not battle.view.fog.visible, "spectator view restored")
	_check(battle.view.cam_mode == "auto", "camera follows the selection")
	battle.runner.paused = true
	# Finish with a real result object.
	var leader: BUnit = sim.heroes[0]
	sim.deathmatch.kills[leader.team] = 5
	sim.deathmatch.check_end()
	_check(sim.state != BattleSim.RUNNING and sim.finish_reason == "deathmatch_kills", "kill target ends the battle")
	var result: Dictionary = sim.result()
	app.show_result(result, battle.config)
	await _frames(3)
	_check(app.current == "result", "deathmatch result screen opens")
	var rs: ResultScreen = app.screens.result
	_check(_find_text(rs, "우승") and _find_text(rs, "처치 경쟁"), "result shows the winner and the kill race")
	_check(_find_text(rs, leader.def.name), "winner named")
	await _shot("deathmatch_result_15")
	_check(app.nav_buttons.deathmatch.button_pressed, "result keeps the deathmatch nav highlighted")
	battle.runner.dispose_sim()
	sim = null
	app.goto("home")
	await _frames(2)
	_check(JSON.stringify(Settings.records).length() > 0, "records still readable")
	print("UI_VALIDATION_15 ", checks, " PASS / ", failures, " FAIL")
	var report_path: String = "res://reports/deathmatch_ui_15.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ui-report="):
			report_path = arg.substr(12)
	DirAccess.make_dir_recursive_absolute(report_path.get_base_dir())
	var file: FileAccess = FileAccess.open(report_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"suite": "deathmatch_ui_15", "passed": checks, "failed": failures, "isolated_user_dir": ProjectSettings.get_setting("application/config/custom_user_dir_name"), "records_before": records_before, "checks": records}, "  "))
	app.queue_free()
	await _frames(2)
	get_tree().quit(1 if failures else 0)
