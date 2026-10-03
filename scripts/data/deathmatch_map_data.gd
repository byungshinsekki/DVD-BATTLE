class_name DeathmatchMapData
extends RefCounted

# Procedural free-for-all battlefields. The same preset and seed always build
# the same map. Buildings are wall rectangles with doorways; forests are
# overlapping canopy circles that hide units inside them (see Arena.forests);
# rocks and tree trunks are small solid obstacles.

const WIDTH := 3600.0
const HEIGHT := 2200.0
const MARGIN := 40.0

const PRESETS := {
	"dm_forest_village": {"name": "숲의 마을", "subtitle": "서부 숲벨트 · 진흙 늪 · 동부 마을",
		"description": "서쪽의 두 숲벨트와 동쪽의 여섯 오두막 마을이 갈라진 전장입니다. 숲길 사이 진흙 늪이 발을 붙잡고, 숲의 은신과 마을 도로의 시야 차이를 이용해 중앙 회복 샘을 다툽니다.",
		"tacticalNotes": ["숲 안의 영웅은 110 이내(몸 가장자리 기준)로 다가오거나 교전하기 전까지 밖에서 보이지 않습니다.", "숲벨트 사이 진흙 늪은 머무는 동안 이동 속도를 40% 늦춥니다. 추격과 도주 경로에서 피해 갑니다.", "건물마다 아이템 자리가 3곳 있고 벽이 이동·투사체·시야를 모두 막습니다."],
		"accent": "#7fd08a", "floor": "#0c1a12", "grid": "#7fd08a",
		"buildings": [6, 6], "forests": [8, 8], "rocks": [10, 14], "layout_id": "forest_belts_marsh_village",
		"tags": ["개인전", "최대 12명", "아이템", "숲", "진흙"]},
	"dm_ruined_town": {"name": "폐허 도시", "subtitle": "도로 격자 · 중앙 포격 광장",
		"description": "열두 건물이 세 줄의 도로 격자를 이루는 폐허입니다. 가운데 넓은 광장은 빠른 기동로이지만 예고 뒤 포격이 떨어집니다.",
		"tacticalNotes": ["건물 문은 충분히 넓고 도로가 격자로 연결됩니다. 엄폐 모서리에서 제어와 매복을 연계할 수 있습니다.", "광장 포격은 예고 원이 나타난 뒤 떨어지며 광장 안의 영웅 근처를 노립니다. 예고를 보면 건물 쪽으로 비켜 섭니다.", "건물마다 아이템 자리가 3곳이라 실내에서 아이템을 모으기 좋습니다."],
		"accent": "#e0b46e", "floor": "#17130d", "grid": "#e0b46e",
		"buildings": [12, 12], "forests": [6, 6], "rocks": [8, 12], "layout_id": "street_grid_artillery_plaza",
		"tags": ["개인전", "최대 12명", "아이템", "건물 격자", "포격"]},
	"dm_open_steppe": {"name": "바람의 초원", "subtitle": "넓은 초원 · 능선 도약 발판",
		"description": "네 모서리 야영지와 두 줄의 긴 능선 사이로 넓은 초원이 열립니다. 능선 틈을 지나거나 도약 발판으로 능선을 뛰어넘고, 중앙 가속 평원과 돌풍을 타고 전장을 가로지릅니다.",
		"tacticalNotes": ["트인 평원이 넓어 원거리 영웅이 먼저 싸움을 걸기 좋습니다.", "긴 능선은 이동·투사체·시야를 막습니다. 능선 양쪽의 도약 발판은 표시된 방향으로만 능선을 넘겨 줍니다.", "중앙의 가속 평원과 돌풍은 장거리 이동을 돕습니다. 동서 회복 샘은 샘마다 모든 영웅이 충전량을 함께 씁니다."],
		"accent": "#8fc3ef", "floor": "#0b1420", "grid": "#8fc3ef",
		"buildings": [4, 4], "forests": [6, 6], "rocks": [16, 22], "layout_id": "open_steppe_ridge_pads",
		"tags": ["개인전", "최대 12명", "아이템", "능선", "도약 발판"]},
}
const ORDER := ["dm_forest_village", "dm_ruined_town", "dm_open_steppe"]


