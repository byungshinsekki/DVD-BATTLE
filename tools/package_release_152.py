"""Validate and package DVD BATTLE V1.5.2 Developer Play for three platforms.

Run ONLY after build_multiplatform_152.py, validate_152.py, map/environment/AI
audits and the final exported Windows smoke test have passed:
    python tools/package_release_152.py

The source ZIP includes current V1.5.2 QA evidence by default. Pass
--include-historical-reports to include older releases' report directories too.
This tool never builds, launches the game, changes Git or writes older releases.
"""
from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import sys
import tarfile
import zipfile

sys.dont_write_bytecode = True

from build_multiplatform_152 import (  # noqa: E402
    ROOT, RELEASE, REPORTS, PLATFORMS, inspect_binary, sha, source_hashes,
)

VERSION = "1.5.2"
PREFIX = "DVD_BATTLE_1.5.2"
PARENT = ROOT.parent
VALIDATION = ROOT / "VALIDATION_1.5.2_KO.txt"
MANIFEST = REPORTS / "release_manifest.json"
SKIP_DIRS = {".git", ".godot", ".claude", "zz_work", "zz_diag", "__pycache__"}
SKIP_SUFFIXES = {".tmp", ".bak", ".pyc", ".partial"}
CURRENT_REPORT_DIRS = {
    "regression_152", "developer_152", "maps_152", "ai_audit_152", "multiplatform_152",
}
REQUIRED_SUITES = (
    "mechanics_122", "skill_preview_14", "preview_isolation_14", "deathmatch_15",
    "codex_data_151", "developer_152", "codex_ui_151", "deathmatch_ui_15",
    "preview_ui_14", "control_ui_13",
)
AUDITS = {
    "maps_152": ROOT / "reports/maps_152/maps_152.json",
    "environment_152": ROOT / "reports/environment_152.json",
    "ai_audit_152": ROOT / "reports/ai_audit_152/audit.json",
    "ai_matches_152": ROOT / "reports/ai_audit_152/matches.json",
    "map_battles_152": ROOT / "reports/maps_152/battles.json",
    "control_maps_13": ROOT / "reports/regression_152/control_maps_13.json",
    "control_rules_13": ROOT / "reports/regression_152/control_rules_13.json",
    "control_ai_13": ROOT / "reports/regression_152/control_ai_13.json",
    "conquest_15": ROOT / "reports/regression_152/conquest_15.json",
}
ARCHIVES = {
    "windows": PARENT / f"{PREFIX}_WINDOWS.zip",
    "linux": PARENT / f"{PREFIX}_LINUX_X86_64.tar.gz",
    "macos": PARENT / f"{PREFIX}_MACOS_UNIVERSAL.zip",
    "source": PARENT / f"{PREFIX}_SOURCE.zip",
}
ERROR_PATTERN = re.compile(r"(?m)^.*(?:SCRIPT ERROR|ERROR:).*$")


def require(condition, message):
    # Unlike assert, release safety checks remain enabled under python -O.
    if not condition:
        raise RuntimeError(message)


def writable(path):
    """Allow only this project, this release folder and this version's outputs."""
    target = Path(path)
    require(not target.is_symlink(), f"Refusing output symlink: {target}")
    resolved = target.resolve()
    project = ROOT.resolve()
    release = (PARENT / f"{PREFIX}_RELEASE").resolve()
    allowed_file = resolved.parent == PARENT.resolve() and resolved.name in {
        *(p.name for p in ARCHIVES.values()),
        *(p.name + ".partial" for p in ARCHIVES.values()),
        f"{PREFIX}_SHA256.txt",
    }
    require(project in resolved.parents or release in resolved.parents or allowed_file,
            f"Refusing write outside V1.5.2 outputs: {resolved}")
    return resolved


