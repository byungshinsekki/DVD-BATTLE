"""Frozen input selection and independent draft/replay checks. Does not tune AI."""
import argparse
import collections
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPORTS = ROOT / "reports"


def read(name):
    return json.loads((REPORTS / name).read_text(encoding="utf-8-sig"))


def rows(name):
    return [json.loads(line) for line in (REPORTS / name).read_text(encoding="utf-8-sig").splitlines() if line.strip()]


def write(name, value):
    (REPORTS / name).write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding="utf-8")


def generate():
    cases = []
    for split in ("validation", "holdout"):
        for mode in ("elimination", "control"):
            for size in (1, 3, 5):
                for first in (0, 1):
                    arena = ("classic" if first == 0 else "ruined_gate") if mode == "elimination" else ("control_crossroads" if first == 0 else "control_citadel")
                    if split == "holdout":
                        arena = ("moon_garden" if first == 0 else "twin_foundry") if mode == "elimination" else ("control_citadel" if first == 0 else "control_crossroads")
                    cases.append(dict(id=f"{split}_{mode}_{size}_{first}", split=split,
                                      ruleset=mode, team_size=size, first=first, arena_id=arena,
                                      seed=(2875400 + size * 89 + first * 31) if split == "holdout" else (1401000 + size * 100 + first * 7)))
    for split in ("validation", "holdout"):
        write(f"draft_{split}_cases_14.json", [c for c in cases if c["split"] == split])
    previous = ROOT.parent / "DVD_BATTLE_1.3/reports"
    legacy = [json.loads(line) for line in (previous / "legacy_matches_13.jsonl").read_text(encoding="utf-8-sig").splitlines() if line.strip()]
    control = []
    for name in ("control_matches_0.jsonl", "control_matches_1.jsonl"):
        control.extend(json.loads(line) for line in (previous / name).read_text(encoding="utf-8-sig").splitlines() if line.strip())
    # Three representative control games plus every original arena, saved baseline signatures.
    selected = [next(r for r in control if r["case_id"] == key) for key in ("control_0_0_0", "control_1_1_0", "control_2_2_0")]
    baseline = legacy + selected
    write("regression_cases_14.json", [r["config"] for r in baseline])
    write("regression_baseline_13.json", [{"case_id": r["case_id"], "signature": r["signature"]} for r in baseline])
    print(json.dumps({"drafts": len(cases), "mirrored_matches": len(cases) * 2, "regression_matches": len(baseline)}))


def matches():
    for split in ("validation", "holdout"):
        drafts = rows(f"draft_{split}_14.jsonl")
        assert len(drafts) == 12 and all(r["valid"] for r in drafts)
        out = []
        for draft in drafts:
            cfg = draft["config"]
            for new_side in (0, 1):
                out.append(dict(id=f"{cfg['id']}_newside{new_side}", draft_id=cfg["id"],
                                new_side=new_side, split=split, ruleset=cfg["ruleset"], arena_id=cfg["arena_id"],
                                seed=cfg["seed"], max_time=480.0 if cfg["ruleset"] == "control" else 150.0,
                                blue=draft["new_team"] if new_side == 0 else draft["old_team"],
                                red=draft["old_team"] if new_side == 0 else draft["new_team"],
                                blue_ai="tactician", red_ai="tactician"))
        write(f"draft_{split}_match_cases_14.json", out)
    print("Prepared 48 full matches from 24 completed drafts")


def regression_check():
    baseline = {r["case_id"]: r["signature"] for r in read("regression_baseline_13.json")}
    current = rows("regression_matches_14.jsonl")
    comparisons = [{"case_id": r["case_id"], "equal": r["signature"] == baseline.get(r["case_id"]), "error": r["invariant_error"]} for r in current]
    characters = sorted({c for r in current for c in r["config"]["blue"] + r["config"]["red"]})
    status = "PASS" if len(comparisons) == 15 and all(r["equal"] and not r["error"] for r in comparisons) else "FAIL"
    result = {"status": status, "matches": len(comparisons), "characters": characters, "comparisons": comparisons}
    write("battle_regression_14.json", result)
    print(json.dumps(result, ensure_ascii=False, indent=2))
    if status != "PASS":
        raise SystemExit(1)