static func is_deathmatch_id(id: String) -> bool:
	return PRESETS.has(id)


# Catalogue entries shown in setup screens (no geometry: it depends on the seed).
static func catalogue() -> Array:
	var out: Array = []
	for id in ORDER:
		var p: Dictionary = PRESETS[id]
		out.append({"id": id, "name": p.name, "subtitle": p.subtitle, "description": p.description,
			"ruleset": "deathmatch", "layout_id": p.layout_id, "accent": p.accent, "difficulty": "개인전", "icon": "✦",
			"tags": (p.tags as Array) + ["시드별 배치"],
			"width": WIDTH, "height": HEIGHT,
			"bounds": {"minX": MARGIN, "maxX": WIDTH - MARGIN, "minY": MARGIN, "maxY": HEIGHT - MARGIN},
			"floor": {"base": p.floor, "blue": "#16435c", "red": "#542f4b", "grid": p.grid},
			"spawns": {"blue": [{"x": 300.0, "y": 300.0}], "red": [{"x": WIDTH - 300.0, "y": HEIGHT - 300.0}]},
			"obstacles": [], "hazards": [], "control_points": [], "heal_zones": [], "forests": [],
			"tacticalNotes": (p.get("tacticalNotes", []) as Array).duplicate()})
	return out


static func build(preset_id: String, seed_value: int) -> Dictionary:
	var preset: Dictionary = PRESETS.get(preset_id, PRESETS[ORDER[0]])
	for attempt in 12:
		var data: Dictionary = _generate(preset_id, preset, seed_value * 1009 + attempt * 7919 + 17)
		if _valid(data):
			data["generation_attempt"] = attempt
			return data
	return _validated_fallback(preset_id, preset)


static func _rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


static func _wall(id: String, x: float, y: float, w: float, h: float, color: String) -> Dictionary:
	return {"id": id, "shape": "rect", "x": x, "y": y, "w": w, "h": h, "kind": "wall", "material": "stone",
		"blocksUnits": true, "blocksProjectiles": true, "blocksVision": true, "color": color}


static func _circle_solid(id: String, x: float, y: float, r: float, kind: String, color: String) -> Dictionary:
	return {"id": id, "shape": "circle", "x": x, "y": y, "radius": r, "kind": kind, "material": "stone" if kind == "pillar" else "wood",
		"blocksUnits": true, "blocksProjectiles": true, "blocksVision": kind == "pillar", "color": color}


static func _landmark(id: String, label: String, x: float, y: float, radius: float, kind: String = "plaza") -> Dictionary:
	return {"id": id, "label": label, "x": x, "y": y, "radius": radius, "kind": kind}

# Per-preset parameters keep every map's hazard numbers distinct (V1.5.3).
static func _haste(id: String, x: float, y: float, radius: float, mult: float = 1.25, duration: float = 1.6) -> Dictionary:
	return {"id": id, "label": "가속 구역", "shape": "circle", "type": "haste", "x": x, "y": y, "radius": radius,
		"speedMultiplier": mult, "duration": duration, "refreshInterval": 0.5, "color": "#72efcf"}

static func _fountain(id: String, x: float, y: float, heal: float = 0.16, cooldown: float = 18.0) -> Dictionary:
	return {"id": id, "label": "공용 회복 샘", "shape": "circle", "type": "healing_fountain", "x": x, "y": y, "radius": 76.0,
		"healPercent": heal, "cooldown": cooldown, "minMissingPercent": 0.05, "color": "#80e8ac"}

# One-way launch over a ridge; landing points are reserved before rocks and trunks.
static func _jump_pad(id: String, x: float, y: float, tx: float, ty: float) -> Dictionary:
	return {"id": id, "label": "도약 발판", "shape": "circle", "type": "jump_pad", "x": x, "y": y, "radius": 36.0,
		"target": {"x": tx, "y": ty}, "flightTime": 0.75, "cooldown": 2.0, "color": "#7fe3ff"}