def read(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def write_json(path, value):
    writable(path).write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def clean_log(path):
    content = Path(path).read_text(encoding="utf-8-sig", errors="replace")
    require(not ERROR_PATTERN.search(content), f"Engine error in {path}")
    return content


def failed_count(report):
    failures = report.get("failed", report.get("failures", []))
    return len(failures) if isinstance(failures, (list, dict)) else int(failures or 0)


def passed_count(report, label):
    require(report.get("status", "PASS") == "PASS" and failed_count(report) == 0,
            f"Failed report: {label}")
    value = report.get("passed")
    require(isinstance(value, int) and not isinstance(value, bool) and value >= 0,
            f"Missing numeric assertion count: {label}")
    return value


def current_test_hashes():
    return {p.relative_to(ROOT).as_posix(): sha(p)
            for folder in ("scripts", "tests") for p in sorted((ROOT / folder).rglob("*.gd"))}


def suite_count(name, folder):
    content = clean_log(folder / (name + ".log"))
    report_path = folder / (name + ".json")
    count_from_json = passed_count(read(report_path), name) if report_path.is_file() else None
    # Some legacy scripts write a differently named JSON file, but always
    # emit their fresh result on stdout. Never fall back to an old root report.
    for line in reversed(content.splitlines()):
        start = line.find("{")
        if start >= 0:
            try:
                report = json.loads(line[start:])
            except json.JSONDecodeError:
                continue
            if isinstance(report, dict) and "passed" in report:
                count = passed_count(report, name)
                require(count_from_json is None or count == count_from_json,
                        f"Fresh log and JSON assertion counts differ: {name}")
                return count
    match = re.search(r"\b(\d+)\s+PASS\s*/\s*(\d+)\s+FAIL\b", content)
    if match is None:
        match = re.search(r"\bPASS\s+passed=(\d+)\s+failures=(\d+)\b", content)
    require(match is not None and int(match[2]) == 0, f"Missing PASS count in fresh suite log: {name}")
    count = int(match[1])
    require(count_from_json is None or count == count_from_json,
            f"Fresh log and JSON assertion counts differ: {name}")
    return count


def verify_evidence():
    require(ROOT.name == PREFIX, "Run from the DVD_BATTLE_1.5.2 source tree")
    require(RELEASE.resolve() == (PARENT / f"{PREFIX}_RELEASE").resolve(), "Wrong release folder")
    require(sys.flags.optimize == 0, "Do not use python -O; the build binary inspector uses assertions")
    current = source_hashes()
    exports = {}
    for platform, (_, relative) in PLATFORMS.items():
        report = read(REPORTS / f"export_{platform}.json")
        binary = RELEASE / relative
        require(report.get("status") == "PASS" and report.get("version") == VERSION,
                f"Missing successful V1.5.2 export: {platform}")
        require(report.get("exit_code") == 0 and not report.get("errors"), f"Failed export: {platform}")
        require(report.get("runtime_sources_sha256") == current, f"Stale {platform} build; export again")
        require(report.get("sha256") == sha(binary), f"Modified {platform} binary")
        require(Path(report["path"]).resolve() == binary.resolve(), f"Unexpected {platform} binary path")
        clean_log(REPORTS / f"export_{platform}.log")
        inspect_binary(platform, binary)
        exports[platform] = {key: value for key, value in report.items() if key != "runtime_sources_sha256"}

    smoke = read(REPORTS / "windows_smoke.json")
    require(smoke.get("status") == "PASS" and smoke.get("player_settings_unchanged") is True,
            "Windows smoke or player-settings preservation did not pass")
    require(not smoke.get("errors"), "Windows smoke reports engine errors")
    require(smoke.get("executable_sha256") == exports["windows"]["sha256"], "Windows smoke used another EXE")

    regression_dir = ROOT / "reports/regression_152"
    qa = read(regression_dir / "summary.json")
    require(qa.get("version") == VERSION and qa.get("status") == "PASS", "Isolated QA did not pass")
    require(qa.get("sources_unchanged_during_run") is True, "Sources changed during QA")
    require(qa.get("source_hashes") == current_test_hashes(), "QA scripts or runtime sources are stale")
    for name in ("import", *REQUIRED_SUITES):
        suite = qa.get("suites", {}).get(name, {})
        require(suite.get("status") == "PASS" and suite.get("exit") == 0 and not suite.get("errors"),
                f"Missing successful isolated suite: {name}")
    clean_log(regression_dir / "import.log")
    counts = {name: suite_count(name, regression_dir) for name in REQUIRED_SUITES}
    audits = {}
    for name, path in AUDITS.items():
        report = read(path)
        counts[name] = passed_count(report, name)
        audits[name] = {"path": path.relative_to(ROOT).as_posix(), "sha256": sha(path), "passed": counts[name]}
        require(path.stat().st_mtime >= max((ROOT / "scripts/core/arena_env.gd").stat().st_mtime,
                                          (ROOT / "scripts/core/arena.gd").stat().st_mtime) - 2.0
                or name in {"maps_152", "control_maps_13", "control_rules_13", "control_ai_13", "conquest_15"},
                f"Audit predates final environment fixes: {name}")
    for name in ("ai_information_122", "control_information_13", "draft_14", "draft_audit_14", "draft_isolation_14"):
        counts[name] = suite_count(name, ROOT / "reports/ai_audit_152")
    require(read(AUDITS["map_battles_152"]).get("battle_count") == 18, "Expected all eighteen map smoke battles")
    matches = read(AUDITS["ai_matches_152"])
    require(len(matches.get("matches", [])) >= 9, "Expected nine integration matches across three rulesets")
    return current, exports, smoke, qa, counts, audits, len(matches["matches"])


def source_files(include_historical_reports=False):
    for base, dirs, files in os.walk(ROOT, followlinks=False):
        dirs[:] = sorted(name for name in dirs if name not in SKIP_DIRS and not (Path(base) / name).is_symlink())
        for name in sorted(files):
            path = Path(base) / name
            if path.is_symlink() or path.suffix.lower() in SKIP_SUFFIXES:
                continue
            rel = path.relative_to(ROOT)
            if name.startswith("user_settings_before_") or name in {"export_credentials.cfg", ".env"}:
                continue
            if rel.as_posix() == "reports/multiplatform_152/packages.json":
                # Written after the ZIP; including an older copy is misleading.
                continue
            if rel.parts[0] == "reports" and not include_historical_reports:
                current_dir = len(rel.parts) > 2 and rel.parts[1] in CURRENT_REPORT_DIRS
                current_name = re.search(r"(?:^|[_-])152(?:[_.-]|$)|1\.5\.2", name) is not None
                if not current_dir and not current_name:
                    continue
            yield path


def stream_sha(stream):
    return hashlib.file_digest(stream, "sha256").hexdigest()


def make_zip(output, members):
    staging = writable(str(output) + ".partial")
    names = [name for _, name in members]
    require(len(names) == len(set(names)), f"Duplicate archive members: {output}")
    with zipfile.ZipFile(staging, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for path, name in members:
            archive.write(path, name)
    with zipfile.ZipFile(staging) as archive:
        require(archive.testzip() is None and archive.namelist() == names, f"ZIP integrity failed: {output}")
        for path, name in members:
            with archive.open(name) as content:
                require(stream_sha(content) == sha(path), f"ZIP content mismatch: {name}")
    os.replace(staging, writable(output))


def make_linux(output, binary, docs):
    staging = writable(str(output) + ".partial")
    entries = [binary, *docs]
    prefix = f"{PREFIX}_LINUX_X86_64/"
    with tarfile.open(staging, "w:gz", compresslevel=6) as archive:
        for path in entries:
            info = archive.gettarinfo(str(path), prefix + path.name)
            info.mode = 0o755 if path == binary else 0o644
            info.uid = info.gid = 0
            info.uname = info.gname = ""
            with path.open("rb") as stream:
                archive.addfile(info, stream)
    with tarfile.open(staging, "r:gz") as archive:
        require(archive.getnames() == [prefix + path.name for path in entries], "Unexpected Linux archive members")
        for path in entries:
            info = archive.getmember(prefix + path.name)
            require(info.isfile() and info.mode == (0o755 if path == binary else 0o644), f"Wrong tar mode: {path.name}")
            with archive.extractfile(info) as content:
                require(stream_sha(content) == sha(path), f"Linux archive content mismatch: {path.name}")
    os.replace(staging, writable(output))


def make_macos(output, exported_zip, docs):
    staging = writable(str(output) + ".partial")
    shutil.copy2(exported_zip, staging)
    with zipfile.ZipFile(staging, "a", zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for path in docs:
            require(path.name not in archive.namelist(), f"macOS documentation name collision: {path.name}")
            info = zipfile.ZipInfo(path.name)
            info.create_system = 3
            info.external_attr = 0o100644 << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, path.read_bytes())
    inspect_binary("macos", staging)
    with zipfile.ZipFile(exported_zip) as original, zipfile.ZipFile(staging) as archive:
        require(archive.testzip() is None, "macOS ZIP CRC failure")
        for info in original.infolist():
            copied = archive.getinfo(info.filename)
            require(info.external_attr == copied.external_attr, f"macOS permissions changed: {info.filename}")
            with original.open(info) as a, archive.open(copied) as b:
                require(stream_sha(a) == stream_sha(b), f"macOS app/signature changed: {info.filename}")
        for path in docs:
            require(hashlib.sha256(archive.read(path.name)).hexdigest() == sha(path), f"macOS document mismatch: {path.name}")
    os.replace(staging, writable(output))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--include-historical-reports", action="store_true")
    args = parser.parse_args()
    current, exports, smoke, qa, counts, audits, matches = verify_evidence()
    required_docs = [ROOT / "RELEASE_1.5.2_KO.txt", ROOT / "THIRD_PARTY_NOTICES.txt"]
    for path in required_docs:
        require(path.is_file(), f"Missing release documentation: {path}")
    validation_lines = [
        "DVD BATTLE V1.5.2 Developer Play — 다중 플랫폼 배포 검증", "",
        f"자동 확인 항목 {sum(counts.values()):,}개 통과. AI 통합 검사 {matches}경기 및 18개 맵의 각 20초 전투.",
        "확인 항목 수는 독립 경기 수가 아니며 모든 가능한 조합이나 승률 향상을 입증하지 않습니다.",
        *[f"  {name}: {count} PASS" for name, count in counts.items()], "",
        "Windows: PE x86_64. 최종 배포 EXE의 스모크 검사와 기존 플레이어 설정 보존 확인.",
        "Linux: ELF64 x86_64. tar.gz의 실행 파일 권한은 0755로 보존.",
        "macOS: Intel x86_64 및 Apple Silicon arm64 공용 앱, 버전 1.5.2.",
        "macOS 앱의 실행 권한·PCK·서명 리소스 보존. Godot ad-hoc 서명, Apple 공증 없음.",
        "Linux 및 macOS의 해당 운영체제에서의 실제 실행은 이 Windows 환경에서 검증하지 않았습니다.", "",
        "각 내보내기의 런타임 소스 SHA-256과 현재 소스가 일치합니다.",
        "격리 QA는 10개 검사와 가져오기를 모두 완료했으며 검사 코드·런타임 GDScript 해시가 현재 소스와 일치합니다.",
        "검사 근거: reports/regression_152, maps_152, ai_audit_152, environment_152.json, multiplatform_152.",
        "초기 실패·수정 전 진단 자료는 현재 QA 폴더에 별도 이름으로 보존할 수 있으며 최종 PASS 집계에는 포함하지 않습니다.",
        "각 ZIP CRC와 원본 파일의 SHA-256, Linux tar 파일의 SHA-256·권한을 포장 중 다시 검사합니다.",
        "이전 버전 배포 경로에는 쓰지 않으며 .git/.godot/.claude/zz_work/zz_diag는 소스 ZIP에서 제외합니다.",
        "과거 버전 reports 포함: " + ("예" if args.include_historical_reports else "아니요 — V1.5.2 검사 근거만 포함"), "",
    ]
    writable(VALIDATION).write_text("\n".join(validation_lines), encoding="utf-8-sig")
    manifest = {
        "version": VERSION, "edition": "Developer Play", "engine": "4.7.2.stable",
        "packaged_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "platforms": exports, "runtime_sources_sha256": current,
        "automated_assertions_passed": sum(counts.values()), "suites": counts,
        "integration_matches": matches, "audit_reports": audits, "isolated_qa": qa,
        "windows_smoke": smoke, "source_includes_historical_reports": args.include_historical_reports,
        "limitations": ["Linux/macOS native execution was not tested on this Windows host.",
                        "macOS uses ad-hoc signing and has no Apple notarization.",
                        "AI regression checks do not prove universally stronger play or a guaranteed win rate."],
    }
    write_json(MANIFEST, manifest)
    optional_docs = [ROOT / "README_KO.txt", ROOT / "CHANGELOG_1.5.2_KO.txt"]
    docs = [*required_docs, VALIDATION, MANIFEST, *(p for p in optional_docs if p.is_file())]
    for platform in PLATFORMS:
        for doc in docs:
            shutil.copy2(doc, writable(RELEASE / platform / doc.name))
    windows_binary = RELEASE / PLATFORMS["windows"][1]
    linux_binary = RELEASE / PLATFORMS["linux"][1]
    make_zip(ARCHIVES["windows"], [(p, f"{PREFIX}_WINDOWS/" + p.name) for p in [windows_binary, *docs]])
    make_linux(ARCHIVES["linux"], linux_binary, docs)
    make_macos(ARCHIVES["macos"], RELEASE / PLATFORMS["macos"][1], docs)
    files = list(source_files(args.include_historical_reports))
    require(ROOT / "project.godot" in files and ROOT / "tests/environment_152.gd" in files,
            "Source ZIP omitted required project files")
    make_zip(ARCHIVES["source"], [(path, PREFIX + "/" + path.relative_to(ROOT).as_posix()) for path in files])
    require(current == source_hashes(), "Runtime source changed while packaging")
    artifacts = [windows_binary, linux_binary, *ARCHIVES.values()]
    hashes = [{"path": str(path), "bytes": path.stat().st_size, "sha256": sha(path)} for path in artifacts]
    writable(PARENT / f"{PREFIX}_SHA256.txt").write_text(
        "".join(f"{item['sha256']}  {Path(item['path']).name}\n" for item in hashes), encoding="ascii")
    result = {"status": "PASS", "version": VERSION, "archive_integrity": "PASS",
              "automated_assertions_passed": sum(counts.values()), "source_files": len(files),
              "integration_matches": matches, "artifacts": hashes}
    write_json(REPORTS / "packages.json", result)
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
