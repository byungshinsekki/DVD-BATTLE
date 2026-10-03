"""Export V1.5.2 Developer Play with matching Godot 4.7.2 templates; preserve other releases.

Usage: python tools/build_multiplatform_152.py [--platform windows|linux|macos|all]
Set --godot to a Godot 4.7.2 console executable on another machine and update
the custom template locations in export_presets.cfg before exporting.
Install the matching official templates with Godot's template manager too:
the macOS exporter also checks the standard 4.7.2.stable/macos.zip location.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import struct
import subprocess
import time
import zipfile

ROOT = Path(__file__).resolve().parents[1]
REPORTS = ROOT / "reports/multiplatform_152"
RELEASE = ROOT.parent / "DVD_BATTLE_1.5.2_RELEASE"
PLATFORMS = {
    "windows": ("Windows Desktop", "windows/DVD_BATTLE_1.5.2.exe"),
    "linux": ("Linux", "linux/DVD_BATTLE_1.5.2.x86_64"),
    "macos": ("macOS", "macos/DVD_BATTLE_1.5.2_macOS.zip"),
}


def sha(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def source_hashes():
    paths = [ROOT / "project.godot", ROOT / "export_presets.cfg", ROOT / "icon.svg", ROOT / "icon.ico"]
    paths += [p for folder in ("scripts", "scenes", "shaders", "assets") for p in (ROOT / folder).rglob("*")
              if p.is_file() and p.suffix not in (".uid", ".import")]
    return {p.relative_to(ROOT).as_posix(): sha(p) for p in sorted(paths)}


def run_checked(args, log_name, timeout=600):
    started = time.monotonic()
    with (REPORTS / log_name).open("w", encoding="utf-8") as output:
        proc = subprocess.run([str(x) for x in args], stdout=output, stderr=subprocess.STDOUT,
                              timeout=timeout, creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
    log = (REPORTS / log_name).read_text(encoding="utf-8", errors="replace")
    errors = re.findall(r"(?m)^.*(?:SCRIPT ERROR|ERROR:).*$", log)
    result = {"exit_code": proc.returncode, "errors": errors, "seconds": round(time.monotonic() - started, 3)}
    print(log_name, json.dumps(result, ensure_ascii=False), flush=True)
    if proc.returncode or errors:
        raise RuntimeError(f"Failed: {log_name}")
    return result


def inspect_binary(platform, path):
    if platform == "windows":
        with path.open("rb") as f:
            assert f.read(2) == b"MZ", "Missing PE header"
            f.seek(0x3C)
            pe = struct.unpack("<I", f.read(4))[0]
            f.seek(pe)
            assert f.read(4) == b"PE\0\0"
            assert struct.unpack("<H", f.read(2))[0] == 0x8664
        return {"format": "PE", "architecture": "x86_64"}
    if platform == "linux":
        with path.open("rb") as f:
            header = f.read(64)
        assert header[:6] == b"\x7fELF\x02\x01", "Expected little-endian ELF64"
        assert struct.unpack_from("<H", header, 18)[0] == 62, "Expected x86_64"
        return {"format": "ELF64", "architecture": "x86_64", "native_execution_tested": False}
    with zipfile.ZipFile(path) as archive:
        assert archive.testzip() is None
        names = archive.namelist()
        info_name = next(n for n in names if n.endswith(".app/Contents/Info.plist"))
        plist = plistlib.loads(archive.read(info_name))
        assert plist["CFBundleShortVersionString"] == "1.5.2"
        assert plist["CFBundleVersion"] == "1.5.2"
        binary_name = info_name.rsplit("/", 1)[0] + "/MacOS/" + plist["CFBundleExecutable"]
        info = archive.getinfo(binary_name)
        assert (info.external_attr >> 16) & 0o111, "macOS ZIP lost execute permission"
        binary = archive.read(info)
        assert binary[:4] == b"\xca\xfe\xba\xbe", "Expected universal Mach-O"
        arch_count = struct.unpack_from(">I", binary, 4)[0]
        arches = [struct.unpack_from(">I", binary, 8 + i * 20)[0] for i in range(arch_count)]
        assert 0x01000007 in arches and 0x0100000C in arches
        assert any(n.endswith(".pck") for n in names), "Missing game pack"
        assert any("_CodeSignature/CodeResources" in n for n in names), "Missing ad-hoc bundle seal"
    return {"format": "Mach-O Universal 2", "architectures": ["x86_64", "arm64"],
            "bundle_identifier": plist["CFBundleIdentifier"], "zip_execute_permissions": True,
            "signing": "Godot built-in ad-hoc", "notarized": False, "native_execution_tested": False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, default=ROOT.parent / "DVD_BATTLE_1.2.1_RECOVERY_WORK/tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe")
    parser.add_argument("--platform", choices=[*PLATFORMS, "all"], default="all")
    args = parser.parse_args()
    version = subprocess.check_output([str(args.godot), "--version"], text=True).strip()
    assert version.startswith("4.7.2.stable"), version
    REPORTS.mkdir(parents=True, exist_ok=True)
    (REPORTS / ".gdignore").write_text("", encoding="utf-8")
    before = source_hashes()
    run_checked([args.godot, "--headless", "--path", ROOT, "--editor", "--quit"], "import.log")
    for platform in PLATFORMS if args.platform == "all" else [args.platform]:
        preset, rel = PLATFORMS[platform]
        target = RELEASE / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        report = run_checked([args.godot, "--headless", "--path", ROOT, "--export-release", preset, target], f"export_{platform}.log")
        assert target.is_file() and target.stat().st_size > 1_000_000
        report.update({"status": "PASS", "engine": version, "version": "1.5.2", "path": str(target),
                       "bytes": target.stat().st_size, "sha256": sha(target), "binary": inspect_binary(platform, target),
                       "runtime_sources_sha256": before})
        assert source_hashes() == before, "Runtime source changed during export; rebuild required"
        (REPORTS / f"export_{platform}.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
        print(platform, target, report["sha256"], flush=True)


if __name__ == "__main__":
    main()
