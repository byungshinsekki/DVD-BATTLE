class_name Navigator
extends RefCounted

# Grid A* navigation (16 px cells, padded by a body-radius bucket).
#
# V1.5.3 API (all additions are optional arguments; V1.5.2 callers still work):
#   Navigator.get_for(arena, r, skip_mask=0)     grid for the arena's CURRENT navigation
#                                                gate state (arena.nav_sig; gates closing
#                                                within 1.5 s count as closed).
#   Navigator.for_arena(arena, r, gate_sig=-1, skip_mask=0)
#                                                same, with an explicit gate signature
#                                                (bit per Arena.gates slot, 1 = open) and the
#                                                environment switches (ArenaEnv.skip_mask():
#                                                Arena.TYPE_BITS of switched-off types, -1 = the
#                                                whole environment off). Switched-off hazards add
#                                                no cell weights, shortcut blockers or links.
#   Navigator.for_sim(sim, r, gate_sig=-1)       for_arena(sim.arena, r, gate_sig,
#                                                sim.env.skip_mask()) - what a battle should use.
#   nav.next_waypoint(start, goal, r, speed=0, portal_wait=0, pad_wait=0, use_links=true)
#                                                an unreachable goal (behind a closed gate)
#                                                gives the end of the partial path, never the
#                                                goal itself.
#   nav.route_point(...)                         alias of next_waypoint.
#   nav.path_length(start, goal, r, speed=0, portal_wait=0, pad_wait=0, use_links=true)
#                                                walking length of the best route (INF when
#                                                the goal is unreachable; no partial-path lengths).
#   nav.path_points(start, goal, allow_partial=true)   raw grid path. A start / goal whose
#                                                cell is solid snaps to the NEAREST free cell
#                                                (near-ties go to the side facing the other end),
#                                                so mirrored queries give mirrored paths.
#   nav.clear(a, b, r)                           PHYSICAL straight-line walkability (walls and
#                                                closed gates of this grid's signature).
#   nav.safe_clear(a, b, r)                      clear() and not crossing always-on damage
#                                                hazards (lava) or portal / jump-pad circles
#                                                that hold neither end. The routing shortcut.
#   nav.route_link(start, goal, r, ...)          index into nav.links of the link the best route
#                                                uses (-1 = walk directly).
#   nav.direct_length(start, goal, r)            walking length without links (INF if unreachable).
#   nav.outside_links(start, goal, r)            a goal inside a portal / pad trigger pulled back to
#                                                its rim (next_waypoint applies it when walking).
#   Navigator.unit_waypoint(sim, u, goal)        next_waypoint for a hero/summon in a battle with
#   Navigator.unit_path_length(sim, u, goal)     its speed and own portal/pad cooldowns (heroes
#                                                only use links; switched-off types never).
#   Navigator.forget(arena)                      drop grids (a shared arena also drops the grids
#                                                of its per-battle gate copies).
#
# speed: traveller move speed in px/s (0 = DEFAULT_SPEED) converts jump-pad flight
# time and cooldown waits into walking pixels. portal_wait / pad_wait: seconds
# until the traveller's own environment portal / jump-pad cooldown ends; entering
# earlier does nothing, so the wait is added to that link's cost.
#
# Links: every environment portal gives an edge to its pair's exit point (both
# directions), every jump pad a one-way edge to its landing point (exits are
# placed under the grid's own gate signature, so a grid shared by battle copies
# never depends on which copy built it or when). A route is
# min(direct, dist(start, entry) + link cost + dist(exit, goal)); the partial
# distances are native A* queries memoised per link endpoint and grid cell (a
# lazily filled distance field), and a lower bound skips links that cannot win.
#
# Cell weights (AStarGrid2D weight scale, max of overlapping hazards):
#   always-on damage (lava) x8, jump pads and portals x6, periodic damage
#   (spikes, eruption, gravity, shockwave, non-constant lava) x2.5, mud x1.6.

static var _cache: Dictionary = {}

const CELL: = 16.0
const CACHE_LIMIT: = 48
const DEFAULT_SPEED: = 150.0
const LINK_MARGIN: = 40.0
# Clearance kept outside a portal / pad trigger circle by walking goals.
const LINK_RIM: = 12.0
const MEMO_LIMIT: = 4096
const PATH_CACHE_LIMIT: = 512
const W_ALWAYS_DAMAGE: = 8.0
const W_LINK_PAD: = 6.0
const W_PERIODIC: = 2.5
const W_MUD: = 1.6
const BLOCK_ALWAYS: = 0
const BLOCK_LINK: = 1
const BLOCK_PERIODIC: = 2
const SHORTCUT_AVOIDS_PERIODIC: = true
# Path points scanned for the straight-line shortcut (16 px cells, ~560 px).
const SCAN_POINTS: = 35
# Snapping a solid start / goal cell: free cells within this many px of the
# nearest one count as tied and go to the one nearest the other end of the
# query (mirror-consistent; the old raster order favoured the top-left).
const SNAP_TIE: = 4.0

var arena: Arena
var bucket: float = 18.0
# Gate signature this grid was built for (bit per arena.gates slot, 1 = open).
var sig: int = 0
# Arena.TYPE_BITS of switched-off hazard types this grid ignores (only bits of
# types present on the map that change the grid; 0 = everything on).
var skip: int = 0
# Symmetry centre lines and kind (authored "symmetry"), for _snap's boundary ties.
var _mid_x: float = 0.0
var _mid_y: float = 0.0
var _point_sym: bool = false
var grid: AStarGrid2D
var cols: int = 0
var rows: int = 0
var weights: PackedFloat32Array = PackedFloat32Array()
# [{kind:"portal"|"jump_pad", hazard, entry, entry_r, exit, flight}]
var links: Array = []
var _blockers: Array = []
# Shortcut blockers flattened into packed arrays (safe_clear runs per path
# point in _direct_waypoint, so it must not touch Dictionaries).
var _bk_kind: PackedInt32Array = PackedInt32Array()
var _bk_circle: PackedByteArray = PackedByteArray()
var _bk_x: PackedFloat64Array = PackedFloat64Array()
var _bk_y: PackedFloat64Array = PackedFloat64Array()
var _bk_w: PackedFloat64Array = PackedFloat64Array()
var _bk_h: PackedFloat64Array = PackedFloat64Array()
var _memo_in: Array = []
var _memo_out: Array = []
# A grid never changes after _build (gate states use separate grids), so the A*
# result for a (start cell, goal cell) pair is memoised exactly. Movement code
# asks for the same pair on consecutive ticks while a body crosses a cell.
var _path_cache: Dictionary = {}
var _wp_cache: Dictionary = {}


