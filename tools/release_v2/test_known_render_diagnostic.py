"""Standalone render diagnostic checks with bundled bytes and fake processes.

No engine, Git, network or actual user profile is used. All lifecycle receipts
below are synthetic test data, not a claim about a real C8 execution.
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
import config
import release as r
import render_diagnostic as d
import validation


class KnownRender(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="fake-render-", dir=HERE)
        self.addCleanup(self.temp.cleanup)
        self.addCleanup(patch.stopall)
        self.base = Path(self.temp.name)
        self.project, self.qa = self.base / "project", self.base / "qa"
        self.reports = self.base / "reports"
        self.logs = self.reports / "logs"
        self.logs.mkdir(parents=True)
        self.report = self.reports / "headless_assertions/render_v2.stdout.json"
        self.log = self.logs / "headless_render_v2.log"
        self.profiles = self.base / "scratch/profiles"
        self.profile = self.profiles / "headless_render_v2"
        self.fixture = HERE / "test_fixtures/render_v2_known_v1"
        patch.multiple(config, QA=self.qa, SCRATCH=self.base / "scratch", GODOT=self.base / "FAKE_ENGINE_NEVER_EXECUTED.exe").start()
        for root in (self.project, self.qa):
            (root / "tests").mkdir(parents=True)
            (root / "tests/render_v2.gd").write_bytes((self.fixture / "render_v2.gd.txt").read_bytes())

    def process(self, log=None, command=None, success=False):
        log = log or self.log
        return dict(suite=d.SUITE, status="PASS" if success else "FAIL", code=0 if success else 1,
                    timeout=False, pid=123456, seconds=.3, log=str(log),
                    command=command or [str(config.GODOT), "--headless", "--path", str(self.qa), "--script", "res://tests/render_v2.gd"],
                    problems=[line for line in log.read_text(encoding="utf-8").splitlines() if r.PROBLEMS.search(line)],
                    appdata=str(self.profile / "Roaming"), localappdata=str(self.profile / "Local"),
                    cleanup_errors=[], cancelled=False, interrupted=False, exception=None, termination=None)

    def persist(self, process):
        r.write_json(Path(process["log"] + ".process.json"), process)

    def prepare(self):
        return d.prepare(self.project, self.qa, self.report, self.log, self.profile)

    def success_log(self):
        raw = (self.fixture / "stdout.txt").read_text(encoding="utf-8")
        value = r.assertion_json(next(line[10:] for line in raw.splitlines() if line.startswith("RENDER_V2 ")))
        value.update(status="PASS", passed=195, failed=[])
        value["metrics"]["live"]["events"] += ["TANK_DESTROYED", "OVERDRIVE"]
        value["metrics"]["live"]["states"] += ["charge", "missileBarrage", "overdrive"]
        return (raw.splitlines()[0] + "\n\nRENDER_V2 " + json.dumps(value) + "\n").encode()

    def fixture_run(self, success=False):
        context = self.prepare()
        self.log.write_bytes(self.success_log() if success else (self.fixture / "stdout.txt").read_bytes())
        process = self.process(success=success)
        self.persist(process)
        d.capture(context, process, r.assertion_json)
        return process

    def proof(self, process):
        return d.completed_failure(process, self.report, self.project, self.qa, self.profile, r.assertion_json)

    def reject(self, process):
        with self.assertRaises((RuntimeError, ValueError, OSError, KeyError, TypeError)):
            self.proof(process)

    def test_complete_native_stdout_and_fake_lifecycle_remains_fail(self):
        process = self.fixture_run()
        proof = self.proof(process)
        self.assertEqual((proof["acceptance_status"], proof["passed"], proof["failed"], proof["assertion_count"]),
                         ("FAIL", 190, list(d.FAILURES), 195))
        self.assertEqual(proof["capture_kind"], "native_stdout_json")
        self.assertEqual(proof["cause"], "NOT_DETERMINED_BY_PAYLOAD")
        self.assertFalse(self.profile.exists())
        self.assertFalse((self.qa / "reports/render_v2.json").exists())

    def test_timeout_crash_cancel_cleanup_and_incomplete_lifecycle_rejected(self):
        for key, value in (("timeout", True), ("code", -1), ("code", 0), ("code", True), ("pid", 0),
                           ("cancelled", True), ("interrupted", True), ("exception", "error"),
                           ("termination", {}), ("cleanup_errors", ["failed"]), ("seconds", float("inf"))):
            with self.subTest(key=key, value=value):
                process = self.fixture_run()
                process[key] = value
                self.persist(process)
                self.reject(process)
        process = self.fixture_run()
        del process["exception"]
        self.reject(process)

    def test_wrong_command_engine_qa_options_and_profiles_rejected(self):
        for index, value in ((0, "py"), (1, "--editor"), (3, str(self.project)), (5, "res://tests/other.gd")):
            with self.subTest(index=index):
                process = self.fixture_run()
                process["command"][index] = value
                self.persist(process)
                self.reject(process)
        for key in ("appdata", "localappdata"):
            process = self.fixture_run(); process[key] = str(self.base / "WRONG_PROFILE_NEVER_READ")
            self.persist(process); self.reject(process)
        process = self.fixture_run(); process["command"] += ["--", "--report=ignored.json"]
        self.persist(process); self.reject(process)

    def test_persisted_process_and_raw_capture_tamper_rejected(self):
        process = self.fixture_run()
        saved = r.assertion_json(Path(process["log"] + ".process.json").read_text(encoding="utf-8"))
        saved["pid"] += 1; r.write_json(Path(process["log"] + ".process.json"), saved)
        self.reject(process)
        for path in (self.log, self.report, self.report.with_suffix(".capture.json")):
            process = self.fixture_run(); path.write_bytes(path.read_bytes() + b" ")
            if path == self.report.with_suffix(".capture.json"):
                data = r.assertion_json(path.read_text(encoding="utf-8")); data["fixture_before"] = {}; r.write_json(path, data)
            self.reject(process)

    def test_changed_fixture_before_and_during_run_rejected(self):
        source = self.qa / "tests/render_v2.gd"
        original = source.read_bytes()
        source.write_bytes(original + b"\n")
        with self.assertRaisesRegex(RuntimeError, "fixture changed"): self.prepare()
        source.write_bytes(original)
        context = self.prepare()
        self.log.write_bytes((self.fixture / "stdout.txt").read_bytes())
        process = self.process(); self.persist(process)
        source.write_bytes(original + b"\n")
        with self.assertRaisesRegex(RuntimeError, "fixture changed"): d.capture(context, process, r.assertion_json)

    def test_clear_prevents_reusing_old_stdout_and_derived_json(self):
        self.fixture_run()
        context = self.prepare()
        self.assertEqual(self.log.read_bytes(), b"")
        self.assertEqual(self.report.read_bytes(), b"")
        process = self.process(); self.persist(process)
        with self.assertRaisesRegex(RuntimeError, "exactly one"): d.capture(context, process, r.assertion_json)

    def test_proof_survives_later_qa_copy_using_frozen_bytes(self):
        process = self.fixture_run()
        before = self.proof(process)
        (self.qa / "tests/render_v2.gd").write_bytes(b"later QA reuse; not the tested source")
        self.assertEqual(self.proof(process), before)

    def test_real_pass_has_no_continued_failure_and_failure_is_not_a_pass(self):
        process = self.fixture_run(success=True)
        data = d.completed_pass(process, self.report, self.project, self.qa, self.profile, r.assertion_json)
        self.assertEqual((data["status"], data["passed"], data["failed"]), ("PASS", 195, []))
        self.reject(process)
        process = self.fixture_run()
        with self.assertRaises(RuntimeError):
            d.completed_pass(process, self.report, self.project, self.qa, self.profile, r.assertion_json)

    def test_policy_final_install_rejected_before_any_initializer_or_io(self):
        self.assertFalse(d.policy(SimpleNamespace(final=False, dry_run=True))["enabled"])
        with patch.object(r, "Release") as ctor, patch.object(r, "ensure_helper") as install:
            for mode in ("--final", "--install-helper"):
                with self.subTest(mode=mode), self.assertRaises(RuntimeError):
                    r.main([mode, "--continue-on-known-render-failure"])
            ctor.assert_not_called(); install.assert_not_called()
        with patch.object(r, "git") as git:
            with self.assertRaises(RuntimeError):
                r.Release(SimpleNamespace(final=True, dry_run=False, continue_on_known_render_failure=True))
            git.assert_not_called()

    def test_resume_policy_change_rejected_before_profile_inventory(self):
        pg = self.project / "project.godot"; pg.write_text("fake project", encoding="utf-8")
        options = SimpleNamespace(final=False, dry_run=True, out=self.base / "scratch/out", run_id="fake_resume", with_telemetry=False,
                                  baseline_summary=None, resume_final=False, continue_on_test_failure=False, continue_on_known_render_failure=False)
        def fake_git(_project, *args): return "" if args[0] == "status" else "fakehead"
        with patch.object(config, "PROJECT", self.project), patch.object(config, "RELEASE", self.base / "final"), \
             patch.object(r, "git", side_effect=fake_git), patch.object(r, "runtime_hashes", return_value={}), patch.object(r, "verification_hashes", return_value={}), \
             patch.object(r, "source_paths", return_value=[(pg, "project.godot")]), patch.object(r.Release, "binary_hashes", return_value={}), \
             patch.object(r.Release, "tool_hashes", return_value={}), patch.object(r, "legacy_inventory", return_value={}), \
             patch.dict(os.environ, {"APPDATA": str(self.base / "FAKE_PROFILE_NEVER_READ")}):
            with patch.object(r, "profile_inventory", return_value={}): first = r.Release(options)
            self.assertFalse(first.identity["known_render_failure_policy"]["enabled"])
            options.continue_on_known_render_failure = True
            with patch.object(r, "profile_inventory", side_effect=AssertionError("Must stop before profile access")):
                with self.assertRaisesRegex(RuntimeError, "Resume input changed"): r.Release(options)
            options.continue_on_known_render_failure = False
            for field in ("SOURCE_SHA", "POLICY"):
                with patch.object(d, field, "different"), patch.object(r, "profile_inventory", side_effect=AssertionError("Must stop before profile access")):
                    with self.assertRaisesRegex(RuntimeError, "Resume input changed"): r.Release(options)

    def map_fixture(self, report, log, command):
        failures = ["ruined_gate all radii and gate states: [closed courtyard]", "ruined_gate/r28 all radii and gate states: [closed courtyard]"]
        value = dict(suite=r.CONTINUABLE_SUITE, status="FAIL", passed=33, failed=failures, step=8.0, radii=[14,16,18,20,22,24],
                     maps=[dict(sample=name, seconds=.25, issues=["closed courtyard"] if name in ("ruined_gate", "ruined_gate/r28") else [])
                           for name in sorted(r.CONNECTIVITY_SAMPLES)], historical_thorn=["historical corner proof"])
        lines = [f"MAP_CONNECTIVITY_V2 sample={row['sample']} seconds=0.25 problems={len(row['issues'])}" for row in value["maps"]]
        lines += ["ERROR: MAP_CONNECTIVITY_V2 " + label for label in failures] + ["MAP_CONNECTIVITY_V2 FAIL passed=33 failed=2"]
        log.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
        r.write_json(report, value)
        process = self.process(log, command); process["suite"] = r.CONTINUABLE_SUITE
        self.persist(process)
        return process

    def run_s2(self, enabled=True, map_enabled=False, map_failure=False, other=None, success=False, fresh=True, missing=False):
        obj = object.__new__(r.Release)
        obj.options = SimpleNamespace(final=False, dry_run=True, continue_on_test_failure=map_enabled,
                                      continue_on_known_render_failure=enabled, jobs=1, with_telemetry=True, baseline_summary=None)
        obj.test_failure_policy = r.test_failure_policy(obj.options)
        obj.project, obj.reports, obj.logs, obj.out, obj.profiles = self.project, self.reports, self.logs, self.base / "out", self.profiles
        obj.out.mkdir(exist_ok=True)
        obj.state_path = self.reports / "run_state.json"
        obj.source = dict(head="fake", input_sha256="f" * 64)
        obj.identity = dict(known_render_failure_policy=obj.known_render_failure_policy)
        obj.state, obj.unchanged = dict(stages={}, complete=False), lambda: None
        def godot(args, name, check=False):
            suite = name.removeprefix("headless_")
            command, log = [str(config.GODOT), *map(str,args)], obj.logs / (name + ".log")
            if suite == d.SUITE:
                self.assertNotIn("--", command)
                if enabled:
                    self.assertEqual(log.read_bytes(), b"")
                    self.assertEqual(self.report.read_bytes(), b"")
                if fresh: log.write_bytes(self.success_log() if success else (self.fixture / "stdout.txt").read_bytes())
                process = self.process(log, command, success=success)
            elif suite == r.CONTINUABLE_SUITE:
                path = Path(next(arg[9:] for arg in command if arg.startswith("--report=")))
                return self.map_fixture(path, log, command)
            else:
                log.write_text("ERROR: unexpected fixture failure\n", encoding="utf-8")
                process = self.process(log, command); process["suite"] = suite
            self.persist(process)
            return process
        obj.godot = godot
        suites = [] if missing else [d.SUITE]
        if map_failure: suites.append(r.CONTINUABLE_SUITE)
        if other: suites.append(other)
        with patch.object(r, "copy_project", return_value={}), patch.object(r, "import_project", return_value=[]), \
             patch.object(r, "REQUIRED_HEADLESS", set()), patch.object(r, "discover_tests", return_value=dict(headless=suites)):
            result = obj.S2()
        return obj, result

    def test_default_and_map_only_cannot_continue_render_failure(self):
        for map_enabled in (False, True):
            _, result = self.run_s2(enabled=False, map_enabled=map_enabled)
            self.assertEqual(result["status"], "FAIL")
            self.assertEqual(result["continued_test_failures"], [])
            self.assertNotIn("assertion_report", result["tests"][0])

    def test_s2_preserves_native_fail_and_all_evidence_hashes(self):
        obj, result = self.run_s2()
        self.assertEqual((result["status"], result["acceptance_status"], result["release_eligible"]), ("WARN", "FAIL", False))
        test = result["tests"][0]
        self.assertEqual(test["status"], "FAIL")
        obj.stage("S2", lambda: result)
        for path in (test["log"], test["log"] + ".process.json", test["assertion_report"], test["assertion_capture"]):
            self.assertIn(path, obj.state["stages"]["S2"]["output_hashes"])
        proof = result["continued_test_failures"][0]
        self.assertEqual(proof["metrics"]["live"]["ticks"], 1861)

    def test_both_flags_required_when_map_and_render_fail(self):
        for enabled, map_enabled, expected in ((False,False,"FAIL"),(False,True,"FAIL"),(True,False,"FAIL"),(True,True,"WARN")):
            _, result = self.run_s2(enabled=enabled, map_enabled=map_enabled, map_failure=True)
            self.assertEqual(result["status"], expected)
            if expected == "WARN": self.assertEqual({row["suite"] for row in result["continued_test_failures"]}, {d.SUITE,r.CONTINUABLE_SUITE})

    def test_unknown_draft_preview_failures_or_stale_stdout_still_stop(self):
        for other in ("environment_153", "draft_14", "preview_ui_14"):
            _, result = self.run_s2(other=other)
            self.assertEqual((result["status"], result["continued_test_failures"]), ("FAIL", []))
        _, result = self.run_s2(fresh=False)
        self.assertEqual(result["status"], "FAIL")
        self.assertIn("assertion_evidence_error", result["tests"][0])

    def test_enabled_flag_requires_discovered_fixture_and_pass_stays_pass(self):
        with self.assertRaisesRegex(RuntimeError, "requires the render_v2 fixture"): self.run_s2(missing=True)
        _, result = self.run_s2(success=True)
        self.assertEqual((result["status"], result["acceptance_status"], result["continued_test_failures"]), ("PASS", "PASS", []))

    def test_render_flag_does_not_enable_s3_preview_continuation(self):
        obj = object.__new__(r.Release)
        obj.project = self.project
        obj.options = SimpleNamespace(final=False, dry_run=True, continue_on_known_render_failure=True)
        calls = []
        def helper(mode, name, extra, **kwargs):
            calls.append((mode, name, extra, kwargs))
            raise RuntimeError("ordinary UI failure still stops")
        obj.helper = helper
        with patch.object(r, "discover_tests", return_value=dict(rendered=["preview_ui_14"])), \
             patch.object(r, "REQUIRED_RENDERED", {"preview_ui_14"}):
            with self.assertRaisesRegex(RuntimeError, "ordinary UI failure still stops"): obj.S3()
        self.assertEqual(calls, [("uitest", "rendered_preview_ui_14", ["-Suite", "preview_ui_14"], {})])

    def test_execution_complete_is_acceptance_fail_exit_two_and_not_release(self):
        obj, result = self.run_s2()
        for index in range(12):
            stage = dict(status="PASS")
            if index == 0: stage.update(known_render_failure_policy=obj.known_render_failure_policy)
            if index == 2: stage = result
            if index == 10: r.write_json(obj.out / "release_manifest_v2.json", dict(synthetic=True))
            setattr(obj, f"S{index}", lambda value=stage: copy.deepcopy(value))
        self.assertEqual(obj.execute(), 2)
        completion = r.assertion_json((obj.out / "release_completion_v2.json").read_text(encoding="utf-8"))
        self.assertEqual((completion["complete"],completion["execution_complete"],completion["acceptance_status"],completion["release_eligible"],completion["exit_code"]), (True,True,"FAIL",False,2))
        for data in (completion, obj.state, r.assertion_json((obj.out / "post_package_validation.json").read_text(encoding="utf-8"))):
            self.assertEqual(data["known_render_failure_policy"], obj.known_render_failure_policy)
        text = (obj.out / "POST_PACKAGE_VALIDATION_2.0_KO.txt").read_text(encoding="utf-8")
        self.assertIn("FAIL | render_v2/C8 HOLD", text)
        self.assertIn("render_v2 | FAIL | 1", text)
        self.assertIn("native stdout JSON에서 추출한 파생 증거", text)
        for label in d.FAILURES: self.assertIn("FAIL: " + label, text)
        self.assertIn(d.SOURCE_SHA, text)

    def test_infrastructure_failure_is_not_completed_and_main_propagates_two(self):
        obj, _ = self.run_s2()
        with self.assertRaisesRegex(RuntimeError, "infrastructure blocked"):
            obj.stage("S2", lambda: (_ for _ in ()).throw(RuntimeError("infrastructure blocked")))
        self.assertFalse(obj.state["complete"])
        self.assertFalse(obj.state["release_eligible"])
        with patch.object(r, "Release", return_value=SimpleNamespace(execute=lambda:2)):
            self.assertEqual(r.main(["--dry-run", "--continue-on-known-render-failure", "--out", str(self.base / "out")]), 2)


if __name__ == "__main__":
    unittest.main(verbosity=2)
