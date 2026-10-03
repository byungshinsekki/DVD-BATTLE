"""Resumable Windows calibration: train, 5% cold repeats, table, 200 holdout, first picks.

All Godot processes are headless, have isolated APPDATA, and a PID timeout.
No import/export or network operations occur. Import the project separately first.
"""
from __future__ import annotations

import argparse
from concurrent.futures import as_completed
import math
import json
import os
from pathlib import Path
import re
import sys
import threading
import uuid

try:
    from .common import GODOT, ROOT, digest, read_json, require, run_godot, sha, write_json, writable_path, process_pool
    from . import calib_build, calib_cases, sim_sha, runtime_contracts
except ImportError:
    from common import GODOT, ROOT, digest, read_json, require, run_godot, sha, write_json, writable_path, process_pool
    import calib_build
    import calib_cases
    import sim_sha
    import runtime_contracts


def safe_output(root, out):
    root, out = Path(root).resolve(), writable_path(out)
    require(not any(re.match(r"DVD_BATTLE_1\.", part, re.IGNORECASE) for part in (*root.parts, *out.parts)),
            "V1.x source/release paths are read-only")
    require(root != Path("D:/DVD_BATTLE_2.0").resolve(), "Claude's project is not a calibration write target")
    allowed = root / "zz_work"
    scratch = Path("D:/DVD20_CODEX_SCRATCH").resolve()
    require(any(parent in out.parents for parent in (allowed, scratch)), "Output must be under project/zz_work or DVD20_CODEX_SCRATCH")
    return out


