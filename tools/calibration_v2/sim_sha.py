"""The shared calibration/release SIM_SHA v1 definition. No wall time enters it."""
from __future__ import annotations

import argparse
from pathlib import Path
import re

try:
    from .common import GODOT, ROOT, digest, require, run_godot, sha, write_json, writable_path
except ImportError:
    from common import GODOT, ROOT, digest, require, run_godot, sha, write_json, writable_path


FINGERPRINT_DRIVER = "tools/calibration_v2/data_fingerprint_cli.gd"
FINGERPRINT_LIBRARY = "tools/calibration_v2/data_fingerprint.gd"
FINGERPRINT_PREFIX = "DATA_FINGERPRINT_V2 "

def source_hashes(root=ROOT):
    root = Path(root).resolve()
    files = [path for name in ("scripts/core", "scripts/ai") for path in (root / name).rglob("*")
             if path.is_file() and path.suffix not in (".uid", ".import")]
    files.append(root / "scripts/data/char_data.gd")
    return {path.relative_to(root).as_posix(): sha(path) for path in sorted(files)}


def combine(data_fingerprint, sources):
    require(re.fullmatch(r"[0-9a-f]{64}", data_fingerprint) is not None, "Invalid data fingerprint")
    # JSON has ASCII paths and hex values. Godot JSON.stringify(..., '', true)
    # gives the same key ordering and separators for the GDScript validator.
    return digest({"data_fingerprint": data_fingerprint, "sources": sources})


def data_source_hashes(root):
    root = Path(root).resolve()
    return {path.relative_to(root).as_posix(): sha(path) for path in sorted((root / "scripts/data").rglob("*.gd"))
            if path.name != "draft_calibration.gd"}


def fingerprint(root, godot, out, timeout=900):
    out = writable_path(out)
    out.mkdir(parents=True, exist_ok=True)
    log = out / "data_fingerprint.log"
    canonical = writable_path(out / "data_canonical.json")
    if canonical.exists():
        canonical.unlink()
    run_godot(godot, root, ["--script", "res://" + FINGERPRINT_DRIVER, "--",
        "--out=" + canonical.resolve().as_posix()], log, timeout)
    rows = [line.removeprefix(FINGERPRINT_PREFIX) for line in log.read_text(encoding="utf-8", errors="replace").splitlines()
            if line.startswith(FINGERPRINT_PREFIX)]
    require(len(rows) == 1, "Expected one data fingerprint result")
    import json
    data = json.loads(rows[0])
    require(canonical.is_file() and sha(canonical) == data.get("sha256"), "Canonical data file does not match printed fingerprint")
    require(type(data.get("bytes")) is int and canonical.stat().st_size == data["bytes"], "Canonical data byte count differs")
    require(isinstance(data.get("counts"), dict), "Missing fingerprint counts")
    require(Path(data.get("project", "")).resolve() == Path(root).resolve(), "Fingerprint came from a different project")
    return data


def compute(project=ROOT, godot=GODOT, out=None, timeout=900):
    root = Path(project).resolve()
    before = source_hashes(root)
    data_before = data_source_hashes(root)
    producers = [root / path for path in (FINGERPRINT_DRIVER, FINGERPRINT_LIBRARY)]
    producer_before = {str(path): sha(path) for path in producers}
    data = fingerprint(root, godot, out or root / "zz_work/measure/C6/sim_sha", timeout)
    require(before == source_hashes(root), "Simulation source changed while fingerprinting")
    require(data_before == data_source_hashes(root) and producer_before == {str(path): sha(path) for path in producers}, "Data or fingerprint tool changed while fingerprinting")
    combined = combine(data["sha256"], before)
    return {"format": "DVD_BATTLE_SIM_SHA_v1", "algorithm": "DVD_BATTLE_SIM_SHA_v1",
            "sha256": combined, "sim_sha": combined, "files": before,
            "data_fingerprint": data["sha256"], "data_counts": data["counts"], "sources": before,
            "platform": "windows"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--godot", type=Path, default=GODOT)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    result = compute(args.root, args.godot, args.out.parent / "fingerprint")
    write_json(args.out, result)
    print(result["sha256"])


if __name__ == "__main__":
    main()
