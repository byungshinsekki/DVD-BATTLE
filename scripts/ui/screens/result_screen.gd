class_name ResultScreen
extends Control
## Battle report shown after every match: elimination / control / draft (_build), deathmatch
## (_build_deathmatch) and the V2 battleground (_build_battleground: podium of the top 3 teams,
## SurvivorChart with zone bands, ranking table grouped by team). on_show({"result", "config"})
## rebuilds the page once; nothing here runs per frame (the charts only redraw when resized).
## Shared parts: _report_head() (page header + fact badges + actions) and _stat_table() (caption
## header, zebra rows, right-aligned numeric columns with shared widths, gold column bests).

const MAX_W: = 1760.0
const COL_GAP: = 8
const ROW_PAD: = 10
const MEDALS: = [Color("#f4c96b"), Color("#d6dde8"), Color("#d09a62")]
const BEST_CAPTION: = "금색 = 항목 최고"

# Row styles are shared between rebuilds (never mutated after creation).
static var _styles: Dictionary = {}

var app: App
var body: VBoxContainer
var scroll_box: ScrollContainer
var result: Dictionary = {}
var config: Dictionary = {}


func bind(a: App) -> void :
	app = a


func _ready() -> void :
	scroll_box = ScrollContainer.new()
	scroll_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll_box.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll_box)
	body = UITheme.vbox(UITheme.SP4)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var m: = UITheme.page_margin(UITheme.max_width(body, MAX_W))
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_box.add_child(m)


func on_show(args: Dictionary) -> void :
	result = args.get("result", {})
	config = args.get("config", {})
	_build()
	scroll_box.scroll_vertical = 0


## MVP weight (unchanged since V1.3); the winning team gets x1.15 in _build().
func _score(r: Dictionary) -> float:
	return float(r.damage) + float(r.healing) * 0.8 + float(r.shielding) * 0.6 + float(r.cc) * 60.0 + float(r.kills) * 150.0 + float(r.get("capture_time", 0.0)) * 25.0 + float(r.get("captures", 0)) * 180.0


func _clear() -> void :
	for c in body.get_children():
		body.remove_child(c)
		c.queue_free()


# ================================================================== elimination / control / draft

func _build() -> void :
	_clear()
	if result.is_empty():
		return
	if str(result.get("ruleset", "")) == "battleground":
		_build_battleground()
		return
	if str(result.get("ruleset", "")) == "deathmatch":
		_build_deathmatch()
		return
	var units: Array = result.get("units", [])
	var w: int = int(result.get("winner", -1))
	var mode: String = str(config.get("mode", "composition"))
	var arena: Arena = DB.arena(str(result.get("arena", "classic")))
	var ruleset: String = str(result.get("ruleset", config.get("ruleset", "elimination")))
	var control: bool = ruleset == "control"
	var big: bool = units.size() > 6

	# ---- head
	var title: String = "무승부"
	var col: Color = UITheme.GOLD
	if w == 0 or w == 1:
		title = "청 팀 승리" if w == 0 else "홍 팀 승리"
		col = UITheme.team_color(w)
		if mode == "draft":
			title = "승리! AI의 카운터를 꺾었다" if w == 0 else "패배 — AI의 카운터 조합"
	var facts: Array = []
	var reason: String = str(result.get("reason", ""))
	var target_score: int = int(result.get("target_score", 300))
	if control:
		var scores: Array = result.get("scores", [0, 0])
		var reached: bool = maxf(float(scores[0]), float(scores[1])) >= float(target_score)
		facts.append(["목표 점수 달성" if reached else "시간 종료 · 점수 판정", col, "strong",
			"먼저 %d점을 모은 팀이 승리했습니다." % target_score if reached else "제한 시간이 끝나 점수가 높은 팀이 승리했습니다."])
		facts.append(["청 %d : %d 홍" % [int(scores[0]), int(scores[1])], UITheme.TEXT, "soft", "최종 점수입니다 (목표 %d점)." % target_score])
	else:
		var reason_text: String = reason
		var reason_tip: String = ""
		if reason == "elimination":
			reason_text = "전멸"
			reason_tip = "상대 팀을 모두 처치해 승부가 났습니다."
		elif reason == "time_limit":
			reason_text = "시간 종료 · 남은 체력 합 판정"
			reason_tip = "제한 시간이 끝나 살아 있는 영웅의 체력 합이 많은 팀이 승리했습니다."
		facts.append([reason_text, col, "strong", reason_tip])
	facts.append([("AI 대전 · " if mode == "draft" else "") + CodexData.arena_kind_label(ruleset), UITheme.ACCENT, "soft", ""])
	facts.append([arena.name, UITheme.TEXT_DIM, "soft", ""])
	facts.append(["경기 시간 " + UITheme.fmt_time(float(result.get("duration", 0.0))), UITheme.TEXT_DIM, "soft", ""])
	facts.append(["시드 %d" % int(result.get("seed", 0)), UITheme.TEXT_DIM, "outline", "같은 시드로 다시 하면 똑같은 전투가 재생됩니다."])
	var new_cb: Callable = func() -> void:
		app.goto("draft" if mode == "draft" else "setup", {"ruleset": "control" if control else "elimination"})
	body.add_child(_report_head("BATTLE REPORT", title, col, facts, "새 전투 편성", new_cb,
		"결정론적 시뮬레이션이라 같은 설정이면 똑같은 전투가 다시 재생됩니다."))

	# ---- MVP + flow chart
	var row: = UITheme.hbox(UITheme.SP4)
	var mvp: Dictionary = {}
	var best_score: = -1.0
	for r in units:
		var s: float = _score(r) * (1.15 if int(r.team) == w else 1.0)
		if s > best_score:
			best_score = s
			mvp = r
	if not mvp.is_empty():
		row.add_child(_mvp_card(mvp, best_score, control, big))
	var chart: = HpChart.new()
	chart.history = result.get("control_history", []) if control else result.get("history", [])
	chart.max_time = float(result.get("duration", 0.0))
	chart.target = float(target_score) if control else -1.0
	chart.custom_minimum_size = Vector2(0, 140 if big else 150)
	chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chart.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var legend: Array = [["청 팀", UITheme.team_color(0), false], ["홍 팀", UITheme.team_color(1), false]]
	if control:
		legend.append(["목표 %d점" % target_score, UITheme.GOLD, true])
	var gv: = UITheme.vbox(UITheme.SP3)
	gv.add_child(UITheme.section_header("거점 점수 흐름" if control else "팀 체력 흐름",
		"팀 점수 추이" if control else "살아 있는 영웅 체력 합", _legend(legend)))
	gv.add_child(chart)
	var gp: = _card(gv)
	gp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(gp)
	body.add_child(row)

	# ---- per-team tables
	var cols: Array = [_col("영웅", 230, "l", false, 150.0), _col("피해", 90, "r", true), _col("받은 피해", 90), _col("회복", 80),
		_col("보호막", 80), _col("제어(초)", 80), _col("처치", 64, "r", true), _col("사망", 64), _col("시전", 64)]
	var best: Dictionary = {}
	for r0 in units:
		var vals0: Array = _elim_values(r0)
		for i in vals0.size():
			if i == 6:
				continue
			best[i + 1] = maxf(float(best.get(i + 1, 0.0)), float(vals0[i][1]))
	body.add_child(UITheme.section_header("영웅별 기록", "", _best_legend("양 팀 영웅 전체에서 항목마다 가장 높은 기록입니다 (사망 제외).")))
	for t in 2:
		var rows: Array = []
		var tk: = 0
		var td: = 0.0
		var th_heal: = 0.0
		var ri: = 0
		for r in units:
			if int(r.team) != t:
				continue
			var cells: Array = [_hero_cell(r, t, big, control, r == mvp)]
			cells.append_array(_elim_values(r))
			var entry: Dictionary = {"cells": cells, "style": _zebra(ri, big)}
			if control:
				var sub: Control = _capture_badges(r, 42 if not big else 38)
				if sub:
					entry["sub"] = sub
			rows.append(entry)
			tk += int(r.kills)
			td += float(r.damage)
			th_heal += float(r.healing)
			ri += 1
		var tv: = UITheme.vbox(UITheme.SP2)
		var th: = UITheme.hbox(UITheme.SP2)
		th.add_child(_bar(UITheme.team_color(t), 18))
		th.add_child(UITheme.label("청 팀" if t == 0 else "홍 팀", "BlackLabel", 18, UITheme.team_color(t)))
		var who: String = AIFactory.label(str(config.get("blue_ai" if t == 0 else "red_ai", "tactician")))
		if mode == "draft":
			who = "사용자 편성" if t == 0 else "AI 드래프트"
		th.add_child(_center(UITheme.badge(who, UITheme.TEXT_DIM, "outline")))
		if t == w:
			th.add_child(_center(UITheme.badge("승리", UITheme.GOLD, "solid")))
		th.add_child(UITheme.spacer())
		var totals: = "처치 %d · 피해 %s" % [tk, _fmt_int(int(td))]
		if th_heal > 0.0:
			totals += " · 회복 %s" % _fmt_int(int(th_heal))
		th.add_child(_center(UITheme.label(totals, "CaptionLabel")))
		tv.add_child(th)
		tv.add_child(_stat_table(cols, rows, best))
		body.add_child(_card(tv))

	# ---- draft record
	if mode == "draft":
		var rec: Dictionary = Settings.records
		var rh: = UITheme.hbox(UITheme.SP4)
		var rl: = UITheme.section_header("AI 대전 전적", "이번 전투까지 반영된 기록입니다")
		rl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rh.add_child(rl)
		for spec in [["승리", "%d승" % int(rec.get("draft_wins", 0)), UITheme.GOOD], ["패배", "%d패" % int(rec.get("draft_losses", 0)), UITheme.BAD],
				["현재 연승", str(int(rec.get("streak", 0))), UITheme.ACCENT], ["최고 연승", str(int(rec.get("best_streak", 0))), UITheme.GOLD]]:
			var tile: = UITheme.stat_tile(spec[0], spec[1], spec[2])
			tile.custom_minimum_size.x = 112
			rh.add_child(tile)
		body.add_child(_card(rh))


