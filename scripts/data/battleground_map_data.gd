class_name BattlegroundMapData
extends RefCounted

# Battleground fields (DESIGN_V2 §3.2): three presets of about 30x the standard
# 1408x792 area, each a recognisable plan that the seed varies.
#   br_ashen_metropolis   road grid over districts (dense blocks of doorway
#                         buildings, parks, ruins, artillery plazas), avenue
#                         haste and one central fortress with timed gates.
#   br_wildwood_frontier  forest masses, a meandering river (water blocks bodies
#                         only) crossed by narrow bridges and mud fords, forest
#                         villages around healing fountains.
#   br_highland_ruins     four broken ridges (passes, jump pads) that cut the
#                         plateau into nine regions, ruin sites, meadows with
#                         gusts and one gravity well.
# build(preset, seed) is a pure function of its arguments and touches no shared
# state, so it may run on a worker thread. It returns DeathmatchMapData-style
# arena data plus kind "battleground", ffa_spawns, item_spots
# [{x, y, kind, ring}] and br {center, half_diag, landmarks, core_radius,
# ring_limits, decor}; decor (roads, river course, crossings, ridge lines) is
# for painters only. generate(preset, attempt_seed) is one unvalidated attempt
# for tools.
#
# Placement works on a grid of reserved rectangles with layer flags (F_*): a
# feature checks the layers it may not overlap and reserves its own footprint.
# Free-standing solids keep 2 * GAP = 92 px between their edges (a bucket-30
# body needs 66 px plus one diagonal 16 px cell); rock formations are 1-4
# overlapping boulders, i.e. one solid blob.
#
# Validation (connectivity()): for each body bucket 30/26/18/12 the map is
# rasterised into a navigator-style grid (16 px cells; a cell is solid when its
# centre lies within bucket + 3 of a unit-blocking obstacle or within bucket of
# the bounds; gates count as closed, jump pads as absent). Its free runs are
# labelled into 4-connected components in one union-find pass (one flood fill
# per bucket, no per-anchor A*). Every spawn, hazard anchor, jump-pad landing
# and the map centre must be walkable and reach a cell of the largest component
# in a straight line. Item spots that fail are dropped; at least 240 must stay,
# with every ring above its minimum. At most 6 attempts, then a validated
# canonical seed.

const MARGIN := 48.0
const CELL := 16.0
const BUCKETS := [30.0, 26.0, 18.0, 12.0]
const MAX_ATTEMPTS := 6
const FALLBACK_SEEDS := [20261001, 4049, 77777]
const SPAWN_MIN := 40
const SPAWN_GAP := 800.0
# Hex lattice step and jitter keep every pair of spawns >= 800 px apart
# (832 - 2 * sqrt(2) * 10 > 800).
const SPAWN_STEP := 832.0
const SPAWN_JITTER := 10.0
const SPAWN_EDGE := 176.0
const SPAWN_CLEAR := 128.0
const CORE_RATIO := 0.18
const RING_LIMITS := [0.2, 0.45, 0.7]
const SPOT_MIN := 240
const RING_SPOT_MIN := [24, 40, 48, 48]
const RING_SPOT_TARGET := [36, 66, 90, 90]
const SPOT_BODY := 30.0
const LIMITS := {"obstacles": [500, 700], "brush": [150, 220], "patches": [40, 70], "hazards": [20, 40], "landmarks": [10, 16]}
const BRUSH_MAX := 216
const PATCH_MAX := 68
const LANDMARK_MAX := 16
# Theme features every map of a preset must carry ([type, minimum, maximum]);
# "water" counts water obstacles, the rest hazard types or gate obstacles.
const REQUIRED := {
	"br_ashen_metropolis": [["gate", 4, 4], ["artillery", 2, 3], ["haste", 6, 40], ["healing_fountain", 1, 6]],
	"br_wildwood_frontier": [["water", 8, 60], ["mud", 2, 10], ["healing_fountain", 3, 8], ["haste", 3, 20]],
	"br_highland_ruins": [["jump_pad", 6, 14], ["wind", 3, 6], ["gravity", 1, 1], ["healing_fountain", 1, 4]],
}
# Half of the minimum edge gap between two free-standing solids (see _solid_circle).
const GAP := 46.0

# Reservation layers: a later feature may not overlap a reserved rectangle whose
# flags meet the mask it checks.
const F_SOLID := 1
const F_BRUSH := 2
const F_HAZARD := 4
const F_PROP := 8
const F_BARRIER := 16
const F_SPOT := 32
# Everything except the barrier layer (spawn clearings, springs, pads).
const F_CLEAR := F_SOLID | F_BRUSH | F_HAZARD | F_PROP | F_SPOT

const PRESETS := {
	"br_ashen_metropolis": {"name": "잿빛 대도시", "subtitle": "도로 격자 · 중앙 성문 요새 · 광장 포격",
		"description": "잿빛으로 무너진 대도시입니다. 넓은 도로 격자가 건물 밀집 구역, 공원, 폐허 구역을 나누고, 한가운데에는 성문이 주기적으로 열리는 요새가 있습니다. 광장에는 예고 뒤 포격이 떨어지고, 중앙 대로와 횡단 대로를 따라 가속 구역이 이어집니다.",
		"tacticalNotes": ["건물마다 문이 두 곳 이상 있고 벽이 이동·투사체·시야를 모두 막습니다. 실내 아이템 자리는 문 앞 매복을 조심하며 챙깁니다.",
			"중앙 요새의 네 성문은 함께 열리고 닫힙니다. 성문이 닫혀도 각 성벽의 무너진 틈으로 드나들 수 있습니다.",
			"광장 포격은 예고 원이 보인 뒤 떨어집니다. 중앙 대로와 횡단 대로의 가속 구역은 자기장을 따라 이동할 때 유리합니다.",
			"공원 숲 안의 영웅은 밖에서 보이지 않습니다. 도로를 건너기 전에 숲과 건물 그늘에서 시야를 먼저 확보합니다."],
		"accent": "#e0a86e", "floor": "#15120e", "grid": "#d6b48a", "width": 7712.0, "height": 4336.0,
		"layout_id": "br_city_grid_fortress",
		"tags": ["배틀그라운드", "최대 30명", "도시", "건물", "성문 요새", "포격"]},
	"br_wildwood_frontier": {"name": "야생림 변경", "subtitle": "울창한 숲 · 굽이치는 강 · 다리와 여울",
		"description": "울창한 숲이 대부분을 덮은 변경입니다. 북쪽에서 남쪽으로 굽이치는 강이 전장을 가르고, 강을 건너는 길은 좁은 다리와 진흙 여울뿐입니다. 숲속 마을의 회복 샘이 쉼터가 됩니다.",
		"tacticalNotes": ["강물은 이동만 막고 시야와 투사체는 통과합니다. 강 건너 적을 견제할 수 있지만 건너려면 다리나 여울을 지나야 합니다.",
			"다리는 좁은 길목입니다. 여울은 넓지만 진흙이 머무는 동안 이동 속도를 늦춥니다.",
			"숲 마을마다 공용 회복 샘이 있고 오두막 안에 아이템 자리가 있습니다.",
			"숲이 넓어 매복하기 쉽습니다. 숲 사이 공터의 가속 구역과 골짜기 바람을 타면 빠르게 이동합니다."],
		"accent": "#7fd08a", "floor": "#0b1710", "grid": "#7fd08a", "width": 7040.0, "height": 4752.0,
		"layout_id": "br_forest_river_villages",
		"tags": ["배틀그라운드", "최대 30명", "숲", "강", "다리", "진흙 여울"]},
	"br_highland_ruins": {"name": "고원 유적", "subtitle": "긴 능선 · 도약 발판 · 고대 유적",
		"description": "네 줄기 긴 능선이 고원을 아홉 구역으로 나눕니다. 능선의 고개로 지나거나 도약 발판으로 넘고, 열린 초원에는 돌풍이 붑니다. 고대 유적의 돌기둥과 무너진 건물이 엄폐물이 되며, 한 유적에는 중력 우물이 있습니다.",
		"tacticalNotes": ["능선은 이동·투사체·시야를 모두 막습니다. 고개와 능선이 엇갈리는 틈으로 건너거나, 도약 발판으로 표시된 방향으로 넘습니다.",
			"열린 초원은 원거리 영웅에게 유리합니다. 돌풍은 주기적으로 방향을 바꾸며 영웅을 밀어냅니다.",
			"유적의 돌기둥 사이는 근접 교전에 좋습니다. 중력 우물은 활성화되면 중심으로 끌어당기며 피해를 줍니다.",
			"중앙 고원 신전은 능선으로 둘러싸여 있어 마지막 자기장이 가까워질수록 고개를 먼저 차지하는 쪽이 유리합니다."],
		"accent": "#9ec3e6", "floor": "#0f1520", "grid": "#9ec3e6", "width": 5792.0, "height": 5776.0,
		"layout_id": "br_highland_ridges_ruins",
		"tags": ["배틀그라운드", "최대 30명", "능선", "도약 발판", "유적", "돌풍"]},
}
const ORDER := ["br_ashen_metropolis", "br_wildwood_frontier", "br_highland_ruins"]


# Generation state of one attempt: the growing feature lists plus a uniform
# grid of reserved rectangles (256 px cells) so placement tests stay local.
class Gen extends RefCounted:
	const RES_CELL := 256.0
	var r: RandomNumberGenerator = RandomNumberGenerator.new()
	var id: String = ""
	var w: float = 0.0
	var h: float = 0.0
	var min_x: float = 0.0
	var max_x: float = 0.0
	var min_y: float = 0.0
	var max_y: float = 0.0
	var center: Vector2 = Vector2.ZERO
	var half_diag: float = 0.0
	var core_r: float = 0.0
	var obstacles: Array = []
	var forests: Array = []
	var patches: int = 0
	var hazards: Array = []
	var buildings: Array = []
	var landmarks: Array = []
	var spawns: Array[Vector2] = []
	# Item spot candidates {pos, kind}; filtered against the finished arena.
	var cands: Array = []
	# Decoration for painters and the atlas (roads, river course); no gameplay.
	var decor: Array = []
	var lattice: Dictionary = {}
	var names: Dictionary = {}
	var _count: Dictionary = {}
	var _rects: Array[Rect2] = []
	var _flags: PackedInt32Array = PackedInt32Array()
	var _cells: Dictionary = {}
	var _gw: int = 1
	var _gh: int = 1

	func setup(preset_id: String, preset: Dictionary, seed_value: int, margin: float, core_ratio: float) -> void:
		id = preset_id
		r.seed = seed_value
		w = float(preset.width)
		h = float(preset.height)
		min_x = margin
		min_y = margin
		max_x = w - margin
		max_y = h - margin
		center = Vector2(w * 0.5, h * 0.5)
		half_diag = 0.5 * sqrt(w * w + h * h)
		core_r = minf(w, h) * core_ratio
		_gw = int(ceil(w / RES_CELL)) + 1
		_gh = int(ceil(h / RES_CELL)) + 1

	func uid(prefix: String) -> String:
		var n: int = int(_count.get(prefix, 0))
		_count[prefix] = n + 1
		return "%s_%d" % [prefix, n]

	func reserve(rect: Rect2, flags: int) -> void:
		var i: int = _rects.size()
		_rects.append(rect)
		_flags.append(flags)
		var x0: int = clampi(int(floor(rect.position.x / RES_CELL)), 0, _gw - 1)
		var x1: int = clampi(int(floor(rect.end.x / RES_CELL)), 0, _gw - 1)
		var y0: int = clampi(int(floor(rect.position.y / RES_CELL)), 0, _gh - 1)
		var y1: int = clampi(int(floor(rect.end.y / RES_CELL)), 0, _gh - 1)
		for gy in range(y0, y1 + 1):
			for gx in range(x0, x1 + 1):
				var key: int = gy * _gw + gx
				if not _cells.has(key):
					_cells[key] = []
				(_cells[key] as Array).append(i)

	func blocked(rect: Rect2, mask: int) -> bool:
		var x0: int = clampi(int(floor(rect.position.x / RES_CELL)), 0, _gw - 1)
		var x1: int = clampi(int(floor(rect.end.x / RES_CELL)), 0, _gw - 1)
		var y0: int = clampi(int(floor(rect.position.y / RES_CELL)), 0, _gh - 1)
		var y1: int = clampi(int(floor(rect.end.y / RES_CELL)), 0, _gh - 1)
		for gy in range(y0, y1 + 1):
			for gx in range(x0, x1 + 1):
				var cell = _cells.get(gy * _gw + gx)
				if cell == null:
					continue
				for i: int in cell:
					if (_flags[i] & mask) != 0 and _rects[i].intersects(rect):
						return true
		return false

	func inside(p: Vector2, inset: float) -> bool:
		return p.x >= min_x + inset and p.x <= max_x - inset and p.y >= min_y + inset and p.y <= max_y - inset

	func count_type(type: String) -> int:
		var n: int = 0
		for hz: Dictionary in hazards:
			if str(hz.type) == type:
				n += 1
		return n

	func add_spot(p: Vector2, kind: String) -> void:
		cands.append({"pos": p, "kind": kind})


static func is_battleground_id(id: String) -> bool:
	return PRESETS.has(id)


# Catalogue entries shown in setup screens and the codex (no geometry: it
# depends on the seed). Same fields as DeathmatchMapData.catalogue().
static func catalogue() -> Array:
	var out: Array = []
	for id in ORDER:
		var p: Dictionary = PRESETS[id]
		var w: float = float(p.width)
		var h: float = float(p.height)
		out.append({"id": id, "kind": "battleground", "name": p.name, "subtitle": p.subtitle, "description": p.description,
			"ruleset": "battleground", "layout_id": p.layout_id, "accent": p.accent, "difficulty": "배틀그라운드", "icon": "◉",
			"tags": (p.tags as Array) + ["시드별 배치"],
			"width": w, "height": h, "area_ratio": w * h / (Arena.WIDTH * Arena.HEIGHT),
			"bounds": {"minX": MARGIN, "maxX": w - MARGIN, "minY": MARGIN, "maxY": h - MARGIN},
			"floor": {"base": p.floor, "blue": "#16435c", "red": "#542f4b", "grid": p.grid},
			"spawns": {"blue": [{"x": 300.0, "y": 300.0}], "red": [{"x": w - 300.0, "y": h - 300.0}]},
			"obstacles": [], "hazards": [], "control_points": [], "heal_zones": [], "forests": [],
			"tacticalNotes": (p.tacticalNotes as Array).duplicate()})
	return out


