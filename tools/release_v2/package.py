"""Deterministic archives, bounded split parts, and fresh verified extraction."""
from pathlib import Path, PurePosixPath
import gzip
import hashlib
import os
import re
import shutil
import stat
import tarfile
import tempfile
import zipfile
import config
from common import atomic_copy, git, guard_output, require, safe_write_path, sha, within


def valid_member(name):
    require(isinstance(name, str) and bool(name), "Empty archive member")
    require("\\" not in name and "\x00" not in name, "Unsafe archive member: " + repr(name))
    trimmed = name[:-1] if name.endswith("/") else name
    parts = trimmed.split("/")
    path = PurePosixPath(trimmed)
    require(not path.is_absolute() and all(p not in ("", ".", "..") for p in parts), "Unsafe archive member: " + name)
    for part in parts:
        require(not any(c in part for c in ':<>"|?*') and not any(ord(c) < 32 for c in part), "Windows-unsafe archive member: " + name)
        require(part == part.rstrip(" ."), "Ambiguous archive member: " + name)
        require(not re.match(r"^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)", part, re.I), "Reserved archive member: " + name)
    return path


def zip_file(archive, path, name, mode=0o644):
    name = valid_member(name).as_posix()
    info = zipfile.ZipInfo(name, config.ARCHIVE_TIME)
    info.create_system = 3
    info.external_attr = (stat.S_IFREG | mode) << 16
    info.compress_type = zipfile.ZIP_DEFLATED
    with archive.open(info, "w", force_zip64=True) as target, Path(path).open("rb") as source:
        shutil.copyfileobj(source, target, 1024 * 1024)


def source_paths(project):
    names = git(project, "-c", "core.quotepath=false", "ls-files", "-z", "--cached", "--others", "--exclude-standard").split("\0")
    result = []
    for name in sorted(set(names) - {""}):
        parts = PurePosixPath(name).parts
        if any(part in config.EXCLUDED_PARTS for part in parts):
            continue
        if name.startswith("reports/release_v2/") or name in ("AGENTS.md", "CODEX_WORK_ORDER_V2.md"):
            continue
        valid_member(name)
        path = Path(project) / name
        if path.is_file():
            require(within(path, project) and not path.is_symlink(), "Source archive path escapes project or is a symlink")
            result.append((path, name))
    return result


def _source_modes(project):
    result = {}
    data = git(project, "-c", "core.quotepath=false", "ls-files", "--stage", "-z")
    for record in data.split("\0"):
        if not record:
            continue
        metadata, name = record.split("\t", 1)
        mode, _object, stage = metadata.split(" ", 2)
        require(stage == "0", "Source archive cannot contain unresolved Git index stages")
        require(mode != "120000", "Source archive symlinks require an explicit portable policy: " + name)
        result[name] = 0o755 if mode == "100755" else 0o644
    return result


def _claim_name(name, seen, files):
    canonical = valid_member(name).as_posix().casefold()
    require(canonical not in seen, "Duplicate or case-colliding archive member: " + name)
    for parent in PurePosixPath(canonical).parents:
        if str(parent) != ".":
            require(str(parent) not in files, "Archive file is also a parent directory: " + name)
    seen.add(canonical)
    return canonical


def inspect_archive(path):
    path = Path(path)
    members, seen, files = {}, set(), set()
    if path.name.endswith(".zip"):
        with zipfile.ZipFile(path) as archive:
            require(archive.testzip() is None, "ZIP CRC failure")
            for info in archive.infolist():
                canonical = _claim_name(info.filename, seen, files)
                mode = info.external_attr >> 16
                require(not stat.S_ISLNK(mode), "Unexpected symlink in release archive")
                if info.is_dir():
                    continue
                require(stat.S_IFMT(mode) in (0, stat.S_IFREG), "Unexpected special ZIP entry")
                require(not any(other.startswith(canonical + "/") for other in seen if other != canonical), "Archive file shadows a directory")
                files.add(canonical)
                with archive.open(info) as stream:
                    digest = hashlib.file_digest(stream, "sha256").hexdigest()
                members[info.filename] = dict(sha256=digest, bytes=info.file_size, mode=mode & 0o777)
    else:
        require(path.name.endswith(".tar.gz"), "Unsupported archive extension")
        with tarfile.open(path, "r:gz") as archive:
            for info in archive:
                canonical = _claim_name(info.name, seen, files)
                require(info.isfile(), "Unexpected non-file TAR member")
                require(not any(other.startswith(canonical + "/") for other in seen if other != canonical), "Archive file shadows a directory")
                files.add(canonical)
                with archive.extractfile(info) as stream:
                    digest = hashlib.file_digest(stream, "sha256").hexdigest()
                members[info.name] = dict(sha256=digest, bytes=info.size, mode=info.mode & 0o777)
                if info.name.endswith(".x86_64"):
                    require(info.mode == 0o755, "Linux executable mode is not 0755")
    require(bool(members), "Archive contains no regular files")
    return dict(path=str(path), sha256=sha(path), bytes=path.stat().st_size, members=members)


