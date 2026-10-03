class_name FxSystem
extends Node2D



const MAX_PARTICLES: = 1400

var quality: int = 2
var time_scale: float = 1.0
var shake: float = 0.0
var shake_dir: Vector2 = Vector2.ZERO


var p_count: int = 0
var p_pos: = PackedVector2Array()
var p_vel: = PackedVector2Array()
var p_life: = PackedFloat32Array()
var p_max: = PackedFloat32Array()
var p_size: = PackedFloat32Array()
var p_drag: = PackedFloat32Array()
var p_grav: = PackedFloat32Array()
var p_col: = PackedColorArray()
var p_shape: = PackedByteArray()

var items: Array = []
static var soft_tex: Texture2D
var texts: Array = []
var text_layer: Node2D

# Readable mode (BattleView.hud_readable, battle screen only): texts are drawn at a legible
# screen size (VfxStyle.hud_px) instead of shrinking with the camera. `hud_scale` is the view
# scale used for sizing (quantised by the view), `inv_scale` converts screen px to world units.
var readable: bool = false
var hud_scale: float = 1.0
var inv_scale: float = 1.0
# World rects of the view's unit labels and hero head stacks (last frame, Rect2 only);
# stacked texts rise above them.
var obstacles: Array = []
const MIN_PX_TEXT: = 13.0
const MIN_PX_NOTE: = 12.0
const MIN_PX_BANNER: = 16.0
const MIN_PX_GLYPH: = 13.0
const MAX_LIFT_PX: = 72.0


func _init() -> void :
	p_pos.resize(MAX_PARTICLES)
	p_vel.resize(MAX_PARTICLES)
	p_life.resize(MAX_PARTICLES)
	p_max.resize(MAX_PARTICLES)
	p_size.resize(MAX_PARTICLES)
	p_drag.resize(MAX_PARTICLES)
	p_grav.resize(MAX_PARTICLES)
	p_col.resize(MAX_PARTICLES)
	p_shape.resize(MAX_PARTICLES)
	var mat: = CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat
	if soft_tex == null:
		soft_tex = make_soft_texture()
	text_layer = Node2D.new()
	text_layer.name = "FxText"
	text_layer.draw.connect(_draw_texts)
	add_child(text_layer)


static func make_soft_texture() -> Texture2D:
	var g: = Gradient.new()
	g.set_offset(0, 0.0)
	g.set_color(0, Color(1, 1, 1, 1))
	g.add_point(0.35, Color(1, 1, 1, 0.75))
	g.add_point(0.7, Color(1, 1, 1, 0.18))
	g.set_offset(g.get_point_count() - 1, 1.0)
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
	var t: = GradientTexture2D.new()
	t.gradient = g
	t.width = 32
	t.height = 32
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	return t


func clear_all() -> void :
	p_count = 0
	items.clear()
	texts.clear()
	shake = 0.0


func qn(n: int) -> int:
	match quality:
		0:
			return maxi(1, floori(n / 4.0))
		1:
			return maxi(1, floori(n / 2.0))
	return n






func particle(pos: Vector2, vel: Vector2, col: Color, size: float, life: float, drag: float = 2.5, grav: float = 0.0, shape: int = 0) -> void :
	var i: = p_count
	if i >= MAX_PARTICLES:

		i = randi() % MAX_PARTICLES
	else:
		p_count += 1
	p_pos[i] = pos
	p_vel[i] = vel
	p_life[i] = life
	p_max[i] = life
	p_size[i] = size
	p_drag[i] = drag
	p_grav[i] = grav
	p_col[i] = col
	p_shape[i] = shape


func burst(pos: Vector2, col: Color, n: int, smin: float, smax: float, size: float, life: float, drag: float = 3.0, grav: float = 0.0, dir: Vector2 = Vector2.ZERO, spread: float = TAU, shape: int = 0) -> void :
	for k in qn(n):
		var ang: = randf() * TAU
		if dir != Vector2.ZERO:
			ang = dir.angle() + (randf() - 0.5) * spread
		var sp: = lerpf(smin, smax, randf())
		var c: = col
		c.a *= lerpf(0.6, 1.0, randf())
		particle(pos + Vector2.from_angle(ang) * randf() * size, Vector2.from_angle(ang) * sp, c, size * lerpf(0.6, 1.3, randf()), life * lerpf(0.7, 1.2, randf()), drag, grav, shape)


