class_name ArenaData
extends RefCounted

# V1.5.3 map-format rework: twelve elimination maps with different sizes, spawn
# orientations and one topology archetype each. Every map is authored as one
# team half (plus self-symmetric centre pieces) and completed by an exact
# symmetry, so obstacles, hazards (with identical phases), brush, jump pads and
# gates are fair by construction:
#   "point"       180-degree rotation about the map centre
#   "mirror_x"    reflection across x = W/2 (teams west / east)
#   "mirror_y"    reflection across y = H/2 (teams north / south)
#   "mirror_anti" reflection across the NE-SW diagonal of a square map
# A paired id "a|b" names the authored piece and its image. Self-symmetric
# pieces use a single id. tests/maps_153.gd re-derives and checks the symmetry.
# Stable map ids are kept; names, layouts and texts changed in V1.5.3.

const LEGACY_AREA: float = 1408.0 * 792.0

static var LIST: Array = _build_all()


static func _build_all() -> Array:
	var out: Array = [_classic(), _ruined_gate(), _thorn_circuit(), _furnace_basin(), _wind_temple(),
		_dimensional_lattice(), _crossroads(), _moon_garden(), _twin_foundry(), _gale_corridor(),
		_rift_harbor(), _bastion_ring()]
	for d in out:
		_freeze(d)
	out.make_read_only()
	return out


# Authored data behaves like the former const literal: shared, never mutated.
static func _freeze(v: Variant) -> void:
	if v is Dictionary:
		for k in v:
			_freeze(v[k])
		(v as Dictionary).make_read_only()
	elif v is Array:
		for x in v:
			_freeze(x)
		(v as Array).make_read_only()


# ------------------------------------------------------------------ symmetry

static func margin_for(w: float, h: float) -> float:
	return snappedf(37.4 * minf(w, h) / 792.0, 0.1)


static func image_point(sym: String, w: float, h: float, p: Vector2) -> Vector2:
	match sym:
		"mirror_x":
			return Vector2(w - p.x, p.y)
		"mirror_y":
			return Vector2(p.x, h - p.y)
		"mirror_anti":
			return Vector2(w - p.y, h - p.x)
	return Vector2(w - p.x, h - p.y)


static func image_vector(sym: String, v: Vector2) -> Vector2:
	match sym:
		"mirror_x":
			return Vector2(-v.x, v.y)
		"mirror_y":
			return Vector2(v.x, -v.y)
		"mirror_anti":
			return Vector2(-v.y, -v.x)
	return -v


static func _snap(v: float) -> float:
	return snappedf(v, 0.1)


# Image of an obstacle / hazard dictionary: shape, vectors and jump target.
static func image_item(sym: String, w: float, h: float, item: Dictionary) -> Dictionary:
	var out: Dictionary = item.duplicate(true)
	if str(item.get("shape", "rect")) == "circle" or not item.has("w"):
		var c: Vector2 = image_point(sym, w, h, Vector2(float(item.x), float(item.y)))
		out.x = _snap(c.x)
		out.y = _snap(c.y)
	else:
		var a: Vector2 = image_point(sym, w, h, Vector2(float(item.x), float(item.y)))
		var b: Vector2 = image_point(sym, w, h, Vector2(float(item.x) + float(item.w), float(item.y) + float(item.h)))
		out.x = _snap(minf(a.x, b.x))
		out.y = _snap(minf(a.y, b.y))
		out.w = _snap(absf(b.x - a.x))
		out.h = _snap(absf(b.y - a.y))
	for key in ["directionA", "directionB", "exitFacing"]:
		if item.has(key):
			var v: Vector2 = image_vector(sym, Vector2(float(item[key].x), float(item[key].y)))
			out[key] = {"x": _snap(v.x), "y": _snap(v.y)}
	if item.has("target"):
		var t: Vector2 = image_point(sym, w, h, Vector2(float(item.target.x), float(item.target.y)))
		out.target = {"x": _snap(t.x), "y": _snap(t.y)}
	return out


static func same_geometry(a: Dictionary, b: Dictionary) -> bool:
	for key in ["x", "y", "w", "h", "radius"]:
		if absf(float(a.get(key, 0.0)) - float(b.get(key, 0.0))) > 0.05:
			return false
	for key in ["directionA", "directionB", "exitFacing", "target"]:
		if a.has(key) != b.has(key):
			return false
		if a.has(key) and (absf(float(a[key].x) - float(b[key].x)) > 0.05 or absf(float(a[key].y) - float(b[key].y)) > 0.05):
			return false
	return true


class Layout extends RefCounted:
	var w: float
	var h: float
	var sym: String
	var obstacles: Array = []
	var hazards: Array = []
	var forests: Array = []
	var blue: Array = []
	var red: Array = []
	var twin_of: Dictionary = {}
	var _patch: int = 0

	func _init(width: float, height: float, symmetry: String) -> void:
		w = width
		h = height
		sym = symmetry

	func obstacle(o: Dictionary) -> void:
		_add(obstacles, o)

	func hazard(hz: Dictionary) -> void:
		_add(hazards, hz)

	func _add(list: Array, item: Dictionary) -> void:
		var ids: PackedStringArray = str(item.id).split("|")
		var a: Dictionary = item.duplicate(true)
		a.id = ids[0]
		var b: Dictionary = ArenaData.image_item(sym, w, h, a)
		if ArenaData.same_geometry(a, b):
			if ids.size() > 1:
				push_error("ArenaData: self-symmetric piece authored as a pair: " + str(item.id))
			list.append(a)
			return
		if ids.size() < 2:
			push_error("ArenaData: asymmetric piece needs a twin id: " + str(item.id))
			return
		b.id = ids[1]
		if a.has("pairId"):
			b["_pair_of"] = str(a.pairId)
		twin_of[a.id] = b.id
		twin_of[b.id] = a.id
		list.append(a)
		list.append(b)

	# Brush patch from overlapping canopy circles [[x, y, r], ...]. The image
	# patch is added unless the circle set maps onto itself.
	func brush(circles: Array) -> void:
		var own: Array = []
		var img: Array = []
		for c in circles:
			own.append(Vector3(float(c[0]), float(c[1]), float(c[2])))
			var p: Vector2 = ArenaData.image_point(sym, w, h, Vector2(float(c[0]), float(c[1])))
			img.append(Vector3(ArenaData._snap(p.x), ArenaData._snap(p.y), float(c[2])))
		var self_symmetric: bool = true
		for v: Vector3 in img:
			var found: bool = false
			for q: Vector3 in own:
				if v.distance_to(q) < 0.05:
					found = true
					break
			if not found:
				self_symmetric = false
				break
		var pa: int = _patch
		_patch += 1
		for v: Vector3 in own:
			forests.append({"x": v.x, "y": v.y, "radius": v.z, "patch": pa})
		if not self_symmetric:
			var pb: int = _patch
			_patch += 1
			for v: Vector3 in img:
				forests.append({"x": v.x, "y": v.y, "radius": v.z, "patch": pb})

	# Blue slots in order; red slot i is the image of blue slot i.
	func spawns(points: Array) -> void:
		for p in points:
			blue.append({"x": float(p[0]), "y": float(p[1])})
			var q: Vector2 = ArenaData.image_point(sym, w, h, Vector2(float(p[0]), float(p[1])))
			red.append({"x": ArenaData._snap(q.x), "y": ArenaData._snap(q.y)})

	func finish(meta: Dictionary) -> Dictionary:
		for hz: Dictionary in hazards:
			if hz.has("_pair_of"):
				hz.pairId = str(twin_of.get(str(hz._pair_of), ""))
				hz.erase("_pair_of")
		var m: float = ArenaData.margin_for(w, h)
		var d: Dictionary = meta.duplicate(true)
		d.width = w
		d.height = h
		d.bounds = {"minX": m, "maxX": ArenaData._snap(w - m), "minY": m, "maxY": ArenaData._snap(h - m)}
		d.symmetry = sym
		d.spawns = {"blue": blue, "red": red}
		d.obstacles = obstacles
		d.hazards = hazards
		d.forests = forests
		return d


