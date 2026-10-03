"""Verify the V1.5 evidence, write VALIDATION_1.5_KO.txt and the manifest, and package the release.

Run after tools/RUN_WIN15_A.bat, RUN_WIN15_V.bat and RUN_WIN15_B.bat (in that order) and after the
AI evaluation outputs in reports/ai_eval_15 exist. The numbers written to VALIDATION_1.5_KO.txt are read
from the reports here, except the frame rates in section 6, which are the values shown on the saved
screenshots in reports/visual_15.
"""
import datetime
import hashlib
import importlib.util
import json
import re
import shutil
import sys
import zipfile
from pathlib import Path

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[1]
REPORTS = ROOT / "reports"
PARENT = ROOT.parent
RELEASE = PARENT / "DVD_BATTLE_1.5_RELEASE"
FRESH = PARENT / "DVD_BATTLE_1.5_FRESH_IMPORT"
EXE = RELEASE / "DVD_BATTLE_1.5.exe"
WIN_ZIP = PARENT / "DVD_BATTLE_1.5_WINDOWS.zip"
SRC_ZIP = PARENT / "DVD_BATTLE_1.5_SOURCE.zip"
SHA_FILE = PARENT / "DVD_BATTLE_1.5_SHA256.txt"

# Suite script -> JSON report written by it.
SUITES = {"mechanics_122": "mechanics_regression", "ai_information_122": None, "control_maps_13": "control_maps_13",
          "control_rules_13": "control_rules_13", "control_ai_13": "control_ai_13", "control_information_13": "control_information_13",
          "skill_preview_14": "skill_preview_14", "preview_isolation_14": "preview_isolation_14", "draft_14": "draft_14",
          "draft_audit_14": "draft_audit_14", "draft_isolation_14": "draft_isolation_14", "deathmatch_15": "deathmatch_15",
          "conquest_15": "conquest_15"}
UI_SUITES = ["deathmatch_ui_15", "control_ui_13", "preview_ui_14"]
VISUAL_STEPS = {"visual_qa_import_15.log", "deathmatch_ui_15.log", "control_ui_13.log", "preview_ui_14.log", "shot_dm12_follow.log",
                "shot_dm12_overview.log", "shot_dm8_view.log", "shot_conquest.log", "shot_dm_setup.log"}
SHOTS = ["home_15", "deathmatch_setup_15", "deathmatch_setup_menu", "deathmatch_battle_ai_15", "deathmatch_battle_rank_15",
         "deathmatch_battle_view_15", "deathmatch_result_15", "dm12_follow", "dm12_overview", "dm8_participant_view",
         "conquest_crossroads", "control_ui_13", "exported_exe_dm"]
GAME_DIRS = ["scripts", "scenes", "shaders", "assets"]
GAME_FILES = ["project.godot", "export_presets.cfg", "icon.svg", "icon.ico", "icon.svg.import"]
SKIP_DIRS = {".godot", "__pycache__", "zz_diag"}
SKIP_SUFFIX = {".tmp", ".bak", ".pyc"}


def read(name):
    return json.loads((REPORTS / name).read_text(encoding="utf-8-sig"))


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


def source_files():
    out = []
    for path in ROOT.rglob("*"):
        rel = path.relative_to(ROOT)
        if path.is_file() and not (SKIP_DIRS & set(rel.parts)) and path.suffix not in SKIP_SUFFIX:
            out.append(path)
    return sorted(out)


