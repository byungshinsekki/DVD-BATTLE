extends Node

# Battleground UI kit (V2 wave 1, B-UIKIT): a rendered gallery of the mode-independent widgets
# (TeamChip, ZonePill, Minimap, BrStanding, SurvivorChart, the 15-colour team palette and the
# RosterCard count badge) fed with deterministic fixture matches for solo 30, duo 15 and trio 10.
# Checks sizes, palette separation, zone texts, minimap geometry and clicks, standing order,
# survivor series and font coverage, then writes a JSON report and one screenshot per format.
# Needs an isolated QA project: run it only through zz_work/tools/gd.ps1 -Mode uitest.

const FORMATS: = [["solo", 1, 30], ["duo", 2, 15], ["trio", 3, 10]]
const NOW: = 300.0
# DESIGN_V2 §3.3 normal-speed schedule: [phase, shrink start, shrink end, damage ratio].
const PHASES: = [[1, 75.0, 135.0, 0.01], [2, 195.0, 240.0, 0.02], [3, 280.0, 315.0, 0.035],
	[4, 345.0, 370.0, 0.05], [5, 390.0, 410.0, 0.08], [6, 425.0, 455.0, 0.12]]
# The V1.5 deathmatch colours; UITheme.FFA must keep them as its first 12 entries.
const FFA_V15: = ["#56a7ff", "#ff6d79", "#6fe08a", "#f4c96b", "#b58cff", "#4fe3e0",
	"#ff9a4d", "#ff7fc8", "#c8f06a", "#8c9bff", "#ece6d6", "#d09a62"]
# Every non-ASCII character the widgets draw (tooltips included); the bundled fonts must have them.
const WIDGET_TEXT: = ["약탈 시간", "자기장 예고", "자기장 수축", "최종 자기장", "자기장 3/6 · 수축 0:42 · 2%/s",
	"단계 원으로 줄어드는 중", "다음 원 공개", "바깥", "안전 지대 없음", "자기장 없음 · 아이템을 모으세요", "곧 수축", "최종",
	"생존 · 9팀 17명", "탈락 · 6팀", "12위 · 3:41 탈락", "다운 · 출혈 12초", "사망", "처치 다운시킴 소생 피해",
	"생존 영웅", "생존 팀", "영웅 팀", "기록이 없습니다", "우승", "지도 없음", "팀 탈락", "×2", "⚔", "▲", "—", "…",
	"미니맵 — 누르거나 끌면 그 위치로 카메라를 옮깁니다.", "P30", "15팀"]
const BUNDLED_FONTS: = ["res://assets/fonts/ui_regular.otf", "res://assets/fonts/ui_bold.otf",
	"res://assets/fonts/ui_black.otf", "res://assets/fonts/symbols.ttf"]

var checks: int = 0
var failures: int = 0
var records: Array = []
var shot_dir: String = ""
var shots: Array = []
var measurements: Dictionary = {}
var root: Control


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
		# gd.ps1 passes --qa-dir only to some suites; fall back to the report's folder.
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
	await _frames(8)
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(shot_dir)
	var path: String = shot_dir.path_join(name + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	shots.append(path)
	print("SHOT ", path)


func _run() -> void:
	DB.ensure_loaded()
	root = Control.new()
	root.theme = UITheme.build()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_tree().root.add_child(root)
	var bg: = ColorRect.new()
	bg.color = UITheme.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	_check_palette()
	_check_names()
	_check_fonts()
	_check_zone_texts()
	await _check_roster_badge()
	var arena: Arena = Arena.from_data(_br_fixture_map(4242))
	_check(Minimap.rasterize(arena).get_data() == Minimap.rasterize(arena).get_data(), "minimap raster is a pure function of the arena")
	_check(SurvivorChart.time_step(492.0, 1100.0) == 60.0 and SurvivorChart.time_step(600.0, 300.0) == 300.0, "survivor chart time labels use round steps")
	for f in FORMATS:
		await _page(str(f[0]), int(f[1]), int(f[2]), arena)
	print("UI_VALIDATION_BR_WIDGETS ", checks, " PASS / ", failures, " FAIL")
	var report_path: String = "res://reports/br_widgets_v2.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ui-report="):
			report_path = arg.substr(12)
	DirAccess.make_dir_recursive_absolute(report_path.get_base_dir())
	var file: FileAccess = FileAccess.open(report_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"suite": "br_widgets_v2", "passed": checks, "failed": failures,
			"isolated_user_dir": ProjectSettings.get_setting("application/config/custom_user_dir_name"),
			"measurements": measurements, "shots": shots, "checks": records}, "  "))
		file.close()
	root.queue_free()
	await _frames(2)
	get_tree().quit(1 if failures else 0)


# ------------------------------------------------------------------ static checks

