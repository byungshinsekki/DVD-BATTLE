"""Windows forced battles with isolated, bounded owned processes.

Legacy positional arguments are retained. Each run owns a NEW <out_dir>/<tag>/
directory for input snapshots, JSONL, logs, process receipts and RESULT.json.
Reusing a tag is refused, including after failure or interruption. --dry-run
validates inputs and prints the plan without writes or starting Godot. Import
the project in isolated QA before using this runner; no import is automatic.
"""
from __future__ import annotations

import argparse
from concurrent.futures import as_completed
import hashlib
import json
import os
from pathlib import Path
import re
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "release_v2"))
import common
import config


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    parser.add_argument("cases", type=Path)
    parser.add_argument("out_dir", type=Path)
    parser.add_argument("tag")
    parser.add_argument("variant", nargs="?", default="base")
    parser.add_argument("variants", nargs="?", default="")
    parser.add_argument("shards", nargs="?", type=int, default=8)
    parser.add_argument("jobs", nargs="?", type=int, choices=(1, 2), default=2)
    parser.add_argument("--timeout", type=int, default=900, help="Per-shard seconds, 1..900")
    parser.add_argument("--dry-run", action="store_true", help="Read-only plan; no Godot, output or profile writes")
    return parser.parse_args(argv)


def source_hashes(root):
    hashes = common.runtime_hashes(root)
    hashes["tools/balance_v2/forced_runner.gd"] = common.sha(root / "tools/balance_v2/forced_runner.gd")
    return hashes


