extends SceneTree

# V1.5.2 map contract: stable catalogue, distinct real geometry, seeded plans,
# radius-30 routes to every spawn, objective, item and public gimmick endpoint.
# V1.5.3: control maps no longer have an exact 2.5x area (now 2.0-3.0x, see
# DESIGN_153 §3), jump-pad landings are public endpoints too, artillery must be
# announced like the other periodic dangers, and the shipped hazard coverage
# includes the new gimmick types. Gate maps route every endpoint with the gates
# open and require all spawns to connect with every gate shut; tests/maps_153.gd
# checks each gate signature and body bucket.
const BODY_RADIUS: float = 30.0
const DM_SEEDS: Array = [1, 2, 3, 77, 4242, 20261001, 152, 9152]
var passed: int = 0
var failed: Array = []
var map_reports: Array = []
var signatures: Dictionary = {}
var layouts: Dictionary = {}
var hazard_types: Dictionary = {}
var catalogue: Array = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed.append(label)
		push_error("MAPS_152 " + label)

func _point(d: Dictionary) -> Vector2:
	return Vector2(float(d.x), float(d.y))

func _geometry_signature(a: Arena) -> String:
	var values: Array = []
	for o: Dictionary in a.obstacles:
		values.append([o.get("shape", "rect"), o.x, o.y, o.get("w", 0), o.get("h", 0), o.get("radius", 0)])
	return JSON.stringify(values).sha256_text()

func _route(nav: Navigator, start: Vector2, goal: Vector2) -> bool:
	if nav.clear(start, goal, BODY_RADIUS):
		return true
	var points: PackedVector2Array = nav.path_points(start, goal)
	if points.size() < 2:
		return false
	if not nav.clear(start, points[0], BODY_RADIUS) or not nav.clear(points[-1], goal, BODY_RADIUS):
		return false
	for i in range(1, points.size()):
		if not nav.clear(points[i - 1], points[i], BODY_RADIUS):
			return false
	return true

