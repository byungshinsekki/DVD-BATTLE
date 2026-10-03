class_name Arena
extends RefCounted

# Authored map geometry plus pure functions of time. Per-battle state lives in
# ArenaEnv; a gated map plays on a private copy (make_battle_copy) because gate
# masks change during the battle.
#
# V1.5.3 gimmick schema (hazards[] unless noted; all have id, shape keys):
#   brush         top-level forests [{x, y, radius, patch}] (sim.observes hides units inside).
#   artillery     area shape + period, warningDuration, phase, count, radius, damage,
#                 school, spread. Salvo of cycle c lands at artillery_impact_time(h, c).
#   gate          obstacles[i].gate = {group "A"|"B", period, openDuration,
#                 warningDuration, phase[, shift]}; B is shifted by period / 2.
#   jump_pad      circle + target {x, y}, flightTime, cooldown (per hero, default 2).
#   closing_ring  x, y (default centre), startTime, endTime, startRadius, endRadius,
#                 damagePercent (max-HP % per tick, true damage), tickInterval.
#   mud           shape + slow (0..0.6), always active.
# Pure helpers: hazard_clock(h, t) (also gate defs), hazard_effect_contains,
#   hazard_penalty(p, t, r, skip_mask), expected_hazard_damage(p, t, r, horizon,
#   skip_mask, max_hp), gate_open_at(obstacle_index, t), gate_clock(g, t),
#   gate_bits_at(t, closing_margin), ring_radius_at(h, t), ring_outside(h, p, t),
#   artillery_impact_time(h, cycle), spawn_centroid(team), default_margin(w, h),
#   type_bit(type), env_def(id).
# Default bounds derive from width/height (margin 37.4 * min(w, h) / 792).

const MASK_UNITS: = 1
const MASK_PROJECTILES: = 2
const MASK_VISION: = 4

const WIDTH: = 1408.0
const HEIGHT: = 792.0

var id: String = "classic"
var name: String = ""
var data: Dictionary = {}
var width: float = WIDTH
var height: float = HEIGHT
var ruleset: String = "elimination"
var control_points: Array = []
var heal_zones: Array = []
var accent: Color = Color("#70b9ff")
var min_x: float = 37.4
var max_x: float = 1370.6
var min_y: float = 37.4
var max_y: float = 754.6


var obs_count: int = 0
var obs_circle: PackedByteArray = PackedByteArray()
var obs_x: PackedFloat64Array = PackedFloat64Array()
var obs_y: PackedFloat64Array = PackedFloat64Array()
var obs_w: PackedFloat64Array = PackedFloat64Array()
var obs_h: PackedFloat64Array = PackedFloat64Array()
var obs_r: PackedFloat64Array = PackedFloat64Array()
var obs_mask: PackedInt32Array = PackedInt32Array()

var obs_minx: PackedFloat64Array = PackedFloat64Array()
var obs_maxx: PackedFloat64Array = PackedFloat64Array()
var obs_miny: PackedFloat64Array = PackedFloat64Array()
var obs_maxy: PackedFloat64Array = PackedFloat64Array()
var obs_ids: PackedStringArray = PackedStringArray()
var obstacles: Array = []
var hazards: Array = []
var spawns: Dictionary = {}
# Deathmatch: canopy circles that hide units inside them, grouped in patches.
var forests: Array = []
var forest_x: PackedFloat64Array = PackedFloat64Array()
var forest_y: PackedFloat64Array = PackedFloat64Array()
var forest_r: PackedFloat64Array = PackedFloat64Array()
var forest_patch: PackedInt32Array = PackedInt32Array()
var ffa_spawns: Array = []
var item_spots: Array = []
# Uniform-grid obstacle index, built only for large generated maps. Small
# authored arenas keep the original linear scans (and identical results).
const GRID: = 128.0
var indexed: bool = false
var _gw: int = 0
var _gh: int = 0
var _cells: Array = []
var _stamp: PackedInt32Array = PackedInt32Array()
var _stamp_id: int = 0

# --- V1.5.3 dynamic geometry -------------------------------------------------
# DB-owned instances are shared by every battle, preview and codex card; a
# battle on a gated map plays on a private copy (battle_copy) whose obstacle
# masks the ArenaEnv toggles. Nothing per battle is ever written to a shared one.
var shared: bool = false
var battle_copy: bool = false
# Gates: obstacle entries carrying a "gate" schedule. gates[slot] is a derived
# public definition {type:"gate", id, obs, group, period, openDuration,
# warningDuration, phase (group shift included), center, rect}. obs_gate maps an
# obstacle index to its gate slot (-1 = static wall), obs_mask_full keeps the
# authored mask so an open gate (mask 0) can be closed again.
var gates: Array = []
var obs_gate: PackedInt32Array = PackedInt32Array()
var obs_mask_full: PackedInt32Array = PackedInt32Array()
# Bit per gate slot, 1 = open. gate_bits is the geometry currently applied to
# obs_mask; nav_sig is the state Navigator.get_for() routes with (gates that
# close within NAV_CLOSING_MARGIN count as closed). Both 0 = authored walls.
var gate_bits: int = 0
var nav_sig: int = 0
const NAV_CLOSING_MARGIN: = 1.5
# Instance id of the shared arena a battle copy was made from (0 = none). Copies
# of one map share navigation grids (Navigator keys them apart from the shared
# instance itself); their static geometry is identical.
var source_uid: int = 0
# Any environment portal or jump pad (Navigator link layer, summon routing).
var has_links: bool = false

# Hazard type bits (Arena.type_bit) let callers skip disabled gimmick types
# without allocating: hazard_penalty(p, t, r, skip_mask).
const TYPE_BITS: = {"lava": 1, "spikes": 2, "eruption": 4, "wind": 8, "portal": 16, "haste": 32, "healing_fountain": 64,
	"gravity": 128, "shockwave": 256, "brush": 512, "artillery": 1024, "gate": 2048, "jump_pad": 4096, "closing_ring": 8192, "mud": 16384}
const ALWAYS_ON_TYPES: = ["wind", "portal", "haste", "healing_fountain", "jump_pad", "mud"]
const HAZARD_TYPES: = ["lava", "spikes", "eruption", "wind", "portal", "haste", "healing_fountain", "gravity", "shockwave",
	"artillery", "jump_pad", "closing_ring", "mud"]


static func type_bit(type: String) -> int:
	return int(TYPE_BITS.get(type, 0))


# Default playable margin for a map that gives only width/height: 37.4 px on the
# 1408x792 baseline, scaled with the shorter side (audit B5).
static func default_margin(w: float, h: float) -> float:
	return 37.4 * minf(w, h) / HEIGHT