static func _lin(c: float) -> float:
	return c / 12.92 if c <= 0.04045 else pow((c + 0.055) / 1.055, 2.4)


## OKLab coordinates of an sRGB colour (perceptual distance between team colours).
static func _oklab(col: Color) -> Vector3:
	var r: float = _lin(col.r)
	var g: float = _lin(col.g)
	var b: float = _lin(col.b)
	var l: float = pow(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b, 1.0 / 3.0)
	var m: float = pow(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b, 1.0 / 3.0)
	var s: float = pow(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b, 1.0 / 3.0)
	return Vector3(0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
		1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
		0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)


func _check_palette() -> void:
	_check(UITheme.FFA.size() == 15, "FFA palette has 15 colours")
	var same: bool = true
	for i in FFA_V15.size():
		if (UITheme.FFA[i] as Color).to_html(false) != Color(FFA_V15[i]).to_html(false):
			same = false
	_check(same, "first 12 FFA colours are unchanged from V1.5")
	_check(UITheme.team_color(0) == UITheme.BLUE and UITheme.team_color(1) == UITheme.RED, "teams 0 / 1 keep blue / red")
	var labs: Array = []
	for i in 15:
		labs.append(_oklab(UITheme.team_color(i)))
	var min_all: float = 9.0
	var min_new: float = 9.0
	for i in 15:
		for j in range(i + 1, 15):
			var d: float = (labs[i] as Vector3).distance_to(labs[j])
			min_all = minf(min_all, d)
			if j >= 12:
				min_new = minf(min_new, d)
	measurements["palette_min_oklab_all"] = snappedf(min_all, 0.001)
	measurements["palette_min_oklab_new"] = snappedf(min_new, 0.001)
	_check(min_all >= 0.055, "15 team colours are distinct (min OKLab distance %.3f)" % min_all)
	_check(min_new >= 0.1, "the 3 new colours are well separated (min OKLab distance %.3f >= 0.1)" % min_new)
	var lighter: bool = true
	for i in 15:
		var base: Color = UITheme.team_color(i)
		var v: Color = UITheme.team_color(15 + i)
		if v.get_luminance() <= base.get_luminance() or v == base or not UITheme.team_needs_label(15 + i) or UITheme.team_needs_label(i):
			lighter = false
	_check(lighter, "teams 15+ use a lighter variant and need their label")
	_check(UITheme.team_color(29) == UITheme.team_color(14).lightened(UITheme.FFA_LIGHTEN), "team 29 = team 14 lightened")


func _check_names() -> void:
	_check(DB.team_name(2, 2) == "3팀" and DB.team_name(14, 3) == "15팀", "DB.team_name gives n팀 for squads")
	_check(DB.team_name(6, 1) == "P7" and DB.team_name(29, 1) == "P30", "DB.team_name gives P{n} for solo")
	_check(UITheme.team_label(9, 2) == "10팀" and UITheme.team_label(0) == "P1", "UITheme.team_label delegates to DB.team_name")
	_check(DB.TEAM_NAMES == ["청 팀", "홍 팀"], "DB.TEAM_NAMES unchanged")


func _fresh_font(path: String) -> Font:
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as Font


func _check_fonts() -> void:
	var fonts: Array = []
	for p in BUNDLED_FONTS:
		var f: Font = _fresh_font(p)
		if f:
			fonts.append(f)
	_check(fonts.size() == BUNDLED_FONTS.size(), "bundled UI fonts load")
	var missing: Dictionary = {}
	for s in WIDGET_TEXT:
		for ch in str(s):
			var code: int = ch.unicode_at(0)
			if code < 128 or missing.has(ch):
				continue
			var ok: bool = false
			for f in fonts:
				if (f as Font).has_char(code):
					ok = true
					break
			if not ok:
				missing[ch] = true
	measurements["glyphs_missing"] = missing.keys()
	_check(missing.is_empty(), "every widget character is in the bundled fonts (missing: %s)" % "".join(PackedStringArray(missing.keys())))
	# Negative control: a symbol the fonts are known not to cover must be reported missing.
	var probe: bool = false
	for f in fonts:
		if (f as Font).has_char("⛨".unicode_at(0)):
			probe = true
	_check(not probe, "coverage probe detects an uncovered symbol (⛨)")


func _zone(state: String, phase: int, end: float, dps: float, known: bool) -> Dictionary:
	return {"phase": phase, "phases_total": 6, "state": state, "t_state_end": end, "dps_ratio": dps, "next_known": known,
		"center": Vector2(3600, 2200), "radius": 2000.0, "next_center": Vector2(3500, 2100), "next_radius": 1200.0}


