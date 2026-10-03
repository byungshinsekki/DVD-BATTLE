extends SceneTree

# V2.0 battleground atlas: every battleground preset at two seeds in one PNG,
# headless-safe (pure Image drawing like tools/map_atlas_153.gd). Per map:
# roads / river course (decor), buildings, brush, hazards, obstacles, item
# spots coloured by ring (gold 0, orange 1, blue 2, grey 3) with the ring
# limits dashed, the 80 placed items (BrItems, rarity colours), spawns (white
# rings), landmarks and the zone circle of every phase (BrZone, normal speed;
# cyan phase 1 to red phase 6, centre path in white).
#
# Usage:
#   <godot> --headless --path <project> --script res://tools/br_atlas_v2.gd -- \
#       [--out=res://reports/br_atlas_v2/atlas.png] [--seeds=20261001,7] [--tile=1000]
#       [--only=br_highland_ruins] [--grid=30]   (grid: tint free cells outside
#       the main component of that body bucket red, for debugging connectivity)
#       [--raw=1]   (draw one unvalidated generation per seed instead of build())

const BG: Color = Color("#0a0f16")
const TEXT: Color = Color("#dfe7f1")
const DIM: Color = Color("#8ea0b5")
const RING_COLORS: Array = [Color("#ffd24a"), Color("#ff9f43"), Color("#58a6ff"), Color("#9aa4ae")]
const ZONE_COLORS: Array = [Color("#5ce1e6"), Color("#58a6ff"), Color("#a78af4"), Color("#e66bd0"), Color("#ff7b5c"), Color("#ff3b3b")]

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
	"|": "..#....#....#....#....#....#....#..", "=": "..........#####.....#####..........",
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
	var seeds: Array = []
	for s in str(args.get("seeds", "20261001,7")).split(","):
		seeds.append(int(s))
	var ids: Array = BattlegroundMapData.ORDER.duplicate()
	if args.has("only"):
		ids = str(args.only).split(",")
	var tile: int = int(args.get("tile", "1000"))
	var tile_h: int = int(tile * 0.72)
	var cols: int = seeds.size()
	var header: int = 96
	img = Image.create(cols * tile + 20, header + ids.size() * tile_h + 10, false, Image.FORMAT_RGBA8)
	img.fill(BG)
	_text(Vector2(20, 16), "DVD BATTLE 2.0  BATTLEGROUND ATLAS  (%d PRESETS X %d SEEDS)" % [ids.size(), seeds.size()], TEXT, 3)
	_text(Vector2(20, 48), "GREY SOLID | DARK BLUE WATER | AMBER GATE | GREEN BRUSH | WHITE RING SPAWN | DOTS ITEM SPOTS BY RING (GOLD 0, ORANGE 1, BLUE 2, GREY 3)", DIM, 1)
	_text(Vector2(20, 62), "BIG DOTS PLACED ITEMS BY RARITY | ZONE PHASES 1-6 CYAN TO RED, WHITE CENTRE PATH | DASHED RING LIMITS 0.2 0.45 0.7 | CYAN PAD->LANDING", DIM, 1)
	_text(Vector2(20, 76), "RED BOX ARTILLERY | TEAL WIND | BROWN MUD | PURPLE GRAVITY | GREEN CROSS SPRING | CYAN CHEVRON HASTE", DIM, 1)
	for row in ids.size():
		for col in seeds.size():
			var t0: int = Time.get_ticks_msec()
			var data: Dictionary = BattlegroundMapData.generate(str(ids[row]), int(seeds[col])) if args.has("raw") else BattlegroundMapData.build(str(ids[row]), int(seeds[col]))
			print("BR_ATLAS build %s seed=%d ms=%d attempt=%d" % [str(ids[row]), int(seeds[col]), Time.get_ticks_msec() - t0, int(data.get("generation_attempt", -1))])
			var ox: int = 10 + col * tile
			var oy: int = header + row * tile_h
			_draw_map(data, int(seeds[col]), Rect2(ox + 6, oy + 6, tile - 12, tile_h - 12))
	var out: String = str(args.get("out", "res://reports/br_atlas_v2/atlas.png"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out.get_base_dir()))
	var err: int = img.save_png(out)
	print("BR_ATLAS saved=", out, " err=", err, " size=", img.get_width(), "x", img.get_height())
	quit(0 if err == OK else 1)


# ------------------------------------------------------------------ map tile

