extends DeathmatchBrain

# Timing wrapper around DeathmatchBrain (B-PERF tool only). Every override
# calls the unchanged implementation; only wall-clock timings are recorded
# (outside the simulation, so they never feed back into it).

const P := preload("res://tools/br_perf_v2/br_prof.gd")
const ProfIntel := preload("res://tools/br_perf_v2/br_prof_intel.gd")


func _init(s: BattleSim, t: int) -> void:
	super(s, t)
	intel.dispose()
	intel = ProfIntel.new(s, t)


func pre_tick(s: BattleSim) -> void:
	var t0: int = Time.get_ticks_usec()
	super.pre_tick(s)
	P.add("brain.pre_tick(total)", Time.get_ticks_usec() - t0)


func _plan() -> void:
	var t0: int = Time.get_ticks_usec()
	super._plan()
	P.add("brain._plan(incl intent)", Time.get_ticks_usec() - t0)


func _update_intent() -> void:
	var t0: int = Time.get_ticks_usec()
	super._update_intent()
	P.add("brain._update_intent", Time.get_ticks_usec() - t0)


func _pick_roam_goal() -> Vector2:
	var t0: int = Time.get_ticks_usec()
	var r: Vector2 = super._pick_roam_goal()
	P.add("brain._pick_roam_goal", Time.get_ticks_usec() - t0)
	return r


func decide(u: BUnit) -> void:
	var t0: int = Time.get_ticks_usec()
	super.decide(u)
	P.add("brain.decide", Time.get_ticks_usec() - t0)


func _move_candidates(u: BUnit, ctx: Dictionary, out: Array) -> void:
	var t0: int = Time.get_ticks_usec()
	super._move_candidates(u, ctx, out)
	P.add("brain._move_candidates", Time.get_ticks_usec() - t0)


func _ability_candidates(u: BUnit, ctx: Dictionary, out: Array) -> void:
	var t0: int = Time.get_ticks_usec()
	super._ability_candidates(u, ctx, out)
	P.add("brain._ability_candidates", Time.get_ticks_usec() - t0)


func _ctx(u: BUnit) -> Dictionary:
	var t0: int = Time.get_ticks_usec()
	var r: Dictionary = super._ctx(u)
	P.add("brain._ctx", Time.get_ticks_usec() - t0)
	return r


func steer(u: BUnit) -> Vector2:
	var t0: int = Time.get_ticks_usec()
	var r: Vector2 = super.steer(u)
	P.add("brain.steer", Time.get_ticks_usec() - t0)
	return r


func _route_waypoint(u: BUnit, goal: Vector2, r: float) -> Vector2:
	var t0: int = Time.get_ticks_usec()
	var w: Vector2 = super._route_waypoint(u, goal, r)
	P.add("brain._route_waypoint(nav)", Time.get_ticks_usec() - t0)
	return w


# --- finer sections (deep profile) ---

func _plan_core(allies: Array[BUnit], with_objectives: bool) -> void:
	var t0: int = Time.get_ticks_usec()
	super._plan_core(allies, with_objectives)
	P.add("brain._plan_core", Time.get_ticks_usec() - t0)


func danger_at(u: BUnit, p: Vector2, horizon: float = 1.0, visible_only: bool = false) -> float:
	var t0: int = Time.get_ticks_usec()
	var r: float = super.danger_at(u, p, horizon, visible_only)
	P.add("brain.danger_at", Time.get_ticks_usec() - t0)
	return r


func _offense_at(u: BUnit, p: Vector2, ctx: Dictionary, tgt: TeamIntel.EnemyBelief) -> float:
	var t0: int = Time.get_ticks_usec()
	var r: float = super._offense_at(u, p, ctx, tgt)
	P.add("brain._offense_at", Time.get_ticks_usec() - t0)
	return r


func _hazard_free_goal(u: BUnit, p: Vector2, r: float) -> Vector2:
	var t0: int = Time.get_ticks_usec()
	var q: Vector2 = super._hazard_free_goal(u, p, r)
	P.add("brain._hazard_free_goal", Time.get_ticks_usec() - t0)
	return q


func _route_hazard_cost(u: BUnit, p: Vector2, r: float, ms: float) -> float:
	var t0: int = Time.get_ticks_usec()
	var q: float = super._route_hazard_cost(u, p, r, ms)
	P.add("brain._route_hazard_cost", Time.get_ticks_usec() - t0)
	return q


func _gimmick_safe_goal(u: BUnit, p: Vector2, r: float, ms: float) -> Vector2:
	var t0: int = Time.get_ticks_usec()
	var q: Vector2 = super._gimmick_safe_goal(u, p, r, ms)
	P.add("brain._gimmick_safe_goal", Time.get_ticks_usec() - t0)
	return q