static func from_data(d: Dictionary) -> Arena:
	var a: = Arena.new()
	a.id = str(d.get("id", "classic"))
	a.name = str(d.get("name", ""))
	a.data = d
	a.width = float(d.get("width", WIDTH))
	a.height = float(d.get("height", HEIGHT))
	a.ruleset = str(d.get("ruleset", "elimination"))
	a.accent = Color(str(d.get("accent", "#70b9ff")))
	var b: Dictionary = d.get("bounds", {})
	var margin: float = default_margin(a.width, a.height)
	a.min_x = float(b.get("minX", margin))
	a.max_x = float(b.get("maxX", a.width - margin))
	a.min_y = float(b.get("minY", margin))
	a.max_y = float(b.get("maxY", a.height - margin))
	for point in d.get("control_points", []):
		var cp: Dictionary = (point as Dictionary).duplicate(true)
		cp["center"] = Vector2(float(cp.x), float(cp.y))
		a.control_points.append(cp)
	for zone in d.get("heal_zones", []):
		var hz: Dictionary = (zone as Dictionary).duplicate(true)
		hz["center"] = Vector2(float(hz.x), float(hz.y))
		a.heal_zones.append(hz)
	for o in d.get("obstacles", []):
		var od: Dictionary = o
		a.obstacles.append(od)
		var circle: = str(od.get("shape", "rect")) == "circle"
		a.obs_circle.append(1 if circle else 0)
		a.obs_x.append(float(od.get("x", 0.0)))
		a.obs_y.append(float(od.get("y", 0.0)))
		a.obs_w.append(float(od.get("w", 0.0)))
		a.obs_h.append(float(od.get("h", 0.0)))
		a.obs_r.append(float(od.get("radius", 0.0)))
		var m: = 0
		if od.get("blocksUnits", true) != false: m |= MASK_UNITS
		if od.get("blocksProjectiles", true) != false: m |= MASK_PROJECTILES
		if od.get("blocksVision", true) != false: m |= MASK_VISION
		a.obs_mask.append(m)
		a.obs_mask_full.append(m)
		a.obs_ids.append(str(od.get("id", "")))
		a.obs_gate.append(-1)
		var gd = od.get("gate", null)
		if gd is Dictionary and m != 0:
			a.obs_gate[a.obs_gate.size() - 1] = a.gates.size()
			a.gates.append(_gate_def(od, gd as Dictionary, a.obs_ids.size() - 1))
	a.obs_count = a.obs_circle.size()
	for i in a.obs_count:
		if a.obs_circle[i] == 1:
			a.obs_minx.append(a.obs_x[i] - a.obs_r[i])
			a.obs_maxx.append(a.obs_x[i] + a.obs_r[i])
			a.obs_miny.append(a.obs_y[i] - a.obs_r[i])
			a.obs_maxy.append(a.obs_y[i] + a.obs_r[i])
		else:
			a.obs_minx.append(a.obs_x[i])
			a.obs_maxx.append(a.obs_x[i] + a.obs_w[i])
			a.obs_miny.append(a.obs_y[i])
			a.obs_maxy.append(a.obs_y[i] + a.obs_h[i])
	for h in d.get("hazards", []):
		var hd: Dictionary = (h as Dictionary).duplicate(true)
		hd["center"] = _shape_center(hd)
		var htype: String = str(hd.get("type", ""))
		hd["tbit"] = type_bit(htype)
		if htype == "closing_ring":
			# Ring centre defaults to the middle of the playable bounds.
			hd["center"] = Vector2(float(hd.x), float(hd.y)) if hd.has("x") and hd.has("y") else a.center()
		elif htype == "jump_pad":
			var tgt: Dictionary = hd.get("target", {})
			hd["landing"] = Vector2(float(tgt.get("x", hd.center.x)), float(tgt.get("y", hd.center.y)))
		if htype == "portal" or htype == "jump_pad":
			a.has_links = true
		if hd.has("directionA"):
			hd["dirA"] = Vector2(float(hd.directionA.x), float(hd.directionA.y)).normalized()
			hd["dirB"] = Vector2(float(hd.directionB.x), float(hd.directionB.y)).normalized()
		if hd.has("exitFacing"):
			hd["exit"] = Vector2(float(hd.exitFacing.x), float(hd.exitFacing.y)).normalized()
		a.hazards.append(hd)
	var sp: Dictionary = d.get("spawns", {})
	for t in [0, 1]:
		var key: = "blue" if t == 0 else "red"
		var arr: Array = []
		for p in sp.get(key, []):
			arr.append(Vector2(float(p.x), float(p.y)))
		a.spawns[t] = arr
	for f in d.get("forests", []):
		var fd: Dictionary = f
		a.forests.append(fd)
		a.forest_x.append(float(fd.x))
		a.forest_y.append(float(fd.y))
		a.forest_r.append(float(fd.radius))
		a.forest_patch.append(int(fd.get("patch", a.forest_patch.size())))
	for p in d.get("ffa_spawns", []):
		a.ffa_spawns.append(Vector2(float(p.x), float(p.y)))
	for spot in d.get("item_spots", []):
		if not bool((spot as Dictionary).get("unreachable", false)):
			a.item_spots.append({"pos": Vector2(float(spot.x), float(spot.y)), "kind": str(spot.get("kind", "field"))})
	if a.obs_count > 32:
		a._build_index()
	if a.forest_x.size() > FOREST_SCAN_MAX:
		a._build_forest_index()
	return a


func _build_index() -> void:
	indexed = true
	_gw = int(ceil(width / GRID)) + 1
	_gh = int(ceil(height / GRID)) + 1
	_cells.resize(_gw * _gh)
	for k in _cells.size():
		_cells[k] = PackedInt32Array()
	for i in obs_count:
		var x0: int = clampi(int(floor(obs_minx[i] / GRID)), 0, _gw - 1)
		var x1: int = clampi(int(floor(obs_maxx[i] / GRID)), 0, _gw - 1)
		var y0: int = clampi(int(floor(obs_miny[i] / GRID)), 0, _gh - 1)
		var y1: int = clampi(int(floor(obs_maxy[i] / GRID)), 0, _gh - 1)
		for gy in range(y0, y1 + 1):
			for gx in range(x0, x1 + 1):
				var cell: PackedInt32Array = _cells[gy * _gw + gx]
				cell.append(i)
				_cells[gy * _gw + gx] = cell
	_stamp.resize(obs_count)
	_stamp.fill(0)


# Obstacle indices whose bounds may touch the box, ascending and unique.
func _candidates(minx: float, miny: float, maxx: float, maxy: float) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	_stamp_id += 1
	if _stamp_id > 2000000000:
		_stamp.fill(0)
		_stamp_id = 1
	var x0: int = clampi(int(floor(minx / GRID)), 0, _gw - 1)
	var x1: int = clampi(int(floor(maxx / GRID)), 0, _gw - 1)
	var y0: int = clampi(int(floor(miny / GRID)), 0, _gh - 1)
	var y1: int = clampi(int(floor(maxy / GRID)), 0, _gh - 1)
	for gy in range(y0, y1 + 1):
		for gx in range(x0, x1 + 1):
			for i in _cells[gy * _gw + gx]:
				if _stamp[i] != _stamp_id:
					_stamp[i] = _stamp_id
					out.append(i)
	out.sort()
	return out


func forest_at(p: Vector2) -> int:
	var n: int = forest_x.size()
	if n > FOREST_SCAN_MAX and not index_off:
		if _f_built != n:
			_build_forest_index()
		var gx: int = int(floor(p.x / FOREST_CELL))
		var gy: int = int(floor(p.y / FOREST_CELL))
		if gx >= 0 and gy >= 0 and gx < _f_gw and gy < _f_gh:
			for k in (_f_cells[gy * _f_gw + gx] as PackedInt32Array):
				var cdx: float = p.x - forest_x[k]
				var cdy: float = p.y - forest_y[k]
				if cdx * cdx + cdy * cdy <= forest_r[k] * forest_r[k]:
					return forest_patch[k]
			return -1
	for k in n:
		var dx: float = p.x - forest_x[k]
		var dy: float = p.y - forest_y[k]
		if dx * dx + dy * dy <= forest_r[k] * forest_r[k]:
			return forest_patch[k]
	return -1


# Dense canopy blocks sight when a line crosses deep into a patch that holds
# neither end. Standing inside a forest lets a unit see out of it.
func forest_occludes(a: Vector2, b: Vector2) -> bool:
	if forest_x.is_empty():
		return false
	var pa: int = forest_at(a)
	var pb: int = forest_at(b)
	var d: Vector2 = b - a
	var len2: float = d.length_squared()
	if len2 < 1.0:
		return false
	if forest_x.size() > FOREST_SCAN_MAX and not index_off:
		if _f_built != forest_x.size():
			_build_forest_index()
		# Only patches whose box meets the segment's box can hold a crossed circle.
		var sminx: float = minf(a.x, b.x)
		var smaxx: float = maxf(a.x, b.x)
		var sminy: float = minf(a.y, b.y)
		var smaxy: float = maxf(a.y, b.y)
		for pi in _f_pid.size():
			var pid: int = _f_pid[pi]
			if pid == pa or pid == pb or _f_pmaxx[pi] < sminx or _f_pminx[pi] > smaxx or _f_pmaxy[pi] < sminy or _f_pminy[pi] > smaxy:
				continue
			for k in (_f_pcircles[pi] as PackedInt32Array):
				if _forest_cuts(k, a, d, len2):
					return true
		return false
	for k in forest_x.size():
		var patch: int = forest_patch[k]
		if patch == pa or patch == pb:
			continue
		if _forest_cuts(k, a, d, len2):
			return true
	return false


func _forest_cuts(k: int, a: Vector2, d: Vector2, len2: float) -> bool:
	var c := Vector2(forest_x[k], forest_y[k])
	var t: float = clampf((c - a).dot(d) / len2, 0.0, 1.0)
	var closest: Vector2 = a + d * t
	var dist2: float = closest.distance_squared_to(c)
	var r: float = forest_r[k]
	if dist2 >= r * r:
		return false
	var half_chord: float = sqrt(r * r - dist2)
	return half_chord * 2.0 > 120.0


# V2 (B-PERF): forest lookups on brush-heavy maps go through a 128 px bucket
# grid (forest_at) and per-patch bounding boxes (forest_occludes) instead of
# scanning every circle. Same results: a bucket lists, in ascending order,
# every circle whose box touches it, so forest_at still returns the patch of
# the lowest-index circle holding p, and a patch whose box misses the
# segment's box cannot occlude it. Points outside the grid scan linearly.
const FOREST_CELL: = 128.0
const FOREST_SCAN_MAX: = 16
# Reference switch (tests): forest and hazard queries scan every entry.
static var index_off: bool = false
var _f_built: int = -1
var _f_gw: int = 0
var _f_gh: int = 0
var _f_cells: Array = []
var _f_pid: PackedInt32Array = PackedInt32Array()
var _f_pminx: PackedFloat64Array = PackedFloat64Array()
var _f_pmaxx: PackedFloat64Array = PackedFloat64Array()
var _f_pminy: PackedFloat64Array = PackedFloat64Array()
var _f_pmaxy: PackedFloat64Array = PackedFloat64Array()
var _f_pcircles: Array = []