## [text, raw] cells in column order: 피해, 받은 피해, 회복, 보호막, 제어(초), 처치, 사망, 시전.
func _elim_values(r: Dictionary) -> Array:
	return [[_fmt_int(int(r.damage)), float(r.damage)], [_fmt_int(int(r.taken)), float(r.taken)],
		[_fmt_int(int(r.healing)), float(r.healing)], [_fmt_int(int(r.shielding)), float(r.shielding)],
		["%.1f" % float(r.cc), float(r.cc)], [str(int(r.kills)), float(r.kills)],
		[str(int(r.deaths)), float(r.deaths)], [str(int(r.casts)), float(r.casts)]]


func _mvp_card(mvp: Dictionary, score: float, control: bool, big: bool) -> Control:
	var formula: = "MVP 점수는 피해 + 회복×0.8 + 보호막×0.6 + 제어 1초당 60 + 처치당 150으로 계산합니다."
	if control:
		formula += " 거점 장악에서는 점령 기여 1초당 25점과 점령 완료당 180점을 더합니다."
	formula += "\n승리 팀 영웅은 점수가 1.15배가 됩니다."
	var v: = UITheme.vbox(UITheme.SP3)
	var score_b: = UITheme.badge("점수 %s" % _fmt_int(roundi(score)), UITheme.GOLD, "outline", formula)
	v.add_child(UITheme.section_header("MVP", "전투 + 점령 기여" if control else "가장 큰 활약", score_b))
	var d: Defs.CharDef = DB.char_def(str(mvp.id))
	var team: int = int(mvp.team)
	var mh: = UITheme.hbox(UITheme.SP3)
	mh.add_child(GlyphDisc.new(d, 56 if big else 64, team))
	var mv: = UITheme.vbox(4)
	mv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mv.add_child(UITheme.ellipsize(UITheme.label(d.name, "TitleLabel", 26)))
	var tags: = UITheme.hbox(6)
	tags.add_child(UITheme.badge("청 팀" if team == 0 else "홍 팀", UITheme.team_color(team), "strong"))
	tags.add_child(UITheme.badge(DB.role_label(d.role), UITheme.role_color(d.role), "soft"))
	mv.add_child(tags)
	mh.add_child(mv)
	v.add_child(mh)
	var tiles: Array = [["피해", _fmt_int(int(mvp.damage)), UITheme.TEXT, "적에게 준 피해 합계입니다."],
		["처치", str(int(mvp.kills)), UITheme.TEXT, ""],
		["제어", "%.1f초" % float(mvp.cc), UITheme.TEXT, "적에게 건 군중 제어 시간의 합계입니다."]]
	if float(mvp.healing) > 0.0:
		tiles.append(["회복", _fmt_int(int(mvp.healing)), UITheme.GOOD, "아군과 자신에게 준 회복량입니다."])
	if float(mvp.shielding) > 0.0:
		tiles.append(["보호막", _fmt_int(int(mvp.shielding)), UITheme.ACCENT, "아군과 자신에게 씌운 보호막 양입니다."])
	if control:
		tiles.append(["점령 기여", "%.1f초" % float(mvp.get("capture_time", 0.0)), UITheme.GOLD, "거점을 중립화·점령하는 데 기여한 시간입니다."])
		tiles.append(["점령 완료", "%d회" % int(mvp.get("captures", 0)), UITheme.GOLD, ""])
	var grid: = GridContainer.new()
	grid.columns = tiles.size() if tiles.size() <= 5 else 4
	grid.add_theme_constant_override("h_separation", UITheme.SP2)
	grid.add_theme_constant_override("v_separation", UITheme.SP2)
	for t in tiles:
		var st: = UITheme.stat_tile(str(t[0]), str(t[1]), t[2], str(t[3]))
		st.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(st)
	v.add_child(grid)
	var p: = _card(v)
	p.custom_minimum_size.x = 360 if grid.columns <= 3 else 430
	p.tooltip_text = UITheme.tip(formula)
	return p


## Name cell: HP-ring disc, name (+ MVP badge) and a survival line.
func _hero_cell(r: Dictionary, team: int, big: bool, control: bool, is_mvp: bool) -> Control:
	var h: = UITheme.hbox(10)
	var d: Defs.CharDef = DB.char_def(str(r.id))
	var alive: bool = bool(r.get("alive", true))
	var hp_ratio: float = clampf(float(r.get("hp", 0.0)) / maxf(1.0, float(r.get("max_hp", 1.0))), 0.0, 1.0)
	var disc: = GlyphDisc.new(d, 28 if big else 32, team)
	disc.set_state(hp_ratio, 0.0, not alive)
	disc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(disc)
	h.add_child(_center(UITheme.label(d.name, "BoldLabel", 14 if big else 15)))
	var st: Label
	if alive:
		st = UITheme.label("체력 %d%%" % roundi(hp_ratio * 100.0), "", 12, _hp_color(hp_ratio))
		st.tooltip_text = "전투가 끝났을 때 남은 체력입니다."
	else:
		st = UITheme.label("부활 대기" if control else "사망", "", 12, UITheme.TEXT_FAINT)
		st.tooltip_text = "전투가 끝났을 때 부활을 기다리는 중이었습니다." if control else "전투 중 쓰러졌습니다."
	st.mouse_filter = Control.MOUSE_FILTER_PASS
	h.add_child(_center(st))
	if is_mvp:
		h.add_child(_center(UITheme.badge("MVP", UITheme.GOLD, "soft")))
	return h