static func bucket_for(r: float) -> float:
	return 12.0 if r <= 12.0 else (18.0 if r <= 18.0 else (26.0 if r <= 26.0 else ceilf(r / 4.0) * 4.0))


# Every bucket a body whose radius stays within [rmin, rmax] can use, ascending
# (the giant's 20.4..27.6 needs 26 and 28). Battles pre-build these grids.
static func buckets_between(rmin: float, rmax: float) -> Array:
	var out: Array = [bucket_for(rmin)]
	var top: float = bucket_for(maxf(rmin, rmax))
	while float(out.back()) < top:
		out.append(bucket_for(float(out.back()) + 0.001))
	return out


# Drops every grid built for arena a. Forgetting a shared (DB) arena also drops
# the grids its per-battle gate copies share (they are keyed by source_uid).
static func forget(a: Arena) -> void:
	var uid: int = a.get_instance_id()
	for key in _cache.keys():
		var owner: Arena = (_cache[key] as Navigator).arena
		if owner == a or (owner.battle_copy and owner.source_uid == uid):
			_cache.erase(key)


# Movement helpers for a hero in a running battle: grid for its body in
# sim.arena under the current gate state and environment switches, its move
# speed and its OWN portal / jump-pad cooldowns (ArenaEnv.portal_wait /
# pad_wait; switched-off types are never used as links).
static func unit_waypoint(sim: BattleSim, u: BUnit, goal: Vector2) -> Vector2:
	var r: float = sim.radius(u)
	var nav: Navigator = for_sim(sim, r)
	if nav.links.is_empty():
		return nav.next_waypoint(u.pos, goal, r, 0.0, 0.0, 0.0, false)
	return nav.next_waypoint(u.pos, goal, r, sim.stat(u, BattleSim.S_MS), sim.env.portal_wait(u), sim.env.pad_wait(u), u.is_hero)


static func unit_path_length(sim: BattleSim, u: BUnit, goal: Vector2) -> float:
	var r: float = sim.radius(u)
	var nav: Navigator = for_sim(sim, r)
	if nav.links.is_empty():
		return nav.path_length(u.pos, goal, r, 0.0, 0.0, 0.0, false)
	return nav.path_length(u.pos, goal, r, sim.stat(u, BattleSim.S_MS), sim.env.portal_wait(u), sim.env.pad_wait(u), u.is_hero)


# Grid for a body of radius r in a running battle: its arena, the current (or
# the given) gate signature and the battle's own environment switches. The
# switches are passed explicitly, never stored on the Arena: maps without gates
# play on the shared DB instance, which other battles and previews also use.
static func for_sim(sim: BattleSim, r: float, gate_sig: int = -1) -> Navigator:
	return for_arena(sim.arena, r, gate_sig, sim.env.skip_mask() if sim.env != null else 0)


static func get_for(a: Arena, r: float, skip_mask: int = 0) -> Navigator:
	return for_arena(a, r, -1, skip_mask)


# Bits of skip_mask that change a grid of arena a: switched-off types that are
# present on the map and carry a cell weight or a link. Everything else (wind,
# haste, artillery, ...) keeps the default grid, so toggling them builds nothing.
static func nav_skip_bits(a: Arena, skip_mask: int) -> int:
	if skip_mask == 0:
		return 0
	var bits: int = 0
	for h in a.hazards:
		var tb: int = int(h.get("tbit", 0))
		if (tb & skip_mask) == 0 or (bits & tb) != 0:
			continue
		var typ: String = str(h.get("type", ""))
		if typ == "portal" or typ == "jump_pad" or hazard_weight(h) > 1.0:
			bits |= tb
	return bits


static func for_arena(a: Arena, r: float, gate_sig: int = -1, skip_mask: int = 0) -> Navigator:
	# Map IDs describe presets, not geometry ownership. Private previews,
	# developer layouts and per-battle gate copies can share an ID with the DB
	# arena, so grids are keyed by instance, padding bucket, gate state and the
	# environment switches that change the grid.
	# Never use a grid whose padding is smaller than the moving body's radius.
	var b: float = bucket_for(r)
	var s: int = 0
	if not a.gates.is_empty():
		s = a.nav_sig if gate_sig < 0 else gate_sig
	var sk: int = nav_skip_bits(a, skip_mask)
	# Battle copies of one shared map reuse each other's grids (same geometry
	# per gate signature) in their own namespace, never the shared arena's.
	var key: String = ("c%d:%d:%d:%d" % [a.source_uid, int(b), s, sk]) if a.battle_copy and a.source_uid != 0 else ("%d:%d:%d:%d" % [a.get_instance_id(), int(b), s, sk])
	if _cache.has(key):
		return _cache[key]
	var n: = Navigator.new()
	n.arena = a
	n.bucket = b
	n.sig = s
	n.skip = sk
	n._build()
	_cache[key] = n
	# Private arenas do not live in DB's procedural-map eviction queue.
	# Bound their cached grids as well; existing controllers retain no grid state.
	while _cache.size() > CACHE_LIMIT:
		_cache.erase(_cache.keys()[0])
	return n


func _build() -> void :
	grid = AStarGrid2D.new()
	cols = int(ceil(arena.width / CELL))
	rows = int(ceil(arena.height / CELL))
	grid.region = Rect2i(0, 0, cols, rows)
	grid.cell_size = Vector2(CELL, CELL)
	grid.offset = Vector2(CELL * 0.5, CELL * 0.5)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.update()
	_mid_x = arena.width * 0.5
	_mid_y = arena.height * 0.5
	_point_sym = str(arena.data.get("symmetry", "")) == "point"
	var pad: = bucket + 3.0
	# V2 (B-MODE): gated maps use the per-obstacle build too, with each gate's
	# mask under this grid's signature (the per-cell reference took ~50 s per
	# grid on the battleground metropolis; the solid sets are identical).
	var solid_map: PackedByteArray = _solid_by_cells(pad) if slow_build else _solid_by_shapes(pad)
	_run_row = PackedInt32Array()
	_run_x0 = PackedInt32Array()
	_run_x1 = PackedInt32Array()
	_row_first = PackedInt32Array()
	_row_first.resize(rows + 1)
	for y in rows:
		_row_first[y] = _run_x0.size()
		var row: int = y * cols
		var open: int = -1
		var wall: int = -1
		for x in cols:
			if solid_map[row + x] == 1:
				if wall < 0:
					wall = x
				if open >= 0:
					_add_run(y, open, x - 1)
					open = -1
			else:
				if open < 0:
					open = x
				if wall >= 0:
					grid.fill_solid_region(Rect2i(wall, y, x - wall, 1), true)
					wall = -1
		if open >= 0:
			_add_run(y, open, cols - 1)
		if wall >= 0:
			grid.fill_solid_region(Rect2i(wall, y, cols - wall, 1), true)
	_row_first[rows] = _run_x0.size()
	_label_components()
	if arena.width * arena.height > BattleSim.SCALE_AREA:
		_build_coarse()
	_build_weights()
	_build_links()


