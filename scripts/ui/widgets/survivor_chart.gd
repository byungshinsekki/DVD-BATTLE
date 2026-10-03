class_name SurvivorChart
extends Control
## Battleground result chart: heroes still in the game over time (step line with a soft fill) and,
## for duos and trios, teams still in the game on the same count axis. Zone shrinks are shaded
## bands labelled Z1..Z6 behind the lines; final kills sit on the hero line as dots in the
## victim's team colour, knocks as small triangles on a lane above the time axis, and team wipe-outs
## as rings on the team line. Hover shows the time, both counts and the nearest event. Replaces
## KillRace (one line per participant, unreadable at 30) in the battleground report.
## Mode-independent: it never reads the simulation.
##
## Input: set_data(d):
##   total: int           heroes at the start
##   teams_total: int     teams at the start; 0 or equal to total (solo) hides the team line
##   max_time: float      match length in seconds (x axis end)
##   samples: Array       [[t, heroes_alive, teams_alive], ...] at every change, first at t = 0.
##                        When empty, the lines are rebuilt from events ("kill" = -1 hero,
##                        "team_out" = -1 team).
##   phases: Array        [{phase: int, start: float, end: float}] zone shrink intervals
##   events: Array        [{t: float, kind: "kill" | "knock" | "team_out", color: Color (victim
##                        team colour), text: String (optional, tooltip)}]
##   winner: String       optional end label, e.g. "3팀 우승"

const PAD_TOP: = 38.0
const PAD_BOTTOM: = 24.0
const HERO_COL: = UITheme.ACCENT
const TEAM_COL: = UITheme.GOLD
const BAND_COL: = Color(0.62, 0.24, 0.52)

var total: int = 0
var teams_total: int = 0
var max_time: float = 60.0
var samples: Array = []
var phases: Array = []
var events: Array = []
var winner: String = ""

var _plot: Rect2 = Rect2()


func _init() -> void:
	custom_minimum_size = Vector2(480, 220)
	mouse_filter = Control.MOUSE_FILTER_PASS


func set_data(d: Dictionary) -> void:
	total = int(d.get("total", 0))
	teams_total = int(d.get("teams_total", 0))
	max_time = maxf(1.0, float(d.get("max_time", 60.0)))
	phases = d.get("phases", [])
	events = d.get("events", [])
	winner = str(d.get("winner", ""))
	samples = d.get("samples", [])
	if samples.is_empty():
		samples = samples_from_events(total, teams_total, events)
	queue_redraw()


func show_teams() -> bool:
	return teams_total > 1 and teams_total != total


## [[t, heroes, teams], ...] from kill / team_out events (sorted by time).
static func samples_from_events(heroes: int, team_count: int, evs: Array) -> Array:
	var list: Array = evs.duplicate()
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("t", 0.0)) < float(b.get("t", 0.0)))
	var out: Array = [[0.0, heroes, team_count]]
	var h: int = heroes
	var tm: int = team_count
	for e in list:
		var kind: String = str(e.get("kind", ""))
		if kind == "kill":
			h = maxi(0, h - 1)
		elif kind == "team_out":
			tm = maxi(0, tm - 1)
		else:
			continue
		out.append([float(e.get("t", 0.0)), h, tm])
	return out


## Heroes (column 1) or teams (column 2) alive at time t, from the samples.
func count_at(t: float, column: int = 1) -> int:
	var v: int = total if column == 1 else teams_total
	for s in samples:
		if float(s[0]) > t + 0.0001:
			break
		v = int(s[column])
	return v


func _top() -> float:
	var top: int = maxi(1, maxi(total, teams_total if show_teams() else 0))
	for s in samples:
		top = maxi(top, int(s[1]))
	return float(top)


static func _nice_step(raw: float) -> float:
	if raw <= 0.0:
		return 1.0
	var mag: float = pow(10.0, floorf(log(raw) / log(10.0)))
	for k in [1.0, 2.0, 2.5, 5.0, 10.0]:
		if float(k) * mag >= raw - 0.000001:
			return maxf(1.0, float(k) * mag)
	return 10.0 * mag


func _x(t: float) -> float:
	return _plot.position.x + _plot.size.x * clampf(t / max_time, 0.0, 1.0)


func _y(v: float, top: float) -> float:
	return _plot.end.y - _plot.size.y * v / top


func _step_points(column: int, top: float) -> PackedVector2Array:
	var pts: = PackedVector2Array()
	var v: int = int(samples[0][column]) if not samples.is_empty() else (total if column == 1 else teams_total)
	pts.append(Vector2(_x(0.0), _y(v, top)))
	for s in samples:
		var t: float = float(s[0])
		if t <= 0.0:
			v = int(s[column])
			pts[0] = Vector2(_x(0.0), _y(v, top))
			continue
		var nv: int = int(s[column])
		if nv == v:
			continue
		pts.append(Vector2(_x(t), _y(v, top)))
		pts.append(Vector2(_x(t), _y(nv, top)))
		v = nv
	pts.append(Vector2(_x(max_time), _y(v, top)))
	return pts


