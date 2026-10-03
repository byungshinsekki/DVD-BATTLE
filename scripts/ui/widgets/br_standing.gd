class_name BrStanding
extends Control
## Battleground standing for the side panel: compact 36 px hero rows grouped by team, teams still
## in the game first, then eliminated teams collapsed to one 28 px line each ("12위 · 3:41 탈락").
## Each live group has a team-colour edge and the team label; a hero row shows the disc, the name,
## HP or the downed / dead state, and kills (plus knocks for duos and trios). Custom drawn: the
## height follows the content, so put it in a ScrollContainer. Hover shows a row's details; a
## click emits member_pressed(team, member) or, on a collapsed line, team_pressed(team).
## Mode-independent: it never reads the simulation.
##
## Input: set_teams(teams), one Dictionary per team (DESIGN_V2 §3.5 BattlegroundMode fields):
##   team: int            0-based team index
##   label: String        team_label(team) — "3팀", solo "P7"
##   color: Color         UITheme.team_color(team)
##   eliminated: bool     placement.has(team)
##   place: int           placement[team] (1 = winner); used once eliminated or at the end
##   elim_time: float     elim_time[team], seconds
##   members: Array       one Dictionary per hero, in player order:
##     name: String, glyph: String, color: Color (hero accent)
##     state: String        "alive" | "downed" | "dead"
##     hp: float            0..1; below 0 = unknown in this perspective
##     downed_left: float   downed: seconds until bleed-out
##     revive: float        optional: downed_info.revive_progress 0..1 (0 = nobody reviving)
##     kills, knocks, revives: int   hstats[u.idx]
##     damage: float        optional, hstats damage (tooltip)
##     note: String         optional second line override (e.g. "자기장 사망")
## Ordering is done here: live teams by heroes standing, then standing + downed, then kills, then
## team index; eliminated teams by place. Each call rebuilds the row layout, so call it when the
## data changed (a few times per second at most), not every frame.

signal member_pressed(team: int, member: int)
signal team_pressed(team: int)

const ROW_H: = 36.0
const OUT_H: = 28.0
const SECTION_H: = 24.0
const GROUP_GAP: = 4.0
const MIN_W: = 300.0
const LABEL_W: = 44.0
const STAT_W: = 34.0

var teams: Array = []
## Layout rows: {kind: "section" | "member" | "out", y, h, team (index into teams), member, text}.
var rows: Array = []
## Team indices (into teams) in display order: live first, then eliminated.
var order: Array = []
var squad_mode: bool = false

var _hover: int = -1
var _height: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_exited.connect(func() -> void:
		if _hover != -1:
			_hover = -1
			queue_redraw())


func set_teams(list: Array) -> void:
	teams = list
	_build()


static func _standing(t: Dictionary) -> int:
	var n: int = 0
	for m in t.get("members", []):
		if str(m.get("state", "alive")) == "alive":
			n += 1
	return n


static func _in_game(t: Dictionary) -> int:
	var n: int = 0
	for m in t.get("members", []):
		if str(m.get("state", "alive")) != "dead":
			n += 1
	return n


static func _kills(t: Dictionary) -> int:
	var n: int = 0
	for m in t.get("members", []):
		n += int(m.get("kills", 0))
	return n


