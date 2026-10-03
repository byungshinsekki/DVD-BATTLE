"""Small infrastructure regressions; never starts Godot or touches player data."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch

import analyze
import run


class TelemetryTests(unittest.TestCase):
    def setUp(self):
        run.STOP.clear()
        scratch = run.PROJECT / "zz_work/c1_prepare/test_scratch"
        scratch.mkdir(parents=True, exist_ok=True)
        self.tmp = tempfile.TemporaryDirectory(dir=scratch)
        self.out = Path(self.tmp.name)

    def tearDown(self):
        run.stop_owned_processes()
        run.STOP.clear()
        assert (run.PROJECT / "zz_work/c1_prepare/test_scratch").resolve() in self.out.resolve().parents
        self.tmp.cleanup()

    def row(self, task, index):
        group = task["group"]
        mi, k = divmod(index, group["n"])
        return {"index": index, "map": group["maps"].split(",")[mi],
                "seed": task["seed0"] + mi * 1000 + k * 17,
                "comp": [str(i) for i in range(group["size"] * 2)],
                "winner": 0, "reason": "elimination", "duration": 3, "heroes": []}

    def test_exact_named_presets_and_second_seed_set(self):
        expected = {"baseline": 282, "extended": 528, "balance": 810,
                    "nav_ring_thorn": 160, "nav_links": 192, "nav_links_small": 96}
        for suite, count in expected.items():
            plan = run.make_plan(suite)
            self.assertEqual(count, sum(len(t["indices"]) for t in plan))
            first, second = plan[:len(plan) // 2], plan[len(plan) // 2:]
            for a, b in zip(first, second):
                self.assertEqual(b["seed0"] - a["seed0"], 50000)
                self.assertEqual(a["indices"], b["indices"])
                self.assertEqual(a["group"], b["group"])
        self.assertEqual(run.make_plan("nav_ring_thorn")[0]["group"]["maps"], "thorn_circuit,bastion_ring")
        self.assertEqual(run.make_plan("nav_links")[0]["group"]["maps"], "dimensional_lattice,rift_harbor,furnace_basin,gale_corridor")

    def test_expected_reproduction_seeds(self):
        ring = run.make_plan("nav_ring_thorn")[0]
        small = run.make_plan("nav_links_small")[0]
        self.assertEqual(self.row(ring, 17)["seed"], 171389)
        self.assertEqual(self.row(ring, 40 + 24)["seed"], 172508)
        self.assertEqual(self.row(small, 12)["seed"], 173100)

    def test_partial_duplicate_and_changed_seed_detection(self):
        task = run.make_plan("nav_ring_thorn")[0]
        rows = [self.row(task, i) for i in task["indices"]]
        path = self.out / "rows.jsonl"
        def write(values):
            path.write_text("\n".join(json.dumps(v) for v in values), encoding="utf-8", newline="\n")
        write(rows)
        self.assertEqual(len(run.validate_rows(path, task)), 20)
        write(rows[:-1])
        with self.assertRaises(ValueError):
            run.validate_rows(path, task)
        self.assertEqual(len(run.validate_rows(path, task, partial=True)), 19)
        write(rows + [rows[-1]])
        with self.assertRaises(ValueError):
            run.validate_rows(path, task, partial=True)
        rows[0]["seed"] += 1
        write(rows)
        with self.assertRaises(ValueError):
            run.validate_rows(path, task)

    def test_timeout_prefix_salvages_complete_lines_only(self):
        task = run.make_plan("nav_ring_thorn")[0]
        path = self.out / "partial.jsonl"
        path.write_text(json.dumps(self.row(task, 0)) + '\n{"index": 4,', encoding="utf-8", newline="\n")
        self.assertEqual([r["index"] for r in run.validate_rows(path, task, partial=True)], [0])
        with self.assertRaises(ValueError):
            run.validate_rows(path, task)

    def test_manifest_partial_and_duplicate_input_rejected(self):
        run.write_json(self.out / "run_manifest.json", {"complete": False})
        with self.assertRaisesRegex(ValueError, "Incomplete run"):
            analyze.read_inputs([str(self.out)])
        task = run.make_plan("nav_ring_thorn")[0]
        row = self.row(task, 0)
        path = self.out / "single.jsonl"
        path.write_text(json.dumps(row) + "\n" + json.dumps(row) + "\n", encoding="utf-8", newline="\n")
        with self.assertRaisesRegex(ValueError, "Duplicate battle"):
            analyze.read_inputs([str(path)])

    def test_censored_nav_events_and_causes_counted(self):
        row = {"map": "thorn_circuit", "reason": "time_limit", "ring_out_s": 2.5, "ring_dmg": 60,
               "heroes": [{"eps": [{"dur": 1.5}, {"dur": 1.49}]}],
               "stuck": [{"dur": 2, "pos": [83.4, 852.9]}],
               "censored_stuck": [{"dur": 3, "pos": [1237, 853]}],
               "trips": [{"cause": "taken", "against": False}, {"cause": "dropped_commit", "against": True}]}
        result = analyze.nav_row([row])
        self.assertEqual(result["stuck_seconds"], 5)
        self.assertEqual(result["censored_stuck_seconds"], 3)
        self.assertEqual(result["pocket_region_seconds"], 2)
        self.assertEqual(result["strict_pocket_seconds"], 2)
        self.assertEqual(result["stuck_seconds_by_cause"]["corner"], 3)
        self.assertEqual(result["ring_episodes_1_5s"], 1)
        self.assertEqual(result["accidental_against_per_battle"], 1)
        self.assertEqual(result["intentional_against_goal"], 0)

    def test_profile_redirect_and_owned_timeout(self):
        log = self.out / "env.log"
        profile = self.out / "profile"
        result = run.run_process([sys.executable, "-c", "import os;print(os.environ['APPDATA'])"], log, profile, 10, self.out)
        self.assertEqual(result["status"], "complete")
        self.assertEqual(log.read_text().strip(), str(profile))
        result = run.run_process([sys.executable, "-c", "import time;time.sleep(10)"], self.out / "timeout.log", profile, 0.1, self.out)
        self.assertTrue(result["timeout"])
        self.assertEqual(result["status"], "failed")
        self.assertEqual(run.ACTIVE, {})

    def test_runtime_snapshot_allows_codex_measurement_output(self):
        run.safe_output(run.PROJECT / "zz_work/measure/C1", Path(r"D:\DVD20_CODEX_SCRATCH\baseline_cfd1024"))
        with self.assertRaises(ValueError):
            run.safe_output(Path(r"D:\DVD_BATTLE_1.5.3_RELEASE\telemetry"), run.PROJECT)

    def test_resume_runs_only_missing_original_index(self):
        from types import SimpleNamespace
        task = {**run.make_plan("nav_ring_thorn")[0], "indices": [0, 4]}
        output = self.out / (task["name"] + ".jsonl")
        (self.out / "logs").mkdir()
        output.write_text(json.dumps(self.row(task, 0)) + "\n", encoding="utf-8", newline="\n")
        previous = {"partial_sha256": run.sha256(output), "partial_indices": [0], "status": "failed", "timeout": True}
        options = SimpleNamespace(godot=run.GODOT, project=run.PROJECT, timeout=900)
        calls = []
        def fake_process(command, log, profile, timeout, cwd):
            calls.append(command)
            self.assertIn("--shard=4/80", command)
            self.assertIn("--n=40", command)
            path = Path(command[-1].split("=", 1)[1])
            path.write_text(json.dumps(self.row(task, 4)) + "\n", encoding="utf-8", newline="\n")
            return {"status": "complete", "wall_seconds": 1}
        with patch.object(run, "run_process", fake_process):
            result = run.execute_task(task, options, self.out, previous)
        self.assertEqual(result["status"], "complete")
        self.assertEqual(result["resumed_indices"], [0])
        self.assertEqual(len(calls), 1)
        self.assertEqual([r["index"] for r in run.validate_rows(output, task)], [0, 4])
        self.assertTrue(run.reusable(result, task, self.out))
        with output.open("a", encoding="utf-8", newline="\n") as stream:
            stream.write(" ")
        self.assertFalse(run.reusable(result, task, self.out))

    def test_paired_navigation_never_pairs_different_rosters(self):
        metrics = {"ring_out_seconds": 3, "ring_damage": 2, "ring_episodes_1_5s": 1,
                   "stuck_seconds": 1, "pocket_region_seconds": 0, "strict_pocket_seconds": 0,
                   "accidental_against_goal": 1, "intentional_against_goal": 0,
                   "dropped_commit_trips": 1, "timeouts": 0}
        before = [{"map": "classic", "seed": 1, "comp": ["a", "b"], "metrics": metrics},
                  {"map": "classic", "seed": 2, "comp": ["c", "d"], "metrics": metrics}]
        after = [{**before[0], "metrics": {**metrics, "ring_out_seconds": 1}},
                 {**before[1], "comp": ["d", "c"]}]
        result = analyze.paired_navigation(before, after)
        self.assertEqual(result["matched"], 1)
        self.assertEqual(result["only_before"], 1)
        self.assertEqual(result["only_after"], 1)
        self.assertEqual(result["by_map"]["classic"]["metrics"]["ring_out_seconds"]["mean_delta"], -2)

    def test_concurrent_resume_cannot_own_same_output_directory(self):
        lock = run.acquire_run_lock(self.out)
        try:
            with self.assertRaisesRegex(ValueError, "Another runner"):
                run.acquire_run_lock(self.out)
        finally:
            lock.close()
        # OS releases the lock; a completed/crashed run leaves no stale blocker.
        run.acquire_run_lock(self.out).close()

    def test_nonfinite_timeout_is_rejected_before_launch(self):
        import contextlib
        import io
        for value in ("nan", "inf", "0", "-1", "900.001", "901"):
            with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
                run.main(["--suite", "baseline", "--out", str(self.out), "--timeout", value, "--print-plan"])

    def test_direct_timeout_cap_rejects_before_spawn(self):
        with patch.object(run.subprocess, "Popen") as spawn:
            for timeout in (float("nan"), float("inf"), 0, -1, 900.001):
                with self.assertRaises(ValueError):
                    run.run_process([sys.executable], self.out / "cap.log", self.out / "profile", timeout, self.out)
            spawn.assert_not_called()

    def test_final_cleanup_failure_cannot_report_success_and_keeps_original_cause(self):
        import contextlib
        import io
        for original_error in (None, ValueError("original measurement failure")):
            run.ACTIVE[123458] = object()
            lock = io.StringIO()
            run.RUN_LOCK = lock
            try:
                with patch.object(run, "_main", return_value=0, side_effect=original_error), \
                     patch.object(run, "stop_owned_processes", return_value=["owned PID 123458: cleanup failed"]), \
                     contextlib.redirect_stderr(io.StringIO()), self.assertRaises(RuntimeError) as caught:
                    run.main([])
                self.assertIn("cleanup failed", str(caught.exception))
                self.assertIs(caught.exception.__cause__, original_error)
                self.assertTrue(lock.closed)
                self.assertIsNone(run.RUN_LOCK)
            finally:
                run.ACTIVE.pop(123458, None)

    def test_stop_during_spawn_includes_registered_process_and_blocks_next_spawn(self):
        entered, release, finished, stopped = (threading.Event() for _ in range(4))
        outcomes, failures, terminated = [], [], []
        class FakeProcess:
            pid = 123456
            returncode = None
            def poll(self):
                return self.returncode
            def wait(self, timeout):
                if not finished.wait(timeout):
                    raise subprocess.TimeoutExpired("fake", timeout)
                return self.returncode
        process = FakeProcess()
        def spawn(*args, **kwargs):
            entered.set()
            if not release.wait(3):
                raise RuntimeError("spawn barrier timed out")
            return process
        def terminate(p):
            terminated.append(p.pid)
            p.returncode = -9
            finished.set()
            return {"method": "fake_owned_tree", "pid": p.pid}
        def work():
            try:
                outcomes.append(run.run_process(["fake"], self.out / "race.log", self.out / "profile", 10, self.out))
            except BaseException as exc:
                failures.append(exc)
        def stop():
            failures.extend(run.stop_owned_processes())
            stopped.set()
        with patch.object(run.subprocess, "Popen", side_effect=spawn) as popen, \
             patch.object(run, "terminate_owned_process_tree", side_effect=terminate):
            worker = threading.Thread(target=work)
            stopper = threading.Thread(target=stop)
            worker.start()
            try:
                self.assertTrue(entered.wait(3))
                stopper.start()
                self.assertTrue(run.STOP.wait(3))
                self.assertFalse(stopped.is_set())
            finally:
                release.set()
                worker.join(5)
                if stopper.ident is not None:
                    stopper.join(5)
            self.assertFalse(worker.is_alive())
            self.assertFalse(stopper.is_alive())
            self.assertEqual(failures, [])
            self.assertEqual(terminated, [process.pid])
            self.assertEqual(outcomes[0]["returncode"], -9)
            self.assertEqual(run.ACTIVE, {})
            cancelled = run.run_process(["fake"], self.out / "cancelled.log", self.out / "profile", 10, self.out)
            self.assertEqual(cancelled["status"], "cancelled")
            self.assertEqual(popen.call_count, 1)

    def test_keyboard_interrupt_uses_tree_cleanup_and_unregisters(self):
        class FakeProcess:
            pid = 123457
            returncode = None
            def poll(self):
                return self.returncode
            def wait(self, timeout):
                raise KeyboardInterrupt()
        process = FakeProcess()
        def terminate(p):
            p.returncode = -9
            return {"method": "fake_owned_tree", "pid": p.pid}
        with patch.object(run.subprocess, "Popen", return_value=process), \
             patch.object(run, "terminate_owned_process_tree", side_effect=terminate) as cleanup:
            with self.assertRaises(KeyboardInterrupt):
                run.run_process(["fake"], self.out / "interrupt.log", self.out / "profile", 10, self.out)
        cleanup.assert_called_once_with(process)
        self.assertEqual(run.ACTIVE, {})

    @unittest.skipUnless(os.name == "nt", "Windows taskkill process-tree regression")
    def test_timeout_kills_python_child_and_grandchild_but_not_unrelated_pid(self):
        import ctypes
        from ctypes import wintypes
        kernel = ctypes.WinDLL("kernel32", use_last_error=True)
        kernel.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
        kernel.OpenProcess.restype = wintypes.HANDLE
        kernel.WaitForSingleObject.argtypes = [wintypes.HANDLE, wintypes.DWORD]
        kernel.WaitForSingleObject.restype = wintypes.DWORD
        kernel.CloseHandle.argtypes = [wintypes.HANDLE]
        def alive(pid):
            handle = kernel.OpenProcess(0x00100000, False, pid)
            if not handle:
                return False
            try:
                return kernel.WaitForSingleObject(handle, 0) == 258
            finally:
                kernel.CloseHandle(handle)
        pid_file = self.out / "descendants.json"
        child_code = ("import json,os,subprocess,sys,time;from pathlib import Path;"
                      "p=subprocess.Popen([sys.executable,'-c','import time;time.sleep(30)'],creationflags=0x08000000);"
                      f"Path({str(pid_file)!r}).write_text(json.dumps({{'child':os.getpid(),'grandchild':p.pid}}));time.sleep(30)")
        parent_code = ("import subprocess,sys,time;"
                       f"subprocess.Popen([sys.executable,'-c',{child_code!r}],creationflags=0x08000000);time.sleep(30)")
        unrelated = subprocess.Popen([sys.executable, "-c", "import time;time.sleep(30)"], creationflags=0x08000000)
        descendants = {}
        try:
            result = run.run_process([sys.executable, "-c", parent_code], self.out / "tree.log", self.out / "profile", 3, self.out)
            self.assertTrue(pid_file.exists(), "owned child and grandchild must exist before timeout")
            descendants = json.loads(pid_file.read_text())
            self.assertTrue(result["timeout"])
            self.assertEqual(result["termination"]["method"], "taskkill_pid_tree")
            self.assertFalse(alive(result["pid"]))
            self.assertFalse(alive(descendants["child"]))
            self.assertFalse(alive(descendants["grandchild"]))
            self.assertIsNone(unrelated.poll(), "cleanup must not select processes by executable name")
            self.assertEqual(run.ACTIVE, {})
        finally:
            run.terminate_owned_process_tree(unrelated)
            # Failure cleanup remains scoped to descendant PIDs created by
            # this test; never enumerate or select other Python processes.
            if pid_file.exists():
                descendants = json.loads(pid_file.read_text())
            for pid in descendants.values():
                if alive(pid):
                    subprocess.run([str(Path(os.environ["SystemRoot"]) / "System32/taskkill.exe"),
                                    "/PID", str(pid), "/T", "/F"], capture_output=True,
                                   timeout=15, creationflags=0x08000000)

    def test_explicit_team_seed_sets_extend_without_changing_existing_plan(self):
        for suite in ("baseline", "extended", "balance"):
            old = run.make_plan(suite, "both")
            expanded = run.make_plan(suite, "1,2,3")
            self.assertEqual(expanded[:len(old)], old)
            first = old[:len(old) // 2]
            third = expanded[len(old):]
            for a, b in zip(first, third):
                self.assertEqual(b["seed0"] - a["seed0"], 100000)
                self.assertEqual(b["seed_set"], 3)
                self.assertEqual(a["group"], b["group"])
                self.assertEqual(a["indices"], b["indices"])
        self.assertEqual(sum(len(t["indices"]) for t in run.make_plan("balance", "1,2,3")), 1215)

    def test_nav_seed_contract_and_invalid_explicit_lists_are_rejected(self):
        for suite in ("nav_ring_thorn", "nav_links", "nav_links_small"):
            self.assertEqual(run.make_plan(suite, "both"), run.make_plan(suite, "1,2"))
            with self.assertRaisesRegex(ValueError, "fixed seed sets"):
                run.make_plan(suite, "1,2,3")
        for value in ("", "0", "-1", "1,1", "1,,2", "a", str(2**63)):
            with self.assertRaises(ValueError):
                run.make_plan("balance", value)


if __name__ == "__main__":
    unittest.main()
