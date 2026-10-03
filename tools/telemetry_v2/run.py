"""Deterministic, resumable V2 telemetry runner; stdlib only.

Changing n or the map order changes the seeded deck. The named presets below are
immutable reproductions of the analysis plans, not just equivalent match counts.
"""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import asdict, dataclass
import hashlib
import json
import math
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import threading
import time

PROJECT = Path(__file__).resolve().parents[2]
GODOT = Path(r"D:\DVD_BATTLE_1.2.1_RECOVERY_WORK\tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe")
SECOND_SEED_OFFSET = 50000
E5_MAPS = "classic,thorn_circuit,wind_temple,crossroads,twin_foundry,rift_harbor"
LINK_MAPS = "dimensional_lattice,rift_harbor,furnace_basin,gale_corridor"
PROBLEM = re.compile(r"SCRIPT ERROR|Parse Error|(?:^|\n)ERROR:|WARNING:.*\.gd|\.gd.*WARNING:", re.I)
ACTIVE: dict[int, subprocess.Popen] = {}
ACTIVE_LOCK = threading.Lock()
STOP = threading.Event()
RUN_LOCK = None


@dataclass(frozen=True)
class Group:
    name: str
    mode: str
    maps: str
    map_count: int
    n: int
    size: int
    seed0: int
    shards: int
    nav: bool = False


BASELINE = (
    Group("e3", "elimination", "all", 12, 8, 3, 153100, 4),
    Group("e5", "elimination", E5_MAPS, 6, 4, 5, 153500, 2),
    Group("c5", "control", "all", 3, 4, 5, 153700, 3),
    Group("dm8", "deathmatch", "all", 3, 3, 8, 153900, 3),
)
EXTENDED = (
    Group("x3", "elimination", "all", 12, 18, 3, 163100, 6),
    Group("x5", "elimination", "all", 12, 3, 5, 163500, 4),
    Group("xdm", "deathmatch", "all", 3, 4, 8, 163900, 2),
)
SUITES = {
    "baseline": BASELINE,
    "extended": EXTENDED,
    "balance": BASELINE + EXTENDED,
    "nav_ring_thorn": (Group("ring_thorn", "elimination", "thorn_circuit,bastion_ring", 2, 40, 3, 171100, 4, True),),
    "nav_links": (Group("links", "elimination", LINK_MAPS, 4, 24, 3, 176100, 4, True),),
    "nav_links_small": (Group("links_small", "elimination", LINK_MAPS, 4, 12, 3, 172100, 4, True),),
}


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def source_fingerprint(project: Path) -> dict:
    paths = [project / "project.godot", project / "tools/ai_probe_153.gd"]
    paths += sorted((project / "scripts").rglob("*.gd"))
    paths += sorted((project / "tools/telemetry_v2").glob("*.gd"))
    values = {p.relative_to(project).as_posix(): sha256(p) for p in paths}
    return {"sha256": hashlib.sha256(json.dumps(values, sort_keys=True).encode()).hexdigest(), "files": values}


def write_json(path: Path, data) -> None:
    temp = path.with_suffix(path.suffix + ".tmp")
    with temp.open("w", encoding="utf-8", newline="\n") as stream:
        json.dump(data, stream, ensure_ascii=False, indent=2)
        stream.write("\n")
    temp.replace(path)


def parse_seed_sets(suite: str, value: str) -> tuple[int, ...]:
    if value == "both":
        return (1, 2)
    try:
        values = tuple(int(part.strip()) for part in value.split(","))
    except ValueError:
        raise ValueError("--seed-sets requires 'both' or a comma-separated list of positive integers") from None
    if not values or any(number <= 0 for number in values) or len(set(values)) != len(values):
        raise ValueError("Seed set identifiers must be distinct positive integers")
    if suite.startswith("nav_") and any(number not in (1, 2) for number in values):
        raise ValueError("Navigation presets only permit the fixed seed sets 1 and 2")
    largest_base = max(g.seed0 + (g.map_count - 1) * 1000 + (g.n - 1) * 17 for g in SUITES[suite])
    if largest_base + (max(values) - 1) * SECOND_SEED_OFFSET > 2**63 - 1:
        raise ValueError("Seed set would exceed Godot's signed int64 seed range")
    return values


