extends SceneTree

var passed: int = 0
var failed: Array[String] = []
var map_reports: Array = []

# The V1.5.2 maps intentionally use triangle, horizontal and diagonal objectives.
# Validate real access and team starting space instead of one old coordinate layout.
# V1.5.3 (DESIGN_153 §3): elimination maps no longer share the legacy 1408x792
# canvas and control maps no longer share one aspect or an exact 2.5x area.
# The legacy-size, exact-area/aspect and "width x 0.65 spawn gap" assertions are
# replaced by the new invariants: elimination aspect 1.25-2.4 and area
# 0.75-1.45x, control area 2.0-3.0x, opposing spawn slots >= 900 px apart by
# walking path (orientation-independent). tests/maps_153.gd holds the rest.
const BODY_RADIUS: float = 30.0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if condition:
		passed += 1
	else:
		failed.append(message)
		push_error("CONTROL MAP: " + message)

func _run() -> void:
	DB.ensure_loaded()
	check(DB.characters.size() == 26, "all 26 heroes retained")
	check(DB.arenas_for("elimination").size() == 12, "12 original elimination arenas retained")
	var arenas: Array = DB.arenas_for("control")
	check(arenas.size() == 3, "three control arenas")
	var layouts: Dictionary = {}
	var objective_layouts: Dictionary = {}
	for a: Arena in DB.arenas_for("elimination"):
		var e_aspect: float = a.width / a.height
		var e_area: float = a.width * a.height / (Arena.WIDTH * Arena.HEIGHT)
		check(e_aspect >= 1.25 - 1e-6 and e_aspect <= 2.4 + 1e-6 and e_area >= 0.75 - 1e-6 and e_area <= 1.45 + 1e-6, "V1.5.3 elimination size envelope " + a.id)
		check(a.control_points.is_empty() and a.heal_zones.is_empty(), "legacy objectives absent " + a.id)
	for a: Arena in arenas:
		var c_area: float = a.width * a.height / (Arena.WIDTH * Arena.HEIGHT)
		check(c_area >= 2.0 and c_area <= 3.0, "control canvas area 2.0-3.0x " + a.id)
		check(absf(float(a.data.get("area_multiplier", 0.0)) - c_area) < 0.001, "declared area multiplier matches the canvas " + a.id)
		check(a.control_points.size() == 3, "three capture points " + a.id)
		check(a.heal_zones.size() == 4, "four shared heal zones " + a.id)
		check(a.obs_count >= 6, "meaningful obstacle layout " + a.id)
		check(not layouts.has(JSON.stringify(a.obstacles)), "distinct obstacle layout " + a.id)
		layouts[JSON.stringify(a.obstacles)] = true
		var goals: Array[Vector2] = []
		var objective_coords: Array = []
		for point: Dictionary in a.control_points:
			check(a.is_walkable(point.center, BODY_RADIUS), "capture center clear " + a.id + "/" + str(point.id))
			check(float(point.center.x) - float(point.radius) >= a.min_x and float(point.center.x) + float(point.radius) <= a.max_x and float(point.center.y) - float(point.radius) >= a.min_y and float(point.center.y) + float(point.radius) <= a.max_y, "capture circle within playable bounds " + a.id + "/" + str(point.id))
			objective_coords.append([point.center.x, point.center.y])
			goals.append(point.center)
		var objective_signature: String = JSON.stringify(objective_coords)
		check(not objective_layouts.has(objective_signature), "distinct objective formation " + a.id)
		objective_layouts[objective_signature] = true
		for i in a.control_points.size():
			for j in range(i + 1, a.control_points.size()):
				var p: Dictionary = a.control_points[i]
				var q: Dictionary = a.control_points[j]
				check((p.center as Vector2).distance_to(q.center) > float(p.radius) + float(q.radius) + BODY_RADIUS * 2.0, "capture areas cannot be occupied together by one body " + a.id)
		for zone: Dictionary in a.heal_zones:
			check(a.is_walkable(zone.center, float(zone.radius)), "heal zone clear of walls " + a.id + "/" + str(zone.id))
			check(float(zone.cooldown) > 0.0 and float(zone.heal_ratio) > 0.0 and float(zone.heal_ratio) < 1.0, "finite heal cooldown and amount " + a.id + "/" + str(zone.id))
			goals.append(zone.center)
		var nav: Navigator = Navigator.new()
		nav.arena = a
		nav.bucket = BODY_RADIUS
		nav._build()
		check(nav.cols > int(ceil(Arena.WIDTH / Navigator.CELL)) and nav.rows > int(ceil(Arena.HEIGHT / Navigator.CELL)), "navigation spans expanded world " + a.id)
		var path_count: int = 0
		var max_route: float = 0.0
		var total_capture_routes: Array[float] = [0.0, 0.0]
		for team in [0, 1]:
			check(a.spawns[team].size() == 5, "five spawn slots " + a.id)
			for spawn: Vector2 in a.spawns[team]:
				check(a.is_walkable(spawn, BODY_RADIUS), "spawn clear " + a.id)
				for goal: Vector2 in goals:
					var path: PackedVector2Array = nav.path_points(spawn, goal)
					check(path.size() >= 2, "spawn-to-objective route " + a.id)
					if path.size() >= 2:
						check(path[-1].distance_to(goal) < Navigator.CELL * 2.0, "route reaches correct expanded endpoint " + a.id)
						max_route = maxf(max_route, nav.path_length(spawn, goal, BODY_RADIUS))
					check(_continuous_route(nav, spawn, goal), "whole radius-30 objective route clears walls " + a.id)
					path_count += 1
				for point: Dictionary in a.control_points:
					total_capture_routes[team] += nav.path_length(spawn, point.center, BODY_RADIUS)
		for i in range(goals.size()):
			for j in range(i + 1, goals.size()):
				check(nav.path_points(goals[i], goals[j]).size() >= 2, "objective rotation route " + a.id)
				check(_continuous_route(nav, goals[i], goals[j]), "whole radius-30 rotation clears walls " + a.id)
		for slot in range(5):
			var blue: Vector2 = a.spawns[0][slot]
			var red: Vector2 = a.spawns[1][slot]
			check(nav.path_length(blue, red, BODY_RADIUS) >= 900.0, "opposing spawn slots are at least 900 px apart by path " + a.id)
			for other_slot in range(slot + 1, 5):
				check(blue.distance_to(a.spawns[0][other_slot]) > BODY_RADIUS * 2.0 and red.distance_to(a.spawns[1][other_slot]) > BODY_RADIUS * 2.0, "same-team initial bodies do not overlap " + a.id)
		# Home-side objectives may be intentionally closer to one team. Total
		# navigation distance to all three must still offer comparable initial access.
		var access_ratio: float = maxf(total_capture_routes[0], total_capture_routes[1]) / maxf(1.0, minf(total_capture_routes[0], total_capture_routes[1]))
		check(access_ratio < 1.15, "aggregate initial objective access within 15 percent " + a.id)
		map_reports.append({"id": a.id, "name": a.name, "width": a.width, "height": a.height,
			"area_multiplier": a.width * a.height / (Arena.WIDTH * Arena.HEIGHT),
			"obstacles": a.obs_count, "points": a.control_points.size(), "heal_zones": a.heal_zones.size(),
			"spawn_routes": path_count, "longest_route": max_route, "navigation_grid": [nav.cols, nav.rows],
			"radius": BODY_RADIUS, "total_capture_routes": total_capture_routes, "initial_access_ratio": access_ratio})
	var report: Dictionary = {"status": "PASS" if failed.is_empty() else "FAIL", "passed": passed, "failed": failed, "maps": map_reports}
	var output: FileAccess = FileAccess.open("res://reports/control_maps_13.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "\t"))
	output.close()
	print("CONTROL_MAPS ", report.status, " passed=", passed, " failed=", failed.size())
	quit(0 if failed.is_empty() else 1)

func _continuous_route(nav: Navigator, start: Vector2, goal: Vector2) -> bool:
	if nav.clear(start, goal, BODY_RADIUS):
		return true
	var points: PackedVector2Array = nav.path_points(start, goal)
	if points.size() < 2 or not nav.clear(start, points[0], BODY_RADIUS) or not nav.clear(points[-1], goal, BODY_RADIUS):
		return false
	for i in range(1, points.size()):
		if not nav.clear(points[i - 1], points[i], BODY_RADIUS):
			return false
	return true
