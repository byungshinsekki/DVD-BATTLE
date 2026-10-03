extends SceneTree

# V2 balance (H-BALANCE): case generator for forced-hero paired tests.
# Offline tool; it never touches user settings or records.
#
#   --hero=<id>          the forced hero (every case contains it)
#   --set=<name>         seed-set label, part of every case id (A, B, ...)
#   --seed0=<int>        first seed of the set
#   --n=<int>            seeds per map (cases = maps x n x 2)
#   --out=<path>         JSON array in tools/balance_runner.gd format
#   [--maps=all|a,b,..]  elimination maps (default: all 12)
#   [--size=3]           team size
#   [--max_time=150]
#
# Every (map, k) draws 2*size-1 distinct heroes from the other 25 of the
# 26-hero roster with its own seeded RNG (no shared deck, so one map's draws do
# not depend on another's): the first size-1 are the forced hero's partners,
# the rest its opponents. Each draw is played twice with the sides mirrored on
# the same battle seed ("_b": forced hero on blue, "_r": on red).

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args: Dictionary = {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var at: int = arg.find("=")
			args[arg.substr(2, at - 2)] = arg.substr(at + 1)
	DB.ensure_loaded()
	var hero: String = str(args.get("hero", ""))
	if DB.char_def(hero) == null:
		push_error("unknown --hero " + hero)
		quit(2)
		return
	var set_name: String = str(args.get("set", "A"))
	var seed0: int = int(args.get("seed0", "250000"))
	var n: int = int(args.get("n", "5"))
	var size: int = int(args.get("size", "3"))
	var max_time: float = float(args.get("max_time", "150"))
	var maps: Array = []
	if str(args.get("maps", "all")) == "all":
		for a in DB.arenas_for("elimination"):
			maps.append((a as Arena).id)
	else:
		maps = Array(str(args.maps).split(",", false))
	var pool: Array = []
	for id in DB.ids():
		if str(id) != hero:
			pool.append(str(id))
	var hero_index: int = DB.ids().find(hero)
	var cases: Array = []
	for mi in maps.size():
		for k in n:
			var rng: RandomNumberGenerator = RandomNumberGenerator.new()
			rng.seed = seed0 * 7919 + mi * 104729 + k * 1299709 + hero_index * 15485863
			var deck: Array = pool.duplicate()
			for i in range(deck.size() - 1, 0, -1):
				var j: int = rng.randi_range(0, i)
				var tmp = deck[i]
				deck[i] = deck[j]
				deck[j] = tmp
			var mine: Array = [hero]
			mine.append_array(deck.slice(0, size - 1))
			var theirs: Array = deck.slice(size - 1, size * 2 - 1)
			var battle_seed: int = seed0 + mi * 1000 + k * 17
			var base_id: String = "%s_%s_%s_%d" % [hero, set_name, str(maps[mi]), k]
			cases.append({"id": base_id + "_b", "arena_id": str(maps[mi]), "seed": battle_seed, "blue": mine, "red": theirs,
				"max_time": max_time, "forced": hero, "forced_team": 0, "set": set_name})
			cases.append({"id": base_id + "_r", "arena_id": str(maps[mi]), "seed": battle_seed, "blue": theirs, "red": mine,
				"max_time": max_time, "forced": hero, "forced_team": 1, "set": set_name})
	var f: FileAccess = FileAccess.open(str(args.get("out", "user://forced_cases.json")), FileAccess.WRITE)
	if f == null:
		push_error("cannot write --out")
		quit(2)
		return
	f.store_string(JSON.stringify(cases, "\t"))
	f.close()
	print("CASES ", cases.size(), " hero=", hero, " set=", set_name, " maps=", maps.size())
	quit(0)