# Reference solid test, one cell at a time (gated maps use it: obstacle masks
# depend on this grid's gate signature).
func _solid_by_cells(pad: float) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	out.resize(cols * rows)
	out.fill(0)
	var gated: bool = not arena.gates.is_empty()
	for y in rows:
		for x in cols:
			var c: = Vector2(x * CELL + CELL * 0.5, y * CELL + CELL * 0.5)
			var solid: = c.x < arena.min_x + bucket or c.x > arena.max_x - bucket or c.y < arena.min_y + bucket or c.y > arena.max_y - bucket
			if not solid:
				solid = arena.inside_obstacle_sig(c, pad, Arena.MASK_UNITS, sig) if gated else arena.inside_obstacle(c, pad, Arena.MASK_UNITS)
			if solid:
				out[y * cols + x] = 1
	return out


# V2 (B-PERF): the same solid set built per obstacle instead of per cell. A
# cell is solid when its centre fails the bounds test or lies inside some
# unit-blocking obstacle padded by pad - exactly Arena.inside_obstacle's
# tests, evaluated only for the cells in each obstacle's padded box.
func _solid_by_shapes(pad: float) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	out.resize(cols * rows)
	out.fill(0)
	var edge_cols: PackedInt32Array = PackedInt32Array()
	for x in cols:
		var cx: float = x * CELL + CELL * 0.5
		if cx < arena.min_x + bucket or cx > arena.max_x - bucket:
			edge_cols.append(x)
	for y in rows:
		var cy: float = y * CELL + CELL * 0.5
		if cy < arena.min_y + bucket or cy > arena.max_y - bucket:
			for x in cols:
				out[y * cols + x] = 1
		else:
			for x in edge_cols:
				out[y * cols + x] = 1
	var gated: bool = not arena.gates.is_empty()
	for i in arena.obs_count:
		var mask: int = arena.mask_for_sig(i, sig) if gated else arena.obs_mask[i]
		if (mask & Arena.MASK_UNITS) == 0:
			continue
		var x0: int = clampi(int(floor((arena.obs_minx[i] - pad) / CELL)) - 1, 0, cols - 1)
		var x1: int = clampi(int(ceil((arena.obs_maxx[i] + pad) / CELL)) + 1, 0, cols - 1)
		var y0: int = clampi(int(floor((arena.obs_miny[i] - pad) / CELL)) - 1, 0, rows - 1)
		var y1: int = clampi(int(ceil((arena.obs_maxy[i] + pad) / CELL)) + 1, 0, rows - 1)
		if arena.obs_circle[i] == 1:
			var centre: Vector2 = Vector2(arena.obs_x[i], arena.obs_y[i])
			var reach: float = arena.obs_r[i] + pad
			for y in range(y0, y1 + 1):
				for x in range(x0, x1 + 1):
					if Vector2(x * CELL + CELL * 0.5, y * CELL + CELL * 0.5).distance_to(centre) <= reach:
						out[y * cols + x] = 1
		else:
			var lx: float = arena.obs_x[i] - pad
			var hx: float = arena.obs_x[i] + arena.obs_w[i] + pad
			var ly: float = arena.obs_y[i] - pad
			var hy: float = arena.obs_y[i] + arena.obs_h[i] + pad
			for y in range(y0, y1 + 1):
				var cy2: float = y * CELL + CELL * 0.5
				if cy2 < ly or cy2 > hy:
					continue
				for x in range(x0, x1 + 1):
					var cx2: float = x * CELL + CELL * 0.5
					if cx2 >= lx and cx2 <= hx:
						out[y * cols + x] = 1
	return out


static func hazard_weight(h: Dictionary) -> float:
	var typ: String = str(h.get("type", ""))
	if typ == "portal" or typ == "jump_pad":
		return W_LINK_PAD
	if typ == "mud":
		return W_MUD
	if bool(h.get("alwaysActive", false)) and float(h.get("damage", 0.0)) > 0.0:
		return W_ALWAYS_DAMAGE
	if typ in ["spikes", "eruption", "gravity", "shockwave", "lava"]:
		return W_PERIODIC
	return 1.0


func _build_weights() -> void:
	weights.resize(cols * rows)
	weights.fill(1.0)
	_blockers.clear()
	_bk_kind.clear()
	_bk_circle.clear()
	_bk_x.clear()
	_bk_y.clear()
	_bk_w.clear()
	_bk_h.clear()
	var weighted: PackedInt32Array = PackedInt32Array()
	var wpad: float = bucket * 0.3
	for h in arena.hazards:
		# A switched-off type is harmless floor: no weight, no shortcut blocker.
		if skip != 0 and (int(h.get("tbit", 0)) & skip) != 0:
			continue
		var w: float = hazard_weight(h)
		var typ: String = str(h.get("type", ""))
		if typ == "portal" or typ == "jump_pad":
			_add_blocker(h, BLOCK_LINK)
		elif w >= W_ALWAYS_DAMAGE:
			_add_blocker(h, BLOCK_ALWAYS)
		elif w >= W_PERIODIC and SHORTCUT_AVOIDS_PERIODIC:
			_add_blocker(h, BLOCK_PERIODIC)
		if w <= 1.0:
			continue
		var hpad: float = (bucket * 0.28 + LINK_RIM * 0.75) if (typ == "portal" or typ == "jump_pad") else wpad
		var ext: Rect2 = _shape_rect(h).grow(hpad + CELL)
		var x0: int = clampi(int(floor(ext.position.x / CELL)), 0, cols - 1)
		var x1: int = clampi(int(floor(ext.end.x / CELL)), 0, cols - 1)
		var y0: int = clampi(int(floor(ext.position.y / CELL)), 0, rows - 1)
		var y1: int = clampi(int(floor(ext.end.y / CELL)), 0, rows - 1)
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				var i: int = y * cols + x
				if weights[i] >= w:
					continue
				if Arena.shape_contains(h, Vector2(x * CELL + CELL * 0.5, y * CELL + CELL * 0.5), hpad):
					if weights[i] <= 1.0:
						weighted.append(i)
					weights[i] = w
	if weighted.is_empty():
		return
	for i in weighted:
		grid.set_point_weight_scale(Vector2i(i % cols, i / cols), weights[i])


