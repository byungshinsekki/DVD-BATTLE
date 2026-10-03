class_name BattleRunner
extends Node



signal stepped(events: Array)
signal finished(result: Dictionary)

var sim: BattleSim
var config: Dictionary = {}
var speed: float = 1.0
var paused: bool = false
var acc: float = 0.0
var alpha: float = 0.0
var hitstop: float = 0.0
var done: bool = false
var max_steps_per_frame: int = 12
var step_ms: float = 0.0


func start(cfg: Dictionary) -> void :
	dispose_sim()
	config = cfg.duplicate(true)
	if str(cfg.get("ruleset", "")) == "battleground":
		# V2 battleground (DESIGN_V2 §3.5 start config). Map generation runs in
		# BattleSim (DB.battleground_arena caches the two most recent maps).
		config["ruleset"] = "battleground"
		var br_cfg: Dictionary = {"seed": int(cfg.get("seed", 1)), "ruleset": "battleground",
			"arena_id": str(cfg.get("arena_id", BattlegroundMapData.ORDER[0])), "squad": int(cfg.get("squad", 1)),
			"teams": cfg.get("teams", []), "zone_speed": str(cfg.get("zone_speed", "normal")),
			"max_time": float(cfg.get("max_time", BattlegroundMode.MAX_TIME))}
		for key in ["map_seed", "items", "scale_lod"]:
			if cfg.has(key):
				br_cfg[key] = cfg[key]
		sim = BattleSim.new(br_cfg)
		sim.collect_frame_events = true
		for t in sim.team_count:
			sim.controllers[t] = AIFactory.make(str(cfg.get("ai", "tactician")), sim, t)
		sim.start()
	elif str(cfg.get("ruleset", "")) == "deathmatch":
		config["ruleset"] = "deathmatch"
		sim = BattleSim.new({"seed": int(cfg.get("seed", 1)), "ruleset": "deathmatch", "arena_id": str(cfg.get("arena_id", DeathmatchMapData.ORDER[0])),
			"players": cfg.get("players", []), "kill_target": int(cfg.get("kill_target", 10)), "max_time": float(cfg.get("max_time", 420.0))})
		sim.collect_frame_events = true
		for t in sim.team_count:
			sim.controllers[t] = AIFactory.make(str(cfg.get("ai", "tactician")), sim, t)
		sim.start()
	else:
		var arena: Arena = DB.arena(str(cfg.get("arena_id", "classic")))
		var ruleset: String = str(cfg.get("ruleset", arena.ruleset))
		config["ruleset"] = ruleset
		sim = BattleSim.new({"seed": int(cfg.get("seed", 1)), "blue": cfg.get("blue", []), "red": cfg.get("red", []), 
			"arena_id": str(cfg.get("arena_id", "classic")), "ruleset": ruleset, "max_time": float(cfg.get("max_time", 480.0 if ruleset == "control" else 150.0))})
		sim.collect_frame_events = true
		sim.controllers[0] = AIFactory.make(str(cfg.get("blue_ai", "tactician")), sim, 0)
		sim.controllers[1] = AIFactory.make(str(cfg.get("red_ai", "tactician")), sim, 1)
		sim.start()
	acc = 0.0
	alpha = 0.0
	done = false
	hitstop = 0.0
	var evs: = sim.drain_frame_events()
	if not evs.is_empty():
		stepped.emit(evs)


func dispose_sim() -> void :
	if sim:
		sim.dispose()
	sim = null


func _exit_tree() -> void :
	dispose_sim()



func warp(t: float) -> void :
	while sim and sim.state == BattleSim.RUNNING and sim.time < t:
		sim.step()
		sim.drain_frame_events()


func add_hitstop(sec: float) -> void :
	hitstop = maxf(hitstop, sec)


# Developer stepping uses exactly the same simulation and event path as playback.
func step_ticks(count: int = 1) -> int:
	paused = true
	acc = 0.0
	alpha = 0.0
	hitstop = 0.0
	var advanced: int = 0
	var started: int = Time.get_ticks_usec()
	for _i in clampi(count, 0, 300):
		if sim == null or done or sim.state != BattleSim.RUNNING:
			break
		sim.step()
		advanced += 1
		var events: Array = sim.drain_frame_events()
		if not events.is_empty():
			stepped.emit(events)
		if sim.state != BattleSim.RUNNING:
			done = true
			finished.emit(sim.result())
	if advanced > 0:
		step_ms = (Time.get_ticks_usec() - started) / 1000.0 / advanced
	return advanced


func _process(delta: float) -> void :
	if sim == null or done:
		return
	if paused:
		return
	if hitstop > 0.0:
		hitstop -= delta
		return
	acc += minf(delta, 0.1) * speed
	var steps: = 0
	var t0: = Time.get_ticks_usec()
	while acc >= BattleSim.DT and steps < max_steps_per_frame:
		acc -= BattleSim.DT
		steps += 1
		sim.step()
		var evs: = sim.drain_frame_events()
		if not evs.is_empty():
			stepped.emit(evs)
		if sim.state != BattleSim.RUNNING:
			done = true
			acc = 0.0
			finished.emit(sim.result())
			break
		if hitstop > 0.0:
			acc = 0.0
			break
	if steps > 0:
		step_ms = lerpf(step_ms, (Time.get_ticks_usec() - t0) / 1000.0 / steps, 0.1)
	if acc > BattleSim.DT * 4.0:
		acc = BattleSim.DT * 4.0
	alpha = clampf(acc / BattleSim.DT, 0.0, 1.0)