# ------------------------------------------------------------------ pieces

static func _wall(id: String, x: float, y: float, w: float, h: float, color: String, kind: String = "wall", material: String = "stone") -> Dictionary:
	return {"id": id, "shape": "rect", "x": x, "y": y, "w": w, "h": h, "kind": kind, "material": material,
		"blocksUnits": true, "blocksProjectiles": true, "blocksVision": true, "color": color}


static func _pillar(id: String, x: float, y: float, r: float, color: String, kind: String = "pillar") -> Dictionary:
	return {"id": id, "shape": "circle", "x": x, "y": y, "radius": r, "kind": kind, "material": "stone",
		"blocksUnits": true, "blocksProjectiles": true, "blocksVision": true, "color": color}


# Low see-through barrier (iron lattice, thorn thicket): blocks bodies only.
# Sight and projectiles cross it, so both sides can fight across it instead of
# parking out of reach (V1.5.3 stalemate rule).
static func _screen(id: String, x: float, y: float, w: float, h: float, color: String, kind: String = "lattice") -> Dictionary:
	return {"id": id, "shape": "rect", "x": x, "y": y, "w": w, "h": h, "kind": kind, "material": "iron" if kind == "lattice" else "wood",
		"blocksUnits": true, "blocksProjectiles": false, "blocksVision": false, "color": color}


# Chasm / ravine / water: blocks bodies only. Sight and projectiles cross it.
static func _chasm(id: String, x: float, y: float, w: float, h: float, color: String, material: String) -> Dictionary:
	return {"id": id, "shape": "rect", "x": x, "y": y, "w": w, "h": h, "kind": "chasm", "material": material,
		"blocksUnits": true, "blocksProjectiles": false, "blocksVision": false, "color": color}


# Timed gate (DESIGN_153 §1.3). Every gate of one map shares the same cycle
# numbers; the engine shifts group B by half a period so A and B alternate.
static func _gate(id: String, x: float, y: float, w: float, h: float, group: String, cycle: Array, color: String) -> Dictionary:
	var g: Dictionary = _wall(id, x, y, w, h, color, "gate", "iron")
	g.gate = {"group": group, "period": float(cycle[0]), "openDuration": float(cycle[1]), "warningDuration": float(cycle[2]), "phase": float(cycle[3])}
	return g


static func _circle_hazard(id: String, type: String, label: String, x: float, y: float, r: float, color: String, params: Dictionary) -> Dictionary:
	var d: Dictionary = {"id": id, "label": label, "type": type, "shape": "circle", "x": x, "y": y, "radius": r, "color": color}
	d.merge(params)
	return d


static func _rect_hazard(id: String, type: String, label: String, x: float, y: float, w: float, h: float, color: String, params: Dictionary) -> Dictionary:
	var d: Dictionary = {"id": id, "label": label, "type": type, "shape": "rect", "x": x, "y": y, "w": w, "h": h, "color": color}
	d.merge(params)
	return d


static func _jump_pad(id: String, x: float, y: float, r: float, tx: float, ty: float, flight: float, cooldown: float) -> Dictionary:
	return {"id": id, "label": "도약 발판", "type": "jump_pad", "shape": "circle", "x": x, "y": y, "radius": r,
		"target": {"x": tx, "y": ty}, "flightTime": flight, "cooldown": cooldown, "color": "#7fe3ff"}


static func _portal(id: String, x: float, y: float, r: float, pair: String, exit: Vector2, cooldown: float) -> Dictionary:
	return {"id": id, "label": "차원 포탈", "type": "portal", "shape": "circle", "x": x, "y": y, "radius": r,
		"pairId": pair, "exitFacing": {"x": exit.x, "y": exit.y}, "cooldown": cooldown, "color": "#a98cff"}


static func _haste(id: String, x: float, y: float, r: float, mult: float, duration: float) -> Dictionary:
	return _circle_hazard(id, "haste", "가속 구역", x, y, r, "#64e8f0", {"speedMultiplier": mult, "duration": duration, "refreshInterval": 0.5})


static func _fountain(id: String, x: float, y: float, r: float, heal: float, cooldown: float, min_missing: float) -> Dictionary:
	return _circle_hazard(id, "healing_fountain", "공용 회복 샘", x, y, r, "#65ecc1", {"healPercent": heal, "cooldown": cooldown, "minMissingPercent": min_missing})


static func _ring(id: String, x: float, y: float, start_t: float, end_t: float, start_r: float, end_r: float, percent: float, tick: float) -> Dictionary:
	# Standard shape keys describe the zone at startTime; semantics use the ring keys.
	return {"id": id, "label": "결계 수축", "type": "closing_ring", "shape": "circle", "x": x, "y": y, "radius": start_r,
		"startTime": start_t, "endTime": end_t, "startRadius": start_r, "endRadius": end_r,
		"damagePercent": percent, "tickInterval": tick, "color": "#d98bff"}


static func _landmark(id: String, label: String, x: float, y: float, radius: float, kind: String = "plaza") -> Dictionary:
	return {"id": id, "label": label, "x": x, "y": y, "radius": radius, "kind": kind}


# ------------------------------------------------------------------ maps

