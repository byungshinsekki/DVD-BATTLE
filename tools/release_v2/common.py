"""Explicit checks, isolated bounded processes, and stable provenance."""
from __future__ import annotations
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time
import config
import process_control

process_pool = process_control.process_pool

PROBLEMS = re.compile(r"SCRIPT ERROR|Parse Error|^ERROR:|WARNING:.*\.gd|\.gd.*WARNING:", re.MULTILINE)

def require(condition, message):
    if not condition:
        raise RuntimeError(message)

def sha(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()

def digest(data):
    return hashlib.sha256(json.dumps(data, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")).hexdigest()

def write_json(path, data):
    atomic_bytes(path, (json.dumps(data, ensure_ascii=False, indent=2) + "\n").encode("utf-8"))

def safe_write_path(path):
    """Reject legacy spelling and filesystem redirection before any write."""
    original = Path(path).absolute()
    resolved = original.resolve()
    for candidate in (original, resolved):
        require(not any(re.match(r"DVD_BATTLE_1\.", p, re.I) for p in candidate.parts), "Legacy release paths are read-only")
    for candidate in (original, *original.parents):
        require(not candidate.is_symlink() and not (hasattr(candidate, "is_junction") and candidate.is_junction()), "Output traverses a symlink/junction: " + str(candidate))
    return resolved

def atomic_bytes(path, payload):
    path = safe_write_path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, name = tempfile.mkstemp(prefix="." + path.name + ".", suffix=".tmp", dir=path.parent)
    temporary = Path(name)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(payload)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if temporary.exists():
            temporary.unlink()

def atomic_copy(source, destination):
    destination = safe_write_path(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    descriptor, name = tempfile.mkstemp(prefix="." + destination.name + ".", suffix=".tmp", dir=destination.parent)
    temporary = Path(name)
    try:
        with os.fdopen(descriptor, "wb") as output, Path(source).open("rb") as stream:
            shutil.copyfileobj(stream, output, 1024 * 1024)
            output.flush()
            os.fsync(output.fileno())
        shutil.copystat(source, temporary)
        os.replace(temporary, destination)
    finally:
        if temporary.exists():
            temporary.unlink()

def within(path, parent):
    path, parent = Path(path).resolve(), Path(parent).resolve()
    return path == parent or parent in path.parents

def guard_output(path, final=False):
    path = safe_write_path(path)
    root = Path(config.RELEASE if final else config.SCRATCH).resolve()
    require(within(path, root) and (final or path != root), f"Output must be {'inside' if final else 'a dedicated child of'} {root}")
    return path

def run(command, log, profile, timeout=900, cwd=None, check=True):
    """Always stop only this command's PID tree. No shell interpolation."""
    require(0 < timeout <= 900, "Timeout must be <=900 seconds")
    profile = safe_write_path(profile)
    require(within(profile, config.SCRATCH) and profile != config.SCRATCH.resolve(), "Process profile must be a dedicated child of scratch")
    log = safe_write_path(log)
    log.parent.mkdir(parents=True, exist_ok=True)
    profile.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env.update(APPDATA=str(safe_write_path(profile / "Roaming")), LOCALAPPDATA=str(safe_write_path(profile / "Local")), PYTHONUTF8="1")
    for key in ("APPDATA", "LOCALAPPDATA"):
        Path(env[key]).mkdir(parents=True, exist_ok=True)
    start = time.monotonic()
    timeout_hit = False
    child = None
    pending = None
    termination = None
    code = 125
    # Replace an existing file before opening it, so a hardlink cannot redirect
    # process output into a protected file with a different pathname.
    atomic_bytes(log, b"")
    with log.open("wb") as stream:
        try:
            child = process_control.spawn([str(x) for x in command], cwd=cwd, env=env, stdin=subprocess.DEVNULL,
                                          stdout=stream, stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0,
                                          start_new_session=os.name != "nt")
            code = child.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            timeout_hit = True
            code = 124
        except BaseException as exc:
            pending = exc
            code = 130 if isinstance(exc, KeyboardInterrupt) else 125
        finally:
            if child is not None:
                if child.poll() is None:termination = process_control.cleanup(child)
                process_control.release(child)
    if os.name == "nt" and code > 0x7fffffff:
        code -= 0x100000000
    text = log.read_text(encoding="utf-8", errors="replace")
    errors = [line for line in text.splitlines() if PROBLEMS.search(line)]
    cleanup_errors = termination['errors'] if termination else []
    cancelled = process_control.STOP.is_set()
    result = dict(command=[str(x) for x in command], pid=child.pid if child else None, code=code, timeout=timeout_hit,
                  seconds=round(time.monotonic()-start, 3), log=str(log), problems=errors,
                  appdata=env["APPDATA"], localappdata=env["LOCALAPPDATA"], termination=termination, cleanup_errors=cleanup_errors,
                  cancelled=cancelled, interrupted=isinstance(pending, KeyboardInterrupt), exception=repr(pending) if pending else None,
                  status="PASS" if code == 0 and not errors and not cleanup_errors and not cancelled and pending is None else "FAIL")
    write_json(log.with_suffix(log.suffix + ".process.json"), result)
    if pending is not None:
        if cleanup_errors:pending.add_note('Cleanup also failed: '+repr(cleanup_errors))
        raise pending
    if check:
        require(result["status"] == "PASS", f"Process failed: {log}; exit={code}; problems={errors[:3]}")
    return result

def import_project(project, logs, profile):
    attempts = []
    for n in range(3):
        result = run([config.GODOT, "--headless", "--path", project, "--editor", "--quit"],
                     Path(logs) / f"import_{n+1}.log", profile, check=False)
        attempts.append(result)
        if result["code"] != -1073741819:
            break
    require(attempts[-1]["status"] == "PASS", f"Import failed: {attempts[-1]['log']}")
    return attempts

def git(project, *args):
    value = subprocess.check_output(["git", "-C", str(project), *args], timeout=30, text=True, encoding="utf-8",
                                    creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
    return value if "-z" in args else value.strip()

def runtime_hashes(project):
    project = Path(project)
    paths = [project / p for p in ("project.godot", "export_presets.cfg", "icon.svg", "icon.ico") if (project / p).is_file()]
    # .uid and .import are source inputs too: resource references and importer
    # options (including font fallbacks) can change the exported runtime.
    paths += [p for folder in ("scripts", "scenes", "shaders", "assets") for p in (project / folder).rglob("*") if p.is_file()]
    return {p.relative_to(project).as_posix(): sha(p) for p in sorted(paths)}

def verification_hashes(project):
    paths = [p for folder in ("tests", "tools") for p in (Path(project) / folder).rglob("*")
             if p.is_file() and p.suffix in (".gd", ".tscn", ".py", ".ps1", ".txt", ".md") and "__pycache__" not in p.parts]
    return {p.relative_to(project).as_posix(): sha(p) for p in sorted(paths)}

def discover_tests(project):
    root = Path(project) / "tests"
    scenes = sorted(p.stem for p in root.glob("*.tscn"))
    return {"headless": sorted(p.stem for p in root.glob("*.gd") if p.stem not in scenes), "rendered": scenes}

def copy_project(project, destination, fresh=False):
    """Copy only source assets; delete stale files only inside verified QA/scratch."""
    destination = safe_write_path(destination)
    project = Path(project).resolve()
    qa_root = Path(config.QA).resolve().parents[1]
    require(any(within(destination, root) and destination != root.resolve() for root in (qa_root, config.SCRATCH)), "Unsafe QA destination")
    require(not within(destination, project) and not within(project, destination), "QA and source trees must be disjoint")
    source_paths = [p for p in Path(project).rglob("*") if p.is_file() and not any(v in config.EXCLUDED_PARTS for v in p.relative_to(project).parts)
                    and not p.relative_to(project).as_posix().startswith("reports/")
                    and p.name not in ("AGENTS.md", "CODEX_WORK_ORDER_V2.md")]
    expected = {p.relative_to(project).as_posix() for p in source_paths}
    for source in source_paths:
        require(within(source, project) and not source.is_symlink(), "Source file escapes project or is a symlink: " + str(source))
        safe_write_path(source)  # Also reject redirecting ancestor directories.
    destination.mkdir(parents=True, exist_ok=True)
    # Reject redirecting existing directories before removing/copying any file.
    for old in destination.rglob("*"):
        safe_write_path(old)
    for old in destination.rglob("*"):
        if not old.is_file():
            continue
        rel = old.relative_to(destination).as_posix()
        if rel.startswith(".godot/") and not fresh:
            continue
        if rel not in expected:
            require(within(old, destination), "Unsafe stale-file removal")
            old.unlink()
    for src in source_paths:
        target = safe_write_path(destination / src.relative_to(project))
        target.parent.mkdir(parents=True, exist_ok=True)
        atomic_copy(src, target)
    if fresh and (destination / ".godot").exists():
        cache = (destination / ".godot").resolve()
        require(within(cache, destination) and cache != destination, "Unsafe cache target")
        shutil.rmtree(cache)
    pg = destination / "project.godot"
    text = pg.read_text(encoding="utf-8")
    text, count = re.subn(r'config/custom_user_dir_name="[^"]*"', f'config/custom_user_dir_name="{config.QA_PROFILE}"', text)
    require(count == 1, "Expected custom profile setting")
    atomic_bytes(pg, text.replace("\r\n", "\n").encode("utf-8"))
    atomic_bytes(destination / "reports/.gdignore", b"")
    return dict(destination=str(destination), source_files=len(source_paths), fresh=fresh)

def profile_inventory(appdata, names):
    result = {}
    names = sorted(set(names) | {p.name for p in Path(appdata).glob("DVD_BATTLE_*") if p.is_dir()})
    for name in names:
        folder = Path(appdata) / name
        result[name] = {"exists": folder.exists(), "files": {p.relative_to(folder).as_posix(): {"bytes": p.stat().st_size, "sha256": sha(p)}
                        for p in sorted(folder.rglob("*")) if p.is_file()} if folder.exists() else {},
                        "directories": sorted(p.relative_to(folder).as_posix() for p in folder.rglob("*") if p.is_dir()) if folder.exists() else []}
    return result

def legacy_inventory(parent, include_release=True):
    result = {}
    protected = sorted(Path(parent).glob("DVD_BATTLE_1.*"))
    if include_release:
        protected.append(Path(parent) / config.RELEASE.name)
    for path in protected:
        entries = [path] if path.is_file() else [p for p in path.rglob("*") if p.is_file()]
        result[path.name] = {"exists": path.exists(), "files": {p.relative_to(parent).as_posix(): [p.stat().st_size, p.stat().st_mtime_ns, sha(p)] for p in entries},
                             "directories": sorted(p.relative_to(path).as_posix() for p in path.rglob("*") if p.is_dir()) if path.is_dir() else []}
    return result