func _build_forest_index() -> void:
	var n: int = forest_x.size()
	_f_built = n
	_f_gw = int(ceil(width / FOREST_CELL)) + 1
	_f_gh = int(ceil(height / FOREST_CELL)) + 1
	_f_cells = []
	_f_cells.resize(_f_gw * _f_gh)
	for c in _f_cells.size():
		_f_cells[c] = PackedInt32Array()
	_f_pid = PackedInt32Array()
	_f_pminx = PackedFloat64Array()
	_f_pmaxx = PackedFloat64Array()
	_f_pminy = PackedFloat64Array()
	_f_pmaxy = PackedFloat64Array()
	_f_pcircles = []
	var slot: Dictionary = {}
	for k in n:
		var r: float = forest_r[k]
		var x0: int = clampi(int(floor((forest_x[k] - r) / FOREST_CELL)), 0, _f_gw - 1)
		var x1: int = clampi(int(floor((forest_x[k] + r) / FOREST_CELL)), 0, _f_gw - 1)
		var y0: int = clampi(int(floor((forest_y[k] - r) / FOREST_CELL)), 0, _f_gh - 1)
		var y1: int = clampi(int(floor((forest_y[k] + r) / FOREST_CELL)), 0, _f_gh - 1)
		for gy in range(y0, y1 + 1):
			for gx in range(x0, x1 + 1):
				var cell: PackedInt32Array = _f_cells[gy * _f_gw + gx]
				cell.append(k)
				_f_cells[gy * _f_gw + gx] = cell
		var pid: int = forest_patch[k]
		if not slot.has(pid):
			slot[pid] = _f_pid.size()
			_f_pid.append(pid)
			_f_pminx.append(INF)
			_f_pmaxx.append(-INF)
			_f_pminy.append(INF)
			_f_pmaxy.append(-INF)
			_f_pcircles.append(PackedInt32Array())
		var s: int = slot[pid]
		# One pixel of slack keeps the box test conservative against rounding.
		_f_pminx[s] = minf(_f_pminx[s], forest_x[k] - r - 1.0)
		_f_pmaxx[s] = maxf(_f_pmaxx[s], forest_x[k] + r + 1.0)
		_f_pminy[s] = minf(_f_pminy[s], forest_y[k] - r - 1.0)
		_f_pmaxy[s] = maxf(_f_pmaxy[s], forest_y[k] + r + 1.0)
		var members: PackedInt32Array = _f_pcircles[s]
		members.append(k)
		_f_pcircles[s] = members


static func _shape_center(s: Dictionary) -> Vector2:
	if str(s.get("shape", "rect")) == "circle":
		return Vector2(float(s.get("x", 0.0)), float(s.get("y", 0.0)))
	return Vector2(float(s.get("x", 0.0)) + float(s.get("w", 0.0)) * 0.5, float(s.get("y", 0.0)) + float(s.get("h", 0.0)) * 0.5)


func center() -> Vector2:
	return Vector2((min_x + max_x) * 0.5, (min_y + max_y) * 0.5)


# Centroid of a team's authored spawn points (team 0 = blue, 1 = red). Maps
# without spawns fall back to the legacy edge column of that side. Painters,
# the opening facing and fallback spawn slots all derive from it.
func spawn_centroid(team: int) -> Vector2:
	var pts: Array = spawns.get(team, [])
	if pts.is_empty():
		return Vector2(170.0 if team % 2 == 0 else width - 170.0, height * 0.5)
	var c: = Vector2.ZERO
	for q in pts:
		c += q
	return c / float(pts.size())


# Private per-battle instance built from the same authored data. The copy starts
# with the authored (closed) gate masks; ArenaEnv applies the schedule.
func make_battle_copy() -> Arena:
	var c: Arena = Arena.from_data(data)
	c.battle_copy = true
	c.source_uid = get_instance_id()
	return c


# Environment definition (hazard or gate) by id, for logs and renderers that
# receive an ENV_* event. Empty when unknown.
func env_def(hazard_id: String) -> Dictionary:
	for h in hazards:
		if str(h.get("id", "")) == hazard_id:
			return h
	for g in gates:
		if str(g.id) == hazard_id:
			return g
	return {}


func has_gates() -> bool:
	return not gates.is_empty()


# --- Gates -------------------------------------------------------------------
# Schedule: every gate of a group shares one cycle. A gate is OPEN for
# openDuration at the start of each cycle, then CLOSED for the rest of the
# period; the WARNING window is the last warningDuration seconds before it
# closes. Group "B" is shifted by half a period (so A and B alternate) unless
# the gate data gives an explicit "shift" (seconds added to its phase).
static func _gate_def(od: Dictionary, gd: Dictionary, obs_index: int) -> Dictionary:
	var period: float = maxf(0.2, float(gd.get("period", 12.0)))
	var group: String = str(gd.get("group", "A"))
	var shift: float = float(gd.get("shift", period * 0.5 if group == "B" else 0.0))
	var rect: Rect2
	var ctr: Vector2
	if str(od.get("shape", "rect")) == "circle":
		var rr: float = float(od.get("radius", 0.0))
		ctr = Vector2(float(od.get("x", 0.0)), float(od.get("y", 0.0)))
		rect = Rect2(ctr - Vector2(rr, rr), Vector2(rr, rr) * 2.0)
	else:
		rect = Rect2(float(od.get("x", 0.0)), float(od.get("y", 0.0)), float(od.get("w", 0.0)), float(od.get("h", 0.0)))
		ctr = rect.get_center()
	var open_d: float = clampf(float(gd.get("openDuration", period * 0.5)), 0.0, period)
	return {"type": "gate", "id": str(od.get("id", "gate_%d" % obs_index)), "label": str(od.get("label", gd.get("label", ""))),
		"obs": obs_index, "group": group, "period": period, "openDuration": open_d,
		"warningDuration": clampf(float(gd.get("warningDuration", 1.5)), 0.0, open_d),
		"phase": float(gd.get("phase", 0.0)) + shift, "center": ctr, "rect": rect, "tbit": TYPE_BITS["gate"]}


static func gate_clock(g: Dictionary, t: float) -> Dictionary:
	var period: float = float(g.period)
	var open_d: float = float(g.openDuration)
	var warn: float = float(g.warningDuration)
	var shifted: float = fposmod(t + float(g.phase), period)
	var open: bool = shifted < open_d
	var remaining: float = (open_d - shifted) if open else (period - shifted)
	if open_d >= period:
		open = true
		remaining = INF
	elif open_d <= 0.0:
		open = false
		remaining = INF
	return {"active": open, "open": open, "warning": open and remaining <= warn and open_d < period,
		"progress": (shifted / maxf(0.001, open_d)) if open else (shifted / period),
		"cycle": int(floor((t + float(g.phase)) / period)), "remaining": remaining, "to_active": 0.0 if open else remaining}


static func gate_def_open(g: Dictionary, t: float, closing_margin: float = 0.0) -> bool:
	var period: float = float(g.period)
	var open_d: float = float(g.openDuration)
	if open_d >= period:
		return true
	if open_d <= 0.0:
		return false
	var shifted: float = fposmod(t + float(g.phase), period)
	return shifted < open_d and open_d - shifted > closing_margin


# Pure prediction: is authored obstacle i a gate that is open at time t?
# Static walls are never open. Ignores the developer toggles (see ArenaEnv).
func gate_open_at(obstacle_index: int, t: float) -> bool:
	if obstacle_index < 0 or obstacle_index >= obs_gate.size() or obs_gate[obstacle_index] < 0:
		return false
	return gate_def_open(gates[obs_gate[obstacle_index]], t)


func all_gates_open_bits() -> int:
	return (1 << gates.size()) - 1


# Bit per gate slot, 1 = open at t and not closing within closing_margin seconds.
func gate_bits_at(t: float, closing_margin: float = 0.0) -> int:
	var bits: int = 0
	for k in gates.size():
		if gate_def_open(gates[k], t, closing_margin):
			bits |= 1 << k
	return bits


# Applies an open/closed pattern to the obstacle masks of THIS instance.
# Only per-battle copies (or private test arenas) may be changed.
func apply_gate_bits(bits: int) -> void:
	if gates.is_empty() or bits == gate_bits:
		return
	for k in gates.size():
		var i: int = int(gates[k].obs)
		obs_mask[i] = 0 if ((bits >> k) & 1) == 1 else obs_mask_full[i]
	gate_bits = bits