# 1. Open baseline. Unchanged reference arena (1408x792, west/east, no terrain).
static func _classic() -> Dictionary:
	var L := Layout.new(1408.0, 792.0, "mirror_x")
	L.spawns([[165, 396], [198, 272.8], [198, 519.2], [140.8, 193.6], [140.8, 598.4]])
	return L.finish({"id": "classic", "name": "표준 원형장", "subtitle": "개방형 기준 전장",
		"description": "장애물과 환경 효과 없이 사거리·기동·조합의 차이를 그대로 비교하는 기준 전장입니다.",
		"accent": "#70b9ff", "difficulty": "기준", "icon": "◎", "tags": ["개방", "기준", "동서 출발"],
		"tacticalNotes": ["엄폐물이 없어 사거리와 진형 차이가 그대로 드러납니다.",
			"원거리 영웅은 거리를 벌리기 쉽고, 근접 영웅은 돌진기로 파고들어야 합니다."],
		"floor": {"base": "#071019", "blue": "#173f68", "red": "#642b3d", "grid": "#9bb5c9"},
		"layout_id": "training_open", "archetype": "open_baseline", "spawn_orientation": "west_east",
		"landmarks": [_landmark("training", "기준 교전 구역", 704, 396, 140)]})


# 2. Gated fortress (1600x896, west/east). The keep has four gates: the
# team-facing pair (A) and the north/south pair (B) open in turns.
static func _ruined_gate() -> Dictionary:
	var L := Layout.new(1600.0, 896.0, "mirror_x")
	var stone: String = "#6b6152"
	var lattice: String = "#9a8a6c"
	var gate_col: String = "#b08850"
	var cycle: Array = [11.0, 4.5, 1.2, 1.5]
	# Narrow keep: its two gate faces are ~300 px apart, so teams held at the
	# faces still see and reach each other through the lattice.
	L.obstacle(_wall("tower_nw|tower_ne", 660, 238, 60, 60, stone, "wall"))
	L.obstacle(_wall("tower_sw|tower_se", 660, 598, 60, 60, stone, "wall"))
	# Broken side passages stay open through the all-closed part of the cycle.
	# 72 px leaves room for the largest hero (diameter 56) on both mirrored sides.
	L.obstacle(_screen("lattice_wn|lattice_en", 668, 370, 28, 23, lattice))
	L.obstacle(_screen("lattice_ws|lattice_es", 668, 503, 28, 23, lattice))
	L.obstacle(_gate("gate_west|gate_east", 668, 393, 28, 110, "A", cycle, gate_col))
	L.obstacle(_gate("gate_north", 720, 248, 160, 28, "B", cycle, gate_col))
	L.obstacle(_gate("gate_south", 720, 620, 160, 28, "B", cycle, gate_col))
	L.obstacle(_wall("ruin_nw|ruin_ne", 318, 168, 150, 40, stone, "ruin"))
	L.obstacle(_wall("ruin_sw|ruin_se", 318, 688, 150, 40, stone, "ruin"))
	L.obstacle(_pillar("rubble_w|rubble_e", 456, 448, 30, "#7a6e5c"))
	L.hazard(_circle_hazard("keep_pulse", "shockwave", "성채 충격파", 800, 448, 96, "#f4ba76",
		{"period": 9.5, "activeDuration": 1.4, "warningDuration": 1.6, "phase": 2.2, "ringWidth": 24.0, "damage": 36.0, "school": "magic", "knockback": 40.0}))
	L.hazard(_haste("rampart_north", 800, 150, 46, 1.3, 1.4))
	L.hazard(_haste("rampart_south", 800, 746, 46, 1.3, 1.4))
	L.spawns([[170, 448], [205, 338], [205, 558], [140, 238], [140, 658]])
	return L.finish({"id": "ruined_gate", "name": "붕괴한 성문", "subtitle": "개폐 성문 성채 · 교대로 열리는 네 문",
		"description": "전장 한가운데 성채가 있고 네 개폐 성문이 짝을 지어 번갈아 열립니다. 동서 문이 열리면 성채를 곧장 가로지르고, 문이 모두 닫힌 동안에도 무너진 측면 통로로 우회할 수 있습니다.",
		"accent": "#c7a47b", "difficulty": "성채", "icon": "▥", "tags": ["개폐 성문", "성채", "충격파", "동서 출발"],
		"tacticalNotes": ["동서 성문과 남북 성문은 번갈아 열립니다. 문이 닫히기 직전에는 경고가 표시되니 문 안에 머물지 않습니다.",
			"성채 벽의 격자 구간은 이동만 막고 시야와 투사체는 통과합니다. 양쪽 탑 아래의 무너진 통로는 항상 열려 있어 안뜰에 갇히지 않습니다.",
			"성채 중앙 충격파는 바깥으로 퍼지는 고리입니다. 외곽 성벽 아래 가속 구역으로 우회할 수 있습니다."],
		"floor": {"base": "#10100f", "blue": "#334555", "red": "#593b3d", "grid": "#b6ad9d"},
		"layout_id": "gated_fortress_keep", "archetype": "gated_fortress", "spawn_orientation": "west_east",
		"landmarks": [_landmark("keep", "성채 안뜰", 800, 448, 100), _landmark("north_rampart", "북쪽 성벽길", 800, 150, 80, "lane"),
			_landmark("south_rampart", "남쪽 성벽길", 800, 746, 80, "lane")]})


