extends RefCounted

const MAP_DUEL_ARENAS: Array[String] = ["classic", "ruined_gate", "thorn_circuit", "furnace_basin", "moon_garden", "bastion_ring"]
const MAP_ELIM_ARENAS: Array[String] = ["classic", "ruined_gate", "thorn_circuit", "furnace_basin", "wind_temple", "dimensional_lattice",
	"crossroads", "moon_garden", "twin_foundry", "gale_corridor", "rift_harbor", "bastion_ring"]
const MAP_CONTROL_ARENAS: Array[String] = ["control_crossroads", "control_citadel", "control_waterway"]
const MAP_FIELDS: Array[String] = ["MAP_DUEL", "MAP_DUEL_COUNTS", "MAP_TEAM_ELIM", "MAP_TEAM_ELIM_COUNTS",
	"MAP_TEAM_CONTROL", "MAP_TEAM_CONTROL_COUNTS"]
const MAP_META: Array[String] = ["MAP_PRIOR_FORMAT", "MAP_PRIOR_SEMANTICS", "MAP_PRIOR_CAP", "MAP_DUEL_SHRINK", "MAP_TEAM_SHRINK"]
const MAP_SEMANTICS: String = "clamp((map_mean-other_maps_mean)*n/(n+k), -cap, cap); additive residual; absent mode/map means zero"


static func _check(ok: bool, label: String, result: Dictionary) -> void:
	if ok:
		result.passed = int(result.passed) + 1
	else:
		result.failed.append(label)


static func validate(data: Dictionary, roster: Array) -> Dictionary:
	var result: Dictionary = {"passed": 0, "failed": []}
	var ids: Array = roster.duplicate()
	ids.sort()
	var n: int = ids.size()
	_check(str(data.get("ENGINE", "")) == "GD-2.0", "engine stamp", result)
	_check(str(data.get("PLATFORM", "")) == "windows", "Windows platform stamp", result)
	_check(int(data.get("GAMES", -1)) == n * (n - 1) / 2 * 12 + 1800, "full measured game count", result)
	_check(data.get("ROSTER", []) == ids, "stored roster matches current DB", result)
	var hex_pattern: RegEx = RegEx.new()
	hex_pattern.compile("^[0-9a-f]{64}$")
	_check(hex_pattern.search(str(data.get("SIM_SHA", ""))) != null, "SIM_SHA shape", result)
	_check(hex_pattern.search(str(data.get("DATA_FINGERPRINT", ""))) != null, "data fingerprint shape", result)
	for field: String in ["DUEL", "TEAM_ELIM", "TEAM_CONTROL", "TEAM"]:
		_check(data.get(field) is Dictionary, field + " dictionary", result)
	var duel: Dictionary = data.get("DUEL", {}) if data.get("DUEL") is Dictionary else {}
	_check(duel.size() == n * (n - 1) / 2, "every unordered duel pair exists", result)
	for key in duel:
		var parts: PackedStringArray = str(key).split("|")
		var legal: bool = parts.size() == 2
		if legal:
			legal = parts[0] in ids and parts[1] in ids and parts[0] < parts[1]
		_check(legal, "duel key " + str(key), result)
		var value = duel[key]
		_check(typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and absf(float(value)) <= 1.0,
			"duel value " + str(key), result)
	for field: String in ["TEAM_ELIM", "TEAM_CONTROL", "TEAM"]:
		var table: Dictionary = data.get(field, {}) if data.get(field) is Dictionary else {}
		var keys: Array = table.keys()
		keys.sort()
		_check(keys == ids, field + " roster IDs", result)
		for key in table:
			var value = table[key]
			_check(typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and absf(float(value)) <= 0.30000001,
				field + " range " + str(key), result)
	_check(data.get("TEAM", {}) == data.get("TEAM_ELIM", {}), "legacy TEAM equals TEAM_ELIM", result)
	_validate_map_priors(data, ids, duel.keys(), result)
	result["status"] = "PASS" if result.failed.is_empty() else "FAIL"
	result["games"] = data.get("GAMES", -1)
	result["duel_pairs"] = duel.size()
	result["roster_count"] = n
	return result