func _check_zone_texts() -> void:
	var p: = ZonePill.new()
	p.set_view(_zone("shrink", 2, 240.0, 0.02, true))
	p.set_time(198.0)
	_check(p.text() == "자기장 2/6 · 수축 0:42 · 2%/s", "zone pill shrink text: " + p.text())
	p.set_view(_zone("wait", 1, 195.0, 0.0, true))
	p.set_time(180.0)
	_check(p.text() == "자기장 예고 0:15", "zone pill announce text: " + p.text())
	p.set_view(_zone("wait", 1, 195.0, 0.01, true))
	_check(p.text() == "자기장 예고 0:15 · 1%/s", "zone pill announce text with damage: " + p.text())
	p.set_view(_zone("loot", 0, 75.0, 0.0, false))
	p.set_time(10.0)
	_check(p.text() == "약탈 시간 1:05", "zone pill loot text: " + p.text())
	p.set_view(_zone("final", 6, 600.0, 0.12, true))
	p.set_time(470.0)
	_check(p.text() == "자기장 6/6 · 최종 · 12%/s" and p.remaining() < 0.0, "zone pill final text: " + p.text())
	_check(ZonePill.dps_text(0.035) == "3.5%/s" and ZonePill.dps_text(0.0) == "", "zone damage format")
	_check(BrStanding.downed_text({"downed_left": 12.2, "revive": 0.4}) == "다운 · 출혈 13초 · 소생 40%"
		and BrStanding.downed_text({"downed_left": 9.0}) == "다운 · 출혈 9초", "standing downed line with revive progress")
	_check(BrStanding.out_text({"place": 12, "elim_time": 221.0}) == "12위 · 3:41 탈락", "standing eliminated line text")
	p.free()


func _check_roster_badge() -> void:
	var host: = HBoxContainer.new()
	host.position = Vector2(-2000, -2000)
	root.add_child(host)
	var card: = RosterCard.new(DB.characters[0])
	host.add_child(card)
	card.set_count(2)
	await _frames(2)
	_check(card.count_badge != null and card.count_badge.visible and card.count_badge.text == "×2", "roster card shows ×2")
	var b: Rect2 = Rect2(card.count_badge.position, card.count_badge.size)
	_check(Rect2(Vector2.ZERO, card.size).encloses(b) and b.position.x > card.size.x * 0.5 and b.position.y < 12.0, "count badge sits in the top-right corner")
	card.set_count(1)
	_check(not card.count_badge.visible, "count badge hidden for n = 1")
	card.set_count(3)
	_check(card.count_badge.visible and card.count_badge.text == "×3", "count badge updates to ×3")
	card.set_count(0)
	_check(not card.count_badge.visible, "count badge hidden for n = 0")
	host.queue_free()


# ------------------------------------------------------------------ fixtures

static func _off(d: Dictionary, o: Vector2) -> Dictionary:
	var c: Dictionary = d.duplicate(true)
	if c.has("x"):
		c["x"] = float(c.x) + o.x
	if c.has("y"):
		c["y"] = float(c.y) + o.y
	if c.has("target"):
		c["target"] = {"x": float(c.target.x) + o.x, "y": float(c.target.y) + o.y}
	return c


## Battleground-scale stand-in map (B-WORLD's generator is not in this tree yet): 2x2 deathmatch
## layouts (7200x4400) plus a river (water chasm) with mud fords, so every minimap layer shows.
func _br_fixture_map(seed_value: int) -> Dictionary:
	var tw: float = 3600.0
	var th: float = 2200.0
	var presets: Array = ["dm_forest_village", "dm_ruined_town", "dm_open_steppe", "dm_forest_village"]
	var obstacles: Array = []
	var forests: Array = []
	var buildings: Array = []
	var hazards: Array = []
	var k: int = 0
	for ty in 2:
		for tx in 2:
			var o: = Vector2(tx * tw, ty * th)
			var d: Dictionary = DeathmatchMapData.build(str(presets[k]), seed_value + k * 13)
			for ob in d.obstacles:
				var c: Dictionary = _off(ob, o)
				c["id"] = "t%d_%s" % [k, str(c.get("id", ""))]
				obstacles.append(c)
			for f in d.forests:
				var c2: Dictionary = _off(f, o)
				c2["patch"] = int(f.get("patch", 0)) + k * 1000
				forests.append(c2)
			for b in d.buildings:
				buildings.append(_off(b, o))
			for h in d.hazards:
				var c4: Dictionary = _off(h, o)
				c4["id"] = "t%d_%s" % [k, str(c4.get("id", ""))]
				hazards.append(c4)
			k += 1
	# River: vertical water chasm segments with two mud fords as crossings.
	var x: float = 5050.0
	for seg in [[60.0, 1180.0], [1420.0, 2820.0], [3060.0, 4340.0]]:
		obstacles.append({"id": "river_%d" % int(seg[0]), "shape": "rect", "x": x, "y": seg[0], "w": 150.0, "h": seg[1] - seg[0],
			"kind": "chasm", "material": "water", "blocksUnits": true, "blocksProjectiles": false, "blocksVision": false, "color": "#2a5b80"})
	for fy in [1180.0, 2820.0]:
		hazards.append({"id": "ford_%d" % int(fy), "label": "진흙 여울", "shape": "rect", "type": "mud", "x": x - 40.0, "y": fy, "w": 230.0, "h": 240.0,
			"slow": 0.4, "color": "#7a5e3c"})
	return {"id": "br_fixture_%d" % seed_value, "name": "배틀그라운드 견본", "ruleset": "deathmatch", "accent": "#7fd08a",
		"width": tw * 2.0, "height": th * 2.0, "bounds": {"minX": 40.0, "maxX": tw * 2.0 - 40.0, "minY": 40.0, "maxY": th * 2.0 - 40.0},
		"floor": {"base": "#0c1a12", "blue": "#16435c", "red": "#542f4b", "grid": "#7fd08a"},
		"obstacles": obstacles, "forests": forests, "buildings": buildings, "hazards": hazards, "control_points": [], "heal_zones": [],
		"spawns": {"blue": [{"x": 400.0, "y": 400.0}], "red": [{"x": 6800.0, "y": 4000.0}]}}


