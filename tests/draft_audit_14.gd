extends SceneTree

var passed: int = 0
var failed: Array[String] = []
var cases: Array = []

# Observe the public evaluator rather than reproducing the search algorithm.
# This catches extra completion evaluations hidden outside the quota wrapper.
class CountingDirector extends DraftDirector:
	var actual_requests: int = 0
	var cache_hit_requests: int = 0
	var full_team_requests: int = 0

	func value(ai: int, user: int) -> float:
		actual_requests += 1
		if _v_cache.has(ai * SHIFT + user):
			cache_hit_requests += 1
		if members(ai).size() == team_size and members(user).size() == team_size:
			full_team_requests += 1
		return super.value(ai, user)

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed.append(label)
		push_error("DRAFT AUDIT: " + label)

func _run() -> void:
	DB.ensure_loaded()
	feature_order_invariance()
	budget_and_depth()
	cancel_and_restart()
	rollout_signs()
	finalist_fairness()
	completion_contract()
	completion_cancel()
	var report: Dictionary = {"status": "PASS" if failed.is_empty() else "FAIL", "passed": passed, "failed": failed, "cases": cases}
	var file: FileAccess = FileAccess.open("res://reports/draft_audit_14.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("DRAFT_AUDIT_14 ", JSON.stringify({"status": report.status, "passed": passed, "failed": failed}))
	quit(0 if failed.is_empty() else 1)

func feature_order_invariance() -> void:
	for id in ["fisherman", "plague_doctor", "blood_mage"]:
		var original: Defs.CharDef = DB.char_def(id)
		var permuted: Defs.CharDef = Defs.CharDef.new()
		for property in original.get_property_list():
			if (int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0: continue
			var value = original.get(str(property.name))
			permuted.set(str(property.name), value.duplicate() if value is Array or value is Dictionary else value)
		permuted.abilities.reverse()
		var normal: Dictionary = DraftDirector.kit_features(original)
		var reversed: Dictionary = DraftDirector.kit_features(permuted)
		check(absf(float(normal.area) - float(reversed.area)) < 0.000001, id + " area evaluation is independent of skill list order")
		check(original.abilities[0].index == 0, id + " audit did not mutate shared definition")

func budget_and_depth() -> void:
	for budget in [26, 27, 88, 800, 4500]:
		var d: DraftDirector = DraftDirector.new({"team_size": 3, "arena_id": "classic", "seed": 14, "budget": budget,
			"rollout_enabled": false, "max_depth": 5, "user_history": {"mage": 9, "world_tree": 8, "hive_mind": 5}})
		d.begin(["archer"], [])
		var max_committed: int = 0
		var limit: int = 0
		while not d.advance(31):
			var progress: Dictionary = d.progress()
			check(int(progress.completed_depth) >= max_committed, "committed depth never decreases, budget %d" % budget)
			max_committed = int(progress.completed_depth)
			limit += 1
			if limit > 20000: break
		var result: Dictionary = d.result()
		check(not result.is_empty() and int(result.search.evals) <= budget, "total evaluation cap %d" % budget)
		check(int(result.search.covered_candidates) == int(result.search.candidates), "all legal candidates covered at budget %d" % budget)
		var sum_evals: int = 0
		var sum_quota: int = 0
		var minimum_quota: int = 999999
		var maximum_quota: int = 0
		for id in result.search.per_candidate_evals:
			var used: int = result.search.per_candidate_evals[id]
			var quota: int = result.search.per_candidate_budget[id]
			check(used <= quota and used >= 1, "candidate quota respected: %d %s" % [budget, id])
			sum_evals += used
			sum_quota += quota
			minimum_quota = mini(minimum_quota, quota)
			maximum_quota = maxi(maximum_quota, quota)
		check(sum_evals == int(result.search.evals) and sum_quota == budget, "evaluation accounting closes at %d" % budget)
		check(maximum_quota - minimum_quota <= 1, "candidate budget differs by at most one at %d" % budget)
		var common_depth: int = int(result.search.completed_depth)
		for root in d._job.roots:
			check((root.line as Array).size() == (4 if common_depth >= 1 else 0), "only completed policy layer supplies full forecast")
		cases.append({"budget": budget, "evals": result.search.evals, "depth": common_depth, "pick": result.id})
		d.cancel()

func cancel_and_restart() -> void:
	var options: Dictionary = {"team_size": 2, "arena_id": "control_citadel", "ruleset": "control", "seed": 1414, "budget": 800, "rollout_enabled": false, "max_depth": 4}
	var d: DraftDirector = DraftDirector.new(options)
	d.begin(["archer"], [])
	d.advance(7)
	d.cancel()
	var count_at_cancel: int = d.evals
	check(d.result().is_empty() and bool(d.progress().cancelled), "cancellation discards incomplete decision")
	check(d.advance(100) and d.evals == count_at_cancel, "cancelled job cannot spend more evaluations")
	d.begin(["archer"], [])
	while not d.advance(1): pass
	var restarted: Dictionary = d.result().duplicate(true)
	var fresh: DraftDirector = DraftDirector.new(options)
	fresh.begin(["archer"], [])
	while not fresh.advance_until(Time.get_ticks_usec() + 1000): pass
	check(JSON.stringify(restarted) == JSON.stringify(fresh.result()), "cancel restart and time-sliced scheduling preserve deterministic result")
	d.cancel()
	fresh.cancel()
	var rollout: DraftDirector = DraftDirector.new({"team_size": 1, "budget": 22, "max_depth": 1, "rollout_tick_budget": 1200, "rollout_gap": 1.0})
	rollout.begin(["mage"], [])
	while str(rollout.progress().phase) != "rollout" and not bool(rollout.progress().done): rollout.advance(1)
	rollout.advance(3)
	check(rollout._job.rollout_sim != null, "rollout cancellation test starts a real isolated simulation")
	rollout.cancel()
	check(rollout._job.rollout_sim == null and rollout._job.director == null and rollout.result().is_empty(), "cancel disposes active rollout and director reference")

func rollout_signs() -> void:
	var director: DraftDirector = DraftDirector.new({"team_size": 1})
	var search: DraftSearch14 = DraftSearch14.new(director, ["mage"], [])
	for mode in ["elimination", "control"]:
		var sim: BattleSim = BattleSim.new({"blue": ["archer"], "red": ["mage"], "ruleset": mode, "arena_id": "control_crossroads" if mode == "control" else "classic"})
		sim.start()
		sim.heroes[0].hp *= 0.4
		if mode == "control":
			sim.time = 20.0
			sim.domination.scores = [7.0, 2.0]
			sim.domination.points[0].owner = 0
		check(absf(search._rollout_value(sim, 0) + search._rollout_value(sim, 1)) < 0.000001, mode + " unfinished signal changes sign with side")
		sim.finish(2, "audit_draw")
		check(is_zero_approx(search._rollout_value(sim, 0)) and is_zero_approx(search._rollout_value(sim, 1)), mode + " completed draw is neutral on both sides")
		sim.winner = 0
		check(search._rollout_value(sim, 0) == 1.0 and search._rollout_value(sim, 1) == -1.0, mode + " terminal winner uses actual side")
		sim.dispose()
	search.cancel()
	director.cancel()

func finalist_fairness() -> void:
	# Controlled final-layer evidence: both engine-tested finalists lose their
	# paired rollouts. A third untested static candidate must not leapfrog them.
	var director: DraftDirector = DraftDirector.new({"team_size": 1, "seed": 14, "budget": 22})
	var search: DraftSearch14 = DraftSearch14.new(director, ["mage"], [])
	search.covered = search.roots.size()
	search.completed_depth = 1
	for root in search.roots: root.evals = 1
	search.calls = search.roots.size()
	search.final_candidates = [
		{"id": "archer", "score": 0.15, "search_score": 0.15, "static": 0.15, "reply": "", "line": []},
		{"id": "engineer", "score": 0.14, "search_score": 0.14, "static": 0.14, "reply": "", "line": []},
		{"id": "swordsman", "score": 0.13, "search_score": 0.13, "static": 0.13, "reply": "", "line": []}]
	search.rollout_jobs = [{"id": "archer", "side": 0}, {"id": "archer", "side": 1}, {"id": "engineer", "side": 0}, {"id": "engineer", "side": 1}]
	search.rollout_rows = [{"id": "archer", "side": 0, "value": -1.0}, {"id": "archer", "side": 1, "value": -1.0}, {"id": "engineer", "side": 0, "value": -1.0}]
	search.rollout_cursor = 3
	search.phase = "rollout"
	search.rollout_sim = BattleSim.new({"blue": ["mage"], "red": ["engineer"]})
	search.rollout_sim.start()
	search.rollout_sim.finish(0, "audit_controlled_loss")
	search._rollout_step()
	check(str(director.result().id) in ["archer", "engineer"], "unverified static third place cannot bypass equally tested finalists")
	check(search.rollout_sim == null, "completed final rollout releases isolated simulation")
	director.cancel()

func _forecast_teams(d: DraftDirector, root: Dictionary, user: Array, ai: Array) -> Dictionary:
	var ours: Array = ai.duplicate()
	var theirs: Array = user.duplicate()
	ours.append(d.ids[root.idx])
	var next_side: String = "user"
	var legal: bool = true
	for row in root.line:
		if (theirs if next_side == "user" else ours).size() >= d.team_size:
			next_side = "ai" if next_side == "user" else "user"
		var id: String = str(row.get("id", ""))
		var side: String = str(row.get("side", ""))
		legal = legal and d.index.has(id) and id not in ours and id not in theirs and side == next_side
		if side == "ai": ours.append(id)
		elif side == "user": theirs.append(id)
		else: legal = false
		legal = legal and ours.size() <= d.team_size and theirs.size() <= d.team_size
		next_side = "ai" if next_side == "user" else "user"
	return {"legal": legal, "ai": ours, "user": theirs, "full": ours.size() == d.team_size and theirs.size() == d.team_size}

func _committed_roots(d: DraftDirector) -> Array:
	var snapshot: Array = []
	for root in d._job.roots:
		snapshot.append({"score": root.score, "line": (root.line as Array).duplicate(true)})
	return snapshot

func completion_contract() -> void:
	var first_layer_scores: Dictionary = {}
	for mode in ["elimination", "control"]:
		for size in [3, 5]:
			for depth_limit in [1, 7]:
				var label: String = "%s %dv%d depth%d" % [mode, size, size, depth_limit]
				var opts: Dictionary = {"team_size": size, "arena_id": "classic" if mode == "elimination" else "control_crossroads",
					"ruleset": mode, "seed": 140417, "budget": 45000, "max_depth": depth_limit, "rollout_enabled": false}
				var d: CountingDirector = CountingDirector.new(opts)
				d.begin(["archer"], [])
				var last_depth: int = 0
				var snapshot: Array = _committed_roots(d)
				var largest_step_requests: int = 0
				var work: int = 0
				while not bool(d.progress().done) and work < 500000:
					var before: int = d.actual_requests
					d.advance(1)
					largest_step_requests = maxi(largest_step_requests, d.actual_requests - before)
					var current_depth: int = int(d.progress().completed_depth)
					if current_depth > last_depth:
						last_depth = current_depth
						snapshot = _committed_roots(d)
					work += 1
				check(bool(d.progress().done), label + " bounded work reaches completion")
				var result: Dictionary = d.result()
				if result.is_empty():
					check(false, label + " has a completed decision")
					d.cancel()
					continue
				check(largest_step_requests <= 1, label + " each scheduler work unit performs at most one evaluation")
				check(d.actual_requests == int(result.search.evals), label + " every evaluator request is inside search accounting")
				check(d.actual_requests <= int(result.search.budget), label + " completion respects total evaluation cap")
				check(int(result.search.completed_depth) >= 1 and bool(result.search.forecast_complete), label + " default budget commits full team policy layer")
				check(_committed_roots(d) == snapshot, label + " partial next layer cannot overwrite common committed scores or lines")
				check(d.full_team_requests >= d._job.roots.size(), label + " final team states were actually evaluated")
				var scores: Array = []
				var quota_total: int = 0
				for root in d._job.roots:
					var teams: Dictionary = _forecast_teams(d, root, ["archer"], [])
					check(bool(teams.legal) and bool(teams.full), label + " full legal alternating forecast for " + str(d.ids[root.idx]))
					check(int(root.evals) <= int(root.quota), label + " root completion quota for " + str(d.ids[root.idx]))
					quota_total += int(root.evals)
					scores.append(root.score)
					if depth_limit == 1:
						var oracle: DraftDirector = DraftDirector.new(opts)
						check(is_equal_approx(float(root.score), oracle.evaluate_state(teams.user, teams.ai)), label + " policy score evaluates its completed roster")
						oracle.cancel()
				check(quota_total == d.actual_requests, label + " candidate quotas include all completion work")
				if depth_limit == 7:
					check(d.cache_hit_requests > 0 and int(result.search.evals) > int(result.search.cache_misses), label + " cache hits remain counted budget requests")
				else:
					first_layer_scores[mode + str(size)] = scores
				cases.append({"completion": label, "work": work, "evals": d.actual_requests, "cache_hits": d.cache_hit_requests,
					"full_team_evals": d.full_team_requests, "depth": result.search.completed_depth, "forecast_count": result.forecast.size(), "pick": result.id})
				d.cancel()
		check(first_layer_scores.get(mode + "3", []) != first_layer_scores.get(mode + "5", []), mode + " first-pick values account for three versus five team slots")
	var tiny: DraftDirector = DraftDirector.new({"team_size": 5, "budget": 26, "rollout_enabled": false})
	var fallback: Dictionary = tiny.decide([], [])
	check(int(fallback.search.completed_depth) == 0 and not bool(fallback.search.forecast_complete) and fallback.forecast.is_empty(), "insufficient policy budget explicitly reports uncompleted prefix fallback")
	check(int(fallback.search.covered_candidates) == 26 and int(fallback.search.evals) == 26, "minimum budget still covers every legal root fairly")
	tiny.cancel()

func completion_cancel() -> void:
	var options: Dictionary = {"team_size": 5, "arena_id": "control_citadel", "ruleset": "control", "seed": 1414,
		"budget": 45000, "rollout_enabled": false, "max_depth": 1}
	var d: CountingDirector = CountingDirector.new(options)
	d.begin(["archer"], [])
	var entered_completion: bool = false
	for _step in 10000:
		d.advance(1)
		for root in d._job.roots:
			if not root.stack.is_empty() and str(root.stack.back().stage).begins_with("completion") and int(root.evals) > 3:
				entered_completion = true
		if entered_completion or bool(d.progress().done): break
	check(entered_completion, "cancellation fixture reaches in-progress policy completion")
	var before_expired: Dictionary = d.progress().duplicate(true)
	var requests_before: int = d.actual_requests
	d.advance_until(Time.get_ticks_usec() - 1)
	check(d.progress() == before_expired and d.actual_requests == requests_before, "expired UI deadline performs no completion work")
	var old_job: RefCounted = d._job
	d.cancel()
	old_job.advance(1000)
	var all_empty: bool = true
	for root in old_job.roots: all_empty = all_empty and root.stack.is_empty()
	check(all_empty and old_job.director == null and d.actual_requests == requests_before and d.result().is_empty(), "cancel drops every completion frame and prevents stale work")
	d.actual_requests = 0
	d.begin(["engineer"], [])
	while not d.advance(29): pass
	var fresh: DraftDirector = DraftDirector.new(options)
	var expected: Dictionary = fresh.decide(["engineer"], [])
	check(d.result() == expected, "restart after policy cancellation has no old candidate or cache side effects")
	d.cancel()
	fresh.cancel()
