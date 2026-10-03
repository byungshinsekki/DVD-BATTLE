class_name App
extends Control


const VERSION: = "V2 프리뷰 · 드래프트 핫픽스"
## Sidebar navigation rows: [screen id, label, icon glyph, group id].
const NAV: = [
	["home", "홈", "⌂", "play"],
	["setup", "조합 대전", "⚔", "play"],
	["draft", "AI 대전", "◈", "play"],
	["deathmatch", "데스매치", "✦", "play"],
	["battleground", "배틀그라운드", "◉", "play"],
	["codex", "전투 도감", "☰", "library"],
	["developer", "개발자 실험실", "⌘", "library"],
	["settings", "설정", "⚙", "system"],
]
## Sidebar groups in display order: [group id, label].
const NAV_GROUPS: = [["play", "플레이"], ["library", "라이브러리"], ["system", "시스템"]]
const SIDEBAR_W: = 232
const TOAST_MAX_W: = 480
const TOAST_MAX: = 3

var bg: DvdBackground
var sidebar: PanelContainer
var content: Control
var screens: Dictionary = {}
var nav_buttons: Dictionary = {}
var nav_group: ButtonGroup
var current: String = ""
var toast_box: VBoxContainer
var last_battle: Dictionary = {}
var battle_origin: String = "setup"
var resume_btn: Button
var _fade_tw: Tween


func _ready() -> void :
	DB.ensure_loaded()
	theme = UITheme.build()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_tree().node_added.connect(_on_node_added)
	_glow_env()
	bg = DvdBackground.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root: = HBoxContainer.new()
	root.add_theme_constant_override("separation", 0)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	sidebar = _build_sidebar()
	root.add_child(sidebar)
	content = Control.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.clip_contents = true
	root.add_child(content)
	_add_screen("home", HomeScreen.new())
	_add_screen("setup", SetupScreen.new())
	_add_screen("draft", DraftScreen.new())
	_add_screen("deathmatch", DeathmatchScreen.new())
	_add_screen("battleground", BattlegroundScreen.new())
	_add_screen("codex", CodexScreen.new())
	_add_screen("settings", SettingsScreen.new())
	_add_screen("battle", BattleScreen.new())
	_add_screen("result", ResultScreen.new())
	_add_screen("developer", DeveloperScreen.new())
	# Toasts live in the content area, anchored top-wide; each toast is shrink-centred, so they stay
	# centred over the content on every resize without manual positioning.
	toast_box = UITheme.vbox(8)
	toast_box.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	toast_box.offset_top = 18
	toast_box.offset_bottom = 18
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(toast_box)
	_fit_window.call_deferred()
	if bool(Settings.get_v("fullscreen", false)):
		set_fullscreen.call_deferred(true, false)
	goto("home")
	_dev_args()


## Wraps every built-in tooltip (see UITheme.wrap_tooltip_node).
func _on_node_added(n: Node) -> void :
	if n is Label:
		UITheme.wrap_tooltip_node(n)



func _fit_window() -> void :
	if DisplayServer.get_name() == "headless" or Engine.is_embedded_in_editor():
		return
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		return
	var screen: = DisplayServer.window_get_current_screen()
	var usable: = DisplayServer.screen_get_usable_rect(screen)
	var win: = DisplayServer.window_get_size()
	if usable.size.x <= 0 or usable.size.y <= 0:
		return
	if win.x <= usable.size.x * 0.96 and win.y <= usable.size.y * 0.92:
		return
	var s: = minf(usable.size.x * 0.9 / win.x, usable.size.y * 0.86 / win.y)
	var ns: = Vector2i(int(win.x * s), int(win.y * s))
	DisplayServer.window_set_size(ns)
	DisplayServer.window_set_position(usable.position + Vector2i(Vector2(usable.size - ns) * 0.5))



func _unhandled_key_input(event: InputEvent) -> void :
	var k: = event as InputEventKey
	if k and k.pressed and not k.echo and k.keycode == KEY_F11:
		set_fullscreen( not is_fullscreen())
		get_viewport().set_input_as_handled()