func gate_slot_open(slot: int) -> bool:
	return ((gate_bits >> slot) & 1) == 1


# Obstacle mask under a navigation gate signature (static walls keep their
# current mask; gates follow the signature, 1 = open).
func mask_for_sig(i: int, open_bits: int) -> int:
	var slot: int = obs_gate[i]
	if slot < 0:
		return obs_mask[i]
	return 0 if ((open_bits >> slot) & 1) == 1 else obs_mask_full[i]


func inside_obstacle_sig(p: Vector2, pad: float, mask: int, open_bits: int) -> bool:
	if gates.is_empty():
		return inside_obstacle(p, pad, mask)
	for i in obs_count:
		if (mask_for_sig(i, open_bits) & mask) == 0:
			continue
		if obs_circle[i] == 1:
			if p.distance_to(Vector2(obs_x[i], obs_y[i])) <= obs_r[i] + pad:
				return true
		elif p.x >= obs_x[i] - pad and p.x <= obs_x[i] + obs_w[i] + pad and p.y >= obs_y[i] - pad and p.y <= obs_y[i] + obs_h[i] + pad:
			return true
	return false


func segment_blocked_sig(a: Vector2, b: Vector2, pad: float, mask: int, open_bits: int) -> bool:
	if gates.is_empty():
		return segment_blocked(a, b, pad, mask)
	var sminx: = minf(a.x, b.x) - pad
	var smaxx: = maxf(a.x, b.x) + pad
	var sminy: = minf(a.y, b.y) - pad
	var smaxy: = maxf(a.y, b.y) + pad
	for i in obs_count:
		if (mask_for_sig(i, open_bits) & mask) == 0:
			continue
		if obs_maxx[i] < sminx or obs_minx[i] > smaxx or obs_maxy[i] < sminy or obs_miny[i] > smaxy:
			continue
		if obs_circle[i] == 1:
			if seg_circle_t(a, b, Vector2(obs_x[i], obs_y[i]), obs_r[i] + pad) >= 0.0:
				return true
		elif seg_rect(a, b, obs_x[i], obs_y[i], obs_w[i], obs_h[i], pad).x >= 0.0:
			return true
	return false


# --- Closing ring ---------------------------------------------------------------
# Safe radius: startRadius until startTime, linear shrink to endRadius at endTime,
# then constant. Pure function of time (render, AI and simulation share it).
static func ring_radius_at(h: Dictionary, t: float) -> float:
	var r0: float = maxf(0.0, float(h.get("startRadius", 900.0)))
	var r1: float = maxf(0.0, float(h.get("endRadius", 200.0)))
	var t0: float = float(h.get("startTime", 60.0))
	var t1: float = maxf(t0, float(h.get("endTime", t0 + 30.0)))
	if t <= t0:
		return r0
	if t >= t1 or t1 - t0 < 1e-6:
		return r1
	return lerpf(r0, r1, (t - t0) / (t1 - t0))


static func ring_active(h: Dictionary, t: float) -> bool:
	return t >= float(h.get("startTime", 60.0))


# Fraction of max health per damage tick: damagePercent is a percentage
# (4 = 4 % of max HP per tick, 0.5 = 0.5 %), clamped to 0..100.
static func ring_damage_fraction(h: Dictionary) -> float:
	return clampf(float(h.get("damagePercent", 4.0)), 0.0, 100.0) * 0.01


static func ring_outside(h: Dictionary, p: Vector2, t: float, padding: float = 0.0) -> bool:
	if not ring_active(h, t):
		return false
	var c: Vector2 = h.get("center", Vector2.ZERO)
	return p.distance_to(c) > ring_radius_at(h, t) - padding


static func _ring_clock(h: Dictionary, t: float) -> Dictionary:
	var t0: float = float(h.get("startTime", 60.0))
	var t1: float = maxf(t0, float(h.get("endTime", t0 + 30.0)))
	var warn: float = maxf(0.0, float(h.get("warningDuration", 5.0)))
	var active: bool = t >= t0
	return {"active": active, "warning": not active and t0 - t <= warn, "progress": clampf((t - t0) / maxf(0.001, t1 - t0), 0.0, 1.0),
		"cycle": 0, "to_active": maxf(0.0, t0 - t), "remaining": (t0 - t) if not active else maxf(0.0, t1 - t)}


# --- Artillery -----------------------------------------------------------------
# Cycle c announces its salvo at impact - warningDuration and lands at
# impact = (c + 1) * period - phase, i.e. the start of cycle c + 1.
static func artillery_impact_time(h: Dictionary, cycle: int) -> float:
	var period: float = maxf(0.2, float(h.get("period", 8.0)))
	return float(cycle + 1) * period - float(h.get("phase", 0.0))


static func artillery_warning(h: Dictionary) -> float:
	var period: float = maxf(0.2, float(h.get("period", 8.0)))
	return clampf(float(h.get("warningDuration", 1.5)), 0.1, period)


# Expected damage from salvos that are NOT announced yet (their points are
# unknown); announced strikes are public telegraphs (ArenaEnv adds them).
# Strike centres always lie inside the area (ArenaEnv clamps them), so a body
# can be hit up to strike radius + 0.3 x its radius outside the area.
static func artillery_expected(h: Dictionary, p: Vector2, t: float, r: float, horizon: float) -> float:
	var strike_r: float = maxf(1.0, float(h.get("radius", 60.0)))
	var reach: float = strike_r + r * 0.3
	if not shape_contains(h, p, reach):
		return 0.0
	var period: float = maxf(0.2, float(h.get("period", 8.0)))
	var phase: float = float(h.get("phase", 0.0))
	var warn: float = artillery_warning(h)
	var first: int = int(floor((t + phase) / period)) - 1
	var last: int = int(floor((t + maxf(0.0, horizon) + phase) / period))
	var salvos: int = 0
	for cycle in range(first, last + 1):
		var impact: float = float(cycle + 1) * period - phase
		if impact - warn > t and impact <= t + maxf(0.0, horizon):
			salvos += 1
	if salvos == 0:
		return 0.0
	var spread: float = maxf(1.0, float(h.get("spread", 60.0)))
	var per_strike: float = 0.5 * minf(1.0, (reach * reach) / (spread * spread))
	var hits: float = minf(1.0, float(maxi(1, int(h.get("count", 3)))) * per_strike)
	return maxf(0.0, float(h.get("damage", 0.0))) * hits * float(salvos)




static func shape_contains(s: Dictionary, p: Vector2, padding: float = 0.0) -> bool:
	if str(s.get("shape", "rect")) == "circle":
		return p.distance_to(Vector2(float(s.x), float(s.y))) <= float(s.get("radius", 0.0)) + padding
	var hw: = float(s.get("w", 0.0)) * 0.5 + padding
	var hh: = float(s.get("h", 0.0)) * 0.5 + padding
	var cx: = float(s.x) + float(s.get("w", 0.0)) * 0.5
	var cy: = float(s.y) + float(s.get("h", 0.0)) * 0.5
	return absf(p.x - cx) <= hw and absf(p.y - cy) <= hh


func inside_obstacle(p: Vector2, pad: float = 0.0, mask: int = MASK_UNITS) -> bool:
	if indexed:
		for i in _candidates(p.x - pad, p.y - pad, p.x + pad, p.y + pad):
			if (obs_mask[i] & mask) == 0:
				continue
			if obs_circle[i] == 1:
				if p.distance_to(Vector2(obs_x[i], obs_y[i])) <= obs_r[i] + pad:
					return true
			elif p.x >= obs_x[i] - pad and p.x <= obs_x[i] + obs_w[i] + pad and p.y >= obs_y[i] - pad and p.y <= obs_y[i] + obs_h[i] + pad:
				return true
		return false
	for i in obs_count:
		if (obs_mask[i] & mask) == 0:
			continue
		if obs_circle[i] == 1:
			if p.distance_to(Vector2(obs_x[i], obs_y[i])) <= obs_r[i] + pad:
				return true
		else:
			if p.x >= obs_x[i] - pad and p.x <= obs_x[i] + obs_w[i] + pad and p.y >= obs_y[i] - pad and p.y <= obs_y[i] + obs_h[i] + pad:
				return true
	return false



