extends Node

var passed: int = 0
var failed: Array = []
var rows: Array = []
var output: String = "res://reports/developer_152.json"
var shot_dir: String = ""


func _ready() -> void:
	var profile: String = str(ProjectSettings.get_setting("application/config/custom_user_dir_name", ""))
	if not profile.contains("QA"):
		push_error("Developer UI validation requires a separate QA profile")
		get_tree().quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): output = arg.substr(9)
		if arg.begins_with("--qa-dir="): shot_dir = arg.substr(9)
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	rows.append({"check": label, "passed": ok})
	if ok:
		passed += 1
	else:
		failed.append(label)
		push_error("FAIL " + label)


func frames(n: int = 3) -> void:
	for i in n: await get_tree().process_frame


func signature(sim: BattleSim) -> String:
	var states: Array = []
	for unit in sim.heroes:
		states.append([unit.idx, unit.pos, unit.hp, Array(unit.cooldowns), unit.alive])
	# Log entries carry AbilityDef objects; borrowed (virtual) abilities are new objects in
	# every battle, so compare them by id instead of by object address.
	var log_rows: Array = []
	for entry in sim.log:
		var row: Dictionary = (entry as Dictionary).duplicate()
		for k in row.keys():
			if row[k] is Object:
				var o: Object = row[k]
				row[k] = str(o.get("id")) if "id" in o else o.get_class()
		log_rows.append(row)
	return JSON.stringify([sim.tick, states, log_rows, sim.env.state_snapshot()])


func shot(label: String) -> void:
	if shot_dir == "" or DisplayServer.get_name() == "headless": return
	await frames(8)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shot_dir.path_join(label + ".png"))


## The Settings autoload looked up at run time, so this file also compiles when it is
## loaded through --script (autoload globals are not registered there).
func _settings() -> Node:
	return get_node("/root/Settings")


