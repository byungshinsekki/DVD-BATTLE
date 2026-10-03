extends SceneTree

# V1.5.3 layout atlas: renders every shipped map (12 elimination, 3 control,
# 3 deathmatch preview seeds) into one PNG, headless-safe (pure Image drawing,
# no window, no RenderingServer). Colour key: grey = solid walls, hatched =
# see-through cover, dark translucent = chasm/ravine/water (units only),
# amber = gates (A/B), green discs = brush, blue/red dots = spawns.
#
# Usage:
#   <godot> --headless --path <project> --script res://tools/map_atlas_153.gd -- \
#       [--out=res://reports/maps_153/layout_atlas_153.png] [--only=<id,id>] [--tile=600]

const BG: Color = Color("#0a0f16")
const TEXT: Color = Color("#dfe7f1")
const DIM: Color = Color("#8ea0b5")
const BLUE: Color = Color("#56a7ff")
const RED: Color = Color("#ff6d79")

const FONT: Dictionary = {
	"A": ".###.#...##...#######...##...##...#", "B": "####.#...##...#####.#...##...#####.",
	"C": ".###.#...##....#....#....#...#.###.", "D": "####.#...##...##...##...##...#####.",
	"E": "######....#....####.#....#....#####", "F": "######....#....####.#....#....#....",
	"G": ".###.#...##....#.####...##...#.####", "H": "#...##...##...#######...##...##...#",
	"I": ".###...#....#....#....#....#...###.", "J": "..###...#....#....#.#..#.#..#..##..",
	"K": "#...##..#.#.#..##...#.#..#..#.#...#", "L": "#....#....#....#....#....#....#####",
	"M": "#...###.###.#.##.#.##...##...##...#", "N": "#...##...###..##.#.##..###...##...#",
	"O": ".###.#...##...##...##...##...#.###.", "P": "####.#...##...#####.#....#....#....",
	"Q": ".###.#...##...##...##.#.##..#..##.#", "R": "####.#...##...#####.#.#..#..#.#...#",
	"S": ".#####....#.....###.....#....#####.", "T": "#####..#....#....#....#....#....#..",
	"U": "#...##...##...##...##...##...#.###.", "V": "#...##...##...##...##...#.#.#...#..",
	"W": "#...##...##...##.#.##.#.##.#.#.#.#.", "X": "#...##...#.#.#...#...#.#.#...##...#",
	"Y": "#...##...#.#.#...#....#....#....#..", "Z": "#####....#...#...#...#...#....#####",
	"0": ".###.#...##..###.#.###..##...#.###.", "1": "..#...##....#....#....#....#...###.",
	"2": ".###.#...#....#...#...#...#...#####", "3": "####.....#....#.###.....#....#####.",
	"4": "...#...##..#.#.#..#.#####...#....#.", "5": "######....####.....#....##...#.###.",
	"6": ".###.#....#....####.#...##...#.###.", "7": "#####....#...#...#...#....#....#...",
	"8": ".###.#...##...#.###.#...##...#.###.", "9": ".###.#...##...#.####....#....#.###.",
	" ": "...................................", "_": "..............................#####",
	"-": "................###................", ".": "..........................##...##..",
	":": "......##...##........##...##.......", "/": "....#....#...#...#...#...#....#....",
	"(": "...#...#...#....#....#.....#.....#.", ")": ".#.....#.....#....#....#...#...#...",
	"|": "..#....#....#....#....#....#....#..", "<": "...#...#...#...#.....#.....#.....#.",
	">": ".#.....#.....#.....#...#...#...#...", "=": "..........#####.....#####..........",
	"+": ".......#....#..#####..#....#.......", "%": "##..###..#...#...#...#...#..###..##",
	",": ".....................##....#...#...", "*": ".....#.#.#.###.#####.###.#.#.#.....",
}