func _draw_map(d: Dictionary, seed_value: int, box: Rect2) -> void:
	_fill_rect(box, Color("#101824"))
	_rect_outline(box, Color("#26374a"), 1)
	if d.is_empty():
		_text(box.position + Vector2(8, 7), "BUILD FAILED", Color("#ff6d79"), 2)
		return
	var a: Arena = Arena.from_data(d)
	var zone: BrZone = BrZone.new(a, d, seed_value, "normal")
	var items: Array = BrItems.place(d, seed_value)
	_text(box.position + Vector2(8, 7), "%s  SEED %d" % [str(d.preset).to_upper(), seed_value], TEXT, 2)
	var rings: Array = [0, 0, 0, 0]
	for s: Dictionary in d.item_spots:
		rings[int(s.ring)] += 1
	var patches: Dictionary = {}
	for f: Dictionary in d.forests:
		patches[int(f.patch)] = true
	_text(box.position + Vector2(8, 26), "%dX%d  ATTEMPT %d  OBST %d  BRUSH %d/%d  HAZ %d  SPAWN %d  SPOTS %d (%d/%d/%d/%d)  MARKS %d" % [
		int(a.width), int(a.height), int(d.get("generation_attempt", 0)), a.obs_count, a.forests.size(), patches.size(),
		a.hazards.size(), a.ffa_spawns.size(), (d.item_spots as Array).size(), rings[0], rings[1], rings[2], rings[3], (d.landmarks as Array).size()], DIM, 1)
	var area := Rect2(box.position + Vector2(6, 40), box.size - Vector2(12, 46))
	var s: float = minf(area.size.x / a.width, area.size.y / a.height)
	var o: Vector2 = area.position + (area.size - Vector2(a.width, a.height) * s) * 0.5
	var fc: Dictionary = d.get("floor", {})
	var base: Color = Color(str(fc.get("base", "#071019")))
	_fill_rect(Rect2(o, Vector2(a.width, a.height) * s), base.darkened(0.45))
	_fill_rect(Rect2(o + Vector2(a.min_x, a.min_y) * s, Vector2(a.max_x - a.min_x, a.max_y - a.min_y) * s), base.lightened(0.05))
	clip = Rect2i(Vector2i(o), Vector2i(Vector2(a.width, a.height) * s))
	var br: Dictionary = d.br
	for dec: Dictionary in br.get("decor", []):
		if str(dec.type) == "road" or str(dec.type) == "tributary":
			_fill_rect(Rect2(o + Vector2(float(dec.x), float(dec.y)) * s, Vector2(float(dec.w), float(dec.h)) * s), Color(1, 1, 1, 0.045))
	if args.has("grid"):
		_draw_grid(d, float(args.grid), s, o)
	for b: Dictionary in d.get("buildings", []):
		_fill_rect(Rect2(o + Vector2(float(b.x), float(b.y)) * s, Vector2(float(b.w), float(b.h)) * s), Color(0.24, 0.19, 0.13, 0.75 if not b.has("ruined") else 0.35))
	for f: Dictionary in a.forests:
		_fill_circle(o + Vector2(float(f.x), float(f.y)) * s, float(f.radius) * s, Color(0.12, 0.36, 0.17, 0.5))
	for h: Dictionary in a.hazards:
		_draw_hazard_under(h, s, o)
	for i in a.obs_count:
		_draw_obstacle(a, i, s, o)
	for h: Dictionary in a.hazards:
		_draw_hazard_over(h, s, o)
	for mark: Dictionary in d.get("landmarks", []):
		_circle_line(o + Vector2(float(mark.x), float(mark.y)) * s, float(mark.get("radius", 60)) * s, Color(a.accent, 0.28), 1.0, true)
	var c: Vector2 = o + zone.centers[0] * s
	for k in 3:
		_circle_line(c, float(BattlegroundMapData.RING_LIMITS[k]) * zone.half_diag * s, Color(1, 1, 1, 0.22), 1.0, true)
	for spot: Dictionary in d.item_spots:
		_fill_circle(o + Vector2(float(spot.x), float(spot.y)) * s, 1.5, Color(RING_COLORS[int(spot.ring)], 0.85))
	for it: Dictionary in items:
		var p: Vector2 = o + (it.pos as Vector2) * s
		_fill_circle(p, 3.6, Color(0, 0, 0, 0.85))
		_fill_circle(p, 2.6, ItemDefs.rarity_color(int(it.rarity)))
	for sp: Vector2 in a.ffa_spawns:
		_ring(o + sp * s, 4.5, Color(1, 1, 1, 0.9), 1.4)
		_fill_circle(o + sp * s, 1.2, Color(1, 1, 1, 0.9))
	for k in range(1, BrZone.PHASES + 1):
		var col: Color = ZONE_COLORS[k - 1]
		var ck: Vector2 = o + zone.centers[k] * s
		if zone.radii[k] > 1.0:
			_circle_line(ck, zone.radii[k] * s, Color(col, 0.95), 1.6, false)
		_line(o + zone.centers[k - 1] * s, ck, Color(1, 1, 1, 0.8), 1.2)
		_fill_circle(ck, 2.2, col)
	_rect_outline(Rect2(o + Vector2(a.min_x, a.min_y) * s, Vector2(a.max_x - a.min_x, a.max_y - a.min_y) * s), Color(Color(str(fc.get("grid", "#9bb5c9"))), 0.45), 1)
	clip = Rect2i(0, 0, 1 << 20, 1 << 20)