## Control mode: capture contribution badges under a hero row, or null when every value is 0.
func _capture_badges(r: Dictionary, indent: int) -> Control:
	var ct: float = float(r.get("capture_time", 0.0))
	var cn: int = int(r.get("captures", 0))
	var zh: int = int(r.get("zone_healing", 0))
	if ct <= 0.0 and cn <= 0 and zh <= 0:
		return null
	var h: = UITheme.hbox(6)
	if ct > 0.0:
		h.add_child(UITheme.badge("점령 기여 %.1f초" % ct, UITheme.GOLD, "soft", "거점을 중립화·점령하는 데 기여한 시간입니다."))
	if cn > 0:
		h.add_child(UITheme.badge("점령 완료 %d회" % cn, UITheme.GOLD, "soft", "이 영웅이 참여해 점령을 끝낸 횟수입니다."))
	if zh > 0:
		h.add_child(UITheme.badge("회복 구역 %s" % _fmt_int(zh), UITheme.GOOD, "soft", "회복 구역에서 받은 회복량입니다."))
	return UITheme.margin(h, indent, 0, 0, 2)


# ================================================================== deathmatch

func _build_deathmatch() -> void:
	var dmr: Dictionary = result.get("deathmatch", {})
	var ranking: Array = dmr.get("ranking", [])
	var by_idx: Dictionary = {}
	for r in result.get("units", []):
		by_idx[int(r.idx)] = r
	var top: Dictionary = ranking[0] if not ranking.is_empty() else {}
	var preset: Dictionary = DeathmatchMapData.PRESETS.get(str(dmr.get("preset", config.get("arena_id", ""))), {})
	var kill_target: int = int(dmr.get("kill_target", 0))

	# ---- head
	var title: String = "무승부"
	var col: Color = UITheme.GOLD
	if not top.is_empty():
		title = "%s 우승" % DB.char_def(str(top.id)).name
		col = UITheme.team_color(int(top.team))
	var by_kills: bool = str(result.get("reason", "")) == "deathmatch_kills"
	var facts: Array = [
		["목표 %d킬 달성" % kill_target if by_kills else "시간 종료 · 처치 순위", col, "strong",
			"가장 먼저 목표 처치 수에 도달했습니다." if by_kills else "제한 시간이 끝나 처치 순위로 우승자를 정했습니다."],
		["%d명 개인전" % ranking.size(), UITheme.ACCENT, "soft", ""],
		[str(preset.get("name", "개인전 전장")), UITheme.TEXT_DIM, "soft", ""],
		["경기 시간 " + UITheme.fmt_time(float(result.get("duration", 0.0))), UITheme.TEXT_DIM, "soft", ""],
		["시드 %d" % int(result.get("seed", 0)), UITheme.TEXT_DIM, "outline", "같은 시드로 다시 하면 지형·아이템·전투가 똑같이 재생됩니다."]]
	var new_cb: Callable = func() -> void:
		app.goto("deathmatch")
	body.add_child(_report_head("DEATHMATCH REPORT", title, col, facts, "새 데스매치 편성", new_cb,
		"결정론적 시뮬레이션이라 같은 설정이면 지형·아이템·전투가 똑같이 다시 재생됩니다."))

	# ---- podium + kill race
	var row: HBoxContainer = UITheme.hbox(UITheme.SP4)
	row.add_child(_podium_card(ranking))
	var chart: KillRace = KillRace.new()
	chart.kill_log = dmr.get("kill_log", [])
	chart.ranking = ranking
	chart.max_time = float(result.get("duration", 0.0))
	chart.target = int(dmr.get("kill_target", 10))
	chart.custom_minimum_size = Vector2(0, 160)
	chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chart.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var legend: Array = []
	for i in mini(3, ranking.size()):
		var lr: Dictionary = ranking[i]
		legend.append(["P%d %s" % [int(lr.team) + 1, DB.char_def(str(lr.id)).name], UITheme.team_color(int(lr.team)), false])
	if ranking.size() > 3:
		legend.append(["그 외 %d명" % (ranking.size() - 3), Color(UITheme.TEXT_FAINT, 0.7), false])
	legend.append(["목표 %d킬" % chart.target, UITheme.GOLD, true])
	var gv: VBoxContainer = UITheme.vbox(UITheme.SP3)
	gv.add_child(UITheme.section_header("처치 경쟁", "누적 처치", _legend(legend)))
	gv.add_child(chart)
	var gp: PanelContainer = _card(gv)
	gp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(gp)
	body.add_child(row)

	# ---- ranking table
	var cols: Array = [_col("순위", 44, "c"), _col("참가자", 220, "l", false, 150.0), _col("처치", 60, "r", true), _col("사망", 60), _col("도움", 60),
		_col("최고 연속", 72), _col("피해", 84, "r", true), _col("받은 피해", 84), _col("회복", 72), _col("주운 아이템", 84), _col("최종 보유", 110, "l", false, -1.0, 18)]
	var rows: Array = []
	var best: Dictionary = {}
	for r in ranking:
		var u: Dictionary = by_idx.get(int(r.idx), {})
		var cells: Array = [_rank_cell(int(r.rank)), _player_cell(r),
			[str(int(r.kills)), float(r.kills)], [str(int(r.deaths)), float(r.deaths)], [str(int(r.assists)), float(r.assists)],
			[str(int(r.best_streak)), float(r.best_streak)], [_fmt_int(int(r.damage)), float(int(r.damage))],
			[_fmt_int(int(u.get("taken", 0.0))), float(int(u.get("taken", 0.0)))], [_fmt_int(int(u.get("healing", 0.0))), float(int(u.get("healing", 0.0)))],
			[str(int(r.items)), float(r.items)], _held_cell(r)]
		for ci in [2, 4, 5, 6, 8, 9]:
			best[ci] = maxf(float(best.get(ci, 0.0)), float(cells[ci][1]))
		var ri: int = rows.size()
		var style: StyleBox = _medal_style(ri) if ri < 3 else _zebra(ri, true)
		rows.append({"cells": cells, "style": style})
	var tv: VBoxContainer = UITheme.vbox(UITheme.SP2)
	tv.add_child(UITheme.section_header("최종 순위", "처치 수 → 적은 사망 → 많은 피해 순",
		_best_legend("처치·도움·최고 연속·피해·회복·주운 아이템에서 가장 높은 기록입니다.")))
	tv.add_child(_stat_table(cols, rows, best))
	body.add_child(_card(tv))
	body.add_child(UITheme.hint_label("도움은 처치 전 %s초 안에 피해를 준 경우입니다. 소환물·설치물이 올린 처치는 주인에게 돌아갑니다." % CodexData.num(DeathmatchMode.ASSIST_WINDOW)))


