class_name Minimap
extends Control
## Battleground minimap (bottom-right of the arena area, DEFAULT_SIZE 240x147). set_arena() paints
## the static map ONCE into a texture at TEX_SCALE (about 1/24 of the world): floor, water / lava
## / mud, forests, buildings and walls. Zone, dots and camera frame are drawn over it and only
## redraw when they change. The map keeps its aspect inside the frame (map_rect). A left click or
## drag on the map emits world_clicked(world position). Mode-independent: it never reads the
## simulation, so the caller decides what the viewer may know.
##
## Input:
##   set_arena(arena: Arena)        static layer, built once per arena (rebuild only on a new map)
##   set_zone(view: Dictionary)     BrZone.public_view(t) (DESIGN_V2 §3.3): center: Vector2,
##                                  radius: float, next_center: Vector2, next_radius: float,
##                                  next_known: bool. Current circle solid, next circle dashed
##                                  (only when next_known), outside tinted. {} clears.
##   set_dots(dots: Array)          [{pos: Vector2 (world), color: Color, kind: "hero" | "downed" |
##                                  "item" | "death"}]; already filtered by fog / perspective.
##   set_camera_rect(rect: Rect2)   world rectangle the battle view shows; Rect2() hides it.

signal world_clicked(pos: Vector2)

const DEFAULT_SIZE: = Vector2(240, 147)
const TEX_SCALE: = 1.0 / 24.0
## The static layer is drawn at SUPERSAMPLE x TEX_SCALE and filtered down (smooth edges).
const SUPERSAMPLE: = 2
const INSET: = 3.0
const ZONE_EDGE: = Color(0.92, 0.95, 1.0, 0.95)
const ZONE_NEXT: = Color(1.0, 1.0, 1.0, 0.85)
const OUTSIDE_TINT: = Color(0.44, 0.11, 0.31, 0.38)
const WATER: = Color("#1d4f78")
const LAVA: = Color("#7a2a12")
const VOID: = Color("#05070b")
const FOREST: = Color("#28663a")
const BUILDING: = Color("#5c4932")

var arena: Arena
var texture: ImageTexture
## Map area inside the frame (local coordinates), aspect kept.
var map_rect: Rect2 = Rect2()
var zone: Dictionary = {}
var dots: Array = []
var camera_rect: Rect2 = Rect2()
## Milliseconds the last static raster took (tests and the perf log).
var build_ms: float = 0.0

var _dragging: bool = false
var _last_emit: Vector2 = Vector2(-1, -1)
# Map layer: a child clipped to map_rect, so the zone tint and dots never spill onto the frame.
var _layer: Control


func _init() -> void:
	custom_minimum_size = DEFAULT_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = UITheme.tip("미니맵 — 누르거나 끌면 그 위치로 카메라를 옮깁니다.")
	_layer = Control.new()
	_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.clip_contents = true
	_layer.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_layer.draw.connect(_draw_layer)
	add_child(_layer)


## Size that wraps arena's aspect inside max_size (frame inset included), for callers that want
## no letterbox.
static func fit_size(a: Arena, max_size: Vector2 = DEFAULT_SIZE) -> Vector2:
	if a == null or a.width <= 0.0 or a.height <= 0.0:
		return max_size
	var inner: = max_size - Vector2(INSET, INSET) * 2.0
	var s: float = minf(inner.x / a.width, inner.y / a.height)
	return Vector2(ceilf(a.width * s + INSET * 2.0), ceilf(a.height * s + INSET * 2.0))


func set_arena(a: Arena) -> void:
	if a == arena and texture != null:
		return
	arena = a
	texture = null
	if a != null:
		var t0: int = Time.get_ticks_usec()
		texture = ImageTexture.create_from_image(rasterize(a))
		build_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	_layout()
	queue_redraw()


func set_zone(view: Dictionary) -> void:
	if view == zone:
		return
	zone = view
	_layer.queue_redraw()


func set_dots(list: Array) -> void:
	dots = list
	_layer.queue_redraw()


func set_camera_rect(r: Rect2) -> void:
	if r == camera_rect:
		return
	camera_rect = r
	_layer.queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout()