func _build() -> void:
	var live: Array = []
	var out: Array = []
	squad_mode = false
	for i in teams.size():
		var t: Dictionary = teams[i]
		if (t.get("members", []) as Array).size() > 1:
			squad_mode = true
		if bool(t.get("eliminated", false)):
			out.append(i)
		else:
			live.append(i)
	live.sort_custom(func(a: int, b: int) -> bool:
		var ta: Dictionary = teams[a]
		var tb: Dictionary = teams[b]
		if _standing(ta) != _standing(tb):
			return _standing(ta) > _standing(tb)
		if _in_game(ta) != _in_game(tb):
			return _in_game(ta) > _in_game(tb)
		if _kills(ta) != _kills(tb):
			return _kills(ta) > _kills(tb)
		return int(ta.get("team", a)) < int(tb.get("team", b)))
	out.sort_custom(func(a: int, b: int) -> bool:
		var pa: int = int(teams[a].get("place", 999))
		var pb: int = int(teams[b].get("place", 999))
		return pa < pb if pa != pb else int(teams[a].get("team", a)) < int(teams[b].get("team", b)))
	order = live + out
	rows = []
	var y: float = 0.0
	var heroes: int = 0
	for i in live:
		heroes += _in_game(teams[i])
	var unit: String = "팀" if squad_mode else "명"
	if not live.is_empty():
		var txt: String = ("생존 · %d팀 %d명" % [live.size(), heroes]) if squad_mode else ("생존 · %d명" % live.size())
		rows.append({"kind": "section", "y": y, "h": SECTION_H, "team": -1, "member": -1, "text": txt, "live": true})
		y += SECTION_H
	for i in live:
		var ms: Array = teams[i].get("members", [])
		for k in ms.size():
			rows.append({"kind": "member", "y": y, "h": ROW_H, "team": i, "member": k, "text": ""})
			y += ROW_H
		y += GROUP_GAP
	if not out.is_empty():
		y += 4.0
		rows.append({"kind": "section", "y": y, "h": SECTION_H, "team": -1, "member": -1, "text": "탈락 · %d%s" % [out.size(), unit]})
		y += SECTION_H
	for i in out:
		rows.append({"kind": "out", "y": y, "h": OUT_H, "team": i, "member": -1, "text": out_text(teams[i])})
		y += OUT_H + 2.0
	_height = ceilf(y)
	if _hover >= rows.size():
		_hover = -1
	update_minimum_size()
	queue_redraw()


## Downed hero line: "다운 · 출혈 12초", plus " · 소생 40%" while a teammate revives.
static func downed_text(m: Dictionary) -> String:
	var s: String = "다운 · 출혈 %d초" % int(ceilf(maxf(0.0, float(m.get("downed_left", 0.0)))))
	var rv: float = float(m.get("revive", 0.0))
	return s + (" · 소생 %d%%" % int(rv * 100.0) if rv > 0.0 else "")


## Collapsed line text: "12위 · 3:41 탈락".
static func out_text(t: Dictionary) -> String:
	return "%d위 · %s 탈락" % [int(t.get("place", 0)), UITheme.fmt_time(float(t.get("elim_time", 0.0)))]


func _get_minimum_size() -> Vector2:
	return Vector2(MIN_W, _height)


func _row_at(p: Vector2) -> int:
	for i in rows.size():
		var r: Dictionary = rows[i]
		if p.y >= float(r.y) and p.y < float(r.y) + float(r.h) and str(r.kind) != "section":
			return i
	return -1


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var h: int = _row_at((event as InputEventMouseMotion).position)
		if h != _hover:
			_hover = h
			queue_redraw()
	elif event is InputEventMouseButton:
		var mb: = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var i: int = _row_at(mb.position)
			if i < 0:
				return
			var r: Dictionary = rows[i]
			var team: int = int(teams[int(r.team)].get("team", int(r.team)))
			if str(r.kind) == "member":
				member_pressed.emit(team, int(r.member))
			else:
				team_pressed.emit(team)
			accept_event()


func _get_tooltip(at: Vector2) -> String:
	var i: int = _row_at(at)
	if i < 0:
		return ""
	var r: Dictionary = rows[i]
	var t: Dictionary = teams[int(r.team)]
	if str(r.kind) == "out":
		var names: PackedStringArray = []
		for m in t.get("members", []):
			names.append(str(m.get("name", "")))
		return UITheme.tip("%s · %s\n%s · 처치 %d" % [str(t.get("label", "")), out_text(t), ", ".join(names), _kills(t)])
	var m: Dictionary = (t.get("members", []) as Array)[int(r.member)]
	var line: String = "%s · %s\n처치 %d" % [str(t.get("label", "")), str(m.get("name", "")), int(m.get("kills", 0))]
	if squad_mode:
		line += " · 다운시킴 %d · 소생 %d" % [int(m.get("knocks", 0)), int(m.get("revives", 0))]
	if m.has("damage"):
		line += " · 피해 %s" % _int_text(int(round(float(m.get("damage", 0.0)))))
	return UITheme.tip(line)