func _mud_cost(u: BUnit, p: Vector2, r: float, kiting: bool) -> float:
	var t0: int = Time.get_ticks_usec()
	var q: float = super._mud_cost(u, p, r, kiting)
	P.add("brain._mud_cost", Time.get_ticks_usec() - t0)
	return q


func _dodge_vector(u: BUnit) -> Vector2:
	var t0: int = Time.get_ticks_usec()
	var q: Vector2 = super._dodge_vector(u)
	P.add("brain._dodge_vector", Time.get_ticks_usec() - t0)
	return q


func _hazard_lookahead(u: BUnit, v: Vector2, r: float) -> Vector2:
	var t0: int = Time.get_ticks_usec()
	var q: Vector2 = super._hazard_lookahead(u, v, r)
	P.add("brain._hazard_lookahead", Time.get_ticks_usec() - t0)
	return q


func _link_soft_walls(u: BUnit, v: Vector2, r: float, goal: Vector2) -> Vector2:
	var t0: int = Time.get_ticks_usec()
	var q: Vector2 = super._link_soft_walls(u, v, r, goal)
	P.add("brain._link_soft_walls", Time.get_ticks_usec() - t0)
	return q


func _hazard_near(p: Vector2, reach: float) -> bool:
	var t0: int = Time.get_ticks_usec()
	var q: bool = super._hazard_near(p, reach)
	P.add("brain._hazard_near", Time.get_ticks_usec() - t0)
	return q


func _environment_move_points(u: BUnit, ctx: Dictionary, pts: Array) -> void:
	var t0: int = Time.get_ticks_usec()
	super._environment_move_points(u, ctx, pts)
	P.add("brain._environment_move_points", Time.get_ticks_usec() - t0)


func _gimmick_move_points(u: BUnit, ctx: Dictionary, pts: Array) -> void:
	var t0: int = Time.get_ticks_usec()
	super._gimmick_move_points(u, ctx, pts)
	P.add("brain._gimmick_move_points", Time.get_ticks_usec() - t0)


func _mode_move_points(u: BUnit, ctx: Dictionary, pts: Array) -> void:
	var t0: int = Time.get_ticks_usec()
	super._mode_move_points(u, ctx, pts)
	P.add("brain._mode_move_points", Time.get_ticks_usec() - t0)


func _sight_point(u: BUnit, e: TeamIntel.EnemyBelief, r: float) -> Vector2:
	var t0: int = Time.get_ticks_usec()
	var q: Vector2 = super._sight_point(u, e, r)
	P.add("brain._sight_point", Time.get_ticks_usec() - t0)
	return q


func _team_adjust(u: BUnit, ctx: Dictionary, cands: Array) -> void:
	var t0: int = Time.get_ticks_usec()
	super._team_adjust(u, ctx, cands)
	P.add("brain._team_adjust", Time.get_ticks_usec() - t0)


func _coordination_adjust(u: BUnit, ctx: Dictionary, cands: Array) -> void:
	var t0: int = Time.get_ticks_usec()
	super._coordination_adjust(u, ctx, cands)
	P.add("brain._coordination_adjust", Time.get_ticks_usec() - t0)


func _gimmick_adjust(u: BUnit, ctx: Dictionary, cands: Array) -> void:
	var t0: int = Time.get_ticks_usec()
	super._gimmick_adjust(u, ctx, cands)
	P.add("brain._gimmick_adjust", Time.get_ticks_usec() - t0)


func _mode_adjust(u: BUnit, ctx: Dictionary, cands: Array) -> void:
	var t0: int = Time.get_ticks_usec()
	super._mode_adjust(u, ctx, cands)
	P.add("brain._mode_adjust", Time.get_ticks_usec() - t0)


func _basic_candidates(u: BUnit, ctx: Dictionary, out: Array) -> void:
	var t0: int = Time.get_ticks_usec()
	super._basic_candidates(u, ctx, out)
	P.add("brain._basic_candidates", Time.get_ticks_usec() - t0)


func _escape_point(threat_c: Vector2) -> Vector2:
	var t0: int = Time.get_ticks_usec()
	var q: Vector2 = super._escape_point(threat_c)
	P.add("brain._escape_point", Time.get_ticks_usec() - t0)
	return q


func _hide_point() -> Vector2:
	var t0: int = Time.get_ticks_usec()
	var q: Vector2 = super._hide_point()
	P.add("brain._hide_point", Time.get_ticks_usec() - t0)
	return q


func _scan_public_signals() -> void:
	var t0: int = Time.get_ticks_usec()
	super._scan_public_signals()
	P.add("brain._scan_public_signals", Time.get_ticks_usec() - t0)


func _lod_travel(u: BUnit, ctx: Dictionary) -> bool:
	var t0: int = Time.get_ticks_usec()
	var q: bool = super._lod_travel(u, ctx)
	P.add("brain._lod_travel(tried)", Time.get_ticks_usec() - t0)
	if q:
		P.add("brain._lod_travel(taken)", 0)
	return q