# V1.5.3 lab: map picker facts, per-type switches, gimmick presets, environment rows.
func _gimmick_lab(lab: DeveloperScreen) -> void:
	lab.mode_option.select(0)
	lab._change_mode()
	var texts_ok: bool = true
	for i in lab.map_option.item_count:
		var a: Arena = DB.arena(lab.map_ids[i])
		var t: String = lab.map_option.get_item_text(i)
		if not (t.contains("%d×%d" % [int(a.width), int(a.height)]) and t.contains(CodexData.orientation_label(a))):
			texts_ok = false
	check(texts_ok, "map picker shows size and spawn orientation")
	var gate_index: int = lab.map_ids.find("ruined_gate")
	lab.map_option.select(gate_index)
	lab._map_hint()
	check(lab.type_buttons["gate"].visible and lab.type_buttons["shockwave"].visible and not lab.type_buttons["mud"].visible, "type switches show the map's gimmicks only")
	check(lab.hint_label.text.contains("개폐 성문"), "map hint lists the gimmicks")
	lab.start_case()
	var sim: BattleSim = lab.runner.sim
	lab.advance_ticks(3)
	(lab.type_buttons["gate"] as Button).button_pressed = false
	check(not sim.env.is_type_enabled("gate") and sim.env.enabled, "gate switch turns only gates off")
	check(sim.arena.gate_bits == sim.arena.all_gates_open_bits(), "switched-off gates stand open")
	check(lab.interventions.back() == {"tick": 3, "type": "gate", "enabled": false}, "type switch records its intervention tick")
	var gate_line: bool = false
	for line in lab.inspector.text.split("\n"):
		if line.begins_with("개폐 성문") and line.contains("꺼짐"):
			gate_line = true
	check(gate_line, "inspector shows the gate row state")
	lab.restart_case()
	check(lab.runner.sim.env.is_type_enabled("gate") and lab.interventions.is_empty() and (lab.type_buttons["gate"] as Button).button_pressed,
		"restart restores the per-type state the case started with")
	(lab.type_buttons["gate"] as Button).button_pressed = false
	lab.start_case()
	check(not lab.runner.sim.env.is_type_enabled("gate") and lab.runner.sim.env.enabled, "new case starts with the switch state")
	(lab.type_buttons["gate"] as Button).button_pressed = true
	check(lab.runner.sim.env.is_type_enabled("gate"), "switch turns gates back on")
	_public_in_team_view(lab, _step_until(lab, "ENV_GATE", 450), "gate open/close")
	var preset_ring: int = -1
	for i in DeveloperScreen.GIMMICK_PRESETS.size():
		if str(DeveloperScreen.GIMMICK_PRESETS[i][2]) == "bastion_ring":
			preset_ring = i
	# The fast-forward runs in frame-budgeted chunks (review 1.5.3: a synchronous
	# 1020-1800 tick loop froze the window for 4-11 s with 0 frames drawn).
	var seen: Dictionary = {"frames": 0, "disabled": false}
	var counter: Callable = func():
		seen.frames = int(seen.frames) + 1
		if lab.preset_option.disabled:
			seen.disabled = true
	get_tree().process_frame.connect(counter)
	await lab.run_preset(preset_ring)
	get_tree().process_frame.disconnect(counter)
	check(lab.runner.sim.arena.id == "bastion_ring" and lab.runner.paused and lab.runner.sim.tick >= 1020, "ring preset starts the ring map and advances")
	check(int(seen.frames) > 0, "ring preset keeps drawing frames while it fast-forwards (%d frames)" % int(seen.frames))
	check(bool(seen.disabled) and not lab.preset_option.disabled, "preset picker is disabled while a preset runs and enabled again afterwards")
	check(lab.runner.sim.tick == int(DeveloperScreen.GIMMICK_PRESETS[preset_ring][3]), "ring preset stops exactly on its tick (%d)" % lab.runner.sim.tick)
	# Chunked fast-forward = the same step sequence as manual stepping.
	var preset_sig: String = signature(lab.runner.sim)
	lab.restart_case()
	var left: int = int(DeveloperScreen.GIMMICK_PRESETS[preset_ring][3])
	while left > 0:
		lab.advance_ticks(mini(left, 300))
		left -= 300
	check(signature(lab.runner.sim) == preset_sig, "preset fast-forward reproduces manual stepping exactly")
	# Ring start banner: public, so it also shows in a team perspective.
	var ring_ev: Dictionary = _step_until(lab, "ENV_RING", 90)
	_public_in_team_view(lab, ring_ev, "closing-ring start")
	var ring_line: bool = false
	for line in lab.inspector.text.split("\n"):
		if line.begins_with("결계 수축") and line.contains("안전 반경"):
			ring_line = true
	check(ring_line, "inspector shows the closing-ring radius")
	# A new case started while a preset is still fast-forwarding stops the old loop.
	lab.run_preset(preset_ring)
	await frames(2)
	var mid_run: bool = lab.preset_option.disabled
	lab.start_case()
	var fresh: BattleSim = lab.runner.sim
	await frames(4)
	check(mid_run and lab.runner.sim == fresh and fresh.tick == 0 and not lab.preset_option.disabled, "starting a new case mid-preset stops the old fast-forward (tick %d)" % fresh.tick)
	var art: int = -1
	for i in DeveloperScreen.GIMMICK_PRESETS.size():
		if str(DeveloperScreen.GIMMICK_PRESETS[i][2]) == "twin_foundry":
			art = i
	await lab.run_preset(art)
	check(lab.runner.sim.arena.id == "twin_foundry" and lab.type_buttons["artillery"].visible, "artillery preset")
	_public_in_team_view(lab, _step_until(lab, "ENV_ARTILLERY", 330), "artillery warning")
	for typ in DeveloperScreen.TYPE_ORDER:
		check(Arena.type_bit(typ) != 0 and CodexData.HAZARDS.has(typ), "lab switch %s maps to an engine type and a codex entry" % typ)
	await _layer_switches(lab)
	await frames(2)


## Steps the lab's case until an event of `type` is logged (at most `max_ticks`).
func _step_until(lab: DeveloperScreen, type: String, max_ticks: int) -> Dictionary:
	var sim: BattleSim = lab.runner.sim
	for i in max_ticks:
		for k in range(sim.log.size() - 1, -1, -1):
			if str(sim.log[k].get("type", "")) == type:
				return sim.log[k]
		if lab.runner.done:
			break
		lab.advance_ticks(1)
	return {}


