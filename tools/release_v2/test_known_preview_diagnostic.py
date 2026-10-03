"""Standalone preview diagnostic orchestration checks; no engine/profile/Git use.

Producer report/stdout bytes are bundled. All process IDs, launcher receipts and
isolated paths below are synthetic and never represent a real engine run.
"""
import copy
import json
from pathlib import Path
import re
import shutil
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
import preview_diagnostic as p
import validation


class KnownPreview(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="fake-preview-", dir=HERE)
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.project = self.base / "project"
        self.fixture = HERE / "test_fixtures/preview_14_known_v1"
        self.addCleanup(patch.stopall)
        patch.object(config, "QA", self.base / "qa_root/release_v2/project").start()
        patch.object(config, "SCRATCH", self.base / "scratch").start()
        patch.object(config, "GODOT", self.base / "FAKE_ENGINE_NEVER_EXECUTED.exe").start()
        for project in (self.project, Path(p.locations(self.project)["qa"])):
            (project / "tests").mkdir(parents=True)
            for suffix in ("gd", "tscn"):
                (project / ("tests/preview_ui_14." + suffix)).write_bytes((self.fixture / ("preview_ui_14." + suffix + ".txt")).read_bytes())
        self.frozen = self.base / "reports/helper_evidence/rendered_preview_ui_14"
        self.capture_path = self.frozen / "preview_capture.json"

    def save(self, path, value):
        r.write_json(path, value)

    def fake_run(self):
        context = p.prepare(self.project, self.capture_path)
        origin = Path(context["origin"])
        for stem, code, args in (
            ("uitest_preview_ui_14", 1, ["--path", context["qa"], "--resolution", "1600x900", "res://tests/preview_ui_14.tscn", "--", "--ui-report=" + (origin / "preview_ui_14.json").as_posix()]),
            ("import_qa_attempt1", 0, ["--headless", "--path", context["qa"], "--editor", "--quit"]),
        ):
            log = origin / (stem + ".log")
            request = dict(executable=str(config.GODOT), args=args, log=str(log), summary=str(log) + ".process.json", timeout=900,
                           appdata=str(Path(context["profile_root"]) / stem / "Roaming"), localappdata=str(Path(context["profile_root"]) / stem / "Local"))
            self.save(Path(str(log) + ".request.json"), request)
            self.save(Path(str(log) + ".process.json"), dict(code=code, pid=123456, timed_out=False, appdata=request["appdata"], localappdata=request["localappdata"],
                      timeout_seconds=900, log=str(log), cleanup_errors=[], termination=None, interrupted=False, seconds=.5))
            log.write_bytes((self.fixture / "stdout.txt").read_bytes() if code else ("Godot Engine v" + config.ENGINE_VERSION + ".FAKE_IMPORT\n[ DONE ] fake import receipt\n").encode())
        (origin / "preview_ui_14.json").write_bytes((self.fixture / "report.json").read_bytes())
        self.frozen.mkdir(parents=True, exist_ok=True)
        for name in p.ARTIFACTS:
            shutil.copyfile(origin / name, self.frozen / name)
        p.capture(context, self.frozen, {key:dict(sha256=value) for key,value in p.TEMPLATES.items()})
        lines = (origin / "uitest_preview_ui_14.log").read_text(encoding="utf-8").splitlines()
        matching = [line for line in lines if re.search(r"FAIL|PASS|passed|failed", line, re.I)][-40:]
        problems = [line for line in lines if re.search(r"SCRIPT ERROR|^ERROR:|Parse Error|^\s+at: |WARNING: .*\.gd", line, re.I)]
        outer = self.base / "logs/rendered_preview_ui_14.log"
        outer.parent.mkdir(parents=True, exist_ok=True)
        outer.write_text("\n".join(["  " + line for line in matching + problems] + [f"UITEST preview_ui_14 exit=1 problems={len(problems)} log={origin / 'uitest_preview_ui_14.log'} report={(origin / 'preview_ui_14.json').as_posix()}"]) + "\n", encoding="utf-8", newline="\n")
        process = dict(status="FAIL", code=1, pid=234567, seconds=.7, timeout=False, cleanup_errors=[], cancelled=False, interrupted=False, exception=None, termination=None,
                       command=["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(self.project / "zz_work/tools/gd.ps1"), "-PythonExe", sys.executable, "-Mode", "uitest", "-Root", str(self.project), "-Suite", "preview_ui_14"],
                       log=str(outer), problems=[], suite="preview_ui_14", preview_capture=str(self.capture_path), helper_evidence_dir=str(self.frozen))
        self.persist(process)
        return process

    def persist(self, process):
        self.save(Path(process["log"] + ".process.json"), process)

    def refresh(self, name):
        context = json.loads(self.capture_path.read_text(encoding="utf-8"))
        path = self.frozen / name
        context["captured"][name] = dict(bytes=path.stat().st_size, sha256=r.sha(path))
        self.save(self.capture_path, context)

    def reject(self, process):
        with self.assertRaises((RuntimeError, ValueError, OSError, KeyError, TypeError)):
            p.completed_failure(process, self.project, r.assertion_json)

    def test_complete_actual_payload_with_synthetic_process_chain_remains_fail(self):
        process = self.fake_run()
        proof = p.completed_failure(process, self.project, r.assertion_json)
        self.assertEqual(proof["acceptance_status"], "FAIL")
        self.assertEqual(proof["passed"], 105)
        self.assertEqual(proof["failed"], [p.FAILURE])
        self.assertEqual(proof["infrastructure_error_count"], 0)
        self.assertEqual(len(proof["evidence_files"]), 13)
        self.assertFalse(Path(p.locations(self.project)["profile_root"]).exists())

    def test_policy_default_dry_only_and_final_rejected_before_io(self):
        options = SimpleNamespace(final=False, dry_run=True)
        self.assertFalse(p.policy(options)["enabled"])
        options.continue_on_known_preview_failure = True
        self.assertTrue(p.policy(options)["enabled"])
        options.final = True
        with self.assertRaises(RuntimeError):p.policy(options)
        with patch.object(r, "Release") as ctor, patch.object(r, "ensure_helper") as install:
            for mode in ("--final", "--install-helper"):
                with self.subTest(mode=mode), self.assertRaises(RuntimeError):
                    r.main([mode, "--continue-on-known-preview-failure"])
            ctor.assert_not_called(); install.assert_not_called()

    def test_outer_bad_lifecycle_or_persisted_disagreement_rejected(self):
        process = self.fake_run()
        for mutation in ({"code":0},{"code":124},{"code":True},{"pid":None},{"status":"PASS"},{"timeout":True},{"cleanup_errors":["tree failure"]},{"cancelled":True},{"interrupted":True},{"exception":"failure"},{"termination":{}},{"suite":"other"}):
            with self.subTest(mutation=mutation):
                changed = dict(process, **mutation); self.persist(changed); self.reject(changed)
        self.persist(dict(process, code=0)); self.reject(process)

    def test_inner_bad_lifecycle_launch_profile_and_timeout_rejected(self):
        process = self.fake_run()
        for name in ("uitest_preview_ui_14", "import_qa_attempt1"):
            receipt = self.frozen / (name + ".log.process.json")
            original = json.loads(receipt.read_text(encoding="utf-8"))
            for mutation in ({"code":124},{"timed_out":True},{"pid":None},{"cleanup_errors":["failed"]},{"termination":{}},{"interrupted":True},{"seconds":901},{"timeout_seconds":899},{"appdata":"actual-profile-forbidden"},{"exception":"unexpected"}):
                with self.subTest(name=name, mutation=mutation):
                    self.save(receipt, dict(original, **mutation)); self.refresh(receipt.name); self.reject(process)
            self.save(receipt, original); self.refresh(receipt.name)
            request = self.frozen / (name + ".log.request.json")
            original = json.loads(request.read_text(encoding="utf-8"))
            for mutation in ({"args":[]},{"executable":"different"},{"timeout":True},{"localappdata":"wrong"}):
                self.save(request, dict(original, **mutation)); self.refresh(request.name); self.reject(process)
            self.save(request, original); self.refresh(request.name)
        p.completed_failure(process, self.project, r.assertion_json)

    def test_missing_stale_changed_source_template_or_clear_evidence_rejected(self):
        process = self.fake_run()
        original = json.loads(self.capture_path.read_text(encoding="utf-8"))
        for key, value in (("status","CLEARED"),("source_before",{}),("source_after",{}),("qa_sources",{}),("helper_templates",{}),("cleared",{}),("captured",{}),("qa","other")):
            self.save(self.capture_path, dict(original, **{key:value})); self.reject(process)
        self.save(self.capture_path, original)
        path = self.frozen / "preview_ui_14.json"
        saved = path.read_bytes(); path.write_bytes(b""); self.reject(process)
        path.write_bytes(saved); path.unlink(); self.reject(process)

    def test_import_retry_error_warning_and_empty_receipt_rejected(self):
        process = self.fake_run()
        log = self.frozen / "import_qa_attempt1.log"
        original = log.read_bytes()
        for text in (b"", original+b"WARNING: renderer\n", original+b"ERROR: parse\n", original+b"FAIL import\n"):
            log.write_bytes(text); self.refresh(log.name); self.reject(process)
        log.write_bytes(original); self.refresh(log.name)
        retry = self.frozen / "import_qa_attempt2.log"
        retry.write_bytes(b"retry evidence"); self.refresh(retry.name); self.reject(process)

    def test_extra_outer_output_or_wrong_helper_command_rejected(self):
        process = self.fake_run()
        changed = dict(process, command=process["command"]+["-NoSync"])
        self.persist(changed); self.reject(changed)
        self.persist(process)
        outer = Path(process["log"])
        with outer.open("a",encoding="utf-8") as stream:stream.write("WARNING: unexpected helper warning\n")
        self.reject(process)

    def test_changed_payload_rejected_even_after_capture_sha_matches(self):
        process = self.fake_run()
        path = self.frozen / "preview_ui_14.json"
        original = json.loads(path.read_text(encoding="utf-8"))
        for mutation in ({"passed":106},{"failed":0},{"checks":[]},{"measurements":{}}):
            self.save(path, dict(original, **mutation)); self.refresh(path.name); self.reject(process)

    def test_preview_only_acceptance_fail_exit_and_report_holds(self):
        proof = p.completed_failure(self.fake_run(), self.project, r.assertion_json)
        stages = {"S"+str(i):dict(status="PASS") for i in range(12)}
        stages["S3"] = dict(status="WARN",acceptance_status="FAIL",continued_ui_test_failures=[proof],tests=[])
        result = r.acceptance_summary(stages)
        self.assertEqual(result["acceptance_status"],"FAIL")
        self.assertFalse(result["release_eligible"])
        self.assertEqual(result["continued_test_failures"],[proof])
        document = self.base / "VALIDATION.txt"
        validation.write_validation(document,stages,True,dict(head="fake",input_sha256="fake"))
        text = document.read_text(encoding="utf-8")
        self.assertIn("C7/C8 HOLD",text)
        self.assertIn("수락 판정: FAIL",text)
        self.assertIn(p.FAILURE,text)

    def run_s3(self, enabled=True, unknown_failure=False):
        process = self.fake_run()
        process["output_hashes"] = r.file_evidence([self.capture_path, *[self.frozen / name for name in p.ARTIFACTS]])
        obj = object.__new__(r.Release)
        obj.project, obj.reports, obj.logs, obj.out = self.project, self.base / "reports", self.base / "logs", self.base / "out"
        obj.out.mkdir(exist_ok=True)
        obj.options = SimpleNamespace(final=False,dry_run=True,continue_on_known_preview_failure=enabled,continue_on_known_draft_failure=True,continue_on_test_failure=True)
        obj.test_failure_policy = r.test_failure_policy(obj.options)
        obj.source = dict(head="fake",input_sha256="f"*64)
        obj.identity = dict(known_preview_failure_policy=obj.known_preview_failure_policy)
        obj.state, obj.state_path = dict(stages={}), obj.reports / "run_state.json"
        obj.unchanged = lambda:None
        calls = []
        def helper(mode,name,extra,**kwargs):
            calls.append((mode,kwargs))
            if mode == "shots":return dict(status="PASS",output_hashes={})
            if unknown_failure:raise RuntimeError("unrelated UI failure must stop")
            if not kwargs.get("known_preview"):raise RuntimeError("default helper rejects exit 1")
            return copy.deepcopy(process)
        obj.helper = helper
        with patch.object(r,"discover_tests",return_value={"rendered":[p.SUITE]}), patch.object(r,"REQUIRED_RENDERED",{p.SUITE}), patch.object(r,"SCREENSHOTS",()):
            result = obj.S3()
        return obj,result,calls

    def test_s3_requires_preview_flag_even_when_other_flags_enabled(self):
        with self.assertRaisesRegex(RuntimeError,"default helper rejects exit 1"):self.run_s3(enabled=False)

    def test_s3_keeps_fail_counts_and_all_evidence_while_other_errors_stop(self):
        obj,result,calls = self.run_s3()
        self.assertEqual((result["status"],result["acceptance_status"],result["release_eligible"]),("WARN","FAIL",False))
        self.assertEqual(calls,[("uitest",{"known_preview":True}),("shots",{})])
        self.assertEqual(result["tests"][0]["status"],"FAIL")
        self.assertEqual(result["tests"][0]["assertions"]["failed"],1)
        obj.stage("S3",lambda:result)
        for path in (str(self.capture_path),result["tests"][0]["log"],result["tests"][0]["log"]+".process.json"):
            self.assertIn(path,obj.state["stages"]["S3"]["output_hashes"])
        with self.assertRaisesRegex(RuntimeError,"unrelated UI failure"):self.run_s3(unknown_failure=True)

    def test_complete_preview_diagnostic_returns_two_and_never_release_eligible(self):
        obj,result,_ = self.run_s3()
        for index in range(12):
            stage = dict(status="PASS")
            if index == 0:stage.update(known_preview_failure_policy=obj.known_preview_failure_policy)
            if index == 3:stage = result
            if index == 10:r.write_json(obj.out / "release_manifest_v2.json",{"fixture":True})
            setattr(obj,"S"+str(index),lambda value=stage:copy.deepcopy(value))
        self.assertEqual(obj.execute(),2)
        completion = json.loads((obj.out / "release_completion_v2.json").read_text(encoding="utf-8"))
        self.assertEqual((completion["complete"],completion["execution_complete"],completion["acceptance_status"],completion["release_eligible"],completion["exit_code"]),(True,True,"FAIL",False,2))
        self.assertEqual(completion["known_preview_failure_policy"],obj.known_preview_failure_policy)
        text = (obj.out / "POST_PACKAGE_VALIDATION_2.0_KO.txt").read_text(encoding="utf-8")
        self.assertIn("preview_ui_14 | FAIL | 1 | 105/1",text)
        self.assertIn("C7/C8 HOLD",text)


if __name__ == "__main__":unittest.main()