func is_fullscreen() -> bool:
	var m: = DisplayServer.window_get_mode()
	return m == DisplayServer.WINDOW_MODE_FULLSCREEN or m == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN



func set_fullscreen(on: bool, remember: bool = true) -> void :
	if DisplayServer.get_name() == "headless":
		return
	if Engine.is_embedded_in_editor():
		toast("편집기에 내장된 실행 창에서는 전체 화면을 쓸 수 없어요", UITheme.WARN)
		_sync_fullscreen_ui()
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)
	if not on:
		_fit_window.call_deferred()
	if remember and bool(Settings.get_v("fullscreen", false)) != on:
		Settings.set_v("fullscreen", on)
	_sync_fullscreen_ui()


func _sync_fullscreen_ui() -> void :
	var st = screens.get("settings")
	if st and st.has_method("sync_fullscreen"):
		st.sync_fullscreen()



var _shot_path: String = ""
var _shot_frames: int = 0
var _shot_every: int = 0
var _shot_count: int = 1
var _shot_idx: int = 0
var _perf: = false


func _dev_args() -> void :
	for a in OS.get_cmdline_user_args():
		if a == "--perf":
			_perf = true
		elif a.begins_with("--goto="):
			goto(a.substr(7))
		elif a.begins_with("--developer-case="):
			# Reproducible lab startup: mode/map/seed/ticks. Starts paused.
			var parts: PackedStringArray = a.substr(17).split("/")
			var lab: DeveloperScreen = screens.developer
			goto("developer")
			var mode_index: int = DeveloperScreen.MODES.find(parts[0])
			if mode_index >= 0:
				lab.mode_option.select(mode_index)
				lab._change_mode()
			if parts.size() > 1 and lab.map_ids.has(parts[1]):
				lab.map_option.select(lab.map_ids.find(parts[1]))
				lab._map_hint()
			if parts.size() > 2:
				lab.seed_input.value = int(parts[2])
			lab.start_case()
			if parts.size() > 3:
				var ticks_left: int = clampi(int(parts[3]), 0, 14400)
				while ticks_left > 0 and not lab.runner.done:
					lab.advance_ticks(mini(ticks_left, 300))
					ticks_left -= 300
		elif a.begins_with("--codex="):
			# --codex=<mode>[/<id>] : open the codex on a mode (chars/arenas/items/glossary) and entry.
			var cx: PackedStringArray = a.substr(8).split("/")
			var cargs: Dictionary = {"mode": cx[0], "item": cx[1] if cx.size() > 1 else ""}
			if cx[0] == "chars" and cx.size() > 1:
				cargs["character"] = cx[1]
			goto("codex", cargs)
		elif a.begins_with("--toast="):
			# --toast=<text> (underscores become spaces): QA preview of the toast style.
			toast(a.substr(8).replace("_", " "), UITheme.WARN)
		elif a.begins_with("--ruleset="):
			if current in ["setup", "draft"]:
				screens[current]._set_ruleset(a.substr(10))
		elif a.begins_with("--demo-preview="):
			var preview_parts: PackedStringArray = a.substr(15).split("/")
			goto("codex", {"character": preview_parts[0], "entry": preview_parts[1] if preview_parts.size() > 1 else ""})
		elif a.begins_with("--demo-battle"):
			var arena: = "ruined_gate"
			if a.contains("="):
				arena = a.split("=")[1]
			var demo_comp: Array = [["swordsman", "mage", "aphrodite"], ["werewolf", "sniper", "metatron"]]
			# --demo-comp=<id,id,..>|<id,id,..> : blue|red comps for --demo-battle (either order).
			for ca: String in OS.get_cmdline_user_args():
				if ca.begins_with("--demo-comp=") and ca.contains("|"):
					var halves: PackedStringArray = ca.substr(12).split("|")
					demo_comp = [Array(halves[0].split(",", false)), Array(halves[1].split(",", false))]
			start_battle({"blue": demo_comp[0], "red": demo_comp[1], "arena_id": arena, "seed": 20260923, "blue_ai": "tactician", "red_ai": "tactician", "mode": "composition"}, "setup")
		elif a.begins_with("--demo-comp=") and a.contains("|"):
			pass
		elif a.begins_with("--demo-comp="):

			var parts: = a.substr(12).split("/")
			start_battle({"blue": Array(parts[0].split(",")), "red": Array(parts[1].split(",")) if parts.size() > 1 else ["giant"],
				"arena_id": parts[2] if parts.size() > 2 else "classic", "seed": int(parts[3]) if parts.size() > 3 else 20260924,
				"blue_ai": "tactician", "red_ai": "tactician", "mode": "composition"}, "setup")
		elif a.begins_with("--vfx-gallery"):

			var gv: = int(a.split("=")[1]) if a.contains("=") else 1
			start_battle(DevGallery.config(gv), "setup")
			var gbs: BattleScreen = screens.battle
			DevGallery.setup(gbs.runner.sim, gv)
			gbs.runner.paused = true
			if gv == 4:
				DevGallery.events(gbs.view, 0.35)
		elif a.begins_with("--demo-dm"):
			# --demo-dm=N[/map[/seed]] : N-player free-for-all with random heroes.
			var dm_parts: PackedStringArray = (a.split("=")[1] if a.contains("=") else "8").split("/")
			var dm_n: int = clampi(int(dm_parts[0]), 2, 12)
			var dm_seed: int = int(dm_parts[2]) if dm_parts.size() > 2 else 20261001
			var dm_rng: RandomNumberGenerator = RandomNumberGenerator.new()
			dm_rng.seed = dm_seed
			var dm_pool: Array = DB.ids().duplicate()
			var dm_players: Array = []
			for _i in dm_n:
				dm_players.append(dm_pool.pop_at(dm_rng.randi_range(0, dm_pool.size() - 1)))
			start_battle({"ruleset": "deathmatch", "mode": "deathmatch", "arena_id": dm_parts[1] if dm_parts.size() > 1 else DeathmatchMapData.ORDER[0],
				"players": dm_players, "seed": dm_seed, "kill_target": 10, "max_time": 420.0, "ai": "tactician"}, "deathmatch")
		elif a.begins_with("--demo-br"):
			# V2 (B-MODE) --demo-br=solo|duo|trio/N[/map[/seed[/fast|normal|slow[/max_time]]]] : battleground
			# with random heroes, N players (solo) or teams; solo may repeat a hero across players. A short
			# max_time (B-UI) ends the match early for report screenshots.
			var br_parts: PackedStringArray = (a.split("=")[1] if a.contains("=") else "solo/12").split("/")
			var br_squad: int = int({"solo": 1, "duo": 2, "trio": 3}.get(br_parts[0], 1))
			var br_cap: int = floori(float(BattlegroundMode.MAX_HEROES) / float(br_squad))
			var br_n: int = clampi(int(br_parts[1]) if br_parts.size() > 1 else 12, 2, br_cap)
			var br_map: String = br_parts[2] if br_parts.size() > 2 and BattlegroundMapData.is_battleground_id(br_parts[2]) else str(BattlegroundMapData.ORDER[0])
			var br_seed: int = int(br_parts[3]) if br_parts.size() > 3 else 20261001
			var br_rng: RandomNumberGenerator = RandomNumberGenerator.new()
			br_rng.seed = br_seed
			var br_teams: Array = []
			for _t in br_n:
				var br_pool: Array = DB.ids().duplicate()
				var br_team: Array = []
				for _m in br_squad:
					br_team.append(br_pool.pop_at(br_rng.randi_range(0, br_pool.size() - 1)))
				br_teams.append(br_team)
			start_battle({"ruleset": "battleground", "mode": "battleground", "arena_id": br_map, "seed": br_seed, "squad": br_squad,
				"teams": br_teams, "zone_speed": br_parts[4] if br_parts.size() > 4 else "normal",
				"max_time": clampf(float(br_parts[5]), 10.0, BattlegroundMode.MAX_TIME) if br_parts.size() > 5 else BattlegroundMode.MAX_TIME,
				"ai": "tactician"}, "battleground")
		elif a.begins_with("--br-setup="):
			# V2 (B-UI) --br-setup=solo|duo|trio[/N[/tab]] : the battleground setup screen with a
			# random roster of that format (tab: chars / items / zone).
			var bs_parts: PackedStringArray = a.substr(11).split("/")
			var bs_args: Dictionary = {"format": bs_parts[0]}
			if bs_parts.size() > 1:
				bs_args["scale"] = int(bs_parts[1])
			if bs_parts.size() > 2:
				bs_args["tab"] = bs_parts[2]
			goto("battleground", bs_args)
		elif a.begins_with("--demo5"):
			var arena5: = "wind_temple"
			if a.contains("="):
				arena5 = a.split("=")[1]
			start_battle({"blue": ["giant", "archer", "mage", "aphrodite", "hermes"], "red": ["nitro", "sniper", "metatron", "hive_mind", "engineer"], "arena_id": arena5, "seed": 777, "blue_ai": "tactician", "red_ai": "tactician", "mode": "composition"}, "setup")
		elif a.begins_with("--shot="):
			_shot_path = a.substr(7)
			if _shot_frames == 0:
				_shot_frames = 120
		elif a.begins_with("--shot-frames="):
			_shot_frames = int(a.substr(14))
		elif a.begins_with("--shot-every="):

			_shot_every = int(a.substr(13))
		elif a.begins_with("--shot-count="):
			_shot_count = maxi(int(a.substr(13)), 1)
		elif a.begins_with("--speed="):
			(screens.battle as BattleScreen).runner.speed = float(a.substr(8))
		elif a.begins_with("--vision="):
			(screens.battle as BattleScreen)._set_vision(int(a.substr(9)))
		elif a == "--draft-auto":
			goto("draft")
			(screens.draft as DraftScreen).auto_user = true
		elif a.begins_with("--tab="):
			var bs: BattleScreen = screens.battle
			bs.tabs.current_tab = int(a.substr(6))
		elif a.begins_with("--cam="):

			var cv: = a.substr(6).split(",")
			var cbv: BattleView = (screens.battle as BattleScreen).view
			cbv.cam_mode = "manual"
			cbv.cam_center_t = Vector2(float(cv[0]), float(cv[1]))
			cbv.cam_center = cbv.cam_center_t
			cbv.cam_zoom_t = float(cv[2]) if cv.size() > 2 else 2.0
			cbv.cam_zoom = cbv.cam_zoom_t
		elif a.begins_with("--warp="):

			(screens.battle as BattleScreen).runner.warp(float(a.substr(7)))
		elif a.begins_with("--select="):
			(screens.battle as BattleScreen)._select(int(a.substr(9)))