func resolve_circle(p: Vector2, r: float = 0.0) -> Vector2:
	var o: = Vector2(clampf(p.x, min_x + r, max_x - r), clampf(p.y, min_y + r, max_y - r))
	for _it in 4:
		var changed: = false
		var scan: PackedInt32Array = _candidates(o.x - r - 2.0, o.y - r - 2.0, o.x + r + 2.0, o.y + r + 2.0) if indexed else PackedInt32Array()
		for n in (scan.size() if indexed else obs_count):
			var i: int = scan[n] if indexed else n
			if (obs_mask[i] & MASK_UNITS) == 0:
				continue
			if obs_circle[i] == 1:
				var c: = Vector2(obs_x[i], obs_y[i])
				var d: = o - c
				var m: = d.length()
				var md: = r + obs_r[i]
				if m >= md:
					continue
				if m < 1e-07:
					d = Vector2(cos(float(i) * 1.7), sin(float(i) * 1.7))
					m = 0.0
				else:
					d = d / m
				o = c + d * (md + 0.02)
				changed = true
			else:
				var ex: = obs_x[i] - r
				var ey: = obs_y[i] - r
				var ew: = obs_w[i] + r * 2.0
				var eh: = obs_h[i] + r * 2.0
				if o.x < ex or o.x > ex + ew or o.y < ey or o.y > ey + eh:
					continue
				var left: = o.x - ex
				var right: = ex + ew - o.x
				var top: = o.y - ey
				var bottom: = ey + eh - o.y
				var mn: = minf(minf(left, right), minf(top, bottom))
				if mn == left:
					o.x = ex - 0.02
				elif mn == right:
					o.x = ex + ew + 0.02
				elif mn == top:
					o.y = ey - 0.02
				else:
					o.y = ey + eh + 0.02
				changed = true
		o.x = clampf(o.x, min_x + r, max_x - r)
		o.y = clampf(o.y, min_y + r, max_y - r)
		if not changed:
			break
	return o


# resolve_circle under a navigation gate signature (gates follow open_bits,
# static walls their own mask) instead of the gates this instance shows right
# now. Navigator places link exits with it, so a grid shared by battle copies
# does not depend on which copy built it or at what time. Build-time only (no
# spatial index); the same push rules as resolve_circle.
func resolve_circle_sig(p: Vector2, r: float, open_bits: int) -> Vector2:
	if gates.is_empty():
		return resolve_circle(p, r)
	var o: = Vector2(clampf(p.x, min_x + r, max_x - r), clampf(p.y, min_y + r, max_y - r))
	for _it in 4:
		var changed: = false
		for i in obs_count:
			if (mask_for_sig(i, open_bits) & MASK_UNITS) == 0:
				continue
			if obs_circle[i] == 1:
				var c: = Vector2(obs_x[i], obs_y[i])
				var d: = o - c
				var m: = d.length()
				var md: = r + obs_r[i]
				if m >= md:
					continue
				if m < 1e-07:
					d = Vector2(cos(float(i) * 1.7), sin(float(i) * 1.7))
				else:
					d = d / m
				o = c + d * (md + 0.02)
				changed = true
			else:
				var ex: = obs_x[i] - r
				var ey: = obs_y[i] - r
				var ew: = obs_w[i] + r * 2.0
				var eh: = obs_h[i] + r * 2.0
				if o.x < ex or o.x > ex + ew or o.y < ey or o.y > ey + eh:
					continue
				var left: = o.x - ex
				var right: = ex + ew - o.x
				var top: = o.y - ey
				var bottom: = ey + eh - o.y
				var mn: = minf(minf(left, right), minf(top, bottom))
				if mn == left:
					o.x = ex - 0.02
				elif mn == right:
					o.x = ex + ew + 0.02
				elif mn == top:
					o.y = ey - 0.02
				else:
					o.y = ey + eh + 0.02
				changed = true
		o.x = clampf(o.x, min_x + r, max_x - r)
		o.y = clampf(o.y, min_y + r, max_y - r)
		if not changed:
			break
	return o


func is_walkable(p: Vector2, r: float) -> bool:
	return resolve_circle(p, r).distance_squared_to(p) <= 0.0064





static func seg_circle_t(a: Vector2, b: Vector2, c: Vector2, r: float) -> float:
	var d: = b - a
	var f: = a - c
	var cc: = f.dot(f) - r * r
	var radial: = f.dot(d)
	if absf(cc) <= 1e-08 and radial >= 0.0:
		return -1.0
	if cc <= 0.0:
		return 0.0
	var aa: = d.dot(d)
	if aa <= 1e-10:
		return -1.0
	var bb: = 2.0 * radial
	var disc: = bb * bb - 4.0 * aa * cc
	if disc < 0.0:
		return -1.0
	var root: = sqrt(disc)
	var t1: = ( - bb - root) / (2.0 * aa)
	if t1 >= 0.0 and t1 <= 1.0:
		return t1
	var t2: = ( - bb + root) / (2.0 * aa)
	if t2 >= 0.0 and t2 <= 1.0:
		return t2
	return -1.0



static func seg_rect(a: Vector2, b: Vector2, x: float, y: float, w: float, h: float, pad: float) -> Vector3:
	var mnx: = x - pad
	var mxx: = x + w + pad
	var mny: = y - pad
	var mxy: = y + h + pad
	var dx: = b.x - a.x
	var dy: = b.y - a.y
	var tmin: = 0.0
	var tmax: = 1.0
	var nx: = 0.0
	var ny: = 0.0
	var p: = - dx
	var q: = a.x - mnx
	if absf(p) < 1e-09:
		if q < 0.0: return Vector3(-1, 0, 0)
	else:
		var t: = q / p
		if p < 0.0:
			if t > tmax: return Vector3(-1, 0, 0)
			if t > tmin:
				tmin = t;nx = -1.0;ny = 0.0
		else:
			if t < tmin: return Vector3(-1, 0, 0)
			tmax = minf(tmax, t)
	p = dx
	q = mxx - a.x
	if absf(p) < 1e-09:
		if q < 0.0: return Vector3(-1, 0, 0)
	else:
		var t: = q / p
		if p < 0.0:
			if t > tmax: return Vector3(-1, 0, 0)
			if t > tmin:
				tmin = t;nx = 1.0;ny = 0.0
		else:
			if t < tmin: return Vector3(-1, 0, 0)
			tmax = minf(tmax, t)
	p = - dy
	q = a.y - mny
	if absf(p) < 1e-09:
		if q < 0.0: return Vector3(-1, 0, 0)
	else:
		var t: = q / p
		if p < 0.0:
			if t > tmax: return Vector3(-1, 0, 0)
			if t > tmin:
				tmin = t;nx = 0.0;ny = -1.0
		else:
			if t < tmin: return Vector3(-1, 0, 0)
			tmax = minf(tmax, t)
	p = dy
	q = mxy - a.y
	if absf(p) < 1e-09:
		if q < 0.0: return Vector3(-1, 0, 0)
	else:
		var t: = q / p
		if p < 0.0:
			if t > tmax: return Vector3(-1, 0, 0)
			if t > tmin:
				tmin = t;nx = 0.0;ny = 1.0
		else:
			if t < tmin: return Vector3(-1, 0, 0)
			tmax = minf(tmax, t)
	if tmin < 0.0 or tmin > 1.0:
		return Vector3(-1, 0, 0)
	return Vector3(tmin, nx, ny)



func segment_hit(a: Vector2, b: Vector2, pad: float, mask: int) -> Dictionary:
	var best_t: = 2.0
	var best_i: = -1
	var best_n: = Vector2.ZERO
	var sminx: = minf(a.x, b.x) - pad
	var smaxx: = maxf(a.x, b.x) + pad
	var sminy: = minf(a.y, b.y) - pad
	var smaxy: = maxf(a.y, b.y) + pad
	var scan: PackedInt32Array = _candidates(sminx, sminy, smaxx, smaxy) if indexed else PackedInt32Array()
	for n in (scan.size() if indexed else obs_count):
		var i: int = scan[n] if indexed else n
		if (obs_mask[i] & mask) == 0:
			continue
		if obs_maxx[i] < sminx or obs_minx[i] > smaxx or obs_maxy[i] < sminy or obs_miny[i] > smaxy:
			continue
		if obs_circle[i] == 1:
			var c: = Vector2(obs_x[i], obs_y[i])
			var t: = seg_circle_t(a, b, c, obs_r[i] + pad)
			if t >= 0.0 and t < best_t:
				best_t = t
				best_i = i
				var pt: = a.lerp(b, t)
				var nn: = pt - c
				best_n = nn.normalized() if nn.length_squared() > 1e-12 else (a - b).normalized()
		else:
			var r: = seg_rect(a, b, obs_x[i], obs_y[i], obs_w[i], obs_h[i], pad)
			if r.x >= 0.0 and r.x < best_t:
				best_t = r.x
				best_i = i
				best_n = Vector2(r.y, r.z)
				if best_n == Vector2.ZERO:
					best_n = (a - b).normalized()
	if best_i < 0:
		return {}
	return {"t": best_t, "point": a.lerp(b, best_t), "normal": best_n, "idx": best_i}