def make_plan(suite: str, seed_sets: str = "both", ai: str = "tactician") -> list[dict]:
    result = []
    for seed_set in parse_seed_sets(suite, seed_sets):
        for group in SUITES[suite]:
            seed0 = group.seed0 + (seed_set - 1) * SECOND_SEED_OFFSET
            for shard in range(group.shards):
                arguments = [f"--mode={group.mode}", f"--maps={group.maps}", f"--n={group.n}",
                             f"--size={group.size}", f"--seed0={seed0}", "--max_time=150",
                             f"--shard={shard}/{group.shards}", f"--ai={ai}"]
                if group.mode == "deathmatch":
                    arguments.append("--kill_target=10")
                result.append({"name": f"{group.name}_set{seed_set}_s{shard}",
                               "group": asdict(group), "seed_set": seed_set, "seed0": seed0,
                               "shard": shard, "arguments": arguments,
                               "script": "res://tools/telemetry_v2/nav_scan.gd" if group.nav else "res://tools/ai_probe_153.gd",
                               "indices": list(range(shard, group.map_count * group.n, group.shards))})
    return result


def validate_rows(path: Path, task: dict, partial: bool = False) -> list[dict]:
    lines = path.read_text(encoding="utf-8").splitlines()
    rows = []
    for index, line in enumerate(lines):
        if not line.strip():
            continue
        try:
            rows.append(json.loads(line))
        except json.JSONDecodeError:
            if partial and index == len(lines) - 1:
                break
            raise
    indices = [r["index"] for r in rows]
    valid = (indices == sorted(set(indices)) and set(indices).issubset(task["indices"])) if partial else indices == task["indices"]
    if not valid:
        raise ValueError(f"{path.name}: missing, duplicate, or reordered match indices")
    group = task["group"]
    map_names = group["maps"].split(",") if group["maps"] != "all" else None
    for row in rows:
        mi, k = divmod(row["index"], group["n"])
        expected_seed = task["seed0"] + mi * 1000 + k * 17
        if row["seed"] != expected_seed:
            raise ValueError(f"{path.name}: seed mismatch at index {row['index']}")
        if map_names and row["map"] != map_names[mi]:
            raise ValueError(f"{path.name}: map order mismatch")
        size = group["size"] if group["mode"] == "deathmatch" else group["size"] * 2
        if len(row["comp"]) != size or len(set(row["comp"])) != size:
            raise ValueError(f"{path.name}: invalid roster")
        if not all(k in row for k in ("winner", "reason", "duration", "heroes")):
            raise ValueError(f"{path.name}: incomplete result")
    return rows