var _perf_frames: int = 0
var _perf_t0: int = 0


func _process(_delta: float) -> void :
	if _perf:
		_perf_frames += 1
		if _perf_frames == 60:
			_perf_t0 = Time.get_ticks_usec()
		elif _perf_frames == 360:
			var ms: = (Time.get_ticks_usec() - _perf_t0) / 1000.0 / 300.0
			print("PERF avg frame %.2f ms (%.0f fps)  process %.2f ms" % [ms, 1000.0 / ms, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0])
			get_tree().quit()
	if _shot_path != "" and Engine.get_process_frames() >= _shot_frames:
		var img: = get_viewport().get_texture().get_image()
		var path: = _shot_path
		if _shot_count > 1:
			path = "%s_%02d.png" % [_shot_path.get_basename(), _shot_idx]
		img.save_png(path)
		print("SHOT saved ", path, " ", img.get_size())
		_shot_idx += 1
		if _shot_idx >= _shot_count:
			_shot_path = ""
			get_tree().quit()
		else:
			_shot_frames += maxi(_shot_every, 1)


func _glow_env() -> void :
	var env: = WorldEnvironment.new()
	var e: = Environment.new()
	e.background_mode = Environment.BG_CANVAS
	e.glow_enabled = true
	e.glow_intensity = 0.9
	e.glow_strength = 1.05
	e.glow_bloom = 0.0
	e.glow_hdr_threshold = 1.02
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	e.set_glow_level(0, 0.0)
	e.set_glow_level(1, 1.0)
	e.set_glow_level(2, 0.8)
	e.set_glow_level(3, 0.6)
	e.set_glow_level(4, 0.35)
	env.environment = e
	add_child(env)


