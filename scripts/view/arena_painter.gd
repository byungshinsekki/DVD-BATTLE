class_name ArenaPainter
extends RefCounted

# Arena drawing shared by the battle view (static + per-frame layers), arena
# cards (setup / draft / deathmatch / codex thumbnails) and the developer lab.
#
# Layers (V1.5.3):
#   draw_floor      static: floor, team tint toward each team's spawn centroid,
#                   grid, spawn rings per spawn cluster, brush ground, mud, landmarks.
#   draw_obstacles  static: walls / pillars, low see-through fences (lattice,
#                   hedge), sunken terrain (chasm). Gates are skipped when
#                   skip_gates (the battle draws them each frame from the live
#                   battle-copy state with draw_gates); cards draw them closed.
#   draw_hazards    per frame: every hazard type incl. artillery areas + public
#                   strike telegraphs (ArenaEnv.artillery_state), jump pads with
#                   direction and landing marker, the closing ring.
#   draw_gates      per frame: open / closing warning / closed with countdown.
#   draw_canopy     brush (team modes and the battleground, "수풀") or forest
#                   canopy (deathmatch, "숲").
#   draw_br_zone    per frame (V2 battleground): zone tint, edge and next circle.
# Per-frame paths allocate nothing: clocks are computed inline, countdown text
# comes from a cached string table and ring geometry is cached per radius step.

const INK: = Color(0.024, 0.035, 0.06)
# Neutral caution colour for environment telegraphs (never a team colour).
const ART_COL: = Color("#ffd166")
const GATE_WARN: = Color("#ffb45e")
const GATE_OPEN: = Color("#8fe3a0")
## Environment types this painter draws (hazard arms, mud on the floor, gates,
## brush canopy). tests/render_153 checks every type in the map data is listed.
const DRAWN_TYPES: = ["lava", "spikes", "eruption", "wind", "portal", "haste", "healing_fountain", "gravity", "shockwave",
	"artillery", "jump_pad", "closing_ring", "mud", "gate", "brush"]
const SPAWN_CLUSTER_GAP: = 300.0
const SPAWN_ZONE_PAD: = 46.0

# World-space labels are multiplied by this (battle view: about 1 / view scale)
# so countdowns stay readable when the camera is zoomed out.
static var text_zoom: float = 1.0
static var _tint_tex: ImageTexture = null
static var _geo: Dictionary = {}
static var _ring_cache: Dictionary = {}
static var _tenths: PackedStringArray = PackedStringArray()
static var _ints: PackedStringArray = PackedStringArray()
static var _fountain_keys: Dictionary = {}


static func _p(p: Vector2, s: float, o: Vector2) -> Vector2:
	return p * s + o


static func floor_colors(arena: Arena) -> Dictionary:
	var f: Dictionary = arena.data.get("floor", {})
	return {"base": Color(str(f.get("base", "#071019"))), "blue": Color(str(f.get("blue", "#173f68"))),
		"red": Color(str(f.get("red", "#642b3d"))), "grid": Color(str(f.get("grid", "#9bb5c9")))}


static func _inner(arena: Arena, s: float, o: Vector2) -> Rect2:
	return Rect2(_p(Vector2(arena.min_x, arena.min_y), s, o), Vector2(arena.max_x - arena.min_x, arena.max_y - arena.min_y) * s)


# Cached "12.5" / "37" countdown strings (no per-frame formatting).
static func num_str(v: float) -> String:
	if _tenths.is_empty():
		for i in 100:
			_tenths.append("%.1f" % (float(i) / 10.0))
		for i in 1000:
			_ints.append(str(i))
	if v < 9.95:
		return _tenths[clampi(int(roundf(maxf(0.0, v) * 10.0)), 0, 99)]
	return _ints[clampi(int(ceilf(v)), 0, 999)]


static var _tenths_s: PackedStringArray = PackedStringArray()
static var _ints_s: PackedStringArray = PackedStringArray()


# Same as num_str with the "초" suffix ("4.2초", "38초").
static func sec_str(v: float) -> String:
	if _tenths_s.is_empty():
		for i in 100:
			_tenths_s.append("%.1f초" % (float(i) / 10.0))
		for i in 1000:
			_ints_s.append("%d초" % i)
	if v < 9.95:
		return _tenths_s[clampi(int(roundf(maxf(0.0, v) * 10.0)), 0, 99)]
	return _ints_s[clampi(int(ceilf(v)), 0, 999)]


# Drops the cached geometry and the tint texture (tests, shutdown).
static func release_caches() -> void:
	_geo.clear()
	_ring_cache.clear()
	_fountain_keys.clear()
	_tint_tex = null


# Derived per-arena geometry (spawn clusters, open centre). Keyed by instance id.
static func geometry(arena: Arena) -> Dictionary:
	var key: int = arena.get_instance_id()
	if _geo.has(key):
		return _geo[key]
	if _geo.size() > 32:
		_geo.clear()
		_ring_cache.clear()
	var clusters: Array = [spawn_clusters(arena.spawns.get(0, [])), spawn_clusters(arena.spawns.get(1, []))]
	var bounds: = PackedVector2Array([Vector2(arena.min_x, arena.min_y), Vector2(arena.max_x, arena.min_y), Vector2(arena.max_x, arena.max_y), Vector2(arena.min_x, arena.max_y)])
	for t in 2:
		for cl in clusters[t]:
			cl["zones"] = spawn_zone(cl.points, bounds)
	var g: Dictionary = {"clusters": clusters, "centre_open": _centre_open(arena)}
	_geo[key] = g
	return g


# Groups a team's spawn points into clusters (split / staggered spawns give two).
# [{center: Vector2, radius: float, points: Array[Vector2]}]
static func spawn_clusters(points: Array) -> Array:
	var groups: Array = []
	for p in points:
		var placed: bool = false
		for gr in groups:
			for q in gr:
				if (p as Vector2).distance_to(q) <= SPAWN_CLUSTER_GAP:
					gr.append(p)
					placed = true
					break
			if placed:
				break
		if not placed:
			groups.append([p])
	var out: Array = []
	for gr in groups:
		var c: = Vector2.ZERO
		for q in gr:
			c += q
		c /= float(gr.size())
		var r: float = 0.0
		for q in gr:
			r = maxf(r, c.distance_to(q))
		out.append({"center": c, "radius": maxf(96.0, r + 64.0), "points": gr})
	return out


# Rounded spawn zone around one cluster: the cluster hull grown by
# SPAWN_ZONE_PAD and clipped to the playable bounds (never spills off the map).
# [{poly: PackedVector2Array, loop: PackedVector2Array (closed)}] in world px.
static func spawn_zone(points: Array, bounds: PackedVector2Array) -> Array:
	var pts: = PackedVector2Array()
	for q in points:
		pts.append(q)
	var shapes: Array = []
	if pts.size() >= 3:
		var hull: PackedVector2Array = Geometry2D.convex_hull(pts)
		if hull.size() > 1 and hull[0] == hull[hull.size() - 1]:
			hull.remove_at(hull.size() - 1)
		if hull.size() >= 3 and absf(_poly_area(hull)) > 100.0:
			shapes = Geometry2D.offset_polygon(hull, SPAWN_ZONE_PAD, Geometry2D.JOIN_ROUND)
	if shapes.is_empty() and pts.size() >= 2:
		var a: Vector2 = pts[0]
		var far: Vector2 = a
		for q in pts:
			if a.distance_squared_to(q) > a.distance_squared_to(far):
				far = q
		var axis: Vector2 = (far - a).normalized()
		var order: Array = Array(pts)
		order.sort_custom(func(p1: Vector2, p2: Vector2) -> bool: return (p1 - a).dot(axis) < (p2 - a).dot(axis))
		shapes = Geometry2D.offset_polyline(PackedVector2Array(order), SPAWN_ZONE_PAD, Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND)
	if shapes.is_empty() and pts.size() == 1:
		var circ: = PackedVector2Array()
		for i in 32:
			circ.append(pts[0] + Vector2.from_angle(TAU * float(i) / 32.0) * SPAWN_ZONE_PAD)
		shapes = [circ]
	var out: Array = []
	for sh in shapes:
		for piece in Geometry2D.intersect_polygons(sh, bounds):
			var pv: PackedVector2Array = piece
			if pv.size() < 3:
				continue
			var loop: = pv.duplicate()
			loop.append(pv[0])
			out.append({"poly": pv, "loop": loop})
	return out


static func _poly_area(p: PackedVector2Array) -> float:
	var a: float = 0.0
	for i in p.size():
		var q: Vector2 = p[i]
		var r: Vector2 = p[(i + 1) % p.size()]
		a += q.x * r.y - r.x * q.y
	return a * 0.5


static func _xf(p: PackedVector2Array, s: float, o: Vector2) -> PackedVector2Array:
	if s == 1.0 and o == Vector2.ZERO:
		return p
	var out: = PackedVector2Array()
	out.resize(p.size())
	for i in p.size():
		out[i] = p[i] * s + o
	return out


static func _centre_open(arena: Arena) -> bool:
	var c: Vector2 = arena.center()
	if arena.inside_obstacle(c, 70.0, Arena.MASK_UNITS):
		return false
	for h in arena.hazards:
		if str(h.get("type", "")) == "closing_ring":
			continue
		if Arena.shape_contains(h, c, 60.0):
			return false
	return true


# White radial falloff (alpha only); modulated by the team floor colour.
static func tint_texture() -> ImageTexture:
	if _tint_tex == null:
		var n: int = 96
		var img: Image = Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
		var half: float = float(n) * 0.5
		for y in n:
			for x in n:
				var d: float = Vector2(float(x) + 0.5 - half, float(y) + 0.5 - half).length() / half
				var a: float = 0.0 if d >= 1.0 else 0.62 * pow(1.0 - d, 1.8)
				img.set_pixel(x, y, Color(1, 1, 1, a))
		_tint_tex = ImageTexture.create_from_image(img)
	return _tint_tex


## Brush and mud live in the static floor / canopy layers: drawn while their
## switch and the master "환경 기믹" switch are on. env == null (cards, codex
## thumbnails, previews) draws everything.
static func env_shows(env: ArenaEnv, typ: String) -> bool:
	return env == null or env.type_active(typ)


## The switch state the static floor and canopy layers depend on (master switch,
## brush, mud). The battle view compares it every frame (ints only) and redraws
## those layers only when it changes.
static func static_env_sig(env: ArenaEnv) -> int:
	if env == null:
		return 0
	if not env.enabled:
		return -1
	return env.disabled_mask & (Arena.type_bit("brush") | Arena.type_bit("mud"))


static func draw_floor(ci: CanvasItem, arena: Arena, s: float, o: Vector2, detail: int = 2, env: ArenaEnv = null) -> void :
	if arena.ruleset == "deathmatch":
		_draw_deathmatch_floor(ci, arena, s, o, detail, env)
		return
	if arena.ruleset == "battleground":
		_draw_battleground_floor(ci, arena, s, o, detail, env)
		return
	var fc: = floor_colors(arena)
	var full: = Rect2(o, Vector2(arena.width, arena.height) * s)
	ci.draw_rect(full, fc.base.darkened(0.35))
	var inner: = _inner(arena, s, o)
	ci.draw_rect(inner, fc.base)
	_draw_team_tint(ci, arena, inner, fc)
	var geo: Dictionary = geometry(arena)
	if detail >= 1:
		var step: = 88.0
		var gc: = Color(fc.grid, 0.05 if detail >= 2 else 0.07)
		var x: = arena.min_x + fmod(arena.width * 0.5 - arena.min_x, step)
		while x < arena.max_x:
			ci.draw_line(_p(Vector2(x, arena.min_y), s, o), _p(Vector2(x, arena.max_y), s, o), gc, 1.0)
			x += step
		var y: = arena.min_y + fmod(arena.height * 0.5 - arena.min_y, step)
		while y < arena.max_y:
			ci.draw_line(_p(Vector2(arena.min_x, y), s, o), _p(Vector2(arena.max_x, y), s, o), gc, 1.0)
			y += step
		if bool(geo.centre_open):
			var cc: = _p(arena.center(), s, o)
			ci.draw_arc(cc, 96.0 * s, 0, TAU, 72, Color(fc.grid, 0.11), maxf(1.0, 1.5 * s), true)
			ci.draw_arc(cc, 10.0 * s, 0, TAU, 24, Color(fc.grid, 0.18), maxf(1.0, 1.2 * s), true)
	if env_shows(env, "brush"):
		_draw_brush_floor(ci, arena, s, o)
	else:
		_draw_brush_off(ci, arena, s, o)
	_draw_mud(ci, arena, s, o, detail, env_shows(env, "mud"))
	_draw_spawns(ci, arena, s, o, detail, fc, geo)
	ci.draw_rect(inner, Color(fc.grid, 0.28), false, maxf(1.0, 2.0 * s))
	_draw_landmarks(ci, arena, s, o, detail)


