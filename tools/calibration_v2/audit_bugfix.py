"""Bounded paired 22-hero draft audit before the calibration-only patch."""
from __future__ import annotations

import argparse
from pathlib import Path
import uuid

try:
    from .common import GODOT, ROOT, read_json, require, run_godot, sha, write_json
    from .run_calibration import safe_output
except ImportError:
    from common import GODOT, ROOT, read_json, require, run_godot, sha, write_json
    from run_calibration import safe_output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--godot", type=Path, default=GODOT)
    parser.add_argument("--before", type=Path, required=True)
    parser.add_argument("--before-search", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    folder = safe_output(args.root, args.out)
    folder.mkdir(parents=True, exist_ok=True)
    attempt = folder / uuid.uuid4().hex
    attempt.mkdir()
    output = attempt / "draft_bugfix_v2.json"
    run_godot(args.godot, args.root, ["--script", str(Path(__file__).with_suffix(".gd").with_name("draft_bugfix_audit.gd")), "--",
        "--before=" + args.before.resolve().as_posix(), "--before-search=" + args.before_search.resolve().as_posix(),
        "--out=" + output.as_posix()], attempt / "draft_bugfix.log")
    report = read_json(output)
    require(report.get("status") == "PASS" and report.get("passed") == 72 and report.get("failed") == []
            and len(report.get("rows", [])) == 72 and all(row.get("same") is True for row in report["rows"]), "Paired audit is incomplete or failed")
    require(report.get("roster_count") == 22 and report.get("before_sha") == sha(args.before)
            and report.get("before_search_sha") == sha(args.before_search), "Paired audit did not use the requested original sources")
    require(report.get("after_sha") == sha(args.root / "scripts/ai/draft_director.gd")
            and report.get("after_search_sha") == sha(args.root / "scripts/ai/draft_search.gd"), "Draft sources changed during paired audit")
    write_json(folder / "summary.json", {"status": "PASS", "passed": 72, "report": str(output), "sha256": sha(output),
               "coverage": "22 heroes; both rulesets; sizes 1/3/5; budgets 1/21/22/23/800/4500; empty/occupied; rollout disabled"})
    print("DRAFT_BUGFIX_V2 PASS 72/72; " + str(output))


if __name__ == "__main__":
    main()