# ------------------------------------------------------------------ sidebar

func _build_sidebar() -> PanelContainer:
	var st: = UITheme.sb(Color(UITheme.BG2, 0.94), Color(1, 1, 1, 0.07), 0, 0, 0, 0)
	st.border_width_right = 1
	var p: = UITheme.styled_panel(st)
	p.custom_minimum_size = Vector2(SIDEBAR_W, 0)
	var v: = UITheme.vbox(2)
	p.add_child(UITheme.margin(v, 14, 22, 15, 18))

	# Brand block.
	var brand: = UITheme.hbox(11)
	var disc: = BrandDisc.new()
	disc.custom_minimum_size = Vector2(38, 38)
	disc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	brand.add_child(disc)
	var bv: = UITheme.vbox(0)
	bv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bv.add_child(UITheme.label("DVD BATTLE", "BlackLabel", 19))
	var sub: = UITheme.label("GODOT EDITION · NEXUS", "EyebrowLabel")
	sub.add_theme_font_override("font", DB.font_bold)
	sub.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	bv.add_child(sub)
	brand.add_child(bv)
	v.add_child(UITheme.margin(brand, 4, 0, 0, 0))
	v.add_child(UITheme.spacer(0, 16))

	# Grouped navigation.
	nav_group = ButtonGroup.new()
	for g in NAV_GROUPS:
		var gl: = UITheme.label(str(g[1]), "FaintLabel", 12)
		gl.add_theme_font_override("font", DB.font_bold)
		v.add_child(UITheme.margin(gl, 12, 12, 0, 4))
		for row in NAV:
			if row[3] != g[0]:
				continue
			var id: String = row[0]
			var b: = NavItem.new(str(row[2]), str(row[1]))
			b.toggle_mode = true
			b.button_group = nav_group
			b.pressed.connect(func(): _nav_pressed(id))
			nav_buttons[id] = b
			v.add_child(b)

	v.add_child(UITheme.expand(UITheme.spacer(0, 8), true, true))
	# Resume shortcut: shown while a battle runs in the background (bottom, so the nav never shifts).
	resume_btn = NavItem.new("▶", "진행 중 전투", UITheme.GOLD)
	resume_btn.tooltip_text = "진행 중인 전투 화면으로 돌아갑니다"
	resume_btn.pressed.connect(func(): goto("battle"))
	resume_btn.visible = false
	v.add_child(resume_btn)
	v.add_child(UITheme.spacer(0, 10))

	var foot: = UITheme.vbox(6)
	foot.add_child(UITheme.sep_line())
	foot.add_child(UITheme.spacer(0, 4))
	foot.add_child(UITheme.label("TACTICIAN · %s" % VERSION, "EyebrowLabel"))
	foot.add_child(UITheme.wrap_label("관측하고, 추론하고, 대응한다.\n보이지 않는 적은 가설로 쫓는다.", "FaintLabel", 12))
	v.add_child(UITheme.margin(foot, 4, 0, 0, 0))
	return p