## Public gimmick events (gates, salvo warnings, ring phases) are shown in every
## perspective; a private event nobody on the team saw stays hidden (review 1.5.3:
## the view dropped the public ones in team perspectives).
func _public_in_team_view(lab: DeveloperScreen, ev: Dictionary, label: String) -> void:
	check(not ev.is_empty() and ev.has("sv") and not bool(ev.sv[0]) and not bool(ev.gv[0]), "%s event is emitted as a source-less environment event" % label)
	lab.perspective_option.select(1)
	lab.perspective_option.item_selected.emit(1)
	check(lab.view.perspective == 0 and not ev.is_empty() and lab.view._ev_vis(ev), "%s effects show in a team perspective" % label)
	var hidden: Dictionary = {"type": "HEALTH_DAMAGED", "s": -1, "g": -1, "sv": [false, false], "gv": [false, false], "pos": Vector2.ZERO}
	check(not lab.view._ev_vis(hidden), "%s: unseen private events stay hidden in a team perspective" % label)
	lab.perspective_option.select(0)
	lab.perspective_option.item_selected.emit(0)


# Brush and mud follow their switches on screen (review 1.5.3: both stayed drawn
# in the static floor / canopy layers, and the master switch never redrew them).
# Samples the rendered lab viewport, so it only runs with a renderer.
func _layer_switches(lab: DeveloperScreen) -> void:
	if DisplayServer.get_name() == "headless":
		check(true, "layer switch pixels skipped headless")
		return
	lab.mode_option.select(0)
	lab._change_mode()
	lab.map_option.select(lab.map_ids.find("gale_corridor"))
	lab._map_hint()
	lab.start_case()
	var mud_pts: Array = []
	for x in [560.0, 600.0, 640.0, 680.0]:
		for y in [530.0, 570.0, 610.0]:
			mud_pts.append(Vector2(x, y))
	var mud_on: Color = await _sample(lab, mud_pts)
	(lab.type_buttons["mud"] as Button).button_pressed = false
	var mud_off: Color = await _sample(lab, mud_pts)
	(lab.type_buttons["mud"] as Button).button_pressed = true
	var mud_back: Color = await _sample(lab, mud_pts)
	lab.environment_toggle.button_pressed = false
	var mud_master: Color = await _sample(lab, mud_pts)
	lab.environment_toggle.button_pressed = true
	var mud_master_back: Color = await _sample(lab, mud_pts)
	check(_cdist(mud_on, mud_off) > 0.05 and _cdist(mud_on, mud_back) < 0.015,
		"mud floor disappears with its switch and comes back (%s / %s / %s)" % [mud_on.to_html(false), mud_off.to_html(false), mud_back.to_html(false)])
	check(_cdist(mud_off, mud_master) < 0.015 and _cdist(mud_on, mud_master_back) < 0.015,
		"master environment switch redraws the mud floor too (%s / %s)" % [mud_master.to_html(false), mud_master_back.to_html(false)])
	lab.map_option.select(lab.map_ids.find("moon_garden"))
	lab._map_hint()
	lab.start_case()
	var brush_pts: Array = []
	for x in [540.0, 560.0, 580.0, 610.0, 630.0]:
		for y in [112.0, 128.0, 144.0]:
			brush_pts.append(Vector2(x, y))
	var brush_on: Color = await _sample(lab, brush_pts)
	(lab.type_buttons["brush"] as Button).button_pressed = false
	var brush_off: Color = await _sample(lab, brush_pts)
	(lab.type_buttons["brush"] as Button).button_pressed = true
	var brush_back: Color = await _sample(lab, brush_pts)
	check(_cdist(brush_on, brush_off) > 0.05 and _cdist(brush_on, brush_back) < 0.015,
		"brush ground and canopy disappear with the brush switch and come back (%s / %s / %s)" % [brush_on.to_html(false), brush_off.to_html(false), brush_back.to_html(false)])