# 3. Loop circuit (1296x912, NW/SE corners). A see-through thorn hedge runs
# diagonally from the NE bend to the SW bend with a spiked gap in its middle:
# three crossings (short spiked gap, two long open bends), both ways round
# equal. The hedge is thin across the team axis; the V1.5.3 draft had a 470 px
# deep thicket there and both teams parked out of range on either side.
static func _thorn_circuit() -> Dictionary:
	var L := Layout.new(1296.0, 912.0, "point")
	var hedge: String = "#5f7a45"
	# Overlapping 150x110 blocks stepping roughly (112, -79); the central block
	# is left out, so the centre is a diagonal gap about 117 px wide.
	L.obstacle(_screen("thorn_ne1|thorn_sw1", 697, 314, 150, 110, hedge, "hedge"))
	L.obstacle(_screen("thorn_ne2|thorn_sw2", 797, 243, 150, 110, hedge, "hedge"))
	L.obstacle(_screen("thorn_ne3|thorn_sw3", 909, 164, 150, 110, hedge, "hedge"))
	L.obstacle(_pillar("stump_n|stump_s", 520, 250, 26, "#5c5140"))
	L.obstacle(_pillar("stump_w|stump_e", 300, 470, 26, "#5c5140"))
	L.obstacle(_pillar("boulder_ne|boulder_sw", 1150, 150, 40, "#6a6a5a"))
	var spike: Dictionary = {"period": 4.2, "activeDuration": 1.3, "warningDuration": 0.8, "damage": 34.0, "school": "physical",
		"slow": 0.25, "slowDuration": 0.8, "tickInterval": 0.5}
	var gap: Dictionary = spike.duplicate()
	gap.phase = 0.0
	var pocket: Dictionary = spike.duplicate()
	pocket.phase = 2.1
	L.hazard(_rect_hazard("spikes_gap", "spikes", "가시 틈", 588, 411, 120, 90, "#e1b45f", gap))
	# Step pocket on the north-west face; its image sits on the south-east face.
	L.hazard(_rect_hazard("spikes_nw_pocket|spikes_se_pocket", "spikes", "가시 함정", 697, 243, 100, 71, "#e1b45f", pocket))
	L.hazard(_haste("sprint_ne|sprint_sw", 1150, 330, 44, 1.28, 1.6))
	L.brush([[1110, 420, 58], [1170, 450, 46]])
	L.spawns([[150, 160], [262, 108], [108, 272], [372, 100], [196, 300]])
	return L.finish({"id": "thorn_circuit", "name": "가시 순환로", "subtitle": "사선 가시 덤불 · 가운데 가시 틈",
		"description": "북서와 남동 모서리에서 출발해 전장을 비스듬히 가로지르는 가시 덤불을 넘나드는 순환로입니다. 덤불 가운데의 가시 틈으로 곧장 건너거나, 덤불 양 끝의 북동·남서 굽이로 돌아 들어갑니다.",
		"accent": "#d7a85a", "difficulty": "순환로", "icon": "▲", "tags": ["순환로", "가시 함정", "수풀", "대각선 출발"],
		"tacticalNotes": ["가시 덤불은 이동만 막고 시야와 투사체는 통과합니다. 덤불 너머로 견제하며 가운데 틈과 두 굽이 중 건널 곳을 고릅니다.",
			"가운데 틈의 가시와 덤불에 붙은 오목한 자리의 가시는 반 주기씩 엇갈려 솟습니다. 틈의 가시가 가라앉은 순간이 가장 빠른 진입 시점입니다.",
			"북동·남서 굽이는 멀지만 안전합니다. 굽이의 수풀과 가속 구역은 측면 기습에 쓰입니다."],
		"floor": {"base": "#10120d", "blue": "#354b39", "red": "#57433b", "grid": "#b2b98f"},
		"layout_id": "thorn_loop_diagonal", "archetype": "loop_circuit", "spawn_orientation": "diagonal",
		"landmarks": [_landmark("gap", "가운데 가시 틈", 648, 456, 90), _landmark("ne_bend", "북동 굽이", 1150, 250, 90, "lane"),
			_landmark("sw_bend", "남서 굽이", 146, 662, 90, "lane")]})


# 4. Lava bridges with jump pads (1344x1072, north/south). A molten chasm
# splits the basin; two bridges carry alternating eruption vents. Each team
# has a pad on both outer rims that leaps the chasm diagonally and lands in
# front of the enemy centre. Pads sit on the flanks so no link reaches the
# enemy spawn faster than the bridges (link path >= 900, tests/maps_153).
static func _furnace_basin() -> Dictionary:
	var L := Layout.new(1344.0, 1072.0, "mirror_y")
	var molten: String = "#5a2416"
	L.obstacle(_chasm("molten_west", 50.6, 466, 319.4, 140, molten, "lava"))
	L.obstacle(_chasm("molten_mid", 490, 466, 364, 140, molten, "lava"))
	L.obstacle(_chasm("molten_east", 974, 466, 319.4, 140, molten, "lava"))
	L.obstacle(_pillar("basalt_nw|basalt_sw", 300, 318, 32, "#4d3a33"))
	L.obstacle(_pillar("basalt_ne|basalt_se", 1044, 318, 32, "#4d3a33"))
	L.hazard(_circle_hazard("lava_north|lava_south", "lava", "용암 웅덩이", 672, 432, 44, "#ff6b3a",
		{"alwaysActive": true, "damage": 34.0, "tickInterval": 0.5, "school": "magic"}))
	var vent: Dictionary = {"period": 8.0, "activeDuration": 0.8, "warningDuration": 1.4, "damage": 42.0, "knockback": 55.0, "school": "magic"}
	var vent_w: Dictionary = vent.duplicate()
	vent_w.phase = 1.0
	var vent_e: Dictionary = vent.duplicate()
	vent_e.phase = 5.0
	L.hazard(_circle_hazard("bridge_vent_west", "eruption", "다리 분출구", 430, 536, 62, "#ffc166", vent_w))
	L.hazard(_circle_hazard("bridge_vent_east", "eruption", "다리 분출구", 914, 536, 62, "#ffc166", vent_e))
	L.hazard(_jump_pad("leap_nw|leap_sw", 150, 404, 30, 560, 704, 1.0, 2.5))
	L.hazard(_jump_pad("leap_ne|leap_se", 1194, 404, 30, 784, 704, 1.0, 2.5))
	L.spawns([[672, 125], [560, 150], [784, 150], [450, 118], [894, 118]])
	return L.finish({"id": "furnace_basin", "name": "용광로 분지", "subtitle": "용암 협곡 · 두 다리와 측면 도약",
		"description": "동서로 흐르는 용암 협곡이 분지를 남북으로 가릅니다. 분출구가 번갈아 솟는 두 다리로 건너거나, 협곡 양 끝의 도약 발판으로 협곡을 비스듬히 뛰어넘어 상대 진영 앞에 내려섭니다.",
		"accent": "#ff8a4c", "difficulty": "용암 다리", "icon": "◉", "tags": ["용암 협곡", "도약 발판", "분출구", "남북 출발"],
		"tacticalNotes": ["용암 협곡은 걸어서 건널 수 없지만 시야와 투사체는 통과합니다. 원거리 영웅은 협곡 너머로 견제합니다.",
			"협곡 가운데 가장자리의 용암 웅덩이는 항상 활성입니다. 다리 분출구는 서쪽과 동쪽이 4초 간격으로 번갈아 터집니다.",
			"협곡 양 끝의 도약 발판은 한 방향으로만 날아가 상대 진영 앞 중앙에 내려 줍니다. 다리를 지키는 적의 옆을 찌를 때 아군과 함께 넘어갑니다."],
		"floor": {"base": "#150c09", "blue": "#3a2f45", "red": "#5a2a22", "grid": "#c9865a"},
		"layout_id": "molten_chasm_bridges", "archetype": "lava_bridges", "spawn_orientation": "north_south",
		"landmarks": [_landmark("west_bridge", "서쪽 다리", 430, 536, 90, "lane"), _landmark("east_bridge", "동쪽 다리", 914, 536, 90, "lane"),
			_landmark("molten_rim", "용암 협곡 중앙", 672, 536, 120)]})