static func _on_pad(p: Vector2, hazards: Array) -> bool:
	for h in hazards:
		if str(h.type) == "jump_pad" and (p.distance_to(Vector2(float(h.x), float(h.y))) <= float(h.radius) + 40.0
				or p.distance_to(Vector2(float(h.target.x), float(h.target.y))) <= 50.0):
			return true
	return false


static func _in_hazard(p: Vector2, hazards: Array, pad: float) -> bool:
	for h in hazards:
		if Arena.shape_contains(h, p, pad):
			return true
	return false

static func _generate(preset_id: String, preset: Dictionary, seed_value: int) -> Dictionary:
	var r: RandomNumberGenerator = _rng(seed_value)
	var occupied: Array = [] # Reserve architectural footprints and public gimmick approaches.
	var obstacles: Array = []
	var buildings: Array = []
	var forests: Array = []
	var hazards: Array = []
	var landmarks: Array = []
	var anchors: Array[Vector2] = []
	var forest_anchors: Array[Vector2] = []
	match preset_id:
		"dm_ruined_town":
			for y in [260.0, 910.0, 1570.0]:
				for x in [330.0, 1070.0, 2220.0, 2960.0]:
					anchors.append(Vector2(x, y))
			forest_anchors = [Vector2(1800, 420), Vector2(1800, 1780), Vector2(820, 740), Vector2(2750, 740), Vector2(820, 1450), Vector2(2750, 1450)]
			hazards = [_fountain("city_north_spring", 1800, 210, 0.15, 20.0), _fountain("city_south_spring", 1800, 1990, 0.15, 20.0),
				_haste("city_north_avenue", 1800, 760, 105, 1.2, 1.9), _haste("city_south_avenue", 1800, 1450, 105, 1.2, 1.9),
				{"id": "city_plaza_barrage", "label": "광장 포격", "shape": "rect", "type": "artillery", "x": 1520.0, "y": 880.0, "w": 560.0, "h": 440.0,
				"period": 10.0, "warningDuration": 2.0, "phase": 4.0, "count": 4, "radius": 85.0, "damage": 44.0, "school": "physical", "spread": 80.0, "color": "#ff8f6b"}]
			landmarks = [_landmark("city_plaza", "중앙 포격 광장", 1800, 1100, 300), _landmark("city_west_street", "서부 도로 격자", 900, 1100, 260, "lane"), _landmark("city_east_street", "동부 도로 격자", 2700, 1100, 260, "lane")]
		"dm_open_steppe":
			anchors = [Vector2(330, 260), Vector2(2940, 260), Vector2(330, 1650), Vector2(2940, 1650)]
			forest_anchors = [Vector2(860, 400), Vector2(2740, 400), Vector2(600, 1100), Vector2(3000, 1100), Vector2(860, 1800), Vector2(2740, 1800)]
			var north_y: float = 635.0 + r.randf_range(-40.0, 40.0)
			var south_y: float = 1500.0 + r.randf_range(-40.0, 40.0)
			var ridges: Array = [
				_wall("ridge_north_west", 1020, north_y, 770 + r.randf_range(-60, 60), 65, "#586c79"),
				_wall("ridge_north_east", 2180, north_y, 550 + r.randf_range(-45, 45), 65, "#586c79"),
				_wall("ridge_south_west", 870, south_y, 550 + r.randf_range(-45, 45), 65, "#586c79"),
				_wall("ridge_south_east", 1810, south_y, 770 + r.randf_range(-60, 60), 65, "#586c79")]
			for ridge in ridges:
				obstacles.append(ridge)
				occupied.append(Rect2(ridge.x, ridge.y, ridge.w, ridge.h).grow(100.0))
			# Ridge pads: one pad on each face of the two long ridges, launching
			# over the ridge in opposite directions (never onto the other pad).
			var nx: float = float(ridges[0].x) + float(ridges[0].w) * 0.5
			var sx: float = float(ridges[3].x) + float(ridges[3].w) * 0.5
			hazards = [_haste("steppe_open_sprint", 1800, 1100, 175, 1.35, 1.2), _fountain("steppe_west_spring", 410, 1100, 0.17, 22.0), _fountain("steppe_east_spring", 3190, 1100, 0.17, 22.0),
				{"id": "steppe_gust", "label": "초원 횡풍", "shape": "rect", "type": "wind", "x": 950.0, "y": 1015.0, "w": 1700.0, "h": 170.0,
				"period": 7.0, "activeDuration": 7.0, "phase": 0.0, "directionA": {"x": 1.0, "y": 0.0}, "directionB": {"x": -1.0, "y": 0.0}, "force": 75.0, "color": "#7acfc5"},
				_jump_pad("ridge_pad_nw_down", nx - 120.0, north_y - 115.0, nx - 120.0, north_y + 205.0),
				_jump_pad("ridge_pad_nw_up", nx + 120.0, north_y + 180.0, nx + 120.0, north_y - 140.0),
				_jump_pad("ridge_pad_se_down", sx - 120.0, south_y - 115.0, sx - 120.0, south_y + 205.0),
				_jump_pad("ridge_pad_se_up", sx + 120.0, south_y + 180.0, sx + 120.0, south_y - 140.0)]
			landmarks = [_landmark("steppe_plain", "가속 초원", 1800, 1100, 340), _landmark("steppe_north_pass", "북쪽 능선 틈", 1970, north_y, 100, "lane"),
				_landmark("steppe_south_pass", "남쪽 능선 틈", 1610, south_y, 100, "lane"), _landmark("steppe_north_leap", "북쪽 능선 도약", nx, north_y + 32, 150, "lane"),
				_landmark("steppe_south_leap", "남쪽 능선 도약", sx, south_y + 32, 150, "lane")]
		_:
			for y in [310.0, 940.0, 1570.0]:
				for x in [2020.0, 2820.0]:
					anchors.append(Vector2(x, y))
			for y in [360.0, 850.0, 1350.0, 1840.0]:
				for x in [600.0, 1200.0]:
					forest_anchors.append(Vector2(x, y))
			hazards = [_fountain("village_communal_spring", 1800, 1100), _haste("village_north_trail", 1560, 430, 85), _haste("village_south_trail", 1560, 1770, 85),
				{"id": "forest_well", "label": "숲길 중력 우물", "shape": "circle", "type": "gravity", "x": 1000.0, "y": 1100.0, "radius": 150.0,
				"period": 9.0, "activeDuration": 2.0, "warningDuration": 1.4, "phase": 3.0, "force": 130.0, "damage": 6.0, "tickInterval": 0.5, "school": "magic", "color": "#a78af4"},
				{"id": "marsh_north", "label": "숲 진흙 늪", "shape": "rect", "type": "mud", "x": 740.0, "y": 560.0, "w": 320.0, "h": 140.0, "slow": 0.4, "color": "#7a5e3c"},
				{"id": "marsh_south", "label": "숲 진흙 늪", "shape": "rect", "type": "mud", "x": 740.0, "y": 1500.0, "w": 320.0, "h": 140.0, "slow": 0.4, "color": "#7a5e3c"}]
			landmarks = [_landmark("forest_belts", "서부 숲벨트", 900, 1100, 300, "landmark"), _landmark("village_green", "공용 샘 마당", 1800, 1100, 170, "supply"),
				_landmark("east_village", "동부 마을 도로", 2650, 1100, 300, "lane"), _landmark("forest_marsh", "숲 진흙 늪", 900, 630, 150, "lane")]
	# Each preset has a recognisable large-scale plan. Seeds vary footprints,
	# doors, groves, rocks and supplies inside that plan instead of mixing it away.
	var wall_color: String = "#6b6456" if preset_id == "dm_ruined_town" else "#5d6a70"
	for anchor in anchors:
		var w: float = r.randf_range(275.0, 355.0)
		var h: float = r.randf_range(240.0, 310.0)
		var p: Vector2 = anchor + Vector2(r.randf_range(-36.0, 36.0), r.randf_range(-32.0, 32.0))
		var rect := Rect2(p, Vector2(w, h))
		occupied.append(rect.grow(90.0))
		var b_id: String = "b%d" % buildings.size()
		buildings.append({"id": b_id, "x": p.x, "y": p.y, "w": w, "h": h})
		_add_building(obstacles, r, b_id, rect, wall_color)
	for h in hazards:
		if str(h.shape) == "circle":
			var radius: float = float(h.radius) + 55.0
			occupied.append(Rect2(float(h.x) - radius, float(h.y) - radius, radius * 2.0, radius * 2.0))
		else:
			occupied.append(Rect2(float(h.x), float(h.y), float(h.w), float(h.h)).grow(40.0))
		if h.has("target"):
			occupied.append(Rect2(float(h.target.x) - 80.0, float(h.target.y) - 80.0, 160.0, 160.0))
	for patch_id in forest_anchors.size():
		var c: Vector2 = forest_anchors[patch_id] + Vector2(r.randf_range(-35, 35), r.randf_range(-35, 35))
		var radius: float = r.randf_range(106, 132) if preset_id == "dm_forest_village" else r.randf_range(72, 98)
		for k in 3:
			var p: Vector2 = c + Vector2(float(k - 1) * radius * 0.58, r.randf_range(-38, 38))
			forests.append({"x": p.x, "y": p.y, "radius": radius, "patch": patch_id})
		# Trunks are separated from walls and one another by broad movement gaps.
		for k in 2:
			var tp: Vector2 = c + Vector2(-65 if k == 0 else 65, r.randf_range(-45, 45))
			var footprint := Rect2(tp - Vector2(65, 65), Vector2(130, 130))
			var clear: bool = true
			for other in occupied:
				if footprint.intersects(other):
					clear = false
					break
			if clear:
				obstacles.append(_circle_solid("trunk_%d_%d" % [patch_id, k], tp.x, tp.y, 16.0, "tree", "#4a3a2a"))
				occupied.append(footprint)
	var n_rocks: int = r.randi_range(int(preset.rocks[0]), int(preset.rocks[1]))
	var tries: int = 0
	var rocks: int = 0
	while rocks < n_rocks and tries < 500:
		tries += 1
		var rp := Vector2(r.randf_range(160.0, WIDTH - 160.0), r.randf_range(160.0, HEIGHT - 160.0))
		var rr: float = r.randf_range(22.0, 42.0)
		var footprint := Rect2(rp - Vector2(rr + 75, rr + 75), Vector2(rr + 75, rr + 75) * 2)
		var clear: bool = true
		for other in occupied:
			if footprint.intersects(other):
				clear = false
				break
		if clear:
			occupied.append(footprint)
			obstacles.append(_circle_solid("rock_%d" % rocks, rp.x, rp.y, rr, "pillar", "#5c6e6e"))
			rocks += 1
	var data: Dictionary = {"id": "%s_%d" % [preset_id, seed_value], "preset": preset_id, "name": preset.name,
		"subtitle": preset.subtitle, "description": preset.description, "ruleset": "deathmatch", "accent": preset.accent,
		"layout_id": preset.layout_id, "landmarks": landmarks,
		"difficulty": "개인전", "icon": "✦", "tags": (preset.tags as Array) + ["구획별 시드 변형"],
		"width": WIDTH, "height": HEIGHT,
		"bounds": {"minX": MARGIN, "maxX": WIDTH - MARGIN, "minY": MARGIN, "maxY": HEIGHT - MARGIN},
		"floor": {"base": preset.floor, "blue": "#16435c", "red": "#542f4b", "grid": preset.grid},
		"obstacles": obstacles, "forests": forests, "buildings": buildings, "hazards": hazards, "control_points": [], "heal_zones": [],
		"tacticalNotes": (preset.get("tacticalNotes", []) as Array).duplicate()}
	data["ffa_spawns"] = _spawn_points(r, data)
	data["item_spots"] = _item_spots(r, data)
	data["spawns"] = {"blue": [data.ffa_spawns[0]], "red": [data.ffa_spawns[1]]}
	return data


