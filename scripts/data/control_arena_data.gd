class_name ControlArenaData
extends RefCounted

# V1.5.3 control maps: three different orientations and objective triangles,
# each about 2.5x the legacy 1408x792 area. Geometry is completed by an exact
# symmetry (see ArenaData) so both teams get identical access to A/B/C.
#   control_crossroads  west/east,   mirror across x = W/2, apex A on the axis
#   control_citadel     north/south, mirror across y = H/2, keep B on the axis
#   control_waterway    NW/SE,       mirror across the NE-SW diagonal (square)
# Nominal multiplier used by UI texts ("about 2.5x"); real areas are 2.48-2.51x.
const AREA_MULTIPLIER: float = 2.5

const HEAL_COOLDOWN: float = 25.0
const HEAL_RATIO: float = 0.35


static func _point(id: String, label: String, x: float, y: float, r: float) -> Dictionary:
	return {"id": id, "label": label, "x": x, "y": y, "radius": r}


# Heal zones in symmetric pairs [[x, y], ...]: the image of each is appended.
static func _heal_pairs(L: ArenaData.Layout, points: Array, radius: float) -> Array:
	var out: Array = []
	for i in points.size():
		var p: Vector2 = Vector2(float(points[i][0]), float(points[i][1]))
		var q: Vector2 = ArenaData.image_point(L.sym, L.w, L.h, p)
		out.append({"id": "heal_%d" % (i * 2), "x": p.x, "y": p.y, "radius": radius, "cooldown": HEAL_COOLDOWN, "heal_ratio": HEAL_RATIO})
		out.append({"id": "heal_%d" % (i * 2 + 1), "x": snappedf(q.x, 0.1), "y": snappedf(q.y, 0.1), "radius": radius, "cooldown": HEAL_COOLDOWN, "heal_ratio": HEAL_RATIO})
	return out


static func _finish(L: ArenaData.Layout, meta: Dictionary, points: Array, heals: Array) -> Dictionary:
	var d: Dictionary = L.finish(meta)
	d.ruleset = "control"
	d.area_multiplier = snappedf(L.w * L.h / ArenaData.LEGACY_AREA, 0.001)
	d.control_points = points
	d.heal_zones = heals
	d.icon = "⚑"
	return d


static func all() -> Array:
	return [_crossroads(), _citadel(), _waterway()]


# West/east teams, apex A on the axis in the north and B/C in the south.
static func _crossroads() -> Dictionary:
	var L := ArenaData.Layout.new(2240.0, 1248.0, "mirror_x")
	var wall: String = "#4b6572"
	L.obstacle(ArenaData._wall("junction_core", 1060, 650, 120, 100, wall))
	L.obstacle(ArenaData._wall("branch_west|branch_east", 850, 560, 160, 40, wall))
	L.obstacle(ArenaData._pillar("apex_cover_w|apex_cover_e", 880, 260, 34, "#527878"))
	L.obstacle(ArenaData._wall("south_median", 1060, 1010, 120, 40, wall))
	L.obstacle(ArenaData._wall("wing_west|wing_east", 560, 560, 40, 160, wall))
	L.obstacle(ArenaData._pillar("base_rock_w|base_rock_e", 700, 1110, 30, "#527878"))
	L.brush([[980, 420, 64], [1030, 462, 46]])
	L.brush([[1090, 870, 56], [1150, 870, 56]])
	L.hazard(ArenaData._haste("apex_rush", 1120, 150, 46, 1.2, 2.0))
	L.hazard(ArenaData._haste("flank_rush_w|flank_rush_e", 560, 400, 44, 1.2, 2.0))
	L.spawns([[210, 624], [245, 500], [245, 748], [180, 380], [180, 868]])
	var points: Array = [_point("A", "A · 북부 정점", 1120, 320, 76), _point("B", "B · 남서 기지", 760, 900, 76), _point("C", "C · 남동 기지", 1480, 900, 76)]
	return _finish(L, {"id": "control_crossroads", "name": "삼방 교차로", "subtitle": "삼각 거점 · Y자 합류",
		"description": "북쪽 정점 A와 남서·남동 기지 B·C가 삼각형을 이룹니다. 가운데 합류점과 수풀을 돌아 어느 두 거점을 이을지 정합니다.",
		"accent": "#6ed6dd", "difficulty": "삼각 거점", "tags": ["거점 장악", "동서 출발", "삼각 배치", "수풀", "면적 약 2.5배"],
		"tacticalNotes": ["A는 두 팀에게서 같은 거리에 있고, B는 청 팀, C는 홍 팀 쪽에 가깝습니다. 가까운 기지와 정점을 먼저 잇습니다.",
			"합류점 위쪽 수풀과 남쪽 수풀은 거점 사이를 오가는 적을 기습하기 좋습니다.",
			"북쪽 가속 구역은 정점 A로의 빠른 지원을 돕습니다. 회복 구역 네 곳은 두 팀이 따로 쓸 수 있게 대칭으로 놓였습니다."],
		"floor": {"base": "#08151b", "blue": "#16435c", "red": "#542f4b", "grid": "#6ed6dd"},
		"layout_id": "triangle_y_junction", "archetype": "triangle_objectives", "spawn_orientation": "west_east",
		"landmarks": [ArenaData._landmark("apex", "북쪽 정점", 1120, 320, 96), ArenaData._landmark("y_merge", "삼방 합류", 1120, 700, 90, "lane")]},
		points, _heal_pairs(L, [[470, 260], [470, 988]], 40.0))