func _podium_card(ranking: Array) -> Control:
	var v: = UITheme.vbox(UITheme.SP2)
	v.add_child(UITheme.section_header("시상대", "상위 3명"))
	for i in mini(3, ranking.size()):
		var r: Dictionary = ranking[i]
		var d: Defs.CharDef = DB.char_def(str(r.id))
		var team: int = int(r.team)
		var ph: = UITheme.hbox(UITheme.SP3)
		var medal: = UITheme.label(str(i + 1), "BlackLabel", 22 if i == 0 else 18, MEDALS[i])
		medal.custom_minimum_size = Vector2(22, 0)
		medal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		medal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ph.add_child(medal)
		var disc: = GlyphDisc.new(d, 44 if i == 0 else 36, team)
		disc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ph.add_child(disc)
		var pv: = UITheme.vbox(3)
		pv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var nh: = UITheme.hbox(6)
		nh.add_child(UITheme.label(d.name, "BlackLabel", 20 if i == 0 else 16))
		nh.add_child(_center(UITheme.badge("P%d" % (team + 1), UITheme.team_color(team), "strong")))
		pv.add_child(nh)
		var sh: = UITheme.hbox(6)
		sh.add_child(_center(UITheme.badge("%d킬" % int(r.kills), MEDALS[i] if i == 0 else UITheme.TEXT_DIM, "strong" if i == 0 else "soft")))
		sh.add_child(_center(UITheme.label("%d사망 · %d도움 · 최고 %d연속" % [int(r.deaths), int(r.assists), int(r.best_streak)], "CaptionLabel")))
		pv.add_child(sh)
		ph.add_child(pv)
		var tint: StyleBoxFlat = UITheme.sbc(Color(1, 1, 1, 0.025), UITheme.CLEAR, UITheme.R_M, 1, 10, 6)
		if i == 0:
			tint = UITheme.sbc(Color(UITheme.GOLD, 0.07), Color(UITheme.GOLD, 0.3), UITheme.R_M, 1, 10, 8)
		var pp: = UITheme.styled_panel(tint, ph)
		pp.mouse_filter = Control.MOUSE_FILTER_PASS
		v.add_child(pp)
	if ranking.is_empty():
		v.add_child(UITheme.empty_state("●", "기록이 없습니다"))
	var p: = _card(v)
	p.custom_minimum_size.x = 350
	return p


func _rank_cell(rank: int) -> Label:
	var l: = UITheme.label(str(rank), "BlackLabel", 15, MEDALS[rank - 1] if rank >= 1 and rank <= 3 else UITheme.TEXT_FAINT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


func _player_cell(r: Dictionary) -> Control:
	var h: = UITheme.hbox(UITheme.SP2)
	var team: int = int(r.team)
	var d: Defs.CharDef = DB.char_def(str(r.id))
	var disc: = GlyphDisc.new(d, 24, team)
	disc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(disc)
	var tag: = UITheme.badge("P%d" % (team + 1), UITheme.team_color(team), "strong")
	tag.custom_minimum_size.x = 34
	h.add_child(_center(tag))
	var nl: = UITheme.ellipsize(UITheme.label(d.name, "BoldLabel", 14))
	nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(nl)
	return h


## Held items as rarity tiles (tooltips); "—" with an explanation when nothing is held.
func _held_cell(r: Dictionary) -> Control:
	var held: Array = r.get("held", [])
	if held.is_empty():
		var l: = UITheme.label("—", "", 14, UITheme.TEXT_FAINT)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		if int(r.get("items", 0)) > 0 and int(r.get("deaths", 0)) > 0:
			l.tooltip_text = UITheme.tip("사망 시 소실\n죽으면 가장 높은 등급 아이템 1개만 그 자리에 떨어지고 나머지는 사라집니다.")
		elif int(r.get("items", 0)) > 0:
			l.tooltip_text = "보유한 아이템이 없습니다."
		else:
			l.tooltip_text = "주운 아이템이 없습니다."
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		return l
	var h: = UITheme.hbox(4)
	for held_id in held:
		h.add_child(UITheme.item_tile(str(held_id), 24))
	return h


# ================================================================== battleground (V2)

const BR_SQUAD_NAMES: = {1: "솔로", 2: "듀오", 3: "트리오"}


## Team label as the battle showed it: "P7" (solo) / "3팀".
func _br_label(team: int, squad: int) -> String:
	return DB.team_name(team, squad)


func _build_battleground() -> void:
	var brr: Dictionary = result.get("battleground", {})
	var dmr: Dictionary = result.get("deathmatch", {})
	var ranking: Array = dmr.get("ranking", [])
	var squad: int = int(brr.get("squad", 1))
	var team_rows: Array = (brr.get("teams", []) as Array).duplicate()
	var by_idx: Dictionary = {}
	for r in ranking:
		by_idx[int(r.idx)] = r
	var units: Dictionary = {}
	for u in result.get("units", []):
		units[int(u.idx)] = u
	var duration: float = float(result.get("duration", 0.0))
	var winner: int = int(brr.get("winner_team", -1))
	var pid: String = str(dmr.get("preset", config.get("arena_id", "")))
	var preset: Dictionary = BattlegroundMapData.PRESETS.get(pid, {})
	team_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pa: int = int(a.get("place", 0)) if int(a.get("place", 0)) > 0 else 999
		var pb: int = int(b.get("place", 0)) if int(b.get("place", 0)) > 0 else 999
		return pa < pb if pa != pb else int(a.team) < int(b.team))

	# ---- head
	var title: String = "무승부"
	var col: Color = UITheme.GOLD
	if winner >= 0:
		var wrow: Dictionary = {}
		for t in team_rows:
			if int(t.team) == winner:
				wrow = t
		var members: Array = wrow.get("members", [])
		if squad <= 1 and not members.is_empty() and by_idx.has(int(members[0])):
			title = "%s %s 우승" % [_br_label(winner, squad), DB.char_def(str(by_idx[int(members[0])].id)).name]
		else:
			title = "%s 우승" % _br_label(winner, squad)
		col = UITheme.team_color(winner)
	var last: bool = str(result.get("reason", "")) == "battleground_last"
	var heroes: int = ranking.size()
	var facts: Array = [
		["마지막 생존 팀" if last else "시간 종료 · 생존 인원·체력 판정", col, "strong",
			"다른 팀이 모두 탈락해 승부가 났습니다." if last else "제한 시간 %s이 지나 남은 팀을 생존 인원, 그다음 체력 합으로 순위를 정했습니다." % UITheme.fmt_time(duration)],
		[("%s · %d명" % [str(BR_SQUAD_NAMES.get(squad, "솔로")), heroes]) if squad <= 1 else ("%s · %d팀 %d명" % [str(BR_SQUAD_NAMES.get(squad, "")), team_rows.size(), heroes]), UITheme.ACCENT, "soft", ""],
		[str(preset.get("name", "배틀그라운드")), UITheme.TEXT_DIM, "soft", str(preset.get("subtitle", ""))],
		["자기장 " + str(BrZone.SPEED_LABELS.get(str(brr.get("zone_speed", "normal")), "보통")), Color("#cf9bff"), "soft", "자기장 일정의 빠르기입니다."],
		["경기 시간 " + UITheme.fmt_time(duration), UITheme.TEXT_DIM, "soft", ""],
		["시드 %d" % int(result.get("seed", 0)), UITheme.TEXT_DIM, "outline", "같은 시드로 다시 하면 지형·아이템·자기장·전투가 똑같이 재생됩니다."]]
	var new_cb: Callable = func() -> void:
		app.goto("battleground")
	body.add_child(_report_head("BATTLEGROUND REPORT", title, col, facts, "새 배틀그라운드 편성", new_cb,
		"결정론적 시뮬레이션이라 같은 설정이면 지형·아이템·자기장·전투가 똑같이 다시 재생됩니다."))

	# ---- podium + survivor chart
	var row: HBoxContainer = UITheme.hbox(UITheme.SP4)
	row.add_child(_br_podium(team_rows, by_idx, squad, duration))
	var chart: SurvivorChart = SurvivorChart.new()
	var events: Array = []
	for k in dmr.get("kill_log", []):
		var vt: int = int(k[2])
		events.append({"t": float(k[0]), "kind": "kill", "color": UITheme.team_color(vt), "text": "%s 영웅 탈락" % _br_label(vt, squad)})
	for kn in result.get("br_knocks", []):
		events.append({"t": float(kn[0]), "kind": "knock", "color": UITheme.team_color(int(kn[1])), "text": "%s 영웅 다운" % _br_label(int(kn[1]), squad)})
	for t in team_rows:
		if float(t.get("elim_time", -1.0)) >= 0.0:
			events.append({"t": float(t.elim_time), "kind": "team_out", "color": UITheme.team_color(int(t.team)),
				"text": "%s 탈락 · %d위" % [_br_label(int(t.team), squad), int(t.get("place", 0))]})
	var phases: Array = []
	for z in BrZone.schedule_rows(str(brr.get("zone_speed", "normal"))):
		if float(z.shrink_start) < duration:
			phases.append({"phase": int(z.phase), "start": float(z.shrink_start), "end": float(z.shrink_end)})
	# The mode records [time, teams, heroes]; the chart expects [time, heroes, teams].
	var samples: Array = []
	for sample in brr.get("series", []):
		samples.append([float(sample[0]), int(sample[2]), int(sample[1])])
	chart.set_data({"total": heroes, "teams_total": team_rows.size(), "max_time": maxf(1.0, duration), "samples": samples,
		"phases": phases, "events": events, "winner": title})
	chart.custom_minimum_size = Vector2(0, 250)
	chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chart.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var gv: VBoxContainer = UITheme.vbox(UITheme.SP3)
	gv.add_child(UITheme.section_header("생존자 흐름", "살아 있는 영웅%s · 보라 띠 = 자기장 수축" % (" · 팀" if squad > 1 else "")))
	gv.add_child(chart)
	var gp: PanelContainer = _card(gv)
	gp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(gp)
	body.add_child(row)

	# ---- ranking table grouped by team
	var cols: Array = [_col("순위", 44, "c"), _col("팀", 56, "l", false, 40.0), _col("참가자", 200, "l", false, 150.0), _col("처치", 52, "r", true),
		_col("다운시킴", 64), _col("소생", 52), _col("피해", 80, "r", true), _col("생존 시간", 72), _col("주운 아이템", 76), _col("최종 보유", 110, "l", false, -1.0, 18)]
	var rows: Array = []
	var best: Dictionary = {}
	for ti in team_rows.size():
		var t: Dictionary = team_rows[ti]
		var team: int = int(t.team)
		var place: int = int(t.get("place", 0))
		var members: Array = t.get("members", [])
		for mi in members.size():
			var r: Dictionary = by_idx.get(int(members[mi]), {})
			if r.is_empty():
				continue
			var first: bool = mi == 0
			var cells: Array = [_rank_cell(place) if first else Control.new(), _br_team_cell(team, squad) if first else Control.new(), _br_player_cell(r, units.get(int(r.idx), {}), squad),
				[str(int(r.kills)), float(r.kills)], [str(int(r.get("knocks", 0))), float(r.get("knocks", 0))], [str(int(r.get("revives", 0))), float(r.get("revives", 0))],
				[_fmt_int(int(r.damage)), float(int(r.damage))], [UITheme.fmt_time(float(r.get("survival", 0.0))), float(r.get("survival", 0.0))],
				[str(int(r.items)), float(r.items)], _held_cell(r)]
			for ci in [3, 4, 5, 6, 7, 8]:
				best[ci] = maxf(float(best.get(ci, 0.0)), float(cells[ci][1]))
			var style: StyleBox = _medal_style(ti) if ti < 3 else _zebra(ti, true)
			rows.append({"cells": cells, "style": style})
	var tv: VBoxContainer = UITheme.vbox(UITheme.SP2)
	tv.add_child(UITheme.section_header("최종 순위", "팀 순위 = 탈락 역순 · 팀 안에서는 생존 → 처치 → 피해 순",
		_best_legend("처치·다운시킴·소생·피해·생존 시간·주운 아이템에서 가장 높은 기록입니다.")))
	tv.add_child(_stat_table(cols, rows, best))
	body.add_child(_card(tv))
	body.add_child(UITheme.hint_label("다운시킴은 듀오·트리오에서 적을 다운시킨 횟수입니다. 자기장·출혈로 쓰러지면 %s초 안에 마지막으로 피해를 준 적 영웅의 처치로 기록됩니다. 탈락하면 지닌 아이템은 모두 그 자리에 떨어집니다." % CodexData.num(BattlegroundMode.ZONE_CREDIT_WINDOW)))