## A whole fixture match: per team {team, label, color, out (elimination time, -1 = winner), place,
## members [{def, death, knock}]}, the events and the match end. Deterministic per seed.
func _match(squad: int, n_teams: int, seed_value: int) -> Dictionary:
	var rng: = RandomNumberGenerator.new()
	rng.seed = seed_value
	var chars: Array = DB.characters
	var order: Array = range(n_teams)
	for i in range(n_teams - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: int = order[i]
		order[i] = order[j]
		order[j] = tmp
	var outs: Array = []
	for i in n_teams - 1:
		outs.append(28.0 + 468.0 * pow(rng.randf(), 0.7))
	outs.sort()
	var teams: Array = []
	for t in n_teams:
		var members: Array = []
		for m in squad:
			var hero: int = (t * 7 + 3) % chars.size() if squad == 1 else (t * squad + m) % chars.size()
			members.append({"def": chars[hero], "death": -1.0, "knock": -1.0, "kills": 0, "knocks": 0, "revives": 0, "damage": 0.0})
		teams.append({"team": t, "label": DB.team_name(t, squad), "color": UITheme.team_color(t), "out": -1.0, "place": 1, "members": members})
	for j in n_teams - 1:
		var tm: Dictionary = teams[order[j]]
		tm.out = outs[j]
		tm.place = n_teams - j
		var ms: Array = tm.members
		for m in ms.size():
			var death: float = float(tm.out) if m == ms.size() - 1 else maxf(12.0, float(tm.out) - rng.randf_range(4.0, 46.0))
			ms[m].death = death
			if squad > 1:
				ms[m].knock = maxf(6.0, death - rng.randf_range(3.0, 19.0))
	# The winning squad loses one member mid-game half of the time.
	var win: Dictionary = teams[order[n_teams - 1]]
	if squad > 1 and rng.randf() < 0.6:
		win.members[0].death = rng.randf_range(210.0, 290.0)
		win.members[0].knock = float(win.members[0].death) - 9.0
	var end: float = float(outs[outs.size() - 1]) + 6.0
	var events: Array = []
	for tm2 in teams:
		for m2 in tm2.members:
			if float(m2.knock) >= 0.0:
				events.append({"t": float(m2.knock), "kind": "knock", "team": tm2.team, "color": tm2.color, "text": "%s %s 다운" % [tm2.label, m2.def.name]})
			if float(m2.death) >= 0.0:
				events.append({"t": float(m2.death), "kind": "kill", "team": tm2.team, "color": tm2.color, "text": "%s %s 처치" % [tm2.label, m2.def.name]})
		if float(tm2.out) >= 0.0:
			events.append({"t": float(tm2.out), "kind": "team_out", "team": tm2.team, "color": tm2.color, "text": "%s 탈락 · %d위" % [tm2.label, int(tm2.place)]})
	events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.t) < float(b.t))
	# Credit kills, knocks and damage to members of other teams still in the game at that moment.
	for e in events:
		if str(e.kind) == "team_out":
			continue
		var cands: Array = []
		for tm3 in teams:
			if int(tm3.team) == int(e.team):
				continue
			for m3 in tm3.members:
				if float(m3.death) < 0.0 or float(m3.death) > float(e.t):
					cands.append(m3)
		if not cands.is_empty():
			var killer: Dictionary = cands[rng.randi_range(0, cands.size() - 1)]
			killer[("kills" if str(e.kind) == "kill" else "knocks")] = int(killer[("kills" if str(e.kind) == "kill" else "knocks")]) + 1
			killer.damage = float(killer.damage) + rng.randf_range(300.0, 900.0)
	for tm4 in teams:
		for m4 in tm4.members:
			if squad > 1 and rng.randf() < 0.3:
				m4.revives = rng.randi_range(1, 2)
			m4.damage = float(m4.damage) + rng.randf_range(200.0, 1600.0)
	return {"squad": squad, "teams": teams, "events": events, "end": end, "winner": win}