# North/south teams. Outposts A (north-west) and C (south-west) mirror each
# other; keep B sits on the axis in the east with two alternating gate pairs.
static func _citadel() -> Dictionary:
	var L := ArenaData.Layout.new(1952.0, 1424.0, "mirror_y")
	var stone: String = "#786951"
	var lattice: String = "#a08c68"
	var gate_col: String = "#b08850"
	var cycle: Array = [12.0, 7.0, 1.5, 2.0]
	L.obstacle(ArenaData._wall("tower_nw|tower_sw", 1150, 562, 56, 56, stone))
	L.obstacle(ArenaData._wall("tower_ne|tower_se", 1394, 562, 56, 56, stone))
	L.obstacle(ArenaData._screen("keep_lattice_n1|keep_lattice_s1", 1206, 572, 39, 28, lattice))
	L.obstacle(ArenaData._screen("keep_lattice_n2|keep_lattice_s2", 1355, 572, 39, 28, lattice))
	L.obstacle(ArenaData._screen("keep_lattice_w1|keep_lattice_w2", 1160, 618, 28, 39, lattice))
	L.obstacle(ArenaData._gate("keep_gate_north|keep_gate_south", 1245, 572, 110, 28, "A", cycle, gate_col))
	L.obstacle(ArenaData._gate("keep_gate_west", 1160, 657, 28, 110, "B", cycle, gate_col))
	L.obstacle(ArenaData._wall("rampart_nw|rampart_sw", 380, 300, 220, 40, "#665d51"))
	L.obstacle(ArenaData._wall("rampart_ne|rampart_se", 1560, 400, 40, 180, "#665d51"))
	L.obstacle(ArenaData._pillar("court_pillar_n|court_pillar_s", 900, 560, 30, "#6f6453"))
	L.hazard(ArenaData._rect_hazard("courtyard_barrage", "artillery", "포격 구역", 430, 600, 380, 224, "#ff8f6b",
		{"period": 11.0, "warningDuration": 1.8, "phase": 4.0, "count": 3, "radius": 80.0, "damage": 40.0, "school": "magic", "spread": 90.0}))
	L.hazard(ArenaData._haste("outer_rush_n|outer_rush_s", 1700, 300, 44, 1.32, 1.3))
	L.spawns([[976, 150], [860, 175], [1092, 175], [744, 140], [1208, 140]])
	var points: Array = [_point("A", "A · 북서 전초", 620, 440, 66), _point("B", "B · 동쪽 내성", 1300, 712, 66), _point("C", "C · 남서 전초", 620, 984, 66)]
	return _finish(L, {"id": "control_citadel", "name": "환상 요새", "subtitle": "남북 출발 · 동쪽 내성 성문",
		"description": "북서·남서 전초와 동쪽 내성이 삼각형을 이룹니다. 내성은 동쪽 뒤편이 열려 있고 남북 성문과 서쪽 성문이 번갈아 열리며, 두 전초 사이 안뜰에는 포격이 떨어집니다.",
		"accent": "#deb877", "difficulty": "성채 거점", "tags": ["거점 장악", "남북 출발", "개폐 성문", "포격", "면적 약 2.5배"],
		"tacticalNotes": ["A는 청 팀, C는 홍 팀 쪽 전초이고 B 내성은 두 팀에게서 같은 거리에 있습니다.",
			"내성의 남북 성문과 서쪽 성문은 번갈아 열립니다. 모두 닫혀 있어도 동쪽 뒷길로 돌아 들어갈 수 있습니다.",
			"두 전초 사이 안뜰에는 예고 뒤 포격이 떨어집니다. 예고 원을 보고 전초 쪽으로 비켜 섭니다."],
		"floor": {"base": "#17130f", "blue": "#16435c", "red": "#542f4b", "grid": "#deb877"},
		"layout_id": "citadel_gated_keep", "archetype": "gated_keep_objectives", "spawn_orientation": "north_south",
		"landmarks": [ArenaData._landmark("keep", "동쪽 내성", 1300, 712, 110), ArenaData._landmark("courtyard", "포격 안뜰", 620, 712, 110, "lane")]},
		points, _heal_pairs(L, [[300, 420], [1700, 470]], 40.0))