def package_all(project, out, exports, validation, final=False):
    out = guard_output(out, final=final)
    out.mkdir(parents=True, exist_ok=True)
    require(set(exports) == {"windows", "linux", "macos"}, "Packaging requires exactly three validated exports")
    require(0 < config.SPLIT_BYTES < config.MAX_ATTACHMENT_BYTES, "Split size must be below attachment limit")
    for kind, value in exports.items():
        binary = Path(value["path"]).resolve()
        require(within(binary, out) and binary.is_file(), "Export must be inside this build output: " + kind)
        require(sha(binary) == value["sha256"], "Export changed before packaging: " + kind)
    require(Path(validation).is_file() and within(validation, out), "Validation document must be inside this build output")
    validation_before = sha(validation)
    originals = {kind: sha(value["path"]) for kind, value in exports.items()}
    source_list = source_paths(project)
    source_modes = _source_modes(project)
    source_before = {name: sha(path) for path, name in source_list}
    # Stage the entire set before replacing any previously published archive.
    with tempfile.TemporaryDirectory(prefix=".package-stage-", dir=out) as directory:
        staging = Path(directory)
        archives = {}
        win = staging / f"DVD_BATTLE_{config.VERSION}_Windows.zip"
        with zipfile.ZipFile(win, "w", allowZip64=True) as archive:
            binary = Path(exports["windows"]["path"])
            zip_file(archive, binary, binary.name, 0o755)
            zip_file(archive, validation, Path(validation).name)
        archives["windows"] = inspect_archive(win)
        linux = staging / f"DVD_BATTLE_{config.VERSION}_Linux.tar.gz"
        with linux.open("wb") as raw, gzip.GzipFile(filename="", fileobj=raw, mode="wb", mtime=0) as compressed:
            with tarfile.open(fileobj=compressed, mode="w", format=tarfile.PAX_FORMAT) as archive:
                for path, mode in [(Path(exports["linux"]["path"]), 0o755), (Path(validation), 0o644)]:
                    info = tarfile.TarInfo(valid_member(path.name).as_posix())
                    info.size, info.mode, info.uid, info.gid, info.mtime = path.stat().st_size, mode, 0, 0, 0
                    info.uname = info.gname = ""
                    with path.open("rb") as stream:
                        archive.addfile(info, stream)
        archives["linux"] = inspect_archive(linux)
        mac = staging / f"DVD_BATTLE_{config.VERSION}_macOS.zip"
        shutil.copyfile(exports["macos"]["path"], mac)
        require(sha(mac) == originals["macos"], "macOS archive changed while packaging")
        archives["macos"] = inspect_archive(mac)
        source = staging / f"DVD_BATTLE_{config.VERSION}_Source.zip"
        with zipfile.ZipFile(source, "w", allowZip64=True) as archive:
            for path, name in source_list:
                zip_file(archive, path, name, source_modes.get(name, 0o644))
        archives["source"] = inspect_archive(source)
        require([name for _path, name in source_paths(project)] == [name for _path, name in source_list], "Source file list changed while packaging")
        require({name: sha(path) for path, name in source_list} == source_before, "Source files changed while packaging")
        require(sha(validation) == validation_before, "Validation document changed while packaging")
        require({kind: sha(value["path"]) for kind, value in exports.items()} == originals, "Exports changed while packaging")
        parts = []
        for kind, entry in archives.items():
            path = Path(entry["path"])
            if path.stat().st_size < config.MAX_ATTACHMENT_BYTES:
                continue
            combined = hashlib.sha256()
            with path.open("rb") as stream:
                index = 0
                while chunk := stream.read(config.SPLIT_BYTES):
                    index += 1
                    target = staging / (path.name + f".part{index:02d}")
                    target.write_bytes(chunk)
                    combined.update(chunk)
                    require(target.stat().st_size < config.MAX_ATTACHMENT_BYTES, "Split archive exceeds size limit")
                    parts.append(dict(archive=kind, index=index, path=str(target), bytes=len(chunk), sha256=sha(target)))
            require(combined.hexdigest() == entry["sha256"], "Split output differs from original archive")
        listing = [f"{entry['sha256']}  {Path(entry['path']).name}" for entry in [*archives.values(), *parts]]
        checksum = staging / "SHA256.txt"
        checksum.write_text("\n".join(listing) + "\n", encoding="utf-8", newline="\n")
        split_readme = staging / "SPLIT_ARCHIVES_KO.txt"
        if parts:
            split_readme.write_text(
                "분할 파일은 독립 ZIP이 아니라 원본 압축물의 바이트 조각입니다.\n"
                "같은 이름의 .part01, .part02 등을 숫자 순서로 이진 결합한 뒤 원본 ZIP/tar.gz로 여십시오.\n"
                "각 조각은 28MiB 미만이며 생성 시 전체 재결합 SHA256을 원본과 대조했습니다.\n", encoding="utf-8", newline="\n")
        published = set()
        for item in sorted(staging.iterdir()):
            target = safe_write_path(out / item.name)
            atomic_copy(item, target)
            published.add(target.name)
        for entry in archives.values():
            archive_name = Path(entry["path"]).name
            for old in out.glob(archive_name + ".part*"):
                if re.fullmatch(re.escape(archive_name) + r"\.part\d+", old.name) and old.name not in published:
                    safe_write_path(old).unlink()
            entry["path"] = str(out / archive_name)
        for part in parts:
            part["path"] = str(out / Path(part["path"]).name)
        if not parts and (out / split_readme.name).exists():
            safe_write_path(out / split_readme.name).unlink()
        return dict(archives=archives, parts=parts,
                    checksums={"path": str(out / checksum.name), "sha256": sha(out / checksum.name)})