## Top-3 teams: medal, team label, member discs and names, team kills / knocks and when it fell;
## below, the match highlights (most kills, most damage, most revives).
func _br_podium(team_rows: Array, by_idx: Dictionary, squad: int, duration: float) -> Control:
	var v: = UITheme.vbox(UITheme.SP2)
	v.add_child(UITheme.section_header("시상대", "상위 3팀" if squad > 1 else "상위 3명"))
	for i in mini(3, team_rows.size()):
		var t: Dictionary = team_rows[i]
		var team: int = int(t.team)
		var members: Array = t.get("members", [])
		var ph: = UITheme.hbox(UITheme.SP3)
		var medal: = UITheme.label(str(i + 1), "BlackLabel", 22 if i == 0 else 18, MEDALS[i])
		medal.custom_minimum_size = Vector2(22, 0)
		medal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		medal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ph.add_child(medal)
		var discs: = UITheme.hbox(-6 if members.size() > 1 else 0)
		discs.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var kills: int = 0
		var knocks: int = 0
		var names: PackedStringArray = PackedStringArray()
		for idx in members:
			var r: Dictionary = by_idx.get(int(idx), {})
			if r.is_empty():
				continue
			var d: Defs.CharDef = DB.char_def(str(r.id))
			var disc: = GlyphDisc.new(d, (40 if i == 0 else 34) if members.size() == 1 else 30, team)
			disc.set_state(1.0 if float(r.get("survival", 0.0)) >= duration - 0.01 else 0.0, 0.0, float(r.get("survival", 0.0)) < duration - 0.01)
			discs.add_child(disc)
			kills += int(r.kills)
			knocks += int(r.get("knocks", 0))
			names.append(d.name)
		ph.add_child(discs)
		var pv: = UITheme.vbox(3)
		pv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var fell: float = float(t.get("elim_time", -1.0))
		var status: String = ("다운시킴 %d · " % knocks if squad > 1 else "") + ("끝까지 생존" if fell < 0.0 else "%s 탈락" % UITheme.fmt_time(fell))
		var nh: = UITheme.hbox(6)
		nh.add_child(_center(UITheme.badge(_br_label(team, squad), UITheme.team_color(team), "strong")))
		if squad <= 1:
			# Solo: the hero's name is the headline.
			var nm: = UITheme.ellipsize(UITheme.label(" · ".join(names), "BlackLabel", 20 if i == 0 else 16), true)
			nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			nh.add_child(nm)
			pv.add_child(nh)
			var sh: = UITheme.hbox(6)
			sh.add_child(_center(UITheme.badge("%d킬" % kills, MEDALS[i] if i == 0 else UITheme.TEXT_DIM, "strong" if i == 0 else "soft")))
			sh.add_child(_center(UITheme.label(status, "CaptionLabel")))
			pv.add_child(sh)
		else:
			# Squads: team, kills and fate on top, the members underneath.
			nh.add_child(_center(UITheme.badge("%d킬" % kills, MEDALS[i] if i == 0 else UITheme.TEXT_DIM, "strong" if i == 0 else "soft")))
			nh.add_child(_center(UITheme.label(status, "CaptionLabel")))
			pv.add_child(nh)
			var ml: = UITheme.ellipsize(UITheme.label(" · ".join(names), "BoldLabel", 15 if i == 0 else 14), true)
			ml.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			pv.add_child(ml)
		ph.add_child(pv)
		var tint: StyleBoxFlat = UITheme.sbc(Color(1, 1, 1, 0.025), UITheme.CLEAR, UITheme.R_M, 1, 10, 6)
		if i == 0:
			tint = UITheme.sbc(Color(UITheme.GOLD, 0.07), Color(UITheme.GOLD, 0.3), UITheme.R_M, 1, 10, 8)
		var pp: = UITheme.styled_panel(tint, ph)
		pp.mouse_filter = Control.MOUSE_FILTER_PASS
		v.add_child(pp)
	if team_rows.is_empty():
		v.add_child(UITheme.empty_state("●", "기록이 없습니다"))
	# Highlights: the best hero per stat (ties: the better-placed team, then the first listed).
	var tiles: = UITheme.hbox(UITheme.SP2)
	for spec in [["kills", "최다 처치", "%d"], ["damage", "최다 피해", "%s"], ["revives" if squad > 1 else "items", "최다 소생" if squad > 1 else "최다 획득", "%d"]]:
		var key: String = str(spec[0])
		var top: Dictionary = {}
		for t in team_rows:
			for idx in t.get("members", []):
				var r: Dictionary = by_idx.get(int(idx), {})
				if not r.is_empty() and float(r.get(key, 0)) > float(top.get(key, 0)):
					top = r
		if top.is_empty():
			continue
		var value: String = _fmt_int(int(top[key])) if key == "damage" else str(int(top[key]))
		var tile: = UITheme.stat_tile(str(spec[1]), value, UITheme.GOLD, "%s %s" % [_br_label(int(top.team), squad), DB.char_def(str(top.id)).name])
		var who: = UITheme.ellipsize(UITheme.label("%s %s" % [_br_label(int(top.team), squad), DB.char_def(str(top.id)).name], "FaintLabel", UITheme.FS_MICRO))
		(tile.get_child(0) as VBoxContainer).add_child(who)
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tiles.add_child(tile)
	if tiles.get_child_count() > 0:
		v.add_child(UITheme.spacer(0, 2))
		v.add_child(tiles)
	else:
		tiles.free()
	var p: = _card(v)
	p.custom_minimum_size.x = 400
	return p


