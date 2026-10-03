"""Synthetic filesystem/process regression tests. These are not game evidence."""
import copy
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

import calib_cases
import common
import run_calibration
import runtime_contracts as contracts
import sim_sha
from test_pipeline import roster, results


class RuntimeContracts(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=Path(__file__).parent)
        self.folder = Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def receipt(self, *, bad_process=False):
        cases = calib_cases.generate(roster())[:2]
        label = "chunk"
        common.write_json(self.folder / "cases/chunk.json", cases)
        output = self.folder / "results/chunk.jsonl"
        output.parent.mkdir()
        output.write_text("".join(json.dumps(row) + "\n" for row in results(cases).values()), encoding="utf-8", newline="\n")
        log = self.folder / "logs/chunk.log"
        log.parent.mkdir()
        log.write_text("synthetic log\n", encoding="utf-8", newline="\n")
        common.write_json(self.folder / "logs/chunk.process.json", {"status": "FAIL" if bad_process else "PASS",
                          "exit_code": 1 if bad_process else 0, "timeout": False, "errors": []})
        contracts.save_receipt(self.folder, label, cases, "identity")
        return cases, output

    def test_only_receipted_results_resume(self):
        cases, output = self.receipt()
        self.assertEqual(contracts.verified_result_paths(self.folder, cases, "identity"), [output])
        (output.parent / "interrupted.jsonl").write_text('{"partial', encoding="utf-8")
        self.assertEqual(contracts.verified_result_paths(self.folder, cases, "identity"), [output])
        (self.folder / "receipts/chunk.json").unlink()
        self.assertEqual(contracts.verified_result_paths(self.folder, cases, "identity"), [])

    def test_receipt_requires_matching_identity_and_bytes(self):
        cases, output = self.receipt()
        with self.assertRaisesRegex(RuntimeError, "another run"):
            contracts.verified_result_paths(self.folder, cases, "other")
        output.write_text("\n", encoding="utf-8")
        with self.assertRaisesRegex(RuntimeError, "evidence differs"):
            contracts.verified_result_paths(self.folder, cases, "identity")

    def test_receipt_rejects_failed_process_even_with_valid_hash(self):
        cases, _ = self.receipt(bad_process=True)
        with self.assertRaisesRegex(RuntimeError, "successful process"):
            contracts.verified_result_paths(self.folder, cases, "identity")

    def test_receipt_rejects_path_escape(self):
        cases, _ = self.receipt()
        path = self.folder / "receipts/chunk.json"
        record = common.read_json(path)
        record["files"]["result"]["path"] = "../elsewhere.jsonl"
        common.write_json(path, record)
        with self.assertRaisesRegex(RuntimeError, "evidence differs"):
            contracts.verified_result_paths(self.folder, cases, "identity")

    def test_resume_reuses_only_success_and_preserves_failed_attempt(self):
        cases = calib_cases.generate(roster())[:3]
        args = SimpleNamespace(root=self.folder, out=self.folder, jobs=2, chunk_size=1, timeout=900, godot=self.folder / "fake.exe")
        runner = run_calibration.Runner(args, {"sim_sha": "s"}, {"binaries": {}})
        launched = []

        def fake_run(godot, root, arguments, log, timeout):
            self.assertEqual(timeout, 900)
            request = Path(next(arg.split("=", 1)[1] for arg in arguments if arg.startswith("--cases=")))
            output = Path(next(arg.split("=", 1)[1] for arg in arguments if arg.startswith("--output=")))
            selected = common.read_json(request)
            launched.extend(case["id"] for case in selected)
            output.write_text("".join(json.dumps(row) + "\n" for row in results(selected).values()), encoding="utf-8", newline="\n")
            log.parent.mkdir(parents=True, exist_ok=True)
            log.write_text("synthetic\n", encoding="utf-8", newline="\n")
            record = {"status": "PASS", "exit_code": 0, "timeout": False, "errors": [], "seconds": 0}
            common.write_json(log.with_suffix(".process.json"), record)
            return record

        batch = self.folder / "training"
        chunk = [cases[0]]
        stale = batch / "results" / ("shard_0_" + common.digest(chunk)[:20] + ".jsonl")
        stale.parent.mkdir(parents=True)
        stale.write_text('{"interrupted', encoding="utf-8")
        with patch.object(runner, "sources_unchanged"), patch.object(run_calibration, "run_godot", side_effect=fake_run):
            rows = runner.run_batch(cases, batch)
            self.assertEqual(set(rows), {case["id"] for case in cases})
            self.assertEqual(len(launched), 3)
            runner.run_batch(cases, batch)
            self.assertEqual(len(launched), 3)
        preserved = list((batch / "rejected").rglob("*.jsonl"))
        self.assertEqual(len(preserved), 1)
        self.assertEqual(preserved[0].read_text(), '{"interrupted')

    def test_batch_four_receipts_resume_and_cold_stays_one_case(self):
        cases = calib_cases.generate(roster())[:9]
        args = SimpleNamespace(root=self.folder, out=self.folder, jobs=2, chunk_size=4, timeout=900, godot=self.folder / "fake.exe")
        runner = run_calibration.Runner(args, {"sim_sha": "s"}, {"binaries": {}})
        launched = []

        def fake_run(godot, root, arguments, log, timeout):
            self.assertEqual(timeout, 900)
            request = Path(next(arg.split("=", 1)[1] for arg in arguments if arg.startswith("--cases=")))
            output = Path(next(arg.split("=", 1)[1] for arg in arguments if arg.startswith("--output=")))
            selected = common.read_json(request)
            launched.append(tuple(case["id"] for case in selected))
            self.assertEqual(len({case["index"] % args.jobs for case in selected}), 1)
            output.write_text("".join(json.dumps(row) + "\n" for row in results(selected).values()), encoding="utf-8", newline="\n")
            log.parent.mkdir(parents=True, exist_ok=True)
            log.write_text("synthetic batch process\n", encoding="utf-8", newline="\n")
            process = {"status": "PASS", "exit_code": 0, "timeout": False, "errors": [], "seconds": 0}
            common.write_json(log.with_suffix(".process.json"), process)
            return process

        with patch.object(runner, "sources_unchanged"), patch.object(run_calibration, "run_godot", side_effect=fake_run):
            training = runner.run_batch(cases, self.folder / "training")
            self.assertEqual(set(training), {case["id"] for case in cases})
            self.assertEqual(sorted(map(len, launched)), [1, 4, 4])
            before_resume = launched.copy()
            self.assertEqual(runner.run_batch(cases, self.folder / "training"), training)
            self.assertEqual(launched, before_resume)
            cold = runner.run_batch(cases, self.folder / "cold", cold=True)
            self.assertEqual(cold, training)
            self.assertEqual([len(group) for group in launched[len(before_resume):]], [1] * len(cases))
        receipts = [common.read_json(path) for path in (self.folder / "training/receipts").glob("*.json")]
        self.assertEqual(sorted(len(row["case_ids"]) for row in receipts), [1, 4, 4])
        self.assertEqual(len(list((self.folder / "cold/receipts").glob("*.json"))), 9)

    def first_picks(self):
        source = roster()
        source[0]["id"] = "werewolf"
        ids = calib_cases.roster_ids(source)
        reports = []
        for size in (1, 3):
            for seed in (1, 2, 3):
                for i, arena in enumerate(contracts.ARENAS):
                    reports.append({"status": "MEASURED", "scope": "single_pick", "roster": ids,
                                    "rows": [{"team_size": size, "seed": seed, "arena_id": arena,
                                              "id": ids[i], "score_basis": "search", "search": {}}]})
        return source, reports

    def test_first_pick_full_grid_and_thresholds(self):
        source, reports = self.first_picks()
        output = contracts.first_pick_report(reports, source)
        self.assertEqual(output["status"], "PASS")
        self.assertEqual((len(output["rows"]), len(output["groups"])), (90, 6))
        for report in reports[:4]:
            report["rows"][0]["id"] = "werewolf"
        output = contracts.first_pick_report(reports, source)
        self.assertEqual(output["groups"][0]["werewolf"], 4)
        self.assertEqual(output["status"], "FAIL")
        for report in reports[:6]:
            report["rows"][0]["id"] = "hero_01"
        self.assertEqual(contracts.first_pick_report(reports, source)["status"], "FAIL")

    def test_first_pick_rejects_missing_duplicate_stale_and_unknown(self):
        source, reports = self.first_picks()
        for altered in (reports[:-1], reports + [reports[0]]):
            with self.assertRaises(RuntimeError): contracts.first_pick_report(altered, source)
        for key, value in (("status", "PASS"), ("roster", ["unknown"])):
            bad = copy.deepcopy(reports)
            bad[0][key] = value
            with self.assertRaises(RuntimeError): contracts.first_pick_report(bad, source)
        bad = copy.deepcopy(reports)
        bad[0]["rows"][0]["id"] = "unknown"
        with self.assertRaises(RuntimeError): contracts.first_pick_report(bad, source)

    def test_first_pick_accepts_actual_producer_score_basis_strings(self):
        source, reports = self.first_picks()
        for basis in ("search", "search_and_engine"):
            with self.subTest(basis=basis):
                for report in reports:
                    report["rows"][0]["score_basis"] = basis
                output = contracts.first_pick_report(reports, source)
                self.assertEqual(output["status"], "PASS")
                self.assertEqual({row["score_basis"] for row in output["rows"]}, {basis})

    def test_first_pick_rejects_invalid_score_basis_and_search_evidence(self):
        source, reports = self.first_picks()
        for key, values in (("score_basis", ("unknown", "", {}, {"search": True}, None, [], 1)),
                            ("search", (None, [], "search", 1))):
            for value in values:
                with self.subTest(key=key, value=value):
                    bad = copy.deepcopy(reports)
                    bad[0]["rows"][0][key] = value
                    with self.assertRaisesRegex(RuntimeError, "Missing first-pick decision evidence"):
                        contracts.first_pick_report(bad, source)
            bad = copy.deepcopy(reports)
            del bad[0]["rows"][0][key]
            with self.assertRaisesRegex(RuntimeError, "Missing first-pick decision evidence"):
                contracts.first_pick_report(bad, source)

    def test_first_pick_format_smoke_cannot_satisfy_full_audit(self):
        source, reports = self.first_picks()
        for count in (1, 2):
            with self.subTest(count=count):
                with self.assertRaisesRegex(RuntimeError, f"^Incomplete first-pick audit: {count}/90$"):
                    contracts.first_pick_report(reports[:count], source)

    def test_binary_guard_uses_sha_when_metadata_changes(self):
        binary = self.folder / "fake.exe"
        binary.write_bytes(b"one")
        guard = contracts.BinaryGuard({"engine": {"path": str(binary), "sha256": common.sha(binary)}})
        guard.check()
        binary.write_bytes(b"different")
        with self.assertRaisesRegex(RuntimeError, "binary changed"):
            guard.check()

    def test_external_runner_and_fingerprint_are_identity_inputs(self):
        for relative in contracts.EXTERNAL_TOOLS:
            target = self.folder / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(relative, encoding="utf-8")
        before = contracts.tool_hashes(self.folder)
        (self.folder / contracts.EXTERNAL_TOOLS[0]).write_text("changed", encoding="utf-8")
        self.assertNotEqual(before, contracts.tool_hashes(self.folder))
        self.assertTrue(set(contracts.EXTERNAL_TOOLS) <= set(before))

    def test_tree_kill_timeout_falls_back_to_exact_pid(self):
        process = Mock(pid=123456)
        process.poll.return_value = None
        process.kill.side_effect = lambda: setattr(process.poll, 'return_value', 0)
        with patch.object(common.subprocess, "run", side_effect=subprocess.TimeoutExpired("taskkill", 20)) as kill:
            proof = common.terminate_pid_tree(process)
        if os.name == "nt":
            executable = Path(os.environ.get('SystemRoot', 'C:/Windows')) / 'System32/taskkill.exe'
            self.assertEqual(kill.call_args.args[0], [str(executable), "/PID", "123456", "/T", "/F"])
            self.assertTrue(proof['errors'])
        process.kill.assert_called_once()
        process.wait.assert_called_once_with(timeout=20)

    def test_headless_runner_redirects_profiles_and_writes_failure_evidence(self):
        process = Mock(pid=123456, returncode=1)
        def fake_launch(command, **kwargs):
            self.assertIn("--headless", command)
            self.assertEqual(kwargs["cwd"], self.folder.resolve())
            for variable in ("APPDATA", "LOCALAPPDATA"):
                self.assertIn(str(self.folder), kwargs["env"][variable])
            kwargs["stdout"].write(b"ERROR: synthetic failure\n")
            return process
        log = self.folder / "run.log"
        with patch.object(common.subprocess, "Popen", side_effect=fake_launch):
            with self.assertRaisesRegex(RuntimeError, "Godot failed"):
                common.run_godot(self.folder / "fake.exe", self.folder, [], log)
        evidence = common.read_json(log.with_suffix(".process.json"))
        self.assertEqual(evidence["status"], "FAIL")
        self.assertEqual(evidence["errors"], ["ERROR: synthetic failure"])

    def test_fingerprint_requires_matching_fresh_canonical_output(self):
        def fake_run(godot, root, arguments, log, timeout):
            output = Path(next(arg.split("=", 1)[1] for arg in arguments if arg.startswith("--out=")))
            output.write_bytes(b'{}')
            record = {"sha256": common.sha(output), "bytes": 2, "counts": {}, "project": str(root)}
            log.write_text(sim_sha.FINGERPRINT_PREFIX + json.dumps(record), encoding="utf-8")
        with patch.object(sim_sha, "run_godot", side_effect=fake_run):
            self.assertEqual(sim_sha.fingerprint(self.folder, "fake", self.folder / "fp")["bytes"], 2)
        with patch.object(sim_sha, "run_godot"):
            with self.assertRaisesRegex(RuntimeError, "Canonical data"):
                sim_sha.fingerprint(self.folder, "fake", self.folder / "fp")

    def test_teams_cover_all_maps_at_both_sizes(self):
        cases = calib_cases.generate(roster())
        for size in (3, 5):
            counts = {arena: 0 for arena in calib_cases.ELIMINATION}
            for case in cases:
                if case["kind"] == "team" and case["ruleset"] == "elimination" and len(case["blue"]) == size:
                    counts[case["arena_id"]] += 1
            self.assertLessEqual(max(counts.values()) - min(counts.values()), 1)
            self.assertGreater(min(counts.values()), 0)

    def test_roster_ids_reject_coercion_and_pair_separator(self):
        for value in (None, 12, "", "foo|bar"):
            invalid = roster()
            invalid[0]["id"] = value
            with self.assertRaisesRegex(RuntimeError, "Malformed roster"):
                calib_cases.roster_ids(invalid)

    def test_main_preserves_measured_table_and_hold_after_acceptance_failure(self):
        for relative in (*contracts.EXTERNAL_TOOLS, "scripts/core/fake.gd", "scripts/ai/fake.gd", "scripts/data/char_data.gd"):
            target = self.folder / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text("synthetic source", encoding="utf-8")
        target = self.folder / "scripts/data/draft_calibration.gd"
        target.write_text("previous synthetic table", encoding="utf-8")
        engine = self.folder / "fake.exe"
        engine.write_bytes(b"synthetic engine; never execute")
        output = self.folder / "zz_work/full"
        batches = []

        def stamp(project, godot, out, timeout):
            files = sim_sha.source_hashes(project)
            return {"sim_sha": "a" * 64, "sha256": "a" * 64, "data_fingerprint": "b" * 64,
                    "sources": files, "files": files, "platform": "windows"}

        def fake_godot(godot, root, arguments, log, timeout):
            log.parent.mkdir(parents=True, exist_ok=True)
            if arguments == ["--version"]:
                log.write_text("4.7.2.stable.synthetic", encoding="utf-8")
            elif any(arg.startswith("--roster=") for arg in arguments):
                destination = Path(next(arg.split("=", 1)[1] for arg in arguments if arg.startswith("--roster=")))
                common.write_json(destination, roster())
                log.write_text("ROSTER 22", encoding="utf-8")
            elif "res://tools/calibration_v2/calib_check.gd" in arguments:
                log.write_text('CALIB_CHECK {"status":"PASS","failed":[],"games":4572,"roster_count":22}', encoding="utf-8")
            else:
                self.fail("Unexpected fake invocation: " + str(arguments))

        class FakeRunner:
            def __init__(self, args, source_stamp, contract):
                self.binaries = SimpleNamespace(check=lambda **kwargs: None)
            def run_batch(self, cases, folder, *, cold=False):
                batches.append((folder.name, len(cases), cold))
                return results(cases)
            def sources_unchanged(self):
                pass
            def first_pick_audit(self, source_roster):
                return {"status": "FAIL", "groups": [{"status": "FAIL", "werewolf": 15}], "rows": []}

        argv = ["run_calibration.py", "--root", str(self.folder), "--godot", str(engine), "--out", str(output)]
        with patch.object(sys, "argv", argv), patch.object(run_calibration, "run_godot", side_effect=fake_godot), \
             patch.object(run_calibration.sim_sha, "compute", side_effect=stamp), patch.object(run_calibration, "Runner", FakeRunner):
            with self.assertRaises(SystemExit) as stop:
                run_calibration.main()
            original_state = (output / "run_state.json").read_bytes()
            original_preflight = {path: path.read_bytes() for path in (output / "preflight").rglob("*") if path.is_file()}
            self.assertEqual(common.read_json(output / "run_state.json")["contract"]["chunk_size"], 1)
            with patch.object(sys, "argv", argv + ["--chunk-size", "4"]):
                with self.assertRaisesRegex(RuntimeError, "Existing run belongs"):
                    run_calibration.main()
            self.assertEqual((output / "run_state.json").read_bytes(), original_state)
            engine.write_bytes(b"different synthetic engine; never execute")
            with self.assertRaisesRegex(RuntimeError, "Existing run belongs"):
                run_calibration.main()
            self.assertEqual((output / "run_state.json").read_bytes(), original_state)
            self.assertTrue(all(path.read_bytes() == content for path, content in original_preflight.items()))
            self.assertEqual(len(list((output / "preflight").iterdir())), 3)
        self.assertEqual(stop.exception.code, 3)
        self.assertEqual(batches, [("training", 4572, False), ("determinism", 229, True), ("holdout", 200, False)])
        self.assertEqual(common.read_json(output / "summary.json")["status"], "HOLD")
        self.assertEqual(common.read_json(output / "run_state.json")["stage"], "complete")
        self.assertEqual(target.read_text(), (output / "draft_calibration.gd").read_text())
        self.assertEqual((output / "calibration_before.gd").read_text(), "previous synthetic table")


if __name__ == "__main__":
    unittest.main(verbosity=2)