func _nav_pressed(id: String) -> void :
	if id != current:
		Sfx.play("click", 0.35)
	goto(id)


func _sync_nav(id: String) -> void :
	for k in nav_buttons:
		(nav_buttons[k] as Button).set_pressed_no_signal(k == id or (id == "result" and k == battle_origin))


func _add_screen(id: String, s: Control) -> void :
	s.name = id
	s.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	s.visible = false
	content.add_child(s)
	screens[id] = s
	if s.has_method("bind"):
		s.bind(self)


## Shows screen `id` and calls its on_show(args). Going to the current screen with empty args is a
## no-op (no flash); with args the screen just receives on_show(args) again (no fade).
func goto(id: String, args: Dictionary = {}) -> void :
	if not screens.has(id):
		return
	if id == current and args.is_empty():
		_sync_nav(id)
		return
	var switching: = id != current
	if current != "" and switching:
		var old: Control = screens[current]
		if old.has_method("on_hide"):
			old.on_hide()
		old.visible = false
	current = id
	var s: Control = screens[id]
	s.visible = true
	if switching:
		if _fade_tw and _fade_tw.is_valid():
			_fade_tw.kill()
		s.modulate = Color(1, 1, 1, 0)
		_fade_tw = create_tween()
		_fade_tw.tween_property(s, "modulate", Color.WHITE, 0.18)
	if s.has_method("on_show"):
		s.on_show(args)
	var full: = id == "battle"
	sidebar.visible = not full
	bg.visible = not full
	bg.dim_t = 1.0 if id == "home" else 0.22
	_sync_nav(id)
	var bs: BattleScreen = screens.battle
	resume_btn.visible = id != "battle" and bs.is_running()