def stage_checks():
    a = read("windows_stage_A_15.json")
    v = read("windows_stage_V_15.json")
    b = read("windows_stage_B_15.json")
    required = ["final_import_15.log"] + [s + ".log" for s in SUITES] + ["regression_matches_15_legacy_walls.log", "regression_matches_15.log", "windows_export_15.log"]
    for name in required:
        assert a["steps"][name]["ok"], name
        clean_log(name)
    # The graphical steps of stage A were repeated in stage V (the first QA import crashed on a cold cache).
    for name, step in v["steps"].items():
        if name.startswith("visual_qa_import_15"):
            continue
        assert step["ok"], name
        clean_log(name)
    assert VISUAL_STEPS - {"visual_qa_import_15.log"} <= set(v["steps"]), "stage V incomplete"
    assert any(s["ok"] for k, s in v["steps"].items() if k.startswith("visual_qa_import_15")), "QA import"
    assert v["started"] > a["started"] and b["started"] > v["started"]
    exe = a["exe"]
    assert exe["sha256"] == sha(EXE) and exe["bytes"] == EXE.stat().st_size, "exported executable changed"
    assert exe["file_version"] == "1.5.0.0" and exe["product_version"] == "1.5.0.0" and "GD-1.5" in exe["description"]
    assert a["exported_headless_start_exit"] == 0 and a["exported_render_exit"] == 0 and a["exported_render_shot"]
    assert a["settings_unchanged"] and a["settings_unchanged_by_exe"] and b["settings_unchanged"]
    assert not b["has_godot_cache_before_import"] and not b["source_mismatches"]
    for name, step in b["steps"].items():
        if name.startswith("fresh_import_15") and not step["ok"]:
            continue
        assert step["ok"], name
        clean_log(name)
    assert any(s["ok"] for k, s in b["steps"].items() if k.startswith("fresh_import_15"))
    # Stage B compared these files with the cache-free copy; make sure nothing changed since.
    compared = [p for p in ROOT.rglob("*") if p.is_file() and p.suffix in {".gd", ".tscn", ".gdshader", ".godot", ".cfg"}
                and not ({".godot", "reports", "zz_diag"} & set(p.relative_to(ROOT).parts))]
    assert len(compared) == b["source_files_checked"], "source tree changed after stage B (%d vs %d)" % (len(compared), b["source_files_checked"])
    for path in compared:
        assert sha(path) == sha(FRESH / path.relative_to(ROOT)), "differs from the fresh import: " + str(path)
    # The game files are older than the exported executable: the EXE was built from this source.
    game = [p for d in GAME_DIRS for p in (ROOT / d).rglob("*") if p.is_file()] + [ROOT / f for f in GAME_FILES]
    newest = max(game, key=lambda p: p.stat().st_mtime)
    assert newest.stat().st_mtime < EXE.stat().st_mtime, "game source changed after export: " + str(newest)
    device = re.search(r"Using Device: (.+)", clean_log("deathmatch_ui_15.log"))
    return a, v, b, len(compared), (device.group(1).strip() if device else "")


def suites():
    counts = {}
    for script, report_name in SUITES.items():
        if report_name is None:
            info = json.loads(re.search(r"AI_INFORMATION_REGRESSION (\{.*\})", clean_log(script + ".log")).group(1))
            assert info["status"] == "PASS" and not info["failed"]
            counts[script] = info["passed"]
            continue
        report = read(report_name + ".json")
        assert report.get("status", "PASS") == "PASS" and failures_of(report) == 0, script
        counts[script] = report["passed"]
    ui = {}
    for name in UI_SUITES:
        report = read(name + ".json")
        assert report.get("status", "PASS") == "PASS" and failures_of(report) == 0, name
        if "isolated_user_dir" in report:
            assert "QA" in str(report["isolated_user_dir"]).upper()
        ui[name] = report["passed"]
    return counts, ui


def regression():
    rows = read("battle_regression_15.json")
    base = {}
    for line in (REPORTS / "regression_matches_14.jsonl").read_text(encoding="utf-8-sig").splitlines():
        if line.strip():
            row = json.loads(line)
            base[row["case_id"]] = row
    legacy = [r for r in rows if r["run"] == "legacy_walls"]
    current = [r for r in rows if r["run"] == "current"]
    assert len(legacy) == 15 and len(current) == 15
    assert not any(r["invariant_error"] for r in rows)
    legacy_elim = [r for r in legacy if r["ruleset"] == "elimination"]
    assert len(legacy_elim) == 12 and all(r["equal_to_14"] for r in legacy_elim), "legacy wall replay differs from V1.4"
    changed = []
    for r in current:
        if r["ruleset"] == "elimination" and not r["equal_to_14"]:
            old = base[r["case_id"]]
            assert r["winner"] == old["winner"], "winner changed: " + r["case_id"]
            changed.append({"case_id": r["case_id"], "duration_14": round(old["duration"], 2), "duration_15": round(r["duration"], 2), "winner": r["winner"]})
    same = sum(1 for r in current if r["ruleset"] == "elimination" and r["equal_to_14"])
    return {"legacy_elimination_equal": len(legacy_elim), "current_elimination_equal": same, "current_elimination_changed": changed}


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
    """Linux replay of the reference battles with the V1.4 wall handling vs the Windows replay."""
    def rows(path):
        return {json.loads(l)["case_id"]: json.loads(l) for l in path.read_text(encoding="utf-8-sig").splitlines() if l.strip()}
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
        rows = [json.loads(l) for l in (REPORTS / "ai_eval_15" / ("dm_small_%d.jsonl" % n)).read_text(encoding="utf-8-sig").splitlines() if l.strip()]
        assert len(rows) == 3
        out[n] = {"duration": rows[0]["duration"], "kills": [r["kills"] for r in rows], "first_contact": [r["first_contact"] for r in rows]}
    return out