static func _int_text(n: int) -> String:
	var s: = str(absi(n))
	var out: = ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


static func _col(v: Variant, fallback: Color) -> Color:
	if v is Color:
		return v
	if v is String and Color.html_is_valid(v):
		return Color.html(v)
	return fallback


# ------------------------------------------------------------------ drawing

func _draw() -> void:
	var w: float = size.x
	# Group frames first (one per live team), then the rows on top.
	var group_top: Dictionary = {}
	var group_bottom: Dictionary = {}
	for r in rows:
		if str(r.kind) != "member":
			continue
		var ti: int = int(r.team)
		if not group_top.has(ti):
			group_top[ti] = float(r.y)
		group_bottom[ti] = float(r.y) + float(r.h)
	for ti in group_top:
		var tc: Color = _col(teams[ti].get("color"), UITheme.ACCENT)
		var gr: = Rect2(0.0, float(group_top[ti]), w, float(group_bottom[ti]) - float(group_top[ti]))
		draw_style_box(UITheme.sbc(Color(tc, 0.05), Color(tc, 0.28), UITheme.R_S, 1, 0), gr)
		draw_rect(Rect2(gr.position.x + 1.0, gr.position.y + 5.0, 3.0, gr.size.y - 10.0), tc)
	for i in rows.size():
		var r: Dictionary = rows[i]
		var rect: = Rect2(0.0, float(r.y), w, float(r.h))
		match str(r.kind):
			"section":
				draw_string(DB.font_bold, Vector2(2.0, rect.position.y + 16.0), str(r.text), HORIZONTAL_ALIGNMENT_LEFT, w - 4.0, UITheme.MIN_FS, UITheme.TEXT_FAINT)
				draw_line(Vector2(0.0, rect.end.y - 3.0), Vector2(w, rect.end.y - 3.0), Color(UITheme.LINE, 0.8), 1.0)
				# Column captions over the stat columns of the rows below.
				var cr: float = w - 10.0
				draw_string(DB.font_regular, Vector2(cr - STAT_W - 8.0, rect.position.y + 16.0), "처치", HORIZONTAL_ALIGNMENT_RIGHT, STAT_W + 8.0, UITheme.MIN_FS, UITheme.TEXT_FAINT)
				if squad_mode and bool(r.get("live", false)):
					draw_string(DB.font_regular, Vector2(cr - STAT_W * 2.0 - 16.0, rect.position.y + 16.0), "다운", HORIZONTAL_ALIGNMENT_RIGHT, STAT_W + 8.0, UITheme.MIN_FS, UITheme.TEXT_FAINT)
			"member":
				if i == _hover:
					draw_rect(rect.grow_individual(-5.0, -1.0, -1.0, -1.0), Color(1, 1, 1, 0.045))
				_draw_member(teams[int(r.team)], int(r.member), rect)
			"out":
				_draw_out(teams[int(r.team)], rect, i == _hover)