var img: Image
var clip: Rect2i = Rect2i(0, 0, 1 << 20, 1 << 20)
var args: Dictionary = {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var s: String = str(a)
		if s.begins_with("--") and s.contains("="):
			args[s.substr(2, s.find("=") - 2)] = s.substr(s.find("=") + 1)
	_run.call_deferred()


func _run() -> void:
	DB.ensure_loaded()
	var maps: Array = []
	for a: Arena in DB.arenas_for("elimination"):
		maps.append(a)
	for a: Arena in DB.arenas_for("control"):
		maps.append(a)
	for id in DeathmatchMapData.ORDER:
		maps.append(DB.deathmatch_preview(str(id)))
	if args.has("only"):
		var keep: Array = str(args.only).split(",")
		maps = maps.filter(func(a: Arena) -> bool: return keep.has(a.id) or keep.has(str(a.data.get("preset", ""))))
	var tile: int = int(args.get("tile", "600"))
	var cols: int = int(args.get("cols", "3" if maps.size() > 2 else str(maps.size())))
	var tile_h: int = int(tile * 0.74)
	var rows: int = int(ceil(float(maps.size()) / cols))
	var header: int = 86
	img = Image.create(cols * tile + 20, header + rows * tile_h + 10, false, Image.FORMAT_RGBA8)
	img.fill(BG)
	_text(Vector2(20, 18), "DVD BATTLE 1.5.3  MAP LAYOUT ATLAS  (%d MAPS)" % maps.size(), TEXT, 3)
	_text(Vector2(20, 52), "GREY SOLID | CROSS-HATCH LATTICE/HEDGE (BODIES ONLY) | DARK CHASM (BODIES ONLY) | AMBER GATE A/B | GREEN BRUSH | CYAN PAD->TARGET | MAGENTA RING END | BLUE/RED SPAWN", DIM, 1)
	_text(Vector2(20, 66), "ORANGE LAVA | YELLOW SPIKES | RING ERUPTION/SHOCKWAVE | PURPLE PORTAL/GRAVITY | RED BOX ARTILLERY | BROWN MUD | TEAL WIND | GOLD CONTROL", DIM, 1)
	for i in maps.size():
		var ox: int = 10 + (i % cols) * tile
		var oy: int = header + (i / cols) * tile_h
		_draw_map(maps[i], Rect2(ox + 6, oy + 6, tile - 12, tile_h - 12))
	var out: String = str(args.get("out", "res://reports/maps_153/layout_atlas_153.png"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out.get_base_dir()))
	var err: int = img.save_png(out)
	print("MAP_ATLAS saved=", out, " err=", err, " size=", img.get_width(), "x", img.get_height())
	quit(0 if err == OK else 1)


# ------------------------------------------------------------------ map tile

func _draw_map(a: Arena, box: Rect2) -> void:
	_fill_rect(box, Color("#101824"))
	_rect_outline(box, Color("#26374a"), 1)
	var d: Dictionary = a.data
	var title: String = a.id.to_upper()
	if a.ruleset == "deathmatch":
		title = str(d.get("preset", a.id)).to_upper()
	_text(box.position + Vector2(8, 7), title, TEXT, 2)
	var line2: String = "%dX%d  %s  %s  %s" % [int(a.width), int(a.height), str(d.get("spawn_orientation", a.ruleset)).to_upper(),
		str(d.get("symmetry", "")).to_upper(), str(d.get("archetype", d.get("layout_id", ""))).to_upper()]
	_text(box.position + Vector2(8, 26), line2, DIM, 1)
	var types: Dictionary = {}
	for h: Dictionary in a.hazards:
		types[str(h.type).to_upper()] = int(types.get(str(h.type).to_upper(), 0)) + 1
	var gates: int = 0
	for o: Dictionary in a.obstacles:
		if o.has("gate"):
			gates += 1
	var parts: Array = []
	for k in types:
		parts.append("%s %d" % [k, types[k]])
	if gates > 0:
		parts.append("GATE %d" % gates)
	if not a.forests.is_empty():
		parts.append("BRUSH %d" % a.forests.size())
	_text(box.position + Vector2(8, 38), " ".join(parts), DIM, 1)
	var area := Rect2(box.position + Vector2(6, 52), box.size - Vector2(12, 58))
	var s: float = minf(area.size.x / a.width, area.size.y / a.height)
	var o: Vector2 = area.position + (area.size - Vector2(a.width, a.height) * s) * 0.5
	var fc: Dictionary = d.get("floor", {})
	var base: Color = Color(str(fc.get("base", "#071019")))
	_fill_rect(Rect2(o, Vector2(a.width, a.height) * s), base.darkened(0.45))
	_fill_rect(Rect2(o + Vector2(a.min_x, a.min_y) * s, Vector2(a.max_x - a.min_x, a.max_y - a.min_y) * s), base.lightened(0.04))
	# Team floor tint toward each spawn centroid (clipped to the map).
	clip = Rect2i(Vector2i(o), Vector2i(Vector2(a.width, a.height) * s))
	if a.ruleset != "deathmatch":
		for t in [0, 1]:
			var sp: Array = a.spawns.get(t, [])
			if sp.is_empty():
				continue
			var c := Vector2.ZERO
			for p: Vector2 in sp:
				c += p
			c /= float(sp.size())
			var tint: Color = Color(str(fc.get("blue" if t == 0 else "red", "#173f68")))
			for k in 4:
				_fill_circle(o + c * s, (360.0 - k * 80.0) * s, Color(tint, 0.10))
	for mark: Dictionary in d.get("landmarks", []):
		_ring(o + Vector2(float(mark.x), float(mark.y)) * s, float(mark.get("radius", 60)) * s, Color(a.accent, 0.18), 1.0)
	for f: Dictionary in a.forests:
		_fill_circle(o + Vector2(float(f.x), float(f.y)) * s, float(f.radius) * s, Color(0.12, 0.36, 0.17, 0.55))
	for f: Dictionary in a.forests:
		_ring(o + Vector2(float(f.x), float(f.y)) * s, float(f.radius) * s, Color(0.35, 0.7, 0.35, 0.6), 1.0)
	for b: Dictionary in d.get("buildings", []):
		_fill_rect(Rect2(o + Vector2(float(b.x), float(b.y)) * s, Vector2(float(b.w), float(b.h)) * s), Color(0.24, 0.19, 0.13, 0.9))
	for h: Dictionary in a.hazards:
		_draw_hazard_under(a, h, s, o)
	for i in a.obs_count:
		_draw_obstacle(a, i, s, o)
	for h: Dictionary in a.hazards:
		_draw_hazard_over(a, h, s, o)
	for cp: Dictionary in a.control_points:
		var c: Vector2 = o + (cp.center as Vector2) * s
		_fill_circle(c, float(cp.radius) * s, Color("#e8c15a", 0.22))
		_ring(c, float(cp.radius) * s, Color("#e8c15a", 0.95), 2.0)
		_text(c - Vector2(5, 7), str(cp.id), Color("#fff2c0"), 2)
	for hz: Dictionary in a.heal_zones:
		var c2: Vector2 = o + (hz.center as Vector2) * s
		_ring(c2, float(hz.radius) * s, Color("#65ecc1", 0.8), 1.5)
		_line(c2 - Vector2(4, 0), c2 + Vector2(4, 0), Color("#65ecc1"), 2.0)
		_line(c2 - Vector2(0, 4), c2 + Vector2(0, 4), Color("#65ecc1"), 2.0)
	if a.ruleset == "deathmatch":
		for p: Vector2 in a.ffa_spawns:
			_ring(o + p * s, 4.0, Color(TEXT, 0.8), 1.2)
		for spot: Dictionary in a.item_spots:
			_fill_circle(o + (spot.pos as Vector2) * s, 1.4, Color("#f0d070", 0.7))
	else:
		for t in [0, 1]:
			var col: Color = BLUE if t == 0 else RED
			var sp2: Array = a.spawns.get(t, [])
			for k in sp2.size():
				var p2: Vector2 = o + (sp2[k] as Vector2) * s
				_fill_circle(p2, 4.2, col)
				if k == 0:
					_ring(p2, 6.5, Color(1, 1, 1, 0.85), 1.2)
	_rect_outline(Rect2(o + Vector2(a.min_x, a.min_y) * s, Vector2(a.max_x - a.min_x, a.max_y - a.min_y) * s), Color(Color(str(fc.get("grid", "#9bb5c9"))), 0.45), 1)
	clip = Rect2i(0, 0, 1 << 20, 1 << 20)


func _draw_obstacle(a: Arena, i: int, s: float, o: Vector2) -> void:
	var od: Dictionary = a.obstacles[i]
	var col: Color = Color(str(od.get("color", "#5d5a55")))
	var see: bool = (a.obs_mask[i] & Arena.MASK_VISION) == 0
	var units_only: bool = see and (a.obs_mask[i] & Arena.MASK_PROJECTILES) == 0
	var gate: bool = od.has("gate")
	if a.obs_circle[i] == 1:
		var c: Vector2 = o + Vector2(a.obs_x[i], a.obs_y[i]) * s
		var r: float = a.obs_r[i] * s
		_fill_circle(c, r, col if not see else Color(col, 0.55))
		_ring(c, r, col.lightened(0.4), 1.0)
		return
	var rect := Rect2(o + Vector2(a.obs_x[i], a.obs_y[i]) * s, Vector2(a.obs_w[i], a.obs_h[i]) * s)
	if gate:
		_fill_rect(rect, Color("#d9a441", 0.9))
		_rect_outline(rect, Color("#ffe39a"), 1)
		var g: String = str((od.gate as Dictionary).get("group", "A"))
		_text(rect.get_center() - Vector2(3, 4), g, Color("#2a1a05"), 1)
	elif units_only and str(od.get("kind", "")) == "chasm":
		_fill_rect(rect, Color(col, 0.85))
		_rect_outline(rect, Color(col.lightened(0.35), 0.9), 1)
	elif units_only:
		# Low lattice / hedge: bodies stop, sight and shots cross (cross-hatched).
		_fill_rect(rect, Color(col, 0.35))
		_hatch(rect, Color(col.lightened(0.5), 0.9))
		_hatch_back(rect, Color(col.lightened(0.5), 0.6))
		_rect_outline(rect, Color(col.lightened(0.45), 0.95), 1)
	elif see:
		_fill_rect(rect, Color(col, 0.42))
		_hatch(rect, Color(col.lightened(0.45), 0.85))
		_rect_outline(rect, Color(col.lightened(0.4), 0.95), 1)
	else:
		_fill_rect(rect, col)
		_rect_outline(rect, col.lightened(0.45), 1)


func _hazard_color(h: Dictionary) -> Color:
	return Color(str(h.get("color", "#f5b36d")))


func _draw_hazard_under(a: Arena, h: Dictionary, s: float, o: Vector2) -> void:
	var col: Color = _hazard_color(h)
	var ty: String = str(h.type)
	match ty:
		"lava":
			_shape_fill(h, s, o, Color(col, 0.8))
		"spikes":
			_shape_fill(h, s, o, Color(col, 0.32))
			_shape_outline(h, s, o, Color(col, 0.9))
		"mud":
			_shape_fill(h, s, o, Color(col, 0.55))
			_shape_outline(h, s, o, Color(col.lightened(0.2), 0.8))
		"wind":
			_shape_fill(h, s, o, Color(col, 0.12))
			_shape_outline(h, s, o, Color(col, 0.55))
		"gravity":
			_shape_fill(h, s, o, Color(col, 0.16))
		"healing_fountain":
			_shape_fill(h, s, o, Color(col, 0.22))
		"artillery":
			_shape_fill(h, s, o, Color(col, 0.08))


func _draw_hazard_over(a: Arena, h: Dictionary, s: float, o: Vector2) -> void:
	var col: Color = _hazard_color(h)
	var ty: String = str(h.type)
	var c: Vector2 = o + (h.center as Vector2) * s
	match ty:
		"eruption":
			_ring(c, float(h.radius) * s, Color(col, 0.9), 1.5)
			_fill_circle(c, float(h.radius) * s * 0.3, Color(col, 0.7))
		"shockwave":
			_ring(c, float(h.radius) * s, Color(col, 0.95), 2.0)
			_ring(c, float(h.radius) * s * 0.55, Color(col, 0.45), 1.0)
			_fill_circle(c, 3.0, col)
		"gravity":
			_ring(c, float(h.radius) * s, Color(col, 0.9), 1.5)
			_ring(c, float(h.radius) * s * 0.5, Color(col, 0.6), 1.0)
		"healing_fountain":
			_ring(c, float(h.radius) * s, Color(col, 0.9), 1.5)
			_line(c - Vector2(5, 0), c + Vector2(5, 0), col, 2.5)
			_line(c - Vector2(0, 5), c + Vector2(0, 5), col, 2.5)
		"haste":
			_ring(c, float(h.radius) * s, Color(col, 0.9), 1.5)
			_line(c + Vector2(-3, -3), c + Vector2(1, 0), col, 1.5)
			_line(c + Vector2(-3, 3), c + Vector2(1, 0), col, 1.5)
		"portal":
			_ring(c, float(h.radius) * s, Color(col, 1.0), 2.0)
			for h2: Dictionary in a.hazards:
				if str(h2.id) == str(h.get("pairId", "")):
					_dashed(c, o + (h2.center as Vector2) * s, Color(col, 0.5), 1.0)
		"wind":
			var dir: Vector2 = h.get("dirA", Vector2.RIGHT)
			_arrow(c - dir * 14.0, c + dir * 14.0, Color(col, 0.95), 1.5)
		"jump_pad":
			var t: Vector2 = o + Vector2(float(h.target.x), float(h.target.y)) * s
			_fill_circle(c, float(h.radius) * s, Color(col, 0.55))
			_ring(c, float(h.radius) * s, col, 1.5)
			_arrow(c, t, Color(col, 0.95), 1.5)
			_ring(t, 5.0, Color(col, 0.9), 1.0)
		"closing_ring":
			var end_r: float = float(h.get("endRadius", 200)) * s
			_dashed_circle(c, end_r, Color(col, 0.95), 2.0)
			_fill_circle(c, 2.5, col)
		"artillery":
			var rect := Rect2(o + Vector2(float(h.x), float(h.y)) * s, Vector2(float(h.w), float(h.h)) * s)
			_dashed_rect(rect, Color(col, 0.95), 1.5)
			var r: float = float(h.get("radius", 60)) * s
			_ring(c, r, Color(col, 0.7), 1.0)
			_line(c - Vector2(r, 0), c + Vector2(r, 0), Color(col, 0.7), 1.0)
			_line(c - Vector2(0, r), c + Vector2(0, r), Color(col, 0.7), 1.0)


func _shape_fill(h: Dictionary, s: float, o: Vector2, col: Color) -> void:
	if str(h.get("shape", "rect")) == "circle":
		_fill_circle(o + Vector2(float(h.x), float(h.y)) * s, float(h.radius) * s, col)
	elif h.has("w"):
		_fill_rect(Rect2(o + Vector2(float(h.x), float(h.y)) * s, Vector2(float(h.w), float(h.h)) * s), col)


func _shape_outline(h: Dictionary, s: float, o: Vector2, col: Color) -> void:
	if str(h.get("shape", "rect")) == "circle":
		_ring(o + Vector2(float(h.x), float(h.y)) * s, float(h.radius) * s, col, 1.2)
	elif h.has("w"):
		_rect_outline(Rect2(o + Vector2(float(h.x), float(h.y)) * s, Vector2(float(h.w), float(h.h)) * s), col, 1)


# ------------------------------------------------------------------ raster

func _blend(x: int, y: int, c: Color) -> void:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height() or not clip.has_point(Vector2i(x, y)):
		return
	if c.a >= 0.999:
		img.set_pixel(x, y, c)
		return
	img.set_pixel(x, y, img.get_pixel(x, y).blend(c))


func _fill_rect(r: Rect2, c: Color) -> void:
	var x0: int = int(round(r.position.x))
	var y0: int = int(round(r.position.y))
	var x1: int = int(round(r.end.x))
	var y1: int = int(round(r.end.y))
	if c.a >= 0.999:
		img.fill_rect(Rect2i(x0, y0, maxi(1, x1 - x0), maxi(1, y1 - y0)), c)
		return
	for y in range(y0, maxi(y0 + 1, y1)):
		for x in range(x0, maxi(x0 + 1, x1)):
			_blend(x, y, c)


func _rect_outline(r: Rect2, c: Color, w: int) -> void:
	for k in w:
		_fill_rect(Rect2(r.position.x, r.position.y + k, r.size.x, 1), c)
		_fill_rect(Rect2(r.position.x, r.end.y - 1 - k, r.size.x, 1), c)
		_fill_rect(Rect2(r.position.x + k, r.position.y, 1, r.size.y), c)
		_fill_rect(Rect2(r.end.x - 1 - k, r.position.y, 1, r.size.y), c)


func _hatch(r: Rect2, c: Color) -> void:
	var step: float = 5.0
	var k: float = 0.0
	while k < r.size.x + r.size.y:
		for t in int(minf(r.size.x, r.size.y)) + 1:
			var p := Vector2(r.position.x + k - t, r.position.y + t)
			if p.x >= r.position.x and p.x < r.end.x and p.y < r.end.y:
				_blend(int(p.x), int(p.y), c)
		k += step


func _hatch_back(r: Rect2, c: Color) -> void:
	var step: float = 5.0
	var k: float = 0.0
	while k < r.size.x + r.size.y:
		for t in int(minf(r.size.x, r.size.y)) + 1:
			var p := Vector2(r.end.x - 1.0 - k + t, r.position.y + t)
			if p.x >= r.position.x and p.x < r.end.x and p.y < r.end.y:
				_blend(int(p.x), int(p.y), c)
		k += step


func _fill_circle(c: Vector2, r: float, col: Color) -> void:
	var r2: float = r * r
	for y in range(int(floor(c.y - r)), int(ceil(c.y + r)) + 1):
		for x in range(int(floor(c.x - r)), int(ceil(c.x + r)) + 1):
			var dx: float = x + 0.5 - c.x
			var dy: float = y + 0.5 - c.y
			if dx * dx + dy * dy <= r2:
				_blend(x, y, col)


func _ring(c: Vector2, r: float, col: Color, w: float) -> void:
	var outer: float = r + w * 0.5
	var inner: float = maxf(0.0, r - w * 0.5)
	for y in range(int(floor(c.y - outer)), int(ceil(c.y + outer)) + 1):
		for x in range(int(floor(c.x - outer)), int(ceil(c.x + outer)) + 1):
			var d: float = Vector2(x + 0.5, y + 0.5).distance_to(c)
			if d <= outer and d >= inner:
				_blend(x, y, col)


func _dashed_circle(c: Vector2, r: float, col: Color, w: float) -> void:
	var n: int = maxi(12, int(r * 0.35))
	for k in n:
		if k % 2 == 1:
			continue
		var a0: float = TAU * k / n
		var a1: float = TAU * (k + 1) / n
		_line(c + Vector2.from_angle(a0) * r, c + Vector2.from_angle(a1) * r, col, w)


func _dashed_rect(r: Rect2, col: Color, w: float) -> void:
	var corners: Array = [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.position]
	for i in 4:
		_dashed(corners[i], corners[i + 1], col, w)


func _dashed(a: Vector2, b: Vector2, col: Color, w: float) -> void:
	var length: float = a.distance_to(b)
	var n: int = maxi(1, int(length / 6.0))
	for k in n:
		if k % 2 == 0:
			_line(a.lerp(b, float(k) / n), a.lerp(b, float(k + 1) / n), col, w)


func _line(a: Vector2, b: Vector2, col: Color, w: float) -> void:
	var half: float = w * 0.5
	var minx: int = int(floor(minf(a.x, b.x) - half))
	var maxx: int = int(ceil(maxf(a.x, b.x) + half))
	var miny: int = int(floor(minf(a.y, b.y) - half))
	var maxy: int = int(ceil(maxf(a.y, b.y) + half))
	var d: Vector2 = b - a
	var len2: float = maxf(1e-6, d.length_squared())
	for y in range(miny, maxy + 1):
		for x in range(minx, maxx + 1):
			var p := Vector2(x + 0.5, y + 0.5)
			var t: float = clampf((p - a).dot(d) / len2, 0.0, 1.0)
			if p.distance_to(a + d * t) <= half + 0.35:
				_blend(x, y, col)


func _arrow(a: Vector2, b: Vector2, col: Color, w: float) -> void:
	_line(a, b, col, w)
	var dir: Vector2 = (b - a).normalized()
	if dir == Vector2.ZERO:
		return
	var side := Vector2(-dir.y, dir.x)
	_line(b, b - dir * 6.0 + side * 3.5, col, w)
	_line(b, b - dir * 6.0 - side * 3.5, col, w)


func _text(p: Vector2, s: String, col: Color, scale: int) -> void:
	var x: float = p.x
	for ch in s.to_upper():
		var g: String = str(FONT.get(ch, FONT["*"] if ch != " " else FONT[" "]))
		for row in 7:
			for colk in 5:
				var idx: int = row * 5 + colk
				if idx < g.length() and g[idx] == "#":
					for dy in scale:
						for dx in scale:
							_blend(int(x) + colk * scale + dx, int(p.y) + row * scale + dy, col)
		x += 6 * scale