# 5. Wind aperture (1376x1024, NE/SW corners). Four offset temple slabs ring
# the sanctum; tangential winds circle it and reverse every half period.
static func _wind_temple() -> Dictionary:
	var L := Layout.new(1376.0, 1024.0, "point")
	var slab: String = "#4f6f6c"
	L.obstacle(_wall("slab_north|slab_south", 548, 330, 240, 36, slab))
	L.obstacle(_wall("slab_east|slab_west", 870, 380, 36, 240, slab))
	L.obstacle(_pillar("shrine_ne|shrine_sw", 1010, 300, 30, "#5d7a77"))
	L.obstacle(_pillar("shrine_nw|shrine_se", 330, 250, 34, "#5d7a77"))
	L.obstacle(_pillar("shrine_n|shrine_s", 668, 150, 28, "#5d7a77"))
	var wind: Dictionary = {"period": 8.0, "phase": 0.0, "activeDuration": 8.0, "force": 70.0}
	var wn: Dictionary = wind.duplicate()
	wn.directionA = {"x": -1.0, "y": 0.0}
	wn.directionB = {"x": 1.0, "y": 0.0}
	var we: Dictionary = wind.duplicate()
	we.directionA = {"x": 0.0, "y": -1.0}
	we.directionB = {"x": 0.0, "y": 1.0}
	L.hazard(_rect_hazard("gust_north|gust_south", "wind", "회랑 횡풍", 548, 250, 240, 80, "#6ae0dd", wn))
	L.hazard(_rect_hazard("gust_east|gust_west", "wind", "회랑 횡풍", 906, 380, 80, 240, "#6ae0dd", we))
	L.hazard(_fountain("spring_nw|spring_se", 230, 210, 58, 0.14, 21.0, 0.06))
	L.spawns([[1180, 190], [1090, 140], [1240, 290], [980, 110], [1268, 400]])
	return L.finish({"id": "wind_temple", "name": "풍절 사원", "subtitle": "회오리 성소 · 대각선 출발",
		"description": "네 석판이 비껴 선 성소를 횡풍이 한 방향으로 휘감습니다. 바람은 반 주기마다 거꾸로 돌고, 북서와 남동 모서리의 회복 샘을 두 팀이 함께 씁니다.",
		"accent": "#6ae0dd", "difficulty": "회오리", "icon": "≋", "tags": ["회오리 성소", "횡풍", "회복 샘", "대각선 출발"],
		"tacticalNotes": ["석판 사이의 비스듬한 틈으로 성소에 들어갑니다. 바람을 등지면 빠르게, 거스르면 느리게 돕니다.",
			"네 횡풍은 같은 방향으로 성소를 돌고 4초마다 방향을 바꿉니다. 가벼운 영웅일수록 크게 밀립니다.",
			"회복 샘은 북서·남동 중립 모서리에 있으며 두 팀이 충전량을 공유합니다."],
		"floor": {"base": "#081413", "blue": "#1d4b5a", "red": "#56323f", "grid": "#8fd6cf"},
		"layout_id": "wind_aperture_sanctum", "archetype": "wind_aperture", "spawn_orientation": "diagonal",
		"landmarks": [_landmark("sanctum", "회오리 성소", 688, 512, 120), _landmark("spring_nw", "북서 샘터", 230, 210, 80, "supply"),
			_landmark("spring_se", "남동 샘터", 1146, 814, 80, "supply")]})


# 6. Islands with portals (1472x1040, north/south). Void chasms split five
# platforms; bridges link homes to the flank islands, portals link home and core.
static func _dimensional_lattice() -> Dictionary:
	var L := Layout.new(1472.0, 1040.0, "point")
	var void_col: String = "#1b1233"
	L.obstacle(_chasm("void_nw|void_se", 49.1, 300, 100.9, 80, void_col, "void"))
	L.obstacle(_chasm("void_north_a|void_south_a", 270, 300, 570, 80, void_col, "void"))
	L.obstacle(_chasm("void_north_b|void_south_b", 940, 300, 262, 80, void_col, "void"))
	L.obstacle(_chasm("void_ne|void_sw", 1322, 300, 100.9, 80, void_col, "void"))
	L.obstacle(_chasm("void_wn|void_es", 440, 380, 80, 85, void_col, "void"))
	L.obstacle(_chasm("void_ws|void_en", 440, 575, 80, 85, void_col, "void"))
	L.obstacle(_pillar("crystal_n|crystal_s", 736, 240, 30, "#5b4a8a"))
	L.obstacle(_pillar("crystal_w|crystal_e", 250, 440, 28, "#5b4a8a"))
	L.hazard(_portal("rift_home_n|rift_home_s", 1150, 215, 34, "rift_core_n", Vector2(0, -1), 2.5))
	L.hazard(_portal("rift_core_n|rift_core_s", 575, 415, 32, "rift_home_n", Vector2(1, 0), 2.5))
	L.hazard(_circle_hazard("core_well", "gravity", "핵 중력 우물", 736, 520, 86, "#b395ff",
		{"period": 10.5, "activeDuration": 2.2, "warningDuration": 1.5, "phase": 4.5, "force": 110.0, "damage": 7.0, "tickInterval": 0.5, "school": "magic"}))
	L.hazard(_haste("drift_west|drift_east", 245, 560, 42, 1.24, 1.5))
	L.spawns([[736, 120], [620, 150], [852, 150], [500, 112], [972, 112]])
	return L.finish({"id": "dimensional_lattice", "name": "차원 격자", "subtitle": "허공 위 다섯 섬 · 포탈 연결",
		"description": "허공이 다섯 섬을 가릅니다. 본진 섬은 비껴 놓인 좁은 다리로 가운데 중력 우물 섬과, 모서리 다리로 양옆 섬과 이어지며, 포탈을 타면 가운데 섬으로 곧장 넘어갑니다.",
		"accent": "#a98cff", "difficulty": "포탈 섬", "icon": "∞", "tags": ["허공 섬", "포탈", "중력 우물", "남북 출발"],
		"tacticalNotes": ["허공은 걸어서 건널 수 없지만 시야와 투사체는 통과합니다. 섬 가장자리에서 건너편을 견제합니다.",
			"본진 포탈은 가운데 섬으로, 가운데 섬의 포탈은 해당 본진으로 돌아갑니다. 영웅마다 2.5초 재사용 대기시간이 있습니다.",
			"본진에서 가운데 섬으로 가는 다리는 한쪽으로 비껴 있어 곧장 건너지 못합니다. 가운데 섬은 중력 우물의 주기를 보고 들어갑니다."],
		"floor": {"base": "#0d0a18", "blue": "#26306a", "red": "#5a2a55", "grid": "#a58cff"},
		"layout_id": "void_islands_portals", "archetype": "portal_islands", "spawn_orientation": "north_south",
		"landmarks": [_landmark("core", "핵 섬", 736, 520, 120), _landmark("west_isle", "서쪽 섬", 245, 520, 90, "lane"),
			_landmark("east_isle", "동쪽 섬", 1227, 520, 90, "lane")]})