func _br_team_cell(team: int, squad: int) -> Control:
	var b: = UITheme.badge(_br_label(team, squad), UITheme.team_color(team), "strong")
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return _center(b)


## Hero name cell: disc (greyed when out), name and how the hero ended (생존 / 자기장 / 출혈 / 처치됨).
func _br_player_cell(r: Dictionary, u: Dictionary, squad: int) -> Control:
	var h: = UITheme.hbox(UITheme.SP2)
	var team: int = int(r.team)
	var d: Defs.CharDef = DB.char_def(str(r.id))
	var alive: bool = bool(u.get("alive", int(r.get("deaths", 1)) == 0))
	var disc: = GlyphDisc.new(d, 24, team)
	disc.set_state(clampf(float(u.get("hp", 0.0)) / maxf(1.0, float(u.get("max_hp", 1.0))), 0.0, 1.0) if alive else 0.0, 0.0, not alive)
	disc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(disc)
	var nl: = UITheme.ellipsize(UITheme.label(d.name, "BoldLabel", 14))
	nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(nl)
	var cause: String = str(r.get("death_cause", ""))
	var st_text: String = "생존" if alive else str({"zone": "자기장", "bleed": "출혈", "team_wipe": "팀 전멸", "hazard": "환경"}.get(cause, "처치됨"))
	var st: = UITheme.label(st_text, "", 12, UITheme.GOOD if alive else UITheme.TEXT_FAINT)
	st.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(st)
	return h


# ================================================================== shared parts

## Report head: page_header with a 36 px coloured title, a row of fact badges ([text, color, style,
## tooltip]) and shrink-centred actions (rematch / new setup (primary) / home).
func _report_head(eyebrow: String, title: String, color: Color, facts: Array, new_label: String, new_cb: Callable, again_tip: String) -> Control:
	var again_cb: Callable = func() -> void:
		app.start_battle(config, app.battle_origin)
	var home_cb: Callable = func() -> void:
		app.goto("home")
	var again: = UITheme.button("↻ 같은 시드로 재대결", "", again_cb, again_tip)
	var nb: = UITheme.button(new_label, "PrimaryButton", new_cb)
	var hb: = UITheme.button("홈", "GhostButton", home_cb, "홈 화면으로 돌아갑니다.")
	again.custom_minimum_size = Vector2(0, 44)
	nb.custom_minimum_size = Vector2(150, 44)
	hb.custom_minimum_size = Vector2(72, 44)
	var head: HBoxContainer = UITheme.page_header(eyebrow, title, "", [again, nb, hb])
	var tl: Label = head.get_meta("title")
	tl.add_theme_font_size_override("font_size", UITheme.FS_DISPLAY)
	tl.add_theme_color_override("font_color", color)
	var fr: = HFlowContainer.new()
	fr.add_theme_constant_override("h_separation", 6)
	fr.add_theme_constant_override("v_separation", 6)
	for f in facts:
		var b: = UITheme.badge(str(f[0]), f[1], str(f[2]), str(f[3]) if f.size() > 3 else "")
		(b.get_meta("label") as Label).add_theme_font_size_override("font_size", UITheme.FS_CAPTION)
		fr.add_child(b)
	var left: VBoxContainer = tl.get_parent()
	left.add_child(UITheme.spacer(0, 4))
	left.add_child(fr)
	return head


## Column spec: min width w, alignment "l"/"r"/"c", strong (TEXT instead of TEXT_DIM), stretch ratio
## (default w) and a left inset (separates a left-aligned column from a right-aligned neighbour).
func _col(title: String, w: int, align: String = "r", strong: bool = false, ratio: float = -1.0, inset: int = 0) -> Dictionary:
	return {"title": title, "w": w, "align": align, "strong": strong, "ratio": ratio if ratio > 0.0 else float(w), "inset": inset}


## Table: caption header row + hairline + one panel per row.
## cols: _col() dicts; every column keeps its min width and expands in proportion to it, so header,
##       rows and sibling tables line up. Numeric columns are right-aligned.
## rows: [{"cells": Array, "style": StyleBox, "sub": Control (optional, shown under the row)}];
##       a cell is a Control (used as is), [text, raw] (numeric), or a plain value.
## best: {column index: best raw}; a cell equal to it (and > 0) is gold + bold, zeros are faint.
func _stat_table(cols: Array, rows: Array, best: Dictionary) -> VBoxContainer:
	var t: = UITheme.vbox(2)
	var hdr: = UITheme.hbox(COL_GAP)
	for c in cols:
		var l: = UITheme.ellipsize(UITheme.label(str(c.title), "FaintLabel", UITheme.FS_MICRO))
		l.horizontal_alignment = _align(str(c.align))
		hdr.add_child(_place(l, c))
	t.add_child(UITheme.margin(hdr, ROW_PAD, 0, ROW_PAD, 4))
	t.add_child(UITheme.sep_line())
	t.add_child(UITheme.spacer(0, 2))
	for row in rows:
		var rv: = UITheme.vbox(4)
		var rh: = UITheme.hbox(COL_GAP)
		var cells: Array = row.cells
		for ci in cols.size():
			rh.add_child(_cell(cells[ci], cols[ci], best.get(ci)))
		rv.add_child(rh)
		var sub: Control = row.get("sub")
		if sub:
			rv.add_child(sub)
		var p: = UITheme.styled_panel(row.get("style", _zebra(1, false)), rv)
		p.mouse_filter = Control.MOUSE_FILTER_PASS
		t.add_child(p)
	return t