# Floor tint: a soft radial wash of each team's colour centred on that team's
# spawn centroid (works for left/right, top/bottom, diagonal and split maps).
static func _draw_team_tint(ci: CanvasItem, arena: Arena, inner: Rect2, fc: Dictionary) -> void:
	var tex: ImageTexture = tint_texture()
	var c0: Vector2 = arena.spawn_centroid(0)
	var c1: Vector2 = arena.spawn_centroid(1)
	var reach: float = maxf(360.0, c0.distance_to(c1) * 0.78)
	var world: = Rect2(Vector2(arena.min_x, arena.min_y), Vector2(arena.max_x - arena.min_x, arena.max_y - arena.min_y))
	var ts: float = float(tex.get_width())
	for t in 2:
		var c: Vector2 = c0 if t == 0 else c1
		var src: = Rect2((world.position - (c - Vector2(reach, reach))) / (2.0 * reach) * ts, world.size / (2.0 * reach) * ts)
		ci.draw_texture_rect_region(tex, inner, src, Color(fc.blue if t == 0 else fc.red, 1.0), false, false)


static func _team_floor_col(fc: Dictionary, t: int) -> Color:
	return (fc.blue as Color).lightened(0.38) if t == 0 else (fc.red as Color).lightened(0.38)


# Spawn zone per spawn cluster (hull grown and clipped to the map) plus a small
# pad per spawn slot. Split / staggered spawns get one zone per entrance.
static func _draw_spawns(ci: CanvasItem, arena: Arena, s: float, o: Vector2, detail: int, fc: Dictionary, geo: Dictionary) -> void:
	for t in 2:
		var col: Color = _team_floor_col(fc, t)
		var ui: Color = UITheme.team_color(t)
		for cl in geo.clusters[t]:
			for z in cl.zones:
				ci.draw_colored_polygon(_xf(z.poly, s, o), Color(col, 0.07 if detail >= 1 else 0.1))
				ci.draw_polyline(_xf(z.loop, s, o), Color(col, 0.34 if detail >= 1 else 0.4), maxf(1.0, 1.5 * s), true)
			for q in cl.points:
				var pq: Vector2 = _p(q, s, o)
				if detail >= 1:
					ci.draw_circle(pq, 13.0 * s, Color(col, 0.1))
					ci.draw_arc(pq, 13.0 * s, 0, TAU, 24, Color(col, 0.34), maxf(1.0, 1.2 * s), true)
				else:
					ci.draw_circle(pq, maxf(1.6, 9.0 * s), Color(ui, 0.9))


# Deathmatch terrain: no team sides. Soft ground patches, plank floors inside
# buildings, darker forest floor under the canopy and the spawn circles.
static func _draw_deathmatch_floor(ci: CanvasItem, arena: Arena, s: float, o: Vector2, detail: int, env: ArenaEnv = null) -> void:
	var fc: = floor_colors(arena)
	var full: = Rect2(o, Vector2(arena.width, arena.height) * s)
	ci.draw_rect(full, fc.base.darkened(0.4))
	var inner: = _inner(arena, s, o)
	ci.draw_rect(inner, fc.base)
	if detail >= 1:
		var rng: = RandomNumberGenerator.new()
		rng.seed = hash(arena.id)
		for i in (70 if detail >= 2 else 26):
			var p: = Vector2(rng.randf_range(arena.min_x, arena.max_x), rng.randf_range(arena.min_y, arena.max_y))
			var r: = rng.randf_range(70.0, 240.0)
			var tint: Color = fc.grid if rng.randf() < 0.5 else fc.base.lightened(0.25)
			ci.draw_circle(_p(p, s, o), r * s, Color(tint, rng.randf_range(0.015, 0.04)))
		var step: = 200.0
		var gc: = Color(fc.grid, 0.035)
		var x: = arena.min_x + step
		while x < arena.max_x:
			ci.draw_line(_p(Vector2(x, arena.min_y), s, o), _p(Vector2(x, arena.max_y), s, o), gc, 1.0)
			x += step
		var y: = arena.min_y + step
		while y < arena.max_y:
			ci.draw_line(_p(Vector2(arena.min_x, y), s, o), _p(Vector2(arena.max_x, y), s, o), gc, 1.0)
			y += step
	if env_shows(env, "brush"):
		for k in arena.forest_x.size():
			ci.draw_circle(_p(Vector2(arena.forest_x[k], arena.forest_y[k]), s, o), (arena.forest_r[k] + 6.0) * s, Color(0.05, 0.13, 0.07, 0.9))
	else:
		_draw_brush_off(ci, arena, s, o)
	_draw_mud(ci, arena, s, o, detail, env_shows(env, "mud"))
	for b in arena.data.get("buildings", []):
		var rect: = Rect2(_p(Vector2(float(b.x), float(b.y)), s, o), Vector2(float(b.w), float(b.h)) * s)
		ci.draw_rect(rect, Color(0.2, 0.16, 0.11, 0.95))
		if detail >= 2:
			var yy: = rect.position.y + 20.0 * s
			while yy < rect.end.y:
				ci.draw_line(Vector2(rect.position.x, yy), Vector2(rect.end.x, yy), Color(0.1, 0.08, 0.05, 0.6), maxf(1.0, s))
				yy += 20.0 * s
	if detail >= 1:
		for p2 in arena.ffa_spawns:
			var c: = _p(p2, s, o)
			ci.draw_arc(c, 34.0 * s, 0, TAU, 32, Color(fc.grid, 0.22), maxf(1.0, 1.4 * s), true)
			ci.draw_arc(c, 6.0 * s, 0, TAU, 12, Color(fc.grid, 0.3), maxf(1.0, 1.2 * s), true)
	ci.draw_rect(inner, Color(fc.grid, 0.3), false, maxf(1.0, 2.0 * s))
	_draw_landmarks(ci, arena, s, o, detail)


# V2 battleground terrain (~30x the standard area, drawn once into the static
# layer): no team sides. Ground wash, a coarse survey grid, the generator's
# painter decor (roads, river banks, bridge and ford marks), brush ground, mud,
# building floors, faint spawn rings and the landmark names.
static func _draw_battleground_floor(ci: CanvasItem, arena: Arena, s: float, o: Vector2, detail: int, env: ArenaEnv = null) -> void:
	var fc: = floor_colors(arena)
	var full: = Rect2(o, Vector2(arena.width, arena.height) * s)
	ci.draw_rect(full, fc.base.darkened(0.45))
	var inner: = _inner(arena, s, o)
	ci.draw_rect(inner, fc.base)
	var br: Dictionary = arena.data.get("br", {})
	if detail >= 1:
		var rng: = RandomNumberGenerator.new()
		rng.seed = hash(arena.id)
		for i in (150 if detail >= 2 else 40):
			var p: = Vector2(rng.randf_range(arena.min_x, arena.max_x), rng.randf_range(arena.min_y, arena.max_y))
			var r: = rng.randf_range(140.0, 420.0)
			var tint: Color = fc.grid if rng.randf() < 0.5 else fc.base.lightened(0.25)
			ci.draw_circle(_p(p, s, o), r * s, Color(tint, rng.randf_range(0.012, 0.032)))
		var step: = 400.0
		var gc: = Color(fc.grid, 0.03)
		var x: = arena.min_x + step
		while x < arena.max_x:
			ci.draw_line(_p(Vector2(x, arena.min_y), s, o), _p(Vector2(x, arena.max_y), s, o), gc, 1.0)
			x += step
		var y: = arena.min_y + step
		while y < arena.max_y:
			ci.draw_line(_p(Vector2(arena.min_x, y), s, o), _p(Vector2(arena.max_x, y), s, o), gc, 1.0)
			y += step
	for dec in br.get("decor", []):
		var dd: Dictionary = dec
		match str(dd.get("type", "")):
			"road", "tributary":
				var rr: = Rect2(_p(Vector2(float(dd.x), float(dd.y)), s, o), Vector2(float(dd.w), float(dd.h)) * s)
				var road: bool = str(dd.type) == "road"
				ci.draw_rect(rr, Color(fc.grid, 0.05) if road else Color(0.16, 0.36, 0.5, 0.2))
				if road and detail >= 1:
					var lw: float = maxf(1.0, 2.0 * s)
					if rr.size.x >= rr.size.y:
						ci.draw_line(rr.position, Vector2(rr.end.x, rr.position.y), Color(fc.grid, 0.1), lw)
						ci.draw_line(Vector2(rr.position.x, rr.end.y), rr.end, Color(fc.grid, 0.1), lw)
					else:
						ci.draw_line(rr.position, Vector2(rr.position.x, rr.end.y), Color(fc.grid, 0.1), lw)
						ci.draw_line(Vector2(rr.end.x, rr.position.y), rr.end, Color(fc.grid, 0.1), lw)
			"river":
				var xs: Array = dd.get("xs", [])
				var ys: Array = dd.get("ys", [])
				var pts: = PackedVector2Array()
				for k in mini(xs.size(), ys.size()):
					pts.append(_p(Vector2(float(xs[k]), float(ys[k])), s, o))
				if pts.size() >= 2:
					var wd: float = float(dd.get("width", 160.0))
					ci.draw_polyline(pts, Color(0.12, 0.3, 0.36, 0.3), maxf(1.0, wd * 1.7 * s), true)
					ci.draw_polyline(pts, Color(0.1, 0.26, 0.4, 0.35), maxf(1.0, wd * 1.2 * s), true)
			"bridge", "ford":
				if detail >= 1:
					var cp: = _p(Vector2(float(dd.x), float(dd.y)), s, o)
					ci.draw_arc(cp, 46.0 * s, 0, TAU, 24, Color(fc.grid, 0.22), maxf(1.0, 2.0 * s), true)
	if env_shows(env, "brush"):
		for k in arena.forest_x.size():
			ci.draw_circle(_p(Vector2(arena.forest_x[k], arena.forest_y[k]), s, o), (arena.forest_r[k] + 5.0) * s, Color(0.05, 0.13, 0.07, 0.85))
	else:
		_draw_brush_off(ci, arena, s, o)
	_draw_mud(ci, arena, s, o, detail, env_shows(env, "mud"))
	for b in arena.data.get("buildings", []):
		var rect: = Rect2(_p(Vector2(float(b.x), float(b.y)), s, o), Vector2(float(b.w), float(b.h)) * s)
		ci.draw_rect(rect, Color(0.2, 0.16, 0.11, 0.5 if (b as Dictionary).has("ruined") else 0.92))
		if detail >= 2:
			var yy: = rect.position.y + 24.0 * s
			while yy < rect.end.y:
				ci.draw_line(Vector2(rect.position.x, yy), Vector2(rect.end.x, yy), Color(0.1, 0.08, 0.05, 0.5), maxf(1.0, s))
				yy += 24.0 * s
	if detail >= 2:
		for p2 in arena.ffa_spawns:
			ci.draw_arc(_p(p2, s, o), 30.0 * s, 0, TAU, 24, Color(fc.grid, 0.16), maxf(1.0, 1.4 * s), true)
	ci.draw_rect(inner, Color(fc.grid, 0.3), false, maxf(1.0, 3.0 * s))
	_draw_landmarks(ci, arena, s, o, detail)


# --- V2 battleground zone -------------------------------------------------------
# Live zone in world space (battle view; s = 1, o = 0): the outside tinted up to
# the map edge, the current circle as a bright edge, the next circle dashed once
# it is public (BrZone.public_view). One triangle array of about 100 rays (the
# tint) plus three multiline calls; px = world units per screen pixel, so the
# lines keep their on-screen width at any zoom. The point and index buffers are
# static and reused every frame.
const BR_ZONE_RAYS: = 96
const BR_TINT: = Color(0.42, 0.1, 0.3, 0.26)
const BR_EDGE: = Color(0.86, 0.93, 1.0)
const BR_NEXT: = Color(1.0, 1.0, 1.0, 0.8)
static var _bz_pts: PackedVector2Array = PackedVector2Array()
static var _bz_cols: PackedColorArray = PackedColorArray()
static var _bz_idx: PackedInt32Array = PackedInt32Array()
static var _bz_angles: PackedFloat64Array = PackedFloat64Array()
static var _bz_edge: PackedVector2Array = PackedVector2Array()
static var _bz_next: PackedVector2Array = PackedVector2Array()