## Team snapshot at time now in the widget input format (TeamChip / BrStanding).
func _team_view(tm: Dictionary, now: float, rng: RandomNumberGenerator) -> Dictionary:
	var members: Array = []
	var standing: int = 0
	for m0 in tm.members:
		if not (float(m0.knock) >= 0.0 and float(m0.knock) <= now):
			standing += 1
	for m in tm.members:
		var st: String = "alive"
		var left: float = 0.0
		var revive: float = 0.0
		if float(m.death) >= 0.0 and float(m.death) <= now:
			st = "dead"
		elif float(m.knock) >= 0.0 and float(m.knock) <= now:
			st = "downed"
			left = float(m.death) - now
			# A standing teammate is reviving when the bleed-out is still far away.
			revive = 0.4 if standing > 0 and left > 15.0 else 0.0
		members.append({"name": m.def.name, "glyph": m.def.glyph, "color": m.def.accent, "state": st,
			"hp": snappedf(rng.randf_range(0.12, 1.0), 0.01) if st == "alive" else 0.0, "downed_left": left, "downed_total": 30.0,
			"revive": revive, "kills": m.kills, "knocks": m.knocks, "revives": m.revives, "damage": m.damage})
	var out: bool = float(tm.out) >= 0.0 and float(tm.out) <= now
	return {"team": tm.team, "label": tm.label, "color": tm.color, "eliminated": out, "place": int(tm.place) if out else 0,
		"elim_time": float(tm.out) if out else 0.0, "members": members}


func _zone_at(now: float) -> Dictionary:
	for ph in PHASES:
		if now < float(ph[1]):
			var prev: int = int(ph[0]) - 1
			return _zone("loot" if prev == 0 else "wait", prev, float(ph[1]), 0.0 if prev == 0 else float(PHASES[prev - 1][3]), now >= float(ph[1]) - 30.0)
		if now < float(ph[2]):
			return _zone("shrink", int(ph[0]), float(ph[2]), float(ph[3]), true)
	return _zone("final", 6, -1.0, 0.12, true)


# ------------------------------------------------------------------ gallery page

func _caption(text: String) -> Label:
	return UITheme.label(text, "FaintLabel", UITheme.MIN_FS)


func _section(parent: Control, title: String, hint: String = "") -> void:
	parent.add_child(UITheme.section_header(title, hint))


