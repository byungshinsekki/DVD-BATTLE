extends SceneTree

# V1.5.3 map-format contract (DESIGN_153 §3). Checks the twelve elimination and
# three control maps for variety (size, aspect, area, spawn orientation,
# archetype), exact declared symmetry of every piece (obstacles, gates, hazards
# with their phases, brush, pads, portals, spawns, objectives), connectivity for
# body buckets 12/18/26/28 in every gate state, fairness of path lengths from
# each team's spawn centroid, spawn-to-spawn distance (walking and through
# portals / jump pads), stalemate guards (no hidden or deep blockers across the
# centre line), spawn safety, gimmick coverage and per-map hazard parameter
# uniqueness (deathmatch presets included). Gate states are evaluated on private copies of the map
# data (gates removed = open, gates kept = closed) because the navigation grid
# of the shipped engine treats every obstacle as permanent.
#
# Distances use the Navigator grid convention (16 px cells, cell solid when the
# body + 3 px overlaps a unit-blocking obstacle or the body leaves the bounds,
# octile moves without corner cutting) computed as a full Dijkstra field.

const BUCKETS: Array = [12.0, 18.0, 26.0, 28.0]
const CELL: float = 16.0
const FAIR_TOLERANCE: float = 0.03
const SYMMETRY_TOLERANCE: float = 0.5
# Longest unit-blocked stretch of the spawn-centroid line: V1.5.3 thorn_circuit
# had a 528 px thicket there and both teams parked out of range on either side.
const PARKING_GAP: float = 300.0
const LINK_SPEED: float = 150.0 # Navigator.DEFAULT_SPEED: jump-pad flight seconds -> px
const NEW_TYPES: Array = ["artillery", "jump_pad", "closing_ring", "mud"]
const OLD_TYPES: Array = ["lava", "spikes", "eruption", "wind", "portal", "haste", "healing_fountain", "gravity", "shockwave"]
# Keys that are geometry or naming; every other hazard key must match its image.
const GEOMETRY_KEYS: Array = ["id", "label", "x", "y", "w", "h", "radius", "directionA", "directionB", "exitFacing", "target", "pairId", "center", "dirA", "dirB", "exit", "color", "landing", "tbit"]

var passed: int = 0
var failed: Array = []
var reports: Array = []


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed.append(label)
		push_error("MAPS_153 " + label)


# ------------------------------------------------------------------ symmetry (independent of ArenaData)

func _img(sym: String, w: float, h: float, p: Vector2) -> Vector2:
	match sym:
		"mirror_x":
			return Vector2(w - p.x, p.y)
		"mirror_y":
			return Vector2(p.x, h - p.y)
		"mirror_anti":
			return Vector2(w - p.y, h - p.x)
		"point":
			return Vector2(w - p.x, h - p.y)
	return Vector2.INF


func _img_vec(sym: String, v: Vector2) -> Vector2:
	match sym:
		"mirror_x":
			return Vector2(-v.x, v.y)
		"mirror_y":
			return Vector2(v.x, -v.y)
		"mirror_anti":
			return Vector2(-v.y, -v.x)
	return -v


func _rect_of(d: Dictionary) -> Rect2:
	return Rect2(float(d.x), float(d.y), float(d.get("w", 0.0)), float(d.get("h", 0.0)))


func _shape_image(sym: String, a: Arena, d: Dictionary) -> Dictionary:
	if str(d.get("shape", "rect")) == "circle" or not d.has("w"):
		var c: Vector2 = _img(sym, a.width, a.height, Vector2(float(d.x), float(d.y)))
		return {"circle": true, "c": c, "r": float(d.get("radius", 0.0))}
	var r: Rect2 = _rect_of(d)
	var p: Vector2 = _img(sym, a.width, a.height, r.position)
	var q: Vector2 = _img(sym, a.width, a.height, r.end)
	return {"circle": false, "rect": Rect2(minf(p.x, q.x), minf(p.y, q.y), absf(q.x - p.x), absf(q.y - p.y))}


func _shape_matches(img: Dictionary, d: Dictionary) -> bool:
	if bool(img.circle):
		return (str(d.get("shape", "rect")) == "circle" or not d.has("w")) and (img.c as Vector2).distance_to(Vector2(float(d.x), float(d.y))) <= SYMMETRY_TOLERANCE \
			and absf(float(img.r) - float(d.get("radius", 0.0))) <= SYMMETRY_TOLERANCE
	if str(d.get("shape", "rect")) == "circle" or not d.has("w"):
		return false
	var r: Rect2 = img.rect
	var o: Rect2 = _rect_of(d)
	return r.position.distance_to(o.position) <= SYMMETRY_TOLERANCE and r.end.distance_to(o.end) <= SYMMETRY_TOLERANCE


func _vec(d: Variant) -> Vector2:
	return Vector2(float(d.x), float(d.y))


func _params_equal(a: Dictionary, b: Dictionary) -> bool:
	for k in a:
		if GEOMETRY_KEYS.has(str(k)):
			continue
		if not b.has(k) or JSON.stringify(a[k]) != JSON.stringify(b[k]):
			return false
	for k in b:
		if not GEOMETRY_KEYS.has(str(k)) and not a.has(k):
			return false
	return true


func _find_hazard_image(sym: String, a: Arena, h: Dictionary) -> Dictionary:
	var img: Dictionary = _shape_image(sym, a, h)
	for o: Dictionary in a.hazards:
		if str(o.type) != str(h.type) or not _shape_matches(img, o) or not _params_equal(h, o):
			continue
		var ok: bool = true
		for key in ["directionA", "directionB", "exitFacing"]:
			if h.has(key) != o.has(key):
				ok = false
			elif h.has(key) and _img_vec(sym, _vec(h[key]).normalized()).distance_to(_vec(o[key]).normalized()) > 0.01:
				ok = false
		if h.has("target") and (not o.has("target") or _img(sym, a.width, a.height, _vec(h.target)).distance_to(_vec(o.target)) > SYMMETRY_TOLERANCE):
			ok = false
		if ok:
			return o
	return {}


