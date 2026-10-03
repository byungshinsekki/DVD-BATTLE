class_name GlyphDisc
extends Control
## Character portrait disc: layered accent disc + CJK glyph. With set_state() it shows an HP ring
## (and shield arc); otherwise a team/accent rim. def == null draws an empty "+" slot.
## API: _init(def, px, team), set_def(def, team), set_state(hp, shield, dead), highlight, glyph_override.


var def: Defs.CharDef
var team: int = -1
var hp_ratio: float = -1.0
var shield_ratio: float = 0.0
var dead: bool = false
var highlight: bool = false
var glyph_override: String = ""


func _init(d: Defs.CharDef = null, px: float = 48.0, t: int = -1) -> void :
	def = d
	team = t
	custom_minimum_size = Vector2(px, px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_def(d: Defs.CharDef, t: int = -1) -> void :
	def = d
	team = t
	queue_redraw()


func set_state(hp: float, shield: float, is_dead: bool) -> void :
	if absf(hp - hp_ratio) > 0.002 or absf(shield - shield_ratio) > 0.002 or is_dead != dead:
		hp_ratio = hp
		shield_ratio = shield
		dead = is_dead
		queue_redraw()


func _draw() -> void :
	var s: = minf(size.x, size.y)
	var c: = size * 0.5
	var r: = s * 0.5 - 2.0
	if def == null:
		draw_circle(c, r, Color(1, 1, 1, 0.04))
		draw_arc(c, r, 0, TAU, 48, Color(1, 1, 1, 0.14), 1.5, true)
		var f: = DB.font_bold
		var fs: = int(s * 0.34)
		draw_string(f, Vector2(0, c.y + fs * 0.35), "+", HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, Color(1, 1, 1, 0.25))
		return
	var acc: = def.accent
	var rim: = UITheme.team_color(team) if team >= 0 else acc.lightened(0.2)
	if dead:
		acc = Color(0.3, 0.32, 0.36)
		rim = Color(0.4, 0.42, 0.46)
	if highlight:
		draw_circle(c, r + 3.0, Color(rim, 0.25))

	draw_circle(c, r, acc.darkened(0.62))
	draw_circle(c, r * 0.86, acc.darkened(0.35))
	draw_circle(c + Vector2( - r * 0.18, - r * 0.22), r * 0.55, Color(acc.lightened(0.25), 0.18))

	var ring_w: = maxf(2.0, s * 0.07)
	if hp_ratio >= 0.0 and not dead:
		draw_arc(c, r - ring_w * 0.5, 0, TAU, 56, Color(0, 0, 0, 0.45), ring_w, true)
		var hc: = UITheme.GOOD if hp_ratio > 0.5 else (UITheme.WARN if hp_ratio > 0.25 else UITheme.BAD)
		draw_arc(c, r - ring_w * 0.5, - PI * 0.5, - PI * 0.5 + TAU * clampf(hp_ratio, 0.0, 1.0), 56, hc, ring_w, true)
		if shield_ratio > 0.01:
			draw_arc(c, r + 1.5, - PI * 0.5, - PI * 0.5 + TAU * clampf(shield_ratio, 0.0, 1.0), 48, Color(0.95, 0.97, 1.0, 0.9), 2.0, true)
	else:
		draw_arc(c, r, 0, TAU, 56, rim, maxf(1.5, s * 0.045), true)

	var g: = glyph_override if glyph_override != "" else def.glyph
	var font: = DB.font_glyph
	var fsz: = int(s * (0.5 if g.length() <= 1 else 0.34))
	var tw: = font.get_string_size(g, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz).x
	var asc: = font.get_ascent(fsz)
	var desc: = font.get_descent(fsz)
	var pos: = Vector2(c.x - tw * 0.5, c.y + (asc - desc) * 0.5)
	draw_string(font, pos + Vector2(0, 1.5), g, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, Color(0, 0, 0, 0.5))
	draw_string(font, pos, g, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, Color(1, 1, 1, 0.4) if dead else Color.WHITE)
	if dead:
		draw_line(c + Vector2( - r * 0.6, - r * 0.6), c + Vector2(r * 0.6, r * 0.6), Color(1, 0.4, 0.45, 0.8), 2.0, true)
