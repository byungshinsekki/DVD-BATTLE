"""Run V1.5.2 core and rendered UI regressions in an isolated QA project.

Map geometry, control strategy and AI audit suites have separate reports.
No tests touch the normal player or developer profile. Existing QA files are
updated without deleting unrelated directories. Run from any working directory.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
QA = ROOT.parent / "DVD_BATTLE_1.5.2_QA"
REPORTS = ROOT / "reports/regression_152"
GODOT = ROOT.parent / "DVD_BATTLE_1.2.1_RECOVERY_WORK/tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe"
SCRIPTS = ["mechanics_122", "skill_preview_14", "preview_isolation_14", "deathmatch_15", "codex_data_151"]
SCENES = ["developer_152", "codex_ui_151", "deathmatch_ui_15", "preview_ui_14", "control_ui_13"]


def hashes():
    return {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
            for folder in ("scripts", "tests") for p in sorted((ROOT / folder).rglob("*.gd"))}


def run(args, name, timeout=600):
    start = time.monotonic()
    log_path = REPORTS / (name + ".log")
    with log_path.open("w", encoding="utf-8") as log:
        process = subprocess.run([str(a) for a in args], stdout=log, stderr=subprocess.STDOUT,
                                 creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0, timeout=timeout)
    content = log_path.read_text(encoding="utf-8", errors="replace")
    errors = re.findall(r"(?m)^.*(?:SCRIPT ERROR|ERROR:).*$", content)
    result = {"status": "PASS" if process.returncode == 0 and not errors else "FAIL",
              "exit": process.returncode, "seconds": round(time.monotonic() - start, 3), "errors": errors}
    print(name, json.dumps(result, ensure_ascii=False), flush=True)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--only", nargs="*", default=None)
    args = parser.parse_args()
    REPORTS.mkdir(parents=True, exist_ok=True)
    (REPORTS / ".gdignore").write_text("", encoding="utf-8")
    QA.mkdir(exist_ok=True)
    for folder in ("scripts", "scenes", "shaders", "assets", "tests"):
        shutil.copytree(ROOT / folder, QA / folder, dirs_exist_ok=True)
    for name in ("project.godot", "icon.svg", "icon.ico"):
        shutil.copy2(ROOT / name, QA / name)
    project = QA / "project.godot"
    project.write_text(project.read_text(encoding="utf-8").replace("DVD_BATTLE_V152_DEVELOPER", "DVD_BATTLE_V152_QA"), encoding="utf-8")
    (QA / "reports").mkdir(exist_ok=True)
    before = hashes()
    results = {"import": run([GODOT, "--headless", "--path", QA, "--editor", "--quit"], "import")}
    for name in SCRIPTS + SCENES:
        if args.only is not None and name not in args.only:
            continue
        options = [GODOT, "--path", QA]
        if name in SCRIPTS:
            options += ["--headless", "--script", "res://tests/" + name + ".gd"]
        else:
            options += ["res://tests/" + name + ".tscn"]
        options += ["--", "--report=" + str(REPORTS / (name + ".json")),
                    "--ui-report=" + str(REPORTS / (name + ".json")), "--qa-dir=" + str(REPORTS)]
        results[name] = run(options, name)
        generated = QA / "reports" / (name + ".json")
        if generated.exists() and not (REPORTS / (name + ".json")).exists():
            shutil.copy2(generated, REPORTS / generated.name)
    report = {"version": "1.5.2", "status": "PASS" if all(r["status"] == "PASS" for r in results.values()) else "FAIL",
              "suites": results, "source_hashes": before, "sources_unchanged_during_run": hashes() == before}
    (REPORTS / "summary.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    raise SystemExit(0 if report["status"] == "PASS" else 1)


if __name__ == "__main__":
    main()