static func _add_building(obstacles: Array, r: RandomNumberGenerator, b_id: String, rect: Rect2, color: String) -> void:
	var t: float = 22.0
	var door: float = r.randf_range(130.0, 148.0)
	# Each side gets a doorway with probability; at least two sides are open.
	var open: Array = [r.randf() < 0.6, r.randf() < 0.6, r.randf() < 0.6, r.randf() < 0.6]
	var count: int = 0
	for o in open:
		count += int(o)
	var k: int = 0
	while count < 2:
		var side: int = r.randi_range(0, 3)
		if not open[side]:
			open[side] = true
			count += 1
		k += 1
		if k > 20:
			break
	var x: float = rect.position.x
	var y: float = rect.position.y
	var w: float = rect.size.x
	var h: float = rect.size.y
	# top, bottom (horizontal)
	for side in [0, 1]:
		var yy: float = y if side == 0 else y + h - t
		if open[side]:
			var at: float = r.randf_range(x + 28.0, x + w - 28.0 - door)
			obstacles.append(_wall("%s_w%d_a" % [b_id, side], x, yy, at - x, t, color))
			obstacles.append(_wall("%s_w%d_b" % [b_id, side], at + door, yy, x + w - at - door, t, color))
		else:
			obstacles.append(_wall("%s_w%d" % [b_id, side], x, yy, w, t, color))
	# left, right (vertical, between the horizontal walls)
	for side in [2, 3]:
		var xx: float = x if side == 2 else x + w - t
		var y0: float = y + t
		var hh: float = h - t * 2.0
		if open[side]:
			var at2: float = r.randf_range(y0 + 24.0, y0 + hh - 24.0 - door)
			obstacles.append(_wall("%s_w%d_a" % [b_id, side], xx, y0, t, at2 - y0, color))
			obstacles.append(_wall("%s_w%d_b" % [b_id, side], xx, at2 + door, t, y0 + hh - at2 - door, color))
		else:
			obstacles.append(_wall("%s_w%d" % [b_id, side], xx, y0, t, hh, color))
	# Interior partitions were removed: supplies must remain reachable at radius 30.