def preserved_14():
    listed = {}
    for line in (PARENT / "DVD_BATTLE_1.4_SHA256.txt").read_text(encoding="ascii").splitlines():
        digest, name = line.split(None, 1)
        listed[name.strip()] = digest
    paths = {"DVD_BATTLE_1.4.exe": PARENT / "DVD_BATTLE_1.4_RELEASE" / "DVD_BATTLE_1.4.exe",
             "DVD_BATTLE_1.4_WINDOWS.zip": PARENT / "DVD_BATTLE_1.4_WINDOWS.zip", "DVD_BATTLE_1.4_SOURCE.zip": PARENT / "DVD_BATTLE_1.4_SOURCE.zip"}
    for name, path in paths.items():
        assert sha(path) == listed[name], "V1.4 artefact changed: " + name
    return listed


def diff_14():
    old_root = PARENT / "DVD_BATTLE_1.4"
    skip = {".godot", "__pycache__", "zz_diag", "reports"}

    def listing(root):
        return {p.relative_to(root).as_posix(): p for p in root.rglob("*") if p.is_file() and not (skip & set(p.relative_to(root).parts))}
    old, new = listing(old_root), listing(ROOT)
    added = sorted(set(new) - set(old))
    removed = sorted(set(old) - set(new))
    changed = sorted(k for k in set(old) & set(new) if sha(old[k]) != sha(new[k]))
    return {"added": added, "changed": changed, "removed": removed}


def pct(a, b):
    return "%.1f%%" % (100.0 * a / b) if b else "-"