func _cell(v: Variant, c: Dictionary, best_v: Variant) -> Control:
	var out: Control
	if v is Control:
		out = v
	else:
		var text: String = str(v)
		var raw: float = -1.0
		if v is Array:
			text = str(v[0])
			raw = float(v[1])
		elif v is int or v is float:
			raw = float(v)
		var top_v: bool = best_v != null and raw > 0.0 and absf(raw - float(best_v)) < 0.001
		var fg: Color = UITheme.TEXT if bool(c.strong) else UITheme.TEXT_DIM
		if top_v:
			fg = UITheme.GOLD
		elif raw == 0.0:
			fg = UITheme.TEXT_FAINT
		var l: = UITheme.label(text, "", UITheme.FS_SM, fg)
		if top_v:
			l.add_theme_font_override("font", DB.font_bold)
		l.horizontal_alignment = _align(str(c.align))
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		out = l
	return _place(out, c)


## Gives a cell its column width/ratio; columns with an inset get a left margin wrapper.
func _place(n: Control, c: Dictionary) -> Control:
	var out: Control = n
	if int(c.inset) > 0:
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		out = UITheme.margin(n, int(c.inset), 0, 0, 0)
	out.custom_minimum_size.x = float(c.w)
	out.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	out.size_flags_stretch_ratio = float(c.ratio)
	out.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return out


func _align(a: String) -> HorizontalAlignment:
	if a == "l":
		return HORIZONTAL_ALIGNMENT_LEFT
	if a == "c":
		return HORIZONTAL_ALIGNMENT_CENTER
	return HORIZONTAL_ALIGNMENT_RIGHT


## Zebra row style (every other row gets a faint fill); compact rows use less vertical padding.
func _zebra(i: int, compact: bool) -> StyleBoxFlat:
	var vpad: int = 3 if compact else 5
	return UITheme.sbc(Color(1, 1, 1, 0.03) if i % 2 == 0 else UITheme.CLEAR, UITheme.CLEAR, UITheme.R_S, 0, ROW_PAD, vpad)


## Top-3 deathmatch rows: medal tint with a 3 px medal bar on the left.
static func _medal_style(i: int) -> StyleBoxFlat:
	var key: = "medal%d" % i
	var s: StyleBoxFlat = _styles.get(key)
	if s == null:
		var mc: Color = MEDALS[clampi(i, 0, 2)]
		s = UITheme.sb(Color(mc, 0.075 if i == 0 else 0.05), Color(mc, 0.85), UITheme.R_S, 0, ROW_PAD, 3)
		s.border_width_left = 3
		s.corner_radius_top_left = 2
		s.corner_radius_bottom_left = 2
		_styles[key] = s
	return s


## CardPanel that lets wheel events reach the page scroller.
func _card(child: Control) -> PanelContainer:
	var p: = UITheme.panel("CardPanel", child)
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	return p


func _center(c: Control) -> Control:
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return c


## Vertical colour bar (team marker in table heads).
func _bar(color: Color, h: int) -> Control:
	var p: = Panel.new()
	p.add_theme_stylebox_override("panel", UITheme.sbc(color, UITheme.CLEAR, 2, 0, 0, 0))
	p.custom_minimum_size = Vector2(4, h)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


## Chart legend: [[text, color, dashed], ...] as line swatches + captions.
func _legend(entries: Array) -> HBoxContainer:
	var h: = UITheme.hbox(UITheme.SP3)
	for e in entries:
		var it: = UITheme.hbox(6)
		it.add_child(_swatch(e[1], bool(e[2])))
		it.add_child(UITheme.label(str(e[0]), "CaptionLabel"))
		h.add_child(it)
	return h


func _swatch(color: Color, dashed: bool) -> Control:
	var h: = UITheme.hbox(2)
	h.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in (3 if dashed else 1):
		var p: = Panel.new()
		p.add_theme_stylebox_override("panel", UITheme.sbc(color, UITheme.CLEAR, 1, 0, 0, 0))
		p.custom_minimum_size = Vector2(4, 2) if dashed else Vector2(16, 3)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(p)
	return h


## "금색 = 항목 최고" caption with a gold swatch; tip explains which columns count.
func _best_legend(tip_text: String) -> Control:
	var h: = UITheme.hbox(6)
	var sw: = Panel.new()
	sw.add_theme_stylebox_override("panel", UITheme.sbc(UITheme.GOLD, UITheme.CLEAR, 3, 0, 0, 0))
	sw.custom_minimum_size = Vector2(9, 9)
	sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(sw)
	h.add_child(UITheme.label(BEST_CAPTION, "CaptionLabel"))
	h.tooltip_text = UITheme.tip(tip_text)
	h.mouse_filter = Control.MOUSE_FILTER_PASS
	return h


func _hp_color(ratio: float) -> Color:
	if ratio > 0.5:
		return UITheme.GOOD
	if ratio > 0.25:
		return UITheme.WARN
	return UITheme.BAD


## 12345 -> "12,345".
static func fmt_int(n: int) -> String:
	var s: = str(absi(n))
	var out: = ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


func _fmt_int(n: int) -> String:
	return fmt_int(n)


## Smallest "nice" step (1, 2, 2.5, 5 x 10^k) that is >= raw.
static func nice_step(raw: float) -> float:
	if raw <= 0.0:
		return 1.0
	var mag: float = pow(10.0, floorf(log(raw) / log(10.0)))
	for k in [1.0, 2.0, 2.5, 5.0, 10.0]:
		if float(k) * mag >= raw - 0.000001:
			return float(k) * mag
	return 10.0 * mag


## Spreads label baselines (sorted by y) at least gap apart inside [lo, hi]. Items: [y, ...].
static func spread_labels(items: Array, gap: float, lo: float, hi: float) -> void:
	items.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for k in range(1, items.size()):
		items[k][0] = maxf(float(items[k][0]), float(items[k - 1][0]) + gap)
	if items.is_empty():
		return
	var over: float = float(items[items.size() - 1][0]) - hi
	if over > 0.0:
		for it in items:
			it[0] = float(it[0]) - over
	var under: float = lo - float(items[0][0])
	if under > 0.0:
		for it in items:
			it[0] = float(it[0]) + under


## Time axis ("m:ss") under rect r: first label left-aligned, last right-aligned, others centred.
static func draw_time_axis(ci: CanvasItem, r: Rect2, tmax: float, y: float) -> void:
	var font: Font = DB.font_regular
	for k in 6:
		var x: float = r.position.x + r.size.x * float(k) / 5.0
		var txt: String = UITheme.fmt_time(tmax * float(k) / 5.0)
		var align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER
		var bx: float = x - 30.0
		if k == 0:
			align = HORIZONTAL_ALIGNMENT_LEFT
			bx = x
		elif k == 5:
			align = HORIZONTAL_ALIGNMENT_RIGHT
			bx = x - 60.0
		ci.draw_string(font, Vector2(bx, y), txt, align, 60.0, UITheme.FS_MICRO, UITheme.TEXT_FAINT)


# ================================================================== charts

