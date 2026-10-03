"""Standalone stdlib regressions using bundled producer fixtures and fake processes.

Run from a checkout or extracted source ZIP with:
    python -B tools/release_v2/test_known_draft_diagnostic.py
No Godot, Git, network, actual user profile or external fixture is used.
"""
import copy
import json
import os
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import release as r
import config
import validation


class KnownDraft(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="fake-draft-", dir=HERE)
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.qa = self.base / "qa"
        (self.qa / "tests").mkdir(parents=True)
        (self.qa / "tests/draft_14.gd").write_bytes((HERE / "test_fixtures/draft_14_gap_v1/draft_14.gd.txt").read_bytes())
        self.report = self.base / "reports/headless_assertions/draft_14.json"
        self.log = self.base / "logs/headless_draft_14.log"
        self.log.parent.mkdir(parents=True)

    def process(self, log=None, command=None):
        log = log or self.log
        return dict(suite="draft_14", status="FAIL", code=1, timeout=False, pid=123456, seconds=.3,
                    command=command or ["FAKE_ENGINE_NOT_EXECUTED", "--headless", "--path", str(self.qa), "--script", "res://tests/draft_14.gd"],
                    log=str(log), problems=[line for line in log.read_text(encoding="utf-8").splitlines() if r.PROBLEMS.search(line)],
                    cleanup_errors=[], cancelled=False, interrupted=False, exception=None, termination=None)

    def persist(self, process):
        r.write_json(Path(process["log"]).with_suffix(".log.process.json"), process)

    def fixture(self):
        receipt = r.prepare_draft_report(self.qa, self.report)
        Path(receipt["producer_report"]).write_bytes((HERE / "test_fixtures/draft_14_gap_v1/report.json").read_bytes())
        r.capture_draft_report(receipt)
        self.log.write_bytes((HERE / "test_fixtures/draft_14_gap_v1/stdout.txt").read_bytes())
        process = self.process()
        self.persist(process)
        return process, json.loads(self.report.read_text(encoding="utf-8"))

    def set_report(self, value):
        self.report.write_text(json.dumps(value), encoding="utf-8", newline="\n")
        self.refresh_capture_hash()

    def refresh_capture_hash(self):
        path = self.report.with_suffix(".capture.json")
        receipt = json.loads(path.read_text(encoding="utf-8"))
        receipt.update(captured_sha256=r.sha(self.report), producer_sha256=r.sha(self.report), captured_bytes=self.report.stat().st_size)
        r.write_json(path, receipt)

    def assert_rejected(self, process):
        with self.assertRaises((RuntimeError, ValueError, OSError, KeyError, TypeError)):
            r.completed_draft_failure(process, self.report, self.qa)

    def connectivity_fixture(self, report, log):
        """The same complete synthetic map failure used by the original policy tests."""
        report.parent.mkdir(parents=True, exist_ok=True)
        log.parent.mkdir(parents=True, exist_ok=True)
        failed = ["ruined_gate all radii and gate states: [closed courtyard]", "ruined_gate/r28 all radii and gate states: [closed courtyard]"]
        data = dict(suite=r.CONTINUABLE_SUITE, status="FAIL", passed=33, failed=failed, step=8.0, radii=[14,16,18,20,22,24],
                    maps=[dict(sample=sample, seconds=.25, issues=["closed courtyard"] if sample in ("ruined_gate", "ruined_gate/r28") else []) for sample in sorted(r.CONNECTIVITY_SAMPLES)],
                    historical_thorn=["geometric fixture " + str(i) for i in range(8)])
        lines = ["Godot fake fixture"] + [f"MAP_CONNECTIVITY_V2 sample={row['sample']} seconds=0.25 problems={len(row['issues'])}" for row in data["maps"]]
        lines += ["ERROR: MAP_CONNECTIVITY_V2 " + failure for failure in failed]
        lines += ["   at: push_error (core/variant/variant_utility.cpp:1024)", "MAP_CONNECTIVITY_V2 FAIL passed=33 failed=2"]
        log.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
        report.write_text(json.dumps(data), encoding="utf-8", newline="\n")
        process = dict(suite=r.CONTINUABLE_SUITE, status="FAIL", code=1, timeout=False, pid=123456, seconds=.3,
                       command=["fake_engine", "--script", "res://tests/map_connectivity_v2.gd", "--", "--report=" + report.resolve().as_posix()],
                       log=str(log), problems=[line for line in lines if r.PROBLEMS.search(line)])
        self.persist(process)
        return process

    def test_actual_producer_bytes_complete_known_failure_stays_fail(self):
        process, data = self.fixture()
        proof = r.completed_draft_failure(process, self.report, self.qa)
        self.assertEqual(proof["acceptance_status"], "FAIL")
        self.assertEqual(proof["failed"], data["failures"])
        self.assertEqual(proof["assertion_count"], 237)
        self.assertEqual(proof["fixture_sha256"], r.KNOWN_DRAFT_FIXTURE_SHA)
        self.assertEqual(data["measurements"][-1]["search"]["rollout"]["games"], 2)
        self.assertEqual(proof["infrastructure_error_count"], 0)

    def test_wrong_exit_crash_timeout_cancel_cleanup_and_missing_fields_rejected(self):
        mutations = [{"code":0}, {"code":124}, {"code":-1073741819}, {"code":True}, {"status":"PASS"},
                     {"timeout":True}, {"cancelled":True}, {"interrupted":True}, {"exception":"oops"},
                     {"cleanup_errors":["cleanup failure"]}, {"termination":{"errors":[]}}, {"pid":None}, {"suite":"draft_audit_14"}]
        for mutation in mutations:
            with self.subTest(mutation=mutation):
                process, _ = self.fixture(); process.update(mutation); self.persist(process); self.assert_rejected(process)
        for field in ("cleanup_errors", "cancelled", "interrupted", "exception", "termination"):
            process, _ = self.fixture(); process.pop(field); self.persist(process); self.assert_rejected(process)

    def test_persisted_process_mismatch_rejected(self):
        process, _ = self.fixture()
        self.persist({**process, "pid":42})
        self.assert_rejected(process)

    def test_command_wrong_qa_script_or_unexpected_option_rejected(self):
        for cmd in (["fake"], ["fake","--headless","--path",str(self.base / "wrong"),"--script","res://tests/draft_14.gd"],
                    ["fake","--headless","--path",str(self.qa),"--script","res://tests/other.gd"],
                    ["fake","--headless","--path",str(self.qa),"--script","res://tests/draft_14.gd","--","--report=ignored"]):
            process, _ = self.fixture(); process["command"] = cmd; self.persist(process); self.assert_rejected(process)

    def test_changed_fixture_and_capture_evidence_rejected(self):
        for mutation in ({"fixture_before_sha256":"f"*64,"fixture_after_sha256":"f"*64}, {"fixture_after_sha256":"e"*64},
                         {"cleared_bytes":5}, {"cleared_sha256":"a"*64}, {"status":"CLEARED"},
                         {"producer_report":"other"}, {"captured_report":"other"}, {"captured_sha256":"a"*64},
                         {"captured_bytes":0}, {"producer_sha256":"a"*64}):
            process, _ = self.fixture()
            path = self.report.with_suffix(".capture.json")
            receipt = json.loads(path.read_text(encoding="utf-8")); receipt.update(mutation); r.write_json(path, receipt)
            self.assert_rejected(process)

    def test_missing_empty_malformed_duplicate_nonfinite_reports_rejected(self):
        for text in ("", "{broken", '{"status":"FAIL","status":"PASS"}', '{"x":NaN}', '{"x":Infinity}', '{"x":1e999}'):
            process, _ = self.fixture(); self.report.write_text(text, encoding="utf-8")
            self.refresh_capture_hash()
            self.assert_rejected(process)
        process, _ = self.fixture(); self.report.unlink(); self.assert_rejected(process)

    def test_exact_labels_counts_status_and_complete_measurements_required(self):
        mutations = [lambda d:d.update(status="PASS"), lambda d:d.update(passed=230), lambda d:d.update(passed=True),
                     lambda d:d["failures"].append("new failure"), lambda d:d["failures"].pop(),
                     lambda d:d["failures"].__setitem__(0,"different failure"), lambda d:d["measurements"].pop(),
                     lambda d:d["measurements"].append(copy.deepcopy(d["measurements"][0])),
                     lambda d:d["measurements"][0].update(label="unexpected"), lambda d:d.update(extra=1)]
        for mutate in mutations:
            process, data = self.fixture(); mutate(data); self.set_report(data); self.assert_rejected(process)

    def test_rollout_and_candidate_budget_contract_cannot_change(self):
        mutations = [lambda s:s.update(budget=44999), lambda s:s.update(search_complete=False), lambda s:s.update(evals=41),
                     lambda s:s["per_candidate_evals"].pop("archer"), lambda s:s["per_candidate_evals"].update(archer=3),
                     lambda s:s["per_candidate_budget"].update(archer=2142), lambda s:s["rollout"].update(skipped="horizon"),
                     lambda s:s["rollout"].update(gap_gate=.03), lambda s:s["rollout"].update(games=4),
                     lambda s:s["rollout"].update(ticks=1), lambda s:s["rollout"].update(enabled=False),
                     lambda s:s["rollout"].update(horizon_ticks=299), lambda s:s["rollout"].update(tick_budget=2400),
                     lambda s:s["rollout"].update(rows=[{}]), lambda s:s["rollout"].update(weight=.25)]
        for mutate in mutations:
            process, data = self.fixture(); mutate(data["measurements"][8]["search"]); self.set_report(data); self.assert_rejected(process)

    def test_every_measurement_payload_and_nested_search_is_required(self):
        for index in range(10):
            process, data = self.fixture()
            data["measurements"][index] = {"label":data["measurements"][index]["label"]}
            self.set_report(data); self.assert_rejected(process)
        mutations = [lambda rows:rows[0]["search"].pop("rollout"), lambda rows:rows[1]["search"]["opponent_model"].clear(),
                     lambda rows:rows[2]["search"]["policy_completion"].clear(), lambda rows:rows[3]["search"]["per_candidate_budget"].clear(),
                     lambda rows:rows[6].update(largest_slice_ms=-1), lambda rows:rows[7]["three"]["forecast"].pop(),
                     lambda rows:rows[7]["five"]["forecast"][0].pop("id"),
                     lambda rows:rows[9]["search"]["rollout"]["rows"][0].pop("finished")]
        for mutate in mutations:
            process, data = self.fixture(); mutate(data["measurements"]); self.set_report(data); self.assert_rejected(process)

    def test_extra_errors_warnings_failure_output_and_summary_mismatch_rejected(self):
        for addition in ("ERROR: unrelated", "SCRIPT ERROR: boom", "Parse Error: syntax", "WARNING: leaked object", "some FAIL", "DRAFT 1.4 FAIL passed=231 failures=6"):
            process, _ = self.fixture()
            self.log.write_text(self.log.read_text(encoding="utf-8") + addition + "\n", encoding="utf-8", newline="\n")
            process["problems"] = [line for line in self.log.read_text(encoding="utf-8").splitlines() if r.PROBLEMS.search(line)]
            self.persist(process); self.assert_rejected(process)
        for summary in ("", "DRAFT 1.4 PASS passed=237 failures=0", "DRAFT 1.4 FAIL passed=230 failures=6"):
            process, _ = self.fixture()
            self.log.write_text(self.log.read_text(encoding="utf-8").replace("DRAFT 1.4 FAIL passed=231 failures=6", summary), encoding="utf-8", newline="\n")
            self.assert_rejected(process)

    def test_log_hash_and_raw_capture_remain_independent_of_later_qa_rebuild(self):
        process, data = self.fixture()
        proof = r.completed_draft_failure(process, self.report, self.qa)
        (self.qa / "reports/draft_14.json").write_text("overwritten later", encoding="utf-8")
        (self.qa / "tests/draft_14.gd").write_text("later QA copy", encoding="utf-8")
        self.assertEqual(r.completed_draft_failure(process, self.report, self.qa), proof)
        self.assertEqual(json.loads(self.report.read_text(encoding="utf-8")), data)

    def test_policy_final_install_rejected_before_release_or_helper(self):
        with patch.object(r, "Release", side_effect=AssertionError("No initialization")), patch.object(r, "ensure_helper", side_effect=AssertionError("No helper")):
            for mode in ("--final", "--install-helper"):
                for flags in (["--continue-on-known-draft-failure"], ["--continue-on-test-failure", "--continue-on-known-draft-failure"]):
                    with self.assertRaisesRegex(RuntimeError, "only with --dry-run"): r.main([mode, *flags])

    def test_policy_identity_changes_with_flag_and_fixture_version(self):
        options = SimpleNamespace(final=False, dry_run=True, continue_on_known_draft_failure=False)
        disabled = r.known_draft_failure_policy(options)
        options.continue_on_known_draft_failure = True
        enabled = r.known_draft_failure_policy(options)
        self.assertNotEqual(r.digest(disabled), r.digest(enabled))
        self.assertEqual(enabled["allowed_suites"], ["draft_14"])
        self.assertEqual(enabled["fixture_sha256"], r.KNOWN_DRAFT_FIXTURE_SHA)

    def test_resume_flag_change_rejected_before_any_profile_inventory(self):
        project = self.base / "resume_project"; project.mkdir()
        pg = project / "project.godot"; pg.write_text('config/custom_user_dir_name="FAKE_ONLY"\n',encoding="utf-8")
        options = SimpleNamespace(final=False,dry_run=True,out=self.base / "scratch/out",run_id="fake_resume",with_telemetry=False,
                                  baseline_summary=None,resume_final=False,continue_on_test_failure=False,continue_on_known_draft_failure=False)
        def fake_git(_project,*args):return "" if args[0] == "status" else "fakehead"
        with patch.object(config,"PROJECT",project), patch.object(config,"SCRATCH",self.base / "scratch"), patch.object(config,"RELEASE",self.base / "final"), \
             patch.object(r,"git",side_effect=fake_git), patch.object(r,"runtime_hashes",return_value={}), patch.object(r,"verification_hashes",return_value={}), \
             patch.object(r,"source_paths",return_value=[(pg,"project.godot")]), patch.object(r.Release,"binary_hashes",return_value={}), \
             patch.object(r.Release,"tool_hashes",return_value={}), patch.object(r,"legacy_inventory",return_value={}), \
             patch.dict(os.environ,{"APPDATA":str(self.base / "FAKE_PROFILE_NEVER_READ")}):
            with patch.object(r,"profile_inventory",return_value={}):first = r.Release(options)
            self.assertFalse(first.identity["known_draft_failure_policy"]["enabled"])
            options.continue_on_known_draft_failure = True
            with patch.object(r,"profile_inventory",side_effect=AssertionError("Must stop before profile access")):
                with self.assertRaisesRegex(RuntimeError,"Resume input changed"):r.Release(options)
            options.continue_on_known_draft_failure = False
            with patch.object(r,"KNOWN_DRAFT_FIXTURE_SHA","a"*64), patch.object(r,"profile_inventory",side_effect=AssertionError("Must stop before profile access")):
                with self.assertRaisesRegex(RuntimeError,"Resume input changed"):r.Release(options)

    def run_s2(self, draft_enabled=True, map_enabled=False, map_failure=False, other_failure=False, fresh=True):
        obj = object.__new__(r.Release)
        obj.options = SimpleNamespace(final=False, dry_run=True, continue_on_test_failure=map_enabled,
                                      continue_on_known_draft_failure=draft_enabled, jobs=1, with_telemetry=True, baseline_summary=None)
        obj.test_failure_policy = r.test_failure_policy(obj.options)
        obj.project, obj.reports, obj.logs, obj.out = self.base / "project", self.base / "reports", self.log.parent, self.base / "out"
        obj.profiles, obj.state_path = self.base / "FAKE_PROFILES_UNUSED", obj.reports / "run_state.json"
        obj.project.mkdir(exist_ok=True); obj.out.mkdir(exist_ok=True)
        obj.source = {"head":"fake", "input_sha256":"f"*64}
        obj.identity = {"known_draft_failure_policy":obj.known_draft_failure_policy}
        obj.state, obj.unchanged = {"stages":{}, "complete":False}, lambda:None
        emptied = []
        def godot(args, name, check=False):
            suite = name.removeprefix("headless_")
            command = ["FAKE_ENGINE_NOT_EXECUTED", *map(str,args)]
            log = obj.logs / (name + ".log")
            if suite == "draft_14":
                if draft_enabled:
                    fixed = self.qa / "reports/draft_14.json"
                    emptied.append(fixed.read_bytes() == b"")
                    if fresh: fixed.write_bytes((HERE / "test_fixtures/draft_14_gap_v1/report.json").read_bytes())
                log.write_bytes((HERE / "test_fixtures/draft_14_gap_v1/stdout.txt").read_bytes())
                process = self.process(log, command)
            elif suite == r.CONTINUABLE_SUITE:
                target = Path(next(arg[9:] for arg in command if arg.startswith("--report=")))
                if map_failure:
                    return self.connectivity_fixture(target, log)
                r.write_json(target, dict(suite=suite, status="PASS", passed=35, failed=[]))
                log.write_text("MAP_CONNECTIVITY_V2 PASS passed=35 failed=0\n", encoding="utf-8", newline="\n")
                process = self.process(log, command); process.update(status="PASS",code=0,suite=suite)
            else:
                log.write_text("ERROR: unexpected failure\n" if other_failure else "OTHER PASS\n", encoding="utf-8", newline="\n")
                process = self.process(log, command); process.update(status="FAIL" if other_failure else "PASS",code=1 if other_failure else 0,suite=suite)
            self.persist(process)
            return process
        obj.godot = godot
        suites = ["draft_14", r.CONTINUABLE_SUITE, "environment_153"]
        with patch.object(config,"QA",self.qa), patch.object(r,"copy_project",return_value={}), patch.object(r,"import_project",return_value=[]), patch.object(r,"REQUIRED_HEADLESS",set(suites)), patch.object(r,"discover_tests",return_value={"headless":suites}):
            result = obj.S2()
        self.assertEqual(emptied, [True] if draft_enabled else [])
        return obj, result

    def test_default_and_map_flag_alone_do_not_allow_draft_failure(self):
        for map_enabled in (False, True):
            _, result = self.run_s2(draft_enabled=False, map_enabled=map_enabled)
            self.assertEqual(result["status"], "FAIL")
            self.assertEqual(result["continued_test_failures"], [])

    def test_draft_flag_preserves_fail_and_captures_fresh_raw_report(self):
        obj, result = self.run_s2()
        self.assertEqual((result["status"],result["acceptance_status"],result["release_eligible"]), ("WARN","FAIL",False))
        test = next(row for row in result["tests"] if row["suite"] == "draft_14")
        self.assertEqual(test["status"], "FAIL")
        self.assertEqual(Path(test["assertion_report"]).read_bytes(), (HERE / "test_fixtures/draft_14_gap_v1/report.json").read_bytes())
        self.assertIn(test["assertion_capture"], result["output_hashes"])
        obj.stage("S2", lambda:result)
        for path in (test["log"],test["log"] + ".process.json",test["assertion_report"],test["assertion_capture"]):
            self.assertIn(path,obj.state["stages"]["S2"]["output_hashes"])

    def test_both_failure_flags_are_required_for_both_suites(self):
        _, result = self.run_s2(map_failure=True)
        self.assertEqual(result["status"],"FAIL")
        _, both = self.run_s2(map_enabled=True,map_failure=True)
        self.assertEqual(both["status"],"WARN")
        self.assertEqual({row["suite"] for row in both["continued_test_failures"]},{"draft_14",r.CONTINUABLE_SUITE})

    def test_unknown_failure_or_stale_fixed_report_still_stops(self):
        for args in ({"other_failure":True},{"fresh":False}):
            _, result = self.run_s2(**args)
            self.assertEqual(result["status"],"FAIL")
            self.assertEqual(result["continued_test_failures"],[])

    def test_execution_complete_is_not_acceptance_and_exit_two(self):
        obj, result = self.run_s2()
        for index in range(12):
            stage = {"status":"PASS"}
            if index == 0: stage.update(known_draft_failure_policy=obj.known_draft_failure_policy,test_failure_policy=obj.test_failure_policy)
            if index == 2: stage = result
            if index == 10: r.write_json(obj.out / "release_manifest_v2.json", {"fixture":True})
            setattr(obj,f"S{index}",lambda value=stage:copy.deepcopy(value))
        self.assertEqual(obj.execute(),2)
        completion = json.loads((obj.out / "release_completion_v2.json").read_text(encoding="utf-8"))
        self.assertEqual((completion["complete"],completion["execution_complete"],completion["acceptance_status"],completion["release_eligible"],completion["exit_code"]),(True,True,"FAIL",False,2))
        text = (obj.out / "POST_PACKAGE_VALIDATION_2.0_KO.txt").read_text(encoding="utf-8")
        self.assertIn("FAIL | C6/C8 HOLD",text)
        self.assertIn("draft_14 | FAIL | 1",text)
        for label in r.KNOWN_DRAFT_FAILURES:self.assertIn("FAIL: " + label,text)
        self.assertIn(r.KNOWN_DRAFT_FIXTURE_SHA,text)
        self.assertEqual(completion["known_draft_failure_policy"],obj.known_draft_failure_policy)

    def test_main_propagates_two_without_running_initializer(self):
        with patch.object(r,"Release",return_value=SimpleNamespace(execute=lambda:2)):
            self.assertEqual(r.main(["--dry-run","--continue-on-known-draft-failure","--out",str(self.base / "out")]),2)


if __name__ == "__main__":
    unittest.main(verbosity=2)
