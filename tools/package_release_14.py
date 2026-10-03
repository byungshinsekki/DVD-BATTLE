"""Package verified V1.4 source and Windows binaries with reproducible evidence."""
import datetime
import hashlib
import json
import re
import shutil
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPORTS = ROOT / "reports"
RELEASE = ROOT.parent / "DVD_BATTLE_1.4_RELEASE"


def read(name):
    return json.loads((REPORTS / name).read_text(encoding="utf-8-sig"))


def sha(path):
    with path.open("rb") as file:
        return hashlib.file_digest(file, "sha256").hexdigest()


def archive(path, files, parent):
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as bundle:
        for file in sorted(files):
            bundle.write(file, file.relative_to(parent).as_posix())
    with zipfile.ZipFile(path) as bundle:
        assert bundle.testzip() is None


def main():
    comparison = read("release_comparison_14.json")
    assert comparison["status"] == "PASS" and not comparison["failures"]
    assert comparison["evaluated_sources_sha256"] == {name: sha(ROOT / "scripts/ai" / name) for name in ["draft_director.gd", "draft_search.gd"]}
    regression = read("battle_regression_14.json")
    assert regression["status"] == "PASS" and regression["matches"] == 15
    suites = {}
    for name in ["mechanics_regression", "control_maps_13", "control_rules_13", "control_ai_13", "control_information_13",
                 "skill_preview_14", "preview_isolation_14", "draft_14", "draft_audit_14", "draft_isolation_14", "preview_ui_14", "draft_policy_ui_14"]:
        report = read(name + ".json")
        assert "failed" in report or "failures" in report, name
        failures = report["failed"] if "failed" in report else report["failures"]
        assert report["status"] == "PASS" and not failures, name
        suites[name] = report["passed"]
    info_log = (REPORTS / "ai_information_122.log").read_text(encoding="utf-8-sig")
    info = json.loads(re.search(r"AI_INFORMATION_REGRESSION (\{.*\})", info_log).group(1))
    assert info["passed"] == 46 and not info["failed"]
    suites["legacy_information"] = info["passed"]
    for name in ["windows_export_14", "exported_startup_14", "exported_preview_14", "final_import_14",
                 "skill_preview_14", "preview_isolation_14", "draft_14", "draft_isolation_14", "draft_validation_14", "draft_holdout_14",
                 "draft_validation_matches_14", "draft_holdout_matches_14", "regression_matches_14", "fresh_import_14", "fresh_startup_14"]:
        content = (REPORTS / (name + ".log")).read_text(encoding="utf-8-sig")
        assert not re.search(r"SCRIPT ERROR|ERROR:", content), name
    assert "SHOT saved" in (REPORTS / "exported_preview_14.log").read_text(encoding="utf-8-sig")
    old_exe = ROOT.parent / "DVD_BATTLE_1.3_RELEASE/DVD_BATTLE_1.3.exe"
    assert sha(old_exe) == "fd5be4acf67b3258b2c4904f482fde509fc3a976c07b1773c1755a7e5b303fa4"
    unchanged = []
    for folder in ("scripts/core", "scripts/data", "scripts/ai"):
        for path in (ROOT / folder).glob("*.gd"):
            if path.name in ("draft_director.gd", "draft_search.gd"):
                continue
            old = ROOT.parent / "DVD_BATTLE_1.3" / path.relative_to(ROOT)
            assert old.exists() and sha(path) == sha(old), str(path)
            unchanged.append(path.relative_to(ROOT).as_posix())
    exe = RELEASE / "DVD_BATTLE_1.4.exe"
    source_files = [p for folder in ["scripts", "scenes", "shaders"] for p in (ROOT / folder).rglob("*") if p.is_file()]
    source_files += [ROOT / "project.godot", ROOT / "export_presets.cfg"]
    fresh_root = ROOT.parent / "DVD_BATTLE_1.4_FRESH_IMPORT"
    for path in source_files:
        if path.suffix == ".gd" or path.name == "project.godot":
            assert sha(path) == sha(fresh_root / path.relative_to(ROOT)), "Source changed after clean import: " + str(path)
    preview = read("skill_preview_14.json")
    manifest = {"version": "GD-1.4", "file_version": "1.4.0.0", "engine": "Godot 4.7.2",
                "packaged_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
                "executable_sha256": sha(exe), "executable_bytes": exe.stat().st_size, "embedded_pck": True,
                "assertions_passed": sum(suites.values()), "suites": suites,
                "cache_free_source_import_and_startup": True,
                "preview_active": preview["active"], "preview_passive": preview["passive"], "roster_count": 22,
                "draft_comparison": {key: comparison[key] for key in ["drafts", "matches", "outcomes_for_v14", "pick_time_ms", "method", "limitations"]},
                "unchanged_battle_matches": 15, "same_process_preview_isolation_matches": 4, "same_process_draft_isolation_matches": 2,
                "previous_executable_preserved_sha256": sha(old_exe), "unchanged_combat_files": unchanged,
                "source_files_sha256": {p.relative_to(ROOT).as_posix(): sha(p) for p in sorted(source_files)}}
    (REPORTS / "release_manifest_14.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    outcomes = comparison["outcomes_for_v14"]["all"]
    lines = ["DVD BATTLE V1.4 검증 기록", "", f"자동 검사 {sum(suites.values())}항목 PASS", ""]
    lines += [f"  {name}: {count}" for name, count in suites.items()]
    lines += ["", f"미리보기: 22명, 액티브 {preview['active']}개, 패시브 {preview['passive']}개.",
              "모든 항목은 실제 BattleSim에서 시전·공격·피해·회복·상태·소환 등의 실효과를 검증했습니다.",
              "공유 캐릭터/스킬/전장 정의 불변, 재시작 결정성, 해제 후 호출, 설정·전적 불변을 검사했습니다.",
              "같은 프로세스에서 모든 미리보기 실행 전후 섬멸·거점 경기의 최종 상태가 일치했습니다(총 4회).",
              "드래프트 내부 모의전 실행 전후에도 같은 프로세스의 실제 경기 최종 상태가 일치했고 설정·전적이 보존됐습니다(비교 경기 2회).",
              "기존 전투 15회가 V1.3 기준과 모두 같은 최종 상태를 재현했습니다. 22명과 전장 15개가 포함됩니다.",
              "", "드래프트 비교", "검증용 12드래프트와 별도 홀드아웃 12드래프트. 각 조합을 같은 시드로 진영을 바꾸어 총48회 대전했습니다.",
              "섬멸·거점 모드, 1v1·3v3·5v5, 양측 선픽을 포함합니다. 전투 AI와 캐릭터 수치는 양쪽 동일합니다.",
              f"V1.4 조합 결과: {outcomes.get('wins', 0)}승 {outcomes.get('losses', 0)}패 {outcomes.get('draws', 0)}무.",
              "작고 상관된 표본의 기술 통계입니다. 모든 조합에 대한 일반 승률이나 강도 향상률을 보장하지 않습니다.",
              "AI 가중치는 이 비교 결과에 맞춰 조정하지 않았습니다. 입력과 원자료를 reports에 보존했습니다.",
              "초기48경기에서 발견한 탐색 경계의 미완성 조합 평가 문제를 수정한 뒤, 기존 검증 입력과 새 홀드아웃 입력으로 다시 검사했습니다.",
              "수정 전48경기·이전 판단 엔진 코드는 reports/pre_completion_14에 보존했습니다.",
              "총 평가/후보별 평가 예산, 공통 완료 깊이, 프레임 분할 결정성, 취소, 모드 반응, 실제 전투 비교를 검사했습니다.",
              "", "배포", "Godot 4.7.2 / Windows x86_64 / 파일 버전1.4.0.0 / PCK내장.",
              "배포 EXE 메뉴 시작 및 실제 도감 미리보기 화면 저장을 확인했습니다. ZIP CRC 검사도 통과했습니다.",
              "캐시가 없는 별도 소스 복사본의 Godot 가져오기와 메뉴 시작이 오류 없이 완료됐고 소스 SHA-256도 일치합니다.",
              "기존 V1.3 EXE와 전투 코어·로스터·전투AI 파일은 SHA-256 비교로 보존을 확인했습니다.",
              "시각 및 UI 검증의 상세 조건·결과·제한은 reports/UI_VISUAL_1.4.txt를 참조하십시오.",
              "재실행 도구는 README_KO.txt 및 tools/verify_release.ps1을 참조하십시오.", ""]
    (ROOT / "VALIDATION_1.4_KO.txt").write_text("\n".join(lines), encoding="utf-8-sig")
    for name in ["README_KO.txt", "CHANGELOG_1.4_KO.txt", "VALIDATION_1.4_KO.txt", "THIRD_PARTY_NOTICES.txt"]:
        shutil.copy2(ROOT / name, RELEASE / name)
    shutil.copy2(REPORTS / "release_manifest_14.json", RELEASE / "release_manifest_14.json")
    win_zip = ROOT.parent / "DVD_BATTLE_1.4_WINDOWS.zip"
    src_zip = ROOT.parent / "DVD_BATTLE_1.4_SOURCE.zip"
    archive(win_zip, [p for p in RELEASE.iterdir() if p.is_file()], ROOT.parent)
    files = [p for p in ROOT.rglob("*") if p.is_file() and not ({".godot", "__pycache__"} & set(p.relative_to(ROOT).parts))
             and p.suffix not in [".tmp", ".bak", ".pyc"] and p.name != "user_settings_before_14.sha256"]
    archive(src_zip, files, ROOT.parent)
    (ROOT.parent / "DVD_BATTLE_1.4_SHA256.txt").write_text("\n".join(f"{sha(p)}  {p.name}" for p in [exe, win_zip, src_zip]) + "\n", encoding="ascii")
    print(json.dumps({"assertions": sum(suites.values()), "validation_matches": 69, "draft_outcomes": outcomes,
                      "artifacts": [{"path": str(p), "bytes": p.stat().st_size, "sha256": sha(p)} for p in [exe, win_zip, src_zip]]}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
