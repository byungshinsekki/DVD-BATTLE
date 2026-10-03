extends SceneTree

const Schema = preload("res://tools/calibration_v2/calibration_schema.gd")
const Stamp = preload("res://tools/calibration_v2/sim_stamp.gd")
const Legacy = preload("res://tests/baselines/draft_director_13.gd")

class Roster26:
	extends RefCounted
	var budget: int = 22
	var ruleset: String = "elimination"
	var search_options: Dictionary = {"rollout_enabled": false}
	var team_size: int = 5
	func mask_of(_team: Array) -> int: return 0
	func legal(_ai: int, _user: int) -> PackedInt32Array:
		return PackedInt32Array(range(26))

var passed: int = 0
var failed: Array = []


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed.append(label)
		push_error(label)


func _run() -> void:
	DB.ensure_loaded()
	var output: String = "res://reports/calibration_v2.json"
	var expected_current: String = ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): output = arg.substr(9)
		if arg.begins_with("--current-sim-sha="): expected_current = arg.substr(18)
	var data: Dictionary = load("res://scripts/data/draft_calibration.gd").get_script_constant_map()
	var validation: Dictionary = Schema.validate(data, DB.ids())
	passed += int(validation.passed)
	failed.append_array(validation.failed)
	check(DraftDirector.SHIFT == (1 << 32) and Legacy.SHIFT == (1 << 32), "current and legacy 32-bit cache halves")
	check(1 * DraftDirector.SHIFT + (1 << 22) != 2 * DraftDirector.SHIFT, "26-roster cache collision is removed")
	var mask26: int = (1 << 26) - 1
	check(mask26 * DraftDirector.SHIFT + mask26 > 0, "26-roster masks remain inside signed int64")
	var tiny: DraftDirector = DraftDirector.new({"budget": 1, "rollout_enabled": false})
	check(tiny.budget == DB.ids().size(), "minimum budget follows current roster")
	var synthetic: Roster26 = Roster26.new()
	var search: DraftSearch14 = DraftSearch14.new(synthetic, [], [])
	var quotas: int = 0
	for row: Dictionary in search.roots:
		check(int(row.quota) >= 1, "synthetic 26th root is evaluated fairly: " + str(row.idx))
		quotas += int(row.quota)
	check(search.total_budget == 26 and quotas == 26 and search.roots.size() == 26, "26-root budget and quota accounting")
	search.cancel()
	var ids: Array = DB.ids()
	check(DraftDirector._roster_team({ids[0]: 0.1, "unknown_hero": 0.2}, ids) == {ids[0]: 0.1}, "unknown TEAM IDs ignored")
	check(DraftDirector._roster_duel({"unknown_hero|zzz": 0.2}, ids).is_empty(), "unknown DUEL IDs ignored")
	var saved: Dictionary = DraftDirector._cal_cache
	DraftDirector._cal_cache = {"duel": {}, "team": {ids[0]: 0.03}, "team_elim": {ids[0]: 0.21}, "team_control": {ids[0]: -0.17}, "games": 0}
	var elim: DraftDirector = DraftDirector.new({"arena_id": "classic"})
	var control: DraftDirector = DraftDirector.new({"arena_id": "control_crossroads", "ruleset": "control"})
	check(is_equal_approx(elim.team_power[int(elim.index[ids[0]])], 0.21), "elimination uses TEAM_ELIM")
	check(is_equal_approx(control.team_power[int(control.index[ids[0]])], -0.17), "control uses TEAM_CONTROL after elimination cache")
	DraftDirector._cal_cache = {"duel": {}, "team": {ids[0]: 0.03}, "games": 0}
	var fallback: DraftDirector = DraftDirector.new({"arena_id": "control_crossroads", "ruleset": "control"})
	check(is_equal_approx(fallback.team_power[int(fallback.index[ids[0]])], 0.03), "legacy TEAM fallback remains supported")
	DraftDirector._cal_cache = saved
	var current: Dictionary = Stamp.compute()
	check(not current.is_empty(), "current simulation stamp computed without launching a child process")
	if not expected_current.is_empty():
		check(str(current.get("sim_sha", "")) == expected_current, "Python/GDScript SIM_SHA implementations match")
	var fresh: bool = str(current.get("sim_sha", "")) == str(data.get("SIM_SHA", ""))
	if not fresh:
		print("CALIBRATION_V2 WARN stale calibration: stored=", data.get("SIM_SHA", ""), " current=", current.get("sim_sha", ""))
	var report: Dictionary = {"status": "PASS" if failed.is_empty() else "FAIL", "passed": passed, "failed": failed,
		"calibration": validation, "fresh": fresh, "current_sim_sha": current.get("sim_sha", ""),
		"stored_sim_sha": data.get("SIM_SHA", ""), "freshness_policy": "warn in Phase 1; final release rejects stale data"}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	var file: FileAccess = FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write calibration test report: " + output)
		quit(1)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		push_error("Cannot finish calibration test report: " + output)
		quit(1)
		return
	print("CALIBRATION_V2 ", JSON.stringify(report))
	quit(0 if failed.is_empty() else 1)