class Runner:
    def __init__(self, args, stamp, contract):
        self.args, self.stamp, self.contract = args, stamp, contract
        self.lock = threading.Lock()
        self.binaries = runtime_contracts.BinaryGuard(contract["binaries"])

    def sources_unchanged(self):
        require(sim_sha.source_hashes(self.args.root) == self.stamp["sources"], "Simulation sources changed; do not mix old and new calibration samples")
        require(sim_sha.data_source_hashes(self.args.root) == self.contract["data_sources"], "Data sources changed during calibration")
        require(runtime_contracts.tool_hashes(self.args.root) == self.contract["tool_sources"], "Measurement tools changed during calibration")
        self.binaries.check()

    def run_case_group(self, cases, folder, label, identity):
        self.sources_unchanged()
        request = folder / "cases" / (label + ".json")
        output = writable_path(folder / "results" / (label + ".jsonl"))
        # Preserve all evidence of interrupted/failed attempts before retrying.
        old = [request, output, folder / "logs" / (label + ".log"), folder / "logs" / (label + ".process.json")]
        existing = [writable_path(path) for path in old if path.exists()]
        if existing:
            rejected = writable_path(folder / "rejected" / (label + "_" + uuid.uuid4().hex))
            rejected.mkdir(parents=True)
            for path in existing:
                path.replace(rejected / path.name)
        output.parent.mkdir(parents=True, exist_ok=True)
        write_json(request, cases)
        process = run_godot(self.args.godot, self.args.root,
            ["--script", "res://tools/balance_runner.gd", "--", "--cases=" + request.as_posix(), "--output=" + output.as_posix()],
            folder / "logs" / (label + ".log"), self.args.timeout)
        self.sources_unchanged()
        # Check this chunk independently, even if the engine returned code 0.
        calib_build.read_results([output], cases)
        runtime_contracts.save_receipt(folder, label, cases, identity)
        with self.lock:
            print(f"{folder.name} {label}: {len(cases)} games, {process['seconds']:.1f}s", flush=True)

    def run_batch(self, cases, folder, *, cold=False):
        folder.mkdir(parents=True, exist_ok=True)
        identity = digest({"contract": self.contract, "cases_sha": digest(cases), "cold_process_per_case": cold})
        paths = runtime_contracts.verified_result_paths(folder, cases, identity)
        completed = calib_build.read_results(paths, cases, allow_incomplete=True)
        pending = [case for case in cases if case["id"] not in completed]
        write_json(folder / "progress.json", {"expected": len(cases), "completed": len(completed), "remaining": len(pending),
            "sim_sha": self.stamp["sim_sha"], "cases_sha": digest(cases), "cold_process_per_case": cold})
        # Membership follows original index % jobs, not filtered-pending index.
        jobs = []
        chunk_size = 1 if cold else self.args.chunk_size
        for shard in range(self.args.jobs):
            part = [case for case in pending if int(case["index"]) % self.args.jobs == shard]
            for start in range(0, len(part), chunk_size):
                chunk = part[start:start + chunk_size]
                label = f"shard_{shard}_{digest(chunk)[:20]}"
                jobs.append((chunk, label))
        failures = []
        with process_pool(max_workers=self.args.jobs) as pool:
            futures = {pool.submit(self.run_case_group, chunk, folder, label, identity): label for chunk, label in jobs}
            for future in as_completed(futures):
                try:
                    future.result()
                except Exception as exc:
                    failures.append({"chunk": futures[future], "error": str(exc)})
                    for other in futures:
                        other.cancel()
                    write_json(folder / "failure.json", {"status": "FAIL", "failures": failures})
                    raise RuntimeError(f"Calibration batch failed: {folder}; {failures[:2]}") from exc
        if failures:
            write_json(folder / "failure.json", {"status": "FAIL", "failures": failures})
            raise RuntimeError(f"Calibration batch failed: {folder}; {failures[:2]}")
        rows = calib_build.read_results(runtime_contracts.verified_result_paths(folder, cases, identity), cases)
        write_json(folder / "progress.json", {"expected": len(cases), "completed": len(rows), "remaining": 0,
            "status": "PASS", "sim_sha": self.stamp["sim_sha"], "cases_sha": digest(cases), "cold_process_per_case": cold})
        return rows

    def first_pick_audit(self, roster):
        folder = self.args.out / "first_pick_cases" / uuid.uuid4().hex
        folder.mkdir(parents=True, exist_ok=True)

        def one(size, seed, arena):
            output = folder / f"size{size}_seed{seed}_{arena}.json"
            self.sources_unchanged()
            run_godot(self.args.godot, self.args.root, ["--script", "res://tools/calibration_v2/first_pick_audit.gd", "--",
                f"--team-size={size}", f"--seed={seed}", f"--arena={arena}", "--out=" + output.as_posix()],
                folder / f"size{size}_seed{seed}_{arena}.log", self.args.timeout)
            self.sources_unchanged()
            return read_json(output)

        with process_pool(max_workers=self.args.jobs) as pool:
            futures = [pool.submit(one, size, seed, arena) for size in (1, 3) for seed in (1, 2, 3) for arena in runtime_contracts.ARENAS]
            reports = [future.result() for future in futures]
        return runtime_contracts.first_pick_report(reports, roster)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--godot", type=Path, default=GODOT)
    parser.add_argument("--jobs", type=int, default=6)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--seed", type=int, default=calib_cases.SEED)
    parser.add_argument("--timeout", type=int, default=900)
    parser.add_argument("--chunk-size", type=int, default=1,
                        help="Games per process (default 1 avoids accumulated 900s timeout; raise only after measurement)")
    parser.add_argument("--plan-only", action="store_true", help="Read roster and source stamp; write cases only")
    args = parser.parse_args()
    args.root = args.root.resolve()
    args.out = safe_output(args.root, args.out)
    require(os.name == "nt", "Calibration is stamped for Windows; run on Windows only")
    require(1 <= args.jobs <= 6 and 1 <= args.timeout <= 900 and 1 <= args.chunk_size <= 32, "Invalid process budget")
    args.out.mkdir(parents=True, exist_ok=True)
    input_sources = sim_sha.source_hashes(args.root)
    input_data = sim_sha.data_source_hashes(args.root)
    input_tools = runtime_contracts.tool_hashes(args.root)
    input_binaries = runtime_contracts.binary_hashes(args.godot)
    # Do not overwrite previous evidence before deciding whether resume is valid.
    preflight = args.out / "preflight" / uuid.uuid4().hex
    preflight.mkdir(parents=True)
    version_log = preflight / "godot_version.log"
    run_godot(args.godot, args.root, ["--version"], version_log, args.timeout)
    version = version_log.read_text(encoding="utf-8", errors="replace").strip()
    require(version.startswith("4.7.2.stable"), f"Expected Godot 4.7.2.stable: {version}")
    roster_path = preflight / "roster.json"
    run_godot(args.godot, args.root, ["--script", "res://tools/balance_runner.gd", "--", "--roster=" + roster_path.as_posix()],
              preflight / "roster.log", args.timeout)
    roster = read_json(roster_path)
    cases = calib_cases.generate(roster, args.seed)
    manifest = calib_cases.manifest(roster, cases, args.seed)
    stamp = sim_sha.compute(args.root, args.godot, preflight / "fingerprint", args.timeout)
    require(stamp["sources"] == input_sources and sim_sha.data_source_hashes(args.root) == input_data
            and runtime_contracts.tool_hashes(args.root) == input_tools
            and runtime_contracts.binary_hashes(args.godot) == input_binaries, "Inputs changed during calibration preflight")
    contract = {"schema": 2, "sim_sha": stamp["sim_sha"], "cases_sha": manifest["cases_sha"],
                "roster_sha": manifest["roster_sha"], "tool_sources": input_tools, "binaries": input_binaries,
                "data_sources": input_data, "python_version": sys.version, "jobs": args.jobs,
                "chunk_size": args.chunk_size,
                "godot_version": version,
                "platform": "windows", "seed": args.seed}
    state_path = args.out / "run_state.json"
    if state_path.exists():
        require(read_json(state_path)["contract"] == contract,
                "Existing run belongs to different sources/roster/cases/engine/tools; choose a fresh output directory")
    write_json(state_path, {"contract": contract, "stage": "planned"})
    write_json(args.out / "sim_sha.json", stamp)
    write_json(args.out / "roster.json", roster)
    write_json(args.out / "cases.json", cases)
    write_json(args.out / "cases_manifest.json", manifest)
    for shard in range(args.jobs):
        write_json(args.out / f"shard_{shard}.json", [case for case in cases if case["index"] % args.jobs == shard])
    if args.plan_only:
        print(f"PLANNED {len(cases)} cases; no calibration table written")
        return
    runner = Runner(args, stamp, contract)
    training = runner.run_batch(cases, args.out / "training")
    write_json(state_path, {"contract": contract, "stage": "training_complete"})
    sample = calib_cases.determinism_sample(cases)
    cold = runner.run_batch(sample, args.out / "determinism", cold=True)
    checks = [{"case_id": case["id"], "training": training[case["id"]]["signature"], "cold": cold[case["id"]]["signature"],
               "match": training[case["id"]]["signature"] == cold[case["id"]]["signature"]} for case in sample]
    determinism = {"status": "PASS" if all(row["match"] for row in checks) else "FAIL",
                   "samples": len(sample), "expected_samples": math.ceil(len(cases) * .05), "rows": checks}
    write_json(args.out / "determinism.json", determinism)
    require(determinism["status"] == "PASS", "Cold-start signatures differ; table generation refused")
    runner.sources_unchanged()
    current = sim_sha.compute(args.root, args.godot, args.out / "final_fingerprint", args.timeout)
    require(current["sim_sha"] == stamp["sim_sha"], "Data/source fingerprint changed during measurement")
    data = calib_build.aggregate(roster, cases, training)
    generated = calib_build.build_text(data, stamp)
    candidate = writable_path(args.out / "draft_calibration.gd")
    candidate.write_text(generated, encoding="utf-8", newline="\n")
    write_json(args.out / "table_statistics.json", data)
    candidate_log = args.out / "logs/calib_check_candidate.log"
    run_godot(args.godot, args.root, ["--script", "res://tools/calibration_v2/calib_check.gd", "--",
        "--file=" + candidate.as_posix()], candidate_log, args.timeout)
    candidate_rows = [line.removeprefix("CALIB_CHECK ") for line in candidate_log.read_text(encoding="utf-8").splitlines()
                      if line.startswith("CALIB_CHECK ")]
    require(len(candidate_rows) == 1, "Candidate checker omitted its complete report")
    candidate_report = json.loads(candidate_rows[0])
    require(candidate_report.get("status") == "PASS" and candidate_report.get("failed") == []
            and candidate_report.get("games") == len(cases) and candidate_report.get("roster_count") == len(manifest["roster"]),
            "Candidate table validation failed or is incomplete")
    require(candidate.read_text(encoding="utf-8") == generated, "Candidate table changed during validation")
    runner.sources_unchanged()
    runner.binaries.check(full=True)
    write_json(args.out / "calib_check.json", candidate_report)
    target = writable_path(args.root / "scripts/data/draft_calibration.gd")
    backup = writable_path(args.out / "calibration_before.gd")
    if not backup.exists():
        backup.write_bytes(target.read_bytes())
    temporary = writable_path(target.with_suffix(".gd.partial"))
    temporary.write_text(generated, encoding="utf-8", newline="\n")
    os.replace(temporary, target)
    write_json(state_path, {"contract": contract, "stage": "table_generated", "table_sha": sha(target)})
    unseen_cases = calib_cases.holdout(roster, args.seed)
    write_json(args.out / "holdout_cases.json", unseen_cases)
    unseen = runner.run_batch(unseen_cases, args.out / "holdout")
    holdout_report = calib_build.holdout_audit(data["duel"], unseen_cases, unseen)
    write_json(args.out / "holdout.json", holdout_report)
    first_pick = runner.first_pick_audit(roster)
    write_json(args.out / "first_pick.json", first_pick)
    runner.sources_unchanged()
    runner.binaries.check(full=True)
    require(sha(target) == sha(candidate), "Generated calibration table changed during acceptance audits")
    # Audit threshold failure leaves the measured table/report intact for review.
    # It never changes director weights or reports an acceptance success.
    accepted = holdout_report["status"] == first_pick["status"] == "PASS"
    summary = {"status": "PASS" if accepted else "HOLD", "games": len(cases), "roster": manifest["roster"],
               "sim_sha": stamp["sim_sha"], "table_sha": sha(target), "determinism": determinism["status"],
               "cold_samples": len(sample), "holdout_agreement": holdout_report["sign_agreement"],
               "first_pick": first_pick["status"], "first_pick_groups": first_pick["groups"], "cases_manifest": manifest}
    write_json(args.out / "summary.json", summary)
    write_json(state_path, {"contract": contract, "stage": "complete", "status": summary["status"], "table_sha": sha(target)})
    print(f"CALIBRATION {summary['status']}: games={len(cases)}, cold={len(sample)}, holdout={holdout_report['sign_agreement']:.3f}")
    raise SystemExit(0 if accepted else 3)


if __name__ == "__main__":
    main()