def terminate_owned_process_tree(process: subprocess.Popen) -> dict:
    """Stop only this Popen's live PID tree; never select an executable name."""
    if process.poll() is not None:
        return {"method": "already_exited", "pid": process.pid}
    if os.name == "nt":
        taskkill = Path(os.environ.get("SystemRoot", r"C:\Windows")) / "System32/taskkill.exe"
        result = subprocess.run([str(taskkill), "/PID", str(process.pid), "/T", "/F"],
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                timeout=15, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        if result.returncode != 0 and process.poll() is None:
            raise RuntimeError(f"Owned PID tree {process.pid} cleanup failed: {result.stdout!r}")
        method = "taskkill_pid_tree"
    else:
        # Each non-Windows child below owns its new session/process group.
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        method = "owned_process_group"
    process.wait(timeout=15)
    return {"method": method, "pid": process.pid}


def stop_owned_processes() -> list[str]:
    # Publish STOP first. Spawn checks it while holding the registration lock,
    # so a spawn already in progress is registered before this snapshot.
    STOP.set()
    with ACTIVE_LOCK:
        owned = list(ACTIVE.values())
    errors = []
    for process in owned:
        try:
            terminate_owned_process_tree(process)
        except (OSError, RuntimeError, subprocess.SubprocessError) as exc:
            errors.append(f"owned PID {process.pid}: {exc}")
        finally:
            if process.poll() is not None:
                with ACTIVE_LOCK:
                    ACTIVE.pop(process.pid, None)
    return errors


def run_process(command: list[str], log: Path, profile: Path, timeout: float, cwd: Path) -> dict:
    """Run one owned PID. Child APPDATA never points to a real player profile."""
    if not math.isfinite(timeout) or not 0 < timeout <= 900:
        raise ValueError("Every child process requires a finite timeout in (0, 900] seconds")
    profile.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env["APPDATA"] = str(profile)
    env["LOCALAPPDATA"] = str(profile / "local")
    env["XDG_DATA_HOME"] = str(profile / "xdg_data")
    env["XDG_CONFIG_HOME"] = str(profile / "xdg_config")
    started = time.monotonic()
    timed_out = False
    termination = None
    with log.open("w", encoding="utf-8", newline="\n") as stream:
        with ACTIVE_LOCK:
            if STOP.is_set():
                return {"status": "cancelled"}
            process = subprocess.Popen(command, cwd=cwd, env=env, stdout=stream, stderr=subprocess.STDOUT,
                                       creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
                                       start_new_session=os.name != "nt")
            ACTIVE[process.pid] = process
        try:
            try:
                code = process.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                timed_out = True
                termination = terminate_owned_process_tree(process)
                code = process.returncode
        except BaseException:
            if process.poll() is None:
                terminate_owned_process_tree(process)
            raise
        finally:
            # Keep a still-live handle registered if OS cleanup failed, so the
            # caller's final cleanup can retry and report its exact owned PID.
            if process.poll() is not None:
                with ACTIVE_LOCK:
                    ACTIVE.pop(process.pid, None)
    text = log.read_text(encoding="utf-8", errors="replace")
    problems = [line for line in text.splitlines() if PROBLEM.search(line)]
    return {"status": "complete" if code == 0 and not timed_out and not problems else "failed",
            "pid": process.pid, "returncode": code, "timeout": timed_out,
            "termination": termination,
            "wall_seconds": round(time.monotonic() - started, 3), "problems": problems[:20],
            "log": log.name, "appdata": str(profile)}


def execute_task(task: dict, options, out: Path, previous: dict | None = None) -> dict:
    output = out / (task["name"] + ".jsonl")
    log = out / "logs" / (task["name"] + ".log")
    checkpoint = out / (task["name"] + ".checkpoint.json")
    task_sha = hashlib.sha256(json.dumps(task, sort_keys=True).encode()).hexdigest()
    command = [str(options.godot), "--headless", "--path", str(options.project), "--script", task["script"],
               "--", *task["arguments"], "--out=" + output.as_posix()]
    retained = []
    if checkpoint.exists():
        saved = json.loads(checkpoint.read_text(encoding="utf-8"))
        if saved.get("task_sha256") == task_sha:
            previous = saved
    if previous and previous.get("partial_sha256") and output.exists() and previous["partial_sha256"] == sha256(output):
        retained = validate_rows(output, task, partial=True)
    if retained:
        # Retry only missing original indices. The full deck n/maps/seed stays
        # unchanged; index/total is simply a one-match shard of that same plan.
        done = {r["index"]: r for r in retained}
        results = []
        total = task["group"]["n"] * task["group"]["map_count"]
        result = {"status": "complete", "resumed_indices": sorted(done), "attempts": results}
        for index in task["indices"]:
            if index in done:
                continue
            name = task["name"] + f"_retry_i{index}"
            retry_output = out / "logs" / (name + ".jsonl.part")
            retry_command = [*command[:-1], f"--shard={index}/{total}", "--out=" + retry_output.as_posix()]
            attempt = run_process(retry_command, out / "logs" / (name + ".log"), out / "_profiles" / name, options.timeout, options.project)
            results.append(attempt)
            if attempt["status"] != "complete":
                result["status"] = "failed"
                break
            retry_rows = validate_rows(retry_output, {**task, "indices": [index]})
            done[index] = retry_rows[0]
            temp = output.with_suffix(".jsonl.tmp")
            with temp.open("w", encoding="utf-8", newline="\n") as stream:
                for key in sorted(done):
                    stream.write(json.dumps(done[key], ensure_ascii=False) + "\n")
            temp.replace(output)
            write_json(checkpoint, {"task_sha256": task_sha, "partial_sha256": sha256(output), "partial_indices": sorted(done)})
        result["wall_seconds"] = round(sum(r.get("wall_seconds", 0) for r in results), 3)
    else:
        result = run_process(command, log, out / "_profiles" / task["name"], options.timeout, options.project)
    result["command"] = command
    if result["status"] == "complete":
        try:
            rows = validate_rows(output, task)
            result.update({"sha256": sha256(output), "battles": len(rows), "output": output.name})
        except (ValueError, KeyError, OSError) as exc:
            result.update({"status": "failed", "validation_error": str(exc)})
    if result["status"] != "complete" and output.exists() and (retained or result.get("timeout") or STOP.is_set()) and not result.get("problems"):
        try:
            partial_rows = validate_rows(output, task, partial=True)
            result["partial_indices"] = [r["index"] for r in partial_rows]
            result["partial_sha256"] = sha256(output)
            write_json(checkpoint, {"task_sha256": task_sha, "partial_sha256": result["partial_sha256"], "partial_indices": result["partial_indices"]})
        except (ValueError, KeyError, OSError):
            pass
    return result


def safe_output(out: Path, project: Path) -> None:
    if out != PROJECT and PROJECT not in out.parents and Path(r"D:\DVD20_CODEX_SCRATCH") not in out.parents:
        raise ValueError("Output must be inside this project or D:\\DVD20_CODEX_SCRATCH")
    if out == project or not ("zz_work" in out.parts or "reports" in out.parts or "DVD20_CODEX_SCRATCH" in out.parts):
        raise ValueError("Use a dedicated zz_work, reports, or scratch output directory")


def reusable(result: dict, task: dict, out: Path) -> bool:
    try:
        path = out / (task["name"] + ".jsonl")
        return result.get("status") == "complete" and result.get("sha256") == sha256(path) and bool(validate_rows(path, task))
    except (OSError, ValueError, KeyError):
        return False


def acquire_run_lock(out: Path):
    """OS-owned lock: two resumptions cannot overwrite the same output set."""
    stream = (out / ".run.lock").open("a+b")
    if stream.seek(0, os.SEEK_END) == 0:
        stream.write(b"0")
        stream.flush()
    stream.seek(0)
    try:
        if os.name == "nt":
            import msvcrt
            msvcrt.locking(stream.fileno(), msvcrt.LK_NBLCK, 1)
        else:
            import fcntl
            fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        stream.close()
        raise ValueError("Another runner holds this output directory; wait for it to finish") from None
    return stream


def main(argv=None) -> int:
    global RUN_LOCK
    try:
        return _main(argv)
    finally:
        original_error = sys.exc_info()[1]
        cleanup_errors = []
        with ACTIVE_LOCK:
            live = bool(ACTIVE)
        if live:
            cleanup_errors = stop_owned_processes()
            for error in cleanup_errors:
                print("PROCESS_CLEANUP_ERROR " + error, file=sys.stderr)
        if RUN_LOCK is not None:
            RUN_LOCK.close()
            RUN_LOCK = None
        if cleanup_errors:
            raise RuntimeError("Owned process cleanup failed: " + "; ".join(cleanup_errors)) from original_error


def _main(argv=None) -> int:
    global RUN_LOCK
    STOP.clear()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--suite", choices=SUITES, required=True)
    parser.add_argument("--jobs", type=int, default=4)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--project", type=Path, default=PROJECT)
    parser.add_argument("--godot", type=Path, default=GODOT)
    parser.add_argument("--timeout", type=float, default=900)
    parser.add_argument("--seed-sets", default="both", help="both (default), or distinct positive set IDs: 1,2,3; nav permits only 1/2")
    parser.add_argument("--ai", default="tactician")
    parser.add_argument("--print-plan", action="store_true")
    options = parser.parse_args(argv)
    if not 1 <= options.jobs <= 6 or not math.isfinite(options.timeout) or not 0 < options.timeout <= 900:
        parser.error("--jobs must be 1..6 and --timeout must be finite and in (0, 900] seconds")
    options.project = options.project.resolve()
    out = options.out.resolve()
    tasks = make_plan(options.suite, options.seed_sets, options.ai)
    if options.print_plan:
        print(json.dumps({"suite": options.suite, "battles": sum(len(t["indices"]) for t in tasks), "tasks": tasks}, indent=2))
        return 0
    safe_output(out, options.project)
    out.mkdir(parents=True, exist_ok=True)
    RUN_LOCK = acquire_run_lock(out)
    (out / "logs").mkdir(exist_ok=True)
    fingerprint = source_fingerprint(options.project)
    config = {"suite": options.suite, "seed_sets": options.seed_sets, "ai": options.ai,
              "project": str(options.project), "godot": str(options.godot.resolve()),
              "godot_sha256": sha256(options.godot), "source_sha256": fingerprint["sha256"], "tasks": tasks}
    manifest_path = out / "run_manifest.json"
    if manifest_path.exists():
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        if manifest["config"] != config:
            raise ValueError("Resume rejected: source/engine/config changed. Use a new output directory.")
    else:
        manifest = {"schema": 1, "config": config, "source": fingerprint, "results": {}, "complete": False}
        write_json(manifest_path, manifest)
    roster_path = out / "roster_meta.json"
    if not (manifest.get("roster", {}).get("status") == "complete" and roster_path.exists()
            and manifest["roster"].get("sha256") == sha256(roster_path)):
        roster_result = run_process([str(options.godot), "--headless", "--path", str(options.project),
                                    "--script", "res://tools/ai_probe_153.gd", "--", "--roster=" + roster_path.as_posix()],
                                   out / "logs/roster.log", out / "_profiles/roster", min(120, options.timeout), options.project)
        if roster_result["status"] != "complete" or not roster_path.exists():
            manifest["roster"] = roster_result
            write_json(manifest_path, manifest)
            return 1
        roster_result["sha256"] = sha256(roster_path)
        manifest["roster"] = roster_result
        write_json(manifest_path, manifest)
    pending = [task for task in tasks if not reusable(manifest["results"].get(task["name"], {}), task, out)]
    print(f"TELEMETRY suite={options.suite} games={sum(len(t['indices']) for t in tasks)} pending={len(pending)}/{len(tasks)} jobs={options.jobs}", flush=True)
    pool = ThreadPoolExecutor(max_workers=options.jobs)
    try:
        futures = {pool.submit(execute_task, task, options, out, manifest["results"].get(task["name"], {})): task for task in pending}
        for future in as_completed(futures):
            task = futures[future]
            try:
                result = future.result()
            except Exception as exc:
                result = {"status": "failed", "exception": repr(exc)}
            manifest["results"][task["name"]] = result
            write_json(manifest_path, manifest)
            print(f"{result['status'].upper()} {task['name']} battles={result.get('battles', 0)} wall={result.get('wall_seconds', 0)}", flush=True)
    except KeyboardInterrupt:
        for error in stop_owned_processes():
            print("PROCESS_CLEANUP_ERROR " + error, file=sys.stderr)
        print("Interrupted; only this runner's owned PIDs stopped. Completed shards remain resumable.", flush=True)
        return 130
    finally:
        pool.shutdown(wait=True, cancel_futures=True)
    manifest["complete"] = all(reusable(manifest["results"].get(t["name"], {}), t, out) for t in tasks)
    manifest["source_unchanged"] = source_fingerprint(options.project)["sha256"] == fingerprint["sha256"]
    manifest["complete"] = manifest["complete"] and manifest["source_unchanged"]
    if options.suite == "balance" and manifest["complete"]:
        appearances = {}
        for task in tasks:
            if task["group"]["mode"] != "deathmatch":
                for row in validate_rows(out / (task["name"] + ".jsonl"), task):
                    for hero in row["comp"]:
                        appearances[hero] = appearances.get(hero, 0) + 1
        roster = json.loads(roster_path.read_text(encoding="utf-8"))
        manifest["team_appearances"] = {h["id"]: appearances.get(h["id"], 0) for h in roster}
        manifest["balance_sample_gate"] = all(n >= 200 for n in manifest["team_appearances"].values())
    write_json(manifest_path, manifest)
    print("TELEMETRY_DONE " + str(manifest["complete"]), flush=True)
    return 0 if manifest["complete"] and manifest.get("balance_sample_gate", True) else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, KeyError) as exc:
        print("TELEMETRY_ERROR " + str(exc), file=sys.stderr)
        raise SystemExit(2)