## Distance from c (inside rect) along dir to the rect boundary.
static func _ray_to_rect(c: Vector2, dir: Vector2, rect: Rect2) -> float:
	var t: float = INF
	if dir.x > 1e-6:
		t = minf(t, (rect.end.x - c.x) / dir.x)
	elif dir.x < -1e-6:
		t = minf(t, (rect.position.x - c.x) / dir.x)
	if dir.y > 1e-6:
		t = minf(t, (rect.end.y - c.y) / dir.y)
	elif dir.y < -1e-6:
		t = minf(t, (rect.position.y - c.y) / dir.y)
	return maxf(0.0, t)


static func draw_br_zone(ci: CanvasItem, arena: Arena, view: Dictionary, px: float, anim: float = 0.0) -> void:
	if view.is_empty() or arena == null:
		return
	var rect: = Rect2(Vector2.ZERO, Vector2(arena.width, arena.height))
	var c: Vector2 = view.get("center", rect.get_center())
	c = c.clamp(rect.position, rect.end)
	var r: float = maxf(0.0, float(view.get("radius", 0.0)))
	var state: String = str(view.get("state", "loot"))
	var shrinking: bool = state == "shrink"
	var damaging: bool = float(view.get("dps_ratio", 0.0)) > 0.0
	# Ray angles: the uniform circle plus the four map corners (the tint reaches them exactly).
	_bz_angles.resize(0)
	for i in BR_ZONE_RAYS:
		_bz_angles.append(TAU * float(i) / float(BR_ZONE_RAYS))
	for corner in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
		_bz_angles.append(fposmod((corner as Vector2 - c).angle(), TAU))
	_bz_angles.sort()
	var n: int = _bz_angles.size()
	_bz_pts.resize(n * 2)
	_bz_cols.resize(n * 2)
	var tint: Color = Color(BR_TINT, BR_TINT.a * (1.0 if damaging else 0.55))
	var any_outside: bool = false
	for i in n:
		var d: = Vector2.from_angle(_bz_angles[i])
		var far: float = _ray_to_rect(c, d, rect)
		var near: float = minf(r, far)
		if near < far - 0.5:
			any_outside = true
		_bz_pts[i * 2] = c + d * near
		_bz_pts[i * 2 + 1] = c + d * far
		_bz_cols[i * 2] = tint
		_bz_cols[i * 2 + 1] = tint
	if any_outside:
		_bz_idx.resize(n * 6)
		for i in n:
			var j: int = (i + 1) % n
			_bz_idx[i * 6] = i * 2
			_bz_idx[i * 6 + 1] = i * 2 + 1
			_bz_idx[i * 6 + 2] = j * 2 + 1
			_bz_idx[i * 6 + 3] = i * 2
			_bz_idx[i * 6 + 4] = j * 2 + 1
			_bz_idx[i * 6 + 5] = j * 2
		RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), _bz_idx, _bz_pts, _bz_cols)
	# Current edge: the arcs inside the map, dark under-stroke then the bright line.
	_circle_segments(_bz_edge, c, r, rect, false)
	if not _bz_edge.is_empty():
		var glow: float = 0.75 + 0.25 * sin(anim * 5.0) if shrinking else 0.85
		ci.draw_multiline(_bz_edge, Color(INK, 0.7), 6.0 * px)
		ci.draw_multiline(_bz_edge, Color(BR_EDGE, glow), 2.6 * px)
	# Next circle (public from its announce time): dashed white.
	if bool(view.get("next_known", false)):
		var nr: float = float(view.get("next_radius", 0.0))
		var nc: Vector2 = view.get("next_center", c)
		if absf(nr - r) > 4.0 or nc.distance_to(c) > 4.0:
			_circle_segments(_bz_next, nc, maxf(nr, 6.0 * px), rect, true)
			if not _bz_next.is_empty():
				ci.draw_multiline(_bz_next, Color(INK, 0.55), 4.0 * px)
				ci.draw_multiline(_bz_next, BR_NEXT, 1.8 * px)


## Segment pairs of a 96-gon around c clipped to rect (a pair is kept when either end is
## inside); dashed keeps every other segment.
static func _circle_segments(out: PackedVector2Array, c: Vector2, r: float, rect: Rect2, dashed: bool) -> void:
	out.resize(0)
	if r <= 0.5:
		return
	var prev: Vector2 = c + Vector2(r, 0.0)
	for i in range(1, BR_ZONE_RAYS + 1):
		var q: Vector2 = c + Vector2.from_angle(TAU * float(i) / float(BR_ZONE_RAYS)) * r
		if (not dashed or i % 2 == 1) and (rect.has_point(prev) or rect.has_point(q)):
			out.append(prev)
			out.append(q)
		prev = q


# Brush ground (team modes): trampled dark grass under every patch circle.
static func _draw_brush_floor(ci: CanvasItem, arena: Arena, s: float, o: Vector2) -> void:
	for k in arena.forest_x.size():
		ci.draw_circle(_p(Vector2(arena.forest_x[k], arena.forest_y[k]), s, o), (arena.forest_r[k] + 5.0) * s, Color(0.05, 0.12, 0.06, 0.78))


# Switched-off brush (developer lab): only a faint outline where the patches
# were, like switched-off hazards in draw_hazards; no ground, no canopy.
static func _draw_brush_off(ci: CanvasItem, arena: Arena, s: float, o: Vector2) -> void:
	for k in arena.forest_x.size():
		ci.draw_arc(_p(Vector2(arena.forest_x[k], arena.forest_y[k]), s, o), arena.forest_r[k] * s, 0, TAU, 40, Color(0.5, 0.78, 0.36, 0.15), maxf(1.0, s), true)


# Mud: dark wet ground with clods and puddle glints (always active, static).
# Switched off (lab): a faint outline only, like switched-off hazards.
static func _draw_mud(ci: CanvasItem, arena: Arena, s: float, o: Vector2, detail: int, on: bool = true) -> void:
	for h in arena.hazards:
		if str(h.get("type", "")) != "mud":
			continue
		var col: = Color(str(h.get("color", "#8a6a45")))
		if not on:
			hazard_shape_draw(ci, h, s, o, Color(col, 0.025), Color(col, 0.15), maxf(1.0, s))
			continue
		var circle: bool = str(h.get("shape", "rect")) == "circle"
		hazard_shape_draw(ci, h, s, o, Color(col.darkened(0.5), 0.9), Color(0, 0, 0, 0), 1.0)
		if detail >= 1:
			var rng: = RandomNumberGenerator.new()
			rng.seed = hash(str(h.get("id", "mud")))
			var box: Rect2 = _hazard_box(h)
			var n: int = clampi(int(box.get_area() / (1800.0 if detail >= 2 else 5000.0)), 6, 90)
			for i in n:
				var rr: float = rng.randf_range(7.0, 22.0)
				var p: Vector2 = _random_in(h, box, rng, rr)
				var shade: Color = col.darkened(0.15) if i % 3 != 0 else col.darkened(0.7)
				ci.draw_circle(_p(p, s, o), rr * s, Color(shade, 0.32))
			for i in maxi(2, n / 5):
				var rr2: float = rng.randf_range(6.0, 13.0)
				var p2: Vector2 = _random_in(h, box, rng, rr2)
				ci.draw_circle(_p(p2, s, o), rr2 * s, Color(0.45, 0.55, 0.62, 0.13))
				ci.draw_arc(_p(p2, s, o), rr2 * 0.7 * s, PI * 1.1, PI * 1.6, 8, Color(0.85, 0.92, 1.0, 0.28), maxf(1.0, 1.2 * s), true)
		var line: = Color(col.lightened(0.1), 0.5)
		if circle:
			ci.draw_arc(_p(h.center, s, o), float(h.get("radius", 30.0)) * s, 0, TAU, 48, line, maxf(1.0, 1.5 * s), true)
		else:
			ci.draw_rect(Rect2(_p(Vector2(float(h.x), float(h.y)), s, o), Vector2(float(h.w), float(h.h)) * s), line, false, maxf(1.0, 1.5 * s))


## World bounds of a hazard for culling: its shape plus the reach of what is drawn around it
## (jump landings, labels, strike circles inside the area).
static func hazard_bounds(h: Dictionary) -> Rect2:
	# The closing ring and shapes without a box are never culled.
	if str(h.get("type", "")) == "closing_ring" or not (h.has("x") and h.has("y")):
		return Rect2(-1e7, -1e7, 2e7, 2e7)
	if str(h.get("shape", "rect")) != "circle" and not (h.has("w") and h.has("h")):
		return Rect2(-1e7, -1e7, 2e7, 2e7)
	var box: Rect2 = _hazard_box(h)
	if str(h.get("type", "")) == "jump_pad" and h.get("landing") is Vector2:
		box = box.expand(h.landing)
	return box.grow(160.0)


static func _hazard_box(h: Dictionary) -> Rect2:
	if str(h.get("shape", "rect")) == "circle":
		var r: float = float(h.get("radius", 30.0))
		return Rect2(Vector2(float(h.x), float(h.y)) - Vector2(r, r), Vector2(r, r) * 2.0)
	return Rect2(float(h.x), float(h.y), float(h.w), float(h.h))


static func _random_in(h: Dictionary, box: Rect2, rng: RandomNumberGenerator, inset: float) -> Vector2:
	if str(h.get("shape", "rect")) == "circle":
		var r: float = maxf(0.0, float(h.get("radius", 30.0)) - inset)
		return Vector2(float(h.x), float(h.y)) + Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * r
	var a: Vector2 = box.position + Vector2(inset, inset)
	var b: Vector2 = box.end - Vector2(inset, inset)
	if b.x < a.x:
		a.x = box.get_center().x
		b.x = a.x
	if b.y < a.y:
		a.y = box.get_center().y
		b.y = a.y
	return Vector2(rng.randf_range(a.x, b.x), rng.randf_range(a.y, b.y))


# Authored floor landmarks distinguish routes without pretending to be solid
# collision geometry. The labels remain readable in the map overview.
static func _draw_landmarks(ci: CanvasItem, arena: Arena, s: float, o: Vector2, detail: int) -> void:
	for mark in arena.data.get("landmarks", []):
		var c: Vector2 = _p(Vector2(float(mark.x), float(mark.y)), s, o)
		var r: float = maxf(4.0, float(mark.get("radius", 70.0)) * s)
		var kind: String = str(mark.get("kind", "landmark"))
		var col: Color = arena.accent
		if kind == "supply": col = Color("#6fcaa6")
		elif kind == "lane": col = col.darkened(0.22)
		ci.draw_circle(c, r, Color(col, 0.035))
		for k in 4:
			var a: float = float(k) * PI * 0.5 + PI * 0.12
			ci.draw_arc(c, r, a, a + PI * 0.24, 14, Color(col, 0.14), maxf(1.0, s), true)
		if detail >= 1 and s >= 0.28:
			var font_size: int = clampi(int(15.0 * s), 9, 16)
			var label: String = str(mark.get("label", ""))
			var text_width: float = DB.font_bold.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			ci.draw_string(DB.font_bold, c + Vector2(-text_width * 0.5, r + font_size), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(col, 0.48))


# Canopy drawn over the units, translucent so a spectator still sees who hides
# inside. Deathmatch: forest canopy ("숲"). Team modes: tall grass ("수풀").
static func draw_canopy(ci: CanvasItem, arena: Arena, s: float, o: Vector2, alpha: float, detail: int = 2, env: ArenaEnv = null) -> void:
	if not env_shows(env, "brush"):
		return
	var all: PackedInt32Array = PackedInt32Array()
	all.resize(arena.forest_x.size())
	for k in all.size():
		all[k] = k
	draw_canopy_list(ci, arena, all, s, o, alpha, detail)


