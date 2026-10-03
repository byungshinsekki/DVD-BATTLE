"""Validate complete balance results and generate, never hand-edit, calibration."""
from __future__ import annotations

import argparse
from collections import defaultdict
import json
from pathlib import Path
import re

try:
    from .common import read_json, require, write_json, writable_path
    from .calib_cases import roster_ids, DUEL_ARENAS, ELIMINATION, CONTROL
except ImportError:
    from common import read_json, require, write_json, writable_path
    from calib_cases import roster_ids, DUEL_ARENAS, ELIMINATION, CONTROL


MAP_PRIOR_CAP = 0.12
MAP_DUEL_SHRINK = 20.0
MAP_TEAM_SHRINK = 60.0
MAP_PRIOR_SEMANTICS = "clamp((map_mean-other_maps_mean)*n/(n+k), -cap, cap); additive residual; absent mode/map means zero"


def recover_truncated_tails(folder):
    """Preserve crash originals, keep only complete JSON lines for resume."""
    import hashlib
    for path in sorted(Path(folder).glob("*.jsonl")):
        raw = path.read_bytes()
        if not raw or raw.endswith(b"\n"):
            continue
        lines = raw.splitlines(keepends=True)
        try:
            json.loads(lines[-1])
        except (json.JSONDecodeError, UnicodeDecodeError):
            # Never repair corruption in an earlier line.
            for line in lines[:-1]:
                if line.strip(): json.loads(line)
            backup = path.with_name(path.name + ".incomplete." + hashlib.sha256(raw).hexdigest()[:12])
            if not backup.exists(): backup.write_bytes(raw)
            path.write_bytes(b"".join(lines[:-1]))


def read_results(paths, cases, *, allow_incomplete=False):
    expected = {case["id"]: case for case in cases}
    require(len(expected) == len(cases), "Duplicate expected case IDs")
    rows = {}
    for path in sorted(map(Path, paths)):
        lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
        for index, line in enumerate(lines):
            if not line.strip():
                continue
            try:
                row = json.loads(line)
            except json.JSONDecodeError:
                # A killed writer may leave only its final row truncated.
                if allow_incomplete and index == len(lines) - 1 and not line.endswith("\n"):
                    continue
                raise RuntimeError(f"Malformed result row: {path}:{index + 1}")
            case_id = str(row.get("case_id", ""))
            require(case_id in expected, f"Unexpected case {case_id} in {path}")
            require(case_id not in rows, f"Duplicate result for {case_id}")
            require(row.get("config") == expected[case_id], f"Config differs for {case_id}")
            require(not row.get("invariant_error"), f"Invariant error in {case_id}: {row.get('invariant_error')}")
            require(type(row.get("winner")) is int and row["winner"] in (0, 1, 2), f"Invalid winner in {case_id}")
            require(re.fullmatch(r"[0-9a-f]{64}", str(row.get("signature", ""))) is not None,
                    f"Missing/invalid signature in {case_id}")
            rows[case_id] = row
    if not allow_incomplete:
        missing = sorted(set(expected) - set(rows))
        require(not missing, f"Missing {len(missing)} results: {missing[:8]}")
    return rows