def make_plan(args):
    common.require(os.name == "nt", "This launcher requires Windows and configured Windows Godot")
    common.require(1 <= args.timeout <= 900, "Timeout must be 1..900 seconds")
    common.require(1 <= args.shards <= 256, "Shard count must be 1..256")
    common.require(args.jobs in (1, 2), "At most two Godot jobs are allowed")
    common.require(re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]{0,63}", args.tag), "Tag must be 1..64 ASCII letters/digits/_/-")
    common.require(not re.fullmatch(r"(?i:con|prn|aux|nul|com[1-9]|lpt[1-9])", args.tag), "Tag is a reserved Windows filename")
    root = common.safe_write_path(args.root)
    common.require(root == config.PROJECT.resolve() or common.within(root, config.SCRATCH) or root == config.QA.resolve(),
                   "Project must be this Codex project or a dedicated scratch/QA project")
    common.require((root / "project.godot").is_file() and (root / "tools/balance_v2/forced_runner.gd").is_file(), "Project or forced_runner.gd is missing")
    common.require((root / ".godot/global_script_class_cache.cfg").is_file(), "Complete an isolated project import first")
    common.require(config.GODOT.is_file(), "Configured Godot binary is missing; no downloads are attempted")
    out_dir = common.safe_write_path(args.out_dir)
    common.require(common.within(out_dir, config.PROJECT / "zz_work") or common.within(out_dir, config.SCRATCH),
                   "Output must be inside this project's zz_work or configured scratch")
    run_dir = common.safe_write_path(out_dir / args.tag)
    profile = common.guard_output(config.SCRATCH / "balance_v2" / args.tag)
    common.require(not run_dir.exists(), "Run output already exists; choose a new tag: " + str(run_dir))
    common.require(not profile.exists(), "Run profile already exists; choose a new tag: " + str(profile))
    common.require(not common.within(run_dir, profile) and not common.within(profile, run_dir), "Output and profile directories must be disjoint")
    cases_path = args.cases.resolve(strict=True)
    cases_bytes = cases_path.read_bytes()
    cases = json.loads(cases_bytes.decode("utf-8"))
    common.require(isinstance(cases, list) and cases, "Cases must be a nonempty JSON array")
    ids = []
    for case in cases:
        common.require(isinstance(case, dict) and isinstance(case.get("id"), str) and case["id"], "Every case needs a nonempty string id")
        common.require(case.get("forced_team") in (0, 1) and isinstance(case.get("forced"), str) and case["forced"], "Every case needs its forced hero and team")
        common.require(all(isinstance(case.get(team), list) and case[team] for team in ("blue", "red")), "Every case needs two nonempty rosters")
        common.require(case["forced"] in case["blue" if case["forced_team"] == 0 else "red"], "Forced hero must belong to its indicated team")
        common.require(isinstance(case.get("arena_id"), str) and case["arena_id"] and isinstance(case.get("seed"), int), "Every case needs an arena and integer seed")
        ids.append(case["id"])
    common.require(len(set(ids)) == len(ids), "Case ids must be unique")
    common.require(args.shards <= len(cases), "Shard count cannot exceed case count")
    variants_bytes = None
    variants_path = None
    if args.variant != "base":
        common.require(bool(args.variants), "A named variant requires its variants.json path")
        variants_path = Path(args.variants).resolve(strict=True)
        variants_bytes = variants_path.read_bytes()
        variants = json.loads(variants_bytes.decode("utf-8"))
        common.require(isinstance(variants, dict) and isinstance(variants.get(args.variant), list) and variants[args.variant], "Named variant is missing or empty")
    shards = []
    for i in range(args.shards):
        output = run_dir / f"{args.tag}_s{i}.jsonl"
        log = run_dir / f"{args.tag}_s{i}.log"
        shard_profile = profile / f"shard_{i}"
        command = [str(config.GODOT), "--headless", "--path", str(root), "--script", "res://tools/balance_v2/forced_runner.gd", "--",
                   "--cases=" + str(run_dir / "cases.json"), "--out=" + str(output), f"--shard={i}/{args.shards}"]
        if variants_bytes is not None:
            command += ["--variant=" + args.variant, "--variants=" + str(run_dir / "variants.json")]
        shards.append({"index": i, "command": command, "output": str(output), "log": str(log), "profile": str(shard_profile),
                       "appdata": str(shard_profile / "Roaming"), "localappdata": str(shard_profile / "Local"),
                       "receipt": str(log) + ".process.json", "case_ids": ids[i::args.shards]})
    plan = {"status": "DRY_RUN" if args.dry_run else "PLANNED", "project": str(root), "run_dir": str(run_dir), "profile": str(profile),
            "jobs": args.jobs, "timeout_seconds": args.timeout, "variant": args.variant, "case_count": len(cases),
            "cases_input": str(cases_path), "cases_sha256": hashlib.sha256(cases_bytes).hexdigest(),
            "variants_input": str(variants_path) if variants_path else None,
            "variants_sha256": hashlib.sha256(variants_bytes).hexdigest() if variants_bytes is not None else None,
            "source_hashes": source_hashes(root), "shards": shards}
    return plan, cases_bytes, variants_bytes, cases


def validate_rows(shard, cases, variant):
    path = Path(shard["output"])
    common.require(path.is_file(), "Shard JSONL is missing")
    lines = path.read_text(encoding="utf-8").splitlines()
    common.require(all(line.strip() for line in lines), "Shard JSONL contains a blank row")
    rows = [json.loads(line) for line in lines]
    common.require(all(isinstance(row, dict) for row in rows), "Shard rows must be objects")
    common.require([row.get("case_id") for row in rows] == shard["case_ids"], "Shard cases are missing, repeated or out of order")
    expected = {case["id"]: case for case in cases}
    for row in rows:
        case = expected[row["case_id"]]
        common.require(row.get("variant") == variant and row.get("invariant_error") == "", "Variant mismatch or simulation invariant failure")
        common.require(all(row.get(dst) == case.get(src, "") for dst, src in (("forced", "forced"), ("forced_team", "forced_team"),
                       ("arena", "arena_id"), ("seed", "seed"), ("set", "set"))), "Row inputs differ from the submitted case")
        common.require(type(row.get("winner")) is int and row["winner"] in (0, 1, 2) and isinstance(row.get("signature"), str)
                       and re.fullmatch(r"[0-9a-f]{64}", row["signature"]), "Row winner or signature is malformed")
    log = Path(shard["log"]).read_text(encoding="utf-8", errors="replace")
    done = re.findall(r"^FORCED_DONE cases=(\d+) failures=(\d+) wall_seconds=", log, re.MULTILINE)
    common.require(done == [(str(len(rows)), "0")], "Missing or inconsistent shard completion record")
    return {"count": len(rows), "sha256": common.sha(path)}