## The canopy of a subset of the forest / brush circles (the battle view's culled battleground
## chunks); draw_canopy draws them all.
static func draw_canopy_list(ci: CanvasItem, arena: Arena, list: PackedInt32Array, s: float, o: Vector2, alpha: float, detail: int = 2) -> void:
	var brush: bool = arena.ruleset != "deathmatch"
	# ~190 brush circles on a battleground map: fewer tufts per patch.
	if arena.ruleset == "battleground":
		detail = mini(detail, 1)
	for k in list:
		var c: = _p(Vector2(arena.forest_x[k], arena.forest_y[k]), s, o)
		var r: = arena.forest_r[k] * s
		if brush:
			_draw_brush_patch(ci, c, r, s, alpha, detail, k)
			continue
		ci.draw_circle(c, r, Color(0.11, 0.3, 0.16, alpha))
		if detail >= 1:
			var rng: = RandomNumberGenerator.new()
			rng.seed = k * 7919 + 13
			for j in (6 if detail >= 2 else 3):
				var ang: = rng.randf() * TAU
				var d: = rng.randf_range(0.15, 0.62) * r
				ci.draw_circle(c + Vector2.from_angle(ang) * d, rng.randf_range(0.26, 0.42) * r, Color(0.16, 0.4, 0.2, alpha * 0.55))
			ci.draw_circle(c + Vector2( - r * 0.22, - r * 0.26), r * 0.3, Color(0.42, 0.66, 0.32, alpha * 0.22))
		ci.draw_arc(c, r, 0, TAU, 40, Color(0.3, 0.55, 0.3, alpha * 0.5), maxf(1.0, 1.2 * s), true)


static func _draw_brush_patch(ci: CanvasItem, c: Vector2, r: float, s: float, alpha: float, detail: int, k: int) -> void:
	ci.draw_circle(c, r, Color(0.2, 0.4, 0.16, alpha * 0.82))
	if detail >= 1:
		var rng: = RandomNumberGenerator.new()
		rng.seed = k * 104729 + 71
		var tufts: int = 16 if detail >= 2 else 7
		var blade: float = maxf(2.0, 11.0 * s)
		for j in tufts:
			var base: Vector2 = c + Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * r * 0.82
			var lean: float = rng.randf_range(-0.35, 0.35)
			var gc: = Color(0.42, 0.68, 0.28, alpha * 0.85) if j % 2 == 0 else Color(0.3, 0.55, 0.22, alpha * 0.85)
			for b in 3:
				var ang: float = -PI * 0.5 + lean + (float(b) - 1.0) * 0.42
				ci.draw_line(base, base + Vector2.from_angle(ang) * blade * (1.0 if b == 1 else 0.75), gc, maxf(1.0, 1.4 * s), true)
	ci.draw_arc(c, r, 0, TAU, 40, Color(0.5, 0.78, 0.36, alpha * 0.5), maxf(1.0, 1.3 * s), true)


static func obstacle_color(od: Dictionary) -> Color:
	var c: = Color(str(od.get("color", "#5d5a55")))
	return c


static func draw_control_layout(ci: CanvasItem, arena: Arena, s: float, o: Vector2) -> void:
	if arena.ruleset != "control":
		return
	for point in arena.control_points:
		var c: Vector2 = _p(point.center, s, o)
		var r: float = maxf(6.0, float(point.radius) * s)
		ci.draw_circle(c, r, Color(UITheme.GOLD, 0.16))
		ci.draw_arc(c, r, 0, TAU, 32, Color(UITheme.GOLD, 0.9), 1.2, true)
		ci.draw_string(DB.font_bold, c + Vector2(-3, 3), str(point.id), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, UITheme.TEXT)
	for zone in arena.heal_zones:
		var c: Vector2 = _p(zone.center, s, o)
		ci.draw_circle(c, maxf(3.0, float(zone.radius) * s), Color(UITheme.GOOD, 0.12))
		ci.draw_line(c - Vector2(2.5, 0), c + Vector2(2.5, 0), UITheme.GOOD, 1.5)
		ci.draw_line(c - Vector2(0, 2.5), c + Vector2(0, 2.5), UITheme.GOOD, 1.5)


# Static obstacles. skip_gates: the battle view draws gates every frame instead.
static func draw_obstacles(ci: CanvasItem, arena: Arena, s: float, o: Vector2, detail: int = 2, skip_gates: bool = false) -> void :
	for i in arena.obs_count:
		draw_obstacle(ci, arena, i, s, o, detail, skip_gates)


## V2 battleground: a subset of the obstacles (the battle view draws its static layer in culled
## chunks, one canvas item per map chunk). Gates are skipped (drawn per frame).
static func draw_obstacle_list(ci: CanvasItem, arena: Arena, list: PackedInt32Array, s: float, o: Vector2, detail: int = 2) -> void:
	for i in list:
		draw_obstacle(ci, arena, i, s, o, detail, true)


static func draw_obstacle(ci: CanvasItem, arena: Arena, i: int, s: float, o: Vector2, detail: int, skip_gates: bool) -> void:
	var od: Dictionary = arena.obstacles[i]
	var kind: String = str(od.get("kind", "wall"))
	if i < arena.obs_gate.size() and arena.obs_gate[i] >= 0:
		if not skip_gates:
			var g: Dictionary = arena.gates[arena.obs_gate[i]]
			_draw_gate(ci, g, obstacle_color(od), s, o, 0, 0.0, 0.0, 0.0, detail)
		return
	if arena.obs_circle[i] == 0:
		var rect0: = Rect2(_p(Vector2(arena.obs_x[i], arena.obs_y[i]), s, o), Vector2(arena.obs_w[i], arena.obs_h[i]) * s)
		match kind:
			"chasm":
				_draw_chasm(ci, od, rect0, s, detail)
				return
			"lattice":
				_draw_lattice(ci, od, rect0, s, detail)
				return
			"hedge":
				_draw_hedge(ci, od, rect0, s, detail)
				return
	_draw_solid(ci, arena, i, od, s, o, detail)


static func _draw_solid(ci: CanvasItem, arena: Arena, i: int, od: Dictionary, s: float, o: Vector2, detail: int) -> void:
	var col: = obstacle_color(od)
	var vis_block: = (arena.obs_mask_full[i] & Arena.MASK_VISION) != 0 if i < arena.obs_mask_full.size() else (arena.obs_mask[i] & Arena.MASK_VISION) != 0
	if arena.obs_circle[i] == 1:
		var c: = _p(Vector2(arena.obs_x[i], arena.obs_y[i]), s, o)
		var r: = arena.obs_r[i] * s
		if detail >= 1:
			ci.draw_circle(c + Vector2(4, 6) * s, r, Color(0, 0, 0, 0.35))
		ci.draw_circle(c, r, col.darkened(0.25))
		ci.draw_circle(c + Vector2( - r * 0.12, - r * 0.14), r * 0.82, col)
		if detail >= 2:
			ci.draw_arc(c + Vector2( - r * 0.12, - r * 0.14), r * 0.62, 0, TAU, 32, Color(col.darkened(0.2), 0.6), maxf(1.0, 1.2 * s), true)
			ci.draw_arc(c + Vector2( - r * 0.12, - r * 0.14), r * 0.38, 0, TAU, 24, Color(col.darkened(0.2), 0.45), maxf(1.0, 1.0 * s), true)
			ci.draw_circle(c + Vector2( - r * 0.25, - r * 0.3), r * 0.35, Color(col.lightened(0.35), 0.3))
		ci.draw_arc(c, r, 0, TAU, 48, Color(col.lightened(0.45), 0.55 if vis_block else 0.3), maxf(1.0, 1.6 * s), true)
		return
	var rect: = Rect2(_p(Vector2(arena.obs_x[i], arena.obs_y[i]), s, o), Vector2(arena.obs_w[i], arena.obs_h[i]) * s)
	if detail >= 1:
		ci.draw_rect(Rect2(rect.position + Vector2(5, 7) * s, rect.size), Color(0, 0, 0, 0.35))
	ci.draw_rect(rect, col.darkened(0.3))
	var top: = Rect2(rect.position + Vector2(2, 2) * s, rect.size - Vector2(4, 7) * s)
	if top.size.x > 0 and top.size.y > 0:
		ci.draw_rect(top, col)
		if detail >= 2:
			var bh: = 18.0 * s
			var row: = 0
			var yy: = top.position.y + bh
			while yy < top.end.y - 2.0:
				ci.draw_line(Vector2(top.position.x, yy), Vector2(top.end.x, yy), Color(col.darkened(0.35), 0.55), maxf(1.0, s))
				var bw: = 34.0 * s
				var xx: = top.position.x + (bw * 0.5 if row % 2 == 1 else 0.0) + bw
				while xx < top.end.x - 2.0:
					ci.draw_line(Vector2(xx, yy - bh), Vector2(xx, yy), Color(col.darkened(0.35), 0.4), maxf(1.0, s))
					xx += bw
				yy += bh
				row += 1
			ci.draw_rect(Rect2(top.position, Vector2(top.size.x, maxf(2.0, top.size.y * 0.12))), Color(col.lightened(0.3), 0.35))
	if not vis_block:
		var k: = 0.0
		while k < rect.size.x + rect.size.y and detail >= 1:
			var a: = rect.position + Vector2(k, 0)
			var b: = rect.position + Vector2(k - rect.size.y, rect.size.y)
			var seg: = _clip_seg_rect(a, b, rect)
			if seg.size() == 2:
				ci.draw_line(seg[0], seg[1], Color(1, 1, 1, 0.08), 1.0)
			k += 10.0 * s
	ci.draw_rect(rect, Color(col.lightened(0.45), 0.5 if vis_block else 0.28), false, maxf(1.0, 1.5 * s))


# Sunken terrain (lava trench, void, water canal, ravine): bodies cannot cross,
# sight and projectiles can. Drawn as a pit: lip, deep floor, shadowed near walls.
static func _draw_chasm(ci: CanvasItem, od: Dictionary, rect: Rect2, s: float, detail: int) -> void:
	var col: = obstacle_color(od)
	var mat: String = str(od.get("material", "void"))
	var deep: Color
	var glow: Color
	match mat:
		"lava":
			deep = Color("#1a0602")
			glow = Color("#ff6a2a")
		"water":
			deep = Color("#04131f")
			glow = Color("#6cc0ff")
		"ravine":
			deep = Color("#040b0d")
			glow = Color("#7fb3b8")
		_:
			deep = Color("#04020a")
			glow = Color("#a58cff")
	ci.draw_rect(rect.grow(maxf(1.0, 3.0 * s)), Color(col.lightened(0.3), 0.5))
	ci.draw_rect(rect, deep)
	ci.draw_rect(rect, Color(col, 0.55))
	var wall: float = minf(minf(rect.size.y, rect.size.x) * 0.32, 16.0 * s)
	if wall >= 1.0:
		for i in 3:
			var w: float = wall * (1.0 - float(i) / 3.0)
			ci.draw_rect(Rect2(rect.position, Vector2(rect.size.x, w)), Color(0, 0, 0, 0.26))
			ci.draw_rect(Rect2(rect.position, Vector2(w * 0.6, rect.size.y)), Color(0, 0, 0, 0.14))
		ci.draw_rect(Rect2(Vector2(rect.position.x, rect.end.y - wall * 0.45), Vector2(rect.size.x, wall * 0.45)), Color(col.lightened(0.18), 0.4))
	if detail >= 1:
		var rng: = RandomNumberGenerator.new()
		rng.seed = hash(str(od.get("id", "chasm")))
		var inner: Rect2 = rect.grow_individual(-wall * 0.6, -wall, -2.0 * s, -wall * 0.5)
		if inner.size.x > 2.0 and inner.size.y > 2.0:
			var n: int = clampi(int(inner.get_area() / maxf(1.0, 900.0 * s * s)), 3, 60) if detail >= 2 else clampi(int(inner.get_area() / maxf(1.0, 2600.0 * s * s)), 2, 14)
			match mat:
				"lava":
					# Dark crust with a few glowing molten seams flowing along the trench.
					var along_x: bool = inner.size.x >= inner.size.y
					var span: float = inner.size.y if along_x else inner.size.x
					var seams: int = clampi(int(span / maxf(1.0, 30.0 * s)), 1, 6)
					for j in seams:
						var f: float = (float(j) + 0.5) / float(seams)
						var ph: float = rng.randf() * TAU
						var amp: float = minf(span / float(seams) * 0.3, 9.0 * s)
						var length: float = inner.size.x if along_x else inner.size.y
						var steps: int = clampi(int(length / maxf(1.0, 14.0 * s)), 4, 80)
						var prev: Vector2 = Vector2.ZERO
						for k in steps + 1:
							var u: float = float(k) / float(steps)
							var w: float = sin(u * length / maxf(1.0, 38.0 * s) + ph) * amp
							var q: Vector2 = Vector2(inner.position.x + u * inner.size.x, inner.position.y + f * inner.size.y + w) if along_x else Vector2(inner.position.x + f * inner.size.x + w, inner.position.y + u * inner.size.y)
							if k > 0:
								ci.draw_line(prev, q, Color(glow, 0.22), maxf(2.0, 7.0 * s), true)
								ci.draw_line(prev, q, Color(1.5, 0.72, 0.3, 0.75), maxf(1.0, 2.0 * s), true)
							prev = q
					for i in maxi(2, n / 5):
						var p: = Vector2(rng.randf_range(inner.position.x, inner.end.x), rng.randf_range(inner.position.y, inner.end.y))
						ci.draw_circle(p, rng.randf_range(1.5, 3.5) * s, Color(1.6, 0.85, 0.4, 0.55))
				"water":
					var yy: float = inner.position.y + 8.0 * s
					var row: int = 0
					while yy < inner.end.y:
						var x0: float = inner.position.x + (12.0 * s if row % 2 == 1 else 0.0)
						while x0 + 14.0 * s < inner.end.x:
							ci.draw_arc(Vector2(x0 + 7.0 * s, yy), 7.0 * s, PI * 1.15, PI * 1.85, 6, Color(glow, 0.32), maxf(1.0, 1.2 * s), true)
							x0 += 26.0 * s
						yy += 13.0 * s
						row += 1
				"ravine":
					for i in n:
						var p2: = Vector2(rng.randf_range(inner.position.x, inner.end.x), rng.randf_range(inner.position.y, inner.end.y))
						var r2: float = rng.randf_range(3.0, 9.0) * s
						ci.draw_circle(p2, r2, Color(col.lightened(0.22), 0.5))
						ci.draw_circle(p2 + Vector2(-r2, -r2) * 0.3, r2 * 0.4, Color(glow, 0.22))
				_:
					for i in n:
						var p3: = Vector2(rng.randf_range(inner.position.x, inner.end.x), rng.randf_range(inner.position.y, inner.end.y))
						ci.draw_circle(p3, maxf(0.6, rng.randf_range(0.6, 1.8) * s), Color(glow.lightened(0.4), rng.randf_range(0.25, 0.7)))
					var ctr: Vector2 = inner.get_center()
					var rad: float = minf(inner.size.x, inner.size.y) * 0.4
					if rad > 3.0:
						ci.draw_arc(ctr, rad, 0.3, 2.4, 16, Color(glow, 0.16), maxf(1.0, 1.4 * s), true)
						ci.draw_arc(ctr, rad * 0.6, 3.4, 5.6, 14, Color(glow, 0.12), maxf(1.0, 1.2 * s), true)
	ci.draw_rect(rect, Color(INK, 0.7), false, maxf(1.0, 1.4 * s))