# North-west/south-east teams on a square map, mirrored across the NE-SW
# diagonal. A stepped river runs along that diagonal: B holds the wide central
# ford, two narrow muddy fords sit near the neutral corners.
static func _waterway() -> Dictionary:
	var L := ArenaData.Layout.new(1664.0, 1664.0, "mirror_anti")
	var water: String = "#123a5a"
	for k in range(-7, 8):
		if absi(k) <= 1 or absi(k) == 4 or absi(k) == 5:
			continue
		var c: Vector2 = Vector2(832.0 + k * 96.0, 832.0 - k * 96.0)
		L.obstacle(ArenaData._chasm("river_%d" % (k + 7), c.x - 64.0, c.y - 64.0, 128, 128, water, "water"))
	L.obstacle(ArenaData._pillar("bank_rock_a|bank_rock_b", 520, 420, 34, "#567490"))
	L.obstacle(ArenaData._wall("bank_wall_a|bank_wall_b", 300, 700, 140, 36, "#425b75"))
	L.obstacle(ArenaData._wall("bank_wall_c|bank_wall_d", 700, 300, 36, 140, "#425b75"))
	L.hazard(ArenaData._rect_hazard("ford_mud_ne", "mud", "여울 진흙", 1184, 320, 160, 160, "#8a6a45", {"slow": 0.3}))
	L.hazard(ArenaData._rect_hazard("ford_mud_sw", "mud", "여울 진흙", 320, 1184, 160, 160, "#8a6a45", {"slow": 0.3}))
	L.hazard(ArenaData._haste("bank_current_a|bank_current_b", 820, 520, 44, 1.3, 1.2))
	L.spawns([[230, 230], [360, 180], [180, 360], [500, 150], [150, 500]])
	var points: Array = [_point("A", "A · 북서 둑", 560, 720, 70), _point("B", "B · 중앙 여울", 832, 832, 72), _point("C", "C · 남동 둑", 944, 1104, 70)]
	return _finish(L, {"id": "control_waterway", "name": "갈라진 수로", "subtitle": "대각선 강 · 세 여울",
		"description": "북동에서 남서로 흐르는 계단식 강이 전장을 가릅니다. 두 팀은 북서와 남동 모서리에서 출발하고, 넓은 중앙 여울의 B와 강 양쪽 둑의 A·C를 다툽니다.",
		"accent": "#8baee8", "difficulty": "대각 수로", "tags": ["거점 장악", "대각선 출발", "진흙", "강 여울", "면적 약 2.5배"],
		"tacticalNotes": ["강은 걸어서 건널 수 없지만 시야와 투사체는 통과합니다. 건너편 둑의 적을 보며 여울을 고릅니다.",
			"중앙 여울은 넓고 B가 있습니다. 북동·남서 여울은 좁고 진흙이 이동 속도를 30% 늦춥니다.",
			"A는 청 팀, C는 홍 팀 쪽 둑에 있습니다. 둑의 가속 구역은 가까운 거점과 중앙 여울을 빠르게 잇습니다."],
		"floor": {"base": "#0a1221", "blue": "#16435c", "red": "#542f4b", "grid": "#8baee8"},
		"layout_id": "diagonal_river_fords", "archetype": "river_fords", "spawn_orientation": "diagonal",
		"landmarks": [ArenaData._landmark("central_ford", "중앙 여울", 832, 832, 120), ArenaData._landmark("ford_ne", "북동 여울", 1264, 400, 90, "lane"),
			ArenaData._landmark("ford_sw", "남서 여울", 400, 1264, 90, "lane")]},
		points, _heal_pairs(L, [[300, 920], [920, 300]], 40.0))