func ring(pos: Vector2, col: Color, r0: float, r1: float, life: float, width: float = 3.0, fill: float = 0.0) -> void :
	items.append({"kind": "ring", "pos": pos, "col": col, "r0": r0, "r1": r1, "t": 0.0, "life": life, "w": width, "fill": fill})


func flash(pos: Vector2, col: Color, radius: float, life: float = 0.18) -> void :
	items.append({"kind": "flash", "pos": pos, "col": col, "r": radius, "t": 0.0, "life": life})


func slash(pos: Vector2, dir: Vector2, col: Color, radius: float, arc: float = 2.2, life: float = 0.22, width: float = 5.0) -> void :
	items.append({"kind": "slash", "pos": pos, "dir": dir.normalized() if dir != Vector2.ZERO else Vector2.RIGHT, "col": col, "r": radius, "arc": arc, "t": 0.0, "life": life, "w": width})


func cone(pos: Vector2, dir: Vector2, rng_: float, ang: float, col: Color, life: float = 0.28) -> void :
	items.append({"kind": "cone", "pos": pos, "dir": dir.normalized() if dir != Vector2.ZERO else Vector2.RIGHT, "range": rng_, "ang": ang, "col": col, "t": 0.0, "life": life})


func beam(from: Vector2, to: Vector2, col: Color, width: float = 4.0, life: float = 0.2) -> void :
	items.append({"kind": "beam", "from": from, "to": to, "col": col, "w": width, "t": 0.0, "life": life})


func streak(from: Vector2, to: Vector2, col: Color, width: float = 10.0, life: float = 0.3) -> void :
	items.append({"kind": "streak", "from": from, "to": to, "col": col, "w": width, "t": 0.0, "life": life})


func afterimage(pos: Vector2, radius: float, col: Color, life: float = 0.35) -> void :
	items.append({"kind": "ghost", "pos": pos, "r": radius, "col": col, "t": 0.0, "life": life})


# Jump-pad flight trail: the same arc as the pad preview (ArenaPainter.leap_point),
# drawn up to the flying hero with a glowing head and a closing landing ring.
func leap(from: Vector2, to: Vector2, col: Color, life: float) -> void :
	items.append({"kind": "leap", "from": from, "to": to, "col": col, "t": 0.0, "life": maxf(0.1, life), "h": ArenaPainter.leap_height(from.distance_to(to))})


func tether(from_idx: int, to_idx: int, col: Color, life: float, width: float = 3.0) -> void :
	items.append({"kind": "tether", "a": from_idx, "b": to_idx, "col": col, "t": 0.0, "life": life, "w": width})



func sig(pos: Vector2, id: String, col: Color, radius: float = 30.0, life: float = 0.6) -> void :
	items.append({"kind": "sig", "pos": pos, "id": id, "col": col, "r": radius, "t": 0.0, "life": life, "rot": randf() * TAU})



func passive_pulse(idx: int, motif: String, col: Color, radius: float, life: float = 0.7) -> void :
	items.append({"kind": "ppulse", "idx": idx, "motif": motif, "col": col, "r": radius, "t": 0.0, "life": life})



func motif_fly(pos: Vector2, vel: Vector2, motif: String, col: Color, size: float, life: float = 0.6, spin: float = 4.0) -> void :
	items.append({"kind": "mfly", "pos": pos, "vel": vel, "motif": motif, "col": col, "r": size, "t": 0.0, "life": life, "spin": spin, "rot": randf() * TAU})



func glyph(pos: Vector2, g: String, col: Color, size: float = 26.0, life: float = 0.7, stack: bool = true) -> void :
	_add_text({"kind": "glyph", "pos": pos, "text": g, "col": col, "size": size, "t": 0.0, "life": life, "rise": 26.0, "stack": stack,
		"minpx": MIN_PX_GLYPH + maxf(0.0, size - 16.0) * 0.4}, DB.font_glyph)