# Low iron lattice fence: blocks bodies, sight and shots pass. Hatched, see-through.
static func _draw_lattice(ci: CanvasItem, od: Dictionary, rect: Rect2, s: float, detail: int) -> void:
	var col: = obstacle_color(od)
	ci.draw_rect(Rect2(rect.position + Vector2(3, 4) * s, rect.size), Color(0, 0, 0, 0.22))
	ci.draw_rect(rect, Color(col.darkened(0.62), 0.42))
	if detail >= 1:
		var step: float = maxf(3.0, 9.0 * s)
		var hc: = Color(col.lightened(0.12), 0.78)
		var k: float = 0.0
		while k < rect.size.x + rect.size.y:
			var s1: = _clip_seg_rect(rect.position + Vector2(k, 0), rect.position + Vector2(k - rect.size.y, rect.size.y), rect)
			if s1.size() == 2:
				ci.draw_line(s1[0], s1[1], hc, maxf(1.0, 1.4 * s), true)
			var s2: = _clip_seg_rect(rect.position + Vector2(k - rect.size.y, 0), rect.position + Vector2(k, rect.size.y), rect)
			if s2.size() == 2:
				ci.draw_line(s2[0], s2[1], hc, maxf(1.0, 1.4 * s), true)
			k += step
	ci.draw_rect(rect, Color(col.lightened(0.3), 0.95), false, maxf(1.0, 2.0 * s))
	if detail >= 1:
		_draw_posts(ci, rect, s, col.lightened(0.42))


static func _draw_posts(ci: CanvasItem, rect: Rect2, s: float, col: Color) -> void:
	var horizontal: bool = rect.size.x >= rect.size.y
	var thick: float = minf(rect.size.x, rect.size.y)
	var length: float = maxf(rect.size.x, rect.size.y)
	var post: float = minf(thick, maxf(3.0, 8.0 * s))
	var n: int = maxi(1, int(length / maxf(1.0, 46.0 * s)))
	for j in n + 1:
		var f: float = float(j) / float(n)
		var c: Vector2 = Vector2(rect.position.x + rect.size.x * f, rect.get_center().y) if horizontal else Vector2(rect.get_center().x, rect.position.y + rect.size.y * f)
		ci.draw_rect(Rect2(c - Vector2(post, post) * 0.5, Vector2(post, post)), col)


# Low thorn hedge: leafy clumps, blocks bodies only (sight and shots pass).
static func _draw_hedge(ci: CanvasItem, od: Dictionary, rect: Rect2, s: float, detail: int) -> void:
	var col: = obstacle_color(od)
	ci.draw_rect(Rect2(rect.position + Vector2(3, 5) * s, rect.size), Color(0, 0, 0, 0.2))
	ci.draw_rect(rect, Color(col.darkened(0.5), 0.72))
	if detail >= 1:
		var rng: = RandomNumberGenerator.new()
		rng.seed = hash(str(od.get("id", "hedge")))
		var cell: float = maxf(4.0, 24.0 * s)
		var y: float = rect.position.y + cell * 0.5
		while y < rect.end.y:
			var x: float = rect.position.x + cell * 0.5
			while x < rect.end.x:
				var r: float = cell * rng.randf_range(0.5, 0.68)
				var p: = Vector2(clampf(x + rng.randf_range(-0.2, 0.2) * cell, rect.position.x + r * 0.8, rect.end.x - r * 0.8), clampf(y + rng.randf_range(-0.2, 0.2) * cell, rect.position.y + r * 0.8, rect.end.y - r * 0.8))
				ci.draw_circle(p, r, Color(col.darkened(0.1), 0.92))
				ci.draw_circle(p + Vector2(-0.25, -0.3) * r, r * 0.5, Color(col.lightened(0.28), 0.5))
				if detail >= 2 and rng.randf() < 0.55:
					var tip: = p + Vector2.from_angle(rng.randf() * TAU) * r
					ci.draw_line(tip, tip + (tip - p).normalized() * 4.0 * s, Color(0.85, 0.78, 0.55, 0.75), maxf(1.0, 1.2 * s), true)
				x += cell
			y += cell
	else:
		ci.draw_rect(rect, Color(col, 0.7))
	ci.draw_rect(rect, Color(col.lightened(0.35), 0.4), false, maxf(1.0, 1.2 * s))


static func _clip_seg_rect(a: Vector2, b: Vector2, r: Rect2) -> Array:
	var res: = Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([a, b]), PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]))
	if res.is_empty():
		return []
	var pl: PackedVector2Array = res[0]
	if pl.size() < 2:
		return []
	return [pl[0], pl[pl.size() - 1]]


static func hazard_shape_draw(ci: CanvasItem, h: Dictionary, s: float, o: Vector2, fill: Color, line: Color, lw: float) -> void :
	if str(h.get("shape", "rect")) == "circle":
		var c: = _p(Vector2(float(h.x), float(h.y)), s, o)
		var r: = float(h.get("radius", 30.0)) * s
		if fill.a > 0.0:
			ci.draw_circle(c, r, fill)
		if line.a > 0.0:
			ci.draw_arc(c, r, 0, TAU, 64, line, lw, true)
	else:
		var rect: = Rect2(_p(Vector2(float(h.x), float(h.y)), s, o), Vector2(float(h.w), float(h.h)) * s)
		if fill.a > 0.0:
			ci.draw_rect(rect, fill)
		if line.a > 0.0:
			ci.draw_rect(rect, line, false, lw)