func _page(fmt: String, squad: int, n_teams: int, arena: Arena) -> void:
	var data: Dictionary = _match(squad, n_teams, 20261001 + squad * 97)
	var rng: = RandomNumberGenerator.new()
	rng.seed = 77 + squad
	var views: Array = []
	for tm in data.teams:
		views.append(_team_view(tm, NOW, rng))
	var page: = Control.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(page)
	var outer: = UITheme.vbox(14)
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	outer.offset_left = 16
	outer.offset_top = 10
	outer.offset_right = -16
	outer.offset_bottom = -10
	page.add_child(outer)

	# --- top bar: team chips either side of the clock, survivors and the compact zone pill.
	var bar: = UITheme.panel("GlassPanel")
	var bar_row: = UITheme.hbox(10)
	bar.add_child(bar_row)
	outer.add_child(bar)
	var left_chips: = UITheme.hbox(3 if squad == 1 else 5)
	left_chips.alignment = BoxContainer.ALIGNMENT_END
	left_chips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var right_chips: = UITheme.hbox(3 if squad == 1 else 5)
	right_chips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var chips: Array = []
	var half: int = int(ceil(n_teams / 2.0))
	# The followed team: the first team still in the game from the 3rd chip on.
	var followed: int = -1
	for i in range(2, views.size()):
		if not bool(views[i].eliminated):
			followed = i
			break
	for i in views.size():
		var chip: = TeamChip.new()
		var v: Dictionary = views[i]
		chip.set_data({"label": v.label, "color": v.color, "members": v.members, "eliminated": v.eliminated, "place": v.place, "selected": i == followed})
		(left_chips if i < half else right_chips).add_child(chip)
		chips.append(chip)
	var alive_heroes: int = 0
	var alive_teams: int = 0
	for v2 in views:
		if not bool(v2.eliminated):
			alive_teams += 1
			for m in v2.members:
				if str(m.state) != "dead":
					alive_heroes += 1
	var mid: = UITheme.vbox(4)
	mid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var clock: = UITheme.label("%s · 생존 %d/%d%s" % [UITheme.fmt_time(NOW), alive_heroes, n_teams * squad, (" · %d팀" % alive_teams) if squad > 1 else ""], "BoldLabel", 14)
	clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid.add_child(clock)
	var top_pill: = ZonePill.new(true)
	top_pill.set_view(_zone_at(NOW))
	top_pill.set_time(NOW)
	mid.add_child(top_pill)
	bar_row.add_child(left_chips)
	bar_row.add_child(mid)
	bar_row.add_child(right_chips)

	var body: = UITheme.hbox(20)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(body)
	var left: = UITheme.vbox(12)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(left)
	var right: = UITheme.vbox(10)
	right.custom_minimum_size = Vector2(368, 0)
	body.add_child(right)

	# --- zone pills (all four states, full size) next to the minimap at default and large size.
	var titles: Dictionary = {"solo": "솔로 30명", "duo": "듀오 15팀", "trio": "트리오 10팀"}
	_section(left, "자기장 알약 · 미니맵", "%s · %s 시점 · 알약 480×56 (상단 바 300×30) · 미니맵 240×147" % [titles[fmt], UITheme.fmt_time(NOW)])
	var row_a: = UITheme.hbox(16)
	left.add_child(row_a)
	var pill_col: = UITheme.vbox(8)
	row_a.add_child(pill_col)
	var pills: Array = []
	for z in [[_zone("loot", 0, 75.0, 0.0, false), 10.0], [_zone("wait", 1, 195.0, 0.01, true), 180.0],
			[_zone("shrink", 2, 240.0, 0.02, true), 198.0], [_zone("final", 6, -1.0, 0.12, true), 470.0]]:
		var pill: = ZonePill.new()
		pill.set_view(z[0])
		pill.set_time(z[1])
		pill_col.add_child(pill)
		pills.append(pill)
	var mm: = Minimap.new()
	mm.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row_a.add_child(mm)
	var mm_big: = Minimap.new()
	mm_big.custom_minimum_size = Vector2(404, 248)
	mm_big.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row_a.add_child(mm_big)
	var zone_now: Dictionary = _zone_at(NOW)
	zone_now.center = Vector2(3800.0, 2050.0)
	zone_now.radius = 1150.0
	zone_now.next_center = Vector2(3650.0, 2250.0)
	zone_now.next_radius = 800.0
	var dots: Array = _dots(views, zone_now, rng)
	for m2 in [mm, mm_big]:
		m2.set_arena(arena)
		m2.set_zone(zone_now)
		m2.set_dots(dots)
		m2.set_camera_rect(Rect2(3150.0, 1750.0, 1450.0, 920.0))

	# --- survivor chart over the whole match.
	_section(left, "생존자 그래프", "결과 화면 · 자기장 수축 띠 · 처치 표식")
	var chart: = SurvivorChart.new()
	chart.custom_minimum_size = Vector2(0, 220)
	chart.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var phase_list: Array = []
	for ph in PHASES:
		if float(ph[1]) < float(data.end):
			phase_list.append({"phase": ph[0], "start": ph[1], "end": minf(float(ph[2]), float(data.end))})
	var win: Dictionary = data.winner
	var win_text: String = str(win.label) if squad > 1 else "%s %s" % [win.label, win.members[0].def.name]
	chart.set_data({"total": n_teams * squad, "teams_total": n_teams if squad > 1 else 0, "max_time": data.end,
		"phases": phase_list, "events": data.events, "winner": "%s 우승" % win_text})
	left.add_child(chart)

	# --- team chip states, the 30 team colours and a roster card with a count badge.
	_section(left, "팀칩 상태 · 팀 색 30 · 로스터 ×2", "솔로 36 · 듀오 56 · 트리오 86 (높이 58) · 16번째부터 밝은 변형 + 번호")
	var states_row: = UITheme.hbox(10)
	left.add_child(states_row)
	for s in _chip_samples():
		var col: = UITheme.vbox(3)
		var chip2: = TeamChip.new()
		chip2.set_data(s[1])
		chip2.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(chip2)
		var cap: = _caption(str(s[0]))
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(cap)
		states_row.add_child(col)
	states_row.add_child(UITheme.spacer(6, 0))
	var swatches: = GridContainer.new()
	swatches.columns = 15
	swatches.add_theme_constant_override("h_separation", 3)
	swatches.add_theme_constant_override("v_separation", 3)
	swatches.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for t in 30:
		swatches.add_child(_swatch(t))
	states_row.add_child(swatches)
	states_row.add_child(UITheme.spacer(6, 0))
	var rc1: = RosterCard.new(DB.characters[5])
	rc1.set_count(2)
	rc1.set_picked(4, "P5")
	rc1.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	states_row.add_child(rc1)

	# --- right: the standing at side-panel width.
	_section(right, "순위", "팀별 묶음 · 탈락 팀은 한 줄")
	var standing: = BrStanding.new()
	standing.set_teams(views)
	var sc: = UITheme.scroll(standing)
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(sc)
	await _frames(4)


	# --- checks for this format.
	var tag: String = fmt
	var want_w: float = [36.0, 56.0, 86.0][squad - 1]
	var sizes_ok: bool = true
	for c in chips:
		var ch: TeamChip = c
		if not is_equal_approx(ch.size.x, want_w) or not is_equal_approx(ch.size.y, TeamChip.H):
			sizes_ok = false
	_check(sizes_ok and chips.size() == n_teams, "%s: %d team chips at %dx58" % [tag, n_teams, int(want_w)])
	var bar_fits: bool = bar.get_combined_minimum_size().x <= 1568.0
	_check(bar_fits, "%s: top bar fits 1600 px (min %d)" % [tag, int(bar.get_combined_minimum_size().x)])
	measurements["%s_topbar_min_w" % tag] = int(bar.get_combined_minimum_size().x)
	_check(top_pill.size.y >= ZonePill.COMPACT_SIZE.y and top_pill.size.x >= ZonePill.COMPACT_SIZE.x, "%s: compact zone pill at least 300x30" % tag)
	var pills_ok: bool = true
	for p in pills:
		if not ((p as ZonePill).size == ZonePill.FULL_SIZE):
			pills_ok = false
	_check(pills_ok, "%s: full zone pills are 480x56" % tag)
	_check(mm.size == Minimap.DEFAULT_SIZE, "%s: minimap default size 240x147 (%s)" % [tag, str(mm.size)])
	var tex: Texture2D = mm.texture
	var want_tex: = Vector2(arena.width, arena.height) / 24.0
	var tex_size: Vector2 = tex.get_size() if tex else Vector2.ZERO
	measurements["minimap_texture"] = [int(tex_size.x), int(tex_size.y)]
	_check(absf(tex_size.x - want_tex.x) <= 1.0 and absf(tex_size.y - want_tex.y) <= 1.0 and tex.get_image().has_mipmaps(), "%s: minimap texture is arena/24 with mipmaps (%s)" % [tag, str(tex_size)])
	var aspect_ok: bool = absf(mm.map_rect.size.x / mm.map_rect.size.y - arena.width / arena.height) < 0.02
	var inside: bool = Rect2(Vector2.ZERO, mm.size).grow(0.5).encloses(mm.map_rect)
	_check(aspect_ok and inside, "%s: minimap keeps the map aspect inside its frame" % tag)
	var target: = Vector2(1234.0, 3456.0)
	var round_trip: Vector2 = mm.map_to_world(mm.world_to_map(target))
	_check(round_trip.distance_to(target) < 0.5, "%s: minimap world <-> map round trip" % tag)
	var got: Array = []
	var cb: = func(p: Vector2) -> void: got.append(p)
	mm.world_clicked.connect(cb)
	var ev: = InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = mm.world_to_map(Vector2(4000.0, 1000.0))
	mm._gui_input(ev)
	var up: = InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = ev.position
	mm._gui_input(up)
	_check(got.size() == 1 and (got[0] as Vector2).distance_to(Vector2(4000.0, 1000.0)) < 1.0, "%s: minimap click emits world_clicked at the world point" % tag)
	# The same spot again, then a drag to another spot; motion after release emits nothing.
	mm._gui_input(ev)
	var drag: = InputEventMouseMotion.new()
	drag.position = mm.world_to_map(Vector2(2000.0, 3000.0))
	drag.button_mask = MOUSE_BUTTON_MASK_LEFT
	mm._gui_input(drag)
	mm._gui_input(up)
	mm._gui_input(drag)
	mm.world_clicked.disconnect(cb)
	_check(got.size() == 3 and (got[2] as Vector2).distance_to(Vector2(2000.0, 3000.0)) < 1.0, "%s: minimap repeat click and drag pan the camera" % tag)
	measurements["%s_minimap_build_ms" % tag] = snappedf(mm.build_ms, 0.01)
	_check(mm.build_ms < 250.0, "%s: minimap static raster %.1f ms (< 250)" % [tag, mm.build_ms])
	# Standing order and rows.
	var seen_out: bool = false
	var order_ok: bool = true
	var last_place: int = 0
	for ti in standing.order:
		var tv: Dictionary = views[ti]
		if bool(tv.eliminated):
			seen_out = true
			if int(tv.place) < last_place:
				order_ok = false
			last_place = int(tv.place)
		elif seen_out:
			order_ok = false
	_check(order_ok and standing.order.size() == n_teams, "%s: standing lists live teams first, eliminated by place" % tag)
	var row_ok: bool = true
	var outs_ok: bool = true
	for r in standing.rows:
		if str(r.kind) == "member" and not is_equal_approx(float(r.h), BrStanding.ROW_H):
			row_ok = false
		if str(r.kind) == "out":
			var tv2: Dictionary = views[int(r.team)]
			if str(r.text) != "%d위 · %s 탈락" % [int(tv2.place), UITheme.fmt_time(float(tv2.elim_time))]:
				outs_ok = false
	_check(row_ok and is_equal_approx(BrStanding.ROW_H, 36.0), "%s: standing hero rows are 36 px" % tag)
	_check(outs_ok, "%s: eliminated teams collapse to one line" % tag)
	_check(standing.size.y >= standing.get_combined_minimum_size().y - 0.5 and standing.get_combined_minimum_size().y > 0.0, "%s: standing height follows its rows" % tag)
	# Survivor series.
	var mono: bool = true
	var prev: int = 9999
	for s2 in chart.samples:
		if int(s2[1]) > prev:
			mono = false
		prev = int(s2[1])
	var win_alive: int = 0
	for m5 in win.members:
		if float(m5.death) < 0.0:
			win_alive += 1
	_check(mono and chart.count_at(0.0) == n_teams * squad and chart.count_at(float(data.end)) == win_alive, "%s: survivor line runs %d -> %d" % [tag, n_teams * squad, win_alive])
	if squad > 1:
		_check(chart.count_at(float(data.end), 2) == 1 and chart.show_teams(), "%s: team line ends at 1 team" % tag)
	await _shot("br_widgets_%s" % tag)
	page.queue_free()
	await _frames(2)