func _layout() -> void:
	var inner: = Rect2(Vector2(INSET, INSET), size - Vector2(INSET, INSET) * 2.0)
	if arena == null or arena.width <= 0.0 or arena.height <= 0.0 or inner.size.x <= 0.0 or inner.size.y <= 0.0:
		map_rect = inner
	else:
		var s: float = minf(inner.size.x / arena.width, inner.size.y / arena.height)
		var ms: = Vector2(arena.width, arena.height) * s
		map_rect = Rect2((inner.position + (inner.size - ms) * 0.5).round(), ms)
	_layer.position = map_rect.position
	_layer.size = map_rect.size
	_layer.queue_redraw()
	queue_redraw()


## Minimap pixels per world pixel at the current size.
func map_scale() -> float:
	return map_rect.size.x / arena.width if arena != null and arena.width > 0.0 else 0.0


func world_to_map(p: Vector2) -> Vector2:
	return map_rect.position + p * map_scale()


func map_to_world(p: Vector2) -> Vector2:
	var s: float = map_scale()
	if s <= 0.0:
		return Vector2.ZERO
	var w: = (p - map_rect.position) / s
	return Vector2(clampf(w.x, 0.0, arena.width), clampf(w.y, 0.0, arena.height))


func _gui_input(event: InputEvent) -> void:
	if arena == null:
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb: = event as InputEventMouseButton
		_dragging = mb.pressed and map_rect.has_point(mb.position)
		if _dragging:
			# A new press always emits, even on the spot of the previous one.
			_last_emit = Vector2(-1e9, -1e9)
			_emit(mb.position)
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_emit((event as InputEventMouseMotion).position)
		accept_event()


func _emit(local: Vector2) -> void:
	var p: = map_to_world(local.clamp(map_rect.position, map_rect.end))
	if p.distance_to(_last_emit) < 1.0:
		return
	_last_emit = p
	world_clicked.emit(p)


# ------------------------------------------------------------------ static layer (CPU raster)

## Paints the static map into an Image of about arena size x TEX_SCALE (mipmapped). Rect fills
## and per-row circle spans are native Image calls, so a 7700x4300 map with 600 obstacles and 200
## forest circles takes a few milliseconds. Draw order: floor, water / mud / lava, forests,
## buildings, walls; low fences and hedges are blended with the floor.
static func rasterize(a: Arena) -> Image:
	var k: float = TEX_SCALE * SUPERSAMPLE
	var w: int = maxi(8, ceili(a.width * k - 0.001))
	var h: int = maxi(8, ceili(a.height * k - 0.001))
	var fc: = ArenaPainter.floor_colors(a)
	var base: Color = fc.base
	var img: = Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	img.fill(base.darkened(0.45))
	_fill_rect(img, Rect2(a.min_x, a.min_y, a.max_x - a.min_x, a.max_y - a.min_y), k, base.lightened(0.04))
	for hz in a.hazards:
		var typ: String = str(hz.get("type", ""))
		var col: Color
		match typ:
			"mud":
				col = Color(str(hz.get("color", "#8a6a45"))).darkened(0.35)
			"water":
				col = WATER
			"lava":
				col = LAVA
			"healing_fountain":
				col = Color(UITheme.GOOD, 1.0).darkened(0.35)
			_:
				continue
		_fill_shape(img, hz, k, col)
	for i in a.obs_count:
		var od: Dictionary = a.obstacles[i]
		if str(od.get("kind", "")) != "chasm":
			continue
		var mat: String = str(od.get("material", "void"))
		_fill_shape(img, od, k, WATER if mat == "water" else (LAVA if mat == "lava" else VOID))
	for j in a.forest_x.size():
		_fill_circle(img, Vector2(a.forest_x[j], a.forest_y[j]), a.forest_r[j], k, FOREST)
	for b in a.data.get("buildings", []):
		var br: = Rect2(float(b.get("x", 0.0)), float(b.get("y", 0.0)), float(b.get("w", 0.0)), float(b.get("h", 0.0)))
		_fill_rect(img, br, k, BUILDING)
	for i in a.obs_count:
		var od2: Dictionary = a.obstacles[i]
		var kind: String = str(od2.get("kind", "wall"))
		if kind == "chasm":
			continue
		var col2: Color = ArenaPainter.obstacle_color(od2).lightened(0.18)
		if kind == "lattice" or kind == "hedge" or (a.obs_mask_full[i] & Arena.MASK_VISION) == 0:
			col2 = col2.lerp(base, 0.45)
		if a.obs_circle[i] == 1:
			_fill_circle(img, Vector2(a.obs_x[i], a.obs_y[i]), maxf(a.obs_r[i], 0.75 / k), k, col2)
		else:
			_fill_rect(img, Rect2(a.obs_x[i], a.obs_y[i], a.obs_w[i], a.obs_h[i]), k, col2)
	img.resize(maxi(4, floori(float(w) / SUPERSAMPLE)), maxi(4, floori(float(h) / SUPERSAMPLE)), Image.INTERPOLATE_BILINEAR)
	img.generate_mipmaps()
	return img