static func _in_forest(p: Vector2, forests: Array) -> bool:
	for f in forests:
		if p.distance_to(Vector2(float(f.x), float(f.y))) <= float(f.radius):
			return true
	return false


static func _in_building(p: Vector2, buildings: Array, pad: float = 0.0) -> bool:
	for b in buildings:
		if Rect2(float(b.x), float(b.y), float(b.w), float(b.h)).grow(pad).has_point(p):
			return true
	return false


static func _clear_of_obstacles(p: Vector2, obstacles: Array, pad: float) -> bool:
	for o in obstacles:
		if Arena.shape_contains(o, p, pad):
			return false
	return true


static func _spawn_points(r: RandomNumberGenerator, data: Dictionary) -> Array:
	var out: Array = []
	var bounds: Dictionary = data.bounds
	var tries: int = 0
	while out.size() < 16 and tries < 3000:
		tries += 1
		var p := Vector2(r.randf_range(float(bounds.minX) + 120.0, float(bounds.maxX) - 120.0),
			r.randf_range(float(bounds.minY) + 120.0, float(bounds.maxY) - 120.0))
		if _in_forest(p, data.forests) or _in_building(p, data.buildings, 60.0) or not _clear_of_obstacles(p, data.obstacles, 60.0) or _in_hazard(p, data.hazards, 60.0):
			continue
		var ok: bool = true
		for q in out:
			if p.distance_to(Vector2(float(q.x), float(q.y))) < 520.0:
				ok = false
				break
		if ok:
			out.append({"x": p.x, "y": p.y})
	return out