# Text centred on c at px * text_zoom, with a dark outline. No allocation.
static func label(ci: CanvasItem, c: Vector2, text: String, col: Color, px: int, zoom: float = -1.0) -> void:
	var f: Font = DB.font_bold
	if f == null:
		return
	var z: float = text_zoom if zoom < 0.0 else zoom
	var w: float = f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	ci.draw_set_transform(c, 0.0, Vector2(z, z))
	ci.draw_string_outline(f, Vector2(-w * 0.5, 0.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, 4, Color(INK, 0.85 * col.a))
	ci.draw_string(f, Vector2(-w * 0.5, 0.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# Two-part label ("포격 " + "1.4"): caption in col_a, number in col_b.
static func label2(ci: CanvasItem, c: Vector2, a: String, b: String, col_a: Color, col_b: Color, px: int) -> void:
	var f: Font = DB.font_bold
	if f == null:
		return
	var z: float = text_zoom
	var wa: float = f.get_string_size(a, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var wb: float = f.get_string_size(b, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var x0: float = -(wa + wb) * 0.5
	ci.draw_set_transform(c, 0.0, Vector2(z, z))
	ci.draw_string_outline(f, Vector2(x0, 0.0), a, HORIZONTAL_ALIGNMENT_LEFT, -1, px, 4, Color(INK, 0.85 * col_a.a))
	ci.draw_string_outline(f, Vector2(x0 + wa, 0.0), b, HORIZONTAL_ALIGNMENT_LEFT, -1, px, 4, Color(INK, 0.85 * col_b.a))
	ci.draw_string(f, Vector2(x0, 0.0), a, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col_a)
	ci.draw_string(f, Vector2(x0 + wa, 0.0), b, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col_b)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _dashed_arc(ci: CanvasItem, c: Vector2, r: float, col: Color, w: float, dashes: int, rot: float = 0.0) -> void:
	var step: float = TAU / float(dashes)
	for i in dashes:
		var a0: float = rot + float(i) * step
		ci.draw_arc(c, r, a0, a0 + step * 0.55, 5, col, w, true)


static func _dashed_rect(ci: CanvasItem, rect: Rect2, col: Color, w: float, dash: float) -> void:
	var tr: Vector2 = Vector2(rect.end.x, rect.position.y)
	var bl: Vector2 = Vector2(rect.position.x, rect.end.y)
	_dashed_line(ci, rect.position, tr, col, w, dash)
	_dashed_line(ci, tr, rect.end, col, w, dash)
	_dashed_line(ci, rect.end, bl, col, w, dash)
	_dashed_line(ci, bl, rect.position, col, w, dash)


static func _dashed_line(ci: CanvasItem, a: Vector2, b: Vector2, col: Color, w: float, dash: float) -> void:
	var length: float = a.distance_to(b)
	if length < 0.5:
		return
	var d: Vector2 = (b - a) / length
	var t: float = 0.0
	while t < length:
		ci.draw_line(a + d * t, a + d * minf(length, t + dash), col, w)
		t += dash * 2.0


# Inline clock fields (filled by _clock, read right after; no allocation).
static var _c_active: bool = false
static var _c_warning: bool = false
static var _c_progress: float = 0.0
static var _c_to_active: float = 0.0


static func _clock(h: Dictionary, t: float, typ: String) -> void:
	if bool(h.get("alwaysActive", false)) or typ in Arena.ALWAYS_ON_TYPES:
		_c_active = true
		_c_warning = false
		_c_progress = 1.0
		_c_to_active = 0.0
		return
	var period: float = maxf(0.1, float(h.get("period", 1.0)))
	var shifted: float = fposmod(t + float(h.get("phase", 0.0)), period)
	var act: float = clampf(float(h.get("activeDuration", 0.0)), 0.0, period)
	var warn: float = clampf(float(h.get("warningDuration", 0.0)), 0.0, period - act)
	_c_active = shifted < act
	_c_warning = shifted >= period - warn
	_c_progress = (shifted / maxf(0.001, act)) if _c_active else (shifted / period)
	_c_to_active = (period - shifted) if shifted >= act else 0.0


static func _fountain_remaining(h: Dictionary, env: ArenaEnv, t: float) -> float:
	if env == null:
		return 0.0
	var id: String = str(h.get("id", ""))
	var key: String = _fountain_keys.get(id, "")
	if key == "":
		key = "fountain:" + id
		_fountain_keys[id] = key
	return maxf(0.0, float(env.cooldowns.get(key, 0.0)) - t)


static func draw_hazards(ci: CanvasItem, arena: Arena, s: float, o: Vector2, t: float, detail: int = 2, anim: float = 0.0, env: ArenaEnv = null, cull: Rect2 = Rect2()) -> void :
	var idx: int = -1
	var culled: bool = cull.size.x > 0.0
	for h in arena.hazards:
		idx += 1
		var col: = Color(str(h.get("color", "#f5b36d")))
		var ty: = str(h.get("type", ""))
		if ty == "mud":
			continue
		# V2 battleground view: hazards off screen are skipped (world rect, s = 1).
		if culled and not cull.intersects(hazard_bounds(h)):
			continue
		if env and not env.type_active(ty):
			if ty != "closing_ring":
				hazard_shape_draw(ci, h, s, o, Color(col, 0.025), Color(col, 0.15), maxf(1.0, s))
			continue
		_clock(h, t, ty)
		var phase: = "active" if _c_active else ("warning" if _c_warning else "idle")
		var warn_p: = 1.0 - _c_to_active / maxf(0.05, float(h.get("warningDuration", 0.5)))
		match ty:
			"haste":
				hazard_shape_draw(ci, h, s, o, Color(col, 0.13), Color(col, 0.75), maxf(1.0, 2.0 * s))
				var c4: Vector2 = _p(h.center, s, o)
				var arrow: float = 12.0 * s
				for k in 3:
					var base: Vector2 = c4 + Vector2((float(k) - 1.0) * 19.0 * s, 0.0)
					ci.draw_line(base + Vector2(-arrow * 0.4, -arrow), base + Vector2(arrow * 0.4, 0), Color(col.lightened(0.25), 0.9), maxf(1.0, 2.0 * s), true)
					ci.draw_line(base + Vector2(arrow * 0.4, 0), base + Vector2(-arrow * 0.4, arrow), Color(col.lightened(0.25), 0.9), maxf(1.0, 2.0 * s), true)
			"healing_fountain":
				var c5: Vector2 = _p(h.center, s, o)
				var r5: float = float(h.get("radius", 40.0)) * s
				var remaining: float = _fountain_remaining(h, env, t)
				var ready: bool = remaining <= 0.0
				ci.draw_circle(c5, r5, Color(col, 0.18 if ready else 0.04))
				ci.draw_arc(c5, r5, 0, TAU, 48, Color(col, 0.8 if ready else 0.25), maxf(1.0, 2.0 * s), true)
				if not ready:
					var charge: float = clampf(1.0 - remaining / maxf(0.1, float(h.get("cooldown", 18.0))), 0.0, 1.0)
					ci.draw_arc(c5, r5 * 0.83, -PI * 0.5, -PI * 0.5 + TAU * maxf(0.001, charge), 48, Color(col, 0.75), maxf(1.0, 2.0 * s), true)
				ci.draw_line(c5 - Vector2(r5 * 0.3, 0), c5 + Vector2(r5 * 0.3, 0), Color(col, 1.0 if ready else 0.25), maxf(2.0, 5.0 * s))
				ci.draw_line(c5 - Vector2(0, r5 * 0.3), c5 + Vector2(0, r5 * 0.3), Color(col, 1.0 if ready else 0.25), maxf(2.0, 5.0 * s))
				if not ready and detail >= 2 and env != null:
					label(ci, c5 + Vector2(0, r5 + 14.0 * text_zoom), num_str(remaining), Color(col, 0.85), 12)
			"gravity":
				var c6: Vector2 = _p(h.center, s, o)
				var r6: float = float(h.get("radius", 100.0)) * s
				ci.draw_circle(c6, r6, Color(col, 0.11 if phase == "active" else 0.025))
				ci.draw_arc(c6, r6, 0, TAU, 64, Color(col, 0.8 if phase != "idle" else 0.23), maxf(1.0, 2.0 * s), true)
				ci.draw_circle(c6, maxf(2.0, 9.0 * s), Color(col, 0.85))
				if phase == "active":
					for k in 3:
						var rr: float = r6 * (1.0 - fposmod(t * 0.8 + float(k) / 3.0, 1.0))
						ci.draw_arc(c6, maxf(1.0, rr), t + k, t + k + PI * 1.5, 40, Color(col, 0.62), maxf(1.0, 1.8 * s), true)
				elif phase == "warning":
					ci.draw_arc(c6, r6 * clampf(warn_p, 0.02, 1.0), 0, TAU, 48, Color(col.lightened(0.35), 0.8), maxf(1.0, 2.0 * s), true)
			"shockwave":
				var c7: Vector2 = _p(h.center, s, o)
				var r7: float = float(h.get("radius", 150.0)) * s
				ci.draw_arc(c7, r7, 0, TAU, 72, Color(col, 0.25), maxf(1.0, s), true)
				ci.draw_circle(c7, maxf(2.0, 7.0 * s), Color(col, 0.8))
				if phase == "warning":
					ci.draw_circle(c7, r7, Color(col, 0.05 + 0.08 * clampf(warn_p, 0.0, 1.0)))
					ci.draw_arc(c7, r7, -PI * 0.5, -PI * 0.5 + TAU * clampf(warn_p, 0.01, 1.0), 72, Color(col.lightened(0.25), 0.9), maxf(1.0, 3.0 * s), true)
				elif phase == "active":
					var wave: float = Arena.shockwave_radius(h, t) * s
					ci.draw_arc(c7, maxf(1.0, wave), 0, TAU, 72, Color(col, 0.3), maxf(1.0, float(h.get("ringWidth", 22.0)) * s), true)
					ci.draw_arc(c7, maxf(1.0, wave), 0, TAU, 72, Color(col.lightened(0.45), 0.95), maxf(1.0, 2.5 * s), true)
			"lava":
				var pulse: = 0.5 + 0.5 * sin(anim * 2.2 + float(h.x) * 0.01)
				hazard_shape_draw(ci, h, s, o, Color(col.darkened(0.45), 0.85), Color(col, 0.0), 1.0)
				if str(h.get("shape", "rect")) == "circle":
					var c: = _p(Vector2(float(h.x), float(h.y)), s, o)
					var r: = float(h.radius) * s
					ci.draw_circle(c, r * 0.78, Color(col, 0.55 + 0.15 * pulse))
					ci.draw_circle(c + Vector2(r * 0.12, - r * 0.1), r * 0.42, Color(col.lightened(0.35), 0.45 + 0.2 * pulse))
					if detail >= 2:
						for k in 5:
							var ang: = anim * 0.4 + k * 1.3 + float(h.y) * 0.02
							var bp: = c + Vector2.from_angle(ang) * r * (0.35 + 0.35 * fmod(k * 0.37 + anim * 0.13, 1.0))
							ci.draw_circle(bp, r * 0.06 * (1.0 + pulse), Color(1.4, 0.9, 0.5, 0.65))
					ci.draw_arc(c, r, 0, TAU, 64, Color(col.lightened(0.2), 0.7), maxf(1.0, 2.0 * s), true)
				else:
					hazard_shape_draw(ci, h, s, o, Color(col, 0.5 + 0.15 * pulse), Color(col.lightened(0.2), 0.7), maxf(1.0, 2.0 * s))
			"spikes":
				var a: = 0.14
				var line_a: = 0.35
				if phase == "warning":
					var blink: = 0.5 + 0.5 * sin(anim * 18.0)
					a = 0.18 + 0.2 * blink
					line_a = 0.7 + 0.3 * blink
				elif phase == "active":
					a = 0.5
					line_a = 1.0
				hazard_shape_draw(ci, h, s, o, Color(col, a), Color(col, line_a), maxf(1.0, 2.0 * s))
				if detail >= 1:
					_draw_spike_teeth(ci, h, s, o, col, phase == "active")
			"eruption":
				var c2: = _p(Vector2(float(h.x), float(h.y)), s, o)
				var r2: = float(h.get("radius", 100.0)) * s
				ci.draw_circle(c2, r2 * 0.28, Color(col.darkened(0.5), 0.9))
				ci.draw_circle(c2, r2 * 0.18, Color(col, 0.7))
				ci.draw_arc(c2, r2, 0, TAU, 72, Color(col, 0.28), maxf(1.0, 1.5 * s), true)
				if phase == "warning":
					var pr: = clampf(warn_p, 0.0, 1.0)
					ci.draw_circle(c2, r2, Color(col, 0.08 + 0.16 * pr))
					ci.draw_arc(c2, r2 * pr, 0, TAU, 72, Color(col.lightened(0.3), 0.9), maxf(1.0, 3.0 * s), true)
				elif phase == "active":
					ci.draw_circle(c2, r2, Color(1.6, 0.8, 0.35, 0.45))
					ci.draw_arc(c2, r2, 0, TAU, 72, Color(2.0, 1.1, 0.5, 1.0), maxf(2.0, 4.0 * s), true)
			"wind":
				var dir: = Arena.hazard_direction(h, t)
				hazard_shape_draw(ci, h, s, o, Color(col, 0.07), Color(col, 0.3), maxf(1.0, 1.5 * s))
				if detail >= 1:
					_draw_wind_streaks(ci, h, s, o, col, dir, anim, detail)
				else:
					_draw_arrow(ci, _p(h.center, s, o), dir, maxf(4.0, 26.0 * s), Color(col.lightened(0.2), 0.85), maxf(1.0, 2.0 * s))
			"portal":
				var c3: = _p(Vector2(float(h.x), float(h.y)), s, o)
				var r3: = float(h.get("radius", 36.0)) * s
				ci.draw_circle(c3, r3, Color(col.darkened(0.6), 0.9))
				for k in 3:
					var rr: = r3 * (0.45 + 0.2 * k)
					var st: = anim * (1.6 - k * 0.4) + k
					ci.draw_arc(c3, rr, st, st + PI * 1.2, 32, Color(col.lightened(0.1 * k), 0.75 - 0.18 * k), maxf(1.0, 2.2 * s), true)
				ci.draw_arc(c3, r3, 0, TAU, 48, Color(col, 0.85), maxf(1.0, 2.0 * s), true)
				if h.has("exit") and detail >= 2:
					var ex: Vector2 = h.exit
					ci.draw_line(c3 + ex * r3 * 0.9, c3 + ex * r3 * 1.35, Color(col, 0.7), maxf(1.0, 2.0 * s), true)
			"artillery":
				_draw_artillery(ci, h, col, s, o, t, detail, anim, env)
			"jump_pad":
				_draw_jump_pad(ci, h, col, s, o, detail, anim)
			"closing_ring":
				_draw_ring(ci, arena, h, idx, col, s, o, t, detail, anim)


static func _draw_arrow(ci: CanvasItem, c: Vector2, dir: Vector2, length: float, col: Color, w: float) -> void:
	var d: Vector2 = dir.normalized() if dir.length_squared() > 1e-6 else Vector2.RIGHT
	var a: Vector2 = c - d * length * 0.5
	var b: Vector2 = c + d * length * 0.5
	ci.draw_line(a, b, col, w, true)
	var n: Vector2 = d.orthogonal()
	ci.draw_line(b, b - d * length * 0.35 + n * length * 0.25, col, w, true)
	ci.draw_line(b, b - d * length * 0.35 - n * length * 0.25, col, w, true)


# --- artillery -----------------------------------------------------------------
# Area: dashed outline with corner brackets and a salvo countdown. Strikes: the
# public telegraphs (ArenaEnv.artillery_state) in neutral caution yellow with a
# filling disc, crosshair, falling shell and impact countdown.
static func _draw_artillery(ci: CanvasItem, h: Dictionary, col: Color, s: float, o: Vector2, t: float, detail: int, anim: float, env: ArenaEnv) -> void:
	var box: Rect2 = _hazard_box(h)
	var rect: = Rect2(_p(box.position, s, o), box.size * s)
	var circle: bool = str(h.get("shape", "rect")) == "circle"
	var period: float = maxf(0.2, float(h.get("period", 8.0)))
	var phase: float = float(h.get("phase", 0.0))
	var warn: float = Arena.artillery_warning(h)
	var cycle: int = int(floor((t + phase) / period))
	var impact: float = Arena.artillery_impact_time(h, cycle)
	var announce: float = impact - warn
	var to_salvo: float = announce - t
	if to_salvo < 0.0:
		to_salvo = Arena.artillery_impact_time(h, cycle + 1) - warn - t
	var soon: float = clampf(1.0 - to_salvo / 3.0, 0.0, 1.0)
	var lw: float = maxf(1.0, 2.0 * s)
	if circle:
		var c: Vector2 = rect.get_center()
		var r: float = rect.size.x * 0.5
		ci.draw_circle(c, r, Color(col, 0.045 + 0.05 * soon))
		_dashed_arc(ci, c, r, Color(col, 0.6 + 0.3 * soon), lw, 36)
	else:
		ci.draw_rect(rect, Color(col, 0.045 + 0.05 * soon))
		_dashed_rect(ci, rect, Color(col, 0.6 + 0.3 * soon), lw, maxf(3.0, 12.0 * s))
		var br: float = minf(minf(rect.size.x, rect.size.y) * 0.18, 34.0 * s)
		var bc: = Color(col.lightened(0.2), 0.95)
		var bw: float = maxf(1.5, 3.0 * s)
		for cx in 2:
			for cy in 2:
				var corner: = Vector2(rect.position.x if cx == 0 else rect.end.x, rect.position.y if cy == 0 else rect.end.y)
				var sx: float = 1.0 if cx == 0 else -1.0
				var sy: float = 1.0 if cy == 0 else -1.0
				ci.draw_line(corner, corner + Vector2(br * sx, 0), bc, bw)
				ci.draw_line(corner, corner + Vector2(0, br * sy), bc, bw)
	var ctr: Vector2 = rect.get_center()
	var cr: float = maxf(4.0, 14.0 * s)
	ci.draw_arc(ctr, cr, 0, TAU, 24, Color(col, 0.55), maxf(1.0, 1.5 * s), true)
	ci.draw_line(ctr - Vector2(cr * 1.5, 0), ctr + Vector2(cr * 1.5, 0), Color(col, 0.55), maxf(1.0, 1.5 * s))
	ci.draw_line(ctr - Vector2(0, cr * 1.5), ctr + Vector2(0, cr * 1.5), Color(col, 0.55), maxf(1.0, 1.5 * s))
	if detail >= 2 and env != null:
		ci.draw_arc(ctr, cr + 5.0, -PI * 0.5, -PI * 0.5 + TAU * clampf(1.0 - to_salvo / period, 0.0, 1.0), 32, Color(col.lightened(0.3), 0.85), 2.0, true)
		var top: Vector2 = Vector2(ctr.x, rect.position.y + 18.0 * text_zoom) if not circle else ctr - Vector2(0, rect.size.y * 0.5 - 18.0 * text_zoom)
		label2(ci, top, "포격 예고 ", sec_str(to_salvo), Color(col.lightened(0.3), 0.9), Color(ART_COL, 0.6 + 0.4 * soon), 12)
	if env == null:
		return
	var id: String = str(h.get("id", ""))
	for st in env.artillery_state():
		if str(st.id) != id:
			continue
		_draw_strike(ci, _p(st.pos, s, o), float(st.radius) * s, float(st.warn_t), float(st.impact_t), t, s, anim, detail)


static func _draw_strike(ci: CanvasItem, c: Vector2, r: float, warn_t: float, impact_t: float, t: float, s: float, anim: float, detail: int) -> void:
	var span: float = maxf(0.05, impact_t - warn_t)
	var k: float = clampf((t - warn_t) / span, 0.0, 1.0)
	var left: float = maxf(0.0, impact_t - t)
	var blink: float = 0.5 + 0.5 * sin(anim * (10.0 + 18.0 * k))
	ci.draw_circle(c, r, Color(ART_COL, 0.08 + 0.1 * k))
	ci.draw_circle(c, r * k, Color(ART_COL, 0.16 + 0.12 * k))
	# caution stripes along the rim
	var seg: int = 16
	for i in seg:
		if i % 2 == 1:
			continue
		var a0: float = TAU * float(i) / float(seg) + anim * 0.6
		ci.draw_arc(c, r - 3.0 * s, a0, a0 + TAU / float(seg), 6, Color(ART_COL, 0.55 + 0.35 * blink), maxf(1.5, 5.0 * s), true)
	ci.draw_arc(c, r, 0, TAU, 56, Color(INK, 0.85), maxf(2.0, 4.5 * s), true)
	ci.draw_arc(c, r, -PI * 0.5, -PI * 0.5 + TAU * k, 56, ART_COL, maxf(1.5, 2.6 * s), true)
	var cr: float = r * 0.32
	ci.draw_line(c - Vector2(cr, 0), c + Vector2(cr, 0), Color(INK, 0.9), maxf(1.5, 3.5 * s))
	ci.draw_line(c - Vector2(0, cr), c + Vector2(0, cr), Color(INK, 0.9), maxf(1.5, 3.5 * s))
	ci.draw_line(c - Vector2(cr, 0), c + Vector2(cr, 0), ART_COL, maxf(1.0, 1.6 * s))
	ci.draw_line(c - Vector2(0, cr), c + Vector2(0, cr), ART_COL, maxf(1.0, 1.6 * s))
	# falling shell: drops onto the mark as impact approaches
	var drop: float = (1.0 - k) * 150.0 * s
	var shell: Vector2 = c - Vector2(0, drop)
	ci.draw_circle(c, maxf(2.0, 6.0 * s * (0.4 + 0.6 * k)), Color(0, 0, 0, 0.35 * k))
	if drop > 2.0:
		ci.draw_line(shell - Vector2(0, 22.0 * s), shell, Color(ART_COL, 0.35), maxf(1.0, 3.0 * s), true)
	ci.draw_circle(shell, maxf(2.0, 5.0 * s), Color(INK, 0.95))
	ci.draw_circle(shell, maxf(1.0, 3.2 * s), Color(1.6, 1.25, 0.6, 1.0))
	if detail >= 1:
		label(ci, c + Vector2(0, -r - 6.0 * text_zoom), num_str(left), Color(ART_COL, 1.0), 14)


# --- jump pads -----------------------------------------------------------------
# Lift (world px) of the flight arc at progress k; shared with the flight fx and
# the hero drawing so the dashed preview, the trail and the hero line up.
static func leap_height(dist: float) -> float:
	return clampf(dist * 0.2, 24.0, 90.0)


static func leap_point(from: Vector2, to: Vector2, k: float, height: float) -> Vector2:
	return from.lerp(to, k) - Vector2(0.0, sin(PI * k) * height)


static func _draw_jump_pad(ci: CanvasItem, h: Dictionary, col: Color, s: float, o: Vector2, detail: int, anim: float) -> void:
	var c: Vector2 = _p(h.center, s, o)
	var r: float = float(h.get("radius", 30.0)) * s
	var land_w: Vector2 = h.get("landing", h.center)
	var land: Vector2 = _p(land_w, s, o)
	var dir: Vector2 = (land - c).normalized() if land.distance_squared_to(c) > 1.0 else Vector2.UP
	var height: float = leap_height((h.center as Vector2).distance_to(land_w)) * s
	# trajectory preview (dashed) and landing marker
	var n: int = 22
	var prev: Vector2 = c
	for i in range(1, n + 1):
		var q: Vector2 = leap_point(c, land, float(i) / float(n), height)
		if i % 2 == 1:
			ci.draw_line(prev, q, Color(col, 0.42 if detail >= 1 else 0.6), maxf(1.0, 1.6 * s), true)
		prev = q
	var lr: float = maxf(3.0, 20.0 * s)
	_dashed_arc(ci, land, lr, Color(col, 0.75), maxf(1.0, 1.8 * s), 10, anim * 0.4)
	ci.draw_line(land + Vector2(-lr, -lr) * 0.45, land + Vector2(lr, lr) * 0.45, Color(col, 0.7), maxf(1.0, 1.6 * s))
	ci.draw_line(land + Vector2(lr, -lr) * 0.45, land + Vector2(-lr, lr) * 0.45, Color(col, 0.7), maxf(1.0, 1.6 * s))
	# pad body
	ci.draw_circle(c, r, Color(col.darkened(0.62), 0.92))
	ci.draw_arc(c, r, 0, TAU, 40, Color(col, 0.95), maxf(1.0, 2.2 * s), true)
	ci.draw_arc(c, r * 0.72, 0, TAU, 32, Color(col, 0.35), maxf(1.0, 1.2 * s), true)
	if detail >= 1:
		var pk: float = fposmod(anim * 0.9, 1.0)
		ci.draw_arc(c, r * (0.3 + 0.7 * pk), 0, TAU, 32, Color(col.lightened(0.3), 0.6 * (1.0 - pk)), maxf(1.0, 1.5 * s), true)
	var nrm: Vector2 = dir.orthogonal()
	for k in 2:
		var tip: Vector2 = c + dir * r * (-0.05 + 0.5 * float(k))
		var back: Vector2 = tip - dir * r * 0.4
		var cc: = Color(col.lightened(0.35), 0.95 if k == 1 else 0.6)
		ci.draw_line(back + nrm * r * 0.5, tip, cc, maxf(1.5, 3.4 * s), true)
		ci.draw_line(back - nrm * r * 0.5, tip, cc, maxf(1.5, 3.4 * s), true)


# --- closing ring ----------------------------------------------------------------
static func _draw_ring(ci: CanvasItem, arena: Arena, h: Dictionary, idx: int, col: Color, s: float, o: Vector2, t: float, detail: int, anim: float) -> void:
	var c: Vector2 = _p(h.center, s, o)
	var t0: float = float(h.get("startTime", 60.0))
	var t1: float = maxf(t0, float(h.get("endTime", t0 + 30.0)))
	var r_end: float = maxf(0.0, float(h.get("endRadius", 200.0))) * s
	var inner: Rect2 = _inner(arena, s, o)
	if t < t0:
		# Preview: the final safe zone and the countdown to the start.
		var warn: float = maxf(0.0, float(h.get("warningDuration", 5.0)))
		var urgent: bool = t0 - t <= warn
		var blink: float = (0.5 + 0.5 * sin(anim * 9.0)) if urgent else 0.0
		ci.draw_circle(c, r_end, Color(col, 0.03 + 0.04 * blink))
		_dashed_arc(ci, c, r_end, Color(col, 0.45 + 0.4 * blink), maxf(1.0, 2.0 * s), 40, anim * 0.05)
		if detail >= 2:
			var y: float = maxf(inner.position.y + 16.0 * text_zoom, c.y - r_end - 8.0 * text_zoom)
			label2(ci, Vector2(c.x, y), "결계 수축까지 ", sec_str(t0 - t), Color(col.lightened(0.35), 0.75 + 0.25 * blink), Color(1, 1, 1, 0.8 + 0.2 * blink), 13)
		return
	var r: float = Arena.ring_radius_at(h, t) * s
	var geo: Dictionary = _ring_geometry(arena, h, idx, r, c, inner, s, o)
	for poly in geo.outside:
		ci.draw_colored_polygon(poly, Color(col.darkened(0.35), 0.17))
	for seg in geo.edge:
		ci.draw_polyline(seg, Color(INK, 0.8), maxf(2.0, 6.0 * s), true)
		ci.draw_polyline(seg, Color(col.lightened(0.15), 0.95), maxf(1.5, 2.6 * s), true)
	if r - r_end > 2.0 * s:
		_dashed_arc(ci, c, r_end, Color(col, 0.4), maxf(1.0, 1.5 * s), 40)
	# inward chevrons on the boundary (inside the arena only)
	if detail >= 1:
		var shift: float = fposmod(anim * 0.15, TAU / 12.0)
		for i in 12:
			var ang: float = shift + TAU * float(i) / 12.0
			var d: Vector2 = Vector2.from_angle(ang)
			var p: Vector2 = c + d * (r + 14.0 * s)
			if not inner.has_point(p):
				continue
			var nrm: Vector2 = d.orthogonal()
			var tip: Vector2 = p - d * 9.0 * s
			ci.draw_line(p + nrm * 7.0 * s, tip, Color(col.lightened(0.3), 0.85), maxf(1.0, 2.2 * s), true)
			ci.draw_line(p - nrm * 7.0 * s, tip, Color(col.lightened(0.3), 0.85), maxf(1.0, 2.2 * s), true)
	if detail >= 2:
		var y2: float = maxf(inner.position.y + 16.0 * text_zoom, c.y - r - 10.0 * text_zoom)
		if t < t1:
			label2(ci, Vector2(c.x, y2), "결계 수축 중 · 최종까지 ", sec_str(t1 - t), Color(col.lightened(0.35), 0.95), Color(1, 1, 1, 0.95), 13)
		else:
			label(ci, Vector2(c.x, y2), "최종 결계 · 바깥은 피해", Color(col.lightened(0.35), 0.95), 13)


# Outside-of-ring polygons (arena minus the safe circle, split at the centre row
# so no piece has a hole) and the boundary segments inside the arena. Cached
# per hazard for the battle view (s = 1) in 2 px radius steps.
static func _ring_geometry(arena: Arena, h: Dictionary, idx: int, r: float, c: Vector2, inner: Rect2, s: float, o: Vector2) -> Dictionary:
	var cacheable: bool = s == 1.0 and o == Vector2.ZERO
	var key: int = arena.get_instance_id() * 64 + idx
	var rq: int = int(roundf(r * 0.5))
	if cacheable and _ring_cache.has(key):
		var hit: Dictionary = _ring_cache[key]
		if int(hit.rq) == rq:
			return hit
	var rr: float = float(rq) * 2.0 if cacheable else r
	var circ: = PackedVector2Array()
	for i in 96:
		circ.append(c + Vector2.from_angle(TAU * float(i) / 96.0) * maxf(1.0, rr))
	var outside: Array = []
	var cy: float = clampf(c.y, inner.position.y, inner.end.y)
	for half in [Rect2(inner.position, Vector2(inner.size.x, cy - inner.position.y)), Rect2(Vector2(inner.position.x, cy), Vector2(inner.size.x, inner.end.y - cy))]:
		var hr: Rect2 = half
		if hr.size.y < 0.5:
			continue
		var poly: = PackedVector2Array([hr.position, Vector2(hr.end.x, hr.position.y), hr.end, Vector2(hr.position.x, hr.end.y)])
		for piece in Geometry2D.clip_polygons(poly, circ):
			if (piece as PackedVector2Array).size() >= 3:
				outside.append(piece)
	var loop: = circ.duplicate()
	loop.append(circ[0])
	var rect_poly: = PackedVector2Array([inner.position, Vector2(inner.end.x, inner.position.y), inner.end, Vector2(inner.position.x, inner.end.y)])
	var edge: Array = Geometry2D.intersect_polyline_with_polygon(loop, rect_poly)
	var geo: Dictionary = {"rq": rq, "outside": outside, "edge": edge}
	if cacheable:
		_ring_cache[key] = geo
	return geo


# --- gates -----------------------------------------------------------------------
# Per-frame gates of a battle arena (battle copy state, developer switches).
static func draw_gates(ci: CanvasItem, arena: Arena, s: float, o: Vector2, t: float, detail: int = 2, anim: float = 0.0, env: ArenaEnv = null) -> void:
	if arena.gates.is_empty():
		return
	var on: bool = env == null or env.type_active("gate")
	for k in arena.gates.size():
		var g: Dictionary = arena.gates[k]
		var vis: Vector3 = gate_visual(arena, k, t, on)
		_draw_gate(ci, g, obstacle_color(arena.obstacles[int(g.obs)]), s, o, int(vis.x), vis.y if on else -1.0, vis.z, anim, detail)


# Visual state of gate slot k at time t: x = 0 closed / 1 open / 2 closing warning,
# y = seconds until it changes, z = progress 0..1 through the warning window.
# The open/closed state follows the live battle copy (developer switches, the
# engine's own transitions); shared arenas use the authored schedule.
static func gate_visual(arena: Arena, k: int, t: float, on: bool = true) -> Vector3:
	var g: Dictionary = arena.gates[k]
	var period: float = float(g.period)
	var open_d: float = float(g.openDuration)
	var warn: float = float(g.warningDuration)
	var shifted: float = fposmod(t + float(g.phase), period)
	var clock_open: bool = shifted < open_d
	var remaining: float = (open_d - shifted) if clock_open else (period - shifted)
	var open: bool
	if not on:
		open = true
	elif arena.battle_copy or arena.gate_bits != 0:
		open = arena.gate_slot_open(k)
	else:
		open = clock_open
	if not open:
		return Vector3(0.0, remaining, 0.0)
	if on and clock_open and remaining <= warn and open_d < period:
		return Vector3(2.0, remaining, 1.0 - remaining / maxf(0.01, warn))
	return Vector3(1.0, remaining, 0.0)


# state 0 closed, 1 open, 2 closing warning (frac 0..1 of the warning window).
# remaining < 0 hides the countdown (cards, switched off).
static func _draw_gate(ci: CanvasItem, g: Dictionary, col: Color, s: float, o: Vector2, state: int, remaining: float, frac: float, anim: float, detail: int) -> void:
	var wr: Rect2 = g.rect
	var rect: = Rect2(_p(wr.position, s, o), wr.size * s)
	var horizontal: bool = rect.size.x >= rect.size.y
	var thick: float = minf(rect.size.x, rect.size.y)
	var bar_w: float = maxf(1.0, 2.6 * s)
	var spacing: float = maxf(3.0, 10.0 * s)
	match state:
		0:
			if detail >= 1:
				ci.draw_rect(Rect2(rect.position + Vector2(4, 6) * s, rect.size), Color(0, 0, 0, 0.32))
			ci.draw_rect(rect, Color(col.darkened(0.58), 0.97))
			_gate_bars(ci, rect, horizontal, spacing, Color(col.lightened(0.18), 0.95), bar_w, 1.0)
			var mid_w: float = maxf(1.0, 3.0 * s)
			if horizontal:
				ci.draw_line(Vector2(rect.position.x, rect.get_center().y), Vector2(rect.end.x, rect.get_center().y), Color(col.darkened(0.15), 0.95), mid_w)
			else:
				ci.draw_line(Vector2(rect.get_center().x, rect.position.y), Vector2(rect.get_center().x, rect.end.y), Color(col.darkened(0.15), 0.95), mid_w)
			ci.draw_rect(rect, Color(col.lightened(0.38), 1.0), false, maxf(1.0, 2.0 * s))
		1:
			ci.draw_rect(rect, Color(GATE_OPEN, 0.06))
			_dashed_rect(ci, rect, Color(GATE_OPEN, 0.55), maxf(1.0, 1.5 * s), maxf(3.0, 8.0 * s))
			_gate_bars(ci, rect, horizontal, spacing, Color(col.lightened(0.18), 0.6), bar_w, 0.16)
		2:
			var blink: float = 0.5 + 0.5 * sin(anim * 16.0)
			ci.draw_rect(rect, Color(GATE_WARN, 0.12 + 0.2 * blink))
			_gate_bars(ci, rect, horizontal, spacing, Color(col.lightened(0.18), 0.9), bar_w, 0.16 + 0.84 * frac)
			ci.draw_rect(rect, Color(GATE_WARN, 0.65 + 0.35 * blink), false, maxf(1.5, 2.6 * s))
	# posts at both ends of the opening
	var post: float = maxf(3.0, thick * 0.9)
	var pc: = Color(col.lightened(0.05), 1.0)
	var e0: Vector2 = Vector2(rect.position.x, rect.get_center().y) if horizontal else Vector2(rect.get_center().x, rect.position.y)
	var e1: Vector2 = Vector2(rect.end.x, rect.get_center().y) if horizontal else Vector2(rect.get_center().x, rect.end.y)
	var post_box: Vector2 = Vector2(post, post)
	ci.draw_rect(Rect2(e0 - post_box * 0.5, post_box), Color(col.darkened(0.4), 1.0))
	ci.draw_rect(Rect2(e0 - post_box * 0.5, post_box), pc, false, maxf(1.0, 1.4 * s))
	ci.draw_rect(Rect2(e1 - post_box * 0.5, post_box), Color(col.darkened(0.4), 1.0))
	ci.draw_rect(Rect2(e1 - post_box * 0.5, post_box), pc, false, maxf(1.0, 1.4 * s))
	if detail >= 2 and remaining >= 0.0:
		var c: Vector2 = rect.get_center()
		var tag: Vector2 = c + (Vector2(0, -thick * 0.5 - 12.0 * text_zoom) if horizontal else Vector2(thick * 0.5 + 16.0 * text_zoom, 0))
		match state:
			0:
				var open_col: = Color(GATE_OPEN, 0.95 if remaining <= 3.0 else 0.7)
				label2(ci, tag, "열림 ", sec_str(remaining), open_col, Color(1, 1, 1, 0.9 if remaining <= 3.0 else 0.65), 12)
			2:
				label2(ci, tag, "닫힘 ", sec_str(remaining), Color(GATE_WARN, 1.0), Color(1, 1, 1, 1.0), 13)
		label(ci, e0 + (Vector2(0, post * 0.5 + 11.0 * text_zoom)), str(g.group), Color(col.lightened(0.4), 0.8), 10)


# Portcullis bars across the thin axis; amount 0..1 = how far they are lowered.
static func _gate_bars(ci: CanvasItem, rect: Rect2, horizontal: bool, spacing: float, col: Color, w: float, amount: float) -> void:
	if amount <= 0.0:
		return
	if horizontal:
		var x: float = rect.position.x + spacing * 0.5
		var y1: float = rect.position.y + rect.size.y * amount
		while x < rect.end.x:
			ci.draw_line(Vector2(x, rect.position.y), Vector2(x, y1), col, w)
			x += spacing
	else:
		var y: float = rect.position.y + spacing * 0.5
		var x1: float = rect.position.x + rect.size.x * amount
		while y < rect.end.y:
			ci.draw_line(Vector2(rect.position.x, y), Vector2(x1, y), col, w)
			y += spacing


static func _draw_spike_teeth(ci: CanvasItem, h: Dictionary, s: float, o: Vector2, col: Color, active: bool) -> void :
	if str(h.get("shape", "rect")) == "circle":
		return
	var x0: = float(h.x)
	var y0: = float(h.y)
	var w: = float(h.w)
	var hh: = float(h.h)
	var step: = 26.0
	var rows: = maxi(1, int(hh / step))
	var cols: = maxi(1, int(w / step))
	var height: = 9.0 if active else 4.0
	var tooth: = Color(col.lightened(0.3), 0.95 if active else 0.45)
	for i in cols:
		for j in rows:
			var cx: = x0 + (i + 0.5) * w / cols
			var cy: = y0 + (j + 0.5) * hh / rows
			var base: = _p(Vector2(cx, cy + 5), s, o)
			var tip: = _p(Vector2(cx, cy + 5 - height), s, o)
			var half: = 5.0 * s
			ci.draw_line(base + Vector2(-half, 0), tip, tooth, maxf(1.0, 2.0 * s), true)
			ci.draw_line(tip, base + Vector2(half, 0), tooth, maxf(1.0, 2.0 * s), true)
			ci.draw_line(base + Vector2(-half, 0), base + Vector2(half, 0), tooth, maxf(1.0, 1.5 * s), true)


static func _draw_wind_streaks(ci: CanvasItem, h: Dictionary, s: float, o: Vector2, col: Color, dir: Vector2, anim: float, detail: int) -> void :
	if str(h.get("shape", "rect")) == "circle":
		return
	var x0: = float(h.x)
	var y0: = float(h.y)
	var w: = float(h.w)
	var hh: = float(h.h)
	var n: = 14 if detail >= 2 else 6
	var seed_base: int = hash(str(h.get("id", "w")))
	var speed: = 140.0
	for i in n:
		# Deterministic per-streak hash noise (no RandomNumberGenerator per frame).
		var fx: = _hash01(seed_base, i * 4)
		var fy: = _hash01(seed_base, i * 4 + 1)
		var len_: = 22.0 + _hash01(seed_base, i * 4 + 2) * 26.0
		var p: = Vector2(x0 + fx * w, y0 + fy * hh)
		var travel: = fmod(anim * speed + _hash01(seed_base, i * 4 + 3) * 400.0, maxf(w, hh) + 60.0)
		p += dir * travel
		p.x = x0 + fposmod(p.x - x0, w)
		p.y = y0 + fposmod(p.y - y0, hh)
		var a: = _p(p, s, o)
		var b: = _p(p - dir * len_, s, o)
		ci.draw_line(a, b, Color(col.lightened(0.2), 0.45), maxf(1.0, 1.6 * s), true)
		ci.draw_circle(a, 1.6 * s, Color(col.lightened(0.4), 0.7))


static func _hash01(seed_base: int, i: int) -> float:
	var x: int = (seed_base ^ (i * 374761393)) & 0x7fffffff
	x = ((x ^ (x >> 13)) * 1274126177) & 0x7fffffff
	x = x ^ (x >> 16)
	return float(x & 0xffff) / 65535.0
