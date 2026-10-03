"""Package V1.5.1 only after matching exports, Windows smoke and isolated QA pass."""
import hashlib
import json
from pathlib import Path
import shutil
import tarfile
import zipfile

from build_multiplatform_151 import ROOT, RELEASE, REPORTS, PLATFORMS, sha, source_hashes, inspect_binary


def read(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def main():
    current = source_hashes()
    exports = {}
    for platform, (_, relative) in PLATFORMS.items():
        report = read(REPORTS / f"export_{platform}.json")
        binary = RELEASE / relative
        assert report["status"] == "PASS" and not report["errors"]
        assert report["runtime_sources_sha256"] == current, f"Stale {platform} build"
        assert report["sha256"] == sha(binary), f"Modified {platform} binary"
        inspect_binary(platform, binary)
        exports[platform] = {k: v for k, v in report.items() if k != "runtime_sources_sha256"}
    smoke = read(REPORTS / "windows_smoke.json")
    assert smoke["status"] == "PASS" and smoke["player_settings_unchanged"]
    assert smoke["executable_sha256"] == exports["windows"]["sha256"]
    binary_audit = read(REPORTS / "binary_audit.json")
    assert binary_audit["status"] == "PASS"
    for platform in PLATFORMS:
        assert binary_audit["binaries"][platform]["sha256"] == exports[platform]["sha256"]
    qa = read(REPORTS / "qa/summary.json")
    assert qa["status"] == "PASS", "Isolated QA did not pass"
    required = ["import_verification", "codex_data_151", "mechanics_122", "deathmatch_15", "conquest_15",
                "codex_ui_151", "preview_ui_14", "control_ui_13", "deathmatch_ui_15"]
    for name in required:
        assert qa["tests"][name]["ok"] and qa["tests"][name]["exit_code"] == 0, name
        assert not qa["tests"][name].get("failed"), name
    qa_root = Path(qa["qa_source"])
    # The QA project uses a dedicated settings folder; runtime code and assets must match exactly.
    for name, digest in current.items():
        if name.startswith(("scripts/", "scenes/", "shaders/", "assets/")):
            assert sha(qa_root / name) == digest, "QA source mismatch: " + name
    assertions = sum(qa["tests"][name].get("passed", 0) for name in required)
    assert qa["passed"] == assertions and qa["failed_checks"] == 0, "QA totals do not match the suite results"
    template_manifest = ROOT.parent / "DVD_BATTLE_BUILD_TOOLS/godot-4.7.2/selected_templates_manifest.json"
    templates = read(template_manifest)
    for entry in templates["selected_members"]:
        assert sha(entry["path"]) == entry["sha256"]
    manifest = {"version": "1.5.1", "engine": "4.7.2.stable", "platforms": exports,
                "automated_assertions_passed": assertions, "qa": qa, "windows_smoke": smoke,
                "binary_audit": binary_audit,
                "runtime_sources_sha256": current, "template_provenance": templates,
                "limitations": ["Linux and macOS native launch, graphics, audio and input were not tested on this Windows host.",
                                "macOS uses Godot built-in ad-hoc signing; Apple Developer ID signing and notarization were not performed.",
                                "The selected official template members were size/CRC verified; the entire TPZ was not downloaded or SHA verified."]}
    manifest_path = REPORTS / "release_manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    validation = ROOT / "VALIDATION_MULTIPLATFORM_1.5.1_KO.txt"
    validation.write_text("\n".join([
        "DVD BATTLE V1.5.1 — 다중 플랫폼 배포 검증", "",
        f"현재 통합 소스 자동 검사 {assertions}항목 통과.",
        *[f"  {name}: " + (str(qa['tests'][name]['passed']) + ' PASS' if 'passed' in qa['tests'][name] else 'PASS') for name in required],
        "", "Windows: PE x86_64, 파일/제품 버전1.5.1.0, 내장 PCK.",
        "배포 EXE 메뉴 시작·아이템 도감·데스매치 화면 저장 완료. 종료0, 엔진 오류 없음. 기존 사용자 설정 SHA-256 불변.",
        "Linux: ELF64 x86_64, 내장 PCK. tar.gz에 실행 권한0755 보존.",
        "macOS: Universal2 x86_64+arm64, 버전1.5.1, .app/PCK/Info.plist 및 서명 리소스 확인.",
        "macOS ZIP의 실행 권한 확인. Godot 내장 ad-hoc 서명, Apple 공증 없음.",
        "", "Windows에서 교차 내보내기했습니다. Linux/macOS 실기동은 검증하지 않았습니다.",
        "격리 복사본의 게임 코드·에셋과 각 빌드의 소스 SHA-256 일치를 검사했습니다.",
        "공식4.7.2 HTTPS 템플릿의 필요한 항목을 선택 다운로드해 크기·CRC32·로컬SHA256을 확인했습니다.",
        "전체 템플릿 TPZ의 SHA256은 선택 다운로드 방식 때문에 검증하지 않았습니다.",
        "기존 reports의 1.4/1.5 기록은 이전 버전 자료입니다. 이번 결과는 reports/multiplatform_151에 있습니다.",
        "아카이브 CRC/파일 해시/실행 권한은 포장 단계에서 다시 확인합니다.", ""
    ]), encoding="utf-8-sig")
    docs = [ROOT / "RELEASE_1.5.1_KO.txt", validation, ROOT / "THIRD_PARTY_NOTICES.txt", manifest_path]
    for platform in PLATFORMS:
        for doc in docs:
            shutil.copy2(doc, RELEASE / platform / doc.name)
    windows = ROOT.parent / "DVD_BATTLE_1.5.1_WINDOWS.zip"
    linux = ROOT.parent / "DVD_BATTLE_1.5.1_LINUX_X86_64.tar.gz"
    macos = ROOT.parent / "DVD_BATTLE_1.5.1_MACOS_UNIVERSAL.zip"
    with zipfile.ZipFile(windows, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for path in [RELEASE / PLATFORMS["windows"][1], *docs]:
            archive.write(path, "DVD_BATTLE_1.5.1_WINDOWS/" + path.name)
    linux_binary = RELEASE / PLATFORMS["linux"][1]
    with tarfile.open(linux, "w:gz", compresslevel=6) as archive:
        for path in [linux_binary, *docs]:
            info = archive.gettarinfo(str(path), "DVD_BATTLE_1.5.1_LINUX_X86_64/" + path.name)
            info.mode = 0o755 if path == linux_binary else 0o644
            info.uid = info.gid = 0
            info.uname = info.gname = ""
            with path.open("rb") as content:
                archive.addfile(info, content)
    shutil.copy2(RELEASE / PLATFORMS["macos"][1], macos)
    with zipfile.ZipFile(macos, "a", zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for doc in docs:
            info = zipfile.ZipInfo(doc.name)
            info.create_system = 3
            info.external_attr = 0o100644 << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, doc.read_bytes())
    for path in (windows, macos):
        with zipfile.ZipFile(path) as archive:
            assert archive.testzip() is None
    inspect_binary("macos", macos)
    with tarfile.open(linux, "r:gz") as archive:
        info = archive.getmember("DVD_BATTLE_1.5.1_LINUX_X86_64/" + linux_binary.name)
        assert info.mode == 0o755
        with archive.extractfile(info) as stream:
            assert hashlib.file_digest(stream, "sha256").hexdigest() == sha(linux_binary)
    artifacts = [RELEASE / PLATFORMS["windows"][1], windows, linux, macos]
    lines = [f"{sha(path)}  {path.name}" for path in artifacts]
    (ROOT.parent / "DVD_BATTLE_1.5.1_SHA256.txt").write_text("\n".join(lines) + "\n", encoding="ascii")
    result = {"status": "PASS", "assertions": assertions, "archive_integrity": "PASS",
              "artifacts": [{"path": str(p), "bytes": p.stat().st_size, "sha256": sha(p)} for p in artifacts]}
    (REPORTS / "packages.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