func _draw() -> void:
	var font: Font = DB.font_regular
	var bold: Font = DB.font_bold
	var fs: int = UITheme.MIN_FS
	var top: float = _top()
	var step: float = _nice_step(top / 4.0)
	var left: float = font.get_string_size(str(int(top)), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 12.0
	var end_heroes: int = count_at(max_time, 1)
	var end_teams: int = count_at(max_time, 2)
	var hero_end: String = "영웅 %d" % end_heroes
	var team_end: String = "팀 %d" % end_teams
	var right: float = bold.get_string_size(hero_end, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 22.0
	if show_teams():
		right = maxf(right, bold.get_string_size(team_end, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 22.0)
	_plot = Rect2(Vector2(left, PAD_TOP), Vector2(maxf(10.0, size.x - left - right), maxf(10.0, size.y - PAD_TOP - PAD_BOTTOM)))
	var r: Rect2 = _plot
	draw_rect(r, Color(1, 1, 1, 0.02))
	# Zone bands (behind everything).
	for ph in phases:
		var x0: float = _x(float(ph.get("start", 0.0)))
		var x1: float = _x(float(ph.get("end", 0.0)))
		if x1 - x0 < 0.5:
			continue
		var depth: float = clampf(float(ph.get("phase", 1)) / 6.0, 0.0, 1.0)
		draw_rect(Rect2(x0, r.position.y, x1 - x0, r.size.y), Color(BAND_COL, 0.09 + 0.08 * depth))
		draw_line(Vector2(x0, r.position.y), Vector2(x0, r.end.y), Color(BAND_COL.lightened(0.3), 0.35), 1.0)
		# Phase name above the plot, so it never sits on the lines.
		var lab: String = "Z%d" % int(ph.get("phase", 0))
		draw_string(font, Vector2(x0, r.position.y - 4.0), lab, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UITheme.TEXT_FAINT)
	# Count grid.
	var v: float = 0.0
	while v <= top + 0.001:
		var y: float = _y(v, top)
		draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), Color(1, 1, 1, 0.12 if v == 0.0 else 0.05), 1.0)
		draw_string(font, Vector2(0, y + 4.0), str(int(v)), HORIZONTAL_ALIGNMENT_RIGHT, left - 8.0, fs, UITheme.TEXT_FAINT)
		v += step
	_draw_time_axis(r, size.y - 6.0)
	_draw_legend()
	if samples.is_empty() or total <= 0:
		draw_string(font, Vector2(r.position.x, r.get_center().y), "기록이 없습니다", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, UITheme.FS_CAPTION, UITheme.TEXT_FAINT)
		return
	# Lines: teams first (under), heroes on top with a soft fill.
	var ends: Array = []
	if show_teams():
		var tp: PackedVector2Array = _step_points(2, top)
		draw_polyline(tp, TEAM_COL, 2.0, true)
		ends.append([tp[tp.size() - 1].y + 4.0, TEAM_COL, team_end])
	var hp: PackedVector2Array = _step_points(1, top)
	var fill: = hp.duplicate()
	fill.append(Vector2(hp[hp.size() - 1].x, r.end.y))
	fill.append(Vector2(hp[0].x, r.end.y))
	draw_colored_polygon(fill, Color(HERO_COL, 0.08))
	draw_polyline(hp, HERO_COL, 2.0, true)
	ends.append([hp[hp.size() - 1].y + 4.0, HERO_COL, hero_end])
	# Event markers: knocks on a lane above the axis, kills on the hero line, wipe-outs on the team line.
	var surface: Color = UITheme.BG
	for e in events:
		var t: float = float(e.get("t", 0.0))
		var x: float = _x(t)
		var cv: Variant = e.get("color")
		var col: Color = cv if cv is Color else UITheme.TEXT_DIM
		match str(e.get("kind", "")):
			"knock":
				var q: = Vector2(x, r.end.y - 7.0)
				draw_colored_polygon(PackedVector2Array([q + Vector2(0, -5.5), q + Vector2(5.0, 3.5), q + Vector2(-5.0, 3.5)]), surface)
				draw_colored_polygon(PackedVector2Array([q + Vector2(0, -3.5), q + Vector2(3.2, 2.2), q + Vector2(-3.2, 2.2)]), col)
			"kill":
				var p: = Vector2(x, _y(count_at(t, 1), top))
				draw_circle(p, 6.0, surface, true, -1.0, true)
				draw_circle(p, 4.0, col, true, -1.0, true)
			"team_out":
				if show_teams():
					var p2: = Vector2(x, _y(count_at(t, 2), top))
					draw_circle(p2, 6.0, surface, true, -1.0, true)
					draw_arc(p2, 4.0, 0, TAU, 16, col, 2.0, true)
	for en in ends:
		draw_circle(Vector2(r.end.x, float(en[0]) - 4.0), 4.0, en[1], true, -1.0, true)
	_spread(ends, 15.0, r.position.y + 4.0, r.end.y + 4.0)
	for en in ends:
		draw_line(Vector2(r.end.x + 8.0, float(en[0]) - 4.0), Vector2(r.end.x + 14.0, float(en[0]) - 4.0), en[1], 2.0)
		draw_string(bold, Vector2(r.end.x + 17.0, float(en[0])), str(en[2]), HORIZONTAL_ALIGNMENT_LEFT, right - 18.0, fs, UITheme.TEXT)
	if winner != "":
		var ww: float = bold.get_string_size(winner, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(bold, Vector2(r.end.x - ww, 13.0), winner, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UITheme.GOLD)


# One row above the plot: line keys and marker keys, in text colours.
func _draw_legend() -> void:
	var font: Font = DB.font_regular
	var fs: int = UITheme.MIN_FS
	var x: float = _plot.position.x
	var y: float = 13.0
	var items: Array = [["line", HERO_COL, "생존 영웅"]]
	if show_teams():
		items.append(["line", TEAM_COL, "생존 팀"])
	items.append(["dot", UITheme.TEXT_DIM, "처치"])
	if show_teams():
		items.append(["tri", UITheme.TEXT_DIM, "다운"])
	items.append(["band", BAND_COL, "자기장 수축"])
	for it in items:
		var c: Color = it[1]
		match str(it[0]):
			"line":
				draw_line(Vector2(x, y - 4.0), Vector2(x + 14.0, y - 4.0), c, 2.0)
				x += 19.0
			"dot":
				draw_circle(Vector2(x + 4.0, y - 4.0), 4.0, c, true, -1.0, true)
				x += 13.0
			"tri":
				var q: = Vector2(x + 4.0, y - 4.0)
				draw_colored_polygon(PackedVector2Array([q + Vector2(0, -4.0), q + Vector2(4.0, 3.0), q + Vector2(-4.0, 3.0)]), c)
				x += 13.0
			"band":
				draw_rect(Rect2(x, y - 10.0, 12.0, 12.0), Color(c, 0.35))
				x += 17.0
		var label: String = str(it[2])
		draw_string(font, Vector2(x, y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UITheme.TEXT_DIM)
		x += font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 14.0


## Seconds between time-axis labels: the smallest round step (30 s .. 10 min) leaving at least
## 90 px per label.
static func time_step(span: float, width: float) -> float:
	var most: int = maxi(2, int(width / 90.0))
	for s in [30.0, 60.0, 120.0, 180.0, 300.0, 600.0]:
		if span / s <= float(most):
			return s
	return 600.0


# Round "m:ss" labels with small ticks under rect r; the first is left-aligned, one that would
# overflow the right edge is right-aligned.
func _draw_time_axis(r: Rect2, y: float) -> void:
	var font: Font = DB.font_regular
	var step: float = time_step(max_time, r.size.x)
	var t: float = 0.0
	while t <= max_time + 0.001:
		var x: float = _x(t)
		draw_line(Vector2(x, r.end.y), Vector2(x, r.end.y + 4.0), Color(1, 1, 1, 0.2), 1.0)
		var txt: String = UITheme.fmt_time(t)
		var tw: float = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.MIN_FS).x
		var bx: float = x - tw * 0.5
		if t == 0.0:
			bx = x
		elif bx + tw > r.end.x + 8.0:
			bx = r.end.x + 8.0 - tw
		draw_string(font, Vector2(bx, y), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.MIN_FS, UITheme.TEXT_FAINT)
		t += step


static func _spread(items: Array, gap: float, lo: float, hi: float) -> void:
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


func _get_tooltip(at: Vector2) -> String:
	if not _plot.grow(4.0).has_point(at) or samples.is_empty():
		return ""
	var t: float = clampf((at.x - _plot.position.x) / maxf(1.0, _plot.size.x), 0.0, 1.0) * max_time
	var line: String = "%s · 생존 영웅 %d" % [UITheme.fmt_time(t), count_at(t, 1)]
	if show_teams():
		line += " · 팀 %d" % count_at(t, 2)
	var best: Dictionary = {}
	var best_d: float = 8.0
	for e in events:
		var dx: float = absf(_x(float(e.get("t", 0.0))) - at.x)
		if dx < best_d:
			best_d = dx
			best = e
	if not best.is_empty():
		var kinds: Dictionary = {"kill": "처치", "knock": "다운", "team_out": "팀 탈락"}
		var detail: String = str(best.get("text", kinds.get(str(best.get("kind", "")), "")))
		line += "\n%s %s" % [UITheme.fmt_time(float(best.get("t", 0.0))), detail]
	return UITheme.tip(line)
