class_name TeamChip
extends Button
## Battleground top-bar team chip: a team-colour cap with the team label ("3팀" / "P7") over one
## 26 px member disc per hero and a status line under each disc (HP bar, or the bleed-out timer).
## A downed member pulses with a red ring that runs down with the bleed timer (a green ring and
## "소생" while a teammate revives it), a dead member dims under a cross, and an eliminated team
## greys out and shows its place ("4위") in the cap.
## Widths follow the team size: solo 36, duo 56, trio 86 (width_for); height 58.
## Custom drawn with shared StyleBoxes; set_data() redraws only when something visible changed, and
## only a chip with a downed member animates. Mode-independent: it never reads the simulation.
##
## Input: set_data(d), field names as in DESIGN_V2 §3.5 (BattlegroundMode):
##   label: String        team_label(team) — "3팀", solo "P7"
##   color: Color         UITheme.team_color(team)
##   members: Array       one Dictionary per hero, in player order:
##     glyph: String        hero glyph (CharDef.glyph)
##     color: Color         hero accent (CharDef.accent)
##     state: String        "alive" | "downed" | "dead"
##     hp: float            alive: HP ratio 0..1; below 0 = unknown in this perspective
##     downed_left: float   downed: seconds until bleed-out (downed_info.bleed_at - sim.time)
##     downed_total: float  optional: this downing's bleed window (30 / 20 / 10 s), default 30
##     revive: float        optional: downed_info.revive_progress 0..1 (0 = nobody reviving)
##     name: String         optional: hero name for the tooltip
##   eliminated: bool     team is out (placement.has(team))
##   place: int           placement[team] (1 = winner), shown when eliminated
##   selected: bool       optional: highlighted frame (the followed team)

const H: = 58.0
const WIDTHS: = [36.0, 56.0, 86.0]
const SLOT: = 26.0
const DISC_R: = 11.0
const CAP_H: = 15.0
const DISC_Y: = 33.0
const BAR_Y: = 49.0
const BLEED_DEFAULT: = 30.0

var label_text: String = ""
var color: Color = UITheme.BLUE
var members: Array = []
var eliminated: bool = false
var place: int = 0
var selected: bool = false

var _key: PackedFloat32Array = PackedFloat32Array()
var _pulse: float = 0.0
var _any_downed: bool = false

# Cap StyleBoxes (top corners rounded) per colour, shared by every chip.
static var _caps: Dictionary = {}


func _init() -> void:
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	custom_minimum_size = Vector2(WIDTHS[0], H)
	var empty: = StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		add_theme_stylebox_override(st, empty)
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	set_process(false)


## Chip width for a team of n heroes (1 → 36, 2 → 56, 3 → 86).
static func width_for(n: int) -> float:
	return WIDTHS[clampi(n, 1, WIDTHS.size()) - 1]


func set_data(d: Dictionary) -> void:
	label_text = str(d.get("label", ""))
	color = _col(d.get("color"), UITheme.BLUE)
	members = d.get("members", [])
	eliminated = bool(d.get("eliminated", false))
	place = int(d.get("place", 0))
	selected = bool(d.get("selected", false))
	var w: float = width_for(members.size())
	if not is_equal_approx(custom_minimum_size.x, w):
		custom_minimum_size = Vector2(w, H)
	_any_downed = false
	var k: = PackedFloat32Array([color.r, color.g, color.b, 1.0 if eliminated else 0.0, float(place), 1.0 if selected else 0.0, float(label_text.hash())])
	for m in members:
		var st: String = str(m.get("state", "alive"))
		k.append(float(["alive", "downed", "dead"].find(st)))
		k.append(snappedf(float(m.get("hp", 1.0)), 0.02))
		if st == "downed":
			_any_downed = true
			k.append(ceilf(float(m.get("downed_left", 0.0))))
			k.append(snappedf(float(m.get("revive", 0.0)), 0.02))
	set_process(_any_downed and not eliminated and is_visible_in_tree())
	if k != _key:
		_key = k
		tooltip_text = _tooltip()
		queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED or what == NOTIFICATION_ENTER_TREE:
		set_process(_any_downed and not eliminated and is_visible_in_tree())


