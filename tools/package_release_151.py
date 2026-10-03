"""Verify the V1.5.1 evidence, write VALIDATION_1.5.1_KO.txt and the manifest, and package the release.

Run after tools/RUN_WIN151_A.bat, RUN_WIN151_V.bat and RUN_WIN151_B.bat (in that order):
    py tools/package_release_151.py
Port of package_release_15.py (kept unchanged as history). V1.5.1 is a UI release, so besides the
usual stage, suite and packaging checks this script proves that the simulation is unchanged:
  - the data fingerprint (tools/data_fingerprint_151.gd) of this tree equals the one of the shipped
    V1.5 source (DVD_BATTLE_1.5_SOURCE.zip),
  - the 12 legacy-wall elimination replays equal V1.4 and all 15 legacy/current replays equal V1.5,
  - the deathmatch and conquest suite metrics equal the V1.5 Windows reports stored in the V1.5 source zip.
Every number written to VALIDATION_1.5.1_KO.txt is read from the reports. The shipped V1.5 (and V1.4)
artefacts are only read: their hashes are checked before and after packaging, and every output path
is refused if it points at a V1.5 artefact.
"""
import datetime
import hashlib
import importlib.util
import json
import os
import re
import shutil
import struct
import sys
import zipfile
from pathlib import Path

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[1]
REPORTS = ROOT / "reports"
PARENT = ROOT.parent
VERSION = "GD-1.5.1"
FILE_VERSION = "1.5.1.0"
RELEASE = PARENT / "DVD_BATTLE_1.5.1_RELEASE"
FRESH = PARENT / "DVD_BATTLE_1.5.1_FRESH_IMPORT"
EXE = RELEASE / "DVD_BATTLE_1.5.1.exe"
WIN_ZIP = PARENT / "DVD_BATTLE_1.5.1_WINDOWS.zip"
SRC_ZIP = PARENT / "DVD_BATTLE_1.5.1_SOURCE.zip"
SHA_FILE = PARENT / "DVD_BATTLE_1.5.1_SHA256.txt"
WIN_PREFIX = "DVD_BATTLE_1.5.1_RELEASE/"
SRC_PREFIX = "DVD_BATTLE_1.5.1/"
VALIDATION = "VALIDATION_1.5.1_KO.txt"
CHANGELOG = "CHANGELOG_1.5.1_KO.txt"
UI_VISUAL = "reports/UI_VISUAL_1.5.1.txt"
MANIFEST = "release_manifest_151.json"
DOCS = ["README_KO.txt", CHANGELOG, VALIDATION, "THIRD_PARTY_NOTICES.txt", UI_VISUAL]
RELEASE_DOCS = ["README_KO.txt", CHANGELOG, VALIDATION, "THIRD_PARTY_NOTICES.txt"]
VISUAL_DIR = REPORTS / "visual_151"
QA_USER_DIR = "DVD_BATTLE_V151_VISUAL_QA"

# Shipped V1.5: read only. Baseline for the data fingerprint, the replays and the source diff.
V15_ZIP = PARENT / "DVD_BATTLE_1.5_SOURCE.zip"
V15_PREFIX = "DVD_BATTLE_1.5/"
PROTECTED = [PARENT / "DVD_BATTLE_1.5_RELEASE", PARENT / "DVD_BATTLE_1.5_WINDOWS.zip", V15_ZIP,
             PARENT / "DVD_BATTLE_1.5_SHA256.txt", PARENT / "DVD_BATTLE_1.5", PARENT / "DVD_BATTLE_1.5_VISUAL_QA",
             PARENT / "DVD_BATTLE_1.5_FRESH_IMPORT", PARENT / "DVD_BATTLE_1.4_RELEASE", PARENT / "DVD_BATTLE_1.4_WINDOWS.zip",
             PARENT / "DVD_BATTLE_1.4_SOURCE.zip", PARENT / "DVD_BATTLE_1.4_SHA256.txt", PARENT / "DVD_BATTLE_1.4"]

# Suite script -> JSON report written by it.
SUITES = {"mechanics_122": "mechanics_regression", "ai_information_122": None, "control_maps_13": "control_maps_13",
          "control_rules_13": "control_rules_13", "control_ai_13": "control_ai_13", "control_information_13": "control_information_13",
          "skill_preview_14": "skill_preview_14", "preview_isolation_14": "preview_isolation_14", "draft_14": "draft_14",
          "draft_audit_14": "draft_audit_14", "draft_isolation_14": "draft_isolation_14", "deathmatch_15": "deathmatch_15",
          "conquest_15": "conquest_15", "codex_data_151": "codex_data_151"}
UI_SUITES = ["deathmatch_ui_15", "control_ui_13", "preview_ui_14", "codex_ui_151"]
# Screenshots taken by windows_release_151.ps1 (Run-Visual, Invoke-Shot) and the exported-EXE run.
GAMEPLAY_SHOTS = ["dm12_follow", "dm12_overview", "dm8_participant_view", "conquest_crossroads", "deathmatch_setup_menu",
                  "home_151", "setup_151", "draft_151", "settings_151", "codex_chars_151", "codex_arenas_151",
                  "codex_items_151", "codex_glossary_151", "battle_3v3_151"]
UI_TEST_SHOTS = ["home_15", "deathmatch_setup_15", "deathmatch_battle_ai_15", "deathmatch_battle_rank_15",
                 "deathmatch_battle_view_15", "deathmatch_result_15", "control_ui_13"]
