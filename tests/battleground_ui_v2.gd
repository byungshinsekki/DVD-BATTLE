extends Node

# V2 battleground UI (wave 3, B-UI) in the real app at 1600x900: the setup screen (formats, team
# roster, duplicate rules, threaded map previews, right tabs), the battle screen's battleground mode
# for solo 30 / duo 15 / trio 10 (top-bar budget, team chips, zone pill, minimap, kill feed,
# standing, team perspectives with V / Shift+V, zoom and picking limits, no deathmatch strings,
# widget refresh throttle), the report, the setup -> battle -> result flow on a short fixture, and
# the home / codex / developer lab entries. Writes a JSON report and screenshots.
# Needs an isolated QA project: run it only through zz_work/tools/gd.ps1 -Mode uitest.

const FORMATS: = [["solo", 1, 30, "br_ashen_metropolis", 7, 45.0], ["duo", 2, 15, "br_wildwood_frontier", 11, 30.0],
	["trio", 3, 10, "br_highland_ruins", 5, 30.0]]
const CONFIG_KEYS: = ["ruleset", "mode", "arena_id", "seed", "squad", "teams", "zone_speed", "max_time", "ai"]
# Deathmatch-only texts that must never appear in a battleground battle.
const DM_STRINGS: = ["목표 999킬", "목표 %d킬", "개인전 · 목표", "선두", "아직 처치 없음", "재출전"]
# Symbols the battleground screens draw (feed, cards, tables, glossary icons); each must be in a
# bundled font (otherwise the system font draws it).
const SYMBOLS: = ["▲", "✚", "☠", "⚔", "◉", "⊙", "▼", "救", "–", "—", "×", "✕", "↻", "▶", "ⓘ", "·", "→"]
const BUNDLED_FONTS: = ["res://assets/fonts/ui_regular.otf", "res://assets/fonts/ui_bold.otf", "res://assets/fonts/ui_black.otf",
	"res://assets/fonts/glyph_serif.otf", "res://assets/fonts/symbols.ttf"]

var checks: int = 0
var failures: int = 0
var records: Array = []
var shot_dir: String = ""
var shots: Array = []
var measurements: Dictionary = {}
var app: App


func _ready() -> void:
	# This test renders UI and must use a separate settings folder.
	var isolated: bool = bool(ProjectSettings.get_setting("application/config/use_custom_user_dir", false))
	var directory: String = str(ProjectSettings.get_setting("application/config/custom_user_dir_name", ""))
	if not isolated or not directory.to_upper().contains("QA"):
		push_error("UI validation requires an isolated QA project with a custom QA user directory.")
		get_tree().quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-dir="):
			shot_dir = arg.substr(9)
	if shot_dir == "":
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--ui-report="):
				shot_dir = arg.substr(12).get_base_dir()
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
	if shot_dir == "" or DisplayServer.get_name() == "headless":
		return
	await _frames(10)
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(shot_dir)
	var path: String = shot_dir.path_join(name + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	shots.append(path)
	print("SHOT ", path)


func _texts(node: Node, out: Array) -> void:
	if node is CanvasItem and not (node as CanvasItem).visible:
		return
	if node is Label:
		out.append((node as Label).text)
	elif node is Button:
		out.append((node as Button).text)
	elif node is RichTextLabel:
		out.append((node as RichTextLabel).get_parsed_text())
	for c in node.get_children():
		_texts(c, out)


func _find_text(node: Node, text: String) -> bool:
	var all: Array = []
	_texts(node, all)
	for t in all:
		if str(t).contains(text):
			return true
	return false


func _find_type(node: Node, cls: String) -> Node:
	if node.get_class() == cls or (node.get_script() != null and (node.get_script() as Script).get_global_name() == cls):
		return node
	for c in node.get_children():
		var hit: Node = _find_type(c, cls)
		if hit:
			return hit
	return null


func _key(battle: BattleScreen, code: Key, shift: bool = false) -> void:
	var ev: InputEventKey = InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	ev.shift_pressed = shift
	battle._unhandled_key_input(ev)


func _run() -> void:
	var records_before: String = JSON.stringify(Settings.records)
	app = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(app)
	await _frames(3)
	_fonts()
	await _navigation()
	await _setup_screen()
	for f in FORMATS:
		await _battle(str(f[0]), int(f[1]), int(f[2]), str(f[3]), int(f[4]), float(f[5]))
	await _report_and_flow()
	await _home_codex_lab()
	_check(JSON.stringify(Settings.records).length() > 0, "records still readable")
	print("UI_VALIDATION_BR_V2 ", checks, " PASS / ", failures, " FAIL")
	var report_path: String = "res://reports/battleground_ui_v2.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ui-report="):
			report_path = arg.substr(12)
	DirAccess.make_dir_recursive_absolute(report_path.get_base_dir())
	var file: FileAccess = FileAccess.open(report_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"suite": "battleground_ui_v2", "passed": checks, "failed": failures,
			"isolated_user_dir": ProjectSettings.get_setting("application/config/custom_user_dir_name"), "records_before": records_before,
			"measurements": measurements, "shots": shots, "checks": records}, "  "))
		file.close()
	(app.screens.battle as BattleScreen).runner.dispose_sim()
	app.queue_free()
	await _frames(2)
	get_tree().quit(1 if failures else 0)


