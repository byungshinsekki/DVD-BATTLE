"""Pure stdlib regressions; fixtures resolve relative to the extracted module.

No engine, subprocess, temporary file, profile, or external fixture is used.
"""
import copy
import json
from pathlib import Path
import sys
import unittest

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import draft26_payload as payload


class Draft26Payload(unittest.TestCase):
	@classmethod
	def setUpClass(cls):
		fixture = HERE / "test_fixtures/draft_14_roster26_v1"
		cls.original = json.loads((fixture / "report.json").read_text(encoding="utf-8"))
		cls.stdout = (fixture / "stdout.txt").read_text(encoding="utf-8").splitlines()
		cls.errors = ["ERROR: " + value for value in payload.FAILURES]

	def setUp(self):
		self.data = copy.deepcopy(self.original)
		self.lines = list(self.stdout)
		self.problems = list(self.errors)

	def validate(self):
		return payload.validate(self.data, self.lines, self.problems)

	def rejected(self):
		with self.assertRaises(RuntimeError):
			self.validate()

	def test_actual_complete_report_is_failure_and_input_is_unchanged(self):
		before = copy.deepcopy((self.data, self.lines, self.problems))
		proof = self.validate()
		self.assertEqual(proof["status"], "FAIL")
		self.assertEqual(proof["acceptance_status"], "FAIL")
		self.assertEqual((proof["passed"], proof["assertion_count"], proof["measurement_count"]), (255, 261, 10))
		self.assertEqual(proof["failed"], list(payload.FAILURES))
		self.assertEqual(proof["measurements"], self.data["measurements"])
		self.assertEqual(proof["infrastructure_error_count"], 0)
		self.assertEqual(before, (self.data, self.lines, self.problems))
		proof["measurements"][0]["id"] = "mutated returned copy"
		self.assertEqual(before, (self.data, self.lines, self.problems))

	def test_closed_roster_and_fixed_prefix_candidate_sets(self):
		self.assertEqual(payload.ROSTER, tuple(sorted(payload.ROSTER)))
		self.assertEqual(len(set(payload.ROSTER)), 26)
		self.assertEqual(payload.LEGAL, set(payload.ROSTER) - {"giant"})
		self.assertEqual(len(payload.LEGAL), 25)
		self.assertEqual(len(payload.FINAL_LEGAL), 17)
		self.assertTrue(set(("achilles", "hades", "torquemada", "war_machine")) <= set(payload.ROSTER))

	def test_root_schema_status_counts_and_exact_failure_order(self):
		for mutation in (lambda d:d.update(extra=0), lambda d:d.pop("status"), lambda d:d.update(status="PASS"),
			lambda d:d.update(passed=True), lambda d:d.update(passed=255.0), lambda d:d.update(passed=231),
			lambda d:d["failures"].reverse(), lambda d:d["failures"].append("new failure"),
			lambda d:d["failures"].pop(), lambda d:d["failures"].__setitem__(0,"different failure")):
			self.setUp(); mutation(self.data); self.rejected()
		for value in (None, [], True, "report"):
			self.setUp(); self.data=value; self.rejected()

	def test_measurement_coverage_labels_order_and_full_schema(self):
		for index in range(10):
			self.setUp(); self.data["measurements"][index] = {"label":payload.LABELS[index]}; self.rejected()
		for mutation in (lambda m:m.pop(), lambda m:m.append(copy.deepcopy(m[0])), lambda m:m.reverse(),
			lambda m:m[0].update(label="changed"), lambda m:m[3].update(extra=0)):
			self.setUp(); mutation(self.data["measurements"]); self.rejected()

	def test_each_search_member_is_required(self):
		for index in (0, 1, 2, 3, 4, 5, 8, 9):
			for field in self.original["measurements"][index]["search"]:
				with self.subTest(index=index, field=field):
					self.setUp(); self.data["measurements"][index]["search"].pop(field); self.rejected()

	def test_nested_policy_model_and_rollout_schema_is_closed(self):
		for nested in ("policy_completion", "opponent_model", "rollout"):
			for field in self.original["measurements"][0]["search"][nested]:
				self.setUp(); self.data["measurements"][0]["search"][nested].pop(field); self.rejected()
			self.setUp(); self.data["measurements"][0]["search"][nested]["extra"]=0; self.rejected()

	def test_all_numeric_leaves_reject_nonfinite_bool_and_string(self):
		def numeric_paths(value, path=()):
			if type(value) in (int,float):
				yield path
			elif isinstance(value,dict):
				for key,item in value.items():
					yield from numeric_paths(item,path+(key,))
			elif isinstance(value,list):
				for key,item in enumerate(value):
					yield from numeric_paths(item,path+(key,))
		for path in numeric_paths(self.original):
			for invalid in (float("nan"), float("inf"), -float("inf"), True, "1"):
				with self.subTest(path=path, invalid=invalid):
					self.setUp(); node=self.data
					for key in path[:-1]: node=node[key]
					node[path[-1]]=invalid; self.rejected()

	def test_boolean_leaves_reject_integer_substitutes(self):
		for path in (("forecast_complete",), ("search_complete",), ("policy_completion","enabled"),
			("policy_completion","prefix_fallback"), ("rollout","enabled"), ("rollout","final_pick_only"), ("rollout","finalists_only")):
			self.setUp(); node=self.data["measurements"][0]["search"]
			for key in path[:-1]: node=node[key]
			node[path[-1]]=int(node[path[-1]]); self.rejected()

	def test_candidates_cannot_be_dropped_or_replaced_with_unknown_or_picked(self):
		for index, replacement in ((0,"archer"),(8,"giant"),(9,"engineer"),(0,"unknown")):
			self.setUp(); search=self.data["measurements"][index]["search"]
			for field in ("per_candidate_budget","per_candidate_evals"):
				value=search[field].pop("achilles"); search[field][replacement]=value
			self.rejected()
		self.setUp(); search=self.data["measurements"][8]["search"]
		for hero in ("achilles","hades","torquemada","war_machine"):
			search["per_candidate_budget"].pop(hero); search["per_candidate_evals"].pop(hero)
		search.update(candidates=21, covered_candidates=21); self.rejected()

	def test_budget_evaluation_and_coverage_totals_must_agree(self):
		for mutation in (lambda s:s.update(budget=44999), lambda s:s.update(covered_candidates=24),
			lambda s:s.update(forecast_complete=False), lambda s:s.update(completed_depth=0),
			lambda s:s.update(completed_depth=999), lambda s:s.update(evals=49),
			lambda s:s["per_candidate_evals"].update(achilles=1801),
			lambda s:s["per_candidate_budget"].update(achilles=1799),
			lambda s:s["policy_completion"].update(completed_candidates=24),
			lambda s:s["policy_completion"].update(prefix_fallback=True),
			lambda s:s["opponent_model"].update(worst_weight=.8)):
			self.setUp(); mutation(self.data["measurements"][0]["search"]); self.rejected()

	def test_bounded_search_exact_metrics_are_required(self):
		for field in ("cache_misses","nodes","depth","completed_depth","target_depth","candidates","covered_candidates","evals","budget"):
			self.setUp(); self.data["measurements"][8]["search"][field]+=1; self.rejected()
		self.setUp(); self.data["measurements"][8]["search"]["search_complete"]=False; self.rejected()
		self.setUp(); search=self.data["measurements"][8]["search"]
		search["per_candidate_budget"].update(achilles=1799, aphrodite=1801); self.rejected()
		self.setUp(); search=self.data["measurements"][8]["search"]
		search["per_candidate_evals"].update(achilles=1, aphrodite=3); self.rejected()

	def test_bounded_rollout_exact_gap_contract_required(self):
		changes={"enabled":False,"final_pick_only":False,"finalists_only":False,"games":1,"gap_gate":.03,
			"horizon_ticks":301,"min_horizon_ticks":299,"rows":[{}],"sides_per_finalist":1,
			"skipped":"horizon","tick_budget":1201,"ticks":1,"weight":.25}
		for field,value in changes.items():
			self.setUp(); self.data["measurements"][8]["search"]["rollout"][field]=value; self.rejected()

	def test_full_horizon_forecast_required(self):
		for name in ("three","five"):
			for mutation in (lambda r:r["forecast"].pop(), lambda r:r.update(depth=0), lambda r:r.update(id="unknown"),
				lambda r:r["forecast"][0].update(side="opponent"), lambda r:r["forecast"][0].update(policy=1),
				lambda r:r["forecast"][0].update(extra=0), lambda r:r["forecast"][0].pop("id")):
				self.setUp(); mutation(self.data["measurements"][7][name]); self.rejected()

	def test_choices_times_and_scores_are_not_pinned(self):
		self.data["measurements"][0].update(id="war_machine",milliseconds=321.125)
		self.data["measurements"][6]["largest_slice_ms"]=99.0
		self.data["measurements"][7]["three"]["value"]=-.125
		self.data["measurements"][9].update(id="achilles",wall_seconds=99.0,slice_count=500,largest_slice_ms=10.5,p95_slice_ms=1.5)
		self.assertEqual(self.validate()["passed"],255)

	def test_actual_last_row_gap_is_not_the_old_two_game_fixture(self):
		row=self.data["measurements"][9]["search"]
		self.assertEqual((row["candidates"],row["rollout"]["games"],row["rollout"]["ticks"],row["rollout"]["skipped"]),(17,0,0,"gap"))
		self.validate()

	def engine_trials(self):
		rollout=self.data["measurements"][9]["search"]["rollout"]
		rollout.update(games=2,ticks=3600,skipped="",rows=[
			{"id":"hades","side":0,"ticks":1800,"seconds":60.0,"value":.1,"finished":False},
			{"id":"achilles","side":0,"ticks":1800,"seconds":60.0,"value":-.1,"finished":False}])
		return rollout

	def test_last_row_full_trial_shape_can_describe_other_valid_measurement(self):
		self.engine_trials(); self.validate()

	def test_last_row_trial_schema_counts_and_finite_values_required(self):
		for mutation in (lambda r:r["rows"][0].pop("finished"), lambda r:r.update(games=3),lambda r:r.update(ticks=3599),
			lambda r:r["rows"][0].update(ticks=1801),lambda r:r["rows"][0].update(seconds=float("inf")),
			lambda r:r["rows"][0].update(value=float("nan")),lambda r:r["rows"][0].update(value=1.1),
			lambda r:r["rows"][0].update(id="engineer"),lambda r:r["rows"][0].update(side=True),
			lambda r:r["rows"][0].update(finished=0)):
			self.setUp(); mutation(self.engine_trials()); self.rejected()

	def test_stdout_extra_errors_warnings_and_unclassified_lines_rejected(self):
		for extra in ("ERROR: unrelated","SCRIPT ERROR: issue","Parse Error: issue","WARNING: issue","some FAIL","all good",payload.SUMMARY):
			self.setUp(); self.lines.append(extra)
			self.problems=[line for line in self.lines if payload.SEVERITY.search(line)]
			self.rejected()

	def test_stdout_error_order_backtrace_header_and_summary_are_exact(self):
		for old,new in ((payload.SUMMARY,"DRAFT 1.4 FAIL passed=254 failures=6"),
			(payload.SUMMARY,"DRAFT 1.4 PASS passed=261 failures=0"),(payload.HEADER,"Godot fake engine"),
			("       [1] rollout_contract (res://tests/draft_14.gd:155)","       [1] rollout_contract (res://tests/draft_14.gd:999)")):
			self.setUp(); self.lines=[new if line==old else line for line in self.lines]; self.rejected()
		self.setUp(); self.lines.reverse(); self.rejected()
		self.setUp(); self.lines=[line for line in self.lines if line != payload.SUMMARY]; self.rejected()

	def test_problem_list_cannot_hide_or_invent_failure(self):
		for change in (lambda p:p.pop(), lambda p:p.reverse(), lambda p:p.append("ERROR: extra")):
			self.setUp(); change(self.problems); self.rejected()
		self.problems=tuple(self.errors); self.rejected()

	def test_lines_must_be_complete_individual_strings(self):
		for lines in ("\n".join(self.stdout), [None], ["\n".join(self.stdout)], [line+"\r" for line in self.stdout]):
			self.setUp(); self.lines=lines; self.rejected()

	def test_public_shape_validator_does_not_require_known_failure(self):
		measured=copy.deepcopy(self.original["measurements"])
		self.assertIsNone(payload.complete_measurements(measured))
		measured[8]["search"]["rollout"]["gap_gate"]=.5
		self.assertIsNone(payload.complete_measurements(measured))
		measured[0]["id"]=[]
		with self.assertRaises(RuntimeError): payload.complete_measurements(measured)

	def test_malformed_unhashable_values_raise_runtime_error(self):
		for mutation in (lambda d:d["measurements"][0].update(id=[]), lambda d:d["measurements"][9].update(id={}),
			lambda d:d["measurements"][8].update(search=[]), lambda d:d.update(measurements=None)):
			self.setUp(); mutation(self.data); self.rejected()


if __name__ == "__main__":
	unittest.main(verbosity=2)