func _check_symmetry(a: Arena, sym: String, row: Dictionary) -> void:
	var tag: String = a.id + " symmetry(" + sym + ")"
	check(sym in ["point", "mirror_x", "mirror_y", "mirror_anti"], tag + " declared kind")
	if sym == "mirror_anti":
		check(is_equal_approx(a.width, a.height), tag + " anti-diagonal mirror needs a square map")
	check(absf(a.min_x - (a.width - a.max_x)) < 0.11 and absf(a.min_y - (a.height - a.max_y)) < 0.11, tag + " symmetric bounds")
	var bad: Array = []
	for i in a.obs_count:
		var o: Dictionary = a.obstacles[i]
		var img: Dictionary = _shape_image(sym, a, o)
		var found: bool = false
		for j in a.obs_count:
			var p: Dictionary = a.obstacles[j]
			if a.obs_mask[i] == a.obs_mask[j] and str(o.get("kind", "")) == str(p.get("kind", "")) and _shape_matches(img, p) \
					and JSON.stringify(o.get("gate", {})) == JSON.stringify(p.get("gate", {})):
				found = true
				break
		if not found:
			bad.append("obstacle:" + str(o.id))
	var pair_of: Dictionary = {}
	for h: Dictionary in a.hazards:
		var im: Dictionary = _find_hazard_image(sym, a, h)
		if im.is_empty():
			bad.append("hazard:" + str(h.id))
		else:
			pair_of[str(h.id)] = str(im.id)
	for h: Dictionary in a.hazards:
		if str(h.type) == "portal" and pair_of.has(str(h.id)) and pair_of.has(str(h.get("pairId", ""))):
			var twin: String = pair_of[str(h.id)]
			var twin_pair: String = ""
			for o2: Dictionary in a.hazards:
				if str(o2.id) == twin:
					twin_pair = str(o2.get("pairId", ""))
			if twin_pair != pair_of[str(h.pairId)]:
				bad.append("portal_pair:" + str(h.id))
	var patch_map: Dictionary = {}
	for k in a.forests.size():
		var f: Dictionary = a.forests[k]
		var c: Vector2 = _img(sym, a.width, a.height, Vector2(float(f.x), float(f.y)))
		var hit: int = -1
		for m in a.forests.size():
			var g: Dictionary = a.forests[m]
			if c.distance_to(Vector2(float(g.x), float(g.y))) <= SYMMETRY_TOLERANCE and absf(float(f.radius) - float(g.radius)) <= SYMMETRY_TOLERANCE:
				hit = m
				break
		if hit < 0:
			bad.append("brush:%d" % k)
			continue
		var pa: int = int(f.get("patch", k))
		var pb: int = int(a.forests[hit].get("patch", hit))
		if patch_map.has(pa) and int(patch_map[pa]) != pb:
			bad.append("brush_patch:%d" % pa)
		patch_map[pa] = pb
	for i in a.spawns[0].size():
		if i >= a.spawns[1].size() or _img(sym, a.width, a.height, a.spawns[0][i]).distance_to(a.spawns[1][i]) > SYMMETRY_TOLERANCE:
			bad.append("spawn_slot:%d" % i)
	for group in [a.control_points, a.heal_zones]:
		for cp: Dictionary in group:
			var c2: Vector2 = _img(sym, a.width, a.height, cp.center)
			var ok: bool = false
			for other: Dictionary in group:
				if c2.distance_to(other.center) <= SYMMETRY_TOLERANCE and absf(float(cp.radius) - float(other.radius)) <= SYMMETRY_TOLERANCE:
					ok = true
			if not ok:
				bad.append("objective:" + str(cp.id))
	check(bad.is_empty(), tag + " every piece maps onto an identical piece " + str(bad))
	row["symmetry"] = sym
	row["asymmetric_pieces"] = bad


# ------------------------------------------------------------------ gate states and distance fields

func _gate_groups(a: Arena) -> Array:
	var groups: Array = []
	for o: Dictionary in a.obstacles:
		if o.has("gate"):
			var g: String = str((o.gate as Dictionary).get("group", "A"))
			if not groups.has(g):
				groups.append(g)
	groups.sort()
	return groups


# Private Arena copy for a gate state: open groups are removed from the data.
func _state_arena(a: Arena, open_groups: Array) -> Arena:
	if _gate_groups(a).is_empty():
		return a
	var d: Dictionary = a.data.duplicate(true)
	var kept: Array = []
	for o: Dictionary in a.obstacles:
		if o.has("gate") and open_groups.has(str((o.gate as Dictionary).get("group", "A"))):
			continue
		kept.append(o.duplicate(true))
	d.obstacles = kept
	return Arena.from_data(d)


# Named states: "static" = every gate solid (also the no-gate state), canonical
# signatures = exactly one group open (or all-open for one group).
func _states(a: Arena) -> Dictionary:
	var groups: Array = _gate_groups(a)
	var out: Dictionary = {"static": _state_arena(a, [])}
	if groups.is_empty():
		return out
	out["all_open"] = _state_arena(a, groups)
	if groups.size() >= 2:
		for g in groups:
			out["open_" + str(g)] = _state_arena(a, [g])
	return out


func _canonical(states: Dictionary) -> Array:
	var names: Array = []
	for k in states:
		if str(k).begins_with("open_"):
			names.append(k)
	if names.is_empty():
		names.append("all_open" if states.has("all_open") else "static")
	return names