# ------------------------------------------------------------------ fonts

func _fonts() -> void:
	var fonts: Array = []
	for p in BUNDLED_FONTS:
		var f: Resource = ResourceLoader.load(p, "", ResourceLoader.CACHE_MODE_IGNORE)
		if f is Font:
			fonts.append(f)
	var missing: Array = []
	for ch in SYMBOLS:
		var have: bool = false
		for f in fonts:
			have = have or (f as Font).has_char(str(ch).unicode_at(0))
		if not have:
			missing.append(ch)
	for k in ["downed", "revive", "br_zone"]:
		for ch in str(CodexData.STATUS[k].icon):
			var have2: bool = false
			for f in fonts:
				have2 = have2 or (f as Font).has_char(ch.unicode_at(0))
			if not have2:
				missing.append(k + ":" + ch)
	_check(fonts.size() == BUNDLED_FONTS.size() and missing.is_empty(), "battleground symbols and glossary icons are in the bundled fonts %s" % str(missing))


# ------------------------------------------------------------------ navigation

func _navigation() -> void:
	_check(App.VERSION == "V2 프리뷰 · 드래프트 핫픽스" and app.current == "home", "V2 preview starts on the home screen")
	var row: Array = []
	for r in App.NAV:
		if str(r[0]) == "battleground":
			row = r
	_check(row == ["battleground", "배틀그라운드", "◉", "play"], "sidebar NAV has 배틀그라운드 ◉ under play")
	_check(app.nav_buttons.has("battleground") and app.screens.get("battleground") is BattlegroundScreen, "battleground screen is registered")
	app.goto("battleground")
	await _frames(3)
	_check(app.current == "battleground" and (app.nav_buttons.battleground as Button).button_pressed, "nav opens the setup screen")


# ------------------------------------------------------------------ setup

func _wait_previews(bs: BattlegroundScreen, max_frames: int = 900) -> int:
	var n: int = 0
	while n < max_frames:
		var ready: bool = true
		for id in bs.map_cards:
			var card = bs.map_cards[id]
			if card.loading or card.texture == null:
				ready = false
		if ready:
			return n
		await get_tree().process_frame
		n += 1
	return n