func _inspect(a: Arena, sample_id: String, distinct_layout: bool) -> void:
	var layout: String = str(a.data.get("layout_id", ""))
	check(not layout.is_empty(), sample_id + " explicit topology ID")
	check(not (a.data.get("landmarks", []) as Array).is_empty(), sample_id + " public landmarks")
	if distinct_layout:
		catalogue.append(a.data)
		check(not layouts.has(layout), sample_id + " unique topology ID")
		layouts[layout] = true
		var signature: String = _geometry_signature(a)
		check(not signatures.has(signature), sample_id + " distinct actual geometry")
		signatures[signature] = true
	var obstacle_ids: Dictionary = {}
	var obstacle_shapes: Dictionary = {}
	for i in a.obs_count:
		var o: Dictionary = a.obstacles[i]
		check(not obstacle_ids.has(str(o.id)), sample_id + " unique obstacle ID " + str(o.id))
		obstacle_ids[str(o.id)] = true
		var shape: String = JSON.stringify([o.get("shape", "rect"), o.x, o.y, o.get("w", 0), o.get("h", 0), o.get("radius", 0)])
		check(not obstacle_shapes.has(shape), sample_id + " no duplicate collider " + str(o.id))
		obstacle_shapes[shape] = true
		check(a.obs_minx[i] >= a.min_x - 0.01 and a.obs_maxx[i] <= a.max_x + 0.01 and a.obs_miny[i] >= a.min_y - 0.01 and a.obs_maxy[i] <= a.max_y + 0.01, sample_id + " collider within playable bounds " + str(o.id))
	var goals: Array = []
	if a.ruleset == "deathmatch":
		check(a.ffa_spawns.size() >= 12, sample_id + " supports twelve players")
		for i in a.ffa_spawns.size():
			goals.append({"label": "spawn:%d" % i, "point": a.ffa_spawns[i]})
		for i in a.item_spots.size():
			goals.append({"label": "item:%d" % i, "point": a.item_spots[i].pos})
		check(a.item_spots.size() >= DeathmatchMode.MAX_FIELD_ITEMS, sample_id + " sufficient reachable item anchors")
	else:
		for side in [0, 1]:
			check(a.spawns[side].size() == 5, sample_id + " five team spawn slots")
			for i in a.spawns[side].size():
				goals.append({"label": "spawn:%d:%d" % [side, i], "point": a.spawns[side][i]})
	for cp: Dictionary in a.control_points:
		goals.append({"label": "capture:" + str(cp.id), "point": cp.center})
	for hz: Dictionary in a.heal_zones:
		check(a.is_walkable(hz.center, float(hz.radius)), sample_id + " entire heal zone clear " + str(hz.id))
		goals.append({"label": "heal:" + str(hz.id), "point": hz.center})
	var hazard_ids: Dictionary = {}
	for h: Dictionary in a.hazards:
		check(not hazard_ids.has(str(h.id)), sample_id + " unique hazard ID " + str(h.id))
		hazard_ids[str(h.id)] = h
		hazard_types[str(h.type)] = true
		goals.append({"label": "gimmick:" + str(h.id), "point": h.center})
		if str(h.type) == "healing_fountain":
			check(float(h.cooldown) > 0 and float(h.healPercent) > 0 and float(h.healPercent) < 1, sample_id + " bounded shared heal " + str(h.id))
		elif str(h.type) in ["gravity", "shockwave"]:
			check(float(h.period) > float(h.activeDuration) + float(h.warningDuration) and float(h.warningDuration) >= 1.0, sample_id + " announced periodic danger " + str(h.id))
		elif str(h.type) == "artillery":
			check(str(h.shape) == "rect" and float(h.period) > float(h.warningDuration) + 1.0 and float(h.warningDuration) >= 1.0 and int(h.count) >= 1, sample_id + " announced artillery salvo " + str(h.id))
	for h: Dictionary in a.hazards:
		if str(h.type) != "portal":
			continue
		var pair: Dictionary = hazard_ids.get(str(h.get("pairId", "")), {})
		check(not pair.is_empty() and str(pair.get("pairId", "")) == str(h.id), sample_id + " reciprocal portal " + str(h.id))
		if not pair.is_empty():
			var direction: Vector2 = pair.get("exit", ((pair.center as Vector2) - (h.center as Vector2)).normalized())
			var exit_point: Vector2 = (pair.center as Vector2) + direction * (float(pair.radius) + BODY_RADIUS + 8.0)
			goals.append({"label": "portal_exit:" + str(h.id), "point": exit_point})
	for h: Dictionary in a.hazards:
		if str(h.type) == "jump_pad":
			goals.append({"label": "jump_target:" + str(h.id), "point": Vector2(float(h.target.x), float(h.target.y))})
	# Gate maps: every endpoint is routed with the gates open (a private copy
	# without the gate pieces); spawns must also connect with every gate shut.
	var route_arena: Arena = a
	var gated: bool = false
	for o: Dictionary in a.obstacles:
		gated = gated or o.has("gate")
	if gated:
		var copy: Dictionary = a.data.duplicate(true)
		copy.obstacles = (copy.obstacles as Array).filter(func(o: Dictionary) -> bool: return not o.has("gate"))
		route_arena = Arena.from_data(copy)
		var shut := Navigator.new()
		shut.arena = a
		shut.bucket = BODY_RADIUS
		shut._build()
		for side in [0, 1]:
			for p: Vector2 in a.spawns[side]:
				check(_route(shut, a.spawns[0][0], p), sample_id + " spawns connected with every gate shut")
	var nav := Navigator.new()
	nav.arena = route_arena
	nav.bucket = BODY_RADIUS
	nav._build()
	var start: Vector2 = goals[0].point
	var longest: float = 0.0
	for goal: Dictionary in goals:
		var point: Vector2 = goal.point
		check(route_arena.is_walkable(point, BODY_RADIUS), sample_id + " radius-30 clearance " + str(goal.label))
		check(_route(nav, start, point), sample_id + " physical radius-30 route " + str(goal.label))
		longest = maxf(longest, nav.path_length(start, point, BODY_RADIUS))
	if a.ruleset == "control":
		check(a.control_points.size() == 3 and a.heal_zones.size() == 4, sample_id + " three points / four shared heals")
		var area: float = a.width * a.height / (Arena.WIDTH * Arena.HEIGHT)
		check(area >= 2.0 and area <= 3.0, sample_id + " canvas area 2.0-3.0x")
	map_reports.append({"id": sample_id, "layout_id": layout, "colliders": a.obs_count, "hazards": a.hazards.size(), "checked_anchors": goals.size(), "longest_route": longest, "geometry_sha256": _geometry_signature(a)})
	print("MAPS_152 map=", sample_id, " anchors=", goals.size(), " failures=", failed.size())