SHOTS = UI_TEST_SHOTS + GAMEPLAY_SHOTS + ["exported_exe_dm"]


def shot_log(name):
    return "shot_%s.log" % name if name.endswith("_151") else "shot_%s_151.log" % name


VISUAL_STEPS = {"visual_qa_import_151.log"} | {s + ".log" for s in UI_SUITES} | {shot_log(s) for s in GAMEPLAY_SHOTS}
GAME_DIRS = ["scripts", "scenes", "shaders", "assets"]
GAME_FILES = ["project.godot", "export_presets.cfg", "icon.svg", "icon.ico", "icon.svg.import"]
SKIP_DIRS = {".godot", "__pycache__", "zz_diag", ".git", ".claude", "zz_work"}
SKIP_SUFFIX = {".tmp", ".bak", ".pyc"}
# Source files compared with the cache-free copy (same rule as Get-SourceFiles in windows_release_151.ps1).
COMPARE_SKIP = {".godot", "reports", "zz_diag", ".git", ".claude", "zz_work"}
COMPARE_SUFFIX = {".gd", ".tscn", ".gdshader", ".godot", ".cfg"}
TIMING = {"mapgen_ms_max", "worst_tick_ms"}


def writable(path):
    """Every output goes through here: nothing of a shipped release is ever written."""
    target = Path(path).resolve()
    for protected in PROTECTED:
        p = protected.resolve()
        if target == p or p in target.parents:
            raise SystemExit("refusing to write a shipped-release path: %s" % target)
    if re.search(r"DVD_BATTLE_1\.5(?!\.1)", str(target)):
        raise SystemExit("refusing to write a V1.5 path: %s" % target)
    return target


def read(name):
    return json.loads((REPORTS / name).read_text(encoding="utf-8-sig"))


def rows_of(path):
    return [json.loads(line) for line in Path(path).read_text(encoding="utf-8-sig").splitlines() if line.strip()]


