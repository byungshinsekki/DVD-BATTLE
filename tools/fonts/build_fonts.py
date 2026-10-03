"""Reproduce bundled CJK subsets using explicitly supplied LOCAL source fonts.

This tool never installs packages and never downloads files. Dependencies:
fontTools, installed separately with approval. Example after promotion:

  py tools/fonts/build_fonts.py --serif-source <NotoSerifCJKkr-Black.otf> \
    --source-url <the verified official source URL>

Use --audit-only to inspect current/planned coverage, and --self-test for the
dependency-free GDScript literal collector tests. UI subsets are rebuilt only
with --rebuild-ui and explicit source files, after reviewing ui_missing.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unicodedata

FONT_FILES = {
    "glyph_serif": "glyph_serif.otf",
    "ui_regular": "ui_regular.otf",
    "ui_bold": "ui_bold.otf",
    "ui_black": "ui_black.otf",
    "symbols": "symbols.ttf",
}
UI_FONTS = ("ui_regular", "ui_bold", "ui_black")
SERIF_MAX_BYTES = 1500000


def source_root() -> Path:
    # Works both in tools/fonts after promotion and in zz_work/font_prepare.
    return Path(__file__).resolve().parents[2]


def write_text(path: Path, value: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(value, encoding="utf-8", newline="\n")


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def gd_literals(source: str):
    """Yield decoded quoted GDScript literals, excluding # comments.

    Supports single/double/triple quotes, raw strings and unicode escapes;
    StringName/NodePath prefixes do not alter the quoted payload. This is a
    lexer, not eval: source content is never executed by the collector.
    """
    i, n = 0, len(source)
    while i < n:
        if source[i] == "#":
            end = source.find("\n", i)
            i = n if end < 0 else end + 1
            continue
        if source[i] not in "\"'":
            i += 1
            continue
        quote = source[i]
        triple = source.startswith(quote * 3, i)
        delimiter = quote * (3 if triple else 1)
        raw = i > 0 and source[i - 1] == "r" and (i < 2 or not (source[i - 2].isalnum() or source[i - 2] == "_"))
        i += len(delimiter)
        chars: list[str] = []
        closed = False
        while i < n:
            if source.startswith(delimiter, i):
                i += len(delimiter)
                closed = True
                break
            ch = source[i]
            if ch != "\\":
                chars.append(ch)
                i += 1
                continue
            if i + 1 >= n:
                chars.append(ch)
                i += 1
                break
            escaped = source[i + 1]
            if raw:
                chars.extend((ch, escaped))
                i += 2
                continue
            widths = {"u": 4, "U": 8, "x": 2}
            width = widths.get(escaped, 0)
            digits = source[i + 2:i + 2 + width]
            if width and len(digits) == width and all(c in "0123456789abcdefABCDEF" for c in digits):
                code = int(digits, 16)
                if code <= 0x10FFFF and not 0xD800 <= code <= 0xDFFF:
                    chars.append(chr(code))
                    i += width + 2
                    continue
            replacements = {"n": "\n", "r": "\r", "t": "\t", "b": "\b", "f": "\f", "v": "\v", "a": "\a"}
            chars.append(replacements.get(escaped, escaped))
            i += 2
        if not closed:
            raise ValueError("Unterminated quoted literal; refusing incomplete glyph collection")
        yield "".join(chars)


def selected_codepoint(code: int) -> bool:
    if code <= 127:
        return False
    name = unicodedata.name(chr(code), "")
    if name.startswith(("CJK UNIFIED IDEOGRAPH", "CJK COMPATIBILITY IDEOGRAPH")):
        return True
    # CJK symbols/punctuation and compatibility/fullwidth forms; geometric
    # shapes and the Unicode arrow blocks requested by the work order.
    return any(lo <= code <= hi for lo, hi in (
        (0x3000, 0x303F), (0xFE30, 0xFE4F), (0xFF00, 0xFFEF),
        (0x25A0, 0x25FF), (0x2190, 0x21FF), (0x27F0, 0x27FF),
        (0x2900, 0x297F), (0x2B00, 0x2BFF),
    ))


def collect(root: Path, extra_file: Path) -> dict:
    all_codes: set[int] = set()
    ui_codes: set[int] = set()
    files: dict[str, list[str]] = {}
    for path in sorted((root / "scripts").rglob("*.gd")):
        relative = path.relative_to(root).as_posix()
        codes = {ord(ch) for literal in gd_literals(path.read_text(encoding="utf-8-sig"))
                 for ch in literal if selected_codepoint(ord(ch))}
        all_codes.update(codes)
        # Data text is rendered by the UI; include it rather than assuming
        # every data glyph is always drawn using the separate serif face.
        if relative.startswith(("scripts/ui/", "scripts/data/")):
            ui_codes.update(codes)
        if codes:
            files[relative] = [f"U+{c:04X}" for c in sorted(codes)]
    extra: set[int] = set()
    if extra_file.exists():
        for line in extra_file.read_text(encoding="utf-8-sig").splitlines():
            if line.lstrip().startswith("#"):
                continue
            extra.update(ord(ch) for ch in line if not ch.isspace())
    all_codes.update(extra)
    return {"all": all_codes, "ui": ui_codes, "extra": extra, "files": files}


def ttfont_class():
    try:
        from fontTools.ttLib import TTFont
    except ImportError as error:
        raise SystemExit("fontTools is unavailable. This tool does not install it. Obtain approval/install separately, then rerun.") from error
    return TTFont


def font_info(path: Path) -> dict:
    TTFont = ttfont_class()
    with TTFont(str(path), lazy=False, recalcTimestamp=False) as font:
        cmap = {code for table in font["cmap"].tables if table.isUnicode()
                for code in getattr(table, "cmap", {})}
        def names(name_id):
            return sorted({n.toUnicode() for n in font["name"].names if n.nameID == name_id})
        return {"file": path.name, "sha256": sha256(path), "bytes": path.stat().st_size,
                "family": names(1), "version": names(5), "license_text": names(13),
                "license_url": names(14), "cff": "CFF " in font or "CFF2" in font,
                "variable": "fvar" in font, "codepoints": cmap}


def printable(codes) -> list[str]:
    return [f"U+{code:04X} {chr(code)}" for code in sorted(codes)]


def subset(source: Path, destination: Path, codes: set[int], temp: Path, timeout: float) -> None:
    info = font_info(source)
    if not info["cff"] or info["variable"]:
        raise ValueError("This approved official-OTF flow requires a static CFF source. For a VF/TrueType fallback, stop and perform the documented .ttf path/import migration separately.")
    text_path = temp / (destination.stem + "_subset_text.txt")
    write_text(text_path, "".join(chr(code) for code in sorted(codes)))
    output = temp / destination.name
    command = [sys.executable, "-m", "fontTools.subset", str(source),
               "--text-file=" + str(text_path), "--layout-features=*", "--name-IDs=*",
               "--name-languages=*", "--notdef-outline", "--no-recalc-timestamp",
               "--canonical-order", "--output-file=" + str(output)]
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            text=True, encoding="utf-8", errors="replace", timeout=timeout,
                            creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0,
                            env={**os.environ, "SOURCE_DATE_EPOCH": "0"})
    write_text(temp / (destination.stem + "_subset.log"), result.stdout)
    if result.returncode != 0:
        raise RuntimeError(f"Subsetting failed for {destination.name}: {result.stdout}")
    actual = font_info(output)
    missing = codes - actual["codepoints"]
    if missing:
        raise RuntimeError("Subset lost requested codepoints: " + str(printable(missing)))
    if destination.stem == "glyph_serif" and actual["bytes"] > SERIF_MAX_BYTES:
        raise RuntimeError(f"glyph_serif exceeds 1.5 MB: {actual['bytes']} bytes")
    destination.parent.mkdir(parents=True, exist_ok=True)
    # All outputs are validated before callers copy staged data into assets.
    destination.write_bytes(output.read_bytes())


def self_test() -> None:
    sample = '# "偽"\nvar x = "政#報" # "欺"\nvar y = \'誘\\\'宣\'\nvar z = """訊\n默"""\nvar q = "\\u653F"\nvar raw = r"\\u653F"\n'
    values = list(gd_literals(sample))
    assert values == ["政#報", "誘'宣", "訊\n默", "政", "\\u653F"], values
    assert selected_codepoint(ord("政"))
    assert selected_codepoint(ord("↻"))
    assert selected_codepoint(ord("◇"))
    assert not selected_codepoint(ord("한"))
    assert not selected_codepoint(ord("A"))
    try:
        list(gd_literals('var x = "broken'))
    except ValueError:
        pass
    else:
        raise AssertionError("unterminated strings must not silently lose glyphs")
    print("FONT_COLLECTOR_SELF_TEST PASS")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=source_root())
    parser.add_argument("--serif-source", type=Path)
    parser.add_argument("--source-url", default="")
    parser.add_argument("--extra", type=Path)
    parser.add_argument("--out", type=Path)
    parser.add_argument("--audit-only", action="store_true")
    parser.add_argument("--rebuild-ui", action="store_true")
    parser.add_argument("--ui-regular-source", type=Path)
    parser.add_argument("--ui-bold-source", type=Path)
    parser.add_argument("--ui-black-source", type=Path)
    parser.add_argument("--ui-source-url", default="")
    parser.add_argument("--timeout", type=float, default=1200.0)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return 0
    if args.serif_source is None or not args.serif_source.is_file():
        parser.error("--serif-source must be an existing local official source font")
    root = args.root.resolve()
    if not (root / "project.godot").is_file():
        parser.error("--root must be the project root")
    extra = args.extra or Path(__file__).with_name("extra_glyphs.txt")
    output = (args.out or root / "tools/fonts/build_report").resolve()
    output.mkdir(parents=True, exist_ok=True)
    requested = collect(root, extra)
    installed = {key: font_info(root / "assets/fonts" / name) for key, name in FONT_FILES.items()}
    sources = {"glyph_serif": args.serif_source.resolve()}
    for key in UI_FONTS:
        supplied = getattr(args, key + "_source")
        if supplied is not None:
            sources[key] = supplied.resolve()
    source_info = {key: font_info(path) for key, path in sources.items()}
    ui_required = requested["ui"] - installed["symbols"]["codepoints"]
    ui_missing = {key: ui_required - installed[key]["codepoints"] for key in UI_FONTS}
    rebuild = ["glyph_serif"]
    if args.rebuild_ui:
        for key in UI_FONTS:
            if ui_missing[key]:
                if key not in sources:
                    parser.error(f"--rebuild-ui needs --{key.replace('_', '-')}-source; no automatic download is performed")
                rebuild.append(key)
    subsets: dict[str, set[int]] = {}
    for key in rebuild:
        preserve = installed[key]["codepoints"]
        source_codes = source_info[key]["codepoints"]
        lost_existing = preserve - source_codes
        if lost_existing:
            raise ValueError(f"{key} source cannot preserve existing cmap: {printable(lost_existing)}")
        desired = requested["all"] if key == "glyph_serif" else requested["ui"]
        subsets[key] = preserve | (desired & source_codes)
    planned = {key: subsets.get(key, info["codepoints"]) for key, info in installed.items()}
    union = planned["glyph_serif"] | planned["ui_black"] | planned["symbols"]
    uncovered = requested["all"] - union
    report = {"collector": "quoted GDScript literals only; comments excluded", "sources": {},
              "requested": printable(requested["all"]), "extra": printable(requested["extra"]),
              "source_files": requested["files"], "ui_missing_before": {k: printable(v) for k, v in ui_missing.items()},
              "planned_rebuild": rebuild, "requested_uncovered_after_plan": printable(uncovered),
              "preserved_cmap_counts": {k: len(v["codepoints"]) for k, v in installed.items()},
              "source_absent_requested": {k: printable(requested["all"] - v["codepoints"]) for k, v in source_info.items()},
              "audit_only": args.audit_only}
    for key, info in source_info.items():
        report["sources"][key] = {k: v for k, v in info.items() if k != "codepoints"}
        report["sources"][key]["origin_url"] = args.source_url if key == "glyph_serif" else args.ui_source_url
        report["sources"][key]["license"] = "OFL-1.1"
    write_text(output / "font_audit.json", json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"planned_rebuild": rebuild, "ui_missing": {k: len(v) for k, v in ui_missing.items()},
                      "uncovered": printable(uncovered), "report": str(output / "font_audit.json")}, ensure_ascii=False))
    if args.audit_only:
        return 0
    if uncovered:
        raise ValueError("Required glyphs are absent from the planned bundled union; inspect audit and supply appropriate approved sources.")
    if not args.source_url:
        parser.error("Build requires --source-url recording the verified official font origin")
    if any(k in rebuild for k in UI_FONTS) and not args.ui_source_url:
        parser.error("UI rebuild requires --ui-source-url for provenance")
    # Temporary outputs stay inside the report directory. No asset changes
    # occur until every subset has passed retention, coverage and size checks.
    with tempfile.TemporaryDirectory(prefix="subset_", dir=output) as temp_string:
        temp = Path(temp_string)
        staged = temp / "validated"
        for key in rebuild:
            subset(sources[key], staged / FONT_FILES[key], subsets[key], temp, args.timeout)
        report["outputs"] = {}
        for key in rebuild:
            generated = staged / FONT_FILES[key]
            target = root / "assets/fonts" / FONT_FILES[key]
            report["outputs"][key] = {"file": FONT_FILES[key], "sha256": sha256(generated), "bytes": generated.stat().st_size,
                                       "codepoints": len(subsets[key])}
            target.write_bytes(generated.read_bytes())
    report["audit_only"] = False
    write_text(output / "font_audit.json", json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    provenance = ["# Bundled font sources", "", "License: OFL-1.1. Sources are provided locally; this builder performs no downloads.", ""]
    for key in rebuild:
        info = report["sources"][key]
        provenance += [f"## {key}", "", f"- Source file: `{info['file']}`", f"- Family: {', '.join(info['family'])}",
                       f"- Version: {', '.join(info['version'])}", f"- SHA256: `{info['sha256']}`",
                       f"- Official origin: {info['origin_url']}", f"- License: OFL-1.1 ({'; '.join(info['license_url'])})",
                       f"- Output SHA256: `{report['outputs'][key]['sha256']}`", ""]
    provenance += ["Existing cmap entries are retained. New CJK/shape/arrow characters are collected from quoted script literals and extra_glyphs.txt.",
                   "Subsetting uses layout-features=*, name-IDs=*, name-languages=*, notdef-outline, canonical-order and no-recalc-timestamp.",
                   "Run the raw-font Godot test after reimport. Build manifests report unsupported source characters and the bundled union explicitly.", ""]
    write_text(root / "tools/fonts/FONT_SOURCES.md", "\n".join(provenance))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