def check():
    failures = []
    drafts = rows("draft_validation_14.jsonl") + rows("draft_holdout_14.jsonl")
    games = rows("draft_validation_matches_14.jsonl") + rows("draft_holdout_matches_14.jsonl")
    if len(drafts) != 24 or len(games) != 48:
        failures.append("Incomplete draft benchmark")
    groups = collections.defaultdict(lambda: collections.Counter())
    pairs = collections.defaultdict(list)
    expected_matches = {case["id"]: case for split in ("validation", "holdout") for case in read(f"draft_{split}_match_cases_14.json")}
    for row in games:
        cfg = row["config"]
        if cfg != expected_matches.get(row["case_id"]):
            failures.append(f"Match inputs changed: {row['case_id']}")
        if row["invariant_error"]:
            failures.append(f"{row['case_id']}: {row['invariant_error']}")
        outcome = "draws" if row["winner"] == 2 else ("wins" if row["winner"] == cfg["new_side"] else "losses")
        for label in ("all", cfg["split"], cfg["ruleset"], f"{len(cfg['blue'])}v{len(cfg['red'])}", f"{cfg['split']}_{cfg['ruleset']}"):
            groups[label][outcome] += 1
            groups[label]["matches"] += 1
        pairs[cfg["draft_id"]].append(outcome)
    if len(pairs) != 24 or any(len(pair) != 2 for pair in pairs.values()):
        failures.append("Missing mirrored draft pair")
    timings = collections.defaultdict(list)
    picks = collections.Counter()
    expected_cases = {case["id"]: case for split in ("validation", "holdout") for case in read(f"draft_{split}_cases_14.json")}
    source_hashes = {name: hashlib.sha256((ROOT / "scripts/ai" / name).read_bytes()).hexdigest() for name in ("draft_director.gd", "draft_search.gd")}
    for draft in drafts:
        if draft["config"] != expected_cases.get(draft["id"]):
            failures.append(f"Draft inputs changed: {draft['id']}")
        if draft.get("source_sha256") != source_hashes:
            failures.append(f"Draft source changed since benchmark: {draft['id']}")
        if not draft["valid"] or len(set(draft["new_team"] + draft["old_team"])) != 2 * draft["config"]["team_size"]:
            failures.append(f"Illegal or incomplete draft: {draft['id']}")
        for pick in draft["picks"]:
            timings[pick["version"]].append(pick["wall_ms"])
            if pick["version"] == "1.4":
                picks[pick["id"]] += 1
                search = pick["decision"]["search"]
                if int(search["evals"]) > int(search["budget"]):
                    failures.append(f"Evaluation budget exceeded: {draft['id']}")
    previous = {r["case_id"]: r["signature"] for r in read("regression_baseline_13.json")}
    regression = rows("regression_matches_14.jsonl")
    comparisons = [{"case_id": r["case_id"], "equal": r["signature"] == previous.get(r["case_id"]), "error": r["invariant_error"]} for r in regression]
    if len(comparisons) != 15 or not all(r["equal"] and not r["error"] for r in comparisons):
        failures.append("V1.3 battle behavior regression")
    previous_ai = ROOT / "tests/baselines/draft_director_13.gd"
    result = {"status": "PASS" if not failures else "FAIL", "failures": failures,
              "drafts": len(drafts), "matches": len(games), "mirrored_pairs": dict(pairs),
              "outcomes_for_v14": {name: dict(counts) for name, counts in groups.items()},
              "pick_time_ms": {version: {"count": len(values), "mean": sum(values) / len(values), "max": max(values)} for version, values in timings.items()},
              "v14_pick_counts": dict(picks), "unchanged_battle_comparisons": comparisons,
              "legacy_draft_source_sha256": hashlib.sha256(previous_ai.read_bytes()).hexdigest(),
              "evaluated_sources_sha256": source_hashes,
              "method": "V1.4 and frozen V1.3 alternate legal unique picks; both pick orders; each composition plays identical seed with swapped sides. Both teams use the same unchanged Tactician combat AI. Validation inputs retained; fresh holdout inputs fixed before horizon repair. Initial 48-game results archived in pre_completion_14. No character weights fitted to match outcomes.",
              "limitations": "Small deterministic sample with correlated mirror pairs; descriptive outcomes, not a general win-rate or statistical-strength guarantee. Holdout means no fitting to these results, not unseen roster data."}
    write("release_comparison_14.json", result)
    print(json.dumps(result, ensure_ascii=False, indent=2))
    if failures:
        raise SystemExit(1)


parser = argparse.ArgumentParser()
parser.add_argument("command", choices=("generate", "matches", "regression", "check"))
args = parser.parse_args()
{"generate": generate, "matches": matches, "regression": regression_check, "check": check}[args.command]()