func _swatch(t: int) -> Control:
	var c: = Control.new()
	c.custom_minimum_size = Vector2(26, 18)
	c.tooltip_text = "P%d" % (t + 1)
	c.draw.connect(func() -> void:
		var col: Color = UITheme.team_color(t)
		c.draw_style_box(UITheme.sbc(col, UITheme.CLEAR, UITheme.R_XS, 0, 0), Rect2(Vector2.ZERO, c.size))
		var ink: Color = UITheme.BG if col.get_luminance() > 0.5 else Color.WHITE
		c.draw_string(DB.font_bold, Vector2(0, 13.5), str(t + 1), HORIZONTAL_ALIGNMENT_CENTER, c.size.x, UITheme.MIN_FS, ink))
	return c


func _member(i: int, state: String, hp: float = 0.8, left: float = 0.0, revive: float = 0.0) -> Dictionary:
	var d: Defs.CharDef = DB.characters[i % DB.characters.size()]
	return {"name": d.name, "glyph": d.glyph, "color": d.accent, "state": state, "hp": hp, "downed_left": left, "downed_total": 30.0, "revive": revive}


func _chip_samples() -> Array:
	return [
		["솔로", {"label": "P7", "color": UITheme.team_color(6), "members": [_member(4, "alive", 0.62)]}],
		["솔로 17+", {"label": "P18", "color": UITheme.team_color(17), "members": [_member(9, "alive", 0.2)]}],
		["솔로 탈락", {"label": "P3", "color": UITheme.team_color(2), "members": [_member(1, "dead")], "eliminated": true, "place": 23}],
		["듀오 다운", {"label": "4팀", "color": UITheme.team_color(3), "members": [_member(2, "alive", 0.9), _member(8, "downed", 0.0, 8.0)]}],
		["듀오 탈락", {"label": "9팀", "color": UITheme.team_color(8), "members": [_member(5, "dead"), _member(6, "dead")], "eliminated": true, "place": 11}],
		["트리오 소생", {"label": "2팀", "color": UITheme.team_color(1), "members": [_member(10, "alive", 1.0), _member(11, "downed", 0.0, 22.0, 0.45), _member(12, "dead")]}],
		["트리오 탈락", {"label": "13팀", "color": UITheme.team_color(12), "members": [_member(13, "dead"), _member(14, "dead"), _member(15, "dead")], "eliminated": true, "place": 7}],
	]


func _dots(views: Array, zone_now: Dictionary, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var c: Vector2 = zone_now.center
	for v in views:
		var anchor: Vector2 = c + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(80.0, float(zone_now.radius) * 1.15)
		for m in v.members:
			var p: Vector2 = anchor + Vector2(rng.randf_range(-120.0, 120.0), rng.randf_range(-120.0, 120.0))
			match str(m.state):
				"alive":
					if not bool(v.eliminated):
						out.append({"pos": p, "color": v.color, "kind": "hero"})
				"downed":
					out.append({"pos": p, "color": v.color, "kind": "downed"})
				_:
					out.append({"pos": Vector2(rng.randf_range(300.0, 6900.0), rng.randf_range(300.0, 4100.0)), "color": UITheme.TEXT_DIM, "kind": "death"})
	for i in 18:
		var r: int = [4, 4, 3, 3, 2, 2, 1][i % 7]
		out.append({"pos": Vector2(rng.randf_range(200.0, 7000.0), rng.randf_range(200.0, 4200.0)), "color": ItemDefs.rarity_color(r), "kind": "item"})
	return out