func _setup_screen() -> void:
	var bs: BattlegroundScreen = app.screens.battleground
	_check(bs.squad == 1 and bs.slots.size() == bs.n_teams and bs._filled().size() == bs.slots.size() and not bs.start_btn.disabled, "defaults to a full random solo roster, ready to start")
	_check(bs.map_cards.size() == 3, "three battleground maps offered")
	var t0: int = Time.get_ticks_msec()
	var waited: int = await _wait_previews(bs)
	measurements["preview_frames"] = waited
	measurements["preview_ms"] = Time.get_ticks_msec() - t0
	var ok: bool = true
	for id in bs.map_cards:
		ok = ok and bs.map_cards[id].texture != null and not bs.map_cards[id].counts.is_empty()
	_check(ok, "map previews are built off the main thread and shown (%d frames)" % waited)
	# Another consumer can finish and collect a shared job before the setup gets a frame.
	var foreign_seed: int = bs._seed_value() + 1
	bs.seed_edit.text = str(foreign_seed)
	bs._request(bs.map_id)
	bs.set_process(false)
	var foreign_preview: Dictionary = BattlegroundScreen.preview_now(bs.map_id, foreign_seed)
	bs._process(0.0)
	var shared_card = bs.map_cards[bs.map_id]
	_check(not foreign_preview.is_empty() and shared_card.texture == foreign_preview.texture
		and shared_card.shown_seed == foreign_seed and not shared_card.loading,
		"setup applies a shared preview collected by another consumer")
	# A seed edit rebuilds only the selected map.
	var builds0: int = BattlegroundScreen.builds
	bs.seed_edit.text = "4242"
	bs._on_seed_text("4242")
	var n: int = 0
	while n < 900 and (bs.seed_timer >= 0.0 or bs.map_cards[bs.map_id].loading or bs.map_cards[bs.map_id].shown_seed != 4242):
		await get_tree().process_frame
		n += 1
	var others: bool = true
	for id in bs.map_cards:
		if id != bs.map_id:
			others = others and bs.map_cards[id].shown_seed != 4242
	_check(BattlegroundScreen.builds - builds0 == 1 and bs.map_cards[bs.map_id].shown_seed == 4242 and others, "a seed edit rebuilds only the selected map (%d build)" % (BattlegroundScreen.builds - builds0))
	# Formats, scale presets and the roster panel budget.
	for f in [[1, 30, "solo"], [2, 15, "duo"], [3, 10, "trio"]]:
		bs._set_format(int(f[0]))
		bs._set_scale(int(f[1]))
		bs._randomize_all()
		await _frames(3)
		var cfg: Dictionary = bs.build_config()
		var keys: Array = cfg.keys()
		keys.sort()
		var want: Array = CONFIG_KEYS.duplicate()
		want.sort()
		_check(keys == want and str(cfg.ruleset) == "battleground" and int(cfg.squad) == int(f[0]) and (cfg.teams as Array).size() == int(f[1]) and float(cfg.max_time) == BattlegroundMode.MAX_TIME,
			"%s config has the DESIGN §3.5 keys" % str(f[2]))
		_check(BattlegroundMode.validate(cfg).is_empty() and bs.slots.size() == 30 and not bs.start_btn.disabled, "%s %d: 30 heroes, valid" % [str(f[2]), int(f[1])])
		var need: float = bs.team_box.get_combined_minimum_size().y
		_check(need <= bs.team_scroll.size.y + 0.5, "%s roster panel fits without scrolling (%.0f / %.0f px)" % [str(f[2]), need, bs.team_scroll.size.y])
		measurements["roster_h_" + str(f[2])] = need
		await _shot("br_setup_" + str(f[2]))
	# Duplicates: allowed across solo players, never inside one squad.
	bs._set_format(1)
	bs._set_scale(10)
	bs._clear()
	bs.pick("hades")
	bs.pick("hades")
	await _frames(2)
	var hades_card: RosterCard = null
	for rc in bs.roster_cards:
		if (rc as RosterCard).def.id == "hades":
			hades_card = rc
	_check(bs.slots.count("hades") == 2 and hades_card.count == 2 and hades_card.count_badge.visible and hades_card.count_badge.text == "×2", "solo allows the same hero twice (×2 badge)")
	bs._set_format(2)
	bs._set_scale(5)
	bs._clear()
	bs.pick("hades")
	bs.pick("hades")
	_check(bs.team_ids(0).is_empty(), "picking a hero again in the same squad removes it")
	bs.pick("hades")
	bs.pick("achilles")
	_check(bs.team_ids(0) == ["hades", "achilles"] and bs.active_team == 1, "a full squad passes the next pick on to the next team")
	bs.pick("hades")
	_check(bs.team_ids(1) == ["hades"], "the same hero may play in another squad")
	_check(not BattlegroundMode.validate({"squad": 2, "teams": [["hades", "hades"], ["mage", "archer"]]}).is_empty(), "the mode rejects a hero twice in one squad")
	bs._fill_rest()
	_check(bs._filled().size() == bs.slots.size() and BattlegroundMode.validate(bs.build_config()).is_empty(), "fill completes a valid duo roster")
	bs._clear()
	_check(bs._filled().is_empty() and bs.start_btn.disabled and bs.fill_btn.disabled == false, "clear empties the roster and disables start")
	bs._randomize_all()
	# Right tabs: character, item odds by ring, zone timetable.
	bs.right_tabs.current_tab = 1
	await _frames(2)
	_check(bs.items_wrap.visible and _find_text(bs.items_wrap, "고리별 등급 확률") and _find_text(bs.items_wrap, "중앙") and _find_text(bs.items_wrap, "필드 80개 중"), "item tab shows the ring odds and battleground counts")
	bs.right_tabs.current_tab = 2
	await _frames(2)
	var z_rows: int = 0
	for c in bs.zone_table.get_children():
		if c is PanelContainer:
			z_rows += 1
	_check(bs.zone_wrap.visible and z_rows == BrZone.PHASES and _find_text(bs.zone_wrap, "Z6") and _find_text(bs.zone_wrap, "12%/s"), "zone tab lists the 6 phases")
	bs._set_speed("fast")
	await _frames(1)
	_check(_find_text(bs.zone_wrap, "1:00–1:48"), "zone table follows the zone speed (fast: Z1 1:00–1:48)")
	bs._set_speed("normal")
	bs.right_tabs.current_tab = 0