static func _fill_shape(img: Image, d: Dictionary, k: float, col: Color) -> void:
	if str(d.get("shape", "rect")) == "circle":
		_fill_circle(img, Vector2(float(d.get("x", 0.0)), float(d.get("y", 0.0))), float(d.get("radius", 30.0)), k, col)
	else:
		_fill_rect(img, Rect2(float(d.get("x", 0.0)), float(d.get("y", 0.0)), float(d.get("w", 0.0)), float(d.get("h", 0.0))), k, col)


# World rect -> image pixels; at least one pixel so thin walls stay visible.
static func _fill_rect(img: Image, r: Rect2, k: float, col: Color) -> void:
	var x0: int = floori(r.position.x * k)
	var y0: int = floori(r.position.y * k)
	var x1: int = maxi(x0 + 1, roundi(r.end.x * k))
	var y1: int = maxi(y0 + 1, roundi(r.end.y * k))
	var rect: = Rect2i(x0, y0, x1 - x0, y1 - y0).intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
	if rect.size.x > 0 and rect.size.y > 0:
		img.fill_rect(rect, col)


static func _fill_circle(img: Image, c: Vector2, r: float, k: float, col: Color) -> void:
	var cx: float = c.x * k
	var cy: float = c.y * k
	var rr: float = maxf(0.5, r * k)
	var y0: int = maxi(0, floori(cy - rr))
	var y1: int = mini(img.get_height() - 1, ceili(cy + rr))
	for y in range(y0, y1 + 1):
		var dy: float = float(y) + 0.5 - cy
		if absf(dy) > rr:
			continue
		var half: float = sqrt(rr * rr - dy * dy)
		var x0: int = maxi(0, roundi(cx - half))
		var x1: int = mini(img.get_width(), roundi(cx + half))
		if x1 > x0:
			img.fill_rect(Rect2i(x0, y, x1 - x0, 1), col)




# ------------------------------------------------------------------ dynamic layers

func _draw() -> void:
	draw_style_box(UITheme.sbc(Color(0.02, 0.03, 0.05, 0.94), UITheme.LINE2, UITheme.R_S, 1, 0), Rect2(Vector2.ZERO, size))
	if arena == null or texture == null:
		draw_string(DB.font_regular, Vector2(0, size.y * 0.5 + 4.0), "지도 없음", HORIZONTAL_ALIGNMENT_CENTER, size.x, UITheme.MIN_FS, UITheme.TEXT_FAINT)


# Layer coordinates: (0, 0) is the map's top-left corner, world * map_scale().
func _draw_layer() -> void:
	if arena == null or texture == null:
		return
	var ci: Control = _layer
	var s: float = map_scale()
	ci.draw_texture_rect(texture, Rect2(Vector2.ZERO, map_rect.size), false)
	_draw_zone(ci, s)
	for d in dots:
		_draw_dot(ci, d, s)
	if camera_rect.size.x > 0.0 and camera_rect.size.y > 0.0:
		var cr: = Rect2(camera_rect.position * s, camera_rect.size * s)
		ci.draw_rect(cr.grow(1.0), Color(0, 0, 0, 0.55), false, 1.0)
		ci.draw_rect(cr, Color(1, 1, 1, 0.92), false, 1.0)
	ci.draw_rect(Rect2(Vector2.ZERO, map_rect.size), Color(1, 1, 1, 0.1), false, 1.0)