class Grid extends RefCounted:
	var cols: int
	var rows: int
	var solid: PackedByteArray

	func idx(c: Vector2i) -> int:
		return c.y * cols + c.x


func _grid(a: Arena, bucket: float) -> Grid:
	var g := Grid.new()
	g.cols = int(ceil(a.width / CELL))
	g.rows = int(ceil(a.height / CELL))
	g.solid.resize(g.cols * g.rows)
	var pad: float = bucket + 3.0
	for y in g.rows:
		for x in g.cols:
			var c := Vector2(x * CELL + CELL * 0.5, y * CELL + CELL * 0.5)
			var s: bool = c.x < a.min_x + bucket or c.x > a.max_x - bucket or c.y < a.min_y + bucket or c.y > a.max_y - bucket
			if not s:
				s = a.inside_obstacle(c, pad, Arena.MASK_UNITS)
			g.solid[y * g.cols + x] = 1 if s else 0
	return g


func _cell_of(g: Grid, p: Vector2) -> Vector2i:
	return Vector2i(clampi(int(p.x / CELL), 0, g.cols - 1), clampi(int(p.y / CELL), 0, g.rows - 1))


func _free_near(g: Grid, p: Vector2) -> Vector2i:
	var c: Vector2i = _cell_of(g, p)
	if g.solid[g.idx(c)] == 0:
		return c
	var best: Vector2i = Vector2i(-1, -1)
	var best_d: float = INF
	for r in range(1, 8):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var q := Vector2i(c.x + dx, c.y + dy)
				if q.x < 0 or q.y < 0 or q.x >= g.cols or q.y >= g.rows or g.solid[g.idx(q)] == 1:
					continue
				var d: float = p.distance_to(Vector2(q.x * CELL + CELL * 0.5, q.y * CELL + CELL * 0.5))
				if d < best_d:
					best_d = d
					best = q
		if best.x >= 0:
			return best
	return Vector2i(-1, -1)


# Any-angle length: the Dijkstra cell chain from the target back to the source,
# string-pulled with the body-radius corridor test. The octile grid overstates
# oblique straight lines by up to 8 percent; this is the real walking length.
func _geodesic(sa: Arena, g: Grid, bucket: float, from: Vector2, to: Vector2) -> float:
	var parent := PackedInt32Array()
	var field: PackedFloat32Array = _field(g, from, parent)
	var best: int = -1
	var best_d: float = INF
	for q: Vector2i in _anchor_cells(g, to):
		var d: float = field[g.idx(q)] + to.distance_to(Vector2(q.x * CELL + CELL * 0.5, q.y * CELL + CELL * 0.5))
		if d < best_d:
			best_d = d
			best = g.idx(q)
	if best < 0 or not is_finite(best_d):
		return INF
	var pts: Array = [to]
	var k: int = best
	while k >= 0:
		pts.append(Vector2((k % g.cols) * CELL + CELL * 0.5, (k / g.cols) * CELL + CELL * 0.5))
		k = parent[k]
	pts.append(from)
	pts.reverse()
	var total: float = 0.0
	var i: int = 0
	while i < pts.size() - 1:
		var j: int = pts.size() - 1
		while j > i + 1 and sa.segment_blocked(pts[i], pts[j], bucket + 2.0, Arena.MASK_UNITS):
			j -= 1
		total += (pts[i] as Vector2).distance_to(pts[j])
		i = j
	return total


# Portal / jump-pad links in the Navigator convention (DESIGN_153 §2): entry
# = hazard centre (reached at its rim), pad exit = landing, portal exit = pair
# centre + exitFacing * (pair radius + body + 8), cost = flight seconds x 150.
func _links(a: Arena, bucket: float) -> Array:
	var out: Array = []
	for h: Dictionary in a.hazards:
		var typ: String = str(h.type)
		if typ == "jump_pad":
			out.append({"id": str(h.id), "entry": h.center, "r": float(h.radius), "exit": _vec(h.target), "cost": float(h.get("flightTime", 0.8)) * LINK_SPEED})
		elif typ == "portal":
			for o: Dictionary in a.hazards:
				if str(o.id) == str(h.get("pairId", "")):
					var dir: Vector2 = o.get("exit", ((o.center as Vector2) - (h.center as Vector2)).normalized())
					out.append({"id": str(h.id), "entry": h.center, "r": float(h.radius), "exit": (o.center as Vector2) + dir * (float(o.radius) + bucket + 8.0), "cost": 0.0})
	return out


# Shortest spawn-to-spawn route that uses one or two links (INF without links).
func _link_path(sa: Arena, g: Grid, bucket: float, from: Vector2, to: Vector2) -> float:
	var links: Array = _links(sa, bucket)
	var best: float = INF
	var to_entry: Array = []
	var from_exit: Array = []
	for l: Dictionary in links:
		to_entry.append(maxf(0.0, _geodesic(sa, g, bucket, from, l.entry) - float(l.r)))
		from_exit.append(_geodesic(sa, g, bucket, l.exit, to))
	for i in links.size():
		best = minf(best, float(to_entry[i]) + float(links[i].cost) + float(from_exit[i]))
		for j in links.size():
			if i == j:
				continue
			var mid: float = maxf(0.0, _geodesic(sa, g, bucket, links[i].exit, links[j].entry) - float(links[j].r))
			best = minf(best, float(to_entry[i]) + float(links[i].cost) + mid + float(links[j].cost) + float(from_exit[j]))
	return best


