extends SceneTree

# V1.5 conquest AI evaluation: how steadily one AI kind assigns heroes to
# objectives. Three mirrored 5v5 conquest matches (same composition and AI on
# both teams). Every 0.5 s it samples each living hero's current objective
# order and counts changes of objective ("flips"), jumps between the two
# outer objectives, time spent on heal-zone trips and time on objectives.
#
# godot --headless --path . --script res://tools/ai_eval_15/assignment_probe_15.gd -- \
#     --ai=tactician --out=reports/ai_eval_15/assignment_probe_tactician.jsonl

const COMPS := [["giant", "archer", "engineer", "aphrodite", "werewolf"], ["swordsman", "sniper", "mage", "metatron", "pirate"],
	["nitro", "hermes", "world_tree", "plague_doctor", "joker"]]
const ARENAS := ["control_crossroads", "control_citadel", "control_waterway"]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DB.ensure_loaded()
	var args: Dictionary = {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var i: int = arg.find("=")
			args[arg.substr(2, i - 2)] = arg.substr(i + 1)
	var ai: String = str(args.get("ai", "tactician"))
	var out_path: String = str(args.get("out", ""))
	var out: FileAccess = null
	if out_path != "":
		DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
		out = FileAccess.open(out_path, FileAccess.READ_WRITE if FileAccess.file_exists(out_path) else FileAccess.WRITE)
		out.seek_end()
	for m in 3:
		var comp: Array = COMPS[m]
		var sim := BattleSim.new({"ruleset": "control", "arena_id": ARENAS[m], "blue": comp, "red": comp, "seed": 900 + m, "max_time": 480.0})
		sim.controllers[0] = AIFactory.make(ai, sim, 0)
		sim.controllers[1] = AIFactory.make(ai, sim, 1)
		sim.start()
		var last: Dictionary = {}
		var flips: Array = [0, 0]
		var far_flips: Array = [0, 0]
		var heal_trip: Array = [0.0, 0.0]
		var on_point: Array = [0.0, 0.0]
		var alive_t: Array = [0.0, 0.0]
		var owned_t: Array = [0.0, 0.0]
		while sim.state == BattleSim.RUNNING:
			sim.step()
			if sim.tick % 15 != 0:
				continue
			for p in sim.domination.points:
				if int(p.owner) >= 0:
					owned_t[int(p.owner)] += 0.5
			for u in sim.heroes:
				if not u.alive:
					continue
				alive_t[u.team] += 0.5
				var ex: Dictionary = sim.controllers[u.team].explain(u).get("control", {}).get("assignment", {})
				var pt: int = int(ex.get("point", -1))
				if str(ex.get("heal_target", "")) != "":
					heal_trip[u.team] += 0.5
				for p in sim.domination.points:
					if u.pos.distance_to(p.center) <= float(p.radius):
						on_point[u.team] += 0.5
				if last.has(u.idx) and int(last[u.idx]) != pt and pt >= 0 and int(last[u.idx]) >= 0:
					flips[u.team] += 1
					if absi(pt - int(last[u.idx])) == 2:
						far_flips[u.team] += 1
				last[u.idx] = pt
		var row: Dictionary = {"ai": ai, "match": m, "arena": ARENAS[m], "comp": comp, "winner": sim.winner, "t": snappedf(sim.time, 0.1),
			"flips": flips, "far_flips": far_flips, "heal_trip_s": heal_trip, "on_point_s": on_point, "alive_s": alive_t, "owned_s": owned_t}
		print("MATCH ", JSON.stringify(row))
		if out:
			out.store_line(JSON.stringify(row))
			out.flush()
		sim.dispose()
	if out:
		out.close()
	quit(0)