# Debug overlay: free cells of the bucket grid outside its main component.
func _draw_grid(d: Dictionary, bucket: float, s: float, o: Vector2) -> void:
	var grid: Dictionary = BattlegroundMapData.run_grid(d, bucket)
	var row_start: PackedInt32Array = grid.row_start
	var x0: PackedInt32Array = grid.x0
	var x1: PackedInt32Array = grid.x1
	var comp: PackedInt32Array = grid.comp
	for y in int(grid.rows):
		for i in range(row_start[y], row_start[y + 1]):
			if comp[i] == int(grid.main):
				continue
			var r := Rect2(o + Vector2(float(x0[i]) * 16.0, float(y) * 16.0) * s, Vector2(float(x1[i] - x0[i] + 1) * 16.0, 16.0) * s)
			_fill_rect(r, Color(1.0, 0.1, 0.1, 0.8))


func _draw_obstacle(a: Arena, i: int, s: float, o: Vector2) -> void:
	var od: Dictionary = a.obstacles[i]
	var col: Color = Color(str(od.get("color", "#5d5a55")))
	if a.obs_circle[i] == 1:
		var c: Vector2 = o + Vector2(a.obs_x[i], a.obs_y[i]) * s
		var r: float = maxf(0.8, a.obs_r[i] * s)
		_fill_circle(c, r, col.lightened(0.15))
		return
	var rect := Rect2(o + Vector2(a.obs_x[i], a.obs_y[i]) * s, Vector2(a.obs_w[i], a.obs_h[i]) * s)
	if od.has("gate"):
		_fill_rect(rect, Color("#d9a441"))
	elif str(od.get("kind", "")) == "chasm":
		_fill_rect(rect, Color("#1c4e6a"))
	elif str(od.get("kind", "")) == "hedge":
		_fill_rect(rect, Color(col, 0.6))
	else:
		_fill_rect(rect, col.lightened(0.18))


func _draw_hazard_under(h: Dictionary, s: float, o: Vector2) -> void:
	var col: Color = Color(str(h.get("color", "#f5b36d")))
	match str(h.type):
		"mud":
			_shape_fill(h, s, o, Color(col, 0.6))
		"wind":
			_shape_fill(h, s, o, Color(col, 0.16))
		"gravity":
			_shape_fill(h, s, o, Color(col, 0.22))
		"healing_fountain":
			_shape_fill(h, s, o, Color(col, 0.3))
		"artillery":
			_shape_fill(h, s, o, Color(col, 0.1))
		"haste":
			_shape_fill(h, s, o, Color(col, 0.18))


func _draw_hazard_over(h: Dictionary, s: float, o: Vector2) -> void:
	var col: Color = Color(str(h.get("color", "#f5b36d")))
	var c: Vector2 = o + (h.center as Vector2) * s
	match str(h.type):
		"gravity":
			_ring(c, float(h.radius) * s, Color(col, 0.9), 1.4)
		"healing_fountain":
			_line(c - Vector2(4, 0), c + Vector2(4, 0), col, 2.0)
			_line(c - Vector2(0, 4), c + Vector2(0, 4), col, 2.0)
		"haste":
			_line(c + Vector2(-3, -3), c + Vector2(1, 0), col, 1.4)
			_line(c + Vector2(-3, 3), c + Vector2(1, 0), col, 1.4)
		"wind":
			var dir: Vector2 = h.get("dirA", Vector2.RIGHT)
			_arrow(c - dir * 10.0, c + dir * 10.0, Color(col, 0.95), 1.4)
		"jump_pad":
			var t: Vector2 = o + Vector2(float(h.target.x), float(h.target.y)) * s
			_fill_circle(c, maxf(2.0, float(h.radius) * s), Color(col, 0.7))
			_arrow(c, t, Color(col, 0.95), 1.2)
		"artillery":
			var rect := Rect2(o + Vector2(float(h.x), float(h.y)) * s, Vector2(float(h.w), float(h.h)) * s)
			_rect_outline(rect, Color(col, 0.95), 1)


func _shape_fill(h: Dictionary, s: float, o: Vector2, col: Color) -> void:
	if str(h.get("shape", "rect")) == "circle":
		_fill_circle(o + Vector2(float(h.x), float(h.y)) * s, float(h.radius) * s, col)
	elif h.has("w"):
		_fill_rect(Rect2(o + Vector2(float(h.x), float(h.y)) * s, Vector2(float(h.w), float(h.h)) * s), col)


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
		var cr: Rect2i = Rect2i(x0, y0, maxi(1, x1 - x0), maxi(1, y1 - y0)).intersection(clip)
		if cr.size.x > 0 and cr.size.y > 0:
			img.fill_rect(cr, c)
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


# Large circles as short segments (a per-pixel ring scan would be too slow).
func _circle_line(c: Vector2, r: float, col: Color, w: float, dashed: bool) -> void:
	var n: int = maxi(16, int(r * 0.6))
	for k in n:
		if dashed and k % 2 == 1:
			continue
		var a0: float = TAU * k / n
		var a1: float = TAU * (k + 1) / n
		_line(c + Vector2.from_angle(a0) * r, c + Vector2.from_angle(a1) * r, col, w)


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
	_line(b, b - dir * 5.0 + side * 3.0, col, w)
	_line(b, b - dir * 5.0 - side * 3.0, col, w)


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