func text(pos: Vector2, s: String, col: Color, size: float = 16.0, life: float = 0.9, rise: float = 34.0, bold: bool = true, jitter: bool = true) -> void :

	var off: = Vector2(randf_range(-8, 8), 0.0) if jitter else Vector2.ZERO
	# Minimum screen size grows a little with the requested size so big hits still read bigger.
	var mn: = (MIN_PX_TEXT + maxf(0.0, size - 14.0) * 0.4) if bold else (MIN_PX_NOTE + maxf(0.0, size - 12.0) * 0.4)
	_add_text({"kind": "text", "pos": pos + off, "text": s, "col": col, "size": size, "t": 0.0, "life": life, "rise": rise, "bold": bold, "minpx": mn}, DB.font_black if bold else DB.font_bold)


func banner(pos: Vector2, s: String, col: Color, size: float = 20.0, life: float = 1.4) -> void :
	_add_text({"kind": "banner", "pos": pos, "text": s, "col": col, "size": size, "t": 0.0, "life": life, "rise": 12.0,
		"minpx": MIN_PX_BANNER + maxf(0.0, size - 18.0) * 0.4}, DB.font_black)


func _add_text(tx: Dictionary, font: Font) -> void :
	tx["w"] = font.get_string_size(str(tx.text), HORIZONTAL_ALIGNMENT_LEFT, -1, int(tx.size)).x if font else float(tx.size) * str(tx.text).length()
	tx["lift"] = 0.0
	tx["lift_v"] = 0.0
	tx["font"] = font
	tx["px"] = -1
	tx["wpx"] = 0.0
	texts.append(tx)
	if texts.size() > 90:
		texts.pop_front()


## Readable mode: screen px for a text (0 = draw at world size, e.g. when it is already large on
## screen). The measured width is cached on the text and refreshed only when the size changes.
func _px_for(tx: Dictionary) -> int:
	var sz: float = tx.size
	if sz * hud_scale > 28.5:
		return 0
	var px: = VfxStyle.hud_px(sz, hud_scale, float(tx.minpx))
	if px != int(tx.px):
		tx.px = px
		var f: Font = tx.font
		tx.wpx = f.get_string_size(str(tx.text), HORIZONTAL_ALIGNMENT_LEFT, -1, px).x if f else float(px) * str(tx.text).length()
	return px


## Rise distance in world units: readable texts rise at least ~3/4 of their world rise in screen px.
func _rise(tx: Dictionary) -> float:
	var rise: float = tx.rise
	if readable:
		return maxf(rise, rise * 0.75 * inv_scale)
	return rise




func _layout_texts(delta: float) -> void :
	var placed: Array = []
	var follow: = 1.0 - exp( - delta * 18.0)
	for i in range(texts.size() - 1, -1, -1):
		var tx: Dictionary = texts[i]
		if not bool(tx.get("stack", true)):
			continue
		var r: = _text_rect(tx)
		for guard in 10:
			var bump: = 0.0
			for pr in placed:
				if (pr as Rect2).intersects(r):
					bump = maxf(bump, r.end.y - (pr as Rect2).position.y + 1.0)
			if readable:
				for ob: Rect2 in obstacles:
					if ob.intersects(r):
						bump = maxf(bump, r.end.y - ob.position.y + 1.0)
			if bump <= 0.0:
				break
			tx.lift = float(tx.lift) + bump
			r.position.y -= bump
		placed.append(r)
		tx.lift_v = lerpf(float(tx.lift_v), float(tx.lift), follow) if delta > 0.0 else float(tx.lift_v)



func _text_rect(tx: Dictionary) -> Rect2:
	var k: float = tx.t / tx.life
	var sz: float = tx.size
	var base_y: float = float(tx.pos.y) - _rise(tx) * (1.0 - pow(1.0 - k, 2.0)) - float(tx.lift)
	var w: float = tx.get("w", sz * 2.0)
	if readable:
		var px: = _px_for(tx)
		if px > 0:
			# Screen-sized box with ~2 px of breathing room between stacked texts.
			var h: = (px + 3.0) * inv_scale
			w = (float(tx.wpx) + 4.0) * inv_scale
			return Rect2(float(tx.pos.x) - w * 0.5, base_y - (px * 0.86 + 1.5) * inv_scale, w, h)
	return Rect2(float(tx.pos.x) - w * 0.5 - 1.0, base_y - sz * 0.82, w + 2.0, sz * 0.98)