func _draw_label_pill(t: Dictionary, x: float, cy: float, dim: bool) -> void:
	var tc: Color = _col(t.get("color"), UITheme.ACCENT)
	var text: String = str(t.get("label", ""))
	var f: Font = DB.font_bold
	var fs: int = UITheme.MIN_FS
	var tw: float = minf(f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x, LABEL_W - 12.0)
	var pr: = Rect2(x, cy - 9.0, tw + 10.0, 18.0)
	if dim:
		draw_style_box(UITheme.sbc(Color(1, 1, 1, 0.04), Color(tc, 0.45), UITheme.R_PILL, 1, 0), pr)
		draw_string(f, Vector2(pr.position.x, cy + 4.5), UITheme.fit_text(f, text, fs, LABEL_W - 12.0), HORIZONTAL_ALIGNMENT_CENTER, pr.size.x, fs, UITheme.TEXT_DIM)
	else:
		draw_style_box(UITheme.sbc(tc, UITheme.CLEAR, UITheme.R_PILL, 0, 0), pr)
		var ink: Color = UITheme.BG if tc.get_luminance() > 0.5 else Color.WHITE
		draw_string(f, Vector2(pr.position.x, cy + 4.5), UITheme.fit_text(f, text, fs, LABEL_W - 12.0), HORIZONTAL_ALIGNMENT_CENTER, pr.size.x, fs, ink)


func _draw_disc(m: Dictionary, c: Vector2, r: float, rim: Color, grey: bool) -> void:
	var st: String = str(m.get("state", "alive"))
	var acc: Color = _col(m.get("color"), UITheme.ACCENT)
	var glyph: String = str(m.get("glyph", "?"))
	var dead: bool = grey or st == "dead"
	if st == "downed" and not grey:
		draw_circle(c, r + 3.0, Color(UITheme.BAD, 0.2), true, -1.0, true)
	draw_circle(c, r, Color(0.2, 0.22, 0.27) if dead else acc.darkened(0.55 if st == "alive" else 0.72), true, -1.0, true)
	if not dead and st == "alive":
		draw_circle(c, r * 0.84, acc.darkened(0.3), true, -1.0, true)
	var edge: Color = Color(0.42, 0.45, 0.52, 0.8) if dead else (UITheme.BAD if st == "downed" else rim)
	draw_arc(c, r, 0, TAU, 32, edge, 1.5, true)
	var gf: Font = DB.font_glyph
	var gs: int = maxi(UITheme.MIN_FS, int(r * (1.15 if glyph.length() <= 1 else 0.8)))
	var gw: float = gf.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, gs).x
	var gp: = Vector2(c.x - gw * 0.5, c.y + (gf.get_ascent(gs) - gf.get_descent(gs)) * 0.5)
	draw_string(gf, gp, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, gs, Color(1, 1, 1, 0.32 if dead else (0.7 if st == "downed" else 1.0)))
	if st == "dead" and not grey:
		var q: float = r * 0.6
		draw_line(c + Vector2(-q, -q), c + Vector2(q, q), Color(UITheme.BAD, 0.8), 1.8, true)
		draw_line(c + Vector2(q, -q), c + Vector2(-q, q), Color(UITheme.BAD, 0.8), 1.8, true)


# "⚔ 3" style stat in a fixed STAT_W column (icon left, value right-aligned at right), so the
# columns line up across rows; returns the column's left x.
func _draw_stat(right: float, base: float, icon: String, value: int, dim: bool, icon_px: int = 15) -> float:
	var vf: Font = DB.font_bold
	var vs: String = str(value)
	var vw: float = vf.get_string_size(vs, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FS_CAPTION).x
	draw_string(vf, Vector2(right - vw, base), vs, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FS_CAPTION, UITheme.TEXT_DIM if dim else UITheme.TEXT)
	var ix: float = right - STAT_W
	draw_string(DB.font_regular, Vector2(ix, base + 0.5), icon, HORIZONTAL_ALIGNMENT_LEFT, -1, icon_px, UITheme.TEXT_FAINT if dim else UITheme.TEXT_DIM)
	return ix


