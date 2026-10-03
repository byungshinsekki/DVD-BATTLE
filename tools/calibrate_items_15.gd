extends SceneTree

# Measures, per hero, which share of the damage it actually deals in
# deathmatch comes from basic attacks (the rest: abilities and their
# summons). ItemValuation.BASIC_SHARE is this table; rerun after balance
# changes:  godot --headless --path . --script res://tools/calibrate_items_15.gd -- --round=0
# Rounds 0..5 each play two 11-player matches that together seat all heroes.

func _initialize() -> void:
	_run.call_deferred()


func _owner_hero(sim: BattleSim, idx: int) -> BUnit:
	var u: BUnit = sim.u_at(idx)
	var guard: int = 0
	while u != null and not u.is_hero and guard < 6:
		u = sim.u_at(u.owner_idx)
		guard += 1
	return u


func _run() -> void:
	DB.ensure_loaded()
	var round_i: int = 0
	var out_path: String = ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--round="):
			round_i = int(arg.substr(8))
		elif arg.begins_with("--output="):
			out_path = arg.substr(9)
	var ids: Array = DB.ids().duplicate()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 150000 + round_i
	for i in range(ids.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp = ids[i]
		ids[i] = ids[j]
		ids[j] = tmp
	var half: int = ids.size() / 2
	var totals: Dictionary = {}
	for part in 2:
		var players: Array = ids.slice(0, half) if part == 0 else ids.slice(half)
		var map_id: String = DeathmatchMapData.ORDER[(round_i + part) % 3]
		var sim: BattleSim = BattleSim.new({"ruleset": "deathmatch", "arena_id": map_id, "players": players, "seed": 7100 + round_i * 10 + part, "max_time": 150.0, "kill_target": 99})
		for t in sim.team_count:
			sim.controllers[t] = AIFactory.make("tactician", sim, t)
		sim.start()
		while sim.state == BattleSim.RUNNING:
			sim.step()
			for ev in sim.tick_events:
				if str(ev.type) != "HEALTH_DAMAGED" or str(ev.get("source_type", "")) in ["ITEM", "REGEN"]:
					continue
				var src: BUnit = _owner_hero(sim, int(ev.s))
				var tgt: BUnit = sim.u_at(int(ev.g))
				if src == null or tgt == null or not tgt.is_hero or src == tgt:
					continue
				var row: Array = totals.get(src.def.id, [0.0, 0.0])
				row[0 if bool(ev.get("basic", false)) else 1] += float(ev.amount)
				totals[src.def.id] = row
		sim.dispose()
	var text: String = JSON.stringify(totals)
	print("CALIBRATION ", text)
	if out_path != "":
		var f: FileAccess = FileAccess.open(out_path, FileAccess.WRITE)
		f.store_string(text)
	quit(0)
