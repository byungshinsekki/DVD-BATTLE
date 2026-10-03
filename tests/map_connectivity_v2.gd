extends SceneTree

const RADII: Array = [14, 16, 18, 20, 22, 24]
const DM_SEEDS: Array = [1, 77, 20261001]
var passed: int = 0
var failed: Array[String] = []
var measured: Array = []


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	if ok:
		passed += 1
	else:
		failed.append(message)
		push_error("MAP_CONNECTIVITY_V2 " + message)


func inspect(data: Dictionary, sample: String, radii: Array = RADII) -> void:
	var before: int = Time.get_ticks_usec()
	var issues: Array[String] = MapConnectivity.check(data, radii, 8.0)
	var elapsed: float = float(Time.get_ticks_usec() - before) / 1000000.0
	check(issues.is_empty(), sample + " all radii and gate states: " + str(issues))
	measured.append({"sample": sample, "seconds": elapsed, "issues": issues})
	print("MAP_CONNECTIVITY_V2 sample=", sample, " seconds=", elapsed, " problems=", issues.size())


func _run() -> void:
	DB.ensure_loaded()
	_synthetic_corner_enclosures()
	check(DB.arenas_for("elimination").size() == 12, "twelve elimination maps")
	check(DB.arenas_for("control").size() == 3, "three control maps")
	check(DeathmatchMapData.ORDER.size() == 3, "three deathmatch presets")
	for arena: Arena in DB.arenas:
		inspect(arena.data, arena.id)
	for id: String in ["ruined_gate", "crossroads", "thorn_circuit"]:
		inspect(DB.arena(id).data, id + "/r28", [28])
	# Reinstating the old unbroken lattice must reproduce the sealed keep.
	# This guards the permanent side passages without exempting closed gates.
	var sealed_keep: Dictionary = DB.arena("ruined_gate").data.duplicate(true)
	var restored_keep: int = 0
	for obstacle: Dictionary in sealed_keep.obstacles:
		if str(obstacle.id) in ["lattice_wn", "lattice_en"]:
			obstacle.y = 298.0
			obstacle.h = 95.0
			restored_keep += 1
		elif str(obstacle.id) in ["lattice_ws", "lattice_es"]:
			obstacle.h = 95.0
			restored_keep += 1
	check(restored_keep == 4, "four historical keep lattice segments restored privately")
	check(not MapConnectivity.check(sealed_keep, [28], 8.0).is_empty(), "historical all-closed keep remains detectable")
	for id: String in DeathmatchMapData.ORDER:
		for seed_value: int in DM_SEEDS:
			inspect(DeathmatchMapData.build(id, seed_value), "%s/seed=%d" % [id, seed_value])
	# The historical map, restored locally in a copied dictionary, must fail:
	# a test which cannot detect that pocket cannot prove the new map fixed it.
	var thorn: Dictionary = DB.arena("thorn_circuit").data.duplicate(true)
	var width: float = float(thorn.width)
	var height: float = float(thorn.height)
	var restored: int = 0
	for obstacle: Dictionary in thorn.obstacles:
		if str(obstacle.id) == "boulder_ne":
			obstacle["x"] = 1190.0
			obstacle["y"] = 110.0
			restored += 1
		elif str(obstacle.id) == "boulder_sw":
			obstacle["x"] = width - 1190.0
			obstacle["y"] = height - 110.0
			restored += 1
	check(restored == 2, "both historical mirrored boulders restored in private fixture")
	var historical: Array[String] = MapConnectivity.check(thorn, RADII, 8.0)
	check(not historical.is_empty(), "historical thorn pocket is detected: " + str(historical))
	var report: Dictionary = {"suite": "map_connectivity_v2", "status": "PASS" if failed.is_empty() else "FAIL", "passed": passed, "failed": failed, "step": 8.0, "radii": RADII, "maps": measured, "historical_thorn": historical}
	var report_path: String = "res://zz_work/measure/C2/map_connectivity_v2.json"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):
			report_path = arg.substr(9)
	DirAccess.make_dir_recursive_absolute(report_path.get_base_dir())
	var out: FileAccess = FileAccess.open(report_path, FileAccess.WRITE)
	if out == null:
		push_error("MAP_CONNECTIVITY_V2 cannot write report: " + report_path)
		quit(1)
		return
	out.store_string(JSON.stringify(report, "\t"))
	out.close()
	print("MAP_CONNECTIVITY_V2 ", "PASS" if failed.is_empty() else "FAIL", " passed=", passed, " failed=", failed.size())
	quit(0 if failed.is_empty() else 1)


# Append to tests/map_connectivity_v2.gd; call
#     _synthetic_corner_enclosures()
# in _run() after DB.ensure_loaded() and before final JSON serialization.
# Uses only the public check(data, radii, step) API. No production fixtures,
# thresholds, or engine geometry are changed by these tests.
func _synthetic_corner_enclosures() -> void:
	# r16 puts the legal NE corner (304,16) exactly on the 8px lattice.
	# The expanded disk has R56, dx=dy=44: it overlaps both center-space
	# boundaries while the corner is outside it. The free pocket is inside
	# x>294.64, y<25.36 (area<88), well below PI*16^2 ~= 804.25.
	# It has only three grid8 points (area192). Thus only the independent
	# geometric enclosure proof may report this; lowering the ordinary
	# lattice-area threshold is neither needed nor allowed.
	var sealed: Dictionary = {
		"id": "synthetic_corner", "width": 320.0, "height": 320.0,
		"bounds": {"minX": 0.0, "minY": 0.0, "maxX": 320.0, "maxY": 320.0},
		"obstacles": [{"id": "corner_rock", "shape": "circle", "x": 260.0,
			"y": 60.0, "radius": 40.0, "blocksUnits": true}],
		"spawns": {"blue": [{"x": 64.0, "y": 160.0}], "red": [{"x": 160.0, "y": 256.0}]}
	}
	var sealed_issues: Array[String] = MapConnectivity.check(sealed, [16], 8.0)
	check(sealed_issues.size() == 1 and sealed_issues[0].contains("corner_enclosure obstacle=corner_rock"),
		"sub-threshold free corner has exact enclosure proof: " + str(sealed_issues))

	# Moving the same rock down leaves a genuine top passage. A nearby
	# boundary by itself is insufficient to prove enclosure.
	var open_passage: Dictionary = sealed.duplicate(true)
	open_passage.obstacles[0].y = 100.0
	var open_issues: Array[String] = MapConnectivity.check(open_passage, [16], 8.0)
	check(open_issues.is_empty(), "one adjacent passage open is not enclosed: " + str(open_issues))

	# Keep the sealed geometry but add a valid spawn within the pocket. It
	# attaches to (304,16) with a clear segment, so neither spawn attachment
	# nor the geometric proof should report a disconnected unanchored area.
	var anchored: Dictionary = sealed.duplicate(true)
	anchored.spawns.blue.append({"x": 303.9, "y": 16.1})
	var anchored_issues: Array[String] = MapConnectivity.check(anchored, [16], 8.0)
	check(anchored_issues.is_empty(), "spawn inside same corner component exempts enclosure: " + str(anchored_issues))