# Dijkstra field (octile, no corner cutting) from a point.
func _field(g: Grid, source: Vector2, parent: PackedInt32Array = PackedInt32Array()) -> PackedFloat32Array:
	parent.resize(g.cols * g.rows)
	parent.fill(-1)
	var dist := PackedFloat32Array()
	dist.resize(g.cols * g.rows)
	dist.fill(INF)
	var heap_d := PackedFloat32Array()
	var heap_i := PackedInt32Array()
	for s: Vector2i in _anchor_cells(g, source):
		var start: int = g.idx(s)
		dist[start] = source.distance_to(Vector2(s.x * CELL + CELL * 0.5, s.y * CELL + CELL * 0.5))
		_push(heap_d, heap_i, dist[start], start)
	var dirs: Array = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
	while not heap_i.is_empty():
		var top_d: float = heap_d[0]
		var top: int = heap_i[0]
		_pop(heap_d, heap_i)
		if top_d > dist[top] + 1e-4:
			continue
		var cx: int = top % g.cols
		var cy: int = top / g.cols
		for dvec: Vector2i in dirs:
			var nx: int = cx + dvec.x
			var ny: int = cy + dvec.y
			if nx < 0 or ny < 0 or nx >= g.cols or ny >= g.rows:
				continue
			var ni: int = ny * g.cols + nx
			if g.solid[ni] == 1:
				continue
			var step: float = CELL
			if dvec.x != 0 and dvec.y != 0:
				if g.solid[cy * g.cols + nx] == 1 or g.solid[ny * g.cols + cx] == 1:
					continue
				step = CELL * 1.41421356
			var nd: float = top_d + step
			if nd < dist[ni] - 1e-4:
				dist[ni] = nd
				parent[ni] = top
				_push(heap_d, heap_i, nd, ni)
	return dist


func _push(hd: PackedFloat32Array, hi: PackedInt32Array, d: float, i: int) -> void:
	hd.append(d)
	hi.append(i)
	var k: int = hd.size() - 1
	while k > 0:
		var p: int = (k - 1) / 2
		if hd[p] <= hd[k]:
			break
		var td: float = hd[p]
		hd[p] = hd[k]
		hd[k] = td
		var ti: int = hi[p]
		hi[p] = hi[k]
		hi[k] = ti
		k = p


func _pop(hd: PackedFloat32Array, hi: PackedInt32Array) -> void:
	var last: int = hd.size() - 1
	hd[0] = hd[last]
	hi[0] = hi[last]
	hd.resize(last)
	hi.resize(last)
	var k: int = 0
	var n: int = last
	while true:
		var l: int = k * 2 + 1
		var r: int = l + 1
		var m: int = k
		if l < n and hd[l] < hd[m]:
			m = l
		if r < n and hd[r] < hd[m]:
			m = r
		if m == k:
			break
		var td: float = hd[m]
		hd[m] = hd[k]
		hd[k] = td
		var ti: int = hi[m]
		hi[m] = hi[k]
		hi[k] = ti
		k = m


# Free cells around p (the first non-empty Chebyshev ring plus one more ring),
# so a point on a cell border or inside a small obstacle is resolved the same
# way on both sides of a symmetric map.
func _anchor_cells(g: Grid, p: Vector2) -> Array:
	var c: Vector2i = _cell_of(g, p)
	var out: Array = []
	var limit: int = 12
	for r in range(0, 13):
		if r > limit:
			break
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var q := Vector2i(c.x + dx, c.y + dy)
				if q.x < 0 or q.y < 0 or q.x >= g.cols or q.y >= g.rows or g.solid[g.idx(q)] == 1:
					continue
				out.append(q)
		if not out.is_empty() and limit == 12:
			limit = r + 1
	return out


func _dist_at(g: Grid, field: PackedFloat32Array, p: Vector2) -> float:
	var best: float = INF
	for q: Vector2i in _anchor_cells(g, p):
		best = minf(best, field[g.idx(q)] + p.distance_to(Vector2(q.x * CELL + CELL * 0.5, q.y * CELL + CELL * 0.5)))
	return best


# ------------------------------------------------------------------ features

func _centroid(points: Array) -> Vector2:
	var c := Vector2.ZERO
	for p: Vector2 in points:
		c += p
	return c / maxf(1.0, float(points.size()))


# Walkable anchor points of every public feature: [label, point, needs_open_gate].
func _features(a: Arena) -> Array:
	var out: Array = []
	for h: Dictionary in a.hazards:
		var typ: String = str(h.type)
		if typ == "portal":
			for o: Dictionary in a.hazards:
				if str(o.id) == str(h.get("pairId", "")):
					out.append(["portal_exit:" + str(h.id), (o.center as Vector2) + (o.get("exit", Vector2.ZERO) as Vector2) * (float(o.radius) + 38.0)])
		if typ == "jump_pad":
			out.append(["jump_target:" + str(h.id), _vec(h.target)])
		out.append([typ + ":" + str(h.id), h.center])
	for cp: Dictionary in a.control_points:
		out.append(["capture:" + str(cp.id), cp.center])
	for hz: Dictionary in a.heal_zones:
		out.append(["heal:" + str(hz.id), hz.center])
	var patches: Dictionary = {}
	for f: Dictionary in a.forests:
		var k: int = int(f.get("patch", 0))
		if not patches.has(k):
			patches[k] = []
		(patches[k] as Array).append(Vector2(float(f.x), float(f.y)))
	for k in patches:
		out.append(["brush:%d" % k, _centroid(patches[k])])
	for o: Dictionary in a.obstacles:
		if o.has("gate"):
			out.append(["gate:" + str(o.id), Arena._shape_center(o)])
	return out