static func _item_spots(r: RandomNumberGenerator, data: Dictionary) -> Array:
	# Anchors: building interiors (supply rooms), forest edges and open field.
	var spots: Array = []
	for b in data.buildings:
		# Three guaranteed interior supply anchors; all rooms have wide doors and
		# no partition. Keep centres far enough from walls for the nav-grid link.
		var center := Vector2(float(b.x) + float(b.w) * 0.5, float(b.y) + float(b.h) * 0.5)
		for offset in [Vector2(-float(b.w) * 0.18, -float(b.h) * 0.12), Vector2(float(b.w) * 0.18, -float(b.h) * 0.12), Vector2(0, float(b.h) * 0.18)]:
			var p: Vector2 = center + offset
			spots.append({"x": p.x, "y": p.y, "kind": "building"})
	for f in data.forests:
		if r.randf() < 0.5:
			var fp: Vector2 = Vector2(float(f.x), float(f.y)) + Vector2.from_angle(r.randf() * TAU) * float(f.radius) * r.randf_range(0.2, 0.8)
			if _clear_of_obstacles(fp, data.obstacles, 45.0) and not _on_pad(fp, data.hazards):
				spots.append({"x": fp.x, "y": fp.y, "kind": "forest"})
	var bounds: Dictionary = data.bounds
	var tries: int = 0
	var field: int = 0
	while field < 28 and tries < 1500:
		tries += 1
		var p2 := Vector2(r.randf_range(float(bounds.minX) + 80.0, float(bounds.maxX) - 80.0), r.randf_range(float(bounds.minY) + 80.0, float(bounds.maxY) - 80.0))
		if _in_building(p2, data.buildings, 40.0) or not _clear_of_obstacles(p2, data.obstacles, 40.0) or _on_pad(p2, data.hazards):
			continue
		spots.append({"x": p2.x, "y": p2.y, "kind": "forest" if _in_forest(p2, data.forests) else "field"})
		field += 1
	return spots