static func _validate_map_priors(data: Dictionary, ids: Array, pair_ids: Array, result: Dictionary) -> void:
	# Old measured tables remain readable. A partial new-format table is invalid.
	var present: bool = false
	for field: String in MAP_FIELDS + MAP_META:
		present = present or data.has(field)
	if not present:
		return
	_check(typeof(data.get("MAP_PRIOR_FORMAT")) == TYPE_INT and data.get("MAP_PRIOR_FORMAT") == 1, "map prior format", result)
	_check(data.get("MAP_PRIOR_SEMANTICS") == MAP_SEMANTICS, "map residual semantics", result)
	for field: String in ["MAP_PRIOR_CAP", "MAP_DUEL_SHRINK", "MAP_TEAM_SHRINK"]:
		var value = data.get(field)
		var expected: float = {"MAP_PRIOR_CAP": 0.12, "MAP_DUEL_SHRINK": 20.0, "MAP_TEAM_SHRINK": 60.0}[field]
		_check(typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and is_equal_approx(float(value), expected),
			field + " fixed evidence shrink", result)
	for field: String in MAP_FIELDS:
		_check(data.get(field) is Dictionary, field + " dictionary", result)
	for family: String in ["MAP_DUEL", "MAP_TEAM_ELIM", "MAP_TEAM_CONTROL"]:
		var expected_maps: Array = MAP_DUEL_ARENAS.duplicate() if family == "MAP_DUEL" else (MAP_ELIM_ARENAS.duplicate() if family == "MAP_TEAM_ELIM" else MAP_CONTROL_ARENAS.duplicate())
		expected_maps.sort()
		var expected_keys: Array = pair_ids.duplicate() if family == "MAP_DUEL" else ids.duplicate()
		expected_keys.sort()
		var maps: Dictionary = data.get(family, {}) if data.get(family) is Dictionary else {}
		var counts: Dictionary = data.get(family + "_COUNTS", {}) if data.get(family + "_COUNTS") is Dictionary else {}
		var map_keys: Array = maps.keys()
		map_keys.sort()
		var count_keys: Array = counts.keys()
		count_keys.sort()
		_check(map_keys == expected_maps, family + " measured maps only", result)
		_check(count_keys == expected_maps, family + " count maps", result)
		var total_count: int = 0
		for arena: String in expected_maps:
			_check(maps.get(arena) is Dictionary and counts.get(arena) is Dictionary, family + " map dictionaries " + arena, result)
			var values: Dictionary = maps.get(arena, {}) if maps.get(arena) is Dictionary else {}
			var samples: Dictionary = counts.get(arena, {}) if counts.get(arena) is Dictionary else {}
			var keys: Array = values.keys()
			keys.sort()
			var sample_keys: Array = samples.keys()
			sample_keys.sort()
			_check(keys == expected_keys, family + " map roster " + arena, result)
			_check(sample_keys == expected_keys, family + " sample roster " + arena, result)
			for key in expected_keys:
				var residual = values.get(key)
				_check(typeof(residual) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(residual)) and absf(float(residual)) <= 0.12000001,
					family + " bounded residual " + arena + "/" + str(key), result)
				var count = samples.get(key)
				var valid_count: bool = typeof(count) == TYPE_INT and int(count) > 0
				_check(valid_count and (family != "MAP_DUEL" or count == 2), family + " measured count " + arena + "/" + str(key), result)
				if valid_count:
					total_count += int(count)
		var expected_total: int = pair_ids.size() * 12 if family == "MAP_DUEL" else (11000 if family == "MAP_TEAM_ELIM" else 3000)
		_check(total_count == expected_total, family + " total measured appearances", result)