func start_battle(cfg: Dictionary, origin: String) -> void :
	last_battle = cfg.duplicate(true)
	battle_origin = origin
	goto("battle", {"config": cfg})


func show_result(result: Dictionary, cfg: Dictionary) -> void :
	goto("result", {"result": result, "config": cfg})


# ------------------------------------------------------------------ toasts

## Short notice at the top centre of the content area. color picks the severity stripe/icon
## (UITheme.WARN, BAD, GOOD; anything else = info). Wraps at 480 px; at most 3 visible.
func toast(text: String, color: Color = UITheme.ACCENT) -> void :
	for c in toast_box.get_children():
		if c.has_meta("toast_text") and str(c.get_meta("toast_text")) == text:
			c.queue_free()
	var live: Array = toast_box.get_children().filter(func(c): return not c.is_queued_for_deletion())
	while live.size() >= TOAST_MAX:
		(live.pop_front() as Node).queue_free()
	var p: = PanelContainer.new()
	p.theme_type_variation = "OverlayPanel"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	p.set_meta("toast_text", text)
	var h: = UITheme.hbox(10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var stripe: = Panel.new()
	stripe.add_theme_stylebox_override("panel", UITheme.sbc(color, UITheme.CLEAR, 2, 0, 0, 0))
	stripe.custom_minimum_size = Vector2(3, 0)
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(stripe)
	var glyph: = "●"
	if color == UITheme.WARN or color == UITheme.GOLD:
		glyph = "▲"
	elif color == UITheme.BAD:
		glyph = "✕"
	elif color == UITheme.GOOD:
		glyph = "✓"
	var ic: = UITheme.label(glyph, "", 13, color)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ic.custom_minimum_size = Vector2(14, 0)
	ic.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	h.add_child(ic)
	var l: = UITheme.label(text, "", 14, UITheme.TEXT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var widest: = 0.0
	for line in text.split("\n"):
		widest = maxf(widest, DB.font_regular.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x)
	# 480 max minus panel padding (2x14), stripe (3), icon (14) and gaps (2x10).
	l.custom_minimum_size = Vector2(minf(ceilf(widest) + 2.0, TOAST_MAX_W - 65.0), 0)
	h.add_child(l)
	p.add_child(h)
	toast_box.add_child(p)
	p.modulate = Color(1, 1, 1, 0)
	var tw: = p.create_tween()
	tw.tween_property(p, "modulate", Color.WHITE, 0.15)
	tw.tween_interval(2.4 if text.length() < 40 else 3.4)
	tw.tween_property(p, "modulate", Color(1, 1, 1, 0), 0.35)
	tw.tween_callback(p.queue_free)


# ------------------------------------------------------------------ sidebar widgets

## Sidebar nav item: fixed-width icon column + label, accent tint and a drawn 3px accent bar when
## active. Label colours follow the button state (updated only when the state changes).
class NavItem:
	extends Button
	var icon_l: Label
	var text_l: Label
	var tint: Color
	var _state: int = -1

	func _init(glyph: String, title: String, tint_color: Color = UITheme.ACCENT) -> void :
		tint = tint_color
		theme_type_variation = "NavButton"
		focus_mode = Control.FOCUS_NONE
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		custom_minimum_size = Vector2(0, 40)
		var h: = UITheme.hbox(10)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		h.offset_left = 12
		h.offset_right = -10
		icon_l = UITheme.label(glyph, "", 16)
		icon_l.custom_minimum_size = Vector2(22, 0)
		icon_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		icon_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		icon_l.size_flags_vertical = Control.SIZE_FILL
		icon_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(icon_l)
		text_l = UITheme.label(title, "", 15)
		text_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		text_l.size_flags_vertical = Control.SIZE_FILL
		text_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		UITheme.ellipsize(text_l)
		h.add_child(text_l)
		add_child(h)
		if tint != UITheme.ACCENT:
			# Emphasised action (resume): tinted surface in its own colour.
			add_theme_stylebox_override("normal", UITheme.sbc(Color(tint, 0.07), Color(tint, 0.28), UITheme.R_M, 1, 12, 8))
			add_theme_stylebox_override("hover", UITheme.sbc(Color(tint, 0.13), Color(tint, 0.45), UITheme.R_M, 1, 12, 8))
			add_theme_stylebox_override("pressed", UITheme.sbc(Color(tint, 0.18), Color(tint, 0.55), UITheme.R_M, 1, 12, 8))
			add_theme_stylebox_override("hover_pressed", UITheme.sbc(Color(tint, 0.18), Color(tint, 0.55), UITheme.R_M, 1, 12, 8))
		_apply_state()

	func _apply_state() -> void :
		var st: = get_draw_mode()
		if st == _state:
			return
		_state = st
		var on: = button_pressed and toggle_mode
		var hot: = st == DRAW_HOVER or st == DRAW_HOVER_PRESSED
		var fg: Color = UITheme.TEXT if (on or hot) else UITheme.TEXT_DIM
		var ic: Color = UITheme.ACCENT if on else fg
		if tint != UITheme.ACCENT:
			fg = tint.lightened(0.25) if hot else tint
			ic = fg
		icon_l.add_theme_color_override("font_color", ic)
		text_l.add_theme_color_override("font_color", fg)
		text_l.add_theme_font_override("font", DB.font_bold if on else DB.font_regular)

	func _draw() -> void :
		_apply_state()
		if button_pressed and toggle_mode:
			draw_style_box(UITheme.sbc(tint, UITheme.CLEAR, 2, 0, 0, 0), Rect2(0, 10, 3, size.y - 20))


## Animated brand mark (redrawn at 30 Hz, paused while hidden).
class BrandDisc:
	extends Control
	var t: = 0.0
	var _acc: = 0.0

	func _ready() -> void :
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void :
		t += delta
		_acc += delta
		if _acc >= 1.0 / 30.0:
			_acc = 0.0
			if is_visible_in_tree():
				queue_redraw()

	func _draw() -> void :
		var c: = size * 0.5
		var r: = minf(size.x, size.y) * 0.5 - 1.0
		var col: = UITheme.ACCENT.lerp(UITheme.RED, 0.5 + 0.5 * sin(t * 0.8))
		draw_circle(c, r, Color(col, 0.16))
		draw_arc(c, r, 0, TAU, 48, col, 2.0, true)
		draw_arc(c, r * 0.6, t * 1.5, t * 1.5 + PI, 24, Color(col, 0.7), 2.0, true)
		draw_circle(c, r * 0.18, UITheme.BG)
		draw_arc(c, r * 0.18, 0, TAU, 16, col, 1.2, true)