func _sample(lab: DeveloperScreen, pts: Array) -> Color:
	await frames(6)
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var xf: Transform2D = lab.view.get_global_transform_with_canvas()
	# canvas_items stretch: viewport (2D) coordinates -> rendered pixels.
	var k: Vector2 = Vector2(img.get_size()) / get_viewport().get_visible_rect().size
	var sum: Color = Color(0, 0, 0, 0)
	var n: int = 0
	for p: Vector2 in pts:
		var q: Vector2i = Vector2i((xf * p) * k)
		if q.x < 0 or q.y < 0 or q.x >= img.get_width() or q.y >= img.get_height():
			continue
		var c: Color = img.get_pixelv(q)
		sum += Color(c.r, c.g, c.b, 1.0)
		n += 1
	return Color(sum.r / maxf(1.0, n), sum.g / maxf(1.0, n), sum.b / maxf(1.0, n)) if n > 0 else Color(-1, -1, -1)


func _cdist(a: Color, b: Color) -> float:
	return (absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)) / 3.0


# Draft screen reuses its evaluation director (audit follow-up) and the lab's static helpers.
func _draft_and_helpers(app: App) -> void:
	var ds: DraftScreen = app.screens.draft
	var keep: Array = [ds.size_n, ds.arena_id, ds.ruleset, ds.user.duplicate(), ds.ai.duplicate()]
	ds.size_n = 3
	ds.arena_id = "twin_foundry"
	ds.ruleset = "elimination"
	ds.user = ["swordsman", "archer"]
	ds.ai = ["werewolf"]
	var v1: float = ds._evaluation()
	var dir1: DraftDirector = ds._eval_dir
	ds.user = ["swordsman", "archer", "mage"]
	var v2: float = ds._evaluation()
	check(dir1 != null and is_same(dir1, ds._eval_dir), "draft refresh reuses its evaluation director")
	var fresh: DraftDirector = DraftDirector.new({"team_size": 3, "arena_id": "twin_foundry", "ruleset": "elimination"})
	check(is_equal_approx(v2, fresh.evaluate_state(["swordsman", "archer", "mage"], ["werewolf"])) and is_equal_approx(v1, fresh.evaluate_state(["swordsman", "archer"], ["werewolf"])),
		"cached evaluation equals a fresh director")
	ds.arena_id = "furnace_basin"
	ds._evaluation()
	check(not is_same(dir1, ds._eval_dir), "changing the arena rebuilds the evaluation director")
	ds.size_n = int(keep[0])
	ds.arena_id = str(keep[1])
	ds.ruleset = str(keep[2])
	ds.user = keep[3]
	ds.ai = keep[4]
	var text: String = DeveloperScreen.map_item_text(DB.arena("rift_harbor"))
	check(text.contains("1440×864") and text.contains("분할"), "lab map picker text " + text)
	check(DeveloperScreen.arena_types(DB.arena("twin_foundry")) == ["artillery", "eruption"], "lab switch list for twin_foundry")
	var covered: Dictionary = {}
	for p in DeveloperScreen.GIMMICK_PRESETS:
		var id: String = str(p[2])
		var ar: Arena = DB.deathmatch_preview(id) if id.begins_with("dm_") else DB.arena(id)
		for typ in DeveloperScreen.arena_types(ar):
			covered[typ] = true
	for typ in ["artillery", "gate", "jump_pad", "closing_ring", "mud", "brush"]:
		check(covered.has(typ), "a gimmick test preset covers " + typ)
	# Ring presets stop where the ring first acts (the picker's promise), not
	# 20 s later where a 5v5 case could already be over (crossroads: tick 1767 < 1800).
	for p in DeveloperScreen.GIMMICK_PRESETS:
		var ring_arena: Arena = DB.arena(str(p[2])) if not str(p[2]).begins_with("dm_") else null
		if ring_arena == null:
			continue
		for h in ring_arena.hazards:
			if str(h.type) == "closing_ring":
				check(absf(float(p[3]) / 30.0 - float(h.startTime)) <= 2.0 and str(p[0]).contains("%d초" % int(roundf(float(p[3]) / 30.0))),
					"ring preset %s stops at the ring start (%.0f s vs %.0f s)" % [str(p[0]), float(p[3]) / 30.0, float(h.startTime)])