# Ring of a point: 0 = d < 0.2, 1 = < 0.45, 2 = < 0.7, 3 = the rest, where d
# is the distance to the map centre divided by the half diagonal.
static func ring_of(p: Vector2, center: Vector2, half_diag: float) -> int:
	var d: float = p.distance_to(center) / maxf(1.0, half_diag)
	for k in RING_LIMITS.size():
		if d < float(RING_LIMITS[k]):
			return k
	return RING_LIMITS.size()


static func build(preset_id: String, seed_value: int, report: Dictionary = {}) -> Dictionary:
	var pid: String = preset_id if PRESETS.has(preset_id) else str(ORDER[0])
	var reasons: Array = []
	report["reasons"] = reasons
	for attempt in MAX_ATTEMPTS:
		var data: Dictionary = _attempt(pid, seed_value * 1009 + attempt * 7919 + 17, reasons)
		if not data.is_empty():
			_finish(data, pid, seed_value, attempt, false)
			return data
	# Canonical seeds keep the preset's plan and pass the same contract.
	for fallback_seed in FALLBACK_SEEDS:
		var data2: Dictionary = _attempt(pid, int(fallback_seed), reasons)
		if not data2.is_empty():
			_finish(data2, pid, seed_value, MAX_ATTEMPTS, true)
			return data2
	push_error("Battleground map has no validated layout: " + pid)
	return {}


static func _finish(data: Dictionary, pid: String, seed_value: int, attempt: int, fallback: bool) -> void:
	data["id"] = "%s_%d" % [pid, seed_value]
	data["seed"] = seed_value
	data["generation_attempt"] = attempt
	if fallback:
		data["generation_fallback"] = true


static func _attempt(pid: String, attempt_seed: int, reasons: Array) -> Dictionary:
	var arena_out: Array = []
	var data: Dictionary = generate(pid, attempt_seed, arena_out)
	if (data.ffa_spawns as Array).size() < SPAWN_MIN:
		reasons.append("%d: spawns %d" % [attempt_seed, (data.ffa_spawns as Array).size()])
		return {}
	var why: String = _validate(data, arena_out[0])
	if why != "":
		reasons.append("%d: %s" % [attempt_seed, why])
		return {}
	return data


# One unvalidated generation attempt (tools and diagnostics; build() is the
# game's entry point). arena_out receives the Arena used for the item spots.
static func generate(preset_id: String, attempt_seed: int, arena_out: Array = []) -> Dictionary:
	var pid: String = preset_id if PRESETS.has(preset_id) else str(ORDER[0])
	var preset: Dictionary = PRESETS[pid]
	var g := Gen.new()
	g.setup(pid, preset, attempt_seed, MARGIN, CORE_RATIO)
	match pid:
		"br_wildwood_frontier":
			_wildwood(g)
		"br_highland_ruins":
			_highland(g)
		_:
			_metropolis(g)
	if g.spawns.size() < 2:
		return {"ffa_spawns": []}
	var data: Dictionary = _assemble(g, pid, preset)
	var arena: Arena = Arena.from_data(data)
	data["item_spots"] = _spots(g, arena)
	arena_out.append(arena)
	return data


static func _assemble(g: Gen, pid: String, preset: Dictionary) -> Dictionary:
	var ffa: Array = []
	for p in g.spawns:
		ffa.append({"x": p.x, "y": p.y})
	return {"id": pid, "preset": pid, "kind": "battleground", "name": preset.name, "subtitle": preset.subtitle,
		"description": preset.description, "ruleset": "battleground", "accent": preset.accent, "layout_id": preset.layout_id,
		"landmarks": g.landmarks, "difficulty": "배틀그라운드", "icon": "◉", "tags": (preset.tags as Array) + ["시드별 배치"],
		"width": g.w, "height": g.h,
		"bounds": {"minX": g.min_x, "maxX": g.max_x, "minY": g.min_y, "maxY": g.max_y},
		"floor": {"base": preset.floor, "blue": "#16435c", "red": "#542f4b", "grid": preset.grid},
		"obstacles": g.obstacles, "forests": g.forests, "buildings": g.buildings, "hazards": g.hazards,
		"control_points": [], "heal_zones": [], "tacticalNotes": (preset.tacticalNotes as Array).duplicate(),
		"ffa_spawns": ffa, "item_spots": [], "spawns": {"blue": [ffa[0]], "red": [ffa[1]]},
		"br": {"center": {"x": g.center.x, "y": g.center.y}, "half_diag": g.half_diag, "landmarks": g.landmarks,
			"core_radius": g.core_r, "ring_limits": RING_LIMITS.duplicate(), "decor": g.decor}}


# ------------------------------------------------------------------ pieces

static func _box(p: Vector2, half: float) -> Rect2:
	return Rect2(p - Vector2(half, half), Vector2(half, half) * 2.0)


static func _rect(x: float, y: float, w: float, h: float) -> Rect2:
	return Rect2(roundf(x), roundf(y), roundf(w), roundf(h))


