"""Fixed-seed, roster-driven C6 training/holdout cases; no Godot invocation."""
from __future__ import annotations

import argparse
from itertools import combinations
from pathlib import Path
import random

try:
    from .common import digest, read_json, require, write_json
except ImportError:
    from common import digest, read_json, require, write_json

ELIMINATION = ["classic", "ruined_gate", "thorn_circuit", "furnace_basin", "wind_temple", "dimensional_lattice",
               "crossroads", "moon_garden", "twin_foundry", "gale_corridor", "rift_harbor", "bastion_ring"]
CONTROL = ["control_crossroads", "control_citadel", "control_waterway"]
DUEL_ARENAS = ["classic", "ruined_gate", "thorn_circuit", "furnace_basin", "moon_garden", "bastion_ring"]
SEED = 200601


def roster_ids(roster):
    require(isinstance(roster, list) and all(isinstance(row, dict) and isinstance(row.get("id"), str)
            and row["id"] and "|" not in row["id"] for row in roster), "Malformed roster IDs")
    ids = sorted(row["id"] for row in roster)
    require(len(ids) >= 10 and len(set(ids)) == len(ids), "Roster must contain distinct IDs and support 5v5")
    return ids


def generate(roster, seed=SEED):
    ids = roster_ids(roster)
    rng = random.Random(seed)
    cases = []
    pairs = list(combinations(ids, 2))
    for arena_index, arena in enumerate(DUEL_ARENAS):
        for pair_index, (a, b) in enumerate(pairs):
            for side in (0, 1):
                blue, red = ([a], [b]) if side == 0 else ([b], [a])
                cases.append({"id": f"duel_{arena_index:02d}_{pair_index:04d}_{side}", "kind": "duel",
                    "arena_id": arena, "ruleset": "elimination", "blue": blue, "red": red,
                    "seed": seed * 100 + arena_index * 10000 + pair_index * 17,
                    "max_time": 240.0})
    map_index = {3: 0, 5: 0}
    for k in range(1500):
        size = 5 if k % 3 == 0 else 3
        pool = ids.copy()
        rng.shuffle(pool)
        arena = ELIMINATION[map_index[size] % len(ELIMINATION)]
        map_index[size] += 1
        cases.append({"id": f"team_elim_{k:04d}", "kind": "team", "arena_id": arena,
            "ruleset": "elimination", "blue": pool[:size], "red": pool[size:size * 2],
            "seed": seed * 100 + 1000000 + k * 17, "max_time": 150.0})
    for k in range(300):
        pool = ids.copy()
        rng.shuffle(pool)
        cases.append({"id": f"team_control_{k:04d}", "kind": "team", "arena_id": CONTROL[k % len(CONTROL)],
            "ruleset": "control", "blue": pool[:5], "red": pool[5:10],
            "seed": seed * 100 + 2000000 + k * 17, "max_time": 480.0})
    for index, case in enumerate(cases):
        case["index"] = index
    return cases


def holdout(roster, seed=SEED, count=200):
    ids = roster_ids(roster)
    pairs = list(combinations(ids, 2))
    rng = random.Random(seed + 700001)
    rng.shuffle(pairs)
    cases = []
    for k in range(count):
        a, b = pairs[k % len(pairs)]
        blue, red = ([a], [b]) if k % 2 == 0 else ([b], [a])
        cases.append({"id": f"holdout_{k:04d}", "kind": "duel", "index": k,
            "arena_id": DUEL_ARENAS[k % len(DUEL_ARENAS)], "ruleset": "elimination",
            "blue": blue, "red": red, "seed": seed * 100 + 10000000 + k * 17, "max_time": 240.0})
    return cases


def determinism_sample(cases):
    # One in every twenty includes index 0; this is exactly ceil(5% * N).
    return [case for index, case in enumerate(cases) if index % 20 == 0]


def manifest(roster, cases, seed=SEED):
    return {"schema": 1, "seed": seed, "roster": roster_ids(roster), "roster_sha": digest(roster),
            "cases_sha": digest(cases), "games": len(cases), "duel_arenas": DUEL_ARENAS,
            "duels": sum(case["kind"] == "duel" for case in cases),
            "team_elimination": sum(case["kind"] == "team" and case["ruleset"] == "elimination" for case in cases),
            "team_control": sum(case["ruleset"] == "control" for case in cases),
            "cold_sample_ids": [case["id"] for case in determinism_sample(cases)]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("roster", type=Path)
    parser.add_argument("out", type=Path)
    parser.add_argument("--seed", type=int, default=SEED)
    parser.add_argument("--shards", type=int, default=6)
    args = parser.parse_args()
    require(1 <= args.shards <= 6, "Shards must be 1..6")
    roster = read_json(args.roster)
    cases = generate(roster, args.seed)
    write_json(args.out / "cases.json", cases)
    write_json(args.out / "cases_manifest.json", manifest(roster, cases, args.seed))
    write_json(args.out / "holdout_cases.json", holdout(roster, args.seed))
    for shard in range(args.shards):
        write_json(args.out / f"shard_{shard}.json", [case for case in cases if case["index"] % args.shards == shard])
    print(f"Generated {len(cases)} training cases; {len(determinism_sample(cases))} cold samples; 200 holdout")


if __name__ == "__main__":
    main()