func _feature_types(a: Arena) -> Dictionary:
	var types: Dictionary = {}
	for h: Dictionary in a.hazards:
		types[str(h.type)] = true
	for o: Dictionary in a.obstacles:
		if o.has("gate"):
			types["gate"] = true
	if not a.forests.is_empty():
		types["brush"] = true
	return types


# Hazard parameter signature (every non-geometry key, phases included) -> maps
# using it. A signature may repeat inside one map (symmetric twins) but never
# across maps: no copy-paste parameter sets (DESIGN_153 §3).
func _record_params(a: Arena, map_key: String, params_by_type: Dictionary) -> void:
	for h: Dictionary in a.hazards:
		var sig: Dictionary = {}
		for k in h:
			if not GEOMETRY_KEYS.has(str(k)) and str(k) not in ["type", "shape", "tbit", "landing"]:
				sig[k] = h[k]
		var key: String = str(h.type) + "|" + JSON.stringify(sig)
		if not params_by_type.has(key):
			params_by_type[key] = {}
		(params_by_type[key] as Dictionary)[map_key] = true


# ------------------------------------------------------------------ per map

func _inspect(a: Arena, coverage: Dictionary, params_by_type: Dictionary) -> Dictionary:
	var d: Dictionary = a.data
	var row: Dictionary = {"id": a.id, "ruleset": a.ruleset, "size": [a.width, a.height], "aspect": snappedf(a.width / a.height, 0.001),
		"area_x": snappedf(a.width * a.height / (Arena.WIDTH * Arena.HEIGHT), 0.001), "orientation": str(d.get("spawn_orientation", "")),
		"archetype": str(d.get("archetype", "")), "layout_id": str(d.get("layout_id", ""))}
	var sym: String = str(d.get("symmetry", ""))
	_check_symmetry(a, sym, row)
	# Bounds and pieces inside the canvas.
	check(a.min_x > 0.0 and a.min_y > 0.0 and a.max_x < a.width and a.max_y < a.height, a.id + " playable bounds inside the canvas")
	check(absf(a.min_x - snappedf(37.4 * minf(a.width, a.height) / 792.0, 0.1)) < 0.11, a.id + " bounds margin follows the size (B5 contract)")
	for i in a.obs_count:
		check(a.obs_minx[i] >= a.min_x - 0.01 and a.obs_maxx[i] <= a.max_x + 0.01 and a.obs_miny[i] >= a.min_y - 0.01 and a.obs_maxy[i] <= a.max_y + 0.01,
			a.id + " obstacle inside bounds " + str(a.obs_ids[i]))
	for h: Dictionary in a.hazards:
		var c: Vector2 = h.center
		check(c.x >= a.min_x and c.x <= a.max_x and c.y >= a.min_y and c.y <= a.max_y, a.id + " hazard inside bounds " + str(h.id))
		if h.has("target"):
			var t: Vector2 = _vec(h.target)
			check(a.is_walkable(t, 28.0), a.id + " jump landing walkable for the largest body " + str(h.id))
			for o: Dictionary in a.hazards:
				if str(o.type) in ["jump_pad", "lava"]:
					check(not Arena.shape_contains(o, t, 30.0), a.id + " jump landing clear of pads and lava " + str(h.id) + "/" + str(o.id))
	# Spawns: five per team, clear bodies, not in hazards or brush.
	for team in [0, 1]:
		var sp: Array = a.spawns[team]
		check(sp.size() == 5, a.id + " five spawn slots team %d" % team)
		for i in sp.size():
			var p: Vector2 = sp[i]
			check(a.is_walkable(p, 30.0), a.id + " spawn clear of obstacles %d/%d" % [team, i])
			for h: Dictionary in a.hazards:
				if str(h.type) == "closing_ring":
					continue
				check(not Arena.shape_contains(h, p, 24.0), a.id + " spawn outside hazard %d/%d %s" % [team, i, str(h.id)])
			for f: Dictionary in a.forests:
				check(p.distance_to(Vector2(float(f.x), float(f.y))) > float(f.radius) + 24.0, a.id + " spawn outside brush %d/%d" % [team, i])
			for j in range(i + 1, sp.size()):
				check(p.distance_to(sp[j]) >= 60.0, a.id + " same-team bodies do not overlap %d/%d-%d" % [team, i, j])
	# Features and coverage.
	var types: Dictionary = _feature_types(a)
	for t in types:
		coverage[t] = (coverage.get(t, []) as Array) + [a.id]
	row["features"] = types.keys()
	_record_params(a, a.id, params_by_type)
	# Connectivity in every gate state and bucket; features in canonical states.
	var states: Dictionary = _states(a)
	var canonical: Array = _canonical(states)
	row["gate_states"] = states.keys()
	var features: Array = _features(a)
	var blue_c: Vector2 = _centroid(a.spawns[0])
	var red_c: Vector2 = _centroid(a.spawns[1])
	for state_name in states:
		var sa: Arena = states[state_name]
		for bucket: float in BUCKETS:
			var g: Grid = _grid(sa, bucket)
			var field: PackedFloat32Array = _field(g, a.spawns[0][0])
			var unreachable: Array = []
			for team in [0, 1]:
				for p: Vector2 in a.spawns[team]:
					if not is_finite(_dist_at(g, field, p)):
						unreachable.append("spawn")
			if canonical.has(state_name):
				for fe: Array in features:
					if str(fe[0]).begins_with("gate:") and state_name == "static":
						continue
					if not is_finite(_dist_at(g, field, fe[1])):
						unreachable.append(str(fe[0]))
			check(unreachable.is_empty(), "%s connectivity state=%s bucket=%d %s" % [a.id, state_name, int(bucket), str(unreachable)])
	# Fairness and distances (bucket 18) in canonical states.
	var worst: float = 0.0
	var worst_label: String = ""
	var spawn_path: float = INF
	var link_path: float = INF
	var detour_min: float = INF
	var detour_max: float = 0.0
	for state_name in canonical + ["static"]:
		var sa2: Arena = states[state_name]
		var g2: Grid = _grid(sa2, 18.0)
		var fb: PackedFloat32Array = _field(g2, blue_c)
		var fr: PackedFloat32Array = _field(g2, red_c)
		var cc: float = _geodesic(sa2, g2, 18.0, blue_c, red_c)
		spawn_path = minf(spawn_path, cc)
		detour_min = minf(detour_min, cc / maxf(1.0, blue_c.distance_to(red_c)))
		detour_max = maxf(detour_max, cc / maxf(1.0, blue_c.distance_to(red_c)))
		var nav := Navigator.new()
		nav.arena = sa2
		nav.bucket = 18.0
		nav._build()
		# Walking length only: the V1.5.3 link layer (route_link) takes portals
		# and pads into account by default, the walking geodesic does not.
		var nav_len: float = nav.path_length(blue_c, red_c, 18.0)
		if nav.has_method("route_link"):
			nav_len = float(nav.callv("path_length", [blue_c, red_c, 18.0, 0.0, 0.0, 0.0, false]))
		check(nav_len >= cc * 0.97, "%s navigator path length agrees with the geodesic (%s: %.0f vs %.0f)" % [a.id, state_name, nav_len, cc])
		var lp: float = minf(_link_path(sa2, g2, 18.0, blue_c, red_c), _link_path(sa2, g2, 18.0, red_c, blue_c))
		link_path = minf(link_path, lp)
		if not canonical.has(state_name):
			continue
		for fe2: Array in features:
			if str(fe2[0]).begins_with("gate:") and state_name == "static":
				continue
			var p2: Vector2 = fe2[1]
			var q2: Vector2 = _img(sym, a.width, a.height, p2)
			var db: float = _dist_at(g2, fb, p2)
			var dr: float = _dist_at(g2, fr, q2)
			if not is_finite(db) or not is_finite(dr):
				continue
			var err: float = absf(db - dr) / maxf(1.0, maxf(db, dr))
			if err > worst:
				worst = err
				worst_label = "%s@%s blue=%.0f red=%.0f" % [str(fe2[0]), state_name, db, dr]
	check(worst <= FAIR_TOLERANCE, "%s fair path lengths within 3%% (worst %.4f %s)" % [a.id, worst, worst_label])
	check(spawn_path >= 900.0, "%s spawn-to-spawn path >= 900 (%.0f)" % [a.id, spawn_path])
	# Portals and jump pads must not bring a team closer than 900 px of walking
	# (flight priced at 150 px/s) to the enemy spawn either.
	check(link_path >= 900.0, "%s spawn-to-spawn path through portals/jump pads >= 900 (%.0f)" % [a.id, link_path])
	row["fairness_worst"] = snappedf(worst, 0.0001)
	row["spawn_path"] = snappedf(spawn_path, 1.0)
	row["spawn_link_path"] = snappedf(link_path, 1.0) if is_finite(link_path) else -1.0
	row["detour_min"] = snappedf(detour_min, 0.001)
	row["detour_max"] = snappedf(detour_max, 0.001)
	row["parking"] = _parking(a, states, blue_c, red_c)
	print("MAPS_153 map=%s %dx%d aspect=%.2f area=%.2fx orient=%s arch=%s sym=%s detour=%.3f/%.3f spawn_path=%.0f link_path=%.0f fair=%.4f features=%s parking=%s" % [
		a.id, int(a.width), int(a.height), a.width / a.height, a.width * a.height / (Arena.WIDTH * Arena.HEIGHT), row.orientation, row.archetype, sym,
		detour_min, detour_max, spawn_path, link_path if is_finite(link_path) else -1.0, worst, str(types.keys()), str(row.parking)])
	return row


