extends SceneTree

var passed: int = 0
var failed: Array[String] = []
var measurements: Array = []


class CountingDirector extends DraftDirector:
	var requests: int = 0

	func value(ai: int, user: int) -> float:
		requests += 1
		return super.value(ai, user)


class FixedWidthSearch extends DraftSearch14:
	# Experimental control: retain the former 6/4/3 beam while using the same
	# current evaluator, terminal evidence, inputs and evaluation allowance.
	func _plan_horizon(_legal_count: int, _remaining: int, _quota: int) -> void:
		pass


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed.append(label)
		push_error("DRAFT SEARCH V2: " + label)


func _run() -> void:
	DB.ensure_loaded()
	budget_horizon()
	terminal_evidence()
	public_control_objective()
	var report: Dictionary = {"status": "PASS" if failed.is_empty() else "FAIL", "passed": passed,
		"failed": failed, "measurements": measurements}
	print("DRAFT_SEARCH_V2_HOTFIX ", JSON.stringify(report))
	quit(0 if failed.is_empty() else 1)


func _search(options: Dictionary, fixed_width: bool, work: int) -> Dictionary:
	var d: CountingDirector = CountingDirector.new(options)
	d.begin([], [])
	if fixed_width:
		d.cancel()
		d._job = FixedWidthSearch.new(d, [], [])
	var started: int = Time.get_ticks_usec()
	while not d.advance(work):
		pass
	var decision: Dictionary = d.result().duplicate(true)
	check(d.requests == int(decision.search.evals), "every request counted, fixed width=" + str(fixed_width))
	check(d.requests <= int(options.budget), "unchanged total evaluation budget, fixed width=" + str(fixed_width))
	var quota_total: int = 0
	var lowest_quota: int = 999999
	var highest_quota: int = 0
	for id: String in decision.search.per_candidate_budget:
		var limit: int = decision.search.per_candidate_budget[id]
		check(int(decision.search.per_candidate_evals[id]) <= limit, "candidate quota " + id)
		quota_total += limit
		lowest_quota = mini(lowest_quota, limit)
		highest_quota = maxi(highest_quota, limit)
	check(quota_total == int(options.budget) and highest_quota - lowest_quota <= 1, "all candidates receive equal quota")
	check(int(decision.search.covered_candidates) == DB.ids().size(), "all roster candidates covered")
	for root: Dictionary in d._job.roots:
		var seen: Dictionary = {d.ids[root.idx]: true}
		var sides: Dictionary = {"ai": 1, "user": 0}
		for row: Dictionary in root.line:
			check(not seen.has(row.id), "forecast has no duplicate pick")
			seen[row.id] = true
			sides[row.side] += 1
		check(int(sides.ai) == d.team_size and int(sides.user) == d.team_size, "every candidate has a complete legal team forecast")
	measurements.append({"fixed_width": fixed_width, "mode": options.ruleset, "milliseconds": (Time.get_ticks_usec() - started) / 1000.0,
		"pick": decision.id, "depth": decision.search.completed_depth, "evals": decision.search.evals,
		"horizon_plan": decision.search.horizon_plan})
	d.cancel()
	return decision


func budget_horizon() -> void:
	var options: Dictionary = {"team_size": 5, "arena_id": "control_crossroads", "ruleset": "control", "seed": 2601003,
		"budget": 45000, "rollout_enabled": false}
	var fixed: Dictionary = _search(options, true, 1024)
	var planned: Dictionary = _search(options, false, 1024)
	check(int(planned.search.completed_depth) > int(fixed.search.completed_depth), "same 5v5 opening budget completes a deeper opponent-response horizon")
	check(int(planned.search.horizon_plan.planned_depth) <= int(planned.search.completed_depth), "cost plan is conservative about completed depth")
	check(int(planned.search.horizon_plan.beam_cap) >= 2, "budget planning retains alternative rational replies")
	var sliced: Dictionary = _search(options, false, 13)
	check(planned == sliced, "adaptive horizon is independent of scheduler partition")
	var tiny: DraftDirector = DraftDirector.new({"team_size": 5, "budget": 26, "rollout_enabled": false})
	var fallback: Dictionary = tiny.decide([], [])
	check(int(fallback.search.evals) == 26 and fallback.search.policy_completion.prefix_fallback, "minimum budget remains honest uniform prefix coverage")
	tiny.cancel()


func terminal_evidence() -> void:
	var d: CountingDirector = CountingDirector.new({"team_size": 2, "arena_id": "classic", "ruleset": "elimination", "seed": 26,
		"budget": 45000, "max_depth": 2, "rollout_enabled": false})
	d.begin(["archer"], ["mage"])
	var largest_unit: int = 0
	while not bool(d.progress().done):
		var before: int = d.requests
		d.advance(1)
		largest_unit = maxi(largest_unit, d.requests - before)
	var result: Dictionary = d.result()
	check(largest_unit <= 1 and d.requests == int(result.search.evals), "terminal reuse preserves one evaluation per scheduler unit and exact accounting")
	check(int(result.search.horizon_plan.terminal_evidence_reuses) > 0, "last-slot complete-roster evidence is reused")
	check(bool(result.search.search_complete) and int(result.search.completed_depth) == 2, "last-slot enumeration still completes the actual draft")
	d.cancel()


func public_control_objective() -> void:
	var d: DraftDirector = DraftDirector.new({"team_size": 1, "ruleset": "control", "arena_id": "control_crossroads", "rollout_enabled": false})
	var search: DraftSearch14 = DraftSearch14.new(d, ["archer"], [])
	var sim: BattleSim = BattleSim.new({"blue": ["mage"], "red": ["archer"], "ruleset": "control", "arena_id": "control_crossroads"})
	sim.start()
	sim.time = 60.0
	for point: Dictionary in sim.domination.points:
		point.owner = -1
		point.progress = 0.0
		point.contested = false
	var neutral: float = search._rollout_value(sim, 0)
	sim.domination.points[0].progress = -0.8
	var capturing: float = search._rollout_value(sim, 0)
	check(capturing > neutral, "unfinished own capture has positive objective value")
	check(is_equal_approx(capturing, -search._rollout_value(sim, 1)), "public capture signal reverses with side")
	sim.domination.points[0].progress = 0.8
	check(search._rollout_value(sim, 0) < neutral, "enemy capture progress is a disadvantage")
	sim.domination.points[0].progress = 0.0
	sim.domination.points[0].owner = 0
	var uncontested: float = search._rollout_value(sim, 0)
	sim.domination.points[0].contested = true
	check(search._rollout_value(sim, 0) < uncontested, "contested owner no longer earns the full uncontested holding bonus")
	sim.domination.points[0].contested = false
	for point: Dictionary in sim.domination.points:
		point.owner = 0
	var all_three: float = search._rollout_value(sim, 0)
	var saved: Array[Dictionary] = sim.domination.points.duplicate(true)
	sim.domination.points.resize(1)
	check(is_equal_approx(search._rollout_value(sim, 0), all_three), "holding every point is normalized by actual public point count")
	sim.domination.points = saved
	for point: Dictionary in sim.domination.points:
		point.owner = -1
	sim.domination.scores = [30.0, 0.0]
	check(search._rollout_value(sim, 0) > neutral, "earned control points improve the trial result")
	sim.finish(2, "draft_hotfix_fixture_draw")
	check(is_zero_approx(search._rollout_value(sim, 0)) and is_zero_approx(search._rollout_value(sim, 1)), "terminal draw overrides all provisional objective evidence")
	sim.dispose()
	search.cancel()
	d.cancel()