def aggregate(roster, cases, results):
    ids = roster_ids(roster)
    allowed = set(ids)
    duel = defaultdict(lambda: [0.0, 0])
    teams = {"elimination": defaultdict(lambda: [0.0, 0]), "control": defaultdict(lambda: [0.0, 0])}
    map_duels = {arena: defaultdict(lambda: [0.0, 0]) for arena in DUEL_ARENAS}
    map_teams = {mode: {arena: defaultdict(lambda: [0.0, 0]) for arena in arenas}
                 for mode, arenas in (("elimination", ELIMINATION), ("control", CONTROL))}
    require(set(results) == {case["id"] for case in cases}, "Aggregation requires exactly all training results")
    for case in cases:
        row = results[case["id"]]
        require(row.get("config") == case and not row.get("invariant_error"), f"Invalid result: {case['id']}")
        require(set(case["blue"] + case["red"]) <= allowed, "Unknown hero in training case")
        winner = int(row["winner"])
        score = 1.0 if winner == 0 else (-1.0 if winner == 1 else 0.0)
        if case["kind"] == "duel":
            require(case["ruleset"] == "elimination" and len(case["blue"]) == len(case["red"]) == 1, "Invalid duel")
            a, b = case["blue"][0], case["red"][0]
            key = "|".join(sorted((a, b)))
            duel[key][0] += score * (1 if a < b else -1)
            duel[key][1] += 1
            require(case["arena_id"] in map_duels, "Unknown duel training map")
            local = map_duels[case["arena_id"]][key]
            local[0] += score * (1 if a < b else -1)
            local[1] += 1
        else:
            require(case["kind"] == "team" and case["ruleset"] in teams, "Invalid training kind/ruleset")
            table = teams[case["ruleset"]]
            require(case["arena_id"] in map_teams[case["ruleset"]], "Unknown team training map")
            local_table = map_teams[case["ruleset"]][case["arena_id"]]
            for side, heroes in enumerate((case["blue"], case["red"])):
                for hero in heroes:
                    table[hero][0] += score * (1 if side == 0 else -1)
                    table[hero][1] += 1
                    local_table[hero][0] += score * (1 if side == 0 else -1)
                    local_table[hero][1] += 1
    require(len(duel) == len(ids) * (len(ids) - 1) // 2, "Not every duel pair was measured")
    require(all(value[1] == 12 for value in duel.values()), "Each duel pair requires six maps and both sides")
    require(all(set(table) == allowed for table in teams.values()), "Team samples do not cover entire roster")
    require(all(set(table) == set(duel) and all(value[1] == 2 for value in table.values())
                for table in map_duels.values()), "Each map must contain both sides of every duel pair")
    require(all(set(table) == allowed for maps in map_teams.values() for table in maps.values()),
            "Every team map must cover the entire roster")
    return {"games": len(cases), "roster": ids,
            "duel": {key: round(total / (n + 4.0), 8) for key, (total, n) in sorted(duel.items())},
            "duel_counts": {key: n for key, (_, n) in sorted(duel.items())},
            **{f"team_{mode}": {hero: round(max(-0.3, min(0.3, total / (n + 20.0))), 8)
                for hero, (total, n) in sorted(table.items())} for mode, table in teams.items()},
            **{f"team_{mode}_counts": {hero: n for hero, (_, n) in sorted(table.items())} for mode, table in teams.items()},
            "map_prior_semantics": MAP_PRIOR_SEMANTICS,
            "map_prior_cap": MAP_PRIOR_CAP, "map_duel_shrink": MAP_DUEL_SHRINK, "map_team_shrink": MAP_TEAM_SHRINK,
            "map_duel": map_residuals(map_duels, duel, MAP_DUEL_SHRINK),
            "map_duel_counts": map_counts(map_duels),
            **{f"map_team_{mode}": map_residuals(maps, teams[mode], MAP_TEAM_SHRINK)
               for mode, maps in map_teams.items()},
            **{f"map_team_{mode}_counts": map_counts(maps) for mode, maps in map_teams.items()}}


def map_residuals(local_maps, overall, shrink):
    """Use disjoint other-map outcomes as the reference; never reuse local rows there.

    Counts describe appearances, not independent trials. Mirrored duels share a
    seed; the small n/(n+20) weight and cap preserve that limited evidential role.
    These are contextual residuals, not predicted probabilities or win rates.
    """
    output = {}
    for arena, table in sorted(local_maps.items()):
        values = {}
        for key, (total, n) in sorted(table.items()):
            all_total, all_n = overall[key]
            other_n = all_n - n
            require(n > 0 and other_n > 0 and shrink > 0, "A map residual requires local and other-map samples")
            contrast = total / n - (all_total - total) / other_n
            values[key] = round(max(-MAP_PRIOR_CAP, min(MAP_PRIOR_CAP, contrast * n / (n + shrink))), 8)
        output[arena] = values
    return output


def map_counts(local_maps):
    return {arena: {key: n for key, (_, n) in sorted(table.items())}
            for arena, table in sorted(local_maps.items())}


def gd_dict(table):
    return "{\n" + "".join(f"\t{json.dumps(key)}: {value:.8f},\n" for key, value in sorted(table.items())) + "}"


def gd_map_dict(maps, *, counts=False):
    lines = ["{"]
    for arena, table in sorted(maps.items()):
        lines.append(f"\t{json.dumps(arena)}: {{")
        for key, value in sorted(table.items()):
            literal = str(value) if counts else f"{value:.8f}"
            lines.append(f"\t\t{json.dumps(key)}: {literal},")
        lines.append("\t},")
    return "\n".join(lines + ["}"])


def build_text(data, stamp):
    require(stamp.get("platform") == "windows", "Calibration must be generated on Windows")
    require(re.fullmatch(r"[0-9a-f]{64}", stamp.get("sha256", "")) is not None, "Invalid SIM_SHA")
    lines = ["class_name DraftCalibration", "", "# Generated by tools/calibration_v2/calib_build.py; do not edit.",
             "# Measured tactician vs tactician. This table changes draft estimates only.",
             'const ENGINE := "GD-2.0"', f"const GAMES := {data['games']}",
             f"const SIM_SHA := {json.dumps(stamp['sha256'])}", 'const PLATFORM := "windows"',
             f"const DATA_FINGERPRINT := {json.dumps(stamp['data_fingerprint'])}",
             f"const ROSTER := {json.dumps(data['roster'])}",
             "const DUEL := " + gd_dict(data["duel"]),
             "const TEAM_ELIM := " + gd_dict(data["team_elimination"]),
             "const TEAM_CONTROL := " + gd_dict(data["team_control"]),
             "const TEAM := TEAM_ELIM", "",
             "# Map entries are additive residuals against the same-mode other maps.",
             "# Counts are appearances, not independent trials; mirrored duels share a seed.",
             "# Unmeasured modes/maps have no entry and must contribute zero.",
             "const MAP_PRIOR_FORMAT := 1",
             "const MAP_PRIOR_SEMANTICS := " + json.dumps(data["map_prior_semantics"]),
             f"const MAP_PRIOR_CAP := {data['map_prior_cap']:.8f}",
             f"const MAP_DUEL_SHRINK := {data['map_duel_shrink']:.8f}",
             f"const MAP_TEAM_SHRINK := {data['map_team_shrink']:.8f}",
             "const MAP_DUEL := " + gd_map_dict(data["map_duel"]),
             "const MAP_DUEL_COUNTS := " + gd_map_dict(data["map_duel_counts"], counts=True),
             "const MAP_TEAM_ELIM := " + gd_map_dict(data["map_team_elimination"]),
             "const MAP_TEAM_ELIM_COUNTS := " + gd_map_dict(data["map_team_elimination_counts"], counts=True),
             "const MAP_TEAM_CONTROL := " + gd_map_dict(data["map_team_control"]),
             "const MAP_TEAM_CONTROL_COUNTS := " + gd_map_dict(data["map_team_control_counts"], counts=True), ""]
    return "\n".join(lines)


def holdout_audit(table, cases, rows):
    require(len(cases) == 200 and set(rows) == {case["id"] for case in cases}, "Exactly 200 holdout cases are required")
    details = []
    for case in cases:
        a, b = case["blue"][0], case["red"][0]
        estimate = table["|".join(sorted((a, b)))] * (1 if a < b else -1)
        predicted = (estimate > 0) - (estimate < 0)
        winner = int(rows[case["id"]]["winner"])
        actual = 1 if winner == 0 else (-1 if winner == 1 else 0)
        details.append({"case_id": case["id"], "predicted_sign": predicted, "actual_sign": actual,
                        "match": predicted == actual, "estimate_blue": estimate})
    matches = sum(row["match"] for row in details)
    return {"status": "PASS" if matches / 200 >= 0.70 else "FAIL", "cases": 200, "matches": matches,
            "sign_agreement": matches / 200, "threshold": 0.70,
            "ties": "zero is a third sign; all 200 cases remain in the denominator",
            "predicted_zero": sum(row["predicted_sign"] == 0 for row in details),
            "actual_zero": sum(row["actual_sign"] == 0 for row in details), "rows": details}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--roster", required=True, type=Path)
    parser.add_argument("--cases", required=True, type=Path)
    parser.add_argument("--stamp", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("results", nargs="+", type=Path)
    args = parser.parse_args()
    args.output = writable_path(args.output)
    require(not any(re.match(r"DVD_BATTLE_1\.", part, re.IGNORECASE) for part in args.output.resolve().parts),
            "V1.x output paths are read-only")
    cases = read_json(args.cases)
    rows = read_results(args.results, cases)
    table = aggregate(read_json(args.roster), cases, rows)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(build_text(table, read_json(args.stamp)), encoding="utf-8", newline="\n")
    write_json(args.output.with_suffix(".summary.json"), table)
    print(f"CALIBRATION games={table['games']} pairs={len(table['duel'])} -> {args.output}")


if __name__ == "__main__":
    main()