## Cumulative kills per participant (step lines). Top 3 are highlighted and labelled at the line end,
## the winner's line glows, the kill target is a labelled dashed gold line; integer y ticks.
class KillRace:
	extends Control
	var kill_log: Array = []
	var ranking: Array = []
	var max_time: float = 60.0
	var target: int = 10

	func _end_text(row: Dictionary) -> String:
		return "P%d %s  %d" % [int(row.team) + 1, DB.char_def(str(row.id)).name, int(row.kills)]

	func _draw() -> void:
		var font: Font = DB.font_regular
		var bold: Font = DB.font_bold
		var fsz: int = UITheme.FS_MICRO
		var hl: int = mini(3, ranking.size())
		var texts: Array = []
		var gutter: float = 12.0
		for i in hl:
			var s: String = _end_text(ranking[i])
			texts.append(s)
			gutter = maxf(gutter, bold.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz).x + 20.0)
		gutter = minf(gutter, size.x * 0.3)
		var r: Rect2 = Rect2(Vector2(28, 20), Vector2(maxf(10.0, size.x - 28.0 - gutter), maxf(10.0, size.y - 20.0 - 24.0)))
		draw_rect(r, Color(1, 1, 1, 0.02))
		var top: float = float(target)
		for row in ranking:
			top = maxf(top, float(row.kills))
		top = maxf(1.0, top)
		var step: int = maxi(1, int(ceil(top / 5.0)))
		var tick: int = 0
		while float(tick) <= top + 0.001:
			var y: float = r.end.y - r.size.y * float(tick) / top
			draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), Color(1, 1, 1, 0.12 if tick == 0 else 0.05), 1.0)
			draw_string(font, Vector2(0, y + 4), str(tick), HORIZONTAL_ALIGNMENT_RIGHT, r.position.x - 8.0, fsz, UITheme.TEXT_FAINT)
			tick += step
		if target > 0:
			var ty: float = r.end.y - r.size.y * float(target) / top
			draw_dashed_line(Vector2(r.position.x, ty), Vector2(r.end.x, ty), Color(UITheme.GOLD, 0.7), 1.5, 6.0)
			draw_string(bold, Vector2(r.position.x + 6.0, ty - 5.0), "목표 %d킬" % target, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, UITheme.GOLD)
		var tmax: float = maxf(1.0, max_time)
		var ends: Array = []
		for i in range(ranking.size() - 1, -1, -1):
			var row: Dictionary = ranking[i]
			var team: int = int(row.team)
			var pts: PackedVector2Array = PackedVector2Array([Vector2(r.position.x, r.end.y)])
			var n: int = 0
			for e in kill_log:
				if int(e[1]) != team:
					continue
				var x: float = r.position.x + r.size.x * clampf(float(e[0]) / tmax, 0.0, 1.0)
				pts.append(Vector2(x, r.end.y - r.size.y * float(n) / top))
				n += 1
				pts.append(Vector2(x, r.end.y - r.size.y * float(n) / top))
			var end: Vector2 = Vector2(r.end.x, r.end.y - r.size.y * float(n) / top)
			pts.append(end)
			var col: Color = UITheme.team_color(team)
			if i == 0:
				draw_polyline(pts, Color(col, 0.18), 8.0, true)
				draw_polyline(pts, col, 3.0, true)
			elif i < 3:
				draw_polyline(pts, Color(col, 0.95), 2.0, true)
			else:
				draw_polyline(pts, Color(col, 0.3), 1.25, true)
			if i < hl:
				draw_circle(end, 4.5 if i == 0 else 3.5, col)
				ends.append([end.y + 4.0, col, texts[i], i == 0])
		ResultScreen.spread_labels(ends, 15.0, r.position.y + 4.0, r.end.y + 4.0)
		for e in ends:
			draw_string(bold if bool(e[3]) else font, Vector2(r.end.x + 10.0, float(e[0])), str(e[2]), HORIZONTAL_ALIGNMENT_LEFT,
				gutter - 12.0, fsz, (e[1] as Color).lightened(0.3))
		ResultScreen.draw_time_axis(self, r, tmax, size.y - 5.0)


## Two team lines (HP sum, or control score) with soft fills, "nice" y ticks, end values and, in
## control mode, a labelled dashed target line.
class HpChart:
	extends Control
	var history: Array = []
	var max_time: float = 150.0
	var target: float = -1.0

	func _draw() -> void :
		var font: Font = DB.font_regular
		var bold: Font = DB.font_bold
		var fsz: int = UITheme.FS_MICRO
		var top: float = 1.0
		for row in history:
			top = maxf(top, maxf(float(row[1]), float(row[2])))
		if target > 0.0:
			top = maxf(top, target)
		top *= 1.06
		var step: float = ResultScreen.nice_step(top / 4.0)
		var last_tick: float = floorf(top / step) * step
		var left: float = font.get_string_size(ResultScreen.fmt_int(int(last_tick)), HORIZONTAL_ALIGNMENT_LEFT, -1, fsz).x + 10.0
		var finals: Array = []
		var right: float = 12.0
		if history.size() >= 2:
			var lastrow: Array = history[history.size() - 1]
			for t in 2:
				var s: String = ResultScreen.fmt_int(int(round(float(lastrow[1 + t]))))
				finals.append(s)
				right = maxf(right, bold.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz).x + 20.0)
		var pad_top: float = 20.0 if target > 0.0 else 10.0
		var r: = Rect2(Vector2(left, pad_top), Vector2(maxf(10.0, size.x - left - right), maxf(10.0, size.y - pad_top - 24.0)))
		draw_rect(r, Color(1, 1, 1, 0.02))
		var v: float = 0.0
		while v <= top + 0.001:
			var y: float = r.end.y - r.size.y * v / top
			draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), Color(1, 1, 1, 0.12 if v == 0.0 else 0.05), 1.0)
			draw_string(font, Vector2(0, y + 4), ResultScreen.fmt_int(int(v)), HORIZONTAL_ALIGNMENT_RIGHT, left - 8.0, fsz, UITheme.TEXT_FAINT)
			v += step
		var tmax: = maxf(1.0, max_time)
		ResultScreen.draw_time_axis(self, r, tmax, size.y - 5.0)
		if history.size() < 2:
			draw_string(font, Vector2(r.position.x, r.get_center().y), "기록이 없습니다", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, UITheme.FS_CAPTION, UITheme.TEXT_FAINT)
			return
		if target > 0.0:
			var ty: float = r.end.y - r.size.y * target / top
			draw_dashed_line(Vector2(r.position.x, ty), Vector2(r.end.x, ty), Color(UITheme.GOLD, 0.7), 1.5, 6.0)
			draw_string(bold, Vector2(r.position.x + 6.0, ty - 5.0), "목표 %s점" % ResultScreen.fmt_int(int(target)), HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, UITheme.GOLD)
		var ends: Array = []
		for t in 2:
			var pts: = PackedVector2Array()
			for row in history:
				var x: = r.position.x + r.size.x * clampf(float(row[0]) / tmax, 0.0, 1.0)
				var y2: = r.end.y - r.size.y * float(row[1 + t]) / top
				pts.append(Vector2(x, y2))
			var col: = UITheme.team_color(t)
			var fill: = pts.duplicate()
			fill.append(Vector2(pts[pts.size() - 1].x, r.end.y))
			fill.append(Vector2(pts[0].x, r.end.y))
			draw_colored_polygon(fill, Color(col, 0.08))
			draw_polyline(pts, col, 2.0, true)
			var end: Vector2 = pts[pts.size() - 1]
			draw_circle(end, 3.5, col)
			ends.append([end.y + 4.0, col, finals[t]])
		ResultScreen.spread_labels(ends, 15.0, r.position.y + 4.0, r.end.y + 4.0)
		for e in ends:
			draw_string(bold, Vector2(r.end.x + 10.0, float(e[0])), str(e[2]), HORIZONTAL_ALIGNMENT_LEFT, right - 12.0, fsz, (e[1] as Color).lightened(0.25))