func segment_blocked(a: Vector2, b: Vector2, pad: float, mask: int) -> bool:
	var sminx: = minf(a.x, b.x) - pad
	var smaxx: = maxf(a.x, b.x) + pad
	var sminy: = minf(a.y, b.y) - pad
	var smaxy: = maxf(a.y, b.y) + pad
	var scan: PackedInt32Array = _candidates(sminx, sminy, smaxx, smaxy) if indexed else PackedInt32Array()
	for n in (scan.size() if indexed else obs_count):
		var i: int = scan[n] if indexed else n
		if (obs_mask[i] & mask) == 0:
			continue
		if obs_maxx[i] < sminx or obs_minx[i] > smaxx or obs_maxy[i] < sminy or obs_miny[i] > smaxy:
			continue
		if obs_circle[i] == 1:
			if seg_circle_t(a, b, Vector2(obs_x[i], obs_y[i]), obs_r[i] + pad) >= 0.0:
				return true
		else:
			if seg_rect(a, b, obs_x[i], obs_y[i], obs_w[i], obs_h[i], pad).x >= 0.0:
				return true
	return false


func line_of_sight(a: Vector2, b: Vector2, pad: float = 2.0) -> bool:
	return not segment_blocked(a, b, pad, MASK_VISION)



func terrain_contact(a: Vector2, b: Vector2, r: float, projectile: bool) -> Dictionary:
	var hit: = segment_hit(a, b, r, MASK_PROJECTILES if projectile else MASK_UNITS)
	var pr: = 0.0 if projectile else r
	var lo_x: = min_x + pr
	var hi_x: = max_x - pr
	var lo_y: = min_y + pr
	var hi_y: = max_y - pr
	var d: = b - a
	if absf(d.x) > 1e-12 and (b.x < lo_x or b.x > hi_x):
		var edge: = lo_x if b.x < lo_x else hi_x
		var t: = clampf((edge - a.x) / d.x, 0.0, 1.0)
		if hit.is_empty() or t < float(hit.t):
			hit = {"t": t, "point": a + d * t, "normal": Vector2(1.0 if b.x < lo_x else -1.0, 0.0), "idx": -1}
	if absf(d.y) > 1e-12 and (b.y < lo_y or b.y > hi_y):
		var edge2: = lo_y if b.y < lo_y else hi_y
		var t2: = clampf((edge2 - a.y) / d.y, 0.0, 1.0)
		if hit.is_empty() or t2 < float(hit.t):
			hit = {"t": t2, "point": a + d * t2, "normal": Vector2(0.0, 1.0 if b.y < lo_y else -1.0), "idx": -1}
	return hit




func distance_to_wall(p: Vector2) -> float:
	var best: = minf(minf(p.x - min_x, max_x - p.x), minf(p.y - min_y, max_y - p.y))
	var scan: PackedInt32Array = _candidates(p.x - 384.0, p.y - 384.0, p.x + 384.0, p.y + 384.0) if indexed else PackedInt32Array()
	for n in (scan.size() if indexed else obs_count):
		var i: int = scan[n] if indexed else n
		if obs_mask[i] == 0:
			continue
		if obs_circle[i] == 1:
			best = minf(best, maxf(0.0, p.distance_to(Vector2(obs_x[i], obs_y[i])) - obs_r[i]))
		else:
			var cx: = clampf(p.x, obs_x[i], obs_x[i] + obs_w[i])
			var cy: = clampf(p.y, obs_y[i], obs_y[i] + obs_h[i])
			if p.x >= obs_x[i] and p.x <= obs_x[i] + obs_w[i] and p.y >= obs_y[i] and p.y <= obs_y[i] + obs_h[i]:
				best = 0.0
			else:
				best = minf(best, p.distance_to(Vector2(cx, cy)))
	return maxf(0.0, best)



func nearest_wall(p: Vector2) -> Dictionary:
	var best: = {"distance": p.x - min_x, "point": Vector2(min_x, p.y), "normal": Vector2(1, 0), "tangent": Vector2(0, 1)}
	var cand: = [
		{"distance": max_x - p.x, "point": Vector2(max_x, p.y), "normal": Vector2(-1, 0), "tangent": Vector2(0, 1)}, 
		{"distance": p.y - min_y, "point": Vector2(p.x, min_y), "normal": Vector2(0, 1), "tangent": Vector2(1, 0)}, 
		{"distance": max_y - p.y, "point": Vector2(p.x, max_y), "normal": Vector2(0, -1), "tangent": Vector2(1, 0)}, 
	]
	for c in cand:
		if float(c.distance) < float(best.distance):
			best = c
	var scan: PackedInt32Array = _candidates(p.x - 384.0, p.y - 384.0, p.x + 384.0, p.y + 384.0) if indexed else PackedInt32Array()
	for scan_k in (scan.size() if indexed else obs_count):
		var i: int = scan[scan_k] if indexed else scan_k
		# An open gate (mask 0) is not a wall for wall-running or wall passives.
		if obs_mask[i] == 0:
			continue
		if obs_circle[i] == 1:
			var cc: = Vector2(obs_x[i], obs_y[i])
			var n: = (p - cc)
			n = n.normalized() if n.length_squared() > 1e-06 else Vector2(1, 0)
			var dd: = maxf(0.0, p.distance_to(cc) - obs_r[i])
			if dd < float(best.distance):
				best = {"distance": dd, "point": cc + n * obs_r[i], "normal": n, "tangent": Vector2( - n.y, n.x)}
		else:
			var q: = Vector2(clampf(p.x, obs_x[i], obs_x[i] + obs_w[i]), clampf(p.y, obs_y[i], obs_y[i] + obs_h[i]))
			var n2: = p - q
			if n2.length_squared() < 1e-06:
				var l: = absf(p.x - obs_x[i])
				var r: = absf(obs_x[i] + obs_w[i] - p.x)
				var t: = absf(p.y - obs_y[i])
				var bt: = absf(obs_y[i] + obs_h[i] - p.y)
				var mn: = minf(minf(l, r), minf(t, bt))
				n2 = Vector2(-1, 0) if mn == l else (Vector2(1, 0) if mn == r else (Vector2(0, -1) if mn == t else Vector2(0, 1)))
			else:
				n2 = n2.normalized()
			var d2: = p.distance_to(q)
			if d2 < float(best.distance):
				best = {"distance": d2, "point": q, "normal": n2, "tangent": Vector2( - n2.y, n2.x)}
	return best


func avoidance_vector(p: Vector2, r: float = 18.0, lookahead: float = 96.0) -> Vector2:
	var v: = Vector2.ZERO
	var left: = p.x - min_x - r
	var right: = max_x - p.x - r
	var top: = p.y - min_y - r
	var bottom: = max_y - p.y - r
	if left < lookahead: v.x += (lookahead - left) / lookahead
	if right < lookahead: v.x -= (lookahead - right) / lookahead
	if top < lookahead: v.y += (lookahead - top) / lookahead
	if bottom < lookahead: v.y -= (lookahead - bottom) / lookahead
	var reach: float = r + lookahead + 4.0
	var scan: PackedInt32Array = _candidates(p.x - reach, p.y - reach, p.x + reach, p.y + reach) if indexed else PackedInt32Array()
	for n in (scan.size() if indexed else obs_count):
		var i: int = scan[n] if indexed else n
		if (obs_mask[i] & MASK_UNITS) == 0:
			continue
		var nearest: Vector2
		if obs_circle[i] == 1:
			var c: = Vector2(obs_x[i], obs_y[i])
			var dir: = (p - c)
			dir = dir.normalized() if dir.length_squared() > 1e-06 else Vector2(1, 0)
			nearest = c + dir * obs_r[i]
		else:
			nearest = Vector2(clampf(p.x, obs_x[i], obs_x[i] + obs_w[i]), clampf(p.y, obs_y[i], obs_y[i] + obs_h[i]))
		var away: = p - nearest
		var dist: = away.length() - r
		if dist >= lookahead:
			continue
		var dirn: = away.normalized() if away.length_squared() > 1e-06 else Vector2(nearest_wall(p).normal)
		v += dirn * clampf((lookahead - dist) / lookahead, 0.0, 1.4)
	return v.normalized() if v.length_squared() > 1e-10 else v





# Public clock of any hazard (and of a gate definition from Arena.gates).
# artillery: warning = telegraphed salvo in flight, active = impact flash
# (activeDuration, default 0.3 s) at the start of the next cycle.
# closing_ring: warning = last warningDuration (default 5 s) before startTime,
# active from startTime on; remaining = time until startTime, then until endTime.
static func hazard_clock(h: Dictionary, t: float) -> Dictionary:
	var typ: = str(h.get("type", ""))
	if typ == "gate":
		return gate_clock(h, t)
	if typ == "closing_ring":
		return _ring_clock(h, t)
	if h.get("alwaysActive", false) or typ in ALWAYS_ON_TYPES:
		return {"active": true, "warning": false, "progress": 1.0, "cycle": 0, "remaining": 0.0, "to_active": 0.0}
	var period: = maxf(0.1, float(h.get("period", 1.0)))
	var phase: = float(h.get("phase", 0.0))
	var shifted: = fposmod(t + phase, period)
	var act: = clampf(float(h.get("activeDuration", 0.3 if typ == "artillery" else 0.0)), 0.0, period)
	var warn: = clampf(float(h.get("warningDuration", 0.0)), 0.0, period - act)
	return {
		"active": shifted < act, 
		"warning": shifted >= period - warn, 
		"progress": (shifted / maxf(0.001, act)) if shifted < act else (shifted / period), 
		"cycle": int(floor((t + phase) / period)), 
		"to_active": (period - shifted) if shifted >= act else 0.0, 
		"remaining": act - shifted if shifted < act else (period - shifted if shifted >= period - warn else period - warn - shifted),
	}