def execute(plan, cases_bytes, variants_bytes, cases):
    run_dir = Path(plan["run_dir"])
    profile = Path(plan["profile"])
    # Atomic reservation: never reuse existing output, evidence or profiles.
    common.safe_write_path(run_dir).mkdir(parents=True, exist_ok=False)
    futures = {}
    results = {}
    failure = None
    code = 1
    try:
        common.safe_write_path(profile).mkdir(parents=True, exist_ok=False)
        common.write_json(run_dir / "PLAN.json", plan)
        common.atomic_bytes(run_dir / "cases.json", cases_bytes)
        if variants_bytes is not None:
            common.atomic_bytes(run_dir / "variants.json", variants_bytes)

        def one(shard):
            result = {"index": shard["index"], "status": "FAIL", "process_receipt": shard["receipt"]}
            try:
                result["process"] = common.run(shard["command"], shard["log"], shard["profile"],
                                               timeout=plan["timeout_seconds"], cwd=plan["project"], check=False)
                common.require(result["process"]["status"] == "PASS", "Native process, diagnostics or cleanup failed")
                result["rows"] = validate_rows(shard, cases, plan["variant"])
                result["status"] = "PASS"
            except Exception as exc:
                result["error"] = repr(exc)
            common.write_json(run_dir / f"shard_{shard['index']}.result.json", result)
            return result

        with common.process_pool(max_workers=plan["jobs"]) as pool:
            futures = {pool.submit(one, shard): shard["index"] for shard in plan["shards"]}
            for future in as_completed(futures):
                result = future.result()
                results[result["index"]] = result
                print(f"shard {result['index']} {result['status']}", flush=True)
                common.require(result["status"] == "PASS", "A shard failed; cancel remaining owned processes and preserve partial evidence")
        common.require(source_hashes(Path(plan["project"])) == plan["source_hashes"], "Project runtime inputs changed during measurement")
        common.require(common.sha(run_dir / "cases.json") == plan["cases_sha256"], "Cases snapshot changed during measurement")
        if variants_bytes is not None:
            common.require(common.sha(run_dir / "variants.json") == plan["variants_sha256"], "Variant snapshot changed during measurement")
        code = 0
    except KeyboardInterrupt as exc:
        failure = repr(exc)
        code = 130
    except Exception as exc:
        failure = repr(exc)
    finally:
        # process_pool finishes cleanup first. Keep receipts from concurrently
        # cancelled shards as well as the shard that caused cancellation.
        for future, index in futures.items():
            if index in results:
                continue
            if future.cancelled():
                results[index] = {"index": index, "status": "NOT_STARTED"}
            else:
                try:
                    results[index] = future.result()
                except BaseException as exc:
                    results[index] = {"index": index, "status": "FAIL", "error": repr(exc)}
        summary = {"status": "PASS" if code == 0 else "FAIL", "exit_code": code, "error": failure,
                   "complete": len(results) == len(plan["shards"]) and all(r["status"] == "PASS" for r in results.values()),
                   "results": [results[i] for i in sorted(results)], "plan": str(run_dir / "PLAN.json")}
        common.write_json(run_dir / "RESULT.json", summary)
    print(json.dumps({"status": summary["status"], "exit_code": code, "result": str(run_dir / "RESULT.json")}), flush=True)
    return code


def main(argv=None):
    args = parse_args(argv)
    try:
        plan, cases_bytes, variants_bytes, cases = make_plan(args)
        if args.dry_run:
            print(json.dumps(plan, ensure_ascii=False, indent=2))
            return 0
        return execute(plan, cases_bytes, variants_bytes, cases)
    except (OSError, RuntimeError, ValueError, TypeError) as exc:
        print("FORCED_LAUNCHER_ERROR: " + str(exc), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