func _draw_member(t: Dictionary, k: int, rect: Rect2) -> void:
	var ms: Array = t.get("members", [])
	var m: Dictionary = ms[k]
	var tc: Color = _col(t.get("color"), UITheme.ACCENT)
	var cy: float = rect.position.y + rect.size.y * 0.5
	if k == 0:
		_draw_label_pill(t, 10.0, cy, false)
	var st: String = str(m.get("state", "alive"))
	_draw_disc(m, Vector2(10.0 + LABEL_W + 14.0, cy), 12.0, tc.lightened(0.1), false)
	var x: float = 10.0 + LABEL_W + 32.0
	var right: float = rect.end.x - 10.0
	var stat_x: float = _draw_stat(right, cy + 5.0, "⚔", int(m.get("kills", 0)), st == "dead")
	if squad_mode:
		stat_x = _draw_stat(stat_x - 8.0, cy + 5.0, "▲", int(m.get("knocks", 0)), st == "dead", UITheme.MIN_FS)
	var text_w: float = stat_x - 10.0 - x
	var hero_name: String = str(m.get("name", ""))
	draw_string(DB.font_bold, Vector2(x, cy - 2.0), UITheme.fit_text(DB.font_bold, hero_name, UITheme.FS_CAPTION, text_w),
		HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FS_CAPTION, UITheme.TEXT_FAINT if st == "dead" else UITheme.TEXT)
	var note: String = str(m.get("note", ""))
	var y2: float = cy + 13.0
	if note != "":
		draw_string(DB.font_regular, Vector2(x, y2), UITheme.fit_text(DB.font_regular, note, UITheme.MIN_FS, text_w), HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.MIN_FS, UITheme.TEXT_DIM)
		return
	match st:
		"downed":
			draw_string(DB.font_bold, Vector2(x, y2), UITheme.fit_text(DB.font_bold, downed_text(m), UITheme.MIN_FS, text_w), HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.MIN_FS,
				UITheme.GOOD if float(m.get("revive", 0.0)) > 0.0 else (UITheme.WARN if float(m.get("downed_left", 0.0)) > 10.0 else UITheme.BAD))
		"dead":
			draw_string(DB.font_regular, Vector2(x, y2), "사망", HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.MIN_FS, UITheme.TEXT_FAINT)
		_:
			var hp: float = float(m.get("hp", 1.0))
			var bar: = Rect2(x, cy + 5.0, minf(96.0, text_w), 4.0)
			if hp < 0.0:
				draw_rect(bar, Color(1, 1, 1, 0.16), false, 1.0)
			else:
				draw_rect(bar, Color(0, 0, 0, 0.5))
				var hc: Color = UITheme.GOOD if hp > 0.5 else (UITheme.WARN if hp > 0.25 else UITheme.BAD)
				draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(hp, 0.0, 1.0), bar.size.y)), hc)


func _draw_out(t: Dictionary, rect: Rect2, hover: bool) -> void:
	draw_style_box(UITheme.sbc(Color(1, 1, 1, 0.045 if hover else 0.02), Color(UITheme.LINE, 0.7), UITheme.R_S, 1, 0), rect)
	var cy: float = rect.position.y + rect.size.y * 0.5
	_draw_label_pill(t, 10.0, cy, true)
	var right: float = rect.end.x - 10.0
	var stat_x: float = _draw_stat(right, cy + 5.0, "⚔", _kills(t), true)
	# Member mini discs, greyed, right to left.
	var ms: Array = t.get("members", [])
	var dx: float = stat_x - 6.0
	for k in range(ms.size() - 1, -1, -1):
		_draw_disc(ms[k], Vector2(dx - 8.0, cy), 8.0, UITheme.TEXT_FAINT, true)
		dx -= 19.0
	var x: float = 10.0 + LABEL_W + 4.0
	var place_s: String = "%d위" % int(t.get("place", 0))
	var bf: Font = DB.font_bold
	draw_string(bf, Vector2(x, cy + 4.5), place_s, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FS_CAPTION, UITheme.TEXT_DIM)
	var pw: float = bf.get_string_size(place_s, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FS_CAPTION).x
	var rest: String = " · %s 탈락" % UITheme.fmt_time(float(t.get("elim_time", 0.0)))
	draw_string(DB.font_regular, Vector2(x + pw, cy + 4.5), UITheme.fit_text(DB.font_regular, rest, UITheme.MIN_FS, dx - x - pw - 4.0),
		HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.MIN_FS, UITheme.TEXT_FAINT)