# ------------------------------------------------------------------ battle

func _battle(fmt: String, squad: int, n: int, map: String, seed_v: int, warp_t: float) -> void:
	var bs: BattlegroundScreen = app.screens.battleground
	app.goto("battleground")
	await _frames(2)
	bs._set_format(squad)
	bs._set_scale(n)
	bs._randomize_all()
	bs._set_map(map)
	bs.seed_edit.text = str(seed_v)
	var t0: int = Time.get_ticks_msec()
	bs._start()
	await _frames(3)
	measurements["start_ms_" + fmt] = Time.get_ticks_msec() - t0
	var battle: BattleScreen = app.screens.battle
	var sim: BattleSim = battle.runner.sim
	var br: BattlegroundMode = battle.br
	_check(app.current == "battle" and br != null and sim.is_battleground() and br.squad == squad and br.team_count == n and sim.heroes.size() == 30 and str(sim.arena.data.get("preset", "")) == map and sim.seed_value == seed_v,
		"%s: setup start reaches the battle (%d teams on %s)" % [fmt, n, map])
	_check(app.battle_origin == "battleground", "%s: battle origin is the battleground setup" % fmt)
	battle.runner.paused = true
	var widths_ok: bool = battle.br_chips.size() == n
	for chip in battle.br_chips:
		widths_ok = widths_ok and is_equal_approx((chip as TeamChip).custom_minimum_size.x, TeamChip.width_for(squad))
	_check(widths_ok, "%s: one team chip per team, %d px wide" % [fmt, int(TeamChip.width_for(squad))])
	var top_w: float = battle.top_bar.get_combined_minimum_size().x
	var bottom_w: float = battle.bottom_bar.get_combined_minimum_size().x
	measurements["top_bar_w_" + fmt] = top_w
	measurements["bottom_bar_w_" + fmt] = bottom_w
	_check(top_w <= 1600.0 and battle.top_bar.size.x <= 1600.5, "%s: top bar fits 1600 px (%.0f)" % [fmt, top_w])
	_check(bottom_w <= 1600.0, "%s: bottom bar fits 1600 px (%.0f)" % [fmt, bottom_w])
	_check(battle.zone_pill.visible and battle.zone_pill.compact and battle.zone_pill.text() != "", "%s: compact zone pill in the top bar (%s)" % [fmt, battle.zone_pill.text()])
	_check(battle.alive_l.visible and battle.alive_l.text.begins_with("생존 30/30") and (squad == 1 or battle.alive_l.text.ends_with("%d팀" % n)), "%s: survivors label %s" % [fmt, battle.alive_l.text])
	var arena_r: Rect2 = battle.arena_area.get_global_rect()
	var mm_r: Rect2 = battle.minimap.get_global_rect()
	_check(battle.minimap.visible and arena_r.encloses(mm_r) and mm_r.end.x > arena_r.end.x - 30.0 and mm_r.end.y > arena_r.end.y - 30.0 and battle.minimap.texture != null,
		"%s: minimap at the bottom-right of the arena" % fmt)
	var titles: Array = []
	for i in battle.tabs.tab_count:
		titles.append(battle.tabs.get_tab_title(i))
	_check(titles == ["순위", "유닛", "이벤트", "AI 판단"], "%s: side tabs" % fmt)
	_check(battle.dm_view_opt.visible and battle.dm_view_opt.item_count == n + 1 and not battle.team_tags[0].visible, "%s: team perspective picker lists every team" % fmt)
	_check_item_perspective(battle, fmt)
	var base: float = battle.view.base_scale
	_check(is_equal_approx(battle.view.max_zoom(), maxf(4.0, 1.6 / base)), "%s: zoom cap max(4, 1.6/base) = %.1f" % [fmt, battle.view.max_zoom()])
	battle.view.manual_zoom(1000.0, battle.arena_area.size * 0.5)
	_check(battle.view.cam_zoom_t <= battle.view.max_zoom() + 0.001 and battle.view.cam_zoom_t > 4.0, "%s: manual zoom reaches but never passes the cap" % fmt)
	battle.view.set_cam_mode("full")
	battle.view._apply_camera(0.0)
	# Picking: 14 screen px around a hero's body, whatever the zoom.
	var hero: BUnit = sim.heroes[0]
	var off: float = (sim.radius(hero) + 10.0 / battle.view.view_scale)
	_check(battle.view.pick_unit(hero.pos + Vector2(off, 0.0)) >= 0, "%s: picking radius scales with the zoom" % fmt)
	battle._set_cam("auto")
	# Play: warp, then let the screen run so the widgets and the feed update.
	t0 = Time.get_ticks_msec()
	battle.runner.warp(warp_t)
	measurements["warp_ms_" + fmt] = Time.get_ticks_msec() - t0
	battle.runner.paused = false
	battle.runner.speed = 2.0
	var pushes0: int = battle.br_pushes
	var f0: int = Engine.get_process_frames()
	var tm0: int = Time.get_ticks_msec()
	await _frames(45)
	var secs: float = float(Time.get_ticks_msec() - tm0) / 1000.0
	var pushes: int = battle.br_pushes - pushes0
	measurements["pushes_" + fmt] = [pushes, Engine.get_process_frames() - f0, secs]
	_check(pushes <= int(ceil(secs / BattleScreen.BR_PUSH)) + 2, "%s: widgets refresh at most every %.2f s (%d pushes in %.1f s, %d frames)" % [fmt, BattleScreen.BR_PUSH, pushes, secs, Engine.get_process_frames() - f0])
	battle.runner.paused = true
	_check(battle.feed_box.get_child_count() <= BattleScreen.BR_FEED_MAX, "%s: kill feed keeps at most 6 lines (%d)" % [fmt, battle.feed_box.get_child_count()])
	# Rank tab = BrStanding grouped by team.
	battle.tabs.current_tab = 0
	battle._refresh_panel(true)
	await _frames(2)
	var standing: BrStanding = battle.br_standing
	_check(standing != null and standing.is_inside_tree() and standing.teams.size() == n and _find_text(battle.tab_body, "생존"), "%s: rank tab shows the team standing" % fmt)
	await _shot("br_battle_%s_rank" % fmt)
	# Unit tab: held items n / 3, hero cards.
	var target: BUnit = null
	for u in sim.heroes:
		if u.alive:
			target = u
			break
	battle._select(target.idx)
	battle.tabs.current_tab = 1
	battle._refresh_panel(true)
	await _frames(2)
	_check(_find_text(battle.tab_body, "보유 아이템") and _find_text(battle.tab_body, "/ 3칸") and _find_text(battle.tab_body, "처치"), "%s: unit tab shows held items n / 3 and hero stats" % fmt)
	# V2 hero cards (fuel pips / tank / overdrive, soul harvest / cerberus, shield guard).
	for spec in [["war_machine", "연료"], ["hades", "영혼 수확"], ["achilles", "방패"]]:
		for u in sim.heroes:
			if u.alive and u.def.id == str(spec[0]):
				battle._select(u.idx)
				battle._refresh_panel(true)
				await _frames(2)
				_check(_find_text(battle.tab_body, str(spec[1])), "%s: %s card shows %s" % [fmt, str(spec[0]), str(spec[1])])
				break
	var downed: BUnit = null
	for u in sim.heroes:
		if br.is_downed(u):
			downed = u
	if downed:
		battle._select(downed.idx)
		battle._refresh_panel(true)
		await _frames(2)
		_check(_find_text(battle.tab_body, "다운 · 출혈") and battle.sel_hp_l.text.begins_with("다운"), "%s: downed card for a downed hero" % fmt)
	battle._select(target.idx)
	# AI tab renders for the selected hero.
	battle.tabs.current_tab = 3
	battle._refresh_panel(true)
	await _frames(2)
	_check(battle.tab_body.get_child_count() > 0, "%s: AI tab renders" % fmt)
	battle.tabs.current_tab = 2
	battle._refresh_panel(true)
	await _frames(2)
	battle.tabs.current_tab = 0
	battle._refresh_panel(true)
	# No deathmatch strings anywhere on the battle screen.
	var all: Array = []
	_texts(battle, all)
	var bad: Array = []
	for t in all:
		for d in DM_STRINGS:
			if str(t).contains(d):
				bad.append(str(t))
	_check(bad.is_empty() and battle.sub_l.text == "" and not battle.leader_pill.visible, "%s: no deathmatch strings (kill target, leader) %s" % [fmt, str(bad.slice(0, 3))])
	# Perspectives by team: V forward, Shift+V backward, eliminated teams skipped.
	battle._set_vision(-1)
	_key(battle, KEY_V)
	var first_live: int = battle._br_next_view(-1, 1)
	_check(battle.view.perspective == first_live and battle.dm_view_opt.selected == first_live + 1 and battle.view.fog.visible, "%s: V picks the first team still in play" % fmt)
	_key(battle, KEY_V, true)
	_check(battle.view.perspective == -1, "%s: Shift+V goes back to the spectator view" % fmt)
	_key(battle, KEY_V, true)
	var last_live: int = battle._br_next_view(-1, -1)
	_check(battle.view.perspective == last_live and not br.is_eliminated(last_live), "%s: Shift+V from the spectator view picks the last team in play" % fmt)
	var out_team: int = -1
	for t in br.team_count:
		if br.is_eliminated(t):
			out_team = t
			break
	if out_team >= 0:
		var before: int = out_team - 1
		while before >= 0 and br.is_eliminated(before):
			before -= 1
		_check(battle._br_next_view(before, 1) != out_team, "%s: V skips an eliminated team (%s)" % [fmt, br.team_label(out_team)])
	measurements["eliminated_" + fmt] = n - br.alive_team_count()
	await _frames(3)
	await _shot("br_battle_%s_view" % fmt)
	battle._set_vision(-1)
	battle.tabs.current_tab = 1
	battle._refresh_panel(true)
	await _frames(3)
	await _shot("br_battle_%s_unit" % fmt)
	battle.tabs.current_tab = 0
	battle.runner.dispose_sim()


