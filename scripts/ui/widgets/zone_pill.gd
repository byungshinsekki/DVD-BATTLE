class_name ZonePill
extends Control
## Battleground zone timer: what the zone is doing, the countdown to its next change, the damage
## per second outside it and one pip per zone phase. Two layouts chosen by height:
##   full    (FULL_SIZE 480x56, the bottom-centre slot ControlObjectives uses): state title, a line of
##           detail, a large countdown and the phase pips;
##   compact (COMPACT_SIZE 300x30, top bar): one line, e.g. "자기장 2/6 · 수축 0:42 · 2%/s".
## Redraws only when a shown value changes (call set_time() every frame). Mode-independent.
##
## Input: set_view(view) takes BrZone.public_view(t) / BattlegroundMode.zone_view() (DESIGN_V2 §3.3):
##   phase: int          shrinks started so far: 0 while looting, k during shrink k and the wait
##                       after it (the next shrink is phase + 1)
##   phases_total: int   number of shrinks (6)
##   state: String       "loot" | "wait" | "shrink" | "final"
##   t_state_end: float  sim time the current state ends (countdown = t_state_end - now)
##   dps_ratio: float    max-HP fraction per second outside the circle (0.02 = 2%/s)
##   next_known: bool    the next circle has been announced (public)
##   center / radius / next_center / next_radius are not used here (see Minimap.set_zone).
## set_time(now) takes the sim time. text() returns the one-line summary.

const FULL_SIZE: = Vector2(480, 56)
const COMPACT_SIZE: = Vector2(300, 30)
const STATES: = ["loot", "wait", "shrink", "final"]
const TITLES: = {"loot": "약탈 시간", "wait": "자기장 예고", "shrink": "자기장 수축", "final": "최종 자기장"}

var view: Dictionary = {}
var now: float = 0.0
## Compact one-line layout (sets the minimum size; any height below 44 px also draws compact).
var compact: bool = false:
	set(v):
		compact = v
		custom_minimum_size = COMPACT_SIZE if v else FULL_SIZE
		queue_redraw()

var _key: PackedFloat32Array = PackedFloat32Array()


func _init(is_compact: bool = false) -> void:
	compact = is_compact
	mouse_filter = Control.MOUSE_FILTER_PASS


func set_view(v: Dictionary) -> void:
	view = v
	_refresh()


func set_time(t: float) -> void:
	now = t
	_refresh()


func state() -> String:
	var s: String = str(view.get("state", "loot"))
	return s if s in STATES else "loot"


func phase() -> int:
	return int(view.get("phase", 0))


func phases_total() -> int:
	return maxi(1, int(view.get("phases_total", 6)))


## Seconds until the current state ends; -1 when there is no countdown (final, or no end given).
func remaining() -> float:
	var end: float = float(view.get("t_state_end", -1.0))
	if state() == "final" or end < 0.0 or is_inf(end) or is_nan(end):
		return -1.0
	return maxf(0.0, end - now)


## State colour: looting green, announced gold, shrinking amber, final red.
func state_color() -> Color:
	match state():
		"wait":
			return UITheme.GOLD
		"shrink":
			return UITheme.WARN
		"final":
			return UITheme.BAD
	return UITheme.GOOD


## "2%/s", "3.5%/s"; "" when there is no damage.
static func dps_text(ratio: float) -> String:
	if ratio <= 0.0:
		return ""
	var v: float = ratio * 100.0
	return ("%d%%/s" % int(roundf(v))) if absf(v - roundf(v)) < 0.05 else ("%.1f%%/s" % v)


## The one-line summary, e.g. "자기장 2/6 · 수축 0:42 · 2%/s", "자기장 예고 0:15", "약탈 시간 1:05".
func text() -> String:
	var out: = ""
	for seg in _segments():
		out += str(seg[0])
	return out


# [text, font, size, colour] runs of the one-line summary.
func _segments() -> Array:
	var sc: Color = state_color()
	var rem: float = remaining()
	var clock: String = UITheme.fmt_time(rem) if rem >= 0.0 else ""
	var dps: String = dps_text(float(view.get("dps_ratio", 0.0)))
	var b: Font = DB.font_bold
	var k: Font = DB.font_black
	var r: Font = DB.font_regular
	var fs: int = UITheme.FS_CAPTION
	var segs: Array = []
	match state():
		"shrink":
			segs = [["자기장 %d/%d" % [phase(), phases_total()], b, fs, UITheme.TEXT], [" · 수축 ", r, fs, UITheme.TEXT_DIM], [clock, k, 14, sc]]
		"final":
			segs = [["자기장 %d/%d" % [mini(phase(), phases_total()), phases_total()], b, fs, UITheme.TEXT], [" · ", r, fs, UITheme.TEXT_DIM], ["최종", k, 14, sc]]
		_:
			segs = [[str(TITLES[state()]), b, fs, UITheme.TEXT], [" ", r, fs, UITheme.TEXT_DIM], [clock, k, 14, sc]]
	if dps != "":
		segs.append([" · " + dps, r, UITheme.MIN_FS, UITheme.TEXT_DIM])
	return segs


func _refresh() -> void:
	var rem: float = remaining()
	var k: = PackedFloat32Array([float(STATES.find(state())), float(phase()), float(phases_total()),
		ceilf(rem) if rem >= 0.0 else -1.0, 1.0 if bool(view.get("next_known", false)) else 0.0,
		roundf(float(view.get("dps_ratio", 0.0)) * 1000.0), size.x, size.y])
	if k != _key:
		_key = k
		queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	if size.y < 44.0 or compact:
		_draw_compact()
	else:
		_draw_full()