def validation_text(ctx):
    s, ui, dm, cq, ev, reg, a, b = ctx["suites"], ctx["ui"], ctx["dm"], ctx["conquest"], ctx["eval"], ctx["regression"], ctx["stage_a"], ctx["stage_b"]
    pf = ctx["platform"]
    sm = ctx["small"]
    total = sum(s.values()) + sum(ui.values())
    old, new = ev["conquest_probe"]["tactician14"], ev["conquest_probe"]["tactician"]
    ot, nt = old["totals"], new["totals"]
    asg_o, asg_n = ev["assignment_probe"]["tactician14"], ev["assignment_probe"]["tactician"]
    wb = ev["wall_band"]
    h = ev["head_to_head"]
    modes = dm["ai_modes"]
    mode_total = sum(modes.values())
    mode_names = {"hunt": "사냥", "loot": "보급", "roam": "탐색", "recover": "회복", "evade": "회피", "chase": "추격", "listen": "소음 추적", "dead": "재출전 대기"}
    mode_line = ", ".join("%s %s" % (mode_names.get(k, k), pct(v, mode_total)) for k, v in sorted(modes.items(), key=lambda kv: -kv[1]))
    arena_names = {"control_crossroads": "삼방 교차로", "control_citadel": "환상 요새", "control_waterway": "갈라진 수로"}
    by_arena = ", ".join("%s %d승 %d패" % (arena_names.get(k, k), v.get("win", 0), v.get("loss", 0)) for k, v in h["by_arena"].items())
    by_size = ", ".join("%s %d승 %d패" % (k.replace("v", "대"), v.get("win", 0), v.get("loss", 0)) for k, v in h["by_size"].items())
    pairs = h["mirrored_pairs"]
    changed = ", ".join("%s %.2f→%.2f초" % (c["case_id"].replace("release_", ""), c["duration_14"], c["duration_15"]) for c in reg["current_elimination_changed"])
    suite_lines = ["  %-24s %5d" % (k, v) for k, v in s.items()] + ["  %-24s %5d" % (k, v) for k, v in ui.items()]
    exe = a["exe"]
    lines = [
        "DVD BATTLE V1.5 검증 기록",
        "작성: %s (tools/package_release_15.py가 reports의 원자료에서 생성)" % datetime.date.today().isoformat(),
        "",
        "요약",
        "  자동 검사 %d항목 PASS, 실패 0. Windows 실제 실행(Godot 4.7.2, %s)." % (total, ctx["device"] or "Windows"),
        "  배포 EXE DVD_BATTLE_1.5.exe: %s bytes, SHA-256 %s, 파일·제품 버전 %s, PCK 내장." % (format(exe["bytes"], ","), exe["sha256"], exe["file_version"]),
        "  데스매치(개인전 2~12명, 전장 3종 절차 생성, 아이템 28종, 전용 AI)와 거점 장악 AI 개선을 추가했습니다.",
        "  V1.4 벽 처리로 재생하면 기존 섬멸전 12경기가 V1.4와 완전히 같습니다.",
        "  거점 AI는 행동 지표(스폰 앞 포탑 0, 헛된 포탑·시전 감소)가 뚜렷이 좋아졌으나, V1.4 AI와의 직접 대전 승률 차이는 유의하지 않습니다.",
        "",
        "1. 자동 검사 (Windows, tools/windows_release_15.ps1)",
        "  Stage A %s: 가져오기, 스크립트 검사 13종, 기준 전투 재생, EXE 내보내기, EXE 시작." % a["started"].replace("T", " "),
        "  Stage V %s: 격리 QA 복제본에서 실제 화면 UI 검사 3종과 화면 저장." % ctx["stage_v"]["started"].replace("T", " "),
        "  (Stage A의 화면 검사 단계는 QA 복제본 첫 가져오기가 캐시 없는 글꼴 가져오기 중 비정상 종료되어, 재시도와 캐시 복사를 추가한 Stage V로 다시 실행했습니다.)",
        "  Stage B %s: 캐시 없는 소스 복사본의 가져오기·시작·데스매치 검사." % b["started"].replace("T", " "),
    ] + suite_lines + [
        "  합계 %d / 실패 0. 각 로그에 SCRIPT ERROR와 ERROR 줄이 없습니다." % total,
        "",
        "2. 데스매치",
        "  전장 생성: 3종 × 시드 6개 = %d개 지도. 같은 시드 재생성 동일, 크기 3600×2200, 출발 지점 12곳 이상·간격 500 이상," % dm["maps_checked"],
        "    모든 출발 지점·아이템 위치가 가장 큰 몸집으로 도달 가능, 장애물이 지도 안, 시드별로 다른 배치. 가장 오래 걸린 생성 %d ms." % dm["mapgen_ms_max"],
        "  넓은 지도용 장애물 색인이 무작위 1500회 검사에서 선형 검사와 같은 결과를 냈습니다.",
        "  규칙: 12명 각자 다른 팀, 시작 보급 수, 처치·도움 인정(포탑 처치는 엔지니어), 6초 뒤 재출전과 보호, 공격 시 보호 해제,",
        "    사망 시 최고 등급 1개만 떨어뜨림, 중복 아이템 거절, 가득 찬 가방 교체, 필드 30개 상한, 목표 처치·시간 종료, 순위, 점수판과 처치 기록 일치,",
        "    같은 입력 재실행 결과 동일.",
        "  아이템 28종: 이름·문양 중복 없음, 문양이 내장 글꼴에 존재, 등급 8/6/6/4/4. 모든 효과를 실제 BattleSim에서 수치로 측정했습니다",
        "    (예: 흡혈 8%, 모래시계 -15%와 중첩 -25%, 처형 +18%, 가시 반사는 기본 공격만, 불사조 1회 부활, 천둥 4번째 적중, 왕관 5중첩 상한, 방패 -18%와 제어 1회 무효).",
        "  아이템 판단: 스킬 위주 영웅은 쿨감을, 기본 공격 영웅은 공속을 더 높게 평가하고, 원거리 영웅이 사거리 아이템을, 기본 공격이 없는 영웅은",
        "    적중 효과 아이템을 낮게 평가합니다. 중복 거절·전설 교체·약한 아이템 무시와 판단 이유 문구를 확인했습니다.",
        "  AI 경기 (8명, 150초 × 2경기, 숲의 마을): 분당 처치 %.1f, 분당 피해 %s, 아이템 획득 %d · 거절 %d, 최장 틱 %.1f ms." % (
            dm["ai_kills_per_min_8p"], format(dm["ai_damage_per_min_8p"], ","), dm["ai_item_picks"], dm["ai_item_skips"], dm["worst_tick_ms"]),
        "    의도 분포(1초 표본): %s." % mode_line,
        "  캐시 없는 복사본(Stage B)의 같은 검사도 %d항목 PASS였고 AI 경기 지표가 Stage A와 같았습니다(측정 시간 값 제외)." % ctx["fresh_dm_passed"],
        "  UI (deathmatch_ui_15): 설정 기본값, 인원 증감, 전장·시드·목표·시간 적용, 아이템 도감, 12명 전투, 점수 칩, 시야 선택, 패널 4종, AI 판단 문구,",
        "    참가자 시야와 안개, 목표 처치 종료와 결과 화면을 실제 화면에서 확인했습니다. 상세는 reports/UI_VISUAL_1.5.txt.",
        "",
        "3. 거점 장악 AI (V1.5 = tactician, V1.4 = tactician14)",
        "  Windows conquest_15: 양 팀에 엔지니어가 있는 5대5 2경기(각 120초)에서 적 없이 자기 스폰 근처에 세운 포탑 — V1.5 %d개 중 %d, V1.4 %d개 중 %d." % (
            cq["turrets"]["tactician"]["turrets"], cq["turrets"]["tactician"]["idle_spawn_turrets"], cq["turrets"]["tactician14"]["turrets"], cq["turrets"]["tactician14"]["idle_spawn_turrets"]),
        "    모든 영웅이 거점 명령을 받는지, V1.4 비교 AI가 이전 계획기를 쓰는지도 확인했습니다.",
        "  아래 평가는 tools/ai_eval_15로 Linux 헤드리스 Godot 4.7.2에서 실행했고 원자료는 reports/ai_eval_15에 있습니다.",
        "  엔지니어 포함 5대5, 같은 AI끼리 6경기씩 (conquest_probe_15.gd):",
        "    포탑 설치                      V1.4 %4d   V1.5 %4d" % (ot["turrets"], nt["turrets"]),
        "    스폰 450 이내 설치             V1.4 %4d (%s)   V1.5 %4d (%s)" % (ot["turret_spawnside"], pct(ot["turret_spawnside"], ot["turrets"]), nt["turret_spawnside"], pct(nt["turret_spawnside"], nt["turrets"])),
        "    피해를 한 번도 못 준 포탑      V1.4 %4d (%s)   V1.5 %4d (%s)" % (ot["turret_no_damage"], pct(ot["turret_no_damage"], ot["turrets"]), nt["turret_no_damage"], pct(nt["turret_no_damage"], nt["turrets"])),
        "    거점에서 300 넘게 떨어진 포탑  V1.4 %4d (%s)   V1.5 %4d (%s)" % (ot["turret_far_obj"], pct(ot["turret_far_obj"], ot["turrets"]), nt["turret_far_obj"], pct(nt["turret_far_obj"], nt["turrets"])),
        "    750 안에 적이 없는 스킬 시전   V1.4 %4d / %d (스폰 근처 %d)   V1.5 %4d / %d (스폰 근처 %d)" % (ot["casts_no_enemy"], ot["casts"], ot["casts_no_enemy_spawn"], nt["casts_no_enemy"], nt["casts"], nt["casts_no_enemy_spawn"]),
        "    수적 열세 사망 비율            V1.4 %s (%d/%d)   V1.5 %s (%d/%d)" % (pct(ot["deaths_outnumbered"], ot["deaths"]), ot["deaths_outnumbered"], ot["deaths"], pct(nt["deaths_outnumbered"], nt["deaths"]), nt["deaths_outnumbered"], nt["deaths"]),
        "    거점 안 체류 비율              V1.4 %s   V1.5 %s" % (pct(ot["on_point_samples"], ot["alive_samples"]), pct(nt["on_point_samples"], nt["alive_samples"])),
        "    전투 밖 거점 밖 정지 표본      V1.4 %s   V1.5 %s" % (pct(ot["far_idle"], ot["alive_samples"]), pct(nt["far_idle"], nt["alive_samples"])),
        "    (수적 열세: 사망 순간 520 안의 적이 아군보다 2명 이상 많음. 체류·정지는 1초 표본.)",
        "  고정 조합 미러 3경기씩 (assignment_probe_15.gd):",
        "    팀당 경기당 담당 거점 변경     V1.4 %.1f   V1.5 %.1f (그중 양 끝 거점 사이 이동 V1.4 %.1f, V1.5 %.1f)" % (asg_o["flips_per_team_match"], asg_n["flips_per_team_match"], asg_o["far_flips_per_team_match"], asg_n["far_flips_per_team_match"]),
        "    회복 구역 이동 시간 비율       V1.4 %.1f%%   V1.5 %.1f%%" % (asg_o["heal_trip_pct"], asg_n["heal_trip_pct"]),
        "    거점 안 체류 비율              V1.4 %.1f%%   V1.5 %.1f%%" % (asg_o["on_point_pct"], asg_n["on_point_pct"]),
        "  벽 접촉 (기준 거점 3경기, wall_band_15.gd): 벽 충돌 여유 안에 있던 영웅 틱 V1.4 처리 %d → V1.5 %d, 이동 명령 중 제자리 정지 틱 %d → %d." % (
            wb["legacy"]["control"]["band_ticks"], wb["current"]["control"]["band_ticks"], wb["legacy"]["control"]["frozen_ticks"], wb["current"]["control"]["frozen_ticks"]),
        "    Windows conquest_15도 V1.4 처리의 벽 고착을 재현하고 V1.5에서 벽을 따라 이동하는 것을 확인했습니다.",
        "  직접 대전 (h2h_15.gd): %d조합을 같은 시드로 진영을 바꾸어 %d경기. V1.5 %d승 %d패 (%s; %s)." % (
            h["compositions"], h["matches"], h["a_outcomes"].get("win", 0), h["a_outcomes"].get("loss", 0), by_size, by_arena),
        "    같은 조합 두 경기 모두 승 %d, 1승 1패 %d, 모두 패 %d. 평균 점수 차 %+.1f점(300점 선승). 양측 부호 검정 p = %.2f." % (
            pairs.get("both_won", 0), pairs.get("split", 0), pairs.get("both_lost", 0), h["mean_score_margin_a_minus_b"], h["sign_test_p_two_sided"]),
        "    → 승률 향상은 통계적으로 확인되지 않았습니다. 환상 요새에서는 오히려 열세였습니다. 이번 개선은 사용자가 지적한 비합리적 행동을",
        "      없애는 데 초점을 두었고, 그 행동 지표는 위와 같이 개선되었습니다. 저장된 32경기 중 3경기를 릴리스 코드로 다시 실행해(Linux) 결과가 같음을 확인했습니다.",
        "",
        "4. 기존 전투 회귀 (Windows, 기준 15경기: 섬멸전 12 + 거점 3)",
        "  V1.4 벽 처리(--legacy_walls=1): 섬멸전 %d/12가 V1.4 최종 상태 서명과 완전히 같습니다." % reg["legacy_elimination_equal"],
        "  V1.5 벽 처리: 섬멸전 %d/12 동일. 변경 %d경기(%s)는 진행 시간만 달라졌고 승자는 같습니다." % (reg["current_elimination_equal"], len(reg["current_elimination_changed"]), changed),
        "  거점 3경기는 AI 변경으로 진행이 달라지는 것이 의도된 결과입니다. 모든 경기에서 불변식 오류가 없습니다.",
        "  캐릭터·스킬 수치(scripts/data/char_data.gd)는 바꾸지 않았습니다. 전투 코어의 변경은 데스매치 전용 분기, 넓은 지도용 장애물 색인,",
        "    벽 접촉 수정입니다. V1.4 벽 처리로 재생한 기준 섬멸전이 모두 V1.4와 같으므로, 이 경기들의 결과를 바꾼 것은 벽 접촉 수정뿐입니다.",
        "",
        "5. 배포와 보존",
        "  EXE 헤드리스 시작(종료 코드 %d), 실제 렌더링 데스매치 실행(종료 코드 %d)과 화면 저장(3440×1440 전체 화면)." % (a["exported_headless_start_exit"], a["exported_render_exit"]),
        "  모든 Windows 단계 전후로 사용자 설정 파일 해시가 같았습니다(QA 검사는 별도 사용자 디렉터리 사용).",
        "  캐시 없는 소스 복사본(D:\\DVD_BATTLE_1.5_FRESH_IMPORT): .godot 없이 가져오기 %.1f초, 시작 %.1f초, 데스매치 검사 통과, 소스 %d개 SHA-256 일치." % (
            ctx["fresh_import_s"], b["steps"]["fresh_startup_15.log"]["seconds"], ctx["fresh_files"]),
        "  EXE 내보내기 이후 게임 소스(scripts, scenes, shaders, assets, project.godot, export_presets.cfg)가 바뀌지 않았음을 수정 시각으로 확인했습니다.",
        "  V1.4 EXE와 ZIP 2개의 SHA-256이 V1.4 배포 기록과 같습니다.",
        "  ZIP은 CRC 검사와 원본 파일별 SHA-256 비교를 통과했습니다. 해시는 DVD_BATTLE_1.5_SHA256.txt에 있습니다.",
        "  V1.4 대비 소스 변경: 추가 %d, 수정 %d, 삭제 %d개 파일(reports 제외, 목록은 release_manifest_15.json)." % (len(ctx["diff"]["added"]), len(ctx["diff"]["changed"]), len(ctx["diff"]["removed"])),
        "",
        "6. 제한과 참고",
        "  12명 데스매치는 AI 12개가 동시에 판단해 틱당 약 6~7ms(Windows 표시값)가 걸립니다. 1600×900 1배속에서 약 30 FPS였고,",
        "    4배속에서는 9~11 FPS까지 떨어졌습니다. 8명 참가자 시야는 약 50 FPS(3440×1440 전체 화면 43 FPS)였습니다.",
        "  2~3명 경기는 넓은 전장에서 서로를 찾는 데 시간이 걸립니다. %d초 경기 전장별 1회(Linux, dm_small_15.gd)의 처치 수: 2명 %s, 4명 %s." % (
            int(sm[2]["duration"]), "/".join(str(k) for k in sm[2]["kills"]), "/".join(str(k) for k in sm[4]["kills"])),
        "  3장의 tools/ai_eval_15 평가는 Linux에서 실행했습니다. 전투 시뮬레이션은 같은 플랫폼에서는 재실행 결과가 같지만, 플랫폼 사이에는",
        "    수학 함수의 부동소수점 결과 차이(추정)로 경기가 달라질 수 있습니다. 기준 %d경기를 V1.4 벽 처리로 Linux에서 재생하면 Windows와 최종 상태가" % pf["cases"],
        "    같은 경기는 %d개, 진행 시간이 다른 경기 %d개, 승자가 다른 경기 %d개(%s)였습니다(reports/ai_eval_15/linux_legacy_walls_replay.jsonl)." % (
            len(pf["same_final_state"]), len(pf["different_duration"]), len(pf["different_winner"]), ", ".join(k.replace("release_", "") for k in pf["different_winner"]) or "없음"),
        "    따라서 3장의 Linux 수치는 같은 코드의 Linux 표본입니다. V1.4 기록과의 회귀 비교(4장)와 배포 검사는 모두 Windows에서 수행했습니다.",
        "  AI 대 AI 결과는 작은 표본의 기술 통계입니다. 모든 조합·전장에서의 승률이나 강도를 보장하지 않습니다.",
        "  재실행: tools/RUN_WIN15_A.bat → RUN_WIN15_V.bat → RUN_WIN15_B.bat → python tools/package_release_15.py. AI 평가 명령은 각 도구 머리말에 있습니다.",
        "",
    ]
    return "\n".join(lines)