static func _shuffle(r: RandomNumberGenerator, arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j: int = r.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


static func _add_wall(g: Gen, prefix: String, rect: Rect2, color: String, kind: String = "wall", material: String = "stone") -> void:
	if rect.size.x < 4.0 or rect.size.y < 4.0:
		return
	g.obstacles.append(ArenaData._wall(g.uid(prefix), rect.position.x, rect.position.y, rect.size.x, rect.size.y, color, kind, material))


static func _water(g: Gen, rect: Rect2) -> void:
	if rect.size.x < 4.0 or rect.size.y < 4.0:
		return
	g.obstacles.append({"id": g.uid("water"), "shape": "rect", "x": rect.position.x, "y": rect.position.y, "w": rect.size.x, "h": rect.size.y,
		"kind": "chasm", "material": "water", "blocksUnits": true, "blocksProjectiles": false, "blocksVision": false, "color": "#2c6e8e"})


# Small solid circle (rock, pillar, trunk, post) unless its footprint grown by
# gap meets a reserved solid area. Reserves that footprint, so two such circles
# keep 2 * gap between their edges (>= 92 px with GAP: a bucket-30 body needs
# 66 px plus one diagonal grid cell, 23 px, to pass on the 16 px grid).
static func _solid_circle(g: Gen, p: Vector2, rad: float, kind: String, color: String, gap: float, flags: int = F_SOLID | F_PROP | F_HAZARD) -> bool:
	var foot: Rect2 = _box(p, rad + gap)
	if not g.inside(p, rad + 40.0) or g.blocked(foot, F_SOLID):
		return false
	g.obstacles.append(DeathmatchMapData._circle_solid(g.uid(kind), roundf(p.x), roundf(p.y), roundf(rad), kind, color))
	g.reserve(foot, flags)
	return true


# Building with doorways (DeathmatchMapData rules: 22 px walls, doors 132-148,
# at least two sides open). Registers its floor, footprint and supply spots.
static func _house(g: Gen, rect: Rect2, color: String) -> void:
	var r: RandomNumberGenerator = g.r
	var t: float = 22.0
	var door: float = roundf(r.randf_range(132.0, 148.0))
	var open: Array = [r.randf() < 0.6, r.randf() < 0.6, r.randf() < 0.6, r.randf() < 0.6]
	var count: int = 0
	for o in open:
		count += int(o)
	var guard: int = 0
	while count < 2 and guard < 24:
		var side: int = r.randi_range(0, 3)
		if not open[side]:
			open[side] = true
			count += 1
		guard += 1
	if count < 2:
		open[0] = true
		open[1] = true
	var b_id: String = g.uid("bld")
	var x: float = rect.position.x
	var y: float = rect.position.y
	var w: float = rect.size.x
	var h: float = rect.size.y
	# A side shorter than door + corner jambs keeps its wall; the long sides open.
	if h - t * 2.0 - 52.0 < door:
		open = [true, true, false, false]
	elif w - 60.0 < door:
		open = [false, false, true, true]
	for side in [0, 1]:
		var yy: float = y if side == 0 else y + h - t
		if open[side]:
			var at: float = roundf(r.randf_range(x + 30.0, x + w - 30.0 - door))
			_add_wall(g, b_id, Rect2(x, yy, at - x, t), color)
			_add_wall(g, b_id, Rect2(at + door, yy, x + w - at - door, t), color)
		else:
			_add_wall(g, b_id, Rect2(x, yy, w, t), color)
	for side in [2, 3]:
		var xx: float = x if side == 2 else x + w - t
		var y0: float = y + t
		var hh: float = h - t * 2.0
		if open[side]:
			var at2: float = roundf(r.randf_range(y0 + 26.0, y0 + hh - 26.0 - door))
			_add_wall(g, b_id, Rect2(xx, y0, t, at2 - y0), color)
			_add_wall(g, b_id, Rect2(xx, at2 + door, t, y0 + hh - at2 - door), color)
		else:
			_add_wall(g, b_id, Rect2(xx, y0, t, hh), color)
	# Larger buildings get one partition stub from a closed-off wall: it never
	# reaches more than 40 % across, so every room stays open at radius 30.
	if w >= 330.0 and w >= h and not (open[0] and open[1]):
		var top: bool = not open[0]
		var sx: float = roundf(r.randf_range(x + w * 0.38, x + w * 0.62))
		var sl: float = roundf((h - t * 2.0) * 0.38)
		_add_wall(g, b_id, Rect2(sx - 9.0, y + t if top else y + h - t - sl, 18.0, sl), color)
	elif h >= 330.0 and h > w and not (open[2] and open[3]):
		var left: bool = not open[2]
		var sy: float = roundf(r.randf_range(y + h * 0.38, y + h * 0.62))
		var sw: float = roundf((w - t * 2.0) * 0.38)
		_add_wall(g, b_id, Rect2(x + t if left else x + w - t - sw, sy - 9.0, sw, 18.0), color)
	g.buildings.append({"id": b_id, "x": x, "y": y, "w": w, "h": h})
	g.reserve(rect.grow(GAP), F_SOLID | F_BRUSH | F_HAZARD | F_PROP)
	var c: Vector2 = rect.get_center()
	if w * h >= 90000.0:
		for o in [Vector2(-0.2, -0.15), Vector2(0.2, -0.15), Vector2(0.0, 0.2)]:
			g.add_spot(c + Vector2(o.x * w, o.y * h), "building")
	else:
		for o in [Vector2(-0.18, 0.0), Vector2(0.18, 0.0)]:
			g.add_spot(c + Vector2(o.x * w, o.y * h), "building")


# Roofless ruin: every side alternates broken wall pieces and wide gaps.
static func _ruin_house(g: Gen, rect: Rect2, color: String) -> void:
	var r: RandomNumberGenerator = g.r
	var t: float = 26.0
	var b_id: String = g.uid("ruin")
	for side in 4:
		var horizontal: bool = side < 2
		var length: float = rect.size.x if horizontal else rect.size.y - t * 2.0
		var u: float = 0.0
		var solid: bool = r.randf() < 0.7
		while u < length - 1.0:
			var seg: float = minf(r.randf_range(50.0, 150.0) if solid else r.randf_range(132.0, 210.0), length - u)
			if solid and seg >= 24.0:
				var piece: Rect2
				if horizontal:
					var yy: float = rect.position.y if side == 0 else rect.end.y - t
					piece = Rect2(rect.position.x + u, yy, seg, t)
				else:
					var xx: float = rect.position.x if side == 2 else rect.end.x - t
					piece = Rect2(xx, rect.position.y + t + u, t, seg)
				_add_wall(g, b_id, _rect(piece.position.x, piece.position.y, piece.size.x, piece.size.y), color, "ruin")
			u += seg
			solid = not solid
	g.buildings.append({"id": b_id, "x": rect.position.x, "y": rect.position.y, "w": rect.size.x, "h": rect.size.y, "ruined": true})
	g.reserve(rect.grow(GAP + 4.0), F_SOLID | F_BRUSH | F_HAZARD | F_PROP)
	var c: Vector2 = rect.get_center()
	g.add_spot(c + Vector2(-rect.size.x * 0.18, 0.0), "ruin")
	g.add_spot(c + Vector2(rect.size.x * 0.18, 0.0), "ruin")


# Brush patch of overlapping canopy circles around c (Arena.forests). Returns
# the number of circles (0 when fewer than two fit).
static func _brush_patch(g: Gen, c: Vector2, n: int, rmin: float, rmax: float) -> int:
	if g.patches >= PATCH_MAX or g.forests.size() + 2 > BRUSH_MAX:
		return 0
	var circles: Array = []
	var box: Rect2 = Rect2(c, Vector2.ZERO)
	for k in n:
		if g.forests.size() + circles.size() >= BRUSH_MAX:
			break
		var rad: float = g.r.randf_range(rmin, rmax)
		var p: Vector2 = c
		if k > 0:
			p = c + Vector2.from_angle(g.r.randf() * TAU) * rad * g.r.randf_range(0.55, 0.85)
		var rect: Rect2 = _box(p, rad)
		if not g.inside(p, 40.0) or g.blocked(rect, F_BRUSH):
			continue
		circles.append({"x": roundf(p.x), "y": roundf(p.y), "radius": roundf(rad), "patch": g.patches})
		box = box.merge(rect)
	if circles.size() < 2:
		return 0
	g.forests.append_array(circles)
	g.reserve(box.grow(30.0), F_BRUSH)
	g.patches += 1
	return circles.size()


static func _haste_at(g: Gen, p: Vector2, rad: float, mult: float, duration: float) -> bool:
	if not g.inside(p, rad + 40.0) or g.blocked(_box(p, rad + 30.0), F_HAZARD | F_BARRIER):
		return false
	g.hazards.append(DeathmatchMapData._haste(g.uid("haste"), roundf(p.x), roundf(p.y), rad, mult, duration))
	g.reserve(_box(p, rad + 40.0), F_SOLID | F_BRUSH | F_HAZARD | F_PROP)
	return true


static func _fountain_at(g: Gen, p: Vector2, heal: float, cooldown: float) -> bool:
	if g.blocked(_box(p, 76.0 + 40.0), F_HAZARD):
		return false
	g.hazards.append(DeathmatchMapData._fountain(g.uid("spring"), roundf(p.x), roundf(p.y), heal, cooldown))
	g.reserve(_box(p, 76.0 + 50.0), F_CLEAR)
	return true


static func _wind_at(g: Gen, rect: Rect2, label: String, force: float, mask: int = F_SOLID | F_HAZARD | F_BARRIER) -> bool:
	if not g.inside(rect.position, 30.0) or not g.inside(rect.end, 30.0) or g.blocked(rect.grow(40.0), mask):
		return false
	var horizontal: bool = rect.size.x >= rect.size.y
	var dir: Vector2 = Vector2.RIGHT if horizontal else Vector2.DOWN
	if g.r.randf() < 0.5:
		dir = -dir
	var period: float = snappedf(g.r.randf_range(6.0, 9.0), 0.5)
	g.hazards.append({"id": g.uid("gust"), "label": label, "shape": "rect", "type": "wind",
		"x": rect.position.x, "y": rect.position.y, "w": rect.size.x, "h": rect.size.y,
		"period": period, "activeDuration": period, "phase": snappedf(g.r.randf_range(0.0, 4.0), 0.5),
		"directionA": {"x": dir.x, "y": dir.y}, "directionB": {"x": -dir.x, "y": -dir.y}, "force": force, "color": "#7acfc5"})
	g.reserve(rect.grow(20.0), F_SOLID | F_BRUSH | F_HAZARD | F_PROP)
	return true


# Horizontal gust lanes laid in the empty channels between spawn-lattice rows.
static func _channel_winds(g: Gen, n: int, label: String, lmin: float, lmax: float) -> void:
	var lat: Dictionary = g.lattice
	var row_h: float = float(lat.row_h)
	var base: float = float(lat.y0) + (lat.o as Vector2).y
	var placed: int = 0
	var tries: int = 0
	while placed < n and tries < 400:
		tries += 1
		var k: int = g.r.randi_range(-1, int((g.max_y - base) / row_h))
		var yc: float = base + (float(k) + 0.5) * row_h + g.r.randf_range(-40.0, 40.0)
		var length: float = roundf(g.r.randf_range(lmin, lmax))
		var thick: float = roundf(g.r.randf_range(160.0, 180.0))
		var x: float = g.r.randf_range(g.min_x + 60.0, g.max_x - 60.0 - length)
		if _wind_at(g, _rect(x, yc - thick * 0.5, length, thick), label, 72.0):
			placed += 1


static func _scatter_haste(g: Gen, n: int, rad: float, min_gap: float) -> void:
	var placed: int = 0
	var tries: int = 0
	while placed < n and tries < 260:
		tries += 1
		var p: Vector2 = Vector2(g.r.randf_range(g.min_x + 200.0, g.max_x - 200.0), g.r.randf_range(g.min_y + 200.0, g.max_y - 200.0))
		var far: bool = true
		for hz: Dictionary in g.hazards:
			if str(hz.type) == "haste" and p.distance_to(Vector2(float(hz.x), float(hz.y))) < min_gap:
				far = false
				break
		if far and not g.blocked(_box(p, rad + 140.0), F_BARRIER) and _haste_at(g, p, rad, 1.3, 1.6):
			placed += 1


# Up to n trunks within reach of c; a few extra tries per trunk.
static func _trees(g: Gen, c: Vector2, n: int, reach: float) -> void:
	var made: int = 0
	for _try in n * 3:
		if made >= n:
			return
		if _solid_circle(g, c + Vector2.from_angle(g.r.randf() * TAU) * g.r.randf_range(15.0, reach), g.r.randf_range(13.0, 19.0), "tree", "#4a3a2a", GAP, F_SOLID | F_HAZARD):
			made += 1


# Random brush patches until the map holds target canopy circles.
static func _brush_fill(g: Gen, target: int, rmin: float, rmax: float, trees: int = 0, tries: int = 900) -> void:
	var k: int = 0
	while g.forests.size() < target and k < tries:
		k += 1
		var p: Vector2 = Vector2(g.r.randf_range(g.min_x + 80.0, g.max_x - 80.0), g.r.randf_range(g.min_y + 80.0, g.max_y - 80.0))
		if _brush_patch(g, p, g.r.randi_range(2, 4), rmin, rmax) > 0 and trees > 0:
			_trees(g, p, g.r.randi_range(1, trees), 90.0)


# Rock formations (one to four overlapping boulders: a single solid blob, so
# no slit between them can trap a body) in clusters, until the map holds
# target obstacles. The ground between the clusters stays open.
static func _rock_fill(g: Gen, target: int, rmin: float, rmax: float, color: String, gap: float, spread: float = 300.0) -> void:
	var k: int = 0
	while g.obstacles.size() < target and k < 3000:
		k += 1
		var c: Vector2 = Vector2(g.r.randf_range(g.min_x + 120.0, g.max_x - 120.0), g.r.randf_range(g.min_y + 120.0, g.max_y - 120.0))
		if g.blocked(_box(c, 60.0), F_SOLID):
			continue
		var n: int = g.r.randi_range(2, 4)
		var made: int = 0
		for _try in n * 4:
			if made >= n or g.obstacles.size() >= target:
				break
			var p: Vector2 = c + Vector2.from_angle(g.r.randf() * TAU) * g.r.randf_range(0.0, spread)
			var size: int = mini(target - g.obstacles.size(), [1, 2, 2, 3, 3, 4][g.r.randi_range(0, 5)])
			if _formation(g, p, size, rmin, rmax, color, gap):
				made += 1


static func _formation(g: Gen, c: Vector2, n: int, rmin: float, rmax: float, color: String, gap: float) -> bool:
	var pts: Array[Vector2] = []
	var rads: Array[float] = []
	var box: Rect2 = Rect2()
	for k in n:
		var rad: float = roundf(g.r.randf_range(rmin, rmax))
		var p: Vector2 = c
		if k > 0:
			var j: int = g.r.randi_range(0, k - 1)
			p = pts[j] + Vector2.from_angle(g.r.randf() * TAU) * (rads[j] + rad) * g.r.randf_range(0.5, 0.75)
		p = p.round()
		pts.append(p)
		rads.append(rad)
		box = _box(p, rad) if k == 0 else box.merge(_box(p, rad))
	if not g.inside(box.position, 40.0) or not g.inside(box.end, 40.0) or g.blocked(box.grow(gap), F_SOLID):
		return false
	for k in n:
		g.obstacles.append(DeathmatchMapData._circle_solid(g.uid("rock"), pts[k].x, pts[k].y, rads[k], "pillar", color))
	g.reserve(box.grow(gap), F_SOLID | F_PROP | F_HAZARD)
	return true


# Compass name of a position relative to the map centre ("북서", "중앙", ...).
static func _dir_name(g: Gen, p: Vector2) -> String:
	var nx: float = (p.x - g.center.x) / (g.w * 0.5)
	var ny: float = (p.y - g.center.y) / (g.h * 0.5)
	var ns: String = "북" if ny < -0.3 else ("남" if ny > 0.3 else "")
	var ew: String = "서" if nx < -0.3 else ("동" if nx > 0.3 else "")
	if ns == "" and ew == "":
		return "중앙"
	return ns + ew


static func _mark(g: Gen, label: String, p: Vector2, radius: float, kind: String = "landmark") -> bool:
	if g.landmarks.size() >= LANDMARK_MAX or g.names.has(label):
		return false
	g.names[label] = true
	g.landmarks.append(DeathmatchMapData._landmark(g.uid("mark"), label, roundf(p.x), roundf(p.y), radius, kind))
	return true


static func _mark_dir(g: Gen, bases: Array, p: Vector2, radius: float, kind: String = "landmark") -> bool:
	var d: String = _dir_name(g, p)
	for base in bases:
		if _mark(g, "%s %s" % [d, base], p, radius, kind):
			return true
	return false


# ------------------------------------------------------------------ spawns

# Spawns on a hex lattice (step 832, rows 720 apart) whose offset is chosen
# among 16 seeded candidates for the most valid points; each point is then
# jittered by at most 10 px and gets a 256 px clearing nothing may occupy.
static func _spawn_lattice(g: Gen, ok: Callable) -> void:
	var row_h: float = SPAWN_STEP * sqrt(3.0) * 0.5
	var x0: float = g.min_x + SPAWN_EDGE
	var y0: float = g.min_y + SPAWN_EDGE
	var best: Array[Vector2] = []
	var best_o: Vector2 = Vector2.ZERO
	for _t in 16:
		var o: Vector2 = Vector2(g.r.randf() * SPAWN_STEP, g.r.randf() * row_h)
		var pts: Array[Vector2] = _lattice_points(g, o, ok)
		if pts.size() > best.size():
			best = pts
			best_o = o
	g.lattice = {"x0": x0, "y0": y0, "o": best_o, "step": SPAWN_STEP, "row_h": row_h}
	for p in best:
		var q: Vector2 = (p + Vector2(g.r.randf_range(-SPAWN_JITTER, SPAWN_JITTER), g.r.randf_range(-SPAWN_JITTER, SPAWN_JITTER))).round()
		if q.distance_to(g.center) < g.core_r + 48.0 or not ok.call(q):
			q = p.round()
		g.spawns.append(q)
		g.reserve(_box(q, SPAWN_CLEAR), F_CLEAR)
	# The zone starts at the map centre: keep it open ground.
	g.reserve(_box(g.center, 150.0), F_SOLID | F_HAZARD | F_PROP)


static func _lattice_points(g: Gen, o: Vector2, ok: Callable) -> Array[Vector2]:
	var row_h: float = SPAWN_STEP * sqrt(3.0) * 0.5
	var x0: float = g.min_x + SPAWN_EDGE
	var x1: float = g.max_x - SPAWN_EDGE
	var y1: float = g.max_y - SPAWN_EDGE
	var pts: Array[Vector2] = []
	var k: int = 0
	while true:
		var y: float = g.min_y + SPAWN_EDGE + o.y + float(k) * row_h
		if y > y1:
			break
		var x: float = x0 + fposmod(o.x + float(k % 2) * SPAWN_STEP * 0.5, SPAWN_STEP)
		while x <= x1:
			var p: Vector2 = Vector2(x, y)
			if p.distance_to(g.center) >= g.core_r + 48.0 and ok.call(p):
				pts.append(p)
			x += SPAWN_STEP
		k += 1
	return pts


# ------------------------------------------------------------------ metropolis

static func _metropolis(g: Gen) -> void:
	var r: RandomNumberGenerator = g.r
	var span_x: float = g.max_x - g.min_x
	var span_y: float = g.max_y - g.min_y
	var vx: Array = []
	var vw: Array = []
	for k in range(1, 8):
		var x: float = g.min_x + span_x * float(k) / 8.0
		if k != 4:
			x += r.randf_range(-70.0, 70.0)
		vx.append(roundf(x))
		vw.append(300.0 if k == 4 else roundf(r.randf_range(170.0, 200.0)))
	var hy: Array = []
	var hw: Array = []
	for k in range(1, 4):
		var y: float = g.min_y + span_y * float(k) / 4.0
		if k != 2:
			y += r.randf_range(-60.0, 60.0)
		hy.append(roundf(y))
		hw.append(300.0 if k == 2 else roundf(r.randf_range(170.0, 200.0)))
	var ring_w: float = 120.0
	var streets: Array = []
	for k in vx.size():
		streets.append(Rect2(float(vx[k]) - float(vw[k]) * 0.5, g.min_y, float(vw[k]), span_y))
	for k in hy.size():
		streets.append(Rect2(g.min_x, float(hy[k]) - float(hw[k]) * 0.5, span_x, float(hw[k])))
	var edges: Array = [Rect2(g.min_x, g.min_y, span_x, ring_w), Rect2(g.min_x, g.max_y - ring_w, span_x, ring_w),
		Rect2(g.min_x, g.min_y, ring_w, span_y), Rect2(g.max_x - ring_w, g.min_y, ring_w, span_y)]
	# Roads stay open: no solids or brush (haste, gusts and street props may
	# sit on them). The outskirts strip along the bounds may be overgrown.
	for rect: Rect2 in streets + edges:
		g.reserve(rect, F_SOLID | F_BRUSH if streets.has(rect) else F_SOLID)
		g.decor.append({"type": "road", "x": rect.position.x, "y": rect.position.y, "w": rect.size.x, "h": rect.size.y})
	_spawn_lattice(g, func(_p: Vector2) -> bool: return true)
	_fortress(g)
	var blocks: Array = []
	for j in 4:
		var y0: float = g.min_y + ring_w if j == 0 else float(hy[j - 1]) + float(hw[j - 1]) * 0.5
		var y1: float = g.max_y - ring_w if j == 3 else float(hy[j]) - float(hw[j]) * 0.5
		for i in 8:
			var x0: float = g.min_x + ring_w if i == 0 else float(vx[i - 1]) + float(vw[i - 1]) * 0.5
			var x1: float = g.max_x - ring_w if i == 7 else float(vx[i]) - float(vw[i]) * 0.5
			var core: bool = (i == 3 or i == 4) and (j == 1 or j == 2)
			blocks.append({"rect": Rect2(x0, y0, x1 - x0, y1 - y0), "i": i, "j": j, "type": "fortress" if core else ""})
	_districts(g, blocks)
	# Avenue haste along the central avenue and the cross boulevard.
	var y_h: float = g.min_y + 330.0
	while y_h < g.max_y - 330.0:
		if absf(y_h - g.center.y) > 790.0:
			_haste_at(g, Vector2(g.center.x, y_h), 96.0, 1.25, 1.8)
		y_h += 640.0
	var x_h: float = g.min_x + 340.0
	while x_h < g.max_x - 340.0:
		if absf(x_h - g.center.x) > 790.0:
			_haste_at(g, Vector2(x_h, g.center.y), 96.0, 1.25, 1.8)
		x_h += 700.0
	# Street gusts between the towers of two side streets.
	var lanes: Array = []
	for k in [0, 1, 2, 4, 5, 6]:
		for row in [0, 3]:
			for dy in [-160.0, 0.0, 160.0]:
				lanes.append([k, row, dy])
	_shuffle(r, lanes)
	var gusts: int = 0
	for lane: Array in lanes:
		if gusts >= 2:
			break
		var k2: int = int(lane[0])
		var yc: float = (blocks[int(lane[1]) * 8] as Dictionary).rect.get_center().y + float(lane[2])
		var gw: float = float(vw[k2]) - 34.0
		if _wind_at(g, _rect(float(vx[k2]) - gw * 0.5, yc - 280.0, gw, 560.0), "빌딩 돌풍", 70.0, F_HAZARD | F_PROP):
			gusts += 1
	var parks: int = 0
	var dense: int = 0
	for b: Dictionary in blocks:
		match str(b.type):
			"plaza":
				_plaza(g, b)
			"park":
				_park(g, b, parks < 3, parks < 4)
				parks += 1
			"ruin":
				_ruin_block(g, b)
			"dense":
				_dense(g, b, dense < 2)
				dense += 1
			_:
				_glacis(g, b)
	_street_props(g, streets)
	# Extra haste where side streets cross the outer avenues, until 21 hazards.
	var crossings: Array = []
	for k in vx.size():
		for m in [0, 2]:
			crossings.append(Vector2(float(vx[k]), float(hy[m])))
	_shuffle(r, crossings)
	for p: Vector2 in crossings:
		if g.hazards.size() >= 21:
			break
		_haste_at(g, p, 80.0, 1.2, 1.6)
	_brush_fill(g, r.randi_range(164, 196), 56.0, 86.0, 0, 1400)
	_scatter_haste(g, 21 - g.hazards.size(), 80.0, 700.0)
	_rock_fill(g, r.randi_range(540, 620), 16.0, 26.0, "#6a6256", GAP)
	_mark(g, "중앙 대로", Vector2(g.center.x, g.min_y + span_y * 0.2), 150.0, "lane")
	_mark(g, "횡단 대로", Vector2(g.min_x + span_x * 0.2, g.center.y), 150.0, "lane")


static func _districts(g: Gen, blocks: Array) -> void:
	var order: Array = []
	for k in blocks.size():
		if str(blocks[k].type) == "":
			order.append(k)
	_shuffle(g.r, order)
	# Three artillery plazas (beside the fortress, west, east) in different
	# block rows, on blocks whose open square clear of spawn clearings is at
	# least 420 px on a side.
	var rows_used: Dictionary = {}
	for want in [[3, 4], [0, 2], [5, 7]]:
		for k in order:
			var b: Dictionary = blocks[k]
			if str(b.type) != "" or int(b.i) < int(want[0]) or int(b.i) > int(want[1]) or rows_used.has(int(b.j)):
				continue
			var area: Rect2 = _carve(g, (b.rect as Rect2).grow(-46.0), 300.0)
			if area.size.x >= 420.0 and area.size.y >= 420.0:
				b.type = "plaza"
				rows_used[int(b.j)] = true
				break
	_pick_blocks(blocks, order, "park", 7)
	_pick_blocks(blocks, order, "ruin", 3)
	for k in order:
		if str(blocks[k].type) == "":
			blocks[k].type = "dense"


static func _pick_blocks(blocks: Array, order: Array, type: String, n: int) -> void:
	var count: int = 0
	for k in order:
		if count >= n:
			return
		var b: Dictionary = blocks[k]
		if str(b.type) != "":
			continue
		var touching: bool = false
		for other: Dictionary in blocks:
			if str(other.type) == type and absi(int(other.i) - int(b.i)) + absi(int(other.j) - int(b.j)) == 1:
				touching = true
				break
		if touching:
			continue
		b.type = type
		count += 1


# Central keep: four corner towers, a timed gate in the middle of every wall
# (one group, so they open and close together) and a permanent breach in each
# wall (pinwheel), so the courtyard stays reachable while the gates are shut.
static func _fortress(g: Gen) -> void:
	var c: Vector2 = g.center
	var half: float = 520.0
	var t: float = 36.0
	var tower: float = 112.0
	var gate_w: float = 164.0
	var breach: float = 156.0
	var stone: String = "#6b6456"
	var cycle: Dictionary = {"group": "A", "period": 18.0, "openDuration": 9.0, "warningDuration": 1.6, "phase": 0.0}
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var tc: Vector2 = c + Vector2(sx, sy) * (half - tower * 0.5)
			_add_wall(g, "fort_tower", _rect(tc.x - tower * 0.5, tc.y - tower * 0.5, tower, tower), stone)
	var inner: float = half - tower
	var breach_sign: Array = [-1.0, -1.0, 1.0, 1.0]
	for side in 4:
		var horizontal: bool = side % 2 == 0
		# Wall line position across the side (outer face aligned with the towers).
		var across: float = (c.y - half if side == 0 else c.y + half - t) if horizontal else (c.x + half - t if side == 1 else c.x - half)
		var base: float = c.x if horizontal else c.y
		var mid: float = (inner + gate_w * 0.5) * 0.5 * float(breach_sign[side])
		var spans: Array = [[-inner, -gate_w * 0.5], [gate_w * 0.5, inner]]
		for s: Array in spans:
			var a: float = float(s[0])
			var b: float = float(s[1])
			var pieces: Array = [[a, b]]
			if mid > a and mid < b:
				pieces = [[a, mid - breach * 0.5], [mid + breach * 0.5, b]]
			for pc: Array in pieces:
				var u0: float = base + float(pc[0])
				var u1: float = base + float(pc[1])
				if horizontal:
					_add_wall(g, "fort_wall", _rect(u0, across, u1 - u0, t), stone)
				else:
					_add_wall(g, "fort_wall", _rect(across, u0, t, u1 - u0), stone)
		var gate_rect: Rect2 = _rect(base - gate_w * 0.5, across, gate_w, t) if horizontal else _rect(across, base - gate_w * 0.5, t, gate_w)
		var gate: Dictionary = ArenaData._wall(g.uid("fort_gate"), gate_rect.position.x, gate_rect.position.y, gate_rect.size.x, gate_rect.size.y, "#b08850", "gate", "iron")
		gate["label"] = "요새 성문"
		gate["gate"] = cycle.duplicate()
		g.obstacles.append(gate)
		# Gate frames: no item spot inside, approaches stay clear.
		g.reserve(gate_rect.grow(44.0), F_SPOT)
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var pp: Vector2 = c + Vector2(sx, sy) * 205.0
			g.obstacles.append(DeathmatchMapData._circle_solid(g.uid("fort_pillar"), pp.x, pp.y, 28.0, "pillar", "#7a6e5c"))
			# Inner bastion: an L of two low walls facing the courtyard corner.
			var corner: Vector2 = c + Vector2(sx, sy) * 360.0
			_add_wall(g, "fort_bastion", _rect(corner.x - (110.0 if sx > 0.0 else 0.0), corner.y - 14.0, 110.0, 28.0), stone)
			_add_wall(g, "fort_bastion", _rect(corner.x - 14.0, corner.y - (110.0 if sy > 0.0 else 0.0), 28.0, 110.0), stone)
	for o in [Vector2(0, -120), Vector2(0, 120), Vector2(-120, 0), Vector2(120, 0), Vector2(-300, -300), Vector2(300, 300), Vector2(300, -300), Vector2(-300, 300)]:
		g.add_spot(c + o, "building")
	g.reserve(_box(c, half + 90.0), F_SOLID | F_BRUSH | F_HAZARD | F_PROP)
	g.buildings.append({"id": "fortress", "x": c.x - half, "y": c.y - half, "w": half * 2.0, "h": half * 2.0, "fortress": true})
	_mark(g, "중앙 성문 요새", c, half, "landmark")


# Leftover corners of the four fortress blocks: a little brush and rubble.
static func _glacis(g: Gen, b: Dictionary) -> void:
	var rect: Rect2 = (b.rect as Rect2).grow(-40.0)
	for k in 8:
		var p: Vector2 = rect.position + Vector2(g.r.randf() * rect.size.x, g.r.randf() * rect.size.y)
		if k < 4:
			_brush_patch(g, p, 3, 60.0, 84.0)
		else:
			_solid_circle(g, p, g.r.randf_range(14.0, 22.0), "pillar", "#6a6256", GAP)


# Largest sub-rectangle of area that keeps margin clear of every spawn clearing.
static func _carve(g: Gen, area: Rect2, min_side: float, margin: float = 24.0) -> Rect2:
	var parts: Array = [area]
	for p in g.spawns:
		var q: Rect2 = _box(p, SPAWN_CLEAR + margin)
		var next: Array = []
		for a: Rect2 in parts:
			if not a.intersects(q):
				next.append(a)
				continue
			for s: Rect2 in [Rect2(a.position.x, a.position.y, q.position.x - a.position.x, a.size.y),
					Rect2(q.end.x, a.position.y, a.end.x - q.end.x, a.size.y),
					Rect2(a.position.x, a.position.y, a.size.x, q.position.y - a.position.y),
					Rect2(a.position.x, q.end.y, a.size.x, a.end.y - q.end.y)]:
				if s.size.x >= min_side and s.size.y >= min_side:
					next.append(s)
		parts = next
	var best: Rect2 = Rect2()
	for a: Rect2 in parts:
		if a.get_area() > best.get_area():
			best = a
	return best


static func _plaza(g: Gen, b: Dictionary) -> void:
	var area: Rect2 = _carve(g, (b.rect as Rect2).grow(-46.0), 300.0)
	if area.size.x < 420.0 or area.size.y < 420.0 or g.blocked(area, F_HAZARD):
		b.type = "dense"
		_dense(g, b, false)
		return
	area = _rect(area.position.x, area.position.y, area.size.x, area.size.y)
	var c: Vector2 = area.get_center()
	var count: int = clampi(int(area.get_area() / 110000.0), 4, 6)
	g.hazards.append({"id": g.uid("barrage"), "label": "광장 포격", "shape": "rect", "type": "artillery",
		"x": area.position.x, "y": area.position.y, "w": area.size.x, "h": area.size.y,
		"period": snappedf(g.r.randf_range(11.0, 13.0), 0.5), "warningDuration": 2.0, "phase": snappedf(g.r.randf_range(0.0, 6.0), 0.5),
		"count": count, "radius": 88.0, "damage": 46.0, "school": "physical", "spread": 110.0, "color": "#ff8f6b"})
	for sx in [0.0, 1.0]:
		for sy in [0.0, 1.0]:
			var corner: Vector2 = area.position + Vector2(70.0 + sx * (area.size.x - 140.0), 70.0 + sy * (area.size.y - 140.0))
			_solid_circle(g, corner, 26.0, "pillar", "#857a68", GAP)
	g.reserve(area.grow(30.0), F_SOLID | F_BRUSH | F_HAZARD | F_PROP)
	for k in 3:
		g.add_spot(area.position + Vector2(g.r.randf_range(100.0, area.size.x - 100.0), g.r.randf_range(100.0, area.size.y - 100.0)), "plaza")
	_mark_dir(g, ["포격 광장", "광장"], c, minf(area.size.x, area.size.y) * 0.5, "plaza")


static func _park(g: Gen, b: Dictionary, fountain: bool, named: bool) -> void:
	var inner: Rect2 = (b.rect as Rect2).grow(-70.0)
	var c: Vector2 = inner.get_center()
	if fountain:
		for o in [Vector2.ZERO, Vector2(-0.25, 0.0), Vector2(0.25, 0.0), Vector2(0.0, -0.25), Vector2(0.0, 0.25)]:
			if _fountain_at(g, c + Vector2(o.x * inner.size.x, o.y * inner.size.y), 0.15, 20.0):
				break
	if g.r.randf() < 0.45:
		var pw: float = roundf(g.r.randf_range(200.0, 260.0))
		var ph: float = roundf(g.r.randf_range(110.0, 150.0))
		var pos: Vector2 = inner.position + Vector2(g.r.randf() * maxf(0.0, inner.size.x - pw), g.r.randf() * maxf(0.0, inner.size.y - ph))
		var pond: Rect2 = _rect(pos.x, pos.y, pw, ph)
		if not g.blocked(pond.grow(70.0), F_SOLID | F_HAZARD):
			_water(g, pond)
			g.reserve(pond.grow(50.0), F_SOLID | F_BRUSH | F_HAZARD | F_PROP | F_SPOT)
	var placed: Array[Vector2] = []
	var want: int = g.r.randi_range(6, 8)
	for _try in want * 6:
		if placed.size() >= want:
			break
		var p: Vector2 = inner.position + Vector2(g.r.randf() * inner.size.x, g.r.randf() * inner.size.y)
		var far: bool = true
		for q in placed:
			if p.distance_to(q) < 210.0:
				far = false
				break
		if not far:
			continue
		if _brush_patch(g, p, g.r.randi_range(3, 4), 62.0, 100.0) > 0:
			placed.append(p)
			_trees(g, p, g.r.randi_range(2, 4), 110.0)
			if g.r.randf() < 0.6:
				g.add_spot(p + Vector2(g.r.randf_range(-40.0, 40.0), g.r.randf_range(-40.0, 40.0)), "forest")
	if named:
		_mark_dir(g, ["공원", "숲 공원", "정원"], c, 300.0, "landmark")


static func _lots(g: Gen, rect: Rect2) -> Array:
	var halves: Array = _split(g, rect, rect.size.x >= rect.size.y)
	var lots: Array = []
	for hh: Rect2 in halves:
		var along_x: bool = hh.size.x >= hh.size.y
		var long_side: float = hh.size.x if along_x else hh.size.y
		if long_side >= 2.0 * 236.0 + 116.0 and g.r.randf() < 0.85:
			lots.append_array(_split(g, hh, along_x))
		else:
			lots.append(hh)
	return lots


static func _split(g: Gen, rect: Rect2, along_x: bool) -> Array:
	var alley: float = g.r.randf_range(104.0, 136.0)
	var length: float = rect.size.x if along_x else rect.size.y
	var cut: float = length * g.r.randf_range(0.45, 0.55)
	if along_x:
		return [Rect2(rect.position, Vector2(cut - alley * 0.5, rect.size.y)),
			Rect2(rect.position.x + cut + alley * 0.5, rect.position.y, length - cut - alley * 0.5, rect.size.y)]
	return [Rect2(rect.position, Vector2(rect.size.x, cut - alley * 0.5)),
		Rect2(rect.position.x, rect.position.y + cut + alley * 0.5, rect.size.x, length - cut - alley * 0.5)]


static func _lot_building(g: Gen, lot0: Rect2, color: String, ruined: bool) -> bool:
	var min_side: float = 226.0
	# A spawn clearing in the lot leaves a courtyard: build on the rest.
	var lot: Rect2 = _carve(g, lot0, min_side + 8.0, 20.0)
	if lot.size.x - 8.0 < min_side or lot.size.y - 8.0 < min_side:
		return false
	for k in 4:
		var shrink: float = 1.0 - 0.1 * float(k)
		var w: float = minf(clampf(lot.size.x * g.r.randf_range(0.86, 0.97) * shrink, min_side, lot.size.x - 8.0), 720.0)
		var h: float = minf(clampf(lot.size.y * g.r.randf_range(0.86, 0.97) * shrink, min_side, lot.size.y - 8.0), 560.0)
		var pos: Vector2 = lot.position + Vector2(g.r.randf_range(0.0, lot.size.x - w), g.r.randf_range(0.0, lot.size.y - h))
		var rect: Rect2 = _rect(pos.x, pos.y, w, h)
		if g.blocked(rect.grow(24.0), F_SOLID):
			continue
		if ruined:
			_ruin_house(g, rect, color)
		else:
			_house(g, rect, color)
		return true
	return false


static func _dense(g: Gen, b: Dictionary, named: bool) -> void:
	for lot: Rect2 in _lots(g, (b.rect as Rect2).grow(-20.0)):
		var roll: float = g.r.randf()
		if roll < 0.1 and g.count_type("mud") < 3 and _site(g, lot):
			continue
		if roll < 0.18 and _brush_patch(g, lot.get_center(), g.r.randi_range(2, 4), 60.0, 86.0) > 0:
			continue
		if not _lot_building(g, lot, "#6b6456", false):
			_brush_patch(g, lot.get_center(), g.r.randi_range(2, 3), 60.0, 86.0)
	if named:
		_mark_dir(g, ["상가 구역", "주택가"], (b.rect as Rect2).get_center(), 340.0, "landmark")


# Construction site: a mud pit with two crates.
static func _site(g: Gen, lot: Rect2) -> bool:
	var rect: Rect2 = lot.grow(-40.0)
	if rect.size.x < 220.0 or rect.size.y < 180.0 or g.blocked(rect.grow(20.0), F_SOLID | F_HAZARD):
		return false
	rect = _rect(rect.position.x, rect.position.y, minf(rect.size.x, 420.0), minf(rect.size.y, 360.0))
	g.hazards.append({"id": g.uid("site_mud"), "label": "공사장 진흙", "shape": "rect", "type": "mud",
		"x": rect.position.x, "y": rect.position.y, "w": rect.size.x, "h": rect.size.y, "slow": 0.35, "color": "#7a5e3c"})
	_add_wall(g, "crate", _rect(rect.position.x + 34.0, rect.position.y + 34.0, 44.0, 44.0), "#6e5638", "wall", "wood")
	_add_wall(g, "crate", _rect(rect.end.x - 78.0, rect.end.y - 78.0, 44.0, 44.0), "#6e5638", "wall", "wood")
	g.reserve(rect.grow(30.0), F_SOLID | F_BRUSH | F_HAZARD | F_PROP)
	g.add_spot(rect.get_center(), "field")
	return true


static func _ruin_block(g: Gen, b: Dictionary) -> void:
	var rect: Rect2 = b.rect
	for lot: Rect2 in _lots(g, rect.grow(-20.0)):
		_lot_building(g, lot, "#5e574c", true)
	for _n in g.r.randi_range(6, 9):
		var p: Vector2 = rect.position + Vector2(g.r.randf() * rect.size.x, g.r.randf() * rect.size.y)
		_solid_circle(g, p, g.r.randf_range(14.0, 24.0), "pillar", "#6a6256", GAP)
	_mark_dir(g, ["폐허 구역", "무너진 거리"], rect.get_center(), 340.0, "landmark")


static func _street_props(g: Gen, streets: Array) -> void:
	for rect: Rect2 in streets:
		var vertical: bool = rect.size.y > rect.size.x
		var length: float = rect.size.y if vertical else rect.size.x
		var width: float = rect.size.x if vertical else rect.size.y
		for _n in int(length / 240.0):
			var along: float = g.r.randf_range(120.0, length - 120.0)
			var side: float = (width * 0.5 - 52.0) * (1.0 if g.r.randf() < 0.5 else -1.0)
			var p: Vector2 = rect.get_center() + (Vector2(side, along - length * 0.5) if vertical else Vector2(along - length * 0.5, side))
			var rad: float = g.r.randf_range(16.0, 22.0)
			var foot: Rect2 = _box(p, rad + 50.0)
			if not g.inside(p, 60.0) or g.blocked(foot, F_HAZARD | F_PROP):
				continue
			g.obstacles.append(DeathmatchMapData._circle_solid(g.uid("prop"), roundf(p.x), roundf(p.y), roundf(rad), "pillar", "#6d665c"))
			g.reserve(foot, F_SOLID | F_PROP | F_HAZARD)


# ------------------------------------------------------------------ wildwood

static func _wildwood(g: Gen) -> void:
	var r: RandomNumberGenerator = g.r
	_river(g)
	_spawn_lattice(g, func(p: Vector2) -> bool: return not g.blocked(_box(p, SPAWN_CLEAR - 18.0), F_BARRIER))
	_bank_stones(g)
	_villages(g)
	_scatter_haste(g, 5, 100.0, 1100.0)
	_channel_winds(g, 3, "골짜기 바람", 760.0, 1000.0)
	_marshes(g, r.randi_range(4, 5))
	_scatter_haste(g, 21 - g.hazards.size(), 90.0, 700.0)
	_lodges(g, r.randi_range(8, 10))
	_forest_masses(g, r.randi_range(190, 210))
	_rock_fill(g, r.randi_range(540, 620), 18.0, 36.0, "#5c6e6e", GAP)


# Main river: five vertical runs joined by horizontal jogs, from the north edge
# to the south edge, kept clear of the centre. Every run (and every long jog)
# has one crossing: a narrow bridge or a wide mud ford. A tributary leaves one
# run for the nearer side edge.
static func _river(g: Gen) -> void:
	var r: RandomNumberGenerator = g.r
	var t: float = 160.0
	var n: int = 5
	var span_y: float = g.max_y - g.min_y
	var xs: Array = []
	var ys: Array = []
	for _try in 40:
		var x_start: float = g.w * 0.3 + r.randf_range(-220.0, 220.0)
		var x_end: float = g.w * 0.7 + r.randf_range(-220.0, 220.0)
		if r.randf() < 0.5:
			var tmp: float = x_start
			x_start = x_end
			x_end = tmp
		ys = [0.0]
		for k in range(1, n):
			ys.append(roundf(g.min_y + span_y * float(k) / float(n) + r.randf_range(-110.0, 110.0)))
		ys.append(g.h)
		# The middle run passes the centre 450-750 px to one side and its two
		# jogs stay at least 520 px above and below it.
		ys[2] = roundf(minf(float(ys[2]), g.center.y - r.randf_range(520.0, 640.0)))
		ys[3] = roundf(maxf(float(ys[3]), g.center.y + r.randf_range(520.0, 640.0)))
		var side: float = 1.0 if r.randf() < 0.5 else -1.0
		xs = []
		for k in n:
			var x: float = lerpf(x_start, x_end, float(k) / float(n - 1))
			if k > 0 and k < n - 1:
				x += r.randf_range(-260.0, 260.0)
			if k == 2:
				x = g.center.x + side * r.randf_range(450.0, 750.0)
			xs.append(roundf(x))
		for k in range(1, n):
			if k != 2 and absf(float(xs[k]) - float(xs[k - 1])) < 320.0:
				var s: float = signf(float(xs[k]) - float(xs[k - 1]))
				xs[k] = float(xs[k - 1]) + (s if s != 0.0 else 1.0) * 320.0
		var clear: bool = true
		for rect: Rect2 in _river_rects(xs, ys, t, g):
			if rect.grow(400.0).has_point(g.center):
				clear = false
		for x in xs:
			if float(x) < g.min_x + 600.0 or float(x) > g.max_x - 600.0:
				clear = false
		if clear:
			break
	var rects: Array = _river_rects(xs, ys, t, g)
	# Crossing per run (passage across a vertical piece) and per long jog.
	var crossings: Array = []
	for k in n:
		var lo: float = g.min_y + 420.0 if k == 0 else float(ys[k]) + 280.0
		var hi: float = g.max_y - 420.0 if k == n - 1 else float(ys[k + 1]) - 280.0
		if hi - lo >= 40.0:
			crossings.append({"rect": k, "at": roundf(r.randf_range(lo, hi)), "vertical": true})
	for k in n - 1:
		var a: float = minf(float(xs[k]), float(xs[k + 1]))
		var b: float = maxf(float(xs[k]), float(xs[k + 1]))
		if b - a >= 700.0:
			crossings.append({"rect": n + k, "at": roundf(r.randf_range(a + 280.0, b - 280.0)), "vertical": false})
	# Tributary toward the nearer side edge from a middle run.
	var trib: Rect2 = Rect2()
	var options: Array = []
	for k in [1, 2, 3]:
		var x: float = float(xs[k])
		if x - g.min_x >= 1500.0 and x < g.center.x:
			options.append([k, -1.0])
		if g.max_x - x >= 1500.0 and x > g.center.x:
			options.append([k, 1.0])
	_shuffle(r, options)
	for opt: Array in options:
		var k: int = int(opt[0])
		var lo2: float = float(ys[k]) + 330.0
		var hi2: float = float(ys[k + 1]) - 330.0
		var run_cross: float = -1.0e9
		for cr: Dictionary in crossings:
			if int(cr.rect) == k:
				run_cross = float(cr.at)
		for _try in 12:
			if hi2 <= lo2:
				break
			var ty: float = roundf(r.randf_range(lo2, hi2))
			if absf(ty - run_cross) < 430.0 or absf(ty - g.center.y) < 520.0:
				continue
			var x_run: float = float(xs[k])
			if float(opt[1]) < 0.0:
				trib = Rect2(0.0, ty - 60.0, x_run - t * 0.5 + 4.0, 120.0)
			else:
				trib = Rect2(x_run + t * 0.5 - 4.0, ty - 60.0, g.w - (x_run + t * 0.5 - 4.0), 120.0)
			break
		if trib.size.x > 0.0:
			break
	if trib.size.x > 0.0:
		rects.append(trib)
		var length: float = trib.size.x
		var m: int = maxi(1, int(length / 1100.0))
		for j in m:
			var at: float = trib.position.x + length * (float(j) + 0.5) / float(m) + r.randf_range(-120.0, 120.0)
			at = clampf(at, trib.position.x + 320.0, trib.end.x - 320.0)
			crossings.append({"rect": rects.size() - 1, "at": roundf(at), "vertical": false, "tributary": true})
		g.decor.append({"type": "tributary", "x": trib.position.x, "y": trib.position.y, "w": trib.size.x, "h": trib.size.y})
	# Crossing kinds: two fords, the rest bridges (the one nearest the centre is a bridge).
	var order: Array = range(crossings.size())
	_shuffle(r, order)
	var nearest: int = -1
	var best_d: float = INF
	for i in crossings.size():
		var cp: Vector2 = _crossing_point(crossings[i], rects)
		if cp.distance_to(g.center) < best_d:
			best_d = cp.distance_to(g.center)
			nearest = i
	var fords: int = 0
	for i: int in order:
		var cr2: Dictionary = crossings[i]
		cr2["kind"] = "bridge"
		if i != nearest and fords < 2:
			cr2["kind"] = "ford"
			fords += 1
	# Water pieces split at the crossings.
	var pieces: Array = []
	for i in rects.size():
		var rect: Rect2 = rects[i]
		var cuts: Array = []
		for cr3: Dictionary in crossings:
			if int(cr3.rect) == i:
				var gap: float = r.randf_range(156.0, 172.0) if str(cr3.kind) == "bridge" else r.randf_range(280.0, 340.0)
				cr3["gap"] = roundf(gap)
				cuts.append([float(cr3.at) - gap * 0.5, float(cr3.at) + gap * 0.5])
		cuts.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
		var vertical: bool = rect.size.y > rect.size.x
		var u0: float = rect.position.y if vertical else rect.position.x
		var u_end: float = rect.end.y if vertical else rect.end.x
		for cut: Array in cuts + [[u_end, u_end]]:
			var u1: float = float(cut[0])
			if u1 - u0 >= 8.0:
				var piece: Rect2 = _rect(rect.position.x, u0, rect.size.x, u1 - u0) if vertical else _rect(u0, rect.position.y, u1 - u0, rect.size.y)
				pieces.append(piece)
			u0 = float(cut[1])
	# Solids keep GAP + 50 px from the water, so a 30 px body passes between.
	for piece: Rect2 in pieces:
		_water(g, piece)
		g.reserve(piece.grow(50.0), F_SOLID | F_BRUSH | F_PROP | F_BARRIER)
	g.decor.append({"type": "river", "xs": xs.duplicate(), "ys": ys.duplicate(), "width": t})
	_mark(g, "굽이강", Vector2(float(xs[1]), (float(ys[1]) + float(ys[2])) * 0.5), 200.0, "lane")
	if trib.size.x > 0.0:
		_mark(g, "샛강", trib.get_center(), 200.0, "lane")
	# Crossing furniture: bridge posts, ford mud, clear approaches, names.
	var named: int = 0
	for i in crossings.size():
		var cr4: Dictionary = crossings[i]
		var rect2: Rect2 = rects[int(cr4.rect)]
		var vertical2: bool = rect2.size.y > rect2.size.x
		var gap2: float = float(cr4.gap)
		var cp2: Vector2 = _crossing_point(cr4, rects)
		var thick: float = rect2.size.x if vertical2 else rect2.size.y
		# Passage rectangle through the water.
		var passage: Rect2 = Rect2(rect2.position.x, cp2.y - gap2 * 0.5, thick, gap2) if vertical2 else Rect2(cp2.x - gap2 * 0.5, rect2.position.y, gap2, thick)
		var approach: Rect2 = passage.grow_individual(240.0, 0.0, 240.0, 0.0) if vertical2 else passage.grow_individual(0.0, 240.0, 0.0, 240.0)
		g.reserve(approach, F_SOLID | F_BRUSH | F_PROP)
		if str(cr4.kind) == "bridge":
			for sx in [0.0, 1.0]:
				for sy in [0.0, 1.0]:
					var post: Vector2
					if vertical2:
						post = Vector2(passage.position.x + 12.0 + sx * (thick - 24.0), passage.position.y - 11.0 + sy * (gap2 + 22.0))
					else:
						post = Vector2(passage.position.x - 11.0 + sx * (gap2 + 22.0), passage.position.y + 12.0 + sy * (thick - 24.0))
					g.obstacles.append(DeathmatchMapData._circle_solid(g.uid("bridge_post"), roundf(post.x), roundf(post.y), 10.0, "post", "#7a6248"))
		else:
			var mud: Rect2 = passage.grow_individual(50.0, 0.0, 50.0, 0.0) if vertical2 else passage.grow_individual(0.0, 50.0, 0.0, 50.0)
			mud = _rect(mud.position.x, mud.position.y, mud.size.x, mud.size.y)
			g.hazards.append({"id": g.uid("ford"), "label": "진흙 여울", "shape": "rect", "type": "mud",
				"x": mud.position.x, "y": mud.position.y, "w": mud.size.x, "h": mud.size.y, "slow": 0.45, "color": "#7a5e3c"})
			g.reserve(mud, F_HAZARD)
		g.decor.append({"type": str(cr4.kind), "x": cp2.x, "y": cp2.y})
		if i == nearest:
			_mark(g, "중앙 대교", cp2, 180.0, "lane")
		elif named < 3:
			if _mark_dir(g, ["다리", "옛 다리"] if str(cr4.kind) == "bridge" else ["여울", "얕은 여울"], cp2, 160.0, "lane"):
				named += 1


static func _river_rects(xs: Array, ys: Array, t: float, g: Gen) -> Array:
	var out: Array = []
	var n: int = xs.size()
	for k in n:
		var y0: float = 0.0 if k == 0 else float(ys[k]) - t * 0.5
		var y1: float = g.h if k == n - 1 else float(ys[k + 1]) + t * 0.5
		out.append(Rect2(float(xs[k]) - t * 0.5, y0, t, y1 - y0))
	for k in n - 1:
		var a: float = minf(float(xs[k]), float(xs[k + 1])) - t * 0.5
		var b: float = maxf(float(xs[k]), float(xs[k + 1])) + t * 0.5
		out.append(Rect2(a, float(ys[k + 1]) - t * 0.5, b - a, t))
	return out


static func _crossing_point(cr: Dictionary, rects: Array) -> Vector2:
	var rect: Rect2 = rects[int(cr.rect)]
	if rect.size.y > rect.size.x:
		return Vector2(rect.get_center().x, float(cr.at))
	return Vector2(float(cr.at), rect.get_center().y)


static func _villages(g: Gen) -> void:
	var names: Array = ["참나무 마을", "이끼 마을", "솔바람 마을", "사슴 마을", "부엉이 마을", "여우 마을"]
	_shuffle(g.r, names)
	var centers: Array[Vector2] = []
	var want: int = g.r.randi_range(4, 5)
	var tries: int = 0
	while centers.size() < want and tries < 400:
		tries += 1
		var p: Vector2 = Vector2(g.r.randf_range(g.min_x + 560.0, g.max_x - 560.0), g.r.randf_range(g.min_y + 520.0, g.max_y - 520.0)).round()
		if p.distance_to(g.center) < 650.0 or g.blocked(_box(p, 470.0), F_BARRIER) or g.blocked(_box(p, 130.0), F_HAZARD):
			continue
		var far: bool = true
		for q in centers:
			if p.distance_to(q) < 1500.0:
				far = false
				break
		if not far:
			continue
		centers.append(p)
		_fountain_at(g, p, 0.16, 18.0)
		var n: int = g.r.randi_range(4, 5)
		var a0: float = g.r.randf() * TAU
		for k in n:
			for _try in 4:
				var a: float = a0 + TAU * float(k) / float(n) + g.r.randf_range(-0.3, 0.3)
				# Square footprints: diagonal cabins stand further out than axial ones.
				var cc: Vector2 = p + Vector2.from_angle(a) * (330.0 + 140.0 * absf(sin(2.0 * a)) + g.r.randf_range(0.0, 40.0))
				var cw: float = roundf(g.r.randf_range(250.0, 300.0))
				var ch: float = roundf(g.r.randf_range(250.0, 290.0))
				var rect: Rect2 = _rect(cc.x - cw * 0.5, cc.y - ch * 0.5, cw, ch)
				if g.inside(rect.position, 40.0) and g.inside(rect.end, 40.0) and not g.blocked(rect.grow(GAP), F_SOLID):
					_house(g, rect, "#6e5a44")
					break
		# Garden fences (bodies only; sight and shots pass) between the cabins.
		for k in n:
			var a2: float = a0 + TAU * (float(k) + 0.5) / float(n)
			var fc: Vector2 = p + Vector2.from_angle(a2) * 420.0
			var horizontal: bool = absf(cos(a2)) < 0.7
			var fr: Rect2 = _rect(fc.x - (90.0 if horizontal else 9.0), fc.y - (9.0 if horizontal else 90.0), 180.0 if horizontal else 18.0, 18.0 if horizontal else 180.0)
			if g.inside(fr.position, 60.0) and g.inside(fr.end, 60.0) and not g.blocked(fr.grow(50.0), F_SOLID | F_HAZARD):
				g.obstacles.append(ArenaData._screen(g.uid("fence"), fr.position.x, fr.position.y, fr.size.x, fr.size.y, "#8a7350", "hedge"))
				g.reserve(fr.grow(50.0), F_SOLID | F_PROP | F_HAZARD)
		g.reserve(_box(p, 250.0), F_BRUSH)
		g.add_spot(p + Vector2(0.0, 150.0), "field")
		_mark(g, str(names[centers.size() - 1]), p, 420.0, "supply")


# Hunters' lodges: lone cabins in the woods, away from the river and villages.
static func _lodges(g: Gen, n: int) -> void:
	var placed: int = 0
	var tries: int = 0
	while placed < n and tries < 300:
		tries += 1
		var cw: float = roundf(g.r.randf_range(250.0, 300.0))
		var ch: float = roundf(g.r.randf_range(250.0, 290.0))
		var pos: Vector2 = Vector2(g.r.randf_range(g.min_x + 100.0, g.max_x - 100.0 - cw), g.r.randf_range(g.min_y + 100.0, g.max_y - 100.0 - ch))
		var rect: Rect2 = _rect(pos.x, pos.y, cw, ch)
		if g.blocked(rect.grow(50.0), F_SOLID | F_HAZARD | F_BARRIER):
			continue
		_house(g, rect, "#6e5a44")
		if placed == 0:
			_mark(g, "사냥꾼 오두막", rect.get_center(), 200.0, "supply")
		placed += 1


# Bank marshes: mud strips beside long river pieces.
static func _marshes(g: Gen, n: int) -> void:
	var waters: Array = []
	for o: Dictionary in g.obstacles:
		if str(o.get("material", "")) == "water" and maxf(float(o.w), float(o.h)) >= 560.0:
			waters.append(Rect2(float(o.x), float(o.y), float(o.w), float(o.h)))
	_shuffle(g.r, waters)
	var placed: int = 0
	for wr: Rect2 in waters:
		if placed >= n:
			break
		var vertical: bool = wr.size.y > wr.size.x
		var length: float = wr.size.y if vertical else wr.size.x
		var along: float = roundf(g.r.randf_range(260.0, minf(420.0, length - 160.0)))
		var across: float = roundf(g.r.randf_range(140.0, 200.0))
		var side: float = 1.0 if g.r.randf() < 0.5 else -1.0
		var rect: Rect2
		if vertical:
			var x: float = wr.end.x if side > 0.0 else wr.position.x - across
			rect = _rect(x, wr.get_center().y - along * 0.5, across, along)
		else:
			var y: float = wr.end.y if side > 0.0 else wr.position.y - across
			rect = _rect(wr.get_center().x - along * 0.5, y, along, across)
		if not g.inside(rect.position, 20.0) or not g.inside(rect.end, 20.0) or g.blocked(rect.grow(10.0), F_HAZARD):
			continue
		var stony: bool = false
		for o2: Dictionary in g.obstacles:
			if str(o2.get("shape", "")) == "circle" and rect.grow(float(o2.radius) + 8.0).has_point(Vector2(float(o2.x), float(o2.y))):
				stony = true
				break
		if stony:
			continue
		g.hazards.append({"id": g.uid("marsh"), "label": "강변 늪", "shape": "rect", "type": "mud",
			"x": rect.position.x, "y": rect.position.y, "w": rect.size.x, "h": rect.size.y, "slow": 0.4, "color": "#6f5a3a"})
		g.reserve(rect, F_SOLID | F_HAZARD | F_PROP)
		placed += 1


# Stones half-sunk into the river banks, never near a crossing or a hazard.
static func _bank_stones(g: Gen) -> void:
	var crossings: Array[Vector2] = []
	for d: Dictionary in g.decor:
		if str(d.type) == "bridge" or str(d.type) == "ford":
			crossings.append(Vector2(float(d.x), float(d.y)))
	var waters: Array = []
	for o: Dictionary in g.obstacles:
		if str(o.get("material", "")) == "water":
			waters.append(Rect2(float(o.x), float(o.y), float(o.w), float(o.h)))
	for wr: Rect2 in waters:
		var vertical: bool = wr.size.y > wr.size.x
		var length: float = wr.size.y if vertical else wr.size.x
		var half: float = (wr.size.x if vertical else wr.size.y) * 0.5
		var c: Vector2 = wr.get_center()
		var u: float = g.r.randf_range(60.0, 160.0)
		while u < length - 60.0:
			var rad: float = g.r.randf_range(16.0, 26.0)
			var off: float = (half + rad - 8.0) * (1.0 if g.r.randf() < 0.5 else -1.0)
			var pos: Vector2 = Vector2(c.x + off, wr.position.y + u) if vertical else Vector2(wr.position.x + u, c.y + off)
			u += g.r.randf_range(170.0, 300.0)
			var near: bool = false
			for q in crossings:
				if pos.distance_to(q) < 250.0:
					near = true
					break
			if near or not g.inside(pos, rad + 30.0) or g.blocked(_box(pos, rad + 14.0), F_HAZARD):
				continue
			g.obstacles.append(DeathmatchMapData._circle_solid(g.uid("bank_stone"), roundf(pos.x), roundf(pos.y), roundf(rad), "pillar", "#62717a"))
			g.reserve(_box(pos, rad + GAP), F_SOLID | F_PROP | F_HAZARD)


static func _forest_masses(g: Gen, target: int) -> void:
	var masses: Array[Vector2] = []
	var tries: int = 0
	while masses.size() < 15 and tries < 400:
		tries += 1
		var p: Vector2 = Vector2(g.r.randf_range(g.min_x + 300.0, g.max_x - 300.0), g.r.randf_range(g.min_y + 300.0, g.max_y - 300.0))
		if g.blocked(_box(p, 220.0), F_BARRIER | F_HAZARD):
			continue
		var far: bool = true
		for q in masses:
			if p.distance_to(q) < 780.0:
				far = false
				break
		if far:
			masses.append(p)
	var named: int = 0
	for m in masses:
		if g.forests.size() >= target:
			break
		var made: int = 0
		var want: int = g.r.randi_range(3, 5)
		for _try in want * 5:
			if made >= want or g.forests.size() >= target:
				break
			var pc: Vector2 = m + Vector2.from_angle(g.r.randf() * TAU) * g.r.randf_range(0.0, 400.0)
			if _brush_patch(g, pc, 4, 100.0, 140.0) == 0:
				continue
			made += 1
			_trees(g, pc, g.r.randi_range(3, 6), 170.0)
			if g.r.randf() < 0.3:
				var horizontal: bool = g.r.randf() < 0.5
				var ll: float = roundf(g.r.randf_range(130.0, 180.0))
				var lp: Vector2 = pc + Vector2.from_angle(g.r.randf() * TAU) * 90.0
				var log_rect: Rect2 = _rect(lp.x - (ll * 0.5 if horizontal else 11.0), lp.y - (11.0 if horizontal else ll * 0.5), ll if horizontal else 22.0, 22.0 if horizontal else ll)
				if g.inside(log_rect.position, 60.0) and g.inside(log_rect.end, 60.0) and not g.blocked(log_rect.grow(46.0), F_SOLID):
					var lg: Dictionary = ArenaData._wall(g.uid("log"), log_rect.position.x, log_rect.position.y, log_rect.size.x, log_rect.size.y, "#5a4330", "tree", "wood")
					lg["blocksVision"] = false
					g.obstacles.append(lg)
					g.reserve(log_rect.grow(GAP), F_SOLID | F_PROP | F_HAZARD)
			if g.r.randf() < 0.45:
				g.add_spot(pc + Vector2(g.r.randf_range(-50.0, 50.0), g.r.randf_range(-50.0, 50.0)), "forest")
		if made >= 3 and named < 3 and _mark_dir(g, ["큰 숲", "깊은 숲", "고목 숲"], m, 480.0, "landmark"):
			named += 1
	_brush_fill(g, target, 80.0, 120.0, 3)


# ------------------------------------------------------------------ highland

static func _highland(g: Gen) -> void:
	var r: RandomNumberGenerator = g.r
	_spawn_lattice(g, func(_p: Vector2) -> bool: return true)
	var lines: Dictionary = _ridge_lines(g)
	var pieces: Array = []
	var xv: Array = lines.v
	var yh: Array = lines.h
	var labels: Array = [["북쪽 능선 고개", "남쪽 능선 고개"], ["서쪽 능선 고개", "동쪽 능선 고개"]]
	for k in yh.size():
		pieces.append_array(_ridge_line(g, true, float(yh[k]), xv, str(labels[0][k])))
	for k in xv.size():
		pieces.append_array(_ridge_line(g, false, float(xv[k]), yh, str(labels[1][k])))
	_ridge_pads(g, pieces, r.randi_range(5, 6))
	_outcrops(g, pieces)
	_channel_winds(g, 5, "고원 돌풍", 760.0, 1100.0)
	_temple(g)
	_henges(g, 3)
	_ruin_sites(g, xv, yh)
	_scatter_haste(g, 3, 100.0, 1400.0)
	_scatter_haste(g, 21 - g.hazards.size(), 90.0, 900.0)
	var houses: int = 0
	var tries: int = 0
	while houses < 14 and tries < 500:
		tries += 1
		var hw: float = roundf(r.randf_range(260.0, 320.0))
		var hh: float = roundf(r.randf_range(240.0, 300.0))
		var pos: Vector2 = Vector2(r.randf_range(g.min_x + 120.0, g.max_x - 120.0 - hw), r.randf_range(g.min_y + 120.0, g.max_y - 120.0 - hh))
		var rect: Rect2 = _rect(pos.x, pos.y, hw, hh)
		if g.blocked(rect.grow(50.0), F_SOLID | F_HAZARD):
			continue
		_ruin_house(g, rect, "#77705f")
		houses += 1
	_fragments(g, r.randi_range(30, 36))
	_brush_fill(g, r.randi_range(170, 200), 70.0, 104.0)
	_rock_fill(g, r.randi_range(540, 610), 18.0, 40.0, "#5c6e6e", GAP)


# Ridge lines run in the empty channels of the spawn lattice: horizontal lines
# midway between two lattice rows, vertical lines midway between the columns
# (points of alternate rows are 416 px apart), so no spawn is dropped.
static func _ridge_lines(g: Gen) -> Dictionary:
	var lat: Dictionary = g.lattice
	var o: Vector2 = lat.o
	var row_h: float = float(lat.row_h)
	var half_step: float = float(lat.step) * 0.5
	var span_x: float = g.max_x - g.min_x
	var span_y: float = g.max_y - g.min_y
	var hs: Array = []
	for want in [0.3, 0.7]:
		var target: float = g.min_y + span_y * float(want) + g.r.randf_range(-120.0, 120.0)
		var k: float = roundf((target - float(lat.y0) - o.y) / row_h - 0.5)
		hs.append(roundf(float(lat.y0) + o.y + (k + 0.5) * row_h))
	var phase: float = float(lat.x0) + fposmod(o.x, half_step)
	var vs: Array = []
	for want2 in [0.3, 0.7]:
		var target2: float = g.min_x + span_x * float(want2) + g.r.randf_range(-120.0, 120.0)
		var j: float = roundf((target2 - phase) / half_step - 0.5)
		vs.append(roundf(phase + (j + 0.5) * half_step))
	return {"h": hs, "v": vs}


# One broken ridge: horizontal lines leave a 420 px gap where a vertical line
# crosses them (two 178 px slots beside it); every line gets one pass in its
# middle section and, half the time, one in each outer section.
static func _ridge_line(g: Gen, horizontal: bool, at: float, crosses: Array, pass_label: String) -> Array:
	var span: float = (g.max_x - g.min_x) if horizontal else (g.max_y - g.min_y)
	var lo: float = (g.min_x if horizontal else g.min_y) + span * 0.09
	var hi: float = (g.max_x if horizontal else g.max_y) - span * 0.09
	var cs: Array = crosses.duplicate()
	cs.sort()
	var gaps: Array = []
	if horizontal:
		for c in cs:
			gaps.append([float(c) - 210.0, float(c) + 210.0])
	var sections: Array = [[lo, float(cs[0]) - 210.0, false], [float(cs[0]) + 210.0, float(cs[1]) - 210.0, true], [float(cs[1]) + 210.0, hi, false]]
	for s: Array in sections:
		var a: float = float(s[0]) + 300.0
		var b: float = float(s[1]) - 300.0
		var middle: bool = bool(s[2])
		if b <= a or (not middle and g.r.randf() < 0.45):
			continue
		var width: float = roundf(g.r.randf_range(250.0, 320.0))
		var u: float = roundf(g.r.randf_range(a, b))
		gaps.append([u - width * 0.5, u + width * 0.5])
		var pass_pt: Vector2 = Vector2(u, at) if horizontal else Vector2(at, u)
		var corridor: Rect2 = Rect2(u - width * 0.5, at - 250.0, width, 500.0) if horizontal else Rect2(at - 250.0, u - width * 0.5, 500.0, width)
		g.reserve(corridor, F_SOLID | F_BRUSH | F_PROP)
		if middle:
			_mark(g, pass_label, pass_pt, 150.0, "lane")
	gaps.sort_custom(func(p: Array, q: Array) -> bool: return float(p[0]) < float(q[0]))
	var pieces: Array = []
	var u0: float = lo
	for gp: Array in gaps + [[hi, hi]]:
		var u1: float = float(gp[0])
		if u1 - u0 >= 140.0:
			var rect: Rect2 = _rect(u0, at - 32.0, u1 - u0, 64.0) if horizontal else _rect(at - 32.0, u0, 64.0, u1 - u0)
			_add_wall(g, "ridge", rect, "#586c79")
			g.reserve(rect.grow(64.0), F_SOLID | F_BRUSH | F_PROP | F_BARRIER)
			pieces.append({"rect": rect, "horizontal": horizontal})
		u0 = maxf(u0, float(gp[1]))
	g.decor.append({"type": "ridge_line", "horizontal": horizontal, "at": at})
	return pieces


# Jump-pad pairs over long ridge pieces: one pad on each face, launching over
# the ridge in opposite directions (DeathmatchMapData._jump_pad).
static func _ridge_pads(g: Gen, pieces: Array, pairs: int) -> void:
	var long: Array = []
	for p: Dictionary in pieces:
		var rect: Rect2 = p.rect
		if maxf(rect.size.x, rect.size.y) >= 640.0:
			long.append(p)
	_shuffle(g.r, long)
	var placed: int = 0
	for p: Dictionary in long:
		if placed >= pairs:
			break
		var rect: Rect2 = p.rect
		var horizontal: bool = bool(p.horizontal)
		var a: float = (rect.position.x if horizontal else rect.position.y) + 150.0
		var b: float = (rect.end.x if horizontal else rect.end.y) - 390.0
		if b <= a:
			continue
		var mid: float = rect.get_center().y if horizontal else rect.get_center().x
		var pads: Array = []
		for _try in 8:
			var u: float = roundf(g.r.randf_range(a, b))
			pads = []
			for k in 2:
				var s: float = -1.0 if k == 0 else 1.0
				var uk: float = u + 240.0 * float(k)
				var pad_across: float = mid + s * (32.0 + 110.0)
				var land_across: float = mid - s * (32.0 + 140.0)
				var pad: Vector2 = Vector2(uk, pad_across) if horizontal else Vector2(pad_across, uk)
				var land: Vector2 = Vector2(uk, land_across) if horizontal else Vector2(land_across, uk)
				pads.append([pad, land])
			for pl: Array in pads:
				if g.blocked(_box(pl[0], 36.0 + 34.0), F_HAZARD) or g.blocked(_box(pl[1], 56.0), F_HAZARD | F_SOLID):
					pads = []
					break
			if not pads.is_empty():
				break
		if pads.is_empty():
			continue
		for pl: Array in pads:
			var pad2: Vector2 = pl[0]
			var land2: Vector2 = pl[1]
			g.hazards.append(DeathmatchMapData._jump_pad(g.uid("ridge_pad"), pad2.x, pad2.y, land2.x, land2.y))
			g.reserve(_box(pad2, 36.0 + 44.0), F_CLEAR)
			g.reserve(_box(land2, 84.0), F_CLEAR)
		placed += 1


# Jagged ridge faces: boulders half-sunk into the long sides of every ridge
# piece, never into a pass, a pad or a landing (those reserve F_HAZARD).
static func _outcrops(g: Gen, pieces: Array) -> void:
	for p: Dictionary in pieces:
		var rect: Rect2 = p.rect
		var horizontal: bool = bool(p.horizontal)
		var length: float = rect.size.x if horizontal else rect.size.y
		var c: Vector2 = rect.get_center()
		var u: float = g.r.randf_range(50.0, 120.0)
		while u < length - 50.0:
			var rad: float = g.r.randf_range(18.0, 30.0)
			var off: float = (32.0 + rad - 10.0) * (1.0 if g.r.randf() < 0.5 else -1.0)
			var pos: Vector2 = Vector2(rect.position.x + u, c.y + off) if horizontal else Vector2(c.x + off, rect.position.y + u)
			u += g.r.randf_range(110.0, 180.0)
			if g.blocked(_box(pos, rad + 12.0), F_HAZARD):
				continue
			g.obstacles.append(DeathmatchMapData._circle_solid(g.uid("outcrop"), roundf(pos.x), roundf(pos.y), roundf(rad), "pillar", "#5f6f78"))
			g.reserve(_box(pos, rad + GAP), F_SOLID | F_PROP | F_HAZARD)


# Lone broken wall fragments (old field walls) scattered over the meadows.
static func _fragments(g: Gen, n: int) -> void:
	var placed: int = 0
	var tries: int = 0
	while placed < n and tries < 400:
		tries += 1
		var horizontal: bool = g.r.randf() < 0.5
		var length: float = roundf(g.r.randf_range(110.0, 240.0))
		var p: Vector2 = Vector2(g.r.randf_range(g.min_x + 200.0, g.max_x - 200.0), g.r.randf_range(g.min_y + 200.0, g.max_y - 200.0))
		var rect: Rect2 = _rect(p.x, p.y, length if horizontal else 26.0, 26.0 if horizontal else length)
		if g.blocked(rect.grow(70.0), F_SOLID | F_HAZARD):
			continue
		_add_wall(g, "fragment", rect, "#77705f", "ruin")
		g.reserve(rect.grow(56.0), F_SOLID | F_PROP | F_HAZARD)
		placed += 1


# Standing-stone circles in open meadows (eight stones, 105 px gaps).
static func _henges(g: Gen, n: int) -> void:
	var placed: int = 0
	var tries: int = 0
	while placed < n and tries < 200:
		tries += 1
		var c: Vector2 = Vector2(g.r.randf_range(g.min_x + 400.0, g.max_x - 400.0), g.r.randf_range(g.min_y + 400.0, g.max_y - 400.0)).round()
		if g.blocked(_box(c, 270.0), F_SOLID | F_HAZARD | F_BARRIER):
			continue
		var a0: float = g.r.randf() * TAU
		for k in 8:
			var p: Vector2 = c + Vector2.from_angle(a0 + TAU * float(k) / 8.0) * 190.0
			g.obstacles.append(DeathmatchMapData._circle_solid(g.uid("standing_stone"), roundf(p.x), roundf(p.y), roundf(g.r.randf_range(20.0, 24.0)), "pillar", "#7d7a70"))
		g.reserve(_box(c, 240.0), F_SOLID | F_BRUSH | F_HAZARD | F_PROP)
		g.add_spot(c, "ruin")
		_mark_dir(g, ["선돌 고리", "돌무지 고리"], c, 220.0, "landmark")
		placed += 1


# Central plateau temple: a broken pillar ring around the clear centre and
# four tangential wall fragments.
static func _temple(g: Gen) -> void:
	var c: Vector2 = g.center
	var n: int = 10
	var skip_a: int = g.r.randi_range(0, n - 1)
	var skip_b: int = (skip_a + 5) % n
	var a0: float = g.r.randf() * TAU
	for k in n:
		if k == skip_a or k == skip_b:
			continue
		var p: Vector2 = c + Vector2.from_angle(a0 + TAU * float(k) / float(n)) * 330.0
		if not g.blocked(_box(p, 24.0 + GAP), F_SOLID | F_HAZARD):
			g.obstacles.append(DeathmatchMapData._circle_solid(g.uid("temple_pillar"), roundf(p.x), roundf(p.y), 24.0, "pillar", "#8b8574"))
	# Wall fragments where nothing else (a pad, a gust lane, a ridge) stands.
	for k in 4:
		var d: Vector2 = Vector2.from_angle(PI * 0.5 * float(k)) * 640.0
		var horizontal: bool = k % 2 == 1
		var rect: Rect2 = _rect(c.x + d.x - (150.0 if horizontal else 15.0), c.y + d.y - (15.0 if horizontal else 150.0), 300.0 if horizontal else 30.0, 30.0 if horizontal else 300.0)
		if not g.blocked(rect.grow(GAP), F_SOLID | F_HAZARD):
			_add_wall(g, "temple_wall", rect, "#77705f", "ruin")
	for k in 6:
		g.add_spot(c + Vector2.from_angle(a0 + TAU * (float(k) + 0.5) / 6.0) * g.r.randf_range(170.0, 240.0), "ruin")
	g.reserve(_box(c, 700.0), F_SOLID | F_BRUSH | F_HAZARD | F_PROP)
	_mark(g, "고원 신전", c, 420.0, "landmark")


static func _ruin_sites(g: Gen, xv: Array, yh: Array) -> void:
	var xs: Array = [g.min_x, float(xv[0]), float(xv[1]), g.max_x]
	var ys: Array = [g.min_y, float(yh[0]), float(yh[1]), g.max_y]
	var regions: Array = []
	for j in 3:
		for i in 3:
			if i == 1 and j == 1:
				continue
			regions.append(Vector2((float(xs[i]) + float(xs[i + 1])) * 0.5, (float(ys[j]) + float(ys[j + 1])) * 0.5))
	_shuffle(g.r, regions)
	var names: Array = ["바람 신전 터", "부서진 열주", "옛 성채 터", "돌기둥 회랑", "무너진 사당", "달빛 제단", "용의 무덤"]
	_shuffle(g.r, names)
	var sites: int = 0
	for c0: Vector2 in regions:
		if sites >= 6:
			break
		var c: Vector2 = c0
		for _try in 12:
			var q: Vector2 = c0 + Vector2(g.r.randf_range(-260.0, 260.0), g.r.randf_range(-260.0, 260.0))
			if not g.blocked(_box(q, 200.0), F_BARRIER | F_HAZARD):
				c = q.round()
				break
		var label: String = str(names[sites])
		if sites < 3:
			_fountain_at(g, c, 0.16, 20.0)
		elif g.count_type("gravity") == 0 and _gravity_well(g, c):
			label = "중력 우물 유적"
		_ruin_site(g, c)
		_mark(g, label, c, 360.0, "landmark")
		sites += 1
	# The one gravity well: at a ruin site when one had room, else in the open.
	var tries: int = 0
	while g.count_type("gravity") == 0 and tries < 300:
		tries += 1
		var q2: Vector2 = Vector2(g.r.randf_range(g.min_x + 300.0, g.max_x - 300.0), g.r.randf_range(g.min_y + 300.0, g.max_y - 300.0)).round()
		if not g.blocked(_box(q2, 200.0), F_SOLID | F_BARRIER) and _gravity_well(g, q2):
			_mark(g, "중력 우물", q2, 200.0, "landmark")


static func _gravity_well(g: Gen, c: Vector2) -> bool:
	if g.blocked(_box(c, 190.0), F_HAZARD):
		return false
	g.hazards.append({"id": g.uid("well"), "label": "유적 중력 우물", "shape": "circle", "type": "gravity", "x": c.x, "y": c.y, "radius": 150.0,
		"period": 10.0, "activeDuration": 2.2, "warningDuration": 1.4, "phase": 3.0, "force": 135.0, "damage": 7.0, "tickInterval": 0.5,
		"school": "magic", "color": "#a78af4"})
	g.reserve(_box(c, 190.0), F_SOLID | F_HAZARD | F_PROP)
	return true


static func _ruin_site(g: Gen, c: Vector2) -> void:
	var r: RandomNumberGenerator = g.r
	var along_x: bool = r.randf() < 0.5
	var count: int = r.randi_range(5, 7)
	var spacing: float = 132.0
	var sep: float = 236.0
	var axis: Vector2 = Vector2.RIGHT if along_x else Vector2.DOWN
	var side: Vector2 = Vector2.DOWN if along_x else Vector2.RIGHT
	var shift: Vector2 = side * (r.randf_range(-1.0, 1.0) * 120.0 + 260.0 * (1.0 if r.randf() < 0.5 else -1.0))
	# Colonnade: two rows of pillars placed as one unit (bodies of radius 30
	# walk between the rows, not between the pillars of a row).
	var cols: Array[Vector2] = []
	var box: Rect2 = Rect2()
	for row in 2:
		for k in count:
			var p: Vector2 = (c + shift + axis * (float(k) - float(count - 1) * 0.5) * spacing + side * (float(row) - 0.5) * sep).round()
			cols.append(p)
			box = _box(p, 25.0) if cols.size() == 1 else box.merge(_box(p, 25.0))
	if g.inside(box.position, 60.0) and g.inside(box.end, 60.0) and not g.blocked(box.grow(GAP), F_SOLID | F_HAZARD):
		for p in cols:
			g.obstacles.append(DeathmatchMapData._circle_solid(g.uid("column"), p.x, p.y, roundf(r.randf_range(20.0, 25.0)), "pillar", "#8b8574"))
		g.reserve(box.grow(GAP), F_SOLID | F_PROP | F_HAZARD)
		g.add_spot(c + shift, "ruin")
		g.add_spot(c + shift + axis * spacing, "ruin")
	var hw: float = roundf(r.randf_range(280.0, 340.0))
	var hh: float = roundf(r.randf_range(240.0, 300.0))
	var hc: Vector2 = c - shift.normalized() * 380.0 + axis * r.randf_range(-160.0, 160.0)
	var house: Rect2 = _rect(hc.x - hw * 0.5, hc.y - hh * 0.5, hw, hh)
	if g.inside(house.position, 60.0) and g.inside(house.end, 60.0) and not g.blocked(house.grow(GAP), F_SOLID | F_HAZARD):
		_ruin_house(g, house, "#77705f")
	for _n in r.randi_range(4, 6):
		var p2: Vector2 = c + Vector2.from_angle(r.randf() * TAU) * r.randf_range(120.0, 420.0)
		_solid_circle(g, p2, r.randf_range(12.0, 20.0), "pillar", "#6f6a5e", GAP)


# ------------------------------------------------------------------ item spots

static func _spots(g: Gen, arena: Arena) -> Array:
	var out: Array = []
	var counts: Array = [0, 0, 0, 0]
	for cand: Dictionary in g.cands:
		_try_spot(g, arena, cand.pos, str(cand.kind), out, counts)
	for ring in 4:
		var lo: float = 0.0 if ring == 0 else float(RING_LIMITS[ring - 1]) * g.half_diag
		var hi: float = float(RING_LIMITS[ring]) * g.half_diag if ring < 3 else g.half_diag
		var tries: int = 0
		while int(counts[ring]) < int(RING_SPOT_TARGET[ring]) and tries < 900:
			tries += 1
			var rho: float = sqrt(lerpf(lo * lo, hi * hi, g.r.randf()))
			var p: Vector2 = g.center + Vector2.from_angle(g.r.randf() * TAU) * rho
			if not g.inside(p, 60.0):
				continue
			_try_spot(g, arena, p, "forest" if arena.forest_at(p) >= 0 else "field", out, counts)
	return out


static func _try_spot(g: Gen, arena: Arena, p0: Vector2, kind: String, out: Array, counts: Array) -> void:
	var p: Vector2 = p0.round()
	if not g.inside(p, 40.0) or g.blocked(_box(p, 32.0), F_SPOT) or not arena.is_walkable(p, SPOT_BODY):
		return
	var ring: int = ring_of(p, g.center, g.half_diag)
	out.append({"x": p.x, "y": p.y, "kind": kind, "ring": ring})
	counts[ring] = int(counts[ring]) + 1
	g.reserve(_box(p, 32.0), F_SPOT)


# ------------------------------------------------------------------ validation

# Hazards by type plus "gate" and "water" obstacles.
static func feature_counts(data: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for hz: Dictionary in data.get("hazards", []):
		out[str(hz.type)] = int(out.get(str(hz.type), 0)) + 1
	for o: Dictionary in data.get("obstacles", []):
		var key: String = "gate" if o.has("gate") else ("water" if str(o.get("material", "")) == "water" else "")
		if key != "":
			out[key] = int(out.get(key, 0)) + 1
	return out


# Anchors that must be reachable for every body: spawns, hazard centres,
# jump-pad landings and the map centre (the zone starts there).
static func anchor_points(data: Dictionary) -> Array:
	var out: Array = []
	var spawns: Array = data.get("ffa_spawns", [])
	for i in spawns.size():
		out.append({"label": "spawn %d" % i, "pos": Vector2(float(spawns[i].x), float(spawns[i].y))})
	for hz: Dictionary in data.get("hazards", []):
		var c: Vector2 = Vector2(float(hz.x), float(hz.y))
		if str(hz.get("shape", "rect")) != "circle":
			c += Vector2(float(hz.get("w", 0.0)), float(hz.get("h", 0.0))) * 0.5
		out.append({"label": "hazard %s" % str(hz.id), "pos": c})
		if hz.has("target"):
			out.append({"label": "landing %s" % str(hz.id), "pos": Vector2(float(hz.target.x), float(hz.target.y))})
	out.append({"label": "centre", "pos": Vector2(float(data.width) * 0.5, float(data.height) * 0.5)})
	return out


# Free runs of a navigator-style grid for one body bucket: cell (x, y) has its
# centre at (16x + 8, 16y + 8) and is solid exactly when Navigator._build would
# make it solid (bounds - bucket, Arena.inside_obstacle(c, bucket + 3) over the
# unit-blocking obstacles, gates closed). Runs are 4-connected through vertical
# overlap; comp[i] is the union-find root of run i, main the largest component.
static func run_grid(data: Dictionary, bucket: float) -> Dictionary:
	var cols: int = int(ceil(float(data.width) / CELL))
	var rows: int = int(ceil(float(data.height) / CELL))
	var b: Dictionary = data.bounds
	var pad: float = bucket + 3.0
	var cx0: int = maxi(0, int(ceil((float(b.minX) + bucket - CELL * 0.5) / CELL)))
	var cx1: int = mini(cols - 1, int(floor((float(b.maxX) - bucket - CELL * 0.5) / CELL)))
	var cy0: int = maxi(0, int(ceil((float(b.minY) + bucket - CELL * 0.5) / CELL)))
	var cy1: int = mini(rows - 1, int(floor((float(b.maxY) - bucket - CELL * 0.5) / CELL)))
	# Blocked interval per (row, obstacle), packed row << 32 | x0 << 16 | x1.
	var keys: PackedInt64Array = PackedInt64Array()
	for o: Dictionary in data.obstacles:
		if o.get("blocksUnits", true) == false:
			continue
		if str(o.get("shape", "rect")) == "circle":
			var ox: float = float(o.x)
			var oy: float = float(o.y)
			var big: float = float(o.radius) + pad
			var ya: int = maxi(cy0, int(ceil((oy - big - CELL * 0.5) / CELL)))
			var yb: int = mini(cy1, int(floor((oy + big - CELL * 0.5) / CELL)))
			for y in range(ya, yb + 1):
				var dy: float = float(y) * CELL + CELL * 0.5 - oy
				var hw2: float = big * big - dy * dy
				if hw2 < 0.0:
					continue
				var hw: float = sqrt(hw2)
				var xa: int = maxi(cx0, int(ceil((ox - hw - CELL * 0.5) / CELL)))
				var xb: int = mini(cx1, int(floor((ox + hw - CELL * 0.5) / CELL)))
				if xb >= xa:
					keys.append((y << 32) | (xa << 16) | xb)
		else:
			var rx: float = float(o.x)
			var ry: float = float(o.y)
			var xa2: int = maxi(cx0, int(ceil((rx - pad - CELL * 0.5) / CELL)))
			var xb2: int = mini(cx1, int(floor((rx + float(o.w) + pad - CELL * 0.5) / CELL)))
			var ya2: int = maxi(cy0, int(ceil((ry - pad - CELL * 0.5) / CELL)))
			var yb2: int = mini(cy1, int(floor((ry + float(o.h) + pad - CELL * 0.5) / CELL)))
			if xb2 < xa2:
				continue
			for y in range(ya2, yb2 + 1):
				keys.append((y << 32) | (xa2 << 16) | xb2)
	keys.sort()
	var run_x0: PackedInt32Array = PackedInt32Array()
	var run_x1: PackedInt32Array = PackedInt32Array()
	var row_start: PackedInt32Array = PackedInt32Array()
	row_start.resize(rows + 2)
	var k: int = 0
	var nk: int = keys.size()
	for y in rows:
		row_start[y] = run_x0.size()
		if y < cy0 or y > cy1:
			continue
		var cursor: int = cx0
		while k < nk and (keys[k] >> 32) == y:
			var a: int = int((keys[k] >> 16) & 0xFFFF)
			var e: int = int(keys[k] & 0xFFFF)
			if a > cursor:
				run_x0.append(cursor)
				run_x1.append(a - 1)
			cursor = maxi(cursor, e + 1)
			k += 1
		if cursor <= cx1:
			run_x0.append(cursor)
			run_x1.append(cx1)
	row_start[rows] = run_x0.size()
	row_start[rows + 1] = run_x0.size()
	var n: int = run_x0.size()
	var parent: PackedInt32Array = PackedInt32Array()
	parent.resize(n)
	for i in n:
		parent[i] = i
	for y in range(cy0, cy1):
		var i: int = row_start[y]
		var ie: int = row_start[y + 1]
		var j: int = row_start[y + 1]
		var je: int = row_start[y + 2]
		while i < ie and j < je:
			if run_x0[i] <= run_x1[j] and run_x0[j] <= run_x1[i]:
				# Union by smaller root with path halving.
				var ra: int = i
				while parent[ra] != ra:
					parent[ra] = parent[parent[ra]]
					ra = parent[ra]
				var rb: int = j
				while parent[rb] != rb:
					parent[rb] = parent[parent[rb]]
					rb = parent[rb]
				if ra != rb:
					parent[maxi(ra, rb)] = mini(ra, rb)
			if run_x1[i] < run_x1[j]:
				i += 1
			else:
				j += 1
	var comp: PackedInt32Array = PackedInt32Array()
	comp.resize(n)
	var sizes: Dictionary = {}
	var free: int = 0
	for i in n:
		var root: int = i
		while parent[root] != root:
			root = parent[root]
		parent[i] = root
		comp[i] = root
		var cells: int = run_x1[i] - run_x0[i] + 1
		sizes[root] = int(sizes.get(root, 0)) + cells
		free += cells
	var main: int = -1
	var main_size: int = 0
	for root in sizes:
		if int(sizes[root]) > main_size or (int(sizes[root]) == main_size and int(root) < main):
			main = int(root)
			main_size = int(sizes[root])
	return {"bucket": bucket, "cols": cols, "rows": rows, "row_start": row_start, "x0": run_x0, "x1": run_x1, "comp": comp,
		"main": main, "main_size": main_size, "free": free, "components": sizes.size()}


static func comp_at(grid: Dictionary, x: int, y: int) -> int:
	if y < 0 or y >= int(grid.rows):
		return -1
	var row_start: PackedInt32Array = grid.row_start
	var x0: PackedInt32Array = grid.x0
	var x1: PackedInt32Array = grid.x1
	for i in range(row_start[y], row_start[y + 1]):
		if x >= x0[i] and x <= x1[i]:
			return (grid.comp as PackedInt32Array)[i]
	return -1


# p is walkable for the bucket and links in a straight line to a cell of the
# main component (its own cell or one of the eight around it).
static func anchor_ok(arena: Arena, grid: Dictionary, p: Vector2, bucket: float) -> bool:
	if not arena.is_walkable(p, bucket):
		return false
	var gx: int = int(floor(p.x / CELL))
	var gy: int = int(floor(p.y / CELL))
	var main: int = int(grid.main)
	for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
		if comp_at(grid, gx + d.x, gy + d.y) != main:
			continue
		var c: Vector2 = Vector2(float(gx + d.x) * CELL + CELL * 0.5, float(gy + d.y) * CELL + CELL * 0.5)
		if not arena.segment_blocked(p, c, bucket, Arena.MASK_UNITS):
			return true
	return false


# Connectivity per bucket (30, 26, 18, 12): grid statistics, failing anchor
# labels and failing item-spot indices.
static func connectivity(data: Dictionary, arena: Arena = null) -> Array:
	var a: Arena = arena if arena != null else Arena.from_data(data)
	var anchors: Array = anchor_points(data)
	var spots: Array = data.get("item_spots", [])
	var out: Array = []
	var dead: Dictionary = {}
	for bucket in BUCKETS:
		var grid: Dictionary = run_grid(data, float(bucket))
		var bad: Array = []
		for an: Dictionary in anchors:
			if not anchor_ok(a, grid, an.pos, float(bucket)):
				bad.append(str(an.label))
		var spots_bad: Array = []
		for i in spots.size():
			if dead.has(i):
				spots_bad.append(i)
				continue
			if not anchor_ok(a, grid, Vector2(float(spots[i].x), float(spots[i].y)), float(bucket)):
				spots_bad.append(i)
				dead[i] = true
		out.append({"bucket": float(bucket), "free": grid.free, "main_size": grid.main_size, "components": grid.components,
			"anchors_bad": bad, "spots_bad": spots_bad})
	return out


static func _validate(data: Dictionary, arena: Arena) -> String:
	var counts: Dictionary = {"obstacles": (data.obstacles as Array).size(), "brush": (data.forests as Array).size(),
		"hazards": (data.hazards as Array).size(), "landmarks": (data.landmarks as Array).size()}
	var patch_ids: Dictionary = {}
	for f: Dictionary in data.forests:
		patch_ids[int(f.patch)] = true
	counts["patches"] = patch_ids.size()
	for key in LIMITS:
		var lim: Array = LIMITS[key]
		if int(counts[key]) < int(lim[0]) or int(counts[key]) > int(lim[1]):
			return "%s %d outside %d-%d" % [key, int(counts[key]), int(lim[0]), int(lim[1])]
	for hz: Dictionary in data.hazards:
		if not Arena.HAZARD_TYPES.has(str(hz.type)):
			return "unsupported hazard " + str(hz.type)
	var features: Dictionary = feature_counts(data)
	for req: Array in REQUIRED.get(str(data.get("preset", "")), []):
		var n: int = int(features.get(str(req[0]), 0))
		if n < int(req[1]) or n > int(req[2]):
			return "%s %d outside %d-%d" % [str(req[0]), n, int(req[1]), int(req[2])]
	var spawns: Array = data.ffa_spawns
	if spawns.size() < SPAWN_MIN:
		return "spawns %d" % spawns.size()
	var c: Vector2 = Vector2(float(data.width) * 0.5, float(data.height) * 0.5)
	var core: float = minf(float(data.width), float(data.height)) * CORE_RATIO
	for i in spawns.size():
		var p: Vector2 = Vector2(float(spawns[i].x), float(spawns[i].y))
		if p.distance_to(c) < core:
			return "spawn %d inside the central circle" % i
		for j in range(i + 1, spawns.size()):
			if p.distance_to(Vector2(float(spawns[j].x), float(spawns[j].y))) < SPAWN_GAP:
				return "spawns %d/%d closer than %d" % [i, j, int(SPAWN_GAP)]
	var report: Array = connectivity(data, arena)
	var dead: Dictionary = {}
	for row: Dictionary in report:
		if not (row.anchors_bad as Array).is_empty():
			return "bucket %d: %s" % [int(row.bucket), str((row.anchors_bad as Array).slice(0, 4))]
		for i in row.spots_bad:
			dead[int(i)] = true
	var kept: Array = []
	var per_ring: Array = [0, 0, 0, 0]
	var spots: Array = data.item_spots
	for i in spots.size():
		if dead.has(i):
			continue
		kept.append(spots[i])
		per_ring[int(spots[i].ring)] = int(per_ring[int(spots[i].ring)]) + 1
	data["item_spots"] = kept
	if kept.size() < SPOT_MIN:
		return "item spots %d" % kept.size()
	for ring in 4:
		if int(per_ring[ring]) < int(RING_SPOT_MIN[ring]):
			return "ring %d spots %d" % [ring, int(per_ring[ring])]
	return ""