# ------------------------------------------------------------------ report + flow

func _check_item_perspective(battle: BattleScreen, fmt: String) -> void:
	var sim: BattleSim = battle.runner.sim
	var br: BattlegroundMode = battle.br
	var visible_pos: Vector2 = sim.heroes[0].pos
	var hidden_pos: Vector2 = Vector2.INF
	for iy in 5:
		for ix in 5:
			var p: Vector2 = Vector2(sim.arena.width * float(ix + 1) / 6.0, sim.arena.height * float(iy + 1) / 6.0)
			if not sim.point_seen(0, p):
				hidden_pos = p
				break
		if hidden_pos != Vector2.INF:
			break
	_check(hidden_pos != Vector2.INF, "%s: item sight fixture has an unseen position" % fmt)
	if hidden_pos == Vector2.INF:
		return
	var legendary: String = ""
	for id in ItemDefs.ORDER:
		if ItemDefs.rarity_of(str(id)) == 4:
			legendary = str(id)
			break
	_check(legendary != "", "%s: item sight fixture uses a legendary pickup" % fmt)
	var saved_field: Array = br.field
	br.field = [{"item": legendary, "pos": visible_pos}, {"item": legendary, "pos": hidden_pos}]
	battle._set_vision(0)
	battle._push_br()
	_check(battle.view.field_item_visible(visible_pos) and not battle.view.field_item_visible(hidden_pos),
		"%s: battleground world and hover hide items outside the team sight" % fmt)
	var shown: Array = battle.minimap.dots.filter(func(dot: Dictionary) -> bool: return str(dot.get("kind", "")) == "item")
	_check(shown.size() == 1 and (shown[0].pos as Vector2) == visible_pos, "%s: team minimap hides the unseen legendary item" % fmt)
	battle._set_vision(-1)
	battle._push_br()
	shown = battle.minimap.dots.filter(func(dot: Dictionary) -> bool: return str(dot.get("kind", "")) == "item")
	_check(shown.size() == 2 and battle.view.field_item_visible(hidden_pos), "%s: spectator minimap shows both legendary items" % fmt)
	battle.view._note_heat(hidden_pos)
	var spectator_heat: bool = not battle.view._heat.is_empty() and battle.view.hottest_fight() != Vector2.INF
	battle._set_vision(0)
	_check(spectator_heat and battle.view._heat.is_empty() and battle.view._heat_next == 0 and battle.view.hottest_fight() == Vector2.INF,
		"%s: team perspective clears spectator fight location memory" % fmt)
	battle._set_vision(-1)
	br.field = saved_field
	battle._push_br()