def archive(path, files, parent):
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as bundle:
        for file in files:
            bundle.write(file, file.relative_to(parent).as_posix())
    with zipfile.ZipFile(path) as bundle:
        assert bundle.testzip() is None
        names = bundle.namelist()
        assert len(names) == len(files)
        for file in files:
            digest = hashlib.sha256()
            with bundle.open(file.relative_to(parent).as_posix()) as member:
                for block in iter(lambda: member.read(1 << 20), b""):
                    digest.update(block)
            assert digest.hexdigest() == sha(file), "zip content differs: " + str(file)
    return len(files)


def main():
    stage_a, stage_v, stage_b, fresh_files, device = stage_checks()
    counts, ui = suites()
    dm = read("deathmatch_15.json")
    fresh_dm = json.loads((FRESH / "reports" / "deathmatch_15.json").read_text(encoding="utf-8-sig"))
    timing = {"mapgen_ms_max", "worst_tick_ms"}
    assert fresh_dm["status"] == "PASS" and fresh_dm["passed"] == dm["passed"]
    assert {k: v for k, v in fresh_dm["metrics"].items() if k not in timing} == {k: v for k, v in dm["metrics"].items() if k not in timing}
    conquest = read("conquest_15.json")["metrics"]
    reg = regression()
    evaluation = ai_evaluation()
    preserved = preserved_14()
    diff = diff_14()
    assert "scripts/data/char_data.gd" not in diff["changed"], "roster data changed"
    platform = platform_replay()
    small = small_matches()
    for shot in SHOTS:
        assert (REPORTS / "visual_15" / (shot + ".png")).is_file(), shot
    fresh_import_s = next(s["seconds"] for k, s in stage_b["steps"].items() if k.startswith("fresh_import_15") and s["ok"])
    ctx = {"suites": counts, "ui": ui, "dm": dm["metrics"], "conquest": conquest, "eval": evaluation, "regression": reg,
           "stage_a": stage_a, "stage_v": stage_v, "stage_b": stage_b, "device": device, "fresh_files": fresh_files,
           "fresh_dm_passed": fresh_dm["passed"], "fresh_import_s": fresh_import_s, "diff": diff, "platform": platform, "small": small}
    with open(ROOT / "VALIDATION_1.5_KO.txt", "w", encoding="utf-8-sig", newline="\r\n") as file:
        file.write(validation_text(ctx))
    for name in ["README_KO.txt", "CHANGELOG_1.5_KO.txt", "THIRD_PARTY_NOTICES.txt", "reports/UI_VISUAL_1.5.txt"]:
        assert (ROOT / name).is_file(), name
    manifest = {"version": "GD-1.5", "file_version": "1.5.0.0", "engine": "Godot 4.7.2", "platform": "Windows x86_64",
                "packaged_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(), "render_device": device,
                "executable": {"name": EXE.name, "bytes": EXE.stat().st_size, "sha256": sha(EXE), "embedded_pck": True},
                "assertions_passed": sum(counts.values()) + sum(ui.values()), "suites": counts, "ui_suites": ui,
                "windows_stages": {k: {"started": s["started"], "finished": s.get("finished")} for k, s in (("A", stage_a), ("V", stage_v), ("B", stage_b))},
                "cache_free_source_import": {"folder": FRESH.name, "files_compared": fresh_files, "mismatches": 0},
                "deathmatch_metrics": dm["metrics"], "conquest_suite_metrics": conquest, "battle_regression": reg,
                "ai_evaluation": evaluation, "small_deathmatch": small, "linux_windows_replay": platform, "preserved_v14_sha256": preserved, "changes_since_v14": diff,
                "source_files_sha256": {p.relative_to(ROOT).as_posix(): sha(p) for p in source_files() if p.name != "release_manifest_15.json"}}
    (REPORTS / "release_manifest_15.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    for name in ["README_KO.txt", "CHANGELOG_1.5_KO.txt", "VALIDATION_1.5_KO.txt", "THIRD_PARTY_NOTICES.txt"]:
        shutil.copy2(ROOT / name, RELEASE / name)
    shutil.copy2(REPORTS / "release_manifest_15.json", RELEASE / "release_manifest_15.json")
    release_files = sorted(p for p in RELEASE.iterdir() if p.is_file())
    win_count = archive(WIN_ZIP, release_files, PARENT)
    src_count = archive(SRC_ZIP, source_files(), PARENT)
    SHA_FILE.write_text("".join("%s  %s\n" % (sha(p), p.name) for p in [EXE, WIN_ZIP, SRC_ZIP]), encoding="ascii")
    print(json.dumps({"assertions": manifest["assertions_passed"], "windows_zip_files": win_count, "source_zip_files": src_count,
                      "artifacts": [{"path": str(p), "bytes": p.stat().st_size, "sha256": sha(p)} for p in [EXE, WIN_ZIP, SRC_ZIP]]},
                     ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
