class_name DvdBackground
extends Control
## App backdrop: navy canvas, a faint drifting grid, dust motes and the bouncing "DVD" disc.
## `dim_t` (0..1) is the target prominence of the disc, its glow and the motes (1 on home, low on
## content-heavy screens); `dim` eases toward it. Everything stays quiet enough to sit behind content.


var pos: = Vector2(300, 200)
var vel: = Vector2(74, 52)
var col_i: int = 0
var t: float = 0.0
var motes: Array = []
var flash: float = 0.0
var dim: float = 1.0
var dim_t: float = 1.0
const COLORS: = [Color("#56a7ff"), Color("#ff6d79"), Color("#6fe0a2"), Color("#f4c96b"), Color("#a98cff"), Color("#66d1d8")]
const DISC_R: = 58.0
const GRID_STEP: = 64.0


func _ready() -> void :
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rng: = RandomNumberGenerator.new()
	rng.seed = 42
	# Motes live in normalised coordinates so they cover any window size.
	for i in 46:
		motes.append({"p": Vector2(rng.randf(), rng.randf()), "v": Vector2(rng.randf_range(-8, 8), rng.randf_range(-14, -4)),
			"r": rng.randf_range(0.8, 2.0), "a": rng.randf_range(0.04, 0.17)})


func _process(delta: float) -> void :
	if not is_visible_in_tree():
		return
	var sz: = size
	if sz.x < 2.0 or sz.y < 2.0:
		return
	t += delta
	dim = move_toward(dim, dim_t, delta * 2.0)
	flash = maxf(0.0, flash - delta * 1.5)
	var r: = DISC_R
	pos += vel * delta
	var bounced: = false
	if pos.x < r:
		pos.x = r
		vel.x = absf(vel.x)
		bounced = true
	elif pos.x > sz.x - r:
		pos.x = sz.x - r
		vel.x = - absf(vel.x)
		bounced = true
	if pos.y < r:
		pos.y = r
		vel.y = absf(vel.y)
		bounced = true
	elif pos.y > sz.y - r:
		pos.y = sz.y - r
		vel.y = - absf(vel.y)
		bounced = true
	if bounced:
		col_i = (col_i + 1) % COLORS.size()
		flash = 1.0
	var inv: = Vector2(1.0 / sz.x, 1.0 / sz.y)
	for m in motes:
		m.p += m.v * inv * delta
		if m.p.y < -0.02:
			m.p.y = 1.02
			m.p.x = randf()
		if m.p.x < -0.02:
			m.p.x = 1.02
		elif m.p.x > 1.02:
			m.p.x = -0.02
	queue_redraw()


func _draw() -> void :
	var sz: = size
	draw_rect(Rect2(Vector2.ZERO, sz), UITheme.BG)
	var k: = dim
	var c: Color = COLORS[col_i]

	# Ambient glow that follows the disc (quiet; fades further on content screens).
	var glow: = 0.35 + 0.65 * k
	for j in 5:
		draw_circle(pos, 380.0 - j * 60.0, Color(c, (0.006 + j * 0.0028) * glow))

	var gc: = Color(1, 1, 1, 0.017)
	var x: = fmod(t * 6.0, GRID_STEP)
	while x < sz.x:
		draw_line(Vector2(x, 0), Vector2(x, sz.y), gc, 1.0)
		x += GRID_STEP
	var y: = fmod(t * 4.0, GRID_STEP)
	while y < sz.y:
		draw_line(Vector2(0, y), Vector2(sz.x, y), gc, 1.0)
		y += GRID_STEP

	var ma: = 0.5 + 0.5 * k
	for m in motes:
		draw_circle(m.p * sz, m.r, Color(1, 1, 1, m.a * ma))

	var r: = DISC_R
	draw_circle(pos, r + 10.0 + flash * 14.0, Color(c, (0.045 + flash * 0.08) * k))
	draw_circle(pos, r, Color(c, 0.10 * k))
	draw_arc(pos, r, 0, TAU, 72, Color(c, 0.42 * k), 2.0, true)
	draw_arc(pos, r * 0.62, t * 0.8, t * 0.8 + PI * 1.3, 40, Color(c, 0.26 * k), 2.0, true)
	draw_circle(pos, r * 0.16, Color(UITheme.BG, k))
	draw_arc(pos, r * 0.16, 0, TAU, 24, Color(c, 0.45 * k), 1.5, true)
	var f: = DB.font_black
	var s: = "DVD"
	var w: = f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
	draw_string(f, pos + Vector2( - w * 0.5, 11), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(c, 0.55 * k))

	# Top/bottom vignette.
	for j in 8:
		var h: = 12.0 * (8 - j)
		draw_rect(Rect2(0, 0, sz.x, h), Color(0, 0, 0, 0.05))
		draw_rect(Rect2(0, sz.y - h, sz.x, h), Color(0, 0, 0, 0.05))