# 7. Cover maze (1536x800, west/east). Many short walls and pillars, brush in
# the alleys and a closing ring that pulls the hunt into the centre.
static func _crossroads() -> Dictionary:
	var L := Layout.new(1536.0, 800.0, "point")
	var wall: String = "#56657a"
	L.obstacle(_wall("maze_a1|maze_a2", 346, 92, 28, 112, wall))
	L.obstacle(_wall("maze_b1|maze_b2", 346, 330, 28, 140, wall))
	L.obstacle(_wall("maze_c1|maze_c2", 346, 596, 28, 112, wall))
	L.obstacle(_wall("maze_d1|maze_d2", 452, 210, 116, 28, wall))
	L.obstacle(_wall("maze_e1|maze_e2", 452, 562, 116, 28, wall))
	L.obstacle(_pillar("maze_f1|maze_f2", 520, 400, 26, "#66778c"))
	L.obstacle(_wall("maze_g1|maze_g2", 640, 88, 28, 124, wall))
	L.obstacle(_wall("maze_h1|maze_h2", 640, 588, 28, 124, wall))
	L.obstacle(_pillar("maze_i1|maze_i2", 660, 300, 24, "#66778c"))
	L.obstacle(_pillar("maze_j1|maze_j2", 660, 500, 24, "#66778c"))
	L.obstacle(_wall("maze_k1|maze_k2", 736, 206, 64, 28, wall))
	L.brush([[455, 140, 52], [505, 128, 44]])
	L.brush([[590, 470, 50], [612, 520, 40]])
	L.hazard(_circle_hazard("maze_sink", "gravity", "교차로 중력 우물", 768, 400, 78, "#b395ff",
		{"period": 11.0, "activeDuration": 1.8, "warningDuration": 1.5, "phase": 5.0, "force": 100.0, "damage": 5.0, "tickInterval": 0.5, "school": "magic"}))
	L.hazard(_ring("maze_seal", 768, 400, 40.0, 100.0, 900.0, 240.0, 2.5, 0.5))
	L.spawns([[165, 400], [200, 290], [200, 510], [140, 180], [140, 620]])
	return L.finish({"id": "crossroads", "name": "교차 회랑", "subtitle": "엄폐 미로 · 결계 수축",
		"description": "짧은 벽과 기둥이 촘촘한 미로 회랑입니다. 골목의 수풀에 숨어 기습할 수 있지만, 결계가 줄어들면 모두 가운데 교차로로 모여야 합니다.",
		"accent": "#86c1ff", "difficulty": "엄폐 미로", "icon": "╬", "tags": ["엄폐 미로", "수풀", "결계 수축", "동서 출발"],
		"tacticalNotes": ["벽이 짧고 많아 시야가 자주 끊깁니다. 모서리마다 매복과 추격이 반복됩니다.",
			"수풀 안의 영웅은 가까이 다가가거나 교전하기 전까지 밖에서 보이지 않습니다.",
			"40초부터 결계가 줄어들어 100초에 중앙만 남습니다. 결계 밖에서는 최대 체력 비례 피해를 받습니다."],
		"floor": {"base": "#0b0f16", "blue": "#1f3e5e", "red": "#5b2f3a", "grid": "#9fb3c9"},
		"layout_id": "cover_maze_ring", "archetype": "cover_maze", "spawn_orientation": "west_east",
		"landmarks": [_landmark("junction", "중앙 교차로", 768, 400, 110), _landmark("north_alley", "북쪽 골목", 520, 140, 70, "lane"),
			_landmark("south_alley", "남쪽 골목", 1016, 660, 70, "lane")]})


# 8. Three lanes with brush (1760x736, west/east). Two garden walls split the
# long garden into lanes with two crossings each; brush sits in the side lanes.
static func _moon_garden() -> Dictionary:
	var L := Layout.new(1760.0, 736.0, "mirror_x")
	var hedge: String = "#3f6150"
	L.obstacle(_wall("wall_nw|wall_ne", 360, 228, 270, 30, hedge))
	L.obstacle(_wall("wall_n_mid", 750, 228, 260, 30, hedge))
	L.obstacle(_wall("wall_sw|wall_se", 360, 478, 270, 30, hedge))
	L.obstacle(_wall("wall_s_mid", 750, 478, 260, 30, hedge))
	L.obstacle(_pillar("lantern_w|lantern_e", 690, 368, 26, "#6b8a7a"))
	L.obstacle(_pillar("stone_nw|stone_ne", 250, 120, 26, "#6b8a7a"))
	L.obstacle(_pillar("stone_sw|stone_se", 250, 616, 26, "#6b8a7a"))
	L.brush([[560, 128, 62], [626, 120, 50]])
	L.brush([[560, 608, 62], [626, 616, 50]])
	L.hazard(_fountain("moon_well", 880, 368, 58, 0.16, 20.0, 0.05))
	L.hazard(_haste("moonpath_nw|moonpath_ne", 420, 132, 40, 1.22, 1.8))
	L.hazard(_haste("moonpath_sw|moonpath_se", 420, 604, 40, 1.22, 1.8))
	L.spawns([[160, 368], [195, 262], [195, 474], [140, 150], [140, 586]])
	return L.finish({"id": "moon_garden", "name": "월영 정원", "subtitle": "세 갈래 정원길 · 수풀 매복",
		"description": "긴 정원을 두 담장이 세 갈래 길로 나눕니다. 양옆 길의 수풀에 숨어 기습하고, 가운데 길의 공용 회복 샘을 차지하며, 담장 틈으로 길을 바꿉니다.",
		"accent": "#9be0c0", "difficulty": "세 갈래", "icon": "◌", "tags": ["세 갈래 길", "수풀", "회복 샘", "동서 출발"],
		"tacticalNotes": ["담장마다 틈이 두 곳 있어 가운데 길과 양옆 길을 오갈 수 있습니다.",
			"양옆 길의 수풀 안에 있는 영웅은 가까이 다가가기 전까지 보이지 않습니다. 수풀을 먼저 확인하고 지나갑니다.",
			"가운데 회복 샘은 두 팀이 충전량을 공유합니다. 양옆 길 입구의 가속 구역으로 빠르게 돌아 들어갈 수 있습니다."],
		"floor": {"base": "#0a1110", "blue": "#1b4450", "red": "#4d3043", "grid": "#a8d8c4"},
		"layout_id": "three_lane_garden", "archetype": "three_lanes", "spawn_orientation": "west_east",
		"landmarks": [_landmark("moon_well", "달빛 샘", 880, 368, 90, "supply"), _landmark("north_path", "북쪽 정원길", 880, 130, 80, "lane"),
			_landmark("south_path", "남쪽 정원길", 880, 606, 80, "lane")]})