def verify_and_extract(packages, destination):
    destination = guard_output(destination)
    destination.mkdir(parents=True, exist_ok=True)
    require(sha(packages["checksums"]["path"]) == packages["checksums"]["sha256"], "Checksum listing changed")
    require(set(packages["archives"]) == {"windows", "linux", "macos", "source"}, "Expected exactly four release archives")
    checksum_lines = [f"{entry['sha256']}  {Path(entry['path']).name}" for entry in [*packages["archives"].values(), *packages["parts"]]]
    require(Path(packages["checksums"]["path"]).read_text(encoding="utf-8") == "\n".join(checksum_lines) + "\n", "Checksum listing disagrees with package manifest")
    verified = {}
    session = Path(tempfile.mkdtemp(prefix="verified-", dir=destination))
    for kind, expected in packages["archives"].items():
        require(kind in ("windows", "linux", "macos", "source"), "Unknown package kind")
        path = Path(expected["path"])
        require(inspect_archive(path) == expected, "Archive metadata or bytes changed: " + kind)
        root = session / kind
        root.mkdir()
        if path.name.endswith(".zip"):
            with zipfile.ZipFile(path) as archive:
                for name, item in expected["members"].items():
                    target = safe_write_path(root / valid_member(name))
                    require(within(target, root), "Extraction path escaped scratch")
                    target.parent.mkdir(parents=True, exist_ok=True)
                    with archive.open(name) as source, target.open("xb") as output:
                        shutil.copyfileobj(source, output, 1024 * 1024)
                    if item["mode"]:
                        os.chmod(target, item["mode"])
        else:
            with tarfile.open(path, "r:gz") as archive:
                for name, item in expected["members"].items():
                    target = safe_write_path(root / valid_member(name))
                    require(within(target, root), "Extraction path escaped scratch")
                    target.parent.mkdir(parents=True, exist_ok=True)
                    with archive.extractfile(name) as source, target.open("xb") as output:
                        shutil.copyfileobj(source, output, 1024 * 1024)
                    os.chmod(target, item["mode"])
        actual_names = {p.relative_to(root).as_posix() for p in root.rglob("*") if p.is_file()}
        require(actual_names == set(expected["members"]), "Extracted file list mismatch: " + kind)
        for name, item in expected["members"].items():
            target = root / name
            require(target.stat().st_size == item["bytes"] and sha(target) == item["sha256"], f"Extracted byte/hash mismatch: {kind}/{name}")
            if os.name != "nt" and item["mode"]:
                require(stat.S_IMODE(target.stat().st_mode) == item["mode"], f"Extracted mode mismatch: {kind}/{name}")
        verified[kind] = dict(status="PASS", root=str(root), files=len(expected["members"]))
    joined = {}
    require(all(p["archive"] in packages["archives"] for p in packages["parts"]), "Split part references an unknown archive")
    for kind, expected in packages["archives"].items():
        parts = sorted((p for p in packages["parts"] if p["archive"] == kind), key=lambda p: p["index"])
        require(bool(parts) == (expected["bytes"] >= config.MAX_ATTACHMENT_BYTES), "Missing or unexpected split set")
        if not parts:
            continue
        require([p["index"] for p in parts] == list(range(1, len(parts) + 1)), "Missing/duplicate split index")
        combined = hashlib.sha256()
        byte_count = 0
        for part in parts:
            path = Path(part["path"])
            require(0 < part["bytes"] <= config.SPLIT_BYTES and part["bytes"] < config.MAX_ATTACHMENT_BYTES, "Invalid split size")
            require(path.stat().st_size == part["bytes"] and sha(path) == part["sha256"], "Split part byte/hash mismatch")
            with path.open("rb") as stream:
                for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                    combined.update(chunk)
                    byte_count += len(chunk)
        require(byte_count == expected["bytes"] and combined.hexdigest() == expected["sha256"], "Split reassembly differs from original archive")
        joined[kind] = dict(status="PASS", parts=len(parts), sha256=combined.hexdigest(), bytes=byte_count)
    return dict(archives=verified, split_reassembly=joined, extraction_session=str(session))