# Validate complete continuous routes including the link from an arbitrary item
# anchor to its nearest navigation cell. A nonempty grid path alone can hide a
# clipped final segment when the anchor is beside a wall or tree trunk.
static func _reachable(nav: Navigator, first: Vector2, point: Vector2) -> bool:
	if nav.clear(first, point, 30.0):
		return true
	var path: PackedVector2Array = nav.path_points(first, point)
	if path.size() < 2 or not nav.clear(first, path[0], 30.0) or not nav.clear(path[-1], point, 30.0):
		return false
	for i in range(1, path.size()):
		if not nav.clear(path[i - 1], path[i], 30.0):
			return false
	return true

static func _valid(data: Dictionary) -> bool:
	var spawns: Array = data.get("ffa_spawns", [])
	if spawns.size() < 12 or (data.get("item_spots", []) as Array).size() < 30:
		return false
	var arena: Arena = Arena.from_data(data)
	var nav := Navigator.new()
	nav.arena = arena
	nav.bucket = 30.0
	nav._build()
	var first := Vector2(float(spawns[0].x), float(spawns[0].y))
	var anchors: Array = spawns.duplicate()
	anchors.append_array(data.get("item_spots", []))
	for hazard in arena.hazards:
		anchors.append({"x": hazard.center.x, "y": hazard.center.y})
		if hazard.has("target"):
			anchors.append({"x": float(hazard.target.x), "y": float(hazard.target.y)})
	for anchor in anchors:
		var p := Vector2(float(anchor.x), float(anchor.y))
		if not arena.is_walkable(p, 30.0) or not _reachable(nav, first, p):
			return false
	return true

# Generation must never return the previous unchecked fallback. Canonical seeds
# retain each preset's plan and pass the same radius-30 contract before delivery.
static func _validated_fallback(preset_id: String, preset: Dictionary) -> Dictionary:
	for fallback_seed in [1026, 2035, 3044]:
		var data: Dictionary = _generate(preset_id, preset, fallback_seed)
		if _valid(data):
			data["generation_attempt"] = 12
			data["generation_fallback"] = true
			return data
	push_error("Deathmatch map has no connected validated layout: " + preset_id)
	return {}