# 9. Artillery plaza with bunkers (1344x976, NW/SE corners). The open plaza is
# shelled on a telegraphed salvo; L-shaped bunkers are the only cover.
static func _twin_foundry() -> Dictionary:
	var L := Layout.new(1344.0, 976.0, "point")
	var bunker: String = "#6c5a48"
	L.obstacle(_wall("foundry_ne|foundry_sw", 1030, 46.1, 267.9, 160, "#5d4a3a", "wall"))
	L.obstacle(_wall("bunker_nw_top|bunker_se_top", 440, 350, 90, 28, bunker))
	L.obstacle(_wall("bunker_nw_side|bunker_se_side", 440, 378, 28, 70, bunker))
	L.obstacle(_wall("bunker_ne_top|bunker_sw_top", 814, 350, 90, 28, bunker))
	L.obstacle(_wall("bunker_ne_side|bunker_sw_side", 876, 378, 28, 70, bunker))
	L.obstacle(_pillar("crucible_n|crucible_s", 672, 420, 26, "#7a5d44"))
	L.obstacle(_wall("crate_n|crate_s", 300, 330, 90, 30, bunker))
	L.hazard(_rect_hazard("plaza_barrage", "artillery", "포격 구역", 402, 318, 540, 340, "#ff8f6b",
		{"period": 9.0, "warningDuration": 1.6, "phase": 3.5, "count": 3, "radius": 72.0, "damage": 46.0, "school": "physical", "spread": 70.0}))
	L.hazard(_circle_hazard("foundry_vent_ne|foundry_vent_sw", "eruption", "주조로 분출구", 1000, 270, 64, "#ffc166",
		{"period": 7.0, "activeDuration": 0.9, "warningDuration": 1.3, "phase": 1.0, "damage": 38.0, "knockback": 48.0, "school": "magic"}))
	L.spawns([[150, 140], [262, 100], [110, 250], [372, 94], [100, 360]])
	return L.finish({"id": "twin_foundry", "name": "쌍둥이 주조소", "subtitle": "포격 광장 · 엄폐 벙커",
		"description": "두 주조소 사이의 넓은 광장에 주기적으로 포격이 떨어집니다. 포격은 하늘에서 떨어져 벽으로 막을 수 없으니 예고 원 밖으로 벗어나고, ㄱ자 벙커는 사격과 시야를 가리는 데 씁니다. 분출구가 쉬는 틈에는 주조소 옆길로 돌아갈 수 있습니다.",
		"accent": "#f0a860", "difficulty": "포격 광장", "icon": "◇", "tags": ["포격", "엄폐 벙커", "분출구", "대각선 출발"],
		"tacticalNotes": ["포격은 예고 원이 나타난 뒤 떨어지며 광장 안의 영웅 근처를 노립니다. 예고를 보고 벗어나면 피할 수 있습니다.",
			"ㄱ자 벙커는 광장 모서리에서 중앙을 향해 열려 있습니다. 벙커와 가운데 두 도가니는 사격과 시야를 가리지만 포격은 막지 못합니다.",
			"북동·남서 주조소 앞 분출구는 같은 주기로 터집니다. 광장을 피해 옆길로 돌 때 예고를 확인합니다."],
		"floor": {"base": "#13100c", "blue": "#2f3f52", "red": "#5b3a2e", "grid": "#d0a070"},
		"layout_id": "artillery_bunker_plaza", "archetype": "artillery_plaza", "spawn_orientation": "diagonal",
		"landmarks": [_landmark("plaza", "포격 광장", 672, 488, 150), _landmark("foundry_ne", "북동 주조소", 1000, 270, 80, "lane"),
			_landmark("foundry_sw", "남서 주조소", 344, 706, 80, "lane")]})


# 10. Twisting ravine with mud (1664x704, NW/SE corners). Two ravines force a
# Z-shaped route through muddy bends; one-way pads vault the first ravine.
static func _gale_corridor() -> Dictionary:
	var L := Layout.new(1664.0, 704.0, "point")
	L.obstacle(_chasm("ravine_west|ravine_east", 590, 33.2, 64, 440, "#16414a", "ravine"))
	L.obstacle(_pillar("rock_w|rock_e", 380, 470, 38, "#5d6f72"))
	L.obstacle(_pillar("rock_mid", 832, 352, 40, "#5d6f72"))
	L.obstacle(_pillar("rock_nw|rock_se", 850, 150, 30, "#5d6f72"))
	L.hazard(_rect_hazard("mire_west|mire_east", "mud", "진흙탕", 520, 500, 200, 140, "#8a6a45", {"slow": 0.35}))
	L.hazard(_rect_hazard("draft_west|draft_east", "wind", "협곡 돌풍", 180, 250, 300, 170, "#6ae0dd",
		{"period": 9.0, "phase": 0.0, "activeDuration": 9.0, "force": 60.0, "directionA": {"x": 0.0, "y": 1.0}, "directionB": {"x": 0.0, "y": -1.0}}))
	L.hazard(_jump_pad("vault_west|vault_east", 520, 170, 32, 740, 170, 0.9, 3.0))
	L.spawns([[150, 140], [260, 96], [110, 250], [362, 92], [100, 362]])
	return L.finish({"id": "gale_corridor", "name": "풍향 협곡", "subtitle": "Z자 골짜기 · 진흙 굽이",
		"description": "두 골짜기가 전장을 Z자로 꺾습니다. 굽이마다 진흙탕이 발을 붙잡고, 돌풍이 골짜기를 따라 불며, 도약 발판으로 첫 골짜기를 한 번에 넘을 수 있습니다.",
		"accent": "#7ad0dc", "difficulty": "굽이 협곡", "icon": "≋", "tags": ["Z자 골짜기", "진흙", "도약 발판", "대각선 출발"],
		"tacticalNotes": ["골짜기는 걸어서 건널 수 없지만 시야와 투사체는 통과합니다. 건너편 적을 보며 굽이로 돌아갑니다.",
			"굽이의 진흙탕은 머무는 동안 이동 속도를 35% 늦춥니다. 다른 둔화와는 가장 강한 효과 하나만 적용됩니다.",
			"도약 발판은 첫 골짜기 너머 가운데 구역으로 한 방향만 보냅니다. 돌풍은 4.5초마다 남북으로 방향을 바꿉니다."],
		"floor": {"base": "#0b1214", "blue": "#23465a", "red": "#4f3440", "grid": "#9fc7cf"},
		"layout_id": "z_ravine_mud_bends", "archetype": "twisting_ravine", "spawn_orientation": "diagonal",
		"landmarks": [_landmark("west_bend", "서쪽 굽이", 620, 570, 90, "lane"), _landmark("east_bend", "동쪽 굽이", 1044, 134, 90, "lane"),
			_landmark("gorge", "가운데 골", 832, 352, 110)]})