func _run() -> void:
	DB.ensure_loaded()
	check(DB.arenas_for("elimination").size() == 12, "twelve elimination maps retained")
	check(DB.arenas_for("control").size() == 3, "three control maps retained")
	check(DeathmatchMapData.ORDER.size() == 3, "three deathmatch presets retained")
	var expected: Array = ["classic", "ruined_gate", "thorn_circuit", "furnace_basin", "wind_temple", "dimensional_lattice", "crossroads", "moon_garden", "twin_foundry", "gale_corridor", "rift_harbor", "bastion_ring", "control_crossroads", "control_citadel", "control_waterway"]
	for a: Arena in DB.arenas:
		check(expected.has(a.id), "retained stable arena ID " + a.id)
		_inspect(a, a.id, true)
	var cp_signatures: Dictionary = {}
	for a: Arena in DB.arenas_for("control"):
		var coords: Array = []
		for cp in a.control_points:
			coords.append(cp.center)
		var sig: String = str(coords)
		check(not cp_signatures.has(sig), "distinct control objective arrangement " + a.id)
		cp_signatures[sig] = true
	for id in DeathmatchMapData.ORDER:
		var seeds: Dictionary = {}
		var fallback: Dictionary = DeathmatchMapData._validated_fallback(id, DeathmatchMapData.PRESETS[id])
		check(not fallback.is_empty() and bool(fallback.get("generation_fallback", false)), id + " exhausted-attempt fallback explicitly validated")
		if not fallback.is_empty():
			_inspect(Arena.from_data(fallback), id + "/forced_fallback", false)
		for seed_value in DM_SEEDS:
			var data: Dictionary = DeathmatchMapData.build(id, seed_value)
			var again: Dictionary = DeathmatchMapData.build(id, seed_value)
			check(JSON.stringify(data) == JSON.stringify(again), "%s seed %d exact deterministic generation" % [id, seed_value])
			var a: Arena = Arena.from_data(data)
			var sig: String = _geometry_signature(a)
			check(not seeds.has(sig), "%s seed %d varies geometry within preset plan" % [id, seed_value])
			seeds[sig] = true
			_inspect(a, "%s/%d" % [id, seed_value], seed_value == DM_SEEDS[0])
			var buildings: Array = data.buildings
			var supply_count: int = 0
			for spot in data.item_spots:
				if str(spot.kind) == "building":
					supply_count += 1
			check(supply_count == buildings.size() * 3, "%s/%d three accessible supply anchors per building" % [id, seed_value])
			if id == "dm_forest_village":
				check(buildings.size() == 6 and float(buildings[0].x) > 1900, "%s village stays east of forest belt" % id)
			elif id == "dm_ruined_town":
				check(buildings.size() == 12, "%s twelve blocks preserve street grid" % id)
			else:
				check(buildings.size() == 4 and str(a.obstacles[0].id).begins_with("ridge_"), "%s four camps and long ridge topology" % id)
	check(layouts.size() == 18 and signatures.size() == 18, "eighteen distinct layout and geometry contracts")
	for type in ["haste", "healing_fountain", "gravity", "shockwave", "portal", "wind", "lava", "spikes", "eruption", "artillery", "jump_pad", "closing_ring", "mud"]:
		check(hazard_types.has(type), "shipped map coverage for " + type)
	var report: Dictionary = {"suite": "maps_152", "status": "PASS" if failed.is_empty() else "FAIL", "passed": passed, "failed": failed, "radius": BODY_RADIUS, "distinct_presets": layouts.size(), "dm_seeds_per_preset": DM_SEEDS.size(), "maps": map_reports}
	DirAccess.make_dir_recursive_absolute("res://reports/maps_152")
	var output: FileAccess = FileAccess.open("res://reports/maps_152/maps_152.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "\t"))
	output.close()
	var geometry_output: FileAccess = FileAccess.open("res://reports/maps_152/layout_catalogue_152.json", FileAccess.WRITE)
	geometry_output.store_string(JSON.stringify(catalogue, "\t"))
	geometry_output.close()
	print("MAPS_152 ", report.status, " passed=", passed, " failed=", failed.size())
	quit(0 if failed.is_empty() else 1)