func add_shake(amount: float) -> void :
	shake = minf(18.0, shake + amount)






func step(delta: float) -> void :
	var dt: = delta * time_scale
	var i: = 0
	while i < p_count:
		p_life[i] -= dt
		if p_life[i] <= 0.0:
			p_count -= 1
			if i != p_count:
				p_pos[i] = p_pos[p_count]
				p_vel[i] = p_vel[p_count]
				p_life[i] = p_life[p_count]
				p_max[i] = p_max[p_count]
				p_size[i] = p_size[p_count]
				p_drag[i] = p_drag[p_count]
				p_grav[i] = p_grav[p_count]
				p_col[i] = p_col[p_count]
				p_shape[i] = p_shape[p_count]
			continue
		var v: = p_vel[i]
		v *= maxf(0.0, 1.0 - p_drag[i] * dt)
		v.y += p_grav[i] * dt
		p_vel[i] = v
		p_pos[i] += v * dt
		i += 1
	var keep: Array = []
	for it in items:
		it.t += dt
		if it.t < it.life:
			keep.append(it)
	items = keep
	var keep_t: Array = []
	for tx in texts:
		tx.t += delta
		if tx.t < tx.life:
			keep_t.append(tx)
	texts = keep_t
	_layout_texts(delta)
	shake = maxf(0.0, shake - delta * (8.0 + shake * 4.0))
	queue_redraw()
	text_layer.queue_redraw()


var unit_pos_cb: Callable