func _run() -> void:
	var settings_before: String = JSON.stringify(_settings().get("data"))
	var records_before: String = JSON.stringify(_settings().get("records"))
	var app: App = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(app)
	await frames(5)
	var lab: DeveloperScreen = app.screens.developer
	check(App.VERSION == "V2 프리뷰 · 드래프트 핫픽스" and app.current == "home", "V2 preview opens the home screen")
	app.goto("developer")
	await frames(2)
	check(app.current == "developer", "developer lab remains available from navigation")
	check(lab.runner.sim == null and not lab.view.visible, "empty lab never draws an uninitialized battle")
	check(lab.roster_options.size() == DeveloperScreen.ROSTER_SLOTS and DeveloperScreen.ROSTER_SLOTS == 30, "up to thirty individual participants (V2 battleground)")
	for option in lab.roster_options:
		check(option.item_count == 26, "every roster slot exposes all 26 heroes")
	# V2: a fourth mode (battleground); deathmatch and battleground both use their own AI.
	check(DeveloperScreen.MODES.size() == 4 and DeveloperScreen.MODES[3] == "battleground", "lab offers the battleground mode")
	for mode in DeveloperScreen.MODES.size():
		lab.mode_option.select(mode)
		lab._change_mode()
		check(lab.map_ids.size() == [12, 3, 3, 3][mode], "map count for " + DeveloperScreen.MODES[mode])
		check(lab.ai_options[0].disabled == (mode >= 2), "AI picker matches supported mode")
		lab.start_case()
		check(lab.runner.sim.ruleset == DeveloperScreen.MODES[mode] and lab.runner.paused and lab.runner.sim.tick == 0, "case starts paused " + str(mode))
		check(lab.view.sim == lab.runner.sim and lab.view.visible, "view uses the active simulation")
		lab.advance_ticks(1)
		check(lab.runner.sim.tick == 1 and is_equal_approx(lab.runner.sim.time, BattleSim.DT), "one tick is exactly 1/30 second")
		lab.advance_ticks(30)
		check(lab.runner.sim.tick == 31 and lab.runner.paused, "one second adds thirty ticks and remains paused")
		var before: String = signature(lab.runner.sim)
		lab.restart_case()
		lab.advance_ticks(31)
		check(before == signature(lab.runner.sim), "same configuration and seed exactly reproduce " + str(mode))
		var old_seed: int = lab.runner.sim.seed_value
		lab.seed_input.value += 17
		lab.restart_case()
		check(lab.runner.sim.seed_value == old_seed, "pending seed edits do not change restart conditions")
		lab.start_case()
		check(lab.runner.sim.seed_value == old_seed + 17, "new case uses pending seed edits")
		lab.advance_ticks(2)
		lab.environment_toggle.button_pressed = false
		check(not lab.runner.sim.env.enabled and lab.interventions == [{"tick": 2, "environment_enabled": false}], "environment toggle records its exact intervention tick")
		lab.environment_toggle.button_pressed = true
		check(lab.runner.sim.env.enabled and lab.interventions.size() == 2, "environment can be enabled again")
		var snap: Dictionary = lab.snapshot()
		check(snap.config == lab.last_config and snap.tick == 2 and snap.units.size() == lab.runner.sim.heroes.size(), "snapshot contains configuration, tick and every hero")
		lab.save_report()
		check(FileAccess.file_exists(lab.last_report_path), "report saved in developer report directory")
		var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(lab.last_report_path))
		check(saved.get("interventions", []).size() == 2 and saved.get("version", "") == App.VERSION, "saved report includes version and interventions")
		lab.restart_case()
		check(lab.interventions.is_empty() and lab.runner.sim.env.enabled, "restart restores original environment state")
		lab.toggle_pause()
		check(not lab.runner.paused, "play releases pause")
		app.goto("home")
		check(lab.runner.paused, "leaving the lab pauses its simulation")
		app.goto("developer")
		check(lab.runner.paused, "returning keeps the case paused")
	# Battleground rosters: solo may repeat a hero, a duo may not hold the same hero twice.
	lab.mode_option.select(3)
	lab._change_mode()
	lab.squad_option.select(0)
	lab.squad_option.item_selected.emit(0)
	lab.count_input.value = 4
	lab.roster_options[1].select(lab.roster_options[0].selected)
	lab.start_case()
	check(lab.runner.sim.is_battleground() and lab.runner.sim.heroes.size() == 4 and lab.runner.sim.heroes[0].def.id == lab.runner.sim.heroes[1].def.id,
		"battleground solo accepts the same hero twice")
	var solo_sim: BattleSim = lab.runner.sim
	lab.squad_option.select(1)
	lab.squad_option.item_selected.emit(1)
	lab.start_case()
	check(lab.runner.sim == solo_sim and lab.status_label.text.contains("두 번"), "battleground duo rejects a hero twice in one team")
	lab.roster_options[1].select(1 if lab.roster_options[0].selected != 1 else 2)
	lab.start_case()
	check(lab.runner.sim != solo_sim and lab.runner.sim.battleground.squad == 2 and lab.runner.sim.battleground.team_count == 4, "battleground duo case starts with 4 teams")
	var br_lines: String = lab.inspector.text
	check(br_lines.contains("자기장") and br_lines.contains("필드 아이템") and br_lines.contains("생존"), "inspector shows the zone, field items and survivors")
	check(lab.perspective_option.item_count == 5 and lab.perspective_option.get_item_text(1).begins_with("1팀"), "battleground perspectives are named by team")
	lab.squad_option.select(0)
	lab.squad_option.item_selected.emit(0)
	# Duplicate validation must leave the old running case intact.
	lab.mode_option.select(2)
	lab._change_mode()
	lab.start_case()
	lab.roster_options[1].select(lab.roster_options[0].selected)
	var same_sim: BattleSim = lab.runner.sim
	lab.start_case()
	check(lab.runner.sim == same_sim and lab.status_label.text.contains("두 번"), "duplicate individual participants rejected")
	lab.roster_options[1].select(1)
	# A completed case emits finish once even after further step requests.
	var runner: BattleRunner = BattleRunner.new()
	add_child(runner)
	var finished: Array = []
	runner.finished.connect(func(result: Dictionary): finished.append(result))
	runner.start({"arena_id": "classic", "blue": ["giant"], "red": ["giant"], "seed": 152, "max_time": BattleSim.DT * 2})
	runner.step_ticks(30)
	runner.step_ticks(30)
	check(runner.done and finished.size() == 1, "manual stepping stops and emits one result at match end")
	runner.queue_free()
	# Show a populated control map for responsive visual inspection.
	lab.mode_option.select(1)
	lab._change_mode()
	lab.map_option.select(1)
	lab._map_hint()
	lab.count_input.value = 5
	lab._cycle_roster()
	lab.start_case()
	lab.advance_ticks(300)
	lab.roster_button.pressed.emit()
	await frames(4)
	for dimensions: Vector2i in [Vector2i(1600, 900), Vector2i(3440, 1440)]:
		if DisplayServer.get_name() != "headless":
			get_window().mode = Window.MODE_WINDOWED
			get_window().size = dimensions
			await get_tree().create_timer(0.3).timeout
			await frames(6)
		var available: Rect2 = app.content.get_global_rect()
		for control: Control in [lab.status_label, lab.inspector, lab.environment_toggle, lab.map_option, lab.ai_options[1]]:
			check(available.grow(2.0).encloses(control.get_global_rect()), "lab control stays visible at " + str(dimensions) + "/" + str(control.name))
		check(lab.arena_area.size.x >= 320 and lab.arena_area.size.y >= 220, "battle keeps useful space at " + str(dimensions))
		await shot("developer_" + str(dimensions.x) + "x" + str(dimensions.y))
	await _gimmick_lab(lab)
	_draft_and_helpers(app)
	check(JSON.stringify(_settings().get("data")) == settings_before, "lab leaves player settings unchanged")
	check(JSON.stringify(_settings().get("records")) == records_before, "lab does not write normal battle records")
	var result: Dictionary = {"status": "PASS" if failed.is_empty() else "FAIL", "passed": passed, "failed": failed, "checks": rows}
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var file: FileAccess = FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "  "))
	print("DEVELOPER_152 ", passed, " PASS / ", failed.size(), " FAIL")
	app.queue_free()
	await frames(2)
	get_tree().quit(0 if failed.is_empty() else 1)
