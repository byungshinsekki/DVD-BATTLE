extends SceneTree

var passed: int = 0
var failures: Array = []
var measurements: Array = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failures.append(label)
		push_error(label)

func _run() -> void:
	DB.ensure_loaded()
	for mode in ["elimination", "control"]:
		for size in [1, 3, 5]:
			structure(mode, size)
	frame_splitting()
	cancel_resume()
	mode_and_history()
	completion_horizon()
	rollout_contract()
	final_pick_performance()
	var report: Dictionary = {"status": "PASS" if failures.is_empty() else "FAIL", "passed": passed, "failures": failures, "measurements": measurements}
	var file: FileAccess = FileAccess.open("res://reports/draft_14.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("DRAFT 1.4 ", report.status, " passed=", passed, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func options(mode: String, size: int, budget_: int = 45000) -> Dictionary:
	return {"team_size": size, "arena_id": "classic" if mode == "elimination" else "control_crossroads", "ruleset": mode,
		"seed": 9173, "budget": budget_, "rollout_enabled": false}

func structure(mode: String, size: int) -> void:
	var dd: DraftDirector = DraftDirector.new(options(mode, size))
	var started: int = Time.get_ticks_usec()
	var result_: Dictionary = dd.decide(["archer"], [])
	var search: Dictionary = result_.search
	var label: String = "%s %dv%d" % [mode, size, size]
	check(result_.id != "archer" and DB.char_def(result_.id) != null, label + " legal choice")
	check(int(search.evals) <= int(search.budget), label + " strict total budget")
	check(int(search.covered_candidates) == 25, label + " all legal candidates covered")
	var total: int = 0
	var limits: Array = []
	for id: String in search.per_candidate_evals:
		var spent: int = search.per_candidate_evals[id]
		var limit: int = search.per_candidate_budget[id]
		check(spent >= 1 and spent <= limit, label + " candidate quota " + id)
		total += spent
		limits.append(limit)
	check(total == int(search.evals), label + " all work accounted")
	limits.sort()
	check(int(limits.back()) - int(limits.front()) <= 1, label + " equal candidate quotas")
	check(int(search.completed_depth) >= 1 and int(search.completed_depth) <= int(search.target_depth), label + " completed depth truthful")
	var searched_steps: int = 0
	var forecast_ids: Dictionary = {"archer": true}
	forecast_ids[result_.id] = true
	for step_: Dictionary in result_.forecast:
		searched_steps += 0 if bool(step_.get("policy", false)) else 1
		check(not forecast_ids.has(step_.id), label + " completed policy picks stay legal")
		forecast_ids[step_.id] = true
	check(searched_steps <= int(search.completed_depth) - 1, label + " searched depth excludes policy completion")
	check(result_.forecast.size() == size * 2 - 2 and search.forecast_complete, label + " every default root receives full composition forecast")
	check(search.policy_completion.completed_candidates == search.candidates, label + " uniform full-completion coverage")
	measurements.append({"label": label, "id": result_.id, "milliseconds": (Time.get_ticks_usec() - started) / 1000.0, "search": search})
	dd.cancel()

func frame_splitting() -> void:
	var opts: Dictionary = options("control", 3, 5500)
	var direct: Dictionary = DraftDirector.new(opts).decide(["archer"], [])
	var sliced: DraftDirector = DraftDirector.new(opts)
	sliced.begin(["archer"], [])
	var calls: int = 0
	while not sliced.advance(1 if calls % 2 == 0 else 17):
		calls += 1
	check(sliced.result() == direct, "frame work partition does not change result or budget")
	var deadline: DraftDirector = DraftDirector.new(opts)
	deadline.begin(["archer"], [])
	var before: Dictionary = deadline.progress()
	check(not deadline.advance_until(Time.get_ticks_usec() - 1), "expired deadline yields immediately")
	check(deadline.progress() == before, "expired deadline performs no work")
	var worst_us: int = 0
	while not bool(deadline.progress().done):
		var start: int = Time.get_ticks_usec()
		deadline.advance_until(start + 1000)
		worst_us = maxi(worst_us, Time.get_ticks_usec() - start)
	check(deadline.result() == direct, "wall time slicing does not change deterministic result")
	measurements.append({"label": "1ms cooperative static search", "largest_slice_ms": worst_us / 1000.0})
	var tiny: Dictionary = DraftDirector.new(options("elimination", 5, 26)).decide([], [])
	check(tiny.search.evals == 26 and tiny.search.covered_candidates == 26, "minimum budget covers every roster candidate exactly once")
	check(tiny.search.completed_depth == 0 and tiny.search.policy_completion.prefix_fallback, "tiny budget is honestly marked uniform prefix fallback")

func cancel_resume() -> void:
	var dd: DraftDirector = DraftDirector.new(options("elimination", 5))
	dd.begin(["engineer"], [])
	dd.advance(50)
	dd.cancel()
	check(dd.progress().cancelled and dd.progress().done and dd.result().is_empty(), "cancel exposes no partial committed choice")
	var after: Dictionary = dd.progress()
	check(dd.advance(100) and dd.progress() == after, "cancelled search does no further work")
	dd.begin(["archer"], [])
	while not dd.advance(511):
		pass
	check(not dd.result().is_empty() and not dd.progress().cancelled, "cancelled director supports fresh begin")
	check(dd.result().id != "archer", "restart uses new draft state")

func mode_and_history() -> void:
	var elimination: DraftDirector = DraftDirector.new(options("elimination", 3, 5000))
	var control: DraftDirector = DraftDirector.new(options("control", 3, 5000))
	var team: Array = [DraftDirector.kit_features(DB.char_def("politician")), DraftDirector.kit_features(DB.char_def("world_tree")), DraftDirector.kit_features(DB.char_def("archer"))]
	check(not is_equal_approx(elimination.mode_composition(team), control.mode_composition(team)), "rulesets use different composition models")
	var public_counts: Dictionary = {"giant": 40, "politician": 18, "archer": 5}
	var copy: Dictionary = public_counts.duplicate(true)
	var opts: Dictionary = options("elimination", 3, 8000)
	opts.user_history = public_counts
	var model: DraftDirector = DraftDirector.new(opts)
	var result_: Dictionary = model.decide(["archer"], [])
	check(public_counts == copy, "opponent model never modifies player records")
	check(is_equal_approx(result_.search.opponent_model.worst_weight + result_.search.opponent_model.expected_weight, 1.0), "bounded worst-case and expectation blend")
	check(result_.search.opponent_model.history_prior_max <= 0.3, "history cannot dominate rational counterplay")
	check(result_.id != "archer", "history cannot make an already picked character legal")
	var preferred: DraftDirector = DraftDirector.new(options("elimination", 3))
	preferred.user_history = {"world_tree": 1000}
	preferred.begin(["archer"], [])
	var frame: Dictionary = {"remaining": 5, "ply": 1, "turn": -1, "rows": []}
	for i in preferred.ids.size():
		if preferred.ids[i] != "archer":
			frame.rows.append({"idx": i, "value": float(i), "weight": 0.0})
	preferred._job._rank_frame(frame)
	var total_p: float = 0.0
	var found: bool = false
	for move: Dictionary in frame.moves:
		total_p += move.weight
		found = found or preferred.ids[move.idx] == "world_tree"
	check(found, "strong recorded preference is considered beyond static counter beam")
	check(is_equal_approx(total_p, 1.0), "response probabilities form a normalized distribution")
	preferred.cancel()

func rollout_contract() -> void:
	var opts: Dictionary = options("elimination", 1)
	opts.rollout_enabled = true
	opts.rollout_tick_budget = 1200
	# V1.5.3 (DR-3): the production engine check runs only for nearby
	# finalists. This lifecycle fixture must enter that phase independently of
	# the learned table's score scale (the 26-hero gap can exceed 1.0).
	# Measure the same static finalists first, then use a finite gate strictly
	# above their actual gap. The production default and all rollout assertions
	# below stay unchanged; final_pick_performance also tests the default gate.
	var static_opts: Dictionary = opts.duplicate(true)
	static_opts.rollout_enabled = false
	var static_result: Dictionary = DraftDirector.new(static_opts).decide(["giant"], [])
	check(not static_result.alternatives.is_empty(), "rollout fixture has two static finalists")
	if static_result.alternatives.is_empty():
		return
	var static_gap: float = float(static_result.search_score) - float(static_result.alternatives[0].search_score)
	check(is_finite(static_gap) and static_gap >= 0.0, "rollout fixture static gap is finite and ordered")
	if not is_finite(static_gap):
		return
	opts.rollout_gap = static_gap + 1.0
	var dd: DraftDirector = DraftDirector.new(opts)
	dd.begin(["giant"], [])
	while dd.progress().phase != "rollout" and not dd.progress().done:
		dd.advance(1)
	check(dd.progress().phase == "rollout", "final-pick actual-engine phase starts")
	dd.advance(4)
	check(dd.progress().rollout_ticks <= 3, "rollout yields between individual ticks")
	dd.cancel()
	check(dd.progress().cancelled and dd.result().is_empty(), "actual-engine phase can be cancelled")
	var first: Dictionary = DraftDirector.new(opts).decide(["giant"], [])
	var second: DraftDirector = DraftDirector.new(opts)
	second.begin(["giant"], [])
	while not second.advance(7):
		pass
	check(first == second.result(), "actual-engine results independent of frame slicing")
	var row: Dictionary = first.search.rollout
	check(row.games == 4 and row.ticks <= 1200, "two candidates with mirrored sides obey fixed tick budget")
	check(row.weight <= 0.24, "short rollout is a bounded supporting signal")
	var seen: Dictionary = {}
	for match_: Dictionary in row.rows:
		seen[str(match_.id) + str(match_.side)] = true
		check(match_.ticks <= 300, "rollout per-game horizon respected")
	check(seen.size() == 4, "rollout candidate side coverage is balanced")
	check(seen.has(str(first.id) + "0") and seen.has(str(first.id) + "1"), "chosen finalist received both engine side trials")
	check(first.alternatives.size() == 1 and first.alternatives[0].score_basis == "search_and_engine", "only comparable finalists appear as engine alternatives")
	var fixture: BattleSim = BattleSim.new({"blue": ["giant"], "red": ["giant"]})
	fixture.state = BattleSim.FINISHED
	fixture.winner = 2
	check(second._job._rollout_value(fixture, 0) == 0.0 and second._job._rollout_value(fixture, 1) == 0.0, "engine draw winner2 is neutral for both sides")
	fixture.dispose()
	measurements.append({"label": "actual-engine bounded rollout", "search": first.search})

func completion_horizon() -> void:
	var three: Dictionary = DraftDirector.new(options("control", 3)).decide([], [])
	var five: Dictionary = DraftDirector.new(options("control", 5)).decide([], [])
	check(three.forecast.size() == 5 and five.forecast.size() == 9, "same empty prefix forecasts actual requested team size")
	check(not is_equal_approx(three.search_score, five.search_score), "three and five player leaf values account for remaining slots")
	check(three.search.policy_completion.evals > 0 and five.search.policy_completion.evals > 0, "completion work is measured within evaluation quota")
	check(three.search.policy_completion.completed_candidates == 26 and five.search.policy_completion.completed_candidates == 26, "all opening candidates have full-team policy evaluation")
	measurements.append({"label": "full-composition horizon", "three": {"id": three.id, "value": three.search_score, "depth": three.search.completed_depth, "forecast": three.forecast},
		"five": {"id": five.id, "value": five.search_score, "depth": five.search.completed_depth, "forecast": five.forecast}})

func final_pick_performance() -> void:
	var opts: Dictionary = options("control", 5)
	opts.rollout_enabled = true
	var dd: DraftDirector = DraftDirector.new(opts)
	dd.begin(["swordsman", "archer", "mage", "giant", "politician"], ["werewolf", "sniper", "metatron", "engineer"])
	var slices: Array = []
	var start: int = Time.get_ticks_usec()
	while not dd.progress().done:
		var before: int = Time.get_ticks_usec()
		dd.advance_until(before + 8000)
		slices.append(Time.get_ticks_usec() - before)
	slices.sort()
	var result_: Dictionary = dd.result()
	# V1.5.3 (DR-3): the default engine check is skipped unless the finalists
	# are within 0.03, and a control check lasts 60 s (1800 ticks) per game,
	# one paired game per finalist on the same side (3600 ticks in total).
	var ro: Dictionary = result_.search.rollout
	var finalist_gap: float = float(result_.search_score) - float(result_.alternatives[0].search_score) if not result_.alternatives.is_empty() else 0.0
	if str(ro.get("skipped", "")) == "gap":
		check(ro.games == 0 and ro.ticks == 0 and finalist_gap > float(ro.gap_gate), "default control5v5 last pick skips the engine check for distant finalists")
		check(result_.score_basis == "search", "skipped engine check keeps the search score basis")
	else:
		check(ro.games == 2 and ro.horizon_ticks >= 1800 and ro.ticks <= 3600, "default control5v5 last-pick fixed 60 s paired engine budget")
		check(result_.score_basis == "search_and_engine", "default last-pick explains experimental score basis")
	measurements.append({"label": "control5v5 final pick default 8ms slices", "wall_seconds": (Time.get_ticks_usec() - start) / 1000000.0,
		"slice_count": slices.size(), "largest_slice_ms": slices.back() / 1000.0, "p95_slice_ms": slices[int(slices.size() * 0.95)] / 1000.0,
		"id": result_.id, "search": result_.search})