func _process(delta: float) -> void:
	_pulse = fmod(_pulse + delta, TAU)
	queue_redraw()


func _tooltip() -> String:
	var parts: PackedStringArray = []
	for m in members:
		var nm: String = str(m.get("name", m.get("glyph", "")))
		match str(m.get("state", "alive")):
			"downed":
				var rv: float = float(m.get("revive", 0.0))
				parts.append("%s (다운 · 출혈 %d초%s)" % [nm, int(ceilf(float(m.get("downed_left", 0.0)))), (" · 소생 %d%%" % int(rv * 100.0)) if rv > 0.0 else ""])
			"dead":
				parts.append("%s (사망)" % nm)
			_:
				parts.append(nm)
	var head: String = ("%s · %d위 탈락" % [label_text, place]) if eliminated else label_text
	return UITheme.tip("%s — %s" % [head, ", ".join(parts)]) if not parts.is_empty() else head


## Colour from a Color or an html string (data files), else fallback.
static func _col(v: Variant, fallback: Color) -> Color:
	if v is Color:
		return v
	if v is String and Color.html_is_valid(v):
		return Color.html(v)
	return fallback


static func _cap_style(col: Color) -> StyleBoxFlat:
	var key: = col.to_html()
	var s: StyleBoxFlat = _caps.get(key)
	if s == null:
		s = UITheme.sb(col, UITheme.CLEAR, 0, 0, 0, 0)
		s.corner_radius_top_left = UITheme.R_S
		s.corner_radius_top_right = UITheme.R_S
		_caps[key] = s
	return s


## Centre of member k's disc (slots of 26 px, spread over the chip width).
func disc_center(k: int) -> Vector2:
	var n: int = maxi(1, members.size())
	var w: float = width_for(n)
	var gap: float = (w - 4.0 - SLOT * n) / float(n - 1) if n > 1 else 0.0
	var x0: float = (w - SLOT * n - gap * (n - 1)) * 0.5
	return Vector2(x0 + SLOT * 0.5 + k * (SLOT + gap), DISC_Y)


func _draw() -> void:
	var w: float = size.x
	var tc: Color = color
	var hover: bool = is_hovered()
	var rect: = Rect2(Vector2.ZERO, size)
	if eliminated:
		var dim_edge: Color = UITheme.TEXT_DIM if selected else Color(UITheme.LINE2, 0.7 if hover else 0.45)
		draw_style_box(UITheme.sbc(Color(1, 1, 1, 0.025), dim_edge, UITheme.R_S, 2 if selected else 1, 0), rect)
		draw_style_box(_cap_style(Color("#2a3247")), Rect2(1, 1, w - 2, CAP_H))
	else:
		var edge: float = 0.95 if selected else (0.8 if hover else 0.5)
		draw_style_box(UITheme.sbc(Color(tc, 0.12 if hover else 0.08), Color(tc, edge), UITheme.R_S, 2 if selected else 1, 0), rect)
		draw_style_box(_cap_style(tc), Rect2(1, 1, w - 2, CAP_H))
	var cap: String = label_text
	var ink: Color = UITheme.BG if tc.get_luminance() > 0.5 else Color.WHITE
	if eliminated:
		cap = ("%d위" % place) if w < 70.0 or label_text == "" else "%d위 · %s" % [place, label_text]
		ink = UITheme.TEXT_DIM
	var f: Font = DB.font_bold
	var fs: int = UITheme.MIN_FS
	cap = UITheme.fit_text(f, cap, fs, w - 4.0)
	draw_string(f, Vector2(0, 12.5), cap, HORIZONTAL_ALIGNMENT_CENTER, w, fs, ink)
	var pulse: float = 0.5 + 0.5 * sin(_pulse * 4.0)
	for k in members.size():
		_draw_member(members[k], disc_center(k), pulse)