# Pip i: 2 = done, 3 = shrinking now, 1 = announced next, 0 = later.
func _pip_state(i: int) -> int:
	var p: int = phase()
	match state():
		"shrink":
			return 2 if i < p - 1 else (3 if i == p - 1 else 0)
		"final":
			return 2
		"wait", "loot":
			if i < p:
				return 2
			return 1 if i == p and bool(view.get("next_known", false)) else 0
	return 0


func _draw_pips(right: float, y: float, w: float, h: float, gap: float) -> float:
	var n: int = phases_total()
	var sc: Color = state_color()
	var x: float = right - n * w - (n - 1) * gap
	for i in n:
		var r: = Rect2(x + i * (w + gap), y, w, h)
		match _pip_state(i):
			3:
				draw_rect(r, sc)
			2:
				draw_rect(r, Color(UITheme.TEXT_DIM, 0.75))
			1:
				draw_rect(r, Color(sc, 0.18))
				draw_rect(r, Color(sc, 0.9), false, 1.0)
			_:
				draw_rect(r, Color(1, 1, 1, 0.1))
	return x


func _draw_icon(c: Vector2, r: float) -> void:
	var sc: Color = state_color()
	draw_circle(c, r, Color(sc, 0.14), true, -1.0, true)
	draw_arc(c, r, 0, TAU, 40, Color(sc, 0.95), maxf(1.5, r * 0.1), true)
	if state() == "loot" and not bool(view.get("next_known", false)):
		draw_circle(c, maxf(1.5, r * 0.18), Color(sc, 0.9), true, -1.0, true)
		return
	# Next circle: dashed, a little off-centre like a real announcement.
	var nc: = c + Vector2(r * 0.16, -r * 0.1)
	var nr: float = r * (0.0 if state() == "final" else 0.5)
	if nr > 0.0:
		var dashes: int = 8
		for i in dashes:
			var a0: float = TAU * float(i) / dashes
			draw_arc(nc, nr, a0, a0 + TAU / dashes * 0.55, 6, Color(UITheme.TEXT, 0.85), maxf(1.0, r * 0.08), true)
	else:
		draw_circle(c, maxf(1.5, r * 0.22), sc, true, -1.0, true)


func _draw_full() -> void:
	var sc: Color = state_color()
	var w: float = size.x
	var h: float = size.y
	draw_style_box(UITheme.sbc(Color(0.03, 0.045, 0.07, 0.94), Color(sc, 0.7), UITheme.R_M, 1, 0), Rect2(Vector2.ZERO, size))
	_draw_icon(Vector2(28, h * 0.5), 15.0)
	var rem: float = remaining()
	var big: String = UITheme.fmt_time(rem) if rem >= 0.0 else dps_text(float(view.get("dps_ratio", 0.0)))
	var bf: Font = DB.font_black
	var bw: float = bf.get_string_size(big, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
	draw_string(bf, Vector2(w - 16.0 - bw, 29.0), big, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, sc)
	var pips_x: float = _draw_pips(w - 16.0, 39.0, 13.0, 4.0, 3.0)
	var left: float = 54.0
	var title: String = str(TITLES[state()])
	draw_string(DB.font_bold, Vector2(left, 24.0), UITheme.fit_text(DB.font_bold, title, UITheme.FS_BODY, w - left - bw - 28.0),
		HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FS_BODY, UITheme.TEXT)
	var sub: String = _detail()
	draw_string(DB.font_regular, Vector2(left, 43.0), UITheme.fit_text(DB.font_regular, sub, UITheme.MIN_FS, pips_x - left - 12.0),
		HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.MIN_FS, UITheme.TEXT_DIM)


# Second line of the full layout.
func _detail() -> String:
	var p: int = phase()
	var n: int = phases_total()
	var dps: String = dps_text(float(view.get("dps_ratio", 0.0)))
	var out: String = " · 바깥 %s" % dps if dps != "" else ""
	match state():
		"shrink":
			return "%d/%d단계 원으로 줄어드는 중%s" % [p, n, out]
		"wait":
			return "다음 %d/%d단계 원 공개%s" % [mini(p + 1, n), n, out]
		"final":
			return "%d/%d단계 · 안전 지대 없음%s" % [mini(p, n), n, out]
	return ("1/%d단계 원 공개 · 곧 수축" % n) if bool(view.get("next_known", false)) else "자기장 없음 · 아이템을 모으세요"


func _draw_compact() -> void:
	var sc: Color = state_color()
	var h: float = size.y
	draw_style_box(UITheme.sbc(Color(0.03, 0.045, 0.07, 0.94), Color(sc, 0.6), UITheme.R_PILL, 1, 0), Rect2(Vector2.ZERO, size))
	var r: float = clampf(h * 0.3, 5.0, 10.0)
	_draw_icon(Vector2(h * 0.5 + 3.0, h * 0.5), r)
	var x: float = h + 6.0
	var base: float = h * 0.5 + 5.0
	var pip_w: float = 6.0
	var pips_need: float = phases_total() * (pip_w + 2.0) + 10.0
	var right: float = size.x - 12.0
	var text_w: float = 0.0
	for seg in _segments():
		text_w += (seg[1] as Font).get_string_size(str(seg[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, int(seg[2])).x
	var show_pips: bool = x + text_w + pips_need <= right
	var limit: float = right - (pips_need if show_pips else 0.0)
	for seg in _segments():
		var f: Font = seg[1]
		var fs: int = int(seg[2])
		var s: String = UITheme.fit_text(f, str(seg[0]), fs, limit - x)
		if s == "" or x >= limit:
			break
		draw_string(f, Vector2(x, base), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, seg[3])
		x += f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	if show_pips:
		_draw_pips(right, h * 0.5 - 1.5, pip_w, 3.0, 2.0)