# Circle: x, y = centre, w = radius. Rect: x, y, w, h as authored.
func _add_blocker(h: Dictionary, kind: int) -> void:
	_blockers.append(h)
	_bk_kind.append(kind)
	var circle: bool = str(h.get("shape", "rect")) == "circle"
	_bk_circle.append(1 if circle else 0)
	if circle:
		var c: Vector2 = h.center
		_bk_x.append(c.x)
		_bk_y.append(c.y)
		_bk_w.append(float(h.get("radius", 0.0)))
		_bk_h.append(0.0)
	else:
		_bk_x.append(float(h.get("x", 0.0)))
		_bk_y.append(float(h.get("y", 0.0)))
		_bk_w.append(float(h.get("w", 0.0)))
		_bk_h.append(float(h.get("h", 0.0)))


static func _shape_rect(h: Dictionary) -> Rect2:
	if str(h.get("shape", "rect")) == "circle":
		var r: float = float(h.get("radius", 0.0))
		return Rect2(float(h.get("x", 0.0)) - r, float(h.get("y", 0.0)) - r, r * 2.0, r * 2.0)
	return Rect2(float(h.get("x", 0.0)), float(h.get("y", 0.0)), float(h.get("w", 0.0)), float(h.get("h", 0.0)))


func _build_links() -> void:
	links.clear()
	_memo_in.clear()
	_memo_out.clear()
	var by_id: Dictionary = {}
	for h in arena.hazards:
		by_id[str(h.get("id", ""))] = h
	for h in arena.hazards:
		var typ: String = str(h.get("type", ""))
		# A switched-off portal / pad is inert floor: no link, and walking goals
		# on it are not pulled back to its rim (outside_links).
		if skip != 0 and (int(h.get("tbit", 0)) & skip) != 0:
			continue
		# Exits are resolved under THIS grid's gate signature, not the gates the
		# arena instance happens to show right now (shared grids stay order-free).
		if typ == "portal":
			var pair: Dictionary = by_id.get(str(h.get("pairId", "")), {})
			if pair.is_empty() or pair == h:
				continue
			var dir: Vector2 = pair.get("exit", ((pair.center as Vector2) - (h.center as Vector2)).normalized())
			var exitp: Vector2 = (pair.center as Vector2) + dir * (float(pair.get("radius", 30.0)) + bucket + 8.0)
			links.append({"kind": "portal", "hazard": str(h.id), "entry": h.center, "entry_r": float(h.get("radius", 30.0)),
				"exit": arena.resolve_circle_sig(exitp, bucket, sig), "flight": 0.0})
		elif typ == "jump_pad":
			links.append({"kind": "jump_pad", "hazard": str(h.id), "entry": h.center, "entry_r": float(h.get("radius", 30.0)),
				"exit": arena.resolve_circle_sig(h.get("landing", h.center), bucket, sig), "flight": maxf(0.05, float(h.get("flightTime", 0.8)))})
	for _k in links.size():
		_memo_in.append({})
		_memo_out.append({})


func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(clampi(int(p.x / CELL), 0, cols - 1), clampi(int(p.y / CELL), 0, rows - 1))