func _draw_member(m: Dictionary, c: Vector2, pulse: float) -> void:
	var st: String = str(m.get("state", "alive"))
	var acc: Color = _col(m.get("color"), UITheme.ACCENT)
	var glyph: String = str(m.get("glyph", "?"))
	var r: float = DISC_R
	var gf: Font = DB.font_glyph
	var gs: int = 13 if glyph.length() <= 1 else UITheme.MIN_FS
	var gw: float = gf.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, gs).x
	var gp: = Vector2(c.x - gw * 0.5, c.y + (gf.get_ascent(gs) - gf.get_descent(gs)) * 0.5)
	if eliminated or st == "dead":
		draw_circle(c, r, Color(0.2, 0.22, 0.27), true, -1.0, true)
		draw_arc(c, r, 0, TAU, 32, Color(0.42, 0.45, 0.52, 0.8), 1.2, true)
		draw_string(gf, gp, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, gs, Color(1, 1, 1, 0.3))
		if not eliminated:
			var q: float = r * 0.62
			draw_line(c + Vector2(-q, -q), c + Vector2(q, q), Color(UITheme.BAD, 0.85), 2.0, true)
			draw_line(c + Vector2(q, -q), c + Vector2(-q, q), Color(UITheme.BAD, 0.85), 2.0, true)
		return
	if st == "downed":
		var left: float = maxf(0.0, float(m.get("downed_left", 0.0)))
		var total: float = maxf(1.0, float(m.get("downed_total", BLEED_DEFAULT)))
		var revive: float = clampf(float(m.get("revive", 0.0)), 0.0, 1.0)
		var ring: Color = UITheme.GOOD if revive > 0.0 else UITheme.BAD
		draw_circle(c, r + 3.5, Color(ring, 0.12 + 0.2 * pulse), true, -1.0, true)
		draw_circle(c, r, acc.darkened(0.72), true, -1.0, true)
		draw_string(gf, gp, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, gs, Color(1, 1, 1, 0.7))
		draw_arc(c, r + 1.0, 0, TAU, 32, Color(ring, 0.25), 2.0, true)
		# Bleed-out ring runs down; while a teammate revives, the ring fills green instead.
		var frac: float = revive if revive > 0.0 else clampf(left / total, 0.0, 1.0)
		draw_arc(c, r + 1.0, -PI * 0.5, -PI * 0.5 + TAU * frac, 32, ring.lightened(0.15 * pulse), 2.0, true)
		var txt: String = "소생" if revive > 0.0 else "%d초" % int(ceilf(left))
		var tcol: Color = UITheme.GOOD if revive > 0.0 else (UITheme.WARN if left > 10.0 else UITheme.BAD)
		draw_string(DB.font_bold, Vector2(c.x - SLOT * 0.5 - 2.0, BAR_Y + 7.5), txt, HORIZONTAL_ALIGNMENT_CENTER, SLOT + 4.0, UITheme.MIN_FS, tcol)
		return
	draw_circle(c, r, acc.darkened(0.55), true, -1.0, true)
	draw_circle(c, r * 0.84, acc.darkened(0.3), true, -1.0, true)
	draw_arc(c, r, 0, TAU, 32, color.lightened(0.15), 1.5, true)
	draw_string(gf, gp + Vector2(0, 1), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, gs, Color(0, 0, 0, 0.45))
	draw_string(gf, gp, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, gs, Color.WHITE)
	var hp: float = float(m.get("hp", 1.0))
	var bar: = Rect2(c.x - 10.0, BAR_Y, 20.0, 3.0)
	if hp < 0.0:
		draw_rect(bar, Color(1, 1, 1, 0.18), false, 1.0)
		return
	draw_rect(bar, Color(0, 0, 0, 0.55))
	var hc: Color = UITheme.GOOD if hp > 0.5 else (UITheme.WARN if hp > 0.25 else UITheme.BAD)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(hp, 0.0, 1.0), bar.size.y)), hc)