func _draw() -> void :

	for it in items:
		var k: float = it.t / it.life
		match str(it.kind):
			"ring":
				var r: = lerpf(it.r0, it.r1, 1.0 - pow(1.0 - k, 2.2))
				var a: = (1.0 - k)
				var c: Color = it.col
				if it.fill > 0.0:
					draw_circle(it.pos, r, Color(c, c.a * a * it.fill))
				draw_arc(it.pos, r, 0, TAU, 72, Color(c, c.a * a), maxf(1.0, it.w * (1.0 - k * 0.6)), true)
			"flash":
				var c2: Color = it.col
				var a2: = 1.0 - k
				var r2: float = it.r * (0.7 + 0.5 * k)
				draw_texture_rect(soft_tex, Rect2(it.pos - Vector2(r2, r2), Vector2(r2, r2) * 2.0), false, Color(c2, 0.55 * a2))
				draw_texture_rect(soft_tex, Rect2(it.pos - Vector2(r2, r2) * 0.4, Vector2(r2, r2) * 0.8), false, Color(c2.r * 1.5, c2.g * 1.5, c2.b * 1.5, 0.9 * a2))
			"slash":
				var dir: Vector2 = it.dir
				var sweep: = clampf(k * 1.6, 0.0, 1.0)
				var arc: float = it.arc
				var start: = dir.angle() - arc * 0.5
				var end: = start + arc * sweep
				var fade: = 1.0 - clampf((k - 0.45) / 0.55, 0.0, 1.0)
				var c3: Color = it.col
				for layer in 3:
					var rr: float = it.r * (1.0 - layer * 0.08)
					draw_arc(it.pos, rr, maxf(start, end - arc * 0.7), end, 24, Color(c3.r * (1.0 + layer * 0.3), c3.g * (1.0 + layer * 0.3), c3.b * (1.0 + layer * 0.3), (0.5 - layer * 0.12) * fade), it.w * (1.0 - layer * 0.3), true)
			"cone":
				var c4: Color = it.col
				var a4: = (1.0 - k) * 0.35
				var pts: = PackedVector2Array([it.pos])
				var dirc: Vector2 = it.dir
				var n: = 14
				var rng_: float = it.range * (0.6 + 0.4 * minf(1.0, k * 3.0))
				for j in n + 1:
					var ang: float = dirc.angle() - it.ang * 0.5 + it.ang * j / n
					pts.append(it.pos + Vector2.from_angle(ang) * rng_)
				draw_colored_polygon(pts, Color(c4, a4))
				draw_arc(it.pos, rng_, dirc.angle() - it.ang * 0.5, dirc.angle() + it.ang * 0.5, 16, Color(c4.r * 1.4, c4.g * 1.4, c4.b * 1.4, a4 * 2.2), 2.5, true)
			"beam":
				var c5: Color = it.col
				var a5: = 1.0 - k
				draw_line(it.from, it.to, Color(c5, 0.25 * a5), it.w * 3.0, true)
				draw_line(it.from, it.to, Color(c5.r * 1.6, c5.g * 1.6, c5.b * 1.6, 0.9 * a5), maxf(1.0, it.w * (1.0 - k * 0.5)), true)
			"streak":
				var c6: Color = it.col
				var a6: = 1.0 - k
				var from: Vector2 = it.from
				var to: Vector2 = it.to
				var mid: = from.lerp(to, clampf(k * 2.0, 0.0, 1.0))
				draw_line(mid, to, Color(c6, 0.35 * a6), it.w, true)
				draw_line(mid, to, Color(c6.r * 1.5, c6.g * 1.5, c6.b * 1.5, 0.7 * a6), it.w * 0.35, true)
			"leap":
				var lf: Vector2 = it.from
				var lt: Vector2 = it.to
				var lh: float = it.h
				var lc: Color = it.col
				var prev: Vector2 = lf
				for j in range(1, 21):
					var kk: float = float(j) / 20.0
					if kk > k:
						break
					var q: Vector2 = ArenaPainter.leap_point(lf, lt, kk, lh)
					var ta: float = clampf(1.0 - (k - kk) * 2.2, 0.0, 1.0)
					draw_line(prev, q, Color(lc, 0.8 * ta), 3.0, true)
					prev = q
				var head: Vector2 = ArenaPainter.leap_point(lf, lt, k, lh)
				draw_texture_rect(soft_tex, Rect2(head - Vector2(18, 18), Vector2(36, 36)), false, Color(lc, 0.55))
				draw_arc(lt, 8.0 + 22.0 * (1.0 - k), 0, TAU, 32, Color(lc, 0.35 + 0.55 * k), 2.0, true)
			"ghost":
				var c7: Color = it.col
				var a7: = (1.0 - k) * 0.45
				draw_circle(it.pos, it.r, Color(c7, a7 * 0.5))
				draw_arc(it.pos, it.r, 0, TAU, 32, Color(c7, a7), 2.0, true)
			"tether":
				if unit_pos_cb.is_valid():
					var pa: Vector2 = unit_pos_cb.call(int(it.a))
					var pb: Vector2 = unit_pos_cb.call(int(it.b))
					if pa != Vector2.INF and pb != Vector2.INF:
						var c8: Color = it.col
						var a8: = minf(1.0, (1.0 - k) * 3.0)
						draw_chain(self, pa, pb, c8, a8, it.w)
			"sig":
				var fs: = 1.0 - k
				var cs: Color = it.col
				Motifs.signature(self, str(it.id), it.pos, float(it.rot) + k * 0.6, float(it.r) * (0.45 + k * 0.6), Color(cs, 0.9 * fs), k * 2.0)
				draw_arc(it.pos, float(it.r) * (0.6 + k * 0.7), 0.2, 5.7, 32, Color(cs, 0.35 * fs), 1.2, true)
			"ppulse":
				if unit_pos_cb.is_valid():
					var pp: Vector2 = unit_pos_cb.call(int(it.idx))
					if pp != Vector2.INF:
						_passive_pulse(pp, str(it.motif), float(it.r), it.col, k)
			"mfly":
				var fm: Vector2 = it.pos + (it.vel as Vector2) * it.t * (1.0 - k * 0.5)
				var cm: Color = it.col
				Motifs.draw(self, str(it.motif), fm, float(it.rot) + float(it.spin) * it.t, float(it.r), Color(cm, cm.a * (1.0 - k)), Color(cm.lightened(0.5), 1.0 - k), it.t)

	for i in p_count:
		var lf: = p_life[i] / p_max[i]
		var c9: = p_col[i]
		c9.a *= clampf(lf * 1.4, 0.0, 1.0)
		var sz: = p_size[i] * (0.4 + 0.6 * lf)
		match p_shape[i]:
			1:
				var v: = p_vel[i]
				var tail: = v * 0.045
				draw_line(p_pos[i], p_pos[i] - tail, c9, maxf(1.0, sz * 0.7), false)
			2:
				draw_rect(Rect2(p_pos[i] - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), c9)
			_:
				var rr: = sz * 1.8
				draw_texture_rect(soft_tex, Rect2(p_pos[i] - Vector2(rr, rr), Vector2(rr, rr) * 2.0), false, c9)