# Free cell for a point p whose cell c may be solid (inside a wall pad, a closed
# gate frame or an obstacle-covered map centre): the free cell whose centre is
# nearest p (within 7 rings). Cells within SNAP_TIE px of that distance count as
# tied and go to the one nearest ref (the other end of the query); remaining
# exact ties keep the scan order. Pure geometry, so mirrored queries on a mirrored
# grid snap to mirrored cells. p = INF uses the centre of c; ref = INF skips the
# reference tie-break. Scalar locals only (runs inside per-tick queries).
func _free_cell_near(c: Vector2i, p: Vector2 = Vector2.INF, ref: Vector2 = Vector2.INF) -> Vector2i:
	if not grid.is_point_solid(c):
		return c
	var px: float = p.x if p.is_finite() else c.x * CELL + CELL * 0.5
	var py: float = p.y if p.is_finite() else c.y * CELL + CELL * 0.5
	var use_ref: bool = ref.is_finite()
	# Pass 1: nearest free distance. A ring-r cell centre lies at least
	# (r - 0.71) cells from any point of cell c, so rings beyond the nearest
	# free distance (+ SNAP_TIE) cannot win.
	var best_d: float = INF
	var last: int = 7
	for r in range(1, 8):
		if r > last:
			break
		for dy in range( - r, r + 1):
			for dx in range( - r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var qx: int = c.x + dx
				var qy: int = c.y + dy
				if qx < 0 or qy < 0 or qx >= cols or qy >= rows or grid.is_point_solid(Vector2i(qx, qy)):
					continue
				var ex: float = qx * CELL + CELL * 0.5 - px
				var ey: float = qy * CELL + CELL * 0.5 - py
				best_d = minf(best_d, sqrt(ex * ex + ey * ey))
		if best_d < INF:
			last = mini(last, int(floor((best_d + SNAP_TIE) / CELL + 0.71)))
	if best_d == INF:
		return c
	# Pass 2: among the (near-)nearest cells, the one nearest ref.
	var out: Vector2i = c
	var out_d: float = INF
	var out_ref: float = INF
	for r in range(1, last + 1):
		for dy in range( - r, r + 1):
			for dx in range( - r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var qx: int = c.x + dx
				var qy: int = c.y + dy
				if qx < 0 or qy < 0 or qx >= cols or qy >= rows or grid.is_point_solid(Vector2i(qx, qy)):
					continue
				var cx: float = qx * CELL + CELL * 0.5
				var cy: float = qy * CELL + CELL * 0.5
				var d: float = sqrt((cx - px) * (cx - px) + (cy - py) * (cy - py))
				if d > best_d + SNAP_TIE:
					continue
				var dr: float = sqrt((cx - ref.x) * (cx - ref.x) + (cy - ref.y) * (cy - ref.y)) if use_ref else 0.0
				if dr < out_ref - 0.01 or (dr <= out_ref + 0.01 and d < out_d - 0.01):
					out = Vector2i(qx, qy)
					out_d = d
					out_ref = dr
	return out


# Snapped grid cell for point p with the other end of the query as reference.
# A point exactly on a cell boundary (map centres, keep / control centres and
# centred spawn lines of symmetric maps usually are) must not always take the
# +x / +y cell, or both teams route from / to the same absolute side and get
# different path lengths. The side is the one facing ref; with ref on the same
# line, the side facing the map's centre line; on the centre line itself only a
# point-symmetric map (180-degree rotation) needs a side, taken from the other
# axis (mirror maps map such a query onto itself or keep that coordinate).
func _snap(p: Vector2, ref: Vector2) -> Vector2i:
	var c: Vector2i = cell_of(p)
	if ref.is_finite():
		if c.x > 0 and float(c.x) * CELL == p.x and _low_side(p.x, ref.x, _mid_x, ref.y < p.y):
			c.x -= 1
		if c.y > 0 and float(c.y) * CELL == p.y and _low_side(p.y, ref.y, _mid_y, ref.x < p.x):
			c.y -= 1
	return _free_cell_near(c, p, ref)


func _low_side(v: float, ref_v: float, mid: float, other_low: bool) -> bool:
	if ref_v != v:
		return ref_v < v
	if v != mid:
		return v > mid
	return _point_sym and other_low


func _cell_centre(c: Vector2i) -> Vector2:
	return Vector2(c.x * CELL + CELL * 0.5, c.y * CELL + CELL * 0.5)


# Physical straight-line walkability for a body of radius r under this grid's
# gate signature (map validation tools rely on this meaning).
func clear(a: Vector2, b: Vector2, r: float) -> bool:
	if arena.gates.is_empty():
		return not arena.segment_blocked(a, b, r + 2.0, Arena.MASK_UNITS)
	return not arena.segment_blocked_sig(a, b, r + 2.0, Arena.MASK_UNITS, sig)


# Routing shortcut: physically clear AND
#   - never crossing an always-on damage hazard (lava),
#   - not crossing a periodic damage hazard (spikes, eruption, gravity,
#     shockwave) unless one end already lies inside it (the weighted A* path
#     decided to go through),
#   - keeping LINK_RIM * 0.75 clearance from a portal / jump-pad trigger that
#     holds neither end of the segment.
func safe_clear(a: Vector2, b: Vector2, r: float) -> bool:
	if not _bk_kind.is_empty() and not _blockers_clear(a, b, r):
		return false
	return clear(a, b, r)


func _blockers_clear(a: Vector2, b: Vector2, r: float) -> bool:
	var pad: float = r * 0.3
	var trigger: float = r * 0.28
	var link_pad: float = trigger + LINK_RIM * 0.75
	var sminx: float = minf(a.x, b.x)
	var smaxx: float = maxf(a.x, b.x)
	var sminy: float = minf(a.y, b.y)
	var smaxy: float = maxf(a.y, b.y)
	for k in _bk_kind.size():
		var kind: int = _bk_kind[k]
		var p: float = link_pad if kind == BLOCK_LINK else pad
		var ep: float = trigger if kind == BLOCK_LINK else pad
		var x: float = _bk_x[k]
		var y: float = _bk_y[k]
		var w: float = _bk_w[k]
		if _bk_circle[k] == 1:
			var rr: float = w + p
			# Bounding-box reject (no crossing possible, contains checks moot).
			if x + rr < sminx or x - rr > smaxx or y + rr < sminy or y - rr > smaxy:
				continue
			if kind != BLOCK_ALWAYS:
				var re: float = (w + ep) * (w + ep)
				if (a.x - x) * (a.x - x) + (a.y - y) * (a.y - y) <= re or (b.x - x) * (b.x - x) + (b.y - y) * (b.y - y) <= re:
					continue
			if Arena.seg_circle_t(a, b, Vector2(x, y), rr) >= 0.0:
				return false
		else:
			var hh: float = _bk_h[k]
			if x + w + p < sminx or x - p > smaxx or y + hh + p < sminy or y - p > smaxy:
				continue
			if kind != BLOCK_ALWAYS:
				if (a.x >= x - ep and a.x <= x + w + ep and a.y >= y - ep and a.y <= y + hh + ep) or (b.x >= x - ep and b.x <= x + w + ep and b.y >= y - ep and b.y <= y + hh + ep):
					continue
			if Arena.seg_rect(a, b, x, y, w, hh, p).x >= 0.0:
				return false
	return true


func route_point(start: Vector2, goal: Vector2, r: float, speed: float = 0.0, portal_wait: float = 0.0, pad_wait: float = 0.0, use_links: bool = true) -> Vector2:
	return next_waypoint(start, goal, r, speed, portal_wait, pad_wait, use_links)


func next_waypoint(start: Vector2, goal: Vector2, r: float, speed: float = 0.0, portal_wait: float = 0.0, pad_wait: float = 0.0, use_links: bool = true) -> Vector2:
	if use_links and not links.is_empty():
		var k: int = route_link(start, goal, r, speed, portal_wait, pad_wait)
		if k >= 0:
			return _direct_waypoint(start, links[k].entry, r)
		goal = outside_links(start, goal, r)
	return _direct_waypoint(start, goal, r)


# A walking goal inside a portal / jump-pad trigger circle is pulled back to
# just outside its rim (unless the traveller already stands in the trigger):
# stepping on it would teleport or launch the hero away from where it wanted
# to be (audit B1: most environment portal trips went against the goal).
func outside_links(start: Vector2, goal: Vector2, r: float) -> Vector2:
	for l in links:
		var e: Vector2 = l.entry
		var trigger: float = float(l.entry_r) + r * 0.28
		var d: float = goal.distance_to(e)
		if d >= trigger + LINK_RIM or start.distance_to(e) <= trigger:
			continue
		var dir: Vector2 = (goal - e) / d if d > 0.001 else start - e
		dir = dir.normalized() if dir.length_squared() > 1e-6 else Vector2.RIGHT
		return e + dir * (trigger + LINK_RIM)
	return goal


# Farthest path point (within SCAN_POINTS cells) reachable in a safe straight
# line. The cap bounds the per-call cost on long detours; the waypoint is
# recomputed every tick, so a nearer point on the same path changes nothing.
# The shortcut index found from the START CELL's centre is memoised per
# (start cell, goal cell, radius) - a pure function of the key, so results never
# depend on cache history - and reused while the exact start still sees it.
func _direct_waypoint(start: Vector2, goal: Vector2, r: float) -> Vector2:
	if safe_clear(start, goal, r):
		return goal
	var ca: Vector2i = _snap(start, goal)
	var cb: Vector2i = _snap(goal, start)
	if coarse != null and start.distance_to(goal) > COARSE_MIN:
		cb = _coarse_subgoal(ca, cb)
	var path: = _cell_path(ca, cb, true)
	var n: int = path.size()
	if n < 2:
		# A one-point partial path to another cell means the goal is unreachable
		# (closed gate, enclosed spot) and the traveller already stands at the
		# closest reachable cell: hold there instead of pressing into the wall.
		if n == 1 and ca != cb:
			return path[0]
		return goal
	var top: int = mini(n - 1, SCAN_POINTS)
	var rq: int = clampi(int(r), 0, 63)
	var key: int = ((ca.y * cols + ca.x) * cols * rows + (cb.y * cols + cb.x)) * 64 + rq
	var idx: int = int(_wp_cache.get(key, -1))
	if idx < 0:
		idx = 1
		var centre: Vector2 = Vector2(ca.x * CELL + CELL * 0.5, ca.y * CELL + CELL * 0.5)
		for i in range(top, 1, -1):
			if safe_clear(centre, path[i], float(rq)):
				idx = i
				break
		if _wp_cache.size() >= PATH_CACHE_LIMIT:
			_wp_cache.clear()
		_wp_cache[key] = idx
	if idx > 1 and idx <= top and safe_clear(start, path[idx], r):
		return path[idx]
	for i in range(top, 1, -1):
		if safe_clear(start, path[i], r):
			return path[i]
	return path[1]


func path_points(start: Vector2, goal: Vector2, allow_partial: bool = true) -> PackedVector2Array:
	var ca: Vector2i = _snap(start, goal)
	var cb: Vector2i = _snap(goal, start)
	if coarse != null and start.distance_to(goal) > COARSE_MIN:
		var assisted: PackedVector2Array = _coarse_path_points(ca, cb, allow_partial)
		if not assisted.is_empty():
			return assisted
	return _cell_path(ca, cb, allow_partial)


# Grid path between two snapped cells, memoised per (a, b, partial): a pure
# function of the key.
func _cell_path(a: Vector2i, b: Vector2i, allow_partial: bool) -> PackedVector2Array:
	if grid.is_point_solid(a) or grid.is_point_solid(b):
		return PackedVector2Array()
	# Unreachable goal: the full search would find nothing (exact answer
	# without exploring the start's whole component). On battleground-size
	# maps a partial route to an unreachable goal holds at the start cell
	# instead of searching the whole component for the nearest approach.
	if component_of(a) != component_of(b):
		if not allow_partial:
			return PackedVector2Array()
		if coarse != null:
			return PackedVector2Array([_cell_centre(a)])
	var key: int = ((a.y * cols + a.x) * cols * rows + (b.y * cols + b.x)) * 2 + (1 if allow_partial else 0)
	var hit = _path_cache.get(key)
	if hit != null:
		return hit
	var path: PackedVector2Array = grid.get_point_path(a, b, allow_partial)
	astar_calls += 1
	if _path_cache.size() >= PATH_CACHE_LIMIT:
		_path_cache.clear()
	_path_cache[key] = path
	return path


# Walking length of the direct route (no links), INF if unreachable.
func direct_length(start: Vector2, goal: Vector2, r: float) -> float:
	if clear(start, goal, r):
		return start.distance_to(goal)
	var a: Vector2i = _snap(start, goal)
	var b: Vector2i = _snap(goal, start)
	var pts: = _cell_path(a, b, false)
	if pts.size() < 2:
		# Same cell or unreachable: only a start and goal sharing a free cell count.
		return start.distance_to(goal) if pts.size() == 1 and a == b else INF
	var total: = start.distance_to(pts[0])
	for i in range(1, pts.size()):
		total += pts[i - 1].distance_to(pts[i])
	return total + pts[pts.size() - 1].distance_to(goal)


func path_length(start: Vector2, goal: Vector2, r: float, speed: float = 0.0, portal_wait: float = 0.0, pad_wait: float = 0.0, use_links: bool = true) -> float:
	var direct: float = direct_length(start, goal, r)
	if not use_links or links.is_empty():
		return direct
	var k: int = route_link(start, goal, r, speed, portal_wait, pad_wait, direct)
	if k < 0:
		return direct
	return _link_total(k, start, goal, speed, portal_wait, pad_wait)


# Index of the link the best route uses, or -1 when walking directly is best
# (a link must save LINK_MARGIN px). direct < 0 computes the direct length.
func route_link(start: Vector2, goal: Vector2, r: float, speed: float = 0.0, portal_wait: float = 0.0, pad_wait: float = 0.0, direct: float = -1.0) -> int:
	if links.is_empty():
		return -1
	var v: float = speed if speed > 1.0 else DEFAULT_SPEED
	var best: float = direct
	if best < 0.0:
		best = start.distance_to(goal) if safe_clear(start, goal, r) else direct_length(start, goal, r)
	var best_k: int = -1
	var target: float = best - LINK_MARGIN
	for k in links.size():
		var l: Dictionary = links[k]
		var base: float = float(l.flight) * v
		var exit_to_goal: float = (l.exit as Vector2).distance_to(goal)
		var lower: float = maxf(0.0, start.distance_to(l.entry) - float(l.entry_r)) + base + exit_to_goal
		if lower >= target:
			continue
		var to_entry: float = _to_entry(k, start)
		if to_entry == INF:
			continue
		var wait_s: float = portal_wait if str(l.kind) == "portal" else pad_wait
		var cost: float = to_entry + base + maxf(0.0, wait_s * v - to_entry)
		if cost + exit_to_goal >= target:
			continue
		var from_exit: float = _from_exit(k, goal)
		if from_exit == INF or cost + from_exit >= target:
			continue
		target = cost + from_exit
		best_k = k
	return best_k


func _link_total(k: int, start: Vector2, goal: Vector2, speed: float, portal_wait: float, pad_wait: float) -> float:
	var l: Dictionary = links[k]
	var v: float = speed if speed > 1.0 else DEFAULT_SPEED
	var to_entry: float = _to_entry(k, start)
	var wait_s: float = portal_wait if str(l.kind) == "portal" else pad_wait
	return to_entry + float(l.flight) * v + maxf(0.0, wait_s * v - to_entry) + _from_exit(k, goal)


# Walking distance from p to the rim of link k's entry circle (INF if unreachable).
func _to_entry(k: int, p: Vector2) -> float:
	var l: Dictionary = links[k]
	var entry: Vector2 = l.entry
	var er: float = float(l.entry_r)
	if p.distance_to(entry) <= er:
		return 0.0
	var ca: Vector2i = _snap(p, entry)
	var key: int = ca.y * cols + ca.x
	var memo: Dictionary = _memo_in[k]
	if memo.has(key):
		return float(memo[key]) + p.distance_to(Vector2(ca.x * CELL + CELL * 0.5, ca.y * CELL + CELL * 0.5))
	# The memoised value must be a pure function of the key cell: the entry is
	# snapped toward the key cell's centre, never toward this particular p.
	var cb: Vector2i = _snap(entry, _cell_centre(ca))
	var d: float = INF
	if not grid.is_point_solid(ca) and not grid.is_point_solid(cb) and component_of(ca) == component_of(cb):
		var pts: PackedVector2Array = grid.get_point_path(ca, cb, false)
		if pts.size() == 1:
			d = maxf(0.0, pts[0].distance_to(entry) - er)
		elif pts.size() >= 2:
			d = 0.0
			var reached: bool = false
			for i in range(1, pts.size()):
				var q: Vector2 = pts[i]
				var qd: float = q.distance_to(entry)
				if qd <= er:
					# Stop at the rim: stepping onto the pad/portal is the link.
					var pd: float = pts[i - 1].distance_to(entry)
					d += maxf(0.0, pd - er)
					reached = true
					break
				d += pts[i - 1].distance_to(q)
			if not reached:
				d += maxf(0.0, pts[pts.size() - 1].distance_to(entry) - er)
	if memo.size() >= MEMO_LIMIT:
		memo.clear()
	memo[key] = d
	return d + p.distance_to(Vector2(ca.x * CELL + CELL * 0.5, ca.y * CELL + CELL * 0.5))


# Walking distance from link k's exit point to p (INF if unreachable).
func _from_exit(k: int, p: Vector2) -> float:
	var l: Dictionary = links[k]
	var exitp: Vector2 = l.exit
	if clear(exitp, p, bucket):
		return exitp.distance_to(p)
	var cb: Vector2i = _snap(p, exitp)
	var key: int = cb.y * cols + cb.x
	var memo: Dictionary = _memo_out[k]
	if memo.has(key):
		return float(memo[key]) + p.distance_to(Vector2(cb.x * CELL + CELL * 0.5, cb.y * CELL + CELL * 0.5))
	var ca: Vector2i = _snap(exitp, _cell_centre(cb))
	var d: float = INF
	if not grid.is_point_solid(ca) and not grid.is_point_solid(cb) and component_of(ca) == component_of(cb):
		var pts: PackedVector2Array = grid.get_point_path(ca, cb, false)
		if pts.size() >= 1:
			d = exitp.distance_to(pts[0])
			for i in range(1, pts.size()):
				d += pts[i - 1].distance_to(pts[i])
	if memo.size() >= MEMO_LIMIT:
		memo.clear()
	memo[key] = d
	return d + p.distance_to(Vector2(cb.x * CELL + CELL * 0.5, cb.y * CELL + CELL * 0.5))


# --- V2 scale (B-PERF) ---
# Connected components of the free cells, labelled once per grid from the
# runs of free cells _build records row by row (union-find over runs that
# overlap in neighbouring rows). Diagonal steps need both orthogonal
# neighbours free (DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES), so 4-neighbour
# components are exactly the reachable sets. A query whose ends lie in
# different components is answered without a search; reachable queries run
# the same A* as before, so routes on every map are unchanged.
# Reference switch: build every grid with the per-cell solid test.
static var slow_build: bool = false
# Profiling counter for tools: grid searches that missed the path memo.
static var astar_calls: int = 0
var _run_row: PackedInt32Array = PackedInt32Array()
var _run_x0: PackedInt32Array = PackedInt32Array()
var _run_x1: PackedInt32Array = PackedInt32Array()
var _row_first: PackedInt32Array = PackedInt32Array()
var _run_label: PackedInt32Array = PackedInt32Array()
var component_count: int = 0


func _add_run(y: int, x0: int, x1: int) -> void:
	_run_row.append(y)
	_run_x0.append(x0)
	_run_x1.append(x1)


func _label_components() -> void:
	var n: int = _run_x0.size()
	_uf = PackedInt32Array()
	_uf.resize(n)
	for i in n:
		_uf[i] = i
	for y in range(rows - 1):
		var i: int = _row_first[y]
		var i_end: int = _row_first[y + 1]
		var j: int = i_end
		var j_end: int = _row_first[y + 2]
		while i < i_end and j < j_end:
			if _run_x0[i] <= _run_x1[j] and _run_x0[j] <= _run_x1[i]:
				var ra: int = _find(i)
				var rb: int = _find(j)
				if ra != rb:
					_uf[maxi(ra, rb)] = mini(ra, rb)
			if _run_x1[i] < _run_x1[j]:
				i += 1
			else:
				j += 1
	_run_label.resize(n)
	var ids: Dictionary = {}
	for k in n:
		var root: int = _find(k)
		if not ids.has(root):
			ids[root] = ids.size()
		_run_label[k] = int(ids[root])
	component_count = ids.size()
	_uf = PackedInt32Array()


# Union-find root with path compression (member array: packed arrays are
# copied on write when passed to a function).
var _uf: PackedInt32Array = PackedInt32Array()


func _find(i: int) -> int:
	var r: int = i
	while _uf[r] != r:
		r = _uf[r]
	while _uf[i] != r:
		var nxt: int = _uf[i]
		_uf[i] = r
		i = nxt
	return r


# Component label of a cell (-1 = solid or outside the grid).
func component_of(c: Vector2i) -> int:
	if c.x < 0 or c.y < 0 or c.x >= cols or c.y >= rows:
		return -1
	var lo: int = _row_first[c.y]
	var hi: int = _row_first[c.y + 1] - 1
	while lo <= hi:
		var mid: int = (lo + hi) >> 1
		if c.x < _run_x0[mid]:
			hi = mid - 1
		elif c.x > _run_x1[mid]:
			lo = mid + 1
		else:
			return _run_label[mid]
	return -1


# Test hook: cells where the per-obstacle build and the per-cell reference
# disagree (0 = identical solid sets).
func debug_build_mismatch() -> int:
	var pad: float = bucket + 3.0
	var fast: PackedByteArray = _solid_by_shapes(pad)
	var ref: PackedByteArray = _solid_by_cells(pad)
	var bad: int = 0
	for i in fast.size():
		if fast[i] != ref[i]:
			bad += 1
	return bad


# Coarse routing for battleground-size maps only (area above
# BattleSim.SCALE_AREA; every existing map keeps the exact fine routes). A
# walk longer than COARSE_MIN heads for a subgoal COARSE_AHEAD steps along a
# 64 px coarse path, so each fine A* spans about 640 px instead of the whole
# map. A coarse cell is open when at least COARSE_FREE_MIN of its 16 fine cells
# are; its subgoal is its free fine cell nearest the centre. The subgoal is a
# pure function of (start cell, goal cell), so memoised routes never depend on
# query history.
const COARSE_K: = 4
const COARSE_MIN: = 1500.0
const COARSE_AHEAD: = 10
const COARSE_FREE_MIN: = 8
const COARSE_MEMO_LIMIT: = 2048
var coarse: AStarGrid2D = null
var coarse_cols: int = 0
var coarse_rows: int = 0
var _coarse_rep: PackedInt32Array = PackedInt32Array()
var _coarse_paths: Dictionary = {}


func _build_coarse() -> void:
	coarse_cols = int(ceil(float(cols) / COARSE_K))
	coarse_rows = int(ceil(float(rows) / COARSE_K))
	coarse = AStarGrid2D.new()
	coarse.region = Rect2i(0, 0, coarse_cols, coarse_rows)
	coarse.cell_size = Vector2(CELL * COARSE_K, CELL * COARSE_K)
	coarse.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	coarse.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	coarse.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	coarse.update()
	var free_n: PackedInt32Array = PackedInt32Array()
	free_n.resize(coarse_cols * coarse_rows)
	free_n.fill(0)
	for k in _run_x0.size():
		var qy: int = _run_row[k] / COARSE_K
		var x0: int = _run_x0[k]
		var x1: int = _run_x1[k]
		var qx: int = x0 / COARSE_K
		while qx * COARSE_K <= x1:
			free_n[qy * coarse_cols + qx] += mini(x1, qx * COARSE_K + COARSE_K - 1) - maxi(x0, qx * COARSE_K) + 1
			qx += 1
	# Fine cells of a block by distance from its centre (ties in scan order).
	var order: Array = []
	for dy in COARSE_K:
		for dx in COARSE_K:
			var ex: float = dx + 0.5 - COARSE_K * 0.5
			var ey: float = dy + 0.5 - COARSE_K * 0.5
			order.append([ex * ex + ey * ey, dy * COARSE_K + dx, dx, dy])
	order.sort_custom(func(p: Array, q: Array) -> bool: return float(p[0]) < float(q[0]) or (float(p[0]) == float(q[0]) and int(p[1]) < int(q[1])))
	_coarse_rep.resize(coarse_cols * coarse_rows)
	_coarse_rep.fill(-1)
	for qy2 in coarse_rows:
		for qx2 in coarse_cols:
			var q: int = qy2 * coarse_cols + qx2
			if free_n[q] >= COARSE_FREE_MIN:
				for o in order:
					var fx: int = qx2 * COARSE_K + int(o[2])
					var fy: int = qy2 * COARSE_K + int(o[3])
					if fx < cols and fy < rows and not grid.is_point_solid(Vector2i(fx, fy)):
						_coarse_rep[q] = fy * cols + fx
						break
			if _coarse_rep[q] < 0:
				coarse.set_point_solid(Vector2i(qx2, qy2), true)


func _coarse_open(q: Vector2i) -> Vector2i:
	if not coarse.is_point_solid(q):
		return q
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
		var n: Vector2i = q + d
		if n.x >= 0 and n.y >= 0 and n.x < coarse_cols and n.y < coarse_rows and not coarse.is_point_solid(n):
			return n
	return Vector2i(-1, -1)


# Fine cell to route toward instead of cb (cb itself when the coarse route is
# short, missing or leads into another component).
func _coarse_subgoal(ca: Vector2i, cb: Vector2i) -> Vector2i:
	var qa: Vector2i = _coarse_open(Vector2i(ca.x / COARSE_K, ca.y / COARSE_K))
	var qb: Vector2i = _coarse_open(Vector2i(cb.x / COARSE_K, cb.y / COARSE_K))
	if qa.x < 0 or qb.x < 0 or qa == qb:
		return cb
	var key: int = (qa.y * coarse_cols + qa.x) * coarse_cols * coarse_rows + (qb.y * coarse_cols + qb.x)
	var path = _coarse_paths.get(key)
	if path == null:
		path = coarse.get_id_path(qa, qb, false)
		if _coarse_paths.size() >= COARSE_MEMO_LIMIT:
			_coarse_paths.clear()
		_coarse_paths[key] = path
	if (path as Array).size() <= COARSE_AHEAD + 1:
		return cb
	var node: Vector2i = path[COARSE_AHEAD]
	var rep: int = _coarse_rep[node.y * coarse_cols + node.x]
	if rep < 0:
		return cb
	var sub: Vector2i = Vector2i(rep % cols, rep / cols)
	if component_of(sub) != component_of(ca):
		return cb
	return sub


# Long path_points on a battleground-size map: the exact fine path to the
# coarse subgoal, then the coarse route's cell representatives to cb (callers
# sample only the first few hundred pixels: fronts, scout and sight points).
# Empty when the coarse route does not apply (the caller searches in full).
func _coarse_path_points(ca: Vector2i, cb: Vector2i, allow_partial: bool) -> PackedVector2Array:
	var sub: Vector2i = _coarse_subgoal(ca, cb)
	if sub == cb:
		return PackedVector2Array()
	var head: PackedVector2Array = _cell_path(ca, sub, allow_partial)
	if head.size() < 2 or _cell_centre(sub).distance_squared_to(head[head.size() - 1]) > 1.0:
		return PackedVector2Array()
	var qa: Vector2i = _coarse_open(Vector2i(ca.x / COARSE_K, ca.y / COARSE_K))
	var qb: Vector2i = _coarse_open(Vector2i(cb.x / COARSE_K, cb.y / COARSE_K))
	var route: Array = _coarse_paths.get((qa.y * coarse_cols + qa.x) * coarse_cols * coarse_rows + (qb.y * coarse_cols + qb.x), [])
	var out: PackedVector2Array = head.duplicate()
	for i in range(COARSE_AHEAD + 1, route.size() - 1):
		var node: Vector2i = route[i]
		var rep: int = _coarse_rep[node.y * coarse_cols + node.x]
		if rep >= 0:
			out.append(_cell_centre(Vector2i(rep % cols, rep / cols)))
	out.append(_cell_centre(cb))
	return out


# Whether a body of this grid's bucket can walk from a to b (snapped like a
# route query). Map validation can use it instead of one A* per anchor.
func reachable(a: Vector2, b: Vector2) -> bool:
	var ca: Vector2i = _snap(a, b)
	var cb: Vector2i = _snap(b, a)
	var la: int = component_of(ca)
	return la >= 0 and la == component_of(cb)