func _draw_zone(ci: Control, s: float) -> void:
	if zone.is_empty() or not zone.has("radius"):
		return
	var c: Vector2 = _v2(zone.get("center")) * s
	var r: float = maxf(0.0, float(zone.get("radius", 0.0)) * s)
	# Outside tint: a thick arc whose inner edge is the circle, reaching past the farthest map
	# corner; the clipped layer cuts it to the map.
	var far: float = 0.0
	for corner in [Vector2.ZERO, Vector2(map_rect.size.x, 0.0), map_rect.size, Vector2(0.0, map_rect.size.y)]:
		far = maxf(far, c.distance_to(corner))
	if r < far:
		if r < 0.75:
			ci.draw_rect(Rect2(Vector2.ZERO, map_rect.size), OUTSIDE_TINT)
		else:
			var band: float = far - r + 2.0
			ci.draw_arc(c, r + band * 0.5, 0, TAU, _segs(r), OUTSIDE_TINT, band, false)
	if r >= 0.75:
		ci.draw_arc(c, r, 0, TAU, _segs(r), Color(0, 0, 0, 0.5), 3.0, true)
		ci.draw_arc(c, r, 0, TAU, _segs(r), ZONE_EDGE, 1.5, true)
	if bool(zone.get("next_known", false)) and zone.has("next_radius"):
		var nc: Vector2 = _v2(zone.get("next_center")) * s
		var nr: float = maxf(0.0, float(zone.get("next_radius", 0.0)) * s)
		if nr >= 1.0:
			var n: int = clampi(int(nr * 0.45), 8, 40)
			for i in n:
				var a0: float = TAU * float(i) / n
				ci.draw_arc(nc, nr, a0, a0 + TAU / n * 0.55, 4, ZONE_NEXT, 1.2, true)
		else:
			ci.draw_circle(nc, 1.5, ZONE_NEXT, true, -1.0, true)


static func _segs(r: float) -> int:
	return clampi(int(r * 0.6), 32, 128)


static func _v2(v: Variant) -> Vector2:
	if v is Vector2:
		return v
	if v is Dictionary:
		return Vector2(float((v as Dictionary).get("x", 0.0)), float((v as Dictionary).get("y", 0.0)))
	return Vector2.ZERO


func _draw_dot(ci: Control, d: Dictionary, s: float) -> void:
	var p: Vector2 = _v2(d.get("pos")) * s
	if not Rect2(Vector2.ZERO, map_rect.size).grow(4.0).has_point(p):
		return
	var cv: Variant = d.get("color")
	var col: Color = cv if cv is Color else UITheme.TEXT
	match str(d.get("kind", "hero")):
		"hero":
			ci.draw_circle(p, 3.7, Color(0, 0, 0, 0.75), true, -1.0, true)
			ci.draw_circle(p, 2.7, col, true, -1.0, true)
		"downed":
			ci.draw_circle(p, 4.4, Color(0, 0, 0, 0.6), true, -1.0, true)
			ci.draw_arc(p, 3.1, 0, TAU, 14, col, 1.4, true)
			ci.draw_circle(p, 1.3, UITheme.BAD, true, -1.0, true)
		"item":
			var q: float = 2.4
			ci.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -q - 1.2), p + Vector2(q + 1.2, 0), p + Vector2(0, q + 1.2), p + Vector2(-q - 1.2, 0)]), Color(0, 0, 0, 0.6))
			ci.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -q), p + Vector2(q, 0), p + Vector2(0, q), p + Vector2(-q, 0)]), col)
		"death":
			var e: float = 2.5
			# Deaths stay quieter than the living: thin and translucent.
			ci.draw_line(p + Vector2(-e, -e), p + Vector2(e, e), Color(0, 0, 0, 0.45), 3.0, true)
			ci.draw_line(p + Vector2(e, -e), p + Vector2(-e, e), Color(0, 0, 0, 0.45), 3.0, true)
			ci.draw_line(p + Vector2(-e, -e), p + Vector2(e, e), Color(col, 0.7), 1.3, true)
			ci.draw_line(p + Vector2(e, -e), p + Vector2(-e, e), Color(col, 0.7), 1.3, true)