# The same expanding ring is used by simulation, drawing and AI forecasting.
# previous_t/previous_position sweep a single simulation step, preventing a
# fast wave or a moving unit from slipping through between two sampled frames.
# closing_ring: the EFFECT region is outside the current safe circle (padding
# widens the outside, i.e. shrinks the safe radius). Every other type uses its
# authored shape (for artillery that is the landing area, strikes themselves are
# ArenaEnv state).
static func hazard_effect_contains(h: Dictionary, p: Vector2, t: float, padding: float = 0.0, previous_t: float = -1.0, previous_position: Vector2 = Vector2.INF) -> bool:
	var typ: String = str(h.get("type", ""))
	if typ == "closing_ring":
		return ring_outside(h, p, t, padding)
	if typ != "shockwave":
		return shape_contains(h, p, padding)
	var clk: Dictionary = hazard_clock(h, t)
	var period: float = maxf(0.1, float(h.get("period", 1.0)))
	var duration: float = clampf(float(h.get("activeDuration", 1.0)), 0.001, period)
	var phase: float = float(h.get("phase", 0.0))
	var cycle: int = int(clk.cycle)
	var cycle_start: float = float(cycle) * period - phase
	var prior: float = t if previous_t < 0.0 else minf(previous_t, t)
	if not bool(clk.active) and not (prior < cycle_start + duration and prior >= cycle_start):
		return false
	var maximum: float = maxf(0.0, float(h.get("radius", 0.0)))
	var sweep_start: float = maxf(prior, cycle_start)
	var sweep_end: float = minf(t, cycle_start + duration)
	var low: float = clampf((sweep_start - cycle_start) / duration, 0.0, 1.0) * maximum
	var high: float = clampf((sweep_end - cycle_start) / duration, 0.0, 1.0) * maximum
	var center_pos: Vector2 = h.get("center", _shape_center(h))
	var from: Vector2 = p if previous_position == Vector2.INF else previous_position
	var span: float = t - prior
	var start_pos: Vector2 = from.lerp(p, clampf((sweep_start - prior) / span, 0.0, 1.0)) if span > 1e-9 else p
	var end_pos: Vector2 = from.lerp(p, clampf((sweep_end - prior) / span, 0.0, 1.0)) if span > 1e-9 else p
	var half_width: float = maxf(1.0, float(h.get("ringWidth", 22.0))) * 0.5 + padding
	if absf(start_pos.distance_to(center_pos) - low) <= half_width or absf(end_pos.distance_to(center_pos) - high) <= half_width:
		return true
	# Compare unit and wave at the SAME interpolated time. Merely overlapping
	# their independent radial ranges incorrectly hits runners keeping a safe
	# lead ahead of a wave, and misses a dash through its center.
	var relative: Vector2 = start_pos - center_pos
	var movement: Vector2 = end_pos - start_pos
	return _swept_ring_edge(relative, movement, low + half_width, high - low) or _swept_ring_edge(relative, movement, low - half_width, high - low)


static func _swept_ring_edge(relative: Vector2, movement: Vector2, radius_start: float, radius_delta: float) -> bool:
	var a: float = movement.length_squared() - radius_delta * radius_delta
	var b: float = 2.0 * (relative.dot(movement) - radius_start * radius_delta)
	var c: float = relative.length_squared() - radius_start * radius_start
	if absf(a) < 1e-8:
		if absf(b) < 1e-8:
			return absf(c) < 1e-8 and maxf(radius_start, radius_start + radius_delta) >= 0.0
		var root: float = -c / b
		return root >= 0.0 and root <= 1.0 and radius_start + radius_delta * root >= 0.0
	var discriminant: float = b * b - 4.0 * a * c
	if discriminant < 0.0:
		return false
	var square_root: float = sqrt(discriminant)
	for root: float in [(-b - square_root) / (2.0 * a), (-b + square_root) / (2.0 * a)]:
		if root >= 0.0 and root <= 1.0 and radius_start + radius_delta * root >= 0.0:
			return true
	return false


static func shockwave_radius(h: Dictionary, t: float) -> float:
	var clk: Dictionary = hazard_clock(h, t)
	return float(h.get("radius", 0.0)) * float(clk.progress) if bool(clk.active) else 0.0


static func shockwave_expected_hits(h: Dictionary, p: Vector2, t: float, radius: float, horizon: float) -> int:
	var center_pos: Vector2 = h.get("center", _shape_center(h))
	var distance: float = p.distance_to(center_pos)
	var maximum: float = maxf(1.0, float(h.get("radius", 0.0)))
	var half_width: float = maxf(1.0, float(h.get("ringWidth", 22.0))) * 0.5 + radius
	if distance > maximum + half_width:
		return 0
	var period: float = maxf(0.1, float(h.get("period", 1.0)))
	var duration: float = clampf(float(h.get("activeDuration", 1.0)), 0.001, period)
	var phase: float = float(h.get("phase", 0.0))
	var first: int = int(floor((t + phase) / period))
	var last: int = int(floor((t + maxf(0.0, horizon) + phase) / period))
	var hits: int = 0
	for cycle in range(first, last + 1):
		var start: float = float(cycle) * period - phase
		var entry: float = start + clampf((distance - half_width) / maximum, 0.0, 1.0) * duration
		var leave: float = start + clampf((distance + half_width) / maximum, 0.0, 1.0) * duration
		if t <= leave and t + maxf(0.0, horizon) >= entry:
			hits += 1
	return hits


# Conservative raw damage for a unit entering a periodic field now. Per-unit
# hit cooldowns are private simulation state; inactive intervals contribute 0.
static func periodic_damage_ticks(h: Dictionary, t: float, horizon: float) -> int:
	var period: float = maxf(0.1, float(h.get("period", 1.0)))
	var duration: float = clampf(float(h.get("activeDuration", 0.0)), 0.0, period)
	var interval: float = maxf(0.12, float(h.get("tickInterval", 0.5)))
	var phase: float = float(h.get("phase", 0.0))
	var first: int = int(floor((t + phase) / period))
	var last: int = int(floor((t + maxf(0.0, horizon) + phase) / period))
	var ticks: int = 0
	for cycle in range(first, last + 1):
		var start: float = float(cycle) * period - phase
		var exposure: float = minf(t + maxf(0.0, horizon), start + duration) - maxf(t, start)
		if exposure > 1e-9:
			ticks += int(ceil(exposure / interval - 1e-9))
	return ticks


static func hazard_direction(h: Dictionary, t: float) -> Vector2:
	if str(h.get("type", "")) != "wind":
		return Vector2.ZERO
	var half: = maxf(0.5, float(h.get("period", 5.0))) * 0.5
	var idx: = int(floor((t + float(h.get("phase", 0.0))) / half))
	return h.dirA if idx % 2 == 0 else h.dirB