# 11. Split docks (1440x864, staggered). Each team starts on two docks split by
# a canal; a ferry portal joins the docks, the harbour centre holds cover.
static func _rift_harbor() -> Dictionary:
	var L := Layout.new(1440.0, 864.0, "point")
	var water: String = "#10324f"
	L.obstacle(_chasm("canal_west|canal_east", 40.8, 392, 380, 80, water, "water"))
	L.obstacle(_chasm("basin_north|basin_south", 560, 150, 60, 170, water, "water"))
	L.obstacle(_pillar("crane_n|crane_s", 720, 290, 34, "#5c6b7a"))
	L.obstacle(_wall("station", 680, 402, 80, 60, "#5c6b7a"))
	L.obstacle(_wall("crate_w|crate_e", 470, 560, 110, 30, "#5c6b7a"))
	L.hazard(_portal("ferry_nw|ferry_se", 330, 300, 32, "ferry_sw", Vector2(1, 0), 3.0))
	L.hazard(_portal("ferry_sw|ferry_ne", 330, 564, 32, "ferry_nw", Vector2(1, 0), 3.0))
	L.hazard(_haste("tide_north|tide_south", 880, 130, 42, 1.26, 1.3))
	L.brush([[480, 432, 58], [520, 400, 40]])
	L.brush([[640, 690, 56]])
	L.spawns([[150, 210], [160, 650], [255, 140], [270, 745], [120, 320]])
	return L.finish({"id": "rift_harbor", "name": "차원 정거장", "subtitle": "갈라진 부두 · 엇갈린 출발",
		"description": "두 팀 모두 운하로 갈린 두 부두에서 나뉘어 출발합니다. 나룻 포탈로 부두를 잇거나 앞으로 나아가 합류하며, 운하 어귀 갈대 수풀이 합류 지점을 가립니다.",
		"accent": "#72b6ff", "difficulty": "갈라진 부두", "icon": "▣", "tags": ["엇갈린 출발", "운하", "포탈", "수풀"],
		"tacticalNotes": ["한 팀이 두 부두로 나뉘어 출발합니다. 인원이 많은 부두는 상대의 인원이 적은 부두와 마주 봅니다.",
			"운하는 걸어서 건널 수 없지만 시야와 투사체는 통과합니다. 나룻 포탈은 같은 팀 쪽 두 부두만 잇습니다.",
			"운하 어귀의 갈대 수풀은 합류 지점을 가립니다. 수풀을 확인하지 않고 합류하면 기습을 받기 쉽습니다."],
		"floor": {"base": "#081018", "blue": "#1d4468", "red": "#56304a", "grid": "#8bb8e8"},
		"layout_id": "split_docks_canals", "archetype": "split_docks", "spawn_orientation": "split",
		"landmarks": [_landmark("station", "중앙 정거장", 720, 432, 110), _landmark("west_mouth", "서쪽 운하 어귀", 480, 432, 70, "lane"),
			_landmark("east_mouth", "동쪽 운하 어귀", 960, 432, 70, "lane")]})


# 12. Closing-ring arena (1152x880, NE/SW corners). Short bastions ring the
# centre shockwave; the barrier shrinks to the ring after 85 seconds. The final
# circle (220 = inner face of the stones) leaves a band of about 80 px outside
# the wave's reach (120 + 26 ring width): heroes dodge the wave at the edge
# instead of trading ring damage for wave damage (V1.5.3 review: endRadius 200
# vs a 170 px wave gave 44.7 environment damage per hero-minute).
static func _bastion_ring() -> Dictionary:
	var L := Layout.new(1152.0, 880.0, "point")
	# Twenty standing stones on a 250 px circle (offset 9 degrees); four are
	# missing, leaving the only four ways into the ring.
	for k in [1, 2, 3, 4, 6, 7, 8, 9]:
		var ang: float = deg_to_rad(9.0 + 18.0 * k)
		L.obstacle(_pillar("stone_%02d|stone_%02d" % [k, k + 10], snappedf(576.0 + 250.0 * cos(ang), 0.1), snappedf(440.0 + 250.0 * sin(ang), 0.1), 30, "#7a705f"))
	L.obstacle(_wall("outwork_ne|outwork_sw", 860, 150, 34, 96, "#6e6456"))
	L.obstacle(_wall("outwork_nw|outwork_se", 250, 290, 96, 34, "#6e6456"))
	L.hazard(_circle_hazard("ring_pulse", "shockwave", "요새 충격파", 576, 440, 120, "#f4ba76",
		{"period": 10.0, "activeDuration": 1.8, "warningDuration": 1.7, "phase": 5.0, "ringWidth": 26.0, "damage": 32.0, "school": "magic", "knockback": 32.0}))
	L.hazard(_ring("bastion_seal", 576, 440, 35.0, 85.0, 700.0, 220.0, 3.0, 0.5))
	L.hazard(_fountain("spring_nw|spring_se", 150, 150, 52, 0.15, 24.0, 0.05))
	L.spawns([[990, 150], [900, 110], [1060, 240], [800, 95], [1070, 340]])
	return L.finish({"id": "bastion_ring", "name": "환형 요새", "subtitle": "수축 결계 · 선돌 고리",
		"description": "선돌이 둥글게 둘러선 작은 요새입니다. 고리 안으로는 동서남북 네 틈으로만 들어가며, 35초부터 결계가 줄어들어 고리 안쪽만 남습니다. 가운데 충격파는 고리 안쪽 가장자리까지 닿지 않아 가장자리에서 피할 수 있습니다.",
		"accent": "#e6c27a", "difficulty": "수축 결계", "icon": "▣", "tags": ["결계 수축", "선돌 고리", "충격파", "대각선 출발"],
		"tacticalNotes": ["결계는 35초부터 85초까지 줄어들고, 이후 선돌 고리 안쪽만 안전합니다. 결계 밖에서는 최대 체력 비례 피해를 받습니다. 가운데 충격파는 고리 안쪽 가장자리까지 닿지 않으므로, 충격파 예고가 뜨면 가장자리로 물러나 피합니다.",
			"선돌 사이는 좁아서 지나갈 수 없습니다. 동서남북의 네 틈을 먼저 차지하면 결계가 줄어들 때 유리합니다.",
			"북서·남동 모서리의 회복 샘은 결계가 줄어들면 결계 밖에 남습니다. 초반에 활용합니다."],
		"floor": {"base": "#100e14", "blue": "#2b3d5c", "red": "#5a3040", "grid": "#c8b48a"},
		"layout_id": "shrinking_bastion_ring", "archetype": "closing_ring_arena", "spawn_orientation": "diagonal",
		"landmarks": [_landmark("inner_ring", "선돌 고리", 576, 440, 150), _landmark("spring_nw", "북서 샘터", 150, 150, 70, "supply"),
			_landmark("spring_se", "남동 샘터", 1002, 730, 70, "supply")]})
