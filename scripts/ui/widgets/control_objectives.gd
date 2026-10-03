class_name ControlObjectives
extends Control
## Bottom-centre control-point strip (control mode): one card per point with its owner, a plain
## state line and the capture progress. It redraws only when a point's state changes and draws with
## shared StyleBoxes (UITheme.sbc), so it costs nothing while the map is quiet.

const W: = 480.0
const H: = 56.0
const GAP: = 8.0

var sim: BattleSim:
	set(v):
		sim = v
		_key = PackedFloat32Array()
		queue_redraw()
var _key: PackedFloat32Array = PackedFloat32Array()


func _init() -> void:
	custom_minimum_size = Vector2(W, H)
	mouse_filter = Control.MOUSE_FILTER_PASS
	tooltip_text = UITheme.tip("\n".join(CodexData.rule_lines(CodexData.CONTROL_RULES)))


func _process(_delta: float) -> void:
	if not visible or sim == null or not sim.is_control_mode() or sim.domination == null:
		return
	var k: = PackedFloat32Array()
	for point in sim.domination.points:
		k.append(float(point.get("owner", -1)))
		k.append(1.0 if bool(point.get("contested", false)) else 0.0)
		k.append(snappedf(float(point.get("progress", 0.0)), 0.01))
	if k != _key:
		_key = k
		queue_redraw()


func _draw() -> void:
	if sim == null or not sim.is_control_mode() or sim.domination == null:
		return
	var points: Array = sim.domination.points
	var n: = maxi(1, points.size())
	var width: float = (size.x - GAP * (n - 1)) / float(n)
	for i in points.size():
		var point: Dictionary = points[i]
		var owner: int = int(point.get("owner", -1))
		var contested: bool = bool(point.get("contested", false))
		var progress: float = float(point.get("progress", 0.0))
		var active: bool = absf(progress) > 0.001
		var col: Color = UITheme.team_color(owner) if owner >= 0 else UITheme.TEXT_FAINT
		var accent: Color = UITheme.GOLD if contested else col
		var rect: = Rect2(i * (width + GAP), 0, width, H)
		draw_style_box(UITheme.sbc(Color(0.03, 0.045, 0.07, 0.94), Color(accent, 0.7 if owner >= 0 or contested else 0.45), UITheme.R_M, 1, 0), rect)
		var pos: Vector2 = rect.position
		var c: = pos + Vector2(24, 25)
		draw_circle(c, 15.0, Color(col, 0.22))
		draw_arc(c, 15.0, 0.0, TAU, 40, Color(accent, 0.85), 1.5, true)
		var letter: = str(point.get("id", i + 1))
		var lw: = DB.font_black.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		draw_string(DB.font_black, c + Vector2(-lw * 0.5, 6), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, accent.lightened(0.15))
		var caption: String = "경합 중" if contested else ("%s 거점" % DB.TEAM_NAMES[owner] if owner >= 0 and owner < 2 else "중립 거점")
		var note: String
		if contested:
			note = "양 팀이 있어 정지"
		elif active:
			note = "%s %.1f초" % ["점령 중" if owner < 0 else "중립화 중", (1.0 - absf(progress)) * sim.domination.capture_time]
		elif owner >= 0:
			note = "초당 +%s점 득점 중" % CodexData.num(DominationMode.SCORE_RATE)
		else:
			note = "들어가면 점령 시작"
		var tw: = width - 54.0
		draw_string(DB.font_bold, pos + Vector2(46, 23), UITheme.fit_text(DB.font_bold, caption, 13, tw), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, accent.lightened(0.2) if owner >= 0 or contested else UITheme.TEXT_DIM)
		draw_string(DB.font_regular, pos + Vector2(46, 41), UITheme.fit_text(DB.font_regular, note, 12, tw), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UITheme.TEXT_DIM)
		var y: = H - 6.0
		draw_line(pos + Vector2(10, y), pos + Vector2(width - 10, y), Color(1, 1, 1, 0.07), 3.0)
		if active:
			var progress_col: Color = UITheme.BLUE if progress < 0.0 else UITheme.RED
			draw_line(pos + Vector2(10, y), pos + Vector2(10 + (width - 20) * absf(progress), y), progress_col, 3.0)