func _report_and_flow() -> void:
	# Setup -> battle -> result on a short fixture: a solo 10 start, the clock cap lowered to 15 s.
	var bs: BattlegroundScreen = app.screens.battleground
	app.goto("battleground")
	await _frames(2)
	bs._set_format(1)
	bs._set_scale(10)
	bs._randomize_all()
	bs._set_map("br_highland_ruins")
	bs._set_speed("fast")
	bs.seed_edit.text = "5"
	bs._start()
	await _frames(3)
	var battle: BattleScreen = app.screens.battle
	var sim: BattleSim = battle.runner.sim
	_check(app.current == "battle" and battle.br != null and sim.heroes.size() == 10 and battle.br.zone_speed == "fast", "flow: the setup starts a solo 10 battle with the fast zone")
	sim.max_time = 15.0
	battle.runner.warp(15.5)
	battle.runner.paused = false
	var n: int = 0
	while app.current != "result" and n < 600:
		await get_tree().process_frame
		n += 1
	_check(app.current == "result" and battle.ended, "flow: the battle ends on its clock and opens the report (%d frames)" % n)
	var rs: ResultScreen = app.screens.result
	_check(_find_text(rs, "BATTLEGROUND REPORT") and _find_text(rs, "우승") and _find_text(rs, "시간 종료"), "report head: winner and reason")
	_check(_find_text(rs, "시상대") and _find_text(rs, "생존자 흐름") and _find_type(rs, "SurvivorChart") != null, "report has the podium and the survivor chart")
	var chart: SurvivorChart = _find_type(rs, "SurvivorChart") as SurvivorChart
	var expected: Array = []
	for sample in (rs.result.get("battleground", {}) as Dictionary).get("series", []):
		expected.append([float(sample[0]), int(sample[2]), int(sample[1])])
	_check(not expected.is_empty() and chart.samples == expected, "report uses the actual survivor series with heroes and teams in the correct columns")
	for col in ["순위", "팀", "참가자", "처치", "다운시킴", "소생", "피해", "생존 시간", "주운 아이템", "최종 보유"]:
		_check(_find_text(rs, col), "ranking column %s" % col)
	_check(_find_text(rs, "새 배틀그라운드 편성") and not _find_text(rs, "목표"), "report offers a new battleground setup, no kill target")
	_check(app.nav_buttons.battleground.button_pressed, "the report keeps the battleground nav highlighted")
	await _shot("br_result_solo10")
	# A squad report (trio, 3 teams, 12 s) from a real result object.
	var cfg: Dictionary = {"ruleset": "battleground", "mode": "battleground", "arena_id": "br_wildwood_frontier", "seed": 11, "squad": 3,
		"teams": [["hades", "achilles", "torquemada"], ["war_machine", "mage", "archer"], ["giant", "sniper", "aphrodite"]], "zone_speed": "fast", "max_time": 12.0, "ai": "tactician"}
	app.start_battle(cfg, "battleground")
	await _frames(2)
	var b2: BattleScreen = app.screens.battle
	b2.runner.paused = true
	b2.runner.warp(12.5)
	b2.runner.paused = false
	n = 0
	while app.current != "result" and n < 600:
		await get_tree().process_frame
		n += 1
	var table_rows: int = 0
	var brr: Dictionary = (app.screens.result as ResultScreen).result.get("battleground", {})
	_check(app.current == "result" and int(brr.get("squad", 0)) == 3 and (brr.get("teams", []) as Array).size() == 3 and _find_text(rs, "3팀") and _find_text(rs, "상위 3팀"),
		"trio report groups the table by team")
	await _shot("br_result_trio")
	# The new-match button goes back to the battleground setup.
	var new_btn: Button = null
	for b in rs.find_children("*", "Button", true, false):
		if (b as Button).text == "새 배틀그라운드 편성":
			new_btn = b
	if new_btn:
		new_btn.pressed.emit()
	await _frames(2)
	_check(app.current == "battleground", "새 배틀그라운드 편성 opens the setup screen")
	(app.screens.battle as BattleScreen).runner.dispose_sim()


