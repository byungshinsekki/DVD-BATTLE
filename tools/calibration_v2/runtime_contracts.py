"""Fail-closed provenance and complete first-pick accounting; no engine launch."""
from __future__ import annotations

from collections import Counter
from pathlib import Path
import sys

try:
    from . import calib_cases
    from .common import digest, read_json, require, sha, write_json
except ImportError:
    import calib_cases
    from common import digest, read_json, require, sha, write_json

EXTERNAL_TOOLS = ("tools/balance_runner.gd", "tools/data_fingerprint_151.gd")
ARENAS = calib_cases.ELIMINATION + calib_cases.CONTROL


def tool_hashes(project):
    own = Path(__file__).parent
    hashes = {"tools/calibration_v2/" + path.name: sha(path) for path in sorted(own.iterdir())
              if path.suffix in (".py", ".gd")}
    hashes.update({relative: sha(Path(project) / relative) for relative in EXTERNAL_TOOLS})
    return hashes


def binary_paths(godot):
    paths = {"godot_console": Path(godot).resolve(), "python": Path(sys.executable).resolve()}
    gui = paths["godot_console"].with_name(paths["godot_console"].name.replace("_console.exe", ".exe"))
    if gui.is_file() and gui != paths["godot_console"]:
        paths["godot_gui"] = gui
    return paths


def binary_hashes(godot):
    return {name: {"path": str(path), "sha256": sha(path)} for name, path in binary_paths(godot).items()}


class BinaryGuard:
    """Hash every binary at startup/final; stat changes trigger a rehash per chunk.

    Re-reading a large Godot binary for each of 5,000 launches adds terabytes of
    unnecessary I/O. Metadata is only an in-run invalidation cache, never resume
    evidence: a new invocation always verifies complete SHA-256 values again.
    """
    def __init__(self, expected):
        self.expected = expected
        self.observed = {}
        self.check(full=True)

    def check(self, *, full=False):
        for name, entry in self.expected.items():
            path = Path(entry["path"])
            info = path.stat()
            identity = (info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns, info.st_ctime_ns)
            if full or self.observed.get(name) != identity:
                require(sha(path) == entry["sha256"], f"Runtime binary changed: {name}")
                self.observed[name] = identity


def save_receipt(folder, label, cases, identity):
    folder = Path(folder)
    names = {"request": "cases/" + label + ".json", "result": "results/" + label + ".jsonl",
             "log": "logs/" + label + ".log", "process": "logs/" + label + ".process.json"}
    record = {"schema": 1, "status": "PASS", "identity": identity, "cases_sha": digest(cases),
              "case_ids": [case["id"] for case in cases],
              "files": {kind: {"path": relative, "sha256": sha(folder / relative)} for kind, relative in names.items()}}
    write_json(folder / "receipts" / (label + ".json"), record)


def verified_result_paths(folder, cases, identity):
    """Only a complete, unchanged, successful process can supply resume rows.

    Unreceipted files remain untouched for diagnosis and are ignored. A receipt
    that exists but is malformed or no longer matches its bytes is a hard error.
    """
    folder = Path(folder)
    expected = {case["id"]: case for case in cases}
    used = set()
    results = []
    for path in sorted((folder / "receipts").glob("*.json")):
        record = read_json(path)
        require(record.get("schema") == 1 and record.get("status") == "PASS" and record.get("identity") == identity,
                f"Resume receipt belongs to another run or is invalid: {path}")
        case_ids = record.get("case_ids", [])
        require(isinstance(case_ids, list) and case_ids and len(set(case_ids)) == len(case_ids)
                and all(case_id in expected for case_id in case_ids), f"Invalid receipt cases: {path}")
        require(not used.intersection(case_ids), f"Duplicate receipt cases: {path}")
        selected = [expected[case_id] for case_id in case_ids]
        require(record.get("cases_sha") == digest(selected), f"Receipt case digest differs: {path}")
        names = {"request": "cases/" + path.stem + ".json", "result": "results/" + path.stem + ".jsonl",
                 "log": "logs/" + path.stem + ".log", "process": "logs/" + path.stem + ".process.json"}
        require(set(record.get("files", {})) == set(names), f"Incomplete receipt evidence: {path}")
        for kind, relative in names.items():
            entry = record["files"][kind]
            target = folder / relative
            require(entry.get("path") == relative and target.is_file() and sha(target) == entry.get("sha256"),
                    f"Receipt evidence differs: {path}: {kind}")
        process = read_json(folder / names["process"])
        require(process.get("status") == "PASS" and type(process.get("exit_code")) is int
                and process["exit_code"] == 0 and process.get("timeout") is False and process.get("errors") == [],
                f"Receipt does not describe a successful process: {path}")
        require(read_json(folder / names["request"]) == selected, f"Receipt request differs: {path}")
        used.update(case_ids)
        results.append(folder / names["result"])
    return results


def first_pick_report(reports, roster):
    expected_roster = calib_cases.roster_ids(roster)
    expected = {(size, seed, arena) for size in (1, 3) for seed in (1, 2, 3) for arena in ARENAS}
    rows = []
    observed = set()
    for report in reports:
        require(report.get("status") == "MEASURED" and report.get("scope") == "single_pick", "Expected one complete first-pick measurement")
        require(sorted(report.get("roster", [])) == expected_roster, "First-pick roster changed")
        require(isinstance(report.get("rows"), list) and len(report["rows"]) == 1, "Missing first-pick row")
        row = report["rows"][0]
        key = (row.get("team_size"), row.get("seed"), row.get("arena_id"))
        require(key in expected and key not in observed and row.get("id") in expected_roster, "Duplicate or invalid first-pick case")
        require(row.get("score_basis") in ("search", "search_and_engine")
                and isinstance(row.get("search"), dict), "Missing first-pick decision evidence")
        observed.add(key)
        rows.append(row)
    require(observed == expected, f"Incomplete first-pick audit: {len(observed)}/90")
    groups = []
    for size in (1, 3):
        for seed in (1, 2, 3):
            counts = dict(sorted(Counter(row["id"] for row in rows if row["team_size"] == size and row["seed"] == seed).items()))
            wolf, most = counts.get("werewolf", 0), max(counts.values())
            groups.append({"team_size": size, "seed": seed, "counts": counts, "maps": 15, "werewolf": wolf,
                           "maximum_hero": most, "status": "PASS" if wolf <= 3 and most <= 5 else "FAIL"})
    return {"status": "PASS" if all(group["status"] == "PASS" for group in groups) else "FAIL",
            "groups": groups, "rows": sorted(rows, key=lambda row: (row["team_size"], row["seed"], row["arena_id"])),
            "criteria": {"werewolf_max_per_15": 3, "any_hero_max_per_15": 5}}