# Stalemate guard: where the straight line between the spawn centroids is
# blocked for bodies, the two faces on either side must see each other (vision
# crosses the blocker, possibly offset sideways by up to 120 px) within 560 px,
# and the blocked stretch must stay within PARKING_GAP. Solid walls where both
# teams could park out of sight, or deep see-through islands that keep both
# fronts out of attack range, fail this.
func _parking(a: Arena, states: Dictionary, b: Vector2, r: Vector2) -> Array:
	var out: Array = []
	for state_name in states:
		var sa: Arena = states[state_name]
		var dir: Vector2 = (r - b).normalized()
		var side := Vector2(-dir.y, dir.x)
		var total: float = b.distance_to(r)
		var inside: bool = false
		var enter: float = 0.0
		var t: float = 0.0
		while t <= total:
			var p: Vector2 = b + dir * t
			var blocked: bool = sa.inside_obstacle(p, 20.0, Arena.MASK_UNITS)
			if blocked and not inside:
				inside = true
				enter = t
			elif not blocked and inside:
				inside = false
				var p1: Vector2 = b + dir * maxf(0.0, enter - 4.0)
				var p2: Vector2 = b + dir * t
				var seen: bool = false
				for o1 in [0.0, -60.0, 60.0, -120.0, 120.0]:
					for o2 in [0.0, -60.0, 60.0, -120.0, 120.0]:
						var q1: Vector2 = p1 + side * float(o1)
						var q2: Vector2 = p2 + side * float(o2)
						if q1.distance_to(q2) <= 560.0 and sa.line_of_sight(q1, q2) and sa.is_walkable(q1, 14.0) and sa.is_walkable(q2, 14.0):
							seen = true
				out.append({"state": state_name, "gap": snappedf(t - enter, 1.0), "visible": seen})
			t += 4.0
	return out