# Steering/path cost of standing at p at time t (public map state only).
# skip_mask: OR of Arena.type_bit(type) for types that are switched off
# (ArenaEnv.hazard_penalty passes the developer toggles).
func hazard_penalty(p: Vector2, t: float, r: float = 0.0, skip_mask: int = 0) -> float:
	var pen: = 0.0
	if _hz_n != hazards.size():
		_index_hazard_boxes()
	for hi in hazards.size():
		var h: Dictionary = hazards[hi]
		if skip_mask != 0 and (skip_mask & _hz_tbit[hi]) != 0:
			continue
		# B-PERF: pads, fountains and haste add nothing; any other non-ring
		# type adds only inside its shape (padded as below).
		var hk: int = _hz_kind[hi]
		if hk == HZ_INERT and not index_off:
			continue
		if hk != HZ_RING and not index_off:
			var bp: float = r + _hz_wpad[hi] + 0.01
			if p.x < _hz_minx[hi] - bp or p.x > _hz_maxx[hi] + bp or p.y < _hz_miny[hi] - bp or p.y > _hz_maxy[hi] + bp:
				continue
		var typ: = str(h.type)
		if typ == "closing_ring":
			pen += ring_penalty(h, p, t, r)
			continue
		var shape_pad: float = r + (maxf(1.0, float(h.get("ringWidth", 22.0))) * 0.5 if typ == "shockwave" else 0.0)
		if not shape_contains(h, p, shape_pad):
			continue
		var clk: = hazard_clock(h, t)
		if typ in ["haste", "healing_fountain", "jump_pad"]:
			continue
		elif typ == "portal":
			pen -= 0.04
		elif typ == "wind" or typ == "mud":
			pen += 0.08
		elif typ == "artillery":
			# Unknown strike points: a mild cost while a salvo is in the air.
			# The announced strike circles are telegraphs (ArenaEnv.hazard_penalty).
			pen += 0.09 if bool(clk.warning) else 0.0
		elif typ == "shockwave":
			if hazard_effect_contains(h, p, t, r):
				pen += 1.3
			elif bool(clk.warning) or shockwave_expected_hits(h, p, t, r, 0.65) > 0:
				pen += 0.42
		elif typ == "gravity":
			# Scaled by the well's actual damage (mode follow-up, audit C-2):
			# the pull alone costs 0.3, a well dealing 60+ dps the old 0.85.
			var gk: float = clampf(maxf(0.0, float(h.get("damage", 0.0))) / maxf(0.12, float(h.get("tickInterval", 0.5))) / 60.0, 0.0, 1.0)
			if clk.active:
				pen += 0.3 + 0.55 * gk
			elif clk.warning:
				pen += 0.2 + 0.18 * gk
		elif clk.active:
			pen += 1.4 if typ == "eruption" else (0.62 if typ == "lava" else 0.75)
		elif clk.warning:
			pen += 0.38
	if not gates.is_empty() and (skip_mask & TYPE_BITS["gate"]) == 0:
		pen += gate_penalty(p, t, r)
	return pen


# Standing inside a gate frame: a closed gate is a wall (2.0), one that closes
# within max(warningDuration, NAV_CLOSING_MARGIN) should be left now (0.9).
func gate_penalty(p: Vector2, t: float, r: float = 0.0) -> float:
	var pen: float = 0.0
	for g in gates:
		var rect: Rect2 = g.rect
		if p.x < rect.position.x - r or p.x > rect.end.x + r or p.y < rect.position.y - r or p.y > rect.end.y + r:
			continue
		var clk: Dictionary = gate_clock(g, t)
		if not bool(clk.open):
			pen += 2.0
		elif float(clk.remaining) <= maxf(float(g.warningDuration), NAV_CLOSING_MARGIN):
			pen += 0.9
	return pen


static func ring_penalty(h: Dictionary, p: Vector2, t: float, r: float = 0.0) -> float:
	var d: float = p.distance_to(h.get("center", Vector2.ZERO)) + r * 0.3
	if ring_active(h, t) and d > ring_radius_at(h, t):
		return 1.5
	# Leave early: outside the circle that will be safe in 4 s.
	if ring_active(h, t + 4.0) and d > ring_radius_at(h, t + 4.0):
		return 0.35
	return 0.0


# Expected raw damage for a unit standing at p over [t, t + horizon].
# closing_ring deals max_hp * damage fraction per tick outside the circle.
func expected_hazard_damage(p: Vector2, t: float, r: float, horizon: float, skip_mask: int = 0, max_hp: float = 1000.0) -> float:
	var total: = 0.0
	if _hz_n != hazards.size():
		_index_hazard_boxes()
	for hi in hazards.size():
		var h: Dictionary = hazards[hi]
		if skip_mask != 0 and (skip_mask & _hz_tbit[hi]) != 0:
			continue
		# B-PERF: always-on types add nothing; plain fields only inside their
		# shape padded by r (rings, shockwaves and artillery keep their tests).
		var ek: int = _hz_ekind[hi]
		if ek == HZ_INERT and not index_off:
			continue
		if ek == HZ_SHAPE and not index_off and (p.x < _hz_minx[hi] - r - 0.01 or p.x > _hz_maxx[hi] + r + 0.01 or p.y < _hz_miny[hi] - r - 0.01 or p.y > _hz_maxy[hi] + r + 0.01):
			continue
		var typ: = str(h.type)
		if typ in ALWAYS_ON_TYPES:
			continue
		if typ == "shockwave":
			total += float(h.get("damage", 0.0)) * shockwave_expected_hits(h, p, t, r, horizon)
			continue
		if typ == "closing_ring":
			total += ring_expected_ticks(h, p, t, horizon, r) * ring_damage_fraction(h) * max_hp
			continue
		if typ == "artillery":
			total += artillery_expected(h, p, t, r, horizon)
			continue
		if not shape_contains(h, p, r):
			continue
		if typ == "gravity":
			total += float(h.get("damage", 0.0)) * periodic_damage_ticks(h, t, horizon)
			continue
		var now: = hazard_clock(h, t)
		var fut: = hazard_clock(h, t + horizon * 0.55)
		var like: = 1.0 if (h.get("alwaysActive", false) or now.active) else (0.68 if (now.warning or fut.active) else 0.16)
		var interval: = maxf(0.15, float(h.get("tickInterval", horizon)))
		var ticks: = 1.0 if typ == "eruption" else maxf(1.0, horizon / interval)
		total += float(h.get("damage", 0.0)) * ticks * like
	return total


# V2 (B-PERF): hazard type codes and shape boxes for hazard_penalty and
# expected_hazard_damage, built on first use. Hazards are fixed per arena
# (the tactician's hazard bounds assume the same); the boxes only skip
# hazards whose own shape test would fail, so both sums are unchanged.
const HZ_SHAPE: = 0
const HZ_INERT: = 1
const HZ_RING: = 2
const HZ_OTHER: = 3
var _hz_n: int = -1
var _hz_kind: PackedInt32Array = PackedInt32Array()
var _hz_ekind: PackedInt32Array = PackedInt32Array()
var _hz_tbit: PackedInt32Array = PackedInt32Array()
var _hz_wpad: PackedFloat64Array = PackedFloat64Array()
var _hz_minx: PackedFloat64Array = PackedFloat64Array()
var _hz_maxx: PackedFloat64Array = PackedFloat64Array()
var _hz_miny: PackedFloat64Array = PackedFloat64Array()
var _hz_maxy: PackedFloat64Array = PackedFloat64Array()


func _index_hazard_boxes() -> void:
	var n: int = hazards.size()
	_hz_n = n
	_hz_kind.resize(n)
	_hz_ekind.resize(n)
	_hz_tbit.resize(n)
	_hz_wpad.resize(n)
	_hz_minx.resize(n)
	_hz_maxx.resize(n)
	_hz_miny.resize(n)
	_hz_maxy.resize(n)
	for i in n:
		var h: Dictionary = hazards[i]
		var typ: String = str(h.type)
		_hz_tbit[i] = int(h.get("tbit", 0))
		if typ == "closing_ring":
			_hz_kind[i] = HZ_RING
		elif typ in ["haste", "healing_fountain", "jump_pad"]:
			_hz_kind[i] = HZ_INERT
		else:
			_hz_kind[i] = HZ_SHAPE
		if typ in ALWAYS_ON_TYPES:
			_hz_ekind[i] = HZ_INERT
		elif typ in ["shockwave", "closing_ring", "artillery"]:
			_hz_ekind[i] = HZ_OTHER
		else:
			_hz_ekind[i] = HZ_SHAPE
		_hz_wpad[i] = maxf(1.0, float(h.get("ringWidth", 22.0))) * 0.5 if typ == "shockwave" else 0.0
		# shape_contains: circle = centre (x, y) and radius, else the rect x, y, w, h.
		var hx: float = float(h.get("x", 0.0))
		var hy: float = float(h.get("y", 0.0))
		if str(h.get("shape", "rect")) == "circle":
			var cr: float = float(h.get("radius", 0.0))
			_hz_minx[i] = hx - cr
			_hz_maxx[i] = hx + cr
			_hz_miny[i] = hy - cr
			_hz_maxy[i] = hy + cr
		else:
			_hz_minx[i] = hx
			_hz_maxx[i] = hx + float(h.get("w", 0.0))
			_hz_miny[i] = hy
			_hz_maxy[i] = hy + float(h.get("h", 0.0))


# Damage ticks a unit standing still at p would take from the ring in the horizon.
static func ring_expected_ticks(h: Dictionary, p: Vector2, t: float, horizon: float, r: float = 0.0) -> float:
	var interval: float = maxf(0.2, float(h.get("tickInterval", 1.0)))
	var d: float = p.distance_to(h.get("center", Vector2.ZERO)) + r * 0.3
	var ticks: float = 0.0
	var tau: float = t
	var limit: float = t + maxf(0.0, horizon)
	while tau <= limit + 1e-6:
		if ring_active(h, tau) and d > ring_radius_at(h, tau):
			ticks += 1.0
		tau += interval
	return ticks
