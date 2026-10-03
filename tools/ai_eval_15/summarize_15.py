"""Summarise the V1.5 conquest AI evaluation (reports/ai_eval_15).

Reads the raw outputs of conquest_probe_15.gd, assignment_probe_15.gd,
wall_band_15.gd and h2h_15.gd and writes reports/ai_eval_15/summary_15.json.
"""
import collections
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EVAL = ROOT / "reports" / "ai_eval_15"
KINDS = ("tactician14", "tactician")


def rows(path):
    if not path.exists():
        return []
    return [json.loads(line) for line in path.read_text(encoding="utf-8-sig").splitlines() if line.strip()]


def pct(a, b):
    return round(100.0 * a / b, 1) if b else None


def conquest_probe():
    out = {}
    for kind in KINDS:
        data = rows(EVAL / f"conquest_probe_{kind}.jsonl")
        total = collections.Counter()
        for row in data:
            total.update(row["stats"])
        out[kind] = {"matches": len(data), "totals": dict(total),
                     "turret_spawnside_pct": pct(total["turret_spawnside"], total["turrets"]),
                     "turret_no_damage_pct": pct(total["turret_no_damage"], total["turrets"]),
                     "turret_far_obj_pct": pct(total["turret_far_obj"], total["turrets"]),
                     "casts_no_enemy_pct": pct(total["casts_no_enemy"], total["casts"]),
                     "deaths_outnumbered_pct": pct(total["deaths_outnumbered"], total["deaths"]),
                     "on_point_pct": pct(total["on_point_samples"], total["alive_samples"]),
                     "matches_detail": [{k: row[k] for k in ("match", "arena", "winner", "t", "scores")} for row in data]}
    return out


def assignment_probe():
    out = {}
    for kind in KINDS:
        data = rows(EVAL / f"assignment_probe_{kind}.jsonl")
        flips = sum(sum(r["flips"]) for r in data)
        far = sum(sum(r["far_flips"]) for r in data)
        heal = sum(sum(r["heal_trip_s"]) for r in data)
        on_point = sum(sum(r["on_point_s"]) for r in data)
        alive = sum(sum(r["alive_s"]) for r in data)
        out[kind] = {"matches": len(data), "flips_per_team_match": round(flips / (2 * len(data)), 1) if data else None,
                     "far_flips_per_team_match": round(far / (2 * len(data)), 1) if data else None,
                     "heal_trip_pct": pct(heal, alive), "on_point_pct": pct(on_point, alive)}
    return out


def wall_band():
    out = {}
    for mode in ("legacy", "current"):
        data = rows(EVAL / f"wall_band_{mode}.jsonl")
        by = collections.defaultdict(lambda: {"cases": 0, "band_ticks": 0, "frozen_ticks": 0})
        for row in data:
            entry = by[row["ruleset"]]
            entry["cases"] += 1
            entry["band_ticks"] += row["band_ticks"]
            entry["frozen_ticks"] += row["frozen_ticks"]
        out[mode] = dict(by)
    return out


def binomial_two_sided(k, n):
    if n == 0:
        return None
    probs = [math.comb(n, i) / 2 ** n for i in range(n + 1)]
    return round(min(1.0, sum(p for p in probs if p <= probs[k] + 1e-12)), 3)


def head_to_head():
    specs_path = EVAL / "h2h_specs_15.json"
    if not specs_path.exists():
        return {}
    specs = {s["id"]: s for s in json.loads(specs_path.read_text(encoding="utf-8-sig"))}
    data = rows(EVAL / "h2h_results_15.jsonl")
    outcome = collections.Counter()
    by_size = collections.defaultdict(collections.Counter)
    by_arena = collections.defaultdict(collections.Counter)
    pairs = collections.defaultdict(list)
    margins = []
    for row in data:
        spec = specs[row["id"]]
        a_side = spec["a_side"]
        result = "draw" if row["winner"] == 2 else ("win" if row["winner"] == a_side else "loss")
        outcome[result] += 1
        by_size[f"{row['size']}v{row['size']}"][result] += 1
        by_arena[row["arena"]][result] += 1
        pairs[row["id"].split("_")[0]].append(result)
        if "scores" in row:
            margins.append(row["scores"][a_side] - row["scores"][1 - a_side])
    pair_kinds = collections.Counter("both_won" if p == ["win", "win"] else ("both_lost" if p == ["loss", "loss"] else "split")
                                     for p in (sorted(v, reverse=True) for v in pairs.values()) if len(p) == 2)
    decisive = outcome["win"] + outcome["loss"]
    a_ai = next(iter(specs.values()))["config"]["blue_ai"]
    b_ai = next(iter(specs.values()))["config"]["red_ai"]
    return {"a_ai": a_ai, "b_ai": b_ai, "matches": len(data), "compositions": len(pairs), "a_outcomes": dict(outcome),
            "by_size": {k: dict(v) for k, v in sorted(by_size.items())}, "by_arena": {k: dict(v) for k, v in sorted(by_arena.items())},
            "mirrored_pairs": dict(pair_kinds), "mean_score_margin_a_minus_b": round(sum(margins) / len(margins), 1) if margins else None,
            "sign_test_p_two_sided": binomial_two_sided(outcome["win"], decisive)}


def main():
    summary = {"conquest_probe": conquest_probe(), "assignment_probe": assignment_probe(), "wall_band": wall_band(), "head_to_head": head_to_head(),
               "notes": "tactician = V1.5 AI, tactician14 = V1.4 AI kept for comparison. conquest_probe: mirrored 5v5 with an engineer on both teams; "
                        "assignment_probe: 3 mirrored 5v5 compositions; wall_band: reference battles, V1.4 (legacy) vs V1.5 wall handling; "
                        "head_to_head: each composition played on both sides with the same seed."}
    (EVAL / "summary_15.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