func _run() -> void:
	DB.ensure_loaded()
	var elim: Array = DB.arenas_for("elimination")
	var control: Array = DB.arenas_for("control")
	check(elim.size() == 12 and control.size() == 3, "12 elimination + 3 control maps")
	var coverage: Dictionary = {}
	var coverage_team: Dictionary = {}
	var params_by_type: Dictionary = {}
	var sizes: Dictionary = {}
	var orient: Dictionary = {}
	var archetypes: Dictionary = {}
	var detour_115: int = 0
	for a: Arena in elim:
		var row: Dictionary = _inspect(a, coverage, params_by_type)
		reports.append(row)
		sizes["%dx%d" % [int(a.width), int(a.height)]] = true
		orient[row.orientation] = int(orient.get(row.orientation, 0)) + 1
		archetypes[row.archetype] = true
		var aspect: float = a.width / a.height
		var area: float = a.width * a.height / (Arena.WIDTH * Arena.HEIGHT)
		check(aspect >= 1.25 - 1e-6 and aspect <= 2.4 + 1e-6, a.id + " aspect 1.25-2.4 (%.3f)" % aspect)
		check(area >= 0.75 - 1e-6 and area <= 1.45 + 1e-6, a.id + " area 0.75-1.45x (%.3f)" % area)
		if float(row.detour_min) >= 1.15:
			detour_115 += 1
		if a.id != "classic":
			check((row.features as Array).size() >= 2, a.id + " at least two distinct features " + str(row.features))
			for p: Dictionary in row.parking:
				check(bool(p.visible), "%s no hidden parking faces across the centre line %s" % [a.id, str(p)])
				check(float(p.gap) <= PARKING_GAP, "%s blocker across the centre line is thin enough to fight over (%s)" % [a.id, str(p)])
		for t in row.features:
			coverage_team[t] = int(coverage_team.get(t, 0)) + 1
		_check_orientation(a, str(row.orientation))
	var classic: Arena = DB.arena("classic")
	check(classic.width == 1408.0 and classic.height == 792.0 and classic.obs_count == 0 and classic.hazards.is_empty() and classic.forests.is_empty(), "classic stays the open 1408x792 baseline")
	check(sizes.size() >= 5, "at least five distinct elimination sizes (%d)" % sizes.size())
	check(int(orient.get("west_east", 0)) <= 5, "west/east spawns on at most five maps %s" % str(orient))
	check(int(orient.get("north_south", 0)) >= 2, "north/south spawns on at least two maps %s" % str(orient))
	check(int(orient.get("diagonal", 0)) >= 2, "diagonal spawns on at least two maps %s" % str(orient))
	check(int(orient.get("split", 0)) >= 1, "split spawns on at least one map %s" % str(orient))
	check(archetypes.size() == 12, "twelve distinct topology archetypes (%d)" % archetypes.size())
	check(detour_115 >= 4, "at least four maps with detour factor >= 1.15 (%d)" % detour_115)
	# Control maps.
	var cp_shapes: Dictionary = {}
	var control_orient: Dictionary = {}
	for a: Arena in control:
		var row: Dictionary = _inspect(a, coverage, params_by_type)
		reports.append(row)
		var area: float = a.width * a.height / (Arena.WIDTH * Arena.HEIGHT)
		check(area >= 2.0 and area <= 3.0, a.id + " control area 2.0-3.0x (%.3f)" % area)
		check(a.control_points.size() == 3 and a.heal_zones.size() == 4, a.id + " three points and four heal zones")
		var p0: Vector2 = a.control_points[0].center
		var p1: Vector2 = a.control_points[1].center
		var p2: Vector2 = a.control_points[2].center
		var cross: float = absf((p1 - p0).cross(p2 - p0))
		check(cross / maxf(1.0, p0.distance_to(p2) * p0.distance_to(p2)) > 0.08, a.id + " capture points form a real triangle, not a line")
		cp_shapes[JSON.stringify([snappedf(p0.distance_to(p1) / a.width, 0.01), snappedf(p1.distance_to(p2) / a.width, 0.01)])] = true
		control_orient[str(row.orientation)] = true
		for t in row.features:
			coverage_team[t] = int(coverage_team.get(t, 0)) + 1
		_check_orientation(a, str(row.orientation))
	check(control_orient.size() == 3, "three different control orientations %s" % str(control_orient.keys()))
	check(cp_shapes.size() == 3, "three different capture-point geometries")
	# Gimmick coverage across all modes (deathmatch previews included).
	for id in DeathmatchMapData.ORDER:
		for seed_value in [1, 2, 20261001]:
			var dm: Arena = Arena.from_data(DeathmatchMapData.build(str(id), seed_value))
			var types: Dictionary = _feature_types(dm)
			for t in types:
				if seed_value == 20261001:
					coverage[t] = (coverage.get(t, []) as Array) + [str(id)]
			if seed_value == 20261001:
				_record_params(dm, str(id), params_by_type)
			for h: Dictionary in dm.hazards:
				if str(h.type) == "jump_pad":
					check(dm.is_walkable(_vec(h.target), 30.0) and dm.is_walkable(h.center, 30.0), "%s/%d jump pad and landing walkable" % [id, seed_value])
				if str(h.type) == "artillery":
					check(str(h.shape) == "rect", "%s artillery area uses a rect (radius is the strike radius)" % id)
			for p: Vector2 in dm.ffa_spawns:
				for h: Dictionary in dm.hazards:
					check(not Arena.shape_contains(h, p, 24.0), "%s/%d free-for-all spawn outside hazards" % [id, seed_value])
			for spot: Dictionary in dm.item_spots:
				for h: Dictionary in dm.hazards:
					if str(h.type) == "jump_pad":
						check((spot.pos as Vector2).distance_to(h.center) > float(h.radius) + 30.0 and (spot.pos as Vector2).distance_to(_vec(h.target)) > 40.0,
							"%s/%d item anchors stay off jump pads and landings" % [id, seed_value])
	for t in NEW_TYPES:
		check((coverage.get(t, []) as Array).size() >= 2, "new gimmick %s on at least two maps %s" % [t, str(coverage.get(t, []))])
	check((coverage.get("gate", []) as Array).size() >= 2, "gates on at least two maps %s" % str(coverage.get("gate", [])))
	check(int(coverage_team.get("brush", 0)) >= 3, "brush on at least three team maps (%d)" % int(coverage_team.get("brush", 0)))
	for t in OLD_TYPES:
		check((coverage.get(t, []) as Array).size() >= 1, "existing gimmick %s kept on a map" % t)
	var ring_maps: Array = coverage.get("closing_ring", [])
	for id in ring_maps:
		check(DB.arena_by_id.has(str(id)) and (DB.arena_by_id[str(id)] as Arena).ruleset == "elimination", "closing ring only in elimination maps (%s)" % str(id))
	for a: Arena in DB.arenas:
		var rings: int = 0
		for h: Dictionary in a.hazards:
			if str(h.type) == "closing_ring":
				rings += 1
				check(a.is_walkable(Vector2(float(h.x), float(h.y)), 28.0) and float(h.endRadius) < float(h.startRadius) and float(h.endTime) > float(h.startTime), a.id + " closing ring shrinks to a walkable centre")
				_ring_dodge_band(a, h)
		check(rings <= 1, a.id + " at most one closing ring")
	for key in params_by_type:
		check((params_by_type[key] as Dictionary).size() == 1, "hazard parameter set used by one map only: %s %s" % [key.get_slice("|", 0), str((params_by_type[key] as Dictionary).keys())])
	var summary: Dictionary = {"suite": "maps_153", "status": "PASS" if failed.is_empty() else "FAIL", "passed": passed, "failed": failed,
		"sizes": sizes.keys(), "orientations": orient, "detour_ge_115": detour_115, "coverage": coverage, "maps": reports}
	DirAccess.make_dir_recursive_absolute("res://reports/maps_153")
	var f: FileAccess = FileAccess.open("res://reports/maps_153/maps_153.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(summary, "\t"))
	f.close()
	print("MAPS_153 ", summary.status, " passed=", passed, " failed=", failed.size())
	quit(0 if failed.is_empty() else 1)


# Settled closing ring vs a shockwave inside it (V1.5.3 review): the final safe
# circle must leave a band outside the wave's reach, so heroes can dodge the
# wave without stepping into the ring. bastion_ring had endRadius 200 against a
# 170 px wave (+26 ring width): 44.7 environment damage per hero-minute.
func _ring_dodge_band(a: Arena, ring: Dictionary) -> void:
	for w: Dictionary in a.hazards:
		if str(w.type) != "shockwave":
			continue
		var off: float = (w.center as Vector2).distance_to(ring.center)
		if off >= float(ring.endRadius):
			continue
		var ring_w: float = float(w.get("ringWidth", 22.0))
		var reach: float = off + float(w.radius) + ring_w
		check(float(ring.endRadius) >= reach + 70.0, "%s final safe radius leaves a 70 px band outside the shockwave %s (%.0f vs %.0f + 70)" % [a.id, str(w.id), float(ring.endRadius), reach])
		# Measured with the engine's own hit tests: radii on the line from the ring
		# centre away from the wave where a standing largest body (r 28, hit padding
		# 0.28 r) takes neither ring nor wave damage over a full wave cycle after
		# the ring has settled.
		var dir: Vector2 = ((ring.center as Vector2) - (w.center as Vector2)).normalized() if off > 1.0 else Vector2.RIGHT
		var t0: float = float(ring.endTime) + 0.5
		var period: float = maxf(0.5, float(w.get("period", 10.0)))
		var band: float = 0.0
		var d: float = 0.0
		while d <= float(ring.endRadius) + 20.0:
			var p: Vector2 = (ring.center as Vector2) + dir * d
			var safe: bool = not Arena.ring_outside(ring, p, t0, 0.0)
			var t: float = t0
			while safe and t <= t0 + period:
				if Arena.hazard_effect_contains(w, p, t, 28.0 * 0.28, t - BattleSim.DT, p):
					safe = false
				t += BattleSim.DT
			if safe:
				band += 2.0
			d += 2.0
		check(band >= 60.0, "%s settled ring keeps a dodge band outside the shockwave %s for the largest body (%.0f px)" % [a.id, str(w.id), band])


# Declared orientation must match the spawn geometry.
func _check_orientation(a: Arena, kind: String) -> void:
	var b: Vector2 = _centroid(a.spawns[0])
	var r: Vector2 = _centroid(a.spawns[1])
	var d: Vector2 = r - b
	var ok: bool = false
	match kind:
		"west_east":
			ok = absf(d.x) >= a.width * 0.6 and absf(d.y) <= a.height * 0.15
		"north_south":
			ok = absf(d.y) >= a.height * 0.6 and absf(d.x) <= a.width * 0.15
		"diagonal":
			ok = absf(d.x) >= a.width * 0.45 and absf(d.y) >= a.height * 0.45
		"split":
			var spread: float = 0.0
			for p: Vector2 in a.spawns[0]:
				for q: Vector2 in a.spawns[0]:
					spread = maxf(spread, p.distance_to(q))
			ok = spread >= a.height * 0.45
	check(ok, "%s declared spawn orientation %s matches geometry (%s)" % [a.id, kind, str(d)])