def sha(path):
    digest = hashlib.sha256()
    with open(path, "rb") as file:
        for block in iter(lambda: file.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def clean_log(name):
    text = (REPORTS / name).read_text(encoding="utf-8-sig", errors="replace")
    assert not re.search(r"SCRIPT ERROR|^ERROR:", text, re.MULTILINE), "error in " + name
    return text


def failures_of(report):
    value = report.get("failed", report.get("failures", []))
    return len(value) if isinstance(value, list) else int(value)


def walk(root, skip_dirs):
    for base, dirs, files in os.walk(root):
        dirs[:] = sorted(d for d in dirs if d not in skip_dirs)
        for name in sorted(files):
            yield Path(base) / name


def source_files():
    return sorted(p for p in walk(ROOT, SKIP_DIRS) if p.suffix not in SKIP_SUFFIX)


def compared_files():
    return sorted(p for p in walk(ROOT, COMPARE_SKIP) if p.suffix in COMPARE_SUFFIX)


def started(stage):
    return datetime.datetime.fromisoformat(stage["started"])


def fresh_since(path, stage, what):
    """The report was written by this run, not left over from an earlier release."""
    written = datetime.datetime.fromtimestamp(Path(path).stat().st_mtime)
    assert written >= started(stage) - datetime.timedelta(seconds=2), "stale report (older than the stage): " + what


def png_size(path):
    with open(path, "rb") as file:
        head = file.read(24)
    assert head[:8] == b"\x89PNG\r\n\x1a\n", "not a PNG: " + str(path)
    return struct.unpack(">II", head[16:24])


def v15_member(zip_file, rel):
    return zip_file.read(V15_PREFIX + rel)


def stage_checks():
    a = read("windows_stage_A_151.json")
    v = read("windows_stage_V_151.json")
    b = read("windows_stage_B_151.json")
    for stage, name in ((a, "A"), (v, "V"), (b, "B")):
        assert stage.get("stage") == name and stage.get("version") == VERSION and stage.get("finished"), "stage %s incomplete" % name
    required = (["final_import_151.log", "data_fingerprint_151.log", "data_fingerprint_v15_151.log"] + [s + ".log" for s in SUITES]
                + ["regression_matches_151_legacy_walls.log", "regression_matches_151.log", "windows_export_151.log"])
    for name in required:
        assert a["steps"][name]["ok"], name
        clean_log(name)
    # The V1.5 scratch import may need a retry after a cold-cache crash; one clean attempt is enough.
    assert any(s["ok"] for k, s in a["steps"].items() if k.startswith("v15_src_import_151")), "V1.5 source import"
    # The graphical steps are repeated in stage V; stage V is the record (as in V1.5).
    for name, step in v["steps"].items():
        if name.startswith("visual_qa_import_151"):
            continue
        assert step["ok"], name
        clean_log(name)
    assert VISUAL_STEPS - {"visual_qa_import_151.log"} <= set(v["steps"]), "stage V incomplete: %s" % sorted(VISUAL_STEPS - set(v["steps"]))
    assert any(s["ok"] for k, s in v["steps"].items() if k.startswith("visual_qa_import_151")), "QA import"
    assert v.get("qa_user_dir") == QA_USER_DIR
    assert v["started"] > a["started"] and b["started"] > v["started"], "stages must run in the order A, V, B"
    exe = a["exe"]
    assert exe["sha256"] == sha(EXE) and exe["bytes"] == EXE.stat().st_size, "exported executable changed"
    assert exe["file_version"] == FILE_VERSION and exe["product_version"] == FILE_VERSION and VERSION in exe["description"], exe
    assert a["exported_headless_start_exit"] == 0 and a["exported_render_exit"] == 0 and a["exported_render_shot"]
    assert a["settings_unchanged"] and a["settings_unchanged_by_exe"] and b["settings_unchanged"]
    assert not b["has_godot_cache_before_import"] and not b["source_mismatches"]
    for name, step in b["steps"].items():
        if name.startswith("fresh_import_151") and not step["ok"]:
            continue
        assert step["ok"], name
        clean_log(name)
    assert any(s["ok"] for k, s in b["steps"].items() if k.startswith("fresh_import_151"))
    assert {"fresh_startup_151.log", "fresh_deathmatch_151.log"} <= set(b["steps"]), "stage B incomplete"
    # Stage B compared these files with the cache-free copy; make sure nothing changed since.
    compared = compared_files()
    assert len(compared) == b["source_files_checked"], "source tree changed after stage B (%d vs %d)" % (len(compared), b["source_files_checked"])
    for path in compared:
        assert sha(path) == sha(FRESH / path.relative_to(ROOT)), "differs from the fresh import: " + str(path)
    # The game files are older than the exported executable: the EXE was built from this source.
    game = [p for d in GAME_DIRS for p in (ROOT / d).rglob("*") if p.is_file()] + [ROOT / f for f in GAME_FILES]
    newest = max(game, key=lambda p: p.stat().st_mtime)
    assert newest.stat().st_mtime < EXE.stat().st_mtime, "game source changed after export: " + str(newest)
    device = re.search(r"Using Device: (.+)", clean_log("deathmatch_ui_15.log"))
    engine = re.search(r"Godot Engine v(\d+\.\d+(?:\.\d+)?)", clean_log("final_import_151.log"))
    return a, v, b, len(compared), (device.group(1).strip() if device else ""), (engine.group(1) if engine else "")


def suites(a, v):
    counts = {}
    for script, report_name in SUITES.items():
        if report_name is None:
            info = json.loads(re.search(r"AI_INFORMATION_REGRESSION (\{.*\})", clean_log(script + ".log")).group(1))
            assert info["status"] == "PASS" and not info["failed"]
            counts[script] = info["passed"]
            continue
        report = read(report_name + ".json")
        fresh_since(REPORTS / (report_name + ".json"), a, report_name)
        assert report.get("status", "PASS") == "PASS" and failures_of(report) == 0, script
        counts[script] = int(report["passed"])
    ui = {}
    isolated = {}
    for name in UI_SUITES:
        report = read(name + ".json")
        fresh_since(REPORTS / (name + ".json"), v, name)
        assert report.get("status", "PASS") == "PASS" and failures_of(report) == 0, name
        if "isolated_user_dir" in report:
            assert "QA" in str(report["isolated_user_dir"]).upper() and "V151" in str(report["isolated_user_dir"]).upper(), name
            isolated[name] = report["isolated_user_dir"]
        ui[name] = int(report["passed"])
    return counts, ui, isolated


def data_fingerprint(a):
    """tools/data_fingerprint_151.gd: engine-read data without display-only fields, this tree vs the V1.5 source."""
    def from_log(name):
        match = re.search(r"^DATA_FINGERPRINT_151 (\{.*\})\s*$", clean_log(name), re.MULTILINE)
        assert match, "no fingerprint in " + name
        return json.loads(match.group(1))
    current, v15 = from_log("data_fingerprint_151.log"), from_log("data_fingerprint_v15_151.log")
    recorded = a["data_fingerprint"]
    assert recorded["current"]["sha256"] == current["sha256"] and recorded["v15"]["sha256"] == v15["sha256"], "stage A record differs from the logs"
    assert current["sha256"] == v15["sha256"] and current["counts"] == v15["counts"], "engine-read data differs from V1.5"
    assert recorded["equal"] is True
    # The canonical JSON written with --out hashes to the printed value.
    assert sha(REPORTS / "data_fingerprint_151.json") == current["sha256"]
    assert sha(REPORTS / "data_fingerprint_v15.json") == v15["sha256"]
    assert a["v15_source_zip"]["ok"] and a["v15_source_zip"]["sha256"] == sha(V15_ZIP), "V1.5 source zip used for the fingerprint"
    check = a["v15_source_check"]
    assert check["scripts_checked"] > 0 and not check["mismatches"], "V1.5 scratch extraction differs from the zip: %s" % check["mismatches"]
    return {"sha256": current["sha256"], "bytes": current["bytes"], "counts": current["counts"], "v15_sha256": v15["sha256"],
            "v15_source": V15_ZIP.name, "equal": True, "tool": "tools/data_fingerprint_151.gd",
            "canonical_json": ["reports/data_fingerprint_151.json", "reports/data_fingerprint_v15.json"]}


def regression(v15zip):
    """Legacy-wall elimination replays equal V1.4; all 15 legacy and current replays equal V1.5 (Windows)."""
    # The baselines are the files shipped in the V1.5 source: they must not have been overwritten.
    for name in ["regression_matches_14.jsonl", "regression_matches_15.jsonl", "regression_matches_15_legacy_walls.jsonl"]:
        assert hashlib.sha256(v15_member(v15zip, "reports/" + name)).hexdigest() == sha(REPORTS / name), "baseline changed: " + name
    by_case = lambda path: {r["case_id"]: r for r in rows_of(path)}
    base14 = by_case(REPORTS / "regression_matches_14.jsonl")
    base15 = {"legacy_walls": by_case(REPORTS / "regression_matches_15_legacy_walls.jsonl"), "current": by_case(REPORTS / "regression_matches_15.jsonl")}
    runs = {"legacy_walls": by_case(REPORTS / "regression_matches_151_legacy_walls.jsonl"), "current": by_case(REPORTS / "regression_matches_151.jsonl")}
    fields = ("signature", "winner", "duration", "reason", "ruleset")
    for run, rows in runs.items():
        assert len(rows) == 15 and set(rows) == set(base15[run]), run
        for case, row in rows.items():
            assert not row["invariant_error"], "invariant error: %s %s" % (run, case)
            old = base15[run][case]
            assert all(row[f] == old[f] for f in fields), "replay differs from V1.5: %s %s" % (run, case)
    legacy_elim = [r for r in runs["legacy_walls"].values() if r["ruleset"] == "elimination"]
    assert len(legacy_elim) == 12 and all(r["signature"] == base14[r["case_id"]]["signature"] for r in legacy_elim), "legacy wall replay differs from V1.4"
    # The comparison the stage script wrote agrees with this one.
    table = read("battle_regression_151.json")
    assert len(table) == 30 and all(r["equal_to_15"] for r in table)
    assert all(r["equal_to_14"] for r in table if r["run"] == "legacy_walls" and r["ruleset"] == "elimination")
    current = list(runs["current"].values())
    return {"cases": len(current), "legacy_elimination_equal_14": len(legacy_elim),
            "legacy_equal_15": len(runs["legacy_walls"]), "current_equal_15": len(current),
            "current_elimination": sum(1 for r in current if r["ruleset"] == "elimination"),
            "current_control": sum(1 for r in current if r["ruleset"] != "elimination"),
            "compared_fields": list(fields)}


def v15_metrics(v15zip, dm, conquest):
    """Deathmatch and conquest suites measure real AI matches: their metrics must equal the V1.5 Windows run."""
    old_dm = json.loads(v15_member(v15zip, "reports/deathmatch_15.json").decode("utf-8-sig"))["metrics"]
    old_cq = json.loads(v15_member(v15zip, "reports/conquest_15.json").decode("utf-8-sig"))["metrics"]
    assert {k: v for k, v in dm.items() if k not in TIMING} == {k: v for k, v in old_dm.items() if k not in TIMING}, "deathmatch metrics differ from V1.5"
    assert conquest == old_cq, "conquest metrics differ from V1.5"
    return {"deathmatch_equal_excluding_timing": True, "conquest_equal": True, "timing_keys_ignored": sorted(TIMING)}


def ai_evaluation():
    spec = importlib.util.spec_from_file_location("summarize_15", ROOT / "tools" / "ai_eval_15" / "summarize_15.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    computed = {"conquest_probe": module.conquest_probe(), "assignment_probe": module.assignment_probe(),
                "wall_band": module.wall_band(), "head_to_head": module.head_to_head()}
    stored = read("ai_eval_15/summary_15.json")
    for key in computed:
        assert computed[key] == stored[key], "ai_eval_15 summary is stale: " + key
    assert computed["conquest_probe"]["tactician"]["matches"] == 6 and computed["conquest_probe"]["tactician14"]["matches"] == 6
    assert computed["head_to_head"]["matches"] == 32
    return computed


def platform_replay():
    """V1.5 evidence: Linux replay of the reference battles with the V1.4 wall handling vs the V1.5 Windows replay."""
    def rows(path):
        return {r["case_id"]: r for r in rows_of(path)}
    linux = rows(REPORTS / "ai_eval_15" / "linux_legacy_walls_replay.jsonl")
    windows = rows(REPORTS / "regression_matches_15_legacy_walls.jsonl")
    assert set(linux) == set(windows) and len(linux) == 15
    same = [k for k in windows if linux[k]["signature"] == windows[k]["signature"]]
    duration = [k for k in windows if abs(linux[k]["duration"] - windows[k]["duration"]) > 0.01]
    winner = [k for k in windows if linux[k]["winner"] != windows[k]["winner"]]
    return {"cases": len(windows), "same_final_state": same, "different_duration": duration, "different_winner": winner}


def small_matches():
    out = {}
    for n in (2, 4):
        rows = rows_of(REPORTS / "ai_eval_15" / ("dm_small_%d.jsonl" % n))
        assert len(rows) == 3
        out[n] = {"duration": rows[0]["duration"], "kills": [r["kills"] for r in rows], "first_contact": [r["first_contact"] for r in rows]}
    return out


def preserved(version):
    listed = {}
    for line in (PARENT / ("DVD_BATTLE_%s_SHA256.txt" % version)).read_text(encoding="ascii").splitlines():
        if line.strip():
            digest, name = line.split(None, 1)
            listed[name.strip()] = digest
    paths = {"DVD_BATTLE_%s.exe" % version: PARENT / ("DVD_BATTLE_%s_RELEASE" % version) / ("DVD_BATTLE_%s.exe" % version),
             "DVD_BATTLE_%s_WINDOWS.zip" % version: PARENT / ("DVD_BATTLE_%s_WINDOWS.zip" % version),
             "DVD_BATTLE_%s_SOURCE.zip" % version: PARENT / ("DVD_BATTLE_%s_SOURCE.zip" % version)}
    assert set(paths) == set(listed), "unexpected V%s hash list" % version
    for name, path in paths.items():
        assert sha(path) == listed[name], "V%s artefact changed: %s" % (version, name)
    return listed


def diff_15(v15zip):
    """Source changes against the shipped V1.5 source zip (reports excluded)."""
    skip = SKIP_DIRS | {"reports"}
    old = {}
    for info in v15zip.infolist():
        if info.is_dir():
            continue
        assert info.filename.startswith(V15_PREFIX), info.filename
        rel = info.filename[len(V15_PREFIX):]
        if not (skip & set(rel.split("/"))):
            old[rel] = info
    new = {p.relative_to(ROOT).as_posix(): p for p in walk(ROOT, skip)}
    added = sorted(set(new) - set(old))
    removed = sorted(set(old) - set(new))
    changed, eol_only = [], []
    for rel in sorted(set(old) & set(new)):
        before, after = v15zip.read(old[rel]), new[rel].read_bytes()
        if before != after:
            changed.append(rel)
            if before.replace(b"\r\n", b"\n") == after.replace(b"\r\n", b"\n"):
                eol_only.append(rel)
    return {"baseline": V15_ZIP.name, "added": added, "changed": changed, "changed_line_endings_only": eol_only, "removed": removed}


def pct(a, b):
    return "%.1f%%" % (100.0 * a / b) if b else "-"


def validation_text(ctx):
    s, ui, dm, cq, reg, a, v, b = ctx["suites"], ctx["ui"], ctx["dm"], ctx["conquest"], ctx["regression"], ctx["stage_a"], ctx["stage_v"], ctx["stage_b"]
    fp, ev, pf, sm, diff = ctx["fingerprint"], ctx["eval"], ctx["platform"], ctx["small"], ctx["diff"]
    c = fp["counts"]
    total = sum(s.values()) + sum(ui.values())
    exe = a["exe"]
    h = ev["head_to_head"]
    modes = dm["ai_modes"]
    mode_total = sum(modes.values())
    mode_names = {"hunt": "사냥", "loot": "보급", "roam": "탐색", "recover": "회복", "evade": "회피", "chase": "추격", "listen": "소음 추적", "dead": "재출전 대기"}
    mode_line = ", ".join("%s %s" % (mode_names.get(k, k), pct(val, mode_total)) for k, val in sorted(modes.items(), key=lambda kv: -kv[1]))
    turrets = cq["turrets"]
    suite_lines = ["  %-24s %5d" % (k, val) for k, val in s.items()] + ["  %-24s %5d  (실제 화면)" % (k, val) for k, val in ui.items()]
    w, hgt = ctx["ui_resolution"]
    ew, eh = ctx["exe_shot_size"]
    arenas = c["arenas"] + c["control_arenas"] + c["deathmatch_presets"]
    a_visual = [k for k in VISUAL_STEPS if k in a["steps"] and not k.startswith("visual_qa_import_151")]
    a_visual_failed = sorted(k for k in a_visual if not a["steps"][k]["ok"])
    if not a_visual:
        a_visual_line = []
    elif not a_visual_failed:
        a_visual_line = ["  Stage A의 화면 검사 단계도 모두 통과했습니다. 아래 UI 수치와 화면은 Stage V의 재실행 결과입니다."]
    else:
        a_visual_line = ["  Stage A의 화면 검사 단계 중 통과하지 못한 %d단계(%s)는 Stage V에서 다시 실행해 통과했습니다." % (
            len(a_visual_failed), ", ".join(k.replace(".log", "") for k in a_visual_failed))]
    shot_lines = ["    " + ", ".join(ctx["shots"][i:i + 6]) + ("," if i + 6 < len(ctx["shots"]) else ".") for i in range(0, len(ctx["shots"]), 6)]
    isolated = ", ".join(sorted(set(ctx["isolated"].values()))) or QA_USER_DIR
    sizes = sorted((tuple(int(x) for x in k[len("layout_"):].split("x")) for k in ctx["preview_measurements"]
                    if re.fullmatch(r"layout_\d+x\d+", k)), key=lambda t: t[0] * t[1])
    layouts = "과 ".join("%d×%d" % t for t in sizes)
    wide = "%d×%d" % sizes[-1] if sizes else ""
    lines = [
        "DVD BATTLE V1.5.1 검증 기록",
        "작성: %s (tools/package_release_151.py가 reports의 원자료에서 생성)" % datetime.date.today().isoformat(),
        "",
        "요약",
        "  자동 검사 %d항목 PASS, 실패 0. Windows 실제 실행(Godot %s, %s)." % (total, ctx["engine"] or "4.7.2", ctx["device"] or "Windows"),
        "  배포 EXE DVD_BATTLE_1.5.1.exe: %s bytes, SHA-256 %s, 파일·제품 버전 %s, PCK 내장." % (format(exe["bytes"], ","), exe["sha256"], exe["file_version"]),
        "  V1.5.1은 UX/UI 리워크 릴리스입니다. 모든 화면의 디자인·가독성·조작 흐름을 다듬었고, 전투 도감에 아이템 도감(%d종)을 추가했으며," % c["items"],
        "    도감에서 잘 보이지 않던 스킬·패시브·아이템·전장 효과를 수치·상태 용어와 함께 표시하도록 바꾸었습니다.",
        "  시뮬레이션·AI·데이터 수치는 바꾸지 않았습니다. 엔진이 읽는 데이터의 지문이 V1.5와 같고(4장), 기준 전투 %d경기의 재생이" % reg["cases"],
        "    V1.5와, 섬멸전 %d경기의 V1.4 벽 처리 재생이 V1.4와 완전히 같습니다(3장)." % reg["legacy_elimination_equal_14"],
        "",
        "1. 자동 검사 (Windows, tools/windows_release_151.ps1)",
        "  Stage A %s: 가져오기, 데이터 지문(V1.5.1과 V1.5 소스), 스크립트 검사 %d종, 기준 전투 재생, EXE 내보내기, EXE 시작." % (a["started"].replace("T", " "), len(s)),
        "  Stage V %s: 격리 QA 복제본에서 실제 화면 UI 검사 %d종과 화면 저장 %d장." % (v["started"].replace("T", " "), len(ui), len(ctx["shots"])),
        "  Stage B %s: 캐시 없는 소스 복사본의 가져오기·시작·데스매치 검사." % b["started"].replace("T", " "),
    ] + a_visual_line + suite_lines + [
        "  합계 %d / 실패 0. 각 로그에 SCRIPT ERROR와 ERROR 줄이 없습니다. 모든 보고서는 이번 단계 실행 중에 새로 기록되었습니다." % total,
        "",
        "2. UI 검사 (실제 화면 %d×%d, 격리 사용자 디렉터리 %s)" % (w, hgt, isolated),
        "  deathmatch_ui_15 %d항목: 홈·데스매치 설정(인원, 전장, 시드, 목표, 시간, 아이템 탭)·12명 전투·패널 4종·결과 화면." % ui["deathmatch_ui_15"],
        "  control_ui_13 %d항목: 거점 장악 전투와 결과 화면." % ui["control_ui_13"],
        "  preview_ui_14 %d항목: 스킬 미리보기의 16:9 화면·조작·설명이 %s에서 스크롤 없이 보이는지와 재생 동작." % (ui["preview_ui_14"], layouts or "두 해상도"),
        "  codex_ui_151 %d항목: 전투 도감의 캐릭터·전장·아이템·용어 모드와 아이템 상세, 캐릭터 외 모드에서 미리보기 시뮬레이션 분리." % ui["codex_ui_151"],
        "  codex_data_151 %d항목(헤드리스): 도감 설명 데이터와 효과 표시 문구." % s["codex_data_151"],
        "  화면 저장 %d장(reports/visual_151):" % len(ctx["shots"]),
    ] + shot_lines + [
        "  상세는 reports/UI_VISUAL_1.5.1.txt.",
        "",
        "3. 기존 전투 재생 (Windows, 기준 %d경기: 섬멸전 %d + 거점 %d)" % (reg["cases"], reg["current_elimination"], reg["current_control"]),
        "  V1.4 벽 처리(--legacy_walls=1): 섬멸전 %d/%d가 V1.4 최종 상태 서명과 같고, %d/%d경기 모두 V1.5의 같은 재생과 같습니다." % (
            reg["legacy_elimination_equal_14"], reg["current_elimination"], reg["legacy_equal_15"], reg["cases"]),
        "  현재 벽 처리: %d/%d경기가 V1.5 Windows 결과(reports/regression_matches_15.jsonl)와 최종 상태 서명·승자·진행 시간·종료 사유까지 같습니다." % (
            reg["current_equal_15"], reg["cases"]),
        "  모든 경기에서 불변식 오류가 없습니다. 비교 기준 파일 3개는 V1.5 소스 ZIP의 파일과 바이트 단위로 같습니다.",
        "  데스매치 AI 경기(deathmatch_15)의 지표도 V1.5 기록과 같습니다(측정 시간 값 제외): 분당 처치 %.1f, 분당 피해 %s, 아이템 획득 %d · 거절 %d," % (
            dm["ai_kills_per_min_8p"], format(dm["ai_damage_per_min_8p"], ","), dm["ai_item_picks"], dm["ai_item_skips"]),
        "    의도 분포(1초 표본) %s." % mode_line,
        "  거점 장악 검사(conquest_15)의 포탑 지표도 V1.5와 같습니다: V1.5 AI %d개 중 스폰 앞 %d, V1.4 AI %d개 중 %d." % (
            turrets["tactician"]["turrets"], turrets["tactician"]["idle_spawn_turrets"], turrets["tactician14"]["turrets"], turrets["tactician14"]["idle_spawn_turrets"]),
        "  캐시 없는 복사본(Stage B)의 데스매치 검사도 %d항목 PASS였고 AI 경기 지표가 Stage A와 같았습니다(측정 시간 값 제외)." % ctx["fresh_dm_passed"],
        "",
        "4. 데이터 지문 (tools/data_fingerprint_151.gd)",
        "  엔진이 읽는 데이터(캐릭터 %d · 스킬 %d · 패시브 %d, 아이템 %d, 섬멸전 전장 %d, 거점 전장 %d, 데스매치 프리셋 %d과 생성 지도 %d)에서" % (
            c["characters"], c["abilities"], c["passives"], c["items"], c["arenas"], c["control_arenas"], c["deathmatch_presets"], c["deathmatch_maps"]),
        "    표시 전용 문구(스킬 설명·도형·타이밍 문구, 패시브 이름·설명, 캐릭터 요약·성향 이름·교리·넥서스 소개, 아이템 이름·설명·문양,",
        "    전장 설명·부제·전술 메모·태그·아이콘·유형)를 뺀 정규화 JSON(%s bytes)의 SHA-256:" % format(fp["bytes"], ","),
        "    V1.5.1  %s" % fp["sha256"],
        "    V1.5    %s  (DVD_BATTLE_1.5_SOURCE.zip, 배포 해시 목록과 일치)" % fp["v15_sha256"],
        "  → 같습니다. 스킬 효과·수치·조건·AI 설정, 캐릭터 능력치·성향 수치, 아이템 효과·등급·태그·출현 가중치,",
        "    전장 지형·위험 요소·거점·회복 구역 수치와 데스매치 지도 생성 결과가 V1.5와 같습니다.",
        "  정규화 JSON은 reports/data_fingerprint_151.json과 reports/data_fingerprint_v15.json이며, 파일의 SHA-256이 위 값과 같습니다.",
        "",
        "5. 배포와 보존",
        "  EXE 헤드리스 시작(종료 코드 %d), 실제 렌더링 데스매치 실행(종료 코드 %d)과 화면 저장(%d×%d)." % (
            a["exported_headless_start_exit"], a["exported_render_exit"], ew, eh),
        "  모든 Windows 단계 전후로 사용자 설정 파일 해시가 같았습니다(QA 검사는 별도 사용자 디렉터리 사용).",
        "  캐시 없는 소스 복사본(D:\\DVD_BATTLE_1.5.1_FRESH_IMPORT): .godot 없이 가져오기 %.1f초, 시작 %.1f초, 데스매치 검사 통과, 소스 %d개 SHA-256 일치." % (
            ctx["fresh_import_s"], b["steps"]["fresh_startup_151.log"]["seconds"], ctx["fresh_files"]),
        "  EXE 내보내기 이후 게임 소스(scripts, scenes, shaders, assets, project.godot, export_presets.cfg)가 바뀌지 않았음을 수정 시각으로 확인했습니다.",
        "  V1.5 EXE와 ZIP 2개, V1.4 EXE와 ZIP 2개의 SHA-256이 각 배포 기록과 같습니다(패키징 전후 모두). V1.5 파일은 덮어쓰지 않았습니다.",
        "  ZIP은 CRC 검사와 원본 파일별 SHA-256 비교를 통과했습니다. 해시는 DVD_BATTLE_1.5.1_SHA256.txt에 있습니다.",
        "  V1.5 대비 소스 변경: 추가 %d, 수정 %d(그중 줄바꿈만 다른 파일 %d), 삭제 %d개 파일(reports 제외, 기준 DVD_BATTLE_1.5_SOURCE.zip, 목록은 %s)." % (
            len(diff["added"]), len(diff["changed"]), len(diff["changed_line_endings_only"]), len(diff["removed"]), MANIFEST),
        "",
        "6. V1.5에서 이어받은 근거",
        "  시뮬레이션과 데이터가 V1.5와 같으므로(3·4장), V1.5의 AI 평가 결과를 그대로 이어받습니다. 원자료는 reports/ai_eval_15에 있고,",
        "    저장된 요약을 원자료에서 다시 계산해 같음을 확인했습니다.",
        "  거점 AI 직접 대전(Linux, h2h_15.gd): %d조합 %d경기, V1.5 AI %d승 %d패, 양측 부호 검정 p = %.2f(승률 차이는 유의하지 않음)." % (
            h["compositions"], h["matches"], h["a_outcomes"].get("win", 0), h["a_outcomes"].get("loss", 0), h["sign_test_p_two_sided"]),
        "  Linux와 Windows의 기준 %d경기 재생(V1.4 벽 처리): 최종 상태 같음 %d, 진행 시간 다름 %d, 승자 다름 %d." % (
            pf["cases"], len(pf["same_final_state"]), len(pf["different_duration"]), len(pf["different_winner"])),
        "  소규모 데스매치(Linux, dm_small_15.gd, %d초 경기 전장별 1회)의 처치 수: 2명 %s, 4명 %s." % (
            int(sm[2]["duration"]), "/".join(str(k) for k in sm[2]["kills"]), "/".join(str(k) for k in sm[4]["kills"])),
        "",
        "7. 제한과 참고",
        "  이번 릴리스는 화면과 도감 표시만 바꿨습니다. 전투 결과·AI 판단·밸런스는 V1.5와 같습니다(3·4장).",
        "  프레임 속도는 이번 검증에서 따로 측정하지 않았습니다. 전투 시뮬레이션의 계산 내용은 V1.5와 같습니다.",
        "  UI 검사는 이 PC(%s)의 실제 화면에서 실행했습니다. preview_ui_14의 넓은 화면 배치(%s)는 같은 해상도의 모니터에서 전체 화면으로 확인됩니다." % (
            ctx["device"] or "Windows", wide or "-"),
        "  AI 대 AI 결과는 작은 표본의 기술 통계입니다. 모든 조합·전장에서의 승률이나 강도를 보장하지 않습니다.",
        "  재실행: tools/RUN_WIN151_A.bat → RUN_WIN151_V.bat → RUN_WIN151_B.bat → py tools/package_release_151.py",
        "",
    ]
    return "\n".join(lines)


def archive(path, files, root, prefix):
    names = [prefix + file.relative_to(root).as_posix() for file in files]
    with zipfile.ZipFile(writable(path), "w", zipfile.ZIP_DEFLATED, compresslevel=6) as bundle:
        for file, name in zip(files, names):
            bundle.write(file, name)
    with zipfile.ZipFile(path) as bundle:
        assert bundle.testzip() is None
        assert bundle.namelist() == names
        for file, name in zip(files, names):
            digest = hashlib.sha256()
            with bundle.open(name) as member:
                for block in iter(lambda: member.read(1 << 20), b""):
                    digest.update(block)
            assert digest.hexdigest() == sha(file), "zip content differs: " + str(file)
    return len(files)


def main():
    assert ROOT.name == "DVD_BATTLE_1.5.1", "run from the V1.5.1 tree"
    preserved_15 = preserved("1.5")
    preserved_14 = preserved("1.4")
    stage_a, stage_v, stage_b, fresh_files, device, engine = stage_checks()
    counts, ui, isolated = suites(stage_a, stage_v)
    fingerprint = data_fingerprint(stage_a)
    dm = read("deathmatch_15.json")
    fresh_dm = json.loads((FRESH / "reports" / "deathmatch_15.json").read_text(encoding="utf-8-sig"))
    assert fresh_dm["status"] == "PASS" and fresh_dm["passed"] == dm["passed"]
    assert {k: v for k, v in fresh_dm["metrics"].items() if k not in TIMING} == {k: v for k, v in dm["metrics"].items() if k not in TIMING}
    conquest = read("conquest_15.json")["metrics"]
    with zipfile.ZipFile(V15_ZIP) as v15zip:
        reg = regression(v15zip)
        same_metrics = v15_metrics(v15zip, dm["metrics"], conquest)
        diff = diff_15(v15zip)
    evaluation = ai_evaluation()
    platform = platform_replay()
    small = small_matches()
    assert (VISUAL_DIR / ".gdignore").is_file(), "reports/visual_151/.gdignore"
    for shot in SHOTS:
        assert (VISUAL_DIR / (shot + ".png")).is_file(), shot
    shots = sorted(p.stem for p in VISUAL_DIR.glob("*.png"))
    ui_resolution = png_size(VISUAL_DIR / "home_151.png")
    exe_shot_size = png_size(VISUAL_DIR / "exported_exe_dm.png")
    fresh_import_s = next(s["seconds"] for k, s in stage_b["steps"].items() if k.startswith("fresh_import_151") and s["ok"])
    ctx = {"suites": counts, "ui": ui, "isolated": isolated, "dm": dm["metrics"], "conquest": conquest, "eval": evaluation, "regression": reg,
           "stage_a": stage_a, "stage_v": stage_v, "stage_b": stage_b, "device": device, "engine": engine, "fresh_files": fresh_files,
           "fresh_dm_passed": fresh_dm["passed"], "fresh_import_s": fresh_import_s, "diff": diff, "platform": platform, "small": small,
           "fingerprint": fingerprint, "shots": shots, "ui_resolution": ui_resolution, "exe_shot_size": exe_shot_size,
           "preview_measurements": read("preview_ui_14.json").get("measurements", {})}
    with open(writable(ROOT / VALIDATION), "w", encoding="utf-8-sig", newline="\r\n") as file:
        file.write(validation_text(ctx))
    for name in DOCS:
        assert (ROOT / name).is_file(), name
    manifest = {"version": VERSION, "file_version": FILE_VERSION, "engine": "Godot " + (engine or "4.7.2"), "platform": "Windows x86_64",
                "packaged_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(), "render_device": device,
                "executable": {"name": EXE.name, "bytes": EXE.stat().st_size, "sha256": sha(EXE), "embedded_pck": True},
                "assertions_passed": sum(counts.values()) + sum(ui.values()), "suites": counts, "ui_suites": ui,
                "ui_isolated_user_dirs": isolated, "shots": shots,
                "windows_stages": {k: {"started": s["started"], "finished": s.get("finished")} for k, s in (("A", stage_a), ("V", stage_v), ("B", stage_b))},
                "cache_free_source_import": {"folder": FRESH.name, "files_compared": fresh_files, "mismatches": 0},
                "data_fingerprint": fingerprint, "battle_regression": reg, "metrics_equal_to_v15": same_metrics,
                "deathmatch_metrics": dm["metrics"], "conquest_suite_metrics": conquest,
                "carried_from_v15": {"ai_evaluation": evaluation, "small_deathmatch": small, "linux_windows_replay": platform},
                "preserved_v15_sha256": preserved_15, "preserved_v14_sha256": preserved_14, "changes_since_v15": diff,
                "source_files_sha256": {p.relative_to(ROOT).as_posix(): sha(p) for p in source_files() if p.name != MANIFEST}}
    writable(REPORTS / MANIFEST).write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    for name in RELEASE_DOCS:
        shutil.copy2(ROOT / name, writable(RELEASE / name))
    shutil.copy2(REPORTS / MANIFEST, writable(RELEASE / MANIFEST))
    release_files = sorted(p for p in RELEASE.iterdir() if p.is_file())
    win_count = archive(WIN_ZIP, release_files, RELEASE, WIN_PREFIX)
    src_count = archive(SRC_ZIP, source_files(), ROOT, SRC_PREFIX)
    writable(SHA_FILE).write_text("".join("%s  %s\n" % (sha(p), p.name) for p in [EXE, WIN_ZIP, SRC_ZIP]), encoding="ascii")
    # The shipped releases are still intact after packaging.
    assert preserved("1.5") == preserved_15 and preserved("1.4") == preserved_14
    print(json.dumps({"assertions": manifest["assertions_passed"], "data_fingerprint": fingerprint["sha256"],
                      "windows_zip_files": win_count, "source_zip_files": src_count,
                      "artifacts": [{"path": str(p), "bytes": p.stat().st_size, "sha256": sha(p)} for p in [EXE, WIN_ZIP, SRC_ZIP]]},
                     ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