# ------------------------------------------------------------------ home / codex / lab

func _home_codex_lab() -> void:
	app.goto("home")
	await _frames(3)
	var home: HomeScreen = app.screens.home
	_check(home.br_card != null and _find_text(home.br_card, "배틀그라운드") and _find_text(home.br_card, "NEW") and _find_text(home.br_card, "솔로·듀오·트리오")
		and _find_text(home.br_card, "최대 30명") and _find_text(home.br_card, "아이템 80") and _find_text(home.br_card, "전장 3종"), "home shows the battleground feature card")
	_check(_find_text(home, "21") and HomeScreen.MODE_GLYPHS.size() == 5 and HomeScreen._arena_total() == 21, "home counts 21 arenas and 5 modes")
	var n: int = 0
	while n < 600:
		var ready: bool = true
		for th in home.br_thumbs:
			ready = ready and th.texture != null
		if ready:
			break
		await get_tree().process_frame
		n += 1
	_check(home.br_thumbs.size() == 3 and n < 600, "home map thumbnails load (%d frames)" % n)
	await _shot("br_home")
	home.br_card.pressed.emit()
	await _frames(2)
	_check(app.current == "battleground", "the feature card opens the setup")
	# Codex: battleground arena group and glossary terms.
	app.goto("codex", {"mode": "arenas"})
	await _frames(3)
	var codex: CodexScreen = app.screens.codex
	n = 0
	while codex.arena_cards.size() < 21 and n < 900:
		await get_tree().process_frame
		n += 1
	_check(codex.arena_cards.size() == 21 and codex.arena_cards.has("br_highland_ruins"), "codex lists the 3 battleground maps (%d frames)" % n)
	codex._jump_arena_group("battleground")
	await _frames(2)
	_check(codex.arena_scroll.scroll_vertical > 0, "group jump scrolls to 배틀그라운드")
	await _shot("br_codex_arenas")
	app.goto("codex", {"mode": "glossary", "item": "downed"})
	await _frames(3)
	_check(codex.term_cards.has("downed") and codex.term_cards.has("revive") and codex.term_cards.has("br_zone"), "glossary has 다운, 소생 and 자기장")
	_check(CodexData.term_for_label("기절(다운)") == "downed" and CodexData.term_label("downed") == "다운" and CodexData.term_label("revive") == "소생" and CodexData.term_label("br_zone") == "자기장",
		"glossary labels and the 기절(다운) alias")
	_check(str(CodexData.STATUS.downed.desc).contains("체력 %d" % int(BattlegroundMode.DOWNED_HP))
		and str(CodexData.STATUS.downed.desc).contains("%d%%만" % int(BattlegroundMode.DOWNED_TAKEN * 100.0)),
		"downed glossary matches the integrated squad health and damage rules")
	await _shot("br_codex_glossary")
	# Developer lab: the battleground mode.
	app.goto("developer")
	await _frames(2)
	var lab: DeveloperScreen = app.screens.developer
	lab.mode_option.select(3)
	lab._change_mode()
	lab.count_input.value = 6
	lab.start_case()
	await _frames(3)
	_check(lab.runner.sim != null and lab.runner.sim.is_battleground() and lab.map_ids.size() == 3 and lab.squad_field.visible and lab.inspector.text.contains("자기장"), "developer lab runs a battleground case with zone rows")
	await _shot("br_lab")
	lab.runner.dispose_sim()