func draw_chain(ci: CanvasItem, a: Vector2, b: Vector2, c: Color, alpha: float, w: float) -> void :
	var d: = b - a
	var len_: = d.length()
	if len_ < 2.0:
		return
	ci.draw_line(a, b, Color(c, 0.25 * alpha), w * 2.6, true)
	var n: = int(len_ / 14.0)
	var dir: = d / len_
	for k in n:
		var p: = a + dir * (k + 0.5) * len_ / maxf(1, n)
		ci.draw_circle(p, w * 0.7, Color(c.r * 1.4, c.g * 1.4, c.b * 1.4, 0.8 * alpha))


func _draw_texts() -> void :
	var transformed: = false
	for tx in texts:
		var k: float = tx.t / tx.life
		var c: Color = tx.col
		var pos: Vector2 = tx.pos - Vector2(0, _rise(tx) * (1.0 - pow(1.0 - k, 2.0)) + float(tx.get("lift_v", 0.0)))
		var sz: float = tx.size
		var px: = _px_for(tx) if readable else 0
		var fade: = 1.0
		if px > 0:
			# Busy fights: texts pushed far up the stack fade out instead of building a tower.
			var over: = float(tx.get("lift_v", 0.0)) / inv_scale - MAX_LIFT_PX
			if over > 0.0:
				fade = clampf(1.0 - over / 24.0, 0.0, 1.0)
				if fade <= 0.01:
					continue
		match str(tx.kind):
			"glyph":
				var pop: = 1.0 + 0.5 * maxf(0.0, 1.0 - k * 5.0)
				var a: = 1.0 - maxf(0.0, (k - 0.6) / 0.4)
				if px > 0:
					_centered_px(tx, pos, px, pop, Color(c, a * fade))
					transformed = true
				else:
					_centered(DB.font_glyph, pos, str(tx.text), int(sz * pop), Color(c, a), true)
			"banner":
				var a2: = minf(1.0, k * 6.0) * (1.0 - maxf(0.0, (k - 0.75) / 0.25))
				if px > 0:
					_centered_px(tx, pos, px, 1.0, Color(c, a2 * fade))
					transformed = true
				else:
					_centered(DB.font_black, pos, str(tx.text), int(sz), Color(c, a2), true)
			_:
				var pop2: = 1.0 + 0.35 * maxf(0.0, 1.0 - k * 6.0)
				var a3: = 1.0 - maxf(0.0, (k - 0.55) / 0.45)
				if px > 0:
					_centered_px(tx, pos, px, pop2, Color(c, a3 * fade))
					transformed = true
				else:
					_centered(DB.font_black if tx.get("bold", true) else DB.font_bold, pos, str(tx.text), int(sz * pop2), Color(c, a3), true)
	if transformed:
		text_layer.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _centered(font: Font, pos: Vector2, s: String, size: int, col: Color, outline: bool) -> void :
	var w: = font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var p: = Vector2(pos.x - w * 0.5, pos.y)
	if outline:
		text_layer.draw_string_outline(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, maxi(2, floori(size / 6.0)), Color(0, 0, 0, col.a * 0.85))
	text_layer.draw_string(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


## Readable mode: draws at a fixed screen size `px`; the pop animation scales the quad instead of
## changing the font size, so no new glyph sizes are rasterised while texts animate.
func _centered_px(tx: Dictionary, pos: Vector2, px: int, pop: float, col: Color) -> void :
	var f: Font = tx.font
	var s: = str(tx.text)
	var k: = inv_scale * pop
	text_layer.draw_set_transform(pos, 0.0, Vector2(k, k))
	var p: = Vector2(float(tx.wpx) * -0.5, 0.0)
	text_layer.draw_string_outline(f, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, 3 if px >= 14 else 2, Color(0, 0, 0, col.a * 0.85))
	text_layer.draw_string(f, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)



func _passive_pulse(p: Vector2, m: String, r: float, co: Color, k: float) -> void :
	var f: = 1.0 - k
	var rr: = r + 7.0 + 6.0 * k
	var hi: = co.lightened(0.5)
	var c: = Color(co, co.a * f)
	var h: = Color(hi, f)
	match m:
		"triple", "reactor", "shards":
			var count: = 3 if m == "triple" else (6 if m == "reactor" else 4)
			for i in count:
				var a: = TAU * i / count - PI * 0.5
				draw_colored_polygon(Motifs.ngon(3.6, 4, a + 0.4, p + Vector2.from_angle(a) * rr), h if i % 2 == 0 else c)
		"regen", "bank", "aegis", "lifesteal":
			for sg: float in [-1.0, 1.0]:
				var cp: = p + Vector2(sg * (r + 4.0), -5.0 - k * 9.0)
				draw_line(cp - Vector2(3, 0), cp + Vector2(3, 0), c, 2.0, true)
				draw_line(cp - Vector2(0, 3), cp + Vector2(0, 3), c, 2.0, true)
			draw_arc(p, rr, 0.3, PI - 0.3, 16, Color(co, 0.7 * f), 1.4, true)
		"hourglass":
			var hp: = p + Vector2(0, - r - 10.0)
			var tp: = PackedVector2Array()
			for q: Vector2 in [Vector2(-5, -6), Vector2(5, -6), Vector2(-5, 6), Vector2(5, 6), Vector2(-5, -6)]:
				tp.append(hp + q.rotated(k * PI))
			draw_polyline(tp, c, 1.7, true)
		"reticle", "neural":
			for i in 4:
				var a2: = i * TAU / 4.0
				draw_arc(p, rr, a2 + 0.15, a2 + 0.55, 6, Color(co, 0.8 * f), 1.8, true)
		"fish", "borrow":
			Motifs.draw(self, "fish" if m == "fish" else "feather", p + Vector2(0, - r - 12.0 - k * 6.0), 0.0, 5.0 if m != "fish" else 1.0, c, h, 0.0)
		"growth":
			for i in 3:
				draw_colored_polygon(Motifs.ngon(2.6, 4, 0.0, p + Vector2((i - 1) * 7.0, - r - 5.0 - k * 9.0)), c)
		"confusion", "plague":
			for i in 4:
				var a3: = i * TAU / 4.0 + k * 0.4
				Motifs.outline(self, Motifs.ngon(2.8, 6 if m == "plague" else 4, 0.0, p + Vector2.from_angle(a3) * rr), c, 1.3)
		"reflect", "helmet", "styx":
			Motifs.outline(self, Motifs.ngon(rr, 6, PI / 6.0, p), c, 2.0)
		# V2 passives: hades (souls drawn in), war machine (fuel pips), torquemada (cross).
		"kynee":
			for i in 5:
				var a5: = TAU * i / 5.0 + k * 1.2
				draw_circle(p + Vector2.from_angle(a5) * rr * (1.0 - k * 0.5), 2.2 * f + 0.6, h if i % 2 == 0 else c)
		"fuel":
			for i in 5:
				var a6: = PI * 0.25 + (i + 0.5) / 5.0 * PI * 0.5
				draw_arc(p, rr, a6 - 0.08, a6 + 0.08, 4, h, 3.0, true)
		"faith":
			var cp2: = p + Vector2(0, - r - 9.0 - k * 6.0)
			draw_line(cp2 - Vector2(0, 6), cp2 + Vector2(0, 6), h, 2.0, true)
			draw_line(cp2 + Vector2(-4, -2), cp2 + Vector2(4, -2), h, 2.0, true)
		_:
			var count2: = 2 if m == "wings" or m == "talaria" else 3
			for i in count2:
				var a4: = i * TAU / count2 + PI * 0.25
				draw_arc(p, rr + i * 2.0, a4 + k * 0.5, a4 + k * 0.5 + 0.9, 8, Color(co, 0.7 * f), 1.8, true)
